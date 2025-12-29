local T = unpack(Twich)
local E = unpack(ElvUI)

-- WoW globals
local _G = _G

--- @class DataTextsModule
--- @field Goblin GoblinDataText
--- @field datatexts table
--- @field Menu Menu
--- @field Mounts MountsDataText
--- @field Portals PortalsDataText
-- DropDown is legacy; prefer DataTextsModule.Menu
local DataTextsModule = T:GetModule("DataTexts")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
-- NOTE: Menu frames are created lazily by the Menu submodule.

local Module = TM.Generics.Module:New({
    enabled = { key = "datatexts.enabled", default = false, },
})

--- @return table<string, ConfigEntry> the configuration for this module.
function DataTextsModule:GetConfiguration()
    return Module.CONFIGURATION
end

DataTextsModule.DefaultColor = {
    r = 1,
    g = 1,
    b = 1
}

--- @class ColorMode
DataTextsModule.ColorMode = {
    ELVUI = { id = "elvui", name = "ElvUI Value Color" },
    CUSTOM = { id = "custom", name = "Custom Color" },
    DEFAULT = { id = "default", name = "Default (white)" },
}

function DataTextsModule:IsEnabled()
    return Module:IsEnabled()
end

function DataTextsModule:Enable()
    -- initialize any submodules that have been enabled previously
    self.Goblin:OnInitialize()
    self.Portals:OnInitialize()
    if self.Mounts and self.Mounts.OnInitialize then
        self.Mounts:OnInitialize()
    end
end

function DataTextsModule:Disable()
    -- Placeholder for future functionality
end

function DataTextsModule:OnInitialize()
    if Module:IsEnabled() then return end
    if CM:GetProfileSettingByConfigEntry(Module.CONFIGURATION.enabled) then
        self:Enable()
    end
end

--- @class ElvUI_DT_Panel : Frame
--- @field text FontString

--- @class ElvUI_DT_Module
--- @field tooltip GameTooltip
--- @field RegisterDatatext fun(name:string, category:string|nil, events:string[]|nil, onEvent:fun(panel:ElvUI_DT_Panel,event:string,...), onUpdate:fun(panel:ElvUI_DT_Panel,elapsed:number)|nil, onClick:function|nil, onEnter:function|nil, onLeave:function|nil)

--- Returns the underlying ElvUI DataText module.
--- @return ElvUI_DT_Module
function DataTextsModule:GetDatatextModule()
    return E:GetModule("DataTexts")
end

--- Registers a new ElvUI datatext using a simplified interface.
--- @param name string Internal datatext name (unique).
--- @param prettyName string|nil Display name shown in ElvUI config.
--- @param events string[]|nil List of events to register for.
--- @param onEventFunc fun(panel: ElvUI_DT_Panel, event: string, ...)|nil Event handler (updates text).
--- @param onUpdateFunc fun(panel: ElvUI_DT_Panel, elapsed: number)|nil OnUpdate handler.
--- @param onClickFunc fun(panel: ElvUI_DT_Panel, button: string)|nil OnClick handler.
--- @param onEnterFunc fun(panel: ElvUI_DT_Panel)|nil OnEnter handler (tooltip).
--- @param onLeaveFunc fun(panel: ElvUI_DT_Panel)|nil OnLeave handler.
function DataTextsModule:NewDataText(name, prettyName, events, onEventFunc, onUpdateFunc, onClickFunc, onEnterFunc,
                                     onLeaveFunc)
    local DT = E:GetModule("DataTexts")
    DT:RegisterDatatext(
        name,
        "TwichUI",          -- category for grouping in ElvUI config
        events or {},       -- event list
        onEventFunc,        -- eventFunc
        onUpdateFunc,       -- onUpdate
        onClickFunc,        -- onClick
        onEnterFunc,        -- onEnter
        onLeaveFunc,        -- onLeave
        prettyName or name, -- localized name in config
        nil                 -- options (none for now)
    )                       -- [web:103][web:106]
end

