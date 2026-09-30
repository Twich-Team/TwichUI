dofile(TESTS .. "harness.lua")
local me = MakeClient("Twich", {"!!!TwichUI","Foo"})
CLIENTS.Twich = me
me.TwichUIDB = {setup = {scanNext = true}}
me.LOADED["!!!TwichUI"]=true; me.FireEvent("ADDON_LOADED","!!!TwichUI")
me.FooDB = {a=string.rep("x", 5000)}; me.LOADED.Foo=true; me.FireEvent("ADDON_LOADED","Foo")
me.FireEvent("PLAYER_LOGIN")
local ST = me.TwichUI.Setups
ST:SaveMine(false)
assert(me.TwichUI.Share:SendToSelf()); (function() for _=1,10 do FlushTimers(); Pump() end end)(); me.TwichUI.Share:Respond("Twich-Forever", true); (function() for _=1,10 do FlushTimers(); Pump() end end)(); (function() for _=1,10 do FlushTimers(); Pump() end end)()
me.TwichUIBackupDB["Twich - Forever"] = {created=1, tables={FooDB={present=true,data={b=1}}}}
local items = ST.StorageItems()
for _, i in ipairs(items) do print(i.kind, i.label, ST.FormatSize(i.bytes)) end
assert(#items == 4)
for _, i in ipairs(items) do i.remove() end
assert(#ST.StorageItems() == 0 and ST.Mine() == nil and not ST:HasBackup())
print("STORAGE TESTS PASSED")
