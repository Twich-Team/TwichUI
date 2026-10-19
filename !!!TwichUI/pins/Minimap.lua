-- TwichUI: Party pins on the minimap
-- Shows the pins that are within range of you on the minimap, in the same shape and color as on the world
-- map (smaller; a party pin has its badge). Names are in the tooltip; right-click opens the same actions.
-- Nothing points at a pin that is out of range: there are no edge arrows, routes or navigation.
--   Where a pin is: from the game's own map data, the way Blizzard's HybridMinimap does it. The player's
--   place on the pin's map is C_Map.GetPlayerMapPosition(pin.map, "player"), and that map's size in yards is
--   C_Map.GetMapWorldSize. The map's x runs east and its y south, so the pin is (x difference * width)
--   yards east and (y difference * height) yards south of you. Yards become pixels the way the game's
--   HybridMinimap does: the minimap's half width is C_Minimap.GetViewRadius() yards. When the minimap
--   rotates (the rotateMinimap setting) the offset is turned by the way you face (GetPlayerFacing,
--   counterclockwise from north). No world coordinates or unit positions are read, so there is no axis
--   convention to get wrong.
--   Which pins: only those placed on the minimap's own map or one of its parents (a zone pin while you are in
--   that zone, a continent pin anywhere on it). A pin on a map you are not in, or in a dungeon without a
--   map, is not shown, and a pin is never put on a map it doesn't belong to.
--   When it works: one throttled updater (25 times a second while the minimap rotates, 10 otherwise) that
--   exists only while the feature is on, the minimap is shown and a pin could be on it. A pin button is
--   moved only when its place changed by half a pixel or more.
-- Pins you removed from your map are not shown here either.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local PM = R.PinsMap
local PMM = {}
R.PinsMinimap = PMM

local SIZE = 16               -- pixels; the pin texture is drawn in a square this big (the diamond is 15)
local FAST, SLOW = 0.04, 0.10
local INSET = 3               -- a pin whose middle is nearer the rim than this isn't drawn
local MAX_PARENTS = 8

local driver
local active = false
local eligible = {}           -- entries that could be on the minimap now, in a fixed order
local slots = {}              -- slots[i] is the button for eligible[i]
local relate = {}             -- [mapID] = true for the minimap's map and its parents
local relateFor               -- the map `relate` was made for (false: none)
local wait = 0
local sizeW, sizeH = {}, {}   -- [mapID] = yards across; kept (a map's size doesn't change)
local tickX, tickY = {}, {}   -- the player's place on a map, this update only
local stats = { ticks = 0, moves = 0, rebuilds = 0, shown = 0, rotating = false, range = nil,
    errors = 0, reported = false, last = "none", reasons = {} }
local view = {}               -- what Gather read on the last update

local function Enabled()
    return Minimap ~= nil and R:Enabled("partyPins") and PL.Pref("minimap")
end

