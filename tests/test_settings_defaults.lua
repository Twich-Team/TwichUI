dofile(TESTS .. "harness.lua")
-- The options panel's Defaults button must put every toggle back to what a
-- new install gets: the opt-in channels and group check stay off.
local c = MakeClient("Rich", {"!!!TwichUI"})
local defaults = {}
c.Settings = {
  RegisterVerticalLayoutCategory = function() return {GetID = function() return 1 end}, {AddInitializer = function() end} end,
  RegisterAddOnSetting = function(_, _, key, tbl, _, _, default)
    assert(tbl == c.TwichUIDB.modules, "settings write to the saved modules table")
    defaults[key] = default
    return {}
  end,
  CreateCheckbox = function() end,
  RegisterAddOnCategory = function() end,
}
local chunk = assert(loadfile(ROOT .. "Settings.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local n = 0
for key, default in pairs(defaults) do
  n = n + 1
  assert(default == c.TwichUI.DEFAULT_MODULES[key], key .. " default matches a new install")
end
assert(n == 12, "every module has a toggle: " .. n)
assert(defaults.shareGroup == false and defaults.shareGuild == false and defaults.groupCheck == false, "opt-in stays off")
assert(defaults.media == true and defaults.shareWhisper == true)
print("SETTINGS DEFAULTS TESTS PASSED")
