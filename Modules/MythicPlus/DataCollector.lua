--[[
    Data collector is responsible for gathering Mythic+ related data during dungeon runs.
    It listens to DungeonMonitor events, aggregates a run record, and writes completed runs
    to the MythicPlus database.
]]

---@diagnostic disable-next-line: undefined-global
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

---@type MythicPlusDungeonMonitorSubmodule
local DungeonMonitor = MythicPlusModule.DungeonMonitor

---@type MythicPlusAPISubmodule
local API = MythicPlusModule.API

---@type MythicPlusScoreCalculatorSubmodule
local ScoreCalculator = MythicPlusModule.ScoreCalculator

local _G = _G
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetSpecialization = _G.GetSpecialization
local GetSpecializationInfo = _G.GetSpecializationInfo
local date = _G.date
local time = _G.time
local GetBuildInfo = _G.GetBuildInfo
local C_ChallengeMode = _G.C_ChallengeMode

local callbackID = nil

---@class DungeonSession
---@field mapID number
---@field dungeonName string|nil
---@field startUnix number
---@field level number|nil
---@field affixes number[]|nil
---@field deaths number|nil
---@field group table|nil
---@field loot table|nil
---@field completion table|nil
---@field completed boolean|nil
---@field completedAt number|nil
---@type DungeonSession|nil
DungeonSession = nil

