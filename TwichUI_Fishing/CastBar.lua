-- TwichUI Fishing: the fishing cast bar (Stage 2)
-- A compact walnut-and-bronze bar near the bottom of the screen (tools/make_fishing_art.py: castbar, castfill, castspark) with
-- the line's timer, and a line of session figures and prompts under it. Shown by Fishing Mode in its immersive and compact
-- presentations (Present.lua).
--
-- States, from the game's own events only:
--   idle         Fishing Mode is on and no line is out: "Ready to cast" and the key that casts
--   casting      the cast was sent (UNIT_SPELLCAST_SENT with a Fishing spell) and the line is not out yet
--   line         a Fishing channel is active: the fill and the seconds left come from the channel's own start and end times
--                (UnitChannelInfo). They time the line, not a bite: the game gives no bite signal, and none is shown or
--                guessed. With no times to read, the seconds since the cast are counted up and the fill stays empty.
--   caught       the line ended with fishing loot (Stage 1's CATCH)
--   missed, interrupted, failed    Stage 1's CAST_FAILED: nothing on the line, the cast was interrupted, or it was refused
-- A result shows for RESULT seconds, then the bar is idle again.
--
-- Under the bar: the session's length and catches, the lure's time left (Lure.Status, which reads the pole only), and the
-- estimated value only when a valuation is connected (Present.Value: Stage 3; nothing is priced here). The last line is a
-- warning when there is one (gear still to be put back, saved data held by a newer version), otherwise the prompts.
--
-- Work: an OnUpdate exists only while a line is out (the fill, about 30 times a second, and the seconds, ten times a second);
-- a one-second ticker only while the bar is shown; everything else is event driven. Hidden, it does nothing.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local H = F.Hud
local CB = {}
F.CastBar = CB

CB.WIDTH = 360
CB.RESULT = 1.8
local K = CB.WIDTH / H.ART.castbar.cw
local TR = H.ART.castbar.trough
local TROUGH_L, TROUGH_T = TR[1] * K, TR[2] * K
local FILL_W, FILL_H = H.ART.castfill.cw * K, H.ART.castfill.ch * K

local frame, ui
local state, line, resultTimer = "idle", nil, nil
local ticker
CB.updates = 0     -- OnUpdate passes that did work (tests, diagnostics)

local LABEL = {
    idle = "Ready to cast", casting = "Casting\226\128\166", line = "Fishing\226\128\166", caught = "Caught!",
    missed = "Nothing on the line", interrupted = "Interrupted", failed = "Couldn't cast", ending = "Fishing\226\128\166",
}

---------------------------------------------------------------------------
-- Building (once, when first shown)
---------------------------------------------------------------------------
local function Text(parent, size, role, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    H.Font(fs, size, role)
    H.Color(fs, color or H.IVORY)
    return fs
end

local function Build()
    if frame then return frame end
    local f, u
    f = CreateFrame("Frame", "TwichUIFishingCastBar", UIParent)
    f:SetSize(CB.WIDTH, H.ART.castbar.ch * K)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(false)
    f:Hide()
    u = {}
    u.art = f:CreateTexture(nil, "ARTWORK", nil, 0)
    u.art:SetAllPoints()
    H.Texture(u.art, "castbar", { 0.17, 0.11, 0.07, 0.92 })
    u.fill = f:CreateTexture(nil, "ARTWORK", nil, 2)
    u.fill:SetPoint("TOPLEFT", f, "TOPLEFT", TROUGH_L, -TROUGH_T)
    u.fill:SetSize(FILL_W, FILL_H)
    H.Texture(u.fill, "castfill", { 0.80, 0.57, 0.26, 0.95 })
    u.spark = f:CreateTexture(nil, "ARTWORK", nil, 3)
    u.spark:SetSize(FILL_H * 2.4, FILL_H * 2.4)
    u.spark:SetBlendMode("ADD")
    H.Texture(u.spark, "castspark", { 1, 0.86, 0.62, 0.25 })
    u.spark:Hide()
    -- labels sit on the walnut above the trough
    u.label = Text(f, 13, "serif")
    u.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", TROUGH_L + 4, -TROUGH_T + 1)
    u.time = Text(f, 13, "serif")
    u.time:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", TROUGH_L + FILL_W - 4, -TROUGH_T + 1)
    u.time:SetJustifyH("RIGHT")
    u.stats = Text(f, 12, "strong")
    u.stats:SetPoint("TOP", f, "BOTTOM", 0, -3)
    u.note = Text(f, 11, "body", H.SOFT)
    u.note:SetPoint("TOP", u.stats, "BOTTOM", 0, -3)
    -- a faint shade under the two lines, so they read over bright scenery too
    u.shade = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    u.shade:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -30, 14)
    u.shade:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 30, -44)
    H.Texture(u.shade, "scrim", { 0.06, 0.04, 0.03, 0.3 })
    u.shade:SetAlpha(H.SHADE)
    H.Movable(f, "castbar", "BOTTOM")
    H.Place(f, "castbar", "BOTTOM")
    -- kept only once every part exists: a build that fails part-way leaves nothing half-made in use
    frame, ui = f, u
    return frame
