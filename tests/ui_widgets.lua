-- A small stand-in for the game's frames, textures, font strings and animation groups, with real layout: points, sizes, scale,
-- alpha and shown state are kept, and Rect(region) works out where a region is on a 1366 x 768 screen the way the game
-- resolves anchors. It records what is drawn (texture files and coordinates, colors, text, fonts), so a test can check the
-- heads-up pieces and tools/render_fishing_hud.py can draw a capture of them from UIDump(). It proves layout arithmetic and
-- bookkeeping only: not the game's rendering, its fonts' metrics, taint or protected behaviour.
--
--   UIWidgets(env, opts) -> W     opts.missing[path] = true: SetTexture / SetFont refuse that file (returns false)
--   W.Create(kind, name, parent)  what env.CreateFrame should return for non-secure frames
--   W.Rect(region)                left, bottom, width, height in screen units (nil while it can't be resolved)
--   W.Visible(region)             shown, with every parent shown
--   W.Alpha(region)               its alpha times its parents'
--   W.Dump()                      every visible drawn region, in drawing order, as plain tables
--   W.Tick(dt)                    runs OnUpdate scripts and animation groups for dt seconds

function UIWidgets(env, opts)
  opts = opts or {}
  local W = { regions = {}, frames = {}, serial = 0, missing = opts.missing or {}, mouse = {} }
  local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
  local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

  local function Base(kind, parent)
    W.serial = W.serial + 1
    local r = { kind = kind, parent = parent, points = {}, shown = true, alpha = 1, scale = 1, serial = W.serial, scripts = {} }
    function r:SetPoint(point, rel, relPoint, x, y)
      if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
      rel = rel or self.parent
      if type(rel) == "string" then rel = env[rel] end
      if type(relPoint) ~= "string" then relPoint, x, y = point, relPoint, x end
      for i, p in ipairs(self.points) do if p[1] == point then table.remove(self.points, i) break end end
      assert(type(x or 0) == "number" and type(y or 0) == "number", "SetPoint offsets must be numbers: " .. tostring(point) .. " " .. tostring(x) .. " " .. tostring(y))
      table.insert(self.points, { point, rel, relPoint, x or 0, y or 0 })
    end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints(rel)
      rel = rel or self.parent
      self.points = {}
      self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
      self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
    end
    function r:GetNumPoints() return #self.points end
    function r:GetPoint(i) local p = self.points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetWidth(w) self.w = w end
    function r:SetHeight(h) self.h = h end
    function r:GetWidth() local _, _, w = W.Rect(self); return (w and w / W.Scale(self)) or self.w or 0 end
    function r:GetHeight() local _, _, _, h = W.Rect(self); return (h and h / W.Scale(self)) or self.h or 0 end
    function r:GetSize() return self:GetWidth(), self:GetHeight() end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:SetShown(v) self.shown = v and true or false end
    function r:IsShown() return self.shown end
    function r:IsVisible() return W.Visible(self) end
    function r:SetAlpha(a) self.alpha = a end
    function r:GetAlpha() return self.alpha end
    function r:GetEffectiveAlpha() return W.Alpha(self) end
    function r:GetParent() return self.parent end
    function r:SetParent(p) self.parent = p end
    function r:IsForbidden() return false end
    function r:GetLeft() local l = W.Rect(self); return l and l / W.Scale(self) end
    function r:GetBottom() local _, b = W.Rect(self); return b and b / W.Scale(self) end
    function r:GetRight() local l, _, w = W.Rect(self); return l and (l + w) / W.Scale(self) end
    function r:GetTop() local _, b, _, h = W.Rect(self); return b and (b + h) / W.Scale(self) end
    function r:GetCenter() local l, b, w, h = W.Rect(self); if l then local s = W.Scale(self) return (l + w / 2) / s, (b + h / 2) / s end end
    W.regions[#W.regions + 1] = r
    return r
  end

  local function Animations(owner)
    local ag = { anims = {}, playing = false, scripts = {}, owner = owner, t = 0 }
    function ag:CreateAnimation(kind)
      local a = { kind = kind, duration = 0, order = 1 }
      function a:SetFromAlpha(v) self.from = v end
      function a:SetToAlpha(v) self.to = v end
      function a:SetDuration(v) self.duration = v end
      function a:SetOrder(v) self.order = v end
      function a:SetOffset(x, y) self.dx, self.dy = x, y end
      function a:SetSmoothing() end
      function a:SetStartDelay(v) self.delay = v end
      table.insert(self.anims, a)
      return a
    end
    function ag:Play() self.playing, self.t = true, 0; self.plays = (self.plays or 0) + 1 end
    function ag:Stop() self.playing = false end
    function ag:IsPlaying() return self.playing end
    function ag:SetScript(n, fn) self.scripts[n] = fn end
    function ag:SetLooping() end
    function ag:Length()
      local orders = {}
      for _, a in ipairs(self.anims) do orders[a.order] = math.max(orders[a.order] or 0, (a.delay or 0) + a.duration) end
      local n = 0 for _, d in pairs(orders) do n = n + d end
      return n
    end
    W.groups = W.groups or {}
    table.insert(W.groups, ag)
    return ag
  end

  local function Region(kind, parent, layer, sub)
    local r = Base(kind, parent)
    r.layer, r.sub = layer or "ARTWORK", sub or 0
    function r:SetDrawLayer(l, s) self.layer, self.sub = l, s or 0 end
    function r:CreateAnimationGroup() return Animations(self) end
    return r
  end

  local function Texture(parent, layer, sub)
    local t = Region("Texture", parent, layer, sub)
    t.coords = { 0, 1, 0, 1 }
    function t:SetTexture(path)
      if path ~= nil and W.missing[path] then self.file = nil return false end
      self.file, self.color = path, nil
      return true
    end
    function t:GetTexture() return self.file end
    function t:SetColorTexture(r, g, b, a) self.file, self.color = nil, { r, g, b, a or 1 } end
    function t:SetTexCoord(l, r, tp, b) self.coords = { l, r, tp, b } end
    function t:GetTexCoord() return unpack(self.coords) end
    function t:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
    function t:SetBlendMode(m) self.blend = m end
    function t:SetDesaturated(v) self.desaturated = v end
    return t
  end

  local function FontString(parent, layer)
    local f = Region("FontString", parent, layer)
    f.text, f.size, f.justifyH = "", 12, "CENTER"
    function f:SetFont(file, size, flags)
      if W.missing[file] then return false end
      self.font, self.size, self.flags = file, size, flags
      return true
    end
    function f:GetFont() return self.font, self.size, self.flags end
    function f:SetText(t) self.text = t ~= nil and tostring(t) or "" end
    function f:GetText() return self.text end
    function f:SetFormattedText(fmt, ...) self.text = fmt:format(...) end
    function f:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
    function f:SetShadowColor(r, g, b, a) self.shadow = { r, g, b, a or 1 } end
    function f:SetShadowOffset(x, y) self.shadowOffset = { x, y } end
    function f:SetJustifyH(j) self.justifyH = j end
    function f:SetJustifyV(j) self.justifyV = j end
    function f:SetWordWrap(v) self.wrap = v end
    function f:SetNonSpaceWrap() end
    function f:SetMaxLines() end
    -- plain text length only: |c..|r, |T..|t and |cff colors are not counted
    function f:Plain() return (self.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
    function f:GetStringWidth()
      local n = 0
      for _ in self:Plain():gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
      return n * self.size * 0.5
    end
    function f:GetStringHeight() return self.size end
    return f
  end

  function W.Create(kind, name, parent)
    local fr = Base(kind or "Frame", parent)
    fr.strata, fr.level, fr.events, fr.hooks, fr.name = nil, nil, {}, {}, name
    fr.mouse = false
    function fr:SetFrameStrata(s) self.strata = s end
    function fr:GetFrameStrata() return self.strata or (self.parent and self.parent.GetFrameStrata and self.parent:GetFrameStrata()) or "MEDIUM" end
    function fr:SetFrameLevel(l) self.level = l end
    function fr:GetFrameLevel() return self.level or ((self.parent and self.parent.GetFrameLevel and self.parent:GetFrameLevel() or 0) + 1) end
    function fr:SetScale(s) self.scale = s end
    function fr:GetScale() return self.scale end
    function fr:GetEffectiveScale() return W.Scale(self) end
    function fr:EnableMouse(v) self.mouse = v and true or false end
    function fr:IsMouseEnabled() return self.mouse end
    function fr:EnableMouseWheel() end
    function fr:SetMovable(v) self.movable = v end
    function fr:SetClampedToScreen(v) self.clamped = v end
    function fr:RegisterForDrag(...) self.drag = { ... } end
    function fr:StartMoving() self.moving = true end
    function fr:StopMovingOrSizing() self.moving = false end
    function fr:SetScript(n, fn) self.scripts[n] = fn end
    function fr:GetScript(n) return self.scripts[n] end
    function fr:HookScript(n, fn) self.hooks[n] = self.hooks[n] or {}; table.insert(self.hooks[n], fn) end
    function fr:RegisterEvent(e) self.events[e] = true end
    function fr:UnregisterEvent(e) self.events[e] = nil end
    function fr:UnregisterAllEvents() self.events = {} end
    function fr:IsProtected() return false end
    function fr:GetObjectType() return self.kind end
    function fr:IsMouseOver() return W.mouse[self] == true end
    function fr:GetChildren()
      local out = {}
      for _, c in ipairs(W.frames) do if c.parent == self then out[#out + 1] = c end end
      return unpack(out)
    end
    function fr:CreateTexture(_, layer, _, sub) return Texture(self, layer, sub) end
    function fr:CreateFontString(_, layer) return FontString(self, layer) end
    function fr:CreateAnimationGroup() return Animations(self) end
    function fr:SetClipsChildren() end
    local oldShow, oldHide = fr.Show, fr.Hide
    function fr:Show() local was = W.Visible(self); oldShow(self); if not was and W.Visible(self) and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function fr:Hide() local was = W.Visible(self); oldHide(self); if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
    if name then env[name] = fr end
    W.frames[#W.frames + 1] = fr
    return fr
  end

  -- The screen itself.
  local screen = W.Create("Frame", nil, nil)
  screen.w, screen.h, screen.isScreen = 1366, 768, true
  W.screen = screen

  function W.Scale(r)
    local s, p = 1, r
    while p do
      if p.kind ~= "Texture" and p.kind ~= "FontString" then s = s * (p.scale or 1) end
      p = p.parent
    end
    return s
  end

  function W.Visible(r)
    local p = r
    while p do if not p.shown then return false end p = p.parent end
    return true
  end

  function W.Alpha(r)
    local a, p = 1, r
    while p do a = a * (p.alpha or 1) p = p.parent end
    return a
  end

  local function Anchor(rect, point)
    local l, b, w, h = rect[1], rect[2], rect[3], rect[4]
    local x = point:find("LEFT", 1, true) and l or point:find("RIGHT", 1, true) and l + w or l + w / 2
    local y = point:find("TOP", 1, true) and b + h or point:find("BOTTOM", 1, true) and b or b + h / 2
    return x, y
  end

  local resolving = {}
  function W.Rect(r)
    if r.isScreen then return 0, 0, r.w, r.h end
    if resolving[r] then return nil end
    resolving[r] = true
    local s = W.Scale(r)
    local w, h = r.w, r.h
    if r.kind == "FontString" then
      w = w or r:GetStringWidth()
      h = h or r.size * 1.2
    end
    local L, R, T, B, CX, CY
    for _, p in ipairs(r.points) do
      local rel = p[2]
      local rr = rel and { W.Rect(rel) }
      if rr and rr[1] then
        local ax, ay = Anchor(rr, p[3])
        ax, ay = ax + p[4] * s, ay + p[5] * s
        local pt = p[1]
        if pt:find("LEFT", 1, true) then L = ax elseif pt:find("RIGHT", 1, true) then R = ax else CX = ax end
        if pt:find("TOP", 1, true) then T = ay elseif pt:find("BOTTOM", 1, true) then B = ay else CY = ay end
      end
    end
    resolving[r] = nil
    local sw, sh = (w or 0) * s, (h or 0) * s
    local left, bottom, width, height
    -- which edge placed it across (a capture lays text out from that edge: its own width there is only estimated)
    if L and R then left, width, r.hanchor = L, R - L, "LR" elseif L then left, width, r.hanchor = L, sw, "L"
    elseif R then left, width, r.hanchor = R - sw, sw, "R"
    elseif CX then left, width, r.hanchor = CX - sw / 2, sw, "C" end
    if T and B then bottom, height = B, T - B elseif B then bottom, height = B, sh elseif T then bottom, height = T - sh, sh
    elseif CY then bottom, height = CY - sh / 2, sh end
    if not (left and bottom) then return nil end
    return left, bottom, width, height
  end

  -- Every visible texture and font string, in the order the game would draw them.
  function W.Dump()
    local out = {}
    for _, r in ipairs(W.regions) do
      if (r.kind == "Texture" or r.kind == "FontString") and W.Visible(r) and W.Alpha(r) > 0.003 then
        local l, b, w, h = W.Rect(r)
        if l then
          local fr = r.parent
          local item = { kind = r.kind, rect = { l, b, w, h }, alpha = W.Alpha(r), layer = LAYER[r.layer] or 3, sub = r.sub or 0,
            strata = STRATA[fr:GetFrameStrata()] or 3, level = fr:GetFrameLevel(), serial = r.serial, scale = W.Scale(r) }
          if r.kind == "Texture" then
            item.file, item.color, item.coords, item.blend, item.vertex = r.file, r.color, r.coords, r.blend, r.vertex
          else
            item.text, item.font, item.size, item.color, item.justify, item.shadow = r.text, r.font, r.size, r.textColor, r.justifyH, r.shadowOffset
            item.wrap, item.justifyV = r.wrap, r.justifyV
            item.fixedWidth = r.w ~= nil or r.hanchor == "LR"
            item.hanchor = r.hanchor
          end
          out[#out + 1] = item
        end
      end
    end
    table.sort(out, function(a, b)
      if a.strata ~= b.strata then return a.strata < b.strata end
      if a.level ~= b.level then return a.level < b.level end
      if a.layer ~= b.layer then return a.layer < b.layer end
      if a.sub ~= b.sub then return a.sub < b.sub end
      return a.serial < b.serial
    end)
    return out
  end

  -- Runs OnUpdate scripts of visible frames and plays animation groups for dt seconds (in steps of at most 1/30 s).
  function W.Tick(dt, clock)
    local left = dt
    while left > 1e-9 do
      local step = math.min(left, 1 / 30)
      left = left - step
      if clock then clock(step) end
      for _, fr in ipairs(W.frames) do
        local fn = fr.scripts.OnUpdate
        if fn and W.Visible(fr) then fn(fr, step) end
      end
      for _, ag in ipairs(W.groups or {}) do
        if ag.playing then
          ag.t = ag.t + step
          if ag.t >= ag:Length() then
            ag.playing = false
            if ag.scripts.OnFinished then ag.scripts.OnFinished(ag) end
          end
        end
      end
    end
  end

  return W
end
