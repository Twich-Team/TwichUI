--[[
        ThirdPartyAPI Module
        This module provides access to third-party APIs for integration with other addons.
]]
local T, W, I, C = unpack(Twich)

--- @class ThirdPartyAPIModule
--- @field TSM TradeSkillMasterAPI
local TPA = T:GetModule("ThirdPartyAPI")

--- @type ToolsModule
local Tools = T:GetModule("Tools")

--- @type LoggerModule
local Logger = T:GetModule("Logger")

function TPA:CreateFailureMessage(addonName, command)
    return string.format("Could not open %s; %s is unavailable. Do you have %s installed and enabled?", addonName,
        command, addonName)
end

function TPA:OpenThroughSlashCommand(addonName, command)
    local ok = Tools.Game:RunSlashCommandIfAvailable(command)
    if not ok then
        Logger.Warn(self:CreateFailureMessage(addonName, command))
    end
end

-- Note: Keeping very small submodules within this file until/if they grow too large.

--[[
        FarmHud
        * Has an API that I can access
]]
--- @class FarmHUDAPI
local _FarmHud = TPA.FarmHud or {}
TPA.FarmHud = _FarmHud

_FarmHud.addonName = "FarmHUD"

--- @alias FarmHud { Toggle: function } API from FarmHUD addon
local FarmHud = FarmHud -- Global from FarmHUD addon

--- Checks if FarmHud addon is available and its API can be used.
--- @return boolean available whether FarmHud is available
function _FarmHud:IsAvailable()
    return FarmHud and FarmHud.Toggle
end

--- Opens the FarmHud interface if available.
function _FarmHud:Open()
    if not self:IsAvailable() then
        return
    end
end

--[[
        LootAppraiser
        * No accessable API
]]
--- @class LootAppraiserAPI
local _LootAppraiser = TPA.LootAppraiser or {}
TPA.LootAppraiser = _LootAppraiser
_LootAppraiser.addonName = "LootAppraiser"
_LootAppraiser.slashCommand = "/la"

function _LootAppraiser:IsAvailable()
    local available, _, _ = Tools.Game:IsSlashCommandAvailable(self.slashCommand)
    return available
end

function _LootAppraiser:Open()
    TPA:OpenThroughSlashCommand(self.addonName, self.slashCommand)
end

--[[
        Routes
        * No accessable API
]]
--- @class RoutesAPI
local _Routes = TPA.Routes or {}
TPA.Routes = _Routes
_Routes.addonName = "Routes"
_Routes.slashCommand = "/routes"

function _Routes:IsAvailable()
    local available, _, _ = Tools.Game:IsSlashCommandAvailable(self.slashCommand)
    return available
end

function _Routes:Open()
    TPA:OpenThroughSlashCommand(self.addonName, self.slashCommand)
end

--[[
        Journalator
        * Has an API that I can access
]]
--- @class JournalatorAPI
local _Journalator = TPA.Journalator or {}
TPA.Journalator = _Journalator
_Journalator.addonName = "Journalator"
_Journalator.slashCommand = "/jnr"

--- @alias Journalator { Toggle: function } API from Journalator addon
local Journalator = Journalator -- Global from Journalator addon

function _Journalator:IsAvailable()
    return Journalator and Journalator.Toggle
end

function _Journalator:Open()
    if not self:IsAvailable() then
        return
    end

    Journalator.Toggle()
end
