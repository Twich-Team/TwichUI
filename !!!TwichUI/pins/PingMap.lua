-- TwichUI: Map pings on the world map
-- Draws pings (pins/Ping.lua keeps and checks them), lists the recent ones at the top right of the map, sends a
-- ping from a map click, and replays one from the list.
--   Gesture: Ctrl-Alt-click on the map (or Ctrl-Alt-right-click, or Ping the map then one plain click). It is a
--     canvas click handler like the pin clicks (pins/Map.lua), at a priority above WaypointUI's own Ctrl-click
--     handler (100), and it takes only the exact keys chosen: every other click carries on to the map. The place
--     is the map's own normalized cursor position on the map being viewed, never the screen or your zone. Only
--     that click sends anything; browsing, dragging and the pointer's movement never do.
--   Drawing: each ping is a small frame on the map's canvas (a bevelled marker, the sender's name on a dark plate
--     and, unless reduced motion is on, two soft rings that expand and fade), placed as pins are (PM.PlaceAt) and
--     drawn again when the map, its zoom or its size changes. On the ping's own map, or on a parent of it through
--     the game's world-position conversion (as pins are). On any other map nothing is drawn: the list has it.
--     Frames are reused (at most MAX_EFFECTS), a new ping from the same sender takes that sender's frame, and
--     they have no mouse. The one OnUpdate runs only while a ping is showing.
--   The list: at the top right of the map, beside the game's own buttons, only while there is something to list
--     and the map is open. A click opens that entry's map (once, asked of the map the player is on) and replays
--     the ping there; a manual map change meanwhile, a newer click, the map closing or the feature going off
--     cancels it. A replay shows the ping and plays the sound the policy allows; it adds no entry and sends nothing.
--   Receiving never opens or moves the map.
-- Nothing here is saved.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local PG = PL.Ping
local PM = R.PinsMap
local MP = R.MapPing
local SH = R.Share
local S = R.ChronicleStyle
local V = {}
R.MapPingView = V

local CLICK_PRIORITY = 105       -- above WaypointUI's Ctrl-click handler (100) and the pin clicks (95); exact keys only
local MAX_EFFECTS = 6
local MAX_ROWS = 8               -- PG.LIMITS.listSize[2]
local ARM_SECONDS = 60
local TEST_SECONDS = 30
local NAV_WAIT = 2               -- how long a click waits for the map it asked for
local AGE_STEP = 5               -- the list's ages are redrawn this often while it is showing
local NOTICE_GAP = 3             -- the same sentence is not shown again this soon

local RING_TEXTURE = [[Interface\minimap\UI-Minimap-Ping-Expand]]   -- the game's own, as MapPinPingTemplate uses it
local MARK, RING_FROM, RING_TO = 18, 26, 104
local RING_TIME, RING_STAGGER, POP, FADE = 1.2, 0.4, 0.25, 0.5

local pal = PL.palette
local installed = false
local provider
local pool, active = {}, {}                     -- effect frames; the ones showing
local driver
local panel, rows = nil, {}
local pad = 8
local styleDirty = false                        -- the look (or the scale it is drawn at) changed: draw the border again
local armed = 0
local token = 0                                 -- bumped by every click, cancel and teardown: older callbacks do nothing
local pending                                   -- { token, id, map, snapshot }: a click waiting for its map
local testUntil = 0
local hintShown = false
local ageGen = 0
local lastSay, lastSayAt
local stats = { shown = 0, replays = 0, navigations = 0, stale = 0, expired = 0, clicks = 0, refused = 0 }

local function MapOpen() return WorldMapFrame and WorldMapFrame:IsShown() end
local function Now() return GetTime() end
local function Clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function Say(text)
    local now = Now()
    if text == lastSay and lastSayAt and now >= lastSayAt and now - lastSayAt < NOTICE_GAP then return end
    lastSay, lastSayAt = text, now
    PM.Notice(text)
end

