-- RestedXP timer bars (modules/RestedXPTimers.lua): off with the skin and silent when off; one hook however
-- often it is switched; a started bar is drawn with the saved look (fill, gradient, background, border,
-- text, icon, height) and nothing about its countdown changes; repeated starts create nothing new; a bar
-- that stops goes back to LibCandyBar's shared cache as it was; turning the look off while a timer runs
-- restores it without restarting it; a newer RestedXP colour or height is never overwritten; missing media
-- falls back and stays chosen; the preview is separate from RestedXP's timers and from LibCandyBar.
-- RestedXP's Timers.lua and LibCandyBar-3.0 are simulated from their source (RXPGuides v4.11.22, candybar
-- minor 104): the same names and the same order of calls, not the game.
dofile(TESTS .. "harness.lua")

local ORIGIN = [[Fonts\FRIZQT__.TTF]]
local WHITE = [[Interface\Buttons\WHITE8x8]]
local BAR_FILL = [[Interface\CHARACTERFRAME\BarFill]]
local WATCH = [[Interface\ICONS\INV_Misc_PocketWatch_02]]

local function near(a, b) return math.abs(a - b) < 0.003 end

---------------------------------------------------------------------------
-- A small fake of the game's frames: enough of the backdrop mixin, fonts, textures and status bars.
---------------------------------------------------------------------------
local function Boot(opts)
  opts = opts or {}
  local c = MakeClient("Rich", { "!!!TwichUI" })
  local made = {}
  local Methods
  local function Fake(kind)
    local o = { kind = kind, shown = true, scripts = {}, points = {}, alpha = 1, vertex = { 1, 1, 1, 1 }, level = 1 }
    made[#made + 1] = o
    return setmetatable(o, { __index = function(_, k)
      if Methods[k] then return Methods[k] end
      if type(k) == "string" and k:find("^%u") then return function() end end
    end })
  end
  Methods = {
    Show = function(s) s.shown = true end,
    Hide = function(s) if s.shown then s.shown = false; if s.scripts.OnHide then s.scripts.OnHide(s) end end end,
    IsShown = function(s) return s.shown end,
    SetShown = function(s, v) s.shown = v and true or false end,
    SetScript = function(s, n, fn) s.scripts[n] = fn end,
    GetScript = function(s, n) return s.scripts[n] end,
    SetFrameLevel = function(s, v) s.level = v end,
    GetFrameLevel = function(s) return s.level end,
    CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
    CreateFontString = function(s)
      local t = Fake("font"); t.parent = s; t.font = { ORIGIN, 10, "" }; t.color = { 1, 1, 1, 1 }; t.wrap = true
      return t
    end,
    SetText = function(s, v) s.text = v end,
    GetText = function(s) return s.text end,
    ClearAllPoints = function(s) s.points = {} end,
    SetPoint = function(s, point, a, b, x, y)
      local rel, rp
      if type(a) == "number" then rel, rp, x, y = s.parent, point, a, b
      elseif type(b) == "string" then rel, rp = a, b
      else rel, rp, x, y = a, point, b, x end
      local entry = { point, rel or s.parent, rp, x or 0, y or 0 }
      for i, p in ipairs(s.points) do if p[1] == point then s.points[i] = entry; return end end
      s.points[#s.points + 1] = entry
    end,
    GetNumPoints = function(s) return #s.points end,
    GetPoint = function(s, i) local p = s.points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end,
    SetHeight = function(s, v) s.height = v end,
    GetHeight = function(s) return s.height or 0 end,
    SetWidth = function(s, v) s.width = v end,
    GetWidth = function(s) return s.width or 0 end,
    SetSize = function(s, w, h) s.width, s.height = w, h end,
    SetTexture = function(s, v) s.file = v end,
    GetTexture = function(s) return s.file end,
    SetTexCoord = function(s, ...) s.coords = { ... } end,
    SetColorTexture = function(s, r, g, b, a) s.color = { r, g, b, a } end,
    SetBackdrop = function(s, info)
      if info and (info.bgFile or info.edgeFile) then s.backdropInfo = info else s.backdropInfo = nil end
      s.backdropCalls = (s.backdropCalls or 0) + 1
    end,
    ClearBackdrop = function(s) s.backdropInfo = nil end,
    SetBackdropColor = function(s, r, g, b, a) if s.backdropInfo then s.bgColor = { r, g, b, a } end end,
    SetBackdropBorderColor = function(s, r, g, b, a) if s.backdropInfo then s.edgeColor = { r, g, b, a } end end,
    SetAlpha = function(s, a) s.alpha = a end,
    GetAlpha = function(s) return s.alpha end,
    SetFont = function(s, path, size, flags)
      if path == "Bad\\File.ttf" then return false end
      s.font = { path, size, flags or "" }
      s.fontSets = (s.fontSets or 0) + 1
      return true
    end,
    GetFont = function(s) if s.font then return s.font[1], s.font[2], s.font[3] end end,
    SetTextColor = function(s, r, g, b, a) s.color = { r, g, b, a or 1 } end,
    GetTextColor = function(s) return s.color[1], s.color[2], s.color[3], s.color[4] end,
    SetWordWrap = function(s, v) s.wrap = v end,
    SetVertexColor = function(s, r, g, b, a) s.vertex = { r, g, b, a or 1 } end,
    GetVertexColor = function(s) return s.vertex[1], s.vertex[2], s.vertex[3], s.vertex[4] end,
    SetGradient = function(s, orient, lo, hi)
      if c.GRADIENT_FAILS then error("no gradient") end
      s.gradient = { orient, lo, hi }
      s.gradientSets = (s.gradientSets or 0) + 1
    end,
    -- status bars: one texture of its own, like the game's
    SetStatusBarTexture = function(s, file)
      s.sbFile = file
      s.sbTex = s.sbTex or Fake("texture")
      s.sbTex.file = file
      s.sbTexSets = (s.sbTexSets or 0) + 1
      return true
    end,
    GetStatusBarTexture = function(s) return s.sbTex end,
    SetStatusBarColor = function(s, r, g, b, a) s.sbColor = { r, g, b, a or 1 }; s.sbColorSets = (s.sbColorSets or 0) + 1 end,
    SetMinMaxValues = function(s, lo, hi) s.min, s.max = lo, hi end,
    SetValue = function(s, v) s.value = v end,
    SetParent = function(s, p) s.parent = p end,
    IsEnabled = function(s) return true end,
    EnableMouse = function() end,
    GetEffectiveScale = function() return 1 end,
  }
  c.Fake, c.made = Fake, made
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind); f.name, f.parent = name, parent; return f end
  c.UIParent = Fake("UIParent")
  c.UISpecialFrames = {}
  c.STANDARD_TEXT_FONT = ORIGIN
  c.GameFontNormal = { GetFont = function() return ORIGIN, 12, "" end }
  c.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
  c.NOW = 1000
  c.GetTime = function() return c.NOW end
  c.hookCount = 0
  c.hooksecurefunc = function(tbl, name, fn)
    local orig = assert(tbl[name], "hooking something that is not there: " .. tostring(name))
    c.hookCount = c.hookCount + 1
    tbl[name] = function(...)
      local r = { orig(...) }
      fn(...)
      return unpack(r)
    end
  end
  c.TwichUIDB = opts.db or { modules = {} }
  for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/RestedXPSkin.lua",
      "modules/RestedXPTimers.lua", "diag/Diagnostics.lua", "diag/RestedXPSkin.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  return c
end

local function Start(c)
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  return c.TwichUI
end

---------------------------------------------------------------------------
-- LibCandyBar-3.0 minor 104, as far as RestedXP's use of it goes (libs/LibCandyBar-3.0).
---------------------------------------------------------------------------
local function MakeCandy(c)
  local Fake = c.Fake
  local lib = c.LibStub:NewLibrary("LibCandyBar-3.0", 104)
  lib.callbacks = c.LibStub("CallbackHandler-1.0"):New(lib)
  lib.cache, lib.created, lib.news, lib.registrations = {}, 0, 0, 0
  local proto = {}
  local function restyle(self)
    if not self.running then return end
    self.candyBarIconFrame:ClearAllPoints()
    self.candyBarBar:ClearAllPoints()
    if self.candyBarIconFrame.icon then
      self.candyBarIconFrame:SetWidth(self.height)
      self.candyBarIconFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      self.candyBarBar:SetPoint("TOPLEFT", self.candyBarIconFrame, "TOPRIGHT", 0, 0)
      self.candyBarBar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
      self.candyBarIconFrame:Show()
    else
      self.candyBarBar:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
      self.candyBarBar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
      self.candyBarIconFrame:Hide()
    end
  end
  function proto:SetColor(...) self.candyBarBar:SetStatusBarColor(...) end
  function proto:SetBackgroundColor(...) self.candyBarBackground:SetVertexColor(...) end
  function proto:SetTextColor(...) self.candyBarLabel:SetTextColor(...); self.candyBarDuration:SetTextColor(...) end
  function proto:SetFont(...) self.candyBarLabel:SetFont(...); self.candyBarDuration:SetFont(...) end
  function proto:SetHeight(h) self.height = h; restyle(self) end
  function proto:GetLabel() return self.candyBarLabel.text end
  function proto:SetLabel(t) self.candyBarLabel.text = t; self.candyBarLabel:SetText(t) end
  function proto:GetIcon() return self.candyBarIconFrame.icon end
  function proto:SetIcon(icon)
    self.candyBarIconFrame.icon = icon
    self.candyBarIconFrame:SetTexture(icon)
    restyle(self)
  end
  function proto:SetDuration(d) self.remaining = d end
  function proto:Start()
    self.running = true
    restyle(self)
    self.start = c.GetTime()
    self.exp = self.start + self.remaining
    self.candyBarBar:SetMinMaxValues(0, self.remaining)
    self.candyBarBar:SetValue(self.remaining)
    self.starts = (self.starts or 0) + 1
    self:Show()
  end
  function proto:Stop(...)
    lib.callbacks:Fire("LibCandyBar_Stop", self, ...)
    self.running = nil
    self:Hide()
    self:SetParent(c.UIParent)
    lib.cache[self] = true
  end
  function lib:New(texture, width, height)
    lib.news = lib.news + 1
    local bar = next(lib.cache)
    if not bar then
      lib.created = lib.created + 1
      bar = c.CreateFrame("Frame", nil, c.UIParent)
      for k, v in pairs(proto) do bar[k] = v end
      bar.candyBarIconFrame = bar:CreateTexture()
      bar.candyBarBar = c.CreateFrame("StatusBar", nil, bar)
      bar.candyBarBackground = bar.candyBarBar:CreateTexture()
      bar.candyBarBackdrop = c.CreateFrame("Frame", nil, bar, "BackdropTemplate")
      bar.candyBarBackdrop:SetFrameLevel(0)
      bar.candyBarDuration = bar.candyBarBar:CreateFontString()
      bar.candyBarLabel = bar.candyBarBar:CreateFontString()
      bar.candyBarDuration:SetPoint("TOPLEFT", bar.candyBarBar, "TOPLEFT", 2, 0)
      bar.candyBarDuration:SetPoint("BOTTOMRIGHT", bar.candyBarBar, "BOTTOMRIGHT", -2, 0)
      bar.candyBarLabel:SetPoint("TOPLEFT", bar.candyBarBar, "TOPLEFT", 2, 0)
      bar.candyBarLabel:SetPoint("BOTTOMRIGHT", bar.candyBarBar, "BOTTOMRIGHT", -2, 0)
    else
      lib.cache[bar] = nil
    end
    bar:SetFrameLevel(100)
    bar.candyBarBar:SetStatusBarTexture(texture)
    bar.candyBarBackground:SetTexture(texture)
    bar.width, bar.height = width, height
    for k in pairs(bar.scripts) do bar.scripts[k] = nil end   -- RESET ALL THE THINGS!
    bar:SetBackgroundColor(0.5, 0.5, 0.5, 0.3)
    bar:SetColor(0.5, 0.5, 0.5, 1)
    bar:SetTextColor(1, 1, 1, 1)
    bar:SetFont(ORIGIN, 10)
    bar:SetLabel()
    bar:SetIcon()
    bar:SetDuration()
    return bar
  end
  local register = lib.RegisterCallback
  lib.RegisterCallback = function(...) lib.registrations = lib.registrations + 1; return register(...) end
  return lib
end

---------------------------------------------------------------------------
-- RestedXP: the parts of the window the skin needs, and Timers.lua.
---------------------------------------------------------------------------
local function MakeRestedXP(c, opts)
  opts = opts or {}
  local Fake = c.Fake
  local RXP = {
    themes = {
      ["RXP Blue"] = { name = "RXP Blue", background = { 0.05, 0.05, 0.1, 1 }, textColor = { 1, 1, 1 }, font = ORIGIN,
        texturePath = "x/", mapPins = { 0.2, 0.4, 1, 1 } },
      ["RXP Gold"] = { name = "RXP Gold", background = { 0.1, 0.07, 0, 1 }, textColor = { 1, 0.9, 0.7 }, font = ORIGIN,
        texturePath = "y/", mapPins = { 1, 0.8, 0, 1 } },
    },
    settings = { profile = { activeTheme = "RXP Blue", guideFontSize = 9, showFlightTimers = true } },
    enabledFrames = {}, registered = 0, renders = 0, v2 = { themes = {} },
  }
  function RXP.v2:IsGuideWindowEnabled() return RXP.V2 and true or false end
  function RXP:RegisterTheme(t) RXP.registered = RXP.registered + 1; RXP.themes[t.name] = t end
  RXP.activeTheme, RXP.colors, RXP.font = RXP.themes["RXP Blue"], RXP.themes["RXP Blue"], ORIGIN

  local edge = { bgFile = WHITE, edgeFile = "rxp/borders", edgeSize = 8, insets = { left = 4, right = 2, top = 2, bottom = 4 } }
  local frame = Fake("Frame")
  frame.backdrop = { edge = edge, guideName = edge }
  local function Part() local f = Fake("Frame"); f.text = f:CreateFontString(); f.bg = f:CreateTexture(); return f end
  frame.BottomFrame, frame.GuideName, frame.Footer = Fake("Frame"), Part(), Part()
  frame.GuideName:SetHeight(35)
  frame.Footer:SetHeight(20)
  frame.Footer.cog, frame.Footer.icon = Fake("Button"), Fake("Button")
  frame.CurrentStepFrame = Fake("Frame"); frame.CurrentStepFrame.framePool = {}
  function frame.CurrentStepFrame.UpdateText() end
  frame.ScrollChild = Fake("Frame"); frame.ScrollChild.framePool = {}
  frame.ScrollFrame = Fake("ScrollFrame")
  local scroll = Fake("Slider")
  scroll.thumb = Fake("texture")
  function scroll:GetThumbTexture() return self.thumb end
  for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    scroll[k] = Fake("Button")
    for _, piece in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do scroll[k][piece] = Fake("texture") end
  end
  frame.ScrollFrame.ScrollBar = scroll
  RXP.frame = frame
  function frame:UpdateVisuals()
    for _, f in ipairs({ frame.BottomFrame, frame.GuideName, frame.Footer }) do f:ClearBackdrop(); f:SetBackdrop(edge) end
  end
  RXP.enabledFrames.RXPFrame = frame
  function RXP.RenderFrame()
    local name = RXP.settings.profile.activeTheme
    RXP.activeTheme = RXP.themes[name] or RXP.themes["RXP Blue"]
    RXP.colors, RXP.font = RXP.activeTheme, RXP.activeTheme.font
    RXP.renders = RXP.renders + 1
    frame:UpdateVisuals()
  end
  function RXP.UpdateGuideFontSize() end
  RXP.currentGuide = true

  -- Timers.lua
  local candy = c.LibStub("LibCandyBar-3.0")
  local BarContainer = Fake("Frame")
  BarContainer.height = 16
  BarContainer.bars = {}
  BarContainer.barTexture = BAR_FILL
  BarContainer.barIcon = WATCH
  frame.BarContainer = BarContainer
  frame.IsShown = function() return true end
  RXP.sorts = 0
  local barPool = {}
  local function OnHide(self)
    BarContainer.bars[self:GetLabel()] = nil
    RXP:SortTimers()
  end
  function RXP:SortTimers()
    RXP.sorts = RXP.sorts + 1
    local bars = {}
    for _, bar in pairs(BarContainer.bars) do bars[#bars + 1] = bar end
    table.sort(bars, function(a, b) return a.exp > b.exp end)
    local last
    for _, bar in ipairs(bars) do
      bar:ClearAllPoints()
      if last then bar:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 0) else bar:SetPoint("TOPLEFT", BarContainer, "TOPLEFT", 0, 0) end
      last = bar
      bar:SetHeight(BarContainer.height)
    end
  end
  local function CreateBar(label)
    local bar
    for _, v in pairs(barPool) do
      if not v:IsShown() then bar = v; break end
    end
    if not bar then
      bar = candy:New(BarContainer.barTexture, 100, 16)
      table.insert(barPool, bar)
      bar:SetDuration(60)
      bar:SetScript("OnHide", OnHide)
    end
    bar:SetLabel(label)
    return bar
  end
  RXP.pool = barPool
  function RXP.HideTimers()
    for _, bar in pairs(barPool) do if bar:IsShown() then bar:Hide() end end
  end
  function RXP.ShowTimers()
    for _, bar in pairs(barPool) do
      if not bar:IsShown() and bar.exp and bar.exp > c.GetTime() then
        BarContainer.bars[bar:GetLabel()] = bar
        bar:Show()
      end
    end
    RXP:SortTimers()
  end
  function RXP.StopTimer(label)
    local bar = BarContainer.bars[label]
    if not bar then return end
    bar:Stop()
    RXP:SortTimers()
  end
  function RXP.StartTimer(duration, label, options)
    if type(duration) ~= "number" or duration <= 0 then return end
    label = label or ""
    local bar = BarContainer.bars[label] or CreateBar(label)
    BarContainer.bars[label] = bar
    bar:SetDuration(duration)
    bar:SetIcon(BarContainer.barIcon)
    bar:SetColor(unpack(RXP.colors.mapPins))
    bar:SetHeight(BarContainer.height)
    bar:Start()
    RXP:SortTimers()
    return bar
  end

  local ace = c.LibStub:NewLibrary("AceAddon-3.0", 1)
  function ace:GetAddon(name) if name == "RXPGuides" then return RXP end end
  c.RXPFrame = frame
  c.LOADED["RXPGuides"] = true
  return RXP
end

local function RestedXPLoads(c, RXP)
  local channel = c.RXPGuides_Themes
  if channel then
    for _, t in pairs(channel) do RXP:RegisterTheme(t) end
    for k in pairs(channel) do channel[k] = nil end
  end
  c.FireEvent("ADDON_LOADED", "RXPGuides")
  FlushTimers()
end

-- The usual set-up: TwichUI, the candy bar library and RestedXP loaded, the skin selected.
local function World(opts)
  opts = opts or {}
  local c = Boot({ db = opts.db or { modules = { restedxpSkin = true } } })
  local lib = MakeCandy(c)
  local R = Start(c)
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  local S = R.RestedXPSkin
  if opts.select ~= false then assert(S.UseTheme()); FlushTimers() end
  return c, R, S, RXP, lib
end

---------------------------------------------------------------------------
-- Defaults and validation
---------------------------------------------------------------------------
do
  local c = Boot()
  local R = Start(c)
  local T = R.RestedXPSkin.Timers
  assert(T and T.Opt and T.Look, "the module is there")
  local O = T.Opt
  assert(O.Get("skinTimers") == true, "timer skinning is on whenever the RestedXP skin is")
  assert(R:Enabled("restedxpSkin") == false, "the skin itself is not turned on by this")
  assert(O.Get("fillColor") == "ff80502d" and O.Get("fillColor2") == "ffc69a52", "burnished bronze to antique gold")
  assert(O.Get("fillGradient") == "horizontal" and O.Get("showIcon") == false and O.Get("barHeight") == 16)
  -- invalid values are refused and, saved by hand, read as the default without being erased
  assert(O.Set("barHeight", 99) == false and O.Set("labelSize", 2) == false and O.Set("fillColor", "red") == false)
  assert(O.Set("labelOutline", "huge") == false and O.Set("fillGradient", "diagonal") == false and O.Set("nope", 1) == false)
  assert(O.Set("barHeight", 20) and O.Get("barHeight") == 20)
  c.TwichUIDB.ui.restedxpTimerText.labelSize = 400
  c.TwichUIDB.ui.restedxpTimerText.fillTexture = 12
  c.TwichUIDB.ui.restedxpTimerText.showIcon = "yes"
  assert(O.Get("labelSize") == 10 and O.Get("fillTexture") == "solid" and O.Get("showIcon") == false)
  assert(c.TwichUIDB.ui.restedxpTimerText.labelSize == 400, "an unusable value is not erased")
  assert(T.Look.Get("borderSize") == 1 and T.Look.Get("borderColor") == "ff8c6e38")
  assert(T.Look.Set("borderOpacity", 40) and c.TwichUIDB.ui.restedxpTimerLook.borderOpacity == 40)
  T.Reset()
  assert(c.TwichUIDB.ui.restedxpTimerText == nil and c.TwichUIDB.ui.restedxpTimerLook == nil, "reset forgets the saved values")
  assert(O.Get("barHeight") == 16)
  local why = T.Status()
  assert(why.code == "skin-off", why.code)
end

---------------------------------------------------------------------------
-- Skin off: nothing hooked, no frames made, RestedXP's bars are its own.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = false } } })
  local lib = MakeCandy(c)
  local R = Start(c)
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  assert(c.hookCount == 0, "off: nothing is hooked")
  local before = #c.made
  local bar = RXP.StartTimer(30, "Waiting")
  assert(bar.candyBarBar.sbColor[1] == 0.2 and bar.candyBarBackdrop.backdropInfo == nil and bar:GetIcon() == WATCH)
  assert(bar.candyBarLabel.font[3] == "" and bar.candyBarLabel.wrap == true)
  assert(RXP.frame.BarContainer.height == 16)
  assert(lib.registrations == 0)
  assert(R.RestedXPSkin.Timers.Snapshot().drawn == 0)
end

---------------------------------------------------------------------------
-- On: a started bar is drawn; its countdown is not touched.
---------------------------------------------------------------------------
do
  local c, R, S, RXP, lib = World()
  local T = S.Timers
  assert(S.Status().code == "active")
  assert(c.hookCount == 3 + 1 + 2, "RenderFrame, UpdateText, UpdateGuideFontSize, the window's SetScale, then StartTimer and ShowTimers: " .. c.hookCount)
  local bar = RXP.StartTimer(45, "Waiting for the ceremony")
  local sb = bar.candyBarBar
  -- fill: flat texture, a gradient from the dark to the light end, the opacity carried by its colours
  assert(sb.sbFile == WHITE, "flat texture by default")
  local tex = sb:GetStatusBarTexture()
  assert(tex.gradient and tex.gradient[1] == "HORIZONTAL", "a left to right gradient")
  assert(near(tex.gradient[2].r, 0x80 / 255) and near(tex.gradient[2].g, 0x50 / 255) and near(tex.gradient[2].b, 0x2d / 255), "dark end #80502D")
  assert(near(tex.gradient[3].r, 0xc6 / 255) and near(tex.gradient[3].g, 0x9a / 255) and near(tex.gradient[3].b, 0x52 / 255), "light end #C69A52")
  assert(near(tex.gradient[2].a, 1) and near(sb.sbColor[1], 1) and near(sb.sbColor[4], 1), "neutral vertex colour: the gradient is the colour")
  -- background and border: the library's own backdrop frame, drawn with the shared look, just outside the bar
  local bd = bar.candyBarBackdrop
  assert(bd.backdropInfo and bd.backdropInfo.bgFile == WHITE and bd.backdropInfo.edgeFile == WHITE, "background and a one pixel line")
  assert(near(bd.bgColor[4], 0.85) and near(bd.edgeColor[4], 0.90), "separate opacities")
  assert(bd.points[1][1] == "TOPLEFT" and bd.points[1][4] == -1 and bd.points[1][5] == 1, "outside the bar, so the border never covers the fill")
  assert(bd:GetFrameLevel() == sb:GetFrameLevel() - 1, "just under the fill")
  assert(bar.candyBarBackground.vertex[4] == 0, "the library's own background gives way")
  -- text: face, size, outline, colour, a label that stops short of the time and is cut, not wrapped
  local label, time = bar.candyBarLabel, bar.candyBarDuration
  assert(label.font[1] == ORIGIN and label.font[2] == 10 and label.font[3] == "OUTLINE" and time.font[3] == "OUTLINE")
  assert(label.wrap == false and time.wrap == false)
  assert(near(label.color[1], 0xe9 / 255))
  local right = label.points[#label.points]
  assert(right[1] == "BOTTOMRIGHT" and right[2] == time and right[3] == "BOTTOMLEFT", "the label ends where the time begins")
  assert(time.points[1][1] == "TOPRIGHT" and time.points[1][4] == -4, "padding")
  -- icon: hidden by default, and its room is given back to the bar by the library's own call
  assert(bar:GetIcon() == nil and bar.candyBarIconFrame.shown == false)
  assert(sb.points[1][2] == bar, "the bar starts at the bar's own left edge")
  -- the countdown is RestedXP's
  assert(bar.exp == 1045 and bar.remaining == 45 and bar.running and bar.starts == 1)
  assert(sb.min == 0 and sb.max == 45 and sb.value == 45)
  assert(RXP.frame.BarContainer.height == 16, "its own height at the default")
  assert(RXP.frame.BarContainer.bars["Waiting for the ceremony"] == bar)
  assert(T.Status().code == "active")
end

---------------------------------------------------------------------------
-- Settings change while a timer runs; larger text makes the bar as tall as it needs; the timer is not restarted.
---------------------------------------------------------------------------
do
  local c, R, S, RXP = World()
  local T = S.Timers
  local bar = RXP.StartTimer(60, "Flight")
  local starts, exp = bar.starts, bar.exp
  assert(T.Opt.Set("fillGradient", "none") and T.Opt.Set("fillColor", "ff336699") and T.Opt.Set("fillOpacity", 50))
  assert(T.Opt.Set("labelSize", 16) and T.Opt.Set("timeSize", 12) and T.Opt.Set("showIcon", true) and T.Opt.Set("textPadding", 8))
  assert(T.Look.Set("borderSize", 3))
  FlushTimers()
  local tex = bar.candyBarBar:GetStatusBarTexture()
  assert(near(bar.candyBarBar.sbColor[1], 0x33 / 255) and near(bar.candyBarBar.sbColor[4], 0.5), "one colour, at the fill opacity")
  assert(tex.gradientSets == 2 and near(tex.gradient[2].r, 1) and near(tex.gradient[3].r, 1), "the gradient is neutralised, not left behind")
  assert(bar.candyBarLabel.font[2] == 16 and bar.candyBarDuration.font[2] == 12)
  assert(RXP.frame.BarContainer.height == math.ceil(16 * 1.25) + 2, "tall enough for the text: " .. RXP.frame.BarContainer.height)
  assert(bar.height == RXP.frame.BarContainer.height, "RestedXP's own layout set it")
  assert(bar:GetIcon() == WATCH, "the icon is back")
  assert(bar.candyBarLabel.points[1][4] == 8, "padding")
  assert(bar.candyBarBackdrop.points[1][4] == -3, "the border's reach follows its thickness")
  assert(bar.starts == starts and bar.exp == exp and bar.running, "no restart, same end time")
  -- a smaller height setting cannot cut the text; a bigger one is honoured
  assert(T.Opt.Set("labelSize", 10) and T.Opt.Set("timeSize", 10) and T.Opt.Set("barHeight", 24))
  FlushTimers()
  assert(RXP.frame.BarContainer.height == 24 and bar.height == 24)
end

---------------------------------------------------------------------------
-- Repeated starts: nothing new is made; the pool and the records stay as they were.
---------------------------------------------------------------------------
do
  local c, R, S, RXP, lib = World()
  local T = S.Timers
  local first = RXP.StartTimer(10, "A")
  RXP.StopTimer("A")
  FlushTimers()
  local frames = #c.made
  for i = 1, 20 do
    local bar = RXP.StartTimer(10 + i, i % 2 == 0 and "A" or "B")
    assert(bar, "started")
    RXP.StopTimer(i % 2 == 0 and "A" or "B")
  end
  assert(#c.made == frames, "no frame, texture or string was made by 20 more starts: " .. (#c.made - frames))
  assert(lib.created == 1, "the library made one bar")
  local snap = T.Snapshot()
  assert(snap.bars == 1, "one record for one pooled bar")
  assert(snap.drawn == 0, "stopped: nothing left drawn")
  assert(snap.styled == 21 and snap.restored == 21, "drawn at each start, put back at each stop: " .. snap.styled .. "/" .. snap.restored)
  -- RestedXP keeps its pooled bars in the library's cache too, so a bar it already ran is handed out again
  -- by the library (made afresh: its font and colours are the library's) and must be drawn again
  local again = RXP.StartTimer(30, "Third")
  assert(again == first and again.candyBarLabel.font[3] == "OUTLINE" and again.candyBarBackground.vertex[4] == 0)
  lib.cache[again] = true
  local made = lib:New(BAR_FILL, 100, 16)   -- what RestedXP's CreateBar does when its pool has no free bar
  assert(made == again and made.candyBarLabel.font[3] == "", "reset by the library")
  made:SetLabel("Fourth"); made:SetDuration(9); made:SetIcon(WATCH)
  RXP.frame.BarContainer.bars.Fourth = made
  made:Start()
  RXP.frame.BarContainer.bars.Third = nil
  RXP.StartTimer(9, "Fourth")
  assert(made.candyBarLabel.font[3] == "OUTLINE" and made.candyBarBackground.vertex[4] == 0, "drawn again at the start")
end

---------------------------------------------------------------------------
-- Several at once, as RestedXP stacks them: each drawn, and the library makes one bar for each.
---------------------------------------------------------------------------
do
  local c, R, S, RXP, lib = World()
  local T = S.Timers
  local a, b = RXP.StartTimer(30, "One"), RXP.StartTimer(20, "Two")
  assert(a ~= b and T.Snapshot().bars == 2 and lib.created == 2)
  assert(a.candyBarLabel.font[3] == "OUTLINE" and b.candyBarLabel.font[3] == "OUTLINE", "both drawn")
  assert(b.points[1][2] == a, "RestedXP's stacking is its own")
  T.Opt.Set("barHeight", 20); FlushTimers()
  assert(a.height == 20 and b.height == 20)
end

---------------------------------------------------------------------------
-- Hook idempotency: the switch and the timer setting any number of times.
---------------------------------------------------------------------------
do
  local c, R, S, RXP, lib = World()
  local T = S.Timers
  local hooks = c.hookCount
  for _ = 1, 4 do
    c.TwichUIDB.modules.restedxpSkin = false
    S.OnSwitch()
    c.TwichUIDB.modules.restedxpSkin = true
    S.OnSwitch()
    FlushTimers()
    T.Opt.Set("skinTimers", false)
    T.Opt.Set("skinTimers", true)
    FlushTimers()
  end
  c.FireEvent("ADDON_LOADED", "RXPGuides"); FlushTimers()
  assert(c.hookCount == hooks or c.hookCount == hooks + 1, "no hook twice (the item tray's, once): " .. c.hookCount .. " vs " .. hooks)
  local snap = T.Snapshot()
  assert(snap.hookStart and snap.hookShow and snap.stopCallback)
  -- one StartTimer is one drawing
  assert(S.UseTheme()); FlushTimers()
  local bar = RXP.StartTimer(12, "Once")
  assert(bar.candyBarBar.sbTex.gradientSets == 1, "drawn once for one start: " .. tostring(bar.candyBarBar.sbTex.gradientSets))
end

---------------------------------------------------------------------------
-- A stopped bar goes back to the shared cache as it was; another addon's bar made from it is not ours.
---------------------------------------------------------------------------
do
  local c, R, S, RXP, lib = World()
  local T = S.Timers
  local bar = RXP.StartTimer(15, "Stopped")
  assert(bar.candyBarLabel.font[3] == "OUTLINE" and bar.candyBarBackdrop.backdropInfo)
  RXP.StopTimer("Stopped")
  assert(lib.cache[bar], "in the library's cache")
  assert(bar.candyBarLabel.font[2] == 10 and bar.candyBarLabel.font[3] == "" and bar.candyBarLabel.wrap == true, "its own font and wrap")
  assert(bar.candyBarLabel.points[1][1] == "TOPLEFT" and bar.candyBarLabel.points[1][4] == 2 and #bar.candyBarLabel.points == 2, "its anchors")
  assert(bar.candyBarBackdrop.backdropInfo == nil and bar.candyBarBackdrop.shown == false, "no backdrop left for another addon's styler")
  assert(bar.candyBarBar.sbFile == BAR_FILL, "RestedXP's texture")
  assert(near(bar.candyBarBackground.vertex[4], 0.3), "the library's background strength")
  -- another addon takes it
  local foreign = lib:New("Interface\\Foreign", 200, 12)
  assert(foreign == bar and bar.candyBarLabel.font[3] == "" and bar.candyBarBackdrop.backdropInfo == nil)
end

---------------------------------------------------------------------------
-- Turning the look off while a timer runs: restored, not restarted; a newer RestedXP value wins.
---------------------------------------------------------------------------
do
  local c, R, S, RXP, lib = World()
  local T = S.Timers
  local bar = RXP.StartTimer(90, "Long wait")
  assert(T.Opt.Set("barHeight", 22)); FlushTimers()
  assert(RXP.frame.BarContainer.height == 22)
  local before = { exp = bar.exp, start = bar.start, starts = bar.starts, shown = bar:IsShown(), value = bar.candyBarBar.value }
  -- RestedXP's own colour changes meanwhile (the player picked a theme colour); the stale one must not return
  RXP.colors.mapPins = { 0.9, 0.1, 0.1, 1 }
  T.Opt.Set("skinTimers", false)
  FlushTimers()
  assert(S.Status().code == "active", "the guide window keeps its look")
  assert(T.Status().code == "off")
  assert(bar.starts == before.starts and bar.exp == before.exp and bar.start == before.start and bar.running, "same countdown")
  assert(bar:IsShown() == before.shown and RXP.frame.BarContainer.bars["Long wait"] == bar, "visible and kept under its label")
  assert(bar.candyBarBar.sbColor[1] == 0.9 and bar.candyBarBar.sbColor[2] == 0.1, "RestedXP's colour as it is now")
  assert(bar.candyBarBar:GetStatusBarTexture().gradient[2].r == 1, "no gradient left")
  assert(bar.candyBarLabel.font[3] == "" and bar.candyBarLabel.wrap == true and bar:GetIcon() == WATCH)
  assert(bar.candyBarBackdrop.backdropInfo == nil)
  assert(RXP.frame.BarContainer.height == 16 and bar.height == 16, "RestedXP's own height, by its own layout")
  assert(T.Snapshot().drawn == 0)
  -- and on again: drawn again, still the same timer
  T.Opt.Set("skinTimers", true); FlushTimers()
  assert(bar.candyBarLabel.font[3] == "OUTLINE" and RXP.frame.BarContainer.height == 22 and bar.starts == before.starts)
  -- a height RestedXP set itself in the meantime is not overwritten when the look goes
  RXP.frame.BarContainer.height = 18
  c.TwichUIDB.modules.restedxpSkin = false
  S.OnSwitch(); FlushTimers()
  assert(RXP.frame.BarContainer.height == 18, "a newer RestedXP value stays")
  assert(bar.candyBarLabel.font[3] == "" and bar.running and bar.exp == before.exp)
end

---------------------------------------------------------------------------
-- Another theme chosen, or a conflict: the bars are given back; a timer that starts then is not drawn.
---------------------------------------------------------------------------
do
  local c, R, S, RXP = World()
  local T = S.Timers
  local bar = RXP.StartTimer(40, "Boat")
  assert(bar.candyBarLabel.font[3] == "OUTLINE")
  RXP.settings.profile.activeTheme = "RXP Gold"
  RXP.RenderFrame()
  FlushTimers()
  assert(S.Status().code == "theme-not-selected" and T.Status().code == "skin-off")
  assert(bar.candyBarLabel.font[3] == "" and bar.candyBarBackdrop.backdropInfo == nil and bar.running)
  local other = RXP.StartTimer(20, "Another")
  assert(other.candyBarLabel.font[3] == "", "not drawn while the skin isn't")
  assert(near(other.candyBarBar.sbColor[1], 1) and other.candyBarBar.sbColor[1] == 1, "RestedXP's gold pins")
  -- back to ours
  RXP.settings.profile.activeTheme = "TwichUI"
  RXP.RenderFrame(); FlushTimers()
  assert(bar.candyBarLabel.font[3] == "OUTLINE" and other.candyBarLabel.font[3] == "OUTLINE", "both drawn again")
  -- the v2 window
  RXP.V2 = true
  RXP.RenderFrame(); FlushTimers()
  assert(bar.candyBarLabel.font[3] == "" and T.Status().code == "skin-off", "the v2 window's bars are RestedXP's own")
end

---------------------------------------------------------------------------
-- Combat: nothing is drawn until it ends; the bar still runs.
---------------------------------------------------------------------------
do
  local c, R, S, RXP = World()
  local T = S.Timers
  c.COMBAT = true
  local bar = RXP.StartTimer(30, "In combat")
  assert(bar.candyBarLabel.font[3] == "" and bar.running, "left as RestedXP draws it")
  T.Opt.Set("labelSize", 12); FlushTimers()
  assert(bar.candyBarLabel.font[3] == "")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); FlushTimers()
  assert(bar.candyBarLabel.font[3] == "OUTLINE" and bar.candyBarLabel.font[2] == 12, "drawn once combat ends")
  -- a bar that stops in combat is put back when it ends
  c.COMBAT = true
  RXP.StopTimer("In combat")
  assert(bar.candyBarLabel.font[3] == "OUTLINE", "waits")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); FlushTimers()
  assert(bar.candyBarLabel.font[3] == "" and bar.candyBarBackdrop.backdropInfo == nil)
end

---------------------------------------------------------------------------
-- Media: a missing texture or font falls back, stays chosen, and is drawn when the pack arrives.
---------------------------------------------------------------------------
do
  local c, R, S, RXP = World()
  local T = S.Timers
  local LSM = c.LibStub("LibSharedMedia-3.0")
  assert(T.Opt.Set("fillTexture", "Gone Bar") and T.Opt.Set("labelFont", "Gone Font"))
  local bar = RXP.StartTimer(30, "Media")
  FlushTimers()
  assert(bar.candyBarBar.sbFile == BAR_FILL, "RestedXP's own texture while the saved one is missing: " .. tostring(bar.candyBarBar.sbFile))
  assert(bar.candyBarLabel.font[1] == ORIGIN, "the guide's own font")
  assert(c.TwichUIDB.ui.restedxpTimerText.fillTexture == "Gone Bar" and c.TwichUIDB.ui.restedxpTimerText.labelFont == "Gone Font", "still chosen")
  local snap = T.Snapshot()
  assert(snap.fallbackFill and snap.fallbackLabel)
  local choices = T.FillChoices("Gone Bar")
  assert(choices[#choices][1] == "Gone Bar" and choices[#choices][2]:find("not available", 1, true), "listed, marked")
  assert(choices[1][1] == "default" and choices[2][1] == "solid")
  -- the pack arrives
  LSM:Register("statusbar", "Gone Bar", [[Interface\AddOns\Pack\bar]])
  FlushTimers()
  assert(bar.candyBarBar.sbFile == [[Interface\AddOns\Pack\bar]], "drawn when it arrives")
  assert(T.Snapshot().fallbackFill == nil)
  -- "default" is RestedXP's own texture, by choice
  assert(T.Opt.Set("fillTexture", "default")); FlushTimers()
  assert(bar.candyBarBar.sbFile == BAR_FILL)
end

---------------------------------------------------------------------------
-- A client that can't draw the gradient: a solid colour between the two, counted.
---------------------------------------------------------------------------
do
  local c, R, S, RXP = World()
  local T = S.Timers
  c.GRADIENT_FAILS = true
  local bar = RXP.StartTimer(30, "No gradient")
  local sb = bar.candyBarBar
  assert(near(sb.sbColor[1], (0x80 + 0xc6) / 2 / 255), "the average of the two")
  assert(T.Snapshot().gradientFallbacks == 1)
  c.GRADIENT_FAILS = false
end

---------------------------------------------------------------------------
-- The preview: its own frames, the real drawing code, nothing of RestedXP's or the library's.
---------------------------------------------------------------------------
do
  local c, R, S, RXP, lib = World()
  local T = S.Timers
  c.SettingsPanel = c.Fake("Frame")
  local starts, news, sorts = 0, lib.news, RXP.sorts
  local real = RXP.StartTimer
  RXP.StartTimer = function(...) starts = starts + 1; return real(...) end
  assert(T.PreviewShown() == false)
  T.TogglePreview()
  assert(T.PreviewShown() == true)
  assert(starts == 0 and lib.news == news and next(RXP.frame.BarContainer.bars) == nil, "no timer, no library bar")
  assert(RXP.sorts == sorts, "RestedXP's layout was not run")
  local found
  for _, f in ipairs(c.made) do if f.name == "TwichUIRXPTimerPreview" then found = f end end
  assert(found and found.shown and found.parent == c.UIParent, "a frame of its own")
  assert(#found.points >= 1)
  -- drawn by the real code: its bars carry the saved look
  local drawn = 0
  for _, f in ipairs(c.made) do
    if f.kind == "font" and f.font and f.font[3] == "OUTLINE" and f.parent and f.parent.kind == "StatusBar" then drawn = drawn + 1 end
  end
  assert(drawn == 4, "two bars, a label and a time each: " .. drawn)
  local snap = T.Snapshot()
  assert(snap.drawn == 0 and snap.bars == 0, "the live records are untouched")
  -- a setting changes: the preview follows
  assert(T.Opt.Set("barHeight", 20)); FlushTimers()
  local heights = {}
  for _, f in ipairs(c.made) do
    if f.parent == found and f.kind == "Frame" and f.height then heights[#heights + 1] = f.height end
  end
  assert(#heights >= 2 and heights[1] == 20, "the sample bars are the new height")
  assert(RXP.frame.BarContainer.height == 20)
  -- a real timer is separate from it
  local live = RXP.StartTimer(30, "Real")
  assert(starts == 1 and live ~= nil and RXP.frame.BarContainer.bars.Real == live)
  -- hidden: put away, and again when the options window closes or the module goes
  T.TogglePreview()
  assert(T.PreviewShown() == false)
  T.TogglePreview()
  assert(T.PreviewShown() == true)
  c.TwichUIDB.modules.restedxpSkin = false
  S.OnSwitch(); FlushTimers()
  assert(T.PreviewShown() == false, "gone with the module")
  assert(live.running and live.exp == 1030, "the real timer was never part of it")
  RXP.StartTimer = real
end

---------------------------------------------------------------------------
-- The troubleshooting report carries counts and flags only.
---------------------------------------------------------------------------
do
  local c, R, S, RXP = World()
  RXP.StartTimer(30, "Secret quest name")
  local report = R.Diag.Build()
  assert(report:find("timer bars", 1, true), "a line for the timer bars")
  assert(not report:find("Secret quest name", 1, true), "no timer text")
end

print("RESTEDXP TIMER TESTS PASSED")
