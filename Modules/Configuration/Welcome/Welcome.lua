--[[
        Welcome Panel
        This configuration section welcomes users to the addon, describing its capabilities and orienting them with its philosphies.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")

--- Creates the primary developer configuration panels.
function CM:CreateWelcomePanel()
    local TT = TM.Text
    local CT = TM.Colors
    return {
        type = "group",
        name = "Welcome",
        order = 1,
        childGroups = "tab",
        args = {
            -- Display addon logo banner
            logo = {
                type = "description",
                name = "",
                order = 1,
                image = function()
                    return [[Interface\AddOns\TwichUI\Media\Textures\twich-banner]], 229, 100
                end,
            },
            -- Add a space between the banner and the welcome message
            logoSpacer = CM.Widgets:Spacer(2),
            -- Display a welcome message
            welcomeMessage = {
                type = "description",
                name = "Welcome to " ..
                    CM:GetAddonNameFormatted() ..
                    "! This addon is designed to enhance your World of Warcraft experience with a focus on customization, performance, and user-friendly features.",
                fontSize = "large",
                order = 3,
            },
            welcomeMessageSpacer = CM.Widgets:Spacer(4),
            -- group to display addon data such as version and warcraft version
            addonData = {
                type = "group",
                name = "Game Information",
                order = 5,
                inline = true,
                args = {
                    -- display the addon version
                    version = {
                        type = "description",
                        name = CM:GetAddonNameFormatted() ..
                            " version: " .. TT.Color(CT.TWICH.SECONDARY_ACCENT, T.addonMetadata.version),
                        order = 1,
                        fontSize = "medium",
                    },
                    -- display wow version
                    wowVersion = {
                        type = "description",
                        name = function()
                            return TT.Color(CT.TWICH.GOLD_ACCENT, "World of Warcraft") .. " version: " ..
                                TT.Color(CT.TWICH.SECONDARY_ACCENT,
                                    (T.wowMetadata.wowpatch or "") .. " (TOC: " .. (T.wowMetadata.wowtoc or "") .. ")")
                        end,
                        order = 2,
                        fontSize = "medium",
                    },
                },
            },
            -- group to explain the philosophy behind the addon
            philosophy = {
                type = "group",
                name = "Getting Started",
                order = 6,
                inline = true,
                args = {
                    -- explain the philosophy
                    philosophyMessage = {
                        type = "description",
                        name = CM:GetAddonNameFormatted() ..
                            " is built on the principle of providing a highly customizable and performant user experience. I believe in empowering users to tailor their interface to their specific needs and preferences, while also ensuring that the addon runs smoothly and efficiently.\nI have spent a lot of time learning and developing this addon, I hope that it will serve you well.",
                        order = 1,
                        fontSize = "medium",
                    },
                    gettingStartedSpacer = CM.Widgets:Spacer(2),
                    instructionalMessage = {
                        type = "description",
                        name = function()
                            local base =
                            "The addon offers various modules which can be enabled or disabled based on your needs. You will find the modules to the left. Selecting a module will bring you to a detailed configuration page for that module. Most modules will be disabled by default, to ensure you have full control over what the addon does."
                            return CM:ColorTextKeywords(base)
                        end,
                        order = 3,
                        fontSize = "medium",
                    },
                    moduleSpacer = CM.Widgets:Spacer(4),
                    moduleInformation = {
                        type = "description",
                        name = function()
                            local base =
                            "Modules may have several submodules, which can only be enabled if its parent module is enabled. Submodules can be found below the parent module's entry in the list to the left. Each configuration page includes detailed descriptions of how the module works, and provides a large amount of customization."
                            return CM:ColorTextKeywords(base)
                        end,
                        order = 5,
                        fontSize = "medium",
                    },
                    performanceSpace = CM.Widgets:Spacer(6),
                    performanceMessage = {
                        type = "description",
                        name = function()
                            local base =
                            "A note on performance: This addon is designed to be lightweight and efficient. However, some features may have a slight impact on performance. If a module or submodule may effect performance, it will clearly state so, and I have included configuration to allow you to determine the performance impact to the best of my ability."
                            return CM:ColorTextKeywords(base)
                        end,
                        order = 7,
                        fontSize = "medium",
                    },
                },
            },

        }

    }
end
