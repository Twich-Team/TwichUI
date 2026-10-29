dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- Release hardening of the layout packages (docs/layouts/implementation-status.md, "RH-1"). Each section is a regression test
-- for one finding of the hardening pass: parent and child preservation, reset versus stop managing, partial updates and
-- recovery, the final-plan fit, screen coverage, portable media, comparing a published package with the bundled one, and the
-- transport's decompression bound. TwichUI's code is the real one; EllesmereUI is the stand-in (layouts_mock.lua) with the
-- real functions' shape, filling its defaults into a blob as it loads. Nothing here is the game.

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local Copy, Same = LM.Copy, LM.Same
local EUI = { defaults = true }

local function Engine(c)
  assert(c.TwichUI.LayoutsLauncher.Load())
  return c.TwichUI.Layouts
end
local function Reload(name, c, opts) return LM.Boot(name, LM.Logout(c), opts or { eui = EUI }) end
local function Rows(plan)
  local out = {}
  for _, r in ipairs(plan.update and plan.update.rows or {}) do out[r.unit] = r end
  return out
end

local c0 = LM.Boot("Table", nil, { eui = EUI })
local L0 = Engine(c0)
local PKG, CLASSIC, COMPACT = L0.CLASSIC_PACKAGE, L0.CLASSIC_VARIANT, L0.COMPACT_VARIANT
local TC0 = c0.TwichUI.TwichConfig
local function Field(group, slot, key)
  local f = TC0.Group(group).index[slot][key]
  return "twichui:" .. table.concat(f.at, ".") .. "." .. f.key, f
end
local FONT_U = Field("classBars", "classBars", "font")
local NAV_U, NAV_F = Field("navigation", "navigation", "font")
local MINIMAP_U, LAYOUT_U = "ellesmereui:pos.minimap", "ellesmereui:layout"
local CHATSIZE_U = "ellesmereui:addons.EllesmereUIChat.chat.chatFontSize"
local COORDS_U = "ellesmereui:addons.EllesmereUIMinimap.minimap.coordsMode"
local TARGET, BACKUP = "TwichUI Adventure", "TwichUI Adventure (previous)"

local function Publish(revision, edit)
  local p = Copy(PKG)
  p.revision = revision
  if edit then edit(p) end
  local env, problems = L0.Pub.Build(p, { now = 1000 + revision, notes = "Revision " .. revision })
  assert(env, "published: " .. tostring(problems and problems[1] and (problems[1].code .. " " .. tostring(problems[1].where))))
  assert(L0.Pub.Check(env), "and it checks out")
  return env.package
end
local CHAT_V1 = PKG.layers.base.ellesmereui.modules.EllesmereUIChat.chat.chatFontSize
local V1 = Publish(1)

local function Install(name, c, pkg, variant, opts)
  local L = Engine(c)
  local plan = L.Plan(pkg, variant, opts)
  assert(plan.ok, "plan: " .. tostring(plan.blocked[1] and plan.blocked[1].code or (plan.problems and plan.problems[1] and plan.problems[1].code)))
  local ok, res = L.Apply(pkg, variant, plan.key, opts)
  assert(ok and (res.state == "applied" or res.state == "verified"), "apply: " .. tostring(ok and res.state or res))
  return Reload(name, c), plan, res
end
local function Update(name, c, pkg, variant, opts)
  local L = Engine(c)
  local plan = L.Plan(pkg, variant, opts)
  assert(plan.ok, "update plan: " .. tostring(plan.blocked[1] and plan.blocked[1].code))
  local ok, res = L.Apply(pkg, variant, plan.key, opts)
  assert(ok and (res.state == "applied" or res.state == "verified"), "update apply: " .. tostring(ok and res.state or res))
  return Reload(name, c), plan
end
local function Live(c) return c.EllesmereUIDB.profiles[TARGET] end

