-- TwichUI: Guild Locations on the world map (docs/guild-locations.md)
-- A class badge on the game's world map for each guildmate who is sharing a position and whose message guildloc/Comm.lua has
-- accepted. Only what Comm holds in memory is drawn: nothing here is saved, sent or relayed, and nothing is asked of the guild.
--   Which: live, unexpired records (GL.Live), never the local player and never a guildmate in your party or raid (the game
--     draws group members itself; the record stays held and is not touched). At most MAX_DRAWN per viewed map, in the
--     order Comm lists them (first held first, then name), so the same records win every time. Records not drawn are still
--     held: drawing never decides what is kept.
--   Where: the map the position was sent on and the maps it is inside, up to the viewed one, and on map exploration's
--     seamless map, through the same rule and the same world-position conversion as the NPC markers and the pins
--     (npcs/Map.lua Relevant, pins/Map.lua Position).
--   Look: the class badge from media/guildloc/ (class token from the guild roster, never from a message); an unknown or
--     missing class wears the TwichUI emblem. Class and level are unknown until the roster says.
--   Drawing: a map data provider, told when the map, its size or its zoom changes (and, on every opening, to refresh). Nothing runs per frame and nothing runs while
--     the map is hidden (a change then is remembered and drawn when the map is next shown). A change to the records is drawn
--     within COALESCE seconds, one pass at most that often. A marker is bound to a record by key, so a redraw moves it
--     instead of swapping it; markers are pooled and every one is reset when it is let go.
--   Clicks: the marker's menu (Set waypoint, Navigate to this spot, Invite to party). Each asks again at the moment of the
--     click: the record must still be held and fresh and the roster must still list the member; nothing is automatic.
--     Alt, Shift and Ctrl clicks go to the map's own handlers, as over the NPC markers.
-- The position is the last one received. It says nothing about shared phase or layer.
-- TwichUI never opens or closes the world map itself.

local R = TwichUI
local GL = R.GuildLoc
local RS = GL.Roster
local SH = R.Share
local PN = R.Pins
local Perf = R.Perf
local GM = {}
GL.Map = GM

local SIZE = 20                -- a marker's side on screen at the map's widest view (the 32 px badge, near 1:1)
local ZOOM_GROWTH = 1.3        -- 26 at the closest zoom
local MAX_DRAWN = 150
local COALESCE = 0.5           -- seconds between layouts caused by record changes
local EDGE = 0.2               -- on the seamless map, markers this far past the map underneath still show

-- the nine badges that exist; any other class token wears the emblem
local ART = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true,
    WARLOCK = true, DRUID = true }
GM.MAX_DRAWN = MAX_DRAWN

local provider, canvas
local installed = false
local pool = {}                 -- every marker made; one with no `key` is free
local byKey = {}                -- [record key] = the marker drawing it now
local used = 0
local lastLayout
local dirty = false             -- the records or the roster changed while the map was hidden
local layoutT
local stats = { layouts = 0, skipped = 0, capped = 0, menus = 0, waypoints = 0, navs = 0, invites = 0, stale = 0 }

