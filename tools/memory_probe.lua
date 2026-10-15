-- TwichUI: offline memory probe (Lua 5.1, outside the game). Not part of the addon or its tests.
-- Usage: lua5.1 tools/memory_probe.lua [--saved <SavedVariables\!!!TwichUI.lua>] [--class MAGE] [--no-settings] [--verbose]
--
-- Loads !!!TwichUI in its .toc order under a permissive stand-in for the game, fires ADDON_LOADED, PLAYER_LOGIN and
-- PLAYER_ENTERING_WORLD, then (unless --no-settings) loads TwichUI_Settings, opens it, visits every page, searches,
-- and repeats open/visit/close ten times. After each stage it does a full collection and prints the Lua heap.
-- Also: the garbage one search keystroke makes, and with --saved, how much heap each saved variable holds (each
-- dropped from a fresh load in turn) and the largest other addons' tables kept in backups and setups.
--
-- What the figures are: Lua 5.1 heap on this machine, after full collections. The game runs its own Lua 5.1 and
-- counts per addon, so its figures differ; compare runs of this probe with each other (before/after a change),
-- not with the game's. Frames here are plain tables, as their Lua side is in the game; the game's own memory for
-- widgets is in neither count. The stand-in answers most game calls with nothing, so features that need bags,
-- spells or a group do less here than in play: runtime figures are a floor. Per-file figures move by up to about
-- 100 KB when Lua's string table grows during that file. The saved variables file is read with an empty
-- environment and only numbers and addon table names are printed; nothing is written anywhere.
-- docs/memory.md has the cost map these figures fed, and how to measure in the game.

require("bit")

local args = { class = "MAGE" }
do
    local i = 1
    while arg[i] do
        local a = arg[i]
        if a == "--saved" then args.saved = arg[i + 1]; i = i + 1
        elseif a == "--class" then args.class = (arg[i + 1] or "MAGE"):upper(); i = i + 1
        elseif a == "--no-settings" then args.noSettings = true
        elseif a == "--verbose" then args.verbose = true
        else io.stderr:write("memory_probe: unknown argument " .. a .. "\n"); os.exit(2) end
        i = i + 1
    end
end
local REPO = (arg[0]:match("^(.*)[/\\]tools[/\\][^/\\]+$") or ".") .. "/"
local CORE, SETTINGS = REPO .. "!!!TwichUI/", REPO .. "TwichUI_Settings/"

local function KB() collectgarbage("collect"); collectgarbage("collect"); return collectgarbage("count") end
local errors, errorCount = {}, 0
local function Err(where, e)
    errorCount = errorCount + 1
    local key = where .. ": " .. tostring(e):sub(1, 160)
    errors[key] = (errors[key] or 0) + 1
end

---------------------------------------------------------------------------
-- The game's widgets: one shared metatable, so a frame costs what its own fields cost
---------------------------------------------------------------------------
local frames, framesByType, eventFrames, timers = {}, {}, {}, {}
local Widget, methods = {}, {}
local NUMBERS = { GetWidth = 100, GetHeight = 20, GetScale = 1, GetEffectiveScale = 1, GetAlpha = 1, GetFrameLevel = 1,
    GetStringWidth = 50, GetStringHeight = 12, GetLeft = 0, GetRight = 100, GetTop = 100, GetBottom = 0, GetValue = 0,
    GetNumPoints = 0, GetLineHeight = 12, GetNumLines = 1, GetVerticalScroll = 0, GetHorizontalScroll = 0,
    GetVerticalScrollRange = 0, GetNumLetters = 0, GetUnboundedStringWidth = 50, GetDuration = 0, GetProgress = 0,
    GetMaxLetters = 0, GetID = 0, GetFrameStrata = "MEDIUM" }

