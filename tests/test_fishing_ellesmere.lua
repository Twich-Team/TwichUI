-- TwichUI Fishing, Stage 2: fading EllesmereUI's interface (TwichUI_Fishing/Ellesmere.lua, Fade.lua's ownership policy).
-- Against a stand-in built from reading EllesmereUI's source (tests/ellesmere_mock.lua): detection, action bars, unit frames
-- through their shared parent, 3D portraits, the minimap, mouse-over bars, EllesmereUI's own writes while faded, combat,
-- frames made or rebuilt while faded, a frame something keeps animating, turning the integration off and on, repeated use,
-- errors, and EllesmereUI absent. Proves bookkeeping against modelled behaviour, not compatibility with the real addon.
dofile(TESTS .. "fishing_mock.lua")
dofile(TESTS .. "ellesmere_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"

local function Fresh(o)
  o = o or {}
  local c, W = FishingClient()
  local faults = {}
  c.geterrorhandler = function() return function(e) faults[#faults + 1] = tostring(e) end end
  W.faults = faults
  W.Camera()
  local hooks = 0
  local base = c.hooksecurefunc
  c.hooksecurefunc = function(...) hooks = hooks + 1; return base(...) end
  W.hookCount = function() return hooks end
  local EUI = EllesmereStandIn(c, W, o)
  W.bound.F = KEY
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  return c, W, c.TwichUI.Fishing, EUI
end
local function Settle(W) W.Frames(1) end
local function Enter(c, W) c.TwichUI.RunCommand("fish mode"); Settle(W) end
local function Leave(c, W) c.TwichUI.RunCommand("fish mode"); Settle(W) end

---------------------------------------------------------------------------
-- 1. Detection and what can be faded
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local st = F.Ellesmere.Status()
  Check(st.detected and st.version == "9.9.1" and st.forever, "EllesmereUI is detected, with its version and Forever support")
  Check(st.found.bars == 6 and st.found.units == 1 and st.found.minimap == 1, ("found: bars %d, units %d, minimap %d"):format(st.found.bars, st.found.units, st.found.minimap))
  local inv = F.Fade.Inventory()
  Check(inv.bars.EllesmereUI == 6 and inv.units.EllesmereUI == 1, "the inventory counts EllesmereUI's frames by group")
end

---------------------------------------------------------------------------
-- 2. Entering and leaving: bars, unit frames (one shared parent), the portrait, the minimap
---------------------------------------------------------------------------
do
  local c, W, F, EUI = Fresh()
  Enter(c, W)
  Check(EUI.bars.MainBar:GetAlpha() == 0 and EUI.bars.Bar2:GetAlpha() == 0 and EUI.bars.StanceBar:GetAlpha() == 0, "action bars fade")
  Check(EUI.paging:GetAlpha() == 0 and EUI.xp:GetAlpha() == 0, "the paging arrows and the data bar fade")
  Check(EUI.hider:GetAlpha() == 0 and EUI.wrap:GetAlpha() == 1 and EUI.player:GetAlpha() == 1 and EUI.target:GetAlpha() == 1,
    "unit frames fade through their shared parent: EllesmereUI's own frames and wrapper are not written")
  Check(EUI.model:GetAlpha() == 0, "the 3D portrait, which doesn't inherit alpha, fades by itself")
  Check(EUI.map:GetAlpha() == 0 and EUI.cluster:GetAlpha() == 0, "the minimap fades (the cluster EllesmereUI emptied stays as it was)")
  Check(EUI.menu:GetAlpha() == 1, "EllesmereUI's secure micro menu is never touched")
  Check(EUI.bars.Bar3:GetAlpha() == 0, "the mouse-over bar was already at rest (0)")
  local writes = EUI.writes
  Leave(c, W)
  Check(EUI.bars.MainBar:GetAlpha() == 1 and EUI.bars.Bar3:GetAlpha() == 0 and EUI.hider:GetAlpha() == 1 and EUI.model:GetAlpha() == 1
    and EUI.map:GetAlpha() == 1 and EUI.paging:GetAlpha() == 1, "everything back at EllesmereUI's own preference")
  Check(EUI.record[EUI.bars.MainBar] == 1 and EUI.record[EUI.bars.Bar3] == 0, "EllesmereUI's own record was never changed")
  Check(EUI.writes == writes, "and EllesmereUI was not made to write anything")
  Check(not F.Fade.Status().ticking, "no upkeep runs once Fishing Mode is off")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, " | "))
