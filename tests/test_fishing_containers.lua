-- TwichUI Fishing: containers caught while fishing (TwichUI_Fishing/Containers.lua). Recognition, the queue and its
-- provenance, opening by the player's press, contents attribution, several clams, full bags, failed and locked opens, a clam
-- opened by hand, the queue following the bags, automatic opening that works or is blocked, unrelated containers, and the
-- provenance later valuation reads without counting anything twice. Simulated client (tests/fishing_mock.lua).
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY, OPEN = "CLICK TwichUIFishingButton:LeftButton", "CLICK TwichUIFishingOpen:LeftButton"

local function Fresh(opts)
  local c, W = FishingClient(opts)
  W.bound.F, W.bound.G = KEY, OPEN
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  W.Wear(16, POLE)
  return c, W, c.TwichUI.Fishing
end
local function Catch(W, slots) W.StartLine(); W.Loot(slots, { fishing = true }); W.StopLine(); W.Advance(2) end
local function Unopened(F) return F.Containers.Status().unopened end

---------------------------------------------------------------------------
-- A clam from fishing is queued; nothing about its contents is assumed
---------------------------------------------------------------------------
local c, W, F = Fresh()
Catch(W, { { FISH1, 1 }, { CLAM, 1 } })
local s = F.Session.Current()
Check(Unopened(F) == 1 and F.API.Queue()[1].item == CLAM and F.API.Queue()[1].sid == s.id, "the clam is queued with its session")
Check(s.containers[CLAM].caught == 1 and s.containers[CLAM].opened == 0, "recorded as a container caught")
Check(next(s.contents) == nil and s.species[CLAM].q == 1, "nothing about its contents is assumed")
-- a clam that did not come from fishing is never queued
W.Give(BIGCLAM); W.Settle()
W.Loot({ { BIGCLAM, 1 } }, { fishing = false })
Check(Unopened(F) == 1, "containers from elsewhere are not queued")

