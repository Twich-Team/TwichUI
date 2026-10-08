dofile(TESTS .. "harness.lua")
-- Saved data: schema, upgrade, defaults, damaged data, newer data, imports and restore points, and what is
-- never saved. All fixtures are synthetic (made-up names, no real saved variables). See docs/persistence.md.

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

local function same(a, b, seen)
  if a ~= a and b ~= b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  if a == b then return true end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do if not same(v, b[k], seen) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local SV = { "TwichUIDB", "TwichUIBackupDB", "TwichUIShareDB", "TwichUIRestoreDB", "TwichUIChronicleDB" }
local function saved(c) local s = {} for _, n in ipairs(SV) do s[n] = c[n] end return s end
local function logout(c) c.FireEvent("PLAYER_LOGOUT") return saved(c) end

local function boot(name, sv, opts)
  opts = opts or {}
  local c = MakeClient(name, opts.addons or { "!!!TwichUI", "Foo", "Bar" })
  CLIENTS[name] = c
  c.said = {}
  c.print = function(s) c.said[#c.said + 1] = tostring(s) end
  for _, f in ipairs(opts.files or {}) do local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {}) end
  for k, v in pairs(sv or {}) do c[k] = v end
  if opts.before then opts.before(c) end
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  if not opts.noLogin then c.FireEvent("PLAYER_LOGIN") end   -- noLogin: other addons load first, as in the game
  return c
end

local function heard(c, text)
  for _, s in ipairs(c.said) do if s:find(text, 1, true) then return true end end
  return false
end

local function settle() for _ = 1, 10 do FlushTimers(); Pump() end end
local function run(fn, ...)
  local out
  fn(..., function(v) out = { true, v } end, function(m) out = { false, m } end)
  for _ = 1, 20000 do if out then break end FlushTimers() end
  assert(out, "job finished")
  return out[1], out[2]
end

---------------------------------------------------------------------------
-- 1. A fresh install
---------------------------------------------------------------------------
local fresh = boot("Fresh")
local R = fresh.TwichUI
local P = R.Persist
assert(P.SCHEMA == 1 and fresh.TwichUIDB.schema == P.SCHEMA, "new data is written at the current schema")
for k, v in pairs(R.DEFAULT_MODULES) do assert(fresh.TwichUIDB.modules[k] == v, "default for " .. k) end
assert(fresh.TwichUIDB.shareTransport == "DIRECT", "a new install sends Direct")
assert(fresh.TwichUIChronicleDB.version == 1 and type(fresh.TwichUIChronicleDB.chars) == "table")
local rep = P.Report()
assert(rep.main.outcome == "fresh" and rep.main.stored == nil and rep.lost == 0, "fresh: nothing reset")
assert(not heard(fresh, "TwichUI reset") and not heard(fresh, "newer TwichUI"), "no notice for a new install")
assert(R.DEFAULT_MODULES ~= fresh.TwichUIDB.modules, "the defaults table is never the live table")
fresh.TwichUIDB.modules.media = not R.DEFAULT_MODULES.media
assert(R.DEFAULT_MODULES.media ~= fresh.TwichUIDB.modules.media, "changing a setting never changes the defaults")

---------------------------------------------------------------------------
-- 2. Complete, valid, current data is left exactly as it is
---------------------------------------------------------------------------
local mine = boot("Complete")
mine.TwichUIDB.modules.chronicleDeaths = true
mine.TwichUIDB.modules.media = false
mine.TwichUIDB.ui = { showAdvanced = true, arrivalHold = "long", trainingPosition = { x = 12, y = -40 }, qol = { x = "y" }, chronicleClock = "24" }
mine.TwichUIDB.gear = { strictness = "eager", weights = { MAGE = { [62] = { intellect = 2.5 } } }, priority = {}, usePriority = {}, trees = { ["Pal-Forever"] = 62 } }
mine.TwichUI.Chronicle.Add("note", { title = "Note", note = "synthetic note one" })
local snapshot = copy(logout(mine))
local again = boot("Complete", copy(snapshot))
assert(again.TwichUI.Persist.Report().main.outcome == "current", "second load: already current")
assert(same(again.TwichUIDB.modules, snapshot.TwichUIDB.modules) and same(again.TwichUIDB.ui, snapshot.TwichUIDB.ui)
  and same(again.TwichUIDB.gear, snapshot.TwichUIDB.gear), "a complete current save comes back unchanged")
assert(again.TwichUI.Persist.Report().lost == 0 and not heard(again, "TwichUI reset"), "nothing reset, no notice")
do
  local found
  for _, e in ipairs(again.TwichUI.Chronicle.Entries()) do if e.note == "synthetic note one" then found = true end end
  assert(found, "the note written before the reload is still there")
end

---------------------------------------------------------------------------
-- 3. Partial settings get their missing defaults, and only those
---------------------------------------------------------------------------
local partial = boot("Partial", { TwichUIDB = { schema = 1, shareTransport = "GUILD", modules = { chronicle = false }, ui = { showAdvanced = true } } })
local pm = partial.TwichUIDB.modules
assert(pm.chronicle == false, "a saved choice is kept")
assert(pm.media == partial.TwichUI.DEFAULT_MODULES.media and pm.foodDrink == false and pm.arrival == true, "missing ones get their default")
assert(partial.TwichUIDB.shareTransport == "GUILD" and partial.TwichUIDB.ui.showAdvanced == true)
local added = partial.TwichUI.Persist.Report().repairs["defaults-added"]
local total = 0
for _ in pairs(partial.TwichUI.DEFAULT_MODULES) do total = total + 1 end
assert(added == total - 1, "every default but the saved one was added: " .. tostring(added))
assert(partial.TwichUI.Persist.Report().lost == 0, "filling defaults loses nothing")

