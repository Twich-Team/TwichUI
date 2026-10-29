dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- "Force re-apply" (LY.Plan / LY.Apply opts.force): an account an earlier install left stuck can be set up again. A forced plan
-- sets this character's own earlier records aside and takes over a profile no record claims; it never lifts what is not
-- TwichUI's to lift (a newer TwichUI's record, an unusable EllesmereUI). TwichUI's code is the real one;
-- EllesmereUI is the stand-in (layouts_mock.lua). Nothing here is the game.

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local EUI = { defaults = true }
local TARGET = "TwichUI Adventure"

local function Engine(c)
  assert(c.TwichUI.LayoutsLauncher.Load())
  return c.TwichUI.Layouts
end
local function Reload(name, c, opts) return LM.Boot(name, LM.Logout(c), opts or { eui = EUI }) end

local c0 = LM.Boot("Table", nil, { eui = EUI })
local L0 = Engine(c0)
local PKG, CLASSIC = L0.CLASSIC_PACKAGE, L0.CLASSIC_VARIANT

local function Installed(name)
  local c = LM.Boot(name, nil, { eui = EUI })
  local L = Engine(c)
  local plan = L.Plan(PKG, CLASSIC)
  assert(plan.ok, "plan: " .. tostring(plan.blocked[1] and plan.blocked[1].code))
  local ok, res = L.Apply(PKG, CLASSIC, plan.key)
  assert(ok and (res.state == "applied" or res.state == "verified"), "apply: " .. tostring(ok and res.state or res))
  return Reload(name, c)
