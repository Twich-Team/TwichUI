-- TwichUI Workshop: the "What's it worth?" tooltip section, as the player arranged it (pure: no game calls, no frames)
-- Worth.lua decides what is known; this file decides which lines are shown, in what order, and when. ONE builder (WL.Rows / WL.Lines)
-- makes the section for the live tooltip (WorthTip.lua) and for the designer's preview (TwichUI_Settings/pages/WorkshopWorth.lua), so the
-- preview cannot drift from the tooltip.
--
-- THE RULES (docs/workshop.md, "What's it worth?"):
--   * a layout only chooses PRESENTATION: which of the thirteen line types appear, their order, and "Always" or "Hold Shift" for each. Every
--     line is built from the same evaluation whether it is shown or not, so hiding a row never changes a figure or the recommendation;
--   * a qualification that keeps a figure honest belongs to the figure's own row, never to a separate line the player could remove:
--     "before fees" / "after fees", "old prices" and "partial scan" on the auction row, "average" on the disenchant row, and the
--     recommendation's own "(disenchant unknown)";
--   * a line with nothing to say is not drawn (a potion has no disenchant row), and the heading is not drawn without content;
--   * "Hold Shift for details" appears only when holding Shift would show something more;
--   * Shift adds the Shift-only lines to the Always lines in the configured order; an Always line is never shown twice.
--
-- Saved in the profile in use (presentation, like the other TwichUI settings): TwichUIDB.ui.workshopWorth = { v = 1, enabled = false?,
--   lines = { { id, when = "always"|"shift" }, ... } }. Missing = the defaults; an unusable entry is skipped when read (the saved table is
--   left as it is until the player changes something); a table written by a NEWER TwichUI (v above ours) reads as the defaults and is never
--   overwritten. Never stored here: prices, inventory, or anything observed (those stay account-wide in TwichUIDB.workshop).

local R = TwichUI
local W = R.Workshop
local WO, PR = W.Worth, W.Prices
local WL = {}
W.WorthLayout = WL

WL.VERSION = 1
WL.KEY = "workshopWorth"
WL.TITLE = "What's it worth?"
WL.HINT = "Hold Shift for details"

---------------------------------------------------------------------------
-- The line types
---------------------------------------------------------------------------
-- label: the designer's name for it; what: one sentence for its tooltip; when: where a new one starts.
WL.TYPES = {
    { id = "recommend", label = "Recommendation", when = "always",
      what = "Suggested: Vendor, Auction house or Disenchant, only when the estimates prove it. Otherwise why not." },
    { id = "vendor", label = "Vendor value", when = "always", what = "What a vendor pays for one." },
    { id = "auction", label = "Auction value", when = "always",
      what = "The cheapest listing your last scan saw, marked \"before fees\" until the auction house's cut is confirmed." },
    { id = "disenchant", label = "Disenchant value (average)", when = "always",
      what = "Only for weapons and armor that might disenchant. There is no outcome data yet, so it says \"no data\"." },
    { id = "status", label = "Price age / status", when = "shift", what = "When the prices were scanned, and if the scan was partial." },
    { id = "source", label = "Price source", when = "shift", what = "Which auction house the prices came from." },
    { id = "outcomes", label = "Disenchant outcomes", when = "shift",
      what = "What disenchanting may give. There is no outcome data in this version, so this line stays empty." },
    { id = "note", label = "Limits note", when = "shift", what = "One short line: estimates are not sales, and deposits and failed listings are not counted." },
    { id = "marketvalue", label = "Market value", when = "always",
      what = "A 14-day reference built from listings your scans saw. Not a selling price and not a promise it will sell." },
    { id = "recent", label = "Recent price", when = "shift", what = "A representative listing price from your last scan. A listing, not a sale." },
    { id = "historical", label = "Historical value", when = "shift",
      what = "A 60-day reference from listings your scans saw, older weeks counted by their average. Not a selling price." },
    { id = "supply", label = "Supply and competition", when = "shift",
      what = "How many were listed in your last scan, and how many sit at or below the price you would compete with. Listings, never demand." },
    { id = "quality", label = "Market data quality", when = "shift", what = "How far the market figures can be trusted (Good, Fair, Limited) and why, in a few words." },
}
WL.BY_ID = {}
for i, t in ipairs(WL.TYPES) do WL.BY_ID[t.id] = t; t.order = i end
WL.MAX_LINES = #WL.TYPES

