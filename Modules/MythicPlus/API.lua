local T = unpack(Twich)

--- @type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")

--- @type LoggerModule
local Logger = T:GetModule("Logger")

--- @class MythicPlusAPISubmodule
local API = MythicPlusModule.API or {}
MythicPlusModule.API = API

local MythicPlus = C_MythicPlus
local ChallengeMode = C_ChallengeMode

--- @class PlayerKeystoneInfo
--- @field dungeonID number
--- @field level number
--- @field affixes table<number, number> list of affix IDs

local function ShouldSimulate(funcName)
    if not MythicPlusModule.Simulator then
        return false
    end

    if not MythicPlusModule.Simulator.enabled then
        return false
    end

    return MythicPlusModule.Simulator:CanSimulate(funcName)
end

---@return table|nil simRun
local function GetSimRun()
    local sim = MythicPlusModule and MythicPlusModule.Simulator
    if not sim or type(sim.IsSimulating) ~= "function" or not sim:IsSimulating() then
        return nil
    end
    if type(sim.GetActiveRun) ~= "function" then
        return nil
    end
    local run = sim:GetActiveRun()
    return (type(run) == "table") and run or nil
end

---@return table|nil apiState
local function GetSimAPIState()
    local sim = MythicPlusModule and MythicPlusModule.Simulator
    if not sim or type(sim.IsSimulating) ~= "function" or not sim:IsSimulating() then
        return nil
    end
    if type(sim.GetAPIState) ~= "function" then
        return nil
    end
    local st = sim:GetAPIState()
    return (type(st) == "table") and st or nil
end

