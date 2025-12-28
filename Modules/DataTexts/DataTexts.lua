local T = unpack(Twich)
local E = unpack(ElvUI)

--- @class DataTextsModule
--- @field Goblin GoblinDataText
--- @field datatexts table
--- @field Menu Menu
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
--- @param onEventFunc fun(panel: table)|nil Event handler (updates text).
--- @param onUpdateFunc fun(panel: table, elapsed: number)|nil OnUpdate handler.
--- @param onClickFunc fun(panel: table, button: string)|nil OnClick handler.
--- @param onEnterFunc fun(panel: table)|nil OnEnter handler (tooltip).
--- @param onLeaveFunc fun(panel: table)|nil OnLeave handler.
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