---------------------------------------------------------------------------
-- The rings and the marker
---------------------------------------------------------------------------
local function NewEffect()
    local canvas = PM.Canvas()
    local f = CreateFrame("Frame", nil, canvas)
    f:SetSize(RING_TO, RING_TO)
    f:EnableMouse(false)
    f:Hide()
    f.rings = {}
    for i = 1, 2 do
        -- a dark ring under a bright one, so the ring reads on a pale map and on a dark one
        local dark = f:CreateTexture(nil, "ARTWORK", nil, 0)
        dark:SetTexture(RING_TEXTURE)
        dark:SetVertexColor(0.05, 0.03, 0.02, 1)
        dark:SetPoint("CENTER")
        local ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
        ring:SetTexture(RING_TEXTURE)
        ring:SetVertexColor(0.96, 0.80, 0.38, 1)
        ring:SetPoint("CENTER")
        f.rings[i] = { dark = dark, ring = ring }
    end
    f.markDark = f:CreateTexture(nil, "ARTWORK", nil, 2)
    f.markDark:SetTexture(PL.PIN_TEXTURE)
    f.markDark:SetVertexColor(0.04, 0.03, 0.02, 1)
    f.markDark:SetPoint("CENTER")
    f.mark = f:CreateTexture(nil, "ARTWORK", nil, 3)
    f.mark:SetTexture(PL.PIN_TEXTURE)
    f.mark:SetVertexColor(1, 0.96, 0.82, 1)
    f.mark:SetPoint("CENTER")
    f.plate = f:CreateTexture(nil, "ARTWORK", nil, 4)
    f.plate:SetColorTexture(0.05, 0.04, 0.03, 0.8)
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    f.label:SetWordWrap(false)
    f.label:SetJustifyH("CENTER")
    f.label:SetPoint("TOP", f, "CENTER", 0, -(MARK / 2 + 6))
    f.plate:SetPoint("TOPLEFT", f.label, "TOPLEFT", -5, 2)
    f.plate:SetPoint("BOTTOMRIGHT", f.label, "BOTTOMRIGHT", 5, -2)
    PL.MapText.Apply(f.label)   -- the player's choice of font for names on the map
    return f
end

local function SizeLabel(f, name)
    f.label:SetText(name)
    local w = f.label:GetStringWidth()
    f.label:SetWidth(Clamp((w or 60) + 2, 24, 200))
end

-- One step of a ping's life. Returns true once it is over.
local function Step(e, dt)
    local f = e.frame
    e.t = e.t + dt
    local t, life = e.t, e.life
    if t >= life then return true end
    local alpha = 1
    local size = MARK
    if not e.reduced and t < POP then
        local k = t / POP
        alpha = k
        size = MARK * (k < 0.6 and (0.5 + 0.65 * k / 0.6) or (1.15 - 0.15 * (k - 0.6) / 0.4))
    end
    if t > life - FADE then alpha = math.min(alpha, (life - t) / FADE) end
    f:SetAlpha(alpha)
    f.mark:SetSize(size, size)
    f.markDark:SetSize(size + 5, size + 5)
    local ringsEnd = life - FADE
    for i, r in ipairs(f.rings) do
        local rt = t - (i - 1) * RING_STAGGER
        if e.reduced or rt < 0 or t > ringsEnd then
            if r.shown then r.ring:Hide(); r.dark:Hide(); r.shown = false end
        else
            local phase = (rt % RING_TIME) / RING_TIME
            local grow = 1 - (1 - phase) * (1 - phase)
            local d = RING_FROM + (RING_TO - RING_FROM) * grow
            local a = (1 - phase) ^ 1.4
            r.ring:SetSize(d, d); r.ring:SetAlpha(a * 0.95)
            r.dark:SetSize(d + 6, d + 6); r.dark:SetAlpha(a * 0.7)
            if not r.shown then r.ring:Show(); r.dark:Show(); r.shown = true end
        end
    end
    return false
end

local function Retire(e)
    e.frame:Hide()
    e.frame:SetAlpha(1)
    e.running = false
end

local function Compact()
    local keep = 0
    for i = 1, #active do
        local e = active[i]
        if e.running then keep = keep + 1; active[keep] = e end
    end
    for i = keep + 1, #active do active[i] = nil end
