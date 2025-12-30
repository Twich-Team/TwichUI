---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")

---@type LoggerModule
local Logger = T:GetModule("Logger")

--- @type DeveloperConfigurationModule
CM.Developer = CM.Developer or {}

--- @class DeveloperConvenienceConfiguration
local DC = CM.Developer.Convenience or {}
CM.Developer.Convenience = DC

--- Create the logger configuration panels
--- @param order number The order of the logger configuration panel
function DC:Create(order)
    return {
        type = "group",
        name = "Convenience",
        order = order,
        args = {
            -- module description
            description = CM.Widgets:SubmoduleDescription(
                "Convenience features provide quick access to common developer settings to make development easier and more efficient."),
            autoOpenConfigGroup = {
                type = "group",
                inline = true,
                name = "Auto-Open Configuration",
                order = 1,
                args = {
                    description = CM.Widgets:ComponentDescription(1,
                        "Automatically opens the configuration panel when the addon is loaded."),
                    enableAutoOpen = {
                        type = "toggle",
                        name = "Enable",
                        desc = "If enabled, the configuration panel will automatically open when the addon is loaded.",
                        order = 2,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.convenience.autoOpenConfig", false)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.convenience.autoOpenConfig", value)
                        end,
                    }
                }
            },
            mythicPlusGroup = {
                type = "group",
                inline = true,
                name = "Mythic+",
                order = 2,
                args = {
                    description = CM.Widgets:ComponentDescription(1,
                        "Convenience settings related to Mythic+ development."),
                    autoShowMythicPlus = {
                        type = "toggle",
                        name = "Auto-show Mythic+ Window on Reload",
                        desc =
                        "If enabled, the Mythic+ main window will be shown automatically after /reload (when the Mythic+ module is enabled).",
                        order = 2,
                        width = "full",
                        get = function()
                            return CM:GetProfileSettingSafe("developer.convenience.autoShowMythicPlusWindow", false)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.convenience.autoShowMythicPlusWindow", value)
                        end,
                    },
                },
            },
        }
    }
end
