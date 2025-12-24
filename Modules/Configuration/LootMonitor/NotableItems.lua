--[[
        Notable Items Configuration
        This configuration section allows the user to customize which items are notable items, as well as the notable item notification frame.
]]
local T, W, I, C = unpack(Twich)
--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
local TT = TM.Text
local CT = TM.Colors
local MT = TM.Money

local LSM = T.Libs.LSM
local LM = T:GetModule("LootMonitor")

local function UpdateNotificationFrame()
    local nif = LM and LM.NotableItemNotificationFrame
    if nif and type(nif.UpdateFrame) == "function" then
        nif:UpdateFrame()
    end
end

--- @type LootMonitorConfigurationModule
CM.LootMonitor = CM.LootMonitor or {}

--- @class NotableItemConfigurationModule
local NI = CM.LootMonitor.NotableItems or {}
CM.LootMonitor.NotableItems = NI

local function CreateFrameLayoutGroup(order)
    return {
        type = "group",
        name = "Frame Layout",
        inline = true,
        order = order,
        args = {
            description = CM.Widgets:ComponentDescription(1,
                "Configure the layout of the notification frame, including content position and size."),
            contentAlign = {
                type = "select",
                name = "Content Alignment",
                desc = "Align icon and text to the left or right side of the frame.",
                order = 2,
                values = {
                    LEFT  = "Left",
                    RIGHT = "Right",
                },
                get = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.contentAlignment", "LEFT")
                end,
                set = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.contentAlignment", value)
                    UpdateNotificationFrame()
                end,
            },
            frameSizeWidth = {
                type  = "range",
                name  = "Frame Width",
                desc  = "Width of the notification frame.",
                order = 3,
                min   = 100,
                max   = 800,
                step  = 10,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.frameWidth", 400)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.frameWidth", value)
                    UpdateNotificationFrame()
                end,
            },
            frameSizeHeight = {
                type  = "range",
                name  = "Frame Height",
                desc  = "Height of the notification frame.",
                order = 4,
                min   = 20,
                max   = 200,
                step  = 5,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.frameHeight", 60)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.frameHeight", value)
                    UpdateNotificationFrame()
                end,
            },
        }
    }
end

local function CreateAnimationGroup(order)
    return {
        type = "group",
        name = "Animation & Display Duration",
        inline = true,
        order = order,
        args = {
            description = CM.Widgets:ComponentDescription(1,
                "Configure the duration of the fade-in and fade-out animations, as well as the display duration of the notification frame."),
            displayDuration = {
                type  = "range",
                name  = "Display Duration",
                desc  = "How long (in seconds) the frame stays visible (including fade time).",
                order = 7,
                min   = 1,
                max   = 10,
                step  = 0.5,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.displayDuration", 5)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.displayDuration", value)
                    UpdateNotificationFrame()
                end,
            },
            fadeInDuration = {
                type  = "range",
                name  = "Fade In Time",
                desc  = "Time (in seconds) for the frame to fade in.",
                order = 8,
                min   = 0,
                max   = 3,
                step  = 0.1,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.fadeInTime", 0.3)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.fadeInTime", value)
                    UpdateNotificationFrame()
                end,
            },

            fadeOutDuration = {
                type  = "range",
                name  = "Fade Out Time",
                desc  = "Time (in seconds) for the frame to fade out.",
                order = 9,
                min   = 0,
                max   = 3,
                step  = 0.1,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.fadeOutTime", 0.3)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.fadeOutTime", value)
                    UpdateNotificationFrame()
                end,
            },
        }
    }
end

--- Creates the configuration for what defines a Notable Item.
--- @return table A configuration section for defining Notable Items.
local function CreateItemDefinitionSection(order)
    return {
        type = "group",
        name = "Notable Item Definition",
        order = order,
        args = {
            description = CM.Widgets:ComponentDescription(1,
                "This section allows configuring of what defines a Notable Item. If an item is looted that meets or exceeds all of the defined threshholds, it will be considered a Notable Item and trigger a notification."),
            minGoldValue = {
                type = "input",
                name = "Minimum Gold Value",
                desc = CM:ColorTextKeywords(
                    "The value of the item must be at or above this value to become a notable item."),
                order = 2,
                get = function()
                    -- stored as a copperValue in db
                    local copperValue = CM:GetProfileSettingSafe("lootMonitor.notableItems.minCopperValue",
                        100 * 100 * 100) -- default 100 gold
                    local goldValue = floor(MT.CopperToGold(copperValue))
                    return tostring(goldValue)
                end,
                set = function(_, value)
                    local goldValue = tonumber(value) or 0
                    local copperValue = MT.GoldToCopper(goldValue)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.minCopperValue", copperValue)
                end,
            },
            minSaleRate = {
                type = "input",
                name = "Minimum Sale Rate",
                desc =
                    CM:ColorTextKeywords(
                        "The sale rate of the item must be at or above this value to become a notable item. Sale rate is always TradeSkillMaster's DBRegionSaleRate value for the item."),
                order = 3,
                get = function()
                    local saleRate = CM:GetProfileSettingSafe("lootMonitor.notableItems.minSaleRate", 0.01)
                    saleRate = tonumber(saleRate)
                    return tostring(saleRate)
                end,
                set = function(_, value)
                    local saleRate = tonumber(value) or 0
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.minSaleRate", saleRate)
                end,
            },
            ignorePoorQuality = {
                type = "toggle",
                name = "Ignore Poor Quality Items",
                desc = CM:ColorTextKeywords(
                    "If enabled, items of poor quality (grey/junk items) will never be considered Notable Items."),
                order = 4,
                get = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.ignorePoorQuality", true)
                end,
                set = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.ignorePoorQuality", value)
                end
            }
        }
    }
