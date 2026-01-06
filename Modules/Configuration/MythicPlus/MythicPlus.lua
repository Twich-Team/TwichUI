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
                                name = "Opacity",
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
                            pieChartColor = {
                                type = "color",
                                name = "Pie Chart Color",
                                order = 2,
                                get = function()
                                    local c = CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                    .DUNGEONS_PIE_CHART_COLOR) or { r = 0, g = 0.44, b = 0.87 }
                                    return c.r, c.g, c.b
                                end,
                                set = function(_, r, g, b)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.DUNGEONS_PIE_CHART_COLOR,
                                        { r = r, g = g, b = b })
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

            -- Runs Panel Settings
            runsGroup = {
                type = "group",
                name = TT.Color(CT.TWICH.TERTIARY_ACCENT, "Runs"),
                order = 3.5,
                hidden = function() return not CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED) end,
                args = {
                    description = CM.Widgets:ComponentDescription(0,
                        "Customize the Runs panel and the Run Details popup."),

                    runDetailsGroup = {
                        type = "group",
                        name = "Run Details",
                        inline = true,
                        order = 1,
                        args = {
                            labelColor = {
                                type = "color",
                                name = "Label Color",
                                desc = "Controls the color of labels like Date/Time/Loot/Group in the Run Details popup.",
                                order = 1,
                                get = function()
                                    local c = CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION
                                        .RUN_DETAILS_LABEL_COLOR) or { r = 1, g = 1, b = 1 }
                                    return c.r, c.g, c.b
                                end,
                                set = function(_, r, g, b)
                                    local module = GetModule()
                                    CM:SetProfileSettingByConfigEntry(module.CONFIGURATION.RUN_DETAILS_LABEL_COLOR,
                                        { r = r, g = g, b = b })

                                    -- Best-effort live update if the Runs panel and/or details frame exists.
                                    if module and module.MainWindow and module.MainWindow.GetPanelFrame then
                                        local panel = module.MainWindow:GetPanelFrame("runs")
                                        local details = panel and rawget(panel, "__twichuiRunDetailsFrame")
                                        if details and details.ApplyLabelColors then
                                            details:ApplyLabelColors()
                                        end
                                    end
                                end,
                            },
                        },
                    },
                },
            },

            -- Best in Slot Settings
            bestInSlotGroup = {
                type = "group",
                name = TT.Color(CT.TWICH.TERTIARY_ACCENT, "Best in Slot"),
                order = 4,
                childGroups = "tab",
                hidden = function() return not CM:GetProfileSettingByConfigEntry(GetModule().CONFIGURATION.ENABLED) end,
                args = {
                    missingItemsTab = {
                        type = "group",
                        name = "Missing Items",
                        order = 2,
                        args = {
                            chatOutputGroup = {
                                type = "group",
                                name = "Chat Output",
                                inline = true,
                                order = 1,
                                args = {
                                    printMissingOnEntry = {
                                        type = "toggle",
                                        name = "Display BiS Dropped from Instance in Chat When Entering",
                                        desc = CM:ColorTextKeywords(
                                            "When enabled, entering a dungeon or raid will print a list of your missing Best-in-Slot items for that instance (including boss when known)."),
                                        width = "full",
                                        order = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.printMissingOnInstanceEntry", true)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.printMissingOnInstanceEntry", value)
                                        end,
                                    },
                                },
                            },

                            entryDisplayGroup = {
                                type = "group",
                                name = "On-Screen Display",
                                inline = true,
                                order = 2,
                                args = {
                                    help = {
                                        type = "description",
                                        order = 0,
                                        width = "full",
                                        name = CM:ColorTextKeywords(
                                            "These settings control the on-screen list shown when entering a dungeon or raid. Use the ElvUI mover named 'TwichUI BiS Entry Display' to reposition it."),
                                    },
                                    enabled = {
                                        type = "toggle",
                                        name = "Show Missing BiS on Screen When Entering",
                                        desc = CM:ColorTextKeywords(
                                            "When enabled, entering a dungeon or raid will show an on-screen list of your missing Best-in-Slot items for that instance (including boss when known)."),
                                        width = "full",
                                        order = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                    },
                                    test = {
                                        type = "execute",
                                        name = "Test Display",
                                        desc = CM:ColorTextKeywords(
                                            "Shows a test on-screen list immediately (also creates the ElvUI mover after the first run)."),
                                        order = 1.1,
                                        func = function()
                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.TestEntryDisplay then
                                                module.BestInSlot:TestEntryDisplay()
                                            end
                                        end,
                                    },
                                    durationSec = {
                                        type = "range",
                                        name = "Display Duration (seconds)",
                                        desc = CM:ColorTextKeywords(
                                            "How long the on-screen list stays visible after entering an instance."),
                                        order = 2,
                                        min = 5,
                                        max = 120,
                                        step = 5,
                                        bigStep = 15,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.durationSec", 45)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.durationSec", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                    growDirection = {
                                        type = "select",
                                        name = "Grow Direction",
                                        desc = CM:ColorTextKeywords(
                                            "Whether the list grows up or down from the anchor."),
                                        order = 3,
                                        width = "full",
                                        values = { UP = "Up", DOWN = "Down" },
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.growDirection", "UP")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.growDirection", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                    frameSpacing = {
                                        type = "range",
                                        name = "Row Spacing",
                                        desc = CM:ColorTextKeywords("Spacing between item rows."),
                                        order = 4,
                                        min = 0,
                                        max = 20,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.frameSpacing", 6)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.frameSpacing", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                    appearanceHeader = {
                                        type = "header",
                                        name = "Appearance",
                                        order = 6,
                                    },

                                    backgroundTexture = {
                                        type = "select",
                                        dialogControl = "LSM30_Statusbar",
                                        name = "Row Texture",
                                        desc = CM:ColorTextKeywords("Background texture used for each row."),
                                        order = 6.1,
                                        width = "full",
                                        values = function() return LSM and LSM:HashTable("statusbar") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.backgroundTexture", "ElvUI Norm")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.backgroundTexture", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    backgroundColor = {
                                        type = "color",
                                        name = "Row Color",
                                        desc = CM:ColorTextKeywords("Row background color (includes alpha)."),
                                        hasAlpha = true,
                                        order = 6.2,
                                        width = "full",
                                        get = function()
                                            local c = CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.backgroundColor",
                                                { r = 0.07, g = 0.07, b = 0.07, a = 0.80 })
                                            return c.r, c.g, c.b, c.a
                                        end,
                                        set = function(_, r, g, b, a)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.backgroundColor",
                                                { r = r, g = g, b = b, a = a })

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                    borderHeader = {
                                        type = "header",
                                        name = "Border",
                                        order = 7,
                                    },
                                    borderTexture = {
                                        type = "select",
                                        dialogControl = "LSM30_Border",
                                        name = "Border Texture",
                                        desc = CM:ColorTextKeywords("Texture used for the border lines."),
                                        order = 7.1,
                                        width = "full",
                                        values = function()
                                            local out = {}
                                            if LSM and LSM.HashTable then
                                                local ht = LSM:HashTable("border") or {}
                                                for k, v in pairs(ht) do
                                                    out[k] = v
                                                end
                                            end

                                            -- Guarantee a solid option that always renders well for 1px borders.
                                            out["Interface\\Buttons\\WHITE8X8"] = "Solid (Recommended)"
                                            return out
                                        end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.borderTexture",
                                                "Interface\\Buttons\\WHITE8X8")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.borderTexture", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    borderSize = {
                                        type = "range",
                                        name = "Border Size",
                                        desc = CM:ColorTextKeywords("0 disables the border."),
                                        order = 7.2,
                                        min = 0,
                                        max = 10,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.borderSize", 1)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.borderSize", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    borderColor = {
                                        type = "color",
                                        name = "Border Color",
                                        desc = CM:ColorTextKeywords("Border line color (includes alpha)."),
                                        hasAlpha = true,
                                        order = 7.3,
                                        width = "full",
                                        get = function()
                                            local c = CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.borderColor",
                                                { r = 0, g = 0, b = 0, a = 0.9 })
                                            return c.r, c.g, c.b, c.a
                                        end,
                                        set = function(_, r, g, b, a)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.borderColor",
                                                { r = r, g = g, b = b, a = a })

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                    fontsHeader = {
                                        type = "header",
                                        name = "Fonts",
                                        order = 8,
                                    },
                                    itemFont = {
                                        type = "select",
                                        dialogControl = "LSM30_Font",
                                        name = "Item Font",
                                        desc = CM:ColorTextKeywords("Font used for the item line."),
                                        order = 8.1,
                                        width = "full",
                                        values = function() return LSM and LSM:HashTable("font") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemFont", "Expressway")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemFont", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    itemFontSize = {
                                        type = "range",
                                        name = "Item Font Size",
                                        order = 8.2,
                                        min = 6,
                                        max = 32,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemFontSize", 12)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemFontSize", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    itemFontOutline = {
                                        type = "select",
                                        name = "Item Font Outline",
                                        order = 8.3,
                                        width = "full",
                                        values = {
                                            NONE = "None",
                                            OUTLINE = "Outline",
                                            THICKOUTLINE = "Thick Outline",
                                            MONOCHROMEOUTLINE = "Monochrome Outline",
                                        },
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemFontOutline", "NONE")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemFontOutline", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    itemFontColor = {
                                        type = "color",
                                        name = "Item Font Color",
                                        hasAlpha = true,
                                        order = 8.4,
                                        width = "full",
                                        get = function()
                                            local c = CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemFontColor",
                                                { r = 1, g = 1, b = 1, a = 1 })
                                            return c.r, c.g, c.b, c.a
                                        end,
                                        set = function(_, r, g, b, a)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemFontColor",
                                                { r = r, g = g, b = b, a = a })

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                    detailFont = {
                                        type = "select",
                                        dialogControl = "LSM30_Font",
                                        name = "Detail Font",
                                        desc = CM:ColorTextKeywords("Font used for the details line."),
                                        order = 8.5,
                                        width = "full",
                                        values = function() return LSM and LSM:HashTable("font") or {} end,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailFont", "Expressway")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailFont", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    detailFontSize = {
                                        type = "range",
                                        name = "Detail Font Size",
                                        order = 8.6,
                                        min = 6,
                                        max = 28,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailFontSize", 11)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailFontSize", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    detailFontOutline = {
                                        type = "select",
                                        name = "Detail Font Outline",
                                        order = 8.7,
                                        width = "full",
                                        values = {
                                            NONE = "None",
                                            OUTLINE = "Outline",
                                            THICKOUTLINE = "Thick Outline",
                                            MONOCHROMEOUTLINE = "Monochrome Outline",
                                        },
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailFontOutline", "NONE")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailFontOutline", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    detailFontColor = {
                                        type = "color",
                                        name = "Detail Font Color",
                                        hasAlpha = true,
                                        order = 8.8,
                                        width = "full",
                                        get = function()
                                            local c = CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailFontColor",
                                                { r = 0.8, g = 0.8, b = 0.8, a = 1 })
                                            return c.r, c.g, c.b, c.a
                                        end,
                                        set = function(_, r, g, b, a)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailFontColor",
                                                { r = r, g = g, b = b, a = a })

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                    layoutHeader = {
                                        type = "header",
                                        name = "Layout",
                                        order = 9,
                                    },
                                    frameWidth = {
                                        type = "range",
                                        name = "Row Width",
                                        order = 9.1,
                                        min = 200,
                                        max = 900,
                                        step = 10,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.frameWidth", 420)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.frameWidth", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    frameHeight = {
                                        type = "range",
                                        name = "Row Height",
                                        order = 9.2,
                                        min = 30,
                                        max = 120,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.frameHeight", 50)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.frameHeight", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    padLeft = {
                                        type = "range",
                                        name = "Left Padding",
                                        order = 9.3,
                                        min = 0,
                                        max = 50,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.padLeft", 10)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.padLeft", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    padRight = {
                                        type = "range",
                                        name = "Right Padding",
                                        order = 9.4,
                                        min = 0,
                                        max = 50,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.padRight", 10)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.padRight", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    iconSize = {
                                        type = "range",
                                        name = "Icon Size",
                                        desc = CM:ColorTextKeywords("Set to 0 to hide icons."),
                                        order = 9.5,
                                        min = 0,
                                        max = 64,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.iconSize", 30)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.iconSize", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    iconGap = {
                                        type = "range",
                                        name = "Icon Gap",
                                        order = 9.6,
                                        min = 0,
                                        max = 50,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.iconGap", 10)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.iconGap", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                    itemTextYOffset = {
                                        type = "range",
                                        name = "Item Text Y Offset",
                                        desc = CM:ColorTextKeywords(
                                            "Vertical offset for the item line (can be negative)."),
                                        order = 9.7,
                                        min = -50,
                                        max = 50,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemTextYOffset", 6)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.itemTextYOffset", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },
                                    detailTextYOffset = {
                                        type = "range",
                                        name = "Detail Text Y Offset",
                                        desc = CM:ColorTextKeywords(
                                            "Vertical spacing between item and detail lines (can be negative)."),
                                        order = 9.8,
                                        min = -50,
                                        max = 50,
                                        step = 1,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailTextYOffset", -6)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.detailTextYOffset", value)

                                            local module = GetModule()
                                            if module and module.BestInSlot and module.BestInSlot.UpdateEntryDisplayVisuals then
                                                module.BestInSlot:UpdateEntryDisplayVisuals()
                                            end
                                        end,
                                        disabled = function()
                                            return not CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.entryDisplay.enabled", true)
                                        end,
                                    },

                                },
                            },
                        }
                    },

                    generalTab = {
                        type = "group",
                        name = "General",
                        order = 1,
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
                                                module.BestInSlot:RefreshCache()
                                            end
                                        end,
                                    },
                                }
                            },
                        }
                    },

                    notificationsTab = {
                        type = "group",
                        name = "Notifications",
                        order = 3,
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

                            testingGroup = {
                                type = "group",
                                inline = true,
                                name = "Testing",
                                order = 1.1,
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
                                        max = 60,
                                        step = 0.5,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "mythicplus.bestInSlot.notifications.displayDuration", 15)
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
