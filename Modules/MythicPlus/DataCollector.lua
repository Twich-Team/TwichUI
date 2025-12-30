--[[
    Data collector is responsible for gathering Mythic+ related data during dungeon runs, including tracking keystone levels, affixes, completion times, and other relevant metrics.
]]

local T = unpack(Twich)

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@class MythicPlusDataCollectorSubmodule
---@field enabled boolean
local DataCollector = MythicPlusModule.DataCollector or {}
MythicPlusModule.DataCollector = DataCollector

---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type MythicPlusDatabaseSubmodule
local Database = MythicPlusModule.Database


local DungeonMonitor = MythicPlusModule.DungeonMonitor
local callbackID = nil

---@class DungeonSession
---@field mapID number

local DungeonSession

function DataCollector:Enable()
    if self.enabled then return end
    self.enabled = true

    -- Restore session from DB if it exists (persisted across reloads)
    DungeonSession = Database:GetDungeonSession()
    if DungeonSession then
        Logger.Debug("Restored active Mythic+ session for map " .. tostring(DungeonSession.mapID))
    end

    -- hook into DungeonMonitor events here to start collecting data
    callbackID = DungeonMonitor:RegisterCallback(function(eventName, ...)
        if eventName == "CHALLENGE_MODE_START" then
            local mapID = ...

            if DungeonSession then
                Logger.Warn("A lingering Mythic+ dungeon session is active. Overwriting with new session")
                DungeonSession = nil
                Database:ResetDungeonSession()
            end

            DungeonSession = {
                mapID = mapID,
            }
            -- persist the active session so it survives /reload
            Database:SetDungeonSession(DungeonSession)

            Logger.Debug("Mythic+ dungeon started, mapID: " .. tostring(mapID))
        elseif eventName == "CHALLENGE_MODE_RESET" then
            local mapID = ...

            if not DungeonSession then
                Logger.Warn("A Mythic+ dungeon reset detected without an active session")
                return
            end

            -- clear persisted session
            DungeonSession = nil
            Database:ResetDungeonSession()
            Logger.Debug("Mythic+ dungeon reset/aborted, mapID: " .. tostring(mapID))
        elseif eventName == "CHALLENGE_MODE_COMPLETED_REWARDS" then
            local mapID, medal, timeMS, money, rewards = ...

            if not DungeonSession then
                Logger.Warn("A Mythic+ dungeon completion detected without an active session")
                return
            end

            -- TODO: process session

            -- clear persisted session
            DungeonSession = nil
            Database:ResetDungeonSession()
            Logger.Debug("Mythic+ dungeon completed, mapID: " .. tostring(mapID) .. ", timeMS: " .. tostring(timeMS))
        end
    end)


    Logger.Debug("Mythic plus data collector enabled")
end

function DataCollector:Disable()
    if not self.enabled then return end
    self.enabled = false

    -- unregister from DungeonMonitor events
    if callbackID then
        DungeonMonitor:UnregisterCallback(callbackID)
        callbackID = nil
    end

    Logger.Debug("Mythic plus data collector disabled")
end
