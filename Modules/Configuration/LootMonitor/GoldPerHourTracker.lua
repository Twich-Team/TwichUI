--[[
        Gold Per Hour Tracker Configuration
        This configuration section allows the user to customize how the gold per hour tracker functions.
]]
local T, W, I, C = unpack(Twich)
--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
local TT = TM.Text
local CT = TM.Colors

--- @type LootMonitorModule
local LM = T:GetModule("LootMonitor")

--- @type LootMonitorConfigurationModule
CM.LootMonitor = CM.LootMonitor or {}

--- Helper function to safely access the GoldPerHourTracker module
local function GetGPHModule()
    return LM and LM.GoldPerHourTracker
end

--- @class GoldPerHourTrackerConfigurationModule
local GPH = CM.LootMonitor.GoldPerHourTracker or {}
CM.LootMonitor.GoldPerHourTracker = GPH


function GPH:Create()
    return {
        resetWarning = CM.Widgets:ComponentDescription(1,
            TT.Color(CT.TWICH.TEXT_ERROR, "Warning:") ..
            "Changing the Gold Per Hour settings will clear all tracked data, including items and gold received. This action cannot be undone."),
        spacer = CM.Widgets:Spacer(1.5),
        timeFrameGroup = {
            type = "group",
            name = "Time Frame",
            inline = true,
            order = 2,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "These settings configure the time frame that the Gold Per Hour tracker uses to calculate rates.\n\n"
                    ..
                    "Unlike most addons, Gold Per Hour tracker was designed to use a sliding window approach, meaning that it only considers loot and gold received within the last X minutes (configurable below). This provides a more accurate representation of your current earning rate, especially during varied play sessions, and allows the addon to constantly track your gold per hour.\n\n"
                    ..
                    "If you prefer a traditional cumulative approach, you can enable the 'Always On' option below, which will track your gold per hour from the moment you enable the tracker until you disable it. However, keep in mind that this may lead to skewed results over long play sessions and reduced performance due to the accumulation of data."),
                alwaysOnToggle = {
                    type = "toggle",
                    name = "Always On",
                    desc = CM:ColorTextKeywords(
                        "When enabled, the Gold Per Hour tracker will track your earnings continuously from the moment it is enabled, rather than using a sliding time window. This may reduce performance over long sessions as more data is accumulated."),
                    order = 2,
                    get = function()
                        local GPHM = GetGPHModule()
                        return GPHM and CM:GetProfileSettingByConfigEntry(GPHM.CONFIGURATION.ALWAYS_ON) or false
                    end,
                    set = function(_, value)
                        local GPHM = GetGPHModule()
                        if GPHM then
                            CM:SetProfileSettingByConfigEntry(GPHM.CONFIGURATION.ALWAYS_ON, value)
                            GPHM:SetAlwaysOn(value)
                        end
                    end
                },
                windowSize = {
                    type = "range",
                    name = "Window Size (minutes)",
                    desc = CM:ColorTextKeywords(
                        "Sets the size of the sliding time window (in minutes) that the Gold Per Hour tracker uses to calculate rates."),
                    order = 3,
                    min = 1,
                    max = 120,
                    step = 1,
                    bigStep = 30,
                    hidden = function()
                        local GPHM = GetGPHModule()
                        return GPHM and CM:GetProfileSettingByConfigEntry(GPHM.CONFIGURATION.ALWAYS_ON) or false
                    end,
                    get = function()
                        local GPHM = GetGPHModule()
                        local seconds = GPHM and CM:GetProfileSettingByConfigEntry(GPHM.CONFIGURATION.WINDOW_SIZE) or 900
                        return seconds / 60
                    end,
                    set = function(_, value)
                        local GPHM = GetGPHModule()
                        if GPHM then
                            CM:SetProfileSettingByConfigEntry(GPHM.CONFIGURATION.WINDOW_SIZE, value * 60)
                            GPHM:Reset()
                        end
                    end
                }
            }
        },
        performanceGroup = {
            type = "group",
            name = "Performance & Accuracy",
            inline = true,
            order = 3,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "These settings allow you to balance performance and accuracy for the Gold Per Hour tracker.\n\n"
                    ..
                    "Using a periodic ticker can help keep the gold per hour calculation up-to-date, especially during periods of frequent loot and gold acquisition. However, it may introduce a slight performance overhead due to regular computations. The faster the ticker runs, the more accurate the displayed rate will be, but at the cost of increased CPU usage."),
                useTicker = {
                    type = "toggle",
                    name = "Periodic Recalculation",
                    desc = CM:ColorTextKeywords(
                        "When enabled, the Gold Per Hour tracker will periodically recalculate your gold per hour at the interval specified below. This can help keep the displayed rate more accurate during times when loot is not steadily being received."),
                    order = 2,
                    get = function()
                        local GPHM = GetGPHModule()
                        return GPHM and CM:GetProfileSettingByConfigEntry(GPHM.CONFIGURATION.USE_TICKER)
                    end,
                    set = function(_, value)
                        local GPHM = GetGPHModule()
                        if GPHM then
                            CM:SetProfileSettingByConfigEntry(GPHM.CONFIGURATION.USE_TICKER, value)
                            GPHM:SetUseTicker(value)
                        end
                    end
                },
                updateInterval = {
                    type = "range",
                    name = "Update Interval (seconds)",
                    desc = CM:ColorTextKeywords(
                        "Sets the interval (in seconds) at which the Gold Per Hour tracker recalculates your gold per hour when periodic recalculation is enabled."),
                    order = 3,
                    min = 5,
                    max = 120,
                    step = 1,
                    bigStep = 5,
                    hidden = function()
                        local GPHM = GetGPHModule()
                        return GPHM and not CM:GetProfileSettingByConfigEntry(GPHM.CONFIGURATION.USE_TICKER)
                    end,
                    get = function()
                        local GPHM = GetGPHModule()
                        return GPHM and CM:GetProfileSettingByConfigEntry(GPHM.CONFIGURATION.TICK_RATE)
                    end,
                    set = function(_, value)
                        local GPHM = GetGPHModule()
                        if GPHM then
                            CM:SetProfileSettingByConfigEntry(GPHM.CONFIGURATION.TICK_RATE, value)
                            GPHM:SetTickRate(tonumber(value))
                        end
                    end
                }

            }
        }
    }
end
