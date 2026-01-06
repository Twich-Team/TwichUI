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
local GetSpecializationInfoByID = _G.GetSpecializationInfoByID
local GetInspectSpecialization = _G.GetInspectSpecialization
local NotifyInspect = _G.NotifyInspect
local ClearInspectPlayer = _G.ClearInspectPlayer
local CanInspect = _G.CanInspect
local InCombatLockdown = _G.InCombatLockdown
local GetTime = _G.GetTime
local date = _G.date
local time = _G.time
local GetBuildInfo = _G.GetBuildInfo
local C_ChallengeMode = _G.C_ChallengeMode
local C_Timer = _G.C_Timer
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local LOCALIZED_CLASS_NAMES_MALE = _G.LOCALIZED_CLASS_NAMES_MALE
local LOCALIZED_CLASS_NAMES_FEMALE = _G.LOCALIZED_CLASS_NAMES_FEMALE

local callbackID = nil

-- Holds the most recent roster snapshot payload so simulations/remote logs can apply it
-- even when GROUP_ROSTER_SNAPSHOT arrives before CHALLENGE_MODE_START.
local PendingGroupSnapshot = nil

---@class DungeonSession
---@field mapID number
---@field mapChallengeModeID number|nil
---@field dungeonName string|nil
---@field startUnix number
---@field level number|nil
---@field affixes number[]|nil
---@field deaths number|nil
---@field groupStart table|nil
---@field groupStartRoster table|nil
---@field group table|nil
---@field groupRoster table|nil
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

---@param link string
---@return number|nil
local function TryGetItemIdFromLink(link)
    if type(link) ~= "string" or link == "" then
        return nil
    end
    local itemId = link:match("item:(%d+):")
    itemId = itemId and tonumber(itemId) or nil
    if itemId and itemId > 0 then
        return itemId
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
        return nil, nil
    end

    return info.level, info.affixes
end

---@param playerName string|nil
---@param guid string|nil
---@param playerGuid string|nil
---@return boolean
local function IsPlayerLoot(playerName, guid, playerGuid)
    if playerGuid and guid and guid == playerGuid then
        return true
    end

    if type(playerName) ~= "string" or playerName == "" then
        return false
    end

    local myName, myRealm
    if type(UnitName) == "function" then
        myName, myRealm = UnitName("player")
    end

    if type(myName) ~= "string" or myName == "" then
        return false
    end

    if playerName == myName then
        return true
    end

    if type(myRealm) == "string" and myRealm ~= "" then
        local full = myName .. "-" .. myRealm
        if playerName == full then
            return true
        end
        -- Sometimes chat formats as "Name - Realm".
        if playerName == (myName .. " - " .. myRealm) then
            return true
        end
    end

    return false
end

local function PersistSession()
    Database:SetDungeonSession(DungeonSession)
end

---@param v any
---@return string|nil classFile
local function NormalizeClassFileToken(v)
    if type(v) ~= "string" or v == "" then
        return nil
    end

    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[v] then
        return v
    end

    local up = v:upper()
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[up] then
        return up
    end

    if type(LOCALIZED_CLASS_NAMES_MALE) == "table" then
        for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            if localized == v then
                return token
            end
        end
    end

    if type(LOCALIZED_CLASS_NAMES_FEMALE) == "table" then
        for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            if localized == v then
                return token
            end
        end
    end

    return nil
end

---@param group table|nil
---@return table
local function BuildGroupRosterFromSnapshot(group)
    local out = {}
    if type(group) ~= "table" then
        return out
    end

    for _, member in ipairs(group) do
        if type(member) == "table" then
            local classFile = NormalizeClassFileToken(member.classFile or member.class)
            if not classFile and type(member.spec) == "string" and member.spec ~= "" then
                local lastWord = member.spec:match("([^%s]+)$")
                classFile = NormalizeClassFileToken(lastWord)
            end

            local specId = member.specId or member.specID or member.specializationID or member.specializationId
            if type(specId) ~= "number" or specId <= 0 then
                specId = nil
            end

            out[#out + 1] = {
                guid = member.guid,
                name = member.name,
                realm = member.realm,
                role = member.role,
                spec = member.spec,
                specId = specId,
                class = member.class,
                classFile = classFile,
            }
        end
    end

    return out