end

local function Tick(_, elapsed)
    if elapsed > 0.1 then elapsed = 0.1 end
    for i = 1, #active do
        local e = active[i]
        if e.running then
            local ok, finished = pcall(Step, e, elapsed)
            if not ok then
                Retire(e)
                if R.Fault then R.Fault("map ping", finished) end
            elseif finished then
                Retire(e)
            end
        end
    end
    Compact()
    if #active == 0 and driver then driver:SetScript("OnUpdate", nil) end
end

local function Run()
    driver = driver or CreateFrame("Frame")
    if not driver:GetScript("OnUpdate") then driver:SetScript("OnUpdate", Tick) end
end

-- Stops every ping showing (keepKey: not that one, the Test ping when the group went away).
local function StopAll(keepKey)
    for i = 1, #active do
        if active[i].key ~= keepKey then Retire(active[i]) end
    end
    Compact()
    if #active == 0 and driver and driver:GetScript("OnUpdate") then driver:SetScript("OnUpdate", nil) end
end

-- Where the ping is on the map being viewed: its own map, or one it is inside, else nil.
local function Where(info, viewed)
    if not viewed then return nil end
    return PM.Position({ map = info.map, x = info.x, y = info.y }, viewed)
end

local function Place(e, viewed)
    local mx, my = Where(e.info, viewed)
    if mx and PM.PlaceAt(e.frame, mx, my) then
        if not e.frame:IsShown() then e.frame:Show() end
        return true
    end
    e.frame:Hide()
    return false
end

