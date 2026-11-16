-- TwichUI: Reminders, sharing one reminder with another player
-- You choose a reminder and a player (or your group); they are asked; if they accept, it is sent and both of you see
-- its progress; what arrives is checked and added to their reminders turned off. Nothing is applied, shown or enabled
-- for them, and nothing here runs until the player asks to share or another player offers.
--
-- Conversation (addressed control messages on setup sharing's prefix, so its routing, throttling, switches and name
-- rules apply; the types are its own, so a TwichUI that doesn't know them ignores them):
--   you    -> them : remoffer   the reminder's name and how big it is (their question and progress bar)
--   them   -> you  : remreply   accepted? or why not
--   you    -> them : remdata    the reminder, as RM.Export made it
--   them   -> you  : remdone    stored, or why it was refused
-- Several can be going at once (a send to your group is one offer per member). Each transfer is answered by the player it
-- was addressed to and by nobody else. Routing is the player's Sending options (R.Share.Route), never switched on its own.
-- Receiving is behind the same switches as setups (setupSharing, acceptSetups) and the reminders switch; the player is
-- always asked, and what is received goes through RM.Admit (Config.lua), the only door.
-- docs/reminders.md, "Sharing a reminder".

local R = TwichUI
local RM = R.Reminders
local SH = R.Share
local AceComm = LibStub("AceComm-3.0")

local RS = {}
R.ReminderShare = RS

local PROTOCOL = SH.PROTOCOL
local OFFER_TIMEOUT = 120      -- seconds to wait for the other player to answer
local DATA_TIMEOUT = 60        -- seconds without progress before a transfer is called off
local MAX_WIRE = 16384         -- the most one reminder message may be (a real one is a few hundred bytes to a few KB)
local MAX_GROUP = 10           -- the most players one "everyone in my group" send offers to
local KEEP_FINISHED = 60       -- seconds a finished transfer stays in the list (the progress card hides it sooner)
local MAX_KEPT = 40            -- finished or not, the most outgoing transfers held

RS.GROUP = "group"             -- the "who" that means every other player in your party or raid
RS.MAX_GROUP = MAX_GROUP
RS.out = {}                    -- outgoing, in the order they began: { id, target, name, stage, sent, total, route, started, last, reason }
RS.inc = {}                    -- incoming, one per sender: { id, name, stage, got, expected, route, started, last, reason, newId }

-- out: offered -> sending -> delivered -> done | declined | failed
-- inc: asking -> waiting -> receiving -> done | declined | failed
local TERMINAL = { done = true, declined = true, failed = true }
RS.TERMINAL = TERMINAL

local listeners, arrivals = {}, {}
function RS:OnChange(fn) listeners[#listeners + 1] = fn end
function RS:OnArrived(fn) arrivals[#arrivals + 1] = fn end
local function Changed() for _, fn in ipairs(listeners) do pcall(fn) end end

-- For /tui diagnostics while it is tracing: a code, never a name or a reminder.
local function Trace(code, detail, who)
    local D = R.Diag
    if D and D.Tracing() then D.Trace("share", "reminder-" .. code, detail, who) end
end

local function Short(name) return SH.Short(name) end
RS.Short = Short

local seq = math.random(0, 9999)
local function NewId()
    seq = (seq + 1) % 10000
    return ("%d%04d"):format(time(), seq)
end

local function RouteFromArrival(dist, sender)
    if dist == "WHISPER" then return { "WHISPER", sender } end
    return { dist }
end

-- One control message to one player. callback(accepted) is told whether the game took each piece (it says nothing
-- of whether anyone received it).
local function SendMsg(target, msg, prio, route, callback)
    msg.to = SH.FullName(target)
    local text = SH.EncodeControl(msg)
    AceComm:SendCommMessage(SH.PREFIX, text, route[1], route[2], prio or "NORMAL", callback)
end

---------------------------------------------------------------------------
-- The watchdog: one ticker while anything is in progress, gone when nothing is
---------------------------------------------------------------------------
local ticker
local Respond

local function Active()
    for _, o in ipairs(RS.out) do if not TERMINAL[o.stage] then return true end end
    for _, inc in pairs(RS.inc) do if not TERMINAL[inc.stage] then return true end end
    return false
end

local function Prune()
    local now = GetTime()
    local kept = {}
    for _, o in ipairs(RS.out) do
        if not TERMINAL[o.stage] or now - (o.ended or now) < KEEP_FINISHED then kept[#kept + 1] = o end
    end
    while #kept > MAX_KEPT do table.remove(kept, 1) end
    RS.out = kept
    for sender, inc in pairs(RS.inc) do
        if TERMINAL[inc.stage] and now - (inc.ended or now) >= KEEP_FINISHED then RS.inc[sender] = nil end
    end
end

local function Fail(o, reason, code)
    o.stage, o.reason, o.code, o.ended, o.text = "failed", reason, code, GetTime(), nil
    Trace("failed", code, o.target or o.sender)
end

local function Tick()
    local now = GetTime()
    local changed = false
    for _, o in ipairs(RS.out) do
        local idle = now - (o.last or o.started)
        if o.stage == "offered" and now - o.started > OFFER_TIMEOUT then
            Fail(o, ("No answer from %s. They may be offline, may not run a TwichUI that receives reminders, or may not have answered yet."):format(Short(o.target)), "offer-no-answer")
            changed = true
        elseif o.stage == "sending" and idle > DATA_TIMEOUT then
            Fail(o, "The transfer stalled. Try again.", "stalled")
            changed = true
        elseif o.stage == "delivered" and idle > DATA_TIMEOUT then
            Fail(o, ("Everything was sent, but %s never confirmed it arrived. They may not have received it."):format(Short(o.target)), "no-confirmation")
            changed = true
        end
    end
    for sender, inc in pairs(RS.inc) do
        if inc.stage == "asking" and now - inc.started > OFFER_TIMEOUT then
            if StaticPopup_Hide then StaticPopup_Hide("TWICHUI_REMINDER_OFFER") end
            pcall(Respond, sender, false)
            inc.reason = "You didn't answer in time."
            changed = true
        elseif (inc.stage == "waiting" or inc.stage == "receiving") and now - (inc.last or inc.started) > DATA_TIMEOUT then
            Fail(inc, "The transfer stopped. Ask them to send it again.", "receive-stalled")
            changed = true
        end
    end
    Prune()
    if changed then Changed() end
    if not Active() and ticker then ticker:Cancel(); ticker = nil end
end

local function Ensure()
    if not ticker then ticker = C_Timer.NewTicker(5, Tick) end
end

---------------------------------------------------------------------------
-- Sending (you)
---------------------------------------------------------------------------
-- The other characters in your party or raid, by full name.
function RS.GroupMembers()
    local out = {}
    if not IsInGroup() then return out end
    local me = SH.SelfName()
    local function Add(unit)
        local n = GetUnitName(unit, true)
        if n and n ~= "" and not SH.SameName(n, me) then out[#out + 1] = n end
    end
    if IsInRaid() then
        for i = 1, 40 do Add("raid" .. i) end
    else
        for i = 1, 4 do Add("party" .. i) end
    end
    return out
end

local function CheckTarget(name)
    local target = SH.FullName(name)
    if not target then return nil, "Type the player's name, or target them." end
    if target:find("#", 1, true) then return nil, "That looks like a Battle.net name. Type the character's name instead." end
    if SH.Realmless() and not target:find(" ", 1, true) then
        return nil, ("Forever needs the full name, first and last (like %s)."):format(SH.SelfName())
    end
    if SH.SameName(target, SH.SelfName()) then return nil, "That's you." end
    return target
end

local function SendData(o)
    o.stage, o.last = "sending", GetTime()
    Changed()
    AceComm:SendCommMessage(SH.PREFIX, o.text, o.route[1], o.route[2], "BULK", function(_, sent, total, accepted)
        if o.stage ~= "sending" then return end
        if accepted == false then
            Fail(o, "The game wouldn't send it. Check they are still there and try again.", "data-refused-by-game")
            Changed()
            return
        end
        o.sent, o.total, o.last = sent or o.sent, total or o.total, GetTime()
        if (o.sent or 0) >= (o.total or 1) then
            o.stage = "delivered"   -- handed to the game; their "remdone" is the confirmation
            o.text = nil
        end
        Changed()
    end)
end

-- One offer to one player. Returns the transfer, or nil and a sentence.
local function Begin(payload, target)
    local route, why = SH.Route(target)
    if not route then return nil, why end
    local o = { id = NewId(), target = target, name = payload.name, stage = "offered", sent = 0, total = 0, route = route, started = GetTime() }
    o.last = o.started
    o.text = SH.EncodeControl({ t = "remdata", id = o.id, to = SH.FullName(target), r = payload })
    if #o.text > MAX_WIRE then return nil, "That reminder is too large to send." end
    o.total = #o.text
    RS.out[#RS.out + 1] = o
    SendMsg(target, { t = "remoffer", p = PROTOCOL, id = o.id, name = payload.name, size = #o.text }, "ALERT", route, function(_, _, _, accepted)
        if accepted == false and o.stage == "offered" then
            Fail(o, "The game wouldn't send the offer. Check the name, that they are online, and your Sending options.", "offer-refused-by-game")
            Changed()
        end
    end)
    Trace("offer-sent", "route=" .. tostring(route[1]), target)
    return o
end

-- Offers reminder `id` to one player (a name), or to everyone else in your group (RS.GROUP). Returns true and a
-- sentence for the player, or false and the reason nothing was offered. The other player is asked; nothing happens to
-- their reminders unless they accept.
function RS.Send(id, who)
    if not R:Enabled("setupSharing") then return false, "Sharing is turned off. Turn it on in the sharing settings first." end
    if SH.Blocked() then return false, "Sharing is blocked here right now (instance restrictions). Try in a city." end
    local payload, why = RM.Export(id)
    if not payload then return false, why end

    local targets = {}
    if who == RS.GROUP then
        local members = RS.GroupMembers()
        if #members == 0 then return false, "You aren't in a group with anyone else." end
        if #members > MAX_GROUP then
            return false, ("Your group has %d other players; \"everyone\" is for up to %d. Send it to one player instead."):format(#members, MAX_GROUP)
        end
        targets = members
    else
        local target, bad = CheckTarget(who)
        if not target then return false, bad end
        targets[1] = target
    end

    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    Prune()
    local offered, problems, firstProblem = 0, 0, nil
    for _, target in ipairs(targets) do
        local busy
        for _, o in ipairs(RS.out) do
            if not TERMINAL[o.stage] and SH.SameName(o.target, target) then busy = true end
        end
        if busy then
            problems, firstProblem = problems + 1, firstProblem or ("Already sending to %s."):format(Short(target))
        else
            local o, bad = Begin(payload, target)
            if o then offered = offered + 1 else problems, firstProblem = problems + 1, firstProblem or bad end
        end
    end
    if offered == 0 then return false, firstProblem end
    Ensure()
    Changed()
    if who ~= RS.GROUP then return true, ("Asked %s if they want \"%s\"."):format(Short(targets[1]), payload.name) end
    local text = ("Asked %d player%s if they want \"%s\"."):format(offered, offered == 1 and "" or "s", payload.name)
    if problems > 0 then text = text .. (" %d couldn't be reached: %s"):format(problems, firstProblem) end
    return true, text
end

local function FindOut(id, sender)
    for _, o in ipairs(RS.out) do
        if o.id == id and SH.SameName(o.target, sender) then return o end
    end
end

local DECLINED = {
    off = "They've turned off receiving shared items.",
    version = "They need to update TwichUI.",
    unavailable = "They have reminders turned off.",
    full = "Their reminder list is full.",
    busy = "They were answering another offer. Try again in a moment.",
    declined = "They declined.",
}

SH.handlers.remreply = function(sender, msg)
    local o = type(msg.id) == "string" and FindOut(msg.id, sender)
    if not o or o.stage ~= "offered" then
        Trace("ignored", "reply-not-for-a-current-offer", sender)
        return
    end
    if msg.accept ~= true then
        local reason = type(msg.reason) == "string" and DECLINED[msg.reason] or DECLINED.declined
        o.stage, o.reason, o.ended, o.text = "declined", reason, GetTime(), nil
        o.code = "declined-" .. ((type(msg.reason) == "string" and DECLINED[msg.reason]) and msg.reason or "declined")
        Trace("declined", o.code, sender)
        Changed()
        return
    end
    Trace("accepted", nil, sender)
    local ok, err = pcall(SendData, o)
    if not ok then
        Fail(o, "Couldn't send it.", "send-error")
        Changed()
        R.Fault("sharing a reminder", err)
    end
end

local REFUSED = {
    full = "Their reminder list is full.",
    newer = "Their reminders were made by a newer TwichUI than theirs reads.",
    version = "They need to update TwichUI.",
    invalid = "It couldn't be used on their side, so nothing was added.",
}

SH.handlers.remdone = function(sender, msg)
    local o = type(msg.id) == "string" and FindOut(msg.id, sender)
    if not o or (o.stage ~= "sending" and o.stage ~= "delivered") then return end
    o.ended, o.text = GetTime(), nil
    if msg.ok == true then
        o.stage, o.sent = "done", o.total
        Trace("delivery-confirmed", nil, sender)
    else
        o.stage = "failed"
        o.code = "refused-by-receiver"
        o.reason = (type(msg.code) == "string" and REFUSED[msg.code]) or REFUSED.invalid
        Trace("refused-by-receiver", tostring(msg.code), sender)
    end
    Changed()
end

---------------------------------------------------------------------------
-- Receiving (them)
---------------------------------------------------------------------------
local function CanAdd()
    if not R:Enabled("reminders") then return false, "unavailable", "Reminders are turned off." end
    if not RM.Writable() then return false, "full", RM.REFUSE.newer end
    if RM.Count() >= RM.MAX then return false, "full", RM.REFUSE.full end
    return true
end

Respond = function(sender, accept)
    local inc = RS.inc[sender]
    if not inc or inc.stage ~= "asking" then return end
    if accept then
        local ok, code, why = CanAdd()
        if not ok then
            inc.stage, inc.reason, inc.ended = "declined", why, GetTime()
            SendMsg(sender, { t = "remreply", id = inc.id, accept = false, reason = code }, "ALERT", inc.route)
            R.Print("%s", why)
            Changed()
            return
        end
        inc.stage, inc.got, inc.last = "waiting", 0, GetTime()
        SendMsg(sender, { t = "remreply", id = inc.id, accept = true }, "ALERT", inc.route)
        Trace("accepted-offer", nil, sender)
    else
        inc.stage, inc.ended = "declined", GetTime()
        SendMsg(sender, { t = "remreply", id = inc.id, accept = false, reason = "declined" }, "ALERT", inc.route)
        Trace("declined-offer", nil, sender)
    end
    Changed()
end
RS.Respond = Respond

SH.handlers.remoffer = function(sender, msg, dist)
    local route = RouteFromArrival(dist, sender)
    local size = tonumber(msg.size)
    if type(msg.id) ~= "string" or #msg.id > 24 or not msg.id:match("^%w+$")
        or not size or size % 1 ~= 0 or size < 1 or size > MAX_WIRE then
        SH.lastDropped, SH.droppedCode = ("reminder offer from %s was not well formed"):format(tostring(sender)), "reminder-offer-malformed"
        Trace("ignored", SH.droppedCode, sender)
        return
    end
    local name = RM.PlainText(msg.name, RM.NAME_MAX)
    if not name then
        Trace("ignored", "reminder-offer-name", sender)
        return
    end
    local function Decline(code)
        SendMsg(sender, { t = "remreply", id = msg.id, accept = false, reason = code }, "ALERT", route)
        Trace("declined-offer", code, sender)
    end
    if not R:Enabled("acceptSetups") then return Decline("off") end
    if msg.p ~= PROTOCOL then return Decline("version") end
    local canAdd, code = CanAdd()
    if not canAdd then return Decline(code) end
    -- one question at a time: a second offer while one is open is answered "busy", not queued behind it
    for other, inc in pairs(RS.inc) do
        if not SH.SameName(other, sender) and inc.stage == "asking" then return Decline("busy") end
    end

    local inc = { id = msg.id, name = name, sender = sender, stage = "asking", got = 0, expected = size, route = route, started = GetTime() }
    inc.last = inc.started
    RS.inc[sender] = inc
    Ensure()
    Trace("offer-received", "via " .. tostring(dist), sender)
    Changed()
    local text = ("%s wants to share a reminder with you: \"%s\".\n\nAccepting only downloads it. It is added turned off and limited to this character, so nothing appears on your screen until you turn it on."):format(Short(sender), name)
    R.Interact.Confirm("TWICHUI_REMINDER_OFFER", text, function() Respond(sender, true) end,
        { accept = "Receive", cancel = "Not now", onCancel = function() Respond(sender, false) end })
end

SH.handlers.remdata = function(sender, msg)
    local inc = RS.inc[sender]
    if not inc or inc.id ~= msg.id or (inc.stage ~= "waiting" and inc.stage ~= "receiving") then
        Trace("ignored", "data-not-for-a-current-transfer", sender)
        return
    end
    inc.stage = "checking"
    local ok, added, detail = pcall(RM.Admit, msg.r)
    if not ok then
        Fail(inc, "TwichUI couldn't check what arrived.", "admit-error")
        SendMsg(sender, { t = "remdone", id = inc.id, ok = false, code = "invalid" }, "ALERT", inc.route)
        Changed()
        R.Fault("receiving a reminder", added)
        return
    end
    if added ~= true then
        local code = (detail == RM.REFUSE.full and "full") or (detail == RM.REFUSE.newer and "newer") or "invalid"
        Fail(inc, ("It wasn't added. %s"):format(tostring(detail)), "refused-" .. code)
        SendMsg(sender, { t = "remdone", id = inc.id, ok = false, code = code }, "ALERT", inc.route)
        Changed()
        return
    end
    inc.stage, inc.got, inc.newId, inc.ended = "done", inc.expected, detail, GetTime()
    SendMsg(sender, { t = "remdone", id = inc.id, ok = true }, "ALERT", inc.route)
    Trace("stored", nil, sender)
    Changed()
    for _, fn in ipairs(arrivals) do pcall(fn, sender, inc) end
end

-- Receive progress: the pieces of the reminder's message as they arrive, counted against the size they offered.
R:On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
    if prefix ~= SH.PREFIX then return end
    if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then return end
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    local inc = RS.inc[SH.FullName(sender)]
    if not inc or (inc.stage ~= "waiting" and inc.stage ~= "receiving") then return end
    inc.stage = "receiving"
    inc.got = math.min(inc.expected, inc.got + #text)
    inc.last = GetTime()
    if not inc.tick or GetTime() - inc.tick > 0.25 then inc.tick = GetTime(); Changed() end
end)

---------------------------------------------------------------------------
-- Ending things: sharing switched off, or the player cancelling
---------------------------------------------------------------------------
-- Brings every transfer in progress to an end (R.Share:Settle calls this when sharing or receiving is switched off;
-- incomingOnly: just the ones coming in). A waiting offer is answered "not now" so the sender is not left hanging, and
-- its question is taken down. Nothing already stored is touched.
function RS.Settle(reason, incomingOnly)
    if not incomingOnly then
        for _, o in ipairs(RS.out) do
            if not TERMINAL[o.stage] then
                o.stage, o.reason, o.ended, o.text = "failed", "Sharing was turned off.", GetTime(), nil
                o.code = reason or "settled"
            end
        end
    end
    for sender, inc in pairs(RS.inc) do
        if not TERMINAL[inc.stage] then
            if inc.stage == "asking" then pcall(Respond, sender, false) end
            if not TERMINAL[inc.stage] then
                inc.stage, inc.reason, inc.ended, inc.code = "failed", "Receiving was turned off.", GetTime(), reason or "settled"
            end
        end
    end
    if StaticPopup_Hide then StaticPopup_Hide("TWICHUI_REMINDER_OFFER") end
    Changed()
end

-- Stops offering one outgoing transfer that has not been answered yet (the progress card's close).
function RS.Cancel(o)
    if o and not TERMINAL[o.stage] then
        o.stage, o.reason, o.ended, o.text, o.code = "failed", "Cancelled.", GetTime(), nil, "cancelled"
        Changed()
    end
end

-- What is held, for /tui perf (read only).
function RS.Count()
    local n = #RS.out
    for _ in pairs(RS.inc) do n = n + 1 end
    return n
end
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("reminders.shareTransfers", { label = "Reminder sharing (transfers held: those in progress and the ones just finished)", unit = "count", kind = "state", read = RS.Count })
end