end

---@return table
local function BuildGroupRosterFromLive()
    local out = {}

    local function Add(unit)
        if not UnitName or not UnitGUID or not UnitGUID(unit) then
            return
        end

        local guid = UnitGUID(unit)
        if type(guid) ~= "string" or guid == "" then
            return
        end

        local name, realm = UnitName(unit)
        local classFile
        if type(UnitClass) == "function" then
            local _, cf = UnitClass(unit)
            classFile = cf
        end
        classFile = NormalizeClassFileToken(classFile)

        local specName, specId = nil, nil
        if unit == "player" and type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
            local specIndex = GetSpecialization()
            if specIndex then
                local id, name2 = GetSpecializationInfo(specIndex)
                if type(name2) == "string" and name2 ~= "" then
                    specName = name2
                end
                if type(id) == "number" and id > 0 then
                    specId = id
                end
            end
        end

        out[#out + 1] = {
            guid = guid,
            name = name,
            realm = realm,
            role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil,
            spec = specName,
            specId = specId,
            class = nil,
            classFile = classFile,
        }
    end

    Add("player")

    if not IsInGroup or not IsInGroup() then
        return out
    end
    if IsInRaid and IsInRaid() then
        return out
    end

    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if count <= 0 then
        return out
    end

    for i = 1, 4 do
        Add("party" .. tostring(i))
    end

    return out
end

local InspectState = {
    token = 0,
    active = false,
    inFlight = nil, -- { unit=string, guid=string }
    queue = nil,    -- string[]
    rounds = 0,
    maxRounds = 4,
}

---@param roster table|nil
---@param guid string
---@param specId number|nil
---@param specName string|nil
---@return boolean changed
local function ApplySpecToRoster(roster, guid, specId, specName)
    if type(roster) ~= "table" then
        return false
    end
    local changed = false
    for _, m in ipairs(roster) do
        if type(m) == "table" and m.guid == guid then
            if type(specId) == "number" and specId > 0 and (type(m.specId) ~= "number" or m.specId <= 0) then
                m.specId = specId
                changed = true
            end
            if type(specName) == "string" and specName ~= "" and (type(m.spec) ~= "string" or m.spec == "") then
                m.spec = specName
                changed = true
            end
        end
    end
    return changed
end

---@return boolean
local function IsInspectAvailable()
    return type(NotifyInspect) == "function" and type(GetInspectSpecialization) == "function" and
    type(UnitGUID) == "function"
end

---@return boolean
local function SessionNeedsSpecEnrichment()
    if not DungeonSession or DungeonSession.completed then
        return false
    end
    if type(DungeonSession.groupRoster) ~= "table" then
        return false
    end
    for _, m in ipairs(DungeonSession.groupRoster) do
        if type(m) == "table" and m.guid and (type(m.spec) ~= "string" or m.spec == "") and
            (type(m.specId) ~= "number" or m.specId <= 0) then
            return true
        end
    end
    return false
end

