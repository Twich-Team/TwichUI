-- Character-bank batch semantics and one-visit per-rule overrides, synthetic inventories only.
dofile(TESTS .. "mi_mock.lua")
local failures = 0
local function Check(ok, why) if not ok then failures = failures + 1; print("FAIL: " .. why) end end
local function Fresh()
  local c = MIClient("Rich", { db = { modules = { magicInventory = true } } })
  c.ITEMS[2447].maxStack = 100
  c.Bags({ [0] = { size = 4, slots = { [1] = { 2447, 55 }, [2] = { 2589, 1 } } },
    [6] = { size = 8, slots = { [1] = { 2447, 20 }, [2] = { 2589, 20 }, [3] = { 2770, 20 } } } })
  local MI = c.TwichUI.MagicInventory
  c.SORTS = {}
  c.C_Container.SortBank = function(bankType)
    Check(not MI.Run.Busy() and not c.CURSOR, "bank sort runs after the transfer releases the cursor")
    c.SORTS[#c.SORTS + 1] = "bank:" .. bankType
  end
  c.C_Container.SortBags = function() c.SORTS[#c.SORTS + 1] = "bags" end
  local herbs = MI.SaveRule({ name = "Herbs", enabled = true, kind = "bank", flow = "balance", keep = 20, include = { [2447] = true } })
  local cloth = MI.SaveRule({ name = "Cloth", enabled = true, kind = "bank", flow = "balance", keep = 10, include = { [2589] = true } })
  c.OpenBank()
  return c, MI, MI.Run, herbs, cloth
end
local function Settle(c, Run)
  for _ = 1, 12 do if not Run.Current() then break end; c.Settle() end
end
-- One approval covers deposits and withdrawals; attempted work cannot fill the progress bar.
do
  local c, MI, Run = Fresh()
  local p = MI.CurrentPlan("bank")
  Check(p.stacks == 2 and #c.PICKUPS == 0 and #c.SORTS == 0, "opening and planning never move or sort items")
  Check(MI.BankAutoSort() and not c.TwichUIDB.magicInventory, "the default is on without writing saved data")
  local snapshots = {}
  Run.OnUpdate(function() local prog = Run.BankProgress(); if prog then snapshots[#snapshots + 1] = prog.confirmed end end)
  Check(Run.Bank(p), "start one bank batch")
  Check(Run.Current().steps[1].withdraw == false and Run.Current().steps[2].withdraw == true, "deposits precede withdrawals")
  Check(Run.BankProgress().total == 2 and Run.BankProgress().confirmed == 0, "attempted first move is not progress")
  c.Settle()
  Check(Run.Current() and Run.Current().state == "withdrawing" and Run.BankProgress().confirmed == 1, "continues to withdrawal without another click")
  Check(#c.SORTS == 0, "neither inventory sorts while a move is pending")
  c.Settle()
  local last, prog = Run.Last(), Run.BankProgress()
  Check(last.stopReason == "done" and #last.results.confirmed == 2, "both directions confirmed in one result")
  Check(table.concat(c.SORTS, ",") == "bank:" .. c.Enum.BankType.Character .. ",bags",
    "a completed bank batch sorts the character bank and bags once")
  Check(not prog.active and prog.confirmed == 2 and prog.total == 2, "finished progress retained")
  Check(Run.CarriedCount(2447) == 20 and Run.CarriedCount(2589) == 10, "both bag targets reached")
  Check(p.groups[1].steps[1].withdraw == nil and p.groups[1].steps[1].lockTries == nil, "reviewed steps not mutated")
  Check(not Run.Bank(MI.CurrentPlan(nil)), "settings preview cannot execute the bank batch")
end
-- An explicit Off survives the next load of the feature and suppresses both native sorts.
do
  local c, MI, Run = Fresh()
  MI.SetBankAutoSort(false)
  Check(Run.Bank(MI.CurrentPlan("bank")), "start an opted-out batch")
  Settle(c, Run)
  Check(Run.Last().stopReason == "done" and #c.SORTS == 0, "Off leaves sorting to the player")
  local reloaded = MIClient("Rich", { db = c.TwichUIDB })
  local preference = reloaded.TwichUI.MagicInventory
  Check(preference.BankAutoSort() == false, "Off survives reloading the saved preference")
  preference.SetBankAutoSort(true)
  Check(preference.BankAutoSort(), "the player can reenable sorting")
end
-- Full bags can be freed by an earlier deposit in the same reviewed batch.
do
  local c, MI, Run = Fresh()
  c.Bags({ [0] = { size = 1, slots = { [1] = { 2447, 55 } } },
    [6] = { size = 3, slots = { [1] = { 2589, 20 } } } })
  local herb = MI.Rules()[1]; herb.flow, herb.keep = "deposit", 0; MI.SaveRule(herb)
  Check(Run.Bank(MI.CurrentPlan("bank")), "full-bag batch starts")
  Settle(c, Run)
  Check(Run.Last().stopReason == "done" and Run.CarriedCount(2589) == 10, "deposit frees the slot used by withdrawal")
end
-- Manual actions override only the selected rule, with no persisted edit, even on a disabled saved rule.
for _, dir in ipairs({ "deposit", "withdraw" }) do
  local c, MI, Run, herbs = Fresh()
  MI.SetRuleEnabled(herbs, false)
  local gen = MI.Generation()
  local p = MI.CurrentPlan("bank", nil, { ruleId = herbs, dir = dir })
  Check(p.manual.ruleId == herbs and #p.groups == 1, "manual review contains one selected rule")
  Check(p.groups[1].items == (dir == "deposit" and 55 or 20), "all matching stock, ignoring saved target")
  Check(Run.Bank(p), "start manual " .. dir)
  Settle(c, Run)
  Check(Run.Last().stopReason == "done" and Run.CarriedCount(2447) == (dir == "deposit" and 0 or 75), "manual " .. dir .. " moves all selected stock")
  Check(Run.CarriedCount(2589) == 1 and c.BAGS[6].slots[3].count == 20, "unselected rules and items untouched")
  Check(MI.Generation() == gen and MI.Rule(herbs).keep == 20 and MI.Rule(herbs).flow == "balance" and not MI.Rule(herbs).enabled, "manual override does not edit saved rule or generation")
end
-- All truly means all, including stock beyond MAX_KEEP.
do
  local c, MI, Run, herbs = Fresh()
  c.ITEMS[2447].maxStack = 20000
  c.BAGS[6].slots[1].count = 15000
  local p = MI.CurrentPlan("bank", nil, { ruleId = herbs, dir = "withdraw" })
  Check(p.items == 15000, "withdraw all is not capped at a saved target limit")
  Check(Run.Bank(p), "start large manual withdrawal"); Settle(c, Run)
  Check(Run.CarriedCount(2447) == 15055, "large matching stock withdrawn")
end
-- Keep protections and Never transfer are still effective during manual use.
do
  local c, MI, Run, herbs = Fresh()
  MI.SaveRule({ name = "Keep some", kind = "keep", enabled = true, keep = 7, include = { [2447] = true } })
  c.TwichUI.Restock = { Protects = function() return true end, Rule = function() return { target = 9 } end }
  local p = MI.CurrentPlan("bank", nil, { ruleId = herbs, dir = "deposit" })
  Check(p.items == 46, "manual deposit retains other keep and vendor targets")
  Check(Run.Bank(p), "protected deposit starts"); Settle(c, Run)
  Check(Run.CarriedCount(2447) == 9, "protected target retained")
  MI.SetNever(2447, true)
  for _, dir in ipairs({ "deposit", "withdraw" }) do
    Check(MI.CurrentPlan("bank", nil, { ruleId = herbs, dir = dir }).items == 0, "Never transfer protects manual " .. dir)
  end
end
-- Global Never transfer rules, item protections and per-rule exclusions cannot be overridden.
do
  local c, MI, Run, herbs = Fresh()
  MI.SaveRule({ name = "Protected", kind = "never", enabled = true, include = { [2447] = true } })
  Check(MI.CurrentPlan("bank", nil, { ruleId = herbs, dir = "withdraw" }).items == 0, "Never rule protects manual withdrawal")
end
for _, protection in ipairs({ "locked", "quest", "conjured", "inSet" }) do
  local c, MI, Run, herbs = Fresh()
  local id = protection == "conjured" and 8079 or protection == "inSet" and 9001 or 2447
  c.BAGS[0].slots[1].id = id
  c.BAGS[0].slots[1][protection] = true
  local rule = MI.Rule(herbs); rule.include = { [id] = true }; MI.SaveRule(rule)
  Check(MI.CurrentPlan("bank", nil, { ruleId = herbs, dir = "deposit" }).items == 0, protection .. " protects manual deposit")
end
-- Stops/failures never transition into the next direction or retry uncertain work.
for _, stop in ipairs({ "stop", "close", "combat", "rules", "refused", "uncertain" }) do
  local c, MI, Run, herbs = Fresh()
  Check(Run.Bank(MI.CurrentPlan("bank")), "start " .. stop .. " batch")
  if stop == "stop" then Run.Stop()
  elseif stop == "close" then c.CloseBank()
  elseif stop == "combat" then c.COMBAT = true; c.FireEvent("PLAYER_REGEN_DISABLED")
  elseif stop == "rules" then MI.SetRuleEnabled(herbs, false); c.Settle()
  elseif stop == "refused" then c.PENDING_MOVES = {}; RunLongTimers(10)
  elseif stop == "uncertain" then c.PENDING_MOVES = {}; c.BAGS[0].slots[1] = nil; RunLongTimers(10) end
  Check(not Run.Current() and #c.SORTS == 0, stop .. " ends the batch without sorting")
  Check(Run.CarriedCount(2589) == 1, stop .. " prevents following withdrawal")
  Check(Run.BankProgress().confirmed < Run.BankProgress().total, stop .. " never shows full confirmed progress")
end
-- Generation/closed/disabled/cursor guards apply before a batch starts.
for _, guard in ipairs({ "rules", "closed", "off", "cursor" }) do
  local c, MI, Run, herbs = Fresh()
  local p = MI.CurrentPlan("bank")
  if guard == "rules" then MI.SetRuleEnabled(herbs, false)
  elseif guard == "closed" then c.CloseBank()
  elseif guard == "off" then c.TwichUIDB.modules.magicInventory = false
  else c.CURSOR = { other = true } end
  Check(not Run.Bank(p) and #c.PICKUPS == 0, guard .. " prevents starting")
end
if failures > 0 then os.exit(1) end
print("PASSED test_magic_inventory_bank")
