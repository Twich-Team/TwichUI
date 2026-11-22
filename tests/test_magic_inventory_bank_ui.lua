-- Compact bank controls against real planning/running code and stand-in frames/inventory.
dofile(TESTS .. "mi_mock.lua")
local failures = 0
local function Check(ok, why) if not ok then failures = failures + 1; print("FAIL: " .. why) end end
local c = MIClient("Rich", { db = { modules = { magicInventory = true } }, beforeFiles = function(cl)
  cl.CreateFrame = function(kind, name, parent) local f = MIFake(kind, parent); if name then cl[name] = f end; return f end
  cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
  cl.GameTooltip = MIFake("GameTooltip")
  for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "CraftLook.lua" }) do
    local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
  end
end, files = MI_FILES })
local MI = c.TwichUI.MagicInventory
local Run, Win = MI.Run, MI.Window
local function Flush() for _ = 1, 8 do FlushTimers() end end
local function Find(frame, label)
  if frame.shown == false then return end
  if type(frame.text) == "table" and frame.text.text == label then return frame end
  for _, child in ipairs(frame.children or {}) do local found = Find(child, label); if found then return found end end
end
local function Has(frame, text)
  if frame.shown == false then return false end
  if type(frame.text) == "string" and frame.text:find(text, 1, true) then return true end
  for _, child in ipairs(frame.children or {}) do if Has(child, text) then return true end end
  return false
end
local function Click(frame, label)
  local b = Find(frame, label)
  Check(b and b.enabled, "enabled button: " .. label)
  if b and b.enabled then b:Fire("OnClick", "LeftButton") end
  Flush()
end
c.ITEMS[2447].maxStack = 100
c.Bags({ [0] = { size = 6, slots = { [1] = { 2447, 55 }, [2] = { 2589, 1 } } },
  [6] = { size = 6, slots = { [1] = { 2447, 20 }, [2] = { 2589, 20 } } } })
