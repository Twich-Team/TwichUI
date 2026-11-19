-- A tiny fake WoW frame world for the reachability tests (tests/test_reach.lua, tests/test_testlab_ui.lua).
-- OFFLINE MODEL: frames have typed-in rectangles in screen units, a strata, a level, a parent and the mouse flags the documented widget API
-- has. It is NOT the game: how the real client orders frames, clips them or routes input is exactly what the guided probe in the client
-- measures. The model of GetMouseFoci below is the simple rule the analysis assumes (visible, mouse enabled, inside the hit rectangle,
-- clipped by scroll frames, highest strata then level then creation order); it exists so the code that READS the answer can be tested.
--
--   local World = dofile(TESTS .. "reach_world.lua")
--   local w = World.New()
--   local win = w:Frame{ name = "Window", x = 100, y = 100, w = 800, h = 600, strata = "HIGH", level = 5 }
--   local btn = w:Frame{ type = "Button", name = "Add", parent = win, x = 400, y = 300, w = 120, h = 30, level = 6, mouse = true, onClick = function() end }
--   w:Install(env)          -- EnumerateFrames, GetMouseFoci, GetCursorPosition into a table of globals
--   w:Cursor(450, 315)      -- where the pointer is
--
-- Frame fields: type (default "Frame"), name, parent, x y w h (screen units, bottom-left origin), scale (own scale, default 1; the parent's
-- multiplies in), strata (default "MEDIUM"), level (default parent's + 1), mouse (default true for Button/CheckButton/EditBox/Slider, false
-- otherwise), shown (default true), enabled (Buttons: true), click/motion (default follow `mouse`), insets {l, r, t, b}, clips, propagate,
-- onClick/onEnter (set as scripts), agg / aggregateAnd (what IsMouseEnabled answers), propagateApi (see the getter), noEnabled (a frame type without IsEnabled), noClickEnabled (an older client without IsMouseClickEnabled).
local World = {}
World.__index = World

local MOUSE_BY_DEFAULT = { Button = true, CheckButton = true, EditBox = true, Slider = true }
local HAS_ENABLED = { Button = true, CheckButton = true, EditBox = true, Slider = true }

function World.New()
  return setmetatable({ frames = {}, cx = 0, cy = 0 }, World)
end

