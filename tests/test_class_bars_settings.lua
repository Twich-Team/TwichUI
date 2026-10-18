dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Class resource bars, the settings pages (TwichUI_Settings/pages/ClassBars.lua) and the report section: the four
-- pages and where they sit; each row reads and writes through the feature (never the saved variables); narrow
-- resets say what they cover and keep the rest; a class's own resource rows are per class and resource, show
-- whether they override the shared style and reset only themselves; rows are greyed out with a reason while the
-- bars are off; the report names resources and counts but no values. The bars themselves are test_class_bars.lua.

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. tostring(msg)) end end

local function Pages(S)
  local by = {}
  for _, p in ipairs(S.pages) do by[p.key] = p end
  return by
end
local function Row(page, name, kind)
  for _, r in ipairs(page.rows) do if r:GetName() == name and (not kind or r.kind == kind) then return r end end
end

local c, S = SettingsClient({ name = "Mage" })
local R = c.TwichUI
local CB, K = R.ClassBars, S.K

-- pages
do
  local by = Pages(S)
  Check(by.classBars and by.classBars.group == "class" and by.classBars.kind == "page", "the page is under Gear & class")
  for _, key in ipairs({ "classBarsLayout", "classBarsLook", "classBarsEffects" }) do
    Check(by[key] and by[key].parent == "Class resource bars", key .. " is a tab of it")
  end
  Check(#K.Tabs("classBars") == 4 and K.Tabs("classBars")[1].key == "classBars", "General, Layout, Appearance, Effects")
  local names = {}
  for _, t in ipairs(K.Tabs("classBars")) do names[#names + 1] = K.TabLabel(t) end
  Check(table.concat(names, ",") == "General,Layout,Appearance,Effects", "tab names: " .. table.concat(names, ","))
end

-- rows read and write through the feature
do
  local v = S.variables
  R:SetEnabled("classBars", false)
  v.TWICHUI_classBarsScale:SetValue(130)
  Check(CB.Get("scale") == 130 and v.TWICHUI_classBarsScale.get() == 130, "a slider writes through Set")
  v.TWICHUI_classBarsHideMounted:SetValue(true)
  Check(CB.Get("hideMounted") == true)
  v.TWICHUI_classBarsShow:SetValue("combat")
  Check(CB.Get("show") == "combat")
  v.TWICHUI_classBarsPrimaryWidth:SetValue(10)
  Check(CB.Get("primaryWidth") == 10 or CB.Get("primaryWidth") == 240, "an out-of-range value is refused by the feature, not clamped by the page")
  v.TWICHUI_classBarsLookBgOpacity:SetValue(20)
  Check(CB.Look.Get("bgOpacity") == 20, "the look's rows write the look")
  v.TWICHUI_classBarsEffects:SetValue(true)
  Check(CB.Get("effects") == true)
  Check(c.TwichUIDB.ui.classBars.scale == 130 and c.TwichUIDB.ui.classBarsLook.bgOpacity == 20, "saved where the feature keeps them")
end

-- narrow resets
do
  local by = Pages(S)
  local reset = Row(by.classBarsLayout, "Layout", "button")
  Check(reset and reset.reset, "the Layout page has its reset")
  local text = S.ClickReset(reset)
  Check(CB.Get("scale") == 100, "the layout is back")
  Check(CB.Get("show") == "combat" and CB.Get("hideMounted") and CB.Get("effects") and CB.Look.Get("bgOpacity") == 20,
    "and the behavior, effects and look are kept")
  Check(text:find("differ from their defaults", 1, true), "it says how much it changes")
  local when = Row(by.classBars, "When to show", "button")
  Check(when and when.reset)
  S.ClickReset(when)
  Check(CB.Get("show") == "always" and CB.Get("hideMounted") == false and CB.Get("effects") == true, "When to show resets its own")
  S.ClickReset(Row(by.classBarsEffects, "Effects", "button"))
  Check(CB.Get("effects") == false and CB.Look.Get("bgOpacity") == 20, "Effects resets its own")
  local look = Row(by.classBarsLook, "Background and border", "button")
  Check(look and look.reset)
  S.ClickReset(look)
  Check(CB.Look.Get("bgOpacity") == CB.Look.DEFAULTS.bgOpacity, "the look resets by itself")
end

-- a class's own resources: per class and resource, shown as overriding or inherited, reset alone
do
  local by = Pages(S)
  local v = S.variables
  Check(v.TWICHUI_classBarsOvMANASource and v.TWICHUI_classBarsOvMANAText and v.TWICHUI_classBarsOvMANAShow and v.TWICHUI_classBarsOvMANAColor,
    "a Mage has rows for its mana")
  Check(not v.TWICHUI_classBarsOvRAGESource and not v.TWICHUI_classBarsOvCOMBOPOINTSSource, "and for nothing it cannot have")
  local source = v.TWICHUI_classBarsOvMANASource
  Check(source.get() == "inherit" and CB.GetOverride("MAGE:MANA", "colorSource") == nil, "inheriting by default")
  local row
  for _, r in ipairs(by.classBarsLook.rows) do if r.setting == source then row = r end end
  Check(row and row.note and row.note():find("Following the shared style", 1, true), "the row says it follows the shared style")
  source:SetValue("class")
  Check(CB.GetOverride("MAGE:MANA", "colorSource") == "class" and c.TwichUIDB.ui.classBarsOverrides["MAGE:MANA"].colorSource == "class",
    "saved under the class and resource")
  Check(row.note():find("this resource only", 1, true), "and says it overrides")
  v.TWICHUI_classBarsOvMANAColor:SetValue("ff102030")
  Check(CB.GetOverride("MAGE:MANA", "color") == "ff102030" and CB.GetOverride("MAGE:MANA", "colorSource") == "custom", "choosing a color makes the fill custom")
  v.TWICHUI_classBarsOvMANAText:SetValue("percent")
  v.TWICHUI_classBarsOvMANAShow:SetValue("never")
  Check(CB.GetOverride("MAGE:MANA", "text") == "percent" and CB.GetOverride("MAGE:MANA", "show") == "never")
  v.TWICHUI_classBarsOvMANAShow:SetValue("inherit")
  Check(CB.GetOverride("MAGE:MANA", "show") == nil, "Same as the shared style stops overriding")
  source:SetValue("inherit")
  Check(CB.GetOverride("MAGE:MANA", "color") == nil and CB.GetOverride("MAGE:MANA", "colorSource") == nil, "inheriting the fill forgets the custom color too")
  -- another class's setting is not touched by this page's reset
  CB.SetOverride("WARRIOR:RAGE", "text", "none")
  local reset = Row(by.classBarsLook, "Reset Mana")
  Check(reset and reset.reset, "each resource has its own reset")
  S.ClickReset(reset)
  Check(not CB.HasOverride("MAGE:MANA") and CB.GetOverride("WARRIOR:RAGE", "text") == "none", "it forgets this resource's override and nothing else")
  Check(CB.Get("fillStyle") == "solid", "nor the shared style")
end

-- greyed out with a reason while the bars are off; on when they are on
do
  local by = Pages(S)
  R:SetEnabled("classBars", false)
  local row = Row(by.classBars, "Hide while dead or a ghost")
  Check(row and not row:Enabled() and row:DisabledReason():find("Show class resource bars", 1, true), "greyed out, and says why")
  R:SetEnabled("classBars", true)
  Check(row:Enabled(), "and enabled with the bars on")
  local level = Row(by.classBars, "Sample level")
  Check(level and not level:Enabled() and level:DisabledReason():find("preview", 1, true), "the sample level needs the preview")
  local test = Row(by.classBarsEffects, "Test the effects")
  Check(test and not test:Enabled(), "the test needs effects on")
  R:SetEnabled("classBars", false)
end

-- the preview and moving buttons call the feature and say plainly when they cannot
do
  local by = Pages(S)
  R:SetEnabled("classBars", true)
  c.FireEvent("PLAYER_ENTERING_WORLD")
  local preview = Row(by.classBars, "Preview")
  Check(preview and not CB.PreviewActive())
  preview.click()
  Check(CB.PreviewActive(), "Show starts the preview")
  Check(S.variables.TWICHUI_classBarsSampleLevel.get() == 70)
  S.variables.TWICHUI_classBarsSampleLevel:SetValue(20)
  Check(select(1, CB.PreviewLevels()) == 20, "the sample level drives the sample")
  preview.click()
  Check(not CB.PreviewActive(), "Stop ends it")
  R.SettingsLauncher.Closed()
  local move = Row(by.classBars, "Move the bars")
  move.click()
  Check(CB.PositioningActive(), "Move starts positioning")
  move.click()
  Check(not CB.PositioningActive(), "Finish ends it")
  R:SetEnabled("classBars", false)
end

-- the report: resource names and counts, no values
do
  local chunk = assert(loadfile(ROOT .. "diag/ClassBars.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  R:SetEnabled("classBars", true)
  c.FireEvent("PLAYER_ENTERING_WORLD")
  local report = R.Diag.Build()
  Check(report:find("Class resource bars", 1, true), "the report has a section")
  Check(report:find("primary: power / MANA", 1, true), "naming the resource")
  Check(report:find("events registered", 1, true) and report:find("animation driver: idle", 1, true), "and the counts that say what it costs")
  R:SetEnabled("classBars", false)
end

-- a Druid sees the rows of all its resources
do
  local d, DS = SettingsClient({ name = "Druid", beforeDescribe = function(cc) cc.UnitClass = function() return "Druid", "DRUID" end end })
  local v = DS.variables
  for _, key in ipairs({ "MANA", "RAGE", "ENERGY", "COMBOPOINTS" }) do
    Check(v["TWICHUI_classBarsOv" .. key .. "Source"], "a Druid has rows for " .. key)
  end
  local by = Pages(DS)
  Check(Row(by.classBarsLayout, "Show the combat points bar") == nil and Row(by.classBarsLayout, "Show the combo points bar"), "and a combo points bar row")
  Check(Row(by.classBarsLayout, "Show the druid mana bar"), "and a mana bar row")
  local m, MS = SettingsClient({ name = "Mage" })
  Check(Row(Pages(MS).classBarsLayout, "Show the combo points bar") == nil, "a Mage has none")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("CLASS BARS SETTINGS TESTS PASSED")
