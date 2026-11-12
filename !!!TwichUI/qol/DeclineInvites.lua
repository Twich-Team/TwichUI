-- TwichUI: Quality of Life, Decline group invitations
-- Declines a group invitation, except from the people the player chose. Off until turned on.
--
-- What the game gives us (WoW: Forever UI source and API documentation):
--   PARTY_INVITE_REQUEST(name, isTank, isHealer, isDamage, isNativeRealm, isCrossShard,
--   allowMultipleRoles, inviterGUID, questSessionActive) shows the "invites you to a group" pop-up (StaticPopup
--   PARTY_INVITE). DeclineGroup() refuses it, which is what the pop-up's own Decline button calls.
--   PARTY_INVITE_CANCEL fires when the invitation is withdrawn.
-- Left to the player, always, with the pop-up untouched:
--   * an invitation that carries a role (isTank, isHealer or isDamage): it comes from the group
--     finder, usually in answer to the player's own application, and has its own role pop-up;
--   * a quest session (party sync) invitation: it has its own pop-up;
--   * an inviter the Accept group invitations feature is set to join, when that feature is on.
-- If the inviter's name is missing the exceptions can't be applied, so the invitation is declined.
--
-- Our listener and the game's own both run on the event. If ours ran first there would be no pop-up
-- yet to hide, and the game would then show one for an invitation already answered. So the decline
-- waits one frame. One decline is planned per invitation; a later invitation, a withdrawn one or
-- turning the feature off cancels the plan (a generation number, since a timer can't be cancelled).

local R = TwichUI
local Q = R.QoL
local N = {}
R.QoLDeclineInvites = N

local generation = 0

local function Decline(plan)
    if plan.generation ~= generation then return end
    generation = generation + 1      -- this invitation is dealt with
    DeclineGroup()
    StaticPopup_Hide("PARTY_INVITE")
end

local function OnInvite(name, isTank, isHealer, isDamage, _, _, _, _, questSessionActive)
    generation = generation + 1
    if isTank or isHealer or isDamage or questSessionActive then return end
    if Q.Allowed(name, Q.Get("declineInvitesFrom")) then return end
    -- the accepting feature is joining this person: not also declining them
    if R:Enabled("qolInvites") and Q.Allowed(name, Q.Get("invitesFrom")) then return end
    local plan = { generation = generation }
    C_Timer.After(0, function() Decline(plan) end)
end

local function OnCancel() generation = generation + 1 end

function N.Stop() generation = generation + 1 end

N.feature = Q.Add({
    key = "qolDeclineInvites",
    guild = true,
    Events = function() return { PARTY_INVITE_REQUEST = OnInvite, PARTY_INVITE_CANCEL = OnCancel } end,
    Stop = N.Stop,
})
N.OnInvite = OnInvite
