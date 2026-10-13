dofile(TESTS .. "harness.lua")
-- The settings window is its own addon, loaded on demand (TwichUI_Settings). Without it ever loading:
--   * switches still do what they do: R:SetEnabled runs the feature's update once, and only on a change;
--   * a profile change still updates every feature whose switch changed;
--   * a reload a switch needs is still asked about (the window isn't there to show it);
-- and when it can't load, R:OpenSettings says why, in plain words, and nothing breaks.

local c = MakeClient("Rich", {"!!!TwichUI"})
c.StaticPopupDialogs = {}
local asked = 0
c.StaticPopup_Show = function(key) if key == "TWICHUI_RELOAD" then asked = asked + 1 end end
c.said = {}
c.print = function(s) c.said[#c.said + 1] = tostring(s) end
local loads = 0
c.C_AddOns.LoadAddOn = function(name) loads = loads + 1; return false, "DISABLED" end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN")
local R = c.TwichUI
assert(R.Switches and R.SettingsLauncher and not R.SettingsUI and not R.SettingsKit, "only the core is loaded")
assert(loads == 0, "nothing tries to load the settings at login")

-- a feature's update, through the registry
local refreshed = 0
R.Arrival = { Refresh = function() refreshed = refreshed + 1 end }
R:SetEnabled("arrival", false)
assert(refreshed == 1 and c.TwichUIDB.modules.arrival == false, "turned off: one update")
R:SetEnabled("arrival", false)
assert(refreshed == 1, "the same value again: no update")
R:SetEnabled("arrival", true, true)
assert(refreshed == 1 and c.TwichUIDB.modules.arrival == true, "already applied by the caller: recorded only")

-- a reload switch: asked once when it differs from load, not when it goes back
R:SetEnabled("groupCheck", false)
assert(asked == 1 and R.Switches.ReloadPending())
R:SetEnabled("groupCheck", true)
assert(asked == 1 and not R.Switches.ReloadPending(), "back to what loaded: nothing to reload for")

-- a profile change follows every switch without the settings window
local PF = R.Profiles
R:SetEnabled("arrival", false)
refreshed = 0
local ok, code, info = PF.Create("Fresh")   -- a new profile has arrival on (its default)
assert(ok and code == "create", tostring(code))
assert(c.TwichUIDB.modules.arrival == true and refreshed == 1, "the feature followed the profile: " .. refreshed)
assert(#info.failed == 0, "nothing failed: " .. table.concat(info.failed, ", "))
assert(not R.SettingsUI and loads == 0, "and the settings never loaded")

-- can't load: said once per try, in plain words; nothing else changes
local said = #c.said
local opened, why = R:OpenSettings("chronicle")
assert(opened == false and why == "DISABLED" and loads == 1)
assert(c.said[said + 1] and c.said[said + 1]:find("turned off in your AddOns list", 1, true), tostring(c.said[said + 1]))
c.C_AddOns.LoadAddOn = function() return false, "MISSING" end
R:OpenSettings()
assert(c.said[#c.said]:find("TwichUI_Settings, is missing", 1, true), c.said[#c.said])
-- loaded but broken (its files failed): explained too
c.C_AddOns.LoadAddOn = function() return true end
assert(select(2, R:OpenSettings()) == "INCOMPLETE")
assert(R.SettingsLauncher.Snapshot().failed == "INCOMPLETE", "the troubleshooting report has it")
-- the compartment's right-click and the slash command go the same way
TwichUI_OnCompartmentClick = c.TwichUI_OnCompartmentClick
c.TwichUI_OnCompartmentClick(nil, "RightButton")
c.SlashCmdList.TWICHUI("options")
assert(R.SettingsLauncher.attempts == 5, "every launcher goes through R:OpenSettings: " .. R.SettingsLauncher.attempts)
print("PASSED")