local herbs = MI.SaveRule({ name = "Herbs", kind = "bank", enabled = true, flow = "balance", keep = 20, include = { [2447] = true } })
MI.SaveRule({ name = "Cloth", kind = "bank", enabled = true, flow = "balance", keep = 10, include = { [2589] = true } })
c.OpenBank(); Flush()
Check(not Win.IsShown() and not Run.Current() and #c.PICKUPS == 0, "opening does not show review or run")
Win.Show(); Flush()
local f = c.TwichUIMagicInventory
Check(f.craftedFrame and f.bankSummary.shown, "crafted bank review built")
Check(Has(f, "Deposit 35 · Bags 55 → 20") and Has(f, "Withdraw 9 · Bags 1 → 10"), "concise item intentions and bag counts")
Check(not Has(f, "Reserved by other rules") and not Find(f, "Deposit 1 stack"), "old verbose groups and staged actions absent")
Check(f.bankSummary.deposit.value.text == "35 items" and f.bankSummary.withdraw.value.text == "9 items", "summary separates both quantities")
local autoSort = f.bankAutoSort
local function ClickAutoSort()
  autoSort:Fire("OnClick", "LeftButton"); Flush()
end
Check(autoSort:IsShown() and autoSort:GetChecked() and autoSort.w == 42 and Has(f, "Auto-sort"),
  "bank review displays the shared default-on switch")
ClickAutoSort()
Check(not autoSort:GetChecked() and MI.BankAutoSort() == false, "the switch saves and displays Off")
Click(f, "Run rules")
ClickAutoSort()
Check(not autoSort:GetChecked() and MI.BankAutoSort() == false, "the sorting choice is disabled during a transfer")
Check(Run.Current() and not f.bankGo.shown and f.stop.shown, "one action starts whole batch; Stop replaces it")
Check(f.bankProgress.shown and not f.bankProgress.fill.shown, "attempted moves do not fill progress")
Check(not f.manage.enabled and not f.again.enabled, "review controls disabled while running")
c.Settle(); Flush()
Check(Run.Current() and Run.Current().state == "withdrawing", "continues to second direction")
Check(f.bankProgress.text.text == "1 / 2 moves confirmed" and f.bankProgress.fill.w > 1, "visible confirmed progress")
c.Settle(); Flush()
Check(not Run.Current() and Has(f, "Completed") and f.bankProgress.text.text == "2 / 2 moves confirmed", "one completion and full confirmed progress")
Check(Run.CarriedCount(2447) == 20 and Run.CarriedCount(2589) == 10, "both targets reached")
Click(f, "Details")
Check(Has(f, "Last transfer") and Find(f, "Hide details"), "details are accessible without permanent prose")
Click(f, "Hide details")
-- Selecting manual actions changes only the review. It must not run until its primary action is clicked.
local gen = MI.Generation()
Click(f, "Rule actions")
Check(Find(f, "Deposit all") and Find(f, "Withdraw all"), "per-rule manual actions offered")
Click(f, "Deposit all")
Check(Win.Plan().manual.ruleId == herbs and Win.Plan().items == 20 and not Run.Current(), "deposit all reviews selected rule without running")
Check(not f.bankProgress.shown, "old result dismissed when starting another review")
Check(MI.Generation() == gen and MI.Rule(herbs).keep == 20, "manual selection leaves saved data unchanged")
Click(f, "Leave out")
Check(not f.bankGo.enabled and Win.Plan().items == 0, "manual review supports exclusions")
Click(f, "Include")
Click(f, "Deposit all")
c.Settle(); Flush()
Check(Run.CarriedCount(2447) == 0, "manual primary action deposits full matching quantity")
Click(f, "Use rules")
Click(f, "Rule actions")
Click(f, "Withdraw all")
Check(Win.Plan().manual.dir == "withdraw" and Win.Plan().items == 75 and not Run.Current(), "withdraw all reviews all selected bank stock")
c.CloseBank(); Flush()
Check(not Win.IsShown(), "closing bank closes bank review")
c.OpenBank(); Flush(); Win.Show(); Flush()
Check(Win.Plan().manual == nil and Find(f, "Run rules"), "one-visit override cleared by bank close")
Check(not autoSort:GetChecked(), "reopening the bank preserves the switch state")
ClickAutoSort()
Check(autoSort:GetChecked() and MI.BankAutoSort(), "turning sorting back on updates the saved choice")
-- Stale override selection is discarded when its rule is removed.
Click(f, "Rule actions"); Click(f, "Withdraw all")
MI.DeleteRule(herbs); Flush()
Check(not Win.Plan().manual, "deleted manual rule falls back to regular review")
Win.Show(true); Flush()
Check(not f.bankGo.shown and not f.bankAutoSort.shown and Win.Context() == nil and #c.PENDING_MOVES == 0, "settings preview cannot execute bank batch")
-- Pools and hooks stay bounded across repeated visits.
c.CloseBank(); Flush(); c.OpenBank(); Flush(); Win.Show(); Flush()
Click(f, "Rule actions"); Click(f, "Back")
local frames, listeners = Win.FrameCount(), Run.ListenerCount()
for _ = 1, 10 do c.CloseBank(); Flush(); c.OpenBank(); Flush(); Win.Show(); Flush(); Click(f, "Rule actions"); Click(f, "Back") end
Check(Win.FrameCount() == frames and Run.ListenerCount() == listeners, "repeated visits reuse rows and listeners")
-- At the rule limit, pooled heading buttons must adopt the compact per-rule width.
for i = #MI.Rules() + 1, MI.MAX_RULES do
  MI.SaveRule({ name = "Expedition supplies for a very long journey " .. i, kind = "bank", flow = "balance", keep = 20,
    enabled = false, include = { [2447] = true } })
end
local rejected = MI.SaveRule({ name = "One over the limit", kind = "bank", include = { [2447] = true } })
Check(not rejected and #MI.Rules() == MI.MAX_RULES, "the rule limit is enforced without dropping saved rules")
Flush()
Click(f, "Rule actions")
local shown = 0
for _, row in ipairs(f.content.children) do
  if row.shown and row.withdrawAll and row.withdrawAll.shown then
    shown = shown + 1
    Check(row.action.w == 102 and row.withdrawAll.w == 102, "reused manual controls keep their compact width")
  end
end
Check(shown == MI.MAX_RULES and MI.MAX_RULES > 40, "every saved bank rule has both manual actions")
frames = Win.FrameCount()
Click(f, "Back"); Click(f, "Rule actions")
Check(Win.FrameCount() == frames, "full rule review reuses its warmed row pool")
if failures > 0 then os.exit(1) end
print("PASSED test_magic_inventory_bank_ui")
