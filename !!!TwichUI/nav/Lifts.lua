-- TwichUI: Navigation, lifts and elevators
-- The walking maps have no lifts: a lift's platform is placed by the game's server, so the client's files (the bake's source)
-- hold only its housing, and the floors a lift joins (the Freewind Post plateau, Thunder Bluff's mesas) come out as places
-- nothing walks to. This file is the list of lifts the planner (nav/Journey.lua) may use as a ride between two stand points,
-- and the code that joins each stand point to the walking map. Data only plus a lookup; no frames, no events, nothing is
-- ever pressed, clicked or ridden for the player: a lift is a step in the instructions ("Take the Great Lift up").
--
-- A lift is { id, name, cont, faction (1 Alliance, 2 Horde, 3 both), seconds, base = { x, y, z }, top = { x, y, z } }.
--   x, y   world yards (x north, y west), the spot where a player steps on or off the lift: a point on the floor at that end
--   z      the height of that floor. Where floors stack (the shaft's base under its top landing) the height picks the floor.
--   seconds  an estimate of the wait for the platform plus the ride, one way. Nothing about the platform's position is known.
--
-- Where the numbers come from (checked against client 1.60.1.70938, not taken on trust): the two Thousand Needles lifts are the
-- placements of the WMO world/wmo/elevators/thousandneedleselevator in Kalimdor's tiles (35,40) and (36,42), whose shaft axes
-- are at (-4666, -1839) and (-5392, -2496) and whose floors, in the baked walking map, are at z -45 and z 86 (the Great
-- Lift) and z -47 and z 89 (Freewind Post's, the top a plateau of its own). The stand points are polygon centres of the
-- walking map on those floors, 15 to 20 yards from the axis so that standing in the cabin is not standing at an exit.
-- Thunder Bluff's lifts are not in the client at all (no placement, no table); theirs are from the player's own position
-- readings (see their entries).
--
-- Stairs are listed the same way (`stairs = true`: the same two stand points and an estimate of the climb, worded as stairs).
-- Orgrimmar's are geometry in the client (the city is one WMO), but the baked walking map does not join the foot of the flight
-- master's tower to its top: the walk there is a 900-yard loop round the city's east side for a flight master 30 yards away.
-- The WMO's steep surfaces climb inside that tower from z 0 to z 60 around (1675, -4320). The top stand point is the flight
-- point's own; the bottom is the street at the west foot of the tower, about 15 yards from where the steps start (the exact
-- entrance is not in any table). Not verified in the game.

local R = TwichUI
local ND = R.NavData
local LF = {}
R.NavLifts = LF

LF.LIFTS = {
    { id = "great", name = "Great Lift", cont = 1, faction = 3, seconds = 35,
      base = { x = -4681, y = -1855, z = -46 }, top = { x = -4651, y = -1833, z = 86 } },
    { id = "freewind", name = "Freewind Post lift", cont = 1, faction = 3, seconds = 35,
      base = { x = -5394, y = -2513, z = -47 }, top = { x = -5408, y = -2492, z = 89 } },
    { id = "orgfm", name = "Orgrimmar flight master stairs", stairs = true, cont = 1, faction = 3, seconds = 25,
      base = { x = 1645, y = -4310, z = 3 }, top = { x = 1677.6, y = -4315.8, z = 62 } },
    -- Thunder Bluff: four lifts to the main mesa, in two pairs (south-west and north-east). The shaft axes are the player's own
    -- readings (UnitPosition at each lift, 2026-11): (-1285.5, 188.6), (-1308.5, 185.8), (-1028, -27.5), (-1036.9, -50). The
    -- readings have no height and the walking map has no floor on the shafts (the platform is the server's), so each end is the
    -- nearest ground 14 to 19 yards away: the lowland (z 59 to 61) on the side away from the cliff, the mesa edge (z 131 and
    -- 141) at the cliff. Away from the axis so that standing in the cabin is not standing at an exit. Floors are from the baked
    -- map; the rides' time is an estimate.
    { id = "tb1", name = "Thunder Bluff lift 1", cont = 1, faction = 3, seconds = 30,
      base = { x = -1293, y = 202, z = 59 }, top = { x = -1284, y = 172, z = 131 } },
    { id = "tb2", name = "Thunder Bluff lift 2", cont = 1, faction = 3, seconds = 30,
      base = { x = -1310, y = 204, z = 59 }, top = { x = -1305, y = 172, z = 131 } },
    { id = "tb3", name = "Thunder Bluff lift 3", cont = 1, faction = 3, seconds = 30,
      base = { x = -1013, y = -19, z = 61 }, top = { x = -1046, y = -20, z = 141 } },
    { id = "tb4", name = "Thunder Bluff lift 4", cont = 1, faction = 3, seconds = 30,
      base = { x = -1023, y = -42, z = 61 }, top = { x = -1049, y = -42, z = 141 } },
}

-- Whether any lift or stairs end on the continent is within `yards` of either point (a short walk there is worth planning
-- with them; elsewhere it is just walked).
function LF.Near(cont, sx, sy, gx, gy, yards)
    local r2 = yards * yards
    for _, lf in ipairs(LF.LIFTS) do
        if lf.cont == cont then
            for _, e in ipairs({ lf.base, lf.top }) do
                if (e.x - sx) ^ 2 + (e.y - sy) ^ 2 <= r2 or (e.x - gx) ^ 2 + (e.y - gy) ^ 2 <= r2 then return true end
            end
        end
    end
    return false
end

-- The lifts on any of these continents (nil entries skipped).
function LF.On(...)
    local want, out = {}, {}
    for i = 1, select("#", ...) do
        local c = select(i, ...)
        if c then want[c] = true end
    end
    for _, lf in ipairs(LF.LIFTS) do
        if want[lf.cont] then out[#out + 1] = lf end
    end
    return out
end

local YARDS, HEIGHT = 12, 14     -- how far from the listed point (yards on the ground) and how far off its height a floor may be

-- A stand point joined to the walking map: the polygon at that spot on the floor at that height, so a point where floors
-- stack is on the right one. Returns { x, y, prefer = { tile, poly } } (the polygon's own centre), or nil when the map has
-- no such floor (the lift is then left out).
local cache = {}
function LF.Stand(cont, pt)
    local key = cont .. ":" .. pt.x .. ":" .. pt.y .. ":" .. pt.z
    local c = cache[key]
    if c ~= nil then return c or nil end
    local found
    if ND and ND.HasMap(cont) then
        local tx, ty = ND.TileOf(pt.x, pt.y)
        local t = ND.Tile(cont, tx, ty)
        local ft, fp = ND.FloorAt(cont, pt.x, pt.y, pt.z, HEIGHT)      -- the point itself is on a floor at that height
        if ft then
            found = { x = pt.x, y = pt.y, prefer = { tile = ft.id, poly = fp } }
        elseif t then
            local best
            for p = 1, t.np do
                if t.area[p] == 1 then
                    local dx, dy = t.cxp[p] - pt.x, t.cyp[p] - pt.y
                    local d = math.sqrt(dx * dx + dy * dy)
                    local dz = math.abs((t.zmin[p] + t.zmax[p]) / 2 - pt.z)
                    if d <= YARDS and dz <= HEIGHT then
                        local score = d + dz * 2
                        if not best or score < best then best, found = score, { x = t.cxp[p], y = t.cyp[p], prefer = { tile = t.id, poly = p } } end
                    end
                end
            end
        end
    end
    -- a miss is not remembered while the map's data is not there to look in (it loads on demand)
    if found or (ND and ND.HasMap(cont)) then cache[key] = found or false end
    return found
end

function LF.Reset() cache = {} end
