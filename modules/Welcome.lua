-- TwichUI: welcome dialog
-- One short page that says what TwichUI is and where its settings, notification previews and
-- troubleshooting report are. It is shown once, automatically, for a new installation, and any time
-- the player asks (/tui about, or Welcome in the options overview). It changes no setting and enables
-- nothing: its only buttons close it or open TwichUI's options.
--
-- When it appears on its own. Persist.lua writes TwichUIDB.welcome.state = "pending" only when a load
-- found no saved settings at all; every other load leaves it "seen" (see "First run" there). Here:
--   * nothing happens unless the state is "pending";
--   * the dialog waits for the world, and for combat, a flight path, a game banner, a cinematic, a hidden
--     interface and any TwichUI card (Welcome Back, zone, training, friend) to be out of the way. It looks
--     again on world entry and at the end of combat, and on a short timer a bounded number of times;
--     none of that is saved, and a session that gave up simply tries again at the next world entry;
--   * the state becomes "seen" only once the dialog is really on screen. Closing it, or showing it by
--     hand first, never brings it back by itself.
-- It never holds back or removes a real notice: cards in the coordinator (modules/Notify.lua) go on as
-- before, and the dialog only waits for them. A deleted TwichUIDB.lua is a new installation again, and
-- shows it once more; switching characters, profiles of other addons or resetting a feature does not.
-- Look: the Chronicle's umber and bronze (chronicle/Style.lua) and the zone card's fonts, drawn from
-- flat colours and fonts shipped with TwichUI. It does not use EllesmereUI's skin, so it is the same
-- with or without it and is never skinned twice.

local R = TwichUI
local W = {}
R.Welcome = W

local FRAME_NAME = "TwichUIWelcome"
local WIDTH = 440
local PAD = 22                -- space inside the frame's sides
local BAND = 44               -- title band height
local SETTLE = 3              -- seconds after entering the world before the first look
local RETRY = 2               -- seconds between looks while something is in the way
local MAX_TRIES = 15          -- looks per world entry; after that it waits for the next event

-- What the dialog says. Plain text; a point is a label and a sentence.
W.TITLE = "Welcome to TwichUI"
W.INTRO = "A quiet companion for the interface of WoW: Forever. It tidies and clarifies a few things without taking over, and each feature has its own settings and can be turned off."
W.POINTS = {
    { "Choose what you want", "Open the settings to see each feature and switch it on or off. A few are off until you turn them on." },
    { "Preview before you decide", "Notifications in the settings can show each on-screen card with made-up details first. Nothing is recorded." },
    { "If something doesn't work", "Troubleshooting in the settings builds a report you can read and copy. Nothing is sent anywhere." },
}
W.FOOTER = "Type /tui for all commands."

local frame
local token = 0               -- bumped to drop a waiting timer; a timer only acts if it is still current
local waiting = false         -- one timer is waiting (a second is never started)
local tries = 0
local shownCount = 0          -- for the troubleshooting report
local active = {}             -- [event] = handler, while registered

---------------------------------------------------------------------------
-- First-run state
---------------------------------------------------------------------------
local function State()
    local w = TwichUIDB and TwichUIDB.welcome
    return type(w) == "table" and w.state or nil
end

-- True while the automatic welcome is still owed: a new installation that has not yet seen it.
function W.Owed() return State() == "pending" end

local function MarkSeen()
    local w = TwichUIDB and TwichUIDB.welcome
    if type(w) == "table" and w.state == "pending" then w.state = "seen" end
end

---------------------------------------------------------------------------
-- The dialog
---------------------------------------------------------------------------
local function Color(c, a) return c[1], c[2], c[3], a end

-- A font string in the zone card's fonts (with that card's fallback for scripts they don't cover).
local function Text(parent, path, size, fallback, color)
    local A = R.Arrival
    local fs = parent:CreateFontString(nil, "OVERLAY")
    A.SetFont(fs, path, size, fallback)
    fs:SetShadowColor(0, 0, 0, 0.7)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(Color(color))
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    return fs
end

local function Rule(parent, K)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetColorTexture(K.bronzeLo[1], K.bronzeLo[2], K.bronzeLo[3], 0.8)
    t:SetHeight(1)
    return t
end

-- The height a font string needs for the text it holds at its width. A client that has not measured yet
-- gives 0 or nil; a line's worth stands in so the frame is never collapsed.
local function Height(fs, minimum)
    local h = fs:GetStringHeight()
    if type(h) ~= "number" or h < minimum then return minimum end
    return h
end

