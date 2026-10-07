-- EllesmereUI profile sharing: what is exported, what a friend's import may touch.
-- EllesmereUI itself is a stand-in here (the real addon needs the game), so this proves TwichUI's side:
-- the payload it hands over, the names it picks, what it records, and what it never calls.
dofile(TESTS .. "harness.lua")

local function Copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = Copy(v) end
  return o
end

-- Strings are shared across the stand-ins: a real EllesmereUI decodes any other copy's export.
local FAKE_STRINGS, FAKE_N = {}, 0

local MODULES = {
  { canon = "EllesmereUIActionBars", display = "Action Bars", folder = "EllesmereUIActionBars" },
  { canon = "EllesmereUINameplates", display = "Nameplates", folder = "EllesmereUINameplates" },
  { canon = "EllesmereUIDataBars", display = "DataBars", folder = "EllesmereUIDataBars" },
  { canon = "EllesmereUIQoL", display = "Quality of Life", folder = "EllesmereUIQoL" },
}

-- A stand-in for EllesmereUI's profile functions, with the real ones' shape (see EllesmereUI_Profiles.lua).
local function InstallEUI(env, opts)
  opts = opts or {}
  local E = { IS_FOREVER = true, calls = {}, _ADDON_DB_MAP = {} }
  for _, m in ipairs(MODULES) do table.insert(E._ADDON_DB_MAP, { canon = m.canon, display = m.display, folder = m.folder, suffix = m.canon:gsub("^EllesmereUI", "") }) end
  local db = opts.db or {
    activeProfile = "Mine",
    profiles = { Mine = { addons = { EllesmereUIActionBars = { scale = 1 } }, fonts = { global = "Mine font" } },
                 Raid = { addons = { EllesmereUINameplates = { w = 5 } } } },
    profileOrder = { "Mine", "Raid" }, specProfiles = { [62] = "Raid" },
    ppUIScale = 0.8, clickCast = { bind = 1 }, lastSpecByChar = { ["Pal - Forever"] = 62 },
  }
  env.EllesmereUIDB = db
  E.db = db
  local strings = FAKE_STRINGS
  E.strings = strings
  local function Call(name, ...) table.insert(E.calls, { name, ... }) end
  function E.GetProfileList() return db.profileOrder, db.profiles end
  function E.GetActiveProfileName() return db.activeProfile end
  function E.GetProfilesDB() return db end
  function E.IsModuleAddonLoaded(folder) return not (opts.notLoaded or {})[folder] end
  function E.PayloadFromOtherClient(p) return p.client == "retail" end
  function E.ExportProfile(name, ...)
    Call("ExportProfile", name, ...)
    if not db.profiles[name] then return nil end
    FAKE_N = FAKE_N + 1
    local str = ("!EUI_fake%d_"):format(FAKE_N) .. ("x"):rep(20)
    strings[str] = opts.payload and Copy(opts.payload) or { version = 3, type = "full", data = {
      addons = { EllesmereUINameplates = Copy(db.profiles[name].addons.EllesmereUINameplates or { w = 1 }),
                 EllesmereUIDataBars = { characters = { ["Rich - Forever"] = { gold = 9 } }, keep = 1 },
                 NotAModule = { x = 1 } },
      fonts = { global = "Sender font" }, customColors = { a = 1 }, darkMode = { d = 1 }, euiAccent = { useClass = true }, uiScale = 0.5, applyUIScale = true,
      blizzSkinGlobals = { skin = 1 }, assignedSpecs = { 62, 63 }, clickCast = { b = 1 }, spellAssignments = { z = 1 },
      unlockLayout = { anchors = {} }, unlockLayoutMeta = { keyToFolder = {} }, windowSkinLook = "x",
    } }
    return str
  end
  function E.DecodeImportString(str)
    local p = strings[str]
    if not p then return nil, "Failed to decode string" end
    if opts.decodeFails then return nil, "Failed to decompress data" end
    return Copy(p)
  end
  function E.ImportProfile(payload, name)
    Call("ImportProfile", Copy(payload), name)
    E.imported = Copy(payload)
    if opts.failImport then return false, "Unknown profile type" end
    db.profiles[name] = { addons = Copy(payload.data.addons) }
    table.insert(db.profileOrder, 1, name)
    if opts.throwAfterCreate then error("boom") end
    if opts.specLocked then return true, nil, "spec_locked" end
    db.activeProfile = name
    return true, nil
  end
  function E.SwitchProfile(name) Call("SwitchProfile", name); db.activeProfile = name end
  function E.DeleteProfile(name)
    Call("DeleteProfile", name)
    db.profiles[name] = nil
    for i, v in ipairs(db.profileOrder) do if v == name then table.remove(db.profileOrder, i) break end end
  end
  function E.called(name) local c = 0 for _, x in ipairs(E.calls) do if x[1] == name then c = c + 1 end end return c end
  env.EllesmereUI = E
  return E
