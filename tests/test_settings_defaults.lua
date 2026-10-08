dofile(TESTS .. "harness.lua")
-- The options panel's Defaults button must put every toggle back to what a
-- new install gets: the opt-in channels and group check stay off.
-- Also: advanced options hide behind one remembered switch, gear options
-- read and write the gear preferences, and skins report their status.
local c = MakeClient("Rich", {"!!!TwichUI", "Attune"})
local defaults, initializers, proxies, dropdowns = {}, {}, {}, {}
local pageOrder, variables = {}, {}   -- variables[name] = the page it was registered on
local function Initializer(name, tooltip)
  local i = {data = {name = name, tooltip = tooltip}, shown = {}, modify = {}}
  function i:AddShownPredicate(fn) table.insert(self.shown, fn) end
  function i:AddModifyPredicate(fn) table.insert(self.modify, fn) end
  function i:SetParentInitializer(parent, fn) self.parent = parent; if fn then table.insert(self.modify, fn) end end
  function i:Shown() for _, fn in ipairs(self.shown) do if not fn() then return false end end return true end
  table.insert(initializers, i)
  return i
end
c.CreateSettingsListSectionHeaderInitializer = function(name, tooltip) return Initializer(name, tooltip) end
c.CreateSettingsButtonInitializer = function(name, _, click, tooltip) local i = Initializer(name, tooltip); i.click = click; return i end
c.Settings = {
  VarType = {Boolean = "boolean", String = "string", Number = "number"},
  RegisterVerticalLayoutCategory = function(name) return {GetID = function() return 1 end, name = name}, {AddInitializer = function() end} end,
  RegisterVerticalLayoutSubcategory = function(parent, name)
    assert(parent.name == "TwichUI", "pages sit directly under TwichUI")
    table.insert(pageOrder, name)
    local id = #pageOrder + 10
    return {GetID = function() return id end, name = name}, {AddInitializer = function() end}
  end,
  RegisterAddOnSetting = function(category, variable, key, tbl, _, name, default)
    assert(not variables[variable], variable .. " is registered once")
    variables[variable] = category.name
    if tbl == c.TwichUIDB.modules then defaults[key] = default
    else assert(variable == "TWICHUI_showAdvanced" and tbl == c.TwichUIDB.ui and default == false, "only the advanced switch lives elsewhere") end
    return {name = name, SetValueChangedCallback = function(self, fn) self.changed = fn end}
  end,
  RegisterProxySetting = function(category, variable, varType, name, default, get, set)
    assert(not variables[variable], variable .. " is registered once")
    variables[variable] = category.name
    local s = {variable = variable, varType = varType, name = name, default = default, get = get, set = set}
    s.SetValue = function(self, value) self.set(value) end
    proxies[variable] = s
    return s
  end,
  CreateSliderOptions = function(min, max, step) return { min = min, max = max, step = step } end,
  CreateSlider = function(_, setting, options, tooltip) local i = Initializer(setting.name, tooltip); i.setting = setting; i.options = options; return i end,
  CreateColorSwatch = function(_, setting, tooltip) local i = Initializer(setting.name, tooltip); i.setting = setting; i.swatch = true; return i end,
  CreateCheckbox = function(_, setting, tooltip) local i = Initializer(setting.name, tooltip); i.setting = setting; return i end,
  CreateDropdown = function(_, setting, options, tooltip) local i = Initializer(setting.name, tooltip); i.setting = setting; dropdowns[setting.variable] = options; return i end,
  CreateControlTextContainer = function()
    local data = {}
    return {Add = function(_, value, label, tip) table.insert(data, {value = value, label = label, tooltip = tip}) end, GetData = function() return data end}
  end,
  RegisterCanvasLayoutSubcategory = function(parent, _, name) assert(parent.name == "Gear comparison" and name == "Stat weights") return {GetID = function() return 2 end} end,
  OpenToCategory = function(id) c.opened = id end,
  RegisterAddOnCategory = function() end,
}
c.UnitClass = function() return "Mage", "MAGE" end
c.UnitLevel = function() return 30 end
c.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return nil end }
local function Obj()
  return setmetatable({}, {__index = function(t, k)
    if k == "twichBevel" or k == "twichBorders" then return nil end   -- a field TwichUI sets itself, not a method
    if k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return Obj() end end
    return function() end
  end})
