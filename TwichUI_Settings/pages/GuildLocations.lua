-- TwichUI settings: Guild Locations (guildloc/). Privacy controls, current status and the focused diagnostic view. The choice is
-- guildloc/State.lua's alone: this page reads GL.State and changes it only through GL.SetState, which saves it and ends or
-- withdraws a session as needed. The choice has no default on this page, so "Reset this page" never touches it (only the
-- interval goes back to 15 s). Opening the page starts nothing; choosing Sharing is the only thing here that does.

local R = TwichUI
local K = R.SettingsKit

-- icon: Guild Locations' own illustration (a parchment map with pins and a pennant), media/guildloc/settings.
local NAMES = { sharing = "Sharing", invisible = "Invisible", off = "Off" }

-- Why the saved choice can't be changed or is not simply what was saved, in plain words (nil when it is).
local function Problem(why)
    if why == "held" then return "TwichUI's saved data is from a newer version and has been set aside, so this feature is inactive until that is resolved. Nothing is sent or changed." end
    if why == "not-ready" then return "TwichUI's saved data is not loaded yet. Nothing is sent." end
    if why == "bad-record" or why == "bad-state" then return "The saved choice could not be read, so Invisible is in force: nothing is sent. Choosing a state here replaces it." end
end

local function Locked()
    local _, why = R.GuildLoc.State()
    return why == "held" or why == "not-ready"
end

-- What is true right now, given the choice and the guild. Counts and states only; no names or places.
local function Now()
    local GL = R.GuildLoc
    local state, why = GL.State()
    if why == "held" or why == "not-ready" then return "Inactive", "quiet", Problem(why) end
    if state == "off" then return "Nothing sent or shown", "quiet", "Off: nothing is sent, received or kept." end
    if state == "invisible" then
        return "Not sharing your position", "quiet", "You are hidden from guildmates in this feature, and you still see those who share. Your addon may answer a guildmate's diagnostic check with a small status reply containing no coordinates." .. (why and ("\n" .. Problem(why)) or "")
    end
    if not IsInGuild() then return "Not in a guild", "quiet", "Sharing is chosen, but there is no guild to send to. Your choice is kept and applies in any guild you join." end
    local ready, reason = (GL.SendStatus or GL.CanSend)()
    if ready then return "Ready to send", "ok", "Your client can send a position now. This does not confirm a guildmate received it; use Diagnostics to test both directions." end
    local D = GL.Diagnostics
    return "Waiting", "warn", D and D.Describe(reason) or "Sharing is chosen, but nothing can be sent right now. Open Diagnostics for the reason."
end

-- A change made elsewhere (the launcher's menu) shows in an open window.
local function Redraw() K.RefreshOverview() end

K.Page({
    key = "guildLocations", icon = "guildLocations", name = "Guild Locations", order = 77, group = "map",
    description = "Share your own map position with guildmates who use TwichUI, and see theirs.",
    keywords = "guild locations location position share sharing invisible hidden privacy guildmates members map addon channel heartbeat diagnostics test missing",
    when = function() return R.GuildLoc ~= nil end,
    overview = { label = "Guild Locations", tip = "Your position for guildmates running TwichUI.", status = function()
        local state, why = R.GuildLoc.State()
        if why == "held" or why == "not-ready" then return K.OnOff(false, nil, "Inactive") end
        return K.OnOff(state == "sharing", "Sharing", NAMES[state]) end },
    build = function()
        local GL = R.GuildLoc
        local Header, Choice = K.Header, K.Choice
        GL.OnChange(Redraw)

        Header("Your location", "On by default. Your own current map position is sent over your guild's hidden addon channel (never chat) to guildmates running TwichUI, about once a minute while you stand still and more often while you move. It is not sent to anyone outside your guild, is not relayed, and is not kept as a history. Guildmates who share appear on relevant maps; your group uses the game's own markers.")
        local choice = Choice("guildLocationsState", "Guild Locations",
            "Sharing: your position is sent and guildmates' positions are shown.\nInvisible: your position is not sent, and you still see guildmates who share. Your addon may answer a guildmate's diagnostic check with a small status reply containing no coordinates.\nOff: nothing is sent, received or kept; diagnostic requests are not answered.\n\nInvisible and Off apply to this feature only. They do not change party pins, map pings or the game's own group markers. You can choose Invisible or Off while not in a guild; the choice is kept for when you join one. It belongs to this account, not to a profile, and is not part of backups or shared settings.",
            K.STRING, nil, function() return (GL.State()) end, function(value) GL.SetState(value) end,
            { { "sharing", "Sharing" }, { "invisible", "Invisible (still see others)" }, { "off", "Off" } })
        if choice then
            choice:AddModifyPredicate(function() return not Locked() end)
            choice.why = function() local _, why = GL.State(); return Problem(why) end
        end

        local interval = Choice("guildLocationsInterval", "Update interval while moving",
            "How often your position is sent while you are moving. Standing still, it is sent about once a minute whatever you choose. Shorter keeps your marker fresher on guildmates' maps and sends a few more small guild-channel messages. It never changes by itself.\n\nThis never changes whether you are sharing.",
            K.NUMBER, GL.DEFAULT_INTERVAL, function() return GL.Interval() end, function(value) GL.SetInterval(value) end,
            { { 10, "10 seconds" }, { 15, "15 seconds" }, { 30, "30 seconds" }, { 60, "60 seconds" } })
        if interval then
            interval:AddModifyPredicate(function() return not Locked() end)
            interval.why = function() local _, why = GL.State(); return Problem(why) end
        end

        Header("Right now", "What is true at the moment. Reading this page never starts sharing.")
        K.Status("Your choice", function() local state = GL.State(); return NAMES[state] or "Off" end,
            function() local _, why = GL.State(); return Problem(why) or "Saved for this account. Profiles, imports and backups do not change it, and \"Reset this page\" leaves it alone." end,
            "The choice saved on this account.",
            function() return GL.State() == "sharing" and "ok" or "quiet" end)
        K.Status("Status", function() return (Now()) end, function() local _, _, detail = Now(); return detail end,
            "Whether anything can be sent at this moment.", function() local _, tone = Now(); return tone end)
        K.Button("Diagnostics", "Open", function()
            if GL.Window then GL.Window.Show() end
        end, "Inspect a guildmate's receive and map status, run an isolated local self-test, or ask their addon to reply automatically. Opening the window sends nothing and changes no sharing choice.")
    end,
})
