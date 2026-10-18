-- Dungeon Journal on a data bar: made only when the journal is loaded, LibDataBroker exists and the switch is on;
-- a click opens and closes the journal's own window through its global toggle; nothing happens when the switch is
-- off or the window isn't built yet; late loading of the journal or of LibDataBroker is picked up; made once.
dofile(TESTS .. "harness.lua")

local OURS = "TwichUI Dungeon Journal"
-- Only this broker's registrations: the Chronicle's data object shares the library.
local function Count(c) local n = 0 for _, name in ipairs(c.made) do if name == OURS then n = n + 1 end end return n end
local function Obj(c) return c.objects[OURS] end

-- A stand-in for the journal: its toggle and its window, as ForeverDungeonJournal defines them.
local function Journal(c)
  local j = { shown = false, toggles = 0 }
  c.ForeverDungeonJournal_Toggle = function() j.toggles = j.toggles + 1; j.shown = not j.shown end
  c.ForeverDungeonJournalFrame = { IsShown = function() return j.shown end }
  return j
end

local function Client(withJournal, withLDB)
  local c = MakeClient("Rich", { "!!!TwichUI", "ForeverDungeonJournal" })
  c.TwichUIDB = { modules = { dungeonJournalBroker = true } }
  c.made, c.objects = {}, {}
  if withLDB then
    local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
    function LDB:NewDataObject(name, o) table.insert(c.made, name); c.objects[name] = o; return o end
  end
  local j = withJournal and Journal(c) or nil
  local chunk = assert(loadfile(ROOT .. "modules/DungeonJournalBroker.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  c.j = j
  return c
end

-- 1. Logged in with the journal and a data bar's LibDataBroker: made once, with its icon, no text, and the switch on.
do
  local c = Client(true, true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "Other")
  assert(Count(c) == 1, "registered once, by name")
  local obj = Obj(c)
  assert(obj.type == "data source" and obj.label == "Dungeon Journal", "a data source labelled for the journal")
  assert(obj.icon == c.TwichUI.PATH .. "media\\textures\\dungeon-journal-broker", "TwichUI's own journal icon")
  assert(obj.text == "", "icon only")
  assert(c.TwichUI.DungeonJournalBroker.Available(), "available once made")
end

-- 2. A click opens the window, a second click closes it; the journal's own toggle is what runs.
do
  local c = Client(true, true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local obj, j = Obj(c), c.j
  obj.OnClick("frame", "LeftButton")
  assert(j.shown and j.toggles == 1, "the first click opens the journal")
  obj.OnClick("frame", "LeftButton")
  assert(not j.shown and j.toggles == 2, "the second click closes it")
end

-- 3. The switch off: a click does nothing, and the tooltip says so. Turned on again, clicks work.
do
  local c = Client(true, true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local obj, j = Obj(c), c.j
  c.TwichUI.Switches.Set("dungeonJournalBroker", false)
  obj.OnClick("frame", "LeftButton")
  assert(j.toggles == 0 and not j.shown, "off: a click leaves the journal alone")
  local lines = {}
  obj.OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. ": " .. b end })
  assert(table.concat(lines, "\n"):find("Turned off", 1, true), "the tooltip says it is off")
  c.TwichUI.Switches.Set("dungeonJournalBroker", true)
  obj.OnClick("frame", "LeftButton")
  assert(j.toggles == 1 and j.shown, "back on: the click opens it again")
end

-- 4. The window isn't built yet (a click before the journal's own PLAYER_LOGIN): nothing happens, no error.
do
  local c = Client(false, true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  assert(Count(c) == 0, "no journal yet at login: nothing made")
  -- the journal then loads: its toggle exists, its window does not yet
  c.ForeverDungeonJournal_Toggle = function() c.toggled = (c.toggled or 0) + 1 end
  c.FireEvent("ADDON_LOADED", "ForeverDungeonJournal")
  assert(Count(c) == 1, "made once the journal loads after login")
  Obj(c).OnClick("frame", "LeftButton")
  assert((c.toggled or 0) == 0, "no window yet: the click does nothing")
  c.ForeverDungeonJournalFrame = { IsShown = function() return false end }
  Obj(c).OnClick("frame", "LeftButton")
  assert(c.toggled == 1, "with its window built, the click toggles it")
end

-- 5. Without the journal, or without a data bar's LibDataBroker, nothing is made.
do
  local c = Client(false, true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  assert(Count(c) == 0 and not c.TwichUI.DungeonJournalBroker.Available(), "no journal, nothing made")
  local d = Client(true, false)
  d.FireEvent("ADDON_LOADED", "!!!TwichUI"); d.FireEvent("PLAYER_LOGIN")
  assert(not d.TwichUI.DungeonJournalBroker.Available(), "no LibDataBroker, nothing made")
  -- a data bar addon brings the library later
  local LDB = d.LibStub:NewLibrary("LibDataBroker-1.1", 1)
  function LDB:NewDataObject(name, o) table.insert(d.made, name); return o end
  d.FireEvent("ADDON_LOADED", "SomeDataBar")
  assert(Count(d) == 1 and d.TwichUI.DungeonJournalBroker.Available(), "made when a data bar brings LibDataBroker later")
end

-- 6. The switch off before login: nothing is made at all.
do
  local c = Client(true, true)
  c.TwichUIDB.modules.dungeonJournalBroker = false
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  assert(Count(c) == 0, "switch off at login: nothing made")
end

print("DUNGEON JOURNAL BROKER TESTS PASSED")
