-- Guild Locations: explicit local inspection and a bounded, automatic peer check.
-- All identities/results are memory-only and expire. Routine exported diagnostics contain
-- counts/codes only. Controls use the real location prefix, not the configuration transport.
-- Off never participates. Invisible can answer status but never sends a position.
local R = TwichUI
local GL, SH = R.GuildLoc, R.Share
local RS, Perf = GL.Roster, R.Perf
local D = {}
GL.Diagnostics = D

D.TIMEOUT, D.TRACE_SECONDS = 90, 120
local POLLS = { 0, 20, 50, 80 }
local descriptions = {
    ready = "Ready to send when the next update is due; delivery is not yet confirmed.",
    off = "Guild Locations is Off. No diagnostic messages are sent or answered.",
    ["not-sharing"] = "Your position is not being shared.",
    held = "Saved data belongs to a newer version; Guild Locations is inactive.",
    ["not-ready"] = "Saved data is not ready.",
    ["no-guild"] = "There is no guild to send to.",
    loading = "The player has not entered the world yet.",
    ["no-session"] = "No sending session is running.",
    ["bad-record"] = "The saved sharing record could not be read.",
    ["bad-state"] = "The saved sharing choice could not be read; Invisible is in force.",
    ["bad-epoch"] = "Saved message ordering is unusable. Toggling Sharing cannot safely repair it; no position is sent.",
    ["epoch-range"] = "The clock or saved message ordering is outside the supported range.",
    epoch = "A fresh message-ordering epoch could not be allocated.",
    blocked = "The game is currently blocking addon messages.",
    ["no-acecomm"] = "The communication library is unavailable.",
    ["ctl-incompatible"] = "The active throttle library is incompatible.",
    ["ctl-unreadable"] = "The throttle library's available bandwidth could not be read.",
    transport = "Transport readiness could not be read.",
    queueing = "The shared throttle library is busy sending queued messages.",
    ["no-room"] = "The throttle library has no room for this message yet.",
    outstanding = "A previously queued position is still outstanding.",
    ["no-position"] = "No usable position is available. Loading, map metadata or hidden coordinates may be responsible.",
    refused = "The game refused the message.",
    ["send-error"] = "The communication library failed to hand over the message.",
    ["handed-over"] = "The message was handed to the communication library; receipt is not confirmed.",
    accepted = "A normal position update was accepted.",
    withdrawn = "The member withdrew their position.",
    ["not-in-roster"] = "The sender is missing from this client's guild roster cache or their name does not match.",
    ["unknown-map"] = "The position's map could not be validated on this client.",
    unreadable = "The message or sender could not be read.",
    channel = "The message did not arrive on a usable guild channel.",
    ["too-long"] = "The message exceeded the size limit.",
    malformed = "The message did not match the protocol.",
    ["newer-protocol"] = "The sender uses a newer location protocol.",
    ["bad-version"] = "The location protocol version is unsupported.",
    ["bad-kind"] = "The message kind is unsupported.",
    ["bad-range"] = "The position contains an out-of-range value.",
    ["old-epoch"] = "An older session's update was rejected.",
    ["closed-epoch"] = "An update from an already withdrawn session was rejected.",
    ["old-number"] = "A duplicate or out-of-order update was rejected.",
    rate = "The sender exceeded the receive rate limit.",
    ["bucket-cap"] = "The receive rate-tracking capacity is full.",
    full = "The live position and withdrawal capacity is full.",
    self = "Your own position is intentionally not drawn by Guild Locations.",
    group = "This member is in your group; Blizzard's group markers are used instead.",
    ["different-map"] = "The position is outside the maps relevant to the current view.",
    projection = "The position could not be converted to the current map.",
    bounds = "The converted position is outside the visible map bounds.",
    cap = "The position is beyond the 150-marker drawing limit.",
    drawn = "The member has a Guild Locations badge on the current map.",
    pending = "The map has not laid out this badge yet.",
    ["map-unavailable"] = "The world map or marker provider is unavailable.",
    ["map-closed"] = "The world map is closed; no badges are drawn.",
    shown = "A SYNTHETIC badge is shown at the map center for 10 seconds.",
    unseen = "No message from this member has been observed during this inspection.",
    busy = "A communication check is already running.",
    cooldown = "Wait 10 seconds before starting another communication check.",
    ["bad-name"] = "Enter the member's full character name, including their last name on Forever.",
    offline = "The local guild roster currently lists this member as offline.",
}
function D.Describe(code) return descriptions[code] or "The result is unavailable." end
local function Codes(text)
    local set = {}
    for code in text:gmatch("%S+") do set[code] = true end
    return set
