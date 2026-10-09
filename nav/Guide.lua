-- TwichUI: navigation, the next step
-- While a route is active, a slim strip near the top of the screen says what to do next and how long
-- it should take, with Recalculate and Stop. An optional arrow below it points the way to where the
-- current step leads, with the distance. Both are plain frames: they work in combat and never take an
-- action for you.
--
-- Times are said honestly: walking is "at least" (measured in a straight line), a flight is "about", and
-- the strip says when a time is rough. When the route ends by arriving (or because it can no longer be
-- followed) the strip says so for a few seconds, then goes; stopping it yourself takes it away at once.
-- No sound, no chat, no animation.
--
-- Move both in Edit Mode: while it is open, an outline stands where each appears. Drag to move it,
-- right-click to put it back. Places are kept in TwichUIDB.ui (navStripPlace, navArrowPlace).

local R = TwichUI
local G = {}
R.NavGuide = G

local STRIP_W, STRIP_H = 520, 50
local ARROW_SIZE = 56
local STRIP_TOP = -64                 -- default place: centred, this far below the top of the screen
local ARROW_GAP = 6                   -- default place: just under the strip
local FINAL_HOLD = 4                  -- seconds the closing line stays
local ARROW_EVERY = 0.05              -- seconds between arrow updates while it is shown
local SHAFT, HEAD, HEAD_ANGLE = 15, 9, 0.6
local FINAL = { arrived = true, ["left-continent"] = true, ["no-route"] = true }
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"
local NON_WESTERN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }
local FONT_STEP = R.PATH .. [[media\fonts\BarlowSemiCondensed-SemiBold.ttf]]
local FONT_NOTE = R.PATH .. [[media\fonts\BarlowSemiCondensed-Medium.ttf]]

local strip, arrow
local movers = {}
local finalToken = 0
local shown = { key = nil }           -- what the strip last said, so it is only rewritten when that changes
local editHooked = false

local function K()
    local S = R.ChronicleStyle
    return S and S.color or {
        bg = { 0.150, 0.115, 0.082 }, bronze = { 0.55, 0.43, 0.22 }, bronzeLo = { 0.30, 0.23, 0.13 },
        gold = { 0.79, 0.64, 0.29 }, text = { 0.93, 0.88, 0.76 }, stone = { 0.62, 0.58, 0.51 },
    }
end

local function SetFont(fs, path, size, fallback)
    local locale = GetLocale and GetLocale()
    if NON_WESTERN[locale] or not fs:SetFont(path, size) then
        local font = _G[fallback]
        local file = font and font.GetFont and font:GetFont()
        fs:SetFont(file or STANDARD_TEXT_FONT, size)
    end
end

---------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------
local function Saved(key)
    local ui = TwichUIDB and TwichUIDB.ui
    local p = type(ui) == "table" and ui[key]
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and p.x == p.x and p.y == p.y then return p end
end

local function PlaceStrip(frame)
    frame:ClearAllPoints()
    local p = Saved("navStripPlace")
    if p then frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else frame:SetPoint("TOP", UIParent, "TOP", 0, STRIP_TOP) end
end

local function PlaceArrow(frame)
    frame:ClearAllPoints()
    local p = Saved("navArrowPlace")
    if p then frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else frame:SetPoint("TOP", UIParent, "TOP", 0, STRIP_TOP - STRIP_H - ARROW_GAP) end
end