local function OpenSettings()
    if not R:OpenSettings() then
        R.Print("the settings aren't available right now.")
        return   -- the dialog stays, so the player is not left with nothing
    end
    frame:Hide()
end

-- Positions everything from the text as the client lays it out now, then sizes the frame to fit.
-- Safe to repeat; run each time the dialog opens so a different font, scale or locale is measured, not assumed.
local function Layout()
    local inner = WIDTH - PAD * 2
    local y = BAND + 16
    frame.intro:SetWidth(inner)
    frame.intro:ClearAllPoints()
    frame.intro:SetPoint("TOPLEFT", PAD, -y)
    y = y + Height(frame.intro, 16) + 14

    frame.ruleTop:ClearAllPoints()
    frame.ruleTop:SetPoint("TOPLEFT", PAD, -y)
    frame.ruleTop:SetPoint("TOPRIGHT", -PAD, -y)
    y = y + 15

    for i, point in ipairs(frame.points) do
        point.label:SetWidth(inner)
        point.label:ClearAllPoints()
        point.label:SetPoint("TOPLEFT", PAD + 14, -y)
        point.mark:ClearAllPoints()
        point.mark:SetPoint("TOPLEFT", PAD + 2, -(y + 6))
        y = y + Height(point.label, 16) + 2
        point.body:SetWidth(inner - 14)
        point.body:ClearAllPoints()
        point.body:SetPoint("TOPLEFT", PAD + 14, -y)
        y = y + Height(point.body, 16) + (i < #frame.points and 12 or 0)
    end
    y = y + 16

    frame.ruleBottom:ClearAllPoints()
    frame.ruleBottom:SetPoint("TOPLEFT", PAD, -y)
    frame.ruleBottom:SetPoint("TOPRIGHT", -PAD, -y)
    y = y + 14

    frame.footer:SetWidth(inner - frame.open:GetWidth() - frame.dismiss:GetWidth() - 24)
    frame.footer:ClearAllPoints()
    frame.footer:SetPoint("TOPLEFT", PAD, -(y + 5))
    frame.open:ClearAllPoints()
    frame.open:SetPoint("TOPRIGHT", -PAD, -y)
    frame.dismiss:ClearAllPoints()
    frame.dismiss:SetPoint("RIGHT", frame.open, "LEFT", -8, 0)
    local footerBottom = y + 5 + Height(frame.footer, 14)
    y = math.max(y + 24, footerBottom) + PAD - 4

    local height = math.ceil(y)
    frame:SetSize(WIDTH, height)
    return height
end

-- Buttons are wide enough for their label, never narrower than a standard button.
local function WideEnough(button, minimum)
    local w = button.text:GetStringWidth()
    button:SetWidth(math.max(minimum, (type(w) == "number" and w or 0) + 32))
end

local function Build()
    local S, A = R.ChronicleStyle, R.Arrival
    if not (S and S.Frame and A and A.SetFont and A.FONT_TITLE) then return false end
    local K = S.color
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 300)   -- replaced by Layout() from the real text below
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, FRAME_NAME)   -- Escape closes it

    f.title = Text(f, A.FONT_TITLE, 18, "GameFontNormalLarge", K.text)
    f.title:SetWordWrap(false)
    f.title:SetWidth(WIDTH - PAD - 48)
    f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(BAND / 2))
    f.title:SetText(W.TITLE)
    f.close = S.Close(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -10, -(BAND / 2 - 10))

    f.intro = Text(f, A.FONT_LINE, 15, "GameFontHighlight", K.text)
    f.intro:SetText(W.INTRO)
    f.ruleTop = Rule(f, K)

    f.points = {}
    for i, p in ipairs(W.POINTS) do
        local point = {}
        point.mark = f:CreateTexture(nil, "ARTWORK")      -- a small bronze square, as a ledger's bullet
        point.mark:SetColorTexture(Color(K.gold, 0.9))
        point.mark:SetSize(5, 5)
        point.label = Text(f, A.FONT_LINE, 15, "GameFontNormal", K.gold)
        point.label:SetWordWrap(false)
        point.label:SetText(p[1])
        point.body = Text(f, A.FONT_LINE, 14, "GameFontHighlightSmall", K.textDim)
        point.body:SetText(p[2])
        f.points[i] = point
    end
    f.ruleBottom = Rule(f, K)

    f.footer = Text(f, A.FONT_LINE, 13, "GameFontDisableSmall", K.stone)
    f.footer:SetText(W.FOOTER)
    f.open = S.Button(f, "Open Settings", 110, "primary", OpenSettings)
    f.dismiss = S.Button(f, "Close", 80, "secondary", function() f:Hide() end)
    WideEnough(f.open, 110)
    WideEnough(f.dismiss, 80)
    frame = f
    -- The frame's art is drawn for the height the text really needs, measured here and again at each opening.
    S.Frame(f, WIDTH, Layout())
    S.Header(f, BAND - 8)

    -- Whatever closes it (button, close box, Escape, a new loading screen taking the UI), it is simply gone.
    f:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        if R.Interact then R.Interact.HideTip(self) end
    end)
    return true
