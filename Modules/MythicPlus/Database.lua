local T = unpack(Twich)

--- @type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")

--- @type LoggerModule
local Logger = T:GetModule("Logger")

--- @class MythicPlusDatabaseSubmodule
local Database = MythicPlusModule.Database or {}
MythicPlusModule.Database = Database

--[[
    MythicPlus Database Structure
]]
---@class MythicPlusDatabase_CharacterEntry_Metadata
---@field characterName string
---@field realmName string
---@field class string
---@field faction string

---@class MythicPlusDatabase_RunEntry
---@field id string Unique ID for the run (timestamp + mapId)
---@field timestamp number
---@field date string Formatted date
---@field patch string WoW patch version
---@field mapId number
---@field level number
---@field affixes number[]
---@field score number
---@field time number Seconds
---@field onTime boolean
---@field deaths number
---@field upgrade number +1, +2, +3
---@field group table<string, string> Role -> Class/Spec string
---@field loot table<string, string>[] List of item links
---@field importedFromBlizzard boolean|nil True if the run was created via Blizzard run history import.
---@field blizzardSync boolean|nil True if Blizzard data has been applied to this run.
---@field blizzardKey string|nil Stable-ish key for matching Blizzard run history entries.
---@field blizzardSyncedAt number|nil unix timestamp when last synced.
---@field blizzard table|nil Minimal snapshot of Blizzard fields used for sync.
---@field abandoned boolean|nil True if the run ended without completion (reset/left instance).

---@class MythicPlusDatabase_CharacterEntry
---@field Metadata MythicPlusDatabase_CharacterEntry_Metadata
---@field KeystoneData MythicPlusDatabase_CharacterEntry_Keystone
---@field Runs MythicPlusDatabase_RunEntry[]
---@field DungeonStats table<number, MythicPlusDatabase_DungeonStats>

---@class MythicPlusDatabase_DungeonStats
---@field mapId number
---@field totalTime number
---@field runs number
---@field completes number
---@field abandons number
---@field totalPlayerDeaths number
---@field totalGroupDeaths number
---@field loot table<string, number> itemId or link -> count
---@field composition table<string, table<string, number>> role -> class -> count


---@class MythicPlusDatabase
---@field Characters table<string, MythicPlusDatabase_CharacterEntry> key is UnitGUID
---@field DungeonSession DungeonSession|nil current active dungeon session
---@field Global table Global data shared across characters

--- local cached vars
local UnitGUID = UnitGUID
local UnitName = UnitName
local GetRealmName = GetRealmName
local UnitClass = UnitClass
local UnitFactionGroup = UnitFactionGroup
local GetBuildInfo = GetBuildInfo

local FALLBACK_DB = { Global = {} }

local function MigrateLegacyDB(db)
    if type(db) ~= "table" then return end
    db.Global = db.Global or {}
    if db.Global.__twichuiMythicPlusDBMigrated then
        return
    end

    local legacyCharacters = db.Characters
    if type(legacyCharacters) ~= "table" then
        legacyCharacters = db.characters
    end

    local migratedAny = false
    if type(legacyCharacters) == "table" then
        for guid, entry in pairs(legacyCharacters) do
            if type(guid) == "string" and type(entry) == "table" then
                if type(db[guid]) ~= "table" then
                    db[guid] = entry
                    migratedAny = true
                else
                    -- Merge legacy Runs into existing entry if needed.
                    local dst = db[guid]
                    dst.Runs = dst.Runs or {}
                    if type(entry.Runs) == "table" and #dst.Runs == 0 and #entry.Runs > 0 then
                        dst.Runs = entry.Runs
                        migratedAny = true
                    end
                    if type(dst.Metadata) ~= "table" and type(entry.Metadata) == "table" then
                        dst.Metadata = entry.Metadata
                        migratedAny = true
                    end
                    if type(dst.KeystoneData) ~= "table" and type(entry.KeystoneData) == "table" then
                        dst.KeystoneData = entry.KeystoneData
                        migratedAny = true
                    end
                end
            end
        end
    end

    if migratedAny then
        Logger.Info("Migrated legacy Mythic+ DB character entries.")
    end

    -- Mark as migrated to avoid doing work repeatedly.
    db.Global.__twichuiMythicPlusDBMigrated = true
end