end

---------------------------------------------------------------------------
-- 3. EllesmereUI writes while faded: covered at once (no flash); the pointer wins; its preference is kept
---------------------------------------------------------------------------
do
  local c, W, F, EUI = Fresh()
  Enter(c, W)
  EUI.TargetChanged()          -- a visibility pass writes 1 to every always-visible bar and the target frame
  Check(EUI.bars.MainBar:GetAlpha() == 0 and EUI.model:GetAlpha() == 0, "a visibility pass is covered in the same instant: no flash")
  Check(EUI.target:GetAlpha() == 1 and EUI.hider:GetAlpha() == 0, "the target frame is EllesmereUI's to write; it stays hidden through the shared parent")
  -- the pointer over a mouse-over bar: EllesmereUI's fade in is shown
  EUI.Hover("Bar3", true); W.Frames(0.3)
  Check(EUI.bars.Bar3:GetAlpha() == 1, "hovering a mouse-over bar shows it, as EllesmereUI wants")
  EUI.Hover("Bar3", false); W.Frames(0.3)
  Check(EUI.bars.Bar3:GetAlpha() == 0, "and it rests again when the pointer leaves")
  W.Advance(1.1)
  Check(EUI.bars.Bar3:GetAlpha() == 0, "still at rest after the upkeep pass")
  -- the pointer over an always-visible bar that EllesmereUI rewrites: shown while hovered, faded again after
  W.UI.mouse[EUI.bars.MainBar] = true
  EUI.VisibilityPass()
  Check(EUI.bars.MainBar:GetAlpha() == 1, "an owner's write under the pointer is shown")
  W.UI.mouse[EUI.bars.MainBar] = nil
  W.Advance(1.1); W.Frames(1)
  Check(EUI.bars.MainBar:GetAlpha() == 0, "and the bar fades again once the pointer has left")
  Leave(c, W)
  Check(EUI.bars.MainBar:GetAlpha() == 1 and EUI.bars.Bar3:GetAlpha() == 0, "back at EllesmereUI's latest preferences")
  Check(F.Fade.last.owner >= 2, "the frames EllesmereUI wrote meanwhile are counted")
end

---------------------------------------------------------------------------
-- 4. Combat: everything back at once; EllesmereUI's combat writes then land untouched
---------------------------------------------------------------------------
do
  local c, W, F, EUI = Fresh()
  Enter(c, W)
  W.Fight()
  Check(EUI.bars.MainBar:GetAlpha() == 1 and EUI.hider:GetAlpha() == 1 and EUI.model:GetAlpha() == 1, "combat: back at once")
  local covered = F.Fade.covered
  EUI.FadeTo(EUI.bars.Bar2, 0.5, 0.1); W.Frames(0.3)
  Check(EUI.bars.Bar2:GetAlpha() == 0.5 and F.Fade.covered == covered, "afterwards EllesmereUI's own fades land as it writes them (the hook is inert)")
  W.Peace()
end

---------------------------------------------------------------------------
-- 5. Frames made or rebuilt while faded
---------------------------------------------------------------------------
do
  local c, W, F, EUI = Fresh()
  Enter(c, W)
  local late = EUI.Late("Bar9")
  W.Advance(1.1); W.Frames(1)
  Check(late:GetAlpha() == 0, "a bar EllesmereUI makes while fishing fades within a second")
  local old, new = EUI.Rebuild("Bar2")
  W.Advance(1.1); W.Frames(1)
  Check(old:GetAlpha() == 1 and new:GetAlpha() == 0, "a rebuilt bar: the old frame is put back, the new one fades")
  Leave(c, W)
  Check(late:GetAlpha() == 1 and new:GetAlpha() == 1 and old:GetAlpha() == 1, "all back afterwards")
  Check(F.Fade.last.stale == 1, "the rebuilt frame is reported")
