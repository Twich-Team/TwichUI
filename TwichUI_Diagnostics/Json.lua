-- TwichUI Diagnostics: JSON for reports, and cutting a report into pieces to copy
-- Writing only: nothing here reads JSON or runs anything it is given. Objects' keys are written in a fixed order (the
-- `first` list, then the rest sorted), so the same capture always gives the same text. Numbers: whole numbers as
-- integers, others with 6 significant digits; NaN and infinities as null. Strings are escaped, and bytes that are not
-- valid UTF-8 become "?" so the text is always valid JSON. An empty table is written as [] (every empty part of a
-- report is a list). Tables nested deeper than MAX_DEPTH, or a table inside itself, are refused with an error.
--
-- Pieces: the game gives an addon no clipboard and no files, so a large report is shown in pieces to copy one after
-- another. Each piece starts with one header line naming its place, the report's length and an Adler-32 of the whole
-- report and of the piece; join the pieces' text after their header lines, in order, to get the report back exactly.

local R = TwichUI
local DX = R.DiagnosticsKit
local J = {}
DX.Json = J

J.MAX_DEPTH = 32
J.FIRST = { "schema", "kind", "id", "uid", "generatedAt", "units", "provenance", "redaction", "truncation" }

local format, byte, char, concat = string.format, string.byte, string.char, table.concat

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

-- valid UTF-8 kept, anything else "?"
local function Utf8(s)
    if not s:find("[\128-\255]") then return s end
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = byte(s, i)
        local len = (c < 0x80 and 1) or (c >= 0xC2 and c <= 0xDF and 2) or (c >= 0xE0 and c <= 0xEF and 3) or (c >= 0xF0 and c <= 0xF4 and 4) or 0
        local ok = len > 0 and i + len - 1 <= n
        if ok then
            for k = i + 1, i + len - 1 do
                local d = byte(s, k)
                if d < 0x80 or d > 0xBF then ok = false break end
            end
        end
        if ok then out[#out + 1] = s:sub(i, i + len - 1); i = i + len
        else out[#out + 1] = "?"; i = i + 1 end
    end
    return concat(out)
end

local function Str(s)
    s = Utf8(s)
    return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or format("\\u%04x", byte(c)) end) .. '"'
end
J.String = Str

local function Num(v)
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return format("%d", v) end
    return format("%.6g", v)
end

local function IsArray(t)
    local n = #t
    local count = 0
    for k in pairs(t) do
        count = count + 1
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    end
    return count == n
end

local Encode
local function Keys(t)
    local keys, rank = {}, {}
    for i, k in ipairs(J.FIRST) do rank[k] = i end
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys, function(a, b)
        local ra, rb = rank[a], rank[b]
        if ra and rb then return ra < rb end
        if ra or rb then return ra ~= nil end
        return a < b
    end)
    return keys
end

Encode = function(v, out, depth, seen)
    local t = type(v)
    if v == nil then out[#out + 1] = "null"
    elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif t == "number" then out[#out + 1] = Num(v)
    elseif t == "string" then out[#out + 1] = Str(v)
    elseif t == "table" then
        if depth > J.MAX_DEPTH then error("json: nested too deep", 0) end
        if seen[v] then error("json: a table inside itself", 0) end
        seen[v] = true
        if next(v) == nil then out[#out + 1] = "[]"
        elseif IsArray(v) then
            out[#out + 1] = "["
            for i = 1, #v do
                if i > 1 then out[#out + 1] = "," end
                Encode(v[i], out, depth + 1, seen)
            end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for _, k in ipairs(Keys(v)) do
                local val = v[k]
                if val == nil then val = v[tonumber(k)] end
                if type(val) ~= "function" and type(val) ~= "userdata" then
                    if not first then out[#out + 1] = "," end
                    first = false
                    out[#out + 1] = Str(k)
                    out[#out + 1] = ":"
                    Encode(val, out, depth + 1, seen)
                end
            end
            out[#out + 1] = "}"
        end
        seen[v] = nil
    else
        out[#out + 1] = "null"   -- functions, userdata and threads have no JSON form (reports hold none)
    end
end

function J.Encode(v)
    local out = {}
    Encode(v, out, 1, {})
    return concat(out)
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
function J.Adler32(text)
    local LD = LibStub and LibStub("LibDeflate", true)
    if LD and LD.Adler32 then return format("%08x", LD:Adler32(text)) end
    local a, b = 1, 0
    for i = 1, #text do
        a = (a + byte(text, i)) % 65521
        b = (b + a) % 65521
    end
    return format("%08x", b * 65536 + a)
end

-- A piece ends before a byte that continues a UTF-8 character, so no character is split between two pieces.
local function Cut(text, from, size)
    local stop = math.min(#text, from + size - 1)
    if stop < #text then
        while stop > from do
            local c = byte(text, stop + 1)
            if c and c >= 0x80 and c < 0xC0 then stop = stop - 1 else break end
        end
    end
    return stop
end

-- text -> { { index, count, header, body, text } }; `label` names the report in each header.
function J.Pieces(text, sizeBytes, label)
    local whole = J.Adler32(text)
    local bodies = {}
    local from = 1
    if #text == 0 then bodies[1] = "" end
    while from <= #text do
        local stop = Cut(text, from, sizeBytes)
        bodies[#bodies + 1] = text:sub(from, stop)
        from = stop + 1
    end
    local out = {}
    for i, body in ipairs(bodies) do
        local header = format("TWICHUI-DIAGNOSTICS piece %d/%d of %s | report %d bytes, adler32 %s | this piece adler32 %s | join the text after each first line, in order",
            i, #bodies, label or "report", #text, whole, J.Adler32(body))
        out[i] = { index = i, count = #bodies, header = header, body = body, text = header .. "\n" .. body }
    end
    return out, whole
end

-- The pieces' texts (headers included) back to the report, checked: text, or nil and a reason.
function J.Join(texts)
    local parts, total, whole, count = {}, nil, nil, nil
    for i, t in ipairs(texts) do
        local header, body = t:match("^([^\n]*)\n(.*)$")
        if not header then return nil, "piece " .. i .. " has no header" end
        local idx, n, size, sum, own = header:match("piece (%d+)/(%d+) of .- | report (%d+) bytes, adler32 (%x+) | this piece adler32 (%x+)")
        if not idx then return nil, "piece " .. i .. " has an unreadable header" end
        idx, n = tonumber(idx), tonumber(n)
        if idx ~= i then return nil, "pieces out of order" end
        count, total, whole = count or n, total or tonumber(size), whole or sum
        if n ~= count or sum ~= whole then return nil, "pieces from different reports" end
        if J.Adler32(body) ~= own then return nil, "piece " .. i .. " changed" end
        parts[i] = body
    end
    if #parts ~= count then return nil, "pieces missing" end
    local text = concat(parts)
    if #text ~= total or J.Adler32(text) ~= whole then return nil, "the joined report does not match" end
    return text
end
