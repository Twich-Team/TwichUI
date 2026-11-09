-- TwichUI: Quality of Life, Invite nearby players
-- A key binding (Key Bindings > TwichUI, none bound until you choose a key) that invites the friendly players
-- standing close to you to your group, so they get quest credit too. Each press is the player's own request:
-- nothing here runs on an event, a timer or a hook, and nothing is saved.
--
-- What the game gives us (WoW: Forever UI source and API documentation, 1.60.1):
--   * There is no list of the players around you. The nearest thing is nameplate units: "nameplate1" to
--     "nameplate40" (walked with UnitExists, as EllesmereUI does on this client; the namePlateUnitToken field
--     read off a nameplate frame can be a secret value here). Other players have one only while friendly player
--     nameplates are shown (the nameplateShowFriendlyPlayers setting), so with those off nobody can be found;
--     the press says so.
--   * CheckInteractDistance(unit, 4) is the game's follow distance, about 28 yards: "close" here. During combat
--     the game blocks it for a friendly unit and names the addon, which no pcall catches (the Manners addon's
--     notes for this client), so a press in combat checks nobody and says why.
--   * C_PartyInfo.InviteUnit(name) invites by name (SecretArguments AllowedWhenUntainted: a secret name can't be
--     passed from addon code, so a name we can't read is skipped). C_PartyInfo.CanInvite() says whether you may.
--     Inviting past a full party asks to convert it to a raid, so a press invites no more than the open seats.
--   * Whether an invitation arrived, was declined or failed (the player is already in a group, say) is the
--     game's to tell you: it does, in chat. Nothing here claims more than that it was sent.
-- A name invited by a press is not invited again by another press within RECENT seconds, so pressing twice
-- doesn't send the same people a second invitation. That memory is for this session only and is pruned on
-- each press.

local R = TwichUI
local Q = R.QoL
local N = {}
R.QoLNearbyInvite = N

N.MAX_PLATES = 40
N.DISTANCE_INDEX = 4     -- CheckInteractDistance: follow, about 28 yards
N.RECENT = 60            -- seconds
local PARTY_SEATS = 4    -- others in a party (MAX_PARTY_MEMBERS)
local RAID_SEATS = 40    -- everyone in a raid (MAX_RAID_MEMBERS)

BINDING_HEADER_TWICHUI = BINDING_HEADER_TWICHUI or "TwichUI"
_G["BINDING_NAME_TWICHUI_INVITE_NEARBY"] = "Invite nearby players to your group"

local recent = {}   -- [lowercased name] = GetTime() of the press that invited them

local function Plain(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

local function Yes(value)
    value = Plain(value)
    return value == true or value == 1
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return value
end

-- How many more people this group can take without becoming a raid (or a bigger one), or nil and why not.
local function Seats()
    if not IsInGroup() then return PARTY_SEATS end
    if C_PartyInfo.CanInvite and not Yes(Call(C_PartyInfo.CanInvite)) then
        return nil, "Only the group leader (or a raid assistant) can invite."
    end
    if IsInRaid() then return RAID_SEATS - (GetNumGroupMembers() or 0) end
    local others = GetNumSubgroupMembers and GetNumSubgroupMembers() or ((GetNumGroupMembers() or 1) - 1)
    return PARTY_SEATS - (others or 0)
end

-- The name to invite, as "Name" or "Name-Realm", or nil when the game doesn't give one we can read.
local function InviteName(unit)
    local name, realm = UnitName(unit)
    name, realm = Plain(name), Plain(realm)
    if type(name) ~= "string" or name == "" then return nil end
    if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
    return name
end

local function InOurGroup(unit)
    return Yes(Call(UnitInParty, unit)) or Plain(Call(UnitInRaid, unit)) ~= nil
end

-- A friendly player close to you, not yet with you: their name, or nil.
local function Candidate(unit, me)
    if not Yes(UnitExists(unit)) or not Yes(UnitIsPlayer(unit)) then return nil end
    if Yes(Call(UnitIsUnit, unit, "player")) then return nil end
    if not Yes(UnitCanCooperate("player", unit)) or not Yes(UnitIsConnected(unit)) then return nil end
    if InOurGroup(unit) then return nil end
    if not Yes(Call(CheckInteractDistance, unit, N.DISTANCE_INDEX)) then return nil end
    local name = InviteName(unit)
    if not name or Q.Normal(name) == me then return nil end
    return name
end

-- The friendly players close to you, in the order of their nameplate units (not by distance); one entry per name.
function N.Nearby()
    local found, seen = {}, {}
    local me = Q.Normal((UnitName("player")))
    for i = 1, N.MAX_PLATES do
        local name = Candidate("nameplate" .. i, me)
        local key = name and name:lower()
        if key and not seen[key] then
            seen[key] = true
            found[#found + 1] = name
        end
    end
    return found
end

local function Prune(now)
    for key, at in pairs(recent) do
        if now - at >= N.RECENT then recent[key] = nil end
    end
end

local function FriendlyPlatesShown()
    if not GetCVarBool then return true end
    return GetCVarBool("nameplateShowFriendlyPlayers") and true or false
end

-- The key binding. Returns how many invitations were sent (for tests); says what happened in your chat frame.
function N.Invite()
    if not (C_PartyInfo and C_PartyInfo.InviteUnit) then
        R.Print("The game's party invitation isn't available.")
        return 0
    end
    if InCombatLockdown() then
        R.Print("The game doesn't let TwichUI check who is close during a fight. Press again once it's over.")
        return 0
    end
    local seats, why = Seats()
    if not seats then R.Print(why) return 0 end
    if seats <= 0 then R.Print("Your group is full.") return 0 end

    local now = GetTime()
    Prune(now)
    local invited, again, left = {}, 0, 0
    for _, name in ipairs(N.Nearby()) do
        local key = name:lower()
        if recent[key] then
            again = again + 1
        elseif #invited >= seats then
            left = left + 1
        elseif pcall(C_PartyInfo.InviteUnit, name) then
            recent[key] = now
            invited[#invited + 1] = name
        end
    end

    if #invited > 0 then
        R.Print("Invited %s.", table.concat(invited, ", "))
    elseif again == 0 and left == 0 then
        if FriendlyPlatesShown() then
            R.Print("No friendly players close enough to invite.")
        else
            R.Print("No one found: TwichUI finds nearby players by their nameplates. Turn on friendly player nameplates (Options > Nameplates) to use this.")
        end
    end
    if again > 0 then
        R.Print("%d close by %s invited less than a minute ago.", again, again == 1 and "was" or "were")
    end
    if left > 0 then
        R.Print("Your group has no more room: %d more close by %s not invited.", left, left == 1 and "was" or "were")
    end
    return #invited
end

-- For tests: forget who was invited recently.
function N.Forget() for key in pairs(recent) do recent[key] = nil end end
