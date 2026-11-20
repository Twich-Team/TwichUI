-- TwichUI: the gold ledger's recorder (docs/workshop/gold-ledger.md)
-- A small, always-available recorder of the gold the player's character gains and spends, kept in its own saved
-- variable, TwichUILedgerDB. It lives in the core so it keeps recording while the Workshop addon (and its window) is not
-- loaded; the Workshop's Gold Ledger page only reads what is kept here.
--
-- What is recorded: one entry for each observed change of the character's gold. The amount is the exact difference
-- between two valid readings of GetMoney() in this session, in signed integer copper. Classification is metadata on
-- that one entry, never a second money entry:
--   * A change nothing vouches for stays UNCLASSIFIED (evidence "balance": only the balance moved).
--   * A completed transaction reports itself as EVIDENCE (Lg.Evidence): a kind, an exact signed amount and optional item
--     facts. It is attached only to an entry of exactly that amount that was observed in the same frame, or within a few
--     seconds with no rival of the same amount; evidence waits briefly for its money when it arrives first. An ambiguous
--     match attaches nothing. Evidence never creates money by itself.
--   * The mailbox (auction/Mail.lua) reports money it was asked to take and then saw arrive; the Auction House purchase
--     controller (TwichUI_Workshop/auction/Actions.lua) reports a completed purchase. A posting, a server-reported sale
--     that is not yet collected, an open vendor or mailbox window prove nothing and are never evidence.
--   * LedgerAuction.lua correlates owned completed postings/cancellations to their exact deposit/fee debit.
--     Seller invoice gross/fee/returned-deposit fields describe the collected entry; they are never extra cash.
--
-- What is NOT recorded: gold that changed while the character was logged out, while the Workshop was turned off, or between
-- the last reading of a session and the next (the first reading of a session is only a baseline and makes no entry), and
-- history is never rebuilt from the current balance. A reading that cannot be trusted (missing, secret, negative,
-- fractional, not finite) is ignored and changes nothing.
--
-- Opt-in boundary: recording needs the Workshop to be turned on (R.WorkshopLauncher.Enabled). Turning it off stops new
-- records and keeps the old ones; nothing is deleted. No timers, no polling: the recorder listens to PLAYER_MONEY (and two
-- bookkeeping events) only while recording, and a newer-format saved variable is held aside untouched and not recorded to.
--
-- TwichUILedgerDB = { version = 1, chars = { ["Name - Realm"] = {
--     name, realm,                   the character's identity (also the key)
--     since,                         unix time of the first reading that made this record (recording started)
--     tz,                            1 = days are local calendar days (absent/0: UTC days, rebuilt on first read)
--     nextId,                        the next journal id (ids are never reused)
--     entries = { {                  the journal, oldest first, at most MAX_ENTRIES (+ TRIM_SLACK)
--         id, t, a,                  stable id, unix time, signed copper (positive in, negative out; never zero)
--         k,                         source code (SOURCES); absent = unclassified
--         e,                         evidence code (EVIDENCE): how the classification, if any, was established
--         i, q, n, x,                optional: item id, quantity, a short note, a correlation id
--         u, s,                      optional: native auction ID; bounded versioned seller settlement (s.v = 1)
--     }, ... },
--     days = { [localDay] = {        one per local calendar day the recorder was running for this character (RETAIN_DAYS kept)
--         i, o, n,                   copper in, copper out (a positive number), entries counted
--         ci = { [source] = copper }, co = { [source] = copper }      the same split by source ("other" = unclassified)
--     } },
-- } } }
-- A day record with n = 0 means "recorded, and nothing happened"; no record means "not recorded" (outside coverage).
-- Days are the player's LOCAL calendar days (rec.tz = 1; records made before that were bucketed by UTC day and are rebuilt from their
-- journal once, see Rebuild). The day number is local-midnight based: day N covers [DayStart(N), DayStart(N+1)).

local R = TwichUI
local P = R.Persist
local Lg = {}
R.Ledger = Lg

Lg.VERSION = 1
Lg.MAX_ENTRIES = 2000      -- journal entries kept per character
Lg.TRIM_SLACK = 50         -- the journal may run this far over before the oldest are dropped in one step
Lg.RETAIN_DAYS = 90        -- days of daily totals (and of journal entries) kept, today included
Lg.MAX_CHARS = 100         -- characters with a record; a new one past this is not recorded
Lg.MAX_MONEY = 9007199254740991   -- 2^53 - 1: the largest exact integer; sums saturate here
Lg.RECENT_WINDOW = 10      -- seconds an entry (or evidence) can wait for its other half
local MAX = Lg.MAX_MONEY
local DAY = 86400
local MAX_TIME = 4102444800   -- 2100-01-01 UTC: later times are not plausible clocks
local MAX_ITEM, MAX_QTY, MAX_NOTE, MAX_CORR = 2147483647, 2147483647, 60, 64
local MAX_RECENT, MAX_PENDING, MAX_SEEN = 64, 8, 256   -- recent: a junk sweep can make dozens of entries within the evidence window

