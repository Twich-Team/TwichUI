-- TwichUI: Vendors and trainers on the world map
-- Small square plaques on the game's world map for the NPCs in your list (npcs/Store.lua), one icon per kind
-- (npcs/Kinds.lua), so they read apart from TwichUI's pins (diamonds) and the map's places (round badges) by shape.
--   Which: the kinds you chose (npcs/Prefs.lua), class trainers for your class only unless you chose every class, and
--     what others sent you only while that is chosen. An NPC of several kinds wears the icon of its first shown kind.
--     What others sent you is drawn dimmed and greyed, and its tooltip says it hasn't been seen by you.
--   Where: on the map an NPC was noted on and on that map's parents down to a zone (never on a continent or the world,
--     where hundreds would cover it), placed through the game's own world-position conversion as pins are
--     (pins/Map.lua's Position, which also places them on map exploration's seamless map). At most MAX_DRAWN at once.
--   Drawing: a map data provider (MapCanvasDataProviderMixin), told when the map, its zoom or its size changes, the list
--     changes or a choice changes. Nothing runs per frame.
--   Clicks: a click opens the NPC's actions (Set waypoint, Pin this place, Navigate here, Forget this NPC); nothing is
--     done without one of them being chosen. Alt, Shift and Ctrl clicks are handed to the map's own click handlers, so
--     the pin and ping shortcuts work over a marker as anywhere else. A drag on map exploration's map pans it.
-- TwichUI never opens or closes the world map itself.

local R = TwichUI
local NK, NS, NP = R.NpcKinds, R.NpcStore, R.NpcPrefs
local NMAP = {}
R.NpcMap = NMAP

local SIZE = 18                -- a marker's side on screen before the size choice
local MAX_DRAWN = 300
local MAX_PARENTS = 8
local REPORT_ALPHA = 0.6
local EDGE = 0.2               -- on the seamless map, markers this far past the map underneath still show

local provider, canvas
local installed = false
local pool, used = {}, 0
local stats = { layouts = 0, drawn = 0, capped = 0, menus = 0, waypoints = 0, forgotten = 0 }

local function Enabled() return R:Enabled("npcMap") end
local function MapOpen() return WorldMapFrame and WorldMapFrame:IsShown() end
local function Notice(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end

---------------------------------------------------------------------------
-- Which NPCs show, and with which icon
---------------------------------------------------------------------------
local myClass
local function MyClass()
    if not myClass and UnitClassBase then
        local c = UnitClassBase("player")
        if type(c) == "string" and not (issecretvalue and issecretvalue(c)) then myClass = c end
    end
    return myClass
end

-- The kind an entry shows as now, or nil when it is hidden.
local function ShownKind(e)
    if not e.own and not NP.Get("reports") then return nil end
    local all = NP.Get("trainerClass") == "all"
    return NK.Primary(e.tags, function(kind)
        if not NP.Shown(kind) then return false end
        if kind == "classTrainer" and not all then return e.cls ~= nil and e.cls[MyClass() or ""] == true end
        return true
    end)
end
NMAP.ShownKind = ShownKind

-- Whether a map's NPCs belong on the viewed map: the same map, or a map inside it (the viewed one is a zone or smaller,
-- NS.ValidMap); on the seamless map, any map it stitches.
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

local function Relevant(viewed)
    local MV, MW = R.MapView, R.MapWorld
    local stitched = MV and MV.Ready and MV.Ready() and MW and MW.Stitchable and MW.Stitchable(viewed)
    local memo = {}
    return function(map)
        local r = memo[map]
        if r == nil then
            if map == viewed then r = true
            elseif stitched then r = MW.Stitchable(map) and true or false
            else r = IsAncestor(viewed, map) end
            memo[map] = r
        end
        return r
    end, stitched
end

---------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------
local Tooltip, Click

