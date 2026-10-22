-- TwichUI: world map exploration, the view
-- One seamless map: the game's world map with every continent's and zone's painting stitched onto it (map/Art.lua), so
-- the mouse wheel goes from the whole world into any zone, cave or city and back without the map jumping. The game's map
-- stays underneath: its canvas, its pins, its quest areas. Once the view has been still a moment, the map underneath
-- quietly becomes the one you are looking at (the world, a continent, a zone, a city), so the game's own pins, quest
-- areas and coordinates are the ones for what is on screen. Everything TwichUI draws sits in that same view.
--
-- "World" coordinates are the world map's 0..1 (map/World.lua); zoom is 1 where the whole world fits the view.
--   Wheel: zoom about the point under the pointer (it stays put), eased (or at once, a choice). The deepest zoom is a
--     choice (default 48 times the whole world), a little more over a city, and as far as a cave's map needs over a cave.
--   Drag: the game's own panning, anywhere on the world. A press stops an ease.
--   Click: into the next map down under the pointer (framed); right-click: out to the map above. Clicks the map's other
--     handlers take (TwichUI's pins, pings, map tools, the waypoint) are theirs: this one comes last.
--   Back: a jump (a travel link, a place) remembers the view it left, at most BACK_LIMIT, this session only.
--   A resize keeps the place and how far in. Another map shown by the game (its dropdown, a quest) is shown whole.
--
-- How it touches the game's map (as OpenMap does, approved for this): a data provider; hooks on the scroll container's
-- wheel and press and on its zoom-level set-up (panning allowed at every zoom: baseScale); its scroll limits replaced
-- while installed (the original put back when off), so the view can go anywhere on the world whatever map is underneath;
-- its wheel zoom mode set to none while the stitched map shows; its own InstantPanAndZoom to place the view; SetMapID to
-- follow the view, never in combat (it waits). Maps that aren't part of the world (a battleground, Zephras Isle) are the
-- game's own, with its own wheel zoom. Off, everything is put back and the map is shown whole.
-- While OpenMap is loaded this stays off (MV.Blocker); nothing of OpenMap's is called or changed.

local R = TwichUI
local VM, MXP, MW = R.MapViewMath, R.MapExplorePrefs, R.MapWorld
local MV = {}
R.MapView = MV

local WHEEL_SECONDS, GLIDE_SECONDS = 0.18, 0.45
local BACK_LIMIT = 12
local SETTLE = 0.6               -- seconds the view is still before the map underneath follows it
local ENTER, LEAVE = 0.9, 0.7    -- a map becomes the one underneath at this share of its whole-map zoom; stops below that
local CITY_DEEPER = 1.5
local CLICK_PRIORITY = 1         -- the map's click handlers: the last (pins 95, pings 105, tools 110 come first)
local PRESS = "LeftButton"

local map, sc
local provider
local installed, hooked = false, false
local active = false             -- the map underneath is part of the world, and the stitched painting is on it
local switching = false
local savedWheel, origExtents
local anim, driver
local follower, stillFor = nil, 0
local notifier
local frames = {}                -- [mapID] = the map's place in world yards (VM.MapFrame + cont), or false
local back = {}
local lastView, resizeRestore
local listeners = {}
local stats = { wheel = 0, glides = 0, switches = 0, waits = 0, pressed = 0, dragged = 0, notified = 0, resized = 0, clicks = 0 }

local function Notice(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end
MV.Notice = Notice

local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Whether it runs
---------------------------------------------------------------------------
function MV.Blocker()
    local api = C_AddOns
    if api and api.IsAddOnLoaded and api.IsAddOnLoaded("OpenMap") then return "OpenMap" end
    return nil
end

function MV.Wanted() return R:Enabled("mapExplore") and MV.Blocker() == nil end
function MV.Installed() return installed end
function MV.Active() return active end

local function Shown() return map ~= nil and map:IsShown() end
MV.Shown = Shown

-- Ready: the stitched map is up on an open map.
local function Ready() return installed and active and Shown() end
MV.Ready = Ready

---------------------------------------------------------------------------
-- Telling the other parts
---------------------------------------------------------------------------
-- fn(event): "view" (once a frame at most, after the view moved), "scale" (at once), "attach" (the map underneath
-- changed or the stitched map came or went), "map", "show", "hide", "back", "on", "off".
function MV.Subscribe(fn) listeners[#listeners + 1] = fn end
local function Emit(event)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, event)
        if not ok and R.Fault then R.Fault("map " .. event, err) end
    end
end
MV.Emit = Emit

---------------------------------------------------------------------------
-- The view in world terms
---------------------------------------------------------------------------
function MV.MapID() return map and map:GetMapID() or nil end
function MV.Canvas() return map and map:GetCanvas() end
function MV.Container() return sc end
function MV.Scale() return sc:GetCanvasScale() end
function MV.ViewSize() return sc:GetWidth(), sc:GetHeight() end
function MV.CanvasSize() return sc.Child:GetWidth(), sc.Child:GetHeight() end

local function FitPx()
    local W, H = MW.Size()
    local vw, vh = MV.ViewSize()
    return math.min(vw / W, vh / H)
end

-- canvas units of map `id` per world pixel
local function K(id)
    local a = MW.Art(id)
    local l, r = MW.Rect(id)
    local W = MW.Size()
    return a.w / ((r - l) * W)
end

-- The view: its middle (world) and zoom.
function MV.View()
    local id = MV.MapID()
    local u, v = MW.ToWorld(id, sc:GetCurrentScrollX() or 0.5, sc:GetCurrentScrollY() or 0.5)
    return u, v, MV.Scale() * K(id) / FitPx()
end

-- The zoom at which map `id` just fits the view.
function MV.FitZoom(id)
    local l, r, t, b = MW.Rect(id)
    if not l then return nil end
    local W, H = MW.Size()
    local vw, vh = MV.ViewSize()
    return math.min(vw / ((r - l) * W), vh / ((b - t) * H)) / FitPx()
end

-- The zoom at which a world rectangle just fits the view.
function MV.RectZoom(u0, v0, u1, v1)
    local W, H = MW.Size()
    local vw, vh = MV.ViewSize()
    return math.min(vw / ((u1 - u0) * W), vh / ((v1 - v0) * H)) / FitPx()
end

-- World units across one map unit of the view at `zoom`.
local function PerPx(zoom)
    local W, H = MW.Size()
    local px = FitPx() * zoom
    return 1 / (W * px), 1 / (H * px)
end

-- The part of the world in view: u0, v0, u1, v1.
function MV.ViewRect()
    local u, v, zoom = MV.View()
    local vw, vh = MV.ViewSize()
    local pu, pv = PerPx(zoom)
    return u - vw / 2 * pu, v - vh / 2 * pv, u + vw / 2 * pu, v + vh / 2 * pv
end

-- The pointer's offset from the view's middle, in the map's units (y down).
local function CursorOffset()
    local x, y = sc:GetCursorPosition()
    local vw, vh = MV.ViewSize()
    local left, top = sc:GetLeft(), sc:GetTop()
    if not (x and left) then return 0, 0 end
    return x - (left + vw / 2), (top - vh / 2) - y
end

-- Where the pointer is on the world, and the zoom.
function MV.CursorWorld()
    local u, v, zoom = MV.View()
    local sx, sy = CursorOffset()
    local pu, pv = PerPx(zoom)
    return u + sx * pu, v + sy * pv, zoom
end

local function ShowWorld(u, v, zoom)
    local id = MV.MapID()
    local x, y = MW.FromWorld(id, u, v)
    sc:InstantPanAndZoom(zoom * FitPx() / K(id), x, y, true)
end

-- The deepest zoom at a world point: the choice, more over a city, and over a cave as far as its map needs.
function MV.MaxZoomAt(u, v)
    local most = MXP.Get("maxZoom")
    local MA = R.MapArt
    if u and MA and MA.CityAt(u, v) then most = most * CITY_DEEPER end
    local caves = R.MapCaves
    local cave = u and caves and caves.FillZoomAt(u, v)
    if cave then most = math.max(most, cave) end
    return most
end

-- A map's place in world yards (continent, and its corners), through Navigation's checked conversion.
function MV.MapFrame(id)
    if type(id) ~= "number" then return nil end
    local f = frames[id]
    if f ~= nil then return f or nil end
    local World = R.Nav and R.Nav.World
    f = false
    if World then
        local c1, tlx, tly = World(id, 0, 0)
        local c2, trx, try = World(id, 1, 0)
        local c3, blx, bly = World(id, 0, 1)
        if c1 and c1 == c2 and c1 == c3 then
            local made = VM.MapFrame(tlx, tly, trx, try, blx, bly)
            if made then
                made.cont = c1
                f = made
            end
        end
    end
    frames[id] = f
    return f or nil
end

-- Whether the view is past where the painting has anything finer, with nothing finer laid over it.
function MV.Enlarged()
    if not Ready() then return false end
    local u, v, zoom = MV.View()
    local id = MW.Deepest(u, v)
    local fit = MV.FitZoom(id)
    local MD = R.MapDetail
    return fit ~= nil and zoom > fit * 2.5 and not (MD and MD.Showing())
end

-- The canvas's frame level plus offset: what is drawn over the map's art and under its pins (detail 6, caves 7).
function MV.ArtLevel(offset)
    local canvas = MV.Canvas()
    return (canvas and canvas:GetFrameLevel() or 0) + offset
end

---------------------------------------------------------------------------
-- Moving
---------------------------------------------------------------------------
local function StopAnim()
    anim = nil
    if driver then driver:SetScript("OnUpdate", nil) end
end
MV.Stop = StopAnim

local function Frame(a, k)
    local zoom = VM.LogLerp(a.z0, a.z1, k)
    if a.mode == "anchor" then
        local pu, pv = PerPx(zoom)
        return a.au - a.sx * pu, a.av - a.sy * pv, zoom
    end
    -- a glide: the middle moves with 1/zoom, as zooming about one still point looks
    local w = math.abs(a.z1 - a.z0) < 1e-9 and k or (1 / a.z0 - 1 / zoom) / (1 / a.z0 - 1 / a.z1)
    return a.u0 + (a.u1 - a.u0) * w, a.v0 + (a.v1 - a.v0) * w, zoom
end

local Follow

local function Step(_, elapsed)
    local a = anim
    if not a or not Ready() or MV.MapID() ~= a.map then StopAnim() return end
    a.t = a.t + math.min(elapsed or 0, 0.1)
    local done = a.t >= a.dur
    ShowWorld(Frame(a, done and 1 or VM.Ease(a.t / a.dur)))
    if done then
        StopAnim()
        if a.done then a.done() end
    end
end

local function Start(a)
    a.map = MV.MapID()
    if not MXP.Get("smooth") or not a.dur or a.dur <= 0 then
        StopAnim()
        ShowWorld(Frame(a, 1))
        if a.done then a.done() end
        return
    end
    a.t = 0
    anim = a
    driver = driver or CreateFrame("Frame")
    driver:SetScript("OnUpdate", Step)
end

function MV.Animating() return anim ~= nil end

-- Zoom by wheel notches about a screen point (sx, sy: from the view's middle; the pointer's by default).
function MV.ZoomBy(notches, sx, sy)
    if not Ready() or notches == 0 then return false end
    local u, v, zoom = MV.View()
    if not sx then sx, sy = CursorOffset() end
    local pu, pv = PerPx(zoom)
    local au, av = u + sx * pu, v + sy * pv
    local from = (anim and anim.mode == "anchor") and anim.z1 or zoom
    local most = MV.MaxZoomAt(au, av)
    if notches > 0 then most = math.max(most, math.min(from, zoom)) end   -- zooming in never pushes you out
    local target = VM.Clamp(from * (1 + MXP.Get("wheelStep") / 100) ^ notches, 1, math.max(most, 1))
    if math.abs(target - zoom) < 1e-9 and not anim then return false end
    stats.wheel = stats.wheel + 1
    Start({ mode = "anchor", au = au, av = av, sx = sx, sy = sy, z0 = zoom, z1 = target, dur = WHEEL_SECONDS })
    return true
end

function MV.ZoomStep(notches) return MV.ZoomBy(notches, 0, 0) end

-- A glide to a world point at `zoom` (within the limits there). done: once there.
function MV.GlideTo(u, v, zoom, done)
    if not Ready() then return false end
    local u0, v0, z0 = MV.View()
    stats.glides = stats.glides + 1
    Start({ mode = "glide", u0 = u0, v0 = v0, z0 = z0, u1 = u, v1 = v,
        z1 = VM.Clamp(zoom, 1, math.max(MV.MaxZoomAt(u, v), 1)), dur = GLIDE_SECONDS, done = done })
    return true
end

-- The view on a world rectangle, filling `fill` of it.
function MV.FrameWorldRect(u0, v0, u1, v1, fill, done)
    if not Ready() then return false end
    return MV.GlideTo((u0 + u1) / 2, (v0 + v1) / 2, MV.RectZoom(u0, v0, u1, v1) * (fill or 0.9), done)
end

-- A map, whole, as the game shows it.
function MV.FrameMap(id, done)
    local l, r, t, b = MW.Rect(id)
    if not l then return false end
    return MV.GlideTo((l + r) / 2, (t + b) / 2, MV.FitZoom(id), done)
end

-- Out to the whole world, remembering the view for Back.
function MV.World()
    if not Ready() then return false end
    MV.Remember("world")
    return MV.GlideTo(0.5, 0.5, 1)
end
MV.Fit = MV.World

---------------------------------------------------------------------------
-- The way back
---------------------------------------------------------------------------
function MV.Remember(tag)
    if not Ready() then return false end
    local u, v, zoom = MV.View()
    back[#back + 1] = { u = u, v = v, zoom = zoom, tag = tag }
    while #back > BACK_LIMIT do table.remove(back, 1) end
    Emit("back")
    return true
end

function MV.CanGoBack() return #back > 0 end
function MV.BackDepth() return #back end
function MV.Peek() return back[#back] end

function MV.Back()
    if not Ready() then return false, "closed" end
    local e = table.remove(back)
    if not e then return false, "none" end
    MV.GlideTo(e.u, e.v, e.zoom)
    Emit("back")
    return true, nil, e
end

function MV.ForgetBack()
    if #back == 0 then return end
    for i = #back, 1, -1 do back[i] = nil end
    Emit("back")
end

-- A jump: remembers the view, then glides to a world point. Returns true.
function MV.GoTo(u, v, zoom, tag, done)
    if not Ready() then return false, "closed" end
    MV.Remember(tag)
    return MV.GlideTo(u, v, zoom, done)
end

-- A map that isn't part of the stitched world (Zephras Isle): shown by the game, never in combat.
function MV.ShowMap(id)
    if not (installed and Shown()) then return false, "closed" end
    if InCombat() then return false, "combat" end
    if Ready() then MV.Remember("map") end
    local ok = pcall(map.SetMapID, map, id)
    return ok, not ok and "failed" or nil
end

local REASONS = {
    combat = "The map can't be changed by TwichUI during combat.",
    failed = "That map can't be shown.",
    closed = "Open your map first.",
}
function MV.Reason(code) return REASONS[code] or "That can't be done right now." end

---------------------------------------------------------------------------
-- Where a click lands: the deepest map under the pointer and the point on it (pins, pings and navigation use this, so a
-- click past the edge of the map underneath is on the map that is drawn there, not clamped to the edge)
---------------------------------------------------------------------------
function MV.ResolveClick(cx, cy)
    local host = MV.MapID()
    if not Ready() then return host, cx, cy end
    local u, v, zoom = MV.CursorWorld()
    local id, x, y = MW.Deepest(u, v)
    local MA = R.MapArt
    local city = MA and MA.CityAt(u, v)
    if city and zoom >= (MV.FitZoom(city) or math.huge) * 0.5 then
        id = city
        x, y = MW.FromWorld(city, u, v)
    end
    if id == MW.WORLD and host ~= MW.WORLD then
        -- on the open sea between maps: the map underneath, if the point is on it
        local hx, hy = MW.FromWorld(host, u, v)
        if hx and hx >= 0 and hx <= 1 and hy >= 0 and hy <= 1 then return host, hx, hy end
    end
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return id, x, y end
    return host, cx, cy
end

---------------------------------------------------------------------------
-- Following the view: which map should be underneath
---------------------------------------------------------------------------
local function Settled()
    local info = sc.mouseButtonInfo and sc.mouseButtonInfo[PRESS]
    if anim or (info and info.down) then return false end
    return (sc.currentScrollX or sc.targetScrollX) == sc.targetScrollX
        and (sc.currentScrollY or sc.targetScrollY) == sc.targetScrollY
        and (sc.currentScale or sc.targetScale) == sc.targetScale
end

-- The map to have underneath for a view: the deepest one under its middle that it is zoomed in far enough for.
function MV.PickMap(u, v, zoom, current)
    local pick = MW.WORLD
    for _, id in ipairs(MW.ChainAt(u, v)) do
        if id ~= MW.WORLD then
            local need = (id == current) and LEAVE or ENTER
            if zoom >= MV.FitZoom(id) * need then pick = id end
        end
    end
    local MA = R.MapArt
    local city = MA and MA.CityAt(u, v)
    if city then
        local need = (city == current) and LEAVE or ENTER
        if zoom >= MV.FitZoom(city) * need then pick = city end
    end
    return pick
end

local function Switch(target)
    local u, v, zoom = MV.View()
    switching = true
    local ok, err = pcall(map.SetMapID, map, target)
    switching = false
    if not ok then
        if R.Fault then R.Fault("map switch", err) end
        return false
    end
    stats.switches = stats.switches + 1
    if active then ShowWorld(u, v, zoom) end
    return true
end

local function WaitForCombat()
    R:Off("PLAYER_REGEN_ENABLED", WaitForCombat)
    Follow()
end

local function FollowStep(_, elapsed)
    if not Ready() then follower:Hide() return end
    if not Settled() then stillFor = 0 return end
    stillFor = stillFor + (elapsed or 0)
    if stillFor < SETTLE then return end
    follower:Hide()
    if InCombat() then
        stats.waits = stats.waits + 1
        R:On("PLAYER_REGEN_ENABLED", WaitForCombat)
        return
    end
    local u, v, zoom = MV.View()
    local current = MV.MapID()
    local target = MV.PickMap(u, v, zoom, current)
    if target ~= current then Switch(target) end
end

-- After the view moved: once it has been still a moment, the map underneath follows it.
Follow = function()
    if not Ready() then return end
    if not follower then
        follower = CreateFrame("Frame")
        follower:Hide()
        follower:SetScript("OnUpdate", FollowStep)
    end
    stillFor = 0
    follower:Show()
end
MV.Follow = Follow
function MV.Following() return follower ~= nil and follower:IsShown() end

---------------------------------------------------------------------------
-- Presses on TwichUI's own buttons on the map: a drag pans the map, a click is the button's
---------------------------------------------------------------------------
function MV.Press(button)
    if not (Ready() and button == PRESS) then return end
    StopAnim()
    stats.pressed = stats.pressed + 1
    sc:OnMouseDown(button)
end

function MV.Release(button)
    if not (Ready() and button == PRESS) then return true end
    local info = sc.mouseButtonInfo and sc.mouseButtonInfo[button]
    if not (info and info.down) then return true end
    local x, y = sc:GetCursorPosition()
    if sc:WouldCursorPositionBeClick(button, x, y) then
        info.down = false       -- the press was the button's: the map's release (and its click handlers) doesn't run
        return true
    end
    stats.dragged = stats.dragged + 1
    sc:OnMouseUp(button)
    return false
end

function MV.WireButton(b)
    b:HookScript("OnMouseDown", function(_, button) MV.Press(button) end)
    b:HookScript("OnMouseUp", function(self, button) self.mvDragged = not MV.Release(button) end)
end

function MV.WasDrag(b)
    local d = b.mvDragged
    b.mvDragged = nil
    return d == true
end

---------------------------------------------------------------------------
-- The map's lifecycle
---------------------------------------------------------------------------
local function Attach()
    local MA = R.MapArt
    local id = MV.MapID()
    local want = installed and id and MW.Stitchable(id) and MA.Build()
    active = (want and MA.Layout(id)) and true or false
    MA.SetShown(active)
    if installed then
        if active then
            sc:SetMouseWheelZoomMode(MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE)
            sc.baseScale = 0                          -- the game pans only past this scale: everywhere, on the world
        elseif savedWheel then
            sc:SetMouseWheelZoomMode(savedWheel)
        end
    end
    Emit("attach")
end

local function RecordView()
    if not Ready() then lastView = nil return end
    local u, v, zoom = MV.View()
    lastView = { map = MV.MapID(), u = u, v = v, zoom = zoom }
end

local function Notified()
    notifier:Hide()
    if not installed then return end
    stats.notified = stats.notified + 1
    local restore = resizeRestore
    resizeRestore = nil
    if restore and Ready() and restore.map == MV.MapID() and not anim then
        stats.resized = stats.resized + 1
        ShowWorld(restore.u, restore.v, restore.zoom)
    end
    RecordView()
    Emit("view")
    Follow()
end

local function Dirty()
    if switching then return end
    if not notifier then
        notifier = CreateFrame("Frame")
        notifier:Hide()
        notifier:SetScript("OnUpdate", Notified)
    end
    notifier:Show()
end
MV.Dirty = Dirty

local function Explored() if R.MapArt then R.MapArt.RefreshExplored() end Dirty() end

local function OnWheel(_, delta)
    if not Ready() then return end
    MV.ZoomBy(delta > 0 and 1 or -1)
end

local function OnPress()
    if installed then StopAnim() end
end

-- Plain clicks on the stitched map: in to the next map down under the pointer, or out to the one above.
local function OnMapClick(_, button)
    if not Ready() or (button ~= "LeftButton" and button ~= "RightButton") then return false end
    stats.clicks = stats.clicks + 1
    local u, v, zoom = MV.CursorWorld()
    local chain = MW.ChainAt(u, v)
    local MA = R.MapArt
    local city = MA and MA.CityAt(u, v)
    if city then chain[#chain + 1] = city end
    if button == "LeftButton" then
        for _, id in ipairs(chain) do
            if id ~= MW.WORLD and (MV.FitZoom(id) or 0) > zoom * 1.05 then
                MV.FrameMap(id)
                return true
            end
        end
        return true   -- (as deep as the maps go: the click does nothing, rather than the game's jump to a map shown whole)
    end
    local target = MW.WORLD
    for _, id in ipairs(chain) do
        if id ~= MW.WORLD and (MV.FitZoom(id) or math.huge) < zoom * 0.95 then target = id end
    end
    MV.FrameMap(target)
    return true
end

-- The scroll limits while the stitched map shows: the view's middle anywhere on the world (the world always covering
-- the view), whatever map is underneath; the game's own on every other map.
local function Extents(self, scale)
    local id = MV.MapID()
    if not (active and installed and id and MW.Stitchable(id)) then return origExtents(self, scale) end
    local W, H = MW.Size()
    local k = K(id)
    local hu = (self:GetWidth() * 0.5 / (scale * k)) / W
    local hv = (self:GetHeight() * 0.5 / (scale * k)) / H
    local u0, u1, v0, v1 = hu, 1 - hu, hv, 1 - hv
    if u0 > u1 then u0, u1 = 0.5, 0.5 end
    if v0 > v1 then v0, v1 = 0.5, 0.5 end
    local l, r, t, b = MW.Rect(id)
    return (u0 - l) / (r - l), (u1 - l) / (r - l), (v0 - t) / (b - t), (v1 - t) / (b - t)
end

local function OnZoomLevels(self)
    if installed and active then self.baseScale = 0 end
end

local function Build()
    if provider then return true end
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer and MapCanvasDataProviderMixin) then return false end
    map, sc = WorldMapFrame, WorldMapFrame.ScrollContainer
    if not (sc.InstantPanAndZoom and sc.CalculateScrollExtentsAtScale and sc.WouldCursorPositionBeClick
        and sc.SetMouseWheelZoomMode and sc.CreateZoomLevels and sc.Child) then
        map, sc = nil, nil
        return false
    end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData() end
    function provider:RefreshAllData() end
    function provider:OnShow()
        Attach()
        if active then
            R:On("MAP_EXPLORATION_UPDATED", Explored)
            if R.MapArt then R.MapArt.RefreshExplored() end
            local id = MV.MapID()
            local l, r, t, b = MW.Rect(id)
            ShowWorld((l + r) / 2, (t + b) / 2, MV.FitZoom(id))   -- the map the game opened on, whole
        end
        Emit("show")
        Dirty()
    end
    function provider:OnHide()
        StopAnim()
        if follower then follower:Hide() end
        R:Off("MAP_EXPLORATION_UPDATED", Explored)
        R:Off("PLAYER_REGEN_ENABLED", WaitForCombat)
        lastView, resizeRestore = nil, nil
        MV.ForgetBack()
        Emit("hide")
    end
    function provider:OnMapChanged()
        StopAnim()
        Attach()
        if not switching then
            lastView = nil
            if Ready() then
                -- a map the game (or you, through its dropdown) put up: shown whole, as the game shows it
                local id = MV.MapID()
                local l, r, t, b = MW.Rect(id)
                ShowWorld((l + r) / 2, (t + b) / 2, MV.FitZoom(id))
            end
        end
        Emit("map")
        Dirty()
    end
    function provider:OnCanvasSizeChanged()
        if lastView and Shown() and lastView.map == MV.MapID() and not switching then resizeRestore = lastView end
        Dirty()
    end
    function provider:OnCanvasScaleChanged()
        if switching then return end
        Emit("scale")
        Dirty()
    end
    function provider:OnCanvasPanChanged() Dirty() end
    return true
end

local function Install()
    origExtents = origExtents or sc.CalculateScrollExtentsAtScale
    sc.CalculateScrollExtentsAtScale = Extents
    WorldMapFrame:AddDataProvider(provider)
    WorldMapFrame:AddCanvasClickHandler(OnMapClick, CLICK_PRIORITY)
    if not hooked then
        -- once; they do nothing while this is off
        sc:HookScript("OnMouseWheel", OnWheel)
        sc:HookScript("OnMouseDown", OnPress)
        hooksecurefunc(sc, "CreateZoomLevels", OnZoomLevels)
        hooked = true
    end
    savedWheel = savedWheel or sc.mouseWheelZoomMode or MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL
    installed = true
    Emit("on")
    if Shown() then provider:OnShow() end
end

local function Uninstall()
    StopAnim()
    if follower then follower:Hide() end
    installed, active = false, false
    lastView, resizeRestore = nil, nil
    MV.ForgetBack()
    R:Off("MAP_EXPLORATION_UPDATED", Explored)
    R:Off("PLAYER_REGEN_ENABLED", WaitForCombat)
    if R.MapArt then R.MapArt.SetShown(false) end
    WorldMapFrame:RemoveCanvasClickHandler(OnMapClick, CLICK_PRIORITY)
    WorldMapFrame:RemoveDataProvider(provider)
    sc.CalculateScrollExtentsAtScale = origExtents
    if savedWheel then sc:SetMouseWheelZoomMode(savedWheel) end
    if Shown() then
        -- the game's own zoom levels, limits and whole-map view again
        sc:CreateZoomLevels()
        sc:CalculateScrollExtents()
        sc:ResetZoom()
    end
    Emit("off")
end

function MV.Refresh()
    if not Build() then return end
    local want = MV.Wanted()
    if want and not installed then Install()
    elseif not want and installed then Uninstall() end
end

MXP.Subscribe(function()
    if not Ready() then return end
    local u, v, zoom = MV.View()
    local most = math.max(MV.MaxZoomAt(u, v), 1)
    if zoom > most * 1.001 then
        StopAnim()
        ShowWorld(u, v, most)
    end
    Dirty()
end)

R:On("PLAYER_LOGIN", MV.Refresh)
R:On("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" or name == "OpenMap" then MV.Refresh() end
end)

-- Read only, for /tui diagnostics and the tests.
function MV.Snapshot()
    local out = { installed = installed, active = active, hooked = hooked, blocker = MV.Blocker(), back = #back,
        animating = anim ~= nil, following = MV.Following(), frames = 0 }
    for _ in pairs(frames) do out.frames = out.frames + 1 end
    for k, v in pairs(stats) do out[k] = v end
    if Ready() then
        local u, v, zoom = MV.View()
        out.zoom, out.max, out.map = zoom, MV.MaxZoomAt(u, v), MV.MapID()
    end
    return out
end