end
c.CreateFrame = function() return Obj() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function() end
for _, f in ipairs({ "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
  "gear/Hints.lua", "gear/Tooltip.lua", "gear/Bags.lua", "gear/Window.lua", "modules/Notify.lua", "modules/Arrival.lua", "modules/Media.lua", "modules/FriendLogin.lua", "modules/Borders.lua", "modules/FoodDrink.lua",
  "modules/TrainingData.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/MageTravel.lua", "modules/MageConjure.lua",
  "qol/QoL.lua", "qol/Summons.lua", "qol/Resurrect.lua", "qol/ReleasePvP.lua", "qol/Duels.lua", "qol/QuickKeybind.lua", "Settings.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI

-- Every module toggle defaults to what a new install gets.
local n = 0
for key, default in pairs(defaults) do
  n = n + 1
  assert(default == R.DEFAULT_MODULES[key], key .. " default matches a new install")
end
assert(n == 42, "every module has a toggle: " .. n)
assert(defaults.arrival == true and defaults.arrivalSubzones == true and defaults.arrivalReducedMotion == false,
  "arrival card and subzone cards on; reduced motion opt-in")
assert(defaults.arrivalDungeons == true, "dungeon and raid arrival cards on by default")
assert(defaults.shareGroup == nil and defaults.shareGuild == nil and defaults.shareWhisper == nil, "the old per-channel switches are gone")
assert(defaults.groupCheck == true and defaults.media == true)
assert(defaults.chronicle == true and defaults.chronicleChat == true, "Chronicle and its chat line are on by default")
assert(defaults.chronicleDeaths == false, "death entries are opt-in")
assert(defaults.welcomeBack == true, "Welcome Back bookmark is on by default")
assert(defaults.foodDrink == false and defaults.foodDrinkFood == true and defaults.foodDrinkDrink == true, "Food and Drink buttons are opt-in")
assert(defaults.mageTravel == true and defaults.mageConjure == true, "the Mage launchers are on (they show only on a data bar)")
assert(defaults.auctionPosting == true, "Sell from Bags tab is on by default (it only searches when you pick an item)")
assert(defaults.trainingNotice == true, "new training card is on by default")
assert(defaults.friendLogin == true, "Battle.net friend login card is on by default")
assert(defaults.friendLoginSound == true, "the friend login chime is on by default")

-- Advanced options: hidden until the switch is on, then shown; essentials never hidden.
local advanced, visible = {}, {}
for _, i in ipairs(initializers) do
  if #i.shown > 0 then advanced[i.data.name] = i else visible[i.data.name] = true end
end
assert(c.TwichUIDB.ui.showAdvanced == false, "advanced starts hidden")
for name, i in pairs(advanced) do assert(not i:Shown(), name .. " hidden by default") end
c.TwichUIDB.ui.showAdvanced = true
for name, i in pairs(advanced) do assert(i:Shown(), name .. " shown with advanced on") end
for _, name in ipairs({"Upgrade hints in item tooltips", "Mark upgrades in my bags", "Weigh gear for", "Stat weights",
  "Configuration sharing", "Let friends send me addon configurations", "Hide addon welcome messages", "Show advanced options"}) do
  assert(visible[name], name .. " is visible by default")
end
for _, name in ipairs({"How big a gain counts", "Show the reasoning", "Bag mark style", "How long the zone card stays", "Send configurations by"}) do
  assert(advanced[name], name .. " is advanced")
end

-- Gear options read and write the gear preferences.
local P = R.GearPrefs
proxies.TWICHUI_gearStrictness.set("eager"); assert(P.Get("strictness") == "eager")
assert(proxies.TWICHUI_gearStrictness.get() == "eager")
proxies.TWICHUI_gearReveal.set("alt"); assert(P.Get("reveal") == "alt")
proxies.TWICHUI_gearBagStyle.set("badge"); assert(P.Get("bagStyle") == "badge")
proxies.TWICHUI_gearPossible.set(false); assert(P.Get("glancePossible") == false)
proxies.TWICHUI_gearFuture.set(false); assert(P.Get("futureLevels") == false)
assert(proxies.TWICHUI_gearTree.get() == 0, "automatic by default")
proxies.TWICHUI_gearTree.set(8); assert(P.TreeChoice() == 8)
proxies.TWICHUI_gearTree.set(0); assert(P.TreeChoice() == nil, "0 puts it back to automatic")
for variable, s in pairs(proxies) do
  if variable ~= "TWICHUI_gearTree" then
    assert(s.default ~= nil, variable .. " has a default")
  end
end
local trees = dropdowns.TWICHUI_gearTree()
assert(trees[1].value == 0 and #trees == 4, "automatic and the mage's three trees: " .. #trees)
assert(#dropdowns.TWICHUI_gearStrictness() == 3 and #dropdowns.TWICHUI_gearReveal() == 4 and #dropdowns.TWICHUI_gearBagStyle() == 3)

-- Zone arrival card: how long it stays, saved with the UI options.
local hold = proxies.TWICHUI_arrivalHold
assert(hold.default == "standard" and hold.get() == "standard", "standard by default")
hold.set("longer"); assert(c.TwichUIDB.ui.arrivalHold == "longer" and hold.get() == "longer")
assert(#dropdowns.TWICHUI_arrivalHold() == 4 and dropdowns.TWICHUI_arrivalHold()[3].tooltip == "Stays 4 seconds before fading away.")

-- Friend login chime: which game volume it follows, saved with the UI options; a button to hear it.
local channel = proxies.TWICHUI_friendLoginChannel
assert(channel and channel.default == "SFX" and channel.get() == "SFX", "Sound Effects by default")
channel.set("Master"); assert(c.TwichUIDB.ui.friendLoginChannel == "Master" and channel.get() == "Master")
local channels = dropdowns.TWICHUI_friendLoginChannel()
assert(#channels == 4 and channels[1].value == "SFX" and channels[4].value == "Master" and channels[2].tooltip:find("Dialog"), "four channels, each explained")
local heard = {}
c.PlaySoundFile = function(path, ch) heard[#heard + 1] = { path = path, channel = ch }; return true end
local hear, chime
for _, i in ipairs(initializers) do
  if i.data.name == "Hear the chime" then hear = i end
  if i.data.name == "Play a soft chime with it" then chime = i end
end
assert(hear and hear.click and chime, "a button to hear the chime, and a switch for it")
hear.click()
assert(#heard == 1 and heard[1].channel == "Master" and heard[1].path:find("TwichUI_Notification.mp3", 1, true), "plays the chime on the chosen channel")
assert(c.TwichUIDB.modules.friendLoginSound == true)
c.TwichUIDB.modules.friendLogin = false
assert(hear.parent and hear.modify[1]() == false and chime.modify[1]() == false, "greyed out while the friend card is off")
c.TwichUIDB.modules.friendLogin = true
assert(hear.modify[1]() == true)
assert(c.TwichUI.MediaSounds["TwichUI Notification"] == "TwichUI_Notification.mp3", "offered to other addons' sound lists too")

-- Notification previews: a visible section on the Notifications page. A sounds switch that is off unless chosen
-- and saved with the UI options, a button per display (only for the displays that exist), a sequence test and Clear.
local byName = {}
for _, i in ipairs(initializers) do if i.data.name then byName[i.data.name] = i end end
assert(byName["Notification previews"] and #byName["Notification previews"].shown == 0, "a visible section header")
local previewSounds = proxies.TWICHUI_previewSounds
assert(previewSounds and variables.TWICHUI_previewSounds == "Notifications", "on the Notifications page")
assert(previewSounds.default == false and previewSounds.get() == false, "silent unless chosen")
previewSounds.set(true); assert(c.TwichUIDB.ui.previewSounds == true and previewSounds.get() == true and R.Notify.PreviewSounds())
previewSounds.set(false); assert(c.TwichUIDB.ui.previewSounds == false and not R.Notify.PreviewSounds())
for _, name in ipairs({ "Zone arrival", "Friend login", "Test coordinated sequence", "Clear previews" }) do
  assert(byName[name] and byName[name].click and #byName[name].shown == 0, name .. " has a visible button")
end
assert(not byName["Training available"] and not byName["Chronicle welcome back"], "no button for a display that isn't there")
assert(byName["Zone arrival"].data.tooltip:find("made-up", 1, true) and byName["Friend login"].data.tooltip:find("No friend state", 1, true))
local ui = c.TwichUIDB.ui
local savedBefore = ui.arrivalHold .. tostring(ui.friendLoginChannel)
byName["Zone arrival"].click()
assert(R.Notify.State().active[1] == "arrival:preview", "the button shows the zone card as a preview")
byName["Clear previews"].click()
assert(#R.Notify.State().active == 0, "Clear previews takes it down")
byName["Test coordinated sequence"].click()
assert(R.Notify.State().active[1] == "arrival:sequence-arrival", "the sequence starts with the zone card")
byName["Clear previews"].click()
assert(#R.Notify.State().active == 0 and #R.Notify.State().waiting == 0)
assert(ui.arrivalHold .. tostring(ui.friendLoginChannel) == savedBefore and c.TwichUIDB.modules.arrival == true, "previews change no setting")

-- Skins: missing addons say so and can't be ticked; installed ones report status.
local attune, auctionator
for _, i in ipairs(initializers) do
  if i.data.name == "Attune" then attune = i end
  if i.data.name and i.data.name:find("^Auctionator") then auctionator = i end
end
assert(attune and #attune.modify == 0, "installed skin can be changed")
assert(auctionator.data.name:find("not installed"), "missing addon labelled")
assert(#auctionator.modify == 1 and auctionator.modify[1]() == false, "missing addon's skin greyed out")
assert(auctionator.data.tooltip:find("Status: .*Not installed"), auctionator.data.tooltip)
assert(type(attune.data.tooltip) == "string" and attune.data.tooltip:find("Status:"), "status in a plain-string tooltip")
c.TwichUIDB.modules.attuneSkin = false
attune.setting.changed()
assert(attune.data.tooltip:find("after reload"), "toggle change shows it needs a reload")

-- The overview links to one page per feature, in this order; every setting
-- is on exactly one page (registration above refuses a repeat).
assert(table.concat(pageOrder, ",") == "Gear comparison,Notifications,Quality of life,Food and drink,Mage,Journey Chronicle,Auction House,Addon skins,Configuration sharing", table.concat(pageOrder, ","))
for variable, page in pairs({
  TWICHUI_media = "TwichUI", TWICHUI_quietLogin = "TwichUI", TWICHUI_showAdvanced = "TwichUI", 
  TWICHUI_gearHints = "Gear comparison", TWICHUI_gearTree = "Gear comparison", TWICHUI_gearBagStyle = "Gear comparison",
  TWICHUI_arrival = "Notifications", TWICHUI_arrivalHold = "Notifications", TWICHUI_arrivalReducedMotion = "Notifications",
  TWICHUI_previewSounds = "Notifications", TWICHUI_trainingNotice = "Notifications", TWICHUI_friendLogin = "Notifications", TWICHUI_friendLoginSound = "Notifications", TWICHUI_friendLoginChannel = "Notifications",
  TWICHUI_chronicle = "Journey Chronicle", TWICHUI_chronicleClock = "Journey Chronicle", TWICHUI_chronicleSound = "Journey Chronicle", TWICHUI_welcomeBack = "Journey Chronicle",
  TWICHUI_auctionPosting = "Auction House",
  TWICHUI_qolSummons = "Quality of life", TWICHUI_qolSummonsFrom = "Quality of life", TWICHUI_qolSummonsWait = "Quality of life",
  TWICHUI_qolResurrect = "Quality of life", TWICHUI_qolResurrectCombat = "Quality of life", TWICHUI_qolReleasePvP = "Quality of life",
  TWICHUI_qolReleaseWait = "Quality of life", TWICHUI_qolDuels = "Quality of life", TWICHUI_qolDuelsFrom = "Quality of life",
  TWICHUI_qolDuelsToDeath = "Quality of life", TWICHUI_qolQuickKeybind = "Quality of life",
  TWICHUI_foodDrink = "Food and drink", TWICHUI_foodDrinkFood = "Food and drink", TWICHUI_foodDrinkDrink = "Food and drink",
  TWICHUI_mageTravel = "Mage", TWICHUI_mageTravelText = "Mage", TWICHUI_mageConjure = "Mage", TWICHUI_mageConjureText = "Mage",
  TWICHUI_attuneSkin = "Addon skins", TWICHUI_whatsTrainingSkin = "Addon skins",
  TWICHUI_setupSharing = "Configuration sharing", TWICHUI_shareTransport = "Configuration sharing",
}) do assert(variables[variable] == page, variable .. " is on " .. page .. ", not " .. tostring(variables[variable])) end
-- The Mage launchers' text choices read and write each launcher's own setting.
for variable, module in pairs({ TWICHUI_mageTravelText = R.MageTravel, TWICHUI_mageConjureText = R.MageConjure }) do
  local proxy = assert(proxies[variable], variable .. " is on the page")
  assert(proxy.default == module.DEFAULT_TEXT and proxy.get() == module.DEFAULT_TEXT, variable .. " default")
  proxy:SetValue("none")
  assert(module.TextChoice() == "none" and proxy.get() == "none", variable .. " saves")
end
assert(c.TwichUIDB.ui.mageTravelText == "none" and c.TwichUIDB.ui.mageConjureText == "none")
-- Food and Drink appearance: each control reads and writes the module's own setting; Reset restores them.
do
  local FD = R.FoodDrink
  for variable, key in pairs({ TWICHUI_foodDrinkSize = "size", TWICHUI_foodDrinkSpacing = "spacing", TWICHUI_foodDrinkLayout = "layout",
      TWICHUI_foodDrinkBorderSize = "borderSize", TWICHUI_foodDrinkBorderClass = "borderClass", TWICHUI_foodDrinkBorderColor = "borderColor",
      TWICHUI_foodDrinkZoom = "zoom", TWICHUI_foodDrinkShowCount = "showCount",
      TWICHUI_foodDrinkBorderTexture = "borderTexture", TWICHUI_foodDrinkBorderOpacity = "borderOpacity",
      TWICHUI_foodDrinkButtonOpacity = "buttonOpacity", TWICHUI_foodDrinkMouseover = "mouseover", TWICHUI_foodDrinkIdleOpacity = "idleOpacity" }) do
    local proxy = assert(proxies[variable], variable .. " is on the page")
    assert(variables[variable] == "Food and drink", variable)
    assert(proxy.default == FD.DEFAULTS[key] and proxy.get() == FD.DEFAULTS[key], key .. " starts at its default")
  end
  -- Prefer Mage-conjured food and water: a choice of items, so not part of the look Reset puts back
  local prefer = assert(proxies.TWICHUI_foodDrinkPreferConjured, "the preference is on the page")
  assert(variables.TWICHUI_foodDrinkPreferConjured == "Food and drink" and prefer.default == false and prefer.get() == false, "off by default")
  prefer.set(true); assert(FD.Get("preferConjured") == true and prefer.get() == true, "saves")
  local preferInit
  for _, i in ipairs(initializers) do if i.setting and i.setting.variable == "TWICHUI_foodDrinkPreferConjured" then preferInit = i end end
  assert(preferInit and #preferInit.modify == 1, "live only while the buttons are on")
  assert(preferInit.data.tooltip and preferInit.data.tooltip:find("even when an ordinary item restores more", 1, true), "the tooltip says what prefer means")
  local size = proxies.TWICHUI_foodDrinkSize
  size.set(41.4); assert(FD.Get("size") == 41 and size.get() == 41, "a slider value is kept as a whole number")
  size.set(500); assert(FD.Get("size") == 41, "out of range is refused")
  proxies.TWICHUI_foodDrinkBorderColor.set("ff102030"); assert(FD.Get("borderColor") == "ff102030")
  proxies.TWICHUI_foodDrinkLayout.set("vertical"); assert(FD.Get("layout") == "vertical")
  local sliders = 0
  for _, i in ipairs(initializers) do if i.options and i.setting.variable:find("^TWICHUI_foodDrink") then sliders = sliders + 1 end end
  assert(sliders == 7, "size, spacing, border thickness, border opacity, zoom, button opacity and idle opacity are sliders: " .. sliders)
  local textures = {}
  for _, o in ipairs(dropdowns.TWICHUI_foodDrinkBorderTexture()) do textures[o.value] = o.label end
  assert(textures.solid == "Solid" and textures["Blizzard Tooltip"], "Solid, then LibSharedMedia's borders")
  assert(textures.None == nil, "not LibSharedMedia's \"None\"")
  local labels = {}
  for _, o in ipairs(dropdowns.TWICHUI_foodDrinkLayout()) do labels[o.value] = true end
  assert(labels.horizontal and labels.vertical)
  local reset
  for _, i in ipairs(initializers) do if i.click and i.data.name == "Appearance" then reset = i end end
  assert(reset, "a Reset button")
  -- the idle opacity is only live while the mouseover fade is on
  local idle
  for _, i in ipairs(initializers) do if i.setting and i.setting.variable == "TWICHUI_foodDrinkIdleOpacity" then idle = i end end
  assert(idle and #idle.modify == 1, "the idle opacity depends on the fade")
  c.TwichUIDB.modules.foodDrink = true
  FD.Set("mouseover", false); assert(not idle.modify[1](), "greyed while the fade is off")
  FD.Set("mouseover", true); assert(idle.modify[1](), "live while it is on")
  c.TwichUIDB.modules.foodDrink = false
  reset.click()
  assert(FD.Get("size") == 36 and FD.Get("layout") == "horizontal" and FD.Get("borderColor") == FD.DEFAULTS.borderColor, "Reset puts the look back")
  assert(FD.Get("preferConjured") == true, "Reset leaves the preference alone")
  prefer.set(false)
end
-- Broker menu appearance: one shared section on the Mage page; each control reads and writes the
-- shared look; Reset puts back only that.
do
  local MS = R.MenuStyle
  local keys = { TWICHUI_brokerMenuBgTexture = "bgTexture", TWICHUI_brokerMenuBgColor = "bgColor", TWICHUI_brokerMenuBgOpacity = "bgOpacity",
    TWICHUI_brokerMenuBorderTexture = "borderTexture", TWICHUI_brokerMenuBorderSize = "borderSize",
    TWICHUI_brokerMenuBorderColor = "borderColor", TWICHUI_brokerMenuBorderOpacity = "borderOpacity" }
  local n = 0
  for variable, key in pairs(keys) do
    n = n + 1
    local proxy = assert(proxies[variable], variable .. " is on the page")
    assert(variables[variable] == "Mage", variable .. " is with the menus it styles")
    assert(proxy.default == MS.DEFAULTS[key] and proxy.get() == MS.DEFAULTS[key], key .. " starts at its default")
  end
  assert(n == 7)
  local headers = {}
  for _, i in ipairs(initializers) do if not i.setting and not i.click then headers[i.data.name] = true end end
  assert(headers["Broker menu appearance"], "a clearly named section")
  local sliders = {}
  for _, i in ipairs(initializers) do
    if i.options and keys[i.setting.variable] then sliders[keys[i.setting.variable]] = i.options end
  end
  assert(sliders.bgOpacity.min == 0 and sliders.bgOpacity.max == 100 and sliders.borderOpacity.max == 100
    and sliders.borderSize.min == 0 and sliders.borderSize.max == 16, "sensible ranges")
  local swatches = 0
  for _, i in ipairs(initializers) do if i.swatch and keys[i.setting.variable] then swatches = swatches + 1 end end
  assert(swatches == 2, "a color for each piece, and no alpha in either: opacity is its own control")

  proxies.TWICHUI_brokerMenuBgOpacity.set(35); assert(MS.Get("bgOpacity") == 35 and proxies.TWICHUI_brokerMenuBgOpacity.get() == 35)
  proxies.TWICHUI_brokerMenuBorderOpacity.set(60); assert(MS.Get("borderOpacity") == 60 and MS.Get("bgOpacity") == 35)
  proxies.TWICHUI_brokerMenuBorderSize.set(500); assert(MS.Get("borderSize") == 1, "out of range is refused")
  proxies.TWICHUI_brokerMenuBgColor.set("ff102030"); assert(MS.Get("bgColor") == "ff102030")
  proxies.TWICHUI_brokerMenuBorderTexture.set("Blizzard Dialog"); assert(MS.Get("borderTexture") == "Blizzard Dialog")
  proxies.TWICHUI_brokerMenuBgTexture.set("none"); assert(MS.Get("bgTexture") == "none")
  assert(c.TwichUIDB.ui.brokerMenu.bgTexture == "none", "saved by id")
  local function Options(variable)
    local ids = {}
    for i, o in ipairs(dropdowns[variable]()) do ids[i] = o.value end
    return ids
  end
  local bg, border = Options("TWICHUI_brokerMenuBgTexture"), Options("TWICHUI_brokerMenuBorderTexture")
  assert(bg[1] == "none" and bg[2] == "solid" and bg[3] == "Blizzard Tooltip", "None, Solid, then the game's own: " .. table.concat(bg, ","))
  assert(border[1] == "none" and border[2] == "solid" and border[3] == "Blizzard Tooltip")

  c.TwichUIDB.ui.mageTravelText = "none"
  c.TwichUIDB.ui.foodDrink = { size = 50 }
  local preview, reset
  for _, i in ipairs(initializers) do
    if i.click and i.data.name == "Preview" then preview = i end
    if i.click and i.data.name == "Menu appearance" then reset = i end
  end
  assert(preview and reset, "a preview and a reset")
  preview.click(); preview.click()   -- shows and puts away without error
  reset.click()
  assert(c.TwichUIDB.ui.brokerMenu == nil, "Reset forgets the saved appearance")
  for _, key in pairs(keys) do assert(MS.Get(key) == MS.DEFAULTS[key], key .. " is back to its default") end
  assert(c.TwichUIDB.ui.mageTravelText == "none" and c.TwichUIDB.ui.foodDrink.size == 50, "Reset leaves everything else alone")
end
assert(R.settingsCategories.chronicle and R.settingsCategories.sharing and R.settingsCategories.overview == R.settingsCategory)
R:OpenSettings("chronicle"); assert(c.opened == R.settingsCategories.chronicle:GetID(), "opens a named page")
R:OpenSettings(); assert(c.opened == R.settingsCategory:GetID(), "opens the overview by default")

-- Overview rows: status text follows the toggles, and each opens its page.
local rows = {}
for _, i in ipairs(initializers) do if i.click and i.data.name:find("%s%s%s") then rows[i.data.name:match("^(.-)%s%s%s")] = i end end
assert(not rows["Zone arrival"], "the zone card no longer has a row of its own")
local zone = assert(rows["Notifications"], "overview has one Notifications row")
assert(zone.data.name:find("3 of 3 on"), zone.data.name)
c.TwichUIDB.modules.arrival = false
c.TwichUIDB.modules.attuneSkin = true
-- a toggle change refreshes the status
local arrivalToggle; for _, i in ipairs(initializers) do if i.setting and i.setting.name == "Show a title card when I arrive in a new zone" then arrivalToggle = i end end
arrivalToggle.setting.changed()
assert(zone.data.name:find("2 of 3 on"), zone.data.name)
c.TwichUIDB.modules.trainingNotice, c.TwichUIDB.modules.friendLogin = false, false
arrivalToggle.setting.changed()
assert(zone.data.name:find("Off"), "all three off: " .. zone.data.name)
zone.click(); assert(c.opened == R.settingsCategories.notifications:GetID(), "row opens the Notifications page")
assert(not R.settingsCategories.arrival, "no separate zone arrival page")
assert(rows["Addon skins"].data.name:find("of") or rows["Addon skins"].data.name:find("None installed"), rows["Addon skins"].data.name)


-- Quality of life: everything is opt-in, there is no "requested invites" row (the game's interface
-- for it isn't in Forever), choices read and write the saved options, and the waits are advanced.
for _, key in ipairs({ "qolSummons", "qolResurrect", "qolResurrectCombat", "qolReleasePvP", "qolDuels", "qolDuelsToDeath", "qolQuickKeybind" }) do
  assert(defaults[key] == false, key .. " is off by default")
end
for variable in pairs(variables) do assert(not variable:lower():find("invite"), variable .. ": no invite setting") end
local Q = R.QoL
assert(proxies.TWICHUI_qolSummonsFrom.get() == "known" and proxies.TWICHUI_qolDuelsFrom.get() == "known")
proxies.TWICHUI_qolSummonsFrom.set("group"); assert(Q.Get("summonsFrom") == "group" and proxies.TWICHUI_qolSummonsFrom.get() == "group")
proxies.TWICHUI_qolSummonsFrom.set("bogus"); assert(Q.Get("summonsFrom") == "group", "an unlisted choice is refused")
proxies.TWICHUI_qolDuelsFrom.set("nobody"); assert(Q.Get("duelsFrom") == "nobody")
proxies.TWICHUI_qolSummonsWait.set(5); assert(Q.Get("summonsWait") == 5)
proxies.TWICHUI_qolReleaseWait.set(0); assert(Q.Get("releaseWait") == 0)
assert(#dropdowns.TWICHUI_qolSummonsFrom() == 3 and #dropdowns.TWICHUI_qolDuelsFrom() == 4)
assert(dropdowns.TWICHUI_qolSummonsWait()[1].label == "Don't wait" and dropdowns.TWICHUI_qolSummonsWait()[2].label == "1 second")
assert(proxies.TWICHUI_qolSummonsFrom.default == "known" and proxies.TWICHUI_qolSummonsWait.default == 3 and proxies.TWICHUI_qolReleaseWait.default == 2)
c.TwichUIDB.ui.showAdvanced = false
for _, name in ipairs({ "Wait before accepting a summon", "Wait before releasing" }) do assert(advanced[name], name .. " is advanced") end
for _, name in ipairs({ "Accept summons", "Accept resurrection", "Release in battlegrounds", "Decline duel requests" }) do
  assert(visible[name], name .. " is visible by default")
end
-- Turning a switch on or off starts and stops its listening, with no reload.
local summonToggle; for _, i in ipairs(initializers) do if i.setting and i.setting.name == "Accept summons" then summonToggle = i end end
c.TwichUIDB.modules.qolSummons = true; summonToggle.setting.changed(); assert(R.frame.events.CONFIRM_SUMMON, "listening once on")
c.TwichUIDB.modules.qolSummons = false; summonToggle.setting.changed(); assert(not R.frame.events.CONFIRM_SUMMON, "and not once off")
-- The overview row follows the switches.
local qolRow = assert(rows["Quality of life"], "overview has a Quality of life row")
assert(qolRow.data.name:find("Off"), qolRow.data.name)
c.TwichUIDB.modules.qolDuels, c.TwichUIDB.modules.qolReleasePvP = true, true; summonToggle.setting.changed()
assert(qolRow.data.name:find("2 of 5 on"), qolRow.data.name)
qolRow.click(); assert(c.opened == R.settingsCategories.qol:GetID(), "row opens the Quality of life page")
-- Leatrix Plus overlap shows in the tooltip, and leaves its settings alone.
c.C_AddOns.IsAddOnLoaded = function(n) return n == "Leatrix_Plus" end
c.LeaPlusDB = { AutoAcceptSummon = "On" }
summonToggle.setting.changed()
assert(summonToggle.data.tooltip:find("Leatrix Plus also has this turned on"), "overlap note")
c.LeaPlusDB.AutoAcceptSummon = "Off"; summonToggle.setting.changed()
assert(not summonToggle.data.tooltip:find("Leatrix"), "no note when Leatrix has it off")

print("SETTINGS DEFAULTS TESTS PASSED")
