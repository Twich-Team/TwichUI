--[[
        Developer Configuration
        This configuration section allows the manipulation of developer tools and settings.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")

--- @class DeveloperConfigurationModule
--- @field Logger DeveloperLoggerConfigurationModule
CM.Developer = CM.Developer or {}

--- Creates the primary developer configuration panels.
function CM:CreateDeveloperConfiguration()
    local TT = TM.Text
    local CT = TM.Colors
    return {
        type = "group",
        name = "Developer Tools",
        order = 100,
        childGroups = "tab",
        args = {
            moduleDescription = {
                type = "description",
                name =
                    "This module allows access to various developer tools and settings. It is highly recommended to use these tools with caution, as they can " ..
                    TT.Color(CT.TWICH.TERTIARY_ACCENT, "affect") ..
                    " the " ..
                    TT.Color(CT.TWICH.TERTIARY_ACCENT, "stability") ..
                    " and " .. TT.Color(CT.TWICH.TERTIARY_ACCENT, "performance") .. " of the addon.",
                order = 0,
                fontSize = "large",
            },
            loggerGroup = CM.Developer.Logger:Create(1)
        }

    }
end
