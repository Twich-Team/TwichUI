-- TwichUI: RestedXP timer bars
-- A TwichUI look for the bars RestedXP shows for waits, flights and the like, as a finish on top of the
-- RestedXP skin (modules/RestedXPSkin.lua). It starts nothing and counts nothing: RestedXP starts the bar,
-- runs its countdown and ends it exactly as before. This only changes how a running bar is drawn.
--
-- What the bars are (RXPGuides v4.11.22, Timers.lua and libs/LibCandyBar-3.0):
--   * Every RestedXP timer goes through one function, addon.StartTimer(duration, label): the guide steps'
--     waits (element.timer / timerText), the flight timer (PLAYER_CONTROL_LOST), Hearthstone batching. It
--     takes a bar from its own pool (LibCandyBar bars, made once and reused), sets the label, duration,
--     colour, icon and height, and starts it. LibCandyBar runs the countdown from its own animation.
--   * A bar's parts: candyBarBar (a StatusBar: the fill), candyBarBackground (a texture), candyBarLabel and
--     candyBarDuration (strings), candyBarIconFrame (a texture, RestedXP's pocket watch) and
--     candyBarBackdrop (a frame the library provides for stylers to draw a background and border on).
--     There is no spark.
--
-- How it works:
--   * One hook on addon.StartTimer (and one on addon.ShowTimers, which shows bars RestedXP hid): the bar it
--     just started or reused is styled. Nothing runs per tick, and the library's update is not touched.
--   * The look is drawn once per start and again when a setting changes (coalesced into one update). The
--     fill's colour (RestedXP resets it at every start) and the icon are put right again at each start; the
--     rest only when a setting changed.
--   * Bar height is RestedXP's own BarContainer.height, which its layout reads (StartTimer, SortTimers), so
--     its stacking, anchoring and footer behaviour stay its own; its SortTimers is run once after a change.
--   * Width is not offered: the bars take the width of the footer they hang from, and that is the window's.
--   * What was changed on a bar is remembered once per pooled bar (a snapshot taken when this first drew on
--     it) and put back when the bar stops (LibCandyBar's stop callback: the library keeps stopped bars in a
--     cache shared with every other addon's bars, so one must not leave carrying this look), and when the
--     look is turned off. Colour and height are never restored from a snapshot: they are read from RestedXP
--     as they are then, so a newer RestedXP setting wins.
--   * Active only while the RestedXP skin is (its theme selected, no other skin, not the v2 window) and
--     "Skin timer bars" is on. Nothing is drawn in combat; the latest request waits for it to end.
--
-- Saved: TwichUIDB.ui.restedxpTimerLook (background and border: MenuStyle's) and
-- TwichUIDB.ui.restedxpTimerText (the switch, fill, text, height and padding, icon; only values the player
-- changed are saved). Frames, fonts and media files are never saved.

local R = TwichUI
local Perf = R.Perf
local Skin = R.RestedXPSkin
if not Skin then return end

local T = {}
Skin.Timers = T

local MS = R.MenuStyle
local WHITE = [[Interface\Buttons\WHITE8x8]]
local PREVIEW_ICON = [[Interface\Icons\INV_Misc_PocketWatch_02]]
local LIB, STOP = "LibCandyBar-3.0", "LibCandyBar_Stop"
local DEBOUNCE = 0.2
local GAP = 6   -- between the label and the remaining time

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local LOOK_DEFAULTS = {
    bgTexture = "solid", bgColor = "ff17110b", bgOpacity = 85,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 90, borderSize = 1,
}
local DEFAULTS = {
    skinTimers = true,
    -- fill: "default" is RestedXP's own bar texture; the gradient runs from the first colour (left or
    -- bottom) to the second (a burnished bronze to a muted antique gold)
    fillTexture = "solid", fillColor = "ff80502d", fillColor2 = "ffc69a52", fillGradient = "horizontal",
    fillOpacity = 100,
    -- text: "inherit" is the guide's step text font (label) or the label's own (remaining time)
    labelFont = "inherit", labelOutline = "outline", labelSize = 10, labelColor = "ffe9e1cf",
    timeFont = "inherit", timeOutline = "inherit", timeSize = 10, timeColor = "ffe9e1cf",
    -- the bar's own height (RestedXP's is 16; a larger text makes it as tall as the text needs), the room
    -- left and right of the text, and RestedXP's pocket watch icon (a decoration)
    barHeight = 16, textPadding = 4, showIcon = false,
}
local LIMITS = {
    fillOpacity = { 20, 100 }, labelSize = { 8, 18 }, timeSize = { 8, 18 },
    barHeight = { 12, 28 }, textPadding = { 0, 12 },
}
local OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local GRADIENTS = { none = true, horizontal = "HORIZONTAL", vertical = "VERTICAL" }
local FLAGS = { skinTimers = true, showIcon = true }
local COLORS = { fillColor = true, fillColor2 = true, labelColor = true, timeColor = true }

T.OUTLINE_CHOICES = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" } }
T.TIME_OUTLINE_CHOICES = {
    { "inherit", "Same as the label" }, { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" },
}
T.GRADIENT_CHOICES = {
    { "horizontal", "Left to right" }, { "vertical", "Bottom to top" }, { "none", "None (one color)" },
}

local Look = MS.New("restedxpTimerLook", LOOK_DEFAULTS)
T.Look = Look

local function Valid(key, value)
    local limit = LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif key == "fillTexture" or key == "labelFont" or key == "timeFont" then return R.Borders.ValidName(value)
    elseif key == "labelOutline" then return type(value) == "string" and OUTLINES[value] ~= nil
    elseif key == "timeOutline" then return value == "inherit" or (type(value) == "string" and OUTLINES[value] ~= nil)
    elseif key == "fillGradient" then return type(value) == "string" and GRADIENTS[value] ~= nil
    elseif COLORS[key] then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif FLAGS[key] then return type(value) == "boolean" end
    return false
end

local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    local saved = ui and ui.restedxpTimerText
    return type(saved) == "table" and saved or nil
end

local Opt = { DEFAULTS = DEFAULTS, LIMITS = LIMITS }
T.Opt = Opt

function Opt.Get(key)
    local saved = Saved()
    local value = saved and saved[key]
    if Valid(key, value) then return value end
    return DEFAULTS[key]
end

---------------------------------------------------------------------------
-- Runtime state. Nothing here is saved.
---------------------------------------------------------------------------
local rev = 0                       -- bumped when a setting or the media changes
local recs = setmetatable({}, { __mode = "k" })   -- bar -> { what this drew on it, and what was there }
local want = {}                     -- the settings, resolved; read again only when rev has moved
local wantRev = -1
local hooks = { start = false, show = false }
local installed = false             -- registered for the stop callback and the scale event
local scheduled = false
local waiting = false               -- a pass is waiting for combat to end
local heightOrig, heightSet         -- RestedXP's bar height before this changed it; what this set
local fallback = {}                 -- fill / label / time -> true while a saved media file could not be used
local stats = { styled = 0, restored = 0, refreshes = 0, gradientFallbacks = 0 }
local preview, previewRecs          -- the settings preview: its frames, and its own records (never recs)
local WHITE_COLOR                   -- a neutral gradient, to clear one

---------------------------------------------------------------------------
-- RestedXP's side
---------------------------------------------------------------------------
-- RestedXP's bar container and addon object when this version has what is used here (Timers.lua).
local function Container()
    local rxp = Skin.Addon()
    local window = rawget(_G, "RXPFrame")
    local c = window and window.BarContainer
    if type(rxp) == "table" and type(c) == "table" and type(c.bars) == "table"
        and type(rxp.StartTimer) == "function" and type(rxp.SortTimers) == "function" then
        return c, rxp
    end
end

local function Applies()
    return Opt.Get("skinTimers") and Skin.Active() and Container() ~= nil
end

---------------------------------------------------------------------------
-- What is wanted, resolved once per change
---------------------------------------------------------------------------
-- A line of text needs about 1.25 times its size to show without its descenders clipped.
local function Need(size) return math.ceil(size * 1.25) + 2 end

local function Wants()
    if wantRev == rev then return end
    wantRev = rev
    local br, bg, bb = Look.ParseColor(Opt.Get("fillColor"))
    local er, eg, eb = Look.ParseColor(Opt.Get("fillColor2"))
    local alpha = Opt.Get("fillOpacity") / 100
    want.r1, want.g1, want.b1, want.r2, want.g2, want.b2, want.alpha = br, bg, bb, er, eg, eb, alpha
    local orient = GRADIENTS[Opt.Get("fillGradient")]
    want.average = false
    if type(orient) == "string" and type(_G.CreateColor) == "function" then
        want.orient = orient
        want.minColor = CreateColor(br, bg, bb, alpha)   -- the left or the bottom
        want.maxColor = CreateColor(er, eg, eb, alpha)
    else
        want.orient, want.minColor, want.maxColor = nil, nil, nil
        want.average = type(orient) == "string"   -- shading asked for, no way to draw it: between the two
    end
    local file, state = MS.StatusBars.Resolve(Opt.Get("fillTexture"))
    if Opt.Get("fillTexture") == "default" then file, state = nil, "ok" end
    want.fillFile = file
    fallback.fill = state == "missing" or nil

    local body = Skin.BodyFont()
    local labelPath, labelState = MS.Fonts.Resolve(Opt.Get("labelFont"), body)
    fallback.label = labelState == "missing" or nil
    local timePath, timeState = labelPath, "default"
    if Opt.Get("timeFont") ~= "inherit" then timePath, timeState = MS.Fonts.Resolve(Opt.Get("timeFont"), labelPath) end
    fallback.time = timeState == "missing" or nil
    want.labelPath, want.timePath = labelPath, timePath
    want.labelFlags = OUTLINES[Opt.Get("labelOutline")]
    local timeOutline = Opt.Get("timeOutline")
    want.timeFlags = timeOutline == "inherit" and want.labelFlags or OUTLINES[timeOutline]
    want.labelSize, want.timeSize = Opt.Get("labelSize"), Opt.Get("timeSize")
    want.lr, want.lg, want.lb = Look.ParseColor(Opt.Get("labelColor"))
    want.tr, want.tg, want.tb = Look.ParseColor(Opt.Get("timeColor"))

    want.pad = Opt.Get("textPadding")
    want.showIcon = Opt.Get("showIcon")
    -- never shorter than the larger text needs, so a big font is not clipped
    want.height = math.max(Opt.Get("barHeight"), Need(math.max(want.labelSize, want.timeSize)))
end

---------------------------------------------------------------------------
-- Drawing on one bar. A bar is a LibCandyBar bar (or the preview's own, which has the same parts).
---------------------------------------------------------------------------
local function Parts(bar)
    local sb, bg, label, time = bar.candyBarBar, bar.candyBarBackground, bar.candyBarLabel, bar.candyBarDuration
    if sb and bg and label and time and sb.GetStatusBarTexture and label.GetFont and time.GetFont then
        return sb, bg, label, time
    end
end

local function SavePoints(region, out)
    local n = region:GetNumPoints() or 0
    out.n = n
    for i = 1, n do
        local p = out[i]
        if not p then p = {}; out[i] = p end
        p[1], p[2], p[3], p[4], p[5] = region:GetPoint(i)
    end
end

local function LoadPoints(region, saved)
    if not (saved and saved.n and saved.n > 0) then return end
    region:ClearAllPoints()
    for i = 1, saved.n do
        local p = saved[i]
        region:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
end

local function SaveFont(fs, out)
    local file, size, flags = fs:GetFont()
    out.file, out.size, out.flags = file, size, flags or ""
    out.r, out.g, out.b, out.a = fs:GetTextColor()
end

-- A snapshot of what a bar shows before this draws on it. A record is made once per bar (the pool is
-- small) and written over each time, so starting a timer does not allocate.
local function Capture(bar, rec, sb, bg, label, time)
    local tex = sb:GetStatusBarTexture()
    rec.file = tex and tex:GetTexture() or nil
    rec.bgR, rec.bgG, rec.bgB, rec.bgA = bg:GetVertexColor()
    rec.label = rec.label or { pts = {} }
    rec.time = rec.time or { pts = {} }
    SaveFont(label, rec.label)
    SaveFont(time, rec.time)
    SavePoints(label, rec.label.pts)
    SavePoints(time, rec.time.pts)
    local c = Container()
    rec.icon = bar.GetIcon and bar:GetIcon() or (c and c.barIcon) or nil
    rec.appliedFile, rec.gradient, rec.edge, rec.pad = nil, false, nil, nil
end

-- Face, size and outline of a string; only what differs is set.
local function StyleFont(fs, path, size, flags)
    local file, current, outline = fs:GetFont()
    if not (file and current) then return end
    if file ~= path or current ~= size or (outline or "") ~= flags then
        fs:SetFont(path, size, flags)
    end
end

local function Fill(rec, sb)
    local file = want.fillFile or rec.file
    if file ~= nil and rec.appliedFile ~= file then
        if sb:SetStatusBarTexture(file) ~= false then rec.appliedFile = file end
    end
    local tex = sb:GetStatusBarTexture()
    -- A gradient and a colour both live in the texture's vertex colours, so they are set in an order that
    -- gives the same result whichever of the two the client lets win: the colour neutral, the gradient
    -- last, and the opacity carried by the gradient's own colours.
    if want.orient and tex and tex.SetGradient then
        sb:SetStatusBarColor(1, 1, 1, 1)
        if pcall(tex.SetGradient, tex, want.orient, want.minColor, want.maxColor) then
            rec.gradient = true
            return
        end
        stats.gradientFallbacks = stats.gradientFallbacks + 1
        sb:SetStatusBarColor((want.r1 + want.r2) / 2, (want.g1 + want.g2) / 2, (want.b1 + want.b2) / 2, want.alpha)
        return
    end
    if rec.gradient and tex and tex.SetGradient and WHITE_COLOR then
        pcall(tex.SetGradient, tex, "HORIZONTAL", WHITE_COLOR, WHITE_COLOR)
        rec.gradient = false
    end
    if want.average then
        sb:SetStatusBarColor((want.r1 + want.r2) / 2, (want.g1 + want.g2) / 2, (want.b1 + want.b2) / 2, want.alpha)
    else
        sb:SetStatusBarColor(want.r1, want.g1, want.b1, want.alpha)
    end
end

-- The background and border: the library's own frame for stylers (or one of ours when this version of
-- the library has none), drawn with the shared look, just under the fill and just outside the bar's
-- edge, so the border never covers the fill.
local function Backdrop(bar, rec, sb)
    local bd = bar.candyBarBackdrop
    if not (bd and bd.SetBackdrop) then
        bd = rec.own
        if not bd then
            bd = CreateFrame("Frame", nil, bar, "BackdropTemplate")
            rec.own = bd
        end
    end
    rec.bd = bd
    local level = math.max(0, (sb:GetFrameLevel() or 1) - 1)
    if bd:GetFrameLevel() ~= level then bd:SetFrameLevel(level) end
    local edge = Look.Apply(bd)
    -- the highlight and shade lines of a plain border are clutter on a bar this thin
    local bevel = bd.twichBevel
    if bevel then
        if bevel.top then bevel.top:Hide() end
        if bevel.bottom then bevel.bottom:Hide() end
    end
    if rec.edge ~= edge or bd:GetNumPoints() ~= 2 then
        bd:ClearAllPoints()
        bd:SetPoint("TOPLEFT", bar, "TOPLEFT", -edge, edge)
        bd:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", edge, -edge)
        rec.edge = edge
    end
    if not bd:IsShown() then bd:Show() end
end

-- Label at the left, remaining time at the right, and the label stops short of the time and is cut with
-- an ellipsis rather than running into it or wrapping past the bar's height.
local function Text(rec, sb, label, time)
    StyleFont(label, want.labelPath, want.labelSize, want.labelFlags)
    StyleFont(time, want.timePath, want.timeSize, want.timeFlags)
    label:SetTextColor(want.lr, want.lg, want.lb, 1)
    time:SetTextColor(want.tr, want.tg, want.tb, 1)
    label:SetWordWrap(false)
    time:SetWordWrap(false)
    if rec.pad ~= want.pad then
        local pad = want.pad
        time:ClearAllPoints()
        time:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -pad, 0)
        time:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -pad, 0)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", sb, "TOPLEFT", pad, 0)
        label:SetPoint("BOTTOMRIGHT", time, "BOTTOMLEFT", -GAP, 0)
        rec.pad = pad
    end
