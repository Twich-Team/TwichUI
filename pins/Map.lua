-- TwichUI: Party pins on the world map
-- Draws local and party pins on the game's world map, and places new ones from a map click.
--   Drawing: a map data provider (the map's own extension point, MapCanvasDataProviderMixin) is told when
--     the map, its zoom or its size changes, and lays out TwichUI's own buttons on the map's canvas. Each
--     is TwichUI's own pin shape (media/textures/map-pin.tga, a bevelled diamond) tinted with the pin's
--     color, its middle on the place; a party pin also carries a small parchment badge, so local and party
--     pins differ by shape as well as color. A pin is drawn on the map it was placed on and on that map's parents (a zone pin on
--     its continent), placed there through the game's own world-position conversion; never on a sibling or
--     child map, so it can't land on the wrong map.
--     Nothing runs per frame: work happens only when the map changes, zooms or a pin changes.
--   Placing: a canvas click handler (the map's own, which runs addon handlers through securecallfunction)
--     answers only the exact clicks chosen in Party pins options (Alt-click and Alt-Shift-click unless
--     changed) or one click after Place a pin; every other click carries on to the map as before. Ctrl-
--     click stays the game's waypoint, and the player's own waypoint is never changed except by Set
--     waypoint. A click opens the pin editor: nothing is made, and nothing sent, until it is saved.
-- TwichUI never opens or closes the world map itself (opening it from addon code can leave it unable to
-- do some things in combat); Show on map moves an open map, or waits for the player to open it.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local PM = {}
R.PinsMap = PM

local PIN_SIZE = 24                      -- the square the pin texture fills (the diamond itself is 60 of 64)
local CLICK_PRIORITY = 95                   -- before the game's waypoint handler (90); only exact clicks are taken
local ARM_SECONDS = 60
local FOCUS_SECONDS = 120
local MAX_PARENTS = 8

local provider, canvas
local installed = false      -- provider and handlers are on the map now
local pool, used = {}, 0
local armed = 0              -- GetTime() until which one plain click places a pin
local focus                  -- { token, map, until }: Show on map while the map was closed
local stats = { layouts = 0, drawn = 0, unplaced = 0, refused = 0 }

local function Enabled() return R:Enabled("partyPins") end
local function Notice(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end
PM.Notice = Notice

local function MapOpen() return WorldMapFrame and WorldMapFrame:IsShown() end

---------------------------------------------------------------------------
-- Where a pin is on a map, or nil
---------------------------------------------------------------------------
local function IsAncestor(viewed, map)
    local id = map
    for _ = 1, MAX_PARENTS do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if not ok or type(info) ~= "table" then return false end
        id = info.parentMapID
        if not id or id == 0 then return false end
        if id == viewed then return true end
    end
    return false
end

function PM.Position(pin, viewed)
    local x, y = pin.x / PN.COORD, pin.y / PN.COORD
    if pin.map == viewed then return x, y end
    if not viewed or not IsAncestor(viewed, pin.map) then return nil end
    local ok, mx, my = pcall(function()
        local continent, world = C_Map.GetWorldPosFromMapPos(pin.map, CreateVector2D(x, y))
        if not continent or not world then return nil end
        local map, pos = C_Map.GetMapPosFromWorldPos(continent, world, viewed)
        if map ~= viewed or not pos then return nil end
        return pos:GetXY()
    end)
    if ok and mx and my and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then return mx, my end
    return nil
end

---------------------------------------------------------------------------
-- The pin buttons
---------------------------------------------------------------------------
local function LabelShown(b)
    if PL.Pref("labels") == "always" then return true end
    return b.over or (b.entry and PN.selected == b.entry.token)
end

-- anchor: where the tooltip goes (the map's by default); yards: how far you are from it, on the minimap.
local function Tooltip(b, anchor, yards)
    local e = b.entry
    if not e then return end
    local pin = e.pin
    GameTooltip:SetOwner(b, anchor or "ANCHOR_RIGHT", anchor and 0 or -4, anchor and 0 or -4)
    GameTooltip:SetText(pin.name, 1, 1, 1, 1, true)
    local SH = R.Share
    if e.kind == "local" then
        GameTooltip:AddLine(pin.copiedFrom and ("Local pin, copied from " .. pin.copiedFrom .. "'s") or "Local pin", 0.78, 0.74, 0.66)
    elseif pin.mine then
        GameTooltip:AddLine("Your party pin", 0.86, 0.69, 0.30)
    else
        GameTooltip:AddLine("Party pin from " .. (SH and SH.Short(pin.owner) or pin.owner), 0.86, 0.69, 0.30)
    end
    GameTooltip:AddLine(PN.Describe(pin), 0.62, 0.58, 0.51)
    if yards then GameTooltip:AddLine(("About %d yards away"):format(yards), 0.78, 0.74, 0.66) end
    GameTooltip:AddLine("Right-click for actions", 0.45, 0.43, 0.38)
    GameTooltip:Show()
end
PM.Tooltip = Tooltip

local function OnEnter(b)
    b.over = true
    b.label:SetShown(LabelShown(b))
    Tooltip(b)
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
        PN.Select(PN.selected == e.token and nil or e.token)
    end
end

local function NewPin()
    local b = CreateFrame("Button", nil, canvas)
    b:SetSize(PIN_SIZE, PIN_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- the selected pin's glow: the same shape, larger, behind
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture(PL.PIN_TEXTURE)
    b.glow:SetPoint("CENTER", 0, 0)
    b.glow:SetSize(PIN_SIZE + 6, PIN_SIZE + 6)
    b.glow:SetVertexColor(1, 0.95, 0.80, 0.55)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(PL.PIN_TEXTURE)
    b.icon:SetAllPoints()
    -- the party badge: a parchment square with a dark edge on the diamond's upper-right edge
    b.badgeEdge = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.badgeEdge:SetColorTexture(0.06, 0.04, 0.03, 1)
    b.badgeEdge:SetSize(8, 8)
    b.badgeEdge:SetPoint("CENTER", b, "TOPLEFT", PL.BadgePoint(PIN_SIZE))
    b.badge = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.badge:SetColorTexture(0.93, 0.87, 0.71, 1)
    b.badge:SetSize(6, 6)
    b.badge:SetPoint("CENTER", b.badgeEdge, "CENTER", 0, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(PL.PIN_TEXTURE)
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.35)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, 2)
    b.label:SetWidth(140)
    b.label:SetWordWrap(false)
    b.label:SetJustifyH("CENTER")
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("OnClick", OnClick)
    return b
end

-- Only what changed is set again.
local function Dress(b, e)
    local pin = e.pin
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
    b.entry = e
    local selected = PN.selected == e.token
    b.glow:SetShown(selected)
    b.label:SetShown(LabelShown(b))
end

local function FrameLevel()
    local ok, level = pcall(function()
        return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    end)
    return (ok and type(level) == "number") and level or (canvas:GetFrameLevel() + 500)
end

local function Place(b)
    local scale = WorldMapFrame:GetCanvasScale()
    if not scale or scale <= 0 then return end
    local global = WorldMapFrame.GetGlobalPinScale and WorldMapFrame:GetGlobalPinScale() or 1
    local s = global / scale
    b:SetScale(s)
    b:ClearAllPoints()
    -- the middle of the diamond is the place
    b:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * b.mx / s, -canvas:GetHeight() * b.my / s)
end

local function HideFrom(n)
    for i = n, #pool do
        local b = pool[i]
        if b:IsShown() then b:Hide() end
        b.entry, b.over = nil, false
    end
end

-- Everything on the map now. Runs when the map, the pins or the choices change; never per frame.
function PM.Layout()
    if not (installed and MapOpen()) then return end
    local viewed = WorldMapFrame:GetMapID()
    stats.layouts = stats.layouts + 1
    used = 0
    local level = FrameLevel()
    local unplaced = 0
    for _, e in ipairs(PN.Entries()) do
        if not e.dismissed then
            local x, y = PM.Position(e.pin, viewed)
            if x then
                used = used + 1
                local b = pool[used]
                if not b then
                    b = NewPin()
                    pool[used] = b
                end
                b.mx, b.my = x, y
                b:SetFrameLevel(level + (e.kind == "party" and 1 or 0))
                Dress(b, e)
                Place(b)
                b:Show()
            elseif e.pin.map == viewed then
                unplaced = unplaced + 1
            end
        end
    end
    HideFrom(used + 1)
    stats.drawn, stats.unplaced = used, unplaced
end

local function Rescale()
    if not (installed and MapOpen()) then return end
    for i = 1, used do Place(pool[i]) end
end

---------------------------------------------------------------------------
-- Placing
---------------------------------------------------------------------------
function PM.Armed() return armed > GetTime() end

-- Place a pin: the next plain left-click on the map, within a minute.
function PM.Arm()
    if not Enabled() then return false end
    armed = GetTime() + ARM_SECONDS
    if MapOpen() then
        Notice("Click the map where the pin goes.")
    else
        Notice("Open your map and click where the pin goes.")
    end
    return true
end

function PM.Disarm() armed = 0 end

local function OnCanvasClick(_, button, cx, cy)
    if not (Enabled() and installed) then return false end
    local kind
    if PL.Matches("localClick", button) then kind = "local"
    elseif PL.Matches("partyClick", button) then kind = "party"
    elseif PM.Armed() and button == "LeftButton" and not (IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown()) then
        kind = "choose"
    end
    if not kind then return false end
    armed = 0
    local map = WorldMapFrame:GetMapID()
    local x, y = PN.Quantize(cx), PN.Quantize(cy)
    if not (PN.ValidMap(map) and x and y) then
        stats.refused = stats.refused + 1
        Notice(PN.Reason(not PN.ValidMap(map) and "unknown-map" or "bad-coordinates"))
        return true
    end
    if R.PinsEditor then R.PinsEditor.OpenNew(map, x, y, kind == "party") end
    return true   -- this click made a pin: the map doesn't also zoom or move
end

local function Cursor()
    if not Enabled() then return nil end
    if PM.Armed() or PL.Held() then return "MAP_PIN_CURSOR" end
    return nil
end

---------------------------------------------------------------------------
-- Show on map, and the map's lifecycle
---------------------------------------------------------------------------
local function ApplyFocus()
    local f = focus
    focus = nil
    if not (f and f.untilTime > GetTime() and MapOpen()) then return end
    if WorldMapFrame:GetMapID() ~= f.map then WorldMapFrame:SetMapID(f.map) end
    PN.Select(f.token)
end

-- Moves an open map to the pin and picks it out. With the map closed, it is picked out now and shown
-- when the player next opens the map (within two minutes).
function PM.ShowOnMap(e)
    local ok, why = PN.Can("show", e)
    if not ok then Notice(why) return false end
    local pin = PN.Fresh(e)
    if MapOpen() and installed then
        if WorldMapFrame:GetMapID() ~= pin.map then WorldMapFrame:SetMapID(pin.map) end
        PN.Select(e.token)
        PM.Layout()
    else
        PN.Select(e.token)
        focus = { token = e.token, map = pin.map, untilTime = GetTime() + FOCUS_SECONDS }
        Notice("Open your map to see it.")
    end
    return true
end

-- The game's waypoint, only when asked. It replaces the waypoint you had, as setting one in the game does.
function PM.SetWaypoint(e)
    local ok, why = PN.Can("waypoint", e)
    if not ok then Notice(why) return false end
    local pin = PN.Fresh(e)
    local set = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(pin.map, pin.x / PN.COORD, pin.y / PN.COORD))
    if not set then Notice(PN.Reason("no-waypoint")) return false end
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK) end
    return true