end

local function Pump10() for _ = 1, 10 do FlushTimers(); Pump() end end

------------ Rich (sender): a scan that finds EllesmereUIDB, a normal addon, and a chosen profile
local rich = MakeClient("Rich", { "!!!TwichUI", "EllesmereUI", "Foo" })
CLIENTS.Rich = rich
rich.TwichUIDB = { setup = { scanNext = true } }
rich.LOADED["!!!TwichUI"] = true; rich.FireEvent("ADDON_LOADED", "!!!TwichUI")
local richE = InstallEUI(rich)
rich.LOADED.EllesmereUI = true; rich.FireEvent("ADDON_LOADED", "EllesmereUI")
rich.FooDB = { profiles = { Default = { s = 1 } }, profileKeys = {} }
rich.LOADED.Foo = true; rich.FireEvent("ADDON_LOADED", "Foo")
rich.FireEvent("PLAYER_LOGIN")
local RST, RES = rich.TwichUI.Setups, rich.TwichUI.Ellesmere

local groups = RST:DetectedByAddon()
local euiGroup
for _, g in ipairs(groups) do if g.owner == "EllesmereUI" then euiGroup = g end end
assert(euiGroup and euiGroup.backupOnly, "EllesmereUI's table is listed as backups-only")
assert(RST.db.selection.EllesmereUIDB == true, "still ticked, so backups keep protecting it")

-- no profile chosen: nothing EllesmereUI in the setup, and the table is never shared
RST:SaveMine(false)
local mine = RST.Mine()
assert(mine.tables.FooDB and not mine.tables.EllesmereUIDB, "the whole database is never in a shared setup")
assert(mine.eui == nil)

-- choose a profile
assert(RES.ChosenProfile() == nil)
RES.Choose("Raid")
assert(RES.ChosenProfile() == "Raid")
assert(RST:SaveMine(false) == 2)
mine = RST.Mine()
assert(mine.eui and mine.eui.name == "Raid" and mine.eui.str:find("^!EUI_"), "profile entry saved")
local exportArgs
for _, c in ipairs(richE.calls) do if c[1] == "ExportProfile" then exportArgs = c end end
-- ExportProfile(name, modules, layout, cdm, cdmSpecs, globals, overrides, windowSkins)
assert(exportArgs[2] == "Raid" and exportArgs[3] == nil and exportArgs[4] == true and exportArgs[5] == true
  and exportArgs[6] == nil and exportArgs[7] == true and exportArgs[8] == true and exportArgs[9] == false,
  "exports one profile with its look and no window skins")
local firstId = mine.eui.id
RST:SaveMine(false)
assert(RST.Mine().eui.id == firstId, "a profile keeps its id across saves")
RES.Choose("Mine"); RST:SaveMine(false)
assert(RST.Mine().eui.id ~= firstId, "a different profile gets its own id")
RES.Choose("Raid"); RST:SaveMine(false)
assert(RST.Mine().eui.id == firstId)
assert(RST.CountAddons(RST.Mine()) == 1)