-- A number the addon may use, or nil. A value the client marks secret is never compared or computed with:
-- the checks that don't touch the value come first. (Guarded because this client has secret values and
-- the minimap's own readings are what other minimap addons here guard too.)
local function Readable(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if canaccessvalue and not canaccessvalue(v) then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- What a value is, for the troubleshooting report: "number", "nil", "secret" or another type's name.
local function Kind(v)
    if type(v) == "nil" then return "nil" end
    if issecretvalue and issecretvalue(v) then return "secret" end
    return type(v)
end

-- The minimap's view radius in yards for each zoom step, from the game's zoom setting, used only when the
-- game won't give the radius itself (C_Minimap.GetViewRadius). The values are HereBeDragons', which
-- EUI-RestedXP also falls back to here; outdoor is when the zoom is the one "minimapZoom" names. Not
-- verified in the game: the report says when this was used.
local OUTDOOR = { [0] = 233.33, [1] = 200, [2] = 166.67, [3] = 133.33, [4] = 100, [5] = 66.67 }
local INDOOR = { [0] = 150, [1] = 120, [2] = 90, [3] = 60, [4] = 40, [5] = 25 }

local function ZoomRadius()
    if type(Minimap.GetZoom) ~= "function" then return nil end
    local zoom = Readable(Minimap:GetZoom())
    if not zoom then return nil end
    zoom = math.floor(zoom + 0.5)
    local outdoors = Readable(tonumber(GetCVar and GetCVar("minimapZoom")))
    local row = (outdoors and outdoors == zoom) and OUTDOOR or INDOOR
    return row[math.max(0, math.min(5, zoom))]
end

-- Reads everything the placing needs into `view` (reused). Returns nil when it is all usable, else why not:
-- "minimap-hidden", "no-map", "no-radius", "no-width" or "no-facing". It is also what the troubleshooting
-- report asks, so it shows what the updater sees.
local function Gather(out)
    out.visible = Minimap:IsVisible() and true or false
    local raw = C_Minimap and C_Minimap.GetUiMapID and C_Minimap.GetUiMapID()
    out.mapKind, out.mapSource = Kind(raw), "minimap"
    local map = Readable(raw)
    if not map and C_Map and C_Map.GetBestMapForUnit then
        -- the map the player is on, which is the minimap's whenever the minimap has one
        raw = C_Map.GetBestMapForUnit("player")
        map = Readable(raw)
        out.mapSource = map and "player" or "none"
    end
    out.map = map
    raw = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    out.radiusKind, out.radiusSource = Kind(raw), "client"
    local radius = Readable(raw)
    if not (radius and radius > 0) then
        radius = ZoomRadius()
        out.radiusSource = radius and "zoom" or "none"
    end
    out.radius = radius
    local width = Readable(Minimap:GetWidth())
    out.halfWidth = width and width > 0 and width / 2 or nil
    out.rotating = (GetCVarBool and GetCVarBool("rotateMinimap")) and true or false
    out.facing, out.facingKind = 0, "not needed"
    if out.rotating then
        raw = GetPlayerFacing()
        out.facingKind = Kind(raw)
        out.facing = Readable(raw)   -- nil when it can't be read: nothing is placed then
    end
    if not out.visible then return "minimap-hidden" end
    if not out.map then return "no-map" end
    if not out.radius then return "no-radius" end
    if not out.halfWidth then return "no-width" end
    if out.facing == nil then return "no-facing" end
end
PMM.Gather = Gather   -- read only: navigation's minimap trail places its route the same way (nav/MinimapTrail.lua)

---------------------------------------------------------------------------
-- The buttons
---------------------------------------------------------------------------
-- Whether this pin's name is drawn now, by the Names on the minimap choice.
local function LabelShown(b)
    local mode = PL.Pref("minimapLabels")
    if mode == "always" then return true end
    if mode == "off" then return false end
    return b.over or (b.entry ~= nil and PN.selected == b.entry.token)
end

local function OnEnter(b)
    b.over = true
    b.label:SetShown(LabelShown(b))
    PM.Tooltip(b, "ANCHOR_LEFT", b.yards)
end

local function OnLeave(b)
    b.over = false
    b.label:SetShown(LabelShown(b))
    GameTooltip:Hide()
end

local function OnClick(b, button)
    local e = b.entry
    if not e then return end
    GameTooltip:Hide()
    if button == "RightButton" then
        if R.PinsWindow then R.PinsWindow.OpenActions(e, b) end
    else
        R.PinsMap.Activate(e)
    end
end

local function NewSlot()
    local b = CreateFrame("Button", nil, Minimap)
    b:SetSize(SIZE, SIZE)
    b:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(PL.PIN_TEXTURE)
    b.glow:SetPoint("CENTER", 0, 0)
    b.glow:SetSize(SIZE + 6, SIZE + 6)
    b.glow:SetVertexColor(1, 0.95, 0.80, 0.55)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(PL.PIN_TEXTURE)
    b.icon:SetAllPoints()
    b.badgeEdge = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.badgeEdge:SetColorTexture(0.06, 0.04, 0.03, 1)
    b.badgeEdge:SetSize(6, 6)
    b.badgeEdge:SetPoint("CENTER", b, "TOPLEFT", PL.BadgePoint(SIZE))
    b.badge = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.badge:SetColorTexture(0.93, 0.87, 0.71, 1)
    b.badge:SetSize(4, 4)
    b.badge:SetPoint("CENTER", b.badgeEdge, "CENTER", 0, 0)
    -- the name, under the pin; made once and left hidden unless asked for
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, 1)
    b.label:SetWordWrap(false)
    b.label:SetJustifyH("CENTER")
    PL.MapText.Apply(b.label, 120)
    b.label:Hide()
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("OnClick", OnClick)
    b:Hide()
    return b
end

-- Only what changed is set again.
local function Dress(b, e)
    local pin = e.pin
    b.entry = e
    if b.color ~= pin.color then
        b.color = pin.color
        local c = PN.ColorRGB(pin.color)
        b.icon:SetVertexColor(c[1], c[2], c[3], 1)
    end
    local party = e.kind == "party"
    if b.party ~= party then
        b.party = party
        b.badge:SetShown(party)
        b.badgeEdge:SetShown(party)
    end
    if b.name ~= pin.name then
        b.name = pin.name
        b.label:SetText(pin.name)   -- plain text: Pins.CleanName took out every escape sequence
    end
    b.glow:SetShown(PN.selected == e.token)
    b.label:SetShown(LabelShown(b))