---@return string[]
local function BuildInspectQueueFromSession()
    local out = {}
    if not DungeonSession or type(DungeonSession.groupRoster) ~= "table" then
        return out
    end

    local missing = {}
    for _, m in ipairs(DungeonSession.groupRoster) do
        if type(m) == "table" and type(m.guid) == "string" and m.guid ~= "" then
            local hasSpec = (type(m.spec) == "string" and m.spec ~= "") or (type(m.specId) == "number" and m.specId > 0)
            if not hasSpec then
                missing[m.guid] = true
            end
        end
    end

    for i = 1, 4 do
        local unit = "party" .. tostring(i)
        local guid = UnitGUID and UnitGUID(unit)
        if type(guid) == "string" and missing[guid] then
            out[#out + 1] = unit
        end
    end

    return out
end

local function StopInspectLoop()
    InspectState.active = false
    InspectState.inFlight = nil
    InspectState.queue = nil
    InspectState.rounds = 0
end

local function TryInspectNext(token)
    if InspectState.token ~= token or not InspectState.active then
        return
    end
    if not DungeonSession or DungeonSession.completed then
        StopInspectLoop()
        return
    end
    if not IsInspectAvailable() then
        StopInspectLoop()
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(1.0, function() TryInspectNext(token) end)
        end
        return
    end
    if InspectState.inFlight then
        return
    end

    if not InspectState.queue or #InspectState.queue == 0 then
        if not SessionNeedsSpecEnrichment() or (InspectState.rounds or 0) >= (InspectState.maxRounds or 4) then
            StopInspectLoop()
            return
        end

        InspectState.rounds = (InspectState.rounds or 0) + 1
        InspectState.queue = BuildInspectQueueFromSession()
        if not InspectState.queue or #InspectState.queue == 0 then
            StopInspectLoop()
            return
        end
    end

    local unit = table.remove(InspectState.queue, 1)
    if type(unit) ~= "string" or unit == "" then
        TryInspectNext(token)
        return
    end

    local guid = UnitGUID(unit)
    if type(guid) ~= "string" or guid == "" then
        TryInspectNext(token)
        return
    end

    if type(CanInspect) == "function" then
        local ok, can = pcall(CanInspect, unit)
        if ok and can == false then
            TryInspectNext(token)
            return
        end
    end

    InspectState.inFlight = { unit = unit, guid = guid }

    pcall(NotifyInspect, unit)

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(1.5, function()
            if InspectState.token ~= token or not InspectState.active then
                return
            end
            if InspectState.inFlight and InspectState.inFlight.guid == guid then
                InspectState.inFlight = nil
                if type(ClearInspectPlayer) == "function" then
                    pcall(ClearInspectPlayer)
                end
                TryInspectNext(token)
            end
        end)
    end
end

---@param reason string|nil
local function StartInspectLoop(reason)
    if not DungeonSession or DungeonSession.completed then
        return
    end
    if not IsInspectAvailable() then
        return
    end
    if not IsInGroup or not IsInGroup() then
        return
    end
    if IsInRaid and IsInRaid() then
        return
    end
    if not SessionNeedsSpecEnrichment() then
        return
    end

    InspectState.token = (InspectState.token or 0) + 1
    InspectState.active = true
    InspectState.inFlight = nil
    InspectState.queue = BuildInspectQueueFromSession()
    InspectState.rounds = 0

    Logger.Debug("DataCollector: Starting party spec inspect loop (" .. tostring(reason or "") .. ")")

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.25, function() TryInspectNext(InspectState.token) end)
    else
        TryInspectNext(InspectState.token)
    end
end

---@param name string|nil
---@param realm string|nil
---@return string
local function FormatFullName(name, realm)
    name = tostring(name or "")
    realm = tostring(realm or "")
    if name == "" then
        return "Unknown"
    end
    if realm ~= "" and not name:find("-", 1, true) then
        return name .. "-" .. realm
    end
    return name
end

---@param group table|nil
---@return table<string, string>
local function BuildGroupMapFromSnapshot(group)
    local out = {}
    if type(group) ~= "table" then
        return out
    end

    local dpsIndex = 1
    for _, member in ipairs(group) do
        if type(member) == "table" then
            local fullName = FormatFullName(member.name, member.realm)
            local specOrClass = member.spec or member.class
            local label = fullName
            if type(specOrClass) == "string" and specOrClass ~= "" then
                label = label .. " (" .. specOrClass .. ")"
            end

            local role = tostring(member.role or "")
            if role == "TANK" then
                out.tank = label
            elseif role == "HEALER" then
                out.healer = label
            else
                out["dps" .. tostring(dpsIndex)] = label
                dpsIndex = dpsIndex + 1
            end
        end
    end

    return out
end

