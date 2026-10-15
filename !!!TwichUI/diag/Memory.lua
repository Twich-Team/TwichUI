-- TwichUI: troubleshooting report, memory
-- What the game counts toward TwichUI, how much of the settings window has been made this session, and the
-- saved data the game loaded for TwichUI at login, by part, as numbers of stored values. Read only when the
-- report is built or /tui diagnostics memory is typed: no events, timers or hooks, nothing kept but the last
-- reading of the game's count. Counts, and in chat the names of other addons' stored tables; no character
-- names, no contents. docs/memory.md has the cost map and the measuring steps for the game.

local R = TwichUI
local D = R.Diag
local M = {}
R.DiagMemory = M

M.READ_EVERY = 15                       -- seconds between reads of the game's count (the call is costly; Blizzard's addon list waits as long)
local MAX_DEPTH, MAX_VISITS = 64, 2000000   -- bounds on one count, whatever the data holds
local COMPANION = "TwichUI_Settings"
local TOP = 5                           -- largest stored tables named by the chat command

local lastRead, lastMain, lastSettings

-- The game's count in KB for TwichUI and its settings window, and how many seconds ago it was read. Read again
-- only after READ_EVERY seconds, unless fresh. nil when the game gives no count.
function M.GameCount(fresh)
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return nil end
    local now = GetTime()
    if fresh or not lastRead or now - lastRead >= M.READ_EVERY then
        if not pcall(UpdateAddOnMemoryUsage) then return nil end
        local ok1, main = pcall(GetAddOnMemoryUsage, R.ADDON)
        local ok2, settings = pcall(GetAddOnMemoryUsage, COMPANION)
        lastMain = ok1 and type(main) == "number" and main or nil
        lastSettings = ok2 and type(settings) == "number" and settings or nil
        lastRead = now
    end
    return lastMain, lastSettings, now - lastRead
end

-- Stored values in t: every key of every table in it, without a list of tables seen (saved data holds no
-- shared tables, and the bounds stop anything else). capped: the count stopped at a bound.
local visits
local function Walk(t, depth)
    local n = 0
    for _, v in next, t do
        n = n + 1
        visits = visits + 1
        if visits > MAX_VISITS then return n end
        if type(v) == "table" and depth < MAX_DEPTH then n = n + Walk(v, depth + 1) end
    end
    return n
end
function M.Values(t)
    if type(t) ~= "table" then return 0, false end
    visits = 0
    local n = Walk(t, 1)
    return n, visits > MAX_VISITS
end

local function Count(t)
    local n = 0
    if type(t) == "table" then for _ in next, t do n = n + 1 end end
    return n
end

