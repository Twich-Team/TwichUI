-- TwichUI: addon data (read-only), core
-- What other addons keep between sessions, as far as the game lets an addon
-- see it. The game reads an addon's saved data from disk only when that addon
-- loads, and an addon can't read files, so only addons loaded right now can be
-- looked at. Data of addons that are off, waiting to load or removed stays on
-- disk, out of reach.
--
-- Which data belongs to which addon isn't something the game says. TwichUI
-- loads first, so a scan you ask for (one reload) notes the new globals that
-- appear as each addon loads, the same moment setup sharing uses. An addon's
-- code makes globals too, so only plain data is kept (tables of strings,
-- numbers and booleans, and loose values) and code is skipped. That is a good
-- guess, not a declaration, and the window says so.
--
-- Nothing here changes, copies or sends another addon's data. A scan
-- remembers names and owners only (TwichUIDB.storedData); sizes are counted
-- when the window asks, a little each frame, and kept for that session.

local R = TwichUI
local ST = R.Setups
local SD = {}
R.StoredData = SD

-- TwichUI's own saved variables, as the .toc declares them (all account-wide).
SD.OWN = { "TwichUIDB", "TwichUIBackupDB", "TwichUIShareDB", "TwichUIRestoreDB", "TwichUIChronicleDB" }
local own = {}
for _, name in ipairs(SD.OWN) do own[name] = true end

local db                         -- TwichUIDB.storedData
SD.sizes = {}                    -- [name] = { entries, bytes, shared, unsaved, partial, failed } this session
local listeners = {}

function SD.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed(name)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, name)
        if not ok then geterrorhandler()(err) end
    end
end

local function Loaded(addon)
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, addon)
    return ok and loaded and true or false
end

---------------------------------------------------------------------------
-- Scan: which globals appear as each addon loads
---------------------------------------------------------------------------
local known                      -- every global name seen so far, during a scan only
local found, loadedNow, before   -- this scan's results

-- Globals an addon's code makes that look like loose values but aren't data.
local CODE_NAMES = { "^SLASH_", "^BINDING_" }

-- Saved data is plain: string, number and boolean keys and values, and tables
-- of those, with no metatable (code objects and frames have functions,
-- userdata or a metatable). Looks at up to LOOK_LIMIT entries; a bigger table
-- that is plain that far counts as data.
local LOOK_LIMIT = 5000
local function LooksLikeData(t)
    if getmetatable(t) ~= nil then return false end
    local n, stack, seen = 0, { t }, { [t] = true }
    while #stack > 0 do
        local x = table.remove(stack)
        if canaccesstable and not canaccesstable(x) then return false end
        for k, v in next, x do
            n = n + 1
            if n > LOOK_LIMIT then return true end
            local kt, vt = type(k), type(v)
            if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then return false end
            if vt == "table" then
                if not seen[v] then seen[v] = true; stack[#stack + 1] = v end
            elseif vt ~= "string" and vt ~= "number" and vt ~= "boolean" then
                return false
            end
        end
    end
    return true
end

-- "table", "value" or nil (not data)
function SD.Kind(name, v)
    local t = type(v)
    if t == "table" then
        local ok, data = pcall(LooksLikeData, v)
        return (ok and data) and "table" or nil
    elseif t == "string" or t == "number" or t == "boolean" then
        for _, p in ipairs(CODE_NAMES) do if name:find(p) then return nil end end
        return "value"
    end
end

local function ScanNew(owner)
    local blizzard = owner:find("^Blizzard_") ~= nil
    for k, v in next, _G do
        if not known[k] then
            known[k] = true
            if not blizzard and type(k) == "string" and not k:find("^TwichUI") then
                local kind = SD.Kind(k, v)
                if kind then found[k] = { owner = owner, value = (kind == "value") or nil } end
            end
        end
    end
end

-- Keeps what earlier scans found for addons that didn't load this time (off,
-- waiting to load, removed); replaces the rest.
local function FinishScan()
    local now = time()
    for name, e in pairs(db.found) do
        if loadedNow[e.owner] or found[name] or own[name] then db.found[name] = nil end
    end
    for name, e in pairs(found) do
        e.seen = now
        db.found[name] = e
    end
    db.scanned, db.before = now, before
    known, found, loadedNow, before = nil, nil, nil, nil
    C_Timer.After(1, function() if R.StoredDataWindow then R.StoredDataWindow:Show() end end)
