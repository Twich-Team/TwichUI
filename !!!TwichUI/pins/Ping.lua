-- TwichUI: Map pings, sending, receiving and the recent list
-- A map ping is a spot on the world map shared with your group for a few seconds, like a minimap ping. The game
-- has nothing for this: MINIMAP_PING carries a position on the minimap only (and is restricted), and
-- Blizzard_PingUI is the secure, mainline-only ping of the 3D world. So TwichUI sends its own small message over
-- the group's hidden addon channel. Nothing is ever written in chat, and a group member without TwichUI (with
-- Party pins and Map pings on) sees nothing; no other addon's pings are read or written.
--
-- The message (prefix "TwichUIPing", its own), version 1, plain text and nothing that is run or looked up:
--   "1:<map>:<x>:<y>:<seq>"     map: a map id; x, y: whole steps 0..10000 of the map (the pin system's coordinates);
--                               seq: 0..65535, one more than the sender's last (it starts at a random number)
-- Who sent it is what the game says (the sender argument of the addon message), never a field of the message.
-- Where it goes: one message, to the group the game currently counts: INSTANCE_CHAT in an instance group, RAID in a
-- raid, else PARTY (setup/Share.lua's GroupDist), so a player in a home party and an instance group is sent one.
-- Every incoming message is checked before anything is kept, cheapest first: Map pings and receiving on, the text,
-- the channel and that it fits your group now, that the sender is in your group (a name compared as setup/Share.lua
-- compares them, so "Name", "Name-Realm" and "First Last" forms agree), the sender's rate, the size, the version, the
-- exact shape, a map the game knows, coordinates in range, and that it is not one already seen.
--
-- What is kept (memory only, nothing is saved): the recent list (newest first; at most `listSize` entries, at most
-- two per sender, each for `listMinutes` from the moment it ARRIVED here: a sender's clock is never read), and for each
-- sender in the group a rate bucket and the last few sequence numbers. Leaving the group, turning the feature off or
-- /reload clears all of it. A ping is never passed on to anyone.
--
-- Presentation (the rings, the list, the clicks) is pins/PingMap.lua; this file has no frames.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local PG = PL.Ping
local SH = R.Share
local MP = {}
R.MapPing = MP

local AceComm = LibStub("AceComm-3.0")

MP.PREFIX = "TwichUIPing"
MP.PROTOCOL = 1

-- Every bound in one place (docs/map-pings.md lists them).
MP.LIMITS = {
    outBurst = 3, outRefill = 1 / 3,         -- sending: three pings in a burst, then one every three seconds
    inBurst = 4, inRefill = 0.4,             -- taking in, per sender: four in a burst, then one every 2.5 seconds
    soundGap = 1.5,                          -- seconds between sounds from any senders
    senderSoundGap = 5,                      -- ... and from one sender
    replayGap = 0.6,                         -- seconds between clicks on a recent entry that do anything
    replaySoundGap = 2,                      -- ... and between replay sounds
    seen = 8,                                -- sequence numbers remembered per sender
    perSender = 2,                           -- recent entries kept per sender
    maxSenders = 40,                         -- senders with any state (a raid)
    maxText = 40,                            -- bytes of a message
    maxSeq = 65535,
}
local L = MP.LIMITS

local stats = { sent = 0, refused = 0, received = 0, shown = 0, own = 0, silent = 0, soundPlayed = 0, soundHeld = 0, soundFallback = false }
local drops = {}                              -- reason code -> count; codes only, never names, places or text
local senders = {}                            -- [key] = { tokens, at, seen = { seq... } (a ring), nextSeen, sound }
local entries = {}                            -- newest first
local out = { tokens = L.outBurst, at = nil }
local seq = math.random(0, L.maxSeq)
local nextId = 0
local lastSound, lastReplaySound, lastReplay
local timerGen, timerDue = 0, nil
local subscribers = {}

local function Now() return GetTime() end
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Active() return R:Enabled("partyPins") and R:Enabled("mapPings") end
MP.Active = Active

local function Drop(code)
    drops[code] = (drops[code] or 0) + 1
    local D = R.Diag
    if D and D.Tracing and D.Tracing() then D.Trace("pins", "ping-dropped", code) end
    return false, code
end

local function Trace(code, detail)
    local D = R.Diag
    if D and D.Tracing and D.Tracing() then D.Trace("pins", code, detail) end
end

-- fn(event, entry): "ping" (a ping arrived from someone else), "own" (you sent one), "list" (the recent list
-- changed), "clear" (everything from the group was forgotten) or "prefs" (a ping choice changed). Listeners must not change the list.
function MP.Subscribe(fn) subscribers[#subscribers + 1] = fn end
local function Tell(event, entry)
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, event, entry)
        if not ok and R.Fault then R.Fault("map pings", err) end
    end
end

---------------------------------------------------------------------------
-- Words for the reasons a ping isn't sent
---------------------------------------------------------------------------
local REASONS = {
    ["off"] = "Map pings are turned off.",
    ["send-off"] = "Sending map pings is turned off in the Pins and Pings options.",
    ["no-group"] = "Join a party or raid to ping.",
    ["blocked"] = "The game isn't allowing group messages right now.",
    ["unsupported-map"] = "That map can't be pinged.",
    ["bad-coordinates"] = "That spot is outside the map.",
    ["rate"] = "Pinging too quickly. Wait a moment.",
}
function MP.Reason(code) return REASONS[code] or "That can't be done right now." end

---------------------------------------------------------------------------
-- Maps and places
---------------------------------------------------------------------------
-- A map a ping can be on: one the game knows (the pin system's check) that is not the cosmic map, which is not a
-- place. Where the game gives no map type, a known map is allowed.
function MP.SupportedMap(map)
    if not PN.ValidMap(map) then return false end
    local ok, info = pcall(C_Map.GetMapInfo, map)
    if ok and type(info) == "table" and info.mapType ~= nil and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Cosmic then
        return false
    end
    return true
end

-- A position on a map as whole steps. x, y: 0..1 as the map gives them. Returns steps, steps, or nil and a code.
function MP.Steps(map, x, y)
    if not MP.SupportedMap(map) then return nil, "unsupported-map" end
    local sx, sy = PN.Quantize(x), PN.Quantize(y)
    if not (sx and sy) then return nil, "bad-coordinates" end
    return sx, sy
end

local function Bucket(b, cap, refill, now)
    if b.at then b.tokens = math.min(cap, b.tokens + (now - b.at) * refill) end
    b.at = now
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

---------------------------------------------------------------------------
-- Your group
---------------------------------------------------------------------------
local function IsMember(name)
    if not IsInGroup() then return false end
    local prefix, count = "party", 4
    if IsInRaid() then prefix, count = "raid", 40 end
    for i = 1, count do
        local n = GetUnitName(prefix .. i, true)
        if n and not Secret(n) and SH.SameName(n, name) then return true end
    end
    return false
end
MP.IsMember = IsMember

-- Whether a message from `dist` can be from your group as the game counts it now.
local function FitsGroup(dist)
    if dist == "PARTY" then return IsInGroup() and not IsInRaid() end
    if dist == "RAID" then return IsInRaid() end
    if dist == "INSTANCE_CHAT" then return LE_PARTY_CATEGORY_INSTANCE ~= nil and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
    return false
end

-- The channel a ping would go to now, or nil and a code.
function MP.Route()
    if not Active() then return nil, "off" end
    if not IsInGroup() then return nil, "no-group" end
    if SH.Blocked() then return nil, "blocked" end
    return SH.GroupDist()
end

---------------------------------------------------------------------------
-- The recent list
---------------------------------------------------------------------------
local function Lifetime() return PG.Get("listMinutes") * 60 end

local function Remove(i) table.remove(entries, i) end

-- Takes out what is old (or over the size now chosen). Returns whether anything went.
local function Prune(now)
    local gone = false
    local ttl, size = Lifetime(), PG.Get("listSize")
    for i = #entries, 1, -1 do
        if now - entries[i].at >= ttl or i > size then
            Remove(i)
            gone = true
        end
    end
    return gone
end

local Schedule
local function Expire(gen)
    if gen ~= timerGen then return end
    timerDue = nil
    if Prune(Now()) then Tell("list") end
    Schedule()
end

-- One timer, for the oldest entry's end: no polling. A newer one that ends earlier replaces it.
function Schedule()
    local oldest = entries[#entries]
    if not oldest then return end
    local due = oldest.at + Lifetime()
    if timerDue and timerDue <= due then return end
    timerGen = timerGen + 1
    timerDue = due
    local gen = timerGen
    C_Timer.After(math.max(0.5, due - Now()) + 0.05, function() Expire(gen) end)
end

-- The entries now, newest first. Do not change the table.
function MP.Entries()
    if Prune(Now()) then Tell("list") end
    return entries
end

function MP.Find(id)
    for _, e in ipairs(entries) do if e.id == id then return e end end
    return nil
end

-- Whether an entry is still within its time (a click on one that has gone says so).
function MP.Alive(e)
    return e ~= nil and MP.Find(e.id) == e and Now() - e.at < Lifetime()
end

local function AddEntry(key, who, name, map, x, y)
    local now = Now()
    Prune(now)
    -- at most two per sender: a newer ping of theirs takes the place of their oldest
    local mine = {}
    for i, e in ipairs(entries) do
        if e.key == key then mine[#mine + 1] = i end
    end
    for j = #mine, L.perSender, -1 do Remove(mine[j]) end
    nextId = nextId + 1
    local e = { id = nextId, key = key, who = who, name = name, map = map, x = x, y = y, at = now }
    table.insert(entries, 1, e)
    Prune(now)   -- the size now chosen
    Schedule()
    return e
end

---------------------------------------------------------------------------
-- Sound: one policy for arrivals and for clicks on a recent entry
---------------------------------------------------------------------------
-- Plays the chosen sound now, without any policy. Returns whether the game took it. A chosen sound that has gone
-- (its media pack is not loaded) plays the game's own map ping, so a ping is never silent by accident; the choice
-- is kept as it was.
function MP.PlayChosen()
    stats.soundFallback = false
    local name = PG.Get("soundFile")
    if name ~= PG.GAME_SOUND and PlaySoundFile then
        local path = R:ResolveSound(name)
        if path then
            local ok = PlaySoundFile(path, PG.Get("channel"))
            if ok then stats.soundPlayed = stats.soundPlayed + 1 return true end
        end
        stats.soundFallback = true
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.MAP_PING then
        local ok = PlaySound(SOUNDKIT.MAP_PING)
        if ok then stats.soundPlayed = stats.soundPlayed + 1 return true end
    end
    return false
end

-- kind: "received" (arrival, of the sender `key`), "replay" (a click on a recent entry) or "test" (the options'
-- Test ping). Muted means no sound at all, replays included. Returns whether a sound played.
function MP.Sound(kind, key)
    if not PG.Get("sound") then stats.silent = stats.silent + 1 return false end
    local now = Now()
    if kind == "replay" then
        if lastReplaySound and now >= lastReplaySound and now - lastReplaySound < L.replaySoundGap then
            stats.soundHeld = stats.soundHeld + 1
            return false
        end
        lastReplaySound = now
    elseif kind == "received" then
        if lastSound and now >= lastSound and now - lastSound < L.soundGap then
            stats.soundHeld = stats.soundHeld + 1
            return false
        end
        local s = key and senders[key]
        if s and s.sound and now >= s.sound and now - s.sound < L.senderSoundGap then
            stats.soundHeld = stats.soundHeld + 1
            return false
        end
        if s then s.sound = now end
    end
    lastSound = now
    return MP.PlayChosen()
end

-- A click on a recent entry may do something only this often. Returns whether it may.
function MP.TakeReplay()
    local now = Now()
    if lastReplay and now >= lastReplay and now - lastReplay < L.replayGap then return false end
    lastReplay = now
    return true
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
-- Pings the group at a place on a map. x, y: 0..1 as the map gives them. Explicit player input only: the caller
-- is a click the player made (pins/PingMap.lua). Returns true and a table { map, x, y } (whole steps) to show at
-- once, or false and a reason code (MP.Reason words it).
function MP.Send(map, x, y)
    local dist, why = MP.Route()
    if not dist then return false, why end
    if not R:Enabled("mapPingsSend") then return false, "send-off" end
    local sx, sy = MP.Steps(map, x, y)
    if not sx then return false, sy end
    if not Bucket(out, L.outBurst, L.outRefill, Now()) then return false, "rate" end
    seq = seq >= L.maxSeq and 0 or seq + 1
    local text = ("%d:%d:%d:%d:%d"):format(MP.PROTOCOL, map, sx, sy, seq)
    AceComm:SendCommMessage(MP.PREFIX, text, dist, nil, "NORMAL", function(_, _, _, accepted)
        if accepted == false then
            stats.refused = stats.refused + 1
            Trace("ping-refused")
        end
    end)
    stats.sent = stats.sent + 1
    Trace("ping-sent")
    local ping = { map = map, x = sx, y = sy, own = true }
    stats.own = stats.own + 1
    Tell("own", ping)
    return true, ping
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
-- The state kept for a sender in your group, made on their first message. Only members get this far.
local function Sender(key)
    local s = senders[key]
    if s then return s end
    local n = 0
    for _ in pairs(senders) do n = n + 1 end
    if n >= L.maxSenders then senders = {} end   -- a group is never this big; a stale pile is dropped whole
    s = { tokens = L.inBurst, at = nil, seen = {}, nextSeen = 1 }
    senders[key] = s
    return s
end

local function Seen(s, value)
    for i = 1, L.seen do if s.seen[i] == value then return true end end
    s.seen[s.nextSeen] = value
    s.nextSeen = s.nextSeen % L.seen + 1
    return false
end

-- Reads a message's text. Returns map, x, y, seq, or nil and a code.
local function Parse(text)
    local v = text:match("^(%d+):")
    if not v or #v > 3 then return nil, "malformed" end
    if tonumber(v) > MP.PROTOCOL then return nil, "newer-protocol" end
    if tonumber(v) ~= MP.PROTOCOL then return nil, "bad-version" end
    local map, x, y, s = text:match("^%d+:(%d+):(%d+):(%d+):(%d+)$")
    if not map or #map > 9 or #x > 5 or #y > 5 or #s > 5 then return nil, "malformed" end
    return tonumber(map), tonumber(x), tonumber(y), tonumber(s)
end

local function OnMessage(_, text, dist, sender)
    if not Active() or not R:Enabled("mapPingsReceive") then return end
    if Secret(text) or Secret(sender) or Secret(dist) or type(text) ~= "string" or type(sender) ~= "string" then return Drop("unreadable") end
    if not FitsGroup(dist) then return Drop("channel") end
    local who = SH.FullName(sender)
    if not who then return Drop("sender") end
    if SH.SameName(who, SH.SelfName()) then return end   -- your own, echoed back
    if not IsMember(who) then return Drop("not-member") end
    local key = who:lower()
    local s = Sender(key)
    if not Bucket(s, L.inBurst, L.inRefill, Now()) then return Drop("rate") end
    if #text > L.maxText then return Drop("too-large") end
    local map, x, y, number = Parse(text)
    if not map then return Drop(x) end
    if number > L.maxSeq then return Drop("malformed") end
    if not (PN.ValidCoord(x) and PN.ValidCoord(y)) then return Drop("bad-coordinates") end
    if not MP.SupportedMap(map) then return Drop("unsupported-map") end
    if Seen(s, number) then return Drop("duplicate") end
    stats.received = stats.received + 1
    local name = PN.CleanName(SH.Short(who)) or "?"
    local e = AddEntry(key, who, name, map, x, y)
    Trace("ping-received")
    MP.Sound("received", key)
    Tell("ping", e)
    Tell("list")
end

AceComm:RegisterComm(MP.PREFIX, OnMessage)
MP.OnMessage = OnMessage   -- for tests

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
-- Forgets everything from the group: the list, the senders, the sound times, the waiting timer.
function MP.Clear()
    entries = {}
    senders = {}
    lastSound, lastReplaySound, lastReplay = nil, nil, nil
    timerGen, timerDue = timerGen + 1, nil
    out.tokens, out.at = L.outBurst, nil
    Tell("clear")
end

-- Brings the state in line with the switches and the group. Repeatable.
function MP.Evaluate()
    if not Active() or not IsInGroup() then
        MP.Clear()
        return
    end
    -- a member who left takes their pings and their state; the others keep theirs
    local changed = false
    for i = #entries, 1, -1 do
        if not IsMember(entries[i].who) then
            Remove(i)
            changed = true
        end
    end
    for key in pairs(senders) do
        if not IsMember(key) then senders[key] = nil end
    end
    if changed then Tell("list") end
end

-- The switch changed (Switches.lua) or the game is starting.
function MP.Refresh()
    if Active() then
        R:On("GROUP_ROSTER_UPDATE", MP.Evaluate)
    else
        R:Off("GROUP_ROSTER_UPDATE", MP.Evaluate)
    end
    MP.Evaluate()
end

R:On("PLAYER_ENTERING_WORLD", MP.Refresh)
PG.OnChange(function()
    if Prune(Now()) then Tell("list") end
    Schedule()
    Tell("prefs")
end)

-- Read only, for /tui diagnostics: states and counts, never a name, place or message.
function MP.Snapshot()
    local codes = {}
    for code, n in pairs(drops) do codes[#codes + 1] = ("%s %d"):format(code, n) end
    table.sort(codes)
    local count = 0
    for _ in pairs(senders) do count = count + 1 end
    local registered = "unknown"
    if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
        local ok, result = pcall(C_ChatInfo.IsAddonMessagePrefixRegistered, MP.PREFIX)
        if ok then registered = result and "registered" or "not registered" end
    end
    local channel = "none"
    if Active() and IsInGroup() then channel = SH.Blocked() and "held by the game" or SH.GroupDist() end
    return {
        active = Active(), protocol = MP.PROTOCOL, prefix = MP.PREFIX, prefixState = registered, channel = channel,
        sent = stats.sent, refused = stats.refused, received = stats.received, own = stats.own,
        entries = #entries, senders = count, drops = codes, silent = stats.silent,
        soundPlayed = stats.soundPlayed, soundHeld = stats.soundHeld, soundFallback = stats.soundFallback,
        timerWaiting = timerDue ~= nil,
    }
end