end

local function FrameAppearanceFrame(order)
    return {
        type = "group",
        name = "Frame Appearance",
        order = order,
        inline = true,
        args = {
            description = CM.Widgets:ComponentDescription(1,
                "Configure the appearance of the notification frame, including background and border."),
            frameTexture = {
                type          = "select",
                name          = "Frame Texture",
                desc          = "Backdrop texture for the notable loot frame.",
                order         = 2,
                dialogControl = "LSM30_Statusbar",
                values        = LSM:HashTable("statusbar"),
                get           = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.frameTexture",
                        "Interface\\TargetingFrame\\UI-StatusBar")
                end,
                set           = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.frameTexture", value)
                    UpdateNotificationFrame()
                end,
            },
            frameColor = {
                type     = "color",
                name     = "Frame Color",
                desc     = "Color and transparency for the frame background.",
                order    = 3,
                hasAlpha = true,
                get      = function()
                    local c = CM:GetProfileSettingSafe("lootMonitor.notableItems.frameColor",
                        { r = 0, g = 0, b = 0, a = 0.5 })
                    if type(c) == "table" then
                        return tonumber(c.r) or 0, tonumber(c.g) or 0, tonumber(c.b) or 0, tonumber(c.a) or 1
                    end
                    return 0, 0, 0, 0.5
                end,
                set      = function(_, r, g, b, a)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.frameColor",
                        { r = tonumber(r) or 0, g = tonumber(g) or 0, b = tonumber(b) or 0, a = tonumber(a) or 1 })
                    UpdateNotificationFrame()
                end,
            },
            borderColor = {
                type     = "color",
                name     = "Border Color",
                desc     = "Color and transparency of the frame border.",
                order    = 5,
                hasAlpha = true,
                get      = function()
                    local c = CM:GetProfileSettingSafe("lootMonitor.notableItems.frameBorderColor",
                        { r = 1, g = 1, b = 1, a = 1 })
                    if type(c) == "table" then
                        return tonumber(c.r) or 1, tonumber(c.g) or 1, tonumber(c.b) or 1, tonumber(c.a) or 1
                    end
                    return 1, 1, 1, 1
                end,
                set      = function(_, r, g, b, a)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.frameBorderColor",
                        { r = tonumber(r) or 1, g = tonumber(g) or 1, b = tonumber(b) or 1, a = tonumber(a) or 1 })
                    UpdateNotificationFrame()
                end,
            },
            borderSize = {
                type  = "range",
                name  = "Border Size",
                desc  = "Thickness of the frame border.",
                order = 6,
                min   = 0,
                max   = 8,
                step  = 1,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.frameBorderSize", 2)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.frameBorderSize", value)
                    UpdateNotificationFrame()
                end,
            },
        }
    }
end

local function FrameGrowthGroup(order)
    return {
        type = "group",
        name = "Frame Growth",
        inline = true,
        order = order,
        args = {
            description = CM.Widgets:ComponentDescription(1,
                "Configure the screen position and growth direction of the notification frame."),
            growDirection = {
                type   = "select",
                name   = "Growth Direction",
                desc   = "Direction new loot messages grow from the anchor.",
                order  = 2,
                values = {
                    UP   = "Up",
                    DOWN = "Down",
                },
                get    = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.growDirection", "UP")
                end,
                set    = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.growDirection", value)
                    UpdateNotificationFrame()
                end,
            },

            growSpacing = {
                type  = "range",
                name  = "Message Spacing",
                desc  = "Spacing (in pixels) between stacked loot messages.",
                order = 11,
                min   = 0,
                max   = 40,
                step  = 1,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.growSpacing", 4)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.growSpacing", value)
                    UpdateNotificationFrame()
                end,
            },
            maxMessages = {
                type  = "range",
                name  = "Max Messages",
                desc  =
                "Maximum number of loot messages shown at once. Older ones are removed when this limit is reached.",
                order = 12,
                min   = 1,
                max   = 20,
                step  = 1,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.maxMessages", 5)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.maxMessages", value)
                    UpdateNotificationFrame()
                end,
            },

        }
    }
end

