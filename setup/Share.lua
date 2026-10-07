-- TwichUI: Setup Sharing, sending and receiving in game
--
-- Conversation (addressed messages; see "Routing" for which channel; the
-- player picks Direct, Party or Guild and TwichUI never switches by itself):
--   you    -> friend : offer    what's in your setup, with a fingerprint per addon
--   friend -> you    : reply    accepted? and which parts they don't have yet
--   you    -> friend : incoming how big the transfer is (for their progress bar)
--   you    -> friend : data     just the parts they asked for
--   friend -> you    : done
-- Messages are serialized, compressed and chunked (LibSerialize, LibDeflate,
-- AceComm + ChatThrottleLib). Received data is only ever read as settings;
-- nothing in it is run as code.

local R = TwichUI
local ST = R.Setups
local SH = {}
R.Share = SH

local AceComm = LibStub("AceComm-3.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local PREFIX = "TwichUISetup"
local PROTOCOL = 2
-- Bulk data is split across several prefixes: the game throttles each
-- prefix separately (a burst of 10 messages, then about one per second).
local LANES = { "TwichUIData1", "TwichUIData2", "TwichUIData3", "TwichUIData4" }
local LANE_SET = {}
for i, p in ipairs(LANES) do LANE_SET[p] = i end
local OFFER_TIMEOUT = 120      -- seconds to wait for the friend to click Accept
local DATA_TIMEOUT = 60        -- seconds of silence before a transfer is called off

SH.outgoing = nil   -- { target, id, stage, sent, total, started, want }
SH.incoming = {}    -- [sender] = { id, offer, stage, expected, got }
local listeners = {}
function SH:OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed() for _, fn in ipairs(listeners) do pcall(fn) end end

local function Fail(where, err)
    SH.lastError = ("%s: %s"):format(where, tostring(err))
    R.Print("%sSomething went wrong (%s).|r Type /tui share status and send me the output.", R.RED, where)
    geterrorhandler()(err)
end
SH.Fail = Fail


---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Encode(t)
    local s = LibSerialize:Serialize(t)
    return LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(s, { level = 5 }))
end

local function Decode(str)
    local d = LibDeflate:DecodeForWoWAddonChannel(str)
    if not d then return nil end
    d = LibDeflate:DecompressDeflate(d)
    if not d then return nil end
    local ok, t = LibSerialize:Deserialize(d)
    if ok and type(t) == "table" then return t end
end

---------------------------------------------------------------------------
-- Big payloads are packed and unpacked a little at a time over several
-- frames, so a large configuration can't freeze the game or trip the game's
-- "script ran too long" limit. Format: "Z1" then "<length>:<piece>" pieces,
-- each piece a separately compressed slice of the serialized data.
---------------------------------------------------------------------------
local SLICE = 32768
local BUDGET_MS = 12
local jobs = {}
local jobFrame = CreateFrame("Frame")
local clock = debugprofilestop or function() return GetTime() * 1000 end

local function RunJobs()
    local start = clock()
    while jobs[1] and clock() - start < BUDGET_MS do
        local job = jobs[1]
        local ok, finished = pcall(job.step)
        if not ok then
            table.remove(jobs, 1)
            pcall(job.fail, finished)
        elseif finished then
            table.remove(jobs, 1)
        end
    end
    if not jobs[1] then jobFrame:SetScript("OnUpdate", nil) end
end