-- Starts a ping on the map being viewed. info: { map, x, y (whole steps), name, key }. Returns whether it is
-- showing (false, with a reason: the ping is on a map this one doesn't hold).
function V.ShowPing(info)
    if not (installed and MapOpen()) then return false, "closed" end
    local viewed = WorldMapFrame:GetMapID()
    if not Where(info, viewed) then return false, "elsewhere" end
    -- the frame: this sender's, else a free one, else the one that has been showing longest
    local e
    for _, a in ipairs(active) do if a.running and a.key == info.key then e = a break end end
    if not e then
        for _, a in ipairs(pool) do if not a.running then e = a break end end
    end
    if not e and #pool < MAX_EFFECTS then
        e = { frame = NewEffect() }
        pool[#pool + 1] = e
    end
    if not e then
        for _, a in ipairs(active) do if a.running and (not e or a.t > e.t) then e = a end end
    end
    local already = e.running
    e.key, e.info, e.t = info.key, info, 0
    e.life = PG.Get("seconds")
    e.reduced = PG.Get("reducedMotion")
    e.running = true
    for _, r in ipairs(e.frame.rings) do r.ring:Hide(); r.dark:Hide(); r.shown = false end
    SizeLabel(e.frame, info.name)
    e.frame:SetFrameLevel(PM.FrameLevel("PIN_FRAME_LEVEL_QUEST_PING") or 1)
    Place(e, viewed)
    if not already then active[#active + 1] = e end
    Step(e, 0)
    Run()
    stats.shown = stats.shown + 1
    return true
end

-- The map, its zoom or its size changed: where each showing ping is.
local function Relayout()
    if #active == 0 then return end
    local viewed = MapOpen() and WorldMapFrame:GetMapID() or nil
    for _, e in ipairs(active) do
        if e.running then Place(e, viewed) end
    end
end

---------------------------------------------------------------------------
-- Replaying and navigating
---------------------------------------------------------------------------
local function Replay(snapshot)
    if not (installed and MapOpen()) then return end
    if V.ShowPing(snapshot) then
        stats.replays = stats.replays + 1
        MP.Sound("replay")
    end
end

local function Cancel()
    token = token + 1
    pending = nil
end

-- A click on a recent entry. Asked again at this moment: the entry may have expired, the feature gone off.
function V.Activate(e)
    if not (installed and MP.Active() and MapOpen()) then return false end
    stats.clicks = stats.clicks + 1
    if not MP.Alive(e) then
        stats.expired = stats.expired + 1
        Say("That ping has expired.")
        V.RefreshList()
        return false
    end
    if not MP.TakeReplay() then return false end   -- rapid clicks: the first one counts
    Cancel()
    local mine = token
    local snapshot = { map = e.map, x = e.x, y = e.y, name = e.name, key = e.key }
    if WorldMapFrame:GetMapID() == e.map then
        Replay(snapshot)
        return true
    end
    pending = { token = mine, map = e.map, snapshot = snapshot }
    stats.navigations = stats.navigations + 1
    -- once: the map announces itself (OnMapChanged) and the replay follows; nothing here tries again
    local ok = pcall(WorldMapFrame.SetMapID, WorldMapFrame, e.map)
    if not ok then
        pending = nil
        Say("That map couldn't be opened.")
        return false
    end
    if pending and pending.token == mine then
        C_Timer.After(NAV_WAIT, function()
            if token == mine and pending and pending.token == mine then
                pending = nil
                Say("That map didn't open.")
            end
        end)
    end
    return true
end

-- The map being viewed changed. A click waiting for a map gets it, or is dropped if the player went elsewhere.
local function MapChanged()
    local p = pending
    if p then
        pending = nil
        if WorldMapFrame:GetMapID() == p.map then
            local mine = p.token
            C_Timer.After(0, function()   -- after the map has finished laying itself out
                if token ~= mine then stats.stale = stats.stale + 1 return end
                Replay(p.snapshot)
            end)
        else
            token = token + 1
            stats.stale = stats.stale + 1
        end
    end
    Relayout()
    V.RefreshList()
end

---------------------------------------------------------------------------
-- The recent list
---------------------------------------------------------------------------
local WIDTH_BASE = 196

local function TextSize() return PL.Get("textSize") end
local function RowHeight() return math.ceil(TextSize() * 1.25 + (TextSize() - 2) * 1.25) + 10 end
local function HeadHeight() return math.ceil((TextSize() - 2) * 1.25) + 8 end
local function PanelWidth()
    local base = math.floor(WIDTH_BASE * TextSize() / PL.DEFAULTS.textSize + 0.5)
    local container = WorldMapFrame and WorldMapFrame:GetCanvasContainer()
    local room = container and container:GetWidth() or 0
    if room > 0 then base = math.min(base, math.max(150, math.floor(room * 0.45))) end   -- a small map is not covered
    return base
end

local function AgeText(seconds)
    if seconds < 5 then return "now" end
    if seconds < 60 then return ("%ds"):format(seconds) end
    return ("%dm"):format(math.floor(seconds / 60))
end

local function ShowTip(row)
    local e = row.entry
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:SetText(e.name, 1, 1, 1, 1, true)
    GameTooltip:AddLine(("%s (%.1f, %.1f)"):format(PN.MapName(e.map), e.x / PN.COORD * 100, e.y / PN.COORD * 100), 0.78, 0.74, 0.66)
    if row.here then
        GameTooltip:AddLine("On this map. Click to show it again.", 0.86, 0.69, 0.30)
    else
        GameTooltip:AddLine("On another map. Click to open that map and show it there.", 0.86, 0.69, 0.30)
    end
    GameTooltip:Show()
end

local function NewRow(i)
    local row = CreateFrame("Button", nil, panel)
    row:RegisterForClicks("LeftButtonUp")
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetWidth(3)
    row.bar:SetPoint("TOPLEFT", 0, -1)
    row.bar:SetPoint("BOTTOMLEFT", 0, 1)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 0.95, 0.8, 0.10)
    row.name = PL.Text(row, "GameFontHighlight", "name")
    row.age = PL.Text(row, "GameFontNormalSmall", "meta")
    row.age:SetJustifyH("RIGHT")
    row.where = PL.Text(row, "GameFontNormalSmall", "meta")
    row.action = PL.Text(row, "GameFontNormalSmall", "meta")
    row.action:SetJustifyH("RIGHT")
    for _, fs in ipairs({ row.name, row.where }) do fs:SetWordWrap(false) end
    row:SetScript("OnEnter", ShowTip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        if self.entry then V.Activate(self.entry) end
    end)
    rows[i] = row
    return row
end

local function Anchor(row, i, rowH)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", pad + 2, -(pad + HeadHeight() + (i - 1) * rowH))
    row:SetPoint("RIGHT", panel, "RIGHT", -(pad + 2), 0)
    row:SetHeight(rowH)
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -3)
    row.age:ClearAllPoints()
    row.age:SetPoint("TOPRIGHT", row, "TOPRIGHT", -3, -3)
    row.name:SetPoint("RIGHT", row.age, "LEFT", -6, 0)
    row.action:ClearAllPoints()
    row.action:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
    row.where:ClearAllPoints()
    row.where:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3)
    row.where:SetPoint("RIGHT", row.action, "LEFT", -6, 0)
