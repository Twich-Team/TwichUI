--[[
    Menu
    The menu frame is used to create advanced menus within the interface, allowing for submenus, icons, colors,
    and actionable entries (allow user to cast spells and use items).

    The menu appearance is configurable via the Addon Configuration.
]]
local T = unpack(Twich)
local E = unpack(ElvUI)

--- @type DataTextsModule
local DataTextsModule = T:GetModule("DataTexts")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")

-- WoW globals
local _G = _G
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local ToggleFrame = ToggleFrame
local tinsert = tinsert
local wipe = wipe
local type = type
local unpack = unpack
local max = max
local tostring = tostring
local C_Timer = C_Timer
local LibStub = _G.LibStub
local Masque = (LibStub and LibStub("Masque", true)) or _G.Masque

local LSM = E.Libs.LSM

---@class TwichUI_MenuFrame : Frame
---@field parent Frame|nil
---@field anchorButton Button|nil
---@field timer any|nil

---@class TwichUI_MenuButton : Button
---@field isSecure boolean
---@field text FontString
---@field right_text FontString
---@field iconButton TwichUI_MenuIconButton|nil
---@field hoverTex Texture|nil
---@field func fun()|nil
---@field funcOnEnter fun(button:Button)|nil
---@field funcOnLeave fun(button:Button)|nil
---@field submenu any
---@field tooltip any

---@class TwichUI_MenuIconButton : Button
---@field Icon Texture
---@field __masqueAdded boolean|nil

---@class TwichUI_MenuItem
---@field text string
---@field right_text? string
---@field color? string               -- color code prefix e.g. "|cffRRGGBB"
---@field icon? any                  -- texture path or texture id; rendered via E:TextureString
---@field isTitle? boolean
---@field isDescription? boolean
---@field notClickable? boolean
---@field tooltip? any
---@field func? fun()
---@field funcOnEnter? fun(button:Button)
---@field funcOnLeave? fun(button:Button)
---@field submenu? TwichUI_MenuItem[]|fun():TwichUI_MenuItem[]
---@field spell? string|number
---@field item? string|number
---@field macro? string

---@class MenuAppearanceConfig
---@field useElvUIFont boolean
---@field font string
---@field fontSize number
---@field fontFlag string
---@field useElvUITitleFont boolean
---@field titleFont string
---@field titleFontSize number
---@field titleFontFlag string
---@field padding number
---@field iconTextSpacing number
---@field textColor table
---@field titleColor table
---@field hoverAlpha number
---@field autoHideDelay number

--- @class Menu
--- @field CONFIGURATION table<string, ConfigEntry>
--- @field instances table<string, any>
local Menu = DataTextsModule.Menu or {}
DataTextsModule.Menu = Menu

Menu.instances = Menu.instances or {}

Menu.masqueGroup = Menu.masqueGroup or nil

function Menu:_EnsureMasqueGroup()
    if self.masqueGroup then return self.masqueGroup end
    if not Masque or type(Masque.Group) ~= "function" then return nil end

    local ok, group = pcall(Masque.Group, Masque, "TwichUI", "DataText Menus")
    if ok and group then
        self.masqueGroup = group
        return group
    end
    return nil
end

