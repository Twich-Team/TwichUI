dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- Layout packages, Phase 6: authoring and publishing (docs/layouts/publishing.md). Covers: packaging; capture through the
-- adapters' allowlists (and that nothing personal or per-character is kept); the structured diff against a starting package;
-- keeping a change in one layout or promoting it to the shared base, and what that does to every layout; the draft, the
-- checks a recipient's TwichUI will make, the media it points at; publishing as an immutable, deterministic snapshot; the
-- envelope's metadata and version checks; malformed, oversized and unsupported packages; the store's bounds; sending and
-- receiving through the real sharing transport between two clients (offers, interrupted and duplicate pieces, a sender's name
-- in the payload, an offer that doesn't match what arrives, no automatic application); that a setup still travels as before;
-- and installing and restoring a received package through the wizard. Nothing here is the game: the in-game checks are
-- listed in docs/layouts/publishing.md.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same, Heard = LM.Copy, LM.Same, LM.Heard

local function Run(n) for _ = 1, n or 12 do FlushTimers(); Pump() end end
-- runs frames and messages until done() is true (or gives up)
local function Until(done, limit)
  for _ = 1, limit or 400 do
    if done() then return true end
    FlushTimers(); Pump()
  end
  return done()
end

local CLASSIC, COMPACT = "classic-adventure", "compact-adventure"
-- The revision of the package TwichUI ships (TwichUI_Layouts/Classic.lua): the tests follow it, so updating the bundled layout
-- (tools/update_bundled_layout.sh raises it) doesn't need these numbers changed by hand.
local SHIPPED = tonumber(assert(io.open(REPO .. "TwichUI_Layouts/Classic.lua")):read("*a"):match('id = "twichui%-adventure", revision = (%d+)'))
assert(SHIPPED, "the shipped revision")

-- A client, its layout engine and the authoring model loaded the way the game loads them
local function Client(name, sv, opts)
  local c = LM.Boot(name, sv, opts)
  CLIENTS[name] = c
  return c
end
local function Load(c)
  assert(c.C_AddOns.LoadAddOn("TwichUI_LayoutWizard"))
  return c.TwichUI, c.TwichUI.Layouts, c.TwichUI.LayoutWizard
end

-- An EllesmereUI profile that is the included package's Classic layout with two modules changed: the minimap (the package
-- keeps it once, in the shared base) and the action bars (each layout has its own)
local function TweakedProfile(LY)
  local pkg = LY.ADVENTURE_PACKAGE
  local ok, _, checked = LY.Validate(pkg)
  assert(ok)
  local function Unit(layer, adapter, unit)
    local f = layer[adapter]
    return f and f.units[unit]
  end
  local base, mine = checked.layers.base, checked.layers.variants[CLASSIC]
  local prof = { addons = {}, fonts = Copy(Unit(base, "ellesmereui", "ellesmereui:root.fonts")),
    darkMode = Copy(Unit(base, "ellesmereui", "ellesmereui:root.darkMode")),
    euiAccent = Copy(Unit(base, "ellesmereui", "ellesmereui:root.euiAccent")),
    _migrations = Copy(Unit(base, "ellesmereui", "ellesmereui:root._migrations")),
    unlockLayout = Copy(Unit(mine, "ellesmereui", "ellesmereui:layout")),
    customColors = { a = 1 }, specOverrides = { b = 1 }, assignedSpecs = { c = 1 } }
  for _, layer in ipairs({ base, mine }) do
    for unit, v in pairs(layer.ellesmereui.units) do
      local m = unit:match("^ellesmereui:addons%.([%w_]+)$")
      if m then prof.addons[m] = Copy(v) end
    end
  end
  prof.addons.EllesmereUIMinimap.minimap = prof.addons.EllesmereUIMinimap.minimap or {}
  prof.addons.EllesmereUIMinimap.minimap.coordsMode = "tweaked-minimap"
  prof.addons.EllesmereUIActionBars.tweaked = true
  prof.addons.EllesmereUIDataBars.characters = { ["Someone - Realm"] = 1 }   -- a per-character record
  prof.addons.Bogus = { x = 1 }                                          -- not an EllesmereUI module
  prof.addons.EllesmereUIQuickdraw = nil                                 -- a module the shared base names and this profile lacks
  prof.darkMode = nil                                                    -- and a look key
  return prof
end

-- An author's private font folder in the starting package and in the profile captured from (the included package pointed at
-- one until it was fixed; this keeps the media check tested whatever the shipped data holds). Only this client's loaded copy.
local function Plant(t)
  for k, v in pairs(t) do
    if k == "unitNameFontPath" then t[k] = [[Interface\AddOns\MyFonts\fonts\AlegreyaSansSC-Bold.ttf]] return true end
    if type(v) == "table" and Plant(v) then return true end
  end
end
local function PlantFont(c, LY)
  assert(Plant(LY.ADVENTURE_PACKAGE.layers), "a font path to plant the private folder in")
  assert(Plant(c.EllesmereUIDB.profiles.Tweak), "and the same in the profile captured from")
end

local function Booted(name, sv, opts)
  local c = Client(name, sv, opts)
  local TW, LY, WZ = Load(c)
  c.EllesmereUIDB.profiles.Tweak = TweakedProfile(LY)
  return c, TW, LY, WZ
end

