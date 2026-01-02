---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)

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
