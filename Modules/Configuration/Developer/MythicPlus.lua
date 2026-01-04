---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)
---@diagnostic disable: undefined-field, inject-field

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
--- @type ToolsModule
local TM = T:GetModule("Tools")

local LSM = T.Libs and T.Libs.LSM

--- @type DeveloperConfigurationModule
CM.Developer = CM.Developer or {}

--- @class DeveloperMythicPlusConfiguration
local DMP = CM.Developer.MythicPlus or {}
CM.Developer.MythicPlus = DMP

--- Create the Mythic+ developer configuration panels
--- @param order number The order of the panel
function DMP:Create(order)
    return {
        type = "group",
        name = "Mythic+",
        order = order,
        args = {
            description = CM.Widgets:SubmoduleDescription(
                "Developer tools and settings for the Mythic+ module."),

            portalMockGroup = {
                type = "group",
                name = "Portal Spell Mock",
                inline = true,
                order = 5,
                args = {
                    description = CM.Widgets:ComponentDescription(1,
                        "Simulates a dungeon portal spell being present in your spellbook so you can test the Dungeons UI without actually unlocking the portal. This does not modify the real spellbook."),
                    enabled = {
                        type = "toggle",
                        name = "Enable Mock",
                        order = 1,
                        width = "full",
                        get = function()
                            return CM:GetProfileSettingSafe("developer.testing.mythicPlus.portalMock.enabled", false)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.testing.mythicPlus.portalMock.enabled", value)
                            if MythicPlusModule and MythicPlusModule.Dungeons and MythicPlusModule.Dungeons.ClearPortalSpellCache then
                                MythicPlusModule.Dungeons:ClearPortalSpellCache()
                            elseif MythicPlusModule and MythicPlusModule.Dungeons and MythicPlusModule.Dungeons.Refresh then
                                MythicPlusModule.Dungeons:Refresh()
                            end
                        end,
                    },
                    mapId = {
                        type = "input",
                        name = "Map ID (0 = all)",
                        desc =
                        "Set to a specific Challenge Mode mapID to mock only that dungeon, or 0 to apply to all dungeons.",
                        order = 2,
                        width = "full",
                        get = function()
                            return tostring(CM:GetProfileSettingSafe("developer.testing.mythicPlus.portalMock.mapId", 0) or
                            0)
                        end,
                        set = function(_, value)
                            local v = tonumber(value) or 0
                            if v < 0 then v = 0 end
                            CM:SetProfileSettingSafe("developer.testing.mythicPlus.portalMock.mapId", v)
                            if MythicPlusModule and MythicPlusModule.Dungeons and MythicPlusModule.Dungeons.ClearPortalSpellCache then
                                MythicPlusModule.Dungeons:ClearPortalSpellCache()
                            elseif MythicPlusModule and MythicPlusModule.Dungeons and MythicPlusModule.Dungeons.Refresh then
                                MythicPlusModule.Dungeons:Refresh()
                            end
                        end,
                    },
                    spellId = {
                        type = "input",
                        name = "Spell ID",
                        desc =
                        "SpellID to use as the mocked portal spell. For click-testing, pick a spell you actually know; otherwise it may not cast.",
                        order = 3,
                        width = "full",
                        get = function()
                            return tostring(CM:GetProfileSettingSafe("developer.testing.mythicPlus.portalMock.spellId", 0) or
                            0)
                        end,
                        set = function(_, value)
                            local v = tonumber(value) or 0
                            if v < 0 then v = 0 end
                            CM:SetProfileSettingSafe("developer.testing.mythicPlus.portalMock.spellId", v)
                            if MythicPlusModule and MythicPlusModule.Dungeons and MythicPlusModule.Dungeons.ClearPortalSpellCache then
                                MythicPlusModule.Dungeons:ClearPortalSpellCache()
                            elseif MythicPlusModule and MythicPlusModule.Dungeons and MythicPlusModule.Dungeons.Refresh then
                                MythicPlusModule.Dungeons:Refresh()
                            end
                        end,
                    },
                    clearCache = {
                        type = "execute",
                        name = "Clear Portal Cache",
                        desc = "Clears the cached portal-spell lookup results so the UI re-checks immediately.",
                        order = 4,
                        func = function()
                            if MythicPlusModule and MythicPlusModule.Dungeons and MythicPlusModule.Dungeons.ClearPortalSpellCache then
                                MythicPlusModule.Dungeons:ClearPortalSpellCache()
                            elseif MythicPlusModule and MythicPlusModule.Dungeons and MythicPlusModule.Dungeons.Refresh then
                                MythicPlusModule.Dungeons:Refresh()
                            end
                        end,
                    },
                }
            },

            bestInSlotGroup = {
                type = "group",
                name = "Best in Slot",
                inline = true,
                order = 10,
                args = {
                    clearItemCache = {
                        type = "execute",
                        name = "Clear BiS Item Cache",
                        desc = "Clears the stored item source cache so it will rebuild on demand.",
                        order = 1,
                        func = function()
                            if MythicPlusModule.BestInSlot and MythicPlusModule.BestInSlot.ClearItemCache then
                                MythicPlusModule.BestInSlot:ClearItemCache()
                            end
                        end,
                    },
                }
            },
        }
    }
end
