-- Navigation in EllesmereUI's Unlock Mode (nav/Unlock.lua): two movers registered once, only when chosen and only when
-- EllesmereUI has what they need; each stand-in is the size of what it stands for; the frame and arrow are centred on
-- their stand-in and follow it; the one saved place (ui.navigation.position / arrowPosition); a discarded session goes
-- back; dragging in the game is off while EllesmereUI is in charge; and everything is a no-op without EllesmereUI.
--   1  off by default, nothing registered     2  turning it on: registered, labelled, nothing moves
--   3  sizes follow scale and layout           4  hiding: arrow in the frame, parts off, navigation off
--   5  drag, Save & Exit, discard, no drift    6  reset, clear, other writes refused
--   7  the in-game drag is off, and back       8  EllesmereUI late, absent, partial, refusing
-- EllesmereUI is a stand-in that follows the documented contract (EllesmereUI.lua MakeUnlockElement, EUI_UnlockMode.lua
-- registration and listeners, EUI_UnlockMode_Session.lua save and revert). What the real mover does in the game still has
-- to be checked there.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI"})

---------------------------------------------------------------------------
-- Frames with real geometry: anchor points against the screen or another frame, sizes and scales.
---------------------------------------------------------------------------
local W, H, UI_SCALE = 1024, 768, 0.64
local ANCH = { CENTER = {0, 0}, TOPLEFT = {-1, 1}, TOP = {0, 1}, TOPRIGHT = {1, 1}, LEFT = {-1, 0}, RIGHT = {1, 0},
  BOTTOMLEFT = {-1, -1}, BOTTOM = {0, -1}, BOTTOMRIGHT = {1, -1} }
local UIP

local function Size(f)   -- width and height in the screen's units
  if f == UIP then return W, H end
  local s = f.scale or 1
  return (f.w or 0) * s, (f.h or 0) * s
end
local function Centre(f) -- the frame's centre in the screen's units, or nil without a place
  if f == UIP then return W / 2, H / 2 end
  local p = f.pt
  if not p then return nil end
  local rcx, rcy = Centre(p.rel)
  if not rcx then return nil end
  local rw, rh = Size(p.rel)
  local ra, a = ANCH[p.relPoint], ANCH[p.point]
  local s = f.scale or 1
  local w, h = Size(f)
  return rcx + ra[1] * rw / 2 + p.x * s - a[1] * w / 2, rcy + ra[2] * rh / 2 + p.y * s - a[2] * h / 2
end

local frames = {}
local function Frame(o)
  o = o or {}
  o.shown, o.scripts, o.hooks, o.attrs = true, {}, {}, {}
  table.insert(frames, o)
  return setmetatable(o, {__index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "GetScript" then return function(s, n) return s.scripts[n] end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end end
    if k == "RegisterForDrag" then return function(s, ...) s.drag = select("#", ...) > 0 and (...) or nil end end
    if k == "EnableMouse" then return function(s, v) s.mouse = v and true or false end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetFont" then return function() return true end end
    if k == "GetStringWidth" then return function() return 40 end end
    if k == "GetStringHeight" then return function() return 12 end end
    if k == "SetWidth" then return function(s, v) s.w = v end end
    if k == "SetHeight" then return function(s, v) s.h = v end end
    if k == "GetWidth" then return function(s) if s == UIP then return W end return s.w or 0 end end
    if k == "GetHeight" then return function(s) if s == UIP then return H end return s.h or 0 end end
    if k == "SetSize" then return function(s, w, h) s.w, s.h = w, h; s.sizes = (s.sizes or 0) + 1 end end
    if k == "GetSize" then return function(s) return s.w or 0, s.h or 0 end end
    if k == "SetScale" then return function(s, v) s.scale = v end end
    if k == "GetScale" then return function(s) return s == UIP and 1 or (s.scale or 1) end end
    if k == "GetEffectiveScale" then return function(s) return s == UIP and UI_SCALE or UI_SCALE * (s.scale or 1) end end
    if k == "ClearAllPoints" then return function(s) s.pt = nil end end
    if k == "SetPoint" then return function(s, point, rel, relPoint, x, y)
      -- only placements against the screen or a frame of this test have geometry (the rest are laid out inside the frame)
      s.pt = (rel == UIP or (type(rel) == "table" and rel.isTestFrame)) and { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 } or nil
      s.setPoints = (s.setPoints or 0) + 1
    end end
    if k == "GetCenter" then return function(s)
      local cx, cy = Centre(s)
      if not cx then return nil end
      local sc = s == UIP and 1 or (s.scale or 1)
      return cx / sc, cy / sc
    end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Frame() end end
    if k == "SetMovable" or k == "SetFrameStrata" or k == "SetFrameLevel" or k == "SetClampedToScreen" then return function() end end
    if type(k) == "string" and k:find("^%u") then return function() end end   -- any other method: does nothing
    return nil
  end})
