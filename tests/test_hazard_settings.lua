dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Hazard alerts in the settings window and in the saved settings the window reads:
--   * the page: where it sits, its switch (off by default), rows that read and write through the feature's own
--     Get/Set, rows greyed out under the switch with a reason, the sound tests, the standalone GTFO notice, Reset;
--   * the Rules tab: adding by typing, what is refused and why, the three things kept apart in the hint (the rule, the
--     game knowing the spell, the aura happening), editing, copying, removing, nothing made again on a redraw;
--   * nothing here registers a sound by itself, and the preview registers nothing.
-- Stand-in frames keep their scripts, text, focus and shown state; nothing here is the game.

local made = 0
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, scroll = 0, events = {}, children = {} }
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
    SetEnabled = function(s, v) s.enabled = v and true or false; Fire(s, v and "OnEnable" or "OnDisable") end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end,
    GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function(s) return math.max(0, (s.child and s.child.h or 0) - s.h) end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetTexture = function(s, t) s.texture = t end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
  }
  if kind == "ScrollFrame" then f.ScrollBar = Fake("Slider", f); f.ScrollBar.ThumbTexture = Fake("Texture", f.ScrollBar) end
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end



local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.GameTooltip = Fake("GameTooltip")
  c.Enum = { UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 } }
  c.REGISTERED, c.PLAYED = 0, {}
  c.C_UnitAuras = { AddAuraSound = function() c.REGISTERED = c.REGISTERED + 1; return c.REGISTERED end, RemoveAuraSound = function() end }
  c.PlaySoundFile = function(path, channel) c.PLAYED[#c.PLAYED + 1] = { path, channel }; return true end
  c.C_Spell = { GetSpellName = function(id) return ({ [1000] = "Test Fire" })[id] end }
end

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c, S = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
local HZ, A, K = R.Hazard, R.HazardAlerts, S.K
local function Flush() for _ = 1, 4 do FlushTimers() end end

---------------------------------------------------------------------------
-- 1. The page and its rows
---------------------------------------------------------------------------
local page, tab
for _, p in ipairs(S.pages) do
  if p.key == "hazard" then page = p elseif p.key == "hazardRules" then tab = p end
end
Check(page and page.group == "everyday" and page.kind == "page" and page.name == "Hazard alerts", "a page of its own under Everyday")
Check(tab and tab.parent == "Hazard alerts" and tab.kind == "hosted", "the rules are a tab of it")
local sw = S.variables.TWICHUI_hazardAlerts
Check(sw and sw:GetValue() == false and sw:GetDefaultValue() == false, "off by default")

local rows = {}
for _, row in ipairs(K.pages.hazard.rows) do
  if row.setting and row.setting.variable then rows[row.setting.variable] = row end
  if row.data and row.data.name then rows[row.data.name] = rows[row.data.name] or row end
end
for _, v in ipairs({ "HighOn", "LowOn", "FailOn", "HighSound", "LowSound", "FailSound", "Channel" }) do
  local key = v:sub(1, 1):lower() .. v:sub(2)
  Check(S.variables["TWICHUI_hazard" .. v], v .. " is a setting on the page")
  if S.variables["TWICHUI_hazard" .. v] then Check(S.variables["TWICHUI_hazard" .. v]:GetValue() == HZ.DEFAULTS[key], v .. " reads its default") end
end
Check(S.variables.TWICHUI_hazardFailOn and not S.variables.TWICHUI_hazardFriendlyOn, "no friendly-fire category is offered")

-- greyed out under the switch with a reason; the tests too
local high = rows.TWICHUI_hazardHighSound
Check(high and not high:Enabled() and high:DisabledReason() ~= nil, "sound choices wait for the switch")
Check(rows["Urgent danger test"] and not rows["Urgent danger test"]:Enabled(), "so do the tests")
sw:SetValue(true)
Check(R:Enabled("hazardAlerts") and high:Enabled() and rows["Urgent danger test"]:Enabled(), "on: they work")
Check(c.REGISTERED == 0, "turning it on with no rules registers nothing")

-- a row writes through the feature
S.variables.TWICHUI_hazardHighSound:SetValue("Light Fades")
Check(HZ.Get("highSound") == "Light Fades" and c.TwichUIDB.ui.hazard.highSound == "Light Fades", "a choice writes through Set")
S.variables.TWICHUI_hazardChannel:SetValue("Master")
Check(HZ.Get("channel") == "Master")
S.variables.TWICHUI_hazardLowOn:SetValue(false)
Check(HZ.Get("lowOn") == false, "a box")
Check(not rows["Warning test"]:Enabled(), "a category that is off greys its sound and test")
S.variables.TWICHUI_hazardLowOn:SetValue(true)

-- the sound choices include None and the registered sounds
local list = HZ and R:SoundChoices("Light Fades")
Check(#list >= 3, "TwichUI's sounds are offered")

-- the test buttons play the real sound once and register nothing
c.PLAYED = {}
rows["Urgent danger test"].click()
Check(#c.PLAYED == 1 and c.PLAYED[1][2] == "Master" and c.PLAYED[1][1]:find("Light_Fades", 1, true), "the test plays the chosen sound on the chosen channel")
S.variables.TWICHUI_hazardFailSound:SetValue("None")
rows["Failed mechanic test"].click()
Check(#c.PLAYED == 1 and c.REGISTERED == 0, "None plays nothing, and no test registers anything")

-- a note on the switch when standalone GTFO is loaded
local note = rows.TWICHUI_hazardAlerts.note
Check(note and note() == nil, "no notice without GTFO")
c.LOADED.GTFO = true
local text, tone = note()
Check(text and text:find("GTFO", 1, true) and text:find("two", 1, true) and tone == "warn", "a notice about duplicate sounds with GTFO loaded")
Check(HZ.Get("highOn") and R:Enabled("hazardAlerts"), "and nothing of ours was changed by it")
c.LOADED.GTFO = nil

-- the built-in list is empty and says so
local shipped = rows["Shipped rules"]
Check(shipped and shipped.value() == "None yet", "no built-in rule is claimed")

-- Reset: the page's own settings only
HZ.Add({ name = "Keep", spell = 1000, trigger = "applied", category = "high", throttle = 2 })
HZ.SetBuiltinEnabled("x.y", false)
local reset
for _, row in ipairs(K.pages.hazard.rows) do if row.reset and row.data.name == "Hazard alert settings" then reset = row end end
Check(reset, "a reset for the settings")
S.ClickReset(reset)
Check(HZ.Get("highSound") == HZ.DEFAULTS.highSound and HZ.Get("channel") == "SFX" and HZ.Get("failSound") == HZ.DEFAULTS.failSound, "the settings are back")
Check(HZ.Count() == 1 and HZ.IsBuiltinOff("x.y") and R:Enabled("hazardAlerts"), "the rules, the built-in choices and the switch are kept")
HZ.ClearCustom(); HZ.ResetBuiltin()

---------------------------------------------------------------------------
-- 2. The Rules tab
---------------------------------------------------------------------------
local P = R.HazardRulesPage
local f = P.Frame()
Check(P.Frame() == f, "one frame")
f:Hide(); f:Show()   -- built the first time it is shown
Check(f.empty and f.empty.shown and f.count.text == "0 of " .. HZ.MAX_CUSTOM, "an empty list says what it is for")
Check(f.examples.shown and not f.spell.shown, "the editor is closed until asked for")

local function RowFor(id)
  for _, ch in ipairs(f.content.children) do
    if ch.test and ch.rule and ch.rule.id == id and ch.shown then return ch end
  end
end
local function Rows()
  local n = 0
  for _, ch in ipairs(f.content.children) do if ch.test and ch.shown then n = n + 1 end end
  return n
end

-- adding by typing
f.add:Fire("OnClick")
Check(P.Open(nil) and f.spell.shown and f.editTitle.text == "New rule", "Add opens the editor")
f.name:SetText("Test fire")
f.spell:SetText("")
Check(not P.Save() and f.problem.text:find("spell ID", 1, true), "a missing spell ID is said")
f.spell:SetText("12x")
Check(not P.Save(), "not a number")
f.spell:SetText("1000")
f.spell:Fire("OnTextChanged")
Check(f.hint.text:find("The game knows spell 1000 as \"Test Fire\"", 1, true) and f.hint.text:find("cannot be checked", 1, true), "the hint names what the game knows and what it can't check: " .. f.hint.text)
f.spell:SetText("987654")
f.spell:Fire("OnTextChanged")
Check(f.hint.text:find("no name for spell 987654", 1, true) and f.hint.text:find("can still be saved", 1, true), "an uncached spell is explained, not refused")
f.name:SetText("")
Check(not P.Save() and f.problem.text:find("name", 1, true), "a name is needed")
f.name:SetText("Unknown thing")
local registeredBefore = c.REGISTERED
Check(P.Save() and HZ.Count() == 1 and HZ.List()[1].spell == 987654, "an uncached spell is saved")
Flush()
Check(Rows() == 1 and not f.spell.shown, "drawn, and the editor closes")
local id1 = HZ.List()[1].id
Check(c.REGISTERED == registeredBefore + 1, "with the alerts on, the saved rule is registered with the game once")

-- a duplicate and the hint about it
P.Open(nil)
f.name:SetText("Again"); f.spell:SetText("987654")
f.spell:Fire("OnTextChanged")
Check(f.hint.text:find("already listens", 1, true), "the hint names the rule it would double")
Check(not P.Save() and f.problem.text:find("already listens", 1, true) and HZ.Count() == 1, "refused as a duplicate")
P.Close()

-- the dropdown choices in the editor
P.Open(id1)
Check(f.spell.text == "987654" and f.name.text == "Unknown thing" and f.editTitle.text == "Edit rule", "Edit loads the rule")
f.trigger.onPick("stacks"); f.category.onPick("fail"); f.throttle.onPick(4)
Check(P.Save() and HZ.Find(id1).trigger == "stacks" and HZ.Find(id1).category == "fail" and HZ.Find(id1).throttle == 4, "edited")
Flush()

-- on/off, test, copy, remove
local row = RowFor(id1)
row.check:Fire("OnClick")
Check(HZ.Find(id1).enabled == false, "turned off from the list")
c.PLAYED = {}
row.test:Fire("OnClick")
Check(#c.PLAYED == 1 and c.PLAYED[1][1]:find("Single_Knell", 1, true), "Test plays that rule's category sound")
row.copy:Fire("OnClick")
Flush()
Check(HZ.Count() == 2 and Rows() == 2 and f.spell.shown, "Copy makes a switched-off copy and opens it")
local copy
for _, r in ipairs(HZ.List()) do if r.id ~= id1 then copy = r end end
Check(copy.enabled == false and copy.name:find("(copy)", 1, true) and copy.trigger == "applied", "the copy is off and takes another trigger")
P.Close()
RowFor(copy.id).remove:Fire("OnClick")
Flush()
Check(HZ.Count() == 1 and Rows() == 1 and P.lastSaid:find("Removed", 1, true), "removed")

-- an edit open while its rule goes away closes
P.Open(id1)
HZ.Remove(id1)
Flush()
Check(not f.spell.shown and P.lastTone == "warn", "the editor closes when its rule is gone")

-- the cap is said
for i = 1, HZ.MAX_CUSTOM do HZ.Add({ name = "r" .. i, spell = 4000 + i, trigger = "applied", category = "low", throttle = 1 }) end
Flush()
Check(f.add.enabled == false and f.count.text == HZ.MAX_CUSTOM .. " of " .. HZ.MAX_CUSTOM, "a full list disables Add")
HZ.ClearCustom()
Flush()

-- redraws make nothing new
local count = made
for _ = 1, 5 do P.Refresh() end
f:Hide(); f:Show(); Flush()
Check(made == count, "redrawing and reopening make no new frames")
Check(c.REGISTERED >= 1, "the controller did the registering")

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED")