end

-- Icon: with none the library gives its room to the bar (SetIcon(nil), its own way), and RestedXP's next
-- start sets its pocket watch again, which is why this runs at every start.
local function Icon(bar, rec)
    if not (bar.GetIcon and bar.SetIcon) then return end
    local has = bar:GetIcon() ~= nil
    if want.showIcon then
        if not has and rec.icon then bar:SetIcon(rec.icon) end
    elseif has then
        bar:SetIcon(nil)
    end
end

-- forced: RestedXP has just started the bar and reset its colour and icon, so those are drawn again;
-- otherwise a bar that is already drawn for the current settings is left alone.
local function Paint(bar, rec, forced)
    local sb, bg, label, time = Parts(bar)
    if not sb then return false end
    if rec.on and rec.rev == rev and not forced then return true end
    if not rec.on then
        Capture(bar, rec, sb, bg, label, time)
        rec.on = true
        rec.rev = -1
        stats.styled = stats.styled + 1
    end
    rec.stopped = nil
    Fill(rec, sb)
    Icon(bar, rec)
    -- A start draws the text again whatever was drawn before: the library gives a bar its font, colours and
    -- background strength afresh each time it makes one (and RestedXP's pool and the library's cache are
    -- not kept apart, so a bar that was drawn can be made again). Faces and colours are compared first, so
    -- an unchanged bar is not touched.
    if forced or rec.rev ~= rev then
        if bar.SetBackgroundColor then bar:SetBackgroundColor(0, 0, 0, 0) end   -- the backdrop is the background now
        Text(rec, sb, label, time)
    end
    if rec.rev ~= rev then Backdrop(bar, rec, sb) end
    rec.rev = rev
    return true