Menu.CONFIGURATION = Menu.CONFIGURATION or {
    USE_ELVUI_FONT = { key = "datatexts.menu.useElvuiFont", default = true },
    FONT = { key = "datatexts.menu.font", default = "Expressway" },
    FONT_SIZE = { key = "datatexts.menu.fontSize", default = 12 },
    FONT_FLAG = { key = "datatexts.menu.fontFlag", default = "OUTLINE" },

    USE_ELVUI_TITLE_FONT = { key = "datatexts.menu.useElvuiTitleFont", default = true },
    TITLE_FONT = { key = "datatexts.menu.titleFont", default = "Expressway" },
    TITLE_FONT_SIZE = { key = "datatexts.menu.titleFontSize", default = 12 },
    TITLE_FONT_FLAG = { key = "datatexts.menu.titleFontFlag", default = "OUTLINE" },

    TEXT_COLOR = { key = "datatexts.menu.textColor", default = { r = 1, g = 1, b = 1 } },
    -- Blizzard default "gold/orange" UI text color (NORMAL_FONT_COLOR): 1.0, 0.82, 0.0
    TITLE_COLOR = { key = "datatexts.menu.titleColor", default = { r = 1, g = 0.82, b = 0 } },

    PADDING = { key = "datatexts.menu.padding", default = 10 },
    ICON_TEXT_SPACING = { key = "datatexts.menu.iconTextSpacing", default = 4 },
    HOVER_ALPHA = { key = "datatexts.menu.hoverAlpha", default = 0.08 },
    AUTO_HIDE_DELAY = { key = "datatexts.menu.autoHideDelay", default = 2 },
}

local function Clamp01(v)
    if v == nil then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

---@param color table|nil
---@return string
local function ToHexColorPrefix(color)
    if not color then return "|cffffffff" end
    local r = Clamp01(color.r or 1)
    local g = Clamp01(color.g or 1)
    local b = Clamp01(color.b or 1)
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

---@return MenuAppearanceConfig
function Menu:GetAppearanceConfig()
    local useElvUIFont = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.USE_ELVUI_FONT)
    local useElvUITitleFont = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.USE_ELVUI_TITLE_FONT)
    local padding = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.PADDING) or 10
    local iconTextSpacing = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.ICON_TEXT_SPACING) or 4
    local hoverAlpha = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.HOVER_ALPHA) or 0.08
    local autoHideDelay = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.AUTO_HIDE_DELAY) or 2

    local textColor = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.TEXT_COLOR) or { r = 1, g = 1, b = 1 }
    local titleColor = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.TITLE_COLOR) or { r = 1, g = 0.82, b = 0 }

    local titleFontPath
    local titleFontSize
    local titleFontFlag
    if useElvUITitleFont then
        local elvFontName = (E.db and E.db.general and E.db.general.font) or "Expressway"
        titleFontPath = LSM:Fetch("font", elvFontName)
        titleFontSize = (E.db and E.db.general and E.db.general.fontSize) or 12
        titleFontFlag = (E.db and E.db.general and E.db.general.fontStyle) or "OUTLINE"
    else
        titleFontPath = LSM:Fetch("font",
            CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.TITLE_FONT) or "Expressway")
        titleFontSize = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.TITLE_FONT_SIZE) or 12
        titleFontFlag = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.TITLE_FONT_FLAG) or "OUTLINE"
    end

    if useElvUIFont then
        local elvFontName = (E.db and E.db.general and E.db.general.font) or "Expressway"
        local elvFontPath = LSM:Fetch("font", elvFontName)
        return {
            useElvUIFont = true,
            font = elvFontPath,
            fontSize = (E.db and E.db.general and E.db.general.fontSize) or 12,
            fontFlag = (E.db and E.db.general and E.db.general.fontStyle) or "OUTLINE",
            useElvUITitleFont = useElvUITitleFont,
            titleFont = titleFontPath,
            titleFontSize = titleFontSize,
            titleFontFlag = titleFontFlag,
            padding = padding,
            iconTextSpacing = iconTextSpacing,
            textColor = textColor,
            titleColor = titleColor,
            hoverAlpha = hoverAlpha,
            autoHideDelay = autoHideDelay,
        }
    end

    return {
        useElvUIFont = false,
        font = LSM:Fetch("font", CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.FONT) or "Expressway"),
        fontSize = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.FONT_SIZE) or 12,
        fontFlag = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.FONT_FLAG) or "OUTLINE",
        useElvUITitleFont = useElvUITitleFont,
        titleFont = titleFontPath,
        titleFontSize = titleFontSize,
        titleFontFlag = titleFontFlag,
        padding = padding,
        iconTextSpacing = iconTextSpacing,
        textColor = textColor,
        titleColor = titleColor,
        hoverAlpha = hoverAlpha,
        autoHideDelay = autoHideDelay,
    }
