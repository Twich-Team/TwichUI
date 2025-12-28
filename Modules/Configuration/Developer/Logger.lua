--[[
        Logger Configuration
        This configuration section controls various logger settings.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local LM = T:GetModule("Logger")

local LSM = T.Libs.LSM

CM.Developer = CM.Developer or {}
--- @class DeveloperLoggerConfigurationModule
--- @field Create function function to create the logger configuration panels
CM.Developer.Logger = CM.Developer.Logger or {}

local LoggerConfig = CM.Developer.Logger

--- Create the logger configuration panels
--- @param order number The order of the logger configuration panel
function LoggerConfig:Create(order)
    return {
        type = "group",
        name = "Logger",
        order = order,
        args = {
            -- module description
            description = CM.Widgets:SubmoduleDescription("The logger is responsible for all output to the chat window."),
            -- set the logger level
            levelSelect = {
                type = "select",
                name = "Logging Level",
                order = 2,
                desc =
                "Set the logging level to control the amount of information displayed in the chat window. The lower the level, the more information that will be displayed.",
                values = function()
                    -- pull the levels from the logger module and place in a table in numeric order
                    local levels = LM.LEVELS
                    local options = {}
                    for levelName, levelInfo in pairs(levels) do
                        options[levelInfo.levelNumeric] = levelName
                    end
                    return options
                end,
                get = function()
                    return LM.level.levelNumeric
                end,
                set = function(_, value)
                    -- find the level object by by the numeric value
                    local levels = LM.LEVELS
                    local level = nil
                    for _, levelInfo in pairs(levels) do
                        if levelInfo.levelNumeric == value then
                            level = levelInfo
                            break
                        end
                    end
                    if not level then
                        LM.Error("Failed to set Logger level to numeric value " ..
                            value .. ". Could not determine level object from numeric.")
                        return
                    end
                    CM:SetProfileSettingSafe("developer.logger.level", level)
                    LM.level = level
                    LM.Debug("Logger level set to " .. level.name)
                end
            },
            notificationSoundGroup = {
                type = "group",
                name = "Notification Sound",
                inline = true,
                order = 3,
                args = {
                    description = CM.Widgets:SubmoduleDescription(
                        "Configure a sound to be played for certain log levels."
                    ),
                    enableSound = {
                        type = "toggle",
                        name = "Enable Notification Sound",
                        order = 1,
                        desc = "Enable or disable the notification sound for log levels.",
                        get = function()
                            return CM:GetProfileSettingByConfigEntry(
                                LM.CONFIGURATION.SOUND_ENABLE
                            )
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingByConfigEntry(
                                LM.CONFIGURATION.SOUND_ENABLE,
                                value
                            )
                        end
                    },
                    soundLevel = {
                        type = "select",
                        name = "Sound At & Above Level",
                        order = 2,
                        desc = "Select the log level at which the notification sound will be played.",
                        values = function()
                            local levels = LM.LEVELS
                            local options = {}
                            for levelName, levelInfo in pairs(levels) do
                                options[levelInfo.levelNumeric] = levelName
                            end
                            return options
                        end,
                        get = function()
                            local level = CM:GetProfileSettingByConfigEntry(
                                LM.CONFIGURATION.SOUND_AT_LEVEL
                            )
                            return level.levelNumeric
                        end,
                        set = function(_, value)
                            -- find the level object by by the numeric value
                            local levels = LM.LEVELS
                            local level = nil
                            for _, levelInfo in pairs(levels) do
                                if levelInfo.levelNumeric == value then
                                    level = levelInfo
                                    break
                                end
                            end
                            if not level then
                                LM.Error("Failed to set notification Logger level to numeric value " ..
                                    value .. ". Could not determine level object from numeric.")
                                return
                            end
                            CM:SetProfileSettingByConfigEntry(LM.CONFIGURATION.SOUND_AT_LEVEL, level)
                        end
                    },
                    soundSelect = {
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Notification Sound",
                        desc = CM:ColorTextKeywords(
                            "The sound that plays when a log event occurs."),
                        order = 2,
                        values = LSM:HashTable("sound"),
                        get = function()
                            return CM:GetProfileSettingByConfigEntry(LM.CONFIGURATION.SOUND_EFFECT)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingByConfigEntry(LM.CONFIGURATION.SOUND_EFFECT, value)
                        end
                    }
                }
            },
            testLogGroup = {
                type = "group",
                name = "Test Logger",
                inline = true,
                order = 4,
                args = {
                    testDebug = {
                        type = "execute",
                        name = "Test Debug Log",
                        order = 1,
                        desc = "Sends a test debug log message to the chat window.",
                        func = function()
                            LM.Debug("This is a test DEBUG log message.")
                        end
                    },
                    testInfo = {
                        type = "execute",
                        name = "Test Info Log",
                        order = 2,
                        desc = "Sends a test info log message to the chat window.",
                        func = function()
                            LM.Info("This is a test INFO log message.")
                        end
                    },
                    testWarn = {
                        type = "execute",
                        name = "Test Warn Log",
                        order = 3,
                        desc = "Sends a test warn log message to the chat window.",
                        func = function()
                            LM.Warn("This is a test WARN log message.")
                        end
                    },
                    testError = {
                        type = "execute",
                        name = "Test Error Log",
                        order = 4,
                        desc = "Sends a test error log message to the chat window.",
                        func = function()
                            LM.Error("This is a test ERROR log message.")
                        end
                    }
                }
            }
        }
    }
end
