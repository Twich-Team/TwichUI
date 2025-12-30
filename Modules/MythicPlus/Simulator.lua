--[[
    Mythic+ Simulator allows testing of various addon components without running dungeons over and over.
    If the Simulator is enabled, and a call is made to a supported function in the API, then the call is instead
    routed here, and a simulated response is returned.
]]

local T = unpack(Twich)

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@class MythicPlusSimulatorSubmodule
---@field enabled boolean
local Sim = MythicPlusModule.Simulator or {}
MythicPlusModule.Simulator = Sim

local EventSim = Sim.EventSim or {}
Sim.EventSim = EventSim

---@type LoggerModule
local Logger = T:GetModule("Logger")

function Sim:Enable()
    if self.enabled then return end
    Logger.Debug("Mythic plus simulator enabled")
end

function Sim:Disable()
    if not self.enabled then return end
    Logger.Debug("Mythic plus simulator disabled")
end

--- Determines if the simulator can simulate the given function.
---@param funcName string the name of the function
---@return boolean canSimulate true if the simulator can simulate the function, false otherwise
function Sim:CanSimulateFunc(funcName)
    return Sim[funcName] ~= nil
end

--[[ Simulated API functions go below this line ]]

---@class MythicPlusSimulator_SupportedEvent events supported by the simulator
Sim.SupportedEvents = {
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED_REWARDS"
}

---@param event MythicPlusSimulator_SupportedEvent the event to simulate
function Sim:SimEvent(event)
    Logger.Debug("Request received to simulate event: " .. event)

    if not self.EventSim:Delegate(event) then
        Logger.Error("Simulator did not simulate event '" ..
            event .. "'. Either the simulation was not implemented, or the event is not supported.")
        return
    end
end

function EventSim:Delegate(event)
    if event and self["__" .. event] then
        self["__" .. event](self)
        return true
    else
        return false
    end
end

function EventSim:__CHALLENGE_MODE_START()
    local mapID = 525
    local DungeonMonitor = MythicPlusModule.DungeonMonitor
    if DungeonMonitor and DungeonMonitor.enabled then
        Logger.Debug("Simulating CHALLENGE_MODE_START event with mapID " .. mapID)
        DungeonMonitor:EventHandler("CHALLENGE_MODE_START", mapID)
    end
end

function EventSim:__CHALLENGE_MODE_COMPLETED_REWARDS()
    local mapID = 525
    local medal = 3
    local timeMS = 1500000
    local money = 500000
    ---@type ChallengeModeReward[]
    local rewards = {
        {
            rewardID = 32837,    -- is this an item id?
            quantity = 1,
            displayInfoID = nil, -- not sure what this is
            isCurrency = false,
        },
    }

    local DungeonMonitor = MythicPlusModule.DungeonMonitor
    if DungeonMonitor and DungeonMonitor.enabled then
        Logger.Debug("Simulating CHALLENGE_MODE_COMPLETED_REWARDS event with mapID " .. mapID)
        DungeonMonitor:EventHandler("CHALLENGE_MODE_COMPLETED_REWARDS", mapID, medal, timeMS, money, rewards)
    end
end
