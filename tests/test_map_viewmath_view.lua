-- The map view's arithmetic, direct: ClampCenter, ViewRect, RectView and FitScale (map/ViewMath.lua),
-- each checked against hand-computed numbers. Loads only ViewMath, no game frames.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
local chunk = assert(loadfile(ROOT .. "map/ViewMath.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local VM = c.TwichUI.MapViewMath

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end

---------------------------------------------------------------------------
-- ClampCenter: kept inside the Extents limits; an in-range centre stays; a
-- smaller-than-view axis is centred
---------------------------------------------------------------------------
do
  -- scale 1, the canvas twice the view: the limits are 0.25..0.75 on both axes
  assert(near(VM.ClampCenter(0.5, 0.5, 1000, 600, 2000, 1200, 1), 0.5), "in-range centre left alone")
  local cx, cy = VM.ClampCenter(0.3, 0.9, 1000, 600, 2000, 1200, 1)
  assert(near(cx, 0.3) and near(cy, 0.75), "clamped to the limits on both axes")
  cx, cy = VM.ClampCenter(-0.4, 1.7, 1000, 600, 2000, 1200, 1)
  assert(near(cx, 0.25) and near(cy, 0.75), "past the limits on both axes")
  -- the y axis: the map is smaller than the view there, so it is centred
  cx, cy = VM.ClampCenter(0.3, 0.9, 1000, 600, 2000, 400, 1)
  assert(near(cx, 0.3) and near(cy, 0.5), "centred on the axis where the map is smaller than the view")
  -- both axes smaller than the view
  cx, cy = VM.ClampCenter(0.1, 0.9, 1000, 600, 1000, 600, 0.5)
  assert(near(cx, 0.5) and near(cy, 0.5), "centred on both axes")
end

---------------------------------------------------------------------------
-- ViewRect: left, right, top, bottom around the centre; shrinks as scale grows
---------------------------------------------------------------------------
do
  local l, r, t, b = VM.ViewRect(0.5, 0.4, 1000, 600, 1000, 600, 1)
  assert(near(l, 0) and near(r, 1) and near(t, -0.1) and near(b, 0.9), "the view around the centre at scale 1")
  l, r, t, b = VM.ViewRect(0.5, 0.4, 1000, 600, 1000, 600, 2)
  assert(near(l, 0.25) and near(r, 0.75) and near(t, 0.15) and near(b, 0.65), "the view shrinks as scale grows")
end

---------------------------------------------------------------------------
-- RectView: nil for a rectangle with no area; otherwise the scale at which
-- it fills `fill` of the view (fill defaults to 1) and its midpoint
---------------------------------------------------------------------------
do
  assert(VM.RectView(0.2, 0.3, 0.2, 0.7, 1000, 600, 1000, 600) == nil, "zero width")
  assert(VM.RectView(0.2, 0.3, 0.6, 0.3, 1000, 600, 1000, 600) == nil, "zero height")
  local scale, u, v = VM.RectView(0.2, 0.3, 0.6, 0.7, 1000, 600, 1000, 600)
  assert(near(scale, 2.5) and near(u, 0.4) and near(v, 0.5), "fills the view (fill defaults to 1)")
  scale, u, v = VM.RectView(0.2, 0.3, 0.6, 0.7, 1000, 600, 1000, 600, 0.5)
  assert(near(scale, 1.25) and near(u, 0.4) and near(v, 0.5), "fill 0.5 leaves half the view")
  scale, u, v = VM.RectView(0.1, 0.2, 0.3, 0.6, 1000, 600, 1000, 600)
  assert(near(scale, 2.5) and near(u, 0.2) and near(v, 0.4), "the height-limited ratio and the midpoint")
end

---------------------------------------------------------------------------
-- FitScale: the smaller of the two ratios
---------------------------------------------------------------------------
do
  assert(near(VM.FitScale(1000, 600, 1000, 600), 1), "same shape")
  assert(near(VM.FitScale(800, 400, 1000, 600), 2 / 3), "the height ratio is smaller")
  assert(near(VM.FitScale(600, 400, 1000, 500), 0.6), "the width ratio is smaller")
end

print("MAP VIEWMATH VIEW PASSED")
