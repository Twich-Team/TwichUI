-- A geometry probe for the layout wizard's stand-in frames (layouts_mock.lua): where a frame or text ends up, from its anchors, in
-- units from the top left of the window, y growing downward. The stand-ins keep what the page told them (size, points, text), so the
-- real page builders can be measured, not only scanned for strings.
--
--   P.Rect(obj)           -> { l, t, w, h, r, b } or nil when it has no anchor the probe understands (a stretched texture)
--   P.Shown(obj)          whether it and everything above it is shown
--   P.Descendants(frame)  every region and frame under it, depth first
--
-- Anchors read: SetPoint(point, x, y), (point, relTo, x, y), (point, relTo, relPoint, x, y). A frame with no anchor sits at its
-- parent's top left. The window is the origin. A text with no width set is as wide as its characters (6 units each); its height is the
-- stand-in's (12 a line).

local P = {}
P.origin = nil   -- the frame measured from (the wizard's window): its top left is 0, 0

local FRAC = { TOPLEFT = { 0, 0 }, TOP = { 0.5, 0 }, TOPRIGHT = { 1, 0 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 1 }, BOTTOM = { 0.5, 1 }, BOTTOMRIGHT = { 1, 1 } }

local function Size(o)
  local w, h = o.w or 0, o.h or 0
  if o.kind == "FontString" then
    if w == 0 then w = #(o.text or "") * 6 end
    h = o:GetStringHeight()
  end
  return w, h
end

local function Resolve(o, depth)
  if depth > 40 then return nil end
  local w, h = Size(o)
  local pts = o.points or {}
  local rect
  if o == P.origin then
    rect = { l = 0, t = 0, w = w, h = h }
  elseif #pts == 0 then
    local parent = o.parent
    if not parent then rect = { l = 0, t = 0, w = w, h = h }
    else
      local pr = Resolve(parent, depth + 1)
      if not pr then return nil end
      rect = { l = pr.l, t = pr.t, w = w, h = h }
    end
  else
    -- every anchor pins an edge or the middle of the frame to a place on what it is anchored to; two anchors on opposite edges give
    -- the size (a footer stretched across the window), one anchor and the frame's own size give the rest
    local l, r, cx, t, bt, cy
    for _, a in ipairs(pts) do
      local point, i, rel = a[1], 2, o.parent
      if type(a[i]) == "table" then rel, i = a[i], i + 1 end
      local relPoint = point
      if type(a[i]) == "string" then relPoint, i = a[i], i + 1 end
      local x, y = a[i] or 0, a[i + 1] or 0
      local rr = rel and Resolve(rel, depth + 1)
      if not rr then return nil end
      local f, g = FRAC[relPoint], FRAC[point]
      if not (f and g) then return nil end
      local ax, ay = rr.l + f[1] * rr.w + x, rr.t + f[2] * rr.h - y
      if g[1] == 0 then l = ax elseif g[1] == 1 then r = ax else cx = ax end
      if g[2] == 0 then t = ay elseif g[2] == 1 then bt = ay else cy = ay end
    end
    if l and r then w = r - l elseif l then r = l + w elseif r then l = r - w elseif cx then l = cx - w / 2 else l = 0 end
    if t and bt then h = bt - t elseif t then bt = t + h elseif bt then t = bt - h elseif cy then t = cy - h / 2 else t = 0 end
    rect = { l = l, t = t, w = w, h = h }
  end
  rect.r, rect.b = rect.l + rect.w, rect.t + rect.h
  return rect
end

function P.Rect(o)   -- worked out fresh each time: a page lays out again whenever it is drawn
  return Resolve(o, 0)
end

function P.Shown(o)
  while o do
    if o.shown == false then return false end
    o = o.parent
  end
  return true
end

function P.Descendants(frame, out)
  out = out or {}
  for _, ch in ipairs(frame.children or {}) do
    out[#out + 1] = ch
    P.Descendants(ch, out)
  end
  return out
end

return P
