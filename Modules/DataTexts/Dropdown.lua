local E = unpack(ElvUI)
local T = unpack(Twich)
--- @type DataTextsModule
local DataTextsModule = T:GetModule("DataTexts")

-- Cache WoW Globals
local _G = _G
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local LSM = E.Libs.LSM
local ToggleFrame = ToggleFrame
local format = format
local strfind = strfind
local tinsert = tinsert

local autoHideDelay = 2
local PADDING = 10

local function DropDownTimer(menuFrame)
    local parent = menuFrame.parent

    -- if mouse is not over the menu or its parent datatext, hide it
    if not menuFrame:IsMouseOver() and (not parent or not parent:IsMouseOver()) then
        menuFrame:Hide()

        if menuFrame.timer then
            menuFrame.timer:Cancel()
            menuFrame.timer = nil
        end
    end
end

-- list = tbl see below
-- text = string, right_tex = string, color = color string for first text, icon = texture, func = function, funcOnEnter = function,
-- funcOnLeave = function, isTitle = boolean, macro = macrotext, tooltip = id or var you can use for the functions, notClickable = boolean,
-- submenu = boolean

function DataTextsModule:DropDown(list, frame, parent, ButtonWidth, HideDelay, submenu)
    local SAVE_HEIGHT = E.db.general.fontSize / 3 + 16
    local BUTTON_HEIGHT, BUTTON_WIDTH = 0, 0
    local font = LSM:Fetch("font", E.db.general.font)
    local fontSize = E.db.general.fontSize
    local fontFlag = E.db.general.fontStyle
    autoHideDelay = HideDelay or 2

    -- init frame once
    if not frame.buttons then
        frame.buttons = {}
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        tinsert(_G.UISpecialFrames, frame:GetName())
        frame:Hide()

        -- ElvUI-style background/border
        if frame.SetTemplate then
            frame:SetTemplate("Transparent")
        else
            frame:SetBackdrop({
                bgFile = E.media.blankTex,
                edgeFile = E.media.borderTex,
                tile = false,
                tileSize = 0,
                edgeSize = E.Border,
                insets = { left = E.Spacing, right = E.Spacing, top = E.Spacing, bottom = E.Spacing },
            })
            frame:SetBackdropColor(unpack(E.media.backdropcolor))
            frame:SetBackdropBorderColor(unpack(E.media.bordercolor))
        end
    end

    -- clear old buttons
    for i, _ in ipairs(frame.buttons) do
        frame.buttons[i]:Hide()
        frame.buttons[i] = nil
    end

    -- build buttons
    for i, item in ipairs(list) do
        local btn = frame.buttons[i]
        if not btn then
            if item.macro then
                btn = CreateFrame("Button", "TwichUI_DropdownMacroButton" .. i, frame, "SecureActionButtonTemplate")
            else
                btn = CreateFrame("Button", nil, frame)
            end
            frame.buttons[i] = btn
        end

        btn.submenu = item.submenu

        if item.macro then
            btn:SetAttribute("type", "macro")
            btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
            btn:SetAttribute("macrotext1", item.macro)
            -- btn:SetScript("OnClick", nil)
        elseif not item.notClickable then
            local function OnClick(button)
                if button.func then button.func() end

                local buttonParent = button:GetParent()
                if not button.submenu then
                    buttonParent:Hide()
                elseif buttonParent.timer then
                    buttonParent.timer:Cancel()
                    buttonParent.timer = nil
                end
            end

            btn.func = item.func
            btn:SetAttribute("type", nil)
            btn:RegisterForClicks("LeftButtonUp")
            btn:SetScript("OnClick", OnClick)
        else
            btn:SetAttribute("type", nil)
            btn:SetScript("OnClick", nil)
        end

        if not item.isTitle then
            btn.hoverTex = btn.hoverTex or btn:CreateTexture(nil, "OVERLAY")
            btn.hoverTex:SetAllPoints()
            btn.hoverTex:SetTexture(E.media.blankTex)
            btn.hoverTex:SetVertexColor(1, 1, 1, 0.08) -- subtle light overlay
            btn.hoverTex:SetBlendMode("ADD")
            btn.hoverTex:Hide()

            local function OnLeave(button)
                button.hoverTex:Hide()
                if button.funcOnLeave then button.funcOnLeave(button) end
            end

            local function OnEnter(button)
                button.hoverTex:Show()
                if btn.funcOnEnter then button.funcOnEnter(button) end
            end

            btn.tooltip = item.tooltip
            btn:SetScript("OnEnter", OnEnter)
            btn.funcOnEnter = item.funcOnEnter
            btn:SetScript("OnLeave", OnLeave)
            btn.funcOnLeave = item.funcOnLeave
        else
            btn:SetScript("OnEnter", nil)
            btn:SetScript("OnLeave", nil)
        end

        btn.text = btn.text or btn:CreateFontString(nil, "BORDER")
        btn.text:SetAllPoints()
        btn.text:FontTemplate(font, fontSize, fontFlag)
        btn.text:SetJustifyH("LEFT")

        btn.right_text = btn.right_text or btn:CreateFontString(nil, "BORDER")
        btn.right_text:SetAllPoints()
        btn.right_text:FontTemplate(font, fontSize, fontFlag)
        btn.right_text:SetJustifyH("RIGHT")

        local text = (item.icon and item.text) and (E:TextureString(item.icon, ":14:14") .. " " .. item.text) or
            item.text
        btn.text:SetText(item.color and format("%s%s|r", item.color, text) or text)
        if item.right_text then
            btn.right_text:SetText(item.right_text)
        else
            btn.right_text:SetText("")
        end

        if i == 1 then
            btn:Point("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
        else
            btn:Point("TOPLEFT", frame.buttons[i - 1], "BOTTOMLEFT")
        end

        BUTTON_HEIGHT = max(btn.text:GetStringHeight(), BUTTON_HEIGHT, SAVE_HEIGHT)
        BUTTON_WIDTH = max(btn.text:GetStringWidth() + (btn.right_text and btn.right_text:GetStringWidth() or 0),
            BUTTON_WIDTH, ButtonWidth or 0)

        frame.buttons[i] = btn
    end

    -- size to contents
    for _, btn in ipairs(frame.buttons) do
        btn:Show()
        btn:SetHeight(BUTTON_HEIGHT)
        btn:SetWidth(BUTTON_WIDTH + 2)
    end

    frame:SetHeight((#list * BUTTON_HEIGHT + PADDING * 2))
    frame:SetWidth(BUTTON_WIDTH + PADDING * 2)

    -- anchor relative to parent panel: above it
    frame:ClearAllPoints()
    if parent then
        frame:SetPoint("BOTTOM", parent, "TOP", 0, 4) -- tweak 0,4 as needed
        frame.parent = parent                         -- so DropDownTimer can see the datatext
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end

    if InCombatLockdown() then
        return
    else
        if not frame.timer then
            frame.timer = C_Timer.NewTicker(autoHideDelay, function()
                DropDownTimer(frame)
            end)
        end

        if frame.name ~= submenu then
            frame.name = submenu
            frame:Show()
        else
            ToggleFrame(frame)
        end
    end
end
