-- TwichUI: portable backups
-- Turns one saved backup (restore point) into a text string you can copy out
-- of the game, and reads such a string back in as a new backup. Nothing here
-- is sent to anyone, and nothing in an import is ever run as code: it is
-- only decoded as data (LibDeflate, LibSerialize) and checked before anything
-- is stored. Importing never applies a backup; restoring stays a separate,
-- deliberate step.
--
-- Format, version 1 (one line of plain text):
--   TUIBK1:<length>:<check>:<size>:<payload>
--   length  size of the data once unpacked
--   check   Adler-32 of the unpacked data. It catches accidental damage such
--           as a cut-off paste or a mangled character; it is not security
--           and says nothing about who made the string.
--   size    length of <payload>, to catch truncation
--   payload "<n>:<piece>" pieces, each a separately compressed slice of the
--           serialized backup, printable characters only
-- The data is { fmt, addon, point = { name, created, source, sourceName, tables } }.

local R = TwichUI
local ST, RS = R.Setups, R.Restore
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local P = {}
R.Portable = P

local FORMAT = 1
local MAGIC = "TUIBK"
local SLICE = 16384          -- unpacked bytes per piece
local PIECE_MAX = 26000      -- packed characters per piece, far above what SLICE produces
local BUDGET_MS = 12

P.FORMAT = FORMAT
P.LIMITS = {
    input = 8 * 1048576,     -- characters accepted from a paste
    raw = 24 * 1048576,      -- bytes after unpacking
    depth = 64,
    tables = 500,            -- settings tables in one backup
    nodes = 3000000,
    string = 2 * 1048576,
    key = 4096,
    name = 100,
    ident = 128,
}
local L = P.LIMITS

-- What imports may add to your stored backups. Backups you create yourself
-- are not limited by these.
P.MAX_POINTS = 20
P.MAX_TOTAL = 32 * 1048576

---------------------------------------------------------------------------
-- Background jobs: one at a time, a little each frame
---------------------------------------------------------------------------
local job
local frame = CreateFrame("Frame")
local clock = debugprofilestop or function() return GetTime() * 1000 end

local function Stop()
    job = nil
    frame:SetScript("OnUpdate", nil)
end

local function Run()
    local j = job
    if not j then return end
    local start = clock()
    repeat
        local ok, success, value = coroutine.resume(j.co)
        if not ok then
            Stop()
            geterrorhandler()(success)
            j.fail("Something went wrong while reading that. Nothing was changed.")
            return
        end
        if coroutine.status(j.co) == "dead" then
            Stop()
            if success then j.done(value) else j.fail(value) end
            return
        end
    until clock() - start >= BUDGET_MS
end

-- body returns true, result  |  false, message, and calls coroutine.yield() between slices
local function Start(body, done, fail)
    Stop()
    job = { co = coroutine.create(body), done = done, fail = fail }
    frame:SetScript("OnUpdate", Run)
end

function P.Cancel() Stop() end
function P.Busy() return job ~= nil end

local yield = coroutine.yield

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local function AddonVersion()
    if R.Group and R.Group.Version then
        local ok, v = pcall(R.Group.Version)
        if ok and type(v) == "string" then return v end
    end
    return "?"
end

