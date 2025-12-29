local T = unpack(Twich)

--- @class MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local Logger = T:GetModule("Logger")

--- @class MythicPlusConfiguration
MythicPlusModule.CONFIGURATION = {
    ENABLED = { key = "mythicplus.enabled", default = false, },
}

local Module = TM.Generics.Module:New(MythicPlusModule.CONFIGURATION)

function MythicPlusModule:Enable()
    if Module:IsEnabled() then return end
    Module:Enable()

    Logger.Debug("Mythic+ module enabled")
end

function MythicPlusModule:Disable()
    if not Module:IsEnabled() then return end
    Module:Disable()

    Logger.Debug("Mythic+ module disabled")
end

function MythicPlusModule:OnInitialize()
    if Module:IsEnabled() then return end

    if CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.ENABLED) then
        self:Enable()
    end
end
