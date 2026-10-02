-- TwichUI: group awareness
--   * Version check: when you're grouped, TwichUI says hello with its version
--     number (a few bytes, group channel only) and tells you when someone has
--     a newer version, or one too old to share configurations with you.
--   * Group check: /twichui check (or Party compatibility check in /tui share) asks everyone in your
--     group which TwichUI they run and which of your recommended addons
--     they're missing.
--   * Direct-message probe: on Forever, addon whispers to first-and-last names
--     are currently dropped. Once per game build, TwichUI whispers one tiny
--     test message to a grouped TwichUI user; if it arrives, sharing switches
--     back to direct messages automatically.
-- All of it is off until the player turns on "Version and group check".

local R = TwichUI
local ST, SH = R.Setups, R.Share
local G = {}
R.Group = G

G.peers = {}          -- [name] = { v = "3.0.0", p = protocol, seen = time }
G.check = nil         -- { id, started, results = { [name] = reply } }
local warned = {}     -- [name] = true once we've told the player about them
local listeners = {}
function G:OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed() for _, fn in ipairs(listeners) do pcall(fn) end end

local function Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = get and get(R.ADDON, "Version") or "0"
    if v:find("^@") then v = "0-dev" end
    return v
end
G.Version = Version

-- "3.0.1" > "3.0.0"; anything that doesn't parse compares as equal.
local function Parse(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.?(%d*)%.?(%d*)")
    if not a then return nil end
    return { tonumber(a), tonumber(b) or 0, tonumber(c) or 0 }
end
function G.Compare(x, y)
    local a, b = Parse(x), Parse(y)
    if not a or not b then return 0 end
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] > b[i] and 1 or -1 end
    end
    return 0
end

local function Enabled() return R:Enabled("groupCheck") end

