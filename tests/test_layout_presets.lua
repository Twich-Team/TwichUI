dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- Editable TwichUI helper presets (docs/layouts/presets.md): package format 6 (a preset choice's mode "settings", the "keep" option,
-- retired ids), what a preset may and may never name, false/zero/empty/reset/omitted kept apart, precedence over the layout's own
-- layers; the authoring workspace's presets (capture into a preset, create, duplicate, rename, describe, reorder, default, remove,
-- the scope, the values, nothing live changed); the wizard with more than three options, a removed pick, a deliberate switch, kept
-- and owned settings, the review's words, apply, verify, Undo, Restore and Finish; publishing; and the bundling import's round trip
-- (export, import, deterministic files, no-op, the profile recapture keeping the presets, refusals that leave the files alone).
-- TwichUI's code is the real one; EllesmereUI is the stand-in (layouts_mock.lua). Nothing here is the game.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same = LM.Copy, LM.Same
local EUI = { defaults = true }
local function Run(n) for _ = 1, n or 12 do FlushTimers(); Pump() end end
local function Until(done, limit)
  for _ = 1, limit or 600 do
    if done() then return true end
    FlushTimers(); Pump()
  end
  return done()
end
local function Has(problems, code, where)
  for _, p in ipairs(problems or {}) do
    if p.code == code and (where == nil or tostring(p.where):find(where, 1, true)) then return true end
  end
  return false
end

local CLASSIC = "classic-adventure"
local SCREEN = { w = 2133.33, h = 1200 }
local NAV, CB, MB, FD = "twichui:modules.navigation", "twichui:modules.classBars", "twichui:modules.markersBar", "twichui:modules.foodDrink"

local function Client(name, sv)
  local c = LM.Boot(name, sv, { eui = EUI })
  CLIENTS[name] = c
  assert(c.C_AddOns.LoadAddOn("TwichUI_LayoutWizard"))
  return c, c.TwichUI, c.TwichUI.Layouts, c.TwichUI.LayoutWizard
end