-- The saved data the game loaded for TwichUI, by part: { key, label, values, items, largest, capped }.
-- items: backups, setups or copies in the part (nil where that means nothing).
function M.Saved()
    local parts, capped = {}, false
    local function Add(key, label, t, items, largest)
        local n, c = M.Values(t)
        capped = capped or c
        parts[#parts + 1] = { key = key, label = label, values = n, items = items, largest = largest }
        return n
    end
    local main = type(TwichUIDB) == "table" and TwichUIDB or nil
    local setup = main and type(main.setup) == "table" and main.setup or nil
    local received = setup and type(setup.received) == "table" and setup.received or nil
    local all, c = M.Values(main)
    capped = capped or c
    local inReceived = M.Values(received)
    parts[#parts + 1] = { key = "settings", label = "settings, profiles, map pins and sharing lists (TwichUIDB)", values = all - inReceived }
    Add("received", "setups friends sent you", received, Count(received))
    Add("chronicle", "Journey Chronicle (TwichUIChronicleDB)", TwichUIChronicleDB)
    local points = type(TwichUIRestoreDB) == "table" and type(TwichUIRestoreDB.points) == "table" and TwichUIRestoreDB.points or nil
    local largest = 0
    for _, p in ipairs(points or {}) do largest = math.max(largest, (M.Values(p))) end
    Add("backups", "backups (TwichUIRestoreDB)", TwichUIRestoreDB, points and #points or 0, largest)
    Add("mine", "your shareable setup (TwichUIShareDB)", TwichUIShareDB)
    Add("undo", "Undo copies (TwichUIBackupDB)", TwichUIBackupDB, Count(TwichUIBackupDB))
    local total = 0
    for _, p in ipairs(parts) do total = total + p.values end
    return parts, total, capped
end

-- The largest other addons' tables kept in backups, setups and Undo copies: { { name, where, values } }, at most n.
function M.Largest(n)
    local list = {}
    local function From(tables, where)
        if type(tables) ~= "table" then return end
        for name, e in next, tables do
            if type(name) == "string" and type(e) == "table" then
                local data = type(e.data) == "table" and e.data or e   -- the addon's table, without TwichUI's note of its owner
                list[#list + 1] = { name = name:find("^[%w_]+$") and name or "(a table)", where = where, values = (M.Values(data)) }
            end
        end
    end
    local pack = type(TwichUIShareDB) == "table" and TwichUIShareDB.pack
    if type(pack) == "table" then From(pack.tables, "your setup") end
    local points = type(TwichUIRestoreDB) == "table" and TwichUIRestoreDB.points
    for _, p in ipairs(type(points) == "table" and points or {}) do
        if type(p) == "table" then From(p.tables, "a backup") end
    end
    local setup = type(TwichUIDB) == "table" and TwichUIDB.setup
    if type(setup) == "table" and type(setup.received) == "table" then
        for _, r in next, setup.received do if type(r) == "table" then From(r.tables, "a received setup") end end
    end
    if type(TwichUIBackupDB) == "table" then
        for _, b in next, TwichUIBackupDB do if type(b) == "table" then From(b.tables, "an Undo copy") end end
    end
    table.sort(list, function(a, b) return a.values > b.values end)
    for i = #list, (n or TOP) + 1, -1 do list[i] = nil end
    return list
end

local function Thousands(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
M.Thousands = Thousands

local function SettingsLine()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(COMPANION)
    local UI = R.SettingsUI
    if not loaded or not UI then return "settings window: not loaded this session (nothing of it is in memory)" end
    local s = UI.Stats and UI.Stats()
    if type(s) ~= "table" then return "settings window: loaded (it stays loaded until a reload; the game can't unload an addon)" end
    return ("settings window: loaded; %d pages described, %d drawn (kept until a reload; the game can't unload an addon); search index %s")
        :format(s.described or 0, s.drawn or 0, s.searchIndex and "made" or "not made yet")
end

local function CountLine(fresh)
    local main, settings, age = M.GameCount(fresh)
    if not main then return "the game's count: unavailable (the game gave none)" end
    return ("the game's count: %s %s KB, %s %s KB (read %ds ago)"):format(R.ADDON, Thousands(main), COMPANION,
        Thousands(settings or 0), math.floor(age or 0))
end

local LIMITS = {
    "The game's count is the Lua memory the game puts down to the addon, garbage not yet collected included; the memory the game itself keeps for frames and textures is not in it. Compare readings taken the same way, not one reading.",
    "Which addon a shared library's memory counts toward is not documented; it appears to be the addon that loaded the library first, and TwichUI loads first.",
    "Saved data is loaded at login and stays in memory all session, whatever is used. Value counts compare its parts; a value's size depends on its kind and length, so they are not kilobytes.",
}

local function Memory()
    local lines = {}
    lines[#lines + 1] = CountLine(false)
    lines[#lines + 1] = SettingsLine()
    local parts, total, capped = M.Saved()
    lines[#lines + 1] = ("saved data loaded at login: %s stored values%s"):format(Thousands(total), capped and " at least (the count stopped at its limit)" or "")
    for _, p in ipairs(parts) do
        local extra = ""
        if p.items then extra = ("; %d %s"):format(p.items, p.items == 1 and "item" or "items") end
        if p.largest and p.largest > 0 then extra = extra .. ("; the largest %s values"):format(Thousands(p.largest)) end
        lines[#lines + 1] = ("  %s: %s values%s"):format(p.label, Thousands(p.values), extra)
    end
    return { configured = nil, initialized = nil, status = "ready", lines = lines, limits = LIMITS }
end

D.Register("memory", { title = "Memory", order = 16, snapshot = Memory })

-- /tui diagnostics memory [collect]: the same, in chat, with the largest stored tables by name. collect: one full
-- garbage collection of every addon first, for readings to compare (TwichUI never collects by itself).
function M.Command(arg)
    local collect = (arg or ""):lower():find("collect", 1, true) ~= nil
    if collect then collectgarbage("collect") end
    local say = function(text) print(("  %s%s|r"):format(R.GREY, text)) end
    R.Print(collect and "memory, after one full garbage collection of every addon (as asked):"
        or "memory (/tui diagnostics memory collect reads it after a full collection, for comparisons):")
    say(CountLine(true))
    say(SettingsLine())
    local parts, total, capped = M.Saved()
    local bits = {}
    for _, p in ipairs(parts) do bits[#bits + 1] = ("%s %s"):format(p.key, Thousands(p.values)) end
    say(("saved data loaded at login: %s values%s (%s)"):format(Thousands(total), capped and " at least" or "", table.concat(bits, ", ")))
    local top = M.Largest(TOP)
    if #top > 0 then
        local names = {}
        for _, e in ipairs(top) do names[#names + 1] = ("%s in %s (%s)"):format(e.name, e.where, Thousands(e.values)) end
        say("largest addon tables kept: " .. table.concat(names, "; "))
        say("/tui share shows your setup, /tui restore your backups, /tui saved all of TwichUI's saved data.")
    end
end
