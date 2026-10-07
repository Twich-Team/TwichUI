-- Mage Travel: the spell list matches the Forever training data; Mages only; the launcher made
-- once, and only when LibDataBroker exists, with the chosen text ("Travel", "Portals" or none); the menu lists the faction's own teleports and
-- portals, sets a secure spell only on learned rows and only out of combat, explains unlearned
-- ones without inventing a trainer, refuses to open in combat and closes as combat starts,
-- follows learning and late spell data while open, closes after a cast's release, and listens
-- only while open.
dofile(TESTS .. "harness.lua")

-- The spell list against What's Training?'s Forever data, as TwichUI carries it.
do
  local env = setmetatable({ TwichUI = {} }, { __index = _G })
  local chunk = assert(loadfile(ROOT .. "modules/TrainingData.lua")); setfenv(chunk, env); chunk("!!!TwichUI", {})
  local levels = env.TwichUI.TrainingData.MAGE()
  local data = {}
  for level, list in pairs(levels) do for _, e in ipairs(list) do data[e[1]] = { level = level, faction = e.faction } end end
  local menv = setmetatable({ TwichUI = { PATH = "", On = function() end, TrainingData = env.TwichUI.TrainingData } }, { __index = _G })
  for _, f in ipairs({ "modules/SpellMenu.lua", "modules/MageTravel.lua" }) do
    local mchunk = assert(loadfile(ROOT .. f)); setfenv(mchunk, menv); mchunk("!!!TwichUI", {})
  end
  local M = menv.TwichUI.MageTravel
  local seen = {}
  for faction, set in pairs(M.SPELLS) do
    for _, kind in ipairs(M.KINDS) do
      assert(#set[kind.key] == 3, faction .. " " .. kind.key .. ": three cities")
      for _, id in ipairs(set[kind.key]) do
        assert(not seen[id], id .. " listed once"); seen[id] = true
        assert(data[id], id .. " is in the Forever training data")
        assert(data[id].faction == faction, id .. " is " .. faction .. "'s")
        assert(M.TrainedAt(id) == data[id].level, id .. " trained at the data's level")
      end
    end
  end
  assert(M.TrainedAt(3561) == 20 and M.TrainedAt(3565) == 30 and M.TrainedAt(10059) == 40 and M.TrainedAt(11420) == 50)
  assert(M.Destination("Teleport: Stormwind") == "Stormwind" and M.Destination("Portal: Thunder Bluff") == "Thunder Bluff")
  assert(M.Destination("传送门") == "传送门", "a name without the colon is kept whole")
end

local function Boot(class, faction, withLDB)
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
    GetAttribute = function(s, k) return s.attrs[k] end,
    CreateTexture = function() return Fake("texture") end,
    CreateFontString = function() return Fake("font") end,
    SetText = function(s, v) s.text = v end,
    SetTexture = function(s, v) s.texture = v end,
    SetDesaturated = function(s, v) s.desaturated = v end,
    IsMouseOver = function(s) return s.mouse == true end,
    SetPoint = function(s, ...) s.point = { ... } end,
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
  local tip = { lines = {} }
  function tip:SetOwner(o) self.owner = o; self.lines = {}; self.spell = nil end
  function tip:IsOwned(o) return self.owner == o end
  function tip:SetSpellByID(id) self.spell = id end
  function tip:AddLine(t) table.insert(self.lines, t) end
  function tip:Hide() self.owner = nil end
  tip.ClearAllPoints, tip.SetPoint, tip.Show = function() end, function() end, function() end
  c.GameTooltip = tip

  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
  c.UnitClass = function() return "Class", class end
  c.UnitFactionGroup = function() return faction, faction end
  c.UnitLevel = function() return c.LEVEL or 32 end
  c.KNOWN = {}
  c.NAMES = {
    [3561] = "Teleport: Stormwind", [3562] = "Teleport: Ironforge", [3565] = "Teleport: Darnassus",
    [10059] = "Portal: Stormwind", [11416] = "Portal: Ironforge", [11419] = "Portal: Darnassus",
    [3567] = "Teleport: Orgrimmar", [3563] = "Teleport: Undercity", [3566] = "Teleport: Thunder Bluff",
    [11417] = "Portal: Orgrimmar", [11418] = "Portal: Undercity", [11420] = "Portal: Thunder Bluff",
  }
  c.requested = {}
  c.C_Spell = {
    GetSpellName = function(id) return c.NAMES[id] end,
    GetSpellTexture = function(id) return 1000 + id end,
    RequestLoadSpellData = function(id) c.requested[id] = true end,
  }
  c.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
  c.C_SpellBook = { IsSpellKnown = function(id, bank) assert(bank == 0); return c.KNOWN[id] == true end }
  c.made = {}
  if withLDB then
    local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
    function LDB:NewDataObject(name, o)
      if name ~= "TwichUI Mage Travel" then return o end   -- the Chronicle's own
      table.insert(c.made, name); c.obj = o; return o
    end
  end
  for _, f in ipairs({ "chronicle/Style.lua", "modules/TrainingData.lua", "modules/SpellMenu.lua", "modules/MageTravel.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.TwichUIDB = { modules = {} }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.frames = frames
  return c
end

-- Other classes: nothing at all.
local w = Boot("WARRIOR", "Alliance", true)
w.FireEvent("PLAYER_LOGIN")
assert(#w.made == 0 and not w.TwichUI.MageTravel.Available(), "no launcher for a Warrior")
assert(not w.TwichUI.MageTravel.Open({}), "and no menu")

-- No data bar addon: loads fine, no launcher; one loaded later brings it.
local n = Boot("MAGE", "Alliance", false)
n.FireEvent("PLAYER_LOGIN")
assert(not n.TwichUI.MageTravel.Available(), "no LibDataBroker, no launcher")
local LDB = n.LibStub:NewLibrary("LibDataBroker-1.1", 1)
function LDB:NewDataObject(name, o) if name == "TwichUI Mage Travel" then table.insert(n.made, name) end return o end
n.FireEvent("ADDON_LOADED", "SomeDataBar")
assert(#n.made == 1 and n.TwichUI.MageTravel.Available(), "made once a data bar brings LibDataBroker")

-- An Alliance Mage with Teleport: Stormwind and Teleport: Ironforge.
local c = Boot("MAGE", "Alliance", true)
local M = c.TwichUI.MageTravel
c.KNOWN[3561], c.KNOWN[3562] = true, true
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "Other")
assert(#c.made == 1 and c.made[1] == "TwichUI Mage Travel", "registered once, by name")
local obj = c.obj
assert(obj.type == "data source" and obj.label == "Mage Travel" and obj.icon == c.TwichUI.PATH .. "media\\textures\\mage-travel",
  "a data source with TwichUI's portal icon")
assert(obj.text == "Travel" and M.TextChoice() == "Travel", "\"Travel\" on the bar by default")
assert(M.SetTextChoice("Portals") and obj.text == "Portals" and c.TwichUIDB.ui.mageTravelText == "Portals", "\"Portals\" at once")
assert(M.SetTextChoice("none") and obj.text == "", "or just the icon")
assert(not M.SetTextChoice("Teleports") and obj.text == "" and c.TwichUIDB.ui.mageTravelText == "none", "an unknown choice is refused")
c.TwichUIDB.ui.mageTravelText = 42
assert(M.TextChoice() == "Travel", "a bad saved value reads as the default")
assert(M.SetTextChoice("Travel") and obj.text == "Travel")
assert(not M.IsOpen(), "nothing opens by itself")

local lines = {}
obj.OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. ": " .. b end })
local joined = table.concat(lines, "\n")
assert(joined:find("Teleports: 2 of 3 learned", 1, true) and joined:find("Portals: 0 of 3 learned", 1, true), joined)
assert(not M.IsOpen(), "hovering the launcher doesn't open it")

-- Opening: a secure row per spell, the Alliance's only, a spell set only where learned.
local bar = { GetRect = function() return 900, 740, 60, 20 end, GetEffectiveScale = function() return 1 end }
c.UIParent.GetEffectiveScale = function() return 1 end
c.UIParent.GetWidth = function() return 1024 end
c.UIParent.GetHeight = function() return 768 end
obj.OnClick(bar, "LeftButton")
assert(M.IsOpen(), "a click opens it")
local menu
for _, f in ipairs(c.frames) do if f.name == "TwichUIMageTravelMenu" then menu = f end end
assert(menu and c.UISpecialFrames[1] == "TwichUIMageTravelMenu", "Esc closes it")
assert(menu.point[1] == "TOPRIGHT" and menu.point[2] == c.UIParent and menu.point[4] == 960 and menu.point[5] == 738,
  "below a bar at the top right, placed against UIParent: " .. tostring(menu.point[1]))
local function Rows()
  local list = {}
  for _, f in ipairs(c.frames) do
    if f.template == "SecureActionButtonTemplate" and f.shown then list[#list + 1] = f end
  end
  return list
end
local rows = Rows()
assert(#rows == 6, "three teleports and three portals: " .. #rows)
local byID = {}
for _, r in ipairs(rows) do
  assert(r.parent == menu, "rows sit in the menu")
  byID[r.entry.id] = r
  assert(r.entry.id ~= 3567 and r.entry.id ~= 11417, "no Horde spells")
end
assert(byID[3561].attrs.type == "spell" and byID[3561].attrs.spell == 3561, "a learned teleport casts by ID")
assert(byID[3565].attrs.type == nil and byID[3565].attrs.spell == nil, "an unlearned one has no action")
assert(byID[10059].attrs.type == nil, "nor an unlearned portal")
assert(byID[3561].name.text == "Stormwind" and byID[3565].note.text == "Level 30" and byID[3561].note.text == "", "destination, and the level when unlearned")
assert(byID[3565].icon.desaturated == true and byID[3561].icon.desaturated == false, "unlearned icons greyed, names kept")

-- Hovering: the game's spell tooltip, then the honest learning lines.
byID[10059].scripts.OnEnter(byID[10059])
local t = table.concat(c.GameTooltip.lines, "\n")
assert(c.GameTooltip.spell == 10059, "the game's own spell tooltip")
assert(t:find("Not yet learned", 1, true) and t:find("Portal, Alliance only", 1, true) and t:find("Trained at level 40", 1, true)
  and t:find("Learning location unavailable", 1, true), t)
byID[3561].scripts.OnEnter(byID[3561])
t = table.concat(c.GameTooltip.lines, "\n")
assert(t:find("Click to cast", 1, true) and not t:find("Trained at", 1, true), "no training lines for a learned spell")
byID[3561].scripts.OnLeave(byID[3561])
assert(c.GameTooltip.owner == nil)

-- Listening only while open.
local bus = c.TwichUI.frame
assert(bus.events.SPELLS_CHANGED and bus.events.PLAYER_REGEN_DISABLED and bus.events.GLOBAL_MOUSE_DOWN, "listens while open")

-- Learning a spell while it is open.
c.KNOWN[10059] = true
c.FireEvent("SPELLS_CHANGED"); FlushTimers()
assert(byID[10059].attrs.type == "spell" and byID[10059].attrs.spell == 10059, "the new portal is castable")

-- Clicking: an unlearned row keeps the menu open; a learned one closes on the release only.
byID[3565].scripts.PostClick(byID[3565], "LeftButton", false)
assert(M.IsOpen(), "an unlearned row does nothing")
byID[3561].scripts.PostClick(byID[3561], "LeftButton", true)
assert(M.IsOpen(), "the press may be the one that casts: still open")
byID[3561].scripts.PostClick(byID[3561], "LeftButton", false)
assert(not M.IsOpen(), "closed after the release")
assert(not bus.events.SPELLS_CHANGED and not bus.events.GLOBAL_MOUSE_DOWN and not bus.events.PLAYER_REGEN_DISABLED, "stops listening when closed")

-- A click elsewhere closes it; on the menu or the launcher it doesn't.
obj.OnClick(bar, "LeftButton")
menu.mouse = true; c.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton"); assert(M.IsOpen())
menu.mouse = false; bar.IsMouseOver = function() return true end; c.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton"); assert(M.IsOpen())
bar.IsMouseOver = function() return false end; c.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton"); assert(not M.IsOpen(), "a click elsewhere closes it")
obj.OnClick(bar, "LeftButton"); obj.OnClick(bar, "LeftButton")
assert(not M.IsOpen(), "the launcher toggles it")

-- Combat: closes as it begins; won't open during it, and says so locally.
obj.OnClick(bar, "LeftButton")
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not M.IsOpen(), "closed just before lockdown")
c.COMBAT = true
obj.OnClick(bar, "LeftButton")
assert(not M.IsOpen() and c.notices[#c.notices] == "Mage Travel can't be opened in combat.", "refused, with a message")
lines = {}
obj.OnTooltipShow({ AddLine = function(_, l) lines[#lines + 1] = l end, AddDoubleLine = function() end })
assert(table.concat(lines, "\n"):find("can't be opened in combat", 1, true), "the launcher's tooltip says so too")
-- Still open as lockdown began (the close came too late): left alone until combat ends.
c.COMBAT = false; obj.OnClick(bar, "LeftButton"); c.COMBAT = true
local before = byID[3565].attrs.type
c.KNOWN[3565] = true; c.FireEvent("SPELLS_CHANGED"); FlushTimers()
assert(byID[3565].attrs.type == before, "no attribute changes in combat")
assert(M.Close() == false and M.IsOpen(), "can't close in combat")
c.FireEvent("PLAYER_REGEN_DISABLED"); assert(M.IsOpen())
c.COMBAT = false; c.FireEvent("PLAYER_REGEN_ENABLED")
assert(not M.IsOpen(), "closed when combat ends")

-- Spell data the game hasn't loaded: the row waits, and appears when it arrives.
c.NAMES[11419] = nil
obj.OnClick(bar, "LeftButton")
assert(#Rows() == 5 and c.requested[11419], "left out and asked for")
c.NAMES[11419] = "Portal: Darnassus"
c.FireEvent("SPELL_DATA_LOAD_RESULT", 11419, true); FlushTimers()
assert(#Rows() == 6, "drawn once it loads")
obj.OnClick(bar, "LeftButton")

-- A Horde Mage sees Horde cities only.
local h = Boot("MAGE", "Horde", true)
h.FireEvent("PLAYER_LOGIN")
h.obj.OnClick({}, "LeftButton")
local ids = {}
for _, f in ipairs(h.frames) do if f.template == "SecureActionButtonTemplate" and f.shown then ids[#ids + 1] = f.entry.id end end
table.sort(ids)
assert(table.concat(ids, ",") == "3563,3566,3567,11417,11418,11420", table.concat(ids, ","))

-- Turned off: the menu closes and won't open.
c.TwichUIDB.modules.mageTravel = false
assert(not M.Open(bar) and not M.IsOpen())

print("PASSED")