---------------------------------------------------------------------------
-- 4. false, 0, "" and empty tables are values, not gaps
---------------------------------------------------------------------------
local odd = {
  schema = 1, shareTransport = "DIRECT",
  modules = { groupCheck = false, welcomeBack = false, arrival = false },
  ui = { showAdvanced = false, arrivalHold = "", foodDrinkPosition = { x = 0, y = 0 }, qol = {}, foodDrink = { borderSize = 0, showCount = false },
         brokerMenu = {} },
  gear = { glancePossible = false, weights = {}, priority = {}, usePriority = {}, trees = {} },
  setup = { detected = {}, selection = {}, received = {}, trusted = {}, recommend = { someAddon = false } },
}
local keep = boot("Odd", { TwichUIDB = copy(odd) })
assert(keep.TwichUIDB.modules.groupCheck == false and keep.TwichUIDB.modules.welcomeBack == false and keep.TwichUIDB.modules.arrival == false)
assert(keep.TwichUIDB.ui.showAdvanced == false and keep.TwichUIDB.ui.arrivalHold == "", "false and the empty string stay")
assert(keep.TwichUIDB.ui.foodDrinkPosition.x == 0 and keep.TwichUIDB.ui.foodDrink.borderSize == 0 and keep.TwichUIDB.ui.foodDrink.showCount == false, "zero and false stay")
assert(next(keep.TwichUIDB.ui.qol) == nil and next(keep.TwichUIDB.ui.brokerMenu) == nil, "empty groups stay empty")
assert(keep.TwichUIDB.gear.glancePossible == false and next(keep.TwichUIDB.gear.weights) == nil)
assert(keep.TwichUIDB.setup.recommend.someAddon == false, "a deliberate 'no' is kept")

---------------------------------------------------------------------------
-- 5. Wrong types: the narrowest repair, and the neighbours are untouched
---------------------------------------------------------------------------
local bad = boot("Bad", { TwichUIDB = {
  schema = 1,
  modules = { chronicle = "yes", arrival = 0, welcomeBack = false, shareGroup = "legacy-and-unknown-kept" },
  ui = { qol = "oops", foodDrink = 7, brokerMenu = { borderSize = 3 }, showAdvanced = true, futureField = { keep = "me" } },
  gear = { reveal = "alt", weights = "nope", priority = { MAGE = 5 }, usePriority = { WARRIOR = { [71] = true } }, trees = {} },
  setup = 12,
  storedData = "x", whisperProbe = true, shareTransport = 12,
} })
local bd = bad.TwichUIDB
assert(bd.modules.chronicle == true and bd.modules.arrival == true, "a non-boolean switch returns to its default, not 'on' by accident")
assert(bd.modules.welcomeBack == false and bd.modules.shareGroup == "legacy-and-unknown-kept", "valid and unknown values stay")
assert(bd.ui.qol == nil and bd.ui.foodDrink == nil, "a group that is not a table is dropped so it can be rebuilt")
assert(bd.ui.brokerMenu.borderSize == 3 and bd.ui.showAdvanced == true and bd.ui.futureField.keep == "me", "neighbours and unknown fields stay")
assert(type(bd.setup) == "table" and type(bd.setup.received) == "table" and bd.storedData ~= "x" and bd.whisperProbe == nil)
assert(bd.shareTransport == "DIRECT")
assert(bd.gear.reveal == "alt")
do local chunk = assert(loadfile(ROOT .. "gear/Prefs.lua")); setfenv(chunk, bad); chunk("!!!TwichUI", {}) end
bad.TwichUI.GearPrefs.Get("reveal")   -- opening the preferences repairs the groups in them
assert(type(bd.gear.weights) == "table" and bd.gear.priority.MAGE == nil and bd.gear.usePriority.WARRIOR[71] == true)
local r5 = bad.TwichUI.Persist.Report()
assert(r5.repairs["module-not-boolean"] == 2 and r5.repairs["container-not-table"] >= 5 and r5.lost >= 7, "counted by reason code")
assert(heard(bad, "reset or set aside") and heard(bad, "/tui diagnostics"), "one notice, with where to look")
local notices = 0
for _, s in ipairs(bad.said) do if s:find("reset or set aside", 1, true) then notices = notices + 1 end end
assert(notices == 1, "said once")

-- Out-of-range values are the owning feature's to judge when it reads them; they are not erased.
local range = boot("Range", { TwichUIDB = { schema = 1, modules = {}, ui = { foodDrink = { size = 9999, layout = "sideways" }, trainingPosition = { x = 1e9, y = 0 } } } })
assert(range.TwichUIDB.ui.foodDrink.size == 9999 and range.TwichUIDB.ui.trainingPosition.x == 1e9, "stored as the player left them")

-- The whole variable the wrong type
local junkRoot = boot("JunkRoot", { TwichUIDB = 5, TwichUIBackupDB = "x", TwichUIShareDB = true, TwichUIRestoreDB = 3, TwichUIChronicleDB = "text" })
assert(type(junkRoot.TwichUIDB) == "table" and junkRoot.TwichUIDB.schema == 1 and type(junkRoot.TwichUIBackupDB) == "table")
assert(type(junkRoot.TwichUIShareDB) == "table" and type(junkRoot.TwichUIRestoreDB) == "table" and junkRoot.TwichUIChronicleDB.version == 1)
assert(junkRoot.TwichUI.Persist.Report().repairs["root-not-table"] == 5, "five roots were not tables")

local nan = 0 / 0
local badSchema = boot("BadSchema", { TwichUIDB = { schema = "two", modules = { chronicle = false } } })
assert(badSchema.TwichUIDB.schema == 1 and badSchema.TwichUIDB.modules.chronicle == false and badSchema.TwichUI.Persist.Report().repairs["schema-invalid"] == 1, "an unreadable number is treated as unversioned")
local nanSchema = boot("NanSchema", { TwichUIDB = { schema = nan, modules = {} } })
assert(nanSchema.TwichUIDB.schema == 1)