end

local function HideSlot(b)
    if b.on then
        b.on = false
        b.yards = nil
        b:Hide()
        if b.over then GameTooltip:Hide(); b.over = false end
    end
end

---------------------------------------------------------------------------
-- Which pins could be here
---------------------------------------------------------------------------
-- The minimap's map and its parents, remade only when the minimap's map changes.
local function Relate(map)
    if map == relateFor then return end
    relateFor = map
    wipe(relate)
    local id = map
    for _ = 1, MAX_PARENTS do
        if not id or id == 0 then break end
        relate[id] = true
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if not (ok and type(info) == "table") then break end
        id = info.parentMapID
    end
end

local function WorldSize(map)
    local w = sizeW[map]
    if w == nil then
        local ok, width, height = pcall(C_Map.GetMapWorldSize, map)
        width, height = Readable(width), Readable(height)
        if ok and width and height and width > 0 and height > 0 then
            sizeW[map], sizeH[map] = width, height
        else
            sizeW[map], sizeH[map] = false, false
        end
        w = sizeW[map]
    end
    if w then return w, sizeH[map] end
end

-- Rebuilt when pins, choices or the switch change. Decides whether the updater needs to run at all.
local Hide, Update
function PMM.Rebuild()
    stats.rebuilds = stats.rebuilds + 1
    wipe(eligible)
    if not active then
        Hide()
        return
    end
    for _, e in ipairs(PN.Entries()) do
        if not e.dismissed then eligible[#eligible + 1] = e end
    end
    for i = 1, #eligible do
        local b = slots[i]
        if not b then
            b = NewSlot()
            slots[i] = b
        end
        Dress(b, eligible[i])
        b.px, b.py = nil, nil     -- placed again on the next update
    end
    for i = #eligible + 1, #slots do
        slots[i].entry = nil
        HideSlot(slots[i])
    end
    if driver then
        driver:SetScript("OnUpdate", #eligible > 0 and Update or nil)
    end
    wait = 0
end

function Hide()
    for _, b in ipairs(slots) do HideSlot(b); b.entry = nil end
    if driver then driver:SetScript("OnUpdate", nil) end
    stats.shown = 0
end

---------------------------------------------------------------------------
-- The updater
---------------------------------------------------------------------------
local function PlayerOn(map)
    local x = tickX[map]
    if x == nil then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if ok and type(pos) == "table" and pos.GetXY then
            local px, py = pos:GetXY()
            px, py = Readable(px), Readable(py)
            if px and py then
                tickX[map], tickY[map] = px, py
                return px, py
            end
        end
        tickX[map], tickY[map] = false, false
        return nil
    end
    if x then return x, tickY[map] end
end

local function Place(b, x, y)
    -- half a pixel is the finest the eye follows on a 140 pixel minimap
    x = math.floor(x * 2 + 0.5) / 2
    y = math.floor(y * 2 + 0.5) / 2
    if x ~= b.px or y ~= b.py then
        b.px, b.py = x, y
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", x, y)
        stats.moves = stats.moves + 1
    end
    if not b.on then
        b.on = true
        b:Show()
    end
end

local function Note(code)
    stats.last = code
    stats.reasons[code] = (stats.reasons[code] or 0) + 1
end

local function HideAll()
    for i = 1, #eligible do HideSlot(slots[i]) end
    stats.shown = 0
end

-- One pass over the pins. Under pcall (see Update), so a failure is counted and shown once rather than
-- repeated every update.
local function Step()
    local reason = Gather(view)
    stats.rotating = view.rotating
    if reason then
        -- no map for the minimap (a dungeon), no radius or facing to read, or it is hidden: nothing is placed
        HideAll()
        Note(reason)
        return
    end
    Relate(view.map)
    wipe(tickX); wipe(tickY)
    local halfWidth, radiusYards, facing, rotating = view.halfWidth, view.radius, view.facing, view.rotating
    local pixelsPerYard = halfWidth / radiusYards
    local limit = halfWidth - INSET
    local sin, cos = math.sin(facing), math.cos(facing)
    stats.range = radiusYards
    local shown = 0
    for i = 1, #eligible do
        local b, pin = slots[i], eligible[i].pin
        local placed = false
        if relate[pin.map] then
            local width, height = WorldSize(pin.map)
            local ux, uy = PlayerOn(pin.map)
            if width and ux then
                -- yards east and north of you
                local east = (pin.x / PN.COORD - ux) * width
                local north = -(pin.y / PN.COORD - uy) * height
                local sx, sy = east, north
                if rotating then
                    sx = east * cos + north * sin
                    sy = north * cos - east * sin
                end
                local px, py = sx * pixelsPerYard, sy * pixelsPerYard
                if px * px + py * py <= limit * limit then
                    b.yards = math.floor(math.sqrt(east * east + north * north) + 0.5)
                    Place(b, px, py)
                    placed = true
                    shown = shown + 1
                end
            end
        end
        if not placed then HideSlot(b) end
    end
    stats.shown = shown
    Note("ok")
end

function Update(_, seconds)
    wait = wait - (seconds or 0)
    if wait > 0 then return end
    wait = view.rotating and FAST or SLOW
    stats.ticks = stats.ticks + 1
    if not Minimap:IsVisible() then
        -- its pins are its children and hidden with it; nothing to work out
        stats.last = "minimap-hidden"
        return
    end
    local ok, err = pcall(Step)
    if not ok then
        stats.errors = stats.errors + 1
        stats.last = "error"
        HideAll()
        if not stats.reported then
            stats.reported = true
            R.Fault("party pins minimap", err)   -- once; later ones are only counted
        end
    end
end
PMM.Update = Update

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------
local function Refresh()
    local want = Enabled()
    if want and not active then
        if not driver then driver = CreateFrame("Frame") end
        active = true
        relateFor = nil
    elseif not want and active then
        active = false
    end
    PMM.Rebuild()
end
PMM.Refresh = Refresh

-- The minimap's map changes with the zone; the next update notices it. A change of pins, choices or the
-- switch rebuilds the list.
PN.OnChange(function() if active then PMM.Rebuild() end end)
-- Other choices (the window's place, the world map's labels) don't concern the minimap, except whether
-- names are drawn beside its pins, which only shows or hides what is already there.
PL.OnPrefChange(function()
    if Enabled() ~= active then
        Refresh()
    else
        for i = 1, #eligible do slots[i].label:SetShown(LabelShown(slots[i])) end
    end
end)
R:On("PLAYER_LOGIN", Refresh)

-- Read only, for /tui diagnostics: states, kinds and counts, never names, places or coordinates. It asks the
-- game again now (the same reads the updater makes), so a report shows what the updater would see.
function PMM.Snapshot()
    local now = {}
    local reason
    if Minimap then reason = Gather(now) else reason = "no-minimap" end
    local reasons = {}
    for code, n in pairs(stats.reasons) do reasons[#reasons + 1] = code .. " " .. n end
    table.sort(reasons)
    -- the first pin that could be on it: is its map related, sized, and does the player have a place on it?
    local probe
    local first = eligible[1]
    if first and now.map then
        Relate(now.map)
        local width = WorldSize(first.pin.map)
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, first.pin.map, "player")
        local x
        if ok and type(pos) == "table" and pos.GetXY then x = pos:GetXY() end
        probe = {
            related = relate[first.pin.map] == true, sized = width ~= nil,
            position = ok and (type(pos) == "nil" and "nil" or ((issecretvalue and issecretvalue(x)) and "secret" or (Readable(x) and "yes" or "unreadable"))) or "error",
        }
    end
    return {
        active = active, minimap = Minimap ~= nil, eligible = #eligible, shown = stats.shown, slots = #slots,
        running = driver ~= nil and driver:GetScript("OnUpdate") ~= nil, ticks = stats.ticks, moves = stats.moves,
        rebuilds = stats.rebuilds, rotating = stats.rotating, rangeYards = stats.range,
        errors = stats.errors, last = stats.last, reasons = reasons, now = reason or "ok",
        visible = now.visible, mapKind = now.mapKind, mapSource = now.mapSource,
        radiusKind = now.radiusKind, radiusSource = now.radiusSource, radius = now.radius,
        width = now.halfWidth and now.halfWidth * 2 or nil, facingKind = now.facingKind, probe = probe,
    }
end

-- For tests: where each slot is now.
function PMM.State()
    local out = {}
    for i = 1, #eligible do
        local b = slots[i]
        out[i] = { token = eligible[i].token, shown = b.on == true, x = b.px, y = b.py, yards = b.yards,
            name = b.label:IsShown() and b.label:GetText() or nil }
    end
    return out
end
