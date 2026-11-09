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

-- A whole number from lo to hi, or nil (a secret, a fraction, NaN, a string, out of range)
function W.Int(v, lo, hi)
    v = Plain(v)
    if type(v) ~= "number" or v ~= v or v < lo or v > hi or math.floor(v) ~= v then return nil end
    return v
end

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