---@return table|nil completion
local function TryGetCompletionInfoFallback()
    if not C_ChallengeMode then
        return nil
    end

    if type(C_ChallengeMode.GetChallengeCompletionInfo) == "function" then
        local ok, mapId, level, timeVal, onTime, upgradeLevels, practiceRun = pcall(C_ChallengeMode
            .GetChallengeCompletionInfo)
        if ok then
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
                practiceRun = practiceRun,
                source = "C_ChallengeMode.GetChallengeCompletionInfo",
            }
        end
    end

    ---@diagnostic disable-next-line: deprecated
    if type(C_ChallengeMode.GetCompletionInfo) == "function" then
        ---@diagnostic disable-next-line: deprecated
        local ok, mapId, level, timeVal, onTime, upgradeLevels = pcall(C_ChallengeMode.GetCompletionInfo)
        if not ok then
            return nil
        end

        local timeSec
        if type(timeVal) == "number" then
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

    return nil
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
    local mapChallengeModeID = tonumber(DungeonSession.mapChallengeModeID)
    local level = tonumber(DungeonSession.level) or
        tonumber(DungeonSession.completion and DungeonSession.completion.level) or 0

    local timeSec = tonumber(DungeonSession.completion and DungeonSession.completion.timeSec)
    if timeSec == nil and tonumber(DungeonSession.completion and DungeonSession.completion.timeMS) ~= nil then
        timeSec = tonumber(DungeonSession.completion.timeMS) / 1000
    end
    local deaths = tonumber(DungeonSession.deaths) or 0

    local scoringMapId = mapChallengeModeID or mapId
    local onTime, upgrade = ComputeTiming(scoringMapId, level, timeSec)

    -- If we can't compute from par time, prefer the recorded completion markers.
    if DungeonSession.completion and DungeonSession.completion.onTime ~= nil then
        onTime = DungeonSession.completion.onTime and true or false
    end
    if upgrade == nil and DungeonSession.completion and tonumber(DungeonSession.completion.upgradeLevels) ~= nil then
        upgrade = tonumber(DungeonSession.completion.upgradeLevels)
    end

    local score
    if ScoreCalculator and type(ScoreCalculator.TryGetBlizzardRunScore) == "function" and scoringMapId and level and timeSec then
        score = select(1, ScoreCalculator.TryGetBlizzardRunScore(scoringMapId, level, timeSec))
    end
    if score == nil and ScoreCalculator and type(ScoreCalculator.CalculateForRun) == "function" and scoringMapId and level and timeSec then
        score = select(1, ScoreCalculator.CalculateForRun(scoringMapId, level, timeSec))
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
        mapChallengeModeID = mapChallengeModeID,
        dungeonName = DungeonSession.dungeonName,
        level = level,
        affixes = DungeonSession.affixes or {},
        score = tonumber(score) or 0,
        time = timeSec,
        onTime = onTime,
        deaths = deaths,
        upgrade = upgrade,
        groupStart = DungeonSession.groupStart,
        groupStartRoster = DungeonSession.groupStartRoster,
        group = DungeonSession.groupStart or DungeonSession.group or {},
        groupRoster = DungeonSession.groupRoster,
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
    PendingGroupSnapshot = nil
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

            local level, affixes

            -- During simulation, prefer the recorded run metadata instead of the player's live keystone.
            local sim = MythicPlusModule and MythicPlusModule.Simulator
            if sim and type(sim.GetActiveRun) == "function" then
                local simRun = sim:GetActiveRun()
                if type(simRun) == "table" and tonumber(simRun.mapId or simRun.mapID) == tonumber(mapID) then
                    level = tonumber(simRun.level) or
                        (type(simRun.completion) == "table" and tonumber(simRun.completion.level)) or nil
                    if type(simRun.affixes) == "table" and #simRun.affixes > 0 then
                        affixes = simRun.affixes
                    end
                end
            end

            if level == nil or affixes == nil then
                local l2, a2 = TryGetActiveKeystoneInfo(mapID)
                if level == nil then level = l2 end
                if affixes == nil then affixes = a2 end
            end
            DungeonSession = {
                mapID = tonumber(mapID) or mapID,
                mapChallengeModeID = nil,
                startUnix = time(),
                level = level,
                affixes = affixes,
                deaths = 0,
                group = BuildGroupMap(),
                groupStart = nil,
                groupRoster = BuildGroupRosterFromLive(),
                groupStartRoster = nil,
                loot = {},
                completed = false,
            }

            -- Default start group to whatever we have at session start.
            DungeonSession.groupStart = DungeonSession.group
            DungeonSession.groupStartRoster = DungeonSession.groupRoster

            -- If we received a roster snapshot before CHALLENGE_MODE_START (common in simulation/remote logs),
            -- use it as the initial group instead of the local live roster.
            if type(PendingGroupSnapshot) == "table" and type(PendingGroupSnapshot.group) == "table" and #PendingGroupSnapshot.group > 0 then
                local snap = BuildGroupMapFromSnapshot(PendingGroupSnapshot.group)
                local snapRoster = BuildGroupRosterFromSnapshot(PendingGroupSnapshot.group)
                DungeonSession.group = snap
                DungeonSession.groupStart = snap
                DungeonSession.groupRoster = snapRoster
                DungeonSession.groupStartRoster = snapRoster
            end

            PersistSession()
            Logger.Debug("Mythic+ dungeon started, mapID: " .. tostring(mapID))

            -- Try to enrich the live roster with spec info via INSPECT_READY.
            StartInspectLoop("challenge_mode_start")
            return
        end

        if eventName == "GROUP_ROSTER_UPDATE" then
            if not DungeonSession then return end
            local payload = ...
            local groupList = nil
            if type(payload) == "table" then
                if type(payload.group) == "table" then
                    groupList = payload.group
                elseif payload.group == nil and #payload > 0 then
                    groupList = payload
                end
            end

            if type(groupList) == "table" and #groupList > 0 then
                DungeonSession.group = BuildGroupMapFromSnapshot(groupList)
                DungeonSession.groupRoster = BuildGroupRosterFromSnapshot(groupList)
            else
                DungeonSession.group = BuildGroupMap()
                DungeonSession.groupRoster = BuildGroupRosterFromLive()
            end
            PersistSession()

            -- Roster update may have introduced new units; try to inspect missing specs.
            StartInspectLoop("group_roster_update")
            return
        end

        if eventName == "INSPECT_READY" then
            if not DungeonSession or DungeonSession.completed then return end
            local guid = ...
            if type(guid) ~= "string" or guid == "" then
                return
            end

            local unit = nil
            if InspectState.inFlight and InspectState.inFlight.guid == guid then
                unit = InspectState.inFlight.unit
            else
                for i = 1, 4 do
                    local u = "party" .. tostring(i)
                    if UnitGUID and UnitGUID(u) == guid then
                        unit = u
                        break
                    end
                end
            end

            local specId, specName = nil, nil
            if unit and type(GetInspectSpecialization) == "function" then
                local ok, sid = pcall(GetInspectSpecialization, unit)
                if ok and type(sid) == "number" and sid > 0 then
                    specId = sid
                    if type(GetSpecializationInfoByID) == "function" then
                        local ok2, _, sname = pcall(GetSpecializationInfoByID, sid)
                        if ok2 and type(sname) == "string" and sname ~= "" then
                            specName = sname
                        end
                    end
                end
            end

            local changed = false
            if specId or specName then
                changed = ApplySpecToRoster(DungeonSession.groupRoster, guid, specId, specName) or changed
                changed = ApplySpecToRoster(DungeonSession.groupStartRoster, guid, specId, specName) or changed
            end
            if changed then
                PersistSession()
            end

            if type(ClearInspectPlayer) == "function" then
                pcall(ClearInspectPlayer)
            end

            if InspectState.inFlight and InspectState.inFlight.guid == guid then
                InspectState.inFlight = nil
                if C_Timer and type(C_Timer.After) == "function" then
                    C_Timer.After(0.10, function() TryInspectNext(InspectState.token) end)
                else
                    TryInspectNext(InspectState.token)
                end
            end

            return
        end

        if eventName == "GROUP_ROSTER_SNAPSHOT" then
            local payload = ...
            local groupList = nil
            if type(payload) == "table" then
                if type(payload.group) == "table" then
                    groupList = payload.group
                elseif payload.group == nil and #payload > 0 then
                    groupList = payload
                end
            end

            if type(groupList) == "table" and #groupList > 0 then
                PendingGroupSnapshot = { group = groupList }
                if DungeonSession then
                    local snap = BuildGroupMapFromSnapshot(groupList)
                    local snapRoster = BuildGroupRosterFromSnapshot(groupList)
                    DungeonSession.group = snap
                    DungeonSession.groupRoster = snapRoster
                    if type(DungeonSession.groupStart) ~= "table" or next(DungeonSession.groupStart) == nil then
                        DungeonSession.groupStart = snap
                    end
                    if type(DungeonSession.groupStartRoster) ~= "table" or #DungeonSession.groupStartRoster == 0 then
                        DungeonSession.groupStartRoster = snapRoster
                    end
                    PersistSession()
                end
            end
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

        if eventName == "TWICH_DUNGEON_COMPLETION" then
            local payload = ...
            if type(payload) ~= "table" then
                payload = {}
            end

            if not DungeonSession then
                Logger.Warn("A Mythic+ dungeon completion detected without an active session")
                return
            end

            local raw1 = nil
            if type(payload.raw) == "table" then
                raw1 = payload.raw[1]
            end

            local cmID = tonumber(payload.mapChallengeModeID) or tonumber(payload.mapChallengeModeId)
                or tonumber(payload.challengeModeID) or tonumber(payload.challengeModeId)
            if cmID == nil and type(raw1) == "table" then
                cmID = tonumber(raw1.mapChallengeModeID) or tonumber(raw1.mapChallengeModeId)
                    or tonumber(raw1.challengeModeID) or tonumber(raw1.challengeModeId)
            end
            if cmID ~= nil then
                DungeonSession.mapChallengeModeID = cmID
            end

            local mapID = tonumber(payload.mapID) or tonumber(payload.mapId) or
                (DungeonSession and tonumber(DungeonSession.mapID)) or payload.mapID or payload.mapId

            local payloadLevel = tonumber(payload.level)
            if payloadLevel == nil and type(raw1) == "table" then
                payloadLevel = tonumber(raw1.level)
            end

            local timeSec = tonumber(payload.timeSec)
            local timeMS = tonumber(payload.timeMS)
            if timeSec == nil and timeMS ~= nil then
                timeSec = timeMS / 1000
            end
            if timeSec == nil and type(raw1) == "table" and tonumber(raw1.time) ~= nil then
                -- Blizzard completion info commonly reports ms in `time`.
                timeMS = tonumber(raw1.time)
                timeSec = timeMS / 1000
            end

            local upgradeLevels = tonumber(payload.upgradeLevels)
            if upgradeLevels == nil and type(raw1) == "table" then
                upgradeLevels = tonumber(raw1.keystoneUpgradeLevels)
            end

            local onTime = payload.onTime
            if onTime == nil and type(raw1) == "table" then
                onTime = raw1.onTime
                if onTime == nil and upgradeLevels ~= nil then
                    onTime = upgradeLevels > 0
                end
            end

            -- IMPORTANT: During simulation, CHALLENGE_MODE_COMPLETED may trigger DungeonMonitor to
            -- synthesize a TWICH_DUNGEON_COMPLETION using live APIs (which can return stale/zero values).
            -- Never allow a 0/empty completion to clobber a real recorded completion.
            do
                local existing = DungeonSession.completion
                local existingTime = (type(existing) == "table") and tonumber(existing.timeSec) or nil
                if existingTime == nil and type(existing) == "table" and tonumber(existing.timeMS) ~= nil then
                    existingTime = tonumber(existing.timeMS) / 1000
                end
                local existingLevel = (type(existing) == "table") and tonumber(existing.level) or nil

                local incomingTime = tonumber(timeSec)
                if incomingTime == nil and tonumber(timeMS) ~= nil then
                    incomingTime = tonumber(timeMS) / 1000
                end
                local incomingLevel = tonumber(payloadLevel)

                -- If we already have a valid time/level, ignore incoming updates that don't.
                if existingTime and existingTime > 0 and (incomingTime == nil or incomingTime <= 0) then
                    return
                end
                if existingLevel and existingLevel > 0 and (incomingLevel == nil or incomingLevel <= 0) then
                    return
                end

                -- Also ignore payloads that contain basically no information.
                local hasUseful = (mapID ~= nil) and (
                    (incomingTime ~= nil and incomingTime > 0) or (incomingLevel ~= nil and incomingLevel > 0) or
                    onTime ~= nil or (upgradeLevels ~= nil and upgradeLevels > 0) or cmID ~= nil or
                    (type(payload.raw) == "table" and #payload.raw > 0))
                if not hasUseful and existingTime and existingTime > 0 then
                    return
                end
            end

            -- Prefer simulator metadata before consulting live keystone info.
            if payloadLevel == nil or type(DungeonSession.affixes) ~= "table" or #DungeonSession.affixes == 0 then
                local sim = MythicPlusModule and MythicPlusModule.Simulator
                if sim and type(sim.GetActiveRun) == "function" then
                    local simRun = sim:GetActiveRun()
                    if type(simRun) == "table" and tonumber(simRun.mapId or simRun.mapID) == tonumber(mapID) then
                        if payloadLevel == nil then
                            payloadLevel = tonumber(simRun.level) or
                                (type(simRun.completion) == "table" and tonumber(simRun.completion.level)) or nil
                        end
                        if (type(DungeonSession.affixes) ~= "table" or #DungeonSession.affixes == 0) and type(simRun.affixes) == "table" and #simRun.affixes > 0 then
                            DungeonSession.affixes = simRun.affixes
                        end
                    end
                end

                if payloadLevel == nil or type(DungeonSession.affixes) ~= "table" or #DungeonSession.affixes == 0 then
                    local level, affixes = TryGetActiveKeystoneInfo(mapID)
                    if payloadLevel == nil and level then
                        payloadLevel = level
                    end
                    if (type(DungeonSession.affixes) ~= "table" or #DungeonSession.affixes == 0) and affixes and #affixes > 0 then
                        DungeonSession.affixes = affixes
                    end
                end
            end

            if payloadLevel ~= nil then
                DungeonSession.level = payloadLevel
            end

            -- Extra: if the payload didn't contain affixes, but the simulator run JSON did, keep them.
            if (type(DungeonSession.affixes) ~= "table" or #DungeonSession.affixes == 0) then
                local sim = MythicPlusModule and MythicPlusModule.Simulator
                if sim and type(sim.GetActiveRun) == "function" then
                    local simRun = sim:GetActiveRun()
                    if type(simRun) == "table" and tonumber(simRun.mapId or simRun.mapID) == tonumber(mapID) then
                        if type(simRun.affixes) == "table" and #simRun.affixes > 0 then
                            DungeonSession.affixes = simRun.affixes
                        end
                    end
                end
            end

            DungeonSession.completion = {
                mapID = mapID,
                level = payloadLevel or DungeonSession.level,
                timeSec = timeSec,
                timeMS = timeMS or (timeSec and timeSec * 1000) or nil,
                onTime = onTime,
                upgradeLevels = upgradeLevels or nil,
                practiceRun = payload.practiceRun or (type(raw1) == "table" and raw1.practiceRun) or nil,
                source = payload.source,
            }
            DungeonSession.completed = true
            DungeonSession.completedAt = time()
            PersistSession()

            Logger.Debug("Mythic+ dungeon completed (challenge completion info), mapID: " .. tostring(mapID))
            return
        end

        if eventName == "CHAT_MSG_LOOT" then
            if not DungeonSession then return end

            local msg, playerName, _, _, _, _, _, _, _, _, _, guid = ...
            local playerGuid = UnitGUID and UnitGUID("player")
            if not IsPlayerLoot(playerName, guid, playerGuid) then
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
                DungeonSession.loot[#DungeonSession.loot + 1] = {
                    link = link,
                    itemId = TryGetItemIdFromLink(link),
                    quantity = qty,
                }
            end

            PersistSession()
            return
        end

        if eventName == "CHALLENGE_MODE_RESET" then
            if not DungeonSession then return end
            Logger.Debug("Mythic+ dungeon reset/aborted, ending session")
            DungeonSession = nil
            PendingGroupSnapshot = nil
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
