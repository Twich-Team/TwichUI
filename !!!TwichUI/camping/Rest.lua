-- TwichUI: camping bar, the Cozy Sleeping Bag's progress bar
-- Lying in the Cozy Sleeping Bag for a minute gives +1% experience, two minutes +2%, three +3% (guides: Data.lua REST_*).
-- This draws a bar to three minutes with a notch at each minute and a timer, while you lie in the bag. It is part of the
-- camping bar: it is on only while the camping bar is, has its own switch (restShow, on by default) and its own place, and
-- is a plain frame (no clicks, nothing protected), so it shows in combat too. It never uses the bag, sends anything, plays a
-- sound or says anything in chat.
--
-- How it knows you are in the bag (camping/State.lua RestStep decides; this reads the game):
--   * the game gives no buff during the first minute, so the clock cannot start from an aura. It starts when you are
--     "resting" (IsResting; the guides say the bag counts as a rested place) within a few minutes of using the bag (the item's
--     cooldown start, or the use spell succeeding);
--   * once the Well-Rested aura exists its stack count moves the clock forward to match, never back;
--   * the clock stops a moment after resting stops (you left the bag), and the bar lingers a few seconds, then goes.
-- NONE of those signals has been read from a Forever client. `/tui camp probe` prints what the client says right now, and
-- `/tui camp probe watch` records a few minutes of events to read with `/tui camp probe show`; docs/camping-bar.md lists
-- what to look for.
--
-- Cost: events only while the bar and its switch are on (resting, entering the world, bag cooldown, and the player's own
-- aura and cast events). A 0.2 s timer runs only while the bar is on screen. No OnUpdate.
-- Saved: the look is in TwichUIDB.ui.campingBar (rest* keys, Bar.lua's C.DEFAULTS); the place is
-- TwichUIDB.ui.campingRestPosition { x, y } from the middle of the screen. Nothing about a session is saved.

local R = TwichUI
local D, S, C = R.CampingData, R.CampingState, R.Camping
local RB = {}
R.CampingRest = RB

local DEFAULT_X, DEFAULT_Y = 0, -215
local TICK = 0.2                 -- seconds between looks while the bar is on screen
local SMOOTH_TICK = 1 / 30       -- seconds between redraws with "smooth" on (reads of the game stay at TICK)
local UNKNOWN_ICON = 134400
local GAP = 4                    -- between the icon and the bar
local PREVIEW_SPEED, PREVIEW_START = 15, 0
local EDIT_SAMPLE = 90           -- seconds shown while Edit Mode is open, so the bar can be placed
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"

local st = S.RestNew()           -- the session
local frame, mover, ticker
local evFrame
local registered = {}            -- event = true, while listened for
local preview                    -- { t0 } while the settings' sample runs
local editing = false
local moving = false          -- the settings' Move button is on
local castAt                     -- when the bag's use spell last succeeded (GetTime)
local itemSpell                  -- the bag's use spell ID, once the game has told
local ticks = 0
local tickerRate, lastObserve   -- the running ticker's interval, and when the game was last read
local drawn = {}                 -- last text drawn, so an unchanged tick sets nothing
local geom                       -- { w, h, edge }: the room inside the border, set by Layout
local borders = {}               -- what Borders.Draw made for the bar's border

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- Place
---------------------------------------------------------------------------
function RB.Position()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.campingRestPosition
    if type(saved) == "table" and C.ValidOffset(saved.x) and C.ValidOffset(saved.y) then return saved.x, saved.y end
    return DEFAULT_X, DEFAULT_Y
end

-- Where the bar goes now: the saved place or, while EllesmereUI's Unlock Mode is in charge of it (camping/Unlock.lua), the
-- place its stand-in is at. Same coordinates either way.
function RB.Placement()
    local U = RB.Unlock
    if U then
        local x, y = U.Offset()
        if x then return x, y end
    end
    return RB.Position()
end

local function Place(f)
    local x, y = RB.Placement()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function RB.SetPosition(x, y)
    if type(TwichUIDB) ~= "table" then return end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    TwichUIDB.ui.campingRestPosition = x and { x = x, y = y } or nil
    if frame then Place(frame) end
    if mover then Place(mover) end
end
function RB.ResetPosition()
    RB.SetPosition(nil)
    if RB.Unlock then RB.Unlock.Reset() end
end

-- The bar's size, for the stand-in EllesmereUI moves.
function RB.Footprint() return C.Get("restWidth"), C.Get("restHeight") end

-- EllesmereUI's stand-in moved: the bar (a plain frame, so also in combat) goes where it is.
function RB.Reposition()
    if frame then Place(frame) end
    if mover and mover:IsShown() then Place(mover) end
    return true
end

---------------------------------------------------------------------------
-- Reading the game (each read tolerates a missing or secret answer)
---------------------------------------------------------------------------
local function ReadResting()
    if not IsResting then return nil end
    local v = Plain(IsResting())
    if v == nil then return nil end
    return v and true or false
end

-- The Well-Rested stack count: 0 when the aura is absent, nil when the game would not say.
local function ReadStacks()
    local U = C_UnitAuras
    if not (U and U.GetPlayerAuraBySpellID) then return nil end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and Plain(C_Secrets.ShouldAurasBeSecret()) then return nil end
    local ok, aura = pcall(U.GetPlayerAuraBySpellID, D.REST_AURA)
    if not ok then return nil end
    if aura == nil then return 0 end
    if issecretvalue and issecretvalue(aura) then return nil end
    local n = type(aura) == "table" and Plain(aura.applications)
    if type(n) ~= "number" then return nil end
    return math.max(1, n)
end

-- When the bag was last used: the later of its cooldown's start and the use spell's last success.
local function ReadUsedAt()
    local at = castAt
    if C_Container and C_Container.GetItemCooldown then
        local ok, start, duration = pcall(C_Container.GetItemCooldown, D.SLEEPING_BAG)
        start, duration = Plain(start), Plain(duration)
        if ok and type(start) == "number" and type(duration) == "number" and start > 0 and duration > 1.5 then
            if not at or start > at then at = start end
        end
    end
    return at
end

local function ItemSpell()
    if itemSpell == nil and C_Item and C_Item.GetItemSpell then
        local ok, _, id = pcall(C_Item.GetItemSpell, D.SLEEPING_BAG)
        id = Plain(id)
        if ok and type(id) == "number" then itemSpell = id end
    end
    return itemSpell
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function Rgba(hex)
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x%x%x$") then return 1, 1, 1, 1 end
    local function part(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
    return part(3), part(5), part(7), part(1)
end

local function FontPath()
    local f = GameFontHighlightSmall
    local path = f and f.GetFont and f:GetFont()
    return path or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "TwichUICampingRest", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    local track = CreateFrame("Frame", nil, frame)
    frame.track = track
    track.back = track:CreateTexture(nil, "BACKGROUND")
    track.fill = track:CreateTexture(nil, "ARTWORK")
    track.notch = { track:CreateTexture(nil, "OVERLAY", nil, 1), track:CreateTexture(nil, "OVERLAY", nil, 1) }
    track.rim = { top = track:CreateTexture(nil, "OVERLAY"), bottom = track:CreateTexture(nil, "OVERLAY"),
        left = track:CreateTexture(nil, "OVERLAY"), right = track:CreateTexture(nil, "OVERLAY") }
    local text = CreateFrame("Frame", nil, track)
    text:SetAllPoints()
    text:SetFrameLevel(track:GetFrameLevel() + 2)
    track.label = text:CreateFontString(nil, "OVERLAY")
    track.time = text:CreateFontString(nil, "OVERLAY")
end

-- Size, colours, notches, border and text style: everything the player sets except the progress itself. Safe in combat.
local OUTLINE_FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function BorderColor()
    local opacity = C.Get("restBorderOpacity") / 100
    if C.Get("restBorderClass") then
        local _, class = UnitClass("player")
        local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b, opacity end
    end
    local r, g, b = Rgba(C.Get("restBorderColor"))
    return r, g, b, opacity
end

-- The file the fill is drawn with: a status bar texture from LibSharedMedia or EllesmereUI, or a flat fill.
local function FillFile()
    local MS = R.MenuStyle
    if MS and MS.StatusBars then
        local file = MS.StatusBars.Resolve(C.Get("restTexture"))
        if file then return file end
    end
    return WHITE
end

local function SetFont(fs, size)
    local fallback = FontPath()
    local MS = R.MenuStyle
    local file = fallback
    if MS and MS.Fonts then file = MS.Fonts.Resolve(C.Get("restFont"), fallback) or fallback end
    local flags = OUTLINE_FLAGS[C.Get("restOutline")] or ""
    if fs:SetFont(file, size, flags) == false then fs:SetFont(fallback, size, flags) end
end

local function Layout()
    if not frame then return end
    local W, H = C.Get("restWidth"), C.Get("restHeight")
    local edge = C.Get("restBorderSize")
    local showIcon = C.Get("restIcon")
    local iconW = showIcon and H or 0
    local trackLeft = showIcon and (H + GAP) or 0
    local trackW = math.max(1, W - trackLeft)
    frame:SetSize(W, H)
    frame.icon:SetShown(showIcon)
    frame.icon:ClearAllPoints()
    frame.icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.icon:SetSize(iconW, H)
    local icon = C_Item and C_Item.GetItemIconByID and Plain(C_Item.GetItemIconByID(D.SLEEPING_BAG))
    frame.icon:SetTexture(icon or UNKNOWN_ICON)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local track = frame.track
    track:ClearAllPoints()
    track:SetPoint("TOPLEFT", frame, "TOPLEFT", trackLeft, 0)
    track:SetSize(trackW, H)
    track.back:SetAllPoints()
    track.back:SetColorTexture(Rgba(C.Get("restBack")))

    -- the border: a plain line drawn here, or a texture (LibSharedMedia's, EllesmereUI's) drawn by Borders
    local r, g, b, a = BorderColor()
    local texture = C.Get("restBorderTexture")
    local mode = R.Borders.Draw(borders, track, texture, edge, r, g, b, a)
    local inset = C.EdgeInset(mode, texture, edge)
    for _, t in pairs(track.rim) do
        t:ClearAllPoints()
        t:SetColorTexture(r, g, b, a)
        t:SetShown(mode == "line" and edge > 0)
    end
    local e = math.max(edge, 1)
    track.rim.top:SetPoint("TOPLEFT"); track.rim.top:SetPoint("TOPRIGHT"); track.rim.top:SetHeight(e)
    track.rim.bottom:SetPoint("BOTTOMLEFT"); track.rim.bottom:SetPoint("BOTTOMRIGHT"); track.rim.bottom:SetHeight(e)
    track.rim.left:SetPoint("TOPLEFT"); track.rim.left:SetPoint("BOTTOMLEFT"); track.rim.left:SetWidth(e)
    track.rim.right:SetPoint("TOPRIGHT"); track.rim.right:SetPoint("BOTTOMRIGHT"); track.rim.right:SetWidth(e)

    -- the room inside the border
    local innerW, innerH = math.max(1, trackW - 2 * inset), math.max(1, H - 2 * inset)
    geom = { w = innerW, h = innerH, edge = inset }
    track.fill:ClearAllPoints()
    track.fill:SetPoint("TOPLEFT", track, "TOPLEFT", inset, -inset)
    track.fill:SetHeight(innerH)
    track.fill:SetTexture(FillFile())

    local nw = C.Get("restNotchWidth")
    local nr, ng, nb, na = Rgba(C.Get("restNotchColor"))
    for i, n in ipairs(track.notch) do
        n:SetColorTexture(nr, ng, nb, na)
        n:ClearAllPoints()
        n:SetPoint("TOPLEFT", track, "TOPLEFT", inset + math.floor(innerW * i / D.REST_STACKS - nw / 2 + 0.5), -inset)
        n:SetSize(nw, innerH)
    end

    SetFont(track.label, C.Get("restTextSize"))
    SetFont(track.time, C.Get("restTimerSize"))
    track.label:SetTextColor(Rgba(C.Get("restTextColor")))
    track.time:SetTextColor(Rgba(C.Get("restTimerColor")))
    for _, fs in ipairs({ track.label, track.time }) do fs:ClearAllPoints() end
    track.label:SetPoint("LEFT", track, "LEFT", inset + 5, 0)
    track.label:SetJustifyH("LEFT")
    track.time:SetPoint("RIGHT", track, "RIGHT", -(inset + 5), 0)
    track.time:SetJustifyH("RIGHT")
    frame:SetAlpha(C.Get("restOpacity") / 100)
    drawn = {}
    if RB.Unlock then RB.Unlock.Sync() end
end

-- Draws a view: the fill, its colour, the label and the timer.
local function Draw(view)
    local track = frame.track
    local inner = geom
    if not inner then return end
    local width = inner.w * view.fraction
    if not C.Get("restSmooth") then width = math.floor(width + 0.5) end   -- whole pixels, a step at a time
    if drawn.width ~= width then
        drawn.width = width
        track.fill:SetShown(width > 0)
        if width > 0 then
            track.fill:SetWidth(width)
            track.fill:SetTexCoord(0, view.fraction, 0, 1)   -- a textured fill is cut, not squeezed
        end
    end
    if drawn.complete ~= view.complete then
        drawn.complete = view.complete
        track.fill:SetVertexColor(Rgba(C.Get(view.complete and "restDoneColor" or "restFill")))
    end
    local label = C.Get("restLabel") and S.RestLabel(view) or ""
    if drawn.label ~= label then drawn.label = label; track.label:SetText(label) end
    local time = S.RestTimerText(C.Get("restTimer"), view)
    if drawn.time ~= time then drawn.time = time; track.time:SetText(time) end
end

---------------------------------------------------------------------------
-- What is showing, and the clock that moves it
---------------------------------------------------------------------------
local function Enabled() return R:Enabled("campingBar") and C.Get("restShow") end

-- The view to draw now, or nil for none. A real session wins over the settings' sample, which wins over Edit Mode's.
local function CurrentView(now)
    if st.phase == "lying" then return S.RestView(math.max(st.elapsed, now - st.start)) end   -- between reads it runs on the clock
    if st.phase ~= "idle" then return S.RestView(st.elapsed) end
    if preview then
        local e = (now - preview.t0) * PREVIEW_SPEED + PREVIEW_START
        if e <= D.REST_TOTAL + C.Get("restLinger") * PREVIEW_SPEED then return S.RestView(e) end
        preview = nil
    end
    if editing then return S.RestView(EDIT_SAMPLE) end
    return nil
end

local StopTicker
local function Render()
    if not Enabled() then
        if frame then frame:Hide() end
        return StopTicker()
    end
    local view = CurrentView(GetTime())
    if not view then
        if frame then frame:Hide() end
        return StopTicker()
    end
    Build()
    if not geom then Layout() end
    Draw(view)
    if not frame:IsShown() then Place(frame); frame:Show() end
end

local function Observe()
    lastObserve = GetTime()
    local resting = ReadResting()
    if st.phase == "idle" and resting ~= true then return end   -- nothing can start
    S.RestStep(st, { now = GetTime(), resting = resting, usedAt = ReadUsedAt(), stacks = ReadStacks(),
        linger = C.Get("restLinger") })
end

local function Tick()
    ticks = ticks + 1
    -- smooth redraws more often than the game is read: the bar runs on the clock in between (CurrentView)
    if not lastObserve or GetTime() - lastObserve >= TICK - 0.001 then Observe() end
    Render()
end

local function StartTicker()
    if not (C_Timer and C_Timer.NewTicker) then return end
    local rate = C.Get("restSmooth") and SMOOTH_TICK or TICK
    if ticker and tickerRate == rate then return end
    if ticker then ticker:Cancel() end
    ticker, tickerRate = C_Timer.NewTicker(rate, Tick), rate
end

function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil; tickerRate = nil end
end

-- Looks now, then makes sure the clock runs exactly while something is showing.
local function Look()
    Observe()
    Render()
    if frame and frame:IsShown() then StartTicker() else StopTicker() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnEvent(_, event, unit, _, spellID)
    if event == "UNIT_AURA" then
        -- cheap while nothing can start: Observe reads IsResting first
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local want = ItemSpell()
        if want and Plain(spellID) == want then castAt = GetTime() else return end
    end
    Look()
end

local function Listen(wanted)
    if wanted and not evFrame then
        evFrame = CreateFrame("Frame")
        evFrame:SetScript("OnEvent", R.Perf.Wrap("camping.rest", OnEvent))
    end
    if wanted and not registered.PLAYER_UPDATE_RESTING then
        evFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
        evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        evFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
        evFrame:RegisterUnitEvent("UNIT_AURA", "player")
        evFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        for _, e in ipairs({ "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_COOLDOWN", "UNIT_AURA",
            "UNIT_SPELLCAST_SUCCEEDED" }) do registered[e] = true end
    elseif not wanted and evFrame and registered.PLAYER_UPDATE_RESTING then
        evFrame:UnregisterAllEvents()
        for e in pairs(registered) do registered[e] = nil end
    end
end

---------------------------------------------------------------------------
-- Edit Mode: an outline stands over the bar while it is open; drag to move, right-click to put it back
---------------------------------------------------------------------------
local function EditModeActive()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

local function BuildMover()
    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(C.Get("restWidth"), C.Get("restHeight"))
    mover:SetFrameStrata("HIGH")
    mover:SetFrameLevel(1000)
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    if mover.SetDontSavePosition then mover:SetDontSavePosition(true) end
    mover:Hide()
    local fill = mover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MOVER_ATLAS) then
        fill:SetAtlas(MOVER_ATLAS)
    else
        fill:SetColorTexture(0.55, 0.43, 0.22, 0.35)
    end
    mover:SetScript("OnDragStart", function(self) if not InCombat() then self:StartMoving() end end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        if not (cx and cy and px and py) then Place(self) return end
        RB.SetPosition(math.floor(cx - px + 0.5), math.floor(cy - py + 0.5))
    end)
    mover:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then RB.ResetPosition() end end)
    mover:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("TwichUI: Sleeping bag bar", 1, 1, 1)
        GameTooltip:AddLine("Where the Cozy Sleeping Bag's progress bar sits. Drag to move it; right-click to put it back.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function ShowMover(shown)
    -- One mover for the place: when EllesmereUI's Unlock Mode is in charge of it, this outline stays away.
    if shown and RB.Unlock and RB.Unlock.Drives() then shown = false end
    if shown and Enabled() then
        editing = true
        Build()
        Layout()
        if not mover then BuildMover() end
        mover:SetSize(frame:GetSize())
        Place(mover)
        mover:Show()
    else
        editing, moving = false, false
        if mover then mover:StopMovingOrSizing(); mover:Hide() end
    end
    Look()
end

-- Move mode, for the settings page: the same outline and sample as Edit Mode, without Edit Mode. Ends with Done, the
-- settings window closing, or Edit Mode closing.
function RB.Moving() return moving end
function RB.StartMove()
    if not Enabled() then return false, "off" end
    if RB.Unlock and RB.Unlock.Drives() then return false, "unlock" end
    moving = true
    ShowMover(true)
    return true
end
function RB.StopMove()
    if not moving then return end
    moving = false
    ShowMover(EditModeActive())
end
if R.OnSettingsClosed then R.OnSettingsClosed(function() RB.StopMove() end) end

local editHooked = false
local function HookEditMode()
    if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    editHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function() ShowMover(true) end, RB)
    EventRegistry:RegisterCallback("EditMode.Exit", function() ShowMover(false) end, RB)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- Redraws for a changed setting and makes the events match the switches. Safe to call at any time.