end

-- Puts back what Capture saw, and what RestedXP itself would have. The countdown, the fill's value, the
-- label and the bar's visibility are never touched.
local function Unpaint(bar, rec)
    local sb, _, label, time = Parts(bar)
    rec.on = false
    rec.stopped = nil
    stats.restored = stats.restored + 1
    if not sb then return end
    local tex = sb:GetStatusBarTexture()
    if rec.appliedFile ~= nil and rec.file ~= nil then sb:SetStatusBarTexture(rec.file) end
    rec.appliedFile = nil
    if rec.gradient and tex and tex.SetGradient and WHITE_COLOR then
        pcall(tex.SetGradient, tex, "HORIZONTAL", WHITE_COLOR, WHITE_COLOR)
    end
    rec.gradient = false
    -- RestedXP sets the fill's colour from its theme at every start: read as it is now
    local rxp = Skin.Addon()
    local pins = type(rxp) == "table" and type(rxp.colors) == "table" and rxp.colors.mapPins
    if type(pins) == "table" and pins[1] then sb:SetStatusBarColor(unpack(pins)) end
    if rec.bgR and bar.SetBackgroundColor then bar:SetBackgroundColor(rec.bgR, rec.bgG, rec.bgB, rec.bgA) end
    for _, part in ipairs({ { label, rec.label }, { time, rec.time } }) do
        local fs, saved = part[1], part[2]
        if saved and saved.file and saved.size then fs:SetFont(saved.file, saved.size, saved.flags) end
        if saved and saved.r then fs:SetTextColor(saved.r, saved.g, saved.b, saved.a or 1) end
        fs:SetWordWrap(true)
        if saved then LoadPoints(fs, saved.pts) end
    end
    rec.pad = nil
    if rec.icon and bar.GetIcon and bar:GetIcon() == nil then bar:SetIcon(rec.icon) end
    local bd = rec.bd
    if bd then
        if bd.ClearBackdrop then bd:ClearBackdrop() end
        if bd.twichBorders then R.Borders.Hide(bd.twichBorders) end
        local bevel = bd.twichBevel
        if bevel then
            if bevel.top then bevel.top:Hide() end
            if bevel.bottom then bevel.bottom:Hide() end
        end
        bd:ClearAllPoints()
        bd:Hide()
    end
    rec.edge = nil
