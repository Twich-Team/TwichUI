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
---@field upgrade number +1, +2, +3
---@field group table<string, string> Role -> Class/Spec string
---@field loot table<string, string>[] List of item links

---@class MythicPlusDatabase_CharacterEntry
---@field Metadata MythicPlusDatabase_CharacterEntry_Metadata
---@field KeystoneData MythicPlusDatabase_CharacterEntry_Keystone
---@field Runs MythicPlusDatabase_RunEntry[]


---@class MythicPlusDatabase
---@field Characters table<string, MythicPlusDatabase_CharacterEntry> key is UnitGUID
---@field DungeonSession DungeonSession|nil current active dungeon session

--- local cached vars
local UnitGUID = UnitGUID
local UnitName = UnitName
local GetRealmName = GetRealmName
local UnitClass = UnitClass
local UnitFactionGroup = UnitFactionGroup
local GetBuildInfo = GetBuildInfo

local function GetDB()
    if not _G.TwichUIDungeonDB then
        _G.TwichUIDungeonDB = {}
    end
    return _G.TwichUIDungeonDB
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
    }
end

function Database:GetForCurrentCharacter()
    local playerGUID = UnitGUID("player")
    local db = GetDB()

    if not db[playerGUID] then
        InitCurrentCharacter(playerGUID)
    end
    return db[playerGUID]
end

---@param runData MythicPlusDatabase_RunEntry
function Database:AddRun(runData)
    local charDB = self:GetForCurrentCharacter()
    if not charDB.Runs then charDB.Runs = {} end

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
