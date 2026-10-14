-- TwichUI: troubleshooting window and /tui diagnostics
-- A small window: a short explanation of what a report holds, whether tracing is on, buttons to
-- refresh the report, start or stop tracing and clear what was collected, and the report itself in a
-- text box to select and copy by hand (Ctrl+A, Ctrl+C). The game gives an addon no clipboard, so there
-- is no "copy" button. The report is built when the window opens or Refresh is pressed, never in the
-- background, and nothing is sent anywhere.

local R = TwichUI
local D = R.Diag
local W = {}
R.DiagWindow = W

local WIDTH, HEIGHT = 700, 520
local FRAME_NAME = "TwichUIDiagnosticsWindow"

local function Say(fmt, ...) R.Print("troubleshooting: " .. fmt, ...) end

local window

---------------------------------------------------------------------------
-- Look. The same as the sharing window's (setup/Window.lua): EllesmereUI's shell, panels, buttons,
-- scroll bar and fonts when its skin toolkit is there, else the plain dark frame that window falls
-- back to. The toolkit arrives at login, so a window built earlier is skinned when it does.
---------------------------------------------------------------------------
local skinnable = {}   -- { kind, object, options }, in the order they were made

local function Skin(kind, obj, ...)
    local S = R.S
    if not (S and S[kind] and obj) then return end
    pcall(S[kind], obj, ...)
end