end

local function Build()
    if provider or not WorldMapFrame or not MapCanvasDataProviderMixin then return false end
    canvas = WorldMapFrame:GetCanvas()
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData() HideFrom(1); used = 0 end
    function provider:RefreshAllData() PM.Layout() end
    function provider:OnMapChanged() PM.Layout() end
    function provider:OnCanvasSizeChanged() PM.Layout() end
    function provider:OnCanvasScaleChanged() Rescale() end
    function provider:OnShow()
        if focus then C_Timer.After(0, ApplyFocus) end   -- after the map has finished opening
    end
    return true
end

-- On with the switch, off without it: TwichUI's pins and handlers are put on the map or taken off it.
-- The game's own pins and handlers, and other addons', are not touched.
function PM.Refresh()
    if not WorldMapFrame then return end
    if not Build() and not provider then return end
    local want = Enabled()
    if want and not installed then
        WorldMapFrame:AddDataProvider(provider)
        WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
        if WorldMapFrame.AddCursorHandler then WorldMapFrame:AddCursorHandler(Cursor, CLICK_PRIORITY) end
        installed = true
        PM.Layout()
    elseif not want and installed then
        WorldMapFrame:RemoveCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
        if WorldMapFrame.RemoveCursorHandler then WorldMapFrame:RemoveCursorHandler(Cursor, CLICK_PRIORITY) end
        WorldMapFrame:RemoveDataProvider(provider)   -- hides every TwichUI pin (RemoveAllData)
        installed, armed, focus = false, 0, nil
    end
end

PN.OnChange(function() if installed and MapOpen() then PM.Layout() end end)
PL.OnPrefChange(function() if installed and MapOpen() then PM.Layout() end end)

-- The world map is loaded when it is first needed (or with the game).
R:On("PLAYER_LOGIN", PM.Refresh)
R:On("ADDON_LOADED", function(name) if name == "Blizzard_WorldMap" then PM.Refresh() end end)

-- Read only, for /tui diagnostics.
function PM.Snapshot()
    return {
        mapLoaded = WorldMapFrame ~= nil, provider = provider ~= nil, installed = installed,
        open = MapOpen() and true or false, drawn = stats.drawn, unplaced = stats.unplaced,
        layouts = stats.layouts, refused = stats.refused, pool = #pool, armed = PM.Armed(),
        waiting = focus ~= nil,
    }
end
