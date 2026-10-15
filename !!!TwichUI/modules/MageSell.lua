-- TwichUI: Mage, sell ordinary food and drink
-- For Mages, off until turned on (Mage options page). When a merchant opens, sells the plain,
-- non-conjured food and drink in the carried bags, so the bags hold conjured refreshments instead.
-- Selling is destructive, so every rule below leaves an item out when in doubt; nothing here is ever
-- "safe to sell" by default.
--
-- What is sold: an item the game files under Food & Drink whose use-spell is the game's plain Food or
-- Drink spell and whose spell text is only the restore sentence (FoodDrink.Inspect, the same reading the
-- Food and Drink buttons use). Buff food, feasts, anything with more to say or that can't be read is
-- left out; so are potions, elixirs, reagents and everything else that isn't Food & Drink.
--
-- What is never sold, in the order it is checked (the codes are what /tui diagnostics counts):
--   excluded                 on the player's never-sell list (item ID, every stack)
--   conjured                 a known Mage-conjured item (FoodDrink.CONJURED, MS.CONJURED_EXTRA), or one whose
--                            tooltip carries the game's own "Conjured Item" text
--   conjured-check-unavailable  the tooltip couldn't be read, or this client doesn't define that text:
--                            an item that can't be shown not to be conjured is kept
--   not-plain-food-or-drink, no-use-spell  buff food, feasts, anything with an extra effect
--   item-data-pending, spell-text-pending  the game hasn't loaded it yet (asked for; looked at again)
--   special-quality          better than Common (Poor or Common only)
--   no-sell-price, high-value  no vendor price, or one far above ordinary food
--   quest-item, quest-check-unavailable  the game calls it a quest item, or can't say
--   category-off             Sell food or Sell drink is off for what it restores (a combined item needs both)
--   locked, bound            locked right now; soulbound (Mage-conjured items report bound)
-- Conjured items: the game exposes no "conjured" flag (nothing in the Forever UI source or API
-- documentation), so protection is layered: the item IDs, the bound flag, the missing sell price (all
-- three are what the Classic-era data and other Forever addons say; none has been seen in this
-- client) and the tooltip's own text. An unfamiliar new rank is kept when any layer catches it, and
-- is sold only if it is unbound, priced, Common, plain food/drink and its tooltip says nothing: the one
-- case no layer can see. See docs/mage-sell.md.
--
-- Handling mode (ui.mageSellMode): "direct" (the default; everything below) or "ellesmere". In "ellesmere" this
-- file never sells: the same classifier (MS.Judge/MS.Scan) picks the items and each item ID is marked as junk
-- through EllesmereUI's Junk Marker (EllesmereJunk.lua); EllesmereUI files and sells it by its own rules. A mark
-- is per item ID for the whole account, so an ID is marked only when every carried stack of it is eligible, and
-- only after the player has confirmed that once (ui.mageSell.euiAck, never shared). Marks are never removed here.
-- Marking is driven by bag changes, not by the merchant, so the junk is in place before a visit.
--
-- Selling: one run per merchant visit, started a moment after MERCHANT_SHOW, through the same
-- classifier the preview uses. Each stack is revalidated at the moment it is sold (feature, class,
-- merchant open, not in combat, item still in that slot with that count, not locked, classification
-- again, price) and sold with C_Container.UseContainerItem, one at a time: the next waits for the game
-- to change that slot (BAG_UPDATE_DELAYED), so a sale is counted only when the bag shows it gone. A
-- slot that changed is skipped, never sold from a stale list. No cursor, no splitting, no purchasing.
-- A run is dropped (never resumed) when the merchant closes, combat starts, the feature or its
-- options change, or another merchant opens. Pending work is never saved.
-- Buyback: the Forever UI shows BUYBACK_ITEMS_PER_PAGE (12) slots, one per stack. A run sells at most
-- that many less 2, so it cannot push its own first sales out; sales by hand or by other addons still can.
-- Saved: the switches (TwichUIDB.modules.mageSell*) and TwichUIDB.ui.mageSell.exclude, { [itemID] = true }.

local R = TwichUI
local FD = R.FoodDrink
local MS = {}
R.MageSell = MS

local SETTLE = 0.3            -- seconds after the merchant opens before the bags are looked at
local STEP_WAIT = 2           -- seconds the game has to show one sale before the run stops
local BUYBACK_FALLBACK = 12   -- BUYBACK_ITEMS_PER_PAGE in the Forever UI source
local BUYBACK_MARGIN = 2      -- slots left alone
local MAX_EXCLUDED = 200
local MAX_CACHE = 128
local HIGH_VALUE = 10000      -- copper for one: 1 gold is a lot for ordinary food and drink (a guess; see docs)
local MAX_QUALITY = 1         -- Poor and Common

-- Conjured items this client's other addons know that FoodDrink.CONJURED (the Classic-era ranks 1 to 6)
-- doesn't list: rank 7 of Conjure Water and Conjure Food (8079, 22895) and Mountain Spring Water
-- (231778). Protection only: never used to offer an item to the buttons. Source: Water Dispenser's
-- Forever data for build 1.60.1.70291, whose own notes say 231778 is unconfirmed. A wrong entry only
-- keeps an item; a missing one is caught by the other layers.
MS.CONJURED_EXTRA = { [8079] = true, [22895] = true, [231778] = true }