---------------------------------------------------------------------------
-- A1. An allowlisted EllesmereUI field inside a module blob (the minimap's coordinates) is a unit of its own: the recipient's
--     change is seen, kept through an update that replaces the blob, and survives EllesmereUI filling its defaults at load
---------------------------------------------------------------------------
do
  local NAME = "Coords"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local b = L.Journal.ReadBaseline()
  Check(b.parts.ellesmereui.units[COORDS_U] ~= nil, "A1. the minimap's coordinates are tracked in the baseline")
  Live(c).addons.EllesmereUIMinimap.minimap.coordsMode = "always"   -- mine (the layout's is "never")
  local V2 = Publish(2, function(p) p.layers.base.ellesmereui.modules.EllesmereUIMinimap.twichTest = 1 end)   -- the blob changes
  local plan = L.Plan(V2, CLASSIC)
  local r = Rows(plan)[COORDS_U]
  Check(r and r.case == "mine" and r.decision == "keep", "    my change to them is seen and kept (" .. tostring(r and r.case) .. ")")
  Check(Rows(plan)["ellesmereui:addons.EllesmereUIMinimap"].decision == "apply", "    while the minimap blob is replaced with the layout's")
  Check(plan.parts.ellesmereui.payload.data.addons.EllesmereUIMinimap.minimap.coordsMode == "always", "    my value is carried into the payload")
  local ok = L.Apply(V2, CLASSIC, plan.key)
  c = Reload(NAME, c)
  L = Engine(c)
  Check(ok and Live(c).addons.EllesmereUIMinimap.minimap.coordsMode == "always" and Live(c).addons.EllesmereUIMinimap.twichTest == 1,
    "    after the reload (and EllesmereUI's load-time defaults): mine, inside the layout's new blob")
  Check(L.Journal.Read().state == "verified", "    and the check after the reload matches")
  Check(L.Journal.Read().expect.ellesmereui[COORDS_U] ~= nil, "    the field is read back by value, not only for presence")
end

---------------------------------------------------------------------------
-- A2. A sub-unit the package stops naming keeps the recipient's value even when its parent blob is replaced (stop managing
--     preserves; it never resets). Repeated for a value and for absence.
---------------------------------------------------------------------------
do
  local NAME = "Released"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  Live(c).addons.EllesmereUIChat.chat.chatFontSize = CHAT_V1 + 5
  local V2 = Publish(2, function(p)
    local chat = p.layers.base.ellesmereui.modules.EllesmereUIChat
    chat.chat.chatFontSize = nil   -- the layout stops naming the chat text size
    chat.twichTest = 7             -- and changes the blob, so the blob is replaced
  end)
  local plan = L.Plan(V2, CLASSIC)
  local r = Rows(plan)[CHATSIZE_U]
  Check(r and r.case == "removed" and r.decision == "release", "A2. a text size the layout stops naming is released")
  Check(plan.parts.ellesmereui.payload.data.addons.EllesmereUIChat.chat.chatFontSize == CHAT_V1 + 5, "    and my value goes into the replaced blob")
  L.Apply(V2, CLASSIC, plan.key)
  c = Reload(NAME, c)
  L = Engine(c)
  Check(Live(c).addons.EllesmereUIChat.chat.chatFontSize == CHAT_V1 + 5 and Live(c).addons.EllesmereUIChat.twichTest == 7,
    "    after the reload: my chat text size, inside the layout's new chat blob")
  Check(L.Journal.Read().state == "verified" and L.Journal.ReadBaseline().parts.ellesmereui.units[CHATSIZE_U] == nil,
    "    checked; the baseline no longer tracks it")

  -- absent: a sub-unit the recipient's profile doesn't have stays absent (EllesmereUI's own default)
  local NAME2 = "ReleasedAbsent"
  local d = Install(NAME2, LM.Boot(NAME2, nil, { eui = EUI }), V1, CLASSIC)
  local L2 = Engine(d)
  Live(d).addons.EllesmereUIChat.chat.chatFontSize = nil
  local plan2 = L2.Plan(V2, CLASSIC)
  Check(plan2.parts.ellesmereui.payload.data.addons.EllesmereUIChat.chat.chatFontSize == nil, "    an absent value stays absent")
end

---------------------------------------------------------------------------
-- A3. An owned setting that ends up in the atomic layout group: the group is the recipient's while it holds one of their own
--     settings; "Use the layout's" for the group can't take it back
---------------------------------------------------------------------------
do
  local NAME = "OwnedLinked"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local own = { update = { choose = { [MINIMAP_U] = "own" } } }
  local V2 = Publish(2, function(p) p.layers.base.twichui.groups.navigation.navigation.font = "Cinzel" end)
  c = Update(NAME, c, V2, CLASSIC, own)
  local L = Engine(c)
  Check(L.Journal.ReadBaseline().parts.ellesmereui.units[MINIMAP_U].o == true, "A3. the minimap's place is mine")
  local mine = Copy(Live(c).addons.EllesmereUIMinimap.minimap.position)
  -- v3 links the minimap to another element (now part of the layout group) and changes another link in the group
  local V3 = Publish(3, function(p)
    local anchors = p.layers.variants[CLASSIC].ellesmereui.layout.anchors
    anchors.EBS_Minimap = { target = "MainBar", side = "TOP", offsetX = 0, offsetY = 40 }
    anchors.Bar5.offsetY = (anchors.Bar5.offsetY or 0) + 3
  end)
  local opts = { update = { groups = { layout = "package" } } }
  local plan = L.Plan(V3, CLASSIC, opts)
  local r = Rows(plan)
  Check(r[MINIMAP_U].decision == "owned" and r[MINIMAP_U].group == "layout", "    in the group now, and still mine")
  Check(plan.update.groups.layout and plan.update.groups.layout.choice == "mine" and plan.update.groups.layout.owned,
    "    the group stays mine, and says it is because one of its settings is mine")
  Check(r[LAYOUT_U].decision == "keep", "    so the layout's links aren't applied around my own place")
  Check(Same(plan.parts.ellesmereui.payload.data.addons.EllesmereUIMinimap.minimap.position, mine), "    my place goes into the payload")
  local back = L.Plan(V3, CLASSIC, { update = { groups = { layout = "package" }, choose = { [MINIMAP_U] = "manage" } } })
  Check(Rows(back)[MINIMAP_U].decision ~= "owned" and Rows(back)[LAYOUT_U].decision == "apply" and not back.update.groups.layout,
    "    Manage again hands it back, and then the group can take the layout's")
  local rec = L.Plan(V3, CLASSIC, { update = { policy = "recommended" } })
  Check(Rows(rec)[MINIMAP_U].decision == "owned" and rec.update.groups.layout.choice == "mine", "    Reapply recommended doesn't take it back either")
end

---------------------------------------------------------------------------
-- A4. An owned setting whose current value TwichUI can't read stays the recipient's (the mark is kept, the value is carried)
---------------------------------------------------------------------------
do
  local NAME = "OwnedOdd"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local V2 = Publish(2, function(p) p.layers.base.twichui.groups.navigation.navigation.font = "Cinzel" end)
  c = Update(NAME, c, V2, CLASSIC, { update = { choose = { [MINIMAP_U] = "own" } } })
  local L = Engine(c)
  Live(c).addons.EllesmereUIMinimap.minimap.position = { point = "TOPLEFT", x = "odd" }   -- a form TwichUI doesn't read
  local V3 = Publish(3, function(p) p.layers.base.ellesmereui.modules.EllesmereUIMinimap.twichTest = 3 end)
  local plan = L.Plan(V3, CLASSIC)
  Check(Rows(plan)[MINIMAP_U] and Rows(plan)[MINIMAP_U].decision == "owned", "A4. an owned place TwichUI can't read is still mine")
  Check(Same(plan.parts.ellesmereui.payload.data.addons.EllesmereUIMinimap.minimap.position, { point = "TOPLEFT", x = "odd" }),
    "    carried into the payload as it is")
  L.Apply(V3, CLASSIC, plan.key)
  c = Reload(NAME, c)
  L = Engine(c)
  local bu = L.Journal.ReadBaseline().parts.ellesmereui.units[MINIMAP_U]
  Check(bu ~= nil and bu.o == true, "    and the baseline still says it is mine")
end

---------------------------------------------------------------------------
-- B1. A record with a step that never ran can't be settled as installed: no "verified", no baseline, no management change
---------------------------------------------------------------------------
do
  local NAME = "Stopped"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local V2 = Publish(2, function(p)
    p.layers.base.twichui.groups.navigation.navigation.font = "Cinzel"
    p.layers.base.ellesmereui.modules.EllesmereUIBags.twichTest = 2
  end)
  local TA = L.ADAPTERS.twichui
  local real = TA.Apply
  TA.Apply = function() return { state = "failed", code = "write", rollback = "clean" } end
  local plan = L.Plan(V2, CLASSIC)
  local _, first = L.Apply(V2, CLASSIC, plan.key)
  TA.Apply = real
  Check(first.state == "partial" and first.steps[1].state == "done", "B1. (an update whose EllesmereUI step was done)")
  -- what a client stopped between the two steps leaves: still applying, EllesmereUI done, TwichUI never run
  local raw = c.TwichUIDB.layouts.install
  raw.state, raw.steps[2].state, raw.steps[2].code, raw.steps[2].rollback = "applying", "pending", nil, nil
  c = Reload(NAME, c)
  L = Engine(c)
  Check(L.Journal.Read().state == "interrupted", "B1. found at login: interrupted")
  local report = L.Verify(true)
  local j, m, b = L.Journal.Read(), L.Journal.ReadManaged(), L.Journal.ReadBaseline()
  Check(j.state == "partial", "    a recorded check can't settle it: it stays unfinished (" .. tostring(j.state) .. ")")
  Check(m.revision == 1 and b.parts.ellesmereui.revision == 1 and b.parts.twichui.revision == 1, "    the management record and the baseline stay v1's")
  Check(report and report.incomplete == true, "    and the report says a step didn't run")
  local retry = L.Plan(V2, CLASSIC)
  Check(retry.ok and retry.update.resume and retry.parts.ellesmereui.resumed, "    setting up again resumes it, EllesmereUI's step already done")
end

---------------------------------------------------------------------------
-- B2. An update can't start while a Restore or an Undo is half done
---------------------------------------------------------------------------
do
  local NAME = "HalfUndone"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local V2 = Publish(2, function(p) p.layers.base.twichui.groups.navigation.navigation.font = "Cinzel" end)
  c = Update(NAME, c, V2, CLASSIC)
  local L = Engine(c)
  c.TwichUIDB.layouts.install.state = "undo-partial"
  local p = L.Plan(V2, CLASSIC)
  Check(not p.ok and p.blocked[1].code == "undo-unfinished", "B2. an Undo that didn't finish blocks a new update (" .. tostring(p.blocked[1] and p.blocked[1].code) .. ")")
  c.TwichUIDB.layouts.install.state = "restore-partial"
  p = L.Plan(V2, CLASSIC)
  Check(not p.ok and p.blocked[1].code == "restore-unfinished", "    and so does a Restore that didn't finish")
  Check(L.Explain("undo-unfinished") ~= "undo-unfinished" and L.Explain("restore-unfinished") ~= "restore-unfinished", "    both explained")
end

---------------------------------------------------------------------------
-- B3. Undo that stopped after renaming the old profile back can be finished: the retry doesn't need the copy again
---------------------------------------------------------------------------
do
  local NAME = "UndoTwice"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local home = Engine(c).Journal.Read().snapshot.ellesmereui.active
  c.EllesmereUIDB.activeProfile = home   -- the player went back to their own EllesmereUI profile before the update
  local V2 = Publish(2, function(p) p.layers.base.ellesmereui.modules.EllesmereUIBags.twichTest = 2 end)
  c = Update(NAME, c, V2, CLASSIC)
  local L = Engine(c)
  local up = L.PlanUndo()
  Check(up.ok, "B3. Undo this update plans")
  local E = c.EllesmereUI
  local switch = E.SwitchProfile
  E.SwitchProfile = function(name) if name == home then return end switch(name) end   -- the last switch fails
  local ok, res = L.Undo(up.key)
  E.SwitchProfile = switch
  Check(ok and res.state == "undo-partial", "    it stops part way (" .. tostring(res and res.state) .. ")")
  Check(c.EllesmereUIDB.profiles[BACKUP] == nil and c.EllesmereUIDB.profiles[TARGET] ~= nil, "    after the old profile got its name back")
  local again = L.PlanUndo()
  Check(again.ok, "    the retry plans (" .. tostring(again.blocked[1] and again.blocked[1].code) .. ")")
  local ok2, res2 = L.Undo(again.key)
  Check(ok2 and res2.state == "undoing" and c.EllesmereUIDB.activeProfile == home, "    and finishes: the profile in use before the update is in use")
  c = Reload(NAME, c)
  L = Engine(c)
  Check(L.Journal.Read().revision == 1 and L.Journal.Read().update == nil, "    checked after the reload: back to v1")
end

---------------------------------------------------------------------------
-- B4. A finished setup remembers whether its last check matched, and the wizard says so
-- B5. Stop managing belongs to the character that installed it
---------------------------------------------------------------------------
do
  local NAME = "Mismatched"
  local c = LM.Boot(NAME, nil, { eui = EUI })
  local L = Engine(c)
  local plan = L.Plan(V1, CLASSIC)
  L.Apply(V1, CLASSIC, plan.key)
  local TC = c.TwichUI.TwichConfig
  local f = TC.Group("navigation").index.navigation.font
  TC.Container(f, true)[f.key] = "Spectral Medium"   -- changed before the check: it won't match
  c = Reload(NAME, c)
  L = Engine(c)
  Check(L.Journal.Read().state == "mismatch" and L.Journal.ReadManaged().check == "mismatch", "B4. the management record keeps the last check's result")
  Check(L.Finish(), "    Keep this setup")
  Check(L.Journal.ReadManaged().check == "mismatch", "    still known after finishing")

  local alt = LM.Boot("Other", LM.Logout(c), { eui = EUI })
  local LA = Engine(alt)
  local ok, code = LA.Detach()
  Check(not ok and code == "journal-other-character" and LA.Journal.ReadManaged() ~= nil, "B5. another character can't stop managing it")
end

---------------------------------------------------------------------------
-- B6. Collisions and missing profiles: an unrelated profile under the copy's name, a copy that went missing, a replaced copy
---------------------------------------------------------------------------
do
  local NAME = "Collide"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  c.EllesmereUIDB.profiles[BACKUP] = { addons = {} }   -- the player's own profile happens to have that name
  local V2 = Publish(2, function(p) p.layers.base.ellesmereui.modules.EllesmereUIBags.twichTest = 2 end)
  local p = L.Plan(V2, CLASSIC)
  Check(not p.ok and p.blocked[1].adapter == "ellesmereui" and p.blocked[1].code == "backup-taken", "B6. an unrelated profile under the copy's name blocks the update")
  c.EllesmereUIDB.profiles[BACKUP] = nil
  c = Update(NAME, c, V2, CLASSIC)
  L = Engine(c)
  -- a second update before the first was kept: the copy from before the first is replaced, and the review says so
  local V3 = Publish(3, function(p2) p2.layers.base.ellesmereui.modules.EllesmereUIBags.twichTest = 3 end)
  local p3 = L.Plan(V3, CLASSIC)
  Check(p3.ok and p3.parts.ellesmereui.backup.replaces, "    a second update replaces the copy kept by the first")
  -- the copy went missing (the player deleted it in EllesmereUI): Undo is refused with the reason; Restore still works
  c.EllesmereUIDB.profiles[BACKUP] = nil
  local pu = L.PlanUndo()
  Check(not pu.ok and pu.blocked[1].code == "backup-missing", "    a missing copy: Undo this update is refused, with the reason")
  Check(L.PlanRestore().ok, "    Restore is still offered")
end

---------------------------------------------------------------------------
-- A5. Reset to the addon's default (package format 4) versus stop managing: v1 sets a non-default value, the author puts it
--     back to the default, v2 is published; an existing recipient gets the default, keeps their own change, or keeps the old
--     value when the package only stops naming it. Older readers refuse format 4; reset is only for settings with a known default.
---------------------------------------------------------------------------
do
  Check(L0.FORMAT >= 4, "A5. the package format that can say reset is 4, which this TwichUI reads (it reads up to " .. L0.FORMAT .. "; the shipped one is 6: it also carries editable presets)")
  local DEF = NAV_F.default
  Check(PKG.layers.base.twichui.groups.navigation.navigation.font ~= nil and DEF ~= PKG.layers.base.twichui.groups.navigation.navigation.font,
    "    v1 sets the navigation font to something other than TwichUI's default")
  local function ResetNav(p)
    p.format = 6
    p.layers.base.twichui.groups.navigation.navigation.font = nil
    p.layers.base.twichui.reset = { NAV_U }
    p.layers.base.ellesmereui.reset = { COORDS_U }
    p.layers.base.ellesmereui.modules.EllesmereUIMinimap.minimap.coordsMode = nil
  end
  local V2R = Publish(2, ResetNav)
  Check(V2R.format == 6 and V2R.layers.base.twichui.reset[1] == NAV_U, "    published as format 6 (the package's own), the reset as a plain list of unit ids")
  -- the recipient didn't touch it: it goes back to TwichUI's default, and nothing is stored
  local NAME = "Resets"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local plan = L.Plan(V2R, CLASSIC)
  local r = Rows(plan)[NAV_U]
  Check(r and r.case == "package" and r.decision == "apply", "    the reset is the layout's change: applied (" .. tostring(r and r.case) .. ")")
  local rc = Rows(plan)[COORDS_U]
  Check(rc and rc.decision == "apply" and plan.parts.ellesmereui.payload.data.addons.EllesmereUIMinimap.minimap.coordsMode == nil,
    "    the EllesmereUI field is taken out of the blob, so EllesmereUI's own default applies")
  L.Apply(V2R, CLASSIC, plan.key)
  local TC = c.TwichUI.TwichConfig
  Check(TC.Raw(NAV_F) == nil and TC.Effective(NAV_F) == DEF, "    TwichUI: nothing stored, the setting reads TwichUI's default")
  c = Reload(NAME, c)
  L = Engine(c)
  local j, b = L.Journal.Read(), L.Journal.ReadBaseline()
  Check(j.state == "verified", "    checked after the reload by value: verified")
  Check(b.parts.twichui.units[NAV_U].p == L.Value(DEF) and b.parts.twichui.units[NAV_U].s == "d", "    the baseline: recommended = the default, and not stored")
  -- the next update leaves it alone (nothing to do), and a later TwichUI default would be followed (never stored)
  Check(Rows(L.Plan(V2R, CLASSIC))[NAV_U].case == "same", "    the same package again: unchanged")
  -- failure to reset is detected: a value stored again before the check reads differently
  local plan2 = L.Plan(V2R, CLASSIC)
  Check(select(2, L.Apply(V2R, CLASSIC, plan2.key)) == "nothing", "    nothing to do")
  -- Undo brings the v1 value back
  local up = L.PlanUndo()
  Check(up.ok, "    Undo this update is offered")
  L.Undo(up.key)
  c = Reload(NAME, c)
  TC = c.TwichUI.TwichConfig
  Check(TC.Effective(NAV_F) == PKG.layers.base.twichui.groups.navigation.navigation.font, "    Undo: the v1 value is back")

  -- the recipient changed it: theirs is kept (a conflict), unless they choose the layout's
  local NAME2 = "ResetsMine"
  local d = Install(NAME2, LM.Boot(NAME2, nil, { eui = EUI }), V1, CLASSIC)
  local L2 = Engine(d)
  d.TwichUI.TwichConfig.Container(NAV_F, true)[NAV_F.key] = "Spectral Medium"
  local p2 = L2.Plan(V2R, CLASSIC)
  Check(Rows(p2)[NAV_U].case == "conflict" and Rows(p2)[NAV_U].decision == "keep", "    a recipient who changed it keeps theirs")
  Check(Rows(L2.Plan(V2R, CLASSIC, { update = { choose = { [NAV_U] = "package" } } }))[NAV_U].decision == "apply", "    or takes the layout's default")
  -- a reset that didn't take: something stores a value again before the check
  local p3 = L2.Plan(V2R, CLASSIC, { update = { choose = { [NAV_U] = "package" } } })
  L2.Apply(V2R, CLASSIC, p3.key, { update = { choose = { [NAV_U] = "package" } } })
  d.TwichUI.TwichConfig.Container(NAV_F, true)[NAV_F.key] = "Cinzel"
  d = Reload(NAME2, d)
  L2 = Engine(d)
  local diffs = L2.Journal.Read().verify.diffs
  local seen = false
  for _, x in ipairs(diffs) do if x.unit == NAV_U then seen = true end end
  Check(L2.Journal.Read().state == "mismatch" and seen, "    a reset that didn't take is found by the check")

  -- stop naming it (format 3 or 4, no reset): released, the v1 value stays
  local V2S = Publish(2, function(p) p.layers.base.twichui.groups.navigation.navigation.font = nil end)
  local NAME3 = "Unmanaged"
  local e = Install(NAME3, LM.Boot(NAME3, nil, { eui = EUI }), V1, CLASSIC)
  local L3 = Engine(e)
  local p4 = L3.Plan(V2S, CLASSIC)
  Check(Rows(p4)[NAV_U].case == "removed" and Rows(p4)[NAV_U].decision == "release", "    stop naming it: released")
  L3.Apply(V2S, CLASSIC, p4.key)
  Check(e.TwichUI.TwichConfig.Effective(NAV_F) == PKG.layers.base.twichui.groups.navigation.navigation.font, "    and the recipient keeps the v1 value")

  -- validation: where reset can be said, and for what
  local function Problems(edit)
    local p = Copy(PKG); p.format = 4; edit(p)
    local ok, problems = L0.Validate(p)
    local codes = {}
    for _, x in ipairs(ok and {} or problems) do codes[x.code] = true end
    return ok, codes
  end
  local ok3, c3 = Problems(function(p) p.format = 3; p.layers.base.twichui.reset = { NAV_U } end)
  Check(not ok3 and c3["not-yet"], "    a format 3 package can't say reset")
  local _, c4 = Problems(function(p) p.layers.base.twichui.reset = { "twichui:place.marker-bar" } end)
  Check(c4["reset-unsupported"], "    a TwichUI place can't be reset (its default isn't a value TwichUI can name)")
  local _, c5 = Problems(function(p) p.layers.base.ellesmereui.reset = { MINIMAP_U } end)
  Check(c5["reset-unsupported"], "    nor an EllesmereUI position, text size or blob")
  local _, c6 = Problems(function(p) p.layers.base.twichui.reset = { FONT_U } end)
  Check(c6["reset-and-set"], "    a setting can't be both set and reset in one layer")
  local _, c7 = Problems(function(p) p.choices[1].options[2].twichui.reset = { NAV_U } end)
  Check(next(c7) ~= nil, "    a wizard choice can't reset")
  local _, c8 = Problems(function(p) p.layers.base.twichui.reset = { NAV_U, NAV_U } end)
  Check(c8.repeated, "    a unit named twice is refused")
  local ok9 = Problems(function(p) ResetNav(p) end)
  Check(ok9, "    a reset in the base is valid")
  -- an older TwichUI (format 3) refuses the package rather than misreading it
  local was = L0.FORMAT
  L0.FORMAT = 3
  local okOld, pOld = L0.Validate(V2R)
  L0.FORMAT = was
  Check(not okOld and pOld[1].code == "format-newer", "    a TwichUI that reads format 3 refuses it as newer")
  Check(L0.Canon(L0.DEFAULT) ~= L0.Canon(L0.REMOVE) and L0.Copy(L0.DEFAULT) == L0.DEFAULT, "    reset and inherit are different markers, and keep their identity")
end

---------------------------------------------------------------------------
-- A6. Authoring: a setting the layout names that the captured profile leaves at TwichUI's default is a decision, never
--     assumed: left out by default; included, "Reset to default" (format 4) or "Stop managing"
---------------------------------------------------------------------------
do
  local NAME = "Author Ing"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  assert(c.C_AddOns.LoadAddOn("TwichUI_LayoutWizard"))
  local LY, A = c.TwichUI.Layouts, c.TwichUI.LayoutWizard.Author
  c.TwichUI.TwichConfig.Container(NAV_F, true)[NAV_F.key] = nil   -- the author puts the navigation font back to the default
  assert(A.Begin())
  A.SetSource("eui", TARGET)
  A.SetSource("twichui", c.TwichUI.Profiles.Current())
  Check(A.Capture(), "A6. captured")
  local it
  for _, x in ipairs(A.Items()) do if x.id == NAV_U then it = x end end
  Check(it and it.kind == "default" and it.canReset and not it.include, "    a setting back at the default is its own kind of change, left out until the author decides")
  local function Base(pkg) return pkg.layers.base.twichui end
  local d0 = A.Draft()
  Check(Base(d0).groups.navigation.navigation.font ~= nil and Base(d0).reset == nil, "    left out: the package keeps its value")
  Check(A.SetInclude(NAV_U, true) and it.how == "reset", "    included: Reset to default unless the author chooses otherwise")
  local d1 = A.Draft()
  Check(d1.format == 6 and Base(d1).reset and Base(d1).reset[1] == NAV_U and Base(d1).groups.navigation.navigation.font == nil,
    "    reset: format 6 (the package's own), the unit in the base's reset list, its value gone")
  Check(LY.Pub.Strict(d1), "    and the draft passes the strict check a recipient makes")
  Check(A.SetHow(NAV_U, "release"), "    or Stop managing")
  local d2 = A.Draft()
  Check(d2.format == 6 and Base(d2).reset == nil and Base(d2).groups.navigation.navigation.font == nil, "    release: no longer named, nothing reset, format unchanged")
  Check(not A.SetHow(FONT_U, "reset"), "    only such a setting offers the choice")
  A.End()
end

---------------------------------------------------------------------------
-- C. The final plan: Review previews and checks what Apply leaves (the player's own minimap, chat, kept layout group, a whole
--    EllesmereUI kept as it is), not only the recommended placement; nothing is changed to draw it, nothing is moved to clear
--    a warning
---------------------------------------------------------------------------
local function Review(c)
  assert(c.C_AddOns.LoadAddOn("TwichUI_LayoutWizard"))
  local M = c.TwichUI.LayoutWizard.Model
  M.End()
  assert(M.Begin())
  M.Go(M.REVIEW)
  assert(M.Step() == M.REVIEW, "on Review")
  return M
end
do
  local NAME = "Final Plan"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local mm = Live(c).addons.EllesmereUIMinimap.minimap
  mm.position.y = mm.position.y - 80                     -- the minimap moved down
  local chat = Live(c).addons.EllesmereUIChat.chat
  chat.chatSize.w, chat.chatSize.h = chat.chatSize.w + 60, chat.chatSize.h + 40   -- chat made bigger
  local plan = L.Plan(V1, CLASSIC)
  local f = plan.final
  Check(f and not f.exact, "C. an update that keeps the player's placements has a final plan that isn't the recommended one")
  local units = {}
  for _, it in ipairs(f.retained) do units[it.unit] = it end
  Check(units[MINIMAP_U] and units["ellesmereui:pos.chat"], "   the minimap and chat are listed as kept where the player has them")
  local rec, fin = plan.geometry.components, f.geometry.components
  Check(fin.minimap.kept and math.abs(fin.minimap.rect.y - (rec.minimap.rect.y - 80)) < 1.01, "   the final minimap is where the player put it, not the layout's")
  Check(fin.chat.kept and math.abs(fin.chat.rect.w - (rec.chat.rect.w + 60)) < 1.01 and math.abs(fin.chat.rect.h - (rec.chat.rect.h + 40)) < 1.01,
    "   and the final chat is the player's size")
  local before = { eui = Copy(c.EllesmereUIDB), tw = Copy(c.TwichUIDB) }
  local M = Review(c)
  local r = M.Review()
  Check(r.fit.exact == false and r.fit.retained and r.fit.retained:find("Minimap", 1, true) and r.fit.retained:find("Chat", 1, true),
    "   Review says what is kept where the player has it")
  local scene = M.Scene()
  local drawnChat
  for _, comp in ipairs(scene.components) do if comp.id == "chat" then drawnChat = comp end end
  Check(drawnChat and math.abs(drawnChat.rect.w - fin.chat.rect.w) < 0.01, "   the Review preview draws the player's chat, not the layout's")
  Check(M.SceneNote() and M.SceneNote():find("Shown as Apply leaves it", 1, true), "   and its caption says it shows what Apply leaves")
  Check(Same(before.eui, c.EllesmereUIDB) and Same(before.tw, c.TwichUIDB), "   planning and drawing the final plan change no profile")
  M.Go(2)
  Check(M.SceneNote() == nil, "   the layout step keeps the recommended preview")
  -- a kept chat moved over the block: the final plan doesn't fit, though the recommended one does; it is never moved
  chat.chatPosition.x = chat.chatPosition.x + 700
  M.End()
  M = Review(c)
  r = M.Review()
  Check(r.fit.recommendedFits and not r.fit.fits and #r.fit.lines > 0, "   a kept chat over the block: the final plan doesn't fit (the recommended one does)")
  local p2 = L.Plan(V1, CLASSIC)
  Check(math.abs(p2.parts.ellesmereui.payload.data.addons.EllesmereUIChat.chat.chatPosition.x - chat.chatPosition.x) < 0.01,
    "   and the player's chat isn't moved to clear it")
  M.End()
end

do
  -- a kept layout group, and EllesmereUI kept as it is
  local NAME = "Final Whole"
  local c = Install(NAME, LM.Boot(NAME, nil, { eui = EUI }), V1, CLASSIC)
  local L = Engine(c)
  local live = Live(c)
  live.addons.EllesmereUIActionBars.barPositions.Bar5.x = live.addons.EllesmereUIActionBars.barPositions.Bar5.x + 30   -- in the group
  local V2 = Publish(2, function(p)
    local a = p.layers.variants[CLASSIC].ellesmereui.layout.anchors.Bar2
    a.offsetY = (a.offsetY or 0) + 4
  end)
  local plan = L.Plan(V2, CLASSIC)
  local inGroup = false
  for _, it in ipairs(plan.final.retained) do if it.unit == "ellesmereui:pos.bar-5" then inGroup = true end end
  Check(plan.update.groups.layout and plan.update.groups.layout.choice == "mine" and inGroup, "C. a group kept as mine: its members are listed as kept")
  -- another vintage and an opaque change of the player's: EllesmereUI kept as it is
  live._migrations = Copy(live._migrations or {})
  live._migrations.laterMigration = true
  live.addons.EllesmereUIBags.mine = 1
  local pw = L.Plan(V2, CLASSIC)
  Check(pw.update.whole.ellesmereui and pw.update.whole.ellesmereui.choice == "keep" and pw.final.whole[1] == "ellesmereui" and not pw.final.exact,
    "   EllesmereUI kept as it is: the final plan says its placement is the player's")
  local M = Review(c)
  Check(M.Review().fit.retained:find("EllesmereUI is kept as you have it", 1, true), "   and Review says so instead of claiming the layout's fit")
  M.End()
end

---------------------------------------------------------------------------
-- D. Screen coverage: the objective tracker is illustrative only; pieces outside their box are checked (Compact's pet frame
--    and stance bar over Chat on 16:9); overlaps on the author's own canvas are the author's arrangement; scale guidance
---------------------------------------------------------------------------
do
  local G = L0.Geometry
  local geo = G.Resolve(PKG.geometry, { w = 2133.33, h = 1200 }, { variant = CLASSIC })
  Check(geo.fits, "D. Classic fits 1920 x 1080 at 0.64")
  local over = G.WithRects(geo, { objectives = geo.components.central.rect })
  local ill = false
  for _, d in ipairs(over.diagnostics) do if d.id == "objectives" or d.other == "objectives" then ill = d.illustrative == true end end
  Check(over.fits and ill, "   the objective tracker over the block is illustrative (Edit Mode places it): not counted against the fit")
  Check(not G.WithRects(geo, { chat = geo.components.central.rect }).fits, "   chat over the block is")
  local fc = L0.Fit(PKG, CLASSIC, geo)
  Check(fc.fits and fc.clear and #fc.issues == 0, "   Classic's pieces are clear of each other on that screen")
  local gk = G.Resolve(PKG.geometry, { w = 2133.33, h = 1200 }, { variant = COMPACT })
  local fk = L0.Fit(PKG, COMPACT, gk)
  local pet, stance = false, false
  for _, it in ipairs(fk.issues) do
    if it.id == "uf-pet" and it.other == "chat" then pet = true end
    if it.id == "bar-stance" and it.other == "chat" then stance = true end
  end
  Check(gk.fits and not fk.clear and pet and stance, "   Compact: the boxes fit, but the pet frame and stance bar reach over Chat (said, not hidden)")
  local cv = G.Resolve(PKG.geometry, { w = 2866.67, h = 1200 }, { variant = COMPACT })
  Check(L0.Fit(PKG, COMPACT, cv).clear, "   nothing is reported on the author's own canvas")
  -- the battle resurrection timer is carried but not placed: named, never part of the fit
  local cB = LM.Boot("Unplaced", nil, { eui = EUI })
  local LB = Engine(cB)
  local pB = LB.Plan(V1, CLASSIC)
  local named = false
  for _, n in ipairs(pB.parts.ellesmereui.notes) do if n.code == "unplaced" and n.id == "battle-res" then named = true end end
  Check(named, "   the battle resurrection timer is named as not placed")
  -- scale guidance, and the UI scale read correctly
  local c = LM.Boot("Scale", nil, { eui = EUI, screen = { w = 1365.33, h = 768, physW = 1920, physH = 1080, scale = 1.40625 } })
  assert(c.C_AddOns.LoadAddOn("TwichUI_LayoutWizard"))
  local M = c.TwichUI.LayoutWizard.Model
  assert(M.Begin())
  local screen = M.Screen()
  Check(math.abs(M.UIScale(screen) - 1.0) < 0.001 and M.ScreenText(screen):find("UI scale 1.00", 1, true), "   1920 x 1080 at UI scale 1.0 reads as UI scale 1.00")
  local layout = M.Layout()
  local sc = M.ScaleHint(layout, screen, "standard")
  Check(sc and sc < 1 and sc >= M.MIN_SCALE, "   Classic doesn't fit there; it fits at a UI scale of " .. tostring(sc) .. " or smaller")
  local at = G.Resolve(PKG.geometry, { w = 1920 * (768 / sc) / 1080, h = 768 / sc }, { variant = layout.variant })
  Check(at and at.fits, "   and it really does fit at that scale")
  local compat = M.Compat()
  local line
  for _, x in ipairs(compat) do if x.id == "screen" then line = x.detail end end
  Check(line and line:find(("UI scale of %.2f"):format(sc), 1, true), "   the welcome step says so")
  local author = LM.Boot("Author Screen", nil, { eui = EUI, screen = { w = 2866.67, h = 1200, physW = 3440, physH = 1440, scale = 1.2 } })
  assert(author.C_AddOns.LoadAddOn("TwichUI_LayoutWizard"))
  local MA = author.TwichUI.LayoutWizard.Model
  Check(MA.ScreenText(MA.Screen()):find("UI scale 0.64", 1, true), "   the author's 3440 x 1440 at 0.64 reads as UI scale 0.64 (not its effective scale)")
  M.End()
end

---------------------------------------------------------------------------
-- M. Portable media: the package TwichUI ships names only files every player has (TwichUI's own, in the list it keeps;
--    EllesmereUI's; the game's). The release workflow runs these tests, so a private path is a release failure, not a warning.
---------------------------------------------------------------------------
do
  local refs = L0.Pub.Refs(PKG)
  local bad = {}
  for _, r in ipairs(refs) do
    if r.source == "foreign" or r.source == "unsafe" then bad[#bad + 1] = r.path
    elseif r.source == "twichui" and L0.Pub.BundledKind(r.path) and not L0.Pub.Bundled(r.path) then bad[#bad + 1] = r.path end
  end
  Check(#refs > 0 and #bad == 0, "M. every file the shipped package names is one players have: " .. table.concat(bad, ", "))
  local font = PKG.layers.base.ellesmereui.root.fonts.unitNameFontPath
  Check(font and font:find("!!!TwichUI", 1, true) and L0.Pub.Bundled(font), "   the unit-name font is TwichUI's own copy (it was the author's private MyFonts folder)")
end

---------------------------------------------------------------------------
-- P. A published package and the bundled one: made by two different paths, compared by what they resolve to (every layout,
--    every choice), apart from their names, revisions and developer flag
---------------------------------------------------------------------------
do
  local Pub = L0.Pub
  local same = Pub.Compare(V1, PKG)
  Check(same and same.same and same.identity[1] == same.identity[2], "P. a publication of the bundled package resolves the same as it")
  local mf = {}
  for _, m in ipairs(same.meta) do mf[m.field] = true end
  Check(mf.revision and mf.dev, "   and the differences that don't change what it resolves to are listed apart (revision, developer flag)")
  local V2 = Publish(2, function(p)
    p.layers.base.twichui.groups.navigation.navigation.font = "Cinzel"
    p.layers.variants[COMPACT].ellesmereui.modules.EllesmereUIActionBars.twichTest = 1
    p.choices[2].options[3].ellesmereui.root.euiAccent.custom.r = 0.1
  end)
  local d = Pub.Compare(V2, PKG)
  local parts = {}
  for _, x in ipairs(d.differ) do parts[x.part] = x end
  Check(not d.same and parts["layer:base"] and parts["layer:base"].units[1] == "twichui|" .. NAV_U, "   a shared setting changed: the base differs, at that setting")
  Check(parts["layer:variant:" .. COMPACT] and not parts["layer:variant:" .. CLASSIC], "   a Compact-only change: only Compact's layer differs")
  Check(parts.choices ~= nil, "   a choice's option changed: the choices differ")
  local titled = Copy(PKG); titled.title = "Renamed"
  Check(Pub.Compare(titled, PKG).same, "   a new title alone resolves the same")
  local again = Pub.Contents(PKG)
  Check(again.identity == Pub.Contents(Copy(PKG)).identity, "   the identity is deterministic (a deep copy gives the same)")
end

if failures > 0 then print(failures .. " check(s) FAILED") os.exit(1) end
print("OK")
