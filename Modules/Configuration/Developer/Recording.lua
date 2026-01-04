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

local LSM = T.Libs and T.Libs.LSM

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
            movedNote = {
                type = "description",
                order = 1,
                name = "Mythic+ recording controls have moved to: Developer Tools → Mythic+ Data Recorder.",
            },
        }
    }
end