---------------------------------------------------------------------------
-- 6. The older layout (schema 0 = every release before schemas): a synthetic fixture built from what
--    earlier commits wrote, not from anyone's real file
---------------------------------------------------------------------------
local function legacy()
  return {
    modules = { media = true, auctionatorSkin = false, setupSharing = true, acceptSetups = true, quietLogin = true,
      shareWhisper = true, shareGroup = true, shareGuild = false, groupCheck = false, chronicleDeaths = true,
      comboPoints = true, comboPointsHideGame = false, foodDrink = true },
    ui = { showAdvanced = true, arrivalHold = "long", trainingPosition = { x = 12, y = -40 },
      comboPoints = { style = "bar" }, comboPointsPosition = { x = 1, y = 2 },
      foodDrink = { borderSize = 0, showCount = false }, qol = {}, chronicleClock = "24" },
    gear = { strictness = "eager", weights = { MAGE = { [62] = { intellect = 2 } } }, trees = { ["Pal-Forever"] = 62 } },
    setup = { detected = {}, selection = { FooDB = true }, received = {}, trusted = { ["Rich-Forever"] = true }, recommend = {} },
    storedData = { found = { FooDB = { owner = "Foo" } }, scanMode = "old" },
    svTest = { ok = true },
    whisperProbe = { build = "70009", ok = true, at = 5 },
  }
end
local old = boot("Legacy", { TwichUIDB = legacy() })
local od = old.TwichUIDB
assert(od.schema == 1 and old.TwichUI.Persist.Report().main.outcome == "migrated" and old.TwichUI.Persist.Report().main.stored == nil)
assert(od.shareTransport == "PARTY" and od.modules.shareGroup == true and od.modules.shareWhisper == true, "group choice kept; the old keys are left as they were")
assert(od.modules.comboPoints == nil and od.modules.comboPointsHideGame == nil and od.ui.comboPoints == nil and od.ui.comboPointsPosition == nil, "only the combo points keys are removed")
assert(od.storedData.scanMode == nil and od.svTest == nil and od.storedData.found.FooDB.owner == "Foo")
local want = legacy()
assert(od.modules.auctionatorSkin == false and od.modules.groupCheck == false and od.modules.chronicleDeaths == true and od.modules.foodDrink == true)
assert(same(od.ui.trainingPosition, want.ui.trainingPosition) and od.ui.arrivalHold == "long" and od.ui.chronicleClock == "24" and od.ui.foodDrink.borderSize == 0, "valid values and positions survive")
assert(same(od.gear.weights, want.gear.weights) and od.gear.trees["Pal-Forever"] == 62 and od.gear.strictness == "eager")
assert(same(od.setup.selection, want.setup.selection) and od.setup.trusted["Rich-Forever"] == true and od.whisperProbe.ok == true)
assert(old.TwichUI.Persist.Report().repairs["legacy-key-removed"] == 6 and old.TwichUI.Persist.Report().lost == 0, "six leftovers removed; nothing the player stored was lost")
assert(not heard(old, "reset or set aside"), "an ordinary upgrade says nothing")

-- What each earlier release really wrote (tests/fixtures: made by running that release's own code, for a
-- made-up character). Every one comes up to the current schema with the player's choices intact.
for _, tag in ipairs({ "v3.0.4", "v3.0.5", "v3.0.6", "v3.0.7", "v3.0.8" }) do
  local fixture = dofile(TESTS .. "fixtures/saved_" .. tag .. ".lua")
  local c = boot("Oldie", copy(fixture))
  local d, rp = c.TwichUIDB, c.TwichUI.Persist.Report()
  assert(d.schema == 1 and rp.main.outcome == "migrated" and rp.main.stored == nil, tag .. ": upgraded to schema 1")
  assert(d.modules.chronicleDeaths == true and d.modules.groupCheck == false and d.modules.auctionatorSkin == false, tag .. ": the player's choices survive")
  assert(d.shareTransport == "DIRECT", tag .. ": no group or guild choice was ever made")
  for k, v in pairs(c.TwichUI.DEFAULT_MODULES) do assert(d.modules[k] ~= nil, tag .. ": " .. k .. " filled in") end
  assert(fixture.TwichUIDB.migrated == nil or d.migrated == fixture.TwichUIDB.migrated, tag .. ": the old one-time marker is left as it was")
  assert(rp.lost == 0 and not heard(c, "reset or set aside"), tag .. ": nothing lost, nothing announced")
  if fixture.TwichUIChronicleDB then
    local found
    for _, e in ipairs(c.TwichUI.Chronicle.Entries()) do if e.note == "written on " .. tag then found = true end end
    assert(found, tag .. ": the Chronicle note is still there")
  end
  local reload = boot("Oldie", copy(saved(c)))
  assert(reload.TwichUI.Persist.Report().main.outcome == "current" and same(reload.TwichUIDB, c.TwichUIDB), tag .. ": a second load changes nothing")
end

-- every earlier way of choosing how to send
local function transportFor(modules) return boot("T" .. tostring(modules), { TwichUIDB = { modules = modules } }).TwichUIDB.shareTransport end
assert(transportFor({}) == "DIRECT" and transportFor({ shareWhisper = true }) == "DIRECT" and transportFor({ shareGroup = true }) == "PARTY")
assert(transportFor({ shareGuild = true }) == "GUILD" and transportFor({ shareGroup = true, shareGuild = true }) == "PARTY")
assert(boot("TChosen", { TwichUIDB = { shareTransport = "GUILD", modules = { shareGroup = true } } }).TwichUIDB.shareTransport == "GUILD", "an existing choice is never overwritten")
for _, t in ipairs(fresh.TwichUI.Share.TRANSPORTS) do
  assert(boot("TV" .. t, { TwichUIDB = { schema = 1, shareTransport = t, modules = {} } }).TwichUIDB.shareTransport == t, t .. " is a valid transport for Persist too")
end

---------------------------------------------------------------------------
-- 7. Repeating: loading again, or running a step again, changes nothing
---------------------------------------------------------------------------
local once = copy(saved(old))
local twice = boot("Legacy", copy(once))
assert(twice.TwichUI.Persist.Report().main.outcome == "current" and same(twice.TwichUIDB, once.TwichUIDB), "loading an upgraded save again changes nothing")
local work = copy(legacy())
local ctx = { own = function(k) return type(work[k]) == "table" and work[k] or nil end, repair = function() end }
P.STEPS[1](work, ctx)
local first = copy(work)
P.STEPS[1](work, ctx)
assert(same(work, first), "the step is repeatable")
local normalized = copy(partial.TwichUIDB)
P.Normalize(normalized); P.Normalize(normalized)
assert(same(normalized, partial.TwichUIDB), "Normalize is repeatable")

