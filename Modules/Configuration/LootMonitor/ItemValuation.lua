--[[
        Item Valudation
        This configuration section allows customization of how the loot monitor and its submodules determine the value of items.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type ThirdPartyAPIModule
local TPA = T:GetModule("ThirdPartyAPI")
--- @type LoggerModule
local LM = T:GetModule("Logger")


--- @type LootMonitorConfigurationModule
CM.LootMonitor = CM.LootMonitor or {}

--- @class ItemValudationConfigurationModule
local IV = CM.LootMonitor.ItemValuation or {}
CM.LootMonitor.ItemValuation = IV

--- Creates the configuration panel to configure how items are valuated.
function IV:Create()
    local TT = TM.Text
    local CT = TM.Colors
    return { -- warning text if TSM is not available
        tsmWarning = {
            type = "description",
            name =
                TT.Color(CT.TWICH.TEXT_WARNING,
                    "TradeSkillMaster is not available. The Item Valuation submodule requires TradeSkillMaster to utilize as a pricing tool. Ensure it is installed and enabled."),
            order = 1,
            fontSize = "medium",
            width = "full",
            hidden = function()
                return TPA.TSM:IsAvailable()
            end,
        },
        priceSourceGroup = {
            type = "group",
            name = "Price Source",
            order = 2,
            inline = true,
            hidden = function()
                return not TPA.TSM:IsAvailable()
            end,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    TT.Color(CT.TWICH.SECONDARY_ACCENT, "Loot Monitor") ..
                    " utilizes " ..
                    TT.Color(CT.TWICH.GOLD_ACCENT, "TradeSkillMaster") ..
                    " price sources to determine the value of looted items. " ..
                    "The options below allow configuration of which price source to utilize. Explanations of price sources " ..
                    "can be found on " ..
                    TT.Color(CT.TWICH.GOLD_ACCENT, "TradeSkillMaster's") ..
                    " support page. All " ..
                    TT.Color(CT.TWICH.SECONDARY_ACCENT, "Loot Monitor") ..
                    " " ..
                    TT.Color(CT.TWICH.TERTIARY_ACCENT, "submodules") ..
                    " will utilize this source for determining value of items.\n\nCustom price sources can be configured in " ..
                    TT.Color(CT.TWICH.GOLD_ACCENT, "TradeSkillMaster") .. "."),
                priceSourceSpacer = CM.Widgets:Spacer(2),
                priceSourceSelect = {
                    type = "select",
                    name = "Price Source",
                    desc = "Select the TradeSkillMaster price source to use when determining the value of items.",
                    order = 3,
                    width = 1.5,
                    values = function()
                        local sources = TPA.TSM:GetPriceSources()
                        local values = {}
                        for _, source in ipairs(sources) do
                            values[source] = source
                        end
                        return values
                    end,
                    get = function()
                        return CM:GetProfileSettingSafe("lootMonitor.itemValuation.priceSource", "DBRegionMarketAvg")
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingSafe("lootMonitor.itemValuation.priceSource", value)
                    end,
                },
                priceSourceDescription = {
                    type = "description",
                    order = 4,
                    fontSize = "medium",
                    width = "full",
                    name = function()
                        local priceSource = CM:GetProfileSettingSafe("lootMonitor.itemValuation.priceSource",
                            "DBRegionMarketAvg")
                        local description = TPA.TSM:GetPriceSourceDescription(priceSource)
                        return TT.Color(CT.TWICH.TEXT_SECONDARY, description)
                    end
                }
            }
        },
        conditionalValuationGroup = {
            type = "group",
            name = "Conditional Valuation",
            order = 5,
            inline = true,
            hidden = function()
                return not TPA.TSM:IsAvailable()
            end,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "Conditional valuation allows for more complex item value calculations based on specific conditions."),
                conditionalValuationSpacer = CM.Widgets:Spacer(2),
                junkItemsGroup = {
                    type = "group",
                    name = "Poor Quality Items",
                    order = 3,
                    inline = true,
                    args = {
                        description = CM.Widgets:ComponentDescription(1,
                            "These options apply only to Poor Quality (junk) (grey) items."),
                        junkItemsSpacer = CM.Widgets:Spacer(2),
                        valuationMethodSelect = {
                            type = "select",
                            name = "Valuation Method",
                            desc = "The method to use to determine the value of poor quality items.",
                            order = 3,
                            width = 1.5,
                            values = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS
                                return {
                                    [methods.VENDOR.uid] = methods.VENDOR.name,
                                    [methods.IGNORE.uid] = methods.IGNORE.name,
                                }
                            end,
                            get = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS

                                return CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.junkItems.valuationMethod", methods.VENDOR).uid
                            end,
                            set = function(_, value)
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS
                                local selectedMethod = nil
                                for _, method in pairs(methods) do
                                    if method.uid == value then
                                        selectedMethod = method
                                        break
                                    end
                                end
                                if not selectedMethod then
                                    LM.Error("Failed to set Junk Item valuation method to numeric value " ..
                                        value .. ". Could not determine valuation method object from numeric.")
                                    return
                                end

                                CM:SetProfileSettingSafe(
                                    "lootMonitor.itemValuation.junkItems.valuationMethod", selectedMethod)
                            end,
                        },
                        valuationMethodDescription = {
                            type = "description",
                            order = 4,
                            fontSize = "medium",
                            width = "full",
                            name = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS

                                local method = CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.junkItems.valuationMethod", methods.VENDOR)

                                local description = CM:ColorTextKeywords(method.description)
                                return TT.Color(CT.TWICH.TEXT_SECONDARY, description)
                            end
                        }
                    }
                },
                armorAndWeaponsGroup = {
                    type = "group",
                    name = "Armor and Weapon Items",
                    order = 4,
                    inline = true,
                    args = {
                        description = CM.Widgets:ComponentDescription(1,
                            "These options apply only to Armor and Weapon items, regardless of quality."),
                        spacer = CM.Widgets:Spacer(2),
                        valuationMethodSelect = {
                            type = "select",
                            name = "Valuation Method",
                            desc = "The method to use to determine the value of armor and weapon items.",
                            order = 3,
                            width = 1.5,
                            values = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS
                                local options = {}
                                for _, method in pairs(methods) do
                                    options[method.uid] = method.name
                                end
                                return options
                            end,
                            get = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS

                                return CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.armorAndWeaponItems.valuationMethod",
                                    methods.DISENCHANT_OR_VENDOR).uid
                            end,
                            set = function(_, value)
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS
                                local selectedMethod = nil
                                for _, method in pairs(methods) do
                                    if method.uid == value then
                                        selectedMethod = method
                                        break
                                    end
                                end
                                if not selectedMethod then
                                    LM.Error(
                                        "Failed to set Armor and Weapon Item valuation method to numeric value " ..
                                        value .. ". Could not determine valuation method object from numeric.")
                                    return
                                end

                                CM:SetProfileSettingSafe(
                                    "lootMonitor.itemValuation.armorAndWeaponItems.valuationMethod", selectedMethod)
                            end,
                        },
                        minimumSaleRate = {
                            type = "input",
                            name = "Minimum Sale Rate",
                            desc =
                            "The sale rate of the item must be above this value to use the TradeSkillMaster price source.",
                            order = 4,
                            hidden = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS
                                local method = CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.armorAndWeaponItems.valuationMethod",
                                    methods.DISENCHANT_OR_VENDOR)
                                return method.uid ~= methods.TSM_PRICE_SOURCE_WITH_GATE.uid
                            end,
                            get = function()
                                return tostring(CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.armorAndWeaponItems.minimumSaleRate", 0.010))
                            end,
                            set = function(_, value)
                                CM:SetProfileSettingSafe(
                                    "lootMonitor.itemValuation.armorAndWeaponItems.minimumSaleRate", tonumber(value))
                            end,
                        },
                        valuationMethodDescription = {
                            type = "description",
                            order = 4,
                            fontSize = "medium",
                            width = "full",
                            name = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS

                                local method = CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.armorAndWeaponItems.valuationMethod",
                                    methods.DISENCHANT_OR_VENDOR)

                                local description = CM:ColorTextKeywords(method.description)
                                return TT.Color(CT.TWICH.TEXT_SECONDARY, description)
                            end
                        }
                    },
                },
                remainingItemsGroup = {
                    type = "group",
                    name = "Remaining Items",
                    order = 4,
                    inline = true,
                    args = {
                        description = CM.Widgets:ComponentDescription(1,
                            "These options apply any items that do not fall into the above categories."),
                        spacer = CM.Widgets:Spacer(2),
                        valuationMethodSelect = {
                            type = "select",
                            name = "Valuation Method",
                            desc = "The method to use to determine the value of remaining items.",
                            order = 3,
                            width = 1.5,
                            values = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS
                                local options = {}
                                for _, method in pairs(methods) do
                                    options[method.uid] = method.name
                                end
                                return options
                            end,
                            get = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS

                                return CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.remainingItems.valuationMethod",
                                    methods.TSM_PRICE_SOURCE_WITH_GATE).uid
                            end,
                            set = function(_, value)
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS
                                local selectedMethod = nil
                                for _, method in pairs(methods) do
                                    if method.uid == value then
                                        selectedMethod = method
                                        break
                                    end
                                end
                                if not selectedMethod then
                                    LM.Error(
                                        "Failed to set Remaining Item valuation method to numeric value " ..
                                        value .. ". Could not determine valuation method object from numeric.")
                                    return
                                end

                                CM:SetProfileSettingSafe(
                                    "lootMonitor.itemValuation.remainingItems.valuationMethod", selectedMethod)
                            end,
                        },
                        minimumSaleRate = {
                            type = "input",
                            name = "Minimum Sale Rate",
                            desc =
                            "The sale rate of the item must be above this value to use the TradeSkillMaster price source.",
                            order = 4,
                            hidden = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS
                                local method = CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.remainingItems.valuationMethod",
                                    methods.TSM_PRICE_SOURCE_WITH_GATE)
                                return method.uid ~= methods.TSM_PRICE_SOURCE_WITH_GATE.uid
                            end,
                            get = function()
                                return tostring(CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.remainingItems.minimumSaleRate", 0.010))
                            end,
                            set = function(_, value)
                                CM:SetProfileSettingSafe(
                                    "lootMonitor.itemValuation.remainingItems.minimumSaleRate", tonumber(value))
                            end,
                        },
                        valuationMethodDescription = {
                            type = "description",
                            order = 4,
                            fontSize = "medium",
                            width = "full",
                            name = function()
                                ---@type LootMonitorModule
                                local module = T:GetModule("LootMonitor")
                                local methods = module.ItemValuator.VALUATION_METHODS

                                local method = CM:GetProfileSettingSafe(
                                    "lootMonitor.itemValuation.remainingItems.valuationMethod",
                                    methods.TSM_PRICE_SOURCE_WITH_GATE)

                                local description = CM:ColorTextKeywords(method.description)
                                return TT.Color(CT.TWICH.TEXT_SECONDARY, description)
                            end
                        }
                    }
                }
            }
        }

    }
end
