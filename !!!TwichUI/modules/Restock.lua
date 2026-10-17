-- TwichUI: vendor restocking
-- Keeps a chosen number of selected items in the carried bags. When a merchant that sells an item on the list
-- opens, TwichUI counts what the bags hold and, after asking (the default) or by itself (only once the player has
-- confirmed that on this computer), buys enough to reach the target. Off until turned on (modules.restock, only an
-- explicit true); the list starts empty and nothing on it is ever enabled by TwichUI itself.
--
-- The rules (per profile, TwichUIDB.ui.restock):
--   items      { { id = itemID, target = n, enabled = bool }, ... }   the order is the priority when money or the
--              spending limit can't cover everything: higher in the list is bought first
--   mode       "ask" (default) | "auto". "auto" is used only while ui.restockAck is true (account-wide, never
--              shared or carried by a profile): a profile or an imported setup can choose it but can't confirm it
--   useLimit   false (default): no limit of TwichUI's own; true: at most `limit` copper per merchant visit (0 is a
--              real limit: nothing is bought)
-- The settings window (TwichUI_Settings/pages/Restock*.lua) edits them only through the functions below.
--
-- Game APIs (Forever is the "camelot" game type, in the mainline family, so Blizzard's Mainline MerchantFrame.lua
-- is the one it loads; every merchant call below is one that file makes):
--   GetMerchantNumItems(), GetMerchantItemID(i), GetMerchantItemLink(i), GetMerchantItemMaxStack(i),
--   GetMerchantItemCostInfo(i) (how many items or currencies a listing costs besides money), BuyMerchantItem(i, n),
--   C_MerchantFrame.GetItemInfo(i) -> { price, stackCount, numAvailable, isPurchasable, hasExtendedCost, currencyID }
--   GetMoney(); C_Container.GetContainerNumSlots/GetContainerItemInfo/GetContainerNumFreeSlots (its second result is
--   the bag's family); C_Item.GetItemMaxStackSizeByID, GetItemFamily, GetItemUniqueness, GetItemInfoInstant,
--   RequestLoadItemDataByID; events MERCHANT_SHOW, MERCHANT_CLOSED, MERCHANT_UPDATE, BAG_UPDATE_DELAYED,
--   GET_ITEM_INFO_RECEIVED, UI_ERROR_MESSAGE, ADDON_ACTION_BLOCKED/FORBIDDEN, PLAYER_REGEN_DISABLED.
-- What Blizzard's own buttons show about a listing (MerchantItemButton_BuyMultipleStacks, the stack split frame):
--   * `price` is for one purchase of `stackCount` items (it divides by stackCount for a single item's cost);
--   * the quantity given to BuyMerchantItem is a count of items, in steps of stackCount (the split frame's
--     minimum split), at most GetMerchantItemMaxStack(i) in one call;
--   * numAvailable is -1 for unlimited, 0 for sold out, otherwise a limited stock. Whether a limited stock counts
--     items or purchases isn't shown anywhere, so it is read as items (the smaller of the two): at worst TwichUI buys
--     less than it could.
--   * a listing with hasExtendedCost, a currencyID or any cost item is bought with something besides money: never
--     bought here. Buyback has listings of its own (GetBuybackItemInfo); GetMerchantItemID(i) is only what is for sale.
-- None of this has been seen in the game; docs/vendor-restock.md lists the checks.
--
-- Counting: only the carried bags (backpack and the equipped bags, special bags such as quivers and pouches
-- included), by item ID. Never the bank, mail, auctions or anything equipped. Room: empty slots of a bag that can
-- hold the item (an ordinary bag, or a special bag whose family matches the item's) and the free part of the
-- item's own stacks.
--
-- A visit: a moment after MERCHANT_SHOW (after TwichUI's own selling, if it is running), one plan, read only. Ask
-- mode shows it (items, quantities, prices, total, what falls short and why) with Purchase and Cancel; nothing is
-- bought until Purchase. Auto mode goes straight on. Either way the plan is bought one listing at a time: each
-- purchase is checked again first (same visit and settings, merchant open, out of combat, the same listing at a
-- price no higher than approved, bags, money and spending limit counted again, never more than approved), then the
-- next waits until the bags show the last one arrived. One that doesn't show up, or that the game refuses, stops
-- the run: nothing is retried. One run per visit, so bags changing afterwards never start another. The merchant
-- closing, combat, the feature or any rule changing, or a profile change drops it at once. Nothing of a visit is saved.

local R = TwichUI
local RS = {}
R.Restock = RS

local SETTLE = 0.5             -- seconds after the merchant opens before anything is looked at
local WAIT_STEP = 0.5          -- seconds between looks while TwichUI's own selling runs or the merchant's data loads
local MAX_SELL_WAITS = 40      -- looks while selling runs before giving up on this visit (20 seconds)
local MAX_INFO_TRIES = 3       -- looks for merchant or item data that hasn't arrived, before planning with what is known
local STEP_WAIT = 3            -- seconds the game has to show one purchase in the bags before the run stops
local REPORT_SETTLE = 0.5      -- seconds after the last purchase before the summary, so the money has been taken
local MAX_REVIEWS = 3          -- fresh questions a visit may ask after the approved plan changed under it
local MAX_LINES = 10           -- items listed by name in the question
local PROMPT = "TWICHUI_RESTOCK_CONFIRM"

RS.MAX_ITEMS = 60
RS.MAX_TARGET = 9999
RS.DEFAULT_TARGET = 20
RS.DEFAULTS = { mode = "ask", useLimit = false, limit = 10000 }
RS.LIMITS = { limit = { 0, 99999999 } }   -- copper: up to 9,999g 99s 99c
RS.MODES = { { "ask", "Ask before purchasing" }, { "auto", "Purchase automatically" } }

-- Why something wasn't bought (or not all of it), in the words the question and the summary use.
RS.REASONS = {
    ["extended-cost"] = "costs tokens, items or another currency besides gold, which TwichUI doesn't spend",
    ["no-price"] = "has no gold price TwichUI can read",
    ["entry-unreadable"] = "the merchant's listing couldn't be read",
    ["not-purchasable"] = "the merchant won't sell it to you",
    ["sold-out"] = "sold out",
    stock = "the merchant has only a few left",
    ["bags-full"] = "not enough room in your bags",
    unique = "you can carry only so many",
    money = "not enough money",
    ["spend-limit"] = "your spending limit for a visit",
    bundle = "sold only in bundles, and another bundle would go past your target",
    ["count-unknown"] = "TwichUI couldn't count it in your bags",
    ["item-data-pending"] = "its item details hadn't loaded",
    ["price-changed"] = "its price went up",
}

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local function Whole(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v % 1 == 0 end
local function ValidID(id) return Whole(id) and id >= 1 and id <= 2147483647 end
local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Count(n, one, many) return ("%d %s"):format(n, n == 1 and one or many) end

---------------------------------------------------------------------------
-- Settings. Strict on purpose: only an explicit true turns the feature on, and only an acknowledged "auto" buys
-- without asking, so a missing or damaged value can never start spending.
---------------------------------------------------------------------------
function RS.Enabled()
    local m = TwichUIDB and TwichUIDB.modules
    return type(m) == "table" and m.restock == true
end

local function Store(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    if type(db.ui.restock) ~= "table" then
        if not create then return nil end
        db.ui.restock = {}
    end
    return db.ui.restock
end

function RS.Valid(key, value)
    if key == "mode" then return value == "ask" or value == "auto" end
    if key == "useLimit" then return type(value) == "boolean" end
    if key == "limit" then
        local l = RS.LIMITS.limit
        return Whole(value) and value >= l[1] and value <= l[2]
    end
    return false
end

function RS.Get(key)
    local t = Store(false)
    local value
    if t then value = t[key] end   -- not "and ... or": a saved false is a value
    if RS.Valid(key, value) then return value end
    return RS.DEFAULTS[key]
end

local Changed   -- (below) every change to what a visit would do goes through it

-- fn() after the rules, the mode or a visit changed (the settings window redraws). Registered once each.
local listeners = {}
function RS.OnChange(fn) listeners[#listeners + 1] = fn end
local function Notify()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("restock view", err) end
    end
end

-- Returns true, or false and why: "invalid", "needs-ack" (choosing auto before confirming), "no-settings".
function RS.Set(key, value)
    if RS.DEFAULTS[key] == nil or not RS.Valid(key, value) then return false, "invalid" end
    if key == "mode" and value == "auto" and not RS.Acknowledged() then return false, "needs-ack" end
    local t = Store(true)
    if not t then return false, "no-settings" end
    if t[key] == value then return true end
    t[key] = value
    Changed()
    return true
end

-- Whether the player has confirmed, on this account, that "Purchase automatically" spends without asking.
function RS.Acknowledged()
    local ui = TwichUIDB and TwichUIDB.ui
    return type(ui) == "table" and ui.restockAck == true
end

function RS.Acknowledge()
    if type(TwichUIDB) ~= "table" then return false end
    if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
    TwichUIDB.ui.restockAck = true
    Changed()
    return true
end

function RS.SavedMode() return RS.Get("mode") end
-- What a visit does: "auto" only when chosen and confirmed here.
function RS.Mode()
    if RS.Get("mode") == "auto" and RS.Acknowledged() then return "auto" end
    return "ask"
end
-- "auto" was chosen (by you on another computer, a profile or a shared setup) but isn't confirmed here.
function RS.AutoWaiting() return RS.Get("mode") == "auto" and not RS.Acknowledged() end

-- The most a visit may spend, in copper, or nil for no limit of TwichUI's own (the money you have always is one).
function RS.SpendLimit()
    if RS.Get("useLimit") ~= true then return nil end
    return RS.Get("limit")
end

-- "1g 5s 20c" from copper, "0c" for none. Plain text (the setting's own button and the tests read it).
function RS.MoneyText(copper)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- For chat: the game's coin string where it has one.
local function Money(copper)
    if type(GetMoneyString) == "function" then
        local ok, text = pcall(GetMoneyString, copper)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return RS.MoneyText(copper)
end

---------------------------------------------------------------------------
-- The list. Item IDs only; one rule per item. Reading never writes; a write stores the list as it reads (an entry
-- that can't be read is left out of that write, and nothing else is touched).
---------------------------------------------------------------------------
local function CleanRule(e)
    if type(e) ~= "table" or not ValidID(e.id) then return nil end
    if not (Whole(e.target) and e.target >= 1 and e.target <= RS.MAX_TARGET) then return nil end
    return { id = e.id, target = e.target, enabled = e.enabled == true }
end
RS.CleanRule = CleanRule

-- The rules in order, as copies: { { id, target, enabled }, ... }.
function RS.Rules()
    local t = Store(false)
    local list, seen = {}, {}
    if t and type(t.items) == "table" then
        for _, e in ipairs(t.items) do
            local rule = CleanRule(e)
            if rule and not seen[rule.id] then
                seen[rule.id] = true
                list[#list + 1] = rule
                if #list >= RS.MAX_ITEMS then break end
            end
        end
    end
    return list
end

function RS.Rule(id)
    for i, rule in ipairs(RS.Rules()) do
        if rule.id == id then return rule, i end
    end
end

local function Write(list)
    local t = Store(true)
    if not t then return false end
    local out = {}
    for i, rule in ipairs(list) do out[i] = { id = rule.id, target = rule.target, enabled = rule.enabled == true } end
    t.items = out
    Changed()
    return true
end

-- An item ID from a number, an item link or typed digits; nil otherwise.
function RS.ParseItem(value)
    if type(value) == "string" then
        value = tonumber(value:match("item:(%d+)") or value:match("^%s*(%d+)%s*$"))
    end
    if ValidID(value) then return value end
end

-- Whether the game knows an item by this ID. nil when it can't say (no API).
function RS.Known(id)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    return Plain(C_Item.GetItemInfoInstant(id)) ~= nil
end

-- Adds an item. Returns true, index, "added" | "exists" (it was there already: nothing changed), or false, a sentence.
function RS.Add(value, target, enabled)
    local id = RS.ParseItem(value)
    if not id then return false, "That isn't an item ID. Type the number from the item's link, or drop the item here." end
    if RS.Known(id) == false then return false, ("No item has the ID %d."):format(id) end
    local list = RS.Rules()
    for i, rule in ipairs(list) do
        if rule.id == id then return true, i, "exists" end
    end
    if #list >= RS.MAX_ITEMS then return false, ("The list holds %d items; remove one first."):format(RS.MAX_ITEMS) end
    target = target or RS.DEFAULT_TARGET
    if not (Whole(target) and target >= 1 and target <= RS.MAX_TARGET) then target = RS.DEFAULT_TARGET end
    list[#list + 1] = { id = id, target = target, enabled = enabled ~= false }
    if not Write(list) then return false, "Your settings aren't available right now." end
    return true, #list, "added"
end

-- Returns true, or false and a sentence.
function RS.SetTarget(id, target)
    if not (Whole(target) and target >= 1 and target <= RS.MAX_TARGET) then
        return false, ("A target is a whole number from 1 to %d."):format(RS.MAX_TARGET)
    end
    local list = RS.Rules()
    for _, rule in ipairs(list) do
        if rule.id == id then
            if rule.target == target then return true end
            rule.target = target
            return Write(list), nil
        end
    end
    return false, "That item isn't on your list any more."
end

function RS.SetRuleEnabled(id, on)
    local list = RS.Rules()
    for _, rule in ipairs(list) do
        if rule.id == id then
            on = on and true or false
            if rule.enabled == on then return true end
            rule.enabled = on
            return Write(list)
        end
    end
    return false
end

-- Takes the rule off the list. Nothing in your bags is touched.
function RS.Remove(id)
    local list = RS.Rules()
    for i, rule in ipairs(list) do
        if rule.id == id then
            table.remove(list, i)
            return Write(list)
        end
    end
    return false
end

-- Moves a rule up (delta -1) or down (+1) in the priority order.
function RS.Move(id, delta)
    local list = RS.Rules()
    for i, rule in ipairs(list) do
        if rule.id == id then
            local j = i + delta
            if j < 1 or j > #list then return false end
            list[i], list[j] = list[j], list[i]
            return Write(list)
        end
    end
    return false
end

-- Whether TwichUI's own selling must leave this item alone: it is restocked, so selling it would only be bought back.
function RS.Protects(id)
    if not RS.Enabled() then return false end
    local rule = RS.Rule(id)
    return rule ~= nil and rule.enabled
end

---------------------------------------------------------------------------
-- Class reagents to choose from. Reagents and ammunition sold by vendors, by class. Item IDs only: the names and
-- icons shown are the game's own. Sources (both specific to Forever): EllesmereUI DataBars' Supplies block, whose
-- class list is used only on Forever (EllesmereUI.IS_FOREVER), for the class reagents; RestedXP's Forever guides
-- (.collect lines with the item named) for the arrows, shot, Dust of Decay, Empty Vial and Flash Powder. Left out
-- on purpose: what vendors don't sell (Soul Shard, Blinding Powder, the poisons themselves), what is never used up
-- (Thieves' Tools), and higher ammunition and poison ingredients neither source names. Which reagent a spell needs
-- depends on its rank and what you have learned, which these don't check: `use` says what each is for.
---------------------------------------------------------------------------
RS.SUGGESTIONS = {
    MAGE = {
        { id = 17020, target = 20, use = "Arcane Brilliance" },
        { id = 17031, target = 10, use = "Teleport spells" },
        { id = 17032, target = 10, use = "Portal spells" },
        { id = 17056, target = 20, use = "Slow Fall" },
    },
    PRIEST = {
        { id = 17028, target = 20, use = "Prayer of Fortitude (rank 1)" },
        { id = 17029, target = 20, use = "Higher-rank group buffs" },
        { id = 17056, target = 20, use = "Levitate" },
    },
    DRUID = {
        { id = 17021, target = 20, use = "Gift of the Wild (rank 1)" },
        { id = 17026, target = 20, use = "Gift of the Wild (rank 2)" },
        { id = 17034, target = 5, use = "Rebirth (rank 1)" },
        { id = 17035, target = 5, use = "Rebirth (rank 2)" },
        { id = 17036, target = 5, use = "Rebirth (rank 3)" },
        { id = 17037, target = 5, use = "Rebirth (rank 4)" },
        { id = 17038, target = 5, use = "Rebirth (rank 5)" },
    },
    PALADIN = {
        { id = 21177, target = 20, use = "Greater Blessings" },
        { id = 17033, target = 5, use = "Divine Intervention" },
    },
    SHAMAN = {
        { id = 17030, target = 5, use = "Reincarnation" },
        { id = 17057, target = 10, use = "Water Breathing" },
        { id = 17058, target = 10, use = "Water Walking" },
    },
    WARLOCK = {
        { id = 5565, target = 5, use = "Inferno" },
        { id = 16583, target = 5, use = "Ritual of Doom" },
    },
    ROGUE = {
        { id = 5140, target = 10, use = "Vanish" },
        { id = 2928, target = 20, use = "Crafting poisons" },
        { id = 3371, target = 20, use = "Crafting poisons" },
    },
    HUNTER = {
        { id = 2512, target = 1000, use = "Ammunition for bows and crossbows" },
        { id = 2515, target = 1000, use = "Ammunition for bows and crossbows" },
        { id = 2516, target = 1000, use = "Ammunition for guns" },
        { id = 2519, target = 1000, use = "Ammunition for guns" },
    },
}
RS.SUGGESTION_CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK" }

function RS.PlayerClass()
    if not UnitClass then return nil end
    local _, class = UnitClass("player")
    return Plain(class)
end

-- The suggestions for a class (default: yours), each a copy with `listed` set when the item is on your list.
function RS.Suggestions(class)
    class = class or RS.PlayerClass()
    local out = {}
    for i, s in ipairs(RS.SUGGESTIONS[class] or {}) do
        out[i] = { id = s.id, target = s.target, use = s.use, listed = RS.Rule(s.id) ~= nil }
    end
    return out
end

-- Adds one suggestion with its suggested target. It is added on, like an item you add yourself, and is yours to
-- change or remove: nothing is added for you, and nothing is removed when you change class or profile.
function RS.AddSuggestion(class, id)
    for _, s in ipairs(RS.SUGGESTIONS[class] or {}) do
        if s.id == id then return RS.Add(id, s.target, true) end
    end
    return false, "That isn't one of the suggestions."
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

local function Band(a, b)
    if bit and bit.band then return bit.band(a, b) end
    return nil
end

-- One look at the carried bags: { counts = { [id] = n }, unknown = { [id] = true }, empty = { { bag, slot, family } },
-- partial = { [id] = room in its own stacks, by its stack size, filled in by Room } , stacks = { [id] = { counts } } }.
local function ScanBags(wanted)
    local out = { counts = {}, unknown = {}, empty = {}, stacks = {} }
    for id in pairs(wanted) do out.counts[id] = 0 end
    for bag = 0, LastBag() do
        local slots = Plain(C_Container.GetContainerNumSlots(bag)) or 0
        if slots > 0 then
            local family = 0
            if bag ~= 0 and C_Container.GetContainerNumFreeSlots then
                local _, f = C_Container.GetContainerNumFreeSlots(bag)
                family = Plain(f)
            end
            for slot = 1, slots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if not info then
                    out.empty[#out.empty + 1] = { bag = bag, slot = slot, family = family }
                else
                    local id = Plain(info.itemID)
                    if id and wanted[id] then
                        local n = Plain(info.stackCount)
                        if Whole(n) and n >= 0 then
                            out.counts[id] = out.counts[id] + n
                            out.stacks[id] = out.stacks[id] or {}
                            table.insert(out.stacks[id], n)
                        else
                            out.unknown[id] = true
                        end
                    end
                end
            end
        end
    end
    return out
end
RS.ScanBags = ScanBags

-- What a bag of `bagFamily` holds: anything (0), or only what shares a family with the item. A bag whose family
-- can't be read holds nothing as far as this is concerned.
local function Fits(bagFamily, itemFamily)
    if bagFamily == 0 then return true end
    if not (Whole(bagFamily) and Whole(itemFamily) and itemFamily ~= 0) then return false end
    local both = Band(bagFamily, itemFamily)
    return both ~= nil and both ~= 0
end

-- How many more of an item the bags can take: the free part of its own stacks and the empty slots that can hold it
-- (less those `claimed` for other items of the same plan). Also returns the empty slots counted, in order.
local function Room(scan, id, maxStack, itemFamily, claimed)
    local room = 0
    for _, n in ipairs(scan.stacks[id] or {}) do room = room + math.max(0, maxStack - n) end
    local partial = room
    local free = {}
    for _, e in ipairs(scan.empty) do
        if not claimed[e] and Fits(e.family, itemFamily) then
            free[#free + 1] = e
            room = room + maxStack
        end
    end
    return room, partial, free
end

-- What the item itself is: its stack size and family (nil, "item-data-pending" while the game hasn't loaded it).
local function ItemFacts(id)
    local maxStack = C_Item and C_Item.GetItemMaxStackSizeByID and Plain(C_Item.GetItemMaxStackSizeByID(id))
    if not (Whole(maxStack) and maxStack >= 1) then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return nil, "item-data-pending"
    end
    local family = C_Item.GetItemFamily and Plain(C_Item.GetItemFamily(id)) or 0
    local limitMax
    if C_Item.GetItemUniqueness then
        local _, most = C_Item.GetItemUniqueness(id)
        most = Plain(most)
        if Whole(most) and most > 0 then limitMax = most end
    end
    return { maxStack = maxStack, family = Whole(family) and family or 0, limitMax = limitMax }
end

---------------------------------------------------------------------------
-- The merchant
---------------------------------------------------------------------------
local merchantOpen = false

function RS.MerchantOpen()
    if not merchantOpen then return false end
    local frame = _G.MerchantFrame
    if type(frame) == "table" and frame.IsShown and not frame:IsShown() then return false end
    return true
end

-- One listing as it is now: { index, id, price (per purchase), stack, available, maxStack, why (nil: can be bought
-- with money) }. nil when the listing can't be read at all.
local function Listing(index)
    local id = GetMerchantItemID and Plain(GetMerchantItemID(index))
    local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(index)
    if not ValidID(id) or type(info) ~= "table" then return nil end
    local e = { index = index, id = id, price = Plain(info.price), stack = Plain(info.stackCount),
        available = Plain(info.numAvailable), name = Plain(info.name) }
    local extended, currency, purchasable = Plain(info.hasExtendedCost), Plain(info.currencyID), Plain(info.isPurchasable)
    -- what else it costs: anything but an explicit "nothing" (no extended cost, no currency, no cost items) is more than money
    local otherCost = extended ~= false or currency ~= nil
    if not otherCost and GetMerchantItemCostInfo then
        local costs = Plain(GetMerchantItemCostInfo(index))
        otherCost = not (Whole(costs) and costs == 0)
    end
    e.maxStack = GetMerchantItemMaxStack and Plain(GetMerchantItemMaxStack(index))
    if otherCost then
        e.why = "extended-cost"
    elseif not (Whole(e.price) and e.price > 0) then
        e.why = "no-price"
    elseif not (Whole(e.stack) and e.stack >= 1) or not Whole(e.available) or e.available < -1 then
        e.why = "entry-unreadable"
    elseif purchasable ~= true then
        e.why = "not-purchasable"
    elseif e.available == 0 then
        e.why = "sold-out"
    elseif not (Whole(e.maxStack) and e.maxStack >= e.stack) then
        e.why = "entry-unreadable"
    end
    return e
end
RS.Listing = Listing

-- Every listing for sale: byId = { [id] = { listing, ... } }, missing = listings that couldn't be read yet.
local function Listings()
    local n = GetMerchantNumItems and Plain(GetMerchantNumItems())
    if not Whole(n) or n < 0 then return nil end
    local byId, missing = {}, 0
    for index = 1, n do
        local e = Listing(index)
        if e then
            byId[e.id] = byId[e.id] or {}
            table.insert(byId[e.id], e)
        else
            missing = missing + 1
        end
    end
    return byId, missing
end

local function LinkFor(id, index)
    local link = index and GetMerchantItemLink and Plain(GetMerchantItemLink(index))
    if type(link) == "string" and link ~= "" then return link end
    local name, itemLink = nil, nil
    if C_Item and C_Item.GetItemInfo then name, itemLink = C_Item.GetItemInfo(id) end
    itemLink = Plain(itemLink)
    if type(itemLink) == "string" and itemLink ~= "" then return itemLink end
    name = Plain(name)
    if type(name) == "string" and name ~= "" then return name end
    return ("item %d"):format(id)
end

-- p1/s1 cheaper per item than p2/s2 (integers, no division).
local function Cheaper(p1, s1, p2, s2) return p1 * s2 < p2 * s1 end

-- The most of one listing that fits, in whole purchases: units, and why it is less than `deficit` (nil if it isn't).
local function Fit(e, deficit, room, uniqueRoom, money, spend)
    local cap, why = deficit, nil
    local function Cap(n, reason)
        if n < cap then cap, why = n, reason end
    end
    if e.available > 0 then Cap(e.available, "stock") end
    Cap(room, "bags-full")
    if uniqueRoom then Cap(uniqueRoom, "unique") end
    Cap(math.floor(money / e.price) * e.stack, "money")
    if spend then Cap(math.floor(spend / e.price) * e.stack, "spend-limit") end
    cap = math.max(0, cap)
    local units = math.floor(cap / e.stack) * e.stack
    if units < deficit and why == nil then why = "bundle" end
    return units, why
end

---------------------------------------------------------------------------
-- The plan. Reads only: never buys, never changes a setting. plan = {
--   visit, gen, money, limit, total, missing (listings not read), pending (something still loading),
--   items = { { id, link, index, units, stack, price, cost, carried, target, deficit, short, why } },   -- to buy
--   notes = { { id, link, deficit, why } } }  -- sold here and needed, but nothing can be bought, and why
---------------------------------------------------------------------------
local visit, generation = 0, 0

function RS.Plan()
    local plan = { visit = visit, gen = generation, items = {}, notes = {}, total = 0, missing = 0, pending = false }
    plan.money = GetMoney and Plain(GetMoney())
    if not Whole(plan.money) then plan.why = "money-unknown" return plan end
    plan.limit = RS.SpendLimit()
    local byId, missing = Listings()
    if not byId then plan.why = "no-merchant" return plan end
    plan.missing = missing
    local rules, wanted = {}, {}
    for _, rule in ipairs(RS.Rules()) do
        if rule.enabled and byId[rule.id] then
            rules[#rules + 1] = rule
            wanted[rule.id] = true
        end
    end
    if #rules == 0 then return plan end
    local scan = ScanBags(wanted)
    local money, spend = plan.money, plan.limit
    local claimed = {}
    for _, rule in ipairs(rules) do
        local id = rule.id
        local listings = byId[id]
        local carried = scan.counts[id]
        local function Note(why, deficit)
            plan.notes[#plan.notes + 1] = { id = id, link = LinkFor(id, listings[1].index), deficit = deficit, why = why }
        end
        if scan.unknown[id] then
            Note("count-unknown", nil)
        elseif carried < rule.target then
            local deficit = rule.target - carried
            local usable, firstWhy = {}, nil
            for _, e in ipairs(listings) do
                if e.why then firstWhy = firstWhy or e.why else usable[#usable + 1] = e end
            end
            local facts, factsWhy = nil, nil
            if #usable > 0 then facts, factsWhy = ItemFacts(id) end
            if #usable == 0 then
                Note(firstWhy, deficit)
            elseif not facts then
                plan.pending = true
                Note(factsWhy, deficit)
            else
                local room, partial, free = Room(scan, id, facts.maxStack, facts.family, claimed)
                local uniqueRoom = facts.limitMax and math.max(0, facts.limitMax - carried) or nil
                -- the listing that buys the most toward the target; then the cheapest per item; then the first
                local best, bestUnits, bestWhy
                for _, e in ipairs(usable) do
                    local units, why = Fit(e, deficit, room, uniqueRoom, money, spend)
                    if not best or units > bestUnits
                        or (units == bestUnits and Cheaper(e.price, e.stack, best.price, best.stack)) then
                        best, bestUnits, bestWhy = e, units, why
                    end
                end
                if bestUnits <= 0 then
                    Note(bestWhy or "bundle", deficit)
                else
                    local cost = (bestUnits / best.stack) * best.price
                    plan.items[#plan.items + 1] = { id = id, link = LinkFor(id, best.index), index = best.index,
                        units = bestUnits, stack = best.stack, price = best.price, cost = cost, carried = carried,
                        target = rule.target, deficit = deficit, short = deficit - bestUnits, why = bestWhy }
                    plan.total = plan.total + cost
                    money = money - cost
                    if spend then spend = spend - cost end
                    -- the empty slots this needs are not there for the items after it
                    local need = math.max(0, bestUnits - partial)
                    local slots = math.ceil(need / facts.maxStack)
                    for i = 1, math.min(slots, #free) do claimed[free[i]] = true end
                end
            end
        end
    end
    return plan
end

---------------------------------------------------------------------------
-- Words: the question, and the summary afterwards
---------------------------------------------------------------------------
local function PriceText(item)
    if item.stack > 1 then
        return ("%s of %d for %s (%s per %d)"):format(Count(item.units / item.stack, "bundle", "bundles"), item.stack,
            RS.MoneyText(item.cost), RS.MoneyText(item.price), item.stack)
    end
    return ("%s (%s each)"):format(RS.MoneyText(item.cost), RS.MoneyText(item.price))
end

local function Reason(why) return RS.REASONS[why] or "it couldn't be bought" end

-- The question asked in "Ask before purchasing" mode. lead: a sentence before it (a plan that changed).
function RS.QuestionText(plan, lead)
    local lines = {}
    if lead then lines[#lines + 1] = lead .. "\n" end
    lines[#lines + 1] = "TwichUI vendor restocking: buy from this merchant?\n"
    for i, item in ipairs(plan.items) do
        if i > MAX_LINES then
            lines[#lines + 1] = ("...and %s more (in the total)."):format(Count(#plan.items - MAX_LINES, "item", "items"))
            break
        end
        local line = ("%s ×%d: %s"):format(item.link, item.units, PriceText(item))
        if item.short > 0 then line = line .. ("; %d short of your target: %s"):format(item.short, Reason(item.why)) end
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = ("\nTotal: %s. You have %s.%s"):format(RS.MoneyText(plan.total), RS.MoneyText(plan.money),
        plan.limit and (" Spending limit for a visit: %s."):format(RS.MoneyText(plan.limit)) or "")
    if #plan.notes > 0 then
        local parts = {}
        for i, n in ipairs(plan.notes) do
            if i > 4 then parts[#parts + 1] = ("and %d more"):format(#plan.notes - 4) break end
            parts[#parts + 1] = ("%s (%s)"):format(n.link, Reason(n.why))
        end
        lines[#lines + 1] = "Not bought: " .. table.concat(parts, "; ") .. "."
    end
    lines[#lines + 1] = "\nNothing is bought unless you press Purchase."
    return table.concat(lines, "\n")
end

local STOP_TEXT = {
    closed = "the merchant closed",
    combat = "combat started",
    blocked = "the game blocked the purchase",
    ["price-changed"] = "a price went up after you approved it",
    ["listing-changed"] = "the merchant's listing changed",
}

-- One line in your own chat after a run: what arrived in your bags (never what was only asked for), what fell short
-- and why, and why it stopped. Nothing is said for a visit with nothing to do.
local function Report(r, outcome, exactCost)
    local bought, short = {}, r.short
    for _, q in ipairs(r.queue) do
        if q.bought > 0 then bought[#bought + 1] = ("%s ×%d"):format(q.link, q.bought) end
    end
    local parts = {}
    if #bought > 0 then
        local cost = r.spent > 0 and ((exactCost and " for " or " for about ") .. Money(r.spent)) or ""
        if #bought <= 2 then
            parts[#parts + 1] = ("Restocked %s%s."):format(table.concat(bought, " and "), cost)
        else
            parts[#parts + 1] = ("Restocked %s%s: %s."):format(Count(#bought, "item", "items"), cost, table.concat(bought, ", "))
        end
    end
    if #short > 0 then
        local shown = {}
        for i = 1, math.min(3, #short) do shown[i] = short[i] end
        if #short > 3 then shown[#shown + 1] = ("and %d more"):format(#short - 3) end
        parts[#parts + 1] = (#bought > 0 and "Short: " or "Couldn't restock ") .. table.concat(shown, "; ") .. "."
    end
    if r.unconfirmed then
        local u = r.unconfirmed
        local line = ("%s ×%d was asked for but %s"):format(u.link, u.units,
            u.arrived > 0 and ("only %d showed up in your bags"):format(u.arrived) or "it didn't show up in your bags")
        if outcome == "refused" and r.error then line = line .. (": the game said \"%s\""):format((r.error:gsub("[%.%s]+$", ""))) end
        parts[#parts + 1] = line .. ". Nothing more was tried."
    end
    if STOP_TEXT[outcome] then parts[#parts + 1] = "Restocking stopped: " .. STOP_TEXT[outcome] .. "." end
    if #parts == 0 then return end
    R.Print("%s", table.concat(parts, " "))
end

---------------------------------------------------------------------------
-- A visit: the run that buys, and the question before it
---------------------------------------------------------------------------
local run                      -- the purchases in progress, or nil
local prompt                   -- { visit, gen, plan } while the question is open
local planned = 0              -- the visit a plan was already made for (one per visit)
local reviews = 0              -- fresh questions asked this visit
local waits, infoTries = 0, 0
local last                     -- the last visit's outcome, counts only
local active = {}              -- [event] = handler, while registered
local sessionActive = {}       -- events needed only while a purchase waits

local function Want(set, event, handler, wanted)
    if wanted and not set[event] then
        set[event] = handler
        R:On(event, handler)
    elseif not wanted and set[event] then
        R:Off(event, set[event])
        set[event] = nil
    end
end

local function StopWaiting()
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
        Want(sessionActive, e, nil, false)
    end
end

local function StopInfoWait()
    Want(sessionActive, "MERCHANT_UPDATE", nil, false)
    Want(sessionActive, "GET_ITEM_INFO_RECEIVED", nil, false)
end

local function ClosePrompt()
    if prompt then
        prompt = nil
        if StaticPopup_Hide then StaticPopup_Hide(PROMPT) end
    end
end

local function Finish(r, outcome)
    if r ~= run then return end
    run = nil
    StopWaiting()
    local items = 0
    for _, q in ipairs(r.queue) do if q.bought > 0 then items = items + 1 end end
    last = { outcome = outcome, mode = r.mode, items = items, spent = r.spent, short = #r.short,
        unconfirmed = r.unconfirmed ~= nil }
    if outcome == "changed" then
        R.Life.Note("cancelled-stale-restock")
        return   -- the player just changed something: no summary on top of it
    end
    local startMoney, spent = r.startMoney, r.spent
    C_Timer.After(REPORT_SETTLE, function()
        local now = GetMoney and Plain(GetMoney())
        Report(r, outcome, Whole(now) and Whole(startMoney) and startMoney - now == spent)
    end)
    Notify()
end

-- Is it still right to buy, from the settings and the world as they are now? true, or false and the outcome code.
local function Valid(r)
    if r.gen ~= generation or not RS.Enabled() then return false, "changed" end
    if r.visit ~= visit or not RS.MerchantOpen() then return false, "closed" end
    if InCombat() then return false, "combat" end
    return true
end

local Step, Begin, Ask

local function Arrived(r)
    local w = r.waiting
    local scan = ScanBags({ [w.id] = true })
    if scan.unknown[w.id] then return 0 end
    return math.max(0, scan.counts[w.id] - w.before)
end

-- The waiting purchase is settled: delta items arrived of w.units asked for. Only what arrived counts as bought;
-- anything less stops the run (it is never asked for again).
local function Settle(r, delta, outcome)
    local w = r.waiting
    r.waiting = nil
    StopWaiting()
    local got = math.min(delta, w.units)
    local item = r.byId[w.id]
    if got > 0 then
        item.bought = item.bought + got
        r.spent = r.spent + (got / w.stack) * w.price
    end
    if got < w.units then
        r.unconfirmed = { link = item.link, units = w.units, arrived = got }
        if not outcome then
            if w.error then outcome, r.error = "refused", w.error
            else outcome = got > 0 and "partial" or "unconfirmed" end
        end
        Finish(r, outcome)
        return
    end
    Step(r)
end

local function OnBags()
    local r = run
    if not (r and r.waiting) then return end
    local delta = Arrived(r)
    if delta >= r.waiting.units then Settle(r, delta) end
end

-- The game's red error text while a purchase waits ("Inventory is full", ...). It may be about something else, so
-- it only says why, if the purchase then doesn't arrive; the bags still decide.
local function OnError(_, message)
    local r = run
    if not (r and r.waiting) then return end
    message = Plain(message)
    if type(message) == "string" and message ~= "" then r.waiting.error = message:sub(1, 120) end
end

local function OnBlocked(addon)
    local r = run
    if Plain(addon) ~= R.ADDON or not (r and r.waiting) then return end
    Settle(r, Arrived(r), "blocked")
end

local function Timeout(r, token)
    if r ~= run or not r.waiting or r.waiting.token ~= token then return end
    Settle(r, Arrived(r))
end

-- The next purchase, checked against the world as it is now, or the end of the run.
function Step(r)
    if r ~= run then return end
    local ok, why = Valid(r)
    if not ok then Finish(r, why) return end
    while true do
        local item = r.queue[r.index]
        if not item then Finish(r, "done") return end
        local left = item.approved - item.bought
        local e = Listing(item.index)
        if left <= 0 then
            r.index = r.index + 1
        elseif not e or e.id ~= item.id or e.why or e.stack ~= item.stack then
            Finish(r, "listing-changed")
            return
        elseif e.price > item.price then
            -- dearer than approved: the question has to be asked again (or, buying by itself, the run stops)
            if r.mode == "ask" and reviews < MAX_REVIEWS then r.review = true end
            Finish(r, "price-changed")
            if r.review then C_Timer.After(WAIT_STEP, function() Ask(r.visit, "The price of something went up since you looked, so here is the plan again.") end) end
            return
        else
            local facts = ItemFacts(item.id)
            local scan = ScanBags({ [item.id] = true })
            local money = GetMoney and Plain(GetMoney())
            if not facts or scan.unknown[item.id] or not Whole(money) then
                r.short[#r.short + 1] = ("%s (%s)"):format(item.link, Reason(facts and "count-unknown" or "item-data-pending"))
                r.index = r.index + 1
            else
                local carried = scan.counts[item.id]
                local deficit = math.min(left, item.target - carried)
                local room = Room(scan, item.id, facts.maxStack, facts.family, {})
                local uniqueRoom = facts.limitMax and math.max(0, facts.limitMax - carried) or nil
                local spend = r.limit and (r.limit - r.spent) or nil
                local cap = r.approvedTotal - r.spent
                spend = spend and math.min(spend, cap) or cap
                local units, short = Fit(e, deficit, room, uniqueRoom, money, spend)
                units = math.min(units, math.floor(e.maxStack / e.stack) * e.stack)
                if deficit <= 0 or units <= 0 then
                    if deficit > 0 then r.short[#r.short + 1] = ("%s %d (%s)"):format(item.link, deficit, Reason(short or "bundle")) end
                    r.index = r.index + 1
                else
                    r.token = r.token + 1
                    r.waiting = { id = item.id, before = carried, units = units, stack = e.stack, price = e.price, token = r.token }
                    Want(sessionActive, "BAG_UPDATE_DELAYED", OnBags, true)
                    Want(sessionActive, "UI_ERROR_MESSAGE", OnError, true)
                    Want(sessionActive, "ADDON_ACTION_BLOCKED", OnBlocked, true)
                    Want(sessionActive, "ADDON_ACTION_FORBIDDEN", OnBlocked, true)
                    local token = r.token
                    C_Timer.After(STEP_WAIT, function() Timeout(r, token) end)
                    local called, err = pcall(BuyMerchantItem, item.index, units)
                    if not called then
                        if R.Diag then R.Diag.Error("restock", err) end
                        Settle(r, 0, "blocked")
                    end
                    return
                end
            end
        end
    end
end

-- Buys what a plan approved, never more: per item, at most its approved quantity at no more than its approved price,
-- and in all at most the approved total.
function Begin(plan)
    if run then return false, "busy" end
    local r = { gen = generation, visit = visit, mode = RS.Mode(), queue = {}, byId = {}, index = 1, token = 0,
        short = {}, spent = 0, limit = plan.limit, approvedTotal = plan.total, startMoney = GetMoney and Plain(GetMoney()) }
    for _, item in ipairs(plan.items) do
        local q = { id = item.id, link = item.link, index = item.index, approved = item.units, stack = item.stack,
            price = item.price, target = item.target, bought = 0 }
        r.queue[#r.queue + 1] = q
        r.byId[item.id] = q
        if item.short > 0 then r.short[#r.short + 1] = ("%s %d (%s)"):format(item.link, item.short, Reason(item.why)) end
    end
    for _, n in ipairs(plan.notes) do r.short[#r.short + 1] = ("%s (%s)"):format(n.link, Reason(n.why)) end
    run = r
    Notify()
    Step(r)
    return true
end

-- What a visit couldn't buy at all is said once a session for each item and reason, not at every visit.
local told, toldCount = {}, 0
local function FirstTime(n)
    local key = n.id .. ":" .. n.why
    if told[key] then return false end
    if toldCount >= RS.MAX_ITEMS * 4 then told, toldCount = {}, 0 end
    told[key] = true
    toldCount = toldCount + 1
    return true
end

-- Makes the plan for this visit and asks, or buys, or says why nothing can be bought.
local function Visit(mine, lead)
    if mine ~= visit or not RS.MerchantOpen() or not RS.Enabled() then return end
    if InCombat() then last = { outcome = "combat" } return end
    local plan = RS.Plan()
    if plan.why then last = { outcome = plan.why } return end
    StopInfoWait()
    if (plan.missing > 0 or plan.pending) and infoTries < MAX_INFO_TRIES then
        -- the merchant's or an item's details are still arriving: look again when they do, or in a moment, a few
        -- times at most; then the plan is made with what is known, and what isn't is left out
        infoTries = infoTries + 1
        local again = false
        local function Again()
            if again then return end
            again = true
            StopInfoWait()
            C_Timer.After(WAIT_STEP, function() Visit(mine, lead) end)
        end
        Want(sessionActive, "MERCHANT_UPDATE", Again, true)
        Want(sessionActive, "GET_ITEM_INFO_RECEIVED", Again, true)
        C_Timer.After(WAIT_STEP * 2, Again)
        return
    end
    if #plan.items == 0 then
        last = { outcome = "nothing", notes = #plan.notes }
        local r = { queue = {}, short = {}, spent = 0 }
        for _, n in ipairs(plan.notes) do
            if FirstTime(n) then r.short[#r.short + 1] = ("%s (%s)"):format(n.link, Reason(n.why)) end
        end
        Report(r, "done", true)
        return
    end
    if RS.Mode() == "auto" then
        Begin(plan)
        return
    end
    -- Ask: the question names what would be bought; Purchase buys that plan, checked again at every step
    ClosePrompt()
    local p = { visit = mine, gen = generation, plan = plan }
    prompt = p
    R.Interact.Confirm(PROMPT, RS.QuestionText(plan, lead), function()
        if prompt ~= p then return end
        prompt = nil
        Begin(plan)
    end, {
        accept = "Purchase", cancel = CANCEL or "Cancel",
        valid = function()
            if prompt ~= p or p.visit ~= visit or p.gen ~= generation or not RS.MerchantOpen() or not RS.Enabled() then
                prompt = nil
                return false, "The merchant closed or your restock settings changed, so nothing was bought."
            end
            if InCombat() then return false, "Nothing was bought: combat started." end
            return true
        end,
        onCancel = function()
            if prompt == p then prompt = nil end
            last = { outcome = "cancelled" }
        end,
    })
end

function Ask(mine, lead)
    if mine ~= visit or run then return end
    reviews = reviews + 1
    Visit(mine, lead)
end

-- A moment after the merchant opens: waits while TwichUI's own selling runs (it frees room and brings money in),
-- then plans once.
local function Start(mine)
    if mine ~= visit or not RS.MerchantOpen() or not RS.Enabled() or planned == mine then return end
    local MS = R.MageSell
    if MS and MS.Running and MS.Running() then
        waits = waits + 1
        if waits <= MAX_SELL_WAITS then C_Timer.After(WAIT_STEP, function() Start(mine) end) end
        return
    end
    planned = mine
    Visit(mine)
end

-- Drops the run in progress and the open question, without a word (an option changed, or the feature went off).
local function Cancel()
    generation = generation + 1
    ClosePrompt()
    StopInfoWait()
    if run then Finish(run, "changed") end
end

function Changed()
    Cancel()
    Notify()
end

---------------------------------------------------------------------------
-- Events: only while the feature is on
---------------------------------------------------------------------------
local function OnShow()
    visit = visit + 1
    Cancel()
    merchantOpen = true
    waits, infoTries, reviews = 0, 0, 0
    local mine = visit
    C_Timer.After(SETTLE, function() Start(mine) end)
end

local function OnClosed()
    merchantOpen = false
    generation = generation + 1
    ClosePrompt()
    StopInfoWait()
    if run then Finish(run, "closed") end
end

local function OnCombat()
    ClosePrompt()
    if run then Finish(run, "combat") end
end

-- Safe to call any time, as often as you like: makes the listening match the settings and drops what a change made stale.
function RS.Refresh()
    local on = RS.Enabled()
    Want(active, "MERCHANT_SHOW", OnShow, on)
    Want(active, "MERCHANT_CLOSED", OnClosed, on)
    Want(active, "PLAYER_LEAVING_WORLD", OnClosed, on)
    Want(active, "PLAYER_REGEN_DISABLED", OnCombat, on)
    Cancel()
    if not on then merchantOpen = false end
    Notify()
end

-- A profile change: its own rules and mode from now on; anything planned under the old ones stops.
R.Profiles.OnApply("views", "restock", function() RS.Refresh() end)
R:OnInit(RS.Refresh)

---------------------------------------------------------------------------
-- For the settings window, diagnostics and tests. Counts and codes; no names, no bag places.
---------------------------------------------------------------------------
function RS.Running() return run ~= nil end
function RS.Asking() return prompt ~= nil end
function RS.Last() return last end
