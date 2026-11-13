-- Updating prices on opening the auction house (A6): the core detector (WorkshopAuto.lua), the policy (TwichUI_Workshop/Auto.lua), the shared
-- scanner's automatic start, Stop, give-way, provenance and the gates, against a fake auction house, fake timers and a fake clock. The core is the
-- real core; the Workshop is loaded the way the launcher loads it (lazily, on the first visit that needs it).
-- Synthetic: it proves our logic. Whether the real client accepts an automatic ReplicateItems is for the Test Lab probes (autoscan.*).
dofile(TESTS .. "harness.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua",
    "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Auto.lua", "Session.lua" }

local function Ser(v)
    if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

---------------------------------------------------------------------------
-- A client: the real core, a lazily loaded Workshop, a fake auction house
---------------------------------------------------------------------------
local function Setup(opts)
    opts = opts or {}
    local c = MakeClient("Rich", { "!!!TwichUI" })
    c.print = function() end
    local clock, timers, base = 0, {}, 100 * 86400 + 43200
    c.GetTime = function() return clock end
    c.time = function() return base + math.floor(clock) end
    local own = 0   -- timers made by WorkshopAuto.lua itself (other modules schedule theirs on the same events)
    c.C_Timer = { After = function(d, fn)
        local src = debug.getinfo(2, "S").source
        if src:find("WorkshopAuto", 1, true) then own = own + 1 end
        timers[#timers + 1] = { at = clock + d, fn = fn }
    end }
    c.GetRealmName = function() return "Realm" end
    c.COMBAT = false
    c.InCombatLockdown = function() return c.COMBAT end
    local ah = { ready = true, sent = 0, records = {}, side = "Alliance", fails = false }
    for i = 1, 30 do ah.records[i] = { item = 1000 + i, count = 1, buyout = 500 + i } end
    c.C_AuctionHouse = {
        IsThrottledMessageSystemReady = function() return ah.ready end,
        ReplicateItems = function() ah.sent = ah.sent + 1; if ah.fails then error("refused") end end,
        GetNumReplicateItems = function() return #ah.records end,
        GetReplicateItemInfo = function(i)
            local r = ah.records[i + 1]
            if not r then return end
            return "n", 1, r.count, 1, true, 1, "", 0, 0, r.buyout, 0, nil, nil, "o", "o", 0, r.item, true
        end,
    }
    c.UnitFactionGroup = function() return ah.side end
    c.AuctionHouseFrame = { shown = true, IsShown = function(s) return s.shown end, HookScript = function() end }
    local loads = 0
    c.C_AddOns.LoadAddOn = function()
        loads = loads + 1
        for _, f in ipairs(FILES) do
            local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
        end
        c.TwichUI.Workshop.ready = true
        c.TwichUI.Workshop.Prices.RECORD_HISTORY = true
        return true
    end
    for _, f in ipairs({ "WorkshopLauncher.lua", "WorkshopAuto.lua" }) do
        local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
    end
    c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
    c.FireEvent("PLAYER_LOGIN")
    local R = c.TwichUI
    local t = { c = c, R = R, ah = ah, WA = R.WorkshopAuto }
    if opts.capability ~= false then t.WA.CAPABILITY = opts.capability or "supported" end
    function t.W() return R.Workshop end
    function t.Loads() return loads end
    function t.Advance(sec)
        local target = clock + sec
        while true do
            local best, bi
            for i, tm in ipairs(timers) do if tm.at <= target and (not best or tm.at < best.at) then best, bi = tm, i end end
            if not best then break end
            table.remove(timers, bi)
            if best.at > clock then clock = best.at end
            best.fn()
        end
        clock = target
    end
    function t.Pending() return #timers end
    -- runs the earliest timer only, whatever its time (the steps of a long read, one at a time)
    function t.Tick()
        local best, bi
        for i, tm in ipairs(timers) do if not best or tm.at < best.at then best, bi = tm, i end end
        if not best then return false end
        table.remove(timers, bi)
        if best.at > clock then clock = best.at end
        best.fn()
        return true
    end
    -- from a started scan to the middle of its reading: the listings arrive and the steps are run one by one until the reading has begun
    function t.ToReading()
        t.Advance(0.5); t.Reply()
        local guard = 0
        while t.W().Scan.phase ~= "reading" and guard < 100 do t.Tick(); guard = guard + 1 end
        return t.W().Scan.phase == "reading"
    end
    function t.OwnTimers() return own end
    function t.Open() c.AuctionHouseFrame.shown = true; c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21); t.Advance(0.01) end
    function t.Close() c.AuctionHouseFrame.shown = false; c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21); c.FireEvent("AUCTION_HOUSE_CLOSED") end
    function t.Reply() c.FireEvent("REPLICATE_ITEM_LIST_UPDATE") end
    -- runs a started scan to its end the way the game would: the listings arrive, the quiet period passes, the reading and saving steps run
    function t.Finish()
        t.Advance(0.5); t.Reply(); t.Advance(60)
    end
    function t.Saved() return Ser(c.TwichUIWorkshopDB) end
    function t.Market() local W = t.W(); local key = W.Scan.Market(); return W.Prices.Market(key) end
    function t.Minutes(m) t.Advance(m * 60) end
    return t
