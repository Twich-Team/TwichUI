dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- The settings' shared behaviour (TwichUI_Settings/Kit.lua, Switches.lua) and the update paths it calls:
--   * a page that fails to describe does not take the other pages, or the AddOns launcher, with it;
--   * a switch acts only when its value changes, and asks to reload only when the value differs from the one
--     the UI loaded with; R:SetEnabled goes the same way;
--   * a Reset forgets the look in one go (one redraw) and each control shows its value again;
--   * the same value again redraws nothing;
--   * the features' own setters refuse what they can't use;
--   * nothing is marked Advanced or hidden behind a preference; the old "Show advanced options" is gone;
--   * nothing on the settings pages, Reset buttons and "Reset this page" included, touches map pins.

local errors = {}
local harnessHandler
local c, S = SettingsClient({ beforeDescribe = function(c)
  -- a page whose build fails, between two that work
  c.TwichUI.SettingsKit.Page({ key = "broken", name = "Broken page", order = 15, group = "everyday", build = function() error("boom") end })
  harnessHandler = c.geterrorhandler
  c.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
end })
c.geterrorhandler = harnessHandler   -- from here on, any error fails the test as usual
local R, K = c.TwichUI, c.TwichUI.SettingsKit

local function Page(name)
  for _, cat in ipairs(S.pages) do if cat.name == name then return cat end end
end
local function Row(pageName, label, kind)
  for _, i in ipairs(Page(pageName).rows) do
    local name = i:GetName() or ""
    if (not kind or i.kind == kind) and (name == label or name:find("^" .. label:gsub("%p", "%%%0") .. "   ")) then return i end
  end
end