-- Remembers an object to skin, and skins it now if the toolkit is already here.
local function Track(kind, obj, ...)
    skinnable[#skinnable + 1] = { kind = kind, obj = obj, args = { ... } }
    Skin(kind, obj, ...)
end

-- UIPanelScrollFrameTemplate's bar is the old arrow-button slider: the same treatment the sharing window
-- gives it (arrows faded, thumb a slim strip).
local function SkinScrollFrame(scroll)
    local sb = scroll and scroll.ScrollBar
    if not (R.S and type(sb) == "table") then return end
    Skin("ScrollBar", sb)
    local name = sb:GetName() or ""
    for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local b = sb[suffix] or _G[name .. suffix]
        if b then
            for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
                local t = b[getter] and b[getter](b)
                if t then t:SetAlpha(0) end
            end
        end
    end
    local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetVertexColor(1, 1, 1, 0.3)
        thumb:SetWidth(4)
    end
end

local function Plain(frame, bg, edge)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

local function ApplySkin(f)
    for _, item in ipairs(skinnable) do Skin(item.kind, item.obj, unpack(item.args)) end
    SkinScrollFrame(f.scroll)
end

-- The tracing line and the Start/Stop button's wording, from the service's state.
function W.RefreshStatus()
    if not window then return end
    local s = D.Status()
    if s.tracing then
        window.status:SetText(("%sTracing is ON|r  (%d records kept; it stops by itself after %d minutes; nothing is saved)")
            :format(R.GREEN, s.records, D.TRACE_SECONDS / 60))
        window.toggle:SetText("Stop tracing")
    else
        window.status:SetText(("%sTracing is off|r  (%d records kept; it is off until you start it, and is not kept across a reload)")
            :format(R.GREY, s.records))
        window.toggle:SetText("Start tracing")
    end
    -- Nothing to forget: the button says so instead of seeming to do something.
    window.clear:SetEnabled(s.records + s.errors > 0)
    R.Interact.RefreshTip(window.toggle)
    R.Interact.RefreshTip(window.clear)
end

function W.Refresh()
    if not window then return end
    local text = D.Build()
    window.text = text
    window.edit:SetText(text)
    window.edit:SetCursorPosition(0)
    if #window.edit:GetText() < #text then
        Say("the box could not hold the whole report; the end is cut off.")
    end
    W.RefreshStatus()
end

local function Button(parent, label, width, tooltip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(label)
    if tooltip then R.Interact.Tip(b, nil, tooltip) end
    Track("Button", b)
    Track("StateButtonLabel", b)
    return b
end

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    Track("Font", fs)
    return fs
end

local function Build()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:HookScript("OnShow", R.FitToScreen)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, FRAME_NAME)
    if R.S then Skin("Shell", f) else Plain(f, { 0.07, 0.065, 0.06, 0.97 }, { 0.25, 0.23, 0.2 }) end
    skinnable[#skinnable + 1] = { kind = "Shell", obj = f, args = {} }
    f:Hide()

    -- Header, as the sharing window's: the icon, the name and a quiet line saying what this is.
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 12, -8)
    logo:SetTexture(R.ICON)
    local title = Text(f, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("TwichUI")
    title:SetTextColor(1, 1, 1)
    local sub = Text(f, "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("troubleshooting report")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    Track("CloseButton", close)

    local intro = Text(f, "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 16, -46)
    intro:SetWidth(WIDTH - 32)
    intro:SetText("This report is built on your computer when you open this window or press Refresh. It lists settings, "
        .. "module states, counts and reason codes. It leaves out character, realm, guild, friend and BattleTag names, chat, "
        .. "Chronicle entries and your configuration, and nothing is sent anywhere. Read it first; then click in the box, "
        .. "press Ctrl+A and Ctrl+C, and paste it where you were asked to.")

    f.status = Text(f, "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
    f.status:SetWidth(WIDTH - 32)

    local refresh = Button(f, "Refresh report", 120,
        "Builds the report again from how things are now. It is made on your computer; nothing is sent.")
    refresh:SetPoint("TOPLEFT", f.status, "BOTTOMLEFT", 0, -8)
    refresh:SetScript("OnClick", W.Refresh)
    f.toggle = Button(f, "Start tracing", 120, function()
        if D.Tracing() then
            return "Stops tracing now. What was recorded is kept until you clear it or reload."
        end
        return ("Starts recording short notes about TwichUI's own decisions, in memory only. It stops by itself after %d minutes and is gone after a reload."):format(D.TRACE_SECONDS / 60)
    end)
    f.toggle:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
    f.toggle:SetScript("OnClick", function()
        if D.Tracing() then D.Stop("manual") else D.Start() end
        W.Refresh()
    end)
    local clear = Button(f, "Clear records", 120, function()
        local s = D.Status()
        return "Forgets the trace records and recent errors kept so far. Tracing, if on, carries on.",
            (s.records + s.errors == 0) and "Nothing has been collected." or nil
    end)
    f.clear = clear
    clear:SetPoint("LEFT", f.toggle, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        D.Clear()
        W.Refresh()
    end)

    -- The report sits in an inset panel, like the sharing window's lists and copy boxes.
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", refresh, "BOTTOMLEFT", 0, -10)
    box:SetPoint("BOTTOMRIGHT", -16, 16)
    if R.S then Skin("Panel", box, { inset = true }) else Plain(box, { 0, 0, 0, 0.5 }, { 1, 1, 1, 0.08 }) end
    skinnable[#skinnable + 1] = { kind = "Panel", obj = box, args = { { inset = true } } }

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    f.scroll = scroll
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(WIDTH - 72)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    -- The report is for reading and copying; typing in the box puts the text back.
    edit:SetScript("OnTextChanged", function(e, user)
        if user and f.text then
            e:SetText(f.text)
            e:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit

    SkinScrollFrame(scroll)
    -- EllesmereUI hands its toolkit over at login; a window opened before that is skinned then.
    if not R.S then R:OnSkin(function() ApplySkin(f) end) end
    return f
end

function W.Show()
    if not window then window = Build() end
    W.Refresh()
    window:Show()
    window:Raise()
end

function W.IsShown() return window ~= nil and window:IsShown() end

-- Whatever changes the tracing state (a timeout, a command, a button) keeps the status line true.
D.OnChange(W.RefreshStatus)

---------------------------------------------------------------------------
-- /tui diagnostics
---------------------------------------------------------------------------
local USAGE = "start | stop | clear | status | test friend | test sound [stock] | probe"

local function Status()
    local s = D.Status()
    if s.tracing then
        Say("tracing is ON (%ds so far, %d of at most %d records kept; it stops by itself after %d minutes).",
            s.elapsed, s.records, s.max, D.TRACE_SECONDS / 60)
    else
        Say("tracing is off (%d records kept).", s.records)
    end
    for _, m in ipairs(D.Summary()) do print(("  %s%s|r"):format(R.GREY, m.line)) end
    Say("/tui diagnostics opens the full report.")
end

function W.Command(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word, rest = word:lower(), rest:lower()
    if word == "" or word == "open" or word == "report" then
        W.Show()
    elseif word == "start" then
        if D.Start() then
            Say("tracing is ON for up to %d minutes, in memory only. Reproduce the problem, then type /tui diagnostics to read and copy the report. /tui diagnostics stop ends it sooner.",
                D.TRACE_SECONDS / 60)
        else
            Say("tracing is already on.")
        end
        W.Refresh()
    elseif word == "stop" then
        Say(D.Stop("manual") and "tracing stopped. The records are kept until you clear them or reload; /tui diagnostics shows them." or "tracing was not on.")
        W.Refresh()
    elseif word == "clear" then
        D.Clear()
        Say("records cleared%s.", D.Tracing() and " (tracing is still on)" or "")
        W.Refresh()
    elseif word == "status" then
        Status()
    elseif word == "test" then
        local Friends = R.DiagFriends
        if rest == "friend" and Friends then Friends.TestCard()
        elseif rest:match("^sound") and Friends then Friends.TestSound(rest == "sound stock")
        else Say("usage: /tui diagnostics test friend | test sound [stock]. Tests are made-up: they show the card or chime works, not that real events arrive.") end
    elseif word == "probe" then
        if R.FoodDrinkProbe then R.FoodDrinkProbe.Run() else Say("the consumables probe isn't available right now.") end
    else
        Say("usage: /tui diagnostics %s", USAGE)
    end
end

-- /tui frienddiag, as it was before the shared service: each word is sent to its new home.
function W.LegacyFriendDiag(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word, rest = word:lower(), rest:lower()
    Say("/tui frienddiag has moved: use /tui diagnostics (start, stop, clear, status, test friend, test sound).")
    if word == "status" then W.Command("status")
    elseif word == "test" then
        if rest == "logout" then Say("there is no TwichUI logout card; only login is built.") else W.Command("test friend") end
    elseif word == "sound" then W.Command("test " .. (rest == "stock" and "sound stock" or "sound"))
    elseif word == "trace" then W.Command(rest == "off" and "stop" or "start")
    elseif word == "reset" then
        D.Stop("manual")
        W.Command("clear")
    elseif word == "report" then W.Command("")
    end
end