end

local function Restyle()
    if not panel then return end
    pad = math.max(5, math.ceil(PL.Surface(PL.MenuLook, panel)))
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", pad + 6, -pad - 1)
    Paint(panel.title, pal.gold)
    Paint(panel.count, pal.stone)
    panel.count:ClearAllPoints()
    panel.count:SetPoint("LEFT", panel.title, "RIGHT", 6, 0)
end

local function BuildPanel()
    if panel then return end
    panel = CreateFrame("Frame", "TwichUIMapPings", WorldMapFrame, "BackdropTemplate")
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)       -- clicks on the list are not clicks on the map
    panel:Hide()
    panel.title = PL.Text(panel, "GameFontNormalSmall", "meta")
    panel.title:SetText("Map pings")
    panel.count = PL.Text(panel, "GameFontNormalSmall", "meta")
    -- a title with a hint, not a button: it says how to ping
    panel.head = CreateFrame("Frame", nil, panel)
    panel.head:EnableMouse(true)
    panel.head:SetPoint("TOPLEFT", panel.title, "TOPLEFT", -2, 2)
    panel.head:SetPoint("BOTTOMRIGHT", panel.count, "BOTTOMRIGHT", 2, -2)
    panel.head:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Map pings", 1, 1, 1)
        GameTooltip:AddLine("Pings from your group, newest first. Click one to open its map and show it again.", 0.78, 0.74, 0.66, true)
        GameTooltip:AddLine(PG.HowTo(), 0.86, 0.69, 0.30, true)
        GameTooltip:Show()
    end)
    panel.head:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Restyle()
end

local function ScheduleAges()
    ageGen = ageGen + 1
    local mine = ageGen
    local function Again()
        if mine ~= ageGen or not (panel and panel:IsShown()) then return end
        V.RefreshList()
        C_Timer.After(AGE_STEP, Again)
    end
    C_Timer.After(AGE_STEP, Again)
end

