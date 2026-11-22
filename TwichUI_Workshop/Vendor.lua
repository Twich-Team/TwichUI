-- TwichUI Workshop: what a vendor was seen to charge, and where
-- No frames and no game calls (Observe.lua reads the merchant window; Session.lua hands the listings here). It keeps the PURCHASE price a
-- merchant asked for an item the Workshop cares about, so the shopping list can compare buying from a vendor with the auction house and
-- with making the item. Vendor SELL values (what a vendor pays you) are never used and never stored.
--
--   TwichUIDB.workshop.vendor = { v = 1, items = { [itemID] = { p, s, a, at, npc } } }   account-wide, bounded, never in a profile, a share
--       or a backup (the same "workshop" key as the queue and the prices: Restore.OWN_LEFT_OUT, TwichConfig.LOCAL)
--       p  copper for ONE purchase of s items (the merchant sells in stacks of s; buying n items means ceil(n / s) purchases)
--       a  how many the merchant had when seen: -1 unlimited, otherwise a count (0 = sold out)
--       at when it was seen (time)           npc the creature id of the merchant, or absent
--   Only listings paid for with money alone are kept: an extended cost, a currency or a cost item makes the listing not a price in copper.
--   It is what was seen the LAST time a merchant's window was open while the Workshop window was too. A merchant's stock changes with
--   level, reputation and season, so a record is a guide, never proof the item is for sale now; the view says when it was seen.
--   Where the merchant is comes from the player's own NPC collection (npcs/): a place is offered only for a merchant that list holds, whose
--   stock names the item, on a map the game shows, for the player's side.

local R = TwichUI
local W = R.Workshop
local Q = W.Queue
local PR = W.Prices
local Int = W.Int
local V = {}
W.Vendor = V
local revision=0
function V.Revision()return revision end

V.SAVED_VERSION = 1
V.MAX_ITEMS = 400
V.OLD_AFTER = 7 * 86400   -- seconds after which a vendor record is called old

local MAX_TIME = 4102444800