local function IconConfigurationFrame(order)
    return {
        type = "group",
        name = "Icon",
        order = order,
        inline = true,
        args = {
            description = CM.Widgets:ComponentDescription(1,
                "Configure the icon size."),
            iconSize = {
                type  = "range",
                name  = "Icon Size",
                desc  = "Size of the item icon displayed in the notification frame.",
                order = 2,
                min   = 16,
                max   = 128,
                step  = 1,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.iconSize", 32)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.iconSize", value)
                    UpdateNotificationFrame()
                end,
            },
        }
    }
end

local function FontConfigurationFrame(order)
    return {
        type = "group",
        name = "Fonts",
        order = order,
        inline = true,
        args = {
            description = CM.Widgets:ComponentDescription(0,
                "Configure the font, size, and color used in the notification frame."),
            fontSelect = {
                type          = "select",
                name          = "Font",
                desc          = "Font used in the notification frame.",
                order         = 1,
                width         = 1.5,
                dialogControl = "LSM30_Font",
                values        = LSM:HashTable("font"),
                get           = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.font", "Expressway")
                end,
                set           = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.font", value)
                    UpdateNotificationFrame()
                end,
            },
            itemFontSize = {
                type  = "range",
                name  = "Item Font Size",
                desc  = "Font size for the item link text.",
                order = 2,
                min   = 8,
                max   = 32,
                step  = 1,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.itemFontSize", 18)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.itemFontSize", value)
                    UpdateNotificationFrame()
                end,
            },
            valueFontSize = {
                type  = "range",
                name  = "Value Font Size",
                desc  = "Font size for the value text.",
                order = 3,
                min   = 8,
                max   = 32,
                step  = 1,
                get   = function()
                    return CM:GetProfileSettingSafe("lootMonitor.notableItems.valueFontSize", 14)
                end,
                set   = function(_, value)
                    CM:SetProfileSettingSafe("lootMonitor.notableItems.valueFontSize", value)
                    UpdateNotificationFrame()
                end,
            },
        }
    }
end

local function CreateNotableItemFrameConfiguration(order)
    return {
        type = "group",
        name = "Notification Frame",
        order = order,
        args = {
            description = CM.Widgets:ComponentDescription(1,
                "This section configures the Notable Item received notification frame that appears when a Notable Item is looted."),
            testingGroup = {
                type = "group",
                inline = true,
                name = "Testing",
                order = 2,
                args = {
                    testNotificationButton = {
                        type = "execute",
                        name = TT.Color(CT.TWICH.GOLD_ACCENT, "Show Test Notification"),
                        desc = CM:ColorTextKeywords(
                            "Displays a test Notable Item notification using a sample item."),
                        order = 1,
                        func = function()
                            --- @type LootMonitorModule
                            local LM = T:GetModule("LootMonitor")
                            LM.NotableItemNotificationHandler:TestShowNotification()
                        end
                    },
                    pinPreviewFrame = {
                        type = "toggle",
                        name = TT.Color(CT.TWICH.GOLD_ACCENT, "Toggle Preview Frame"),
                        desc = CM:ColorTextKeywords(
                            "Toggles a preview of the Notable Item notification frame that won't disappear."),
                        order = 2,
                        get = function()
                            --- @type LootMonitorModule
                            local LM = T:GetModule("LootMonitor")
                            return LM.NotableItemNotificationFrame.previewShown
                        end,
                        set = function(_, value)
                            --- @type LootMonitorModule
                            local LM = T:GetModule("LootMonitor")
                            if value then
                                LM.NotableItemNotificationFrame:ShowPreview()
                            else
                                LM.NotableItemNotificationFrame:HidePreview()
                            end
                        end,
                    }
                }
            },
            soundGroup = {
                type = "group",
                inline = true,
                name = "Sound",
                order = 3,
                args = {
                    description = CM.Widgets:ComponentDescription(1,
                        "Configure the sound that plays when a Notable Item is looted."),
                    soundSelect = {
                        type = "select",
                        dialogControl = "LSM30_Sound",
                        name = "Notification Sound",
                        desc = CM:ColorTextKeywords(
                            "The sound that plays when a Notable Item notification is looted."),
                        order = 2,
                        values = LSM:HashTable("sound"),
                        get = function()
                            return CM:GetProfileSettingSafe("lootMonitor.notableItems.notificationSound", "Notable Loot")
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("lootMonitor.notableItems.notificationSound", value)
                        end
                    }
                }
            },
            animationAndDurationGroup = CreateAnimationGroup(4),
            frameLayoutGroup = CreateFrameLayoutGroup(5),
            iconConfigurationGroup = IconConfigurationFrame(6),
            fontConfigurationGroup = FontConfigurationFrame(7),
            frameAppearanceGroup = FrameAppearanceFrame(8),
            frameGrowthGroup = FrameGrowthGroup(9),

        }
    }
end



--- Creates the Notable Items configuration section.
--- @return table A configuration section for Notable Items.
function NI:Create()
    -- Return the two sections directly so the parent group's `childGroups = "tab"`
    -- (provided by the SubmoduleGroup) will render these as tabs.
    return {
        itemDefinitionSection = CreateItemDefinitionSection(10),
        notableItemFrameSection = CreateNotableItemFrameConfiguration(20),
    }
end
