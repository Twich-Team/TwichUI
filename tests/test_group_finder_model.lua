dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local f = assert(loadfile(ROOT .. "groupfinder/Model.lua")); setfenv(f, c); f("!!!TwichUI", {})
local M = c.TwichUI.GroupFinder.Model
local a = { id=1, leader="Stoneward", solo=false, activities={10,11}, activityName="Blackrock Depths", activityNames={"Blackrock Depths","Scholomance"}, openings={TANK=0,HEALER=1,DAMAGER=0}, age=20 }
local b = { id=2, leader="Dawnmend", solo=true, activities={10,11}, activityName="Blackrock Depths", activityNames={"Blackrock Depths","Scholomance"}, roles={HEALER=true,DAMAGER=true}, class="PRIEST", level=60, style="UNKNOWN",age=12,friendCount=1 }
local filters = M.Defaults("groups")
assert(M.Matches(a, filters, "groups") and not M.Matches(b,filters,"groups"))
filters.activitiesNone=true
assert(not M.Matches(a,filters,"groups") and not M.Matches(b,filters,"players"), "explicit no dungeons never means all")
filters.activitiesNone=false
filters.activities = { [11]=true }
assert(M.Matches(a,filters,"groups"), "multi-activity OR matching")
filters.activities = { [12]=true }
assert(not M.Matches(a,filters,"groups"))
filters.activities, filters.roles = {}, {TANK=true}
assert(not M.Matches(a,filters,"groups"), "group filter uses remaining role, not tank already present")
filters.roles = { HEALER=true }
assert(M.Matches(a,filters,"groups"))
filters.needsRole = true
assert(M.Matches(a,filters,"groups"), "needs my role uses selected roles")
assert(M.Matches(b,filters,"players",{known=true,openings={HEALER=1,DAMAGER=0}}))
assert(not M.Matches(b,filters,"players",{known=true,openings={HEALER=0,DAMAGER=0,TANK=1}}))
assert(M.Matches(b,filters,"players",{known=false,reason="Unknown"}), "manual roles remain usable without party composition")
filters = M.Defaults("players")
filters.minLevel, filters.maxLevel = 60,60
assert(M.Matches(b,filters,"players"),"inclusive level bounds")
filters.maxLevel = 59
assert(not M.Matches(b,filters,"players"))
filters.maxLevel,filters.minLevel,filters.classes = nil,nil,{DRUID=true}
assert(not M.Matches(b,filters,"players"))
filters.classes, filters.search = {},"SCHolo"
assert(M.Matches(b,filters,"players"),"immediate case-insensitive search over every listed dungeon")
filters.search = "dawn"
assert(M.Matches(b,filters,"players"))
filters.search = "%"
assert(not M.Matches(b,filters,"players"),"search is plain text")
filters.search,filters.friendsOnly = "",true
assert(M.Matches(b,filters,"players") and not M.Matches(a,filters,"groups"))
filters.guildOnly = true
assert(not M.Matches(b,filters,"players"))
filters.guildOnly,filters.friendsOnly,filters.maxAge = false,false,11
assert(not M.Matches(b,filters,"players"))
assert(M.Sort({a,b},"newest")[1] == b)
local elapsed = 10
c.GetTime = function() return elapsed end
b.readAt, b.age = 10, 299
local aging = M.Defaults(); aging.maxAge = 300
assert(M.Matches(b,aging,"players"))
elapsed = 12
assert(not M.Matches(b,aging,"players"), "listing age advances locally without a server search")
b.readAt, b.age = nil, 12
assert(#M.Filter({a,b},M.Defaults(),"players") == 1)

local db = c.TwichUIDB
db.groupFinder = {mode="players",players={roles={HEALER=true},needsRole=false,search="restored"}}
assert(M.Get("players").search == "restored" and M.Get("players").needsRole == false)
M.Set("players","minLevel",58)
assert(M.Get("players").minLevel == 58 and M.Get("players").roles.HEALER)
assert(M.SavePreset("players","  Healers  ",M.Get("players")))
M.Set("players","search","")
assert(M.LoadPreset("players","Healers").search == "restored")
local p = M.Get("players");p.activities={[10]=true,[999]=true}
assert(M.SavePreset("players","Dungeons",p))
assert(M.LoadPreset("players","Dungeons",{{id=10}}).activities[10])
assert(not M.Get("players").activities[999],"unavailable IDs do not hide all loaded listings")
assert(M.GetPresets("players").Dungeons.activities[999],"saved preset retains temporarily unavailable ID")
M.Set("players","activitiesNone",true)
assert(M.SavePreset("players","None",M.Get("players")))
M.Set("players","activitiesNone",false)
assert(M.LoadPreset("players","None",{{id=10}}).activitiesNone, "preset preserves explicit empty selection")
M.DeletePreset("players","Healers")
assert(not M.GetPresets("players").Healers)
assert(not M.SavePreset("players","|Tbad",{}))
local saved = db.groupFinder
f = assert(loadfile(ROOT .. "groupfinder/Model.lua"));setfenv(f,c);f("!!!TwichUI",{})
assert(c.TwichUI.GroupFinder.Model.Get("players").minLevel == 58 and db.groupFinder == saved,"restores settings without reset")
print("test_group_finder_model: OK")
