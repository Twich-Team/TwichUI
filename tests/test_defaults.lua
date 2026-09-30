dofile(TESTS .. "harness.lua")
local a = MakeClient("Fresh", {"!!!TwichUI"})
a.LOADED["!!!TwichUI"]=true; a.FireEvent("ADDON_LOADED","!!!TwichUI")
assert(a.TwichUIDB.modules.groupCheck == false, "off for new installs")
local b = MakeClient("Upgrader", {"!!!TwichUI"})
b.TwichUIDB = {modules = {groupCheck = true, shareGroup = true}}   -- saved by 3.0.0
b.LOADED["!!!TwichUI"]=true; b.FireEvent("ADDON_LOADED","!!!TwichUI")
assert(b.TwichUIDB.modules.groupCheck == false, "3.0.0 default switched off once")
assert(b.TwichUIDB.modules.shareGroup == true, "other choices kept")
b.TwichUIDB.modules.groupCheck = true
local c = MakeClient("Upgrader", {"!!!TwichUI"})
c.TwichUIDB = b.TwichUIDB
c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
assert(c.TwichUIDB.modules.groupCheck == true, "turning it back on sticks")
print("DEFAULTS TESTS PASSED")
