local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")

--- @class DataTextsConfigurationModule
--- @field Goblin GoblinDataTextConfigurationModule
local DT = CM.DataTexts or {}
CM.DataTexts = DT

function DT:Create(order)
    ---@return DataTextsModule module
    local function GetDataTextsModule()
        return T:GetModule("DataTexts")
    end

    local TT = TM.Text
    local CT = TM.Colors

    return CM.Widgets:ModuleGroup(order, "DataTexts",
        "This module provides additional datatexts for use in ElvUI panels.",
        {
            moduleEnableToggle = {
                type = "toggle",
                name = TT.Color(CT.TWICH.SECONDARY_ACCENT, "Enable"),
                desc = CM:ColorTextKeywords("Enable the Datatexts module."),
                descStyle = "inline",
                order = 2,
                width = "full",
                get = function()
                    return CM:GetProfileSettingByConfigEntry(GetDataTextsModule():GetConfiguration().enabled)
                end,
                set = function(_, value)
                    CM:SetProfileSettingByConfigEntry(GetDataTextsModule():GetConfiguration().enabled, value)
                    --- @type DataTextsModule
                    local module = T:GetModule("DataTexts")
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
                    .. "Individual datatexts must be enabled before they will appear in ElvUI's datatext configuration.\n\n"
                    .. "When disabling a datatext submodule, you must reload your UI for the change to fully take effect."),
                fontSize = "medium",
                hidden = function()
                    return not CM:GetProfileSettingByConfigEntry(GetDataTextsModule():GetConfiguration().enabled)
                end,
            },

            goblinSubmodule = CM.Widgets:SubmoduleGroup(10, "Gold Goblin",
                "The Gold Goblin datatext provides quick access to information related to character and account gold, as well as various gold-making activities.",
                "datatexts.enabled", "datatexts.goblin.enable", function(enabled)
                    if enabled then
                        GetDataTextsModule().Goblin:Enable()
                    else
                        GetDataTextsModule().Goblin:Disable()
                    end
                end,
                CM.DataTexts.Goblin:Create()),

        }
    )
end