local function NewMarker()
    local b = CreateFrame("Button", nil, canvas)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetBlendMode("ADD")
    b.hl:SetAlpha(0.3)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, 1)
    b.label:SetWordWrap(false)
    b.label:SetJustifyH("CENTER")
    if R.PinsLook and R.PinsLook.MapText then R.PinsLook.MapText.Apply(b.label, 140) end
    b:SetScript("OnEnter", function(self) Tooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, button) Click(self, button) end)
    if R.MapView then R.MapView.WireButton(b) end
    return b
end

local function Dress(b, e, kind)
    if b.kind ~= kind then
        b.kind = kind
        b.icon:SetTexture(kind.icon)
        b.hl:SetTexture(kind.icon)
    end
    local reported = not e.own
    if b.reported ~= reported then
        b.reported = reported
        b.icon:SetDesaturated(reported)
        b:SetAlpha(reported and REPORT_ALPHA or 1)
    end
    if b.name ~= e.n then
        b.name = e.n
        b.label:SetText(e.n)   -- plain text: the store cleaned it
    end
    b.label:SetShown(NP.Get("labels"))
    local size = SIZE * NP.Get("iconSize") / 100
    b:SetSize(size, size)
    b.entry = e
end

-- Puts a frame's middle at a place on the viewed map (0..1), the same size on screen at every zoom (as pins are).
local function Place(b)
    local scale = WorldMapFrame:GetCanvasScale()
    if not scale or scale <= 0 then return false end
    local global = WorldMapFrame.GetGlobalPinScale and WorldMapFrame:GetGlobalPinScale() or 1
    local s = global / scale
    b:SetScale(s)
    b:ClearAllPoints()
    b:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * b.mx / s, -canvas:GetHeight() * b.my / s)
    return true
end

local function HideFrom(n)
    for i = n, #pool do
        local b = pool[i]
        if b:IsShown() then b:Hide() end
        b.entry = nil
    end
end

local function FrameLevel()
    local ok, level = pcall(function()
        return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    end)
    -- under TwichUI's pins (drawn at that level), over the map's own art
    return ((ok and type(level) == "number") and level or (canvas:GetFrameLevel() + 500)) - 2
end

-- Everything on the map now. Runs when the map, the list or the choices change; never per frame.
function NMAP.Layout()
    if not (installed and MapOpen()) then return end
    stats.layouts = stats.layouts + 1
    used = 0
    local viewed = WorldMapFrame:GetMapID()
    local PM = R.PinsMap
    if viewed and NS.ValidMap(viewed) and PM and PM.Position then
        local relevant, stitched = Relevant(viewed)
        local level = FrameLevel()
        local low, high = stitched and -EDGE or 0, stitched and 1 + EDGE or 1
        local at = {}   -- one place handed to Position (it reads map, x, y)
        for _, e in ipairs(NS.Entries()) do
            if relevant(e.m) then
                local kind = ShownKind(e)
                if kind then
                    at.map, at.x, at.y = e.m, e.x, e.y
                    local mx, my = PM.Position(at, viewed)
                    if mx and mx >= low and mx <= high and my >= low and my <= high then
                        if used >= MAX_DRAWN then
                            stats.capped = stats.capped + 1
                            break
                        end
                        used = used + 1
                        local b = pool[used]
                        if not b then
                            b = NewMarker()
                            pool[used] = b
                        end
                        b.mx, b.my = mx, my
                        b:SetFrameLevel(level)
                        Dress(b, e, kind)
                        Place(b)
                        b:Show()
                    end
                end
            end
        end
    end
    HideFrom(used + 1)
    stats.drawn = used
end

local function Rescale()
    if not (installed and MapOpen()) then return end
    for i = 1, used do Place(pool[i]) end
end

---------------------------------------------------------------------------
-- What a marker says and does
---------------------------------------------------------------------------
local DIM = { 0.62, 0.58, 0.51 }
local SOFT = { 0.78, 0.74, 0.66 }
local GOLD = { 0.86, 0.69, 0.30 }

