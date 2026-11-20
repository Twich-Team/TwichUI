-- TwichUI Workshop: coin presentation for the Gold Ledger (UI.Coins)
-- Shows exact copper as gold, silver and copper COIN ARTWORK (inline textures) instead of the letters g, s and c. Presentation only:
-- LedgerQuery.Money stays the pure text form used by queries, tests and plain descriptions, and every figure here is built from the same
-- exact integer copper; nothing is rounded except where a deliberate compact level is chosen, and a compacted figure always keeps its
-- exact value (fs.exact) for the hover.
--
-- The artwork. The game's own helper C_CurrencyInfo.GetCoinTextureString(amount, fontHeight) (Forever UI source,
-- CurrencyInfoDocumentation.lua; the default UI's money frames use the same textures, and so do other Forever addons) returns text with
-- one |T...|t texture per denomination, without a thousands separator and always with zero parts left out in its own way. Its text is not
-- reused: it cannot group digits, sign an amount or compact it. Its texture PATHS are, read once from a probe amount, so the artwork is
-- the client's own wherever the helper exists; where it does not (or answers something unexpected) the standard Interface\MoneyFrame
-- paths are used. The deprecated global GetCoinTextureString is never called.
--
-- Compact levels (see Co.Fit): 1 every denomination; 2 no copper once there is a larger part; 3 the largest part only; 4 that part
-- abbreviated (1.2k, 3.4M gold). A figure is never silently cut: a compacted one is marked on the font string (fs.compact) and the
-- exact amount is kept in fs.exact for the tooltip.

local R = TwichUI
local W = R.Workshop
local UI = W.UI
local Co = { MAX = 9007199254740991 }
UI.Coins = Co

Co.DEFAULT = {
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    silver = "Interface\\MoneyFrame\\UI-SilverIcon",
    copper = "Interface\\MoneyFrame\\UI-CopperIcon",
}
local LETTER = { gold = "g", silver = "s", copper = "c" }

local paths, icons = nil, true

