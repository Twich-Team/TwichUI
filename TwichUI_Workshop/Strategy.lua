-- TwichUI Workshop: the crafting strategy (P2): plain words for the multilevel planner's plan, the cooperative job that computes it, and the
-- adapter that turns it into the rows the Shopping page draws
-- CraftPlanner.lua (P1) decides; this file connects it to the windows without changing it:
--   * Words: Summary / RangeText / Savings / Actions / Status say what a plan is and how sure it is ("Best verified plan", "Best plan found",
--     "Potential savings", "at least"), from the plan's own figures; nothing here is calculated again. Pure.
--   * Jobs: Request starts (or finds) the plan for one input SNAPSHOT, a key made of an epoch and what the plan is about. The work is
--     CP.Job, CP.STEP work units per frame, one first slice at once so a small plan is ready before the page is drawn. A job whose input changed
--     (Bump) is cancelled, a job that finishes after a newer request began is thrown away (generation token), and a result is never reused for a
--     key it was not computed for. Nothing runs when nothing is requested: the frame timer is rescheduled only while a job is unfinished.
--   * Adapter: Adapt turns a plan into Shopping.Plan's row shape (collect, buy and make rows, totals), keeping split quantities, combined demand,
--     collect rows, cost ranges and source reasons, so the Shopping page keeps its familiar interface. Shopping.lua's own planner stays as the
--     basic (one level) fallback; the page says which one it is showing.
--   * Ops / Detail: the crafts a confirmed plan adds to the queue, and the flat list of rows the full strategy view shows.
-- No frames, no saved data, no game calls (a timer and a clock are used when the game has them).

local R = TwichUI
local W = R.Workshop
local CP, Sh = W.CraftPlanner, W.Shopping
local St = {}
W.Strategy = St

St.epoch = 0            -- changes whenever something a plan depends on changed (Bump)
St.FIRST = 3            -- slices run at once when a plan is requested (about 1 ms each offline; the rest go one per frame)
St.onChange = nil       -- fn() called when a job finished (or was dropped by a change) and the page should be drawn again

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
-- A range of copper as words: "A", "A to B", or "at least A" (high nil: the upper end is open). `lowerOnly`: some price is missing, so even the
-- lower figure is only what is known.
function St.RangeText(r, money, lowerOnly)
    if not r or r.low == nil then return nil end
    if lowerOnly or r.high == nil then return "at least " .. money(r.low) end
    if r.high == r.low then return money(r.low) end
    return money(r.low) .. " to " .. money(r.high)
end

-- How a cost is shown: "simple" (the default: one planning figure, its uncertainty in one visible word, the range in the tooltip) or
-- "detailed" (the range inline). Session keeps the player's choice (Session.PriceDetail) and sets St.detailed; every page reads it here, so
-- Workshop has one format.
St.detailed = false

-- One cost for the page: text, tip. The figure is the planner's own lower bound (plans are compared on it), so a figure that is not exact always
-- says so: "from X" when the upper end is known, "at least X" when it is open or a price is missing. Never a guaranteed total from a lower bound,
-- and never an invented upper end. tip: the range and why it is one (nil for an exact figure).
function St.CostText(r, money, lowerOnly, detailed)
    if not r or r.low == nil then return nil end
    if detailed == nil then detailed = St.detailed end
    if lowerOnly then return "at least " .. money(r.low), "Some prices are missing, so this is only the part that is known." end
    if r.high == nil then return "at least " .. money(r.low), "Part of it is an auction estimate with no known upper end: buying that many may cost more." end
    if r.high == r.low then return money(r.low), nil end
    local tip = ("Between %s and %s. Auctions may require buying whole stacks."):format(money(r.low), money(r.high))
    if detailed then return money(r.low) .. " to " .. money(r.high), tip end
    return "from " .. money(r.low), tip
end

-- How sure the plan is, in the words the windows use. tone: "good" | "warn" | "quiet".
function St.Status(s)
    if not s or s.status == "empty" then return "Nothing to plan", "quiet" end
    if s.status == "unavailable" then return "No plan could be made", "warn" end
    if s.status == "incomplete" then return "Partial plan: some prices or recipes are missing", "warn" end
    if s.proven then return "Best verified plan", "good" end
    return "Best plan found", "good"
end

