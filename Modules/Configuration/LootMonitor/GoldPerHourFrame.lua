--[[
        Gold Per Hour Frame Configuration
        This configuration section allows the user to customize how the gold per hour loot feed frame displays and behaves.
]]
local T, W, I, C = unpack(Twich)
local LSM = T.Libs.LSM
--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
local TT = TM.Text
local CT = TM.Colors

--- @type LootMonitorModule
local LM = T:GetModule("LootMonitor")

--- @type LootMonitorConfigurationModule
CM.LootMonitor = CM.LootMonitor or {}

--- Helper function to safely access the GoldPerHourFrame module
local function GetGPHFrameModule()
    return LM and LM.GoldPerHourFrame
end

--- @class GoldPerHourFrameConfigurationModule
local GPHFrame = CM.LootMonitor.GoldPerHourFrame or {}
CM.LootMonitor.GoldPerHourFrame = GPHFrame


function GPHFrame:Create()
    return {
        displayGroup = {
            type = "group",
            name = "Display",
            inline = true,
            order = 2,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "These settings configure the appearance and display of the Gold Per Hour loot feed frame.\n\n"
                    ..
                    "The loot feed shows a real-time list of items you've looted, grouped together by item. Columns are sortable by clicking the header. The frame displays vital statistics at the bottom, including total gold looted, current gold per hour rate, and tracking time."),
                enableToggle = {
                    type = "toggle",
                    name = "Enable Frame",
                    desc = CM:ColorTextKeywords(
                        "When enabled, the Gold Per Hour loot feed frame will be displayed."),
                    order = 1,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        return GPHFrameModule and GPHFrameModule:IsEnabled() or false
                    end,
                    set = function(_, value)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            if value then
                                GPHFrameModule:Enable()
                            else
                                GPHFrameModule:Disable()
                            end
                        end
                    end
                },
                frameWidthSetting = {
                    type = "range",
                    name = "Frame Width",
                    desc = CM:ColorTextKeywords(
                        "Sets the width of the loot feed frame in pixels."),
                    order = 2,
                    min = 300,
                    max = 1000,
                    step = 10,
                    bigStep = 50,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        return GPHFrameModule and
                            CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_WIDTH) or 500
                    end,
                    set = function(_, value)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_WIDTH, value)
                            if GPHFrameModule:IsEnabled() then
                                GPHFrameModule:Disable()
                                GPHFrameModule:Enable()
                            end
                        end
                    end
                },
                frameHeightSetting = {
                    type = "range",
                    name = "Frame Height",
                    desc = CM:ColorTextKeywords(
                        "Sets the height of the loot feed frame in pixels."),
                    order = 3,
                    min = 200,
                    max = 800,
                    step = 10,
                    bigStep = 50,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        return GPHFrameModule and
                            CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_HEIGHT) or 400
                    end,
                    set = function(_, value)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_HEIGHT, value)
                            if GPHFrameModule:IsEnabled() then
                                GPHFrameModule:Disable()
                                GPHFrameModule:Enable()
                            end
                        end
                    end
                },
                frameScaleSetting = {
                    type = "range",
                    name = "Frame Scale",
                    desc = CM:ColorTextKeywords(
                        "Sets the scale multiplier for the frame. Values greater than 1 enlarge the frame."),
                    order = 4,
                    min = 0.5,
                    max = 2.0,
                    step = 0.1,
                    bigStep = 0.25,
                    isPercent = true,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        return GPHFrameModule and
                            CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_SCALE) or 1.0
                    end,
                    set = function(_, value)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_SCALE, value)
                            if GPHFrameModule:IsEnabled() and GPHFrameModule.frame then
                                GPHFrameModule.frame:SetScale(value)
                            end
                        end
                    end
                },
                frameAlphaSetting = {
                    type = "range",
                    name = "Frame Transparency",
                    desc = CM:ColorTextKeywords(
                        "Sets the transparency of the frame. Lower values make it more transparent."),
                    order = 5,
                    min = 0.1,
                    max = 1.0,
                    step = 0.05,
                    bigStep = 0.1,
                    isPercent = true,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        return GPHFrameModule and
                            CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_ALPHA) or 1.0
                    end,
                    set = function(_, value)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_ALPHA, value)
                            if GPHFrameModule:IsEnabled() and GPHFrameModule.frame then
                                GPHFrameModule.frame:SetAlpha(value)
                            end
                        end
                    end
                },
                frameTextureSetting = {
                    type = "select",
                    name = "Frame Texture",
                    desc = CM:ColorTextKeywords(
                        "Sets the background texture of the frame."),
                    order = 6,
                    dialogControl = "LSM30_Statusbar",
                    values = function()
                        return LSM:HashTable("background")
                    end,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        return GPHFrameModule and
                            CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_TEXTURE) or
                            "Blizzard Tooltip"
                    end,
                    set = function(_, value)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_TEXTURE, value)
                            if GPHFrameModule:IsEnabled() then
                                GPHFrameModule:UpdateFrameTexture()
                            end
                        end
                    end
                },
                frameBgColorSetting = {
                    type = "color",
                    name = "Frame Background Color",
                    desc = CM:ColorTextKeywords(
                        "Sets the background color and transparency of the frame behind the loot list."),
                    order = 6.5,
                    hasAlpha = true,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        local color = GPHFrameModule and
                            CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_BG_COLOR) or
                            { r = 0.04, g = 0.04, b = 0.04, a = 0.9 }
                        return color.r, color.g, color.b, color.a
                    end,
                    set = function(_, r, g, b, a)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_BG_COLOR,
                                { r = r, g = g, b = b, a = a })
                            if GPHFrameModule:IsEnabled() then
                                GPHFrameModule:UpdateFrameTexture()
                            end
                        end
                    end
                },
                frameBorderTextureSetting = {
                    type = "select",
                    name = "Frame Border Texture",
                    desc = CM:ColorTextKeywords(
                        "Sets the border texture of the frame."),
                    order = 7,
                    dialogControl = "LSM30_Border",
                    values = function()
                        return LSM:HashTable("border")
                    end,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        return GPHFrameModule and
                            CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_BORDER_TEXTURE) or
                            "Blizzard Tooltip"
                    end,
                    set = function(_, value)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_BORDER_TEXTURE, value)
                            if GPHFrameModule:IsEnabled() then
                                GPHFrameModule:UpdateFrameTexture()
                            end
                        end
                    end
                },
                frameBorderColorSetting = {
                    type = "color",
                    name = "Frame Border Color",
                    desc = CM:ColorTextKeywords(
                        "Sets the border color of the frame."),
                    order = 8,
                    hasAlpha = true,
                    get = function()
                        local GPHFrameModule = GetGPHFrameModule()
                        local color = GPHFrameModule and
                            CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_BORDER_COLOR) or
                            { r = 0.5, g = 0.5, b = 0.5, a = 1.0 }
                        return color.r, color.g, color.b, color.a
                    end,
                    set = function(_, r, g, b, a)
                        local GPHFrameModule = GetGPHFrameModule()
                        if GPHFrameModule then
                            CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.FRAME_BORDER_COLOR,
                                { r = r, g = g, b = b, a = a })
                            if GPHFrameModule:IsEnabled() then
                                GPHFrameModule:UpdateFrameTexture()
                            end
                        end
                    end
                }
            }
        },
        styleGroup = {
            type = "group",
            name = "Styling",
            inline = true,
            order = 3,
            args = {
                description = CM.Widgets:ComponentDescription(1,
                    "These settings allow you to customize the appearance of the Gold Per Hour loot feed, including colors, fonts, and styling of various frame elements."),
                columnHeadersSubgroup = {
                    type = "group",
                    name = "Column Headers",
                    inline = true,
                    order = 2,
                    args = {
                        headerBgColor = {
                            type = "color",
                            name = "Background Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the background color of the column header row."),
                            order = 1,
                            hasAlpha = true,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.HEADER_BG_COLOR) or
                                    { r = 0.2, g = 0.2, b = 0.2, a = 0.8 }
                                return color.r, color.g, color.b, color.a
                            end,
                            set = function(_, r, g, b, a)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.HEADER_BG_COLOR,
                                        { r = r, g = g, b = b, a = a })
                                    GPHFrameModule:UpdateHeaderColors()
                                end
                            end
                        },
                        headerTextColor = {
                            type = "color",
                            name = "Text Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the text color of column headers."),
                            order = 2,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.HEADER_TEXT_COLOR) or
                                    { r = 0.8, g = 0.8, b = 1 }
                                return color.r, color.g, color.b
                            end,
                            set = function(_, r, g, b)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.HEADER_TEXT_COLOR,
                                        { r = r, g = g, b = b })
                                    GPHFrameModule:UpdateHeaderColors()
                                end
                            end
                        }
                    }
                },
                itemRowsSubgroup = {
                    type = "group",
                    name = "Item Rows",
                    inline = true,
                    order = 3,
                    args = {
                        rowHeight = {
                            type = "range",
                            name = "Row Height",
                            desc = CM:ColorTextKeywords(
                                "Sets the height of each item row in pixels."),
                            order = 1,
                            min = 15,
                            max = 40,
                            step = 1,
                            bigStep = 5,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_HEIGHT) or 25
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_HEIGHT, value)
                                    GPHFrameModule:UpdateRowStyling()
                                end
                            end
                        },
                        rowTexture = {
                            type = "select",
                            name = "Row Texture",
                            desc = CM:ColorTextKeywords(
                                "Sets the background texture of item rows."),
                            order = 1.5,
                            dialogControl = "LSM30_Statusbar",
                            values = function()
                                return LSM:HashTable("background")
                            end,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_TEXTURE) or
                                    "Blizzard Tooltip"
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_TEXTURE, value)
                                    GPHFrameModule:UpdateRowTexture()
                                end
                            end
                        },
                        rowBorderTexture = {
                            type = "select",
                            name = "Row Border Texture",
                            desc = CM:ColorTextKeywords(
                                "Sets the border texture of item rows."),
                            order = 1.6,
                            dialogControl = "LSM30_Border",
                            values = function()
                                local borders = { ["None"] = "None" }
                                for name in pairs(LSM:HashTable("border")) do
                                    borders[name] = name
                                end
                                return borders
                            end,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_BORDER_TEXTURE) or
                                    "None"
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_BORDER_TEXTURE,
                                        value)
                                    GPHFrameModule:UpdateRowTexture()
                                end
                            end
                        },
                        rowBorderColor = {
                            type = "color",
                            name = "Row Border Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the border color of item rows."),
                            order = 1.7,
                            hasAlpha = true,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_BORDER_COLOR) or
                                    { r = 0.3, g = 0.3, b = 0.3, a = 0.8 }
                                return color.r, color.g, color.b, color.a
                            end,
                            set = function(_, r, g, b, a)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_BORDER_COLOR,
                                        { r = r, g = g, b = b, a = a })
                                    GPHFrameModule:UpdateRowTexture()
                                end
                            end
                        },
                        rowBgColor = {
                            type = "color",
                            name = "Background Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the background color of item rows."),
                            order = 2,
                            hasAlpha = true,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_BG_COLOR) or
                                    { r = 0.15, g = 0.15, b = 0.15, a = 0.6 }
                                return color.r, color.g, color.b, color.a
                            end,
                            set = function(_, r, g, b, a)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_BG_COLOR,
                                        { r = r, g = g, b = b, a = a })
                                    GPHFrameModule:UpdateRowStyling()
                                end
                            end
                        },
                        rowHoverBgColor = {
                            type = "color",
                            name = "Hover Background Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the background color shown when mousing over an item row."),
                            order = 2.5,
                            hasAlpha = true,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_HOVER_BG_COLOR)
                                    or { r = 0.12, g = 0.12, b = 0.12, a = 1.0 }
                                return color.r, color.g, color.b, color.a
                            end,
                            set = function(_, r, g, b, a)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.ROW_HOVER_BG_COLOR,
                                        { r = r, g = g, b = b, a = a })
                                    GPHFrameModule:UpdateRowStyling()
                                end
                            end
                        },
                        rowTextColor = {
                            type = "color",
                            name = "Text Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the text color of item rows."),
                            order = 3,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_TEXT_COLOR) or
                                    { r = 1, g = 1, b = 1 }
                                return color.r, color.g, color.b
                            end,
                            set = function(_, r, g, b)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_TEXT_COLOR,
                                        { r = r, g = g, b = b })
                                    GPHFrameModule:UpdateRowStyling()
                                end
                            end
                        },
                        rowValueColor = {
                            type = "color",
                            name = "Value Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the color of gold values in item rows."),
                            order = 3.5,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_VALUE_COLOR) or
                                    { r = 1, g = 0.84, b = 0 }
                                return color.r, color.g, color.b
                            end,
                            set = function(_, r, g, b)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_VALUE_COLOR,
                                        { r = r, g = g, b = b })
                                    GPHFrameModule:UpdateRowStyling()
                                end
                            end
                        },
                        rowSpacing = {
                            type = "range",
                            name = "Row Spacing",
                            desc = CM:ColorTextKeywords(
                                "Sets the vertical spacing between rows in pixels."),
                            order = 4,
                            min = 0,
                            max = 10,
                            step = 1,
                            bigStep = 2,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_SPACING) or 0
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_SPACING, value)
                                    GPHFrameModule:UpdateRowStyling()
                                end
                            end
                        },
                        scrollBgColor = {
                            type = "color",
                            name = "Loot Area Background",
                            desc = CM:ColorTextKeywords(
                                "Sets the background color and transparency of the scroll area behind item rows."),
                            order = 5,
                            hasAlpha = true,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.SCROLL_BG_COLOR) or
                                    { r = 0.03, g = 0.03, b = 0.03, a = 0.9 }
                                return color.r, color.g, color.b, color.a
                            end,
                            set = function(_, r, g, b, a)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.SCROLL_BG_COLOR,
                                        { r = r, g = g, b = b, a = a })
                                    GPHFrameModule:UpdateScrollStyling()
                                end
                            end
                        }
                    }
                },
                statsSubgroup = {
                    type = "group",
                    name = "Statistics Footer",
                    inline = true,
                    order = 4,
                    args = {
                        statsHeight = {
                            type = "range",
                            name = "Footer Height",
                            desc = CM:ColorTextKeywords(
                                "Sets the height of the statistics footer area in pixels."),
                            order = 0.5,
                            min = 30,
                            max = 100,
                            step = 1,
                            bigStep = 5,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.STATS_HEIGHT) or 55
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule and GPHFrameModule.frame then
                                    CM:SetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.STATS_HEIGHT, value)

                                    -- Resize and re-anchor stats frame relative to parent frame
                                    if GPHFrameModule.statsFrame then
                                        GPHFrameModule.statsFrame:SetSize(
                                            GPHFrameModule.frame:GetWidth() - 8, value)
                                        GPHFrameModule.statsFrame:ClearAllPoints()
                                        GPHFrameModule.statsFrame:SetPoint(
                                            "BOTTOMLEFT", GPHFrameModule.frame, "BOTTOMLEFT", 4, 4)
                                    end

                                    -- Adjust scroll/row container height so it always fills space above footer
                                    if GPHFrameModule.scrollFrame then
                                        local frameHeight = GPHFrameModule.frame:GetHeight()
                                        -- Match CreateFrame(): keep scroll bottom flush with stats top
                                        local newScrollHeight = frameHeight - (value + 59)
                                        if newScrollHeight < 0 then newScrollHeight = 0 end
                                        GPHFrameModule.scrollFrame:SetSize(
                                            GPHFrameModule.frame:GetWidth() - 8, newScrollHeight)
                                    end
                                end
                            end
                        },
                        statsSpacing = {
                            type = "range",
                            name = "Stats Spacing",
                            desc = CM:ColorTextKeywords(
                                "Sets the horizontal spacing between statistics (Raw Gold, Total Looted, GPH)."),
                            order = 0.6,
                            min = 80,
                            max = 220,
                            step = 5,
                            bigStep = 10,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.STATS_SPACING) or
                                    140
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.STATS_SPACING, value)
                                    if GPHFrameModule.UpdateStatsLayout then
                                        GPHFrameModule:UpdateStatsLayout()
                                    end
                                end
                            end
                        },
                        statsTextColor = {
                            type = "color",
                            name = "Label Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the color of statistic labels."),
                            order = 1,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.STATS_LABEL_COLOR) or
                                    { r = 0.7, g = 0.7, b = 0.7 }
                                return color.r, color.g, color.b
                            end,
                            set = function(_, r, g, b)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.STATS_LABEL_COLOR,
                                        { r = r, g = g, b = b })
                                    GPHFrameModule:UpdateStatsStyling()
                                end
                            end
                        },
                        statsValueColor = {
                            type = "color",
                            name = "Value Color",
                            desc = CM:ColorTextKeywords(
                                "Sets the color of statistic values."),
                            order = 2,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.STATS_VALUE_COLOR) or
                                    { r = 1, g = 1, b = 0 }
                                return color.r, color.g, color.b
                            end,
                            set = function(_, r, g, b)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.STATS_VALUE_COLOR,
                                        { r = r, g = g, b = b })
                                    GPHFrameModule:UpdateStatsStyling()
                                end
                            end
                        }
                    }
                },
                fontsSubgroup = {
                    type = "group",
                    name = "Fonts",
                    inline = true,
                    order = 5,
                    args = {
                        baseFont = {
                            type = "select",
                            name = "Base Font",
                            desc = "Font used for the title, headers, rows, and statistics.",
                            order = 1,
                            width = 1.5,
                            dialogControl = "LSM30_Font",
                            values = function()
                                return LSM:HashTable("font")
                            end,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.BASE_FONT) or
                                    "Expressway"
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.BASE_FONT, value)
                                    GPHFrameModule:UpdateAllStyling()
                                    if GPHFrameModule.UpdateTitleStyling then
                                        GPHFrameModule:UpdateTitleStyling()
                                    end
                                end
                            end
                        },
                        titleFontSize = {
                            type = "range",
                            name = "Title Font Size",
                            desc = "Font size for the frame title.",
                            order = 2,
                            min = 8,
                            max = 32,
                            step = 1,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.TITLE_FONT_SIZE) or
                                    14
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.TITLE_FONT_SIZE, value)
                                    if GPHFrameModule.UpdateTitleStyling then
                                        GPHFrameModule:UpdateTitleStyling()
                                    end
                                end
                            end
                        },
                        headerFontSize = {
                            type = "range",
                            name = "Header Font Size",
                            desc = "Font size for column headers.",
                            order = 3,
                            min = 8,
                            max = 24,
                            step = 1,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.HEADER_FONT_SIZE)
                                    or 12
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.HEADER_FONT_SIZE, value)
                                    GPHFrameModule:UpdateHeaderColors()
                                end
                            end
                        },
                        rowFontSize = {
                            type = "range",
                            name = "Row Font Size",
                            desc = "Font size for loot rows.",
                            order = 4,
                            min = 8,
                            max = 24,
                            step = 1,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.ROW_FONT_SIZE) or
                                    11
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.ROW_FONT_SIZE, value)
                                    GPHFrameModule:UpdateRowStyling()
                                end
                            end
                        },
                        statsFontSize = {
                            type = "range",
                            name = "Statistics Font Size",
                            desc = "Font size for statistics text.",
                            order = 5,
                            min = 8,
                            max = 24,
                            step = 1,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                return GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(GPHFrameModule.CONFIGURATION.STATS_FONT_SIZE)
                                    or 10
                            end,
                            set = function(_, value)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.STATS_FONT_SIZE, value)
                                    GPHFrameModule:UpdateStatsStyling()
                                end
                            end
                        },
                        titleTextColor = {
                            type = "color",
                            name = "Title Text Color",
                            desc = CM:ColorTextKeywords("Sets the title text color."),
                            order = 6,
                            get = function()
                                local GPHFrameModule = GetGPHFrameModule()
                                local color = GPHFrameModule and
                                    CM:GetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.TITLE_TEXT_COLOR) or
                                    { r = 1, g = 1, b = 1 }
                                return color.r, color.g, color.b
                            end,
                            set = function(_, r, g, b)
                                local GPHFrameModule = GetGPHFrameModule()
                                if GPHFrameModule then
                                    CM:SetProfileSettingByConfigEntry(
                                        GPHFrameModule.CONFIGURATION.TITLE_TEXT_COLOR,
                                        { r = r, g = g, b = b })
                                    if GPHFrameModule.UpdateTitleStyling then
                                        GPHFrameModule:UpdateTitleStyling()
                                    end
                                end
                            end
                        }
                    }
                }
            }
        }
    }
end