end
local sendCodes = Codes("ready not-sharing held not-ready no-guild loading no-session bad-record bad-epoch epoch-range epoch blocked no-acecomm ctl-incompatible ctl-unreadable transport no-room queueing outstanding no-position")
local receiveCodes = Codes("accepted withdrawn unseen not-in-roster unknown-map unreadable channel too-long malformed newer-protocol bad-version bad-kind bad-range old-epoch closed-epoch old-number rate bucket-cap full")
local renderCodes = Codes("off map-unavailable map-closed no-position self group different-map projection bounds cap drawn pending")

local listeners = {}
function D.OnChange(fn)
    for _, old in ipairs(listeners) do if old == fn then return end end
    listeners[#listeners + 1] = fn
end
function D.Changed()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("guild locations", err) end
    end
end

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Name(value)
    if Secret(value) or type(value) ~= "string" or #value > 96 or value:find("[%c:|]") then return nil end
    local full = SH.FullName(value)
    if not full or #full > 96 then return nil end
    if SH.Realmless() and not full:find(" ", 1, true) then return nil end
    return full
end
local function Age(at) return math.max(0, math.floor(GetTime() - at)) end
local watch, test, responder
local lastStart, lastReply
local serial = 0
local stats = { requests = 0, replies = 0, timeouts = 0, rejected = 0 }
local pollT, expireT, responseT
local guildEvent = false
local OnGuild
local function SyncGuildEvent()
    local want = watch ~= nil or test ~= nil or responder ~= nil
    if want == guildEvent then return end
    guildEvent = want
    if want then R:On("PLAYER_GUILD_UPDATE", OnGuild) else R:Off("PLAYER_GUILD_UPDATE", OnGuild) end
end

function D.IsRunning() return test ~= nil and test.running == true and GetTime() - test.at < D.TIMEOUT end
function D.Stop()
    watch, test = nil, nil
    pollT.Cancel()
    expireT.Cancel()
    SyncGuildEvent()
    D.Changed()
end

local function Select(name)
    local full = Name(name)
    if not full then return false, "bad-name" end
    watch = { name = full, key = full:lower() }
    expireT.Set(D.TRACE_SECONDS)
    SyncGuildEvent()
    return true
end
function D.Inspect(name)
    if not D.IsRunning() then Select(name) end
    return D.Report(name)
end

-- Only an explicit local inspection or one current automatic peer check retains a decision.
function D.Observe(sender, ok, code)
    if not code then return end
    local name = Name(sender)
    if not name then return end
    local key = name:lower()
    if watch and watch.key == key then
        watch.receive = { code = code, at = GetTime() }
        D.Changed()
    end
    if responder and SH.SameName(responder.name, name) then
        responder.receive = { code = code, at = GetTime() }
    end
end

local function Inbox(name, trace)
    local rec = GL.Peek(name)
    local code = trace and trace.receive and trace.receive.code
    if not code then code = rec and (rec.closed and "withdrawn" or "accepted") or "unseen" end
    return rec, code
end

local function Render(name)
    if GL.State() == "off" then return "off" end
    return GL.Map and GL.Map.Explain and GL.Map.Explain(name:lower()) or "map-unavailable"
end

local function Poll()
    local p = test
    if not p or not p.running then return end
    if GL.State() == "off" or not IsInGuild() then D.Stop() return end
    local elapsed = GetTime() - p.at
    if elapsed >= D.TIMEOUT or p.poll >= #POLLS then
        p.running = false
        if not p.remote then stats.timeouts = stats.timeouts + 1 end
        D.Changed()
        return
    end
    p.poll = p.poll + 1
    -- A late timer sends at most one current probe; it never replays missed polls.
    while p.poll < #POLLS and POLLS[p.poll + 1] <= elapsed do p.poll = p.poll + 1 end
    local poll = p.poll
    p.accepted = nil
    local ok, code = GL.SendDiagnostic("1:q:" .. p.id .. ":" .. p.name, function(accepted)
        if test ~= p or not p.running or p.poll ~= poll or GetTime() - p.at >= D.TIMEOUT then return end
        p.accepted = accepted
        D.Changed()
    end)
    p.send = code
    if ok then stats.requests = stats.requests + 1 end
    local nextAt = POLLS[p.poll + 1] or D.TIMEOUT
    pollT.Set(math.max(0, nextAt - (GetTime() - p.at)))
    D.Changed()
end
pollT = GL.NewTimer(function() Perf.Call("guildloc.diagnostic", Poll) end)
expireT = GL.NewTimer(D.Stop)
responseT = GL.NewTimer(function() responder = nil; SyncGuildEvent() end)

function D.Start(name)
    if D.IsRunning() then return false, "busy" end
    if GL.State() == "off" then return false, "off" end
    if not IsInGuild() then return false, "no-guild" end
    if SH.Blocked() then return false, "blocked" end
    local full = Name(name)
    if not full then return false, "bad-name" end
    if SH.SameName(full, SH.SelfName()) then return false, "self" end
    local entry = RS.Lookup(full)
    if not entry then RS.Request() return false, "not-in-roster" end
    -- Online is cached and can be stale just after login. Membership is the
    -- trust gate; a listed-offline peer may still answer the explicit check.
    if lastStart and GetTime() - lastStart < 10 then return false, "cooldown" end
    D.Stop()
    Select(full)
    lastStart = GetTime()
    serial = serial + 1
    -- Correlation only, not an authentication token. The game-provided sender is checked too.
    local id = ("%d%04d%d"):format(math.floor(GetTime()), math.random(0, 9999), serial)
    if #id > 24 then return false, "malformed" end
    test = { id = id, name = full, at = GetTime(), poll = 0, running = true }
    RS.Request()
    Poll()
    return true
end

local function Whole(s, low, high)
    if not s or #s > 10 or (#s > 1 and s:sub(1, 1) == "0") then return nil end
    local n = tonumber(s)
    if n and n % 1 == 0 and n >= low and n <= high then return n end
end

local function Handle(text, dist, sender)
    if GL.State() == "off" then return true end
    if #text > 220 or Secret(dist) or dist ~= "GUILD" or not IsInGuild() or SH.Blocked() then
        stats.rejected = stats.rejected + 1
        return true
    end
    local full = Name(sender)
    if not full or SH.SameName(full, SH.SelfName()) then return true end
    local entry = RS.Lookup(full)
    if not entry then RS.Request(); stats.rejected = stats.rejected + 1 return true end
    local id, target = text:match("^1:q:(%d+):(.+)$")
    if id then
        if #id > 24 or not Name(target) or not SH.SameName(target, SH.SelfName()) then return true end
        if lastReply and GetTime() - lastReply < 10 then return true end
        if not responder or responder.id ~= id or not SH.SameName(responder.name, full) then
            responder = { name = full, id = id }
        end
        responseT.Set(95)
        SyncGuildEvent()
        lastReply = GetTime()
        local rec, receive = Inbox(full, responder)
        local _, send = GL.SendStatus()
        local e, n, age = 0, 0, 0
        if rec and not rec.closed then e, n, age = rec.epoch, rec.number, math.floor(rec.age) end
        local reply = ("1:r:%s:%s:%s:%s:%s:%.0f:%d:%d"):format(id, GL.State(), send, receive, Render(full), e, n, age)
        local ok = GL.SendDiagnostic(reply)
        if ok then stats.replies = stats.replies + 1 end
        return true
    end
    local state, send, receive, render, e, n, age
    id, state, send, receive, render, e, n, age = text:match("^1:r:(%d+):(%a+):([%a%-]+):([%a%-]+):([%a%-]+):(%d+):(%d+):(%d+)$")
    local p = test
    if not id or #id > 24 or not p or not D.IsRunning() or p.id ~= id or not SH.SameName(p.name, full) then return true end
    if p.remote and GetTime() - p.remote.at < 4 then return true end
    e, n, age = Whole(e, 0, GL.EPOCH_MAX), Whole(n, 0, GL.LIMITS.maxSeq), Whole(age, 0, GL.LIMITS.expiry)
    if (state ~= "sharing" and state ~= "invisible") or not sendCodes[send] or not receiveCodes[receive]
        or not renderCodes[render] or not e or not n or not age
        or (e ~= 0 and (e < GL.EPOCH_MIN or n == 0)) or (e == 0 and n ~= 0) then
        stats.rejected = stats.rejected + 1
        return true
    end
    p.remote = { state = state, send = send, receive = receive, render = render, epoch = e, number = n, age = age, at = GetTime() }
    D.Changed()
    return true
end
function D.Handle(text, dist, sender)
    -- Keep ordinary position traffic out of the diagnostic scope and rate budget.
    if Secret(text) or type(text) ~= "string" or not text:find("^1:[qr]:") then return false end
    return Perf.Call("guildloc.diagnostic", Handle, text, dist, sender)
end

local function Prefix()
    local ci = C_ChatInfo
    if ci and ci.IsAddonMessagePrefixRegistered then
        local ok, registered = pcall(ci.IsAddonMessagePrefixRegistered, GL.PREFIX)
        if ok and not Secret(registered) then return registered and "registered" or "NOT registered" end
    end
    return "registration cannot be queried on this client"
end

function D.Report(name)
    local s = GL.Snapshot()
    local _, send = GL.SendStatus()
    local lines = { "Guild Locations diagnostics (local, temporary)", "Your choice: " .. s.state,
        "Your sending: " .. D.Describe(send), "Location prefix: " .. Prefix() }
    if s.reason then lines[#lines + 1] = "Saved choice: " .. D.Describe(s.reason) end
    local _, minor = LibStub:GetLibrary("AceComm-3.0", true)
    local ctl = _G.ChatThrottleLib
    lines[#lines + 1] = ("Libraries: AceComm %s; ChatThrottleLib %s"):format(tostring(minor or "unknown"), tostring(ctl and ctl.version or "unknown"))
    lines[#lines + 1] = "Roster entries: " .. s.roster
    lines[#lines + 1] = "Last position accepted by your game: " .. (s.sentAge and (math.floor(s.sentAge) .. " s ago") or "none this sending session")
    lines[#lines + 1] = "Last skipped tick: " .. (s.lastSkip and D.Describe(s.lastSkip) or "none")
    local m = GL.Map and GL.Map.Snapshot and GL.Map.Snapshot() or {}
    lines[#lines + 1] = ("Map: %s; provider %s; badges %d"):format(m.open and "open" or "closed", m.installed and "installed" or "unavailable", m.drawn or 0)
    local full = Name(name)
    if full then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Member: " .. full
        local entry = RS.Lookup(full)
        lines[#lines + 1] = "Roster match: " .. (entry and (entry.online and "yes, online" or "yes, listed offline") or "missing; use the full name and refresh the guild roster")
        local trace = watch and watch.key == full:lower() and watch or nil
        local rec, receive = Inbox(full, trace)
        lines[#lines + 1] = "Local receive result: " .. D.Describe(receive)
        if trace and trace.receive then lines[#lines + 1] = "Last observed message: " .. Age(trace.receive.at) .. " s ago" end
        lines[#lines + 1] = "Held position: " .. (rec and not rec.closed and (math.floor(rec.age) .. " s old (expires after 300 s)") or "none")
        lines[#lines + 1] = "Local badge: " .. D.Describe(Render(full))
    else
        lines[#lines + 1] = "Enter a full guildmate name to inspect their receive and map status."
    end
    local p = test
    if p then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Communication check: " .. (D.IsRunning() and ("running (" .. Age(p.at) .. "/90 s)") or "finished")
        lines[#lines + 1] = "Test member: " .. p.name
        if p.remote then
            local peer = p.remote
            lines[#lines + 1] = "Round trip: confirmed on the Guild Locations prefix."
            lines[#lines + 1] = "Peer's reply: " .. Age(peer.at) .. " s ago (a snapshot of their status then)"
            lines[#lines + 1] = "Peer's choice: " .. peer.state .. "; " .. D.Describe(peer.send)
            lines[#lines + 1] = "Peer receiving you: " .. D.Describe(peer.receive)
            local sent = GL.LastSent()
            if peer.epoch > 0 then
                local matches = sent and sent.epoch == peer.epoch and sent.number == peer.number
                lines[#lines + 1] = "Peer's held location: " .. (matches and "matches your last game-accepted update" or "an earlier normal update")
                    .. " (" .. (peer.age + Age(peer.at)) .. " s since their receipt)"
            else
                lines[#lines + 1] = "Peer holds no live location for you."
            end
            lines[#lines + 1] = "Your badge on their map: " .. D.Describe(peer.render)
        else
            lines[#lines + 1] = "Round trip: inconclusive; no compatible peer reply yet."
            lines[#lines + 1] = "An old addon, Off, offline, roster mismatch or blocked delivery can all cause silence."
        end
        lines[#lines + 1] = "Last probe: " .. D.Describe(p.send)
        lines[#lines + 1] = "Last probe accepted by your game: " .. (p.accepted == true and "yes" or p.accepted == false and "no" or "not reported")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Inspection expires after 120 s. Tests never change either player's sharing choice."
    lines[#lines + 1] = "Matching positions do not establish a shared phase or layer."
    return table.concat(lines, "\n")
end

function D.SelfTest()
    local lines = { "SYNTHETIC local self-test. No network sends, saved-data changes or real guild records." }
    local inbox, now = {}, 0
    local e = GL.EPOCH_MIN + 1
    local function Push(text)
        local kind, epoch, n, map, x, y = GL.Parse(text)
        if not kind then return false, epoch end
        local rec, why = GL.ReduceRecord(inbox.member, kind, epoch, n, map, x, y, "SYNTHETIC", now)
        if not rec then return false, why end
        inbox.member = rec
        return true
    end
    local function Check(label, fn)
        local ok, pass = pcall(fn)
        lines[#lines + 1] = (ok and pass and "PASS: " or "FAIL: ") .. label
    end
    Check("Decode and hold a position", function()
        return Push(GL.EncodePosition(e, 1, 1, 5000, 5000)) and inbox.member.x == 5000
    end)
    Check("Reject duplicate and older updates", function()
        local ok, why = Push(GL.EncodePosition(e, 1, 1, 5000, 5000))
        local old, reason = Push(GL.EncodePosition(e - 1, 2, 1, 5000, 5000))
        return not ok and why == "old-number" and not old and reason == "old-epoch"
    end)
    Check("Withdraw and reject a closed session", function()
        if not Push(GL.EncodeWithdraw(e + 1)) or not inbox.member.closed then return false end
        local ok, why = Push(GL.EncodePosition(e + 1, 1, 1, 5000, 5000))
        return not ok and why == "closed-epoch"
    end)
    Check("Resume with a fresh session", function() return Push(GL.EncodePosition(e + 2, 1, 1, 5000, 5000)) and not inbox.member.closed end)
    Check("Expire at the receiver's 300-second boundary", function()
        return GL.RecordCurrent(inbox.member, GL.LIMITS.expiry - 1) and not GL.RecordCurrent(inbox.member, GL.LIMITS.expiry)
    end)
    local ok, code = false, "map-unavailable"
    if GL.Map and GL.Map.SelfTest then ok, code = GL.Map.SelfTest() end
    lines[#lines + 1] = (ok and "PREVIEW: " or "NOT TESTED: ") .. D.Describe(code)
    lines[#lines + 1] = "Confirm the SYNTHETIC badge visually. This does not prove real network delivery, roster matching or cross-map projection."
    return table.concat(lines, "\n")
end

function D.Snapshot()
    return { running = D.IsRunning(), watching = watch ~= nil, responding = responder ~= nil,
        timers = pollT.Engines() + expireT.Engines() + responseT.Engines(), requests = stats.requests,
        replies = stats.replies, timeouts = stats.timeouts, rejected = stats.rejected, events = guildEvent and 1 or 0,
        armed = (pollT.Armed() and 1 or 0) + (expireT.Armed() and 1 or 0) + (responseT.Armed() and 1 or 0) }
end
GL.OnRecords(function()
    if not watch then return end
    local rec = GL.Peek(watch.name)
    local signature = rec and (rec.epoch .. ":" .. rec.number .. ":" .. tostring(rec.closed))
    if signature ~= watch.record then watch.record = signature; D.Changed() end
end)
RS.OnRefresh(function() if watch or test then D.Changed() end end)
GL.OnChange(function(kind)
    if kind ~= "state" then return end
    D.Stop()
    responder = nil
    responseT.Cancel()
    SyncGuildEvent()
end)
OnGuild = function(unit)
    if unit ~= nil and unit ~= "player" then return end
    D.Stop()
    responder = nil
    responseT.Cancel()
    SyncGuildEvent()
end
