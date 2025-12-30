--[[
    Mythic+ Data module. Contains constants and data related to Mythic+ dungeons, affixes, and other relevant information.
]]

local T = unpack(Twich)

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@class MythicPlusDataSubmodule
local Data = MythicPlusModule.Data or {}

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
