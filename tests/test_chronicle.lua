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

-- off by default: nothing registered, nothing written, notes still work
local a = boot("Alpha")
local C, Rec = a.TwichUI.Chronicle, a.TwichUI.ChronicleRecorder
assert(not has(a, "PLAYER_LEVEL_UP") and not has(a, "ZONE_CHANGED_NEW_AREA") and not has(a, "ENCOUNTER_END"))
a.FireEvent("PLAYER_LEVEL_UP", 12)
assert(C.Count() == 0, "tracking is off")
local n1 = C.Add("note", { title = "Note", note = "  First night at the lake  ", zone = "Elwynn Forest" })
local n2 = C.Add("note", { title = "Note", note = "Second" })
assert(n1 and n2 and n1.note == "First night at the lake" and n1.id ~= n2.id)
assert(not C.Add("note", { title = "Note", note = "   " }), "empty notes aren't saved")
assert(a.TwichUI.Chronicle.CurrentZone() == "Elwynn Forest")
a.ZONE = ""; assert(C.CurrentZone() == nil, "missing zone is nil, not wrong"); a.ZONE = "Elwynn Forest"

-- editing and deleting touch only the chosen entry
assert(C.Update(n2.id, "Second, edited", false))
assert(C.Find(n2.id).note == "Second, edited" and C.Find(n1.id).note == "First night at the lake" and C.Find(n1.id).zone == "Elwynn Forest")
assert(C.Delete(n1.id) and not C.Find(n1.id) and C.Find(n2.id) and C.Count() == 1)
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
local e = boot("Gamma")
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
local h = boot("Delta", { db = {}, chron = { chars = { ["Delta - Forever"] = { entries = { 5, { id = 1 }, { id = 2, t = 10, kind = "note", title = "ok", note = 7 }, { id = 2, t = 11, kind = "note", title = "dup" } } }, ["Bad"] = 3 } } })
assert(h.TwichUI.Chronicle.Count() == 1 and h.TwichUIChronicleDB.chars.Bad == nil)
assert(h.TwichUI.Chronicle.Add("note", { title = "Note", note = "x" }).id > 2)

-- never part of sharing, setups or backups
for _, f in ipairs({ "setup/Setups.lua", "setup/Share.lua", "setup/Restore.lua", "setup/Group.lua" }) do
  local fh = assert(io.open(ROOT .. f)); local src = fh:read("*a"); fh:close()
  assert(not src:find("Chronicle"), f .. " must not touch the Chronicle")
end
assert(a.TwichUI.Setups.SafeName("TwichUIChronicleDB") == false, "a setup can never replace the Chronicle")
print("CHRONICLE TEST PASSED")
