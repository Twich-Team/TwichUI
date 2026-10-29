dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Layout packages, Phase 2 (TwichUI_Layouts; docs/layouts/): package checks, composing the layers, the canonical form,
-- the TwichUI and EllesmereUI adapters, the install record, apply order, partial failure, verification, restore,
-- the check after a reload, installing again, and that nothing outside the install changes.
-- TwichUI's sharing, profile and feature code is the real one. EllesmereUI is a stand-in with the real functions' shape
-- (EllesmereUI_Profiles.lua, 9.6.8): this proves TwichUI's side only. Failure paths use mocked adapters. Nothing here is
-- the game: the in-game checks are listed in docs/layouts/implementation-status.md.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end

local function Copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local o = {}
  seen[t] = o
  for k, v in pairs(t) do o[Copy(k, seen)] = Copy(v, seen) end
  return setmetatable(o, getmetatable(t))
end

local function Same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local SV = { "TwichUIDB", "TwichUIBackupDB", "TwichUIShareDB", "TwichUIRestoreDB", "TwichUIChronicleDB", "EllesmereUIDB" }

---------------------------------------------------------------------------
-- A stand-in EllesmereUI. Export strings are kept in one table shared by every client (a real EllesmereUI reads any
-- export). ImportProfileSilent does what the real one is documented to do: cleanSlate deletes a profile of that name,
-- applyUIScale = false strips the scale, the import builds on the active profile and replaces whole module blobs,
-- and it activates the profile unless the spec is locked.
---------------------------------------------------------------------------
local STRINGS, NSTR = {}, 0
local SEQ = {}   -- the order of the calls that change something, across TwichUI and EllesmereUI
local function Encode(payload)
  NSTR = NSTR + 1
  local s = ("!EUI_t%d_"):format(NSTR) .. ("x"):rep(12)
  STRINGS[s] = Copy(payload)
  return s
end

local function EUIDB()
  return {
    activeProfile = "Mine",
    profiles = {
      Mine = { addons = { EllesmereUIMinimap = { minimap = { enabled = true, coordsPosition = "topLeft" } },
                          EllesmereUIActionBars = { bars = { 1, 2 } }, EllesmereUIDataBars = { characters = { x = 1 }, keep = 1 } },
               fonts = { global = "Mine font" }, unlockLayout = { anchors = { a = 1 } } },
      Raid = { addons = { EllesmereUINameplates = { w = 5 } } },
    },
    profileOrder = { "Mine", "Raid" }, specProfiles = { [62] = "Raid" }, ppUIScale = 0.8, clickCast = { bind = 1 },
  }
end