end

---------------------------------------------------------------------------
-- Height: RestedXP's own field, read by its layout
---------------------------------------------------------------------------
local function ApplyHeight(on)
    local c, rxp = Container()
    if not c then return end
    local relayout = false
    if on then
        if heightSet == nil or c.height ~= heightSet then heightOrig = c.height end   -- RestedXP's, as it is now
        if c.height ~= want.height then
            c.height = want.height
            relayout = true
        end
        heightSet = want.height
    elseif heightSet ~= nil then
        if c.height == heightSet and heightOrig then   -- not changed by RestedXP meanwhile
            c.height = heightOrig
            relayout = true
        end
        heightSet = nil
    end
    -- its own re-layout (bar heights, stacking, the container): run only when there is a bar to lay out
    if relayout and next(c.bars) ~= nil then pcall(rxp.SortTimers, rxp) end
end

local function RestoreAll()
    for bar, rec in pairs(recs) do
        if rec.on then Unpaint(bar, rec) end
    end
    ApplyHeight(false)
end

---------------------------------------------------------------------------
-- Keeping bars in step
---------------------------------------------------------------------------
local OnRegen

-- Draws every running bar (and every one this has drawn on) for the current settings, or gives them back.
function T.Refresh()
    -- the sample bars are frames of ours, not RestedXP's: they follow a change at once, in combat or not
    if preview and preview.frame:IsShown() then T.PaintPreview() end
    if InCombatLockdown() then
        if not waiting then
            waiting = true
            R:On("PLAYER_REGEN_ENABLED", OnRegen)
        end
        return
    end
    stats.refreshes = stats.refreshes + 1
    if not Applies() then
        RestoreAll()
        return
    end
    Wants()
    ApplyHeight(true)
    local c = Container()
    for _, bar in pairs(c.bars) do
        Paint(bar, recs[bar] or T.NewRec(bar))
    end
    for bar, rec in pairs(recs) do
        if rec.on and rec.rev ~= rev then Paint(bar, rec) end
    end