end
c.CreateFrame = function(kind, name, parent, template) return Frame({ kind = kind, name = name, parent = parent, template = template, isTestFrame = true }) end
UIP = Frame()
c.UIParent = UIP
c.GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
c.GameTooltip = Frame()
c.InCombatLockdown = function() return false end

---------------------------------------------------------------------------
-- EllesmereUI, as documented.
---------------------------------------------------------------------------
local EUI
local function MakeEUI(opts)
  opts = opts or {}
  local e = { elements = {}, registerCalls = 0, unregisterCalls = 0, listeners = {}, reapplied = {}, session = false }
  function e:RegisterUnlockElements(list)
    e.registerCalls = e.registerCalls + 1
    if opts.refuse then error("refused") end
    for _, el in ipairs(list) do e.elements[el.key] = el end
  end
  function e:UnregisterUnlockElement() e.unregisterCalls = e.unregisterCalls + 1 end
  if not opts.noMake then
    -- the documented whitelist: a field left out never reaches Unlock Mode
    function e.MakeUnlockElement(o)
      return { key = o.key, label = o.label, group = o.group, order = o.order, getFrame = o.getFrame, getSize = o.getSize,
        savePosition = o.savePos, loadPosition = o.loadPos, clearPosition = o.clearPos, applyPosition = o.applyPos,
        setWidth = o.setWidth, setHeight = o.setHeight, isHidden = o.isHidden, isAnchored = o.isAnchored, noResize = o.noResize }
    end
  end
  function e:RegisterUnlockModeListener(owner, fn)
    e.listeners[owner] = fn
    if e.session then fn(true) end
  end
  function e:IsUnlockModeActive() return e.session end
  function e.ReapplyOwnAnchor(key) table.insert(e.reapplied, key) end
  return e
end
local function SnapHalf(v) return math.floor(v * 2 + 0.5) / 2 end   -- stand-in for EllesmereUI's pixel snap: idempotent

local KEYS = { frame = "TwichUI_NavFrame", arrow = "TwichUI_NavArrow" }
local function El(kind) return EUI.elements[KEYS[kind]] end
local function Stand(kind) return El(kind).getFrame(KEYS[kind]) end
local function Open() EUI.session = true; for _, fn in pairs(EUI.listeners) do fn(true) end end
local function Close(action) EUI.session = false; for _, fn in pairs(EUI.listeners) do fn(false, action or "exit") end end
-- a drag: the live frame is set by its TOPLEFT (EUI_UnlockMode_Movers.lua)
local function Drag(kind, ox, oy)
  local f = Stand(kind)
  local w, h = f:GetSize()
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIP, "TOPLEFT", W / 2 + ox - w / 2, oy - H / 2 + h / 2)
end
-- Save & Exit: CENTER/CENTER from the live rect in screen units (Positions.lua ConvertToCenterPos / SaveBarPosition)
local function Commit(kind)
  local f = Stand(kind)
  local cx, cy = f:GetCenter()
  local ratio = f:GetEffectiveScale() / UIP:GetEffectiveScale()
  El(kind).savePosition(KEYS[kind], "CENTER", "CENTER", cx * ratio - W / 2, cy * ratio - H / 2, "TOPLEFT", "TOPLEFT")
