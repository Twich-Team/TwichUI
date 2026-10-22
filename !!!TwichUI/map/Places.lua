-- TwichUI: world map exploration, places
-- Small round markers on the stitched world map for places from map/Data.lua: dungeon and raid entrances, caves (whose own
-- maps surface as you zoom onto them, map/Caves.lua), and boat and zeppelin docks with where each goes. Each kind can be
-- turned off; they are never saved as pins (a place can be pinned on purpose, below).
--   Where: at their place on the world, from the zoom where the continents show (caves from closer in). Names under them
--     once closer in, never where two would overlap (the more important kind keeps its name). Outside the view: hidden.
--   Each marker hangs from an anchor in the stitched painting (map/Art.lua's root), on a layer over the map that is not
--     scaled: it moves with every zoom and pan by itself, the same size on screen, with nothing done per frame.
--   Clicks (one input, one action):
--     left-click        a dungeon: its own map (map/DungeonView.lua), where one is known; a cave: the view glides onto it
--                       and its map surfaces; a dock: the view glides to the other end of the ride (with two ends, the
--                       choice). The view moves; your character, flights, transports and spells are never touched. Back
--                       returns.
--     right-click       the place's actions: the above, "Pin this place" (the new pin window, named for the place; a pin
--                       of yours already there is picked out instead) and "Navigate here" (while Navigation is on).
--     Alt, Shift, Ctrl  handed to the map's click handlers at the place (the pin, ping and waypoint shortcuts).
--     a drag            pans the map, and is not a click.
--   Markers sit over TwichUI's pins, so where they overlap the place's click comes first; an armed map tool stays armed.

local R = TwichUI
local VM, MXP, MV, MW = R.MapViewMath, R.MapExplorePrefs, R.MapView, R.MapWorld
local PL = R.PinsLook
local MPL = {}
R.MapPlaces = MPL

local ICON = R.PATH .. [[media\textures\place-]]
local GLOW = R.PATH .. [[media\textures\nav-dot]]
local BASE = 20                        -- a marker's side on screen before the size choice
local LEVEL_OVER_PINS = 3
local SPOT_SECONDS = 3
local MARGIN = 0.03
local TRAVEL_YARDS = 1400              -- a ride's far end is shown with about this much round it
local GOLD = { 0.86, 0.69, 0.30 }

local KINDS = {
    dungeon = { icon = "dungeon", cat = "dungeons", noun = "Dungeon entrance", rank = 1, from = 2.2, label = 7 },
    raid = { icon = "raid", cat = "dungeons", noun = "Raid entrance", rank = 1, from = 2.2, label = 7 },
    boat = { icon = "boat", cat = "travel", noun = "Boat dock", rank = 2, from = 2.2, label = 7 },
    zeppelin = { icon = "zeppelin", cat = "travel", noun = "Zeppelin tower", rank = 2, from = 2.2, label = 7 },
    cave = { icon = "cave", cat = "caves", noun = "Cave", rank = 3, from = 9, label = 18 },
}
MPL.KINDS = KINDS

---------------------------------------------------------------------------
-- The places, from map/Data.lua (built the first time they are laid out)
---------------------------------------------------------------------------
local places, byId

