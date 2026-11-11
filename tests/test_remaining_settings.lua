dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local c, S = SettingsClient()
local R, K = c.TwichUI, S.K
local function Row(page, name)
    for _, row in ipairs(K.pages[page].rows) do if row:GetName() == name then return row end end
    error("missing " .. name)
end
local MX = R.MapExplorePrefs
local initial = MX.Get("caves")
R:SetEnabled("mapExplore", true)
local cave = Row("worldMapPlaces", "Caves")
cave.setting:SetValue(not initial)
assert(MX.Get("caves") == not initial)
cave.setting:SetValue(initial)
R:SetEnabled("mapExplore", false)
assert(MX.Get("caves") == initial, "preferences survive exploration being off")
Row("worldMapPlaces", "Map exploration").click()
assert(c.opened == "worldMap", "setup navigation never enables exploration")
local originalState, originalLoaded = K.AddonState, K.Loaded
local state = "missing"
K.AddonState = function() return state end
K.Loaded = function() return state == "loaded" end
local skinRow = K.switchRows.auctionatorSkin
local card
for _, row in ipairs(K.pages.skins.rows) do if row.card and row.card.title == "Auctionator look" then card = row.card end end
assert(card.summary():find("Not installed",1,true))
state = "loaded"; R.S = true
local enabled = skinRow.setting:GetValue()
assert(not card.summary():find("Active",1,true), "no claim that frames were verified")
skinRow.setting:SetValue(not enabled)
assert(card.summary():find("reload",1,true), "reload state is visible")
skinRow.setting:SetValue(enabled)
K.AddonState, K.Loaded = originalState, originalLoaded
print("REMAINING SETTINGS PASSED")
