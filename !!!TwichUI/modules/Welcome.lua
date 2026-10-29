-- TwichUI: welcome dialog
-- One compact page that says what TwichUI is, shows a few of its features, says which features act for the player
-- (and which of those are on), and opens the settings or a preview of the notification cards. It is shown when the
-- player asks (/tui about, or Welcome in the settings' Home page), never by itself: a new installation is offered the
-- layout setup instead (Onboarding.lua, docs/onboarding.md). It changes no setting and enables nothing: its buttons
-- close it, open TwichUI's settings (at Home or at the page of something it lists) or show a sample card.
--
-- The older first-run marker, TwichUIDB.welcome.state ("pending" for a new installation, else "seen"; Persist.lua), is
-- moved to "seen" when the dialog is shown, and is otherwise only read as evidence of an existing user. "Hide addon welcome
-- messages" (Home) is a different thing: it hides other addons' lines in chat and has no say over this dialog.
--
-- What it says about automation comes from modules/WelcomeAutomation.lua, read each time the dialog is shown, so it
-- matches the switches of the moment. The settings window (TwichUI_Settings) is not loaded to draw the dialog or to
-- read that summary; it loads only when a button asks to open it (R:OpenSettings).
--
-- Preview: the button shows the zone card and the friend card through the notification coordinator's own preview
-- (Notify.Preview): made-up details, no sound unless the player allowed preview sounds, nothing recorded, no game
-- state touched, reduced motion honoured by the cards. Closing the dialog takes back the previews it started.
--
-- Look: TwichUI's own window look (Look.lua), the same family as the settings window, with or without
-- EllesmereUI; it is never skinned by it. Its fade follows "Reduce window motion" on Home.

local R = TwichUI
local W = {}
R.Welcome = W

local FRAME_NAME = "TwichUIWelcome"
local WIDTH = 460
local PAD = 22                -- space inside the frame's sides
local BAND = 44               -- title band height
local PREVIEW_KINDS = { "arrival", "friend" }   -- the sample cards the Preview button shows (different places, so together)

-- What the dialog says. Plain text; a point is a label and a sentence.
W.TITLE = "Welcome to TwichUI"
W.INTRO = "A quiet companion for the interface of WoW: Forever. It tidies and clarifies a few things without taking over, and each feature has its own settings and can be turned off."
W.POINTS = {
    { "Cards for what's new", "Small cards for new zones, new spells to train and Battle.net friends signing in, in place of the game's own text and pop-up." },
    { "Journey Chronicle", "A private journal for each character: levels, zones, bosses and your own notes." },
    { "Gear hints", "Item tooltips can say when something is a likely upgrade, from stat weights you can edit. It's a hint, not a simulation." },
}
W.AUTO_HEAD = "What can act for you"
W.AUTO_LEAD = "Opening this window or a preview turns nothing on. Each feature below has its own switch in the settings."
W.ON_LABEL = "On now"
W.NONE_ON = "Nothing here is turned on."
W.OFF_LABEL = "Off until you turn them on"
W.LINKS_LABEL = "Review in settings:"
W.FOOTER = "Type /tui for all commands. Troubleshooting in the settings builds a report if something goes wrong."

local frame
local shownCount = 0          -- for the troubleshooting report
local previewing = false      -- this dialog started previews that are still up

---------------------------------------------------------------------------
-- The older first-run marker
---------------------------------------------------------------------------
local function State()
    local w = TwichUIDB and TwichUIDB.welcome
    return type(w) == "table" and w.state or nil
end

local function MarkSeen()
    local w = TwichUIDB and TwichUIDB.welcome
    if type(w) == "table" and w.state == "pending" then w.state = "seen" end
end

---------------------------------------------------------------------------
-- The dialog
---------------------------------------------------------------------------
local function Look() return R.Look end

-- A wrapped, top-aligned text in the window look. kind: "body", "small", "meta" or "heading" (Look.Text).
local function Text(parent, kind, wrap)
    local fs = Look().Text(parent, kind)
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(wrap and true or false)
    return fs
end

local function Rule(parent)
    local t = Look().Solid(parent, "BORDER", Look().pal.divider, 0.8)
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

local function Width(fs)
    local w = fs:GetStringWidth()
    return type(w) == "number" and w or 0
end

-- Opens the settings (at a page, or at Home) and puts the dialog away. R:OpenSettings loads the settings addon
-- the first time and says why in chat when it can't; then the dialog stays, so the player is not left with nothing.
local function OpenSettings(page)
    if not R:OpenSettings(page) then return end
    frame:Hide()
end

-- Shows the sample zone and friend cards. Returns true, or false and a reason: "unavailable" (no coordinator),
-- "combat" (previews wait, as the settings' do) or "refused".
function W.Preview()
    local N = R.Notify
    if not (N and N.Preview) then return false, "unavailable" end
    if InCombatLockdown() then
        R.Print("previews wait until you're out of combat.")
        return false, "combat"
    end
    local shown = 0
    for _, kind in ipairs(PREVIEW_KINDS) do
        if N.Preview(kind) then shown = shown + 1 end
    end
    if shown == 0 then
        R.Print("couldn't show the sample cards right now.")
        return false, "refused"
    end
    previewing = true
    return true
end

-- Takes back the previews this dialog started (only those: previews begun in the settings are left alone).
local function DropPreviews()
    if not previewing then return end
    previewing = false
    local N = R.Notify
    if not (N and N.DropPreviews) then return end
    for _, kind in ipairs(PREVIEW_KINDS) do N.DropPreviews(kind) end
end

-- "a, b and c"
local function Join(list)
    local n = #list
    if n <= 1 then return list[1] or "" end
    return table.concat(list, ", ", 1, n - 1) .. " and " .. list[n]
end

-- Fills in what depends on the moment: the automation summary. Safe to repeat. Row and link frames are made once
-- and reused, so showing the dialog again adds nothing.
local function Populate()
    local f = frame
    local pal = Look().pal
    local sum = R.WelcomeAutomation and R.WelcomeAutomation.Summary() or { on = {}, off = {}, pages = {} }
    f.summary = sum

    for i, item in ipairs(sum.on) do
        local row = f.rows[i]
        if not row then
            row = { label = Text(f, "body", false), body = Text(f, "small", true) }
            f.rows[i] = row
        end
        row.label:SetText(item.label)
        row.body:SetText(item.text)
        row.label:Show()
        row.body:Show()
    end
    for i = #sum.on + 1, #f.rows do
        f.rows[i].label:Hide()
        f.rows[i].body:Hide()
    end
    if #sum.on == 0 then f.onNone:Show() else f.onNone:Hide() end

    local phrases = {}
    for i, item in ipairs(sum.off) do phrases[i] = item.text end
    if #phrases > 0 then
        local line = Join(phrases)
        f.offText:SetText(line:sub(1, 1):upper() .. line:sub(2) .. ".")
        f.offLabel:Show()
        f.offText:Show()
    else
        f.offLabel:Hide()
        f.offText:Hide()
    end

    for i, page in ipairs(sum.pages) do
        local link = f.links[i]
        if not link then
            link = R.ChronicleStyle.Link(f, "", function(self) OpenSettings(self.page) end, pal.tealHi, pal.text)
            link.text:SetJustifyH("LEFT")
            link.text:SetWordWrap(false)   -- its width is then the text's own, which the layout measures
            f.links[i] = link
        end
        link.page = page
        link.text:SetText(R.WelcomeAutomation.PAGE_LABEL[page] or page)
        link:Show()
    end
    for i = #sum.pages + 1, #f.links do f.links[i]:Hide() end
    if #sum.pages > 0 then f.linksLabel:Show() else f.linksLabel:Hide() end
end

-- Buttons are wide enough for their label, never narrower than a standard button.
local function WideEnough(button, minimum)
    local w = button.text:GetStringWidth()
    button:SetWidth(math.max(minimum, (type(w) == "number" and w or 0) + 32))
end

-- Positions everything from the text as the client lays it out now, then sizes the frame to fit.
-- Safe to repeat; run each time the dialog opens so a different font, scale or locale is measured, not assumed.
local function Layout()
    local f = frame
    local inner = WIDTH - PAD * 2
    local y = BAND + 16

    local function Place(fs, x, width, minimum, gap)
        fs:SetWidth(width)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", x, -y)
        y = y + Height(fs, minimum) + gap
    end
    local function Line(rule)
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", PAD, -y)
        rule:SetPoint("TOPRIGHT", -PAD, -y)
    end

    Place(f.intro, PAD, inner, 16, 14)
    Line(f.ruleTop)
    y = y + 15

    for i, point in ipairs(f.points) do
        point.mark:ClearAllPoints()
        point.mark:SetPoint("TOPLEFT", PAD + 2, -(y + 6))
        Place(point.label, PAD + 14, inner - 14, 16, 2)
        Place(point.body, PAD + 14, inner - 14, 14, i < #f.points and 10 or 0)
    end
    y = y + 16
    Line(f.ruleMid)
    y = y + 15

    -- What can act for you
    Place(f.autoHead, PAD, inner, 16, 2)
    Place(f.autoLead, PAD, inner, 14, 12)

    local sum = f.summary
    Place(f.onLabel, PAD, inner, 14, 4)
    if #sum.on == 0 then
        Place(f.onNone, PAD + 14, inner - 14, 14, 10)
    else
        for i, item in ipairs(sum.on) do
            local row = f.rows[i]
            Place(row.label, PAD + 14, inner - 14, 14, 1)
            Place(row.body, PAD + 14, inner - 14, 13, i < #sum.on and 7 or 10)
        end
    end
    if #sum.off > 0 then
        Place(f.offLabel, PAD, inner, 14, 4)
        Place(f.offText, PAD + 14, inner - 14, 13, 12)
    end

    if #sum.pages > 0 then
        f.linksLabel:ClearAllPoints()
        f.linksLabel:SetPoint("TOPLEFT", PAD, -(y + 1))
        local x, rowTop = PAD + Width(f.linksLabel) + 10, y
        for i = 1, #sum.pages do
            local link = f.links[i]
            local w = math.ceil(Width(link.text)) + 4
            if x + w > PAD + inner and x > PAD + 1 then   -- no room left on this line: the next
                x = PAD
                rowTop = rowTop + 18
            end
            link:SetSize(w, 14)
            link:ClearAllPoints()
            link:SetPoint("TOPLEFT", x, -rowTop)
            x = x + w + 12
        end
        y = rowTop + 18
    end
    y = y + 6
    Line(f.ruleBottom)
    y = y + 14

    Place(f.footer, PAD, inner, 13, 12)

    -- Buttons, right to left: Open Settings, Preview notifications, Close. If they don't fit on one line they
    -- go on two rather than overlapping.
    local buttons = { f.open }
    if f.preview:IsShown() then buttons[#buttons + 1] = f.preview end
    buttons[#buttons + 1] = f.dismiss
    local total = -8
    for _, b in ipairs(buttons) do total = total + b:GetWidth() + 8 end
    local wrapAt = total > inner and #buttons - 1 or #buttons
    local x, rowY = -PAD, y
    for i, b in ipairs(buttons) do
        if i > wrapAt then
            x, rowY = -PAD, rowY + 30
        end
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", x, -rowY)
        x = x - b:GetWidth() - 8
    end
    y = rowY + 24 + PAD - 4

    local height = math.ceil(y)
    f:SetSize(WIDTH, height)
    return height
end

local function Build()
    local L = Look()
    if not (L and L.Shell and L.Text and L.Button and L.Solid and L.CloseBox and R.ChronicleStyle and R.ChronicleStyle.Link) then
        return false
    end
    local pal = L.pal
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
    frame = f

    f.intro = Text(f, "body", true)
    f.intro:SetText(W.INTRO)
    f.ruleTop = Rule(f)

    f.points = {}
    for i, p in ipairs(W.POINTS) do
        local point = {}
        point.mark = L.Solid(f, "ARTWORK", pal.bronzeText, 0.9)   -- a small bronze square, as a ledger's bullet
        point.mark:SetSize(5, 5)
        point.label = Text(f, "heading", false)
        point.label:SetText(p[1])
        point.body = Text(f, "small", true)
        point.body:SetText(p[2])
        f.points[i] = point
    end
    f.ruleMid = Rule(f)

    f.autoHead = Text(f, "heading", false)
    f.autoHead:SetText(W.AUTO_HEAD)
    f.autoLead = Text(f, "small", true)
    f.autoLead:SetText(W.AUTO_LEAD)
    f.onLabel = Text(f, "meta", false)
    f.onLabel:SetText(W.ON_LABEL)
    f.onLabel:SetTextColor(pal.tealHi[1], pal.tealHi[2], pal.tealHi[3])
    f.onNone = Text(f, "small", true)
    f.onNone:SetText(W.NONE_ON)
    f.rows = {}
    f.offLabel = Text(f, "meta", false)
    f.offLabel:SetText(W.OFF_LABEL)
    f.offText = Text(f, "small", true)
    f.linksLabel = Text(f, "meta", false)
    f.linksLabel:SetText(W.LINKS_LABEL)
    f.links = {}
    f.summary = { on = {}, off = {}, pages = {} }
    f.ruleBottom = Rule(f)

    f.footer = Text(f, "meta", true)
    f.footer:SetText(W.FOOTER)
    f.open = L.Button(f, "Open Settings", 110, "primary", function() OpenSettings() end)
    f.preview = L.Button(f, "Preview notifications", 150, "secondary", function() W.Preview() end)
    f.dismiss = L.Button(f, "Close", 80, "secondary", function() f:Hide() end)
    WideEnough(f.open, 110)
    WideEnough(f.preview, 150)
    WideEnough(f.dismiss, 80)
    local I = R.Interact
    if I and I.Tip then
        I.Tip(f.preview, "Preview notifications", "Shows a sample zone card and friend card with made-up details. Nothing is recorded or turned on, and no sound plays unless you've allowed preview sounds in the settings.")
        I.Tip(f.open, "Open Settings", "Opens TwichUI's settings at Home. Each feature has its own page, and every one can be turned off.")
    end

    -- Whatever closes it (button, close box, Escape, a new loading screen taking the UI), it is simply gone,
    -- and so are the sample cards it showed.
    f:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        DropPreviews()
        if R.Interact then R.Interact.HideTip(self) end
    end)
    Populate()
    Layout()   -- the frame's height now follows its text, and its art is drawn for that height

    -- The rim and title band, and a short fade in unless "Reduce window motion" is on (Look.Shell).
    L.Shell(f, BAND)
    f.title = L.Text(f, "title")
    f.title:SetWordWrap(false)
    f.title:SetWidth(WIDTH - PAD - 48)
    f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(BAND / 2))
    f.title:SetText(W.TITLE)
    f.close = L.CloseBox(f, function() f:Hide() end)
    return true
end

---------------------------------------------------------------------------
-- Showing it
---------------------------------------------------------------------------
-- Shows the dialog now. Returns true, or false and a reason. Used by /tui about and the options.
function W.Show()
    if not frame and not Build() then
        R.Print("the welcome isn't available right now.")
        return false, "unavailable"
    end
    Populate()
    -- The Preview button needs the coordinator; without it (it didn't load) the button is left out.
    if R.Notify and R.Notify.Preview then frame.preview:Show() else frame.preview:Hide() end
    Layout()
    R.FitToScreen(frame)   -- its height follows its text, so it is fitted after Layout, not on OnShow
    frame:Show()
    if not frame:IsVisible() then return false, "hidden" end   -- e.g. the interface is hidden: nothing was seen
    shownCount = shownCount + 1
    MarkSeen()
    return true
end

function W.Hide() if frame then frame:Hide() end end
function W.IsShown() return frame ~= nil and frame:IsShown() end

-- For the troubleshooting report: states and counts only.
function W.Snapshot()
    return { state = State() or "none", shown = shownCount }
end
