--[[
    Mythic+ Score calculator.

    * I could not find official documentation on how Mythic+ scores are calculated, so I am relying on Mr.Mythical here: https://mrmythical.com/rating-calculator
        It should produce a fairly accurate approximation of the score based on available data.

    * Keystones start at +2 and scale infinitely.
    * The base score for a +2 keystone is 155 points.
    * Each additional key level adds 15 points to the base score.
    * Besides the base score, clearing certain key levels with new affixes will earn you bonus points: +4, +7, +10, and +12 each award an extra 15 points for increased difficulty.
    * Completing a Mythic+ dungeon quickly not only awards you an even higher keystone but also grants extra score. The time bonus scales linearly from 0% to 40% faster than the par time, awarding up to an additional 15 points.
]]

local T = unpack(Twich)

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@class MythicPlusScoreCalculatorSubmodule
local ScoreCalculator = MythicPlusModule.ScoreCalculator or {}

---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type MythicPlusDataSubmodule
local Data = MythicPlusModule.Data


--- Calculate the Mythic+ score for a completed keystone run.
--
-- Parameters:
-- - `keystoneLevel` (integer): The numeric level of the completed keystone (keystones start at 2).
-- - `completedInTime` (number|nil): The time in seconds the dungeon was completed in. If `nil`, no time bonus is applied.
-- - `parTime` (number|nil): The par time in seconds used to compute time bonuses. If `nil` or <= 0, time bonuses are skipped.
--
-- Returns:
-- - (integer) The total Mythic+ score for the run (base + affix bonuses + time bonus).
--
-- Notes:
-- - Uses configuration values from `Data.MythicPlusScoreConfig` and affix counts from `Data.GetAffixCountForKeystoneLevel`.
-- - Does NOT take into account the Fortified/Tyrannical split.
---@param keystoneLevel integer
---@param completedInTime number|nil
---@param parTime number|nil
---@return integer
function ScoreCalculator.Calculate(keystoneLevel, completedInTime, parTime)
    -- determine score of keystone based on level alone
    local baseScore = Data.MythicPlusScoreConfig.BASE_SCORE +
        ((keystoneLevel - 2) * Data.MythicPlusScoreConfig.SCORE_PER_LEVEL)

    -- add in bonuses for affixes
    local affixCount = Data.GetAffixCountForKeystoneLevel(keystoneLevel)
    if affixCount then
        baseScore = baseScore + (affixCount * Data.MythicPlusScoreConfig.AFFIX_BONUS_SCORE)
    end

    -- add in time bonus
    local timeBonus = 0
    if completedInTime and parTime and parTime > 0 then
        local timeRatio = completedInTime / parTime
        if timeRatio < 0.6 then
            timeBonus = Data.MythicPlusScoreConfig.TIME_BONUS_MAX
        elseif timeRatio < 1.0 then
            timeBonus = math.floor((1.0 - timeRatio) / Data.MythicPlusScoreConfig.TIME_BONUS_THRESHOLD *
                Data.MythicPlusScoreConfig.TIME_BONUS_MAX)
        end
    end

    local totalScore = baseScore + timeBonus
    return totalScore
end