---------------------------------------------------------------------------
-- The fishing key opens it between casts, and its contents are attributed
---------------------------------------------------------------------------
local seen = {}
F.Subscribe("ITEM", function(_, id, q, how, sid, from) seen[#seen + 1] = { id = id, q = q, how = how, sid = sid, from = from } end)
Check(W.Key("F") == "item" and F.Action.last.kind == "open", "the next press opens the clam rather than casting")
W.Advance(3)
s = F.Session.Current()
Check(Unopened(F) == 0 and #F.API.Queue() == 0, "opened: off the queue")
Check(s.containers[CLAM].opened == 1 and s.containers[CLAM].got[PEARL] == 1 and s.containers[CLAM].got[CLAMMEAT] == 1, "what it held, kept with the clam")
Check(s.contents[PEARL] == 1 and s.species[PEARL] == nil, "contents are not catches")
Check(s.items == 2 and s.catches == 1, "the catch count is unchanged by opening")
Check(seen[1].how == "content" and seen[1].from == CLAM and seen[1].sid == s.id, "notified with provenance")
Check(W.Key("F") == "spell", "then the key casts")
W.Key("F"); W.Advance(2)
-- the open key does the same, and the fishing key can be told not to
c.TwichUI.RunCommand("fish containers key off")
Catch(W, { { CLAM, 1 } })
Check(W.Key("F") == "spell", "containers key off: the fishing key casts")
W.Key("F"); W.Advance(2)
Check(W.Key("G") == "item" and F.Action.last.kind == "cast", "the open key opens it")
W.Advance(3)
Check(Unopened(F) == 0 and F.Session.Current().containers[CLAM].opened == 2, "opened by the open key")
c.TwichUI.RunCommand("fish containers key on")

---------------------------------------------------------------------------
-- Several clams, oldest first; learning a container from the bags
---------------------------------------------------------------------------
Catch(W, { { CLAM, 1 } })
Catch(W, { { BIGCLAM, 1 } })
Catch(W, { { CLAM, 1 } })
Check(Unopened(F) == 3 and #F.API.Queue() == 3, "three clams in three lots")
Catch(W, { { BLOATED, 1 } })
Check(Unopened(F) == 4 and F.Store.IsKnownContainer(BLOATED), "an unknown item the bags call openable is learned as a container")
Catch(W, { { FISH2, 1 } })
Check(Unopened(F) == 4 and not F.Store.IsKnownContainer(FISH2), "a plain fish is not")
W.contents[BLOATED] = { { FISH1, 1 } }
local directFish = F.Session.Current().species[FISH1].q
for _ = 1, 4 do W.Key("G"); W.Advance(3) end
s = F.Session.Current()
Check(Unopened(F) == 0, "all four opened, one press each")
Check(s.containers[BIGCLAM].got[PEARL] == 2 and s.containers[BLOATED].got[FISH1] == 1, "each with its own contents")
Check(s.contents[FISH1] == 1 and s.species[FISH1].q == directFish, "a fish from a container is a content, never a direct catch")

---------------------------------------------------------------------------
-- Full bags, a failed open, a locked one
---------------------------------------------------------------------------
Catch(W, { { CLAM, 1 } })
local free = W.FreeCount()
for i = 1, free do W.Give(3100 + i) end
W.Settle()
Check(W.Key("G") == nil and W.errors[#W.errors]:find("room"), "bags full: not opened, and said")
Check(Unopened(F) == 1, "still queued")
for b = 0, 4 do for sl = 1, W.bagSize do local e = W.bags[b][sl]; if e and e.id > 3100 and e.id < 3200 then W.bags[b][sl] = nil end end end
W.holdContainers = true
W.Key("G")
W.Advance(4)
W.holdContainers = false
Check(Unopened(F) == 1 and F.noteCounts["open-failed"] == 1 and F.Session.Current().containers[CLAM].failed == 1, "no loot window: a failed open, still queued")
W.locked[CLAM] = true
W.Key("G"); W.Advance(1)
Check(F.API.Queue()[1].locked and F.noteCounts["container-locked"] == 1, "a locked container is marked and skipped")
Check(F.Containers.Plan(false) == nil, "and not offered again")
W.locked[CLAM] = nil
F.API.Queue()   -- read only
F.Containers.Queue()[1].locked = nil

---------------------------------------------------------------------------
-- Opened with bags too full for everything: the container stays, what was taken is attributed
---------------------------------------------------------------------------
local realOpen = W.OpenContainer
W.OpenContainer = function(b, sl) realOpen(b, sl, { take = function(i) return i == 1 end, keep = true }) end
W.Key("G"); W.Advance(3)
W.OpenContainer = realOpen
s = F.Session.Current()
Check(Unopened(F) == 1 and F.Containers.Queue()[1].partial, "the clam is still in the bags: still queued")
Check(s.containers[CLAM].got[PEARL] >= 1, "what was taken is counted")
W.Key("G"); W.Advance(3)
Check(Unopened(F) == 0, "the next press finishes it")

---------------------------------------------------------------------------
-- Opened by hand (right-click): matched only when exactly one queued container left the bags
---------------------------------------------------------------------------
Catch(W, { { CLAM, 1 } })
local before = F.Session.Current().containers[CLAM].opened
W.OpenContainer(W.Find(CLAM))
W.Advance(3)
Check(Unopened(F) == 0 and F.Session.Current().containers[CLAM].opened == before + 1, "a hand-opened queued clam is matched")
-- a container from elsewhere opened by hand, while one from fishing is queued: not attributed
Catch(W, { { CLAM, 1 } })
W.Give(CRATE); W.Settle()
local contents = F.Session.Current().contents[JUNK]
W.OpenContainer(W.Find(CRATE))
W.Advance(3)
Check(Unopened(F) == 1 and F.Session.Current().contents[JUNK] == contents, "another container's loot is not fishing's")

---------------------------------------------------------------------------
-- The queue follows the bags (sold, destroyed)
---------------------------------------------------------------------------
local b0, s0 = W.Find(CLAM); W.bags[b0][s0] = nil; W.Settle()
Check(Unopened(F) == 0 and F.noteCounts["queue-trimmed"] == 1, "a queued clam that left the bags is dropped")

---------------------------------------------------------------------------
-- Across sessions and a reload: contents go to the session the clam was caught in
---------------------------------------------------------------------------
c.TwichUI.RunCommand("fish stop")
Catch(W, { { CLAM, 1 } })
local sid = F.Session.Current().id
c.TwichUI.RunCommand("fish stop")
local saved = FishRoundTrip(c.TwichUIFishingDB)
local c2, W2 = FishingClient({ db = saved, epoch = W.epoch + 60 })
W2.bound.G = OPEN; W2.bags = W.bags; W2.equipped = W.equipped
c2.FireEvent("UPDATE_BINDINGS"); W2.Advance(1)
local F2 = c2.TwichUI.Fishing
Check(F2.Containers.Status().unopened == 1 and F2.API.Queue()[1].sid == sid, "the queue survives a reload")
W2.Key("G"); W2.Advance(3)
local old = F2.API.Sessions(1)[1]
Check(old.id == sid and old.containers[CLAM].opened == 1 and old.containers[CLAM].got[PEARL] == 1, "contents credited to the session it was caught in")
Check(F2.Session.Current() == nil, "opening a clam later does not start a fishing session")

---------------------------------------------------------------------------
-- Provenance for valuation: nothing counted twice
---------------------------------------------------------------------------
local p = F2.API.Provenance(sid)
Check(p.direct[CLAM] == nil and p.containers[CLAM].caught == 1 and p.containers[CLAM].opened == 1 and p.containers[CLAM].unopened == 0, "a caught container is a container, not a direct catch")
Check(p.contents[PEARL] == 1, "and what it held is listed apart")
local life = F2.API.Provenance("lifetime")
Check(life.direct[FISH1] and life.direct[FISH2] and life.direct[CLAM] == nil and life.direct[BIGCLAM] == nil, "lifetime: fish are direct, containers are not")
Check(life.contents[PEARL] >= 4, "lifetime contents")

---------------------------------------------------------------------------
-- Automatic opening: used when the client allows it; turned off for good the first time it is blocked
---------------------------------------------------------------------------
do
  local c3, W3, F3 = Fresh()
  c3.TwichUI.RunCommand("fish containers auto")
  Catch(W3, { { CLAM, 1 } })
  W3.Advance(2)
  Check(F3.Containers.Status().unopened == 0 and W3.calls.use == 1, "opened automatically after the catch")
  Check(F3.Containers.Status().autoOpen == "worked", "and the client's answer is remembered")
  Check(F3.Session.Current().containers[CLAM].got[PEARL] == 1, "with its contents attributed")
  -- never during a line, in combat or while looting
  W3.StartLine()
  W3.Loot({ { CLAM, 1 } }, { fishing = true })
  W3.Advance(2)
  Check(F3.Containers.Status().unopened == 1 and W3.calls.use == 1, "not while the line is out")
  W3.StopLine(); W3.Fight(); W3.Advance(3)
  Check(W3.calls.use == 1, "not in combat")
  W3.Peace()
  local c4, W4, F4 = Fresh()
  c4.TwichUI.RunCommand("fish containers auto")
  W4.blockInsecure.use = true
  Catch(W4, { { CLAM, 1 } })
  W4.Advance(3)
  Check(F4.Containers.Status().autoOpen == "blocked" and F4.Containers.Status().unopened == 1, "blocked: remembered, the clam stays queued")
  Check(W4.errors[#W4.errors]:find("doesn't allow"), "and said once")
  Catch(W4, { { CLAM, 1 } })
  W4.Advance(3)
  Check(W4.calls.use == 1, "never tried again")
  W4.blockInsecure.use = false
  Check(W4.Key("F") == "item" and F4.Action.last.kind == "open", "the fishing key opens it instead")
  c4.TwichUI.RunCommand("fish containers off")
  Catch(W4, { { CLAM, 1 } })
  Check(F4.Containers.Plan(true) == nil and F4.Containers.Status().unopened >= 1, "off: recorded, never opened by TwichUI")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_containers")