-- a backup still holds the table (it is the user's own, put back as a whole on purpose)
local made, point = rich.TwichUI.Restore:Create("b")
assert(made == "created" and point.tables.EllesmereUIDB, "backups keep EllesmereUI")
assert(not RES.Blocked("restore:" .. point.id, "EllesmereUIDB"), "own backups may restore it")
assert(RES.Blocked("recv:Rich-Forever", "EllesmereUIDB") and RES.Blocked("file", "EllesmereUIDB"), "someone else's setup may not")
assert(not RES.Blocked("recv:Rich-Forever", "FooDB"))

-- a profile that EllesmereUI can't export is reported, not shared
RES.Choose("Gone")
assert(RES.ChosenProfile() == nil, "a deleted profile is no longer chosen")
RES.Choose("Raid")
local realExport = richE.ExportProfile
richE.ExportProfile = function() return nil end
assert(select(2, RES.Build()), "export failure has a reason")
richE.ExportProfile = realExport
richE.IS_FOREVER = false
assert(RES.Api() == nil and select(2, RES.Build()):find("Forever"), "not the Forever build")
richE.IS_FOREVER = true

------------ Pal (recipient) with their own customized profiles, one named like the sender's
local pal = MakeClient("Pal", { "!!!TwichUI", "EllesmereUI", "Foo" })
CLIENTS.Pal = pal
pal.LOADED["!!!TwichUI"] = true; pal.FireEvent("ADDON_LOADED", "!!!TwichUI")
local palDB = { activeProfile = "Mine", profileOrder = { "Mine", "Raid" }, specProfiles = { [62] = "Raid", [63] = "Mine" },
  profiles = { Mine = { addons = { EllesmereUIActionBars = { scale = 2 } }, fonts = { global = "Pal font" } },
               Raid = { addons = { EllesmereUINameplates = { w = 99 } } } }, ppUIScale = 0.9 }
local palE = InstallEUI(pal, { db = palDB })
pal.LOADED.EllesmereUI = true; pal.FireEvent("ADDON_LOADED", "EllesmereUI")
pal.FooDB = { profiles = { Default = {} }, profileKeys = {} }; pal.LOADED.Foo = true; pal.FireEvent("ADDON_LOADED", "Foo")
pal.FireEvent("PLAYER_LOGIN")
local before = Copy(palDB)
local mineProfile, raidProfile = palDB.profiles.Mine, palDB.profiles.Raid

assert(rich.TwichUI.Share:SendTo("Pal")); Pump10()
pal.TwichUI.Share:Respond("Rich-Forever", true); Pump10(); Pump10()
local recv = pal.TwichUIDB.setup.received["Rich-Forever"]
assert(recv and recv.eui and recv.eui.str == RST.Mine().eui.str, "the exported profile arrived untouched")
assert(not recv.tables.EllesmereUIDB and recv.tables.FooDB)
local PST, PES = pal.TwichUI.Setups, pal.TwichUI.Ellesmere
assert(palE.called("ImportProfile") == 0, "receiving imports nothing")

------------ The review
local plan = PES.Plan(recv, "Rich")
assert(plan.ok and plan.kind == "profile" and plan.sourceName == "Raid", tostring(plan.why))
assert(plan.dest == "Raid (Rich)", "same display name as a local profile gets a distinct name: " .. tostring(plan.dest))
assert(plan.active == "Mine" and #plan.previous == 0)
local shown = {}
for _, m in ipairs(plan.modules) do shown[#shown + 1] = m.display end
assert(table.concat(shown, ",") == "Nameplates,DataBars", "only modules EllesmereUI recognises: " .. table.concat(shown, ","))
assert(plan.layout and not plan.cdm and plan.look and plan.colours)
local noted = false
for _, n in ipairs(plan.notes) do if n:find("palette") then noted = true end end
assert(noted, "the shared-palette effect of imported colours is disclosed")
assert(#plan.dest <= 30)
-- the same name is never reused, whatever its case
palDB.profiles["raid (rich)"] = { addons = {} }; table.insert(palDB.profileOrder, "raid (rich)")
assert(PES.Plan(recv, "Rich").dest == "Raid (Rich) 2")
palDB.profiles["raid (rich)"] = nil; table.remove(palDB.profileOrder)
local long = PES.NewName(("A"):rep(60), "Someone With A Long Name")
assert(#long <= 30 and not palDB.profiles[long], long)
assert(not PES.NewName("Bad|cffff0000Name\n", "R|i"):find("[|%c]"))
-- the setup's pieces on the received page never include the database
assert(#PST.PackByAddon(recv) == 1 and PST.PackByAddon(recv)[1].owner ~= "EllesmereUI")

------------ Importing: a new profile, nothing else touched
assert(not select(1, PES.Apply(recv, "Rich", "Something else")), "refuses if the name changed since the review")
assert(palE.called("ImportProfile") == 0)
local ok, report = PES.Apply(recv, "Rich", plan.dest)
assert(ok, tostring(report))
assert(palE.called("ImportProfile") == 1 and palE.called("DeleteProfile") == 0 and palE.called("SwitchProfile") == 0,
  "one import, no delete, no switch")
local imp = palE.imported
assert(palE.calls[#palE.calls][3] == plan.dest)
for _, k in ipairs({ "uiScale", "applyUIScale", "blizzSkinGlobals", "assignedSpecs", "clickCast", "spellAssignments", "unlockLayoutMeta" }) do
  assert(imp.data[k] == nil, k .. " must not be imported")
end
assert(imp.data.unlockLayout and imp.data.windowSkinLook == "x", "profile-scoped data stays")
assert(imp.data.fonts.global == "Sender font" and imp.data.customColors.a == 1 and imp.data.darkMode.d == 1 and imp.data.euiAccent.useClass,
  "the profile's look is imported with it")
assert(imp.data.addons.NotAModule == nil, "unknown modules are dropped")
assert(imp.data.addons.EllesmereUIDataBars.characters == nil and imp.data.addons.EllesmereUIDataBars.keep == 1, "per-character data dropped")
assert(imp.data.addons.EllesmereUINameplates.w == 5)
assert(report.dest == "Raid (Rich)" and report.previous == "Mine" and report.status == "active" and report.verified, "report")
-- everything that was there is still there
assert(palDB.profiles.Mine == mineProfile and palDB.profiles.Raid == raidProfile, "other profiles are the same tables")
assert(palDB.profiles.Mine.addons.EllesmereUIActionBars.scale == 2 and palDB.profiles.Raid.addons.EllesmereUINameplates.w == 99)
assert(palDB.specProfiles[62] == "Raid" and palDB.specProfiles[63] == "Mine", "spec assignments unchanged")
assert(palDB.ppUIScale == before.ppUIScale and palDB.profiles.Mine.fonts.global == "Pal font")
assert(PST.db.eui.imports["Raid (Rich)"].key == "Rich - Forever|" .. firstId, "provenance recorded")
assert(pal.TwichUIDB.setup.eui.last.dest == "Raid (Rich)")
-- one note after the reload, then it is gone
local printed = {}
local realPrint = pal.print
pal.print = function(s) printed[#printed + 1] = tostring(s) end
pal.FireEvent("PLAYER_LOGIN")
pal.print = realPrint
assert(#printed >= 1 and printed[1]:find("Raid %(Rich%)") and printed[1]:find("Mine"), "login note names both profiles: " .. tostring(printed[1]))
assert(pal.TwichUIDB.setup.eui.last == nil)

------------ Importing again: a separate copy, with a pointer to the earlier one
palDB.activeProfile = "Mine"
local plan2 = PES.Plan(recv, "Rich")
assert(plan2.dest == "Raid (Rich) 2" and #plan2.previous == 1 and plan2.previous[1].dest == "Raid (Rich)")
assert(PES.Apply(recv, "Rich", plan2.dest))
assert(palDB.profiles["Raid (Rich)"] and palDB.profiles["Raid (Rich) 2"], "both copies exist")
palDB.profiles["Raid (Rich)"].addons.EllesmereUINameplates.w = 1234   -- a local edit
assert(PES.Apply(recv, "Rich", PES.Plan(recv, "Rich").dest))
assert(palDB.profiles["Raid (Rich)"].addons.EllesmereUINameplates.w == 1234, "an edited imported profile is never replaced")
-- deleted in EllesmereUI: the earlier import is forgotten
palE.DeleteProfile("Raid (Rich) 2")
local gone = false
for _, p in ipairs(PES.Plan(recv, "Rich").previous) do if p.dest == "Raid (Rich) 2" then gone = true end end
assert(not gone and PST.db.eui.imports["Raid (Rich) 2"] == nil)
-- another sender with the same profile name is a different source
local other = Copy(recv); other.source = "Zed - Forever"; other.sender = "Zed-Forever"
assert(#PES.Plan(other, "Zed").previous == 0, "same names from another sender don't match")
local sameIdOtherName = Copy(recv); sameIdOtherName.eui.name = "Renamed"
assert(#PES.Plan(sameIdOtherName, "Rich").previous > 0, "a renamed source is still the same source (id)")

------------ Spec-locked: stored, not switched
palE.db.activeProfile = "Mine"
local lockedE = palE
local oldImport = lockedE.ImportProfile
lockedE.ImportProfile = function(p, n)
  table.insert(lockedE.calls, { "ImportProfile", Copy(p), n })
  palDB.profiles[n] = { addons = Copy(p.data.addons) }; table.insert(palDB.profileOrder, 1, n)
  return true, nil, "spec_locked"
end
local ok3, rep3 = PES.Apply(recv, "Rich", PES.Plan(recv, "Rich").dest)
assert(ok3 and rep3.status == "stored" and palDB.activeProfile == "Mine")
lockedE.ImportProfile = oldImport

------------ Failures leave nothing behind
local namesBefore = #palDB.profileOrder
lockedE.ImportProfile = function(p, n) table.insert(lockedE.calls, { "ImportProfile", Copy(p), n }) return false, "Unknown profile type" end
local ok4, msg4 = PES.Apply(recv, "Rich", PES.Plan(recv, "Rich").dest)
assert(not ok4 and msg4:find("Unknown profile type") and #palDB.profileOrder == namesBefore, "refused import changes nothing")
-- an error after the profile was created: put the previous profile back, remove only what this import made
local deletes0, switches0 = lockedE.called("DeleteProfile"), lockedE.called("SwitchProfile")
lockedE.ImportProfile = function(p, n)
  table.insert(lockedE.calls, { "ImportProfile", Copy(p), n })
  palDB.profiles[n] = { addons = {} }; table.insert(palDB.profileOrder, 1, n); palDB.activeProfile = n
  error("boom")
end
local capturedErr
pal.geterrorhandler = function() return function(e) capturedErr = e end end
local dest5 = PES.Plan(recv, "Rich").dest
local ok5 = PES.Apply(recv, "Rich", dest5)
assert(not ok5 and capturedErr and tostring(capturedErr):find("boom"), "the error is reported")
assert(palDB.profiles[dest5] == nil and palDB.activeProfile == "Mine", "half-made profile removed, previous profile back")
assert(lockedE.called("DeleteProfile") == deletes0 + 1 and lockedE.called("SwitchProfile") == switches0 + 1)
assert(lockedE.calls[#lockedE.calls][2] == dest5 and palDB.profiles.Mine == mineProfile and palDB.profiles.Raid == raidProfile)
lockedE.ImportProfile = oldImport

-- a decode that fails, a profile of the wrong kind, nothing recognisable
local function ApplyFails(p, why)
  local c0 = pal.EllesmereUI.called("ImportProfile")
  local okx, msg = PES.Apply(p, "Rich", nil)
  assert(not okx, why)
  assert(pal.EllesmereUI.called("ImportProfile") == c0, why .. ": EllesmereUI's import must not run")
  return msg
end
local unknownStr = Copy(recv); unknownStr.eui.str = "!EUI_" .. ("z"):rep(30)
ApplyFails(unknownStr, "undecodable")
for _, bad in ipairs({
  { eui = { id = "1", name = "x", str = "not an eui string" } },
  { eui = { id = "", name = "x", str = "!EUI_abcdef" } },
  { eui = { id = "1", name = "|", str = "!EUI_abcdef" } },
  { eui = { id = "1", name = "x", str = "!EUI_" .. ("a"):rep(5 * 1048576) } },
  { eui = "garbage" },
}) do
  assert(PES.Source(bad) == nil and select(2, PES.Source(bad)), "malformed entry rejected")
  assert(PES.CleanEntry(bad.eui) == nil)
  assert(not PES.Plan(bad, "Rich").ok)
  ApplyFails(bad, "malformed")
end
for _, payload in ipairs({
  { version = 3, type = "cdm_spells", data = { addons = {} } },
  { version = 3, type = "full", data = "text" },
  { version = 3, type = "full", data = { addons = { NotAModule = { a = 1 } } } },
  { version = 3, type = "full", data = {} },
}) do
  local e2 = InstallEUI(pal, { db = palDB, payload = payload })
  local str = e2.ExportProfile("Mine")
  local pack = { source = "X - Forever", eui = { id = "9", name = "N", str = str } }
  local plan9 = PES.Plan(pack, "X")
  assert(not plan9.ok and plan9.why, "bad payload kind or content is refused")
  ApplyFails(pack, "bad payload")
end
InstallEUI(pal, { db = palDB })
palE = pal.EllesmereUI

------------ Missing / incompatible EllesmereUI
local keep = pal.EllesmereUI
pal.EllesmereUI = nil
assert(PES.Api() == nil and #PES.ProfileNames() == 0)
local planNo = PES.Plan(recv, "Rich")
assert(not planNo.ok and planNo.why:find("isn't installed"))
assert(not PES.Apply(recv, "Rich", nil))
pal.EllesmereUI = { IS_FOREVER = true }
assert(select(2, PES.Api()):find("profile function"), "an EllesmereUI without the functions is refused")
pal.EllesmereUI = keep
local inCombat = pal.InCombatLockdown
pal.InCombatLockdown = function() return true end
assert(not PES.Apply(recv, "Rich", nil), "not in combat")
pal.InCombatLockdown = inCombat

------------ Older shares that carry the whole database
local legacyDB = { activeProfile = "Old", specProfiles = { [62] = "Old" }, ppUIScale = 0.3, dataBarsGold = { x = 1 },
  profiles = { Old = { addons = { EllesmereUIActionBars = { b = 1 }, EllesmereUIQoL = { chars = { a = 1 }, q = 2 }, Junk = { j = 1 } },
    fonts = { global = "F" }, assignedSpecs = { 62 }, _migrations = { m = 1 } }, Other = { addons = { EllesmereUINameplates = { n = 1 } } } } }
local legacy = { format = 2, created = 5, version = 1, source = "Old - Forever", sourceName = "Old", sender = "Old-Forever",
  tables = { EllesmereUIDB = { owner = "EllesmereUI", data = legacyDB, hash = "1" }, FooDB = { owner = "Foo", data = { a = 1 }, hash = "2" } } }
local srcL = PES.Source(legacy)
assert(srcL and srcL.kind == "legacy" and srcL.name == "Old", "the sender's active profile is found")
assert(#PST.PackByAddon(legacy) == 1 and PST.CountAddons(legacy) == 1, "the database is not an applicable addon")
local planL = PES.Plan(legacy, "Old")
assert(planL.ok and planL.dest == "Old (Old)" and #planL.notes >= 1)
local okL, repL = PES.Apply(legacy, "Old", planL.dest)
assert(okL, tostring(repL))
local li = palE.imported
assert(li.type == "full" and li.data.addons.EllesmereUIActionBars.b == 1 and li.data.addons.Junk == nil, "only recognised modules")
assert(li.data.addons.EllesmereUIQoL.chars == nil and li.data.addons.EllesmereUIQoL.q == 2, "per-character data dropped")
assert(li.data.assignedSpecs == nil and li.data.unlockLayout == nil and li.data._migrations.m == 1)
assert(palDB.profiles.Other == nil and palDB.dataBarsGold == nil, "nothing else of the sender's database came with it")
assert(palDB.specProfiles[62] == "Raid" and palDB.profiles.Mine == mineProfile)
-- no usable profile: refused, with a reason
for _, db in ipairs({ { profiles = {} }, { activeProfile = "A", profiles = { A = { addons = {} } } }, { activeProfile = "A", profiles = { A = "x" } }, "nope" }) do
  local bad = { source = "B - Forever", tables = { EllesmereUIDB = { owner = "EllesmereUI", data = db } } }
  local s, why = PES.Source(bad)
  assert(s == nil and why, "unusable database refused")
  assert(not PES.Plan(bad, "B").ok)
end
-- and the load-time apply refuses the table whatever is queued
PST:Queue("apply", { "EllesmereUIDB", "FooDB" }, "recv:Old-Forever")
pal.TwichUIDB.setup.received["Old-Forever"] = legacy
assert(pal.reloaded)
local d1, d2, d3 = pal.TwichUIDB, pal.TwichUIBackupDB, pal.TwichUIShareDB
local pal2 = MakeClient("Pal", { "!!!TwichUI", "EllesmereUI", "Foo" })
pal2.TwichUIDB, pal2.TwichUIBackupDB, pal2.TwichUIShareDB = d1, d2, d3
pal2.LOADED["!!!TwichUI"] = true; pal2.FireEvent("ADDON_LOADED", "!!!TwichUI")
local liveDB = { activeProfile = "Mine", profiles = { Mine = { addons = {} } }, profileOrder = { "Mine" }, specProfiles = {} }
pal2.EllesmereUIDB = liveDB
pal2.LOADED.EllesmereUI = true; pal2.FireEvent("ADDON_LOADED", "EllesmereUI")
pal2.FooDB = { profiles = { Default = {} }, profileKeys = {} }; pal2.LOADED.Foo = true; pal2.FireEvent("ADDON_LOADED", "Foo")
pal2.FireEvent("PLAYER_LOGIN")
assert(pal2.EllesmereUIDB == liveDB and liveDB.activeProfile == "Mine" and liveDB.profiles.Old == nil, "the table was not replaced")
assert(pal2.FooDB.a == 1, "other settings in the same setup still apply")

print("ELLESMERE SHARE PASSED")
print("PASSED")
