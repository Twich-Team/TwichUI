-- Mage: sell ordinary food and drink. Classification (ordinary food and drink, combined items, conjured
-- items by ID and by tooltip, buff food, potions, quest items, locked, bound, unpriced, special quality,
-- the never-sell list, unloaded and unreadable items), the preview matching what is sold, dry run, the
-- per-visit limit, one sale at a time and counted only once the bag shows it, stale slots, the merchant
-- closing, combat, the feature switched off mid-run, a blocked or unconfirmed sale, and nothing listening
-- when off or on another class.
-- Mocks show TwichUI's own bookkeeping. Whether the game sells, blocks or buys back anything is for the game.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local frames, byName = {}, {}
local function Fake(name)
  local o = { shown = false, scripts = {}, hooks = {}, events = {}, attrs = {}, enabled = true }
  if name then byName[name] = o end
  table.insert(frames, o)
  return setmetatable(o, { __index = function(_, k)
    if k == "Show" then return function(s) s.shown = true; if s.scripts.OnShow then s.scripts.OnShow(s) end end end
    if k == "Hide" then return function(s) s.shown = false; if s.scripts.OnHide then s.scripts.OnHide(s) end end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetEnabled" then return function(s, v) s.enabled = v and true or false end end
    if k == "IsEnabled" then return function(s) return s.enabled end end
    if k == "SetSize" then return function(s, w, h) if w then s.w, s.h = w, h end end end
    if k == "SetWidth" then return function(s, w) s.w = w end end
    if k == "SetHeight" then return function(s, h) s.h = h end end
    if k == "GetWidth" then return function(s) return s.w or 0 end end
    if k == "GetHeight" then return function(s) return s.h or 0 end end
    if k == "GetStringHeight" then return function() return 14 end end
    if k == "GetStringWidth" then return function() return 60 end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    return function() end
  end })
end
c.CreateFrame = function(_, name) return Fake(name) end
c.UIParent = Fake()
c.UISpecialFrames = {}
c.GameTooltip = Fake()
c.ClearCursor = function() c.CURSOR_CLEARED = (c.CURSOR_CLEARED or 0) + 1 end
c.R_OUT = {}
c.print = function(s) table.insert(c.R_OUT, tostring(s)) end

c.CLASS, c.LEVEL, c.COMBAT = "MAGE", 30, false
c.UnitClass = function() return c.CLASS:sub(1, 1) .. c.CLASS:sub(2):lower(), c.CLASS end
c.UnitLevel = function() return c.LEVEL end
c.InCombatLockdown = function() return c.COMBAT end
c.HEALTH, c.MANA = "Health", "Mana"
c.ITEM_CONJURED, c.ITEM_BIND_QUEST, c.ITEM_STARTS_QUEST = "Conjured Item", "Quest Item", "This Item Begins a Quest"
c.BUYBACK_ITEMS_PER_PAGE = 12
c.NUM_BAG_SLOTS = 4
c.MERCHANT_UP = false
c.MerchantFrame = { IsShown = function() return c.MERCHANT_UP end }

