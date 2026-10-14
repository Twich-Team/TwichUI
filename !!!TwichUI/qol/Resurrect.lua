-- TwichUI: Quality of Life, Accept resurrection
-- Accepts a resurrection another player offers. Off until turned on.
--
-- What the game gives us (WoW: Forever UI source and API documentation):
--   RESURRECT_REQUEST(inviter) says an offer has been made. ResurrectGetOfferer() names who
--   offered while it stands, ResurrectHasSickness() / ResurrectHasTimer() say what it carries,
--   GetCorpseRecoveryDelay() is the wait the game's own pop-up imposes before its Accept button
--   works, and AcceptResurrect() accepts.
-- Only RESURRECT_REQUEST offers are handled. Self-resurrection (soulstone, Ankh), spirit healers
-- and corpse recovery are separate and left alone, and no other pop-up is touched.
--
-- Left to the player (the game's pop-up stays as it is):
--   every offer under the Hardcore ruleset (the game's own UI never shows one there);
--   an offer that carries resurrection sickness (the player may want to weigh it);
--   a combat resurrection unless Also accept combat resurrections is on. The game has no "this is
--     a combat resurrection" flag, so an offer counts as one when the person offering is in your
--     group and in combat. Someone outside your group can't be seen in combat or out of it, so
--     their offer counts as an ordinary one;
--   an offer made while the game's wait (GetCorpseRecoveryDelay) is running: it is accepted once
--     that wait is over, if the same offer still stands, and not otherwise. That one timer is
--     planned from the time the game reports; nothing polls and nothing retries.
-- A newer offer, turning the feature off or coming back to life cancels the plan.

local R = TwichUI
local Q = R.QoL
local Rez = {}
R.QoLResurrect = Rez

local generation = 0

local function Same(a, b)
    a, b = Q.Normal(a), Q.Normal(b)
    return a ~= nil and a == b
end

-- Is the offerer a group member we can see in combat?
local function OffererInCombat(offerer)
    local unit = Q.GroupUnit(offerer)
    return unit ~= nil and UnitAffectingCombat(unit) and true or false
end

local function Accept(plan)
    if plan.generation ~= generation then return end
    generation = generation + 1     -- this offer is dealt with
    if plan.waited then
        -- after the game's wait: still the same offer, and the wait really is over
        if not Same(ResurrectGetOfferer(), plan.offerer) or (GetCorpseRecoveryDelay() or 0) > 0 then return end
    end
    AcceptResurrect()
end

local function OnRequest(offerer)
    generation = generation + 1
    if Q.Hardcore() or Q.Normal(offerer) == nil then return end
    if ResurrectHasSickness() then return end
    if not R:Enabled("qolResurrectCombat") and OffererInCombat(offerer) then return end
    local plan = { generation = generation, offerer = offerer }
    local wait = GetCorpseRecoveryDelay() or 0
    if wait > 0 then
        plan.waited = true
        C_Timer.After(wait + 1, function() Accept(plan) end)
    else
        Accept(plan)
    end
end

local function OnAlive() generation = generation + 1 end

function Rez.Stop() generation = generation + 1 end

Rez.feature = Q.Add({
    key = "qolResurrect",
    Events = function() return { RESURRECT_REQUEST = OnRequest, PLAYER_ALIVE = OnAlive, PLAYER_UNGHOST = OnAlive } end,
    Stop = Rez.Stop,
})
Rez.OnRequest = OnRequest
