-- TwichUI Workshop: names, limits and small checks
-- No game calls and no frames. The other files add to R.Workshop (W); the window file is last and marks it ready.
-- Plain() drops a "secret" value the game will not let an addon read, so nothing here ever compares, formats or saves one.

local R = TwichUI
local W = R.Workshop or {}
R.Workshop = W

W.ADDON = "TwichUI_Workshop"
W.SAVED_VERSION = 1      -- the shape of TwichUIDB.workshop; a higher number was written by a newer TwichUI and is left alone
W.MAX_QUEUE = 30         -- recipes in one character's queue
W.MAX_CRAFTS = 999       -- crafts of one recipe
W.MAX_QTY = 9999         -- one number of items (a material count, an output)
W.MAX_MATS = 16          -- different materials in one recipe
W.MAX_ID = 2147483647

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
W.Plain = Plain

-- Is v a finite number (not NaN, not an infinity)? Decided WITHOUT comparing v with anything. OBSERVED in WoW: Forever 1.60.1 build 70888
-- (Test Lab run, 2026-11-12): a NaN equals itself, equals 0, and is both less and greater than ordinary numbers, so no comparison tells a
-- NaN from a number there (desktop Lua says NaN ~= NaN and rejects it). A finite number prints as digits, a point, an exponent and signs
-- only; a NaN or an infinity prints with letters (nan, inf, -nan(ind), ...). Run this BEFORE any comparison of a value that came from
-- outside (an auction record, a game call); compare only what it accepted. A secret value is not a number here (Plain first).
function W.Finite(v)
    if type(v) ~= "number" then return false end
    return tostring(v):find("^[%d%.eE%+%-]+$") ~= nil
end
local Finite = W.Finite

-- A whole number from lo to hi, or nil (a secret, a fraction, NaN, an infinity, a string, out of range)
function W.Int(v, lo, hi)
    v = Plain(v)
    if not Finite(v) or v < lo or v > hi or math.floor(v) ~= v then return nil end
    return v
end

-- A held item count (bags, bank, guild bank): a whole number from 0 up, or nil. Unknown stays nil and is never zero. This is THE boundary every
-- count read from the game passes (Observe.BagCount) or is judged by (Materials.Rows, Stock.Craft): W.Int decides finiteness without a
-- comparison, so a NaN, an infinity (either sign), a fraction, a negative, a secret value and a non-number are all "not a count" in every
-- client. The old guard `n ~= n or n < 0` let a positive infinity through (it is not NaN and not negative) and, where a NaN compares oddly,
-- depended on the interpreter. OBSERVED: Forever 1.60.1 build 70888 (Test Lab core report): numeric.held.inf made a craft "ready".
function W.Count(v) return W.Int(v, 0, W.MAX_ID) end

-- Cuts a string to at most `max` bytes without leaving half of a multi-byte character at the end
local function Cut(s, max)
    if #s <= max then return s end
    local cut = s:sub(1, max)
    local i = #cut
    while i > 0 and cut:byte(i) >= 0x80 and cut:byte(i) < 0xC0 do i = i - 1 end
    if i > 0 and cut:byte(i) >= 0xC0 then
        local lead = cut:byte(i)
        local need = lead >= 0xF0 and 4 or (lead >= 0xE0 and 3 or 2)
        if #cut - i + 1 < need then cut = cut:sub(1, i - 1) end
    end
    return cut
end
W.Cut = Cut

-- Plain text: a string with control characters turned into spaces, trimmed, at most `max` bytes; nil if nothing is left
function W.Text(v, max)
    v = Plain(v)
    if type(v) ~= "string" then return nil end
    v = v:gsub("%c", " ")
    v = v:gsub("^%s+", "")
    v = v:gsub("%s+$", "")
    if v == "" then return nil end
    return Cut(v, max)
end

-- THE one allocation of owned items (Materials, Shopping and Opportunities all call it, so nothing is counted twice): `want` items are taken
-- from what is held, in the order they are easiest to get: the bags, then the player's bank, then the guild bank. A nil or negative amount
-- counts as none. Returns taken from bags, from the bank, from the guild bank, and what is still missing.
function W.Split(want, bags, bank, guild)
    want = (type(want) == "number" and want > 0) and want or 0
    local function Have(n) return (type(n) == "number" and n > 0) and n or 0 end
    local b = math.min(want, Have(bags))
    want = want - b
    local k = math.min(want, Have(bank))
    want = want - k
    local g = math.min(want, Have(guild))
    return b, k, g, want - g
end

-- The game's recipe difficulty (TradeskillRelativeDifficulty 0..3) in the words players know. The word always goes with the colour.
W.DIFFICULTY = {
    [0] = { word = "Orange", color = { 1, 0.50, 0.25 }, tip = "Orange: always gives a skill point." },
    [1] = { word = "Yellow", color = { 1, 0.82, 0 }, tip = "Yellow: often gives a skill point." },
    [2] = { word = "Green", color = { 0.25, 0.75, 0.25 }, tip = "Green: sometimes gives a skill point." },
    [3] = { word = "Grey", color = { 0.62, 0.62, 0.62 }, tip = "Grey: gives no skill points." },
}

local function Range(lo, hi)
    if lo == hi then return tostring(lo) end
    return lo .. "-" .. hi
end

-- What one craft makes: "2" or "2-3", or nil when the output isn't known
function W.PerCraft(outMin, outMax)
    if not outMin then return nil end
    return Range(outMin, outMax or outMin)
end

-- What `crafts` crafts are expected to make, or nil when the output isn't known
function W.Expected(outMin, outMax, crafts)
    if not outMin or not crafts then return nil end
    return Range(outMin * crafts, (outMax or outMin) * crafts)
end
