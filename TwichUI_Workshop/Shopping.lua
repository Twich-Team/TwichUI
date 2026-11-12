-- TwichUI Workshop: the shopping list (pure)
-- Turns the queue's materials (Materials.Rows: what is needed, what queued crafts will make, what the bags hold, what is still short) and
-- the prices already known into ONE list of what to get and where: from a vendor, from the auction house, or by making it. No frames, no
-- game calls and nothing saved: the caller hands in functions that answer from the saved prices, the saved vendor prices, the known recipes
-- and the bags, so the same inputs always give the same plan.
--
-- THE RULES (docs/workshop.md repeats them):
--   * Each missing material is one row. Needs are the queue's, added up first (Materials.lua); bags are applied once per item.
--   * One shared pool of owned items, in three layers: the bags, the bank, the guild bank (Stock.lua; W.Split takes from them in that order).
--     The queue's own craft needs take what is owned first. A material that is made (a "subcraft") then draws its reagents from what is LEFT,
--     and each reagent spent is taken out of the pool, so no owned item is spent twice. What is still lacking for a subcraft is bought.
--   * Stored materials are COLLECTED, not bought: whatever the plan takes from the bank or the guild bank (for the queue's own crafts or for the
--     reagents of a made material) becomes a "collect" row of its own, beside the buy and make rows. They lower what is bought, never what a craft
--     costs: the Make option's economic cost still values an owned reagent at what it would cost, wherever it is held.
--   * One level only. A made material's reagents are bought, never made in turn. A material is not made when one of its reagents is itself
--     being made, when another made material already counts it as a reagent, or when its own recipe uses it (a circle): the option then says why.
--   * Only a FIXED output is used to suggest making: crafts are rounded up to cover what is short (ceil(short / output)) and the leftover is
--     shown. A recipe that makes a range, whose materials TwichUI cannot count or whose output is unknown is listed with the reason and never
--     suggested. Cooldowns, tools and crafting stations are not checked (not read); the row says so.
--   * Costs. Vendor: whole purchases of the merchant's stack at the price last SEEN (never a sell value). Auction house: Prices.Quote (exact
--     only up to what the saved scan shows at the cheapest price, otherwise a unit-price estimate, or not enough listed). Make: the economic
--     cost of the reagents, owned ones valued at what they would cost (owning them does not make them free); the cash needed is separate.
--   * "Suggested source" is the cheapest option whose cost is known, ties to vendor, then auction, then making. It is a comparison of what is
--     known, not a claim of the cheapest plan: choices are made one material at a time and sources are never searched exhaustively.
--   * A player's choice (picks) is used when its option still exists, and is decided first so a suggestion never takes its place.
--   * Spending adds up only what is priced. Anything unpriced is counted in `missing`, never in the total, and the total says so.
--   Work is bounded by construction: at most 30 recipes x 16 materials rows, 4 candidate recipes each, 16 reagents each.

local R = TwichUI
local W = R.Workshop
local PR, V = W.Prices, W.Vendor
local Sh = {}
W.Shopping = Sh

Sh.MAX_CANDIDATES = 4
Sh.NAMES = { vendor = "Vendor", auction = "Auction house", make = "Make" }
Sh.ORDER = { "vendor", "auction", "make" }   -- also the order ties are broken in

local function Round(x) return math.floor(x + 0.5) end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------
-- The options for buying `qty` of an item: { vendor = opt, auction = opt } (either may be missing). An option: { kind, state, cost, quote, at }.
-- cost is nil when it cannot be said (vendor: "noprice" = a merchant is known to sell it but no price was seen, "limited" = it had fewer
-- when seen; auction: "few" = fewer listed than asked for).
local function BuyOptions(inp, item, qty)
    local o = {}
    local vr = inp.vendor(item)
    if vr then
        local q = V.Quote(vr, qty)
        o.vendor = { kind = "vendor", state = q.state, cost = q.cost, quote = q, at = vr.at, npc = vr.npc }
    elseif inp.sells(item) then
        o.vendor = { kind = "vendor", state = "noprice" }
    end
    local aq = PR.Quote(inp.auction(item), qty)
    if aq.state ~= "none" then
        o.auction = { kind = "auction", state = aq.state, cost = aq.cost, quote = aq, at = aq.at, estimate = aq.state == "estimate" }
    end
    return o
