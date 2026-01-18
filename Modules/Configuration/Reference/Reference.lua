--[[
        Reference Configuration
        Reference panels provide in-game UI/UX design notes such as color palettes.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")

function CM:CreateReferenceConfiguration()
    return {
        type = "group",
        name = "Reference",
        order = 5,
        childGroups = "tab",
        args = {
            colors = CM:CreateReferenceColorsConfiguration(),
        },
    }
end