end
local function ApplyPos(kind, pos)   -- ApplyCenterPosition: the centralized apply, snapped
  local f = Stand(kind)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIP, "CENTER", SnapHalf(pos.x), SnapHalf(pos.y))
end
local function Revert(kind, snap)    -- RevertPositions: the snapshot taken at open, saved back and applied
  El(kind).savePosition(KEYS[kind], snap.point, snap.relPoint, snap.x, snap.y)
  ApplyPos(kind, snap)
end

---------------------------------------------------------------------------
-- The addon: the navigation views (their data and routes are not needed to place a frame)
---------------------------------------------------------------------------
local EXTRA = { "modules/Borders.lua", "modules/MenuStyle.lua", "nav/Prefs.lua", "nav/Data.lua", "nav/Route.lua",
  "nav/Journey.lua", "nav/Nav.lua", "nav/Travel.lua", "nav/Paint.lua", "nav/Unlock.lua", "nav/Frame.lua", "nav/Arrow.lua" }
for _, f in ipairs(EXTRA) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {}, ui = { navigation = { position = { x = 100, y = -50 }, arrowPosition = { x = -200, y = 90 } } } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local NV, NP, NF, NA, NU = R.Nav, R.NavPrefs, R.NavFrame, R.NavArrow, R.NavUnlock
assert(NU, "the integration is loaded")
R:SetEnabled("navigation", true)
-- a route being followed is not needed: the views are shown for a sample, as the settings preview does
NV.Active = function() return true end
NV.Snapshot = function() return NF.SAMPLE end
local function Look() FlushTimers() end
local function Same(a, b) return math.abs(a - b) < 1e-9 end
local function Saved(key) return c.TwichUIDB.ui.navigation[key] end
local function Views()   -- the frame object's frame, and the arrow on its own
  local fr = NF.Main().f
  local arrow
  for _, f in ipairs(frames) do if f.name == "TwichUINavigationArrow" then arrow = f end end
  return fr, arrow
end
local function Offset(f) local cx, cy = Centre(f); return cx - W / 2, cy - H / 2 end

NF.Refresh(); Look()
local frame, arrow = Views()
assert(frame.shown and arrow and arrow.shown, "the frame and the arrow are shown")
assert(Same(Offset(frame) and select(1, Offset(frame)), 100) and Same(select(2, Offset(frame)), -50), "the frame sits at the saved place")
assert(Same(select(1, Offset(arrow)), -200) and Same(select(2, Offset(arrow)), 90), "the arrow sits at the saved place")

---------------------------------------------------------------------------
-- 1. Off by default: EllesmereUI present, nothing registered, nothing changes
---------------------------------------------------------------------------
do
  assert(NP.DEFAULTS.unlockMode == false and NP.Get("unlockMode") == false, "off by default")
  c.EllesmereUI = MakeEUI(); EUI = c.EllesmereUI
  c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "EllesmereUI"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); Look()
  assert(EUI.registerCalls == 0 and next(EUI.listeners) == nil, "not registered while off")
  assert(NU.Status() == "off" and not NU.Drives("frame") and not NU.Drives("arrow") and NU.Anchor("frame") == nil)
  assert(not NP.Valid("unlockMode", "yes") and NP.Valid("unlockMode", true), "only a boolean is a choice")
  c.TwichUIDB.ui.navigation.unlockMode = "yes"
  assert(NP.Get("unlockMode") == false and NU.Status() == "off", "anything but true is off")
  c.TwichUIDB.ui.navigation.unlockMode = nil
  -- the in-game drag works as before
  NP.Set("locked", false); Look()
  assert(frame.mouse == true and frame.drag == "LeftButton", "unlocked: the frame is dragged in the game")
  assert(arrow.mouse == true and arrow.drag == "LeftButton", "and so is the arrow")
  NP.Set("locked", true); Look()
end