end

local function ApplyElvUITemplate(frame)
    if frame.SetTemplate then
        frame:SetTemplate("Transparent")
        return
    end

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

local function CancelTimer(menuFrame)
    if menuFrame and menuFrame.timer then
        menuFrame.timer:Cancel()
        menuFrame.timer = nil
    end
end

local function StartAutoHideTimer(menuFrame, delay)
    if not menuFrame or menuFrame.timer then return end

    menuFrame.timer = C_Timer.NewTicker(delay, function()
        local parent = menuFrame.parent
        local anchorButton = menuFrame.anchorButton

        -- hide when not hovered and not hovering the parent panel or the anchor button
        if not menuFrame:IsMouseOver() then
            local hoveringParent = parent and parent.IsMouseOver and parent:IsMouseOver()
            local hoveringAnchor = anchorButton and anchorButton.IsMouseOver and anchorButton:IsMouseOver()
            if not hoveringParent and not hoveringAnchor then
                menuFrame:Hide()
                CancelTimer(menuFrame)
            end
        end
    end)
end

---@class TwichUI_MenuInstance
---@field id string
---@field frame Frame|nil
---@field buttons Button[]|nil
---@field child TwichUI_MenuInstance|nil

---@param id string
---@return TwichUI_MenuInstance
function Menu:Acquire(id)
    if self.instances[id] then
        return self.instances[id]
    end

    local instance = {
        id = id,
        frame = nil,
        buttons = nil,
        child = nil,
    }
    self.instances[id] = instance
    return instance
end

---@param instance TwichUI_MenuInstance
function Menu:_EnsureFrame(instance)
    if instance.frame then return end

    local frame = CreateFrame("Frame", "TwichUI_Menu_" .. tostring(instance.id), UIParent, "BackdropTemplate")
    instance.frame = frame
    instance.buttons = {}

    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()

    ApplyElvUITemplate(frame)
    tinsert(_G.UISpecialFrames, frame:GetName())
end

---@param instance TwichUI_MenuInstance
function Menu:_ClearButtons(instance)
    if not instance.buttons then return end
    for i, _ in ipairs(instance.buttons) do
        ---@type TwichUI_MenuButton|nil
        local btn = instance.buttons[i]
        if btn then
            btn:Hide()
            -- IMPORTANT: never clear the OnClick handler on protected buttons.
            -- Clearing it taints/breaks SecureActionButtonTemplate execution.
            local isProtected = (btn.IsProtected and btn:IsProtected()) or false
            if not isProtected then
                btn:SetScript("OnClick", nil)
            end
            btn:SetScript("PostClick", nil)
            btn:SetScript("OnMouseDown", nil)
            btn:SetScript("OnEnter", nil)
            btn:SetScript("OnLeave", nil)
            btn.func = nil
            btn.funcOnEnter = nil
            btn.funcOnLeave = nil
            btn.submenu = nil
            btn.tooltip = nil
            -- do not nil the object to keep reuse; just keep it hidden
        end
    end
end

