dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Action bar glows in the settings window:
--   * the page: where it sits, its switch (on by default), rows that read and write through glows/Config.lua's Get/Set,
--     rows greyed out under the switch, Reset (what you added is kept);
--   * the Spells and looks tab: the kinds, each one's rows, the editor (a row's own look and the kind's defaults), the
--     sample that glows as it is set and stops when the page hides, adding by ID or link and what is refused, nothing
--     made again on a redraw.
-- Stand-in frames keep their scripts, text and shown state; nothing here is the game.

local made = 0
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 36, h = 36,
    text = "", enabled = true, focus = false, scroll = 0, events = {}, children = {}, level = 1 }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  f.Fire = Fire
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn; s.hooks[n] = nil end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    ClearAllPoints = function(s) s.points = {} end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
    GetText = function(s) return s.text end,
    GetStringHeight = function() return 12 end, GetStringWidth = function(s) return #s.text * 6 end,
    IsTruncated = function() return false end,
    SetEnabled = function(s, v) s.enabled = v and true or false end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true end,
    ClearFocus = function(s) s.focus = false end,
    HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end,
    GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function(s) return math.max(0, (s.child and s.child.h or 0) - s.h) end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetFrameLevel = function(s) return s.level end, SetFrameLevel = function(s, l) s.level = l end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetTexture = function(s, t) s.texture = t end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    UnregisterAllEvents = function(s) s.events = {} end, RegisterUnitEvent = function(s, e) s.events[e] = true end,
    IsEventRegistered = function(s, e) return s.events[e] == true end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    SetThumbTexture = function(s) s.thumb = s.thumb or Fake("Texture", s) end,
    GetThumbTexture = function(s) s.thumb = s.thumb or Fake("Texture", s); return s.thumb end,
    SetMinMaxValues = function(s, lo, hi) s.lo, s.hi = lo, hi end, GetMinMaxValues = function(s) return s.lo or 0, s.hi or 100 end,
    SetValue = function(s, v) s.value = v end, GetValue = function(s) return s.value or 0 end,
    CreateFontString = function(s) return Fake("FontString", s) end,
    CreateAnimationGroup = function(s)
      local g = Fake("AnimationGroup", s)
      g.CreateAnimation = function(self) return Fake("Animation", self) end
      g.Play = function(self) self.playing = true end
      g.Stop = function(self) self.playing = false end
      return g
    end,
  }
  if kind == "ScrollFrame" then f.ScrollBar = Fake("Slider", f); f.ScrollBar.ThumbTexture = Fake("Texture", f.ScrollBar) end
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local NAMES = { [12051] = "Evocation", [12043] = "Presence of Mind", [1459] = "Arcane Intellect", [116] = "Frostbolt" }
local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.GameTooltip = Fake("GameTooltip")
  c.C_Spell = { GetSpellName = function(id) return NAMES[id] end, GetSpellTexture = function(id) return 100 + id end,
    GetSpellCooldown = function() return { isEnabled = true, isActive = false } end, IsSpellUsable = function() return false, false end }
  c.C_SpellBook = { IsSpellKnown = function(id) return id == 12051 end }
  c.C_Item = { GetItemCount = function() return 0 end, GetItemNameByID = function(id) return id == 8079 and "Conjured Crystal Water" or nil end,
    GetItemInfoInstant = function(id) if id == 8079 then return id end end, GetItemIconByID = function() return 1 end }
  c.PlaySoundFile = function() return true end
end

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c, S = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
local BG, K, D = R.BarGlows, S.K, R.BarGlowDraw
local function Flush() for _ = 1, 4 do FlushTimers() end end

---------------------------------------------------------------------------
-- 1. The page and its rows
---------------------------------------------------------------------------
local page, tab
for _, p in ipairs(S.pages) do
  if p.key == "barGlows" then page = p elseif p.key == "barGlowsSpells" then tab = p end
end
Check(page and page.group == "class" and page.kind == "page" and page.name == "Action bar glows", "a page under Gear & class")
Check(tab and tab.parent == "Action bar glows" and tab.kind == "hosted", "Spells and looks is a tab of it")
local sw = S.variables.TWICHUI_barGlows
Check(sw and sw:GetValue() == true and sw:GetDefaultValue() == true, "on by default")

local rows = {}
for _, row in ipairs(K.pages.barGlows.rows) do
  if row.setting and row.setting.variable then rows[row.setting.variable] = row end
end
S.variables.TWICHUI_barGlowsQuietInTowns:SetValue(false)
Check(BG.Get("quietInTowns") == false and c.TwichUIDB.ui.barGlows.quietInTowns == false, "a box writes through Set")
S.variables.TWICHUI_barGlowsPartyGroupFrom:SetValue(4)
Check(BG.Get("partyGroupFrom") == 4, "a dropdown writes through Set")
S.variables.TWICHUI_barGlowsBar3On:SetValue(false)
Check(BG.BarOn("bar3") == false, "a bar turned off")
S.variables.TWICHUI_barGlowsBar2Faded:SetValue(true)
Check(BG.BarFaded("bar2") and rows.TWICHUI_barGlowsFadedOpacity:Enabled(), "a faded bar; its opacity can be set")
sw:SetValue(false)
Check(not rows.TWICHUI_barGlowsQuietInTowns:Enabled() and rows.TWICHUI_barGlowsQuietInTowns:DisabledReason() ~= nil, "greyed out while off, with a reason")
sw:SetValue(true)
-- Reset: the settings back; what you added kept
BG.Add({ kind = "lowStock", item = 8079 })
BG.SetSpellField("readyCooldown", "evocation", "color", "ff112233")
local reset
for _, row in ipairs(K.pages.barGlows.rows) do if row.reset then reset = row end end
Check(reset, "a reset")
S.ClickReset(reset)
Check(BG.Get("quietInTowns") == true and BG.Get("partyGroupFrom") == 2 and BG.BarOn("bar3") and not BG.BarFaded("bar2"), "the settings are back")
Check(BG.Style("readyCooldown", "evocation").color == BG.TYPE_DEFAULTS.readyCooldown.color, "and the looks")
Check(BG.FindAdded("lowStock", "i8079") ~= nil and R:Enabled("barGlows"), "what you added and the switch are kept")

