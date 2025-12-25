--[[
        Loot Monitor
        This configuration section allows customization of the loot monitor module and its submodules.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")

--- @class LootMonitorConfigurationModule
--- @field ItemValuation ItemValudationConfigurationModule
--- @field NotableItems NotableItemConfigurationModule
--- @field GoldPerHourTracker GoldPerHourTrackerConfigurationModule
--- @field GoldPerHourFrame GoldPerHourFrameConfigurationModule
CM.LootMonitor = CM.LootMonitor or {}

--- Creates the primary loot monitor configuration panels.
function CM:CreateLootMonitorConfiguration()
    local TT = TM.Text
    local CT = TM.Colors
    return
        CM.Widgets:ModuleGroup(50, "Loot Monitor",
            "This module monitors incoming loot and raw gold, enabling several submodules, such as Notable Item notifications and Gold Per Hour tracking.",
            {
                moduleEnableToggle = {
                    type = "toggle",
                    name = TT.Color(CT.TWICH.SECONDARY_ACCENT, "Enable"),
                    desc = CM:ColorTextKeywords("Enable the Loot Monitor module."),
                    descStyle = "inline",
                    order = 2,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingSafe("lootMonitor.enable", false)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingSafe("lootMonitor.enable", value)
                        --- @type LootMonitorModule
                        local module = T:GetModule("LootMonitor")
                        if value then
                            module:Enable()
                        else
                            module:Disable()
                        end
                    end
                },
                enabledSpacer = CM.Widgets:Spacer(3),
                enabledSubmodulesText = {
                    type = "description",
                    order = 4,
                    name = CM:ColorTextKeywords(
                        "Now that the module is enabled, you can find available submodules to the left, under the module's section."),
                    fontSize = "medium",
                    hidden = function()
                        return not CM:GetProfileSettingSafe("lootMonitor.enable", false)
                    end,
                },

                itemValuationSubmodule = CM.Widgets:SubmoduleGroup(9, "Item Valuation",
                    "The Item Valuation submodule allows customization of how the Loot Monitor and its submodules determine the value of items.",
                    "lootMonitor.enable", nil, nil,
                    CM.LootMonitor.ItemValuation:Create()),

                notableItemsSubmodule = CM.Widgets:SubmoduleGroup(10, "Notable Items",
                    "This submodule will display a notification when a Notable Item is looted. A Notable Item is any item whose value meets or exceeds your configured threshholds.",
                    "lootMonitor.enable", "lootMonitor.notableItems.enable", function(enabled)
                        --- @type LootMonitorModule
                        local LM = T:GetModule("LootMonitor")
                        if enabled then
                            LM.NotableItemNotificationHandler:Enable()
                        else
                            LM.NotableItemNotificationHandler:Disable()
                        end
                    end,
                    CM.LootMonitor.NotableItems:Create()),

                goldPerHourTrackerSubmodule = CM.Widgets:SubmoduleGroup(11, "Gold Per Hour",
                    "This submodule tracks your gold per hour based on loot and raw gold received, providing near real-time gold per hour statistics.",
                    "lootMonitor.enable", "lootMonitor.goldPerHourTracker.enabled", function(enabled)
                        --- @type LootMonitorModule
                        local LM = T:GetModule("LootMonitor")
                        if enabled then
                            LM.GoldPerHourTracker:Enable()
                        else
                            LM.GoldPerHourTracker:Disable()
                        end
                    end,
                    CM.LootMonitor.GoldPerHourTracker:Create()),

                goldPerHourFrameSubmodule = CM.Widgets:SubmoduleGroup(12, "Gold Per Hour Frame",
                    "This submodule provides a visual loot feed frame that displays a real-time list of looted items with sortable columns and gold per hour statistics.",
                    "lootMonitor.enable", "lootMonitor.goldPerHourFrame.enabled", function(enabled)
                        --- @type LootMonitorModule
                        local LM = T:GetModule("LootMonitor")
                        if enabled then
                            LM.GoldPerHourFrame:Enable()
                        else
                            LM.GoldPerHourFrame:Disable()
                        end
                    end,
                    CM.LootMonitor.GoldPerHourFrame:Create()),

            })
end
