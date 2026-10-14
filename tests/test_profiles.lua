dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Profiles (Profiles.lua, Persist.lua schema 2, TwichUI_Settings/pages/Profiles.lua): the upgrade from a real v3.0.12 save, every
-- operation, names, independence of copies, what is never part of a profile, combat, characters sharing a profile
-- or not across sessions, a missing or late choice, damaged saved data, and that a change tells each part once.
-- All data is synthetic. These exercise TwichUI's own code paths; the game's panel, combat lockdown and
-- protected frames are for the in-game checks in docs/profiles.md.

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do out[copy(k, seen)] = copy(v, seen) end
  return out
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Whether two values share any table (a copy must share none).
local function shares(a, b)
  local seen = {}
  local function walk(t) if type(t) == "table" and not seen[t] then seen[t] = true for _, v in pairs(t) do walk(v) end end end
  walk(a)
  local found = false
  local visited = {}
  local function look(t)
    if type(t) ~= "table" or visited[t] then return end
    visited[t] = true
    if seen[t] then found = true return end
    for _, v in pairs(t) do look(v) end
  end
  look(b)
  return found
end

local SV = { "TwichUIDB", "TwichUIBackupDB", "TwichUIShareDB", "TwichUIRestoreDB", "TwichUIChronicleDB" }