local function AddJob(step, fail)
    jobs[#jobs + 1] = { step = step, fail = fail }
    jobFrame:SetScript("OnUpdate", RunJobs)
end

local function EncodeBig(t, done, fail)
    local handler = LibSerialize:SerializeAsync(t)
    local serialized, pos, pieces = nil, 1, {}
    AddJob(function()
        if not serialized then
            local completed, result = handler()
            if completed then serialized = result end
            return false
        end
        if pos > #serialized then
            done("Z1" .. table.concat(pieces))
            return true
        end
        local slice = serialized:sub(pos, pos + SLICE - 1)
        pos = pos + SLICE
        local enc = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(slice, { level = 5 }))
        pieces[#pieces + 1] = #enc .. ":" .. enc
        return false
    end, fail)
end

local function DecodeBig(str, done, fail)
    if type(str) ~= "string" or str:sub(1, 2) ~= "Z1" then fail("not a TwichUI data block") return end
    local pos, parts, handler = 3, {}, nil
    AddJob(function()
        if not handler then
            if pos > #str then
                handler = LibSerialize:DeserializeAsync(table.concat(parts))
                parts = nil
                return false
            end
            local len, from = str:match("^(%d+):()", pos)
            if not len then error("damaged data block") end
            len = tonumber(len)
            local piece = str:sub(from, from + len - 1)
            if #piece ~= len then error("damaged data block") end
            pos = from + len
            local d = LibDeflate:DecodeForWoWAddonChannel(piece)
            d = d and LibDeflate:DecompressDeflate(d)
            if not d then error("damaged data block") end
            parts[#parts + 1] = d
            return false
        end
        local completed, success, result = handler()
        if completed then
            if not success or type(result) ~= "table" then error("damaged data block") end
            done(result)
            return true
        end
        return false
    end, fail)
end

local function MyRealm() return GetNormalizedRealmName() or (GetRealmName() or ""):gsub("[%s%-]", "") end

-- Names. On Forever, characters have a first and a last name ("Ranulf
-- Ashenvow") and there are no realms: that full name is what you whisper.
-- UnitName() only returns the first name there; GetUnitName(unit, true)
-- returns the full one. Everywhere else it's "Name" or "Name-Realm".
function SH.SelfName()
    local n = GetUnitName and GetUnitName("player", true)
    if not n or n == "" then n = UnitName("player") end
    return n
end

function SH.Realmless()
    return (SH.SelfName() or ""):find(" ", 1, true) ~= nil
end

-- The form we whisper to and store: "First Last" on Forever, "Name-Realm" elsewhere.
function SH.FullName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if name == "" then return nil end
    if SH.Realmless() then
        if name:find(" ", 1, true) then name = name:gsub("%-[^%s%-]+$", "") end
    elseif not name:find("-", 1, true) then
        name = name .. "-" .. MyRealm()
    end
    return name
end

function SH.SameName(a, b)
    a, b = SH.FullName(a), SH.FullName(b)
    return a ~= nil and b ~= nil and a:lower() == b:lower()
end

function SH.NameHint()
    return SH.Realmless() and "Friend's full name (first and last)" or "Friend's name (or Name-Realm)"
end

function SH.Short(name)
    if not name then return "?" end
    if SH.Realmless() then return (name:gsub("%-[^%s%-]+$", "")) end
    return Ambiguate(name, "short")
end

-- Midnight-era rules block addon messages during encounters, Mythic+, PvP
-- matches and similar. Check before starting instead of failing halfway.
function SH.Blocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Routing. The player picks how configurations are sent; TwichUI uses that
-- and nothing else, so a failed Direct send is never quietly repeated over
-- your party or guild.
--   Direct: an addon whisper (distribution "WHISPER") to the named character.
--   Party:  your party, raid or instance group's addon channel.
--   Guild:  your guild's addon channel.
-- Party and Guild messages reach everyone in that group; the recipient's name
-- is inside the message and every other TwichUI ignores it. That filters, it
-- doesn't make the data private.
-- Receiving works on all of them whatever you send with.
---------------------------------------------------------------------------
local function GroupDist()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return IsInRaid() and "RAID" or "PARTY"
end

local function InMyGroup(name)
    if not IsInGroup() then return false end
    if IsInRaid() then
        for i = 1, 40 do
            if SH.SameName(GetUnitName("raid" .. i, true), name) then return true end
        end
    else
        for i = 1, 4 do
            if SH.SameName(GetUnitName("party" .. i, true), name) then return true end
        end
    end
    return false
end

local function InMyGuild(name)
    if not IsInGuild() or not GetGuildRosterInfo then return false end
    for i = 1, (GetNumGuildMembers() or 0) do
        local n, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if SH.SameName(n, name) then return true, online end
    end
    return false
end

-- The three ways to send. DIRECT is the default; the choice is saved in
-- TwichUIDB.shareTransport.
SH.TRANSPORTS = { "DIRECT", "PARTY", "GUILD" }
SH.TRANSPORT_LABEL = { DIRECT = "Direct", PARTY = "Party", GUILD = "Guild" }
SH.TRANSPORT_HELP = {
    DIRECT = "Sends straight to the character you name; only they receive it.",
    PARTY = "Sends over your party or raid's hidden addon channel. Everyone in the group receives the data; only the named friend's TwichUI reads it.",
    GUILD = "Sends over your guild's hidden addon channel. Every online guild member receives the data; only the named friend's TwichUI reads it.",
}
SH.TRANSPORT_EXPLAIN = "Direct sends to the character you name. Party and Guild send over those groups' hidden addon channels instead: no chat text appears, but everyone there receives the data, and it is addressed to one person so other TwichUI users ignore it. That is a filter, not privacy; your settings can include character names. TwichUI only uses the one you pick, and never switches on its own if it fails."

local VALID_TRANSPORT = {}
for _, t in ipairs(SH.TRANSPORTS) do VALID_TRANSPORT[t] = true end

function SH.Transport()
    local t = TwichUIDB and TwichUIDB.shareTransport
    return VALID_TRANSPORT[t] and t or "DIRECT"
end

function SH.SetTransport(t)
    if not VALID_TRANSPORT[t] or not TwichUIDB then return false end
    TwichUIDB.shareTransport = t
    Changed()
    return true
end

-- First load with this setting. A new install has nothing saved and gets
-- Direct. Before this, sending went over a group or guild channel only if
-- the player switched "group channel" or "guild channel" on (both start off),
-- so a saved "on" is something they chose and is kept. The old settings can't
-- tell a deliberate choice of Party/Guild from a workaround for the broken
-- direct messages, so nothing is guessed: those players keep what they had
-- and can pick Direct in Sending options. If both were on, Party is kept
-- (the old router tried the group first). Everyone else, including anyone
-- who left the defaults or turned direct messages off with no other
-- channel, gets Direct. The old keys are left as they were.
function SH.MigrateTransport()
    if not TwichUIDB or VALID_TRANSPORT[TwichUIDB.shareTransport] then return end
    local m = TwichUIDB.modules or {}
    TwichUIDB.shareTransport = (m.shareGroup == true and "PARTY") or (m.shareGuild == true and "GUILD") or "DIRECT"
end
R:OnInit(SH.MigrateTransport)

-- Which arrival channels we read. All of them, whatever we send with: a
-- transfer still has to be addressed to us, and nothing is applied before the
-- player has accepted it and clicked Apply.
local RECEIVABLE = { WHISPER = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, LOOP = true }
function SH.Receivable(dist) return RECEIVABLE[dist] == true end

-- Tiny group-check messages (version hello, group check, direct-message
-- probe) have their own switch and only ever use the group channel.
SH.DIAG_TYPES = { commtest = true, commtestack = true }   -- see setup/CommTest.lua
SH.GROUP_TYPES = { hello = true, checkreq = true, checkrep = true, probeack = true }
local function AllowedFor(msgType, dist)
    if SH.GROUP_TYPES[msgType] and (dist == "PARTY" or dist == "RAID" or dist == "INSTANCE_CHAT") then
        return R:Enabled("groupCheck")
    end
    if msgType == "probe" and dist == "WHISPER" then return R:Enabled("groupCheck") end
    return SH.Receivable(dist)
end

-- Returns { dist, whisperTarget } or nil, reason. Never falls back to
-- another transport.
function SH.Route(target)
    local who = SH.Short(target)
    local transport = SH.Transport()
    if SH.SameName(target, SH.SelfName()) then
        -- Test on yourself: use the chosen channel when it exists, else stay
        -- on this computer. (You can't whisper yourself.)
        if transport == "PARTY" and IsInGroup() then return { GroupDist() } end
        if transport == "GUILD" and IsInGuild() then return { "GUILD" } end
        return { "LOOP" }
    end
    if transport == "PARTY" then
        if not IsInGroup() then
            return nil, "You chose Party, but you're not in a party or raid. Join a group, or choose Direct or Guild in Sending options."
        end
        if not InMyGroup(target) then
            return nil, ("You chose Party, but %s isn't in your group. Group up with them, or choose Direct or Guild in Sending options."):format(who)
        end
        return { GroupDist() }
    elseif transport == "GUILD" then
        if not IsInGuild() then
            return nil, "You chose Guild, but you're not in a guild. Choose Direct or Party in Sending options."
        end
        local inGuild, online = InMyGuild(target)
        if not inGuild then
            return nil, ("You chose Guild, but %s isn't in your guild. Choose Direct or Party in Sending options."):format(who)
        end
        if online == false then return nil, ("%s isn't online."):format(who) end
        return { "GUILD" }
    end
    return { "WHISPER", target }
end

-- What to tell the player when the game itself refused a send.
local function RefusedReason(route, who)
    local dist = route and route[1]
    if dist == "WHISPER" then
        return ("The game wouldn't send a direct message to %s. Check their name and that they're online. TwichUI hasn't tried anything else; you can choose Party or Guild in Sending options."):format(who)
    elseif dist == "GUILD" then
        return "The game wouldn't send over the guild channel. Check you're still in the guild, then try again."
    end
    return "The game wouldn't send over the group channel. Check you're still in the group, then try again."
end

local function RouteFromArrival(dist, sender)
    if dist == "WHISPER" then return { "WHISPER", sender } end
    return { dist }
end

local OnControl, OnLane   -- set below

-- Control messages (small): addressed with "to". onRefused, if given, is
-- called once if the game refuses to send a piece. (AceComm hands the callback
-- a true/false "the game accepted it" as its 4th argument; that only says the
-- game took the message, not that anyone received it.)
local function Send(target, msg, prio, route, onRefused)
    msg.to = (target == "*") and "*" or SH.FullName(target)
    local text = Encode(msg)
    if route[1] == "LOOP" then
        local me = SH.SelfName()
        C_Timer.After(0.1, function() OnControl(PREFIX, text, "LOOP", me) end)
        return
    end
    local callback, refused
    if onRefused then
        callback = function(_, _, _, accepted)
            if accepted == false and not refused then
                refused = true
                onRefused()
            end
        end
    end
    AceComm:SendCommMessage(PREFIX, text, route[1], route[2], prio or "NORMAL", callback)
end

local function NewId() return ("%d%04d"):format(time(), math.random(0, 9999)) end

-- For other TwichUI modules (group check): send a small control message.
SH.PREFIX, SH.PROTOCOL = PREFIX, PROTOCOL
function SH.SendControl(target, msg, prio, route) Send(target, msg, prio, route) end
SH.NewId = NewId
SH.GroupDist = GroupDist

---------------------------------------------------------------------------
-- Sending (you)
---------------------------------------------------------------------------
-- Sender watchdog: if nothing has moved for a while, call it failed. Runs
-- only while a send is in progress.
local watchdog
local function StartWatchdog()
    if watchdog then return end
    watchdog = C_Timer.NewTicker(5, function()
        local o = SH.outgoing
        if o and o.stage == "sending" and o.last and GetTime() - o.last > DATA_TIMEOUT then
            o.stage = "failed"; o.reason = "The transfer stalled. Try again; only the missing parts will be sent."
            Changed()
        elseif o and o.stage == "delivered" and o.last and GetTime() - o.last > DATA_TIMEOUT then
            -- Everything was handed to the game, but no "done" came back.
            o.stage = "failed"
            o.reason = ("Everything was sent, but %s never confirmed it arrived. They may not have received it. Ask them, or try again; you can also choose another way to send in Sending options."):format(SH.Short(o.target))
            Changed()
        end
        if not o or (o.stage ~= "offered" and o.stage ~= "packing" and o.stage ~= "sending" and o.stage ~= "delivered") then
            watchdog:Cancel()
            watchdog = nil
        end
    end)
end

-- Returns false, reason if it can't start.
-- selfTest: send to your own character. It goes through the real addon
-- message path, so you can try the whole flow without a friend.
function SH:SendTo(name, selfTest)
    local mine = ST.Mine()
    if not mine or not (next(mine.tables or {}) or mine.eui) then return false, "Save your configuration first." end
    local target = SH.FullName(name)
    if not target then return false, "Type your friend's name, or target them." end
    if target:find("#", 1, true) then
        return false, "That looks like a Battle.net name. Type the character's name instead."
    end
    if SH.Realmless() and not target:find(" ", 1, true) then
        return false, ("Forever needs the full name, first and last (like %s)."):format(SH.SelfName())
    end
    if SH.SameName(target, SH.SelfName()) and not selfTest then
        return false, "That's you. Use \"Test on myself\" to try it out."
    end
    if SH.Blocked() then return false, "Sharing is blocked here right now (instance restrictions). Try in a city." end
    if SH.outgoing and SH.outgoing.stage ~= "done" and SH.outgoing.stage ~= "failed" then
        return false, "Already sending to " .. SH.Short(SH.outgoing.target) .. "."
    end
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    local route, why = SH.Route(target)
    if not route then return false, why end

    local list = {}
    for tname, e in pairs(mine.tables) do list[tname] = { owner = e.owner, hash = e.hash } end
    local id = NewId()
    local o = { target = target, id = id, stage = "offered", sent = 0, total = 0, started = GetTime(), route = route }
    SH.outgoing = o
    StartWatchdog()
    Send(target, {
        t = "offer", p = PROTOCOL, id = id,
        from = SH.SelfName(), created = mine.created, version = mine.version,
        tables = list, em = mine.editModeHash, addons = ST.CountAddons(mine),
        bytes = ST.PackBytes(mine),
    }, "ALERT", route, function()
        if SH.outgoing == o and o.stage == "offered" then
            o.stage = "failed"; o.reason = RefusedReason(route, SH.Short(target))
            Changed()
        end
    end)
    Changed()
    C_Timer.After(OFFER_TIMEOUT, function()
        if SH.outgoing == o and o.stage == "offered" then
            local how = route[1] == "WHISPER" and "directly" or (route[1] == "GUILD" and "over the guild channel" or "over the group channel")
            o.stage = "failed"; o.reason = ("No answer. The game accepted the offer, but nothing came back. Check %s is online and running a recent TwichUI with configuration sharing on, then try again. TwichUI sent it %s only; you can choose another way in Sending options. (TwichUI versions before this change may only listen on the group or guild channel if their owner switched that on.)"):format(SH.Short(target), how)
            Changed()
        end
    end)
    return true
end

function SH:SendToSelf()
    return SH:SendTo(SH.SelfName(), true)
end

-- /tui share status: what the transfer code thinks is happening (for bug reports).
function SH:Status()
    local P = R.Print
    P("you are %s; sending by %s; self-test route: %s", tostring(SH.SelfName()), SH.TRANSPORT_LABEL[SH.Transport()], (SH.Route(SH.SelfName()) or { "none" })[1])
    local o = SH.outgoing
    if o then
        P("sending to %s: %s via %s (%s/%s bytes)%s", tostring(o.target), tostring(o.stage), tostring(o.route and o.route[1]),
            tostring(o.sent), tostring(o.total), o.reason and (" - " .. o.reason) or "")
    else
        P("not sending anything")
    end
    local any = false
    for sender, inc in pairs(SH.incoming) do
        any = true
        P("from %s: %s via %s (%s/%s bytes)%s", tostring(sender), tostring(inc.stage), tostring(inc.route and inc.route[1]),
            tostring(inc.got), tostring(inc.expected), inc.reason and (" - " .. inc.reason) or "")
    end
    if not any then P("nothing incoming") end
    P("last message: %s", SH.lastSeen or "none")
    if SH.lastDropped then P("last ignored: %s", SH.lastDropped) end
    if SH.lastError then P("%slast error: %s|r", R.RED, SH.lastError) end
end

function SH:CancelSend()
    if SH.outgoing then SH.outgoing.stage = "failed"; SH.outgoing.reason = "Cancelled." ; Changed() end
end

local function SendData(o, want, wantEM)
    local mine = ST.Mine()
    local tables = {}
    for _, tname in ipairs(want or {}) do
        local e = mine.tables[tname]
        if e then tables[tname] = { owner = e.owner, data = e.data, hash = e.hash } end
    end
    local payload = {
        t = "data", p = PROTOCOL, id = o.id,
        meta = { created = mine.created, version = mine.version, source = mine.source, sourceName = mine.sourceName },
        keep = {}, tables = tables,
    }
    for tname, e in pairs(mine.tables) do payload.keep[tname] = { owner = e.owner, hash = e.hash } end
    if wantEM and mine.editMode then payload.em, payload.emName = mine.editMode, mine.editModeName end
    payload.emHash = mine.editModeHash
    payload.addons = mine.addons
    payload.eui = mine.eui   -- one EllesmereUI profile, as EllesmereUI exported it

    o.stage = "packing"
    o.last = GetTime()
    o.parts = #want
    Changed()
    EncodeBig(payload, function(encoded)
        if SH.outgoing ~= o or o.stage ~= "packing" then return end
        SH.SendLanes(o, encoded)
    end, function(err)
        o.stage = "failed"
        o.reason = "Couldn't package your configuration: " .. tostring(err)
        Changed()
        Fail("packaging your configuration", err)
    end)
end

function SH.SendLanes(o, encoded)
    local nLanes = math.max(1, math.min(#LANES, math.ceil(#encoded / 1500)))
    local per = math.ceil(#encoded / nLanes)
    local pieces, total = {}, 0
    for i = 1, nLanes do
        local text = ("%s:%d:%d:"):format(o.id, i, nLanes) .. encoded:sub((i - 1) * per + 1, i * per)
        pieces[i] = text
        total = total + #text
    end
    o.stage = "sending"
    o.last = GetTime()
    o.sent, o.total = 0, total
    local laneSent = {}
    Changed()
    Send(o.target, { t = "incoming", id = o.id, size = total }, "ALERT", o.route)
    for i, text in ipairs(pieces) do
        if o.route[1] == "LOOP" then
            local me = SH.SelfName()
            C_Timer.After(0.2 * i, function()
                OnLane(LANES[i], text, "LOOP", me)
                if SH.outgoing ~= o or o.stage ~= "sending" then return end
                laneSent[i] = #text
                local sent = 0
                for _, v in pairs(laneSent) do sent = sent + v end
                o.sent, o.last = sent, GetTime()
                if sent >= total then o.stage = "delivered" end
                Changed()
            end)
        else
            AceComm:SendCommMessage(LANES[i], text, o.route[1], o.route[2], "BULK", function(lane, sent, _, accepted)
                if SH.outgoing ~= o or o.stage ~= "sending" then return end
                if accepted == false then
                    o.stage = "failed"; o.reason = RefusedReason(o.route, SH.Short(o.target))
                    Changed()
                    return
                end
                laneSent[lane] = sent
                local s2 = 0
                for _, v in pairs(laneSent) do s2 = s2 + v end
                o.sent, o.last = s2, GetTime()
                if s2 >= total then o.stage = "delivered" end   -- handed to the game; the friend's "done" is the confirmation
                Changed()
            end, i)
        end
    end
end

---------------------------------------------------------------------------
-- Receiving (friend)
---------------------------------------------------------------------------
local function WantList(sender, offer)
    local have = ST.db.received[sender]
    local want = {}
    for tname, e in pairs(offer.tables or {}) do
        local mine = have and have.tables[tname]
        if not (mine and mine.hash and mine.hash == e.hash) then want[#want + 1] = tname end
    end
    local wantEM = offer.em ~= nil and not (have and have.editModeHash == offer.em)
    return want, wantEM
end

function SH:Respond(sender, accept, always)
    if not sender then
        -- Fallback: the one configuration waiting for an answer.
        for k, v in pairs(SH.incoming) do if v.stage == "asking" then sender = k end end
    end
    local inc = sender and SH.incoming[sender]
    if not inc or inc.stage ~= "asking" then return end
    if always then ST.db.trusted[sender] = true end
    if not accept then
        inc.stage = "declined"
        Send(sender, { t = "reply", id = inc.id, accept = false }, "ALERT", inc.route)
        Changed()
        return
    end
    local want, wantEM = WantList(sender, inc.offer)
    inc.stage = "waiting"
    inc.parts = #want
    inc.last = GetTime()
    local okSend, err = pcall(Send, sender, { t = "reply", id = inc.id, accept = true, want = want, wantEM = wantEM }, "ALERT", inc.route)
    if not okSend then Fail("sending your answer", err) end
    Changed()
    local id = inc.id
    local function watchdog()
        local cur = SH.incoming[sender]
        if not cur or cur.id ~= id or cur.stage == "done" or cur.stage == "failed" then return end
        if GetTime() - (cur.last or 0) > DATA_TIMEOUT then
            cur.stage = "failed"; cur.reason = "The transfer stopped. Ask them to send again; only the missing parts will be sent."
            Changed()
        else
            C_Timer.After(5, watchdog)
        end
    end
    C_Timer.After(5, watchdog)
end

local function Validate(t)
    -- Settings only: names are strings, data is plain tables (DeepCopy strips anything else).
    if type(t) ~= "table" then return false end
    for tname, e in pairs(t) do
        if type(tname) ~= "string" or type(e) ~= "table" or type(e.owner) ~= "string" then return false end
        if not ST.SafeName(tname) then return false end
    end
    return true
end

local function StoreReceived(sender, msg)
    local old = ST.db.received[sender]
    local pack = {
        format = 2,
        created = msg.meta.created, version = msg.meta.version,
        source = msg.meta.source, sourceName = msg.meta.sourceName or SH.Short(sender),
        sender = sender, received = time(),
        tables = {},
    }
    -- keep = the full list in the sender's setup; take new data where sent,
    -- otherwise reuse what we already had (same fingerprint).
    for tname, e in pairs(msg.keep) do
        local sent = msg.tables[tname]
        if sent and type(sent.data) == "table" then
            pack.tables[tname] = { owner = e.owner, hash = e.hash, data = ST.DeepCopy(sent.data) }
        elseif old and old.tables[tname] and old.tables[tname].hash == e.hash then
            pack.tables[tname] = old.tables[tname]
        end
    end
    pack.eui = R.Ellesmere.CleanEntry(msg.eui)   -- nil unless it is a well-formed EllesmereUI profile
    if msg.em then
        pack.editMode, pack.editModeName, pack.editModeHash = msg.em, msg.emName, msg.emHash
    elseif old and old.editModeHash and old.editModeHash == msg.emHash then
        pack.editMode, pack.editModeName, pack.editModeHash = old.editMode, old.editModeName, old.editModeHash
    end
    -- Recommended addon list: plain text only.
    if type(msg.addons) == "table" then
        pack.addons = {}
        for key, e in pairs(msg.addons) do
            if type(key) == "string" and type(e) == "table" and type(e.title) == "string" then
                local folders = {}
                for _, fo in ipairs(type(e.folders) == "table" and e.folders or {}) do
                    if type(fo) == "string" then folders[#folders + 1] = fo end
                end
                local function str(v) return type(v) == "string" and v or nil end
                pack.addons[key] = { title = e.title, version = str(e.version), curse = str(e.curse),
                    wago = str(e.wago), wowi = str(e.wowi), website = str(e.website), folders = folders }
            end
        end
    end
    ST.db.received[sender] = pack
    return pack
end

---------------------------------------------------------------------------
-- Message handling
---------------------------------------------------------------------------
local handlers = {}
SH.handlers = handlers   -- other modules add their own message types here

handlers.offer = function(sender, msg, dist)
    local route = RouteFromArrival(dist, sender)
    if not R:Enabled("acceptSetups") then
        Send(sender, { t = "reply", id = msg.id, accept = false, reason = "off" }, "ALERT", route)
        return
    end
    if msg.p ~= PROTOCOL then
        Send(sender, { t = "reply", id = msg.id, accept = false, reason = "version" }, "ALERT", route)
        return
    end
    if type(msg.tables) ~= "table" then return end
    SH.incoming[sender] = { id = msg.id, offer = msg, stage = "asking", got = 0, expected = 0, route = route, parts = {} }
    Changed()
    if ST.db.trusted[sender] then
        SH:Respond(sender, true)
    elseif R.Window then
        R.Window:AskAccept(sender, msg)
    end
end

handlers.reply = function(sender, msg)
    local o = SH.outgoing
    if not o or o.id ~= msg.id or not SH.SameName(o.target, sender) then
        SH.lastDropped = ("reply ignored (sending=%s, id %s vs %s, from %s vs %s)"):format(
            tostring(o and o.stage), tostring(o and o.id), tostring(msg.id), tostring(sender), tostring(o and o.target))
        return
    end
    if not msg.accept then
        o.stage = "failed"
        o.reason = (msg.reason == "off" and "They've turned off receiving configurations.")
            or (msg.reason == "version" and "They need to update TwichUI.")
            or "They declined."
        Changed()
        return
    end
    if type(msg.want) ~= "table" then SH.lastDropped = "reply without a want list" return end
    -- Even when nothing is new we still send the (small) list, so addons you
    -- removed from your setup disappear on their side too.
    local ok, err = pcall(SendData, o, msg.want, msg.wantEM)
    if not ok then
        o.stage = "failed"
        o.reason = "Couldn't package your configuration: " .. tostring(err)
        Changed()
        Fail("packaging your configuration", err)
    end
end

handlers.incoming = function(sender, msg)
    local inc = SH.incoming[sender]
    if not inc or inc.id ~= msg.id then return end
    inc.stage = "receiving"
    inc.expected = tonumber(msg.size) or 0
    inc.got = 0
    inc.lanes = inc.lanes or {}
    inc.last = GetTime()
    Changed()
end

handlers.data = function(sender, msg)
    local inc = SH.incoming[sender]
    if not inc or inc.id ~= msg.id or (inc.stage ~= "receiving" and inc.stage ~= "waiting") then return end
    if type(msg.meta) ~= "table" or not Validate(msg.keep) or not Validate(msg.tables) then
        inc.stage = "failed"; inc.reason = "The configuration arrived damaged. Ask them to send again."
        Changed()
        return
    end
    StoreReceived(sender, msg)
    inc.stage = "done"
    inc.got = inc.expected
    Send(sender, { t = "done", id = msg.id }, "ALERT", inc.route)
    Changed()
    if R.Window then R.Window:Received(sender) end
end

handlers.done = function(sender, msg)
    local o = SH.outgoing
    if o and o.id == msg.id and SH.SameName(o.target, sender) then
        o.stage = "done"
        Changed()
        R.Print("%s has your addon configuration now.", SH.Short(sender))
    end
end

OnControl = function(_, text, dist, sender)
    sender = SH.FullName(sender)
    local okDecode, msg = pcall(Decode, text)
    if not okDecode then Fail("reading a message", msg) return end
    if not msg or type(msg.t) ~= "string" then
        SH.lastDropped = ("undecodable message from %s (%d bytes)"):format(tostring(sender), #text)
        return
    end
    -- TEMPORARY (commtest): diagnostic types ignore the sharing switches; they carry no private data.
    local isDiag = SH.DIAG_TYPES[msg.t]
    local isGroupType = SH.GROUP_TYPES[msg.t] or msg.t == "probe" or isDiag
    if not isGroupType and not R:Enabled("setupSharing") then return end
    if not isDiag and not AllowedFor(msg.t, dist) then return end
    SH.lastSeen = ("%s from %s via %s"):format(msg.t, tostring(sender), tostring(dist))
    -- Broadcasts (group check) are for everyone except their sender.
    if msg.to == "*" and isGroupType then
        if dist ~= "LOOP" and SH.SameName(sender, SH.SelfName()) then return end
    -- Group and guild messages reach everyone; only handle ones meant for us.
    elseif not SH.SameName(msg.to, SH.SelfName()) then
        SH.lastDropped = ("%s addressed to %s, not you"):format(msg.t, tostring(msg.to))
        return
    end
    local h = handlers[msg.t]
    if h then
        local ok, err = pcall(h, sender, msg, dist)
        if not ok then Fail("handling " .. msg.t, err) end
    end
end

-- Data lanes: "<id>:<index>:<count>:<piece>". Pieces are kept only for a
-- transfer we accepted from that sender; everything else is ignored.
OnLane = function(_, text, dist, sender)
    if not R:Enabled("setupSharing") then return end
    if not SH.Receivable(dist) then return end
    sender = SH.FullName(sender)
    local inc = SH.incoming[sender]
    if not inc or (inc.stage ~= "receiving" and inc.stage ~= "waiting") then return end
    local id, idx, n, rest = text:match("^(%d+):(%d+):(%d+):()")
    if not id or id ~= inc.id then return end
    idx, n = tonumber(idx), tonumber(n)
    if not idx or not n or n < 1 or n > #LANES or idx < 1 or idx > n then return end
    inc.lanes = inc.lanes or {}
    inc.lanes[idx] = text:sub(rest)
    inc.last = GetTime()
    for i = 1, n do if not inc.lanes[i] then return end end
    local joined = table.concat(inc.lanes, "", 1, n)
    inc.lanes = nil
    inc.stage = "unpacking"
    inc.last = GetTime()
    Changed()
    DecodeBig(joined, function(msg)
        inc.last = GetTime()
        if msg.t ~= "data" then error("damaged data block") end
        inc.stage = "receiving"   -- handlers.data expects an active transfer
        local ok, err = pcall(handlers.data, sender, msg)
        if not ok then Fail("storing the configuration", err) end
    end, function(err)
        inc.stage = "failed"; inc.reason = "The configuration arrived damaged. Ask them to send again."
        Changed()
        Fail("unpacking the configuration", err)
    end)
end

AceComm:RegisterComm(PREFIX, OnControl)
for _, lane in ipairs(LANES) do AceComm:RegisterComm(lane, OnLane) end

-- Receive progress: count raw chunks on the data lanes as they arrive.
R:On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
    if not LANE_SET[prefix] then return end
    local inc = SH.incoming[SH.FullName(sender)]
    if inc and inc.stage == "receiving" then
        inc.got = inc.got + #text
        inc.last = GetTime()
        if not inc.tick or GetTime() - inc.tick > 0.25 then inc.tick = GetTime(); Changed() end
    end
end)

-- "No player named 'X' is currently playing." The game prints one per
-- message chunk. Turn it into a single clear failure and hide the repeats.
local notFoundPattern
if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" then
    notFoundPattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end
-- ChatFrame_AddMessageEventFilter is only a deprecation fallback on current clients.
local AddMessageEventFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if notFoundPattern and AddMessageEventFilter then
    AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return false end
        local who = msg:match(notFoundPattern)
        if not who then return false end
        local o = SH.outgoing
        if o and SH.SameName(o.target, who) then
            if o.stage == "offered" or o.stage == "sending" then
                o.stage = "failed"
                o.reason = SH.Realmless()
                    and ("Couldn't find %s. Check the full name (first and last) and that they're online."):format(SH.Short(o.target))
                    or ("Couldn't find %s. Check the name and that they're online."):format(SH.Short(o.target))
                Changed()
            end
            return true
        end
        for sender, inc in pairs(SH.incoming) do
            if SH.SameName(sender, who) and inc.stage ~= "done" then return true end
        end
        return false
    end)
end