local function NewWidget(kind, parent)
    local w = setmetatable({ __type = kind, __parent = parent }, Widget)
    frames[#frames + 1] = w
    framesByType[kind] = (framesByType[kind] or 0) + 1
    return w
end

local function Script(self, name, ...)
    local s = rawget(self, "__s")
    if s and s[name] then local ok, e = pcall(s[name], self, ...) if not ok then Err(name, e) end end
end

local function Method(k)
    if k:find("^Create") then local kind = k:sub(7); return function(self) return NewWidget(kind, self) end end
    if NUMBERS[k] ~= nil then local v = NUMBERS[k]; return function() return v end end
    if k:find("^Get.*Texture$") then
        return function(self)
            local t = rawget(self, "__" .. k)
            if not t then t = NewWidget("Texture", self); rawset(self, "__" .. k, t) end
            return t
        end
    end
    local simple = {
        SetScript = function(self, n, fn) rawset(self, "__s", rawget(self, "__s") or {}); self.__s[n] = fn end,
        GetScript = function(self, n) local s = rawget(self, "__s"); return s and s[n] end,
        HasScript = function() return true end,
        HookScript = function(self, n, fn)
            rawset(self, "__h", rawget(self, "__h") or {})
            local h = self.__h
            h[n] = h[n] or {}
            h[n][#h[n] + 1] = fn
        end,
        RegisterEvent = function(self, e) eventFrames[e] = eventFrames[e] or {}; eventFrames[e][self] = true end,
        UnregisterEvent = function(self, e) if eventFrames[e] then eventFrames[e][self] = nil end end,
        UnregisterAllEvents = function(self) for _, set in pairs(eventFrames) do set[self] = nil end end,
        IsEventRegistered = function(self, e) return eventFrames[e] and eventFrames[e][self] or false end,
        Show = function(self) rawset(self, "__shown", true); Script(self, "OnShow") end,
        Hide = function(self) local was = rawget(self, "__shown"); rawset(self, "__shown", false); if was then Script(self, "OnHide") end end,
        SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
        IsShown = function(self) return rawget(self, "__shown") and true or false end,
        GetParent = function(self) return rawget(self, "__parent") end,
        GetObjectType = function(self) return rawget(self, "__type") end,
        IsObjectType = function(self, t) return rawget(self, "__type") == t end,
        SetText = function(self, t) rawset(self, "__text", t) end,
        GetText = function(self) return rawget(self, "__text") end,
        GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
        GetSize = function() return 100, 20 end,
        GetCenter = function() return 50, 50 end,
        GetRect = function() return 0, 0, 100, 20 end,
        GetChecked = function(self) return rawget(self, "__checked") end,
        SetChecked = function(self, v) rawset(self, "__checked", v) end,
        GetMinMaxValues = function() return 0, 1 end,
        GetName = function(self) return rawget(self, "__name") end,
    }
    simple.RegisterUnitEvent = simple.RegisterEvent
    simple.IsVisible = simple.IsShown
    simple.GetTextColor = function() return 1, 1, 1, 1 end
    simple.GetVertexColor = simple.GetTextColor
    if simple[k] then return simple[k] end
    if k == "IsForbidden" or k == "IsProtected" or k == "IsMouseOver" or k == "HasFocus" or k == "IsDragging" then return function() return false end end
    return function() return nil end
end
Widget.__index = function(_, k)
    if type(k) ~= "string" or not k:find("^[A-Z]") then return nil end
    local f = methods[k]
    if not f then f = Method(k); methods[k] = f end
    return f
end

local function Fire(event, ...)
    local list = {}
    for fr in pairs(eventFrames[event] or {}) do list[#list + 1] = fr end
    for _, fr in ipairs(list) do
        local s, h = rawget(fr, "__s"), rawget(fr, "__h")
        if s and s.OnEvent then local ok, e = pcall(s.OnEvent, fr, event, ...) if not ok then Err(event, e) end end
        for _, fn in ipairs(h and h.OnEvent or {}) do local ok, e = pcall(fn, fr, event, ...) if not ok then Err(event, e) end end
    end
end

local function FlushTimers(rounds)
    for _ = 1, rounds or 5 do
        local t = timers
        timers = {}
        for _, fn in ipairs(t) do local ok, e = pcall(fn) if not ok then Err("timer", e) end end
        if #timers == 0 then break end
    end
end

---------------------------------------------------------------------------
-- The global environment: Lua, a few game functions with plausible answers, and stand-ins for the rest
---------------------------------------------------------------------------
local env = {}
-- Optional addons and libraries stay absent (TwichUI's own libraries load from its folder).
local ABSENT = { LibStub = true, ChatThrottleLib = true, CreateColor = true, EllesmereUI = true, RXP = true, RXPFrame = true,
    Auctionator = true, SpeakStone = true, WhatsTraining = true, Attune = true, LibDBIcon = true, TomTom = true,
    TwichUI_PackFile = true, EllesmereUIDB = true, ForeverDungeonJournal = true, EUI_Bags = true }
local stubs = {}
local function Stub(name)
    if stubs[name] then return stubs[name] end
    local s = setmetatable({}, {
        __call = function() return nil end,
        __index = function(_, k) if type(k) == "string" and k:find("^[A-Z]") then return Stub(name .. "." .. k) end end,
    })
    stubs[name] = s
    return s
end
local function Lib(t, name) return setmetatable(t, { __index = function(_, k) return Stub(name .. "." .. k) end }) end

local loaded, LoadSettings = { ["!!!TwichUI"] = true }, nil
local hooks = 0
local G = {
    _VERSION = _VERSION, assert = assert, error = error, ipairs = ipairs, pairs = pairs, next = next, pcall = pcall,
    xpcall = xpcall, select = select, tonumber = tonumber, tostring = tostring, type = type, unpack = unpack,
    setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal,
    print = function() end, string = string, table = table, math = math, bit = bit, coroutine = coroutine,
    collectgarbage = function() return 0 end, newproxy = newproxy, getfenv = getfenv, setfenv = setfenv,
    strsub = string.sub, strlen = string.len, strbyte = string.byte, strchar = string.char, strfind = string.find,
    strmatch = string.match, strrep = string.rep, strlower = string.lower, strupper = string.upper, gsub = string.gsub,
    format = string.format, gmatch = string.gmatch, strrev = string.reverse,
    tinsert = table.insert, tremove = table.remove, tconcat = table.concat, sort = table.sort,
    floor = math.floor, ceil = math.ceil, abs = math.abs, max = math.max, min = math.min, sqrt = math.sqrt, random = math.random,
    date = os.date, time = os.time, GetTime = os.clock, GetServerTime = os.time,
    debugprofilestop = function() return os.clock() * 1000 end, debugstack = function() return "" end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
    strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
    strsplit = function(sep, s)
        local out = {}
        for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
        return unpack(out)
    end,
    strjoin = function(sep, ...) return table.concat({ ... }, sep) end,
    tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end,
    Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end,
    CreateFromMixins = function(...) local o = {} for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end,
    geterrorhandler = function() return function(e) Err("error handler", e) end end, seterrorhandler = function() end,
    securecall = function(f, ...) return f(...) end, securecallfunction = function(f, ...) return f(...) end,
    issecurevariable = function() return true end, InCombatLockdown = function() return false end,
    issecretvalue = function() return false end,
    hooksecurefunc = function() hooks = hooks + 1 end,
    CreateFrame = function(kind, name, parent)
        local w = NewWidget(kind or "Frame", parent)
        if name then rawset(w, "__name", name); env[name] = w end
        return w
    end,
    RunNextFrame = function(fn) timers[#timers + 1] = fn end,
    GetScreenWidth = function() return 1920 end, GetScreenHeight = function() return 1080 end,
    UnitName = function() return "Probe" end, GetRealmName = function() return "Forever" end,
    GetNormalizedRealmName = function() return "Forever" end,
    UnitClass = function() return args.class:sub(1, 1) .. args.class:sub(2):lower(), args.class, 8 end,
    UnitRace = function() return "Human", "Human", 1 end, UnitLevel = function() return 60 end,
    UnitGUID = function() return "Player-1-00000001" end, UnitFactionGroup = function() return "Alliance", "Alliance" end,
    UnitExists = function(u) return u == "player" end, UnitIsPlayer = function() return true end,
    UnitIsDeadOrGhost = function() return false end, UnitAffectingCombat = function() return false end,
    GetMoney = function() return 0 end, GetFramerate = function() return 60 end, GetLocale = function() return "enUS" end,
    GetBuildInfo = function() return "1.60.1", "70009", "Sep", 16001 end, GetCVar = function() return "0" end,
    GetCVarBool = function() return false end, IsInGroup = function() return false end, IsInRaid = function() return false end,
    IsInGuild = function() return false end, IsInInstance = function() return false, "none" end,
    GetNumGroupMembers = function() return 0 end, GetNumSubgroupMembers = function() return 0 end,
    BNGetNumFriends = function() return 0, 0 end, GetNumSkillLines = function() return 0 end,
    GetRealZoneText = function() return "Elwynn Forest" end, GetZoneText = function() return "Elwynn Forest" end,
    GetSubZoneText = function() return "" end, GetMinimapZoneText = function() return "Goldshire" end,
    GetCursorPosition = function() return 0, 0 end, PlaySoundFile = function() return true end, PlaySound = function() return true end,
    UpdateAddOnMemoryUsage = function() end, GetAddOnMemoryUsage = function() return 0 end,
    StaticPopupDialogs = {}, UISpecialFrames = {}, SlashCmdList = {}, hash_SlashCmdList = {}, ITEM_QUALITY_COLORS = {},
    RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end }),
    NUM_BAG_SLOTS = 4, BACKPACK_CONTAINER = 0, NUM_CHAT_WINDOWS = 1, STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF",
    Enum = Stub("Enum"),
}
G.C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTimer = function(_, fn)
        local t = {}
        function t:Cancel() self.cancelled = true end
        function t:IsCancelled() return self.cancelled end
        timers[#timers + 1] = function() if not t.cancelled then fn(t) end end
        return t
    end,
    NewTicker = function()
        local t = {}
        function t:Cancel() self.cancelled = true end
        function t:IsCancelled() return self.cancelled end
        return t
    end,
}
G.C_AddOns = {
    GetNumAddOns = function() return 2 end,
    GetAddOnInfo = function(i)
        local n = (i == 1 or i == "!!!TwichUI") and "!!!TwichUI" or "TwichUI_Settings"
        return n, n, "", true, "", "INSECURE"
    end,
    IsAddOnLoaded = function(n)
        n = (n == 1 and "!!!TwichUI") or (n == 2 and "TwichUI_Settings") or n
        return loaded[n] or false, loaded[n] or false
    end,
    IsAddOnLoadOnDemand = function(n) return n == "TwichUI_Settings" or n == 2 end,
    DoesAddOnExist = function(n) return n == "!!!TwichUI" or n == "TwichUI_Settings" end,
    GetAddOnMetadata = function(_, f) if f == "Version" then return "1.0.0" end end,
    GetAddOnEnableState = function() return 2 end, GetAddOnDependencies = function() end,
    LoadAddOn = function(n) if n == "TwichUI_Settings" then LoadSettings(); return true end return false, "MISSING" end,
}
G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() end,
    GetContainerItemID = function() end, GetContainerItemLink = function() end, GetContainerNumFreeSlots = function() return 0, 0 end }
G.C_Item = Lib({ GetItemInfo = function() end, GetItemCount = function() return 0 end, IsItemDataCachedByID = function() return false end }, "C_Item")
G.C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function() return true end,
    IsAddonMessagePrefixRegistered = function() return true end, InChatMessagingLockdown = function() return false end }
G.C_Map = Lib({ GetBestMapForUnit = function() return 1429 end, GetMapInfo = function(id) return { mapID = id, name = "Elwynn Forest", mapType = 3 } end }, "C_Map")
G.C_BattleNet = Lib({}, "C_BattleNet")
G.C_FriendList = Lib({ GetNumFriends = function() return 0 end, GetNumOnlineFriends = function() return 0 end }, "C_FriendList")
G.C_Spell = Lib({ IsSpellDataCached = function() return true end }, "C_Spell")
G.C_AddOnProfiler = { IsEnabled = function() return false end }

setmetatable(env, { __index = function(_, k)
    local v = G[k]
    if v ~= nil then return v end
    if type(k) ~= "string" or ABSENT[k] then return nil end
    if k:find("^SLASH_") or k:find("^BINDING_") then return nil end
    -- Blizzard frames named in UI code (UIParent, GameTooltip, Minimap, ChatFrame1, DEFAULT_CHAT_FRAME...)
    if k == "UIParent" or k == "Minimap" or k:find("Frame%d*$") or k:find("_FRAME$") or k:find("Tooltip$")
        or k:find("Button$") or k:find("Bar$") or k:find("Parent$") then
        local w = NewWidget("Blizzard", nil)
        rawset(w, "__name", k)
        rawset(env, k, w)
        return w
    end
    if k:find("^[A-Z]+_[A-Z_0-9]+$") then return k end   -- the game's global strings
    if k:find("^C_") or k:find("^[A-Z]") then return Stub(k) end
    return nil
end })
env._G = env

---------------------------------------------------------------------------
-- Loading and measuring
---------------------------------------------------------------------------
local function TocFiles(dir, toc)
    local list = {}
    for line in io.lines(dir .. toc) do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" and not line:find("^#") and line:find("%.lua$") then list[#list + 1] = (line:gsub("\\", "/")) end
    end
    return list
end

local perFile = {}
local function RunFile(dir, f, addon, ns)
    local before, made = KB(), #frames
    local chunk, err = loadfile(dir .. f)
    if not chunk then Err("compile " .. f, err) return end
    setfenv(chunk, env)
    local ok, e = pcall(chunk, addon, ns)
    if not ok then Err("load " .. f, e) end
    chunk = nil
    perFile[#perFile + 1] = { addon .. "/" .. f, KB() - before, #frames - made }
end

local stages, last = {}, nil
local function Stage(name)
    local now = KB()
    stages[#stages + 1] = { name, now, now - (last or now), #frames }
    last = now
end

Stage("stand-in for the game")
if args.saved then
    local saved = {}
    local chunk = assert(loadfile(args.saved))
    setfenv(chunk, saved)
    chunk()
    chunk = nil
    for k, v in pairs(saved) do rawset(env, k, v) end
end
Stage(args.saved and "saved variables (as the game loads them first)" or "saved variables (none: a new install)")
local coreNs = {}
for _, f in ipairs(TocFiles(CORE, "!!!TwichUI.toc")) do RunFile(CORE, f, "!!!TwichUI", coreNs) end
Stage("!!!TwichUI files run (code and what they build)")
Fire("ADDON_LOADED", "!!!TwichUI")
FlushTimers()
Stage("ADDON_LOADED (saved data checked, start-up hooks)")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)
Fire("SPELLS_CHANGED"); Fire("BAG_UPDATE_DELAYED"); Fire("ZONE_CHANGED_NEW_AREA")
FlushTimers(10)
Stage("login and entering the world")

local R = rawget(env, "TwichUI")
local churn = {}
LoadSettings = function()
    if loaded.TwichUI_Settings then return end
    loaded.TwichUI_Settings = true
    local ns = {}
    for _, f in ipairs(TocFiles(SETTINGS, "TwichUI_Settings.toc")) do RunFile(SETTINGS, f, "TwichUI_Settings", ns) end
    Fire("ADDON_LOADED", "TwichUI_Settings")
end
if not args.noSettings and R and R.OpenSettings then
    LoadSettings()
    Stage("TwichUI_Settings files run")
    local K, UI, Search = R.SettingsKit, R.SettingsUI, R.SettingsSearch
    if K and K.Describe then
        local ok, e = pcall(K.Describe)
        if not ok then Err("Describe", e) end
        local rows = 0
        for _, page in pairs(K.pages) do rows = rows + #(page.rows or {}) end
        Stage(("every page described (%d pages, %d rows; no frames)"):format(#K.list, rows))
    end
    local ok, e = pcall(R.OpenSettings, R)
    if not ok then Err("open", e) end
    FlushTimers()
    Stage("first open: the window and one page")
    local keys = {}
    for _, page in ipairs(K and K.list or {}) do keys[#keys + 1] = page.key end
    for _, key in ipairs(keys) do local ok2, e2 = pcall(R.OpenSettings, R, key) if not ok2 then Err("page " .. key, e2) end end
    FlushTimers()
    Stage(("every page drawn (%d)"):format(#keys))
    if Search and UI and UI.SetQuery then
        UI.SetQuery("sound")
        Stage("first search (the index, the result rows)")
        -- Garbage per keystroke: everything one keystroke allocates, with the collector stopped.
        for _, q in ipairs({ "notification sound", "pins", "zzz nothing" }) do
            local run, all = 0, 0
            for i = 1, #q do
                local typed = q:sub(1, i)
                collectgarbage("collect"); collectgarbage("stop")
                local a = collectgarbage("count")
                Search.Run(typed)
                local b = collectgarbage("count")
                collectgarbage("restart"); collectgarbage("collect"); collectgarbage("stop")
                local c = collectgarbage("count")
                UI.SetQuery(typed)
                local d = collectgarbage("count")
                collectgarbage("restart")
                run, all = run + (b - a), all + (d - c)
            end
            churn[#churn + 1] = ("%-20s Search.Run %5.1f KB, the whole keystroke (search and drawing) %5.1f KB"):format(("%q"):format(q), run / #q, all / #q)
        end
        UI.SetQuery("")
    end
    pcall(R.CloseSettings, R)
    FlushTimers()
    Stage("closed")
    for _ = 1, 10 do
        pcall(R.OpenSettings, R)
        for _, key in ipairs(keys) do pcall(R.OpenSettings, R, key) end
        pcall(R.CloseSettings, R)
        FlushTimers()
    end
    Stage("ten more rounds of open, every page, close")
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
print(("TwichUI memory probe: Lua heap after full collections (%s, class %s, %s)"):format(_VERSION, args.class,
    args.saved and "saved variables given" or "no saved variables"))
print(("  %-58s %9s %8s %8s"):format("stage", "heap KB", "+KB", "widgets"))
for _, s in ipairs(stages) do print(("  %-58s %9.0f %8.0f %8d"):format(s[1], s[2], s[3], s[4])) end
table.sort(perFile, function(a, b) return a[2] > b[2] end)
print("largest files (compiled code and what running the file kept):")
for i = 1, math.min(args.verbose and #perFile or 12, #perFile) do
    print(("  %-52s %7.1f KB"):format(perFile[i][1], perFile[i][2]))
end
local kinds = {}
for k, v in pairs(framesByType) do kinds[#kinds + 1] = k .. " " .. v end
table.sort(kinds)
print(("widgets made: %d (%s)"):format(#frames, table.concat(kinds, ", ")))
local events = {}
for e, set in pairs(eventFrames) do if next(set) then events[#events + 1] = e end end
table.sort(events)
print(("events registered at the end: %d%s"):format(#events, args.verbose and (": " .. table.concat(events, " ")) or ""))
local updaters = 0
for _, fr in ipairs(frames) do local s = rawget(fr, "__s") if s and s.OnUpdate then updaters = updaters + 1 end end
print(("OnUpdate scripts set at the end: %d (timers never run OnUpdate here, so a fade left running counts); hooks: %d"):format(updaters, hooks))
if #churn > 0 then
    print("garbage per search keystroke, typing each query one letter at a time:")
    for _, line in ipairs(churn) do print("  " .. line) end
end

if args.saved then
    -- Each variable's own heap: a fresh load, the variable dropped, the difference.
    print("saved variables, the heap each holds alone:")
    local function Fresh() local t = {} local chunk = assert(loadfile(args.saved)) setfenv(chunk, t) chunk() return t end
    for _, name in ipairs({ "TwichUIDB", "TwichUIChronicleDB", "TwichUIRestoreDB", "TwichUIShareDB", "TwichUIBackupDB" }) do
        local t = Fresh()
        local full = KB()
        t[name] = nil
        print(("  %-22s %8.0f KB"):format(name, full - KB()))
        t = nil
        KB()
    end
    local M = R and R.DiagMemory
    if M then
        print("largest other addons' tables kept (values):")
        for _, e in ipairs(M.Largest(8)) do print(("  %-32s in %-18s %8d"):format(e.name, e.where, e.values)) end
    end
end
local distinct = 0
for _ in pairs(errors) do distinct = distinct + 1 end
print(("stand-in errors: %d (%d distinct)%s"):format(errorCount, distinct, distinct > 0 and not args.verbose and "; --verbose lists them" or ""))
if args.verbose then for k, n in pairs(errors) do print(("  %dx %s"):format(n, k)) end end