local function Members()
    local out = {}
    if not IsInGroup() then return out end
    if IsInRaid() then
        for i = 1, 40 do
            local n = GetUnitName("raid" .. i, true)
            if n and not SH.SameName(n, SH.SelfName()) then out[#out + 1] = SH.FullName(n) end
        end
    else
        for i = 1, 4 do
            local n = GetUnitName("party" .. i, true)
            if n then out[#out + 1] = SH.FullName(n) end
        end
    end
    return out
end
G.Members = Members

local function Broadcast(msg, prio)
    if not Enabled() or not IsInGroup() or SH.Blocked() then return false end
    SH.SendControl("*", msg, prio or "NORMAL", { SH.GroupDist() })
    return true
end

---------------------------------------------------------------------------
-- Version hello
---------------------------------------------------------------------------
local lastHello = -math.huge
function G:SayHello(isReply)
    if GetTime() - lastHello < (isReply and 10 or 3) then return end
    lastHello = GetTime()
    Broadcast({ t = "hello", v = Version(), p = SH.PROTOCOL, r = isReply or nil })
end

local function Note(name, v, p)
    G.peers[name] = { v = v, p = p, seen = time() }
    if warned[name] then return end
    local who = SH.Short(name)
    if G.Compare(v, Version()) > 0 then
        warned[name] = true
        R.Print("%s has a newer TwichUI (%s). You have %s; update when you can.", who, v, Version())
    elseif (tonumber(p) or 0) < SH.PROTOCOL then
        warned[name] = true
        R.Print("%s has an older TwichUI (%s). Sharing configurations with them needs version %s or newer on their side.",
            who, tostring(v), Version())
    end
end

SH.handlers.hello = function(sender, msg)
    if type(msg.v) ~= "string" then return end
    local known = G.peers[sender]
    Note(sender, msg.v, msg.p)
    -- Answer newcomers once so they learn about us too (rate-limited).
    if not known and not msg.r then C_Timer.After(1 + math.random() * 2, function() G:SayHello(true) end) end
    Changed()
    G:MaybeProbe()
end

---------------------------------------------------------------------------
-- Group check
---------------------------------------------------------------------------
local CHECK_WAIT = 6

function G:RunCheck(quiet)
    if not Enabled() then
        R.Print("group check is off. Turn it on in /tui options or under Party compatibility check in /tui share; your friends need it on too.")
        return false
    end
    if not IsInGroup() then
        R.Print("you're not in a group.")
        return false
    end
    if SH.Blocked() then
        R.Print("the game is blocking addon messages here right now. Try again outside the instance.")
        return false
    end
    local rec = {}
    for key, e in pairs(ST:BuildAddonList()) do rec[key] = e.folders end
    local id = SH.NewId()
    G.check = { id = id, started = GetTime(), results = {}, rec = ST:BuildAddonList(), members = Members(), done = false }
    Broadcast({ t = "checkreq", id = id, rec = rec }, "ALERT")
    Changed()
    C_Timer.After(CHECK_WAIT, function()
        if G.check and G.check.id == id then
            G.check.done = true
            Changed()
            if not quiet then G:PrintCheck() end
        end
    end)
    return true
end

SH.handlers.checkreq = function(sender, msg)
    if type(msg.rec) ~= "table" then return end
    local missing = {}
    for key, folders in pairs(msg.rec) do
        if type(key) == "string" and type(folders) == "table" then
            local state = ST.AddonInstallState({ folders = folders })
            if state ~= "installed" then missing[#missing + 1] = key end
        end
    end
    SH.SendControl(sender, { t = "checkrep", id = msg.id, v = Version(), p = SH.PROTOCOL, missing = missing },
        "NORMAL", { SH.GroupDist() })
end

SH.handlers.checkrep = function(sender, msg)
    local c = G.check
    if not c or c.id ~= msg.id then return end
    c.results[sender] = { v = tostring(msg.v or "?"), p = msg.p, missing = type(msg.missing) == "table" and msg.missing or {} }
    Note(sender, tostring(msg.v or "?"), msg.p)
    Changed()
end

-- Rows for the Group tab / chat: every group member, with what we know.
function G:CheckRows()
    local c = G.check
    local rows = {}
    for _, name in ipairs(c and c.members or Members()) do
        local res = c and c.results[name]
        local row = { name = name, short = SH.Short(name) }
        if res then
            row.version = res.v
            local cmp = G.Compare(res.v, Version())
            row.state = (tonumber(res.p) or 0) < SH.PROTOCOL and "old" or (cmp < 0 and "behind") or (cmp > 0 and "ahead") or "ok"
            row.missing = {}
            for _, key in ipairs(res.missing) do
                local e = c.rec[key]
                row.missing[#row.missing + 1] = e and e.title or key
            end
            table.sort(row.missing)
        elseif c and not c.done then
            row.state = "waiting"
        else
            row.state = "none"
        end
        rows[#rows + 1] = row
    end
    return rows
end

function G:PrintCheck()
    local rows = G:CheckRows()
    if #rows == 0 then R.Print("nobody else is in your group.") return end
    R.Print("group check:")
    for _, r in ipairs(rows) do
        local line
        if r.state == "none" then line = "no TwichUI (or group check turned off)"
        elseif r.state == "waiting" then line = "waiting..."
        else
            line = ("TwichUI %s%s"):format(r.version,
                (r.state == "old" and " (too old to share with)") or (r.state == "behind" and " (older than yours)")
                or (r.state == "ahead" and " (newer than yours)") or "")
            if #r.missing > 0 then
                line = line .. (", missing %d: %s"):format(#r.missing, table.concat(r.missing, ", "))
            else
                line = line .. ", has all your recommended addons"
            end
        end
        print(("  %s%s|r: %s"):format(R.GOLD, r.short, line))
    end
end

---------------------------------------------------------------------------
-- Direct-message probe (Forever)
---------------------------------------------------------------------------
local function Build() return select(2, GetBuildInfo()) or "?" end

function SH.WhisperWorks()
    local p = TwichUIDB and TwichUIDB.whisperProbe
    return p and p.ok and p.build == Build() or false
end

function G.WhisperStatus()
    if not SH.Realmless() then return "Direct messages work normally here." end
    local p = TwichUIDB and TwichUIDB.whisperProbe
    if p and p.build == Build() then
        return p.ok and "Direct messages work again on this game build; TwichUI uses them first."
            or ("Still not working on this game build (checked %s)."):format(date("%b %d", p.at or 0))
    end
    return "Not checked on this game build yet. TwichUI tests once when you're grouped with another TwichUI user."
end

local probing
function G:MaybeProbe()
    if probing or not Enabled() or not SH.Realmless() or not R:Enabled("shareWhisper") then return end
    local p = TwichUIDB.whisperProbe
    if p and p.build == Build() then return end
    -- pick a grouped TwichUI user
    local target
    for _, name in ipairs(Members()) do
        if G.peers[name] then target = name break end
    end
    if not target or SH.Blocked() then return end
    probing = { n = SH.NewId(), to = target }
    local AceComm = LibStub("AceComm-3.0")
    local LibSerialize = LibStub("LibSerialize")
    local LibDeflate = LibStub("LibDeflate")
    local msg = { t = "probe", n = probing.n, to = SH.FullName(target) }
    local text = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(LibSerialize:Serialize(msg)))
    AceComm:SendCommMessage(SH.PREFIX, text, "WHISPER", target, "ALERT")
    local n = probing.n
    C_Timer.After(20, function()
        if probing and probing.n == n then
            TwichUIDB.whisperProbe = { build = Build(), ok = false, at = time() }
            probing = nil
            Changed()
        end
    end)
end

SH.handlers.probe = function(sender, msg)
    if not IsInGroup() then return end
    SH.SendControl(sender, { t = "probeack", n = msg.n }, "ALERT", { SH.GroupDist() })
end

SH.handlers.probeack = function(sender, msg)
    if not probing or probing.n ~= msg.n then return end
    probing = nil
    local was = SH.WhisperWorks()
    TwichUIDB.whisperProbe = { build = Build(), ok = true, at = time() }
    if not was then
        R.Print("direct addon messages work again on Forever. Configuration sharing now uses them first; group and guild channels are only a fallback.")
    end
    Changed()
end

---------------------------------------------------------------------------
-- Triggers
---------------------------------------------------------------------------
local rosterSize = 0
local pending
R:On("GROUP_ROSTER_UPDATE", function()
    local n = GetNumGroupMembers() or 0
    if n > rosterSize and n > 1 and not pending then
        pending = true
        C_Timer.After(3, function() pending = nil; G:SayHello() end)
    end
    if n <= 1 then wipe(G.peers); wipe(warned) end
    rosterSize = n
    Changed()
end)

R:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    rosterSize = GetNumGroupMembers() or 0
    if (isLogin or isReload) and IsInGroup() then
        C_Timer.After(6, function() G:SayHello() end)
    end
end)