end
local function Codes(plan)
  local out = {}
  for _, b in ipairs(plan.blocked) do out[#out + 1] = b.code end
  return table.concat(out, ",")
end
local function ForceOpts() return { force = true } end

---------------------------------------------------------------------------
-- 1. Records an earlier install left: a Restore that never finished, an Undo that never finished, another package's, one that can't
--    be read. Each blocks; a forced plan sets it aside and the install that follows is a new one with its own record.
---------------------------------------------------------------------------
for _, case in ipairs({
  { "restore-partial", function(c) c.TwichUIDB.layouts.install.state = "restore-partial" end, "restore-unfinished" },
  { "undo-partial", function(c) c.TwichUIDB.layouts.install.state = "undo-partial" end, "undo-unfinished" },
  { "restoring", function(c) c.TwichUIDB.layouts.install.state = "restoring" end, "restore-pending" },
  { "other package", function(c) c.TwichUIDB.layouts.install.package = "someone-elses" end, "journal-other-package" },
  { "damaged", function(c) c.TwichUIDB.layouts.install = { v = 1, state = "gibberish" } end, "journal-damaged" },
}) do
  local name, break_, code = case[1], case[2], case[3]
  local c = Installed("Stuck " .. name)
  break_(c)
  local L = Engine(c)
  local plain = L.Plan(PKG, CLASSIC)
  Check(not plain.ok and plain.blocked[1].code == code, "1. " .. name .. " blocks a plain plan (" .. Codes(plain) .. ")")
  local plan = L.Plan(PKG, CLASSIC, ForceOpts())
  Check(plan.ok and plan.forced and plan.forced.replaced ~= nil, "   forced, it plans (" .. Codes(plan) .. ")")
  Check(plan.mode == "new" and plan.journal == nil and plan.update == nil, "   as a new install, not an update of the broken record")
  Check(plan.key ~= L.Plan(PKG, CLASSIC).key, "   with a key of its own")
  local ok, res = L.Apply(PKG, CLASSIC, plain.key, ForceOpts())
  Check(not ok and res == "stale", "   the plain plan's key can't apply a forced plan")
  local done, result = L.Apply(PKG, CLASSIC, plan.key, ForceOpts())
  Check(done and (result.state == "applied" or result.state == "verified"), "   and it applies (" .. tostring(done and result.state or result) .. ")")
  local j = L.Journal.Read()
  Check(j and (j.state == "applied" or j.state == "verified") and j.snapshot and j.snapshot.twichui, "   leaving a record that can be read, with its own snapshot")
end

---------------------------------------------------------------------------
-- 2. A profile with the install's name that no record claims (the record was lost after a failed install)
---------------------------------------------------------------------------
do
  local c = Installed("Taken")
  c.TwichUIDB.layouts = nil   -- the records are gone; both profiles remain
  local L = Engine(c)
  local plain = L.Plan(PKG, CLASSIC)
  Check(not plain.ok and plain.parts.ellesmereui.blocked == "target-taken" and plain.parts.twichui.blocked == "target-taken",
    "2. profiles with the install's name and no record block a plain plan")
  local profiles = {}
  for name in pairs(c.EllesmereUIDB.profiles) do profiles[name] = c.EllesmereUIDB.profiles[name] end
  local plan = L.Plan(PKG, CLASSIC, ForceOpts())
  Check(plan.ok and plan.parts.ellesmereui.adopted and plan.parts.twichui.adopted, "   a forced plan takes both over, and says so")
  local home = plan.parts.ellesmereui.forcedHome
  Check(home and home ~= TARGET and profiles[home] and plan.parts.ellesmereui.home == home,
    "   EllesmereUI's profile is in use: it leaves it for another first (never deleting the profile in use)")
  Check(plan.forced.replaced == nil, "   no record was set aside, so none is claimed")
  local ok, res = L.Apply(PKG, CLASSIC, plan.key, ForceOpts())
  Check(ok and (res.state == "applied" or res.state == "verified"), "   it applies")
  local j = L.Journal.Read()
  Check(j.snapshot.ellesmereui.active == home and j.snapshot.ellesmereui.created == false,
    "   Restore goes back to that one, and the profile that was already there isn't recorded as made by the install")
  Check(c.EllesmereUIDB.profiles[TARGET] ~= nil, "   and EllesmereUI's profile of that name is the layout's")
  local same = true
  for name, prof in pairs(profiles) do if name ~= TARGET and c.EllesmereUIDB.profiles[name] ~= prof then same = false end end
  for name in pairs(c.EllesmereUIDB.profiles) do if name ~= TARGET and not profiles[name] then same = false end end
  Check(same, "   no other profile was made or touched")
end

---------------------------------------------------------------------------
-- 3. An install that already matches: refused as "nothing" unless forced
---------------------------------------------------------------------------
do
  local c = Installed("Matches")
  local L = Engine(c)
  L.Continue()
  local plan = L.Plan(PKG, CLASSIC)
  local ok, why = L.Apply(PKG, CLASSIC, plan.key)
  Check(not ok and why == "nothing", "3. an install that already matches is refused (" .. tostring(why) .. ")")
  local forced = L.Plan(PKG, CLASSIC, ForceOpts())
  local imports = c.EllesmereUI.called("ImportProfileSilent")
  local done, res = L.Apply(PKG, CLASSIC, forced.key, ForceOpts())
  Check(done and res.changed ~= false, "   forced, it goes ahead")
  Check(c.EllesmereUI.called("ImportProfileSilent") == imports + 1, "   and EllesmereUI's profile is imported again")
end

---------------------------------------------------------------------------
-- 4. What force does not lift
---------------------------------------------------------------------------
do
  local c = Installed("Newer")
  c.TwichUIDB.layouts.install.v = 99
  local L = Engine(c)
  local p = L.Plan(PKG, CLASSIC, ForceOpts())
  Check(not p.ok and Codes(p) == "journal-newer", "4. a record from a newer TwichUI still blocks (" .. Codes(p) .. ")")

  local o = Installed("Other")
  o.TwichUIDB.layouts.install.char = "Someone-Else"
  o.TwichUIDB.layouts.install.state = "restore-partial"
  local LO = Engine(o)
  p = LO.Plan(PKG, CLASSIC)
  Check(not p.ok and Codes(p):find("journal-other-character", 1, true), "   another character's record blocks a plain plan (" .. Codes(p) .. ")")
  p = LO.Plan(PKG, CLASSIC, ForceOpts())
  Check(p.ok and p.forced.otherCharacter == true and p.parts.twichui.blocked == nil, "   a forced plan sets it aside, and says it was another character's (" .. Codes(p) .. ")")
  local okO, resO = LO.Apply(PKG, CLASSIC, p.key, ForceOpts())
  Check(okO and LO.Journal.Read() and LO.Journal.Read().char ~= "Someone-Else", "   and the install that follows is this character's own")

  local e = LM.Boot("NoEUI", nil, { eui = EUI })
  local LE = Engine(e)
  e.EllesmereUI._firstInstallPending = true
  p = LE.Plan(PKG, CLASSIC, ForceOpts())
  Check(not p.ok and p.parts.ellesmereui.blocked == "eui-first-run", "   EllesmereUI's first-run picker still blocks")

  local k = Installed("Combat")
  local LK = Engine(k)
  k.TwichUIDB.layouts.install.state = "restore-partial"
  local plan = LK.Plan(PKG, CLASSIC, ForceOpts())
  k.combat = true
  local ok, why = LK.Apply(PKG, CLASSIC, plan.key, ForceOpts())
  Check(not ok and why == "combat", "   combat still refuses")
  Check(k.TwichUIDB.layouts.install.state == "restore-partial", "   and leaves the record as it was")
  Check(LK.Plan(PKG, CLASSIC, { force = "yes" }).forced == nil, "   only true forces; any other value doesn't")
end

---------------------------------------------------------------------------
-- 5. A forced install that changes nothing puts the record it set aside back
---------------------------------------------------------------------------
do
  local c = Installed("Refused")
  c.TwichUIDB.layouts.install.state = "restore-partial"
  local before = c.TwichUIDB.layouts.install
  local L = Engine(c)
  c.EllesmereUI.EncodePayload = function() return nil end   -- EllesmereUI is first in the order: refusing here changes nothing
  local plan = L.Plan(PKG, CLASSIC, ForceOpts())
  Check(plan.ok, "5. planned")
  local ok, res = L.Apply(PKG, CLASSIC, plan.key, ForceOpts())
  Check(ok and res.state == "failed" and res.changed == false, "   the install fails without changing anything")
  Check(c.TwichUIDB.layouts.install == before and before.state == "restore-partial", "   and the record it set aside is back, as it was")
end

if failures > 0 then print(failures .. " check(s) FAILED") os.exit(1) end
print("OK")
