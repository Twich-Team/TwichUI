-- TwichUI Layouts: the canonical form of a value, and its fingerprint (architecture.md §6)
-- One text per value, whatever order pairs() walks a table in: keys sorted by their own canonical text, numbers written
-- with %.17g, and false, 0, "" and nothing all distinct. Used for plan keys (two plans with the same key do the same
-- thing), for what an install expects to read back, and for the values a snapshot keeps. Bounded: a cycle, a table
-- nested too deeply, too many values or too much text is refused, never walked. No game calls.

local R = TwichUI
local LY = {}
R.Layouts = LY
LY.CONTRACT = 1   -- the adapter contract's version (architecture.md §4)

-- "Inherit the layer below" in a package layer (§1, §6). A table only this file makes, so no real value can be it.
LY.REMOVE = setmetatable({}, { __tostring = function() return "REMOVE" end, __newindex = function() error("LY.REMOVE is read only", 2) end })

LY.CANON = { depth = 16, nodes = 50000, bytes = 8 * 1048576 }
LY.FINGERPRINT_KEEP = 64   -- a canonical text up to this long is kept as it is; a longer one as a checksum and its length

local L = LY.CANON
local LibDeflate = LibStub("LibDeflate")

local function Num(n)
    if n ~= n or n == math.huge or n == -math.huge then return nil end
    if n == 0 then return "0" end   -- 0 and -0 are the same value
    return ("%.17g"):format(n)
end

local function KeyText(k)
    local t = type(k)
    if t == "string" then return "s" .. #k .. ":" .. k end
    if t == "number" then local s = Num(k) return s and ("n" .. s .. ";") end
    if t == "boolean" then return k and "t" or "f" end
end

local Refused = {}   -- the error value a refusal is raised with: { refused = code }

-- The canonical text of v, or nil and why: "cycle", "depth", "size", "number" (NaN or infinite), "type" (a function,
-- a frame ...), "key" (a table key that is not a string, number or boolean).
function LY.Canon(v)
    local out, n, nodes, bytes = {}, 0, 0, 0
    local active = {}
    local function Stop(code) error(setmetatable({ refused = code }, Refused), 0) end
    local function Put(s)
        n = n + 1
        out[n] = s
        bytes = bytes + #s
        if bytes > L.bytes then Stop("size") end
    end
    local function Walk(x, depth)
        nodes = nodes + 1
        if nodes > L.nodes then Stop("size") end
        if x == LY.REMOVE then Put("R") return end
        local t = type(x)
        if t == "nil" then Put("z")
        elseif t == "boolean" then Put(x and "t" or "f")
        elseif t == "number" then
            local s = Num(x)
            if not s then Stop("number") end
            Put("n" .. s .. ";")
        elseif t == "string" then
            Put("s" .. #x .. ":")
            Put(x)
        elseif t == "table" then
            if active[x] then Stop("cycle") end
            if depth >= L.depth then Stop("depth") end
            active[x] = true
            local keys = {}
            for k in next, x do
                local kt = KeyText(k)
                if not kt then Stop("key") end
                keys[#keys + 1] = { k = k, t = kt }
                if #keys > L.nodes then Stop("size") end
            end
            table.sort(keys, function(a, b) return a.t < b.t end)
            Put("{")
            for _, e in ipairs(keys) do
                Put(e.t)
                Walk(x[e.k], depth + 1)
            end
            Put("}")
            active[x] = nil
        else
            Stop("type")
        end
    end
    local ok, err = pcall(Walk, v, 0)
    if not ok then
        if getmetatable(err) == Refused then return nil, err.refused end
        error(err, 0)
    end
    return table.concat(out)
end

-- A short, stable text for v: its canonical text when that is short, else a checksum and the length. nil and why
-- when v has no canonical text. Two equal values always give the same fingerprint.
function LY.Fingerprint(v)
    local c, why = LY.Canon(v)
    if not c then return nil, why end
    if #c <= LY.FINGERPRINT_KEEP then return "=" .. c end
    return "#" .. tostring(LibDeflate:Adler32(c)) .. ":" .. #c
end

-- The normalized value of a setting the layouts compare unit by unit (updates.md): its whole canonical text, so a baseline
-- holds the value itself and not a checksum of it. Settings are small (a word, a number, a colour); one whose text is longer
-- than LY.VALUE_MAX is kept as its fingerprint, which still compares equal values as equal.
LY.VALUE_MAX = 256
function LY.Value(v)
    local c, why = LY.Canon(v)
    if not c then return nil, why end
    if #c <= LY.VALUE_MAX then return "=" .. c end
    return LY.Fingerprint(v)
end

function LY.Same(a, b)
    local ca, cb = LY.Canon(a), LY.Canon(b)
    return ca ~= nil and ca == cb
end

---------------------------------------------------------------------------
-- Small shared helpers
---------------------------------------------------------------------------
function LY.Set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

function LY.SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- A stable id: lower-case letters, digits and single hyphens, starting with a letter (§5).
function LY.IsId(s, max)
    return type(s) == "string" and #s <= (max or 64) and s:match("^[a-z][a-z0-9%-]*$") ~= nil
        and not s:find("%-%-") and not s:find("%-$")
end

-- Plain text: 1..max bytes, no control characters and no "|" (where the game's colour and texture codes start).
function LY.Plain(s, max)
    return type(s) == "string" and #s >= 1 and #s <= max and not s:find("[%c|]")
end

function LY.Copy(v) return R.Persist.DeepCopy(v) end

-- A bounded list of problems: { code, where } (where: a unit, a layer or a field name). Codes are a fixed vocabulary.
LY.MAX_PROBLEMS = 24
function LY.Problems()
    local list = { n = 0 }
    function list.add(code, where)
        list.n = list.n + 1
        if #list < LY.MAX_PROBLEMS then list[#list + 1] = { code = code, where = where } end
    end
    return list
end