-- 1. One broken page: reported, and everything else is there.
assert(#errors == 1 and errors[1]:find("boom", 1, true), "the failure is reported: " .. table.concat(errors, " | "))
assert(S.registered() and S.registered().name == "TwichUI", "TwichUI is still added to the AddOns list")
assert(Page("Broken page") and K.pages.broken.failed, "the broken page's place is kept, and it says so")
for _, name in ipairs({ "Gear comparison", "Notifications", "Party pins", "Configuration sharing" }) do
  assert(#Page(name).rows > 0, name .. " is built")
end
assert(Row("TwichUI", "Reduce window motion") and not Row("TwichUI", "Notifications", "link"), "the overview is built, and lists no features")
assert(not Row("TwichUI", "Show advanced options") and not S.variables.TWICHUI_showAdvanced, "the advanced-options switch is gone")

-- 2. Switches act only on a real change.
local arrival = S.variables.TWICHUI_arrival
local refreshed = 0
local refresh = R.Arrival.Refresh
R.Arrival.Refresh = function(...) refreshed = refreshed + 1; return refresh(...) end
arrival:SetValue(true)
assert(refreshed == 0, "the value it already has: no update")
arrival:SetValue(false)
assert(refreshed == 1 and c.TwichUIDB.modules.arrival == false, "a real change: one update")
arrival:SetValue(false); arrival:NotifyUpdate()
assert(refreshed == 1, "again, or only told to show its value: no update")
arrival:SetValueToDefault()
assert(refreshed == 2 and c.TwichUIDB.modules.arrival == true, "Defaults changed it back: one update")
-- the overview's status still follows a change made elsewhere (cheap, and nothing in the feature runs)
local notifications = { status = K.pages.notifications.def.overview.status }
c.TwichUIDB.modules.trainingNotice = false
arrival:NotifyUpdate()
assert(notifications.status():find("2 of 3 on", 1, true), notifications.status())
assert(refreshed == 2)
c.TwichUIDB.modules.trainingNotice = true

-- Reload: asked only when the value differs from the one the UI loaded with.
local skin = S.variables.TWICHUI_attuneSkin
local asked = S.popups
skin:SetValue(true)
assert(S.popups == asked, "unchanged: not asked")
skin:SetValue(false)
assert(S.popups == asked + 1, "changed from what loaded: asked once")
skin:SetValue(true)
assert(S.popups == asked + 1, "back to what loaded: nothing to reload for")
assert(Row("Addon skins", "Attune"):GetTooltip():find("Status:", 1, true), "the skin's status is still written")

-- R:SetEnabled: through the checkbox. alreadyApplied: the caller did the work; only the status follows.
asked = S.popups
R:SetEnabled("groupCheck", false, true)
assert(c.TwichUIDB.modules.groupCheck == false and S.popups == asked, "set, no prompt, nothing run twice")
S.variables.TWICHUI_groupCheck:SetValue(true)
assert(S.popups == asked, "back to what loaded")
S.variables.TWICHUI_groupCheck:SetValue(false)
assert(S.popups == asked + 1, "and the checkbox is judged against the right value")
S.variables.TWICHUI_groupCheck:SetValue(true)
R:SetEnabled("arrival", false)
assert(refreshed == 3 and c.TwichUIDB.modules.arrival == false, "without alreadyApplied the feature's update runs once")
R:SetEnabled("arrival", true)

-- 3. Reset: one redraw, each control told once, nothing else touched.
local MS = R.MenuStyle
local redraws = 0
MS.Subscribe(function() redraws = redraws + 1 end)
S.variables.TWICHUI_brokerMenuBgOpacity:SetValue(40)
S.variables.TWICHUI_brokerMenuBorderOpacity:SetValue(50)
assert(redraws == 2 and c.TwichUIDB.ui.brokerMenu.bgOpacity == 40)
S.variables.TWICHUI_brokerMenuBgOpacity:SetValue(40)
MS.Set("bgOpacity", 40)
assert(redraws == 2, "the same value again redraws nothing")
c.TwichUIDB.ui.mageTravelText = "none"
for _, s in ipairs(S.list) do s.notified = 0 end
redraws = 0
Row("Mage", "Menu appearance", "button").click()
assert(redraws == 1, "Reset redraws once: " .. redraws)
assert(c.TwichUIDB.ui.brokerMenu == nil and MS.Get("bgOpacity") == MS.DEFAULTS.bgOpacity, "the look is forgotten")
for _, suffix in ipairs({ "BgTexture", "BgColor", "BgOpacity", "BorderTexture", "BorderSize", "BorderColor", "BorderOpacity" }) do
  assert(S.variables["TWICHUI_brokerMenu" .. suffix].notified == 1, suffix .. "'s control is told once")
end
assert(c.TwichUIDB.ui.mageTravelText == "none", "nothing else is touched")

-- Food and Drink's look Reset keeps the place and the conjured preference.
local FD = R.FoodDrink
FD.Set("size", 50); FD.Set("preferConjured", true)
c.TwichUIDB.ui.foodDrinkPosition = { x = 3, y = 4 }
Row("Food and drink", "Appearance", "button").click()
assert(FD.Get("size") == FD.DEFAULTS.size and FD.Get("preferConjured") == true and c.TwichUIDB.ui.foodDrinkPosition.x == 3)
FD.Set("preferConjured", false)

-- 4. The timer bars switch's tooltip is read when shown, so it follows the skin's own switch.
local timers = Row("RestedXP guide window", "Skin timer bars")
c.TwichUIDB.modules.restedxpSkin = false
assert(timers:GetTooltip():find("Greyed out", 1, true) and timers:GetTooltip():find("Status:", 1, true))
c.TwichUIDB.modules.restedxpSkin = true
assert(not timers:GetTooltip():find("Greyed out", 1, true) and timers:GetTooltip():find("Status:", 1, true), timers:GetTooltip())
c.TwichUIDB.modules.restedxpSkin = false

-- 5. The features' own setters, which the options use: an unusable value is refused, a usable one kept.
assert(R.Arrival.SetHoldChoice("bogus") == false and R.Arrival.HoldChoice() == "standard")
assert(R.Arrival.SetHoldChoice("long") and R.Arrival.HoldChoice() == "long" and c.TwichUIDB.ui.arrivalHold == "long")
assert(R.FriendLogin.SetSoundChannel("Loud") == false and R.FriendLogin.SoundChannel() == "SFX")
assert(R.FriendLogin.SetSoundChannel("Dialog") and c.TwichUIDB.ui.friendLoginChannel == "Dialog")
assert(R.Chronicle.SetClock("13") == false and R.Chronicle.Clock() == "12")
assert(R.Chronicle.SetClock("24") and R.Chronicle.Clock() == "24" and S.variables.TWICHUI_chronicleClock:GetValue() == "24")
R.Notify.SetPreviewSounds(1)
assert(c.TwichUIDB.ui.previewSounds == true and S.variables.TWICHUI_previewSounds:GetValue() == true)

-- 5b. Appearance pages sit under the page they belong to, with a pointer there; the switch keeps its page.
assert(Page("Chronicle appearance").parent == "Journey Chronicle" and Page("Pin appearance").parent == "Party pins")
assert(S.variables.TWICHUI_chronicleAccentColor.page == "Chronicle appearance" and S.variables.TWICHUI_chronicle.page == "Journey Chronicle")
assert(S.variables.TWICHUI_pinsLookBgColor.page == "Pin appearance" and S.variables.TWICHUI_partyPins.page == "Party pins")
Row("Journey Chronicle", "Chronicle appearance", "button").click()
assert(c.opened == "chronicleLook", "the Chronicle's pointer opens its appearance page")
Row("Party pins", "Pin appearance", "button").click()
assert(c.opened == "pinsLook", "and the pins' theirs")
c.TwichUIDB.modules.partyPins = false
assert(not Row("Pin appearance", "Accent color"):Enabled(), "the pins' look is greyed out while Party pins is off")
c.TwichUIDB.modules.partyPins = true

-- No Advanced mechanism: the rows that used to be behind it sit in the section of what they belong with.
assert(not K.Advanced and not K.AdvancedShown and not K.advancedPages, "the kit has no Advanced marking")
local strict = Row("Gear comparison", "How big a gain counts")
assert(strict.advanced == nil and strict.section:GetName() == "Upgrade hints", "plain, with the other upgrade hint settings")
assert(Row("Gear comparison", "Bag mark style").section:GetName() == "Bag marks" and Row("Gear comparison", "Bag mark style").parent:GetName() == "Mark upgrades in my bags")
for _, page in ipairs(K.list) do
  for _, row in ipairs(page.rows) do
    assert(row.advanced == nil, page.name .. ": " .. tostring(row:GetName()) .. " is not marked advanced")
    assert(row.kind == "header" or row.section, page.name .. ": " .. tostring(row:GetName()) .. " is in a section")
    assert(not (row.section and row.section:GetName() == "Advanced"), page.name .. " has no Advanced section")
  end
end
local resetTimers = Row("RestedXP guide window", "Reset timer bars")
assert(resetTimers.section:GetName() == "Timer bar background and border", "the timer bars' Reset ends the timer bars' sections")
local resetLook = Row("RestedXP guide window", "Reset appearance")
assert(resetLook.section:GetName() == "RestedXP guide window", "the look's Reset is with the switch it resets: " .. resetLook.section:GetName())

-- 6. Map pins: no setting, Reset or Defaults touches them, kept pins included.
c.C_Map = c.C_Map or {}
c.C_Map.GetMapInfo = function(id) return { mapID = id, name = "Map " .. id } end
local PN = R.Pins
assert(PN.AddLocal({ map = 1429, x = 1, y = 2, name = "Ordinary" }))
assert(PN.AddLocal({ map = 1429, x = 3, y = 4, name = "Kept", kept = true }))
local function Snapshot(t, out)
  out = out or {}
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = t[k] ~= nil and t[k] or t[tonumber(k)]
    if type(v) == "table" then out[#out + 1] = k .. "{"; Snapshot(v, out); out[#out + 1] = "}"
    else out[#out + 1] = k .. "=" .. tostring(v) end
  end
  return table.concat(out, ",")
end
local before = Snapshot(c.TwichUIDB.pins)
local chronicleBefore = Snapshot(c.TwichUIChronicleDB or {})
assert(chronicleBefore ~= "", "the Chronicle has entries to keep")
for _, cat in ipairs(S.pages) do
  for _, i in ipairs(cat.rows) do
    if i.kind == "button" and i.data.buttonText == "Reset" and i.click then i.click() end
  end
end
for _, page in ipairs(K.NavOrder()) do K.ResetPage(page.key) end
FlushTimers()
assert(Snapshot(c.TwichUIDB.pins) == before, "pins are as they were")
assert(Snapshot(c.TwichUIChronicleDB or {}) == chronicleBefore, "the Chronicle is as it was")
assert(#PN.LocalPins() == 2)

print("PASSED")