---------------------------------------------------------------------------
-- The strip
---------------------------------------------------------------------------
local function BuildStrip()
    local c = K()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(STRIP_W, STRIP_H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], 0.92)
        f:SetBackdropBorderColor(c.bronze[1], c.bronze[2], c.bronze[3], 0.9)
    end
    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.accent:SetWidth(3)
    f.accent:SetPoint("TOPLEFT", 1, -1)
    f.accent:SetPoint("BOTTOMLEFT", 1, 1)
    f.step = f:CreateFontString(nil, "OVERLAY")
    SetFont(f.step, FONT_STEP, 13, "GameFontHighlight")
    f.step:SetTextColor(c.text[1], c.text[2], c.text[3])
    f.step:SetJustifyH("LEFT")
    f.step:SetWordWrap(false)
    f.step:SetPoint("TOPLEFT", 14, -9)
    f.step:SetPoint("RIGHT", f, "RIGHT", -150, 0)
    f.note = f:CreateFontString(nil, "OVERLAY")
    SetFont(f.note, FONT_NOTE, 11, "GameFontNormalSmall")
    f.note:SetTextColor(c.stone[1], c.stone[2], c.stone[3])
    f.note:SetJustifyH("LEFT")
    f.note:SetWordWrap(false)
    f.note:SetPoint("TOPLEFT", f.step, "BOTTOMLEFT", 0, -4)
    f.note:SetPoint("RIGHT", f, "RIGHT", -150, 0)
    local S = R.ChronicleStyle
    if S and S.Button then
        f.stop = S.Button(f, "Stop", 46, "secondary", function() if R.Nav then R.Nav.Stop() end end)
        f.recalc = S.Button(f, "Recalculate", 84, "secondary", function() if R.Nav then R.Nav.Recalculate() end end)
    else
        f.stop = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.stop:SetSize(46, 22)
        f.stop:SetText("Stop")
        f.stop:SetScript("OnClick", function() if R.Nav then R.Nav.Stop() end end)
        f.recalc = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.recalc:SetSize(84, 22)
        f.recalc:SetText("Recalculate")
        f.recalc:SetScript("OnClick", function() if R.Nav then R.Nav.Recalculate() end end)
    end
    f.stop:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.recalc:SetPoint("RIGHT", f.stop, "LEFT", -6, 0)
    local I = R.Interact
    if I and I.Tip then
        I.Tip(f.stop, "Stop the route", "Ends this route. Your map pin stays where it is.")
        I.Tip(f.recalc, "Recalculate", "Plans the route again from where you stand, to the same destination.")
    end
    f:Hide()
    PlaceStrip(f)
    return f
end

local function Accent(mode)
    local c = K()
    local tone = mode == "flight" and c.bronze or c.gold
    strip.accent:SetColorTexture(tone[1], tone[2], tone[3], 1)
end

local function Say(step, note, mode, buttons)
    if not strip then strip = BuildStrip() end
    strip.step:SetText(step)
    strip.note:SetText(note or "")
    Accent(mode)
    strip.stop:SetShown(buttons)
    strip.recalc:SetShown(buttons)
    strip:Show()
end

local function Whole(n) return n and math.floor(n + 0.5) or -1 end

-- Rewrites the strip for the active route. Cheap when nothing it shows has changed.
local function UpdateStrip()
    local N = R.Nav
    local j = N and N.Current()
    if not j then return end
    local leg = j.plan.legs[j.index]
    local step = N.StepRemainingNow()
    local total = N.RemainingNow()
    local key = j.index * 4 + (j.flying and 1 or 0) + (j.status and 2 or 0)
    if shown.key == key and shown.step == Whole(step) and shown.total == Whole(total) and shown.status == j.status and shown.plan == j.plan then return end
    shown.key, shown.step, shown.total, shown.status, shown.plan = key, Whole(step), Whole(total), j.status, j.plan
    finalToken = finalToken + 1   -- a route in progress cancels any closing line still waiting to go
    if j.status == "instance" then
        Say("Route paused", "Routes wait outside dungeons, raids and battlegrounds.", leg.mode, true)
        return
    elseif j.status == "no-position" then
        Say("Route paused", "The game isn't giving your position here.", leg.mode, true)
        return
    end
    local stepsLeft = #j.plan.legs - j.index
    local after = total and ((j.plan.minimum and "  ·  journey at least " or "  ·  journey about ") .. N.Duration(total)) or ""
    if leg.mode == "flight" and j.flying then
        Say("Flying to " .. (leg.toNode and leg.toNode.name or "a flight point"),
            N.TimeNote(leg, step, j.plan.speedLearned) .. after, "flight", true)
    elseif leg.mode == "flight" then
        Say(N.Instruction(leg, j.goal) .. " (choose it at the flight master)",
            N.TimeNote(leg, step, j.plan.speedLearned) .. after, "flight", true)
    else
        Say(N.Instruction(leg, j.goal), N.TimeNote(leg, step, j.plan.speedLearned)
            .. (stepsLeft > 0 and after or ""), "walk", true)
    end
end

local function HideStrip()
    shown.key = nil
    if strip then strip:Hide() end
end