end

function T.NewRec(bar)
    local rec = { on = false, rev = -1 }
    recs[bar] = rec
    return rec
end

function OnRegen()
    R:Off("PLAYER_REGEN_ENABLED", OnRegen)
    waiting = false
    for bar, rec in pairs(recs) do
        if rec.stopped and rec.on then Unpaint(bar, rec) end
    end
    T.Refresh()
end

local function Flush()
    scheduled = false
    T.Refresh()
end

-- A setting or the media changed: one update, a moment from now.
local function Changed()
    rev = rev + 1
    if scheduled then return end
    scheduled = true
    C_Timer.After(DEBOUNCE, Flush)
end

function Opt.Set(key, value)
    if DEFAULTS[key] == nil or not Valid(key, value) then return false end
    TwichUIDB.ui = TwichUIDB.ui or {}
    if type(TwichUIDB.ui.restedxpTimerText) ~= "table" then TwichUIDB.ui.restedxpTimerText = {} end
    if TwichUIDB.ui.restedxpTimerText[key] == value then return true end   -- unchanged: nothing to redraw
    TwichUIDB.ui.restedxpTimerText[key] = value
    Changed()
    return true
end

-- The timer bars' whole look back to the defaults (the switch included). Nothing else is touched.
function T.Reset()
    if TwichUIDB and TwichUIDB.ui then TwichUIDB.ui.restedxpTimerText = nil end
    Look.Reset()   -- notifies, which comes back to Changed
    Changed()
