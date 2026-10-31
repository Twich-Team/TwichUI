-- Magic Inventory, getting the guild bank ready and carrying out one approved plan across tabs (inventory/GuildBank.lua GB.Show,
-- inventory/GuildPrep.lua, inventory/GuildRun.lua), against the scripted stand-in server of tests/mi_guildsim.lua with the frame's
-- own tab buttons (S.Tabs). Synthetic data only; a stand-in that does what the test says proves the addon's decisions, not what
-- Forever's guild bank does (whether a tab can be shown from addon code, whether the cursor survives a tab switch, and whether a
-- cross-tab move counts against the allowance are real-client checks: docs/magic-inventory.md).
--   * preparation: tabs read one at a time, each only after the one before answered or timed out; delayed, missing and unread
--     tabs; a tab the rank can't see is never asked for; the player's tab is shown again; the player's own navigation wins;
--   * idle rebuilds: any number of events is one rebuild, none while a run is going; repeated open events are one cycle;
--   * the plan across tabs: a deposit into two tabs, an organize that needs a move between tabs, dependencies between tabs,
--     an unavailable destination, a stale confirmation, changed rules;
--   * safety: delayed, duplicate and missing answers, an uncertain outcome, a tab that never answers (with the item on the
--     cursor), the player's navigation, closing, the cursor, Stop, refused calls and Continue.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "mi_guildsim.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local function Has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

