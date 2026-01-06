--[[
        DataTexts Developer Configuration
        Controls debug logging for DataText modules.
]]
---@diagnostic disable: need-check-nil
---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local Logger = T:GetModule("Logger")

CM.Developer = CM.Developer or {}

--- @class DeveloperDataTextsConfigurationModule
--- @field Create fun(order:number):table
CM.Developer.DataTexts = CM.Developer.DataTexts or {}

local DataTextsConfig = CM.Developer.DataTexts

function DataTextsConfig:Create(order)
    return {
        type = "group",
        name = "DataTexts",
        order = order,
        args = {
            description = CM.Widgets:SubmoduleDescription(
                "Developer settings for DataText modules (mainly debug logging)."
            ),
            debugLogging = {
                type = "toggle",
                name = "Enable DataText Debug Logging",
                desc = "When enabled, DataText modules will emit debug logs (OnEvent, enable/disable, etc).",
                order = 2,
                width = "full",
                get = function()
                    return CM:GetProfileSettingSafe("developer.datatexts.debugLoggingEnabled", false)
                end,
                set = function(_, value)
                    CM:SetProfileSettingSafe("developer.datatexts.debugLoggingEnabled", value)
                    Logger.Debug("DataText debug logging set to " .. tostring(value))
                end,
            },
        },
    }
end