---------------------------------------------------------------------------
-- 2. The Spells and looks tab
---------------------------------------------------------------------------
local P = R.BarGlowsSpellsPage
local f = P.Frame()
Check(P.Frame() == f, "one frame")
f:Hide(); f:Show()
Flush()
local function Shown()
  local list = {}
  for _, ch in ipairs(f.content.children) do if ch.data and ch.shown then list[#list + 1] = ch end end
  return list
end
local list = Shown()
Check(#list > 1 and list[1].data.defaults, "missing buffs: the defaults row first, then the spells")
-- another kind
f.kind.onPick("readyCooldown")
list = Shown()
local evo
for _, row in ipairs(list) do if row.data.key == "evocation" then evo = row end end
Check(evo and evo.name.text == "Evocation" and evo.data.known == true, "Evocation listed, learned")
local pom
for _, row in ipairs(list) do if row.data.key == "presenceOfMind" then pom = row end end
Check(pom and pom.data.known == false and pom.detail.text:find("not learned", 1, true), "a talent not learned: said so")
-- a row's on/off
evo.check:Fire("OnClick")
Flush()
Check(not BG.SpellEnabled("readyCooldown", "evocation"), "a row turned off")
evo.check:Fire("OnClick")
Flush()
Check(BG.SpellEnabled("readyCooldown", "evocation"), "and on")
-- the editor on a row
evo.look:Fire("OnClick")
Check(f.editTitle.shown and f.editTitle.text == "Look of Evocation", "Look opens the editor for that row")
Check(D.IsGlowing(f.sample), "the sample glows")
f.look.onPick("pixel")
f.color.SetValue(f.color, "ff00ff00")
Flush()
Check(BG.SpellField("readyCooldown", "evocation", "look") == "pixel" and BG.Style("readyCooldown", "evocation").look == "pixel", "a row's own look")
Check(BG.Style("readyCooldown", "berserking").look == BG.TYPE_DEFAULTS.readyCooldown.look, "only that row")
Check(f.thickness and f.look.value == "pixel", "the editor shows it")
f.reset:Fire("OnClick")
Flush()
Check(BG.SpellField("readyCooldown", "evocation", "look") == nil and not BG.SpellHasOwnLook("readyCooldown", "evocation"), "Use the defaults")
-- the defaults row
list = Shown()
list[1].look:Fire("OnClick")
Check(f.editTitle.text == "Defaults for ready cooldown", "the kind's defaults: " .. f.editTitle.text)
f.when.onPick("always")
Flush()
Check(BG.TypeField("readyCooldown", "when") == "always" and BG.Style("readyCooldown", "evocation").when == "always", "the kind's when reaches its rows")
local whenChoices = f.when.choices()
local town = false
for _, ch in ipairs(whenChoices) do if ch.value == "townAlert" then town = true end end
Check(not town, "Alert in town is not offered for a cooldown")
list[1].reset:Fire("OnClick")
Flush()
Check(BG.TypeField("readyCooldown", "when") == "inCombat", "the defaults reset")
-- nothing made again on a redraw
local before = made
P.Refresh(); P.Refresh()
Check(made == before, "a redraw makes nothing new: " .. (made - before))
-- hiding stops the sample
f:Hide()
Check(not D.IsGlowing(f.sample), "the sample stops when the page hides")
f:Show()
Flush()

---------------------------------------------------------------------------
-- 3. Adding
---------------------------------------------------------------------------
Check(P.ParseId("12051") == 12051 and select(2, P.ParseId("|cff71d5ff|Hspell:12051:0|h[Evocation]|h|r")) == "spell"
  and select(2, P.ParseId("|cffffffff|Hitem:8079::::|h[Water]|h|r")) == "item" and P.ParseId("abc") == nil, "an ID, a spell link, an item link")
f.addKind.onPick("proc")
f.addId:SetText("999999")
Check(not P.Add() and f.note.text:find("knows no spell", 1, true), "an unknown spell is refused")
f.addKind.onPick("readyCooldown")
f.addId:SetText("12051")
local ok, why = P.Add()
Check(not ok and why == "builtin" and f.note.text:find("already listed", 1, true), "a built-in spell is pointed to its row: " .. f.note.text)
f.addKind.onPick("proc")
f.addId:SetText("12051")
Check(P.Add() and BG.FindAdded("proc", "s12051"), "the same spell as another kind can be added")
BG.Remove("proc", "s12051")
f.addKind.onPick("lowStock")
Check(f.addAs.value == "item", "low stock takes items")
f.addId:SetText("8079")
ok, why = P.Add()
Check(not ok and why == "duplicate", "already added")
BG.Remove("lowStock", "i8079")
ok = P.Add()
Check(ok and BG.FindAdded("lowStock", "i8079") and f.kind.value == "lowStock", "added; the list shows its kind")
list = Shown()
local water
for _, row in ipairs(list) do if row.data.key == "i8079" then water = row end end
Check(water and water.remove.shown and water.detail.text:find("low below 20", 1, true), "its row: Remove, and its limit")
water.remove:Fire("OnClick")
Flush()
Check(BG.FindAdded("lowStock", "i8079") == nil, "removed")

if failures == 0 then print("PASSED") else print(failures .. " FAILED") os.exit(1) end
