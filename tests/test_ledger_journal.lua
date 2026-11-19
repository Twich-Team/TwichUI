-- The gold ledger's recorder (auction/Ledger.lua): the journal, its baselines, aggregates, retention and saved-data
-- safety. The client, the clock and the balance are mocks: that the real game reports GetMoney()/PLAYER_MONEY as modelled
-- (and from when after login) is for an in-game check (docs/workshop/gold-ledger.md). Synthetic data only.
dofile(TESTS .. "harness.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function Fingerprint(v)
    if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = Fingerprint(k) .. "=" .. Fingerprint(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

local DAY = 86400
local T0 = 20000 * DAY + 12 * 3600   -- noon UTC of day 20000

-- A client at a given moment. `db` is the "saved file" (shared between clients to model a relog); `enabled` the Workshop opt-in.
local function Client(opts)
    opts = opts or {}
    local c = MakeClient(opts.name or "Rich", { "!!!TwichUI" })
    c.TwichUIDB = { modules = { chronicle = false }, ui = { workshopEnabled = opts.enabled ~= false } }
    c.TwichUILedgerDB = opts.db
    c.NOW, c.MONO, c.MONEY = opts.now or T0, 100, opts.money == nil and 1000000 or opts.money
    c.GetServerTime = function() return c.NOW end
    c.GetTime = function() return c.MONO end
    c.GetMoney = function() return c.MONEY end
    if opts.realm then c.GetRealmName = function() return opts.realm end end
    for _, f in ipairs({ "WorkshopLauncher.lua", "auction/Ledger.lua" }) do
        local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
    end
    c.LOADED["!!!TwichUI"] = true
    c.FireEvent("ADDON_LOADED", "!!!TwichUI")
    c.FireEvent("PLAYER_LOGIN")
    if opts.world ~= false then c.FireEvent("PLAYER_ENTERING_WORLD", true, false) end
    c.R = c.TwichUI
    c.L = c.R.Ledger
    -- the balance moves, the game says so (a frame passes first unless told otherwise)
    function c.Set(v, frame) c.MONEY = v; if frame ~= false then c.MONO = c.MONO + 1 end; c.FireEvent("PLAYER_MONEY") end
    function c.Rec() return c.TwichUILedgerDB.chars[opts.key or ((opts.name or "Rich") .. " - Forever")] end
    return c
end

local function Sum(rec, field) local n = 0 for _, d in pairs(rec.days) do n = n + d[field] end return n end

-- 1. First reading is a baseline: no entry, but the day is recorded (a quiet day is not a gap)
do
    local c = Client()
    local rec = c.Rec()
    Check(rec, "the character's record exists after the first reading")
    Same(#rec.entries, 0, "the baseline made no entry")
    Same(rec.since, T0, "recording start")
    Check(rec.days[20000] and rec.days[20000].n == 0, "the day is recorded with no activity")
    Same(c.TwichUILedgerDB.version, 1)
    Check(c.L.Active(), "recording while the Workshop is on")
    Same(c.L.Snapshot().events, 3, "three listeners while recording")
end

-- 2. Positive and negative changes, exact copper, and the day aggregates
do
    local c = Client()
    c.Set(1000000 + 12345)
    c.Set(1000000 + 12345 - 500)
    local rec = c.Rec()
    Same(#rec.entries, 2)
    Same(rec.entries[1].a, 12345); Same(rec.entries[2].a, -500)
    Same(rec.entries[1].id, 1); Same(rec.entries[2].id, 2)
    Same(rec.entries[1].e, "balance"); Check(rec.entries[1].k == nil, "unclassified carries no source")
    local d = rec.days[20000]
    Same(d.i, 12345); Same(d.o, 500); Same(d.n, 2)
    Same(d.ci.other, 12345); Same(d.co.other, 500)
end

-- 3. Duplicate notifications with an unchanged balance create nothing
do
    local c = Client()
    c.Set(1000100)
    c.Set(1000100); c.Set(1000100)
    Same(#c.Rec().entries, 1)
    Same(c.L.Snapshot().stats.duplicate, 2)
end

-- 4. Changes that happened between two readings arrive as one exact difference
do
    local c = Client()
    c.MONEY = 1000000 + 5; c.MONEY = c.MONEY + 3          -- two changes before the game says anything
    c.FireEvent("PLAYER_MONEY")
    local rec = c.Rec()
    Same(#rec.entries, 1); Same(rec.entries[1].a, 8)
end

-- 5. Unreadable, secret, negative, fractional, non-finite values change nothing; the next good reading is exact
do
    local c = Client()
    local bad = { "nil", "negative", "fraction", "nan", "inf", "string", "secret", "huge" }
    c.issecretvalue = function(v) return v == "SECRET" end
    for _, kind in ipairs(bad) do
        c.GetMoney = function()
            if kind == "nil" then return nil
            elseif kind == "negative" then return -5
            elseif kind == "fraction" then return 1000000.5
            elseif kind == "nan" then return 0 / 0
            elseif kind == "inf" then return math.huge
            elseif kind == "string" then return "1000001"
            elseif kind == "secret" then return "SECRET"
            else return 1e300 end
        end
        c.FireEvent("PLAYER_MONEY")
    end
    Same(#c.Rec().entries, 0, "no entry from any unusable reading")
    Same(c.L.Snapshot().stats.invalid, #bad)
    c.GetMoney = function() return c.MONEY end
    c.Set(1000000 + 77)
    Same(c.Rec().entries[1].a, 77, "the baseline survived the bad readings")
end

-- 6. Relog and reload: nothing is invented for the time away; the journal persists
do
    local c1 = Client()
    c1.Set(1000900)
    local db = c1.TwichUILedgerDB
    local c2 = Client({ db = db, money = 5000000, now = T0 + 3600 })   -- a lot more gold on return
    Same(#c2.Rec().entries, 1, "the earlier entry is kept")
    c2.Set(5000050)
    Same(#c2.Rec().entries, 2); Same(c2.Rec().entries[2].a, 50, "only the change seen this session")
    Same(c2.Rec().entries[2].id, 2, "ids continue")
    Same(c2.Rec().since, T0, "recording start is the first session's")
end

-- 7. Characters and realms are separate records; a change of character never compares their balances
do
    local c1 = Client({ name = "Rich", money = 100 })
    c1.Set(150)
    local db = c1.TwichUILedgerDB
    local c2 = Client({ db = db, name = "Ann", money = 9000000 })
    c2.Set(9000010)
    local c3 = Client({ db = db, name = "Rich", realm = "OtherRealm", money = 5, key = "Rich - OtherRealm" })
    c3.Set(25)
    Same(#db.chars["Rich - Forever"].entries, 1); Same(db.chars["Rich - Forever"].entries[1].a, 50)
    Same(#db.chars["Ann - Forever"].entries, 1); Same(db.chars["Ann - Forever"].entries[1].a, 10)
    Same(#db.chars["Rich - OtherRealm"].entries, 1); Same(db.chars["Rich - OtherRealm"].entries[1].a, 20)
    Same(db.chars["Rich - OtherRealm"].realm, "OtherRealm")
    local list = c3.L.Characters()
    Same(#list, 3, "every character with a record")
    -- the same client changing character mid-session: the old balance is not the new character's baseline
    local c = Client({ name = "Rich", money = 1000 })
    c.Set(2000)
    c.UnitName = function() return "Mallory" end
    c.Set(3000)
    Same(#c.TwichUILedgerDB.chars["Mallory - Forever"].entries, 0, "first reading of another character is a baseline")
    Same(#c.TwichUILedgerDB.chars["Rich - Forever"].entries, 1)
end

-- 8. UTC date boundaries
do
    local c = Client({ now = 20001 * DAY - 1 })
    c.Set(1000010)                       -- 23:59:59 of day 20000
    c.NOW = 20001 * DAY; c.Set(1000030)  -- 00:00:00 of day 20001
    c.NOW = 20001 * DAY + 5; c.Set(1000025)
    local rec = c.Rec()
    Same(rec.days[20000].i, 10); Same(rec.days[20000].o, 0)
    Same(rec.days[20001].i, 20); Same(rec.days[20001].o, 5)
    Same(rec.entries[1].t, 20001 * DAY - 1); Same(rec.entries[2].t, 20001 * DAY)
    -- a day with no change is a recorded day; one never seen has no record
    c.NOW = 20003 * DAY; c.Set(1000025, true)
    Check(rec.days[20003] and rec.days[20003].n == 0, "quiet day recorded")
    Check(rec.days[20002] == nil, "a day with no session is outside coverage")
end

-- 9. Retention: the journal is bounded, its totals are kept; old days and old entries go together
do
    local c = Client()
    local L = c.L
    Same(L.MAX_ENTRIES, 2000)
    local rec = c.Rec()
    local expectIn, expectOut = 0, 0
    for i = 1, L.MAX_ENTRIES + L.TRIM_SLACK + 10 do
        local d = (i % 2 == 0) and i or -i
        c.MONEY = c.MONEY + d
        expectIn = expectIn + (d > 0 and d or 0); expectOut = expectOut + (d < 0 and -d or 0)
        c.MONO = c.MONO + 1
        c.FireEvent("PLAYER_MONEY")
    end
    Check(#rec.entries <= L.MAX_ENTRIES + L.TRIM_SLACK, "bounded journal")
    Check(#rec.entries >= L.MAX_ENTRIES, "kept at least the bound")
    Same(rec.days[20000].i, expectIn, "dropped entries stay in the day's totals")
    Same(rec.days[20000].o, expectOut)
    Same(rec.entries[#rec.entries].id, L.MAX_ENTRIES + L.TRIM_SLACK + 10, "ids are never reused")
    -- old days and old entries are compacted at load, together; the retained totals are untouched
    local db = c.TwichUILedgerDB
    local r = db.chars["Rich - Forever"]
    r.days[20000 - 100] = { i = 5, o = 0, n = 1, ci = {}, co = {} }
    r.days[20000 - 89] = { i = 7, o = 0, n = 1, ci = {}, co = {} }
    table.insert(r.entries, 1, { id = 0 + 999999, t = (20000 - 100) * DAY, a = 5, e = "balance" })
    local c2 = Client({ db = db, now = T0 + 86400 * 0 })
    local r2 = c2.Rec()
    Check(r2.days[20000 - 100] == nil, "a day past the retention is gone")
    Check(r2.days[20000 - 89] ~= nil, "the oldest retained day (90 days, today included) is kept")
    for _, e in ipairs(r2.entries) do Check(e.t >= (20000 - 89) * DAY, "no entry older than the retention") end
    Same(r2.days[20000].i, expectIn, "retained totals untouched by compaction")
end

-- 10. Saved data: newer version held aside and untouched; damaged parts repaired narrowly
do
    local future = { version = 99, chars = { ["Rich - Forever"] = { entries = { { id = 1, t = 1, a = 5 } }, secret = "kept" } } }
    local print_ = Fingerprint(future)
    local c = Client({ db = future })
    Check(c.L.Held(), "a newer ledger is held")
    Check(not c.L.Active(), "nothing is recorded to a held ledger")
    c.Set(1000100)
    Same(#c.L.Characters(), 0)
    c.TwichUI.Persist.Release()
    Same(Fingerprint(c.TwichUILedgerDB), print_, "the newer ledger is handed back byte for byte")

    local bad = { version = "x", chars = {
        ["Rich - Forever"] = { name = 5, since = "soon", nextId = 2, entries = {
            { id = 5, t = T0 - 10, a = 40, k = "mail", e = "wrong", i = 99, q = -1, n = "a|cffff0000red|r note" },
            { id = 6, t = T0 - 5, a = 0 }, { id = 7, t = "x", a = 1 }, "junk", { id = 8, t = T0 - 4, a = -9, k = "ahSale" },
            { id = 2, t = T0 - 20, a = 1, k = "bogus" },
        }, days = { [20000] = { i = 40, o = "x", n = 1, ci = { mail = 40, ghost = 7 } }, ["bad"] = {}, [20001] = 5 } },
        ["Ann - Forever"] = "oops",
        [7] = {},
    } }
    local c2 = Client({ db = bad })
    local rec = c2.Rec()
    Check(rec, "a damaged record is repaired, not reset")
    Same(#rec.entries, 3, "invalid entries dropped, the rest kept")
    Same(rec.entries[1].id, 2); Same(rec.entries[1].k, nil, "unknown source cleared")
    Same(rec.entries[2].id, 5); Same(rec.entries[2].k, "mail"); Same(rec.entries[2].e, "mailbox", "evidence follows the source")
    Same(rec.entries[2].i, 99); Same(rec.entries[2].q, nil)
    Check(not rec.entries[2].n:find("|"), "an escape sequence is stripped from a note")
    Same(rec.entries[3].id, 8); Same(rec.entries[3].k, nil, "a source cannot move gold the other way")
    Check(rec.nextId > 8, "ids continue past the largest")
    Same(rec.days[20000].o, 0); Same(rec.days[20000].ci.mail, 40); Check(rec.days[20000].ci.ghost == nil)
    Check(c2.TwichUILedgerDB.chars["Ann - Forever"] == nil and c2.TwichUILedgerDB.chars[7] == nil, "records that are not records are dropped")
    Same(c2.TwichUILedgerDB.version, 1, "an unreadable version is read as the current layout")
    local report = c2.TwichUI.Persist.Report()
    Check((report.repairs["ledger-entry-dropped"] or 0) >= 3, "dropped entries are counted")
end

-- 11. Overflow: totals saturate at the largest exact integer, never wrap or lose exactness
do
    local MAXM = 9007199254740991
    local c = Client({ money = 0 })
    c.Set(MAXM)
    Same(c.Rec().entries[1].a, MAXM, "the largest exact amount")
    c.Set(0)
    Same(c.Rec().entries[2].a, -MAXM)
    c.Set(MAXM)
    local d = c.Rec().days[20000]
    Same(d.i, MAXM, "the total saturates"); Same(d.o, MAXM)
    c.GetMoney = function() return MAXM + 2 end
    c.FireEvent("PLAYER_MONEY")
    Same(#c.Rec().entries, 3, "a balance past the supported range is unusable")
end

-- 12. Opt-in: no listeners without the Workshop; turning it off stops recording and keeps the records; on again re-baselines
do
    local off = Client({ enabled = false })
    Check(not off.L.Active() and off.L.Snapshot().events == 0, "nothing listens while the Workshop is off")
    Check(off.TwichUILedgerDB.chars["Rich - Forever"] == nil, "and nothing is made")
    off.Set(1000010)
    Same(off.L.Snapshot().stats.recorded, 0)

    local c = Client()
    c.Set(1000010)
    local counts = {}; c.R.ListenerCounts(counts)
    Same(counts.PLAYER_MONEY or 0, 1, "one money listener")
    local logoutBefore = counts.PLAYER_LOGOUT or 0
    c.TwichUIDB.ui.workshopEnabled = false
    c.R.WorkshopLauncher.Apply()
    Check(not c.L.Active(), "turned off")
    counts = {}; c.R.ListenerCounts(counts)
    Same(counts.PLAYER_MONEY or 0, 0, "the listeners are released"); Same(counts.PLAYER_LOGOUT or 0, logoutBefore - 1)
    c.Set(1000990)
    Same(#c.Rec().entries, 1, "old records kept, nothing new")
    c.TwichUIDB.ui.workshopEnabled = true
    c.R.WorkshopLauncher.Apply()
    Check(c.L.Active(), "turned on again")
    Same(#c.Rec().entries, 1, "the gap is not turned into income")
    c.Set(1001000)
    Same(#c.Rec().entries, 2); Same(c.Rec().entries[2].a, 10, "recording resumes from a fresh baseline")
    c.R.WorkshopLauncher.Apply(); c.R.WorkshopLauncher.Apply()
    counts = {}; c.R.ListenerCounts(counts)
    Same(counts.PLAYER_MONEY or 0, 1, "repeated refreshes add no listeners")
end

-- 13. Before the world is entered nothing is read (the balance may not be loaded yet)
do
    local c = Client({ world = false, money = 0 })
    c.Set(5000)
    Same(c.L.Snapshot().stats.events, 0)
    Check(c.Rec() == nil, "no record before the world")
    c.MONEY = 7000
    c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    Same(#c.Rec().entries, 0, "entering the world takes the baseline")
    c.Set(7001)
    Same(c.Rec().entries[1].a, 1)
end

-- 14. Subscribers hear about changes; a failing subscriber does not stop recording
do
    local c = Client()
    local heard = 0
    c.L.Subscribe(function() heard = heard + 1 end)
    c.L.Subscribe(function() error("boom") end)
    c.geterrorhandler = function() return function() end end
    local r0 = c.L.Revision()
    c.Set(1000001)
    Check(heard >= 1 and c.L.Revision() > r0)
    Same(#c.Rec().entries, 1)
    c.Set(1000001)
    local r1 = c.L.Revision()
    c.Set(1000001)
    Same(c.L.Revision(), r1, "no change, no notification")
end

-- 15. A large history opens quickly (character records are cleaned once, and never rebuilt for a money event)
do
    local db = { version = 1, chars = {} }
    for k = 1, 10 do
        local entries, days = {}, {}
        for i = 1, 2000 do entries[i] = { id = i, t = T0 - 2000 + i, a = (i % 3 == 0) and -i or i, e = "balance" } end
        for d = 0, 89 do days[20000 - d] = { i = 1, o = 1, n = 1, ci = { other = 1 }, co = { other = 1 } } end
        db.chars["Char" .. k .. " - Forever"] = { name = "Char" .. k, realm = "Forever", since = T0 - 3000, nextId = 2001, entries = entries, days = days }
    end
    local c = Client({ db = db })
    local started = os.clock()
    local list = c.L.Characters()
    local took = os.clock() - started
    Same(#list, 11, "ten stored characters and this one")
    Check(took < 1.5, "cleaning ten full journals took " .. took)
    local before = os.clock()
    for i = 1, 200 do c.Set(1000000 + i) end
    Check(os.clock() - before < 1, "a money event does not scan the history")
end

print("LEDGER JOURNAL PASSED")
