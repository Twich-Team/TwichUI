dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- The authoring workspace's review table (docs/layouts/publishing.md, "Review the changes"): friendly names and ids, a stable order,
-- inclusion apart from selection, filters/sort/pages, impact worked out with the real composer (and checked against LY.Resolve),
-- values before and after, attention flags with evidence, reviewed marks, bulk scope, and the window built from the real builders.
-- Nothing here is the game: the in-game checks are listed in docs/layouts/publishing.md.

META = { EllesmereUI = { Version = "9.6.8" } }

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same = LM.Copy, LM.Same

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


local function Setup(name)
  local c, TW, LY, WZ = Booted(name)
  local A = WZ.Author
  assert(A.Begin())
  A.SetSource("eui", "Tweak")
  A.SetSource("twichui", nil)
  assert(A.Capture())
  return c, TW, LY, WZ, A, WZ.AuthorReview
end
local function ById(A) local by = {} for _, it in ipairs(A.Items()) do by[it.id] = it end return by end
local MINI, BARS, QUICK, DARK = "ellesmereui:addons.EllesmereUIMinimap", "ellesmereui:addons.EllesmereUIActionBars",
  "ellesmereui:addons.EllesmereUIQuickdraw", "ellesmereui:root.darkMode"

---------------------------------------------------------------------------
-- 1. Names, ids, order, inclusion apart from selection
---------------------------------------------------------------------------
do
  local c, TW, LY, WZ, A, RV = Setup("Rev Iew")
  local before = { eui = Copy(c.EllesmereUIDB), tw = Copy(c.TwichUIDB) }
  local by = ById(A)
  Check(RV.Name(by[MINI]) == "Minimap" and RV.Name(by[BARS]) == "Action bars" and RV.Name(by[QUICK]) == "Quickdraw", "modules get friendly names")
  Check(RV.Tech(by[BARS]) == BARS, "and keep the canonical id for the tooltip and the details")
  Check(RV.Humanize("fontSize") == "Font size" and RV.Humanize("showUI2") == "Show ui 2", "setting keys read as words")
  Check(RV.Details(by[BARS]) == "1 field" and RV.Details(by[QUICK]):find("fields"), "details are counted in fields")
  Check(RV.KIND_LABEL.removed == "Removed" and by[QUICK].kind == "removed", "change types are words")

  -- the default order: included first, left-out last; the same every time
  local function Order() local ids = {} for _, it in ipairs(RV.Page().rows) do ids[#ids + 1] = it.id end return ids end
  local o1 = Order()
  A.SetInclude(MINI, false); A.SetInclude(MINI, true)
  Check(Same(o1, Order()), "the order is deterministic")
  Check(o1[#o1] == DARK or o1[#o1] == QUICK, "left-out changes are last by default")
  Check(RV.SummaryText() == "4 changes · 2 included · 0 need review · 0 blocked", "the summary: " .. RV.SummaryText())

  -- including is not selecting; selecting is not including; neither reorders the table
  RV.Select(BARS)
  A.SetInclude(BARS, false)
  Check(RV.Selected() == by[BARS] and not by[BARS].include, "leaving a change out keeps it selected")
  Check(Same(o1, Order()), "and does not reorder the table")
  A.SetInclude(BARS, true)
  RV.Select(nil)
  Check(by[BARS].include and RV.Selected() == nil, "closing the details does not change inclusion")
  Check(not RV.Select("no-such-id"), "an id that is not there cannot be selected")

  -- filters: counts, zero results, clearing
  RV.SetFilter("status", "excluded")
  local pg = RV.Page()
  Check(pg.total == 2 and #pg.rows == 2 and RV.Filtered(), "Excluded lists the two left out")
  Check(RV.Counts().changes == 4 and RV.Counts().shown == 2, "the summary counts everything, the view counts what it lists")
  RV.SetFilter("status", "all"); RV.SetFilter("kind", "removed")
  Check(RV.Page().total == 2, "Removed lists the two removals")
  RV.SetFilter("kind", "all"); RV.SetFilter("search", "  QUICK ")
  Check(RV.Page().total == 1 and RV.Page().rows[1].id == QUICK, "search finds by name or id, ignoring case and spaces")
  RV.SetFilter("search", "zzzz")
  pg = RV.Page()
  Check(pg.total == 0 and pg.from == 0 and pg.pages == 1 and #pg.rows == 0, "a search with no match is an empty page, not an error")
  RV.ClearFilters()
  Check(not RV.Filtered() and RV.Page().total == 4, "Clear filters shows everything")
  RV.SetFilter("layout", COMPACT)
  Check(RV.Page().total == 2, "the layout filter lists what really changes Compact: " .. RV.Page().total)
  RV.ClearFilters()
  RV.SetFilter("sort", "name")
  local names = {}
  for _, it in ipairs(RV.Page().rows) do names[#names + 1] = RV.Name(it):lower() end
  local sorted = Copy(names); table.sort(sorted)
  Check(Same(names, sorted), "sorting by name sorts by name")
  RV.SetFilter("sort", "details")
  local r = RV.Page().rows
  Check(r[1].n.total >= r[#r].n.total, "sorting by details puts the most fields first")
  RV.SetFilter("sort", "attention")

  -- paging is clamped and keeps state
  RV.SetPageSize(10); RV.SetPage(99)
  Check(RV.Page().page == 1, "a page past the end is clamped")
  Check(not RV.SetPageSize(7), "only the supported page sizes are accepted")
  A.SetInclude(MINI, false); RV.SetPage(1); RV.SetPageSize(15); RV.SetPageSize(10)
  Check(not by[MINI].include, "inclusion survives paging, sorting and filtering")
  Check(Same(before.eui, c.EllesmereUIDB) and Same(before.tw, c.TwichUIDB), "none of it touched a profile")
end

---------------------------------------------------------------------------
-- 2. Impact: the composer's answer, checked against LY.Resolve on the real draft
---------------------------------------------------------------------------
do
  local c, TW, LY, WZ, A, RV = Setup("Imp Act")
  local s = A.Session()
  local by = ById(A)
  local canvas = LY.ADVENTURE_PACKAGE.geometry.canvas
  local function Units(pkg, variant, id)
    local ok, res = LY.Resolve(pkg, variant, { screen = { w = canvas.w, h = canvas.h } })
    assert(ok, "the draft resolves")
    local adapter = by[id].adapter
    return res.adapters[adapter] and res.adapters[adapter].units[id]
  end
  local base = LY.ADVENTURE_PACKAGE
  local agreed, total = 0, 0
  for _, id in ipairs({ MINI, BARS, QUICK }) do
    local it = by[id]
    for _, to in ipairs({ "variant", "base" }) do
      if not (to == "variant" and it.baseOnly) then
        for _, other in ipairs(s.items) do other.include = false end
        it.include, it.to = true, to
        local draft = A.Draft(true)
        local impact = RV.Impact(it, to)
        for _, e in ipairs(impact.byVariant) do
          local changed = not Same(Units(base, e.variant, id), Units(draft, e.variant, id))
          total = total + 1
          if changed == e.changes then agreed = agreed + 1
          else print(("  disagree: %s -> %s, %s: composer says %s, resolver says %s"):format(id, to, e.variant, tostring(e.changes), tostring(changed))) end
        end
      end
    end
  end
  Check(total >= 8 and agreed == total, ("the impact agrees with LY.Resolve for every layout (%d of %d)"):format(agreed, total))
  for _, other in ipairs(s.items) do other.include = other.kind ~= "removed" and other.kind ~= "default" end
  by[MINI].to, by[BARS].to = "variant", "variant"

  -- a variant override stops a shared change from reaching that layout
  local bars = by[BARS]
  local shared = RV.Impact(bars, "base")
  local compact
  for _, e in ipairs(shared.byVariant) do if e.variant == COMPACT then compact = e end end
  Check(compact and not compact.changes and compact.note:find("own value wins", 1, true), "Compact keeps its own action bars: " .. tostring(compact and compact.note))
  Check(shared.text == "Classic" and RV.Impact(bars, "variant").text == "Classic", "so sharing them still affects Classic only")
  -- a minimap value that lives in the base reaches Compact only when shared
  local mini = by[MINI]
  Check(RV.Impact(mini, "variant").text == "Classic", "kept in this layout: Classic only")
  Check(RV.Impact(mini, "base").text == "Both", "shared: both layouts, because Compact inherits the base")
  Check(#RV.PromotionReach(mini) == 1 and RV.PromotionReach(mini)[1] == "Compact", "promoting it would newly change Compact")
  Check(#RV.PromotionReach(bars) == 0, "promoting the action bars changes no other layout, so needs no question")
  -- cached by destination: the same table comes back
  Check(RV.Impact(mini, "base") == RV.Impact(mini, "base"), "the impact is cached by destination")
  -- a removal
  local q = by[QUICK]
  Check(RV.Impact(q, "base").text ~= "Unknown" and q.baseOnly, "a removal of something the base names can only be made in the base")
end

---------------------------------------------------------------------------
-- 3. Values as shown, leaf differences, whole modules
---------------------------------------------------------------------------
do
  local c, TW, LY, WZ, A, RV = Setup("Val Ues")
  local F = RV.Format
  Check(F(false) == "Off" and F(true) == "On" and F(0) == "0" and F("") == "(empty text)" and F(nil) == "(missing)" and F(LY.DEFAULT) == "(default)",
    "false, zero, an empty string, missing and the default all read differently")
  Check(F(0.25) == "0.25" and F(12) == "12", "numbers read as numbers")
  local text, _, color = F({ r = 1, g = 0, b = 0.5, a = 0.5 })
  Check(text == "#FF0080 at 50%" and color and color.r == 1, "a colour reads as hex and carries a swatch")
  Check(F({ x = 10.4, y = -3 }) == "10, -3" and F({}) == "(empty list)", "a position and an empty list")
  local file, full, _, media = F([[Interface\AddOns\MyFonts\fonts\Some.ttf]])
  Check(file == "Some.ttf" and full:find("MyFonts", 1, true) and media, "a media path shows its file, with the whole path for the tooltip")
  local piped = F("|cffff0000red|r")
  Check(piped == "||cffff0000red||r", "untrusted text is shown as text: a pipe is escaped, never a colour code")
  local long = F(string.rep("x", 500))
  Check(#long <= RV.MAX_VALUE and long:sub(-3) == "...", "a long value is cut with a mark")
  local _, longFull = F(string.rep("y", 5000))
  Check(#longFull <= RV.FULL_VALUE, "and its full reading is bounded too")
  Check(F(function() end) == "(function)" and F(0/0) == "NaN", "malformed values are shown, not raised")

  -- leaves
  local it = { id = "ellesmereui:addons.EllesmereUIChat", label = "Module EllesmereUIChat", adapter = "ellesmereui", kind = "changed",
    old = { chat = { fontSize = 12, shadow = false, name = "", tint = { r = 1, g = 1, b = 1 } }, gone = 5 },
    new = { chat = { fontSize = 14, shadow = true, name = "x", tint = { r = 0, g = 0, b = 1 } }, fresh = 0 } }
  local rows, total, trunc = RV.Leaves(it)
  local by = {}
  for _, r in ipairs(rows) do by[r.raw] = r end
  Check(total == 6 and not trunc and #rows == 6, "six leaves differ: " .. total)
  Check(by["chat.fontSize"].before == "12" and by["chat.fontSize"].after == "14" and by["chat.fontSize"].label == "Chat > Font size", "a value change, with a readable name")
  Check(by["chat.shadow"].before == "Off" and by["chat.shadow"].after == "On", "false to true")
  Check(by["chat.name"].before == "(empty text)" and by["chat.name"].after == "x", "empty to text")
  Check(by["chat.tint"].beforeColor and by["chat.tint"].afterColor.b == 1, "a colour is one leaf with swatches on both sides")
  Check(by["gone"].kind == "removed" and by["gone"].after == "(missing)" and by["fresh"].kind == "added" and by["fresh"].before == "(missing)" and by["fresh"].after == "0",
    "removed and added values are labelled as such, and zero is not missing")
  local t = A.Tally(it.old, it.new)
  Check(t.changed == 4 and t.added == 1 and t.removed == 1 and t.total == 6, "the tally agrees with the leaves")
  -- bounds
  local big = {}
  for i = 1, 3000 do big["k" .. i] = i end
  local big2 = {}
  for i = 1, 3000 do big2["k" .. i] = i + 1 end
  local rows2, total2, trunc2 = RV.Leaves({ id = "x", label = "x", old = big, new = big2, kind = "changed" })
  Check(#rows2 == RV.MAX_LEAVES and trunc2 and total2 > RV.MAX_LEAVES, "a large difference lists a bounded number of rows and says so")
  local huge = {}
  for i = 1, A.MAX_LEAVES + 500 do huge[i] = i end
  Check(A.Tally(nil, huge).capped, "the count stops at its bound and says so")
  local deep, node = {}, nil
  node = deep
  for _ = 1, 40 do node.n = {} node = node.n end
  Check(pcall(RV.Leaves, { id = "d", label = "d", old = deep, new = {}, kind = "changed" }), "a deeply nested value does not overflow")
  Check(pcall(A.Tally, deep, nil), "nor does the count")

  -- a whole module is published whole
  local by2 = ById(A)
  local mini = by2[MINI]
  Check(RV.IsBlob(mini), "a module is an opaque blob")
  local _, tot = RV.Leaves(mini)
  Check(tot == 1, "its inspection diff lists the one value that differs")
  for _, o in ipairs(A.Items()) do o.include = false end
  mini.include, mini.to = true, "base"
  local draft = A.Draft(true)
  Check(Same(LY.Capture.Get(draft.layers.base, MINI), mini.new), "but the draft carries the module as a whole, not that one value merged in")
  Check(not WZ.AuthorReview.SetLeaf, "there is no way to include a single value of a module")
end

---------------------------------------------------------------------------
-- 4. Attention: reasons with evidence, never a score
---------------------------------------------------------------------------
local function Bump(t, left)
  for k, v in pairs(t) do
    if left.n <= 0 then return end
    if type(v) == "number" then t[k] = v + 1; left.n = left.n - 1
    elseif type(v) == "table" and not (type(v.r) == "number") then Bump(v, left) end
  end
end
local function Count(t) local n = 0 for _, v in pairs(t) do n = n + (type(v) == "table" and Count(v) or 1) end return n end

do
  local c, TW, LY, WZ = Booted("Att En")
  local prof = c.EllesmereUIDB.profiles.Tweak
  -- one module with many value-only changes (no key added or removed)
  local bulky
  for m, blob in pairs(prof.addons) do
    if m ~= "EllesmereUIMinimap" and m ~= "EllesmereUIActionBars" and type(blob) == "table" and Count(blob) > 60 then bulky = m break end
  end
  assert(bulky, "a module to change many values of")
  local left = { n = 80 }
  Bump(prof.addons[bulky], left)
  -- one small change that switches something: an "enabled" key flipped in the minimap
  LY.ADVENTURE_PACKAGE.layers.base.ellesmereui.modules.EllesmereUIMinimap.enabled = true
  prof.addons.EllesmereUIMinimap.enabled = false
  -- a file of another addon in the profile only
  assert(Plant(prof), "a private font path")
  local A, RV = WZ.Author, WZ.AuthorReview
  assert(A.Begin()); A.SetSource("eui", "Tweak"); A.SetSource("twichui", nil); assert(A.Capture())
  local by = ById(A)
  local function Codes(it) local out = {} for _, f in ipairs(RV.Flags(it).list) do out[f.code] = f end return out end

  local bulkItem = by["ellesmereui:addons." .. bulky]
  Check(bulkItem and bulkItem.n.changed >= 60 and bulkItem.n.added == 0 and bulkItem.n.removed == 0, "a module with many changed values: " .. tostring(bulkItem and bulkItem.n.changed))
  local bc = Codes(bulkItem)
  Check(RV.Level(bulkItem) == "info" and not bc.structure and bc["whole-module"], "many changed values are a scope, not a risk: no review flag, only the whole-module note")
  local mc = Codes(by[MINI])
  Check(by[MINI].n.total <= 2 and mc["feature-toggled"] and RV.Level(by[MINI]) == "review", "one flipped switch is flagged although a single value differs")
  Check(mc["feature-toggled"].evidence[1]:find("enabled", 1, true) and mc["feature-toggled"].evidence[1]:find("key name", 1, true), "with its evidence, saying it was matched by the key name")
  local qc = Codes(by[QUICK])
  by[QUICK].include = true
  RV.Flags(by[QUICK])
  qc = Codes(by[QUICK])
  Check(qc.removed and qc.removed.evidence[1]:find("Shared base", 1, true) and qc.removed.action, "a removal is flagged, with where it is stored and what to look at")
  Check(RV.Level(by[BARS]) == "info" and not Codes(by[BARS]).removed, "an ordinary module change carries only the note")
  -- not every row is amber
  local amber = 0
  for _, it in ipairs(A.Items()) do if it.include and RV.Level(it) == "review" then amber = amber + 1 end end
  Check(amber < #A.Items(), "the indicator is not on every row")

  -- the media change is flagged before a check, and blocked after one
  local fontItem
  for _, it in ipairs(A.Items()) do for _, f in ipairs(RV.Flags(it).list) do if f.code == "media-external" then fontItem = it end end end
  Check(fontItem and RV.Level(fontItem) == "review", "a file from another addon is flagged for review before any check")
  local rep = A.Check()
  Check(not rep.ok, "the check refuses it")
  Check(RV.Level(fontItem) == "blocked" and Codes(fontItem)["media-blocked"].evidence[1]:find("another addon", 1, true), "and the row it is in is blocked, saying why")
  Check(RV.Counts().blocked >= 1 and RV.SummaryText():find("1 blocked", 1, true), "the summary counts it")
  RV.SetFilter("status", "blocked")
  Check(RV.Page().total == RV.Counts().blocked and RV.Page().rows[1] == fontItem, "the Blocked filter lists it")
  -- reviewed never bypasses a block
  RV.ClearFilters()
  RV.SetReviewed(fontItem.id, true)
  Check(RV.IsReviewed(fontItem) and RV.Level(fontItem) == "blocked", "marking it reviewed leaves it blocked")
  A.Session().report = nil
  Check(not A.Check().ok and not A.Publish(function() end), "and publishing is still refused")
  A.SetInclude(fontItem.id, false)
  Check(RV.Level(fontItem) ~= "blocked", "leaving the change out removes the block (it is not published)")
  A.SetInclude(fontItem.id, true)
  local fix = A.MediaFixes()[1]
  if fix and fix.replacement then
    A.FixMedia(fix.path)
    local again = A.Check()
    Check(#again.blockers == 0 or not again.blockers[1]:find("another addon", 1, true), "using TwichUI's copy clears the file's block: " .. tostring(again.blockers[1]))
    Check(RV.Level(fontItem) ~= "blocked", "and the row is no longer blocked once the file is replaced")
  end
end

---------------------------------------------------------------------------
-- 5. Reviewed, next item, bulk scope, publication
---------------------------------------------------------------------------
do
  local c, TW, LY, WZ, A, RV = Setup("Rev Mark")
  local by = ById(A)
  local before = { eui = Copy(c.EllesmereUIDB), tw = Copy(c.TwichUIDB) }
  by[QUICK].include = true; A.Session().rev = A.Session().rev + 1
  -- the removal needs a look; the others only carry notes
  Check(RV.Counts().review == 1 and RV.Level(by[QUICK]) == "review", "one included change needs review")
  local nxt = RV.NextNeedingReview()
  Check(nxt == by[QUICK], "Next item needing review finds it")
  RV.Select(QUICK)
  Check(RV.NextNeedingReview() == by[QUICK], "and wraps round to it when it is the only one")
  RV.SetReviewed(QUICK, true)
  Check(RV.IsReviewed(by[QUICK]) and RV.Counts().review == 0 and RV.Counts().reviewed == 1 and by[QUICK].include, "marking reviewed changes the count and not inclusion")
  Check(RV.NextNeedingReview() == nil, "nothing is left to look at")
  RV.SetFilter("status", "reviewed")
  Check(RV.Page().total == 1, "the Reviewed filter lists it")
  RV.ClearFilters()
  -- a leaving-out is not a review
  A.SetInclude(QUICK, false)
  Check(RV.Counts().review == 0 and RV.IsReviewed(by[QUICK]), "an excluded change needs no review, and keeps the mark it had")
  A.SetInclude(QUICK, true)
  -- the mark follows the change as proposed
  A.SetInclude(MINI, true)
  RV.SetReviewed(MINI, true)
  Check(RV.IsReviewed(by[MINI]) and RV.StaleReason(by[MINI]) == nil, "marked")
  A.SetTarget(MINI, "base")
  Check(not RV.IsReviewed(by[MINI]) and RV.StaleReason(by[MINI]) == "its destination changed", "moving it to the shared base makes the mark stale, and says why")
  RV.SetReviewed(MINI, true)
  by[MINI].new = Copy(by[MINI].new); by[MINI].new.extra = 1
  Check(not RV.IsReviewed(by[MINI]) and RV.StaleReason(by[MINI]) == "the values changed", "a different value makes it stale")
  RV.SetReviewed(MINI, false)
  Check(RV.StaleReason(by[MINI]) == nil and not RV.IsReviewed(by[MINI]), "and the author can clear a mark")
  -- the destination alone (the effect on the layouts staying the same) also ends a mark
  RV.SetReviewed(BARS, true)
  Check(RV.IsReviewed(by[BARS]), "the action bars are marked")
  A.SetTarget(BARS, "base")
  Check(RV.Impact(by[BARS]).text == "Classic" and not RV.IsReviewed(by[BARS]) and RV.StaleReason(by[BARS]) == "its destination changed",
    "sharing them changes no layout's result, but the destination changed, so the mark is stale")
  A.SetTarget(BARS, "variant")
  -- recapturing the same profile keeps a mark; a different source loses it
  RV.SetReviewed(QUICK, true)
  A.Capture()
  by = ById(A)
  Check(RV.IsReviewed(by[QUICK]), "capturing the same profile again keeps the mark: it is the same proposed change")
  Check(RV.Page().page == 1, "and the page is valid")

  -- bulk: exactly the changes in the order, every page, nothing hidden
  for _, it in ipairs(A.Items()) do A.SetInclude(it.id, true) end
  RV.SetFilter("kind", "removed")
  local order = RV.Page().total
  local changed, risky = RV.Bulk(false)
  Check(order == 2 and changed == 2, "the bulk scope is the filtered view: " .. changed)
  RV.ApplyBulk(false)
  Check(not by[QUICK].include and not by[DARK].include and by[MINI].include and by[BARS].include, "Leave out touched the two removals and nothing else")
  local n2, risky2 = RV.Bulk(true)
  Check(n2 == 2 and risky2 == 2, "including removals is counted as a decision about players' settings")
  RV.ClearFilters()
  Check(RV.Bulk(true) == 2 and RV.Bulk(false) == 2, "with the filters cleared the scope is every change")
  local sr = A.Session().rev
  RV.ApplyBulk(true)
  Check(by[QUICK].include and by[DARK].include, "Include with no filter includes all")

  -- nothing changed a profile while inspecting
  Check(Same(before.eui, c.EllesmereUIDB) and Same(before.tw, c.TwichUIDB), "the table never changed a profile")

  -- the publication is the table's decisions
  for _, it in ipairs(A.Items()) do it.include = false end
  by[MINI].include, by[MINI].to = true, "base"
  by[BARS].include, by[BARS].to = true, "variant"
  by[QUICK].include = false
  by[MINI].new = Copy(A.Items()[1] and by[MINI].new); by[MINI].new.extra = nil
  local draft = A.Draft(true)
  local canvas = LY.ADVENTURE_PACKAGE.geometry.canvas
  local function Resolved(variant, id)
    local ok, res = LY.Resolve(draft, variant, { screen = { w = canvas.w, h = canvas.h } })
    assert(ok)
    return res.adapters.ellesmereui.units[id]
  end
  Check(Same(Resolved(CLASSIC, MINI), by[MINI].new) and Same(Resolved(COMPACT, MINI), by[MINI].new), "an included, shared change is what both layouts resolve to")
  Check(Same(Resolved(CLASSIC, BARS), by[BARS].new), "an included, own change is what Classic resolves to")
  Check(Same(Resolved(COMPACT, BARS), LY.Capture.Get(LY.ADVENTURE_PACKAGE.layers.variants[COMPACT], BARS)), "and Compact keeps its own")
  Check(Same(Resolved(CLASSIC, QUICK), by[QUICK].old), "a change left out leaves the package as it was")
  Check(A.Counts().included == 2 and RV.Counts().included == 2, "the table's counts are the publication's")
  -- the confirmation names unflagged-but-open items
  Check(RV.Counts().review == 0, "no flagged change is open here")
end

---------------------------------------------------------------------------
-- 6. The window, from the real builders
---------------------------------------------------------------------------
do
  local c, TW, LY, WZ = Booted("Win Rev")
  PlantFont(c, LY)
  c.SlashCmdList.TWICHUI("layout author")
  local win = c.TwichUILayoutAuthor
  local P = WZ.AuthorWindow.pool
  local A, RV = WZ.Author, WZ.AuthorReview
  local function Click(label) local b = LM.Button(win, label) assert(b, "a button " .. label) b.scripts.OnClick(b) end
  Check(LM.Says(win, "Capture first."), "before a capture the section says what will appear")
  A.SetSource("eui", "Tweak")
  A.SetSource("twichui", nil)
  Click("Capture")
  local rv = P.rv
  Check(LM.Says(win, "4 changes · 2 included"), "the summary is above the table")
  Check(LM.Says(win, "Changes stay in this draft until you publish."), "with the reassurance, once")
  for _, h in ipairs({ "Include", "Setting", "Change", "Details", "Destination", "Affects", "Attention" }) do
    Check(rv.head:IsShown() and LM.Says(rv.head, h), "the header names " .. h)
  end
  local shown = {}
  for _, row in ipairs(rv.rows) do if row.frame:IsShown() then shown[#shown + 1] = row end end
  Check(#shown == 4, "four rows")
  local byName = {}
  for _, row in ipairs(shown) do byName[row.name.text] = row end
  Check(byName["Minimap"].kind.text == "Changed" and byName["Minimap"].detail.text == "1 field" and byName["Minimap"].dest.text.text == "This layout"
    and byName["Minimap"].affects.text == "Classic", "a row: name, change, details, destination, affects")
  Check(byName["Quickdraw"].attn.text == "Excluded" and byName["Quickdraw"].kind.text == "Removed", "a left-out removal says Excluded")
  Check(byName["Minimap"].attn.text == "Note" and not byName["Minimap"].bar:IsShown(), "a plain change has no amber marker")
  -- the checkbox only changes inclusion; a row click only selects
  local mini = byName["Minimap"]
  mini.check.scripts.OnClick(mini.check)
  Check(not mini.it.include and RV.Selected() == nil and mini.attn.text == "Excluded", "the box leaves it out and does not pick the row")
  mini.check.scripts.OnClick(mini.check)
  mini.frame.scripts.OnClick(mini.frame)
  Check(RV.Selected() == mini.it and mini.it.include and mini.sel:IsShown(), "the row click picks it (strongly marked) and leaves inclusion alone")
  Check(rv.d:IsShown() and LM.Says(rv.d, "Minimap") and LM.Says(rv.d, "ID: ellesmereui:addons.EllesmereUIMinimap") and LM.Says(rv.d, "Stored now in: Shared base"), "the details: name, id, storage")
  Check(LM.Says(rv.d, "Classic Adventure: changes") and LM.Says(rv.d, "Compact Adventure: unchanged"), "and what happens to each layout")
  Check(LM.Says(rv.d, "replaced as a whole") and LM.Says(rv.d, "Setting") and LM.Says(rv.d, "Before") and LM.Says(rv.d, "After"), "a module says it is included as a whole, above the before/after table")
  local leaf = rv.d.leaves[1]
  Check(leaf.frame:IsShown() and leaf.after.text == "tweaked-minimap" and leaf.label.text:find("Coords mode", 1, true), "the leaf shows the setting, before and after")
  -- the destination button asks before widening
  local sel = rv.rows
  mini.dest.scripts.OnClick(mini.dest)
  Check(c.popup and c.popup.key == "TWICHUI_LAYOUT_SHARE" and c.popup.text:find("Compact", 1, true), "sharing a change that would newly change Compact asks first")
  c.Decline()
  Check(mini.it.to == "variant", "declining leaves the destination")
  mini.dest.scripts.OnClick(mini.dest); c.Accept()
  Check(mini.it.to == "base" and mini.dest.text.text == "Shared base" and mini.affects.text == "Both" and RV.Selected() == mini.it, "accepting shares it; the row now says Both and stays selected")
  -- mark reviewed from the details
  rv.d.review.scripts.OnClick(rv.d.review)
  Check(RV.IsReviewed(mini.it) and LM.Says(rv.d, "Reviewed (undo)"), "Mark reviewed in the details")
  mini.dest.scripts.OnClick(mini.dest)
  Check(not RV.IsReviewed(mini.it), "moving it back makes the mark stale")
  -- close the details
  rv.d.close.scripts.OnClick(rv.d.close)
  Check(not rv.d:IsShown() and RV.Selected() == nil, "Close details hides them")
  -- filters through the controls
  P.rv.search:SetText("zzzz"); P.rv.search:Fire("OnEditFocusLost")
  Check(LM.Says(win, "No changes match these filters.") and LM.Says(win, "Showing 0 of 4 changes. Filters are on."), "a search with no match says so, with counts")
  Click("Clear filters")
  Check(not LM.Says(win, "No changes match") and LM.Says(win, "4 changes."), "Clear filters brings the table back")
  Click("Status: All")
  Check(LM.Says(win, "Status: Included") and LM.Says(win, "Showing 2 of 4 changes. Filters are on."), "the status filter cycles and says it is on")
  Check(LM.Says(win, "Leave out 2 filtered changes") and LM.Says(win, "Include 2 filtered changes"), "bulk buttons name their exact scope")
  Click("Clear filters")
  Check(LM.Says(win, "Include all 4 changes") or LM.Says(win, "Include all"), "without filters the bulk buttons say all")
  -- Next needing review, from the window
  local q = P.rv.rows
  for _, row in ipairs(rv.rows) do if row.frame:IsShown() and row.name.text == "Quickdraw" then row.check.scripts.OnClick(row.check) end end
  Check(LM.Says(win, "1 need review"), "including the removal puts it in the summary")
  Click("Next needing review")
  Check(RV.Selected() and RV.Selected().id == QUICK and rv.d:IsShown(), "Next needing review opens it")
  -- the publish confirmation mentions open flags
  Click("Check")
  local ready = A.Session().report
  A.Session().report = nil
  Click("Check")
  if A.Session().report.ok then
    Click("Publish")
    Check(c.popup and c.popup.text:find("flagged for a look", 1, true), "Publish's confirmation says changes were flagged and not marked reviewed")
    c.Decline()
  else
    Check(true, "(the check is blocked here by the planted font, so no publish question)")
  end
end

---------------------------------------------------------------------------
-- 7. Many changes, paging, repeated use, diagnostics
---------------------------------------------------------------------------
do
  local c, TW, LY, WZ = Booted("Man Y")
  c.SlashCmdList.TWICHUI("layout author")
  local win = c.TwichUILayoutAuthor
  local P = WZ.AuthorWindow.pool
  local A, RV = WZ.Author, WZ.AuthorReview
  A.SetSource("eui", "Tweak")   -- (the TwichUI profile stays: its many settings back at default make a long table)
  local b = LM.Button(win, "Capture"); b.scripts.OnClick(b)
  local total = #A.Items()
  Check(total > 100, "a long table: " .. total)
  local rv = P.rv
  local function Shown() local n = 0 for _, row in ipairs(rv.rows) do if row.frame:IsShown() then n = n + 1 end end return n end
  Check(Shown() == 10 and LM.Says(win, ("1-10 of %d."):format(total)) and LM.Says(win, "Page 1 of " .. math.ceil(total / 10)), "ten rows and the visible range")
  local made0 = c.made()
  local frames0 = WZ.AuthorWindow.frames
  local nxt = LM.Button(win, "Next")
  for _ = 1, 15 do nxt.scripts.OnClick(nxt) end
  Check(LM.Says(win, "Page 16 of") and LM.Says(win, "151-160 of"), "paging forward")
  local prev = LM.Button(win, "Previous")
  for _ = 1, 15 do prev.scripts.OnClick(prev) end
  -- details open, close, page, sort, size: nothing new is made
  local size = LM.Button(win, "Rows: 10")
  for i = 1, 20 do
    rv.rows[1].frame.scripts.OnClick(rv.rows[1].frame)
    nxt.scripts.OnClick(nxt)
    rv.d.close.scripts.OnClick(rv.d.close)
  end
  size.scripts.OnClick(size)
  Check(Shown() == 15 and RV.State().size == 15, "Rows cycles the page size")
  size.scripts.OnClick(size); size.scripts.OnClick(size)
  Check(RV.State().size == 10, "and cycles back")
  local st = RV.State()
  st.page = math.ceil(total / 10)
  Check(RV.Page().page == st.page and #RV.Page().rows == total - (st.page - 1) * 10, "the last page holds the rest")
  RV.SetFilter("search", "zzzz")
  Check(st.page == 1, "a filter returns to page 1")
  RV.ClearFilters()
  Check(c.made() == made0 and WZ.AuthorWindow.frames == frames0, "repeated paging and details made no frames")
  local ev = 0
  for _ in pairs(win.events) do ev = ev + 1 end
  Check(ev == 0, "and registered no events")
  local hooks = 0
  for _, h in pairs(rv.rows[1].frame.hooks) do hooks = hooks + #h end
  local h0 = hooks
  for _ = 1, 10 do RV.Rebuild(); WZ.AuthorWindow.Refresh() end
  hooks = 0
  for _, h in pairs(rv.rows[1].frame.hooks) do hooks = hooks + #h end
  Check(hooks == h0, "nor added a handler to a row")
  -- a recapture keeps the filters and clamps the page
  RV.SetFilter("kind", "default"); RV.SetPage(5)
  b.scripts.OnClick(b)
  Check(RV.State().kind == "default" and RV.Page().page <= RV.Page().pages, "capturing again keeps the filters and clamps the page")
  -- the time a long table takes to put in order, offline, as a figure to compare
  RV.ClearFilters()
  local t0 = os.clock()
  for _ = 1, 20 do RV.Rebuild() end
  print(("  (offline) %d changes put in order: %.1f ms each, from cached flags and impact"):format(total, (os.clock() - t0) * 1000 / 20))
  -- the gauges
  local gauges = {}
  for _, g in ipairs(TW.Perf.gauges) do gauges[g.id] = g end
  RV.Select(A.Items()[1].id); WZ.AuthorWindow.Refresh()
  Check(gauges["layoutwizard.author.review.leaves"] and gauges["layoutwizard.author.review.leaves"].read() >= 0, "the leaf rows held are a gauge")
end

-- the diagnostics tool can place every scope and gauge this adds
do
  local gauges = io.open(REPO .. "TwichUI_Diagnostics/Gauges.lua"):read("*a")
  local docs = io.open(REPO .. "docs/diagnostics.md"):read("*a")
  for _, id in ipairs({ "layoutwizard.author.review", "layoutwizard.author.review.detail" }) do
    Check(gauges:find('["' .. id .. '"]', 1, true), id .. " is in DX.OPS")
    Check(docs:find("`" .. id .. "`", 1, true), id .. " is in docs/diagnostics.md")
  end
  Check(docs:find("`layoutwizard.author.review.leaves`", 1, true), "the leaf gauge is documented")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("LAYOUT REVIEW TEST PASSED")