-- "Craft 2 \194\183 Buy 3 \194\183 Collect 1": how many different recipes are made, materials bought, and materials taken from storage
function St.Counts(plan)
    local collect, seen = 0, {}
    for _, c in ipairs(plan.collect or {}) do
        if not seen[c.item] then seen[c.item] = true collect = collect + 1 end
    end
    local buy = 0
    for _, l in ipairs(plan.items or {}) do
        if l.source == "vendor" or l.source == "auction" or l.source == "none" then buy = buy + 1 end
    end
    return { craft = #(plan.crafts or {}), buy = buy, collect = collect, operations = plan.summary and plan.summary.crafts or 0 }
end

function St.Actions(plan)
    local n, parts = St.Counts(plan), {}
    if n.craft > 0 then parts[#parts + 1] = "Craft " .. n.craft end
    if n.buy > 0 then parts[#parts + 1] = "Buy " .. n.buy end
    if n.collect > 0 then parts[#parts + 1] = "Collect " .. n.collect end
    if #parts == 0 then return "Nothing to craft, buy or collect" end
    return table.concat(parts, " \194\183 ")
end

-- What to do, at a glance: "Buy 3 materials", "Collect 2 materials", or "Craft 2 intermediates \194\183 Buy 2 \194\183 Collect 1" when there is
-- more than one kind of step (the first part says what the counts are; the others follow it)
function St.Headline(plan)
    local n = St.Counts(plan)
    local function Things(k, one, many) return k == 1 and one or many end
    local parts = {}
    if n.craft > 0 then parts[#parts + 1] = ("Craft %d %s"):format(n.craft, Things(n.craft, "intermediate", "intermediates")) end
    if n.buy > 0 then parts[#parts + 1] = #parts == 0 and ("Buy %d %s"):format(n.buy, Things(n.buy, "material", "materials")) or ("Buy " .. n.buy) end
    if n.collect > 0 then parts[#parts + 1] = #parts == 0 and ("Collect %d %s"):format(n.collect, Things(n.collect, "material", "materials")) or ("Collect " .. n.collect) end
    if #parts == 0 then return "Nothing to craft, buy or collect" end
    return table.concat(parts, " \194\183 ")
end

-- The saving against buying every missing material directly, in words. Returns label, text, tone, and a sentence for the tooltip.
--   "Savings" only when the plan is certainly cheaper (the ends of the two ranges do not overlap); otherwise "Potential savings" with a
--   figure that is only a comparison of the lower bounds; nothing when a price is missing (no figure is invented). "No saving" (buying directly is
--   as good) and "Unknown" (it can't be compared) are told apart.
St.NO_SAVING = "Buying the materials directly is the best supported option."
St.NO_COMPARE = "Not enough price information to compare every route."
function St.Savings(s, money)
    local sv = s and s.savings
    if not sv then return "Potential savings", "Unknown", "quiet", St.NO_COMPARE end
    if sv.confident then
        return "Savings", "at least " .. money(sv.low), "good", "Certainly cheaper than buying directly: the price ranges do not overlap."
    end
    if sv.lowerBounds and sv.lowerBounds > 0 then
        return "Potential savings", "about " .. money(sv.lowerBounds), "warn", "Cheaper at the lowest prices, but the price ranges overlap, so it is not certain."
    end
    return "Potential savings", "No saving", "quiet", St.NO_SAVING
end

-- Everything the compact Crafting Strategy block shows, as text. money(copper) -> text.
--   status, tone        how sure the plan is (St.Status)
--   headline, actions   what to do (St.Headline; the old counts line St.Actions)
--   cost, costTip       the planning figure: the optimized economic cost (St.CostText; "from" / "at least" when it is not exact)
--   cash, cashTip       the gold needed now (only what is bought)
--   direct, directTip   buying every missing material directly (only when no price is missing)
--   savingsLabel, savings, savingsTone, savingsWhy   St.Savings; saveLine: one short sentence ("Save about 12s", or St.NO_SAVING / St.NO_COMPARE)
--   economic            the old inline range text (St.RangeText), kept for the Detailed presentation and the tests
function St.Summary(plan, money, detailed)
    local s = plan.summary
    local text, tone = St.Status(s)
    local out = { status = text, tone = tone, actions = St.Actions(plan), headline = St.Headline(plan), complete = s.complete,
        ok = s.status == "complete" or s.status == "incomplete" }
    local lowerOnly = s.missing and s.missing > 0
    local cashOnly = s.cashMissing and s.cashMissing > 0
    out.economic = St.RangeText(s.economic, money, lowerOnly)
    out.cost, out.costTip = St.CostText(s.economic, money, lowerOnly, detailed)
    out.cash, out.cashTip = St.CostText(s.cash, money, cashOnly, detailed)
    if s.baseline and s.baseline.missing == 0 then out.direct, out.directTip = St.CostText(s.baseline.economic, money, false, detailed) end
    out.savingsLabel, out.savings, out.savingsTone, out.savingsWhy = St.Savings(s, money)
    local sv = s.savings
    if sv and sv.confident then out.saveLine = "Saves at least " .. money(sv.low)
    elseif sv and sv.lowerBounds and sv.lowerBounds > 0 then out.saveLine = "Could save about " .. money(sv.lowerBounds)
    else out.saveLine = out.savingsWhy end
    out.owned = s.owned or 0
    return out
end

---------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------
local slots, order = {}, {}      -- [name] = slot; the names in the order they were first used (a job's turn)
local gen = 0                    -- the generation of the newest job: a finished job of an older one is dropped
local ticking = false
local CACHE_MAX = 8
local stats = { started = 0, finished = 0, cancelled = 0, dropped = 0, failed = 0, steps = 0, longest = 0, work = 0 }

local function Clock()
    if debugprofilestop then return debugprofilestop() end
    if os and os.clock then return os.clock() * 1000 end
    return 0
end

local function Slot(name)
    local s = slots[name]
    if not s then
        s = { name = name, cache = {}, keys = {} }
        slots[name] = s
        order[#order + 1] = name
    end
    return s
end

local function Remember(s, key, result)
    if not s.cache[key] then
        s.keys[#s.keys + 1] = key
        if #s.keys > CACHE_MAX then s.cache[table.remove(s.keys, 1)] = nil end
    end
    s.cache[key] = result
end

local function Changed()
    if St.onChange then St.onChange() end
end

local pending = false
local function Later(fn)
    if C_Timer and C_Timer.After then C_Timer.After(0, fn) end
end

-- one slice of a slot's job. Returns true when the job finished (the result is kept) or failed.
local function Advance(s)
    local job, mine = s.job, s.gen   -- the slot's own generation: a request of another slot never makes this job stale
    if not job then return true end
    local t0 = Clock()
    local ok, done = pcall(job.Step, job, CP.STEP)
    local dt = Clock() - t0
    stats.steps, stats.work = stats.steps + 1, stats.work + dt
    if dt > stats.longest then stats.longest = dt end
    if not ok then
        s.job, s.state, s.err = nil, "failed", tostring(done)
        stats.failed = stats.failed + 1
        return true
    end
    if not done then return false end
    local result = job:Result()
    s.job = nil
    if s.gen ~= mine then   -- a newer request of this slot began while this ran: its answer is not wanted
        stats.dropped = stats.dropped + 1
        s.state = "stale"
        return true
    end
    s.state, s.result, s.resultKey = "ready", result, s.key
    Remember(s, s.key, result)
    stats.finished = stats.finished + 1
    return true
end

local function Active(only)
    for _, name in ipairs(order) do
        local s = slots[name]
        if (not only or name == only) and s.job and s.state == "planning" then return s end
    end
end

local Tick
local function Kick()
    if ticking then return end
    ticking = true
    Later(function() if ticking then Tick() end end)
end

-- One frame's work: the first unfinished job gets one slice; the page is told when one finished. Another frame is asked for only while a job is
-- still unfinished.
Tick = function()
    ticking = false
    local s = Active()
    if not s then return end
    local done = Advance(s)
    if Active() then Kick() end
    if done then Changed() end
end

-- Runs jobs to the end without a timer (the tests, and nothing else). Returns how many slices were run.
function St.Pump(limit, only)
    local n = 0
    while Active(only) and n < (limit or 100000) do
        Advance(Active(only))
        n = n + 1
    end
    ticking = false
    return n
end

-- Forgets one slot (its job is cancelled, its kept plans dropped): the developer Test Lab uses a slot of its own and drops it, never Reset
function St.Drop(name)
    local s = slots[name]
    if not s then return end
    if s.job then s.job:Cancel(); stats.cancelled = stats.cancelled + 1 end
    slots[name] = nil
    for i, n in ipairs(order) do if n == name then table.remove(order, i) break end end
end

-- The plan for one snapshot of input. name: the slot ("queue", "opp", "confirm"); key: a string that changes whenever anything the plan depends on
-- changes (the caller builds it: Session.PlanKey); make(): returns the planner's input and options, called only when work must be started.
-- Returns state, plan, why: "ready" (plan is for exactly this key), "planning" (a job is running for it), "failed" (why). `manual`: make no frame timer.
function St.Request(name, key, make, manual)
    local s = Slot(name)
    local hit = s.cache[key]
    if hit then
        s.key, s.state, s.result, s.resultKey, s.job = key, "ready", hit, key, nil
        return "ready", hit
    end
    if s.key == key then
        if s.state == "planning" and s.job then return "planning" end
        if s.state == "failed" then return "failed", nil, s.err end
    end
    if s.job then
        s.job:Cancel()
        s.job = nil
        stats.cancelled = stats.cancelled + 1
    end
    gen = gen + 1
    s.gen, s.key, s.state, s.err = gen, key, "planning", nil
    local ok, job = pcall(function()
        local inp, opt = make()
        return CP.Job(inp, opt)
    end)
    if not ok then
        s.state, s.err = "failed", tostring(job)
        stats.failed = stats.failed + 1
        return "failed", nil, s.err
    end
    s.job = job
    stats.started = stats.started + 1
    -- the first slices are run at once (St.FIRST of them, a few milliseconds at most): a small plan is ready before the page is drawn, so a click on a
    -- source does not show the old list for a frame. Anything longer goes on one slice per frame.
    for _ = 1, St.FIRST do
        if Advance(s) then
            if s.state == "ready" then return "ready", s.result end
            return s.state, nil, s.err
        end
    end
    if not manual then Kick() end   -- (manual: the caller steps it with Pump, and no timer is made: the developer Test Lab)
    return "planning"
end

-- The last finished plan of a slot and the key it was made for (to show while a newer one is computed, always labelled as not current)
function St.Last(name)
    local s = slots[name]
    if s and s.result then return s.result, s.resultKey end
end

-- The kept plan of a slot for exactly this key, or nil
function St.Peek(name, key)
    local s = slots[name]
    return s and s.cache[key] or nil
end

function St.State(name)
    local s = slots[name]
    return s and s.state or nil
end

-- Something a plan depends on changed: every running job is cancelled and every kept result is forgotten (the keys carry the epoch, so none
-- could match again). The page is told once, so it asks for the plan again.
function St.Bump()
    St.epoch = St.epoch + 1
    local dropped = false
    for _, s in pairs(slots) do
        if s.job then
            s.job:Cancel()
            s.job, s.state, s.key = nil, "stale", nil
            stats.cancelled = stats.cancelled + 1
            dropped = true
        end
        s.cache, s.keys = {}, {}
    end
    if dropped and not pending then
        pending = true
        Later(function() pending = false; Changed() end)
    end
end

-- The window closed: nothing is kept and nothing runs
function St.Reset()
    for _, s in pairs(slots) do
        if s.job then s.job:Cancel(); stats.cancelled = stats.cancelled + 1 end
    end
    slots, order, ticking = {}, {}, false
end

function St.Stats()
    local running = 0
    for _, s in pairs(slots) do if s.job then running = running + 1 end end
    return { started = stats.started, finished = stats.finished, cancelled = stats.cancelled, dropped = stats.dropped, failed = stats.failed,
        steps = stats.steps, longest = stats.longest, work = stats.work, running = running, epoch = St.epoch }
end
function St.ResetStats() for k in pairs(stats) do stats[k] = 0 end end

---------------------------------------------------------------------------
-- The adapter: a plan as Shopping.Plan's rows
---------------------------------------------------------------------------
local function Unique(list, v)
    for _, x in ipairs(list) do if x == v then return end end
    list[#list + 1] = v
end

-- the cheaper way to buy, from the options' costs (the vendor on a tie), as Shopping.Suggest does for the two buying sources
local function CheaperBuy(opts)
    local best, cost
    for _, k in ipairs({ "vendor", "auction" }) do
        local o = opts[k]
        if o and o.cost and (not cost or o.cost < cost) then best, cost = k, o.cost end
    end
    return best
end

-- the source Workshop would suggest for an item the player chose a source for: the same plan worked out without any of the player's choices
-- (ctx.suggest[item]), or nil while that plan is still being worked out. An item with no choice of the player's suggests what the plan uses.
local function Suggestion(ctx, line, chosen)
    if not line.picked then return chosen end
    return ctx.suggest and ctx.suggest[line.item] or nil
end

-- The make option of a row as Shopping's views read it: kind, state, rec, crafts, made, surplus, reagents ({ item, qty }), planned = true (the cost is
-- part of the whole plan, so it has no figure of its own here)
local function MakeOption(step, rec)
    return { kind = "make", state = "ok", planned = true, rec = rec or { id = step.recipe, name = step.name }, crafts = step.crafts,
        perCraft = step.perCraft, made = step.produced, surplus = step.leftover, reagents = step.reagents, step = step }
end

-- A recipe the planner could use to make a bought item, as a make option (the crafts it would take are worked out from the recipe). Nil when the
-- recipe is not usable under P1's contract: fixed output, countable materials, not using its own output, not refused by the planner.
local function MakeFromRecipe(rec, item, rest, refused)
    if type(rec) ~= "table" or refused[rec.id] then return nil end
    local lo = rec.outMin
    if not (lo and lo > 0 and lo == (rec.outMax or lo) and type(rec.mats) == "table" and #rec.mats > 0 and #rec.mats <= 16) then return nil end
    for _, m in ipairs(rec.mats) do if m.item == item then return nil end end
    local crafts = math.ceil(rest / lo)
    local reagents = {}
    for _, m in ipairs(rec.mats) do reagents[#reagents + 1] = { item = m.item, qty = m.qty * crafts } end
    return { kind = "make", state = "ok", planned = true, rec = rec, crafts = crafts, perCraft = lo, made = crafts * lo, surplus = crafts * lo - rest, reagents = reagents }
end

-- ctx: { mrows = Materials.Rows, inp = the planner's input (its price, vendor and sells functions are used for the options), recById(id),
--        stockMeta(item, where), suggest = { [item] = "vendor" | "auction" | "make" } (the plan without the player's choices, when known) }
-- Returns Shopping.Plan's { rows, totals, unknownBags } plus engine = "multilevel" and plan (the planner's result).
function St.Adapt(plan, ctx)
    local byItem = {}
    for _, r in ipairs(ctx.mrows or {}) do byItem[r.item] = r end
    local s = plan.summary
    local memo = {}
    local stepNames = {}
    for _, c in ipairs(plan.crafts or {}) do stepNames[c.recipe] = c.name end
    local rows = {}
    local totals = { cash = s.cash.low or 0, low = s.cash.low or 0, high = s.cash.high, open = s.cash.high == nil, priced = 0, missing = 0,
        estimate = false, makes = #(plan.crafts or {}), incomplete = false, collect = 0 }
    -- who uses an item as a reagent: the names of the crafts (one per recipe)
    local function ForNames(line)
        local names = {}
        for _, u in ipairs(line.usedBy or {}) do
            if u.recipe and stepNames[u.recipe] then Unique(names, stepNames[u.recipe]) end
        end
        return #names > 0 and names or nil
    end
    local forByItem = {}
    for _, line in ipairs(plan.items or {}) do forByItem[line.item] = ForNames(line) end

    for _, line in ipairs(plan.items or {}) do
        local base = byItem[line.item]
        local item = line.item
        local fields = { item = item, need = line.need, made = (line.queued or 0) > 0 and line.queued or nil, madeRange = base and base.madeRange,
            have = base and base.have, fromBank = base and base.fromBank, fromGuild = base and base.fromGuild, multilevel = true, line = line }
        if line.source == "make" then
            local opts = Sh.BuyOptions(ctx.inp, item, line.rest, memo)
            local mk = MakeOption(line.make, ctx.recById and ctx.recById(line.make.recipe))
            opts.make = mk
            local row = fields
            if row.have == nil and ctx.inp.have then row.have = ctx.inp.have(item) end
            row.kind, row.options, row.source, row.make = "make", opts, "make", mk
            row.short, row.extra, row.qty = base and base.short or line.rest, 0, line.rest
            row.reagentOnly = (base == nil or (base.short or 0) <= 0) or nil
            row.forNames = forByItem[item]
            row.picked, row.pickLost = line.picked == "make" or nil, line.pickLost
            row.suggested = Suggestion(ctx, line, "make")
            if line.countsUnknown then row.uncertain = "Your bag count of this couldn't be read, so none is assumed owned." end
            rows[#rows + 1] = row
        elseif line.source == "vendor" or line.source == "auction" or line.source == "none" then
            local qty = line.rest
            local opts = Sh.BuyOptions(ctx.inp, item, qty, memo)
            local refused = {}
            for _, rj in ipairs(line.rejected or {}) do if rj.id then refused[rj.id] = true end end
            local cands = ctx.inp.recipes and ctx.inp.recipes(item) or {}
            for i = 1, math.min(#cands, CP.LIMITS.candidates) do
                local mo = MakeFromRecipe(cands[i], item, qty, refused)
                if mo then opts.make = mo break end
            end
            local src = line.source ~= "none" and line.source or nil
            -- a source with no usable price (nothing listed that covers it, a vendor price never seen) is not named as the way to get it, unless the
            -- player chose it: the row says "No source" and why, as Shopping always has
            if src and not line.picked and not (opts[src] and opts[src].cost) then src = nil end
            local short = math.min(qty, base and base.short or 0)
            local row = fields
            if row.have == nil and ctx.inp.have then row.have = ctx.inp.have(item) end   -- a material only the plan needs (a made material's reagent): what the bags hold
            row.kind, row.options, row.source = "buy", opts, src
            row.short, row.qty, row.extra = short, qty, qty - short
            row.reagentOnly = short == 0 or nil
            row.forNames = qty > short and forByItem[item] or nil
            row.picked, row.pickLost = (line.picked ~= nil and line.picked == src) or nil, line.pickLost
            row.suggested = src and Suggestion(ctx, line, src) or CheaperBuy(opts)
            local o = src and opts[src] or nil
            if o and o.cost and line.buy and line.buy.low then
                row.cash, row.at, row.estimate = o.cost, o.at, o.estimate
                row.costState, row.low, row.high, row.costInfo = (o.kind == "vendor" and "exact" or o.state), o.low or o.cost, o.high, o.info
                if o.quote and o.quote.surplus and o.quote.surplus > 0 then row.surplus = o.quote.surplus end
                totals.priced = totals.priced + 1
                if o.estimate then totals.estimate = true end
                if o.quote and o.quote.complete == false then totals.incomplete = true end
            else
                totals.missing = totals.missing + 1
            end
            local au = opts.auction
            if row.suggested == "auction" and au and (au.estimate or au.state == "range") then
                row.uncertain = au.state == "range" and "Auctions may require buying larger stacks." or "The auction price is an estimate: more may cost more."
            end
            rows[#rows + 1] = row
        end
    end
    for _, c in ipairs(plan.collect or {}) do
        local base = byItem[c.item]
        local meta = ctx.stockMeta and ctx.stockMeta(c.item, c.where) or {}
        rows[#rows + 1] = { kind = "collect", item = c.item, where = c.where, qty = c.qty, at = meta.at, limited = meta.limited,
            forNames = forByItem[c.item], need = base and base.need, have = base and base.have, made = base and base.made,
            madeRange = base and base.madeRange, options = {}, extra = 0, multilevel = true }
        totals.collect = totals.collect + 1
    end
    local KIND = { collect = 1, buy = 2, make = 3 }
    table.sort(rows, function(a, b)
        if a.kind ~= b.kind then return KIND[a.kind] < KIND[b.kind] end
        if a.item ~= b.item then return a.item < b.item end
        return (a.where or "") < (b.where or "")
    end)
    local unknown = 0
    for _, r in ipairs(ctx.mrows or {}) do if r.short == nil then unknown = unknown + 1 end end
    return { rows = rows, totals = totals, unknownBags = unknown, engine = "multilevel", plan = plan }
end

-- One sentence on why a row has its source (plain words; the numbers are in the details). Adapted rows only. Certainty comes from the planner's
-- comparison of the two plans: "lower" means the plan is certainly cheaper (its price range ends below the other's start), "overlap" that the order is
-- not certain.
local SUBJECT = { vendor = "Buying from the vendor", auction = "Buying at the auction house" }
local AGAINST = { vendor = "buying from the vendor", auction = "buying at the auction house" }
local function Sure(compare)
    if compare == "lower" then return " It is certainly cheaper." end
    return " The price ranges overlap, so it isn't certain."
end

function St.RowWhy(row)
    local line = row.line
    local opts = row.options or {}
    local text
    if row.kind == "collect" then return nil end
    local function Alt(kind)
        for _, a in ipairs(line and line.alternatives or {}) do if a.kind == kind and a.ok ~= false then return a end end
    end
    if row.kind == "make" then
        local mk = row.make
        text = ("The plan makes this: %d %s of %s."):format(mk.crafts, mk.crafts == 1 and "craft" or "crafts", mk.rec.name)
        local buy = Alt("buy")
        local how = CheaperBuy(opts) or "auction"
        if buy then
            if buy.compare == "lower" or buy.compare == "overlap" then
                text = ("Making this looks cheaper than %s."):format(AGAINST[how]) .. Sure(buy.compare)
            elseif buy.compare == "equal" then text = text .. " It costs the same as buying it."
            elseif buy.compare == "higher" then text = text .. " Buying it would cost less, but you chose to make it."
            end
        end
    elseif row.reagentOnly then
        text = "Needed to make " .. table.concat(row.forNames or { "something" }, " and ") .. "."
    else
        local make = Alt("make")
        if make and row.source and (make.compare == "lower" or make.compare == "overlap") then
            text = SUBJECT[row.source] .. " looks cheaper than making it." .. Sure(make.compare)
        elseif make and row.source and make.compare == "equal" then
            text = "Buying costs the same as making it."
        elseif make and row.source and make.compare == "higher" then
            text = "Making it would cost less, but you chose to buy it."
        else
            text = Sh.Explain({ options = { vendor = opts.vendor, auction = opts.auction }, source = row.source, suggested = row.source, picked = false })
        end
    end
    if row.picked and row.suggested and row.source ~= row.suggested then
        text = text .. (" You chose %s."):format(({ vendor = "the vendor", auction = "the auction house", make = "to make it" })[row.source] or "this")
    elseif row.pickLost then
        text = text .. " Your earlier choice is no longer possible."
    end
    return text
end

---------------------------------------------------------------------------
-- What a confirmed plan adds to the queue
---------------------------------------------------------------------------
-- The crafts of a plan in the order they can be done (the planner's own order), each { recipe, name, crafts, produces = item, makes = total }.
-- `final` (a recipe the player is also adding, not queued yet) is appended last: it is made from what the others make.
function St.Ops(plan, final)
    local ops = {}
    for _, c in ipairs(plan and plan.crafts or {}) do
        ops[#ops + 1] = { recipe = c.recipe, name = c.name, crafts = c.crafts, produces = c.item, makes = c.produced }
    end
    if final then ops[#ops + 1] = { recipe = final.id, name = final.name, crafts = final.crafts or 1, produces = final.outItem, final = true } end
    return ops
end

---------------------------------------------------------------------------
-- The full strategy: a checklist
---------------------------------------------------------------------------
-- The comparison of one item's chosen way with its other ways, in ordinary words, from the planner's own alternatives (P1: each alternative
-- is the WHOLE plan with only this item's choice changed, so the figures are plan totals, never an invented per-item share). Returns
-- short, lines, each: short is a few words for the row ("saves 4s", "too close to call"), lines the tooltip's { left, right } pairs, each the
-- one sentence of each alternative (in the planner's order).
--   compare is the chosen plan against the alternative: "lower" (the plan is certainly cheaper), "higher" (the alternative certainly is: the
--   player's own choice), "equal", "overlap" (the order isn't certain) or "unknown" (a price is missing).
local CHOSEN = { make = "crafting it", vendor = "buying it", auction = "buying it", none = "this way" }
function St.Compare(line, money)
    local alts = line and line.alternatives
    if not (alts and #alts > 0) then return nil, nil end
    local lines, each, short = {}, {}, nil
    local mine = line.source == "make" and "Craft" or "Buy"
    for _, a in ipairs(alts) do
        local other = a.kind == "make" and "Craft" or "Buy"
        local what = a.kind == "make" and ("Crafting it" .. (a.name and (" (" .. a.name .. ")") or "")) or "Buying it"
        local text
        if a.ok == false then
            text = what .. ": " .. (CP.WHY[a.why] or "not possible")
        elseif a.difference == nil or a.compare == "unknown" then
            text = what .. ": a price is missing, so it can't be compared."
        elseif a.compare == "equal" or a.difference == 0 then
            text = what .. " costs the same."
            short = short or "same either way"
        elseif a.difference > 0 then
            if a.compare == "lower" then
                text = ("%s costs %s more."):format(what, money(a.difference))
                short = short or ((mine == "Craft" and "saves " or "cheaper by ") .. money(a.difference))
            else
                text = ("%s costs about %s more, but the costs are too close to call."):format(what, money(a.difference))
                short = short or "too close to call"
            end
        else
            text = ("%s would cost %s less; you chose %s."):format(what, money(-a.difference), CHOSEN[line.source] or "this way")
            short = short or "your choice"
        end
        lines[#lines + 1] = { text }
        each[#each + 1] = text
        if a.ok ~= false and a.economic and a.economic.low then
            lines[#lines + 1] = { ("Plan if %s"):format(other == "Craft" and "crafted" or "bought"), (St.CostText(a.economic, money)) }
        end
    end
    return short, lines, each
end

-- Notes on what the plan assumes (the planner's reason sentences, rejected recipes and the two standing caveats): one list, shown behind the
-- strategy view's small "Notes" control, never as paragraphs in the checklist
function St.Notes(plan, name)
    local s = plan.summary
    local out, seen = {}, {}
    local function Add(t) if t and not seen[t] then seen[t] = true out[#out + 1] = t end end
    for _, code in ipairs(s.reasons or {}) do Add(CP.WHY[code]) end
    for _, code in ipairs(s.limits or {}) do Add(CP.WHY[code]) end
    for _, rj in ipairs(plan.rejected or {}) do Add(name(rj.item) .. ": " .. (CP.WHY[rj.why] or "A recipe isn't used.")) end
    Add("Owned materials lower the gold you spend, not the estimated cost: they count at what they would cost.")
    Add("Cooldowns, crafting stations and recipe requirements aren't checked. Nothing is bought or crafted for you.")
    return out
end

-- Rows for the strategy view's scrolling list, in the order the player works through them:
--   { kind = "head" | "step" | "vendor" | "auction" | "buy" | "collect" | "own" | "toggle" | "alt", title, detail, right, item, tone, tip }
-- title is the action ("Craft 3 \195\151 Bolt of Woolen Cloth", "Buy 1 \195\151 Fine Thread", "Collect 2 \195\151 Rugged Leather"); detail is a few
-- words; tip holds the precise numbers ({ left, right } lines) for the row's tooltip, under the item's own tooltip. The other ways the planner
-- considered are one "toggle" row, collapsed unless `showAlts`. name(item) -> text; money(copper) -> text; ageText(seconds) -> text; now: the
-- time ages are counted to.
function St.Detail(plan, name, money, ageText, now, showAlts)
    local out = {}
    local function Row(kind, title, detail, right, item, tone, tip)
        out[#out + 1] = { kind = kind, title = title, detail = detail, right = right, item = item, tone = tone, tip = tip }
    end
    local function Head(title) Row("head", title) end
    local function Seen(at) if at and now then return "seen " .. ageText(math.max(0, now - at)) end return nil end
    local lines = {}
    for _, l in ipairs(plan.items or {}) do lines[l.item] = l end

    if #plan.crafts > 0 then
        Head("Craft")
        for _, c in ipairs(plan.crafts) do
            local tip = { { "Makes", tostring(c.produced) } }
            for _, rg in ipairs(c.reagents) do tip[#tip + 1] = { "Uses " .. rg.qty .. " \195\151 " .. name(rg.item) } end
            if c.leftover > 0 then tip[#tip + 1] = { "Left over", tostring(c.leftover) } end
            local short, cmp = St.Compare(lines[c.item], money)
            for _, x in ipairs(cmp or {}) do tip[#tip + 1] = x end
            local detail = ("makes %d"):format(c.produced) .. (c.leftover > 0 and (", %d spare"):format(c.leftover) or "")
            Row("step", ("Craft %d \195\151 %s"):format(c.crafts, c.name), detail, short or "", c.item, "make", tip)
        end
    end

    local vendor, auction, missing = {}, {}, {}
    for _, l in ipairs(plan.items or {}) do
        local b = l.buy
        if b then
            if not b.low then missing[#missing + 1] = l
            elseif b.source == "vendor" then vendor[#vendor + 1] = l
            else auction[#auction + 1] = l end
        end
    end
    local function BuyRow(kind, l)
        local b = l.buy
        local text, rangeTip = St.CostText({ low = b.low, high = b.high }, money)
        local tip = {}
        if rangeTip then tip[#tip + 1] = { rangeTip } end
        if b.surplus and b.surplus > 0 then tip[#tip + 1] = { "Left over", tostring(b.surplus) } end
        local age = Seen(b.at)
        if age then tip[#tip + 1] = { "Price", age .. (b.freshness == "old" and " (old)" or "") } end
        if b.complete == false then tip[#tip + 1] = { "From a scan that didn't finish." } end
        local _, cmp = St.Compare(l, money)
        for _, x in ipairs(cmp or {}) do tip[#tip + 1] = x end
        local detail = kind == "vendor" and "from a vendor" or "at the Auction House"
        if b.freshness == "old" then detail = detail .. " \194\183 old price" end
        Row(kind, ("Buy %d \195\151 %s"):format(b.qty, name(l.item)), detail, text, l.item, "buy", tip)
    end
    if #vendor > 0 then
        Head("Buy from vendor")
        for _, l in ipairs(vendor) do BuyRow("vendor", l) end
    end
    if #auction > 0 then
        Head("Buy from Auction House")
        for _, l in ipairs(auction) do BuyRow("auction", l) end
    end
    if #missing > 0 then
        Head("No price yet")
        for _, l in ipairs(missing) do
            Row("buy", ("Get %d \195\151 %s"):format(l.buy.qty or l.rest or 0, name(l.item)), "no known source price", "no price", l.item, "warn",
                { { CP.WHY[l.missing] or CP.WHY.nosource } })
        end
    end

    if #plan.collect > 0 then
        Head("Collect")
        for _, c in ipairs(plan.collect) do
            local guild = c.where == "guild"
            Row("collect", ("Collect %d \195\151 %s"):format(c.qty, name(c.item)), guild and "from the guild bank" or "from your bank", "", c.item, "collect",
                { { guild and "Shared stock: others can take it too, and a withdrawal limit may apply." or "Counted from when your bank was last open." } })
        end
    end

    local owned = {}
    for _, l in ipairs(plan.items or {}) do
        if l.owned.bags > 0 then owned[#owned + 1] = l end
    end
    if #owned > 0 then
        Head("Already in your bags")
        for _, l in ipairs(owned) do
            Row("own", name(l.item), "in your bags", tostring(l.owned.bags), l.item, "own",
                { { "Counted at", l.value and money(l.value) or "an unknown value" }, { "Owned materials still count at what they would cost." } })
        end
    end

    local alts = {}
    for _, l in ipairs(plan.items or {}) do
        if l.alternatives and #l.alternatives > 0 then alts[#alts + 1] = l end
    end
    if #alts > 0 then
        local n = 0
        for _, l in ipairs(alts) do n = n + #l.alternatives end
        Row("toggle", ("Other options considered (%d)"):format(n), nil, showAlts and "Hide" or "Show")
        if showAlts then
            for _, l in ipairs(alts) do
                local _, cmp, each = St.Compare(l, money)
                for i, a in ipairs(l.alternatives) do
                    local what = a.kind == "make" and ("Craft " .. name(l.item)) or ("Buy " .. name(l.item))
                    local line = each and each[i] or ""
                    local right
                    if a.ok == false then right = "not possible"
                    elseif a.difference == nil or a.compare == "unknown" then right = "can't compare"
                    elseif a.compare == "equal" or a.difference == 0 then right = "same cost"
                    elseif a.difference > 0 then right = a.compare == "lower" and (money(a.difference) .. " more") or "too close to call"
                    else right = money(-a.difference) .. " less" end
                    Row("alt", what, line, right, l.item, "alt", cmp)
                end
            end
        end
    end
    return out
end
