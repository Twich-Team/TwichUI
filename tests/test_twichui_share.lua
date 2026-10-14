dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- TwichUI's own settings as a part of a shared setup (setup/TwichConfig.lua): what is shared and what is not,
-- the review, applying (profile scope, undo, reload), and what a damaged, older or newer payload may do.
-- Two clients stand in for two players; the sharing code, the profile code and the features are the real ones.
-- Nothing here is the game: windows, combat lockdown and the client's saved-variable writes are in-game checks
-- (docs/twichui-sharing.md).

local LibSerializeEnv

local function Boot(name, before)
  local c, S = SettingsClient({ name = name, beforeInit = function(c)
    c.said = {}
    c.print = function(s) c.said[#c.said + 1] = tostring(s) end
    c.combat = false
    c.InCombatLockdown = function() return c.combat end
    if before then before(c) end
  end })
  c.popups = {}
  CLIENTS[name] = c
  return c, S
end

local function Copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local o = {}
  seen[t] = o
  for k, v in pairs(t) do o[Copy(k, seen)] = Copy(v, seen) end
  return o
end

local function Same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function Pumped() for _ = 1, 12 do FlushTimers(); Pump() end end

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

-- What a client is using, group by group (the effective values, which is what is exported).
local function Everything(c) return c.TwichUI.TwichConfig.Build({ all = true }).groups end

local function Group(entry, id) return entry.groups[id] end

---------------------------------------------------------------------------
-- 1. TwichUI is a source: the schema, its groups, and that every setting is accounted for
---------------------------------------------------------------------------
local A, SA = Boot("Rich")
local TC = A.TwichUI.TwichConfig
local R = A.TwichUI

local groups = TC.Groups()
local ids = {}
for _, g in ipairs(groups) do
  ids[g.id] = g
  Check(g.complete, "group " .. g.id .. " is complete (its feature registries are all there)")
  Check(TC.Usable(g), "group " .. g.id .. " is usable")
end
for _, id in ipairs({ "general", "notifications", "qol", "food", "auction", "chronicle", "chronicleLook", "pins", "pinsLook",
    "gear", "gearWeights", "mage", "skins", "restedxp", "speakstone" }) do
  Check(ids[id], "group " .. id .. " exists")
end
Check(#TC.GroupList() == #groups, "the window lists every group")
Check(TC.Included() == false, "TwichUI's settings are not included until you tick them")

-- every switch is shared or kept local with a reason
local sharedSwitch = {}
for _, g in ipairs(groups) do
  for _, f in ipairs(g.fields) do if f.switch then sharedSwitch[f.key] = true end end
end
for key in pairs(A.TwichUI.DEFAULT_MODULES) do
  Check(sharedSwitch[key] or TC.LOCAL["modules." .. key], "switch " .. key .. " is shared or kept local with a reason")
  Check(not (sharedSwitch[key] and TC.LOCAL["modules." .. key]), "switch " .. key .. " is not both")
end
-- every key of the registries a table part draws on is shared or listed as not shared
local function SharedKey(slot, key)
  for _, g in ipairs(groups) do if g.index[slot] and g.index[slot][key] then return true end end
  return false
end
local REGISTRY = {
  foodDrink = A.TwichUI.FoodDrink.DEFAULTS, chronicleAppearance = A.TwichUI.ChronicleAppearance.DEFAULTS,
  partyPins = A.TwichUI.PinsLook.PREF_DEFAULTS, pinsAppearance = A.TwichUI.PinsLook.DEFAULTS,
  pinsMapText = A.TwichUI.PinsLook.MapText.DEFAULTS, pinsBroker = A.TwichUI.PinsLook.Bar.DEFAULTS,
  pinsSound = A.TwichUI.PinsLook.Sound.DEFAULTS, restedxpSkinText = A.TwichUI.RestedXPSkin.Text.DEFAULTS,
  restedxpTimerText = A.TwichUI.RestedXPSkin.Timers.Opt.DEFAULTS, speakstoneSkinStyle = A.TwichUI.SpeakStoneSkin.Style.DEFAULTS,
  gear = A.TwichUI.GearPrefs.DEFAULTS, brokerMenu = A.TwichUI.MenuStyle.DEFAULTS,
  refreshmentsStyle = A.TwichUI.RefreshmentsPanel.Style.DEFAULTS, restedxpSkin = A.TwichUI.RestedXPSkin.Look.DEFAULTS,
  pinsLook = A.TwichUI.PinsLook.Look.DEFAULTS, pinsBrokerMenu = A.TwichUI.PinsLook.MenuLook.DEFAULTS,
  pinsEditorLook = A.TwichUI.PinsLook.EditorLook.DEFAULTS, speakstoneSkin = A.TwichUI.SpeakStoneSkin.Look.DEFAULTS,
  restedxpTimerLook = A.TwichUI.RestedXPSkin.Timers.Look.DEFAULTS, chronicleLook = A.TwichUI.ChronicleAppearance.LOOK_DEFAULTS,
}
for slot, defaults in pairs(REGISTRY) do
  for key in pairs(defaults) do
    Check(SharedKey(slot, key), ("%s.%s is shared (a new default key has to be placed in the schema)"):format(slot, key))
  end
end

-- every key the settings window can change (the contract fixture's saved layout) is shared or kept local
do
  local fixture = dofile(TESTS .. "fixtures/settings_contract.lua")
  local top, sub
  local function Covered(path)
    local p = path
    while p do
      if TC.LOCAL[p] then return true end
      p = p:match("^(.*)%.[^.]+$")
    end
    return false
  end
  local checked = 0
  for _, line in ipairs(fixture.changedDB or {}) do
    local indent, name, rest = line:match("^( *)([%w_%- ]+)(.*)$")
    if indent then
      local depth = #indent / 2
      if depth == 0 then top, sub = name:gsub(":$", ""), nil
      elseif depth == 1 and (top == "ui" or top == "gear" or top == "modules") then
        local key = name
        if rest:find("^:") then sub = key else sub = nil end
        if top == "modules" then
          Check(sharedSwitch[key] or Covered("modules." .. key), "saved key modules." .. key .. " is placed")
          checked = checked + 1
        elseif not rest:find("^:") then
          Check(SharedKey("ui", key) or SharedKey("gear", key) or Covered(top .. "." .. key), "saved key " .. top .. "." .. key .. " is placed")
          checked = checked + 1
        end
      elseif depth == 2 and (top == "ui" or top == "gear") and sub then
        Check(SharedKey(sub, name) or Covered(top .. "." .. sub .. "." .. name) or Covered(top .. "." .. sub),
          "saved key " .. top .. "." .. sub .. "." .. name .. " is placed")
        checked = checked + 1
      end
    end
  end
  Check(checked > 150, "the fixture walk checked the saved keys (" .. checked .. ")")
end

-- nothing in the settings window is needed to know what is shared
do
  local f = assert(io.open(ROOT .. "setup/TwichConfig.lua")); local src = f:read("*a"); f:close()
  for _, word in ipairs({ "TwichUI_Settings", "LoadAddOn", "SettingsKit", "SettingsUI", "loadstring" }) do
    Check(not src:find(word, 1, true), "TwichConfig.lua does not mention " .. word)
  end
  Check(not src:find("%f[%w_]load%("), "TwichConfig.lua never calls load")
end

---------------------------------------------------------------------------
-- 2. A sender with settings changed in many features; a receiver with others; the real send
---------------------------------------------------------------------------
local function Customise(c)
  local R = c.TwichUI
  R.FoodDrink.Set("size", 48); R.FoodDrink.Set("spacing", 0); R.FoodDrink.Set("zoom", 0); R.FoodDrink.Set("showCount", false)
  R.FoodDrink.Set("borderOpacity", 0); R.FoodDrink.Set("layout", "vertical"); R.FoodDrink.Set("mouseover", true)
  R:SetEnabled("foodDrink", true); R:SetEnabled("foodDrinkDrink", false)
  R:SetEnabled("chronicleDeaths", true); R:SetEnabled("chronicleGold", false); R:SetEnabled("welcomeBack", false)
  R:SetEnabled("arrivalReducedMotion", true); R:SetEnabled("friendLogin", false)
  R:SetEnabled("attuneSkin", false); R:SetEnabled("whatsTrainingSkin", false)
  R:SetEnabled("gearBagIcons", true); R:SetEnabled("auctionPosting", false)
  R:SetEnabled("quietLogin", false)
  R.Arrival.SetHoldChoice("longer")
  R.ChronicleAppearance.Set("titleSize", 20); R.ChronicleAppearance.Set("worn", false); R.ChronicleAppearance.Set("accentColor", "ff112233")
  R.ChronicleAppearance.Look.Set("bgOpacity", 0); R.ChronicleAppearance.Look.Set("borderSize", 3)
  R.Chronicle.SetClock("24")
  R.PinsLook.Set("textSize", 14); R.PinsLook.SetPref("labels", "always"); R.PinsLook.SetPref("minimap", false)
  R.PinsLook.Bar.Set("flashSeconds", 5); R.PinsLook.Sound.Set("enabled", false)
  R.RestedXPSkin.Text.Set("futureFade", 0); R.RestedXPSkin.Text.Set("showCog", false); R.RestedXPSkin.Look.Set("bgOpacity", 40)
  R.SpeakStoneSkin.Style.Set("textSize", 18); R.SpeakStoneSkin.Style.Set("showPortrait", false)
  R.GearPrefs.Set("reveal", "always"); R.GearPrefs.Set("strictness", "eager"); R.GearPrefs.Set("glancePossible", false)
  R.MenuStyle.Set("bgOpacity", 10)
  R.Refreshments.SetShare("party", "DRUID", "water", 0)
  R.Refreshments.SetShare("raid", "MAGE", "food", 7)
  R:SetEnabled("mageTravel", false)
  R.MageTravel.SetTextChoice("Portals")
end

Customise(A)
-- places and records that must stay behind
A.TwichUIDB.ui.foodDrinkPosition = { x = 123, y = 456 }
A.TwichUIDB.ui.trainingPosition = { x = 7, y = 8 }
A.TwichUIDB.ui.settingsWindow = { x = 9, y = 9 }
A.TwichUIDB.ui.partyPins = A.TwichUIDB.ui.partyPins or {}
A.TwichUIDB.ui.partyPins.position = { x = 5, y = 5 }
A.TwichUIDB.ui.guideWaypoint = { ["Player-1-Sentinel"] = { x = 1 } }
A.TwichUIDB.ui.qol = { summonsFrom = "anyone", summonsWait = 9 }
A.TwichUIDB.ui.mageSell = { never = { [12345] = true } }
A.TwichUIDB.modules.qolSummons = true
A.TwichUIDB.modules.mageSell = true
A.TwichUIDB.modules.mageSellDryRun = false
A.TwichUIDB.modules.partyPins = false
A.TwichUIDB.modules.setupSharing = true
A.TwichUIDB.modules.restedxpSkin = true
A.TwichUI.GearPrefs.Get("reveal")
A.TwichUIDB.gear.trees = { ["Rich-Forever"] = 6 }
A.TwichUIDB.shareTransport = "GUILD"
A.TwichUIDB.pins = { list = { { id = 1, name = "SECRET-PIN-NAME" } }, nextId = 2 }
A.TwichUIChronicleDB = { version = 1, chars = { ["Rich - Forever"] = { entries = { { kind = "note", text = "SECRET-NOTE" } } } } }
A.TwichUIRestoreDB = { points = { { id = "1", name = "SECRET-BACKUP", created = 1, tables = { FooDB = { owner = "Foo", data = { secret = "SECRET-RESTORE" } } } } } }
A.TwichUIBackupDB["Rich - Forever"] = { tables = { FooDB = { present = true, data = { secret = "SECRET-UNDO" } } }, created = 1, stamp = 1 }
A.TwichUIDB.setup.received["Old-Forever"] = { created = 1, version = 1, tables = {}, sourceName = "SECRET-SENDER",
  twichui = { schema = 1, status = "ok", groups = { food = { foodDrink = { size = 30 } } } } }

-- stat weights for two trees
A.TwichUIDB.gear.weights = { MAGE = { [6] = { SP = 2.5, CRIT = 9 } } }
A.TwichUIDB.gear.priority = { MAGE = { [6] = { "SP", "CRIT", "HIT" } } }
A.TwichUIDB.gear.usePriority = { MAGE = { [6] = true } }

local B, SB = Boot("Bob")
local BTC = B.TwichUI.TwichConfig
-- B's own customised state, which an import must replace only where the share speaks
B.TwichUI.FoodDrink.Set("size", 30); B.TwichUI.FoodDrink.Set("showCount", true); B.TwichUI.FoodDrink.Set("spacing", 10)
B.TwichUI:SetEnabled("welcomeBack", true)
B.TwichUI.GearPrefs.Get("reveal")   -- the gear table is made on first use
B.TwichUIDB.gear.weights = { WARRIOR = { [1] = { STR = 3 } }, MAGE = { [6] = { SP = 1.1 } } }
B.TwichUIDB.ui.foodDrinkPosition = { x = -50, y = -50 }
B.TwichUIDB.modules.qolSummons = false

-- A saves with TwichUI included (no scan this session: the live parts only)
Check(A.TwichUI.Setups:SaveMine(false) == 0, "without TwichUI ticked and without a scan, nothing is saved")
TC.SetIncluded(true)
TC.SetGroupSelected("pinsLook", false)
Check(A.TwichUI.Setups:SaveMine(false) >= 1, "with TwichUI ticked, a save needs no scan")
local mine = A.TwichUI.Setups.Mine()
Check(mine and mine.twichui and mine.twichui.status == "ok", "the saved setup holds TwichUI's settings")
Check(mine.twichui.groups.pinsLook == nil and mine.twichui.groups.food ~= nil, "a feature left unticked is not in it")

-- nothing that stays local, and no data of any kind, is in what is sent
do
  local offer = A.TwichUI.Share.BuildOffer(mine, "1")
  local data = A.TwichUI.Share.BuildData(mine, "1", {}, false)
  Check(type(offer.twichui) == "table" and offer.twichui.groups > 5, "the offer says TwichUI's settings are there")
  local LibSerialize = A.LibStub("LibSerialize")
  local blob = LibSerialize:Serialize({ offer, data })
  for _, secret in ipairs({ "SECRET-PIN-NAME", "SECRET-NOTE", "SECRET-BACKUP", "SECRET-RESTORE", "SECRET-UNDO", "SECRET-SENDER",
      "Player-1-Sentinel", "GUILD" }) do
    Check(not blob:find(secret, 1, true), "the payload does not carry " .. secret)
  end
  local function Walk(t, path, found)
    for k, v in pairs(t) do
      local p = path .. "." .. tostring(k)
      if type(v) == "table" then Walk(v, p, found) end
      found[#found + 1] = tostring(k)
    end
    return found
  end
  local keys = {}
  for _, k in ipairs(Walk(data.twichui, "twichui", {})) do keys[k] = true end
  -- ("pins" and "qol" are feature names here, not the saved tables of those names)
  for _, name in ipairs({ "shareTransport", "profiles", "profileKeys", "profileState", "setup", "trees", "position",
      "foodDrinkPosition", "trainingPosition", "settingsWindow", "guideWaypoint", "mageSell", "qolSummons",
      "mageSellDryRun", "welcome", "received", "points", "chars", "never", "summonsFrom" }) do
    Check(not keys[name], "the payload has no key " .. name)
  end
  Check(data.twichui.groups.mage.modules.mageSell == nil and data.twichui.groups.mage.modules.mageRefreshmentsAutoFill == nil,
    "selling and auto-fill are not in it")
  Check(data.twichui.groups.qol.modules.qolSummons == nil and data.twichui.groups.qol.modules.qolQuickKeybind ~= nil,
    "only the quick keybind button of Quality of life is in it")
  Check(data.twichui.groups.general.modules.quietLogin == false, "a false value is carried")
  Check(data.twichui.groups.food.foodDrink.zoom == 0 and data.twichui.groups.food.foodDrink.spacing == 0, "zero values are carried")
  Check(data.twichui.groups.restedxp.restedxpSkin.bgOpacity == 40 and not data.twichui.groups.restedxp.modules, "the RestedXP look, not its switch")
  Check(data.twichui.groups.pins.modules == nil, "whether party pins are on is not in it")
  Check(data.twichui.groups.gearWeights.units[1].class == "MAGE", "the stat weights travel by class and tree")
  Check(data.twichui.groups.gearWeights.units[1].use == true, "weighing by ranking travels")
  -- size is the settings' size
  local size = #LibSerialize:Serialize(data.twichui)
  Check(size < 12000, "the TwichUI part is small (" .. size .. " bytes serialized)")
end

A.TwichUIDB.shareTransport = "DIRECT"   -- (the sentinel above was checked; the send below goes direct)

-- size does not grow with history, backups or received setups
do
  local LibSerialize = A.LibStub("LibSerialize")
  local before = #LibSerialize:Serialize(TC.Build({ all = true }).groups)
  local big = {}
  for i = 1, 4000 do big[i] = { kind = "note", text = ("history entry %d "):format(i):rep(8) } end
  A.TwichUIChronicleDB.chars["Rich - Forever"].entries = big
  for i = 1, 30 do A.TwichUIBackupDB["Char" .. i .. " - Forever"] = { tables = { X = { present = true, data = big } }, created = 1 } end
  A.TwichUIDB.setup.received["Big-Forever"] = { created = 1, version = 1, tables = { BigDB = { owner = "Foo", data = big } },
    twichui = { schema = 1, status = "ok", groups = {} } }
  local after = #LibSerialize:Serialize(TC.Build({ all = true }).groups)
  Check(before == after, "the exported size is the same with and without a large history")
  A.TwichUIDB.setup.received["Big-Forever"] = nil
  for i = 1, 30 do A.TwichUIBackupDB["Char" .. i .. " - Forever"] = nil end
  A.TwichUIChronicleDB.chars["Rich - Forever"].entries = { { kind = "note", text = "SECRET-NOTE" } }
end

-- the real send, receive and store
Check(A.TwichUI.Share:SendTo("Bob"))
Pumped()
local inc = B.TwichUI.Share.incoming["Rich-Forever"]
Check(inc and inc.stage == "asking", "Bob is asked")
Check(type(inc.offer.twichui) == "table", "the offer Bob sees names TwichUI's settings")
B.TwichUI.Share:Respond("Rich-Forever", true)
Pumped(); Pumped()
Check(A.TwichUI.Share.outgoing.stage == "done", "the send finished")
local pack = B.TwichUIDB.setup.received["Rich-Forever"]
Check(pack and pack.twichui and pack.twichui.status == "ok", "Bob received TwichUI's settings")
Check(pack.twichui.rejected and next(pack.twichui.rejected) == nil and pack.twichui.unknown == 0, "nothing was dropped")

-- review
local plan = BTC.Plan(pack.twichui)
Check(plan.ok and plan.changed > 20, "the review lists what would change (" .. tostring(plan.changed) .. ")")
Check(plan.profile == "Default" and plan.sharedWith == 0, "it says which profile it would change")
local reloadNames = table.concat(plan.reload, ",")
Check(reloadNames:find("Attune") and reloadNames:find("Whats training") and reloadNames:find("Quiet login"), "it names the changes that need a reload: " .. reloadNames)
Check(not reloadNames:find("Auction"), "a switch that takes effect at once is not a reload")
local byId = {}
for _, g in ipairs(plan.groups) do byId[g.id] = g end
Check(byId.food and byId.food.state == "changed" and #byId.food.changes >= 5, "Food and drink shows its changes")
Check(byId.gearWeights and byId.gearWeights.state == "changed" and byId.gearWeights.scope == "account", "stat weights are shown as account-wide")
Check(#plan.absent == 1 and plan.absent[1] == "Pin appearance", "what the sender left out is said: " .. table.concat(plan.absent, ","))
local beforeApply = Copy(B.TwichUIDB)
-- a review changes nothing
Check(Same(beforeApply, B.TwichUIDB), "reviewing changed nothing")

-- combat: refused, nothing changes
B.combat = true
local ok, code = BTC.Apply(pack.twichui, { from = "Rich" })
Check(ok == false and code == "combat", "refused in combat")
Check(Same(beforeApply, B.TwichUIDB), "a refusal changed nothing")
B.combat = false

-- apply
local SnapBefore = Copy(B.TwichUIDB.profiles)
local ok2, report = BTC.Apply(pack.twichui, { from = "Rich" })
Check(ok2 == true and report.changed == plan.changed, "applied: " .. tostring(report))
Check(B.TwichUI.FoodDrink.Get("size") == 48 and B.TwichUI.FoodDrink.Get("spacing") == 0 and B.TwichUI.FoodDrink.Get("showCount") == false,
  "the feature follows at once")
Check(B.TwichUI:Enabled("welcomeBack") == false and B.TwichUI:Enabled("chronicleDeaths") == true, "switches follow, including off")
Check(B.TwichUI.Switches.ReloadPending(), "a reload is pending for the skins")
Check(#report.reload >= 3, "the report names the reloads")
-- B now uses exactly A's shared configuration, group by group (the pinsLook group was not shared, so it is B's own)
do
  local a, b = Everything(A), Everything(B)
  for id, data in pairs(mine.twichui.groups) do
    if id == "gearWeights" then
      -- B keeps its own entry for a class and tree the sender has none for
      Check(#b[id].units == 2 and b[id].units[2].class == "WARRIOR" and Same(b[id].units[1], a[id].units[1]),
        "stat weights: the shared tree matches, the other stays")
    else
      Check(Same(a[id], b[id]), "group " .. id .. " matches the sender's")
    end
  end
end
-- what must stay B's own
Check(B.TwichUIDB.ui.foodDrinkPosition.x == -50, "B's own place is untouched")
Check(B.TwichUIDB.modules.qolSummons == false and B.TwichUIDB.shareTransport == "DIRECT", "B's acts-for-you and sending choices are untouched")
Check(B.TwichUIDB.gear.weights.WARRIOR and B.TwichUIDB.gear.weights.WARRIOR[1].STR == 3, "another class's weights are untouched")
Check(B.TwichUIDB.gear.weights.MAGE[6].SP == 2.5 and B.TwichUIDB.gear.priority.MAGE[6][1] == "SP", "the shared tree's weights are replaced")
Check(B.TwichUIDB.gear.usePriority.MAGE[6] == true, "and its ranking choice")
Check(B.TwichUIDB.gear.trees == nil or next(B.TwichUIDB.gear.trees) == nil or B.TwichUIDB.gear.trees["Rich-Forever"] == nil, "no talent tree choice came across")
Check(B.TwichUIDB.schema == 2 and B.TwichUIDB.profileState.live == "Default", "profile bookkeeping is untouched")
Check(Same(SnapBefore, B.TwichUIDB.profiles), "other stored profiles are untouched")

-- Undo puts it all back
do
  Check(BTC.UndoInfo() and BTC.UndoInfo().here, "an Undo copy is kept")
  local okU, rep = BTC.Undo()
  Check(okU == true and rep.restored > 20, "undo restores")
  Check(B.TwichUI.FoodDrink.Get("size") == 30 and B.TwichUI.FoodDrink.Get("spacing") == 10 and B.TwichUI.FoodDrink.Get("showCount") == true,
    "undone: the feature follows")
  Check(B.TwichUI:Enabled("welcomeBack") == true, "undone: switches")
  Check(B.TwichUIDB.gear.weights.MAGE[6].SP == 1.1 and B.TwichUIDB.gear.priority.MAGE == nil and B.TwichUIDB.gear.usePriority.MAGE == nil,
    "undone: weights")
  Check(BTC.UndoInfo() == nil, "the Undo copy is spent")
  -- the whole saved settings are what they were, apart from keys that appeared as defaults
  Check(B.TwichUI.TwichConfig.Build({ all = true }).groups.food.foodDrink.size == 30, "undone: exported values")
end

---------------------------------------------------------------------------
-- 3. Profile scope: other profiles and other characters are untouched; a new profile keeps the old one
---------------------------------------------------------------------------
do
  local C = Boot("Cleo")
  local CT = C.TwichUI.TwichConfig
  local PF = C.TwichUI.Profiles
  -- a second profile used by another character
  local okD = PF.Duplicate("Raid")        -- this character now uses "Raid"; "Default" is stored as it was
  Check(okD, "set up: a second profile")
  C.TwichUI.FoodDrink.Set("size", 40)
  PF.Switch("Default")
  C.TwichUIDB.profileKeys["Other - Forever"] = "Raid"
  local rawRaid = Copy(C.TwichUIDB.profiles.Raid)
  local entry = CT.CleanEntry({ schema = 1, groups = { food = { foodDrink = { size = 60 } }, general = { modules = { quietLogin = false } } } })
  Check(entry.status == "ok" and entry.unknown == 0, "a hand-made entry reads")
  local p = CT.Plan(entry)
  Check(p.ok and p.changed == 2 and p.sharedWith == 0, "two changes planned")
  -- to the profile in use
  local okA, rep = CT.Apply(entry, { from = "Rich" })
  Check(okA and C.TwichUI.FoodDrink.Get("size") == 60, "applied to the profile in use")
  Check(Same(rawRaid, C.TwichUIDB.profiles.Raid), "the other profile is untouched")
  Check(C.TwichUIDB.profileKeys["Other - Forever"] == "Raid", "another character's choice is untouched")
  CT.Undo()
  Check(C.TwichUI.FoodDrink.Get("size") ~= 60, "undone")
  -- to a new profile: the old one is kept exactly as it was
  local before = Copy(C.TwichUIDB.ui.foodDrink or {})
  local okN, repN = CT.Apply(entry, { from = "Rich", newProfile = true })
  Check(okN and repN.newProfile == "From Rich" and PF.Current() == "From Rich", "applied to a new profile named for the sender")
  Check(C.TwichUI.FoodDrink.Get("size") == 60, "the new profile has the shared values")
  PF.Switch("Default")
  Check(Same(before, C.TwichUIDB.ui.foodDrink or {}), "the profile it was made from is exactly as it was")
  Check(C.TwichUIDB.profileKeys["Other - Forever"] == "Raid" and Same(rawRaid, C.TwichUIDB.profiles.Raid), "and other characters' are still untouched")
  -- undo is for the profile it changed
  PF.Switch("From Rich")
  PF.Switch("Default")
  local okU, whyU, extra = CT.Undo()
  Check(okU == false and whyU == "profile" and extra == "From Rich", "undo waits for the profile it changed")
end

---------------------------------------------------------------------------
-- 4. Defaulted settings: a sender who never changed anything sends the defaults
---------------------------------------------------------------------------
do
  local D = Boot("Dana")
  local DT = D.TwichUI.TwichConfig
  local fresh = DT.Build({ all = true })
  local E = Boot("Eli")
  E.TwichUI.FoodDrink.Set("size", 60); E.TwichUI.FoodDrink.Set("borderColor", "ff000000")
  E.TwichUI:SetEnabled("chronicleDeaths", true)
  local ok = E.TwichUI.TwichConfig.Apply(DT.CleanEntry(fresh), { from = "Dana" })
  Check(ok, "a share of defaults applies")
  Check(E.TwichUI.FoodDrink.Get("size") == 36 and E.TwichUI.FoodDrink.Get("borderColor") == "ff8c6e38", "the receiver's custom values go back to what the sender uses")
  Check(E.TwichUI:Enabled("chronicleDeaths") == false, "and a switch is the sender's default")
end

---------------------------------------------------------------------------
-- 5. Invalid, unknown, older and newer payloads
---------------------------------------------------------------------------
do
  local X = Boot("Xena")
  local XT = X.TwichUI.TwichConfig
  local function Clean(t) return XT.CleanEntry(t) end
  -- newer / older / not an entry
  local newer = Clean({ schema = 99, groups = { food = { foodDrink = { size = 40 } } } })
  Check(newer.status == "newer" and next(newer.groups or {}) == nil, "a newer payload schema is not read")
  local pn = XT.Plan(newer)
  Check(not pn.ok and pn.why:find("newer"), "and the review says so")
  local okN, codeN = XT.Apply(newer, {})
  Check(okN == false and codeN == "none", "and it cannot be applied")
  Check(Clean({ schema = 0, groups = {} }).status == "damaged", "schema 0 is not a payload")
  Check(Clean({ groups = {} }).status == "damaged", "no schema is not a payload")
  Check(Clean("text").status == "damaged" and Clean(5).status == "damaged", "not a table")
  Check(Clean(nil) == nil, "nothing is nothing")
  Check(Clean({ schema = 1, groups = "x" }).status == "damaged", "groups must be a table")
  -- unknown group, unknown key: ignored and counted; the rest applies
  local mixed = Clean({ schema = 1, groups = {
    nothingLikeThis = { a = { b = 1 } },
    food = { foodDrink = { size = 44, madeUpKey = 5 }, notASlot = { size = 1 } },
    general = { modules = { quietLogin = false, setupSharing = false, mageSell = true } },
  } })
  Check(mixed.status == "ok" and mixed.unknown == 5, "unknown things are counted (" .. tostring(mixed.unknown) .. ")")
  Check(mixed.groups.food.foodDrink.size == 44 and mixed.groups.food.foodDrink.madeUpKey == nil, "the known value is kept")
  Check(mixed.groups.general.modules.quietLogin == false and mixed.groups.general.modules.setupSharing == nil
    and mixed.groups.general.modules.mageSell == nil, "a switch that is kept local is never read, even if it is named")
  -- one bad value skips its whole group; other groups still apply; nothing half-applied
  local bad = Clean({ schema = 1, groups = {
    food = { foodDrink = { size = 9999, spacing = 3 } },
    notifications = { modules = { arrival = false }, ui = { arrivalHold = "short" } },
  } })
  Check(bad.rejected.food and bad.groups.food == nil, "a group with a value out of range is dropped whole")
  Check(bad.groups.notifications == nil and bad.rejected.notifications, "an unknown choice drops its group")
  local before = Copy(X.TwichUIDB)
  local pbad = XT.Plan(bad)
  Check(not pbad.ok or pbad.changed == 0, "nothing in it can be applied")
  Check(Same(before, X.TwichUIDB), "planning changed nothing")
  local mix2 = Clean({ schema = 1, groups = {
    food = { foodDrink = { size = 9999 } },
    auction = { modules = { auctionPosting = false } },
  } })
  Check(mix2.rejected.food and mix2.groups.auction, "the valid group stays")
  local okM = XT.Apply(mix2, {})
  Check(okM and X.TwichUI:Enabled("auctionPosting") == false and X.TwichUI.FoodDrink.Get("size") == 36, "only the valid group was applied")
  -- wrong types, nan, functions, tables where numbers go, cycles
  local cyc = {}; cyc.me = cyc
  for name, v in pairs({ text = "big", nan = 0 / 0, inf = math.huge, fn = function() end, tbl = {}, cyc = cyc, neg = -1, frac = 40.5, bool = true }) do
    local e = Clean({ schema = 1, groups = { food = { foodDrink = { size = v } } } })
    Check(e.groups.food == nil and e.rejected.food, "size = " .. name .. " is refused")
  end
  Check(Clean({ schema = 1, groups = { food = { foodDrink = { borderColor = "red" } } } }).rejected.food, "a colour has to be a colour")
  Check(Clean({ schema = 1, groups = { food = { foodDrink = { layout = "diagonal" } } } }).rejected.food, "a choice has to be one of the choices")
  Check(Clean({ schema = 1, groups = { food = { foodDrink = { borderTexture = ("x"):rep(500) } } } }).rejected.food, "a name has a length")
  Check(Clean({ schema = 1, groups = { food = { foodDrink = { borderTexture = "a|cffff0000b" } } } }).rejected.food, "and no colour codes")
  Check(Clean({ schema = 1, groups = { food = { foodDrink = "oops" } } }).rejected.food, "a slot has to be a table")
  -- the two pin clicks never share a pin
  Check(Clean({ schema = 1, groups = { pins = { partyPins = { localClick = "alt", partyClick = "alt" } } } }).rejected.pins, "the same click twice is refused")
  Check(Clean({ schema = 1, groups = { pins = { partyPins = { localClick = "none", partyClick = "none" } } } }).groups.pins, "both off is fine")
  -- bounded
  local many = { schema = 1, groups = { food = { foodDrink = {} } } }
  for i = 1, 1500 do many.groups.food.foodDrink["k" .. i] = i end
  Check(Clean(many).status == "damaged", "an entry past the value limit is refused")
  -- stat weights
  local function W(units) return Clean({ schema = 1, groups = { gearWeights = { units = units } } }) end
  Check(W({ { class = "MAGE", line = 6, weights = { SP = 2 } } }).groups.gearWeights, "weights read")
  Check(W({ { class = "MAGE", line = 6, weights = { NOTASTAT = 2 } } }).rejected.gearWeights, "an unknown stat is refused")
  Check(W({ { class = "MAGE", line = 6, weights = { SP = -1 } } }).rejected.gearWeights, "a negative weight is refused")
  Check(W({ { class = "MAGE", line = 6, weights = { SP = 5000 } } }).rejected.gearWeights, "a huge weight is refused")
  Check(W({ { class = "mage", line = 6, weights = { SP = 2 } } }).rejected.gearWeights, "a class is a class file name")
  Check(W({ { class = "MAGE", line = 6, priority = { "SP", "SP" } } }).rejected.gearWeights, "a ranking has no repeats")
  Check(W({ { class = "MAGE", line = 6, priority = { "ARMOR" } } }).rejected.gearWeights, "a stat that can't be ranked is refused")
  Check(W({ { class = "MAGE", line = 6, use = "yes" } }).rejected.gearWeights, "and a choice is a boolean")
  Check(W({ { class = "MAGE", line = 6, weights = { SP = 2 } }, { class = "MAGE", line = 6, weights = { SP = 3 } } }).rejected.gearWeights, "a tree twice is refused")
  Check(Clean({ schema = 1, groups = { gearWeights = "x" } }).rejected.gearWeights, "weights in the wrong shape")
end

-- looping or oversized input of every shape is refused without running away
do
  local X = Boot("Yan")
  local XT = X.TwichUI.TwichConfig
  local cyc = { class = "MAGE", line = 6 }
  cyc.weights = cyc
  local function Refused(e) return e.status == "damaged" or (e.rejected and e.rejected.gearWeights) end
  Check(Refused(XT.CleanEntry({ schema = 1, groups = { gearWeights = { units = { cyc } } } })), "a looping stat weights table is refused")
  local deep = {}
  local t = deep
  for _ = 1, 40 do t.next = {}; t = t.next end
  Check(Refused(XT.CleanEntry({ schema = 1, groups = { gearWeights = deep } })), "a deep one is refused")
  local lots = { schema = 1, groups = {} }
  for i = 1, 5000 do lots.groups["g" .. i] = { a = 1 } end
  Check(XT.CleanEntry(lots).status == "damaged", "thousands of unknown groups are refused, not walked")
  local ranked = { class = "MAGE", line = 6, priority = {} }
  for i = 1, 200 do ranked.priority[i] = "SP" end
  Check(Refused(XT.CleanEntry({ schema = 1, groups = { gearWeights = { units = { ranked } } } })), "a long ranking is refused")
  -- ticked, but with every feature left out: nothing to save
  XT.SetIncluded(true)
  for _, g in ipairs(XT.Groups()) do XT.SetGroupSelected(g.id, false) end
  Check(XT.Included() and not XT.WillInclude(), "ticked with nothing chosen includes nothing")
  Check(X.TwichUI.Setups:SaveMine(false) == 0, "and a save has nothing to save")
end

-- a setup from a newer TwichUI: the note is kept, nothing is taken from it
do
  local Q = Boot("Nell")
  Q.TwichUI.Share.incoming["Pia-Forever"] = { id = "1", stage = "receiving", got = 0, expected = 0, route = { "WHISPER", "Pia-Forever" } }
  Q.TwichUI.Share.handlers.data("Pia-Forever", { t = "data", p = 2, id = "1", meta = { created = 1, version = 1 }, keep = {}, tables = {},
    twichui = { schema = 7, groups = { food = { foodDrink = { size = 40 } } }, future = { x = 1 } } })
  local pack = Q.TwichUIDB.setup.received["Pia-Forever"]
  Check(pack and pack.twichui and pack.twichui.status == "newer" and pack.twichui.schema == 7 and pack.twichui.groups == nil,
    "a newer TwichUI's settings are kept as a note, nothing more")
  Check(not Q.TwichUI.TwichConfig.Plan(pack.twichui).ok, "and the review says it can't be read")
end

---------------------------------------------------------------------------
-- 6. What is stored: shape checks at load, the pack's own checks, the saved-data list
---------------------------------------------------------------------------
do
  local Z = Boot("Zed", function(c)
    c.TwichUIDB = { schema = 2, setup = { twichui = "oops", twichUndo = { profile = 5 } },
      profileState = { live = "Default", newCharacters = "Default" }, profiles = {}, profileKeys = {} }
    c.TwichUIShareDB = { pack = { created = 1, version = 1, tables = {}, twichui = "not a table" } }
  end)
  Check(Z.TwichUIDB.setup.twichui == nil and Z.TwichUIDB.setup.twichUndo == nil, "garbage selection and Undo copy are dropped at load")
  Check(Z.TwichUIShareDB.pack.twichui == nil, "a pack whose TwichUI part is not a table loses it")
  Check(Z.TwichUI.TwichConfig.Included() == false and Z.TwichUI.TwichConfig.UndoInfo() == nil, "and nothing is broken")
  Check(Z.TwichUI.Setups.ValidName("TwichUIDB") == false and Z.TwichUI.Setups.ValidName("TwichUIShareDB") == false,
    "TwichUI's own saved tables are still refused as settings tables")
end

-- the saved-data list shows the Undo copy
do
  local items = B.TwichUI.Setups.StorageItems()
  local found = false
  for _, it in ipairs(items) do if it.key == "twichui-undo" then found = true end end
  Check(not found, "no Undo copy, none listed")
  local pack2 = B.TwichUIDB.setup.received["Rich-Forever"]
  B.TwichUI.TwichConfig.Apply(pack2.twichui, { from = "Rich" })
  items = B.TwichUI.Setups.StorageItems()
  for _, it in ipairs(items) do if it.key == "twichui-undo" then found = it end end
  Check(found and found.bytes > 0, "an Undo copy is listed with its size")
  found.remove()
  Check(B.TwichUI.TwichConfig.UndoInfo() == nil, "and can be deleted")
end

---------------------------------------------------------------------------
-- 7. The rest of sharing is as it was
---------------------------------------------------------------------------
do
  local P, Q = Boot("Pia"), Boot("Quin")
  P.FooDB = { scale = 2, nested = { a = true } }
  P.TwichUI.Setups.capture = { FooDB = { owner = "Foo", data = Copy(P.FooDB) } }
  P.TwichUIDB.setup.selection.FooDB = true
  Check(P.TwichUI.Setups:SaveMine(false) == 1, "a table-only setup saves as before")
  Check(P.TwichUI.Setups.Mine().twichui == nil, "and carries no TwichUI part when none is ticked")
  Check(P.TwichUI.Share:SendTo("Quin")); Pumped()
  Q.TwichUI.Share:Respond("Pia-Forever", true); Pumped(); Pumped()
  local got = Q.TwichUIDB.setup.received["Pia-Forever"]
  Check(got and got.tables.FooDB and got.tables.FooDB.data.scale == 2 and got.twichui == nil, "tables arrive, with no TwichUI part")
  Check(P.TwichUI.Share.outgoing.stage == "done", "the send completes")
  -- a table named for TwichUI is still refused on arrival
  local bad = { t = "data", p = 2, id = "1", meta = { created = 1, version = 1 }, keep = { TwichUIDB = { owner = "Foo" } }, tables = { TwichUIDB = { owner = "Foo", data = { x = 1 } } } }
  Q.TwichUI.Share.incoming["Pia-Forever"] = { id = "1", stage = "receiving", got = 0, expected = 0 }
  Q.TwichUI.Share.handlers.data("Pia-Forever", bad)
  Check(Q.TwichUI.Share.incoming["Pia-Forever"].stage == "failed", "a setup naming TwichUI's own table is refused")
  -- the TwichUI part alone is a setup (nothing else needed)
  local alone = Boot("Rae")
  alone.TwichUI.TwichConfig.SetIncluded(true)
  Check(alone.TwichUI.Setups:SaveMine(false) >= 1 and next(alone.TwichUI.Setups.Mine().tables) == nil, "a setup of TwichUI's settings alone")
  local ok = alone.TwichUI.Share:SendTo("Quin")
  Check(ok == true, "and it can be sent")
  Pumped()
  Q.TwichUI.Share:Respond("Rae-Forever", true); Pumped(); Pumped()
  Check(Q.TwichUIDB.setup.received["Rae-Forever"] and Q.TwichUIDB.setup.received["Rae-Forever"].twichui.status == "ok", "and received")
  -- a receiver whose payload is damaged keeps a note, not a crash
  local pack = { created = 1, version = 1, tables = {}, sourceName = "x", twichui = { status = "ok" } }
  Q.TwichUIDB.setup.received["Odd-Forever"] = pack
  Q.TwichUI.Setups.NormalizeDb(Q.TwichUIDB.setup)
  Check(Q.TwichUIDB.setup.received["Odd-Forever"].twichui == nil, "an entry with no groups is dropped at load")
end

---------------------------------------------------------------------------
-- 8. The window code runs with real data (a smoke test: the frames are stand-ins, so what is drawn is the
--    in-game check)
---------------------------------------------------------------------------
do
  local W
  local ok, err = pcall(function()
    local c = B
    c.UISpecialFrames = c.UISpecialFrames or {}
    c.tinsert = table.insert
    c.GameTooltip = setmetatable({}, { __index = function() return function() end end })
    c.GameTooltip_Hide = function() end
    c.ACCEPT, c.CANCEL = "Accept", "Cancel"
    c.UnitIsPlayer = function() return false end
    local chunk = assert(loadfile(ROOT .. "setup/Window.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
    W = c.TwichUI.Window
    c.TwichUI.TwichConfig.SetIncluded(true)
    W:Show("share"); W:ShowChoose()
    W:Refresh()
    W:Show("received")
    W:ShowTwichImport({ key = "recv:Rich-Forever", from = "Rich" })
    W:Refresh()
    -- the one that can't be read, and one that is gone
    c.TwichUIDB.setup.received["Odd-Forever"] = { created = 1, version = 1, tables = {}, sourceName = "Odd", twichui = { schema = 9, status = "newer" } }
    W:ShowTwichImport({ key = "recv:Odd-Forever", from = "Odd" })
    W:ShowTwichImport({ key = "recv:Nobody-Forever", from = "Nobody" })
    W:AskAccept("Rich-Forever", { addons = 2, bytes = 1000, twichui = { schema = 1, groups = 5 } })
  end)
  Check(ok, "the sharing window draws TwichUI's settings: " .. tostring(err))
end

if failures > 0 then
  print(failures .. " check(s) failed")
  error("test_twichui_share failed")
end
print("TWICHUI SHARE PASSED")
