-- Lifecycle: the shared event bus and world state (Core.lua), and the module-level behaviour that
-- depends on them. Mocks cannot show combat-lockdown or protected-frame behaviour; they show that
-- our own bookkeeping is right: handlers run once, removal during dispatch is safe, stale callbacks
-- do nothing, and state is settled when a feature is switched off.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", {"!!!TwichUI"})
local ERRORS = {}
c.geterrorhandler = function() return function(e) ERRORS[#ERRORS + 1] = tostring(e) end end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI

local function Fail(msg) error(msg, 2) end
local function Eq(a, b, msg) if a ~= b then Fail(("%s: expected %s, got %s"):format(msg, tostring(b), tostring(a))) end end

---------------------------------------------------------------------------
-- 1. The bus: a handler that removes itself (or another) while the event is being delivered
---------------------------------------------------------------------------
do
  local log = {}
  local function A() log[#log + 1] = "A" end
  local function Self() log[#log + 1] = "self"; R:Off("TEST_EVENT", Self) end
  local function B() log[#log + 1] = "B" end
  local function Cc() log[#log + 1] = "C" end
  R:On("TEST_EVENT", A); R:On("TEST_EVENT", Self); R:On("TEST_EVENT", B); R:On("TEST_EVENT", Cc)
  c.FireEvent("TEST_EVENT")
  Eq(table.concat(log, ","), "A,self,B,C", "every listener runs once even when one removes itself")
  Eq(#ERRORS, 0, "no error raised by removal during delivery: " .. table.concat(ERRORS, "; "))
  log = {}
  c.FireEvent("TEST_EVENT")
  Eq(table.concat(log, ","), "A,B,C", "the removed listener stays removed")

  -- removing another listener that has not run yet: it must not run
  log = {}
  local Victim
  local function Killer() log[#log + 1] = "killer"; R:Off("TEST_EVENT_2", Victim) end
  Victim = function() log[#log + 1] = "victim" end
  R:On("TEST_EVENT_2", Killer); R:On("TEST_EVENT_2", Victim)
  c.FireEvent("TEST_EVENT_2")
  Eq(table.concat(log, ","), "killer", "a listener removed before its turn does not run")
  Eq(#ERRORS, 0, "no error: " .. table.concat(ERRORS, "; "))

  -- the last listener removing itself unregisters the event once delivery is over
  local function Only() R:Off("TEST_EVENT_3", Only) end
  R:On("TEST_EVENT_3", Only)
  c.FireEvent("TEST_EVENT_3")
  Eq(R.frame.events.TEST_EVENT_3, nil, "event unregistered after its last listener left")

  -- a listener added during delivery is kept, and first runs on the next delivery
  log = {}
  local function Late() log[#log + 1] = "late" end
  local function Adder() log[#log + 1] = "adder"; R:On("TEST_EVENT_4", Late); R:Off("TEST_EVENT_4", Adder) end
  R:On("TEST_EVENT_4", Adder)
  c.FireEvent("TEST_EVENT_4")
  c.FireEvent("TEST_EVENT_4")
  Eq(table.concat(log, ","), "adder,late", "added during delivery, runs from the next one")
  Eq(R.frame.events.TEST_EVENT_4, true, "event stays registered for the listener added during delivery")
end

---------------------------------------------------------------------------
-- 2. Registering the same listener twice is one registration
---------------------------------------------------------------------------
do
  local n = 0
  local function Once() n = n + 1 end
  R:On("TEST_EVENT_5", Once); R:On("TEST_EVENT_5", Once)
  c.FireEvent("TEST_EVENT_5")
  Eq(n, 1, "same function registered twice runs once")
  R:Off("TEST_EVENT_5", Once)
  c.FireEvent("TEST_EVENT_5")
  Eq(n, 1, "one Off removes it")
  Eq(R.frame.events.TEST_EVENT_5, nil, "and the event is released")
end

---------------------------------------------------------------------------
-- 3. World state
---------------------------------------------------------------------------
do
  local L = R.Life
  assert(L, "R.Life exists")
  Eq(L.InWorld(), false, "not in the world before the first loading screen ends")
  c.FireEvent("PLAYER_LOGIN")
  Eq(L.Snapshot().loggedIn, true, "login seen")
  Eq(L.InWorld(), false, "login alone is not the world")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Eq(L.InWorld(), true, "in the world after PLAYER_ENTERING_WORLD")
  c.FireEvent("PLAYER_LEAVING_WORLD")
  Eq(L.InWorld(), false, "out of the world while a loading screen is up")
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false)
  Eq(L.InWorld(), true, "back after the loading screen")
  Eq(L.Snapshot().worldEntries, 2, "entries are counted, not mistaken for fresh logins")

  -- reason codes: bounded, stable, no free text
  for i = 1, 200 do L.Note("code-" .. i) end
  local seen = 0
  for _ in pairs(L.Snapshot().notes) do seen = seen + 1 end
  assert(seen <= 32, "reason codes are bounded (" .. seen .. ")")
  L.Note("deferred-combat")
  L.Note("deferred-combat")
  assert((L.Snapshot().notes["deferred-combat"] or 0) >= 2 or L.Snapshot().notesDropped > 0, "counts or says it dropped")
end

---------------------------------------------------------------------------
-- 4. Sharing: a transfer settled while work was still in flight stays settled
---------------------------------------------------------------------------
do
  SENDER_FMT = function(n) return n end
  GROUP = { ["Ranulf Ashenvow"] = true, ["Pal Stonebrook"] = true }
  local function boot(name, scan)
    local cl = MakeClient(name, {"!!!TwichUI", "Foo"})
    CLIENTS[name] = cl
    if scan then cl.TwichUIDB = { setup = { scanNext = true } } end
    cl.geterrorhandler = function() return function(e) ERRORS[#ERRORS + 1] = tostring(e) end end
    cl.LOADED["!!!TwichUI"] = true; cl.FireEvent("ADDON_LOADED", "!!!TwichUI")
    cl.FooDB = { a = string.rep("abcdefghij", 800) }; cl.LOADED.Foo = true; cl.FireEvent("ADDON_LOADED", "Foo")
    cl.FireEvent("PLAYER_LOGIN"); cl.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    return cl
  end
  local function settle() for _ = 1, 20 do FlushTimers(); Pump() end end
  local a, b = boot("Ranulf Ashenvow", true), boot("Pal Stonebrook")
  -- the sender needs something to send

  a.TwichUI.Setups:SaveMine(false)
  local SA, SB = a.TwichUI.Share, b.TwichUI.Share
  SA.SetTransport("PARTY")

  -- an offer waiting for an answer is answered "not now" and its prompt taken down when receiving is switched off
  assert(SA:SendTo("Pal Stonebrook")); settle()
  Eq(SB.incoming["Ranulf Ashenvow"].stage, "asking", "offer is waiting")
  local hidden
  b.StaticPopup_Hide = function(name) hidden = name end
  SB:Settle("module-off", true)
  Eq(SB.incoming["Ranulf Ashenvow"].stage, "declined", "the waiting offer is answered not now")
  Eq(hidden, "TWICHUI_OFFER", "and its prompt is taken down")
  settle()
  Eq(SA.outgoing.stage, "failed", "the sender is told and does not wait the full timeout")
  -- answering the prompt afterwards does nothing
  SB:Respond("Ranulf Ashenvow", true); settle()
  Eq(SB.incoming["Ranulf Ashenvow"].stage, "declined", "a late Accept on a settled offer is ignored")

  -- a result that arrives after the transfer was settled is not stored
  SA.outgoing = nil
  assert(SA:SendTo("Pal Stonebrook")); settle()
  SB:Respond("Ranulf Ashenvow", true)
  local inc
  for _ = 1, 60 do
    FlushTimers(); Pump()
    inc = SB.incoming["Ranulf Ashenvow"]
    if inc.stage == "unpacking" then break end
  end
  Eq(inc.stage, "unpacking", "reached the unpacking stage")
  SB:Settle("module-off")
  settle()
  Eq(SB.incoming["Ranulf Ashenvow"].stage, "failed", "still settled after the unpacking finished")
  assert(next(b.TwichUIDB.setup.received) == nil, "nothing was stored from the late result")
  assert(b.TwichUI.Life.Snapshot().notes["cancelled-stale-transfer"] >= 1, "counted")
  -- an outgoing transfer is settled too
  SA.outgoing = nil
  assert(SA:SendTo("Pal Stonebrook"))
  SA:Settle("module-off")
  Eq(SA.outgoing.stage, "failed", "outgoing settled")
  SA:Settle("module-off")   -- and settling again changes nothing
  Eq(SA.outgoing.stage, "failed", "idempotent")

end

---------------------------------------------------------------------------
-- 5. Notification coordinator: world gating, lane release, stale callbacks
---------------------------------------------------------------------------
do
  local n = MakeClient("Noti", {"!!!TwichUI"})
  local errs = {}
  n.geterrorhandler = function() return function(e) errs[#errs + 1] = tostring(e) end end
  n.NOW = 1000
  n.GetTime = function() return n.NOW end
  for _, f in ipairs({"modules/Notify.lua"}) do local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, n); chunk("!!!TwichUI", {}) end
  n.LOADED["!!!TwichUI"] = true; n.FireEvent("ADDON_LOADED", "!!!TwichUI")
  local N = n.TwichUI.Notify
  local shown, dismissed = {}, 0
  N.Register("t", {
    label = "T", show = function(p) shown[#shown + 1] = p.id return true end,
    dismiss = function() dismissed = dismissed + 1 end, hold = function() return 2 end,
  })
  -- before the first loading screen has ended: accepted, not shown
  assert(N.Submit({ kind = "t", id = "early", payload = { id = "early" }, ttl = 30 }))
  Eq(#shown, 0, "nothing is shown before the world is entered")
  Eq(#N.State().waiting, 1, "it waits")
  n.FireEvent("PLAYER_LOGIN")
  Eq(#shown, 0, "login alone is not the world")
  n.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Eq(shown[1], "early", "shown as soon as the world is entered")
  -- a loading screen takes the card down and frees its lane; the backlog is not replayed
  n.FireEvent("PLAYER_LEAVING_WORLD")
  Eq(dismissed, 1, "the card is dismissed by the loading screen")
  Eq(#N.State().active, 0, "the lane is free")
  assert(N.Submit({ kind = "t", id = "during", payload = { id = "during" }, ttl = 30 }))
  Eq(#shown, 1, "nothing starts during a loading screen")
  n.FireEvent("PLAYER_ENTERING_WORLD", false, false)
  Eq(shown[#shown], "during", "what was sent during the loading screen shows when it ends")
  -- a renderer that never reports back: the lane is still freed, once, by the safety timer
  assert(N.Submit({ kind = "t", id = "next", payload = { id = "next" }, ttl = 30 }))
  Eq(#N.State().waiting, 1, "the second waits for the first")
  -- Two timers are due: the first card's (dismissed by the loading screen long ago, so stale) and the
  -- second's. Only the second may take anything down, and only its own card.
  local d0 = dismissed
  RunLongTimers(60)
  Eq(shown[#shown], "next", "the safety timer freed the lane")
  Eq(dismissed, d0 + 1, "the stale timer of the first card dismissed nothing")
  Eq(#errs, 0, table.concat(errs, "; "))
end

print("LIFECYCLE TESTS PASSED")