end

---------------------------------------------------------------------------
-- The fill
---------------------------------------------------------------------------
local function SetProgress(p)
    if not p then
        ui.fill:Hide(); ui.spark:Hide()
        return
    end
    p = math.max(0, math.min(1, p))
    if p <= 0.004 then ui.fill:Hide(); ui.spark:Hide() return end
    local l, r, t, b = H.Coords("castfill")
    if ui.fill.twichArt then ui.fill:SetTexCoord(l, r * p, t, b) end
    ui.fill:SetWidth(FILL_W * p)
    ui.fill:Show()
    if p < 0.995 then
        ui.spark:ClearAllPoints()
        ui.spark:SetPoint("CENTER", ui.fill, "RIGHT", 0, 0)
        ui.spark:Show()
    else
        ui.spark:Hide()
    end
end

-- The channel's own times (seconds on the GetTime clock), or nil.
local function ChannelTimes()
    if not UnitChannelInfo then return nil end
    local _, _, _, startMS, endMS = UnitChannelInfo("player")
    startMS, endMS = F.Num(startMS), F.Num(endMS)
    if not (startMS and endMS and endMS > startMS) then return nil end
    return startMS / 1000, endMS / 1000
end

local textAcc, fillAcc = 0, 0
local function OnUpdate(_, elapsed)
    if not line then return end
    fillAcc, textAcc = fillAcc + (elapsed or 0), textAcc + (elapsed or 0)
    if fillAcc < 0.033 then return end
    fillAcc = 0
    local pt = R.Perf.on and R.Perf.Start("fishing.castbar")
    CB.updates = CB.updates + 1
    local now = F.Clock()
    if line.stop then
        SetProgress((now - line.start) / (line.stop - line.start))
        if textAcc >= 0.1 then textAcc = 0; ui.time:SetText(("%.1fs"):format(math.max(0, line.stop - now))) end
    else
        SetProgress(nil)
        if textAcc >= 0.1 then textAcc = 0; ui.time:SetText(H.Duration(now - line.start)) end
    end
    if pt then R.Perf.Stop(pt) end
end

local function Animate(on)
    if not frame then return end
    frame:SetScript("OnUpdate", on and OnUpdate or nil)
end

---------------------------------------------------------------------------
-- The lines under the bar
---------------------------------------------------------------------------
local BULLET = "  |cffc79452\226\128\162|r  "

