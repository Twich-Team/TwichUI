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
-- Dense, reproducible polish fixture: eleven groups and sixty-six solo recruits.
-- Names and content are synthetic; long values deliberately exercise clipping.
results[1].members[1].name = "Stoneward TheArgentDawn"
results[1].info.leaderName = results[1].members[1].name
results[11].members[1].name = "Ezes Bubblydoom"
results[11].info.leaderName = results[11].members[1].name
results[12].members[1].name = "Dawnmend-LesSentinellesÉternelles"
results[12].info.leaderName = results[12].members[1].name
results[12].members[1].lfgRoles.dps = true
local addedDungeons = {"Alcaz Prison","Blackmaw Hold","City of Dalaran","Excavation Site: Wetlands","Dire Maul (East)"}
for index, name in ipairs(addedDungeons) do
    activities[200+index] = {fullName=name,shortName=name,categoryID=2,maxNumPlayers=5,useDungeonRoleExpectations=true,
        minLevelSuggestion=55,maxLevelSuggestion=60,mapID=0}
end
activities[103].fullName = "Les profondeurs oubliées de la montagne des ombres"
for index = 1, 7 do
    local id = 100 + index
    local name = ({"Bronzewarden","Lightbloom","Nightglass","Mountainheart","Ashencrown","Starweaver","Stormbough"})[index]
    Listing(id, { Player(name,"WARRIOR",60,"Western Plaguelands","TANK"), Player("Companion"..index,"ROGUE",59,"Burning Steppes","DAMAGER") },
        index <= 4 and {200+index,index%2==0 and 102 or 101} or index == 5 and {103,101} or index == 6 and {205,102} or {102}, {0,1,2}, 90 + index)
    ids[#ids + 1] = id
end
for index = 1, 62 do
    local id = 1000 + index
    local classes = {"PRIEST","DRUID","SHAMAN"}
    Listing(id, { Player("Recruit"..string.format("%02d",index)..(index % 7 == 0 and "-LesSentinellesÉternelles" or ""),classes[(index-1)%3+1],58+(index%3),"Western Plaguelands","HEALER") },
        index % 2 == 0 and {102,101} or {101,102}, {0,0,0}, 100 + index)
    if index % 5 == 0 then results[id].members[1].lfgRoles.tank = true; results[id].members[1].lfgRoles.dps = true end
    ids[#ids + 1] = id
end
local searches, invites, whispers = 0, 0, 0
local lastQuery
local api = C_LFGList or {}
C_LFGList = api
api.GetAvailableCategories = function() return {2} end
api.GetLfgCategoryInfo = function(id) if id == 2 then return {name="Dungeons"} end end
api.GetAvailableActivities = function(id)
    if id ~= 2 then return {} end
    local available = {}; for activityID in pairs(activities) do available[#available+1]=activityID end
    table.sort(available); return available
end
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
if pose == "before-groups" or pose == "before-players" then
    Lab.Step("reproducible before baseline", function()
        GF.Open()
        GF.SetMode(pose == "before-players" and "players" or "groups")
        GF.ChangeFilter("activities",{[101]=true,[102]=true})
        GF.ChangeFilter("roles",{HEALER=true})
        GF.ChangeFilter("sort","newest")
        GF.ChangeFilter("needsRole",true)
        GF.ChangeFilter("minLevel",58); GF.ChangeFilter("maxLevel",60)
        RefreshClick(); Complete()
        GF.Select(pose == "before-players" and 12 or 1)
        local frame = GF.Window.frame
        frame:SetScale(1.48)
        Lab.Check("construct","baseline width",1060,frame:GetWidth())
        Lab.Check("construct","baseline height",630,frame:GetHeight())
        Lab.Check("construct","baseline row capacity",4,GF.Window.RowCount())
        Lab.Check("construct","baseline capture scale",true,math.abs(frame:GetScale()-1.48)<.0001)
        Lab.Check("construct","baseline frame visible",true,frame:IsVisible())
        Lab.Check("state","baseline expected count",pose == "before-players" and 66 or 11,#GF.rows)
        Lab.Check("state","baseline one hardware handler search",1,searches)
        Lab.Check("state","baseline successful state","ready",GF.state)
        Lab.Check("state","baseline selected survives",pose == "before-players" and 12 or 1,GF.selected and GF.selected.id)
        Lab.Check("state","baseline no automatic contact",0,invites+whispers)
    end)
    Lab.Settle(.3); Lab.Finish()
    return
end
local W = GF.Window
local function Popup() return assert(W.popup, "shared filter popup constructed") end
local function Click(key)
    local control = assert(W.controls and W.controls[key], "menu control: " .. key)
    control:Click(); Lab.Settle(.05)
end
local function Type(box, text)
    box:SetText(text)
    local changed = box:GetScript("OnTextChanged")
    if changed then changed(box, true) end
end
local function ClosePopup()
    local popup = Popup()
    if popup.close then popup.close:Click() else popup:Hide() end
end
local function InViewport(frame)
    local scale, viewport = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    return frame:GetLeft()*scale >= UIParent:GetLeft()*viewport-1
        and frame:GetRight()*scale <= UIParent:GetRight()*viewport+1
        and frame:GetTop()*scale <= UIParent:GetTop()*viewport+1
        and frame:GetBottom()*scale >= UIParent:GetBottom()*viewport-1
end
local function DrawnRows()
    local rows = {}
    for _, child in ipairs({W.frame.list:GetChildren()}) do
        if child.result and child:IsShown() then rows[#rows+1]=child end
    end
    return rows
end
Lab.Step("open and restricted-search boundary", function()
    GF.Open(); GF.SetMode("groups")
    Lab.Check("construct","shared window visible",true,W.IsShown())
    Lab.Check("state","open never launches search",0,searches)
    GF.SetActivities({[101]=true,[102]=true})
    GF.ChangeFilter("roles",{HEALER=true}); GF.ChangeFilter("sort","newest")
    RefreshClick()
    Lab.Check("interact","Refresh starts one query",1,searches)
    RefreshClick()
    Lab.Check("state","duplicate query suppressed",1,searches)
    Lab.Check("state","live dungeon category",2,lastQuery and lastQuery.category)
    Complete()
    Lab.Check("state","successful search state","ready",GF.state)
    Lab.Check("state","dense group fixtures",11,#GF.rows)
    Lab.Check("construct","eight pooled row controls",8,W.RowCount())
end)
Lab.Step("local filters snapshot failure and selection", function()
    GF.ChangeFilter("search","Stoneward")
    Lab.Check("interact","leader search immediate",1,#GF.rows)
    Lab.Check("state","local search issues no query",1,searches)
    GF.ChangeFilter("search","nobody matches this")
    Lab.Check("state","filtered empty list",0,#GF.rows)
    Lab.Check("construct","clear action exposed",true,W.frame.clear:IsShown())
    W.frame.clear:Click()
    Lab.Check("interact","clear restores groups",11,#GF.rows)
    Lab.Check("state","clear preserves dungeon one",true,GF.filters.activities[101])
    Lab.Check("state","clear preserves dungeon two",true,GF.filters.activities[102])
    GF.ChangeFilter("roles",{HEALER=true}); GF.ChangeFilter("sort","newest")
    GF.Select(1)
    local identity = GF.selected.identity
    W.frame.slider:SetValue(3)
    local scroll = W.frame.slider:GetValue()
    RefreshClick(); Event("LFG_LIST_SEARCH_FAILED","Synthetic failure")
    Lab.Check("state","failure visible","failed",GF.state)
    Lab.Check("state","last good rows survive",11,#GF.rows)
    Lab.Check("state","selected listing retained",identity,GF.selected and GF.selected.identity)
    Lab.Check("state","failed snapshot has action explanation",true,type(GF.ContactReason("whisper"))=="string")
    RefreshClick(); Complete()
    Lab.Check("state","manual recovery","ready",GF.state)
    Lab.Check("state","surviving selection retained after success",identity,GF.selected and GF.selected.identity)
    Lab.Check("state","scroll retained after refresh",scroll,W.frame.slider:GetValue())
    W.frame.slider:SetValue(0)
end)
Lab.Step("recruits advertised roles and level boundaries", function()
    GF.SetMode("players"); GF.SetActivities({[101]=true,[102]=true})
    GF.ChangeFilter("roles",{HEALER=true}); GF.ChangeFilter("sort","newest")
    GF.ChangeFilter("minLevel",58); GF.ChangeFilter("maxLevel",60)
    Lab.Check("interact","dense healer recruits",66,#GF.rows)
    GF.ChangeFilter("minLevel",60)
    Lab.Check("state","minimum level inclusive",23,#GF.rows)
    GF.ChangeFilter("minLevel",58); GF.Select(11)
    Lab.Check("state","long realm-qualified name retained","Ezes Bubblydoom",GF.selected and GF.selected.leader)
    Lab.Check("state","multi-dungeon recruit",2,GF.selected and #GF.selected.activities)
    Lab.Check("state","multi-role healer flag",true,GF.selected.roles.HEALER)
    Lab.Check("state","spaced name remains actionable",true,GF.CanContact("invite"))
    Lab.Check("state","unknown damage style retained","UNKNOWN",GF.selected.style)
    Lab.Check("state","fresh spaced name has no disabled reason",nil,GF.ContactReason("invite"))
    GF.Select(12)
    Lab.Check("state","long multirole recruit retained",true,GF.selected.roles.DAMAGER)
    Lab.Check("state","no automatic contacts",0,invites+whispers)
end)
Lab.Step("structured local filters and presets", function()
    W.frame.activities:Click()
    Lab.Check("construct","picker visible",true,Popup():IsShown())
    Lab.Check("construct","picker inside viewport",true,InViewport(Popup()))
    Lab.Check("construct","discoverable new dungeon",true,W.controls["dungeon-103"]~=nil)
    Type(W.controls["picker-search"],"City of Dalaran")
    Lab.Check("interact","picker search keeps matching dungeon",true,W.controls["dungeon-203"]~=nil)
    Lab.Check("state","picker search hides other dungeons",nil,W.controls["dungeon-201"])
    Type(W.controls["picker-search"],"")
    Lab.Check("state","clearing picker search restores choices",true,W.controls["dungeon-201"]~=nil)
    ClosePopup()
    W.frame.more:Click()
    Lab.Check("construct","More filters visible",true,Popup():IsShown())
    Lab.Check("construct","More filters inside viewport",true,InViewport(Popup()))
    Click("class-PRIEST")
    Lab.Check("interact","priest class checkbox",23,#GF.rows)
    Lab.Check("state","hidden filter summary tracks class",true,GF.HiddenFilterCount()>1)
    Click("class-PRIEST")
    Lab.Check("interact","class checkbox clears",66,#GF.rows)
    ClosePopup()
    W.frame.level:Click()
    Type(W.controls["level-min"],"60"); Type(W.controls["level-max"],"60"); Click("level-apply")
    Lab.Check("interact","custom minimum control",60,GF.filters.minLevel)
    Lab.Check("state","custom level boundary",23,#GF.rows)
    W.frame.level:Click(); Type(W.controls["level-min"],"58"); Click("level-apply")
    Lab.Check("state","custom range restored",66,#GF.rows)
    W.frame.presets:Click(); Type(W.controls["preset-name"],"Healer fixture"); Click("preset-save")
    Lab.Check("interact","preset save control",1,#GF.GetPresets())
    GF.ChangeFilter("roles",{DAMAGER=true})
    Lab.Check("state","advertised DPS includes hybrids",13,#GF.rows)
    Click("preset-load-Healer fixture")
    Lab.Check("interact","preset load restores healer selection",true,GF.filters.roles.HEALER)
    Lab.Check("state","preset restores all healer matches",66,#GF.rows)
    W.frame.presets:Click(); Click("preset-remove-Healer fixture")
    Lab.Check("interact","preset remove control",0,#GF.GetPresets())
    ClosePopup()
    Lab.Check("state","local controls initiate no searches",3,searches)
end)
Lab.Step("dungeon picker query-state semantics", function()
    local explicitAll = {}; for _, activity in ipairs(GF.GetActivities()) do explicitAll[activity.id] = true end
    GF.SetActivities(explicitAll); W.frame.activities:Click()
    Lab.Check("state","explicit full scope checks All dungeons",true,W.controls["dungeon-all"].mark:GetChecked())
    GF.SetActivities({}) -- implicit all, initially every available box is selected
    W.frame.activities:Click(); Click("dungeon-101")
    Lab.Check("state","partial dungeon scope uses mixed indicator",true,W.controls["dungeon-all"].entry.mixed)
    Lab.Check("interact","unchecking implicit all materializes selection",nil,GF.filters.activities[101])
    Lab.Check("state","other dungeon remains selected",true,GF.filters.activities[102])
    Lab.Check("state","new dungeon remains selected",true,GF.filters.activities[103])
    for _, activity in ipairs(GF.GetActivities()) do
        if activity.id ~= 101 then Click("dungeon-"..activity.id) end
    end
    Lab.Check("state","unchecked final dungeon stays none",true,GF.filters.activitiesNone)
    Lab.Check("state","no selected dungeons no loaded matches",0,#GF.rows)
    local n = searches; RefreshClick()
    Lab.Check("state","none selection cannot search everything",n,searches)
    ClosePopup(); GF.SetActivities({[101]=true,[102]=true})
    GF.UpdateQueryDirty()
    Lab.Check("state","restoring queried dungeons clears dirty flag",false,GF.queryDirty)
    GF.SetActivities({[103]=true})
    Lab.Check("state","new selection marks query dirty",true,GF.queryDirty)
    Lab.Check("state","empty loaded selection has action reason",true,type(GF.ContactReason("invite"))=="string")
    GF.SetActivities({[101]=true,[102]=true})
end)
Lab.Step("final dense capture", function()
    local players = pose == "players" or pose == "filters"
    GF.SetMode(players and "players" or "groups")
    GF.SetActivities({[101]=true,[102]=true}); GF.ChangeFilter("roles",{HEALER=true})
    GF.ChangeFilter("sort","newest"); GF.ChangeFilter("needsRole",true)
    RefreshClick(); Complete(); GF.Select(players and 12 or 1)
    local frame = W.frame
    frame.slider:SetValue(0)
    frame:SetScale(pose == "small" and .75 or pose == "default" and 1 or 1.48)
    local metrics = W.Metrics()
    Lab.Check("construct","compact frame width",920,metrics.width)
    Lab.Check("construct","compact frame height",548,metrics.height)
    Lab.Check("construct","eight visible rows",8,metrics.visibleRows)
    Lab.Check("construct","eight complete row controls",8,#DrawnRows())
    Lab.Check("state","capture total matches",players and 66 or 11,#GF.rows)
    Lab.Check("state","final search count bounded",4,searches)
    Lab.Check("construct","frame fits viewport",true,InViewport(frame))
    local first, last
    for _, row in ipairs(DrawnRows()) do
        if not first or row:GetTop()>first:GetTop() then first=row end
        if not last or row:GetBottom()<last:GetBottom() then last=row end
    end
    Lab.Check("construct","first row inside list",true,first:GetTop()<=frame.list:GetTop()+1)
    Lab.Check("construct","last row fully inside list",true,last:GetBottom()>=frame.list:GetBottom()-1)
    if pose == "picker" then
        frame.activities:Click()
        Type(W.controls["picker-search"],"")
        Lab.Check("construct","picker capture remains open",true,Popup():IsShown())
        Lab.Check("construct","picker capture in viewport",true,InViewport(Popup()))
    elseif pose == "filters" then
        frame.more:Click(); Click("class-PRIEST")
        Lab.Check("construct","filter capture in viewport",true,InViewport(Popup()))
    elseif pose == "empty" then
        GF.ChangeFilter("search","no such dungeon or player")
        Lab.Check("construct","filtered empty clear visible",true,frame.clear:IsShown())
        Lab.Check("state","empty capture has zero matches",0,#GF.rows)
    elseif pose == "stale" then
        GF.lastSuccess = GetTime()-130; Lab.Settle(1.1)
        Lab.Check("state","age produces stale status","stale",GF.state)
        Lab.Check("state","stale contacts disabled",false,GF.CanContact("whisper"))
        Lab.Check("state","stale reason available",true,type(GF.ContactReason("whisper"))=="string")
    end
end)
Lab.Settle(.3)
Lab.Finish()
