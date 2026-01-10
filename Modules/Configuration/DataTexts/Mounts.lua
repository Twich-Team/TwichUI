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

    local function TooltipHide()
        if _G.GameTooltip and _G.GameTooltip.Hide then
            _G.GameTooltip:Hide()
        end
    end

    local function TooltipForMountSpell(spellID)
        return function(row)
            if not _G.GameTooltip or not _G.GameTooltip.SetOwner then return end
            _G.GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if _G.GameTooltip.SetMountBySpellID then
                _G.GameTooltip:SetMountBySpellID(spellID)
            elseif _G.GameTooltip.SetSpellByID then
                _G.GameTooltip:SetSpellByID(spellID)
            end
            _G.GameTooltip:Show()
        end
    end

    local function BuildMountCandidates()
        local list = {}
        table.insert(list, {
            value = 0,
            name = "None",
            icon = nil,
            search = "none",
        })

        local entries = GetModule():GetCollectedMountEntries() or {}
        for _, m in ipairs(entries) do
            local id = tonumber(m.mountID) or 0
            if id > 0 then
                table.insert(list, {
                    value = id,
                    name = tostring(m.name or ""),
                    icon = m.icon,
                    search = tostring(m.name or ""),
                    onEnter = TooltipForMountSpell(m.spellID),
                    onLeave = TooltipHide,
                })
            end
        end

        return list
    end

    local function NotifyOptionsRefresh()
        local ACR = (T.Libs and T.Libs.AceConfigRegistry)
            or _G.LibStub("AceConfigRegistry-3.0-ElvUI", true)
            or _G.LibStub("AceConfigRegistry-3.0", true)
        if ACR and ACR.NotifyChange then
            pcall(ACR.NotifyChange, ACR, "ElvUI")
        end

        ---@diagnostic disable-next-line: undefined-field
        local E = _G.ElvUI and _G.ElvUI[1]
        if E and type(E.RefreshOptions) == "function" then
            pcall(E.RefreshOptions, E)
        end
    end

    local groundSelector = nil
    local flyingSelector = nil

    local function OpenMountSelector(kind)
        local selector = nil
        local configEntry = nil
        local title = nil
        local current = 0

        if kind == "ground" then
            if not groundSelector then
                groundSelector = TM.UI and TM.UI.CreateSearchSelector and
                    TM.UI.CreateSearchSelector("TwichUIMountsGroundSelector", { hint = "Search mounts" }) or nil
            end
            selector = groundSelector
            configEntry = GetModule():GetConfiguration().FAVORITE_GROUND_MOUNT_ID
            title = "Select Ground Mount"
        else
            if not flyingSelector then
                flyingSelector = TM.UI and TM.UI.CreateSearchSelector and
                    TM.UI.CreateSearchSelector("TwichUIMountsFlyingSelector", { hint = "Search mounts" }) or nil
            end
            selector = flyingSelector
            configEntry = GetModule():GetConfiguration().FAVORITE_FLYING_MOUNT_ID
            title = "Select Flying Mount"
        end

        if not selector or type(selector.Open) ~= "function" then
            LM.Warn("Search selector UI is not available; falling back to dropdown")
            return
        end

        current = CM:GetProfileSettingByConfigEntry(configEntry) or 0

        ---@diagnostic disable-next-line: undefined-field
        local E = _G.ElvUI and _G.ElvUI[1]
        local optionsFrame = (E and (E.OptionsUI or E.OptionsFrame)) or _G.UIParent
        selector:Open({
            title = title,
            candidates = BuildMountCandidates(),
            selectedValue = current,
            relativeTo = optionsFrame,
            onSelect = function(value)
                CM:SetProfileSettingByConfigEntry(configEntry, tonumber(value) or 0)
                GetModule():Refresh()
                NotifyOptionsRefresh()
            end,
        })
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
                    type = "execute",
                    name = function()
                        local id = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration()
                            .FAVORITE_GROUND_MOUNT_ID) or 0
                        return "Favorite Ground Mount: " .. tostring(GetModule():GetMountLabelByID(id))
                    end,
                    desc = "Summoned when flying is not allowed.",
                    order = 8,
                    width = "full",
                    disabled = function()
                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().CLICK_SUMMON_ENABLED)
                    end,
                    func = function()
                        OpenMountSelector("ground")
                    end,
                },

                favoriteFlyingMount = {
                    type = "execute",
                    name = function()
                        local id = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration()
                            .FAVORITE_FLYING_MOUNT_ID) or 0
                        return "Favorite Flying Mount: " .. tostring(GetModule():GetMountLabelByID(id))
                    end,
                    desc = "Summoned when flying is allowed.",
                    order = 9,
                    width = "full",
                    disabled = function()
                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().CLICK_SUMMON_ENABLED)
                    end,
                    func = function()
                        OpenMountSelector("flying")
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
