-- TwichUI: Party pins, sharing with the party
-- Carries party pins between party members who have TwichUI, over the party's hidden addon channel
-- (PARTY, or INSTANCE_CHAT in an instance group). Nothing is ever written in chat. Members without
-- TwichUI see nothing of it.
--
-- Messages (prefix "TwichUIPins", its own: never mixed with configuration transfers), version 1:
--   put  { v, o = "put", p = pin }    a pin of the sender's, new or changed (a higher revision)
--   del  { v, o = "del", id, r }      the sender removed one of their pins for the party
--   hi   { v, o = "hi" }              the sender joined, reloaded or turned party pins on
--   all  { v, o = "all", l = { pin } } the sender's full list, in answer to hi (unlisted ones were removed)
-- pin = { id, r = revision, m = map, x, y (0..10000), n = name, c = color id }.
-- Who sent it is what the game says, never a field of the message: a pin's owner is always its sender,
-- so a member can only add, change or remove their own. Every message is checked before anything is
-- kept: the channel, that the sender is in your party now, the size, the version, and every field of
-- every pin (pins/Pins.lua). Messages are serialized but not compressed, so nothing grows on arrival.
--
-- The session: starts when you are in a party with party pins on, and ends when you leave the party or
-- turn them off; its pins, removals and "removed from my map" records go with it. In a raid nothing is
-- sent or taken in (paused); back in a party the pins are brought up to date. After a /reload while you
-- are still in the party the session is put back as it was (kept in TwichUIDB.pins.session for that one
-- load and cleared at the next); a fresh login always starts empty. A member who leaves takes their pins.
-- The group leader plays no part: it doesn't identify the party and has no say over anyone's pins.
-- The game accepting a message is not proof anyone received it; nothing here claims it.

local R = TwichUI
local PN = R.Pins
local SH = R.Share
local PS = {}
R.PinSync = PS