local subscribed = false
local function Subscribe()
    local MS = R.MenuStyle
    if subscribed or not MS then return end
    subscribed = true
    local function Redraw() if frame then Layout(); Render() end end
    if MS.Fonts and MS.Fonts.Subscribe then MS.Fonts.Subscribe(Redraw) end
    if MS.StatusBars and MS.StatusBars.Subscribe then MS.StatusBars.Subscribe(Redraw) end
end

function RB.Refresh()
    Subscribe()
    local on = Enabled()
    Listen(on)
    if RB.Unlock then RB.Unlock.Refresh() end
    if not on then
        st = S.RestNew()
        preview, editing, moving = nil, false, false
        if mover then mover:StopMovingOrSizing(); mover:Hide() end
        Render()
        return
    end
    HookEditMode()
    if RB.Unlock then RB.Unlock.Refresh() end
    if frame then Layout() end
    if mover and mover:IsShown() then mover:SetSize(C.Get("restWidth"), C.Get("restHeight")); Place(mover) end
    if EditModeActive() and not editing then ShowMover(true) return end
    if moving and RB.Unlock and RB.Unlock.Drives() then ShowMover(false) end
    Look()
end

-- A fifteen-times-speed run of the whole bar, for the settings page. A real session in progress is left alone.
function RB.Preview()
    if not Enabled() or st.phase ~= "idle" then return false end
    preview = { t0 = GetTime() }
    Build()
    Layout()
    Look()
    return true
