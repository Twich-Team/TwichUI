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

-- Compatibility: some callers may expect this name.
function API:GetPlayerKeystoneInfo()
    return self:GetPlayerKeystone()
end

-- Compatibility for the misspelling used in some notes/requests.
API.GetPLayerKeystoneInfo = API.GetPlayerKeystoneInfo