local function GetDB()
    -- Prefer profile-scoped storage so data can differ by character/profile.
    local profile = (T.db and T.db.profile)
    if type(profile) == "table" then
        profile.mythicPlus = profile.mythicPlus or {}
        profile.mythicPlus.dungeonDB = profile.mythicPlus.dungeonDB or {}
        local db = profile.mythicPlus.dungeonDB
        db.Global = db.Global or {}
        MigrateLegacyDB(db)
        return db
    end
    return FALLBACK_DB
end

---@return table|nil
function Database:GetItemCache()
    local db = GetDB()
    return db.Global.ItemCache
end

---@param cache table
function Database:SetItemCache(cache)
    local db = GetDB()
    db.Global.ItemCache = cache
end

---@return string|nil
function Database:GetGameVersion()
    local db = GetDB()
    return db.Global.GameVersion
end

---@param version string
function Database:SetGameVersion(version)
    local db = GetDB()
    db.Global.GameVersion = version
end

---@return DungeonSession|nil
function Database:GetDungeonSession()
    local db = GetDB()
    return db.DungeonSession
end

function Database:ResetDungeonSession()
    local db = GetDB()
    db.DungeonSession = nil
end

--- Persist the active dungeon session into the saved DB.
---@param session DungeonSession|nil
function Database:SetDungeonSession(session)
    local db = GetDB()
    db.DungeonSession = session
end

---@param guid string the UnitGUID for the current character
local function InitCurrentCharacter(guid)
    local db = GetDB()
    -- checking if already initialized
    if db[guid] then
        return
    end

    Logger.Debug("Initializing Mythic+ database for character GUID: " .. guid)

    db[guid] = {
        Metadata = {
            characterName = UnitName("player") or "Unknown",
            realmName = GetRealmName() or "Unknown",
            class = select(2, UnitClass("player")) or "Unknown",
            faction = UnitFactionGroup("player") or "Unknown",
        },
        KeystoneData = {
            -- to be filled later
        },
        Runs = {},
        DungeonStats = {},
    }
end

function Database:GetForCurrentCharacter()
    local playerGUID = UnitGUID("player")
    local db = GetDB()

    if not db[playerGUID] then
        InitCurrentCharacter(playerGUID)
    end
    -- Ensure stats table exists for existing chars
    if not db[playerGUID].DungeonStats then
        db[playerGUID].DungeonStats = {}
    end
    return db[playerGUID]
end

---@param runData MythicPlusDatabase_RunEntry
function Database:AddRun(runData)
    local charDB = self:GetForCurrentCharacter()
    if not charDB.Runs then charDB.Runs = {} end

    -- Normalize core types so comparisons/sorts behave.
    runData.timestamp = tonumber(runData.timestamp) or runData.timestamp
    runData.mapId = tonumber(runData.mapId) or runData.mapId
    runData.level = tonumber(runData.level) or runData.level
    runData.score = tonumber(runData.score) or runData.score
    runData.time = tonumber(runData.time) or runData.time

    -- Ensure ID
    if not runData.id then
        runData.id = tostring(runData.timestamp) .. "-" .. tostring(runData.mapId)
    end

    -- Ensure Patch
    if not runData.patch then
        local version, build, date, tocversion = GetBuildInfo()
        runData.patch = version
    end

    table.insert(charDB.Runs, 1, runData) -- Insert at top
    Logger.Info("Added new Mythic+ run to database: " ..
        tostring(runData.mapId) .. " (+" .. tostring(runData.level) .. ")")

    if not runData.importedFromBlizzard then
        self:UpdateDungeonStatsFromRun(runData)
    end
end

function Database:DeleteRun(runId)
    local charDB = self:GetForCurrentCharacter()
    if not charDB.Runs then return false end

    for i, run in ipairs(charDB.Runs) do
        if run.id == runId then
            table.remove(charDB.Runs, i)
            Logger.Info("Deleted Mythic+ run: " .. tostring(runId))
            return true
        end
    end
    return false
end

function Database:GetRuns()
    local charDB = self:GetForCurrentCharacter()
    return charDB.Runs or {}
end

function Database:ClearRuns()
    local charDB = self:GetForCurrentCharacter()
    charDB.Runs = {}
    Logger.Info("Cleared all Mythic+ runs from database.")
end

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

