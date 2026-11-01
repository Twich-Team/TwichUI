-- TwichUI: Guild Locations, the messages, sending and receiving (docs/guild-locations.md)
-- Guild members using TwichUI share their own current map position on the guild's hidden addon channel (prefix
-- "TwichUIGuild", distribution GUILD). Nothing is ever written in chat. Only the local player's own position is sent, never
-- anyone else's and never relayed; nothing received is saved or passed on; no history is kept. State.lua decides whether
-- anything is sent or kept (sharing / invisible / off); this file does it.
--
-- The message (version 1, plain text, never run or looked up, under 64 bytes, every number in canonical form):
--   "1:p:<E>:<n>:<map>:<x>:<y>"   a position. E epoch, n number within the epoch (1..2^20), map a map id, x and y whole
--                                 steps 0..10000 of the map (zero is a place). No class or level: the roster supplies them.
--   "1:w:<E>"                     a withdrawal: stop showing me
-- Who sent it is what the game says, never a field of the message, and only a sender the guild roster lists is believed.
-- An epoch E (1.6e9..2^32-1) is one more than any this account sent before, never less than the clock. It orders ONE
-- sender's sessions and withdrawals against each other and means nothing else: freshness is always the receiver's own clock.
--   * A sender takes a new epoch for every sharing session and for every withdrawal. A withdrawal (E) closes its own epoch and
--     every lower one from that sender, seen or not, and never a later session.
--   * A receiver keeps { e, n, closed, at } per sender: p(E,n) is dropped when E < e, or E == e and (closed or n <= the last);
--     w(E) is dropped when E < e, else the record becomes a tombstone with no position (also with no earlier record).
--   * That ordering lives only in the receiver's memory. When a record expires (300 s after the last accepted message) or the
--     receiver reloads, an old delayed message is first contact again and can be accepted: it shows for up to 300 s at most.
--     Nothing here orders messages for ever, and a withdrawal cannot erase what another addon already received.
--
-- Receiving, cheapest check first (Receive): the feature is not off or held; text and sender readable; GUILD and in a guild;
-- not ourselves; the size; the sender is in the roster (guildloc/Roster.lua; unknown asks for one throttled refresh); the
-- sender's rate (burst 5, one more per 4 s); the shape and version; the kind; the ranges and a map the client knows as a zone
-- or smaller; then the epoch rules above. Records, tombstones and buckets are bounded, expire on the receiver's clock, and are
-- swept by one timer. At the cap a new sender is refused: live records and unexpired tombstones are never evicted, and a
-- valid message from a sender already held is still taken.
--
-- Sending (Tick). One timer per purpose (State.lua GL.NewTimer). While sharing and in a guild, in the world:
--   * every `interval` seconds (10, 15, 30 or 60; default 15; +-10% each time; the first 5 to 20 s after a start), read the
--     position (nothing when the game gives none: loading, instances, secret values: never a heartbeat without a position);
--   * send when you moved (20 yards, or the same map and a normalized 0.005 where yards cannot be told; a new map counts)
--     since the last send, or every K-th tick while standing still, K = 60 / interval, so the longest healthy gap is
--     60 x 1.1 = 66 s. Loading, a late timer, a refused or skipped send or a missing position make it longer: no count of
--     tolerated misses is promised. A send that is skipped stays due for the next tick;
--   * a position is handed over only if it would go out at once. Preflight (Preflight) reads ChatThrottleLib's own numbers
--     (bQueueing, MSG_OVERHEAD, UpdateAvail) and skips the tick when the library is already queueing or the message plus its
--     overhead would not fit. That is best-effort congestion avoidance, NOT proof the message cannot be queued: the game can
--     still throttle a send the library believed it had room for, and the library then queues it and has no way to cancel it.
--     Such a send is noticed (its callback had not run when the call returned), counted as "queued", and holds the next
--     position back until it is released; it may still go out later;
--   * if the library, AceComm or any of those fields is missing or not what is expected, no position is sent, never an
--     ordinary queued one (the reason shows in the troubleshooting report). Receiving is unaffected;
--   * at most one position is outstanding; none while the game refuses group messages (SH.Blocked).
-- A position is never created after the state changed: every tick reads the saved state first.
--
-- Leaving sharing (invisible or off) with a session running ends the session and sends a withdrawal (ALERT, a new epoch). Whether
-- the game took the message is known (its callback); whether anyone received it is not. `wp` in the saved record marks a
-- withdrawal still owed: if the game did not accept it (a reload, a lockdown, no guild yet) the next load sends one more with
-- a fresh epoch, even while the feature is off. That path only ever sends a withdrawal: it starts no session, sends no
-- position and records nothing. Attempts are at +0, +15 s and +45 s; the first one the game accepts ends it. After the last,
-- the flag is cleared and the sender gives up: receivers' 300 s expiry is then the only thing that removes the marker.
-- Choosing sharing again clears the flag and makes every pending retry and callback of the old withdrawal do nothing; a
-- withdrawal the library already queued still goes out, and receivers ignore it (its epoch is lower than the new session's).
-- Leaving the guild or joining another ends the session without a withdrawal (the old guild can no longer be reached),
-- forgets everything held, and starts a new session, with a new epoch, if sharing.

local R = TwichUI
local GL = R.GuildLoc
local RS = GL.Roster
local SH = R.Share
local NS = R.NpcStore
local Perf = R.Perf

local AceComm = LibStub("AceComm-3.0")

GL.PREFIX = "TwichUIGuild"
GL.PROTOCOL = 1

-- Every bound in one place (docs/guild-locations.md lists them).
GL.LIMITS = {
    maxText = 64,                         -- bytes of a message taken in
    maxSeq = 1048576,                     -- 2^20: the number within an epoch (a new epoch follows)
    coord = 10000,
    expiry = 300,                         -- seconds, from the receipt of the last accepted message, for positions and tombstones
    records = 400,                        -- live records and tombstones together
    buckets = 400,
    inBurst = 5, inRefill = 0.25,         -- per sender: five in a burst, then one every four seconds
    bucketIdle = 60,
    sweep = 15,
    jitter = 0.1,
    startMin = 5, startMax = 20,          -- seconds before the first send of a session
    moveYards = 20, moveFallback = 0.005,
    heartbeat = 60,                       -- seconds, nominal, standing still
    outstandingMax = 60,                  -- seconds before a queued send that never reported is forgotten
    withdrawAt = { 0, 15, 45 },           -- attempts, seconds from the start of the withdrawal
    withdrawGrace = 15,                   -- after the last attempt, before giving up
}
local L = GL.LIMITS

local function Now() return GetTime() end
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local stats = { ticks = 0, sent = 0, refused = 0, queued = 0, queuedSent = 0, errors = 0, received = 0, withdrawn = 0,
    wSent = 0, wAccepted = 0, wRefused = 0, wGaveUp = 0, wStale = 0, wNoEpoch = 0, sessions = 0, guildChanges = 0,
    outstandingReset = 0, offlineCleared = 0, expired = 0 }
local drops = {}      -- reason -> count; codes only, never names, places or text
local skips = {}      -- reason a tick sent nothing -> count
local lastSkip, transportStatus = nil, "unchecked"
local readable = true      -- whether the library's last UpdateAvail gave a number

local function Drop(code)
    drops[code] = (drops[code] or 0) + 1
    return false, code
end
local function Skip(code)
    skips[code] = (skips[code] or 0) + 1
    lastSkip = code
    return false, code
end

---------------------------------------------------------------------------
-- The message
---------------------------------------------------------------------------
function GL.EncodePosition(e, n, map, x, y)
    return ("1:p:%.0f:%d:%d:%d:%d"):format(e, n, map, x, y)
end
function GL.EncodeWithdraw(e) return ("1:w:%.0f"):format(e) end

-- A canonical decimal numeral: no sign, no leading zero, at most `digits` long, in range. Returns the number or nil.
local function Num(s, digits, low, high)
    if #s > digits or (#s > 1 and s:sub(1, 1) == "0") then return nil end
    local v = tonumber(s)
    if not v or v < low or v > high then return nil end
    return v
end

-- Reads a message: "p", epoch, number, map, x, y  or  "w", epoch  or  nil and a code. Only the shape and ranges are checked
-- here; whether the map is one the client knows is the caller's.
function GL.Parse(text)
    if type(text) ~= "string" then return nil, "malformed" end
    if #text > L.maxText then return nil, "too-long" end
    local v = text:match("^(%d+):")
    if not v or #v > 3 or (#v > 1 and v:sub(1, 1) == "0") then return nil, "malformed" end
    v = tonumber(v)
    if v > GL.PROTOCOL then return nil, "newer-protocol" end
    if v ~= GL.PROTOCOL then return nil, "bad-version" end
    local e, n, map, x, y = text:match("^1:p:(%d+):(%d+):(%d+):(%d+):(%d+)$")
    if e then
        e, n, map = Num(e, 10, GL.EPOCH_MIN, GL.EPOCH_MAX), Num(n, 7, 1, L.maxSeq), Num(map, 6, 1, 999999)
        x, y = Num(x, 5, 0, L.coord), Num(y, 5, 0, L.coord)
        if not (e and n and map and x and y) then return nil, "bad-range" end
        return "p", e, n, map, x, y
    end
    e = text:match("^1:w:(%d+)$")
    if e then
        e = Num(e, 10, GL.EPOCH_MIN, GL.EPOCH_MAX)
        if not e then return nil, "bad-range" end
        return "w", e
    end
    local kind = text:match("^1:(%a):")
    if kind and kind ~= "p" and kind ~= "w" then return nil, "bad-kind" end
    return nil, "malformed"
end

---------------------------------------------------------------------------
-- What is held (memory only; nothing here is saved)
---------------------------------------------------------------------------
local records, nLive, nTomb = {}, 0, 0   -- [lower full name] = { e, n, closed, at, name, born, map, x, y }
local buckets, nBuckets = {}, 0          -- [lower full name] = { tokens, at }
local born = 0

local function Forget(key)
    local rec = records[key]
    if not rec then return end
    if rec.closed then nTomb = nTomb - 1 else nLive = nLive - 1 end
    records[key] = nil
end

local function Store(key, rec)
    local old = records[key]
    if old then
        if old.closed then nTomb = nTomb - 1 else nLive = nLive - 1 end
    end
    records[key] = rec
    if rec.closed then nTomb = nTomb + 1 else nLive = nLive + 1 end
end

local function SweepRecords(now)
    local n = 0
    for key, rec in pairs(records) do
        if now - rec.at >= L.expiry then Forget(key); n = n + 1 end
    end
    stats.expired = stats.expired + n
    return n
end

local function SweepBuckets(now)
    local n = 0
    for key, b in pairs(buckets) do
        if now - b.at >= L.bucketIdle then buckets[key] = nil; nBuckets = nBuckets - 1; n = n + 1 end
    end
    return n
end

local sweepT
local function ArmSweep()
    if sweepT and not sweepT.Armed() and nLive + nTomb + nBuckets > 0 then sweepT.Set(L.sweep) end
end

local function WipeHeld()
    records, buckets = {}, {}
    nLive, nTomb, nBuckets = 0, 0, 0
    if sweepT then sweepT.Cancel() end
end

-- A live record whose roster entry shows the member offline in a pass that came after the record's last message: they are not
-- sending. Only a roster that lists them counts; absence proves nothing. Tombstones stay (they only guard against old traffic).
local function ClearOffline()
    local stamp = RS.Stamp()
    if not stamp then return end
    for key, rec in pairs(records) do
        if not rec.closed and rec.at < stamp then
            local entry = RS.Entry(key)
            if entry and entry.online == false then Forget(key); stats.offlineCleared = stats.offlineCleared + 1 end
        end
    end
end
RS.OnRefresh(function() if GL.State() ~= "off" then ClearOffline() end end)

sweepT = GL.NewTimer(function()
    local now = Now()
    SweepRecords(now)
    SweepBuckets(now)
    ArmSweep()
end)

-- Returns true or false and a code.
local function TakeToken(key, now)
    local b = buckets[key]
    if not b then
        if nBuckets >= L.buckets then
            SweepBuckets(now)
            if nBuckets >= L.buckets then return Drop("bucket-cap") end
        end
        b = { tokens = L.inBurst, at = now }
        buckets[key] = b
        nBuckets = nBuckets + 1
        ArmSweep()
    else
        b.tokens = math.min(L.inBurst, b.tokens + (now - b.at) * L.inRefill)
        b.at = now
    end
    if b.tokens < 1 then return Drop("rate") end
    b.tokens = b.tokens - 1
    return true
end

-- The epoch rules. Returns true or false and a code.
local function Apply(key, name, kind, e, n, map, x, y)
    local now = Now()
    local rec = records[key]
    if rec and now - rec.at >= L.expiry then Forget(key); rec = nil; stats.expired = stats.expired + 1 end
    if kind == "p" then
        if rec then
            if e < rec.e then return Drop("old-epoch") end
            if e == rec.e then
                if rec.closed then return Drop("closed-epoch") end
                if n <= rec.n then return Drop("old-number") end
            end
        end
    elseif rec and e < rec.e then
        return Drop("old-epoch")
    end
    if not rec and nLive + nTomb >= L.records then
        SweepRecords(now)
        if nLive + nTomb >= L.records then return Drop("full") end
    end
    local new = { e = e, n = kind == "p" and n or 0, closed = kind == "w", at = now, name = name }
    if rec then new.born = rec.born else born = born + 1; new.born = born end
    if kind == "p" then new.map, new.x, new.y = map, x, y end
    Store(key, new)
    ArmSweep()
    if kind == "p" then stats.received = stats.received + 1 else stats.withdrawn = stats.withdrawn + 1 end
    return true
end

-- A copy of what is held for a name: { epoch, number, closed, age, map, x, y }, or nil. For tests and the map.
function GL.Peek(name)
    local full = SH.FullName(name)
    local rec = full and records[full:lower()]
    if not rec or Now() - rec.at >= L.expiry then return nil end
    return { epoch = rec.e, number = rec.n, closed = rec.closed, age = Now() - rec.at, map = rec.map, x = rec.x, y = rec.y }
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Receive(text, dist, sender)
    if Secret(text) or Secret(sender) or Secret(dist) or type(text) ~= "string" or type(sender) ~= "string" then return Drop("unreadable") end
    if dist ~= "GUILD" or not IsInGuild() then return Drop("channel") end
    if SH.SameName(sender, SH.SelfName()) then return end   -- our own, echoed back
    if #text > L.maxText then return Drop("too-long") end
    local entry, key, full = RS.Lookup(sender)
    if not entry then
        RS.Request()
        return Drop("not-in-roster")
    end
    if not TakeToken(key, Now()) then return end
    local kind, e, n, map, x, y = GL.Parse(text)
    if not kind then return Drop(e) end
    if kind == "p" and not (NS and NS.ValidMap(map)) then return Drop("unknown-map") end
    return Apply(key, full, kind, e, n, map, x, y)
end

local function OnMessage(_, text, dist, sender)
    if GL.State() == "off" then return end   -- first thing: off keeps and shows nothing
    Perf.Call("guildloc.receive", Receive, text, dist, sender)
end
AceComm:RegisterComm(GL.PREFIX, OnMessage)
GL.OnMessage = OnMessage   -- for tests

---------------------------------------------------------------------------
-- The transport, as far as it can be told
---------------------------------------------------------------------------
-- ChatThrottleLib v32 (the library AceComm sends through) sends at once only when it is not queueing and the message plus
-- MSG_OVERHEAD is less than UpdateAvail(); otherwise it queues, and nothing in it can cancel a queued message. Returns the
-- library, or nil and a short reason.
local function Transport()
    if type(AceComm.SendCommMessage) ~= "function" then transportStatus = "no-acecomm" return nil, transportStatus end
    local CTL = _G.ChatThrottleLib
    if type(CTL) ~= "table" or type(CTL.SendAddonMessage) ~= "function" or type(CTL.UpdateAvail) ~= "function"
        or type(CTL.MSG_OVERHEAD) ~= "number" or CTL.MSG_OVERHEAD ~= CTL.MSG_OVERHEAD or CTL.MSG_OVERHEAD < 0
        or (CTL.bQueueing ~= nil and type(CTL.bQueueing) ~= "boolean") then
        transportStatus = "ctl-incompatible"
        return nil, transportStatus
    end
    transportStatus = readable and "ok" or "ctl-unreadable"
    return CTL
end

-- AceComm puts one escape byte in front of a text that begins with a control character. Ours begins with a digit.
local function FrameBytes(text) return text:find("^[\001-\009]") and 1 or 0 end

-- Whether `text` would go out at once. Best effort only (see the top of the file).
local function Preflight(CTL, text)
    if CTL.bQueueing == true then return false, "queueing" end
    local size = #text + FrameBytes(text) + CTL.MSG_OVERHEAD
    local ok, avail = pcall(CTL.UpdateAvail, CTL)
    readable = ok and type(avail) == "number" and avail == avail
    if not readable then
        transportStatus = "ctl-unreadable"
        return false, "transport"
    end
    transportStatus = "ok"
    if size >= avail then return false, "no-room" end
    return true
end
GL.Preflight = Preflight   -- for tests

---------------------------------------------------------------------------
-- Sessions and ticks
---------------------------------------------------------------------------
local session            -- { gen, epoch, seq, idle, due, last }
local sgen = 0           -- bumps whenever a session starts or ends; a callback of an old one does nothing
local outstanding, outstandingAt = 0, nil
local tickT
local guildKey
local noSend            -- why a session could not start, for the report
local eventsOn = {}

local function InWorld() return R.Life ~= nil and R.Life.InWorld() end

local function Readable(v)
    if type(v) ~= "number" or Secret(v) or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- The player's own place as { map, x, y } in whole steps, or nil. Never changes the map being looked at.
local function ReadPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    map = ok and Readable(map)
    if not map or map % 1 ~= 0 or not NS or not NS.ValidMap(map) then return nil end
    local ok2, p = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not (ok2 and p) then return nil end
    local ok3, x, y = pcall(p.GetXY, p)
    x, y = ok3 and Readable(x), ok3 and Readable(y)
    if not (x and y) then return nil end
    local qx, qy = R.Pins.Quantize(x), R.Pins.Quantize(y)
    if not (qx and qy) then return nil end
    return { map = map, x = qx, y = qy }
end

local function Moved(sess, pos)
    local last = sess.last
    if not last or last.map ~= pos.map then return true end
    local SR = R.NpcSearch
    if SR and SR.Distance and last.spot then
        local ok, d = pcall(SR.Distance, last.spot, pos.map, pos.x / L.coord, pos.y / L.coord)
        if ok and type(d) == "number" and d == d then return d >= L.moveYards end
    end
    return math.max(math.abs(pos.x - last.x), math.abs(pos.y - last.y)) / L.coord >= L.moveFallback
end

local function Captured(pos)
    local SR = R.NpcSearch
    local spot
    if SR and SR.Where then
        local ok, s = pcall(SR.Where)
        if ok and type(s) == "table" then spot = s end
    end
    return { map = pos.map, x = pos.x, y = pos.y, spot = spot }
end

-- AceComm calls back (arg, bytes, total bytes, accepted): the last is ChatThrottleLib's didSend, true only when the game took
-- the message. A message is one part, so it is called once.
local function PositionDone(arg, _, _, accepted)
    arg.fired = true
    arg.sent = accepted == true
    if arg.queued then   -- a send the library had queued has now been released
        outstanding = math.max(0, outstanding - 1)
        if arg.sent then stats.queuedSent = stats.queuedSent + 1 end
    end
end

local function SendPosition(sess, pos)
    if SH.Blocked() then return Skip("blocked") end
    if outstanding > 0 then
        if outstandingAt and Now() - outstandingAt > L.outstandingMax then
            outstanding = 0
            stats.outstandingReset = stats.outstandingReset + 1
        else
            return Skip("outstanding")
        end
    end
    local CTL, why = Transport()
    if not CTL then return Skip(why) end
    if sess.seq >= L.maxSeq then   -- a very long session: a new epoch, numbers from the start
        local e = GL.NextEpoch()
        if not e then
            noSend = "epoch"
            return Skip("epoch")
        end
        sess.epoch, sess.seq = e, 0
    end
    local seq = sess.seq + 1
    local text = GL.EncodePosition(sess.epoch, seq, pos.map, pos.x, pos.y)
    local fits, reason = Preflight(CTL, text)
    if not fits then return Skip(reason) end
    sess.seq = seq
    local arg = { gen = sess.gen }
    local ok, err = pcall(AceComm.SendCommMessage, AceComm, GL.PREFIX, text, "GUILD", nil, "NORMAL", PositionDone, arg)
    if not ok then
        stats.errors = stats.errors + 1
        if R.Fault then R.Fault("guild locations", err) end
        return
    end
    if arg.fired then
        if not arg.sent then stats.refused = stats.refused + 1 return Skip("refused") end
        stats.sent = stats.sent + 1
    else
        -- The library queued it after all (the game throttled the send it expected to go through): it may still go out later.
        arg.queued = true
        outstanding, outstandingAt = outstanding + 1, Now()
        stats.queued = stats.queued + 1
    end
    sess.idle, sess.due = 0, false
    sess.last = Captured(pos)
end

local function TickWork(sess, interval)
    stats.ticks = stats.ticks + 1
    sess.idle = sess.idle + 1
    if sess.idle >= math.max(1, math.floor(L.heartbeat / interval + 0.5)) then sess.due = true end
    if not InWorld() then return Skip("loading") end
    local pos = ReadPosition()
    if not pos then return Skip("no-position") end
    if Moved(sess, pos) then sess.due = true end
    if not sess.due then return end
    SendPosition(sess, pos)
end

local Evaluate

local function Tick()
    local sess = session
    if not sess then return end
    if GL.State() ~= "sharing" or not IsInGuild() then return Evaluate() end   -- the state moved on: nothing is created
    local interval = GL.Interval()
    tickT.Set(interval * (1 + (math.random() * 2 - 1) * L.jitter))   -- first, so nothing below can end the chain
    Perf.Call("guildloc.tick", TickWork, sess, interval)
end
tickT = GL.NewTimer(Tick)

local function EndSession()
    if not session then return end
    session = nil
    sgen = sgen + 1
    tickT.Cancel()
end

local function StartSession()
    local e, why = GL.NextEpoch()
    if not e then
        noSend = why
        return false
    end
    noSend = nil
    sgen = sgen + 1
    stats.sessions = stats.sessions + 1
    session = { gen = sgen, epoch = e, seq = 0, idle = 0, due = true }
    tickT.Set(L.startMin + math.random() * (L.startMax - L.startMin))
    return true
end

---------------------------------------------------------------------------
-- Withdrawing
---------------------------------------------------------------------------
local wgen = 0            -- bumps whenever a withdrawal starts or is called off
local wd                  -- { gen, epoch, tries, final }
local wT

local function WithdrawDone(arg, _, _, accepted)
    arg.fired = true
    if arg.gen ~= wgen then stats.wStale = stats.wStale + 1 return end   -- an old withdrawal, or one called off
    if accepted == true then
        stats.wAccepted = stats.wAccepted + 1
        GL.SetPending(false)
        if wd then wd.accepted = true end
        wT.Cancel()
    elseif arg.sync then
        stats.wRefused = stats.wRefused + 1
    end
end

local function WithdrawAttempt()
    local d = wd
    if not d or d.gen ~= wgen then return end
    if d.final then   -- the grace after the last attempt is over
        if GL.Pending() then GL.SetPending(false); stats.wGaveUp = stats.wGaveUp + 1 end
        wd = nil
        return
    end
    if not GL.Pending() or GL.State() == "sharing" then wd = nil return end
    d.tries = d.tries + 1
    if IsInGuild() and not SH.Blocked() and type(AceComm.SendCommMessage) == "function" then
        local arg = { gen = d.gen, sync = true }
        local text = GL.EncodeWithdraw(d.epoch)
        local ok, err = pcall(AceComm.SendCommMessage, AceComm, GL.PREFIX, text, "GUILD", nil, "ALERT", WithdrawDone, arg)
        arg.sync = false
        if ok then
            stats.wSent = stats.wSent + 1
        else
            stats.errors = stats.errors + 1
            if R.Fault then R.Fault("guild locations", err) end
        end
    end
    local at = L.withdrawAt
    if d.tries < #at then
        wT.Set(at[d.tries + 1] - at[d.tries])
    else
        d.final = true
        wT.Set(L.withdrawGrace)
    end
end
wT = GL.NewTimer(WithdrawAttempt)

local function CancelWithdrawal()
    wgen = wgen + 1
    wd = nil
    wT.Cancel()
end

-- Starts owing and sending a withdrawal: the flag is saved first, then a fresh epoch is taken, then the first attempt is made.
local function StartWithdrawal()
    wgen = wgen + 1
    wT.Cancel()
    GL.SetPending(true)
    local e = GL.NextEpoch()
    if not e then
        wd = nil
        stats.wNoEpoch = stats.wNoEpoch + 1
        return
    end
    wd = { gen = wgen, epoch = e, tries = 0 }
    WithdrawAttempt()
end

-- After a load: a withdrawal still owed is sent whatever the state, and nothing else is started by it.
local function ResumePending()
    if wd or not GL.Pending() then return end
    if GL.State() == "sharing" then GL.SetPending(false) return end   -- a new session's epoch supersedes it
    StartWithdrawal()
end

---------------------------------------------------------------------------
-- Keeping the pieces in step with the state
---------------------------------------------------------------------------
local function GuildNow()
    if not IsInGuild() then return nil end
    local name = GetGuildInfo and GetGuildInfo("player")
    if type(name) == "string" and name ~= "" and not Secret(name) then return name end
    return guildKey or "?"
end

-- True when the guild is not the one held records and the session belong to (or there is none now).
local function GuildChanged()
    local now = GuildNow()
    if now == guildKey then return false end
    local before = guildKey
    guildKey = now
    if before == nil and now ~= nil then return false end            -- the first look
    if before == "?" and now ~= nil then return false end            -- the name arrived
    return true
end

local function OnWorld()
    Evaluate()
    ResumePending()
end

local function OnGuildUpdate(unit)
    if unit ~= nil and unit ~= "player" then return end
    Evaluate()
end

local function SyncEvents(state)
    local all = state ~= "off"
    local world = all or GL.Pending()
    if world then R:On("PLAYER_ENTERING_WORLD", OnWorld) else R:Off("PLAYER_ENTERING_WORLD", OnWorld) end
    if all then R:On("PLAYER_GUILD_UPDATE", OnGuildUpdate) else R:Off("PLAYER_GUILD_UPDATE", OnGuildUpdate) end
    eventsOn.world, eventsOn.guild = world, all
end

-- Makes everything agree with the saved state, the guild and the world. Safe to call at any time, as often as needed.
function Evaluate()
    local state = GL.State()
    SyncEvents(state)
    if state == "off" then
        EndSession()
        WipeHeld()
        RS.Stop()
        guildKey = nil
        return
    end
    RS.Start()
    if GuildChanged() then
        stats.guildChanges = stats.guildChanges + 1
        EndSession()
        CancelWithdrawal()
        GL.SetPending(false)   -- the old guild cannot be reached; its receivers' expiry removes the marker
        WipeHeld()
        RS.Reset()
    end
    if state == "sharing" and IsInGuild() and InWorld() then
        if not session then StartSession() end
    else
        EndSession()
    end
end

GL.OnChange(function(kind, new, old)
    if kind == "interval" then
        if session then tickT.Set(new) end
        return
    end
    if new == "sharing" then
        CancelWithdrawal()
        GL.SetPending(false)
    elseif old == "sharing" and session then
        EndSession()
        StartWithdrawal()
    end
    Evaluate()
end)

R:OnInit(function() Evaluate() end)

---------------------------------------------------------------------------
-- What the troubleshooting report and the tests may read: counts and codes only
---------------------------------------------------------------------------
function GL.CanSend()
    if GL.State() ~= "sharing" then return false, "not-sharing" end
    if not session then return false, noSend or "no-session" end
    local CTL, why = Transport()
    if not CTL then return false, why end
    if not readable then return false, "ctl-unreadable" end
    return true
end

local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

function GL.Snapshot()
    local state, why = GL.State()
    local timers = tickT.Engines() + wT.Engines() + sweepT.Engines() + (RS.Snapshot().timers or 0)
    local armed = (tickT.Armed() and 1 or 0) + (wT.Armed() and 1 or 0) + (sweepT.Armed() and 1 or 0)
    local events = (eventsOn.world and 1 or 0) + (eventsOn.guild and 1 or 0) + (RS.Started() and 1 or 0)
    return {
        state = state, reason = why, interval = GL.Interval(), session = session ~= nil, noSend = noSend,
        transport = transportStatus, lastSkip = lastSkip, pending = GL.Pending(), withdrawing = wd ~= nil,
        records = nLive, tombstones = nTomb, buckets = nBuckets, outstanding = outstanding,
        roster = RS.Count(), timers = timers, armed = armed, events = events,
        stats = Copy(stats), drops = Copy(drops), skips = Copy(skips),
    }
end