-- Where a change came from. dir: the direction the source can only have (1 in, -1 out); absent = either.
Lg.SOURCES = {
    ahSale = { label = "Auction sale", dir = 1, evidence = "mailinvoice" },
    mail = { label = "Mail collected", dir = 1, evidence = "mailbox" },
    quest = { label = "Quest reward", dir = 1, evidence = "questreward" },
    ahBuy = { label = "Auction purchase", dir = -1, evidence = "auctionpurchase" },
    vendorBuy = { label = "Vendor Purchase", dir = -1, evidence = "merchantpurchase" },
    vendorSell = { label = "Vendor Sale", dir = 1, evidence = "merchantsale" },
    repair = { label = "Repairs", dir = -1, evidence = "merchantrepair" },
    ahDeposit = { label = "Auction Deposit", dir = -1, evidence = "auctiondeposit" },
    ahCancelFee = { label = "Auction Cancellation Fee", dir = -1, evidence = "auctioncancel" },
    other = { label = "Unclassified", evidence = "balance" },
}
Lg.ORDER = { "ahSale", "mail", "quest", "ahBuy", "vendorBuy", "vendorSell", "repair", "ahDeposit", "ahCancelFee", "other" }
-- How the classification was established, in the words the details show.
Lg.EVIDENCE = {
    balance = "Only your gold balance changed. Nothing identifies the source.",
    mailbox = "Mailbox money you took, matched to the exact amount that arrived.",
    questreward = "A quest you turned in paid this exact gold, matched to the amount that arrived.",
    mailinvoice = "A sold-auction invoice in the mailbox, matched to the exact amount that arrived.",
    auctionpurchase = "A completed Auction House purchase, matched to the exact amount that left.",
    merchantpurchase = "A gold-only merchant purchase request and the exact items received, matched to the observed spending.",
    merchantsale = "A merchant sale request, the removed stack and a new matching buyback receipt, matched to the gold received.",
    merchantrepair = "A player-paid repair-all request and the verified repair cost cleared, matched to the observed spending.",
    auctiondeposit = "An owned posting completed, matched to its native deposit quote and exact observed debit.",
    auctioncancel = "The reviewed auction ID was cancelled, matched to its verified cancellation cost and exact observed debit.",
}

local active, held, ready = false, false, false
local base, baseKey            -- this session's balance baseline and the character it belongs to (never saved)
local revision = 0
local listeners = {}
local stats = { events = 0, recorded = 0, duplicate = 0, invalid = 0, baselines = 0, attributed = 0, ambiguous = 0, repeated = 0, refused = 0, expired = 0 }
local recent, pending = {}, {}
local seen, seenList = {}, {}
local cleaned, compacted = {}, {}
local watching = {}
local attachListeners = {}

