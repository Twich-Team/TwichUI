-- Magic Inventory, withdrawing from a guild bank (inventory/GuildPlan.lua withdraw mode, inventory/GuildRun.lua), against the
-- scripted stand-in server (tests/mi_guildsim.lua). Synthetic data only: it proves the planner's and the run's decisions, not
-- what Forever's guild bank does.
--   * only rules that withdraw, only from their own tab, whole stacks, never past the target;
--   * the review gives each stack an empty bag slot; full bags leave stacks out; the rank's rights and allowance are honoured;
--   * the run: each stack confirmed from the tab and the bag; bags that changed since the review stop it before going over;
--   * deposits and arrangements are not affected by a rule that only withdraws.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "mi_guildsim.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local function Fresh(bags, herbs)
  local c = MIClient("Rich", { db = { modules = { magicInventory = true } } })
  local S = GuildSim(c)
  local MI = c.TwichUI.MagicInventory
  c.GUILD.name = "Night Owls"
  local function Tab(name) return { name = name, icon = 133, slots = {}, withdraw = -1, remaining = -1 } end
  c.GUILD.tabs = { [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") }
  for slot, st in pairs(herbs or {}) do c.GUILD.tabs[3].slots[slot] = { id = st[1], count = st[2] } end
  c.GUILD.current = 3
  c.Bags({ [0] = { size = 16, slots = bags or {} } })
  local dest = MI.AddDest("guild", "Herb tab")
  MI.SetGuildTab(dest, "Night Owls", 3, "Herbs")
  return c, S, MI, dest
end
local function Rule(MI, fields)
  local r = { kind = "guild", enabled = true, cats = {}, qualities = {}, include = {}, exclude = {}, equip = "any", bind = "any", keep = 0 }
  for k, v in pairs(fields) do r[k] = v end
  local id = MI.SaveRule(r)
  Check(MI.Rule(id) and MI.Rule(id).enabled, "rule " .. (fields.name or "?") .. " is on")
  return id
end
local function Carried(c, id)
  local n = 0
  for _, b in pairs(c.BAGS) do for _, s in pairs(b.slots) do if s.id == id then n = n + s.count end end end
  return n
end

---------------------------------------------------------------------------
-- 25 carried, target 40, the tab holds 20, 10 and 5: the 10 and the 5 come out, into empty bag slots
---------------------------------------------------------------------------
do
  local c, S, MI, dest = Fresh({ [1] = { 2447, 20 }, [2] = { 2447, 5 } }, { [1] = { 2447, 20 }, [2] = { 2447, 10 }, [3] = { 2447, 5 } })
  local GR = MI.GuildRun
  Rule(MI, { name = "Keep 40 Peacebloom", dest = dest, cats = { "7:9" }, flow = "withdraw", keep = 40 })
  S.Open(3)
  Check(#S.calls == 0, "opening the guild bank moves nothing")
  local plan = MI.CurrentGuildPlan("withdraw")
  Check(#plan.ops == 2 and plan.ops[1].to.kind == "bag", "two withdrawals planned, to the bags")
  local dplan = MI.CurrentGuildPlan("deposit")
  local deposits = 0
  for _, o in ipairs(dplan.ops) do if o.status == "ok" then deposits = deposits + 1 end end
  Check(deposits == 0, "a rule that only withdraws deposits nothing")
  local rv = GR.Review("withdraw")
  Check(rv.ok and rv.moves == 2 and rv.quantity == 15, "the review: 2 stacks, 15 items: " .. tostring(rv.refuse and rv.refuse.text))
  Check(rv.ops[1].dst.kind == "bag" and rv.ops[1].dst.bag == 0 and rv.ops[1].dst.slot ~= rv.ops[2].dst.slot, "each to its own empty bag slot")
  Check(rv.headline and rv.headline:find("^Withdraw 2 stacks from tab 3"), "it says what it does: " .. tostring(rv.headline))
  Check(#S.calls == 0, "reviewing touched nothing")
  local ok, code = GR.Start(rv)
  Check(ok, "the player's approval starts it: " .. tostring(code))
  S.Pump()
  local res = GR.Last()
  Check(res and res.outcome == "completed" and res.confirmed == 2, "completed, each stack confirmed: " .. tostring(res and res.outcome) .. " " .. tostring(res and res.reason))
  Check(Carried(c, 2447) == 40 and S.TabCount(3, 2447) == 20, "40 in the bags, the stack of 20 left in the tab")
  Check(S.swaps == 0 and (S.offTab or 0) == 0 and not S.cleared, "no swap, nothing done on a tab not shown, the cursor never cleared")
  rv = GR.Review("withdraw")
  Check(not rv.ok and rv.refuse.code == "nothing", "at the target: nothing to withdraw")
end

---------------------------------------------------------------------------
-- never past the target, only the rule's tab, the Never transfer list
---------------------------------------------------------------------------
do
  local c, S, MI, dest = Fresh({ [1] = { 2447, 30 } }, { [1] = { 2447, 20 } })
  c.ITEMS[2447].maxStack = 40
  c.GUILD.tabs[2].slots[1] = { id = 2447, count = 5 }   -- in another tab: not this rule's
  Rule(MI, { name = "Keep 40 Peacebloom", dest = dest, cats = { "7:9" }, flow = "withdraw", keep = 40 })
  S.Open(3)
  local plan = MI.CurrentGuildPlan("withdraw")
  Check(#plan.ops == 0, "a stack of 20 would make 50, and the 5 is in another tab: nothing")
  Check(plan.untouched[1] and plan.untouched[1].text:find("go over 40"), "it says why: " .. tostring(plan.untouched[1] and plan.untouched[1].text))
  c.ITEMS[2447].maxStack = 20
end
do
  local c, S, MI, dest = Fresh({}, { [1] = { 2447, 20 } })
  Rule(MI, { name = "Keep 40 Peacebloom", dest = dest, cats = { "7:9" }, flow = "withdraw", keep = 40 })
  MI.SetNever(2447, true)
  S.Open(3)
  Check(#MI.CurrentGuildPlan("withdraw").ops == 0, "the Never transfer list: not withdrawn")
end

---------------------------------------------------------------------------
-- rights and allowance; full bags
---------------------------------------------------------------------------
do
  local c, S, MI, dest = Fresh({}, { [1] = { 2447, 10 }, [2] = { 2447, 10 } })
  c.GUILD.tabs[3].withdraw = 0
  Rule(MI, { name = "Keep 40 Peacebloom", dest = dest, cats = { "7:9" }, flow = "withdraw", keep = 40 })
  S.Open(3)
  local plan = MI.CurrentGuildPlan("withdraw")
  Check(#plan.ops == 0 and plan.withdrawRules[1] and plan.withdrawRules[1].code == "no-withdraw", "a rank that can't withdraw there: the rule says so")
  c.GUILD.tabs[3].withdraw, c.GUILD.tabs[3].remaining = 5, 1
  S.Show(3)
  local rv = MI.GuildRun.Review("withdraw")
  Check(rv.ok and rv.moves == 1 and #rv.dropped == 1 and rv.dropped[1].code == "limit", "one withdrawal left today: one stack, the other left out")
end
do
  local full = {}
  for i = 1, 16 do full[i] = { 2589, 20 } end
  local c, S, MI, dest = Fresh(full, { [1] = { 2447, 10 } })
  Rule(MI, { name = "Keep 40 Peacebloom", dest = dest, cats = { "7:9" }, flow = "withdraw", keep = 40 })
  S.Open(3)
  local rv = MI.GuildRun.Review("withdraw")
  Check(not rv.ok and rv.dropped[1] and rv.dropped[1].code == "bags-full", "no free bag slot: left out, and nothing to start")
end

---------------------------------------------------------------------------
-- the bags change during the run: the next stack would go over, so the run stops before it
---------------------------------------------------------------------------
do
  local c, S, MI, dest = Fresh({ [1] = { 2447, 20 } }, { [1] = { 2447, 10 }, [2] = { 2447, 10 } })
  local GR = MI.GuildRun
  Rule(MI, { name = "Keep 40 Peacebloom", dest = dest, cats = { "7:9" }, flow = "withdraw", keep = 40 })
  S.Open(3)
  local rv = GR.Review("withdraw")
  Check(rv.ok and rv.moves == 2, "two stacks of 10 reviewed")
  S.hook = function(n, call)
    if n == 2 then c.BAGS[0].slots[9] = { id = 2447, count = 15, bound = false, locked = false } end   -- the player picks up 15 more
  end
  GR.Start(rv)
  S.Pump()
  S.hook = nil
  local res = GR.Last()
  Check(res and res.code == "over" and res.confirmed == 1, "one confirmed, then stopped before going over: " .. tostring(res and res.code))
  Check(Carried(c, 2447) == 45 and S.TabCount(3, 2447) == 10, "the second stack stayed in the tab")
end

if failures == 0 then print("PASSED test_magic_inventory_guildwithdraw") else print(failures .. " failures") os.exit(1) end
