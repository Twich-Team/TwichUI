dofile(TESTS .. "harness.lua")
-- The options panel's Defaults button must put every toggle back to what a
-- new install gets: the opt-in channels and group check stay off.
-- Also: advanced options hide behind one remembered switch, gear options
-- read and write the gear preferences, and skins report their status.
local c = MakeClient("Rich", {"!!!TwichUI", "Attune"})
local defaults, initializers, proxies, dropdowns = {}, {}, {}, {}
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
  RegisterVerticalLayoutCategory = function() return {GetID = function() return 1 end}, {AddInitializer = function() end} end,
  RegisterAddOnSetting = function(_, variable, key, tbl, _, name, default)
    if tbl == c.TwichUIDB.modules then defaults[key] = default
    else assert(variable == "TWICHUI_showAdvanced" and tbl == c.TwichUIDB.ui and default == false, "only the advanced switch lives elsewhere") end
    return {name = name, SetValueChangedCallback = function(self, fn) self.changed = fn end}
  end,
  RegisterProxySetting = function(_, variable, varType, name, default, get, set)
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
  RegisterCanvasLayoutSubcategory = function() return {GetID = function() return 2 end} end,
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
assert(n == 27, "every module has a toggle: " .. n)
assert(defaults.arrival == true and defaults.arrivalSubzones == true and defaults.arrivalReducedMotion == false,
  "arrival card and subzone cards on; reduced motion opt-in")
assert(defaults.shareGroup == false and defaults.shareGuild == false and defaults.groupCheck == true, "group sharing opt-in stays off; group check is on")
assert(defaults.media == true and defaults.shareWhisper == true)
assert(defaults.chronicle == true and defaults.chronicleChat == true, "Chronicle and its chat line are on by default")
assert(defaults.chronicleDeaths == false, "death entries are opt-in")

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

print("SETTINGS DEFAULTS TESTS PASSED")
