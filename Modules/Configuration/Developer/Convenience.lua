local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")

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
            }
        }
    }
end