-- The short layout out of the box: the answer and the values Always; the detail lines under Shift. No outcomes line (it has no data).
WL.DEFAULT_LINES = {
    { id = "recommend", when = "always" }, { id = "vendor", when = "always" }, { id = "auction", when = "always" },
    { id = "disenchant", when = "always" }, { id = "marketvalue", when = "always" }, { id = "recent", when = "shift" },
    { id = "historical", when = "shift" }, { id = "supply", when = "shift" }, { id = "quality", when = "shift" },
    { id = "status", when = "shift" }, { id = "source", when = "shift" }, { id = "note", when = "shift" },
}

local function Copy(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = { id = e.id, when = e.when } end
    return out
end

function WL.DefaultLines() return Copy(WL.DEFAULT_LINES) end

---------------------------------------------------------------------------
-- Checking a layout
---------------------------------------------------------------------------
-- A usable list from anything: entries that are not a table, name no known line type, or repeat one are skipped; a "when" that is neither
-- word reads as "always". Never more than one of a type, so never more than WL.MAX_LINES.
function WL.Clean(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for i = 1, WL.MAX_LINES * 4 do   -- bounded: a damaged table cannot make this long
        local e = list[i]
        if e == nil and i > #list then break end
        if type(e) == "table" and type(e.id) == "string" and WL.BY_ID[e.id] and not seen[e.id] then
            seen[e.id] = true
            out[#out + 1] = { id = e.id, when = e.when == "shift" and "shift" or "always" }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
local function Saved(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    local t = db.ui[WL.KEY]
    if t ~= nil and type(t) ~= "table" then
        if not create then return nil end
        t = nil
    end
    if t == nil then
        if not create then return nil end
        t = {}
        db.ui[WL.KEY] = t
    end
    return t
end

-- true when what is saved was written by a newer TwichUI: read as defaults, never written over
local function Newer(t)
    return t ~= nil and type(t.v) == "number" and t.v > WL.VERSION
end

-- The layout in use: { enabled, lines } as copies (the caller may change them). Never nil.
function WL.Get()
    local t = Saved(false)
    if t == nil or Newer(t) then return { enabled = true, lines = WL.DefaultLines() } end
    local lines
    if type(t.lines) == "table" then lines = WL.Clean(t.lines) else lines = WL.DefaultLines() end   -- {} is the player's own choice: kept
    return { enabled = t.enabled ~= false, lines = lines }
end

function WL.Enabled() return WL.Get().enabled end

-- Does the layout have a line that needs the market figures (A7)? Then the caller asks MarketFacts; otherwise it asks nothing.
WL.MARKET_IDS = { marketvalue = true, recent = true, historical = true, supply = true, quality = true }
function WL.UsesMarket(layout)
    for _, e in ipairs(layout.lines) do if WL.MARKET_IDS[e.id] then return true end end
    return false
end

-- true, or false and a reason: "newer" (written by a newer TwichUI), "nosave"
function WL.CanWrite()
    local t = Saved(false)
    if Newer(t) then return false, "newer" end
    if type(TwichUIDB) ~= "table" then return false, "nosave" end
    return true
end

function WL.SetEnabled(on)
    if on ~= true and on ~= false then return false, "bad" end
    local ok, why = WL.CanWrite()
    if not ok then return false, why end
    local t = Saved(true)
    if t.v == nil then t.v = WL.VERSION end
    t.enabled = on
    return true
end

function WL.SetLines(lines)
    local ok, why = WL.CanWrite()
    if not ok then return false, why end
    if type(lines) ~= "table" then return false, "bad" end
    local t = Saved(true)
    t.v = WL.VERSION
    t.lines = WL.Clean(lines)
    return true
end

-- Back to the short default layout (the "Enable tooltip" choice is not a layout and stays).
function WL.Reset()
    local ok, why = WL.CanWrite()
    if not ok then return false, why end
    local t = Saved(false)
    if t then t.lines = nil end
    return true
end

function WL.IsDefault()
    local a, b = WL.Get().lines, WL.DEFAULT_LINES
    if #a ~= #b then return false end
    for i = 1, #a do if a[i].id ~= b[i].id or a[i].when ~= b[i].when then return false end end
    return true
end

---------------------------------------------------------------------------
-- Changing a layout (each returns a NEW list, or nil and a reason; the argument is never changed)
---------------------------------------------------------------------------
local function IndexOf(list, id)
    for i, e in ipairs(list) do if e.id == id then return i end end
end
WL.IndexOf = IndexOf

local function Clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end

-- at: the place to put it (1 = first; nil or past the end = last)
function WL.Add(list, id, at, when)
    local t = WL.BY_ID[id]
    if not t then return nil, "unknown" end
    if IndexOf(list, id) then return nil, "duplicate" end
    local out = Copy(list)
    local pos = Clamp(math.floor(tonumber(at) or (#out + 1)), 1, #out + 1)
    table.insert(out, pos, { id = id, when = when == "shift" and "shift" or (when == "always" and "always" or t.when) })
    return out
end

function WL.Remove(list, id)
    local i = IndexOf(list, id)
    if not i then return nil, "missing" end
    local out = Copy(list)
    table.remove(out, i)
    return out
end

-- Moves `id` so that it comes BEFORE the line now at position `before` (nil or past the end = last). Dropping it where it already is
-- changes nothing.
function WL.Move(list, id, before)
    local from = IndexOf(list, id)
    if not from then return nil, "missing" end
    local out = Copy(list)
    local entry = table.remove(out, from)
    local pos = Clamp(math.floor(tonumber(before) or (#list + 1)), 1, #list + 1)
    if pos > from then pos = pos - 1 end   -- the line itself came out of the list first
    table.insert(out, pos, entry)
    return out
end

local function Shown(e, shift) return e.when == "always" or shift == true end

-- One step up (dir = -1) or down (1) PAST THE NEXT LINE THAT IS SHOWN in that mode (shift = the Hold Shift preview), so a step is always
-- something the player can see; nil and "edge" at the end of the list.
function WL.Step(list, id, dir, shift)
    local from = IndexOf(list, id)
    if not from then return nil, "missing" end
    local j = from + dir
    while list[j] and not Shown(list[j], shift) do j = j + dir end
    if not list[j] then return nil, "edge" end
    local out = Copy(list)
    local entry = table.remove(out, from)
    table.insert(out, j, entry)
    return out
end

function WL.SetWhen(list, id, when)
    local i = IndexOf(list, id)
    if not i then return nil, "missing" end
    if when ~= "always" and when ~= "shift" then return nil, "bad" end
    local out = Copy(list)
    out[i].when = when
    return out
end

---------------------------------------------------------------------------
-- The words of each line
---------------------------------------------------------------------------
-- A line is { text } or { left, right }; "~" starts a quiet line, "!" a warning and "*" a highlighted one (the suggestion).
-- r: WO.Evaluate's answer; ctx: { money(copper) -> text, ageText(seconds) -> text, market = { label, at, complete } or nil, now }
local AUCTION_WORDS = {
    unavailable = { bound = "can't be listed (bound)", quest = "can't be listed (quest item)" },
    unknown = { bind = "can't tell if it can be listed", variant = "this variant isn't priced", nomarket = "not scanned yet", noprice = "no price" },
}
WL.AUCTION_WORDS = AUCTION_WORDS

local function AuctionLabel(a)
    local tags = {}
    if a.beforeFees then tags[#tags + 1] = "before fees" else tags[#tags + 1] = "after fees" end
    if a.old then tags[#tags + 1] = "old prices" end
    if not a.complete then tags[#tags + 1] = "partial scan" end
    return "Auction (" .. table.concat(tags, ", ") .. ")"
end

local RENDER = {}

function RENDER.recommend(r)
    local rec = WO.Recommend(r)
    if not rec then return nil end
    return { (rec.tone == "good" and "*" or "~") .. rec.text }
end

function RENDER.vendor(r, ctx)
    local v = r.vendor
    return { "Vendor", v.state == "ok" and ctx.money(v.value) or (v.state == "none" and "no sell value" or "unknown") }
end

function RENDER.auction(r, ctx)
    local a = r.auction
    if a.state == "ok" then return { AuctionLabel(a), ctx.money(a.value) } end
    return { "Auction", AUCTION_WORDS[a.state][a.why] or "unknown" }
end

function RENDER.disenchant(r, ctx)
    local d = r.disenchant
    if not d then return nil end   -- not something that disenchants: no row, not "not applicable"
    if d.state == "ok" and type(d.value) == "number" then return { "Disenchant (average)", ctx.money(d.value) } end
    return { "Disenchant (average)", "no data" }
end

-- The market figures (A7): one cached read of the Market services, made by the caller (ctx.facts = MarketFacts.Of's answer; nil when it was not
-- asked or a variant, which is never priced from the base item). The words live in MarketFacts.Line so the details window and this tooltip agree.
local function Market(id)
    return function(r, ctx)
        local F = W.Facts
        if not (F and ctx.facts) or r.auction.state == "unavailable" then return nil end   -- an item that can't be listed gets no market lines
        return F.Line(id, ctx.facts, ctx.money)
    end
end
RENDER.marketvalue = Market("marketvalue")
RENDER.recent = Market("recent")
RENDER.historical = Market("historical")
RENDER.supply = Market("supply")

function RENDER.quality(r, ctx)
    local F = W.Facts
    if not (F and ctx.facts) or r.auction.state == "unavailable" then return nil end
    local line = F.Line("quality", ctx.facts, ctx.money)
    if not line then return nil end
    local notes = F.QualityNotes(ctx.facts, 2)
    if #notes == 0 then return line end
    -- not good: one quiet sentence that wraps, with the reasons ("Market data: Limited, scanned 4 days ago. Only 2 listings.")
    return { "~" .. line[1] .. ": " .. line[2] .. ". " .. table.concat(notes, " ") }
end

-- The prices' age, when there is a scan to speak of
function RENDER.status(r, ctx)
    local a, m = r.auction, ctx.market
    if a.state == "unknown" and a.why == "nomarket" then return { "Scanned", "not yet" } end
    if not m or a.state == "unavailable" or (a.state == "unknown" and (a.why == "variant" or a.why == "bind")) then return nil end
    local at, complete = a.at or m.at, m.complete == true
    if a.state == "ok" then complete = a.complete == true end
    local text = ctx.ageText(PR.Age(at, ctx.now))
    if not complete then text = text .. ", partial scan" end
    return { "Scanned", text }
end

function RENDER.source(r, ctx)
    local a, m = r.auction, ctx.market
    if not m or not m.label or not (a.state == "ok" or (a.state == "unknown" and a.why == "noprice")) then return nil end
    return { "Prices from", m.label }
end

-- Disenchant outcomes (what it may give): no legally reusable outcome data exists for this version (docs/workshop.md), so there is
-- nothing to show. The line type exists so a layout can hold the place; it draws only when an evaluation carries outcomes.
function RENDER.outcomes(r, ctx)
    local d = r.disenchant
    if not (d and d.state == "ok" and type(d.outcomes) == "string" and d.outcomes ~= "") then return nil end
    return { "Disenchant gives", d.outcomes }
end

function RENDER.note(r)
    -- only when there is an auction estimate whose limits it explains
    if r.auction.state ~= "ok" then return nil end
    return { "~Estimates, not sales. Deposits and failed listings aren't counted." }
end

---------------------------------------------------------------------------
-- The section
---------------------------------------------------------------------------
-- layout: { lines = ... } (WL.Get()); shift: is Shift held (the "Hold Shift" preview).
-- Returns nil when there is nothing to show; otherwise
--   { title, rows = { { id, when, line (nil when it has nothing to say), index (its place in the layout) }, ... }, hint }
-- rows are the lines shown in this mode, in order, INCLUDING those with nothing to say (the designer draws them as empty places);
-- hint is "Hold Shift for details" when Shift would show something more.
-- keep (the designer): return the section even when the tooltip would show nothing (then `empty` is true), so its places can still be edited.
function WL.Rows(r, ctx, layout, shift, keep)
    local rows, more, content = {}, false, 0
    for i, e in ipairs(layout.lines) do
        local line = RENDER[e.id](r, ctx)
        if Shown(e, shift) then
            rows[#rows + 1] = { id = e.id, when = e.when, line = line, index = i }
            if line then content = content + 1 end
        elseif line then
            more = true
        end
    end
    local hint = (not shift and more) and WL.HINT or nil
    local empty = content == 0 and not hint
    if empty and not keep then return nil end
    return { title = WL.TITLE .. ((ctx.count or 1) > 1 and " (each)" or ""), rows = rows, hint = hint, empty = empty }
end

-- The same section as the flat lines the tooltip draws: the heading, each line that has something to say, the hint.
function WL.Lines(r, ctx, layout, shift)
    local s = WL.Rows(r, ctx, layout, shift)
    if not s then return nil end
    local out = { { s.title } }
    for _, row in ipairs(s.rows) do if row.line then out[#out + 1] = row.line end end
    if s.hint then out[#out + 1] = { "~" .. s.hint } end
    return out
end

-- How a line is drawn (one place, for the tooltip and the preview). Returns kind, text:
--   "left" a two-column line (left, right); "good", "quiet", "warn", "plain" a single line
WL.COLORS = {
    title = { 1, 0.82, 0 }, good = { 0.62, 0.92, 0.55 }, quiet = { 0.55, 0.55, 0.55 }, warn = { 1, 0.82, 0.3 }, plain = { 0.8, 0.8, 0.8 },
    left = { 0.8, 0.8, 0.8 }, right = { 1, 1, 1 },
}

function WL.Style(line)
    if line[2] ~= nil then return "double", line[1], line[2] end
    local first = line[1]:sub(1, 1)
    if first == "*" then return "good", line[1]:sub(2) end
    if first == "!" then return "warn", line[1]:sub(2) end
    if first == "~" then return "quiet", line[1]:sub(2) end
    return "plain", line[1]
end

function WL.Money(copper)
    if type(GetMoneyString) == "function" then return GetMoneyString(copper, true, nil, true) end
    return tostring(copper) .. "c"
end

---------------------------------------------------------------------------
-- Preview examples (made-up items, labelled as preview data in the designer; nothing is read from the game)
---------------------------------------------------------------------------
local EXAMPLE_NOW = 1800000000
local EXAMPLE_MARKET = { label = "the example auction house", side = "Example", at = EXAMPLE_NOW - 3 * 3600, complete = true }

-- The market figures of an example (what MarketFacts.Of would answer), made up for the preview only: prices in copper, a good fresh scan
local function ExampleFacts(mval, recent, hist, items, ahead, competing, level)
    local function V(v) return { value = v, notes = {} } end
    return { item = 0, now = EXAMPLE_NOW, mval = V(mval), recent = V(recent), hist = V(hist), age = 3 * 3600, freshness = "fresh",
        supply = { items = items }, comp = { competing = competing, ahead = ahead },
        quality = { level = level, reasons = {}, n = 20 } }
end

WL.EXAMPLES = {
    { key = "ordinary", label = "Ordinary item",
      facts = { sell = 500, quality = 1, classID = 7, bindType = 0, bound = false, market = EXAMPLE_MARKET,
          price = { price = 400, at = EXAMPLE_NOW - 3 * 3600, complete = true } },
      market = function() return ExampleFacts(420, 400, 450, 24, 9, 400, "good") end },
    { key = "higher", label = "Auction looks higher",
      facts = { sell = 500, quality = 1, classID = 7, bindType = 0, bound = false, market = EXAMPLE_MARKET,
          price = { price = 900, at = EXAMPLE_NOW - 3 * 3600, complete = true } },
      market = function() return ExampleFacts(700, 900, 650, 5, 2, 900, "good") end },
    { key = "missing", label = "Missing prices",
      facts = { sell = 300, quality = 2, classID = 4, equipLoc = "INVTYPE_CHEST", bindType = 2, bound = false, market = EXAMPLE_MARKET } },
    { key = "unavailable", label = "Can't be auctioned",
      facts = { sell = 300, quality = 2, classID = 4, equipLoc = "INVTYPE_CHEST", bindType = 1, bound = true, market = EXAMPLE_MARKET } },
}
WL.EXAMPLE_BY_KEY = {}
for _, e in ipairs(WL.EXAMPLES) do WL.EXAMPLE_BY_KEY[e.key] = e end

-- The evaluation and context of an example, ready for WL.Rows. Same code as a real item: WO.Evaluate over made-up facts. The product's
-- real state is kept: no auction house cut is confirmed, so the auction value is "before fees".
function WL.Example(key)
    local e = WL.EXAMPLE_BY_KEY[key] or WL.EXAMPLES[1]
    local f = { now = EXAMPLE_NOW }
    for k, v in pairs(e.facts) do f[k] = v end
    local r = WO.Evaluate(f)
    return r, { money = WL.Money, ageText = PR.AgeText, market = EXAMPLE_MARKET, now = EXAMPLE_NOW, count = 1, facts = e.market and e.market() or nil }, e
end
