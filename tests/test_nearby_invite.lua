dofile(TESTS .. "harness.lua")
-- Quality of Life: Invite nearby players (qol/NearbyInvite.lua).
-- The game is simulated: this checks who is picked, how many are invited and what is said, not the game's own
-- nameplates, distances or invitations, which have to be checked in the game.
local c = MakeClient("Rich", {"!!!TwichUI"})
for _, f in ipairs({ "qol/QoL.lua", "qol/NearbyInvite.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local N = R.QoLNearbyInvite
assert(N and N.Invite, "the key's function is there")

-- A tiny world: W.plates[i] = { name, realm, player, coop, online, grouped, close, secret }
local W, invited, said, clock
local SECRET = {}
local function Reset()
  W = { plates = {}, combat = false, group = 0, raid = false, canInvite = true, friendlyPlates = true, inviteFails = {} }
  invited, said, clock = {}, {}, 100
  N.Forget()
end
Reset()
local function Plate(unit) local i = tonumber(unit:match("^nameplate(%d+)$")); return i and W.plates[i] end
c.issecretvalue = function(v) return v == SECRET end
c.GetTime = function() return clock end
c.InCombatLockdown = function() return W.combat end
c.IsInGroup = function() return W.group > 0 end
c.IsInRaid = function() return W.raid end
c.GetNumGroupMembers = function() return W.group > 0 and W.group + 1 or 0 end
c.GetNumSubgroupMembers = function() return W.group end
c.UnitExists = function(unit) return Plate(unit) ~= nil end
c.UnitIsPlayer = function(unit) local p = Plate(unit) return p and p.player ~= false end
c.UnitIsUnit = function(a, b) local p = Plate(a) return b == "player" and p and p.self or false end
c.UnitCanCooperate = function(_, unit) local p = Plate(unit) return p and p.coop ~= false end
c.UnitIsConnected = function(unit) local p = Plate(unit) return p and p.online ~= false end
c.UnitInParty = function(unit) local p = Plate(unit) return p and p.grouped or false end
c.UnitInRaid = function() return nil end
c.CheckInteractDistance = function(unit, index)
  assert(index == 4, "the follow distance is asked")
  assert(not W.combat, "never asked in combat (the game blocks it for a friendly unit)")
  local p = Plate(unit) return p and p.close ~= false
end
c.UnitName = function(unit)
  if unit == "player" then return "Rich" end
  local p = Plate(unit)
  if p then if p.secret then return SECRET end return p.name, p.realm end
end
c.GetCVarBool = function(name) assert(name == "nameplateShowFriendlyPlayers") return W.friendlyPlates end
c.C_PartyInfo = {
  CanInvite = function() return W.canInvite end,
  InviteUnit = function(name) if W.inviteFails[name] then error("refused") end table.insert(invited, name) end,
}
c.print = function(s) table.insert(said, tostring(s)) end
local function Said(pattern) for _, s in ipairs(said) do if s:find(pattern) then return true end end return false end

-- The key binding is named for the game's Key Bindings list.
assert(c.BINDING_NAME_TWICHUI_INVITE_NEARBY and c.BINDING_HEADER_TWICHUI == "TwichUI", "the binding has a name and a header")

-- Picks the close, friendly, online players who aren't with you yet, and nobody else.
W.plates = {
  { name = "Ann" },
  { name = "Bo", close = false },            -- too far
  { name = "Cy", coop = false },             -- the other faction
  { name = "Di", player = false },           -- an NPC
  { name = "Eve", online = false },          -- disconnected
  { name = "Fay", grouped = true },          -- already in your group
  { name = "Rich", self = true },            -- you
  nil,                                       -- a gap in the plate numbers
  { name = "Gus", realm = "Other" },         -- another realm: invited with it
  { secret = true },                         -- a name the game won't let us read
  { name = "Ann" },                          -- the same player twice
}
W.plates[8] = nil
assert(N.Invite() == 2, "two invited")
assert(invited[1] == "Ann" and invited[2] == "Gus-Other" and #invited == 2, "Ann and Gus-Other only")
assert(Said("Invited Ann, Gus%-Other%."), "says who was invited")

-- A second press within a minute doesn't invite them again; after a minute it does.
said, invited = {}, {}
assert(N.Invite() == 0 and #invited == 0, "not again so soon")
assert(Said("2 close by were invited less than a minute ago"), "and says so")
assert(not Said("No friendly players"), "that isn't 'nobody'")
clock = clock + N.RECENT
said = {}
assert(N.Invite() == 2, "a minute later they can be invited again")

-- No more than the open seats: a party of 4 has room for 1, a full party for none.
Reset(); W.plates = { { name = "Ann" }, { name = "Bo" }, { name = "Cy" } }; W.group = 3
assert(N.Invite() == 1 and invited[1] == "Ann", "one seat, one invitation")
assert(Said("no more room: 2 more close by were not invited"), "the rest are counted")
Reset(); W.plates = { { name = "Ann" } }; W.group = 4
assert(N.Invite() == 0 and Said("Your group is full"), "a full party invites nobody (it would ask to become a raid)")
Reset(); W.plates = { { name = "Ann" }, { name = "Bo" } }; W.group = 38; W.raid = true
assert(N.Invite() == 1, "a raid of 39 has one seat")
Reset(); W.plates = { { name = "Ann" } }; W.group = 1; W.canInvite = false
assert(N.Invite() == 0 and Said("Only the group leader"), "not the leader: nothing sent")

-- In combat nothing is checked and nothing sent.
Reset(); W.plates = { { name = "Ann" } }; W.combat = true
assert(N.Invite() == 0 and #invited == 0 and Said("during a fight"), "combat: says why")

-- Nobody close: says so, and points at friendly nameplates when they are off.
Reset()
assert(N.Invite() == 0 and Said("No friendly players close enough"), "nobody close")
Reset(); W.friendlyPlates = false
assert(N.Invite() == 0 and Said("Turn on friendly player nameplates"), "nameplates off: says what to turn on")

-- An invitation the game refuses isn't counted or remembered.
Reset(); W.plates = { { name = "Ann" }, { name = "Bo" } }; W.inviteFails.Ann = true
assert(N.Invite() == 1 and invited[1] == "Bo", "Bo is invited, Ann's refusal is passed over")
W.inviteFails.Ann = nil; said, invited = {}, {}
assert(N.Invite() == 1 and invited[1] == "Ann", "a refused name may be tried at the next press")

-- No invitation API: says so.
Reset(); local api = c.C_PartyInfo; c.C_PartyInfo = {}
assert(N.Invite() == 0 and Said("isn't available")); c.C_PartyInfo = api

print("NEARBY INVITE TESTS PASSED")
