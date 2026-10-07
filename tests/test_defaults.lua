dofile(TESTS .. "harness.lua")
local a = MakeClient("Fresh", {"!!!TwichUI"})
a.LOADED["!!!TwichUI"]=true; a.FireEvent("ADDON_LOADED","!!!TwichUI")
assert(a.TwichUIDB.modules.groupCheck == true, "on for new installs")
local b = MakeClient("Upgrader", {"!!!TwichUI"})
b.TwichUIDB = {modules = {groupCheck = false, shareGroup = true}}
b.LOADED["!!!TwichUI"]=true; b.FireEvent("ADDON_LOADED","!!!TwichUI")
assert(b.TwichUIDB.modules.groupCheck == false, "a saved choice is kept")
assert(b.TwichUIDB.modules.shareGroup == true, "other choices kept")

-- The removed combo points display: only its saved keys go; everything else stays.
local d = MakeClient("Dev", {"!!!TwichUI"})
d.TwichUIDB = {
    modules = { comboPoints = true, comboPointsHideGame = false, foodDrink = true },
    ui = { comboPoints = { style = "bar" }, comboPointsPosition = { x = 1, y = 2 }, foodDrink = { size = 30 }, showAdvanced = true },
}
d.LOADED["!!!TwichUI"]=true; d.FireEvent("ADDON_LOADED","!!!TwichUI")
assert(d.TwichUIDB.modules.comboPoints == nil and d.TwichUIDB.modules.comboPointsHideGame == nil, "combo module keys dropped")
assert(d.TwichUIDB.ui.comboPoints == nil and d.TwichUIDB.ui.comboPointsPosition == nil, "combo ui keys dropped")
assert(d.TwichUIDB.modules.foodDrink == true and d.TwichUIDB.ui.foodDrink.size == 30 and d.TwichUIDB.ui.showAdvanced == true, "unrelated settings kept")
assert(d.TwichUI.ComboPoints == nil, "no combo points module")
print("DEFAULTS TESTS PASSED")
