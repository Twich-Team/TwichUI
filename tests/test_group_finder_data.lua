dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
local SECRET = setmetatable({}, { __eq = function() error("secret compared") end, __tostring = function() error("secret formatted") end })
c.issecretvalue = function(value) return rawequal(value, SECRET) end
local activities = {
    [10] = { fullName = "Blackrock Depths", maxNumPlayers = 5, useDungeonRoleExpectations = true, minLevelSuggestion = 52, maxLevelSuggestion = 60 },
    [11] = { fullName = "Scholomance", maxNumPlayers = 5, useDungeonRoleExpectations = true, minLevelSuggestion = 58, maxLevelSuggestion = 60 },
    [12] = { fullName = "New Forever dungeon", maxNumPlayers = 5, useDungeonRoleExpectations = true },
    [20] = { fullName = "Raid", maxNumPlayers = 40, useDungeonRoleExpectations = false },
}
local results = {
    [1] = { numMembers = 4, leaderName = "Stoneward", activityIDs = { 10, 11 }, partyGUID = "Party-1", age = 18 },
    [2] = { numMembers = 1, leaderName = "Dawnmend", activityIDs = { 10, 11 }, partyGUID = "Party-2", age = 20 },
}
local players = {
    [1] = { name = "Stoneward", level = 60, areaName = "Searing Gorge", classFilename = "WARRIOR", className = "Warrior", assignedRole = "TANK", isLeader = true },
    [2] = { name = "Dawnmend", level = 60, areaName = "Searing Gorge", classFilename = "PRIEST", className = "Priest", assignedRole = "HEALER", isLeader = true, lfgRoles = { healer = true, dps = true }, specName = "Shadow" },
}
c.C_LFGList = {
    GetAvailableCategories = function() return { 2, SECRET } end,
    GetAvailableActivities = function() return { 10, 11, 12, 20 } end,
    GetActivityInfoTable = function(id) return activities[id] end,
    GetSearchResults = function() return 2, { 1, 2 } end,
    GetSearchResultInfo = function(id) return results[id] end,
    GetSearchResultLeaderInfo = function(id) return players[id] end,
    GetSearchResultPlayerInfo = function(id, index) return index == 1 and players[id] or nil end,
    GetSearchResultMemberCounts = function() return { TANK_REMAINING = 0, HEALER_REMAINING = 1, DAMAGER_REMAINING = 0 } end,
}
local function Load(file) local f = assert(loadfile(ROOT .. file)); setfenv(f, c); f("!!!TwichUI", {}) end
Load("groupfinder/Data.lua")
local D = c.TwichUI.GroupFinder.Data
local list = D.Activities()
assert(#list == 3 and list[3].name == "Scholomance", "live five-player activities include new dungeons, omit raids")
assert(list[1].minLevel == 52 and list[1].maxLevel == 60, "suggestions kept separate")
assert(list[1].icon:find("blackrock%-depths$") and list[3].icon:find("scholomance$"), "featured dungeons use packaged original art")
assert(D.ActivityIcon({fullName="Un nouveau donjon",mapID=289}):find("scholomance$"), "verified map mapping survives localization")
assert(D.ActivityIcon({fullName="New Forever dungeon"}):find("reminder%-dungeon%-entrance$"), "new and unmatched dungeons have packaged art")
local group, solo = D.Read(1), D.Read(2)
assert(group and not group.solo and group.openings.HEALER == 1 and group.openings.TANK == 0)
assert(group.level == 60 and group.zone == "Searing Gorge" and #group.activities == 2)
assert(type(group.readAt) == "number", "listing ages retain a public capture timestamp")
results[1].generalPlaystyle,results[1].playstyle = 2,4
assert(D.Read(1).playstyle == 2, "general playstyle matches native browse labels")
players[1].name,results[1].leaderName = "Stone|ward","Stone|ward"
assert(D.Read(1).leader == "Stone|ward", "normalized data stays raw for one UI escape pass")
players[1].name,results[1].leaderName = "Stoneward","Stoneward"
assert(solo.solo and solo.roles.HEALER and solo.roles.DAMAGER and not solo.roles.TANK)
assert(solo.style == "UNKNOWN", "spec spelling alone does not establish Forever damage style")
assert(#D.Results() == 2)
local original = group.identity
results[1].partyGUID = "Party-recycled"
assert(D.Read(1).identity ~= original, "recycled ID has a different contact identity")
results[1].partyGUID = SECRET
assert(D.Read(1).identity == nil, "restricted GUID cannot authorize contact")
results[1].partyGUID, results[1].hasSelf, results[1].isDelisted = "Party-1", false, false
assert(D.Read(1).actionable, "known live public listing can be contacted")
results[1].hasSelf = SECRET
assert(not D.Read(1).actionable, "unknown self flag is never actionable")
results[1].hasSelf,results[1].isDelisted = false, SECRET
assert(not D.Read(1).actionable, "unknown delisted flag is never actionable")
results[1].isDelisted = true
assert(D.Read(1) == nil, "delisted results are not actionable")
results[1].isDelisted = false
players[2].level, players[2].areaName, players[2].classFilename, players[2].lfgRoles = SECRET, SECRET, SECRET, SECRET
solo = D.Read(2)
assert(solo and solo.level == nil and solo.zone == nil and solo.class == nil)
assert(not solo.roles.HEALER and solo.style == "UNKNOWN", "nested restricted fields are not used")
results[2].activityIDs = SECRET
assert(D.Read(2) == nil)
assert(D.Read(SECRET) == nil and D.Read("2") == nil)
c.C_LFGList.GetSearchResultInfo = function() error("restricted") end
assert(D.Read(1) == nil and #D.Results() == 0)

local roles = { player = "TANK", party1 = "DAMAGER", party2 = "DAMAGER", party3 = "DAMAGER" }
c.IsInGroup = function() return true end
c.IsInRaid = function() return false end
c.GetNumGroupMembers = function() return 4 end
c.UnitGroupRolesAssigned = function(unit) return roles[unit] end
c.UnitIsGroupLeader = function() return true end
c.UnitIsGroupAssistant = function() return false end
local party = D.Party()
assert(party.known and party.canInvite and party.count == 4 and party.openings.HEALER == 1)
roles.party1 = "NONE"
assert(not D.Party().known and D.Party().reason, "unknown role explains unavailable party refinement")
c.UnitIsGroupLeader = function() return false end
assert(not D.Party().canInvite, "party member cannot invite")
c.IsInGroup = function() return false end
assert(D.Party().canInvite, "solo player can invite")
c.InCombatLockdown = function() return true end
assert(not D.Party().canInvite)
c.InCombatLockdown = function() return SECRET end
assert(not D.Party().canInvite, "unknown combat state never enables an action")
c.IsInGroup = function() return SECRET end
assert(not D.Party().known and D.Party().count == nil and D.Party().reason, "unknown group state never invents solo openings")
c.IsInGroup = function() return false end
c.IsInRaid = function() return SECRET end
assert(not D.Party().known and D.Party().count == nil, "unknown raid state never invents party composition")
print("test_group_finder_data: OK")