---------------------------------------------------------------------------
-- 8. A failed upgrade changes nothing
---------------------------------------------------------------------------
local frozen = legacy()
local snap = copy(frozen)
local ok, step, why = P.Migrate(frozen, { [1] = function(w, c) c.own("modules").touched = true; c.own("ui").touched = true; w.shareTransport = "X"; error("boom") end }, 0, 1)
assert(ok == false and step == 1 and why:find("boom"), "the error is returned")
assert(same(frozen, snap), "the live table is exactly as it was")
ok, step, why = P.Migrate(frozen, { [1] = function(w) w.modules = 5 end }, 0, 1)
assert(ok == false and why:find("invalid%-result"), "a result that is not usable is refused")
assert(same(frozen, snap), "and nothing was copied over")
ok, step, why = P.Migrate(frozen, {}, 0, 1)
assert(ok == false and why == "no-such-step")
ok, work = P.Migrate(frozen, P.STEPS, 0, 1)
assert(ok and work.modules ~= frozen.modules and work.ui ~= frozen.ui, "the working copy has its own tables")
assert(same(frozen, snap), "making the copy changed nothing")

-- ... and the same through a real load
local failing = boot("Failing", { TwichUIDB = legacy() }, { before = function(c)
  c.TwichUI.Persist.STEPS[1] = function(w, cx) cx.own("modules").broken = true; error("synthetic failure") end
end })
local fd = failing.TwichUIDB
local want2 = legacy()
assert(fd.schema == nil, "the schema is not advanced")
assert(fd.modules.comboPoints == true and fd.ui.comboPoints.style == "bar" and fd.svTest.ok == true and fd.modules.broken == nil, "nothing the step touched was kept")
assert(fd.modules.shareGroup == true and fd.ui.trainingPosition.x == 12 and fd.modules.auctionatorSkin == false, "the player's settings are in place")
assert(failing.TwichUI.Persist.Report().main.outcome == "failed")
assert(heard(failing, "could not upgrade"), "one notice")
local retried = boot("Failing", copy(saved(failing)))
assert(retried.TwichUIDB.schema == 1 and retried.TwichUI.Persist.Report().main.outcome == "migrated", "it is tried again next load, and then works")

---------------------------------------------------------------------------
-- 9. Data from a newer TwichUI is left alone
---------------------------------------------------------------------------
local futureDb = { schema = 99, modules = { chronicle = false, newFeature = true }, newStuff = { list = { 1, 2, 3 } }, ui = { arrivalHold = "future-choice" } }
local futureSnap = copy(futureDb)
local fut = boot("Future", { TwichUIDB = futureDb })
assert(fut.TwichUIDB ~= futureDb and fut.TwichUIDB.schema == 1, "the session runs on a stand-in with defaults")
assert(fut.TwichUIDB.modules.chronicle == true, "defaults, not the newer file's values")
assert(same(futureDb, (function() local x = copy(futureDb); x.heldStored = nil; return x end)()) , "the newer data was not touched while in use")
assert(heard(fut, "newer TwichUI") and heard(fut, "Update TwichUI"), "one actionable notice")
fut.TwichUIDB.modules.chronicle = false   -- a change this session
fut.TwichUIDB.ui = { changed = true }
local out = logout(fut)
assert(out.TwichUIDB == futureDb and same(futureDb, futureSnap), "at logout the original is handed back exactly as it was")
local diagReport = fut.TwichUI.Persist.Report()
assert(diagReport.main.outcome == "future" and diagReport.main.stored == 99)

-- if the client saved the stand-in without the logout event, the next load finds the original inside it
local crashed = boot("Future2", { TwichUIDB = copy(futureSnap) })
local standIn = crashed.TwichUIDB
assert(type(standIn.heldStored) == "table")
local next2 = boot("Future2", { TwichUIDB = copy(standIn) })
assert(next2.TwichUI.Persist.Report().repairs["held-recovered"] == 1, "recovered")
assert(next2.TwichUIDB.heldStored ~= nil and same(next2.TwichUIDB.heldStored, futureSnap), "the original is back in hand (held again, being newer)")
assert(same(logout(next2).TwichUIDB, futureSnap), "and is what gets saved")

-- the Chronicle of a newer TwichUI
local futureChron = { version = 5, chars = { ["Hero - Forever"] = { entries = { { id = 1, t = 50, kind = "hologram", title = "x" } }, nextId = 2, newField = true } } }
local chronSnap = copy(futureChron)
local fc = boot("Hero", { TwichUIChronicleDB = futureChron })
assert(fc.TwichUIChronicleDB ~= futureChron and fc.TwichUI.Chronicle.Count() == 1 and fc.TwichUI.Chronicle.Entries()[1].kind == "start",
  "this session starts a fresh Chronicle; the newer one is not read")
fc.TwichUI.Chronicle.Add("note", { title = "Note", note = "added in this session" })
assert(fc.TwichUI.Persist.Report().chronicle.outcome == "future" and heard(fc, "Journey Chronicle was made by a newer"))
local fo = logout(fc)
assert(fo.TwichUIChronicleDB == futureChron and same(futureChron, chronSnap) and futureChron.version == 5, "the newer Chronicle is handed back unchanged, version included")

