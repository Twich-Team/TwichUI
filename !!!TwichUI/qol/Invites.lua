-- TwichUI: Quality of Life, Accept group invitations
-- Joins the group when a friend or guild member invites you (as the player chose). Off until turned on.
--
-- What the game gives us (WoW: Forever UI source and API documentation):
--   PARTY_INVITE_REQUEST(name, isTank, isHealer, isDamage, isNativeRealm, allowMultipleRoles,
--   inviterGUID, questSessionActive) shows the "invites you to a group" pop-up (StaticPopup
--   PARTY_INVITE). AcceptGroup() joins; DeclineGroup() refuses. PARTY_INVITE_CANCEL fires when the
--   invitation is withdrawn. WillAcceptInviteRemoveQueues() is true when joining would drop a queue.
--   The pop-up's OnHide declines the invitation unless the dialog's inviteAccepted field is set, so
--   after accepting we set it before hiding the pop-up (as the pop-up's own Accept button does).
-- Left to the player, always, with the pop-up untouched:
--   * an invitation that carries a role (isTank, isHealer or isDamage): it comes from the group finder
--     and has its own role pop-up;
--   * a quest session (party sync) invitation: it has its own confirmation;
--   * any invitation while you are already in a group: accepting would take you out of it;
--   * any invitation whose acceptance would remove you from a queue;
--   * an inviter whose name the game doesn't give, or who isn't covered by the player's choice.
--
-- Our listener and the game's own both run on the event. If ours ran first there would be no pop-up
-- yet to hide, and the game would then show one for an invitation already answered. So the accept
-- waits one frame. One accept is planned per invitation; a later invitation, a withdrawn one or
-- turning the feature off cancels the plan (a generation number, since a timer can't be cancelled).
-- There is no retry: if it can't be accepted then, the pop-up is still the player's.

local R = TwichUI
local Q = R.QoL
local I = {}
R.QoLInvites = I

local generation = 0

local function InGroup()
    if IsInGroup() then return true end
    return LE_PARTY_CATEGORY_INSTANCE ~= nil and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or false
end

local function WouldLeaveQueue()
    return WillAcceptInviteRemoveQueues ~= nil and WillAcceptInviteRemoveQueues() and true or false
end

local function Accept(plan)
    if plan.generation ~= generation then return end
    generation = generation + 1      -- this invitation is dealt with
    if InGroup() or WouldLeaveQueue() then return end
    AcceptGroup()
    local popup = StaticPopup_FindVisible and StaticPopup_FindVisible("PARTY_INVITE")
    if popup then popup.inviteAccepted = 1 end
    StaticPopup_Hide("PARTY_INVITE")
end

local function OnInvite(name, isTank, isHealer, isDamage, _, _, _, questSessionActive)
    generation = generation + 1
    if isTank or isHealer or isDamage or questSessionActive then return end
    if InGroup() or WouldLeaveQueue() then return end
    if not Q.Allowed(name, Q.Get("invitesFrom")) then return end
    local plan = { generation = generation }
    C_Timer.After(0, function() Accept(plan) end)
end

local function OnCancel() generation = generation + 1 end

function I.Stop() generation = generation + 1 end

I.feature = Q.Add({
    key = "qolInvites",
    guild = true,
    Events = function() return { PARTY_INVITE_REQUEST = OnInvite, PARTY_INVITE_CANCEL = OnCancel } end,
    Stop = I.Stop,
})
I.OnInvite = OnInvite