local function GetBlizzardRunHistory()
    local C_MythicPlus = _G.C_MythicPlus
    if not C_MythicPlus or type(C_MythicPlus.GetRunHistory) ~= "function" then
        return nil
    end

    local history = SafeCall(C_MythicPlus.GetRunHistory)
    if type(history) == "table" then
        return history
    end

    local unpackFn = _G.unpack or unpack
    local tries = {
        { true,  true },
        { true,  false },
        { false, false },
    }
    for _, args in ipairs(tries) do
        history = SafeCall(C_MythicPlus.GetRunHistory, unpackFn(args))
        if type(history) == "table" then
            return history
        end
    end

    return nil
end

local function GetSeasonMapIds()
    local C_MythicPlus = _G.C_MythicPlus
    if not C_MythicPlus or type(C_MythicPlus.GetSeasonMaps) ~= "function" then
        return {}
    end

    local maps = SafeCall(C_MythicPlus.GetSeasonMaps)
    if type(maps) ~= "table" then
        return {}
    end

    local ids = {}
    for _, entry in ipairs(maps) do
        local mapId
        if type(entry) == "table" then
            mapId = tonumber(entry.mapChallengeModeID) or tonumber(entry.mapChallengeModeId)
                or tonumber(entry.challengeModeID) or tonumber(entry.challengeModeId)
                or tonumber(entry.mapID) or tonumber(entry.mapId)
                or tonumber(entry.id)
        else
            mapId = tonumber(entry)
        end
        if mapId and mapId > 0 then
            table.insert(ids, mapId)
        end
    end

    return ids
end

---@return table[] normalizedRuns
local function GetSeasonBestRunsFallback()
    local C_MythicPlus = _G.C_MythicPlus
    if not C_MythicPlus or type(C_MythicPlus.GetSeasonBestForMap) ~= "function" then
        return {}
    end

    local ids = GetSeasonMapIds()
    if #ids == 0 then
        return {}
    end

    local ScoreCalculator = MythicPlusModule and MythicPlusModule.ScoreCalculator
    local normalized = {}

    for _, mapId in ipairs(ids) do
        local seasonBest = SafeCall(C_MythicPlus.GetSeasonBestForMap, mapId)
        if type(seasonBest) == "table" then
            for _, run in ipairs(seasonBest) do
                if type(run) == "table" then
                    local level = tonumber(run.level) or tonumber(run.keystoneLevel) or tonumber(run.mythicLevel)
                    local durationSec = tonumber(run.durationSec) or tonumber(run.duration) or tonumber(run.time)
                    local score = tonumber(run.mapScore) or tonumber(run.runScore) or tonumber(run.score)
                        or tonumber(run.mythicRating)

                    if level and durationSec then
                        if not score and ScoreCalculator and type(ScoreCalculator.CalculateForRun) == "function" then
                            local approx = ScoreCalculator.CalculateForRun(mapId, level, durationSec)
                            score = tonumber(approx) or score
                        end

                        table.insert(normalized, {
                            mapId = mapId,
                            level = level,
                            durationSec = durationSec,
                            score = score,
                            completedAt = tonumber(run.completedTimestamp) or tonumber(run.completionTimestamp)
                                or tonumber(run.timestamp),
                            source = "seasonBest",
                        })
                    end
                end
            end
        end
    end

    return normalized
end

local function ExtractRunMapId(run)
    if type(run) ~= "table" then return nil end
    return tonumber(run.mapChallengeModeID)
        or tonumber(run.mapChallengeModeId)
        or tonumber(run.challengeModeID)
        or tonumber(run.challengeModeId)
        or tonumber(run.mapID)
        or tonumber(run.mapId)
end

local function ExtractRunLevel(run)
    if type(run) ~= "table" then return nil end
    return tonumber(run.level)
        or tonumber(run.keystoneLevel)
        or tonumber(run.mythicLevel)
end

local function ExtractRunDurationSec(run)
    if type(run) ~= "table" then return nil end
    local sec = tonumber(run.durationSec)
        or tonumber(run.duration)
        or tonumber(run.time)
        or tonumber(run.timeSec)
    if sec and sec > 0 then
        return sec
    end

    local ms = tonumber(run.durationMS)
        or tonumber(run.durationMs)
        or tonumber(run.timeMS)
        or tonumber(run.timeMs)
    if ms and ms > 0 then
        return ms / 1000
    end

    return nil
end

