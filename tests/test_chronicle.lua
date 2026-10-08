dofile(TESTS .. "harness.lua")
local out = {}
local function boot(name, saved)
  local c = MakeClient(name, {"!!!TwichUI"})
  c.print = function(s) table.insert(out, tostring(s)) end
  c.TwichUIDB = saved and saved.db or {}
  c.TwichUIChronicleDB = saved and saved.chron or nil
  c.ZONE = "Elwynn Forest"
  c.GetRealZoneText = function() return c.ZONE end
  c.GetZoneText = c.GetRealZoneText
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  return c
end
local function events(c) local n = 0 for _ in pairs(c.TwichUI.frame.events) do n = n + 1 end return n end
local function has(c, e) return c.TwichUI.frame.events[e] == true end

-- on by default: events registered; notes still work
local a = boot("Alpha")
local C, Rec = a.TwichUI.Chronicle, a.TwichUI.ChronicleRecorder
assert(a.TwichUIDB.modules.chronicle == true and a.TwichUIDB.modules.chronicleChat == true)
assert(has(a, "PLAYER_LEVEL_UP") and has(a, "ZONE_CHANGED_NEW_AREA") and has(a, "ENCOUNTER_END"))
-- explicit saved choices survive
local off = boot("Off", { db = { modules = { chronicle = false, chronicleChat = false } } })
assert(off.TwichUIDB.modules.chronicle == false and off.TwichUIDB.modules.chronicleChat == false)
assert(not has(off, "PLAYER_LEVEL_UP"))
-- chat: one local line per recorded automatic entry; none for notes, duplicates, or when switched off
out = {}
a.FireEvent("PLAYER_LEVEL_UP", 5)
a.FireEvent("PLAYER_LEVEL_UP", 5)    -- duplicate
local lines = 0
for _, l in ipairs(out) do if l:find("Reached level 5", 1, true) then lines = lines + 1 end end
assert(lines == 1, "one message for one recorded entry: " .. lines)
local nmsgs = #out
C.Add("note", { title = "Note", note = "quiet" })
assert(#out == nmsgs, "notes print nothing")
a.TwichUIDB.modules.chronicleChat = false
local cnt = C.Count(); a.FireEvent("PLAYER_LEVEL_UP", 6)
assert(C.Count() == cnt + 1 and #out == nmsgs, "chat off still records, silently")
a.TwichUIDB.modules.chronicleChat = true
local n1 = C.Add("note", { title = "Note", note = "  First night at the lake  ", zone = "Elwynn Forest" })
local n2 = C.Add("note", { title = "Note", note = "Second" })
assert(n1 and n2 and n1.id ~= n2.id and n1.note == "First night at the lake")
local base = C.Count()
assert(not C.Add("note", { title = "Note", note = "   " }), "empty notes aren't saved")
assert(a.TwichUI.Chronicle.CurrentZone() == "Elwynn Forest")
a.ZONE = ""; assert(C.CurrentZone() == nil, "missing zone is nil, not wrong"); a.ZONE = "Elwynn Forest"

-- editing and deleting touch only the chosen entry
assert(C.Update(n2.id, "Second, edited", false))
assert(C.Find(n2.id).note == "Second, edited" and C.Find(n1.id).note == "First night at the lake" and C.Find(n1.id).zone == "Elwynn Forest")
assert(C.Delete(n1.id) and not C.Find(n1.id) and C.Find(n2.id) and C.Count() == base - 1)
assert(not C.Delete(9999))

-- turning tracking on: registers events, writes "Chronicle begun" once
a.TwichUIDB.modules.chronicle = true
Rec.Refresh(); Rec.Refresh()
assert(has(a, "PLAYER_LEVEL_UP") and has(a, "ZONE_CHANGED_NEW_AREA") and has(a, "ENCOUNTER_END"))
local starts = 0
for _, e in ipairs(C.Entries()) do if e.kind == "start" then starts = starts + 1; assert(e.title == "Chronicle begun") end end
assert(starts == 1, "begun is written once")

-- level, zone, boss
a.FireEvent("PLAYER_LEVEL_UP", 12)
a.FireEvent("PLAYER_LEVEL_UP", 12)               -- rapid duplicate
local entries = C.Entries()
assert(entries[#entries].title == "Reached level 12" and entries[#entries].level == 12)
local count = C.Count()
a.FireEvent("ZONE_CHANGED_NEW_AREA")             -- same zone as at enable: nothing
assert(C.Count() == count)
a.ZONE = "Duskwood"; a.FireEvent("ZONE_CHANGED_NEW_AREA")
assert(C.Entries()[C.Count()].title == "Arrived in Duskwood")
a.ZONE = ""; a.FireEvent("ZONE_CHANGED_NEW_AREA"); assert(C.Count() == count + 1, "no zone: nothing recorded")
a.ZONE = "Deadmines"
a.FireEvent("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 0, {})   -- wipe
assert(C.Entries()[C.Count()].kind ~= "boss")
a.FireEvent("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1, {})
local last = C.Entries()[C.Count()]
assert(last.title == "Defeated Edwin VanCleef" and last.zone == "Deadmines" and not last.note)
-- deaths: off until chosen, then recorded with the zone
local before = C.Count()
a.FireEvent("PLAYER_DEAD"); assert(C.Count() == before, "deaths are off by default")
a.TwichUIDB.modules.chronicleDeaths = true; Rec.Refresh()
a.ZONE = "Deadmines"; a.FireEvent("PLAYER_DEAD")
local died = C.Entries()[C.Count()]
assert(died.kind == "death" and died.title == "Fell in Deadmines" and died.zone == "Deadmines")
a.TwichUIDB.modules.chronicleDeaths = false; Rec.Refresh()
a.FireEvent("PLAYER_DEAD"); assert(C.Entries()[C.Count()] == died, "switching it off stops it")
-- login isn't arriving
a.ZONE = "Stormwind City"; a.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local c0 = C.Count(); a.FireEvent("ZONE_CHANGED_NEW_AREA"); assert(C.Count() == c0)

-- each event type can be switched off on its own
a.TwichUIDB.modules.chronicleLevels = false; Rec.Refresh()
assert(not has(a, "PLAYER_LEVEL_UP") and has(a, "ZONE_CHANGED_NEW_AREA"))
local c1 = C.Count(); a.FireEvent("PLAYER_LEVEL_UP", 13); assert(C.Count() == c1)

-- master off: every event stops, nothing is written afterwards
a.TwichUIDB.modules.chronicle = false; Rec.Refresh()
assert(not has(a, "PLAYER_LEVEL_UP") and not has(a, "ZONE_CHANGED_NEW_AREA") and not has(a, "ENCOUNTER_END"))   -- (PLAYER_ENTERING_WORLD stays: other TwichUI features use it)
local c2 = C.Count()
a.ZONE = "Westfall"; a.FireEvent("ZONE_CHANGED_NEW_AREA"); a.FireEvent("ENCOUNTER_END", 2, "X", 1, 5, 1, {})
assert(C.Count() == c2)
-- ... and on again says so
a.TwichUIDB.modules.chronicle = true; a.TwichUIDB.modules.chronicleLevels = true; Rec.Refresh()
assert(C.Entries()[C.Count()].title == "Tracking resumed")

-- survives a reload; another character is separate
local saved = { db = a.TwichUIDB, chron = a.TwichUIChronicleDB }
local b = boot("Alpha", saved)
assert(b.TwichUI.Chronicle.Count() == c2 + 1)
local d = boot("Beta", saved)
assert(d.TwichUI.Chronicle.Count() == 1, "only Beta's own 'begun' line")   -- master is account-wide, so Beta starts tracking
for _, e in ipairs(d.TwichUI.Chronicle.Entries()) do assert(e.kind == "start") end

-- retention: automatic entries go first, notes stay, a full note shelf refuses
local e = boot("Gamma", { db = { modules = { chronicle = false } } })
local G = e.TwichUI.Chronicle
G.MAX_ENTRIES = 5
for i = 1, 3 do G.Add("note", { title = "Note", note = "n" .. i }) end
for i = 1, 6 do G.Add("level", { title = "Reached level " .. i, level = i }) end
assert(G.Count() == 5)
local kinds = {}
for _, en in ipairs(G.Entries()) do kinds[en.kind] = (kinds[en.kind] or 0) + 1 end
assert(kinds.note == 3 and kinds.level == 2, "oldest automatic entries trimmed first")
G.Add("note", { title = "Note", note = "n4" }); G.Add("note", { title = "Note", note = "n5" })
local full, why = G.Add("note", { title = "Note", note = "n6" })
assert(not full and why == "full")
for _, en in ipairs(G.Entries()) do assert(en.kind == "note") end

-- bad or older saved data is cleaned up
local h = boot("Delta", { db = { modules = { chronicle = false } }, chron = { chars = { ["Delta - Forever"] = { entries = { 5, { id = 1 }, { id = 2, t = 10, kind = "note", title = "ok", note = 7 }, { id = 2, t = 11, kind = "note", title = "dup" } } }, ["Bad"] = 3 } } })
-- (the row with nothing readable and the character record that isn't a table go; a note that only repeats
-- an id is kept and given a fresh one, since it is the player's own text)
assert(h.TwichUI.Chronicle.Count() == 2 and h.TwichUIChronicleDB.chars.Bad == nil)
assert(h.TwichUI.Chronicle.Add("note", { title = "Note", note = "x" }).id > 2)

-- never part of sharing, setups or backups
for _, f in ipairs({ "setup/Setups.lua", "setup/Share.lua", "setup/Restore.lua", "setup/Group.lua" }) do
  local fh = assert(io.open(ROOT .. f)); local src = fh:read("*a"); fh:close()
  assert(not src:find("Chronicle"), f .. " must not touch the Chronicle")
end
assert(a.TwichUI.Setups.SafeName("TwichUIChronicleDB") == false, "a setup can never replace the Chronicle")
-- data bar object: made only when LibDataBroker exists; follows changes; click opens the window
local k = boot("Kappa")
assert(k.TwichUI.ChronicleBroker, "loads fine without LibDataBroker")
local made, store = nil, {}
local LDB = { NewDataObject = function(_, name, o) made = name; store = o; return o end }
k.LibStub = setmetatable({ GetLibrary = function(_, n) return n == "LibDataBroker-1.1" and LDB or nil end }, { __call = function() end })
k.FireEvent("PLAYER_LOGIN"); k.FireEvent("PLAYER_LOGIN")
assert(made == "TwichUI Chronicle" and store.type == "data source", "object registered once")
local K = k.TwichUI.Chronicle
assert(store.text == "Journey Chronicle", "text is the name, not a count")
local K = k.TwichUI.Chronicle
K.Add("note", { title = "Note", note = "hi" })
assert(store.text == "Journey Chronicle")
local tip = {}
store.OnTooltipShow({ AddLine = function(_, l) tip[#tip + 1] = l end })
assert(#tip >= 3)
local opened = 0
k.TwichUI.ChronicleWindow = k.TwichUI.ChronicleWindow or {}
k.TwichUI.ChronicleWindow.Toggle = function() opened = opened + 1 end
store.OnClick(nil, "LeftButton"); assert(opened == 1)

-- zone baseline at login: where the player already is never counts as an arrival
local function zones(c)
  local n = 0
  for _, e in ipairs(c.TwichUI.Chronicle.Entries()) do if e.kind == "zone" then n = n + 1 end end
  return n
end
do
  -- login with the zone known, then a stray zone event: nothing
  local z = boot("ZoneKnown")
  z.ZONE = "Stormwind City"; z.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  z.FireEvent("ZONE_CHANGED_NEW_AREA"); z.FireEvent("ZONE_CHANGED_NEW_AREA")
  assert(zones(z) == 0, "login zone is not an arrival")
  -- reload in the same zone
  z.FireEvent("PLAYER_ENTERING_WORLD", false, true); z.FireEvent("ZONE_CHANGED_NEW_AREA")
  assert(zones(z) == 0, "reload zone is not an arrival")
  -- genuine change: exactly one, repeats are quiet
  z.ZONE = "Duskwood"; z.FireEvent("ZONE_CHANGED_NEW_AREA"); z.FireEvent("ZONE_CHANGED_NEW_AREA")
  assert(zones(z) == 1)
  -- a loading screen that is not login does not itself record, the zone event does
  z.FireEvent("PLAYER_ENTERING_WORLD", false, false); assert(zones(z) == 1)
  z.ZONE = "Deadmines"; z.FireEvent("ZONE_CHANGED_NEW_AREA"); assert(zones(z) == 2)

  -- login with the zone not yet given: the first real zone becomes the baseline silently
  local d = boot("ZoneLate")
  d.ZONE = ""; d.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  d.ZONE = "Westfall"; d.FireEvent("ZONE_CHANGED_NEW_AREA")
  assert(zones(d) == 0, "late map data is not an arrival")
  d.ZONE = "Duskwood"; d.FireEvent("ZONE_CHANGED_NEW_AREA"); assert(zones(d) == 1)

  -- zone becomes known with no event, via the retry; later travel still records
  local r = boot("ZoneRetry")
  r.ZONE = ""; r.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  r.ZONE = "Westfall"; FlushTimers()
  r.ZONE = "Duskwood"; r.FireEvent("ZONE_CHANGED_NEW_AREA"); assert(zones(r) == 1)

  -- a saved last-known zone (different from the login zone) fabricates nothing
  local saved = boot("ZoneSaved")
  saved.TwichUI.Chronicle.Record().lastZone = "Orgrimmar"
  saved.ZONE = "Teldrassil"; saved.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  saved.FireEvent("ZONE_CHANGED_NEW_AREA"); assert(zones(saved) == 0)
  -- death, ghost and resurrection in the same place are not arrivals; related events never record twice
  local g = boot("ZoneGhost")
  g.ZONE = "Duskwood"; g.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  g.FireEvent("PLAYER_DEAD"); g.FireEvent("PLAYER_ALIVE"); g.FireEvent("PLAYER_UNGHOST")
  g.FireEvent("PLAYER_ENTERING_WORLD", false, false); g.FireEvent("ZONE_CHANGED_NEW_AREA")
  assert(zones(g) == 0, "dying and getting up where you were is not an arrival")
  g.ZONE = "Westfall"; g.FireEvent("ZONE_CHANGED_NEW_AREA"); g.FireEvent("PLAYER_CONTROL_GAINED"); g.FireEvent("ZONE_CHANGED_NEW_AREA")
  assert(zones(g) == 1, "a real move is one entry however many related events follow")

  -- switching zone tracking off and on while a baseline retry is waiting: the old retry does nothing
  local t = boot("ZoneToggle")
  t.ZONE = ""; t.FireEvent("PLAYER_ENTERING_WORLD", true, false)         -- retry waiting
  t.TwichUIDB.modules.chronicleZones = false; t.TwichUI.ChronicleRecorder.Refresh()
  t.TwichUIDB.modules.chronicleZones = true; t.TwichUI.ChronicleRecorder.Refresh()   -- a fresh baseline starts
  t.ZONE = "Westfall"; FlushTimers()                                      -- both retries come due
  t.ZONE = "Duskwood"; t.FireEvent("ZONE_CHANGED_NEW_AREA")
  assert(zones(t) == 1, "one arrival, and the baseline was taken from Westfall, not Duskwood")
  assert(t.TwichUI.Life.Snapshot().notes["cancelled-stale-baseline"] >= 1, "the old retry was set aside and counted")
end
print("CHRONICLE TEST PASSED")