---------------------------------------------------------------------------
-- 10. Profiles: TwichUI has none of its own. What it does with another addon's profile keys when it
--     applies a setup: point this character at a profile that exists, never touch a profile
---------------------------------------------------------------------------
local function applyFoo(fooData, sourceProfileKeys)
  local a = boot("Pal", nil, {})
  a.TwichUIDB.setup.received["Rich-Forever"] = { created = 5, source = "Rich - Forever", tables = { FooDB = { owner = "Foo", data = fooData } } }
  a.TwichUI.Setups:Queue("apply", { "FooDB" }, "recv:Rich-Forever")
  assert(a.reloaded)
  local b = boot("Pal", saved(a), { noLogin = true })
  b.FooDB = { profileKeys = {}, profiles = { Default = { x = 0 } } }
  b.LOADED.Foo = true; b.FireEvent("ADDON_LOADED", "Foo")
  b.FireEvent("PLAYER_LOGIN")
  return b
end
local fooData = { profileKeys = { ["Rich - Forever"] = "Raid" }, profiles = { Default = { a = 1 }, Raid = { a = 2, nested = { z = 1 } } } }
local applied = applyFoo(copy(fooData))
assert(applied.FooDB.profileKeys["Pal - Forever"] == "Raid", "this character is pointed at the sender's profile")
applied.FooDB.profiles.Raid.nested.z = 99
local storedPack = applied.TwichUIDB.setup.received["Rich-Forever"]
assert(storedPack.tables.FooDB.data.profiles.Raid.nested.z == 1, "the stored setup does not share tables with the live settings")
local missing = copy(fooData); missing.profileKeys["Rich - Forever"] = "Deleted"
assert(applyFoo(missing).FooDB.profileKeys["Pal - Forever"] == "Default", "a profile that is gone falls back to Default")
local noDefault = { profileKeys = { ["Rich - Forever"] = "Deleted" }, profiles = { Other = { a = 1 } } }
local nd = applyFoo(noDefault)
assert(nd.FooDB.profileKeys["Pal - Forever"] == nil and nd.FooDB.profiles.Other.a == 1, "no valid profile: the reference is left empty, no profile is rewritten")

---------------------------------------------------------------------------
-- 11. Copies share nothing: capture, restore points, your setup, imports
---------------------------------------------------------------------------
local scan = boot("Scan", { TwichUIDB = { setup = { scanNext = true } } }, { noLogin = true })
-- (boot fires ADDON_LOADED for TwichUI only; now Foo loads with its data)
scan.FooDB = { a = 1, nested = { b = 2 } }; scan.LOADED.Foo = true; scan.FireEvent("ADDON_LOADED", "Foo"); scan.FireEvent("PLAYER_LOGIN")
local ST, RS, PT = scan.TwichUI.Setups, scan.TwichUI.Restore, scan.TwichUI.Portable
ST.db.selection.FooDB = true
local status, point = RS:Create("first")
assert(status == "created" and point.tables.FooDB.data.nested.b == 2)
ST.capture.FooDB.data.nested.b = 999
assert(point.tables.FooDB.data.nested.b == 2, "a restore point is a copy of the search, not the search")
ST:SaveMine(false)
local mineData = ST.Mine().tables.FooDB.data
ST.capture.FooDB.data.nested.b = 5
assert(mineData.nested.b == 999 and mineData ~= ST.capture.FooDB.data, "your setup is its own copy too")
local second = select(2, RS:Create("second"))
assert(second.tables.FooDB.data ~= point.tables.FooDB.data, "two restore points never share tables")

-- restoring does not change the restore point
assert(RS:Restore(point.id) == true and scan.reloaded)
local rest = boot("Scan", saved(scan), { noLogin = true })
rest.FooDB = { gone = true }; rest.LOADED.Foo = true; rest.FireEvent("ADDON_LOADED", "Foo"); rest.FireEvent("PLAYER_LOGIN")
assert(rest.FooDB.a == 1 and rest.FooDB.nested.b == 2 and rest.FooDB.gone == nil, "restored")
rest.FooDB.nested.b = "changed afterwards"
local p1 = rest.TwichUIRestoreDB.points
local back
for _, p in ipairs(p1) do if p.name == "first" then back = p end end
assert(back and back.tables.FooDB.data.nested.b == 2, "the live settings and the stored backup are separate tables")
assert(rest.TwichUIBackupDB["Scan - Forever"].tables.FooDB.data.gone == true, "the undo copy holds what was replaced")

-- an import hands over its tables once
local exported = select(2, run(PT.Export, back))
ST = rest.TwichUI.Setups
local ok2, result = run(rest.TwichUI.Portable.Check, exported)
assert(ok2 and result.blocked, "it repeats a backup that is already stored")
rest.TwichUI.Restore:Delete(back.id)
ok2, result = run(rest.TwichUI.Portable.Check, exported)
assert(ok2 and not result.blocked)
local imported = assert(rest.TwichUI.Portable.Commit(result))
assert(result.point == nil, "the checked tables now belong to the stored backup")
local again2, why2 = rest.TwichUI.Portable.Commit(result)
assert(not again2 and why2, "a second click imports nothing")
local count = 0
for _, p in ipairs(rest.TwichUI.Restore.List()) do if p.name:find("first", 1, true) then count = count + 1 end end
assert(count == 1)

-- the limits are checked again at the moment of import
rest.TwichUI.Restore.Delete(rest.TwichUI.Restore, imported.id)
ok2, result = run(rest.TwichUI.Portable.Check, exported)
assert(ok2 and not result.blocked)
for i = 1, rest.TwichUI.Portable.MAX_POINTS do
  rest.TwichUI.Restore.AddImported({ name = "filler " .. i, created = i, tables = { FooDB = { owner = "Foo", data = { i = i } } } })
end
local late, lateWhy = rest.TwichUI.Portable.Commit(result)
assert(not late and lateWhy:find("already have"), "a preview made before the list filled up cannot exceed the limit")

---------------------------------------------------------------------------
-- 12. Imports and received setups go through the same rules
---------------------------------------------------------------------------
local ST2 = rest.TwichUI.Setups
for _, name in ipairs({ "_G", "_ENV", "TwichUIDB", "TwichUIChronicleDB", "bad name", "1abc", "", 5 }) do
  assert(ST2.ValidName(name) == false, "not a settings table name: " .. tostring(name))
  assert(ST2.SafeName(name) == false)
