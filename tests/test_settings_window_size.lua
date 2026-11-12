dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- The settings window's size bounds (TwichUI_Settings/Window.lua: UI.SizeBounds, UI.ClampSize): the minimum the
-- layout needs, the screen as the maximum (in the window's own units, so a scale counts), and what a saved width or
-- height that is not a usable number turns into. The window itself is not built here (see the simulator for that).

local failures = 0
local function check(name, ok) if not ok then failures = failures + 1; print("FAIL: " .. name) end end

local c = SettingsClient()
local UI = c.TwichUI.SettingsUI

local minW, minH, maxW, maxH = UI.SizeBounds(1920, 1080, 1)
check("minimum is the first width and a readable height", minW == 936 and minH == 480)
check("maximum leaves a margin on the screen", maxW == 1920 - 48 and maxH == 1080 - 48)

-- a scale below 1 makes the window's units larger than the screen's, so more fits
local _, _, sW, sH = UI.SizeBounds(1920, 1080, 0.5)
check("a smaller scale allows a larger size", sW == 3840 - 48 and sH == 2160 - 48)

-- a screen too small for the minimum never makes the maximum smaller than it
local _, _, tW, tH = UI.SizeBounds(800, 600, 1)
check("the minimum wins on a tiny screen (width; the height keeps its margin)", tW == 936 and tH == 552)

local function Clamp(...) local w, h = UI.ClampSize(...); return w .. "x" .. h end
check("the first size is kept", Clamp(936, 660, 1920, 1080, 1) == "936x660")
check("a valid size is kept", Clamp(1200, 800, 1920, 1080, 1) == "1200x800")
check("too small is raised to the minimum", Clamp(300, 100, 1920, 1080, 1) == "936x480")
check("too large is cut to the screen", Clamp(9000, 9000, 1920, 1080, 1) == "1872x1032")
check("the two sides are independent", Clamp(9000, 600, 1920, 1080, 1) == "1872x600")
check("a larger screen scale cuts a size that no longer fits", Clamp(1800, 1000, 1920, 1080, 1.25) == "1488x816")
check("fractions are rounded", Clamp(1000.4, 700.6, 1920, 1080, 1) == "1000x701")

-- not a size at all: the first size, for that side only
check("a string is the first size", Clamp("wide", "tall", 1920, 1080, 1) == "936x660")
check("nil is the first size", Clamp(nil, nil, 1920, 1080, 1) == "936x660")
check("NaN is the first size", Clamp(0 / 0, 800, 1920, 1080, 1) == "936x800")
check("infinity is the first size", Clamp(math.huge, -math.huge, 1920, 1080, 1) == "936x660")
check("a table is the first size", Clamp({}, 700, 1920, 1080, 1) == "936x700")

-- an unusable screen or scale does not break the clamp
check("no screen: only the minimum applies", Clamp(5000, 5000, nil, nil, nil) == "5000x5000")
check("a bad scale counts as 1", Clamp(5000, 5000, 1920, 1080, 0) == "1872x1032")

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED")
