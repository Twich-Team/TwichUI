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
MythicPlusModule.ScoreCalculator = ScoreCalculator

---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type MythicPlusDataSubmodule
local Data = MythicPlusModule.Data

---@return MythicPlusDataSubmodule|nil
local function GetData()
    Data = Data or (MythicPlusModule and MythicPlusModule.Data) or nil
    return Data
end

local _G = _G
local C_ChallengeMode = _G.C_ChallengeMode
local C_MythicPlus = _G.C_MythicPlus
local unpackFn = _G.unpack or unpack

local function RoundTo(x, decimals)
    x = tonumber(x)
    if not x then return 0 end
    decimals = tonumber(decimals) or 0
    local p = 10 ^ decimals
    return math.floor(x * p + 0.5) / p
end

---@param mapId number|nil
---@return number|nil parTimeSeconds
function ScoreCalculator.GetParTimeSeconds(mapId)
    mapId = tonumber(mapId)
    if not mapId or mapId <= 0 or not C_ChallengeMode then
        return nil
    end

    if type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local ok, name, id, timeLimit = pcall(C_ChallengeMode.GetMapUIInfo, mapId)
        if ok then
            local tl = tonumber(timeLimit)
            if tl and tl > 0 then
                return tl
            end
        end
    end

    if type(C_ChallengeMode.GetMapInfo) == "function" then
        local ok, info = pcall(C_ChallengeMode.GetMapInfo, mapId)
        if ok and type(info) == "table" then
            local tl = tonumber(info.timeLimitSeconds or info.timeLimit)
            if tl and tl > 0 then
                return tl
            end
        end
    end

    return nil
end

---@param mapId number|nil
---@param level number|nil
---@param durationSec number|nil
---@return number|nil runScore
---@return table|nil matchedRun
function ScoreCalculator.TryGetBlizzardRunScore(mapId, level, durationSec)
    mapId = tonumber(mapId)
    level = tonumber(level)
    durationSec = tonumber(durationSec)

    if not mapId or mapId <= 0 or not C_MythicPlus or type(C_MythicPlus.GetRunHistory) ~= "function" then
        return nil, nil
    end

    local history
    do
        local ok, h = pcall(C_MythicPlus.GetRunHistory)
        if ok and type(h) == "table" then
            history = h
        else
            local tries = {
                { true,  true },
                { true,  false },
                { false, false },
            }
            for _, args in ipairs(tries) do
                ok, h = pcall(C_MythicPlus.GetRunHistory, unpackFn(args))
                if ok and type(h) == "table" then
                    history = h
                    break
                end
            end
        end
    end

    if type(history) ~= "table" then
        return nil, nil
    end

    local bestRun
    local bestScore
    local bestDiff

    for _, run in ipairs(history) do
        if type(run) == "table" then
            local runMapId = tonumber(run.mapChallengeModeID) or tonumber(run.mapChallengeModeId)
                or tonumber(run.challengeModeID) or tonumber(run.challengeModeId)
                or tonumber(run.mapID) or tonumber(run.mapId)
            local runLevel = tonumber(run.level) or tonumber(run.keystoneLevel) or tonumber(run.mythicLevel)

            if runMapId == mapId and (not level or not runLevel or runLevel == level) then
                local score = tonumber(run.mapScore) or tonumber(run.runScore) or tonumber(run.score)
                    or tonumber(run.mythicRating)
                if score then
                    local diff = 0
                    if durationSec then
                        local runDur = tonumber(run.durationSec) or tonumber(run.duration) or tonumber(run.time)
                        if runDur then
                            diff = math.abs(runDur - durationSec)
                        end
                    end

                    if not bestDiff or diff < bestDiff then
                        bestDiff = diff
                        bestScore = score
                        bestRun = run
                    end
                end
            end
        end
    end

    return bestScore, bestRun
end