---@param btn TwichUI_MenuButton
---@param appearance MenuAppearanceConfig
---@param isTitle boolean
local function EnsureButtonText(btn, appearance, isTitle)
    if not btn.text then
        btn.text = btn:CreateFontString(nil, "BORDER")
        btn.text:SetJustifyH("LEFT")
    end

    if not btn.right_text then
        btn.right_text = btn:CreateFontString(nil, "BORDER")
        btn.right_text:SetJustifyH("RIGHT")
    end

    -- Layout is set per-item since icon presence changes the left inset.
    btn.text:ClearAllPoints()
    btn.right_text:ClearAllPoints()
    btn.text:SetPoint("TOP", btn, "TOP")
    btn.text:SetPoint("BOTTOM", btn, "BOTTOM")
    btn.text:SetPoint("RIGHT", btn, "RIGHT")
    btn.right_text:SetAllPoints(btn)

    if isTitle then
        btn.text:FontTemplate(appearance.titleFont, appearance.titleFontSize, appearance.titleFontFlag)
        btn.right_text:FontTemplate(appearance.titleFont, appearance.titleFontSize, appearance.titleFontFlag)
    else
        btn.text:FontTemplate(appearance.font, appearance.fontSize, appearance.fontFlag)
        btn.right_text:FontTemplate(appearance.font, appearance.fontSize, appearance.fontFlag)
    end
end

---@param menu Menu
---@param btn TwichUI_MenuButton
---@param icon any
---@param size number
local function EnsureIcon(menu, btn, icon, size)
    if not btn.iconButton then
        ---@type TwichUI_MenuIconButton
        local iconButton = CreateFrame("Button", nil, btn)
        iconButton:EnableMouse(false)
        iconButton:SetPoint("LEFT", btn, "LEFT", 0, 0)
        iconButton:SetSize(size, size)

        iconButton.Icon = iconButton:CreateTexture(nil, "ARTWORK")
        iconButton.Icon:SetAllPoints(iconButton)
        iconButton.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        btn.iconButton = iconButton

        local group = menu:_EnsureMasqueGroup()
        if group and not iconButton.__masqueAdded then
            -- Provide regions explicitly so Masque can skin a non-standard button.
            pcall(group.AddButton, group, iconButton, { Icon = iconButton.Icon })
            pcall(group.ReSkin, group)
            iconButton.__masqueAdded = true
        end
    end

    btn.iconButton:SetSize(size, size)
    btn.iconButton.Icon:SetTexture(icon)
    btn.iconButton:Show()
end

---@param btn TwichUI_MenuButton
---@param appearance MenuAppearanceConfig
local function EnsureHover(btn, appearance)
    if btn.hoverTex then return end
    btn.hoverTex = btn:CreateTexture(nil, "OVERLAY")
    btn.hoverTex:SetAllPoints()
    btn.hoverTex:SetTexture(E.media.blankTex)
    btn.hoverTex:SetVertexColor(1, 1, 1, appearance.hoverAlpha or 0.08)
    btn.hoverTex:SetBlendMode("ADD")
    btn.hoverTex:Hide()
end

