-- TwichUI: navigation, places and positions
-- The few conversions the rest of navigation needs, in one place: where the player stands, map
-- coordinates to world coordinates and back, distances and bearings.
--
-- World coordinates are the ones UnitPosition("player") gives: x, y in yards on a continent, and that
-- continent's instance map ID. C_Map.GetWorldPosFromMapPos answers in the same frame (its vector's X
-- matches UnitPosition's first value), so a map pin and the player can be compared directly. A route is
-- only ever planned within one continent, so distances never cross a map.
-- Nothing here is saved, and nothing here keeps a table between calls.

local R = TwichUI
local W = {}
R.NavWorld = W

-- A number the addon may read and use: not hidden by the game, not NaN, not infinite.
local function Plain(v)
    if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
W.Plain = Plain

-- x, y, map of the player, or nil when the game gives no position (some instances, loading screens).
-- Three values rather than a table: the journey and the arrow ask often.
function W.Here()
    if not UnitPosition then return nil end
    local x, y, _, map = UnitPosition("player")
    x, y, map = Plain(x), Plain(y), Plain(map)
    if not (x and y and map) then return nil end
    return x, y, map
end

-- Inside a dungeon, raid, battleground or arena. Routes are not planned or followed there.
function W.InInstance()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside == true and kind ~= "none"
end

function W.Distance(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- The direction from one point to another, in radians counter-clockwise from north, the way
-- GetPlayerFacing measures the way you face. x grows north and y grows west.
function W.Bearing(fromX, fromY, toX, toY)
    return math.atan2(toY - fromY, toX - fromX)
end

-- The two numbers of a position the game hands back. Read as fields, the way Blizzard's own map code
-- reads them (waypoint.position.x); GetXY only when there are no fields. nil unless both are usable.
local function XY(v)
    if type(v) ~= "table" then return nil end
    local x, y = v.x, v.y
    if x == nil and y == nil and v.GetXY then x, y = v:GetXY() end
    x, y = Plain(x), Plain(y)
    if not (x and y) then return nil end
    return x, y
end
W.XY = XY

-- Why the last map-to-world conversion failed (a code for the troubleshooting report), or nil.
W.lastConversion = nil

local function WorldPos(uiMapID, mx, my)
    local continent, world = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(mx, my))
    continent = Plain(continent)
    local x, y = XY(world)
    if continent and x then return { map = continent, x = x, y = y } end
end

local function MapType(name, fallback)
    return Enum and Enum.UIMapType and Enum.UIMapType[name] or fallback
end

-- A point on a map (0-1 across and down) as a world point { map, x, y }, or nil.
-- When the game won't convert a point on this map, the point is placed on its continent's map
-- (C_Map.GetMapRectOnMap, as Blizzard's map utilities do) and converted from there.
function W.FromMap(uiMapID, mx, my)
    if not (Plain(uiMapID) and Plain(mx) and Plain(my)) then W.lastConversion = "bad-numbers" return nil end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then W.lastConversion = "no-api" return nil end
    local point = WorldPos(uiMapID, mx, my)
    if point then W.lastConversion = nil return point end
    local continent = W.ContinentOf(uiMapID)
    if continent and continent ~= uiMapID and C_Map.GetMapRectOnMap then
        local left, right, top, bottom = C_Map.GetMapRectOnMap(uiMapID, continent)
        left, right, top, bottom = Plain(left), Plain(right), Plain(top), Plain(bottom)
        if left and right and top and bottom then
            point = WorldPos(continent, left + (right - left) * mx, top + (bottom - top) * my)
            if point then W.lastConversion = "via-continent" return point end
        end
        W.lastConversion = "continent-failed"
        return nil
    end
    W.lastConversion = continent and "map-failed" or "no-continent"
    return nil
end

-- A world point's place on a given map (0-1 across and down; outside that range when it lies beyond the
-- map's edge), or nil when the point is not on that map's continent.
function W.ToMap(map, x, y, uiMapID)
    if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local onMap, pos = C_Map.GetMapPosFromWorldPos(map, CreateVector2D(x, y), uiMapID)
    if Plain(onMap) ~= uiMapID then return nil end
    return XY(pos)
end

-- The continent map a map belongs to (itself if it is one), or nil.
function W.ContinentOf(uiMapID)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local continent = MapType("Continent", 2)
    local id = Plain(uiMapID)
    for _ = 1, 8 do   -- maps nest a few levels deep at most; a broken parent chain must not loop
        if not id then return nil end
        local info = C_Map.GetMapInfo(id)
        if type(info) ~= "table" then return nil end
        if info.mapType == continent then return id end
        if info.mapType ~= nil and info.mapType < continent then return nil end   -- above continents: the world
        id = Plain(info.parentMapID)
    end
    return nil
end

-- The continent map the player is on, or nil.
function W.PlayerContinent()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    return W.ContinentOf(C_Map.GetBestMapForUnit("player"))
end

-- The game's name for the zone a world point lies in, or nil. For labels only.
function W.ZoneName(map, x, y)
    if not (C_Map and C_Map.GetMapPosFromWorldPos and C_Map.GetMapInfo and CreateVector2D) then return nil end
    local uiMapID, pos = C_Map.GetMapPosFromWorldPos(map, CreateVector2D(x, y))
    uiMapID = Plain(uiMapID)
    if not uiMapID then return nil end
    local info = C_Map.GetMapInfo(uiMapID)
    if type(info) ~= "table" then return nil end
    local px, py = XY(pos)
    if info.mapType ~= nil and info.mapType < MapType("Zone", 3) and C_Map.GetMapInfoAtPosition and px then
        local zone = C_Map.GetMapInfoAtPosition(uiMapID, px, py)
        if type(zone) == "table" and zone.mapType == MapType("Zone", 3) then info = zone end
    end
    local name = info.name
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or name == "" then return nil end
    return name
end