end

-- Reloads; the window opens again once the scan is done.
function SD.Scan()
    db.scanNext = true
    ReloadUI()
end

function SD.LastScan() return db and db.scanned end

---------------------------------------------------------------------------
-- Addons and where they stand
---------------------------------------------------------------------------
local function EnableState(addon, character)
    local ok, state = pcall(C_AddOns.GetAddOnEnableState, addon, character)
    if ok and type(state) == "number" then return state end
end

local REASON = {
    INTERFACE_VERSION = "Out of date",
    DEP_DISABLED = "Needs an addon that's off",
    DEMAND_LOADED = "Loads when needed",
    DEP_DEMAND_LOADED = "Loads when needed",
}

-- key ("loaded", "waiting", "off", "blocked", "missing"), and a word or two
function SD.Status(addon)
    if Loaded(addon) then return "loaded", "Loaded" end
    local exists = true
    if C_AddOns.DoesAddOnExist then
        local ok, e = pcall(C_AddOns.DoesAddOnExist, addon)
        if ok then exists = e end
    end
    if not exists then return "missing", "Not installed" end
    if EnableState(addon, UnitGUID("player")) == 0 then
        if (EnableState(addon) or 0) > 0 then return "off", "Off for this character" end
        return "off", "Off"
    end
    local ok, _, _, _, loadable, reason = pcall(C_AddOns.GetAddOnInfo, addon)
    reason = ok and reason or ""
    local lod = C_AddOns.IsAddOnLoadOnDemand and C_AddOns.IsAddOnLoadOnDemand(addon)
    if lod and (loadable or REASON[reason] == "Loads when needed") then return "waiting", "Loads when needed" end
    if REASON[reason] then return "blocked", REASON[reason] end
    return "blocked", "Not loaded"
end

function SD.Owner(name)
    if own[name] then return R.ADDON end
    local e = db and db.found[name]
    return e and e.owner
end

function SD.Found(name) return db and db.found[name] end
function SD.IsOwn(name) return own[name] == true end

-- Whether the data can be looked at now: its owner is loaded this session.
function SD.Readable(name)
    local owner = SD.Owner(name)
    return owner ~= nil and Loaded(owner)
end

-- The value itself, only when readable (a global of an addon that isn't
-- loaded may belong to someone else).
function SD.Value(name)
    if SD.Readable(name) then return rawget(_G, name) end
end

local function ByName(a, b) return a:lower() < b:lower() end

-- Why a global an addon brought looks like its own working data (made by its
-- code each session) rather than saved data, or nil. Checked against the saved
-- files on the Forever beta: these signs covered 24 of the 26 working tables a
-- scan picked up and none of the saved ones. Only a sign: such items are still
-- listed, apart, and left out of totals.
function SD.WorkingReason(name, owner)
    if name:find("^_") then return "Its name starts with _, as addons name their own internal data." end
    if name:find("%u") and not name:find("%l") then return "Its name is in capitals, as addons name their constants." end
    if owner and name == owner then return "It has the addon's own name, as addons name their code's main table." end
end

