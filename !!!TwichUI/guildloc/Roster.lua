-- TwichUI: Guild Locations, who is in the guild (docs/guild-locations.md)
-- A position is only believed from someone the game's own guild roster lists. This keeps an index of the roster, keyed by
-- the name form setup/Share.lua compares names in (SH.FullName, lower case), so "Name", "Name-Realm" and "First Last" agree:
-- Lookup(sender) is one table read. What an entry holds is what the roster says and nothing else: whether the member is
-- online, and (only when the game gave something usable) their level and class token. Class and level are never taken from
-- a packet. Unknown stays unknown.
--
-- Membership is all this establishes. It does not make a position true.
--
-- The index is memory only, rebuilt from GetGuildRosterInfo when the game says the roster changed (GUILD_ROSTER_UPDATE,
-- coalesced into one pass, never more often than REBUILD_GAP) and emptied when the feature goes off or the guild changes.
-- Events are listened for only between Start and Stop. A sender the roster does not list is dropped by the caller and
-- asks for one roster refresh, at most every ASK_GAP seconds; the unknown sender is not remembered.
-- Absence from the roster means unknown, never "offline" or "left". The game offers no show-offline-members call here, so a
-- member who is not listed may simply not be loaded yet.
-- Index fields come from the game's return values (online = 9th, level = 4th, class token = 11th); those positions are
-- taken from other addons' use of the call, not from Blizzard's source, so each is checked and unknown when it is not usable.

local R = TwichUI
local GL = R.GuildLoc
local SH = R.Share
local Perf = R.Perf
local RS = {}
GL.Roster = RS

RS.MAX = 3000          -- rows read at most; a guild is never this big on Forever
RS.COALESCE = 1        -- seconds between the game's notice and the pass
RS.REBUILD_GAP = 5     -- seconds between passes
RS.ASK_GAP = 10        -- seconds between requests for a refresh

local index = {}                 -- [lower full name] = { online, level?, class? }
local count, stamp, serial = 0, nil, 0
local started = false
local lastBuild, lastAsk
local listeners = {}
local stats = { passes = 0, asks = 0, truncated = 0 }

local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

function RS.Count() return count end
function RS.Serial() return serial end            -- bumps with every pass; records compare it with their own
function RS.Stamp() return stamp end              -- GetTime() of the last pass
function RS.Started() return started end

-- fn() runs after each pass.
function RS.OnRefresh(fn) listeners[#listeners + 1] = fn end

-- The entry for a sender, or nil (not in the roster, or not a usable name). Also returns the key records use.
function RS.Lookup(sender)
    if type(sender) ~= "string" or Secret(sender) then return nil end
    local full = SH.FullName(sender)
    if not full then return nil end
    local key = full:lower()
    return index[key], key, full
end

-- The entry for a record's key (what Lookup returned as its second value).
function RS.Entry(key) return index[key] end

---------------------------------------------------------------------------
-- Reading the roster
---------------------------------------------------------------------------
local function Level(v)
    if type(v) == "number" and not Secret(v) and v == v and v % 1 == 0 and v >= 1 and v <= 255 then return v end
end
local function Class(v)
    if type(v) == "string" and not Secret(v) and #v <= 20 and v:find("^%u+$") then return v end
end

local function Rebuild()
    if not started then return end
    local fresh, n = {}, 0
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    if type(total) ~= "number" or Secret(total) then total = 0 end
    if total > RS.MAX then total = RS.MAX; stats.truncated = stats.truncated + 1 end
    for i = 1, total do
        local name, _, _, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
        if type(name) == "string" and not Secret(name) then
            local full = SH.FullName(name)
            if full then
                local key = full:lower()
                if not fresh[key] then n = n + 1 end
                fresh[key] = { online = online and true or false, level = Level(level), class = Class(class) }
            end
        end
    end
    index, count = fresh, n
    stamp, serial = GetTime(), serial + 1
    lastBuild = stamp
    stats.passes = stats.passes + 1
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("guild locations", err) end
    end
end

local pass
pass = GL.NewTimer(function() Perf.Call("guildloc.roster", Rebuild) end)

-- Schedules a pass: soon, but never closer to the last one than REBUILD_GAP. Several notices make one pass.
local function Want()
    if not started or pass.Armed() then return end
    local wait = RS.COALESCE
    if lastBuild then wait = math.max(wait, RS.REBUILD_GAP - (GetTime() - lastBuild)) end
    pass.Set(wait)
end

-- Asks the game for a fresh roster (its reply is GUILD_ROSTER_UPDATE). Rate limited. Returns whether a request was made.
function RS.Request()
    if not started or not IsInGuild() then return false end
    local now = GetTime()
    if lastAsk and now - lastAsk < RS.ASK_GAP then return false end
    lastAsk = now
    stats.asks = stats.asks + 1
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    return true
end

local function OnRosterUpdate() Want() end

-- Begins listening and reads what the game already has. Calling it twice changes nothing.
function RS.Start()
    if started then return end
    started = true
    R:On("GUILD_ROSTER_UPDATE", OnRosterUpdate)
    Rebuild()
    RS.Request()
end

-- Stops listening and forgets everything.
function RS.Stop()
    R:Off("GUILD_ROSTER_UPDATE", OnRosterUpdate)
    started = false
    pass.Cancel()
    index, count, stamp, lastBuild, lastAsk = {}, 0, nil, nil, nil
end

-- A different guild (or none): the index described the old one.
function RS.Reset()
    index, count, stamp, lastBuild, lastAsk = {}, 0, nil, nil, nil
    pass.Cancel()
    if started then
        Rebuild()
        RS.Request()
    end
end

function RS.Snapshot()
    return { started = started, entries = count, passes = stats.passes, asks = stats.asks, truncated = stats.truncated,
        timers = pass.Engines() }
end