--- Convenience function to return the default RGB values
--- @return integer the RED value
--- @return integer the GREEN color
--- @return integer the BLUE color
local function GetDefaultRGB()
    return DataTextsModule.DefaultColor.r, DataTextsModule.DefaultColor.g, DataTextsModule.DefaultColor.b
end

--- Colors the provided text with the color configured by the user in their ElvUI settings.
--- @param colorMode any The database storing the datatext settings from ElvUI.
--- @param text string The text to color.
--- @param customColorConfigEntry ConfigEntry|nil The configuration entry for the custom color (if applicable).
--- @return string The provided text formatted the configured color.
function DataTextsModule:ColorTextByElvUISetting(colorMode, text, customColorConfigEntry)
    if not colorMode then
        return text
    end

    local r, g, b = GetDefaultRGB()
    local LM = T:GetModule("Logger")

    if colorMode.id == DataTextsModule.ColorMode.ELVUI.id then
        -- ElvUI's value color (db.general.valuecolor or E.media.rgbvaluecolor depending on version)
        local vc = E.db and E.db.general and E.db.general.valuecolor
        if not vc then vc = E.media and E.media.rgbvaluecolor end
        if vc then
            r, g, b = vc.r, vc.g, vc.b
        end
    elseif colorMode.id == DataTextsModule.ColorMode.CUSTOM.id and customColorConfigEntry then
        local customColor = CM:GetProfileSettingByConfigEntry(customColorConfigEntry) or GetDefaultRGB()

        r, g, b = customColor.r or 1, customColor.g or 1, customColor.b or 1
    end

    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

--- Checks the ElvUI DataTexts registry to see if a datatext with the given name is registered.
--- @param name string The internal name of the datatext to check.
--- @return boolean True if the datatext is registered, false otherwise.
function DataTextsModule:IsDataTextRegistered(name)
    local DT = E:GetModule("DataTexts")
    return DT.RegisteredDataTexts and DT.RegisteredDataTexts[name] ~= nil
end

--- Removes a previously registered ElvUI datatext and refreshes the options UI.
--- @param name string Internal datatext name to remove.
function DataTextsModule:RemoveDataText(name)
    local DT = E:GetModule("DataTexts")
    if DT.RegisteredDataTexts then
        DT.RegisteredDataTexts[name] = nil
    end

    -- If ElvUI provides an explicit removal API, prefer it.
    if type(DT.RemoveDataText) == "function" then
        pcall(DT.RemoveDataText, DT, name)
    end

    -- Notify AceConfig to refresh ElvUI's options so dropdowns update.
    local ACR = (T.Libs and T.Libs.AceConfigRegistry)
        or _G.LibStub("AceConfigRegistry-3.0-ElvUI", true)
        or _G.LibStub("AceConfigRegistry-3.0", true)
    if ACR and ACR.NotifyChange then
        pcall(ACR.NotifyChange, ACR, "ElvUI")
    end

    -- Ask ElvUI to rebuild options if supported.
    if E and type(E.RefreshOptions) == "function" then
        pcall(E.RefreshOptions, E)
    end
end

-- -----------------------------------------------------------------------------
-- Masque (optional) support for Datatext icons
--
-- NOTE:
-- - Masque skins Buttons, not FontString texture markup (|T...|t).
-- - We provide a single shared icon button per ElvUI datatext panel.
-- - The icon button self-hides if the panel text changes (e.g. the panel is
--   switched to a different datatext in ElvUI) to avoid “icon leakage”.
-- -----------------------------------------------------------------------------

local MASQUE_GROUP_NAME = "TwichUI"
local MASQUE_SUBGROUP_NAME = "DataTexts"

---@class TwichUI_DatatextIconButton : Button
---@field Icon Texture
---@field __twichuiElapsed number

---@class ElvUI_DT_Panel_TwichUI : ElvUI_DT_Panel
---@field __twichuiDatatextIconButton TwichUI_DatatextIconButton|nil
---@field __twichuiDatatextIconExpectedText string|nil