local function Enabled() return GL.State() ~= "off" end
local function MapOpen() return WorldMapFrame and WorldMapFrame:IsShown() end
local function Notice(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

---------------------------------------------------------------------------
-- Who is not drawn
---------------------------------------------------------------------------
local selfKey
local function SelfKey()
    local full = SH.FullName(SH.SelfName())
    selfKey = full and full:lower() or nil
    return selfKey
end

-- The lower-case keys of everyone in your party or raid. Read when a layout runs and when an action is chosen.
local function GroupSet()
    local set = {}
    if not (IsInGroup and IsInGroup()) then return set end
    local raid = IsInRaid and IsInRaid()
    local prefix, n = raid and "raid" or "party", raid and 40 or 4
    for i = 1, n do
        local unit = prefix .. i
        if not UnitExists or UnitExists(unit) then
            local name = GetUnitName and GetUnitName(unit, true)
            if type(name) == "string" and not Secret(name) then
                local full = SH.FullName(name)
                if full then set[full:lower()] = true end
            end
        end
    end
    return set
end

---------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------
local Tooltip, Click

local function LabelShown(b)
    local PL = R.PinsLook
    if PL and PL.Pref and PL.Pref("labels") == "always" then return true end
    return b.over == true
end

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
    b:SetScript("OnEnter", function(self)
        self.over = true
        self.label:SetShown(LabelShown(self))
        Tooltip(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.over = false
        self.label:SetShown(LabelShown(self))
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self, button) Click(self, button) end)
    if R.MapView then R.MapView.WireButton(b) end
    return b
end

local function TooltipOwnedBy(b)
    return GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == b
end

-- Lets a marker go: hidden, unbound, and everything a record gave it forgotten, so a reused one starts clean.
local function Release(b)
    if TooltipOwnedBy(b) then GameTooltip:Hide() end
    if b:IsShown() then b:Hide() end
    b.key, b.mx, b.my, b.art, b.name, b.over = nil, nil, nil, nil, nil, false
    b.icon:SetTexture(nil)
    b.hl:SetTexture(nil)
    b.label:SetText("")
    b.label:SetShown(false)
end

local function ReleaseAll()
    for i = 1, #pool do
        if pool[i].key then Release(pool[i]) end
    end
    byKey = {}
    used = 0
end

local function ArtFor(entry)
    local token = entry and entry.class
    return R.PATH .. (ART[token] and ([[media\guildloc\class-]] .. token .. "-small") or [[media\icon]])
end
GM.ArtFor = ArtFor

local function Dress(b, w)
    local rec = w.rec
    local art = ArtFor(RS.Entry(rec.key))
    if b.art ~= art then
        b.art = art
        b.icon:SetTexture(art)
        b.hl:SetTexture(art)
    end
    local name = SH.Short(rec.name)
    if b.name ~= name then
        b.name = name
        b.label:SetText(name)
    end
    b.key, b.mx, b.my = rec.key, w.mx, w.my
    b.label:SetShown(LabelShown(b))
    b:SetSize(SIZE, SIZE)
end

-- Puts a marker's middle at a place on the viewed map (0..1). The same size at the map's widest view, growing to ZOOM_GROWTH
-- times that at the closest zoom (the map's own zoom percent, 0 to 1, as Blizzard's pins use).
local function Place(b)
    local scale = WorldMapFrame:GetCanvasScale()
    if not scale or scale <= 0 then return false end
    local global = WorldMapFrame.GetGlobalPinScale and WorldMapFrame:GetGlobalPinScale() or 1
    local zoom = WorldMapFrame.GetCanvasZoomPercent and WorldMapFrame:GetCanvasZoomPercent() or 0
    local s = global / scale * (1 + (ZOOM_GROWTH - 1) * math.min(1, math.max(0, zoom)))
    b:SetScale(s)
    b:ClearAllPoints()
    b:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * b.mx / s, -canvas:GetHeight() * b.my / s)
    return true
end

local function FrameLevel()
    local ok, level = pcall(function()
        return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    end)
    -- over the NPC plaques (two below that level), under TwichUI's pins (at it)
    return ((ok and type(level) == "number") and level or (canvas:GetFrameLevel() + 500)) - 1
end

