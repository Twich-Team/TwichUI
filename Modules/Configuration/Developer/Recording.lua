--[[
        Recording Configuration
        Developer-only settings related to capturing and exporting data.
]]
---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
---@type LoggerModule
local Logger = T:GetModule("Logger")

--- @type DeveloperConfigurationModule
CM.Developer = CM.Developer or {}

--- @class DeveloperRecordingConfiguration
local DR = CM.Developer.Recording or {}
CM.Developer.Recording = DR

--- Create the recording configuration panels
--- @param order number The order of the panel
function DR:Create(order)
    return {
        type = "group",
        name = "Recording",
        order = order,
        args = {
            description = CM.Widgets:SubmoduleDescription(
                "Recording tools capture in-game data for later review and analysis."
            ),
            mythicPlusGroup = {
                type = "group",
                inline = true,
                name = "Mythic+",
                order = 2,
                args = {
                    description = CM.Widgets:ComponentDescription(1,
                        "Record Mythic+ run data (events and metadata) into a copy/paste export."),
                    toggleRunLogFrame = {
                        type = "execute",
                        name = "Show Run Log",
                        desc = "Shows/hides the export frame for the most recent run log.",
                        order = 2.5,
                        disabled = function()
                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                            if not ok or not mythicPlus or not mythicPlus.RunLogger then
                                return true
                            end
                            if type(mythicPlus.RunLogger.HasRunData) ~= "function" then
                                return true
                            end
                            return not mythicPlus.RunLogger:HasRunData()
                        end,
                        func = function()
                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                            if not ok or not mythicPlus or not mythicPlus.RunLogger then
                                return
                            end
                            if type(mythicPlus.RunLogger.ToggleRunLogFrame) == "function" then
                                mythicPlus.RunLogger:ToggleRunLogFrame()
                            elseif type(mythicPlus.RunLogger.ShowLastRunLog) == "function" then
                                mythicPlus.RunLogger:ShowLastRunLog()
                            end
                        end,
                    },
                    enableRunLogger = {
                        type = "toggle",
                        name = "Enable Run Logger",
                        desc = "Records Mythic+ run events into a copy/paste log on completion. Persists across /reload.",
                        order = 2,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runLogger.enable", false)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLogger.enable", value)
                            -- Legacy key back-compat (older builds)
                            CM:SetProfileSettingSafe("mythicPlus.runLogger.enable", value)

                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                            if ok and mythicPlus and mythicPlus.RunLogger then
                                if value then
                                    if mythicPlus.RunLogger.Initialize then
                                        mythicPlus.RunLogger:Initialize()
                                    elseif mythicPlus.RunLogger.Enable then
                                        mythicPlus.RunLogger:Enable()
                                    end
                                else
                                    if mythicPlus.RunLogger.Disable then
                                        mythicPlus.RunLogger:Disable()
                                    end
                                end
                            else
                                Logger.Debug(
                                    "MythicPlus module not available yet; Run Logger toggle will apply on next load.")
                            end
                        end,
                    },
                },
            },
        }
    }
end
