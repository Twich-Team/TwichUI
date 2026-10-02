-- TwichUI: addon-message communication test.
-- TEMPORARY. Remove once Blizzard's addon messages are confirmed working on
-- WoW: Forever. To remove: delete this file, its line in the .toc, the
-- "commtest" row in Core.lua's command table, SH.DIAG_TYPES in Share.lua and
-- the isDiag lines in OnControl.
--
-- /tui commtest party | guild | whisper <Name-Realm>
-- Sends one tiny message (a random id, nothing else) over TwichUI's real
-- addon prefix and waits for another TwichUI client to answer. Never uses
-- ordinary chat, never retries, never touches saved variables.

local R = TwichUI
local SH = R.Share
local CT = {}
R.CommTest = CT

local TIMEOUT = 10
local pending   -- { id, dist, target, sentAt, acks = { [name] = ms } }

local function Say(fmt, ...) R.Print("commtest: " .. fmt, ...) end

local function PrefixRegistered()
    local ci = C_ChatInfo
    if ci and ci.IsAddonMessagePrefixRegistered then
        local ok, reg = pcall(ci.IsAddonMessagePrefixRegistered, SH.PREFIX)
        if ok then return reg and true or false end
    end
    return true   -- no way to ask; AceComm registers it at load
end

local function Finish(id)
    if not pending or pending.id ~= id then return end
    local p = pending
    pending = nil
    local names = {}
    for n in pairs(p.acks) do names[#names + 1] = SH.Short(n) end
    if #names > 0 then return end   -- already reported on first ack
    Say("%sINCONCLUSIVE|r. The client accepted the %s message, but no TwichUI peer answered within %ds. Another TwichUI user must be online %s to get a conclusive result.",
        R.GOLD, p.label, TIMEOUT, p.need)
end

function CT.Run(arg)
    local kind, who = (arg or ""):match("^(%S*)%s*(.-)%s*$")
    kind = kind:lower()
    if kind ~= "party" and kind ~= "guild" and kind ~= "whisper" then
        Say("usage: /tui commtest party | guild | whisper <Name-Realm>")
        return
    end
    if pending then Say("a test is already running; wait for it to finish.") return end
    if SH.Blocked() then Say("not attempted: addon messages are locked right now (encounter, Mythic+ or PvP).") return end
    if not PrefixRegistered() then Say("not attempted: the %s prefix isn't registered.", SH.PREFIX) return end

    local route, target, need, label
    if kind == "party" then
        if not IsInGroup() then Say("not attempted: you're not in a party or raid.") return end
        route, target, need, label = { SH.GroupDist() }, "*", "in your group", SH.GroupDist()
    elseif kind == "guild" then
        if not IsInGuild() then Say("not attempted: you're not in a guild.") return end
        route, target, need, label = { "GUILD" }, "*", "and in your guild", "GUILD"
    else
        if who == "" then Say("not attempted: whisper needs a name, e.g. /tui commtest whisper Name-Realm") return end
        route, target, need, label = { "WHISPER", who }, who, "(the named player)", "WHISPER"
    end

    local id = SH.NewId()
    pending = { id = id, label = label, need = need, sentAt = GetTime(), acks = {} }
    local ok, err = pcall(SH.SendControl, target, { t = "commtest", id = id }, "ALERT", route)
    if not ok then
        pending = nil
        Say("not attempted: the send failed (%s).", tostring(err))
        return
    end
    Say("sent a %s probe (%s). Waiting up to %ds for a TwichUI peer to answer...", label, id, TIMEOUT)
    C_Timer.After(TIMEOUT, function() Finish(id) end)
end

-- A peer asked: answer on the route the probe arrived on. Carries only the id.
SH.handlers.commtest = function(sender, msg, dist)
    if type(msg.id) ~= "string" or #msg.id > 24 then return end
    local route = (dist == "WHISPER") and { "WHISPER", sender } or { dist }
    if dist == "LOOP" then return end
    SH.SendControl(sender, { t = "commtestack", id = msg.id }, "ALERT", route)
end

SH.handlers.commtestack = function(sender, msg, dist)
    local p = pending
    if not p or p.id ~= msg.id then return end
    local first = next(p.acks) == nil
    p.acks[sender] = math.floor((GetTime() - p.sentAt) * 1000)
    if first then
        Say("%sSUCCESS|r. %s answered over %s in about %d ms. Addon messages work on this path.",
            R.GREEN, SH.Short(sender), tostring(dist), p.acks[sender])
        -- state is cleared by the timeout; later acks from other peers are just recorded
    end
end
