-- TwichUI: Quality of Life, Block duels
-- Declines duel requests, except from the people the player chose. Off until turned on.
--
-- What the game gives us (WoW: Forever UI source and API documentation):
--   DUEL_REQUESTED(playerName) shows the "challenges you to a duel" pop-up; its Decline button
--   calls CancelDuel(), which is what we call.
--   DUEL_TO_THE_DEATH_REQUESTED(playerName) is a separate event with its own pop-ups (the lethal
--   duel Forever adds; accepting it means typing a confirmation). It is left alone unless
--   Also decline duels to the death is on.
--   The pet battle duel events (PET_BATTLE_PVP_DUEL_REQUESTED) are not routed by the Forever UI,
--   so they are not handled and not mentioned in the settings.
-- Only the pop-ups of the duel kinds we decline are hidden; no other pop-up is touched. If the
-- requester's name is missing the exceptions can't be applied, so the request is declined.
--
-- Our listener and the game's own both run on the event. If ours runs first, there is no pop-up
-- yet to hide; declining still ends the request, and the game closes the pop-up itself when the
-- duel is over (DUEL_FINISHED).

local R = TwichUI
local Q = R.QoL
local D = {}
R.QoLDuels = D

local function Decline(requester, popups)
    if Q.Allowed(requester, Q.Get("duelsFrom")) then return end
    CancelDuel()
    for _, which in ipairs(popups) do StaticPopup_Hide(which) end
end

local ORDINARY = { "DUEL_REQUESTED" }
local LETHAL = { "DUEL_TO_THE_DEATH_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED_CONFIRM" }

local function OnDuel(requester) Decline(requester, ORDINARY) end
local function OnLethalDuel(requester) Decline(requester, LETHAL) end

D.feature = Q.Add({
    key = "qolDuels",
    guild = true,
    Events = function()
        local events = { DUEL_REQUESTED = OnDuel }
        if R:Enabled("qolDuelsToDeath") then events.DUEL_TO_THE_DEATH_REQUESTED = OnLethalDuel end
        return events
    end,
})
D.OnDuel, D.OnLethalDuel = OnDuel, OnLethalDuel
