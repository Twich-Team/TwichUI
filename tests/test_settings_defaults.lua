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
    proxies[variable] = s
    return s
  end,
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
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    return function() end
  end})
end
c.CreateFrame = function() return Obj() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function() end
for _, f in ipairs({ "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
  "gear/Hints.lua", "gear/Tooltip.lua", "gear/Bags.lua", "gear/Window.lua", "modules/Arrival.lua", "Settings.lua" }) do
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
assert(n == 31, "every module has a toggle: " .. n)
assert(defaults.arrival == true and defaults.arrivalSubzones == true and defaults.arrivalReducedMotion == false,
  "arrival card and subzone cards on; reduced motion opt-in")
assert(defaults.arrivalDungeons == true, "dungeon and raid arrival cards on by default")
assert(defaults.shareGroup == false and defaults.shareGuild == false and defaults.groupCheck == true, "group sharing opt-in stays off; group check is on")
assert(defaults.media == true and defaults.shareWhisper == true)
assert(defaults.chronicle == true and defaults.chronicleChat == true, "Chronicle and its chat line are on by default")
assert(defaults.chronicleDeaths == false, "death entries are opt-in")
assert(defaults.welcomeBack == true, "Welcome Back bookmark is on by default")
assert(defaults.auctionPosting == true, "Sell from Bags tab is on by default (it only searches when you pick an item)")
assert(defaults.trainingNotice == true, "new training card is on by default")

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
for _, name in ipairs({"How big a gain counts", "Show the reasoning", "Bag mark style", "How long the card stays", "Send over the group channel"}) do
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
assert(table.concat(pageOrder, ",") == "Gear comparison,Zone arrival,Journey Chronicle,Auction House,Addon skins,Configuration sharing", table.concat(pageOrder, ","))
for variable, page in pairs({
  TWICHUI_media = "TwichUI", TWICHUI_quietLogin = "TwichUI", TWICHUI_showAdvanced = "TwichUI", TWICHUI_trainingNotice = "TwichUI",
  TWICHUI_gearHints = "Gear comparison", TWICHUI_gearTree = "Gear comparison", TWICHUI_gearBagStyle = "Gear comparison",
  TWICHUI_arrival = "Zone arrival", TWICHUI_arrivalHold = "Zone arrival",
  TWICHUI_chronicle = "Journey Chronicle", TWICHUI_chronicleClock = "Journey Chronicle", TWICHUI_chronicleSound = "Journey Chronicle", TWICHUI_welcomeBack = "Journey Chronicle",
  TWICHUI_auctionPosting = "Auction House",
  TWICHUI_attuneSkin = "Addon skins", TWICHUI_whatsTrainingSkin = "Addon skins",
  TWICHUI_setupSharing = "Configuration sharing", TWICHUI_shareGuild = "Configuration sharing",
}) do assert(variables[variable] == page, variable .. " is on " .. page .. ", not " .. tostring(variables[variable])) end
assert(R.settingsCategories.chronicle and R.settingsCategories.sharing and R.settingsCategories.overview == R.settingsCategory)
R:OpenSettings("chronicle"); assert(c.opened == R.settingsCategories.chronicle:GetID(), "opens a named page")
R:OpenSettings(); assert(c.opened == R.settingsCategory:GetID(), "opens the overview by default")

-- Overview rows: status text follows the toggles, and each opens its page.
local rows = {}
for _, i in ipairs(initializers) do if i.click and i.data.name:find("%s%s%s") then rows[i.data.name:match("^(.-)%s%s%s")] = i end end
local zone = assert(rows["Zone arrival"], "overview has a Zone arrival row")
assert(zone.data.name:find("On"), zone.data.name)
c.TwichUIDB.modules.arrival = false
c.TwichUIDB.modules.attuneSkin = true
-- a toggle change refreshes the status
local arrivalToggle; for _, i in ipairs(initializers) do if i.setting and i.setting.name == "Show a title card when I arrive in a new zone" then arrivalToggle = i end end
arrivalToggle.setting.changed()
assert(zone.data.name:find("Off"), zone.data.name)
zone.click(); assert(c.opened == R.settingsCategories.arrival:GetID(), "row opens its page")
assert(rows["Addon skins"].data.name:find("of") or rows["Addon skins"].data.name:find("None installed"), rows["Addon skins"].data.name)

print("SETTINGS DEFAULTS TESTS PASSED")