end
rest.string = string                                  -- (the harness's globals are inherited; the game's are raw)
rest.CodeTable = { name = "x", run = function() end }
assert(ST2.SafeName("string") == false and ST2.SafeName("CodeTable") == false, "a table that holds code is not a settings table")
assert(ST2.SafeName("BrandNewDB") == true, "a name nothing uses yet is fine")
rest.PlainDB = { a = 1, b = { c = true } }
assert(ST2.SafeName("PlainDB") == true, "so is a table of plain data")
local deep = {}
local cursor = deep
for _ = 1, 70 do cursor.n = {}; cursor = cursor.n end
local okd, reasond = ST2.CheckData(deep)
assert(okd == false and reasond == "too-deep")
local cyc = { a = {} }; cyc.a.back = cyc
assert(select(2, ST2.CheckData(cyc)) == "cycle")
assert(select(2, ST2.CheckData({ f = print })) == "bad-value" and select(2, ST2.CheckData({ [print] = 1 })) == "bad-key")
assert(select(2, ST2.CheckData({ s = string.rep("x", ST2.LIMITS.string + 1) })) == "string-too-long")
assert(ST2.CheckData({ a = { b = { 1, 2, "x", true } } }) == true)

-- the global table cannot be replaced through a pending apply, whatever the saved pack says
local evil = boot("Evil", nil, {})
evil.TwichUIDB.setup.received["Mallory-Forever"] = { created = 1, source = "Mallory - Forever", tables = {
  _G = { owner = "Foo", data = { wiped = true } }, FooDB = { owner = "Foo", data = { ok = 1 } },
  deepDB = { owner = "Foo", data = deep }, cycleDB = { owner = "Foo", data = { 1 } } } }
evil.TwichUI.Setups:Queue("apply", { "_G", "FooDB", "deepDB", "cycleDB" }, "recv:Mallory-Forever")
local evil2 = boot("Evil", saved(evil), { noLogin = true })
evil2.FooDB = { ok = 0 }; evil2.LOADED.Foo = true; evil2.FireEvent("ADDON_LOADED", "Foo"); evil2.FireEvent("PLAYER_LOGIN")
assert(evil2.TwichUIDB ~= nil and type(evil2.print) == "function" and rawget(evil2, "wiped") == nil, "the environment is intact")
assert(evil2.FooDB.ok == 1, "the valid table applied")
assert(evil2.deepDB == nil, "a table nested too deeply was refused")
assert(heard(evil2, "skipped"), "and reported as skipped")

-- an incoming transfer is refused as a whole when it names something it must not or is too deep
local SH = rest.TwichUI.Share
local function incoming(tables)
  SH.incoming["Mallory-Forever"] = { id = "1", stage = "receiving", route = { "WHISPER", "Mallory" } }
  SH.handlers.data("Mallory-Forever", { id = "1", meta = { created = 1 }, keep = {}, tables = tables })
  return SH.incoming["Mallory-Forever"].stage
end
rest.TwichUIDB.setup.received["Mallory-Forever"] = nil
assert(incoming({ _G = { owner = "Foo", data = {} } }) == "failed", "_G is refused")
assert(incoming({ TwichUIDB = { owner = "Foo", data = {} } }) == "failed", "TwichUI's own data is refused")
assert(incoming({ DeepDB = { owner = "Foo", data = deep } }) == "failed", "too deep is refused")
assert(incoming({ NoOwner = { data = {} } }) == "failed")
assert(rest.TwichUIDB.setup.received["Mallory-Forever"] == nil, "none of it was stored")
rest.TwichUI.Share.incoming["Mallory-Forever"] = nil

