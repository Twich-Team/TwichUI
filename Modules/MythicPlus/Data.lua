--[[
    Mythic+ Data module. Contains constants and data related to Mythic+ dungeons, affixes, and other relevant information.
]]

local T = unpack(Twich)
local _G = _G

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@class MythicPlusDataSubmodule
local Data = MythicPlusModule.Data or {}
MythicPlusModule.Data = Data

---@type table<number, number> where the key is the level of the keystone at which an affix is introduced, and the value is the total number of affixes at that level and above.
Data.AffixLevels = {
    [4] = 1,
    [7] = 2,
    [10] = 3,
    [12] = 4,
}

Data.MythicPlusScoreConfig = {
    BASE_SCORE = 155,           -- Base score for a +2 keystone
    SCORE_PER_LEVEL = 15,       -- Additional score per keystone level above +2
    AFFIX_BONUS_SCORE = 15,     -- Bonus score for each new affix introduced
    TIME_BONUS_MAX = 15,        -- Maximum time bonus score
    TIME_BONUS_THRESHOLD = 0.4, -- Threshold for time bonus (40% faster than par time)
}

--[[
    Lightweight cache helpers

    These caches are intentionally small and conservative:
    - Map UI info is stable for long periods; caching avoids repeated API calls while
      rendering/refreshing panels.
    - Season IDs/maps change infrequently; caching avoids repeated season queries.

    Cache invalidation is event-driven where possible.
]]

---@class MythicPlusDataCache
---@field mapUIInfo table<number, {name:string|nil, timeLimitSeconds:number|nil, texture:number|string|nil, backgroundTexture:number|string|nil}>
---@field seasonId number|nil
---@field seasonMaps table<number, number[]>|nil keyed by seasonId

---@type MythicPlusDataCache
Data._cache = Data._cache or { mapUIInfo = {}, seasonId = nil, seasonMaps = nil }

---@param mapId number
---@return string|nil name
---@return number|nil timeLimitSeconds
---@return number|string|nil texture
---@return number|string|nil backgroundTexture
function Data.GetMapUIInfo(mapId)
    mapId = tonumber(mapId)
    if not mapId then return nil, nil, nil, nil end

    local C_ChallengeMode = _G.C_ChallengeMode
    if not C_ChallengeMode then return nil, nil, nil, nil end

    if type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local name, _, timeLimitSeconds, texture, backgroundTexture = C_ChallengeMode.GetMapUIInfo(mapId)
        return name, tonumber(timeLimitSeconds), texture, backgroundTexture
    end

    if type(C_ChallengeMode.GetMapInfo) == "function" then
        local info = C_ChallengeMode.GetMapInfo(mapId)
        if type(info) == "table" then
            return info.name, tonumber(info.timeLimitSeconds or info.timeLimit), info.texture, info.backgroundTexture
        end
    end

    return nil, nil, nil, nil
end

---@param mapId number
---@param force boolean|nil
---@return string|nil name
---@return number|nil timeLimitSeconds
---@return number|string|nil texture
---@return number|string|nil backgroundTexture
function Data.GetMapUIInfoCached(mapId, force)
    mapId = tonumber(mapId)
    if not mapId then return nil, nil, nil, nil end

    local cache = Data._cache
    if not force and cache and cache.mapUIInfo and cache.mapUIInfo[mapId] then
        local entry = cache.mapUIInfo[mapId]
        return entry.name, entry.timeLimitSeconds, entry.texture, entry.backgroundTexture
    end

    local name, timeLimitSeconds, texture, backgroundTexture = Data.GetMapUIInfo(mapId)
    Data._cache.mapUIInfo[mapId] = {
        name = name,
        timeLimitSeconds = timeLimitSeconds,
        texture = texture,
        backgroundTexture = backgroundTexture,
    }
    return name, timeLimitSeconds, texture, backgroundTexture
end

---@param mapId number
---@param force boolean|nil
---@return string|nil
function Data.GetMapNameCached(mapId, force)
    local name = Data.GetMapUIInfoCached(mapId, force)
    return name
end

function Data.ClearMapCache()
    if Data._cache and Data._cache.mapUIInfo then
        wipe(Data._cache.mapUIInfo)
    end
end

function Data.ClearSeasonCache()
    Data._cache.seasonId = nil
    Data._cache.seasonMaps = nil
end

---@return number|nil
function Data.GetCurrentSeasonIdCached()
    if Data._cache.seasonId ~= nil then
        return Data._cache.seasonId
    end

    local C_MythicPlus = _G.C_MythicPlus
    if not C_MythicPlus or type(C_MythicPlus.GetCurrentSeason) ~= "function" then
        return nil
    end

    local ok, seasonId = pcall(C_MythicPlus.GetCurrentSeason)
    if ok then
        Data._cache.seasonId = tonumber(seasonId)
        return Data._cache.seasonId
    end

    return nil
end

---@return number[]|nil mapIds
function Data.GetCurrentSeasonMapsCached()
    local seasonId = Data.GetCurrentSeasonIdCached()
    if not seasonId then return nil end

    if Data._cache.seasonMaps and Data._cache.seasonMaps[seasonId] then
        return Data._cache.seasonMaps[seasonId]
    end

    local C_MythicPlus = _G.C_MythicPlus
    if not C_MythicPlus or type(C_MythicPlus.GetSeasonMaps) ~= "function" then
        return nil
    end

    local ok, maps = pcall(C_MythicPlus.GetSeasonMaps, seasonId)
    if ok and type(maps) == "table" then
        Data._cache.seasonMaps = Data._cache.seasonMaps or {}
        Data._cache.seasonMaps[seasonId] = maps
        return maps
    end

    return nil
end

local function EnsureCacheEventFrame()
    if Data.__twichuiCacheEventFrame then
        return Data.__twichuiCacheEventFrame
    end

    local f = _G.CreateFrame("Frame")
    Data.__twichuiCacheEventFrame = f
    return f
end

function Data.InitCacheEvents()
    if Data.__twichuiCacheEventsInitialized then return end
    Data.__twichuiCacheEventsInitialized = true

    local f = EnsureCacheEventFrame()

    -- CHALLENGE_MODE_MAPS_UPDATE fires when challenge mode map data updates.
    -- PLAYER_ENTERING_WORLD is a safe general reset point.
    f:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")

    f:SetScript("OnEvent", function(_, event)
        if event == "CHALLENGE_MODE_MAPS_UPDATE" then
            Data.ClearMapCache()
            Data.ClearSeasonCache()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Avoid holding stale data across login/reload/transitions.
            Data.ClearMapCache()
            Data.ClearSeasonCache()
        end
    end)
end

Data.InitCacheEvents()

--- Determines how many affixes are present on a given keystone level.
---@param keystoneLevel integer the level of the keystone to get affixes for
---@return integer affixes a count of how many affixes would be attached to a keystone of the provided level
function Data.GetAffixCountForKeystoneLevel(keystoneLevel)
    keystoneLevel = tonumber(keystoneLevel) or 0
    local affixCount = 0
    local bestLevel = 0
    for level, count in pairs(Data.AffixLevels) do
        if keystoneLevel >= level and level > bestLevel then
            bestLevel = level
            affixCount = count
        end
    end
    return affixCount
end