-- What a code means, in the words the preview shows.
MS.REASONS = {
    ["ordinary-food"] = "Ordinary food",
    ["ordinary-drink"] = "Ordinary drink",
    ["ordinary-food-and-drink"] = "Ordinary food and drink",
    excluded = "On your never-sell list",
    conjured = "Mage-conjured",
    ["conjured-check-unavailable"] = "Can't tell whether it is conjured",
    ["not-plain-food-or-drink"] = "Has an effect beyond restoring health or mana",
    ["no-use-spell"] = "Not ordinary food or drink",
    ["item-data-pending"] = "Still loading",
    ["spell-text-pending"] = "Still loading",
    ["vocabulary-unavailable"] = "Still loading",
    ["special-quality"] = "Better than ordinary quality",
    ["no-sell-price"] = "Has no sell price",
    ["high-value"] = "Worth more than ordinary food",
    ["quest-item"] = "A quest item",
    ["quest-check-unavailable"] = "Can't tell whether a quest needs it",
    ["category-off"] = "Its kind is switched off",
    locked = "Locked right now",
    bound = "Bound to you",
    stale = "Changed since it was looked at",
    empty = "Nothing there",
}

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Settings. Strict on purpose: only an explicit true switches anything on, and dry run is on unless
-- it was explicitly turned off, so a missing or damaged value can never start selling.
---------------------------------------------------------------------------
local function Switch(key)
    local m = TwichUIDB and TwichUIDB.modules
    return type(m) == "table" and m[key] == true
end

function MS.ForPlayer()
    local _, class = UnitClass("player")
    return Plain(class) == "MAGE"
end
function MS.Enabled() return MS.ForPlayer() and Switch("mageSell") end
function MS.DryRun()
    local m = TwichUIDB and TwichUIDB.modules
    return not (type(m) == "table" and m.mageSellDryRun == false)
end
function MS.SellsFood() return Switch("mageSellFood") end
function MS.SellsDrink() return Switch("mageSellDrink") end

---------------------------------------------------------------------------
-- Handling mode. "direct" sells at merchants; "ellesmere" marks the same items as junk in EllesmereUI. Anything
-- but an explicit "ellesmere" reads as "direct", so a damaged value never starts the other behavior.
---------------------------------------------------------------------------
MS.DEFAULT_MODE = "direct"
MS.MODES = { { "direct", "Sell directly" }, { "ellesmere", "Mark as junk with EllesmereUI" } }

function MS.Mode()
    local ui = TwichUIDB and TwichUIDB.ui
    return (type(ui) == "table" and ui.mageSellMode == "ellesmere") and "ellesmere" or "direct"
end

local function GroupTable(create)
    local ui = TwichUIDB and TwichUIDB.ui
    if create then
        if type(TwichUIDB) ~= "table" then return nil end
        if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
        ui = TwichUIDB.ui
        if type(ui.mageSell) ~= "table" then ui.mageSell = {} end
    end
    return type(ui) == "table" and type(ui.mageSell) == "table" and ui.mageSell or nil
end

-- Whether this player has confirmed, on this computer, that EllesmereUI marks reach every copy of an item and
-- stay until they are unmarked. Never shared or carried by a profile: a setup someone sends can choose the mode
-- but cannot confirm it for you.
function MS.Acknowledged()
    local g = GroupTable(false)
    return g ~= nil and g.euiAck == true
end

function MS.Acknowledge()
    local g = GroupTable(true)
    if not g then return false end
    g.euiAck = true
    return true
end

-- Returns true, or false and why: "invalid", "needs-ack" (choosing EllesmereUI before confirming), "no-settings".
function MS.SetMode(value)
    if value ~= "direct" and value ~= "ellesmere" then return false, "invalid" end
    if value == "ellesmere" and not MS.Acknowledged() then return false, "needs-ack" end
    if type(TwichUIDB) ~= "table" then return false, "no-settings" end
    if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
    TwichUIDB.ui.mageSellMode = value
    MS.Refresh()
    return true
end

-- The feature is on and sells itself / marks in EllesmereUI.
function MS.SellsDirectly() return MS.Enabled() and MS.Mode() == "direct" end
function MS.Marks() return MS.Enabled() and MS.Mode() == "ellesmere" end

-- The most stacks one run sells: the buyback list's size less a margin, so the run's own first sales
-- are still there at its end.
function MS.Limit()
    local capacity = tonumber(_G.BUYBACK_ITEMS_PER_PAGE) or BUYBACK_FALLBACK
    capacity = math.floor(math.min(math.max(capacity, 1), BUYBACK_FALLBACK))
    return math.max(1, capacity - BUYBACK_MARGIN)
end

---------------------------------------------------------------------------
-- The never-sell list. Item IDs only (never names), the same for every stack, saved account-wide.
-- A value is read only when it is exactly true.
---------------------------------------------------------------------------
local function ExcludeTable(create)
    local ui = TwichUIDB and TwichUIDB.ui
    if create then
        if type(TwichUIDB) ~= "table" then return nil end
        if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
        ui = TwichUIDB.ui
        if type(ui.mageSell) ~= "table" then ui.mageSell = {} end
        if type(ui.mageSell.exclude) ~= "table" then ui.mageSell.exclude = {} end
    end
    local group = type(ui) == "table" and type(ui.mageSell) == "table" and ui.mageSell or nil
    return group and type(group.exclude) == "table" and group.exclude or nil
