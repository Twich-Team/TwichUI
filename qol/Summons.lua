-- TwichUI: Quality of Life, Accept summons
-- Accepts a summon (a Warlock's Ritual of Summoning, a meeting stone) after a short wait, from the
-- people the player chose. Off until turned on.
--
-- What the game gives us (WoW: Forever UI source and API documentation):
--   CONFIRM_SUMMON(summonReason, skippingStartExperience) shows the summon pop-up.
--   C_SummonInfo.GetSummonConfirmSummoner / GetSummonConfirmAreaName / GetSummonConfirmTimeLeft
--   say who, where and how long is left; C_SummonInfo.ConfirmSummon accepts and CANCEL_SUMMON
--   fires when the summon is withdrawn. The game's own Accept button is disabled in combat or
--   when PlayerCanTeleport() is false; we respect the same two limits.
-- Only an ordinary summon (reason Spell) is handled. A scenario summon and one that skips the
-- starting experience have their own pop-ups and consequences, so they are always left to the player.
--
-- One accept is planned per summon. A later summon, a withdrawn one or turning the feature off
-- cancels the plan (a generation number, since a timer can't be cancelled). When the wait ends the
-- summon must still be the same one (same summoner and place, time left, no combat) or nothing
-- happens. There is no retry: if it can't be accepted then, the game's pop-up is still there.

local R = TwichUI
local Q = R.QoL
local S = {}
R.QoLSummons = S

local generation = 0

local function InCombat() return UnitAffectingCombat("player") end

local function Accept(plan)
    if plan.generation ~= generation then return end
    generation = generation + 1     -- this summon is dealt with
    if InCombat() or not PlayerCanTeleport() then return end
    if (C_SummonInfo.GetSummonConfirmTimeLeft() or 0) <= 0 then return end
    if C_SummonInfo.GetSummonConfirmSummoner() ~= plan.summoner
        or C_SummonInfo.GetSummonConfirmAreaName() ~= plan.area then return end
    C_SummonInfo.ConfirmSummon()
    StaticPopup_Hide("CONFIRM_SUMMON")
end

local function OnSummon(reason, skippingStartExperience)
    generation = generation + 1
    local spell = Enum.SummonReason and Enum.SummonReason.Spell or 0
    if reason ~= spell or skippingStartExperience then return end
    if InCombat() or not PlayerCanTeleport() then return end
    local summoner = C_SummonInfo.GetSummonConfirmSummoner()
    if not Q.Allowed(summoner, Q.Get("summonsFrom")) then return end
    local plan = { generation = generation, summoner = summoner, area = C_SummonInfo.GetSummonConfirmAreaName() }
    local wait = Q.Get("summonsWait")
    if wait > 0 then
        C_Timer.After(wait, function() Accept(plan) end)
    else
        Accept(plan)
    end
end

local function OnCancel() generation = generation + 1 end

function S.Stop() generation = generation + 1 end

S.feature = Q.Add({
    key = "qolSummons",
    guild = true,
    Events = function() return { CONFIRM_SUMMON = OnSummon, CANCEL_SUMMON = OnCancel } end,
    Stop = S.Stop,
})
S.OnSummon = OnSummon