---@param msg string
---@return string[]
local function ExtractItemLinks(msg)
    if type(msg) ~= "string" or msg == "" then
        return {}
    end

    local out = {}
    for link in msg:gmatch("(%|c%x+%|Hitem:.-%|h%[.-%]%|h%|r)") do
        out[#out + 1] = link
        if #out >= 10 then
            return out
        end
    end

    if #out == 0 then
        for link in msg:gmatch("(%|Hitem:.-%|h%[.-%]%|h)") do
            out[#out + 1] = link
            if #out >= 10 then
                return out
            end
        end
    end

    return out
end

---@param msg string
---@return number|nil
local function TryExtractQuantity(msg)
    if type(msg) ~= "string" or msg == "" then
        return nil
    end

    local qty = msg:match("x(%d+)")
    qty = qty and tonumber(qty) or nil
    if qty and qty > 0 then
        return qty
    end
    return nil
end

---@return table
local function BuildGroupMap()
    local group = {}

    local function GetSpecStringForUnit(unit)
        local className = select(1, UnitClass(unit))
        local classFile = select(2, UnitClass(unit))
        local displayClass = className or classFile or "Unknown"

        if unit == "player" and type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
            local specIndex = GetSpecialization()
            if specIndex then
                local _, specName = GetSpecializationInfo(specIndex)
                if type(specName) == "string" and specName ~= "" then
                    return specName .. " " .. tostring(displayClass)
                end
            end
        end

        return tostring(displayClass)
    end

    local function Assign(unit)
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
        local specStr = GetSpecStringForUnit(unit)

        if role == "TANK" then
            group.tank = specStr
            return
        end
        if role == "HEALER" then
            group.healer = specStr
            return
        end

        group.__dpsCount = (group.__dpsCount or 0) + 1
        group["dps" .. tostring(group.__dpsCount)] = specStr
    end

    Assign("player")

    if not IsInGroup or not IsInGroup() then
        group.__dpsCount = nil
        return group
    end

    if IsInRaid and IsInRaid() then
        group.__dpsCount = nil
        return group
    end

    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if count <= 0 then
        group.__dpsCount = nil
        return group
    end

    for i = 1, 4 do
        local unit = "party" .. tostring(i)
        if UnitGUID and UnitGUID(unit) then
            Assign(unit)
        end
    end

    group.__dpsCount = nil
    return group
end

---@param mapId number
---@param level number
---@param timeSec number
---@return boolean onTime
---@return number|nil upgrade
local function ComputeTiming(mapId, level, timeSec)
    mapId = tonumber(mapId)
    level = tonumber(level)
    timeSec = tonumber(timeSec)

    if not mapId or not level or not timeSec then
        return false, nil
    end

    local par = ScoreCalculator and ScoreCalculator.GetParTimeSeconds
        and ScoreCalculator.GetParTimeSeconds(mapId) or nil
    par = tonumber(par)
    if not par or par <= 0 then
        return false, nil
    end

    if timeSec > par then
        return false, nil
    end

    local ratio = timeSec / par
    if ratio <= 0.6 then
        return true, 3
    elseif ratio <= 0.8 then
        return true, 2
    end
    return true, 1
end

---@param mapId number|nil
---@return number|nil level
---@return number[]|nil affixes
local function TryGetActiveKeystoneInfo(mapId)
    if not API or type(API.GetPlayerKeystone) ~= "function" then
        return nil, nil
    end

    local info = API:GetPlayerKeystone()
    if not info then
        return nil, nil
    end

    if mapId and info.dungeonID and tonumber(mapId) ~= tonumber(info.dungeonID) then
        return info.level, info.affixes
    end

    return info.level, info.affixes
end

---@param msg string
---@param guid string|nil
---@param playerGuid string|nil
---@return boolean
local function IsPlayerLoot(msg, guid, playerGuid)
    if playerGuid and guid and guid == playerGuid then
        return true
    end

    if type(msg) == "string" then
        if msg:find("You receive", 1, true) then
            return true
        end

        local name, realm
        if type(UnitName) == "function" then
            name, realm = UnitName("player")
        end
        if type(name) == "string" and name ~= "" then
            local full = name
            if type(realm) == "string" and realm ~= "" then
                full = full .. "-" .. realm
            end

            if msg:find(full .. " receives", 1, true) or msg:find(name .. " receives", 1, true) then
                return true
            end
        end
    end

    return false
end

local function PersistSession()
    Database:SetDungeonSession(DungeonSession)
end

---@return table|nil completion
local function TryGetCompletionInfoFallback()
    ---@diagnostic disable-next-line: deprecated
    if not C_ChallengeMode or type(C_ChallengeMode.GetCompletionInfo) ~= "function" then
        return nil
    end

    ---@diagnostic disable-next-line: deprecated
    local ok, mapId, level, timeVal, onTime, upgradeLevels = pcall(C_ChallengeMode.GetCompletionInfo)
    if not ok then
        return nil
    end

    local timeSec
    if type(timeVal) == "number" then
        -- Some APIs return ms, some seconds.
        if timeVal > 10000 then
            timeSec = timeVal / 1000
        else
            timeSec = timeVal
        end
    end

    return {
        mapID = mapId,
        level = level,
        timeSec = timeSec,
        onTime = onTime,
        upgradeLevels = upgradeLevels,
        source = "C_ChallengeMode.GetCompletionInfo",
    }
end

---@param reason string
local function FinalizeSession(reason)
    if not DungeonSession then
        return
    end

    if DungeonSession.completed and type(DungeonSession.completion) ~= "table" then
        local fallback = TryGetCompletionInfoFallback()
        if type(fallback) == "table" and type(fallback.timeSec) == "number" then
            DungeonSession.completion = {
                mapID = fallback.mapID or DungeonSession.mapID,
                timeSec = fallback.timeSec,
                source = fallback.source,
            }
            if fallback.level then
                DungeonSession.level = tonumber(fallback.level) or DungeonSession.level
            end
        end
    end

    if not DungeonSession.completed or type(DungeonSession.completion) ~= "table" then
        Logger.Debug("DataCollector: Ending session without completion (" .. tostring(reason) .. ")")
        DungeonSession = nil
        Database:ResetDungeonSession()
        return
    end

    local mapId = tonumber(DungeonSession.mapID)
    local level = tonumber(DungeonSession.level) or 0
    local timeSec = tonumber(DungeonSession.completion.timeSec)
    local deaths = tonumber(DungeonSession.deaths) or 0

    local onTime, upgrade = ComputeTiming(mapId, level, timeSec)

    local score
    if ScoreCalculator and type(ScoreCalculator.TryGetBlizzardRunScore) == "function" and mapId and level and timeSec then
        score = select(1, ScoreCalculator.TryGetBlizzardRunScore(mapId, level, timeSec))
    end
    if score == nil and ScoreCalculator and type(ScoreCalculator.CalculateForRun) == "function" and mapId and level and timeSec then
        score = select(1, ScoreCalculator.CalculateForRun(mapId, level, timeSec))
    end

    local ts = time()
    local patch
    if type(GetBuildInfo) == "function" then
        patch = select(1, GetBuildInfo())
    end
    ---@type MythicPlusDatabase_RunEntry
    local run = {
        id = tostring(ts) .. "-" .. tostring(mapId),
        timestamp = ts,
        date = date("%Y-%m-%d %H:%M:%S", ts),
        patch = patch,
        mapId = mapId,
        level = level,
        affixes = DungeonSession.affixes or {},
        score = tonumber(score) or 0,
        time = timeSec,
        onTime = onTime,
        deaths = deaths,
        upgrade = upgrade,
        group = DungeonSession.group or {},
        loot = DungeonSession.loot or {},
    }

    Database:AddRun(run)

    ---@diagnostic disable-next-line: undefined-field
    if MythicPlusModule and MythicPlusModule.Runs and MythicPlusModule.Runs.Refresh and MythicPlusModule.MainWindow then
        local panel = MythicPlusModule.MainWindow:GetPanelFrame("runs")
        if panel and panel.IsShown and panel:IsShown() then
            ---@diagnostic disable-next-line: undefined-field
            MythicPlusModule.Runs:Refresh(panel)
        end
    end

    DungeonSession = nil
    Database:ResetDungeonSession()
end

function DataCollector:Enable()
    if self.enabled then return end
    self.enabled = true

    DungeonSession = Database:GetDungeonSession()
    if DungeonSession then
        Logger.Debug("Restored active Mythic+ session for map " .. tostring(DungeonSession.mapID))
    end

    callbackID = DungeonMonitor:RegisterCallback(function(eventName, ...)
        if eventName == "TWICH_DUNGEON_START" then
            local mapID, dungeonName = ...
            if DungeonSession and tonumber(DungeonSession.mapID) == tonumber(mapID) then
                if not DungeonSession.dungeonName and type(dungeonName) == "string" and dungeonName ~= "" then
                    DungeonSession.dungeonName = dungeonName
                    PersistSession()
                end
            end
            return
        end

        if eventName == "CHALLENGE_MODE_START" then
            local mapID = ...

            if DungeonSession then
                Logger.Warn("A lingering Mythic+ dungeon session is active. Overwriting with new session")
                DungeonSession = nil
                Database:ResetDungeonSession()
            end

            local level, affixes = TryGetActiveKeystoneInfo(mapID)
            DungeonSession = {
                mapID = tonumber(mapID) or mapID,
                startUnix = time(),
                level = level,
                affixes = affixes,
                deaths = 0,
                group = BuildGroupMap(),
                loot = {},
                completed = false,
            }
            PersistSession()

            Logger.Debug("Mythic+ dungeon started, mapID: " .. tostring(mapID))
            return
        end

        if eventName == "GROUP_ROSTER_UPDATE" then
            if not DungeonSession then return end
            DungeonSession.group = BuildGroupMap()
            PersistSession()
            return
        end

        if eventName == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
            if not DungeonSession then return end

            local count = ...
            if not count and C_ChallengeMode and type(C_ChallengeMode.GetDeathCount) == "function" then
                count = C_ChallengeMode.GetDeathCount()
            end

            DungeonSession.deaths = tonumber(count) or DungeonSession.deaths or 0
            PersistSession()
            return
        end

        if eventName == "CHALLENGE_MODE_COMPLETED" then
            if not DungeonSession then return end
            DungeonSession.completed = true
            DungeonSession.completedAt = time()
            PersistSession()
            return
        end

        if eventName == "CHALLENGE_MODE_COMPLETED_REWARDS" then
            local mapID, medal, timeMS, money, rewards = ...

            if not DungeonSession then
                Logger.Warn("A Mythic+ dungeon completion detected without an active session")
                return
            end

            local level, affixes = TryGetActiveKeystoneInfo(mapID)
            if level then DungeonSession.level = level end
            if affixes and #affixes > 0 then DungeonSession.affixes = affixes end

            local timeSec = (tonumber(timeMS) or 0) / 1000
            DungeonSession.completion = {
                mapID = mapID,
                medal = medal,
                timeMS = timeMS,
                timeSec = timeSec,
                money = money,
                rewards = rewards,
            }
            DungeonSession.completed = true
            PersistSession()

            Logger.Debug("Mythic+ dungeon completed (rewards), mapID: " .. tostring(mapID))
            return
        end

        if eventName == "CHAT_MSG_LOOT" then
            if not DungeonSession then return end

            local msg, _, _, _, _, _, _, _, _, _, _, guid = ...
            local playerGuid = UnitGUID and UnitGUID("player")
            if not IsPlayerLoot(msg, guid, playerGuid) then
                return
            end

            local links = ExtractItemLinks(msg)
            if #links == 0 then
                return
            end

            local qty = TryExtractQuantity(msg) or 1
            if type(DungeonSession.loot) ~= "table" then
                DungeonSession.loot = {}
            end

            for _, link in ipairs(links) do
                DungeonSession.loot[#DungeonSession.loot + 1] = { link = link, quantity = qty }
            end

            PersistSession()
            return
        end

        if eventName == "CHALLENGE_MODE_RESET" then
            if not DungeonSession then return end
            Logger.Debug("Mythic+ dungeon reset/aborted, ending session")
            DungeonSession = nil
            Database:ResetDungeonSession()
            return
        end

        if eventName == "PLAYER_ENTERING_WORLD" then
            local isCM = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive()
            if DungeonSession and not isCM then
                Logger.Debug("Left Mythic+ dungeon instance, ending session for map " .. tostring(DungeonSession.mapID))
                FinalizeSession("left_instance")
            end
            return
        end
    end)

    Logger.Debug("Mythic plus data collector enabled")
end

function DataCollector:Disable()
    if not self.enabled then return end
    self.enabled = false

    if callbackID then
        DungeonMonitor:UnregisterCallback(callbackID)
        callbackID = nil
    end

    Logger.Debug("Mythic plus data collector disabled")
end