end

local function ValidID(id)
    return type(id) == "number" and id == id and id >= 1 and id <= 2147483647 and math.floor(id) == id
end

function MS.IsExcluded(id)
    local t = ExcludeTable(false)
    return t ~= nil and t[id] == true
end

-- The listed IDs, lowest first.
function MS.Excluded()
    local list, t = {}, ExcludeTable(false)
    for id, on in pairs(t or {}) do
        if on == true and ValidID(id) then list[#list + 1] = id end
    end
    table.sort(list)
    return list
end

-- id: a number, or text holding an item link or an item ID. Returns true, id; or false, a sentence.
function MS.Exclude(id)
    if type(id) == "string" then
        id = tonumber(id:match("item:(%d+)") or id:match("^%s*(%d+)%s*$"))
    end
    if not ValidID(id) then return false, "That isn't an item. Drop an item here, or paste its link or item ID." end
    if MS.IsExcluded(id) then return true, id end
    if #MS.Excluded() >= MAX_EXCLUDED then
        return false, ("The list holds %d items; remove one first."):format(MAX_EXCLUDED)
    end
    local t = ExcludeTable(true)
    if not t then return false, "Your settings aren't available right now." end
    t[id] = true
    MS.ClearCache()
    if MS.OnChange then MS.OnChange() end
    return true, id
end

function MS.Include(id)
    local t = ExcludeTable(false)
    if not (t and t[id] ~= nil) then return false end
    t[id] = nil
    MS.ClearCache()
    if MS.OnChange then MS.OnChange() end
    return true
end

---------------------------------------------------------------------------
-- Looking at one item. What an item is doesn't change in a session, so the verdict on the item itself
-- is remembered by item ID (never what depends on the player's switches or a particular slot).
-- Only final answers are kept: an item the game hasn't loaded is asked about again.
---------------------------------------------------------------------------
local cache, cacheSize = {}, 0

function MS.ClearCache()
    cache, cacheSize = {}, 0
end

local function Remember(id, entry)
    if cacheSize >= MAX_CACHE then MS.ClearCache() end
    cache[id] = entry
    cacheSize = cacheSize + 1
    return entry
end

function MS.KnownConjured(id)
    return FD.CONJURED[id] == true or MS.CONJURED_EXTRA[id] == true
end

-- What the item's tooltip says about it, using the game's own words (ITEM_CONJURED, ITEM_BIND_QUEST,
-- ITEM_STARTS_QUEST), so it holds in any language: "conjured", "quest" or "clear"; nil when it can't be
-- read (no tooltip data, a secret line, or a client that doesn't define "Conjured Item"). Read only.
local function TooltipFacts(bag, slot)
    local marker = _G.ITEM_CONJURED
    if type(marker) ~= "string" or marker == "" then return nil end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return nil end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    local lines = type(data) == "table" and data.lines
    if type(lines) ~= "table" or #lines == 0 then return nil end
    local quest = { _G.ITEM_BIND_QUEST, _G.ITEM_STARTS_QUEST }
    local result = "clear"
    for _, line in ipairs(lines) do
        local text = type(line) == "table" and line.leftText
        if text ~= nil then
            if issecretvalue and issecretvalue(text) then return nil end
            if type(text) == "string" and text ~= "" then
                if text:find(marker, 1, true) then return "conjured" end
                for _, q in ipairs(quest) do
                    if type(q) == "string" and q ~= "" and text:find(q, 1, true) then result = "quest" end
                end
            end
        end
    end
    return result
end

-- The item itself: { ok = true, kinds, amount, unit, name, icon } or { ok = false, why }. nil, true, code
-- while the game is still loading something; nil, false, "not-food-and-drink" for something else.
local function Static(id, names, words, readOnly, bag, slot)
    local hit = cache[id]
    if hit then return hit end
    if not FD.IsFoodAndDrink(id) then return nil, false, "not-food-and-drink" end
    if MS.KnownConjured(id) then return Remember(id, { ok = false, why = "conjured" }) end
    -- Without the game's spell names or its words for health and mana nothing can be told apart, and
    -- a "no" now would be remembered wrongly: wait for them.
    if not (names.food and names.drink and words.health and words.mana) then
        return nil, true, "vocabulary-unavailable"
    end
    local item, pending, why = FD.Inspect(id, names, words, readOnly)
    if not item then
        if pending then return nil, true, why end
        return Remember(id, { ok = false, why = why })
    end
    local entry = { ok = false, kinds = item.kinds, amount = item.amount, unit = item.sellPrice, name = item.name, icon = item.icon }
    if item.quality == nil then
        return nil, true, "item-data-pending"
    elseif item.quality > MAX_QUALITY then
        entry.why = "special-quality"
    elseif type(item.sellPrice) ~= "number" or item.sellPrice <= 0 then
        entry.why = "no-sell-price"
    elseif item.sellPrice > HIGH_VALUE then
        entry.why = "high-value"
    else
        local facts = TooltipFacts(bag, slot)
        if facts == nil then return nil, false, "conjured-check-unavailable" end   -- not kept: asked again next time
        if facts == "conjured" then entry.why = "conjured"
        elseif facts == "quest" then entry.why = "quest-item"
        else entry.ok = true end
    end
    return Remember(id, entry)
end

-- One bag slot. nil for an empty slot and for anything that isn't Food & Drink (not this feature's
-- business, and never listed). Otherwise { id, bag, slot, count, name, icon, eligible, why, reason, kinds,
-- amount, unit, value, pending }: eligible items carry `reason` (what makes them ordinary), the others `why`.
-- readOnly: ask the game to load nothing.
function MS.Judge(bag, slot, names, words, readOnly)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local id = info and Plain(info.itemID)
    if type(id) ~= "number" or not FD.IsFoodAndDrink(id) then return nil end
    local count = Plain(info.stackCount)
    local v = { id = id, bag = bag, slot = slot, count = type(count) == "number" and count or 0,
        icon = Plain(info.iconFileID), name = Plain(info.itemName), quality = Plain(info.quality), eligible = false }
    local function Skip(why) v.why = why; return v end

    if MS.IsExcluded(id) then return Skip("excluded") end
    local static, pending, why = Static(id, names, words, readOnly, bag, slot)
    if not static then
        v.pending = pending and true or nil
        return Skip(why)
    end
    v.name, v.icon = static.name or v.name, static.icon or v.icon
    if not static.ok then return Skip(static.why) end
    v.kinds, v.amount, v.unit = static.kinds, static.amount, static.unit
    if (static.kinds.food and not MS.SellsFood()) or (static.kinds.drink and not MS.SellsDrink()) then
        return Skip("category-off")
    end
    -- the slot itself; "not exactly false" counts against selling, so an unreadable field keeps the item
    if v.count < 1 then return Skip("empty") end
    if info.isLocked ~= false then return Skip("locked") end
    if info.isBound ~= false then return Skip("bound") end
    if info.hasNoValue ~= false then return Skip("no-sell-price") end
    if not (C_Container.GetContainerItemQuestInfo) then return Skip("quest-check-unavailable") end
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    if type(quest) ~= "table" then return Skip("quest-check-unavailable") end
    if quest.isQuestItem ~= false or quest.questID ~= nil then return Skip("quest-item") end

    v.eligible = true
    v.value = static.unit * v.count
    v.reason = (static.kinds.food and static.kinds.drink) and "ordinary-food-and-drink"
        or (static.kinds.food and "ordinary-food" or "ordinary-drink")
    return v
end

local function LastBag()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

-- Every Food & Drink stack in the carried bags (never the bank, mail or anything else), judged:
-- { eligible = { v... } in bag order, kept = { v... }, counts = { [code] = n }, pending = n, stacks, items,
-- value (copper, from sell prices) }. Reads only; readOnly also asks the game to load nothing.
function MS.Scan(readOnly)
    local names, words = FD.Vocabulary()
    local out = { eligible = {}, kept = {}, counts = {}, pending = 0, stacks = 0, items = 0, value = 0 }
    for bag = 0, LastBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local v = MS.Judge(bag, slot, names, words, readOnly)
            if v then
                if v.eligible then
                    out.eligible[#out.eligible + 1] = v
                    out.stacks, out.items, out.value = out.stacks + 1, out.items + v.count, out.value + v.value
                else
                    out.kept[#out.kept + 1] = v
                    out.counts[v.why] = (out.counts[v.why] or 0) + 1
                    if v.pending then out.pending = out.pending + 1 end
                end
            end
        end
    end
    return out
end

-- "1g 20s 5c" from copper; "nothing" for none.
function MS.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper <= 0 then return "nothing" end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- A run
---------------------------------------------------------------------------
local run                  -- the batch in progress, or nil
local generation = 0       -- bumped to drop a run and every timer waiting for it
local visit = 0            -- which merchant opening this is
local autoVisit = 0        -- the visit an automatic run was already made for
local merchantOpen = false
local blocked = false      -- the game refused an automatic sale this session
local last                 -- the last run's outcome, counts only
local stats = { runs = 0, dryRuns = 0, stacks = 0, items = 0, value = 0, limited = 0, stale = 0,
    closed = 0, combat = 0, unconfirmed = 0, blocked = 0, cancelled = 0 }
local active = {}          -- [event] = handler, while registered

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

-- A merchant is open: opened since this feature began listening, and Blizzard's window (when there is
-- one) is still up.
function MS.MerchantOpen()
    if not merchantOpen then return false end
    local frame = _G.MerchantFrame
    if type(frame) == "table" and frame.IsShown and not frame:IsShown() then return false end
    return true
end

local function Say(fmt, ...) R.Print(fmt, ...) end

local OUTCOME_TEXT = {
    closed = "the merchant closed",
    combat = "combat started",
    unconfirmed = "the game did not show the last sale, so nothing more was tried",
    blocked = "the game blocked the sale (nothing more was tried)",
    changed = "an option changed",
    ["cannot-sell"] = "selling wasn't possible",
}

-- One line, once, in your own chat. Nothing is said when there was nothing to do.
local function Report(r, outcome)
    local what = ("%d %s (%d items)"):format(r.stacks, r.stacks == 1 and "stack" or "stacks", r.items)
    if r.dry then
        local n = r.total - r.limited
        if n == 0 then return end
        local line = ("Dry run: would sell %d %s of ordinary food and drink (%d items, about %s). Nothing was sold."):format(
            n, n == 1 and "stack" or "stacks", r.wouldItems, MS.Money(r.wouldValue))
        if r.limited > 0 then line = line .. (" %d more are over the per-visit limit of %d."):format(r.limited, r.limit) end
        Say("%s Turn off Dry run in the Mage options to sell.", line)
        return
    end
    if r.stacks == 0 and not OUTCOME_TEXT[outcome] and r.limited == 0 then return end
    local line
    if r.stacks > 0 then
        line = ("Sold %s of ordinary food and drink for about %s (from their sell prices)."):format(what, MS.Money(r.value))
    else
        line = "Sold nothing."
    end
    if OUTCOME_TEXT[outcome] then line = line .. " Stopped: " .. OUTCOME_TEXT[outcome] .. "." end
    if r.stale > 0 then line = line .. (" %d changed in your bags and %s skipped."):format(r.stale, r.stale == 1 and "was" or "were") end
    if r.limited > 0 then
        line = line .. (" %d more %s eligible: a visit sells at most %d stacks so your buyback list keeps this visit's sales. Sell more with /tui sell."):format(
            r.limited, r.limited == 1 and "is" or "are", r.limit)
    end
    if r.stacks > 0 then line = line .. " They can be bought back from the merchant's Buyback tab until it fills." end
    Say("%s", line)
end

local function Finish(r, outcome)
    if r ~= run then return end
    run = nil
    generation = generation + 1
    Want("BAG_UPDATE_DELAYED", nil, false)
    Want("ADDON_ACTION_BLOCKED", nil, false)
    Want("ADDON_ACTION_FORBIDDEN", nil, false)
    stats.runs = stats.runs + 1
    if r.dry then stats.dryRuns = stats.dryRuns + 1 end
    stats.stacks, stats.items, stats.value = stats.stacks + r.stacks, stats.items + r.items, stats.value + r.value
    stats.stale = stats.stale + r.stale
    if r.limited > 0 then stats.limited = stats.limited + 1 end
    local key = outcome == "changed" and "cancelled" or outcome
    if stats[key] then stats[key] = stats[key] + 1 end
    last = { outcome = outcome, dry = r.dry, manual = r.manual, stacks = r.stacks, items = r.items, value = r.value,
        eligible = r.total, limited = r.limited, stale = r.stale, kept = r.kept }
    if outcome == "changed" then
        R.Life.Note("cancelled-stale-mage-sell")
        return   -- the player just changed something; no summary on top of it
    end
    Report(r, outcome)
    if MS.OnChange then MS.OnChange() end
end

-- Is it still right to sell, from the settings and the world as they are now? Returns true, or false
-- and the outcome code.
local function Valid(r)
    if r.gen ~= generation then return false, "changed" end
    if not MS.SellsDirectly() then return false, "changed" end
    if r.visit ~= visit or not MS.MerchantOpen() then return false, "closed" end
    if InCombat() then return false, "combat" end
    if not r.dry and MS.DryRun() then return false, "changed" end
    return true
end

local Step

local function Verify(r)
    local w = r.waiting
    local info = C_Container.GetContainerItemInfo(w.bag, w.slot)
    local id = info and Plain(info.itemID)
    local left = (id == w.id) and (Plain(info.stackCount) or w.count) or 0
    if left >= w.count then return false end            -- the game hasn't changed the slot yet
    local sold = w.count - left
    r.stacks, r.items, r.value = r.stacks + 1, r.items + sold, r.value + w.unit * sold
    r.waiting = nil
    return true
end

local function OnBags()
    local r = run
    if not (r and r.waiting) then return end
    if Verify(r) then Step(r) end
end

local function OnBlocked(addon)
    if Plain(addon) ~= R.ADDON or not (run and run.waiting) then return end
    blocked = true
    Finish(run, "blocked")
end

local function Timeout(r, token)
    if r ~= run or not r.waiting or r.waiting.token ~= token or r.gen ~= generation then return end
    if Verify(r) then Step(r) return end
    Finish(r, "unconfirmed")
end

-- Sells the next stack that is still what it was when the bags were looked at, or ends the run.
function Step(r)
    if r ~= run then return end
    local ok, why = Valid(r)
    if not ok then Finish(r, why) return end
    local names, words = FD.Vocabulary()
    while true do
        r.index = r.index + 1
        local e = r.queue[r.index]
        if not e then Finish(r, "done") return end
        -- again, from the bag as it is now: the same item, the same count, still eligible
        local v = MS.Judge(e.bag, e.slot, names, words, true)
        if v and v.eligible and v.id == e.id and v.count == e.count then
            r.waiting = { bag = e.bag, slot = e.slot, id = e.id, count = e.count, unit = e.unit, token = r.index }
            Want("BAG_UPDATE_DELAYED", OnBags, true)
            Want("ADDON_ACTION_BLOCKED", OnBlocked, true)
            Want("ADDON_ACTION_FORBIDDEN", OnBlocked, true)
            local token = r.index
            C_Timer.After(STEP_WAIT, function() Timeout(r, token) end)
            local called, err = pcall(C_Container.UseContainerItem, e.bag, e.slot)
            if not called then
                r.waiting = nil
                blocked = true
                if R.Diag then R.Diag.Error("mage sell", err) end
                Finish(r, "blocked")
            end
            return
        end
        r.stale = r.stale + 1
    end
end

-- Looks at the bags and, unless it is a dry run, starts selling. Returns true, or false and why.
-- manual: asked for by the player's click (the automatic run is once per merchant visit).
function MS.Begin(manual)
    if not MS.Enabled() then return false, "off" end
    if MS.Mode() ~= "direct" then return false, "marking-mode" end   -- EllesmereUI sells in the other mode
    if run then return false, "busy" end
    if not R.Life.InWorld() then return false, "not-in-world" end
    if not MS.MerchantOpen() then return false, "no-merchant" end
    if InCombat() then return false, "combat" end
    if not manual then
        if autoVisit == visit then return false, "already-this-visit" end
        if blocked then return false, "blocked" end
        autoVisit = visit
    end
    local scan = MS.Scan(false)
    local limit = MS.Limit()
    local r = { gen = generation + 1, visit = visit, manual = manual and true or false, dry = MS.DryRun(),
        queue = {}, index = 0, stacks = 0, items = 0, value = 0, stale = 0, limit = limit,
        total = #scan.eligible, limited = 0, kept = #scan.kept, wouldItems = 0, wouldValue = 0 }
    generation = r.gen
    for i, v in ipairs(scan.eligible) do
        if i <= limit then
            r.queue[#r.queue + 1] = { bag = v.bag, slot = v.slot, id = v.id, count = v.count, unit = v.unit }
            r.wouldItems, r.wouldValue = r.wouldItems + v.count, r.wouldValue + v.value
        end
    end
    r.limited = math.max(0, #scan.eligible - limit)
    run = r
    if r.dry or #r.queue == 0 then
        Finish(r, "done")
        return true
    end
    Step(r)
    return true
end

-- Ends a run in progress without a word (the options changed or the feature went off).
local function Cancel()
    generation = generation + 1
    if run then Finish(run, "changed") end
end

---------------------------------------------------------------------------
-- Marking (mode "ellesmere"). Same eligibility as a sale (MS.Scan), then one EllesmereJunk.Mark per item ID.
-- Event-driven: a bag change asks for a look, bursts are folded into one (BAG_UPDATE_DELAYED is already the end
-- of a burst; a short timer folds the rest), and nothing runs on a timer of its own. A look that finds nothing
-- new costs one pass over the bags and writes nothing, so EllesmereUI's own bag refresh (which this asks for
-- only after it actually marked something) cannot start a cycle.
---------------------------------------------------------------------------
local EJ = R.EllesmereJunk
local MARK_DELAY = 0.5         -- seconds a bag change waits, so a burst of changes is one look
local MAX_ATTEMPTS = 3         -- times one ID's mark was not kept by EllesmereUI before it is left alone this session
local MAX_INFO_STALLS = 3      -- looks in a row that found the same items still loading before waiting for a bag change
local markActive = {}          -- [event] = handler, while registered for marking
local markGen = 0              -- bumped to drop the look a timer is waiting for
local markQueued = false       -- a look is already waiting
local markBusy = false         -- inside a look: nothing asks for another look from within it
local markDeferred = false     -- a look was held back (combat, loading screen) and runs when that ends
local markAttempts = {}        -- [itemID] = times EllesmereUI did not keep a mark this session
local markedByUs = {}          -- [itemID] = true for what this session marked: if it stops being junk, the player took it off
local infoStalls, lastPending = 0, nil
local markStats = { looks = 0, marked = 0, already = 0, filed = 0, failed = 0, mixed = 0, stuck = 0, deferred = 0, stale = 0, dry = 0,
    released = 0 }
local markLast                 -- the last look's outcome, counts only

local function WantMark(event, handler, wanted)
    if wanted and not markActive[event] then
        markActive[event] = handler
        R:On(event, handler)
    elseif not wanted and markActive[event] then
        R:Off(event, markActive[event])
        markActive[event] = nil
    end
end

local RequestMark, OnMarkInfo

-- The items a look would mark: { { v, ... } one per item ID, in bag order; mixed = n; pending = n }.
-- An ID is offered only when every carried stack of it is eligible, because the mark is for the ID.
local function Candidates(readOnly)
    local scan = MS.Scan(readOnly)
    local kept, seen, list, mixed = {}, {}, {}, 0
    for _, v in ipairs(scan.kept) do kept[v.id] = true end
    for _, v in ipairs(scan.eligible) do
        if not seen[v.id] then
            seen[v.id] = true
            if kept[v.id] then mixed = mixed + 1 else list[#list + 1] = v end
        end
    end
    return list, mixed, scan.pending
end

local function RunMark(gen)
    markQueued = false
    if gen ~= markGen or not MS.Marks() then return end
    if InCombat() then markDeferred = true; markStats.deferred = markStats.deferred + 1; return end
    if not R.Life.InWorld() then markDeferred = true; return end
    if not MS.Acknowledged() or not EJ.Ready() then return end
    markDeferred = false
    markBusy = true
    local ok, err = pcall(function()
        local list, mixed, pending = Candidates(false)
        local dry = MS.DryRun()
        local out = { marked = 0, already = 0, filed = 0, failed = 0, mixed = mixed, stuck = 0, stale = 0, would = 0, released = 0, dry = dry }
        local names, words = FD.Vocabulary()
        for _, v in ipairs(list) do
            if dry then
                local peek = EJ.Peek(v.id, v.quality)
                if peek == "markable" then out.would = out.would + 1
                elseif peek == "already" then out.already = out.already + 1
                elseif peek == "filed-elsewhere" then out.filed = out.filed + 1 end
            elseif markedByUs[v.id] then
                -- marked here earlier: still junk is nothing to do; not junk now means the player unmarked it, and
                -- that is theirs to decide (until a reload it is not marked again; the never-sell list is the
                -- lasting way to keep an item out)
                local peek = EJ.Peek(v.id, v.quality)
                if peek == "markable" then out.released = out.released + 1
                elseif peek == "already" then out.already = out.already + 1 end
            elseif (markAttempts[v.id] or 0) >= MAX_ATTEMPTS then
                out.stuck = out.stuck + 1
            else
                -- the slot again, as it is now: the same item, still eligible, before anything is asked of EllesmereUI
                local again = MS.Judge(v.bag, v.slot, names, words, true)
                if again and again.eligible and again.id == v.id then
                    local result = EJ.Mark(v.id, again.quality)
                    if result == "failed" then markAttempts[v.id] = (markAttempts[v.id] or 0) + 1 end
                    if result == "marked" then
                        out.marked = out.marked + 1
                        markedByUs[v.id] = true
                    elseif result == "already" then out.already = out.already + 1
                    elseif result == "filed-elsewhere" then out.filed = out.filed + 1
                    else out.failed = out.failed + 1 end
                else
                    out.stale = out.stale + 1
                end
            end
        end
        if out.marked > 0 then EJ.Repaint() end
        -- items still loading are asked about again when the game says they arrived, a few times at most
        if pending > 0 then
            infoStalls = (pending == lastPending) and (infoStalls + 1) or 0
            lastPending = pending
        else
            infoStalls, lastPending = 0, nil
        end
        local waiting = pending > 0 and infoStalls < MAX_INFO_STALLS
        WantMark("GET_ITEM_INFO_RECEIVED", OnMarkInfo, waiting)
        WantMark("SPELL_TEXT_UPDATE", OnMarkInfo, waiting)
        out.pending = pending
        markLast = out
        markStats.looks = markStats.looks + 1
        for _, k in ipairs({ "marked", "already", "filed", "failed", "mixed", "stuck", "stale", "released" }) do
            markStats[k] = markStats[k] + out[k]
        end
        markStats.dry = markStats.dry + out.would
    end)
    markBusy = false
    if not ok and R.Diag then R.Diag.Error("mage sell mark", err) end
    if MS.OnChange then MS.OnChange() end
end

-- Asks for a look at the bags soon. Folds into one that is already waiting.
function RequestMark()
    if markBusy or markQueued or not MS.Marks() then return end
    markQueued = true
    local gen = markGen
    C_Timer.After(MARK_DELAY, function() RunMark(gen) end)
end

local function OnMarkBags() infoStalls = 0; RequestMark() end
function OnMarkInfo() RequestMark() end

local function OnMarkResume()
    if markDeferred then RequestMark() end
end

local function OnMarkAddon(name)
    name = Plain(name)
    if type(name) == "string" and name:find("^EllesmereUI") then RequestMark() end
end

local function OnMarkLeaving()
    markGen = markGen + 1
    markQueued = false
    markDeferred = true          -- looked at again when the next world is entered
end

-- Start or stop listening to match the settings. Safe to call any time.
local function RefreshMarking()
    markGen = markGen + 1        -- a look waiting under older settings does nothing
    markQueued = false
    local on = MS.Marks()
    WantMark("BAG_UPDATE_DELAYED", OnMarkBags, on)
    WantMark("PLAYER_REGEN_ENABLED", OnMarkResume, on)
    WantMark("PLAYER_ENTERING_WORLD", OnMarkResume, on)
    WantMark("PLAYER_LEAVING_WORLD", OnMarkLeaving, on)
    WantMark("ADDON_LOADED", OnMarkAddon, on)
    if not on then
        WantMark("GET_ITEM_INFO_RECEIVED", OnMarkInfo, false)
        WantMark("SPELL_TEXT_UPDATE", OnMarkInfo, false)
        markDeferred, infoStalls, lastPending = false, 0, nil
        markedByUs, markAttempts = {}, {}
        return
    end
    if R.Life.InWorld() then RequestMark() else markDeferred = true end
end

-- What marking is doing, for the settings page, the window and diagnostics:
-- code, one sentence. Codes: off, direct, needs-ack, dry-run, active, or EllesmereJunk's reason.
function MS.MarkState()
    if not MS.ForPlayer() then return "off", "This is for Mages." end
    if not MS.Enabled() then return "off", "Off." end
    if MS.Mode() ~= "ellesmere" then return "direct", "Selling directly at merchants." end
    if not MS.Acknowledged() then
        return "needs-ack", "Waiting for your confirmation: choose this mode in the Mage options to read what it does and confirm."
    end
    local status = EJ.Status()
    if status ~= "ready" then
        return status, EJ.REASONS[status] .. " Nothing is marked and nothing is sold by TwichUI until it is."
    end
    if MS.DryRun() then return "dry-run", "Dry run: eligible items are only counted. Nothing is marked." end
    return "active", "Eligible items are marked as junk in EllesmereUI's bags as they arrive."
end

-- One line on how EllesmereUI will sell what is marked ("auto", "button" or "unknown").
function MS.MarkSelling() return EJ.Selling() end
function MS.MarkLast() return markLast end

-- A merchant opened in marking mode with Dry run on: say once what would be marked. Reads only.
local function ReportDryMark(mine)
    if mine ~= visit or not MS.Marks() or not MS.DryRun() or autoVisit == visit then return end
    if not MS.Acknowledged() or not EJ.Ready() or InCombat() then return end
    autoVisit = visit
    local list = Candidates(true)
    local would = 0
    for _, v in ipairs(list) do
        if EJ.Peek(v.id, v.quality) == "markable" then would = would + 1 end
    end
    if would == 0 then return end
    Say("Dry run: would mark %d kind%s of ordinary food and drink as junk in EllesmereUI (every copy, from now on). Nothing was marked. Turn off Dry run in the Mage options to mark.",
        would, would == 1 and "" or "s")
end

---------------------------------------------------------------------------
-- Events: only while the feature is on
---------------------------------------------------------------------------
local function OnShow()
    visit = visit + 1
    generation = generation + 1
    merchantOpen = true
    if run then Finish(run, "closed") end
    local mine = visit
    C_Timer.After(SETTLE, function()
        if mine ~= visit or not merchantOpen then return end
        if MS.Mode() == "ellesmere" then ReportDryMark(mine) else MS.Begin(false) end
    end)
end

local function OnClosed()
    merchantOpen = false
    generation = generation + 1
    if run then Finish(run, "closed") end
end

local function OnCombat()
    if run then Finish(run, "combat") end
end

local function OnLeaving()
    merchantOpen = false
    generation = generation + 1
    if run then Finish(run, "closed") end
end

-- Safe to call any time, as often as you like: it makes the listening match the settings and drops a run
-- the options have changed under.
function MS.Refresh()
    local on = MS.Enabled()
    local direct = on and MS.Mode() == "direct"
    -- Marking mode listens at a merchant only to say what a dry run would mark; it never sells there.
    local atMerchant = direct or (on and MS.Mode() == "ellesmere" and MS.DryRun())
    Want("MERCHANT_SHOW", OnShow, atMerchant)
    Want("MERCHANT_CLOSED", OnClosed, atMerchant)
    Want("PLAYER_REGEN_DISABLED", OnCombat, direct)
    Want("PLAYER_LEAVING_WORLD", OnLeaving, atMerchant)
    if run then Cancel() end
    if not atMerchant then merchantOpen = false end
    if not on then MS.ClearCache() end
    RefreshMarking()
    if MS.OnChange then MS.OnChange() end
end

-- A profile change: a sale in progress stops (its settings may differ), whatever changed.
R.Profiles.OnApply("views", "mage-sell", function() MS.Refresh() end)

---------------------------------------------------------------------------
-- For /tui diagnostics (diag/MageSell.lua) and the window. Counts and codes; no names, no bag places.
---------------------------------------------------------------------------
function MS.Last() return last end
function MS.Running() return run ~= nil end

function MS.Snapshot()
    local out = {
        mage = MS.ForPlayer(), switchOn = Switch("mageSell"), enabled = MS.Enabled(), food = MS.SellsFood(),
        drink = MS.SellsDrink(), dryRun = MS.DryRun(), merchantOpen = MS.MerchantOpen(), visit = visit,
        blocked = blocked, limit = MS.Limit(), excluded = #MS.Excluded(), cache = cacheSize, last = last,
        conjuredKnown = 0, stats = {},
        mode = MS.Mode(), acknowledged = MS.Acknowledged(), marks = {}, markLast = markLast,
        markers = {
            conjuredText = type(_G.ITEM_CONJURED) == "string" and _G.ITEM_CONJURED ~= "",
            questText = type(_G.ITEM_BIND_QUEST) == "string" and _G.ITEM_BIND_QUEST ~= "",
            tooltipApi = (C_TooltipInfo and C_TooltipInfo.GetBagItem) ~= nil,
            questApi = (C_Container and C_Container.GetContainerItemQuestInfo) ~= nil,
            buybackCapacity = tonumber(_G.BUYBACK_ITEMS_PER_PAGE),
        },
    }
    for k, v in pairs(stats) do out.stats[k] = v end
    for k, v in pairs(markStats) do out.marks[k] = v end
    out.markState, out.markText = MS.MarkState()
    out.selling = EJ.Selling()
    out.bridge = EJ.Status()
    for _ in pairs(FD.CONJURED) do out.conjuredKnown = out.conjuredKnown + 1 end
    for _ in pairs(MS.CONJURED_EXTRA) do out.conjuredKnown = out.conjuredKnown + 1 end
    local events = {}
    for event in pairs(active) do events[#events + 1] = event end
    for event in pairs(markActive) do events[#events + 1] = event .. " (marking)" end
    table.sort(events)
    out.events = events
    if run then
        out.running = { index = run.index, total = run.total, limit = run.limit, dry = run.dry,
            waiting = run.waiting ~= nil, manual = run.manual }
    end
    if out.enabled and C_Container and C_Item and C_Spell then
        local ok, scan = pcall(MS.Scan, true)
        if ok then
            out.scan = { eligible = scan.stacks, items = scan.items, value = scan.value, kept = #scan.kept,
                pending = scan.pending, counts = scan.counts }
        else
            out.scanFailed = true
        end
    end
    return out
end

R:OnInit(MS.Refresh)
R:On("PLAYER_LOGIN", MS.Refresh)   -- the class is certain by then