---------------------------------------------------------------------------
-- Small checks. A value from the game or from a file is decided to be a plain, finite, whole number BEFORE it is compared
-- (a NaN compares oddly in the client: see the Workshop's W.Finite).
---------------------------------------------------------------------------
local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Finite(v) return type(v) == "number" and tostring(v):find("^[%d%.eE%+%-]+$") ~= nil end
local function Whole(v, lo, hi)
    v = Plain(v)
    if not Finite(v) or v < lo or v > hi or math.floor(v) ~= v then return nil end
    return v
end
local function Signed(v)
    v = Plain(v)
    if not Finite(v) or v == 0 or math.floor(v) ~= v or v > MAX or v < -MAX then return nil end
    return v
end
local function Add(x, y)
    local s = x + y
    if s > MAX then return MAX end
    return s
end
local function Note(v)
    if type(v) ~= "string" or issecretvalue and issecretvalue(v) then return nil end
    v = v:gsub("[%c|]", " ")
    if v == "" then return nil end
    if #v > MAX_NOTE then
        local cut = v:sub(1, MAX_NOTE)
        local j = #cut
        while j > 0 and cut:byte(j) >= 0x80 and cut:byte(j) < 0xC0 do j = j - 1 end
        if j > 0 then   -- never half of a multi-byte character
            local b = cut:byte(j)
            local need = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
            if j + need - 1 > #cut then cut = cut:sub(1, j - 1) end
        end
        v = cut
    end
    return v
end

-- Local calendar days. UtcOffset(t) is local minus UTC in seconds at unix time t (0 when the client cannot say, which is UTC days).
-- It is a field so a test can stand a time zone in; everything below goes through it.
local offsets = {}
function Lg.UtcOffset(t)
    local half = math.floor(t / 1800)
    local hit = offsets[half]
    if hit then return hit end
    local off = 0
    local ok, l, g = pcall(function() return date("*t", t), date("!*t", t) end)
    if ok and type(l) == "table" and type(g) == "table" then
        l.isdst, g.isdst = false, false
        local ok2, a, b = pcall(function() return time(l), time(g) end)
        if ok2 and Finite(a) and Finite(b) then
            off = a - b
            if off % 900 ~= 0 or off < -50400 or off > 50400 then off = 0 end   -- no real zone: not a zone
        end
    end
    offsets[half] = off
    return off
end
function Lg.DayOf(t) return math.floor((t + Lg.UtcOffset(t)) / DAY) end
-- The unix time local day `day` begins (the offset is read at that moment, so a daylight-saving change is followed).
function Lg.DayStart(day)
    local s = day * DAY - Lg.UtcOffset(day * DAY)
    return day * DAY - Lg.UtcOffset(s)
end

local function Clock()
    local f = GetServerTime or time
    if type(f) ~= "function" then return nil end
    local ok, t = pcall(f)
    t = ok and Whole(t, 0, MAX_TIME) or nil
    if not t then return nil end
    return t, Lg.DayOf(t)
end
local function Mono()
    if type(GetTime) ~= "function" then return 0 end
    local ok, v = pcall(GetTime)
    return ok and Finite(v) and v or 0
end

local function CharKey()
    local name, realm = Plain(UnitName and UnitName("player")), Plain(GetRealmName and GetRealmName())
    if type(name) ~= "string" or name == "" or name == "Unknown" then return nil end
    if type(realm) ~= "string" or realm == "" then realm = "?" end
    return name .. " - " .. realm, name, realm
end
Lg.CharKey = function() return (CharKey()) end

-- Optional settlement extension on ONE cash entry, not more money entries. Native seller invoices describe
-- gross + returned deposit - commission = collected. At most eight invoices; no sender/buyer or mail text.
-- v is independent of the root schema. Unknown extension versions are retained but never interpreted.
Lg.MAX_INVOICES = 8
function Lg.Settlement(raw, amount)
    if type(raw) ~= "table" or raw.v ~= 1 or not Signed(amount) or amount < 0 or type(raw.invoices) ~= "table" then return nil end
    local count = 0
    for k in pairs(raw.invoices) do
        if not Whole(k, 1, Lg.MAX_INVOICES) then return nil end
        count = count + 1; if count > Lg.MAX_INVOICES then return nil end
    end
    if count == 0 then return nil end
    local s = { v = 1, g = 0, f = 0, d = 0, c = 0, invoices = {} }
    for i = 1, count do
        local r = raw.invoices[i]
        if type(r) ~= "table" then return nil end
        local g, f, d, c = Whole(r.g, 1, MAX), Whole(r.f, 0, MAX), Whole(r.d, 0, MAX), Whole(r.c, 1, MAX)
        if not (g and f and d and c) or g > MAX - d or f > g + d or g + d - f ~= c then return nil end
        for key, n in pairs({ g = g, f = f, d = d, c = c }) do
            if s[key] > MAX - n then return nil end
            s[key] = s[key] + n
        end
        s.invoices[i] = { g = g, f = f, d = d, c = c, n = Note(r.n), q = Whole(r.q, 1, MAX_QTY) }
    end
    if s.c ~= amount then return nil end
    for _, key in ipairs({ "g", "f", "d", "c" }) do if raw[key] ~= nil and raw[key] ~= s[key] then return nil end end
    return s
end

---------------------------------------------------------------------------
-- Cleaning what was read from the saved file (never trusts it; repairs narrowly, never resets a record for one bad field)
---------------------------------------------------------------------------
local function CleanEntry(e)
    if type(e) ~= "table" then return nil end
    local id, t, a = Whole(e.id, 1, MAX), Whole(e.t, 0, MAX_TIME), Signed(e.a)
    if not (id and t and a) then return nil end
    e.id, e.t, e.a = id, t, a
    local src = type(e.k) == "string" and e.k ~= "other" and Lg.SOURCES[e.k] or nil
    if src and src.dir and (a > 0) ~= (src.dir > 0) then src = nil end   -- a source cannot move gold the other way
    if not src then e.k = nil end
    if type(e.e) ~= "string" or not Lg.EVIDENCE[e.e] or (e.k and Lg.SOURCES[e.k].evidence ~= e.e) then
        e.e = e.k and Lg.SOURCES[e.k].evidence or "balance"
    end
    e.i, e.q = Whole(e.i, 1, MAX_ITEM), Whole(e.q, 1, MAX_QTY)
    e.n = Note(e.n)
    e.x = type(e.x) == "string" and #e.x <= MAX_CORR and e.x or nil
    e.u = (e.k == "ahDeposit" or e.k == "ahCancelFee") and Whole(e.u, 1, MAX) or nil
    local future = type(e.s) == "table" and Whole(e.s.v, 2, MAX)
    if not future then e.s = e.k == "ahSale" and Lg.Settlement(e.s, e.a) or nil end
    return e
end

local function CleanSplit(t)
    local out = {}
    if type(t) == "table" then
        for code, v in pairs(t) do
            if type(code) == "string" and Lg.SOURCES[code] then
                v = Whole(v, 0, MAX)
                if v then out[code] = v end
            end
        end
    end
    return out
end

local function CleanDays(days)
    local out = {}
    if type(days) ~= "table" then return out end
    for k, d in pairs(days) do
        local day = Whole(k, 0, MAX_TIME / DAY)
        if day and type(d) == "table" then
            out[day] = { i = Whole(d.i, 0, MAX) or 0, o = Whole(d.o, 0, MAX) or 0, n = Whole(d.n, 0, MAX) or 0,
                ci = CleanSplit(d.ci), co = CleanSplit(d.co) }
        else
            P.Repair("ledger-entry-dropped")
        end
    end
    return out
end

local function ByTime(a, b)
    if a.t ~= b.t then return a.t < b.t end
    return a.id < b.id
end

local Rebuild   -- defined with the aggregates below
-- Makes one character's record usable; false when it is not a record at all. Idempotent.
local function CleanRecord(key, rec)
    if type(rec) ~= "table" then return false end
    local name, realm = tostring(key):match("^(.-) %- (.+)$")
    rec.name = type(rec.name) == "string" and rec.name ~= "" and rec.name or name or "?"
    rec.realm = type(rec.realm) == "string" and rec.realm ~= "" and rec.realm or realm or "?"
    rec.since = Whole(rec.since, 0, MAX_TIME)
    local list, maxId, sorted = {}, 0, true
    if type(rec.entries) == "table" then
        for _, e in ipairs(P.Sequence(rec.entries)) do
            local clean = CleanEntry(e)
            if clean then
                if clean.id > maxId then maxId = clean.id end
                if list[#list] and ByTime(clean, list[#list]) then sorted = false end
                list[#list + 1] = clean
            else
                P.Repair("ledger-entry-dropped")
            end
        end
    end
    if not sorted then table.sort(list, ByTime) end
    rec.entries = list
    local nextId = Whole(rec.nextId, 1, MAX)
    rec.nextId = (nextId and nextId > maxId) and nextId or (maxId + 1)
    rec.days = CleanDays(rec.days)
    rec.tz = Whole(rec.tz, 0, 9)
    if rec.tz ~= 1 then Rebuild(rec) end
    return true
end

-- Retention: daily totals and journal entries older than RETAIN_DAYS go (their days' totals go with them, so the two always
-- agree); a journal past its bound drops its oldest entries (their totals stay in their days). Deterministic.
local function Compact(rec, today)
    local firstDay = today - Lg.RETAIN_DAYS + 1
    for day in pairs(rec.days) do
        if day < firstDay then rec.days[day] = nil end
    end
    local entries = rec.entries
    local cut = 0
    local limit = Lg.DayStart(firstDay)
    while cut < #entries and entries[cut + 1].t < limit do cut = cut + 1 end
    local over = #entries - cut - Lg.MAX_ENTRIES
    if over > 0 then cut = cut + over end
    if cut > 0 then
        local kept = {}
        for i = cut + 1, #entries do kept[#kept + 1] = entries[i] end
        rec.entries = kept
    end
end

-- The record of a character, cleaned once per session; nil when there is none. Reading never makes one.
function Lg.Record(key)
    local db = TwichUILedgerDB
    if held or type(db) ~= "table" or type(db.chars) ~= "table" then return nil end
    local rec = db.chars[key]
    if rec == nil then return nil end
    if not cleaned[key] then
        if not CleanRecord(key, rec) then
            db.chars[key] = nil
            P.Repair("ledger-record-dropped")
            return nil
        end
        cleaned[key] = true
        local _, today = Clock()
        if today then Compact(rec, today) end
    end
    return rec
end

-- Set up once at load. A ledger saved by a newer TwichUI is not read or changed: it is set aside for the session (handed
-- back at logout, see Persist.lua) and nothing is recorded to it.
function Lg.Init()
    P.EnsureRoot("TwichUILedgerDB")
    local db = TwichUILedgerDB
    if not P.IsHeld("TwichUILedgerDB") then
        local stored = db.version
        if stored ~= nil and not P.IsCount(stored) then
            stored = nil
            P.Repair("ledger-repaired")
        end
        if stored and stored > Lg.VERSION then
            P.Hold("TwichUILedgerDB", db, { version = Lg.VERSION, chars = {} })
            P.Repair("future-schema")
            held = true
            ready = true
            return
        end
    else
        held = true
        ready = true
        return
    end
    db.version = Lg.VERSION
    if type(db.chars) ~= "table" then db.chars = {} end
    for key, rec in pairs(db.chars) do   -- what is not a record at all goes now; a record's own parts are cleaned when it is first read
        if type(key) ~= "string" or type(rec) ~= "table" then db.chars[key] = nil; P.Repair("ledger-record-dropped") end
    end
    held, ready = false, true
    local key = CharKey()
    if key and db.chars[key] then Lg.Record(key) end   -- this character's record is made usable now; the others when read
end

---------------------------------------------------------------------------
-- Aggregates
---------------------------------------------------------------------------
local function DayRecord(rec, day)
    local d = rec.days[day]
    if not d then
        d = { i = 0, o = 0, n = 0, ci = {}, co = {} }
        rec.days[day] = d
    end
    return d
end
local function Bump(rec, day, amount, code)
    local d = DayRecord(rec, day)
    if amount > 0 then
        d.i = Add(d.i, amount)
        d.ci[code] = Add(d.ci[code] or 0, amount)
    else
        d.o = Add(d.o, -amount)
        d.co[code] = Add(d.co[code] or 0, -amount)
    end
    d.n = Add(d.n, 1)
end
-- One-time move of a record from UTC days to local days. The journal is the truth: its entries are counted again into local days.
-- Where the journal no longer reaches back (its oldest entry is not number 1: the 2,000-entry bound or retention trimmed it), the
-- old totals of the UTC days up to and including the oldest entry's day cannot be re-split, so each is carried whole onto the local
-- day of its middle; that is the only approximation, and only for days older than the journal. Coverage is kept: every local day
-- a recorded UTC day overlapped has a record. Nothing is invented and no entry changes.
Rebuild = function(rec)
    local old, entries = rec.days, rec.entries
    local first = entries[1]
    local cut = (first and first.id > 1) and math.floor(first.t / DAY) or -1
    rec.days = {}
    for d, v in pairs(old) do
        for _, day in ipairs({ Lg.DayOf(d * DAY), Lg.DayOf(d * DAY + DAY - 1) }) do DayRecord(rec, day) end
        if d <= cut then
            local row = DayRecord(rec, Lg.DayOf(d * DAY + DAY / 2))
            row.i, row.o, row.n = Add(row.i, v.i), Add(row.o, v.o), Add(row.n, v.n)
            for code, n in pairs(v.ci) do row.ci[code] = Add(row.ci[code] or 0, n) end
            for code, n in pairs(v.co) do row.co[code] = Add(row.co[code] or 0, n) end
        end
    end
    for _, e in ipairs(entries) do
        if math.floor(e.t / DAY) > cut then Bump(rec, Lg.DayOf(e.t), e.a, e.k or "other") end
    end
    rec.tz = 1
end

-- An entry was classified after it was counted: its amount moves from "other" to its source, in the same day.
local function Move(rec, day, amount, from, to)
    local d = rec.days[day]
    if not d then return end
    local split, v = amount > 0 and d.ci or d.co, amount > 0 and amount or -amount
    split[from] = math.max(0, (split[from] or 0) - v)
    if split[from] == 0 then split[from] = nil end
    split[to] = Add(split[to] or 0, v)
end

---------------------------------------------------------------------------
-- Changes the Workshop page listens for (only while it is shown); a listener never runs when nothing changed
---------------------------------------------------------------------------
function Lg.Subscribe(fn) if type(fn) == "function" then listeners[fn] = true end end
function Lg.Unsubscribe(fn) listeners[fn] = nil end
local function Changed()
    revision = revision + 1
    for fn in pairs(listeners) do
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("gold ledger", err) end
    end
end
function Lg.Revision() return revision end
-- Something the page shows from another component (cost basis) changed; no cash entry did.
function Lg.Touch() Changed() end

---------------------------------------------------------------------------
-- Evidence: a completed transaction says what a money change was
---------------------------------------------------------------------------
local function Remember(corr)
    if not corr then return end
    seen[corr] = true
    seenList[#seenList + 1] = corr
    if #seenList > MAX_SEEN then seen[table.remove(seenList, 1)] = nil end
end

-- Observers of verified transactions (the cost basis, auction/LedgerCost.lua). They are told AFTER an entry was classified, with the
-- entry, the evidence and the character it belongs to; they can never change the entry or create one.
function Lg.OnAttached(fn, remove)
    if type(remove) == "function" then attachListeners[remove] = nil end
    if type(fn) == "function" then attachListeners[fn] = true end
end

local function Attach(slot, ev)
    local e = slot.e
    Move(slot.rec, Lg.DayOf(e.t), e.a, "other", ev.kind)
    e.k, e.e = ev.kind, Lg.SOURCES[ev.kind].evidence
    e.i, e.q, e.n, e.x = ev.item, ev.qty, ev.note, ev.corr
    e.u, e.s = ev.auction, ev.settlement
    Remember(ev.corr)
    stats.attributed = stats.attributed + 1
    for fn in pairs(attachListeners) do
        local ok, err = pcall(fn, slot.key, e, ev)
        if not ok and R.Fault then R.Fault("gold ledger", err) end
    end
end

local function Prune(now)
    local limit = now - Lg.RECENT_WINDOW
    for i = #pending, 1, -1 do
        if pending[i].gt < limit then table.remove(pending, i); stats.expired = stats.expired + 1 end
    end
    while recent[1] and recent[1].gt < limit do table.remove(recent, 1) end
end

local function Valid(ev)
    if type(ev) ~= "table" then return nil end
    local src = type(ev.kind) == "string" and ev.kind ~= "other" and Lg.SOURCES[ev.kind] or nil
    local amount = Signed(ev.amount)
    if not (src and amount) or (src.dir and (amount > 0) ~= (src.dir > 0)) then return nil end
    local corr = ev.corr
    if corr ~= nil and (type(corr) ~= "string" or corr == "" or #corr > MAX_CORR) then return nil end
    -- Optional exact journal target for observers that have already verified a particular movement.
    -- These fields are session-only; they never change the saved schema or enter the pending queue.
    local entry = ev.entry ~= nil and Whole(ev.entry, 1, MAX) or nil
    if (ev.entry ~= nil or ev.char ~= nil) and (not entry or type(Plain(ev.char)) ~= "string" or Plain(ev.char) ~= CharKey()) then return nil end
    -- Optional, session-only bag facts from an observer that verified them (never saved): the item identity and its carried count.
    local stock
    if type(ev.stock) == "table" then
        local key, before, after = Plain(ev.stock.key), Whole(ev.stock.before, 0, MAX_QTY), Whole(ev.stock.after, 0, MAX_QTY)
        if type(key) == "string" and #key <= 160 and before and after then stock = { key = key, before = before, after = after } end
    end
    return { kind = ev.kind, amount = amount, item = Whole(ev.item, 1, MAX_ITEM), qty = Whole(ev.qty, 1, MAX_QTY),
        note = Note(ev.note), corr = corr, entry = entry, char = ev.char, stock = stock,
        auction = (ev.kind == "ahDeposit" or ev.kind == "ahCancelFee") and Whole(ev.auction, 1, MAX) or nil,
        settlement = ev.kind == "ahSale" and Lg.Settlement(ev.settlement, amount) or nil }
end

-- Offers one completed transaction. Returns "attributed", "pending" (its money has not been seen yet), "ambiguous",
-- "repeated" (this correlation id was already used) or false and a reason. Never records money.
function Lg.Evidence(raw)
    if not active then return false, "inactive" end
    local ev = Valid(raw)
    if not ev then stats.refused = stats.refused + 1 return false, "invalid" end
    if ev.corr and seen[ev.corr] then stats.repeated = stats.repeated + 1 return "repeated" end
    local now = Mono()
    Prune(now)
    if ev.entry then
        local rec = Lg.Record(ev.char)
        for _, slot in ipairs(recent) do
            if slot.rec == rec and slot.e.id == ev.entry then
                if slot.e.k or slot.e.a ~= ev.amount then return false, "target" end
                Attach(slot, ev)
                Changed()
                return "attributed"
            end
        end
        return false, "target"
    end
    -- the money moved in this very frame: the entry the event just made
    local last = recent[#recent]
    if last and last.gt == now and not last.e.k and last.e.a == ev.amount then
        Attach(last, ev)
        Changed()
        return "attributed"
    end
    local found, count
    count = 0
    for _, slot in ipairs(recent) do
        if not slot.e.k and slot.e.a == ev.amount then found, count = slot, count + 1 end
    end
    if count == 1 then
        Attach(found, ev)
        Changed()
        return "attributed"
    elseif count > 1 then
        stats.ambiguous = stats.ambiguous + 1
        return "ambiguous"
    end
    pending[#pending + 1] = { ev = ev, gt = now }
    if #pending > MAX_PENDING then table.remove(pending, 1); stats.expired = stats.expired + 1 end
    return "pending"
end

-- A new entry looks for evidence that arrived first: the one of this very frame, otherwise the only one of that amount.
-- Two candidates that cannot be told apart attach nothing.
local function Claim(slot)
    local e = slot.e
    Prune(slot.gt)
    local all, same = {}, {}
    for i, p in ipairs(pending) do
        if p.ev.amount == e.a then
            all[#all + 1] = i
            if p.gt == slot.gt then same[#same + 1] = i end
        end
    end
    local index = (#same == 1 and same[1]) or (#same == 0 and #all == 1 and all[1]) or nil
    if not index then
        if #all > 1 then stats.ambiguous = stats.ambiguous + 1 end
        return
    end
    local p = table.remove(pending, index)
    if p.ev.corr and seen[p.ev.corr] then stats.repeated = stats.repeated + 1 return end
    Attach(slot, p.ev)
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local function Append(rec, t, day, delta, key)
    local e = { id = rec.nextId, t = t, a = delta, e = "balance" }
    rec.nextId = rec.nextId + 1
    local entries = rec.entries
    entries[#entries + 1] = e
    Bump(rec, day, delta, "other")
    if #entries > Lg.MAX_ENTRIES + Lg.TRIM_SLACK then Compact(rec, day) end
    local slot = { rec = rec, e = e, gt = Mono(), key = key }
    recent[#recent + 1] = slot
    if #recent > MAX_RECENT then table.remove(recent, 1) end
    stats.recorded = stats.recorded + 1
    if #pending > 0 then Claim(slot) end
    return slot
end

-- This character's record, made on first use; nil when nothing may be recorded for it.
local function Writable(key, name, realm, t)
    if held then return nil end
    local db = TwichUILedgerDB
    if type(db) ~= "table" or type(db.chars) ~= "table" then return nil end
    local rec = Lg.Record(key)
    if rec then return rec end
    local count = 0
    for _ in pairs(db.chars) do count = count + 1 end
    if count >= Lg.MAX_CHARS then return nil end
    rec = { name = name, realm = realm, since = t, nextId = 1, entries = {}, days = {}, tz = 1 }
    db.chars[key] = rec
    cleaned[key] = true
    return rec
end

-- One reading of the balance. The first reading of a session is a baseline and makes no entry; an unchanged balance makes
-- none; a reading that cannot be trusted changes nothing at all.
function Lg.Observe()
    if not active or held then return end
    if R.Life and R.Life.InWorld and not R.Life.InWorld() then return end   -- before the world is entered the balance may not be loaded
    stats.events = stats.events + 1
    local key, name, realm = CharKey()
    if not key then stats.invalid = stats.invalid + 1 return end
    local now = Whole(type(GetMoney) == "function" and GetMoney() or nil, 0, MAX)
    if not now then stats.invalid = stats.invalid + 1 return end
    local t, day = Clock()
    if not t then stats.invalid = stats.invalid + 1 return end
    if baseKey ~= key then base, baseKey = nil, key end   -- another character: their balances are never compared
    local rec = Writable(key, name, realm, t)
    if not rec then stats.refused = stats.refused + 1 return end
    local fresh = not rec.days[day]
    DayRecord(rec, day)   -- the recorder was running this day: a quiet day is then a day with no activity, not a gap
    if not rec.since then rec.since = t end
    if compacted[key] ~= day then compacted[key] = day; Compact(rec, day) end
    if base == nil then
        base = now
        stats.baselines = stats.baselines + 1
        if fresh then Changed() end
        return
    end
    local delta = now - base
    if delta == 0 then stats.duplicate = stats.duplicate + 1 return end
    base = now
    Append(rec, t, day, delta, key)
    Changed()
end

local function OnMoney()
    local Perf = R.Perf
    local pt = Perf and Perf.on and Perf.Start("ledger.record")
    Lg.Observe()
    if pt then Perf.Stop(pt) end
end

local function OnLogout()
    if not (active and base and baseKey) then return end
    local rec = Lg.Record(baseKey)
    local _, day = Clock()
    if rec and day then DayRecord(rec, day) end
end

local function Want(event, handler, wanted)
    if wanted and not watching[event] then
        watching[event] = handler
        R:On(event, handler)
    elseif not wanted and watching[event] then
        R:Off(event, watching[event])
        watching[event] = nil
    end
end

local function Stop()
    Want("PLAYER_MONEY", nil, false)
    Want("PLAYER_ENTERING_WORLD", nil, false)
    Want("PLAYER_LOGOUT", nil, false)
    base, baseKey = nil, nil
    for i = #recent, 1, -1 do recent[i] = nil end
    for i = #pending, 1, -1 do pending[i] = nil end
end

function Lg.Consent()
    local l = R.WorkshopLauncher
    return l ~= nil and l.Enabled ~= nil and l.Enabled() == true
end

-- Safe to call any time and as often as you like: makes the listening match the opt-in. The Workshop being turned off stops
-- new records and keeps the old ones.
function Lg.Refresh()
    local on = ready and not held and Lg.Consent()
    if on and not active then
        active = true
        Want("PLAYER_MONEY", OnMoney, true)
        Want("PLAYER_ENTERING_WORLD", Lg.Observe, true)
        Want("PLAYER_LOGOUT", OnLogout, true)
        Lg.Observe()   -- already in the world (turned on, or a profile changed): the baseline is taken now
    elseif not on and active then
        active = false
        Stop()
    end
    if R.MailGold then R.MailGold.Refresh() end   -- the mailbox reports its money to the ledger while this records
    if R.VendorGold then R.VendorGold.Refresh() end
    if R.QuestGold then R.QuestGold.Refresh() end
    if R.AuctionLedger then R.AuctionLedger.Refresh() end
    if R.LedgerCost then R.LedgerCost.Refresh() end
end

function Lg.Active() return active end
function Lg.Held() return held end
function Lg.Ready() return ready end

-- What the page needs to explain itself: is it recording, since when (this character), and why not.
function Lg.Status()
    local key = CharKey()
    local rec = key and Lg.Record(key)
    local why
    if held then why = "held"
    elseif not ready then why = "unavailable"
    elseif not Lg.Consent() then why = "off"
    elseif not active then why = "stopped" end
    return { active = active, held = held, why = why, key = key, since = rec and rec.since or nil }
end

-- Every character with a record: { { key, name, realm, since, entries } }, by name. Cleans each record the first time.
function Lg.Characters()
    local out = {}
    local db = TwichUILedgerDB
    if held or type(db) ~= "table" or type(db.chars) ~= "table" then return out end
    for key in pairs(db.chars) do
        local rec = Lg.Record(key)
        if rec then out[#out + 1] = { key = key, name = rec.name, realm = rec.realm, since = rec.since, entries = #rec.entries } end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

-- Counts only, for the diagnostics gauges and the tests. Read only.
function Lg.Snapshot()
    local key = CharKey()
    local rec = key and not held and type(TwichUILedgerDB) == "table" and type(TwichUILedgerDB.chars) == "table" and TwichUILedgerDB.chars[key] or nil
    local nl = 0
    for _ in pairs(listeners) do nl = nl + 1 end
    local ne, nd = 0, 0
    if type(rec) == "table" then
        ne = type(rec.entries) == "table" and #rec.entries or 0
        if type(rec.days) == "table" then for _ in pairs(rec.days) do nd = nd + 1 end end
    end
    local copy = {}
    for k, v in pairs(stats) do copy[k] = v end
    return { active = active, held = held, listeners = nl, entries = ne, days = nd, revision = revision, pending = #pending,
        recent = #recent, events = (watching.PLAYER_MONEY and 1 or 0) + (watching.PLAYER_ENTERING_WORLD and 1 or 0) + (watching.PLAYER_LOGOUT and 1 or 0),
        stats = copy }
end

if R.Perf and R.Perf.Gauge then
    local function Field(name) return function() return Lg.Snapshot()[name] end end
    R.Perf.Gauge("ledger.events", { label = "Gold ledger: events registered", unit = "count", kind = "listeners", group = "workshop", read = Field("events") })
    R.Perf.Gauge("ledger.entries", { label = "Gold ledger: this character's journal entries (bounded)", unit = "count", kind = "cache", group = "workshop", read = Field("entries") })
    R.Perf.Gauge("ledger.listeners", { label = "Gold ledger: page listeners", unit = "count", kind = "listeners", group = "workshop", read = Field("listeners") })
end

R:OnInit(function()
    Lg.Init()
    Lg.Refresh()
end)
