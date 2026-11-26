dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
local clock, searches, whispers, invites = 10, 0, 0, 0
local lastActivities
c.GetTime = function() return clock end
c.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
local secret = { secret = true }
local info = {
    [11] = { partyGUID="Party-11", leaderName="Stoneward", numMembers=4, activityIDs={101}, hasSelf=false, isDelisted=false },
    [12] = { partyGUID="Party-12", leaderName="Dawnmend", numMembers=1, activityIDs={101,102}, hasSelf=false, isDelisted=false },
}
local ids = {11,12}
local member = {name="Dawnmend",level=60,areaName="Searing Gorge",classFilename="PRIEST",className="Priest",assignedRole="HEALER",lfgRoles={healer=true},isLeader=true}
local searchHook
c.hooksecurefunc = function(target, key, callback)
    if type(target) == "table" then
        local original = target[key]
        target[key] = function(...) local a,b = original(...); callback(...); return a,b end
        searchHook = callback
    end
end
c.C_LFGList = {
    GetAvailableCategories=function() return {2} end,
    GetAvailableActivities=function() return {101,102} end,
    GetActivityInfoTable=function(id) return {fullName=id==101 and "Blackrock Depths" or "Scholomance",categoryID=2,maxNumPlayers=5,useDungeonRoleExpectations=true} end,
    GetSearchResults=function() return #ids, ids end,
    GetSearchResultInfo=function(id) return info[id] end,
    GetSearchResultLeaderInfo=function() return member end,
    GetSearchResultPlayerInfo=function() return member end,
    GetSearchResultMemberCounts=function() return {TANK_REMAINING=0,HEALER_REMAINING=1,DAMAGER_REMAINING=0} end,
    Search=function(_,_,_,_,_,_,activities) searches=searches+1; lastActivities=activities; assert(#activities>=1 and #activities<=2) end,
}
c.IsInGroup=function() return false end
c.UnitGroupRolesAssigned=function() return "TANK" end
c.ChatFrameUtil={SendTell=function(name) assert(name=="Stoneward" or name=="Dawnmend"); whispers=whispers+1 end}
c.C_PartyInfo={InviteUnit=function(name) assert(name=="Dawnmend"); invites=invites+1 end}
local function Load(file) local chunk=assert(loadfile(ROOT.."groupfinder/"..file..".lua")); setfenv(chunk,c); chunk() end
Load("Art"); Load("Data"); Load("Model"); Load("Controller")
local GF=c.TwichUI.GroupFinder
local shown, renders = false, 0
GF.Window={Show=function() shown=true end,Hide=function() shown=false end,IsShown=function() return shown end,Render=function() renders=renders+1 end}
c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
assert(GF.Open() and searches==0, "opening never searches")
assert(GF.queryDirty and GF.GetStatus()=="Ready to search")
assert(GF.ContactReason("whisper")=="Select a listing first.")
assert(GF.Refresh() and searches==1 and GF.state=="searching")
assert(not GF.Refresh() and searches==1, "no duplicate in-flight request")
assert(not GF.CanContact("whisper"), "no actions during search")
c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(GF.state=="ready" and #GF.rows==1 and GF.selected.id==11)
assert(not GF.queryDirty and GF.GetStatus()=="Updated <1m ago")
assert(GF.CanContact("whisper") and GF.Contact("whisper") and whispers==1)
assert(not GF.contacted[GF.selected.identity], "opening whisper is not sending one")
c.FireEvent("CHAT_MSG_WHISPER_INFORM","hello","Stoneward")
assert(GF.contacted[GF.selected.identity]=="Whispered")
local identity=GF.selected.identity
GF.ChangeFilter("search","Stone")
assert(GF.selected.identity==identity and searches==1, "local typing preserves selection without search")
GF.ChangeFilter("search","no matching name")
assert(#GF.rows==0 and #GF.snapshot==2)
GF.ChangeFilter("search","")
GF.SetMode("players")
assert(#GF.rows==1 and GF.selected.id==12 and GF.CanContact("invite"))
assert(GF.Contact("invite") and invites==1 and GF.selected.contacted=="Invited")
local read, contactReads = GF.Data.Read, 0
GF.Data.Read = function(id)
    contactReads = contactReads + 1
    if contactReads > 1 then return nil end
    return read(id)
end
assert(GF.Contact("whisper") and contactReads==1, "contact uses the same live record it validated")
GF.Data.Read = read
info[12].partyGUID="Party-recycled"
assert(not GF.CanContact("invite") and not GF.Contact("invite") and invites==1, "recycled ID is not actionable")
c.FireEvent("LFG_LIST_SEARCH_RESULT_UPDATED",12)
assert(#GF.rows==0, "recycled row removed until next query")
info[12].partyGUID="Party-12"
assert(GF.Refresh())
c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(GF.selected and GF.selected.id==12)
info[12].isDelisted=secret
assert(not GF.CanContact("invite"), "unknown validity cannot invite")
info[12].isDelisted=false
info[12].hasSelf=secret
assert(not GF.CanContact("invite"), "unknown self flag cannot invite")
info[12].hasSelf=false
c.InCombatLockdown=function() return true end
assert(not GF.CanContact("invite") and not GF.Refresh())
c.InCombatLockdown=function() return false end
assert(GF.SavePreset("Healing") and #GF.GetPresets()==1)
GF.ChangeFilter("minLevel",58)
assert(GF.LoadPreset("Healing") and not GF.filters.minLevel)
assert(GF.DeletePreset("Healing") and #GF.GetPresets()==0)
local last=GF.lastSuccess
assert(GF.Refresh())
c.FireEvent("LFG_LIST_SEARCH_FAILED")
assert(GF.state=="failed" and #GF.rows==1 and GF.lastSuccess==last and not GF.CanContact("invite"))
assert(GF.Refresh())
c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
c.C_LFGList.Search(2,0,0,nil,false,nil,{101,102})
assert(GF.state=="stale" and not GF.CanContact("invite"), "foreign search invalidates ownership")
c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(GF.state=="stale", "foreign completion never becomes ours")
assert(GF.Refresh())
c.C_LFGList.Search(2,0,0,nil,false,nil,{101,102})
c.FireEvent("LFG_LIST_SEARCH_FAILED")
assert(GF.state=="stale", "foreign failure cannot mutate our old snapshot")
assert(GF.Refresh())
c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
clock=clock+121; RunTickers()
assert(GF.state=="stale" and not GF.CanContact("invite"))
assert(GF.Refresh()); clock=clock+31; RunTickers()
assert(GF.state=="failed" and #GF.rows==1, "timeout retains last good rows")

-- Local activity choices describe a requested scope, never a completed search.
assert(GF.Refresh()); c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(not GF.queryDirty)
local beforeChanges = searches
GF.SetActivities({[101]=true},false)
assert(GF.queryDirty and GF.GetStatus()=="Selection changed · Search" and searches==beforeChanges)
assert(GF.Refresh() and #lastActivities==1 and lastActivities[1]==101)
GF.SetActivities({[102]=true},false)
c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(GF.queryDirty, "a completion for earlier dungeons cannot clean a later selection")
GF.SetActivities({[101]=true},false)
assert(not GF.queryDirty, "restoring the successfully queried scope needs no extra search")
GF.SetActivities({},false)
assert(GF.queryDirty and GF.Refresh())
c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(not GF.queryDirty)
GF.SetActivities({[102]=true},false)
assert(GF.SavePreset("Different scope"))
local success = GF.lastSuccess
assert(GF.Refresh()); c.FireEvent("LFG_LIST_SEARCH_FAILED")
assert(GF.queryDirty and GF.lastSuccess==success, "failed query cannot clean the changed scope")
GF.SetActivities({},false)
assert(not GF.queryDirty, "scope can match the last good query even while its results are gated")
assert(GF.LoadPreset("Different scope") and GF.queryDirty)
assert(GF.Refresh()); c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(not GF.queryDirty)

GF.SetActivities({},true)
local beforeNone=searches
assert(#GF.rows==0 and GF.queryDirty and not GF.Refresh() and searches==beforeNone, "unchecked final dungeon never searches all")
assert(GF.SavePreset("No dungeons"))
GF.SetActivities({},false)
assert(GF.LoadPreset("No dungeons") and GF.filters.activitiesNone and #GF.rows==0)
GF.ClearFilters()
assert(GF.filters.activitiesNone and #GF.rows==0, "clear local filters preserves an explicit empty dungeon scope")
GF.ChangeFilter("activities",{[102]=true})
assert(not GF.filters.activitiesNone)

-- Clear hidden and top-surface criteria together, preserving dungeons and presets.
GF.ChangeFilter("classes",{PRIEST=true,DRUID=true})
GF.ChangeFilter("playstyle",2); GF.ChangeFilter("maxAge",300)
GF.ChangeFilter("friendsOnly",true); GF.ChangeFilter("guildOnly",true); GF.ChangeFilter("sort","newest")
GF.ChangeFilter("search","no match"); GF.ChangeFilter("minLevel",59); GF.ChangeFilter("maxLevel",60)
GF.ChangeFilter("roles",{HEALER=true}); GF.ChangeFilter("needsRole",true)
assert(GF.HiddenFilterCount()==7, "only hidden criteria count, not text, levels, roles or role toggle")
local presetCount=#GF.GetPresets()
GF.ClearFilters()
assert(GF.HiddenFilterCount()==0 and GF.filters.search=="" and next(GF.filters.roles)==nil and not GF.filters.needsRole)
assert(not GF.filters.minLevel and not GF.filters.maxLevel and GF.filters.activities[102] and #GF.GetPresets()==presetCount)
assert(#GF.rows==1 and GF.selected.id==12 and searches==beforeNone, "reset changes local view without fetching")

-- Recent data can still be non-actionable for explicit native validity reasons.
assert(GF.Refresh()); c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
assert(GF.ContactReason("invite")==nil and GF.CanContact("invite"))
c.IsInGroup=function() return true end
c.GetNumGroupMembers=function() return 5 end
c.UnitIsGroupLeader=function() return true end
c.UnitIsGroupAssistant=function() return false end
assert(GF.ContactReason("invite")=="Your party is full." and not GF.CanContact("invite"))
c.GetNumGroupMembers=function() return 4 end; c.UnitIsGroupLeader=function() return false end
assert(GF.ContactReason("invite")=="Only the party leader or an assistant can invite.")
c.UnitIsGroupLeader=function() return true end; c.IsInRaid=function() return true end
assert(GF.ContactReason("invite")=="Invites here require a five-player party.")
c.IsInRaid=function() return false end; c.InCombatLockdown=function() return true end
assert(GF.ContactReason("invite")=="Invite after combat.")
c.InCombatLockdown=function() return false end; c.IsInGroup=function() return secret end
assert(GF.ContactReason("invite")=="Party status is unavailable.")
c.IsInGroup=function() return false end
local inviteAPI=c.C_PartyInfo.InviteUnit; c.C_PartyInfo.InviteUnit=nil
assert(GF.ContactReason("invite")=="The game's invite action is unavailable.")
c.C_PartyInfo.InviteUnit=inviteAPI
local liveIdentity=GF.selected.identity; GF.selected.identity=nil
assert(GF.ContactReason("invite"):find("identity is unavailable",1,true))
GF.selected.identity=liveIdentity; info[12].partyGUID="reused"
assert(GF.ContactReason("invite")=="This listing changed. Refresh and select it again.")
info[12].partyGUID="Party-12"

-- Actual Forever full names contain spaces; native actions need the exact name.
local nativeWhisper, nativeInvite = c.ChatFrameUtil.SendTell, c.C_PartyInfo.InviteUnit
local whisperTarget, inviteTarget
c.ChatFrameUtil.SendTell=function(name) whisperTarget=name end
c.C_PartyInfo.InviteUnit=function(name) inviteTarget=name end
for _, name in ipairs({"Ezes Bubblydoom","Hellacute UwU","Cuarto Delibra","Murloc Fishgerald"}) do
    info[12].leaderName, member.name = name, name
    assert(GF.Refresh()); c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert(GF.CanContact("whisper") and GF.Contact("whisper") and whisperTarget==name, "native full-name whisper remains exact")
    assert(GF.CanContact("invite") and GF.Contact("invite") and inviteTarget==name, "native full-name invite remains exact")
end
for _, name in ipairs({"", "   ", "Ezes\tBubblydoom", "Ezes\nBubblydoom", "Ezes\000Bubblydoom", "|cffffffffEzes Bubblydoom|r", "|Hplayer:other|hname|h"}) do
    info[12].leaderName, member.name = name, name
    whisperTarget, inviteTarget = nil, nil
    assert(GF.Refresh()); c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    assert(not GF.CanContact("whisper") and not GF.Contact("whisper") and whisperTarget==nil, "empty/control/markup target cannot whisper")
    assert(not GF.CanContact("invite") and not GF.Contact("invite") and inviteTarget==nil, "empty/control/markup target cannot invite")
end
c.ChatFrameUtil.SendTell, c.C_PartyInfo.InviteUnit = nativeWhisper, nativeInvite
info[12].leaderName, member.name = "Dawnmend", "Dawnmend"
assert(GF.Refresh()); c.FireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
clock=clock+121
assert(GF.GetStatus()=="Stale · Updated 2m ago" and GF.ContactReason("invite"):find("two minutes old",1,true))
clock=clock+3600
assert(GF.GetStatus():find("Updated 1h ago",1,true), "footer avoids long raw seconds")
local count=searches
GF.Close(); RunTickers()
assert(not shown and searches==count)
assert(not GF.Refresh(), "keybinding only searches with browser open")
assert(searchHook and renders>0)
print("test_group_finder_controller: OK")