-- done(text). The backup itself is only read, never copied.
function P.Export(point, done, fail)
    Start(function()
        if type(point) ~= "table" or type(point.tables) ~= "table" then return false, "That backup can't be read." end
        local handler = LibSerialize:SerializeAsync({
            fmt = FORMAT, addon = AddonVersion(),
            point = { name = point.name, created = point.created, source = point.source, sourceName = point.sourceName, tables = point.tables },
        })
        local serialized
        while true do
            local completed, result = handler()
            if completed then serialized = result break end
            yield()
        end
        local pieces, pos = {}, 1
        while pos <= #serialized do
            local enc = LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(serialized:sub(pos, pos + SLICE - 1), { level = 5 }))
            pieces[#pieces + 1] = #enc .. ":" .. enc
            pos = pos + SLICE
            yield()
        end
        local payload = table.concat(pieces)
        return true, ("%s%d:%d:%s:%d:%s"):format(MAGIC, FORMAT, #serialized, LibDeflate:Adler32(serialized), #payload, payload)
    end, done, fail)
end

---------------------------------------------------------------------------
-- Checking an import
---------------------------------------------------------------------------
local function Fail(msg) return false, msg end

local NAME_BAD = "[%c|]"
local function CleanName(s)
    s = s:gsub(NAME_BAD, ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #s > L.name then
        s = s:sub(1, L.name)
        -- don't leave half a character at the cut
        s = s:gsub("[\192-\255][\128-\191]*$", function(tail)
            local lead = tail:byte(1)
            return #tail < (lead >= 240 and 4 or lead >= 224 and 3 or 2) and "" or nil
        end)
    end
    return s
end

local function SetOf(list) local s = {} for _, k in ipairs(list) do s[k] = true end return s end
local ENVELOPE_KEYS = SetOf({ "fmt", "addon", "point" })
local POINT_KEYS = SetOf({ "name", "created", "source", "sourceName", "tables" })
local ENTRY_KEYS = SetOf({ "owner", "data" })

local function OnlyKeys(t, allowed)
    for k in pairs(t) do if not allowed[k] then return false end end
    return true
end

-- Cheap checks on the outer structure. Returns the point, or nil, message.
local function CheckShape(env)
    if type(env) ~= "table" or type(env.point) ~= "table" or not OnlyKeys(env, ENVELOPE_KEYS) then
        return nil, "That isn't a TwichUI backup, or it was made by a newer version of TwichUI."
    end
    if env.fmt ~= FORMAT then
        return nil, ("That backup uses export format %s; this TwichUI reads format %d."):format(tostring(env.fmt), FORMAT)
    end
    if env.addon ~= nil and (type(env.addon) ~= "string" or #env.addon > 32) then return nil, "That backup is damaged." end
    local p = env.point
    if not OnlyKeys(p, POINT_KEYS) then
        return nil, "That backup has fields this TwichUI doesn't know. It was probably made by a newer version."
    end
    if type(p.name) ~= "string" or type(p.created) ~= "number" or p.created ~= p.created
        or type(p.tables) ~= "table" or (p.source ~= nil and (type(p.source) ~= "string" or #p.source > 96))
        or (p.sourceName ~= nil and (type(p.sourceName) ~= "string" or #p.sourceName > 64)) then
        return nil, "That backup is damaged."
    end
    local n = 0
    for name, e in pairs(p.tables) do
        n = n + 1
        if n > L.tables then return nil, "That backup holds more settings tables than a backup can." end
        if type(name) == "string" and name:find("^TwichUI") then
            return nil, "That backup contains TwichUI's own data, which a backup never includes. It isn't a backup TwichUI made."
        end
        if not ST.ValidName(name) then return nil, "That backup is damaged." end
        if type(e) ~= "table" or not OnlyKeys(e, ENTRY_KEYS) or type(e.data) ~= "table"
            or type(e.owner) ~= "string" or #e.owner > L.ident then
            return nil, "That backup is damaged."
        end
    end
    if n == 0 then return nil, "That backup is empty." end
    return p, n
end

-- Walks every settings table, a slice at a time. Only plain data is accepted:
-- string, number, boolean keys and string, number, boolean, table values;
-- bounded depth and size; no table containing itself.
local function CheckData(roots)
    local seen, onPath, nodes = {}, {}, 0
    local sinceYield = 0
    for _, root in ipairs(roots) do
        if not seen[root] then
            seen[root] = true
            onPath[root] = true
            local tbls, keys, started, top = { root }, {}, {}, 1
            while top > 0 do
                local t = tbls[top]
                local k, v
                if started[top] then k, v = next(t, keys[top]) else k, v = next(t) end
                if k == nil then
                    onPath[t] = nil
                    tbls[top], keys[top], started[top] = nil, nil, nil
                    top = top - 1
                else
                    keys[top], started[top] = k, true
                    nodes = nodes + 1
                    if nodes > L.nodes then return Fail("That backup is larger than a backup can be.") end
                    local kt, vt = type(k), type(v)
                    if kt == "string" then
                        if #k > L.key then return Fail("That backup is damaged.") end
                    elseif kt ~= "number" and kt ~= "boolean" then
                        return Fail("That backup is damaged.")
                    end
                    if vt == "string" then
                        if #v > L.string then return Fail("That backup is larger than a backup can be.") end
                    elseif vt == "table" then
                        if onPath[v] then return Fail("That backup is damaged.") end
                        if not seen[v] then
                            if top >= L.depth then return Fail("That backup is nested more deeply than a backup can be.") end
                            seen[v] = true
                            onPath[v] = true
                            top = top + 1
                            tbls[top], keys[top], started[top] = v, nil, nil
                        end
                    elseif vt ~= "number" and vt ~= "boolean" then
                        return Fail("That backup is damaged.")
                    end
                    sinceYield = sinceYield + 1
                    if sinceYield >= 20000 then sinceYield = 0; yield() end
                end
            end
        end
    end
    return true
end

local hashCache = {}   -- [point id] = hash (this session only; never saved)
local function HashOf(point)
    local h = point.id and hashCache[point.id]
    if h == nil then
        h = ST.Hash(point.tables) or false
        if point.id then hashCache[point.id] = h end
    end
    return h or nil
end

-- done(result) where result = {
--   point, bytes, count, addons, addonVersion, inputSize,
--   missing = { addon titles }, skipped = n (tables that won't apply here),
--   duplicate = name of an identical backup you already have | nil,
--   blocked = reason an import isn't allowed | nil }
function P.Check(text, done, fail)
    Start(function()
        if type(text) ~= "string" then return Fail("Paste a TwichUI backup string first.") end
        if #text > L.input then
            return Fail(("That is too large to import (over %s)."):format(ST.FormatSize(L.input)))
        end
        text = text:gsub("%s+", "")
        local inputSize = #text
        if inputSize == 0 then return Fail("Paste a TwichUI backup string first.") end
        local version, rest = text:match("^" .. MAGIC .. "(%d+):(.*)$")
        if not version then return Fail("That isn't a TwichUI backup string.") end
        version = tonumber(version)
        if version ~= FORMAT then
            return Fail(("That backup uses export format %d; this TwichUI reads format %d. Update TwichUI on whichever client is older."):format(version, FORMAT))
        end
        local rawLen, check, size, payload = rest:match("^(%d+):(%d+):(%d+):(.*)$")
        if not rawLen then return Fail("That backup string is damaged or cut off.") end
        rawLen, size = tonumber(rawLen), tonumber(size)
        rest = nil
        if rawLen > L.raw then return Fail("That backup is larger than a backup can be.") end
        if #payload ~= size then return Fail("That backup string is incomplete: it looks cut off or changed while copying.") end
        yield()

        local parts, total, pos = {}, 0, 1
        while pos <= #payload do
            local len, from = payload:match("^(%d+):()", pos)
            len = tonumber(len)
            if not len or len < 1 or len > PIECE_MAX then return Fail("That backup string is damaged.") end
            local piece = payload:sub(from, from + len - 1)
            if #piece ~= len then return Fail("That backup string is incomplete: it looks cut off.") end
            pos = from + len
            local d = LibDeflate:DecodeForPrint(piece)
            d = d and LibDeflate:DecompressDeflate(d)
            if not d or #d > SLICE then return Fail("That backup string is damaged.") end
            total = total + #d
            if total > rawLen then return Fail("That backup string is damaged.") end
            parts[#parts + 1] = d
            yield()
        end
        payload = nil
        if total ~= rawLen then return Fail("That backup string is incomplete or damaged.") end
        local serialized = table.concat(parts)
        parts = nil
        if tostring(LibDeflate:Adler32(serialized)) ~= check then
            return Fail("That backup string is damaged: its check number doesn't match. Copy it again from the original.")
        end
        yield()

        local handler = LibSerialize:DeserializeAsync(serialized)
        serialized = nil
        local env
        while true do
            local completed, success, value = handler()
            if completed then
                if not success then return Fail("That backup string is damaged.") end
                env = value
                break
            end
            yield()
        end

        local point, count = CheckShape(env)
        if not point then return Fail(count) end
        local roots = {}
        for _, e in pairs(point.tables) do roots[#roots + 1] = e.data end
        local ok, msg = CheckData(roots)
        if not ok then return Fail(msg) end
        roots = nil
        local addonVersion = env.addon
        env = nil

        local clean = {
            name = CleanName(point.name), created = point.created, source = point.source,
            sourceName = point.sourceName and CleanName(point.sourceName) or nil, tables = point.tables,
        }
        if clean.name == "" then clean.name = date("%b %d %H:%M", math.max(0, math.min(clean.created, 4e9))) end

        local result = {
            point = clean, count = count, addonVersion = addonVersion, inputSize = inputSize,
            bytes = ST.SizeOf(clean.tables), missing = {}, skipped = 0,
        }
        local owners, nOwners = {}, 0
        for name, e in pairs(clean.tables) do
            if not owners[e.owner] then
                owners[e.owner] = true
                nOwners = nOwners + 1
                local state = ST.AddonState(e.owner)
                if state == "missing" or state == "disabled" then result.missing[#result.missing + 1] = ST.AddonTitle(e.owner) end
            end
            if not ST.SafeName(name) then result.skipped = result.skipped + 1 end
            yield()   -- SafeName reads the live table of that name, which can be large
        end
        table.sort(result.missing)
        result.addons = nOwners
        yield()

        -- Limits and repeats. Hashes of backups you already have are kept in
        -- memory only, so looking never changes saved data.
        local hash = ST.Hash(clean.tables)
        result.hash = hash
        local points = RS.List()
        local totalBytes = 0
        for _, p in ipairs(points) do
            totalBytes = totalBytes + RS.Size(p)
            if hash and not result.duplicate and HashOf(p) == hash then result.duplicate = p.name end
            yield()
        end
        if result.duplicate then
            result.blocked = ("You already have this backup (\"%s\")."):format(result.duplicate)
        elseif #points >= P.MAX_POINTS then
            result.blocked = ("You already have %d backups, the most an import can add to. Delete one first."):format(#points)
        elseif totalBytes + result.bytes > P.MAX_TOTAL then
            result.blocked = ("Your backups would take more than %s of saved data. Delete a backup first."):format(ST.FormatSize(P.MAX_TOTAL))
        end
        return true, result
    end, done, fail)
end

-- Stores a checked import as a new backup. Returns the point, or nil, reason.
-- This is the only place an import changes saved data, and it never applies it.
-- The checked tables become the stored backup's own (no second copy of up to 24 MB), so the result
-- gives them up: committing the same result again, or a click on a stale preview, imports nothing.
function P.Commit(result)
    if type(result) ~= "table" or not result.point then return nil, "Nothing to import." end
    if result.blocked then return nil, result.blocked end
    local p = result.point
    -- The preview may be older than this click: the limits are checked against what is stored now.
    local points = RS.List()
    if #points >= P.MAX_POINTS then
        return nil, ("You already have %d backups, the most an import can add to. Delete one first."):format(#points)
    end
    local total = 0
    for _, existing in ipairs(points) do total = total + RS.Size(existing) end
    if total + (result.bytes or 0) > P.MAX_TOTAL then
        return nil, ("Your backups would take more than %s of saved data. Delete a backup first."):format(ST.FormatSize(P.MAX_TOTAL))
    end
    local point = RS.AddImported({
        name = p.name, created = p.created, source = p.source, sourceName = p.sourceName, tables = p.tables,
    })
    if not point then return nil, "That backup couldn't be added." end
    result.point = nil
    return point
end