local function Store(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local ws = TwichUIDB.workshop
    if type(ws) ~= "table" then
        if not create then return nil end
        ws = { v = W.SAVED_VERSION }
        TwichUIDB.workshop = ws
    end
    local v = ws.vendor
    if type(v) ~= "table" then
        if not create then return nil end
        v = { v = V.SAVED_VERSION, items = {} }
        ws.vendor = v
    end
    if type(v.items) ~= "table" then
        if not create then return nil end
        v.items = {}
    end
    return v
end

-- True when a newer TwichUI wrote this (or the workshop data): read as far as understood, never changed
function V.Held()
    if Q.Held() then return true end
    local v = Store(false)
    return v ~= nil and type(v.v) == "number" and v.v > V.SAVED_VERSION
end

-- A checked copy of one saved record, or nil
local function Clean(t)
    if type(t) ~= "table" then return nil end
    local p = Int(t.p, 1, PR.MAX_COPPER)
    local s = Int(t.s, 1, W.MAX_QTY)
    local a = Int(t.a, -1, W.MAX_ID)
    local at = Int(t.at, 1, MAX_TIME)
    if not (p and s and a and at) then return nil end
    return { p = p, s = s, a = a, at = at, npc = Int(t.npc, 1, W.MAX_ID) }
end

-- What is remembered of an item's vendor price, or nil (never a zero price)
function V.Entry(item)
    local v = Store(false)
    return v and Clean(v.items[item]) or nil
end

function V.Count()
    local v = Store(false)
    local n = 0
    if v then for _ in pairs(v.items) do n = n + 1 end end
    return n
end

-- Copper per single item, whole, only for comparing two records (the exact cost of buying n is Quote's)
local function Cheaper(a, b)   -- a is cheaper per item than b
    return a.p * b.s < b.p * a.s
end

-- listings: { { id, price, stack, avail }, ... } as Observe.ReadMerchant gives them. wanted: set [itemID] = true. npc: the merchant's creature id
-- or nil. Keeps what is valid and wanted. Returns how many were kept, or false and why ("held", "unsaved").
function V.Observe(listings, wanted, npc, now)
    if V.Held() then return false, "held" end
    now = Int(now or Q.Now(), 1, MAX_TIME)
    if not now or type(listings) ~= "table" or type(wanted) ~= "table" then return 0 end
    local best = {}
    for _, l in ipairs(listings) do
        local id = Int(l.id, 1, W.MAX_ID)
        local rec = id and wanted[id] and Clean({ p = l.price, s = l.stack, a = l.avail, at = now, npc = npc })
        if rec and (not best[id] or Cheaper(rec, best[id])) then best[id] = rec end
    end
    if next(best) == nil then return 0 end
    local v = Store(true)
    if not v then return false, "unsaved" end
    local kept,changed = 0,{}
    for id, rec in pairs(best) do
        local old = Clean(v.items[id])
        -- another merchant's cheaper price stays; the same merchant (or one not known) is newer news
        if old and old.npc ~= nil and rec.npc ~= nil and old.npc ~= rec.npc and Cheaper(old, rec) then
            -- keep old
        else
            if not old or old.p~=rec.p or old.s~=rec.s or old.a~=rec.a or old.at~=rec.at or old.npc~=rec.npc then changed[id]=true end
            v.items[id] = { p = rec.p, s = rec.s, a = rec.a, at = rec.at, npc = rec.npc }
            kept = kept + 1
        end
    end
    local ws = TwichUIDB.workshop
    ws.v = W.SAVED_VERSION
    -- over the limit: the record seen longest ago goes
    local n = 0
    for _ in pairs(v.items) do n = n + 1 end
    while n > V.MAX_ITEMS do
        local oldest, oldAt
        for id, t in pairs(v.items) do
            local at = type(t) == "table" and tonumber(t.at) or 0
            if not oldAt or at < oldAt then oldest, oldAt = id, at end
        end
        if oldest == nil then break end
        v.items[oldest] = nil
        changed[oldest]=true
        n = n - 1
    end
    if next(changed)then
        revision=revision+1
        if W.Session and W.Session.ItemsChanged then W.Session.ItemsChanged(changed)end
    end
    return kept
end

-- What buying `qty` of an item from that merchant costs, from a record (Entry's answer), or nil when there is none:
--   { state = "ok" | "limited", purchases, items (what the purchases give), surplus, cost (copper; nil when limited), at, npc, avail }
-- Items come in whole stacks, so the cost is for ceil(qty / stack) purchases. "limited": the merchant had fewer than that when seen.
function V.Quote(rec, qty)
    qty = Int(qty, 1, W.MAX_ID)
    if not qty or type(rec) ~= "table" then return nil end
    local purchases = math.ceil(qty / rec.s)
    local items = purchases * rec.s
    local q = { purchases = purchases, items = items, surplus = items - qty, at = rec.at, npc = rec.npc, avail = rec.a, stack = rec.s,
        unit = rec.p / rec.s }
    if rec.a >= 0 and items > rec.a then
        q.state = "limited"
    else
        q.state = "ok"
        q.cost = purchases * rec.p
    end
    return q
end

---------------------------------------------------------------------------
-- Where
---------------------------------------------------------------------------
-- The merchants of the player's own NPC collection that were seen to sell the wanted items, that the character can deal with and that sit on
-- a map the game shows: { [itemID] = { entry, ... } } (the list's own entries: read them, never change them). Empty while the collection is
-- off or knows none. One pass over the list, only for the items asked about.
function V.Sellers(wanted)
    local out = {}
    local NS = R.NpcStore
    if not (NS and NS.Entries and NS.ValidMap and NS.Usable and R.Enabled and R:Enabled("npcMap")) or type(wanted) ~= "table" then return out end
    local mine = NS.MyFaction and NS.MyFaction() or nil
    for _, e in ipairs(NS.Entries()) do
        if type(e) == "table" and type(e.s) == "table" and NS.ValidMap(e.m) and NS.Usable(e, mine)
            and type(e.x) == "number" and type(e.y) == "number" then
            for i = 1, #e.s do
                local id = e.s[i]
                if wanted[id] then
                    local list = out[id]
                    if not list then list = {} out[id] = list end
                    list[#list + 1] = e
                end
            end
        end
    end
    return out
end

-- Where to look for an item: the sellers of it (Sellers' answer for that item: merchants whose stock was seen to hold it, for the player's side,
-- on a map the game shows), best first. Returns the places (at most `limit`, default 3) and how the first one was chosen:
--   "nearest"  a straight-line distance was compared (same continent): it is the nearest KNOWN seller, not a walking route or a time
--   "local"    no position could be compared, but it is on the map the player is on
--   "unknown"  neither: nothing is claimed about how near it is (the merchant the price was seen at leads)
-- The order (the NPC search's tiers, npcs/Search.lua):
--   1  sellers whose distance can be told, nearest first (in whole yards: a recorded place is only good to a few yards)
--   2  sellers on the player's map whose distance can't be told
--   3  every other seller
-- Within a tier and an equal distance: one the player dealt with before a reported one, then the merchant the price was seen at, then the one seen
-- most recently, then by name and place, so the order never shuffles. The merchant where the price was noted is context, never a reason to send the
-- player to another continent past a nearer seller (P2.1: in Undercity, an Undercity seller is shown, not the Orgrimmar one the price came from).
function V.Places(list, npc, limit)
    if type(list) ~= "table" or #list == 0 then return {}, nil end
    local NS, SR = R.NpcStore, R.NpcSearch
    local spot = SR and SR.Where and SR.Where() or nil
    local found = {}
    for _, e in ipairs(list) do
        local dist = spot and SR.Distance and SR.Distance(spot, e.m, e.x / NS.COORD, e.y / NS.COORD) or nil
        local tier = dist and 1 or ((spot and spot.map ~= nil and e.m == spot.map) and 2 or 3)
        found[#found + 1] = { e = e, tier = tier, yards = dist and math.floor(dist + 0.5) or nil, own = e.own == true,
            priced = npc ~= nil and e.id == npc, at = tonumber(e.at) or 0,
            name = tostring(e.n or ""):lower(), key = ("%d:%d:%d:%d"):format(e.id or 0, e.m, e.x, e.y) }
    end
    table.sort(found, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
        if a.own ~= b.own then return a.own end
        if a.priced ~= b.priced then return a.priced end
        if a.at ~= b.at then return a.at > b.at end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    local out = {}
    for i = 1, math.min(#found, limit or 3) do out[i] = found[i].e end
    local first = found[1]
    return out, (first.tier == 1 and "nearest") or (first.tier == 2 and "local") or "unknown"
end