-- Draws the list, or hides it when there is nothing to list or the map is closed. Runs when the list changes,
-- the map changes or opens, and every few seconds while it is showing (the ages).
function V.RefreshList()
    if not (installed and MapOpen() and PG.Get("list")) then
        if panel and panel:IsShown() then panel:Hide() end
        ageGen = ageGen + 1
        return
    end
    local list = MP.Entries()
    if #list == 0 then
        if panel and panel:IsShown() then panel:Hide() end
        ageGen = ageGen + 1
        return
    end
    BuildPanel()
    local wasShown = panel:IsShown()
    local viewed = WorldMapFrame:GetMapID()
    local width, rowH, now = PanelWidth(), RowHeight(), Now()
    panel:SetWidth(width)
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", WorldMapFrame:GetCanvasContainer(), "TOPRIGHT", -44, -4)   -- left of the game's two buttons
    if styleDirty then
        styleDirty = false
        Restyle()
    end
    local n = math.min(#list, MAX_ROWS)
    for i = 1, n do
        local e = list[i]
        local row = rows[i] or NewRow(i)
        Anchor(row, i, rowH)
        row.entry = e
        row.here = e.map == viewed
        row.name:SetText(e.name)
        row.age:SetText(AgeText(math.floor(now - e.at)))
        row.where:SetText(PN.MapName(e.map))
        row.action:SetText(row.here and "Replay" or "Open map")
        Paint(row.name, pal.text)
        Paint(row.age, pal.stone)
        Paint(row.where, row.here and pal.stone or pal.text)
        Paint(row.action, pal.gold)
        local c = row.here and pal.bronzeLo or pal.gold
        row.bar:SetColorTexture(c[1], c[2], c[3], 1)
        row:Show()
    end
    for i = n + 1, #rows do rows[i].entry = nil; rows[i]:Hide() end
    panel.count:SetText(("(%d)"):format(n))
    panel:SetHeight(pad * 2 + HeadHeight() + n * rowH + 2)
    panel:Show()
    if not wasShown then ScheduleAges() end
end

---------------------------------------------------------------------------
-- The gesture
---------------------------------------------------------------------------
function V.Armed() return armed > Now() end

-- Ping the map: the next plain left-click on the map, within a minute. Returns whether it is armed.
function V.Arm()
    if R.MapTools then R.MapTools.Cancel() end   -- one armed click at a time
    local dist, why = MP.Route()
    if not dist then Say(MP.Reason(why)) return false end
    if not R:Enabled("mapPingsSend") then Say(MP.Reason("send-off")) return false end
    armed = Now() + ARM_SECONDS
    Say(MapOpen() and "Click the map where the ping goes." or "Open your map and click where the ping goes.")
    return true
end

function V.Disarm() armed = 0 end

-- Pings the group at a map click's place: the one path the gesture and the map tool bar (pins/MapTools.lua) share.
-- cx, cy: the map's own normalized cursor position on the map being viewed. Says why in one sentence when it can't.
-- Returns true, or false and a reason code (MP.Reason words it).
function V.PingAt(cx, cy)
    local map
    map, cx, cy = PM.ClickPlace(cx, cy)
    local ok, why = MP.Send(map, cx, cy)
    if not ok then
        stats.refused = stats.refused + 1
        Say(MP.Reason(why))
    end
    return ok, why
end

local function OnCanvasClick(_, button, cx, cy)
    if not (installed and MP.Active() and R:Enabled("mapPingsSend")) then return false end
    local take = PG.Matches(button)
    if not take and V.Armed() and button == "LeftButton" and not (IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown()) then
        take = true
    end
    if not take then return false end
    armed = 0
    V.PingAt(cx, cy)
    return true   -- this click was a ping (or a refused one): the map doesn't also zoom, move or set a waypoint
end

---------------------------------------------------------------------------
-- The hint: while the gesture's keys are held over the map, a small tooltip at the pointer says what a click does
---------------------------------------------------------------------------
local function HideHint()
    if hintShown then
        hintShown = false
        if GameTooltip:IsOwned(WorldMapFrame:GetCanvasContainer()) then GameTooltip:Hide() end
    end
end

local function OnModifier()
    if not (installed and MapOpen() and MP.Active() and PG.Get("hint") and R:Enabled("mapPingsSend")) then HideHint() return end
    local container = WorldMapFrame:GetCanvasContainer()
    if PG.Held() and container:IsMouseOver() then
        GameTooltip:SetOwner(container, "ANCHOR_CURSOR")
        GameTooltip:SetText("Click to ping your group", 1, 0.9, 0.55)
        GameTooltip:Show()
        hintShown = true
    else
        HideHint()
    end
end

---------------------------------------------------------------------------
-- The local test ping (the settings' Test ping): the real renderer and the real sound policy, at the middle of the
-- map being viewed. Nothing is sent, listed or saved, and nothing about you or the map changes.
---------------------------------------------------------------------------
local function RunTest()
    testUntil = 0
    if not (installed and MapOpen()) then return end
    local viewed = WorldMapFrame:GetMapID()
    if not V.ShowPing({ map = viewed, x = PN.COORD / 2, y = PN.COORD / 2, name = "Test ping", key = "test" }) then return end
    MP.Sound("test")
end

-- Returns true, or false and a sentence.
function V.Test()
    if not (installed and MP.Active()) then return false, "Turn on Party pins and Map pings to try a ping." end
    if MapOpen() then
        RunTest()
        return true
    end
    testUntil = Now() + TEST_SECONDS
    return true, "Open your world map to see the test ping."
end

---------------------------------------------------------------------------
-- The map's lifecycle
---------------------------------------------------------------------------
local function Build()
    if provider or not WorldMapFrame or not MapCanvasDataProviderMixin then return false end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData() StopAll() end
    function provider:RefreshAllData() Relayout() end
    function provider:OnMapChanged() MapChanged() end
    function provider:OnCanvasSizeChanged()
        styleDirty = true    -- the map's size can change the scale the border is drawn at
        Relayout()
        V.RefreshList()
    end
    function provider:OnCanvasScaleChanged() Relayout() end
    function provider:OnShow()
        C_Timer.After(0, function()
            if not (installed and MapOpen()) then return end
            V.RefreshList()
            if testUntil > Now() then RunTest() end
        end)
    end
    function provider:OnHide()
        -- nothing carries over a closed map: no waiting click, no ping still on its way, no hint
        Cancel()
        StopAll()
        HideHint()
        if panel then panel:Hide() end
        ageGen = ageGen + 1
    end
    -- once: the pointer leaving the map takes the hint away (the hook stays; HideHint does nothing unless it is up)
    WorldMapFrame:GetCanvasContainer():HookScript("OnLeave", HideHint)
    return true
end

-- On with the switches, off without them. The game's own pins and handlers, and other addons', are not touched.
function V.Refresh()
    if not WorldMapFrame then return end
    local want = MP.Active()
    if want and not PM.Canvas() then PM.Refresh() end
    if not PM.Canvas() then return end
    if not Build() and not provider then return end
    if want and not installed then
        WorldMapFrame:AddDataProvider(provider)
        WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
        R:On("MODIFIER_STATE_CHANGED", OnModifier)
        installed = true
        V.RefreshList()
    elseif not want and installed then
        WorldMapFrame:RemoveCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
        R:Off("MODIFIER_STATE_CHANGED", OnModifier)
        installed = false
        Cancel()
        armed, testUntil = 0, 0
        HideHint()
        WorldMapFrame:RemoveDataProvider(provider)   -- stops every ping (RemoveAllData)
        if panel then panel:Hide() end
        ageGen = ageGen + 1
    end
end

MP.Subscribe(function(event, entry)
    if event == "ping" then
        V.ShowPing(entry)
        V.RefreshList()
    elseif event == "own" then
        V.ShowPing({ map = entry.map, x = entry.x, y = entry.y, key = "self",
            name = PN.CleanName(SH.Short(SH.SelfName())) or "You" })
    elseif event == "clear" then
        Cancel()
        StopAll("test")
        V.RefreshList()
    else
        V.RefreshList()
    end
end)

local function LookChanged()
    styleDirty = true
    if panel and panel:IsShown() then V.RefreshList() end
end
PL.Subscribe(LookChanged)
PL.MenuLook.Subscribe(LookChanged)

R:On("PLAYER_LOGIN", V.Refresh)
R:On("ADDON_LOADED", function(name) if name == "Blizzard_WorldMap" then V.Refresh() end end)

-- Read only, for /tui diagnostics: states and counts, never a name or a place.
function V.Snapshot()
    local shown = 0
    for i = 1, #rows do if rows[i]:IsShown() then shown = shown + 1 end end
    return {
        installed = installed, open = MapOpen() and true or false, panel = panel ~= nil, panelShown = panel and panel:IsShown() or false,
        rows = shown, frames = #pool, showing = #active, updating = driver ~= nil and driver:GetScript("OnUpdate") ~= nil,
        waiting = pending ~= nil, armed = V.Armed(), testWaiting = testUntil > Now(),
        shown = stats.shown, replays = stats.replays, navigations = stats.navigations, stale = stats.stale,
        expired = stats.expired, clicks = stats.clicks, refused = stats.refused,
    }
end
