---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

local _G = _G
local CreateFrame = _G.CreateFrame

--- @class MythicPlusModule
--- @field Database MythicPlusDatabaseSubmodule
--- @field API MythicPlusAPISubmodule
--- @field Dungeons MythicPlusDungeonsSubmodule|nil
--- @field MainWindow MythicPlusMainWindow|nil
--- @field Simulator MythicPlusSimulatorSubmodule
--- @field ScoreCalculator MythicPlusScoreCalculatorSubmodule
--- @field Data MythicPlusDataSubmodule
--- @field DungeonMonitor MythicPlusDungeonMonitorSubmodule
--- @field DataCollector MythicPlusDataCollectorSubmodule
--- @field RunLogger MythicPlusRunLoggerSubmodule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local Logger = T:GetModule("Logger")

--- @class MythicPlusConfiguration
MythicPlusModule.CONFIGURATION = {
    ENABLED = { key = "mythicplus.enabled", default = false, },

    -- Main window
    MAIN_WINDOW_ENABLED = { key = "mythicplus.mainWindow.enabled", default = false, },
    MAIN_WINDOW_LOCKED = { key = "mythicplus.mainWindow.locked", default = false, },
    MAIN_WINDOW_WIDTH = { key = "mythicplus.mainWindow.width", default = 420, },
    MAIN_WINDOW_HEIGHT = { key = "mythicplus.mainWindow.height", default = 320, },
    MAIN_WINDOW_SCALE = { key = "mythicplus.mainWindow.scale", default = 1.0, },
    MAIN_WINDOW_ALPHA = { key = "mythicplus.mainWindow.alpha", default = 1.0, },
    MAIN_WINDOW_FONT = { key = "mythicplus.mainWindow.font", default = "Expressway", },
    MAIN_WINDOW_TITLE_FONT_SIZE = { key = "mythicplus.mainWindow.titleFontSize", default = 14, },
    MAIN_WINDOW_TITLE_TEXT_COLOR = { key = "mythicplus.mainWindow.titleTextColor", default = { r = 1, g = 1, b = 1 }, },

    MAIN_WINDOW_POINT = { key = "mythicplus.mainWindow.point", default = "CENTER", },
    MAIN_WINDOW_RELATIVE_POINT = { key = "mythicplus.mainWindow.relativePoint", default = "CENTER", },
    MAIN_WINDOW_X = { key = "mythicplus.mainWindow.x", default = 0, },
    MAIN_WINDOW_Y = { key = "mythicplus.mainWindow.y", default = 0, },

    -- Dungeons panel
    DUNGEONS_LEFT_COL_WIDTH = { key = "mythicplus.dungeons.leftColWidth", default = 280, },
    DUNGEONS_ROW_TEXTURE = { key = "mythicplus.dungeons.rowTexture", default = "Blizzard", },
    DUNGEONS_ROW_ALPHA = { key = "mythicplus.dungeons.rowAlpha", default = 0.55, },
    DUNGEONS_ROW_COLOR = { key = "mythicplus.dungeons.rowColor", default = { r = 0.08, g = 0.08, b = 0.08 }, },
    DUNGEONS_ROW_HOVER_ALPHA = { key = "mythicplus.dungeons.rowHoverAlpha", default = 0.06, },
    DUNGEONS_ROW_HOVER_COLOR = { key = "mythicplus.dungeons.rowHoverColor", default = { r = 0.12, g = 0.12, b = 0.12 }, },
    DUNGEONS_IMAGE_ZOOM = { key = "mythicplus.dungeons.imageZoom", default = 0.12, },
    DUNGEONS_DETAILS_BG_ALPHA = { key = "mythicplus.dungeons.detailsBgAlpha", default = 0.45, },

    -- Diagnostics
    DUNGEONS_DEBUG = { key = "mythicplus.dungeons.debug", default = false, },
}

local Module = TM.Generics.Module:New(MythicPlusModule.CONFIGURATION)

function MythicPlusModule:Enable()
    if Module:IsEnabled() then return end
    Module:Enable()

    if self.Dungeons and self.Dungeons.Initialize then
        self.Dungeons:Initialize()
    end

    if self.Runs and self.Runs.Initialize then
        self.Runs:Initialize()
    end

    if self.Summary and self.Summary.Initialize then
        self.Summary:Initialize()
    end

    if self.MainWindow and self.MainWindow.Initialize then
        self.MainWindow:Initialize()
    end

    if self.DungeonMonitor and self.DungeonMonitor.Enable then
        self.DungeonMonitor:Enable()
    end

    if self.DataCollector and self.DataCollector.Enable then
        self.DataCollector:Enable()
    end

    -- Developer-only subfeature; initializes based on its own config toggle.
    if self.RunLogger and self.RunLogger.Initialize then
        self.RunLogger:Initialize()
    end

    Logger.Debug("Mythic+ module enabled")
end

function MythicPlusModule:Disable()
    if not Module:IsEnabled() then return end
    Module:Disable()

    if self.MainWindow and self.MainWindow.Disable and self.MainWindow:IsEnabled() then
        self.MainWindow:Disable()
    end

    Logger.Debug("Mythic+ module disabled")
end

function MythicPlusModule:OnInitialize()
    if Module:IsEnabled() then return end

    if CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.ENABLED) then
        self:Enable()
    end
end

function MythicPlusModule:IsEnabled()
    return Module:IsEnabled()
end
