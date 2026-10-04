dofile(TESTS .. "harness.lua")
------------ Rich: session with scan requested
local rich = MakeClient("Rich", {"!!!TwichUI","Foo","Bar"})
CLIENTS.Rich = rich
rich.TwichUIDB = {setup = {scanNext = true}}
rich.LOADED["!!!TwichUI"] = true; rich.FireEvent("ADDON_LOADED", "!!!TwichUI")
rich.FooDB = {profiles={RichProf={scale=1.2}}, profileKeys={["Rich - Forever"]="RichProf"}}
rich.FooMixin = {fn=function() end}
rich.LOADED.Foo=true; rich.FireEvent("ADDON_LOADED","Foo")
rich.BarSettings = {enabled=true}; rich.BAR_PRICE_DATABASE = {a=1}
rich.LOADED.Bar=true; rich.FireEvent("ADDON_LOADED","Bar")
rich.FireEvent("PLAYER_LOGIN")
local ST = rich.TwichUI.Setups
local groups = ST:DetectedByAddon()
for _, g in ipairs(groups) do print("group", g.title, g.selected, #g.tables) end
ST:SaveMine(false)
local mine = ST.Mine()
assert(mine.tables.FooDB and mine.tables.BarSettings and not mine.tables.BAR_PRICE_DATABASE)
print("hash FooDB", mine.tables.FooDB.hash)

------------ Pal: fresh friend
local pal = MakeClient("Pal", {"!!!TwichUI","Foo","Bar"})
CLIENTS.Pal = pal
pal.LOADED["!!!TwichUI"] = true; pal.FireEvent("ADDON_LOADED", "!!!TwichUI")
pal.FooDB = {profiles={Default={}}, profileKeys={}}; pal.LOADED.Foo=true; pal.FireEvent("ADDON_LOADED","Foo")
pal.BarSettings = {enabled=false}; pal.LOADED.Bar=true; pal.FireEvent("ADDON_LOADED","Bar")
pal.FireEvent("PLAYER_LOGIN")

-- send
local ok, why = rich.TwichUI.Share:SendTo("Pal")
assert(ok, why)
;(function() for _=1,10 do FlushTimers(); Pump() end end)()
local inc = pal.TwichUI.Share.incoming["Rich-Forever"]
assert(inc and inc.stage == "asking", "pal asked")
pal.TwichUI.Share:Respond("Rich-Forever", true)
;(function() for _=1,10 do FlushTimers(); Pump() end end)(); (function() for _=1,10 do FlushTimers(); Pump() end end)()
assert(inc.stage == "done", "received: "..tostring(inc.stage))
assert(rich.TwichUI.Share.outgoing.stage == "done", "sender done")
local recv = pal.TwichUIDB.setup.received["Rich-Forever"]
assert(recv.tables.FooDB.data.profiles.RichProf.scale == 1.2)
print("first transfer parts:", rich.TwichUI.Share.outgoing.parts)

-- second send with no changes: should send 0 parts
rich.TwichUI.Share.outgoing = nil
assert(rich.TwichUI.Share:SendTo("Pal")); (function() for _=1,10 do FlushTimers(); Pump() end end)()
pal.TwichUI.Share:Respond("Rich-Forever", true); (function() for _=1,10 do FlushTimers(); Pump() end end)(); (function() for _=1,10 do FlushTimers(); Pump() end end)()
print("second transfer parts:", rich.TwichUI.Share.outgoing.parts)
assert(rich.TwichUI.Share.outgoing.parts == 0)
assert(pal.TwichUIDB.setup.received["Rich-Forever"].tables.FooDB.data.profiles.RichProf.scale == 1.2, "kept unchanged")

-- change Bar only, resave (simulate capture changes), send: 1 part
ST.capture.BarSettings.data = {enabled=true, newThing=5}
ST:SaveMine(false)
rich.TwichUI.Share.outgoing = nil
assert(rich.TwichUI.Share:SendTo("Pal")); (function() for _=1,10 do FlushTimers(); Pump() end end)()
pal.TwichUI.Share:Respond("Rich-Forever", true, true); (function() for _=1,10 do FlushTimers(); Pump() end end)(); (function() for _=1,10 do FlushTimers(); Pump() end end)()
print("third transfer parts:", rich.TwichUI.Share.outgoing.parts)
assert(rich.TwichUI.Share.outgoing.parts == 1)
assert(pal.TwichUIDB.setup.received["Rich-Forever"].tables.BarSettings.data.newThing == 5)
assert(pal.TwichUIDB.setup.trusted["Rich-Forever"])
-- fourth: trusted auto-accept
rich.TwichUI.Share.outgoing = nil
assert(rich.TwichUI.Share:SendTo("Pal")); (function() for _=1,10 do FlushTimers(); Pump() end end)(); (function() for _=1,10 do FlushTimers(); Pump() end end)(); (function() for _=1,10 do FlushTimers(); Pump() end end)()
assert(rich.TwichUI.Share.outgoing.stage == "done", "auto accepted")

------------ Pal applies (queue, then new session)
local src = pal.TwichUI.Setups.Sources()[1]
pal.TwichUI.Setups:Queue("apply", {"FooDB","BarSettings"}, src.key)
assert(pal.reloaded)
local savedDB, savedBackup, savedShare = pal.TwichUIDB, pal.TwichUIBackupDB, pal.TwichUIShareDB
local pal2 = MakeClient("Pal", {"!!!TwichUI","Foo","Bar"})
pal2.TwichUIDB, pal2.TwichUIBackupDB, pal2.TwichUIShareDB = savedDB, savedBackup, savedShare
pal2.LOADED["!!!TwichUI"] = true; pal2.FireEvent("ADDON_LOADED", "!!!TwichUI")
pal2.FooDB = {profiles={Default={}}, profileKeys={}}; pal2.LOADED.Foo=true; pal2.FireEvent("ADDON_LOADED","Foo")
pal2.BarSettings = {enabled=false}; pal2.LOADED.Bar=true; pal2.FireEvent("ADDON_LOADED","Bar")
pal2.FireEvent("PLAYER_LOGIN")
assert(pal2.FooDB.profileKeys["Pal - Forever"] == "RichProf", "profile pointed")
assert(pal2.BarSettings.newThing == 5, "bar applied")
assert(pal2.TwichUIBackupDB["Pal - Forever"].tables.BarSettings.data.enabled == false, "backup")
-- media registered
local LSM = pal2.LibStub("LibSharedMedia-3.0")
assert(LSM:IsValid("font", "Cinzel") and LSM:IsValid("sound", "GTFO Fail"))
for name, file in pairs({ ["Spectral"] = "Spectral-Regular.ttf", ["Spectral Medium"] = "Spectral-Medium.ttf",
    ["Spectral SemiBold"] = "Spectral-SemiBold.ttf", ["Spectral Bold"] = "Spectral-Bold.ttf" }) do
    assert(LSM:IsValid("font", name), name)
    assert(LSM:Fetch("font", name):find(file, 1, true), name .. " -> " .. file)
    assert(io.open(ROOT .. "media/fonts/" .. file, "rb"), file .. " missing from media/fonts"):close()
end
print("ALL TESTS PASSED")