end

Look.Subscribe(Changed)
R.Profiles.OnApply("look", "restedxp-timers", Changed)   -- a profile change: one update
MS.StatusBars.Subscribe(function() if fallback.fill then Changed() end end)
MS.Fonts.Subscribe(function() if fallback.label or fallback.time then Changed() end end)

-- Choices for the settings page (read when a list is opened).
function T.FillChoices(current)
    return MS.StatusBars.Choices(current, { { "default", "RestedXP's own texture" } })
end
function T.LabelFontChoices(current)
    return MS.Fonts.Choices(current, { { "inherit", "Same as the guide's step text" } })
end
function T.TimeFontChoices(current)
    return MS.Fonts.Choices(current, { { "inherit", "Same as the label" } })
end

---------------------------------------------------------------------------
-- Hooks. RestedXP's StartTimer is the one place a bar is started or reused.
---------------------------------------------------------------------------
-- RestedXP has started (or restarted) a bar: its label is the key RestedXP keeps it under.
local function OnStart(_, label)
    local c = Container()
    local bar = c and c.bars[label or ""]
    if not bar then return end
    if InCombatLockdown() then
        if not waiting then
            waiting = true
            R:On("PLAYER_REGEN_ENABLED", OnRegen)
        end
        return
    end
    if not Applies() then
        if next(recs) ~= nil then RestoreAll() end   -- the skin has gone since: leave no bar drawn
        return
    end
    Wants()
    ApplyHeight(true)
    Paint(bar, recs[bar] or T.NewRec(bar), true)