-- { name, title, status, statusText, vars = { names }, working = { names }, own, before }
-- vars are likely saved data; working likely the addon's own working data.
-- TwichUI first, then the rest by title; addons a scan found that aren't
-- installed any more come along as "Not installed".
function SD.Addons()
    local byOwner = {}
    for name, e in pairs(db.found) do
        local entry = byOwner[e.owner] or { vars = {}, working = {} }
        byOwner[e.owner] = entry
        table.insert(SD.WorkingReason(name, e.owner) and entry.working or entry.vars, name)
    end
    local list = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, _, _, _, _, security = C_AddOns.GetAddOnInfo(i)
        if name and name ~= R.ADDON and not name:find("^Blizzard_") and security ~= "SECURE" then
            local status, text = SD.Status(name)
            local entry = byOwner[name] or { vars = {}, working = {} }
            list[#list + 1] = { name = name, title = ST.AddonTitle(name), status = status, statusText = text,
                vars = entry.vars, working = entry.working, before = db.before and db.before[name] or nil }
            byOwner[name] = nil
        end
    end
    for owner, entry in pairs(byOwner) do
        if owner ~= R.ADDON then
            local status, text = SD.Status(owner)
            list[#list + 1] = { name = owner, title = owner, status = status, statusText = text, vars = entry.vars, working = entry.working }
        end
    end
    table.sort(list, function(a, b) return ByName(a.title, b.title) end)
    for _, a in ipairs(list) do
        table.sort(a.vars, ByName)
        table.sort(a.working, ByName)
    end
    local vars = {}
    for i, name in ipairs(SD.OWN) do vars[i] = name end
    table.insert(list, 1, { name = R.ADDON, title = "TwichUI", status = "loaded", statusText = "Loaded", vars = vars, working = {}, own = true })
    return list
end

---------------------------------------------------------------------------
-- Sizes: entries, and the bytes the data would take in the saved file as it
-- is now (owners may trim it as they save, e.g. AceDB leaving out defaults)
---------------------------------------------------------------------------
-- The client writes one entry per line with no indent:
--   Name = {\r\n["key"] = "value",\r\n[2] = 1.5,\r\n["sub"] = {\r\n},\r\n}\r\n
-- Strings escape \ " and line breaks; fractions get about 17 digits. Shared
-- tables are counted once, so the estimate can be low where data is shared.
local function StrLen(s)
    local n = #s + 2
    if s:find('[\\"\n\r]') then n = n + select(2, s:gsub('[\\"\n\r]', "")) end
    return n
end

local function NumLen(v)
    if v == math.floor(v) and v > -1e15 and v < 1e15 then return #("%d"):format(v) end
    return #("%.17g"):format(v) - 1
end

local function ScalarLen(v, t)
    if t == "string" then return StrLen(v) end
    if t == "number" then return NumLen(v) end
    if t == "boolean" then return v and 4 or 5 end
end

local SLICE = 500                -- entries between yields
local yield = coroutine.yield

-- Runs in a coroutine; yields every SLICE entries.
function SD.Count(name, value)
    local r = { entries = 0, bytes = 0 }
    local vt = type(value)
    if vt ~= "table" then
        r.bytes = #name + 3 + (ScalarLen(value, vt) or 3) + 2       -- Name = value\r\n
        return r
    end
    r.bytes = #name + 3 + 2                                         -- "Name = " ... "\r\n"
    local seen, stack, steps = { [value] = true }, { value }, 0
    while #stack > 0 do
        local x = table.remove(stack)
        r.bytes = r.bytes + 4                                       -- "{\r\n" ... "}"
        if canaccesstable and not canaccesstable(x) then
            r.partial = true
        else
            for k, v in next, x do
                steps = steps + 1
                if steps % SLICE == 0 and coroutine.running() then yield() end
                if issecretvalue and (issecretvalue(k) or issecretvalue(v)) then
                    r.partial = true
                else
                    local kt, t = type(k), type(v)
                    local kl = ScalarLen(k, kt)
                    local vl = (t == "table") and 0 or ScalarLen(v, t)
                    if kl and vl then
                        r.entries = r.entries + 1
                        r.bytes = r.bytes + kl + 2 + 3 + vl + 3     -- [key] = value,\r\n
                        if t == "table" then
                            if seen[v] then r.shared = true
                            else seen[v] = true; stack[#stack + 1] = v end
                        end
                    else
                        r.unsaved = true                            -- a function or frame: not written to disk
                    end
                end
            end
        end
    end
    return r
end

-- One count at a time, a few milliseconds each frame.
local BUDGET_MS = 4
local clock = debugprofilestop or function() return GetTime() * 1000 end
local runner = CreateFrame("Frame")
local queue, queued, current = {}, {}, nil

local function StartNext()
    while #queue > 0 do
        local name = table.remove(queue, 1)
        queued[name] = nil
        if SD.Readable(name) then
            local value = rawget(_G, name)
            current = { name = name, co = coroutine.create(function() return SD.Count(name, value) end) }
            return true
        end
    end
    runner:SetScript("OnUpdate", nil)
    return false
end

local function Run()
    local start = clock()
    while current or StartNext() do
        local ok, result = coroutine.resume(current.co)
        local name = current.name
        if not ok then
            -- Most likely the addon changed the table while it was being counted.
            SD.sizes[name] = { failed = true }
            current = nil
            Changed(name)
        elseif coroutine.status(current.co) == "dead" then
            SD.sizes[name] = result
            current = nil
            Changed(name)
        end
        if clock() - start >= BUDGET_MS then return end
    end
end

function SD.Measure(name)
    if SD.sizes[name] or queued[name] or (current and current.name == name) then return end
    queued[name] = true
    queue[#queue + 1] = name
    runner:SetScript("OnUpdate", Run)
end

function SD.Busy() return current ~= nil or #queue > 0 end

-- Forget counts (the window counts afresh each time it opens).
function SD.ClearSizes()
    wipe(queue); wipe(queued)
    current = nil
    runner:SetScript("OnUpdate", nil)
    wipe(SD.sizes)
end

---------------------------------------------------------------------------
-- Showing keys and values as text
---------------------------------------------------------------------------
local RANK = { number = 1, string = 2, boolean = 3 }
local function KeyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return (RANK[ta] or 4) < (RANK[tb] or 4) end
    if ta == "number" then return a < b end
    if ta == "string" then
        local la, lb = a:lower(), b:lower()
        if la ~= lb then return la < lb end
        return a < b
    end
    if ta == "boolean" then return (not a) and b end
    return false
end

local SORT_LIMIT = 20000

-- Keys of t: numbers, then names A to Z. Returns keys, how many were hidden
-- (secret), and whether they were left unsorted (too many).
function SD.Keys(t)
    local keys, hidden = {}, 0
    for k in next, t do
        if issecretvalue and issecretvalue(k) then hidden = hidden + 1
        else keys[#keys + 1] = k end
    end
    local unsorted = #keys > SORT_LIMIT
    if not unsorted then table.sort(keys, KeyLess) end
    return keys, hidden, unsorted
end

-- Entries in t, counting up to cap. Returns n and whether there are more.
function SD.CountTo(t, cap)
    local n = 0
    for _ in next, t do
        n = n + 1
        if n >= cap then return n, next(t) ~= nil end
    end
    return n, false
end

-- Cuts at most max bytes without splitting a character.
local function Clip(s, max)
    if #s <= max then return s, false end
    local cut = max
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut), true
end

-- Shows text as written: | is doubled so color codes, icons and links are
-- shown, never used, and line breaks are shown as \n.
function SD.Plain(s)
    return (s:gsub("|", "||"):gsub("\r", "\\r"):gsub("\n", "\\n"))
end

function SD.ShowKey(k)
    if issecretvalue and issecretvalue(k) then return "<secret>" end
    local t = type(k)
    if t == "string" then
        local s, cut = Clip(k, 80)
        return SD.Plain(s) .. (cut and "..." or "")
    end
    if t == "number" or t == "boolean" then return "[" .. tostring(k) .. "]" end
    return "<" .. t .. ">"
end

-- A value as text, for a row (max bytes of a string shown) or a tooltip.
function SD.ShowValue(v, max)
    if issecretvalue and issecretvalue(v) then return R.GREY .. "<secret>|r" end
    local t = type(v)
    if t == "string" then
        local s, cut = Clip(v, max or 160)
        s = '"' .. SD.Plain(s) .. '"'
        if cut then s = s .. R.GREY .. ("... (%s characters)"):format(SD.Num(#v)) .. "|r" end
        return s
    end
    if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
    return R.GREY .. "<" .. t .. ">|r"
end

function SD.Num(n)
    local s = tostring(math.floor(n))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

function SD.FormatSize(bytes) return ST.FormatSize(bytes) end

---------------------------------------------------------------------------
-- Load-time work
---------------------------------------------------------------------------
R:OnInit(function()
    TwichUIDB.storedData = TwichUIDB.storedData or {}
    db = TwichUIDB.storedData
    db.found = db.found or {}
    db.scanMode = nil            -- set by an earlier build; the window always opens after a scan now
    TwichUIDB.svTest = nil       -- the last report of the temporary /tui svtest check (removed)
    SD.db = db
    if not db.scanNext then return end
    db.scanNext = nil
    known, found, loadedNow, before = {}, {}, {}, {}
    for k in next, _G do known[k] = true end
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name ~= R.ADDON and not name:find("^Blizzard_") and C_AddOns.IsAddOnLoaded(i) then
            before[name] = true
        end
    end
    if next(before) == nil then before = nil end
end)

R:On("ADDON_LOADED", function(name)
    if not known or name == R.ADDON then return end
    loadedNow[name] = true
    ScanNew(name)
end)

R:On("PLAYER_LOGIN", function()
    if known then FinishScan() end
end)