local function Build()
    if places then return places end
    if not MV.Ready() then return {} end    -- (built once the map can place things, as the caves are)
    places, byId = {}, {}
    local D = R.MapExploreData
    if not D then return places end
    local function Add(p)
        places[#places + 1] = p
        byId[p.id] = p
    end
    for inst, d in pairs(D.dungeons or {}) do
        local e = d.entrance
        if e then
            Add({ id = "dungeon:" .. inst, kind = d.raid and "raid" or "dungeon", inst = inst, dataName = d.name,
                cont = e[1], x = e[2], y = e[3], floors = #(d.floors or {}) })
        end
    end
    for _, g in ipairs(R.MapCaves and R.MapCaves.Groups() or {}) do
        Add({ id = g.id, kind = "cave", dataName = g.name, cont = g.cont, cave = g,
            u = (g.u0 + g.u1) / 2, v = (g.v0 + g.v1) / 2 })
    end
    local docks = {}
    for id, d in pairs(D.docks or {}) do
        docks[id] = { id = "dock:" .. id, dock = id, dataName = d[1], town = d[2], cont = d[3], x = d[4], y = d[5], dests = {} }
    end
    for _, leg in ipairs(D.travel or {}) do
        local a, b = docks[leg[2]], docks[leg[3]]
        if a and b and (leg[1] == "boat" or leg[1] == "zeppelin") then
            a.dests[#a.dests + 1] = { to = b, kind = leg[1] }
            a.kind = a.kind or leg[1]
        end
    end
    for _, d in pairs(docks) do
        if #d.dests > 0 then Add(d) end
    end
    -- each place's spot on the world (off it: Zephras Isle, not part of the stitched world)
    for _, p in ipairs(places) do
        if not p.u and p.x then p.u, p.v = MW.FromYards(p.cont, p.x, p.y) end
        for _, d in ipairs(p.dests or {}) do
            if not d.to.u then d.to.u, d.to.v = MW.FromYards(d.to.cont, d.to.x, d.to.y) end
        end
    end
    table.sort(places, function(a, b)
        local ra, rb = KINDS[a.kind].rank, KINDS[b.kind].rank
        if ra ~= rb then return ra < rb end
        return a.id < b.id
    end)
    return places
end
MPL.All = Build
function MPL.Get(id) Build() return byId[id] end
function MPL.Forget() places, byId = nil, nil end

-- A place's name: a dungeon's in the game's own words where the client has it, else the data's (English).
function MPL.Name(p)
    if p.inst and GetRealZoneText then
        local ok, name = pcall(GetRealZoneText, p.inst)
        if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then return name end
    end
    return p.dataName
end

---------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------
local layer
local pool, used = {}, 0
local spot
local stats = { layouts = 0, shown = 0, labels = 0, clicks = 0, travels = 0, forwarded = 0, menus = 0 }

local function PinLevel()
    local ok, level = pcall(function()
        return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    end)
    return (ok and type(level) == "number") and level or 2500
end

local function Layer()
    if layer then return layer end
    local sc = MV.Container()
    layer = CreateFrame("Frame", nil, sc)
    layer:SetAllPoints(sc)
    layer:SetClipsChildren(true)
    layer:EnableMouse(false)
    return layer
end

local Tooltip, Click

local function NewMarker()
    local b = CreateFrame("Button", nil, Layer())
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.anchor = R.MapArt.Root():CreateTexture(nil, "BACKGROUND")
    b.anchor:SetSize(1, 1)
    b.anchor:SetAlpha(0)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(GLOW)
    b.glow:SetPoint("CENTER")
    b.glow:SetVertexColor(0.58, 0.78, 0.76, 0.85)
    b.glow:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetBlendMode("ADD")
    b.hl:SetAlpha(0.3)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b.label:SetWordWrap(false)
    b.label:SetJustifyH("CENTER")
    if PL and PL.MapText then PL.MapText.Apply(b.label, 160) end
    MV.WireButton(b)
    b:SetScript("OnClick", function(self, button)
        if MV.WasDrag(self) then return end
        Click(self, button)
    end)
    b:SetScript("OnEnter", function(self) Tooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Dress(b, p)
    if b.place ~= p then
        b.place = p
        b.icon:SetTexture(ICON .. KINDS[p.kind].icon)
        b.hl:SetTexture(ICON .. KINDS[p.kind].icon)
        b.label:SetText(MPL.Name(p))
        local W, H = MW.Size()
        b.anchor:ClearAllPoints()
        b.anchor:SetPoint("TOPLEFT", R.MapArt.Root(), "TOPLEFT", p.u * W, -p.v * H)
        b:ClearAllPoints()
        b:SetPoint("CENTER", b.anchor, "TOPLEFT", 0, 0)
    end
    local size = BASE * MXP.Get("iconSize") / 100
    b:SetSize(size, size)
    b.glow:SetSize(size * 1.9, size * 1.9)
    b:SetAlpha(MXP.Get("iconOpacity") / 100)
    b.glow:SetShown(spot ~= nil and spot.id == p.id and spot.untilTime > GetTime())
end

local function HideFrom(n)
    for i = n, #pool do
        local b = pool[i]
        if b:IsShown() then b:Hide() end
    end
end

local function HideAll()
    HideFrom(1)
    used = 0
end
MPL.HideAll = HideAll

-- Names: from the most important kind down, each only where it overlaps no name already shown (screen boxes).
local boxes = {}
local function Labels(u0, v0, u1, v1, zoom)
    local want = MXP.Get("labels")
    local vw, vh = MV.ViewSize()
    local nb, shown = 0, 0
    for i = 1, used do
        local b = pool[i]
        local p = b.place
        local show = false
        if want and zoom >= KINDS[p.kind].label then
            local x = (p.u - u0) / (u1 - u0) * vw
            local y = (p.v - v0) / (v1 - v0) * vh
            local half = (b:GetWidth() or BASE) / 2
            local w = b.label:GetStringWidth() or 60
            local box = boxes[nb + 1] or {}
            box[1], box[2], box[3], box[4] = x - w / 2, y + half, x + w / 2, y + half + 12
            local clear = true
            for k = 1, nb do
                if VM.Overlaps(box, boxes[k]) then clear = false break end
            end
            if clear then
                nb = nb + 1
                boxes[nb] = box
                show = true
                shown = shown + 1
            end
        end
        b.label:SetShown(show)
    end
    stats.labels = shown
end

function MPL.Layout()
    stats.layouts = stats.layouts + 1
    if not MV.Ready() or (R.MapDungeonView and R.MapDungeonView.IsOpen()) then HideAll() return end
    local u0, v0, u1, v1 = MV.ViewRect()
    local _, _, zoom = MV.View()
    local mu, mv = (u1 - u0) * MARGIN, (v1 - v0) * MARGIN
    local L = Layer()
    L:SetFrameLevel(PinLevel() + LEVEL_OVER_PINS)
    L:Show()
    used = 0
    for _, p in ipairs(Build()) do
        local k = KINDS[p.kind]
        if p.u and MXP.Get(k.cat) and zoom >= k.from
            and p.u >= u0 - mu and p.u <= u1 + mu and p.v >= v0 - mv and p.v <= v1 + mv then
            used = used + 1
            local b = pool[used]
            if not b then
                b = NewMarker()
                pool[used] = b
            end
            Dress(b, p)
            b:Show()
        end
    end
    HideFrom(used + 1)
    stats.shown = used
    Labels(u0, v0, u1, v1, zoom)
end

---------------------------------------------------------------------------
-- What a place says and does
---------------------------------------------------------------------------
local function MapName(id)
    local ok, info = pcall(C_Map.GetMapInfo, id)
    return ok and type(info) == "table" and info.name or nil
end

-- A map off the stitched world showing continent `cont` (Zephras Isle), or nil.
local function OffWorldMap(cont)
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, MW.WORLD)
    for _, info in ipairs(ok and type(kids) == "table" and kids or {}) do
        local f = MV.MapFrame(info.mapID)
        if f and f.cont == cont then return info.mapID end
    end
    return nil
end

-- Where a ride ends: { place, kind, town, map (the zone there, by the game's own shapes), mapName }
local function Destination(dest)
    local d = dest.to
    local map
    if d.u then map = MW.Deepest(d.u, d.v) else map = OffWorldMap(d.cont) end
    return { place = d, kind = dest.kind, town = d.town, map = map, mapName = map and MapName(map) }
end
MPL.Destination = Destination

function Tooltip(b)
    local p = b.place
    if not p then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT", -4, -4)
    GameTooltip:SetText(MPL.Name(p), 1, 1, 1, 1, true)
    GameTooltip:AddLine(KINDS[p.kind].noun, 0.78, 0.74, 0.66)
    if p.kind == "dungeon" or p.kind == "raid" then
        if p.floors > 0 then
            GameTooltip:AddLine(("Click to see its map (%d %s)"):format(p.floors, p.floors == 1 and "floor" or "floors"), GOLD[1], GOLD[2], GOLD[3])
        else
            GameTooltip:AddLine("No map of it is known for WoW: Forever.", 0.62, 0.58, 0.51, true)
        end
    elseif p.kind == "cave" then
        local g = p.cave
        if #g.floors > 1 then
            local names = {}
            for _, fl in ipairs(g.floors) do names[#names + 1] = fl.name end
            GameTooltip:AddLine(("%d floors: %s"):format(#g.floors, table.concat(names, ", ")), 0.78, 0.74, 0.66, true)
        end
        GameTooltip:AddLine("Click to look inside (or zoom in on it)", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine("Marked at the middle of the cave's map, not at its entrance.", 0.62, 0.58, 0.51, true)
    else
        for _, dest in ipairs(p.dests) do
            local to = Destination(dest)
            local where = to.mapName and to.mapName ~= to.town and (" (" .. to.mapName .. ")") or ""
            GameTooltip:AddLine(("%s to %s%s"):format(dest.kind == "zeppelin" and "Zeppelin" or "Boat", to.town, where), 1, 1, 1)
        end
        GameTooltip:AddLine(#p.dests == 1 and "Click to go to the other end" or "Click to choose an end to go to", GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine("From the game's own routes. Whether you can board isn't checked.", 0.62, 0.58, 0.51, true)
    end
    GameTooltip:AddLine("Right-click for more", 0.45, 0.43, 0.38)
    GameTooltip:Show()
end

function MPL.Spotlight(id)
    spot = { id = id, untilTime = GetTime() + SPOT_SECONDS }
    if MV.Ready() then MPL.Layout() end
    C_Timer.After(SPOT_SECONDS + 0.1, function()
        if spot and spot.id == id and spot.untilTime <= GetTime() then
            spot = nil
            if MV.Ready() then MPL.Layout() end
        end
    end)
end

-- Glides to the other end of a ride (on the world), or shows its map (off it). Returns true, or false and a sentence.
function MPL.Travel(dest)
    local d = dest.to
    stats.travels = stats.travels + 1
    if d.u then
        local u0, v0, u1, v1 = MW.YardsRect(d.cont, d.x - TRAVEL_YARDS / 2, d.y - TRAVEL_YARDS / 2,
            d.x + TRAVEL_YARDS / 2, d.y + TRAVEL_YARDS / 2)
        local zoom = u0 and MV.RectZoom(u0, v0, u1, v1) or 20
        local ok, why = MV.GoTo(d.u, d.v, zoom, "travel", function() MPL.Spotlight(d.id) end)
        if not ok then return false, MV.Reason(why) end
        return true
    end
    local map = OffWorldMap(d.cont)
    if not map then return false, "The other end isn't on any map the game has." end
    local ok, why = MV.ShowMap(map)
    if not ok then return false, MV.Reason(why) end
    return true
end

local function Say(ok, why) if not ok and why then MV.Notice(why) end end

-- Glides onto a cave so its map surfaces.
function MPL.LookInside(p)
    local g = p.cave
    MV.Remember("cave")
    return MV.FrameWorldRect(g.u0, g.v0, g.u1, g.v1, 0.9)
end

function MPL.Act(p, anchor)
    if p.kind == "dungeon" or p.kind == "raid" then
        if p.floors > 0 and R.MapDungeonView then return R.MapDungeonView.Open(p.inst) end
        MV.Notice(("No map of %s is known for WoW: Forever."):format(MPL.Name(p)))
        return false
    elseif p.kind == "cave" then
        return MPL.LookInside(p)
    elseif #p.dests == 1 then
        local ok, why = MPL.Travel(p.dests[1])
        Say(ok, why)
        return ok
    end
    return MPL.Menu(p, anchor)
end

-- Opens the new pin window for the place, on the zone it is in, named for it; a pin of yours already there is picked out.
function MPL.PinThis(p)
    local PN, PE = R.Pins, R.PinsEditor
    if not (PN and PE and R:Enabled("partyPins")) then
        MV.Notice("Turn on Party Map to keep pins of your own.")
        return false
    end
    local map, mx, my = MW.Deepest(p.u, p.v)
    local x, y = PN.Quantize(mx), PN.Quantize(my)
    if not (x and y and map ~= MW.WORLD and PN.ValidMap(map)) then
        MV.Notice(PN.Reason("unknown-map"))
        return false
    end
    local near = PN.COORD / 1000 * 3
    for _, e in ipairs(PN.Entries()) do
        local pin = e.pin
        if e.kind == "local" and pin.map == map and math.abs(pin.x - x) <= near and math.abs(pin.y - y) <= near then
            PN.Select(e.token)
            MV.Notice(("Already in your pins: %s"):format(pin.name))
            return false, "exists"
        end
    end
    PE.OpenNew(map, x, y, false, MPL.Name(p))
    return true
end

function MPL.Menu(p, anchor)
    local OpenMenu = R.PinsWindow and R.PinsWindow.OpenMenu
    if not OpenMenu then return false end
    stats.menus = stats.menus + 1
    local choices = {}
    if p.kind == "dungeon" or p.kind == "raid" then
        choices[#choices + 1] = { label = "Show its map", enabled = p.floors > 0,
            why = "No map of it is known for WoW: Forever.",
            tip = "The dungeon's own map, one floor at a time, over this map. Back closes it.",
            run = function() R.MapDungeonView.Open(p.inst) end }
    elseif p.kind == "cave" then
        choices[#choices + 1] = { label = "Look inside", tip = "Glides onto the cave; its map surfaces. Back returns.",
            run = function() MPL.LookInside(p) end }
    else
        for _, dest in ipairs(p.dests) do
            local to = Destination(dest)
            choices[#choices + 1] = { label = ("Go to %s"):format(to.town), enabled = to.map ~= nil,
                why = "The other end isn't on any map the game has.",
                tip = "The map glides to the other end of this ride. Back returns here. Nothing else is done for you.",
                run = function() Say(MPL.Travel(dest)) end }
        end
    end
    local pinsOn = R:Enabled("partyPins")
    choices[#choices + 1] = { label = "Pin this place", enabled = pinsOn, why = "Party Map is turned off.",
        tip = "Opens the new pin window here, named for the place. Nothing is made until you save it.",
        run = function() MPL.PinThis(p) end }
    if R.Nav and R.Nav.Enabled() then
        choices[#choices + 1] = { label = "Navigate here",
            tip = "Plans a route to this place and guides you along it (Navigation). It replaces any destination you had.",
            run = function()
                local map, x, y = MW.Deepest(p.u, p.v)
                local ok, why = R.Nav.StartAt(map, x, y, MPL.Name(p), "map")
                if not ok then MV.Notice(why) end
            end }
    end
    OpenMenu(anchor, MPL.Name(p), choices)
    return true
end

function Click(b, button)
    local p = b.place
    if not p then return end
    GameTooltip:Hide()
    stats.clicks = stats.clicks + 1
    if button == "RightButton" then
        MPL.Menu(p, b)
        return
    end
    if (IsAltKeyDown and IsAltKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then
        -- a shortcut click: the map's own handlers, at the pointer (pins, pings, the waypoint), as on the bare map
        stats.forwarded = stats.forwarded + 1
        local sc = MV.Container()
        WorldMapFrame:ProcessCanvasClickHandlers(button, sc:NormalizeUIPosition(sc:GetCursorPosition()))
        return
    end
    MPL.Act(p, b)
end

MV.Subscribe(function(event)
    if event == "view" or event == "attach" or event == "show" then MPL.Layout()
    elseif event == "hide" or event == "off" then
        HideAll()
        spot = nil
    end
end)
MXP.Subscribe(function() if MV.Ready() then MPL.Layout() end end)
if PL and PL.OnPrefChange then
    PL.OnPrefChange(function()
        for _, b in ipairs(pool) do if PL.MapText then PL.MapText.Apply(b.label, 160) end end
    end)
end

-- Read only, for /tui diagnostics and the tests.
function MPL.Snapshot()
    local out = { places = places and #places or 0, pool = #pool }
    for k, v in pairs(stats) do out[k] = v end
    return out
end
function MPL.Marker(i) return pool[i] end
function MPL.Used() return used end