local function InstallEUI(env, db, opts)
  opts = opts or {}
  local E = { IS_FOREVER = not opts.retail, calls = {}, _ADDON_DB_MAP = {} }
  env.EllesmereUIDB = db
  local function Call(name, a) E.calls[#E.calls + 1] = { name, a }; SEQ[#SEQ + 1] = "eui." .. name end
  function E.GetProfilesDB() db.profiles = db.profiles or {}; db.profileOrder = db.profileOrder or {}; db.specProfiles = db.specProfiles or {}; return db end
  function E.GetActiveProfileName() return db.activeProfile or "Default" end
  function E.GetProfileList() return db.profileOrder, db.profiles end
  function E.IsModuleAddonLoaded() return true end
  function E.ExportProfile(name, folders, layout, cdm, specs, globals, overrides, skins)
    Call("ExportProfile", { name = name, layout = layout, cdm = cdm, globals = globals, overrides = overrides, skins = skins })
    local p = db.profiles[name]
    if not p then return nil end
    local data = { addons = Copy(p.addons), assignedSpecs = { 62 } }
    if layout then data.unlockLayout = Copy(p.unlockLayout) end
    if globals then data.uiScale, data.fonts, data.customColors = db.ppUIScale, Copy(p.fonts), { c = 1 } end
    if cdm then data.cdmSpells = { s = 1 } end
    if overrides then data.specOverrides = { o = 1 } end
    return Encode({ version = 3, type = "full", data = data })
  end
  function E.EncodePayload(p) Call("EncodePayload"); if opts.encodeFails then return nil end return Encode(p) end
  function E.DecodeImportString(s)
    local p = STRINGS[s]
    if not p then return nil, "Failed to decode string" end
    return Copy(p)
  end
  function E.ImportProfile() error("TwichUI never calls ImportProfile directly") end
  function E.SwitchProfile(name) Call("SwitchProfile", name); if db.profiles[name] then db.activeProfile = name end end
  function E.DeleteProfile(name)
    Call("DeleteProfile", name)
    db.profiles[name] = nil
    for i, n in ipairs(db.profileOrder) do if n == name then table.remove(db.profileOrder, i) break end end
    for spec, n in pairs(db.specProfiles) do if n == name then db.specProfiles[spec] = nil end end
    if db.activeProfile == name then db.activeProfile = "Default" end
  end
  -- as the real one (EllesmereUI_Profiles.lua RenameProfile): the same table under the new name; order, spec assignments
  -- and the active profile follow it
  function E.RenameProfile(old, new)
    Call("RenameProfile", { old, new })
    if not db.profiles[old] then return end
    db.profiles[new], db.profiles[old] = db.profiles[old], nil
    for i, n in ipairs(db.profileOrder) do if n == old then db.profileOrder[i] = new break end end
    for spec, n in pairs(db.specProfiles) do if n == old then db.specProfiles[spec] = new end end
    if db.activeProfile == old then db.activeProfile = new end
  end
  function E.ImportProfileSilent(o)
    Call("ImportProfileSilent", Copy(o))
    if env.InCombatLockdown() then return false, "in combat" end
    local payload = E.DecodeImportString(o.importString)
    if type(payload) ~= "table" then return false, "could not decode import string" end
    if o.applyUIScale == false then payload.data.uiScale, payload.data.applyUIScale = nil, nil end
    if not o.autoAssignSpecs then payload.data.assignedSpecs = nil end
    if o.cleanSlate ~= false and db.profiles[o.profileName] then E.DeleteProfile(o.profileName) end
    E.imported = Copy(payload)
    if opts.failImport then return false, "Unknown profile type" end
    local merged = Copy(db.profiles[db.activeProfile] or {})
    merged.addons = merged.addons or {}
    for k, v in pairs(payload.data.addons or {}) do merged.addons[k] = Copy(v) end
    -- the root keys the real import takes from a payload (ImportProfile: fonts, colours, dark mode, accent, migration stamps, layout)
    for _, k in ipairs({ "fonts", "customColors", "darkMode", "euiAccent", "_migrations", "unlockLayout" }) do if payload.data[k] then merged[k] = Copy(payload.data[k]) end end
    db.profiles[o.profileName] = merged
    table.insert(db.profileOrder, o.profileName)
    if type(payload.data.uiScale) == "number" then db.ppUIScale = payload.data.uiScale end
    if opts.throwAfterCreate then error("boom inside the import") end
    if opts.touchOther then db.profiles.Raid = Copy(db.profiles.Raid) end
    if opts.specLocked then return true, nil, "spec_locked" end
    db.activeProfile = o.profileName
    return true, nil
  end
  function E.RegisterExternalInstaller(name) E.installer = name end
  -- What the real one does as it loads: fills its defaults into every profile's blobs.
  function E.Loaded()
    for _, p in pairs(db.profiles or {}) do
      local m = p.addons and p.addons.EllesmereUIMinimap
      if m then m.minimap = m.minimap or {}; if m.minimap.borderSize == nil then m.minimap.borderSize = 1 end end
    end
  end
  function E.called(name) local n = 0 for _, c in ipairs(E.calls) do if c[1] == name then n = n + 1 end end return n end
  env.EllesmereUI = E
  return E
end

---------------------------------------------------------------------------
-- A client, loaded from saved variables as the game does: TwichUI, then EllesmereUI, then login. The layouts addon is
-- loaded on demand from its own .toc.
---------------------------------------------------------------------------
local function LayoutFiles()
  local list = {}
  for line in io.lines(REPO .. "TwichUI_Layouts/TwichUI_Layouts.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then list[#list + 1] = REPO .. "TwichUI_Layouts/" .. (line:gsub("\\", "/")) end
  end
  return list
end

local function Boot(name, sv, opts)
  opts = opts or {}
  local E
  local c = SettingsClient({ name = name, beforeInit = function(c)
    c.said = {}
    c.print = function(s) c.said[#c.said + 1] = tostring(s) end
    c.combat = false
    c.InCombatLockdown = function() return c.combat end
    for _, n in ipairs(SV) do if sv and sv[n] ~= nil then c[n] = Copy(sv[n]) end end
    if not opts.noEUI then
      E = InstallEUI(c, c.EllesmereUIDB or EUIDB(), opts.eui)
      local fire = c.FireEvent
      c.FireEvent = function(e, a, ...)
        fire(e, a, ...)
        if e == "ADDON_LOADED" and a == "!!!TwichUI" then E.Loaded(); c.LOADED.EllesmereUI = true; fire("ADDON_LOADED", "EllesmereUI") end
      end
    end
  end })
  c.layoutLoads = 0
  local settingsLoad = c.C_AddOns.LoadAddOn
  c.C_AddOns.LoadAddOn = function(addon)
    if addon ~= "TwichUI_Layouts" then return settingsLoad(addon) end
    c.layoutLoads = c.layoutLoads + 1
    if opts.layoutsMissing then return false, "MISSING" end
    if not c.LOADED.TwichUI_Layouts then
      for _, f in ipairs(LayoutFiles()) do
        local chunk = assert(loadfile(f)); setfenv(chunk, c); chunk("TwichUI_Layouts", {})
      end
      c.LOADED.TwichUI_Layouts = true
    end
    return true
  end
  c.E = E
  if opts.catchErrors then
    c.errors = {}
    c.geterrorhandler = function() return function(e) c.errors[#c.errors + 1] = tostring(e) end end
  end
  RunLongTimers(5)
  return c
end

local function Logout(c)
  c.FireEvent("PLAYER_LOGOUT")
  local s = {}
  for _, n in ipairs(SV) do s[n] = Copy(c[n]) end
  return s
end

local function Heard(c, text)
  for _, s in ipairs(c.said) do if s:find(text, 1, true) then return true end end
  return false
end

local function Load(c)
  assert(c.TwichUI.LayoutsLauncher.Load())
  return c.TwichUI.Layouts
end

---------------------------------------------------------------------------
-- 1. The core runs without the layouts addon: nothing loads it at login, and the command says why it can't
---------------------------------------------------------------------------
local a = Boot("Rich")
local R = a.TwichUI
Check(R.LayoutsLauncher and a.layoutLoads == 0 and R.Layouts == nil, "nothing loads the layout tools at login")
Check(a.E.installer == nil, "EllesmereUI's first-run picker is left alone without an install under way")
do
  local m = Boot("Missing", nil, { layoutsMissing = true })
  m.SlashCmdList.TWICHUI("layout plan")
  Check(Heard(m, "TwichUI_Layouts, is missing"), "a missing layouts addon is explained")
  Check(m.TwichUI.LayoutsLauncher.Snapshot().failed == "MISSING", "and the reason is kept for the troubleshooting report")
end

local LY = Load(a)
local TA, EA = LY.TwichUIAdapter, LY.EllesmereAdapter
Check(LY.ready and LY.ADAPTERS.twichui == TA and LY.ADAPTERS.ellesmereui == EA, "both adapters are registered")

---------------------------------------------------------------------------
-- 2. The canonical form and the fingerprint
---------------------------------------------------------------------------
do
  local x = {}; x.b = 2; x.a = { 3, 4 }; x[1] = true
  local y = {}; y[1] = true; y.a = { 3, 4 }; y.b = 2
  Check(LY.Canon(x) == LY.Canon(y), "key order does not matter")
  local seen = {}
  for _, v in ipairs({ false, 0, "", "0", "false" }) do
    local c = LY.Canon(v)
    Check(not seen[c], "distinct canonical text for " .. tostring(v) .. " (" .. type(v) .. ")")
    seen[c] = true
  end
  Check(LY.Canon(nil) ~= LY.Canon(false) and LY.Fingerprint(nil) ~= LY.Fingerprint(""), "missing differs from false and empty")
  Check(LY.Canon({ a = false }) ~= LY.Canon({}), "a false value is not a missing one")
  local cyc = {}; cyc.self = cyc
  Check(select(2, LY.Canon(cyc)) == "cycle", "a cycle is refused")
  local deep = {}; local t = deep
  for _ = 1, 20 do t.n = {}; t = t.n end
  Check(select(2, LY.Canon(deep)) == "depth", "too deep is refused")
  Check(select(2, LY.Canon({ f = print })) == "type", "a function is refused")
  Check(select(2, LY.Canon({ [{}] = 1 })) == "key", "a table key is refused")
  Check(select(2, LY.Canon(0 / 0)) == "number", "NaN is refused")
  local big = {}
  for i = 1, 60000 do big[i] = i end
  Check(select(2, LY.Canon(big)) == "size", "too many values are refused")
  local shared = { 1 }
  Check(LY.Canon({ a = shared, b = shared }) ~= nil, "a table seen twice (not a cycle) is fine")
  Check(LY.Canon(0.1) == "n0.10000000000000001;" and LY.Canon(-0) == LY.Canon(0), "numbers at full precision; -0 is 0")
  Check(#LY.Fingerprint(("x"):rep(500)) < 30 and LY.Fingerprint("short"):sub(1, 1) == "=", "a long value's fingerprint is short")
  Check(LY.Canon(LY.REMOVE) == "R", "REMOVE has its own text")
end

---------------------------------------------------------------------------
-- 3. Composing: precedence, REMOVE, unmanaged, superseded fields, retention and reset, determinism
---------------------------------------------------------------------------
do
  local REMOVE = LY.REMOVE
  local layers = {
    { name = "base", units = { u1 = "b1", u2 = "b2", u3 = "b3", blob = "B", ["blob.f"] = "bf", gone = "g" } },
    { name = "variant", units = { u1 = "v1", u3 = REMOVE, only = REMOVE, blob = "V" } },
    { name = "preset", units = { u2 = "p2", gone = REMOVE, ["blob.g"] = "pg" } },
    { name = "choices", units = { u1 = "c1" } },
  }
  local parents = { ["blob.f"] = "blob", ["blob.g"] = "blob" }
  local r = LY.Compose(layers, parents)
  Check(r.units.u1 == "c1" and r.layer.u1 == "choices", "the highest layer wins")
  Check(r.units.u2 == "p2", "a preset beats the variant and the base")
  Check(r.units.u3 == "b3" and r.layer.u3 == "base", "REMOVE inherits the layer below")
  Check(r.units.only == nil and r.unmanaged[1] == "only", "REMOVE with nothing below: unmanaged, never written")
  Check(r.units.gone == "g", "REMOVE in a higher layer falls through to the base")
  Check(r.units["blob.f"] == nil and r.superseded[1] == "blob.f", "a field inside a blob a higher layer replaces is dropped")
  Check(r.units["blob.g"] == "pg", "a field from a layer at or above the blob's is kept")
  local kept = LY.Compose(layers, parents, { u1 = true, u2 = true }, { u2 = true })
  Check(kept.units.u1 == nil and kept.retained[1] == "u1", "a retained unit keeps the recipient's value (not written)")
  Check(kept.units.u2 == "p2", "a reset unit takes the package's value again")
  -- the same layers built in another order give the same result
  local again = {}
  for i, l in ipairs(layers) do
    local u = {}
    local keys = {}
    for k in pairs(l.units) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return x > y end)
    for _, k in ipairs(keys) do u[k] = l.units[k] end
    again[i] = { name = l.name, units = u }
  end
  Check(LY.Canon(LY.Compose(again, parents)) == LY.Canon(r), "deterministic: the same output whatever order the input was built in")
  Check(r.list[1].unit < r.list[#r.list].unit, "the output list is sorted by unit")
end

---------------------------------------------------------------------------
-- 4. Package checks: refusals, unsupported versions and fields
---------------------------------------------------------------------------
local function Pkg(edit)
  local p = Copy(LY.TEST_PACKAGE)
  if edit then edit(p) end
  return p
end
local function Refused(p, code, where)
  local ok, problems = LY.Validate(p)
  if ok then return false end
  for _, pr in ipairs(problems) do
    if pr.code == code and (where == nil or tostring(pr.where):find(where, 1, true)) then return true end
  end
  return false
end
do
  Check(LY.Validate(LY.TEST_PACKAGE), "the test package is valid")
  Check(Refused("x", "not-table"), "not a table")
  Check(Refused(Pkg(function(p) p.format = nil end), "format"), "no format")
  Check(Refused(Pkg(function(p) p.format = LY.FORMAT + 1 end), "format-newer"), "a newer format is refused")
  Check(Refused(Pkg(function(p) p.geometry = {} end), "not-yet", "package.geometry"), "geometry needs format 2")
  Check(Refused(Pkg(function(p) p.wizard = true end), "unknown-field", "package.wizard"), "an unknown field")
  Check(Refused(Pkg(function(p) p.canvas = { w = 2560, h = 1440 } end), "not-yet", "package.canvas"), "geometry is refused as not yet supported")
  Check(Refused(Pkg(function(p) p.id = "Not An Id" end), "bad-id"), "a bad id")
  Check(Refused(Pkg(function(p) p.revision = 0 end), "bad-revision"), "a bad revision")
  Check(Refused(Pkg(function(p) p.requires.ellesmereui.min = "new" end), "bad-value"), "a bad version")
  Check(Refused(Pkg(function(p) p.layers.base.details = {} end), "unknown-adapter"), "an adapter this version doesn't have")
  Check(Refused(Pkg(function(p) p.layers.variants = {} end), "no-variants"), "no variants")
  Check(Refused(Pkg(function(p) p.layers.presets = { other = {} } end), "preset-without-variant"), "a preset for no variant")
  Check(Refused(Pkg(function(p) p.targets.twichui = nil end), "no-target", "twichui"), "no target profile name")
  Check(Refused(Pkg(function(p) p.targets.ellesmereui = "a|cffname" end), "bad-target"), "a target name with codes in it")
  Check(Refused(Pkg(function(p) p.layers.base.twichui.cyc = p.layers end), "shape-cycle"), "a cycle anywhere")
  -- TwichUI fragments
  local function TW(groups) return Pkg(function(p) p.layers.variants.test.twichui = { groups = groups } end) end
  Check(Refused(TW({ notifications = { ui = { arrivalHold = "forever" } } }), "bad-value", "twichui:ui.arrivalHold"), "a value TwichConfig refuses")
  Check(Refused(TW({ nothing = { ui = { x = 1 } } }), "unknown-group"), "an unknown group")
  Check(Refused(TW({ notifications = { ui = { madeUp = 1 } } }), "unknown-unit"), "an unknown field")
  Check(Refused(TW({ qol = { modules = { qolSummons = true } } }), "unknown-unit"), "a switch that acts for you is not in any group")
  Check(Refused(TW({ general = { ui = { reduceSettingsMotion = true } } }), "not-managed", "reduceSettingsMotion"), "an account-wide field is not managed")
  Check(Refused(TW({ restockItems = { items = {} } }), "not-yet", "restockItems"), "a list group is not yet supported")
  Check(Refused(Pkg(function(p) p.layers.base.twichui.places = { ["ui.markerBarPosition"] = { x = 0, y = 0 } } end), "not-yet", "places"), "places are not yet supported")
  -- EllesmereUI fragments
  local function EU(edit) return Pkg(function(p) edit(p.layers) end) end
  Check(Refused(EU(function(l) l.variants.test.ellesmereui.fields["minimap.zoom"] = 3 end), "unknown-unit"), "a field outside the allowlist")
  Check(Refused(EU(function(l) l.variants.test.ellesmereui.fields["minimap.coordsPosition"] = "middle" end), "bad-value"), "a value outside the field's set")
  Check(Refused(EU(function(l) l.variants.test.ellesmereui.base = "!EUI_abcdef" end), "base-only-in-base-layer"), "a base in a variant")
  Check(Refused(EU(function(l) l.base.ellesmereui.base = nil end), "no-base"), "no base")
  Check(Refused(EU(function(l) l.variants.test.ellesmereui.uiScale = 0.7 end), "not-yet"), "the UI scale is not yet supported")
  Check(Refused(EU(function(l) l.variants.test.ellesmereui.disableAddons = {} end), "not-yet"), "module enable states are not yet supported")
  Check(Refused(EU(function(l) l.variants.test.ellesmereui.modules = { EllesmereUIMadeUp = "!EUI_abcdef" } end), "unknown-unit"), "an unknown module")
  Check(Refused(Pkg(function(p) p.dev = nil end), "dev-source-not-allowed"), "only a developer package builds on the recipient's own profile")
  -- the allowlist holds nothing that acts, talks to other players, is a record, or is a place
  local fields = TA.Fields()
  local n = 0
  for path in pairs(fields) do
    n = n + 1
    local p, covered = path, false
    while p do if R.TwichConfig.LOCAL[p] then covered = true end p = p:match("^(.*)%.[^.]+$") end
    Check(not covered, path .. " is managed but kept local")
    Check(fields[path].scope == "profile", path .. " is in the profile")
  end
  Check(n > 50, "the managed TwichUI fields come from the schema: " .. n)
  for key, reason in pairs(R.TwichConfig.LOCAL) do
    Check(fields[key] == nil, key .. " (" .. reason .. ") can't be written by a package")
  end
end

---------------------------------------------------------------------------
-- 5. Resolving the test package's variant
---------------------------------------------------------------------------
do
  local ok, res = LY.Resolve(LY.TEST_PACKAGE, "test")
  Check(ok, "resolves")
  local tw, eu = res.adapters.twichui, res.adapters.ellesmereui
  Check(tw.units["twichui:ui.arrivalHold"] == "longer" and tw.layer["twichui:ui.arrivalHold"] == "variant", "the variant's arrivalHold wins")
  Check(tw.units["twichui:ui.trainingStyle"] == "illustrated" and tw.units["twichui:modules.arrivalSubzones"] == false, "base and variant values together")
  Check(eu.units["ellesmereui:addons.EllesmereUIMinimap.minimap.coordsPosition"] == "bottom", "the EllesmereUI field from the variant")
  Check(type(eu.units["ellesmereui:base"]) == "table", "the developer base")
  local ok2, problems = LY.Resolve(LY.TEST_PACKAGE, "nope")
  Check(not ok2 and problems[1].code == "variant-unknown", "an unknown variant")
end

---------------------------------------------------------------------------
-- 6. Plan (nothing changes), then apply: order, snapshot, what is imported, what is written, nothing else touched
---------------------------------------------------------------------------
local before = { tw = Copy(a.TwichUIDB), eui = Copy(a.EllesmereUIDB), restore = Copy(a.TwichUIRestoreDB), share = Copy(a.TwichUIShareDB),
  chron = Copy(a.TwichUIChronicleDB) }
local beforeHold, beforeStyle = R.TwichConfig.Effective(TA.FieldOf("twichui:ui.arrivalHold")), a.TwichUIDB.ui.trainingStyle
local plan = LY.Plan(LY.TEST_PACKAGE, "test")
Check(plan.ok, "the plan can be applied: " .. tostring(plan.blocked[1] and plan.blocked[1].code))
Check(Same(a.TwichUIDB, before.tw) and Same(a.EllesmereUIDB, before.eui) and a.E.called("ImportProfileSilent") == 0, "a plan changes nothing")
Check(plan.order[1] == "ellesmereui" and plan.order[2] == "twichui", "EllesmereUI first, then TwichUI")
Check(plan.reload and plan.parts.ellesmereui.reload and not plan.parts.twichui.reload, "EllesmereUI needs a reload; TwichUI applies at once")
Check(plan.parts.twichui.action == "duplicate" and plan.parts.twichui.profile == "Default", "TwichUI copies the profile in use")
Check(plan.parts.ellesmereui.rows[1].made and plan.parts.ellesmereui.home == "Mine", "EllesmereUI makes a new profile from yours")
Check(Same(LY.Plan(LY.TEST_PACKAGE, "test").key, plan.key), "the same plan again has the same key")

-- explicit approval: no key, or a stale one, changes nothing
Check(select(2, LY.Apply(LY.TEST_PACKAGE, "test", nil)) == "stale", "no approved key: refused")
Check(select(2, LY.Apply(LY.TEST_PACKAGE, "test", "old")) == "stale", "a different key: refused")
a.combat = true
Check(select(2, LY.Apply(LY.TEST_PACKAGE, "test", plan.key)) == "combat", "refused in combat, in the central function")
a.combat = false
Check(Same(a.TwichUIDB, before.tw) and a.E.called("ImportProfileSilent") == 0 and not LY.Journal.Exists(), "refusals change nothing and leave no record")

SEQ = {}
local PF = R.Profiles
local dup = PF.Duplicate
PF.Duplicate = function(...) SEQ[#SEQ + 1] = "twichui.Duplicate" return dup(...) end
local refreshes = 0
local refresh = PF.Refresh
PF.Refresh = function(kind) SEQ[#SEQ + 1] = "twichui.Refresh"; refreshes = refreshes + 1; Check(kind == "layout", "refreshed as a layout") return refresh(kind) end
local ok, result = LY.Apply(LY.TEST_PACKAGE, "test", plan.key)
PF.Duplicate, PF.Refresh = dup, refresh
Check(ok and result.state == "applied", "applied, waiting for the reload: " .. tostring(result and result.state))
local iImport, iDup = 0, 0
for i, s in ipairs(SEQ) do if s == "eui.ImportProfileSilent" then iImport = i elseif s == "twichui.Duplicate" then iDup = i end end
Check(iImport > 0 and iDup > iImport, "EllesmereUI is imported before TwichUI's profile is made")
Check(refreshes == 1, "every TwichUI feature is told once")

local j = LY.Journal.Read()
Check(j and j.state == "applied" and j.reload == true and j.char == "Rich - Forever", "the record: applied, waiting for a reload, this character")
Check(j.steps[1].adapter == "ellesmereui" and j.steps[1].state == "done" and j.steps[2].state == "done", "both steps done")
-- snapshot: the profiles in use before, the names, that the install made them, fingerprints of what it replaced
local st, se = j.snapshot.twichui, j.snapshot.ellesmereui
Check(st.profile == "Default" and st.target == "Layout Test" and st.created == true and st.char == "Rich - Forever", "TwichUI snapshot identities")
Check(st.values["twichui:ui.arrivalHold"] == LY.Fingerprint(beforeHold), "TwichUI snapshot holds the value it replaced")
Check(st.values["twichui:modules.arrivalSubzones"] == LY.Fingerprint(true), "and the switch's value before")
Check(se.active == "Mine" and se.target == "TwichUI Layout Test" and se.created == true and se.version == "9.6.8", "EllesmereUI snapshot identities")
Check(se.values["ellesmereui:addons.EllesmereUIMinimap.minimap.coordsPosition"] == LY.Fingerprint("topLeft"), "EllesmereUI snapshot holds the field's value before")
Check(se.values["ellesmereui:addons.EllesmereUIMinimap.minimap.coordsMode"] == LY.Fingerprint(nil), "a field that was not set is recorded as not set")
Check(LY.Canon(j) and #LY.Canon(j) < 4000, "the record stays small: " .. #LY.Canon(j))
-- what EllesmereUI was asked
local imp
for _, c in ipairs(a.E.calls) do if c[1] == "ImportProfileSilent" then imp = c[2] end end
Check(imp.profileName == "TwichUI Layout Test" and imp.cleanSlate == true and imp.applyUIScale == false and imp.autoAssignSpecs == false
  and imp.disableAddons == nil, "ImportProfileSilent: own profile, clean slate, the UI scale kept, no spec assignment, no enable changes")
local exp
for _, c in ipairs(a.E.calls) do if c[1] == "ExportProfile" then exp = c[2] end end
Check(exp.name == "Mine" and exp.cdm == false and exp.globals == false and exp.overrides == false and exp.skins == false, "the developer base is exported without spells, look, overrides or skins")
local data = a.E.imported.data
Check(data.uiScale == nil and data.assignedSpecs == nil and data.cdmSpells == nil and data.customColors == nil, "nothing account-wide is imported")
Check(data.addons.EllesmereUIDataBars.characters == nil and data.addons.EllesmereUIDataBars.keep == 1, "per-character data is taken out, the rest kept")
Check(data.addons.EllesmereUIActionBars and data.addons.EllesmereUIMinimap.minimap.enabled == true, "every module of the base is in the payload")
Check(data.addons.EllesmereUIMinimap.minimap.coordsPosition == "bottom" and data.addons.EllesmereUIMinimap.minimap.coordsMode == "always", "the fields are patched in")
-- results
Check(a.EllesmereUIDB.activeProfile == "TwichUI Layout Test", "the install's EllesmereUI profile is in use")
Check(PF.Current() == "Layout Test" and a.TwichUIDB.ui.arrivalHold == "longer" and a.TwichUIDB.ui.trainingStyle == "illustrated"
  and a.TwichUIDB.modules.arrivalSubzones == false, "TwichUI's values are written into the install's own profile")
-- nothing else changed
local function Without(t, keys) local o = Copy(t) for _, k in ipairs(keys) do o[k] = nil end return o end
Check(Same(Without(a.TwichUIDB, { "layouts", "profiles", "profileState", "profileKeys", "modules", "ui", "gear" }),
  Without(before.tw, { "layouts", "profiles", "profileState", "profileKeys", "modules", "ui", "gear" })), "no other TwichUI saved data changed")
Check(Same(a.TwichUIRestoreDB, before.restore) and Same(a.TwichUIShareDB, before.share) and Same(a.TwichUIChronicleDB, before.chron), "backups, shares and the Chronicle unchanged")
local stored = a.TwichUIDB.profiles.Default
local function InProfile(t, group)
  local o = {}
  for k, v in pairs(t or {}) do if not (PF.ACCOUNT[group] and PF.ACCOUNT[group][k]) then o[k] = v end end
  return o
end
Check(stored and Same(stored.modules, InProfile(before.tw.modules, "modules")) and Same(stored.ui, InProfile(before.tw.ui, "ui")), "your own profile is kept as it was")
for k, v in pairs(before.tw.ui) do
  if k ~= "arrivalHold" and k ~= "trainingStyle" then Check(Same(a.TwichUIDB.ui[k], v), "ui." .. k .. " unchanged") end
end
for k, v in pairs(before.tw.modules) do
  if k ~= "arrivalSubzones" then Check(a.TwichUIDB.modules[k] == v, "modules." .. k .. " unchanged") end
end
Check(Same(a.EllesmereUIDB.profiles.Mine, before.eui.profiles.Mine) and Same(a.EllesmereUIDB.profiles.Raid, before.eui.profiles.Raid), "your EllesmereUI profiles are not edited")
Check(Same(a.EllesmereUIDB.specProfiles, before.eui.specProfiles) and a.EllesmereUIDB.ppUIScale == 0.8 and Same(a.EllesmereUIDB.clickCast, before.eui.clickCast), "spec assignments, the UI scale and click-cast unchanged")

-- verify now: everything reads back (EllesmereUI's part may still change at the reload; that check is the one recorded)
local report = LY.Verify(false)
Check(report.state == "match" and report.adapters.twichui.checked == 3 and report.adapters.ellesmereui.checked == 2, "everything reads back")
Check(LY.Journal.Read().state == "applied", "a check without recording leaves the state")

-- the dev command shows a plan and refuses to apply without one
a.said = {}
a.SlashCmdList.TWICHUI("layout apply confirm")
Check(Heard(a, "look at what it would do first"), "apply confirm needs a plan shown first")

---------------------------------------------------------------------------
-- 7. The reload: EllesmereUI's picker is kept away while the install waits, and the install is checked after login
---------------------------------------------------------------------------
local saved = Logout(a)
local b = Boot("Rich", saved)
Check(b.E.installer == "TwichUI", "RegisterExternalInstaller at EllesmereUI's load while an install waits")
Check(b.layoutLoads == 1, "the layouts addon is loaded after login to finish the install")
local jb = b.TwichUI.Layouts.Journal.Read()
Check(jb.state == "verified" and jb.verify.state == "match", "checked after the reload: verified (" .. tostring(jb.state) .. ")")
Check(Heard(b, "read back by value as planned"), "and said once (by value; presence-only parts apart, RH-1)")
Check(b.EllesmereUIDB.profiles["TwichUI Layout Test"].addons.EllesmereUIMinimap.minimap.borderSize == 1, "EllesmereUI's defaults went into the blob, and verification still matched")
local saved2 = Logout(b)
local b2 = Boot("Rich", saved2)
Check(b2.layoutLoads == 0 and b2.E.installer == nil, "a verified install loads nothing at the next login")

---------------------------------------------------------------------------
-- 8. Installing again: same plan does nothing; a changed package re-installs, keeping the first snapshot
---------------------------------------------------------------------------
local LYb = Load(b2)
local again = LYb.Plan(LYb.TEST_PACKAGE, "test")
Check(again.mode == "again" and again.parts.ellesmereui.nothing and again.parts.twichui.nothing, "installed already: nothing to do")
Check(select(2, LYb.Apply(LYb.TEST_PACKAGE, "test", again.key)) == "nothing", "and Apply says so")
local firstSnap = Copy(LYb.Journal.Read().snapshot)
local p2 = Copy(LYb.TEST_PACKAGE)
p2.revision = 2
p2.layers.variants.test.ellesmereui.fields["minimap.coordsPosition"] = "top"
p2.layers.variants.test.twichui.groups.notifications.ui.arrivalHold = "brief"
local plan2 = LYb.Plan(p2, "test")
Check(plan2.ok and plan2.parts.twichui.action == "none" and plan2.parts.ellesmereui.rows[1].made == false, "re-install into the install's own profiles")
Check(plan2.parts.ellesmereui.level == "whole", "Phase 7: a package whose EllesmereUI part is one base profile is labelled as replaced whole")
b2.E.calls = {}
local ok2, res2 = LYb.Apply(p2, "test", plan2.key)
Check(ok2 and res2.state == "applied", "re-applied")
local firstChange
for _, call in ipairs(b2.E.calls) do if call[1] == "SwitchProfile" or call[1] == "ImportProfileSilent" or call[1] == "DeleteProfile" then firstChange = firstChange or call end end
Check(firstChange and firstChange[1] == "SwitchProfile" and firstChange[2] == "Mine", "EllesmereUI leaves the install's profile before it is replaced")
Check(b2.EllesmereUIDB.activeProfile == "TwichUI Layout Test" and b2.EllesmereUIDB.profiles["TwichUI Layout Test"].addons.EllesmereUIMinimap.minimap.coordsPosition == "top", "replaced and in use again")
Check(b2.TwichUIDB.ui.arrivalHold == "brief" and b2.TwichUI.Profiles.Current() == "Layout Test", "TwichUI written in place")
Check(Same(LYb.Journal.Read().snapshot, firstSnap), "the first snapshot is kept: Restore goes back to before the first install")
Check(LYb.Journal.Read().revision == 2, "the record names the new revision")
local nProfiles = 0
for _ in pairs(b2.EllesmereUIDB.profiles) do nProfiles = nProfiles + 1 end
-- Phase 7: an update keeps the install's old profile under another name, for "Undo this update" (updates.md)
Check(nProfiles == 4 and b2.EllesmereUIDB.profiles["TwichUI Layout Test (previous)"] ~= nil, "one install profile in EllesmereUI, and its copy from before this update")
Check(LYb.Journal.Read().euiBackup == "TwichUI Layout Test (previous)" and LYb.Journal.Read().update ~= nil, "the record owns that copy and the way back")

---------------------------------------------------------------------------
-- 9. Verification failure: values changed after the install are reported, never repaired
---------------------------------------------------------------------------
b2.TwichUIDB.ui.trainingStyle = "classic"
b2.EllesmereUIDB.profiles["TwichUI Layout Test"].addons.EllesmereUIMinimap.minimap.coordsMode = "hover"
local rep = LYb.Verify(true)
Check(rep.state == "mismatch", "a mismatch")
local units = {}
for _, d in ipairs(LYb.Journal.Read().verify.diffs) do units[d.unit] = d.code end
Check(units["twichui:ui.trainingStyle"] == "differs" and units["ellesmereui:addons.EllesmereUIMinimap.minimap.coordsMode"] == "differs", "both differences named")
Check(b2.TwichUIDB.ui.trainingStyle == "classic", "verification repairs nothing")
Check(LYb.Journal.Read().state == "mismatch", "recorded as not verified")

---------------------------------------------------------------------------
-- 10. Restore: back to before the first install, then checked after the reload
---------------------------------------------------------------------------
local rplan = LYb.PlanRestore()
Check(rplan.ok and rplan.order[1] == "twichui" and rplan.order[2] == "ellesmereui", "restore runs in reverse order")
Check(rplan.parts.twichui.actions[1].kind == "switch" and rplan.parts.twichui.actions[1].to == "Default" and rplan.parts.twichui.actions[2].kind == "delete", "TwichUI: back to Default, the copy removed")
Check(rplan.parts.ellesmereui.actions[1].to == "Mine" and rplan.parts.ellesmereui.actions[2].name == "TwichUI Layout Test" and rplan.reload, "EllesmereUI: back to Mine, the install's profile removed, then a reload")
Check(select(2, LYb.Restore("nope")) == "stale", "restore needs the key of the plan shown")
b2.combat = true
Check(select(2, LYb.Restore(rplan.key)) == "combat", "restore is refused in combat, centrally")
b2.combat = false
local okR, resR = LYb.Restore(rplan.key)
Check(okR and resR.state == "restoring", "restored as far as possible now, EllesmereUI waits for the reload")
Check(b2.TwichUI.Profiles.Current() == "Default" and b2.TwichUIDB.profiles["Layout Test"] == nil, "TwichUI is back on Default and the copy is gone")
Check(b2.EllesmereUIDB.activeProfile == "Mine" and b2.EllesmereUIDB.profiles["TwichUI Layout Test"] == nil, "EllesmereUI is back on Mine and the install's profile is gone")
local saved3 = Logout(b2)
local c3 = Boot("Rich", saved3)
Check(c3.layoutLoads == 1 and not c3.TwichUI.Layouts.Journal.Exists(), "checked after the reload, and the record is removed")
Check(Heard(c3, "restored: everything the layout install changed is back"), "said once")
Check(c3.TwichUI.TwichConfig.Effective(c3.TwichUI.Layouts.TwichUIAdapter.FieldOf("twichui:ui.arrivalHold")) == beforeHold
  and c3.TwichUIDB.ui.trainingStyle == beforeStyle and c3.TwichUIDB.modules.arrivalSubzones == true, "TwichUI's values are as before the install")
Check(Same(Without(c3.TwichUIDB, { "gear" }), Without(before.tw, { "gear" })), "TwichUI's saved data is as it was before the install")
local mineNow = Copy(c3.EllesmereUIDB.profiles.Mine)
local mineThen = Copy(before.eui.profiles.Mine)
Check(Same(mineNow, mineThen) and Same(c3.EllesmereUIDB.profiles.Raid, before.eui.profiles.Raid) and #c3.EllesmereUIDB.profileOrder == 2, "EllesmereUI's profiles are as before")

---------------------------------------------------------------------------
-- 11. Failure paths, with mocked adapters: partial failure, a clean failure, an error, and restore after a partial one
---------------------------------------------------------------------------
local function MockClient()
  local c = Boot("Mock", nil, { catchErrors = true })
  local L = Load(c)
  local log = {}
  local function Mock(id, behaviour)
    local m = { id = id, contract = 1, label = id }
    function m.Normalize(fragment) local u = {} for k, v in pairs(fragment) do u[id .. ":" .. k] = v end return u, {} end
    function m.TargetName(n) return type(n) == "string" end
    function m.Plan(composed) return { adapter = id, rows = {}, changes = #composed.list, reload = behaviour.reload, key = id, target = "T", nothing = behaviour.nothing } end
    function m.Capture() return { target = "T", created = true, values = {} } end
    function m.CleanSnapshot(s) return type(s) == "table" end
    function m.Expect(composed) local o = {} for _, e in ipairs(composed.list) do o[e.unit] = LY.Fingerprint(e.value) end return o end
    function m.Apply()
      log[#log + 1] = id .. ".apply"
      if behaviour.throw then error("mock " .. id .. " exploded") end
      return behaviour.apply or { state = "done", reload = behaviour.reload }
    end
    function m.Verify() return behaviour.verify or { state = "match", diffs = {}, checked = 1 } end
    function m.PlanRestore() return { actions = { { kind = "delete", name = "T" } }, reload = false, key = id } end
    function m.Restore() log[#log + 1] = id .. ".restore" return behaviour.restore or { state = "done" } end
    function m.VerifyRestore() return behaviour.verifyRestore or { state = "match", diffs = {}, checked = 1 } end
    function m.Label(u) return u end
    function m.Show(v) return tostring(v) end
    return m
  end
  local real = { twichui = L.ADAPTERS.twichui, ellesmereui = L.ADAPTERS.ellesmereui }
  local function Use(be, bt)
    L.ADAPTERS.ellesmereui, L.ADAPTERS.twichui = Mock("ellesmereui", be), Mock("twichui", bt)
  end
  local pkg = { format = 1, id = "mock-package", revision = 1, targets = { twichui = "T", ellesmereui = "T" },
    layers = { base = { ellesmereui = { a = 1 }, twichui = { b = 2 } }, variants = { v = {} } } }
  return c, L, Use, pkg, log, real
end

do
  local c, L, Use, pkg, log = MockClient()
  -- TwichUI fails after EllesmereUI succeeded: partial, with a clear step list, and the record kept for Restore
  Use({ reload = true }, { apply = { state = "failed", code = "write", rollback = "clean" } })
  local p = L.Plan(pkg, "v")
  local okP, res = L.Apply(pkg, "v", p.key)
  Check(okP and res.state == "partial", "a later step failing after an earlier one changed something: partial")
  Check(res.steps[1].state == "done" and res.steps[2].state == "failed" and res.steps[2].rollback == "clean", "the steps say done and failed")
  Check(log[1] == "ellesmereui.apply" and log[2] == "twichui.apply", "in order")
  local jr = L.Journal.Read()
  Check(jr.state == "partial" and jr.reload == true, "recorded as partial, with the reload the done part needs")
  -- restore after a partial install
  local rp = L.PlanRestore()
  local okRR, rr = L.Restore(rp.key)
  Check(okRR and rr.state == "restored" and not L.Journal.Exists(), "restored and checked; the record goes")
  Check(log[3] == "twichui.restore" and log[4] == "ellesmereui.restore", "restore in reverse order")

  -- the first step fails cleanly: nothing changed, no record, the second step never runs
  for k in pairs(log) do log[k] = nil end
  Use({ apply = { state = "failed", code = "eui-import", rollback = "clean" } }, {})
  p = L.Plan(pkg, "v")
  okP, res = L.Apply(pkg, "v", p.key)
  Check(okP and res.state == "failed" and res.changed == false, "a clean failure: failed, nothing changed")
  Check(res.steps[2].state == "not-run" and #log == 1, "the later step is not run")
  Check(not L.Journal.Exists(), "and no record is left behind")

  -- an adapter error: caught, reported, and treated as not rolled back
  Use({ throw = true }, {})
  p = L.Plan(pkg, "v")
  okP, res = L.Apply(pkg, "v", p.key)
  Check(okP and res.state == "partial" and res.steps[1].code == "error" and res.steps[1].rollback == "unknown", "an error is a failure that may have changed something")
  Check(#c.errors == 1 and c.errors[1]:find("mock ellesmereui exploded", 1, true), "reported to the error handler")
  L.Journal.Clear()

  -- a previous install stays as it was when a later one fails cleanly
  Use({ reload = false }, {})
  p = L.Plan(pkg, "v")
  okP, res = L.Apply(pkg, "v", p.key)
  Check(okP and res.state == "verified", "an install with no reload is checked at once")
  local prev = Copy(L.Journal.Read())
  Use({ apply = { state = "failed", code = "eui-import", rollback = "clean" } }, {})
  pkg.revision = 2
  p = L.Plan(pkg, "v")
  okP, res = L.Apply(pkg, "v", p.key)
  Check(okP and res.state == "failed" and Same(L.Journal.Read(), prev), "a clean failure leaves the previous record exactly as it was")
  -- verification failure through an adapter
  Use({ verify = { state = "mismatch", diffs = { { unit = "ellesmereui:a", code = "differs" } } } }, {})
  local vr = L.Verify(true)
  Check(vr.state == "mismatch" and L.Journal.Read().state == "mismatch" and L.Journal.Read().verify.diffs[1].unit == "ellesmereui:a", "a failed verification is recorded")
  -- a restore whose step fails: restore-partial, remaining steps not run
  Use({}, { restore = { state = "failed", code = "previous-gone" } })
  local rp2 = L.PlanRestore()
  local okF, rf = L.Restore(rp2.key)
  Check(okF and rf.state == "restore-partial" and rf.steps[2].state == "not-run" and L.Journal.Read().state == "restore-partial", "a failed restore step: partial, the rest not run")
end

---------------------------------------------------------------------------
-- 12. Real adapters, failing: a failed import leaves no half-made profile; refusals before anything changes
---------------------------------------------------------------------------
do
  local f = Boot("Fail", nil, { eui = { throwAfterCreate = true }, catchErrors = true })
  local L = Load(f)
  local pf = L.Plan(L.TEST_PACKAGE, "test")
  local beforeF = Copy(f.EllesmereUIDB)
  local okF, rf = L.Apply(L.TEST_PACKAGE, "test", pf.key)
  Check(okF and rf.state == "failed" and rf.steps[1].rollback == "clean" and rf.steps[2].state == "not-run", "an import that breaks is put back and TwichUI is not touched")
  Check(f.EllesmereUIDB.activeProfile == "Mine" and f.EllesmereUIDB.profiles["TwichUI Layout Test"] == nil and Same(f.EllesmereUIDB.profiles, beforeF.profiles), "no half-made profile, the profile in use put back")
  Check(f.TwichUI.Profiles.Current() == "Default" and f.TwichUIDB.profiles["Layout Test"] == nil and not L.Journal.Exists(), "TwichUI unchanged, no record")
  Check(#f.errors == 1 and f.errors[1]:find("boom inside the import", 1, true), "the import's error goes to the error handler")

  local g = Boot("Gate", nil, { eui = { encodeFails = true } })
  local LG = Load(g)
  local pg = LG.Plan(LG.TEST_PACKAGE, "test")
  local okG, rg = LG.Apply(LG.TEST_PACKAGE, "test", pg.key)
  Check(okG and rg.state == "failed" and rg.steps[1].code == "eui-encode" and g.E.called("ImportProfileSilent") == 0, "a payload that can't be written out is never imported")

  -- a spec with its own profile: stored, not in use; verification says so
  local s = Boot("Spec", nil, { eui = { specLocked = true } })
  local LS = Load(s)
  local ps = LS.Plan(LS.TEST_PACKAGE, "test")
  local okS, rs = LS.Apply(LS.TEST_PACKAGE, "test", ps.key)
  Check(okS and rs.steps[1].code == "spec-locked", "the import is stored, not activated")
  local vs = LS.Verify(false)
  Check(vs.state == "mismatch" and vs.adapters.ellesmereui.diffs[1].code == "not-active", "and the check reports it is not the one in use")

  -- a profile of the package's name that the install didn't make
  local t = Boot("Taken")
  t.EllesmereUIDB.profiles["TwichUI Layout Test"] = { addons = {} }
  local LT = Load(t)
  local pt = LT.Plan(LT.TEST_PACKAGE, "test")
  Check(not pt.ok and pt.parts.ellesmereui.blocked == "target-taken", "an EllesmereUI profile that isn't ours is never replaced")
  t.EllesmereUIDB.profiles["TwichUI Layout Test"] = nil
  t.TwichUI.Profiles.Create("Layout Test")
  t.TwichUI.Profiles.Switch("Default")
  pt = LT.Plan(LT.TEST_PACKAGE, "test")
  Check(not pt.ok and pt.parts.twichui.blocked == "target-taken", "a TwichUI profile that isn't ours is never written")

  -- EllesmereUI's own first-run setup waiting for an answer
  local w = Boot("Fresh")
  w.EllesmereUI._firstInstallPending = true
  local LW = Load(w)
  Check(LW.Plan(LW.TEST_PACKAGE, "test").parts.ellesmereui.blocked == "eui-first-run", "not while EllesmereUI's first-run picker could still replace it")
  -- EllesmereUI missing, too old, or not the Forever build
  local n = Boot("None", nil, { noEUI = true })
  local LN = Load(n)
  Check(LN.Plan(LN.TEST_PACKAGE, "test").parts.ellesmereui.blocked == "eui-missing", "EllesmereUI missing")
  META.EllesmereUI.Version = "9.5.0"
  local o = Boot("Old")
  local LO = Load(o)
  Check(LO.Plan(LO.TEST_PACKAGE, "test").parts.ellesmereui.blocked == "eui-too-old", "EllesmereUI older than the package needs")
  META.EllesmereUI.Version = "9.7.0"
  local u = Boot("Newer")
  local LU = Load(u)
  local pu = LU.Plan(LU.TEST_PACKAGE, "test")
  Check(pu.ok and pu.parts.ellesmereui.untested, "newer than tested: allowed, and said")
  META.EllesmereUI.Version = "9.6.8"
  -- not the Forever build: a real package is refused; the developer test package is allowed, and the plan says so
  u.EllesmereUI.IS_FOREVER = false
  local notDev = Copy(LU.TEST_PACKAGE)
  notDev.dev = nil
  notDev.layers.base.ellesmereui.base = "!EUI_" .. ("x"):rep(10)
  Check(LU.Plan(notDev, "test").parts.ellesmereui.blocked == "eui-not-forever", "a real package needs the Forever build")
  local pr = LU.Plan(LU.TEST_PACKAGE, "test")
  Check(pr.ok and pr.parts.ellesmereui.otherClient, "the developer package runs on another client, marked as such")
  u.said = {}
  u.SlashCmdList.TWICHUI("layout plan")
  Check(Heard(u, "nothing it shows proves how Forever behaves"), "and the plan says it proves nothing about Forever")

  -- a whole round trip on another client (testing on Retail while Forever can't be played): the profile checks read
  -- EllesmereUI's store directly, so nothing is reported as gone or changed when nothing was
  local rt = Boot("Retail", nil, { eui = { retail = true } })
  local LR = Load(rt)
  local prt = LR.Plan(LR.TEST_PACKAGE, "test")
  local okRt, rrt = LR.Apply(LR.TEST_PACKAGE, "test", prt.key)
  Check(okRt and rrt.state == "applied" and rrt.steps[1].state == "done" and rrt.steps[1].code == nil, "applied on another client, nothing else reported changed")
  Check(LR.Journal.Read().snapshot.ellesmereui.otherClient == true, "the snapshot says which kind of client it was made on")
  local savedRt = Logout(rt)
  local rt2 = Boot("Retail", savedRt, { eui = { retail = true } })
  Check(rt2.TwichUI.Layouts.Journal.Read().state == "verified", "verified after the reload on that client")
  local LR2 = rt2.TwichUI.Layouts
  local rpr = LR2.PlanRestore()
  local okRr, rrr = LR2.Restore(rpr.key)
  Check(okRr and rrr.state == "restoring" and rrr.steps[2].code == nil, "restored on that client, nothing else reported changed")
  local rt3 = Boot("Retail", Logout(rt2), { eui = { retail = true } })
  Check(not rt3.TwichUI.Layouts.Journal.Exists() and rt3.EllesmereUIDB.activeProfile == "Mine", "and checked after the reload")
  -- and the check does see another profile being replaced
  local ot = Boot("Other", nil, { eui = { retail = true, touchOther = true } })
  local LOt = Load(ot)
  local pot = LOt.Plan(LOt.TEST_PACKAGE, "test")
  local _, rot = LOt.Apply(LOt.TEST_PACKAGE, "test", pot.key)
  Check(rot.steps[1].code == "others-changed", "another profile replaced during the import is reported")
end

---------------------------------------------------------------------------
-- 13. A real export string as the base (not a developer package): exclusions, module replacement, superseded fields
---------------------------------------------------------------------------
do
  local x = Boot("Strings")
  local L = Load(x)
  local base = Encode({ version = 3, type = "full", data = {
    addons = { EllesmereUIMinimap = { minimap = { coordsMode = "never" } }, EllesmereUIChat = { c = 1 }, NotAModule = { z = 1 },
               EllesmereUIQoL = { chars = { y = 1 }, q = 1 } },
    uiScale = 0.5, applyUIScale = true, customColors = { a = 1 }, cdmSpells = { s = 1 }, specOverrides = { o = 1 },
    blizzSkinGlobals = { b = 1 }, clickCast = { c = 1 }, assignedSpecs = { 62 }, spellAssignments = { s = 1 }, fonts = { f = 1 } } })
  local chat = Encode({ version = 3, type = "full", data = { addons = { EllesmereUIChat = { c = 2 } } } })
  local map = Encode({ version = 3, type = "full", data = { addons = { EllesmereUIMinimap = { minimap = { coordsMode = "hover" } } } } })
  local pkg = { format = 1, id = "string-package", revision = 1, targets = { ellesmereui = "TwichUI Strings" },
    layers = { base = { ellesmereui = { base = base, fields = { ["minimap.coordsMode"] = "always" } } },
               variants = { one = { ellesmereui = { modules = { EllesmereUIChat = chat, EllesmereUIMinimap = map } } } } } }
  local ok3, res3 = L.Resolve(pkg, "one")
  Check(ok3 and res3.adapters.ellesmereui.superseded[1] == "ellesmereui:addons.EllesmereUIMinimap.minimap.coordsMode", "a base field inside a blob the variant replaces is dropped")
  local px = L.Plan(pkg, "one")
  Check(px.ok, "plans: " .. tostring(px.blocked[1] and px.blocked[1].code))
  L.Apply(pkg, "one", px.key)
  local d = x.E.imported.data
  for _, k in ipairs({ "uiScale", "applyUIScale", "customColors", "cdmSpells", "specOverrides", "blizzSkinGlobals", "clickCast", "assignedSpecs", "spellAssignments" }) do
    Check(d[k] == nil, k .. " is never imported")
  end
  Check(d.fonts and d.fonts.f == 1, "the profile's own look rides with it")
  Check(d.addons.NotAModule == nil and d.addons.EllesmereUIQoL.chars == nil and d.addons.EllesmereUIQoL.q == 1, "unknown modules and private data are taken out")
  Check(d.addons.EllesmereUIChat.c == 2 and d.addons.EllesmereUIMinimap.minimap.coordsMode == "hover", "whole module blobs from the variant replace the base's")
  local vx = L.Verify(false)
  -- Phase 7: presence is reported apart from values read back, never as verified by value
  -- RH-1: the allowlisted minimap fields inside the blob are read back by value; the blobs themselves only for presence
  Check(vx.state == "match" and vx.adapters.ellesmereui.checked == 1 and vx.adapters.ellesmereui.presence == 2,
    "module blobs are checked only for presence (their contents change as EllesmereUI loads), and counted as such")
  Check(x.EllesmereUIDB.ppUIScale == 0.8, "the UI scale is the recipient's")
end

---------------------------------------------------------------------------
-- 14. The record: damaged, newer, another character, detach
---------------------------------------------------------------------------
do
  local d = Boot("Damaged", { TwichUIDB = { layouts = { install = { v = 1, state = "applied", package = "x" } } } })
  Check(d.layoutLoads == 1, "a record waiting for a load is looked at")
  local L = d.TwichUI.Layouts
  local pd = L.Plan(L.TEST_PACKAGE, "test")
  Check(not pd.ok and pd.blocked[1].code == "journal-damaged", "a damaged record blocks installing")
  Check(d.TwichUIDB.layouts.install.package == "x", "and is never repaired or removed by itself")
  d.SlashCmdList.TWICHUI("layout detach confirm")
  Check(not L.Journal.Exists() and d.TwichUIDB.layouts == nil, "detach forgets it, nothing else")

  local newer = { v = 9, state = "applied", future = true }
  local nb = Boot("Newer2", { TwichUIDB = { layouts = { install = Copy(newer) } } })
  local LNB = nb.TwichUI.Layouts
  Check(select(2, LNB.Journal.Read()) == "newer" and Same(nb.TwichUIDB.layouts.install, newer), "a newer record is never changed")
  Check(LNB.Plan(LNB.TEST_PACKAGE, "test").blocked[1].code == "journal-newer", "and blocks installing")

  -- the install record belongs to the character that made it (TwichUI profiles are per character)
  local alt = Boot("Alt", saved)
  Check(alt.layoutLoads == 1 and alt.TwichUI.Layouts.Journal.Read().state == "applied", "another character's login leaves the record waiting")
  local LA = alt.TwichUI.Layouts
  Check(LA.Plan(LA.TEST_PACKAGE, "test").blocked[1].code == "journal-other-character", "and can't install over it")
  Check(LA.PlanRestore().blocked[1].code == "journal-other-character", "or restore it")
end

---------------------------------------------------------------------------
-- 15. The developer command, end to end on a fresh client
---------------------------------------------------------------------------
do
  local dv = Boot("Dev")
  dv.SlashCmdList.TWICHUI("layout validate")
  Check(Heard(dv, "the test package is valid"), "validate")
  dv.SlashCmdList.TWICHUI("layout plan")
  Check(Heard(dv, "is copied as \"Layout Test\"") and Heard(dv, "every character on this account"), "the plan says what changes and its scope")
  dv.SlashCmdList.TWICHUI("layout apply confirm")
  Check(Heard(dv, "applied; it isn't finished or checked until you reload"), "apply confirm after a plan; success is not claimed before the check")
  dv.SlashCmdList.TWICHUI("layout status")
  Check(Heard(dv, ": applied."), "status")
  dv.said = {}
  dv.SlashCmdList.TWICHUI("layout restore confirm")
  Check(Heard(dv, "look at what it would do first"), "restore confirm needs the restore shown first")
  dv.SlashCmdList.TWICHUI("layout restore")
  dv.SlashCmdList.TWICHUI("layout restore confirm")
  Check(Heard(dv, "EllesmereUI finishes at a reload"), "restore, waiting for a reload")
  Check(not dv.reloaded, "nothing reloads by itself")
end

---------------------------------------------------------------------------
-- 16. Classic Adventure (Phase 3): the captured package through the Phase 2 pipeline, on a screen that isn't the
--     author's. Plan, apply, the check after the reload and restore, with the screen layer's places in the payload.
---------------------------------------------------------------------------
do
  local SCREEN = { w = 2133.33, h = 1200 }   -- 1920 x 1080 at the author's UI scale: narrower than the 21:9 canvas
  local cl = Boot("Classic")
  local LC = Load(cl)
  local PKG, VAR = LC.CLASSIC_PACKAGE, LC.CLASSIC_VARIANT
  local before = { tw = Copy(cl.TwichUIDB), eui = Copy(cl.EllesmereUIDB), restore = Copy(cl.TwichUIRestoreDB),
    share = Copy(cl.TwichUIShareDB), chron = Copy(cl.TwichUIChronicleDB) }
  local plan = LC.Plan(PKG, VAR, { screen = SCREEN })
  Check(plan.ok, "Classic Adventure plans (" .. tostring(plan.blocked[1] and plan.blocked[1].code) .. ")")
  Check(plan.geometry and plan.geometry.fits and plan.density == "standard", "for this screen, and everything fits")
  local ep, tp = plan.parts.ellesmereui, plan.parts.twichui
  Check(ep.target == "TwichUI Adventure" and tp.target == "TwichUI Adventure", "the package's own profile names")
  local d = ep.payload.data
  local nMod = 0
  for _ in pairs(d.addons) do nMod = nMod + 1 end
  Check(nMod == 18 and d.addons.EllesmereUIGroupFinder == nil, "every captured module, and no other")
  Check(d.fonts and d.darkMode and d.euiAccent and d._migrations and d.unlockLayout, "the look and the layout links travel")
  Check(d.customColors == nil and d.uiScale == nil and d.cdmSpells == nil and d.addons.EllesmereUICooldownManager.spec == nil, "colours, UI scale, spells and per-spec records don't")
  local half = SCREEN.w / 2
  local mm = d.addons.EllesmereUIMinimap.minimap.position
  Check(math.abs(mm.x - (half - 2.5 - 100)) < 0.02 and math.abs(mm.y - 473.33) < 0.02, "the minimap keeps its distance from the right edge")
  local chat = d.addons.EllesmereUIChat.chat.chatPosition
  Check(chat.point == "BOTTOMLEFT" and math.abs(chat.x - 49.08) < 0.02 and math.abs(chat.y - 62.42) < 0.02, "chat stored from the bottom-left corner, as EllesmereUI keeps it")
  local buffs = d.addons.EllesmereUIUnitFrames.playerAuraBars.buffsPos
  local capBuffs = LC.CLASSIC_CAPTURE.ellesmereui.modules.EllesmereUIUnitFrames.playerAuraBars.buffsPos
  Check(math.abs(buffs.x - (capBuffs.x - (2866.67 - SCREEN.w) / 2)) < 0.02, "the buffs move with the minimap")
  local player = d.addons.EllesmereUIUnitFrames.positions.player
  Check(math.abs(player.x + 329.17) < 0.02 and math.abs(player.y + 241.67) < 0.02, "the central block doesn't move at the same height")
  -- the rows the review shows
  local placedRows, objectives = 0, plan.geometry.components.objectives
  for _, row in ipairs(ep.rows) do if row.place then placedRows = placedRows + 1 end end
  Check(placedRows == 37 and objectives.applied == "edit-mode", "37 placed rows; objectives worked out but not applied")

  -- apply, for this screen only
  Check(select(2, LC.Apply(PKG, VAR, plan.key, { screen = { w = 2560, h = 1440 } })) == "stale", "a plan for another screen is stale")
  Check(select(2, LC.Apply(PKG, VAR, plan.key, { screen = SCREEN, density = "larger" })) == "stale", "and so is one for another density")
  local ok, res = LC.Apply(PKG, VAR, plan.key, { screen = SCREEN })
  Check(ok and res.state == "applied", "applied, waiting for the reload (" .. tostring(res and res.state) .. ")")
  local PF = cl.TwichUI.Profiles
  Check(cl.EllesmereUIDB.activeProfile == "TwichUI Adventure" and PF.Current() == "TwichUI Adventure", "both install profiles in use")
  Check(cl.EllesmereUIDB.ppUIScale == 0.8 and Same(cl.EllesmereUIDB.profiles.Mine, before.eui.profiles.Mine), "the UI scale and your EllesmereUI profiles untouched")
  local ui = cl.TwichUIDB.ui
  Check(ui.markerBarPosition and ui.markerBarPosition.x == -2 and ui.markerBarPosition.y == -92, "TwichUI's marker bar where the author put it (the block didn't move)")
  Check(ui.trainingPosition and ui.trainingPosition.x == 0 and ui.trainingPosition.y == -260, "the training card placed from the cards' component")
  Check(type(ui.healerWatch) == "table" and ui.healerWatch.point == "LEFT" and ui.healerWatch.x == 406, "Healer Watch keeps its point and its distance from the left edge")
  local g = LC.CLASSIC_CAPTURE.twichui.groups
  local gid = next(g)
  local slot = next(g[gid])
  local key, value = next(g[gid][slot])
  local f = cl.TwichUI.TwichConfig.Group(gid).index[slot][key]
  Check(LC.Same(cl.TwichUI.TwichConfig.Effective(f), value), "a captured TwichUI look is written (" .. gid .. "." .. key .. ")")
  Check(Same(cl.TwichUIRestoreDB, before.restore) and Same(cl.TwichUIShareDB, before.share) and Same(cl.TwichUIChronicleDB, before.chron), "backups, shares and the Chronicle unchanged")
  Check(Same(cl.TwichUIDB.profiles.Default.ui.markerBarPosition, before.tw.ui.markerBarPosition), "your own TwichUI profile is kept as it was")
  local j = LC.Journal.Read()
  Check(j and j.expect.ellesmereui["ellesmereui:pos.minimap"] and j.expect.twichui["twichui:place.training-card"] == "@0,-260", "the record expects the placed positions")

  -- the reload: checked, and verified
  local saved = Logout(cl)
  local c2 = Boot("Classic", saved)
  local j2 = c2.TwichUI.Layouts.Journal.Read()
  Check(j2 and j2.state == "verified", "checked after the reload: verified (" .. tostring(j2 and j2.state) .. ")")
  -- a place moved after the install is reported, never repaired
  local L2 = c2.TwichUI.Layouts
  c2.EllesmereUIDB.profiles["TwichUI Adventure"].addons.EllesmereUIMinimap.minimap.position.x = 0
  local rep = L2.Verify(false)
  local moved = false
  for _, dd in ipairs(rep.adapters.ellesmereui.diffs) do if dd.unit == "ellesmereui:pos.minimap" and dd.code == "moved" then moved = true end end
  Check(rep.state == "mismatch" and moved, "a moved minimap is reported")
  Check(c2.EllesmereUIDB.profiles["TwichUI Adventure"].addons.EllesmereUIMinimap.minimap.position.x == 0, "and left as the player moved it")

  -- restore: back to before, after the reload
  local rp = L2.PlanRestore()
  Check(rp.ok, "restore plans")
  local okR, resR = L2.Restore(rp.key)
  Check(okR and resR.state == "restoring", "restored as far as it can be before the reload")
  local c3 = Boot("Classic", Logout(c2))
  Check(c3.TwichUIDB.layouts == nil, "after the reload the restore checks out and the record is gone")
  Check(c3.EllesmereUIDB.activeProfile == "Mine" and c3.EllesmereUIDB.profiles["TwichUI Adventure"] == nil, "EllesmereUI back on your profile, the install's gone")
  Check(c3.TwichUI.Profiles.Current() == "Default" and not c3.TwichUI.Profiles.Exists("TwichUI Adventure"), "TwichUI back on your profile, the install's gone")
  Check(c3.TwichUIDB.ui.trainingPosition == before.tw.ui.trainingPosition and Same(c3.TwichUIDB.ui.markerBarPosition, before.tw.ui.markerBarPosition), "your places as they were")

  -- other screens: a narrow one rearranges, a small one is planned honestly
  local cn = Boot("Narrow")
  local LN = Load(cn)
  local np = LN.Plan(PKG, VAR, { screen = { w = 1680, h = 1050 }, density = "larger" })
  Check(np.ok and np.geometry.narrow and np.geometry.fits, "1680 x 1050, larger: narrow arrangement, everything fits")
  local nd = np.parts.ellesmereui.payload.data
  Check(nd.addons.EllesmereUIChat.chat.chatFontSize == 17, "larger density: the chat text size goes up")
  Check(np.parts.ellesmereui.rows and (function()
    for _, row in ipairs(np.parts.ellesmereui.rows) do if row.text and row.unit:find("chatFontSize") then return true end end end)(), "and the review shows it")
  local sp = LN.Plan(PKG, VAR, { screen = { w = 1365.33, h = 768 } })
  Check(sp.ok and not sp.geometry.fits and #sp.geometry.diagnostics > 0, "1365 x 768: the plan says what doesn't fit")
  Check(LN.Plan(PKG, VAR, { screen = SCREEN, density = "huge" }).problems ~= nil, "an unknown density is refused")
  -- the developer command: plan, geometry, apply confirm
  cn.said = {}
  cn.SlashCmdList.TWICHUI("layout geometry classic 1680x1050")
  Check(Heard(cn, "Damage meter:") and Heard(cn, "not applied: EllesmereUI leaves it to Blizzard's Edit Mode"), "geometry lists the components and says what isn't applied")
  cn.said = {}
  cn.SlashCmdList.TWICHUI("layout geometry classic 1365x768")
  Check(Heard(cn, "not everything fits") and Heard(cn, "overlaps"), "and what doesn't fit")
  cn.said = {}
  cn.SlashCmdList.TWICHUI("layout plan classic")
  Check(Heard(cn, "Screen: 1024 × 768 units") and Heard(cn, "more places move with the central"), "the plan shows the screen and summarises the places")
  Check(Heard(cn, "/tui layout plan classic all"), "and how to see every row")
  cn.SlashCmdList.TWICHUI("layout apply confirm")
  Check(Heard(cn, "applied; it isn't finished or checked until you reload"), "apply confirm installs the plan last shown")
  Check(cn.EllesmereUIDB.activeProfile == "TwichUI Adventure", "the Classic package, not the test one")
  cn.said = {}
  cn.SlashCmdList.TWICHUI("layout plan classic wobble")
  Check(Heard(cn, "unknown: 'wobble'"), "an unknown word is refused")
end

---------------------------------------------------------------------------
-- 17. Choices (Phase 4, package format 3): what the wizard may ask, validated; picks resolved into the layers; the
--     accent read back by value; the picks kept in the record
---------------------------------------------------------------------------
do
  local ck = Boot("Choices")
  local LC = Load(ck)
  local BASE = LC.CLASSIC_PACKAGE
  local SCREEN = { w = 2133.33, h = 1200 }
  local function WithChoices(choices, format)
    local p = {}
    for k, v in pairs(BASE) do p[k] = v end   -- the layers are shared, not copied: nothing here changes them
    p.choices, p.format = choices, format or 3
    return p
  end
  local function Problem(choices, code, why, format)
    local ok, problems = LC.Validate(WithChoices(choices, format))
    local found = false
    for _, pr in ipairs(problems or {}) do if pr.code == code then found = true end end
    Check(not ok and found, why .. " (" .. code .. ")")
  end
  local opt = function(id, extra) local o = { id = id, label = "Label " .. id } for k, v in pairs(extra or {}) do o[k] = v end return o end
  local switch = function(group, key, v) return { twichui = { groups = { [group] = { modules = { [key] = v } } } } } end
  local function Accent(id, r) return { ellesmereui = { root = { euiAccent = { useClass = false, custom = { r = r, g = 0.5, b = 0.5 } } } } } end
  local function Merge(o, f) for k, v in pairs(f) do o[k] = v end return o end

  Check(LC.Validate(BASE), "Classic Adventure, with its three choices, is valid (format " .. BASE.format .. ")")
  Check(LC.FORMAT == 5 and select(2, LC.Validate(WithChoices(nil, 6))) ~= nil, "format 6 is newer than this version reads (format 5 adds tooltip choices and more field kinds)")
  Problem(BASE.choices, "not-yet", "a format 2 package may not carry choices", 2)
  Problem({}, "bad-value", "an empty list of choices")
  Problem({ { id = "x", kind = "magic", label = "L", default = "a", options = { opt("a") } } }, "bad-value", "an unknown kind")
  local many = {}
  for i = 1, 7 do many[i] = { id = "c" .. i, kind = "density", label = "L", default = "standard", options = { opt("standard", { density = "standard" }) } } end
  Problem(many, "bad-value", "more choices than the wizard may ask")
  local opts9 = {}
  for i = 1, 9 do opts9[i] = opt("o" .. i, { density = "standard" }) end
  Problem({ { id = "s", kind = "density", label = "L", default = "o1", options = opts9 } }, "bad-value", "more options than a choice may have")
  Problem({ { id = "s", kind = "density", label = "L", default = "a", extra = 1, options = { opt("a", { density = "standard" }) } } }, "unknown-field", "an unknown field of a choice")
  Problem({ { id = "s", kind = "density", label = "L", default = "a", options = { opt("a", { density = "standard", bogus = 1 }) } } }, "unknown-field", "an unknown field of an option")
  Problem({ { id = "s", kind = "density", label = "L", default = "zzz", options = { opt("a", { density = "standard" }) } } }, "bad-value", "a default that is not an option")
  Problem({ { id = "s", kind = "density", label = "L", default = "a", options = { opt("a", { density = "standard" }), opt("a", { density = "larger" }) } } }, "duplicate-id", "a repeated option id")
  Problem({ { id = "s", kind = "density", label = "L", default = "a", options = { opt("a", { density = "standard" }) } },
    { id = "s", kind = "density", label = "L", default = "a", options = { opt("a", { density = "standard" }) } } }, "duplicate-id", "a repeated choice id")
  Problem({ { id = "S", kind = "density", label = "L", default = "a", options = { opt("a", { density = "standard" }) } } }, "bad-id", "an id that isn't a stable id")
  Problem({ { id = "s", kind = "density", label = "L|r", default = "a", options = { opt("a", { density = "standard" }) } } }, "bad-value", "a label with a colour code in it")
  Problem({ { id = "s", kind = "density", label = "L", default = "a", options = { opt("a", { density = "huge" }) } } }, "density-unknown", "a density the geometry doesn't name")
  Problem({ { id = "s", kind = "density", label = "L", default = "a", options = { opt("a", Merge({ density = "standard" }, switch("classBars", "classBars", true))) } } }, "not-allowed", "a density option that also writes a setting")
  Problem({ { id = "p", kind = "preset", label = "L", default = "a", options = { opt("a", { swatch = { 2, 0, 0 } }) } } }, "bad-value", "a swatch outside 0 to 1")
  -- a preset only turns TwichUI switches on
  Problem({ { id = "p", kind = "preset", label = "L", default = "a", options = { opt("a", switch("classBars", "classBars", false)) } } }, "not-allowed", "a preset that turns a switch off")
  Problem({ { id = "p", kind = "preset", label = "L", default = "a", options = { opt("a", { twichui = { groups = { notifications = { ui = { arrivalHold = "long" } } } } }) } } }, "not-allowed", "a preset that sets something that is not a switch")
  Problem({ { id = "p", kind = "preset", label = "L", default = "a", options = { opt("a", Accent("a", 0.5)) } } }, "base-only-in-base-layer", "a preset that names an EllesmereUI look key")
  Problem({ { id = "p", kind = "preset", label = "L", default = "a", options = { opt("a", { ellesmereui = { fields = { ["minimap.coordsMode"] = "always" } } }) } } }, "not-allowed", "a preset that names an EllesmereUI setting")
  Problem({ { id = "p", kind = "preset", label = "L", default = "a", options = { opt("a", switch("classBars", "notASwitch", true)) } } }, "unknown-unit", "a preset naming a setting that doesn't exist")
  -- an enum writes only what it says it does
  Problem({ { id = "e", kind = "enum", label = "L", default = "a", options = { opt("a", Accent("a", 0.5)) } } }, "bad-value", "an enum with no list of what it sets")
  Problem({ { id = "e", kind = "enum", label = "L", default = "a", sets = { "ellesmereui:root.euiAccent" }, options = { opt("a", switch("classBars", "classBars", true)) } } }, "not-in-sets", "an option that writes a unit outside its choice's list")
  Problem({ { id = "e", kind = "enum", label = "L", default = "a", sets = { "ellesmereui:root.euiAccent" },
    options = { opt("a", { ellesmereui = { root = { fonts = { global = "X" } } } }) } } }, "not-managed", "a choice naming a look key other than the accent")
  Problem({ { id = "e", kind = "enum", label = "L", default = "a", sets = { "ellesmereui:root.euiAccent" },
    options = { opt("a", { ellesmereui = { root = { euiAccent = { custom = { r = 2, g = 0, b = 0 }, useClass = false } } } }) } } }, "bad-value", "an accent that is not a colour")
  Problem({ { id = "e", kind = "enum", label = "L", default = "a", sets = { "ellesmereui:root.euiAccent" },
    options = { opt("a", { ellesmereui = { root = { euiAccent = { useClass = "yes" } } } }) } } }, "bad-value", "an accent whose flag isn't a boolean")
  Problem({ { id = "e1", kind = "enum", label = "L", default = "a", sets = { "ellesmereui:root.euiAccent" }, options = { opt("a", Accent("a", 0.4)) } },
    { id = "e2", kind = "enum", label = "L", default = "a", sets = { "ellesmereui:root.euiAccent" }, options = { opt("a", Accent("a", 0.6)) } } }, "choice-conflict", "two choices writing one unit")
  -- the base layer is the only place for the rest of the look
  local frag = { ellesmereui = { root = { fonts = { global = "X" } } } }
  local pv = {}
  for k, v in pairs(BASE) do pv[k] = v end
  pv.layers = { base = BASE.layers.base, variants = { ["classic-adventure"] = { ellesmereui = { modules = BASE.layers.variants["classic-adventure"].ellesmereui.modules, root = { fonts = { global = "X" } } } } } }
  local okv, prv = LC.Validate(pv)
  Check(not okv, "root keys are still only for the base layer")

  -- resolving picks into the layers
  local ok, res = LC.Resolve(BASE, "classic-adventure", { screen = SCREEN })
  Check(ok and res.picks.helpers == "as-is" and res.picks.accent == "gold" and res.picks.size == "standard", "no picks: every choice at its default")
  local tw = res.adapters.twichui
  Check(tw.units["twichui:modules.classBars"] == nil, "and the 'as is' preset writes no switch")
  ok, res = LC.Resolve(BASE, "classic-adventure", { screen = SCREEN, picks = { helpers = "on-screen", accent = "dusk", size = "larger" } })
  Check(ok and res.adapters.twichui.units["twichui:modules.classBars"] == true and res.adapters.twichui.layer["twichui:modules.classBars"] == "preset", "a picked preset is the preset layer")
  Check(res.adapters.twichui.units["twichui:modules.navigation"] == nil, "and only what that option names")
  local acc = res.adapters.ellesmereui.units["ellesmereui:root.euiAccent"]
  Check(acc.custom.r == 0.47 and res.adapters.ellesmereui.layer["ellesmereui:root.euiAccent"] == "choices", "a picked accent wins over the base's, as the choices layer")
  Check(res.geometry.density == "larger" and res.picks.size == "larger", "a picked size is the density")
  ok, res = LC.Resolve(BASE, "classic-adventure", { screen = SCREEN, picks = { accent = "class" } })
  Check(ok and res.adapters.ellesmereui.units["ellesmereui:root.euiAccent"].useClass == true and res.adapters.ellesmereui.units["ellesmereui:root.euiAccent"].custom == nil,
    "the class colour replaces the whole accent, not just part of it")
  local bad, pr = LC.Resolve(BASE, "classic-adventure", { screen = SCREEN, picks = { accent = "neon" } })
  Check(not bad and pr[1].code == "pick-unknown", "an option the package doesn't have is refused")
  bad, pr = LC.Resolve(BASE, "classic-adventure", { screen = SCREEN, picks = { sparkle = "yes" } })
  Check(not bad and pr[1].code == "pick-unknown", "and a choice it doesn't have")
  bad, pr = LC.Resolve(BASE, "classic-adventure", { screen = SCREEN, picks = { size = "larger" }, density = "standard" })
  Check(not bad and pr[1].code == "density-conflict", "a picked size and a different density named as well are refused")
  ok, res = LC.Resolve(BASE, "classic-adventure", { screen = SCREEN, density = "larger" })
  Check(ok and res.geometry.density == "larger" and res.picks.size == "larger", "a density named alone (the developer command) stands in for the size, and the picks say so")
  Check(not LC.Resolve(BASE, "classic-adventure", { screen = SCREEN, density = "huge" }), "an unknown density is still refused")
  -- the plan key follows the picks
  local pa = LC.Plan(BASE, "classic-adventure", { screen = SCREEN })
  local pb = LC.Plan(BASE, "classic-adventure", { screen = SCREEN, picks = { accent = "ember" } })
  local pc = LC.Plan(BASE, "classic-adventure", { screen = SCREEN, picks = { accent = "ember" } })
  Check(pa.ok and pb.ok and pa.key ~= pb.key and pb.key == pc.key, "the plan's key follows the picks, and is the same for the same picks")
  Check(select(2, LC.Apply(BASE, "classic-adventure", pa.key, { screen = SCREEN, picks = { accent = "ember" } })) == "stale", "a plan shown for other picks is stale")

  -- apply, the reload, and the accent read back by value (EllesmereUI's serializer keeps 14 digits)
  local before = Copy(ck.TwichUIDB)
  local okA, resA = LC.Apply(BASE, "classic-adventure", pb.key, { screen = SCREEN, picks = { accent = "ember" } })
  Check(okA and resA.state == "applied", "applied with a pick")
  local j = LC.Journal.Read()
  Check(j.picks.accent == "ember" and j.picks.size == "standard" and j.picks.helpers == "as-is", "the record keeps every choice")
  Check(j.expect.ellesmereui["ellesmereui:root.euiAccent"] == "accent:rgb:0.800,0.450,0.300", "and expects the accent by value")
  local sv = Logout(ck)
  local c2 = Boot("Choices", sv)
  Check(c2.TwichUI.Layouts.Journal.Read().state == "verified", "verified after the reload")
  local prof = c2.EllesmereUIDB.profiles["TwichUI Adventure"]
  prof.euiAccent.custom.r = tonumber(("%.14g"):format(0.8 + 1e-15))   -- what a round trip through tostring does
  prof.euiAccent.custom.g = tonumber(("%.14g"):format(0.45))
  Check(c2.TwichUI.Layouts.Verify(false).state == "match", "a number that went through EllesmereUI's serializer still matches")
  prof.euiAccent = { useClass = true }
  local rep = c2.TwichUI.Layouts.Verify(false)
  local differs = false
  for _, d in ipairs(rep.adapters.ellesmereui.diffs) do if d.unit == "ellesmereui:root.euiAccent" and d.code == "differs" then differs = true end end
  Check(rep.state == "mismatch" and differs, "another accent is reported, by value")
  prof.euiAccent = nil
  rep = c2.TwichUI.Layouts.Verify(false)
  local missing = false
  for _, d in ipairs(rep.adapters.ellesmereui.diffs) do if d.unit == "ellesmereui:root.euiAccent" and d.code == "missing" then missing = true end end
  Check(missing, "and a missing one")
  Check(c2.TwichUI.Layouts.EllesmereAdapter.AccentSig({ useClass = true, custom = { r = 1, g = 1, b = 1 } }) == "class" and
    c2.TwichUI.Layouts.EllesmereAdapter.AccentSig(nil) == "none", "the accent's signature: the class flag wins; nothing is none")

  -- the record's picks are checked like the rest of it
  local jj = c2.TwichUI.Layouts.Journal
  local rec = jj.Read()
  rec.picks = { accent = 5 }
  Check(select(2, jj.Clean(rec)) == "damaged", "a record whose picks aren't ids is damaged")
  rec.picks = { a1 = "b", a2 = "b", a3 = "b", a4 = "b", a5 = "b", a6 = "b", a7 = "b", a8 = "b", a9 = "b" }
  Check(select(2, jj.Clean(rec)) == "damaged", "and so is one with too many")
  rec.picks = nil
  Check(jj.Clean(rec) ~= nil, "a record with no picks (an install from before choices) is fine")
end

---------------------------------------------------------------------------
-- 18. Compact Adventure (Phase 5): the second layout of the same package, through the same pipeline; switching between
--     the two layouts is an install again into the install's own profiles, and Restore still goes back to before the first
---------------------------------------------------------------------------
do
  local SCREEN = { w = 2133.33, h = 1200 }
  local ck = Boot("Compact")
  local LC = Load(ck)
  local PKG, CLASSIC, COMPACT = LC.CLASSIC_PACKAGE, LC.CLASSIC_VARIANT, LC.COMPACT_VARIANT
  local ok, problems, checked = LC.Validate(PKG)
  Check(ok and #checked.variants == 2 and checked.variants[1] == CLASSIC and checked.variants[2] == COMPACT, "the package has both layouts")
  Check(checked.targets.ellesmereui == "TwichUI Adventure" and checked.targets.twichui == "TwichUI Adventure", "one pair of target profiles for the package, named for neither layout")
  Check(LC.ADVENTURE_PACKAGE == PKG and PKG.id == "twichui-adventure", "the same package")
  local before = { tw = Copy(ck.TwichUIDB), eui = Copy(ck.EllesmereUIDB), restore = Copy(ck.TwichUIRestoreDB), share = Copy(ck.TwichUIShareDB), chron = Copy(ck.TwichUIChronicleDB) }

  -- the plans: each its own, from the same package
  local pk = LC.Plan(PKG, COMPACT, { screen = SCREEN })
  local pc = LC.Plan(PKG, CLASSIC, { screen = SCREEN })
  Check(pk.ok and pc.ok and pk.variant == COMPACT and pc.variant == CLASSIC, "both plan (" .. tostring(pk.blocked[1] and pk.blocked[1].code) .. ")")
  Check(pk.key ~= pc.key and pk.parts.ellesmereui.key ~= pc.parts.ellesmereui.key, "each plan has its own key")
  Check(pk.geometry.variant == COMPACT and pk.geometry.fits and pk.geometry.components.central.rect.w == 1091 and pc.geometry.components.central.rect.w == 890,
    "Compact's plan is resolved with Compact's rules (a block 1091 wide, not 890), and fits")
  local dk, dc = pk.parts.ellesmereui.payload.data, pc.parts.ellesmereui.payload.data
  local nMod = 0
  for _ in pairs(dk.addons) do nMod = nMod + 1 end
  Check(nMod == 18 and dk.addons.EllesmereUIGroupFinder == nil, "Compact: every module, shared and its own, and no other")
  Check(dk.fonts and dk.darkMode and dk.euiAccent and dk._migrations and dk.unlockLayout, "the look and the layout links travel")
  Check(Same(dk.fonts, dc.fonts) and Same(dk.euiAccent, dc.euiAccent) and Same(dk.addons.EllesmereUIBags, dc.addons.EllesmereUIBags), "the look and the shared modules are the same in both")
  Check(dk.addons.EllesmereUIActionBars.barPositions.Bar7 ~= nil and dc.addons.EllesmereUIActionBars.barPositions.Bar7 == nil, "Compact's own bars are Compact's alone")
  Check(not Same(dk.unlockLayout, dc.unlockLayout) and dk.unlockLayout.anchors.Bar7 ~= nil and dc.unlockLayout.anchors.Bar7 == nil, "and so are its layout links")
  Check(Same(dk.addons.EllesmereUIChat.chat.chatPosition, dc.addons.EllesmereUIChat.chat.chatPosition), "chat is placed alike in both at this width")
  Check(math.abs(dk.addons.EllesmereUIUnitFrames.player.healthHeight - 63.3333347) < 1e-5 and dc.addons.EllesmereUIUnitFrames.player.healthHeight == 40, "Compact's unit frames are the taller ones")
  local rows, applied = 0, 0
  for _, row in ipairs(pk.parts.ellesmereui.rows) do if row.place then rows = rows + 1 end end
  for _, c in pairs(pk.geometry.components) do if c.applied then applied = applied + 1 end end
  Check(rows == 41 and applied == 1, "41 placed rows in Compact (Classic's 37, bars 6 and 7, the raid and party frames); objectives still not applied")
  Check(Same(pk.parts.twichui.composed.units, pc.parts.twichui.composed.units) or #pk.parts.twichui.rows == #pc.parts.twichui.rows,
    "TwichUI's part is the same size for both")

  -- apply Compact: the key of Classic's plan is stale for it
  Check(select(2, LC.Apply(PKG, COMPACT, pc.key, { screen = SCREEN })) == "stale", "Classic's plan can't install Compact")
  local okA, res = LC.Apply(PKG, COMPACT, pk.key, { screen = SCREEN })
  Check(okA and res.state == "applied", "Compact applied, waiting for the reload")
  local j = LC.Journal.Read()
  Check(j and j.variant == COMPACT and j.package == "twichui-adventure" and j.snapshot.ellesmereui.active == "Mine" and j.snapshot.ellesmereui.created == true,
    "the record names Compact, and what to go back to")
  local firstSnapshot = Copy(j.snapshot)
  Check(ck.EllesmereUIDB.activeProfile == "TwichUI Adventure" and ck.EllesmereUIDB.profiles["TwichUI Adventure"].addons.EllesmereUIActionBars.barPositions.Bar7,
    "EllesmereUI's profile holds Compact's bars")
  Check(Same(ck.EllesmereUIDB.profiles.Mine, before.eui.profiles.Mine) and ck.EllesmereUIDB.ppUIScale == 0.8, "your EllesmereUI profile and the UI scale are untouched")

  -- after the reload: verified
  local saved = Logout(ck)
  local c2 = Boot("Compact", saved)
  local j2 = c2.TwichUI.Layouts.Journal.Read()
  Check(j2 and j2.state == "verified" and j2.variant == COMPACT, "checked after the reload: verified")
  local L2 = c2.TwichUI.Layouts

  -- switching to Classic: an install again, into the same profiles; the first snapshot stays
  local p2 = L2.Plan(PKG, CLASSIC, { screen = SCREEN })
  Check(p2.ok and p2.mode == "again" and p2.journal.variant == COMPACT, "Classic over Compact plans as an install again")
  local ok2, r2 = L2.Apply(PKG, CLASSIC, p2.key, { screen = SCREEN })
  Check(ok2 and r2.state == "applied", "switched, waiting for the reload")
  local j3 = L2.Journal.Read()
  Check(j3.variant == CLASSIC and Same(j3.snapshot, firstSnapshot), "the record names Classic, and the first snapshot is the one it still holds")
  Check(c2.EllesmereUIDB.profiles["TwichUI Adventure"].addons.EllesmereUIActionBars.barPositions.Bar7 == nil, "EllesmereUI's profile now holds Classic's bars, not Compact's")
  local names = c2.EllesmereUIDB.profileOrder
  Check(#names == 4 and c2.EllesmereUIDB.profiles["TwichUI Adventure (previous)"] ~= nil, "switching adds only the copy of the install's profile from before it (" .. #names .. ")")
  local c3 = Boot("Compact", Logout(c2))
  Check(c3.TwichUI.Layouts.Journal.Read().state == "verified" and c3.TwichUI.Layouts.Journal.Read().variant == CLASSIC, "Classic checked after its reload")

  -- and back, a few times
  local cur = c3
  for i = 1, 4 do
    local LX = cur.TwichUI.Layouts
    local want = i % 2 == 1 and COMPACT or CLASSIC
    local px = LX.Plan(PKG, want, { screen = SCREEN })
    local okx, rx = LX.Apply(PKG, want, px.key, { screen = SCREEN })
    Check(px.ok and okx and rx.state == "applied", "switch " .. i .. " to " .. want .. " applies")
    cur = Boot("Compact", Logout(cur))
    local jx = cur.TwichUI.Layouts.Journal.Read()
    Check(jx.state == "verified" and jx.variant == want, "switch " .. i .. ": checked after the reload, as " .. want)
    Check(Same(jx.snapshot, firstSnapshot) and #cur.EllesmereUIDB.profileOrder == 4, "switch " .. i .. ": still the first snapshot; the install's profile and one copy from before the last switch")
  end
  -- applying the layout that is already installed changes nothing it can say about TwichUI; it is an install again all the same
  Check(cur.TwichUI.Layouts.Journal.Read().variant == CLASSIC, "after four switches: Classic")

  -- unrelated data
  Check(Same(cur.TwichUIRestoreDB, before.restore) and Same(cur.TwichUIShareDB, before.share) and Same(cur.TwichUIChronicleDB, before.chron), "backups, shares and the Chronicle unchanged by any of it")
  Check(Same(cur.EllesmereUIDB.profiles.Mine, before.eui.profiles.Mine) and Same(cur.EllesmereUIDB.profiles.Raid, before.eui.profiles.Raid) and cur.EllesmereUIDB.ppUIScale == 0.8,
    "your EllesmereUI profiles and the UI scale as they were")
  Check(Same(cur.TwichUIDB.profiles.Default.ui.markerBarPosition, before.tw.ui.markerBarPosition), "your own TwichUI profile as it was")

  -- restore from either: back to before the first install
  local LR = cur.TwichUI.Layouts
  local rp = LR.PlanRestore()
  Check(rp.ok, "restore plans")
  local okR, resR = LR.Restore(rp.key)
  Check(okR and resR.state == "restoring", "restored as far as it can be before the reload")
  local cr = Boot("Compact", Logout(cur))
  Check(cr.TwichUIDB.layouts == nil and cr.EllesmereUIDB.activeProfile == "Mine" and cr.EllesmereUIDB.profiles["TwichUI Adventure"] == nil, "after the reload: back on your profile, the install's gone")
  Check(cr.EllesmereUIDB.profiles["TwichUI Adventure (previous)"] == nil and #cr.EllesmereUIDB.profileOrder == 2, "and so is the copy an update kept")
  Check(cr.TwichUI.Profiles.Current() == "Default" and not cr.TwichUI.Profiles.Exists("TwichUI Adventure"), "TwichUI back on your profile, the install's gone")

  -- the other screens and the developer command
  local cn = Boot("CompactNarrow")
  local LN = Load(cn)
  local np = LN.Plan(PKG, COMPACT, { screen = { w = 1680, h = 1050 }, density = "larger" })
  Check(np.ok and np.geometry.narrow and np.geometry.fits, "1680 x 1050, larger: Compact's narrow arrangement, everything fits")
  Check(np.parts.ellesmereui.payload.data.addons.EllesmereUIChat.chat.chatFontSize == 17, "larger density: the chat text goes up in Compact too")
  local sp = LN.Plan(PKG, COMPACT, { screen = { w = 1365.33, h = 768 } })
  Check(sp.ok and not sp.geometry.fits and #sp.geometry.diagnostics > 0, "1365 x 768: Compact's plan says what doesn't fit")
  cn.said = {}
  cn.SlashCmdList.TWICHUI("layout geometry compact 1680x1050")
  Check(Heard(cn, "Unit frames and action bars:") and Heard(cn, "Chat:"), "geometry compact lists Compact's components")
  cn.SlashCmdList.TWICHUI("layout plan compact")
  cn.SlashCmdList.TWICHUI("layout apply confirm")
  Check(Heard(cn, "applied; it isn't finished or checked until you reload") and LN.Journal.Read().variant == COMPACT, "apply confirm installs Compact")
  cn.said = {}
  cn.SlashCmdList.TWICHUI("layout validate compact")
  Check(Heard(cn, "the compact package is valid") and Heard(cn, "compact-adventure"), "validate names the layout")
end

if failures > 0 then print(failures .. " FAILED") os.exit(1) end
print("LAYOUTS TESTS PASSED")
