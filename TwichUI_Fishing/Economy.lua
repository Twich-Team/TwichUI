-- Current-market estimates only. Never persisted and never written to the Gold Ledger.
-- Drawing/catch handlers read a bounded cache; Workshop reads run in deferred batches.
local R = TwichUI
local F = R.Fishing
local E = { MAX_ITEMS = 4096, BATCH = 8 }
F.Economy = E
local cache, queue, queued, cursor, size = {}, {}, {}, 1, 0
local scopes, scopeCount = {}, 0
local stamp, context, running, token = nil, nil, false, 0
local floor = math.floor
local function Copper(n)
    return type(n) == "number" and n == n and n >= 0 and n <= 9007199254740991 and n == floor(n) and n or nil
end
local function Workshop()
    if F.Store.Get("economy.enabled") == false then return nil end
    local w = R.Workshop
    local p = w and w.Pricing
    return w and p and type(p.Source) == "function" and type(p.Generation) == "function"
        and type(p.Reference) == "function" and w.Market and type(w.Market.Value) == "function"
        and w.Active and w.Active() and w or nil
end
local function Changed()
    if F.Hud then F.Hud.serial = F.Hud.serial + 1 end
    F.Emit("ECONOMY")
end
function E.Invalidate()
    scopes, scopeCount = {}, 0
    token = token + 1
    cache, queue, queued, cursor, size, running, stamp, context = {}, {}, {}, 1, 0, false, nil, nil
    Changed()
end
local function Context()
    local w = Workshop()
    if not w then return nil end
    local p = w.Pricing
    local src = p.Source()
    local m = src.market
    local method = F.Store.Get("economy.method") or "market"
    local key = table.concat({ p.Generation(), m and m.key or "none", tostring(m and m.at), method,
        tostring(src.reference), tostring(m and m.realm), tostring(m and m.side) }, "|")
    if key ~= stamp then
        token = token + 1
        cache, queue, queued, cursor, size, running = {}, {}, {}, 1, 0, false
        stamp = key
        context = { key = key, market = m, reference = src.reference == true, method = method,
            label = src.label, why = src.referenceWhy, at = m and m.at, workshop = w }
    end
    return context
end
local function Vendor(id)
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    local _, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(id)
    return Copper(F.Readable(price))
end
local Schedule
local function Work(mine)
    if mine ~= token then return end
    local cx = Context()
    if mine ~= token or not cx then running = false; return end
    local w, changed = cx.workshop, false
    for _ = 1, E.BATCH do
        local id = queue[cursor]
        if not id then break end
        cursor = cursor + 1; queued[id] = nil
        local price, why, at, source
        if cx.reference then
            local ref
            ref, why = w.Pricing.Reference(id, { market = cx.market })
            price, at, source = ref and ref[cx.method], ref and ref.at, "market_server"
        elseif cx.market then
            local value
            value, why = w.Market.Value(id, cx.method, { market = cx.market })
            price, at, source = value and value.value, value and value.at, "local"
        else why = "nomarket" end
        cache[id] = { unit = Copper(price), vendor = Vendor(id), at = at, source = source,
            market = cx.key, why = why or (not price and "missing" or nil), pending = why == "loading" }
        changed = true
    end
    running = false
    if cursor <= #queue then Schedule() else queue, cursor = {}, 1 end
    if changed then scopes, scopeCount = {}, 0; Changed() end
end
Schedule = function()
    if running or not (C_Timer and C_Timer.After) then return end
    running = true
    local mine = token
    C_Timer.After(0.01, function()
        if R.Perf and R.Perf.Call then R.Perf.Call("fishing.economy", Work, mine) else Work(mine) end
    end)
