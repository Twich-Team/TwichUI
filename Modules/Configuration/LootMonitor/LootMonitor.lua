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
                    desc = "Enable the Loot Monitor module.",
                    descStyle = "inline",
                    order = 2,
                    icon = "Interface\\AddOns\\TwichUI\\Media\\Textures\\gold-coin",
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
                    CM.LootMonitor.ItemValuation:Create(1)),

            })
end