---------------------------------------------------------------------------
-- 2. Turning it on: registered once, clearly labelled, and nothing moves
---------------------------------------------------------------------------
local x0f, y0f = Offset(frame)
local x0a, y0a = Offset(arrow)
do
  assert(NP.Set("unlockMode", true)); Look()
  assert(EUI.registerCalls == 1 and El("frame") and El("arrow"), "both registered, in one call")
  assert(El("frame").label == "TwichUI Navigation" and El("arrow").label == "TwichUI Navigation Arrow", "clearly labelled")
  assert(El("frame").group == "TwichUI" and El("arrow").group == "TwichUI" and El("frame").order ~= El("arrow").order)
  for _, k in ipairs({ "frame", "arrow" }) do
    local e = El(k)
    assert(e.noResize == true and e.setWidth == nil and e.setHeight == nil, "no size controls are claimed")
    assert(e.isHidden() == false, "shown in Unlock Mode")
    assert(Stand(k) ~= (k == "frame" and frame or arrow), "a stand-in of its own, not the frame or arrow")
  end
  assert(NU.Status() == "active" and NU.Drives("frame") and NU.Drives("arrow"))
  local sx, sy = Stand("frame"):GetCenter()
  assert(Same(sx - W / 2, 100) and Same(sy - H / 2, -50), "the frame's stand-in starts at the saved place")
  local ax, ay = Stand("arrow"):GetCenter()
  assert(Same(ax - W / 2, -200) and Same(ay - H / 2, 90), "the arrow's stand-in starts at the saved place")
  local fx, fy = Offset(frame); assert(Same(fx, x0f) and Same(fy, y0f), "turning it on moves the frame nowhere")
  local rx, ry = Offset(arrow); assert(Same(rx, x0a) and Same(ry, y0a), "nor the arrow")
  assert(frame.pt.rel == Stand("frame") and arrow.pt.rel == Stand("arrow"), "they are centred on the stand-ins")
  assert(Saved("position").x == 100 and Saved("arrowPosition").x == -200, "the records are as they were")
  assert(EUI.reapplied[1] == KEYS.frame and EUI.reapplied[2] == KEYS.arrow, "existing anchor links are applied once registered")
  -- registered once however often it is asked
  for _ = 1, 4 do NP.Set("frameScale", 100 + _); c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "EllesmereUI"); c.FireEvent("PLAYER_ENTERING_WORLD", false, false) end
  NP.Set("frameScale", 100); Look()
  assert(EUI.registerCalls == 1, "never registered twice: " .. EUI.registerCalls)
  assert(EUI.unregisterCalls == 0, "never unregistered (that would delete the player's anchor links)")
  local n = 0; for _ in pairs(EUI.listeners) do n = n + 1 end
  assert(n == 1, "one session listener")
end

---------------------------------------------------------------------------
-- 3. Sizes: scale applied; the frame's own height once it has one
---------------------------------------------------------------------------
do
  local sw, sh = Stand("arrow"):GetSize()
  assert(sw == 60 and sh == 70, "the arrow's stand-in: 60 x 70 at scale 1: " .. sw .. "x" .. sh)
  NP.Set("arrowScale", 150); Look()
  sw, sh = Stand("arrow"):GetSize()
  assert(sw == 90 and sh == 105, "scaled with Arrow size: " .. sw .. "x" .. sh)
  local gw, gh = El("arrow").getSize(KEYS.arrow); assert(gw == 90 and gh == 105, "getSize says the same")
  NP.Set("arrowScale", 100)
  local w, h = Stand("frame"):GetSize()
  assert(w == 250 and h == frame:GetHeight(), "the frame's stand-in is the frame's size: " .. w .. "x" .. h)
  NP.Set("frameScale", 120); Look()
  w, h = Stand("frame"):GetSize()
  assert(w == 300 and h == math.floor(frame:GetHeight() * 1.2 + 0.5), "scaled with Frame size: " .. w .. "x" .. h)
  NP.Set("textSize", 15); Look()
  assert(Stand("frame"):GetSize() == math.floor(math.floor(250 * 15 / 12 + 0.5) * 1.2 + 0.5), "and with the text size")
  NP.Set("frameScale", 100); NP.Set("textSize", 12); Look()
  -- the frame's height changes with its words: the stand-in follows, and the frame stays centred on it
  local before = select(2, Stand("frame"):GetSize())
  NF.Main():Update({ state = "navigating", dest = { name = "A long way" }, instruction = "Turn left", remaining = 5, toNext = 5, straight = 5,
    nextText = "go on", steps = 3, leg = 1, eta = 600 })
  local after = select(2, Stand("frame"):GetSize())
  assert(after > before and after == frame:GetHeight(), "taller words, taller stand-in: " .. before .. " -> " .. after)
  local fx, fy = Offset(frame); assert(Same(fx, 100) and Same(fy, -50), "the frame is still centred on its place")
  NF.Main():Update(NF.SAMPLE)
