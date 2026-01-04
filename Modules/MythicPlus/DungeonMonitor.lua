--[[
    Simple event handler with callback to enable listening to events related to Mythic+ dungeons.
]]

local T = unpack(Twich)

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@class MythicPlusDungeonMonitorSubmodule
---@field enabled boolean
local DungeonMonitor = MythicPlusModule.DungeonMonitor or {}
MythicPlusModule.DungeonMonitor = DungeonMonitor

--- Event payload definitions for editor tooling / IntelliSense
---@class ChallengeModeStartPayload
---@field mapID number

--- Supported dungeon event names
---@alias DungeonEvent
---| "TWICH_DUNGEON_START"
---| "TWICH_DUNGEON_COMPLETION"
---| "CHALLENGE_MODE_START"
---| "CHALLENGE_MODE_COMPLETED"
---| "CHALLENGE_MODE_RESET"
---| "ENCOUNTER_START"
---| "ENCOUNTER_END"
---| "PLAYER_DEAD"
---| "PLAYER_ENTERING_WORLD"
---| "GROUP_ROSTER_UPDATE"
---| "CHAT_MSG_LOOT"

---@class TwichDungeonCompletionPayload
---@field mapID number|nil
---@field level number|nil
---@field timeSec number|nil
---@field timeMS number|nil
---@field onTime boolean|nil
---@field upgradeLevels number|nil
---@field practiceRun boolean|nil
---@field source string|nil
---@field raw any[]|nil


---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type ToolsModule
local Tools = T:GetModule("Tools")

--[[ NOTE: Actively avoiding combat-related events for now, to prevent issues in Midnight. Will enhance later. ]]
local EVENTS = {
    --- CHALLENGE MODE SPECIFIC
    "CHALLENGE_MODE_START",               -- fires when key is activated
    "CHALLENGE_MODE_COMPLETED",           -- fires when the run is completed
    "CHALLENGE_MODE_RESET",               -- detect aborts or resets mid-key, can mark as abandoned or depleted
    "CHALLENGE_MODE_DEATH_COUNT_UPDATED", -- fires when death count changes

    --- DUNGEON SPECIFIC
    "ENCOUNTER_START", -- track boss encounters starting
    "ENCOUNTER_END",   -- track boss encounters ending

    --- PLAYER SPECIFIC
    "PLAYER_DEAD", -- track player deaths during dungeon runs

    --- WORLD LEVEL
    "PLAYER_ENTERING_WORLD", -- to confirm if in an active M+ instance

    --- GROUP CHANGES
    "GROUP_ROSTER_UPDATE", -- track group changes during dungeon runs

    --- CHAT
    "CHAT_MSG_LOOT", -- track loot messages during dungeon runs (forwarded; consumers decide whether to record)
}

local CONFIGURATION = {}

local Module = Tools.Generics.Module:New(CONFIGURATION, EVENTS)
local CallbackHandler = Tools.Callback.New()

--- Invoke registered callbacks for an event.
---@param event string
---@param ... any
local function InvokeCallbacks(event, ...)
    CallbackHandler:Invoke(event, ...)
end

