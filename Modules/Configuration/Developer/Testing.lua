--[[
        Developer Testing Tools
        Tools for simulating in-game events to exercise addon logic.
]]
---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)
---@diagnostic disable: undefined-field

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type LoggerModule
local Logger = T:GetModule("Logger")
---@type LootMonitorModule
local LootMonitor = T:GetModule("LootMonitor")

--- @type DeveloperConfigurationModule
CM.Developer = CM.Developer or {}

--- @class DeveloperTestingConfiguration
local DT = CM.Developer.Testing or {}
CM.Developer.Testing = DT

--- Create the developer testing configuration panels
--- @param order number The order of the panel
function DT:Create(order)
    return {
        type = "group",
        name = "Testing",
        order = order,
        childGroups = "tab",
        args = {
            description = CM.Widgets:SubmoduleDescription(
                "Tools in this tab simulate events so you can test addon logic without needing real in-game triggers."
            ),
            lootSimGroup = {
                type = "group",
                name = "Loot Simulation",
                order = 1,
                args = {
                    lootSimDesc = {
                        type = "description",
                        order = 1,
                        name =
                        "Enter an itemID or an itemLink (recommended). Quantity controls the simulated stack size. This triggers Loot Monitor's normal LOOT_RECEIVED pipeline (valuation, notifications, GPH tracking, etc.).",
                    },
                    itemInput = {
                        type = "input",
                        name = "Item (ID or Link)",
                        desc =
                        "Examples: 19019 or |cffff8000|Hitem:19019::::::::70:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
                        order = 2,
                        width = "full",
                        get = function()
                            return CM:GetProfileSettingSafe("developer.testing.simulateLoot.item", "")
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.testing.simulateLoot.item", value)
                        end,
                    },
                    quantityInput = {
                        type = "range",
                        name = "Quantity",
                        desc = "Quantity to simulate looting.",
                        order = 3,
                        min = 1,
                        max = 200,
                        step = 1,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.testing.simulateLoot.quantity", 1)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.testing.simulateLoot.quantity", value)
                        end,
                    },
                    simulateLoot = {
                        type = "execute",
                        name = "Simulate Loot",
                        desc = "Simulates receiving the specified item.",
                        order = 4,
                        func = function()
                            local item = CM:GetProfileSettingSafe("developer.testing.simulateLoot.item", "")
                            local quantity = CM:GetProfileSettingSafe("developer.testing.simulateLoot.quantity", 1)

                            if type(item) ~= "string" or item:gsub("%s+", "") == "" then
                                Logger.Warn("Simulate Loot: Please enter an itemID or itemLink.")
                                return
                            end

                            LootMonitor:SimulateLoot(item, quantity)
                        end
                    },
                },
            },
        },
    }
end