end

---------------------------------------------------------------------------
-- 4. Hidden from Unlock Mode when there is nothing to move
---------------------------------------------------------------------------
do
  NP.Set("arrowAttached", true); Look()
  assert(El("arrow").isHidden() == true and El("frame").isHidden() == false, "the arrow in the frame has no mover of its own")
  NP.Set("arrowAttached", false)
  NP.Set("frame", false); Look()
  assert(El("frame").isHidden() == true and El("arrow").isHidden() == false, "frame off: no frame mover")
  NP.Set("arrowAttached", true); Look()
  assert(El("arrow").isHidden() == false, "the arrow is on its own again with the frame off")
  NP.Set("arrowAttached", false); NP.Set("frame", true)
  NP.Set("arrow", false); Look()
  assert(El("arrow").isHidden() == true, "arrow off: no arrow mover")
  NP.Set("arrow", true)
  R:SetEnabled("navigation", false); Look()
  assert(El("frame").isHidden() == true and El("arrow").isHidden() == true and NU.Status() == "module-off" and not NU.Drives("frame"),
    "navigation off: nothing to move")
  R:SetEnabled("navigation", true); NF.Refresh(); Look()
  assert(El("frame").isHidden() == false and El("arrow").isHidden() == false and NU.Status() == "active")
  frame, arrow = Views()
  assert(frame.pt and frame.pt.rel == Stand("frame"), "and the frame is on its stand-in again")
  assert(EUI.registerCalls == 1 and EUI.unregisterCalls == 0, "hiding is not unregistering")
end

---------------------------------------------------------------------------
-- 5. Dragging and saving: the views follow; Save & Exit writes the one record; a discard goes back
---------------------------------------------------------------------------
do
  Open()
  Drag("frame", 220, 140); Drag("arrow", -300, -120)
  local x, y = Offset(frame); assert(Same(x, 220) and Same(y, 140), "the frame follows its stand-in as it is dragged: " .. x .. "," .. y)
  x, y = Offset(arrow); assert(Same(x, -300) and Same(y, -120), "so does the arrow")
  assert(Saved("position").x == 100 and Saved("arrowPosition").x == -200, "nothing is saved until Save & Exit")
  Commit("frame"); Commit("arrow"); Close("save")
  local f, a = Saved("position"), Saved("arrowPosition")
  assert(Same(f.x, 220) and Same(f.y, 140) and Same(a.x, -300) and Same(a.y, -120), "saved as the centre's offset")
  x, y = Offset(frame); assert(Same(x, 220) and Same(y, 140))
  assert(El("frame").loadPosition(KEYS.frame).x == 220 and El("frame").loadPosition(KEYS.frame).point == "CENTER", "EllesmereUI reads the same record")
  assert(NP.Get("position").x == 220, "and so do the preferences")

  -- a discarded session goes back; the records are not touched
  Open()
  local snapF = El("frame").loadPosition(KEYS.frame); snapF = { point = snapF.point, relPoint = snapF.relPoint, x = snapF.x, y = snapF.y }
  local snapA = El("arrow").loadPosition(KEYS.arrow); snapA = { point = snapA.point, relPoint = snapA.relPoint, x = snapA.x, y = snapA.y }
  Drag("frame", -400, 90); Drag("arrow", 50, 50)
  x = Offset(frame); assert(Same(x, -400))
  Revert("frame", snapF); Revert("arrow", snapA); Close("discard")
  x, y = Offset(frame); assert(Same(x, 220) and Same(y, 140), "back where it was: " .. x .. "," .. y)
  x, y = Offset(arrow); assert(Same(x, -300) and Same(y, -120))
  assert(Saved("position").x == 220 and Saved("arrowPosition").x == -300, "records unchanged")

  -- repeated sessions do not drift: open, apply the snapped place, save without moving, many times
  c.TwichUIDB.ui.navigation.position = { x = 101.37, y = -52.61 }
  for _ = 1, 6 do
    El("frame").applyPosition(KEYS.frame); ApplyPos("frame", El("frame").loadPosition(KEYS.frame))
    Open(); Commit("frame"); Close("save")
  end
  local p = Saved("position")
  assert(p.x == SnapHalf(101.37) and p.y == SnapHalf(-52.61), "settles on the snapped place once: " .. p.x .. "," .. p.y)
  Open(); Commit("frame"); Close("save")
  assert(Saved("position").x == p.x and Saved("position").y == p.y, "no further movement")
  c.TwichUIDB.ui.navigation.position = { x = 220, y = 140 }
  El("frame").applyPosition(KEYS.frame)
