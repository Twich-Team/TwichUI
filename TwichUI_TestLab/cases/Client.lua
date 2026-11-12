-- TwichUI Test Lab: client facts (category "client", class readonly, no Workshop needed)
-- What the game's Lua and API surface do, observed in the running client. It reads only: no game state is changed. Values the client is not
-- documented to give are REPORTED (t:Fact), never asserted; only arithmetic that TwichUI's own code depends on is asserted.

local R = TwichUI
local TL = R.TestLab

TL.Category{ id = "client", label = "Client facts", blurb = "Lua number behaviour and which API this client has (read only)" }

local function Read(id, run) TL.Case{ id = id, cat = "client", class = "readonly", budget = 2, run = run } end

Read("client.lua.number-exactness", function(t)
    -- Prices are copper counts in doubles; TwichUI relies on whole numbers below 2^53 being exact
    -- 99999999999 x 10000 = 999,999,999,990,000 (under 2^53 = 9,007,199,254,740,992)
    t:Same(99999999999 * 10000, 999999999990000, "a product below 2^53 is exact")
    t:Same(("%.0f"):format(1e15), "1000000000000000", "%.0f writes a whole number in full")
    t:Same(("%.0f"):format(99999999999), "99999999999", "the largest buyout in full")
    t:Fact("client.lua.two_pow_53_plus_1_equal", tostring(2 ^ 53 + 1 == 2 ^ 53))
end)

Read("client.lua.division-by-zero", function(t)
    -- the offline interpreter gives inf; WoW's Lua may differ. Reported, not asserted.
    local zero = 0
    local ok, value = pcall(function() return 1 / zero end)
    t:Check(type(ok) == "boolean", "pcall answered")
    t:Fact("client.lua.div_zero_ok", ok)
    t:Fact("client.lua.div_zero_value", value)
    local okMod, mod = pcall(function() return 5 % zero end)
    t:Fact("client.lua.mod_zero_ok", okMod)
    t:Fact("client.lua.mod_zero_value", mod)
end)

-- How this client's Lua compares a NaN. The reference model once decided NaN by comparing (`v == v and v >= lo ...`) and, in the client, accepted
-- a NaN count that desktop Lua 5.1 rejects (market.reference.batch, seeds 7100008 and 7100012). These are the primitives, REPORTED so the
-- reason is on record; what is ASSERTED is only that the model's comparison-free test (REF.Finite) is right in this client.
Read("client.lua.nan-comparisons", function(t)
    local REF = TL.Reference
    local zero = 0
    local runtime = zero / zero            -- computed when it runs
    local literal = 0 / 0                  -- the form the fixtures write; the compiler may treat it differently
    local function B(x) return x and "T" or "F" end
    for _, pair in ipairs({ { "runtime", runtime }, { "literal", literal }, { "negated", -runtime }, { "inf", math.huge } }) do
        local name, v = pair[1], pair[2]
        t:Fact("client.nan." .. name .. ".tostring", tostring(v))
        t:Fact("client.nan." .. name .. ".cmp", ("v==v %s  v~=v %s  v<1 %s  v>1 %s  v<=1 %s  v>=1 %s  v==0 %s"):format(
            B(v == v), B(v ~= v), B(v < 1), B(v > 1), B(v <= 1), B(v >= 1), B(v == 0)))
        local okM, mod = pcall(function() return v % 1 end)
        local okF, fl = pcall(math.floor, v)
        t:Fact("client.nan." .. name .. ".arith", ("v%%1=%s  floor(v)=%s  floor(v)==v %s  v-v==0 %s"):format(
            okM and tostring(mod) or "raised", okF and tostring(fl) or "raised", B(okF and fl == v), B(v - v == 0)))
        if REF and REF.Finite then t:Fact("client.nan." .. name .. ".finite", B(REF.Finite(v))) end
    end
    if REF and REF.Finite then
        t:Check(REF.Finite(5) and REF.Finite(99999999999) and REF.Finite(-1.5) and REF.Finite(1e15), "ordinary numbers are finite")
        t:Check(not REF.Finite(runtime) and not REF.Finite(literal) and not REF.Finite(-runtime), "a NaN is not finite, however it was made")
        t:Check(not REF.Finite(math.huge) and not REF.Finite(-math.huge), "nor is an infinity")
    end
end)