local function Boot(name, sv, before)
  local c, S = SettingsClient({ name = name, beforeInit = function(c)
    for k, v in pairs(sv or {}) do c[k] = v end
    c.said = {}
    c.print = function(s) c.said[#c.said + 1] = tostring(s) end
    c.combat = false
    c.InCombatLockdown = function() return c.combat end
    if before then before(c) end
  end })
  c.popups = {}
  local base = c.StaticPopup_Show
  c.StaticPopup_Show = function(which, a1, a2, data)
    c.popups[#c.popups + 1] = { which = which, text = a1, data = data }
    return base(which, a1, a2, data)
  end
  return c, S
end

local function Logout(c)
  c.FireEvent("PLAYER_LOGOUT")
  local s = {}
  for _, n in ipairs(SV) do s[n] = copy(c[n]) end
  return s
end

local function heard(c, text)
  for _, s in ipairs(c.said) do if s:find(text, 1, true) then return true end end
  return false
end

local function find(S, page, name)
  for _, cat in ipairs(S.pages) do
    if cat.name == page then
      for _, row in ipairs(cat.rows) do if row.data and row.data.name == name then return row end end
    end
  end
end

local function options(S, variable)
  local list = {}
  for _, o in ipairs(S.variables[variable].options()) do list[#list + 1] = o.value end
  return list
end

---------------------------------------------------------------------------
-- 1. Upgrading a real v3.0.12 save: the settings every character shared become "Default", where they are
---------------------------------------------------------------------------
local fixture = dofile(TESTS .. "fixtures/saved_v3.0.12.lua")
local c, S = Boot("Rich", copy(fixture))
local R, PF, P = c.TwichUI, c.TwichUI.Profiles, c.TwichUI.Persist
local db = c.TwichUIDB
assert(db.schema == 2 and P.Report().main.outcome == "migrated" and P.Report().main.stored == 1, "schema 1 is upgraded to 2")
assert(PF.Available() and PF.Current() == "Default" and PF.Character() == "Rich - Forever")
assert(db.profileState.live == "Default" and db.profileState.newCharacters == "Default")
assert(next(db.profiles) == nil and db.profileKeys["Rich - Forever"] == "Default", "no other profile; this character's choice is remembered")
local want = fixture.TwichUIDB
for k, v in pairs(want.modules) do assert(db.modules[k] == v, "modules." .. k .. " kept") end
for k, v in pairs(want.ui) do
  if k == "showAdvanced" then
    assert(db.ui[k] == nil, "ui.showAdvanced (the removed 'Show advanced options') is dropped")
  else
    assert(same(db.ui[k], v), "ui." .. k .. " kept")
  end
end
db.ui.reduceSettingsMotion = true   -- an account-wide option that is still current
for k, v in pairs(want.gear) do assert(same(db.gear[k], v), "gear." .. k .. " kept") end
assert(same(db.pins, want.pins) and db.pins.list[1].kept == true, "pins and their kept state are untouched")
assert(same(db.setup, want.setup) and db.shareTransport == want.shareTransport)
local noted = false
for _, e in ipairs(c.TwichUIChronicleDB.chars["Rich - Forever"].entries) do if e.note == "written on v3.0.12" then noted = true end end
assert(noted, "the Chronicle note is there")
assert(P.Report().lost == 0 and not heard(c, "reset or set aside"), "an ordinary upgrade loses and says nothing")

-- The step is repeatable: run on its own result, it changes nothing.
local again = copy(db)
P.STEPS[2](again)
assert(same(again, db), "step 2 changes nothing the second time")

-- A reload: the same profile, nothing moved, nothing new.
local save = Logout(c)
local c2 = Boot("Rich", copy(save))
assert(c2.TwichUI.Profiles.Current() == "Default" and c2.TwichUI.Persist.Report().main.outcome == "current")
assert(same(c2.TwichUIDB.modules, save.TwichUIDB.modules) and same(c2.TwichUIDB.ui, save.TwichUIDB.ui)
  and same(c2.TwichUIDB.profiles, save.TwichUIDB.profiles) and same(c2.TwichUIDB.profileKeys, save.TwichUIDB.profileKeys), "a reload changes nothing")

---------------------------------------------------------------------------
-- 2. Operations
---------------------------------------------------------------------------
local modulesTable, uiTable, gearTable = db.modules, db.ui, db.gear
db.ui.restedxpSkinState = { previousTheme = "RXP Blue" }
db.ui.guideWaypoint = { ["Player-1-Rich"] = { map = 1429, x = 0.5, y = 0.5 } }
db.gear.trees["Rich-Forever"] = 6
local before = {
  pins = copy(db.pins), chronicle = copy(c.TwichUIChronicleDB), setup = copy(db.setup), backups = copy(c.TwichUIBackupDB),
  restore = copy(c.TwichUIRestoreDB), share = copy(c.TwichUIShareDB), weights = copy(db.gear.weights), trees = copy(db.gear.trees),
  sell = copy(db.ui.mageSell), rxpState = copy(db.ui.restedxpSkinState), waypoint = copy(db.ui.guideWaypoint),
  transport = db.shareTransport, welcome = copy(db.welcome), rxpSwitch = db.modules.restedxpSkin,
}
local function untouched(tag)
  assert(same(db.pins, before.pins) and db.pins.list[1].kept == true, tag .. ": pins, kept ones included, untouched")
  assert(same(c.TwichUIChronicleDB, before.chronicle), tag .. ": the Chronicle untouched")
  assert(same(db.setup, before.setup) and same(c.TwichUIBackupDB, before.backups) and same(c.TwichUIRestoreDB, before.restore)
    and same(c.TwichUIShareDB, before.share), tag .. ": setups, Undo copies, backups and your saved setup untouched")
  assert(same(db.gear.weights, before.weights) and same(db.gear.trees, before.trees), tag .. ": stat weights and tree choices untouched")
  assert(same(db.ui.mageSell, before.sell), tag .. ": the never-sell list untouched")
  assert(same(db.ui.restedxpSkinState, before.rxpState) and same(db.ui.guideWaypoint, before.waypoint), tag .. ": per-character and third-party records untouched")
  assert(db.ui.reduceSettingsMotion == true and db.modules.restedxpSkin == before.rxpSwitch, tag .. ": account-wide options untouched")
  assert(db.shareTransport == before.transport and same(db.welcome, before.welcome), tag .. ": sending method and welcome untouched")
  assert(db.modules == modulesTable and db.ui == uiTable and db.gear == gearTable, tag .. ": the live tables are the same tables")
  for name, data in pairs(db.profiles) do
    assert(not shares(data, db.modules) and not shares(data, db.ui) and not shares(data, db.gear), tag .. ": " .. name .. " shares no table with the live ones")
    assert(not shares(data, R.DEFAULT_MODULES) and not shares(data, R.GearPrefs.DEFAULTS), tag .. ": " .. name .. " shares no table with the defaults")
    for other, data2 in pairs(db.profiles) do
      if other ~= name then assert(not shares(data, data2), tag .. ": " .. name .. " and " .. other .. " share no table") end
    end
  end
end

-- A part that counts how often a profile change tells it; registering the same name again adds nothing.
local told = 0
PF.OnApply("views", "test-counter", function() told = told + 1 end)
PF.OnApply("views", "test-counter", function() told = told + 100 end)

-- New: the defaults; the profile left is stored as it was. A reload switch that changed asks once.
local popupsBefore = S.popups
local windowRedraws = 0
R.SettingsUI.RefreshValues = function() windowRedraws = windowRedraws + 1 end   -- an open settings window redraws
local ok, code, info = PF.Create("   Raid   ")
assert(ok and code == "create" and PF.Current() == "Raid", "the name is trimmed")
assert(told == 1, "each part is told once")
assert(#info.failed == 0, "every part followed the change: " .. table.concat(info.failed, ", "))
-- (the mock counts each request; the game shows one dialog for both, as TWICHUI_RELOAD isn't "multiple")
assert(info.reload == true and S.popups == popupsBefore + 2, "groupCheck and auctionatorSkin differ from load: the reload question is asked")
assert(db.modules.chronicleDeaths == false and db.modules.groupCheck == true and db.modules.welcomeBack == true, "a new profile has the default switches")
assert(db.ui.arrivalHold == nil and db.ui.foodDrink == nil and db.ui.brokerMenu == nil and db.ui.chronicleClock == nil, "and the default looks")
assert(db.gear.strictness == "balanced" and db.gear.reveal == "compare", "and the default gear preferences")
assert(R.FoodDrink.Get("size") ~= 44 and R.Chronicle.Clock() == "12" and R.MenuStyle.Get("bgColor") ~= "ff112233", "features read the new values")
assert(S.variables.TWICHUI_arrivalHold:GetValue() == "standard" and windowRedraws == 1, "the settings show them (an open window is redrawn once)")
assert(S.variables.TWICHUI_profileCurrent:GetValue() == "Raid")
local stored = db.profiles.Default
assert(stored.modules.chronicleDeaths == true and stored.ui.arrivalHold == "long" and stored.ui.foodDrink.size == 44 and stored.gear.strictness == "eager")
assert(stored.ui.reduceSettingsMotion == nil and stored.ui.showAdvanced == nil and stored.ui.mageSell == nil and stored.modules.restedxpSkin == nil and stored.gear.weights == nil,
  "account-wide entries are never stored in a profile")
assert(db.profileKeys["Rich - Forever"] == "Raid")
untouched("create")

-- Names
for raw, why in pairs({ [""] = "empty", ["   "] = "empty", ["a|cffb"] = "characters", ["tab\tname"] = "characters",
    [string.rep("x", 33)] = "long", ["raid"] = "taken", [" RAID "] = "taken", ["default"] = "taken" }) do
  local okName, codeName = PF.Create(raw)
  assert(not okName and codeName == why, ("%q: %s, not %s"):format(raw, why, tostring(codeName)))
end
assert(P.ProfileName(string.rep("x", 32)) and P.ProfileName(string.rep("\195\169", 32)) and not P.ProfileName(string.rep("\195\169", 33)),
  "32 characters, counted as characters not bytes")
assert(PF.Explain("characters"):find("|", 1, true) and PF.Explain("taken"))

-- Duplicate: an independent copy, and no option changes, so nothing is applied.
R.FoodDrink.Set("size", 50)
told = 0
ok, code = PF.Duplicate("Raid copy")
assert(ok and code == "duplicate" and PF.Current() == "Raid copy" and told == 0, "duplicating changes no option")
assert(db.profiles.Raid.ui.foodDrink.size == 50 and db.ui.foodDrink.size == 50)
R.FoodDrink.Set("size", 60)
assert(db.profiles.Raid.ui.foodDrink.size == 50, "a change to the copy never reaches the original")
untouched("duplicate")

-- Switch: back to the upgraded settings, exactly.
told = 0
ok, code, info = PF.Switch("Default")
assert(ok and code == "switch" and told == 1 and PF.Current() == "Default")
assert(info.reload == false and #info.failed == 0, "back to the values the UI loaded with: no reload needed")
for k, v in pairs(want.modules) do assert(db.modules[k] == v, "switched back: modules." .. k) end
for k, v in pairs(want.ui) do
  if k ~= "showAdvanced" then assert(same(db.ui[k], v), "switched back: ui." .. k) end
end
assert(db.gear.strictness == "eager" and R.FoodDrink.Get("size") == 44 and R.Chronicle.Clock() == "24")
assert(db.profiles["Raid copy"].ui.foodDrink.size == 60, "the copy kept its own value")
assert(db.profiles.Default == nil, "the profile in use is not stored twice")
assert(select(2, PF.Switch("Default")) == "same" and select(2, PF.Switch("Nope")) == "not-found")
untouched("switch")

-- Copy settings from: the current profile takes the other's settings and keeps its name.
ok, code = PF.CopyFrom("Raid copy")
assert(ok and code == "copy" and PF.Current() == "Default" and db.ui.foodDrink.size == 60 and db.modules.chronicleDeaths == false)
assert(db.profiles["Raid copy"].ui.foodDrink.size == 60 and db.profiles["Raid copy"].ui.foodDrink ~= db.ui.foodDrink, "the source keeps its own tables")
R.FoodDrink.Set("size", 61)
assert(db.profiles["Raid copy"].ui.foodDrink.size == 60, "independent after copying")
assert(select(2, PF.CopyFrom("Default")) == "same")
untouched("copy")

-- Rename: the one in use, another, and only the case; every reference follows.
ok = PF.Rename("Default", "Main")
assert(ok and PF.Current() == "Main" and db.profileState.live == "Main" and db.profileState.newCharacters == "Main"
  and db.profileKeys["Rich - Forever"] == "Main", "renaming the one in use moves every reference")
db.profileKeys["Wren - Forever"] = "Raid"
ok = PF.Rename("Raid", "Dungeons")
assert(ok and db.profiles.Dungeons and db.profiles.Raid == nil and db.profileKeys["Wren - Forever"] == "Dungeons", "another character's choice follows")
assert(PF.Rename("Main", "main") and PF.Current() == "main" and PF.Rename("main", "Main"), "changing only the case is allowed")
assert(select(2, PF.Rename("Main", "dungeons")) == "taken" and select(2, PF.Rename("Main", "Main")) == "unchanged")
untouched("rename")

-- Delete: never the one in use, the one for new characters, or one a character uses (and says who).
assert(select(2, PF.Delete("Main")) == "current")
local okDel, codeDel, users = PF.Delete("Dungeons")
assert(not okDel and codeDel == "in-use" and users[1] == "Wren - Forever", "a profile another character uses is kept")
assert(PF.Explain("in-use", users):find("Wren - Forever", 1, true), "and the message names who uses it")
db.profileState.newCharacters = "Raid copy"
assert(select(2, PF.Delete("Raid copy")) == "new-characters")
db.profileState.newCharacters = "Main"
ok = PF.Delete("Raid copy")
assert(ok and db.profiles["Raid copy"] == nil and select(2, PF.Delete("Raid copy")) == "not-found")
untouched("delete")

-- Reset: the profile in use goes back to the defaults; nothing else does.
ok = PF.Reset()
assert(ok and PF.Current() == "Main" and db.modules.chronicleDeaths == false and db.ui.foodDrink == nil and db.gear.strictness == "balanced")
assert(db.profiles.Dungeons, "other profiles are not reset")
untouched("reset")

-- Combat: whatever changes the options in use is refused, and nothing changes. Rename and Delete are allowed.
PF.Create("Spare")
PF.Switch("Main")
c.combat = true
local snap = copy(db)
for _, run in ipairs({
  function() return PF.Switch("Dungeons") end, function() return PF.Create("X") end, function() return PF.Duplicate("Y") end,
  function() return PF.CopyFrom("Dungeons") end, function() return PF.Reset() end }) do
  local okC, codeC = run()
  assert(not okC and codeC == "combat")
end
assert(same(db, snap), "a refused change changes nothing")
assert(PF.Explain("combat") == "Profile changes are unavailable during combat.")
assert(PF.Rename("Spare", "Spare 2") and PF.Delete("Spare 2"), "a new name or deleting an unused profile is allowed in combat")
c.combat = false

---------------------------------------------------------------------------
-- 3. The options page: its actions go through the same checks, combat rechecked after a confirmation
---------------------------------------------------------------------------
assert(table.concat(options(S, "TWICHUI_profileCurrent"), ",") == "Dungeons,Main")
assert(table.concat(options(S, "TWICHUI_profileCopyFrom"), ",") == ",Dungeons", "copy from lists the others")
-- Switching from the dropdown
S.variables.TWICHUI_profileCurrent:SetValue("Dungeons")
FlushTimers()
assert(PF.Current() == "Dungeons" and heard(c, "Now using profile \"Dungeons\"."))
-- Copy settings from: asks, and the answer is checked again when it comes
S.variables.TWICHUI_profileCopyFrom:SetValue("Main")
FlushTimers()
local ask = c.popups[#c.popups]
assert(ask.which == "TWICHUI_PROFILE_CONFIRM" and ask.text:find("\"Dungeons\"", 1, true) and ask.text:find("\"Main\"", 1, true), "the question names both profiles")
assert(S.variables.TWICHUI_profileCopyFrom:GetValue() == "", "the dropdown only chose what to ask about")
R.FoodDrink.Set("size", 33)
c.combat = true
c.said = {}
ask.data.accept()
assert(heard(c, "Profile changes are unavailable during combat.") and db.ui.foodDrink.size == 33, "combat began after the question: refused")
c.combat = false
ask.data.accept()
assert(db.ui.foodDrink == nil or db.ui.foodDrink.size ~= 33, "accepted out of combat: copied")
-- The dropdown in combat: refused, and it shows the profile in use again
c.combat = true
c.said = {}
S.variables.TWICHUI_profileCurrent:SetValue("Main")
FlushTimers()
assert(PF.Current() == "Dungeons" and heard(c, "unavailable during combat") and S.variables.TWICHUI_profileCurrent:GetValue() == "Dungeons")
c.combat = false
-- New from its button, named in the dialog
find(S, "Profiles", "New profile").click()
local named = c.popups[#c.popups]
assert(named.which == "TWICHUI_PROFILE_NAME")
named.data.accept("Solo")
assert(PF.Current() == "Solo" and heard(c, "Made profile \"Solo\""))
-- Delete: one in use is refused at once with who uses it; an unused one asks first
c.said = {}
S.variables.TWICHUI_profileDelete:SetValue("Main")
FlushTimers()
assert(heard(c, "can't be deleted") and db.profiles.Main, "the one for new characters is kept")
PF.Create("Temp"); PF.Switch("Solo")
S.variables.TWICHUI_profileDelete:SetValue("Temp")
FlushTimers()
local del = c.popups[#c.popups]
assert(del.which == "TWICHUI_PROFILE_CONFIRM" and del.text:find("\"Temp\"", 1, true) and db.profiles.Temp, "asks before deleting")
del.data.accept()
assert(db.profiles.Temp == nil)
-- The panel's Defaults never acts on profiles
for _, v in ipairs({ "TWICHUI_profileCurrent", "TWICHUI_profileCopyFrom", "TWICHUI_profileDelete" }) do
  assert(S.variables[v]:SetValueToDefault() == false)
end
untouched("options page")

-- Each part is told once per change, and switching back and forth adds no listeners.
PF.Switch("Main")
local events = {}
for e in pairs(R.frame.events) do events[#events + 1] = e end
table.sort(events)
told = 0
for _ = 1, 5 do PF.Switch("Solo"); PF.Switch("Main") end
assert(told == 10, "ten changes, ten times told: " .. told)
local after = {}
for e in pairs(R.frame.events) do after[#after + 1] = e end
table.sort(after)
assert(table.concat(events, ",") == table.concat(after, ","), "the same game events are listened to after switching back")
do
  local seen, listeners = {}, #R.Switches.listeners
  for _, key in ipairs(R.Switches.order) do assert(not seen[key], key .. " is in the switch order once"); seen[key] = true end
  for _ = 1, 3 do PF.Switch("Solo"); PF.Switch("Main") end
  assert(#R.Switches.listeners == listeners, "switching adds no switch listeners")
end

---------------------------------------------------------------------------
-- 4. Characters across sessions: sharing on purpose, independent copies, the choice kept, a new character
---------------------------------------------------------------------------
R.FoodDrink.Set("size", 40)   -- Rich, on Main
local s1 = Logout(c)
local w = Boot("Wren", copy(s1))
local WP = w.TwichUI.Profiles
assert(WP.Current() == "Dungeons", "Wren's earlier choice (set above) is used")
w.TwichUI.Profiles.Switch("Main")
assert(w.TwichUI.FoodDrink.Get("size") == 40, "Wren chose Main and shares Rich's settings")
assert(table.concat(WP.UsedBy("Main", true), ",") == "Rich - Forever")
w.TwichUI.FoodDrink.Set("size", 36)   -- a change to the shared profile
local s2 = Logout(w)
local r2 = Boot("Rich", copy(s2))
assert(r2.TwichUI.Profiles.Current() == "Main" and r2.TwichUI.FoodDrink.Get("size") == 36, "the shared change reaches Rich, on purpose")
r2.TwichUI.Profiles.Duplicate("Rich only")
r2.TwichUI.FoodDrink.Set("size", 52)
local s3 = Logout(r2)
local w2 = Boot("Wren", copy(s3))
assert(w2.TwichUI.Profiles.Current() == "Main" and w2.TwichUI.FoodDrink.Get("size") == 36, "Rich's independent copy doesn't reach Wren")
assert(w2.TwichUIDB.profiles["Rich only"].ui.foodDrink.size == 52, "loading Wren stored Rich's profile as it was")
local s4 = Logout(w2)
local r3 = Boot("Rich", copy(s4))
assert(r3.TwichUI.Profiles.Current() == "Rich only" and r3.TwichUI.FoodDrink.Get("size") == 52, "Rich's choice is kept across sessions")
local nova = Boot("Nova", copy(Logout(r3)))
assert(nova.TwichUI.Profiles.Current() == "Main" and nova.TwichUIDB.profileKeys["Nova - Forever"] == "Main",
  "a new character starts with the one for new characters, under its new name")
assert(same(nova.TwichUIDB.pins, before.pins), "pins are the same for every character and profile")

---------------------------------------------------------------------------
-- 5. A chosen profile that is gone, a character the game names late, newer or failed data
---------------------------------------------------------------------------
local gone = copy(s4)
gone.TwichUIDB.profileKeys["Rich - Forever"] = "Vanished"
local g = Boot("Rich", gone)
assert(g.TwichUI.Profiles.Current() == "Main" and heard(g, "\"Vanished\" no longer exists"), "falls back to the one for new characters, and says so once")
assert(g.TwichUI.Persist.Report().repairs["profile-selection-missing"] == 1 and g.TwichUI.Persist.Report().lost == 0)

local late = Boot("Rich", copy(s4), function(cl)
  cl.UnitName = function() if cl.TwichUI.Life.loggedIn then return "Rich" end end
end)
assert(late.TwichUI.Profiles.Current() == "Rich only" and late.TwichUI.FoodDrink.Get("size") == 52, "named at login: switched then, with the rest told")

local future = Boot("Rich", { TwichUIDB = { schema = 99, modules = {} } })
local fa, fwhy = future.TwichUI.Profiles.Available()
assert(not fa and fwhy == "future" and select(2, future.TwichUI.Profiles.Create("X")) == "future")
assert(future.TwichUI.Profiles.Explain("future"):find("newer TwichUI", 1, true))
local failed = Boot("Rich", copy(fixture), function(cl) cl.TwichUI.Persist.STEPS[2] = function() error("synthetic failure") end end)
assert(select(2, failed.TwichUI.Profiles.Available()) == "failed" and failed.TwichUIDB.schema == 1 and failed.TwichUIDB.profiles == nil,
  "a failed upgrade leaves no half-made profiles")

---------------------------------------------------------------------------
-- 6. Damaged profile data: each piece repaired or set aside on its own
---------------------------------------------------------------------------
local damaged = copy(s4)
local d = damaged.TwichUIDB
d.profiles.Broken = 5
d.profiles[7] = { modules = {} }
d.profiles["  padded  "] = { modules = {} }
d.profiles.Odd = { modules = { arrival = "yes", chronicle = false }, ui = { foodDrink = "big", arrivalHold = "short" }, gear = 3 }
d.profiles["Rich only"] = { modules = { chronicle = false } }   -- a stored copy with the name of the one in use
d.profileState.live = "Rich only"
d.profileState.newCharacters = "Nowhere"
d.profileKeys[3] = "Main"
d.profileKeys["Bad - Forever"] = {}
local dm = Boot("Rich", damaged)
local dd, rep = dm.TwichUIDB, dm.TwichUI.Persist.Report().repairs
assert(dd.profiles.Broken == nil and rep["profile-dropped"] == 1, "a profile that isn't a table is dropped and counted")
assert(dd.profiles[7] and dd.profiles["  padded  "], "keys that aren't names are kept as they are")
local listed = table.concat(dm.TwichUI.Profiles.List(), ",")
assert(not listed:find("padded") and not listed:find("7"), "and never offered")
assert(dd.profiles.Odd.modules.arrival == nil and dd.profiles.Odd.modules.chronicle == false, "a bad switch is removed, its neighbours kept")
assert(dd.profiles.Odd.ui.foodDrink == nil and dd.profiles.Odd.ui.arrivalHold == "short" and type(dd.profiles.Odd.gear) == "table")
assert(dd.profiles["Rich only (2)"] and dd.profiles["Rich only (2)"].modules.chronicle == false and rep["profile-renamed"] == 1,
  "a stored copy named like the one in use is kept under a free name")
assert(dd.profileState.newCharacters == "Rich only" and dd.profileKeys[3] == nil and dd.profileKeys["Bad - Forever"] == nil)
assert(dm.TwichUI.Profiles.Current() == "Rich only")
dm.TwichUI.Profiles.Switch("Odd")
assert(dm.TwichUIDB.modules.arrival == true and dm.TwichUI.Arrival and dm.TwichUIDB.ui.arrivalHold == "short", "a removed value takes its default when used")

print("PROFILES TESTS PASSED")
