--[[
        General Configuration
        This configuration section provides general settings applicable across the addon.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")

function CM:CreateGeneralConfiguration()
    return {
        type = "group",
        name = "General",
        order = 2,
        childGroups = "tab",
        args = {
            description = {
                type = "description",
                order = 1,
                name = CM:ColorTextKeywords(
                    "This section contains general settings that affect the overall behavior of the addon."),
                fontSize = "large",
            },
            spacer1 = CM.Widgets:Spacer(2),
            header = {
                type = "header",
                order = 3,
                name = "Configuration",
            },
            showWelcomeMessageOnLogin = {
                type = "toggle",
                name = "Show Welcome Message on Login",
                desc = "If enabled, the welcome message will be displayed in chat each time you log in to the game.",
                order = 4,
                get = function()
                    return CM:GetProfileSettingSafe("general.showWelcomeMessageOnLogin", true)
                end,
                set = function(_, value)
                    CM:SetProfileSettingSafe("general.showWelcomeMessageOnLogin", value)
                end,
            },
        },
    }
end