end

---------------------------------------------------------------------------
-- 6. The default, reset, clear, and what is refused
---------------------------------------------------------------------------
do
  -- Reset position (the settings): both go to the default places and the stand-ins with them
  NP.Reset("position"); Look()
  assert(Saved("position") == nil and Saved("arrowPosition") == nil, "the records are gone")
  local fx, fy = Offset(frame)
  local fw, fh = frame:GetWidth(), frame:GetHeight()
  local top = H / 2 + fy + fh / 2   -- the frame's top edge, measured from the screen's bottom
  assert(Same(fx, 0) and Same(H - top, 140), "the frame's top is 140 below the screen's top, as without EllesmereUI: " .. (H - top))
  local ax, ay = Offset(arrow); assert(Same(ax, 0) and Same(ay, 220), "the arrow's centre is 220 above the screen's centre")
  local lx = El("frame").loadPosition(KEYS.frame)
  assert(lx.point == "CENTER" and Same(lx.x, 0) and Same(lx.y, fy), "loadPos always gives a place, the default included")
  assert(El("arrow").loadPosition(KEYS.arrow).y == 220)
  -- a discarded session that began at the default writes nothing
  Open()
  local snap = El("frame").loadPosition(KEYS.frame); snap = { point = snap.point, relPoint = snap.relPoint, x = snap.x, y = snap.y }
  Drag("frame", 10, 10); Revert("frame", snap); Close("discard")
  assert(Saved("position") == nil, "a place that was never set stays unset")
  Open(); Commit("frame"); Close("save")
  assert(Saved("position") == nil, "saving without moving does not create a record either")
  -- a taller frame at the default keeps its top where it was
  local topBefore = H - (H / 2 + select(2, Offset(frame)) + frame:GetHeight() / 2)
  NF.Main():Update({ state = "navigating", dest = { name = "A long way" }, instruction = "Turn left", remaining = 5, toNext = 5, straight = 5,
    nextText = "go on", steps = 3, leg = 1, eta = 600 })
  local topAfter = H - (H / 2 + select(2, Offset(frame)) + frame:GetHeight() / 2)
  assert(Same(topBefore, topAfter) and Same(topAfter, 140), "taller frame, same top: " .. topAfter)
  NF.Main():Update(NF.SAMPLE)

  -- a typed value (the X and Y boxes) is a save like any other
  Open(); Drag("frame", 33, 44); Commit("frame"); Close("save")
  assert(Same(Saved("position").x, 33) and Same(Saved("position").y, 44))
  -- clearing (EllesmereUI's reset): the place is the default again
  El("frame").clearPosition(KEYS.frame)
  assert(Saved("position") == nil and Same(select(1, Offset(frame)), 0), "cleared: the default place")
  assert(Saved("arrowPosition") == nil)

  -- refused: not a centre point, not numbers, not a place
  local s = El("arrow").savePosition
  s(KEYS.arrow, "TOPLEFT", "TOPLEFT", 10, 10); s(KEYS.arrow, "CENTER", "CENTER", "x", 1); s(KEYS.arrow, "CENTER", "CENTER", 0 / 0, 1)
  s(KEYS.arrow, "CENTER", "CENTER", 1e9, 1); s(KEYS.arrow, "CENTER", "CENTER", 1, nil)
  assert(Saved("arrowPosition") == nil, "none of those is a place")
  s(KEYS.arrow, "CENTER", "CENTER", 12.5, -7.25)
  assert(Saved("arrowPosition").x == 12.5 and Saved("arrowPosition").y == -7.25, "a fractional place is kept as it is")
  assert(not NP.Set("position", { x = 1e9, y = 0 }) and not NP.Set("position", { x = 0 }), "the preferences refuse them too")
  NP.Clear("font"); assert(NP.Get("font") == "default", "only the two places can be cleared")
  NP.Clear("arrowPosition"); assert(Saved("arrowPosition") == nil)
  -- a profile change that brings a place: the stand-in goes there (outside a session), the frame with it
  c.TwichUIDB.ui.navigation.position = { x = -60, y = 30 }; NP.Notify("position"); Look()
  assert(Same(select(1, Offset(frame)), -60) and Same(select(2, Offset(frame)), 30), "a new record moves the stand-in and the frame")
  c.TwichUIDB.ui.navigation.position = { x = 220, y = 140 }; NP.Notify("position"); Look()
end

---------------------------------------------------------------------------
-- 7. One owner: the in-game drag is off while EllesmereUI is in charge, and back when it is not
---------------------------------------------------------------------------
do
  NP.Set("locked", false); Look()
  assert(frame.mouse == false and frame.drag == nil, "the frame is not dragged in the game")
  assert(arrow.mouse == false and arrow.drag == nil, "nor the arrow")
  NP.Set("unlockMode", false); Look()
  assert(NU.Status() == "off" and not NU.Drives("frame") and NU.Anchor("arrow") == nil)
  assert(frame.mouse == true and frame.drag == "LeftButton" and arrow.mouse == true, "off: dragged in the game again")
  assert(frame.pt.rel == UIP and arrow.pt.rel == UIP, "and placed from the record against the screen")
  local x, y = Offset(frame); assert(Same(x, 220) and Same(y, 140), "at the same place")
  El("frame").applyPosition(KEYS.frame); Open(); Commit("frame"); Close("save")
  assert(Saved("position").x == 220, "a save while it is off writes nothing")
  local before = Saved("position")
  El("frame").savePosition(KEYS.frame, "CENTER", "CENTER", 5, 5)
  assert(Saved("position") == before and Same(before.x, 220), "a stale save while off is ignored")
  assert(El("frame").isHidden() == true, "hidden from Unlock Mode while off")
  NP.Set("locked", true)
  NP.Set("unlockMode", true); Look()
  assert(NU.Drives("frame") and frame.pt.rel == Stand("frame"), "on again: no second registration")
  assert(EUI.registerCalls == 1 and EUI.unregisterCalls == 0)
  x, y = Offset(frame); assert(Same(x, 220) and Same(y, 140), "and nothing moved")
end

---------------------------------------------------------------------------
-- 8. EllesmereUI late, absent, partial or refusing
---------------------------------------------------------------------------
local function Fresh(setup)
  local d = MakeClient("Rich", {"!!!TwichUI"})
  -- the frames of this test: new ones for this client
  d.CreateFrame = c.CreateFrame; d.UIParent = UIP; d.GameFontNormal = c.GameFontNormal; d.GameTooltip = c.GameTooltip
  d.InCombatLockdown = c.InCombatLockdown
  if setup then setup(d) end
  for _, f in ipairs(EXTRA) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, d); chunk("!!!TwichUI", {})
  end
  d.TwichUIDB = { modules = { navigation = true }, ui = { navigation = { unlockMode = true, position = { x = 40, y = 41 }, arrowPosition = { x = 7, y = 8 } } } }
  d.LOADED["!!!TwichUI"] = true; d.FireEvent("ADDON_LOADED", "!!!TwichUI")
  local DR = d.TwichUI
  DR.Nav.Active = function() return true end
  DR.Nav.Snapshot = function() return DR.NavFrame.SAMPLE end
  return d, DR