end

---------------------------------------------------------------------------
-- Pure: freshness and the decision
---------------------------------------------------------------------------
do
    local t = Setup({ capability = false })
    t.WA.CAPABILITY = "unknown"
    t.Open()   -- loads the Workshop so its pure functions exist (the default capability is unknown, so this only prompts)
    local A = t.W().Auto
    local H = 3600
    Check(not A.Fresh(nil, 1000), "no time: due")
    Check(not A.Fresh(0 / 0, 1000), "NaN time: due")
    Check(A.Fresh(1000, 1000 + H - 1), "59 min 59 s: fresh")
    Check(not A.Fresh(1000, 1000 + H), "exactly 60 minutes: due")
    Check(A.Fresh(1000 + 60, 1000), "a time a minute in the future is within the skew: fresh")
    Check(not A.Fresh(1000 + 7200, 1000), "a time two hours ahead means the clock moved back: not trusted as fresh")
    Check(A.Fresh(nil, 1000, 10), "a scan accepted earlier this session (monotonic) is fresh whatever the wall clock says")
    Check(not A.Fresh(nil, 1000, H + 1), "...until an hour has passed")
    local base = { enabled = true, open = true, key = "Realm|Alliance", now = 5000, capability = "supported" }
    local function D(over) local c = {} for k, v in pairs(base) do c[k] = v end for k, v in pairs(over or {}) do c[k] = v end return A.Decide(c) end
    Same(D(), "scan", "due, supported: scan")
    Same(select(2, D({ enabled = false })), "disabled")
    Same(select(2, D({ combat = true })), "combat")
    Same(select(2, D({ open = false })), "closed")
    Same(select(2, D({ handled = true })), "visit")
    Same(select(2, D({ key = false })), "market")
    Same(select(2, D({ held = true })), "held")
    Same(select(2, D({ busy = true })), "busy")
    Same(select(2, D({ posting = true })), "posting")
    Same(select(2, D({ at = 5000 - 100 })), "fresh")
    Same(select(2, D({ backoffLeft = 30 })), "backoff")
    Same(D({ backoffLeft = 0 }), "scan", "an expired backoff does not block")
    Same(D({ capability = "unknown" }), "prompt"); Same(select(2, D({ capability = "unknown" })), "unverified")
    Same(D({ capability = "click" }), "prompt"); Same(select(2, D({ capability = "click" })), "click")
    Same(D({ capability = "anything" }), "prompt", "an unrecognised capability is never treated as supported")
end