-- The artwork paths: from the client's own helper when it answers, else the standard ones. Cached.
function Co.Paths()
    if paths then return paths end
    local found
    local C = C_CurrencyInfo
    if C and type(C.GetCoinTextureString) == "function" then
        local ok, text = pcall(C.GetCoinTextureString, 10203, 14)   -- 1 gold, 2 silver, 3 copper: all three denominations
        if ok and type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
            local list = {}
            for path in text:gmatch("|T([^:|]+):") do list[#list + 1] = path end
            if #list == 3 and not list[1]:find("[%c]") then found = { gold = list[1], silver = list[2], copper = list[3] } end
        end
    end
    paths = found or Co.DEFAULT
    paths.native = found ~= nil
    return paths
end
function Co.Reset() paths = nil end                      -- (the tests)
function Co.SetPaths(p) paths = p end                    -- (the tests)
function Co.SetIcons(on) icons = on ~= false end         -- false: letters (g s c); a plain fallback and the tests

---------------------------------------------------------------------------
-- Exact parts
---------------------------------------------------------------------------
local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- negative, gold, silver, copper of a whole number of copper; nil for anything else (NaN, infinity, fractions, text, a secret value)
function Co.Split(copper)
    copper = Plain(copper)
    if type(copper) ~= "number" or copper ~= copper or copper == math.huge or copper == -math.huge or math.floor(copper) ~= copper then return nil end
    if copper > Co.MAX or copper < -Co.MAX then return nil end
    local neg = copper < 0
    local n = neg and -copper or copper
    return neg, math.floor(n / 10000), math.floor(n / 100) % 100, n % 100
end

local function Group(n)
    local text = ("%d"):format(n)
    local k
    repeat text, k = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return text
end

-- The inline texture of one denomination at a font height (an icon about as tall as the text, a little space before it).
function Co.Icon(kind, height)
    local h = math.max(8, math.min(32, math.floor((tonumber(height) or 12) + 0.5)))
    return ("|T%s:%d:%d:2:0|t"):format(Co.Paths()[kind], h, h)
end

local function Unit(kind, number, height)
    if icons then return number .. Co.Icon(kind, height) end
    return number .. LETTER[kind]
end

-- How many compact levels a figure has (1 when there is nothing to leave out).
function Co.Levels(copper)
    local neg, g, s, c = Co.Split(copper)
    if neg == nil then return 0 end
    if g > 0 then return (g >= 1000) and 4 or 3 end
    if s > 0 then return 3 end
    return 1
end

-- The text of an amount. o: signed (a "+" on gains), height (the font size the icons match), level (compact level, default 1).
function Co.Text(copper, o)
    o = o or {}
    local neg, g, s, c = Co.Split(copper)
    if neg == nil then return "" end
    local height, level = o.height or 12, o.level or 1
    local parts = {}
    if g > 0 then
        if level >= 4 and g >= 1000 then
            local text
            if g >= 1000000 then text = ("%.1fM"):format(g / 1000000) else text = ("%.1fk"):format(g / 1000) end
            parts[#parts + 1] = Unit("gold", (text:gsub("%.0([kM])$", "%1")), height)
        else
            parts[#parts + 1] = Unit("gold", Group(g), height)
        end
        if level < 3 and s > 0 then parts[#parts + 1] = Unit("silver", s, height) end
        if level < 2 and c > 0 then parts[#parts + 1] = Unit("copper", c, height) end
    elseif s > 0 then
        parts[#parts + 1] = Unit("silver", s, height)
        if level < 2 and c > 0 then parts[#parts + 1] = Unit("copper", c, height) end
    else
        parts[#parts + 1] = Unit("copper", c, height)
    end
    local text = table.concat(parts, " ")
    if neg then return "-" .. text end
    if o.signed and (g > 0 or s > 0 or c > 0) then return "+" .. text end
    return text
end

-- One denomination only, for a chart axis: the biggest unit that fits the value, rounded ("250" + gold, "50" + silver, "12k" + gold).
function Co.Axis(copper, height)
    local neg, g, s, c = Co.Split(copper)
    if neg == nil then return "" end
    local n = math.abs(copper)
    local text
    if n == 0 then text = Unit("gold", "0", height)
    elseif n >= 100000000 then text = Unit("gold", ("%dk"):format(math.floor(n / 10000 / 1000 + 0.5)), height)
    elseif n >= 10000 then text = Unit("gold", Group(math.floor(n / 10000 + 0.5)), height)
    elseif n >= 100 then text = Unit("silver", math.floor(n / 100 + 0.5), height)
    else text = Unit("copper", n, height) end
    return neg and ("-" .. text) or text
end

---------------------------------------------------------------------------
-- On a font string
---------------------------------------------------------------------------
-- Sets the text and remembers the exact amount (fs.exact) for the hover. size: the font size the icons are cut for.
function Co.Set(fs, copper, o)
    o = o or {}
    local text = Co.Text(copper, { signed = o.signed, height = o.size or 12, level = o.level })
    fs.exact, fs.compact, fs.level = Plain(copper), (o.level or 1) > 1, o.level or 1
    fs:SetText(text)
    return text
end

-- Fits an amount into `width`: first a font a little smaller (never below `min`), then the compact levels, so a figure is never
-- cut off and never made unreadable. measure(fs) overrides the width read (the tests). Returns the size and level used.
function Co.Fit(fs, copper, o)
    local size, min = o.size or 12, o.min or math.max(10, (o.size or 12) - 3)
    local role = o.role
    local function Try(s, level)
        if UI.CL and UI.CL.Font and not o.keepFont then UI.CL.Font(fs, s, false, role) end
        Co.Set(fs, copper, { signed = o.signed, size = s, level = level })
        local w = o.measure and o.measure(fs) or (fs.GetStringWidth and fs:GetStringWidth()) or 0
        return w <= (o.width or math.huge)
    end
    for s = size, min, -1 do
        if Try(s, 1) then return s, 1 end
    end
    local top = Co.Levels(copper)
    for level = 2, math.max(2, top) do
        if Try(min, level) then return min, level end
    end
    return min, math.max(1, top)
end

-- The amount as a line of a tooltip (plain words around it; the game's tooltip draws inline textures).
function Co.Line(label, copper, o)
    return label .. Co.Text(copper, { signed = o and o.signed, height = (o and o.height) or 12 })
end