---------------------------------------------------------------------------
-- The arrow: three lines over three darker ones, turned to face where the step leads.
---------------------------------------------------------------------------
local function BuildArrow()
    local c = K()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(ARROW_SIZE, ARROW_SIZE + 14)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:EnableMouse(false)
    f.lines, f.shadows = {}, {}
    for i = 1, 3 do
        local s = f:CreateLine(nil, "ARTWORK", nil, 0)
        s:SetColorTexture(0.05, 0.03, 0.02, 0.85)
        s:SetThickness(6)
        f.shadows[i] = s
        local l = f:CreateLine(nil, "ARTWORK", nil, 1)
        l:SetColorTexture(c.gold[1], c.gold[2], c.gold[3], 1)
        l:SetThickness(3)
        f.lines[i] = l
    end
    f.distance = f:CreateFontString(nil, "OVERLAY")
    SetFont(f.distance, FONT_NOTE, 11, "GameFontNormalSmall")
    f.distance:SetTextColor(c.text[1], c.text[2], c.text[3])
    f.distance:SetShadowColor(0, 0, 0, 0.85)
    f.distance:SetShadowOffset(1, -1)
    f.distance:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    f.elapsed, f.yards = 0, -1
    f:Hide()
    PlaceArrow(f)
    return f
end

local function Segment(i, x1, y1, x2, y2)
    local s, l = arrow.shadows[i], arrow.lines[i]
    s:SetStartPoint("CENTER", arrow, x1, y1 + 7)
    s:SetEndPoint("CENTER", arrow, x2, y2 + 7)
    l:SetStartPoint("CENTER", arrow, x1, y1 + 7)
    l:SetEndPoint("CENTER", arrow, x2, y2 + 7)
end

local function SetLinesShown(on)
    for i = 1, 3 do arrow.lines[i]:SetShown(on); arrow.shadows[i]:SetShown(on) end
    arrow.distance:SetShown(on)
end

-- Where the arrow points now: the end of the current walking step, or the flight point a flight
-- leaves from. Nothing while in the air or paused.
local function Target(j)
    if j.status then return nil end
    local leg = j.plan.legs[j.index]
    if leg.mode == "walk" then return leg.toX, leg.toY end
    if not j.flying then return leg.fromX, leg.fromY end
end