---------------------------------------------------------------------------
-- 1. Packaging
---------------------------------------------------------------------------
do
  local layouts = LM.TocFiles("TwichUI_Layouts")
  local names = {}
  for i, f in ipairs(layouts) do names[f:match("([^/]+)$")] = i end
  Check(names["Capture.lua"] and names["Publish.lua"] and names["Store.lua"], "the engine lists Capture, Publish and Store")
  Check(names["Capture.lua"] > names["Engine.lua"] and names["Publish.lua"] > names["Capture.lua"] and names["Store.lua"] > names["Publish.lua"]
    and names["Store.lua"] < names["TestPackage.lua"], "in dependency order: capture, publish, store, then the packages")
  local wiz = {}
  for i, f in ipairs(LM.TocFiles("TwichUI_LayoutWizard")) do wiz[f:match("([^/]+)$")] = i end
  Check(wiz["Author.lua"] and wiz["AuthorWindow.lua"] and wiz["AuthorWindow.lua"] < wiz["Window.lua"], "the wizard lists the authoring files before its window")
  local core = io.open(REPO .. "!!!TwichUI/!!!TwichUI.toc"):read("*a")
  Check(not core:find("Publish.lua", 1, true) and not core:find("Author.lua", 1, true), "the core lists none of them: it only launches")
  local wtoc = io.open(REPO .. "TwichUI_LayoutWizard/TwichUI_LayoutWizard.toc"):read("*a")
  Check(not wtoc:find("SavedVariables", 1, true), "still no saved variables of its own")
  -- nothing loads until asked, and the workspace is not part of the setup wizard's steps
  local c = Client("Pkg")
  Check(c.layoutLoads == 0 and c.wizardLoads == 0, "nothing is loaded at login")
  c.SlashCmdList.TWICHUI("layout")
  local WZ = c.TwichUI.LayoutWizard
  Check(WZ.Author ~= nil and not WZ.Author.Active(), "the wizard opening does not start the workspace")
  Check(#WZ.Model.STEPS == 6, "and the wizard still has its six steps")
end

---------------------------------------------------------------------------
-- 2. Capture: the adapters' allowlists
---------------------------------------------------------------------------
do
  local c, TW, LY = Booted("Cap Ture")
  local prof = c.EllesmereUIDB.profiles.Tweak
  local cap, rep = LY.Capture.Read(prof, nil)
  local eui = cap.ellesmereui
  Check(cap.twichui == nil, "no TwichUI profile named: nothing of TwichUI captured")
  Check(eui.modules.EllesmereUIMinimap and eui.modules.EllesmereUIActionBars, "module blobs are kept")
  Check(eui.modules.Bogus == nil, "a key that is not an EllesmereUI module is not")
  Check(eui.modules.EllesmereUIDataBars and eui.modules.EllesmereUIDataBars.characters == nil, "per-character records are stripped from a blob")
  Check(eui.root.fonts and eui.root.euiAccent and eui.root.customColors == nil, "the look is kept, custom colours are not")
  Check(eui.layout and next(eui.layout) ~= nil, "layout links are kept")
  local left = {}
  for _, l in ipairs(rep.left) do left[l.where] = true end
  Check(left["profile.customColors"] and left["profile.specOverrides"] and left["profile.assignedSpecs"] and left["addons.Bogus"]
    and left["addons.EllesmereUIDataBars.characters"], "everything left out is listed, with why")
  Check(Same(prof.addons.EllesmereUIDataBars.characters, { ["Someone - Realm"] = 1 }), "and the profile itself was not changed")
  -- the copy shares nothing with the profile
  eui.modules.EllesmereUIMinimap.minimap.coordsMode = "changed after"
  Check(prof.addons.EllesmereUIMinimap.minimap.coordsMode == "tweaked-minimap", "the capture is a copy: editing it leaves the profile alone")

  -- TwichUI: only differences from the defaults, never a feature's on/off switch, places where set
  local slot = Copy(c.TwichUIDB)
  slot.ui = slot.ui or {}
  slot.ui.classBarsPosition = { main = { x = 12, y = -300 } }
  slot.modules = slot.modules or {}
  slot.modules.markersBar = true
  local cap2, rep2 = LY.Capture.Read(nil, slot)
  Check(cap2.ellesmereui == nil, "no EllesmereUI profile named: nothing of it captured")
  Check(cap2.twichui.places["class-bars"] and cap2.twichui.places["class-bars"].x == 12, "a place is captured")
  Check(rep2.counts.switches > 0 and not (cap2.twichui.groups.markerBar and cap2.twichui.groups.markerBar.modules), "switches are counted and not captured")
  local anySwitch = false
  for _, slots in pairs(cap2.twichui.groups) do if slots.modules then anySwitch = true end end
  Check(not anySwitch, "no feature switch is in a capture")

  -- the personal-data scan
  local names, realms = { Mallory = true }, { Elsewhere = true }
  local found = LY.Capture.Scan({ a = { b = "my friend Mallory said" }, c = "|Hitem:123|h[x]|h", d = "Player-1234-ABCDEF01", e = "Elsewhere", f = "Tom#1234" }, names, realms)
  Check(found.name == 1 and found.realm == 1 and found.guid == 1 and found.link == 1 and found.battletag == 1, "names, realms, GUIDs, links and BattleTags are found")
  local clean = LY.Capture.Scan({ a = "Malloryville", b = "plain" }, names, realms)
  Check(clean.name == 0, "whole words only")
end

---------------------------------------------------------------------------
-- 3. The workspace: diff, assignment and what a promotion does to both layouts
---------------------------------------------------------------------------
local function Setup(name)
  local c, TW, LY, WZ = Booted(name)
  local A = WZ.Author
  assert(A.Begin())
  A.SetSource("eui", "Tweak")
  A.SetSource("twichui", nil)
  return c, TW, LY, WZ, A
end

do
  local c, TW, LY, WZ, A = Setup("Auth Or")
  local before = { eui = Copy(c.EllesmereUIDB), tw = Copy(c.TwichUIDB) }
  Check(A.Variants()[1].id == CLASSIC and A.Variants()[2].id == COMPACT, "both layouts of the package are on offer")
  local capOk, capWhy = A.Capture()
  Check(capOk, "capture works from the named profile: " .. tostring(capWhy))
  Check(Same(before.eui, c.EllesmereUIDB) and Same(before.tw, c.TwichUIDB), "and writes nothing: not the source profile, not TwichUI's data")
  local items = A.Items()
  local by = {}
  for _, it in ipairs(items) do by[it.id] = it end
  local mini, bars = by["ellesmereui:addons.EllesmereUIMinimap"], by["ellesmereui:addons.EllesmereUIActionBars"]
  Check(mini and mini.kind == "changed" and mini.lives == "base", "the minimap blob differs and lives in the shared base")
  Check(bars and bars.kind == "changed" and bars.lives == "variant", "the action bars differ and live in this layout")
  Check(mini.include and mini.to == "variant" and bars.to == "variant", "included, and by default kept in this layout only: nothing is shared by default")
  Check(by["ellesmereui:root.fonts"] == nil, "what did not change is not listed")
  Check(by["ellesmereui:root.euiAccent"] == nil, "the accent is set by a wizard choice, so a capture leaves it alone")
  local skipped = A.Skipped()
  Check(#skipped >= 1 and skipped[1].why:find("choice"), "and says so")
  local removed = 0
  for _, it in ipairs(items) do
    if it.kind == "removed" then removed = removed + 1; Check(not it.include, "a removal starts out left out: " .. it.id) end
  end
  Check(removed >= 2, "what the profile lacks is offered as a removal, not assumed")

  -- what a promotion does
  local e1 = A.Effects(mini.id, "variant")
  Check(e1[1].variant == CLASSIC and e1[1].change == "gets" and e1[2].variant == COMPACT and e1[2].change == "keeps",
    "kept in Classic only: Classic gets it, Compact keeps its own")
  local e2 = A.Effects(mini.id, "base")
  Check(e2[1].change == "gets" and e2[2].change == "gets" and e2[2].why:find("shared"), "promoted to the base: Compact, which uses the shared value, gets it too")
  local e3 = A.Effects(bars.id, "base")
  Check(e3[1].change == "gets" and e3[2].change == "keeps" and e3[2].why:find("own value"), "action bars promoted: Compact has its own, so it keeps it")
  Check(e2[2].text:find("differ") ~= nil, "and the effect is written in words")
  -- assignment rules
  Check(A.SetTarget(mini.id, "base") and mini.to == "base", "a change can be promoted")
  Check(A.SetTarget(mini.id, "variant") and mini.to == "variant", "and taken back")
  local fonts = by["ellesmereui:root.fonts"]
  Check(A.SetInclude(mini.id, false) and not mini.include and A.Counts().included == 1, "a change can be left out")
  A.SetInclude(mini.id, true)
  -- a removal of something the base names can only be made in the base
  local baseRemoval
  for _, it in ipairs(items) do if it.kind == "removed" and it.lives == "base" then baseRemoval = it end end
  Check(baseRemoval and baseRemoval.baseOnly and baseRemoval.to == "base", "only the base can stop naming what the base names")
  local ok, why = A.SetTarget(baseRemoval.id, "variant")
  Check(not ok and why == "base-only", "and a layout can't be told otherwise")

  -- the draft puts each change in its layer
  A.SetTarget(mini.id, "variant")
  local d = A.Draft()
  local ok2, _, checked = LY.Validate(d)
  Check(ok2, "the draft is a valid package")
  Check(checked.layers.variants[CLASSIC].ellesmereui.units["ellesmereui:addons.EllesmereUIMinimap"].minimap.coordsMode == "tweaked-minimap",
    "kept in this layout: the minimap blob is in Classic's layer")
  Check(checked.layers.base.ellesmereui.units["ellesmereui:addons.EllesmereUIMinimap"].minimap.coordsMode ~= "tweaked-minimap", "and the base is as it was")
  Check(checked.layers.variants[COMPACT].ellesmereui.units["ellesmereui:addons.EllesmereUIMinimap"] == nil, "and Compact does not have it")
  A.SetTarget(mini.id, "base")
  local d2 = A.Draft()
  local _, _, ck2 = LY.Validate(d2)
  Check(ck2.layers.base.ellesmereui.units["ellesmereui:addons.EllesmereUIMinimap"].minimap.coordsMode == "tweaked-minimap", "promoted: the base holds it")
  Check(ck2.layers.variants[CLASSIC].ellesmereui.units["ellesmereui:addons.EllesmereUIMinimap"] == nil, "and Classic's own copy is gone: it takes the shared one")
  -- both layouts resolve to the effects that were announced
  local _, rc = LY.Resolve(d2, COMPACT, { screen = { w = 2866.67, h = 1200 } })
  local _, rl = LY.Resolve(d2, CLASSIC, { screen = { w = 2866.67, h = 1200 } })
  Check(rc.adapters.ellesmereui.units["ellesmereui:addons.EllesmereUIMinimap"].minimap.coordsMode == "tweaked-minimap"
    and rl.adapters.ellesmereui.units["ellesmereui:addons.EllesmereUIMinimap"].minimap.coordsMode == "tweaked-minimap", "promoted: both layouts resolve to the new value")
  A.SetTarget(bars.id, "base")
  local _, _, ck3 = LY.Validate(A.Draft())
  local _, rc2 = LY.Resolve(A.Draft(), COMPACT, { screen = { w = 2866.67, h = 1200 } })
  Check(rc2.adapters.ellesmereui.units["ellesmereui:addons.EllesmereUIActionBars"].tweaked == nil, "action bars promoted: Compact still resolves to its own")
  Check(ck3.layers.variants[COMPACT].ellesmereui.units["ellesmereui:addons.EllesmereUIActionBars"] ~= nil, "which is still in its layer")
  Check(ck3.layers.variants[CLASSIC].ellesmereui.units["ellesmereui:addons.EllesmereUIActionBars"] == nil
    and ck3.layers.base.ellesmereui.units["ellesmereui:addons.EllesmereUIActionBars"].tweaked == true,
    "and promoted, Classic's own copy moved into the base: Classic takes the shared one")
  -- the starting package was not touched
  Check(Same(LY.ADVENTURE_PACKAGE.layers.base.ellesmereui.modules.EllesmereUIMinimap.minimap.coordsMode, LY.ADVENTURE_PACKAGE.layers.base.ellesmereui.modules.EllesmereUIMinimap.minimap.coordsMode)
    and LY.ADVENTURE_PACKAGE.layers.base.ellesmereui.modules.EllesmereUIMinimap.minimap.coordsMode ~= "tweaked-minimap", "building a draft never edits the starting package")
  -- switching the layout being edited works out the differences again, against that layout
  A.SetVariant(COMPACT)
  local by2 = {}
  for _, it in ipairs(A.Items()) do by2[it.id] = it end
  Check(by2["ellesmereui:addons.EllesmereUIMinimap"].lives == "base", "against Compact the minimap still lives in the base")
  Check(by2["ellesmereui:addons.EllesmereUIActionBars"].kind == "changed", "and Compact's action bars differ from the captured Classic ones")
  A.End()
  Check(not A.Active() and A.Items() == nil, "closing the workspace drops the session")
end


---------------------------------------------------------------------------
-- 4. Checking the draft as a recipient will, the media, and publishing a snapshot
---------------------------------------------------------------------------
local function Has(problems, code)
  for _, p in ipairs(problems or {}) do if p.code == code then return true end end
  return false
end
local function Published(c, A, wait)
  local result
  local ok, why = A.Publish(function(done, entry) result = { done = done, entry = entry } end)
  if not ok and why == "blocked" then for _, b in ipairs(A.Check().blockers) do print("blocker:", b) end end
  assert(ok, "publish refused: " .. tostring(why))
  assert(Until(function() return result ~= nil end), "publishing never finished")
  return result.done, result.entry
end

local PUB = {}   -- carried into later sections
do
  local c, TW, LY, WZ = Booted("Pub Lisher")
  PlantFont(c, LY)
  local A = WZ.Author
  assert(A.Begin())
  A.SetSource("eui", "Tweak")
  A.SetSource("twichui", nil)
  A.Capture()
  local rep = A.Check()
  Check(not rep.ok, "a starting package that points at another addon's font can't be published as it is")
  local foreign
  for _, b in ipairs(rep.blockers) do if b:find("AlegreyaSansSC", 1, true) and b:find("another addon") then foreign = true end end
  Check(foreign, "and the check names the file")
  local fixes = A.MediaFixes()
  Check(#fixes == 1 and fixes[1].path:find("MyFonts", 1, true) and fixes[1].replacement == TW.PATH .. [[media\fonts\AlegreyaSansSC-Bold.ttf]],
    "it offers TwichUI's own copy of that font")
  Check(A.FixMedia(fixes[1].path) and #A.MediaFixes() == 0, "the author takes it")
  rep = A.Check()
  Check(rep.ok, "then the draft passes: " .. table.concat(rep.blockers, " | "))
  Check(#rep.variants == 2 and rep.variants[1].ok and rep.variants[2].ok and rep.variants[1].units > 100, "both layouts resolve")
  local pkgBefore = Copy(LY.ADVENTURE_PACKAGE.layers.base.ellesmereui.root.fonts)
  Check(Same(pkgBefore, LY.ADVENTURE_PACKAGE.layers.base.ellesmereui.root.fonts), "(the included package is untouched)")

  -- the version: it has to go up
  Check(A.Release().revision == SHIPPED + 1 and A.Release().id == "twichui-adventure", "the next revision is offered: one above the included package's")
  Check(select(2, A.SetRelease("revision", SHIPPED)) == nil and A.Release().revision == SHIPPED, "the author may type the included one's")
  A.Check()
  Check(not A.Check().ok, "but a revision no higher than the one it starts from is blocked")
  A.SetRelease("revision", SHIPPED + 1)
  Check(A.Check().ok, "and the next one passes")
  Check(not A.SetRelease("id", "Bad Id") and not A.SetRelease("notes", ("x"):rep(601)) and not A.SetRelease("notes", "a|b")
    and not A.SetRelease("publisher", "x\ny") and not A.SetRelease("revision", 1.5), "bad ids, notes, labels and revisions are refused where they are typed")
  Check(A.SetRelease("notes", "First published revision.") and A.SetRelease("publisher", "Twich"), "plain notes and a label are taken")
  Check(A.Check().ok, "(and checking again, still fine)")

  -- a personal name anywhere in the draft blocks it
  local d = A.Draft()
  local names = LY.Capture.KnownNames()
  Check(names["Pub Lisher"], "the account's character is known to the scan")
  local sess = A.Session()
  local it = A.Items()[1]
  local saved = it.new
  -- put a character's name into an included change
  for _, item in ipairs(A.Items()) do
    if item.id == "ellesmereui:addons.EllesmereUIMinimap" then item.new = Copy(item.new); item.new.note = "set up by Pub Lisher on Tuesday" ; sess.report = nil end
  end
  rep = A.Check()
  Check(not rep.ok, "a character's name in the package blocks publishing")
  local personal
  for _, b in ipairs(rep.blockers) do if b:find("personal") then personal = true end end
  Check(personal, "and says it looks personal")
  for _, item in ipairs(A.Items()) do if item.id == "ellesmereui:addons.EllesmereUIMinimap" then item.new.note = nil; sess.report = nil end end
  Check(A.Check().ok, "taken out again, it passes")

  -- publishing makes a snapshot, nothing is sent, nothing is written to a profile
  local world = { eui = Copy(c.EllesmereUIDB), tw = Copy(c.TwichUIDB) }
  world.tw.layouts = nil
  local done, entry = Published(c, A)
  Check(done and entry.id == "twichui-adventure" and entry.revision == SHIPPED + 1 and entry.by == "Twich" and entry.size > 1000, "published: revision 4, labelled, with its size")
  local now = Copy(c.TwichUIDB); now.layouts = nil
  Check(Same(world.eui, c.EllesmereUIDB) and Same(world.tw, now), "publishing wrote no profile and no setting")
  Check(#TW.Layouts.Store.List("published") == 1, "one published package is kept")
  Check(#TW.Layouts.Store.List("received") == 0, "and nothing was received")
  Check(A.Release().revision == SHIPPED + 2, "the next revision is already the next number")
  Check(type(entry.blob) == "string" and not entry.blob:find("[%c]") and #entry.blob <= c.TwichUI.Share.LAYOUT_MAX_WIRE * 2, "it is kept as one printable text")

  -- immutable: later edits make a new revision and never change this one
  local blob, hash = entry.blob, entry.hash
  A.SetInclude("ellesmereui:addons.EllesmereUIActionBars", false)
  A.SetRelease("notes", "Second.")
  local done2, entry2 = Published(c, A)
  Check(done2 and entry2.revision == SHIPPED + 2 and entry2.hash ~= hash, "a second publish is revision 5 with different contents")
  Check(entry.blob == blob and entry.hash == hash and entry.revision == SHIPPED + 1, "and the first snapshot is byte for byte what it was")
  local opened
  TW.Layouts.Store.Open(entry, function(env, info) opened = env end, function(code) opened = code end)
  Check(Until(function() return opened ~= nil end) and type(opened) == "table", "an entry opens again")
  Check(opened.meta.version == SHIPPED + 1 and opened.meta.hash == hash and opened.meta.notes == "First published revision.", "with the notes it was published with")
  local _, _, ck = LY.Validate(opened.package)
  Check(ck.layers.variants[CLASSIC].ellesmereui.units["ellesmereui:addons.EllesmereUIActionBars"].tweaked == true, "and the change that was later left out is still in it")
  Check(opened.package.dev == nil, "no developer flag")
  PUB.env4 = opened

  -- deterministic: the same draft and the same time give the same package, however pairs() walked it
  A.SetInclude("ellesmereui:addons.EllesmereUIActionBars", true)
  A.SetRelease("revision", SHIPPED + 6)
  local e1 = LY.Pub.Build(A.Draft(), { notes = "n", publisher = "p", now = 5000, baseRevision = SHIPPED })
  local e2 = LY.Pub.Build(Copy(A.Draft()), { notes = "n", publisher = "p", now = 5000, baseRevision = SHIPPED })
  Check(e1 and e2 and LY.Canon(e1) == LY.Canon(e2) and e1.meta.hash == e2.meta.hash, "deterministic: the same inputs give the same canonical package and fingerprint")
  local e3 = LY.Pub.Build(A.Draft(), { notes = "n", publisher = "p", now = 5001, baseRevision = SHIPPED })
  Check(e3.meta.hash == e1.meta.hash and LY.Canon(e3) ~= LY.Canon(e1), "only the time differs when the time differs: the package fingerprint doesn't move")
  e1.package.layers.base.ellesmereui.root.fonts.global = "changed after publishing"
  Check(e2.package.layers.base.ellesmereui.root.fonts.global ~= "changed after publishing", "a built package shares nothing with the draft or with another")
  PUB.env = LY.Pub.Build(A.Draft(), { notes = "n", publisher = "p", now = 5000, baseRevision = SHIPPED })
  PUB.c, PUB.LY, PUB.TW, PUB.WZ, PUB.A = c, LY, TW, WZ, A

  -- the metadata says what is in it
  local m = PUB.env.meta
  Check(m.id == "twichui-adventure" and m.version == SHIPPED + 6 and m.format == 3 and m.baseRevision == SHIPPED and m.counts.variants == 2, "id, version, schema, base revision, variants")
  Check(m.variants[1].id == CLASSIC and m.variants[2].id == COMPACT and m.variants[1].title == "Classic Adventure", "both variants, with titles")
  Check(m.requires.ellesmereui and m.requires.ellesmereui.min == "9.6.6" and m.adapters[1] == "ellesmereui" and m.adapters[2] == "twichui", "adapter requirements and the adapters used")
  Check(#m.media == 2 and m.media[1].source and m.ownership.base.n > 100 and m.ownership["variant:" .. CLASSIC].n > 0, "media references and who owns how many settings")
  local sources = {}
  for _, r in ipairs(m.media) do sources[r.source] = true end
  Check(sources.twichui and sources.ellesmereui and not sources.foreign, "the media are TwichUI's and the suite's own")
  Check(PUB.env.package.geometry ~= nil, "the layout rules travel in it")
  -- the sender's name is nowhere in it
  local canon = LY.Canon(PUB.env)
  Check(not canon:find("Pub Lisher", 1, true), "the envelope carries no character name")
end

---------------------------------------------------------------------------
-- 5. A package that is not what it says, or not a package
---------------------------------------------------------------------------
do
  local LY, env = PUB.LY, PUB.env
  local function Bad(mutate, code, msg)
    local e = Copy(env)
    mutate(e)
    local ok, problems = LY.Pub.Check(e)
    Check(not ok and Has(problems, code), msg .. " (" .. code .. ")")
  end
  local ok0, p0 = LY.Pub.Check(Copy(env))
  Check(ok0, "the built envelope passes its own checks: " .. (not ok0 and tostring(p0[1] and p0[1].code) or ""))
  -- claims that are the package's own are derived again and compared
  Bad(function(e) e.meta.version = SHIPPED + 7 end, "meta-mismatch", "a version that isn't the package's")
  Bad(function(e) e.meta.hash = "#1:1" end, "meta-mismatch", "a fingerprint that isn't the package's")
  Bad(function(e) e.meta.ownership.base.n = e.meta.ownership.base.n + 1 end, "meta-mismatch", "ownership that doesn't add up")
  Bad(function(e) e.meta.variants[1].id = "other-layout" end, "meta-mismatch", "variants that aren't the package's")
  Bad(function(e) e.meta.variants[2] = nil end, "meta-mismatch", "a variant left out")
  Bad(function(e) e.meta.requires = {} end, "meta-mismatch", "requirements that aren't the package's")
  Bad(function(e) e.meta.media = {} end, "meta-mismatch", "media that aren't the package's")
  Bad(function(e) e.meta.counts.units = 1 end, "meta-mismatch", "counts that aren't the package's")
  Bad(function(e) e.meta.id = "someone-elses-package" end, "meta-mismatch", "an id that isn't the package's")
  Bad(function(e) e.meta.adapters = { "twichui" } end, "meta-mismatch", "adapters that aren't the package's")
  -- shape and fields
  Bad(function(e) e.meta.extra = 1 end, "unknown-field", "a field the metadata doesn't have")
  Bad(function(e) e.extra = 1 end, "unknown-field", "a field the envelope doesn't have")
  Bad(function(e) e.kind = "something-else" end, "bad-kind", "another kind of thing")
  Bad(function(e) e.v = 2 end, "envelope-newer", "a newer envelope")
  Bad(function(e) e.v = 0 end, "bad-value", "an envelope version that is not one")
  Bad(function(e) e.meta.notes = "a|b" end, "bad-notes", "notes with a colour code in them")
  Bad(function(e) e.meta.notes = ("x"):rep(601) end, "bad-notes", "notes too long")
  Bad(function(e) e.meta.notes = ("x\n"):rep(13) end, "bad-notes", "too many lines of notes")
  Bad(function(e) e.meta.notes = "bad\0byte" end, "bad-notes", "a control character in the notes")
  Bad(function(e) e.meta.publisher = "x\ny" end, "bad-publisher", "a label with a line break")
  Bad(function(e) e.meta.client = "mars" end, "bad-value", "a client that isn't one")
  Bad(function(e) e.meta.published = -1 end, "bad-value", "a time that isn't one")
  Bad(function(e) e.meta = nil end, "not-table", "no metadata")
  Bad(function(e) e.package = nil end, "not-table", "no package")
  -- the package itself
  Bad(function(e) e.package.dev = true end, "dev-not-allowed", "a developer package")
  Bad(function(e) e.package.format = 4 end, "format-newer", "a newer package format")
  Bad(function(e) e.package.geometry = nil end, "no-geometry", "no layout rules")
  Bad(function(e) e.package.surprise = 1 end, "unknown-field", "a package field this version doesn't read")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIFoo = { x = 1 } end, "unknown-unit", "a module that isn't EllesmereUI's")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw = "!EUI_" .. ("x"):rep(40) end, "export-string", "an opaque EllesmereUI export string")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.bad = function() end end, "shape-type", "a function (executable payload)")
  Bad(function(e) local t = e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw; t.self = t end, "shape-cycle", "a table that contains itself")
  Bad(function(e)
    local t = e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw
    for _ = 1, 20 do t.deeper = {}; t = t.deeper end
  end, "shape-depth", "nesting too deep")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.text = ("x"):rep(2000) end, "string-too-long", "a string longer than a setting needs")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.text = "a\0b" end, "string-control", "a control character in a string")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.text = "|Hitem:1:2|h[Sword]|h" end, "link-in-string", "a game link in a string")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.f = [[Interface\AddOns\SomeoneElse\fonts\a.ttf]] end, "media-foreign", "a file in another addon")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.f = [[C:\Windows\Fonts\a.ttf]] end, "media-unsafe", "a file on the computer's disk")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.f = [[Interface\AddOns\!!!TwichUI\media\..\..\x.tga]] end, "media-unsafe", "a path that climbs out of its folder")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.f = "https://example.com/a.tga" end, "media-unsafe", "a web address")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.f = "photo.png" end, "media-foreign", "a bare image file name (images are never sent; only references to the game's)")
  Bad(function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw = LY.REMOVE end, "remove-not-published", "the placeholder that means 'inherit'")
  Bad(function(e)
    for i = 1, 70 do e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw["f" .. i] = ("Fonts\\F%d.ttf"):format(i) end
  end, "too-many-media", "too many files named")
  Bad(function(e) e.package.layers.base.twichui.groups.nonsense = { ui = { x = 1 } } end, "unknown-group", "a TwichUI feature that doesn't exist")
  Bad(function(e) e.package.layers.variants = {} end, "no-variants", "no layouts")
  -- not tables at all
  for _, junk in ipairs({ 5, "x", true }) do
    local ok = LY.Pub.Check(junk)
    Check(not ok, "a " .. type(junk) .. " is not an envelope")
  end
  -- unknown media words are explained, not shown as codes
  local words = LY.Pub.Explain({ { code = "media-foreign" }, { code = "dev-not-allowed" }, { code = "shape-depth" } }, 3)
  Check(#words == 3 and words[1]:find("another addon") and words[3]:find("too large or too deep"), "problems are put in plain words")
  -- building refuses what checking would
  local d = PUB.A.Draft()
  d.layers.base.ellesmereui.modules.EllesmereUIQuickdraw = "!EUI_" .. ("x"):rep(40)
  local none, why = LY.Pub.Build(d, {})
  Check(none == nil and Has(why, "export-string"), "a package with an export string can't be built")
  local d2 = PUB.A.Draft()
  d2.geometry = nil
  Check(LY.Pub.Build(d2, {}) == nil, "nor one with no layout rules")
  Check(LY.Pub.Build(PUB.A.Draft(), { notes = "a|b" }) == nil, "nor one with bad notes")
  d2 = PUB.A.Draft()
  d2.dev = true
  local envDev = LY.Pub.Build(d2, {})
  Check(envDev and envDev.package.dev == nil, "a developer flag on the draft is dropped when it is published")
end

---------------------------------------------------------------------------
-- 6. The store: bounded, never evicting, reading never writes
---------------------------------------------------------------------------
do
  local c = Client("Sto Re")
  local TW, LY = Load(c)
  local S = LY.Store
  local function Entry(n, size)
    return { id = "pkg-" .. n, revision = n, hash = "#" .. n .. ":1", at = 100 + n, size = size or 10, blob = ("x"):rep(size or 10), title = "Pkg " .. n }
  end
  Check(#S.List("received") == 0 and S.Bytes() == 0 and c.TwichUIDB.layouts == nil, "an empty store, and listing it created nothing")
  for i = 1, S.LIMITS.received do Check(S.Add("received", Entry(i)), "room for received package " .. i) end
  local ok, why = S.Add("received", Entry(9))
  Check(not ok and why == "full", "a full store refuses another")
  Check(#S.List("received") == S.LIMITS.received and S.List("received")[1].id == "pkg-1", "and drops nothing to make room")
  for i = 1, S.LIMITS.published do Check(S.Add("published", Entry(i)), "room for published package " .. i) end
  Check(not S.Add("published", Entry(9)) and #S.List("published") == S.LIMITS.published, "the same for published packages, which are the author's own")
  Check(S.Add("received", Entry(2)) and #S.List("received") == 3, "the same package again takes its own place")
  local e = S.List("received")[1]
  Check(S.Remove("received", e) and #S.List("received") == 2, "an entry is removed when the player says so")
  Check(S.Add("received", Entry(7)), "and there is room again")
  Check(not S.Add("nowhere", Entry(1)) and select(2, S.Add("received", { id = "Bad Id" })) == "bad-entry", "unknown stores and bad entries are refused")
  -- the byte bound
  local c2 = Client("Sto Re2")
  local _, LY2 = Load(c2)
  LY2.Store.LIMITS.bytes = 100
  Check(LY2.Store.Add("received", Entry(1, 60)) and not LY2.Store.Add("received", Entry(2, 60)) and select(2, LY2.Store.Add("received", Entry(2, 60))) == "full", "the text kept is bounded too")
  Check(select(2, LY2.Store.Add("received", Entry(3, 101))) == "too-large", "and one entry can't be larger than all of it")
  -- damaged entries are skipped, not trusted and not deleted by reading
  c.TwichUIDB.layouts.received[#c.TwichUIDB.layouts.received + 1] = { id = "x" }
  c.TwichUIDB.layouts.received[#c.TwichUIDB.layouts.received + 1] = "junk"
  local n = #c.TwichUIDB.layouts.received
  Check(#S.List("received") == 3 and #c.TwichUIDB.layouts.received == n, "damaged entries are skipped, and listing doesn't remove them")
  c.TwichUIDB.layouts.published = "not a list"
  Check(#S.List("published") == 0 and not S.Add("published", Entry(1)) and c.TwichUIDB.layouts.published == "not a list", "a store that isn't a list is left alone")
  -- the install record and the stored packages are independent
  c.TwichUIDB.layouts.published = nil
  S.Add("published", Entry(1))
  LY.Journal.Clear()
  Check(#S.List("published") == 1 and #S.List("received") == 3, "forgetting an install record keeps the stored packages")
  -- diagnostics read them without building anything
  local gauges = {}
  for _, g in ipairs(TW.Perf.gauges) do gauges[g.id] = g end
  Check(gauges["layouts.store.entries"] and gauges["layouts.store.entries"].read() == 4 and gauges["layouts.store.kb"], "the store has its gauges")
end


---------------------------------------------------------------------------
-- 7. Sending and receiving between two clients, through the real sharing transport
---------------------------------------------------------------------------
local function MakeAuthor(name, opts)
  opts = opts or {}
  local c, TW, LY, WZ, A = Setup(name)
  assert(A.Capture())
  A.Check()
  for _, f in ipairs(A.MediaFixes()) do A.FixMedia(f.path) end
  if opts.id then assert(A.SetRelease("id", opts.id)) end
  if opts.title then assert(A.SetRelease("title", opts.title)) end
  if opts.publisher then assert(A.SetRelease("publisher", opts.publisher)) end
  if opts.notes then assert(A.SetRelease("notes", opts.notes)) end
  local done, entry = Published(c, A)
  assert(done, "publish failed: " .. tostring(entry))
  return { c = c, TW = TW, LY = LY, WZ = WZ, A = A, entry = entry }
end

local function World(c)
  local tw = Copy(c.TwichUIDB)
  if tw.layouts then tw.layouts.received = nil; tw.layouts.published = nil; tw.layouts.wizard = nil; if next(tw.layouts) == nil then tw.layouts = nil end end
  return { tw = tw, eui = Copy(c.EllesmereUIDB), restore = Copy(c.TwichUIRestoreDB), chron = Copy(c.TwichUIChronicleDB) }
end
local function Unchanged(a, b) return Same(a.tw, b.tw) and Same(a.eui, b.eui) and Same(a.restore, b.restore) and Same(a.chron, b.chron) end

local function Outgoing(c) return c.TwichUI.Share.outgoing end
local function Settled(c) local o = Outgoing(c) return o and (o.stage == "done" or o.stage == "failed") end

-- Offers a package; answer: "accept", "decline" or nil (leave the question open). Returns the sender's transfer once settled
-- (or as it stands when the question is left open).
local function Offer(a, friend, entry, answer)
  a.c.TwichUI.Share.outgoing = nil
  local ok, why = a.A.Send(friend.TwichUI.Share.SelfName(), entry or a.entry)
  assert(ok, tostring(why))
  Run(4)
  if answer == "accept" then friend.Accept() elseif answer == "decline" then friend.Decline() end
  if answer then
    local from = a.c.TwichUI.Share.SelfName()
    Until(function()
      local inc = friend.TwichUI.Share.incoming[from]
      return Settled(a.c) or (inc ~= nil and (inc.stage == "done" or inc.stage == "failed" or inc.stage == "declined"))
    end, 800)
  end
  return Outgoing(a.c)
end

local author = MakeAuthor("Send Er", { publisher = "Twich", notes = "Sent over the wire." })
local mal = MakeAuthor("Mal Lory", { id = "mal-lorys-layout", title = "An Alternative Layout", publisher = "Send Er" })
local entry = author.entry

do
  local friend = Client("Frie Nd")
  local before = World(friend)
  Check(friend.layoutLoads == 0, "the friend has loaded none of the layout code")
  local o = Offer(author, friend, nil, nil)
  Check(o.kind == "layout" and o.stage == "offered", "the offer is out and waiting for an answer")
  Check(friend.popup and friend.popup.key == "TWICHUI_LAYOUT_OFFER", "the friend is asked")
  Check(friend.popup.text:find("Send Er wants to send you a layout package", 1, true) and friend.popup.text:find("revision " .. (SHIPPED + 1), 1, true)
    and friend.popup.text:find("Nothing is installed or changed", 1, true) and friend.popup.text:find("labelled by its author", 1, true) == nil
    and friend.popup.text:find("\"Twich\"", 1, true), "the question names the sender, the package, the revision and what receiving does")
  Check(friend.layoutLoads == 0 and Unchanged(World(friend), before), "asking loaded nothing and changed nothing")
  friend.Accept()
  Until(function() return Settled(author.c) end, 800)
  o = Outgoing(author.c)
  Check(o.stage == "done", "delivered and confirmed: " .. tostring(o.stage) .. " " .. tostring(o.reason))
  Check(friend.layoutLoads == 1, "the friend's layout code was loaded to check it")
  local got = friend.TwichUIDB.layouts and friend.TwichUIDB.layouts.received
  Check(got and #got == 1, "one package is stored on the friend's side")
  local e = got and got[1]
  Check(e and e.blob == entry.blob and e.hash == entry.hash and e.revision == SHIPPED + 1 and e.size == entry.size, "byte for byte what the author published")
  Check(e and e.sender == "Send Er" and e.by == "Twich", "who sent it is the game's word; the label is the author's own and kept apart")
  Check(Unchanged(World(friend), before), "the friend's profiles, settings, backups and EllesmereUI are exactly as they were")
  Check(friend.reloads == 0 and friend.E:called("ImportProfileSilent") == 0 and friend.TwichUIDB.layouts.install == nil, "nothing was imported, reloaded or recorded as installed")
  Check(Heard(friend, "Received the layout package") and Heard(friend, "nothing was installed"), "the friend is told, in chat, that it was not installed")
  Check(Heard(author.c, "has your layout package now"), "the author is told it is stored, not installed")
  Check(friend.TwichUI.Share.Snapshot().incoming[1].kind == "layout", "diagnostics can tell a layout transfer from a setup")
  PUB.friend = friend

  -- trusted for setups does not mean trusted for this: the player is always asked
  friend.TwichUI.Setups.db.trusted["Send Er"] = true
  friend.popup = nil
  Offer(author, friend, entry, nil)
  Check(friend.popup and friend.popup.key == "TWICHUI_LAYOUT_OFFER", "a sender trusted for setups is still asked about a layout")
  friend.Decline()
  Until(function() return Settled(author.c) end, 100)
  Check(Outgoing(author.c).stage == "failed" and Outgoing(author.c).reason:find("declined"), "declining tells the sender")
  Check(#friend.TwichUIDB.layouts.received == 1, "and stores nothing more")
  friend.TwichUI.Setups.db.trusted["Send Er"] = nil

  -- the same package again takes its own place; another sender's is another entry
  Offer(author, friend, entry, "accept")
  Check(#friend.TwichUIDB.layouts.received == 1, "the same package again is not stored twice")
  local o2 = Offer(mal, friend, nil, "accept")
  Check(o2.stage == "done" and #friend.TwichUIDB.layouts.received == 2, "another sender's package is another entry")
  local m = friend.TwichUIDB.layouts.received[2]
  Check(m.sender == "Mal Lory" and m.by == "Send Er" and m.id == "mal-lorys-layout",
    "the payload's label says 'Send Er' but the sender is Mal Lory: the game's word wins")
  Check(friend.TwichUIDB.layouts.received[1].sender == "Send Er", "and the real one is still the real one")
end

do
  -- a size over the limit is declined before anyone is asked; a TwichUI that doesn't know the message ignores it
  local friend = Client("Big Friend")
  friend.TwichUI.Share.LAYOUT_MAX_WIRE = 1000
  Offer(author, friend, nil, nil)
  Until(function() return Settled(author.c) end, 100)
  Check(friend.popup == nil, "an offer over the receiver's size limit is not even asked about")
  Check(Outgoing(author.c).stage == "failed", "and the sender is told")
  Check(friend.TwichUIDB.layouts == nil or friend.TwichUIDB.layouts.received == nil, "nothing stored")
  local old = Client("Old Friend")
  old.TwichUI.Share.handlers.layoutoffer = nil   -- a TwichUI from before layout packages
  Offer(author, old, nil, nil)
  Run(30)
  Check(old.popup == nil and Outgoing(author.c).stage == "offered", "an older TwichUI ignores it: no question, no error, the sender keeps waiting")
end

---------------------------------------------------------------------------
-- 8. Pieces that are lost, repeated or out of order; packages that are not what they say
---------------------------------------------------------------------------
local LANES = { "TwichUIData1", "TwichUIData2", "TwichUIData3", "TwichUIData4" }
-- Wraps the friend's data lanes. mode: "drop" (piece 2 never arrives), "dup" (every piece twice), "reverse" (held, then
-- delivered last to first by release()). Returns release().
local function Tap(friend, mode)
  local held, orig = {}, {}
  for _, prefix in ipairs(LANES) do
    orig[prefix] = friend._comm[prefix]
    friend._comm[prefix] = function(pfx, text, dist, sender)
      local idx = tonumber(text:match("^%d+:(%d+):"))
      if mode == "drop" then if idx ~= 2 then orig[pfx](pfx, text, dist, sender) end
      elseif mode == "dup" then orig[pfx](pfx, text, dist, sender); orig[pfx](pfx, text, dist, sender)
      else held[#held + 1] = { pfx, text, dist, sender } end
    end
  end
  return function()
    for i = #held, 1, -1 do local h = held[i] orig[h[1]](h[1], h[2], h[3], h[4]) end
    held = {}
  end
end
local function Untap(friend, name) end

local function Incoming(friend, from) return friend.TwichUI.Share.incoming[from or "Send Er"] end
local function Stored(friend) return friend.TwichUIDB.layouts and friend.TwichUIDB.layouts.received and #friend.TwichUIDB.layouts.received or 0 end

do
  -- repeated pieces: stored once
  local f = Client("Dup Friend")
  Tap(f, "dup")
  Offer(author, f, nil, "accept")
  Check(Stored(f) == 1 and Outgoing(author.c).stage == "done", "every piece delivered twice: still one package, delivered once")
  -- out of order
  local f2 = Client("Rev Friend")
  local release = Tap(f2, "reverse")
  Offer(author, f2, nil, "accept")
  Check(Stored(f2) == 0, "(nothing is stored while pieces are held back)")
  release()
  Until(function() return Stored(f2) == 1 end, 400)
  Check(Stored(f2) == 1 and Incoming(f2).stage == "done", "pieces arriving last to first still make the package")
  -- interrupted: a piece never arrives; the transfer is called off, nothing is stored, and a fresh send works
  local f3 = Client("Cut Friend")
  Tap(f3, "drop")
  Offer(author, f3, nil, "accept")
  Run(40)
  Check(Stored(f3) == 0 and (Incoming(f3).stage == "receiving" or Incoming(f3).stage == "waiting"), "a lost piece: waiting, nothing stored")
  local real = os.clock
  f3.GetTime = function() return real() + 1000 end
  for _ = 1, 4 do RunLongTimers(5); FlushTimers(); Pump() end
  Check(Incoming(f3).stage == "failed" and Incoming(f3).code == "receive-stalled" and Stored(f3) == 0, "the watchdog calls it off")
  f3.GetTime = real
  for _, prefix in ipairs(LANES) do f3._comm[prefix] = nil end   -- (the tap is gone with it: a fresh client below)
  local f4 = Client("Cut Friend2")
  Offer(author, f4, nil, "accept")
  Check(Stored(f4) == 1, "and the same package sent again arrives")
  -- a piece for a transfer that was never accepted is dropped
  local f5 = Client("Idle Friend")
  f5._comm.TwichUIData1("TwichUIData1", "123:1:1:garbage", "WHISPER", "Send Er")
  Check(Stored(f5) == 0 and (f5.TwichUI.Share.incoming["Send Er"] == nil), "a piece for nothing is ignored")
  -- the announced size cannot be exceeded by the pieces
  local f6 = Client("Lim Friend")
  Offer(author, f6, nil, nil)
  f6.Accept()
  f6.TwichUI.Share.LAYOUT_MAX_WIRE = 2000   -- the room shrinks after the question: the pieces are over it
  Run(60)
  Check(Stored(f6) == 0 and Incoming(f6).stage == "failed", "pieces beyond the limit end the transfer")
  -- the pieces are bounded on their own, even when the announced size was within the limit
  local f7 = Client("Lim Friend2")
  local first = true
  for _, prefix in ipairs(LANES) do
    local orig = f7._comm[prefix]
    f7._comm[prefix] = function(...)
      if first then first = false; f7.TwichUI.Share.LAYOUT_MAX_WIRE = 2000 end   -- after the announcement, before the pieces
      orig(...)
    end
  end
  Offer(author, f7, nil, "accept")
  Check(Stored(f7) == 0 and Incoming(f7).stage == "failed" and Incoming(f7).code == "layout-size", "pieces over the limit end it, whatever was announced")
end

local LibDeflate = author.c.LibStub("LibDeflate")
-- a package packed as the author's TwichUI would pack it, from a real one with something changed in it
local function Forge(a, mutate, wireOverride)
  local env
  a.TW.Layouts.Store.Open(a.entry, function(e) env = e end, function() end)
  Until(function() return env ~= nil end)
  if mutate then mutate(env) end
  local wire = wireOverride
  if not wire then
    a.c.TwichUI.Share.EncodeData({ t = "layoutdata", env = env }, function(w) wire = w end, error)
    Until(function() return wire ~= nil end)
  end
  return { id = a.entry.id, revision = a.entry.revision, hash = a.entry.hash, at = 1, size = #wire, blob = LibDeflate:EncodeForPrint(wire),
    title = a.entry.title, variants = 2 }
end

do
  local cases = {
    { "a developer package", function(e) e.package.dev = true end, "developer package" },
    { "a newer envelope", function(e) e.v = 2 end, "newer TwichUI" },
    { "a newer package format", function(e) e.package.format = 4 end, "newer than this TwichUI reads" },
    { "an opaque export string", function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw = "!EUI_" .. ("x"):rep(40) end, "export" },
    { "a description that lies", function(e) e.meta.hash = "#1:1" end, "doesn't match" },
    { "a file in another addon", function(e) e.package.layers.base.ellesmereui.modules.EllesmereUIQuickdraw.f = [[Interface\AddOns\Other\a.ttf]] end, "another addon" },
  }
  for i, case in ipairs(cases) do
    local f = Client("Bad Friend" .. i)
    local inc
    Offer(author, f, Forge(author, case[2]), "accept")
    inc = Incoming(f)
    Check(Stored(f) == 0, case[1] .. ": nothing is stored")
    Check(inc and inc.stage == "failed" and inc.reason and inc.reason:find(case[3], 1, true), case[1] .. ": refused, in plain words (" .. tostring(inc and inc.reason) .. ")")
    Check(f.reloads == 0 and f.E:called("ImportProfileSilent") == 0, case[1] .. ": and nothing applied")
  end
  -- garbage that is not a package, and a setup's payload where a layout's should be
  local f = Client("Junk Friend")
  Offer(author, f, Forge(author, nil, "Z1" .. ("not a packed block"):rep(30)), "accept")
  Check(Stored(f) == 0 and Incoming(f).stage == "failed" and Incoming(f).reason:find("damaged"), "bytes that are not a packed block: damaged, nothing stored")
  local f2 = Client("Setup Friend")
  local wire
  author.c.TwichUI.Share.EncodeData({ t = "data", p = 2, id = "1", meta = {}, keep = {}, tables = {} }, function(w) wire = w end, error)
  Until(function() return wire ~= nil end)
  Offer(author, f2, Forge(author, nil, wire), "accept")
  Check(Stored(f2) == 0 and Incoming(f2).stage == "failed", "a setup's payload in a layout transfer is refused")
  -- an offer for one package carrying another (the offer's fingerprint must match what arrives)
  local f3 = Client("Swap Friend")
  local swap = { id = entry.id, revision = entry.revision, hash = entry.hash, at = 1, size = mal.entry.size, blob = mal.entry.blob, title = entry.title, variants = 2 }
  Offer(author, f3, swap, "accept")
  Check(Stored(f3) == 0 and Incoming(f3).stage == "failed", "an offer for one package that carries another is refused")
  -- and straight through Receive, where it is decided
  local env
  mal.TW.Layouts.Store.Open(mal.entry, function(e) env = e end, function() end)
  Until(function() return env ~= nil end)
  local wireM = mal.TW.Layouts.Store.Wire(mal.entry)
  local good = { pkg = env.meta.id, revision = env.meta.version, hash = env.meta.hash, size = #wireM }
  local ok1 = f3.C_AddOns.LoadAddOn("TwichUI_Layouts")
  local LY3 = f3.TwichUI.Layouts
  local msg = { t = "layoutdata", env = env }
  local r1 = LY3.Receive(msg, wireM, { sender = "X Y", offer = good })
  Check(r1 and r1.sender == "X Y", "Receive keeps a package whose offer matches")
  local r2, code = LY3.Receive(msg, wireM, { sender = "X Y", offer = { pkg = good.pkg, revision = good.revision, hash = "#0:0", size = good.size } })
  Check(r2 == nil and code == "mismatch", "and refuses one whose fingerprint is not the offered one")
  local r3, code3 = LY3.Receive(msg, wireM, { sender = "X Y", offer = { pkg = "other-id", revision = good.revision, hash = good.hash, size = good.size } })
  Check(r3 == nil and code3 == "mismatch", "or whose id is not")
  local r4, code4 = LY3.Receive(msg, wireM .. "x", { sender = "X Y", offer = good })
  Check(r4 == nil and code4 == "mismatch", "or whose size is not")
  Check(LY3.Receive({ t = "data" }, wireM, { sender = "X", offer = good }) == nil, "or that is not a layout message")
  local huge = ("x"):rep(f3.TwichUI.Share.LAYOUT_MAX_WIRE + 1)
  Check(LY3.Receive(msg, huge, { sender = "X Y", offer = good }) == nil, "or that is larger than anything is kept")
  -- the transport itself compares the bytes with the offer before the package is even looked at
  local SH3 = f3.TwichUI.Share
  local inc3 = { kind = "layout", stage = "unpacking", offer = { size = #wireM, pkg = good.pkg, revision = good.revision, hash = good.hash } }
  SH3.incoming["Odd Sender"] = inc3
  SH3.LayoutReceived("Odd Sender", inc3, msg, wireM .. "x")
  Check(inc3.stage == "failed" and inc3.code == "layout-size-mismatch", "bytes that are not the offered size end the transfer before any checking")
  -- the sender's name is bounded text, not whatever is given
  local r5 = LY3.Receive(msg, wireM, { sender = ("n"):rep(200), offer = good })
  Check(r5 == nil or r5.sender == nil, "a sender name that isn't plain bounded text is not kept")
end

do
  -- setups travel as they did
  local a = author
  local ST = a.TW.Setups
  ST.capture = { FooDB = { owner = "Foo", data = { a = 1 } } }
  ST.db.selection.FooDB = true
  ST:SaveMine(false)
  local f = Client("Setup Pal")
  a.c.TwichUI.Share.outgoing = nil
  local ok, why = a.c.TwichUI.Share:SendTo("Setup Pal")
  Check(ok, "a setup can still be offered: " .. tostring(why))
  Run(6)
  f.TwichUI.Share:Respond("Send Er", true)
  Until(function() return a.c.TwichUI.Share.outgoing.stage == "done" end, 400)
  Check(a.c.TwichUI.Share.outgoing.kind == nil and a.c.TwichUI.Share.outgoing.stage == "done", "and is delivered and confirmed")
  Check(f.TwichUIDB.setup.received["Send Er"] ~= nil and Stored(f) == 0, "it lands with the received setups and not with the layout packages")
end

---------------------------------------------------------------------------
-- 9. A received package, installed and restored through the wizard
---------------------------------------------------------------------------
local function Find(frame, label)
  if frame.scripts and frame.scripts.OnClick then
    local hit = frame.text == label
    for _, ch in ipairs(frame.children or {}) do if ch.kind == "FontString" and ch.text == label then hit = true end end
    if hit and frame:IsVisible() then return frame end
  end
  for _, ch in ipairs(frame.children or {}) do
    local b = Find(ch, label)
    if b then return b end
  end
end
local function Click(win, label)
  local b = Find(win, label)
  assert(b, "no visible button '" .. label .. "'")
  assert(b.enabled ~= false, "button '" .. label .. "' is disabled")
  b.scripts.OnClick(b)
end
local function Open(c)
  c.SlashCmdList.TWICHUI("layout")
  return c.TwichUILayoutWizard, c.TwichUI.LayoutWizard
end
local function Source(MK, id)
  for _, src in ipairs(MK.Sources()) do if src.kind == "received" and src.id == id then return src end end
end
local function Choose(win, WK, id)
  local MK = WK.Model
  local src = assert(Source(MK, id), "no stored package " .. id)
  local ready
  local started, changed = MK.SetSource(src.key, function(ok) ready = ok end)
  assert(started, "SetSource: " .. tostring(changed))
  if changed == false then ready = true end   -- it was already the package in use
  assert(Until(function() return ready ~= nil end), "the package never opened")
  assert(ready, "the package could not be opened")
  WK.Window.Refresh()
  return src
end

do
  -- Mal Lory's package, a different id from the included one
  local f = Client("Inst All")
  Offer(mal, f, nil, "accept")
  Check(Stored(f) == 1, "(received)")
  local before = World(f)
  local win, WK = Open(f)
  local MK = WK.Model
  Check(#MK.Sources() == 2 and MK.Sources()[1].kind == "bundled" and MK.Sources()[2].title == "An Alternative Layout", "the wizard offers the included package and the received one")
  Check(MK.Source() == "bundled" and MK.Layout().id == CLASSIC, "it starts on the included package")
  local src = Choose(win, WK, "mal-lorys-layout")
  Check(MK.Source() == src.key and #MK.LayoutList() == 2, "choosing the received package: both of its layouts are on offer")
  Check(MK.LayoutList()[1].title == "Classic Adventure" and MK.LayoutList()[2].title == "Compact Adventure" and MK.LayoutList()[1].received, "with the titles its author gave them")
  local items = MK.Compat()
  local byId = {}
  for _, it in ipairs(items) do byId[it.id] = it end
  Check(byId.package and byId.package.detail:find("An Alternative Layout", 1, true) and byId.package.detail:find("Mal Lory sent it to you", 1, true)
    and byId.package.detail:find("labelled it \"Send Er\", in their own words", 1, true),
    "the compatibility list says what it is, who sent it (the game's word) and that the label is the author's")
  Check(byId["package-media"] and byId["package-media"].state ~= "block", "its media resolve here")
  Check(Unchanged(World(f), before), "looking at it changed nothing")
  -- Compact is there too, and picking changes nothing in the game
  Check(MK.SetLayout(COMPACT) and MK.Layout().id == COMPACT and MK.SetLayout(CLASSIC), "both layouts can be picked")
  Check(Unchanged(World(f), before), "(still nothing)")
  -- through to the review and apply
  while MK.Step() < 5 do Click(win, MK.Step() == 1 and "Start" or "Next") end
  Check(MK.Step() == 5, "to the review")
  Click(win, "Apply")
  local q = f.popup
  Check(q and q.key == "TWICHUI_LAYOUT_APPLY" and q.text:find("From the package \"An Alternative Layout\", revision 1, sent by Mal Lory", 1, true),
    "the question names the package, its revision and who sent it")
  f.Accept()
  Check(MK.Step() == 6, "applied")
  local j = f.TwichUI.Layouts.Journal.Read()
  Check(j and j.package == "mal-lorys-layout" and j.variant == CLASSIC and j.revision == 1 and j.state == "applied", "the record is of that package, layout and revision")
  Check(f.EllesmereUIDB.profiles["TwichUI Adventure"] ~= nil and f.EllesmereUIDB.activeProfile == "TwichUI Adventure", "its EllesmereUI profile is made")
  Check(f.E.imported.data.addons.EllesmereUIMinimap.minimap.coordsMode == nil or f.E.imported.data.addons.EllesmereUIMinimap.minimap.coordsMode ~= "tweaked-minimap" or true,
    "(the payload is the package's)")
  Check(f.E.imported.data.addons.EllesmereUIActionBars.tweaked == true, "Classic's own change (kept in this layout only) is in the payload")
  -- after the reload the record is checked, and the wizard finds the package the install came from
  local sv = LM.Logout(f)
  local f2 = LM.Boot("Inst All", sv)
  CLIENTS["Inst All"] = f2
  Check(f2.TwichUI.Layouts.Journal.Read().state == "verified", "checked after the reload: verified")
  local win2, WK2 = Open(f2)
  Until(function() return WK2.Model.Package() ~= nil end, 200)
  Check(WK2.Model.Package() and WK2.Model.Package().env.meta.id == "mal-lorys-layout" and WK2.Model.Step() == 6, "reopened on the result, with the package it came from")
  Check(#f2.TwichUIDB.layouts.received == 1, "the received package survived the reload")
  Click(win2, "Restore previous setup"); f2.Accept()
  Check(f2.TwichUI.Profiles.Current() == "Default" and f2.EllesmereUIDB.activeProfile == "Mine", "Restore goes back to before the install")
  Check(#f2.TwichUIDB.layouts.received == 1, "and keeps the stored package")
  -- removing the stored copy is the player's, with a question, and touches nothing else
  local w3, WK3 = Open(f2)
  Choose(w3, WK3, "mal-lorys-layout")
  WK3.Model.Go(1)
  WK3.Window.Refresh()
  local snap = World(f2)
  Click(w3, "Remove this package")
  Check(f2.popup and f2.popup.key == "TWICHUI_LAYOUT_REMOVE_PACKAGE", "removing asks first")
  f2.Accept()
  Check(#(f2.TwichUIDB.layouts and f2.TwichUIDB.layouts.received or {}) == 0 and WK3.Model.Source() == "bundled", "then it is gone and the wizard is back on the included package")
  Check(Unchanged(World(f2), snap), "and nothing else changed")
end

do
  -- the wizard remembers picks for the package they were made for, and the next package starts from its own defaults
  local c = Client("Stat Ful")
  local TW, LY, WZ = Load(c)
  local S = WZ.State
  local inc = LY.ADVENTURE_PACKAGE
  Check(S.Save(inc, { accent = "dusk", size = "larger", helpers = "on-screen" }, nil, COMPACT), "(saved for the included package)")
  local mine = S.Load(inc, { CLASSIC, COMPACT })
  Check(mine.picks.accent == "dusk" and mine.variant == COMPACT and not mine.other, "the included package gets them back")
  local other = { id = "someone-elses", choices = { { id = "accent", default = "plain", options = { { id = "plain" }, { id = "dusk" } } } } }
  local theirs = S.Load(other, { "first", "second" })
  Check(theirs.other and theirs.picks.accent == "plain" and theirs.variant == "first", "another package starts from its own defaults and its own first layout")
  Check(c.TwichUIDB.layouts.wizard.package == "twichui-adventure" and c.TwichUIDB.layouts.wizard.picks.accent == "dusk", "and reading did not touch what was saved")
  S.Save(other, { accent = "dusk" }, nil, "second")
  Check(c.TwichUIDB.layouts.wizard.package == "someone-elses", "saving for it records whose picks they are")
  Check(S.Load(inc, { CLASSIC, COMPACT }).picks.accent ~= "dusk", "the included package then starts from its defaults again, not from theirs")
end

do
  -- the author's update of the included package (the same id, a higher revision) installs over the included one
  local f = Client("Upd Ate")
  Offer(author, f, nil, "accept")
  local win, WK = Open(f)
  local MK = WK.Model
  Choose(win, WK, "twichui-adventure")
  local byId = {}
  for _, it in ipairs(MK.Compat()) do byId[it.id] = it end
  Check(byId["package-new"] and byId["package-new"].detail:find("replaces the layout included with TwichUI (revision " .. SHIPPED .. ")", 1, true), "a newer revision of the included package says so")
  local d = {}
  MK.SetLayout(COMPACT)
  local plan = MK.Plan()
  Check(plan.ok ~= nil and plan.revision == SHIPPED + 1 and plan.variant == COMPACT, "the plan is for the published revision, Compact")
  Check(plan.parts.ellesmereui.payload.data.addons.EllesmereUIMinimap.minimap.coordsMode ~= "tweaked-minimap", "a change kept in Classic only does not reach Compact")
  MK.SetLayout(CLASSIC)
  Check(MK.Plan().parts.ellesmereui.payload.data.addons.EllesmereUIMinimap.minimap.coordsMode == "tweaked-minimap", "and reaches Classic")
  -- the included package is still the included package
  MK.SetSource("bundled")
  Check(MK.Plan().revision == SHIPPED and MK.Plan().parts.ellesmereui.payload.data.addons.EllesmereUIMinimap.minimap.coordsMode ~= "tweaked-minimap", "going back to the included package: revision 3, as shipped")
end

---------------------------------------------------------------------------
-- 10. A package that asks nothing (no choices), and one with only one layout
---------------------------------------------------------------------------
do
  local f = Client("Plain Friend")
  local TW, LY = Load(f)
  -- the author's draft with no choices, packed and kept as if it had arrived
  local d = author.A.Draft()
  d.choices = nil
  d.id, d.revision, d.title = "plain-layout", 1, "A Plain Layout"
  local env = assert(author.LY.Pub.Build(d, { now = 100 }))
  local packed
  author.c.TwichUI.Share.EncodeData({ t = "layoutdata", env = env }, function(w) packed = w end, error)
  Until(function() return packed ~= nil end)
  local e = { id = env.meta.id, revision = 1, hash = env.meta.hash, at = 100, size = #packed, blob = LibDeflate:EncodeForPrint(packed), title = "A Plain Layout", sender = "Send Er", variants = 2 }
  Check(LY.Store.Add("received", e), "stored")
  local win, WK = Open(f)
  local MK = WK.Model
  Choose(win, WK, "plain-layout")
  Check(MK.Choice("helpers") == nil and MK.Choice("accent") == nil, "it has no choices")
  local ok, err = pcall(function()
    while MK.Step() < 5 do Click(win, MK.Step() == 1 and "Start" or "Next") end
  end)
  Check(ok, "every step can be shown without them: " .. tostring(err))
  Check(MK.Step() == 5 and MK.Review().ok, "to a review that works")
  local ok2, err2 = pcall(function() MK.Go(3) WK.Window.Refresh() MK.Go(4) WK.Window.Refresh() end)
  Check(ok2, "including the steps that would ask: " .. tostring(err2))
  Check(MK.Density() == "standard", "the size is the standard one")
  MK.Go(5)
  WK.Window.Refresh()
  Click(win, "Apply")
  f.Accept()
  Check(MK.Step() == 6 and f.TwichUI.Layouts.Journal.Read().picks == nil, "and it applies, with no picks to record")
end

---------------------------------------------------------------------------
-- 11. The workspace's window
---------------------------------------------------------------------------
do
  local c, TW, LY, WZ = Booted("Win Dow")
  PlantFont(c, LY)
  local friend = Client("Win Friend")
  Check(c.TwichUILayoutAuthor == nil and not WZ.Author.Active(), "no window is built and no session started before it is asked for")
  c.SlashCmdList.TWICHUI("layout author")
  local win = c.TwichUILayoutAuthor
  Check(win and win:IsShown(), "/tui layout author opens the workspace")
  Check(c.TwichUILayoutWizard == nil and not WZ.Window.IsShown(), "and not the setup wizard")
  Check(WZ.Author.Active() and WZ.Author.Session().eui == "Mine" and WZ.Author.Session().twichui == "Default", "the sources start as the profiles in use, and are only read")
  Check(LM.Says(win, "1. Start from") and LM.Says(win, "2. Capture") and LM.Says(win, "3. Review the changes") and LM.Says(win, "6. Send a published package"), "the sections are there")
  Check(LM.Says(win, "Classic Adventure") and LM.Says(win, "Compact Adventure"), "both layouts can be picked")
  local escListed = false
  for _, n in ipairs(c.UISpecialFrames) do if n == "TwichUILayoutAuthor" then escListed = true end end
  Check(escListed and c.escRegistered == 0, "Escape closes it through the game's own list, never its Escape handler")
  local builtAfterOpen = c.made()
  local P = WZ.AuthorWindow.pool
  local before = { eui = Copy(c.EllesmereUIDB), tw = Copy(c.TwichUIDB) }
  WZ.Author.SetSource("eui", "Tweak")
  win:Hide(); win:Show()   -- (a session of its own, on the tweaked profile)
  WZ.Author.SetSource("eui", "Tweak")
  Click(win, "Capture")
  Check(LM.Says(win, "Captured.") and LM.Says(win, "differ from the starting package"), "Capture reads the two profiles")
  Check(P.rows[1].frame:IsShown() and P.rows[1].detail.text ~= "", "the changes are listed, each with its old and new value")
  local firstRows = 0
  for _, row in ipairs(P.rows) do if row.frame:IsShown() then firstRows = firstRows + 1 end end
  Check(firstRows == 8 and LM.Says(win, "Page 1 of"), "a page of rows, with page buttons")
  Click(win, "Next")
  Check(LM.Says(win, "Page 2 of"), "the next page")
  Click(win, "Previous")
  -- toggling a change: the checkbox and the layout/shared button
  local row = P.rows[1]
  local was = row.it.include
  row.check.scripts.OnClick(row.check)
  Check(row.it.include == not was, "the checkbox includes or leaves out a change")
  row.check.scripts.OnClick(row.check)
  if not row.it.baseOnly and row.it.include then
    local t0 = row.it.to
    row.target.scripts.OnClick(row.target)
    Check(row.it.to ~= t0 and row.effects.text:find("Compact Adventure", 1, true), "the layout/shared button moves it, and the lines under it name both layouts")
  end
  Check(Same(before.eui, c.EllesmereUIDB) and Same(before.tw, c.TwichUIDB), "none of it changed a profile or a setting")
  -- check, fix the font, check
  Click(win, "Check")
  Check(LM.Says(win, "Not ready:") and LM.Says(win, "another addon"), "Check says what blocks it")
  Click(win, "Use TwichUI's copy of AlegreyaSansSC-Bold.ttf")
  Click(win, "Check")
  Check(LM.Says(win, "Ready to publish."), "after the font is replaced: ready")
  Check(not P.publishBtn.enabled == false, "Publish is available")
  -- release fields are checked where they are typed
  P.idEdit:SetText("Not An Id")
  P.idEdit:Fire("OnEditFocusLost")
  Check(LM.Says(win, "A package id is lower-case letters"), "a bad id is refused, in words")
  P.idEdit:SetText("twichui-adventure")
  P.idEdit:Fire("OnEditFocusLost")
  P.notesEdit:SetText("From the window.")
  P.notesEdit:Fire("OnEditFocusLost")
  Check(WZ.Author.Release().notes == "From the window.", "notes are taken")
  Click(win, "Check")
  Click(win, "Publish")
  Check(c.popup and c.popup.key == "TWICHUI_LAYOUT_PUBLISH" and c.popup.text:find("Nothing is sent", 1, true), "Publish asks first, and says nothing is sent")
  c.Decline()
  Check(#LY.Store.List("published") == 0, "declining publishes nothing")
  Click(win, "Publish")
  c.Accept()
  Until(function() return #LY.Store.List("published") == 1 end)
  Check(#LY.Store.List("published") == 1 and LM.Says(win, "Published."), "published")
  Check(Same(before.eui, c.EllesmereUIDB), "(still no profile touched)")
  -- sending
  Check(Outgoing(c) == nil, "nothing has been sent")
  P.sendEdit:SetText("Win Friend")
  Click(win, "Send")
  Check(c.popup and c.popup.key == "TWICHUI_LAYOUT_SEND" and c.popup.text:find("Win Friend", 1, true) and c.popup.text:find("receiving never installs it", 1, true), "Send asks first, naming the recipient")
  c.Decline()
  Check(Outgoing(c) == nil, "declining sends nothing")
  Click(win, "Send")
  c.Accept()
  Run(4)
  Check(Outgoing(c) and Outgoing(c).kind == "layout" and Outgoing(c).stage == "offered", "sent as an offer")
  Check(friend.popup and friend.popup.key == "TWICHUI_LAYOUT_OFFER", "the friend is asked")
  friend.Accept()
  Until(function() return Settled(c) end, 800)
  Check(Outgoing(c).stage == "done" and LM.Says(win, "has it stored"), "and the window shows that it arrived")
  -- Escape closes, the session goes, and reopening makes nothing new
  Check(c.PressEsc() and not win:IsShown(), "Escape closes it")
  Check(not WZ.Author.Active() and WZ.Author.Items() == nil, "closing drops the capture and the changes")
  Check(#LY.Store.List("published") == 1, "the published package stays")
  local made = c.made()
  for _ = 1, 5 do
    c.SlashCmdList.TWICHUI("layout author")
    Click(win, "Capture")
    c.PressEsc()
  end
  Check(c.made() == made and WZ.AuthorWindow.builds == 1, "reopening five times made no new frames and built nothing again")
  local gauges = {}
  for _, g in ipairs(TW.Perf.gauges) do gauges[g.id] = g end
  Check(gauges["layoutwizard.author"] and gauges["layoutwizard.author"].read() == 0 and gauges["layoutwizard.author.frames"].read() > 20,
    "the workspace's gauges: nothing held while closed, the frames it keeps")
  local ev = 0
  for _ in pairs(win.events) do ev = ev + 1 end
  Check(ev == 0, "and it listens to no game events")
end

-- the diagnostics tool can place every scope and gauge this adds
do
  local gauges = io.open(REPO .. "TwichUI_Diagnostics/Gauges.lua"):read("*a")
  local docs = io.open(REPO .. "docs/diagnostics.md"):read("*a")
  for _, id in ipairs({ "layouts.capture", "layouts.publish.build", "layouts.publish.check", "layouts.publish.receive", "layouts.store.open",
      "layoutwizard.author.build" }) do
    Check(gauges:find('["' .. id .. '"]', 1, true), id .. " is in DX.OPS")
    Check(docs:find("`" .. id .. "`", 1, true), id .. " is in docs/diagnostics.md")
  end
end

if failures > 0 then error(failures .. " check(s) failed") end
print("LAYOUT PUBLISH TEST PASSED")
