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
---| "INSPECT_READY"

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

local _G = _G
local C_Timer = _G.C_Timer
local C_ChallengeMode = _G.C_ChallengeMode
local C_Map = _G.C_Map

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

    --- INSPECTION
    "INSPECT_READY", -- used to enrich party roster with spec info

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

-- Some patches/clients fire CHALLENGE_MODE_START before mapID/name can be resolved.
-- Retry briefly so we reliably emit TWICH_DUNGEON_START for RunLogger/DataCollector.
local startResolve = {
    token = 0,
    emitted = false,
    mapID = nil,
    tries = 0,
    maxTries = 40,
    delay = 0.15,
}

---@param mapID any
---@return number|nil
local function NormalizeMapID(mapID)
    mapID = tonumber(mapID) or mapID
    if type(mapID) == "number" and mapID > 0 then
        return mapID
    end
    return nil
end

---@param mapID number
---@return string|nil
local function ResolveDungeonName(mapID)
    if not mapID then
        return nil
    end

    if C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end

    if C_ChallengeMode and type(C_ChallengeMode.GetMapInfo) == "function" then
        local info = C_ChallengeMode.GetMapInfo(mapID)
        if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end

    if C_Map and type(C_Map.GetMapInfo) == "function" then
        local mapInfo = C_Map.GetMapInfo(mapID)
        if type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
            return mapInfo.name
        end
    end

    return nil
end

---@return number|nil
local function GetBestActiveChallengeMapID()
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        local active = NormalizeMapID(C_ChallengeMode.GetActiveChallengeMapID())
        if active then
            return active
        end
    end

    -- Some clients expose keystone info with a mapID as the first return.
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
        local ok, a = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok then
            local active = NormalizeMapID(a)
            if active then
                return active
            end
        end
    end

    return nil
end

local function TryEmitDungeonStart(token)
    if startResolve.token ~= token or startResolve.emitted then
        return
    end

    local mapID = startResolve.mapID

    -- Always prefer the active challenge mapID when available. Some builds pass a different ID
    -- through CHALLENGE_MODE_START, which won't resolve via challenge mode lookup APIs.
    local activeMapID = GetBestActiveChallengeMapID()
    if activeMapID and activeMapID ~= mapID then
        mapID = activeMapID
        startResolve.mapID = activeMapID
    elseif not mapID then
        startResolve.mapID = activeMapID
        mapID = activeMapID
    end

    local name = ResolveDungeonName(mapID)
    if mapID and name then
        startResolve.emitted = true
        Logger.Debug(string.format("DungeonMonitor: Resolved dungeon '%s' (ID: %s)", name, tostring(mapID)))
        InvokeCallbacks("TWICH_DUNGEON_START", mapID, name)
        return
    end

    startResolve.tries = (startResolve.tries or 0) + 1
    if startResolve.tries >= (startResolve.maxTries or 40) then
        -- Fallback: always emit TWICH_DUNGEON_START once we have a mapID, even if the name isn't resolvable yet.
        if mapID then
            startResolve.emitted = true
            local fallbackName = name or ("Unknown (" .. tostring(mapID) .. ")")
            Logger.Warn(string.format(
                "DungeonMonitor: Failed to resolve dungeon name after %d tries; emitting TWICH_DUNGEON_START with fallback '%s' (ID: %s)",
                tonumber(startResolve.tries) or 0,
                tostring(fallbackName),
                tostring(mapID)
            ))
            InvokeCallbacks("TWICH_DUNGEON_START", mapID, fallbackName)
        end
        return
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(startResolve.delay or 0.15, function()
            TryEmitDungeonStart(token)
        end)
    end
end

--- Handle incoming module events and forward them to registered callbacks.
-- Intended to be called via colon syntax: `DungeonMonitor:EventHandler(event, ...)`.
---@param event string
---@param ... any
function DungeonMonitor:EventHandler(event, ...)
    if not self.enabled then return end

    -- Intercept CHALLENGE_MODE_START to resolve dungeon info immediately
    if event == "CHALLENGE_MODE_START" then
        startResolve.token = (startResolve.token or 0) + 1
        startResolve.emitted = false
        startResolve.tries = 0
        startResolve.mapID = NormalizeMapID(...)

        -- Try immediately, then retry briefly if needed.
        TryEmitDungeonStart(startResolve.token)
    end

    -- Intercept completion to emit a stable TwichUI completion payload.
    if event == "CHALLENGE_MODE_COMPLETED" then
        -- Stop any pending start-resolution attempts.
        startResolve.token = (startResolve.token or 0) + 1
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