local CLASS_NAME = {}
local function ClassName(token)
    if CLASS_NAME[token] == nil then
        local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]
        CLASS_NAME[token] = type(name) == "string" and name or (token:sub(1, 1) .. token:sub(2):lower())
    end
    return CLASS_NAME[token]
end

-- "Class trainer (Mage, Priest)", "Profession trainer (Alchemy)", or the kind's own word.
function NMAP.KindLines(e)
    local lines = {}
    local list = {}
    for id in pairs(e.tags) do
        if NK.BY_ID[id] then list[#list + 1] = NK.BY_ID[id] end
    end
    table.sort(list, function(a, b) return a.rank < b.rank end)
    for _, k in ipairs(list) do
        local text = k.noun
        if k.id == "classTrainer" and e.cls then
            local names = {}
            for token in pairs(e.cls) do names[#names + 1] = ClassName(token) end
            table.sort(names)
            text = ("%s (%s)"):format(text, table.concat(names, ", "))
        elseif k.id == "profTrainer" and e.prof then
            text = ("%s (%s)"):format(text, e.prof)
        end
        lines[#lines + 1] = text
    end
    return lines
end

local function When(at)
    if type(at) ~= "number" or not date then return nil end
    return date("%d %b %Y", at)
end

function NMAP.Provenance(e)
    if e.own then
        local text = (e.seen or 1) > 1 and ("Seen by you, %d visits"):format(e.seen) or "Seen by you"
        local when = When(e.at)
        if when then text = text .. ", last on " .. when end
        if (e.rep or 0) > 0 then text = text .. (" (also reported by others %d %s)"):format(e.rep, e.rep == 1 and "time" or "times") end
        return text
    end
    return ("Reported by other players (%d %s); not seen by you yet"):format(e.rep or 1, (e.rep or 1) == 1 and "report" or "reports")
end

function Tooltip(b)
    local e = b.entry
    if not e then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT", -4, -4)
    GameTooltip:SetText(e.n, 1, 1, 1, 1, true)
    if e.t then GameTooltip:AddLine(e.t, GOLD[1], GOLD[2], GOLD[3], true) end
    for _, line in ipairs(NMAP.KindLines(e)) do GameTooltip:AddLine("\226\128\162 " .. line, SOFT[1], SOFT[2], SOFT[3]) end
    GameTooltip:AddLine(NMAP.Provenance(e), e.own and GOLD[1] or DIM[1], e.own and GOLD[2] or DIM[2], e.own and GOLD[3] or DIM[3], true)
    if R.Pins then GameTooltip:AddLine(R.Pins.Describe({ map = e.m, x = e.x, y = e.y }), DIM[1], DIM[2], DIM[3]) end
    GameTooltip:AddLine("Click for actions", 0.45, 0.43, 0.38)
    GameTooltip:Show()
end

-- The game's waypoint at the NPC, only when asked; it replaces the waypoint you had, as setting one in the game does.
function NMAP.SetWaypoint(e)
    local x, y = e.x / NS.COORD, e.y / NS.COORD
    local ok = pcall(function()
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(e.m) then error("no") end
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.m, x, y))
    end)
    if not ok then Notice("The game doesn't allow a waypoint on this map.") return false end
    stats.waypoints = stats.waypoints + 1
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK) end
    return true
end

function NMAP.ConfirmForget(e)
    local what = e.own and "This removes it from your list. It is noted again the next time you deal with it."
        or "This removes what others sent you about it. It comes back if someone sends it again."
    R.Interact.Confirm("TWICHUI_NPC_FORGET", ("Forget %s?\n\n%s Nothing else in your list changes."):format(e.n, what), function()
        if NS.Forget(e) then stats.forgotten = stats.forgotten + 1 end
    end, { accept = "Forget", valid = function()
        for _, x in ipairs(NS.Entries()) do if rawequal(x, e) then return true end end
        return false, "It's no longer in your list."
    end })
end

