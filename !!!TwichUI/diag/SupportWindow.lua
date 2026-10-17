-- TwichUI: support information window
-- Shows the support report (diag/Status.lua) in a read-only box the player can inspect and copy by hand. The game
-- gives an addon no clipboard, so there is no automatic copy: the text is selected when the window opens and the
-- window says to press Ctrl+C. The report is built when the window opens or Refresh is pressed, from a fresh look
-- at the addons; it is not kept: closing the window drops the text. Nothing is sent anywhere.

local R = TwichUI
local W = {}
R.SupportWindow = W

local FRAME_NAME = "TwichUISupportWindow"
local WIDTH, HEIGHT = 620, 500

local f          -- the window, built on first use
local fixed      -- the report as shown: typing in the box puts it back

local function Say(fmt, ...) R.Print("support information: " .. fmt, ...) end

local function Build()
    local L = R.Look
    if not (L and L.Shell and L.Text) then return nil end
    f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
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
    tinsert(UISpecialFrames, FRAME_NAME)
    L.Shell(f, 34)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(22, 22)
    logo:SetPoint("TOPLEFT", 12, -10)
    logo:SetTexture(R.ICON)
    local title = L.Text(f, "title")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Support information")
    L.CloseBox(f)

    local intro = L.Text(f, "small")
    intro:SetPoint("TOPLEFT", 16, -48)
    intro:SetWidth(WIDTH - 32)
    intro:SetText("This is exactly what would be shared. It is built on your computer when this window opens or you press Refresh, "
        .. "and nothing is sent anywhere. It lists versions, the state of TwichUI's optional integrations and which features are on. "
        .. "It has no character, realm, guild or friend names, chat, records, saved data or file paths. Read it first; then press "
        .. "Ctrl+C (the text is selected for you) and paste it where you were asked to.")

    local refresh = L.Button(f, "Refresh", 90, "secondary", function() W.Refresh() end)
    refresh:SetHeight(22)
    local selectAll = L.Button(f, "Select all", 90, "secondary", function() W.Select() end)
    selectAll:SetHeight(22)
    selectAll:SetPoint("BOTTOMLEFT", 16, 14)
    refresh:SetPoint("LEFT", selectAll, "RIGHT", 8, 0)
    f.note = L.Text(f, "meta")
    f.note:SetPoint("LEFT", refresh, "RIGHT", 12, 0)
    f.note:SetWidth(WIDTH - 32 - 90 - 90 - 20)
    f.note:SetWordWrap(false)

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
    box:SetPoint("BOTTOMRIGHT", -16, 46)
    L.Well(box, 0.9)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -24, 6)
    L.ScrollBar(scroll)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetWidth(WIDTH - 32 - 34)
    edit:SetTextInsets(2, 2, 2, 2)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    -- For reading and copying: typing puts the report back.
    edit:SetScript("OnTextChanged", function(e, user)
        if user and fixed then
            e:SetText(fixed)
            e:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    f.edit, f.scroll = edit, scroll
    -- Closing releases the text: nothing of the report is kept while the window is away.
    f:HookScript("OnHide", function()
        fixed = nil
        edit:ClearFocus()
        edit:SetText("")
    end)
    return f
end

function W.Select()
    if not (f and f:IsShown() and fixed) then return end
    f.edit:SetFocus()
    f.edit:HighlightText()
    f.note:SetText("Selected. Press Ctrl+C to copy it.")
end

-- Builds the report again from a fresh look and shows it, selected.
function W.Refresh()
    if not (f and f:IsShown()) then return end
    local S = R.DiagStatus
    if not S then return end
    local ok, text = pcall(S.Report)
    if not ok then
        R.Fault("support information", text)
        Say("the report could not be built. /tui diagnostics has the error.")
        return
    end
    fixed = text
    f.edit:SetText(text)
    f.edit:SetCursorPosition(0)
    f.scroll:SetVerticalScroll(0)
    W.Select()
end

function W.Show()
    if not R.DiagStatus then Say("the status report isn't available right now.") return false end
    if not f and not Build() then Say("the window couldn't be built right now.") return false end
    f:Show()
    f:Raise()
    W.Refresh()
    return true
end

function W.Hide()
    if f and f:IsShown() then f:Hide() end
end

function W.IsShown() return f ~= nil and f:IsShown() end

-- The text as shown (nil while the window is closed).
function W.Text() return fixed end
