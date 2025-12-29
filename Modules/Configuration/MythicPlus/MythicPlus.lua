local T, W, I, C = unpack(Twich)

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")


--- @class MythicPlusConfigurationModule
local MP = CM.MythicPlus or {}
CM.MythicPlus = MP

function MP:Create(order)
    local TT = TM.Text
    local CT = TM.Colors

    ---@return MythicPlusModule module
    local function GetModule()
        return T:GetModule("MythicPlus")
    end

    return CM.Widgets:ModuleGroup(order, "Mythic+", "This module provides numerous tools for Mythic+ players.",
        {
            moduleEnableToggle = {
                type = "toggle",
                name = TT.Color(CT.TWICH.SECONDARY_ACCENT, "Enable"),
                desc = CM:ColorTextKeywords("Enable the Mythic+ module."),
                descStyle = "inline",
                order = 2,
                width = "full",
                get = function()
                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED)
                end,
                set = function(_, value)
                    CM:SetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED, value)
                    local module = GetModule()
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
                    "Now that the module is enabled, you can find available submodules to the left, under the module's section.\n\n"
                ),
                hidden = function()
                    return not CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED)
                end,
            },
        }
    )
end
