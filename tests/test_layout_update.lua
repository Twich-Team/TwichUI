dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- Layout updates (Phase 7; docs/layouts/updates.md): the baseline, the three-way comparison, what an update keeps and applies,
-- atomic layout-link groups, opaque EllesmereUI units, switching layouts, ownership, failed, partial and resumed updates,
-- Undo this update, and an end-to-end run (install v1, change things, publish v2, update keeping them, verify, undo, restore).
-- TwichUI's code is the real one; EllesmereUI is the stand-in (layouts_mock.lua) with the real functions' shape, here filling
-- a default into a blob as it loads, as the real one does. Nothing here is the game: docs/layouts/updates.md lists the in-game
-- checks.

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same, Heard = LM.Copy, LM.Same, LM.Heard
local EUI = { defaults = true }

local function Engine(c)
  assert(c.TwichUI.LayoutsLauncher.Load())
  return c.TwichUI.Layouts
end

local function Reload(name, c, opts) return LM.Boot(name, LM.Logout(c), opts or { eui = EUI }) end

-- Rows of an update plan by unit
local function Rows(plan)
  local out = {}
  for _, r in ipairs(plan.update and plan.update.rows or {}) do out[r.unit] = r end
  return out
end

---------------------------------------------------------------------------
-- 1. The three-way comparison, case by case (table-driven): every case, false / 0 / "" / absent kept apart, inherited
--    defaults, reset, removal, ownership, opaque units, positions within a unit, an entity that can't stay deleted
---------------------------------------------------------------------------
local c0 = LM.Boot("Table", nil, { eui = EUI })
local L0 = Engine(c0)
local MG, FP = L0.Merge, L0.Fingerprint
local ABS = MG.ABSENT
local X, Y, Z = FP("x"), FP("y"), FP("z")
do
  local CASES = {
    -- name, entry, case, decision (keep my changes), decision (recommended)
    { "neither changed", { n = X, c = X, b = { p = X } }, "same", "none", "none" },
    { "only the package changed", { n = Y, c = X, b = { p = X } }, "package", "apply", "apply" },
    { "only the recipient changed", { n = X, c = Y, b = { p = X } }, "mine", "keep", "apply" },
    { "both changed, the same way", { n = Y, c = Y, b = { p = X } }, "both-same", "none", "none" },
    { "both changed, differently", { n = Y, c = Z, b = { p = X } }, "conflict", "keep", "apply" },
    { "read back differently from what was applied, and unchanged since", { n = X, c = Y, b = { p = X, l = Y } }, "same", "none", "none" },
    { "false is not 0", { n = FP(false), c = FP(0), b = { p = FP(false) } }, "mine", "keep", "apply" },
    { "0 is not an empty string", { n = FP(""), c = FP(0), b = { p = FP(0) } }, "package", "apply", "apply" },
    { "an empty string is not absent", { n = FP(""), c = ABS, cs = "a", b = { p = FP(""), s = "x" } }, "mine", "keep", "apply" },
    { "absent on every side", { n = ABS, c = ABS, cs = "a", b = { p = ABS, s = "a" } }, "same", "none", "none" },
    { "false to true in the package", { n = FP(true), c = FP(false), b = { p = FP(false) } }, "package", "apply", "apply" },
    { "a false the recipient set over the layout's true", { n = FP(true), c = FP(false), b = { p = FP(true) } }, "mine", "keep", "apply" },
    { "never stored on either side: the addon's own default moved", { n = X, c = Y, cs = "d", b = { p = X, s = "d" } }, "same", "none", "none" },
    { "reset to the addon's default after it was stored", { n = X, c = Y, cs = "d", b = { p = X, s = "x" } }, "mine", "keep", "apply" },
    { "inherited now, explicit before, same effective value", { n = X, c = X, cs = "d", b = { p = X, s = "x" } }, "same", "none", "none" },
    { "the package no longer names it", { n = nil, c = X, b = { p = X } }, "removed", "release", "release" },
    { "the recipient's own", { n = Y, c = Z, b = { o = true } }, "owned", "owned", "owned" },
    { "newly managed", { n = Y, c = X, known = true }, "added", "apply", "apply" },
    { "newly managed, already the same", { n = X, c = X, known = true }, "same", "none", "none" },
    { "no usable baseline, differs", { n = Y, c = X, known = false }, "unknown", "keep", "apply" },
    { "no usable baseline, the same", { n = X, c = X, known = false }, "same", "none", "none" },
    { "opaque: both changed (even to the same text) is a conflict", { n = Y, c = Y, b = { p = X, l = Z }, comparable = false }, "conflict", "keep", "apply" },
    { "opaque: only the package changed", { n = Y, c = Z, b = { p = X, l = Z }, comparable = false }, "package", "apply", "apply" },
    { "opaque: only the recipient changed", { n = X, c = Y, b = { p = X, l = Z }, comparable = false }, "mine", "keep", "apply" },
    { "opaque: unchanged since it was read back", { n = X, c = Z, b = { p = X, l = Z }, comparable = false }, "same", "none", "none" },
    { "a position within a unit is the same place", { n = "@10,10,CENTER", c = "@11,10,CENTER", b = { p = "@10,10,CENTER" } }, "same", "none", "none" },
    { "a position moved by more than a unit", { n = "@10,10,CENTER", c = "@40,10,CENTER", b = { p = "@10,10,CENTER" } }, "mine", "keep", "apply" },
    { "the same numbers from another point are another place", { n = "@10,10,CENTER", c = "@10,10,LEFT", b = { p = "@10,10,CENTER" } }, "mine", "keep", "apply" },
    { "a size is part of the place", { n = "@10,10,200,200,CENTER", c = "@10,10,260,260,CENTER", b = { p = "@10,10,200,200,CENTER" } }, "mine", "keep", "apply" },
    { "a deleted entity that can't stay deleted is put back", { n = X, c = ABS, cs = "a", b = { p = X, l = Z }, comparable = false, keepAbsent = false }, "mine", "apply", "apply" },
  }
  for _, t in ipairs(CASES) do
    local e = Copy(t[2])
    e.unit = "test:u"
    e.comparable = e.comparable ~= false
    if e.known == nil then e.known = e.b ~= nil end
    local case = MG.Classify(e)
    Check(case == t[3], t[1] .. ": case " .. tostring(case) .. ", wanted " .. t[3])
    local d1 = MG.Decide(e, case, "keep")
    local d2 = MG.Decide(e, case, "recommended")
    Check(d1 == t[4], t[1] .. ": keeping my changes decides " .. tostring(d1) .. ", wanted " .. t[4])
    Check(d2 == t[5], t[1] .. ": the recommended configuration decides " .. tostring(d2) .. ", wanted " .. t[5])
  end
  Check(MG.Classify({ unit = "u", n = nil, c = X }) == nil, "a unit nobody manages has no case")

  -- choices: what each case offers, and what each choice decides
  local conflict = { unit = "u", n = Y, c = Z, b = { p = X }, comparable = true, known = true }
  Check(MG.Decide(conflict, "conflict", "keep", "package") == "apply", "a conflict: Use recommended applies the layout's")
  Check(MG.Decide(conflict, "conflict", "keep", "own") == "owned", "Stop managing makes it the recipient's")
  Check(MG.Decide(conflict, "conflict", "recommended", "mine") == "keep", "Keep mine wins over the recommended configuration")
  local grouped = Copy(conflict); grouped.group = "layout"
  Check(MG.Decide(grouped, "conflict", "keep", "own") == "keep", "a unit in an atomic group can't be made the recipient's alone")
  local found = false
  for _, o in ipairs(MG.Offers("conflict", true)) do if o == "own" then found = true end end
  Check(not found, "and isn't offered it")
  Check(MG.Decide({ unit = "u", n = Y, c = Z, b = { o = true }, comparable = true }, "owned", "keep", "manage") == "apply", "Manage again hands an owned unit back")
  Check(MG.Decide({ unit = "u", n = X, c = X, b = { p = X }, comparable = true }, "same", "keep", "own") == "owned", "an unchanged unit can be made the recipient's")
  Check(MG.Decide({ unit = "u", n = Y, c = X, b = { p = X }, comparable = true }, "package", "keep", "mine") == "keep", "a package update can be declined")
  Check(MG.Decide({ unit = "u", n = Y, c = X, b = { p = X }, comparable = true }, "package", "keep", "nonsense") == "apply", "an unknown choice is ignored")
  -- switching layouts: a unit the layout sets for itself goes back to the new layout's value; a shared one keeps the recipient's
  local own = Copy(conflict); own.variantOwned = true
  local d, how = MG.Decide(own, "conflict", "keep", nil, true)
  Check(d == "apply" and how == "switch", "switching: a layout-specific change returns to the new layout's value")
  Check(MG.Decide(own, "conflict", "keep", "mine", true) == "keep", "unless the recipient keeps it")
  Check(MG.Decide(conflict, "conflict", "keep", nil, true) == "keep", "a shared setting the recipient changed is kept across a switch")
  Check(MG.Decide({ unit = "u", n = X, c = Y, b = { p = X }, comparable = true, variantOwned = true }, "mine", "keep", nil, true) == "keep",
    "a layout-specific setting both layouts give the same value keeps the recipient's change")