end

function RB.Snapshot()
    local events = 0
    for _ in pairs(registered) do events = events + 1 end
    return { events = events, built = frame ~= nil, shown = frame ~= nil and frame:IsShown() or false,
        ticking = ticker ~= nil, ticks = ticks, phase = st.phase, elapsed = st.elapsed }
end

-- For tests: the session and a look on demand.
function RB.Session() return st end
function RB.Look() Look() end
function RB.Geometry() return geom end

---------------------------------------------------------------------------
-- /tui camp probe: what the client says about the bag, for the in-game check (docs/camping-bar.md)
---------------------------------------------------------------------------
local WATCH_SECONDS, WATCH_LINES = 360, 80
local watchFrame, watchLog, watchUntil, watchStart

local function AuraLine(a)
    local name, id, n, dur = Plain(a.name), Plain(a.spellId), Plain(a.applications), Plain(a.duration)
    if type(name) ~= "string" then name = "?" end
    name = name:gsub("[%c|]", "")
    return ("%s (%s) x%s, %ss"):format(name, tostring(id), tostring(n), tostring(dur and math.floor(dur) or "?"))
end

local function Describe()
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    add("resting: %s", tostring(ReadResting()))
    local stacks = ReadStacks()
    add("Well-Rested aura %d: stacks %s", D.REST_AURA, stacks == nil and "unreadable" or tostring(stacks))
    local usedAt = ReadUsedAt()
    add("bag used: %s", usedAt and ("%d s ago"):format(math.floor(GetTime() - usedAt + 0.5)) or "no use seen (cooldown not running)")
    add("bag use spell: %s", tostring(ItemSpell()))
    add("bar: %s, %s s", st.phase, tostring(math.floor(st.elapsed or 0)))
    local U = C_UnitAuras
    if U and U.GetAuraDataByIndex then
        local out = {}
        for i = 1, 40 do
            local ok, a = pcall(U.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or type(a) ~= "table" or (issecretvalue and issecretvalue(a)) then break end
            out[#out + 1] = AuraLine(a)
        end
        add("buffs (%d): %s", #out, table.concat(out, "; "))
    end
    return lines
end

local function Say(lines) for _, line in ipairs(lines) do R.Print("%s", line) end end

local function WatchNote(event, ...)
    if not watchLog then return end
    if #watchLog >= WATCH_LINES then return end
    local t = math.floor((GetTime() - watchStart) * 10 + 0.5) / 10
    local extra = ""
    if event == "UNIT_AURA" then
        extra = ("stacks %s"):format(tostring(ReadStacks()))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        extra = ("spell %s"):format(tostring(Plain((select(3, ...)))))
    end
    watchLog[#watchLog + 1] = ("%5.1fs %s resting=%s %s"):format(t, event, tostring(ReadResting()), extra)
end

local function WatchStop()
    if watchFrame then watchFrame:UnregisterAllEvents() end
    watchUntil = nil
end

function RB.Probe(arg)
    arg = (arg or ""):lower():match("^%s*(%S*)") or ""
    if arg == "watch" then
        watchFrame = watchFrame or CreateFrame("Frame")
        watchFrame:SetScript("OnEvent", function(_, event, ...)
            if watchUntil and GetTime() > watchUntil then return WatchStop() end
            WatchNote(event, ...)
        end)
        watchFrame:UnregisterAllEvents()
        for _, e in ipairs({ "PLAYER_UPDATE_RESTING", "BAG_UPDATE_COOLDOWN" }) do watchFrame:RegisterEvent(e) end
        watchFrame:RegisterUnitEvent("UNIT_AURA", "player")
        watchFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        watchLog, watchStart = {}, GetTime()
        watchUntil = watchStart + WATCH_SECONDS
        C_Timer.After(WATCH_SECONDS + 1, function() if watchUntil and GetTime() > watchUntil then WatchStop() end end)
        R.Print("watching resting, buff and bag events for %d minutes. Use the bag, lie in it, then type /tui camp probe show.", WATCH_SECONDS / 60)
    elseif arg == "stop" then
        WatchStop()
        R.Print("stopped watching.")
    elseif arg == "show" then
        if not watchLog then R.Print("nothing recorded. Type /tui camp probe watch first.") return end
        R.Print("%d events recorded%s:", #watchLog, watchUntil and " (still watching)" or "")
        Say(watchLog)
        Say(Describe())
    else
        R.Print("camping bar probe (the bag's rest clock). Also: probe watch | show | stop")
        Say(Describe())
    end
end

