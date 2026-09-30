-- TwichUI: Setup Sharing, sending and receiving in game
--
-- Conversation (addressed messages; see "Routing" for which channel):
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
    R.Print("%sSomething went wrong (%s).|r Type /pack status and send me the output.", R.RED, where)
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
-- Routing. On Forever the game silently drops addon whispers to two-part
-- names, so messages go over your group (or guild) channel instead, with
-- the recipient's name inside; everyone else ignores them. Elsewhere,
-- whispers still work for friends who aren't grouped with you.
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
    if not IsInGuild() then return false end
    for i = 1, (GetNumGuildMembers() or 0) do
        local n, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if SH.SameName(n, name) then return true, online end
    end
    return false
end

-- Which channels the player allows. Group and guild are opt-in: those
-- messages reach everyone there (only the named recipient's TwichUI reads them).
function SH.Allowed(dist)
    if dist == "LOOP" then return true end
    if dist == "WHISPER" then return R:Enabled("shareWhisper") end
    if dist == "GUILD" then return R:Enabled("shareGuild") end
    if dist == "PARTY" or dist == "RAID" or dist == "INSTANCE_CHAT" then return R:Enabled("shareGroup") end
    return false
end

-- Tiny group-check messages (version hello, group check, direct-message
-- probe) have their own switch and only ever use the group channel.
SH.GROUP_TYPES = { hello = true, checkreq = true, checkrep = true, probeack = true }
local function AllowedFor(msgType, dist)
    if SH.GROUP_TYPES[msgType] and (dist == "PARTY" or dist == "RAID" or dist == "INSTANCE_CHAT") then
        return R:Enabled("groupCheck")
    end
    if msgType == "probe" and dist == "WHISPER" then return R:Enabled("groupCheck") end
    return SH.Allowed(dist)
end

-- Short explanation reused in errors, the options panel and the window.
SH.WHY_FOREVER = "On the Forever beta, the game silently drops the hidden direct messages addons use when the name has a first and last name, so nothing arrives and no error appears. Until Blizzard fixes that, TwichUI can send through your group or guild channel instead, but only if you allow it."

local function GroupOff(who)
    return ("%s is in your group, but sharing over your group channel is turned off. Turn on \"Allow group channel\" in Sending options (or /twichui)."):format(who)
end
local function GuildOff(who)
    return ("%s is in your guild, but sharing over the guild channel is turned off. Turn on \"Allow guild channel\" in Sending options (or /twichui)."):format(who)
end

-- Returns { dist, whisperTarget } or nil, reason.
function SH.Route(target)
    local who = SH.Short(target)
    if SH.SameName(target, SH.SelfName()) then
        -- Test on yourself: use a real channel you've allowed, else stay local.
        if IsInGroup() and SH.Allowed(GroupDist()) then return { GroupDist() } end
        if IsInGuild() and SH.Allowed("GUILD") then return { "GUILD" } end
        return { "LOOP" }
    end
    -- Forever: once a probe has shown direct messages work again on this
    -- game build, use them first (see setup/Group.lua).
    if SH.Realmless() and SH.WhisperWorks and SH.WhisperWorks() and SH.Allowed("WHISPER") then
        return { "WHISPER", target }
    end
    local reason
    if InMyGroup(target) then
        if SH.Allowed(GroupDist()) then return { GroupDist() } end
        reason = GroupOff(who)
    end
    local inGuild, online = InMyGuild(target)
    if inGuild then
        if online == false then return nil, ("%s isn't online."):format(who) end
        if SH.Allowed("GUILD") then return { "GUILD" } end
        reason = reason or GuildOff(who)
    end
    if not SH.Realmless() then
        if SH.Allowed("WHISPER") then return { "WHISPER", target } end
        return nil, reason or "Direct messages are turned off in Sending options, so TwichUI has no way to reach them."
    end
    if reason then return nil, reason end
    if not R:Enabled("shareGroup") and not R:Enabled("shareGuild") then
        return nil, ("Forever can't deliver direct addon messages yet, and sharing over your group and guild is turned off. Open Sending options to allow one, group up with %s, and press Send again."):format(who)
    end
    return nil, ("Forever can't deliver direct addon messages yet, so TwichUI needs %s in your group%s. Invite them, then press Send again."):format(
        who, R:Enabled("shareGuild") and " or guild" or "")
end

local function RouteFromArrival(dist, sender)
    if dist == "WHISPER" then return { "WHISPER", sender } end
    return { dist }
end

local OnControl, OnLane   -- set below

-- Control messages (small): addressed with "to".
local function Send(target, msg, prio, route)
    msg.to = (target == "*") and "*" or SH.FullName(target)
    local text = Encode(msg)
    if route[1] == "LOOP" then
        local me = SH.SelfName()
        C_Timer.After(0.1, function() OnControl(PREFIX, text, "LOOP", me) end)
        return
    end
    AceComm:SendCommMessage(PREFIX, text, route[1], route[2], prio or "NORMAL")
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
-- Returns false, reason if it can't start.
-- selfTest: send to your own character. It goes through the real addon
-- message path, so you can try the whole flow without a friend.
function SH:SendTo(name, selfTest)
    local mine = ST.Mine()
    if not mine or not next(mine.tables or {}) then return false, "Save your configuration first." end
    local target = SH.FullName(name)
    if not target then return false, "Type your friend's name, or target them." end
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
    SH.outgoing = { target = target, id = id, stage = "offered", sent = 0, total = 0, started = GetTime(), route = route }
    Send(target, {
        t = "offer", p = PROTOCOL, id = id,
        from = SH.SelfName(), created = mine.created, version = mine.version,
        tables = list, em = mine.editModeHash, addons = ST.CountAddons(mine),
        bytes = ST.PackBytes(mine),
    }, "ALERT", route)
    Changed()
    C_Timer.After(OFFER_TIMEOUT, function()
        local o = SH.outgoing
        if o and o.id == id and o.stage == "offered" then
            o.stage = "failed"; o.reason = "No answer. Check they're online, running TwichUI 2.6 or newer, and allow the same channel in their Sending options."
            Changed()
        end
    end)
    return true
end

function SH:SendToSelf()
    return SH:SendTo(SH.SelfName(), true)
end

-- /pack status: what the transfer code thinks is happening (for bug reports).
function SH:Status()
    local P = R.Print
    P("you are %s; route test: %s", tostring(SH.SelfName()), (SH.Route(SH.SelfName()) or { "none" })[1])
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
            AceComm:SendCommMessage(LANES[i], text, o.route[1], o.route[2], "BULK", function(lane, sent)
                if SH.outgoing ~= o or o.stage ~= "sending" then return end
                laneSent[lane] = sent
                local s2 = 0
                for _, v in pairs(laneSent) do s2 = s2 + v end
                o.sent, o.last = s2, GetTime()
                if s2 >= total then o.stage = "delivered" end
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
    local isGroupType = SH.GROUP_TYPES[msg.t] or msg.t == "probe"
    if not isGroupType and not R:Enabled("setupSharing") then return end
    if not AllowedFor(msg.t, dist) then return end
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
    if not SH.Allowed(dist) then return end
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
if notFoundPattern and ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
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

-- Sender watchdog: if nothing has moved for a while, call it failed.
C_Timer.NewTicker(5, function()
    local o = SH.outgoing
    if o and o.stage == "sending" and o.last and GetTime() - o.last > DATA_TIMEOUT then
        o.stage = "failed"; o.reason = "The transfer stalled. Try again; only the missing parts will be sent."
        Changed()
    end
end)