function CB.StatsText()
    local P = F.Present
    if CB.preview then return "42m 17s" .. BULLET .. "56 catches" .. BULLET .. "Lure 23m" end
    local parts = {}
    local s = F.Session.Current()
    if s then
        parts[#parts + 1] = H.Duration(F.Session.Elapsed() or 0)
        parts[#parts + 1] = s.catches == 1 and "1 catch" or (s.catches .. " catches")
        local value = P and P.Value and P.Value("session")
        if value and value.text then parts[#parts + 1] = value.text end
    end
    local lure = F.Lure and F.Lure.Status and F.Lure.Status() or nil
    if lure and (lure.state == "active" or lure.state == "expiring") and lure.seconds then
        parts[#parts + 1] = "Lure " .. (lure.seconds >= 60 and (math.floor(lure.seconds / 60) .. "m") or (math.floor(lure.seconds) .. "s"))
    elseif lure and lure.state == "none" then
        parts[#parts + 1] = "No lure"
    end
    return table.concat(parts, BULLET)
end

-- A warning the player can act on (pending gear, held data), or the prompts. Returns text, isWarning.
function CB.NoteText()
    local key = H.Key(F.Action.BINDING)
    if S.held then return "Your fishing records were saved by a newer TwichUI and are read-only here.", true end
    local g = F.Gear and F.Gear.Status and F.Gear.Status()
    if g and g.state == "pending" then
        return key and ("Your own gear is still to go back on: press " .. key .. ", or type /tui fish restore.")
            or "Your own gear is still to go back on: type /tui fish restore.", true
    end
    if S.Get("present.prompts") == false then return "", false end
    local P = F.Present
    local exit = H.Key(P and P.MODE_BINDING or "")
    local reveal = H.Key(P and P.REVEAL_BINDING or "")
    local parts = {}
    if state == "line" then
        parts[#parts + 1] = key and (key .. " or click the bobber to reel in") or "Click the bobber to reel in"
    elseif not key then
        parts[#parts + 1] = "Bind \"Fishing: the next step\" in Key Bindings > TwichUI"
    else
        parts[#parts + 1] = key .. " to fish"
    end
    if reveal then parts[#parts + 1] = "hold " .. reveal .. " to see your interface" end
    parts[#parts + 1] = exit and (exit .. " to leave") or "/tui fish mode to leave"
    return table.concat(parts, BULLET), false
end

function CB.RefreshLines()
    if not frame then return end
    ui.stats:SetText(CB.StatsText())
    local text, warn = CB.NoteText()
    ui.note:SetText(text)
    H.Color(ui.note, warn and H.WARN or H.SOFT)
end

---------------------------------------------------------------------------
-- States
---------------------------------------------------------------------------
local function Paint()
    if not frame then return end
    ui.label:SetText(LABEL[state] or "")
    H.Color(ui.label, (state == "caught") and H.GOLD or (state == "ending" and H.MUTED) or H.IVORY)
    if state == "line" then
        Animate(true)
    else
        Animate(false)
        if state == "caught" then SetProgress(1); ui.time:SetText("")
        elseif state == "idle" or state == "casting" or state == "failed" then SetProgress(nil); ui.time:SetText("") end
    end
    CB.RefreshLines()
end

local function Result(which)
    state = which
    line = nil
    Paint()
    if resultTimer then resultTimer:Cancel() end
    if C_Timer and C_Timer.NewTimer then
        resultTimer = C_Timer.NewTimer(CB.RESULT, function()
            resultTimer = nil
            if state == which then state = "idle"; Paint() end
        end)
    end
end

function CB.State() return state end

function CB.LineStarted()
    if resultTimer then resultTimer:Cancel(); resultTimer = nil end
    local start, stop = ChannelTimes()
    line = { start = start or F.Clock(), stop = stop }
    state = "line"
    textAcc, fillAcc = 1, 1
    Paint()
    if frame and frame:IsShown() then OnUpdate(frame, 1) end
end

function CB.LineEnded()
    if state ~= "line" then return end
    line = nil
    state = "ending"
    Paint()
    -- no result reported (Stage 1 reports a catch at once and a miss within a second and a half): back to idle
    if C_Timer and C_Timer.After then
        C_Timer.After(2.5, function() if state == "ending" then state = "idle"; Paint() end end)
    end
end

local function OnSent(unit, _, _, spellID)
    if unit ~= "player" or state == "line" then return end
    spellID = F.Num(spellID)
    if spellID and F.FISHING_SPELL[spellID] then state = "casting"; Paint() end
end

F.Subscribe("STATE", function(_, new, old)
    if new == "line" then CB.LineStarted()
    elseif old == "line" then CB.LineEnded() end
end)
F.Subscribe("CATCH", function() Result("caught") end)
F.Subscribe("CAST_FAILED", function(_, kind)
    if kind == "missed" or kind == "interrupted" or kind == "failed" then Result(kind) end
end)
for _, e in ipairs({ "GEAR", "LURE", "SESSION_START", "SESSION_END", "CONFIG" }) do
    F.Subscribe(e, function() if frame and frame:IsShown() then CB.RefreshLines() end end)
end

---------------------------------------------------------------------------
-- Shown and hidden by Present.lua
---------------------------------------------------------------------------
function CB.Show()
    Build()
    H.Place(frame, "castbar", "BOTTOM")
    if F.Action.LineOut() then CB.LineStarted() else
        if state == "line" or state == "ending" then state = "idle" end
        Paint()
    end
    frame:SetAlpha(1)
    frame:Show()
    R:On("UNIT_SPELLCAST_SENT", OnSent)
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, CB.RefreshLines) end
end

function CB.Hide()
    if ticker then ticker:Cancel(); ticker = nil end
    R:Off("UNIT_SPELLCAST_SENT", OnSent)
    if not frame then return end
    Animate(false)
    frame:Hide()
end

function CB.Shown() return frame ~= nil and frame:IsShown() end
function CB.Frame() return frame, ui end

-- Move mode: shown with sample figures so it can be placed; the player's drag saves the place.
function CB.Preview(on)
    CB.preview = on and true or nil
    Build()
    H.SetUnlocked(frame, on)
    if on then
        frame:Show()
        state = "line"
        Animate(false)
        ui.label:SetText(LABEL.line)
        ui.time:SetText("12.4s")
        SetProgress(0.58)
        CB.RefreshLines()
    else
        state = "idle"
        Paint()
    end
end

function CB.Relayout()
    if frame then H.Place(frame, "castbar", "BOTTOM") end
end