end

---------------------------------------------------------------------------
-- 6. A frame something keeps animating is left to it (no fight), and the integration can be turned off and on
---------------------------------------------------------------------------
do
  local c, W, F, EUI = Fresh()
  Enter(c, W)
  for i = 1, 30 do EUI.bars.StanceBar:SetAlpha(0.5 + (i % 2) * 0.1) end
  Check(EUI.bars.StanceBar:GetAlpha() > 0.4, "written 30 times in a moment: left to its owner, not fought")
  local lines = table.concat(F.Fade.Report(), "\n")
  Check(lines:find("left to EllesmereUI", 1, true), "and the report says so")
  F.Present.Configure("fade.ellesmere", false); Settle(W)
  Check(EUI.bars.MainBar:GetAlpha() == 1 and EUI.hider:GetAlpha() == 1, "the integration turned off while fishing: EllesmereUI's frames come back")
  F.Present.Configure("fade.ellesmere", true); Settle(W)
  Check(EUI.bars.MainBar:GetAlpha() == 0 and EUI.hider:GetAlpha() == 0, "and on again: they fade")
  Leave(c, W)
end

---------------------------------------------------------------------------
-- 7. Repeated use: no hook added twice, nothing left behind
---------------------------------------------------------------------------
do
  local c, W, F, EUI = Fresh()
  Enter(c, W); Leave(c, W)
  local hooks = W.hookCount()
  for _ = 1, 5 do Enter(c, W); Leave(c, W) end
  Check(W.hookCount() == hooks, ("five more times: no new hooks (%d)"):format(W.hookCount() - hooks))
  Check(EUI.bars.MainBar:GetAlpha() == 1 and EUI.hider:GetAlpha() == 1 and EUI.model:GetAlpha() == 1, "and everything back each time")
end

---------------------------------------------------------------------------
-- 8. Errors, frames that must not be touched, and EllesmereUI absent
---------------------------------------------------------------------------
do
  local c, W, F, EUI = Fresh()
  EUI.bars.Bar2.SetAlpha = function() error("refused") end
  c.TwichUI.RunCommand("fish fade add EllesmereUIMicroMenu")
  Enter(c, W)
  Check(EUI.bars.MainBar:GetAlpha() == 0, "one frame refusing doesn't stop the others")
  Check(F.noteCounts["fade-refused"] and F.noteCounts["fade-refused"] >= 1, "the refusal is noted")
  Check(EUI.menu:GetAlpha() == 1 and table.concat(F.Fade.Report(), "\n"):find("EllesmereUIMicroMenu [added]: skipped, never touched", 1, true),
    "a frame EllesmereUI asks never to have its alpha changed is skipped even when added by name")
  Leave(c, W)
  Check(EUI.bars.MainBar:GetAlpha() == 1 and #W.faults == 0, "everything back, no error: " .. table.concat(W.faults, " | "))
end
do
  local c, W, F = Fresh({ absent = true })
  local bar = W.UI.Create("Frame", "MainMenuBar", c.UIParent)
  Check(not F.Ellesmere.Status().detected and #F.Ellesmere.Targets({ bars = true, units = true, minimap = true }) == 0, "EllesmereUI absent: nothing of it is looked for")
  Enter(c, W)
  Check(bar:GetAlpha() == 0, "the game's own bars still fade")
  Leave(c, W)
  Check(bar:GetAlpha() == 1 and #W.faults == 0, "and come back")
end
do
  local c, W, F, EUI = Fresh({ noUnitFrames = true })
  Enter(c, W)
  Check(EUI.bars.MainBar:GetAlpha() == 0 and F.Ellesmere.Status().found.units == 0, "unit frames module off: the bars still fade")
  Leave(c, W)
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_ellesmere")
