local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local LM = T:GetModule("Logger")

--- @type DataTextsConfigurationModule
local DT = CM.DataTexts or {}
CM.DataTexts = DT

--- @class MountsDataTextConfigurationModule
local MDT = DT.Mounts or {}
DT.Mounts = MDT

function MDT:Create()
    ---@return MountsDataText
    local function GetModule()
        return T:GetModule("DataTexts").Mounts
    end

    local options = {
        displayGroup = {
            type = "group",
            name = "Display",
            inline = true,
            order = 1,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "Configure the Mounts datatext label and menu behavior."),

                displayText = {
                    type = "input",
                    name = "Display Text",
                    desc = "Text shown on the datatext panel.",
                    order = 2,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_TEXT) or
                            "Mounts"
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_TEXT,
                            (value and value ~= "") and value or "Mounts")
                        GetModule():Refresh()
                    end,
                },

                showIcon = {
                    type = "toggle",
                    name = "Show Icon",
                    desc = "Prefix the datatext with an icon texture.",
                    order = 3,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_ICON)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_ICON, value and true or
                            false)
                        GetModule():Refresh()
                    end,
                },

                iconTexture = {
                    type = "input",
                    name = "Icon Texture",
                    desc = "Texture path to use when 'Show Icon' is enabled.",
                    order = 4,
                    width = "full",
                    disabled = function()
                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_ICON)
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().ICON_TEXTURE) or
                            "Interface\\Icons\\Ability_Mount_RidingHorse"
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().ICON_TEXTURE,
                            (value and value ~= "") and value or
                            "Interface\\Icons\\Ability_Mount_RidingHorse")
                        GetModule():Refresh()
                    end,
                },

                iconSize = {
                    type = "range",
                    name = "Icon Size",
                    desc = "Icon size (in pixels).",
                    order = 5,
                    min = 8,
                    max = 32,
                    step = 1,
                    disabled = function()
                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_ICON)
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().ICON_SIZE) or 14
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().ICON_SIZE, value or 14)
                        GetModule():Refresh()
                    end,
                },

                iconPadding = {
                    type = "range",
                    name = "Icon Padding",
                    desc = "Spacing between the icon and the text (in pixels).",
                    order = 5.1,
                    min = 0,
                    max = 16,
                    step = 1,
                    disabled = function()
                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_ICON)
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().ICON_PADDING) or 2
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().ICON_PADDING, value or 2)
                        GetModule():Refresh()
                    end,
                },

                openMenuOnHover = {
                    type = "toggle",
                    name = "Open Menu On Hover",
                    desc = "When enabled, hovering the datatext opens the mounts menu.",
                    order = 6,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().OPEN_MENU_ON_HOVER)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().OPEN_MENU_ON_HOVER, value and
                            true or false)
                    end,
                },

                clickSummonEnabled = {
                    type = "toggle",
                    name = "Click Summons Favorite Mount",
                    desc =
                    "When enabled, clicking the datatext summons your configured ground/flying mount based on whether flying is allowed.",
                    order = 7,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().CLICK_SUMMON_ENABLED)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().CLICK_SUMMON_ENABLED, value and
                            true or false)
                    end,
                },

                favoriteGroundMount = {
                    type = "select",
                    name = "Favorite Ground Mount",
                    desc = "Summoned when flying is not allowed.",
                    order = 8,
                    width = "full",
                    disabled = function()
                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().CLICK_SUMMON_ENABLED)
                    end,
                    values = function()
                        return GetModule():GetCollectedMountOptions() or { [0] = "None" }
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().FAVORITE_GROUND_MOUNT_ID)
                            or 0
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().FAVORITE_GROUND_MOUNT_ID,
                            tonumber(value) or 0)
                    end,
                },

                favoriteFlyingMount = {
                    type = "select",
                    name = "Favorite Flying Mount",
                    desc = "Summoned when flying is allowed.",
                    order = 9,
                    width = "full",
                    disabled = function()
                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().CLICK_SUMMON_ENABLED)
                    end,
                    values = function()
                        return GetModule():GetCollectedMountOptions() or { [0] = "None" }
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().FAVORITE_FLYING_MOUNT_ID)
                            or 0
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().FAVORITE_FLYING_MOUNT_ID,
                            tonumber(value) or 0)
                    end,
                },

                color = CM.Widgets:DatatextColorSelectorGroup(
                    12,
                    GetModule():GetConfiguration().COLOR_MODE,
                    GetModule():GetConfiguration().CUSTOM_COLOR,
                    function()
                        GetModule():Refresh()
                    end
                ),
            }
        },

        menuGroup = {
            type = "group",
            name = "Menu",
            inline = true,
            order = 2,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "Configure which mount groups appear and how entries are filtered."),

                showFavorites = {
                    type = "toggle",
                    name = "Show Favorite Mounts",
                    order = 2,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_FAVORITES)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_FAVORITES, value and
                            true or false)
                    end,
                },

                showUtility = {
                    type = "toggle",
                    name = "Show Utility Mounts",
                    order = 3,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_UTILITY)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_UTILITY, value and true
                            or false)
                    end,
                },

                hideUnusable = {
                    type = "toggle",
                    name = "Hide Unusable Mounts",
                    desc = "When enabled, mounts you cannot use in the current context are hidden instead of greyed out.",
                    order = 4,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().HIDE_UNUSABLE)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().HIDE_UNUSABLE, value and true
                            or false)
                    end,
                },

                sortMode = {
                    type = "select",
                    name = "Sort",
                    order = 5,
                    width = "full",
                    values = {
                        journal = "Journal order",
                        name = "Name (A-Z)",
                    },
                    get = function()
                        local mode = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SORT_MODE)
                        return (mode and mode.id) or "journal"
                    end,
                    set = function(_, value)
                        local mode = nil
                        if value == "name" then
                            mode = { id = "name", name = "Name (A-Z)" }
                        else
                            mode = { id = "journal", name = "Journal order" }
                        end
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().SORT_MODE, mode)
                        GetModule():Refresh()
                    end,
                },

                showSwitchFlightStyle = {
                    type = "toggle",
                    name = "Show 'Switch Flight Style'",
                    order = 6,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_SWITCH_FLIGHT_STYLE)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_SWITCH_FLIGHT_STYLE,
                            value and true or false)
                    end,
                },

                hideTipText = {
                    type = "toggle",
                    name = "Hide Tip Text",
                    desc = "Hides the footer tip at the bottom of the Mounts menu.",
                    order = 7,
                    width = "full",
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().HIDE_TIP_TEXT)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().HIDE_TIP_TEXT, value and true
                            or false)
                    end,
                },
            }
        }
    }

    return options
end