---------------------------------------------------------------------------
-- The setting and the detector
---------------------------------------------------------------------------
do
    local t = Setup()
    Check(t.R.DEFAULT_MODULES.workshopAutoScan == true and t.R:Enabled("workshopAutoScan"), "on by default")
    Check(t.R.Switches.defs.workshopAutoScan ~= nil, "the switch is defined")
    Same(t.WA.Capability(), "supported"); t.WA.CAPABILITY = "bogus"; Same(t.WA.Capability(), "unknown"); t.WA.CAPABILITY = "supported"
    Same(t.Loads(), 0, "nothing is loaded at login")
    Same(t.OwnTimers(), 0, "no timers at login")
end

-- disabled: no load, no timers, no request
do
    local t = Setup()
    t.R:SetEnabled("workshopAutoScan", false)
    t.Open()
    Same(t.Loads(), 0, "disabled: the Workshop is not loaded"); Same(t.OwnTimers(), 0, "disabled: no timer chain"); Same(t.ah.sent, 0)
    Same(t.WA.Snapshot().skipped, "disabled")
    t.Close(); t.R:SetEnabled("workshopAutoScan", true); t.Open()
    Same(t.Loads(), 1, "turned on again: the next visit loads it")
end

-- combat: never loads
do
    local t = Setup()
    t.c.COMBAT = true
    t.Open()
    Same(t.Loads(), 0, "in combat: no load"); Same(t.ah.sent, 0); Same(t.WA.Snapshot().skipped, "combat")
    t.c.COMBAT = false; t.Advance(10)
    Same(t.Loads(), 0, "leaving combat does not retry the same visit")
end

-- a window that never shows (a stale event) loads nothing and does not swallow the next opening
do
    local t = Setup()
    t.c.AuctionHouseFrame.shown = false
    t.c.FireEvent("AUCTION_HOUSE_SHOW")
    t.Advance(10)
    Same(t.Loads(), 0, "no window: no load"); Same(t.WA.Snapshot().skipped, "noWindow"); local n = t.OwnTimers(); t.Advance(30); Same(t.OwnTimers(), n, "the wait is bounded")
    t.Open()
    Same(t.Loads(), 1, "a real opening afterwards is a new visit")
    -- the window appearing a moment after the event is still found
    local u = Setup()
    u.c.AuctionHouseFrame.shown = false
    u.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21); u.Advance(1)
    Same(u.Loads(), 0); u.c.AuctionHouseFrame.shown = true; u.Advance(1)
    Same(u.Loads(), 1, "found within the wait")
    -- an interaction that is not the auctioneer is not a visit
    local v = Setup()
    v.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8); v.Advance(1)
    Same(v.Loads(), 0); Same(v.WA.Snapshot().visits, 0)
end

-- closing before the window check: nothing loads; a stale timer of an old visit does nothing
do
    local t = Setup()
    t.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
    t.c.FireEvent("AUCTION_HOUSE_CLOSED")
    t.Advance(10)
    Same(t.Loads(), 0, "closed before the check: no load"); Same(t.ah.sent, 0)
    -- close and reopen at once: only the second visit acts, once
    local u = Setup()
    u.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
    u.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21)
    u.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
    u.Advance(1)
    Same(u.Loads(), 1); Same(u.ah.sent, 1, "one request for the quick close and reopen"); Same(u.WA.Snapshot().visits, 2)
end