local function ExtractRunScore(run)
    if type(run) ~= "table" then return nil end
    return tonumber(run.mapScore)
        or tonumber(run.runScore)
        or tonumber(run.score)
        or tonumber(run.mythicRating)
end

local function ExtractRunCompletedAt(run)
    if type(run) ~= "table" then return nil end
    return tonumber(run.completedTimestamp)
        or tonumber(run.completionTimestamp)
        or tonumber(run.completedTime)
        or tonumber(run.completionTime)
        or tonumber(run.timestamp)
end

local function MakeBlizzardKey(mapId, level, durationSec, score, completedAt)
    mapId = tonumber(mapId)
    level = tonumber(level)
    durationSec = tonumber(durationSec)
    score = tonumber(score)
    completedAt = tonumber(completedAt)

    if not mapId or not level or not durationSec then
        return nil
    end

    local dur10 = math.floor((durationSec * 10) + 0.5)
    local score10 = score and math.floor((score * 10) + 0.5) or 0
    if completedAt and completedAt > 0 then
        return string.format("%d:%d:%d:%d:%d", completedAt, mapId, level, dur10, score10)
    end
    return string.format("%d:%d:%d:%d", mapId, level, dur10, score10)
end

local function FindMatchingRun(existingByMap, blz)
    local list = existingByMap[blz.mapId]
    if type(list) ~= "table" then return nil end

    local best
    local bestScore

    for _, run in ipairs(list) do
        if type(run) == "table" and tonumber(run.level) == tonumber(blz.level) then
            local t = tonumber(run.time)
            local dt = (t and blz.durationSec) and math.abs(t - blz.durationSec) or nil
            if dt and dt <= 2.0 then
                local s = 0
                if blz.completedAt and tonumber(run.timestamp) then
                    s = s + math.min(math.abs(tonumber(run.timestamp) - blz.completedAt) / 3600, 2)
                end
                s = s + dt
                if (not bestScore) or s < bestScore then
                    bestScore = s
                    best = run
                end
            end
        end
    end

    return best
end

-- When the locally-recorded run is missing `time` (common if completion payload was incomplete),
-- fall back to matching by timestamp proximity + key level within the same dungeon.
local function FindMatchingRunLoose(existingByMap, blz)
    if type(blz) ~= "table" then return nil end
    local list = existingByMap[blz.mapId]
    if type(list) ~= "table" then return nil end

    local best
    local bestScore

    local completedAt = tonumber(blz.completedAt)
    if not completedAt or completedAt <= 0 then
        return nil
    end

    for _, run in ipairs(list) do
        if type(run) == "table" and tonumber(run.level) == tonumber(blz.level) then
            local rt = tonumber(run.timestamp)
            if rt then
                local dtSec = math.abs(rt - completedAt)
                -- Only consider runs reasonably close in time to avoid merging wrong entries.
                if dtSec <= (30 * 60) then
                    -- Prefer runs with missing/zero duration; those are the ones we want to enrich.
                    local hasTime = tonumber(run.time) and tonumber(run.time) > 0
                    local score = dtSec + (hasTime and 999999 or 0)
                    if (not bestScore) or score < bestScore then
                        bestScore = score
                        best = run
                    end
                end
            end
        end
    end

    return best
end

---@class BlizzardRunSyncResult
---@field imported number
---@field updated number
---@field matched number
---@field scanned number

