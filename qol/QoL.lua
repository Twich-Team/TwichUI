-- TwichUI: Quality of Life
-- A small home for opt-in conveniences. Each one lives in its own file in this folder, is off until
-- the player turns it on, and listens for its events only while it is on.
--
-- A feature is a table handed to Q.Add:
--   key     the module toggle in TwichUIDB.modules (also the name Q.Apply is called with)
--   Events  function() -> { EVENT = handler, ... }: what to listen to right now. It may read the
--           feature's other options, so Q.Apply(feature) after one changes adds or drops an event.
--   Stop    optional: called when the feature turns off, to cancel anything it still has pending.
--   guild   optional: true when the feature reads the guild roster (it is asked for once).
-- Q.Apply(feature) makes the listening match the settings. It is safe to call any time, as often as
-- you like: it registers and unregisters only what changed.
--
-- Options that aren't an on/off switch (a source, a wait) are saved in TwichUIDB.ui.qol and read
-- through Q.Get, which falls back to the default for anything that isn't one of the listed choices.
--
-- Who is a "friend", "guild member" or "group member" is judged by character name only (the realm
-- is ignored). Friends: the character friend list and the WoW characters of Battle.net friends.
-- Guild: the guild roster the game has loaded. Group: your party or raid. Anything the game can't
-- tell us (no name, a name we can't read) counts as nobody.

local R = TwichUI
local Q = {}
R.QoL = Q

Q.features = {}

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
-- Each option's choices, in the order they are listed. A saved value must be one of these.
Q.CHOICES = {
    summonsFrom = { "known", "group", "anyone" },
    summonsWait = { 0, 1, 2, 3, 5, 10 },     -- seconds
    duelsFrom = { "known", "friendsGuild", "friends", "nobody" },
    releaseWait = { 0, 1, 2, 3, 5 },         -- seconds
}
Q.DEFAULTS = { summonsFrom = "known", summonsWait = 3, duelsFrom = "known", releaseWait = 2 }

-- Who counts, for a "from" option. true: anyone, even when the game gives no name.
Q.SOURCES = {
    anyone = true,
    known = { friends = true, guild = true, group = true },
    friendsGuild = { friends = true, guild = true },
    friends = { friends = true },
    group = { group = true },
    nobody = {},
}

function Q.Get(key)
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.qol
    local value = type(saved) == "table" and saved[key] or nil
    for _, choice in ipairs(Q.CHOICES[key] or {}) do
        if choice == value then return value end
    end
    return Q.DEFAULTS[key]
end

function Q.Set(key, value)
    for _, choice in ipairs(Q.CHOICES[key] or {}) do
        if choice == value then
            TwichUIDB.ui = TwichUIDB.ui or {}
            TwichUIDB.ui.qol = TwichUIDB.ui.qol or {}
            TwichUIDB.ui.qol[key] = value
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Who is asking
---------------------------------------------------------------------------
local function Readable(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

-- "Name-Realm" or "Name" as one comparable word, or nil when there is no usable name.
function Q.Normal(name)
    name = Readable(name)
    if type(name) ~= "string" then return nil end
    local plain = name:match("^[^%-]+")
    return plain and plain:lower() or nil
end

-- The party or raid unit holding that character, or nil.
function Q.GroupUnit(name)
    local want = Q.Normal(name)
    if not want or not IsInGroup() then return nil end
    local prefix, count
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() or 0 else prefix, count = "party", 4 end
    for i = 1, count do
        local unit = prefix .. i
        if Q.Normal((UnitName(unit))) == want then return unit end
    end
    return nil
end

function Q.IsFriend(name)
    local want = Q.Normal(name)
    if not want then return false end
    local list = C_FriendList
    if list and list.GetNumFriends and list.GetFriendInfoByIndex then
        for i = 1, list.GetNumFriends() or 0 do
            local info = list.GetFriendInfoByIndex(i)
            if info and Q.Normal(info.name) == want then return true end
        end
    end
    local bnet = C_BattleNet
    if bnet and bnet.GetFriendNumGameAccounts and bnet.GetFriendGameAccountInfo and BNGetNumFriends then
        for i = 1, BNGetNumFriends() or 0 do
            for j = 1, bnet.GetFriendNumGameAccounts(i) or 0 do
                local info = bnet.GetFriendGameAccountInfo(i, j)
                if info and info.clientProgram == "WoW" and Q.Normal(info.characterName) == want then return true end
            end
        end
    end
    return false
end

-- Reads the roster the game already has; Q.RequestRoster asks for a fresh one.
function Q.IsGuildMember(name)
    local want = Q.Normal(name)
    if not want or not IsInGuild() or not GetGuildRosterInfo then return false end
    for i = 1, GetNumGuildMembers() or 0 do
        if Q.Normal((GetGuildRosterInfo(i))) == want then return true end
    end
    return false
end

local rosterAsked = false
function Q.RequestRoster()
    if rosterAsked or not IsInGuild() then return end
    rosterAsked = true
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
end

-- Under the Hardcore ruleset the game's own UI never offers a resurrection pop-up, and death is
-- final, so nothing here resurrects or releases anyone then.
function Q.Hardcore()
    return C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() and true or false
end

-- Is this character covered by the source (a key of Q.SOURCES)?
function Q.Allowed(name, source)
    local set = Q.SOURCES[source]
    if set == true then return true end
    if not set or not Q.Normal(name) then return false end
    return (set.friends and Q.IsFriend(name)) or (set.guild and Q.IsGuildMember(name))
        or (set.group and Q.GroupUnit(name) ~= nil) or false
end

---------------------------------------------------------------------------
-- Leatrix Plus does some of the same things. When it has one on, doing it twice is harmless (a
-- second accept, release or decline finds nothing left to do), but the player may want to know.
-- Leatrix saves its choices when you log out, so this reflects the start of the session. TwichUI
-- never changes anything of Leatrix's.
---------------------------------------------------------------------------
Q.LEATRIX = { qolSummons = "AutoAcceptSummon", qolResurrect = "AutoAcceptRes", qolReleasePvP = "AutoReleasePvP",
    qolDuels = "NoDuelRequests" }

function Q.LeatrixOverlap(key)
    local option = Q.LEATRIX[key]
    if not option or not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Leatrix_Plus")) then return false end
    local saved = _G.LeaPlusDB
    return type(saved) == "table" and saved[option] == "On"
end

---------------------------------------------------------------------------
-- Turning features on and off
---------------------------------------------------------------------------
function Q.Add(feature)
    feature.active = {}      -- [event] = handler, while registered
    feature.on = false
    Q.features[#Q.features + 1] = feature
    return feature
end

function Q.Apply(feature)
    local want = R:Enabled(feature.key) and feature.Events() or {}
    for event, handler in pairs(feature.active) do
        if want[event] ~= handler then
            R:Off(event, handler)
            feature.active[event] = nil
        end
    end
    for event, handler in pairs(want) do
        if feature.active[event] ~= handler then
            R:On(event, handler)
            feature.active[event] = handler
        end
    end
    local on = next(want) ~= nil
    if on and not feature.on and feature.guild then Q.RequestRoster() end
    if not on and feature.on and feature.Stop then feature.Stop() end
    feature.on = on
end

function Q.ApplyAll()
    for _, feature in ipairs(Q.features) do Q.Apply(feature) end
end

-- Features are added by the files after this one; apply them once the saved settings are in.
R:OnInit(Q.ApplyAll)
