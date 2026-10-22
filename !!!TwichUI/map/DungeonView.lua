-- TwichUI: world map exploration, dungeon maps
-- A dungeon or raid is a world of its own: its map is not laid on the zone outside (nothing converts between the two),
-- so it is shown on a panel over the world map's canvas, one floor at a time, with its own zoom (the wheel, at the
-- pointer), panning (drag) and the zoom buttons, and the context bar at the top for its name, floors and Back.
--   Which dungeons: those whose map art and building map/Data.lua found byte-identical in Forever's client (the others'
--     entrances say no map is known). The art is the game's own; TwichUI ships none.
--   What it doesn't show: your position (the game gives addons no position inside an instance) and pins or pings
--     (they belong to the world maps): a click with a pin or ping shortcut, or with a map tool armed, says so instead.
--   Opened from a dungeon's marker (map/Places.lua) or the "Inside" button while you are in the dungeon. Closed by Back,
--     Leave, a right-click, the world map changing or closing, or map exploration going off.
-- The floor's twelve textures are set while it is shown and let go when it closes.

local R = TwichUI
local VM, MXP, MV = R.MapViewMath, R.MapExplorePrefs, R.MapView
local DV = {}
R.MapDungeonView = DV

local ART_W, ART_H, TILE = 1002, 668, 256
local MAX_FACTOR = 4
local FIT_SHARE = 0.96
local DRAG_PX = 4                 -- a press that moves further than this (map units) is a drag, not a click
local LEVEL = 9100                -- over every pin on the canvas (the map's pins stop at 9000)

local view, page, tiles = nil, nil, {}
local open                        -- { inst, floor, scale, fit, cx, cy }
local drag                        -- { x, y, cx, cy, moved }
local stats = { opened = 0, refused = 0 }

function DV.Has(inst)
    local D = R.MapExploreData
    local d = D and D.dungeons and D.dungeons[inst]
    return d ~= nil and #(d.floors or {}) > 0
end
function DV.IsOpen() return open ~= nil end
function DV.Factor() return open and open.scale / open.fit or 1 end
function DV.Current() return open and open.inst or nil, open and open.floor or nil end

local function Data() return R.MapExploreData.dungeons[open.inst] end

local function Name(inst)
    local ok, name = pcall(GetRealZoneText, inst)
    if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then return name end
    return R.MapExploreData.dungeons[inst].name
end
DV.Name = Name

local function Cursor()
    local x, y = GetCursorPosition()
    local s = view:GetEffectiveScale()
    local left, top = view:GetLeft(), view:GetTop()
    if not (left and top) then return nil end
    return x / s - left, top - y / s
end

local function Apply()
    local vw, vh = view:GetWidth(), view:GetHeight()
    open.cx, open.cy = VM.ClampCenter(open.cx, open.cy, vw, vh, ART_W, ART_H, open.scale)
    local s = open.scale
    page:SetScale(s)
    page:ClearAllPoints()
    page:SetPoint("TOPLEFT", view, "TOPLEFT", (vw / 2 - open.cx * ART_W * s) / s, -(vh / 2 - open.cy * ART_H * s) / s)
    if R.MapControls then R.MapControls.Update() end
end

function DV.Fit()
    if not open then return end
    open.fit = VM.FitScale(view:GetWidth(), view:GetHeight(), ART_W, ART_H) * FIT_SHARE
    open.scale, open.cx, open.cy = open.fit, 0.5, 0.5
    Apply()
end

-- Zoom about a point of the picture (0..1; the middle by default).
function DV.ZoomBy(notches, ax, ay)
    if not open then return end
    local s = VM.Step(open.scale, notches, MXP.Get("wheelStep"), open.fit, open.fit * MAX_FACTOR)
    if not ax then ax, ay = open.cx, open.cy end
    open.cx, open.cy = VM.Anchored(open.scale, open.cx, open.cy, s, ax, ay)
    open.scale = s
    Apply()
end
function DV.ZoomStep(n) DV.ZoomBy(n) end

local function Bar()
    local MC = R.MapControls
    if not MC then return end
    local d = Data()
    local n = #d.floors
    MC.ShowContext("dungeon", {
        title = Name(open.inst), sub = d.raid and "Raid map" or "Dungeon map",
        note = "Your position isn't shown here, and pins can't be placed on it.",
        floors = n, floor = open.floor, floorName = d.floors[open.floor][2],
        onPrev = function() DV.SetFloor(open and open.floor - 1) end,
        onNext = function() DV.SetFloor(open and open.floor + 1) end,
        onLeave = function() DV.Close() end,
        leaveTitle = "Back to the map", leaveTip = "Closes the dungeon's map. A right-click does the same.",
    })
end

local function ShowFloor()
    local fl = Data().floors[open.floor]
    for i = 1, 12 do
        local row, col = math.floor((i - 1) / 4), (i - 1) % 4
        local px0, py0 = col * TILE, row * TILE
        local pw, ph = math.min(TILE, ART_W - px0), math.min(TILE, ART_H - py0)
        local tex = tiles[i]
        tex:SetTexture(fl[3][i])
        tex:SetTexCoord(0, pw / TILE, 0, ph / TILE)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", page, "TOPLEFT", px0, -py0)
        tex:SetSize(pw, ph)
        tex:Show()
    end
end

local function Refuse()
    stats.refused = stats.refused + 1
    MV.Notice("Pins and pings can't be placed on a dungeon's map.")
end

local function Armed()
    return (R.MapTools and R.MapTools.Armed and R.MapTools.Armed() ~= nil) or (R.PinsMap and R.PinsMap.Armed and R.PinsMap.Armed())
end

local function OnUpdate()
    if not (drag and open) then return end
    local x, y = Cursor()
    if not x then return end
    local dx, dy = x - drag.x, y - drag.y
    if not drag.moved and dx * dx + dy * dy > DRAG_PX * DRAG_PX then drag.moved = true end
    if drag.moved then
        open.cx = drag.cx - dx / (open.scale * ART_W)
        open.cy = drag.cy - dy / (open.scale * ART_H)
        Apply()
    end
end

local function Build()
    if view then return end
    local sc = MV.Container()
    view = CreateFrame("Frame", "TwichUIDungeonMap", sc)
    view:SetAllPoints(sc)
    view:SetFrameLevel(LEVEL)
    view:EnableMouse(true)                 -- clicks here are this map's, never the world map's
    view:EnableMouseWheel(true)
    view:SetClipsChildren(true)
    view:Hide()
    local bg = view:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.08, 0.06, 0.97)
    page = CreateFrame("Frame", nil, view)
    page:SetSize(ART_W, ART_H)
    for i = 1, 12 do tiles[i] = page:CreateTexture(nil, "ARTWORK") end
    view:SetScript("OnMouseWheel", function(_, delta)
        local x, y = Cursor()
        if not (x and open) then return end
        local vw, vh = view:GetWidth(), view:GetHeight()
        local ax = open.cx + (x - vw / 2) / (open.scale * ART_W)
        local ay = open.cy + (y - vh / 2) / (open.scale * ART_H)
        DV.ZoomBy(delta > 0 and 1 or -1, ax, ay)
    end)
    view:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not open then return end
        local x, y = Cursor()
        if not x then return end
        drag = { x = x, y = y, cx = open.cx, cy = open.cy, moved = false }
        view:SetScript("OnUpdate", OnUpdate)
    end)
    view:SetScript("OnMouseUp", function(_, button)
        view:SetScript("OnUpdate", nil)
        local moved = drag and drag.moved
        drag = nil
        if moved then return end
        if button == "RightButton" then DV.Close() return end
        local shortcut = (IsAltKeyDown and IsAltKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown())
        if shortcut or Armed() then Refuse() end
    end)
    view:SetScript("OnHide", function() view:SetScript("OnUpdate", nil) drag = nil end)
