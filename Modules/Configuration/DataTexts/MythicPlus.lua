local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")

--- @type DataTextsConfigurationModule
local DT = CM.DataTexts or {}
CM.DataTexts = DT

--- @class MythicPlusDataTextConfigurationModule
local MPDT = DT.MythicPlus or {}
---@diagnostic disable-next-line: inject-field
DT.MythicPlus = MPDT

function MPDT:Create()
    ---@return MythicPlusDataText module
    local function GetModule()
        return T:GetModule("DataTexts").MythicPlus
    end

    local options = {
        displayGroup = {
            type = "group",
            name = "Display",
            inline = true,
            order = 1,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "Configure the Mythic+ datatext display and tooltip."),

                showKeystone = {
                    type = "toggle",
                    name = "Show Current Keystone",
                    desc = "Include your owned keystone in the datatext.",
                    order = 1.1,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_KEYSTONE) ~= false
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_KEYSTONE, value and true or
                            false)
                        GetModule():Refresh()
                    end,
                },

                showScore = {
                    type = "toggle",
                    name = "Show Mythic+ Score",
                    desc = "Include your overall Mythic+ score in the datatext.",
                    order = 1.2,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_SCORE) ~= false
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_SCORE, value and true or
                            false)
                        GetModule():Refresh()
                    end,
                },

                color = CM.Widgets:DatatextColorSelectorGroup(
                    5,
                    GetModule():GetConfiguration().COLOR_MODE,
                    GetModule():GetConfiguration().CUSTOM_COLOR,
                    function()
                        GetModule():Refresh()
                    end
                ),
            }
        }
    }

    return options
end
