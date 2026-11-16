-- Exercise the actual diagnostic fixture + observer over a tiny synthetic world.
-- Native diagnose.sh covers the real addon/transport; this isolates membership,
-- zero-send and unexpected-traffic checks without loading Blizzard UI.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a"); f:close(); return text
end
-- Trusted repository CODE, concatenated exactly as diagnose.sh does; no saved
-- variables, messages or other untrusted data is ever evaluated.
local source = Read(REPO .. "tools/simlab/scenarios/lib.lua") .. "\n"
    .. Read(REPO .. "tools/simlab/scenarios/group_timers.lua") .. "\nreturn Lab\n"
local packet = "1:p:1700000000:1:2248:5000:5000"
local cases = 0
local function Run(mode, opts)
    opts = opts or {}
    local world = { guild = true, session = true, party = 4, clock = 0, physical = {}, events = {}, output = {} }
    local c = setmetatable({}, { __index = _G })
    c._G = c
    c.SIMLAB_PARAMS = { mode = mode, window = mode == "guildsolo" and 21 or 12 }
    c.A_Print = function(line) world.output[#world.output + 1] = line end
    c.GetTime = function() return world.clock end
    c.IsInGuild = function() return world.guild end
    c.GetGuildInfo = function() return "Synthetic guild" end
    c.IsInGroup = function() return world.party > 0 end
    c.IsInRaid = function() return false end
    c.GetNumGroupMembers = function() return world.party > 0 and world.party + 1 or 0 end
    c.UnitExists = function(unit) return tonumber(unit:match("^party(%d)$") or "99") <= world.party end
    c.TwichUI = {
        Enabled = function() return true end,
        Group = { peers = {}, Members = function()
            local members = {}; for i = 1, world.party do members[i] = i end; return members
        end },
        GuildLoc = {
            State = function() return opts.disabled and "off" or "sharing" end,
            Snapshot = function() return { session = world.session and not opts.disabled } end,
            -- A small read stub; protocol validation itself is covered by the
            -- real GuildLoc.Parse unit tests and native diagnostic launch.
            Parse = function(text)
                local e, n, map, x, y = text:match("^1:p:(%d+):(%d+):(%d+):(%d+):(%d+)$")
                if e then return "p", tonumber(e), tonumber(n), tonumber(map), tonumber(x), tonumber(y) end
            end,
        },
    }
    c.C_Map = {
        GetBestMapForUnit = function(unit) assert(unit == "player"); return 2248 end,
        GetPlayerMapPosition = function() return { GetXY = function() return .5, .5 end } end,
    }
    c.C_ChatInfo = { SendAddonMessage = function(prefix, text, channel, target)
        world.physical[#world.physical + 1] = { prefix = prefix, text = text, channel = channel, target = target }
        if opts.refused then error("synthetic transport refusal") end
    end }
    c.A_Admin = {
        SetPartySize = function(n) world.party = n end,
        SetManualClock = function() end,
        FireEvent = function(event, unit)
            assert(event == "PLAYER_GUILD_UPDATE" and unit == "player")
            world.events[#world.events + 1] = event
            if not opts.staleSession then world.session = c.IsInGuild() end
        end,
        AdvanceTime = function(seconds)
            world.clock = world.clock + seconds
            if world.clock >= 7.5 and not world.fired then
                world.fired = true
                if not opts.missing and (opts.force or (c.IsInGuild() and world.session and not opts.disabled)) then
                    for _ = 1, opts.duplicate and 2 or 1 do
                        -- Like the engine, a timer error does not end the clock.
                        pcall(c.C_ChatInfo.SendAddonMessage, opts.prefix or "TwichUIGuild", opts.packet or packet,
                            opts.channel or "GUILD", opts.target)
                    end
                end
            end
        end,
    }
    local chunk = assert(loadstring(source, "@diagnostics-fixture"))
    setfenv(chunk, c)
    return chunk(), world
end
local function Check(ok, message) cases = cases + 1; assert(ok, message) end

local solo, s = Run("solo")
Check(solo.failed == 0 and #solo.sends == 0 and #s.physical == 0, "unguilded solo keeps the strict zero-message assertion")
Check(#s.events == 1 and not s.session, "the actual fixture must deliver the guild departure and cancel its session")
local guild, g = Run("guildsolo")
Check(guild.failed == 0 and #guild.sends == 1 and #g.physical == 1, "guilded solo observes AND passes the real transport call through")
Check(g.physical[1].channel == "GUILD" and #g.events == 0, "guilded solo does not fake a departure or suppress sharing")
for _, bad in ipairs({
    { force = true }, -- even a valid guild packet must fail the unguilded zero-send case
    { force = true, prefix = "TwichUISetup", channel = "PARTY" },
    { staleSession = true },
    { disabled = true },
}) do
    local result = Run("solo", bad)
    Check(result.failed > 0, "solo failure detector did not notice an invalid fixture/extra send")
end
for _, bad in ipairs({
    { missing = true }, { duplicate = true }, { disabled = true },
    { prefix = "TwichUISetup" }, { prefix = "OtherAddon" }, { channel = "PARTY" }, { channel = "WHISPER" },
    { target = "OtherPlayer" }, { packet = "invalid payload" },
    { packet = "1:p:1700000000:1:1429:5000:5000" }, -- another map
    { packet = "1:p:1700000000:1:2248:1000:5000" }, -- another position
    { refused = true },
}) do
    local result, world = Run("guildsolo", bad)
    Check(result.failed > 0, "guilded solo failure detector did not notice invalid/missing/extra traffic")
    if not bad.missing and not bad.disabled then
        Check(#world.physical > 0, "the observer hid a send instead of checking it")
    end
end
print("PASSED: " .. cases .. " diagnostic isolation and failure-propagation checks")
