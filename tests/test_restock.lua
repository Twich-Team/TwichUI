-- Vendor restocking (modules/Restock.lua), the runtime: the rules, bag-only counting, the plan (unit and bundled
-- listings, limited stock, several listings of one item, bag room and special bags, unique items, money, the
-- spending limit, extended costs left out), asking and cancelling, buying automatically (only once confirmed),
-- every purchase checked again (a higher price, a changed listing, the merchant closing, combat, a rule edited),
-- one purchase at a time counted only once the bags show it (delayed, repeated, partial, refused, missing), one
-- plan per visit, waiting for TwichUI's own selling, and what the summary says.
-- The merchant, the bags and the "server" are mocks: whether the game sells, refuses or delivers is for the game.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
c.R_OUT = {}
c.print = function(s) table.insert(c.R_OUT, tostring(s)) end
c.COMBAT = false
c.InCombatLockdown = function() return c.COMBAT end
c.UnitClass = function() return "Mage", "MAGE" end
c.NUM_BAG_SLOTS = 4
c.CANCEL = "Cancel"

-- Popups: the last one shown, and which were hidden.
c.StaticPopupDialogs = {}
c.POPUPS, c.HIDDEN = {}, {}
c.StaticPopup_Show = function(name, text) table.insert(c.POPUPS, { name = name, text = text }); return {} end
c.StaticPopup_Hide = function(name) c.HIDDEN[name] = (c.HIDDEN[name] or 0) + 1 end
local function LastPopup() return c.POPUPS[#c.POPUPS] end
local function Accept() c.StaticPopupDialogs.TWICHUI_RESTOCK_CONFIRM.OnAccept() end
local function Decline() c.StaticPopupDialogs.TWICHUI_RESTOCK_CONFIRM.OnCancel(nil, nil, "clicked") end

-- Items the game knows: { name, maxStack, family, unique }.
c.ITEMS = {}
c.UNLOADED = {}
c.REQUESTED = {}
c.C_Item = {
  GetItemInfoInstant = function(id) if c.ITEMS[id] then return id, "", "", "", 1000 + id, 15, 0 end end,
  GetItemInfo = function(id)
    local i = c.ITEMS[id]
    if not i or c.UNLOADED[id] then return nil end
    return i.name, "[" .. i.name .. "]"
  end,
  GetItemMaxStackSizeByID = function(id) local i = c.ITEMS[id]; if i and not c.UNLOADED[id] then return i.maxStack end end,
  GetItemFamily = function(id) local i = c.ITEMS[id]; return i and i.family or 0 end,
  GetItemUniqueness = function(id) local i = c.ITEMS[id]; if i and i.unique then return 1, i.unique end end,
  RequestLoadItemDataByID = function(id) c.REQUESTED[id] = (c.REQUESTED[id] or 0) + 1 end,
  GetItemCount = function() return 999 end,   -- would count the bank and equipped items: never used
}
c.ITEMS[17020] = { name = "Arcane Powder", maxStack = 20 }
c.ITEMS[17031] = { name = "Rune of Teleportation", maxStack = 20 }
c.ITEMS[17056] = { name = "Light Feather", maxStack = 20 }
c.ITEMS[2512] = { name = "Rough Arrow", maxStack = 200, family = 1 }
c.ITEMS[9999] = { name = "Unique Charm", maxStack = 1, unique = 1 }
c.ITEMS[1205] = { name = "Melon Juice", maxStack = 20 }

-- Bags: [bag] = { size, family, slots = { [slot] = { id, count } } }.
c.BAGS = {}
local function Bags(spec)
  c.BAGS = {}
  for bag, b in pairs(spec) do
    c.BAGS[bag] = { size = b.size or 16, family = b.family or 0, slots = {} }
    for slot, s in pairs(b.slots or {}) do c.BAGS[bag].slots[slot] = { id = s[1], count = s[2] } end
  end
end
c.C_Container = {
  GetContainerNumSlots = function(bag) return c.BAGS[bag] and c.BAGS[bag].size or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local s = c.BAGS[bag] and c.BAGS[bag].slots[slot]
    if not s then return nil end
    return { itemID = s.id, stackCount = s.count, iconFileID = 1, itemName = c.ITEMS[s.id] and c.ITEMS[s.id].name }
  end,
  GetContainerNumFreeSlots = function(bag)
    local b = c.BAGS[bag]
    if not b then return 0, 0 end
    local free = 0
    for slot = 1, b.size do if not b.slots[slot] then free = free + 1 end end
    return free, b.family
  end,
}
local function Carried(id)
  local n = 0
  for _, b in pairs(c.BAGS) do for _, s in pairs(b.slots) do if s.id == id then n = n + s.count end end end
  return n
end

-- The merchant: listings { id, price, stack, avail, purchasable, extended, currency, costs, maxStack }.
c.MERCHANT = {}
c.MERCHANT_UP = false
c.MONEY = 100000
c.MISSING_LISTING = {}
c.MerchantFrame = { IsShown = function() return c.MERCHANT_UP end }
c.GetMoney = function() return c.MONEY end
c.GetMerchantNumItems = function() return #c.MERCHANT end
c.GetMerchantItemID = function(i) if c.MISSING_LISTING[i] then return nil end local e = c.MERCHANT[i]; return e and e.id end
c.GetMerchantItemLink = function(i) local e = c.MERCHANT[i]; return e and ("[" .. c.ITEMS[e.id].name .. "]") end
c.GetMerchantItemMaxStack = function(i) local e = c.MERCHANT[i]; return e and (e.maxStack or 200) end
c.GetMerchantItemCostInfo = function(i) local e = c.MERCHANT[i]; return e and (e.costs or 0) end
c.C_MerchantFrame = {
  GetItemInfo = function(i)
    local e = c.MERCHANT[i]
    if not e or c.MISSING_LISTING[i] then return nil end
    return { name = c.ITEMS[e.id].name, texture = 1, price = e.price, stackCount = e.stack or 1, numAvailable = e.avail or -1,
      isPurchasable = e.purchasable ~= false, isUsable = true, hasExtendedCost = e.extended or false, currencyID = e.currency }
  end,
}
local function Sell(list) c.MERCHANT = list end

-- The "server": every purchase is recorded; Deliver() puts what was bought in the bags, takes the money and says the
-- bags settled. c.SERVER = "deliver" (default: on Deliver()), or a number: deliver only that many.
c.BOUGHT = {}
c.PENDING = {}
c.BuyMerchantItem = function(index, n)
  local e = c.MERCHANT[index]
  table.insert(c.BOUGHT, { index = index, id = e.id, n = n })
  table.insert(c.PENDING, { id = e.id, n = n, cost = (n / (e.stack or 1)) * e.price, stack = c.ITEMS[e.id].maxStack })
end
local function Put(id, n, maxStack)
  for bag = 0, 4 do
    local b = c.BAGS[bag]
    if b then
      for slot = 1, b.size do
        local s = b.slots[slot]
        if n > 0 and s and s.id == id and s.count < maxStack then
          local add = math.min(n, maxStack - s.count)
          s.count, n = s.count + add, n - add
        end
      end
    end
  end
  for bag = 0, 4 do
    local b = c.BAGS[bag]
    if b then
      for slot = 1, b.size do
        if n > 0 and not b.slots[slot] then
          local add = math.min(n, maxStack)
          b.slots[slot] = { id = id, count = add }
          n = n - add
        end
      end
    end
  end
end
local function Deliver(only)
  local list = c.PENDING
  c.PENDING = {}
  for _, p in ipairs(list) do
    local n = only or p.n
    Put(p.id, n, p.stack)
    c.MONEY = c.MONEY - (n / p.n) * p.cost
  end
  c.FireEvent("BAG_UPDATE_DELAYED")
end

local files = { "modules/Restock.lua" }
for _, f in ipairs(files) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local R = c.TwichUI
local RS = R.Restock
local events = R.frame.events

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local function Said(pattern)
  for _, line in ipairs(c.R_OUT) do if line:find(pattern, 1, true) then return line end end
end
local function Reset() c.R_OUT, c.BOUGHT, c.PENDING, c.POPUPS, c.HIDDEN = {}, {}, {}, {}, {} end
local function Flush(n) for _ = 1, n or 6 do FlushTimers() end end
local function Open()
  c.MERCHANT_UP = true
  c.FireEvent("MERCHANT_SHOW")
  Flush()
end
local function Close()
  c.MERCHANT_UP = false
  c.FireEvent("MERCHANT_CLOSED")
  Flush()
end
local function Rules(list)
  c.TwichUIDB.ui.restock = c.TwichUIDB.ui.restock or {}
  c.TwichUIDB.ui.restock.items = list
  RS.Refresh()
end

---------------------------------------------------------------------------
-- 1. Off by default; strict; nothing listens
---------------------------------------------------------------------------
Check(R.DEFAULT_MODULES.restock == false, "restocking is opt-in")
Check(c.TwichUIDB.modules.restock == false, "a new install gets it off")
Check(not RS.Enabled() and RS.Mode() == "ask" and RS.SpendLimit() == nil and #RS.Rules() == 0, "off, asks first, no limit, an empty list")
Check(not events.MERCHANT_SHOW, "nothing listens while off")
c.TwichUIDB.modules.restock = 1; Check(not RS.Enabled(), "a number is not on")
c.TwichUIDB.modules.restock = "true"; Check(not RS.Enabled(), "text is not on")
c.TwichUIDB.modules.restock = false

---------------------------------------------------------------------------
-- 2. The list: adding, duplicates, targets, on/off, order, removing, damaged entries
---------------------------------------------------------------------------
do
  local ok, why = RS.Add("abc")
  Check(not ok and why:find("item ID"), "text that isn't an ID is refused")
  ok, why = RS.Add(123456)
  Check(not ok and why:find("No item has the ID 123456"), "an ID the game doesn't know is refused")
  ok, why = RS.Add(0)
  Check(not ok, "0 isn't an item")
  local idx, how
  ok, idx, how = RS.Add("17020")
  Check(ok and idx == 1 and how == "added", "typed digits add an item")
  local rule = RS.Rule(17020)
  Check(rule and rule.target == 20 and rule.enabled == true, "with the default target, on")
  ok, idx, how = RS.Add("|cffffffff|Hitem:17020::::::::60:::::|h[Arcane Powder]|h|r")
  Check(ok and idx == 1 and how == "exists" and #RS.Rules() == 1, "the same item again is the rule already there, not a second")
  Check(RS.ParseItem("|Hitem:2512:0|h") == 2512 and RS.ParseItem(" 17031 ") == 17031 and RS.ParseItem("1.5") == nil, "IDs from links and digits")
  for _, bad in ipairs({ 0, -1, 1.5, 10000, "40" }) do
    Check(not RS.SetTarget(17020, bad), "target " .. tostring(bad) .. " is refused")
  end
  Check(RS.Rule(17020).target == 20, "a refused target changes nothing")
  Check(RS.SetTarget(17020, 9999) and RS.Rule(17020).target == 9999, "the most a target can be")
  Check(RS.SetTarget(17020, 1) and RS.Rule(17020).target == 1, "the least")
  RS.SetTarget(17020, 40)
  Check(RS.SetRuleEnabled(17020, false) and RS.Rule(17020).enabled == false and RS.Rule(17020).target == 40, "off keeps its target")
  RS.SetRuleEnabled(17020, true)
  RS.Add(17031, 10); RS.Add(17056, 15)
  Check(RS.Move(17056, -1) and RS.Rules()[2].id == 17056 and RS.Rules()[3].id == 17031, "moved up")
  Check(not RS.Move(17020, -1), "the first can't go higher")
  Check(RS.Remove(17056) and RS.Rule(17056) == nil and #RS.Rules() == 2, "removed")
  -- damaged saved entries are left out, one at a time; the rest still work
  c.TwichUIDB.ui.restock.items = { { id = 17020, target = 40, enabled = true }, "junk", { id = 17031, target = 0, enabled = true },
    { id = 17020, target = 5, enabled = true }, { id = 2512, target = 200, enabled = "yes" } }
  local list = RS.Rules()
  Check(#list == 2 and list[1].id == 17020 and list[1].target == 40 and list[2].id == 2512 and list[2].enabled == false,
    "a damaged entry is skipped, a repeat ignored, a damaged on/off is off")
  -- the list holds at most MAX_ITEMS
  local many = {}
  for i = 1, RS.MAX_ITEMS do many[i] = { id = 50000 + i, target = 1, enabled = false }; c.ITEMS[50000 + i] = { name = "X" .. i, maxStack = 20 } end
  c.TwichUIDB.ui.restock.items = many
  ok, why = RS.Add(17020)
  Check(not ok and why:find("holds"), "a full list says so")
  c.TwichUIDB.ui.restock.items = {}
end

---------------------------------------------------------------------------
-- 3. Ask before purchasing: bag-only counts, the question, Cancel, Purchase, one purchase at a time
---------------------------------------------------------------------------
R:SetEnabled("restock", true)
Check(events.MERCHANT_SHOW and events.MERCHANT_CLOSED, "listening once it is on")
Rules({ { id = 17020, target = 20, enabled = true } })
Bags({ [0] = { size = 16, slots = { [1] = { 17020, 5 }, [2] = { 17020, 2 } } } })
Sell({ { id = 1205, price = 25 }, { id = 17020, price = 500 } })
Reset()
Open()
local q = LastPopup()
Check(q and q.name == "TWICHUI_RESTOCK_CONFIRM", "asks first")
Check(q and q.text:find("[Arcane Powder] ×13", 1, true) and q.text:find("Total: 65s", 1, true) and q.text:find("5s each", 1, true),
  "the question lists the item, how many (target 20 less 7 in the bags, not the 999 GetItemCount would say), each price and the total: " .. tostring(q and q.text))
Check(#c.BOUGHT == 0, "asking buys nothing")
Decline()
c.FireEvent("BAG_UPDATE_DELAYED"); c.FireEvent("MERCHANT_UPDATE"); Flush()
Check(#c.BOUGHT == 0 and #c.POPUPS == 1, "Cancel buys nothing, and nothing is asked again this visit")
Close()

Reset()
Open()
Accept()
Check(#c.BOUGHT == 1 and c.BOUGHT[1].index == 2 and c.BOUGHT[1].n == 13, "Purchase buys 13 from the listing that sells it")
c.FireEvent("BAG_UPDATE_DELAYED"); c.FireEvent("BAG_UPDATE_DELAYED"); c.FireEvent("MERCHANT_UPDATE"); Flush()
Check(#c.BOUGHT == 1, "bag events before the purchase shows up buy nothing more")
Deliver()
Flush()
Check(Carried(17020) == 20, "at the target")
Check(#c.BOUGHT == 1, "nothing more once the target is met")
Check(Said("Restocked [Arcane Powder] ×13 for 65s."), "the summary says what arrived and what it cost: " .. tostring(c.R_OUT[1]))
c.FireEvent("BAG_UPDATE_DELAYED"); Flush()
Check(#c.BOUGHT == 1 and #c.R_OUT == 1, "counts changing afterwards start nothing")
Close()

-- target already met: nothing asked, nothing said
Reset()
Open()
Check(#c.POPUPS == 0 and #c.BOUGHT == 0 and #c.R_OUT == 0, "a met target asks and says nothing")
Close()
-- a merchant that doesn't sell it: nothing
Sell({ { id = 1205, price = 25 } })
RS.SetTarget(17020, 40)
Reset(); Open()
Check(#c.POPUPS == 0 and #c.R_OUT == 0, "a merchant that doesn't sell it: nothing")
Close()

---------------------------------------------------------------------------
-- 4. Bundles, special bags, limited stock, several listings, bag room, unique, money
---------------------------------------------------------------------------
local function PlanFor(rules, merchant, bags, money)
  Rules(rules); Sell(merchant); Bags(bags); c.MONEY = money or 100000
  c.MERCHANT_UP = true
  c.FireEvent("MERCHANT_SHOW")   -- (a visit, so the plan is for it; nothing is flushed, so nothing is asked)
  local plan = RS.Plan()
  Close()
  return plan
end
do
  -- arrows: 200 for 10s; 150 carried, target 1000: four bundles (800), 50 short as a fifth would pass the target
  local plan = PlanFor({ { id = 2512, target = 1000, enabled = true } }, { { id = 2512, price = 1000, stack = 200, maxStack = 200 } },
    { [0] = { size = 4, slots = { [1] = { 1205, 1 }, [2] = { 1205, 1 }, [3] = { 1205, 1 }, [4] = { 1205, 1 } } },
      [1] = { size = 8, family = 1, slots = { [1] = { 2512, 150 } } } })
  local it = plan.items[1]
  Check(it and it.units == 800 and it.cost == 4000 and it.short == 50 and it.why == "bundle", "whole bundles only, within the target")
  -- the quiver holds arrows; an ordinary item doesn't go in it
  plan = PlanFor({ { id = 17020, target = 40, enabled = true } }, { { id = 17020, price = 500 } },
    { [0] = { size = 1, slots = { [1] = { 1205, 1 } } }, [1] = { size = 8, family = 1 } })
  Check(#plan.items == 0 and plan.notes[1] and plan.notes[1].why == "bags-full", "a quiver's room isn't room for powder")
  -- a bundle bigger than the whole need: nothing, and why
  plan = PlanFor({ { id = 2512, target = 100, enabled = true } }, { { id = 2512, price = 1000, stack = 200 } }, { [0] = { size = 16 } })
  Check(#plan.items == 0 and plan.notes[1].why == "bundle", "never past the target to round up a bundle")
  -- limited stock
  plan = PlanFor({ { id = 17020, target = 20, enabled = true } }, { { id = 17020, price = 500, avail = 5 } }, { [0] = { size = 16 } })
  Check(plan.items[1].units == 5 and plan.items[1].why == "stock", "no more than the merchant has")
  plan = PlanFor({ { id = 17020, target = 20, enabled = true } }, { { id = 17020, price = 500, avail = 0 } }, { [0] = { size = 16 } })
  Check(#plan.items == 0 and plan.notes[1].why == "sold-out", "sold out")
  -- two listings: the one that gets furthest to the target, then the cheaper per item
  local two = { { id = 17020, price = 100, stack = 5 }, { id = 17020, price = 25, stack = 1 } }
  plan = PlanFor({ { id = 17020, target = 13, enabled = true } }, two, { [0] = { size = 16 } })
  Check(plan.items[1].index == 2 and plan.items[1].units == 13, "13 needed: the single items reach it")
  plan = PlanFor({ { id = 17020, target = 10, enabled = true } }, two, { [0] = { size = 16 } })
  Check(plan.items[1].index == 1 and plan.items[1].units == 10 and plan.items[1].cost == 200, "10 needed: both reach it, the bundles are cheaper")
  -- bag room: a part stack's free part and no empty slot
  plan = PlanFor({ { id = 17020, target = 40, enabled = true } }, { { id = 17020, price = 10 } },
    { [0] = { size = 2, slots = { [1] = { 17020, 15 }, [2] = { 1205, 3 } } } })
  Check(plan.items[1].units == 5 and plan.items[1].why == "bags-full", "only the room there is")
  -- two items sharing the last empty slot: the first in the list gets it
  plan = PlanFor({ { id = 17020, target = 20, enabled = true }, { id = 17031, target = 20, enabled = true } },
    { { id = 17020, price = 10 }, { id = 17031, price = 10 } }, { [0] = { size = 1 } })
  Check(#plan.items == 1 and plan.items[1].id == 17020 and plan.notes[1].id == 17031 and plan.notes[1].why == "bags-full",
    "one empty slot is planned once, for the item higher in the list")
  -- unique
  plan = PlanFor({ { id = 9999, target = 5, enabled = true } }, { { id = 9999, price = 10 } }, { [0] = { size = 16 } })
  Check(plan.items[1].units == 1 and plan.items[1].why == "unique", "no more than the game lets you carry")
  -- money
  plan = PlanFor({ { id = 17020, target = 20, enabled = true } }, { { id = 17020, price = 100 } }, { [0] = { size = 16 } }, 350)
  Check(plan.items[1].units == 3 and plan.items[1].why == "money", "no more than you can pay for")
  plan = PlanFor({ { id = 17020, target = 20, enabled = true } }, { { id = 17020, price = 100 } }, { [0] = { size = 16 } }, 50)
  Check(#plan.items == 0 and plan.notes[1].why == "money", "nothing you can't pay for")
  -- other costs: tokens, items, another currency, no readable price
  for _, listing in ipairs({ { id = 17020, price = 100, extended = true }, { id = 17020, price = 0, extended = true },
      { id = 17020, price = 100, currency = 1792 }, { id = 17020, price = 100, costs = 1 } }) do
    plan = PlanFor({ { id = 17020, target = 20, enabled = true } }, { listing }, { [0] = { size = 16 } })
    Check(#plan.items == 0 and plan.notes[1].why == "extended-cost", "anything costing more than gold is left alone")
  end
  plan = PlanFor({ { id = 17020, target = 20, enabled = true } }, { { id = 17020, price = 0 } }, { [0] = { size = 16 } })
  Check(#plan.items == 0 and plan.notes[1].why == "no-price", "no readable price")
  plan = PlanFor({ { id = 17020, target = 20, enabled = true } }, { { id = 17020, price = 100, purchasable = false } }, { [0] = { size = 16 } })
  Check(#plan.items == 0 and plan.notes[1].why == "not-purchasable", "not for you")
  -- an item off on the list isn't planned
  plan = PlanFor({ { id = 17020, target = 20, enabled = false } }, { { id = 17020, price = 100 } }, { [0] = { size = 16 } })
  Check(#plan.items == 0 and #plan.notes == 0, "a rule that is off is kept and not bought")
end

---------------------------------------------------------------------------
-- 5. The spending limit: across the visit, in the list's order; 0 is a limit; off is none
---------------------------------------------------------------------------
do
  local rules = { { id = 17020, target = 20, enabled = true }, { id = 17031, target = 20, enabled = true } }
  local merchant = { { id = 17020, price = 10 }, { id = 17031, price = 10 } }
  RS.Set("useLimit", true)
  RS.Set("limit", 250)
  local plan = PlanFor(rules, merchant, { [0] = { size = 16 } })
  Check(plan.total == 250 and plan.items[1].units == 20 and plan.items[2].units == 5 and plan.items[2].why == "spend-limit",
    "the first in the list is bought first; the limit covers the visit")
  RS.Set("limit", 0)
  plan = PlanFor(rules, merchant, { [0] = { size = 16 } })
  Check(#plan.items == 0 and plan.notes[1].why == "spend-limit", "a limit of 0 buys nothing")
  RS.Set("useLimit", false)
  plan = PlanFor(rules, merchant, { [0] = { size = 16 } })
  Check(plan.total == 400 and RS.SpendLimit() == nil, "no limit is not a limit of 0")
  Check(not RS.Set("limit", -1) and not RS.Set("limit", 1.5) and not RS.Set("limit", 100000000), "a limit is whole copper, within range")
  RS.Set("limit", 10000)
end

---------------------------------------------------------------------------
-- 6. Several items bought one after another; a grouped summary
---------------------------------------------------------------------------
Rules({ { id = 17020, target = 20, enabled = true }, { id = 17031, target = 10, enabled = true }, { id = 2512, target = 400, enabled = true } })
Sell({ { id = 17020, price = 500 }, { id = 17031, price = 1000 }, { id = 2512, price = 1000, stack = 200, maxStack = 200 } })
Bags({ [0] = { size = 16 } })
c.MONEY = 100000
Reset(); Open(); Accept()
Check(#c.BOUGHT == 1 and c.BOUGHT[1].id == 17020, "the first purchase only, until it shows up")
Deliver()
Check(#c.BOUGHT == 2 and c.BOUGHT[2].id == 17031 and c.BOUGHT[2].n == 10, "then the next")
Deliver()
Check(#c.BOUGHT == 3 and c.BOUGHT[3].id == 2512 and c.BOUGHT[3].n == 200, "arrows in calls of at most the listing's limit")
Deliver()
Check(#c.BOUGHT == 4 and c.BOUGHT[4].n == 200, "the second bundle")
Deliver()
Flush()
Check(#c.BOUGHT == 4, "done")
local summary = Said("Restocked 3 items")
Check(summary and summary:find("[Arcane Powder] ×20", 1, true) and summary:find("[Rough Arrow] ×400", 1, true) and summary:find("for 2g 20s", 1, true),
  "one grouped line: " .. tostring(summary))
Check(#c.R_OUT == 1, "and only one")
Close()

---------------------------------------------------------------------------
-- 7. Buying automatically: only once confirmed on this account
---------------------------------------------------------------------------
do
  local ok, why = RS.Set("mode", "auto")
  Check(not ok and why == "needs-ack" and RS.Mode() == "ask", "automatic needs your confirmation first")
  c.TwichUIDB.ui.restock.mode = "auto"   -- as a profile or a shared setup would leave it
  Check(RS.AutoWaiting() and RS.Mode() == "ask", "chosen elsewhere and not confirmed: it asks")
  Rules({ { id = 17020, target = 25, enabled = true } })
  Sell({ { id = 17020, price = 500 } })
  Reset(); Open()
  Check(#c.POPUPS == 1 and #c.BOUGHT == 0, "still asks")
  Close()
  RS.Acknowledge()
  Check(RS.Mode() == "auto" and not RS.AutoWaiting(), "confirmed")
  Reset(); Open()
  Check(#c.POPUPS == 0 and #c.BOUGHT == 1 and c.BOUGHT[1].n == 5, "buys without asking")
  Deliver(); Flush()
  Check(Said("Restocked [Arcane Powder] ×5 for 25s."), "and says so")
  Close()
  -- the limits still hold
  RS.SetTarget(17020, 45)
  RS.Set("useLimit", true); RS.Set("limit", 1500)
  Reset(); Open()
  Check(#c.BOUGHT == 1 and c.BOUGHT[1].n == 3, "within the spending limit")
  Deliver(); Flush()
  Check(Said("Short: [Arcane Powder] 17 (your spending limit for a visit)"), "and says what is short and why: " .. tostring(c.R_OUT[1]))
  Close()
  RS.Set("useLimit", false)
  RS.Set("mode", "ask")
end

---------------------------------------------------------------------------
-- 8. Approved, then changed: a higher price asks again; a lower one is fine; a rule edit or closing drops it
---------------------------------------------------------------------------
Rules({ { id = 17020, target = 20, enabled = true } })
Sell({ { id = 17020, price = 500 } })
Bags({ [0] = { size = 16 } })
Reset(); Open()
c.MERCHANT[1].price = 600
Accept()
Check(#c.BOUGHT == 0, "a dearer price than approved buys nothing")
Flush()
local again = LastPopup()
Check(#c.POPUPS == 2 and again.text:find("price of something went up", 1, true) and again.text:find("6s each", 1, true),
  "and the question is asked again with the new price")
Accept()
Check(#c.BOUGHT == 1 and c.BOUGHT[1].n == 20, "approved again: bought")
Deliver(); Flush()
Close()

Rules({ { id = 17020, target = 40, enabled = true } })
Reset(); Open()
c.MERCHANT[1].price = 300
Accept()
Check(#c.BOUGHT == 1 and c.BOUGHT[1].n == 20, "a lower price is fine")
Deliver(); Flush()
Check(Said("for 60s"), "and the summary has what it really cost")
Close()

-- a rule edited while the question is open: it goes, and Purchase does nothing
Rules({ { id = 17020, target = 60, enabled = true } })
Reset(); Open()
RS.SetTarget(17020, 70)
Check((c.HIDDEN.TWICHUI_RESTOCK_CONFIRM or 0) >= 1, "the question is put away")
Accept()
Check(#c.BOUGHT == 0 and Said("nothing was bought"), "a stale approval buys nothing and says so")
Close()

-- the merchant closing while the question is open
Reset(); Open()
c.MERCHANT_UP = false
c.FireEvent("MERCHANT_CLOSED")
Accept()
Check(#c.BOUGHT == 0, "closed: nothing")
Flush()

-- a different listing at that place now
Reset(); Open()
c.MERCHANT[1] = { id = 17031, price = 10 }
Accept()
Check(#c.BOUGHT == 0, "a listing that changed is not bought")
Flush()
Check(Said("listing changed"), "and that is why")
Close()
Sell({ { id = 17020, price = 500 } })

---------------------------------------------------------------------------
-- 9. Purchases that don't show up, show up in part, or are refused: never tried again
---------------------------------------------------------------------------
Rules({ { id = 17020, target = 20, enabled = true }, { id = 17031, target = 5, enabled = true } })
Sell({ { id = 17020, price = 500 }, { id = 17031, price = 1000 } })
Bags({ [0] = { size = 16 } })
c.MONEY = 100000
-- nothing arrives
Reset(); Open(); Accept()
RunLongTimers(3)
Flush()
Check(#c.BOUGHT == 1, "a purchase that never shows up stops the run")
Check(Said("[Arcane Powder] ×20 was asked for but it didn't show up in your bags. Nothing more was tried."), "and is not reported as bought: " .. tostring(c.R_OUT[1]))
Check(not Said("Restocked"), "nothing is claimed")
c.PENDING = {}
Close()
-- part of it arrives
Reset(); Open(); Accept()
Deliver(8)
RunLongTimers(3); Flush()
Check(#c.BOUGHT == 1, "a part delivery stops the run")
Check(Said("Restocked [Arcane Powder] ×8 for 40s.") and Said("only 8 showed up in your bags. Nothing more was tried."), "only what arrived counts: " .. tostring(c.R_OUT[1]))
Close()
-- the game refuses
Bags({ [0] = { size = 16 } })
Reset(); Open(); Accept()
c.FireEvent("UI_ERROR_MESSAGE", 3, "Inventory is full.")
Check(#c.BOUGHT == 1, "waits for the bags to say")
c.PENDING = {}
RunLongTimers(3); Flush()
Check(Said("it didn't show up in your bags: the game said \"Inventory is full\". Nothing more was tried."), "says why it stopped: " .. tostring(c.R_OUT[1]))
Close()
-- an error about something else, and the purchase still arrives: carries on
Reset(); Open(); Accept()
c.FireEvent("UI_ERROR_MESSAGE", 50, "Out of range.")
Deliver()
Check(#c.BOUGHT == 2, "an unrelated error doesn't stop a purchase that arrived")
Deliver(); Flush()
Close()

---------------------------------------------------------------------------
-- 10. Stopping: the merchant closing, combat, the feature off, a profile change
---------------------------------------------------------------------------
Rules({ { id = 17020, target = 20, enabled = true }, { id = 17031, target = 5, enabled = true } })
Bags({ [0] = { size = 16 } })
Reset(); Open(); Accept()
c.MERCHANT_UP = false
c.FireEvent("MERCHANT_CLOSED")
Deliver(); Flush()
Check(#c.BOUGHT == 1, "closing stops the run, and a late delivery doesn't restart it")
Check(Said("Restocking stopped: the merchant closed."), "says so")
Bags({ [0] = { size = 16 } })
Reset(); Open(); Accept()
c.FireEvent("PLAYER_REGEN_DISABLED")
Deliver(); Flush()
Check(#c.BOUGHT == 1 and Said("Restocking stopped: combat started."), "combat stops it")
Close()
Bags({ [0] = { size = 16 } })
Reset(); Open(); Accept()
R:SetEnabled("restock", false)
Deliver(); Flush()
Check(#c.BOUGHT == 1 and #c.R_OUT == 0, "turned off: it stops without a word")
Check(not events.MERCHANT_SHOW, "and stops listening")
R:SetEnabled("restock", true)
Close()
Bags({ [0] = { size = 16 } })
Reset(); Open(); Accept()
RS.Refresh()   -- what a profile change does (Profiles.OnApply "views")
Deliver(); Flush()
Check(#c.BOUGHT == 1, "a profile change drops the run")
Close()
-- combat when the merchant opens: nothing at all
Bags({ [0] = { size = 16 } })
c.COMBAT = true
Reset(); Open()
Check(#c.POPUPS == 0 and #c.BOUGHT == 0, "nothing in combat")
c.COMBAT = false
Close()

---------------------------------------------------------------------------
-- 11. Waiting: for TwichUI's own selling, and for details still loading
---------------------------------------------------------------------------
do
  local selling = true
  R.MageSell = { Running = function() return selling end }
  Rules({ { id = 17020, target = 20, enabled = true } })
  Sell({ { id = 17020, price = 500 } })
  Bags({ [0] = { size = 16 } })
  Reset(); Open()
  Check(#c.POPUPS == 0, "waits while selling runs")
  selling = false
  Flush()
  Check(#c.POPUPS == 1, "then plans")
  Decline()
  Close()
  R.MageSell = nil

  -- an item whose details haven't loaded: asked for, looked at again when they arrive
  c.UNLOADED[17020] = true
  Reset(); Open()
  Check(#c.POPUPS == 0 and (c.REQUESTED[17020] or 0) >= 1, "asks the game for the item's details and waits")
  c.UNLOADED[17020] = nil
  c.FireEvent("GET_ITEM_INFO_RECEIVED", 17020, true)
  Flush()
  Check(#c.POPUPS == 1, "then plans")
  Decline()
  Close()
  -- details that never come: a few looks, then left out with a reason (no endless retrying)
  c.UNLOADED[17020] = true
  Reset(); Open(); Flush(20)
  Check(#c.POPUPS == 0 and #c.BOUGHT == 0 and Said("its item details hadn't loaded"), "left out after a few looks, and why")
  local requests = c.REQUESTED[17020]
  Flush(20)
  Check(c.REQUESTED[17020] == requests, "and nothing keeps asking")
  c.UNLOADED[17020] = nil
  Close()
  -- a listing not read yet
  c.MISSING_LISTING[1] = true
  Reset(); Open()
  Check(#c.POPUPS == 0, "waits for the merchant's listing")
  c.MISSING_LISTING[1] = nil
  c.FireEvent("MERCHANT_UPDATE")
  Flush()
  Check(#c.POPUPS == 1, "then plans")
  Decline()
  Close()
end

---------------------------------------------------------------------------
-- 12. What can't be bought at all is said once a session, not at every visit
---------------------------------------------------------------------------
Rules({ { id = 17020, target = 20, enabled = true } })
Sell({ { id = 17020, price = 100, extended = true } })
Bags({ [0] = { size = 16 } })
Reset(); Open()
Check(#c.POPUPS == 0 and Said("Couldn't restock [Arcane Powder] (costs tokens"), "said once: " .. tostring(c.R_OUT[1]))
Close()
Reset(); Open()
Check(#c.R_OUT == 0, "not again at the next visit")
Close()

---------------------------------------------------------------------------
-- 13. Coexistence: an enabled rule protects its item from TwichUI's own selling
---------------------------------------------------------------------------
Rules({ { id = 1205, target = 20, enabled = true }, { id = 17020, target = 5, enabled = false } })
Check(RS.Protects(1205) and not RS.Protects(17020) and not RS.Protects(2512), "only enabled rules are protected")
R:SetEnabled("restock", false)
Check(not RS.Protects(1205), "and only while restocking is on")
R:SetEnabled("restock", true)

---------------------------------------------------------------------------
-- 14. Nothing of a visit is saved
---------------------------------------------------------------------------
do
  local saved = c.TwichUIDB.ui.restock
  local keys = {}
  for k in pairs(saved) do keys[#keys + 1] = k end
  table.sort(keys)
  Check(table.concat(keys, ",") == "items,limit,mode,useLimit", "only the rules and preferences are saved: " .. table.concat(keys, ","))
  for _, rule in ipairs(saved.items) do
    for k in pairs(rule) do Check(k == "id" or k == "target" or k == "enabled", "a saved rule holds only its id, target and on/off") end
  end
end

if failures > 0 then
  print(failures .. " check(s) failed")
  error("test_restock failed")
end
print("RESTOCK PASSED")
