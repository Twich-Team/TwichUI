-- The map's wheel-zoom and easing arithmetic (map/ViewMath.lua): VM.Step (the next scale for N wheel
-- notches of a step percent, clamped to [lo, hi]), VM.Ease, VM.LogLerp and VM.Lerp, each checked directly
-- against hand-computed numbers. Loads only ViewMath, no game frames.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
local chunk = assert(loadfile(ROOT .. "map/ViewMath.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local VM = c.TwichUI.MapViewMath

local function near(a, b, tol)
    return math.abs(a - b) <= (tol or 1e-9)
end

---------------------------------------------------------------------------
-- VM.Step: scale * (1 + step/100) ^ notches, clamped to [lo, hi]
---------------------------------------------------------------------------
-- positive notches, no clamp: 1 * 1.1^2 = 1.21
assert(near(VM.Step(1, 2, 10, 0.1, 10), 1.21), "Step: two notches up of 10% from 1")
-- negative notches, no clamp: 1 * 1.1^-2 = 1/1.21
assert(near(VM.Step(1, -2, 10, 0.1, 10), 1 / 1.21), "Step: two notches down of 10% from 1")
-- zero notches: unchanged
assert(VM.Step(5, 0, 10, 0.1, 10) == 5, "Step: zero notches leaves the scale unchanged")
-- clamped at hi: 10 * 1.1^5 = 16.1051 -> 10
assert(VM.Step(10, 5, 10, 0.1, 10) == 10, "Step: clamped at the hi limit")
-- clamped at lo: 0.1 * 1.1^-5 = 0.06209 -> 0.1
assert(VM.Step(0.1, -5, 10, 0.1, 10) == 0.1, "Step: clamped at the lo limit")

---------------------------------------------------------------------------
-- VM.Ease: 1 - (1 - t)^3, with t clamped to 0..1
---------------------------------------------------------------------------
assert(VM.Ease(0) == 0, "Ease: 0 at t=0")
assert(VM.Ease(1) == 1, "Ease: 1 at t=1")
assert(near(VM.Ease(0.5), 0.875), "Ease: 0.875 at t=0.5")
assert(VM.Ease(-1) == 0, "Ease: clamps t below 0 to 0")
assert(VM.Ease(2) == 1, "Ease: clamps t above 1 to 1")
-- increasing on 0..1
local prev = VM.Ease(0)
for i = 1, 20 do
    local t = i / 20
    local v = VM.Ease(t)
    assert(v >= prev, "Ease: increasing at t=" .. t)
    prev = v
end

---------------------------------------------------------------------------
-- VM.LogLerp: a * (b/a)^t  (geometric interpolation)
---------------------------------------------------------------------------
assert(VM.LogLerp(1, 4, 0) == 1, "LogLerp: a at t=0")
assert(VM.LogLerp(1, 4, 1) == 4, "LogLerp: b at t=1")
assert(near(VM.LogLerp(1, 4, 0.5), 2), "LogLerp: geometric mean at t=0.5")
assert(VM.LogLerp(2, 8, 0) == 2, "LogLerp: a at t=0 (2..8)")
assert(VM.LogLerp(2, 8, 1) == 8, "LogLerp: b at t=1 (2..8)")
assert(near(VM.LogLerp(2, 8, 0.5), 4), "LogLerp: geometric mean at t=0.5 (2..8)")

---------------------------------------------------------------------------
-- VM.Lerp: a + (b - a) * t  (linear interpolation)
---------------------------------------------------------------------------
assert(VM.Lerp(1, 5, 0) == 1, "Lerp: a at t=0")
assert(VM.Lerp(1, 5, 1) == 5, "Lerp: b at t=1")
assert(VM.Lerp(1, 5, 0.5) == 3, "Lerp: midpoint at t=0.5")
assert(VM.Lerp(2, 10, 0) == 2, "Lerp: a at t=0 (2..10)")
assert(VM.Lerp(2, 10, 1) == 10, "Lerp: b at t=1 (2..10)")
assert(VM.Lerp(2, 10, 0.5) == 6, "Lerp: midpoint at t=0.5 (2..10)")

print("MAP VIEWMATH STEP PASSED")
