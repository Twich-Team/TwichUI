local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local LM = T:GetModule("Logger")

CM.Developer = CM.Developer or {}
--- @class DeveloperDatabasesConfiguration
--- @field Create function function to create the logger configuration panels
CM.Developer.Databases = CM.Developer.Databases or {}

local DatabasesConfig = CM.Developer.Databases

--- Create the logger configuration panels
--- @param order number The order of the logger configuration panel
function DatabasesConfig:Create(order)
    return {
        type = "group",
        name = "Databases",
        order = order,
        args = {
            -- module description
            description = CM.Widgets:SubmoduleDescription(
                "Databases control the function of the entire addon. Proceed at your own risk."),
            clearGroup = {
                type = "group",
                name = "Clear Databases",
                inline = true,
                order = 2,
                args = {
                    clearGoldDB = {
                        type = "execute",
                        name = "Clear Gold Database",
                        order = 1,
                        desc = "Clears all stored gold data for all characters on the account.",
                        func = function()
                            _G.TwichUIGoldDB = {}
                            LM.Info("Cleared TwichUIGoldDB database.")
                        end
                    }
                }
            }
        }
    }
end
