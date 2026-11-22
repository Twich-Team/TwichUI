dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Exercise loot rule artwork persistence and the real shared picker with stand-in frames.

local made = 0
local created = {}
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  created[#created + 1] = f
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
    SetEnabled = function(s, v) s.enabled = v and true or false end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function(s) return unpack(s.font or { "Fonts\\FRIZQT__.TTF", 12, "" }) end,
    SetFont = function(s, file, size, flags) s.font = { file, size, flags }; return true end,
    SetScrollChild = function(s, child) s.child = child end,
    GetScrollChild = function(s) return s.child end,
    SetVerticalScroll = function(s, value) s.scroll = value end,
    GetVerticalScroll = function(s) return s.scroll or 0 end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetScale = function(s, v) s.scale = v end,
    SetTexture = function(s, t) s.texture = t; return true end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
    GetThumbTexture = function(s) s.thumbTex = s.thumbTex or Fake("Texture", s) return s.thumbTex end,
    CreateAnimationGroup = function(s)
      local g = Fake("AnimationGroup", s)
      g.Play = function(self) self.playing = true end
      g.Stop = function(self) self.playing = false end
      g.CreateAnimation = function() return Fake("Animation", g) end
      return g
    end,
  }
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local EQUIP = {}
local ITEMS = { [1201] = { "Dull Heater Shield", 4, 6, "INVTYPE_SHIELD" }, [6948] = { "Hearthstone", 15, 0, "" }, [2139] = { "Dirk", 2, 7, "INVTYPE_WEAPONOFFHAND" } }
local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.UIParent.w, c.UIParent.h = 1024, 768
  c.GameTooltip = Fake("GameTooltip")
  c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemArmorSubclass = { Shield = 6 }, ItemWeaponSubclass = { Fishingpole = 20 } }
  c.C_Item = {
    GetItemInfoInstant = function(id) local it = ITEMS[id] if it then return id, "", "", it[4], 1000 + id, it[2], it[3] end end,
    GetItemIconByID = function(id) if ITEMS[id] then return 1000 + id end end,
    GetItemNameByID = function(id) if ITEMS[id] then return ITEMS[id][1] end end,
    GetItemInfo = function(id) if ITEMS[id] then return ITEMS[id][1] end end,
    RequestLoadItemDataByID = function() end,
    GetItemSpell = function() return nil end, GetItemCount = function() return 0 end,
  }
  c.GetInventoryItemID = function(_, slot) return EQUIP[slot] end
  c.UnitClassBase = function() return "WARRIOR" end
  c.UnitIsGhost = function() return false end
  c.GetCursorInfo = function() return nil end
  c.ClearCursor = function() end
end



local function LoadLoot(c)
    World(c)
    for _, name in ipairs({ "Rules", "Config", "Roll", "Auto", "Blizzard", "Cards", "Victory", "Main" }) do
        local chunk = assert(loadfile(ROOT .. "loot/" .. name .. ".lua")); setfenv(chunk, c); chunk()
    end
end
local c = SettingsClient({ name = "Rich", beforeInit = LoadLoot })
local R, saved = c.TwichUI, c.TwichUIDB
local LR, P, picker = R.LootRolls, R.LootRulesPage, R.SettingsArtworkPicker
R.SettingsUI.IsPageActive = function(key) return key == "lootRules" end
local _, id = LR.Create("greenGear")
local frame = P.Frame(); frame:Show(); P.Select(id); P.Refresh()
local refs = { {kind="art",id="shield"}, {kind="icon",id="auctionHouse"}, {kind="item",id=6948}, {kind="art",id="unavailable-art"} }
for _, ref in ipairs(refs) do
    assert(LR.SetArtwork(id, ref)); local v = LR.Rule(id); assert(v.artwork.kind == ref.kind and v.artwork.id == ref.id)
    ref.id = "mutated"; assert(LR.Rule(id).artwork.id ~= "mutated")
    v.artwork.id = "changed"; assert(LR.Rule(id).artwork.id ~= "changed")
end
local before = LR.Rule(id).artwork.id
assert(not LR.SetArtwork(id, {kind="item",id=0/0})); assert(not LR.SetArtwork(id, {kind="art",id="bad/path"})); assert(LR.Rule(id).artwork.id == before)
local _, copy = LR.Duplicate(id); assert(LR.Rule(copy).artwork.id == before)
local original, duplicate
for _, r in ipairs(LR.Active()) do if r.id == id then original = r elseif r.id == copy then duplicate = r end end
assert(original.artwork ~= duplicate.artwork); duplicate.artwork.id = "changed"; assert(original.artwork.id == before)
local beforeDecision = R.LootRules.Decide({ original }, {quality=2, class=4}, {}).status
assert(LR.SetArtwork(id, {kind="icon",id="auctionHouse"})); P.Select(id); P.Refresh()
assert(R.LootRules.Decide({ original }, {quality=2, class=4}, {}).status == beforeDecision)
assert(P.ChooseArtwork()); picker.TakeItem("6948"); assert(LR.Rule(id).artwork.kind == "icon"); picker.Close(frame); assert(LR.Rule(id).artwork.kind == "icon")
assert(P.ChooseArtwork()); picker.TakeItem("6948"); assert(picker.Apply(frame)); assert(LR.Rule(id).artwork.kind == "item" and LR.Rule(id).artwork.id == 6948)
assert(P.ChooseArtwork()); picker.Frame().automatic.scripts.OnClick(picker.Frame().automatic); picker.Close(frame); assert(LR.Rule(id).artwork.kind == "item")
assert(P.ChooseArtwork()); picker.Frame().automatic.scripts.OnClick(picker.Frame().automatic); assert(picker.Apply(frame)); assert(LR.Rule(id).artwork == nil)
assert(LR.SetArtwork(id, {kind="art",id="unavailable-art"})); P.Refresh()
assert(frame.artStatus:IsShown() and frame.artStatus:GetText():find("unavailable", 1, true)); assert(P.Parts().rows[1].artUnavailable)
assert(P.Parts().rows[1].twichuiTip.body():find("Selected icon unavailable", 1, true))
assert(LR.RemoveCondition(id, 1)); assert(LR.RemoveCondition(id, 1)); P.Refresh()
assert(P.Parts().rows[1].state:GetText():find("Greed", 1, true) and P.Parts().rows[1].state:GetText():find("Needs attention", 1, true))
assert(P.ChooseArtwork()); LR.SetAction(id, "pass"); assert(not picker.Shown()); assert(LR.Rule(id).artwork.id == "unavailable-art")
local realOpen, staleApply = picker.Open
picker.Open = function(owner, opts) staleApply = opts.OnApply; return realOpen(owner, opts) end
assert(P.ChooseArtwork()); picker.Open = realOpen
assert(R.Profiles.Duplicate("Loot copy")); assert(not picker.Shown()); assert(LR.Rule(id).artwork.id == "unavailable-art")
assert(not staleApply({kind="item", id=6948})); assert(LR.Rule(id).artwork.id == "unavailable-art")
assert(P.ChooseArtwork()); P.Select(copy); assert(not picker.Shown())
P.Select(id); assert(P.ChooseArtwork()); LR.Delete(id); assert(not picker.Shown())
print("PASSED")
