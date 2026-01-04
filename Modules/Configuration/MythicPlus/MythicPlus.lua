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
    ---@return MythicPlusModule
    local function GetModule()
        ---@type MythicPlusModule
        local module = T:GetModule("MythicPlus")
        return module
    end

    return CM.Widgets:ModuleGroup(order, "Mythic+ (ALPHA)", "This module provides numerous tools for Mythic+ players.",
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
                    dataDescription = CM.Widgets:ComponentDescription(2,
                        "The Mythic+ module needs to be updated for each season to obtain some data unique to it. If the addon has not been updated, it will still funciton, but will be missing some information."
                    ),
                }
            },

            -- Main Window Settings
            mainWindowGroup = {
                type = "group",
                name = TT.Color(CT.TWICH.TERTIARY_ACCENT, "Main Window"),
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
                name = TT.Color(CT.TWICH.TERTIARY_ACCENT, "Dungeons"),
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
                name = TT.Color(CT.TWICH.TERTIARY_ACCENT, "Best in Slot"),
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
                    },

                    notificationsGroup = {
                        type = "group",
                        name = "Notifications",
                        order = 2,
                        args = {
                            description = CM.Widgets:ComponentDescription(0,
                                "Show a notification when you loot an item that matches your selected Best-in-Slot list."),

                            enableGroup = {
                                type = "group",
                                inline = true,
                                name = "Enable",
                                order = 1,
                                args = {
                                    enabled = {
                                        type = "toggle",
                                        name = "Enable BiS Notifications",
                                        desc = CM:ColorTextKeywords(
                                            "When enabled, looted BiS items will trigger a notification."),
                                        width = "full",
                                        order = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.enabled", true)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.enabled", value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationHandler then
                                                if value then
                                                    module.BestInSlotNotificationHandler:Enable()
                                                else
                                                    module.BestInSlotNotificationHandler:Disable()
                                                end
                                            end
                                        end,
                                    },
                                }
                            },

                            soundGroup = {
                                type = "group",
                                inline = true,
                                name = "Sound",
                                desc = CM:ColorTextKeywords(
                                    "Plays when a BiS notification is shown (NEW/UPGRADE/FOUND)."),
                                order = 2,
                                args = {
                                    soundHelp = {
                                        type = "description",
                                        name = CM:ColorTextKeywords(
                                            "This sound is for BiS notifications that happen when you actually loot an item (or when you use the testing buttons)."),
                                        order = 0,
                                        width = "full",
                                    },
                                    soundSelect = {
                                        type = "select",
                                        dialogControl = "LSM30_Sound",
                                        name = "Notification Sound",
                                        desc = CM:ColorTextKeywords(
                                            "Triggers when you actually loot a selected BiS item (or when using the test/force buttons)."),
                                        order = 1,
                                        width = 1.5,
                                        values = function() return LSM and LSM:HashTable("sound") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.notificationSound",
                                                "TwichUI Green Dude Gets Loot")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.notificationSound", value)
                                        end,
                                    },
                                }
                            },

                            availabilityGroup = {
                                type = "group",
                                inline = true,
                                name = "Availability",
                                desc = CM:ColorTextKeywords(
                                    "Notifies when a selected BiS item becomes available to you (before you actually loot it)."),
                                order = 2.5,
                                args = {
                                    availabilityHelp = {
                                        type = "description",
                                        name = CM:ColorTextKeywords(
                                            "These notifications only trigger for items you have selected in your Best-in-Slot list."),
                                        order = 0,
                                        width = "full",
                                    },
                                    rollHelp = {
                                        type = "description",
                                        name = CM:ColorTextKeywords(
                                            "Roll: Shows a notification when a group loot roll starts for a selected BiS item. This does not mean you won the item — it only means the item is being rolled on."),
                                        order = 0.5,
                                        width = "full",
                                    },
                                    availabilityRollEnabled = {
                                        type = "toggle",
                                        name = "Notify on Roll",
                                        desc = CM:ColorTextKeywords(
                                            "Triggers when a group loot roll starts for a selected BiS item (START_LOOT_ROLL)."),
                                        order = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.availabilityRollEnabled", true)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.availabilityRollEnabled", value)
                                        end,
                                    },
                                    availabilityRollSound = {
                                        type = "select",
                                        dialogControl = "LSM30_Sound",
                                        name = "Roll Sound",
                                        desc = CM:ColorTextKeywords(
                                            "Sound for the BiS Available - Roll notification."),
                                        order = 2,
                                        width = 1.5,
                                        values = function() return LSM and LSM:HashTable("sound") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.availabilityRollSound",
                                                "TwichUI Notification 8")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.availabilityRollSound", value)
                                        end,
                                    },
                                    vaultHelp = {
                                        type = "description",
                                        name = CM:ColorTextKeywords(
                                            "Great Vault: Shows a notification when the Great Vault has selectable rewards and one of them matches a selected BiS item."),
                                        order = 2.5,
                                        width = "full",
                                    },
                                    availabilityVaultEnabled = {
                                        type = "toggle",
                                        name = "Notify on Great Vault",
                                        desc = CM:ColorTextKeywords(
                                            "Triggers when the Great Vault updates and you have available rewards; scans the reward items for selected BiS matches."),
                                        order = 3,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.availabilityVaultEnabled", true)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.availabilityVaultEnabled", value)
                                        end,
                                    },
                                    availabilityVaultSound = {
                                        type = "select",
                                        dialogControl = "LSM30_Sound",
                                        name = "Great Vault Sound",
                                        desc = CM:ColorTextKeywords(
                                            "Sound for the BiS Available - Great Vault notification."),
                                        order = 4,
                                        width = 1.5,
                                        values = function() return LSM and LSM:HashTable("sound") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.availabilityVaultSound",
                                                "TwichUI Notification 8")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.availabilityVaultSound", value)
                                        end,
                                    },
                                }
                            },

                            testingGroup = {
                                type = "group",
                                inline = true,
                                name = "Testing",
                                order = 3,
                                args = {
                                    testNotification = {
                                        type = "execute",
                                        name = TT.Color(CT.TWICH.GOLD_ACCENT, "Show Test Notification"),
                                        desc = CM:ColorTextKeywords("Shows a sample BiS notification."),
                                        order = 1,
                                        func = function()
                                            local module = GetModule()
                                            if not module or not module.BestInSlotNotificationFrame then return end

                                            if module.BestInSlotNotificationFrame.Initialize then
                                                module.BestInSlotNotificationFrame:Initialize()
                                            end

                                            if module.BestInSlotNotificationFrame.ShowNotification then
                                                module.BestInSlotNotificationFrame:ShowNotification(
                                                    "|cffa335ee|Hitem:19019::::::::80:::::|h[Preview BiS Item]|h|r",
                                                    "NEW",
                                                    999,
                                                    nil,
                                                    1
                                                )
                                            end
                                        end,
                                    },
                                    pinPreview = {
                                        type = "toggle",
                                        name = TT.Color(CT.TWICH.GOLD_ACCENT, "Toggle Preview Frame"),
                                        desc = CM:ColorTextKeywords(
                                            "Toggles a preview of the BiS notification frame that won't disappear."),
                                        order = 2,
                                        get = function()
                                            local module = GetModule()
                                            return module and module.BestInSlotNotificationFrame and
                                                module.BestInSlotNotificationFrame.previewShown
                                        end,
                                        set = function(_, value)
                                            local module = GetModule()
                                            if not module or not module.BestInSlotNotificationFrame then return end
                                            if value then
                                                module.BestInSlotNotificationFrame:ShowPreview()
                                            else
                                                module.BestInSlotNotificationFrame:HidePreview()
                                            end
                                        end,
                                    },
                                }
                            },

                            frameLayoutGroup = {
                                type = "group",
                                name = "Frame Layout",
                                inline = true,
                                order = 4,
                                args = {
                                    frameWidth = {
                                        type = "range",
                                        name = "Frame Width",
                                        order = 1,
                                        min = 200,
                                        max = 800,
                                        step = 10,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameWidth", 360)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.frameWidth",
                                                value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    frameHeight = {
                                        type = "range",
                                        name = "Frame Height",
                                        order = 2,
                                        min = 20,
                                        max = 200,
                                        step = 5,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameHeight", 60)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.frameHeight",
                                                value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    maxMessages = {
                                        type = "range",
                                        name = "Max Messages",
                                        order = 3,
                                        min = 1,
                                        max = 10,
                                        step = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.maxMessages", 5)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.maxMessages",
                                                value)
                                        end,
                                    },
                                    frameSpacing = {
                                        type = "range",
                                        name = "Message Spacing",
                                        order = 4,
                                        min = 0,
                                        max = 32,
                                        step = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameSpacing", 8)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.frameSpacing",
                                                value)
                                        end,
                                    },
                                }
                            },

                            animationGroup = {
                                type = "group",
                                name = "Animation & Duration",
                                inline = true,
                                order = 5,
                                args = {
                                    displayDuration = {
                                        type = "range",
                                        name = "Display Duration",
                                        desc = "Total time (seconds) the notification stays visible.",
                                        order = 1,
                                        min = 1,
                                        max = 10,
                                        step = 0.5,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.displayDuration", 8)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.displayDuration", value)
                                        end,
                                    },
                                    fadeInTime = {
                                        type = "range",
                                        name = "Fade In Time",
                                        order = 2,
                                        min = 0,
                                        max = 3,
                                        step = 0.05,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.fadeInTime", 0.25)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.fadeInTime",
                                                value)
                                        end,
                                    },
                                    fadeOutTime = {
                                        type = "range",
                                        name = "Fade Out Time",
                                        order = 3,
                                        min = 0,
                                        max = 3,
                                        step = 0.05,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.fadeOutTime", 0.3)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.fadeOutTime",
                                                value)
                                        end,
                                    },
                                    moveInTime = {
                                        type = "range",
                                        name = "Entrance Move Time",
                                        order = 4,
                                        min = 0,
                                        max = 1,
                                        step = 0.02,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.moveInTime", 0.18)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.moveInTime",
                                                value)
                                        end,
                                    },
                                    moveOutTime = {
                                        type = "range",
                                        name = "Exit Move Time",
                                        order = 5,
                                        min = 0,
                                        max = 1,
                                        step = 0.02,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.moveOutTime", 0.18)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.moveOutTime",
                                                value)
                                        end,
                                    },
                                }
                            },

                            appearanceGroup = {
                                type = "group",
                                name = "Appearance",
                                inline = true,
                                order = 6,
                                args = {
                                    frameTexture = {
                                        type = "select",
                                        name = "Frame Texture",
                                        order = 1,
                                        width = 1.5,
                                        dialogControl = "LSM30_Statusbar",
                                        values = function() return LSM and LSM:HashTable("statusbar") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameTexture",
                                                "ElvUI Norm")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.frameTexture",
                                                value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    frameColor = {
                                        type = "color",
                                        name = "Background Color",
                                        order = 2,
                                        hasAlpha = true,
                                        get = function()
                                            local c = CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameColor",
                                                { r = 0, g = 0, b = 0, a = 0.6 })
                                            return tonumber(c.r) or 0, tonumber(c.g) or 0, tonumber(c.b) or 0,
                                                tonumber(c.a) or 0.6
                                        end,
                                        set = function(_, r, g, b, a)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.frameColor",
                                                { r = r, g = g, b = b, a = a })
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    borderColor = {
                                        type = "color",
                                        name = "Border Color",
                                        desc = "Border color used for acquired BiS notifications (NEW/UPGRADE/FOUND).",
                                        order = 3,
                                        hasAlpha = true,
                                        get = function()
                                            local c = CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameBorderColor",
                                                { r = 0.90, g = 0.72, b = 0.20, a = 1 })
                                            return tonumber(c.r) or 1, tonumber(c.g) or 1, tonumber(c.b) or 1,
                                                tonumber(c.a) or 1
                                        end,
                                        set = function(_, r, g, b, a)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameBorderColor",
                                                { r = r, g = g, b = b, a = a })
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    availabilityBorderColor = {
                                        type = "color",
                                        name = "Availability Border Color",
                                        desc =
                                        "Border color used when a BiS item is available via Roll or Great Vault (does not mean you already acquired the item).",
                                        order = 3.1,
                                        hasAlpha = true,
                                        get = function()
                                            local c = CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameBorderColorAvailable",
                                                { r = 0.23, g = 0.62, b = 1.00, a = 1 })
                                            return tonumber(c.r) or 1, tonumber(c.g) or 1, tonumber(c.b) or 1,
                                                tonumber(c.a) or 1
                                        end,
                                        set = function(_, r, g, b, a)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameBorderColorAvailable",
                                                { r = r, g = g, b = b, a = a })
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    borderSize = {
                                        type = "range",
                                        name = "Border Size",
                                        order = 4,
                                        min = 0,
                                        max = 8,
                                        step = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameBorderSize", 1)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.frameBorderSize", value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                }
                            },

                            iconGroup = {
                                type = "group",
                                name = "Icon",
                                inline = true,
                                order = 7,
                                args = {
                                    iconSize = {
                                        type = "range",
                                        name = "Icon Size",
                                        order = 1,
                                        min = 8,
                                        max = 64,
                                        step = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.iconSize", 32)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.iconSize",
                                                value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                }
                            },

                            fontsGroup = {
                                type = "group",
                                name = "Fonts",
                                inline = true,
                                order = 8,
                                args = {
                                    itemFont = {
                                        type = "select",
                                        name = "Item Font",
                                        order = 1,
                                        width = 1.5,
                                        dialogControl = "LSM30_Font",
                                        values = function() return LSM and LSM:HashTable("font") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.itemFont", "Expressway")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.itemFont",
                                                value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    itemFontSize = {
                                        type = "range",
                                        name = "Item Font Size",
                                        order = 2,
                                        min = 8,
                                        max = 32,
                                        step = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.itemFontSize", 14)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.itemFontSize",
                                                value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    detailFont = {
                                        type = "select",
                                        name = "Detail Font",
                                        order = 3,
                                        width = 1.5,
                                        dialogControl = "LSM30_Font",
                                        values = function() return LSM and LSM:HashTable("font") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.detailFont", "Expressway")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.detailFont",
                                                value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                    detailFontSize = {
                                        type = "range",
                                        name = "Detail Font Size",
                                        order = 4,
                                        min = 8,
                                        max = 32,
                                        step = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.detailFontSize", 12)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.detailFontSize", value)
                                            local module = GetModule()
                                            if module and module.BestInSlotNotificationFrame then
                                                module.BestInSlotNotificationFrame:UpdateFrame()
                                            end
                                        end,
                                    },
                                }
                            },

                            growthGroup = {
                                type = "group",
                                name = "Growth",
                                inline = true,
                                order = 10,
                                args = {
                                    growDirection = {
                                        type = "select",
                                        name = "Growth Direction",
                                        order = 1,
                                        values = { UP = "Up", DOWN = "Down" },
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.growDirection", "UP")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("mythicplus.bestInSlot.notifications.growDirection",
                                                value)
                                        end,
                                    },
                                }
                            },
                        }
                    },
                }
            },


        }
    )
end
