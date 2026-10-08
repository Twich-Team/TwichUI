dofile(TESTS .. "harness.lua")
-- Release hardening: fitting windows to a small screen, tooltips for cut-short rows, work done while a
-- feature is off, and TwichUI loading with none of its optional addons. Mocks show our own arithmetic and
-- bookkeeping; they cannot show how a window really looks at a given size.
local c = MakeClient("Rich", {"!!!TwichUI"})
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI

local function Near(a, b, msg) assert(math.abs(a - b) < 1e-9, ("%s: expected %s, got %s"):format(msg, tostring(b), tostring(a))) end

---------------------------------------------------------------------------
-- FitScale: only ever smaller, never below the floor, never fooled by bad numbers
---------------------------------------------------------------------------
Near(R.FitScale(720, 580, 1920, 1080), 1, "a big screen leaves a window at full size")
Near(R.FitScale(720, 580, 768, 768), 1, "room for the window and its margin")
Near(R.FitScale(900, 580, 800, 600), (800 - 48) / 900, "800x600 holds the widest window by width")
Near(R.FitScale(540, 580, 1024, 600), (600 - 48) / 580, "short screens are limited by height")
Near(R.FitScale(900, 580, 100, 100), 0.6, "never below the floor")
for _, bad in ipairs({ 0, -5, 1 / 0, 0 / 0 }) do
  Near(R.FitScale(bad, 580, 800, 600), 1, "unusable width " .. tostring(bad))
  Near(R.FitScale(900, 580, bad, 600), 1, "unusable screen width " .. tostring(bad))
end
Near(R.FitScale(nil, 580, 800, 600), 1, "no width")
Near(R.FitScale(900, 580, "800", 600), 1, "text is not a size")

---------------------------------------------------------------------------
-- FitToScreen: sets the scale from the window's own size, so repeating it never compounds
---------------------------------------------------------------------------
do
  local screen = { w = 800, h = 600 }
  c.UIParent = { GetWidth = function() return screen.w end, GetHeight = function() return screen.h end }
  local sets = 0
  local frame = { scale = 1 }
  function frame:GetWidth() return 900 end
  function frame:GetHeight() return 580 end
  function frame:GetScale() return self.scale end
  function frame:SetScale(s) sets = sets + 1; self.scale = s end

  R.FitToScreen(frame)
  Near(frame.scale, (800 - 48) / 900, "scaled down to fit a small window")
  R.FitToScreen(frame); R.FitToScreen(frame)
  Near(frame.scale, (800 - 48) / 900, "repeating does not compound")
  assert(sets == 1, "an unchanged fit is not set again (" .. sets .. ")")
  screen.w, screen.h = 1920, 1080
  R.FitToScreen(frame)
  Near(frame.scale, 1, "back to full size when there is room")
  R.FitToScreen(nil)   -- nothing to fit: no error
end

---------------------------------------------------------------------------
-- TipTruncated: the whole text, and only when the label is cut
---------------------------------------------------------------------------
do
  local shown
  local tip = { owner = nil }
  function tip:SetOwner(o) self.owner = o end
  function tip:GetOwner() return self.owner end
  function tip:SetText(t) shown = { title = t, lines = {} } end
  function tip:AddLine(t) shown = shown or { lines = {} }; shown.lines[#shown.lines + 1] = t end
  function tip:Show() self.visible = true end
  function tip:Hide() self.visible = false; self.owner = nil end
  c.GameTooltip = tip

  local truncated = false
  local label = { IsTruncated = function() return truncated end }
  local row = { scripts = {}, mouse = false }
  function row:EnableMouse(v) self.mouse = v end
  function row:SetScript(n, fn) self.scripts[n] = fn end
  function row:HookScript() end
  row.fullName = "A very long backup name that does not fit"
  R.Interact.TipTruncated(row, label, function(r) return r.fullName end)
  assert(row.mouse, "the row answers the mouse")

  row.scripts.OnEnter(row)
  assert(not tip.visible, "a name that fits needs no tooltip")
  truncated = true
  row.scripts.OnEnter(row)
  assert(tip.visible and shown.lines[1] == row.fullName, "a cut name shows in full")
  row.fullName = "Renamed"
  tip:Hide(); shown = nil
  row.scripts.OnEnter(row)
  assert(shown.lines[1] == "Renamed", "read when it opens, never stale")
  row.scripts.OnLeave(row)
  assert(not tip.visible, "leaving hides it")
end

---------------------------------------------------------------------------
-- Group check: a roster change does nothing while the group check is off
---------------------------------------------------------------------------
do
  GROUP = { Rich = true, Pal = true }
  local before = #LONG_TIMERS + #TIMERS
  c.TwichUIDB.modules.groupCheck = false
  c.FireEvent("GROUP_ROSTER_UPDATE")
  assert(#LONG_TIMERS + #TIMERS == before, "no timer is started for a feature that is off")
  c.TwichUIDB.modules.groupCheck = true
  GROUP = { Rich = true }
  c.FireEvent("GROUP_ROSTER_UPDATE")   -- back to alone: resets the roster size
  GROUP = { Rich = true, Pal = true, Zed = true }
  c.FireEvent("GROUP_ROSTER_UPDATE")
  assert(#LONG_TIMERS + #TIMERS == before + 1, "on: one hello is scheduled")
  GROUP = nil
end

---------------------------------------------------------------------------
-- No optional addon present: nothing from them is required to load
---------------------------------------------------------------------------
assert(c.EllesmereUI == nil and c.Auctionator == nil and c.LibStub:GetLibrary("LibDataBroker-1.1", true) == nil,
  "none of the optional addons or libraries is in this environment")
assert(R.S == nil and R.OnSkin and R.Interact and R.Life, "TwichUI is up with its plain look")

print("RELEASE TESTS PASSED")