end

-- RestedXP showed bars it had hidden (its window was shown again): they keep what was drawn, but a
-- setting may have changed, or the skin come on, meanwhile.
local function OnShow()
    if Skin.Active() then T.Refresh() end
end

-- A bar is stopped: the library puts it in a cache every addon's bars share, so it goes back as it was.
local function OnBarStop(_, bar)
    local rec = recs[bar]
    if not (rec and rec.on) then return end
    if InCombatLockdown() then
        rec.stopped = true   -- put back when combat ends
        if not waiting then
            waiting = true
            R:On("PLAYER_REGEN_ENABLED", OnRegen)
        end
        return
    end
    Unpaint(bar, rec)
end

local function OnScale() Changed() end

local extension = {}

function extension.install()
    local c, rxp = Container()
    if not c then return end
    if not hooks.start then
        hooks.start = true
        hooksecurefunc(rxp, "StartTimer", Perf.Wrap("rxp.timers.start", OnStart))
    end
    if not hooks.show and type(rxp.ShowTimers) == "function" then
        hooks.show = true
        hooksecurefunc(rxp, "ShowTimers", Perf.Wrap("rxp.timers.show", OnShow))
    end
    if not installed then
        installed = true
        local lib = LibStub and LibStub(LIB, true)
        if lib and type(lib.RegisterCallback) == "function" then lib.RegisterCallback(T, STOP, OnBarStop) end
        R:On("UI_SCALE_CHANGED", OnScale)
    end
    if not WHITE_COLOR and type(_G.CreateColor) == "function" then WHITE_COLOR = CreateColor(1, 1, 1, 1) end
end

function extension.finished()
    if next(recs) ~= nil or (Container() and next(Container().bars) ~= nil) then T.Refresh() end
end

function extension.stripped()
    if InCombatLockdown() then T.Refresh() return end
    RestoreAll()
end

function extension.disabled()
    if installed then
        installed = false
        local lib = LibStub and LibStub(LIB, true)
        if lib and type(lib.UnregisterCallback) == "function" then lib.UnregisterCallback(T, STOP) end
        R:Off("UI_SCALE_CHANGED", OnScale)
    end
    T.HidePreview()
    if InCombatLockdown() then
        for _, rec in pairs(recs) do if rec.on then rec.stopped = true end end
        if not waiting then
            waiting = true
            R:On("PLAYER_REGEN_ENABLED", OnRegen)
        end
    else
        RestoreAll()
    end
end

Skin.Extend(extension)