---@param instance TwichUI_MenuInstance
---@param anchor Frame
---@param list TwichUI_MenuItem[]
---@param opts? table
function Menu:Show(instance, anchor, list, opts)
    if not instance or not anchor or not list then return end
    if InCombatLockdown() then return end

    self:_EnsureFrame(instance)
    ---@type TwichUI_MenuFrame
    local frame = instance.frame

    -- Don't show an empty menu (it would appear as a tiny blank frame)
    if #list == 0 then
        frame:Hide()
        CancelTimer(frame)
        if instance.child and instance.child.frame then
            instance.child.frame:Hide()
            CancelTimer(instance.child.frame)
        end
        return
    end
    local appearance = self:GetAppearanceConfig()
    local padding = appearance.padding or 10
    local iconTextSpacing = appearance.iconTextSpacing or 4

    local ICON_SIZE = 14

    CancelTimer(frame)
    frame.parent = anchor
    frame.anchorButton = nil

    self:_ClearButtons(instance)

    local saveHeight = (appearance.fontSize / 3) + 16
    local buttonHeight = 0
    local buttonWidth = (opts and opts.minWidth) or 0

    for i, item in ipairs(list) do
        ---@type TwichUI_MenuButton|nil
        local btn = instance.buttons[i]

        local isTitle = item.isTitle
        local isDescription = item.isDescription

        local needsSecure = item and (item.macro or item.spell or item.item)
        local btnIsProtected = btn and btn.IsProtected and btn:IsProtected()
        local btnHasOnClick = btn and btn.GetScript and (btn:GetScript("OnClick") ~= nil)

        -- If we need a secure button, ensure we have a *fresh* SecureActionButtonTemplate handler.
        -- If an earlier build ever cleared OnClick, the button becomes tainted/broken.
        if needsSecure and btn and (not btnIsProtected or not btnHasOnClick) then
            btn:Hide()
            instance.buttons[i] = nil
            btn = nil
        end

        if not btn or (needsSecure and (not btn.isSecure)) or ((not needsSecure) and btn.isSecure) then
            if btn then
                btn:Hide()
                instance.buttons[i] = nil
            end

            if needsSecure then
                ---@type TwichUI_MenuButton
                -- IMPORTANT: don't name secure buttons globally.
                -- Global names can collide across rebuilds when a given index flips secure/insecure.
                btn = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
                btn.isSecure = true
            else
                ---@type TwichUI_MenuButton
                btn = CreateFrame("Button", nil, frame)
                btn.isSecure = false
            end
            instance.buttons[i] = btn
        end

        btn:Show()
        btn.submenu = item.submenu
        btn.tooltip = item.tooltip
        btn.func = item.func
        btn.funcOnEnter = item.funcOnEnter
        btn.funcOnLeave = item.funcOnLeave

        EnsureButtonText(btn, appearance, isTitle)

        local rawText = item.text or ""

        local defaultColorPrefix = isTitle and ToHexColorPrefix(appearance.titleColor) or
            ToHexColorPrefix(appearance.textColor)

        local colorPrefix = item.color or defaultColorPrefix
        local displayText = colorPrefix .. rawText .. "|r"

        if item.icon then
            EnsureIcon(self, btn, item.icon, ICON_SIZE)
            btn.text:SetPoint("LEFT", btn, "LEFT", ICON_SIZE + iconTextSpacing, 0)
        else
            if btn.iconButton then btn.iconButton:Hide() end
            btn.text:SetPoint("LEFT", btn, "LEFT", 0, 0)
        end

        btn.text:SetText(displayText)
        btn.right_text:SetText(item.right_text or "")

        local clickable = (not isTitle) and (not isDescription) and (not item.notClickable)

        if clickable then
            EnsureHover(btn, appearance)

            btn:SetAttribute("type", nil)
            btn:SetAttribute("spell", nil)
            btn:SetAttribute("item", nil)
            btn:SetAttribute("macrotext", nil)

            -- Click-specific secure attributes (left click = 1)
            btn:SetAttribute("type1", nil)
            btn:SetAttribute("spell1", nil)
            btn:SetAttribute("item1", nil)
            btn:SetAttribute("macrotext1", nil)

            if btn.isSecure then
                btn:SetScript("OnMouseDown", nil)

                if item.macro then
                    btn:SetAttribute("type", "macro")
                    btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
                    btn:SetAttribute("macrotext1", item.macro)
                elseif item.spell then
                    btn:SetAttribute("type", "spell")
                    btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
                    btn:SetAttribute("spell1", item.spell)
                elseif item.item then
                    btn:SetAttribute("type", "item")
                    btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
                    btn:SetAttribute("item1", item.item)
                end
                -- IMPORTANT: do not touch OnClick on secure buttons.
                btn:SetScript("PostClick", nil)
            else
                btn:SetScript("OnMouseDown", nil)
                btn:RegisterForClicks("LeftButtonUp")
                btn:SetScript("OnClick", function(button)
                    if button.func then button.func() end

                    if button.submenu then
                        -- keep menu open for submenu items
                        CancelTimer(frame)
                    else
                        frame:Hide()
                        CancelTimer(frame)
                        if instance.child and instance.child.frame then
                            instance.child.frame:Hide()
                            CancelTimer(instance.child.frame)
                        end
                    end
                end)
            end

            btn:SetScript("OnEnter", function(button)
                if button.hoverTex then button.hoverTex:Show() end
                CancelTimer(frame)
                if button.funcOnEnter then button.funcOnEnter(button) end

                if button.submenu then
                    local submenuList = button.submenu
                    if type(submenuList) == "function" then
                        submenuList = submenuList()
                    end
                    if type(submenuList) == "table" then
                        Menu:ShowSubmenu(instance, button, submenuList)
                    end
                end
            end)

            btn:SetScript("OnLeave", function(button)
                if button.hoverTex then button.hoverTex:Hide() end
                if button.funcOnLeave then button.funcOnLeave(button) end
                StartAutoHideTimer(frame, appearance.autoHideDelay or 2)
                if instance.child and instance.child.frame then
                    StartAutoHideTimer(instance.child.frame, appearance.autoHideDelay or 2)
                end
            end)
        else
            btn:SetScript("OnClick", nil)
            btn:SetScript("PostClick", nil)
            btn:SetScript("OnMouseDown", nil)
            btn:SetScript("OnEnter", nil)
            btn:SetScript("OnLeave", nil)
            if btn.hoverTex then btn.hoverTex:Hide() end
        end

        if i == 1 then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -padding)
        else
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", instance.buttons[i - 1], "BOTTOMLEFT")
        end

        local iconExtra = item.icon and (ICON_SIZE + iconTextSpacing) or 0
        buttonHeight = max(buttonHeight, btn.text:GetStringHeight(), saveHeight)
        buttonWidth = max(buttonWidth,
            iconExtra + btn.text:GetStringWidth() + (btn.right_text and btn.right_text:GetStringWidth() or 0))
    end

    for _, btn in ipairs(instance.buttons) do
        if btn and btn:IsShown() then
            btn:SetHeight(buttonHeight)
            btn:SetWidth(buttonWidth + 2)
        end
    end

    frame:SetHeight((#list * buttonHeight) + (padding * 2))
    frame:SetWidth(buttonWidth + (padding * 2))

    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", anchor, "TOP", 0, 4)

    frame:Show()
    StartAutoHideTimer(frame, appearance.autoHideDelay or 2)
end

---@param instance TwichUI_MenuInstance
---@param anchorButton Button
---@param list TwichUI_MenuItem[]
function Menu:ShowSubmenu(instance, anchorButton, list)
    if not instance then return end
    if InCombatLockdown() then return end

    if not instance.child then
        instance.child = self:Acquire(instance.id .. "_child")
    end

    self:_EnsureFrame(instance.child)
    ---@type TwichUI_MenuFrame
    local childFrame = instance.child.frame
    childFrame.anchorButton = anchorButton
    childFrame.parent = instance.frame

    local child = instance.child
    self:Show(child, anchorButton, list, { minWidth = 0 })

    childFrame:ClearAllPoints()
    childFrame:SetPoint("TOPLEFT", anchorButton, "TOPRIGHT", 6, 0)
    childFrame:Show()
end

---@param id string
---@param anchor Frame
---@param list TwichUI_MenuItem[]
---@param opts? table
function Menu:Toggle(id, anchor, list, opts)
    local instance = self:Acquire(id)
    self:_EnsureFrame(instance)

    if instance.frame:IsShown() then
        instance.frame:Hide()
        CancelTimer(instance.frame)
        if instance.child and instance.child.frame then
            instance.child.frame:Hide()
            CancelTimer(instance.child.frame)
        end
        return
    end

    self:Show(instance, anchor, list, opts)
end

function Menu:Hide(id)
    local instance = self.instances[id]
    if not instance or not instance.frame then return end
    instance.frame:Hide()
    CancelTimer(instance.frame)
    if instance.child and instance.child.frame then
        instance.child.frame:Hide()
        CancelTimer(instance.child.frame)
    end
end