function NMAP.Menu(e, anchor)
    local OpenMenu = R.PinsWindow and R.PinsWindow.OpenMenu
    if not OpenMenu then return false end
    stats.menus = stats.menus + 1
    local choices = {
        { label = "Set waypoint", tip = "Sets the game's waypoint at this NPC. It replaces the waypoint you had.",
            run = function() NMAP.SetWaypoint(e) end },
    }
    local PE = R.PinsEditor
    choices[#choices + 1] = { label = "Pin this place", enabled = R:Enabled("partyPins") and PE ~= nil,
        why = "Party Map is turned off.",
        tip = "Opens the new pin window here, named for the NPC. Nothing is made until you save it.",
        run = function() PE.OpenNew(e.m, e.x, e.y, false, e.n) end }
    if R.Nav and R.Nav.Enabled() then
        choices[#choices + 1] = { label = "Navigate here",
            tip = "Plans a route to this NPC and guides you along it (Navigation). It replaces any destination you had.",
            run = function()
                local ok, why = R.Nav.StartAt(e.m, e.x / NS.COORD, e.y / NS.COORD, e.n, "map")
                if not ok and why then Notice(why) end
            end }
    end
    choices[#choices + 1] = { label = "Forget this NPC", danger = true,
        tip = "Removes it from your list (asks first).", run = function() NMAP.ConfirmForget(e) end }
    OpenMenu(anchor, e.n, choices)
    return true
end

function Click(b, button)
    local e = b.entry
    if not e then return end
    if R.MapView and R.MapView.WasDrag(b) then return end
    GameTooltip:Hide()
    if (IsAltKeyDown and IsAltKeyDown()) or (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then
        -- a shortcut click: the map's own handlers at the pointer (pins, pings, the waypoint), as on the bare map
        pcall(function()
            local sc = WorldMapFrame.ScrollContainer
            WorldMapFrame:ProcessCanvasClickHandlers(button, sc:NormalizeUIPosition(sc:GetCursorPosition()))
        end)
        return
    end
    NMAP.Menu(e, b)
end

---------------------------------------------------------------------------
-- On the map or off it
---------------------------------------------------------------------------
local function Build()
    if provider or not WorldMapFrame or not MapCanvasDataProviderMixin then return provider ~= nil end
    canvas = WorldMapFrame:GetCanvas()
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData() HideFrom(1); used = 0 end
    function provider:RefreshAllData() NMAP.Layout() end
    function provider:OnMapChanged() NMAP.Layout() end
    function provider:OnCanvasSizeChanged() NMAP.Layout() end
    function provider:OnCanvasScaleChanged() Rescale() end
    return true
end

function NMAP.Refresh()
    if not WorldMapFrame or not Build() then return end
    local want = Enabled()
    if want and not installed then
        WorldMapFrame:AddDataProvider(provider)
        installed = true
        NMAP.Layout()
    elseif not want and installed then
        WorldMapFrame:RemoveDataProvider(provider)   -- hides every marker (RemoveAllData)
        installed = false
    end
end

NS.OnChange(function() if installed and MapOpen() then NMAP.Layout() end end)
NP.Subscribe(function() if installed and MapOpen() then NMAP.Layout() end end)
if R.PinsLook and R.PinsLook.OnPrefChange then
    R.PinsLook.OnPrefChange(function()
        for _, b in ipairs(pool) do if R.PinsLook.MapText then R.PinsLook.MapText.Apply(b.label, 140) end end
    end)
end

-- The world map is loaded when it is first needed (or with the game).
R:On("PLAYER_LOGIN", NMAP.Refresh)
R:On("ADDON_LOADED", function(name) if name == "Blizzard_WorldMap" then NMAP.Refresh() end end)

-- Read only, for /tui diagnostics and the tests.
function NMAP.Snapshot()
    return { installed = installed, open = MapOpen() and true or false, drawn = stats.drawn, capped = stats.capped,
        layouts = stats.layouts, pool = #pool, menus = stats.menus, waypoints = stats.waypoints, forgotten = stats.forgotten }
end
function NMAP.Marker(i) return pool[i] end
function NMAP.Used() return used end
