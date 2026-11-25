-- Real TwichUI Group Finder: synthetic public-value Forever APIs and game events.
-- No server query, whisper, invite, hardware provenance, taint or reload is tested.
local R, params = TwichUI, SIMLAB_PARAMS or {}
local GF = assert(R.GroupFinder, "Group Finder module loaded")
A_Admin.SetManualClock(GetTime())
Lab.Solo()
R:SetEnabled("guildLocations", false)
local pose = params.pose or "groups"
local activities = {
    [101] = { fullName = "Blackrock Depths", shortName = "Blackrock Depths", categoryID = 2,
        maxNumPlayers = 5, useDungeonRoleExpectations = true, minLevelSuggestion = 52, maxLevelSuggestion = 60, mapID = 1584 },
    [102] = { fullName = "Scholomance", shortName = "Scholomance", categoryID = 2,
        maxNumPlayers = 5, useDungeonRoleExpectations = true, minLevelSuggestion = 58, maxLevelSuggestion = 60, mapID = 2057 },
    [103] = { fullName = "The Forgotten Depths", shortName = "The Forgotten Depths", categoryID = 2,
        maxNumPlayers = 5, useDungeonRoleExpectations = true, minLevelSuggestion = 55, maxLevelSuggestion = 60, mapID = 0 },
}
local function Player(name, class, level, zone, role)
    local names = { WARRIOR = "Warrior", ROGUE = "Rogue", MAGE = "Mage", HUNTER = "Hunter", PRIEST = "Priest", DRUID = "Druid", SHAMAN = "Shaman" }
    return { name = name, level = level, areaName = zone, className = names[class], classFilename = class,
        assignedRole = role, lfgRoles = { tank = role == "TANK", healer = role == "HEALER", dps = role == "DAMAGER" }, isLeader = false }
end
local results, ids = {}, { 1,2,3,4,11,12,13,14 }
local function Listing(id, members, activityIDs, openings, age)
    members[1].isLeader = true
    results[id] = {
        info = { searchResultID = id, activityIDs = activityIDs, leaderName = members[1].name,
            name = "", comment = "", voiceChat = "", voiceMode = 0, numMembers = #members, hasSelf = false,
            isDelisted = false, age = age, partyGUID = "Party-Synthetic-" .. id, numBNetFriends = 0, numCharFriends = 0,
            numGuildMates = 0, playstyle = 0, generalPlaystyle = 0, newPlayerFriendly = false },
        members = members, counts = { TANK_REMAINING = openings[1], HEALER_REMAINING = openings[2], DAMAGER_REMAINING = openings[3] },
    }
end
Listing(1, { Player("Stoneward","WARRIOR",60,"Searing Gorge","TANK"), Player("Rookblade","ROGUE",60,"Searing Gorge","DAMAGER"),
    Player("Emberweft","MAGE",60,"Searing Gorge","DAMAGER"), Player("Flintshot","HUNTER",60,"Searing Gorge","DAMAGER") }, {101}, {0,1,0}, 18)
Listing(2, { Player("Ashfen","WARRIOR",60,"Western Plaguelands","TANK"), Player("Wildarrow","HUNTER",60,"Western Plaguelands","DAMAGER"),
    Player("Frostfern","MAGE",60,"Western Plaguelands","DAMAGER") }, {102}, {0,1,1}, 35)
Listing(3, { Player("Ironmark","WARRIOR",59,"Burning Steppes","TANK"), Player("Goldfang","ROGUE",59,"Burning Steppes","DAMAGER") }, {101}, {0,1,2}, 50)
Listing(4, { Player("Duskhollow","WARRIOR",60,"Western Plaguelands","TANK"), Player("Runewick","MAGE",60,"Western Plaguelands","DAMAGER"),
    Player("Oakshot","HUNTER",60,"Western Plaguelands","DAMAGER"), Player("Shadeleaf","ROGUE",60,"Western Plaguelands","DAMAGER") }, {102}, {0,1,0}, 68)