end

---------------------------------------------------------------------------
-- Showing it
---------------------------------------------------------------------------
-- Shows the dialog now, whatever the state. Returns true, or false and a reason. Used by /tui about and
-- the options; the automatic path calls it (auto) once everything is clear, and says nothing if it can't.
function W.Show(auto)
    if not frame and not Build() then
        if not auto then R.Print("the welcome isn't available right now.") end
        return false, "unavailable"
    end
    Layout()
    frame:Show()
    if not frame:IsVisible() then return false, "hidden" end   -- e.g. the interface is hidden: nothing was seen
    shownCount = shownCount + 1
    if W.Owed() then
        MarkSeen()
        W.Refresh()   -- nothing is owed any more: stop listening and drop any waiting look
    end
    return true
end

function W.Hide() if frame then frame:Hide() end end
function W.IsShown() return frame ~= nil and frame:IsShown() end

---------------------------------------------------------------------------
-- When it may appear on its own
---------------------------------------------------------------------------
local function Toasting()
    local toast = EventToastManagerFrame
    return toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting() and true or false
end

local function Cinematic()
    for _, f in ipairs({ CinematicFrame, MovieFrame }) do
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

-- A TwichUI card waiting or showing (Welcome Back, zone, training, friend, or a preview). Read only: the
-- coordinator is never asked to hold anything back for the dialog.
local function CardsUp()
    local N = R.Notify
    if not (N and N.Snapshot) then return false end
    local s = N.Snapshot()
    return s.queued > 0 or next(s.active) ~= nil
end

-- A short reason code for what is in the way, or nil when it is clear.
function W.InTheWay()
    if not (R.Life and R.Life.configReady) then return "settings" end
    if not R.Life.InWorld() then return "world" end
    if InCombatLockdown() then return "combat" end
    if UnitOnTaxi and UnitOnTaxi("player") then return "flight" end
    if UIParent and UIParent.IsShown and not UIParent:IsShown() then return "interface-hidden" end
    if Toasting() or Cinematic() then return "banner" end
    if CardsUp() then return "cards" end
    return nil
end

local Schedule

local function Attempt(mine)
    if mine ~= token then return end
    waiting = false
    if not W.Owed() then return end
    if W.InTheWay() then
        R.Life.Note("welcome-deferred")
        tries = tries + 1
        if tries < MAX_TRIES then Schedule(RETRY) end   -- then it waits for the next world entry or end of combat
        return
    end
    if not W.Show(true) then   -- not shown, or shown but not visible (the interface was hidden meanwhile): still owed
        tries = tries + 1
        if tries < MAX_TRIES then Schedule(RETRY) end
    end
end

-- Waits `delay` seconds for one look. Never more than one waiting.
function Schedule(delay)
    if waiting or not W.Owed() then return end
    waiting = true
    local mine = token
    C_Timer.After(delay, function() Attempt(mine) end)
end

local function Cancel()
    token = token + 1
    waiting = false
end

local function OnEnteringWorld()
    Cancel()
    tries = 0
    Schedule(SETTLE)
end

local function OnLeavingWorld() Cancel() end

local function OnCombatEnded()
    if tries >= MAX_TRIES then tries = 0 end   -- the fight is over: a fresh set of looks
    Schedule(1)
end

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

-- Listens only while the automatic welcome is owed. Safe to call any time.
function W.Refresh()
    local owed = W.Owed()
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, owed)
    Want("PLAYER_LEAVING_WORLD", OnLeavingWorld, owed)
    Want("PLAYER_REGEN_ENABLED", OnCombatEnded, owed)
    if not owed then Cancel() end
end

-- For the troubleshooting report: states and counts only.
function W.Snapshot()
    return { state = State() or "none", listening = next(active) ~= nil, waiting = waiting, tries = tries, shown = shownCount }
end

R:OnInit(function()
    W.Refresh()
    if W.Owed() and R.Life.InWorld() then Schedule(SETTLE) end
end)
