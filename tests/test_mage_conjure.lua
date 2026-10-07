-- Mage Conjuring: the ranks match the Forever training data (levels and each rank needing the one
-- before); Mages only; the launcher made once with its text choice; the menu lists food and water
-- highest rank first, sets a secure spell only on learned ranks, and explains unlearned ones (the
-- level, the rank needed first, the trainer); it lives beside Mage Travel without either getting
-- in the other's way.
dofile(TESTS .. "harness.lua")

-- The ranks against What's Training?'s Forever data, as TwichUI carries it.
do
  local env = setmetatable({ TwichUI = {} }, { __index = _G })
  local chunk = assert(loadfile(ROOT .. "modules/TrainingData.lua")); setfenv(chunk, env); chunk("!!!TwichUI", {})
  local levels = env.TwichUI.TrainingData.MAGE()
  local data = {}
  for level, list in pairs(levels) do for _, e in ipairs(list) do data[e[1]] = { level = level, req = e.req, faction = e.faction } end end
  local menv = setmetatable({ TwichUI = { PATH = "", On = function() end, OnInit = function() end, TrainingData = env.TwichUI.TrainingData } }, { __index = _G })
  for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/MageConjure.lua" }) do
    local mchunk = assert(loadfile(ROOT .. f)); setfenv(mchunk, menv); mchunk("!!!TwichUI", {})
  end
  local M = menv.TwichUI.MageConjure
  for key, ranks in pairs(M.SPELLS) do
    assert(#ranks == 6, key .. ": six ranks")
    for i, id in ipairs(ranks) do
      local d = data[id]
      assert(d and not d.faction, id .. " is in the Forever training data, for both factions")
      assert(M.TrainedAt(id) == d.level, id .. " trained at the data's level")
      if i == 1 then assert(not d.req, id .. " is the first rank")
      else
        assert(d.req and #d.req == 1 and d.req[1] == ranks[i - 1], id .. " needs the rank before it")
        assert(d.level > data[ranks[i - 1]].level, id .. " comes later")
      end
    end
  end
  assert(M.TrainedAt(587) == 6 and M.TrainedAt(10145) == 52 and M.TrainedAt(5504) == 4 and M.TrainedAt(10139) == 50)
end

local c = MakeClient("Rich", { "!!!TwichUI" })
local frames = {}
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, attrs = {}, events = {} }
  table.insert(frames, o)
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
Methods = {
  Show = function(s) s.shown = true end,
  Hide = function(s) if s.shown then s.shown = false; if s.scripts.OnHide then s.scripts.OnHide(s) end end end,
  IsShown = function(s) return s.shown end,
  SetShown = function(s, v) s.shown = v and true or false end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end,
  SetAttribute = function(s, k, v) s.attrs[k] = v end,
  CreateTexture = function() return Fake("texture") end,
  CreateFontString = function() return Fake("font") end,
  SetText = function(s, v) s.text = v end,
  SetTexture = function(s, v) s.texture = v end,
  SetDesaturated = function(s, v) s.desaturated = v end,
  IsMouseOver = function(s) return s.mouse == true end,
}
c.CreateFrame = function(kind, name, parent, template)
  local f = Fake(kind); f.name, f.parent, f.template = name, parent, template; return f
end
c.UIParent = Fake("UIParent")
c.UISpecialFrames = {}
c.tinsert = table.insert
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
c.notices = {}
c.UIErrorsFrame = { AddMessage = function(_, text) table.insert(c.notices, text) end }
c.SHIFT = false
c.IsShiftKeyDown = function() return c.SHIFT end
c.UIParent.GetEffectiveScale = function() return 1 end
c.UIParent.GetWidth = function() return 1024 end
c.UIParent.GetHeight = function() return 768 end
local tip = { lines = {} }
function tip:SetOwner(o) self.owner = o; self.lines = {}; self.spell = nil end
function tip:IsOwned(o) return self.owner == o end
function tip:SetSpellByID(id) self.spell = id end
function tip:AddLine(t) table.insert(self.lines, t) end
function tip:AddDoubleLine(a, b) table.insert(self.lines, a .. ": " .. b) end
function tip:Hide() self.owner = nil end
tip.ClearAllPoints, tip.SetPoint, tip.Show = function() end, function() end, function() end
c.GameTooltip = tip

c.CLASS = "MAGE"
c.COMBAT = false
c.InCombatLockdown = function() return c.COMBAT end
c.UnitClass = function() return "Class", c.CLASS end
c.UnitFactionGroup = function() return "Horde", "Horde" end
c.UnitLevel = function() return 24 end
c.KNOWN = { [587] = true, [597] = true, [990] = true, [5504] = true, [5505] = true, [5506] = true }
local NAMES = {}
for _, id in ipairs({ 587, 597, 990, 6129, 10144, 10145 }) do NAMES[id] = "Conjure Food" end
for _, id in ipairs({ 5504, 5505, 5506, 6127, 10138, 10139 }) do NAMES[id] = "Conjure Water" end
local RANK = {}
for i, id in ipairs({ 587, 597, 990, 6129, 10144, 10145 }) do RANK[id] = "Rank " .. i end
for i, id in ipairs({ 5504, 5505, 5506, 6127, 10138, 10139 }) do RANK[id] = "Rank " .. i end
c.C_Spell = {
  GetSpellName = function(id) return NAMES[id] end,
  GetSpellTexture = function(id) return 1000 + id end,
  GetSpellSubtext = function(id) return RANK[id] end,
  RequestLoadSpellData = function() end,
}
c.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
c.C_SpellBook = { IsSpellKnown = function(id) return c.KNOWN[id] == true end }
local made = {}
local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
function LDB:NewDataObject(name, o) made[name] = o; return o end
for _, f in ipairs({ "chronicle/Style.lua", "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/MageTravel.lua", "modules/MageConjure.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "Other")
local M, T = c.TwichUI.MageConjure, c.TwichUI.MageTravel

-- The launcher.
local obj = made["TwichUI Mage Conjuring"]
assert(obj and made["TwichUI Mage Travel"], "both launchers")
assert(obj.type == "data source" and obj.label == "Mage Conjuring" and obj.icon == c.TwichUI.PATH .. "media\\textures\\mage-conjure", "TwichUI's bread and water icon")
assert(obj.text == "Conjure", "\"Conjure\" on the bar by default")
assert(M.SetTextChoice("Food & Water") and obj.text == "Food & Water" and c.TwichUIDB.ui.mageConjureText == "Food & Water")
assert(M.SetTextChoice("none") and obj.text == "")
assert(not M.SetTextChoice("Portals"), "another launcher's choice is refused")
assert(T.TextChoice() == "Travel", "each launcher keeps its own text")
assert(obj.OnEnter and obj.OnLeave and not obj.OnTooltipShow, "it handles hovering itself, to lay the shortcut cover")
local Tobj = made["TwichUI Mage Travel"]
assert(Tobj.OnTooltipShow and not Tobj.OnEnter, "Mage Travel has no shortcuts and no cover")

-- Hovering: the tooltip on the data bar's own frame, and a secure cover laid exactly over it.
local bar = { GetRect = function() return 900, 740, 60, 20 end, GetEffectiveScale = function() return 1 end,
  GetFrameStrata = function() return "MEDIUM" end, GetFrameLevel = function() return 5 end,
  IsMouseOver = function() return false end }
local function Cover()
  for _, f in ipairs(frames) do
    if f.template == "SecureActionButtonTemplate" and f.parent == c.UIParent then return f end
  end
end
obj.OnEnter(bar)
local cover = Cover()
assert(cover and cover.shown, "the cover is up while the mouse is on the launcher")
assert(tip.owner == bar, "the tooltip belongs to the data bar's frame, not the secure cover")
local joined = table.concat(tip.lines, "\n")
assert(joined:find("Food: 3 of 6 learned", 1, true) and joined:find("Water: 3 of 6 learned", 1, true)
  and joined:find("Click to choose what to conjure", 1, true), joined)
assert(joined:find("Shift-left-click: Conjure Water, Rank 3", 1, true) and joined:find("Shift-right-click: Conjure Food, Rank 3", 1, true), joined)
assert(cover.attrs["shift-type1"] == "spell" and cover.attrs["shift-spell1"] == 5506, "shift-left: the best water known")
assert(cover.attrs["shift-type2"] == "spell" and cover.attrs["shift-spell2"] == 990, "shift-right: the best food known")
assert(cover.attrs.type == nil and cover.attrs.type1 == nil and cover.attrs.type2 == nil, "a plain click casts nothing")
cover.mouse = true
obj.OnLeave(bar)
assert(tip.owner == bar, "the bar losing the mouse to the cover keeps the tooltip")

-- Clicking the cover: plain clicks are the launcher's; shift-clicks are the game's to cast.
cover.scripts.PostClick(cover, "LeftButton", true)
assert(not M.IsOpen(), "nothing on the press")
cover.scripts.PostClick(cover, "LeftButton", false)
assert(M.IsOpen(), "a plain click opens the menu")
cover.scripts.PostClick(cover, "LeftButton", false)
assert(not M.IsOpen(), "and closes it")
c.SHIFT = true
cover.scripts.PostClick(cover, "LeftButton", false)
cover.scripts.PostClick(cover, "RightButton", false)
assert(not M.IsOpen() and #c.notices == 0, "shift-clicks don't open the menu or the options")
c.SHIFT = false

-- Leaving takes the cover and tooltip away; the next hover has the newest ranks.
cover.mouse = false
cover.scripts.OnLeave(cover)
assert(not cover.shown and tip.owner == nil, "gone with the mouse")
c.KNOWN[6127] = true
obj.OnEnter(bar)
assert(cover.attrs["shift-spell1"] == 6127, "a rank learned since is used")
cover.scripts.OnLeave(cover)

-- No water learned: shift-left-click does nothing, and says why.
for _, id in ipairs({ 5504, 5505, 5506, 6127 }) do c.KNOWN[id] = nil end
obj.OnEnter(bar)
assert(cover.attrs["shift-type1"] == nil and cover.attrs["shift-spell1"] == nil and cover.attrs["shift-spell2"] == 990)
assert(table.concat(tip.lines, "\n"):find("Shift-left-click: Conjure Water, not learned yet", 1, true))
c.SHIFT = true
cover.scripts.PostClick(cover, "LeftButton", false)
assert(c.notices[#c.notices] == "Conjure Water isn't learned yet.", tostring(c.notices[#c.notices]))
c.SHIFT = false
for _, id in ipairs({ 5504, 5505, 5506 }) do c.KNOWN[id] = true end

-- Combat: the cover goes as combat starts and isn't laid during it; a shift-click then says so.
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not cover.shown, "put away just before lockdown")
c.COMBAT = true
cover.attrs["shift-spell1"] = "unchanged"
obj.OnEnter(bar)
assert(not cover.shown and cover.attrs["shift-spell1"] == "unchanged", "no cover, and no attribute changes, in combat")
c.SHIFT = true
obj.OnClick(bar, "LeftButton")
assert(c.notices[#c.notices] == "Shift-click shortcuts can't be used in combat." and not M.IsOpen())
c.SHIFT = false
c.COMBAT = false
obj.OnLeave(bar)

-- The menu: one row per category, the highest rank learned, castable by its exact spell ID.
obj.OnClick({}, "LeftButton")
assert(M.IsOpen() and not T.IsOpen(), "its own menu")
local menu
for _, f in ipairs(frames) do if f.name == "TwichUIMageConjureMenu" then menu = f end end
assert(menu, "its own named menu frame")
local function Rows()
  local rows = {}
  for _, f in ipairs(frames) do
    if f.template == "SecureActionButtonTemplate" and f.shown and f.parent == menu then rows[#rows + 1] = f end
  end
  table.sort(rows, function(a, b) return a.entry.kind.key == "food" and b.entry.kind.key == "water" end)
  return rows
end
local rows = Rows()
assert(#rows == 2, "exactly one food and one water row: " .. #rows)
assert(rows[1].entry.id == 990 and rows[2].entry.id == 5506, "food rank 3, water rank 3")
assert(rows[1].name.text == "Rank 3" and rows[1].note.text == "", "the rank, and no note when learned")
local food, water = rows[1], rows[2]
assert(food.attrs.type == "spell" and food.attrs.spell == 990, "casts that exact food rank by ID")
assert(water.attrs.type == "spell" and water.attrs.spell == 5506, "casts that exact water rank by ID")
food.scripts.OnEnter(food)
local t = table.concat(tip.lines, "\n")
assert(tip.spell == 990 and t:find("Click to cast", 1, true) and not t:find("Trained at", 1, true), t)

-- Food and water have their own highest ranks; a gap in the ranks doesn't matter, nor does ID order.
c.KNOWN = { [587] = true, [990] = true, [10144] = true, [5504] = true, [5505] = true, [6127] = true, [10138] = true }
M.Close(); obj.OnClick({}, "LeftButton")
rows = Rows()
assert(#rows == 2 and rows[1].entry.id == 10144 and rows[2].entry.id == 10138, "food rank 5, water rank 5 despite a gap")
assert(rows[1].attrs.spell == 10144 and rows[2].attrs.spell == 10138)
c.KNOWN = { [10145] = true, [5504] = true }
M.Close(); obj.OnClick({}, "LeftButton")
rows = Rows()
assert(rows[1].entry.id == 10145 and rows[2].entry.id == 5504, "different ranks for each")
assert(rows[1].name.text == "Rank 6" and rows[2].name.text == "Rank 1")

-- Learning a rank while the menu is open: the spellbook event redraws it, still one row each.
c.KNOWN = { [587] = true, [5504] = true }
M.Close(); obj.OnClick({}, "LeftButton")
c.KNOWN[597] = true; c.KNOWN[5505] = true
c.FireEvent("SPELLS_CHANGED"); c.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 5505, 1, false); FlushTimers()
rows = Rows()
assert(#rows == 2 and rows[1].attrs.spell == 597 and rows[2].attrs.spell == 5505, "newly learned ranks replace the old")
assert(rows[1].entry.id == 597 and rows[2].entry.id == 5505)

-- Missing spell data: no lower rank stands in; the row arrives with its name.
NAMES[597] = nil
c.FireEvent("SPELLS_CHANGED"); FlushTimers()
rows = Rows()
assert(#rows == 1 and rows[1].entry.id == 5505, "the food row waits for its name; the water row is unaffected")
NAMES[597] = "Conjure Food"
c.FireEvent("SPELL_DATA_LOAD_RESULT", 597, true); FlushTimers()
rows = Rows()
assert(#rows == 2 and rows[1].attrs.spell == 597, "the row appears when the name loads")

-- Combat: nothing is rebuilt; the open menu has closed, and the secure rows keep what they had.
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not M.IsOpen())
c.COMBAT = true
c.KNOWN[990] = true
c.FireEvent("SPELLS_CHANGED"); FlushTimers()
assert(rows[1].attrs.spell == 597, "no attribute changes in combat")
c.COMBAT = false
obj.OnClick({}, "LeftButton")
rows = Rows()
assert(rows[1].attrs.spell == 990, "the new rank is used when the menu next opens")
M.Close()

-- A category with no learned rank: one muted row, rank 1, with what to learn.
c.KNOWN = { [587] = true, [597] = true, [990] = true }
obj.OnClick({}, "LeftButton")
rows = Rows()
assert(#rows == 2 and rows[1].entry.id == 990 and rows[2].entry.id == 5504, "water shows rank 1 only")
water = rows[2]
assert(water.attrs.type == nil and water.attrs.spell == nil and water.icon.desaturated, "no action for an unlearned one")
assert(water.note.text == "Level 4" and water.name.text == "Rank 1")
water.scripts.OnEnter(water)
t = table.concat(tip.lines, "\n")
assert(tip.spell == 5504 and t:find("Not yet learned", 1, true) and t:find("Trained at level 4", 1, true)
  and t:find("Taught by Mage trainers", 1, true) and not t:find("Requires", 1, true), t)
-- and none of either
c.KNOWN = {}
M.Close(); obj.OnClick({}, "LeftButton")
rows = Rows()
assert(#rows == 2 and rows[1].entry.id == 587 and rows[2].entry.id == 5504 and not rows[1].entry.known)
-- the launcher's tooltip still counts every rank
c.KNOWN = { [587] = true, [597] = true, [990] = true }
obj.OnEnter(bar)
t = table.concat(tip.lines, "\n")
assert(t:find("Food: 3 of 6 learned", 1, true) and t:find("Water: 0 of 6 learned", 1, true), t)
cover.scripts.OnLeave(cover)
M.Close()
c.KNOWN = { [587] = true, [597] = true, [990] = true, [5504] = true, [5505] = true, [5506] = true }
obj.OnClick({}, "LeftButton")
rows = Rows()
local byID = {}
for _, r in ipairs(rows) do byID[r.entry.id] = r end

-- The other launcher: clicking it closes this menu and opens its own.
local bar = { IsMouseOver = function() return false end }
c.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
made["TwichUI Mage Travel"].OnClick(bar, "LeftButton")
assert(not M.IsOpen() and T.IsOpen(), "one menu at a time when clicking from one to the other")
c.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(not T.IsOpen())

-- A cast's release closes it; combat closes it and keeps it shut.
obj.OnClick(bar, "LeftButton")
byID[990].scripts.PostClick(byID[990], "LeftButton", false)
assert(not M.IsOpen(), "closed after casting")
obj.OnClick(bar, "LeftButton")
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not M.IsOpen(), "closed as combat starts")
c.COMBAT = true
obj.OnClick(bar, "LeftButton")
assert(not M.IsOpen(), "won't open in combat")
c.COMBAT = false

-- Other classes: nothing.
local w = MakeClient("Wren", { "!!!TwichUI" })
w.UnitClass = function() return "Class", "PRIEST" end
local wmade = {}
local wLDB = w.LibStub:NewLibrary("LibDataBroker-1.1", 1)
function wLDB:NewDataObject(name, o) wmade[name] = o; return o end
for _, f in ipairs({ "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/MageTravel.lua", "modules/MageConjure.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, w); chunk("!!!TwichUI", {})
end
w.TwichUIDB = { modules = {} }
w.LOADED["!!!TwichUI"] = true; w.FireEvent("ADDON_LOADED", "!!!TwichUI"); w.FireEvent("PLAYER_LOGIN")
assert(not wmade["TwichUI Mage Conjuring"] and not wmade["TwichUI Mage Travel"], "no launchers for a Priest")

print("PASSED")
