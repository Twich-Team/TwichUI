-- Synthetic reference prices for captures/benchmarks; never saved or installed in the client.
function FishingEconomyFixture(c)
    local gen = 1
    local w = { Active = function() return true end, UI = {}, Market = { Value = function() return nil, "nomarket" end } }
    c.TwichUI.Workshop = w
    w.Pricing = { Generation = function() return tostring(gen) end,
        Source = function() return { reference = true, label = "Synthetic Market reference", market = { key = "fixture", realm = "Fixture", side = "Alliance", at = 1800000000 } } end,
        Reference = function(id) return { market = id == 5498 and 101230 or 30 + id % 137, at = 1800000000 } end,
        Changed = function() gen = gen + 1 end }
    setfenv(assert(loadfile(REPO .. "TwichUI_Workshop/Coins.lua")), c)()
    c.FireEvent("ADDON_LOADED", "TwichUI_Workshop")
    return w
end
