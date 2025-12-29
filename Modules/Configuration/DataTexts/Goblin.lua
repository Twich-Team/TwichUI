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

--- @class GoblinDataTextConfigurationModule
local GDT = DT.Goblin or {}
DT.Goblin = GDT

local DoesAddOnExist = C_AddOns.DoesAddOnExist

local function CreateAddonToggles(startOrder)
    ---@type GoblinDataText
    local module = T:GetModule("DataTexts").Goblin
    local toggles = {}
    ---@type table<string, AddOnEntryConfig>
    local addons = module.SUPPORTED_ADDONS
    local index = startOrder or 1
    for addon, config in pairs(addons) do
        local addonName = addon
        local cfg = config

        toggles[config.prettyName:lower()] = {
            type = "toggle",
            name = cfg.prettyName,
            order = index,
            desc = "Display the " .. cfg.prettyName .. " addon in the menu that appears when you click the datatext.",
            get = function()
                return CM:GetProfileSettingByConfigEntry(module:GetAddonConfigurationEntry(cfg))
            end,
            set = function(_, value)
                CM:SetProfileSettingByConfigEntry(
                    module:GetAddonConfigurationEntry(cfg),
                    value
                )
            end,
            disabled = function()
                if config.availableFunc and type(config.availableFunc) == "function" then
                    return not config.availableFunc()
                else
                    return not DoesAddOnExist(addonName)
                end
            end
        }
        index = index + 1
    end
    return toggles
end

