local T, W, I, C = unpack(Twich)

---@class GoldGoblinModule
---@field GoldBalancer GoldBalancerModule
---@field GoldTracker GoldTrackerModule
---@field enabled boolean
local GG         = T:GetModule("GoldGoblin")

---@type ConfigurationModule
local CM         = T:GetModule("Configuration")

---@type table<string, ConfigEntry>
GG.CONFIGURATION = {
    ENABLE = { key = "goldGoblin.enable", default = false }
}

function GG:Enable()
    if self.enabled then return end
    self.enabled = true

    GG.GoldBalancer:OnInitialize()
end

function GG:Disable()
    GG.GoldBalancer:Disable()
end

function GG:OnInitialize()
    if CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.ENABLE) then
        self:Enable()
    end
end

function GG:IsEnabled()
    return self.enabled
end
