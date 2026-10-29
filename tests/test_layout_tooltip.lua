dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- The two personal choices added to the layout wizard (docs/layouts/wizard.md, "Tooltip placement" and "Friendly player
-- nameplates"): the declared choices and their stable ids, what each writes and what it leaves alone, the account-wide tooltip flag
-- (snapshot, verification, update, Undo, Restore), the fixed tooltip place, the friendly-plate fields, plan staleness, older readers,
-- and a pick made for an install that already exists. TwichUI's code is the real one; EllesmereUI is the stand-in (layouts_mock.lua).
-- Nothing here is the game: docs/layouts/implementation-status.md lists the in-game checks.

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
local function Reload(name, c) return LM.Boot(name, LM.Logout(c), { eui = EUI }) end
local TARGET = "TwichUI Adventure"
local CURSOR_U, FIXED_U = "ellesmereui:tooltip.cursor", "ellesmereui:tooltip.fixedPos"
local CLASS_U = "ellesmereui:addons.EllesmereUINameplates.classColorFriendly"
local SHOW_U = "ellesmereui:addons.EllesmereUINameplates.showFriendlyPlayers"

local c0 = LM.Boot("Table", nil, { eui = EUI })
local L0 = Engine(c0)
local PKG, CLASSIC, COMPACT = L0.CLASSIC_PACKAGE, L0.CLASSIC_VARIANT, L0.COMPACT_VARIANT
local EA = L0.EllesmereAdapter

-- A game with a tooltip skin the recipient configured: every key of the account-wide bundle that matters, one explicitly false,
-- one never set, and a position in the profile in use.
local SKIN = { customTooltips = true, tooltipFontScale = 1.2, tooltipBgColor = { r = 0.1, g = 0.2, b = 0.3 }, tooltipCursorPosition = "right",
  tooltipCursorOffsetX = 14, tooltipCursorOffsetY = -6, tooltipGrowthDirection = "up", tooltipShowTarget = false, reskinMail = true }
local function Boot(name, cursor)
  local c = LM.Boot(name, nil, { eui = EUI })
  for k, v in pairs(SKIN) do c.EllesmereUIDB[k] = Copy(v) end
  c.EllesmereUIDB.tooltipAnchorCursor = cursor
  c.EllesmereUIDB.profiles.Mine.tooltipFixedPos = { centerX = 5, centerY = 6 }
  return c
end
local function SkinSame(c)
  for k, v in pairs(SKIN) do if not Same(c.EllesmereUIDB[k], v) then return false, k end end
  return c.EllesmereUIDB.tooltipShowMode == nil
end
local function Install(c, picks, variant)
  local L = Engine(c)
  local plan = L.Plan(PKG, variant or CLASSIC, { picks = picks })
  assert(plan.ok, "plan: " .. tostring(plan.blocked[1] and plan.blocked[1].code))
  local ok, res = L.Apply(PKG, variant or CLASSIC, plan.key, { picks = picks })
  assert(ok and res.state == "applied", "apply: " .. tostring(ok and res.state or res))
  return plan, res
end
local function Rows(plan) local out = {} for _, r in ipairs(plan.parts.ellesmereui.rows) do out[r.unit] = r end return out end
local function URows(plan) local out = {} for _, r in ipairs(plan.update and plan.update.rows or {}) do out[r.unit] = r end return out end

---------------------------------------------------------------------------
-- 1. The choices, their stable ids and what each writes
---------------------------------------------------------------------------
do
  local by = {}
  for _, ch in ipairs(PKG.choices) do by[ch.id] = ch end
  Check(#PKG.choices == 5 and #PKG.choices <= L0.MAX_CHOICES, "1. five choices, within the bound of " .. L0.MAX_CHOICES)
  local t, f = by.tooltip, by["friendly-plates"]
  Check(t and t.label == "Tooltip placement" and t.kind == "enum" and t.default == "layout", "    tooltip: labelled, an enum, Layout position by default")
  Check(t.options[1].id == "layout" and t.options[1].label == "Layout position" and t.options[2].id == "cursor" and t.options[2].label == "Follow mouse",
    "    tooltip options: stable ids layout and cursor, the wording asked for")
  Check(t.options[1].hint == "Show tooltips at this layout's configured location." and t.options[2].hint == "Keep tooltips near your cursor.", "    their explanations")
  Check(f and f.label == "Friendly player nameplates" and f.default == "class" and f.options[1].id == "class" and f.options[2].id == "blue"
    and f.options[1].label == "Class colors" and f.options[2].label == "Standard blue", "    friendly plates: ids class and blue, labels")
  Check(f.options[1].hint == "Use each friendly player's class color." and f.options[2].hint == "Use the standard blue appearance for friendly players.", "    their explanations")
  local ok, resolved = L0.Resolve(PKG, CLASSIC, { screen = { w = 2133.33, h = 1200 }, picks = { tooltip = "cursor", ["friendly-plates"] = "blue" } })
  local u = resolved.adapters.ellesmereui.units
  Check(ok and u[CURSOR_U] == true and u[FIXED_U] == nil, "    Follow mouse names the cursor flag and no place")
  Check(u[SHOW_U] == false and u[CLASS_U] == nil, "    Standard blue: EllesmereUI's friendly player nameplates off, and nothing else named")
  ok, resolved = L0.Resolve(PKG, CLASSIC, { screen = { w = 2133.33, h = 1200 }, picks = {} })
  u = resolved.adapters.ellesmereui.units
  Check(u[CURSOR_U] == false and Same(u[FIXED_U], { point = "CENTER", relPoint = "CENTER", x = 900.83, y = -496.67 }), "    the defaults: the author's tooltip place, not following the mouse")
  Check(u[CLASS_U] == true and u[SHOW_U] == true, "    and Class colors: EllesmereUI manages them, with class colours")
  Check(PKG.format == 6 and L0.FORMAT == 6, "    the package is format 6 (its presets are editable; this TwichUI reads format 6)")
  -- an older reader (format 4) refuses the fragment instead of misreading it
  local old = Copy(PKG); old.format = 4
  local okOld, problems = L0.Validate(old)
  local found
  for _, p in ipairs(problems or {}) do if p.code == "not-yet" and tostring(p.where):find("tooltip") then found = true end end
  Check(not okOld and found, "    a reader of format 4 refuses the tooltip fragment (not-yet)")
  -- only a wizard choice may name it
  local bad = Copy(PKG)
  bad.layers.base.ellesmereui.tooltip = { cursor = true }
  local okBad, pb = L0.Validate(bad)
  found = false
  for _, p in ipairs(pb or {}) do if p.code == "not-managed" then found = true end end
  Check(not okBad and found, "    the base layer may not set the tooltip")
  local junk = Copy(PKG)
  junk.choices[3].options[1].ellesmereui.tooltip.cursor = "yes"
  local okJ = L0.Validate(junk)
  Check(not okJ, "    a cursor flag that isn't a boolean is refused")
  junk = Copy(PKG)
  junk.choices[3].options[1].ellesmereui.tooltip.other = 1
  Check(not L0.Validate(junk), "    an unknown tooltip field is refused")
  junk = Copy(PKG)
  junk.choices[4].options[2].ellesmereui.fields["nameplates.showFriendlyPlayers"] = "no"
  Check(not L0.Validate(junk), "    a flag that isn't a boolean is refused")
  junk = Copy(PKG)
  junk.choices[4].options[2].ellesmereui.fields["nameplates.friendlyBarColor"] = { r = 1, g = 0, b = 0 }
  Check(not L0.Validate(junk), "    a field that isn't allowlisted (the bar colour) is refused")
end

---------------------------------------------------------------------------
-- 2. Planning and previewing change nothing; the plan names the account-wide change and the place
---------------------------------------------------------------------------
do
  local c = Boot("Plan", true)
  local L = Engine(c)
  local before = Copy(c.EllesmereUIDB)
  local plan = L.Plan(PKG, CLASSIC, { picks = {} })
  Check(plan.ok and Same(c.EllesmereUIDB, before), "2. planning leaves EllesmereUIDB exactly as it was")
  local r = Rows(plan)
  Check(r[CURSOR_U] and r[CURSOR_U].account and r[CURSOR_U].old == true and r[CURSOR_U].new == false and r[CURSOR_U].change,
    "    the plan says the account-wide flag goes from following the mouse to the layout's place")
  Check(r[FIXED_U] and r[FIXED_U].tip and r[FIXED_U].old.x == 5 and r[FIXED_U].new.x ~= 5 and r[FIXED_U].change, "    and the place changes from where it is to where the layout puts it")
  Check(plan.parts.ellesmereui.tip.cursor.want == false and plan.parts.ellesmereui.tip.fixed.write.centerX == r[FIXED_U].new.x,
    "    what Apply will write is in the plan")
  local plan2 = L.Plan(PKG, CLASSIC, { picks = {} })
  Check(plan2.key == plan.key, "    the same inputs give the same key")
  c.EllesmereUIDB.tooltipAnchorCursor = false
  local plan3 = L.Plan(PKG, CLASSIC, { picks = {} })
  Check(plan3.key ~= plan.key, "    a live change to the flag after the plan was shown makes it stale")
  local ok, why = L.Apply(PKG, CLASSIC, plan.key, { picks = {} })
  Check(not ok and why == "stale", "    and Apply refuses the old key (" .. tostring(why) .. ")")
  Check(c.EllesmereUIDB.tooltipAnchorCursor == false and c.EllesmereUIDB.profiles[TARGET] == nil, "    nothing was written")
  c.EllesmereUIDB.tooltipAnchorCursor = true
  local p4 = L.Plan(PKG, CLASSIC, { picks = {} })
  c.EllesmereUIDB.profiles.Mine.tooltipFixedPos = { centerX = 99, centerY = 6 }
  Check(L.Plan(PKG, CLASSIC, { picks = {} }).key ~= p4.key, "    so does a change to the tooltip place in the profile in use")
end

---------------------------------------------------------------------------
-- 3. Layout position: the author's place, placed for this screen, written to the install's own profile; the account-wide bundle
--    keeps every other value, set or absent
---------------------------------------------------------------------------
do
  local c = Boot("Layout", true)
  local plan = Install(c, { tooltip = "layout" })
  local prof = c.EllesmereUIDB.profiles[TARGET]
  local want = plan.parts.ellesmereui.tip.fixed.write
  Check(c.EllesmereUIDB.tooltipAnchorCursor == false, "3. Layout position turns cursor-following off")
  Check(prof.tooltipFixedPos and prof.tooltipFixedPos.centerX == want.centerX and prof.tooltipFixedPos.centerY == want.centerY and want.centerX ~= 5,
    "    the layout's place is in the install's own profile, not the one the recipient had")
  Check(c.EllesmereUIDB.profiles.Mine.tooltipFixedPos.centerX == 5, "    their own profile keeps its place")
  local same, key = SkinSame(c)
  Check(same, "    every other value of the tooltip skin is as it was, the unset ones still unset (" .. tostring(key) .. ")")
  Check(c.EllesmereUIDB.tooltipCursorOffsetX == 14 and c.EllesmereUIDB.tooltipGrowthDirection == "up", "    including the cursor offsets and the growth direction")
  c = Reload("Layout", c)
  local L = Engine(c)
  local j = L.Journal.Read()
  Check(j.state == "verified", "    the check after the reload matches (" .. tostring(j.state) .. ")")
  Check(j.expect.ellesmereui[CURSOR_U] == L0.Fingerprint(false) and j.expect.ellesmereui[FIXED_U]:match("^@%-?%d+,%-?%d+$"), "    the flag and the place are read back by value")
  local base = L.Journal.ReadBaseline().parts.ellesmereui.units
  Check(base[CURSOR_U] and base[FIXED_U], "    and both are tracked in the baseline")
end

---------------------------------------------------------------------------
-- 4. Follow mouse: the flag alone; no place is written, nothing of the skin changes
---------------------------------------------------------------------------
do
  local c = Boot("Cursor", false)
  local before = Copy(c.EllesmereUIDB)
  local plan = Install(c, { tooltip = "cursor" })
  Check(c.EllesmereUIDB.tooltipAnchorCursor == true, "4. Follow mouse sets the account-wide flag")
  Check(plan.parts.ellesmereui.tip.fixed == nil and c.EllesmereUIDB.profiles[TARGET].tooltipFixedPos.centerX == 5,
    "    no place is written: the install's profile starts from the one the recipient had, as EllesmereUI's import does")
  Check(SkinSame(c), "    no other tooltip setting changed (cursor position, offsets, growth, skin)")
  local keys = {}
  for k in pairs(c.EllesmereUIDB) do if not Same(c.EllesmereUIDB[k], before[k]) then keys[#keys + 1] = k end end
  table.sort(keys)
  Check(table.concat(keys, ",") == "activeProfile,profileOrder,profiles,tooltipAnchorCursor", "    the account store changed in the flag and the profile list only (" .. table.concat(keys, ",") .. ")")
  c = Reload("Cursor", c)
  Check(Engine(c).Journal.Read().state == "verified", "    verified after the reload")
  -- an explicit false and a never-set key are different stores but the same setting: no write is made when nothing differs
  local c2 = Boot("Same", false)
  local p2 = Engine(c2).Plan(PKG, CLASSIC, { picks = { tooltip = "layout" } })
  Check(p2.parts.ellesmereui.tip.cursor == nil and not Rows(p2)[CURSOR_U].change, "    already off: the flag is not written")
  local c3 = Boot("Unset", nil)
  local p3 = Engine(c3).Plan(PKG, CLASSIC, { picks = { tooltip = "layout" } })
  Check(p3.parts.ellesmereui.tip.cursor == nil, "    never set reads as off: not written either")
end

---------------------------------------------------------------------------
-- 5. Restore puts the account-wide flag back as it was, absent stays absent; a flag the player changed since is left
---------------------------------------------------------------------------
do
  for _, case in ipairs({ { "was absent", nil }, { "was explicitly off", false }, { "was on", true } }) do
    local want = case[2]
    local pick = want == true and "layout" or "cursor"
    local c = Boot("Restore", want)
    Install(c, { tooltip = pick })
    c = Reload("Restore", c)
    local L = Engine(c)
    local pr = L.PlanRestore()
    Check(pr.ok, "5. Restore plans (" .. case[1] .. ")")
    local ok, res = L.Restore(pr.key)
    Check(ok and res.state ~= "failed", "    Restore runs")
    Check(c.EllesmereUIDB.tooltipAnchorCursor == want, "    " .. case[1] .. ": the flag is back as it was (" .. tostring(c.EllesmereUIDB.tooltipAnchorCursor) .. ")")
    c = Reload("Restore", c)
    L = Engine(c)
    local j = L.Journal.Read()
    Check(c.EllesmereUIDB.profiles[TARGET] == nil and (j == nil or j.state == "restored"), "    the install's profile, with its tooltip place, is gone")
    Check(SkinSame(c), "    the rest of the skin was never touched")
  end
  -- changed since the install: left as the player has it
  local c = Boot("Changed", false)
  Install(c, { tooltip = "cursor" })
  c = Reload("Changed", c)
  c.EllesmereUIDB.tooltipAnchorCursor = false          -- the player turned it back off in EllesmereUI
  local L = Engine(c)
  local pr = L.PlanRestore()
  local kept
  for _, a in ipairs(pr.parts.ellesmereui.actions) do if a.kind == "account-kept" or a.kind == "account" then kept = a.kind end end
  Check(kept == nil, "    a flag already as it was before: nothing to put back")
  c.EllesmereUIDB.tooltipAnchorCursor = nil
  c.EllesmereUIDB.tooltipAnchorCursor = true           -- on, as the install left it: restored
  local c2 = Boot("Changed2", false)
  Install(c2, { tooltip = "layout" })                  -- the install leaves it off (as it was): nothing to restore either way
  local c3 = Boot("Changed3", true)
  Install(c3, { tooltip = "layout" })                  -- the install turns it off
  c3 = Reload("Changed3", c3)
  c3.EllesmereUIDB.tooltipAnchorCursor = true          -- the player turned it on again afterwards
  local L3 = Engine(c3)
  local pr3 = L3.PlanRestore()
  local k3
  for _, a in ipairs(pr3.parts.ellesmereui.actions) do if a.kind:find("^account") then k3 = a.kind end end
  Check(k3 == nil, "    a flag the player has already put back to its old value needs no write")
  local c4 = Boot("Changed4", true)
  Install(c4, { tooltip = "cursor" })                  -- on, left on
  local c5 = Boot("Changed5", false)
  Install(c5, { tooltip = "cursor" })                  -- the install turns it on
  c5 = Reload("Changed5", c5)
  c5.EllesmereUIDB.tooltipAnchorCursor = nil           -- the player cleared it themselves: the same as the original
  local pr5 = Engine(c5).PlanRestore()
  local k5
  for _, a in ipairs(pr5.parts.ellesmereui.actions) do if a.kind:find("^account") then k5 = a.kind end end
  Check(k5 == nil, "    already reading as before: nothing is written")
end

---------------------------------------------------------------------------
-- 6. Friendly player nameplates: the two fields and nothing else of the module's blob
---------------------------------------------------------------------------
local AUTHOR = PKG.layers.base.ellesmereui.modules.EllesmereUINameplates
do
  local c = Boot("Plates", nil)
  Install(c, { ["friendly-plates"] = "blue" })
  local blob = c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUINameplates
  Check(blob.showFriendlyPlayers == false, "6. Standard blue turns EllesmereUI's friendly player nameplates off")
  local diff = {}
  for k, v in pairs(AUTHOR) do if not Same(blob[k], v) then diff[#diff + 1] = k end end
  for k in pairs(blob) do if AUTHOR[k] == nil then diff[#diff + 1] = k end end
  table.sort(diff)
  Check(table.concat(diff, ",") == "showFriendlyPlayers", "    nothing else of the blob differs from the layout's own (" .. table.concat(diff, ",") .. ")")
  Check(Same(blob.friendlyNPCColor, AUTHOR.friendlyNPCColor) and blob.classColorFriendly == AUTHOR.classColorFriendly
    and blob.friendlyNameOnly == AUTHOR.friendlyNameOnly and Same(blob.friendlyBarColor, AUTHOR.friendlyBarColor),
    "    friendly NPC colours, class colours, name-only mode and the bar colour are the layout's, not set by the choice")
  c = Reload("Plates", c)
  local L = Engine(c)
  Check(L.Journal.Read().state == "verified" and L.Journal.Read().expect.ellesmereui[SHOW_U] == L0.Fingerprint(false), "    verified after the reload, by value")
  c.EllesmereUIDB.profiles[TARGET].addons.EllesmereUINameplates.showFriendlyPlayers = true
  local report = L.Verify(false)
  local differs
  for _, d in ipairs(report.adapters.ellesmereui.diffs) do if d.unit == SHOW_U then differs = true end end
  Check(report.state == "mismatch" and differs, "    switched back on afterwards is reported, not repaired")

  local c2 = Boot("PlatesClass", nil)
  Install(c2, { ["friendly-plates"] = "class" })
  local b2 = c2.EllesmereUIDB.profiles[TARGET].addons.EllesmereUINameplates
  Check(b2.classColorFriendly == true and b2.showFriendlyPlayers == true, "    Class colors: EllesmereUI manages them, class colours on")
  -- the account's custom colours and other profiles are not touched
  local c3 = Boot("PlatesOthers", nil)
  c3.EllesmereUIDB.customColors = { class = { WARRIOR = { r = 1, g = 0, b = 0 } } }
  c3.EllesmereUIDB.profiles.Raid.addons.EllesmereUINameplates.showFriendlyPlayers = true
  local before = Copy(c3.EllesmereUIDB.profiles.Raid)
  Install(c3, { ["friendly-plates"] = "blue" })
  Check(Same(c3.EllesmereUIDB.customColors, { class = { WARRIOR = { r = 1, g = 0, b = 0 } } }) and Same(c3.EllesmereUIDB.profiles.Raid, before),
    "    the custom colour palette and the recipient's other profiles are untouched")
  -- Restore: the install's profile, with the switch, is gone; the recipient's profile in use never changed
  c3 = Reload("PlatesOthers", c3)
  local L3 = Engine(c3)
  local pr = L3.PlanRestore()
  L3.Restore(pr.key)
  Check(c3.EllesmereUIDB.profiles[TARGET] == nil and c3.EllesmereUIDB.activeProfile == "Mine", "    Restore removes the install's profile and goes back to theirs")
end

---------------------------------------------------------------------------
-- 7. Updates: what the recipient set is kept, an explicit pick has a clear effect, Undo and Restore
---------------------------------------------------------------------------
do
  local c = Boot("Update", nil)
  Install(c, { tooltip = "layout", ["friendly-plates"] = "class" })
  c = Reload("Update", c)
  local L = Engine(c)
  Check(L.Journal.Read().state == "verified", "7. installed and checked")
  local prof = c.EllesmereUIDB.profiles[TARGET]
  local layoutPlace = Copy(prof.tooltipFixedPos)
  prof.tooltipFixedPos = { centerX = 123, centerY = -77 }                       -- the recipient moved the tooltip in Unlock Mode
  -- the same picks again: nothing the recipient set is lost
  local plan = L.Plan(PKG, CLASSIC, { picks = { tooltip = "layout", ["friendly-plates"] = "class" } })
  local r = URows(plan)[FIXED_U]
  Check(r and r.case == "mine" and r.decision == "keep", "    a moved tooltip is seen as theirs and kept (" .. tostring(r and r.case) .. "/" .. tostring(r and r.decision) .. ")")
  Check(plan.parts.ellesmereui.tip.fixed.write.centerX == 123, "    and is what the new profile is written with")
  -- recommended configuration puts the layout's place back
  local rec = L.Plan(PKG, CLASSIC, { picks = { tooltip = "layout" }, update = { policy = "recommended" } })
  Check(rec.parts.ellesmereui.tip.fixed.write.centerX == layoutPlace.centerX, "    the recommended configuration writes the layout's place")
  -- an explicit new pick: Follow mouse. The flag changes; the recipient's place is carried over untouched
  local p2 = L.Plan(PKG, CLASSIC, { picks = { tooltip = "cursor", ["friendly-plates"] = "class" } })
  local ur = URows(p2)
  Check(ur[CURSOR_U] and ur[CURSOR_U].decision == "apply" and Rows(p2)[CURSOR_U].new == true and Rows(p2)[CURSOR_U].change,
    "    picking Follow mouse changes the flag (a clear row in the plan)")
  Check(p2.parts.ellesmereui.tip.fixed.write.centerX == 123, "    and the place they set stays where it is")
  local ok, res = L.Apply(PKG, CLASSIC, p2.key, { picks = { tooltip = "cursor", ["friendly-plates"] = "class" } })
  Check(ok and res.state == "applied", "    the update applies")
  Check(c.EllesmereUIDB.tooltipAnchorCursor == true and c.EllesmereUIDB.profiles[TARGET].tooltipFixedPos.centerX == 123, "    flag on; their place carried into the new profile")
  c = Reload("Update", c)
  L = Engine(c)
  Check(L.Journal.Read().state == "verified", "    verified after the reload")
  -- Undo this update: the flag and the old profile (with its place) come back
  local up = L.PlanUndo()
  Check(up.ok, "    Undo this update plans")
  local acts = {}
  for _, a in ipairs(up.parts.ellesmereui.actions) do acts[#acts + 1] = a.kind end
  Check(acts[#acts] == "account", "    and puts the account-wide flag back")
  local okU, resU = L.Undo(up.key)
  Check(okU and resU.state ~= "failed", "    Undo runs")
  Check(c.EllesmereUIDB.tooltipAnchorCursor == false or c.EllesmereUIDB.tooltipAnchorCursor == nil, "    the flag is off again")
  c = Reload("Update", c)
  L = Engine(c)
  Check(c.EllesmereUIDB.profiles[TARGET].tooltipFixedPos.centerX == 123, "    and the profile from before the update, with their place, is back")
  Check(L.Journal.Read().state == "verified", "    checked (" .. tostring(L.Journal.Read().state) .. ")")
  -- Undo leaves a flag the player changed since
  local p3 = L.Plan(PKG, CLASSIC, { picks = { tooltip = "cursor" } })
  L.Apply(PKG, CLASSIC, p3.key, { picks = { tooltip = "cursor" } })
  c = Reload("Update", c)
  L = Engine(c)
  c.EllesmereUIDB.tooltipAnchorCursor = nil     -- the player cleared it afterwards (reads as off)
  local up2 = L.PlanUndo()
  local kinds = {}
  for _, a in ipairs(up2.parts.ellesmereui.actions) do kinds[a.kind] = true end
  Check(not kinds.account, "    a flag already off is not written by Undo")
end

---------------------------------------------------------------------------
-- 8. A write that fails puts the profiles back; a flag the update newly manages is kept for Restore
---------------------------------------------------------------------------
do
  local c = Boot("Fail", true)
  local L = Engine(c)
  local plan = L.Plan(PKG, CLASSIC, { picks = { tooltip = "layout" } })
  local db = c.EllesmereUIDB
  local profilesBefore = {}
  for k in pairs(db.profiles) do profilesBefore[#profilesBefore + 1] = k end
  -- the account store refuses the flag
  local proxy = setmetatable({}, { __index = db, __newindex = function(t, k, v) if k == "tooltipAnchorCursor" then return end rawset(db, k, v) end })
  c.EllesmereUIDB = proxy
  local okA, res = pcall(L.Apply, PKG, CLASSIC, plan.key, { picks = { tooltip = "layout" } })
  c.EllesmereUIDB = db
  Check(okA, "8. a refused write does not raise")
  Check(db.profiles[TARGET] == nil and db.activeProfile == "Mine" and db.tooltipAnchorCursor == true, "    the install's profile is removed, the profile in use is back, the flag untouched (" .. tostring(db.profiles[TARGET]) .. ")")
  local j = L.Journal.Read()
  Check(j == nil or j.state ~= "verified", "    and nothing is recorded as installed")
end

---------------------------------------------------------------------------
-- 9. The wizard: a choice for a setup that already exists starts from what the game has; picking is the player's own
---------------------------------------------------------------------------
local function OpenWizard(c)
  c.SlashCmdList.TWICHUI("layout")
  return c.TwichUILayoutWizard, c.TwichUI.LayoutWizard
end
do
  -- a setup made before these choices existed: the record has no picks for them, the game has Follow mouse on and EllesmereUI's friendly plates off
  local c = Boot("Wiz", true)
  Install(c, { tooltip = "layout", ["friendly-plates"] = "class" })
  c = Reload("Wiz", c)
  local j = Engine(c).Journal.Read()
  j.picks.tooltip, j.picks["friendly-plates"] = nil, nil     -- as an install from before the choices would be
  Engine(c).Journal.Write(j)
  local function DropBaseline(cc) for _, u in ipairs({ CURSOR_U, FIXED_U, CLASS_U, SHOW_U }) do cc.TwichUIDB.layouts.baseline.parts.ellesmereui.units[u] = nil end end
  DropBaseline(c)
  c.EllesmereUIDB.tooltipAnchorCursor = true
  local prof = c.EllesmereUIDB.profiles[TARGET]
  prof.addons.EllesmereUINameplates.showFriendlyPlayers = false
  local win, WZ = OpenWizard(c)
  local MK = WZ.Model
  Check(MK.Pick("tooltip") == "cursor" and MK.Derived("tooltip"), "9. the tooltip pick is Follow mouse, read from the game, and marked as not the player's own")
  Check(MK.Pick("friendly-plates") == "blue" and MK.Derived("friendly-plates"), "    the plate pick is Standard blue, read from the game")
  Check(c.TwichUIDB.layouts.wizard == nil or (c.TwichUIDB.layouts.wizard.picks or {}).tooltip == nil, "    neither is remembered as a choice")
  local plan = MK.Plan()
  local rows = {}
  for _, r in ipairs(plan.parts.ellesmereui.rows) do rows[r.unit] = r end
  Check(plan.ok and not rows[CURSOR_U].change and not rows[SHOW_U].change, "    so the plan changes neither (" .. tostring(rows[CURSOR_U].change) .. ")")
  local before = Copy(c.EllesmereUIDB)
  MK.SetPick("tooltip", "layout")
  Check(not MK.Derived("tooltip") and Same(c.EllesmereUIDB, before), "    picking Layout position makes it theirs and changes nothing in the game yet")
  Check(c.TwichUIDB.layouts.wizard.picks.tooltip == "layout" and c.TwichUIDB.layouts.wizard.picks["friendly-plates"] == nil, "    and only that pick is remembered")
  plan = MK.Plan()
  rows = {}
  for _, r in ipairs(plan.parts.ellesmereui.rows) do rows[r.unit] = r end
  Check(rows[CURSOR_U].change and rows[CURSOR_U].new == false and rows[CURSOR_U].decision == "apply", "    the plan now turns the account-wide flag off, a clear row")
  Check(rows[FIXED_U].tip and rows[FIXED_U].new and plan.parts.ellesmereui.tip.fixed.write.centerX == rows[FIXED_U].new.x,
    "    and the layout's place is what the install's profile is written with")
  local review = MK.Review()
  local text = table.concat(review.ellesmereui.lines, "\n")
  Check(text:find("every character on this account", 1, true) and text:find("fixed place is set to", 1, true), "    the review names the account-wide effect and the place")
  local listed
  for _, p in ipairs(MK.Review().picks) do if p.id == "tooltip" then listed = p end end
  Check(listed and listed.choice == "Tooltip placement" and listed.option == "Layout position", "    and lists the choice")
  -- the ambiguous case: EllesmereUI's plates on with class colours off matches neither option; the default is shown as such and nothing is overwritten
  local c2 = Boot("WizAmb", nil)
  Install(c2, { ["friendly-plates"] = "class" })
  c2 = Reload("WizAmb", c2)
  local j2 = Engine(c2).Journal.Read()
  j2.picks["friendly-plates"] = nil
  Engine(c2).Journal.Write(j2)
  for _, u in ipairs({ CURSOR_U, FIXED_U, CLASS_U, SHOW_U }) do c2.TwichUIDB.layouts.baseline.parts.ellesmereui.units[u] = nil end
  local p2 = c2.EllesmereUIDB.profiles[TARGET].addons.EllesmereUINameplates
  p2.classColorFriendly = false
  local _, WZ2 = OpenWizard(c2)
  Check(WZ2.Model.Pick("friendly-plates") == "class" and WZ2.Model.Derived("friendly-plates"), "    no option matches class colours switched off: the default, marked as not chosen")
  local pl2 = WZ2.Model.Plan()
  local r2
  for _, r in ipairs(pl2.parts.ellesmereui.rows) do if r.unit == CLASS_U then r2 = r end end
  Check(r2 and r2.decision == "keep" and r2.new == false, "    and the plan keeps what the player has (" .. tostring(r2 and r2.decision) .. ")")
  WZ2.Model.SetPick("friendly-plates", "class")
  local pl3 = WZ2.Model.Plan()
  for _, r in ipairs(pl3.parts.ellesmereui.rows) do if r.unit == CLASS_U then r2 = r end end
  Check(r2.decision == "apply" and r2.new == true and r2.change, "    picking Class colors for themselves applies it")
  -- start over: the layout's own choices, asked for
  WZ2.Model.ResetPicks()
  Check(not WZ2.Model.Derived("friendly-plates") and WZ2.Model.Pick("friendly-plates") == "class", "    Start over gives the layout's own and clears the mark")
end

-- a new install defaults to what the layout recommends, whatever the game has
do
  local c = Boot("WizNew", true)
  local _, WZ = OpenWizard(c)
  local MK = WZ.Model
  Check(MK.Pick("tooltip") == "layout" and MK.Pick("friendly-plates") == "class" and not MK.Derived("tooltip"), "10. a new install: the layout's own recommendation, not the game's")
  Check(MK.Pick("size") == "standard" and MK.Pick("accent") == "gold", "    the other choices as before")
end

---------------------------------------------------------------------------
-- 11. The Personalize page and the previews: selecting changes nothing in the game; the tooltip sample follows the pointer only over
--     the miniature; friendly player samples; page sizing; no listener left behind
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
  b.scripts.OnClick(b)
end
do
  local c = Boot("Page", true)
  local win, WZ = OpenWizard(c)
  local MK, WW = WZ.Model, WZ.Window
  while MK.Step() < MK.PERSONALIZE do Click(win, MK.Step() == 1 and "Get started" or "Next") end
  local before = Copy(c.EllesmereUIDB)
  for _, label in ipairs({ "Tooltip placement", "Layout position", "Follow mouse", "Friendly player nameplates", "Class colors", "Standard blue" }) do
    Check(LM.Says(win, label), "11. the page says \"" .. label .. "\"")
  end
  Check(LM.Says(win, "Show tooltips at this layout's configured location.") and LM.Says(win, "Use each friendly player's class color."), "    with their explanations")
  local page = WW.pages[MK.PERSONALIZE]
  local g = page.groups.tooltip
  Check(g.cards[1].selected and not g.cards[2].selected and g.cards[1].selText.shown, "    Layout position is shown selected (a check, an outline and the word Selected, not colour alone)")
  Click(win, "Follow mouse")
  Check(MK.Pick("tooltip") == "cursor" and g.cards[2].selected and not g.cards[1].selected, "    choosing Follow mouse selects it")
  Click(win, "Standard blue")
  Check(MK.Pick("friendly-plates") == "blue" and page.groups["friendly-plates"].cards[2].selected, "    and Standard blue")
  Check(Same(c.EllesmereUIDB, before) and c.EllesmereUIDB.profiles[TARGET] == nil, "    and selecting changed nothing in the game")
  Check(c.TwichUIDB.layouts.wizard.picks.tooltip == "cursor" and c.TwichUIDB.layouts.wizard.picks["friendly-plates"] == "blue", "    the picks are remembered")
  -- the friendly player sample: synthetic; Standard blue is Blizzard's own plate (blue bars), Class colors is EllesmereUI's (names only here)
  local classCard, blueCard = page.groups["friendly-plates"].cards[1], page.groups["friendly-plates"].cards[2]
  Check(MK.PlatesMode() and MK.PlatesMode().nameOnly == true, "    this layout shows friendly players as names only")
  local bs = blueCard.samples
  Check(#bs == 3 and bs[1].bar.shown and bs[1].bar.color and math.abs(bs[1].bar.color[3] - 1) < 0.001 and bs[1].bar.color[1] < 0.7, "    Standard blue: a blue bar for each sample")
  Check(LM.Says(win, "Blizzard's nameplates draw friendly players") and LM.Says(win, "stays until you change it there"), "    and, while it is the pick, the page says Blizzard's draw them and what EllesmereUI left stays")
  local text = table.concat(MK.Review().ellesmereui.lines, "\n")
  Check(text:find("Show EUI Friendly Player Nameplates", 1, true) and text:find("Blizzard's own nameplates", 1, true) and text:find("stays until you change it there", 1, true),
    "    the review names the EllesmereUI toggle, hands the look to Blizzard's settings, and says what stays")
  Click(win, "Class colors")
  local cs = classCard.samples
  local classNames = cs[1].name.textColor
  Check(not cs[1].bar.shown and classNames and not (classNames[1] == 1 and classNames[2] == 1 and classNames[3] == 1), "    Class colors: the sample names are class coloured")
  Check(cs[1].name.text ~= cs[3].name.text and #cs == 3, "    with more than one sample, so the class colours can be compared")
  Check(not LM.Says(win, "Blizzard's nameplates draw friendly players"), "    and the note goes")
  -- sizing: the page grows with its content and is laid out inside the window's scroll area; the controls don't overlap the preview
  local h = page.frame:GetHeight()
  Check(h > 300 and h < 560, "    the page is " .. h .. " tall: compact, with every choice reachable")
  for _, id in ipairs({ "tooltip", "friendly-plates" }) do
    local gr = page.groups[id]
    for _, card in ipairs(gr.cards) do
      Check(card.w == 351 and card.points[1][2] == page.frame, "    a " .. id .. " card is half the page wide and placed in the page")
    end
  end
  -- repeated showing makes nothing new
  local made = c.made()
  for _ = 1, 8 do Click(win, "Follow mouse"); Click(win, "Layout position"); WW.Refresh() end
  Check(c.made() == made, "    picking and redrawing repeatedly makes no new frames")
end

do
  local c = Boot("Follow", false)
  local win, WZ = OpenWizard(c)
  local MK, WW = WZ.Model, WZ.Window
  while MK.Step() < MK.LAYOUT do Click(win, MK.Step() == 1 and "Get started" or "Next") end
  local pv = WW.pages[MK.LAYOUT].preview
  Click(win, "Tooltip")                                       -- the scenario tab
  local scene = MK.Scene()
  Check(scene.tooltip.mode == "layout" and not scene.tooltip.follow, "11. Layout position: the sample sits at the layout's place")
  local geo = MK.Preview()
  local place = L0.EllesmereAdapter.TipPlace({ point = "CENTER", relPoint = "CENTER", x = 900.83, y = -496.67 }, geo, L0.Geometry.Attach(PKG.geometry, CLASSIC).ellesmereui)
  local r = scene.tooltip.rect
  Check(r.r > place.x - 1 and r.r < place.x + 140 + 1 and r.b > place.y - 83 - 1 and r.b < place.y - 82 + 1 or (math.abs(r.r - (place.x + 140)) < 0.01 and math.abs(r.b - (place.y - 82.5)) < 0.01),
    "    drawn pinned to the corner of EllesmereUI's tooltip box (right " .. r.r .. ", bottom " .. r.b .. ")")
  Check(pv.drawn.tooltip and not pv.drawn.tooltip.follow and not pv.tracking, "    the miniature draws it, with no pointer tracking")
  local fixed = { x = r.x, y = r.y }
  MK.SetPick("tooltip", "cursor")
  WW.Refresh()
  scene = MK.Scene()
  Check(scene.tooltip.mode == "cursor" and scene.tooltip.follow and Same(MK.Preview() ~= nil and { true } or {}, { true }), "    Follow mouse: the sample follows the pointer")
  Check(math.abs(scene.tooltip.rect.x) < 0.01 and pv.drawn.tooltip.follow, "    and rests at the middle of the screen with the cursor marked")
  local tip = pv.boxes.tooltip
  Check(pv.follow and pv.frame.scripts.OnEnter and pv.frame.scripts.OnUpdate == nil, "    no OnUpdate exists until the pointer is over the miniature")
  local rest = { tip.points[1][4], tip.points[1][5] }
  -- the pointer enters: the sample follows it (inside the miniature)
  pv.frame.centerX, pv.frame.centerY = 500, 400
  c.GetCursorPosition = function() return 540, 410 end
  pv.frame.scripts.OnEnter(pv.frame)
  Check(pv.tracking and pv.frame.scripts.OnUpdate, "    over the miniature a throttled update runs")
  pv.frame.scripts.OnUpdate(pv.frame, 0.001)
  Check(tip.points[1][4] == rest[1] and tip.points[1][5] == rest[2], "    (an update inside the throttle does nothing)")
  pv.frame.scripts.OnUpdate(pv.frame, 0.05)
  Check(tip.points[1][1] == "BOTTOM" and tip.points[1][4] == 40 and tip.points[1][5] == 10, "    then the sample's bottom is at the pointer (" .. tostring(tip.points[1][4]) .. ", " .. tostring(tip.points[1][5]) .. ")")
  -- the pointer far outside is clamped to the miniature
  c.GetCursorPosition = function() return 5000, -5000 end
  pv.frame.scripts.OnUpdate(pv.frame, 0.05)
  Check(math.abs(tip.points[1][4]) <= pv.frame.w / 2 and math.abs(tip.points[1][5]) <= pv.frame.h / 2, "    clamped inside the miniature")
  -- the pointer leaves: the update is removed and the sample goes back to its rest place
  pv.frame.scripts.OnLeave(pv.frame)
  Check(not pv.tracking and pv.frame.scripts.OnUpdate == nil and tip.points[1][4] == rest[1] and tip.points[1][5] == rest[2], "    leaving removes the update and returns the sample to rest")
  -- hiding the page, another scenario, or closing also stop it
  pv.frame.scripts.OnEnter(pv.frame)
  Check(pv.tracking, "    entering again")
  Click(win, "Solo")
  Check(not pv.tracking and pv.frame.scripts.OnUpdate == nil, "    another scenario removes the update")
  Click(win, "Tooltip")
  pv.frame.scripts.OnEnter(pv.frame)
  pv.frame:Hide()
  Check(not pv.tracking and pv.frame.scripts.OnUpdate == nil, "    hiding the miniature removes it")
  pv.frame:Show()
  local ok = pcall(function() pv.frame.scripts.OnEnter(pv.frame) end)
  WW.Close()
  Check(not pv.tracking and pv.frame.scripts.OnUpdate == nil, "    closing the window leaves no update running")
  Check(c.EllesmereUIDB.tooltipAnchorCursor == false and not c.EllesmereUIDB.profiles[TARGET], "    and none of it touched the game's tooltip setting")
end

---------------------------------------------------------------------------
-- 12. The full-size preview stays inert with either pick; repeated installs and a step that fails after the first
---------------------------------------------------------------------------
do
  local c = Boot("Overlay", false)
  local win, WZ = OpenWizard(c)
  local MK, WW, OV = WZ.Model, WZ.Window, WZ.Overlay
  Click(win, "Get started")
  MK.SetPick("tooltip", "cursor")
  MK.SetScenario("tooltip")
  WW.Refresh()
  local before = Copy(c.EllesmereUIDB)
  Click(win, "See it full size")
  local root = c.TwichUILayoutOverlay
  Check(root and root.shown and root.mouse == false, "12. the full-size preview opens, taking no mouse")
  local tip = OV.panels.tooltip
  Check(tip and tip.shown and tip.tag.text == "Tooltip (sample)", "    with the sample tooltip, at rest (it never follows there)")
  Check(not tip.scripts.OnUpdate and not root.scripts.OnUpdate, "    and no pointer tracking of any kind")
  Check(Same(c.EllesmereUIDB, before), "    and nothing changed in the game")
  OV.Close("exit")
end

do
  -- the same picks again: nothing to apply; the snapshot from before the first install still stands
  local c = Boot("Repeat", true)
  Install(c, { tooltip = "layout" })
  c = Reload("Repeat", c)
  local L = Engine(c)
  local snap1 = Copy(L.Journal.Read().snapshot.ellesmereui)
  Check(snap1.account.cursor.had and snap1.account.cursor.v == true, "12. the first install records the flag as it was (on)")
  local again = L.Plan(PKG, CLASSIC, { picks = { tooltip = "layout" } })
  Check(again.parts.ellesmereui.nothing or not again.parts.ellesmereui.tip or not again.parts.ellesmereui.tip.cursor, "    the same install again writes no flag")
  -- a later update changes the pick: the first snapshot keeps its value from before the first install
  local p2 = L.Plan(PKG, CLASSIC, { picks = { tooltip = "cursor" } })
  local ok = L.Apply(PKG, CLASSIC, p2.key, { picks = { tooltip = "cursor" } })
  Check(ok, "    an update to Follow mouse applies")
  Check(Same(L.Journal.Read().snapshot.ellesmereui.account, snap1.account), "    and the snapshot is still from before the first install")
  -- a setup whose first install did not manage the flag (made before it was offered): the update keeps what it was just before
  local c2 = Boot("Newly", true)
  Install(c2, { tooltip = "layout" })
  c2 = Reload("Newly", c2)
  local L2 = Engine(c2)
  local j = L2.Journal.Read()
  j.snapshot.ellesmereui.account = nil
  L2.Journal.Write(j)
  c2.EllesmereUIDB.tooltipAnchorCursor = nil
  local p3 = L2.Plan(PKG, CLASSIC, { picks = { tooltip = "cursor" } })
  L2.Apply(PKG, CLASSIC, p3.key, { picks = { tooltip = "cursor" } })
  local acct = L2.Journal.Read().snapshot.ellesmereui.account
  Check(acct and acct.cursor and acct.cursor.had == false, "    a flag newly managed by an update is kept as it was just before (absent), for Restore")
  c2 = Reload("Newly", c2)
  local L2b = Engine(c2)
  local pr = L2b.PlanRestore()
  L2b.Restore(pr.key)
  Check(c2.EllesmereUIDB.tooltipAnchorCursor == nil, "    and Restore puts it back to absent")
end

do
  -- the TwichUI step fails after EllesmereUI's is done: the record is partial, and Restore puts the flag back
  local c = Boot("Partial", false)
  local L = Engine(c)
  local real = L.ADAPTERS.twichui.Apply
  L.ADAPTERS.twichui.Apply = function() return { state = "failed", code = "forced", rollback = "clean" } end
  local plan = L.Plan(PKG, CLASSIC, { picks = { tooltip = "cursor" } })
  local ok, res = L.Apply(PKG, CLASSIC, plan.key, { picks = { tooltip = "cursor" } })
  L.ADAPTERS.twichui.Apply = real
  Check(ok and res.state == "partial" and c.EllesmereUIDB.tooltipAnchorCursor == true, "12. a later step failing leaves the record partial, the flag as written")
  local pr = L.PlanRestore()
  local acts = {}
  for _, a in ipairs(pr.parts.ellesmereui.actions) do acts[#acts + 1] = a.kind end
  Check(pr.ok and acts[#acts] == "account", "    Restore is offered, and puts the flag back")
  local okR = L.Restore(pr.key)
  Check(okR and (c.EllesmereUIDB.tooltipAnchorCursor == false), "    the flag is back as it was (explicitly off)")
end

os.exit(failures == 0 and (print("LAYOUT TOOLTIP TESTS PASSED") or 0) or 1)
