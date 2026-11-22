dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Load the actual feature as an optional subsystem in the shared settings client.
local function LoadLoot(c)
    for _, name in ipairs({ "Rules", "Config", "Roll", "Auto", "Blizzard", "Cards", "Victory", "Main" }) do
        local chunk = assert(loadfile(ROOT .. "loot/" .. name .. ".lua")); setfenv(chunk, c); chunk()
    end
    assert(c.TwichUI.LootRolls.Get("victoryIntensity") == "subtle", "core defaults before settings load")
end
local c, S = SettingsClient({ beforeInit = LoadLoot })
local R, K = c.TwichUI, S.K
local LR = R.LootRolls
assert(not LR.IsOn() and LR.Get("victoryIntensity") == "subtle", "core defaults work before settings")
local page = K.pages.lootRolls
assert(page, "loot page available")
local expected = { Victory = true, VictoryIntensity = "subtle", VictorySound = false, VictoryDuration = "normal" }
for suffix, default in pairs(expected) do
    local setting = assert(K.variables["TWICHUI_lootRolls" .. suffix], suffix)
    assert(setting.default == default and setting.get() == default, tostring(setting.default) .. " / " .. tostring(setting.get()) .. " / " .. tostring(default))
end
K.variables.TWICHUI_lootRollsVictory.set(false)
K.variables.TWICHUI_lootRollsVictoryIntensity.set("off")
K.variables.TWICHUI_lootRollsVictorySound.set(false)
K.variables.TWICHUI_lootRollsVictoryDuration.set("long")
assert(not LR.Get("victory") and not LR.Get("victorySound") and LR.Get("victoryDuration") == "long")
assert(c.TwichUIDB.ui.lootRolls.victoryIntensity == "off")
local saved = c.TwichUIDB.ui.lootRolls
local reloaded = SettingsClient({ beforeInit = LoadLoot, beforeDescribe = function(client) client.TwichUIDB.ui = { lootRolls = saved } end })
assert(not reloaded.TwichUI.LootRolls.Get("victory") and reloaded.TwichUI.LootRolls.Get("victoryDuration") == "long", "new client reads saved values")
local choice = assert(K.variables.TWICHUI_lootRollsVictoryPreviewChoice)
local quality = assert(K.variables.TWICHUI_lootRollsVictoryPreviewQuality)
choice.set("greed"); quality.set(5)
assert(choice.get() == "greed" and quality.get() == 5, "sample selectors work while module is disabled")
local displayed
R.LootVictory.Preview = function(kind, q) displayed = { kind, q }; return true end
local previewRow
for _, row in ipairs(page.rows) do
    if row:GetName() == "Preview victory card" then previewRow = row end
end
assert(previewRow, "preview is described/searchable with the page")
previewRow.click(); previewRow.click()
assert(displayed[1] == "greed" and displayed[2] == 5, "each click replays the selected combination")
assert(c.TwichUIDB.ui.lootRolls.victoryPreviewChoice == nil and c.TwichUIDB.ui.lootRolls.victoryPreviewQuality == nil,
    "sample selectors never save fake loot state")
LR.ResetSettings()
assert(LR.Get("victory") and LR.Get("victoryIntensity") == "subtle" and LR.Get("victoryDuration") == "normal")
assert(not LR.Valid("victoryIntensity", "loud") and not LR.Valid("victoryDuration", 999))
print("PASSED")
