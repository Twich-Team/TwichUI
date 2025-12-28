local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM         = T:GetModule("Configuration")
--- @type ToolsModule
local TM         = T:GetModule("Tools")

--- @class GoldGoblinConfigurationModule
--- @field GoldBalancer GoldBalancerConfigurationModule
--- @field GoldTracker GoldTrackerConfigurationModule
local GG         = CM.GoldGoblin or {}
CM.GoldGoblin    = GG

--- @type GoldGoblinModule
local GGM        = T:GetModule("GoldGoblin")

function GG:Create()
    ---@return GoldGoblinModule module
    local function GetGoldGoblinModule()
        return T:GetModule("GoldGoblin")
    end
    local TT = TM.Text
    local CT = TM.Colors
    return
        CM.Widgets:ModuleGroup(40, "Gold Goblin",
            "The Gold Goblin module helps you manage your in-game finances by providing tools such as the Gold Balancer.",
            {
                moduleEnableToggle = {
                    type = "toggle",
                    name = TT.Color(CT.TWICH.SECONDARY_ACCENT, "Enable"),
                    desc = CM:ColorTextKeywords("Enable the Gold Goblin module."),
                    descStyle = "inline",
                    order = 2,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetGoldGoblinModule().CONFIGURATION.ENABLE)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetGoldGoblinModule().CONFIGURATION.ENABLE, value)
                        --- @type GoldGoblinModule
                        local module = T:GetModule("GoldGoblin")
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
                        return not CM:GetProfileSettingByConfigEntry(GetGoldGoblinModule().CONFIGURATION.ENABLE)
                    end,
                },

                goldBalancerSubmodule = CM.Widgets:SubmoduleGroup(9, "Gold Balancer",
                    "The Gold Balancer submodule helps you balance your gold across multiple characters with your warbank.",
                    "goldGoblin.enable", "goldGoblin.goldBalancer.enable", function(enabled)
                        if enabled then
                            GGM.GoldBalancer:Enable()
                        else
                            GGM.GoldBalancer:Disable()
                        end
                    end,
                    GG.GoldBalancer:Create()),

                goldTrackerSubmodule = CM.Widgets:SubmoduleGroup(10, "Gold Tracker",
                    "The Gold Tracker submodule tracks your total gold across all characters on your account.",
                    "goldGoblin.enable", "goldGoblin.goldTracker.enable", function(enabled)
                        if enabled then
                            GGM.GoldTracker:Enable()
                        else
                            GGM.GoldTracker:Disable()
                        end
                    end,
                    GG.GoldTracker:Create()),
            }
        )
end