local AceComm = LibStub("AceComm-3.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

PS.PREFIX = "TwichUIPins"
local MAX_TEXT = 4000          -- an encoded message, after AceComm has joined its pieces
local HELLO_GAP = 15           -- seconds between your own hellos
local LIST_GAP = 6             -- seconds between your full lists
local BUCKET_SIZE, BUCKET_REFILL = 15, 0.5   -- per sender: a burst of 15, then one message every 2 seconds
local MAX_BUCKETS = 8

local stats = { sent = 0, refused = 0, received = 0, hellos = 0, lists = 0, restored = false }
local buckets = {}             -- [sender] = { tokens, at }
local token = 0                -- bumped as a session starts or ends: a waiting timer for an older one does nothing
local lastHello, lastList = -math.huge, -math.huge
local listPending = false
local paused = false           -- in a raid with a session open
local firstWorld = true

local function Enabled() return R:Enabled("partyPins") end
local function Now() return GetTime() end

local function InParty() return IsInGroup() and not IsInRaid() end

local function IsMember(name)
    if not IsInGroup() or IsInRaid() then return false end
    for i = 1, 4 do
        local n = GetUnitName("party" .. i, true)
        if n and SH.SameName(n, name) then return true end
    end
    return false
end
PS.IsMember = IsMember

-- nil when party pins can be sent now, else a reason code (see Pins.Reason).
function PS.Blocked()
    if not Enabled() then return "off" end
    if not IsInGroup() then return "no-party" end
    if IsInRaid() then return "paused" end
    if not PN.SessionOpen() then return "not-ready" end
    if SH.Blocked() then return "blocked" end
    return nil
end
PN.SendBlocked = PS.Blocked

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function Encode(msg) return LibDeflate:EncodeForWoWAddonChannel(LibSerialize:Serialize(msg)) end

local function Decode(text)
    local raw = LibDeflate:DecodeForWoWAddonChannel(text)
    if not raw then return nil end
    local ok, success, t = pcall(LibSerialize.Deserialize, LibSerialize, raw)
    if ok and success and type(t) == "table" then return t end
end

local function Trace(code, detail)
    local D = R.Diag
    if D and D.Tracing() then D.Trace("pins", code, detail) end
end

-- Returns true when the game took the message (not that anyone got it), or false and a reason code.
local function Send(msg)
    local blocked = PS.Blocked()
    if blocked then return false, blocked end
    msg.v = PN.PROTOCOL
    local text = Encode(msg)
    local mine = token
    AceComm:SendCommMessage(PS.PREFIX, text, SH.GroupDist(), nil, "NORMAL", function(_, _, _, accepted)
        if accepted == false and mine == token then
            stats.refused = stats.refused + 1
            Trace("refused", msg.o)
        end
    end)
    stats.sent = stats.sent + 1
    Trace("sent", msg.o)
    return true
end

local function Wire(p)
    return { id = p.id, r = p.rev, m = p.map, x = p.x, y = p.y, n = p.name, c = p.color }
end

function PS.SayHello()
    if Now() - lastHello < HELLO_GAP then return false end
    if Send({ o = "hi" }) then
        lastHello = Now()
        stats.hellos = stats.hellos + 1
        return true
    end
    return false
end

-- Your full list, once, a moment after someone asks: several hellos at once get one answer, and the
-- delay is a little random so a party doesn't answer all at the same instant.
local function SendList()
    listPending = false
    local list = {}
    for _, p in ipairs(PN.OwnPins()) do list[#list + 1] = Wire(p) end
    if Send({ o = "all", l = list }) then
        lastList = Now()
        stats.lists = stats.lists + 1
    end
end

local function ScheduleList()
    if listPending or not PN.HasPublished() then return end
    listPending = true
    local delay = 1.5 + math.random() * 2
    local since = Now() - lastList
    if since < LIST_GAP then delay = math.max(delay, LIST_GAP - since) end
    local mine = token
    C_Timer.After(delay, function()
        if mine ~= token then return end   -- the session it was for is over
        SendList()
    end)
end
PS.FlushList = SendList    -- for tests

---------------------------------------------------------------------------
-- What you do with your own party pins
---------------------------------------------------------------------------
-- fields: { map, x, y, name, color }. Returns the pin, or nil and a reason code.
function PS.CreateParty(fields)
    local blocked = PS.Blocked()
    if blocked then return nil, blocked end
    local pin, why = PN.CreateOwn(fields)
    if not pin then return nil, why end
    Send({ o = "put", p = Wire(pin) })
    return pin
end

function PS.UpdateParty(key, fields)
    local pin = PN.Shared(key)
    local ok, why = PN.Can("edit", { kind = "party", pin = pin or { key = key } })
    if not ok then return nil, why end
    local updated, code = PN.UpdateOwn(key, fields)
    if not updated then return nil, PN.Reason(code) end
    Send({ o = "put", p = Wire(updated) })
    return updated
end

-- Asked again here, at the moment it runs, whatever the menu showed.
function PS.RemoveForParty(key)
    local pin = PN.Shared(key)
    local ok, why = PN.Can("removeParty", { kind = "party", pin = pin or { key = key } })
    if not ok then return false, why end
    local rev, old = PN.DeleteOwn(key)
    if not rev then return false, PN.Reason(old) end
    Send({ o = "del", id = old.id, r = rev })
    return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Take(sender)
    local now = Now()
    local b = buckets[sender]
    if not b then
        local n = 0
        for _ in pairs(buckets) do n = n + 1 end
        if n >= MAX_BUCKETS then wipe(buckets) end   -- only party members get this far; a party has 4
        b = { tokens = BUCKET_SIZE, at = now }
        buckets[sender] = b
    end
    b.tokens = math.min(BUCKET_SIZE, b.tokens + (now - b.at) * BUCKET_REFILL)
    b.at = now
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

local function OnMessage(_, text, dist, sender)
    if not Enabled() then return end
    if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then PN.Drop("unreadable") return end
    if dist ~= "PARTY" and dist ~= "INSTANCE_CHAT" then PN.Drop("channel") return end
    if IsInRaid() then PN.Drop("paused") return end
    sender = SH.FullName(sender)
    if not sender or SH.SameName(sender, SH.SelfName()) then return end   -- your own, echoed back
    if not IsMember(sender) then PN.Drop("not-member") return end
    if not Take(sender) then PN.Drop("rate") Trace("dropped", "rate") return end
    if #text > MAX_TEXT then PN.Drop("too-large") return end
    local msg = Decode(text)
    if not msg then PN.Drop("undecodable") return end
    if msg.v ~= PN.PROTOCOL then
        PN.Drop(type(msg.v) == "number" and msg.v > PN.PROTOCOL and "newer-protocol" or "bad-version")
        return
    end
    if not PN.SessionOpen() then PN.Drop("no-party") return end
    stats.received = stats.received + 1
    local op = msg.o
    if op == "put" then
        PN.ApplyPut(sender, msg.p)
    elseif op == "del" then
        PN.ApplyDel(sender, msg.id, msg.r)
    elseif op == "all" then
        PN.ApplyAll(sender, msg.l)
    elseif op == "hi" then
        ScheduleList()
    else
        PN.Drop("unknown-op")
        return
    end
    Trace("received", op)
end

AceComm:RegisterComm(PS.PREFIX, OnMessage)

---------------------------------------------------------------------------
-- The session
---------------------------------------------------------------------------
local function Prune()
    for _, owner in ipairs(PN.Owners()) do
        if not IsMember(owner) then PN.RemoveOwner(owner) end
    end
    for name in pairs(buckets) do
        if not IsMember(name) then buckets[name] = nil end
    end
end

-- A hello a moment after joining (or reloading, or leaving a raid): the others' rosters need to show you
-- first, or they would set it aside as coming from someone outside the party. For this session only.
local HELLO_DELAY = 3
local function HelloSoon()
    local mine = token
    C_Timer.After(HELLO_DELAY, function()
        if mine == token then PS.SayHello() end
    end)
end

local function Begin()
    token = token + 1
    listPending = false
    lastHello, lastList = -math.huge, -math.huge
end

local function Finish()
    token = token + 1
    listPending = false
    paused = false
    wipe(buckets)
    PN.EndSession()
end

-- Brings the session in line with the switch and the group. Repeatable.
function PS.Evaluate()
    if not Enabled() or not IsInGroup() then
        if PN.SessionOpen() then Finish() end
        return
    end
    if IsInRaid() then
        -- paused: kept as it is; who is still here is checked when the group is a party again
        if PN.SessionOpen() then paused = true end
        return
    end
    if not PN.SessionOpen() then
        Begin()
        PN.StartSession()
        HelloSoon()
    else
        Prune()
        if paused then
            paused = false
            lastHello = -math.huge
            HelloSoon()   -- back from a raid: catch up
        end
    end
end

-- The switch changed (Settings.lua).
function PS.Refresh()
    if Enabled() then
        R:On("GROUP_ROSTER_UPDATE", PS.Evaluate)
    else
        R:Off("GROUP_ROSTER_UPDATE", PS.Evaluate)
    end
    PS.Evaluate()
end

R:On("PLAYER_ENTERING_WORLD", function(_, isReload)
    if firstWorld then
        firstWorld = false
        local db = type(TwichUIDB) == "table" and type(TwichUIDB.pins) == "table" and TwichUIDB.pins or nil
        local saved = db and db.session
        if db then db.session = nil end      -- used for this load only, whatever happens next
        if Enabled() then R:On("GROUP_ROSTER_UPDATE", PS.Evaluate) end
        if isReload and Enabled() and InParty() and type(saved) == "table"
            and type(saved.char) == "string" and SH.SameName(saved.char, SH.SelfName()) then
            Begin()
            if PN.ImportSession(saved) then
                stats.restored = true
                Prune()
                lastHello = -math.huge
                HelloSoon()
                return
            end
        end
    end
    PS.Evaluate()
end)

-- Kept for the next load only if it turns out to be a /reload in the same party (see above).
R:On("PLAYER_LOGOUT", function()
    if type(TwichUIDB) ~= "table" then return end
    local db = TwichUIDB.pins
    if Enabled() and IsInGroup() and PN.SessionOpen() then
        if type(db) ~= "table" then db = {}; TwichUIDB.pins = db end
        local s = PN.ExportSession()
        s.char = SH.FullName(SH.SelfName())
        s.saved = time()
        db.session = s
    elseif type(db) == "table" then
        db.session = nil
    end
end)

-- Read only, for /tui diagnostics: states and counts, never names, places or payloads.
function PS.Snapshot()
    local transport
    if not Enabled() then transport = "off"
    elseif not IsInGroup() then transport = "none (not grouped)"
    elseif IsInRaid() then transport = "paused (raid)"
    elseif SH.Blocked() then transport = "held by the game"
    else transport = SH.GroupDist() end
    local registered = "unknown"
    if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
        local ok, result = pcall(C_ChatInfo.IsAddonMessagePrefixRegistered, PS.PREFIX)
        if ok then registered = result and "registered" or "not registered" end
    end
    return {
        protocol = PN.PROTOCOL, prefix = PS.PREFIX, prefixState = registered, transport = transport,
        paused = paused, listPending = listPending, sent = stats.sent, refused = stats.refused,
        received = stats.received, hellos = stats.hellos, lists = stats.lists, restored = stats.restored,
        helloAge = lastHello > -math.huge and math.floor(Now() - lastHello) or nil,
    }
end