Listing(11, { Player("Dawnmend","PRIEST",60,"Searing Gorge","HEALER") }, {101,102}, {0,0,0}, 20)
Listing(12, { Player("Thornwell","DRUID",60,"Western Plaguelands","HEALER") }, {101,102}, {0,0,0}, 40)
Listing(13, { Player("Stormward","SHAMAN",59,"Burning Steppes","HEALER") }, {101}, {0,0,0}, 60)
Listing(14, { Player("Ashwillow","PRIEST",58,"Eastern Plaguelands","HEALER") }, {102}, {0,0,0}, 80)
local searches, invites, whispers = 0, 0, 0
local lastQuery
local api = C_LFGList or {}
C_LFGList = api
api.GetAvailableCategories = function() return {2} end
api.GetLfgCategoryInfo = function(id) if id == 2 then return {name="Dungeons"} end end
api.GetAvailableActivities = function(id) return id == 2 and {101,102,103} or {} end
api.GetAvailableActivityGroups = function() return {} end
api.GetActivityInfoTable = function(id) return activities[id] end
api.GetSearchResults = function() return #ids, ids end
api.GetFilteredSearchResults = api.GetSearchResults
api.GetSearchResultInfo = function(id) return results[id] and results[id].info end
api.GetSearchResultPlayerInfo = function(id,index) return results[id] and results[id].members[index] end
api.GetSearchResultLeaderInfo = function(id) return results[id] and results[id].members[1] end
api.GetSearchResultMemberCounts = function(id) return results[id] and results[id].counts end
api.GetActiveEntryInfo = function() return nil end
api.HasActiveEntryInfo = function() return false end
api.Search = function(category,filter,preferred,language,crossFaction,advanced,selected)
    searches = searches + 1
    lastQuery = {category=category,activities=selected}
end
C_LFGListRoles = { GetRoles = function() return {tank=false,healer=true,dps=false} end }
GetRealZoneText = function() return "Searing Gorge" end
GetZoneText = GetRealZoneText
GetSubZoneText = function() return "" end
GetMinimapZoneText = GetRealZoneText
IsInRaid = function() return false end
IsInGroup = function() return true end
GetNumGroupMembers = function() return 4 end
UnitIsGroupLeader = function(unit) return unit == "player" end
UnitIsGroupAssistant = function() return false end
UnitGroupRolesAssigned = function(unit) return unit == "player" and "TANK" or "DAMAGER" end
GetGroupMemberCounts = function() return { TANK=1,HEALER=0,DAMAGER=3,NONE=0 } end
local originalExists = UnitExists
UnitExists = function(unit) if unit == "player" or unit == "party1" or unit == "party2" or unit == "party3" then return true end; if unit == "party4" then return false end; return originalExists(unit) end
UnitLevel = function() return 60 end
InCombatLockdown = function() return false end
C_PartyInfo = C_PartyInfo or {}
C_PartyInfo.InviteUnit = function() invites = invites + 1 end
CanGroupWithAccount = function() return true end
ChatFrameUtil = ChatFrameUtil or {}
ChatFrameUtil.SendTell = function() whispers = whispers + 1 end
ChatFrame_SendTell = ChatFrameUtil.SendTell
local function Event(event,...)
    A_Admin.FireEvent(event,...)
    Lab.Settle(.1)
end
local function Complete()
    Event("LFG_LIST_SEARCH_RESULTS_RECEIVED")
end
local function RefreshClick()
    local frame = GF.Window.frame
    assert(frame and frame.refresh, "real Refresh button exposed")
    frame.refresh:Click()