---@return PlayerKeystoneInfo | nil
function API:GetPlayerKeystone()
    local function SafeCall(fn, ...)
        if type(fn) ~= "function" then
            return nil
        end

        local ok, a, b, c, d, e = pcall(fn, ...)
        if not ok then
            return nil
        end

        return a, b, c, d, e
    end

    -- During simulation, prefer recorded run metadata.
    do
        local simRun = GetSimRun()
        if type(simRun) == "table" then
            local mapId = tonumber(simRun.mapID or simRun.mapId)
            local level = tonumber(simRun.level)
            local affixes = (type(simRun.affixes) == "table") and simRun.affixes or {}
            if mapId and mapId > 0 and level and level > 0 then
                return {
                    dungeonID = mapId,
                    level = level,
                    affixes = affixes,
                }
            end
        end
    end

    local mythicPlus = MythicPlus
    if not mythicPlus then
        return nil
    end

    -- Preferred modern API: explicit map + level
    local dungeonID = SafeCall(mythicPlus.GetOwnedKeystoneChallengeMapID)
    local level = SafeCall(mythicPlus.GetOwnedKeystoneLevel)

    -- Fallback API variants seen across expansions/patches.
    if (not dungeonID or dungeonID == 0) or (not level or level == 0) then
        local a, b = SafeCall(mythicPlus.GetOwnedKeystoneInfo)
        if type(a) == "number" and a > 0 then
            dungeonID = dungeonID or a
        end
        if type(b) == "number" and b > 0 then
            level = level or b
        end
    end

    if not dungeonID or dungeonID == 0 or not level or level == 0 then
        return nil
    end

    local affixes = {}

    -- If the client exposes per-keystone affix IDs, prefer those.
    if type(mythicPlus.GetOwnedKeystoneAffixID) == "function" then
        for i = 1, 10 do
            local affixID = SafeCall(mythicPlus.GetOwnedKeystoneAffixID, i)
            if not affixID or affixID == 0 then
                break
            end
            affixes[#affixes + 1] = affixID
        end
    end

    -- Otherwise, fall back to weekly Mythic+ affixes.
    if #affixes == 0 and type(mythicPlus.GetCurrentAffixes) == "function" then
        local currentAffixes = SafeCall(mythicPlus.GetCurrentAffixes)
        if type(currentAffixes) == "table" then
            for _, affix in ipairs(currentAffixes) do
                local affixID = (type(affix) == "table" and (affix.id or affix.affixID or affix.affixId)) or nil
                if type(affixID) == "number" and affixID > 0 then
                    affixes[#affixes + 1] = affixID
                end
            end
        end
    end

    ---@type PlayerKeystoneInfo
    local info = {
        dungeonID = dungeonID,
        level = level,
        affixes = affixes,
    }

    return info
end

---@return number|nil mapId
function API:GetActiveChallengeMapID()
    local simState = GetSimAPIState()
    if simState and simState.active then
        return tonumber(simState.mapId) or nil
    end

    local cm = ChallengeMode
    if cm and type(cm.GetActiveChallengeMapID) == "function" then
        local ok, v = pcall(cm.GetActiveChallengeMapID)
        if ok then
            v = tonumber(v)
            if v and v > 0 then return v end
        end
    end
    return nil
end

---@return number deaths
function API:GetDeathCount()
    local simState = GetSimAPIState()
    if simState and simState.active then
        return tonumber(simState.deathCount) or 0
    end

    local cm = ChallengeMode
    if cm and type(cm.GetDeathCount) == "function" then
        local ok, v = pcall(cm.GetDeathCount)
        if ok then
            return tonumber(v) or 0
        end
    end
    return 0
end

---@return boolean active
function API:IsChallengeModeActive()
    local simState = GetSimAPIState()
    if simState then
        return simState.active and true or false
    end

    local cm = ChallengeMode
    if cm and type(cm.IsChallengeModeActive) == "function" then
        local ok, v = pcall(cm.IsChallengeModeActive)
        if ok then
            return v and true or false
        end
    end
    return false
end

---@return number|nil overallScore
function API:GetOverallDungeonScore()
    -- During simulation we don't have a meaningful "current player" score.
    if GetSimAPIState() then
        return nil
    end

    local cm = ChallengeMode
    if cm and type(cm.GetOverallDungeonScore) == "function" then
        local ok, v = pcall(cm.GetOverallDungeonScore)
        if ok then
            return tonumber(v) or 0
        end
    end

    return 0
end

-- Mirrors `C_ChallengeMode.GetActiveKeystoneInfo()` for callers that want the *active* run.
-- Return shape varies across patches; we forward whatever the client provides.
function API:GetActiveKeystoneInfo()
    local simState = GetSimAPIState()
    if simState and simState.active then
        return tonumber(simState.mapId) or nil, tonumber(simState.level) or nil
    end

    local cm = ChallengeMode
    if cm and type(cm.GetActiveKeystoneInfo) == "function" then
        local ok, a, b, c, d, e = pcall(cm.GetActiveKeystoneInfo)
        if ok then
            return a, b, c, d, e
        end
    end
    return nil
end

-- Mirrors `C_ChallengeMode.GetChallengeCompletionInfo()`.
-- During simulation we derive this from the recorded completion payload.
function API:GetChallengeCompletionInfo()
    local simState = GetSimAPIState()
    if simState and simState.completed then
        local comp = simState.completion
        if type(comp) == "table" then
            local mapId = tonumber(comp.mapID or comp.mapId) or tonumber(simState.mapId)
            local level = tonumber(comp.level) or tonumber(simState.level)
            local timeMS = tonumber(comp.timeMS)
            local timeSec = tonumber(comp.timeSec)
            local onTime = comp.onTime
            local upgradeLevels = tonumber(comp.upgradeLevels)
            local practiceRun = comp.practiceRun

            if timeMS == nil and timeSec ~= nil then
                timeMS = timeSec * 1000
            end
            if timeSec == nil and timeMS ~= nil then
                timeSec = timeMS / 1000
            end
            if onTime == nil and upgradeLevels ~= nil then
                onTime = upgradeLevels > 0
            end

            -- Prefer ms if present (DungeonMonitor already normalizes).
            return mapId, level, timeMS or timeSec, onTime, upgradeLevels, practiceRun
        end
        return tonumber(simState.mapId) or nil, tonumber(simState.level) or nil
    end

    local cm = ChallengeMode
    if cm and type(cm.GetChallengeCompletionInfo) == "function" then
        local ok, a, b, c, d, e, f = pcall(cm.GetChallengeCompletionInfo)
        if ok then
            return a, b, c, d, e, f
        end
    end
    return nil
end

---@return table|nil affixes
function API:GetCurrentAffixes()
    local simState = GetSimAPIState()
    if simState and type(simState.affixes) == "table" and #simState.affixes > 0 then
        local out = {}
        for _, id in ipairs(simState.affixes) do
            local n = tonumber(id)
            if n and n > 0 then
                out[#out + 1] = { id = n }
            end
        end
        return out
    end

    local mp = MythicPlus
    if mp and type(mp.GetCurrentAffixes) == "function" then
        local ok, affixes = pcall(mp.GetCurrentAffixes)
        if ok then
            return affixes
        end
    end

    return nil
end

function API:RequestCurrentAffixes()
    -- During simulation, there's nothing to request.
    if GetSimAPIState() then return end
    local mp = MythicPlus
    if mp and type(mp.RequestCurrentAffixes) == "function" then
        pcall(mp.RequestCurrentAffixes)
    end
end

---@param mapId number
---@return string|nil name
function API:GetMapUIInfo(mapId)
    mapId = tonumber(mapId)
    if not mapId or mapId <= 0 then return nil end

    local mpData = MythicPlusModule and MythicPlusModule.Data
    if mpData and type(mpData.GetMapNameCached) == "function" then
        local name = mpData.GetMapNameCached(mapId)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end

    local cm = ChallengeMode
    if cm and type(cm.GetMapUIInfo) == "function" then
        local ok, name = pcall(cm.GetMapUIInfo, mapId)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return nil
end

---@param affixId number
---@return string|nil name
---@return string|nil description
---@return number|nil fileDataId
function API:GetAffixInfo(affixId)
    affixId = tonumber(affixId)
    if not affixId or affixId <= 0 then return nil, nil, nil end

    local cm = ChallengeMode
    if cm and type(cm.GetAffixInfo) == "function" then
        local ok, name, description, fileDataId = pcall(cm.GetAffixInfo, affixId)
        if ok then
            return name, description, fileDataId
        end
    end
    return nil, nil, nil
end

-- Compatibility: some callers may expect this name.
function API:GetPlayerKeystoneInfo()
    return self:GetPlayerKeystone()
end

-- Compatibility for the misspelling used in some notes/requests.
API.GetPLayerKeystoneInfo = API.GetPlayerKeystoneInfo
