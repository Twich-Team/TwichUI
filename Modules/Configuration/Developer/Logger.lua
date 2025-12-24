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
            }
        }
    }
end