--- Handle incoming module events and forward them to registered callbacks.
-- Intended to be called via colon syntax: `DungeonMonitor:EventHandler(event, ...)`.
---@param event string
---@param ... any
function DungeonMonitor:EventHandler(event, ...)
    if not self.enabled then return end

    -- Intercept CHALLENGE_MODE_START to resolve dungeon info immediately
    if event == "CHALLENGE_MODE_START" then
        local mapID = ...
        -- If mapID is not provided in the event (it usually is), try to get it
        if not mapID then
            mapID = C_ChallengeMode.GetActiveChallengeMapID()
        end

        if mapID then
            local name = C_ChallengeMode.GetMapUIInfo(mapID)

            -- Fallback to C_ChallengeMode.GetMapInfo
            if not name and C_ChallengeMode.GetMapInfo then
                local info = C_ChallengeMode.GetMapInfo(mapID)
                if info and info.name then
                    name = info.name
                end
            end

            -- Fallback to C_Map
            if not name then
                local mapInfo = C_Map.GetMapInfo(mapID)
                if mapInfo then
                    name = mapInfo.name
                end
            end

            if name then
                Logger.Debug(string.format("DungeonMonitor: Resolved dungeon '%s' (ID: %s)", name, tostring(mapID)))
                InvokeCallbacks("TWICH_DUNGEON_START", mapID, name)
            end
        end
    end

    -- Intercept completion to emit a stable TwichUI completion payload.
    if event == "CHALLENGE_MODE_COMPLETED" then
        local mapID = ...
        if not mapID and C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
            mapID = C_ChallengeMode.GetActiveChallengeMapID()
        end

        ---@type TwichDungeonCompletionPayload
        local payload = {
            mapID = tonumber(mapID) or mapID,
            source = "CHALLENGE_MODE_COMPLETED",
        }

        if C_ChallengeMode and type(C_ChallengeMode.GetChallengeCompletionInfo) == "function" then
            local ok, a, b, c, d, e, f = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
            if ok then
                -- Observed return shape (varies by patch): mapID, level, time, onTime, upgradeLevels, practiceRun
                payload.raw = { a, b, c, d, e, f }
                payload.mapID = tonumber(a) or payload.mapID
                payload.level = tonumber(b) or nil

                local timeVal = tonumber(c)
                if timeVal then
                    -- Some APIs return ms, some seconds. Assume seconds if small.
                    if timeVal > 10000 then
                        payload.timeMS = timeVal
                        payload.timeSec = timeVal / 1000
                    else
                        payload.timeSec = timeVal
                        payload.timeMS = timeVal * 1000
                    end
                end

                if type(d) == "boolean" then
                    payload.onTime = d
                end
                payload.upgradeLevels = tonumber(e) or nil
                if type(f) == "boolean" then
                    payload.practiceRun = f
                end

                payload.source = "C_ChallengeMode.GetChallengeCompletionInfo"
            end
        end

        InvokeCallbacks("TWICH_DUNGEON_COMPLETION", payload)
    end

    Logger.Debug("Dungeon monitor delegating received event: " .. tostring(event))
    InvokeCallbacks(event, ...)
end

function DungeonMonitor:Enable()
    if self.enabled then return end

    -- Bind instance method so the module invokes with the correct `self`.
    -- WoW OnEvent handlers receive (frame, eventName, ...). Normalize so downstream
    -- callbacks always receive (eventName, ...).
    Module:Enable(function(a1, a2, ...)
        if type(a1) == "string" then
            -- Defensive: if an upstream caller already stripped the frame.
            self:EventHandler(a1, a2, ...)
            return
        end

        self:EventHandler(a2, ...)
    end)
    self.enabled = true

    Logger.Debug("Dungeon monitor enabled")
end

function DungeonMonitor:Disable()
    if not self.enabled then return end
    Module:Disable()
    self.enabled = false

    Logger.Debug("Dungeon monitor disabled")
end

--- Register a callback for dungeon events.
--- Example signatures:
---  - function(event: "CHALLENGE_MODE_START", mapID: number) end
---  - function(event: DungeonEvent, ...) end
---@param callback fun(event: "CHALLENGE_MODE_START", mapID: number)|fun(event: "TWICH_DUNGEON_COMPLETION", payload: TwichDungeonCompletionPayload)|fun(event: DungeonEvent, ...)
---@return any handle
function DungeonMonitor:RegisterCallback(callback)
    return CallbackHandler:Register(callback)
end

--- Unregister a previously registered callback.
---@param handle any The handle returned from `RegisterCallback`
function DungeonMonitor:UnregisterCallback(handle)
    CallbackHandler:Unregister(handle)
end

--- Simulate a dungeon event by forwarding it through the same callback pipeline.
--- This is intended for developer tooling (e.g. Simulator) and does not require the
--- event to be registered on the underlying event frame.
---@param event string
---@param ... any
function DungeonMonitor:SimulateEvent(event, ...)
    if not self.enabled then
        Logger.Warn("Dungeon monitor is disabled; simulated event dropped: " .. tostring(event))
        return
    end
    self:EventHandler(event, ...)
end