---------------------------------------------------------------------------
-- The preview: two synthetic bars on frames of their own, drawn by the same code as a real one. They are
-- not RestedXP's bars and not LibCandyBar's (a library bar made here would be taken out of the cache the
-- other addons' bars share), run no countdown and start no timer.
---------------------------------------------------------------------------
local PREVIEW_WIDTH = 300
local SAMPLES = {
    { label = "Boat to Auberdine", time = "2:14", value = 0.65 },
    { label = "Waiting for the speaker to finish what they are saying to the crowd", time = "0:09", value = 0.3 },
}

-- A bar-shaped frame with the parts and the few methods the drawing code uses, as the library lays them out.
local function MakeSampleBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetPoint("TOPLEFT")
    bar.icon:SetPoint("BOTTOMLEFT")
    local sb = CreateFrame("StatusBar", nil, bar)
    sb:SetMinMaxValues(0, 1)
    bar.candyBarBar = sb
    bar.candyBarBackground = sb:CreateTexture(nil, "BACKGROUND")
    bar.candyBarBackground:SetAllPoints()
    bar.candyBarBackdrop = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.candyBarDuration = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    bar.candyBarLabel = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    bar.candyBarLabel:SetJustifyH("LEFT")
    bar.candyBarDuration:SetJustifyH("RIGHT")
    sb:SetStatusBarTexture(WHITE)
    function bar:GetIcon() return self.iconFile end
    function bar:SetBackgroundColor(...) self.candyBarBackground:SetVertexColor(...) end
    function bar:SetIcon(file)
        self.iconFile = file
        self.icon:SetTexture(file)
        self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        self.icon:SetWidth(self:GetHeight())
        self.icon:SetShown(file ~= nil)
        sb:ClearAllPoints()
        if file then sb:SetPoint("TOPLEFT", self.icon, "TOPRIGHT") else sb:SetPoint("TOPLEFT", self) end
        sb:SetPoint("BOTTOMRIGHT", self)
    end
    return bar
end

local function BuildPreview()
    if preview then return end
    local frame = CreateFrame("Frame", "TwichUIRXPTimerPreview", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetSize(PREVIEW_WIDTH, 60)
    frame:Hide()
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4)
    title:SetText("Timer bar preview (not a real timer)")
    preview = { frame = frame, bars = {} }
    previewRecs = {}
    for i = 1, #SAMPLES do
        local bar = MakeSampleBar(frame)
        preview.bars[i] = bar
        previewRecs[bar] = { on = false, rev = -1 }
    end
    if _G.UISpecialFrames then table.insert(_G.UISpecialFrames, "TwichUIRXPTimerPreview") end
end
R.OnSettingsClosed(function() T.HidePreview() end)   -- the sample goes away with the settings window

-- The real drawing code on the samples, with the settings as they are now (whether or not the RestedXP skin
-- is drawing: the preview shows what a timer bar would look like).
function T.PaintPreview()
    if not preview then return end
    Wants()
    local y = 0
    for i, sample in ipairs(SAMPLES) do
        local bar = preview.bars[i]
        local rec = previewRecs[bar]
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", preview.frame, "TOPLEFT", 0, -y)
        bar:SetPoint("TOPRIGHT", preview.frame, "TOPRIGHT", 0, -y)
        bar:SetHeight(want.height)
        bar:SetIcon(PREVIEW_ICON)
        bar.candyBarLabel:SetText(sample.label)
        bar.candyBarDuration:SetText(sample.time)
        bar.candyBarBar:SetValue(sample.value)
        rec.icon = PREVIEW_ICON
        Paint(bar, rec, true)
        y = y + want.height + 6
    end
    preview.frame:SetHeight(math.max(1, y - 6))
end

function T.PreviewShown() return preview ~= nil and preview.frame:IsShown() end

function T.HidePreview()
    if not preview then return end
    preview.frame:Hide()
    -- what it drew is put back so a hidden sample holds nothing; the frames are kept for the next time
    for bar, rec in pairs(previewRecs) do
        if rec.on then Unpaint(bar, rec) end
    end
end

-- Shows the sample beside the settings window, or puts it away.
function T.TogglePreview()
    if T.PreviewShown() then T.HidePreview() return end
    BuildPreview()
    T.PaintPreview()
    local frame = preview.frame
    frame:ClearAllPoints()
    local panel = R.SettingsAnchor()
    if panel then
        frame:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, -64)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:Show()
end

---------------------------------------------------------------------------
-- What it is doing, for the settings page and the troubleshooting report. Words and counts only.
---------------------------------------------------------------------------
-- Codes: off (the timer switch), skin-off (the RestedXP skin isn't drawing), unsupported (this RestedXP
-- has no timer bars this can draw), active.
function T.Status()
    local s = { switchOn = Opt.Get("skinTimers"), skinActive = Skin.Active() and true or false }
    s.supported = Container() ~= nil
    local code
    if not s.switchOn then code = "off"
    elseif not s.skinActive then code = "skin-off"
    elseif not s.supported then code = "unsupported"
    else code = "active" end
    s.code = code
    return s
end

function T.Snapshot()
    local s = T.Status()
    local drawn, known = 0, 0
    for _, rec in pairs(recs) do
        known = known + 1
        if rec.on then drawn = drawn + 1 end
    end
    s.hookStart, s.hookShow, s.stopCallback = hooks.start, hooks.show, installed
    s.bars, s.drawn = known, drawn
    s.styled, s.restored, s.refreshes = stats.styled, stats.restored, stats.refreshes
    s.gradientFallbacks = stats.gradientFallbacks
    s.fallbackFill, s.fallbackLabel, s.fallbackTime = fallback.fill, fallback.label, fallback.time
    s.waiting, s.scheduled = waiting, scheduled
    s.heightChanged = heightSet ~= nil
    s.previewShown = T.PreviewShown()
    return s
end
