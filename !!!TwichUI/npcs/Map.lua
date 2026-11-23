-- TwichUI: Vendors and trainers on the world map
-- Small square plaques on the game's world map for the NPCs in your list (npcs/Store.lua), one icon per kind
-- (npcs/Kinds.lua), so they read apart from TwichUI's pins (diamonds) and the map's places (round badges) by shape.
--   Which: the kinds you chose (npcs/Prefs.lua), class trainers for your class only unless you chose every class, and
--     what others sent you only while that is chosen. An NPC of the other side (Alliance or Horde) is never drawn: a
--     character can't deal with it (npcs/Store.lua's Usable; one whose side was never recorded shows for everyone). An NPC of several kinds wears the icon of its first shown kind.
--     What others sent you is drawn dimmed and greyed, and its tooltip says it hasn't been seen by you.
--   Where: on the map an NPC was noted on and on that map's parents down to a zone (never on a continent or the world,
--     where hundreds would cover it), placed through the game's own world-position conversion as pins are
--     (pins/Map.lua's Position, which also places them on map exploration's seamless map). At most MAX_DRAWN at once.
--   Drawing: a map data provider (MapCanvasDataProviderMixin), told when the map, its zoom or its size changes, the list
--     changes or a choice changes. Seamless view changes refresh eligibility without waiting for the native host;
--     newly eligible plaques fade only their opacity for 0.18 seconds. No updater remains once they are visible.
--   Clicks: a click opens the NPC's actions (Show items for sale, for a merchant; Set waypoint, Pin this place, Navigate
--     here, Forget this NPC); nothing is
--     done without one of them being chosen. Alt, Shift and Ctrl clicks are handed to the map's own click handlers, so
--     the pin and ping shortcuts work over a marker as anywhere else. A drag on map exploration's map pans it.
--   Finding one (NMAP.Locate, for the map tools bar's NPC search): the map goes to the NPC's area and its marker is
--     picked out with a brief ring (pins/Pulse.lua's rings, local only: no message, no sound, no waypoint, no route).
--     An NPC the chosen kinds hide is drawn for as long as it is picked out, and only that one; the saved choices
--     are not touched. The pick ends when another is made, when the box is cleared, when the map closes or goes to a
--     map the NPC isn't on, or when the NPC leaves the list. A choice that has to wait for a map waits for the map's own
--     change notice, at most NAV_WAIT seconds, and a newer choice cancels it.
-- TwichUI never opens or closes the world map itself.

local R = TwichUI
local NK, NS, NP = R.NpcKinds, R.NpcStore, R.NpcPrefs
local Perf = R.Perf
local NMAP = {}
R.NpcMap = NMAP

local ZOOM_GROWTH = 1.6          -- how much larger a marker is at the closest zoom than at the widest
local SIZE = 20.7              -- a marker's side on screen before the size choice
local MAX_DRAWN = 300
local MAX_PARENTS = 8
local EDGE = 0.2               -- on the seamless map, markers this far past the map underneath still show
local NAV_WAIT = 2             -- how long a find waits for the map it asked for
local PULSE_LIFE, PULSE_FADE = 2.6, 0.5   -- seconds the ring is out, the last of them fading
local ENTRY_FADE = 0.18

local provider, canvas
local installed = false
local pool, used = {}, 0
local reveal, revealMarker                 -- the entry picked out (shown even if its kind is hidden), and its marker now
local token = 0                            -- bumped by every find and clear: an older wait does nothing
local pending                              -- { token, map, entry }: a find waiting for its map
local pulse                                -- { frame, rings, t, running }: the ring
local presence, fading = {}, {}             -- only currently eligible entries / currently fading frames
local fadeFrame, fadeTick, fadeRunning
local contextMap, hostMap
local candidates, candidateHost, candidateStitched, candidateReveal, candidateRevealListed, candidateFaction
local tracedEligible, tracedFading, tracedHost, tracedContext
local stats = { layouts = 0, drawn = 0, capped = 0, menus = 0, waypoints = 0, forgotten = 0, finds = 0, pulses = 0, stale = 0,
    eligible = 0, entries = 0, departures = 0, placementFailures = 0, viewUpdates = 0, projections = 0 }

local function Enabled() return R:Enabled("npcMap") end
local function MapOpen() return WorldMapFrame and WorldMapFrame:IsShown() end
local function FadingCount() local n = 0 for _ in pairs(fading) do n = n + 1 end return n end
local function TraceVisibility()
    if not R.MapTrace then return end
    local n = FadingCount()
    if tracedEligible ~= stats.eligible or tracedFading ~= n or tracedHost ~= hostMap or tracedContext ~= contextMap then
        tracedEligible, tracedFading, tracedHost, tracedContext = stats.eligible, n, hostMap, contextMap
        R.MapTrace("npc-markers", stats.eligible, n, used, hostMap or false, contextMap or false)
    end
end
local function StopFade()
    if fadeRunning then fadeFrame:SetScript("OnUpdate", nil); fadeFrame:Hide(); fadeRunning = false end
end
local function FadeTick(_, elapsed)
    if not (installed and MapOpen()) then
        for b in pairs(fading) do fading[b] = nil end
        StopFade()
        return
    end
    for b, state in pairs(fading) do
        state.age = math.min(ENTRY_FADE, state.age + math.max(0, elapsed or 0))
        local t = state.age / ENTRY_FADE
        b:SetAlpha(b.targetAlpha * t * t * (3 - 2 * t))
        if state.age >= ENTRY_FADE then fading[b] = nil end
    end
    if not next(fading) then StopFade(); TraceVisibility() end
end
local function StartFade()
    if not next(fading) then StopFade() return end
    if not fadeFrame then
        fadeFrame = CreateFrame("Frame")
        fadeTick = Perf.Wrap("npcs.map.fade", FadeTick)
    end
    if not fadeRunning then
        fadeFrame:SetScript("OnUpdate", fadeTick)
        fadeFrame:Show()
        fadeRunning = true
    end
end
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

-- The kind an entry shows as now, or nil when it is hidden. mine: your side (NS.MyFaction), read here when left out; a
-- pass over the whole list reads it once and hands it in.
local function ShownKind(e, mine)
    if not e.own and not NP.Get("reports") then return nil end
    if mine == nil then mine = NS.MyFaction() end
    if not NS.Usable(e, mine) then return nil end
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
NMAP.Relevant = Relevant   -- Guild Locations' markers (guildloc/Map.lua) are placed on the same maps by the same rule

---------------------------------------------------------------------------
-- The markers
---------------------------------------------------------------------------
local Tooltip, Click

-- The optional backdrop (ui.npcMap.backdrop) behind a marker, here and on the minimap (npcs/Minimap.lua): "shadow" is a
-- dark copy of the icon's own shape, "plate" a dark square. One texture per marker, made the first time one is wanted.
local PLATE = "Interface\\Buttons\\WHITE8x8"
function NMAP.Backdrop(b, icon)
    local mode = NP.Get("backdrop")
    if mode == "none" then
        if b.back then b.back:Hide() end
        b.backKey = nil
        return
    end
    local key = mode .. "|" .. tostring(icon)
    if b.backKey == key then return end
    b.backKey = key
    if not b.back then b.back = b:CreateTexture(nil, "BACKGROUND") end
    local t = b.back
    t:ClearAllPoints()
    if mode == "shadow" then
        t:SetTexture(icon)
        t:SetVertexColor(0, 0, 0, 0.85)
        t:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
        t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
    else
        t:SetTexture(PLATE)
        t:SetVertexColor(0, 0, 0, 0.6)
        t:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
        t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    end
    t:Show()
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
    NMAP.Backdrop(b, kind.icon)
    local reported = not e.own
    local alpha = reported and NP.Get("reportAlpha") / 100 or 1
    if b.reported ~= reported or b.targetAlpha ~= alpha then
        b.reported, b.targetAlpha = reported, alpha
        b.icon:SetDesaturated(alpha < 1)   -- at full opacity a report looks like any other NPC
    end
    if b.name ~= e.n then
        b.name = e.n
        b.label:SetText(e.n)   -- plain text: the store cleaned it
    end
    local labels = NP.Get("labels")
    if b.labels ~= labels then b.labels = labels; b.label:SetShown(labels) end
    local size = SIZE * NP.Get("iconSize") / 100
    if b.size ~= size then b.size = size; b:SetSize(size, size) end
    b.entry = e
end

local function Finite(value)
    if issecretvalue and issecretvalue(value) then return false end
    local VM = R.MapViewMath
    if VM and VM.Finite then return VM.Finite(value) end
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function OptionalNumber(value, default)
    if issecretvalue and issecretvalue(value) then return nil end
    if value == nil then return default end
    return Finite(value) and value or nil
end

-- The stitched camera keeps a constant screen-space size across native host handoffs. Outside it, retain the native
-- map's original zoom growth. Invalid geometry never reaches a frame setter or reveals a stale pooled anchor.
local function Place(b)
    local scale = WorldMapFrame:GetCanvasScale()
    if not Finite(scale) or scale <= 0 then return false end
    local global
    if WorldMapFrame.GetGlobalPinScale then global = WorldMapFrame:GetGlobalPinScale() end
    global = OptionalNumber(global, 1)
    if not Finite(global) or global <= 0 then return false end
    local MV, MW = R.MapView, R.MapWorld
    local stitched = MV and MV.Ready and MV.Ready() and MW and MW.Stitchable and MW.Stitchable(WorldMapFrame:GetMapID())
    local growth = 1
    if not stitched then
        local zoom
        if WorldMapFrame.GetCanvasZoomPercent then zoom = WorldMapFrame:GetCanvasZoomPercent() end
        zoom = OptionalNumber(zoom, 0)
        if not Finite(zoom) then return false end
        growth = 1 + (ZOOM_GROWTH - 1) * math.min(1, math.max(0, zoom))
    end
    local s = global / scale * growth
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not Finite(w) or not Finite(h) or w <= 0 or h <= 0 or not Finite(s) or s <= 0
        or not Finite(b.mx) or not Finite(b.my) then return false end
    local px, py = w * b.mx / s, -h * b.my / s
    if not Finite(px) or not Finite(py) then return false end
    if b.placedScale ~= s or b.placedX ~= b.mx or b.placedY ~= b.my or b.placedW ~= w or b.placedH ~= h then
        b.placedScale, b.placedX, b.placedY, b.placedW, b.placedH = s, b.mx, b.my, w, h
        b:SetScale(s)
        b:ClearAllPoints()
        b:SetPoint("CENTER", canvas, "TOPLEFT", px, py)
    end
    return true
end

local function HideFrom(n)
    for i = n, #pool do
        local b = pool[i]
        if b:IsShown() then b:Hide() end
        fading[b] = nil
        b.entry = nil
    end
    if not next(fading) then StopFade() end
end

local function FrameLevel()
    local ok, level = pcall(function()
        return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    end)
    -- under TwichUI's pins (drawn at that level), over the map's own art
    return ((ok and type(level) == "number") and level or (canvas:GetFrameLevel() + 500)) - 2
end

---------------------------------------------------------------------------
-- The ring on a find
---------------------------------------------------------------------------
local function StopPulse()
    if not pulse then return end
    pulse.running = false
    pulse.frame:SetScript("OnUpdate", nil)
    pulse.frame:Hide()
    pulse.frame:SetAlpha(1)
    R.MapPulse.Hide(pulse.rings)
end

local function PulseTick(_, elapsed)
    if not pulse.running then return end
    if elapsed > 0.1 then elapsed = 0.1 end
    pulse.t = pulse.t + elapsed
    if pulse.t >= PULSE_LIFE then StopPulse() return end
    if pulse.t > PULSE_LIFE - PULSE_FADE then pulse.frame:SetAlpha((PULSE_LIFE - pulse.t) / PULSE_FADE) end
    Perf.Call("npcs.map.pulse", R.MapPulse.Step, pulse.rings, pulse.t, PULSE_LIFE - PULSE_FADE, pulse.reduced, true)
end

-- Puts the ring over the picked-out marker (again, after a layout or a zoom). Returns whether it could.
local function PlacePulse()
    local PM = R.PinsMap
    if not (pulse and pulse.running and revealMarker and revealMarker.entry == reveal and PM and PM.PlaceAt) then return false end
    if not PM.PlaceAt(pulse.frame, revealMarker.mx, revealMarker.my) then return false end
    pulse.frame:SetFrameLevel((PM.FrameLevel and PM.FrameLevel("PIN_FRAME_LEVEL_QUEST_PING")) or (canvas:GetFrameLevel() + 510))
    return true
end

-- Starts the ring on the picked-out marker, if it is on the map being viewed. Returns whether it is showing.
local function StartPulse()
    local PU = R.MapPulse
    if not (PU and reveal and revealMarker and revealMarker.entry == reveal) then return false end
    if not pulse then
        local f = CreateFrame("Frame", nil, canvas)
        f:SetSize(PU.TO, PU.TO)
        f:EnableMouse(false)
        f:Hide()
        f.rings = PU.AddRings(f, 2)
        pulse = { frame = f, rings = f.rings }
    end
    StopPulse()
    pulse.running, pulse.t = true, 0
    -- the ring's own preference for stillness, since it is the ping's ring (no other feature's is read)
    local PG = R.PinsLook and R.PinsLook.Ping
    pulse.reduced = PG and PG.Get("reducedMotion") and true or false
    if not PlacePulse() then pulse.running = false return false end
    pulse.frame:Show()
    R.MapPulse.Step(pulse.rings, 0, PULSE_LIFE - PULSE_FADE, pulse.reduced, true)
    pulse.frame:SetScript("OnUpdate", PulseTick)
    stats.pulses = stats.pulses + 1
    return true
end

-- Whether an entry is still in the list (the same table: an update changes it in place, a deletion drops it).
local function Listed(e)
    for _, x in ipairs(NS.Entries()) do
        if rawequal(x, e) then return true end
    end
    return false
end

-- The native host intentionally follows only after the camera settles. Eligibility belongs to the camera now;
-- coordinates still belong to that real host's canvas, so its eventual switch cannot reveal stale pooled anchors.
local function ViewContext(viewed)
    local MV, MW = R.MapView, R.MapWorld
    local stitched = MV and MV.Ready and MV.Ready() and MW and MW.Stitchable and MW.Stitchable(viewed)
    hostMap = viewed
    if stitched and MV.View and MV.PickMap and MV.ViewRect and MW.FromWorld then
        local u, v, zoom = MV.View()
        contextMap = MV.PickMap(u, v, zoom, contextMap or viewed)
        local u0, v0, u1, v1 = MV.ViewRect()
        local x0, y0 = MW.FromWorld(viewed, u0, v0)
        local x1, y1 = MW.FromWorld(viewed, u1, v1)
        if x0 and x1 and x1 > x0 and y1 > y0 then
            local padx, pady = (x1 - x0) * 0.05, (y1 - y0) * 0.05
            return NS.ValidMap(contextMap), true, x0 - padx, y0 - pady, x1 + padx, y1 + pady
        end
        return false, true, 0, 0, 0, 0
    end
    contextMap = viewed
    local low, high = stitched and -EDGE or 0, stitched and 1 + EDGE or 1
    return viewed and NS.ValidMap(viewed), stitched, low, low, high, high
end

local function InvalidateCandidates()
    candidateHost = nil
end

-- Map geometry and chosen kinds do not change as the camera moves. Resolve them only when their owning data changes;
-- the bounded camera pass then culls cached host coordinates. No cached coordinate survives a host or mode change.
local function Candidates(viewed, stitched)
    local mine = NS.MyFaction()
    if candidates and candidateHost == viewed and candidateStitched == stitched and candidateReveal == reveal
        and candidateFaction == mine then
        return candidates, candidateRevealListed
    end
    local list, n = candidates or {}, 0
    local relevant, listed = Relevant(viewed), false
    local at = {}
    for _, e in ipairs(NS.Entries()) do
        local picked = reveal ~= nil and rawequal(e, reveal)
        if picked then listed = true end
        if relevant(e.m) then
            local kind = ShownKind(e, mine) or (picked and NK.Primary(e.tags) or nil)
            if kind then
                at.map, at.x, at.y = e.m, e.x, e.y
                local mx, my = R.PinsMap.Position(at, viewed)
                if Finite(mx) and Finite(my) then
                    n = n + 1
                    local row = list[n] or {}
                    row.entry, row.kind, row.mx, row.my = e, kind, mx, my
                    list[n] = row
                end
            end
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    candidates, candidateHost, candidateStitched, candidateReveal, candidateRevealListed = list, viewed, stitched, reveal, listed
    candidateFaction = mine
    stats.projections = stats.projections + 1
    return list, listed
end

-- Everything on the map now. Runs only for provider/list/preference or coalesced seamless-view changes.
function NMAP.Layout()
    if not (installed and MapOpen()) then return end
    local pt = Perf.on and Perf.Start("npcs.map.layout")
    stats.layouts = stats.layouts + 1
    used = 0
    revealMarker = nil
    local scanned, revealListed = false, false
    local viewed = WorldMapFrame:GetMapID()
    local PM = R.PinsMap
    local eligible, stitched, x0, y0, x1, y1 = ViewContext(viewed)
    for b in pairs(fading) do fading[b] = nil end
    if viewed and eligible and PM and PM.Position then
        local level = FrameLevel()
        local capped = false
        scanned = true
        local rows
        rows, revealListed = Candidates(viewed, stitched)
        local revealProcessed = reveal == nil
        for _, row in ipairs(rows) do
            local e = row.entry
            local picked = reveal ~= nil and rawequal(e, reveal)
            if picked then revealProcessed = true end
            if picked or not capped then
                local kind, mx, my = row.kind, row.mx, row.my
                if mx and mx >= x0 and mx <= x1 and my >= y0 and my <= y1 then
                    if used >= MAX_DRAWN and not picked then
                        stats.capped = stats.capped + 1
                        capped = true
                    else
                        used = used + 1
                        local b = pool[used]
                        if not b then
                            b = NewMarker()
                            pool[used] = b
                        end
                        b.mx, b.my = mx, my
                        if b.level ~= level then b.level = level; b:SetFrameLevel(level) end
                        Dress(b, e, kind)
                        if Place(b) then
                            local state = presence[e]
                            if not state then
                                state = { age = stitched and 0 or ENTRY_FADE }
                                presence[e] = state
                                stats.entries = stats.entries + 1
                            end
                            state.seen = stats.layouts
                            local t = state.age / ENTRY_FADE
                            b:SetAlpha(b.targetAlpha * t * t * (3 - 2 * t))
                            if state.age < ENTRY_FADE then fading[b] = state end
                            b:Show()
                            if picked then revealMarker = b end
                        else
                            stats.placementFailures = stats.placementFailures + 1
                            b:Hide(); b.entry = nil
                            used = used - 1
                        end
                    end
                end
            end
            if capped and revealProcessed then break end
        end
    end
    HideFrom(used + 1)
    stats.drawn = used
    for e, state in pairs(presence) do
        if state.seen ~= stats.layouts then presence[e] = nil; stats.departures = stats.departures + 1 end
    end
    stats.eligible = used
    StartFade()
    TraceVisibility()
    if reveal and not (scanned and revealListed or (not scanned and Listed(reveal))) then
        NMAP.ClearReveal(true)   -- it left the list
    end
    if pulse and pulse.running and not PlacePulse() then StopPulse() end
    if pt then Perf.Stop(pt) end
end

local function Rescale()
    if not (installed and MapOpen()) then return end
    for i = 1, used do
        local b = pool[i]
        if not Place(b) then
            b:Hide()
            fading[b] = nil
            stats.placementFailures = stats.placementFailures + 1
        end
    end
    PlacePulse()
end

---------------------------------------------------------------------------
-- Finding one: the map goes to it and its marker is picked out
---------------------------------------------------------------------------
-- Lets go of the picked-out NPC: its ring stops, a marker only the pick was drawing goes, a find still waiting for its map
-- is cancelled. skipDraw: the caller draws the map next.
function NMAP.ClearReveal(skipDraw)
    token = token + 1
    pending = nil
    StopPulse()
    if not reveal then return false end
    reveal, revealMarker = nil, nil
    if not skipDraw and installed and MapOpen() then NMAP.Layout() end
    return true
end

-- Picks out an entry of the list on the map: the map goes to the NPC's area and a ring shows on its marker. Local only:
-- no message, no sound, no waypoint, no route, and the chosen kinds are not changed. Asked again at this moment, because
-- the entry may have been removed since it was listed. Returns true, or false and why: "closed" (the feature is off or
-- the map isn't open), "gone" (it is no longer in the list) or "map" (the game wouldn't show that map).
function NMAP.Locate(e)
    if not (installed and MapOpen()) then return false, "closed" end
    if type(e) ~= "table" or not Listed(e) then
        stats.stale = stats.stale + 1
        return false, "gone"
    end
    NMAP.ClearReveal(true)               -- replaces any earlier pick, and its wait
    local mine = token
    reveal = e
    stats.finds = stats.finds + 1
    if WorldMapFrame:GetMapID() == e.m then
        NMAP.Layout()
        StartPulse()
        return true
    end
    pending = { token = mine, map = e.m, entry = e }
    -- once: the map announces itself (OnMapChanged) and the ring follows; nothing here tries again
    local ok = pcall(WorldMapFrame.SetMapID, WorldMapFrame, e.m)
    if not ok then
        if token == mine then reveal, pending = nil, nil end
        Notice("That map couldn't be opened.")
        return false, "map"
    end
    if pending and pending.token == mine then
        C_Timer.After(NAV_WAIT, function()
            if token == mine and pending and pending.token == mine then
                NMAP.ClearReveal()
                Notice("That map didn't open.")
            end
        end)
    end
    return true
end

function NMAP.Revealed() return reveal end

-- The map being viewed changed. A find waiting for this map gets it (once the map has finished laying itself out); one
-- waiting for another is dropped. With nothing waiting, a pick on a map that no longer holds the NPC ends.
local function MapChanged()
    local p = pending
    if p then
        pending = nil
        if WorldMapFrame:GetMapID() == p.map then
            C_Timer.After(0, function()
                if token ~= p.token or reveal ~= p.entry then stats.stale = stats.stale + 1 return end
                NMAP.Layout()
                StartPulse()
            end)
        else
            NMAP.ClearReveal(true)
        end
        return
    end
    if reveal then
        local viewed = WorldMapFrame:GetMapID()
        if viewed ~= reveal.m and not (viewed and NS.ValidMap(viewed) and Relevant(viewed)(reveal.m)) then
            NMAP.ClearReveal(true)
        end
    end
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

NMAP.Tooltip = Tooltip   -- the minimap's markers (npcs/Minimap.lua) say the same

-- The game's waypoint at the NPC, only when asked; it replaces the waypoint you had, as setting one in the game does.
-- WaypointUI's public API names it for the NPC and takes coordinates in percent. If unavailable or unsuccessful,
-- fall back to the game's own waypoint, which has no name. Suppress its audio so this click still sounds only once.
function NMAP.SetWaypoint(e)
    local x, y = e.x / NS.COORD, e.y / NS.COORD
    local ok, set = pcall(function()
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(e.m) then error("no") end
        local api = type(WaypointUIAPI) == "table" and type(WaypointUIAPI.Navigation) == "table" and WaypointUIAPI.Navigation or nil
        if api and type(api.NewUserNavigation) == "function" then
            local named, nav = pcall(api.NewUserNavigation, {
                name = e.n, mapID = e.m, x = x * 100, y = y * 100, suppressAudio = true,
            })
            if named and nav then return true end
        end
        return C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.m, x, y))
    end)
    if not ok or not set then Notice("The game doesn't allow a waypoint on this map.") return false end
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
    local choices = {}
    local ST = R.NpcStock
    if ST and ST.IsMerchant(e) then
        choices[#choices + 1] = { label = "Show items for sale", enabled = ST.HasStock(e),
            why = "No stock has been noted for this merchant yet. It is noted when you open its window, or when someone sends it.",
            tip = "Lists what this merchant was seen to sell, with each item's own tooltip. Nothing is bought.",
            run = function() ST.Show(e) end }
    end
    choices[#choices + 1] = { label = "Set waypoint", tip = "Sets the game's waypoint at this NPC. It replaces the waypoint you had.",
        run = function() NMAP.SetWaypoint(e) end }
    local PE = R.PinsEditor
    choices[#choices + 1] = { label = "Pin this place", enabled = R:Enabled("partyPins") and PE ~= nil,
        why = "Party pins is turned off.",
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
    function provider:RemoveAllData()
        HideFrom(1); used = 0; stats.drawn, stats.eligible = 0, 0
        for e in pairs(presence) do presence[e] = nil end
        candidates, candidateHost = nil, nil
        TraceVisibility()
    end
    function provider:RefreshAllData() InvalidateCandidates(); NMAP.Layout() end
    function provider:OnMapChanged() InvalidateCandidates(); MapChanged(); NMAP.Layout() end
    function provider:OnCanvasSizeChanged() NMAP.Layout() end
    function provider:OnHide() NMAP.ClearReveal(true); self:RemoveAllData() end
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
        NMAP.ClearReveal(true)
        WorldMapFrame:RemoveDataProvider(provider)   -- hides every marker (RemoveAllData)
        installed = false
    end
end

NS.OnChange(function() InvalidateCandidates(); if installed and MapOpen() then NMAP.Layout() end end)
NP.Subscribe(function() InvalidateCandidates(); if installed and MapOpen() then NMAP.Layout() end end)
if R.MapView and R.MapView.Subscribe then
    R.MapView.Subscribe(function(event)
        if event == "view" or event == "attach" then
            if event == "attach" then InvalidateCandidates() end
            if installed and MapOpen() then stats.viewUpdates = stats.viewUpdates + 1; NMAP.Layout() end
        elseif event == "hide" then
            if provider then provider:RemoveAllData() end
        elseif event == "off" then
            if installed and MapOpen() then NMAP.Layout() end
        end
    end)
end
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
        layouts = stats.layouts, pool = #pool, menus = stats.menus, waypoints = stats.waypoints, forgotten = stats.forgotten,
        finds = stats.finds, pulses = stats.pulses, stale = stats.stale, picked = reveal ~= nil, waiting = pending ~= nil,
        ringing = pulse ~= nil and pulse.running == true, fading = FadingCount(), eligible = stats.eligible,
        entries = stats.entries, departures = stats.departures, placementFailures = stats.placementFailures,
        viewUpdates = stats.viewUpdates, contextMap = contextMap or false, hostMap = hostMap or false,
        fadeDurationSeconds = ENTRY_FADE, candidates = candidates and #candidates or 0, projections = stats.projections }
end
function NMAP.Marker(i) return pool[i] end
function NMAP.Used() return used end
