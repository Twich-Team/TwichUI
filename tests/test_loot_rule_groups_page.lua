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

-- The Loot rules page with and / or blocks: the real page over stand-in frames. Clicks go through each control's own OnClick, so what
-- is checked is what a player's click does to the saved rule and to what the page then shows.
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local R = c.TwichUI
local LR, P = R.LootRolls, R.LootRulesPage
R.SettingsUI.IsPageActive = function(key) return key == "lootRules" end
local frame = P.Frame(); frame:Show()
local function Click(b) assert(b.scripts.OnClick, "no OnClick"); b.scripts.OnClick(b) end
local function X(frm) local p = frm.points[#frm.points]; return p and p[4] end
local function Y(frm) local p = frm.points[#frm.points]; return p and -p[5] end

local _, id = LR.Create("blank")
LR.RemoveCondition(id, 1); LR.SetAction(id, "greed")
P.Select(id); P.Refresh()
local parts = P.Parts()
Check(not (parts.groups[1] and parts.groups[1].frame:IsShown()), "a rule with no group shows no block")

-- add a block with the page's own button
Click(frame.addGroup); P.Refresh()
local rule = LR.Rule(id)
Check(rule.conditions[1] and rule.conditions[1].type == "group", "the Add and/or block button adds a block to the rule")
local g = parts.groups[1]
Check(g.frame:IsShown() and rule.conditions[1].match == "any", "the block is shown, and starts as 'any' inside an 'all' rule")
Check(parts.groups[1].frame.shown and #parts.groups == 1, "one block frame")
Check(rule.incomplete and rule.incomplete:find("Group 1", 1, true), "an empty block leaves the rule unfinished")
local emptyHint
for _, t in ipairs(parts.hints) do if t:IsShown() then emptyHint = t:GetText() end end
Check(emptyHint and emptyHint:find("Empty", 1, true), "an empty block says it is empty and what to do")
Check(P.Parts().rows[1].state:GetText():find("Needs attention", 1, true), "and the list says the rule needs attention")

-- conditions inside the block
LR.AddCondition(id, "quality", { 1 }); LR.AddCondition(id, "quality", { 1 }); LR.AddCondition(id, "class")
LR.SetCondition(id, { 1, 1 }, { value = 3 }); LR.SetCondition(id, { 1, 2 }, { value = 4 })
P.Refresh()
Check(LR.Rule(id).incomplete == nil, "the rule is finished once the block has conditions")
Check(parts.conds[1].frame:IsShown() and parts.conds[2].frame:IsShown() and parts.conds[3].frame:IsShown() and not (parts.conds[4] and parts.conds[4].frame:IsShown()),
  "three condition rows are shown: two in the block, one beside it")
Check(parts.conds[1].path[1] == 1 and parts.conds[1].path[2] == 1 and parts.conds[2].path[2] == 2 and #parts.conds[3].path == 1 and parts.conds[3].path[1] == 2,
  "each row knows its path")
Check(X(parts.conds[1].frame) > X(parts.conds[3].frame) and X(parts.conds[2].frame) == X(parts.conds[1].frame), "conditions in the block are indented under it")
Check(X(g.frame) < X(parts.conds[1].frame) and Y(g.frame) < Y(parts.conds[1].frame) and Y(parts.conds[1].frame) < Y(parts.conds[2].frame) and Y(parts.conds[2].frame) < Y(parts.conds[3].frame),
  "the block's header is above its conditions, which are above the condition after the block")
Check(parts.seps[1] and parts.seps[1]:GetText() == "or" and parts.seps[1]:IsShown(), "'or' is written between the block's conditions")
Check(parts.seps[2] and parts.seps[2]:GetText() == "and", "and 'and' between the block and what follows (the rule is 'all')")

-- the block's own all / any
Click(g.all); P.Refresh()
Check(LR.Rule(id).conditions[1].match == "all" and parts.seps[1]:GetText() == "and", "All: the block and its separator say all")
Click(g.any); P.Refresh()
Check(LR.Rule(id).conditions[1].match == "any" and parts.seps[1]:GetText() == "or", "Any: back")
-- the rule's own all / any, with the page's own buttons
Click(frame.matchAny); P.Refresh()
Check(LR.Rule(id).match == "any" and parts.seps[2]:GetText() == "or", "the rule's own Any of these changes the separator after the block")
Click(frame.matchAll); P.Refresh()

-- the limits show on the buttons
Check(g.addGroup.enabled and g.addCond.enabled and frame.addGroup.enabled and frame.addCond.enabled, "everything may still be added")
Click(g.addGroup); P.Refresh()
Check(LR.Rule(id).conditions[1].conditions[3] and LR.Rule(id).conditions[1].conditions[3].type == "group" and LR.Rule(id).conditions[1].conditions[3].match == "all", "a block inside the block starts as the opposite")
Check(parts.groups[2] and parts.groups[2].frame:IsShown() and X(parts.groups[2].frame) > X(g.frame), "and is indented further")
Check(not parts.groups[2].addGroup.enabled, "a block at the deepest level cannot hold another")
Check(g.addGroup.enabled, "while the outer block can still take blocks beside it")
Click(frame.addGroup); Click(frame.addGroup); P.Refresh()
Check(LR.Rule(id).counts.groups == 4 and not frame.addGroup.enabled, "at the most blocks, the Add block button is off")
Check(LR.Rule(id).conditions[1].conditions[3].conditions[1] == nil and LR.Rule(id).incomplete ~= nil, "empty blocks leave the rule unfinished")

-- removing a block removes what is in it, and its frames are hidden
local function GroupAt(path)
  for _, gr in ipairs(parts.groups) do
    if gr.frame:IsShown() and gr.path and #gr.path == #path then
      local same = true
      for i, k in ipairs(path) do if gr.path[i] ~= k then same = false end end
      if same then return gr end
    end
  end
end
Click(GroupAt({ 4 }).remove); P.Refresh()
Click(GroupAt({ 3 }).remove); P.Refresh()
Click(GroupAt({ 1, 3 }).remove); P.Refresh()
Check(LR.Rule(id).counts.groups == 1 and #LR.Rule(id).conditions[1].conditions == 2, "removing the inner blocks leaves the first with its two conditions")
local shown = 0
for _, gr in ipairs(parts.groups) do if gr.frame:IsShown() then shown = shown + 1 end end
Check(shown == 1, "only one block frame is shown")
Click(parts.conds[1].remove); P.Refresh()
Check(#LR.Rule(id).conditions[1].conditions == 1 and LR.Rule(id).conditions[1].conditions[1].value == 4, "the remove button of a condition in a block removes that condition")
Click(g.remove); P.Refresh()
Check(#LR.Rule(id).conditions == 1 and LR.Rule(id).conditions[1].type == "class" and not g.frame:IsShown(), "removing the block removes everything in it")
Check(not (parts.conds[2] and parts.conds[2].frame:IsShown()), "and the rows that were in it are hidden")

-- a different rule shows its own blocks; no rule shows none
local _, other = LR.Create("greenGear")
P.Select(other); P.Refresh()
Check(not g.frame:IsShown(), "a rule with no block shows no block frame")
P.Select(id); P.Refresh()

-- the roll and card display choices (the settings' segments): each click saves exactly its own choice
for _, key in ipairs({ "need", "greed", "pass", "none" }) do
  Click(frame.actions[key]); P.Refresh()
  Check(LR.Rule(id).action == key, "the " .. key .. " roll choice saves " .. key)
end
for _, key in ipairs({ "expanded", "collapsed", "none" }) do
  Click(frame.displays[key]); P.Refresh()
  Check(LR.Rule(id).display == key, "the " .. key .. " card display choice saves " .. key)
end
Check(frame.actions.pass:IsShown() and frame.displays.collapsed:IsShown() and frame.actions.pass.w == frame.actions.need.w, "the choices are laid out at one width")

if failures > 0 then print(failures .. " failure(s)") os.exit(1) end
print("PASSED")