function GDT:Create()
    ---@return GoblinDataText module
    local function GetModule()
        return T:GetModule("DataTexts").Goblin
    end

    local options = {
        displayGroup = {
            type = "group",
            name = "Display",
            inline = true,
            order = 1,
            args = {
                description = CM.Widgets:ComponentDescription(1, "Configure what the datatext displays on the panel."),

                displayText = {
                    type = "input",
                    name = "Display Text",
                    desc = "Text shown when Display Mode is set to Default.",
                    order = 1.5,
                    width = "full",
                    hidden = function()
                        local mode = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE)
                        return not (mode and mode.id == "default")
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_TEXT) or
                            "Goblin"
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_TEXT,
                            (value and value ~= "") and value or "Goblin")
                        GetModule():Refresh()
                    end,
                },

                showIcon = {
                    type = "toggle",
                    name = "Show Icon",
                    desc = "Prefix the datatext with an icon (applies to all display modes).",
                    order = 1.6,
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
                    order = 1.7,
                    width = "full",
                    disabled = function()
                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_ICON)
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().ICON_TEXTURE) or
                            "Interface\\Icons\\INV_Misc_Coin_01"
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().ICON_TEXTURE,
                            (value and value ~= "") and value or "Interface\\Icons\\INV_Misc_Coin_01")
                        GetModule():Refresh()
                    end,
                },

                iconSize = {
                    type = "range",
                    name = "Icon Size",
                    desc = "Icon size (in pixels).",
                    order = 1.8,
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
                    order = 1.9,
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

                displayMode = {
                    type = "select",
                    name = "Display Mode",
                    order = 2,
                    values = function()
                        local modes      = {}
                        local lmEnabled  = CM:GetProfileSettingSafe("lootMonitor.enable", false)
                        local gphEnabled = CM:GetProfileSettingSafe("lootMonitor.goldPerHourTracker.enabled", false)
                        local includeGPH = lmEnabled and gphEnabled

                        for _, mode in pairs(T.DataTexts.Goblin.DisplayModes) do
                            if mode and mode.id then
                                if mode.id == "gph" and not includeGPH then
                                    -- skip GPH if LootMonitor or GPH tracker disabled
                                elseif mode.hidden and type(mode.hidden) == "function" and mode:hidden() then
                                    -- skip other hidden modes
                                else
                                    modes[mode.id] = mode.name
                                end
                            end
                        end
                        return modes
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE).id
                    end,
                    set = function(_, value)
                        local mode = nil

                        for i, data in pairs(T.DataTexts.Goblin.DisplayModes) do
                            if data.id == value then
                                mode = data
                                break
                            end
                        end
                        if not mode then
                            LM.Error("Failed to set Goblin datatext display mode - invalid mode id: " .. tostring(value))
                            return
                        end
                        CM:SetProfileSettingByConfigEntry(
                            GetModule():GetConfiguration().DISPLAY_MODE,
                            mode
                        )
                        GetModule():Refresh()
                    end,
                },

                gphAfterLootEnabled = {
                    type = "toggle",
                    name = "Show GPH After Loot",
                    desc =
                    "After looting, temporarily show Gold Per Hour for a short time, then return to the configured display.",
                    order = 2.1,
                    hidden = function()
                        local lmEnabled  = CM:GetProfileSettingSafe("lootMonitor.enable", false)
                        local gphEnabled = CM:GetProfileSettingSafe("lootMonitor.goldPerHourTracker.enabled", false)
                        if not (lmEnabled and gphEnabled) then
                            return true
                        end

                        local mode = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE)
                        return mode and mode.id == "gph"
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_GPH_AFTER_LOOT)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_GPH_AFTER_LOOT, value)
                    end,
                },

                gphAfterLootDuration = {
                    type = "range",
                    name = "GPH Display Duration",
                    desc = "Seconds to show GPH after loot.",
                    order = 2.2,
                    min = 1,
                    max = 30,
                    step = 1,
                    hidden = function()
                        local lmEnabled  = CM:GetProfileSettingSafe("lootMonitor.enable", false)
                        local gphEnabled = CM:GetProfileSettingSafe("lootMonitor.goldPerHourTracker.enabled", false)
                        if not (lmEnabled and gphEnabled) then
                            return true
                        end

                        local mode = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE)
                        if mode and mode.id == "gph" then
                            return true
                        end

                        return not CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().SHOW_GPH_AFTER_LOOT)
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().GPH_AFTER_LOOT_DURATION)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(GetModule():GetConfiguration().GPH_AFTER_LOOT_DURATION, value)
                    end,
                },
                goldWarning = {
                    type = "description",
                    name = TM.Text.Color(TM.Colors.TWICH.TEXT_ERROR,
                        "To properly display gold amounts, the Gold Tracker submodule within the Gold Goblin module must be enabled."),
                    order = 2.5,
                    hidden = function()
                        -- Use settings state so UI reflects user toggles immediately.
                        local goldGoblinEnabled = CM:GetProfileSettingSafe("goldGoblin.enable", false)
                        local goldTrackerEnabled = CM:GetProfileSettingSafe("goldGoblin.goldTracker.enable", false)
                        local modulesReady = goldGoblinEnabled and goldTrackerEnabled

                        local mode = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE)
                        local isDefault = mode and mode.id == "default"

                        -- Hide when modules are ready OR when display mode is default.
                        -- Show only if (modules not ready) AND (mode is not default).
                        return modulesReady or isDefault
                    end
                },
                goldDisplayMode = {
                    type = "select",
                    name = "Gold Display Mode",
                    order = 3,
                    desc = "Determines how gold amounts are displayed.",
                    hidden = function()
                        local mode = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE)
                        return mode and mode.id == "default"
                    end,
                    values = {
                        full = "Full",
                        short = "Short",
                    },
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().GOLD_DISPLAY_MODE)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(
                            GetModule():GetConfiguration().GOLD_DISPLAY_MODE,
                            value
                        )
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
        },
        addonsGroup = {
            type = "group",
            name = "Addons",
            inline = true,
            order = 2,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "Select which supported addons appear in the datatext's menu that shows when clicked."),
            }
        },
    }

    -- AceConfig requires args keys to be strings; merge toggles into the args table.
    for key, toggle in pairs(CreateAddonToggles(2)) do
        options.addonsGroup.args[key] = toggle
    end

    return options
end