c.BAGS = {}        -- [bag] = { [slot] = { id, count, locked, bound, noValue, quest } }
c.ITEMS = {}       -- [id] = { class, sub, name, quality, price, spell, spellName, text, tip }
c.UNCACHED, c.REQUESTED, c.NOTIP = {}, {}, {}
c.USED = {}        -- every UseContainerItem call, in order
c.PENDING = nil    -- the sale the "server" has accepted and will show on the next settle
c.C_Container = {
  GetContainerNumSlots = function(bag) return c.BAGS[bag] and 40 or 0 end,
  GetContainerItemInfo = function(bag, slot)
    local s = c.BAGS[bag] and c.BAGS[bag][slot]
    if not s then return nil end
    return { itemID = s.id, stackCount = s.count, isLocked = s.locked or false, isBound = s.bound or false,
      hasNoValue = s.noValue or false, iconFileID = 100 + s.id, itemName = c.ITEMS[s.id] and c.ITEMS[s.id].name }
  end,
  GetContainerItemQuestInfo = function(bag, slot)
    local s = c.BAGS[bag] and c.BAGS[bag][slot]
    return { isQuestItem = s and s.quest or false, questID = s and s.questID, isActive = false }
  end,
  UseContainerItem = function(bag, slot)
    table.insert(c.USED, { bag, slot, c.BAGS[bag][slot].id })
    c.PENDING = { bag, slot }
  end,
}
c.C_Item = {
  GetItemInfoInstant = function(id) local i = c.ITEMS[id]; if not i then return end return id, "", "", "", 100 + id, i.class, i.sub end,
  GetItemInfo = function(id)
    local i = c.ITEMS[id]
    if not i or c.UNCACHED[id] then return end
    return i.name, "link", i.quality, 1, 1, "", "", 20, "", 100 + id, i.price
  end,
  GetItemSpell = function(id) local i = c.ITEMS[id]; if i and i.spell then return i.spellName, i.spell end end,
  RequestLoadItemDataByID = function(id) c.REQUESTED[id] = true end,
}
c.C_Spell = {
  GetSpellName = function(id) return ({ [434] = "Food", [431] = "Drink" })[id] end,
  GetSpellDescription = function(id)
    for _, i in pairs(c.ITEMS) do if i.spell == id then return i.text end end
  end,
  RequestLoadSpellData = function() end,
}
c.C_TooltipInfo = {
  GetBagItem = function(bag, slot)
    local s = c.BAGS[bag] and c.BAGS[bag][slot]
    local i = s and c.ITEMS[s.id]
    if not i or c.NOTIP[s.id] then return nil end
    local lines = { { leftText = i.name }, { leftText = "Use: restores" } }
    for _, extra in ipairs(i.tip or {}) do table.insert(lines, { leftText = extra }) end
    return { lines = lines }
  end,
}

local FOOD, DRINK = "Restores %d health over 21 sec.  Must remain seated while eating.", "Restores %d mana over 21 sec.  Must remain seated while drinking."
local function Item(id, name, o)
  local i = { class = 0, sub = 5, name = name, quality = 1, price = 25, spell = 10000 + id, spellName = "Food", text = FOOD:format(243) }
  for k, v in pairs(o or {}) do i[k] = v end
  c.ITEMS[id] = i
end
local function Drink(id, name, o)
  Item(id, name, { spellName = "Drink", text = DRINK:format(420) })
  for k, v in pairs(o or {}) do c.ITEMS[id][k] = v end
end
local function Bags(list)   -- { { id, count, flags }, ... } into bag 0, slots 1..
  c.BAGS = { [0] = {} }
  for i, e in ipairs(list) do
    local s = { id = e[1], count = e[2] or 5 }
    for k, v in pairs(e[3] or {}) do s[k] = v end
    c.BAGS[0][i] = s
  end
end
-- The "server" shows the accepted sale: the slot empties and the game says the bags settled.
local function Settle()
  local p = c.PENDING
  c.PENDING = nil
  if p then c.BAGS[p[1]][p[2]] = nil end
  c.FireEvent("BAG_UPDATE_DELAYED")
end
local function Flush() FlushTimers() end

