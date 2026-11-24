-- Fishing's small catch-card reveal: pooled, bounded, legible and quiet for repeats/reduced motion.
-- Handler/layout simulation only; not native rendering or game-client input.
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(ok, message) if not ok then failures = failures + 1; print("FAIL: " .. message) end end
local function Fresh()
    local c, W = FishingClient({ names = { [FISH1] = { "Raw Mithril Head Trout", 1 }, [PEARL] = { "Golden Pearl", 3 } } })
    W.Camera()
    c.TwichUI.RunCommand("fish mode")
    return c, W, c.TwichUI.Fishing
end

do
    local c, W, F = Fresh()
    local asked = 0
    F.Present.SetValueProvider(function(kind, id, q)
        if kind == "item" then asked = asked + 1; return "2g" end
    end)
    F.Toast.Push(FISH1, 1, "direct")
    local f = F.Toast.Active()[1]
    Check(f.title:GetText() == "Caught!" and f.entry.q == 1, "Fishing identity and quantity preserved")
    Check(f.value:IsShown() and f.value:GetText():find("Est. 2g", 1, true), "known estimate remains readable")
    Check(f.sheen:GetAlpha() == 0 and f.spark:GetAlpha() == 0, "light begins quietly, without a flash")
    W.Frames(0.4)
    Check(f.sheen:GetAlpha() > 0 and f.spark:GetAlpha() > 0, "one rim sweep and icon glint follow the reveal")
    Check(f.title:GetAlpha() == 1 and f.name:GetAlpha() == 1 and f.value:GetAlpha() == 1, "all text resolves promptly")
    W.Frames(0.7)
    Check(f.flourishDone and f.sheen:GetAlpha() == 0 and f.spark:GetAlpha() == 0, "effects finish within a second")
    local began, priced = f.arrivedAt, asked
    F.Toast.Push(FISH1, 2, "direct")
    Check(#F.Toast.Active() == 1 and f.entry.q == 3 and f.arrivedAt == began and f.flourishDone,
        "repeat catches update the existing quantity without replaying the flourish")
    Check(f.name:GetText():find("\195\1513", 1, true), "merged quantity stays in the established name treatment")
    W.Frames(1)
    Check(asked == priced + 1, "the value provider is asked for the merge, never during animation")
    F.Toast.Clear()
    Check(not f:IsShown() and f:GetScript("OnUpdate") == nil, "clearing detaches every active animation")
    -- The band already measured its geometry. Preview and animation must not
    -- rediscover width from a frame (the minimal Settings harness returns nil).
    f.GetWidth = function() error("toast must use its measured band geometry") end
    F.Toast.Push(PEARL, 1, "content")
    local t = F.Toast.Active()[1]
    W.Frames(0.3)
    Check(t == f and t.kind == "treasure" and t.title:GetText() == "Treasure!", "pooled notice is redressed for treasure")
    Check(t.spark:GetWidth() == 22 and t.spark:GetAlpha() > 0.65, "treasure gets a small warmer glint")
    F.Toast.Clear()
end

do
    local c, W, F = Fresh()
    F.Present.Configure("present.motion", false)
    F.Toast.Push(PEARL, 1, "content")
    local f = F.Toast.Active()[1]
    W.Frames(0.4)
    Check(f.slide == 0 and not f.moves and f.flourishDone, "reduced motion uses the existing fade without movement")
    Check(f.sheen:GetAlpha() == 0 and f.spark:GetAlpha() == 0, "reduced motion has no sweep or pulse")
    Check(f.title:GetAlpha() == 1 and f.name:GetAlpha() == 1, "text is not staggered with reduced motion")
    F.Toast.Clear()
    for id = 9900, 9914 do F.Toast.Push(id, 1, "direct") end
    local active, queue = F.Toast.Active()
    Check(#active == F.Toast.VISIBLE and #queue == F.Toast.QUEUE, "rapid mixed catches retain bounded stacking and queue")
    W.Frames(45)
    active, queue = F.Toast.Active()
    Check(#active == 0 and #queue == 0 and f:GetScript("OnUpdate") == nil, "queued notices complete and pooled frames stop updating")
end

if failures > 0 then error(failures .. " fishing toast polish checks failed") end
print("FISHING TOAST POLISH PASSED")