--- Calculate the Mythic+ score for a completed keystone run.
--
-- Parameters:
-- - `keystoneLevel` (integer): The numeric level of the completed keystone (keystones start at 2).
-- - `completedInTime` (number|nil): The time in seconds the dungeon was completed in. If `nil`, no time bonus is applied.
-- - `parTime` (number|nil): The par time in seconds used to compute time bonuses. If `nil` or <= 0, time bonuses are skipped.
--
-- Returns:
-- - (number) The total Mythic+ score for the run (base + affix bonuses + time bonus).
--
-- Notes:
-- - Uses configuration values from `Data.MythicPlusScoreConfig` and affix counts from `Data.GetAffixCountForKeystoneLevel`.
-- - Does NOT take into account the Fortified/Tyrannical split.
---@param keystoneLevel integer
---@param completedInTime number|nil
---@param parTime number|nil
---@return number
function ScoreCalculator.Calculate(keystoneLevel, completedInTime, parTime)
    local data = GetData()
    if not data or type(data.MythicPlusScoreConfig) ~= "table" or type(data.GetAffixCountForKeystoneLevel) ~= "function" then
        return 0
    end

    keystoneLevel = tonumber(keystoneLevel) or 0
    completedInTime = tonumber(completedInTime)
    parTime = tonumber(parTime)

    if keystoneLevel < 2 then
        return 0
    end

    -- determine score of keystone based on level alone
    local baseScore = data.MythicPlusScoreConfig.BASE_SCORE +
        ((keystoneLevel - 2) * data.MythicPlusScoreConfig.SCORE_PER_LEVEL)

    -- add in bonuses for affixes
    local affixCount = data.GetAffixCountForKeystoneLevel(keystoneLevel)
    if affixCount then
        baseScore = baseScore + (affixCount * data.MythicPlusScoreConfig.AFFIX_BONUS_SCORE)
    end

    -- add in time bonus
    local timeBonus = 0
    if completedInTime and parTime and parTime > 0 then
        local timeRatio = completedInTime / parTime
        if timeRatio < 0.6 then
            timeBonus = data.MythicPlusScoreConfig.TIME_BONUS_MAX
        elseif timeRatio < 1.0 then
            -- Linear from 0%..40% faster => 0..max (e.g. 20% faster = 7.5)
            timeBonus = ((1.0 - timeRatio) / data.MythicPlusScoreConfig.TIME_BONUS_THRESHOLD) *
                data.MythicPlusScoreConfig.TIME_BONUS_MAX
        end
    end

    local totalScore = baseScore + timeBonus
    return RoundTo(totalScore, 1)
end

---@param mapId number|nil
---@param keystoneLevel integer
---@param completedInTime number|nil seconds
---@return number score
---@return table details
function ScoreCalculator.CalculateForRun(mapId, keystoneLevel, completedInTime)
    local data = GetData()
    if not data or type(data.MythicPlusScoreConfig) ~= "table" or type(data.GetAffixCountForKeystoneLevel) ~= "function" then
        return 0, {}
    end

    local parTime = ScoreCalculator.GetParTimeSeconds(mapId)
    local score = ScoreCalculator.Calculate(keystoneLevel, completedInTime, parTime)

    local baseScore = data.MythicPlusScoreConfig.BASE_SCORE +
        ((tonumber(keystoneLevel) - 2) * data.MythicPlusScoreConfig.SCORE_PER_LEVEL)
    local affixCount = data.GetAffixCountForKeystoneLevel(keystoneLevel)
    local affixBonus = (affixCount and (affixCount * data.MythicPlusScoreConfig.AFFIX_BONUS_SCORE)) or 0

    local timeBonus = 0
    local timeRatio
    if completedInTime and parTime and parTime > 0 then
        timeRatio = completedInTime / parTime
        if timeRatio < 0.6 then
            timeBonus = data.MythicPlusScoreConfig.TIME_BONUS_MAX
        elseif timeRatio < 1.0 then
            timeBonus = ((1.0 - timeRatio) / data.MythicPlusScoreConfig.TIME_BONUS_THRESHOLD) *
                data.MythicPlusScoreConfig.TIME_BONUS_MAX
        end
    end

    return score, {
        mapId = tonumber(mapId),
        level = tonumber(keystoneLevel),
        timeSec = tonumber(completedInTime),
        parTimeSec = tonumber(parTime),
        timeRatio = RoundTo(timeRatio, 4),
        baseScore = RoundTo(baseScore, 1),
        affixCount = affixCount,
        affixBonus = RoundTo(affixBonus, 1),
        timeBonus = RoundTo(timeBonus, 1),
        total = score,
    }
end