---------------------------------------------------------------------------
-- Everything on the map now
---------------------------------------------------------------------------
-- Runs when the map, the records or the roster change, never per frame and never while the map is hidden.
function GM.Layout()
    if not installed then return end
    if not MapOpen() then
        dirty = true
        stats.skipped = stats.skipped + 1
        return
    end
    local pt = Perf.on and Perf.Start("guildloc.map.layout")
    dirty = false
    lastLayout = GetTime()
    layoutT.Cancel()
    stats.layouts = stats.layouts + 1
    local want = {}
    local viewed = WorldMapFrame:GetMapID()
    local PM = R.PinsMap
    local NMAP = R.NpcMap
    if viewed and PM and PM.Position then
        local list = GL.Live()
        if #list > 0 then
            local relevant, stitched
            if NMAP and NMAP.Relevant then relevant, stitched = NMAP.Relevant(viewed) end
            local low, high = stitched and -EDGE or 0, stitched and 1 + EDGE or 1
            local group, me = GroupSet(), SelfKey()
            local at = {}   -- one place handed to Position (it reads map, x, y)
            for _, rec in ipairs(list) do
                if rec.key ~= me and not group[rec.key] and (not relevant or relevant(rec.map)) then
                    at.map, at.x, at.y = rec.map, rec.x, rec.y
                    local mx, my = PM.Position(at, viewed)
                    if mx and mx >= low and mx <= high and my >= low and my <= high then
                        if #want >= MAX_DRAWN then
                            stats.capped = stats.capped + 1
                            break
                        end
                        want[#want + 1] = { rec = rec, mx = mx, my = my }
                    end
                end
            end
        end
    end
    -- a record keeps its marker; the rest are let go, then fill from the free ones
    local keep = {}
    for _, w in ipairs(want) do
        local b = byKey[w.rec.key]
        if b then w.b = b; keep[w.rec.key] = b end
    end
    for key, b in pairs(byKey) do
        if not keep[key] then Release(b) end
    end
    local level = want[1] and FrameLevel() or nil
    local scan = 1
    for _, w in ipairs(want) do
        local b = w.b
        if not b then
            while pool[scan] and pool[scan].key do scan = scan + 1 end
            b = pool[scan]
            if not b then
                b = NewMarker()
                pool[#pool + 1] = b
            end
            w.b = b
            -- claimed now, so the scan does not hand it out twice
            b.key = w.rec.key
        end
        keep[w.rec.key] = b
        b:SetFrameLevel(level)
        Dress(b, w)
        Place(b)
        b:Show()
        if b.over then Tooltip(b) end   -- a tooltip being read is the record as it is now
    end
    byKey = keep
    used = #want
    if pt then Perf.Stop(pt) end
end

local function Rescale()
    if not (installed and MapOpen()) then return end
    for _, b in pairs(byKey) do Place(b) end
end

-- Asks for a layout. deferred: a change to the records (never inside the caller; one pass per COALESCE); otherwise a
-- change of map, which draws at once unless a pass ran less than COALESCE ago.
function GM.Request(deferred)
    if not installed then return end
    if not MapOpen() then dirty = true return end
    if layoutT.Armed() then return end
    local wait = lastLayout and (COALESCE - (GetTime() - lastLayout)) or 0
    if deferred then
        layoutT.Set(math.max(wait, 0.05))
    elseif wait <= 0 then
        GM.Layout()
    else
        layoutT.Set(wait)
    end
end

---------------------------------------------------------------------------
-- What a marker says
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

-- "Updated 12 s ago", "Updated 3 min ago": from the receiver's own clock, never from the sender.
function GM.Ago(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return ("Updated %d s ago"):format(seconds) end
    return ("Updated %d min ago"):format(math.floor(seconds / 60))
end

-- "Level 60 Mage", "Mage", "Level 60", or nil when the roster has said neither.
function GM.Identity(entry)
    local level = entry and entry.level
    local class = entry and entry.class and ClassName(entry.class)
    if level and class then return ("Level %d %s"):format(level, class) end
    if class then return class end
    if level then return ("Level %d"):format(level) end
    return nil
end

function Tooltip(b)
    local rec = b.key and GL.Fresh(b.key)
    if not rec then
        if TooltipOwnedBy(b) then GameTooltip:Hide() end
        return
    end
    local entry = RS.Entry(rec.key)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT", -4, -4)
    GameTooltip:SetText(SH.Short(rec.name), 1, 1, 1, 1, true)
    local who = GM.Identity(entry)
    if who then GameTooltip:AddLine(who, SOFT[1], SOFT[2], SOFT[3]) else GameTooltip:AddLine("Class and level not known", DIM[1], DIM[2], DIM[3]) end
    GameTooltip:AddLine(GM.Ago(GetTime() - rec.at), GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:AddLine("Last known location. Their phase or layer may differ.", DIM[1], DIM[2], DIM[3], true)
    GameTooltip:AddLine("Click for actions", 0.45, 0.43, 0.38)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- What a marker does. Every action asks again when chosen.
---------------------------------------------------------------------------
-- The record and roster entry as they are now, or nil and a sentence. The menu may have been open for a while: the member may
-- have withdrawn, expired, left the guild or changed guild since.
local function Current(key)
    local rec = GL.Fresh(key)
    local entry = RS.Entry(key)
    if not (rec and entry) then
        stats.stale = stats.stale + 1
        GM.Request(true)
        return nil, "That guildmate's location is no longer shared."
    end
    return rec, nil, entry
end

local function InviteWhy(key, entry)
    if not (C_PartyInfo and C_PartyInfo.InviteUnit) then return "The game's party invitation isn't available." end
    if C_PartyInfo.CanInvite and not C_PartyInfo.CanInvite() then return "You can't invite to a party right now." end
    if entry and entry.online == false then return "They are offline." end
    if GroupSet()[key] then return "They are already in your group." end
    return nil
end

function GM.SetWaypoint(key)
    local rec, why = Current(key)
    if not rec then Notice(why) return false end
    local ok = pcall(function()
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(rec.map) then error("no") end
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(rec.map, rec.x / PN.COORD, rec.y / PN.COORD))
    end)
    if not ok then Notice("The game doesn't allow a waypoint on this map.") return false end
    stats.waypoints = stats.waypoints + 1
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK) end
    return true
end

-- A route to the spot as last received (a fixed destination: it does not follow them).
function GM.Navigate(key)
    local rec, why = Current(key)
    if not rec then Notice(why) return false end
    if not (R.Nav and R.Nav.Enabled()) then Notice("Navigation is turned off.") return false end
    local ok, reason = R.Nav.StartAt(rec.map, rec.x / PN.COORD, rec.y / PN.COORD, SH.Short(rec.name), "guild")
    if not ok then
        if reason then Notice(reason) end
        return false
    end
    stats.navs = stats.navs + 1
    return true
end

function GM.Invite(key)
    local rec, why, entry = Current(key)
    if not rec then Notice(why) return false end
    local bad = InviteWhy(key, entry)
    if bad then Notice(bad) return false end
    local ok = pcall(C_PartyInfo.InviteUnit, rec.name)
    if not ok then Notice("The game wouldn't send that invitation.") return false end
    stats.invites = stats.invites + 1
    return true
end

function GM.Menu(b)
    local OpenMenu = R.PinsWindow and R.PinsWindow.OpenMenu
    local key = b.key
    local rec = key and GL.Fresh(key)
    if not (OpenMenu and rec) then
        if key then Notice("That guildmate's location is no longer shared.") GM.Request(true) end
        return false
    end
    stats.menus = stats.menus + 1
    local entry = RS.Entry(key)
    local choices = {
        { label = "Set waypoint", tip = "Sets the game's waypoint at the spot they were last seen. It replaces the waypoint you had.",
            run = function() GM.SetWaypoint(key) end },
    }
    local navOk, navWhy = true, nil
    if R.Nav and R.Nav.CanNavigate then navOk, navWhy = R.Nav.CanNavigate(rec.map, rec.x / PN.COORD, rec.y / PN.COORD) end
    choices[#choices + 1] = { label = "Navigate to this spot", enabled = navOk and R.Nav ~= nil, why = navWhy,
        tip = "Plans a route to where they were last seen (Navigation). It does not follow them, and replaces any destination you had.",
        run = function() GM.Navigate(key) end }
    local inviteWhy = InviteWhy(key, entry)
    choices[#choices + 1] = { label = "Invite to party", enabled = inviteWhy == nil, why = inviteWhy,
        tip = "Sends the game's party invitation to them.", run = function() GM.Invite(key) end }
    OpenMenu(b, SH.Short(rec.name), choices)
    return true
end

function Click(b, button)
    if not b.key then return end
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
    GM.Menu(b)
end

---------------------------------------------------------------------------
-- On the map or off it
---------------------------------------------------------------------------
layoutT = GL.NewTimer(function() GM.Layout() end)

local groupOn = false
local function OnGroup() GM.Request(true) end

local function Build()
    if provider or not WorldMapFrame or not MapCanvasDataProviderMixin then return provider ~= nil end
    canvas = WorldMapFrame:GetCanvas()
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData() ReleaseAll() end
    function provider:RefreshAllData() GM.Request(false) end
    function provider:OnMapChanged() ReleaseAll(); GM.Request(false) end   -- the old places mean nothing on the new map
    function provider:OnCanvasSizeChanged() GM.Request(false) end
    function provider:OnHide() layoutT.Cancel(); ReleaseAll(); dirty = true end   -- no work for a closed map
    function provider:OnCanvasScaleChanged() Rescale() end
    return true
end

-- Makes the map agree with the choice: off (or held) takes the provider and its event off; otherwise it is on.
function GM.Refresh()
    if not WorldMapFrame or not Build() then return end
    local want = Enabled()
    if want and not installed then
        WorldMapFrame:AddDataProvider(provider)
        installed = true
        R:On("GROUP_ROSTER_UPDATE", OnGroup)
        groupOn = true
        GM.Request(false)
    elseif not want and installed then
        layoutT.Cancel()
        WorldMapFrame:RemoveDataProvider(provider)   -- releases every marker (RemoveAllData)
        installed = false
        R:Off("GROUP_ROSTER_UPDATE", OnGroup)
        groupOn = false
        dirty = false
    end
end

GL.OnRecords(function() GM.Request(true) end)
RS.OnRefresh(function() GM.Request(true) end)   -- class and level come from the roster
GL.OnChange(function(kind) if kind == "state" then GM.Refresh() end end)
if R.PinsLook and R.PinsLook.OnPrefChange then
    R.PinsLook.OnPrefChange(function()
        for _, b in ipairs(pool) do
            if R.PinsLook.MapText then R.PinsLook.MapText.Apply(b.label, 140) end
            if b.key then b.label:SetShown(LabelShown(b)) end
        end
    end)
end

-- The world map is loaded when it is first needed (or with the game).
R:On("PLAYER_LOGIN", GM.Refresh)
R:On("ADDON_LOADED", function(name) if name == "Blizzard_WorldMap" then GM.Refresh() end end)

-- Read only, for /tui diagnostics and the tests.
function GM.Snapshot()
    return { installed = installed, open = MapOpen() and true or false, drawn = used, pool = #pool, layouts = stats.layouts,
        skipped = stats.skipped, capped = stats.capped, menus = stats.menus, waypoints = stats.waypoints, navs = stats.navs,
        invites = stats.invites, stale = stats.stale, dirty = dirty, timers = layoutT.Engines(), armed = layoutT.Armed() and 1 or 0,
        events = groupOn and 1 or 0 }
end
function GM.Marker(i) return pool[i] end
function GM.Used() return used end
