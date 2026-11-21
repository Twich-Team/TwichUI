-- TwichUI Fishing: saved data (TwichUI_Fishing/Store.lua). A new file, an unversioned one, narrow repair of damaged fields,
-- data from a newer schema held untouched, repeatable migration, plain values only, defaults never shared, and the gear
-- snapshot never lost to a repair. Simulated client (tests/fishing_mock.lua); the round trip stands in for the game's file.
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local function Load(db, epoch)
  local c, W = FishingClient({ db = db, epoch = epoch })
  c.TwichUI.RunCommand("fish")
  return c, W, c.TwichUI.Fishing
end
local KEY = "Rich - Forever"

-- a new install
do
  local c, W, F = Load(nil)
  local db = c.TwichUIFishingDB
  Check(db.schema == 1 and type(db.chars) == "table" and type(db.config) == "table", "a new file gets schema 1")
  Check(F.Store.Get("containers.mode") == "queue" and F.Store.Get("lure.auto") == true and F.Store.Get("gear.pole") == false, "defaults")
  Check(F.Store.Get("enabled") == true, "on once loaded (loading is the player's choice)")
  F.Store.Set("lure.warn", 90)
  local c2, _, F2 = Load(nil)
  Check(F2.Store.Get("lure.warn") == 60, "defaults are never shared between files")
  Check(not F.Store.Set("containers.mode", "always"), "a value that doesn't fit is refused")
  Check(not F.Store.Set("session.idleMinutes", 0) and F.Store.Set("session.idleMinutes", 5), "ranges are checked")
end

-- an unversioned table and a damaged one: each field repaired on its own
do
  local db = {
    config = { lure = { auto = "yes", preferred = 6530 }, containers = "broken", session = { idleMinutes = 25 } },
    chars = {
      [KEY] = {
        totals = { casts = 5, catches = "x", species = { [6291] = { q = 4, c = 4 } }, zones = 7 },
        sessions = { { id = 1, start = 10, stop = 20 }, "junk" },
        queue = { { id = 1, item = 5523, n = 2, sid = 1 }, { id = 2, item = "clam", n = 1 }, { id = 3, item = 5524, n = 0 } },
        gear = { state = "weird", snapshot = { at = 5, kind = "pole", slots = { [16] = { id = 2000 } } } },
        session = { id = "nope" },
      },
      [5] = {},
    },
  }
  local c, W, F = Load(db)
  local ch = c.TwichUIFishingDB.chars[KEY]
  Check(c.TwichUIFishingDB.schema == 1, "an unversioned file is given schema 1")
  Check(F.Store.Get("lure.auto") == true and F.Store.Get("lure.preferred") == 6530, "a damaged value is replaced; the good one beside it is kept")
  Check(F.Store.Get("containers.mode") == "queue" and F.Store.Get("session.idleMinutes") == 25, "a damaged group is rebuilt; other groups untouched")
  Check(ch.totals.casts == 5 and ch.totals.catches == 0 and ch.totals.species[6291].q == 4 and type(ch.totals.zones) == "table", "totals repaired field by field")
  Check(#ch.sessions == 1 and ch.sessions[1].id == 1, "a damaged summary is dropped, the rest kept")
  Check(#ch.queue == 1 and ch.queue[1].item == 5523, "damaged and empty lots dropped")
  Check(ch.gear.state == "pending" and ch.gear.snapshot.slots[16].id == 2000, "a damaged gear record keeps its snapshot, pending")
  Check(ch.session == nil, "a session that can't be read is dropped")
  Check(c.TwichUIFishingDB.chars[5] == nil, "an entry that isn't a character is dropped")
  Check(F.Store.repairs > 0 and F.noteCounts.repaired > 0, "repairs are counted")
  -- repeatable: loading the repaired file again changes nothing
  local once = FishRoundTrip(c.TwichUIFishingDB)
  local c2, _, F2 = Load(FishRoundTrip(once))
  local twice = FishRoundTrip(c2.TwichUIFishingDB)
  local function Same(a, b, path)
    if type(a) ~= type(b) then return false, path end
    if type(a) ~= "table" then return a == b, path end
    for k, v in pairs(a) do local ok, p = Same(v, b[k], path .. "." .. tostring(k)); if not ok then return false, p end end
    for k in pairs(b) do if a[k] == nil then return false, path .. "." .. tostring(k) end end
    return true
  end
  local ok, where = Same(once, twice, "db")
  Check(ok, "loading again is a no-op (" .. tostring(where) .. ")")
  Check(F2.Store.repairs == 0, "and repairs nothing")
end

-- data from a newer schema is held: nothing written, recording off, the key still casts
do
  local db = { schema = 7, chars = { [KEY] = { futureField = true, totals = "new shape" } }, config = { enabled = true } }
  local c, W, F = Load(db)
  Check(F.Store.held and c.TwichUIFishingDB.schema == 7, "held")
  Check(c.TwichUIFishingDB.chars[KEY].totals == "new shape" and c.TwichUIFishingDB.chars[KEY].futureField, "untouched")
  W.bound.F = "CLICK TwichUIFishingButton:LeftButton"
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  W.Wear(16, POLE)
  Check(W.Key("F") == "spell", "the key still casts")
  W.Loot({ { FISH1, 1 } }, { fishing = true }); W.StopLine(); W.Advance(3)
  Check(c.TwichUIFishingDB.chars[KEY].totals == "new shape" and c.TwichUIFishingDB.chars[KEY].session == nil, "nothing is recorded")
  Check(not F.Store.Set("lure.auto", false), "and settings can't be changed")
  Check(F.noteCounts.held == 1, "the hold is reported")
end

-- after real use: plain values only, nothing runtime saved, records apart from configuration
do
  local c, W, F = Load(nil)
  W.bound.F = "CLICK TwichUIFishingButton:LeftButton"
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  W.Wear(16, SWORD); W.Give(POLE); W.Give(LURE50)
  for _ = 1, 3 do W.Key("F"); W.Advance(2) end
  W.Loot({ { FISH1, 2 }, { CLAM, 1 } }, { fishing = true }); W.StopLine(); W.Advance(3)
  local saved = FishRoundTrip(c.TwichUIFishingDB)
  local ch = saved.chars[KEY]
  Check(ch.session and ch.session.casts == 1 and ch.session.recent and #ch.session.recent == 2, "the session in progress is saved")
  Check(ch.gear.snapshot.slots[16].id == SWORD and #ch.queue == 1, "the snapshot and the queue are saved")
  for k in pairs(saved) do Check(({ schema = true, config = true, chars = true, client = true, capability = true })[k], "only declared keys at the top: " .. k) end
  for _, rec in ipairs({ ch.session, ch.totals }) do
    for k in pairs(rec) do Check(k ~= "price" and k ~= "value" and k ~= "gold", "no prices in the catch records") end
    for id, e in pairs(rec.species) do Check(type(id) == "number" and e.name == nil and e.link == nil, "species by id only") end
  end
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_store")
