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
Read("client.runner.pause-probe", function(t)
    local RN = TL.Runner
    local started = RN.Now()
    t:Wait(2)
    local elapsed = RN.Now() - started
    t:Check(elapsed >= 2, "the pause lasted at least the 2 s asked for")
    t:Fact("client.runner.pause_2s_measured_ms", ("%.0f"):format(elapsed * 1000))
end)