local c0, R0, L0 = Client("Rules Reader")
local TA, TC = L0.TwichUIAdapter, R0.TwichConfig
local BUNDLED = L0.ADVENTURE_PACKAGE
local function F(unit) return TA.FieldOf(unit) end
-- a field of each kind, read from the schema (so the test follows TwichUI's real settings)
local INT, ENUM, NAME, COLOR
for _, g in ipairs(TC.Groups()) do
  if not g.custom then
    for _, f in ipairs(g.fields) do
      local unit = "twichui:" .. table.concat(f.at, ".") .. "." .. f.key
      if TA.FieldOf(unit) then
        if f.kind == "int" and not INT and f.min <= 0 and f.max > 0 then INT = { unit = unit, f = f } end
        if f.kind == "enum" and not ENUM then ENUM = { unit = unit, f = f } end
        if f.kind == "name" and not NAME then NAME = { unit = unit, f = f } end
        if f.kind == "color" and not COLOR then COLOR = { unit = unit, f = f } end
      end
    end
  end
end
assert(INT and ENUM and NAME and COLOR, "fields of each kind")

-- a package with an editable preset selector (format 6) in place of the bundled helpers
local function Settings(options, extra)
  local pkg = Copy(BUNDLED)
  pkg.format = 6
  local ch = { id = "helpers", kind = "preset", mode = "settings", label = "TwichUI helpers", hint = "Test presets.", default = options[1].id, options = options }
  for k, v in pairs(extra or {}) do ch[k] = v end
  pkg.choices[1] = ch
  return pkg
end
local function Groups(units)
  local groups = {}
  for unit, v in pairs(units) do
    local f = F(unit)
    groups[f.group] = groups[f.group] or {}
    groups[f.group][f.slot] = groups[f.group][f.slot] or {}
    groups[f.group][f.slot][f.key] = v
  end
  return groups
end

---------------------------------------------------------------------------
-- 1. Package format 6: what an editable preset may name, and what it never can
---------------------------------------------------------------------------
do
  Check(L0.FORMAT == 6, "1. this TwichUI reads package format 6")
  local ok = L0.Validate(BUNDLED)
  Check(ok and BUNDLED.format == 5 and BUNDLED.choices[1].mode == nil, "    the bundled package is unchanged: format 5, its presets switch-on-only")
  local units = { [NAV] = false, [CB] = true, [INT.unit] = 0, [ENUM.unit] = ENUM.f.default }
  local pkg = Settings({
    { id = "keep-all", label = "Leave them as they are", keep = true },
    { id = "kit", label = "Kit", twichui = { groups = Groups(units), reset = { MB } } },
  })
  local okS, problems, checked = L0.Validate(pkg)
  Check(okS, "    an editable preset with false, 0, a word and a reset validates" .. (okS and "" or (": " .. tostring(problems[1].code) .. " " .. tostring(problems[1].where))))
  local u = checked and checked.choices.by.helpers.options.kit.frags.twichui.units
  Check(u and u[NAV] == false and u[INT.unit] == 0 and u[MB] == L0.DEFAULT and u[FD] == nil, "    false and 0 stay values, the reset is a reset, a setting it doesn't name is not managed")
  Check(checked and checked.choices.by.helpers.options["keep-all"].keep == true and checked.choices.by.helpers.mode == "settings", "    the keep option and the mode are read")
  local okR, resolved = L0.Resolve(pkg, CLASSIC, { screen = SCREEN, picks = { helpers = "kit" } })
  local cu = okR and resolved.adapters.twichui.units
  Check(cu and cu[NAV] == false and cu[CB] == true and cu[MB] == L0.DEFAULT and resolved.adapters.twichui.layer[NAV] == "preset", "    picked, its values are in the composed layout, as the preset layer")
  okR, resolved = L0.Resolve(pkg, CLASSIC, { screen = SCREEN, picks = { helpers = "keep-all" } })
  Check(okR and resolved.adapters.twichui.units[NAV] == nil and resolved.adapters.twichui.units[CB] == nil, "    leave them as they are: nothing of the presets' is named")
  -- an empty string is a value TwichUI's name settings never have (TwichConfig's own rule), so a preset can't carry one
  local bad = Settings({ { id = "kit", label = "Kit", twichui = { groups = Groups({ [NAME.unit] = "" }) } } })
  Check(not L0.Validate(bad), "    an empty name, which no TwichUI name setting can have, is refused by the setting's own rule")

  -- precedence: over the layout's own looks; the keep option leaves the layout's value
  local baseUnit
  for g, slots in pairs(BUNDLED.layers.base.twichui.groups) do
    for sl, vals in pairs(slots) do for k, v in pairs(vals) do
      local f = TC.Group(g).index[sl][k]
      if f.kind == "bool" and not baseUnit then baseUnit = { unit = "twichui:" .. table.concat(f.at, ".") .. "." .. f.key, v = v } end
    end end
  end
  local prec = Settings({ { id = "keep-all", label = "Leave", keep = true }, { id = "flip", label = "Flip", twichui = { groups = Groups({ [baseUnit.unit] = not baseUnit.v }) } } })
  local okP, rP = L0.Resolve(prec, CLASSIC, { screen = SCREEN, picks = { helpers = "flip" } })
  Check(okP and rP.adapters.twichui.units[baseUnit.unit] == (not baseUnit.v) and rP.adapters.twichui.layer[baseUnit.unit] == "preset", "    a preset's value wins over the layout's own looks for the same setting")
  okP, rP = L0.Resolve(prec, CLASSIC, { screen = SCREEN, picks = { helpers = "keep-all" } })
  Check(okP and rP.adapters.twichui.units[baseUnit.unit] == baseUnit.v and rP.adapters.twichui.layer[baseUnit.unit] == "base", "    with Leave them as they are, the layout's own value applies (documented)")

  local function Refused(mutate, code, msg)
    local p = Settings({ { id = "keep-all", label = "Leave them as they are", keep = true },
      { id = "kit", label = "Kit", twichui = { groups = Groups({ [CB] = true }) } } })
    mutate(p)
    local okX, px = L0.Validate(p)
    Check(not okX and (code == nil or Has(px, code)), msg .. " (" .. tostring(px and px[1] and px[1].code) .. ")")
  end
  Refused(function(p) p.format = 5 end, "not-yet", "    format 5 can't hold an editable preset: refused as not-yet")
  Refused(function(p) p.choices[1].options[1].twichui = { groups = Groups({ [CB] = true }) } end, "keep-names-settings", "    a keep option that names settings")
  Refused(function(p) p.choices[1].options[2] = { id = "kit", label = "Kit", keep = true } end, "keep-repeated", "    two keep options")
  Refused(function(p) p.choices[1].options[2].twichui = {} end, "preset-empty", "    an editable preset that names nothing (only keep may)")
  Refused(function(p) p.choices[1].options[2].twichui.places = { ["marker-bar"] = { x = 1, y = 2 } } end, "not-allowed", "    a place: positions are the layout's, never a preset's")
  Refused(function(p) p.choices[1].options[2].ellesmereui = { root = { euiAccent = { useClass = true } } } end, nil, "    another addon's setting")
  Refused(function(p) p.choices[1].options[2].twichui.groups = { mage = { modules = { mageSell = true } } } end, "unknown-unit", "    something that acts for you (mage selling) is not a setting a preset can name")
  Refused(function(p) p.choices[1].options[2].twichui.groups.markerOrder = { x = { y = 1 } } end, "not-yet", "    a list group (replaced whole)")
  Refused(function(p) p.choices[1].options[2].twichui.groups.general = { ui = { reduceSettingsMotion = true } } end, "not-managed", "    an account-wide setting")
  Refused(function(p) p.choices[1].retired = { "kit" } end, "retired-id", "    an option that reuses a retired id")
  Refused(function(p) p.choices[1].mode = "everything" end, "bad-value", "    an unknown mode")
  Refused(function(p) p.choices[2].mode = "settings" end, "unknown-field", "    a mode on an enum choice")
  Refused(function(p) p.choices[2].options[1].keep = true end, "unknown-field", "    keep on an enum option")
  Refused(function(p) p.choices[2].sets[#p.choices[2].sets + 1] = CB p.choices[2].options[1].twichui = { groups = Groups({ [CB] = true }) } end,
    "choice-conflict", "    two choices that write the same setting")
  Refused(function(p) p.choices[2].options[1].twichui = { reset = { CB } } p.choices[2].sets[#p.choices[2].sets + 1] = CB end, "reset-not-here", "    a reset in an enum choice")
  -- an older, switch-on-only selector is read as before: never as an editable one, so it still can't turn anything off
  local legacy = Copy(BUNDLED)
  legacy.choices[1].options[2].twichui.groups.classBars.modules.classBars = false
  local okL, pl = L0.Validate(legacy)
  Check(not okL and Has(pl, "not-allowed"), "    a switch-on-only preset still can't turn a feature off (not reread as editable)")
  -- bounds: one option manages at most MAX_UNITS settings
  local many, n = {}, 0
  for path, f in pairs(TA.Fields()) do
    if n <= L0.MAX_UNITS then many["twichui:" .. path] = f.default n = n + 1 end
  end
  local big = Settings({ { id = "kit", label = "Kit", twichui = { groups = Groups(many) } } })
  local okB, pb = L0.Validate(big)
  Check(not okB and Has(pb, "too-many-units"), "    an option past " .. L0.MAX_UNITS .. " settings is refused")
  Check(L0.MAX_EXPECT >= 3 * L0.MAX_UNITS, "    an install record can hold the base, a layout and a full preset")
  -- a preset that only resets settings (no values) keeps its resets (a fragment with only a reset list was once read as empty)
  local only = Settings({ { id = "kit", label = "Kit", twichui = { reset = { CB, NAV } } } })
  local okO, pO, cO = L0.Validate(only)
  local ou = okO and cO.choices.by.helpers.options.kit.frags.twichui.units
  Check(ou and ou[CB] == L0.DEFAULT and ou[NAV] == L0.DEFAULT, "    a fragment holding only a reset list keeps its resets" .. (okO and "" or (": " .. tostring(pO[1].code))))
end

---------------------------------------------------------------------------
-- 2. The authoring workspace's presets: capture into a preset, keeping its scope; effective values, false and defaults included
---------------------------------------------------------------------------
local function Live(c) return { tw = Copy(c.TwichUIDB), eui = Copy(c.EllesmereUIDB) } end
local function Unchanged(c, before)
  local tw = Copy(c.TwichUIDB)
  tw.layouts = nil; local b = Copy(before.tw); b.layouts = nil
  return Same(tw, b) and Same(c.EllesmereUIDB, before.eui)
end
local AUTHORED   -- the draft package made here, for the wizard and the bundling sections
local PUBLISHED  -- { c, entry }
do
  local c, R, LY, WZ = Client("Au Thor")
  local A, AP = WZ.Author, WZ.AuthorPresets
  -- the author's profile: class bars switched off on purpose, navigation never touched (its default), the marker bar on
  c.TwichUIDB.modules.classBars = false
  c.TwichUIDB.modules.navigation = nil
  c.TwichUIDB.modules.markersBar = true
  -- and one setting no preset manages yet, changed from TwichUI's default (an ENUM word other than the default)
  local other
  for _, w in ipairs(LY.SortedKeys(ENUM.f.values)) do if w ~= ENUM.f.default then other = w break end end
  do
    local t = c.TwichUIDB
    for _, k in ipairs(ENUM.f.at) do t[k] = t[k] or {} t = t[k] end
    t[ENUM.f.key] = other
  end
  local before = Live(c)
  local published0 = LY.Store.Count("published")
  assert(A.Begin())
  local P = AP.State()
  Check(P and not P.none and P.id == "helpers" and P.mode == nil and #P.options == 3, "2. the bundled helpers are read: three options, switch-on-only")
  Check(AP.IsKeep(AP.Find("as-is")) and not AP.IsKeep(AP.Find("on-screen")), "    the option that names nothing is the structural \"leave them as they are\"")
  Check(AP.Source() == R.Profiles.Current() and AP.SourceInUse(), "    the source is the profile in use, by its exact name")
  local ok, why = AP.BeginCapture("as-is")
  Check(not ok and why == "keep", "    capturing into \"leave them as they are\" is refused (duplicate or create instead)")

  ok = AP.BeginCapture("on-screen")
  local e = AP.Pending()
  Check(ok and e and e.ops[CB] and e.ops[CB].v == false, "    capture into On-screen helpers: class bars captured as off (false is kept, not omitted)")
  Check(e.ops[MB].v == true and e.ops[FD] ~= nil and e.ops[FD].v == F(FD).default, "    the marker bar on; food and drink at its effective (default) value, stored or not")
  local n = 0 for _ in pairs(e.ops) do n = n + 1 end
  Check(n == 3 and e.ops[NAV] == nil, "    the scope stays the preset's own three switches: navigation is not added by itself")
  local d = AP.Diff()
  local moved = 1 + (F(FD).default == true and 0 or 1)   -- class bars on -> off; food and drink to its default unless that is on
  Check(d.changed == moved and d.added == 0 and d.removed == 0 and d.same == 3 - moved, "    the diff against the draft: what moved from \"on\" is changed, the rest the same")
  Check(AP.Unsaved() and Unchanged(c, before), "    unsaved, and nothing in the profiles or EllesmereUI changed")
  Check(AP.SetView("available"), "    the Not managed view")
  local rows = AP.Rows()
  local navRow
  for _, r in ipairs(rows) do if r.unit == NAV then navRow = r end end
  Check(#rows > 100 and navRow and navRow.op == nil and navRow.captured == F(NAV).default, "    lists what it doesn't manage, with the source's value (navigation at its default)")
  -- the settings the author changed from TwichUI's default come first there
  Check(rows[1].customised == true and rows[1].unit == ENUM.unit, "    settings the profile changed from TwichUI's default come first")
  -- include navigation: it takes the source profile's (default) value, so the preset can say "off" if that's the default
  Check(AP.SetIncluded(NAV, true) and e.ops[NAV].v == F(NAV).default, "    including navigation takes the profile's effective value")
  -- search and categories
  AP.SetView("managed")
  AP.SetQuery("marker")
  rows = AP.Rows()
  Check(#rows == 1 and rows[1].unit == MB, "    search narrows the list (\"marker\": the marker bar)")
  AP.SetQuery("")
  AP.SetGroup("navigation")
  rows = AP.Rows()
  Check(#rows == 1 and rows[1].unit == NAV, "    a category narrows it to that feature's settings")
  AP.SetGroup(nil)
  -- adjusting values: a switch cycles, a number is checked by its own rule, a reset and back
  Check(AP.SetValue(NAV, AP.NextValue(NAV)) and e.ops[NAV].v == not F(NAV).default, "    a switch's value flips on the preset only")
  Check(AP.SetIncluded(INT.unit, true) and AP.SetValue(INT.unit, 0) and e.ops[INT.unit].v == 0, "    a number can be 0")
  Check(not AP.SetValue(INT.unit, INT.f.max + 1), "    a number past its range is refused")
  Check(AP.SetReset(INT.unit, true) and e.ops[INT.unit].reset and AP.SetReset(INT.unit, false) and e.ops[INT.unit].v ~= nil, "    reset to TwichUI's default, and back to a value")
  AP.SetReset(FD, true)
  Check(Unchanged(c, before), "    still nothing live changed")
  -- the settings a preset never manages, with their reasons
  local ex = AP.Excluded()
  local titles = {}
  for _, x in ipairs(ex) do titles[x.code] = x end
  Check(titles.acts and titles.network and titles.place and titles.list and titles.account and titles.positions and titles.acts.n > 0,
    "    Never in a preset: acts for you, other players, places, lists, account-wide, positions, each explained")
  for _, en in ipairs(AP.Eligible().list) do
    if TC.LOCAL[table.concat(en.f.at, ".") .. "." .. en.f.key] or en.f.scope ~= "profile" then Check(false, "    an excluded setting is eligible: " .. en.unit) end
  end
  -- save
  ok = AP.Save()
  Check(ok and not AP.Pending() and P.mode == "settings" and P.converted and AP.IsKeep(AP.Find("as-is")) and AP.Find("as-is").keep == true,
    "    Save to draft: the selector becomes editable; the empty option is now the keep option")
  Check(P.hint == AP.SETTINGS_HINT, "    its description no longer says it only turns things on")
  local draft = A.Draft()
  local ch = draft.choices[1]
  Check(draft.format == 6 and ch.mode == "settings" and ch.options[1].keep == true and ch.options[1].twichui == nil, "    the draft package: format 6, keep option first")
  local on = ch.options[2]
  Check(on.id == "on-screen" and on.twichui.groups.classBars.modules.classBars == false and on.twichui.groups.navigation.modules.navigation == not F(NAV).default,
    "    On-screen helpers keeps its id and carries class bars off, navigation as set")
  Check(on.twichui.reset and on.twichui.reset[1] == FD, "    and food and drink as a reset")
  Check(Same(BUNDLED.choices[1], L0.ADVENTURE_PACKAGE.choices[1]) and LY.ADVENTURE_PACKAGE.choices[1].mode == nil, "    the starting package itself is untouched")
  -- the keep option stays, and can't be removed; capturing into it stays refused
  Check(not AP.Remove("as-is") and not AP.BeginCapture("as-is"), "    the keep option can't be removed or captured into")

  -- create from current settings: a new id, the stated scope (each feature's switch)
  ok = AP.BeginCreate()
  e = AP.Pending()
  local switches = 0
  for _, en in ipairs(AP.Eligible().list) do if en.switch then switches = switches + 1 end end
  n = 0 for _ in pairs(e.ops) do n = n + 1 end
  Check(ok and e.isNew and LY.IsId(e.id) and n == switches and e.ops[CB].v == false, "    Create: a new id, managing every feature switch, with the profile's values")
  Check(AP.SetEditName("Questing kit") and e.label == "Questing kit", "    named")
  ok = AP.Save()
  local kit = AP.Find(e.id)
  Check(ok and kit and kit.label == "Questing kit" and #P.options == 4, "    saved: a fourth option")
  local kitId = kit.id
  Check(not AP.Find("questing-kit") or kitId == "questing-kit", "    its id comes from its name")
  -- rename keeps the id; a taken name is refused
  Check(AP.Rename(kitId, "Adventuring kit") and AP.Find(kitId).label == "Adventuring kit", "    renaming keeps the id")
  Check(not AP.Rename(kitId, "On-screen helpers"), "    another option's name is refused")
  Check(AP.Describe(kitId, "Everything for questing.") and AP.Find(kitId).hint == "Everything for questing." and not AP.Describe(kitId, ("x"):rep(201)), "    described; a long description refused")
  -- duplicate: a new id; reorder; default
  local okD, dupId = AP.Duplicate(kitId)
  Check(okD and dupId ~= kitId and AP.Find(dupId).label == "Copy of Adventuring kit" and #P.options == 5, "    Duplicate: a fifth option with its own id")
  Check(Same(AP.UnitsOf(AP.Find(dupId).ops), AP.UnitsOf(AP.Find(kitId).ops)), "    with the same settings")
  local _, at = AP.Find(dupId)
  Check(AP.Move(dupId, -1) and select(2, AP.Find(dupId)) == at - 1 and not AP.Move(P.options[1].id, -1), "    moved up; the first can't move further")
  Check(AP.SetDefault("on-screen") and P.default == "on-screen", "    a new default")
  -- remove: the default needs a replacement; another option is retired, its id never given out again
  local okR, whyR = AP.Remove("on-screen")
  Check(not okR and whyR == "needs-default", "    removing the default needs another default first")
  Check(AP.Remove("finding-my-way") and not AP.Find("finding-my-way") and P.retired[#P.retired] == "finding-my-way", "    removing another: gone from the draft, its id retired")
  Check(AP.NewId("Finding my way") ~= "finding-my-way" and AP.NewId("Leave them as they are") ~= "as-is", "    a new option never takes a retired or existing id")
  Check(Unchanged(c, before) and LY.Store.Count("published") == published0, "    the whole session changed no profile, no EllesmereUI data and published nothing")
  -- discard: a pending edit that isn't saved changes nothing in the draft
  local snapshot = Copy(AP.UnitsOf(AP.Find(kitId).ops))
  AP.BeginEdit(kitId)
  AP.IncludeShown(false)
  Check(AP.Unsaved() and A.Dirty(), "    leaving everything out is unsaved work; closing would lose it")
  AP.Discard()
  Check(Same(AP.UnitsOf(AP.Find(kitId).ops), snapshot), "    Discard: the draft's preset is as it was")
  -- too many: all or nothing
  AP.BeginEdit(kitId)
  AP.SetView("available")
  local okM, whyM = AP.IncludeShown(true)
  Check(not okM and whyM == "limit", "    including more than " .. L0.MAX_UNITS .. " settings is refused as a whole")
  AP.Discard()
  -- the check and publishing
  A.SetRelease("notes", "Presets made in game.")
  local rep = A.Check()
  Check(rep.ok, "    the draft passes the check a recipient makes" .. (rep.ok and "" or (": " .. tostring(rep.blockers[1]))))
  local done, entry
  A.Publish(function(okp, en) done, entry = okp, en end)
  Until(function() return done ~= nil end)
  Check(done and entry and entry.revision == BUNDLED.revision + 1, "    published as the next revision")
  Check(not A.Dirty(), "    published: closing loses nothing now")
  local first = entry.blob
  -- a later edit makes a new revision; the published one is unchanged
  AP.Rename(kitId, "Kit for later")
  Check(A.Dirty(), "    a change after publishing is work to keep again")
  Check(LY.Store.List("published")[1].blob == first, "    the published package is unchanged by later edits")
  AUTHORED = A.Draft()
  PUBLISHED = { c = c, entry = LY.Store.List("published")[1], kitId = kitId, dupId = dupId }
  Check(Unchanged(c, before), "    and still no profile changed")
  -- the source can be another stored profile, read without switching to it
  c.TwichUIDB.profiles = c.TwichUIDB.profiles or {}
  c.TwichUIDB.profiles.Other = { modules = { classBars = true, navigation = true } }
  local cur = R.Profiles.Current()
  Check(AP.SetSource("Other") and not AP.SourceInUse(), "    another profile can be the source")
  AP.BeginCapture("on-screen")
  e = AP.Pending()
  Check(e.ops[CB].v == true and e.ops[NAV].v == true and R.Profiles.Current() == cur, "    read from it, without switching to it")
  AP.Discard()
  Check(not AP.SetSource("Nobody"), "    a profile that isn't there can't be the source")
  A.End()
end

---------------------------------------------------------------------------
-- 3. The wizard with the authored presets: more than three options, what each does, the review, apply, verify
---------------------------------------------------------------------------
assert(AUTHORED and AUTHORED.format == 6, "the authored draft from section 2")
local REV = BUNDLED.revision + 1
-- The authored package as the one TwichUI ships (as the bundling import would make it), at a revision
local function Pkg(edit, rev)
  local p = Copy(AUTHORED)
  p.dev = true
  p.revision = rev or REV
  if edit then edit(p) end
  return p
end
local function Use(c, pkg)
  local LY = c.TwichUI.Layouts
  LY.ADVENTURE_PACKAGE, LY.CLASSIC_PACKAGE = pkg, pkg
  return LY
end
local function Boot(name, sv, pkg)
  local c, R, LY, WZ = Client(name, sv)
  Use(c, pkg)
  return c, R, LY, WZ
end
local function Reboot(c, name, pkg)
  local sv = LM.Logout(c)
  return Boot(name, sv, pkg)
end
local function ToReview(M)
  M.Go(1)
  for _ = 1, 4 do M.Next() end
  return M.Step() == M.REVIEW
end
local function Lines(r) return r.twichui and table.concat(r.twichui.lines, "\n") or "" end
local KIT, DUP = PUBLISHED.kitId, PUBLISHED.dupId
local PRESET1 = Pkg()
local onOps = PRESET1.choices[1].options[2]
assert(onOps.id == "on-screen")

local rc, rR, rLY, rWZ = Boot("Re Cipient", nil, PRESET1)
local M = rWZ.Model
do
  c0 = nil
  rc.TwichUIDB.modules.classBars = true   -- the recipient uses the class bars: the preset turns them off
  assert(M.Begin())
  local ch = M.Choice("helpers")
  Check(ch and #ch.options == 4 and ch.mode == "settings", "3. the wizard reads the authored options: four, editable presets")
  local sm = M.PresetSummary("helpers", "on-screen")
  local offCB = false
  for _, l in ipairs(sm.summary.off) do if l == "Class resource bars" then offCB = true end end
  Check(offCB and sm.summary.reset >= 1 and not sm.keep, "    On-screen helpers turns the class bars off and resets a setting")
  Check(M.PresetSummary("helpers", "as-is").keep, "    Leave them as they are changes nothing")
  -- the Helpers step draws every option as a card (the page scrolls; no fixed row of three)
  rc.SlashCmdList.TWICHUI("layout")
  local win = rc.TwichUILayoutWizard
  M.Go(1); M.Next(); M.Next()
  rWZ.Window.Refresh()
  Check(M.Step() == M.HELPERS and LM.Says(win, "Adventuring kit") and LM.Says(win, "Copy of Adventuring kit") and LM.Says(win, "On-screen helpers")
    and LM.Says(win, "Leave them as they are"), "    the Helpers step shows all four options")
  local pcard = M.PresetCard("helpers", "on-screen")
  local detail = table.concat(pcard.details, "\n")
  Check(detail:find("Turns off: Class resource bars", 1, true) and not pcard.keep and LM.Says(win, "View included settings"), "    and what each does, read from the package, behind View included settings")
  M.SetPick("helpers", "on-screen")
  Check(ToReview(M), "    on to the review")
  local r = M.Review()
  local text = Lines(r)
  Check(text:find("TwichUI helpers: \"On-screen helpers\".", 1, true) and text:find("Turned off: Class resource bars", 1, true),
    "    the review names the preset and what it turns off")
  Check(text:find("back to TwichUI's default", 1, true) and text:find("Left alone:", 1, true), "    and what it resets and leaves alone")
  local plan = M.Plan()
  local ok, res = M.Apply(plan.key)
  Check(ok and res.state == "applied", "    applied")
  Check(rc.TwichUIDB.modules.classBars == false and rc.TwichUIDB.modules.foodDrink == nil, "    class bars off (false written), food and drink reset (stored value cleared)")
  Check(rc.TwichUIDB.modules.markersBar == true, "    the marker bar on")
  M.End()
  rWZ.Window.Close()
end
rc, rR, rLY, rWZ = Reboot(rc, "Re Cipient", PRESET1)
M = rWZ.Model
do
  local rep = rLY.Verify(true)
  Check(rep and rep.state == "match" and rLY.Journal.Read().state == "verified", "    after the reload: checked by value, verified (" .. tostring(rep and rep.state) .. ")")
  Check(rLY.Journal.ReadBaseline() ~= nil and rLY.Journal.ReadManaged().picks.helpers == "on-screen", "    the baseline and management record name the preset")
end

---------------------------------------------------------------------------
-- 4. Updates: switching preset on purpose, kept and owned settings, Undo, Restore; an update to the same preset; a removed one
---------------------------------------------------------------------------
do
  -- the recipient turns the marker bar off themselves; the kit (which also manages it) is picked on purpose
  rc.TwichUIDB.modules.markersBar = false
  assert(M.Begin())
  Check(M.Pick("helpers") == "on-screen", "4. the wizard remembers the preset installed")
  M.SetPick("helpers", KIT)
  ToReview(M)
  local plan = M.Plan()
  local mb
  for _, row in ipairs(plan.update.rows) do if row.unit == MB then mb = row end end
  local kitMB = PRESET1.choices[1].options[4].twichui.groups.markerBar.modules.markersBar
  Check(mb and (mb.decision == "apply" or (mb.decision == "none" and kitMB == false)), "    a setting the recipient changed takes the chosen preset's value (the switch does what it says)")
  local text = Lines(M.Review())
  Check(text:find("You chose it instead of \"On-screen helpers\"", 1, true), "    the review says it is a different preset than the one installed")
  -- a setting the recipient made theirs stays theirs, and the review says the preset isn't fully in effect
  M.Choose(NAV, "own")
  local r = M.Review()
  Check(r.presetPartial and Lines(r):find("won't be fully in effect", 1, true), "    one made theirs (owned): kept, and the review says the preset won't be fully in effect")
  M.Choose(NAV, nil)
  -- keep mine for one setting: also said
  M.Choose(MB, "mine")
  r = M.Review()
  Check(r.presetPartial and Lines(r):find("as you have it (kept or yours)", 1, true), "    keeping theirs for one: said the same way")
  M.Choose(MB, nil)
  plan = M.Plan()
  local before = Copy(rc.TwichUIDB.modules)
  local ok, res = M.Apply(plan.key)
  -- only TwichUI changes (EllesmereUI matches), so nothing waits for a reload: it is checked at once
  Check(ok and (res.state == "applied" or res.state == "verified"), "    the switch applied (" .. tostring(type(res) == "table" and res.state) .. ")")
  Check(rc.TwichUIDB.modules.markersBar == kitMB and rc.TwichUIDB.modules.classBars == PRESET1.choices[1].options[4].twichui.groups.classBars.modules.classBars,
    "    the kit's values are in effect")
  M.End()
  rc, rR, rLY, rWZ = Reboot(rc, "Re Cipient", PRESET1)
  M = rWZ.Model
  local rep = rLY.Verify(true)
  Check(rep and rep.state == "match", "    verified after the reload")
  Check(rLY.Journal.ReadManaged().picks.helpers == KIT, "    the management record has the new preset")
  -- Undo this update: back to how things were before the switch
  local up = rLY.PlanUndo()
  Check(up.ok ~= false and up.key, "    Undo this update is offered")
  local okU, resU = rLY.Undo(up.key)
  Check(okU and resU and (resU.state == "undone" or resU.state == "undoing"), "    undone (" .. tostring(resU and resU.state) .. ")")
  if resU and resU.state == "undoing" then
    rc, rR, rLY, rWZ = Reboot(rc, "Re Cipient", PRESET1)
    resU = { verify = rLY.VerifyUndo(true) }
  end
  Check(rc.TwichUIDB.modules.markersBar == before.markersBar and rLY.Journal.ReadManaged().picks.helpers == "on-screen",
    "    the marker bar as before the switch, On-screen helpers recorded again")
  -- Restore: back to before the first install (EllesmereUI's part waits for a reload)
  local rp = rLY.PlanRestore()
  local okR, resR = rLY.Restore(rp.key)
  Check(okR and resR and (resR.state == "restoring" or resR.state == "restored"), "    Restore (" .. tostring(resR and resR.state) .. ")")
  if resR and resR.state == "restoring" then
    rc, rR, rLY, rWZ = Reboot(rc, "Re Cipient", PRESET1)
    -- the check after the login (the engine's Continue, which the boot runs) has finished it: the record is gone
    Check(not rLY.Journal.Read() and LM.Heard(rc, "estor"), "    checked after the reload, and the player told")
  end
  Check(rc.TwichUIDB.modules.classBars == true and rR.Profiles.Current() ~= "TwichUI Adventure" and not rLY.Journal.Read(),
    "    the recipient's own profile is back, class bars on as they had them, and the record is gone")
end

-- an update to the same preset: the package changes a value the recipient changed too: theirs is kept (keep my customizations)
do
  local c, R, LY, WZ = Boot("Up Dater", nil, PRESET1)
  local M2 = WZ.Model
  assert(M2.Begin())
  M2.SetPick("helpers", "on-screen")
  ToReview(M2)
  assert(M2.Apply(M2.Plan().key))
  M2.End()
  local intVal = onOps.twichui.groups[F(INT.unit).group][F(INT.unit).slot][F(INT.unit).key]
  c, R, LY, WZ = Reboot(c, "Up Dater", PRESET1)
  assert(LY.Journal.Read().state == "verified", "checked at the login after the reload")
  -- the player changes the number; the next revision of the package changes it as well, differently
  local mine, theirs
  for v = INT.f.min, INT.f.max do
    if v ~= intVal and not mine then mine = v elseif v ~= intVal and v ~= mine and not theirs then theirs = v end
  end
  local t = c.TwichUIDB
  for _, k in ipairs(INT.f.at) do t[k] = t[k] or {} t = t[k] end
  t[INT.f.key] = mine
  local PRESET2 = Pkg(function(p)
    local f = F(INT.unit)
    p.choices[1].options[2].twichui.groups[f.group][f.slot][f.key] = theirs
  end, REV + 1)
  Use(c, PRESET2)
  M2 = WZ.Model
  assert(M2.Begin())
  ToReview(M2)
  local plan = M2.Plan()
  local row
  for _, r in ipairs(plan.update.rows) do if r.unit == INT.unit then row = r end end
  Check(row and row.case == "conflict" and row.decision == "keep", "    the same preset, updated: a setting both changed keeps the player's (" .. tostring(row and row.case) .. ")")
  Check(Lines(M2.Review()):find("The same preset as installed", 1, true), "    and the review says it is the same preset, following the update's rules")
  -- Finish (Keep this setup) ends the journal and keeps managing
  M2.End()
  local okF = LY.Finish()
  Check(okF and not LY.Journal.Read() and LY.Journal.ReadManaged() ~= nil, "    Keep this setup: the journal ends, management goes on")
end

-- a preset the player installed that the next revision removed: said, and a choice asked for (never another applied in its place)
do
  local c, R, LY, WZ = Boot("Gone Option", nil, PRESET1)
  local M3 = WZ.Model
  assert(M3.Begin())
  M3.SetPick("helpers", DUP)
  ToReview(M3)
  assert(M3.Apply(M3.Plan().key))
  M3.End()
  local PRESET3 = Pkg(function(p)
    local opts = p.choices[1].options
    for i = #opts, 1, -1 do if opts[i].id == DUP then table.remove(opts, i) end end
    p.choices[1].retired = p.choices[1].retired or {}
    table.insert(p.choices[1].retired, DUP)
  end, REV + 1)
  c, R, LY, WZ = Reboot(c, "Gone Option", PRESET3)
  assert(LY.Validate(PRESET3))
  M3 = WZ.Model
  assert(M3.Begin())
  Check(M3.Missing("helpers") == DUP, "    the removed preset is noticed (" .. tostring(M3.Missing("helpers")) .. ")")
  M3.Go(1); M3.Next(); M3.Next()
  Check(M3.Step() == M3.HELPERS and not M3.CanContinue(), "    the Helpers step waits for a choice")
  local can, code = M3.CanApply()
  Check(not can and code == "choose-preset", "    and Apply is refused until then")
  c.SlashCmdList.TWICHUI("layout")
  WZ.Window.Refresh()
  Check(LM.Says(c.TwichUILayoutWizard, "is no longer offered by this package"), "    the page says the option is gone, by its id")
  M3.SetPick("helpers", "on-screen")
  Check(M3.Missing("helpers") == nil and M3.CanContinue(), "    once the player picks, it goes on")
  WZ.Window.Close()
  -- "leave them as they are" writes none of the presets' settings
  M3.End()
  assert(M3.Begin())
  M3.SetPick("helpers", "as-is")
  ToReview(M3)
  local plan = M3.Plan()
  local named = 0
  for _, row in ipairs(plan.parts.twichui.rows) do if row.layer == "preset" then named = named + 1 end end
  Check(named == 0 and Lines(M3.Review()):find("It changes none of the", 1, true), "    Leave them as they are: no preset setting in the plan, and the review says so")
end

---------------------------------------------------------------------------
-- 5. Bundling what was approved: export, import, round trip, no-op, determinism, the recapture keeping the presets, refusals
---------------------------------------------------------------------------
dofile(REPO .. "tools/layout_data.lua")
dofile(REPO .. "tools/published_entry.lua")
local function Sh(cmd)
  local p = io.popen(cmd .. " 2>&1; echo \"__rc=$?\"")
  local out = p:read("*a")
  p:close()
  return tonumber(out:match("__rc=(%d+)%s*$")), out
end
local function Read(path) local f = io.open(path, "rb") if not f then return nil end local s = f:read("*a") f:close() return s end
local function Write(path, s) local f = assert(io.open(path, "wb")) f:write(s) f:close() end
local TMP = select(2, Sh("mktemp -d")):match("^(%S+)")
local ABS = select(2, Sh("cd " .. REPO .. " && pwd")):match("^(%S+)")
assert(TMP and ABS)
local FILES = { "TwichUI_Layouts/ChoicesData.lua", "TwichUI_Layouts/ClassicData.lua", "TwichUI_Layouts/CompactData.lua", "TwichUI_Layouts/Classic.lua",
  "docs/layouts/import-published.md", "docs/layouts/capture-classic-adventure.md", "docs/layouts/capture-compact-adventure.md" }
local function Repo(name)
  local W = TMP .. "/" .. name
  local rc0, out0 = Sh(("mkdir -p %q && cd %q && tar --exclude='*.ogg' --exclude='*.tga' --exclude='*.blp' --exclude='*.png' -cf - '!!!TwichUI' TwichUI_Settings TwichUI_Layouts tools tests docs/layouts | (cd %q && tar -xf -)")
    :format(W, ABS, W))
  assert(rc0 == 0, "copied: " .. out0)
  Sh(("rm -f %q"):format(W .. "/docs/layouts/import-published.md"))
  return W
end
local function Files(W) local t = {} for _, f in ipairs(FILES) do t[f] = Read(W .. "/" .. f) or false end return t end
local function SameFiles(a, b) for _, f in ipairs(FILES) do if a[f] ~= b[f] then return false, f end end return true end
local function Import(W, how, extra)
  return Sh(("cd %q && TMPDIR=%q tools/update_bundled_layout.sh --from-published %s --no-tests %s"):format(W, TMP, how, extra or ""))
end
local function SavedWith(dir, entries)
  Sh("mkdir -p " .. dir)
  Write(dir .. "/!!!TwichUI.lua", "TwichUIDB = " .. LD.Emit({ layouts = { published = entries } }) .. "\n")
end
-- the package as the import put it in a repository copy: its choices, read back from the generated file
local function Bundled(W)
  return LD.ReadOwn(W .. "/TwichUI_Layouts/ChoicesData.lua", "ADVENTURE_CHOICES"),
    tonumber((Read(W .. "/TwichUI_Layouts/Classic.lua") or ""):match('id = "twichui%-adventure", revision = (%d+)'))
end

do
  local pc = PUBLISHED.c
  local A = pc.TwichUI.LayoutWizard.Author
  local entry = PUBLISHED.entry
  -- the export text is the stored entry's own bytes, with what identifies it in front
  local text = A.ExportText(entry)
  local parsed = PE.Parse(text)
  Check(text:sub(1, #A.EXPORT_TAG) == A.EXPORT_TAG and parsed and parsed.blob == entry.blob and parsed.hash == entry.hash and parsed.size == entry.size,
    "5. the export text holds exactly the published bytes, with its id, revision, fingerprint and size")
  local wrapped = text:sub(1, 200) .. "\n" .. text:sub(201)
  Check(PE.Parse(wrapped) and PE.Parse(wrapped).blob == entry.blob, "    a line break an editor adds doesn't matter")
  local env = PE.Open(pc, parsed)
  Check(env and env.package.revision == REV and env.package.choices[1].mode == "settings", "    it unpacks and passes the recipient's check")
  -- the export window shows it, read only, and changes nothing
  local before = Copy(pc.TwichUIDB.layouts.published)
  pc.SlashCmdList.TWICHUI("layout author")
  pc.TwichUI.LayoutWizard.AuthorWindow.ShowExport(entry)
  local ex = pc.TwichUILayoutExport
  Check(ex and ex:IsShown() and ex.edit:GetText() == text and LM.Says(ex, "--from-published --text"), "    the Export window shows the text and the command")
  Check(Same(pc.TwichUIDB.layouts.published, before), "    showing it changed nothing that is stored")
  ex:Hide()
  pc.TwichUI.LayoutWizard.AuthorWindow.Close(true)

  -- the import: from a copy of the saved file, into a copy of the repository
  SavedWith(TMP .. "/sv", { entry })
  Write(TMP .. "/export.txt", text .. "\n")
  local W1 = Repo("one")
  local orig = Files(W1)
  local rc1, out1 = Import(W1, "--sv " .. TMP .. "/sv")
  Check(rc1 == 0 and out1:find("Done: imported, checked, not tested", 1, true), "    imported from the saved file (" .. tostring(rc1) .. "): " .. (rc1 == 0 and "" or out1:sub(-600)))
  Check(out1:find("round trip: the bundled package resolves exactly as", 1, true), "    and the round trip checked: the bundled package resolves as the published one")
  local choices, rev = Bundled(W1)
  Check(choices and L0.Canon(choices) == L0.Canon(env.package.choices) and rev == REV,
    "    ChoicesData.lua holds the published choices byte for byte, and Classic.lua its revision")
  local after1 = Files(W1)
  Check(after1["TwichUI_Layouts/ClassicData.lua"] == orig["TwichUI_Layouts/ClassicData.lua"] and after1["TwichUI_Layouts/CompactData.lua"] == orig["TwichUI_Layouts/CompactData.lua"],
    "    the layers were the same, so the two data files are untouched")
  Check(after1["docs/layouts/import-published.md"] and after1["docs/layouts/import-published.md"]:find("Adventuring kit", 1, true)
    and after1["docs/layouts/import-published.md"]:find(env.meta.hash, 1, true), "    the report names the package, its fingerprint and its presets")
  -- again: already bundled, nothing written
  local rc2, out2 = Import(W1, "--sv " .. TMP .. "/sv")
  Check(rc2 == 0 and out2:find("Already bundled", 1, true) and SameFiles(after1, Files(W1)), "    importing it again: already bundled, no file touched")
  -- the same package from the exported text, into another copy: the same files, byte for byte
  local W2 = Repo("two")
  local rc3 = Import(W2, "--text " .. TMP .. "/export.txt")
  local f2 = Files(W2)
  local okText = true
  for _, f in ipairs(FILES) do if f:find("^TwichUI_Layouts/") and f2[f] ~= after1[f] then okText = false end end
  Check(rc3 == 0 and okText and f2["docs/layouts/import-published.md"]:find("exported text", 1, true),
    "    from the exported text: the same package files (the report says where it was read from)")
  local W2b = Repo("two-b")
  local rc3b = Import(W2b, "--sv " .. TMP .. "/sv")
  local okSame, which = SameFiles(after1, Files(W2b))
  Check(rc3b == 0 and okSame, "    the same import into another copy: every file byte for byte the same (deterministic) " .. tostring(which))
  -- the profile recapture keeps the presets it never writes
  local CC = LD.ReadOwn(W1 .. "/TwichUI_Layouts/ClassicData.lua", "CLASSIC_CAPTURE")
  local KC = LD.ReadOwn(W1 .. "/TwichUI_Layouts/CompactData.lua", "COMPACT_CAPTURE")
  local function Prof(own, layout)
    local pr = { addons = {}, unlockLayout = Copy(layout) }
    for k, v in pairs(CC.ellesmereui.root) do pr[k] = Copy(v) end
    for m, b in pairs(CC.ellesmereui.modules) do pr.addons[m] = Copy(b) end
    for m, b in pairs(own or {}) do pr.addons[m] = Copy(b) end
    return pr
  end
  local tw = { profileState = { live = "Default" } }
  for g, slots in pairs(CC.twichui.groups) do
    for sl, vals in pairs(slots) do for k, v in pairs(vals) do
      local f = TC.Group(g).index[sl][k]
      local t = tw
      for _, key in ipairs(f.at) do t[key] = t[key] or {} t = t[key] end
      t[f.key] = Copy(v)
    end end
  end
  for id, v in pairs(CC.twichui.places) do
    local path = TA.PLACES[id].path
    local t = tw
    for i = 1, #path - 1 do t[path[i]] = t[path[i]] or {} t = t[path[i]] end
    if TA.PLACES[id].kind == "point" then t[path[#path]] = t[path[#path]] or {} for k, x in pairs(v) do t[path[#path]][k] = x end
    else t[path[#path]] = Copy(v) end
  end
  local compact = Prof(KC.ellesmereui.modules, KC.ellesmereui.layout or CC.ellesmereui.layout)
  for m in pairs(KC.sameAs.modules) do compact.addons[m] = Copy(CC.ellesmereui.modules[m]) end
  Sh("mkdir -p " .. TMP .. "/prof")
  Write(TMP .. "/prof/EllesmereUI.lua", "EllesmereUIDB = " .. LD.Emit({ profiles = { ["TwichUI - Classic Adventure"] = Prof(nil, CC.ellesmereui.layout),
    ["TwichUI - Minimal Adventure"] = compact }, activeProfile = "TwichUI - Classic Adventure", lastLoginVersion = "9.6.8", ppUIScale = 0.64 }) .. "\n")
  Write(TMP .. "/prof/!!!TwichUI.lua", "TwichUIDB = " .. LD.Emit(tw) .. "\n")
  local rc4, out4 = Sh(("cd %q && TMPDIR=%q tools/update_bundled_layout.sh --sv %q --no-tests --no-bump --returned release"):format(W1, TMP, TMP .. "/prof"))
  local after4 = Files(W1)
  Check(rc4 == 0 and out4:find("Done: generated, checked, not tested", 1, true), "    a profile recapture after the import runs (" .. tostring(rc4) .. ")" .. (rc4 == 0 and "" or out4:sub(-500)))
  Check(after4["TwichUI_Layouts/ChoicesData.lua"] == after1["TwichUI_Layouts/ChoicesData.lua"], "    and leaves ChoicesData.lua, the approved presets, exactly as imported")
  local rc5, out5 = Sh(("cd %q && lua5.1 tools/check_bundled_layout.lua --published --sv %q"):format(W1, TMP .. "/sv/!!!TwichUI.lua"))
  Check(rc5 == 0, "    the recaptured package still holds the published presets (the round trip check passes)" .. (rc5 == 0 and "" or out5:sub(-400)))

  -- refusals leave every file as it was
  local W3 = Repo("three")
  local orig3 = Files(W3)
  Write(TMP .. "/damaged.txt", text:sub(1, #text - 40))
  local rcD, outD = Import(W3, "--text " .. TMP .. "/damaged.txt")
  Check(rcD == 1 and outD:find("Not imported", 1, true) and SameFiles(orig3, Files(W3)), "    damaged text: refused, nothing written")
  Write(TMP .. "/junk.txt", "hello")
  local rcJ = Import(W3, "--text " .. TMP .. "/junk.txt")
  Check(rcJ == 1 and SameFiles(orig3, Files(W3)), "    text that isn't an export: refused, nothing written")
  -- a package whose screen rules differ from Classic.lua's, and one of another id
  local LYp = pc.TwichUI.Layouts
  local function Sealed(mutate)
    local pk = Copy(env.package)
    mutate(pk)
    local e2 = LYp.Pub.Build(pk, { now = 1761600000, client = "forever" })
    assert(e2, "built")
    local got
    LYp.Store.Seal(e2, function(en) got = en end, function(code) got = { failed = code } end)
    assert(Until(function() return got ~= nil end) and not got.failed, "sealed")
    return got
  end
  SavedWith(TMP .. "/svgeo", { Sealed(function(pk) pk.geometry.narrow = 1650 end) })
  local rcG, outG = Import(W3, "--sv " .. TMP .. "/svgeo")
  Check(rcG == 1 and outG:find("geometry", 1, true) and outG:find("Classic.lua", 1, true) and SameFiles(orig3, Files(W3)),
    "    screen rules that differ from Classic.lua's: refused, says where they are written, nothing written")
  SavedWith(TMP .. "/svid", { Sealed(function(pk) pk.id = "someone-else" end) })
  local rcI, outI = Import(W3, "--sv " .. TMP .. "/svid")
  Check(rcI == 1 and outI:find("someone-else", 1, true) and SameFiles(orig3, Files(W3)), "    another package: refused, nothing written")
  -- the same revision as the one bundled, with other contents (after the import above): refused
  SavedWith(TMP .. "/svrev", { Sealed(function(pk) pk.choices[1].options[2].label = "On-screen kit" end) })
  local rcR, outR = Import(W1, "--sv " .. TMP .. "/svrev")
  Check(rcR == 1 and outR:find("higher revision", 1, true) and SameFiles(after4, Files(W1)), "    the bundled revision again, with other contents: refused, nothing written")
  -- two entries and no revision named: listed, refused
  SavedWith(TMP .. "/svtwo", { entry, Sealed(function(pk) pk.revision = REV + 1 end) })
  local rcT, outT = Import(W3, "--sv " .. TMP .. "/svtwo")
  Check(rcT == 1 and outT:find("more than one", 1, true) and SameFiles(orig3, Files(W3)), "    two published packages and none named: refused, they are listed")
  local rcL, outL = Import(W3, "--sv " .. TMP .. "/svtwo", "--list")
  Check(rcL == 0 and outL:find("revision " .. REV, 1, true) and outL:find("revision " .. (REV + 1), 1, true) and SameFiles(orig3, Files(W3)), "    --list lists them and writes nothing")
  -- a round trip that fails after writing puts every file back (Classic.lua here composes the choices in another order)
  local W4 = Repo("four")
  local classic = Read(W4 .. "/TwichUI_Layouts/Classic.lua")
  Write(W4 .. "/TwichUI_Layouts/Classic.lua", (classic:gsub("choices = LY%.ADVENTURE_CHOICES,", "choices = { LY.ADVENTURE_CHOICES[2], LY.ADVENTURE_CHOICES[1], LY.ADVENTURE_CHOICES[3], LY.ADVENTURE_CHOICES[4], LY.ADVENTURE_CHOICES[5] },")))
  local orig4 = Files(W4)
  local rcF, outF = Import(W4, "--sv " .. TMP .. "/sv")
  Check(rcF == 1 and outF:find("doesn't match the published one", 1, true) and SameFiles(orig4, Files(W4)),
    "    a round trip that fails: every file put back, exit 1 (" .. tostring(rcF) .. ")")
end
Sh(("rm -rf %q"):format(TMP))

---------------------------------------------------------------------------
-- 6. The workspace's window: the presets section, the editor through its buttons, nothing lost without asking, nothing rebuilt
---------------------------------------------------------------------------
do
  local c, R, LY, WZ = Client("Win Author")
  local before = Live(c)
  local function Click(win, label)
    local b = LM.Button(win, label)
    assert(b, "a button " .. label)
    b.scripts.OnClick(b)
  end
  c.SlashCmdList.TWICHUI("layout author")
  local win = c.TwichUILayoutAuthor
  local AW, AP, A = WZ.AuthorWindow, WZ.AuthorPresets, WZ.Author
  Check(win and win:IsShown() and LM.Says(win, "4. TwichUI presets") and LM.Says(win, "On-screen helpers") and LM.Says(win, "Helpers and navigation"),
    "6. the presets section lists the options")
  Check(LM.Says(win, "older switch-on-only form"), "    and says the presets are the older kind until a change is saved")
  Check(LM.Says(win, "the profile in use"), "    the source profile by its exact name, marked as the one in use")
  AP.Select("on-screen")
  AW.Refresh()
  Click(win, "Capture current settings into this preset")
  Check(AP.Pending() and LM.Says(win, "Captured into \"On-screen helpers\" (not saved to the draft)"), "    Capture opens the editor, unsaved")
  Click(win, "Not managed")
  AW.Refresh()
  Check(LM.Says(win, "Page 1 of"), "    the Not managed view is paged")
  -- Close asks while there is unsaved work; declining keeps it
  AP.SetIncluded(NAV, true)
  Click(win, "Close")
  Check(c.popup and c.popup.key == "TWICHUI_LAYOUT_PRESETS_CLOSE" and win:IsShown(), "    Close with unsaved work asks first")
  c.Decline()
  Check(win:IsShown() and AP.Pending(), "    declined: still open, the edit kept")
  Click(win, "Save to draft")
  Check(not AP.Pending() and AP.State().changed and LM.Says(win, "Saved to the draft"), "    Save to draft")
  -- Escape keeps the session (and says so); opening again goes on with it
  win:Hide()
  Check(A.Active() and LM.Heard(c, "kept until you reload"), "    Escape: the presets' draft is kept until the reload, and the player told")
  c.SlashCmdList.TWICHUI("layout author")
  Check(win:IsShown() and AP.State() and AP.State().changed, "    reopened: the draft is still there")
  -- the export window for a published package (none yet here) and the editor's buttons don't build anything twice
  local made = c.made()
  for _ = 1, 5 do win:Hide() c.SlashCmdList.TWICHUI("layout author") end
  Check(c.made() == made and AW.builds == 1, "    reopening five times builds nothing new")
  Click(win, "Close")
  Check(c.popup and c.popup.key == "TWICHUI_LAYOUT_PRESETS_CLOSE", "    Close asks again (the draft isn't published)")
  c.Accept()
  Check(not win:IsShown() and not A.Active(), "    accepted: closed and the session dropped")
  Check(Unchanged(c, before), "    and no profile or EllesmereUI data changed")
end

if failures > 0 then print(failures .. " check(s) FAILED") os.exit(1) end
print("OK")