for _, f in ipairs({ "chronicle/Style.lua", "modules/Interact.lua", "modules/Borders.lua", "modules/FoodDrink.lua",
  "modules/EllesmereJunk.lua", "modules/MageSell.lua", "modules/MageSellWindow.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local R = c.TwichUI
local MS, W = R.MageSell, R.MageSellWindow
local M = c.TwichUIDB.modules
local events = R.frame.events

local function Says(pattern)
  for _, line in ipairs(c.R_OUT) do if line:find(pattern, 1, true) then return true end end
  return false
end
local function Reset() c.R_OUT, c.USED, c.PENDING = {}, {}, nil end
local function Visit()   -- the merchant opens and the moment passes
  c.MERCHANT_UP = true
  c.FireEvent("MERCHANT_SHOW")
  Flush()
end
local function Leave()
  c.MERCHANT_UP = false
  c.FireEvent("MERCHANT_CLOSED")
end

---------------------------------------------------------------------------
-- Defaults and strictness.
---------------------------------------------------------------------------
do
  local D = R.DEFAULT_MODULES
  assert(D.mageSell == false, "opt-in")
  assert(D.mageSellFood == true and D.mageSellDrink == true, "kinds on once it is on")
  assert(D.mageSellDryRun == true, "dry run first")
  assert(M.mageSell == false and M.mageSellDryRun == true, "a new install gets them")
  assert(MS.Enabled() == false)
  -- only an explicit true switches it on; a damaged value never does
  M.mageSell = 1; assert(MS.Enabled() == false, "a number is not on")
  M.mageSell = "true"; assert(MS.Enabled() == false, "text is not on")
  M.mageSell = nil; assert(MS.Enabled() == false, "missing is not on")
  M.mageSell = true; assert(MS.Enabled() == true)
  M.mageSellDryRun = nil; assert(MS.DryRun() == true, "missing keeps dry run on")
  M.mageSellDryRun = "no"; assert(MS.DryRun() == true, "damaged keeps dry run on")
  M.mageSellDryRun = false; assert(MS.DryRun() == false, "only an explicit false turns it off")
  M.mageSellDryRun = true
  M.mageSell = false
  assert(MS.Limit() == 10, "twelve buyback slots less two: " .. MS.Limit())
  c.BUYBACK_ITEMS_PER_PAGE = 30; assert(MS.Limit() == 10, "never more than the 12 the UI shows")
  c.BUYBACK_ITEMS_PER_PAGE = 4; assert(MS.Limit() == 2)
  c.BUYBACK_ITEMS_PER_PAGE = nil; assert(MS.Limit() == 10, "the UI's own number, else 12")
  c.BUYBACK_ITEMS_PER_PAGE = 12
end

---------------------------------------------------------------------------
-- Off: nothing listens, nothing happens.
---------------------------------------------------------------------------
Item(4540, "Tough Hunk of Bread")
Bags({ { 4540, 5 } })
Reset()
Visit()
assert(not events.MERCHANT_SHOW and not events.MERCHANT_CLOSED, "nothing registered while off")
assert(#c.USED == 0 and #c.R_OUT == 0, "nothing sold or said while off")
Leave()

---------------------------------------------------------------------------
-- The classifier, on one bag of everything.
---------------------------------------------------------------------------
Item(4540, "Tough Hunk of Bread", { text = FOOD:format(243), price = 25 })          -- sold
Item(4541, "Hearty Bread", { text = FOOD:format(552), price = 60 })                -- sold, second stack
Drink(1179, "Ice Cold Milk", { price = 40 })                                         -- sold
Item(3448, "Senggin Root", { spell = 2639, text = "Restores 282 health and 282 mana over 21 sec. Must remain seated while eating.", price = 10 })   -- needs both kinds
Item(5349, "Conjured Muffin", { price = 0 })                                         -- conjured by ID
Item(8079, "Conjured Crystal Water", { spellName = "Drink", text = DRINK:format(2400), price = 1 })   -- rank 7, ID only in the extra list
Item(9001, "Conjured Mystery Roll", { price = 5, tip = { "Conjured Item" } })        -- an unfamiliar rank: its tooltip says so
Item(9002, "Bound Bread", { price = 5 })
Item(9003, "Priceless Bread", { price = 0 })
Item(9004, "Feast of Plenty", { text = FOOD:format(243) .. " Well Fed: gain 8 Stamina for 15 min." })
Item(9005, "Quest Cheese", { price = 5 })
Item(9006, "Locked Bread", { price = 5 })
Item(9007, "Green Bread", { price = 5, quality = 2 })
Item(9008, "Gold-Plated Bread", { price = 20000 })
Item(9009, "My Favourite Bread", { price = 5 })
Item(9010, "Unloaded Bread", { price = 5 })
Item(9011, "Mystery Bread", { price = 5 })                                           -- tooltip can't be read
Item(9012, "Slot Flagged Quest Bread", { price = 5 })
Item(9013, "Tooltip Quest Bread", { price = 5, tip = { "Quest Item" } })
Item(118, "Lesser Healing Potion", { sub = 1, spell = 9118, spellName = "Lesser Healing Potion", text = "Restores 150 to 170 health instantly." })
Item(2589, "Linen Cloth", { class = 7, sub = 5, spell = nil })
Bags({
  { 4540, 5 }, { 4541, 3 }, { 1179, 10 }, { 3448, 4 }, { 5349, 20 }, { 8079, 20 }, { 9001, 6 }, { 9002, 5, { bound = true } },
  { 9003, 5 }, { 9004, 5 }, { 9005, 5, { quest = true } }, { 9006, 5, { locked = true } }, { 9007, 5 }, { 9008, 5 },
  { 9009, 5 }, { 9010, 5 }, { 9011, 5 }, { 9012, 5, { questID = 77 } }, { 9013, 5 }, { 118, 3 }, { 2589, 40 },
})
c.UNCACHED[9010] = true
c.NOTIP[9011] = true
M.mageSell, M.mageSellFood, M.mageSellDrink = true, true, false   -- drink off: the milk and the combined root are kept
MS.Refresh()
MS.OnChange = nil
MS.ClearCache()
M.mageSell = true; MS.OnChange = nil

local function Ids(list) local out = {} for _, v in ipairs(list) do out[#out + 1] = v.id end return out end
local function Set(list) local out = {} for _, v in ipairs(list) do out[v.id] = v end return out end
local function Reason(scan, id) for _, v in ipairs(scan.kept) do if v.id == id then return v.why end end end

MS.Exclude(9009)
local before = #c.USED
local scan = MS.Scan(false)
local sell = Set(scan.eligible)
assert(table.concat(Ids(scan.eligible), ",") == "4540,4541", "only the plain food: " .. table.concat(Ids(scan.eligible), ","))
assert(sell[4540].reason == "ordinary-food" and sell[4540].value == 125 and sell[4541].value == 180, "values from sell prices")
assert(scan.stacks == 2 and scan.items == 8 and scan.value == 305)
assert(Reason(scan, 1179) == "category-off", "drink is off")
assert(Reason(scan, 3448) == "category-off", "a combined item needs both kinds on")
assert(Reason(scan, 5349) == "conjured", "conjured by ID")
assert(Reason(scan, 8079) == "conjured", "rank 7 is protected from the extra list")
assert(Reason(scan, 9001) == "conjured", "an unfamiliar conjured item is caught by its tooltip")
assert(Reason(scan, 9002) == "bound" and Reason(scan, 9003) == "no-sell-price", tostring(Reason(scan, 9002)) .. " " .. tostring(Reason(scan, 9003)))
assert(Reason(scan, 9004) == "not-plain-food-or-drink", "buff food: " .. tostring(Reason(scan, 9004)))
assert(Reason(scan, 9005) == "quest-item" and Reason(scan, 9012) == "quest-item" and Reason(scan, 9013) == "quest-item", tostring(Reason(scan, 9005)) .. " " .. tostring(Reason(scan, 9012)) .. " " .. tostring(Reason(scan, 9013)))
assert(Reason(scan, 9006) == "locked" and Reason(scan, 9007) == "special-quality" and Reason(scan, 9008) == "high-value")
assert(Reason(scan, 9009) == "excluded", "the player's list")
assert(Reason(scan, 9010) == "item-data-pending" and c.REQUESTED[9010], "unloaded: kept, and asked for")
assert(Reason(scan, 9011) == "conjured-check-unavailable", "can't show it isn't conjured: kept")
assert(Reason(scan, 118) == nil and Reason(scan, 2589) == nil, "potions and cloth are not this feature's business")
assert(scan.pending == 1, "one item still loading")
assert(#c.USED == before, "a look sells nothing")
assert(c.BAGS[0][1].count == 5 and c.CURSOR_CLEARED == nil, "nothing moved or held")

-- both kinds on: the drink and the combined item are eligible
M.mageSellDrink = true
scan = MS.Scan(false)
assert(table.concat(Ids(scan.eligible), ",") == "4540,4541,1179,3448", table.concat(Ids(scan.eligible), ","))
assert(Set(scan.eligible)[3448].reason == "ordinary-food-and-drink")
M.mageSellFood = false
scan = MS.Scan(false)
assert(table.concat(Ids(scan.eligible), ",") == "1179", "only drink: " .. table.concat(Ids(scan.eligible), ","))
assert(Reason(scan, 3448) == "category-off", "food is off, so the combined item stays")
M.mageSellFood = true

-- missing item data is never "safe to sell": no spell names, no words, no marker text, no tooltip API
do
  local names = c.C_Spell.GetSpellName
  c.C_Spell.GetSpellName = function() return nil end
  MS.ClearCache()
  scan = MS.Scan(true)
  assert(scan.stacks == 0, "no spell names, nothing eligible")
  c.C_Spell.GetSpellName = names
  MS.ClearCache()
  c.ITEM_CONJURED = nil
  scan = MS.Scan(true)
  assert(scan.stacks == 0, "this client has no \"Conjured Item\" text: nothing can be shown not to be conjured")
  c.ITEM_CONJURED = "Conjured Item"
  local api = c.C_TooltipInfo
  c.C_TooltipInfo = nil
  MS.ClearCache()
  assert(MS.Scan(true).stacks == 0, "no tooltip API, nothing eligible")
  c.C_TooltipInfo = api
  MS.ClearCache()
  scan = MS.Scan(true)
  assert(#scan.eligible >= 2, "back to normal")
end

-- the preview and the run use one classifier: the window's rows are built from the same scan
do
  local rows = W.Rows(MS.Scan(true))
  local items = {}
  for _, r in ipairs(rows) do if r.kind == "item" then items[#items + 1] = r.id end end
  assert(table.concat(items, ",") == table.concat(Ids(MS.Scan(true).eligible), ","), "the window lists what would be sold")
  local seen = {}
  for _, r in ipairs(rows) do seen[r.kind] = true end
  assert(seen.header and seen.item and seen.kept and seen.excluded, "sold, kept and never-sell sections")
end

---------------------------------------------------------------------------
-- The never-sell list.
---------------------------------------------------------------------------
do
  M.mageSell = true
  assert(MS.Exclude(9009) and #MS.Excluded() == 1)
  assert(MS.Exclude("|cffffffff|Hitem:4540::::::::30:::::|h[Tough Hunk of Bread]|h|r") and MS.IsExcluded(4540), "an item link")
  assert(MS.Exclude(" 2287 ") and MS.IsExcluded(2287), "an item ID")
  local ok, why = MS.Exclude("not an item")
  assert(ok == false and why:find("isn't an item"), "refused with a sentence")
  assert(MS.Exclude(0) == false and MS.Exclude(-5) == false and MS.Exclude(1.5) == false and MS.Exclude(2 ^ 40) == false, "bad numbers refused")
  assert(table.concat(MS.Excluded(), ",") == "2287,4540,9009", "sorted, IDs only")
  assert(c.TwichUIDB.ui.mageSell.exclude[4540] == true, "saved as { [itemID] = true }")
  assert(MS.Include(4540) and not MS.IsExcluded(4540) and MS.Include(4540) == false)
  assert(MS.Include(2287))
  -- a damaged table is not an error and not a reason to sell
  c.TwichUIDB.ui.mageSell.exclude = "broken"
  assert(#MS.Excluded() == 0 and MS.IsExcluded(9009) == false)
  assert(MS.Exclude(9009) and MS.IsExcluded(9009), "rebuilt on the next add")
  c.TwichUIDB.ui.mageSell = 5
  assert(#MS.Excluded() == 0 and MS.Exclude(9009) and MS.IsExcluded(9009), "a damaged group is rebuilt, never read as a list")
  c.TwichUIDB.ui.mageSell.exclude[5] = false
  assert(not MS.IsExcluded(5), "only true counts")
  for i = 1, 300 do MS.Exclude(100000 + i) end
  assert(#MS.Excluded() == 200, "bounded: " .. #MS.Excluded())
  local ok2, why2 = MS.Exclude(999999)
  assert(ok2 == false and why2:find("remove one"), "a full list says so")
  c.TwichUIDB.ui.mageSell.exclude = { [9009] = true }
  MS.ClearCache()
end

---------------------------------------------------------------------------
-- A class that is not a Mage gets nothing registered.
---------------------------------------------------------------------------
do
  c.CLASS = "WARRIOR"
  M.mageSell = true
  MS.Refresh()
  assert(not events.MERCHANT_SHOW and MS.Enabled() == false, "not for a Warrior")
  Visit(); assert(#c.USED == 0 and #c.R_OUT == 0); Leave()
  c.CLASS = "MAGE"
  M.mageSell = false
  MS.Refresh()
end

---------------------------------------------------------------------------
-- Dry run: says what would be sold, sells nothing, once per visit.
---------------------------------------------------------------------------
Item(5350, "Conjured Water", { spellName = "Drink", text = DRINK:format(420), price = 0 })
Bags({ { 4540, 5 }, { 4541, 3 }, { 5349, 20 }, { 9002, 5, { bound = true } } })
c.TwichUIDB.ui.mageSell.exclude = {}
MS.ClearCache()
M.mageSell, M.mageSellFood, M.mageSellDrink, M.mageSellDryRun = true, true, true, true
MS.Refresh()
assert(events.MERCHANT_SHOW and events.MERCHANT_CLOSED and events.PLAYER_REGEN_DISABLED, "listening while on")
assert(not events.BAG_UPDATE_DELAYED, "no bag listener outside a run")
Reset()
Visit()
assert(#c.USED == 0, "dry run sells nothing")
assert(Says("Dry run: would sell 2 stacks") and Says("Nothing was sold"), "one report: " .. table.concat(c.R_OUT, " | "))
assert(#c.R_OUT == 1, "a single line")
assert(c.BAGS[0][1].id == 4540 and c.BAGS[0][2].count == 3, "bags untouched")
assert(MS.Last().dry == true and MS.Last().eligible == 2 and MS.Last().stacks == 0)
c.FireEvent("MERCHANT_UPDATE"); Flush()
assert(#c.R_OUT == 1, "a merchant update starts nothing")
Leave()
assert(not events.BAG_UPDATE_DELAYED, "no bag listener after a run")

---------------------------------------------------------------------------
-- A real run: one sale at a time, each counted when the bag shows it.
---------------------------------------------------------------------------
M.mageSellDryRun = false
Reset(); Visit()
assert(#c.USED == 1 and c.USED[1][3] == 4540, "the first stack, and only the first, is sold: " .. #c.USED)
assert(events.BAG_UPDATE_DELAYED, "listening while a run waits")
c.FireEvent("BAG_UPDATE_DELAYED")
assert(#c.USED == 1, "the bag hasn't changed, so the next waits")
Settle()
assert(#c.USED == 2 and c.USED[2][3] == 4541, "the next goes once the first is gone")
Settle()
assert(#c.USED == 2 and not events.BAG_UPDATE_DELAYED, "run over, no listener")
assert(Says("Sold 2 stacks (8 items) of ordinary food and drink") and Says("about 3s 5c"),
  "one summary: " .. table.concat(c.R_OUT, " | "))
assert(#c.R_OUT == 1)
assert(c.BAGS[0][3].id == 5349 and c.BAGS[0][4].id == 9002, "conjured and bound items stayed")
assert(MS.Last().stacks == 2 and MS.Last().items == 8 and MS.Last().value == 305 and MS.Last().outcome == "done")
Leave()

---------------------------------------------------------------------------
-- The per-visit limit: ten stacks, the rest reported, no second batch by itself.
---------------------------------------------------------------------------
do
  local list = {}
  for i = 1, 14 do
    Item(7000 + i, "Bread " .. i, { price = 3 })
    list[#list + 1] = { 7000 + i, 2 }
  end
  Bags(list)
  MS.ClearCache()
  Reset(); Visit()
  for _ = 1, 20 do if c.PENDING then Settle() end end
  assert(#c.USED == 10, "at most ten stacks a visit: " .. #c.USED)
  assert(Says("4 more are eligible") and Says("at most 10 stacks"), "the limit is said: " .. table.concat(c.R_OUT, " | "))
  assert(#c.R_OUT == 1, "one summary, not one per stack")
  Flush()
  assert(#c.USED == 10, "no second batch by itself")
  -- deliberate: the player's own click continues
  local ok = MS.Begin(true)
  assert(ok and #c.USED == 11, "Sell now continues")
  for _ = 1, 20 do if c.PENDING then Settle() end end
  assert(#c.USED == 14, "the rest, on the player's click: " .. #c.USED)
  Leave(); Reset()
end

---------------------------------------------------------------------------
-- Stale slots: what moved is skipped, not sold from an old list.
---------------------------------------------------------------------------
do
  Bags({ { 4540, 5 }, { 4541, 3 }, { 4542, 2 } })
  Item(4542, "Rye Bread", { price = 30 })
  MS.ClearCache()
  Reset(); Visit()
  assert(#c.USED == 1 and c.USED[1][3] == 4540)
  c.BAGS[0][2] = { id = 4541, count = 1 }       -- the player split the stack meanwhile
  Settle()
  assert(#c.USED == 2 and c.USED[2][3] == 4542, "the changed slot was skipped")
  Settle()
  assert(Says("1 changed in your bags and was skipped"), table.concat(c.R_OUT, " | "))
  assert(c.BAGS[0][2].count == 1, "the changed stack was left alone")
  Leave(); Reset()
end

---------------------------------------------------------------------------
-- A slot that gets locked or put on the list between the look and the sale is skipped.
---------------------------------------------------------------------------
do
  Bags({ { 4540, 5 }, { 4541, 3 }, { 4542, 2 } })
  MS.ClearCache()
  Reset(); Visit()
  c.BAGS[0][2].locked = true
  MS.Exclude(4542)
  Settle()
  Settle()
  assert(#c.USED == 1, "locked and newly excluded stacks were not sold: " .. #c.USED)
  MS.Include(4542)
  Leave(); Reset()
end

---------------------------------------------------------------------------
-- The merchant closes mid-run: the run ends and is never resumed at another merchant.
---------------------------------------------------------------------------
do
  Bags({ { 4540, 5 }, { 4541, 3 }, { 4542, 2 } })
  MS.ClearCache()
  Reset(); Visit()
  assert(#c.USED == 1)
  Leave()
  Settle()
  assert(#c.USED == 1 and not events.BAG_UPDATE_DELAYED, "closed: nothing more, no listener")
  assert(Says("Stopped: the merchant closed"), table.concat(c.R_OUT, " | "))
  -- another merchant: a new run from a fresh look, not the old queue
  Reset()
  c.BAGS = { [0] = { [1] = { id = 4541, count = 3 } } }
  Visit()
  assert(#c.USED == 1 and c.USED[1][3] == 4541, "a new visit looks again")
  Settle(); Leave(); Reset()
end

---------------------------------------------------------------------------
-- Combat, the switch, an option, a blocked sale and one the game doesn't show.
---------------------------------------------------------------------------
do
  local function Fresh()
    Bags({ { 4540, 5 }, { 4541, 3 }, { 4542, 2 } })
    MS.ClearCache()
    Reset()
  end
  Fresh(); Visit()
  c.COMBAT = true
  c.FireEvent("PLAYER_REGEN_DISABLED")
  Settle()
  assert(#c.USED == 1 and Says("Stopped: combat started"), "combat stops it")
  c.COMBAT = false; Leave(); Reset()

  Fresh(); Visit()
  M.mageSell = false; MS.Refresh()
  Settle()
  assert(#c.USED == 1 and not events.MERCHANT_SHOW and not events.BAG_UPDATE_DELAYED, "switched off: stopped and unregistered")
  assert(#c.R_OUT == 0, "no summary on top of the player's own change")
  M.mageSell = true; MS.Refresh(); Leave(); Reset()

  Fresh(); Visit()
  M.mageSellDryRun = true            -- turned back on without a Refresh: the next step sees it
  Settle()
  assert(#c.USED == 1, "dry run turned on mid-run stops it")
  M.mageSellDryRun = false; Leave(); Reset()

  Fresh(); Visit()
  c.FireEvent("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "UseContainerItem")
  assert(c.PENDING and #c.USED == 1)
  c.FireEvent("ADDON_ACTION_BLOCKED", "!!!TwichUI", "UseContainerItem")
  Settle()
  assert(#c.USED == 1 and Says("blocked the sale"), "another addon's block isn't ours; ours stops it")
  Leave(); Reset()
  Visit()
  assert(#c.USED == 0, "after a block, no more automatic runs this session")
  -- the player's own click may still be tried; "forbidden" ends a run the same way
  Fresh()
  assert(MS.Begin(true) and #c.USED == 1, "Sell now is still the player's to try")
  c.FireEvent("ADDON_ACTION_FORBIDDEN", "!!!TwichUI", "UseContainerItem")
  Settle()
  assert(#c.USED == 1 and Says("blocked the sale"), "a forbidden action ends it too")
  assert(not events.ADDON_ACTION_FORBIDDEN and not events.ADDON_ACTION_BLOCKED, "block listeners only during a run")
  Leave(); Reset()
  Leave(); Reset()
end

do
  -- (a fresh client for the unconfirmed case, so the session's block above doesn't apply)
  local d = MakeClient("Pat", { "!!!TwichUI" })
  d.print = c.print
  for k, v in pairs({ UnitClass = c.UnitClass, UnitLevel = c.UnitLevel, InCombatLockdown = c.InCombatLockdown, HEALTH = "Health", MANA = "Mana",
    ITEM_CONJURED = "Conjured Item", ITEM_BIND_QUEST = "Quest Item", ITEM_STARTS_QUEST = "x", BUYBACK_ITEMS_PER_PAGE = 12, NUM_BAG_SLOTS = 4,
    MerchantFrame = c.MerchantFrame, C_Container = c.C_Container, C_Item = c.C_Item, C_Spell = c.C_Spell, C_TooltipInfo = c.C_TooltipInfo,
    CreateFrame = c.CreateFrame, UIParent = c.UIParent, UISpecialFrames = {}, GameTooltip = c.GameTooltip }) do d[k] = v end
  for _, f in ipairs({ "chronicle/Style.lua", "modules/Interact.lua", "modules/Borders.lua", "modules/FoodDrink.lua", "modules/MageSell.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, d); chunk("!!!TwichUI", {})
  end
  d.TwichUIDB = { modules = { mageSell = true, mageSellDryRun = false } }
  d.LOADED["!!!TwichUI"] = true; d.FireEvent("ADDON_LOADED", "!!!TwichUI")
  d.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Bags({ { 4540, 5 }, { 4541, 3 } })
  Reset()
  c.MERCHANT_UP = true
  d.FireEvent("MERCHANT_SHOW"); Flush()
  assert(#c.USED == 1)
  d.FireEvent("BAG_UPDATE_DELAYED")      -- nothing changed
  RunLongTimers(5)                        -- the game never shows it
  assert(#c.USED == 1 and Says("did not show the last sale"), "an unconfirmed sale ends the run: " .. table.concat(c.R_OUT, " | "))
  assert(Says("Sold nothing"), "and it is not counted as sold")
  local s = d.TwichUI.MageSell.Last()
  assert(s.stacks == 0 and s.outcome == "unconfirmed")
  c.MERCHANT_UP = false
end

---------------------------------------------------------------------------
-- The report holds counts and codes, never names.
---------------------------------------------------------------------------
do
  Bags({ { 4540, 5 }, { 5349, 3 }, { 9002, 5, { bound = true } } })
  MS.ClearCache()
  local s = MS.Snapshot()
  assert(s.mage and s.enabled and s.markers.conjuredText and s.markers.tooltipApi and s.conjuredKnown == 15, "conjured known: " .. s.conjuredKnown)
  assert(s.scan and s.scan.eligible == 1 and s.scan.counts.conjured == 1 and s.scan.counts.bound == 1)
  local function NoNames(v, path)
    if type(v) == "string" then
      for _, name in ipairs({ "Tough Hunk of Bread", "Conjured Muffin", "Bound Bread" }) do
        assert(not v:find(name, 1, true), path .. " carries an item name")
      end
    elseif type(v) == "table" then
      for k, x in pairs(v) do NoNames(k, path); NoNames(x, path .. "." .. tostring(k)) end
    end
  end
  NoNames(s, "snapshot")
end

---------------------------------------------------------------------------
-- The window: opens without selling or holding anything, and Sell now only where it can work.
---------------------------------------------------------------------------
do
  Bags({ { 4540, 5 }, { 4541, 3 } })
  MS.ClearCache()
  M.mageSell, M.mageSellDryRun = true, true
  MS.Refresh()
  Reset()
  W.Show()
  local win = byName.TwichUIMageSellWindow
  assert(win and win.shown, "the window is made and shown")
  assert(#c.USED == 0 and c.CURSOR_CLEARED == nil, "opening it sells and holds nothing")
  assert(win.sell.enabled == false, "Sell now is off in dry run")
  M.mageSellDryRun = false
  c.MERCHANT_UP = false
  W.Refresh()
  assert(win.sell.enabled == false, "and without a merchant")
  c.MERCHANT_UP = true; c.FireEvent("MERCHANT_SHOW"); Reset()
  W.Refresh()
  assert(win.sell.enabled == true, "enabled at a merchant with Dry run off")
  c.COMBAT = true; W.Refresh()
  assert(win.sell.enabled == false, "not in combat")
  c.COMBAT = false
  -- a drop on the add area keeps that item and puts it back
  c.GetCursorInfo = function() return "item", 4541 end
  win.drop.scripts.OnReceiveDrag(win.drop)
  assert(MS.IsExcluded(4541) and c.CURSOR_CLEARED == 1, "dropped item excluded, and the cursor let go")
  c.GetCursorInfo = function() return "spell", 5 end
  win.drop.scripts.OnReceiveDrag(win.drop)
  assert(not MS.IsExcluded(5))
  MS.Include(4541)
  W.Hide()
  assert(not events.GET_ITEM_INFO_RECEIVED and not events.BAG_UPDATE_DELAYED, "a closed window listens to nothing")
  Leave()
end

print("MAGE SELL TEST PASSED")
