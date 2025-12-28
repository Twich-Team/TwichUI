local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM         = T:GetModule("Configuration")
--- @type ToolsModule
local TM         = T:GetModule("Tools")

--- @type GoldGoblinConfigurationModule
local GG         = CM.GoldGoblin or {}

--- @class GoldTrackerConfigurationModule
local GTC        = GG.GoldTracker or {}
GG.GoldTracker   = GTC

function GTC:Create()
    return {
        description = CM.Widgets:ComponentDescription(1,
            "There are currently no configuration options for the Gold Tracker submodule.\n\n"
            ..
            "Account-wide gold can be seen using the Goblin datatext.\n\n"
            ..
            " The ability to remove cached data is coming soon!"
        ),
    }
end
