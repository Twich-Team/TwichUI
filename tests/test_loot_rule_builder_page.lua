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


-- The Loot rules builder in the Reminders builder's way: a palette, cards with a grip, boxes, a More menu, and drag and drop. The real page over
-- stand-in frames; clicks go through each control's own handler. Drag is checked in two halves: where the pointer lands (the registered drop
-- targets, with the stand-in frames given the bounds their placement says) and what a drop does (the same commit the pointer's drop makes).
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local R = c.TwichUI
local LR, P = R.LootRolls, R.LootRulesPage
local B = R.LootRulesBuilder
R.SettingsUI.IsPageActive = function(key) return key == "lootRules" end
local frame = P.Frame(); frame:Show()
local CURSOR = { 0, 0 }
c.GetCursorPosition = function() return CURSOR[1], CURSOR[2] end
local function Click(b) assert(b.scripts.OnClick, "no OnClick"); b.scripts.OnClick(b) end
local function X(f) local p = f.points[#f.points]; return p and p[4] end
local function Y(f) local p = f.points[#f.points]; return p and -p[5] end
local function Kinds(list) local out = {} for i, x in ipairs(list) do out[i] = x.type == "group" and ("[" .. Kinds(x.conditions) .. "]") or (x.type == "quality" and ("q" .. x.value) or x.type) end return table.concat(out, ",") end
local id
local function Top() return Kinds(LR.Rule(id).conditions) end
local function Fresh()
  for _, r in ipairs(LR.List()) do LR.Delete(r.id) end
  local _, rid = LR.Create("blank")
  LR.RemoveCondition(rid, 1); LR.SetAction(rid, "greed")
  id = rid
  P.Select(id); P.Refresh()
end
local function Menu(path, value) B.MenuPick(path, value); P.Refresh() end
local function Choice(path, value)
  for _, ch in ipairs(B.MenuFor(path)) do if ch.value == value then return ch end end
end

Fresh()
local parts = P.Parts()
-- the palette: every kind, and the block
Check(#parts.palette == #R.LootRules.ORDER + 1, "the palette offers every kind of condition and the block")
for i, row in ipairs(parts.palette) do Check(row:IsShown(), "palette entry " .. i .. " is shown") end
local seen = {}
for _, row in ipairs(parts.palette) do seen[row.kind] = true end
for _, kind in ipairs(R.LootRules.ORDER) do Check(seen[kind], "the palette has " .. kind) end
Check(seen.block, "and the block")

-- clicking an entry adds it to the end of the rule
local function Entry(kind) for _, row in ipairs(parts.palette) do if row.kind == kind then return row end end end
Click(Entry("quality")); Click(Entry("class")); P.Refresh()
Check(Top() == "q2,class", "clicking a palette entry adds that condition at the end")
Click(Entry("block")); P.Refresh()
Check(LR.Rule(id).conditions[3] and LR.Rule(id).conditions[3].type == "group", "clicking the block entry adds a block")
Check(LR.Rule(id).incomplete and LR.Rule(id).incomplete:find("Group 3", 1, true), "an empty block leaves the rule unfinished")

-- the tree: the rule's box, cards, a box inside it
local top = parts.groups[1]
Check(top.box:IsShown() and not top.grip, "the rule has its own box, with no grip or More of its own")
Check(parts.conds[1]:IsShown() and parts.conds[2]:IsShown() and not (parts.conds[3] and parts.conds[3]:IsShown()), "two cards are shown")
Check(parts.groups[2].box:IsShown() and parts.groups[2].path[1] == 3, "the block is shown, knowing its path")
Check(parts.conds[1].grip:IsShown() and parts.groups[2].grip:IsShown() and parts.groups[2].fold:IsShown(), "cards and blocks have a grip, and a block folds")
Check(X(parts.groups[2].box) == X(parts.conds[1]) or X(parts.groups[2].box) ~= nil, "placed")

-- a condition into the block through its own button's menu path, then the box's All / Any
LR.AddCondition(id, "quality", { 3 }); LR.SetCondition(id, { 3, 1 }, { value = 4 }); LR.AddCondition(id, "bind", { 3 })
P.Refresh()
Check(LR.Rule(id).incomplete == nil, "the rule is finished once the block has conditions")
Check(parts.conds[3]:IsShown() and parts.conds[3].path[1] == 3 and parts.conds[3].path[2] == 1, "a card inside the block knows its path")
Check(X(parts.conds[3]) > X(parts.conds[1]), "and sits inside it, indented")
Check(Y(parts.groups[2].box) < Y(parts.conds[3]) and Y(parts.conds[3]) < Y(parts.conds[4]), "the block's header is above its cards")
local g2 = parts.groups[2]
Click(g2.segall); P.Refresh()
Check(LR.Rule(id).conditions[3].match == "all", "All saves for the block")
Click(g2.segany); P.Refresh()
Check(LR.Rule(id).conditions[3].match == "any", "Any saves for the block")
Click(top.segany); P.Refresh()
Check(LR.Rule(id).match == "any", "the rule's own Any saves for the rule")
Click(top.segall); P.Refresh()
Check(LR.Rule(id).match == "all" and LR.Rule(id).conditions[3].match == "any", "and All, leaving the block's choice alone")
Check(parts.seps[1] and parts.seps[1]:IsShown() and parts.seps[1]:GetText() == "and", "'and' between the rule's neighbours")

-- fold
Click(g2.fold); P.Refresh()
Check(B.Folded({ 3 }) and not parts.conds[3]:IsShown(), "folding a block hides its cards")
Check(g2.folded:IsShown() and g2.folded:GetText():find("Epic", 1, true), "and shows it in one line")
Click(g2.fold); P.Refresh()
Check(not B.Folded({ 3 }) and parts.conds[3]:IsShown(), "unfolding shows them again")

-- the More menu
local card1 = { 1 }
Check(Choice(card1, "dup") and not Choice(card1, "up") and Choice(card1, "down") and Choice(card1, "remove"), "the first card can duplicate, move down and remove, but not up")
Check(Choice({ 3, 1 }, "to:") and Choice({ 3, 1 }, "remove"), "a card in a block can move out to the rule")
local toBlock = Choice(card1, "to:3")
Check(toBlock and toBlock.label:find("any of", 1, true), "a card can move into a block, which the menu names by what it says")
Check(not Choice({ 3 }, "to:3"), "a block cannot move into itself")
Menu(card1, "dup")
Check(Top() == "q2,q2,class,[q4,bind]", "Duplicate copies the card right after it")
Menu({ 2 }, "down")
Check(Top() == "q2,class,q2,[q4,bind]", "Move down")
Menu({ 3 }, "up")
Check(Top() == "q2,q2,class,[q4,bind]", "Move up")
Menu({ 1 }, "to:4")
Check(Top() == "q2,class,[q4,bind,q2]", "Move into a block puts it at the end of the block")
Menu({ 3, 3 }, "to:")
Check(Top() == "q2,class,[q4,bind],q2", "Move out to the rule puts it at the end of the rule")
Menu({ 4 }, "remove")
Check(Top() == "q2,class,[q4,bind]", "Remove")
Menu({ 3 }, "dup")
Check(Top() == "q2,class,[q4,bind],[q4,bind]", "Duplicate on a block copies it with what is in it")
Menu({ 4 }, "remove")

-- right-click opens the same menu (the stand-in menu records that it was asked to open)
local opened
parts.conds[1].more.OpenMenu = function() opened = true end
parts.conds[1].scripts.OnClick(parts.conds[1], "RightButton")
Check(opened, "a right-click on a card opens its More menu")
parts.conds[1].scripts.OnClick(parts.conds[1], "LeftButton"); 

-- dragging: the grip starts a drag of that card or block
local started
Check(parts.conds[2].grip.scripts.OnDragStart, "a card's grip starts a drag")
parts.conds[2].grip.scripts.OnDragStart()
local drag = B.drag
local src = drag.source
Check(src and src.path and src.path[1] == 2 and src.raw and src.id == id, "the drag carries the card's path and rule")
drag:Cancel()

-- the pointer: give each stand-in frame the bounds its placement says, then ask where a point lands
local function Bound(f, w, h)
  local x, y = X(f) or 0, Y(f) or 0
  f.GetLeft = function() return x end; f.GetRight = function() return x + (f.w or w) end
  f.GetTop = function() return 5000 - y end; f.GetBottom = function() return 5000 - y - (f.h or h) end
end
local function GiveBounds()
  local e = frame.editor
  e.GetLeft = function() return -1000 end; e.GetRight = function() return 5000 end; e.GetTop = function() return 6000 end; e.GetBottom = function() return -1000 end
  for _, r in ipairs(drag.rows) do Bound(r.frame, 300, 58) end
  for _, gr in ipairs(drag.groups) do Bound(gr.frame, 300, 100) end
end
local function Land(source, f, where)
  GiveBounds()
  drag.source = source
  local l, r, b, t = f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop()
  local py = where == "top" and t - 2 or (where == "bottom" and b + 2 or (t + b) / 2)
  local drop = drag:Find((l + r) / 2, py)
  drag.source = nil
  return drop
end
Check(#drag.rows >= 4 and #drag.groups >= 2, "every card and box registers as a place to drop")
local row2 = nil
for _, r in ipairs(drag.rows) do if r.frame == parts.conds[2] then row2 = r end end
Check(row2 and #row2.parent == 0 and row2.index == 2, "a top-level card registers its list (the rule) and its place")
local inner
for _, r in ipairs(drag.rows) do if r.frame == parts.conds[3] then inner = r end end
Check(inner and #inner.parent == 1 and inner.parent[1] == 3 and inner.index == 1, "a card in a block registers that block as its list")

-- palette drag: a new condition dropped on the top half of the card lands before it, on the lower half after it
local pal = { id = id, rev = LR.Rev(), kind = "quality" }
local before = Land(pal, parts.conds[2], "top")
Check(before and before.index == 2 and not before.after, "dropping on the upper half of a card lands before it")
local after = Land(pal, parts.conds[2], "bottom")
Check(after and after.index == 3 and after.after, "and on the lower half after it")
local into = Land(pal, parts.conds[3], "bottom")
Check(into and #into.target.parent == 1 and into.index == 2, "on a card in a block lands in that block")
Check(B.DropPlace(pal, {}, 1) == 1 and B.DropPlace({ id = id, rev = LR.Rev() + 1, kind = "quality" }, {}, 1) == nil, "a drag from before the rule changed is refused")
-- drop it: the same commit the pointer makes
B.Commit(pal, {}, 2)
Check(Top() == "q2,q2,class,[q4,bind]", "dropping a palette condition adds it at that place")
B.Commit({ id = id, rev = LR.Rev(), kind = "block" }, { 4 }, 1)
Check(LR.Rule(id).conditions[4].conditions[1].type == "group", "dropping the block entry adds a block at that place in a block")
Menu({ 4, 1 }, "remove")
-- move by drag
local move = { id = id, rev = LR.Rev(), path = { 1 }, raw = true }
Check(B.DropPlace(move, { 4 }, 1) == 1, "an existing card may be dropped into a block")
Check(B.DropPlace(move, {}, 1) == nil and B.DropPlace(move, {}, 2) == nil, "but not where it already is")
B.Commit(move, { 4 }, 1)
Check(Top() == "q2,class,[q2,q4,bind]", "dropping a card into a block at its first place moves it there")
local blockMove = { id = id, rev = LR.Rev(), path = { 3 }, raw = true }
Check(B.DropPlace(blockMove, { 3 }, 1) == nil, "a block cannot be dropped into itself")
B.Commit(blockMove, {}, 1)
Check(Top() == "[q2,q4,bind],q2,class", "a block is moved to the front by dropping it there")
-- a real drag with the pointer: grip down, move over a place, let go (the virtual drag kit makes the drop)
do
  P.Refresh()
  local kind = Top()
  Check(kind == "[q2,q4,bind],q2,class", "the rule before the pointer drag")
  parts = P.Parts()
  local moving = parts.conds[#parts.conds]   -- find the card 'class' (last top-level card)
  for _, cd in ipairs(parts.conds) do if cd:IsShown() and cd.path and #cd.path == 1 and cd.path[1] == 3 then moving = cd end end
  moving.grip.scripts.OnDragStart()
  GiveBounds()
  local target
  for _, cd in ipairs(parts.conds) do if cd:IsShown() and cd.path and #cd.path == 2 and cd.path[1] == 1 and cd.path[2] == 1 then target = cd end end
  local l, r, b, t = target:GetLeft(), target:GetRight(), target:GetBottom(), target:GetTop()
  CURSOR[1], CURSOR[2] = (l + r) / 2, t - 2          -- the upper half of the first card in the block
  moving.grip.scripts.OnDragStop()
  P.Refresh()
  Check(Top() == "[class,q2,q4,bind],q2", "letting go over the upper half of a card in a block drops the dragged card before it")
  -- dropping on nothing changes nothing
  parts = P.Parts()
  local first = parts.conds[1]
  first.grip.scripts.OnDragStart(); GiveBounds()
  CURSOR[1], CURSOR[2] = -500, -500
  first.grip.scripts.OnDragStop(); P.Refresh()
  Check(Top() == "[class,q2,q4,bind],q2", "a drop on nothing changes nothing")
  Check(not R.MagicInventoryPage.Drag.Active(), "and the drag is over")
end

-- limits show up in the drop
Fresh()
for i = 1, R.LootRules.MAX_CONDITIONS do LR.AddCondition(id, "bind") end
P.Refresh()
Check(B.DropPlace({ id = id, rev = LR.Rev(), kind = "quality" }, {}, 1) == nil, "a new condition cannot be dropped when the rule is full")
Check(not Entry("quality"):IsEnabled(), "and the palette shows it as unavailable")
Check(Entry("block"):IsEnabled(), "while a block can still be added")
Fresh()
for i = 1, R.LootRules.MAX_GROUPS do LR.AddGroup(id) end
P.Refresh()
Check(B.DropPlace({ id = id, rev = LR.Rev(), kind = "block" }, {}, 1) == nil and not Entry("block"):IsEnabled(), "a block cannot be added past the limit")

-- the roll and card display choices still work
Fresh()
for _, key in ipairs({ "need", "greed", "pass", "none" }) do
  Click(frame.actions[key]); P.Refresh()
  Check(LR.Rule(id).action == key, "the " .. key .. " roll choice saves " .. key)
end
for _, key in ipairs({ "expanded", "collapsed", "none" }) do
  Click(frame.displays[key]); P.Refresh()
  Check(LR.Rule(id).display == key, "the " .. key .. " card display choice saves " .. key)
end

-- another rule, and no rule
local _, other = LR.Create("greenGear")
P.Select(other); P.Refresh()
Check(not parts.groups[2].box:IsShown() and parts.conds[1]:IsShown(), "another rule shows its own tree")
for _, r in ipairs(LR.List()) do LR.Delete(r.id) end
P.Select(nil); P.Refresh()
Check(not parts.conds[1]:IsShown() and not parts.groups[1].box:IsShown() and not parts.palette[1]:IsShown(), "no rule open shows nothing of the builder")

if failures > 0 then print(failures .. " failure(s)") os.exit(1) end
print("PASSED")