end

-- Opens a dungeon's map (its first floor unless told). Returns whether it opened.
function DV.Open(inst, floor)
    if not (DV.Has(inst) and MV.Ready()) then return false end
    if R.MapCaves then R.MapCaves.Sink() end
    Build()
    local n = #R.MapExploreData.dungeons[inst].floors
    open = { inst = inst, floor = math.max(1, math.min(floor or 1, n)) }
    stats.opened = stats.opened + 1
    MV.Stop()
    view:Show()
    ShowFloor()
    DV.Fit()
    Bar()
    if R.MapPlaces then R.MapPlaces.HideAll() end
    MV.Dirty()
    return true
end

function DV.SetFloor(i)
    if not (open and i) then return false end
    local n = #Data().floors
    if i < 1 or i > n or i == open.floor then return false end
    open.floor = i
    ShowFloor()
    DV.Fit()
    Bar()
    return true
end

function DV.Close()
    if not open then return end
    open, drag = nil, nil
    view:Hide()
    for _, t in ipairs(tiles) do t:SetTexture(nil) t:Hide() end
    if R.MapControls then R.MapControls.HideContext("dungeon") end
    MV.Dirty()
end

MV.Subscribe(function(event)
    if not open then return end
    if event == "map" or event == "hide" or event == "off" then DV.Close()
    elseif event == "size" then DV.Fit() end
end)

-- Read only, for /tui diagnostics and the tests.
function DV.Snapshot()
    local out = { open = open ~= nil }
    if open then out.inst, out.floor, out.factor = open.inst, open.floor, DV.Factor() end
    for k, v in pairs(stats) do out[k] = v end
    return out
end
function DV.Tile(i) return tiles[i] end
function DV.Frame() return view end
