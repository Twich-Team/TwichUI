dofile(TESTS .. "harness.lua")
-- D.RedLines: how many red lines an item tooltip shows, i.e. how many
-- "you can't use this" requirements the game lists. Offline only.
-- IsRed, IsRedColor and IsRedText are local to gear/Data.lua, so they are
-- checked through D.RedLines: data lines exercise IsRedColor, the named
-- text frames exercise IsRedText.
local c = MakeClient("Rich", {"!!!TwichUI"})

for _, f in ipairs({ "gear/Weights.lua", "gear/Prefs.lua", "gear/Data.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local D = c.TwichUI.GearData
assert(type(D.RedLines) == "function", "D.RedLines is defined")

-- The game's red, the same value test_gear.lua feeds through the pipeline.
local RED = { r = 1, g = 0.125, b = 0.125 }

-- A tooltip that must never be touched when the data lines report red.
local poison = {}
local poisonTouched = false
function poison:GetName() poisonTouched = true; return nil end
function poison:NumLines() poisonTouched = true; return 0 end

-- Data lines: each line with a red leftColor or rightColor counts once.
assert(D.RedLines({ { leftColor = RED } }, poison) == 1, "one red leftColor line counts once")
assert(D.RedLines({ { rightColor = RED } }, poison) == 1, "a red rightColor line counts too")
assert(D.RedLines({ { leftColor = RED }, { rightColor = RED } }, poison) == 2, "two red lines count as two")
assert(D.RedLines({ { leftColor = RED, rightColor = RED } }, poison) == 1, "both sides red is still one line")
assert(D.RedLines({ { leftColor = RED }, { leftText = "plain" }, { rightColor = RED } }, poison) == 2, "non-red and missing colors are ignored")
assert(not poisonTouched, "data lines reporting red are answered without touching the tooltip")

-- IsRed's thresholds: r must be above 0.9, g and b below 0.3, all numeric.
assert(D.RedLines({ { leftColor = { r = 0.9, g = 0, b = 0 } } }, poison) == 0, "r = 0.9 is not red (must be above)")
assert(D.RedLines({ { leftColor = { r = 0.91, g = 0.29, b = 0.29 } } }, poison) == 1, "just inside the thresholds is red")
assert(D.RedLines({ { leftColor = { r = 1, g = 0.3, b = 0 } } }, poison) == 0, "g = 0.3 is not red (must be below)")
assert(D.RedLines({ { leftColor = { r = 1, g = 0, b = 0.3 } } }, poison) == 0, "b = 0.3 is not red (must be below)")
assert(D.RedLines({ { leftColor = { r = "1", g = 0, b = 0 } } }, poison) == 0, "non-numeric channels are not red")
assert(D.RedLines({ { leftColor = "red" } }, poison) == 0, "a color that is not a table is not red")

-- Zero red: no lines at all, or a tooltip without a name.
assert(D.RedLines({}, poison) == 0, "no data lines and no name: zero")
assert(D.RedLines(nil, nil) == 0, "nil lines and nil tooltip: zero")
assert(D.RedLines(nil, { GetName = function() return nil end }) == 0, "tooltip without a name: zero")

-- Fallback: data lines report none, so count the tooltip's named text frames,
-- one per line, TextLeft before TextRight.
local function TextFrame(text, color, shown)
  local f = {}
  function f:IsShown() return shown and true or false end
  function f:GetText() return text end
  function f:GetTextColor() if color then return color.r, color.g, color.b end end
  return f
end
local function Tip(name, n)
  local t = {}
  function t:GetName() return name end
  function t:NumLines() return n end
  return t
end
local function Frames()
  c.TipTextLeft1 = TextFrame("Requires Level 50", { r = 1, g = 1, b = 1 }, true)
  c.TipTextRight1 = TextFrame(nil, RED, true)
  c.TipTextLeft2 = TextFrame("Requires Level 50", RED, true)
  c.TipTextRight2 = TextFrame("Requires Warrior", RED, true)
  c.TipTextLeft3 = TextFrame("Requires Level 50", RED, false)
  c.TipTextRight3 = TextFrame("", RED, true)
end
Frames()
assert(D.RedLines({}, Tip("Tip", 3)) == 1, "named frames: line 1 white or nil text, line 2 red on both sides counts once, line 3 hidden or empty")
assert(D.RedLines({ { leftText = "plain" } }, Tip("Tip", 3)) == 1, "non-red data lines fall back to the tooltip too")
assert(D.RedLines({}, Tip("Tip", 1)) == 0, "NumLines bounds the scan: line 2 is never looked at")
c.TipTextLeft2 = nil
assert(D.RedLines({}, Tip("Tip", 3)) == 1, "a missing frame is not red: line 2's right side still counts")

print("TEST_GEAR_REDLINES PASSED")