local function UpdateArrow(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < ARROW_EVERY then return end
    self.elapsed = 0
    local N, W = R.Nav, R.NavWorld
    local j = N and N.Current()
    local tx, ty
    if j then tx, ty = Target(j) end
    local x, y = W.Here()
    local facing = GetPlayerFacing and W.Plain(GetPlayerFacing())
    if not (tx and x and facing) then SetLinesShown(false) return end
    SetLinesShown(true)
    local a = W.Bearing(x, y, tx, ty) - facing
    local dx, dy = -math.sin(a), math.cos(a)   -- up is the way you face
    local tipX, tipY = dx * SHAFT, dy * SHAFT
    Segment(1, -dx * SHAFT, -dy * SHAFT, tipX, tipY)
    local left, right = a + HEAD_ANGLE, a - HEAD_ANGLE
    Segment(2, tipX, tipY, tipX + math.sin(left) * HEAD, tipY - math.cos(left) * HEAD)
    Segment(3, tipX, tipY, tipX + math.sin(right) * HEAD, tipY - math.cos(right) * HEAD)
    local yards = math.floor(W.Distance(x, y, tx, ty) + 0.5)
    if yards ~= self.yards then
        self.yards = yards
        self.distance:SetFormattedText("%d yd", yards)
    end
end

local function ShowArrow(on)
    if on then
        if not arrow then arrow = BuildArrow() end
        if not arrow:IsShown() then
            arrow.elapsed, arrow.yards = ARROW_EVERY, -1
            arrow:SetScript("OnUpdate", UpdateArrow)
            arrow:Show()
        end
    elseif arrow then
        arrow:SetScript("OnUpdate", nil)   -- no work at all while hidden
        arrow:Hide()
    end
end

---------------------------------------------------------------------------
-- Following the journey
---------------------------------------------------------------------------
local function Final(reason)
    local N = R.Nav
    finalToken = finalToken + 1
    local token = finalToken
    Say(N.MESSAGES[reason], reason == "arrived" and "Route complete." or "Place a pin and choose Route to your map pin to plan again.",
        "walk", false)
    C_Timer.After(FINAL_HOLD, function()
        if token == finalToken and not (R.Nav and R.Nav.Current()) then HideStrip() end
    end)
end

local function OnJourney(event, reason)
    if not R:Enabled("navigation") then return end
    if event == "ended" then
        ShowArrow(false)
        shown.key = nil
        if FINAL[reason] then Final(reason) else finalToken = finalToken + 1; HideStrip() end
        return
    end
    UpdateStrip()
    ShowArrow(R:Enabled("navigationArrow"))
end

---------------------------------------------------------------------------
-- Moving them in Edit Mode, as the friend login card does.
---------------------------------------------------------------------------
local function SavePlace(key, frame, x, y)
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui[key] = x and { x = x, y = y } or nil
    local place = key == "navStripPlace" and PlaceStrip or PlaceArrow
    place(frame)
    if key == "navStripPlace" and strip then PlaceStrip(strip) end
    if key == "navArrowPlace" and arrow then PlaceArrow(arrow) end
end

local function BuildMover(key, label, tip, w, h)
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetSize(w, h)
    m:SetFrameStrata("MEDIUM")
    m:SetFrameLevel(1000)
    m:SetClampedToScreen(true)
    m:SetMovable(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    if m.SetDontSavePosition then m:SetDontSavePosition(true) end
    m:Hide()
    local fill = m:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MOVER_ATLAS) then
        fill:SetAtlas(MOVER_ATLAS)
    else
        local c = K().bronze
        fill:SetColorTexture(c[1], c[2], c[3], 0.35)
    end
    local text = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
    text:SetText(label)
    m:SetScript("OnDragStart", function(self) self:StartMoving() end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, bottom = self:GetLeft(), self:GetBottom()
        if not (left and bottom) then SavePlace(key, self, nil) return end
        SavePlace(key, self, math.floor(left + 0.5), math.floor(bottom + 0.5))
    end)
    m:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then SavePlace(key, self, nil) end
    end)
    m:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("TwichUI: " .. label, 1, 1, 1)
        GameTooltip:AddLine(tip .. " Drag to move it; right-click to put it back.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function(self) if R.Interact then R.Interact.HideTip(self) end end)
    m:HookScript("OnHide", function(self) if R.Interact then R.Interact.HideTip(self) end end)
    return m
end

local function EditModeActive()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

local function ShowMovers(on)
    on = on and R:Enabled("navigation")
    if on then
        if not movers.strip then
            movers.strip = BuildMover("navStripPlace", "Navigation", "Where the next step of a route is shown.", STRIP_W, STRIP_H)
            movers.arrow = BuildMover("navArrowPlace", "Navigation arrow", "Where the direction arrow is shown.", ARROW_SIZE, ARROW_SIZE + 14)
        end
        PlaceStrip(movers.strip)
        movers.strip:Show()
        if R:Enabled("navigationArrow") then
            PlaceArrow(movers.arrow)
            movers.arrow:Show()
        else
            movers.arrow:Hide()
        end
    else
        for _, m in pairs(movers) do m:StopMovingOrSizing(); m:Hide() end
    end
end

local function HookEditMode()
    if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    editHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function() ShowMovers(true) end, G)
    EventRegistry:RegisterCallback("EditMode.Exit", function() ShowMovers(false) end, G)
end

-- Shows what the active route needs, and nothing while navigation is off. Safe to call any number of times.
function G.Refresh()
    HookEditMode()
    local on = R:Enabled("navigation")
    local active = on and R.Nav and R.Nav.Current()
    if active then
        shown.key = nil
        UpdateStrip()
        ShowArrow(R:Enabled("navigationArrow"))
    else
        finalToken = finalToken + 1
        HideStrip()
        ShowArrow(false)
    end
    ShowMovers(on and EditModeActive())
end

function G.Snapshot()
    return { strip = strip ~= nil and strip:IsShown() or false, arrow = arrow ~= nil and arrow:IsShown() or false,
        arrowUpdating = arrow ~= nil and arrow:GetScript("OnUpdate") ~= nil, movers = movers.strip ~= nil and movers.strip:IsShown() or false }
end

if R.Nav then R.Nav.OnChange(OnJourney) end
