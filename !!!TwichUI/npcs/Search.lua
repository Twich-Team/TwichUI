-- TwichUI: Vendors and trainers, searching what you know (for the map tools bar's NPC search)
-- A search of the list you already have (npcs/Store.lua, through npcs/Knowledge.lua's rows): the NPCs you dealt with and
-- those other players sent you. Nothing here looks anything up, adds an NPC or changes the list; it has no frames
-- (npcs/SearchBar.lua draws it).
--   What matches. Every word of the query has to appear in the NPC's name, area, role, title or profession, in any order,
--     without regard to case, as plain text (never a pattern): the World Knowledge tab's own filter, so the two agree.
--     An empty query matches nothing (the list is not shown whole).
--   A result is one place. An NPC with several known places is several entries (npcs/Store.lua), and each is its own
--     result, named by its area and, where two results would read the same, its coordinates. Results are told apart by
--     `key` ("<creature>:<map>:<x>:<y>"), never by name. An entry whose map this client doesn't know as a zone or
--     smaller can't be shown on the map and is left out.
--   Nearest first, where that can be said. Your place and a result's place are both turned into continent yards
--     (C_Map.GetWorldPosFromMapPos, as Navigation does); two places are compared only when the game puts them on the same
--     continent (or instance), and the number is the straight line between them: not a walking distance and not a time.
--     The order is:
--       1  places with a distance, nearest first
--       2  places on the map you are on, whose distance can't be told (no position of yours, or no world position)
--       3  every other place, by area name, NPC name, then key
--     Within a group, ties break by name and then key, so the order never shuffles. Nothing is given a distance it
--     doesn't have to fill the list. Inside an instance the game gives no position, so only groups 2 and 3 remain.
--   The cap. Every match is ranked, and the nearest SR.MAX_RESULTS are kept: not the first ones found.
--   Nothing is kept between searches but what Knowledge keeps (the rows, rebuilt after any change to the list).

local R = TwichUI
local NS, KN = R.NpcStore, R.NpcKnowledge
local SR = {}
R.NpcSearch = SR

SR.MAX_RESULTS = 8
SR.MAX_TEXT = 48

local sqrt = math.sqrt

local function Readable(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- The query as it will be matched: escape sequences and control characters out, trimmed. "" when nothing is left.
function SR.Clean(text)
    if type(text) ~= "string" then return "" end
    local clean = R.Pins and R.Pins.CleanName and R.Pins.CleanName(text, SR.MAX_TEXT * 2) or text
    clean = (clean or ""):gsub("%c", " ")
    return (clean:match("^%s*(.-)%s*$"))
end

---------------------------------------------------------------------------
-- Where things are
---------------------------------------------------------------------------
-- A map point in continent yards: continent, x, y, or nil.
local function World(map, x, y)
    local ok, cont, vec = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not (ok and cont and vec) then return nil end
    local a, b = vec:GetXY()
    cont, a, b = Readable(cont), Readable(a), Readable(b)
    if not (cont and a and b) then return nil end
    return cont, a, b
end

-- Where you are, read once per search: { map, cont, x, y }. Each is nil when the game doesn't say (map: no best map;
-- cont, x, y: no position, as inside an instance). Never keeps a place longer than the search that asked.
function SR.Where()
    local spot = {}
    if not (C_Map and C_Map.GetBestMapForUnit) then return spot end
    local map = Readable(C_Map.GetBestMapForUnit("player"))
    if not map then return spot end
    spot.map = map
    local ok, p = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not (ok and p) then return spot end
    local x, y = p:GetXY()
    x, y = Readable(x), Readable(y)
    if not (x and y) then return spot end
    spot.cont, spot.x, spot.y = World(map, x, y)
    return spot
end

-- The straight-line yards from a spot to a place, or nil when the two can't be compared.
function SR.Distance(spot, map, x, y)
    if not (spot and spot.cont) then return nil end
    local cont, wx, wy = World(map, x, y)
    if cont ~= spot.cont then return nil end
    return sqrt((wx - spot.x) ^ 2 + (wy - spot.y) ^ 2)
end

-- "340 yd", "1,240 yd". Always a straight line (the tooltip says so); rounded, because a position is only that good.
function SR.DistanceText(d)
    d = math.floor(d + 0.5)
    if d >= 1000 then return ("%d,%03d yd"):format(math.floor(d / 1000), d % 1000) end
    return d .. " yd"
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
function SR.Key(e) return ("%d:%d:%d:%d"):format(e.id, e.m, e.x, e.y) end

local function Before(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    if a.tier == 1 and a.dist ~= b.dist then return a.dist < b.dist end
    if a.tier == 3 and a.lzone ~= b.lzone then return a.lzone < b.lzone end
    if a.lname ~= b.lname then return a.lname < b.lname end
    return a.key < b.key
end
SR.Before = Before

-- text: what was typed. spot: SR.Where() (read now when left out). limit: how many to keep.
-- Returns results, total, query: results nearest first (at most `limit`), how many places matched in all, and the query as
-- it was matched. A result: { e, key, name, role, more, zone, place, dist, tier, coords } where `dist` is yards or nil,
-- tier 1, 2 or 3 as above, and `coords` is true when another kept result has the same name in the same area (so the row
-- should say which one). `e` is the list's own entry: read it, never change it.
function SR.Run(text, spot, limit)
    local q = SR.Clean(text)
    if q == "" then return {}, 0, q end
    limit = limit or SR.MAX_RESULTS
    spot = spot or SR.Where()
    local all = {}
    for _, row in ipairs(KN.Filter({ text = q })) do
        local e = row.e
        if NS.ValidMap(e.m) then
            local r = { e = e, key = SR.Key(e), name = e.n, lname = row.lname, zone = row.zone, lzone = row.lzone,
                role = row.role, more = row.more, tier = 3 }
            local d = SR.Distance(spot, e.m, e.x / NS.COORD, e.y / NS.COORD)
            if d then
                r.dist, r.tier = d, 1
            elseif spot.map and e.m == spot.map then
                r.tier = 2
            end
            all[#all + 1] = r
        end
    end
    table.sort(all, Before)
    local total = #all
    local out = {}
    for i = 1, math.min(total, limit) do out[i] = all[i] end
    local seen = {}
    for _, r in ipairs(out) do
        local k = r.lname .. "\0" .. r.e.m
        seen[k] = (seen[k] or 0) + 1
    end
    for _, r in ipairs(out) do
        r.place = ("%.1f, %.1f"):format(r.e.x / NS.COORD * 100, r.e.y / NS.COORD * 100)
        r.coords = seen[r.lname .. "\0" .. r.e.m] > 1
    end
    return out, total, q
end