---@return any|nil masqueGroup
function DataTextsModule:GetMasqueDatatextGroup()
    if self.__twichuiMasqueDatatextGroup ~= nil then
        return self.__twichuiMasqueDatatextGroup
    end

    local LibStub = _G.LibStub
    if type(LibStub) ~= "function" then
        self.__twichuiMasqueDatatextGroup = false
        return nil
    end

    local MSQ = LibStub("Masque", true)
    if not MSQ or type(MSQ.Group) ~= "function" then
        self.__twichuiMasqueDatatextGroup = false
        return nil
    end

    local ok, group = pcall(MSQ.Group, MSQ, MASQUE_GROUP_NAME, MASQUE_SUBGROUP_NAME)
    if ok and group then
        self.__twichuiMasqueDatatextGroup = group
        return group
    end

    self.__twichuiMasqueDatatextGroup = false
    return nil
end

---@param panel ElvUI_DT_Panel_TwichUI
---@return TwichUI_DatatextIconButton|nil
function DataTextsModule:EnsureDatatextIconButton(panel)
    if not panel then return nil end

    if panel.__twichuiDatatextIconButton then
        return panel.__twichuiDatatextIconButton
    end

    local CreateFrame = _G.CreateFrame
    if type(CreateFrame) ~= "function" then
        return nil
    end

    ---@class TwichUI_DatatextIconButton
    local btn = CreateFrame("Button", nil, panel)
    btn:EnableMouse(false)
    btn:SetFrameStrata(panel.GetFrameStrata and panel:GetFrameStrata() or "LOW")
    btn:SetFrameLevel((panel.GetFrameLevel and panel:GetFrameLevel() or 1) + 8)

    btn.Icon = btn:CreateTexture(nil, "OVERLAY")
    btn.Icon:SetAllPoints(btn)
    btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.__twichuiElapsed = 0
    btn:SetScript("OnUpdate", function(self, elapsed)
        self.__twichuiElapsed = (self.__twichuiElapsed or 0) + (elapsed or 0)
        if self.__twichuiElapsed < 0.25 then return end
        self.__twichuiElapsed = 0

        local parent = self:GetParent()
        local expected = parent and parent.__twichuiDatatextIconExpectedText
        local textObj = parent and parent.text
        local current = (textObj and textObj.GetText) and textObj:GetText() or nil

        if not expected or not current or current ~= expected then
            self:Hide()
        end
    end)

    panel.__twichuiDatatextIconButton = btn

    -- Register with Masque if available.
    local group = self:GetMasqueDatatextGroup()
    if group and type(group.AddButton) == "function" then
        pcall(group.AddButton, group, btn, { Icon = btn.Icon })
    end

    return btn
end

---@param panel ElvUI_DT_Panel_TwichUI
---@param show boolean
---@param iconTexture string|nil
---@param iconSize number|nil
---@param padding number|nil
---@param expectedText string|nil
function DataTextsModule:UpdateDatatextIcon(panel, show, iconTexture, iconSize, padding, expectedText)
    if not panel then return end

    -- Store the expected panel text so the icon can self-hide when the panel swaps.
    panel.__twichuiDatatextIconExpectedText = expectedText

    if not show or not iconTexture then
        if panel.__twichuiDatatextIconButton then
            panel.__twichuiDatatextIconButton:Hide()
        end
        return
    end

    local btn = self:EnsureDatatextIconButton(panel)
    if not btn or not btn.Icon then return end

    iconSize = tonumber(iconSize) or 14
    padding = tonumber(padding)
    if padding == nil then padding = 2 end
    btn:SetSize(iconSize, iconSize)
    btn.Icon:SetTexture(iconTexture)

    btn:ClearAllPoints()

    -- Anchor relative to the *rendered string*, not the FontString's full width.
    -- Many ElvUI datatext panels use a FontString that spans the whole panel.
    if panel.text and panel.text.GetStringWidth then
        local stringWidth = panel.text:GetStringWidth() or 0
        if stringWidth > 0 then
            btn:SetPoint("RIGHT", panel.text, "CENTER", -(stringWidth / 2) - padding, 0)
        else
            btn:SetPoint("RIGHT", panel.text, "LEFT", -padding, 0)
        end
    else
        btn:SetPoint("LEFT", panel, "LEFT", 2, 0)
    end

    btn:Show()
end
