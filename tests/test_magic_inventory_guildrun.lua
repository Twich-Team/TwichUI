-- Magic Inventory, carrying out a reviewed guild bank arrangement (inventory/GuildRun.lua), against a scripted stand-in
-- server (tests/mi_guildsim.lua). Synthetic data only; nothing here is the game, and a stand-in that does what the test says
-- proves the executor's decisions, not what Forever's guild bank does.
--   * the review: saved rules only, the shown tab only, what is excluded and why, one fingerprint of the plan and its state;
--   * the confirmation: bound to that fingerprint, one use, refused when anything relevant changed, no overlapping runs;
--   * the run: a deposit and an in-bank reorganization, whole stacks, splits and merges, each move confirmed from a read of
--     the source AND the destination; duplicate, delayed, missing and coalesced events; a timeout after the move happened;
--   * safety: surprises, rights and limits, a player's cursor, Stop, closing, no auto-resume, honest final outcomes.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "mi_guildsim.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local function Fresh(bags)
  local c = MIClient("Rich", { db = { modules = { magicInventory = true } } })
  local S = GuildSim(c)
  local MI = c.TwichUI.MagicInventory
  c.ITEMS[2593] = { name = "Flask", class = 0, sub = 0, maxStack = 1, quality = 1 }
  c.GUILD.name = "Night Owls"
  local function Tab(name) return { name = name, icon = 133, slots = {}, withdraw = -1, remaining = -1 } end
  c.GUILD.tabs = { [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") }
  c.GUILD.current = 2
  c.Bags({ [0] = { size = 16, slots = bags or {} } })
  return c, S, MI
end

-- a saved arrangement: build(D, draft, ctx)
local function Arrange(c, MI, build)
  local D = MI.Design
  local names = {}
  for i, t in pairs(c.GUILD.tabs) do names[i] = { name = t.name, icon = t.icon } end
  local d = D.New("Night Owls", names, 3)
  local ctx = { facts = function(id) return (MI.ItemFacts(id)) end }
  build(D, d, ctx)
  local ok, why = D.Save(d)
  assert(ok, why)
end

local function Review(MI, mode)
  local rv = MI.GuildRun.Review(mode)
  return rv
end

local function Describe(rv)
  local out = {}
  for _, o in ipairs(rv.ops or {}) do
    out[#out + 1] = ("%s>%s x%d id%d%s"):format(o.src.kind == "bag" and ("b" .. o.src.bag .. ":" .. o.src.slot) or ("g" .. o.src.tab .. ":" .. o.src.slot),
      "g" .. o.dst.tab .. ":" .. o.dst.slot, o.count, o.id, o.whole and "" or " split")
  end
  return table.concat(out, "; ")
end

---------------------------------------------------------------------------
-- A deposit: whole stacks, a split and a merge, every move confirmed from both sides
---------------------------------------------------------------------------
do
  local c, S, MI = Fresh({ [1] = { 2589, 20 }, [2] = { 2589, 7 }, [3] = { 2592, 20 } })
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx)
    D.PlaceSlot(d, ctx, 2589, 2, 5, 10)          -- a reserved stack of 10 Linen in slot 5
    D.AssignTab(d, ctx, 2592, 2)                 -- Wool goes anywhere in tab 2
  end)
  c.GUILD.tabs[2].slots[9] = { id = 2589, count = 4 }   -- Linen already in tab 2 that is not part of the design
  S.Open(2)
  local before = { linen = S.Total(2589), wool = S.Total(2592) }
  Check(#S.calls == 0 and #S.queue == 0, "opening the guild bank moves nothing")
  local rv = Review(MI, "deposit")
  Check(rv.ok, "a deposit review is made: " .. tostring(rv.refuse and rv.refuse.text))
  Check(#rv.tabs == 1 and rv.tabs[1] == 2 and rv.tabInfo[2].name == "Cloth" and rv.guild == "Night Owls", "it names the guild and the tab it touches")
  Check(rv.moves >= 3 and rv.splits >= 1, "it plans several moves, one of them a split: " .. Describe(rv))
  Check(#S.calls == 0, "reviewing touched nothing")
  local ok, code = GR.Start(rv)
  Check(ok, "confirming starts the run: " .. tostring(code))
  Check(GR.Busy(), "one run is under way")
  S.Pump()
  local res = GR.Last()
  Check(not GR.Busy() and res and res.outcome == "completed", "it completed: " .. tostring(res and res.outcome) .. " " .. tostring(res and res.reason))
  Check(res and res.confirmed == rv.moves and res.total == rv.moves, "every move was confirmed from the game")
  Check(S.Total(2589) == before.linen and S.Total(2592) == before.wool, "nothing was created or lost")
  Check(c.GUILD.tabs[2].slots[5] and c.GUILD.tabs[2].slots[5].id == 2589 and c.GUILD.tabs[2].slots[5].count == 10, "the reserved slot holds exactly 10 Linen")
  Check(S.swaps == 0 and (S.cleared or 0) == 0, "no swap, and ClearCursor was never called")
  Check(S.cursor == nil, "the cursor ends empty")
  local sawSplit = false
  for _, call in ipairs(S.calls) do if call[1] == "split" then sawSplit = true end end
  Check(sawSplit, "a part-stack move used a split")
  Check(GR.ListenerCount() == 0, "the run's events are gone with it")
end


-- the usual arrangement: three Linen stacks and Wool for tab 2
local function Usual(extra)
  local c, S, MI = Fresh({ [1] = { 2589, 20 }, [2] = { 2589, 20 }, [3] = { 2592, 20 }, [4] = { 2592, 5 } })
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2592, 2) end)
  if extra then extra(c, S, MI) end
  S.Open(2)
  return c, S, MI, MI.GuildRun
end
local function Pickups(S) local n = 0 for _, call in ipairs(S.calls) do if call[1] == "pickup" and call[2] == "bag" then n = n + 1 end end return n end

---------------------------------------------------------------------------
-- Organize: moves inside a tab and between tabs, one reviewed plan, each tab shown and read on the way
---------------------------------------------------------------------------
do
  local c, S, MI = Fresh({})
  local GR = MI.GuildRun
  S.Tabs()
  Arrange(c, MI, function(D, d, ctx)
    D.PlaceSlot(d, ctx, 2589, 2, 5, 20)
    D.AssignTab(d, ctx, 2592, 2)
  end)
  c.GUILD.tabs[2].slots[3] = { id = 2589, count = 12 }
  c.GUILD.tabs[2].slots[8] = { id = 2589, count = 8 }
  c.GUILD.tabs[1].slots[4] = { id = 2592, count = 10 }   -- Wool in another tab: gathering it is a move between tabs
  S.Open(1)
  S.Show(2)                                              -- tab 1 was read while it was shown; tab 2 is shown now
  local rv = Review(MI, "reorganize")
  Check(rv.ok and rv.moves == 3 and rv.crossTab == 1, "organize plans the two Linen moves inside tab 2 and the Wool move between tabs: " .. Describe(rv))
  Check(rv.complete and #rv.dropped == 0, "nothing is left out: the move between tabs is part of the plan")
  Check(#rv.tabs == 2 and rv.tabs[1] == 1 and rv.tabs[2] == 2, "the review names both tabs it touches")
  Check(#rv.unread == 1 and rv.unread[1] == 3, "tab 3 was never read: the review says so, and it does not block the rest")
  local joined = table.concat(rv.lines, " ")
  Check(joined:find("between tabs") and joined:find("Not read: tab 3"), "the confirmation says it crosses tabs and that tab 3 is unread")
  Check(GR.Start(rv), "started")
  S.Pump()
  local res = GR.Last()
  Check(res.outcome == "completed", "all three moves were confirmed and the final check agrees: Completed (" .. tostring(res.outcome) .. " " .. tostring(res.reason) .. ")")
  Check(c.GUILD.tabs[2].slots[5] and c.GUILD.tabs[2].slots[5].count == 20 and not c.GUILD.tabs[2].slots[3] and not c.GUILD.tabs[2].slots[8], "the Linen was gathered into the reserved slot")
  Check(not c.GUILD.tabs[1].slots[4] and S.TabCount(2, 2592) == 10, "the Wool moved from tab 1 to tab 2")
  Check((S.offTab or 0) == 0, "every call named the tab that was shown at that moment")
  Check(c.GUILD.current == 2, "the player's tab is shown again at the end")
  Check(Pickups(S) == 0, "organizing never touched the bags")
  Check(#res.unreadTabs == 1, "the result still says tab 3 was not read")
end

-- Deposit and organize use different sources
do
  local c, S, MI, GR = Usual(function(c) c.GUILD.tabs[2].slots[30] = { id = 2589, count = 3 }; c.GUILD.tabs[2].slots[31] = { id = 2589, count = 3 } end)
  local dep = Review(MI, "deposit")
  for _, o in ipairs(dep.ops) do Check(o.src.kind == "bag", "a deposit only takes from the bags") end
  local org = Review(MI, "reorganize")
  for _, o in ipairs(org.ops or {}) do Check(o.src.kind == "guild", "organizing only moves what is in the bank") end
end

---------------------------------------------------------------------------
-- Events: duplicates, missing, delayed and coalesced ones decide nothing
---------------------------------------------------------------------------
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  local sent = 0
  for _ = 1, 40 do
    S.Tick(0)
    sent = sent + S.Settle({ dup = 5 })   -- every answer arrives five times
  end
  local res = GR.Last()
  Check(res and res.outcome == "completed" and #S.moves == rv.moves, "duplicate events: completed, and each move happened once (" .. #S.moves .. " of " .. rv.moves .. ")")
  local splits = 0
  for _, call in ipairs(S.calls) do if call[1] == "split" then splits = splits + 1 end end
  Check(Pickups(S) + splits == rv.moves, "one pickup or split per move, however many events came (" .. Pickups(S) .. " + " .. splits .. " for " .. rv.moves .. ")")
end
do
  -- no event at all: the reads inside the wait find the result
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  S.Settle({ events = false })
  Check(GR.Busy(), "without an event nothing is claimed yet")
  for _ = 1, 40 do
    S.Tick(0.6)
    S.Settle({ events = false })
    if not GR.Busy() then break end
  end
  Check(GR.Last() and GR.Last().outcome == "completed", "missing events: the timed reads still confirm each move from the game (" .. tostring(GR.Last() and GR.Last().outcome) .. ")")
end
do
  -- a delayed answer, inside the wait: the move is confirmed, not repeated
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  local pickupsBefore = #S.calls
  S.Tick(2.5)
  Check(GR.Busy() and #S.calls == pickupsBefore, "waiting 2.5 s: still waiting, nothing sent again")
  Check(GR.Progress().waiting and GR.Progress().confirmed == 0, "the first move isn't counted until the game shows it")
  S.Settle()
  S.Pump()
  Check(GR.Last() and GR.Last().outcome == "completed" and #S.moves == rv.moves, "a late answer inside the wait is accepted")
end
do
  -- coalesced: a burst of unrelated and related events is a few reads
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  for _ = 1, 200 do c.FireEvent("BAG_UPDATE_DELAYED"); c.FireEvent("GUILDBANKBAGSLOTS_CHANGED"); c.FireEvent("CURSOR_CHANGED") end
  local queued = #S.timers
  Check(queued < 30, "200 events queue a handful of timers, not 600 (" .. queued .. ")")
  S.Pump()
  Check(GR.Last() and GR.Last().outcome == "completed" and #S.moves == rv.moves, "a storm of events changed nothing about what moved")
end

---------------------------------------------------------------------------
-- A timeout after the transfer really happened: never repeated
---------------------------------------------------------------------------
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  local calls = #S.calls
  S.Tick(5)                                       -- the game says nothing for longer than the wait
  local res = GR.Last()
  Check(not GR.Busy() and res and res.outcome == "review" and res.code == "timeout", "no answer in time: Needs review")
  Check(res.uncertain == 1 and res.confirmed == 0, "the move in flight is uncertain, not failed and not confirmed")
  Check(#S.calls == calls, "nothing was retried")
  S.Settle()                                      -- the server did it after all
  S.Pump()
  Check(#S.calls == calls and #S.moves == 1, "a late answer after the stop: the move happened once and was never repeated")
  Check(GR.Last().outcome == "review" and not GR.Busy(), "and no new run began by itself")
  local text = table.concat(res.lines, "\n")
  Check(text:find("uncertain"), "the details say which move is uncertain")
end

---------------------------------------------------------------------------
-- Surprises: the destination, the source and the count change
---------------------------------------------------------------------------
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  local second
  for _, o in ipairs(rv.ops) do if not second and o.dst.slot ~= rv.ops[1].dst.slot then second = o.dst end end
  GR.Start(rv)
  S.Settle()
  S.Step()                                         -- the first move is confirmed; the second not started yet
  c.GUILD.tabs[second.tab].slots[second.slot] = { id = 2447, count = 3 }   -- someone fills its destination
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "stopped" and res.code == "dest" and res.confirmed == 1, "a destination that changed: stopped before the move, 1 confirmed (" .. tostring(res and res.code) .. ")")
  Check(res.notStarted == rv.moves - 1, "the rest is reported as not started")
  Check(c.GUILD.tabs[second.tab].slots[second.slot].id == 2447 and S.swaps == 0, "the other item was not touched")
end
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  -- while the first move is in flight, the bag stack it came from changes
  local o = rv.ops[1]
  c.BAGS[0].slots[o.src.slot].count = 3
  S.Settle()
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.uncertain == 1, "a source that changed under a move in flight: Needs review (" .. tostring(res and res.outcome) .. ")")
  Check(#S.calls <= 3, "and nothing more was attempted")
end
do
  -- unrelated inventory events and another tab's traffic are not reasons to stop
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  for _ = 1, 20 do
    c.GUILD.tabs[1].slots[(_ % 90) + 1] = { id = 2447, count = 1 }
    c.FireEvent("GUILDBANK_UPDATE_TABS"); c.FireEvent("BAG_UPDATE_DELAYED")
    S.Settle()
    S.Tick(0)
  end
  S.Pump()
  Check(GR.Last() and GR.Last().outcome == "completed", "unrelated events and changes in another tab: still completed (" .. tostring(GR.Last() and GR.Last().outcome) .. ")")
end
do
  -- a split that the server does with the wrong amount is caught after the placement
  local c, S, MI, GR = Fresh({ [1] = { 2589, 20 } })
  Arrange(c, MI, function(D, d, ctx) D.PlaceSlot(d, ctx, 2589, 2, 5, 12) end)
  S.Open(2)
  S.splitDelta = 1
  local rv = Review(MI, "deposit")
  Check(rv.ok and rv.splits == 1, "a reserved stack of 12 from a stack of 20 is a split")
  GR = MI.GuildRun
  GR.Start(rv)
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.code == "mismatch", "the destination shows 13, not 12: Needs review, not success (" .. tostring(res and res.outcome) .. " " .. tostring(res and res.code) .. ")")
  Check(S.cursor == nil, "and nothing was left on the cursor")
end

---------------------------------------------------------------------------
-- Rights, limits, full tabs and missing room
---------------------------------------------------------------------------
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  S.Settle()
  S.Step()
  c.GUILD.tabs[2].canDeposit = false
  c.FireEvent("GUILDBANK_UPDATE_TABS")
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "stopped" and res.code == "rights" and res.confirmed == 1, "deposit rights lost between moves: stopped (" .. tostring(res and res.code) .. ")")
end
do
  local c, S, MI = Usual()
  c.GUILD.tabs[2].canDeposit = false
  c.FireEvent("GUILDBANK_UPDATE_TABS")
  local rv = Review(MI, "deposit")
  Check(not rv.ok and rv.refuse.code == "nothing" and (#rv.dropped + rv.planBlocked) >= 1, "no deposit right: nothing to review, and the stacks are listed as not possible")
  c.GUILD.tabs[2].canDeposit = true
  c.GUILD.name = "Other Guild"
  rv = Review(MI, "deposit")
  Check(not rv.ok, "another guild: no review")
  c.GUILD.name = "Night Owls"
  local before = c.GUILD.tabs[2].slots[1] and c.GUILD.tabs[2].slots[1].count
  S.Show(1)
  rv = Review(MI, "deposit")
  Check(rv.ok and #rv.tabs == 1 and rv.tabs[1] == 2, "another tab shown: tab 2's earlier reading still serves, and the review is still for tab 2")
  Check(MI.GuildBank.Snapshot().tabs[2].state == "earlier" and MI.GuildBank.Snapshot().tabs[1].state == "live", "browsing marked tab 2 as read earlier and tab 1 live; nothing was thrown away")
end
do
  -- a withdrawal limit: reviewed as far as it goes, and watched while it runs
  local c, S, MI = Fresh({})
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx) D.PlaceSlot(d, ctx, 2589, 2, 5, 20) end)
  c.GUILD.tabs[2].slots[3] = { id = 2589, count = 5 }
  c.GUILD.tabs[2].slots[8] = { id = 2589, count = 5 }
  c.GUILD.tabs[2].slots[9] = { id = 2589, count = 5 }
  c.GUILD.tabs[2].slots[10] = { id = 2589, count = 5 }
  c.GUILD.tabs[2].remaining = 2
  S.Open(2)
  local rv = Review(MI, "reorganize")
  Check(rv.ok and rv.moves == 2 and #rv.dropped >= 1, "two withdrawals left: two moves reviewed, the rest listed as not possible: " .. Describe(rv))
  c.GUILD.tabs[2].remaining = -1
  S.Show(2)
  rv = Review(MI, "reorganize")
  Check(rv.ok and rv.moves == 4, "no limit: all four")
  GR.Start(rv)
  S.Settle(); S.Step()
  c.GUILD.tabs[2].remaining = 0
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "stopped" and res.code == "limit", "the allowance ran out while running: stopped, not worked around (" .. tostring(res and res.code) .. ")")
end
do
  -- a tab with no free slot, and two tabs that need each other's room: reported, not improvised
  local c, S, MI = Fresh({ [1] = { 2589, 20 } })
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  for s = 1, 98 do c.GUILD.tabs[2].slots[s] = { id = 2447, count = 1 } end
  S.Open(2)
  local rv = Review(MI, "deposit")
  Check(not rv.ok and rv.refuse.code == "nothing", "a full tab: nothing to do, and it says so")
  Check(rv.planBlocked > 0 or #rv.dropped > 0, "the blocked work is counted, not skipped silently")
  Check(#S.calls == 0, "and nothing was touched")
end
do
  local c, S, MI = Fresh({})
  local GR = MI.GuildRun
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 3); D.AssignTab(d, ctx, 2592, 2) end)
  MI.SaveRule({ kind = "never", enabled = true, name = "Never", cats = {}, qualities = {}, include = { [2447] = true }, exclude = {}, equip = "any", bind = "any", keep = 0 })
  for s = 1, 97 do c.GUILD.tabs[2].slots[s] = { id = 2447, count = 1 } end   -- (protected: the tidying leaves them where they are)
  c.GUILD.tabs[2].slots[98] = { id = 2589, count = 10 }       -- Linen belongs in tab 3
  for s = 1, 97 do c.GUILD.tabs[3].slots[s] = { id = 2447, count = 1 } end
  c.GUILD.tabs[3].slots[98] = { id = 2592, count = 10 }       -- Wool belongs in tab 2
  S.Open(3)
  S.Show(2)
  local rv = Review(MI, "reorganize")
  Check(not rv.ok, "two full tabs that need each other's room: no run (swaps and parking in the bags are not used)")
  Check(rv.planBlocked > 0 or #rv.dropped > 0, "and the blocked work is reported")
  Check(#S.calls == 0, "nothing was touched")
end

---------------------------------------------------------------------------
-- The cursor
---------------------------------------------------------------------------
do
  local c, S, MI, GR = Usual()
  S.cursor = { other = true, id = 1234 }
  local rv = Review(MI, "deposit")
  Check(not rv.ok and rv.refuse.code == "cursor", "something on the cursor: no review")
  S.cursor = nil
  rv = Review(MI, "deposit")
  S.cursor = { other = true, id = 1234 }
  local ok, code = GR.Start(rv)
  Check(not ok, "something on the cursor at confirmation: not started (" .. tostring(code) .. ")")
  Check(#S.calls == 0 and S.cursor and S.cursor.id == 1234 and (S.cleared or 0) == 0, "the player's cursor was left alone")
end
do
  -- the player picks something else up right after the run picked up its item
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  S.hook = function(n) if n == 1 then S.cursor = { other = true, id = 5555 } end end
  GR.Start(rv)
  S.hook = nil
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.code == "cursor-changed", "manual cursor activity: stopped, Needs review (" .. tostring(res and res.code) .. ")")
  Check(#S.calls == 1 and S.cursor and S.cursor.id == 5555 and (S.cleared or 0) == 0, "no further call, and the player's item is untouched on the cursor")
end
do
  -- the destination won't take the item: it is put back where it came from, and that is confirmed
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  S.destRefuses = true
  GR.Start(rv)
  S.Tick(5)
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "stopped" and res.code == "not-accepted", "an item the destination refused is put back: Stopped (" .. tostring(res and res.outcome) .. " " .. tostring(res and res.code) .. ")")
  Check(S.cursor == nil and c.BAGS[0].slots[rv.ops[1].src.slot] and not c.BAGS[0].slots[rv.ops[1].src.slot].locked, "the item is back, unlocked, and the cursor is empty")
  Check((S.cleared or 0) == 0, "ClearCursor was not used")
end
do
  -- the item cannot be put back either: it stays on the cursor and the player is told
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  S.destRefuses = true
  S.hook = function(n) if n == 2 then S.refuse = true end end   -- after the failed placement, the game ignores the put-back
  GR.Start(rv)
  S.hook = nil
  S.Tick(5)
  S.Tick(5)
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.cursor ~= nil, "an unresolved addon-owned cursor: Needs review, with the cursor named (" .. tostring(res and res.outcome) .. ")")
  Check(S.cursor ~= nil and (S.cleared or 0) == 0, "the item is still on the cursor, intact")
  local text = table.concat(res.lines, "\n")
  Check(text:find("Your cursor holds"), "the result tells the player where it belongs")
  Check(res.outcome ~= "completed", "never a success message")
end

---------------------------------------------------------------------------
-- Stop, closing, reopening, reload
---------------------------------------------------------------------------
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  GR.Stop()
  Check(GR.Busy() and GR.Progress().stopping, "Stop while a move is in flight: it waits for that move")
  S.Settle()
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "stopped" and res.code == "stopped" and res.confirmed == 1 and res.notStarted == rv.moves - 1, "stopped at the boundary after 1 confirmed move")
  Check(#S.moves == 1, "the in-flight move finished and nothing else started")
  local calls = #S.calls
  S.Pump()
  Check(#S.calls == calls, "stopping is not undoing or continuing")
end
do
  -- closing the bank while a move is in flight
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  c.CloseGuildBank()
  local res = GR.Last()
  Check(not GR.Busy() and res and res.outcome == "review" and res.code == "closed" and res.uncertain == 1, "closing mid-move: Needs review, one uncertain")
  local calls = #S.calls
  S.Open(2)
  S.Pump()
  Check(#S.calls == calls and not GR.Busy(), "reopening the bank resumes nothing")
  Check(GR.Last() == res, "the old result is still the old result")
end
do
  -- closing between moves
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  S.Settle()
  S.Step()
  c.CloseGuildBank()
  local res = GR.Last()
  Check(res and res.outcome == "stopped" and res.code == "closed" and res.confirmed == 1 and res.uncertain == 0, "closing between moves: Stopped, 1 confirmed, none uncertain")
end
do
  -- a reload: nothing carries over
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  local c2 = MIClient("Rich", { db = c.TwichUIDB })
  Check(not c2.TwichUI.MagicInventory.GuildRun.Busy() and c2.TwichUI.MagicInventory.GuildRun.Last() == nil, "after a reload there is no run and no result")
  local joined = {}
  for k in pairs(c.TwichUIDB) do joined[#joined + 1] = k end
  Check(not (c.TwichUIDB.magicInventory and c.TwichUIDB.magicInventory.run), "nothing of the run was saved")
end
do
  -- combat and a rules change stop at the boundary
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  c.FireEvent("PLAYER_REGEN_DISABLED")
  S.Settle()
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "stopped" and res.code == "combat" and res.confirmed == 1, "combat: stopped at the next boundary")
  local c2, S2, MI2, GR2 = Usual()
  local rv2 = Review(MI2, "deposit")
  GR2.Start(rv2)
  MI2.SaveRule({ kind = "keep", enabled = true, name = "Keep it", cats = {}, qualities = {}, include = { [2589] = true }, exclude = {}, equip = "any", bind = "any", keep = 5 })
  S2.Settle()
  S2.Pump()
  local r2 = GR2.Last()
  Check(r2 and r2.outcome == "stopped" and r2.code == "changed", "a rule saved during a run stops it at the boundary (" .. tostring(r2 and r2.code) .. ")")
end

---------------------------------------------------------------------------
-- Final reconciliation and honest outcomes
---------------------------------------------------------------------------
do
  -- everything confirmed, then the approved result is read again and does not match
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  GR.Start(rv)
  for _ = 1, 60 do
    S.Settle()
    if GR.Current() and GR.Current().index > rv.moves then break end
    S.Step()
  end
  Check(GR.Busy() and GR.Current().index > rv.moves, "every move is confirmed; the final check has not run yet")
  local o = rv.ops[1]
  c.GUILD.tabs[2].slots[o.dst.slot].count = c.GUILD.tabs[2].slots[o.dst.slot].count - 1   -- a member takes one
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "review" and res.code == "verify", "an approved result that doesn't verify: Needs review, not Completed (" .. tostring(res and res.outcome) .. ")")
  Check(res.verify and #res.verify > 0, "the check says which slot")
end
do
  -- completed: the plan had nothing left out and the result verifies
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  Check(rv.complete, "nothing was left out of this review")
  GR.Start(rv)
  S.Pump()
  Check(GR.Last().outcome == "completed", "Completed requires the verified result")
end
do
  -- one approved deposit goes to two tabs: each tab is shown, read and placed into in turn, then the player's tab comes back
  local c, S, MI = Fresh({ [1] = { 2589, 20 }, [2] = { 2447, 20 } })
  local GR = MI.GuildRun
  S.Tabs()
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2447, 3) end)
  S.Open(3)
  S.Show(2)
  local rv = Review(MI, "deposit")
  Check(rv.ok and rv.moves == 2 and rv.complete, "the Linen for tab 2 and the herbs for tab 3 are one review")
  Check(#rv.tabs == 2 and rv.tabs[1] == 2 and rv.tabs[2] == 3, "naming both tabs")
  Check(rv.headline:find("tabs 2") and rv.headline:find("3 \"Herbs\""), "the confirmation names the tabs: " .. rv.headline)
  Check(GR.Start(rv), "started")
  S.Pump()
  Check(GR.Last().outcome == "completed", "Completed (" .. tostring(GR.Last().outcome) .. " " .. tostring(GR.Last().reason) .. ")")
  Check(S.TabCount(2, 2589) == 20 and S.TabCount(3, 2447) == 20, "both tabs received their items")
  Check((S.offTab or 0) == 0 and c.GUILD.current == 2, "no call named a tab that was not shown, and tab 2 is shown again")
end

---------------------------------------------------------------------------
-- Authorization: the confirmation is bound to the plan and the state it was made from
---------------------------------------------------------------------------
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  Check(#S.calls == 0, "nothing moves for a review")
  -- a rule saved
  MI.SaveRule({ kind = "keep", enabled = true, name = "Keep", cats = {}, qualities = {}, include = { [2447] = true }, exclude = {}, equip = "any", bind = "any", keep = 1 })
  local ok, code, text, fresh = GR.Start(rv)
  Check(not ok and code == "changed" and fresh and fresh.ok, "a rule saved after the review: confirmation refused, a fresh review offered (" .. tostring(code) .. ")")
  Check(#S.calls == 0 and not GR.Busy(), "and nothing was substituted or started")
  Check(not GR.Start(rv), "the old confirmation can't be used again")
end
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  c.BAGS[0].slots[1].count = 19                      -- a bag stack changed
  local ok, code = GR.Start(rv)
  Check(not ok and code == "changed" and #S.calls == 0, "a bag stack that changed: refused")
  rv = Review(MI, "deposit")
  c.GUILD.tabs[2].slots[rv.ops[1].dst.slot] = { id = 2447, count = 1 }; S.Show(2)   -- a bank slot the plan uses changed
  ok, code = GR.Start(rv)
  Check(not ok and code == "changed" and #S.calls == 0, "a bank slot that changed: refused")
  rv = Review(MI, "deposit")
  c.GUILD.tabs[2].canDeposit = false; c.FireEvent("GUILDBANK_UPDATE_TABS")
  ok, code = GR.Start(rv)
  Check(not ok and #S.calls == 0, "rights that changed: refused")
  c.GUILD.tabs[2].canDeposit = true; c.FireEvent("GUILDBANK_UPDATE_TABS")
  rv = Review(MI, "deposit")
  S.Tick(130)
  ok, code = GR.Start(rv)
  Check(not ok and code == "old" and #S.calls == 0, "a review left too long: refused")
  rv = Review(MI, "deposit")
  c.CloseGuildBank()
  ok = GR.Start(rv)
  Check(not ok and #S.calls == 0, "a closed guild bank: refused")
end
do
  -- repeated clicks
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  local first = GR.Start(rv)
  local second, code = GR.Start(rv)
  local other = Review(MI, "deposit")
  Check(first and not second, "the second click on the same review is refused (" .. tostring(code) .. ")")
  Check(not other.ok and other.refuse.code == "busy", "a new review while running is refused")
  local ok3 = GR.Start(rv)
  Check(not ok3, "a third click too")
  local n = #S.calls
  local ok, why = MI.Run.CanDeposit({ generation = MI.Generation() }, { kind = "guild", steps = { 1 }, where = {} })
  Check(ok == false and why == "Another transfer is in progress.", "the older deposit button refuses while a run is under way")
  S.Pump()
  Check(GR.Last().outcome == "completed" and #S.moves == rv.moves, "one run, each move once")
  Check(n >= 1, "something was dispatched by the first click only")
end
do
  -- opening, a rule saved, bag events: nothing starts by itself
  local c, S, MI, GR = Usual()
  c.FireEvent("BAG_UPDATE_DELAYED")
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false)
  MI.SaveRule({ kind = "keep", enabled = true, name = "Keep", cats = {}, qualities = {}, include = { [2447] = true }, exclude = {}, equip = "any", bind = "any", keep = 1 })
  c.CloseGuildBank(); S.Open(2)
  S.Pump()
  Check(#S.calls == 0 and not GR.Busy() and GR.Current() == nil, "no event, save or reopening starts anything")
end
do
  -- the draft in the settings is not the saved arrangement: the review sees only what is saved
  local c, S, MI, GR = Fresh({ [1] = { 2589, 20 } })
  Arrange(c, MI, function(D, d, ctx) D.AssignTab(d, ctx, 2589, 2) end)
  S.Open(2)
  local d = MI.Design.Load(MI.Rules(), { guild = "Night Owls", names = { [1] = { name = "Gear" }, [2] = { name = "Cloth" }, [3] = { name = "Herbs" } }, numTabs = 3,
    resolve = MI.Resolve, facts = function(id) return (MI.ItemFacts(id)) end })
  MI.Design.AssignTab(d, { facts = function(id) return (MI.ItemFacts(id)) end }, 2589, 3)
  Check(MI.Design.Dirty(d), "an unsaved change exists in the draft")
  local rv = Review(MI, "deposit")
  Check(rv.ok and rv.ops[1].dst.tab == 2, "the review follows the saved arrangement (tab 2), not the draft (tab 3)")
end

---------------------------------------------------------------------------
-- A client that wants a click for each move
---------------------------------------------------------------------------
do
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  S.requireClick = true
  S.inClick = true
  GR.Start(rv)
  S.inClick = false
  S.Settle()
  S.Pump()
  Check(GR.Busy() and GR.Progress().needClick and GR.Progress().confirmed == 1, "the game blocked an action outside a click: the run waits for Continue, 1 confirmed")
  Check(S.cursor == nil, "nothing was left on the cursor")
  local calls = #S.calls
  S.Tick(30)
  Check(#S.calls == calls and GR.Busy(), "it does not poll or retry while waiting for the click")
  for _ = 1, 10 do
    if not GR.Busy() then break end
    S.inClick = true
    GR.Continue()
    S.inClick = false
    S.Settle()
    S.Pump()
  end
  Check(GR.Last() and GR.Last().outcome == "completed" and #S.moves == rv.moves, "one move per click, then Completed")
end
do
  -- blocked even in a click: the run stops there
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  S.requireClick = true
  S.inClick = false
  GR.Start(rv)
  S.Pump()
  Check(GR.Busy() and GR.Progress().needClick, "blocked from the start: it asks for a click")
  GR.Continue()
  S.Pump()
  Check(not GR.Busy() and GR.Last().code == "blocked" and GR.Last().outcome == "stopped", "blocked even in the click: stopped, honestly")
end

do
  -- the game refuses only the placing outside a click: the item waits on the cursor for the player's click
  local c, S, MI, GR = Usual()
  local rv = Review(MI, "deposit")
  S.requireClick, S.onlyPlace = true, true
  S.inClick = true
  GR.Start(rv)
  S.inClick = false
  S.Settle()
  S.Pump()
  Check(GR.Busy() and GR.Progress().needClick and S.cursor ~= nil, "a refused placing: the run's item waits on the cursor and the run asks for a click")
  Check(GR.Progress().confirmed == 1, "the first move (placed inside the opening click) is confirmed")
  local held = S.cursor
  S.Tick(30)
  Check(GR.Busy() and S.cursor == held and (S.cleared or 0) == 0, "waiting for the click is not a timeout and the cursor is not touched")
  for _ = 1, 20 do
    if not GR.Busy() then break end
    S.inClick = true
    GR.Continue()
    S.inClick = false
    S.Settle()
    S.Pump()
  end
  Check(GR.Last() and GR.Last().outcome == "completed" and #S.moves == rv.moves and S.cursor == nil, "each placing needed a click; then Completed with an empty cursor")
end

do
  -- splitting off: a part-stack move is listed as not included and never attempted; the older whole-stack review is unchanged
  local c, S, MI = Fresh({ [1] = { 2589, 20 } })
  Arrange(c, MI, function(D, d, ctx) D.PlaceSlot(d, ctx, 2589, 2, 5, 12) end)
  S.Open(2)
  Check(MI.SPLIT.guild == false, "the older review and deposit still move whole stacks only")
  MI.GuildRun.CAN_SPLIT = false
  local rv = Review(MI, "deposit")
  Check(not rv.ok and rv.dropped[1] and rv.dropped[1].code == "needs-split", "with splitting off, the part-stack move is not included")
  Check(rv.dropped[2] and rv.dropped[2].code == "depends", "and the move that builds on it goes with it, even though it would replay on its own")
  Check(#S.calls == 0, "and nothing is attempted")
end

print(failures == 0 and "PASSED test_magic_inventory_guildrun" or ("FAILED: " .. failures))
if failures > 0 then os.exit(1) end