--- Import/sync Blizzard run history into the internal Runs database.
---
--- Behavior:
--- - Adds missing runs (marked `importedFromBlizzard=true`).
--- - Updates existing runs when they match (fills `score`/`time` from Blizzard; keeps your extra fields intact).
--- - Does not delete any runs.
---
--- @param opts table|nil
--- @return BlizzardRunSyncResult
function Database:SyncRunsFromBlizzard(opts)
    opts = type(opts) == "table" and opts or {}
    local throttleSeconds = tonumber(opts.throttleSeconds) or 30

    local charDB = self:GetForCurrentCharacter()
    charDB.Runs = charDB.Runs or {}

    local now = (type(_G.time) == "function" and _G.time()) or 0
    charDB.__blizzardSyncMeta = charDB.__blizzardSyncMeta or {}
    local meta = charDB.__blizzardSyncMeta
    if now > 0 and throttleSeconds > 0 and tonumber(meta.lastAt) and (now - tonumber(meta.lastAt)) < throttleSeconds then
        return { imported = 0, updated = 0, matched = 0, scanned = 0 }
    end
    meta.lastAt = now

    local history = GetBlizzardRunHistory()
    local historyIsNormalized = false
    if type(history) ~= "table" then
        history = nil
    end
    if type(history) == "table" and #history == 0 then
        -- Some clients/regions return an empty run history table even when the character
        -- has Season Bests. Fall back to importing from Season Best per-map data.
        local fallback = GetSeasonBestRunsFallback()
        if type(fallback) == "table" and #fallback > 0 then
            history = fallback
            historyIsNormalized = true
        end
    end
    if type(history) ~= "table" then
        return { imported = 0, updated = 0, matched = 0, scanned = 0 }
    end

    local existingByKey = {}
    local existingByMap = {}
    for _, run in ipairs(charDB.Runs) do
        if type(run) == "table" then
            -- Index by both UI mapId and challenge-mode map ids so Blizzard history can match either.
            local keys = {
                tonumber(run.mapId),
                tonumber(run.mapChallengeModeID) or tonumber(run.mapChallengeModeId),
                tonumber(run.challengeModeID) or tonumber(run.challengeModeId),
                tonumber(run.mapID) or tonumber(run.mapId),
            }
            local seen = {}
            for _, mid in ipairs(keys) do
                if mid and not seen[mid] then
                    seen[mid] = true
                    existingByMap[mid] = existingByMap[mid] or {}
                    table.insert(existingByMap[mid], run)
                end
            end
            if type(run.blizzardKey) == "string" and run.blizzardKey ~= "" then
                existingByKey[run.blizzardKey] = run
            end
        end
    end

    local imported, updated, matched = 0, 0, 0

    for _, raw in ipairs(history) do
        if type(raw) == "table" then
            local mapId, level, durationSec, score, completedAt
            local source

            if historyIsNormalized then
                mapId = tonumber(raw.mapId)
                level = tonumber(raw.level)
                durationSec = tonumber(raw.durationSec)
                score = tonumber(raw.score)
                completedAt = tonumber(raw.completedAt)
                source = raw.source
            else
                mapId = ExtractRunMapId(raw)
                level = ExtractRunLevel(raw)
                durationSec = ExtractRunDurationSec(raw)
                score = ExtractRunScore(raw)
                completedAt = ExtractRunCompletedAt(raw)
            end

            if mapId and level and durationSec then
                local blz = {
                    mapId = mapId,
                    level = level,
                    durationSec = durationSec,
                    score = score,
                    completedAt = completedAt,
                }
                local key = MakeBlizzardKey(mapId, level, durationSec, score, completedAt)

                local target = (key and existingByKey[key]) or FindMatchingRun(existingByMap, blz) or
                    FindMatchingRunLoose(existingByMap, blz)
                if target then
                    matched = matched + 1
                    if key and (not target.blizzardKey or target.blizzardKey == "") then
                        target.blizzardKey = key
                        existingByKey[key] = target
                    end

                    local changed = false
                    if score and (not tonumber(target.score) or math.abs((tonumber(target.score) or 0) - score) > 0.01) then
                        target.score = score
                        changed = true
                    end
                    if durationSec and (not tonumber(target.time) or tonumber(target.time) <= 0) then
                        target.time = durationSec
                        changed = true
                    end

                    -- Backfill missing level if needed.
                    if level and (not tonumber(target.level) or tonumber(target.level) <= 0) then
                        target.level = level
                        changed = true
                    end

                    -- Preserve the Blizzard map id as a challenge-mode id hint if we don't have one.
                    if mapId and (not tonumber(target.mapChallengeModeID) or tonumber(target.mapChallengeModeID) <= 0) then
                        target.mapChallengeModeID = mapId
                        changed = true
                    end

                    target.blizzardSync = true
                    target.blizzardSyncedAt = now
                    target.blizzard = {
                        mapScore = score,
                        durationSec = durationSec,
                        completedAt = completedAt,
                        source = source,
                    }

                    if changed then
                        updated = updated + 1
                    end
                else
                    local ts = (completedAt and completedAt > 0) and completedAt or now
                    local patch
                    if type(GetBuildInfo) == "function" then
                        patch = select(1, GetBuildInfo())
                    end

                    ---@type MythicPlusDatabase_RunEntry
                    local run = {
                        id = string.format("blz-%s-%s-%s", tostring(ts), tostring(mapId), tostring(level)),
                        timestamp = ts,
                        date = (type(_G.date) == "function") and _G.date("%Y-%m-%d %H:%M:%S", ts) or "",
                        patch = patch,
                        mapId = mapId,
                        mapChallengeModeID = mapId,
                        level = level,
                        affixes = {},
                        score = tonumber(score) or 0,
                        time = durationSec,
                        onTime = nil,
                        deaths = 0,
                        upgrade = nil,
                        group = {},
                        loot = {},
                        importedFromBlizzard = true,
                        blizzardSync = true,
                        blizzardKey = key,
                        blizzardSyncedAt = now,
                        blizzard = {
                            mapScore = score,
                            durationSec = durationSec,
                            completedAt = completedAt,
                            source = source,
                        }
                    }

                    self:AddRun(run)
                    imported = imported + 1

                    if key then
                        existingByKey[key] = run
                    end
                    existingByMap[mapId] = existingByMap[mapId] or {}
                    table.insert(existingByMap[mapId], run)
                end
            end
        end
    end

    return { imported = imported, updated = updated, matched = matched, scanned = #history }
end

function Database:RecordAbandon(mapId, time, deaths, playerDeaths)
    self:UpdateDungeonStats(mapId, {
        isRun = true,
        abandoned = true,
        time = time,
        groupDeaths = deaths,
        playerDeaths = playerDeaths
    })
end

function Database:UpdateDungeonStatsFromRun(run)
    if not run or not run.mapId then return end

    local isAbandoned = (run.abandoned == true)

    local comp = { tank = {}, healer = {}, dps = {} }
    if run.group then
        for _, member in pairs(run.group) do
            local role = member.role and member.role:lower()
            local cls = member.class
            if role and cls and (role == "tank" or role == "healer" or role == "dps" or role == "damager") then
                if role == "damager" then role = "dps" end
                local t = comp[role]
                t[cls] = (t[cls] or 0) + 1
            end
        end
    end

    local lootCounts = {}
    if run.loot then
        for _, item in ipairs(run.loot) do
            if item.itemId then
                local k = "item:" .. item.itemId
                lootCounts[k] = (lootCounts[k] or 0) + (item.quantity or 1)
            end
        end
    end

    local update = {
        isRun = true,
        completed = not isAbandoned,
        abandoned = isAbandoned,
        time = run.time,
        groupDeaths = run.deaths,
        playerDeaths = run.playerDeaths,
        loot = lootCounts,
        composition = comp
    }

    self:UpdateDungeonStats(run.mapId, update)
end

function Database:UpdateDungeonStats(mapId, data)
    mapId = tonumber(mapId)
    if not mapId then return end
    local charDB = self:GetForCurrentCharacter()
    if not charDB.DungeonStats then charDB.DungeonStats = {} end

    local stats = charDB.DungeonStats[mapId]
    if not stats then
        stats = {
            mapId = mapId,
            totalTime = 0,
            runs = 0,
            completes = 0,
            abandons = 0,
            totalPlayerDeaths = 0,
            totalGroupDeaths = 0,
            loot = {},
            composition = {
                tank = {},
                healer = {},
                dps = {},
            }
        }
        charDB.DungeonStats[mapId] = stats
    end

    if data.isRun then stats.runs = (stats.runs or 0) + 1 end
    if data.completed then stats.completes = (stats.completes or 0) + 1 end
    if data.abandoned then stats.abandons = (stats.abandons or 0) + 1 end
    if data.time then stats.totalTime = (stats.totalTime or 0) + data.time end
    if data.playerDeaths then stats.totalPlayerDeaths = (stats.totalPlayerDeaths or 0) + data.playerDeaths end
    if data.groupDeaths then stats.totalGroupDeaths = (stats.totalGroupDeaths or 0) + data.groupDeaths end

    if data.loot then
        stats.loot = stats.loot or {}
        for item, count in pairs(data.loot) do
            stats.loot[item] = (stats.loot[item] or 0) + count
        end
    end

    if data.composition then
        stats.composition = stats.composition or {}
        for role, classes in pairs(data.composition) do
            local roleT = stats.composition[role]
            if not roleT then
                roleT = {}
                stats.composition[role] = roleT
            end
            for cls, count in pairs(classes) do
                roleT[cls] = (roleT[cls] or 0) + count
            end
        end
    end
end
