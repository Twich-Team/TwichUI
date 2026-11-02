dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
local chunk = assert(loadfile(ROOT .. "map/ViewMath.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local VM = c.TwichUI.MapViewMath

-- Defined here, not read from VM, so a wrong VM constant is caught.
local TILE = 1600 / 3
local ORIGIN = 32 * TILE
local EPS = 0.001

local function at(wx, wy, col, row)
    local gotC, gotR = VM.TileAt(wx, wy)
    assert(gotC == col, string.format("TileAt(%s, %s) col: got %s, want %s", tostring(wx), tostring(wy), tostring(gotC), tostring(col)))
    assert(gotR == row, string.format("TileAt(%s, %s) row: got %s, want %s", tostring(wx), tostring(wy), tostring(gotR), tostring(row)))
end

-- A point just inside each side of the shared edges of tile (5, 7).
at(ORIGIN - 7 * TILE - EPS, ORIGIN - 5 * TILE, 5, 7)  -- just inside the north edge
at(ORIGIN - 8 * TILE + EPS, ORIGIN - 5 * TILE, 5, 7)  -- just inside the south edge
at(ORIGIN - 7 * TILE, ORIGIN - 5 * TILE - EPS, 5, 7)  -- just inside the west edge
at(ORIGIN - 7 * TILE, ORIGIN - 6 * TILE + EPS, 5, 7)  -- just inside the east edge

-- The world origin (0, 0) is the corner where four tiles meet; just inside each of the four.
at(ORIGIN - 32 * TILE + EPS, ORIGIN - 32 * TILE + EPS, 31, 31)
at(ORIGIN - 32 * TILE + EPS, ORIGIN - 32 * TILE - EPS, 32, 31)
at(ORIGIN - 32 * TILE - EPS, ORIGIN - 32 * TILE + EPS, 31, 32)
at(ORIGIN - 32 * TILE - EPS, ORIGIN - 32 * TILE - EPS, 32, 32)

-- A point where col and row differ, so a swapped axis shows.
at(ORIGIN - 9 * TILE, ORIGIN - 3 * TILE, 3, 9)

-- The four continent corners, just inside.
at(ORIGIN - EPS, ORIGIN - EPS, 0, 0)                                  -- north-west
at(ORIGIN - EPS, ORIGIN - 64 * TILE + EPS, 63, 0)                     -- north-east
at(ORIGIN - 64 * TILE + EPS, ORIGIN - EPS, 0, 63)                     -- south-west
at(ORIGIN - 64 * TILE + EPS, ORIGIN - 64 * TILE + EPS, 63, 63)        -- south-east

-- Just outside the continent: TileAt does not clamp.
at(ORIGIN + EPS, ORIGIN, 0, -1)        -- north of the north edge
at(ORIGIN - 64 * TILE - EPS, ORIGIN, 0, 64)    -- south of the south edge
at(ORIGIN, ORIGIN + EPS, -1, 0)        -- west of the west edge
at(ORIGIN, ORIGIN - 64 * TILE - EPS, 64, 0)    -- east of the east edge

print("MAP VIEWMATH TILEAT PASSED")
