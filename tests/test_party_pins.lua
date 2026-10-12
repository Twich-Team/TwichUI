-- Party pins: names are plain text and cut safely; coordinates and maps are checked; local pins keep
-- their ids through a rename and survive a reload; party pins reach party members with their names and
-- colors; only the sender owns a pin (a forged removal or change can't touch someone else's); removing
-- from your own map sends nothing and survives a resync; a party-wide removal reaches the others and a
-- late or replayed copy can't bring it back; a local copy outlives the original; duplicates and stale
-- revisions are ignored; leaving the party, a raid, a member leaving and a reload behave as documented;
-- limits and the per-sender rate hold; turning the feature off clears the session; and the diagnostics
-- snapshot holds no names, places or text.
-- The network is the harness's simulation. Whether the game delivers these messages is for the game.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end

local function Load(env, files)
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
  end
end

local MAPS = { [1429] = { name = "Elwynn Forest", parentMapID = 1415 }, [1415] = { name = "Eastern Kingdoms", parentMapID = 947 } }
-- reload: this load is a /reload (PLAYER_ENTERING_WORLD's second argument); otherwise a login.
local function boot(name, saved, reload)
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c
  c.C_Map = {
    GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parentMapID } or nil end,
    CanSetUserWaypointOnMap = function(id) return id == 1429 end,
  }
  c.IsInRaid = function() return RAID == true end
  c.GetTime = function() return CLOCK end
  Load(c, { "pins/Pins.lua", "pins/Sync.lua" })
  c.TwichUIDB = saved or { modules = { partyPins = true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", not reload, reload and true or false); TIMERS = {}
  return c
end
local function settle() for _ = 1, 10 do FlushTimers(); Pump() end; CLOCK = CLOCK + 20 end
local function sent(prefix)
  local n = 0
  for _, m in ipairs(SENT_LOG or {}) do if m.prefix == prefix then n = n + 1 end end
  return n
end

local A, B, C = "Ranulf Ashenvow", "Pal Stonebrook", "Cora Vale"
CLOCK = 1000
local function tick(seconds) CLOCK = CLOCK + (seconds or 2) end

---------------------------------------------------------------------------
-- 1. Checks: names, coordinates, maps, colors
---------------------------------------------------------------------------
local a = boot(A)
local PN, PS = a.TwichUI.Pins, a.TwichUI.PinSync
assert(PN.CleanName("  Herb   spot  ") == "Herb spot")
assert(PN.CleanName("|cffff0000Red|r camp") == "Red camp", "color codes go")
assert(PN.CleanName("|Hitem:123|h[Sword]|h here") == "[Sword] here", "links become their text")
assert(PN.CleanName("|TInterface\\Icons\\x:0|t icon") == "icon", "textures go")
assert(PN.CleanName("a|b") == "ab", "a stray bar goes")
assert(PN.CleanName("line\nbreak\ttab") == "line break tab", "control characters go")
assert(PN.CleanName("   ") == nil and PN.CleanName(nil) == nil and PN.CleanName(5) == nil)
local long = PN.CleanName(string.rep("é", 40))   -- 80 bytes of two-byte characters
assert(#long <= PN.NAME_MAX and #long % 2 == 0, "cut on a character boundary")
assert(PN.Quantize(0) == 0 and PN.Quantize(1) == 10000 and PN.Quantize(0.45216) == 4522)
assert(PN.Quantize(-0.1) == nil and PN.Quantize(1.01) == nil and PN.Quantize(0 / 0) == nil and PN.Quantize("0.5") == nil)
assert(PN.Quantize(math.huge) == nil)
assert(PN.ValidMap(1429) and not PN.ValidMap(99999) and not PN.ValidMap(1.5) and not PN.ValidMap(-3) and not PN.ValidMap("1429"))
assert(PN.ValidColor("moss") and not PN.ValidColor("neon") and not PN.ValidColor(nil))

---------------------------------------------------------------------------
-- 2. Local pins: stable ids, edits keep the identity, saved data survives a reload
---------------------------------------------------------------------------
local p1 = assert(PN.AddLocal({ map = 1429, x = 4521, y = 6130, name = "Herbs", color = "moss" }))
local p2 = assert(PN.AddLocal({ map = 1429, x = 100, y = 200 }))
assert(p1.id == "L1" and p2.id == "L2" and p2.name == "Pin 2" and p2.color == "gold", "a generated name and the default color")
assert(PN.UpdateLocal("L1", { name = "Peacebloom", color = "river" }))
assert(PN.FindLocal("L1").name == "Peacebloom" and PN.FindLocal("L1").map == 1429 and PN.FindLocal("L1").x == 4521, "a rename keeps id and place")
assert(not PN.UpdateLocal("L1", { name = "   " }), "an empty name is refused")
assert(not PN.UpdateLocal("L1", { color = "neon" }), "an unknown color is refused")
assert(select(2, PN.AddLocal({ map = 99999, x = 1, y = 1 })) == "unknown-map")
assert(select(2, PN.AddLocal({ map = 1429, x = 10001, y = 1 })) == "bad-coordinates")
assert(PN.RemoveLocal("L2") and PN.LocalCount() == 1)
local p3 = assert(PN.AddLocal({ map = 1429, x = 1, y = 1, name = "Third" }))
assert(p3.id == "L3", "a removed id is never given out again")
-- a damaged saved entry is skipped, not erased
table.insert(a.TwichUIDB.pins.list, { id = "L9", map = 1429, x = "bad", y = 3, name = "x" })
assert(PN.LocalCount() == 2 and #a.TwichUIDB.pins.list == 3)
a.TwichUIDB.pins.nextId = 9   -- as if the counter had fallen behind the kept entry
local savedA = a.TwichUIDB
local a2 = boot(A, savedA)
assert(a2.TwichUI.Pins.LocalCount() == 2 and a2.TwichUI.Pins.FindLocal("L1").name == "Peacebloom", "local pins come back after a reload")
assert(a2.TwichUI.Pins.AddLocal({ map = 1429, x = 5, y = 5 }).id == "L10", "a new id never repeats a kept entry's, even an unreadable one")
CLIENTS[A] = nil

---------------------------------------------------------------------------
-- 3. Not in a party: local pins work, party pins are refused, nothing is sent
---------------------------------------------------------------------------
GROUP = nil; RAID = false; NET = {}; SENT_LOG = {}
a = boot(A); local b = boot(B); local c = boot(C)
PN, PS = a.TwichUI.Pins, a.TwichUI.PinSync
assert(PN.AddLocal({ map = 1429, x = 1, y = 1, name = "Solo" }))
local none, why = PS.CreateParty({ map = 1429, x = 1, y = 1, name = "x" })
assert(none == nil and why == "no-party", tostring(why))
assert(sent("TwichUIPins") == 0, "nothing sent outside a party")

---------------------------------------------------------------------------
-- 4. Joining a party: sessions start; a party pin reaches every member with its name and color
---------------------------------------------------------------------------
GROUP = { [A] = true, [B] = true, [C] = true }
for _, x in ipairs({ a, b, c }) do x.FireEvent("GROUP_ROSTER_UPDATE") end
settle()
assert(PN.SessionOpen() and b.TwichUI.Pins.SessionOpen())
local camp = assert(PS.CreateParty({ map = 1429, x = 4000, y = 5000, name = "|cffff0000Camp|r here", color = "ember" }))
assert(camp.name == "Camp here" and camp.mine)
settle()
local BPN = b.TwichUI.Pins
local onB = BPN.Shared(BPN.Key(A, camp.id))
assert(onB and onB.name == "Camp here" and onB.color == "ember" and onB.x == 4000 and onB.owner == A and not onB.mine, "B got A's pin")
assert(c.TwichUI.Pins.Shared(BPN.Key(A, camp.id)), "C got it too")
assert(#BPN.LocalPins() == 0, "a party pin is not saved as a local pin")

-- an owner's rename and recolor is the same pin, one revision on
assert(PS.UpdateParty(camp.key, { name = "Night camp", color = "violet" }))
settle()
onB = BPN.Shared(BPN.Key(A, camp.id))
assert(onB.name == "Night camp" and onB.color == "violet" and onB.rev == 2 and BPN.SharedCount() == 1, "an edit keeps the identity")

---------------------------------------------------------------------------
-- 5. Ownership comes from the sender: B can't change, remove or even name A's pins
---------------------------------------------------------------------------
local ok, reason = b.TwichUI.PinSync.UpdateParty(onB.key, { name = "Mine now" })
assert(not ok and reason:find("Only the player"), "a recipient can't edit")
ok, reason = b.TwichUI.PinSync.RemoveForParty(onB.key)
assert(not ok and reason:find("Only the player"), "a recipient can't remove it for the party")
-- a forged removal naming A's id, sent by B, only ever addresses B's own pins
local LibSerialize, LibDeflate = b.LibStub("LibSerialize"), b.LibStub("LibDeflate")
-- One message as the game would hand it to `env`, from `from`. Two seconds pass first (the sender's
-- steady rate) unless burst is set.
local function inject(env, from, msg, dist, burst)
  if not burst then tick() end
  local text = LibDeflate:EncodeForWoWAddonChannel(LibSerialize:Serialize(msg))
  env._comm.TwichUIPins("TwichUIPins", text, dist or "PARTY", from)
end
inject(c, B, { v = 1, o = "put", p = { id = camp.id, r = 50, m = 1429, x = 1, y = 1, n = "Hijack", c = "gold" } })
assert(c.TwichUI.Pins.Shared(BPN.Key(B, camp.id)).name == "Hijack", "a put naming A's id only makes a pin of B's own")
inject(c, B, { v = 1, o = "del", id = camp.id, r = 99 })
assert(not c.TwichUI.Pins.Shared(BPN.Key(B, camp.id)), "...and B's removal only removes that one")
local onC = c.TwichUI.Pins.Shared(BPN.Key(A, camp.id))
assert(onC and onC.name == "Night camp" and onC.x == 4000, "A's pin is untouched by B's messages")

---------------------------------------------------------------------------
-- 6. Validation of what arrives
---------------------------------------------------------------------------
local CP = c.TwichUI.Pins
local before = CP.SharedCount()
local function drops(code) return CP.drops[code] or 0 end
local d0 = drops("unknown-map")
inject(c, B, { v = 1, o = "put", p = { id = "zz:1", r = 1, m = 99999, x = 1, y = 1, n = "x", c = "gold" } })
assert(drops("unknown-map") == d0 + 1)
inject(c, B, { v = 1, o = "put", p = { id = "zz:2", r = 1, m = 1429, x = 20000, y = 1, n = "x", c = "gold" } })
inject(c, B, { v = 1, o = "put", p = { id = "zz:3", r = 1, m = 1429, x = 0 / 0, y = 1, n = "x", c = "gold" } })
inject(c, B, { v = 1, o = "put", p = { id = "zz:4", r = 1, m = 1429, x = 1.5, y = 1, n = "x", c = "gold" } })
assert(drops("bad-coordinates") >= 3)
inject(c, B, { v = 1, o = "put", p = { id = "zz:5", r = 1, m = 1429, x = 1, y = 1, n = "|||", c = "gold" } })
assert(drops("bad-name") >= 1, "a name with nothing left is refused")
inject(c, B, { v = 1, o = "put", p = { id = "bad id!", r = 1, m = 1429, x = 1, y = 1, n = "x", c = "gold" } })
assert(drops("bad-id") >= 1)
inject(c, B, { v = 2, o = "put", p = {} })
assert(drops("newer-protocol") >= 1, "a newer protocol is set aside, not guessed at")
inject(c, B, { v = 1, o = "explode" })
assert(drops("unknown-op") >= 1)
inject(c, B, { v = 1, o = "put", p = { id = "zz:6", r = 1, m = 1429, x = 1, y = 1, n = "x", c = "gold" } }, "RAID")
inject(c, B, { v = 1, o = "put", p = { id = "zz:7", r = 1, m = 1429, x = 1, y = 1, n = "x", c = "gold" } }, "WHISPER")
assert(drops("channel") >= 2, "only the party's channel")
inject(c, "Stranger Danger", { v = 1, o = "put", p = { id = "zz:8", r = 1, m = 1429, x = 1, y = 1, n = "x", c = "gold" } })
assert(drops("not-member") >= 1, "someone outside the party is ignored")
c._comm.TwichUIPins("TwichUIPins", "garbage\0\1", "PARTY", B)
c._comm.TwichUIPins("TwichUIPins", string.rep("x", 5000), "PARTY", B)
assert(drops("too-large") >= 1 and drops("undecodable") >= 1)
inject(c, B, { v = 1, o = "put", p = { id = "zz:9", r = 1, m = 1429, x = 1, y = 1, n = "Odd color", c = "neon" } })
assert(CP.Shared(CP.Key(B, "zz:9")).color == "gold" and drops("color-unknown") >= 1, "an unknown color is drawn in the default")
assert(CP.SharedCount() == before + 1, "only the valid pin was kept")
CP.ApplyDel(B, "zz:9", 2)

---------------------------------------------------------------------------
-- 7. Duplicates, out of order, stale revisions
---------------------------------------------------------------------------
local key = CP.Key(B, "dup:1")
inject(c, B, { v = 1, o = "put", p = { id = "dup:1", r = 3, m = 1429, x = 1, y = 1, n = "Third", c = "gold" } })
inject(c, B, { v = 1, o = "put", p = { id = "dup:1", r = 2, m = 1429, x = 1, y = 1, n = "Second", c = "gold" } })
inject(c, B, { v = 1, o = "put", p = { id = "dup:1", r = 3, m = 1429, x = 1, y = 1, n = "Third again", c = "gold" } })
assert(CP.Shared(key).name == "Third" and drops("stale") >= 2, "older and repeated revisions are ignored")
inject(c, B, { v = 1, o = "del", id = "dup:1", r = 4 })
assert(not CP.Shared(key))
inject(c, B, { v = 1, o = "put", p = { id = "dup:1", r = 3, m = 1429, x = 1, y = 1, n = "Late", c = "gold" } })
inject(c, B, { v = 1, o = "put", p = { id = "dup:1", r = 9, m = 1429, x = 1, y = 1, n = "Replay", c = "gold" } })
assert(not CP.Shared(key) and drops("deleted") >= 2, "a removed pin can't come back, whatever its revision")
-- a removal that arrives before the pin itself
inject(c, B, { v = 1, o = "del", id = "early:1", r = 2 })
inject(c, B, { v = 1, o = "put", p = { id = "early:1", r = 1, m = 1429, x = 1, y = 1, n = "Too late", c = "gold" } })
assert(not CP.Shared(CP.Key(B, "early:1")), "a removal seen first still wins")

---------------------------------------------------------------------------
-- 8. Remove from my map: local only, nothing sent, survives a resync and later revisions
---------------------------------------------------------------------------
local bKey = BPN.Key(A, camp.id)
local sentBefore = #SENT_LOG
assert(BPN.Dismiss(bKey))
assert(#SENT_LOG == sentBefore, "dismissing sends nothing")
assert(PN.Shared(camp.key) and CP.Shared(bKey) and not CP.IsDismissed(bKey), "the owner and C still have it")
-- the owner may dismiss their own too: still nothing sent, still on B's and C's maps
assert(PN.Dismiss(camp.key) and #SENT_LOG == sentBefore and CP.Shared(bKey))
assert(PN.Restore(camp.key))
-- resync: C says hello, A answers with its full list; B's dismissal holds
b.TwichUI.PinSync.SayHello(); settle(); RunLongTimers(10); settle()
assert(BPN.Shared(bKey) and BPN.IsDismissed(bKey), "a resync doesn't bring back what you removed from your map")
assert(PS.UpdateParty(camp.key, { name = "Moved camp" })); settle()
assert(BPN.Shared(bKey).name == "Moved camp" and BPN.IsDismissed(bKey), "an update changes it but keeps it off your map")
assert(not BPN.Can("dismiss", { kind = "party", pin = BPN.Shared(bKey) }) and BPN.Can("restore", { kind = "party", pin = BPN.Shared(bKey) }))
assert(BPN.Restore(bKey) and not BPN.IsDismissed(bKey))
-- Dismiss all on your map: nothing sent
sentBefore = #SENT_LOG
assert(BPN.DismissAll() >= 1 and #SENT_LOG == sentBefore)
BPN.Restore(bKey)

---------------------------------------------------------------------------
-- 9. A local copy outlives the original; removing the original for the party
---------------------------------------------------------------------------
local copy = assert(BPN.KeepCopy(bKey))
assert(copy.name == "Moved camp" and copy.copiedFrom == "Ranulf Ashenvow" and copy.id:find("^L"), "an independent local pin")
-- C dismissed it, then the owner removes it for the party: gone from B and C, B's copy stays
assert(CP.Dismiss(bKey))
assert(PS.RemoveForParty(camp.key))
assert(not PN.Shared(camp.key))
settle()
assert(not BPN.Shared(bKey) and not CP.Shared(bKey) and not CP.IsDismissed(bKey), "gone for everyone with TwichUI")
assert(BPN.FindLocal(copy.id), "B's local copy is untouched")
-- the old put arriving late (or replayed) doesn't revive it
inject(b, A, { v = 1, o = "put", p = { id = camp.id, r = 3, m = 1429, x = 1, y = 1, n = "Ghost", c = "gold" } })
assert(not BPN.Shared(bKey))
-- removing it again is refused at the moment it runs (it's gone)
ok, reason = PS.RemoveForParty(camp.key)
assert(not ok and reason:find("no longer"), tostring(reason))

---------------------------------------------------------------------------
-- 10. A member who missed messages catches up from the owner's full list
---------------------------------------------------------------------------
local k1 = assert(PS.CreateParty({ map = 1429, x = 10, y = 10, name = "Keep" }))
local k2 = assert(PS.CreateParty({ map = 1429, x = 20, y = 20, name = "Drop" }))
settle()
assert(CP.Shared(CP.Key(A, k2.id)))
-- C misses the removal of k2 and a rename of k1
assert(PS.RemoveForParty(k2.key)); assert(PS.UpdateParty(k1.key, { name = "Kept" }))
for i = #NET, 1, -1 do NET[i].missedByC = true end
-- deliver to B only
GROUP = { [A] = true, [B] = true }; Pump(); GROUP = { [A] = true, [B] = true, [C] = true }
assert(CP.Shared(CP.Key(A, k2.id)) and CP.Shared(CP.Key(A, k1.id)).name == "Keep", "C missed both")
c.TwichUI.PinSync.SayHello(); settle(); RunLongTimers(10); settle()
assert(not CP.Shared(CP.Key(A, k2.id)), "the full list removes what C missed being removed")
assert(CP.Shared(CP.Key(A, k1.id)).name == "Kept", "and brings the rename")
-- several hellos at once get one answer
local lists = PS.Snapshot().lists
inject(a, B, { v = 1, o = "hi" }); inject(a, C, { v = 1, o = "hi" }); inject(a, B, { v = 1, o = "hi" })
RunLongTimers(10); settle()
assert(PS.Snapshot().lists == lists + 1, "hellos are answered once, not once each")
-- someone with no pins of their own doesn't answer at all
local cLists = c.TwichUI.PinSync.Snapshot().lists
inject(c, B, { v = 1, o = "hi" }); RunLongTimers(10); settle()
assert(c.TwichUI.PinSync.Snapshot().lists == cLists, "no answer from someone who never made a party pin")

---------------------------------------------------------------------------
-- 11. Limits and rate
---------------------------------------------------------------------------
for i = 1, PN.MAX_PER_OWNER - PN.OwnCount() do assert(PS.CreateParty({ map = 1429, x = i, y = i })) end
none, why = PS.CreateParty({ map = 1429, x = 1, y = 1 })
assert(none == nil and why == "owner-limit")
settle()
-- per owner on arrival
local fake = {}
for i = 1, PN.MAX_PER_OWNER + 3 do fake[i] = { id = "fl:" .. i, r = 1, m = 1429, x = 1, y = 1, n = "F" .. i, c = "gold" } end
local accepted = CP.ApplyAll(B, { unpack(fake, 1, PN.MAX_PER_OWNER) })
assert(accepted and CP.Shared(CP.Key(B, "fl:20")))
assert(not CP.ApplyAll(B, fake), "a list longer than the limit is refused whole")
inject(c, B, { v = 1, o = "put", p = fake[PN.MAX_PER_OWNER + 1] })
assert(not CP.Shared(CP.Key(B, "fl:21")) and drops("owner-limit") >= 1)
-- rate: a burst past the bucket from one sender is dropped
local r0 = drops("rate")
for i = 1, 40 do inject(c, B, { v = 1, o = "put", p = { id = "rt:" .. i, r = 1, m = 1429, x = 1, y = 1, n = "R", c = "gold" } }, nil, true) end
assert(drops("rate") > r0, "a flood from one sender is dropped")
-- dismissal and removal records stay bounded
for i = 1, PN.MAX_DELETED + 30 do CP.ApplyDel(B, "tomb:" .. i, 1) end
assert(CP.Snapshot().deleted <= PN.MAX_DELETED)

---------------------------------------------------------------------------
-- 12. Group changes: a member leaving, a raid, leaving the party
---------------------------------------------------------------------------
assert(#CP.Owners() >= 1)
GROUP = { [A] = true, [C] = true }
c.FireEvent("GROUP_ROSTER_UPDATE")
for _, p in ipairs(CP.SharedPins()) do assert(p.owner ~= B, "B left: B's pins go") end
assert(CP.Shared(CP.Key(A, k1.id)), "A's stay")
-- a raid pauses: nothing sent, nothing taken in, the pins stay; back in a party they catch up
RAID = true
c.FireEvent("GROUP_ROSTER_UPDATE"); a.FireEvent("GROUP_ROSTER_UPDATE")
none, why = PS.CreateParty({ map = 1429, x = 1, y = 1 })
assert(none == nil and why == "paused")
assert(not PN.Can("removeParty", { kind = "party", pin = PN.Shared(k1.key) }))
assert(CP.Shared(CP.Key(A, k1.id)), "pins stay while paused")
inject(c, A, { v = 1, o = "put", p = { id = "raid:1", r = 1, m = 1429, x = 1, y = 1, n = "x", c = "gold" } })
assert(not CP.Shared(CP.Key(A, "raid:1")))
RAID = false
local hellos = c.TwichUI.PinSync.Snapshot().hellos
c.FireEvent("GROUP_ROSTER_UPDATE"); a.FireEvent("GROUP_ROSTER_UPDATE")
assert(c.TwichUI.PinSync.Snapshot().hellos == hellos, "the hello waits for the others' rosters")
RunLongTimers(5)
assert(c.TwichUI.PinSync.Snapshot().hellos == hellos + 1, "back in a party: a hello to catch up")
settle(); RunLongTimers(10); settle()
-- leaving the party ends the session: party pins, dismissals and records go; local pins and copies stay
local localBefore = BPN.LocalCount()
GROUP = { [A] = true, [C] = true }
b.FireEvent("GROUP_ROSTER_UPDATE")
assert(not BPN.SessionOpen() and BPN.SharedCount() == 0 and BPN.LocalCount() == localBefore)
-- joining another party starts fresh: nothing of the old one carries over
GROUP = { [B] = true, ["Dax Ironwood"] = true }
b.FireEvent("GROUP_ROSTER_UPDATE")
assert(BPN.SessionOpen() and BPN.SharedCount() == 0 and BPN.Snapshot().deleted == 0)
-- ...and leaving it again before its hello goes out: the hello is never sent into whatever comes next
local bHellos = b.TwichUI.PinSync.Snapshot().hellos
GROUP = { [A] = true, [C] = true }
b.FireEvent("GROUP_ROSTER_UPDATE")
RunLongTimers(10)
assert(b.TwichUI.PinSync.Snapshot().hellos == bHellos, "a timer from an ended session does nothing")

---------------------------------------------------------------------------
-- 13. Reload: kept while still in the party; a fresh login starts empty
---------------------------------------------------------------------------
local ownBefore = PN.OwnCount()
assert(CP.Dismiss(CP.Key(A, k1.id)))
a.FireEvent("PLAYER_LOGOUT"); c.FireEvent("PLAYER_LOGOUT")
assert(type(c.TwichUIDB.pins.session) == "table")
CLIENTS[A], CLIENTS[C] = nil, nil
local a3 = boot(A, a.TwichUIDB, true); local c3 = boot(C, c.TwichUIDB, true)
local A3, C3 = a3.TwichUI.Pins, c3.TwichUI.Pins
assert(A3.OwnCount() == ownBefore and A3.Shared(k1.key).mine, "your own party pins come back after a reload")
assert(C3.Shared(C3.Key(A, k1.id)) and C3.IsDismissed(C3.Key(A, k1.id)), "and what you removed from your map stays removed")
assert(c3.TwichUIDB.pins.session == nil, "the kept copy is for one load only")
-- a fresh login (not a reload) starts empty even in the same party
c3.FireEvent("PLAYER_LOGOUT")
CLIENTS[C] = nil
local c4 = boot(C, c3.TwichUIDB)
assert(c4.TwichUI.Pins.SharedCount() == 0 and c4.TwichUIDB.pins.session == nil, "a login doesn't carry party pins over")
-- a reload outside a party doesn't restore either
c4.FireEvent("PLAYER_LOGOUT")
GROUP = { [A] = true }
CLIENTS[C] = nil
local c5 = boot(C, c4.TwichUIDB, true)
assert(c5.TwichUI.Pins.SharedCount() == 0)
GROUP = { [A] = true, [C] = true }

---------------------------------------------------------------------------
-- 14. Turning it off ends the session and ignores messages; local pins stay
---------------------------------------------------------------------------
local localA = a3.TwichUI.Pins.LocalCount()
a3.TwichUIDB.modules.partyPins = false
a3.TwichUI.PinSync.Refresh()
assert(not a3.TwichUI.Pins.SessionOpen() and a3.TwichUI.Pins.LocalCount() == localA)
inject(a3, C, { v = 1, o = "put", p = { id = "off:1", r = 1, m = 1429, x = 1, y = 1, n = "x", c = "gold" } })
assert(a3.TwichUI.Pins.SharedCount() == 0)
assert(not a3.TwichUI.Pins.Can("show", { kind = "local", pin = a3.TwichUI.Pins.LocalPins()[1] }), "actions say it is off")
a3.FireEvent("PLAYER_LOGOUT")
assert(a3.TwichUIDB.pins.session == nil, "nothing kept for a reload while it is off")

---------------------------------------------------------------------------
-- 15. Saved data holds only plain pin records; diagnostics hold no names, places or text
---------------------------------------------------------------------------
for k in pairs(a3.TwichUIDB.pins) do assert(k == "list" or k == "nextId", "undeclared field in TwichUIDB.pins: " .. tostring(k)) end
local snap = C3.Snapshot()
local sync = c3.TwichUI.PinSync.Snapshot()
local function contains(t, needle)
  for k, v in pairs(t) do
    if type(v) == "table" then if contains(v, needle) then return true end
    elseif tostring(v):find(needle, 1, true) or tostring(k):find(needle, 1, true) then return true end
  end
end
for _, needle in ipairs({ "Ranulf", "Pal", "Cora", "Kept", "Elwynn", "1429" }) do
  assert(not contains(snap, needle) and not contains(sync, needle), "diagnostics must not hold " .. needle)
end
assert(sync.protocol == 1 and sync.prefix == "TwichUIPins")

print("PARTY PINS TESTS PASSED")
