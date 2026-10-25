-- The shared-media borders (Aged, Rounded and Gilt Bronze, Dark Umber): each registered with LibSharedMedia
-- as a border, at a file that exists, never applied by itself; and each file is an edge image of the layout Blizzard's
-- backdrop draws (Backdrop.lua textureUVs): 256x32, eight 32 px cells (left, right, top, bottom, TL, TR, BL, BR) each
-- with its piece in the middle 28 px, painted at the frame's outside, empty inside, edges repeating without a seam.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI"})
c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()

local LSM = c.LibStub("LibSharedMedia-3.0")
assert(LSM.DefaultMedia.border == "None", "the default border is untouched")
local ms = c.TwichUI.MenuStyle

local CELL, GUT = 32, 2
local LEFT, RIGHT, TOP, BOTTOM, TL, TR, BL, BR = 0, 1, 2, 3, 4, 5, 6, 7

local function check(NAME, FILE, square)
  -- registered as a border, under the ASCII name, and nothing else
  local path = LSM:Fetch("border", NAME, true)
  assert(path == [[Interface\AddOns\!!!TwichUI\media\borders\]] .. FILE .. ".tga", "border path: " .. tostring(path))
  local listed = false
  for _, n in ipairs(LSM:List("border")) do if n == NAME then listed = true end end
  assert(listed, NAME .. " is listed with the other borders")
  assert(not LSM:IsValid("background", NAME) and not LSM:IsValid("font", NAME), "only registered as a border")
  assert(c.TwichUI.MediaBorders[NAME] == FILE .. ".tga")
  if ms and ms.Get then assert(ms.Get("borderTexture") ~= NAME, "never selected for anyone") end

  local f = assert(io.open(ROOT .. [[media/borders/]] .. FILE .. ".tga", "rb"), "the texture file is in the addon folder")
  local data = f:read("*a"); f:close()
  local function u16(o) return data:byte(o) + data:byte(o + 1) * 256 end
  assert(data:byte(1) == 0 and data:byte(2) == 0 and data:byte(3) == 2, "uncompressed true-colour TGA, no palette")
  local W, H, BPP, DESC = u16(13), u16(15), data:byte(17), data:byte(18)
  assert(W == 256 and H == 32 and BPP == 32 and DESC == 8, "256x32, 32-bit, 8 alpha bits, origin bottom-left")
  assert(#data == 18 + W * H * 4, "no trailing data")

  local function alpha(x, y) return data:byte(18 + ((H - 1 - y) * W + x) * 4 + 4) end   -- stored bottom-up
  local function px(cell, x, y) return alpha(cell * CELL + GUT + x, GUT + y) end         -- a cell's content pixel
  local function column(cell, x)
    local s = 0
    for y = 0, CELL - 1 do s = s + alpha(cell * CELL + x, y) end
    return s / CELL
  end

  for cell = 0, 7 do
    local s = 0
    for y = 0, 27 do for x = 0, 27 do s = s + px(cell, x, y) end end
    assert(s / 784 > 8, "cell " .. cell .. " is painted")
  end
  -- edges: painted outside, clear inside (left/top: x runs outside to inside; right/bottom: inside to outside)
  assert(column(LEFT, GUT + 4) > 240 and column(LEFT, CELL - 1 - GUT) < 10, "left edge")
  assert(column(RIGHT, CELL - 1 - GUT - 4) > 240 and column(RIGHT, GUT) < 10, "right edge")
  assert(column(TOP, GUT + 4) > 240 and column(TOP, CELL - 1 - GUT) < 10, "top edge")
  assert(column(BOTTOM, CELL - 1 - GUT - 4) > 240 and column(BOTTOM, GUT) < 10, "bottom edge")
  for _, cell in ipairs({ LEFT, RIGHT, TOP, BOTTOM }) do
    for x = 0, CELL - 1 do
      local top = alpha(cell * CELL + x, 0)
      for y = 1, CELL - 1 do assert(alpha(cell * CELL + x, y) == top, "edge " .. cell .. " repeats without a seam (column " .. x .. ")") end
    end
  end
  -- corners: painted along the two sides the corner is on, empty in the opposite (inside) corner
  assert(px(TL, 4, 24) > 200 and px(TL, 24, 4) > 200 and px(TL, 27, 27) == 0, "top left corner")
  assert(px(TR, 23, 24) > 200 and px(TR, 4, 4) > 200 and px(TR, 0, 27) == 0, "top right corner")
  assert(px(BL, 4, 4) > 200 and px(BL, 24, 23) > 200 and px(BL, 27, 0) == 0, "bottom left corner")
  assert(px(BR, 23, 4) > 200 and px(BR, 4, 23) > 200 and px(BR, 0, 0) == 0, "bottom right corner")
  if square then assert(px(TL, 20, 20) == 0 and px(BR, 8, 8) == 0, "the chamfer's inside is clear") end
  -- a corner's arm meets the straight edge: the same painted depth where they join
  for d = 0, 27 do
    assert(math.abs(px(TL, d, 27) - alpha(LEFT * CELL + GUT + d, 5)) <= 2, "TL's left arm continues the left edge")
    assert(math.abs(px(TL, 27, d) - alpha(TOP * CELL + GUT + d, 5)) <= 2, "TL's top arm continues the top edge")
    assert(math.abs(px(BR, 27 - d, 0) - alpha(RIGHT * CELL + GUT + 27 - d, 5)) <= 2, "BR's right arm continues the right edge")
    assert(math.abs(px(BR, 0, 27 - d) - alpha(BOTTOM * CELL + GUT + 27 - d, 5)) <= 2, "BR's bottom arm continues the bottom edge")
  end
end

check("TwichUI - Aged Bronze", "aged-bronze", true)
check("TwichUI - Rounded Bronze", "rounded-bronze", false)
check("TwichUI - Gilt Bronze", "gilt-bronze", false)
check("TwichUI - Dark Umber", "dark-umber", false)

print("MEDIA BORDER TEST PASSED")