end

-- The cheaper priced way to buy `qty`: { source, cost, estimate, at } or nil. A tie goes to the vendor.
local function Best(inp, item, qty)
    local o = BuyOptions(inp, item, qty)
    local best
    if o.vendor and o.vendor.cost then best = { source = "vendor", cost = o.vendor.cost, at = o.vendor.at } end
    if o.auction and o.auction.cost and (not best or o.auction.cost < best.cost) then
        best = { source = "auction", cost = o.auction.cost, estimate = o.auction.estimate, at = o.auction.at }
    end
    return best
end

-- What one owned item is worth: the cheapest price per item known, or nil
local function UnitValue(inp, item)
    local best
    local vr = inp.vendor(item)
    if vr then best = vr.p / vr.s end
    local p = inp.auction(item)
    if p and p.price and (not best or p.price < best) then best = p.price end
    return best
end

-- The suggestion: the source with the lowest known cost (ties: vendor, auction, make), or nil when none has a cost
local function Suggest(opts)
    local best, bestCost
    for _, k in ipairs(Sh.ORDER) do
        local o = opts[k]
        if o and o.cost and (k ~= "make" or o.state == "ok") and (not bestCost or o.cost < bestCost) then best, bestCost = k, o.cost end
    end
    return best
end

local function Usable(o)   -- what a player may choose: any buying option that exists, and making only when it can really be done
    return o ~= nil and (o.kind ~= "make" or o.state == "ok")
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------
-- inp:
--   rows      Materials.Rows' rows: { item, need, made, madeRange, have, short }
--   have      function(item) -> how many the bags hold, or nil
--   stock     function(item) -> bank count, guild count that may be planned with (Stock.Fn), or nil for bags only
--   stockMeta function(item, where) -> { at, limited } for a collect row ("bank" or "guild"), or nil
--   auction   function(item) -> Prices.Lookup's answer or nil
--   vendor    function(item) -> Vendor.Entry's answer or nil
--   sells     function(item) -> true when the NPC collection knows a merchant that sells it
--   recipes   function(item) -> the known recipes that make it, by recipe id: { { id, name, outItem, outMin, outMax, mats|nil, profName, live }, ... }
--   picks     { [item] = "vendor" | "auction" | "make" } the player's choices (anything else is ignored)
--   queued    function(recipeId) -> the queue entry or nil
-- Returns plan = { rows, totals, unknownBags }. A row (kind "collect", "buy" or "make"); a collect row is { kind, item, where = "bank" | "guild", qty, at, limited,
-- forNames (made materials it is a reagent of), need/have for the tooltip }; the others:
--   item, need, made, madeRange, have, short (still needed after bags and queued crafts), extra (more bought as reagents of made materials),
--   qty (what is acquired: buy rows; for make rows what is made), options { vendor, auction, make }, suggested, source, picked, pickLost,
--   cash (copper for the buy rows, nil when unknown), estimate, at, surplus (leftover of a vendor purchase), forNames (made materials it is for),
--   uncertain (words), make (make rows: the option that is done)
function Sh.Plan(inp)
    local rowsIn = inp.rows
    local picks = inp.picks or {}
    local have = inp.have
    local pool, used = {}, {}   -- pool[item]: { bags, bank, guild } owned left after the queue's own craft needs (false: unknown); used[item]: taken by made materials
    local byItem = {}
    for _, r in ipairs(rowsIn) do
        byItem[r.item] = r
        if r.have ~= nil then
            local net = math.max(0, r.need - (r.made or 0))
            pool[r.item] = { bags = r.have - math.min(r.have, net), bank = math.max(0, (r.bank or 0) - (r.fromBank or 0)),
                guild = math.max(0, (r.guild or 0) - (r.fromGuild or 0)) }
        else
            pool[r.item] = false
        end
    end
    -- what is still free of an item in each layer (bags, bank, guild bank), or nil when its bag count can't be read
    local function Free(item)
        local p = pool[item]
        if p == nil then
            local h = have(item)
            if h == nil then
                p = false
            else
                local bank, guild = 0, 0
                if inp.stock then bank, guild = inp.stock(item) end
                p = { bags = h, bank = bank, guild = guild }
            end
            pool[item] = p
        end
        if p == false then return nil end
        local u = used[item] or {}
        return math.max(0, p.bags - (u.bags or 0)), math.max(0, p.bank - (u.bank or 0)), math.max(0, p.guild - (u.guild or 0))
    end

    local madeSet, reagentSet, reagentBuys = {}, {}, {}
    local collectFor = {}   -- [item] = { bank, guild, names }: taken from storage as reagents of made materials

    -- Making `short` of an item from one recipe: an option, with state "ok" or the reason it cannot be done
    local function EvalMake(item, short, rec)
        local opt = { kind = "make", rec = rec, state = "ok", queued = inp.queued and inp.queued(rec.id) or nil }
        local mats = rec.mats
        if type(mats) ~= "table" or #mats == 0 then opt.state = "unsupported" return opt end
        local lo = rec.outMin
        if not lo then opt.state = "noamount" return opt end
        local hi = rec.outMax or lo
        if hi ~= lo then opt.state = "range" opt.range = lo .. "-" .. hi return opt end
        for _, m in ipairs(mats) do
            if m.item == item then opt.state = "circular" return opt end
        end
        if reagentSet[item] then opt.state = "chain" return opt end
        for _, m in ipairs(mats) do
            if madeSet[m.item] then opt.state = "chain" opt.blocker = m.item return opt end
        end
        local crafts = math.ceil(short / lo)
        if crafts > W.MAX_CRAFTS then opt.state = "toomany" return opt end
        opt.crafts, opt.perCraft, opt.made, opt.surplus = crafts, lo, crafts * lo, crafts * lo - short
        local cash, ownedValue, cashKnown, valueKnown = 0, 0, true, true
        opt.reagents = {}
        for _, m in ipairs(mats) do
            local total = m.qty * crafts
            local fb, fk, fg = Free(m.item)
            local b, k, g = 0, 0, 0
            if fb == nil then opt.ownedUnknown = true else b, k, g = W.Split(total, fb, fk, fg) end
            local owned = b + k + g
            local line = { item = m.item, qty = total, owned = owned, buy = total - owned, bags = b, bank = k, guild = g }
            if line.buy > 0 then
                local b = Best(inp, m.item, line.buy)
                if b then
                    line.source, line.cost, line.estimate = b.source, b.cost, b.estimate
                    cash = cash + b.cost
                    if b.estimate then opt.estimate = true end
                else
                    cashKnown = false
                end
            end
            if owned > 0 then
                local u = UnitValue(inp, m.item)
                if u then
                    line.value = Round(owned * u)
                    ownedValue = ownedValue + line.value
                else
                    valueKnown = false
                end
            end
            opt.reagents[#opt.reagents + 1] = line
        end
        if cashKnown then opt.cash = cash end
        if cashKnown and valueKnown then opt.cost = cash + ownedValue end   -- economic cost: owned reagents count at what they would cost
        return opt
    end

    -- the best recipe for an item: the cheapest that can be done, else the first that can be done, else the first one (to say why not)
    local function BestMake(item, short)
        local cands = inp.recipes and inp.recipes(item) or {}
        local best, firstOk, any
        for i = 1, math.min(#cands, Sh.MAX_CANDIDATES) do
            local o = EvalMake(item, short, cands[i])
            any = any or o
            if o.state == "ok" then
                firstOk = firstOk or o
                if o.cost and (not best or o.cost < best.cost) then best = o end
            end
        end
        return best or firstOk or any
    end

    local function Commit(item, mk)
        madeSet[item] = true
        for _, line in ipairs(mk.reagents) do
            reagentSet[line.item] = true
            local u = used[line.item]
            if not u then u = {} used[line.item] = u end
            u.bags, u.bank, u.guild = (u.bags or 0) + line.bags, (u.bank or 0) + line.bank, (u.guild or 0) + line.guild
            if line.bank + line.guild > 0 then
                local c = collectFor[line.item]
                if not c then c = { bank = 0, guild = 0, names = {} } collectFor[line.item] = c end
                c.bank, c.guild = c.bank + line.bank, c.guild + line.guild
                c.names[#c.names + 1] = mk.rec.name
            end
            if line.buy > 0 then
                local rb = reagentBuys[line.item]
                if not rb then rb = { qty = 0, names = {} } reagentBuys[line.item] = rb end
                rb.qty = rb.qty + line.buy
                rb.names[#rb.names + 1] = mk.rec.name
            end
        end
    end

    -- decide the sources, the player's own choices first
    local todo, unknownBags = {}, 0
    for _, r in ipairs(rowsIn) do
        if r.short == nil then unknownBags = unknownBags + 1
        elseif r.short > 0 then todo[#todo + 1] = r end
    end
    table.sort(todo, function(a, b)
        local pa, pb = picks[a.item] ~= nil, picks[b.item] ~= nil
        if pa ~= pb then return pa end
        return a.item < b.item
    end)
    local resolved = {}
    for _, r in ipairs(todo) do
        local res = { item = r.item, need = r.need, made = r.made, madeRange = r.madeRange, have = r.have, short = r.short,
            fromBank = r.fromBank, fromGuild = r.fromGuild }
        res.options = BuyOptions(inp, r.item, r.short)
        local mk = BestMake(r.item, r.short)
        if mk then res.options.make = mk end
        res.suggested = Suggest(res.options)
        local pick = picks[r.item]
        if pick and Usable(res.options[pick]) then
            res.source, res.picked = pick, true
        else
            res.pickLost = pick
            res.source = res.suggested
        end
        if res.source == "make" then Commit(r.item, res.options.make) end
        resolved[#resolved + 1] = res
    end

    -- what is acquired: the buy rows' shortages plus the reagents of made materials, added up per item and priced once for the whole quantity
    local acq, acqItems = {}, {}
    local function Acq(item)
        local a = acq[item]
        if not a then a = { item = item, qty = 0, extra = 0 } acq[item] = a acqItems[#acqItems + 1] = item end
        return a
    end
    for _, res in ipairs(resolved) do
        if res.source ~= "make" then
            local a = Acq(res.item)
            a.main = res
            a.qty = a.qty + res.short
        end
    end
    for g, rb in pairs(reagentBuys) do
        local a = Acq(g)
        a.qty, a.extra, a.forNames = a.qty + rb.qty, rb.qty, rb.names
    end
    table.sort(acqItems)

    local out = {}
    local totals = { cash = 0, priced = 0, missing = 0, estimate = false, makes = 0, incomplete = false, collect = 0 }
    for _, item in ipairs(acqItems) do
        local a = acq[item]
        local main = a.main
        local opts = BuyOptions(inp, item, a.qty)
        local src, picked
        local pick = picks[item]
        if (pick == "vendor" or pick == "auction") and opts[pick] then
            src, picked = pick, true
        elseif main and (main.source == "vendor" or main.source == "auction") and opts[main.source] and opts[main.source].cost then
            src = main.source   -- the suggested way, as long as it still covers everything that is bought of it
        end
        if not src then
            local b = Best(inp, item, a.qty)
            src = b and b.source or (main and (main.source == "vendor" or main.source == "auction") and main.source) or nil
        end
        local base = byItem[item]
        local row = { kind = "buy", item = item, need = base and base.need, made = base and base.made, madeRange = base and base.madeRange,
            have = base and base.have, fromBank = base and base.fromBank, fromGuild = base and base.fromGuild,
            short = main and main.short or 0, extra = a.extra, qty = a.qty, options = opts, source = src,
            picked = picked, pickLost = main and main.pickLost, forNames = a.forNames, reagentOnly = main == nil }
        if main and main.options.make then opts.make = main.options.make end
        row.suggested = main and main.suggested or Suggest(opts)
        if row.reagentOnly then row.suggested = Suggest({ vendor = opts.vendor, auction = opts.auction }) end
        local o = src and opts[src] or nil
        if o and o.cost then
            row.cash, row.at, row.estimate = o.cost, o.at, o.estimate
            if o.quote and o.quote.surplus and o.quote.surplus > 0 then row.surplus = o.quote.surplus end
            totals.cash, totals.priced = totals.cash + o.cost, totals.priced + 1
            if o.estimate then totals.estimate = true end
            if o.quote and o.quote.complete == false then totals.incomplete = true end
        else
            totals.missing = totals.missing + 1
        end
        if row.suggested == "auction" and opts.auction and opts.auction.estimate then row.uncertain = "The auction price is an estimate: more may cost more." end
        out[#out + 1] = row
    end
    for _, res in ipairs(resolved) do
        if res.source == "make" then
            local mk = res.options.make
            local row = { kind = "make", item = res.item, need = res.need, made = res.made, madeRange = res.madeRange, have = res.have,
                fromBank = res.fromBank, fromGuild = res.fromGuild, short = res.short, extra = 0, qty = res.short, options = res.options, suggested = res.suggested, source = "make",
                picked = res.picked, pickLost = res.pickLost, make = mk }
            if mk.estimate then row.uncertain = "Part of the cost of making it is an estimate." end
            if mk.ownedUnknown then row.uncertain = "Your bag counts of its materials couldn't all be read." end
            totals.makes = totals.makes + 1
            out[#out + 1] = row
        end
    end
    -- what is collected from storage: the queue's own needs (rows) plus the reagents of made materials; one row per item and store
    local coll, collItems = {}, {}
    local function Coll(item)
        local c = coll[item]
        if not c then c = { bank = 0, guild = 0, names = nil } coll[item] = c collItems[#collItems + 1] = item end
        return c
    end
    for _, r in ipairs(rowsIn) do
        if (r.fromBank or 0) + (r.fromGuild or 0) > 0 then
            local c = Coll(r.item)
            c.bank, c.guild = c.bank + (r.fromBank or 0), c.guild + (r.fromGuild or 0)
        end
    end
    for item, f in pairs(collectFor) do
        local c = Coll(item)
        c.bank, c.guild, c.names = c.bank + f.bank, c.guild + f.guild, f.names
    end
    table.sort(collItems)
    for _, item in ipairs(collItems) do
        local c, base = coll[item], byItem[item]
        for _, where in ipairs({ "bank", "guild" }) do
            if c[where] > 0 then
                local meta = inp.stockMeta and inp.stockMeta(item, where) or {}
                out[#out + 1] = { kind = "collect", item = item, where = where, qty = c[where], at = meta.at, limited = meta.limited,
                    forNames = c.names, need = base and base.need, have = base and base.have, made = base and base.made,
                    madeRange = base and base.madeRange, options = {}, extra = 0 }
                totals.collect = totals.collect + 1
            end
        end
    end
    -- collect rows first (nothing to pay: go and take them), then the buy rows (they are the shopping), then the made ones; each group by item
    -- number, the bank before the guild bank
    local KIND = { collect = 1, buy = 2, make = 3 }
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return KIND[a.kind] < KIND[b.kind] end
        if a.item ~= b.item then return a.item < b.item end
        return (a.where or "") < (b.where or "")
    end)
    return { rows = out, totals = totals, unknownBags = unknownBags }
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
local SUBJECT = { vendor = "Buying from the vendor", auction = "Buying at the auction house", make = "Making this" }
local AGAINST = { vendor = "buying from the vendor", auction = "buying at the auction house", make = "making it" }

local MAKE_WHY = {
    unsupported = "A recipe for this has materials TwichUI can't count, so it isn't suggested.",
    noamount = "A recipe for this has an output TwichUI doesn't know yet, so it isn't suggested.",
    range = "A recipe for this makes a varying amount, so it isn't suggested.",
    circular = "Its recipe uses the item itself, so it isn't suggested.",
    chain = "Making it would need another made material, so it isn't suggested.",
    toomany = "It would take more crafts than a queue entry holds.",
}

-- One short sentence on how the options compare (plain words, no amounts: the tooltip has those).
function Sh.Explain(row)
    local opts = row.options
    local priced = {}
    for _, k in ipairs(Sh.ORDER) do
        local o = opts[k]
        if o and o.cost and (k ~= "make" or o.state == "ok") then priced[#priced + 1] = { kind = k, cost = o.cost } end
    end
    local text
    if row.reagentOnly then
        text = "Needed to make " .. table.concat(row.forNames or { "something" }, " and ") .. "."
    elseif #priced >= 2 then
        local win, against = priced[1], nil
        for _, p in ipairs(priced) do
            if p.cost < win.cost then win = p end   -- the first of equals wins, as in the suggestion
        end
        for _, p in ipairs(priced) do
            if p ~= win and (not against or p.cost < against.cost) then against = p end
        end
        text = ("%s looks cheaper than %s."):format(SUBJECT[win.kind], AGAINST[against.kind])
    elseif #priced == 1 then
        text = ("Only %s has a price."):format(({ vendor = "the vendor", auction = "the auction house", make = "making it" })[priced[1].kind])
    else
        local v, a, m = opts.vendor, opts.auction, opts.make
        if v and v.state == "noprice" then text = "A vendor sells it, but its price hasn't been seen yet."
        elseif v and v.state == "limited" then text = "A vendor had too few when you last saw it."
        elseif a and a.state == "few" then text = "Not enough are listed at the auction house."
        elseif m and MAKE_WHY[m.state] then text = MAKE_WHY[m.state]
        else text = "No price known yet. Scan prices at the auction house, or visit a vendor that sells it." end
    end
    if row.picked and row.suggested and row.source ~= row.suggested then
        text = text .. (" You chose %s."):format(({ vendor = "the vendor", auction = "the auction house", make = "to make it" })[row.source])
    elseif row.pickLost then
        text = text .. " Your earlier choice is no longer possible."
    end
    return text
end

-- Why a source can't be chosen for this row: one plain sentence, or nil when it can (the same reasons Explain gives, for the disabled choice's tooltip)
function Sh.WhyNot(row, kind)
    if Usable(row.options[kind]) and not (kind == "make" and row.kind == "buy" and row.reagentOnly) then return nil end
    local o = row.options[kind]
    if kind == "vendor" then
        if not o then return "No vendor that sells this has been seen." end
        if o.state == "noprice" then return "A vendor sells it, but its price hasn't been seen yet." end
        if o.state == "limited" then return "A vendor had too few when you last saw it." end
        return "The vendor's price isn't known."
    elseif kind == "auction" then
        if not o then return "No auction price is saved for this. Scan prices at the auction house." end
        if o.state == "few" then return "Not enough are listed at the auction house." end
        return "The auction price isn't known."
    end
    if row.kind == "buy" and row.reagentOnly then return "It is bought: it is a reagent of something you are making." end
    if not o then return "No recipe you know makes this." end
    return MAKE_WHY[o.state] or "It can't be made from what is known."
end

-- The player may pick among these for a row, in the order they are cycled: vendor, auction, make (each only when it exists and can be done).
-- A made material's reagents (reagentOnly rows) are bought, so they offer no making.
function Sh.Choices(row)
    local out = {}
    for _, k in ipairs(Sh.ORDER) do
        if Usable(row.options[k]) and not (k == "make" and row.kind == "buy" and row.reagentOnly) then out[#out + 1] = k end
    end
    return out
end

-- The lines of the row's tooltip: { text } or { left, right }. name(item) -> text; money(copper) -> text; ageText(seconds) -> text.
-- now: the time the ages are counted to.
function Sh.Basis(row, name, money, ageText, now)
    local out = {}
    local function L(left, right) out[#out + 1] = { left, right } end
    L(name(row.item))
    if row.kind == "collect" then
        local guild = row.where == "guild"
        L(("Collect %d from %s"):format(row.qty, guild and "the guild bank" or "your bank"))
        if row.at and now then L("  seen " .. ageText(math.max(0, now - row.at)) .. " (remembered, not live)") end
        if guild then
            L(row.limited and "  Shared stock; a withdrawal limit may apply, so it isn't promised."
                or "  Shared stock: other members can take it too.")
        end
        if row.forNames then L("  Also for making " .. table.concat(row.forNames, " and ")) end
        L("  Nothing is taken out for you.")
        return out
    end
    if row.need then
        local line = ("%d needed"):format(row.need)
        if row.made then line = line .. (", %s%d from queued crafts"):format(row.madeRange and "at least " or "", row.made) end
        if row.have then line = line .. (", %d in bags"):format(row.have) end
        local stored = (row.fromBank or 0) + (row.fromGuild or 0)
        if stored > 0 then line = line .. (", %d to collect from storage"):format(stored) end
        L(line .. (row.short and row.short > 0 and (", " .. row.short .. " still needed") or ""))
    end
    if row.extra and row.extra > 0 then
        L(("%d more to buy for %s"):format(row.extra, table.concat(row.forNames or {}, " and ")))
    end
    local o = row.options
    local function Seen(at) return at and now and ageText(math.max(0, now - at)) or "at an unknown time" end
    if o.vendor then
        local v = o.vendor
        if v.state == "noprice" then
            L("Vendor", "price not seen yet")
        elseif v.quote then
            local q = v.quote
            if q.state == "limited" then
                L("Vendor", ("had only %d when seen %s"):format(q.avail, Seen(v.at)))
            else
                L("Vendor", ("%s for %d%s"):format(money(q.cost), q.items, q.surplus > 0 and (", " .. q.surplus .. " left over") or ""))
                L("  seen " .. Seen(v.at) .. " (stock can change)")
            end
        end
    end
    if o.auction then
        local a = o.auction
        if a.state == "few" then
            L("Auction house", ("only %d listed"):format(a.quote.total or 0))
        else
            local q = a.quote
            L("Auction house", (a.estimate and "about " or "") .. money(a.cost))
            if a.estimate then
                L("  " .. money(q.unit) .. " each is the cheapest listing" .. (q.listed and (" (" .. q.listed .. " at that price)") or "") ..
                    "; the rest may cost more")
            end
            L("  scanned " .. Seen(a.at) .. (q.complete == false and " (not a complete scan)" or ""))
        end
    end
    local m = o.make
    if m then
        if m.state == "ok" then
            L("Make", m.cost and ("worth " .. money(m.cost)) or "cost not known")
            L(("  %s: %d craft%s, %d made, %d left over"):format(m.rec.name, m.crafts, m.crafts == 1 and "" or "s", m.made, m.surplus))
            for _, r in ipairs(m.reagents) do
                local parts = {}
                if r.owned > 0 then
                    local stored = (r.bank or 0) + (r.guild or 0)
                    parts[#parts + 1] = r.owned .. " owned" .. (stored > 0 and (" (" .. stored .. " to collect)") or "")
                        .. (r.value and (" (worth " .. money(r.value) .. ")") or "")
                end
                if r.buy > 0 then parts[#parts + 1] = r.buy .. " to buy" .. (r.cost and (" for " .. money(r.cost)) or ", no price") end
                L(("  %d x %s"):format(r.qty, name(r.item)), table.concat(parts, ", "))
            end
            if m.cash then L("  Cash needed for the materials", money(m.cash)) end
            L("  Cooldowns, tools and stations aren't checked.")
        else
            L("Make", MAKE_WHY[m.state] and "not suggested" or m.state)
            if MAKE_WHY[m.state] then L("  " .. MAKE_WHY[m.state]) end
        end
    end
    return out
end
