-- TwichUI: Quality of Life, Release in battlegrounds
-- Releases your spirit for you after you die in a battleground. Off until turned on.
--
-- What the game gives us (WoW: Forever UI source and API documentation):
--   PLAYER_DEAD, PLAYER_ALIVE and PLAYER_UNGHOST say when you die and when you are back;
--   IsInInstance() gives the kind of place: "pvp" is a battleground, "arena" an arena, "none" the
--   open world, "party" and "raid" the PvE instances. RepopMe() releases.
--   C_DeathInfo.GetSelfResurrectOptions() lists a soulstone or similar; ResurrectGetOfferer()
--   names someone whose resurrection is on offer; GetReleaseTimeRemaining() is > 0 (or -1, no
--   timer) while you may still release; IsFalling() / IsOutOfBounds() are what the game's own
--   Release button looks at.
--
-- Scope: battlegrounds only ("pvp"). Arenas (where releasing may make you a spectator), open-world
-- PvP and everything else are not handled: nothing in the game's UI says which open-world zones
-- are PvP battlegrounds, and being PvP flagged proves nothing. Never in a dungeon, raid or
-- scenario, and never under the Hardcore ruleset.
--
-- It does not release when, at the moment of release:
--   you have a self-resurrection on offer (a soulstone or similar);
--   someone's resurrection is on offer to you (also covers Accept resurrection: it only ever
--     accepts, so the two cannot contradict each other);
--   the game says you can't release (no time left, or you are still falling);
--   you are holding Shift (a way to keep your body: hold it as the wait ends).
-- The wait (Wait before releasing, 2 seconds by default) gives an offered resurrection time to
-- arrive: a RESURRECT_REQUEST during it cancels the release, and so does getting up or leaving.
-- One release is planned per death (a generation number, since a timer can't be cancelled). If it
-- doesn't happen, nothing retries: the game's own Release button is still there.

local R = TwichUI
local Q = R.QoL
local Rel = {}
R.QoLRelease = Rel

local generation = 0

local function SelfResurrectOnOffer()
    local options = C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions and C_DeathInfo.GetSelfResurrectOptions()
    return options ~= nil and #options > 0
end

local function OfferPending()
    local offerer = ResurrectGetOfferer()
    return offerer ~= nil and offerer ~= ""
end

-- The context rule, on its own: is this a place where releasing for you is in scope?
function Rel.InScope()
    local inInstance, kind = IsInInstance()
    return inInstance and kind == "pvp" or false
end

-- Everything that must hold, now, for a release. Shift is looked at only at the end.
function Rel.CanRelease()
    if Q.Hardcore() or not UnitIsDead("player") or UnitIsGhost("player") then return false end
    if not Rel.InScope() then return false end
    if SelfResurrectOnOffer() or OfferPending() then return false end
    local remaining = GetReleaseTimeRemaining()
    if not (remaining > 0 or remaining == -1) then return false end
    if IsFalling() and not IsOutOfBounds() then return false end
    return true
end

local function Release(plan)
    if plan.generation ~= generation then return end
    generation = generation + 1     -- this death is dealt with
    if IsShiftKeyDown() or not Rel.CanRelease() then return end
    RepopMe()
end

local function OnDead()
    generation = generation + 1
    if not Rel.CanRelease() then return end
    local plan = { generation = generation }
    local wait = Q.Get("releaseWait")
    if wait > 0 then
        C_Timer.After(wait, function() Release(plan) end)
    else
        Release(plan)
    end
end

-- A resurrection offered, getting up, or changing place ends the plan.
local function OnCancel() generation = generation + 1 end

function Rel.Stop() generation = generation + 1 end

Rel.feature = Q.Add({
    key = "qolReleasePvP",
    Events = function()
        return { PLAYER_DEAD = OnDead, PLAYER_ALIVE = OnCancel, PLAYER_UNGHOST = OnCancel,
            RESURRECT_REQUEST = OnCancel, PLAYER_ENTERING_WORLD = OnCancel }
    end,
    Stop = Rel.Stop,
})
Rel.OnDead = OnDead