end

do
  -- groups, a whole-addon decision, tracking, and the screen check
  local function Entries()
    return {
      { unit = "a:layout", n = Y, c = Z, b = { p = Y, l = X }, comparable = false, known = true, group = "layout", canKeep = true },  -- mine
      { unit = "a:pos.one", n = "@50,0,CENTER", c = "@0,0,CENTER", b = { p = "@0,0,CENTER" }, comparable = true, known = true, group = "layout" },  -- package
      { unit = "a:pos.free", n = "@0,0,CENTER", c = "@0,0,CENTER", b = { p = "@0,0,CENTER" }, comparable = true, known = true },
    }
  end
  local r = MG.Run(Entries(), { policy = "keep" })
  Check(r.groups.layout.conflict and r.groups.layout.choice == "mine", "a group the recipient changed in one place and the layout in another: kept as theirs")
  Check(r.by["a:pos.one"].decision == "keep" and r.by["a:pos.one"].how == "group", "the layout's change to a member is not applied alone")
  r = MG.Run(Entries(), { policy = "keep", groups = { layout = "package" } })
  Check(r.by["a:layout"].decision == "apply" and r.by["a:pos.one"].decision == "apply", "or the whole group takes the layout's")
  r = MG.Run(Entries(), { policy = "keep", switching = true })
  Check(r.groups.layout.choice == "package" and r.by["a:layout"].decision == "apply", "switching layouts: the group takes the new layout's")
  r = MG.Run(Entries(), { policy = "recommended" })
  Check(r.by["a:layout"].decision == "apply" and not r.groups.layout.conflict, "the recommended configuration: no group conflict")
  Check(r.by["a:pos.free"].decision == "none", "an unrelated unit is untouched by the group")

  local stuck = { { unit = "a:addons.Bags", n = X, c = Y, b = { p = X, l = Z }, comparable = false, known = true, canKeep = false },
    { unit = "a:pos.x", n = "@1,1,CENTER", c = "@30,1,CENTER", b = { p = "@1,1,CENTER" }, comparable = true, known = true } }
  r = MG.Run(Copy(stuck), {})
  Check(r.whole and r.whole.needed and r.whole.choice == "keep" and r.whole.units[1] == "a:addons.Bags", "an opaque change that can't be carried over asks for the whole addon; kept as it is by default")
  r = MG.Run(Copy(stuck), { whole = "replace" })
  Check(r.by["a:addons.Bags"].decision == "apply" and r.by["a:addons.Bags"].how == "whole" and r.by["a:pos.x"].decision == "keep",
    "replace: the opaque part takes the layout's; a comparable change is still kept")

  local tr = MG.Track(MG.Run({
    { unit = "k", n = Y, c = Z, b = { p = X }, comparable = true, known = true },
    { unit = "o", n = Y, c = Z, b = { o = true }, comparable = true, known = true },
    { unit = "gone", n = nil, c = Z, b = { p = X }, comparable = true, known = true },
    { unit = "a", n = Y, c = X, b = { p = X }, comparable = true, known = true },
  }, {}), { k = Y, a = Y, o = Y })
  Check(tr.k.p == Y and tr.k.k == true and tr.o.o == true and tr.o.p == nil and tr.gone == nil and tr.a.p == Y and tr.a.k == nil,
    "tracked for the baseline: the package's side, kept and owned marks; a released unit is dropped")

  local geo = { screen = { w = 1000, h = 800 }, order = { "box" },
    components = { box = { managed = true, label = "Box", rect = L0.Geometry.Rect(0, 0, 200, 200) } } }
  local w = MG.CheckPlaces(geo, { { unit = "o", label = "Off", x = 900, y = 0 }, { unit = "b", label = "Over", x = 10, y = 10 },
    { unit = "m", label = "Mine", x = 10, y = 10, comp = "box" }, { unit = "f", label = "Fine", x = 300, y = 300 } })
  Check(#w == 2 and w[1].code == "offscreen" and w[2].code == "overlap" and w[2].other == "Box", "the screen check warns about off-screen and overlapping kept places, and nothing else")
end

---------------------------------------------------------------------------
-- Packages for the scenarios: Classic Adventure published (the author's private font folder swapped for TwichUI's copy,
-- as the publish check offers), revision by revision. Publishing is the real Pub.Build and Pub.Check.
---------------------------------------------------------------------------
local PKG, CLASSIC, COMPACT = L0.CLASSIC_PACKAGE, L0.CLASSIC_VARIANT, L0.COMPACT_VARIANT
local TC0 = c0.TwichUI.TwichConfig
local function Field(group, slot, key)
  local f = TC0.Group(group).index[slot][key]
  return "twichui:" .. table.concat(f.at, ".") .. "." .. f.key, f
end
local FONT_U, FONT_F = Field("classBars", "classBars", "font")        -- the class bars' font: the recipient changes it
local NAV_U, NAV_F = Field("navigation", "navigation", "font")         -- the navigation font: the layout changes it (shared)
Check(TC0.ValueOk(FONT_F, "Cinzel") and TC0.ValueOk(FONT_F, "Spectral Medium") and TC0.ValueOk(NAV_F, "Cinzel"), "the fonts used here are valid values")
local MARKER_U, MINIMAP_U, BAGS_U, LAYOUT_U = "twichui:place.marker-bar", "ellesmereui:pos.minimap", "ellesmereui:addons.EllesmereUIBags", "ellesmereui:layout"
local CHATSIZE_U = "ellesmereui:addons.EllesmereUIChat.chat.chatFontSize"
local BAR5_U = "ellesmereui:pos.bar-5"
local TARGET = "TwichUI Adventure"
local BACKUP = "TwichUI Adventure (previous)"

local function Fonts(t)
  for k, v in pairs(t) do
    if type(v) == "table" then Fonts(v)
    elseif type(v) == "string" then local s = L0.Pub.Substitute(v); if s then t[k] = s end end
  end
end
local function Publish(revision, edit)
  local p = Copy(PKG)
  Fonts(p)
  p.revision = revision
  if edit then edit(p) end
  local env, problems = L0.Pub.Build(p, { now = 1000 + revision, notes = "Revision " .. revision })
  assert(env, "published: " .. tostring(problems and problems[1] and (problems[1].code .. " " .. tostring(problems[1].where))))
  local ok, why = L0.Pub.Check(env)
  assert(ok, "and it checks out: " .. tostring(why and why[1] and why[1].code))
  return env.package
end
local CHAT_V1 = PKG.layers.base.ellesmereui.modules.EllesmereUIChat.chat.chatFontSize
local V1 = Publish(1)
local function Revision2(p)
  local tw = p.layers.base.twichui
  tw.groups.navigation.navigation.font = "Cinzel"            -- shared change the recipient didn't touch
  tw.groups.classBars.classBars.font = "Spectral Medium"     -- the recipient changed it too: a conflict
  tw.places["marker-bar"] = { x = -2, y = -120 }             -- the recipient moved it too: a conflict
  local eu = p.layers.base.ellesmereui
  eu.modules.EllesmereUIBags.twichTest = 2                   -- an opaque blob only the layout changed
  eu.modules.EllesmereUIChat.chat.chatFontSize = CHAT_V1 + 2 -- a text size the recipient changed too
  local a = p.layers.variants[CLASSIC].ellesmereui.layout.anchors.Bar5
  a.offsetY = (a.offsetY or 0) + 3                           -- the layout links change (Bar 5 on Bar 4)
end
local V2 = Publish(2, Revision2)
Check(V1.dev == nil and V2.revision == 2 and L0.Validate(V2), "two published revisions of the package")

-- Installs `pkg`/`variant` on client `c` and reloads; returns the client after the check
local function Install(name, c, pkg, variant, opts)
  local L = Engine(c)
  local plan = L.Plan(pkg, variant, opts)
  assert(plan.ok, "plan: " .. tostring(plan.blocked[1] and plan.blocked[1].code or (plan.problems and plan.problems[1] and plan.problems[1].code)))
  local ok, res = L.Apply(pkg, variant, plan.key, opts)
  assert(ok and (res.state == "applied" or res.state == "verified"), "apply: " .. tostring(ok and res.state or res))
  return Reload(name, c), plan, res
end

---------------------------------------------------------------------------
-- 2. End to end: apply v1; change a font, a TwichUI place, the minimap and the chat text size; publish v2 with shared and
--    conflicting changes; update keeping the changes; verify; undo the update; restore
---------------------------------------------------------------------------
do
  local NAME = "Journey"
  local c = LM.Boot(NAME, nil, { eui = EUI })
  local beforeAll = { tw = Copy(c.TwichUIDB), eui = Copy(c.EllesmereUIDB) }
  local L = Engine(c)
  local plan1 = L.Plan(V1, CLASSIC)
  local ok1, res1 = L.Apply(V1, CLASSIC, plan1.key)
  Check(ok1 and res1.state == "applied", "1. v1 applied, waiting for the reload")
  Check(L.Journal.ReadBaseline() == nil and c.TwichUIDB.layouts.baseline == nil, "   no baseline is stored because an install started")
  local j1 = L.Journal.Read()
  Check(j1.track and j1.track.twichui[FONT_U] and j1.track.ellesmereui[MINIMAP_U] and j1.track.ellesmereui[BAGS_U], "   the record says what the baseline will take")

  c = Reload(NAME, c)
  L = Engine(c)
  local j = L.Journal.Read()
  local b1 = L.Journal.ReadBaseline()
  Check(j.state == "verified" and b1 and b1.parts.twichui and b1.parts.ellesmereui, "   checked after the reload; both adapters' baselines committed")
  Check(b1.parts.twichui.revision == 1 and b1.parts.ellesmereui.variant == CLASSIC and b1.parts.ellesmereui.schema:find("ellesmereui:1:9.6.8", 1, true),
    "   the baseline names the revision, layout, merge contract, EllesmereUI version")
  Check(b1.parts.ellesmereui.units[MINIMAP_U].p ~= nil and b1.parts.ellesmereui.units[BAGS_U].l == nil
    and b1.parts.ellesmereui.units["ellesmereui:addons.EllesmereUIMinimap"].l ~= nil,
    "   a blob EllesmereUI filled defaults into reads back differently, and that is remembered")
  Check(b1.parts.twichui.units[FONT_U].p == FP("Alegreya Sans Bold") and b1.parts.twichui.units[FONT_U].s == "x", "   a TwichUI setting: the value and that it is stored")
  local size = #L.Canon(b1)
  Check(size < 64000, "   the baseline stays small (" .. size .. " bytes of canonical text)")

  -- 2. the recipient's own changes
  local TC = c.TwichUI.TwichConfig
  local f = TC.Group("classBars").index.classBars.font
  TC.Container(f, true)[f.key] = "Cinzel"
  c.TwichUIDB.ui.markerBarPosition = { x = 300, y = -92 }
  local live = c.EllesmereUIDB.profiles[TARGET]
  local mm = live.addons.EllesmereUIMinimap.minimap.position
  mm.x = mm.x - 60
  live.addons.EllesmereUIChat.chat.chatFontSize = CHAT_V1 + 5
  local mine = Copy(live)

  -- 3. v2, published. 4. update keeping my changes
  local recommended = L.Plan(V2, CLASSIC, { update = { policy = "recommended" } })
  local plan = L.Plan(V2, CLASSIC)
  Check(plan.ok and plan.mode == "again" and plan.update and plan.update.baseline == "ok" and plan.update.policy == "keep", "4. v2 plans as an update, keeping my changes")
  local rows = Rows(plan)
  Check(rows[FONT_U].case == "conflict" and rows[FONT_U].decision == "keep", "   the font both changed: mine kept")
  Check(rows[NAV_U].case == "package" and rows[NAV_U].decision == "apply", "   the font only the layout changed: applied")
  Check(rows[MARKER_U].case == "conflict" and rows[MARKER_U].decision == "keep", "   the marker bar both moved: mine kept")
  Check(rows[MINIMAP_U].case == "mine" and rows[MINIMAP_U].decision == "keep", "   the minimap I moved: kept")
  Check(rows[CHATSIZE_U].case == "conflict" and rows[CHATSIZE_U].decision == "keep", "   the chat text size both changed: mine kept")
  Check(rows[BAGS_U].case == "package" and rows[BAGS_U].decision == "apply" and not rows[BAGS_U].comparable, "   the Bags module only the layout changed: replaced whole")
  Check(rows[LAYOUT_U].case == "package" and rows[LAYOUT_U].decision == "apply", "   the layout links only the layout changed: applied")
  Check(rows["ellesmereui:addons.EllesmereUIMinimap"].case == "same", "   EllesmereUI's own defaults in a blob are not my change")
  Check(plan.update.counts.conflict == 3 and #plan.update.warnings == 0, "   three conflicts, no screen warnings")
  local d = plan.parts.ellesmereui.payload.data
  Check(d.addons.EllesmereUIBags.twichTest == 2 and d.addons.EllesmereUIChat.chat.chatFontSize == CHAT_V1 + 5, "   the payload: the layout's Bags, my chat text size")
  Check(math.abs(d.addons.EllesmereUIMinimap.minimap.position.x - mm.x) < 0.01, "   my minimap place goes into the payload")
  local rd = recommended.parts.ellesmereui.payload.data
  local shift = d.unlockLayout.anchors.EBS_Minimap.offsetX - rd.unlockLayout.anchors.EBS_Minimap.offsetX
  Check(math.abs(shift + 60) < 0.02, "   and its link to the screen edge is moved to match, so EllesmereUI puts it there (" .. shift .. ")")
  Check(d.unlockLayout.anchors.Bar5.offsetY == rd.unlockLayout.anchors.Bar5.offsetY, "   the layout's new links are in it")
  Check(Rows(recommended)[FONT_U].decision == "apply" and Rows(recommended)[MINIMAP_U].decision == "apply", "   (the recommended configuration would apply everything)")

  local okA, resA = L.Apply(V2, CLASSIC, plan.key)
  Check(okA and resA.state == "applied", "   applied, waiting for the reload")
  Check(c.EllesmereUIDB.profiles[BACKUP] ~= nil and Same(c.EllesmereUIDB.profiles[BACKUP], mine) and c.EllesmereUIDB.activeProfile == TARGET,
    "   the install's profile as it was is kept as " .. BACKUP .. ", untouched")
  Check(TC.Effective(f) == "Cinzel" and TC.Effective(TC.Group("navigation").index.navigation.font) == "Cinzel" and c.TwichUIDB.ui.markerBarPosition.x == 300,
    "   TwichUI: my font and marker bar kept, the layout's navigation font applied")
  local ju = L.Journal.Read()
  Check(ju.update and ju.update.twichui.values[NAV_U] and ju.update.twichui.values[FONT_U] == nil and ju.update.ellesmereui.backup == BACKUP,
    "   the record keeps the way back: the value the update replaced (not the ones it kept) and the renamed profile")
  Check(L.Journal.ReadBaseline().parts.twichui.revision == 1, "   the baseline is still v1's until the update checks out")

  -- 5. verify
  c = Reload(NAME, c)
  L = Engine(c)
  j = L.Journal.Read()
  local b2 = L.Journal.ReadBaseline()
  Check(j.state == "verified" and j.revision == 2 and b2.parts.twichui.revision == 2 and b2.parts.ellesmereui.revision == 2, "5. checked after the reload; the baseline is v2's")
  local kf = b2.parts.twichui.units[FONT_U]
  Check(kf.k == true and kf.p == L.Value("Spectral Medium") and kf.a == L.Value("Cinzel") and kf.l == nil,
    "   the kept font: the layout's recommended value (p), the value left in place (a, mine), kept as an override (k); read back as left")
  Check(kf.p == "=s15:Spectral Medium" and kf.a == "=s6:Cinzel", "   stored as the values themselves, not checksums")
  live = c.EllesmereUIDB.profiles[TARGET]
  Check(live.addons.EllesmereUIBags.twichTest == 2 and live.addons.EllesmereUIChat.chat.chatFontSize == CHAT_V1 + 5
    and math.abs(live.addons.EllesmereUIMinimap.minimap.position.x - mm.x) < 0.01, "   live: the layout's Bags, my chat size and minimap")
  -- the same update again: nothing to ask, nothing to do
  local again = L.Plan(V2, CLASSIC)
  Check(Rows(again)[FONT_U].case == "mine" and Rows(again)[FONT_U].decision == "keep" and (again.update.counts.conflict or 0) == 0, "   asked again: my kept font is just mine now, no conflict")
  Check(select(2, L.Apply(V2, CLASSIC, again.key)) == "nothing", "   and there is nothing to do")

  -- 6. undo the update, then restore
  local up = L.PlanUndo()
  Check(up.ok and up.reload and up.order[1] == "twichui" and up.order[2] == "ellesmereui", "6. Undo this update plans, TwichUI first")
  local okU, resU = L.Undo(up.key)
  Check(okU and resU.state == "undoing", "   undone as far as it can be before the reload")
  c = Reload(NAME, c)
  L = Engine(c)
  j = L.Journal.Read()
  local b3 = L.Journal.ReadBaseline()
  Check(j and j.state == "verified" and j.revision == 1 and j.update == nil and j.euiBackup == nil, "   after the reload: the record is v1's again, with no way back of its own")
  Check(Same(b3, b1), "   the baseline is v1's again, exactly")
  live = c.EllesmereUIDB.profiles[TARGET]
  Check(c.EllesmereUIDB.profiles[BACKUP] == nil and c.EllesmereUIDB.activeProfile == TARGET and live.addons.EllesmereUIBags.twichTest == nil
    and math.abs(live.addons.EllesmereUIMinimap.minimap.position.x - mm.x) < 0.01 and live.addons.EllesmereUIChat.chat.chatFontSize == CHAT_V1 + 5,
    "   EllesmereUI: the install's profile as it was before the update, with my changes; the copy is gone")
  TC = c.TwichUI.TwichConfig
  Check(TC.Effective(TC.Group("navigation").index.navigation.font) == "Alegreya Sans Bold" and TC.Effective(TC.Group("classBars").index.classBars.font) == "Cinzel"
    and c.TwichUIDB.ui.markerBarPosition.x == 300 and c.TwichUI.Profiles.Current() == TARGET, "   TwichUI: v1's navigation font back, my font and marker bar as I left them")
  Check(Heard(c, "the last layout update was undone"), "   said once")
  local rp = L.PlanRestore()
  local okR = L.Restore(rp.key)
  Check(rp.ok and okR, "   Restore plans and runs")
  c = Reload(NAME, c)
  Check(c.TwichUIDB.layouts == nil and c.EllesmereUIDB.activeProfile == "Mine" and c.EllesmereUIDB.profiles[TARGET] == nil
    and c.TwichUI.Profiles.Current() == "Default" and Same(c.EllesmereUIDB.profiles.Mine, beforeAll.eui.profiles.Mine),
    "   and Restore still goes back to before the first install; the record and baseline are gone")
end

---------------------------------------------------------------------------
-- 3. Baseline commit timing and partial success: a check that doesn't match keeps that adapter's last good part
---------------------------------------------------------------------------
do
  local NAME = "Partial"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local plan = L.Plan(V2, CLASSIC)
  Check(L.Apply(V2, CLASSIC, plan.key), "an update applied")
  Check(L.Verify(false).state ~= nil and L.Journal.ReadBaseline().parts.ellesmereui.revision == 1, "a check that isn't recorded writes no baseline")
  -- after the update, before the reload, something of TwichUI's changes: its check won't match
  local TC = c.TwichUI.TwichConfig
  local nf = TC.Group("navigation").index.navigation.font
  TC.Container(nf, true)[nf.key] = "Spectral Medium"
  c = Reload(NAME, c)
  L = Engine(c)
  local j, b = L.Journal.Read(), L.Journal.ReadBaseline()
  Check(j.state == "mismatch" and j.verify.baseline[1] == "ellesmereui" and #j.verify.baseline == 1, "a partial check: only EllesmereUI's part is committed")
  Check(b.parts.ellesmereui.revision == 2 and b.parts.twichui.revision == 1, "TwichUI's part stays the last one that checked out")
  -- the next update compares TwichUI against v1's baseline: the navigation font is "changed by me" and kept
  local p2 = L.Plan(V2, CLASSIC)
  Check(Rows(p2)[NAV_U].case == "conflict" and Rows(p2)[NAV_U].decision == "keep", "so the value that didn't check out is treated as the recipient's")
end

do
  -- a failed update (EllesmereUI refuses the import): nothing changes, the previous record and baseline stand
  local NAME = "Failing"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local svBefore = { j = Copy(c.TwichUIDB.layouts), eui = Copy(c.EllesmereUIDB) }
  c = LM.Boot(NAME, LM.Logout(c), { eui = { defaults = true, failImport = true } })
  local L = Engine(c)
  local plan = L.Plan(V2, CLASSIC)
  local ok, res = L.Apply(V2, CLASSIC, plan.key)
  Check(ok and res.state == "failed" and res.changed == false, "a refused import fails cleanly")
  Check(Same(c.TwichUIDB.layouts.install, svBefore.j.install) and Same(c.TwichUIDB.layouts.baseline, svBefore.j.baseline), "the previous record and baseline are exactly as they were")
  Check(c.EllesmereUIDB.profiles[TARGET] ~= nil and c.EllesmereUIDB.profiles[BACKUP] == nil and c.EllesmereUIDB.activeProfile == TARGET
    and Same(c.EllesmereUIDB.profiles[TARGET], svBefore.eui.profiles[TARGET]), "the renamed profile got its name back, unchanged, and is in use")
end

do
  -- a partial update (EllesmereUI done, TwichUI failed), then resumed: EllesmereUI is not imported twice
  local NAME = "Resume"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local TA = L.ADAPTERS.twichui
  local real = TA.Apply
  TA.Apply = function() return { state = "failed", code = "write", rollback = "clean" } end
  local plan = L.Plan(V2, CLASSIC)
  local ok, res = L.Apply(V2, CLASSIC, plan.key)
  TA.Apply = real
  Check(ok and res.state == "partial" and res.steps[1].state == "done" and res.steps[2].state == "failed", "EllesmereUI done, TwichUI failed: partial")
  Check(L.Journal.ReadBaseline().parts.ellesmereui.revision == 1, "a partial update commits no baseline")
  Check(L.PlanUndo().ok, "and it can be undone")
  local imports = c.E.called("ImportProfileSilent")
  local retry = L.Plan(V2, CLASSIC)
  Check(retry.ok and retry.update.resume and retry.parts.ellesmereui.resumed and not retry.parts.twichui.resumed, "set up again with the same choices: it resumes, EllesmereUI's step already done")
  local ok2, res2 = L.Apply(V2, CLASSIC, retry.key)
  Check(ok2 and res2.state == "applied" and c.E.called("ImportProfileSilent") == imports, "applied; EllesmereUI isn't imported a second time")
  Check(L.Journal.Read().update.ellesmereui.backup == BACKUP and c.EllesmereUIDB.profiles[BACKUP] ~= nil, "the way back from before the first attempt stands")
  c = Reload(NAME, c)
  L = Engine(c)
  local b = L.Journal.ReadBaseline()
  Check(L.Journal.Read().state == "verified" and b.parts.ellesmereui.revision == 2 and b.parts.twichui.revision == 2, "checked after the reload: both parts of the baseline are v2's")
  -- resuming a TwichUI step that half-wrote: a value already at the package's reads as "both changed the same way"
  local e = { unit = "u", n = Y, c = Y, b = { p = X }, comparable = true, known = true }
  Check(MG.Classify(e) == "both-same" and MG.Decide(e, "both-same", "keep") == "none", "and a value a stopped attempt already wrote is not written twice")
end

---------------------------------------------------------------------------
-- 4. Switching layouts: shared personal choices stay, layout-specific ones return to the new layout's values; a base update
--    reaches both layouts
---------------------------------------------------------------------------
do
  local NAME = "Switcher"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local live = c.EllesmereUIDB.profiles[TARGET]
  live.addons.EllesmereUIBags.mine = 1           -- shared by both layouts (base)
  live.addons.EllesmereUIActionBars.mine = 1     -- each layout has its own
  local TC = c.TwichUI.TwichConfig
  local nf = TC.Group("navigation").index.navigation.font
  TC.Container(nf, true)[nf.key] = "Cinzel"     -- a shared TwichUI look
  local plan = L.Plan(V1, COMPACT)
  local rows = Rows(plan)
  Check(plan.ok and plan.update.switching == CLASSIC, "Compact over Classic plans as a switch")
  Check(rows[BAGS_U].case == "mine" and rows[BAGS_U].decision == "keep", "a shared module I changed: kept")
  Check(rows[NAV_U].case == "mine" and rows[NAV_U].decision == "keep", "a shared TwichUI look I changed: kept")
  local ab = rows["ellesmereui:addons.EllesmereUIActionBars"]
  Check(ab.case == "conflict" and ab.decision == "apply" and ab.how == "switch", "a layout-specific module I changed: back to Compact's own")
  Check(rows[LAYOUT_U].decision == "apply", "and Compact's layout links")
  local kept = L.Plan(V1, COMPACT, { update = { choose = { ["ellesmereui:addons.EllesmereUIActionBars"] = "mine" } } })
  Check(Rows(kept)["ellesmereui:addons.EllesmereUIActionBars"].decision == "keep" and kept.key ~= plan.key, "unless I keep mine (a different plan)")
  local ok = L.Apply(V1, COMPACT, plan.key)
  c = Reload(NAME, c)
  live = c.EllesmereUIDB.profiles[TARGET]
  Check(ok and c.TwichUI.Layouts.Journal.Read().state == "verified" and live.addons.EllesmereUIBags.mine == 1 and live.addons.EllesmereUIActionBars.mine == nil
    and live.addons.EllesmereUIActionBars.barPositions.Bar7 ~= nil, "switched: my Bags change came along, Compact's action bars replaced Classic's")
  Check(c.TwichUI.TwichConfig.Effective(nf) == "Cinzel", "and my TwichUI look too")
  -- a base update reaches both layouts
  local okC, rc = L0.Resolve(V2, CLASSIC, { screen = { w = 2133.33, h = 1200 } })
  local okK, rk = L0.Resolve(V2, COMPACT, { screen = { w = 2133.33, h = 1200 } })
  Check(okC and okK and rc.adapters.twichui.units[NAV_U] == "Cinzel" and rk.adapters.twichui.units[NAV_U] == "Cinzel"
    and rc.adapters.ellesmereui.units[BAGS_U].twichTest == 2 and rk.adapters.ellesmereui.units[BAGS_U].twichTest == 2, "a base update reaches both layouts")
  local p3 = Engine(c).Plan(V2, COMPACT)
  Check(Rows(p3)[BAGS_U].case == "conflict" and Rows(p3)[BAGS_U].decision == "keep", "and in Compact my Bags change meets the layout's: mine kept")
end

---------------------------------------------------------------------------
-- 5. Versions: another EllesmereUI or merge contract can't be compared unit by unit; a newer baseline is never overwritten
---------------------------------------------------------------------------
do
  local NAME = "Versions"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUIBags.mine = 1
  c = LM.Boot(NAME, LM.Logout(c), { eui = EUI, euiVersion = "9.7.0" })
  local L = Engine(c)
  local plan = L.Plan(V2, CLASSIC)
  local rows = Rows(plan)
  Check(plan.ok and rows[BAGS_U].case == "unknown" and rows[BAGS_U].decision == "keep", "another EllesmereUI version: its units can't be compared; one that differs is kept as mine")
  Check(rows[FONT_U].case == "package", "TwichUI's are compared as before")
  -- ownership survives a version change
  local b = L.Journal.ReadBaseline()
  b.parts.ellesmereui.units[CHATSIZE_U] = { o = true }
  L.Journal.WriteBaseline(b)
  Check(Rows(L.Plan(V2, CLASSIC))[CHATSIZE_U].case == "owned", "a unit the recipient made theirs stays theirs")
  -- another merge contract
  b = L.Journal.ReadBaseline()
  b.parts.twichui.merge = 99
  L.Journal.WriteBaseline(b)
  Check(Rows(L.Plan(V2, CLASSIC))[NAV_U].case == "unknown", "a baseline part from another merge contract: can't tell")
  -- a newer baseline: refused, never overwritten
  b = L.Journal.ReadBaseline()
  b.v = 2
  c.TwichUIDB.layouts.baseline = b
  local nb = Copy(b)
  local pn = L.Plan(V2, CLASSIC)
  Check(not pn.ok and pn.blocked[1].code == "baseline-newer", "a baseline from a newer TwichUI blocks the update")
  Check(select(2, L.Apply(V2, CLASSIC, pn.key)) == "blocked" and Same(c.TwichUIDB.layouts.baseline, nb), "and is left exactly as it is")
  -- a damaged one is not used (and not repaired)
  c.TwichUIDB.layouts.baseline = { v = 1, package = "twichui-adventure", parts = "nope" }
  local pd = L.Plan(V2, CLASSIC)
  Check(pd.ok and pd.update.baseline == "damaged" and Rows(pd)[NAV_U].case == "unknown", "a damaged baseline: nothing is compared against it")
end

---------------------------------------------------------------------------
-- 6. Opaque EllesmereUI units: when the recipient's blob can't be carried into the new install (another vintage), the addon
--    is kept as it is or replaced (after its current profile is kept); never merged inside
---------------------------------------------------------------------------
do
  local NAME = "Vintage"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local live = c.EllesmereUIDB.profiles[TARGET]
  live.addons.EllesmereUIBags.mine = 1
  live._migrations = Copy(live._migrations or {})
  live._migrations.laterMigration = true          -- EllesmereUI migrated the profile since
  local plan = L.Plan(V2, CLASSIC)
  local w = plan.update.whole.ellesmereui
  Check(plan.ok and w and w.needed and w.choice == "keep", "my Bags change can't be carried into the new install: EllesmereUI as a whole is kept by default")
  Check(plan.parts.ellesmereui.kept and plan.parts.ellesmereui.nothing and not plan.parts.ellesmereui.backup, "nothing is imported for it, and no copy is made")
  local imports = c.E.called("ImportProfileSilent")
  local ok, res = L.Apply(V2, CLASSIC, plan.key)
  Check(ok and res.steps[1].state == "kept" and c.E.called("ImportProfileSilent") == imports, "applied: EllesmereUI kept as it is, TwichUI updated")
  Check(c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUIBags.mine == 1 and c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUIBags.twichTest == nil, "my EllesmereUI profile is untouched")
  c = Reload(NAME, c)
  L = Engine(c)
  local b = L.Journal.ReadBaseline()
  Check(L.Journal.Read().state == "verified" and b.parts.ellesmereui.revision == 1 and b.parts.twichui.revision == 2,
    "checked; EllesmereUI's baseline stays v1's, so its update is offered again next time")
  -- replace, after its current profile is kept
  local pr = L.Plan(V2, CLASSIC, { update = { whole = { ellesmereui = "replace" } } })
  Check(pr.ok and pr.parts.ellesmereui.backup and Rows(pr)[BAGS_U].decision == "apply" and Rows(pr)[BAGS_U].how == "whole", "replace: the layout's Bags, after keeping mine")
  local okR = L.Apply(V2, CLASSIC, pr.key, { update = { whole = { ellesmereui = "replace" } } })
  Check(okR and c.EllesmereUIDB.profiles[BACKUP].addons.EllesmereUIBags.mine == 1 and c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUIBags.mine == nil, "replaced; mine is in the copy")
  local up = L.PlanUndo()
  Check(up.ok and L.Undo(up.key), "and Undo this update puts it back")
  c = Reload(NAME, c)
  Check(c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUIBags.mine == 1 and c.EllesmereUIDB.profiles[BACKUP] == nil, "mine is back after the reload")
end

---------------------------------------------------------------------------
-- 7. The layout links are one atomic group with the frames linked by them; a frame linked to a screen edge is merged on its own
---------------------------------------------------------------------------
do
  local NAME = "Links"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local live = c.EllesmereUIDB.profiles[TARGET]
  local b5 = live.addons.EllesmereUIActionBars.barPositions.Bar5
  b5.x = b5.x + 50                                   -- bar 5 is linked to bar 4: part of the group
  local plan = L.Plan(V2, CLASSIC)                   -- v2 changes Bar 5's link
  local rows = Rows(plan)
  Check(rows[BAR5_U].group == "layout" and rows[LAYOUT_U].group == "layout", "bar 5 (linked to bar 4) and the links are one group")
  Check(rows[MINIMAP_U].group == nil, "the minimap (linked to a screen edge) is not")
  Check(plan.update.groups.layout and plan.update.groups.layout.choice == "mine", "I moved bar 5 and the layout changed the links: the group stays mine")
  Check(rows[LAYOUT_U].decision == "keep" and rows[BAR5_U].decision == "keep", "the links and bar 5 together")
  local d = plan.parts.ellesmereui.payload.data
  Check(Same(d.unlockLayout.anchors, live.unlockLayout.anchors) and d.addons.EllesmereUIActionBars.barPositions.Bar5.x == b5.x, "the payload carries my links and my bar 5, both")
  local pg = L.Plan(V2, CLASSIC, { update = { groups = { layout = "package" } } })
  local dg = pg.parts.ellesmereui.payload.data
  Check(Rows(pg)[LAYOUT_U].decision == "apply" and Rows(pg)[BAR5_U].decision == "apply" and dg.unlockLayout.anchors.Bar5.offsetY ~= live.unlockLayout.anchors.Bar5.offsetY,
    "or the layout's, both together")
  -- never one link field on its own
  local okC = L.Plan(V2, CLASSIC, { update = { choose = { [BAR5_U] = "package", [LAYOUT_U] = "mine" } } })
  Check(Rows(okC)[BAR5_U].decision == "keep" and Rows(okC)[BAR5_U].how == "group", "a member can't take the layout's alone while the group stays mine")
end

---------------------------------------------------------------------------
-- 8. Ownership, reset to the addon's default, a setting the package stops managing, a deleted module, a place off the screen
---------------------------------------------------------------------------
do
  local NAME = "Owner"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local TC = c.TwichUI.TwichConfig
  local font = TC.Group("classBars").index.classBars.font
  -- stop managing the class bars' font (no change of mine yet: the option is offered on any managed unit)
  local own = { update = { choose = { [FONT_U] = "own" } } }
  local p = L.Plan(V2, CLASSIC, own)
  Check(Rows(p)[FONT_U].decision == "owned", "Stop managing: the font is mine")
  Check(L.Apply(V2, CLASSIC, p.key, own), "applied")
  Check(TC.Effective(font) == "Alegreya Sans Bold", "not written: it stays what it was")
  c = Reload(NAME, c)
  L = Engine(c)
  TC = c.TwichUI.TwichConfig
  Check(L.Journal.ReadBaseline().parts.twichui.units[FONT_U].o == true, "the baseline records that it is mine")
  local V3 = Publish(3, function(pk) Revision2(pk); pk.layers.base.twichui.groups.classBars.classBars.font = "Cinzel" end)
  local p3 = L.Plan(V3, CLASSIC)
  Check(Rows(p3)[FONT_U].case == "owned" and Rows(p3)[FONT_U].decision == "owned", "a later update leaves it alone")
  Check(Rows(L.Plan(V3, CLASSIC, { update = { choose = { [FONT_U] = "manage" } } }))[FONT_U].decision == "apply", "Manage again hands it back to the layout")
  Check(Rows(L.Plan(V3, CLASSIC, { update = { policy = "recommended" } }))[FONT_U].decision == "owned", "the recommended configuration doesn't take back what I made mine")
  -- reset to the addon's default (nothing stored): my change, kept as not stored
  local nav = TC.Group("navigation").index.navigation.font
  TC.Container(nav, true)[nav.key] = nil
  local pr = L.Plan(V3, CLASSIC)
  Check(Rows(pr)[NAV_U].case == "mine" and Rows(pr)[NAV_U].decision == "keep" and Rows(pr)[NAV_U].e.cs == "d", "reset to the default: my change, kept (nothing written)")
  -- a setting the package stops managing: released, the value stays
  local V4 = Publish(4, function(pk) Revision2(pk); pk.layers.base.twichui.groups.healerWatch.healerWatch.font = nil end)
  local HW_U = "twichui:" .. table.concat(TC.Group("healerWatch").index.healerWatch.font.at, ".") .. ".font"
  local hwBefore = TC.Effective(TC.Group("healerWatch").index.healerWatch.font)
  local p4 = L.Plan(V4, CLASSIC)
  Check(Rows(p4)[HW_U].case == "removed" and Rows(p4)[HW_U].decision == "release", "no longer in the package: released")
  local ok4, r4 = L.Apply(V4, CLASSIC, p4.key)
  Check(ok4 and TC.Effective(TC.Group("healerWatch").index.healerWatch.font) == hwBefore, "and its value stays what it was")
  c = Reload(NAME, c)
  L = Engine(c)
  Check(L.Journal.ReadBaseline().parts.twichui.units[HW_U] == nil, "the baseline stops tracking it")
  -- a module the recipient deleted can't stay deleted (EllesmereUI would take the one from another profile): the layout's goes back
  c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUIBags = nil
  local pd = L.Plan(V4, CLASSIC)
  Check(Rows(pd)[BAGS_U].decision == "apply" and Rows(pd)[BAGS_U].how == "absent" and pd.parts.ellesmereui.payload.data.addons.EllesmereUIBags ~= nil,
    "a deleted module: the layout's is put back, and the review can say why")
  -- a place I put off the screen: a warning, and my place stays
  c.TwichUIDB.ui.markerBarPosition = { x = 5000, y = 0 }
  local po = L.Plan(V4, CLASSIC)
  local warned = false
  for _, w in ipairs(po.update.warnings) do if w.unit == MARKER_U and w.code == "offscreen" then warned = true end end
  Check(warned and Rows(po)[MARKER_U].decision == "keep", "a kept place off the screen is warned about")
  Check(L.Apply(V4, CLASSIC, po.key) and c.TwichUIDB.ui.markerBarPosition.x == 5000, "and never moved to clear the warning")
end

---------------------------------------------------------------------------
-- 9. The wizard: the update review (three ways, details with choices), the confirmation, Undo this update, Keep the update
---------------------------------------------------------------------------
do
  local NAME = "Wizard Update"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), PKG, CLASSIC)
  local TC = c.TwichUI.TwichConfig
  local f = TC.Group("classBars").index.classBars.font
  TC.Container(f, true)[f.key] = "Cinzel"
  c.SlashCmdList.TWICHUI("layout")
  local w, WK = c.TwichUILayoutWizard, c.TwichUI.LayoutWizard
  local MK = WK.Model
  local function Click(label)
    local b = assert(LM.Button(w, label), "no button " .. label)
    assert(b.enabled, "button '" .. label .. "' is disabled")
    b.scripts.OnClick(b)
  end
  local function Manage()   -- the maintenance actions are under "Manage layout"
    local b = LM.Button(w, "Manage layout")
    if b and not b.open then b.scripts.OnClick(b) end
  end
  Check(MK.Step() == 6, "the wizard opens on the result")
  Manage()
  Click("Set up again")
  while MK.Step() < 5 do Click(MK.Step() == 1 and "Get started" or "Next") end
  -- the bundled package with a different accent: an update in which my font change is kept
  MK.SetPick("accent", "ember")
  WK.Window.Refresh()
  Check(LM.Says(w, "Ready to update") and LM.Says(w, "Update: Keep my customizations") and LM.Visible(LM.Button(w, "Change")), "the review is a receipt with one update-policy row")
  Check(not LM.Visible(LM.Button(w, "Review conflicts")), "the three ways are behind Change")
  Click("Change")
  Check(LM.Says(w, "Update while keeping my customizations") and LM.Says(w, "Reapply the recommended configuration")
    and LM.Says(w, "Review conflicts"), "the review offers the three ways")
  Check(LM.Says(w, "Personal settings kept: 1") and LM.Says(w, "Recommended changes:"), "and counts what is kept and what changes")
  Check(MK.UpdateMode() == "keep" and not LM.Visible(LM.Button(w, "Keep mine")), "keeping my changes, with the details folded away")
  local built = c.made()
  Click("Review conflicts")
  Check(MK.UpdateMode() == "review" and LM.Says(w, "Class resource bars > Font") and LM.Says(w, "Yours: Cinzel"), "Review conflicts lists each setting with my value and the layout's")
  local ur = MK.UpdateReview()
  local fontRow
  for _, r in ipairs(ur.rows) do if r.unit == FONT_U then fontRow = r end end
  Check(fontRow and fontRow.case == "mine" and fontRow.current == "Cinzel" and fontRow.recommended == "Alegreya Sans Bold"
    and fontRow.effect ~= "" and fontRow.owner ~= "", "the row: setting, current, recommended, effect, ownership")
  Click("Use recommended")
  Check(MK.UpdateReview().rows[1].decision == "apply" or (function()
    for _, r in ipairs(MK.UpdateReview().rows) do if r.unit == FONT_U then return r.decision == "apply" end end end)(), "choosing re-plans: the layout's font")
  Click("Update while keeping my customizations")
  Click("Reapply the recommended configuration")
  Click("Review conflicts")
  Check(c.made() == built, "switching ways and choices makes no frames")
  Click("Apply")
  Check(c.popup and c.popup.text:find("Updating", 1, true) and c.popup.text:find("Undo this update", 1, true), "the question names the update and the way back")
  c.Accept()
  Check(MK.Step() == 6 and LM.Says(w, "Waiting for a reload") and LM.Says(w, "This was an update") and LM.Visible(LM.Button(w, "Undo this update")), "the result offers Undo this update")
  Check(TC.Effective(f) == "Alegreya Sans Bold", "the layout's font, as chosen")
  Click("Undo this update")
  Check(c.popup and c.popup.key == "TWICHUI_LAYOUT_UNDO" and c.popup.text:find("Undo the last update", 1, true), "undo asks first, naming what it does")
  c.Accept()
  Check(c.TwichUI.Layouts.Journal.Read().state == "undoing" and TC.Effective(f) == "Cinzel", "undoing: my font is back at once; EllesmereUI waits for the reload")
  Click("Reload now")
  c = Reload(NAME, c)
  local j = c.TwichUI.Layouts.Journal.Read()
  Check(j.state == "verified" and j.picks and j.picks.accent ~= "ember", "after the reload: the install from before the update")
  -- keeping an update for good removes the copy
  local L = Engine(c)
  local p = L.Plan(PKG, CLASSIC, { picks = { accent = "ember" } })
  L.Apply(PKG, CLASSIC, p.key, { picks = { accent = "ember" } })
  c = Reload(NAME, c)
  c.SlashCmdList.TWICHUI("layout")
  w = c.TwichUILayoutWizard
  Manage()
  Check(LM.Visible(LM.Button(w, "Keep the update")) and c.EllesmereUIDB.profiles[BACKUP] ~= nil, "a checked update can be kept")
  local b = LM.Button(w, "Keep the update")
  b.scripts.OnClick(b)
  Check(c.popup.text:find(BACKUP, 1, true), "the question names the copy it removes")
  c.Accept()
  Check(c.EllesmereUIDB.profiles[BACKUP] == nil and c.TwichUI.Layouts.Journal.Read().update == nil and c.TwichUI.Layouts.Journal.Read().state == "verified",
    "kept: the copy is gone, nothing else changed")
  Check(not LM.Visible(LM.Button(w, "Undo this update")) and LM.Visible(LM.Button(w, "Restore previous setup")), "Undo is no longer offered; Restore still is")
end

---------------------------------------------------------------------------
-- 10. Consecutive updates: v1, my change, v2 keeps it, v3 doesn't touch it, v4 changes it again. My value stays an override
--     the whole way; it never becomes the layout's recommended default
---------------------------------------------------------------------------
do
  local NAME = "Consecutive"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local TC = c.TwichUI.TwichConfig
  local font = TC.Group("classBars").index.classBars.font
  TC.Container(font, true)[font.key] = "Cinzel"
  c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUIChat.chat.chatFontSize = CHAT_V1 + 5
  local p2 = L.Plan(V2, CLASSIC)
  Check(Rows(p2)[FONT_U].case == "conflict" and Rows(p2)[CHATSIZE_U].case == "conflict", "v2: both conflicts, mine kept")
  L.Apply(V2, CLASSIC, p2.key)
  c = Reload(NAME, c)
  L = Engine(c)
  -- v3 changes something else only
  local V3 = Publish(3, function(pk) Revision2(pk); pk.layers.base.twichui.groups.chronicleLook.chronicleAppearance.font = "Cinzel" end)
  local p3 = L.Plan(V3, CLASSIC)
  Check(Rows(p3)[FONT_U].case == "mine" and Rows(p3)[FONT_U].decision == "keep", "v3 leaves the font alone: still mine, kept")
  Check(Rows(p3)[CHATSIZE_U].case == "mine" and Rows(p3)[CHATSIZE_U].decision == "keep", "and my chat text size")
  Check(L.Apply(V3, CLASSIC, p3.key), "v3 applied")
  c = Reload(NAME, c)
  L = Engine(c)
  TC = c.TwichUI.TwichConfig
  local b3 = L.Journal.ReadBaseline()
  Check(b3.parts.twichui.revision == 3 and b3.parts.twichui.units[FONT_U].k == true and b3.parts.twichui.units[FONT_U].a == L.Value("Cinzel")
    and b3.parts.twichui.units[FONT_U].p == L.Value("Spectral Medium"), "after v3 the font is still recorded as my override over the layout's value")
  Check(b3.parts.ellesmereui.units[CHATSIZE_U].k == true, "and so is the chat text size")
  -- v4 changes the font again: asked again, mine kept by default
  local V4 = Publish(4, function(pk) Revision2(pk); pk.layers.base.twichui.groups.classBars.classBars.font = "Alegreya Sans Bold" end)
  local p4 = L.Plan(V4, CLASSIC)
  Check(Rows(p4)[FONT_U].case == "conflict" and Rows(p4)[FONT_U].decision == "keep", "v4 changes the font again: a conflict again, mine kept")
  Check(L.Apply(V4, CLASSIC, p4.key) and TC.Effective(TC.Group("classBars").index.classBars.font) == "Cinzel", "and after v4 the font is still mine")
  -- if I set the layout's value myself, the override ends
  local e = { unit = "u", n = Y, c = X, b = { p = X, a = Z, k = true }, comparable = true, known = true }
  Check(MG.Classify(e) == "package", "an override set back to the layout's value is no longer mine: the next change applies")
end

---------------------------------------------------------------------------
-- 11. Finish (Keep this setup), reload, reopen the wizard, update: still managed, the install's profiles still its own, the
--     baseline still there. Finishing is not detaching
---------------------------------------------------------------------------
do
  local NAME = "Finisher"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local TC = c.TwichUI.TwichConfig
  local font = TC.Group("classBars").index.classBars.font
  TC.Container(font, true)[font.key] = "Cinzel"
  local m1 = L.Journal.ReadManaged()
  Check(m1 and m1.revision == 1 and m1.variant == CLASSIC and m1.targets.twichui == TARGET and m1.targets.ellesmereui == TARGET
    and m1.home.ellesmereui == "Mine" and m1.home.twichui == "Default", "the management record: package, revision, layout, the install's own profiles, where it came from")
  local ok = L.Finish()
  Check(ok and L.Journal.Read() == nil and L.Journal.ReadManaged() and L.Journal.ReadBaseline(), "Finish: the restore point goes, the management record and baseline stay")
  Check(not L.PlanRestore().ok, "Restore is no longer offered")
  c = Reload(NAME, c)
  L = Engine(c)
  Check(L.Journal.ReadManaged().revision == 1 and L.Journal.ReadBaseline().parts.twichui.revision == 1, "after a reload: still managed, the baseline still there")
  -- reopen the wizard: it shows the managed layout
  c.SlashCmdList.TWICHUI("layout")
  local w, MK = c.TwichUILayoutWizard, c.TwichUI.LayoutWizard.Model
  local mb = LM.Button(w, "Manage layout")
  mb.scripts.OnClick(mb)
  Check(MK.Step() == 6 and LM.Says(w, "Installed and managed") and LM.Says(w, "Your interface is ready") and LM.Visible(LM.Button(w, "Set up again")) and not LM.Visible(LM.Button(w, "Restore previous setup")),
    "the wizard opens on the managed layout; Set up again, no Restore")
  -- update to v2: an update into profiles still recognised as the install's own, compared against the baseline
  local plan = L.Plan(V2, CLASSIC)
  Check(plan.ok and plan.mode == "again" and plan.managed and plan.update.baseline == "ok", "v2 plans as an update (the profiles are still ours)")
  Check(Rows(plan)[FONT_U].case == "conflict" and Rows(plan)[FONT_U].decision == "keep" and Rows(plan)[NAV_U].decision == "apply", "my font kept, the layout's change applied")
  Check(plan.parts.ellesmereui.backup and plan.parts.ellesmereui.home == "Mine", "the install's profile is kept for Undo; Mine is where it came from")
  local okA, res = L.Apply(V2, CLASSIC, plan.key)
  Check(okA and res.state == "applied" and L.Journal.Read().update.managed.revision == 1, "applied; the way back holds the management record from before")
  c = Reload(NAME, c)
  L = Engine(c)
  Check(L.Journal.Read().state == "verified" and L.Journal.ReadManaged().revision == 2 and L.Journal.ReadBaseline().parts.twichui.revision == 2, "checked: managed at v2")
  -- undo goes back to the finished setup at v1 (no install record), not to before the first install
  local up = L.PlanUndo()
  Check(up.ok and L.Undo(up.key), "Undo this update")
  c = Reload(NAME, c)
  L = Engine(c)
  Check(L.Journal.Read() == nil and L.Journal.ReadManaged().revision == 1 and L.Journal.ReadBaseline().parts.twichui.revision == 1
    and c.EllesmereUIDB.profiles[BACKUP] == nil and c.EllesmereUIDB.activeProfile == TARGET, "back to the finished v1 setup, still managed")
  -- stopping management is the only thing that forgets it
  Check(L.Detach() and L.Journal.ReadManaged() == nil and L.Journal.ReadBaseline() == nil and c.EllesmereUIDB.profiles[TARGET] ~= nil,
    "Stop managing forgets the records and changes no profile")
  Check(not L.Plan(V2, CLASSIC).ok, "and then the install's profiles are no longer recognised as its own")
end

---------------------------------------------------------------------------
-- 12. What the check after the reload can and can't say: values read back by value, whole parts only for presence
---------------------------------------------------------------------------
do
  local NAME = "Presence"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local j, b = L.Journal.Read(), L.Journal.ReadBaseline()
  Check(j.verify.checked > 0 and j.verify.presence >= 18, "the check counts values read back (" .. j.verify.checked .. ") apart from parts only present (" .. j.verify.presence .. ")")
  Check(b.parts.ellesmereui.units[BAGS_U].u == true and b.parts.ellesmereui.units[LAYOUT_U].u == true and b.parts.ellesmereui.units[MINIMAP_U].u == nil
    and b.parts.twichui.units[FONT_U].u == nil, "the baseline marks whole parts as checked only for presence; values are not marked")
  c.SlashCmdList.TWICHUI("layout")
  Check(LM.Says(c.TwichUILayoutWizard, "checked only for being there"), "and the result says so in words")
end

if failures > 0 then print(failures .. " FAILED") os.exit(1) end
print("LAYOUT UPDATE TESTS PASSED")
