-- TwichUI: Reminders, what you carry and what you wear down
-- Three condition kinds (Conditions.lua says what a provider is) and their sources (State.lua says what a source is):
--
-- itemCount  how many of one item you carry: `item` (an item ID, never a name), `compare` ("below" | "atLeast") and
--            `count`. The count is the game's own, C_Item.GetItemCount(item) with the bank left out: what you carry in
--            your bags. The bank, the mail and other characters are never counted (they can't be seen from here, and an
--            unseen bank isn't empty), and nothing is added up twice. Read again after BAG_UPDATE_DELAYED. A count the
--            game doesn't give plainly is unknown, never zero.
-- bagSpace   free general-purpose bag slots: `compare` and `count`. The backpack and the equipped bags, 0 to
--            NUM_BAG_SLOTS (the reagent bag is past them, Blizzard_FrameXMLBase/Constants.lua), and of those only the
--            bags of the general family (C_Container.GetContainerNumFreeSlots answers the family; 0 is any item): free
--            room in a quiver, a soul bag or a herb bag can't take just anything, so it doesn't count. A bag that can't
--            be read makes it unknown.
-- durability `what` "broken" (an equipped item is at zero) or "below" (an equipped item is below `percent` of its
--            durability). Item by item from GetInventoryItemDurability(slot) (the character sheet's own reading): never
--            an average, which could hide one broken item behind the rest. Items without durability (rings, a cloak
--            that has none, an empty slot) are left out; with nothing left, nothing needs repair (no match). Read on
--            UPDATE_INVENTORY_DURABILITY and when equipment changes.
--
-- Thresholds: "below" is strictly less than, "at least" includes the number itself (Conditions.lua's C.Compare).
-- None of these ever moves, uses, buys, sells or repairs anything.

local R = TwichUI
local C = R.ReminderConditions
local ST = R.ReminderState

local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN
local Yes = C.Yes
local Plain, Number = ST.Plain, ST.Number

local SU = {}
R.ReminderSupplies = SU
SU.COUNTS = { 1, 5, 10, 20, 50, 100 }
SU.COUNT_MAX = 99999
SU.FREE = { 1, 2, 5, 10, 20 }
SU.FREE_MAX = 200
SU.PERCENTS = { 10, 20, 30, 50, 75 }

local function CompareWords(compare) return compare == "below" and "fewer than" or "at least" end

---------------------------------------------------------------------------
-- How many of an item you carry
---------------------------------------------------------------------------
local function CountOf(cond, obs)
    local t = obs and obs.itemCount
    return type(t) == "table" and cond.item and t[cond.item] or nil
end

C.Register({
    type = "itemCount", label = "How many of an item you carry",
    Supported = function() return C_Item ~= nil and C_Item.GetItemCount ~= nil end,
    unsupported = "this game client doesn't say how many of an item you carry.",
    New = function() return { type = "itemCount", compare = "below", count = 5 } end,

    Check = function(raw)
        if not C.ValidCompare(raw.compare) then return nil, "it compares a count in a way this version of TwichUI doesn't know." end
        local clean = { type = "itemCount", compare = raw.compare }
        clean.count = C.Whole(raw.count, 1, SU.COUNT_MAX)
        if raw.item ~= nil then
            if not R.Reminders.ValidItem(raw.item) then return nil, "it names an item by something that isn't an item ID." end
            clean.item = raw.item
        end
        if not clean.count then return clean, ("choose the count it compares with (1 to %d)."):format(SU.COUNT_MAX) end
        if not clean.item then return clean, "choose the item it counts (its ID or link)." end
        return clean
    end,

    Needs = function(cond, add) if cond.item then add("itemCount:" .. cond.item) end end,

    Evaluate = function(cond, obs)
        local n = CountOf(cond, obs)
        if n == nil then return UNKNOWN, "The game hasn't said how many you carry yet." end
        return Yes(C.Compare(n, cond.compare, cond.count))
    end,

    Summary = function(cond)
        return ("You carry %s %d %s"):format(CompareWords(cond.compare), cond.count or 0, C.ItemWords(cond.item))
    end,

    Observed = function(cond, obs)
        local n = CountOf(cond, obs)
        if n == nil then return "Not read yet" end
        return ("%d carried"):format(n)
    end,

    Scenarios = function(cond)
        local n = cond.count or 5
        local list = {}
        local function Put(key, label, value)
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                obs.itemCount = obs.itemCount or {}
                obs.itemCount[cond.item or 0] = value
            end }
        end
        local fewer, exact, more = { "fewer", ("%d carried"):format(math.max(0, n - 1)), math.max(0, n - 1) },
            { "exact", ("%d carried"):format(n), n }, { "more", ("%d carried"):format(n * 2), n * 2 }
        if cond.compare == "below" then
            Put(fewer[1], fewer[2], fewer[3]); Put("none", "None carried", 0); Put(exact[1], exact[2], exact[3])
        else
            Put(exact[1], exact[2], exact[3]); Put(more[1], more[2], more[3]); Put(fewer[1], fewer[2], fewer[3])
        end
        Put("unread", "Not read yet", nil)
        return list
    end,
})

ST.Source("itemCount", {
    events = { BAG_UPDATE_DELAYED = true },
    Read = function(arg, into)
        local id = tonumber(arg)
        if not id then return false end
        ST.Counted()
        local v
        if C_Item and C_Item.GetItemCount then
            local ok, n = pcall(C_Item.GetItemCount, id, false)
            v = ok and Number(n) or nil
        end
        if v and v < 0 then v = nil end
        into.itemCount = into.itemCount or {}
        if into.itemCount[id] == v then return false end
        into.itemCount[id] = v
        return true
    end,
    Forget = function(arg, into)
        if into.itemCount then into.itemCount[tonumber(arg) or 0] = nil end
    end,
})

---------------------------------------------------------------------------
-- Free bag slots
---------------------------------------------------------------------------
C.Register({
    type = "bagSpace", label = "Free bag slots",
    Supported = function() return C_Container ~= nil and C_Container.GetContainerNumFreeSlots ~= nil end,
    unsupported = "this game client doesn't say how much room your bags have.",
    New = function() return { type = "bagSpace", compare = "below", count = 5 } end,

    Check = function(raw)
        if not C.ValidCompare(raw.compare) then return nil, "it compares free slots in a way this version of TwichUI doesn't know." end
        local clean = { type = "bagSpace", compare = raw.compare, count = C.Whole(raw.count, 1, SU.FREE_MAX) }
        if not clean.count then return clean, ("choose the number of free slots it compares with (1 to %d)."):format(SU.FREE_MAX) end
        return clean
    end,

    Needs = function(_, add) add("bagFree") end,

    Evaluate = function(cond, obs)
        local n = obs and obs.bagFree
        if n == nil then return UNKNOWN, "The game hasn't said how much room is in your bags yet." end
        return Yes(C.Compare(n, cond.compare, cond.count))
    end,

    Summary = function(cond)
        if cond.compare == "below" and cond.count == 1 then return "Your bags are full" end
        return ("You have %s %d free bag slot%s"):format(CompareWords(cond.compare), cond.count or 0, cond.count == 1 and "" or "s")
    end,

    Observed = function(_, obs)
        local n = obs and obs.bagFree
        if n == nil then return "Not read yet" end
        return ("%d free general slot%s"):format(n, n == 1 and "" or "s")
    end,

    Subject = function() return "bagFree", "Free bag slots" end,

    -- the same choices whatever the threshold (conditions that share this input see one consistent bag)
    Scenarios = function()
        local list = {}
        for _, n in ipairs({ 0, 1, 3, 8, 20 }) do
            list[#list + 1] = { key = "free" .. n, label = n == 0 and "Bags full" or ("%d free slots"):format(n), Apply = function(obs) obs.bagFree = n end }
        end
        list[#list + 1] = { key = "unread", label = "Not read yet", Apply = function(obs) obs.bagFree = nil end }
        return list
    end,
})

-- The general-family bags only; unknown when any of them can't be read.
local function ReadFree()
    if not (C_Container and C_Container.GetContainerNumFreeSlots and C_Container.GetContainerNumSlots) then return nil end
    local last = NUM_BAG_SLOTS or 4
    local free = 0
    for bag = 0, last do
        local slots = Number(C_Container.GetContainerNumSlots(bag))
        if slots == nil then return nil end
        if slots > 0 then
            local n, family = C_Container.GetContainerNumFreeSlots(bag)
            n, family = Number(n), Number(family)
            if n == nil then return nil end
            if (family or 0) == 0 then free = free + n end
        end
    end
    return free
end

ST.Source("bagFree", {
    events = { BAG_UPDATE_DELAYED = true },
    Read = function(_, into)
        ST.Counted()
        return ST.Set(into, "bagFree", ReadFree())
    end,
})

---------------------------------------------------------------------------
-- Durability
---------------------------------------------------------------------------
-- key (stored), the editor's label, a tooltip
SU.DURABILITY_CHOICES = {
    { "broken", "Something is broken", "An equipped item's durability is at zero: it gives none of its stats until it is repaired." },
    { "below", "Something is worn", "An equipped item is below the share of its durability you choose. Each item is judged on its own, never an average." },
}
local DURABILITY = {}
for _, c in ipairs(SU.DURABILITY_CHOICES) do DURABILITY[c[1]] = c end
function SU.DurabilityChoice(key) return DURABILITY[key] end

-- Whether any counted item is below pct percent, from obs.durability.items = { { cur, max }, ... }.
local function AnyBelow(d, pct)
    for _, it in ipairs(d.items) do
        if it[1] * 100 < pct * it[2] then return true end
    end
    return false
end

C.Register({
    type = "durability", label = "Equipment durability",
    Supported = function() return rawget(_G, "GetInventoryItemDurability") ~= nil end,
    unsupported = "this game client doesn't say how worn your equipment is.",
    New = function() return { type = "durability", what = "below", percent = 20 } end,

    Check = function(raw)
        if not DURABILITY[raw.what] then return nil, "it asks about durability in a way this version of TwichUI doesn't know." end
        local clean = { type = "durability", what = raw.what }
        if raw.what == "below" then
            clean.percent = C.Whole(raw.percent, 1, 100)
            if not clean.percent then return clean, "choose the share of durability it compares with (1 to 100 percent)." end
        end
        return clean
    end,

    Needs = function(_, add) add("durability") end,

    Evaluate = function(cond, obs)
        local d = obs and obs.durability
        if type(d) ~= "table" then return UNKNOWN, "The game hasn't said how worn your equipment is yet." end
        if cond.what == "broken" then return Yes(d.broken == true) end
        return Yes(AnyBelow(d, cond.percent))
    end,

    Summary = function(cond)
        if cond.what == "broken" then return "An equipped item is broken" end
        return ("An equipped item is below %d%% durability"):format(cond.percent or 0)
    end,

    Observed = function(_, obs)
        local d = obs and obs.durability
        if type(d) ~= "table" then return "Not read yet" end
        if #d.items == 0 then return "Nothing equipped that wears down" end
        if d.broken then return "Something is broken" end
        return ("Most worn item at %d%%"):format(math.floor(d.lowest))
    end,

    Subject = function() return "durability", "Equipment durability" end,

    Scenarios = function()
        local list = {}
        local function Put(key, label, items)
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                if items == nil then obs.durability = nil return end
                local d = { items = {}, broken = false, lowest = nil }
                for i, it in ipairs(items) do
                    d.items[i] = { it[1], it[2] }
                    if it[1] <= 0 then d.broken = true end
                    local pct = it[1] / it[2] * 100
                    if not d.lowest or pct < d.lowest then d.lowest = pct end
                end
                obs.durability = d
            end }
        end
        Put("fine", "Everything in good repair", { { 100, 100 }, { 60, 65 } })
        Put("worn", "One item at 15%", { { 100, 100 }, { 15, 100 } })
        Put("broken", "One item broken, the rest fine", { { 100, 100 }, { 100, 100 }, { 0, 85 } })
        Put("nothing", "Nothing equipped that wears down", {})
        Put("unread", "Not read yet", nil)
        return list
    end,
})

local SLOTS = C.EQUIPPED_SLOTS

local function ReadDurability(into)
    if not GetInventoryItemDurability then return nil end
    local d = { items = {}, broken = false, lowest = nil }
    for _, slot in ipairs(SLOTS) do
        local cur, max = GetInventoryItemDurability(slot)
        cur, max = Number(cur), Number(max)
        if cur and max and max > 0 then
            d.items[#d.items + 1] = { math.max(0, cur), max }
            if cur <= 0 then d.broken = true end
            local pct = math.max(0, cur) / max * 100
            if not d.lowest or pct < d.lowest then d.lowest = pct end
        end
    end
    local old = into.durability
    if type(old) == "table" and #old.items == #d.items then
        local same = true
        for i, it in ipairs(d.items) do
            if old.items[i][1] ~= it[1] or old.items[i][2] ~= it[2] then same = false break end
        end
        if same then return false end
    end
    into.durability = d
    return true
end

ST.Source("durability", {
    events = { UPDATE_INVENTORY_DURABILITY = true, PLAYER_EQUIPMENT_CHANGED = true },
    Read = function(_, into)
        ST.Counted()
        if not GetInventoryItemDurability then return ST.Set(into, "durability", nil) end
        return ReadDurability(into)
    end,
})