end
Lab.Step("open and restricted-search boundary", function()
    GF.Open()
    Lab.Check("construct","shared window visible",true,GF.Window.IsShown())
    Lab.Check("state","open never launches search",0,searches)
    GF.ChangeFilter("activities",{[101]=true,[102]=true})
    GF.ChangeFilter("roles",{HEALER=true})
    GF.ChangeFilter("sort","newest")
    RefreshClick()
    Lab.Check("interact","Refresh starts one query",1,searches)
    RefreshClick()
    Lab.Check("state","duplicate query suppressed",1,searches)
    Lab.Check("state","live dungeon category",2,lastQuery and lastQuery.category)
    Complete()
    Lab.Check("state","successful search state","ready",GF.state)
    Lab.Check("state","four actual group fixtures",4,#GF.rows)
end)
Lab.Step("local filters and snapshot failure", function()
    GF.ChangeFilter("search","Stoneward")
    Lab.Check("interact","leader search immediate",1,#GF.rows)
    Lab.Check("state","local search issues no query",1,searches)
    GF.ChangeFilter("search","nobody matches this")
    Lab.Check("state","filtered empty list",0,#GF.rows)
    GF.ChangeFilter("search","")
    Lab.Check("state","cleared filter restores groups",4,#GF.rows)
    GF.Select(1)
    local identity = GF.selected and GF.selected.identity
    RefreshClick()
    Event("LFG_LIST_SEARCH_FAILED","Synthetic failure")
    Lab.Check("state","failure is visible","failed",GF.state)
    Lab.Check("state","last good rows survive",4,#GF.rows)
    Lab.Check("state","surviving selected listing retained",identity,GF.selected and GF.selected.identity)
    RefreshClick(); Complete()
    Lab.Check("state","manual refresh recovers","ready",GF.state)
end)
Lab.Step("recruit view and advertised roles", function()
    GF.SetMode("players")
    GF.ChangeFilter("activities",{[101]=true,[102]=true})
    GF.ChangeFilter("roles",{HEALER=true})
    GF.ChangeFilter("sort","newest")
    GF.ChangeFilter("minLevel",58)
    GF.ChangeFilter("maxLevel",60)
    Lab.Check("interact","four healer recruits",4,#GF.rows)
    GF.ChangeFilter("minLevel",60)
    Lab.Check("state","player minimum boundary",2,#GF.rows)
    GF.ChangeFilter("minLevel",58)
    GF.Select(11)
    Lab.Check("state","multi-dungeon recruit selected","Dawnmend",GF.selected and GF.selected.leader)
    Lab.Check("state","recruit has two dungeons",2,GF.selected and #GF.selected.activities)
    Lab.Check("state","no automatic whispers",0,whispers)
    Lab.Check("state","no automatic invites",0,invites)
end)
local function Popup()
    for _, child in ipairs({GF.Window.frame:GetChildren()}) do
        if child.items and child.content and child.close then return child end
    end
    error("shared filter popup constructed")
end
local function Type(box, text)
    box:SetText(text)
    local changed = box:GetScript("OnTextChanged")
    if changed then changed(box, true) end
end
Lab.Step("filter and preset controls", function()
    local frame = GF.Window.frame
    frame.activities:Click()
    Lab.Check("construct","dungeon menu visible",true,Popup():IsShown())
    Lab.Check("construct","discovered three dungeon choices",5,#Popup().items)
    Popup().close:Click()
    frame.more:Click()
    Lab.Check("construct","More filters visible",true,Popup():IsShown())
    Popup().items[5]:Click()
    Lab.Check("interact","priest class filter",2,#GF.rows)
    Popup().items[5]:Click()
    Lab.Check("state","class toggle restores recruits",4,#GF.rows)
    Popup().close:Click()
    frame.level:Click()
    Type(Popup().items[2].input,"60")
    Type(Popup().items[4].input,"60")
    Popup().items[5]:Click()
    Lab.Check("interact","custom minimum control",60,GF.filters.minLevel)
    Lab.Check("state","custom range filters rows",2,#GF.rows)
    frame.level:Click()
    Type(Popup().items[2].input,"58")
    Popup().items[5]:Click()
    Lab.Check("state","custom range restored",4,#GF.rows)
    frame.presets:Click()
    Type(Popup().items[2].input,"Healer fixture")
    Popup().items[3]:Click()
    Lab.Check("interact","preset save control",1,#GF.GetPresets())
    GF.ChangeFilter("roles",{DAMAGER=true})
    Lab.Check("state","different role hides healers",0,#GF.rows)
    Popup().items[4]:Click()
    Lab.Check("interact","preset load restores roles",true,GF.filters.roles.HEALER)
    Lab.Check("state","preset restores visible matches",4,#GF.rows)
    frame.presets:Click()
    Popup().items[5]:Click()
    Lab.Check("interact","preset remove control",0,#GF.GetPresets())
    Popup().close:Click()
    Lab.Check("state","local menus issue no searches",3,searches)
    GF.message = "Preset saved."
    GF.Window.UpdateStatus()
    Lab.Check("state","footer keeps action notice",true,GF.Window.statusText:find("Preset saved.",1,true) ~= nil)
    Lab.Check("state","footer keeps refresh age",true,GF.Window.statusText:find("Last refreshed",1,true) ~= nil)
    GF.message = nil
end)
Lab.Step("final capture", function()
    GF.SetMode(pose == "players" and "players" or "groups")
    GF.ChangeFilter("activities",{[101]=true,[102]=true})
    GF.ChangeFilter("roles",{HEALER=true})
    GF.ChangeFilter("sort","newest")
    GF.ChangeFilter("needsRole",true)
    RefreshClick(); Complete()
    GF.Select(pose == "players" and 11 or 1)
    if pose == "small" then GF.Window.frame:SetScale(.75)
    else GF.Window.frame:SetScale(1.48) end
    Lab.Check("construct","capture window visible",true,GF.Window.frame:IsVisible())
    Lab.Check("state","capture has four matches",4,#GF.rows)
    Lab.Check("state","final query count bounded",4,searches)
end)
Lab.Settle(.3)
Lab.Finish()
