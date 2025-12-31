---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)

local LSM = T.Libs and T.Libs.LSM

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")

local TT = (TM and TM.Text) or { Color = function(_, text) return text end }
local CT = (TM and TM.Colors) or { TWICH = { SECONDARY_ACCENT = { r = 1, g = 1, b = 1 } } }


--- @class MythicPlusConfigurationModule
local MP = CM.MythicPlus or {}
CM.MythicPlus = MP

function MP:Create(order)
    ---@return MythicPlusModule module
    local function GetModule()
        return T:GetModule("MythicPlus")
    end

    return CM.Widgets:ModuleGroup(order, "Mythic+", "This module provides numerous tools for Mythic+ players.",
        {
            -- General Settings
            generalGroup = {
                type = "group",
                name = "General",
                order = 1,
                inline = true,
                args = {
                    moduleEnableToggle = {
                        type = "toggle",
                        name = "Enable",
                        desc = CM:ColorTextKeywords("Enable the Mythic+ module."),
                        order = 1,
                        descStyle = "inline",
                        width = "full",
                        get = function() return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED) end,
                        set = function(_, value)
                            CM:SetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED, value)
                            local module = GetModule()
                            if value then module:Enable() else module:Disable() end
                        end
                    },
                }
            },

            -- Main Window Settings
            mainWindowGroup = {
                type = "group",
                name = "Main Window",
                order = 2,
                hidden = function() return not CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED) end,
                args = {
                    description = CM.Widgets:ComponentDescription(0,
                        "Configure the appearance and behavior of the main Mythic+ window."),

                    behaviorGroup = {
                        type = "group",
                        name = "Behavior",
                        inline = true,
                        order = 1,
                        args = {
                            showToggle = {
                                type = "toggle",
                                name = "Show Window",
                                desc = CM:ColorTextKeywords("Toggles the Mythic+ main window."),
                                order = 1,
                                width = "full",
                                get = function()
                                    local module = GetModule()
                                    return module.MainWindow and module.MainWindow.IsEnabled and
                                        module.MainWindow:IsEnabled() or
                                        CM:GetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_ENABLED)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    if not module.MainWindow then return end
                                    if value then module.MainWindow:Enable(true) else module.MainWindow:Disable(true) end
                                end,
                            },
                            lockedToggle = {
                                type = "toggle",
                                name = "Lock Window",
                                desc = CM:ColorTextKeywords("When locked, the window cannot be dragged."),
                                order = 2,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .MAIN_WINDOW_LOCKED)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_LOCKED, value)
                                    if module.MainWindow and module.MainWindow.RefreshLayout then
                                        module.MainWindow
                                            :RefreshLayout()
                                    end
                                end,
                            },
                        }
                    },

                    appearanceGroup = {
                        type = "group",
                        name = "Appearance",
                        inline = true,
                        order = 2,
                        args = {
                            frameWidth = {
                                type = "range",
                                name = "Width",
                                order = 1,
                                min = 280,
                                max = 900,
                                step = 10,
                                bigStep = 50,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .MAIN_WINDOW_WIDTH)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_WIDTH, value)
                                    if module.MainWindow and module.MainWindow.RefreshLayout then
                                        module.MainWindow
                                            :RefreshLayout()
                                    end
                                end,
                            },
                            frameHeight = {
                                type = "range",
                                name = "Height",
                                order = 2,
                                min = 200,
                                max = 700,
                                step = 10,
                                bigStep = 50,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .MAIN_WINDOW_HEIGHT)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_HEIGHT, value)
                                    if module.MainWindow and module.MainWindow.RefreshLayout then
                                        module.MainWindow
                                            :RefreshLayout()
                                    end
                                end,
                            },
                            frameScale = {
                                type = "range",
                                name = "Scale",
                                order = 3,
                                min = 0.5,
                                max = 2.0,
                                step = 0.1,
                                bigStep = 0.25,
                                isPercent = true,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .MAIN_WINDOW_SCALE)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_SCALE, value)
                                    if module.MainWindow and module.MainWindow.RefreshLayout then
                                        module.MainWindow
                                            :RefreshLayout()
                                    end
                                end,
                            },
                            frameAlpha = {
                                type = "range",
                                name = "Transparency",
                                order = 4,
                                min = 0.1,
                                max = 1.0,
                                step = 0.05,
                                bigStep = 0.1,
                                isPercent = true,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .MAIN_WINDOW_ALPHA)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_ALPHA, value)
                                    if module.MainWindow and module.MainWindow.RefreshLayout then
                                        module.MainWindow
                                            :RefreshLayout()
                                    end
                                end,
                            },
                        }
                    },

                    typographyGroup = {
                        type = "group",
                        name = "Typography",
                        inline = true,
                        order = 3,
                        args = {
                            font = {
                                type = "select",
                                name = "Font",
                                order = 1,
                                width = 1.5,
                                dialogControl = "LSM30_Font",
                                values = function() return LSM and LSM:HashTable("font") or {} end,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .MAIN_WINDOW_FONT)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_FONT, value)
                                    if module.MainWindow and module.MainWindow.RefreshLayout then
                                        module.MainWindow
                                            :RefreshLayout()
                                    end
                                end,
                            },
                            titleFontSize = {
                                type = "range",
                                name = "Title Font Size",
                                order = 2,
                                min = 10,
                                max = 24,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .MAIN_WINDOW_TITLE_FONT_SIZE)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_TITLE_FONT_SIZE,
                                        value)
                                    if module.MainWindow and module.MainWindow.RefreshLayout then
                                        module.MainWindow
                                            :RefreshLayout()
                                    end
                                end,
                            },
                            titleColor = {
                                type = "color",
                                name = "Title Color",
                                order = 3,
                                get = function()
                                    local c = CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .MAIN_WINDOW_TITLE_TEXT_COLOR) or { r = 1, g = 1, b = 1 }
                                    return c.r, c.g, c.b
                                end,
                                set = function(_, r, g, b)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.MAIN_WINDOW_TITLE_TEXT_COLOR,
                                        { r = r, g = g, b = b })
                                    if module.MainWindow and module.MainWindow.RefreshLayout then
                                        module.MainWindow
                                            :RefreshLayout()
                                    end
                                end,
                            },
                        }
                    }
                }
            },

            -- Dungeons Panel Settings
            dungeonsGroup = {
                type = "group",
                name = "Dungeons",
                order = 3,
                hidden = function() return not CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED) end,
                args = {
                    description = CM.Widgets:ComponentDescription(0, "Customize the display of the Dungeons list."),

                    layoutGroup = {
                        type = "group",
                        name = "Layout",
                        inline = true,
                        order = 1,
                        args = {
                            leftColWidth = {
                                type = "range",
                                name = "Left Column Width",
                                order = 1,
                                min = 180,
                                max = 420,
                                step = 10,
                                bigStep = 20,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_LEFT_COL_WIDTH)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_LEFT_COL_WIDTH, value)
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                            imageZoom = {
                                type = "range",
                                name = "Dungeon Image Zoom",
                                order = 2,
                                min = 0,
                                max = 0.75,
                                step = 0.01,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_IMAGE_ZOOM)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_IMAGE_ZOOM, value)
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                        }
                    },

                    rowStyleGroup = {
                        type = "group",
                        name = "Row Styling",
                        inline = true,
                        order = 2,
                        args = {
                            rowTexture = {
                                type = "select",
                                name = "Texture",
                                order = 1,
                                width = 1.5,
                                dialogControl = "LSM30_Statusbar",
                                values = function() return LSM and LSM:HashTable("statusbar") or {} end,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_ROW_TEXTURE)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_ROW_TEXTURE, value)
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                            rowColor = {
                                type = "color",
                                name = "Color",
                                order = 2,
                                get = function()
                                    local c = CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_ROW_COLOR) or { r = 1, g = 1, b = 1 }
                                    return c.r, c.g, c.b
                                end,
                                set = function(_, r, g, b)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_ROW_COLOR,
                                        { r = r, g = g, b = b })
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                            rowAlpha = {
                                type = "range",
                                name = "Alpha",
                                order = 3,
                                min = 0,
                                max = 1,
                                step = 0.05,
                                isPercent = true,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_ROW_ALPHA)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_ROW_ALPHA, value)
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                            rowHoverColor = {
                                type = "color",
                                name = "Hover Color",
                                order = 4,
                                get = function()
                                    local c = CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_ROW_HOVER_COLOR) or { r = 1, g = 1, b = 1 }
                                    return c.r, c.g, c.b
                                end,
                                set = function(_, r, g, b)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_ROW_HOVER_COLOR,
                                        { r = r, g = g, b = b })
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                            rowHoverAlpha = {
                                type = "range",
                                name = "Hover Alpha",
                                order = 5,
                                min = 0,
                                max = 1,
                                step = 0.05,
                                isPercent = true,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_ROW_HOVER_ALPHA)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_ROW_HOVER_ALPHA,
                                        value)
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                        }
                    },

                    detailsGroup = {
                        type = "group",
                        name = "Details Panel",
                        inline = true,
                        order = 3,
                        args = {
                            detailsBgAlpha = {
                                type = "range",
                                name = "Background Alpha",
                                order = 1,
                                min = 0,
                                max = 1,
                                step = 0.05,
                                isPercent = true,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_DETAILS_BG_ALPHA)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_DETAILS_BG_ALPHA,
                                        value)
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                        }
                    },

                    debugGroup = {
                        type = "group",
                        name = "Debugging",
                        inline = true,
                        order = 4,
                        args = {
                            debugToggle = {
                                type = "toggle",
                                name = "Enable Debug Logs",
                                desc =
                                "Prints extra debug information for dungeon background images (temporary troubleshooting).",
                                order = 1,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .DUNGEONS_DEBUG)
                                end,
                                set = function(_, value)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_DEBUG, value)
                                    if module.Dungeons and module.Dungeons.Refresh then module.Dungeons:Refresh() end
                                end,
                            },
                        }
                    }
                }
            },

            -- Best in Slot Settings
            bestInSlotGroup = {
                type = "group",
                name = "Best in Slot",
                order = 4,
                hidden = function() return not CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED) end,
                args = {
                    databaseGroup = {
                        type = "group",
                        name = "Item Cache",
                        inline = true,
                        order = 1,
                        args = {
                            description = CM.Widgets:ComponentDescription(0,
                                "The addon stores data on item sources from the current season. This data is managed automatically and refreshed any time there is a game update. If for some reason you're having trouble with items, you can try to force a refresh now."),
                            refreshCache = {
                                type = "execute",
                                name = "Refresh Item Cache",
                                desc = CM:ColorTextKeywords(
                                    "Force a rebuild of the item source database from the Encounter Journal."),
                                descStyle = "inline",
                                order = 1,
                                func = function()
                                    local module = GetModule()
                                    if module.BestInSlot and module.BestInSlot.RefreshCache then
                                        module.BestInSlot
                                            :RefreshCache()
                                    end
                                end,
                            },
                        }
                    }
                }
            },
        }
    )
end
