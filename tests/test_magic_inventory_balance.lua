-- Balance quantities across partial stacks using the real planner and character-bank adapter.
-- Synthetic server data; no live bank actions.
dofile(TESTS .. "mi_mock.lua")
local failures = 0
local function Check(ok, why)
  if not ok then failures = failures + 1; print("FAIL: " .. why) end
end
local function Fresh(have, stored)
  local c = MIClient("Rich", { db = { modules = { magicInventory = true } } })
  c.ITEMS[2447].maxStack = 100
  c.Bags({ [0] = { size = 8, slots = have > 0 and { [1] = { 2447, have } } or {} },
    [6] = { size = 8, slots = stored > 0 and { [1] = { 2447, stored } } or {} } })
  local MI = c.TwichUI.MagicInventory
  MI.SaveRule({ name = "Balance 20", kind = "bank", flow = "balance", keep = 20,
    enabled = true, include = { [2447] = true } })
  c.OpenBank()
  return c, MI, MI.Run
end
local function Group(p, dir)
  for _, g in ipairs(p.groups) do if (g.dir or "deposit") == dir then return g end end
end
for _, sample in ipairs({ { 5, 100, 20 }, { 55, 10, 20 }, { 0, 100, 20 }, { 5, 8, 13 } }) do
  local have, stored, expected = unpack(sample)
  local c, MI, Run = Fresh(have, stored)
  local dir = have > 20 and "deposit" or "withdraw"
  local p = MI.CurrentPlan(nil)
  local g = Group(p, dir)
  Check(g and g.items == math.abs(expected - have), "preview plans exact balance from " .. have .. "/" .. stored)
  Check(not Group(p, dir == "deposit" and "withdraw" or "deposit"), "only one direction per item")
  Check(#c.PICKUPS == 0 and not c.CURSOR, "preview does not move anything")
  Check(Run.Deposit(p, g), "start reviewed balance")
  c.Settle()
  Check(Run.CarriedCount(2447) == expected, "bags reach the available target")
  local bank = c.BAGS[6].slots[1]
  Check(bank and bank.count == have + stored - expected or not bank and have + stored == expected, "total quantity conserved")
  Check(Run.Last() and Run.Last().stopReason == "done" and #Run.Last().results.confirmed == 1, "both sides confirmed")
  Check(#MI.CurrentPlan("bank").groups == 0, "repeat review does not move the balanced item")
end
-- The carried total changed while the reviewed source stack stayed in place.
do
  local c, MI, Run = Fresh(55, 10)
  c.BAGS[0].slots[2] = { id = 2447, count = 10, locked = false, bound = false }
  local p = MI.CurrentPlan("bank")
  c.BAGS[0].slots[2] = nil
  Run.Deposit(p, Group(p, "deposit"))
  Check(not c.PENDING_MOVES or #c.PENDING_MOVES == 0, "changed carried total cannot deposit below keep")
end
-- At target, left out, protected, stale source, changed carried quantity and closed bank.
do
  local c, MI, Run = Fresh(20, 100)
  Check(#MI.CurrentPlan(nil).groups == 0, "at target needs no transfer")
  c.CloseBank()
  Check(#MI.CurrentPlan(nil).groups == 0, "closed bank not read for preview")
end
for _, change in ipairs({ "left-out", "never", "source", "carried", "closed", "refused", "wrong-amount" }) do
  local c, MI, Run = Fresh(5, 100)
  local p = MI.CurrentPlan("bank")
  local g = Group(p, "withdraw")
  if change == "left-out" then
    p = MI.CurrentPlan("bank", { [g.entries[1].key] = true }); g = Group(p, "withdraw")
    Check(g.items == 0 and #g.steps == 0, "left-out withdrawal has no executable steps")
  elseif change == "never" then MI.SetNever(2447, true)
  elseif change == "source" then c.BAGS[6].slots[1].count = 99
  elseif change == "carried" then c.BAGS[0].slots[1].count = 19
  elseif change == "closed" then c.CloseBank()
  elseif change == "refused" then c.BANK_REFUSES = true end
  Run.Deposit(p, g)
  if change == "wrong-amount" then
    c.PENDING_MOVES[1].count = 14
    c.Settle()
    Check(Run.Current() ~= nil and #Run.Current().results.confirmed == 0, "wrong split quantity not confirmed")
    RunLongTimers(10)
    Check(Run.Last().stopReason == "uncertain", "wrong quantity stops without retry")
  else
    Check(not c.PENDING_MOVES or #c.PENDING_MOVES == 0, change .. " prevents transfer")
    Check(c.BAGS[6].slots[1].count == (change == "source" and 99 or 100), change .. " preserves source")
  end
end
if failures > 0 then os.exit(1) end
print("PASSED test_magic_inventory_balance")