end

do -- EllesmereUI absent: the choice is kept, nothing is registered, the saved place is used
  local d, DR = Fresh()
  d.FireEvent("PLAYER_LOGIN"); d.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  DR.NavFrame.Refresh(); FlushTimers()
  assert(DR.NavUnlock.Status() == "no-eui" and not DR.NavUnlock.Drives("frame"), "no EllesmereUI")
  assert(d.TwichUIDB.ui.navigation.unlockMode == true, "the choice is kept while EllesmereUI is away")
  local fr = DR.NavFrame.Main().f
  assert(fr.pt.rel == UIP and Same(select(1, Offset(fr)), 40) and Same(select(2, Offset(fr)), 41), "the saved place is used")

  -- ... then it appears (it loads after TwichUI): registered, and nothing moves
  d.EllesmereUI = MakeEUI(); local E = d.EllesmereUI
  local saved = EUI; EUI = E
  d.FireEvent("ADDON_LOADED", "EllesmereUI"); FlushTimers()
  assert(E.registerCalls == 1 and DR.NavUnlock.Status() == "active", "registered once EllesmereUI is there")
  assert(fr.pt.rel == El("frame").getFrame(), "the frame is on its stand-in now")
  assert(Same(select(1, Offset(fr)), 40) and Same(select(2, Offset(fr)), 41), "and has not moved")
  EUI = saved