function World:Frame(def)
  local w = self
  local kind = def.type or "Frame"
  local f = { _kind = kind, _name = def.name, _parent = def.parent, _x = def.x or 0, _y = def.y or 0, _w = def.w or 0, _h = def.h or 0,
    _scale = def.scale or 1, _strata = def.strata, _level = def.level, _shown = def.shown ~= false, _enabled = def.enabled ~= false,
    _insets = def.insets or { 0, 0, 0, 0 }, _clips = def.clips == true, _propagate = def.propagate, scripts = {}, order = #self.frames + 1 }
  local mouse = def.mouse
  if mouse == nil then mouse = MOUSE_BY_DEFAULT[kind] or false end
  f._click, f._motion = mouse, mouse
  if def.click ~= nil then f._click = def.click end
  if def.motion ~= nil then f._motion = def.motion end
  if def.onClick then f.scripts.OnClick = def.onClick end
  if def.onEnter then f.scripts.OnEnter = def.onEnter end
  if not f._strata then f._strata = f._parent and f._parent:GetFrameStrata() or "MEDIUM" end
  if not f._level then f._level = f._parent and f._parent:GetFrameLevel() + 1 or 1 end

  function f:GetName() return self._name end
  function f:GetObjectType() return self._kind end
  function f:GetParent() return self._parent end
  function f:IsShown() return self._shown end
  function f:Show() self._shown = true end
  function f:Hide() self._shown = false end
  function f:IsVisible() local p = self while p do if not p._shown then return false end p = p._parent end return true end
  function f:GetEffectiveScale() local s, p = 1, self while p do s = s * p._scale p = p._parent end return s end
  function f:GetRect()   -- frame units: the typed-in screen rectangle divided by the effective scale
    local s = self:GetEffectiveScale()
    return self._x / s, self._y / s, self._w / s, self._h / s
  end
  function f:GetFrameStrata() return self._strata end
  function f:SetFrameStrata(v) self._strata = v end
  function f:GetFrameLevel() return self._level end
  function f:SetFrameLevel(v) self._level = v end
  -- IsMouseEnabled: by default "either" (the older stand-in); def.agg forces the aggregate to a value, def.aggregateAnd makes it "both". OBSERVED in
  -- Forever 1.60.1 build 70888: a frame can read mouse false with click true (motion false), and mouse false with motion true (click false).
  function f:IsMouseEnabled()
    if def.agg ~= nil then return def.agg end
    if def.aggregateAnd then return self._click and self._motion end
    return self._click or self._motion
  end
  function f:EnableMouse(v) self._click, self._motion = v and true or false, v and true or false end
  function f:IsMouseMotionEnabled() return self._motion end
  function f:SetMouseMotionEnabled(v) self._motion = v and true or false end
  if not def.noClickEnabled then
    function f:IsMouseClickEnabled() return self._click end
    function f:SetMouseClickEnabled(v) self._click = v and true or false end
  end
  function f:SetHitRectInsets(l, r, t, b) self._insets = { l, r, t, b } end
  function f:GetHitRectInsets() return self._insets[1], self._insets[2], self._insets[3], self._insets[4] end   -- documented order: left, right, top, bottom
  function f:DoesClipChildren() return self._clips end
  -- the propagation getter: Forever's API documentation lists CanPropagateMouseClicks (and no Get...); def.propagateApi = "both" (default), "can",
  -- "get", "none" (neither exists) or "odd" (Can... exists and answers nothing)
  local api = def.propagateApi or "both"
  if api == "both" or api == "can" then function f:CanPropagateMouseClicks() return self._propagate == true end end
  if api == "both" or api == "get" then function f:GetPropagateMouseClicks() return self._propagate == true end end
  if api == "odd" then function f:CanPropagateMouseClicks() return nil end end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  if HAS_ENABLED[kind] and not def.noEnabled then
    function f:IsEnabled() return self._enabled end
    function f:Disable() self._enabled = false end
    function f:Enable() self._enabled = true end
  end
  self.frames[#self.frames + 1] = f
  return f
end

function World:Cursor(x, y) self.cx, self.cy = x, y end

-- the model of the pointer: every frame the rule above would let take it, topmost first
local RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
function World:Foci()
  local x, y, out = self.cx, self.cy, {}
  for _, f in ipairs(self.frames) do
    if f:IsVisible() and f._motion then
      local s = f:GetEffectiveScale()
      local il, ir, it, ib = f._insets[1], f._insets[2], f._insets[3], f._insets[4]
      local l, b, w, h = f:GetRect()
      local ok = x >= (l + il) * s and x <= (l + w - ir) * s and y >= (b + ib) * s and y <= (b + h - it) * s
      local p = f._parent
      while ok and p do
        if p._kind == "ScrollFrame" or p._clips then
          local pl, pb, pw, ph = p:GetRect()
          local ps = p:GetEffectiveScale()
          if not (x >= pl * ps and x <= (pl + pw) * ps and y >= pb * ps and y <= (pb + ph) * ps) then ok = false end
        end
        p = p._parent
      end
      if ok then out[#out + 1] = f end
    end
  end
  table.sort(out, function(a, b)
    if RANK[a._strata] ~= RANK[b._strata] then return RANK[a._strata] > RANK[b._strata] end
    if a._level ~= b._level then return a._level > b._level end
    return a.order > b.order
  end)
  return out
end

-- puts the world's global functions into env (a table the code under test reads globals from)
function World:Install(env)
  local w = self
  env.EnumerateFrames = function(prev)
    local i = 0
    if prev then for k, f in ipairs(w.frames) do if f == prev then i = k break end end end
    return w.frames[i + 1]
  end
  env.GetMouseFoci = function() return w:Foci() end
  env.GetCursorPosition = function() return w.cx, w.cy end
  return env
end

return World
