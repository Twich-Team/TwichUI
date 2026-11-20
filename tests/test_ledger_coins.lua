-- Coin presentation of the Gold Ledger (TwichUI_Workshop/Coins.lua): exact copper in, coin artwork markup out. Pure string work, no frames.
local function Check(v, m) if not v then error(m or "check failed", 2) end end
local function Same(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local function Load(env)
    env = env or {}
    env.TwichUI = { Workshop = { UI = {} } }
    env.math, env.string, env.table, env.type, env.tostring, env.tonumber, env.pcall, env.ipairs, env.pairs = math, string, table, type, tostring, tonumber, pcall, ipairs, pairs
    env.select = select
    local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/Coins.lua")); setfenv(chunk, env); chunk("TwichUI_Workshop", {})
    return env.TwichUI.Workshop.UI.Coins, env
end

local GOLD, SILVER, COPPER = "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon"
local function Icon(path, h) return ("|T%s:%d:%d:2:0|t"):format(path, h, h) end

do
    local Co = Load()
    -- exact parts
    local neg, g, s, c = Co.Split(1235524); Same(neg, false); Same(g, 123); Same(s, 55); Same(c, 24)
    neg, g, s, c = Co.Split(-97 * 100 - 85); Same(neg, true); Same(g, 0); Same(s, 97); Same(c, 85)
    for _, bad in ipairs({ "5", 1.5, 0 / 0, math.huge, -math.huge, 2 ^ 53 + 2, true }) do Same(Co.Split(bad), nil, "unsupported amount " .. tostring(bad)); Same(Co.Text(bad), "", "no text for " .. tostring(bad)) end
    Same(Co.Split(nil), nil)

    -- defaults without the native helper
    Same(Co.Paths().gold, GOLD); Same(Co.Paths().native, false)
    -- the shapes from the brief: gold + silver + copper, negative silver + copper, copper only
    Same(Co.Text(15524, { height = 12 }), "1" .. Icon(GOLD, 12) .. " 55" .. Icon(SILVER, 12) .. " 24" .. Icon(COPPER, 12))
    Same(Co.Text(-9785, { height = 12 }), "-97" .. Icon(SILVER, 12) .. " 85" .. Icon(COPPER, 12))
    Same(Co.Text(16, { height = 12 }), "16" .. Icon(COPPER, 12))
    -- zero, single denominations, zero parts left out, sign
    Same(Co.Text(0, { height = 12 }), "0" .. Icon(COPPER, 12)); Same(Co.Text(0, { height = 12, signed = true }), "0" .. Icon(COPPER, 12), "zero has no sign")
    Same(Co.Text(30000, { height = 12 }), "3" .. Icon(GOLD, 12)); Same(Co.Text(500, { height = 12 }), "5" .. Icon(SILVER, 12))
    Same(Co.Text(10005, { height = 12 }), "1" .. Icon(GOLD, 12) .. " 5" .. Icon(COPPER, 12), "a zero silver part is left out")
    Same(Co.Text(10000, { height = 12, signed = true }), "+1" .. Icon(GOLD, 12)); Same(Co.Text(-10000, { height = 12, signed = true }), "-1" .. Icon(GOLD, 12))
    -- thousands, large values, icon heights
    Same(Co.Text(1234567 * 10000 + 8901, { height = 14 }), "1,234,567" .. Icon(GOLD, 14) .. " 89" .. Icon(SILVER, 14) .. " 1" .. Icon(COPPER, 14))
    Check(Co.Text(Co.MAX, { height = 12 }):find("^900,719,925,474" .. "|T"), "the largest exact amount is shown with every digit")
    Same(Co.Text(10000, { height = 20 }), "1" .. Icon(GOLD, 20)); Same(Co.Text(10000, { height = 3 }), "1" .. Icon(GOLD, 8), "an icon is never smaller than 8"); Same(Co.Text(10000, { height = 99 }), "1" .. Icon(GOLD, 32))
    -- letters: the plain fallback
    Co.SetIcons(false)
    Same(Co.Text(15524), "1g 55s 24c"); Same(Co.Text(-9785), "-97s 85c"); Same(Co.Text(0), "0c"); Same(Co.Text(30000, { signed = true }), "+3g")
    Co.SetIcons(true)

    -- exactness: every figure parses back to the copper it came from (letters, full level), for many amounts
    Co.SetIcons(false)
    local seed = 12345
    local function Rand(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
    for _ = 1, 400 do
        local v = Rand(4) == 0 and Rand(2000) or (Rand(5000) * 10000 + Rand(10000))
        if Rand(2) == 0 then v = -v end
        local text = Co.Text(v)
        local neg = text:sub(1, 1) == "-"
        local total = 0
        for num, unit in text:gmatch("([%d,]+)([gsc])") do
            num = tonumber((num:gsub(",", "")))
            total = total + num * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        end
        Same(neg and -total or total, v, "round trip of " .. v .. " (" .. text .. ")")
    end
    Co.SetIcons(true)

    -- compact levels never invent value and never claim to be exact: level 1 is exact; every other level is marked by the caller
    Co.SetIcons(false)
    Same(Co.Text(1234567 * 10000 + 5524, { level = 1 }), "1,234,567g 55s 24c")
    Same(Co.Text(1234567 * 10000 + 5524, { level = 2 }), "1,234,567g 55s")
    Same(Co.Text(1234567 * 10000 + 5524, { level = 3 }), "1,234,567g")
    Same(Co.Text(1234567 * 10000 + 5524, { level = 4 }), "1.2M" .. "g")
    Same(Co.Text(2500 * 10000, { level = 4 }), "2.5kg"); Same(Co.Text(2000 * 10000, { level = 4 }), "2kg"); Same(Co.Text(999 * 10000 + 99, { level = 4 }), "999g")
    Same(Co.Text(1234, { level = 2 }), "12s"); Same(Co.Levels(0), 1); Same(Co.Levels(77), 1); Same(Co.Levels(1234), 3); Same(Co.Levels(10000), 3); Same(Co.Levels(2000 * 10000), 4); Same(Co.Levels("x"), 0)
    Co.SetIcons(true)

    -- fitting into a width: font a little smaller first, then compact levels; the exact amount is kept for the hover
    local fs = { text = "" }
    function fs:SetText(t) self.text = t end
    local function Measure(f) return #(f.text:gsub("|T[^|]*|t", "XX")) * 7 end   -- an icon counts as two characters
    local size, level = Co.Fit(fs, 9876543210, { size = 19, min = 15, width = 4000, measure = Measure })
    Same(size, 19); Same(level, 1); Same(fs.exact, 9876543210); Same(fs.compact, false)
    size, level = Co.Fit(fs, 9876543210, { size = 19, min = 15, width = 130, measure = Measure })
    Check(size >= 15, "never below the minimum size"); Check(level > 1, "compacted when it does not fit"); Same(fs.exact, 9876543210, "the exact amount survives compaction"); Same(fs.compact, true)
    Check(Measure(fs) <= 130 or level == Co.Levels(9876543210), "it fits, or it is as compact as it gets")
    -- a short amount in a narrow field simply fits
    size, level = Co.Fit(fs, 16, { size = 13, min = 10, width = 60, measure = Measure })
    Same(level, 1)

    -- axis: one denomination
    Same(Co.Axis(0, 10), "0" .. Icon(GOLD, 10)); Same(Co.Axis(30000, 10), "3" .. Icon(GOLD, 10)); Same(Co.Axis(-50000, 10), "-5" .. Icon(GOLD, 10))
    Same(Co.Axis(5000, 10), "50" .. Icon(SILVER, 10)); Same(Co.Axis(42, 10), "42" .. Icon(COPPER, 10)); Same(Co.Axis(2500000, 10), "250" .. Icon(GOLD, 10)); Same(Co.Axis(150000000, 10), "15k" .. Icon(GOLD, 10))
end

-- The client's own helper: its artwork paths are read; everything else about it is ignored.
do
    local texts = "1|TInterface\\Custom\\GoldCoin:14:14:2:0|t 2|TInterface\\Custom\\SilverCoin:14:14:2:0|t 3|TInterface\\Custom\\CopperCoin:14:14:2:0|t"
    local Co = Load({ C_CurrencyInfo = { GetCoinTextureString = function(amount, h) return texts end } })
    Same(Co.Paths().gold, "Interface\\Custom\\GoldCoin"); Same(Co.Paths().silver, "Interface\\Custom\\SilverCoin"); Same(Co.Paths().copper, "Interface\\Custom\\CopperCoin"); Same(Co.Paths().native, true)
    Same(Co.Text(10000, { height = 12 }), "1|TInterface\\Custom\\GoldCoin:12:12:2:0|t")
    -- a helper that errors, answers something else, or is missing falls back to the standard artwork
    for _, helper in ipairs({ function() error("boom") end, function() return "no textures" end, function() return "1|TInterface\\A:14:14|t" end, function() return 5 end }) do
        local c2 = Load({ C_CurrencyInfo = { GetCoinTextureString = helper } })
        Same(c2.Paths().gold, GOLD, "fallback"); Same(c2.Paths().native, false)
    end
    local c3 = Load({ C_CurrencyInfo = {} }); Same(c3.Paths().silver, SILVER)
    local secret = Load({ issecretvalue = function() return true end, C_CurrencyInfo = { GetCoinTextureString = function() return texts end } })
    Same(secret.Paths().gold, GOLD, "a secret value is never read"); Same(secret.Split(5), nil, "a secret amount is never formatted")
end

print("LEDGER COINS OK")