end

do -- an EllesmereUI without Unlock Mode
  local d, DR = Fresh()
  d.EllesmereUI = { }
  d.FireEvent("PLAYER_LOGIN"); DR.NavFrame.Refresh(); FlushTimers()
  assert(DR.NavUnlock.Status() == "no-api" and not DR.NavUnlock.Drives("frame"), "no Unlock Mode: a plain status")
  d.EllesmereUI = MakeEUI({ noMake = true })
  d.FireEvent("PLAYER_LOGIN"); FlushTimers()
  assert(DR.NavUnlock.Status() == "no-api" and d.EllesmereUI.registerCalls == 0, "half an API is none")
  assert(select(1, Offset(DR.NavFrame.Main().f)) == 40, "the saved place is still used")
end

do -- an EllesmereUI that refuses: noted, falls back, not tried again
  local d, DR = Fresh()
  d.EllesmereUI = MakeEUI({ refuse = true }); local E = d.EllesmereUI
  d.FireEvent("PLAYER_LOGIN"); DR.NavFrame.Refresh(); FlushTimers()
  assert(DR.NavUnlock.Status() == "register-failed" and not DR.NavUnlock.Drives("frame"), "refused")
  assert(DR.NavFrame.Main().f.pt.rel == UIP, "the frame keeps its own place")
  for _ = 1, 3 do d.FireEvent("PLAYER_LOGIN"); d.FireEvent("PLAYER_ENTERING_WORLD", false, false) end
  assert(E.registerCalls == 1, "not retried every event: " .. E.registerCalls)
end

do -- the choice never made: EllesmereUI is never touched
  local d, DR = Fresh(); local E = MakeEUI(); d.EllesmereUI = E
  d.TwichUIDB.ui.navigation.unlockMode = nil
  d.FireEvent("PLAYER_LOGIN"); d.FireEvent("ADDON_LOADED", "EllesmereUI"); DR.NavFrame.Refresh(); FlushTimers()
  assert(E.registerCalls == 0 and next(E.listeners) == nil and DR.NavUnlock.Status() == "off")
end

print("PASSED")