-- The NaN guard idioms the code base uses, asked of every kind of malformed number, in THIS client. What is ASSERTED is only that every idiom
-- accepts an ordinary number and that the comparison-free test (REF.Finite) rejects every NaN and infinity; what the others do with a NaN is
-- REPORTED (A accepted the value, R rejected it), because it depends on how this client compares a NaN (client.lua.nan-comparisons).
-- Production sites: the count guard is Observe.BagCount, Stock.Craft and Materials.Rows (their inputs are the game's item counts or a nil);
-- Reach.Num guards frame geometry in the Lab itself; the fixtures' idiom is Fixtures.lua Clamp/Rate/Whole. docs/workshop/testing-roadmap.md M6
-- has the audit table (where each input comes from and whether it can be malformed).
Read("client.lua.nan-guards", function(t)
    local REF = TL.Reference
    local zero = 0
    local runtime = zero / zero
    local forms = { { "nan", runtime }, { "lit", 0 / 0 }, { "neg", -runtime }, { "inf", math.huge }, { "-inf", -math.huge } }
    local idioms = {
        { "count_guard", "v ~= v or v < 0 rejects", function(v) return not (v ~= v or v < 0) end },
        { "reach_num", "v == v and v > -1e12 and v < 1e12 accepts", function(v) return v == v and v > -1e12 and v < 1e12 end },
        { "nan_only", "v ~= v rejects", function(v) return not (v ~= v) end },
        { "ref_finite", "REF.Finite (no comparison)", REF and REF.Finite or function() return true end },
    }
    for _, idiom in ipairs(idioms) do
        local parts = {}
        for _, f in ipairs(forms) do parts[#parts + 1] = f[1] .. "=" .. (idiom[3](f[2]) and "A" or "R") end
        t:Fact("client.nanguard." .. idiom[1], table.concat(parts, " "))
        t:Check(idiom[3](5) and idiom[3](0) and idiom[3](99999999999), idiom[1] .. " accepts ordinary numbers")
    end
    if REF and REF.Finite then
        for _, f in ipairs(forms) do t:Check(not REF.Finite(f[2]), "REF.Finite rejects " .. f[1]) end
    end
    t:Note("A = the idiom accepted the value, R = it rejected it. A NaN that an idiom accepts is a path to look at only if its input can be a NaN: see the audit table in docs/workshop/testing-roadmap.md (M6).")
end)

Read("client.lua.yield-across-pcall", function(t)
    -- The runner never yields inside a pcall, because stock Lua 5.1 refuses. This only reports what this client does.
    local co = coroutine.create(function() local ok = pcall(coroutine.yield) return ok end)
    local resumed, inner = coroutine.resume(co)
    local status = coroutine.status(co)
    local answer = "other"
    if status == "suspended" then answer = "allowed (it yielded)"
    elseif resumed and inner == false then answer = "refused (pcall returned an error)" end
    t:Fact("client.lua.yield_across_pcall", answer)
end)

Read("client.api.presence", function(t)
    for _, name in ipairs({ "GetTimePreciseSec", "debugprofilestop", "C_AddOnProfiler", "GetMouseFoci", "EnumerateFrames" }) do
        t:Fact("client.api." .. name, type(_G[name]))
    end
    t:Fact("client.clock.source", TL.Runner.ClockName())
end)

-- The Lab's own runner, observed in the client: a pause across frames, so that Stop can be tried by hand while it waits (the other cases
-- finish within a few frames). It reads the clock and nothing else.
-- The pause is a COOPERATIVE wait: the runner schedules no step for the case until the time has passed, so nothing is running meanwhile (this is
-- not a non-interruptible operation). Its budget is the pause plus headroom: a wait that ends a few milliseconds after the pause's own end
-- (the next frame) must not be reported as late.
TL.Case{ id = "client.runner.pause-probe", cat = "client", class = "readonly", budget = 4, run = function(t)
    local RN = TL.Runner
    local started = RN.Now()
    t:Wait(2)
    local elapsed = RN.Now() - started
    t:Check(elapsed >= 2, "the pause lasted at least the 2 s asked for")
    t:Fact("client.runner.pause_2s_measured_ms", ("%.0f"):format(elapsed * 1000))
end }
