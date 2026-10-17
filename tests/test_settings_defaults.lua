dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Every switch's default is what a new install gets: the opt-in channels and group check stay off.
-- Also: nothing is hidden behind an advanced flag, gear options read and write the gear preferences, skins report
-- their status, each page reads and writes its feature's own settings, and its Reset puts back only its own.
-- The pages are TwichUI_Settings' descriptions (tests/settings_mock.lua); no window is drawn here.
local c, S = SettingsClient()
local R, K = c.TwichUI, S.K
local defaults, initializers, proxies, dropdowns, variables, pageOrder = {}, {}, {}, {}, {}, {}
for _, page in ipairs(K.list) do   -- (described order: by each page's place, the start page last)
  for _, row in ipairs(page.rows) do
    initializers[#initializers + 1] = row
    if row.kind == "swatch" then row.swatch = true end
    if row.setting and row.data.name == nil then row.data.name = row.setting.name end   -- (as the game's rows had it)
    if row.choices and row.setting then dropdowns[row.setting.variable] = row.choices end
  end
end
for name, s in pairs(K.variables) do
  variables[name] = s.page
  local key = s.kind:match("^switch:modules%.(.+)$")
  if key then
    defaults[key] = s.default
    s.changed = function() R.Switches.Sync() end   -- the value was put in TwichUIDB.modules: follow it, as a profile change does
  else
    s.changed = function() s:NotifyUpdate() end
  end
  if s.kind == "proxy" then proxies[name] = s end
end
for _, page in ipairs(K.NavOrder()) do
  if page.key ~= "overview" and not page.def.host then pageOrder[#pageOrder + 1] = page.name end
end
c.canvases = {}
for _, page in ipairs(K.list) do if page.def.host then c.canvases[page.name] = K.pages[page.parent].name end end
-- pages sit directly under TwichUI, except the appearance and addon pages, each under the page it belongs to
for _, page in ipairs(K.list) do
  local under = { ["RestedXP guide window"] = "Addon skins", ["SpeakStone speech frame"] = "Addon skins", ["Chronicle appearance"] = "Journey Chronicle",
    ["Pin appearance"] = "Party pins", ["Notification appearance"] = "Notifications", ["Stat weights"] = "Gear comparison", ["Refreshment shares"] = "Mage",
    ["Restock items"] = "Vendor restocking" }
  assert((page.parent and K.pages[page.parent].name) == under[page.name], page.name .. " is in its place")
end

-- Every module toggle defaults to what a new install gets.
local n = 0
for key, default in pairs(defaults) do
  n = n + 1
  assert(default == R.DEFAULT_MODULES[key], key .. " default matches a new install")
end
assert(n == 57, "every module has a toggle: " .. n)
assert(defaults.restedxpSkin == false, "the RestedXP skin is opt-in")
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
assert(defaults.mageRefreshments == false, "Mage refreshments are opt-in")
assert(defaults.mageRefreshmentsTrade == true, "its trade strip comes with it when it is turned on")
assert(defaults.mageRefreshmentsAutoFill == true, "and fills a group member's trade by itself")
assert(defaults.mageSell == false, "selling ordinary food and drink is opt-in")
assert(defaults.partyPins == true, "Party pins (map pins) are on for a new profile")
assert(defaults.mageSellFood == true and defaults.mageSellDrink == true and defaults.mageSellDryRun == true,
  "its kinds are on once it is, and it starts as a dry run")
assert(c.canvases["Stat weights"] == "Gear comparison" and c.canvases["Refreshment shares"] == "Mage", "the shares page sits under Mage")
assert(defaults.auctionPosting == true, "Sell from Bags tab is on by default (it only searches when you pick an item)")
assert(defaults.trainingNotice == true, "new training card is on by default")
assert(defaults.friendLogin == true, "Battle.net friend login card is on by default")
assert(defaults.friendLoginSound == true, "the friend login chime is on by default")

-- No setting sits behind an "advanced" flag: every row is drawn whenever its own feature conditions hold.
local visible = {}
for _, i in ipairs(initializers) do
  local name = i:GetName()
  if name then
    assert(i.advanced == nil, name .. " is not marked advanced")
    visible[name] = true
  end
end
assert(c.TwichUIDB.ui.showAdvanced == nil, "no advanced-options preference is kept")
assert(not proxies.TWICHUI_showAdvanced, "there is no 'Show advanced options' setting")
-- (the background's tiling rows also wait for an image background: checked with the Chronicle's below)
local IMAGE_ONLY = { ["Background tiling"] = true, ["Background tile size"] = true, ["Background inset"] = true,
  -- only while a card (not the shared look) is being edited in the notification appearance page
  ["Give this card its own look"] = true, ["Reset this card"] = true }
for _, i in ipairs(initializers) do
  local name = i:GetName()
  -- (a status line of the troubleshooting page is shown or folded away by whether its addon is there: test_status.lua)
  if name and i.kind ~= "header" and i.kind ~= "status" then assert(IMAGE_ONLY[name] or i:Shown(), name .. " is drawn") end
end
for _, name in ipairs({"Upgrade hints in item tooltips", "Mark upgrades in my bags", "Weigh gear for", "Stat weights",
  "Configuration sharing", "Let friends send me addon configurations", "Hide addon welcome messages",
  "How big a gain counts", "Show the reasoning", "Show possible upgrades too", "Hint at gear for higher levels",
  "Bag mark style", "How long the zone card stays", "Send configurations by"}) do
  assert(visible[name], name .. " is visible")
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
-- The Profiles page's choices have no default on purpose: the panel's Defaults button must never switch,
-- copy into or delete a profile.
local NO_DEFAULT = { TWICHUI_gearTree = true, TWICHUI_profileCurrent = true, TWICHUI_profileCopyFrom = true, TWICHUI_profileDelete = true }
-- So do the notification appearance settings: each one reads and writes whichever card (or the shared look) is
-- being edited, so a page-wide "Reset this page" would reset the wrong place. That page's own two Reset buttons
-- say exactly what they cover instead.
for variable in pairs(proxies) do
  if variable:find("^TWICHUI_notifyLook") then NO_DEFAULT[variable] = true end
end
for variable, s in pairs(proxies) do
  if NO_DEFAULT[variable] then
    if variable ~= "TWICHUI_gearTree" then assert(s.default == nil, variable .. " has no default") end
  else
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
local chimeSound = proxies.TWICHUI_friendLoginChime
assert(chimeSound and variables.TWICHUI_friendLoginChime == "Notifications", "a sound choice on the Notifications page")
assert(chimeSound.default == "TwichUI Notification" and chimeSound.get() == "TwichUI Notification", "the notification chime by default")
local chimeChoices = dropdowns.TWICHUI_friendLoginChime()
local chimeAt = {}
for i, choice in ipairs(chimeChoices) do chimeAt[choice.value] = i end
assert(chimeAt["TwichUI Notification"] and chimeAt["TwichUI Drums"] and chimeAt["TwichUI Map Pin"], "TwichUI's sounds are offered, the drums among them")
chimeSound.set("TwichUI Drums"); assert(c.TwichUIDB.ui.friendLoginChime == "TwichUI Drums" and chimeSound.get() == "TwichUI Drums")
chimeSound.set("TwichUI Notification")
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
assert(byName["Notification previews"] and not byName["Notification previews"].advanced, "a visible section header")
local previewSounds = proxies.TWICHUI_previewSounds
assert(previewSounds and variables.TWICHUI_previewSounds == "Notifications", "on the Notifications page")
assert(previewSounds.default == false and previewSounds.get() == false, "silent unless chosen")
previewSounds.set(true); assert(c.TwichUIDB.ui.previewSounds == true and previewSounds.get() == true and R.Notify.PreviewSounds())
previewSounds.set(false); assert(c.TwichUIDB.ui.previewSounds == false and not R.Notify.PreviewSounds())
for _, name in ipairs({ "Zone arrival", "Friend login", "Test coordinated sequence", "Clear previews" }) do
  assert(byName[name] and byName[name].click and not byName[name].advanced, name .. " has a visible button")
end
assert(not byName["Training available"] and not byName["Chronicle welcome back"], "no button for a display that isn't there")
assert(byName["Zone arrival"]:GetTooltip():find("made-up", 1, true) and byName["Friend login"]:GetTooltip():find("No friend state", 1, true))
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

-- Help: where to find the welcome and the commands. Both are visible buttons that change no setting.
do
  local welcomeRow, commandsRow = byName["Welcome"], byName["Chat commands"]
  assert(welcomeRow and welcomeRow.click and not welcomeRow.advanced and commandsRow and commandsRow.click, "Help buttons on the overview")
  assert(welcomeRow:GetTooltip():find("/tui about", 1, true) and welcomeRow:GetTooltip():find("changes nothing", 1, true))
  local modulesBefore = {}
  for k, v in pairs(c.TwichUIDB.modules) do modulesBefore[k] = v end
  commandsRow.click()   -- runs /tui help through the one parser
  local shown = 0
  R.Welcome = { Show = function() shown = shown + 1 end }
  welcomeRow.click()
  assert(shown == 1, "Show welcome reaches the dialog")
  R.Welcome = nil
  welcomeRow.click()   -- no dialog loaded: nothing to do, and no error
  for k, v in pairs(modulesBefore) do assert(c.TwichUIDB.modules[k] == v, "opening Help changes no setting: " .. k) end
end

-- Gear: nothing has to be entered, and the automatic tree is explained with where to override it.
do
  local gearHints, tree
  for _, i in ipairs(initializers) do
    if i.data.name == "Upgrade hints in item tooltips" then gearHints = i end
    if i.data.name == "Weigh gear for" then tree = i end
  end
  assert(gearHints and gearHints:GetTooltip():find("don't have to enter anything", 1, true), "says no setup is needed")
  assert(tree and tree:GetTooltip():find("override", 1, true) and tree:GetTooltip():find("tied", 1, true), "explains automatic detection and the override")
end

-- Skins: missing addons say so and can't be ticked; installed ones report status.
local attune, auctionator
for _, i in ipairs(initializers) do
  if i.data.name == "Attune" then attune = i end
  if i.data.name and i.data.name:find("^Auctionator") then auctionator = i end
end
assert(attune and #attune.modify == 0, "installed skin can be changed")
assert(auctionator.data.name:find("not installed"), "missing addon labelled")
assert(#auctionator.modify == 1 and auctionator.modify[1]() == false, "missing addon's skin greyed out")
assert(auctionator:GetTooltip():find("Status: .*Not installed"), auctionator.data.tooltip)
assert(type(attune:GetTooltip()) == "string" and attune:GetTooltip():find("Status:"), "status in a plain-string tooltip")
c.TwichUIDB.modules.attuneSkin = false
attune.setting.changed()
assert(attune:GetTooltip():find("after reload"), "toggle change shows it needs a reload")

-- The overview links to one page per feature, in this order; every setting
-- is on exactly one page (registration above refuses a repeat).
assert(table.concat(pageOrder, ",") == "Notifications,Notification appearance,Quality of life,Food and drink,Vendor restocking,Auction House,Journey Chronicle,Chronicle appearance,Party pins,Pin appearance,Gear comparison,Mage,Addon skins,RestedXP guide window,SpeakStone speech frame,Configuration sharing,Profiles,Troubleshooting", table.concat(pageOrder, ","))
for variable, page in pairs({
  TWICHUI_media = "TwichUI", TWICHUI_quietLogin = "TwichUI", 
  TWICHUI_gearHints = "Gear comparison", TWICHUI_gearTree = "Gear comparison", TWICHUI_gearBagStyle = "Gear comparison",
  TWICHUI_arrival = "Notifications", TWICHUI_arrivalHold = "Notifications", TWICHUI_arrivalReducedMotion = "Notifications",
  TWICHUI_previewSounds = "Notifications", TWICHUI_trainingNotice = "Notifications", TWICHUI_friendLogin = "Notifications", TWICHUI_friendLoginSound = "Notifications", TWICHUI_friendLoginChannel = "Notifications",
  TWICHUI_chronicle = "Journey Chronicle", TWICHUI_chronicleClock = "Journey Chronicle", TWICHUI_chronicleSound = "Journey Chronicle", TWICHUI_welcomeBack = "Journey Chronicle",
  TWICHUI_auctionPosting = "Auction House",
  TWICHUI_qolSummons = "Quality of life", TWICHUI_qolSummonsFrom = "Quality of life", TWICHUI_qolSummonsWait = "Quality of life",
  TWICHUI_qolResurrect = "Quality of life", TWICHUI_qolResurrectCombat = "Quality of life", TWICHUI_qolReleasePvP = "Quality of life",
  TWICHUI_qolReleaseWait = "Quality of life", TWICHUI_qolDuels = "Quality of life", TWICHUI_qolDuelsFrom = "Quality of life",
  TWICHUI_qolDuelsToDeath = "Quality of life", TWICHUI_qolQuickKeybind = "Quality of life", TWICHUI_qolEasyFishing = "Quality of life",
  TWICHUI_foodDrink = "Food and drink", TWICHUI_foodDrinkFood = "Food and drink", TWICHUI_foodDrinkDrink = "Food and drink",
  TWICHUI_mageTravel = "Mage", TWICHUI_mageTravelText = "Mage", TWICHUI_mageConjure = "Mage", TWICHUI_mageConjureText = "Mage", TWICHUI_mageRefreshments = "Mage", TWICHUI_mageRefreshmentsTrade = "Mage", TWICHUI_mageRefreshmentsAutoFill = "Mage", TWICHUI_refreshmentsTradeGives = "Mage", TWICHUI_refreshmentsText = "Mage",
  TWICHUI_mageSell = "Mage", TWICHUI_mageSellFood = "Mage", TWICHUI_mageSellDrink = "Mage", TWICHUI_mageSellDryRun = "Mage",
  TWICHUI_attuneSkin = "Addon skins", TWICHUI_whatsTrainingSkin = "Addon skins",
  TWICHUI_setupSharing = "Configuration sharing", TWICHUI_shareTransport = "Configuration sharing",
  TWICHUI_profileCurrent = "Profiles", TWICHUI_profileCopyFrom = "Profiles", TWICHUI_profileDelete = "Profiles",
}) do assert(variables[variable] == page, variable .. " is on " .. page .. ", not " .. tostring(variables[variable])) end
-- The Mage launchers' text choices read and write each launcher's own setting.
for variable, module in pairs({ TWICHUI_mageTravelText = R.MageTravel, TWICHUI_mageConjureText = R.MageConjure }) do
  local proxy = assert(proxies[variable], variable .. " is on the page")
  assert(proxy.default == module.DEFAULT_TEXT and proxy.get() == module.DEFAULT_TEXT, variable .. " default")
  proxy:SetValue("none")
  assert(module.TextChoice() == "none" and proxy.get() == "none", variable .. " saves")
end
assert(c.TwichUIDB.ui.mageTravelText == "none" and c.TwichUIDB.ui.mageConjureText == "none")
-- Party pins: the data bar entry's text, icon and color, and the menu's look, are on the Party pins page and
-- read and write the pins' own settings (not the window's or the Mage launchers').
do
  local BR, PL = R.PinsLook.Bar, R.PinsLook
  for variable, key in pairs({ TWICHUI_pinsBarText = "text", TWICHUI_pinsBarIcon = "icon",
      TWICHUI_pinsBarCustomColor = "customColor", TWICHUI_pinsBarColor = "color",
      TWICHUI_pinsBarFlash = "flash", TWICHUI_pinsBarFlashSeconds = "flashSeconds", TWICHUI_pinsBarFlashColor = "flashColor" }) do
    local proxy = assert(proxies[variable], variable .. " is on the page")
    assert(variables[variable] == "Party pins", variable)
    assert(proxy.default == BR.DEFAULTS[key] and proxy.get() == BR.DEFAULTS[key], key .. " starts at its default")
  end
  assert(BR.DEFAULTS.icon == true and BR.DEFAULTS.customColor == false and BR.DEFAULTS.text == "count",
    "as the entry has always been: the count, the icon, and the data bar's own color")
  proxies.TWICHUI_pinsBarText:SetValue("label")
  proxies.TWICHUI_pinsBarIcon:SetValue(false)
  proxies.TWICHUI_pinsBarCustomColor:SetValue(true)
  proxies.TWICHUI_pinsBarColor:SetValue("ff336699")
  assert(BR.Get("text") == "label" and BR.Get("icon") == false and BR.Get("customColor") == true and BR.Get("color") == "ff336699")
  assert(c.TwichUIDB.ui.pinsBroker.icon == false, "a chosen false is saved as a value")
  proxies.TWICHUI_pinsBarFlashSeconds:SetValue(15)
  proxies.TWICHUI_pinsBarFlashColor:SetValue("ff00aa44")
  proxies.TWICHUI_pinsBarFlash:SetValue(false)
  assert(BR.Get("flashSeconds") == 15 and BR.Get("flashColor") == "ff00aa44" and BR.Get("flash") == false)
  assert(BR.DEFAULTS.flash == true and BR.DEFAULTS.flashSeconds == 8, "pointed out for 8 seconds unless changed")
  BR.Reset()
  -- the arrival sound: on the Party pins page, in its own saved table
  do
    local SD = PL.Sound
    for variable, key in pairs({ TWICHUI_pinsSound = "enabled", TWICHUI_pinsSoundFile = "sound", TWICHUI_pinsSoundChannel = "channel" }) do
      local proxy = assert(proxies[variable], variable .. " is on the page")
      assert(variables[variable] == "Party pins", variable)
      assert(proxy.default == SD.DEFAULTS[key] and proxy.get() == SD.DEFAULTS[key], key .. " starts at its default")
    end
    assert(SD.DEFAULTS.enabled == true and SD.DEFAULTS.sound == "TwichUI Map Pin" and SD.DEFAULTS.channel == "SFX")
    proxies.TWICHUI_pinsSound:SetValue(false)
    proxies.TWICHUI_pinsSoundChannel:SetValue("Dialog")
    proxies.TWICHUI_pinsSoundFile:SetValue("GTFO Fail")
    assert(SD.Get("enabled") == false and SD.Get("channel") == "Dialog" and SD.Get("sound") == "GTFO Fail")
    assert(c.TwichUIDB.ui.pinsSound.enabled == false, "a chosen false is saved as a value")
    assert(c.TwichUIDB.ui.pinsBroker == nil, "the data bar's settings are not touched")
    c.TwichUIDB.ui.pinsSound = nil
  end
  for _, suffix in ipairs({ "BgTexture", "BgColor", "BgOpacity", "BorderTexture", "BorderSize", "BorderColor", "BorderOpacity" }) do
    assert(variables["TWICHUI_pinsMenu" .. suffix] == "Pin appearance", "pinsMenu" .. suffix .. " is on the appearance page")
    assert(variables["TWICHUI_pinsLook" .. suffix] == "Pin appearance", "the window's look is still its own")
  end
  proxies.TWICHUI_pinsMenuBgOpacity:SetValue(40)
  assert(PL.MenuLook.Get("bgOpacity") == 40 and c.TwichUIDB.ui.pinsBrokerMenu.bgOpacity == 40)
  assert(R.MenuStyle.Get("bgOpacity") == R.MenuStyle.DEFAULTS.bgOpacity and PL.Look.Get("bgOpacity") == PL.Look.DEFAULTS.bgOpacity,
    "the launchers' and the window's looks are not changed")
  PL.MenuLook.Reset()
  assert(c.TwichUIDB.ui.pinsBrokerMenu == nil and c.TwichUIDB.ui.pinsBroker == nil)
  -- the new pin window's look: every control is on the page, writes its own saved look and nothing else
  for _, suffix in ipairs({ "BgTexture", "BgColor", "BgOpacity", "BorderTexture", "BorderSize", "BorderColor", "BorderOpacity" }) do
    assert(variables["TWICHUI_pinsEditor" .. suffix] == "Pin appearance", "pinsEditor" .. suffix .. " is on the appearance page")
  end
  proxies.TWICHUI_pinsEditorBgOpacity:SetValue(55)
  assert(PL.EditorLook.Get("bgOpacity") == 55 and c.TwichUIDB.ui.pinsEditorLook.bgOpacity == 55)
  assert(PL.Look.Get("bgOpacity") == PL.Look.DEFAULTS.bgOpacity and PL.MenuLook.Get("bgOpacity") == PL.MenuLook.DEFAULTS.bgOpacity,
    "the window's and the menu's looks are not changed")
  PL.EditorLook.Reset()
  assert(c.TwichUIDB.ui.pinsEditorLook == nil)
end
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
  assert(preferInit.data.tooltip and preferInit:GetTooltip():find("even when an ordinary item restores more", 1, true), "the tooltip says what prefer means")
  -- EllesmereUI's Unlock Mode: off by default, live only while the buttons are on, says what it does and where it stands
  assert(defaults.foodDrinkUnlock == false and c.TwichUIDB.modules.foodDrinkUnlock == false, "the Unlock Mode choice is opt-in")
  local unlockInit
  for _, i in ipairs(initializers) do if i.setting and i.setting.name == "Use EllesmereUI Unlock Mode" then unlockInit = i end end
  assert(unlockInit and #unlockInit.modify == 1, "live only while the buttons are on")
  local tip = unlockInit:GetTooltip()
  assert(tip:find("/unlock", 1, true) and tip:find("Edit Mode", 1, true), "the tooltip says how to open it and what happens without it")
  assert(tip:find("Status:", 1, true) and tip:find("Off", 1, true), "and where it stands")
  assert(not c.TwichUIDB.ui.foodDrinkPosition, "nothing is saved by looking")
  c.TwichUIDB.ui.foodDrinkPosition = { x = 5, y = 6 }
  c.TwichUIDB.ui.trainingPosition = { x = 1, y = 2 }
  local positionReset
  for _, i in ipairs(initializers) do if i.click and i.data.name == "Position" then positionReset = i end end
  assert(positionReset, "a Position reset button")
  positionReset.click()
  assert(c.TwichUIDB.ui.foodDrinkPosition == nil and c.TwichUIDB.ui.trainingPosition.x == 1, "it clears this place and no other")
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
  S.ClickReset(reset)
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
    if i.click and i.data.name == "Preview" and not preview then preview = i end   -- the menus' (the panel's comes later)
    if i.click and i.data.name == "Menu appearance" then reset = i end
  end
  assert(preview and reset, "a preview and a reset")
  preview.click(); preview.click()   -- shows and puts away without error
  S.ClickReset(reset)
  assert(c.TwichUIDB.ui.brokerMenu == nil, "Reset forgets the saved appearance")
  for _, key in pairs(keys) do assert(MS.Get(key) == MS.DEFAULTS[key], key .. " is back to its default") end
  assert(c.TwichUIDB.ui.mageTravelText == "none" and c.TwichUIDB.ui.foodDrink.size == 50, "Reset leaves everything else alone")
end
-- Refreshments panel appearance: the same controls for the panel's own look, under its own names, greyed
-- out while refreshments are off; its Reset leaves the menus' look alone.
do
  local PS, MS = R.RefreshmentsPanel.Style, R.MenuStyle
  local n = 0
  for _, suffix in ipairs({ "BgTexture", "BgColor", "BgOpacity", "BorderTexture", "BorderSize", "BorderColor", "BorderOpacity" }) do
    local variable = "TWICHUI_refreshmentsPanel" .. suffix
    assert(proxies[variable] and variables[variable] == "Mage", variable .. " is on the Mage page")
    n = n + 1
  end
  assert(n == 7)
  local headers, controls, reset, preview = {}, {}, nil, nil
  local inPanel = false   -- other pages have a "Preview" button too (Party pins' are on while it is on)
  for _, i in ipairs(initializers) do
    if not i.setting and not i.click then
      headers[i.data.name] = true
      inPanel = i.data.name == "Refreshments panel appearance"
    end
    if i.setting and i.setting.variable and i.setting.variable:find("^TWICHUI_refreshmentsPanel") then controls[#controls + 1] = i end
    if i.click and i.data.name == "Panel appearance" then reset = i end
    if inPanel and i.click and i.data.name == "Preview" and not preview then preview = i end
  end
  assert(headers["Refreshments panel appearance"] and reset and preview and #controls == 7)
  c.TwichUIDB.modules.mageRefreshments = false
  for _, i in ipairs(controls) do assert(not i:Enabled(), i.data.name .. " is greyed out while refreshments are off") end
  assert(not reset:Enabled() and not preview:Enabled())
  c.TwichUIDB.modules.mageRefreshments = true
  for _, i in ipairs(controls) do assert(i:Enabled(), i.data.name .. " can be changed") end
  proxies.TWICHUI_refreshmentsPanelBgOpacity.set(55)
  proxies.TWICHUI_refreshmentsPanelBorderTexture.set("Blizzard Tooltip")
  assert(PS.Get("bgOpacity") == 55 and PS.Get("borderTexture") == "Blizzard Tooltip" and c.TwichUIDB.ui.refreshmentsStyle.bgOpacity == 55)
  MS.Set("bgOpacity", 20)
  S.ClickReset(reset)
  assert(c.TwichUIDB.ui.refreshmentsStyle == nil and PS.Get("bgOpacity") == PS.DEFAULTS.bgOpacity, "the panel's look is reset")
  assert(MS.Get("bgOpacity") == 20, "the menus' look is not")
  MS.Reset()
  c.TwichUIDB.modules.mageRefreshments = false
end
assert(K.pages.chronicle and K.pages.sharing and K.pages.overview)
R:OpenSettings("chronicle"); assert(c.opened == "chronicle", "opens a named page")
R:OpenSettings(); assert(c.opened == "overview", "opens the start page by default")

-- Overview rows: status text follows the toggles, and each opens its page.
-- Home no longer lists the features; each page shows its own status under its title (the page's overview.status).
for _, i in ipairs(initializers) do assert(i.kind ~= "link", "Home has no feature rows") end
local rows = {}
for _, page in ipairs(K.list) do
  local o = page.def.overview
  if o and o.status then
    rows[page.name] = { status = o.status, click = function() R:OpenSettings(page.key) end }
  end
end
assert(not rows["Zone arrival"], "the zone card no longer has a row of its own")
local zone = assert(rows["Notifications"], "the Notifications page has a status")
assert(zone.status():find("3 of 3 on"), zone.status())
c.TwichUIDB.modules.arrival = false
c.TwichUIDB.modules.attuneSkin = true
-- a toggle change refreshes the status
local arrivalToggle; for _, i in ipairs(initializers) do if i.setting and i.setting.name == "Show a title card when I arrive in a new zone" then arrivalToggle = i end end
arrivalToggle.setting.changed()
assert(zone.status():find("2 of 3 on"), zone.status())
c.TwichUIDB.modules.trainingNotice, c.TwichUIDB.modules.friendLogin = false, false
arrivalToggle.setting.changed()
assert(zone.status():find("Off"), "all three off: " .. zone.status())
zone.click(); assert(c.opened == "notifications", "row opens the Notifications page")
assert(not K.pages.arrival, "no separate zone arrival page")
assert(rows["Addon skins"].status():find("of") or rows["Addon skins"].status():find("None installed"), rows["Addon skins"].status())


-- Quality of life: everything is opt-in, there is no "requested invites" row (the game's interface
-- for it isn't in Forever), choices read and write the saved options, and the waits sit with what they wait for.
for _, key in ipairs({ "qolSummons", "qolResurrect", "qolResurrectCombat", "qolReleasePvP", "qolDuels", "qolDuelsToDeath", "qolQuickKeybind", "qolGuideWaypoint", "qolEasyFishing" }) do
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
for _, name in ipairs({ "Accept summons", "Accept resurrection", "Release in battlegrounds", "Decline duel requests",
  "Wait before accepting a summon", "Wait before releasing" }) do
  assert(visible[name], name .. " is visible by default")
end
-- the waits sit with what they wait for, indented under it
do
  local function Row(name) for _, i in ipairs(initializers) do if i:GetName() == name then return i end end end
  local wait, from = Row("Wait before accepting a summon"), Row("Accept summons from")
  assert(wait.section == from.section and wait.section:GetName() == "Summons and resurrection", "the summon wait is in Summons and resurrection")
  assert(wait.parent and wait.parent:GetName() == "Accept summons" and from.parent == wait.parent, "both are under Accept summons")
  local release = Row("Wait before releasing")
  assert(release.section:GetName() == "Battlegrounds" and release.parent:GetName() == "Release in battlegrounds")
end
-- Turning a switch on or off starts and stops its listening, with no reload.
local summonToggle; for _, i in ipairs(initializers) do if i.setting and i.setting.name == "Accept summons" then summonToggle = i end end
c.TwichUIDB.modules.qolSummons = true; summonToggle.setting.changed(); assert(R.frame.events.CONFIRM_SUMMON, "listening once on")
c.TwichUIDB.modules.qolSummons = false; summonToggle.setting.changed(); assert(not R.frame.events.CONFIRM_SUMMON, "and not once off")
-- The overview row follows the switches.
local qolRow = assert(rows["Quality of life"], "the Quality of life page has a status")
assert(qolRow.status():find("Off"), qolRow.status())
c.TwichUIDB.modules.qolDuels, c.TwichUIDB.modules.qolReleasePvP = true, true; summonToggle.setting.changed()
assert(qolRow.status():find("2 of 7 on"), qolRow.status())
-- The RestedXP destination row: off, visible, and its tooltip says what it is doing right now.
do
  local guideRow; for _, i in ipairs(initializers) do if i.setting and i.setting.name == "Mark RestedXP's destination" then guideRow = i end end
  assert(guideRow and visible["Mark RestedXP's destination"], "the RestedXP destination row is there and visible")
  assert(guideRow:GetTooltip():find("Status: .*Off"), guideRow:GetTooltip())
  c.TwichUIDB.modules.qolGuideWaypoint = true
  assert(guideRow:GetTooltip():find("RestedXP not installed"), guideRow:GetTooltip())
  c.TwichUIDB.modules.qolGuideWaypoint = false
end
-- Easy Fishing: off, its key and client-setting rows wait for it, the status says what is missing, and nothing
-- is bound or changed until the player says so.
do
  local function ByName(prefix) for _, i in ipairs(initializers) do if (i:GetName() or ""):sub(1, #prefix) == prefix then return i end end end
  local fishRow = ByName("Easy Fishing")
  local keyRow, clearRow = ByName("Key:"), ByName("Clear the key")
  local targetRow = ByName("Adjust interaction targeting while fishing")
  assert(fishRow and keyRow and clearRow and targetRow, "the Easy Fishing rows are there")
  assert(fishRow.data.tooltip:find("Use the same key to cast your line and reel in a catch.", 1, true), "its explanation")
  assert(fishRow:GetTooltip():find("Status: .*Off"), fishRow:GetTooltip())
  assert(keyRow:GetName() == "Key: not set", keyRow:GetName())
  assert(not keyRow:Enabled() and not clearRow:Enabled() and not targetRow:Enabled(), "greyed out while Easy Fishing is off")
  assert(keyRow:DisabledReason():find("Easy Fishing"), keyRow:DisabledReason())
  c.TwichUIDB.modules.qolEasyFishing = true
  assert(keyRow:Enabled() and targetRow:Enabled(), "on: the key and the permission can be used")
  assert(not clearRow:Enabled() and clearRow:DisabledReason():find("No key"), "nothing to clear while no key is set")
  c.TwichUIDB.modules.qolEasyFishing = false
  assert(R.DEFAULT_MODULES.qolEasyFishing == false and R.QoL.Get("easyFishingTargeting") == "leave", "off, and no permission, for a new install")
end
qolRow.click(); assert(c.opened == "qol", "row opens the Quality of life page")
-- Leatrix Plus overlap shows in the tooltip, and leaves its settings alone.
c.C_AddOns.IsAddOnLoaded = function(n) return n == "Leatrix_Plus" end
c.LeaPlusDB = { AutoAcceptSummon = "On" }
summonToggle.setting.changed()
assert(summonToggle:GetTooltip():find("Leatrix Plus also has this turned on"), "overlap note")
c.LeaPlusDB.AutoAcceptSummon = "Off"; summonToggle.setting.changed()
assert(not summonToggle:GetTooltip():find("Leatrix"), "no note when Leatrix has it off")

-- Interaction details: a greyed-out row says why in its tooltip (and keeps its saved value); a setting
-- that needs a reload says so; previews wait for combat and say so; nothing is hidden silently.
do
  local function Row(name, button)
    for _, i in ipairs(initializers) do
      if i.data.name == name and (not button or i.click) then return i end
    end
    error("no row " .. name)
  end
  local M = c.TwichUIDB.modules
  local arrivalRow, subzones = Row("Show a title card when I arrive in a new zone"), Row("Also for smaller places")
  M.arrival = true
  local base = subzones.data.tooltip
  assert(subzones:GetTooltip() == base and subzones:Enabled(), "on: the usual tooltip, nothing greyed")
  M.arrival = false
  assert(not subzones:Enabled(), "the parent is off: greyed out")
  assert(subzones:GetTooltip():find(base, 1, true) and subzones:GetTooltip():find('needs "Show a title card when I arrive in a new zone" turned on', 1, true),
    "and the tooltip says why: " .. subzones:GetTooltip())
  assert(M.arrivalSubzones == true, "its own saved choice is left as it was")
  M.arrival = true

  -- a reason particular to the row
  local border = Row("Border color")
  M.foodDrink = true
  assert(R.FoodDrink.Set("borderClass", true))
  assert(not border:Enabled() and border:GetTooltip():find("class color", 1, true), "greyed while the class color is used, and says so: " .. border:GetTooltip())
  M.foodDrink = false
  assert(border:GetTooltip():find('needs "Show Food and Drink buttons" turned on', 1, true), "or because the feature is off: " .. border:GetTooltip())

  -- reload-only changes say so before the player changes them
  for _, name in ipairs({ "Hide addon welcome messages", "Custom fonts and sounds", "Configuration sharing", "Attune" }) do
    assert(Row(name):GetTooltip():find("Takes effect after you reload your UI.", 1, true), name .. " mentions the reload")
  end
  assert(not Row("Show Food and Drink buttons"):GetTooltip():find("reload your UI", 1, true), "an immediate setting doesn't")

  -- the sharing window button is greyed while sharing is off, and says what to do if pressed anyway
  local sharingOpen
  for _, i in ipairs(initializers) do if i.data.name == "Configuration sharing" and i.kind == "button" then sharingOpen = i end end
  M.setupSharing = false
  assert(sharingOpen and not sharingOpen:Enabled() and sharingOpen:GetTooltip():find("turned on", 1, true), "greyed with a reason")
  M.setupSharing = true
  assert(sharingOpen:Enabled())

  -- previews: not in combat, and a refusal is explained
  local printed = {}
  c.print = function(line) printed[#printed + 1] = line end
  local label
  for _, info in ipairs(R.Notify.Kinds()) do if info.kind == "arrival" then label = info.label end end
  local preview = Row(label, true)
  c.InCombatLockdown = function() return true end
  preview.click()
  assert(printed[#printed] and printed[#printed]:find("out of combat", 1, true), "preview in combat says to wait")
  c.InCombatLockdown = function() return false end
  Row("Test coordinated sequence", true)   -- exists
  Row("Clear previews", true).click()      -- nothing showing: harmless

  -- Clearing the troubleshooting records says what it did
  if R.DiagWindow then
    printed = {}
    Row("Collected records", true).click()
    assert(printed[#printed] and printed[#printed]:find("cleared", 1, true), "clear answers: " .. tostring(printed[#printed]))
  end
end

-- RestedXP skin: opt-in; its rows grey out with the switch; the detailed rows sit with their section; each writes
-- through to the look; Reset touches only the look (not the switch).
do
  local RS = R.RestedXPSkin
  assert(RS, "the module is loaded")
  local function RowFor(variable)
    for _, i in ipairs(initializers) do if i.setting == proxies[variable] then return i end end
  end
  local function Find(name) for _, i in ipairs(initializers) do if i.data.name == name then return i end end end
  local toggle = Find("Skin the RestedXP guide window")
  assert(toggle and toggle.GetTooltip and toggle:GetTooltip():find("Status: ", 1, true), "its tooltip says where it stands")
  assert(toggle:GetTooltip():find("Off", 1, true), "off by default")
  for _, v in ipairs({ "TWICHUI_restedxpLookBgColor", "TWICHUI_restedxpLookBorderColor", "TWICHUI_restedxpTitleColor",
    "TWICHUI_restedxpBodyColor" }) do
    local row = RowFor(v)
    assert(row and not row.advanced, v .. " is a common setting")
    assert(not row:Enabled(), v .. " is greyed out while the skin is off")
  end
  for _, v in ipairs({ "TWICHUI_restedxpLookBgTexture", "TWICHUI_restedxpLookBgOpacity", "TWICHUI_restedxpLookBorderTexture",
    "TWICHUI_restedxpLookBorderSize", "TWICHUI_restedxpLookBorderOpacity", "TWICHUI_restedxpTitleFont", "TWICHUI_restedxpTitleOutline",
    "TWICHUI_restedxpBodyFont", "TWICHUI_restedxpBodyOutline", "TWICHUI_restedxpTintScrollbar" }) do
    local row = RowFor(v)
    assert(row and not row.advanced and row.section, v .. " is a plain setting in a section of its own page")
  end
  c.TwichUIDB.modules.restedxpSkin = true
  assert(RowFor("TWICHUI_restedxpLookBgColor"):Enabled(), "enabled with the skin on")
  c.TwichUIDB.modules.restedxpSkin = false

  proxies.TWICHUI_restedxpLookBgOpacity.set(40)
  proxies.TWICHUI_restedxpLookBorderColor.set("ff102030")
  proxies.TWICHUI_restedxpTitleOutline.set("thick")
  proxies.TWICHUI_restedxpBodyFont.set("Some Font")
  assert(RS.Look.Get("bgOpacity") == 40 and RS.Look.Get("borderColor") == "ff102030")
  assert(RS.Text.Get("titleOutline") == "thick" and RS.Text.Get("bodyFont") == "Some Font")
  assert(proxies.TWICHUI_restedxpLookBgOpacity.get() == 40, "reads back the saved value")
  proxies.TWICHUI_restedxpLookBgOpacity.set(500)   -- refused, not saved
  assert(RS.Look.Get("bgOpacity") == 40)
  -- a font that is not available is listed, marked, and stays chosen
  local container = dropdowns.TWICHUI_restedxpBodyFont()
  local marked
  for _, entry in ipairs(container) do if entry.value == "Some Font" then marked = entry.label end end
  assert(marked and marked:find("not available", 1, true), "a missing font stays listed, marked")
  assert(container[1].value == "default", "RestedXP's own font is first")

  -- RestedXP's settings are a page of their own under Addon skins, with a pointer on that page
  assert(variables.TWICHUI_restedxpSkin == "RestedXP guide window", "the switch is on RestedXP's page: " .. tostring(variables.TWICHUI_restedxpSkin))
  assert(variables.TWICHUI_restedxpLookBgColor == "RestedXP guide window" and variables.TWICHUI_restedxpArrowShape == "RestedXP guide window")
  assert(K.pages.restedxp, "R:OpenSettings can open it")
  local pointer = Find("RestedXP guide window")
  local pointerButton
  for _, i in ipairs(initializers) do if i.click and i.data.name == "RestedXP guide window" then pointerButton = i end end
  assert(pointerButton, "a pointer button on the Addon skins page")
  pointerButton.click()
  assert(c.opened == "restedxp", "it opens the page")
  local skinsPageIndex, restedxpPageIndex
  for i, name in ipairs(pageOrder) do
    if name == "Addon skins" then skinsPageIndex = i elseif name == "RestedXP guide window" then restedxpPageIndex = i end
  end
  assert(skinsPageIndex and restedxpPageIndex == skinsPageIndex + 1, "listed right under Addon skins")

  -- the waypoint arrow: common settings, validated, written through, and part of the appearance reset
  for _, v in ipairs({ "TWICHUI_restedxpArrowShape", "TWICHUI_restedxpArrowColor", "TWICHUI_restedxpArrowOpacity",
    "TWICHUI_restedxpArrowSize", "TWICHUI_restedxpArrowTextShown", "TWICHUI_restedxpArrowTextSize" }) do
    local row = RowFor(v)
    assert(row and not row.advanced, v .. " is a common setting")
    assert(not row:Enabled(), v .. " is greyed out while the skin is off")
  end
  assert(RowFor("TWICHUI_restedxpArrowSize").options.min == 50 and RowFor("TWICHUI_restedxpArrowSize").options.max == 250)
  assert(RS.Text.Get("arrowShape") == "bronze" and RS.Text.Get("arrowSize") == 100 and RS.Text.Get("arrowColor") == "ffffffff"
    and RS.Text.Get("arrowOpacity") == 100 and RS.Text.Get("arrowTextShown") == true and RS.Text.Get("arrowTextSize") == 100,
    "the bronze plate at RestedXP's own size by default")
  proxies.TWICHUI_restedxpArrowShape.set("RXP Gold")
  proxies.TWICHUI_restedxpArrowSize.set(140)
  proxies.TWICHUI_restedxpArrowColor.set("ff40a0ff")
  proxies.TWICHUI_restedxpArrowOpacity.set(5)      -- out of range
  proxies.TWICHUI_restedxpArrowTextSize.set(500)   -- out of range
  assert(RS.Text.Get("arrowShape") == "RXP Gold" and RS.Text.Get("arrowSize") == 140 and RS.Text.Get("arrowColor") == "ff40a0ff")
  assert(RS.Text.Get("arrowOpacity") == 100 and RS.Text.Get("arrowTextSize") == 100, "out of range is refused")
  local shapes = dropdowns.TWICHUI_restedxpArrowShape()
  assert(shapes[1].value == "bronze" and shapes[2].value == "default", "the shape list opens with the bronze plate, then RestedXP's own")
  local listed
  for _, entry in ipairs(shapes) do if entry.value == "RXP Gold" then listed = entry.label end end
  assert(listed and listed:find("not available", 1, true), "a saved shape that is not there is listed, marked")

  -- the current-step panel: a menu button on hover (on) and the step tab's format (RestedXP's own wording)
  for _, v in ipairs({ "TWICHUI_restedxpSettingsButton", "TWICHUI_restedxpStepLabel" }) do
    local row = RowFor(v)
    assert(row and not row.advanced, v .. " is a common setting")
    assert(not row:Enabled(), v .. " is greyed out while the skin is off")
  end
  assert(Find("Show settings button on current-step hover") and Find("Step label format"), "named as asked")
  assert(RS.Text.Get("settingsButton") == true and RS.Text.Get("stepLabel") == "step", "defaults: button on, Step X")
  local formats = dropdowns.TWICHUI_restedxpStepLabel()
  local labels = {}
  for _, entry in ipairs(formats) do labels[#labels + 1] = entry.label end
  assert(table.concat(labels, "|") == "Step X|Step X/Y|Step X (59%)|Step X/Y (59%)", table.concat(labels, "|"))
  proxies.TWICHUI_restedxpStepLabel.set("both")
  assert(RS.Text.Get("stepLabel") == "both" and proxies.TWICHUI_restedxpStepLabel.get() == "both")
  proxies.TWICHUI_restedxpStepLabel.set("nonsense")
  assert(RS.Text.Get("stepLabel") == "both", "an unknown format is refused")
  proxies.TWICHUI_restedxpSettingsButton.set(false)
  assert(RS.Text.Get("settingsButton") == false and proxies.TWICHUI_restedxpSettingsButton.get() == false)
  proxies.TWICHUI_restedxpSettingsButton.set(true)
  proxies.TWICHUI_restedxpStepLabel.set("step")

  -- the layout and size controls: the everyday ones are common, the borders sit with the header, and
  -- the sizes are greyed until the player chooses to set them
  for _, v in ipairs({ "TWICHUI_restedxpShowCog", "TWICHUI_restedxpShowResizeHandle", "TWICHUI_restedxpShowTitle", "TWICHUI_restedxpShowLogo", "TWICHUI_restedxpShowClassIcon", "TWICHUI_restedxpFooter",
    "TWICHUI_restedxpCustomSizes", "TWICHUI_restedxpLineSpacing", "TWICHUI_restedxpStepPadding", "TWICHUI_restedxpScrollbar" }) do
    local row = RowFor(v)
    assert(row and not row.advanced, v .. " is a common setting")
    assert(not row:Enabled(), v .. " is greyed out while the skin is off")
  end
  assert(RowFor("TWICHUI_restedxpDividers") and not RowFor("TWICHUI_restedxpDividers").advanced
  and RowFor("TWICHUI_restedxpDividers").section:GetName() == "Header and footer", "section borders sit with the header and footer")
  for _, v in ipairs({ "TWICHUI_restedxpTitleSize", "TWICHUI_restedxpActiveSize", "TWICHUI_restedxpListSize" }) do
    local row = RowFor(v)
    assert(row and not row.advanced and row.options and row.options.min >= 8, v .. " is a ranged slider")
    c.TwichUIDB.modules.restedxpSkin = true
    assert(not row:Enabled(), v .. " is greyed out until sizes are set here")
    RS.Text.Set("customSizes", true)
    assert(row:Enabled(), v .. " is enabled once they are")
    RS.Text.Set("customSizes", false)
    c.TwichUIDB.modules.restedxpSkin = false
  end
  assert(RowFor("TWICHUI_restedxpListSize").options.max == RS.Text.LIMITS.listSize[2], "the slider's range is the validated one")
  local fade = RowFor("TWICHUI_restedxpFutureFade")
  assert(fade and not fade.advanced and fade.options.min == 0 and fade.options.max == 70, "the fade is a common 0-70 slider")
  assert(RS.Text.Get("futureFade") == 35, "a gentle fade by default")
  proxies.TWICHUI_restedxpFutureFade.set(50)
  assert(RS.Text.Get("futureFade") == 50)
  proxies.TWICHUI_restedxpFutureFade.set(90)
  assert(RS.Text.Get("futureFade") == 50, "out of range is refused")
  assert(RS.Text.Get("showLogo") == false and RS.Text.Get("showClassIcon") == false, "decoration is off by default")
  assert(RS.Text.Get("showTitle") == true, "the title is shown unless the player hides it")
  assert(RS.Text.Get("showCog") == true and RS.Text.Get("showResizeHandle") == true, "the cog and handle are RestedXP's own by default")
  proxies.TWICHUI_restedxpShowCog.set(false)
  assert(RS.Text.Get("showCog") == false, "the cog can be hidden")
  proxies.TWICHUI_restedxpShowTitle.set(false)
  assert(RS.Text.Get("showTitle") == false and proxies.TWICHUI_restedxpShowTitle.get() == false, "the title can be hidden")
  assert(proxies.TWICHUI_restedxpShowLogo.get() == false)
  proxies.TWICHUI_restedxpShowLogo.set(true)
  proxies.TWICHUI_restedxpListSize.set(13)
  proxies.TWICHUI_restedxpFooter.set("hidden")
  proxies.TWICHUI_restedxpScrollbar.set("original")
  proxies.TWICHUI_restedxpStepPadding.set(5)
  assert(RS.Text.Get("showLogo") == true and RS.Text.Get("listSize") == 13 and RS.Text.Get("footer") == "hidden"
    and RS.Text.Get("scrollbar") == "original" and RS.Text.Get("stepPadding") == 5, "each writes through")
  proxies.TWICHUI_restedxpListSize.set(40)   -- out of range: refused
  proxies.TWICHUI_restedxpFooter.set("nowhere")
  assert(RS.Text.Get("listSize") == 13 and RS.Text.Get("footer") == "hidden", "invalid values are not saved")
  local footerChoices = dropdowns.TWICHUI_restedxpFooter()
  assert(#footerChoices == 3 and footerChoices[1].value == "subtle", "the footer choices")

  c.TwichUIDB.modules.restedxpSkin = true
  S.ClickReset(Find("Reset appearance"))
  assert(RS.Look.Get("bgOpacity") == RS.Look.DEFAULTS.bgOpacity and RS.Look.Get("borderColor") == RS.Look.DEFAULTS.borderColor)
  assert(RS.Text.Get("titleOutline") == "none" and RS.Text.Get("bodyFont") == "default", "text back to its defaults")
  assert(RS.Text.Get("showLogo") == false and RS.Text.Get("listSize") == RS.Text.DEFAULTS.listSize
    and RS.Text.Get("footer") == "subtle" and RS.Text.Get("scrollbar") == "slim" and RS.Text.Get("stepPadding") == 2
    and RS.Text.Get("showTitle") == true and RS.Text.Get("futureFade") == 35 and RS.Text.Get("showCog") == true
    and RS.Text.Get("arrowShape") == "bronze" and RS.Text.Get("arrowSize") == 100,
    "sizes, spacing and what shows are part of the appearance reset")
  assert(c.TwichUIDB.modules.restedxpSkin == true, "the switch is not part of the look")
  c.TwichUIDB.modules.restedxpSkin = false
end

-- SpeakStone skin: opt-in; its page sits right under Addon skins; the everyday rows are in plain view and the
-- the rest in their sections; everything is greyed out with the switch off; each row writes through and refuses what
-- is invalid; the sample line asks SpeakStone's own command; Reset touches only this look.
do
  local SS = R.SpeakStoneSkin
  assert(SS, "the module is loaded")
  assert(defaults.speakstoneSkin == false, "the SpeakStone skin is opt-in")
  local function RowFor(variable)
    for _, i in ipairs(initializers) do if i.setting == proxies[variable] then return i end end
  end
  local function Find(name) for _, i in ipairs(initializers) do if i.data.name == name then return i end end end
  local toggle = Find("Skin the SpeakStone speech frame")
  assert(toggle and toggle.GetTooltip and toggle:GetTooltip():find("Status: ", 1, true), "its tooltip says where it stands")
  assert(toggle:GetTooltip():find("Off", 1, true), "off by default")
  assert(toggle:GetTooltip():find("no reload is needed", 1, true), "and that it can be turned off live")
  assert(variables.TWICHUI_speakstoneSkin == "SpeakStone speech frame", "the switch is on its own page")
  assert(K.pages.speakstone, "R:OpenSettings can open it")

  local common = { "TWICHUI_speakstoneLookBgColor", "TWICHUI_speakstoneLookBgOpacity", "TWICHUI_speakstoneLookBorderColor",
    "TWICHUI_speakstoneNameFont", "TWICHUI_speakstoneNameSize", "TWICHUI_speakstoneNameColor",
    "TWICHUI_speakstoneTextFont", "TWICHUI_speakstoneTextSize", "TWICHUI_speakstoneTextColor", "TWICHUI_speakstoneTimeColor",
    "TWICHUI_speakstoneButtonText", "TWICHUI_speakstoneButtonFill", "TWICHUI_speakstoneButtonBorder", "TWICHUI_speakstoneAccentColor",
    "TWICHUI_speakstoneRightClickClose",
    "TWICHUI_speakstoneShowPortrait", "TWICHUI_speakstonePortraitSize", "TWICHUI_speakstonePortraitShape",
    "TWICHUI_speakstonePortraitBorderColor", "TWICHUI_speakstoneShowProgress", "TWICHUI_speakstoneProgressColor",
    "TWICHUI_speakstoneTrackColor", "TWICHUI_speakstoneProgressHeight" }
  for _, v in ipairs(common) do
    local row = RowFor(v)
    assert(row and not row.advanced, v .. " is a common setting")
    assert(not row:Enabled(), v .. " is greyed out while the skin is off")
  end
  for _, v in ipairs({ "TWICHUI_speakstoneLookBgTexture", "TWICHUI_speakstoneLookBorderTexture", "TWICHUI_speakstoneLookBorderSize",
    "TWICHUI_speakstoneLookBorderOpacity", "TWICHUI_speakstoneTimeFont", "TWICHUI_speakstoneTimeSize",
    "TWICHUI_speakstoneButtonFont", "TWICHUI_speakstoneButtonSize", "TWICHUI_speakstoneLineSpacing",
    "TWICHUI_speakstonePadding", "TWICHUI_speakstonePortraitBorderSize" }) do
    local row = RowFor(v)
    assert(row and not row.advanced and row.section, v .. " is a plain setting in a section of its own page")
  end
  c.TwichUIDB.modules.speakstoneSkin = true
  assert(RowFor("TWICHUI_speakstoneNameColor"):Enabled(), "enabled with the skin on")
  c.TwichUIDB.modules.speakstoneSkin = false

  assert(RowFor("TWICHUI_speakstoneTextSize").options.min == 10 and RowFor("TWICHUI_speakstoneTextSize").options.max == 24)
  proxies.TWICHUI_speakstoneLookBgOpacity.set(40)
  proxies.TWICHUI_speakstoneNameColor.set("ff102030")
  proxies.TWICHUI_speakstoneTextSize.set(15)
  proxies.TWICHUI_speakstonePortraitShape.set("square")
  proxies.TWICHUI_speakstoneShowProgress.set(false)
  assert(SS.Style.Get("rightClickClose") == true, "closing with a right-click is on by default")
  proxies.TWICHUI_speakstoneRightClickClose.set(false)
  assert(SS.Style.Get("rightClickClose") == false and proxies.TWICHUI_speakstoneRightClickClose.get() == false)
  assert(SS.Look.Get("bgOpacity") == 40 and SS.Style.Get("nameColor") == "ff102030" and SS.Style.Get("textSize") == 15
    and SS.Style.Get("portraitShape") == "square" and SS.Style.Get("showProgress") == false)
  assert(proxies.TWICHUI_speakstoneTextSize.get() == 15, "reads back the saved value")
  proxies.TWICHUI_speakstoneTextSize.set(99)          -- refused, not saved
  proxies.TWICHUI_speakstonePortraitShape.set("oval")
  proxies.TWICHUI_speakstoneNameColor.set("gold")
  assert(SS.Style.Get("textSize") == 15 and SS.Style.Get("portraitShape") == "square" and SS.Style.Get("nameColor") == "ff102030")
  -- the name's font is listed with SpeakStone's own first, and a font that has gone stays listed, marked
  proxies.TWICHUI_speakstoneNameFont.set("Some Font")
  local container = dropdowns.TWICHUI_speakstoneNameFont()
  local marked
  for _, entry in ipairs(container) do if entry.value == "Some Font" then marked = entry.label end end
  assert(marked and marked:find("not available", 1, true), "a missing font stays listed, marked")
  assert(container[1].value == "default", "SpeakStone's own font is first")
  local shapes = dropdowns.TWICHUI_speakstonePortraitShape()
  assert(#shapes == 2 and shapes[1].value == "round", "round is first")

  -- the sample line is SpeakStone's own command, and a missing one is not an error
  local sample = Find("Sample line")
  assert(sample and sample.click and not sample:Enabled(), "a sample line row, greyed out with the skin off")
  local asked
  c.SlashCmdList = c.SlashCmdList or {}
  c.SlashCmdList.SPEAKSTONE = function(msg) asked = msg end
  sample.click()
  assert(asked == "frame", "it asks /ss frame")
  c.SlashCmdList.SPEAKSTONE = nil
  sample.click()

  -- listed right under Addon skins, with a pointer on that page
  local skinsPageIndex, ownPageIndex
  for i, name in ipairs(pageOrder) do
    if name == "Addon skins" then skinsPageIndex = i elseif name == "SpeakStone speech frame" then ownPageIndex = i end
  end
  assert(skinsPageIndex and ownPageIndex and ownPageIndex > skinsPageIndex, "listed under Addon skins")
  local pointerButton
  for _, i in ipairs(initializers) do if i.click and i.data.name == "SpeakStone speech frame" then pointerButton = i end end
  assert(pointerButton, "a pointer button on the Addon skins page")
  pointerButton.click()
  assert(c.opened == "speakstone", "it opens the page")

  -- reset: only this look; the switch and the rest of TwichUI stay
  c.TwichUIDB.modules.speakstoneSkin = true
  Find("Reset appearance")  -- RestedXP's page has one of the same name: the one for this page is the last built
  local resets = {}
  for _, i in ipairs(initializers) do if i.click and i.data.name == "Reset appearance" then resets[#resets + 1] = i end end
  local mine
  for _, i in ipairs(resets) do
    if i.data.tooltip and i:GetTooltip():find("SpeakStone", 1, true) then mine = i end
  end
  assert(mine, "its own reset button")
  S.ClickReset(mine)
  assert(SS.Look.Get("bgOpacity") == SS.Look.DEFAULTS.bgOpacity and SS.Style.Get("nameColor") == SS.Style.DEFAULTS.nameColor
    and SS.Style.Get("textSize") == 13 and SS.Style.Get("portraitShape") == "round" and SS.Style.Get("showProgress") == true
    and SS.Style.Get("nameFont") == "Cinzel" and SS.Style.Get("rightClickClose") == true, "everything of the look is back")
  assert(c.TwichUIDB.modules.speakstoneSkin == true, "the switch is not part of the look")
  assert(proxies.TWICHUI_speakstoneTextSize.get() == 13, "and the control shows it")
  c.TwichUIDB.modules.speakstoneSkin = false
end

-- RestedXP timer bars: a group on RestedXP's page, greyed out unless the skin and "Skin timer bars" are on,
-- the everyday controls in plain view and the rest with them, each written through (and validated);
-- only controls that have an effect are offered; its own reset; a preview that is a sample.
do
  local RS = R.RestedXPSkin
  local TM = RS.Timers
  assert(TM, "the timer bars are loaded")
  local function RowFor(variable)
    for _, i in ipairs(initializers) do if i.setting == proxies[variable] then return i end end
  end
  local function Find(name) for _, i in ipairs(initializers) do if i.data.name == name then return i end end end
  local common = { "TWICHUI_restedxpSkinTimers", "TWICHUI_restedxpTimerFillGradient", "TWICHUI_restedxpTimerFillColor",
    "TWICHUI_restedxpTimerFillColor2", "TWICHUI_restedxpTimerFillOpacity", "TWICHUI_restedxpTimerLabelColor",
    "TWICHUI_restedxpTimerTimeColor", "TWICHUI_restedxpTimerLabelSize", "TWICHUI_restedxpTimerTimeSize",
    "TWICHUI_restedxpTimerShowIcon", "TWICHUI_restedxpTimerBarHeight", "TWICHUI_restedxpTimerLookBgColor",
    "TWICHUI_restedxpTimerLookBorderColor" }
  for _, v in ipairs(common) do
    assert(variables[v] == "RestedXP guide window", v .. " is on RestedXP's page: " .. tostring(variables[v]))
    local row = RowFor(v)
    assert(row and not row.advanced, v .. " is a common setting")
    assert(not row:Enabled(), v .. " is greyed out while the skin is off")
  end
  for _, v in ipairs({ "TWICHUI_restedxpTimerTextPadding", "TWICHUI_restedxpTimerFillTexture", "TWICHUI_restedxpTimerLabelFont",
    "TWICHUI_restedxpTimerLabelOutline", "TWICHUI_restedxpTimerTimeFont", "TWICHUI_restedxpTimerTimeOutline",
    "TWICHUI_restedxpTimerLookBgTexture", "TWICHUI_restedxpTimerLookBgOpacity", "TWICHUI_restedxpTimerLookBorderTexture",
    "TWICHUI_restedxpTimerLookBorderSize", "TWICHUI_restedxpTimerLookBorderOpacity" }) do
    local row = RowFor(v)
    assert(row and not row.advanced and row.section, v .. " is a plain setting in a section of its own page")
  end
  -- nothing is offered that has no effect: no spark, no width
  for _, i in ipairs(initializers) do
    local name = i.data.name or ""
    assert(not name:lower():find("spark", 1, true) and not name:find("Timer width", 1, true), "no control without an effect: " .. name)
  end
  assert(RowFor("TWICHUI_restedxpTimerBarHeight").options.min == 12 and RowFor("TWICHUI_restedxpTimerBarHeight").options.max == 28)
  assert(RowFor("TWICHUI_restedxpTimerLabelSize").options.min == 8 and RowFor("TWICHUI_restedxpTimerLabelSize").options.max == 18)
  -- greyed out until the skin is on, and again when the timer switch is off
  c.TwichUIDB.modules.restedxpSkin = true
  assert(RowFor("TWICHUI_restedxpSkinTimers"):Enabled(), "the switch follows the skin")
  assert(RowFor("TWICHUI_restedxpTimerFillColor"):Enabled(), "on by default with the skin")
  proxies.TWICHUI_restedxpSkinTimers.set(false)
  assert(RS.Timers.Opt.Get("skinTimers") == false and not RowFor("TWICHUI_restedxpTimerFillColor"):Enabled(), "greyed out with its own switch off")
  assert(RowFor("TWICHUI_restedxpSkinTimers"):Enabled(), "the switch itself stays reachable")
  proxies.TWICHUI_restedxpSkinTimers.set(true)
  c.TwichUIDB.modules.restedxpSkin = false

  -- writes through, validated
  proxies.TWICHUI_restedxpTimerFillColor.set("ff102030")
  proxies.TWICHUI_restedxpTimerBarHeight.set(20)
  proxies.TWICHUI_restedxpTimerLabelOutline.set("thick")
  proxies.TWICHUI_restedxpTimerShowIcon.set(true)
  proxies.TWICHUI_restedxpTimerLookBorderSize.set(2)
  assert(TM.Opt.Get("fillColor") == "ff102030" and TM.Opt.Get("barHeight") == 20 and TM.Opt.Get("labelOutline") == "thick"
    and TM.Opt.Get("showIcon") == true and TM.Look.Get("borderSize") == 2)
  proxies.TWICHUI_restedxpTimerBarHeight.set(80)           -- out of range: refused
  proxies.TWICHUI_restedxpTimerLabelOutline.set("nowhere")
  assert(TM.Opt.Get("barHeight") == 20 and TM.Opt.Get("labelOutline") == "thick", "invalid values are not saved")
  assert(proxies.TWICHUI_restedxpTimerBarHeight.get() == 20, "reads back")
  -- a missing texture and font stay listed, marked
  proxies.TWICHUI_restedxpTimerFillTexture.set("Lost Bar")
  proxies.TWICHUI_restedxpTimerLabelFont.set("Lost Font")
  local fills, labels = dropdowns.TWICHUI_restedxpTimerFillTexture(), dropdowns.TWICHUI_restedxpTimerLabelFont()
  assert(fills[1].value == "default" and fills[2].value == "solid", "RestedXP's own, then a flat fill")
  assert(fills[#fills].value == "Lost Bar" and fills[#fills].label:find("not available", 1, true))
  assert(labels[1].value == "inherit" and labels[#labels].value == "Lost Font" and labels[#labels].label:find("not available", 1, true))
  assert(dropdowns.TWICHUI_restedxpTimerTimeFont()[1].value == "inherit" and dropdowns.TWICHUI_restedxpTimerTimeOutline()[1].value == "inherit")
  assert(#dropdowns.TWICHUI_restedxpTimerFillGradient() == 3)

  -- a preview button that is a sample, and a reset that is only the timer bars
  local preview
  for _, i in ipairs(initializers) do
    if i.click and i.data.name == "Preview" and i.data.tooltip and i:GetTooltip():find("made-up timer bars", 1, true) then preview = i end
  end
  assert(preview, "a preview of the timer bars")
  -- (this page's frames are stateless stand-ins; showing and hiding are tested in test_restedxp_timers.lua)
  preview.click()
  preview.click()
  c.TwichUIDB.modules.restedxpSkin = true
  RS.Text.Set("bodyFont", "Keep This")
  S.ClickReset(Find("Reset timer bars"))
  assert(TM.Opt.Get("fillColor") == "ff80502d" and TM.Opt.Get("barHeight") == 16 and TM.Opt.Get("labelOutline") == "outline"
    and TM.Opt.Get("showIcon") == false and TM.Look.Get("borderSize") == 1 and TM.Opt.Get("skinTimers") == true,
    "the timer bars are back to their defaults")
  assert(RS.Text.Get("bodyFont") == "Keep This" and c.TwichUIDB.modules.restedxpSkin == true, "nothing else was touched")
  c.TwichUIDB.modules.restedxpSkin = false
  RS.Text.Reset()
end

-- Journey Chronicle appearance: on the Chronicle's page, common settings in plain view, the technical ones
-- in their sections, each written through to the look; greyed or hidden where they would do nothing; and a reset
-- that is only the appearance.
do
  local CA = R.ChronicleAppearance
  assert(CA and CA.Look, "the appearance is loaded")
  local function RowFor(variable)
    for _, i in ipairs(initializers) do if i.setting == proxies[variable] then return i end end
  end
  local function Find(name) for _, i in ipairs(initializers) do if i.data.name == name then return i end end end
  for _, v in ipairs({ "TWICHUI_chronicleLookBgTexture", "TWICHUI_chronicleLookBgColor", "TWICHUI_chronicleLookBgOpacity",
    "TWICHUI_chronicleLookBorderTexture", "TWICHUI_chronicleLookBorderColor", "TWICHUI_chronicleLookBorderOpacity",
    "TWICHUI_chronicleLookBorderSize", "TWICHUI_chronicleFont", "TWICHUI_chronicleHeadingFont", "TWICHUI_chronicleTitleColor",
    "TWICHUI_chronicleBodyColor", "TWICHUI_chronicleAccentColor", "TWICHUI_chronicleHoverOpacity", "TWICHUI_chronicleButtonStyle" }) do
    assert(variables[v] == "Chronicle appearance", v .. " is on the Chronicle's appearance page: " .. tostring(variables[v]))
    assert(RowFor(v) and not RowFor(v).advanced, v .. " is a common setting")
  end
  for _, v in ipairs({ "TWICHUI_chronicleLookBgTiling", "TWICHUI_chronicleLookBgTileSize", "TWICHUI_chronicleLookBgInset" }) do
    assert(RowFor(v) and not RowFor(v).advanced and RowFor(v).section:GetName() == "Background", v .. " sits with the background")
  end
  for v, section in pairs({ TWICHUI_chroniclePadding = "Border", TWICHUI_chronicleWindowOpacity = "Background",
    TWICHUI_chronicleOutline = "Typography", TWICHUI_chronicleScrollThumbColor = "Controls and accents",
    TWICHUI_chronicleDividerColor = "Controls and accents" }) do
    assert(RowFor(v) and not RowFor(v).advanced and RowFor(v).section:GetName() == section, v .. " sits in " .. section)
  end
  -- tiling controls mean something only for an image
  assert(not RowFor("TWICHUI_chronicleLookBgTiling"):Shown(), "a plain color is neither tiled nor stretched")
  proxies.TWICHUI_chronicleLookBgTexture.set("Blizzard Marble")
  assert(RowFor("TWICHUI_chronicleLookBgTiling"):Shown() and RowFor("TWICHUI_chronicleLookBgTileSize"):Shown(), "an image can be")
  proxies.TWICHUI_chronicleLookBgTexture.set("none")
  assert(not RowFor("TWICHUI_chronicleLookBgInset"):Shown(), "None has nothing to inset")
  proxies.TWICHUI_chronicleLookBgTexture.set("solid")
  -- thickness has no meaning for the ledger or for None
  local size = RowFor("TWICHUI_chronicleLookBorderSize")
  assert(CA.Look.Get("borderTexture") == "ledger" and not size:Enabled(), "the ledger has a fixed width")
  assert(size:GetTooltip():find("fixed width", 1, true), "and the tooltip says why")
  proxies.TWICHUI_chronicleLookBorderTexture.set("solid")
  assert(size:Enabled(), "a plain line has a thickness")
  proxies.TWICHUI_chronicleLookBorderTexture.set("none")
  assert(not size:Enabled() and not RowFor("TWICHUI_chronicleLookBorderColor"):Enabled(), "None draws nothing to size or color")
  -- sizes are greyed until chosen
  local titleSize = RowFor("TWICHUI_chronicleTitleSize")
  assert(not titleSize:Enabled(), "sizes follow the game until chosen")
  proxies.TWICHUI_chronicleCustomSizes.set(true)
  assert(titleSize:Enabled() and titleSize.options.min == 10 and titleSize.options.max == 28)
  -- each writes through; invalid values are not saved
  proxies.TWICHUI_chronicleFont.set("Some Font")
  proxies.TWICHUI_chronicleAccentColor.set("ff102030")
  proxies.TWICHUI_chronicleWindowOpacity.set(10)   -- below the floor
  proxies.TWICHUI_chronicleLookBgOpacity.set(45)
  assert(CA.Get("font") == "Some Font" and CA.Get("accentColor") == "ff102030" and CA.Get("windowOpacity") == 100)
  assert(CA.Look.Get("bgOpacity") == 45)
  assert(proxies.TWICHUI_chronicleAccentColor.get() == "ff102030")
  local container = dropdowns.TWICHUI_chronicleFont()
  local listed
  for _, entry in ipairs(container) do if entry.value == "Some Font" then listed = entry.label end end
  assert(container[1].value == "default" and listed and listed:find("not available", 1, true), "the saved font stays listed, marked")
  local styles = dropdowns.TWICHUI_chronicleLookBorderTexture()
  assert(styles[1].value == "ledger", "the ledger is listed first")
  -- appearance only
  c.TwichUIDB.ui.chronicleClock = "24"
  c.TwichUIDB.modules.chronicleSound = false
  S.ClickReset(Find("Reset Chronicle appearance"))
  assert(CA.Get("font") == "default" and CA.Get("accentColor") == CA.DEFAULTS.accentColor and CA.Look.Get("bgOpacity") == 98)
  assert(CA.Look.Get("borderTexture") == "ledger" and CA.Get("customSizes") == false)
  assert(c.TwichUIDB.ui.chronicleClock == "24" and c.TwichUIDB.modules.chronicleSound == false, "nothing but the look is reset")
  assert(Find("Chronicle window") and Find("Chronicle window").click, "a way to open the real window beside the settings")
end

print("SETTINGS DEFAULTS TESTS PASSED")