---------------------------------------------------------------------------
-- 12b. Damaged setups, backups and restore points in a save
---------------------------------------------------------------------------
local damaged = boot("Damaged", {
  TwichUIDB = { schema = 1, modules = {}, setup = {
    detected = { FooDB = { owner = "Foo", bytes = 5 }, Broken = 3, [4] = { owner = "Foo" } },
    selection = { FooDB = true, Weird = "x" }, trusted = { ["Rich-Forever"] = true, ["Other-Forever"] = "yes" },
    received = {
      ["Good-Forever"] = { created = 5, version = 2, sourceName = "Good", tables = { FooDB = { owner = "Foo", data = { a = 1 } }, Junk = 3, NoData = { owner = "Foo" } } },
      ["Bad-Forever"] = { created = 5, tables = "nothing" },
      ["Odd-Forever"] = { created = "yesterday", version = {}, sourceName = 7, tables = { FooDB = { owner = "Foo", data = {} } } },
      [12] = {},
    },
    pending = { mode = "explode", tables = {}, source = "x", char = "Damaged - Forever" },
    scanNext = "later", restoreNext = 5, eui = 4,
  } },
  TwichUIShareDB = { pack = { created = 1, tables = 5 } },
  TwichUIBackupDB = { ["Damaged - Forever"] = { stamp = 1, created = 1, tables = { FooDB = { present = true, data = { a = 1 } }, Bad = { present = true, data = 3 } }, owners = { FooDB = "Foo", x = 1 } },
    ["Gone - Forever"] = "nothing" },
  TwichUIRestoreDB = { points = { 5, { id = "p1", name = "Keep me", created = 10, tables = { FooDB = { owner = "Foo", data = { a = 1 } }, Bad = 7 }, extra = "kept" },
    { name = "No id", created = 20, tables = {} }, { id = "p1", name = "", created = 30, tables = {} }, { id = "p4", name = "No tables", tables = 5 },
    [7] = { id = "p7", name = "After a gap", created = 40, tables = { FooDB = { owner = "Foo", data = { a = 7 } } } } } },
})
local dd = damaged.TwichUIDB.setup
local ST3 = damaged.TwichUI.Setups
assert(dd.detected.FooDB and dd.detected.Broken == nil and dd.selection.FooDB == true and dd.selection.Weird == nil)
assert(dd.trusted["Rich-Forever"] == true and dd.trusted["Other-Forever"] == nil)
assert(dd.received["Good-Forever"].tables.FooDB.data.a == 1 and dd.received["Good-Forever"].tables.Junk == nil and dd.received["Good-Forever"].tables.NoData == nil, "only the unreadable table of a received setup goes")
assert(dd.received["Bad-Forever"] == nil and dd.received[12] == nil, "a setup with nothing to read goes (the sender can send it again)")
local odd2 = dd.received["Odd-Forever"]
assert(odd2 and odd2.created == nil and odd2.version == nil and odd2.sourceName == nil and next(odd2.tables) ~= nil, "unreadable labels are dropped; the settings are kept")
assert(dd.pending == nil and dd.scanNext == nil and dd.restoreNext == nil and dd.eui == nil)
assert(damaged.TwichUIShareDB.pack == nil, "your own setup that cannot be read is dropped; saving it again rebuilds it")
local bk = damaged.TwichUIBackupDB
assert(bk["Damaged - Forever"].tables.FooDB.data.a == 1 and bk["Damaged - Forever"].tables.Bad == nil and bk["Damaged - Forever"].owners.x == nil and bk["Gone - Forever"] == nil)
local pts = damaged.TwichUI.Restore.List()
local names = {}
for _, p in ipairs(pts) do names[p.name] = p end
assert(names["Keep me"] and names["Keep me"].extra == "kept" and names["Keep me"].tables.FooDB and names["Keep me"].tables.Bad == nil, "a backup is kept; unknown fields too")
assert(names["No id"] and names["After a gap"] and names["After a gap"].tables.FooDB.data.a == 7, "the entry after a gap in the list is not lost")
assert(#pts == 5 and names["No tables"] and next(names["No tables"].tables) == nil, "five backups remain")
local seenIds = {}
for _, p in ipairs(pts) do assert(type(p.id) == "string" and not seenIds[p.id], "every backup has its own id"); seenIds[p.id] = true end
assert(damaged.TwichUI.Persist.Report().repairs["restore-point-dropped"] == 1, "the one entry that was not a backup was dropped")
assert(not damaged.TwichUI.Restore:Restore("nope") and select(2, damaged.TwichUI.Restore:Restore("nope")):find("isn't there"), "restoring something missing says so")
assert(not damaged.TwichUI.Restore:Restore(names["No tables"].id), "a backup with nothing in it cannot be queued")
assert(heard(damaged, "reset or set aside"), "the damage was reported once")

---------------------------------------------------------------------------
-- 13. Nothing temporary is saved or comes back
---------------------------------------------------------------------------
local FILES = { "modules/Notify.lua", "diag/Diagnostics.lua" }
local tr = boot("Trans", nil, { files = FILES })
local N, D = tr.TwichUI.Notify, tr.TwichUI.Diag
N.Register("probe", { label = "Probe", show = function() return true end, dismiss = function() end, sample = function() return {} end })
assert(N.Submit({ kind = "probe", id = "a", payload = {} }) and N.Submit({ kind = "probe", id = "b", payload = {} }))
D.Start()
assert(D.Tracing(), "tracing is on")
tr.TwichUI.Share.outgoing = { target = "Someone-Forever", id = "9", stage = "sending" }
tr.TwichUI.Share.incoming["Friend-Forever"] = { id = "7", stage = "receiving", parts = {}, got = 10 }
local sv = logout(tr)

-- every saved variable is plain data, and only declared fields are present
local ST4 = tr.TwichUI.Setups
for _, name in ipairs(SV) do
  assert(ST4.CheckData(sv[name]), name .. " holds only plain data (no functions, frames, timers or cycles)")
end
local TOP = { schema = true, modules = true, ui = true, gear = true, setup = true, storedData = true, shareTransport = true, whisperProbe = true }
for k in pairs(sv.TwichUIDB) do assert(TOP[k], "undeclared top-level field in TwichUIDB: " .. tostring(k)) end
local SETUP = { detected = true, selection = true, received = true, trusted = true, recommend = true, scanNext = true, restoreNext = true,
  lastScan = true, pending = true, eui = true }
for k in pairs(sv.TwichUIDB.setup) do assert(SETUP[k], "undeclared field in TwichUIDB.setup: " .. tostring(k)) end
local function contains(t, needle, seen)
  seen = seen or {}
  if type(t) == "string" then return t:find(needle, 1, true) ~= nil end
  if type(t) ~= "table" or seen[t] then return false end
  seen[t] = true
  for k, v in pairs(t) do if contains(k, needle, seen) or contains(v, needle, seen) then return true end end
  return false
end
for _, needle in ipairs({ "probe", "Someone-Forever", "Friend-Forever", "trace", "queue" }) do
  for _, name in ipairs(SV) do assert(not contains(sv[name], needle), name .. " must not hold transient state: " .. needle) end
end

-- reloading brings none of it back
local tr2 = boot("Trans", sv, { files = FILES })
tr2.TwichUI.Notify.Register("probe", { label = "Probe", show = function() return true end, dismiss = function() end })
local state = tr2.TwichUI.Notify.State()
assert(#state.waiting == 0 and #state.active == 0, "no notice is replayed")
assert(not tr2.TwichUI.Diag.Tracing(), "tracing does not resume")
assert(tr2.TwichUI.Share.outgoing == nil and next(tr2.TwichUI.Share.incoming) == nil, "no transfer resumes")

---------------------------------------------------------------------------
-- 14. The Chronicle keeps what the player wrote
---------------------------------------------------------------------------
local chron = {
  version = 1,
  chars = {
    ["Hero - Forever"] = {
      entries = {
        { id = 1, t = 100, kind = "start", title = "Chronicle begun" },
        { id = 2, t = 200, kind = "note", title = "Note", note = "first note" },
        { id = 2, t = 300, kind = "note", title = "Note", note = "repeats an id" },
        { id = 5, t = 400, kind = "note", note = "no title" },
        { id = 6, kind = "note", title = "Note", note = "no date" },
        { id = 7, t = nan, kind = "note", title = "Note", note = "unreadable date" },
        { id = 8, t = 500, kind = "hologram", title = "from a newer version", extra = { 1, 2 } },
        { id = 9, t = 600, kind = "level", title = "Reached level 10", level = 10 },
        { id = 10, kind = "level", title = "automatic and undated" },
        { id = 11, t = 700, kind = "note", title = "", note = "" },
        "junk",
        [14] = { id = 14, t = 800, kind = "note", title = "Note", note = "after a gap" },
      },
      nextId = 3, tracking = true, lastZone = "Elwynn Forest", unknownField = { keep = true },
      journey = { baseLevel = 1, lastLevel = 9, riding = { [33388] = true }, futureThing = { x = 1 } },
    },
    ["Broken - Forever"] = "text",
  },
}
local ch = boot("Hero", { TwichUIChronicleDB = copy(chron) })
local C = ch.TwichUI.Chronicle
local rec = C.Record()
local texts = {}
for _, e in ipairs(C.Entries()) do if e.kind == "note" then texts[e.note] = e end end
for _, want in ipairs({ "first note", "repeats an id", "no title", "no date", "unreadable date", "after a gap" }) do
  assert(texts[want], "kept the note: " .. want)
end
assert(texts["no title"].title == "Note" and texts["no date"].t == nil, "a missing title is made good; a missing date is not invented")
local ids = {}
for _, e in ipairs(C.Entries()) do assert(type(e.id) == "number" and not ids[e.id], "unique ids"); ids[e.id] = true end
assert(rec.nextId > 14, "new ids come after every id in use")
assert(#rec.unreadable == 1 and rec.unreadable[1].kind == "hologram" and rec.unreadable[1].extra[2] == 2, "an entry of an unknown kind is set aside unchanged")
assert(C.Count() == 8, "eight readable entries: " .. C.Count())
assert(rec.lastZone == "Elwynn Forest" and rec.unknownField.keep == true and rec.journey.futureThing.x == 1 and rec.journey.riding[33388], "unknown fields are carried over")
assert(ch.TwichUIChronicleDB.chars["Broken - Forever"] == nil and ch.TwichUI.Persist.Report().repairs["chronicle-record-dropped"] == 1)
local undatedFirst = C.Entries()[1]
assert(type(undatedFirst.t) ~= "number" or undatedFirst.t ~= undatedFirst.t or undatedFirst.t == 100, "entries without a date sort first, nothing is fabricated")
local added = assert(C.Add("note", { title = "Note", note = "still works" }), "adding works with undated entries present")
assert(added.id > 11)
assert(C.Add("level", { title = "Reached level 11", level = 11 }), "so does an automatic entry (duplicate check skips undated)")
-- repeated load changes nothing
local once2 = copy(logout(ch).TwichUIChronicleDB)
local twice2 = boot("Hero", { TwichUIChronicleDB = copy(once2) })
assert(same(twice2.TwichUIChronicleDB, once2), "loading again changes nothing")
assert(twice2.TwichUI.Persist.Report().repairs["chronicle-entry-set-aside"] == nil, "the entry set aside is not set aside again")

-- notes are never removed to make room; automatic entries go first
local many = { version = 1, chars = { ["Hero - Forever"] = { entries = {}, nextId = 1 } } }
for i = 1, 12 do many.chars["Hero - Forever"].entries[i] = { id = i, t = i, kind = "note", title = "Note", note = "n" .. i } end
for i = 13, 20 do many.chars["Hero - Forever"].entries[i] = { id = i, t = i, kind = "zone", title = "Zone " .. i } end
local lim = boot("Hero", { TwichUIChronicleDB = many }, { before = function(c) c.TwichUI.Chronicle.MAX_ENTRIES = 10 end })
local kinds = {}
for _, e in ipairs(lim.TwichUI.Chronicle.Entries()) do kinds[e.kind] = (kinds[e.kind] or 0) + 1 end
assert(kinds.note == 12 and (kinds.zone or 0) == 0, "all twelve notes stay even though the limit is ten: " .. tostring(kinds.note))
assert(lim.TwichUI.Persist.Report().repairs["chronicle-trimmed"] == 8, "the automatic entries made the room")

-- the Chronicle is not part of sharing or backups
assert(boot("Hero").TwichUI.Setups.SafeName("TwichUIChronicleDB") == false)

---------------------------------------------------------------------------
-- Diagnostics: the report says what happened, with no contents
---------------------------------------------------------------------------
local secret = boot("Zorblax", { TwichUIDB = (function() local d = legacy(); d.setup.received["Rich-Forever"] = { created = 1, sourceName = "FriendlyName", tables = { SecretAddonDB = { owner = "Foo", data = { password = "hunter2" } } } }; return d end)(),
  TwichUIChronicleDB = { version = 1, chars = { ["Zorblax - Forever"] = { entries = { { id = 1, t = 5, kind = "note", title = "Note", note = "PRIVATE NOTE TEXT" }, { id = 2, t = 6, kind = "hologram", title = "x" } }, nextId = 3 } } } },
  { files = { "diag/Diagnostics.lua", "diag/Saved.lua", "diag/Window.lua" } })
local report = secret.TwichUI.Diag.Build()
local function Has(text, needle) return text:find(needle, 1, true) ~= nil end
assert(Has(report, "Saved data") and Has(report, "settings schema: stored none") and Has(report, "upgraded at this load"), "stored and current versions, and the outcome")
assert(Has(report, "repair legacy-key-removed: 6") and Has(report, "repair chronicle-entry-set-aside: 1"), "repairs by stable code")
for _, leak in ipairs({ "Zorblax", "PRIVATE NOTE TEXT", "hunter2", "SecretAddonDB", "FriendlyName", "Rich-Forever" }) do
  assert(not Has(report, leak), "the report must not contain: " .. leak)
end
local futureReport = boot("Zorblax", { TwichUIDB = { schema = 7 } }, { files = { "diag/Diagnostics.lua", "diag/Saved.lua" } }).TwichUI.Diag.Build()
assert(Has(futureReport, "newer-saved-data") and Has(futureReport, "saved by a newer TwichUI"))

print("PERSIST TESTS PASSED")