local function World(bags, tabs)
  local c = MIClient("Rich", { db = { modules = { magicInventory = true } } })
  local S = GuildSim(c)
  S.Tabs()
  local MI = c.TwichUI.MagicInventory
  c.ITEMS[2593] = { name = "Flask", class = 0, sub = 0, maxStack = 1, quality = 1 }
  c.GUILD.name = "Night Owls"
  local function Tab(name) return { name = name, icon = 133, slots = {}, withdraw = -1, remaining = -1 } end
  c.GUILD.tabs = tabs or { [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") }
  c.GUILD.current = 1
  c.Bags({ [0] = { size = 16, slots = bags or {} } })
  return c, S, MI
end

local function Arrange(c, MI, build)
  local D = MI.Design
  local names = {}
  for i, t in pairs(c.GUILD.tabs) do names[i] = { name = t.name, icon = t.icon } end
  local d = D.New("Night Owls", names, 4)
  build(D, d, { facts = function(id) return (MI.ItemFacts(id)) end })
  local ok, why = D.Save(d)
  assert(ok, why)
end

-- time passes and the server answers (a cooperative one unless answer == false)
local function Spin(S, seconds, step, answer)
  step = step or 0.25
  local t = 0
  while t < seconds do
    S.Tick(step)
    if answer ~= false then S.Settle() end
    t = t + step
  end
end
local function Outstanding(S) local n = 0 for _, r in ipairs(S.queue) do if r.query then n = n + 1 end end return n end
local function Pickups(S, kind) local n = 0 for _, call in ipairs(S.calls) do if call[1] == "pickup" and (not kind or call[2] == kind) then n = n + 1 end end return n end

---------------------------------------------------------------------------
-- Preparation: the tabs are read, one at a time, without anyone choosing to and WITHOUT showing them
---------------------------------------------------------------------------
do
  local c, S, MI = World({})
  local P, GB = MI.GuildPrep, MI.GuildBank
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2447, 3) end)
  c.GUILD.tabs[4] = { name = "Officers", icon = 133, slots = {}, viewable = false, withdraw = 0, remaining = 0 }
  c.GUILD.tabs[2].slots[3] = { id = 2589, count = 5 }
  c.GUILD.tabs[3].slots[4] = { id = 2447, count = 7 }
  c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2447, 20 } } } })
  S.Open(1)
  Check(#S.clicks == 0 and #S.queries == 0, "opening the bank asks for nothing at once: the game's own first answer comes first")
  local maxOut = 0
  for _ = 1, 60 do
    S.Tick(0.25)
    maxOut = math.max(maxOut, Outstanding(S))
    S.Settle()
  end
  Check(maxOut <= 1, "at most one tab was being asked for at any time (" .. maxOut .. ")")
  Check(Has(S.queries, 2) and Has(S.queries, 3), "tabs 2 and 3 were each asked for without anyone pressing anything: " .. table.concat(S.queries, ","))
  Check(#S.clicks == 0 and c.GUILD.current == 1, "and no tab was ever shown: the player's tab never changed")
  Check(not Has(S.queries, 4), "the tab the rank can't see was never asked for")
  local snap = GB.Snapshot()
  Check(snap.tabs[2].slots and snap.tabs[3].slots and snap.tabs[3].slots[4].count == 7, "both tabs' items are held")
  Check(snap.tabs[2].state == "earlier" and GB.IsFresh(2) and GB.IsFresh(3), "they count as read in this visit (not live: they are not the tab shown)")
  Check(snap.tabs[4] and snap.tabs[4].slots == nil, "the hidden tab holds nothing")
  Check(P.Status().state == "ready" and P.Status().reading == false, "preparation says ready")
  local sum = P.Summary()
  Check(sum and sum.arrangement and sum.deposit.moves == 2 and sum.organize.moves == 2, "the summary was built by itself: 2 stacks to deposit, 2 to organize (" .. tostring(sum and sum.deposit.moves) .. "/" .. tostring(sum and sum.organize.moves) .. ")")
  Check(#S.calls == 0 and #S.moves == 0, "nothing was picked up or moved by preparing")
  local reads = P.Reads()
  Spin(S, 20)
  Check(P.Reads() == reads, "nothing is asked for again while everything is current")
  Check(P.ListenerCount() == 4, "the preparation listens to four events and no more")
end

do
  -- the player uses the bank while it reads: clicking tabs, holding an item and the log page change nothing about the reading
  local c, S, MI = World({})
  local P, GB = MI.GuildPrep, MI.GuildBank
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2447, 3) end)
  c.GUILD.tabs[3].slots[4] = { id = 2447, count = 7 }
  S.Open(1)
  Spin(S, 0.9, 0.1)
  c.GUILD.current = 3                                   -- the player clicks tab 3 themselves
  c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
  S.cursor = { id = 2589, count = 1, from = { "bag", 0, 1 } }
  c.GuildBankFrame.mode = "log"
  Spin(S, 12)
  Check(#S.clicks == 0 and c.GUILD.current == 3, "the reading never touched the player's tab (they are on 3)")
  Check(GB.Snapshot().tabs[2].slots ~= nil and GB.Snapshot().tabs[1].slots ~= nil and P.Status().state == "ready", "and everything was read anyway: " .. tostring(P.Status().state))
  Check(S.cursor ~= nil and (S.cleared or 0) == 0, "the player's cursor was never touched")
end

do
  -- a delayed answer is waited for, a missing one is not an empty tab
  local c, S, MI = World({})
  local P, GB = MI.GuildPrep, MI.GuildBank
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2447, 3) end)
  c.GUILD.tabs[3].slots[4] = { id = 2447, count = 7 }
  c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2447, 20 } } } })
  S.noAnswer = { [2] = true }
  S.Open(1)
  Spin(S, 1.5, 0.25, false)
  Check(P.Status().state == "reading" and #S.queries == 1 and S.queries[1] == 2 and #S.clicks == 0, "reading: tab 2 was asked for (without showing it)")
  Check(GB.Snapshot().tabs[2].state == "unread", "tab 2 is unread (not empty) while its answer is outstanding")
  Spin(S, 2.4, 0.25, false)
  Check(#S.queries == 2 and S.queries[2] == 2 and #S.clicks == 0, "after the wait it was asked for once more, not hammered")
  Spin(S, 40)
  Check(P.Status().problems[2] == "no-answer", "a tab that never answers is reported as not read")
  Check(#S.clicks == 0 and #S.queries == 3 and S.queries[3] == 3, "two asks for it, then on to tab 3, and no tab was shown: queries " .. table.concat(S.queries, ",") .. " clicks " .. #S.clicks)
  local tab2 = GB.Snapshot().tabs[2]
  Check(tab2.state == "unread" and tab2.slots == nil, "tab 2 is still unread, never treated as empty")
  local sum = P.Summary()
  Check(sum.deposit.moves == 1 and sum.deposit.blocked + (sum.deposit.unknown or 0) >= 1, "the plan puts the herbs in tab 3 and leaves the Linen out as unknown, not into an 'empty' tab 2")
  local rv = MI.GuildRun.Review("deposit")
  Check(rv.ok and rv.moves == 1 and #rv.unread == 1 and rv.unread[1] == 2 and not rv.complete, "the review does the independent part and says tab 2 is unread")
  Check(P.Status().state == "partial", "the status is partial, not ready")
end

do
  -- the answer is taken only after a quiet moment, so an event for something else is not mistaken for it
  local c, S, MI = World({})
  local P, GB = MI.GuildPrep, MI.GuildBank
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  c.GUILD.tabs[2].slots[3] = { id = 2589, count = 5 }
  S.noAnswer = { [2] = true }
  S.Open(1)
  Spin(S, 1.0, 0.1, false)
  Check(#S.queries == 1, "tab 2 asked for")
  c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")              -- an event for the shown tab, nothing to do with tab 2
  Spin(S, 0.3, 0.1, false)
  Check(GB.Snapshot().tabs[2].slots == nil, "inside the quiet moment it is not yet taken as read")
  Spin(S, 0.4, 0.1, false)
  Check(GB.Snapshot().tabs[2].slots ~= nil, "after it, the tab is read (the residual risk of an event with no tab number)")
end

do
  -- the last resort, only when the player asked: the game ignores the query, so the tab is shown, read, and the player's tab comes back
  local c, S, MI = World({})
  local P, GB = MI.GuildPrep, MI.GuildBank
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  c.GUILD.tabs[2].slots[3] = { id = 2589, count = 5 }
  S.noQueryAnswer = { [2] = true }
  S.Open(1)
  Spin(S, 40)
  Check(#S.clicks == 0 and P.Status().problems[2] == "no-answer", "by itself it never shows a tab: tab 2 is just not read")
  local got
  P.EnsureFresh(function(ok) got = ok end)
  Spin(S, 30)
  Check(Has(S.clicks, 2) and S.clicks[#S.clicks] == 1 and c.GUILD.current == 1, "when the player asks, the tab is shown, read, and their own tab shown again: " .. table.concat(S.clicks, ","))
  Check(GB.Snapshot().tabs[2].slots ~= nil and got == true, "and it was read")
end

do
  -- duplicate open events, closing and reopening: one cycle at a time, nothing left behind
  local c, S, MI = World({})
  local P, GB = MI.GuildPrep, MI.GuildBank
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  S.Open(1)
  c.FireEvent("GUILDBANKFRAME_OPENED"); c.FireEvent("GUILDBANKFRAME_OPENED"); c.FireEvent("GUILDBANKFRAME_OPENED")
  Spin(S, 8)
  Check(P.Cycles() == 1, "three open events made one cycle (" .. P.Cycles() .. ")")
  local listeners = P.ListenerCount() + GB.ListenerCount()
  c.CloseGuildBank()
  local n = #S.queries
  Spin(S, 60)
  Check(#S.queries == n and P.Status().state == "idle" and P.Summary() == nil, "closed: nothing is asked for, the summary and the state are gone")
  S.Open(1)
  Spin(S, 8)
  Check(P.Cycles() == 2 and #S.queries > n, "reopened: one more cycle (" .. P.Cycles() .. " cycles, queries " .. table.concat(S.queries, ",") .. ")")
  Check(P.ListenerCount() + GB.ListenerCount() == listeners, "no listener was added by closing and opening again")
  Check(#S.calls == 0, "no pickup, split or place happened in any of it")
end

do
  -- many events are one rebuild, and none while a run is going
  local c, S, MI = World({ [1] = { 2589, 20 } })
  local P = MI.GuildPrep
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  S.Open(1)
  Spin(S, 8)
  Check(P.Summary() and P.Summary().deposit.moves == 1, "ready: one stack to deposit")
  local plans = 0
  local orig = MI.CurrentGuildPlan
  MI.CurrentGuildPlan = function(...) plans = plans + 1; return orig(...) end
  for _ = 1, 40 do c.FireEvent("BAG_UPDATE_DELAYED") end
  Spin(S, 1.5)
  Check(plans == 2, "forty bag events were one rebuild: a deposit plan and an organize plan (" .. plans .. ")")
  plans = 0
  local rv = MI.GuildRun.Review("deposit")
  plans = 0
  MI.GuildRun.Start(rv)
  for _ = 1, 20 do c.FireEvent("BAG_UPDATE_DELAYED") end
  S.Tick(1)
  Check(plans <= 2, "during a run the events don't rebuild the summary (" .. plans .. ", all from the run)")
  S.Pump()
  Spin(S, 3)
  Check(MI.GuildRun.Last().outcome == "completed", "the run completed")
  Check(P.Summary() and P.Summary().deposit.moves == 0, "after it the summary was rebuilt by itself: nothing left to deposit")
  MI.CurrentGuildPlan = orig
end

do
  -- an item the game has not told us about yet is "can't be told", then the summary is built again by itself when it arrives
  local c, S, MI = World({ [1] = { 2589, 20 } })
  local P = MI.GuildPrep
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  S.Open(1)
  Spin(S, 8)
  Check(P.Summary().deposit.moves == 1, "ready")
  c.UNLOADED = { [2589] = true }
  MI.ClearItemCache()
  c.FireEvent("BAG_UPDATE_DELAYED")
  Spin(S, 2)
  Check(P.Summary().deposit.moves == 0 and (P.Summary().deposit.unknown or 0) > 0, "item data missing: the stack is 'can't be told yet', not invented")
  c.UNLOADED = {}
  c.FireEvent("GET_ITEM_INFO_RECEIVED", 2589, true)
  Spin(S, 2)
  Check(P.Summary().deposit.moves == 1, "the item data arrived: the summary was rebuilt by itself")
  local plans = 0
  local orig = MI.CurrentGuildPlan
  MI.CurrentGuildPlan = function(...) plans = plans + 1; return orig(...) end
  for _ = 1, 30 do c.FireEvent("GET_ITEM_INFO_RECEIVED", 2589, true) end
  Spin(S, 3)
  Check(plans == 0, "item events with nothing pending rebuild nothing (" .. plans .. ")")
  MI.CurrentGuildPlan = orig
end

---------------------------------------------------------------------------
-- A plan across tabs: dependencies, unavailable tabs, a stale confirmation
---------------------------------------------------------------------------
local function Ready(c, S)
  S.Open(1)
  Spin(S, 8)
end

do
  -- Wool sits in the slot reserved for Linen; it must leave (to its own tab) first, then the Linen comes in from another tab
  local c, S, MI = World({})
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx)
    D.PlaceSlot(d, ctx, 2589, 2, 5, 20)
    D.AssignTab(d, ctx, 2592, 3)
  end)
  c.GUILD.tabs[2].slots[5] = { id = 2592, count = 8 }
  c.GUILD.tabs[1].slots[7] = { id = 2589, count = 20 }
  Ready(c, S)
  local rv = GR.Review("reorganize")
  Check(rv.ok and rv.moves == 2 and rv.crossTab == 2 and rv.complete, "two moves between tabs, one depending on the other: " .. tostring(rv.ok and rv.headline or rv.refuse.text))
  if rv.ok then
    Check(rv.ops[1].id == 2592 and rv.ops[2].id == 2589, "the Wool leaves the slot first, then the Linen comes in")
    Check(GR.Start(rv), "started")
    S.Pump()
    local res = GR.Last()
    Check(res.outcome == "completed" and res.confirmed == 2, "completed: " .. tostring(res.outcome) .. " " .. tostring(res.reason))
    Check(S.moves[1].id == 2592 and S.moves[2].id == 2589, "the server saw the Wool leave first")
    Check(c.GUILD.tabs[2].slots[5].id == 2589 and c.GUILD.tabs[2].slots[5].count == 20 and S.TabCount(3, 2592) == 8, "tab 2's reserved slot holds the Linen, tab 3 the Wool")
    Check((S.offTab or 0) == 0 and (S.swaps or 0) == 0 and (S.cleared or 0) == 0, "every call named the tab shown; no swap; ClearCursor never called")
    Check(c.GUILD.current == 1, "and the player's tab is shown again")
  end
end

do
  -- the Wool's tab can't be used: the Linen can't come in, nothing is swapped, and independent work still goes on
  local tabs = { [1] = { name = "Gear", icon = 133, slots = {}, withdraw = -1, remaining = -1 }, [2] = { name = "Cloth", icon = 133, slots = {}, withdraw = -1, remaining = -1 },
    [3] = { name = "Herbs", icon = 133, slots = {}, withdraw = -1, remaining = -1, canDeposit = false } }
  local c, S, MI = World({}, tabs)
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx)
    D.PlaceSlot(d, ctx, 2589, 2, 5, 20)
    D.AssignTab(d, ctx, 2592, 3)
    D.AssignTab(d, ctx, 2770, 2)
  end)
  c.GUILD.tabs[2].slots[5] = { id = 2592, count = 8 }
  c.GUILD.tabs[1].slots[7] = { id = 2589, count = 20 }
  c.GUILD.tabs[1].slots[8] = { id = 2770, count = 4 }
  Ready(c, S)
  local rv = GR.Review("reorganize")
  Check(rv.ok and not rv.complete, "the independent part is reviewed, and the review says it is not everything")
  local linenIn, woolOut = false, false
  for _, o in ipairs(rv.ops) do
    if o.id == 2589 then linenIn = true end
    if o.id == 2592 then woolOut = true end
  end
  Check(not linenIn and not woolOut, "neither the Wool's move nor the Linen that depends on it is in it")
  Check(GR.Start(rv), "started")
  S.Pump()
  local res = GR.Last()
  Check(res.outcome == "partial", "Partially completed (" .. tostring(res.outcome) .. ")")
  Check(c.GUILD.tabs[2].slots[5].id == 2592 and S.TabCount(2, 2770) == 4, "the Wool still sits in the reserved slot, the Copper was moved to tab 2")
end

do
  -- a confirmation made a while ago: the tabs are read again first; if the bank changed meanwhile, nothing moves
  local c, S, MI = World({ [1] = { 2589, 20 }, [2] = { 2447, 20 } })
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2447, 3) end)
  Ready(c, S)
  local rv = GR.Review("deposit")
  Check(rv.ok and rv.moves == 2 and #rv.tabs == 2, "reviewed")
  S.Tick(20)                                                    -- the player read it for a while (tabs 2 and 3 are older than GR.START_AGE)
  local queries = #S.queries
  c.GUILD.tabs[3].slots[1] = { id = 2770, count = 2 }           -- somebody else put something where the herbs would go
  c.GUILD.tabs[3].slots[2] = { id = 2770, count = 2 }
  Check(GR.Start(rv), "the confirmation is accepted and starts by reading the tabs again")
  Check(Pickups(S) == 0, "nothing has moved yet")
  Spin(S, 12)
  local res = GR.Last()
  Check(res.outcome == "stopped" and res.code == "stale" and res.confirmed == 0, "the plan changed before anything moved: Stopped, nothing done (" .. tostring(res.outcome) .. " " .. tostring(res.code) .. ")")
  Check(Pickups(S) == 0 and #S.moves == 0, "no pickup, no move: the old plan was not run and no new one was substituted")
  Check(res.fresh and res.fresh.ok and res.fresh.fingerprint ~= rv.fingerprint, "the result carries a NEW review to read and approve")
  Check(#S.queries > queries, "the tabs were read again, without being shown")
  Check(c.GUILD.current == 1 or c.GUILD.current == 3 or c.GUILD.current == 2, "(tab left shown: " .. tostring(c.GUILD.current) .. ")")
  Check(not GR.Busy(), "no run is left")
end

do
  -- unchanged after the refresh: the same approval stands
  local c, S, MI = World({ [1] = { 2589, 20 }, [2] = { 2447, 20 } })
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2447, 3) end)
  Ready(c, S)
  local rv = GR.Review("deposit")
  S.Tick(20)
  local queries = #S.queries
  Check(GR.Start(rv), "started")
  Spin(S, 12)
  Check(GR.Last().outcome == "completed" and #S.queries > queries, "it read the tabs again (without showing them), found them as reviewed and went on: Completed")
end

do
  -- the rules change after the review: the confirmation is refused, or the run stops before moving anything
  local c, S, MI = World({ [1] = { 2589, 20 } })
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  Ready(c, S)
  local rv = GR.Review("deposit")
  S.Tick(20)
  MI.SaveRule({ kind = "keep", enabled = true, name = "Keep", cats = {}, qualities = {}, include = { [2447] = true }, exclude = {}, equip = "any", bind = "any", keep = 1 })
  local ok = GR.Start(rv)
  Spin(S, 12)
  Check(Pickups(S) == 0 and #S.moves == 0, "changed rules: nothing moved")
  Check(not ok or (GR.Last() and GR.Last().outcome ~= "completed"), "and nothing completed under the old approval")
end

---------------------------------------------------------------------------
-- Cross-tab moves: what each acknowledgment has to show
---------------------------------------------------------------------------
-- one Linen stack in tab 1 that belongs in tab 2 (a move between tabs)
local function OneCross()
  local c, S, MI = World({})
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  c.GUILD.tabs[1].slots[7] = { id = 2589, count = 20 }
  Ready(c, S)
  local rv = MI.GuildRun.Review("reorganize")
  assert(rv.ok and rv.moves == 1 and rv.crossTab == 1, "setup: " .. tostring(rv.ok and rv.headline or rv.refuse.text))
  return c, S, MI, MI.GuildRun, rv
end

do
  -- the order of a move between tabs: pick up (source shown), show the destination, place, show the source again
  local c, S, MI, GR, rv = OneCross()
  local seq = {}
  S.tabHook = function(i) seq[#seq + 1] = "tab" .. i end
  S.hook = function(_, call) seq[#seq + 1] = call[1] .. ":" .. call[3] end
  Check(GR.Start(rv), "started")
  S.Pump()
  Check(GR.Last().outcome == "completed", "completed")
  Check(table.concat(seq, " ") == "tab1 pickup:1 tab2 pickup:2 tab1" or table.concat(seq, " "):find("pickup:1 tab2 pickup:2 tab1"), "pickup in tab 1, tab 2 shown, placed in tab 2, tab 1 shown to confirm the source (then home): " .. table.concat(seq, " "))
  Check(S.moves[1].from[2] == 1 and S.moves[1].to[2] == 2 and #S.moves == 1, "one move happened, tab 1 to tab 2")
  Check((S.offTab or 0) == 0, "no call named a tab other than the one shown")
end

do
  -- a late destination echo and duplicate events: the move counts once, only when the destination shows it
  local c, S, MI, GR, rv = OneCross()
  GR.Start(rv)
  for _ = 1, 8 do S.Tick(0.1) end
  S.Settle({ events = false })                                  -- answered, no event
  for _ = 1, 20 do S.Tick(0.25) end
  Check(GR.Busy() or GR.Last(), "(still going or done)")
  S.Pump()
  Check(GR.Last() and GR.Last().outcome == "completed" and #S.moves == 1, "answers without events are found by the timed reads: once")
  local c2, S2, MI2, GR2, rv2 = OneCross()
  GR2.Start(rv2)
  for _ = 1, 40 do S2.Tick(0.25); S2.Settle({ dup = 4 }) end
  Check(GR2.Last() and GR2.Last().outcome == "completed" and #S2.moves == 1 and Pickups(S2) == 2, "four copies of every event: one pickup, one place, one move")
end

do
  -- the source tab does not answer after the placing: the move may have happened, so it is uncertain and never repeated
  local c, S, MI, GR, rv = OneCross()
  S.hook = function(n, call) if n == 2 then S.noAnswer = { [1] = true } end end   -- right after the placing
  GR.Start(rv)
  Spin(S, 30)
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.uncertain == 1 and res.code == "nav-timeout", "Needs review: one uncertain move (" .. tostring(res and res.outcome) .. " " .. tostring(res and res.code) .. ")")
  Check(Pickups(S) == 2 and #S.moves == 1, "nothing was retried: one pickup, one place")
  Check(res.ops[1].note and res.ops[1].note:find("source tab"), "and it says which part wasn't confirmed")
  Check(res.ops[1].note:find("saw: cursor empty") and res.ops[1].note:find("right after the place call the cursor was empty"), "and what the game showed at that moment: " .. tostring(res.ops[1].note))
end

do
  -- the destination tab never shows while the item is on the cursor: it goes back where it came from
  local c, S, MI, GR, rv = OneCross()
  S.hook = function(n, call) if n == 1 then S.noAnswer = { [2] = true } end end   -- right after the pickup
  GR.Start(rv)
  Spin(S, 30)
  local res = GR.Last()
  Check(res and res.code == "nav-timeout" and res.outcome == "stopped" and res.confirmed == 0 and res.failed == 1, "Stopped: nothing moved, the item was put back (" .. tostring(res and res.outcome) .. " " .. tostring(res and res.code) .. ")")
  Check(S.cursor == nil and c.GUILD.tabs[1].slots[7] and c.GUILD.tabs[1].slots[7].count == 20 and not c.GUILD.tabs[1].slots[7].locked, "the stack is in its slot again, unlocked, the cursor empty")
  Check(#S.moves == 0 and (S.cleared or 0) == 0, "no move happened and ClearCursor was never called")
  Check(res.ops[1].note and res.ops[1].note:find("put back"), "the result says it was put back")
end

do
  -- neither tab answers: the item stays on the cursor, and the player is told where it belongs
  local c, S, MI, GR, rv = OneCross()
  S.hook = function(n, call) if n == 1 then S.noAnswer = { [1] = true, [2] = true } end end
  GR.Start(rv)
  Spin(S, 40)
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.cursor and res.cursor.id == 2589, "Needs review, and it says the cursor holds the Linen")
  Check(S.cursor ~= nil and (S.cleared or 0) == 0, "the cursor was left as it is")
  Check(table.concat(res.lines, " "):find("Put it back in tab 1 slot 7"), "and where to put it")
end

do
  -- the player changes tab with the item on the cursor, or between moves
  local c, S, MI, GR, rv = OneCross()
  S.hook = function(n, call) if n == 1 then c.GUILD.current = 3 end end            -- right after the pickup the player clicks tab 3
  GR.Start(rv)
  S.Pump()
  local res = GR.Last()
  Check(res.code == "tab" and res.outcome == "review" and res.cursor, "a tab the run didn't ask for: it stops at once, with the cursor item reported (" .. tostring(res.code) .. ")")
  Check(Pickups(S) == 1 and (S.cleared or 0) == 0, "and it did nothing more")
end

do
  local c, S, MI, GR, rv = OneCross()
  S.hook = function(n, call) if n == 1 then c.CloseGuildBank() end end
  GR.Start(rv)
  S.Pump()
  local res = GR.Last()
  Check(res.code == "closed" and res.outcome == "review" and res.uncertain == 1, "closing the bank with the item held: Needs review, one uncertain move")
  Check(not GR.Busy() and GR.ListenerCount() == 0, "the run and its listeners are gone")
  S.Tick(60); S.Pump()
  Check(#S.calls == 1, "nothing resumed by itself")
  S.Open(1)
  S.Pump()
  Check(#S.calls == 1 and not GR.Busy(), "nor after reopening")
end

do
  -- the player's own cursor item: never touched
  local c, S, MI, GR, rv = OneCross()
  S.hook = function(n, call) if n == 1 then S.cursor = { other = true, id = 5 } end end
  GR.Start(rv)
  S.Pump()
  local res = GR.Last()
  Check(res.code == "cursor-changed" and (S.cleared or 0) == 0, "the cursor changed under the run: stopped, and the new cursor contents were not touched")
end

do
  -- Stop during a move between tabs: that move is finished and confirmed, then it stops
  local c, S, MI = World({})
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2592, 2) end)
  c.GUILD.tabs[1].slots[7] = { id = 2589, count = 20 }
  c.GUILD.tabs[1].slots[8] = { id = 2592, count = 20 }
  Ready(c, S)
  local rv = GR.Review("reorganize")
  Check(rv.ok and rv.moves == 2, "two moves between tabs")
  S.hook = function(n, call) if n == 1 then GR.Stop() end end
  GR.Start(rv)
  S.Pump()
  local res = GR.Last()
  Check(res.outcome == "stopped" and res.confirmed == 1 and res.notStarted == 1 and res.uncertain == 0, "Stop: the move in flight was confirmed, the next was not started (" .. tostring(res.outcome) .. " " .. tostring(res.confirmed) .. ")")
  Check(#S.moves == 1, "one move happened")
end

do
  -- a client that wants a click: a refused pickup waits for Continue; a refused placing keeps the item on the cursor
  local c, S, MI, GR, rv = OneCross()
  S.requireClick, S.onlyPlace = true, true
  S.inClick = true
  GR.Start(rv)
  S.inClick = false
  Spin(S, 4)
  Check(GR.Busy() and GR.Progress().needClick and S.cursor ~= nil, "the placing was refused outside a click: the item waits on the cursor, the run asks for a click")
  local calls = #S.calls
  Spin(S, 20, 1)
  Check(#S.calls == calls and GR.Busy(), "it does not retry on its own")
  for _ = 1, 10 do
    if not GR.Busy() then break end
    S.inClick = true
    GR.Continue()
    S.inClick = false
    Spin(S, 2)
  end
  Check(GR.Last() and GR.Last().outcome == "completed" and #S.moves == 1 and S.cursor == nil and (S.swaps or 0) == 0, "Continue placed it: Completed, once")
end

do
  -- a refused call (nothing happens, nothing blocked) is a delayed pickup, not proof of a click restriction
  local c, S, MI, GR, rv = OneCross()
  S.refuse = true
  GR.Start(rv)
  Spin(S, 30)
  local res = GR.Last()
  Check(res.code == "timeout" and res.outcome == "review" and not res.cursor, "a call the game ignored without a word: a timeout, not a claimed click restriction (" .. tostring(res.code) .. ")")
  Check(not GR.Progress() and Pickups(S) == 1, "and it was not repeated")
end


---------------------------------------------------------------------------
-- Organize also tidies the arrangement's tab: the other items are merged, sorted and moved to the far end, nothing is swapped
---------------------------------------------------------------------------
do
  local c, S, MI = World({})
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  c.GUILD.tabs[2].slots = { [1] = { id = 2447, count = 8 }, [2] = { id = 2592, count = 5 }, [4] = { id = 2447, count = 9 }, [6] = { id = 2592, count = 6 }, [9] = { id = 2589, count = 20 } }
  c.GUILD.tabs[1].slots[3] = { id = 2592, count = 4 }          -- Wool in another tab too: that Wool is not part of the tidying
  Ready(c, S)
  local before = { linen = S.Total(2589), pea = S.Total(2447), wool = S.Total(2592) }
  local rv = GR.Review("reorganize")
  Check(rv.ok and rv.moves >= 3, "organize plans the tidying (" .. tostring(rv.ok and rv.moves or rv.refuse.text) .. ")")
  if rv.ok then
    Check(GR.Start(rv), "started")
    S.Pump()
    local res = GR.Last()
    Check(res.outcome == "completed" or res.outcome == "partial", "it finished: " .. tostring(res.outcome) .. " " .. tostring(res.reason))
    local t2 = c.GUILD.tabs[2].slots
    Check(t2[1] and t2[1].id == 2589 and t2[1].count == 20, "the arrangement's Linen is in the first slot")
    Check(t2[98] and t2[98].id == 2447 and t2[98].count == 17 or (t2[97] and t2[97].id == 2447 and t2[97].count == 17), "the Peacebloom (8 and 9) is one stack at the far end")
    Check(S.Total(2589) == before.linen and S.Total(2447) == before.pea and S.Total(2592) == before.wool, "nothing was lost or created")
    Check((S.swaps or 0) == 0 and (S.cleared or 0) == 0, "no swap, ClearCursor never called")
    Check(c.GUILD.tabs[1].slots[3] and c.GUILD.tabs[1].slots[3].count == 4, "the Wool in the other tab was left alone")
  end
end

---------------------------------------------------------------------------
-- Pacing and the one reconciled retry (the real game dropped placements made right after the last one)
---------------------------------------------------------------------------
local function Several()
  local c, S, MI = World({ [1] = { 2589, 20 }, [2] = { 2592, 20 }, [3] = { 2447, 20 } })
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2592, 2); D.AssignTab(d, ctx, 2447, 2) end)
  Ready(c, S)
  local rv = MI.GuildRun.Review("deposit")
  assert(rv.ok and rv.moves == 3, "setup: " .. tostring(rv.ok and rv.moves or rv.refuse.text))
  return c, S, MI, MI.GuildRun, rv
end

do
  -- moves are paced: the next is not started until GR.GAP after the last one was confirmed
  local c, S, MI, GR, rv = Several()
  GR.GAP = 1.0
  local times = {}
  S.hook = function(_, call) if call[1] == "pickup" and call[2] == "bag" then times[#times + 1] = S.NOW end end
  GR.Start(rv)
  Spin(S, 12)
  Check(GR.Last() and GR.Last().outcome == "completed" and #times == 3, "three paced moves complete")
  Check(times[2] - times[1] >= 1.0 and times[3] - times[2] >= 1.0, "each started at least a second after the one before: " .. table.concat(times, ", "))
end

do
  -- the game silently gives one placement back: after a pause it is looked at again and, because nothing changed, tried once more
  local c, S, MI, GR, rv = Several()
  GR.GAP, GR.SETTLE = 1.0, 1.5
  S.bounce = 1
  GR.Start(rv)
  Spin(S, 20)
  local res = GR.Last()
  Check(res and res.outcome == "completed" and res.confirmed == 3, "the dropped placement was tried again and everything completed (" .. tostring(res and res.outcome) .. ")")
  Check(#S.moves == 3 and S.TabCount(2, 2589) == 20 and S.TabCount(2, 2592) == 20 and S.TabCount(2, 2447) == 20, "each stack landed once")
  Check(res.ops[1].note and res.ops[1].note:find("second try"), "and the result says which move needed a second try")
  Check((S.swaps or 0) == 0 and (S.cleared or 0) == 0, "no swap, ClearCursor never called")
end

do
  -- dropped twice: the second try is the last; then it is uncertain, not repeated again
  local c, S, MI, GR, rv = Several()
  GR.GAP, GR.SETTLE = 1.0, 1.5
  S.bounce = 2
  GR.Start(rv)
  Spin(S, 30)
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.uncertain == 1 and res.confirmed == 0, "dropped twice: Needs review, one uncertain, nothing else started (" .. tostring(res and res.outcome) .. ")")
  Check(Pickups(S, "bag") == 2 and #S.moves == 0, "handed to the game exactly twice, nothing moved")
end

do
  -- a placement that is only slow is NOT tried again: its source is still locked, so it can't be called untouched
  local c, S, MI, GR, rv = Several()
  GR.GAP, GR.SETTLE = 1.0, 1.5
  GR.Start(rv)
  for _ = 1, 48 do                                              -- the server answers tab reads but never the move, for twelve seconds
    S.Tick(0.25)
    local q, keep = S.queue, {}
    S.queue = {}
    for _, r in ipairs(q) do if r.query then S.queue[#S.queue + 1] = r else keep[#keep + 1] = r end end
    S.Settle()
    for _, r in ipairs(keep) do S.queue[#S.queue + 1] = r end
  end
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.uncertain == 1, "no answer at all: uncertain, never repeated (" .. tostring(res and res.outcome) .. " " .. tostring(res and res.code) .. " " .. tostring(res and res.reason) .. ")")
  Check(Pickups(S, "bag") == 1 and Pickups(S, "guild") == 1, "one pickup, one place")
end

print(failures == 0 and "PASSED test_magic_inventory_guildprep" or ("FAILED: " .. failures))
if failures > 0 then os.exit(1) end
