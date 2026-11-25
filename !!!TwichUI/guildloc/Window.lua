-- Guild Locations: an on-demand, local diagnostic view. Frames are made on first open. Opening, inspecting and the
-- synthetic self-test send nothing; only Test with member starts the bounded peer check. Member names and this report
-- stay in this window's memory, never in routine diagnostics or SavedVariables. Closing cancels transient work.

local R = TwichUI
local GL = R.GuildLoc
local D = GL.Diagnostics
local W = {}
GL.Window = W

local FRAME_NAME = "TwichUIGuildLocationsDiagnostics"
local WIDTH, HEIGHT, HEADER = 700, 600, 40
local f, fixed
local selected, localResult, notice = "", nil, nil

local function Say(text) R.Print("Guild Locations: %s", text) end

local function Member()
    return (f.member:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function Describe(code)
    return D.Describe and D.Describe(code) or tostring(code or "Unavailable")
end

local function Inspect()
    local name = Member()
    if name ~= selected then
        D.Stop()
        notice = nil
    end
    selected = name
    f.member:ClearFocus()
    if D.Inspect then D.Inspect(selected) end
    W.Refresh()
end

function W.Refresh()
    if not (f and f:IsShown()) then return end
    local ok, report = pcall(D.Report, selected)
    if not ok then
        if R.Fault then R.Fault("guild locations diagnostics", report) end
        fixed = "The report could not be built. /tui diagnostics has the error."
    else
        fixed = report
        if notice then fixed = notice .. "\n\n" .. fixed end
        if localResult then fixed = fixed .. "\n\n" .. localResult end
    end
    f.edit:SetText(fixed)
    -- Give the scroll child explicit text bounds; do not depend on an EditBox
    -- resizing itself after its hidden parent is first shown.
    f.measure:SetText(fixed)
    local _, breaks = fixed:gsub("\n", "\n")
    f.edit:SetHeight(math.max(24, f.measure:GetStringHeight() or 0, (breaks + 1) * 14) + 8)
    f.edit:SetCursorPosition(0)
    local running = D.IsRunning()
    f.test:SetEnabled(not running)
    f.stop:SetEnabled(running)
end

local function Build()
    local L, F = R.Look, R.FrameLook
    if not (L and L.Text and L.EditBox and L.Well and L.ScrollBar and F and F.Ready()) then return nil end
    local _, _, right = F.ContentInsets()
    f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:HookScript("OnShow", R.FitToScreen)
    table.insert(UISpecialFrames, FRAME_NAME)
    f.shell = F.Shell(f, { below = true, follow = true })
    F.FadeIn(f)
    local head = f.shell:Header(HEADER)
    local icon = head:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", 16, -12)
    icon:SetTexture(R.PATH .. [[media\guildloc\settings-small]])
    local title = L.Text(f, "title")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetSize(WIDTH - 106, 28)
    title:SetWordWrap(false)
    title:SetText("Guild Locations diagnostics")
    if R.CraftLook then R.CraftLook.Window(f, f.shell, { header = HEADER, title = title }) end
    local close = F.Close(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -(right + 2), -12)

    local intro = L.Text(f, "small")
    intro:SetPoint("TOPLEFT", 16, -(HEADER + 12))
    intro:SetWidth(WIDTH - 32)
    intro:SetText("Inspect a guildmate to see why their location is missing. Test with member asks their addon to reply automatically. "
        .. "Your sharing choice stays in force; Invisible and Off never send a location.")

    local label = L.Text(f, "small")
    label:SetPoint("TOPLEFT", 16, -(HEADER + 72))
    label:SetText("Guildmate's full name")
    f.member = L.EditBox(f, WIDTH - 32 - 116 - 8, 24)
    f.member:SetPoint("TOPLEFT", 16, -(HEADER + 92))
    f.member:SetMaxLetters(120)
    f.member:SetScript("OnEnterPressed", Inspect)
    f.member:SetScript("OnEscapePressed", f.member.ClearFocus)
    local inspect = F.Button(f, "Inspect / refresh", 116, "secondary", Inspect)
    inspect:SetHeight(24)
    inspect:SetPoint("LEFT", f.member, "RIGHT", 8, 0)

    f.test = F.Button(f, "Test with member", 150, "primary", function()
        selected = Member()
        f.member:ClearFocus()
        local ok, why = D.Start(selected)
        notice = ok and nil or Describe(why)
        W.Refresh()
    end)
    f.test:SetHeight(24)
    f.test:SetPoint("TOPLEFT", 16, -(HEADER + 128))
    f.stop = F.Button(f, "Stop", 72, "secondary", function()
        D.Stop()
        notice = "Peer test stopped."
        W.Refresh()
    end)
    f.stop:SetHeight(24)
    f.stop:SetPoint("LEFT", f.test, "RIGHT", 8, 0)
    local selfTest = F.Button(f, "Local self-test", 138, "secondary", function()
        localResult = D.SelfTest()
        notice = nil
        W.Refresh()
    end)
    selfTest:SetHeight(24)
    selfTest:SetPoint("LEFT", f.stop, "RIGHT", 8, 0)

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -(HEADER + 164))
    box:SetPoint("BOTTOMRIGHT", -16, 64)
    L.Well(box, 0.9)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -24, 6)
    L.ScrollBar(scroll)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject("GameFontHighlight")
    local font = _G.GameFontHighlight
    if font and font.GetFont then
        local path, size, flags = font:GetFont()
        if path then edit:SetFont(path, size, flags or "") end
    end
    edit:SetWidth(WIDTH - 32 - 34)
    edit:SetPoint("TOPLEFT", 0, 0)
    edit:SetJustifyH("LEFT")
    edit:SetJustifyV("TOP")
    edit:SetTextInsets(2, 2, 2, 2)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    edit:SetScript("OnTextChanged", function(e, user)
        if user and fixed then e:SetText(fixed); e:HighlightText() end
    end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    f.measure = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.measure:SetWidth(WIDTH - 32 - 38)
    f.measure:SetJustifyH("LEFT")
    f.measure:Hide()

    local footer = L.Text(f, "meta")
    footer:SetPoint("BOTTOMLEFT", 16, 18)
    footer:SetWidth(WIDTH - 32)
    footer:SetText("A peer test needs a compatible online guildmate. No reply is inconclusive. "
        .. "Local tests send nothing. Move this window aside to see the map-center test badge. Closing cancels the peer test and removes the test marker.")

    f:HookScript("OnHide", function()
        D.Stop()
        if GL.Map and GL.Map.StopSelfTest then GL.Map.StopSelfTest() end
        selected, localResult, notice, fixed = "", nil, nil, nil
        f.member:ClearFocus()
        f.member:SetText("")
        edit:ClearFocus()
        edit:SetText("")
        f.measure:SetText("")
    end)
    return f
end

function W.Show(name)
    if not D then Say("Diagnostics are unavailable.") return false end
    if not f and not Build() then Say("The diagnostic window could not be built right now.") return false end
    if type(name) == "string" then selected = name; f.member:SetText(name) end
    f:Show()
    f:Raise()
    W.Refresh()
    return true
end

function W.Hide() if f then f:Hide() end end
function W.IsShown() return f ~= nil and f:IsShown() end
function W.Text() return fixed end

-- One listener, regardless of how many times the panel opens. It does no work while closed and owns no timer.
if D then D.OnChange(W.Refresh) end