---------------------------------------------------------------------------
-- A visit that scans: one request, provenance, saved format
---------------------------------------------------------------------------
do
    local t = Setup()
    -- several equivalent events are one visit
    t.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21); t.c.FireEvent("AUCTION_HOUSE_SHOW"); t.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
    t.Advance(1)
    Same(t.WA.Snapshot().visits, 1, "equivalent events are one visit"); Same(t.Loads(), 1); Same(t.ah.sent, 1, "one request")
    local W = t.W()
    Check(W.Scan.Busy() and W.Scan.auto == true, "an automatic scan runs")
    Same(W.Scan.Message(), "Updating market prices...")
    t.Finish()
    Same(W.Scan.state, "done"); Same(W.Scan.Message(), "Market prices updated.")
    local m = t.Market()
    Check(m and m.format == 3 and m.snap and m.snap.auto == true, "the snapshot says automatic")
    local log = W.Prices.ScanLog(m)
    Check(log and #log == 1 and log[1].flags % (2 * W.Prices.SCAN_FLAGS.AUTO) >= W.Prices.SCAN_FLAGS.AUTO, "the scan log carries the automatic flag")
    Same(W.Prices.DbVersion(), W.Prices.SAVED_VERSION, "the database version is unchanged")
    Check(m.h2 ~= nil or m.h2info ~= nil, "the version-2 history was recorded")
    -- a second visit within the hour: no request, a quiet skip
    t.Close(); t.Minutes(10); t.Open()
    Same(t.ah.sent, 1, "no second scan within 60 minutes"); Same(t.W().Auto.state.why, "fresh")
    Check(not W.Scan.Busy())
    -- a visit just before the hour ends is still fresh, just after it is due
    t.Close(); t.Minutes(49); t.Open()
    Same(t.ah.sent, 1, "59 minutes after the scan"); 
    t.Close(); t.Minutes(2); t.Open()
    Same(t.ah.sent, 2, "after 60 minutes the market is due again")
    t.Finish()
    Same(#W.Prices.ScanLog(t.Market()), 2, "both scans are logged")
    -- the other side's auction house is a market of its own
    t.Close(); t.ah.side = "Horde"; t.Open()
    Same(t.ah.sent, 3, "a different market is scanned independently, the other faction's scan does not count")
    t.Finish()
    Check(W.Prices.Market("Realm|Horde") and W.Prices.Market("Realm|Alliance"), "two markets")
end

-- unchanged saved data when the scan is refused, stopped or interrupted
do
    local t = Setup()
    t.Open(); t.Finish()                      -- one accepted scan to protect
    local before = t.Saved()
    t.Close(); t.Minutes(61)
    t.ah.fails = true; t.Open()               -- the request is refused by the client
    local W = t.W()
    Same(W.Scan.state, "failed"); Same(W.Scan.why, "api"); Same(W.Scan.Message(), "Automatic update unavailable. You can update prices manually. Your earlier prices were kept.")
    Same(t.ah.sent, 3 - 1, "one request for this visit")
    Same(t.Saved(), before, "a refused request changes nothing saved")
    -- the refusal backs the market off for 15 minutes of this session: no retry, whatever the clock says
    t.Close(); t.Minutes(5); t.ah.fails = false; t.Open()
    Same(t.ah.sent, 2, "no automatic attempt during the backoff"); Same(W.Auto.state.why, "backoff")
    t.Close(); t.Minutes(11); t.Open()
    Same(t.ah.sent, 3, "after 15 minutes an attempt is allowed again")
    -- ... and the visit still made only one
    t.Reply(); t.Advance(0.5)
    Same(t.ah.sent, 3, "one attempt per visit")
    t.Finish()
end

-- a manual scan is never blocked by the automatic policy
do
    local t = Setup()
    t.Open(); t.Finish()
    local W = t.W()
    Check(W.Scan.state == "done")
    local ok = W.Session.StartScan()
    Check(ok, "a manual scan right after an automatic one starts"); Same(t.ah.sent, 2)
    Check(W.Scan.auto == false, "a manual scan is not marked automatic")
    t.Finish()
    Check(t.Market().snap.auto == false, "the manual snapshot is not marked automatic")
    -- refusal backoff does not stop the manual path either
    t.Close(); t.Minutes(61); t.ah.fails = true; t.Open()
    Same(W.Scan.why, "api"); t.ah.fails = false
    Check(W.Session.StartScan(), "manual start during the backoff"); t.Finish(); Same(W.Scan.state, "done")
end

-- one scan already running
do
    local t = Setup()
    t.Open()
    local W = t.W()
    Check(W.Scan.Busy())
    local a, why = W.Auto.Visit(99)   -- a second call for an unknown/stale visit does nothing
    Same(a, "skip"); Check(why == "closed" or why == "busy" or why == "visit", why)
    Same(t.ah.sent, 1)
end

-- unknown or click-only capability: a prompt, no request, and the click is a manual scan
for _, cap in ipairs({ "unknown", "click" }) do
    local t = Setup({ capability = cap })
    t.Open()
    local W = t.W()
    Same(t.ah.sent, 0, cap .. ": no request is made without a click"); Same(W.Auto.state.action, "prompt"); Check(W.Auto.Prompting())
    Same(t.Loads(), 1)
    -- the visit's one automatic attempt was not used by a prompt; the player's click is a manual scan
    Check(W.Session.StartScan()); W.Auto.Answered()
    Same(t.ah.sent, 1); Check(W.Scan.auto == false, "the click is manual")
    t.Finish()
    Check(t.Market().snap.auto == false); Check(not W.Auto.Prompting())
    -- a fresh market raises no prompt
    t.Close(); t.Minutes(5); t.Open()
    Check(not W.Auto.Prompting(), "fresh: nothing to offer")
end

-- the posting search and the player's own requests
do
    local t = Setup()
    t.c.TwichUI.AuctionScan = { Busy = function() return true end }
    t.Open()
    Same(t.ah.sent, 0, "posting search busy: no automatic scan"); Same(t.W().Auto.state.why, "posting")
    local u = Setup()
    u.ah.ready = false                           -- waiting for the throttle
    u.Open()
    local W = u.W()
    Check(W.Scan.Busy() and W.Scan.phase == "waiting", "an automatic scan waits for the game")
    u.c.FireEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")   -- the player searched meanwhile
    Same(W.Scan.state, "interrupted"); Same(W.Scan.why, "busy"); Same(u.ah.sent, 0, "it gave way instead of asking")
    u.ah.ready = true; u.c.FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY"); Same(u.ah.sent, 0, "a late ready event starts nothing")
    -- a manual scan keeps waiting through another request
    local m = Setup()
    m.ah.ready = false; m.Open(); m.W().Auto.Reset()
    m.W().Scan.Start(nil, nil); -- already running (auto): refused
    local x = Setup({ capability = "unknown" })
    x.ah.ready = false; x.Open()
    Check(x.W().Session.StartScan()); x.c.FireEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
    Check(x.W().Scan.Busy() and x.W().Scan.phase == "waiting", "a manual scan is not given up by another request")
end

---------------------------------------------------------------------------
-- Stop, and closing
---------------------------------------------------------------------------
do
    -- stop while waiting
    local t = Setup(); t.Open(); t.Finish()
    local good = t.Saved()
    t.Close(); t.Minutes(61); t.ah.ready = false; t.Open()
    local W = t.W()
    Check(W.Scan.Busy()); Check(W.Scan.Stop()); Same(W.Scan.why, "stopped"); Check(not W.Scan.Busy())
    t.ah.ready = true; t.c.FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY"); t.Advance(120)
    Same(t.ah.sent, 1, "a stopped scan never sends later"); Same(t.Saved(), good, "stopped while waiting: nothing written")
    Check(not W.Scan.Stop(), "stopping with nothing running is refused")
    -- stop while awaiting the answer, then the answer arrives
    t.Close(); t.Minutes(20); t.ah.ready = true; t.WA.CAPABILITY = "unknown"; t.Open()   -- (a prompt this time: the scans below are the player's)
    Check(W.Session.StartScan(), "manual after the stopped one"); Same(W.Scan.phase, "awaiting")
    Check(W.Scan.Stop()); t.Reply(); t.Advance(60)
    Same(t.Saved(), good, "stopped before reading: the late listings change nothing"); Same(W.Scan.state, "interrupted")
    Same(W.Scan.Message(), "The scan was stopped. Nothing was changed. Your earlier prices were kept.")
    -- stop in the middle of reading: many records so the read takes several steps
    t.ah.records = {}
    for i = 1, 5000 do t.ah.records[i] = { item = 2000 + i, count = 1, buyout = 100 + i } end
    local s0 = t.Saved()
    Check(W.Session.StartScan()); Check(t.ToReading(), "five thousand listings take more than one step")
    Same(W.Scan.phase, "reading")
    Check(W.Scan.Stop(), "stop while reading"); t.Advance(60)
    Same(t.Saved(), s0, "stopped while reading: nothing written"); Same(W.Scan.state, "interrupted")
    -- stop during saving is refused and the commit finishes
    local u = Setup(); u.Open(); Check(u.ToReading())
    local W2 = u.W()
    local guard = 0
    while W2.Scan.phase ~= "saving" and W2.Scan.Busy() and guard < 200 do u.Tick(); guard = guard + 1 end
    Same(W2.Scan.phase, "saving", "the saving step was reached")
    local ok, why = W2.Scan.Stop()
    Check(not ok and why == "saving", "no Stop during the saving step")
    Check(W2.Scan.Busy(), "the scan goes on")
    u.Close()   -- the window closing while the accepted result is being saved: the commit finishes (the listings were read)
    u.Advance(60); Same(W2.Scan.state, "done", "the commit that was under way finishes, even with the window closed")
    Check(u.Market() ~= nil and u.Market().snap.auto == true)
    -- closing the auction house while reading: interrupted, nothing written; closing while saving: the saved result stands
    local v = Setup(); v.Open(); v.Finish(); local kept = v.Saved()
    v.Close(); v.Minutes(61); v.ah.records = {}
    for i = 1, 5000 do v.ah.records[i] = { item = 3000 + i, count = 1, buyout = 100 + i } end
    v.Open(); Check(v.ToReading()); Same(v.W().Scan.phase, "reading")
    v.Close(); v.Advance(60)
    Same(v.W().Scan.state, "interrupted"); Same(v.W().Scan.why, "closed"); Same(v.Saved(), kept, "closed while reading: nothing written")
end

-- a stale scan callback or an old visit cannot start anything
do
    local t = Setup(); t.Open(); t.Finish()
    local A = t.W().Auto
    local before = t.ah.sent
    local snap = A.Snapshot()
    t.Close()
    local a, why = A.Visit(snap.lastVisit)
    Same(a, "skip"); Same(t.ah.sent, before, "the same visit id is handled once; a closed window is not scanned")
    Same(A.Visit(snap.lastVisit - 1), "skip")
end

-- the saved format and an earlier market stay readable (a version-2 database is kept)
do
    local t = Setup(); t.Open(); t.Finish()
    local m1 = t.Market()
    local W = t.W()
    local items1 = 0 for _ in pairs(m1.items) do items1 = items1 + 1 end
    t.Close(); t.Minutes(61); t.Open(); t.Finish()
    local m2 = t.Market()
    Same(W.Prices.DbVersion(), W.Prices.SAVED_VERSION); Same(m2.format, 3)
    Check(m2.snap.seq == m1.snap.seq + 1, "sequence numbers continue")
    Check(m2.at >= m1.at)
end

-- the clock moving backwards cannot make a scan repeat
do
    local t = Setup(); t.Open(); t.Finish()
    t.Close()
    t.c.time = function() return 100 * 86400 - 20000 end    -- the wall clock jumped back hours: the saved scan now lies in the future
    t.Open()
    Same(t.ah.sent, 1, "monotonic freshness: the scan done this session still counts")
end

-- packaging
do
    local function Read(path) local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s end
    Check(Read(ROOT .. "!!!TwichUI.toc"):find("\nWorkshopAuto.lua", 1, true), "the core TOC loads WorkshopAuto.lua")
    Check(Read(REPO .. "TwichUI_Workshop/TwichUI_Workshop.toc"):find("\nAuto.lua", 1, true), "the Workshop TOC loads Auto.lua")
end

print("workshop auto: OK")
