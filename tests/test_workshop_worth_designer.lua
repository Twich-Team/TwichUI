-- The Workshop's "What's it worth?" tooltip designer (TwichUI_Settings/pages/WorkshopWorth.lua) over stand-in frames, with the real
-- Workshop layout code (WorthLayout.lua) behind it:
--   * before the Workshop is loaded: one sentence and one button; the button loads it through the launcher; nothing else loads it;
--   * the list, the mockup and the example / Normal / Hold Shift choices; the mockup is the SAME lines the tooltip builder makes;
--   * click-to-add, select, Move up / Move down, Remove, Always / Hold Shift, no duplicates, Enable tooltip, Reset layout;
--   * the drag handlers (OnDragStart / OnDragStop with a faked pointer position): add by drop, reorder by drop, a drop outside changes
--     nothing, the marker, the frame hiding mid-drag; these prove the handlers, NOT real pointer-driven dragging (docs/workshop.md);
--   * everything saves at once, a newer schema is left alone, redrawing makes no new controls.
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local function Same(a, b, msg) if a ~= b then failures = failures + 1; print("FAIL: " .. (msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a)) end end

local c = MIClient("Rich", {
  db = { modules = {} },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent) local fr = MIFake(kind, parent); if name then cl[name] = fr end return fr end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    cl.time = function() return 1000000 end
    cl.GetRealmName = function() return "Realm" end
    cl.GetCursorPosition = function() return 0, 0 end
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = {},
})
local R = c.TwichUI
c.TwichUIDB.ui = c.TwichUIDB.ui or {}
local made_frames, origCreate = {}, c.CreateFrame
c.CreateFrame = function(...) local fr = origCreate(...); made_frames[#made_frames + 1] = fr; return fr end

local function LoadAs(addon, file)
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk(addon, {})
end
-- the settings side: the Kit, the widgets, the virtual drag (Magic Inventory's, which the designer shares), the designer
R.MagicInventoryPage = {}
for _, file in ipairs({ "../TwichUI_Settings/Kit.lua", "../TwichUI_Settings/Widgets.lua", "../TwichUI_Settings/pages/MagicInventoryDrag.lua", "../TwichUI_Settings/pages/WorkshopWorth.lua" }) do
  LoadAs("TwichUI_Settings", file)
end
local D = R.WorkshopWorthDesigner
local WORKSHOP_FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Prices.lua", "Opportunities.lua",
  "Vendor.lua", "Shopping.lua", "Worth.lua", "WorthLayout.lua" }
-- the launcher: loading the Workshop is what makes R.Workshop exist (the real one calls LoadAddOn)
local loads, refuse = 0, nil
R.WorkshopLauncher = {
  Loaded = function() return R.Workshop ~= nil and R.Workshop.WorthLayout ~= nil end,
  Load = function()
    if refuse then return false, refuse end
    loads = loads + 1
    if not R.Workshop then for _, file in ipairs(WORKSHOP_FILES) do LoadAs("TwichUI_Workshop", "../TwichUI_Workshop/" .. file) end end
    return true
  end,
  Explain = function(code) return "couldn't open the Workshop: " .. tostring(code) end,
}
local function Flush() for _ = 1, 6 do FlushTimers() end end

local function Texts(frame, out)
  out = out or {}
  if type(frame.text) == "string" and frame.text ~= "" and frame.shown ~= false then out[#out + 1] = frame.text end
  for _, ch in ipairs(frame.children or {}) do if ch.shown ~= false then Texts(ch, out) end end
  return out
end
local function Has(frame, pattern) for _, t in ipairs(Texts(frame)) do if t:find(pattern, 1, true) then return true end end return false end
local function Click(b) Check(b and b.shown ~= false, "a control is there to click"); if b and b.scripts.OnClick then b.scripts.OnClick(b, "LeftButton") end end

-- what a mockup row shows, as the tooltip builder's text
local function RowText(fr)
  if fr.wide.shown ~= false and fr.wide.text ~= "" then return fr.wide.text end
  return fr.left.text .. " | " .. fr.right.text
end
local function Mock()   -- the rows shown, top to bottom
  local out = {}
  for i = 1, #D.Model().sec.rows do out[#out + 1] = RowText(D.Row(i)) end
  return out
end
local function Ids()
  local out = {}
  for _, e in ipairs(R.Workshop.WorthLayout.Get().lines) do out[#out + 1] = e.id .. (e.when == "shift" and "*" or "") end
  return table.concat(out, ",")
end
local DEFAULT = "recommend,vendor,auction,disenchant,status*,source*,note*"

---------------------------------------------------------------------------
-- Before the Workshop is loaded
---------------------------------------------------------------------------
local f = D.Frame()
Check(f ~= nil and D.Frame() == f, "one frame, made once")
f:Hide(); f:Show(); Flush()
Check(R.Workshop == nil, "showing the page loads nothing")
Check(Has(f, "needs the Workshop") and f.inviteButton.shown ~= false, "one sentence and one button")
Check(f.mock and f.mock.shown == false and D.ListButton(1) == nil, "no designer yet")
Same(loads, 0, "the Workshop is loaded only by the button")
refuse = "COMBAT"
Click(f.inviteButton); Flush()
Check(Has(f, "COMBAT") and R.Workshop == nil, "refused in combat: said, nothing loaded")
refuse = nil
Click(f.inviteButton); Flush()
Same(loads, 1, "loaded through the launcher")
Check(f.mock.shown ~= false and D.ListButton(8) ~= nil and f.inviteButton.shown == false, "the designer is there")
Check(not Has(f, "COMBAT"), "and the old message is gone")
local L = R.Workshop.WorthLayout

---------------------------------------------------------------------------
-- The list and the mockup
---------------------------------------------------------------------------
Same(Ids(), DEFAULT, "the short default")
for i, t in ipairs(L.TYPES) do Same(D.ListButton(i).label.text, t.label, "list: " .. t.label) end
Check(Has(f, "Drag lines into the preview."), "the one instruction")
Check(Has(f, "Preview data"), "the example values are labelled as preview data")
Check(Has(f, "Example item"), "the mockup is a tooltip")
for _, name in ipairs({ "Normal", "Hold Shift", "Enable tooltip", "Reset layout" }) do Check(Has(f, name), "control named " .. name) end
Check(f.enable:GetChecked() == true, "Enable tooltip is on by default")
Check(f.reset.enabled == false, "nothing to reset yet")
for i, t in ipairs(L.TYPES) do
  local added = L.IndexOf(L.Get().lines, t.id) ~= nil
  Check((D.ListButton(i).check.shown ~= false) == added, "check mark on " .. t.id .. " iff it is in the preview")
end

-- the mockup IS the tooltip builder's output: every example, both previews
local function Expect(exampleKey, shift)
  local r, ctx = L.Example(exampleKey)
  local sec = L.Rows(r, ctx, L.Get(), shift, true)
  local want = {}
  for _, row in ipairs(sec.rows) do
    if row.line then
      local kind, a, b = L.Style(row.line)
      want[#want + 1] = kind == "double" and (a .. " | " .. b) or a
    else
      want[#want + 1] = "(" .. L.BY_ID[row.id].label .. ": nothing to show for this example)"
    end
  end
  return table.concat(want, "\n")
end
for _, e in ipairs(L.EXAMPLES) do
  for _, shift in ipairs({ false, true }) do
    D.SetExample(e.key); D.SetMode(shift)
    Same(table.concat(Mock(), "\n"), Expect(e.key, shift), "preview rows = builder rows: " .. e.key .. (shift and " + Shift" or ""))
    Same(f.mock.title.text, "What's it worth?")
  end
end
D.SetExample("ordinary"); D.SetMode(false)
Same(table.concat(Mock(), "\n"), "Suggested: Vendor\nVendor | 500c\nAuction (before fees) | 400c\n(Disenchant value (average): nothing to show for this example)",
  "ordinary item, Normal") -- coin text is the fallback in this harness
Check(f.mock.hint.shown ~= false and f.mock.hint.text == "Hold Shift for details", "the hint in Normal")
D.SetMode(true)
Check(f.mock.hint.shown == false, "no hint while previewing Hold Shift")
Check(#Mock() == 7, "Hold Shift adds the Shift lines to the Always lines")
D.SetMode(false)
D.SetExample("missing")
Check(table.concat(Mock(), "\n"):find("More prices needed", 1, true) and table.concat(Mock(), "\n"):find("Auction | no price", 1, true), "missing prices")
D.SetExample("unavailable")
Check(table.concat(Mock(), "\n"):find("can't be listed (bound)", 1, true) and table.concat(Mock(), "\n"):find("Disenchant value unknown", 1, true), "an action that cannot be done, and an unknown value, side by side")
do   -- the dropdown's list: a value and a label each (what the shared menu draws)
  local choices = f.example.choices()
  Same(#choices, 4, "four examples")
  for i, e in ipairs(L.EXAMPLES) do Check(choices[i].value == e.key and choices[i].label == e.label, "example choice " .. e.key) end
  f.example.onPick("missing")   -- what picking an entry does
  Same(table.concat(Mock(), "\n"):find("More prices needed", 1, true) ~= nil, true, "picking an example redraws the mockup")
  f.example.onPick("ordinary")
end
D.SetExample("bogus"); Check(f.example.text ~= nil, "an unknown example reads as the first")
D.SetExample("ordinary")

---------------------------------------------------------------------------
-- Select, move, remove, visibility, click to add
---------------------------------------------------------------------------
Click(D.Row(2)); Same(D.Selected(), "vendor", "clicking a row selects it")
Check(f.selTitle.text == "Vendor value" and f.up.shown ~= false and f.up.enabled == true, "its controls appear")
Click(D.Row(2)); Same(D.Selected(), nil, "again deselects")
Check(f.up.shown == false and Has(f, "Click a line in the preview"), "and they go")
Click(D.Row(2))
Click(f.down); Same(Ids(), "recommend,auction,vendor,disenchant,status*,source*,note*", "Move down")
Click(f.up); Click(f.up); Same(Ids(), "vendor,recommend,auction,disenchant,status*,source*,note*", "Move up (twice)")
Check(f.up.enabled == false, "no further up from the top")
Click(f.down); Click(f.down)
-- steps are among the lines SHOWN: Normal skips the hidden Shift lines
D.Select("vendor"); D.Select("vendor")   -- clear
D.Select("disenchant")
Check(f.down.enabled == false, "Normal: nothing shown below it (the rest is Hold Shift only)")
D.SetMode(true)
Check(f.down.enabled == true, "Hold Shift preview: the Shift lines are shown, so it can step down")
D.SetMode(false)
-- visibility
D.Select("disenchant"); D.Select("vendor")
Same(D.Selected(), "vendor")
Click(f.holdShift)
Check(D.Mode() == true and Ids():find("vendor*", 1, true), "Hold Shift from Normal: the line goes, so the Hold Shift preview shows")
Check(Has(f, "Showing the Hold Shift preview"), "and says so")
Click(f.always); Check(not Ids():find("vendor*", 1, true), "back to Always")
D.SetMode(false)
-- remove
Click(f.remove); Same(D.Selected(), nil, "Remove clears the selection")
Check(not Ids():find("vendor", 1, true), "removed")
Check(D.ListButton(2).check.shown == false, "and it can be added again")
-- click to add: the end; Always in Normal; no duplicate
Click(D.ListButton(2)); Check(Ids():sub(-6) == "vendor", "click adds at the end: " .. Ids())
Same(D.Selected(), "vendor", "and selects it")
local before = Ids()
Check(D.AddLine("vendor") == false and Ids() == before and Has(f, "already in the preview"), "no duplicate line types")
Click(D.ListButton(2)); Same(D.Selected(), nil, "an added line's button selects it (toggle)")
D.AddLine("vendor")   -- selected again; no change
-- adding a detail line in the Hold Shift preview keeps its usual Hold Shift choice; in Normal it starts Always so it is seen
Click(D.ListButton(7)); Check(Ids():find("outcomes,", 1, true) or Ids():find("outcomes$"), "outcomes added")
Check(not Ids():find("outcomes*", 1, true), "added in Normal: Always, so it shows where you are looking")
D.RemoveLine("outcomes"); D.SetMode(true); D.AddLine("outcomes")
Check(Ids():find("outcomes*", 1, true), "added in the Hold Shift preview: its usual choice (Hold Shift)")
D.RemoveLine("outcomes"); D.SetMode(false)
Check(D.RemoveLine("outcomes") == false, "removing what is not there does nothing")

-- an empty place is still a row: the placeholder can be selected and removed
D.SetExample("ordinary")
local found
for i, row in ipairs(D.Model().sec.rows) do if row.id == "disenchant" then found = i end end
Check(found and D.Model().sec.rows[found].line == nil, "disenchant has nothing to say for an ordinary item")
Click(D.Row(found)); Same(D.Selected(), "disenchant", "its place can be selected")
D.Select("disenchant")

---------------------------------------------------------------------------
-- Enable tooltip and Reset layout
---------------------------------------------------------------------------
Check(not L.IsDefault() and f.reset.enabled == true, "Reset layout is available after a change")
Click(f.reset); Same(Ids(), DEFAULT, "Reset layout")
Check(f.reset.enabled == false and Has(f, "short default layout"), "and says so")
f.enable.scripts.OnClick(f.enable, "LeftButton")   -- the checkbox toggles itself, then tells the designer
Check(L.Enabled() == false and f.enable:GetChecked() == false, "Enable tooltip off")
D.AddLine("outcomes"); Click(f.reset)
Check(L.Enabled() == false, "Reset layout leaves Enable tooltip as it was")
f.enable.scripts.OnClick(f.enable, "LeftButton"); Check(L.Enabled() == true, "and back on")
Check(c.TwichUIDB.ui.workshopWorth ~= nil and c.TwichUIDB.ui.workshopWorth.v == 1, "saved in the profile's ui group at once")
Check(c.TwichUIDB.workshop == nil, "never in the account-wide Workshop record")

---------------------------------------------------------------------------
-- The drag handlers (not a pointer)
---------------------------------------------------------------------------
-- the mockup sits at the top left of a 1000 high screen; a pointer at rel pixels below its top
local mock = f.mock
mock.GetLeft = function() return 100 end; mock.GetRight = function() return 404 end
mock.GetTop = function() return 1000 end; mock.GetBottom = function() return 800 end
local cursor = { x = 0, y = 0 }
c.GetCursorPosition = function() return cursor.x, cursor.y end
local function Point(rel) cursor.x, cursor.y = 150, 1000 - rel end
local Drag = R.MagicInventoryPage.Drag
local function RowMid(i) local m = D.Model() return (m.tops[i] + m.bottoms[i]) / 2 end

D.SetMode(false)
D.RemoveLine("auction")
Same(Ids(), "recommend,vendor,disenchant,status*,source*,note*")
-- drag "Auction value" from the list and let go above the second row
local b = D.ListButton(3)
b.scripts.OnDragStart(b)
Check(Drag.Active(), "the drag starts")
Point(RowMid(2) - 1)   -- over the first half of row 2 (vendor): before it
Same(D.Find(), 1, "the gap before row 2")
Check(Drag.Source().kind == "list", "carrying a line from the list")
Drag.Stop()   -- OnDragStop does this
Same(Ids(), "recommend,auction,vendor,disenchant,status*,source*,note*", "dropped between the first two rows")
Check(not Drag.Active() and f.marker.shown == false, "the marker is gone")
-- the marker follows the pointer while it is held (the carried label's per-frame update asks where the pointer is)
do
  D.SetMode(false)
  local lb = D.ListButton(7)
  lb.scripts.OnDragStart(lb)
  local ghost
  for _, fr in ipairs(made_frames) do if fr.label and fr.tex and fr.scripts.OnUpdate then ghost = fr end end
  Check(ghost ~= nil and ghost.label.text == "Disenchant outcomes", "a label of the line follows the pointer")
  Point(RowMid(2) + 1)
  ghost.scripts.OnUpdate(ghost)
  local pt = f.marker.points[#f.marker.points]
  Check(f.marker.shown ~= false and pt and pt[5] == -D.Model().gaps[2], "the insertion marker is at the gap under the pointer")
  Point(RowMid(1) - 2)
  ghost.scripts.OnUpdate(ghost)
  pt = f.marker.points[#f.marker.points]
  Check(pt and pt[5] == -D.Model().gaps[0], "and it follows the pointer up")
  cursor.x, cursor.y = 5000, 5000
  ghost.scripts.OnUpdate(ghost)
  Check(f.marker.shown == false, "no marker outside the mockup")
  lb.scripts.OnDragStop(lb)
  Same(Ids(), "recommend,auction,vendor,disenchant,status*,source*,note*", "released outside: unchanged")
end
b = D.ListButton(7)   -- outcomes
b.scripts.OnDragStart(b)
Point(RowMid(1) - 2)
Same(D.Find(), 0, "the gap at the top")
Drag.Cancel()
Same(Ids(), "recommend,auction,vendor,disenchant,status*,source*,note*", "cancelled: nothing changed")
-- dropped outside the mockup: nothing changes, and it is said
b = D.ListButton(7)
b.scripts.OnDragStart(b)
cursor.x, cursor.y = 5000, 5000
Same(D.Find(), nil, "outside the mockup there is no target")
b.scripts.OnDragStop(b)
Same(Ids(), "recommend,auction,vendor,disenchant,status*,source*,note*", "dropped outside: unchanged")
Check(Has(f, "Nothing changed."), "and it says so")
Check(not Drag.Active(), "and the drag is over")
-- a line already in the preview cannot be dragged from the list again
b = D.ListButton(3)
b.scripts.OnDragStart(b)
Check(not Drag.Active(), "no second copy of a line by dragging")
-- reorder by dragging a row: the last row down to the top
D.SetMode(true)
local last = #D.Model().sec.rows
local row = D.Row(last)
row.scripts.OnDragStart(row)
Check(Drag.Active() and Drag.Source().kind == "row" and Drag.Source().id == "note", "carrying a row")
Check(row.alpha == 0.4, "the carried row is dimmed")
Point(2)
row.scripts.OnDragStop(row)
Same(Ids(), "note*,recommend,auction,vendor,disenchant,status*,source*", "the row moved to the top")
Check(row.alpha == 1 or D.Row(last).alpha == 1, "dimming ends")
-- a row dropped where it already is does not change anything
row = D.Row(2)
row.scripts.OnDragStart(row)
Point(RowMid(2) + 1)
row.scripts.OnDragStop(row)
Same(Ids(), "note*,recommend,auction,vendor,disenchant,status*,source*", "dropped on itself: unchanged")
-- below the last row: the end
row = D.Row(1)
row.scripts.OnDragStart(row)
Point(D.Model().bottoms[#D.Model().sec.rows] + 3)
row.scripts.OnDragStop(row)
Same(Ids(), "recommend,auction,vendor,disenchant,status*,source*,note*", "dropped below the last row: moved to the end")
-- the gap to a place in the layout, in the Normal preview (hidden lines in between)
D.SetMode(false)
Same(D.PositionOf(0), 1); Same(D.PositionOf(1), 2)
Same(D.PositionOf(#D.Model().sec.rows), 5, "after the last SHOWN line: before the hidden Shift lines")
D.SetMode(false)
-- a hidden Shift line before the shown ones: a gap means a place in the whole layout, not a count of the rows shown
L.SetLines({ { id = "status", when = "shift" }, { id = "vendor", when = "always" }, { id = "note", when = "shift" }, { id = "auction", when = "always" } })
D.Refresh()
Same(D.PositionOf(0), 2, "before the first SHOWN row is after the hidden line")
Same(D.PositionOf(1), 4, "between two shown rows: before the second, after the hidden line between them")
Same(D.PositionOf(2), 5, "after the last shown row")
Check(D.Drop({ kind = "list", id = "outcomes" }, 1) and Ids() == "status*,vendor,note*,outcomes,auction", "dropped between them: " .. Ids())
L.SetLines(L.DefaultLines()); D.Refresh()
Check(D.StartDrag({ kind = "list", id = "vendor" }) == false and not Drag.Active(), "a line already in the preview is not carried again")
-- drop handlers by themselves
Check(D.Drop({ kind = "bogus" }, 0) == false and D.Drop(nil, 0) == false and D.Drop({ kind = "list", id = "outcomes" }, nil) == false, "a bad drop does nothing")
Check(D.Drop({ kind = "list", id = "outcomes" }, 0) and Ids():sub(1, 9) == "outcomes,", "a drop adds at the gap: " .. Ids())
D.RemoveLine("outcomes")
-- the frame closing mid-drag puts the drag away
b = D.ListButton(7)
b.scripts.OnDragStart(b)
Check(Drag.Active(), "dragging")
f:Hide()
Check(not Drag.Active(), "hiding the page cancels a drag")
f:Show()
Check(Ids() == DEFAULT, "and changed nothing")

---------------------------------------------------------------------------
-- Redrawing, a newer schema, a profile change
---------------------------------------------------------------------------
local made = MI_MADE
for _ = 1, 30 do D.Refresh() end
Same(MI_MADE, made, "redrawing makes no new frames")
local n = #f.mock.children
for _ = 1, 5 do D.SetMode(true); D.SetMode(false); D.SetExample("missing"); D.SetExample("ordinary") end
Same(#f.mock.children, n, "switching previews makes no new rows")
Check(#f.mock.children <= 40, "a bounded mockup")
c.TwichUIDB.ui.workshopWorth = { v = 2, lines = { { id = "note" } }, future = true }
D.Refresh()
Same(Ids(), DEFAULT, "a newer layout reads as the default")
Click(D.ListButton(7)); Check(Has(f, "newer TwichUI"), "and a change is refused, said")
Same(c.TwichUIDB.ui.workshopWorth.v, 2, "the newer data is untouched")
Check(c.TwichUIDB.ui.workshopWorth.future == true and #c.TwichUIDB.ui.workshopWorth.lines == 1, "the newer data is untouched")
D.ResetLayout(); Check(Has(f, "newer TwichUI"), "reset refused too")
c.TwichUIDB.ui.workshopWorth = nil
-- the page host: the Workshop page asks the designer for its frame and height
Check(D.Height() > 300, "a tall designer: " .. tostring(D.Height()))

if failures > 0 then error(failures .. " check(s) failed", 0) end
print("PASSED")