end
function E.Item(id, quantity, suppliedContext)
    quantity = Copper(quantity or 1)
    if not F.Count(id) or not quantity then return nil end
    local cx = suppliedContext
    if cx == nil then cx = Context() elseif cx == false then cx = nil end
    local item = cx and cache[id]
    if cx and not item and not queued[id] and size < E.MAX_ITEMS then
        queued[id], size = true, size + 1; queue[#queue + 1] = id; Schedule()
    end
    local unit = item and item.unit
    local vendor = item and item.vendor or Vendor(id)
    return { id = id, q = quantity, unit = unit, total = unit and Copper(unit * quantity),
        vendorUnit = vendor, vendor = vendor and Copper(vendor * quantity), source = item and item.source,
        market = cx and cx.key, label = cx and cx.label, at = item and item.at,
        age = item and item.at and math.max(0, F.Now() - item.at),
        stale = item and item.at and F.Now() - item.at > 86400 or false,
        pending = cx ~= nil and (not item or item.pending) or false,
        why = item and item.why or (cx and "pending" or "workshop-unavailable") }
end
-- The caller supplies provenance, never raw catches: opened shells are excluded by construction.
function E.Calculate(provenance, seconds, casts)
    if not provenance then return nil end
    local cx = Context()
    local out = { known = 0, priced = 0, missing = 0, vendorKnown = 0, vendorMissing = 0, vendorPriced = 0,
        direct = {}, contents = {}, provisional = {}, market = cx and cx.key, label = cx and cx.label }
    local function Add(items, dest, provisional)
        for id, q in pairs(items or {}) do
            if q > 0 then
                local row = E.Item(id, q, cx or false); dest[id] = row
                if row and row.total ~= nil and row.market == out.market and Copper(out.known + row.total) then
                    out.known = out.known + row.total; out.priced = out.priced + q
                else out.missing = out.missing + q end
                if row and row.vendor ~= nil and Copper(out.vendorKnown + row.vendor) then out.vendorKnown = out.vendorKnown + row.vendor; out.vendorPriced = out.vendorPriced + q
                else out.vendorMissing = out.vendorMissing + q end
                if provisional then out.provisionalQuantity = (out.provisionalQuantity or 0) + q end
            end
        end
    end
    Add(provenance.direct, out.direct)
    Add(provenance.contents, out.contents)
    if F.Store.Get("economy.provisional") ~= false then
        local unopened = {}
        for id, lot in pairs(provenance.containers or {}) do
            unopened[id] = math.max(0, (lot.unopened or 0) - (lot.partial or 0))
            local lost = math.max(0, (lot.caught or 0) - (lot.opened or 0) - (lot.unopened or 0))
                + math.min(lot.unopened or 0, lot.partial or 0)
            out.missing, out.vendorMissing = out.missing + lost, out.vendorMissing + lost
        end
        Add(unopened, out.provisional, true)
    end
    out.complete = out.missing == 0
    out.total = out.priced > 0 and out.known or nil
    out.vendor = out.vendorPriced > 0 and out.vendorKnown or nil
    if out.total and Copper(seconds) and seconds > 0 then
        local whole, remainder = floor(out.total / seconds), out.total % seconds
        local high, low = Copper(whole * 3600), Copper(remainder * 3600)
        out.perHour = high and low and Copper(high + floor(low / seconds)) or nil
    end
    out.perCast = out.total and casts and casts > 0 and floor(out.total / casts) or nil
    -- Historical purchase prices and lure consumption were not recorded. Do not invent expenses or net income.
    out.costWhy = "Lure purchase costs are not recorded; estimated net value is unavailable."
    return out
end
function E.Scope(scope)
    local cx = Context()
    -- No auction service and no vendor display: do not copy provenance/history merely to say unavailable.
    if not cx and F.Store.Get("economy.vendor") ~= true then return nil end
    local key = scope or "lifetime"
    local old = scopes[key]
    local identity = cx and cx.key or "unavailable"
    if old and old.identity == identity and old.token == token then return old.value end
    local meta = F.API.Metrics(scope)
    local result = meta and E.Calculate(F.API.Provenance(scope), meta.seconds, meta.casts) or nil
    if scopeCount >= 64 then scopes, scopeCount = {}, 0 end
    if not scopes[key] then scopeCount = scopeCount + 1 end
    scopes[key] = { identity = identity, token = token, value = result }
    return result
end
for _, event in ipairs({ "ITEM", "CONTAINER", "QUEUE", "CAST", "CATCH", "SESSION_START", "SESSION_END" }) do
    F.Subscribe(event, function() scopes, scopeCount = {}, 0 end)
end

function E.Text(value)
    if value == nil then return "Price unavailable" end
    local w = R.Workshop
    local coins = w and w.UI and w.UI.Coins
    return coins and coins.Text(value) or ("%dg %ds %dc"):format(floor(value / 10000), floor(value / 100) % 100, value % 100)
end
function E.Description(v)
    if not v then return "Estimates unavailable" end
    return (v.total and E.Text(v.total) or "Price unavailable") .. (v.complete and " estimated" or " known subtotal · incomplete")
end
local hooked
local function Hook()
    local w = R.Workshop
    if hooked or not (w and w.Pricing and hooksecurefunc) then return end
    hooked = true
    hooksecurefunc(w.Pricing, "Changed", E.Invalidate)
    if type(w.Suspend) == "function" then hooksecurefunc(w, "Suspend", E.Invalidate) end
    if type(w.Resume) == "function" then hooksecurefunc(w, "Resume", E.Invalidate) end
    if w.Scan and w.Scan.Listen then
        local ended = w.Scan.ended
        w.Scan.Listen(function()
            if ended ~= w.Scan.ended then ended = w.Scan.ended; E.Invalidate() end
        end)
    end
end
R:On("ADDON_LOADED", Hook)
R:On("GET_ITEM_INFO_RECEIVED", E.Invalidate)
Hook()

F.Subscribe("CONFIG", function(_, path) if type(path) == "string" and path:match("^economy%.") then E.Invalidate() end end)

function E.Status()
    local cx = Context()
    return { available = cx ~= nil, source = cx and cx.label, at = cx and cx.at,
        cached = size, pending = #queue - cursor + 1, generation = stamp }
end
function E.CacheSize() return size end
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("fishing.prices", { label = "Fishing item valuations", kind = "cache", group = "fishing", unit = "count", read = E.CacheSize })
end

R:On("AUCTION_HOUSE_SHOW", E.Invalidate)
R:On("AUCTION_HOUSE_CLOSED", E.Invalidate)
