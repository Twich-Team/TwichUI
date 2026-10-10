-- RestedXP skin (modules/RestedXPSkin.lua): off by default and silent when off; works without RestedXP and
-- without EllesmereUI; either load order; one theme and one set of hooks however many times it is
-- switched; settings coalesced into one update and held in combat; media fallbacks keep the saved choice;
-- semantic colours left alone; turning it off gives RestedXP its own look back (by RestedXP's own refresh);
-- another RestedXP skin and the v2 window are stepped around; repeated styling creates nothing new; the
-- troubleshooting section is safe when RestedXP is missing and carries no guide text.
-- RestedXP is simulated from the source of v4.11.22 (GuideWindow.lua, Themes.lua): the same names and the
-- same order of calls, not the game.
dofile(TESTS .. "harness.lua")

local ORIGIN = [[Fonts\FRIZQT__.TTF]]
local WHITE = [[Interface\Buttons\WHITE8x8]]

---------------------------------------------------------------------------
-- A small fake of the game's frames: enough of the backdrop mixin, fonts and textures.
---------------------------------------------------------------------------
local function Boot(opts)
  opts = opts or {}
  local addons = { "!!!TwichUI" }
  for _, a in ipairs(opts.addons or {}) do addons[#addons + 1] = a end
  local c = MakeClient("Rich", addons)
  local made = {}   -- every object created
  local Methods
  local function Fake(kind)
    local o = { kind = kind, shown = true, scripts = {}, points = {}, backdropCalls = 0, alpha = 1, vertex = { 1, 1, 1, 1 } }
    made[#made + 1] = o
    return setmetatable(o, { __index = function(_, k)
      if Methods[k] then return Methods[k] end
      if type(k) == "string" and k:find("^%u") then return function() end end
    end })
  end
  Methods = {
    Show = function(s) s.shown = true end,
    Hide = function(s) s.shown = false end,
    IsShown = function(s) return s.shown end,
    SetShown = function(s, v) s.shown = v and true or false end,
    SetScript = function(s, n, fn) s.scripts[n] = fn end,
    GetScript = function(s, n) return s.scripts[n] end,
    SetFrameLevel = function(s, v) s.level = v end,
    GetFrameLevel = function(s) return s.level or 1 end,
    CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
    CreateFontString = function(s) local t = Fake("font"); t.parent = s; t.font = { ORIGIN, 12, "" }; t.color = { 1, 1, 1 }; return t end,
    SetText = function(s, v) s.text = v end,
    GetText = function(s) return s.text end,
    ClearAllPoints = function(s) s.points = {} end,
    -- (point, relativeTo, [relativePoint,] [x, y]); a point already set is replaced, as in the game
    SetPoint = function(s, point, a, b, c, d)
      local rel, rp, x, y
      if type(a) == "number" then rel, rp, x, y = s.parent, point, a, b
      elseif type(b) == "string" then rel, rp, x, y = a, b, c, d
      else rel, rp, x, y = a, point, b, c end
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
    GetStringHeight = function(s)
      local size = s.font and s.font[2] or 12
      local lines = s.lines or 1
      return size * lines + (s.spacing or 0) * (lines - 1)
    end,
    GetStringWidth = function(s) return s.stringWidth or 40 end,
    SetSpacing = function(s, v) s.spacing = v; s.spacingSets = (s.spacingSets or 0) + 1 end,
    GetSpacing = function(s) return s.spacing or 0 end,
    SetTexture = function(s, v) s.file = v; s.textureSets = (s.textureSets or 0) + 1 end,
    GetTexture = function(s) return s.file end,
    SetTexCoord = function(s, ...) s.coords = { ... } end,
    GetTexCoord = function(s) local t = s.coords or { 0, 0, 0, 1, 1, 0, 1, 1 }; return unpack(t) end,
    SetFontObject = function(s, o) s.fontObject = o end,
    HookScript = function(s, name, fn) s.hooked = s.hooked or {}; s.hooked[name] = fn end,
    IsEnabled = function(s) return s.enabled ~= false end,
    Enable = function(s) s.enabled = true; if s.hooked and s.hooked.OnEnable then s.hooked.OnEnable(s) end end,
    Disable = function(s) s.enabled = false; if s.hooked and s.hooked.OnDisable then s.hooked.OnDisable(s) end end,
    SetColorTexture = function(s, r, g, b, a) s.color = { r, g, b, a } end,
    SetBackdrop = function(s, info)
      if info ~= nil and s.backdropInfo == info then return end
      s.backdropCalls = s.backdropCalls + 1
      if info and (info.bgFile or info.edgeFile) then s.backdropInfo = info else s.backdropInfo = nil end
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
    GetFont = function(s) return s.font[1], s.font[2], s.font[3] end,
    SetTextColor = function(s, r, g, b) s.color = { r, g, b }; s.colorSets = (s.colorSets or 0) + 1 end,
    GetTextColor = function(s) return s.color[1], s.color[2], s.color[3] end,
    SetVertexColor = function(s, r, g, b, a) s.vertex = { r, g, b, a or 1 } end,
    GetVertexColor = function(s) return s.vertex[1], s.vertex[2], s.vertex[3], s.vertex[4] end,
    EnableMouse = function() end,
    GetEffectiveScale = function() return 1 end,
  }
  c.Fake, c.made = Fake, made
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind); f.name, f.parent = name, parent; return f end
  c.UIParent = Fake("UIParent")
  c.STANDARD_TEXT_FONT = ORIGIN
  c.GameFontNormal = { GetFont = function() return ORIGIN, 12, "" end }
  c.GameFontNormalSmall = { GetFont = function() return ORIGIN, 10, "" end }
  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
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
  for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/RestedXPSkin.lua", "diag/Diagnostics.lua", "diag/RestedXPSkin.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  if opts.ellesmere == false then c.EllesmereUI = nil end
  return c
end

local function Start(c)
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  return c.TwichUI
end

---------------------------------------------------------------------------
-- RestedXP, as far as the skin can see it.
---------------------------------------------------------------------------
local function MakeRestedXP(c, opts)
  opts = opts or {}
  local Fake = c.Fake
  local RXP = {
    themes = {
      ["RXP Blue"] = { name = "RXP Blue", background = { 0.05, 0.05, 0.1, 1 }, textColor = { 1, 1, 1 }, font = ORIGIN, texturePath = "x/" },
      ["RXP Gold"] = { name = "RXP Gold", background = { 0.1, 0.07, 0, 1 }, textColor = { 1, 0.9, 0.7 }, font = ORIGIN, texturePath = "y/" },
    },
    settings = { profile = { activeTheme = "RXP Blue", guideFontSize = 9 } },
    enabledFrames = {}, registered = 0, renders = 0, converts = 0, v2 = { themes = {} },
  }
  function RXP.v2:IsGuideWindowEnabled() return RXP.V2 and true or false end
  function RXP.v2:ConvertThemes() RXP.converts = RXP.converts + 1 end
  function RXP:RegisterTheme(t)
    RXP.registered = RXP.registered + 1
    RXP.themes[t.name] = t
  end
  RXP.activeTheme, RXP.colors, RXP.font = RXP.themes["RXP Blue"], RXP.themes["RXP Blue"], ORIGIN

  local edge = { bgFile = WHITE, edgeFile = "rxp/borders", tile = true, edgeSize = 8, tileSize = 8,
    insets = { left = 4, right = 2, top = 2, bottom = 4 } }
  local guideName = { edgeFile = "rxp/borders", edgeSize = 8, insets = { left = 4, right = 2, top = 2, bottom = 4 } }
  local frame = Fake("Frame")
  frame.backdrop = { edge = edge, guideName = guideName, bottom = { bgFile = WHITE, tile = true, tileSize = 16 } }
  local csf = Fake("Frame")
  csf.framePool = {}
  local function Part() local f = Fake("Frame"); f.text = f:CreateFontString(); f.bg = f:CreateTexture(); return f end
  frame.BottomFrame, frame.GuideName, frame.Footer = Fake("Frame"), Part(), Part()
  frame.CurrentStepFrame = csf
  frame.ScrollChild = Fake("Frame"); frame.ScrollChild.framePool = {}
  local bar = Fake("Slider")
  bar.thumb = Fake("texture")
  function bar:GetThumbTexture() return self.thumb end
  for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    bar[k] = Fake("Button")
    for _, piece in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do bar[k][piece] = Fake("texture") end
  end
  -- the header, footer and scroll bar as RestedXP anchors and sizes them (GuideWindow.lua)
  local g, f = frame.GuideName, frame.Footer
  g:SetHeight(35)
  g.icon, g.classIcon = g:CreateTexture(), g:CreateTexture()
  g.icon:SetSize(42, 42); g.classIcon:SetSize(24, 24)
  g.icon:SetPoint("CENTER", g, "LEFT", 16, 0)
  g.classIcon:SetPoint("CENTER", g.icon, "BOTTOMRIGHT", -4, 10)
  g.text:SetPoint("LEFT", g, 29, 0); g.text:SetPoint("RIGHT", g, 0, 0)
  f:SetHeight(20)
  f.text:SetPoint("LEFT", f, 40, 1); f.text:SetPoint("RIGHT", f, -16, 1)
  f.text:SetText("RXP Beta v4.11.22 0/11")
  f.cog = Fake("Button")
  f.icon = Fake("Button"); f.icon.parent = f
  f.text.parent = g   -- RestedXP makes the footer's string on the header's frame
  f.cog.parent = frame
  function frame.TimersShow(on)   -- Timers.lua: the footer's string, button and grip give way to a timer bar
    for _, part in ipairs({ f.text, f.cog, f.icon }) do part:SetAlpha(on and 0 or 1) end
  end
  frame.BottomFrame:SetPoint("TOPLEFT", frame, 3, -3)      -- GuideWindow.lua: the list runs 6 px behind the footer
  frame.BottomFrame:SetPoint("BOTTOMRIGHT", frame, -3, 14)
  frame.ScrollFrame = Fake("ScrollFrame")
  frame.ScrollFrame.ScrollBar = bar
  frame.ScrollFrame:SetPoint("TOPLEFT", frame.BottomFrame, 5, -5)
  frame.ScrollFrame:SetPoint("BOTTOMRIGHT", frame.BottomFrame, -20, 7)
  bar:SetPoint("TOPLEFT", frame.ScrollFrame, "TOPRIGHT", 0, -18)
  bar:SetPoint("BOTTOMLEFT", frame.ScrollFrame, "BOTTOMRIGHT", 6, 16)
  bar:SetWidth(16)
  bar.thumb:SetSize(18, 24)
  bar.thumb:SetTexCoord(0.2, 0.125, 0.2, 0.875, 0.8, 0.125, 0.8, 0.875)
  bar.thumb.file = "rxp/Knob"
  for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    bar[k]:SetSize(18, 16)
    for _, piece in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do bar[k][piece].file = "rxp/" .. k .. piece end
  end
  function frame.UpdateScrollBar()   -- GuideWindow.lua RXPFrame.UpdateScrollBar
    bar.thumb.file = "rxp/Knob"
    for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
      for _, piece in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do bar[k][piece].file = "rxp/" .. k .. piece end
    end
  end
  frame.GuideName.text:SetText("Guide title: " .. (opts.guideText or "Durotar"))
  RXP.frame = frame

  local function Paint(f, info)
    f:ClearBackdrop()
    f:SetBackdrop(info)
    f:SetBackdropColor(unpack(RXP.colors.background))
  end
  function frame:UpdateVisuals()
    Paint(frame.BottomFrame, edge)
    Paint(frame.GuideName, guideName)
    Paint(frame.Footer, guideName)
    frame.GuideName.text:SetFont(RXP.font, 11, ""); frame.GuideName.text:SetTextColor(unpack(RXP.activeTheme.textColor))
    frame.Footer.text:SetFont(RXP.font, 9, ""); frame.Footer.text:SetTextColor(unpack(RXP.activeTheme.textColor))
  end
  RXP.enabledFrames.RXPFrame = frame

  RXP.activeSteps = opts.steps or { { elements = { { text = "Kill boars" }, { text = "Turn in" } } } }
  RXP.layouts = 0
  -- GuideWindow.lua CurrentStepFrame.UpdateText: a line is ceil(text * 1.1) + 1 high, a card is its lines + 18
  -- (10 above, 8 below), cards are 5 apart, and the panel is all of them less 5.
  function csf.UpdateText()
    RXP.layouts = RXP.layouts + 1
    local total = 0
    for i, step in ipairs(RXP.activeSteps) do
      local sf = csf.framePool[i]
      if not sf then
        sf = Fake("Frame")
        sf.number = Part()
        sf.number.text:SetFont(RXP.font, RXP.settings.profile.guideFontSize, "")   -- set once, when RestedXP makes the tab
        sf.number:SetPoint("TOPLEFT", sf, 7, 5)
        sf.elements = {}
        csf.framePool[i] = sf
      end
      sf.step = step
      if sf.theme ~= RXP.activeTheme then   -- RestedXP's own gate (GuideWindow.lua: stepframe.theme)
        sf.theme = RXP.activeTheme
        Paint(sf, edge)
        Paint(sf.number, edge)
      end
      sf.number.text:SetText(step.title or ("Step " .. i))
      sf.number:SetSize(sf.number.text:GetStringWidth() + 10, 17)
      local sum = 0
      for j, element in ipairs(step.elements) do
        local ef = sf.elements[j]
        if not ef then
          ef = Fake("Frame")
          ef.text = ef:CreateFontString()
          ef.text:SetFont(RXP.font, RXP.settings.profile.guideFontSize + 2, "")
          ef.text:SetTextColor(unpack(RXP.activeTheme.textColor))
          ef.icon = ef:CreateFontString()
          ef.icon:SetFont(ORIGIN, 10, "")
          sf.elements[j] = ef
        end
        ef.text:SetText(element.text)
        ef.text.lines = element.lines or 1
        local h = math.ceil(ef.text:GetStringHeight() * 1.1) + 1
        ef:SetHeight(h)
        ef:SetAlpha(1)
        ef:Show()
        ef:ClearAllPoints()
        if j == 1 then
          ef:SetPoint("TOPLEFT", sf, 0, -10); ef:SetPoint("TOPRIGHT", sf, 0, -10)
        else
          ef:SetPoint("TOPLEFT", sf.elements[j - 1], "BOTTOMLEFT", 0, 0)
          ef:SetPoint("TOPRIGHT", sf.elements[j - 1], "BOTTOMRIGHT", 0, 0)
        end
        sum = sum + h
      end
      sf:SetHeight(math.ceil(sum + 18))
      sf:SetAlpha(1)
      sf:Show()
      if not step.tip then total = total + sf:GetHeight() + 5 end
    end
    csf:SetHeight(total - 5)
  end

  -- the guide list: GuideWindow.lua LoadGuide (rows, fonts and anchors) and BottomFrame.UpdateFrame (heights)
  RXP.listLayouts = 0
  RXP.progress = 1
  function RXP.GetGuideProgress() return RXP.progress end
  frame.ScrollChild.f1 = Fake("Frame")
  function frame.BottomFrame.UpdateFrame(self)
    RXP.listLayouts = RXP.listLayouts + 1
    RXP.lastListSelf = self
    for _, row in ipairs(frame.ScrollChild.framePool) do
      row:SetHeight(math.ceil(row.text:GetStringHeight() + 8))
      -- done steps at half strength, the rest full (GuideWindow.lua UpdateFrame)
      row:SetAlpha((row.step and row.step.index < RXP.progress) and 0.5 or 1)
    end
    local height = 0
    for i, row in ipairs(frame.ScrollChild.framePool) do
      local _, _, _, _, y = row:GetPoint(1)
      height = height + row:GetHeight() + (i > 1 and -(y or 0) or 3)
    end
    frame.ScrollChild:SetHeight(height)
  end
  function RXP.LoadRows()
    local pool = frame.ScrollChild.framePool
    for n = 1, opts.rows or 0 do
      local row = pool[n]
      if not row then
        row = Fake("Frame")
        row.text = row:CreateFontString()
        row.number = Fake("Frame")
        row.number:SetPoint("BOTTOMRIGHT", row, 0, 0)
        row.number.text = row.number:CreateFontString()
        row.number.text:SetFont(RXP.font, RXP.settings.profile.guideFontSize - 1, "")
        row.number.text:SetTextColor(unpack(RXP.activeTheme.textColor))
        pool[n] = row
      end
      row:ClearAllPoints()
      if n == 1 then
        row:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", 2, -3)
        row:SetPoint("TOPRIGHT", frame.ScrollChild, "TOPRIGHT", 2, -3)
      else
        row:SetPoint("TOPLEFT", pool[n - 1], "BOTTOMLEFT", 0, -3)
        row:SetPoint("TOPRIGHT", pool[n - 1], "BOTTOMRIGHT", 0, -3)
      end
      row.text:ClearAllPoints()
      row.text:SetPoint("TOPLEFT", row, 0, -5)
      row.text:SetPoint("RIGHT", row.number, "LEFT", 0, 0)
      row.text:SetFont(RXP.font, RXP.settings.profile.guideFontSize, "")
      row.text:SetTextColor(unpack(RXP.activeTheme.textColor))
      row.text:SetText("row " .. n)
      row.step = row.step or { index = n }
      -- RestedXP sets a new OnEnter on every guide load (GuideWindow.lua LoadGuide)
      row.scripts.OnEnter = function(self) self.currentAlpha = self:GetAlpha(); self:SetAlpha(1) end
      row.scripts.OnLeave = function(self) self:SetAlpha(self.currentAlpha) end
      row.text.lines = (opts.rowLines and opts.rowLines[n]) or 1
    end
  end
  function RXP.RenderFrame(themeUpdate, isLoading)   -- GuideWindow.lua addon.RenderFrame
    local name = RXP.settings.profile.activeTheme
    RXP.activeTheme = RXP.themes[name] or RXP.themes["RXP Blue"]
    RXP.colors, RXP.font = RXP.activeTheme, RXP.activeTheme.font
    RXP.renders = RXP.renders + 1
    for _, f in pairs(RXP.enabledFrames) do if f.UpdateVisuals then f:UpdateVisuals(true) end end
    if RXP.currentGuide and not isLoading then
      RXP.LoadRows()
      csf.UpdateText()
      frame.BottomFrame.UpdateFrame()
    end
  end
  function RXP.UpdateGuideFontSize()
    frame.GuideName.text:SetFont(RXP.font, RXP.settings.profile.guideFontSize + 2, "")
    frame.Footer.text:SetFont(RXP.font, RXP.settings.profile.guideFontSize, "")
  end
  -- the item tray
  local item = Fake("Frame")
  item.title = Part()
  function item:UpdateVisuals()
    if RXP.settings.profile.activeItemHideBG then self:ClearBackdrop() else Paint(self, edge) end
    Paint(self.title, edge)
    self.title.text:SetFont(RXP.font, 9, ""); self.title.text:SetTextColor(unpack(RXP.activeTheme.textColor))
  end
  RXP.item = item
  if not opts.noItem then RXP.activeItemFrame = item; RXP.enabledFrames.activeItemFrame = item end
  RXP.currentGuide = true

  -- the waypoint arrow (map.lua): a frame, one rotated texture, a string; RestedXP sets the picture in
  -- UpdateVisuals, the size in SetSize and the string's font in SetFont
  if opts.arrow then
    RXP.settings.profile.arrowScale, RXP.settings.profile.arrowText = 1, 9
    local arrow = Fake("Frame")
    arrow.texture = arrow:CreateTexture()
    arrow.text = arrow:CreateFontString()
    arrow.text:SetFont(ORIGIN, 9, "OUTLINE")
    arrow:SetSize(32, 32)
    function arrow:UpdateVisuals()
      self.texture:SetTexture(RXP.activeTheme.texturePath .. "rxp_navigation_arrow-1")
    end
    arrow:UpdateVisuals()
    RXP.arrowFrame = arrow
    RXP.enabledFrames.arrowFrame = arrow
    RXP.themes["RXP Gold"].displayName = "RXP Gold"
    RXP.v2.themes["RXP Blue V2"] = { navigationArrow = "v2/rxp_navigation_arrow-1" }
  end

  -- the game shares AceAddon through LibStub; the skin finds RestedXP there
  local ace = c.LibStub:NewLibrary("AceAddon-3.0", 1)
  function ace:GetAddon(name) if name == "RXPGuides" then return RXP end end
  c.RXPFrame = frame
  c.LOADED["RXPGuides"] = true
  RXP.frame.UpdateVisuals(frame)
  return RXP
end

-- RestedXP's own start-up: it takes what third parties put in the RXPGuides_Themes channel.
local function RestedXPLoads(c, RXP)
  local channel = c.RXPGuides_Themes
  if channel then
    for _, t in pairs(channel) do RXP:RegisterTheme(t) end
    for k in pairs(channel) do channel[k] = nil end
  end
  c.FireEvent("ADDON_LOADED", "RXPGuides")
  FlushTimers()
end

local function near(a, b) return math.abs(a - b) < 0.003 end
local function Frames(RXP)
  local list = { RXP.frame.BottomFrame, RXP.frame.GuideName, RXP.frame.Footer }
  for _, sf in ipairs(RXP.frame.CurrentStepFrame.framePool) do list[#list + 1] = sf; list[#list + 1] = sf.number end
  return list
end
local function Ours(RXP, f) return f.backdropInfo ~= nil and f.backdropInfo ~= RXP.frame.backdrop.edge and f.backdropInfo ~= RXP.frame.backdrop.guideName end

---------------------------------------------------------------------------
-- Off by default: nothing registered, nothing hooked, nothing in RestedXP's lists.
---------------------------------------------------------------------------
do
  local c = Boot()
  local R = Start(c)
  assert(R.DEFAULT_MODULES.restedxpSkin == false and R:Enabled("restedxpSkin") == false, "opt-in")
  assert(R.RestedXPSkin.Status().code == "off")
  assert(c.RXPGuides_Themes == nil, "no theme is put anywhere while off")
  assert(c.hookCount == 0, "nothing hooked")
  -- RestedXP arriving changes nothing
  local RXP = MakeRestedXP(c)
  c.FireEvent("ADDON_LOADED", "RXPGuides"); FlushTimers()
  assert(c.hookCount == 0 and RXP.registered == 0 and RXP.renders == 0, "still nothing")
  assert(RXP.themes["TwichUI"] == nil)
  assert(#TIMERS == 0, "no timer waits")
  local snap = R.RestedXPSkin.Snapshot()
  assert(snap.hooks == 0 and snap.owned == 0 and snap.scheduled == false)
end

---------------------------------------------------------------------------
-- On, but RestedXP is not installed (and EllesmereUI is absent): neutral, and everything else works.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  assert(c.EllesmereUI == nil)
  assert(S.Status().code == "restedxp-missing", S.Status().code)
  assert(c.RXPGuides_Themes and c.RXPGuides_Themes.TwichUI, "the theme waits in RestedXP's channel")
  local ok = S.UseTheme()
  assert(ok == false, "can't select a theme in an addon that isn't there")
  -- the look settings still work and are kept
  assert(S.Look.Set("bgOpacity", 60) and S.Text.Set("bodyFont", "Anything"))
  assert(c.TwichUIDB.ui.restedxpSkin.bgOpacity == 60 and c.TwichUIDB.ui.restedxpSkinText.bodyFont == "Anything",
    "settings are kept while the dependency is missing")
  FlushTimers()
  local snap = S.Snapshot()
  assert(snap.integrated == false and snap.hooks == 0)
  -- the report builds, says why, and doesn't throw
  local report = R.Diag.Build()
  assert(report:find("RestedXP skin", 1, true) and report:find("RestedXP isn't installed", 1, true), report)
  S.OnSwitch()   -- harmless
  c.TwichUIDB.modules.restedxpSkin = false
  S.OnSwitch()
  assert(c.RXPGuides_Themes.TwichUI == nil, "turning it off takes its theme out of the channel")
end

---------------------------------------------------------------------------
-- TwichUI first, RestedXP after (the usual order); a theme is registered once; not selected on its own.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  local theme = RXP.themes.TwichUI
  assert(theme and theme.name == "TwichUI" and theme.author == "TwichUI" and theme.applicable == true, "registered")
  assert(RXP.registered == 1, "through its own import, once")
  for _, key in ipairs({ "background", "bottomFrameBG", "bottomFrameHighlight", "mapPins", "tooltip", "textColor",
    "texturePath", "headerTexture", "font", "bgTextures", "edges" }) do
    assert(theme[key] ~= nil, "the theme carries " .. key .. ", so RestedXP fills nothing in")
  end
  assert(c.hookCount == 3, "RenderFrame, UpdateText and UpdateGuideFontSize are hooked: " .. c.hookCount)
  assert(RXP.settings.profile.activeTheme == "RXP Blue", "RestedXP's own choice is respected at login")
  assert(S.Status().code == "theme-not-selected")
  assert(RXP.frame.BottomFrame.backdropInfo == RXP.frame.backdrop.edge, "nothing drawn on")
  assert(RXP.renders == 0, "no refresh of RestedXP was asked for")

  -- the player turns the look on for RestedXP
  local used, why = S.UseTheme()
  assert(used, why)
  assert(RXP.settings.profile.activeTheme == "TwichUI" and RXP.activeTheme == theme)
  assert(c.TwichUIDB.ui.restedxpSkinState.previousTheme == "RXP Blue", "the theme it replaced is remembered")
  assert(S.Status().code == "active")
  for _, f in ipairs(Frames(RXP)) do assert(Ours(RXP, f), "every window frame has the look") end
  local look = S.Look
  local bg = RXP.frame.BottomFrame
  assert(bg.backdropInfo.bgFile == WHITE and bg.backdropInfo.edgeFile == WHITE and bg.backdropInfo.edgeSize == 1, "a flat fill, a one pixel line")
  assert(near(bg.bgColor[1], 0x21 / 255) and near(bg.bgColor[4], 0.92), "background colour and opacity")
  assert(near(bg.edgeColor[1], 0x8c / 255) and near(bg.edgeColor[4], 0.90), "border colour and opacity, separately")
  assert(near(bg.alpha, 0.65), "the list is faded by its own setting (35 %); the background opacity above does not fade the frame")
  assert(RXP.frame.GuideName.alpha == 1, "the header is not")
  assert(RXP.frame.GuideName.bg.alpha == 0 and RXP.frame.Footer.bg.alpha == 0, "the banner art steps aside")
  local thumb = RXP.frame.ScrollFrame.ScrollBar.thumb
  assert(near(thumb.vertex[1], 0x8c / 255) and near(thumb.vertex[4], 0.5), "the slim thumb is the border colour, half strength: not a bright slab")
  assert(near(theme.background[4], 0.92) and near(theme.textColor[1], 0xe9 / 255), "the theme carries the look")
  -- text: the title strings take the title colour; the steps keep RestedXP's own gate for new frames
  assert(near(RXP.frame.GuideName.text.color[1], 0xe3 / 255), "title colour")
  local el = RXP.frame.CurrentStepFrame.framePool[1].elements[1].text
  assert(near(el.color[1], 0xe9 / 255), "step text colour")

  -- hooks are installed once, however often RestedXP finishes loading or the skin is asked to attach
  c.FireEvent("ADDON_LOADED", "RXPGuides"); FlushTimers()
  c.FireEvent("PLAYER_LOGIN"); FlushTimers()
  assert(c.hookCount == 3 + 1, "the item tray is hooked once, the rest unchanged: " .. c.hookCount)
  c.FireEvent("ADDON_LOADED", "RXPGuides"); FlushTimers()
  assert(c.hookCount == 4, "still once")
  assert(RXP.registered == 1, "the theme is not registered again")
end

---------------------------------------------------------------------------
-- Settings: many changes, one update; border changes don't ask RestedXP for a refresh; combat holds it.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())
  FlushTimers()
  local theme = RXP.themes.TwichUI
  local renders = RXP.renders

  for i = 1, 30 do S.Look.Set("bgOpacity", 30 + i) end   -- a slider dragged
  assert(#TIMERS == 1, "one update waits, not thirty: " .. #TIMERS)
  FlushTimers()
  assert(RXP.renders == renders + 1, "RestedXP refreshed once for the latest value")
  assert(near(theme.background[4], 0.60), "the latest value won")
  assert(near(RXP.frame.BottomFrame.bgColor[4], 0.60), "and is what is drawn")

  renders = RXP.renders
  S.Look.Set("borderColor", "ff3060c0")
  S.Look.Set("borderSize", 2)
  FlushTimers()
  -- the border colour is also the highlight and the pins; RestedXP is asked once for that
  assert(RXP.renders == renders + 1, "one refresh for a theme colour")
  assert(near(RXP.frame.BottomFrame.edgeColor[3], 0xc0 / 255) and RXP.frame.BottomFrame.backdropInfo.edgeSize == 2)
  renders = RXP.renders
  S.Look.Set("borderOpacity", 50)
  S.Look.Set("borderSize", 3)
  FlushTimers()
  assert(RXP.renders == renders, "a border change alone is drawn without RestedXP refreshing: " .. RXP.renders - renders)
  assert(near(RXP.frame.BottomFrame.edgeColor[4], 0.5) and RXP.frame.BottomFrame.backdropInfo.edgeSize == 3)

  -- the same state again draws nothing
  local calls = {}
  for i, f in ipairs(Frames(RXP)) do calls[i] = f.backdropCalls end
  for _ = 1, 20 do RXP.frame.CurrentStepFrame.UpdateText() end
  S.Request(false); FlushTimers()
  for i, f in ipairs(Frames(RXP)) do assert(f.backdropCalls == calls[i], "frame " .. i .. " was not drawn again") end

  -- combat: nothing is drawn or asked of RestedXP until it ends
  c.COMBAT = true
  renders = RXP.renders
  S.Look.Set("bgOpacity", 10)
  FlushTimers()
  assert(RXP.renders == renders and near(RXP.frame.BottomFrame.bgColor[4], 0.60), "nothing in combat")
  assert(S.Snapshot().waitingCombat == true, "and it says it is waiting")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); FlushTimers()
  assert(near(RXP.frame.BottomFrame.bgColor[4], 0.10), "applied when combat ends")
  assert(S.Snapshot().waitingCombat == false)
  -- RestedXP's own refresh in combat is not drawn on either
  c.COMBAT = true
  RXP.RenderFrame(true)
  assert(Ours(RXP, RXP.frame.BottomFrame) == false, "RestedXP drew its own; left alone in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); FlushTimers()
  assert(Ours(RXP, RXP.frame.BottomFrame), "finished once combat ends")

  -- a turned-off skin cancels what was waiting
  renders = RXP.renders
  S.Look.Set("bgOpacity", 70)
  c.TwichUIDB.modules.restedxpSkin = false
  S.OnSwitch()
  local after = RXP.renders
  FlushTimers()
  assert(RXP.renders == after, "the waiting update did nothing once it was off")
  assert(#TIMERS == 0)
end

---------------------------------------------------------------------------
-- Recycled and later-created frames; semantic colours; trays RestedXP builds later.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c, { noItem = true })
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())
  FlushTimers()

  -- RestedXP needs more step cards: they are drawn on as soon as it lays them out
  RXP.activeSteps = {
    { elements = { { text = "a" }, { text = "b" } } },
    { elements = { { text = "c" } } },
    { elements = { { text = "d" } } },
  }
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(#RXP.frame.CurrentStepFrame.framePool == 3)
  for _, f in ipairs(Frames(RXP)) do assert(Ours(RXP, f), "new card drawn on") end
  -- a card reused for another step keeps the look
  RXP.activeSteps = { { elements = { { text = "z" } } } }
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(Ours(RXP, RXP.frame.CurrentStepFrame.framePool[1]))

  -- a colour RestedXP gave meaning to is left alone; RestedXP's own base colour is recoloured
  local warn = RXP.frame.CurrentStepFrame.framePool[1].elements[1].text
  warn:SetTextColor(1, 0.1, 0.1)
  local plain = RXP.frame.CurrentStepFrame.framePool[2].elements[1].text
  plain:SetTextColor(1, 1, 1)   -- RXP Blue's base white, from before the theme was chosen
  S.Text.Set("bodyColor", "ff80c080")
  FlushTimers()
  assert(near(warn.color[1], 1) and near(warn.color[2], 0.1), "a meaningful colour is kept")
  assert(near(plain.color[2], 0xc0 / 255), "a base colour follows the setting")

  -- the item tray appears after the skin started (RestedXP builds it later): hooked and drawn on
  RXP.activeItemFrame, RXP.enabledFrames.activeItemFrame = RXP.item, RXP.item
  RXP.item.UpdateVisuals(RXP.item)   -- RestedXP paints it as it creates it
  assert(not Ours(RXP, RXP.item), "not ours yet")
  local hooksBefore = c.hookCount
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(c.hookCount == hooksBefore + 1, "hooked when it was first seen")
  assert(Ours(RXP, RXP.item) and Ours(RXP, RXP.item.title), "tray and tab drawn on")
  RXP.item.UpdateVisuals(RXP.item)   -- RestedXP repaints the tray alone
  assert(Ours(RXP, RXP.item), "and again after its own repaint")
  RXP.settings.profile.activeItemHideBG = true   -- the player hid its background in RestedXP's options
  RXP.item.UpdateVisuals(RXP.item)
  assert(RXP.item.backdropInfo == nil, "a background RestedXP hides is not put back")
  assert(Ours(RXP, RXP.item.title))
  RXP.settings.profile.activeItemHideBG = nil
  RXP.item.UpdateVisuals(RXP.item)
  assert(Ours(RXP, RXP.item))
end

---------------------------------------------------------------------------
-- Turning it off and on: RestedXP's own look returns; nothing piles up.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = {} } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  RXP.settings.profile.activeTheme = "RXP Gold"   -- the theme the player had
  RXP.RenderFrame(true)
  local goldPlain = RXP.frame.CurrentStepFrame.framePool[1].elements[1].text
  goldPlain:SetTextColor(1, 0.9, 0.7)
  local frameCount, themeObject

  local function Cycle()
    c.TwichUIDB.modules.restedxpSkin = true
    S.OnSwitch()
    FlushTimers()
    assert(RXP.settings.profile.activeTheme == "TwichUI", "selected")
    assert(RXP.themes.TwichUI and Ours(RXP, RXP.frame.BottomFrame))
    c.TwichUIDB.modules.restedxpSkin = false
    S.OnSwitch()
    FlushTimers()
    assert(RXP.settings.profile.activeTheme == "RXP Gold", "RestedXP's theme comes back: " .. RXP.settings.profile.activeTheme)
    assert(RXP.themes.TwichUI == nil, "its entry is out of RestedXP's list")
    assert(RXP.v2.themes.TwichUI == nil)
    for _, f in ipairs(Frames(RXP)) do
      assert(f.backdropInfo == RXP.frame.backdrop.edge or f.backdropInfo == RXP.frame.backdrop.guideName,
        "RestedXP's own backdrop is back")
      assert(near(f.bgColor[1], 0.1), "and its own colour")
    end
    assert(RXP.frame.GuideName.bg.alpha == 1 and RXP.frame.Footer.bg.alpha == 1, "banner back")
    local up = RXP.frame.ScrollFrame.ScrollBar.ScrollUpButton.Normal
    assert(near(up.vertex[1], 1) and near(up.vertex[3], 1), "scroll bar untinted")
    local el = RXP.frame.CurrentStepFrame.framePool[1].elements[1].text
    assert(near(el.color[1], 1) and near(el.color[2], 0.9) and near(el.color[3], 0.7), "step text is RestedXP's base colour again")
    assert(el.font[1] == ORIGIN and el.font[3] == "", "font back")
    assert(S.Snapshot().owned == 0 and S.Snapshot().touched == false, "nothing held")
    assert(R.Diag, "diag")
    for _, f in ipairs(Frames(RXP)) do
      if f.twichBevel then assert(not f.twichBevel.top.shown and not f.twichBevel.bottom.shown, "highlight and shade hidden") end
    end
  end
  Cycle()
  frameCount = #c.made
  local ThemeAt = {}
  for i = 1, 5 do
    Cycle()
    ThemeAt[i] = RXP.registered
  end
  assert(c.hookCount == 3 or c.hookCount == 4, "hooks are never added again: " .. c.hookCount)
  assert(#c.made == frameCount, "five more cycles created nothing: " .. #c.made - frameCount)
  assert(RXP.registered == 6, "one registration per turn on: " .. RXP.registered)
  assert(c.TwichUIDB.ui.restedxpSkinState.previousTheme == "RXP Gold")
  assert(#TIMERS == 0, "no timers left behind")
  -- after being off, RestedXP's refreshes and settings changes do nothing of ours
  local calls = RXP.frame.BottomFrame.backdropCalls
  S.Look.Set("bgOpacity", 33)
  FlushTimers()
  RXP.RenderFrame(true)
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(Ours(RXP, RXP.frame.BottomFrame) == false, "off means off")
  assert(#TIMERS == 0)
end

---------------------------------------------------------------------------
-- Another RestedXP theme chosen; RestedXP profile change; the v2 window; other skins.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())

  -- the player picks another theme in RestedXP's options
  RXP.settings.profile.activeTheme = "RXP Gold"
  RXP.RenderFrame(true)
  assert(S.Status().code == "theme-not-selected")
  for _, f in ipairs(Frames(RXP)) do assert(not Ours(RXP, f), "stepped aside") end
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(not Ours(RXP, RXP.frame.CurrentStepFrame.framePool[1]), "and stays aside")
  assert(S.Snapshot().owned == 0)
  -- and settings changes don't force it back
  S.Look.Set("bgOpacity", 20); FlushTimers()
  assert(not Ours(RXP, RXP.frame.BottomFrame))
  assert(RXP.settings.profile.activeTheme == "RXP Gold", "RestedXP's choice is never taken back by a settings change")
  -- choosing it again in RestedXP brings it back
  RXP.settings.profile.activeTheme = "TwichUI"
  RXP.RenderFrame(true)
  assert(Ours(RXP, RXP.frame.BottomFrame) and S.Status().code == "active")

  -- RestedXP switches its own profile (another profile, another theme), then back
  local old = RXP.settings.profile
  RXP.settings.profile = { activeTheme = "RXP Blue", guideFontSize = 9 }
  RXP.RenderFrame(true)
  assert(not Ours(RXP, RXP.frame.BottomFrame), "the other profile's theme is respected")
  RXP.settings.profile = old
  RXP.RenderFrame(true)
  assert(Ours(RXP, RXP.frame.BottomFrame), "and ours returns with its profile")

  -- v2 guide window (beta): only the theme's colours reach it; its frames aren't drawn on
  RXP.V2 = true
  assert(S.Status().code == "v2-window")
  RXP.RenderFrame(true)
  assert(not Ours(RXP, RXP.frame.BottomFrame), "no frame is finished while v2 is on")
  S.Look.Set("bgColor", "ff302010"); FlushTimers()
  assert(RXP.converts >= 1, "a theme change asks RestedXP to convert the theme for v2")
  RXP.V2 = false
  RXP.RenderFrame(true)
  assert(Ours(RXP, RXP.frame.BottomFrame))
end

do
  -- EUI-RestedXP's engine is replacing the window: the skin waits and says so
  local c = Boot({ db = { modules = { restedxpSkin = true } }, addons = { "EUI-RestedXP" } })
  c.EUIRestedxPCache = { rxpEnabled = true, rxpLayout = "FRAMELESS" }
  c.LOADED["EUI-RestedXP"] = true
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  assert(S.Status().code == "conflict")
  local ok, why = S.UseTheme()
  assert(ok == false and why == "conflict" and RXP.settings.profile.activeTheme == "RXP Blue", "it doesn't layer over it")
  assert(RXP.renders == 0, "and doesn't repaint RestedXP")
  local snap = S.Snapshot()
  assert(snap.conflict == "eui-restedxp")
  -- its reskin switched to RestedXP's own window: no conflict
  c.EUIRestedxPCache.rxpLayout = "DEFAULT"
  assert(S.Status().code == "theme-not-selected" and S.UseTheme())
  c.EUIRestedxPCache.rxpLayout = "FRAMELESS"
  RXP.RenderFrame(true)   -- the other skin starts drawing again: ours steps aside
  assert(not Ours(RXP, RXP.frame.BottomFrame) and S.Status().code == "conflict")
  -- LiteTweaks
  c.EUIRestedxPCache = nil
  c.LOADED["EUI-RestedXP"] = nil
  c.LOADED.LiteTweaks = true
  c.LiteTweaksDB = { rxpEnabled = true }
  assert(S.Status().conflict == "litetweaks")
  c.LiteTweaksDB.rxpEnabled = false
  assert(S.Status().conflict == nil)
end

---------------------------------------------------------------------------
-- Media: a missing font falls back without losing the choice; it is used when its pack arrives.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())
  local LSM = c.LibStub("LibSharedMedia-3.0")
  assert(S.Text.Set("bodyFont", "Pack Font") and S.Text.Set("titleFont", "Pack Font"))
  FlushTimers()
  local theme = RXP.themes.TwichUI
  assert(theme.font == ORIGIN, "drawn as RestedXP's own while it is missing")
  assert(c.TwichUIDB.ui.restedxpSkinText.bodyFont == "Pack Font", "the choice is kept")
  assert(S.Snapshot().fallbackBody == "missing" and S.Snapshot().fallbackTitle == "missing")
  local listed
  for _, choice in ipairs(S.FontChoices("Pack Font")) do if choice[1] == "Pack Font" then listed = choice[2] end end
  assert(listed and listed:find("not available", 1, true), "listed and marked")
  assert(S.FontChoices("default")[1][1] == "default")

  -- the pack loads later
  LSM:Register("font", "Pack Font", [[Interface\AddOns\Pack\Pack.ttf]], LSM.LOCALE_BIT_western)
  FlushTimers()
  assert(theme.font == [[Interface\AddOns\Pack\Pack.ttf]], "used once it is there: " .. tostring(theme.font))
  assert(S.Snapshot().fallbackBody == nil)
  local fs = RXP.frame.GuideName.text
  assert(fs.font[1] == [[Interface\AddOns\Pack\Pack.ttf]], "the title is drawn with it")
  assert(fs.font[2] == 11, "its size is RestedXP's own")
  -- the list is rebuilt after a registration, not on every opening
  local first = S.FontChoices("default")
  assert(S.FontChoices("default") == first, "cached between openings")
  LSM:Register("font", "Another", [[Interface\AddOns\Pack\Another.ttf]], LSM.LOCALE_BIT_western)
  assert(S.FontChoices("default") ~= first, "invalidated by a registration")

  -- outlines
  assert(S.Text.Set("titleOutline", "thick"))
  FlushTimers()
  assert(fs.font[3] == "THICKOUTLINE", "outline applied: " .. fs.font[3])
  assert(S.Text.Set("titleOutline", "none"))
  FlushTimers()
  assert(fs.font[3] == "", "and removed")
  local sets = fs.fontSets
  for _ = 1, 10 do RXP.UpdateGuideFontSize() end   -- RestedXP resets the header; ours is put back
  assert(fs.font[1] == [[Interface\AddOns\Pack\Pack.ttf]], "put back after RestedXP's own reset")
  local after = fs.fontSets
  for _ = 1, 10 do RXP.frame.CurrentStepFrame.UpdateText() end
  assert(fs.fontSets == after, "no font is set again when nothing changed")

  -- a file the game can't draw isn't used
  LSM:Register("font", "Broken", "Bad\\File.ttf", LSM.LOCALE_BIT_western)
  assert(S.Text.Set("bodyFont", "Broken"))
  FlushTimers()
  assert(theme.font == ORIGIN and S.Snapshot().fallbackBody == "missing", "a font the game refuses falls back")
end

---------------------------------------------------------------------------
-- Validation: colours, opacity and names; bad saved values never reach the frames.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = {} } })
  local R = Start(c)
  local S = R.RestedXPSkin
  assert(not S.Look.Set("bgOpacity", 101) and not S.Look.Set("bgOpacity", -1) and not S.Look.Set("bgOpacity", "9"))
  assert(not S.Look.Set("bgColor", "red") and not S.Look.Set("borderColor", "ff12"))
  assert(not S.Text.Set("bodyColor", "blue") and not S.Text.Set("titleOutline", "huge") and not S.Text.Set("bodyFont", "a|cffff0000b"))
  assert(not S.Text.Set("tintScrollbar", "yes") and not S.Text.Set("nonsense", 1))
  assert(S.Look.Set("bgOpacity", 0) and S.Look.Get("bgOpacity") == 0, "zero is a value")
  assert(S.Text.Set("tintScrollbar", false) and S.Text.Get("tintScrollbar") == false, "false is a value")
  c.TwichUIDB.ui.restedxpSkinText = { bodyColor = "zzz", titleOutline = 7, tintScrollbar = "x", bodyFont = {} }
  assert(S.Text.Get("bodyColor") == S.Text.DEFAULTS.bodyColor and S.Text.Get("titleOutline") == "none"
    and S.Text.Get("tintScrollbar") == true and S.Text.Get("bodyFont") == "default", "bad saved values fall back")
  -- reset: only the look and text; not the switch or the remembered theme
  c.TwichUIDB.modules.restedxpSkin = true
  c.TwichUIDB.ui.restedxpSkinState = { previousTheme = "RXP Gold" }
  S.Reset()
  assert(c.TwichUIDB.ui.restedxpSkin == nil and c.TwichUIDB.ui.restedxpSkinText == nil)
  assert(c.TwichUIDB.modules.restedxpSkin == true and c.TwichUIDB.ui.restedxpSkinState.previousTheme == "RXP Gold")
  assert(S.Look.Get("bgOpacity") == 92 and S.Look.Get("bgTexture") == "solid")
end

---------------------------------------------------------------------------
-- Bounds: a long session of RestedXP refreshes and settings changes creates nothing and holds nothing.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c)
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())
  FlushTimers()
  RXP.activeSteps = { { elements = { { text = "a" } } }, { elements = { { text = "b" } } } }
  RXP.frame.CurrentStepFrame.UpdateText()
  FlushTimers()
  local made, owned = #c.made, S.Snapshot().owned
  local hooks = c.hookCount
  for i = 1, 100 do
    RXP.RenderFrame(true)
    RXP.frame.CurrentStepFrame.UpdateText()
    RXP.UpdateGuideFontSize()
    if i % 10 == 0 then S.Look.Set("bgOpacity", 20 + i % 70); S.Text.Set("bodyColor", ("ff%02x%02x%02x"):format(i, i, 200)); FlushTimers() end
  end
  assert(#c.made == made, "no frame, texture or string was created: " .. #c.made - made)
  assert(S.Snapshot().owned == owned, "the same frames are held")
  assert(c.hookCount == hooks, "no hook was added")
  assert(#TIMERS == 0, "colour and opacity changes queue no layout work: " .. #TIMERS)
  assert(S.Snapshot().knownColors <= 6, "remembered colours are bounded")
  -- RestedXP's own gate (a new theme object) redraws cards; ours finishes them again
  RXP.frame.CurrentStepFrame.framePool[1].theme = nil
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(Ours(RXP, RXP.frame.CurrentStepFrame.framePool[1]))
end

---------------------------------------------------------------------------
-- A cleaner layout: decorations, header, footer, scroll bar, sizes, spacing and padding.
-- The fake lays frames out with RestedXP's own formulas (GuideWindow.lua v4.11.22), so heights are checked
-- against what RestedXP itself would compute, not against numbers this skin made up.
---------------------------------------------------------------------------
local function Anchor(region, i) local p, _, _, x, y = region:GetPoint(i or 1); return p, x, y end

do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c, {
    rows = 6, rowLines = { 1, 3, 1, 2, 1, 1 },
    steps = { { elements = { { text = "Talk to Sergra" }, { text = "Turn in", lines = 2 } } }, { title = "", elements = { { text = "Accept" } } } },
  })
  RXP.LoadRows()
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())
  FlushTimers()
  local f = RXP.frame
  local header, footer = f.GuideName, f.Footer
  local card, card2 = f.CurrentStepFrame.framePool[1], f.CurrentStepFrame.framePool[2]
  local rows = f.ScrollChild.framePool
  local bar = f.ScrollFrame.ScrollBar

  -- decorative images: hidden, not faded, and the room they kept is the title's
  assert(header.icon.shown == false and header.classIcon.shown == false, "logo and class badge hidden by default")
  assert(header.icon.alpha == 1, "hidden, not made transparent")
  assert(Anchor(header.text, 1) == "LEFT" and select(2, Anchor(header.text, 1)) == 10, "the title starts where the logo was")
  assert(select(2, Anchor(header.text, 2)) == -10, "and is centred in the content area")
  assert(header:GetHeight() == 26, "a one-line title needs a shorter header than RestedXP's 35: " .. header:GetHeight())
  header.text.lines = 3
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(header:GetHeight() == math.ceil(11 * 3) + 14, "a long title makes the header taller rather than clipped: " .. header:GetHeight())
  header.text.lines = 1
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(header:GetHeight() == 26)

  -- RestedXP sets the textures again on its refresh: they stay hidden, with no polling
  f.GuideName.icon:SetTexture("rxp/logo"); f.GuideName.classIcon:SetTexture("rxp/MAGE")
  RXP.RenderFrame(true)
  assert(header.icon.shown == false and header.classIcon.shown == false, "still hidden after RestedXP's refresh")
  assert(#TIMERS == 0, "nothing polls")

  -- the player brings them back
  S.Text.Set("showLogo", true); FlushTimers()
  assert(header.icon.shown == true and header.classIcon.shown == false)
  assert(select(2, Anchor(header.text, 1)) == 29, "RestedXP's own room for the logo is back")
  assert(header:GetHeight() >= 42, "tall enough for the logo")
  S.Text.Set("showClassIcon", true); FlushTimers()
  assert(header.classIcon.shown == true)
  S.Text.Set("showLogo", false); FlushTimers()
  assert(header.icon.shown == false and header.classIcon.shown == true, "the badge can stand alone")
  assert(Anchor(header.classIcon, 1) == "CENTER" and select(2, Anchor(header.classIcon, 1)) == 16, "at the header's left")
  S.Text.Set("showClassIcon", false); FlushTimers()
  assert(header.classIcon.shown == false)
  assert(select(3, header.classIcon:GetPoint(1)) == "BOTTOMRIGHT", "its anchor on the logo is RestedXP's again")

  -- footer: subdued by default; the menu button gets a tooltip that carries the version
  assert(footer.text.shown ~= false and near(footer.text.alpha, 0.7 * 0.65), "subdued (and faded with the list), not removed")
  assert(footer.text.font[2] == 8, "a point smaller: " .. footer.text.font[2])
  assert(footer.cog.hooked and footer.cog.hooked.OnEnter, "the menu button has a tooltip")
  local lines = {}
  c.GameTooltip = { SetOwner = function() end, AddLine = function(_, t) lines[#lines + 1] = t end, Show = function() end,
    Hide = function() end, IsForbidden = function() return false end, GetOwner = function() end }
  footer.cog.hooked.OnEnter(footer.cog)
  local joined = table.concat(lines, "|")
  assert(joined:find("RestedXP menu", 1, true) and joined:find("v4.11.22", 1, true), "title and version: " .. joined)
  S.Text.Set("footer", "hidden"); FlushTimers()
  assert(footer.text.shown == false, "hidden on request")
  lines = {}
  footer.cog.hooked.OnEnter(footer.cog)
  assert(table.concat(lines, "|"):find("v4.11.22", 1, true), "its version is still in the tooltip")
  S.Text.Set("footer", "normal"); FlushTimers()
  assert(footer.text.shown ~= false and near(footer.text.alpha, 0.65) and footer.text.font[2] == 9, "as RestedXP draws it (faded with the list)")
  lines = {}
  footer.cog.hooked.OnEnter(footer.cog)
  assert(not table.concat(lines, "|"):find("v4.11.22", 1, true), "not repeated when it is shown")
  S.Text.Set("footer", "subtle"); FlushTimers()

  -- the scroll bar is RestedXP's own slider, slim
  assert(bar:GetWidth() == 8 and bar.thumb:GetWidth() == 5, "narrow bar and thumb")
  assert(bar.thumb:GetHeight() == 24, "the thumb keeps the template's height")
  assert(bar.thumb.file == WHITE, "a flat thumb")
  assert(bar.ScrollUpButton:GetWidth() == 12 and bar.ScrollDownButton:GetHeight() == 12, "small arrows")
  assert(bar.ScrollUpButton.Normal.file:find("UI-ScrollBar-ScrollUpButton-Up", 1, true), "the game's own arrow art, not round badges")
  assert(bar.twichTrack and bar.twichTrack.shown ~= false, "a subtle track")
  assert(select(3, Anchor(f.ScrollFrame, 1)) == -5, "the list's own frame is where RestedXP put it (its scroll range depends on it)")
  assert(select(3, Anchor(bar, 1)) == -16, "the arrows sit clear of the header")
  local made = #c.made
  RXP.RenderFrame(true)   -- RestedXP puts its own art back; ours returns
  assert(bar.thumb.file == WHITE and bar.ScrollUpButton.Normal.file:find("UI-ScrollBar", 1, true), "slim again after RestedXP's refresh")
  assert(#c.made == made, "no second bar or texture")

  -- list rows: text in from the edge and centred, numbers subordinate, a wider gap
  local row = rows[2]
  local p, x, y = Anchor(row.text, 1)
  assert(p == "TOPLEFT" and x == 6 and y == -4, "row text padding")
  assert(near(rows[1].number.text.alpha, 0.7), "the number is quieter")
  assert(near(row.number.text.alpha, 0.7), "numbers are quieter on every row")
  assert(select(2, Anchor(row.number, 1)) == -6, "and not against the edge")
  assert(select(3, Anchor(row, 1)) == -(3 + 2), "rows are apart by RestedXP's gap and the step padding")
  assert(row.text.spacing == 1, "line spacing")
  -- the row heights are RestedXP's own: its text height + 8, with the spacing counted
  assert(row:GetHeight() == math.ceil((9 * 3 + 1 * 2) + 8), "row height fits its wrapped text: " .. row:GetHeight())

  -- the current-step panel: RestedXP's formulas plus the padding, and the tab clear of the edge
  local el1, el2 = card.elements[1], card.elements[2]
  local h1 = math.ceil(11 * 1.1) + 1
  local h2 = math.ceil((11 * 2 + 1) * 1.1) + 1
  assert(el1:GetHeight() == h1 + 2 and el2:GetHeight() == h2 + 2, "padding under each line: " .. el1:GetHeight() .. ", " .. el2:GetHeight())
  assert(el1.text.spacing == 1, "line spacing on the step text")
  local tabW = math.ceil(card.number.text:GetStringWidth()) + 16
  assert(card.number:GetWidth() == tabW and card.number:GetHeight() == 17, "a roomier tab")
  assert(select(2, Anchor(card.number, 1)) == 9, "in from the card's edge")
  -- 10 above the first line, and 6 more (the padding and a little) so it clears the tab
  assert(select(3, Anchor(el1, 1)) == -(10 + 6), "the first line clears the tab: " .. select(3, Anchor(el1, 1)))
  local want1 = math.ceil(h1 + h2 + 18) + 2 * 2 + 6
  assert(card:GetHeight() == want1, "card height: " .. card:GetHeight() .. " vs " .. want1)
  local want2 = math.ceil(h1 + 18) + 2 + 6
  assert(card2:GetHeight() == want2, "second card: " .. card2:GetHeight() .. " vs " .. want2)
  assert(f.CurrentStepFrame:GetHeight() == card:GetHeight() + 5 + card2:GetHeight(), "the panel is the cards and the gaps between them: "
    .. f.CurrentStepFrame:GetHeight())

  -- idempotent: RestedXP's own refreshes, however many, never add the padding twice
  local before = { card:GetHeight(), el1:GetHeight(), f.CurrentStepFrame:GetHeight(), select(3, Anchor(el1, 1)), row:GetHeight(), select(3, Anchor(row, 1)) }
  for _ = 1, 10 do
    RXP.frame.CurrentStepFrame.UpdateText()
    RXP.RenderFrame(true)
    RXP.UpdateGuideFontSize()
  end
  FlushTimers()
  local after = { card:GetHeight(), el1:GetHeight(), f.CurrentStepFrame:GetHeight(), select(3, Anchor(el1, 1)), row:GetHeight(), select(3, Anchor(row, 1)) }
  for i = 1, #before do assert(before[i] == after[i], "layout value " .. i .. " drifted: " .. before[i] .. " -> " .. after[i]) end
  assert(#c.made == made, "and nothing was created")

  -- text sizes: RestedXP's Guide Font Size governs until the player's own are switched on
  assert(rows[1].text.font[2] == 9 and el1.text.font[2] == 11 and header.text.font[2] == 11, "RestedXP's sizes by default")
  S.Text.Set("listSize", 14); S.Text.Set("activeSize", 16); S.Text.Set("titleSize", 15); FlushTimers()
  assert(rows[1].text.font[2] == 9, "nothing changes until custom sizes are on")
  S.Text.Set("customSizes", true); FlushTimers()
  assert(rows[1].text.font[2] == 14 and rows[1].number.text.font[2] == 13, "list text and its number")
  assert(el1.text.font[2] == 16 and el1.icon.font[2] == 16, "step text and its icon")
  assert(card.number.text.font[2] == 14, "the tab")
  assert(header.text.font[2] == 15, "title")
  assert(footer.text.font[2] == 12, "footer follows the title, a little smaller: " .. footer.text.font[2])
  -- wrapping and heights follow: nothing is left at the old, fixed height
  assert(rows[2]:GetHeight() == math.ceil(14 * 3 + 1 * 2 + 8), "row heights follow the list size: " .. rows[2]:GetHeight())
  assert(el2:GetHeight() == math.ceil((16 * 2 + 1) * 1.1) + 1 + 2, "line heights follow the step size: " .. el2:GetHeight())
  assert(card.number:GetHeight() == 21, "and the tab: " .. card.number:GetHeight())
  assert(select(3, Anchor(el1, 1)) == -(10 + 6 + 2), "with the first line clear of the taller tab: " .. select(3, Anchor(el1, 1)))
  assert(header:GetHeight() == 15 + 14, "and the header: " .. header:GetHeight())
  -- recycled and later strings are given the size too
  RXP.activeSteps[3] = { elements = { { text = "a later step" } } }
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(f.CurrentStepFrame.framePool[3].elements[1].text.font[2] == 16, "a card made later has the size")
  RXP.activeSteps[3] = nil
  RXP.frame.CurrentStepFrame.UpdateText()
  RXP.LoadRows(); RXP.frame.BottomFrame.UpdateFrame()   -- RestedXP resets the list fonts on a guide load
  RXP.RenderFrame(true)
  assert(rows[1].text.font[2] == 14, "list fonts put back after a guide is loaded again")

  -- back to RestedXP's: every string, including the ones with the old size
  S.Text.Set("customSizes", false); FlushTimers()
  assert(rows[1].text.font[2] == 9 and rows[1].number.text.font[2] == 8, "list back")
  assert(el1.text.font[2] == 11 and card.number.text.font[2] == 9 and header.text.font[2] == 11, "step text, tab and title back")
  assert(el1.icon.fontObject ~= nil, "the icon string has its own font object again")
  assert(rows[2]:GetHeight() == math.ceil(9 * 3 + 1 * 2 + 8), "and the heights with them")

  -- the padding is a setting; changed, the layout is settled once from RestedXP's own numbers
  S.Text.Set("stepPadding", 6); S.Text.Set("lineSpacing", 0); FlushTimers()
  assert(el1:GetHeight() == h1 + 6 and select(3, Anchor(row, 1)) == -(3 + 6) and row.text.spacing == 0)
  S.Text.Set("stepPadding", 0); FlushTimers()
  assert(el1:GetHeight() == h1 and select(3, Anchor(row, 1)) == -3, "zero padding is RestedXP's own heights: " .. el1:GetHeight())
  assert(f.CurrentStepFrame:GetHeight() == card:GetHeight() + 5 + card2:GetHeight())
  S.Text.Set("stepPadding", 2); S.Text.Set("lineSpacing", 1); FlushTimers()

  -- dividers: header, footer and tabs are lighter than the window; full restores the same border for all
  assert(Ours(RXP, header) and not header.twichBevel.top.shown, "no highlight line on the header")
  assert(near(header.edgeColor[4], 0.9 * 0.5) and near(f.BottomFrame.edgeColor[4], 0.9), "half the strength of the window's border")
  assert(near(card.number.edgeColor[4], 0.9 * 0.5) and near(card.edgeColor[4], 0.9), "the tab too, the card not")
  S.Text.Set("dividers", "full"); FlushTimers()
  assert(near(header.edgeColor[4], 0.9) and near(footer.edgeColor[4], 0.9), "the full border")
  S.Text.Set("dividers", "subtle"); FlushTimers()

  -- the original scroll bar
  S.Text.Set("scrollbar", "original"); FlushTimers()
  assert(bar:GetWidth() == 16 and bar.thumb:GetWidth() == 18 and bar.thumb:GetHeight() == 24, "RestedXP's size")
  assert(bar.thumb.file == "rxp/Knob" and bar.ScrollUpButton.Normal.file == "rxp/ScrollUpButtonNormal", "and art")
  assert(bar.ScrollUpButton:GetWidth() == 18 and bar.ScrollUpButton:GetHeight() == 16)
  assert(bar.twichTrack.shown == false, "no track")
  assert(select(3, Anchor(bar, 1)) == -18, "RestedXP's own anchors")
  S.Text.Set("scrollbar", "slim"); FlushTimers()
  assert(bar:GetWidth() == 8, "and slim again")

  -- turning it off puts everything of RestedXP's back
  c.TwichUIDB.modules.restedxpSkin = false
  S.OnSwitch(); FlushTimers()
  assert(header.icon.shown == true and header.classIcon.shown == true, "logo and badge are back")
  assert(select(2, Anchor(header.text, 1)) == 29 and select(2, Anchor(header.text, 2)) == 0, "title anchors")
  assert(header:GetHeight() == 35, "header height")
  assert(footer.text.shown ~= false and near(footer.text.alpha, 1), "footer text")
  assert(bar:GetWidth() == 16 and bar.thumb.file == "rxp/Knob" and not bar.twichTrack.shown, "scroll bar")
  assert(select(3, Anchor(f.ScrollFrame, 1)) == -5)
  assert(Anchor(card.number, 1) == "TOPLEFT" and select(2, Anchor(card.number, 1)) == 7 and select(3, Anchor(card.number, 1)) == 5, "tab anchor")
  local p2, x2, y2 = Anchor(rows[2].text, 1)
  assert(p2 == "TOPLEFT" and x2 == 0 and y2 == -5, "row text anchor")
  assert(select(2, Anchor(rows[2].number, 1)) == 0 and near(rows[2].number.text.alpha, 1), "row number")
  assert(select(3, Anchor(rows[2], 1)) == -3, "row gap")
  assert(el1:GetHeight() == h1, "line height is RestedXP's own again: " .. el1:GetHeight())
  assert(rows[1].text.font[2] == 9 and rows[1].text.spacing == 0 and el1.text.spacing == 0, "sizes and spacing")
  assert(#TIMERS == 0)
end

-- A size, spacing or layout change in combat waits for combat to end and then lays out once.
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c, { rows = 3 })
  RXP.LoadRows()
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())
  FlushTimers()
  local f = RXP.frame
  local el = f.CurrentStepFrame.framePool[1].elements[1]
  local height = el:GetHeight()
  c.COMBAT = true
  S.Text.Set("customSizes", true); S.Text.Set("activeSize", 20); S.Text.Set("stepPadding", 8)
  FlushTimers()
  assert(el:GetHeight() == height and el.text.font[2] == 11, "nothing in combat")
  local layouts, lists = RXP.layouts, RXP.listLayouts
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); FlushTimers(); FlushTimers()   -- the update, then the settle it queued
  assert(el.text.font[2] == 20, "applied when combat ends")
  assert(el:GetHeight() == math.ceil(20 * 1.1) + 1 + 8, "with the padding once: " .. el:GetHeight())
  -- RestedXP's own refresh (what follows combat) lays everything out once; the settings that changed
  -- meanwhile are settled with one more layout of each, not one per setting
  assert(RXP.layouts == layouts + 2, "step layout: " .. RXP.layouts - layouts)
  assert(RXP.listLayouts == lists + 2, "list layout: " .. RXP.listLayouts - lists)
  assert(RXP.lastListSelf == f.BottomFrame, "the list is laid out the way RestedXP does while it is resized (no step update)")
end


-- Title hidden, a solid step tab, a gentler row hover and EllesmereUI's scroll bar.
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local ICONS = [[Interface\AddOns\EllesmereUI\media\icons\]]
  c.EllesmereUI = { ICONS_PATH = ICONS }
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c, { rows = 3 })
  RXP.LoadRows()
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())
  FlushTimers(); FlushTimers()
  local f = RXP.frame
  local header, rows, bar = f.GuideName, f.ScrollChild.framePool, f.ScrollFrame.ScrollBar
  local card = f.CurrentStepFrame.framePool[1]
  local theme = RXP.themes.TwichUI

  -- EllesmereUI: the stock arrow art is faded (the buttons keep working), its arrow icons are drawn, and the
  -- thumb is a thin half-strength strip rather than a bright slab
  for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    local button = bar[key]
    for _, piece in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do
      assert(button[piece].alpha == 0, key .. " " .. piece .. " art faded")
    end
    assert(button.twichArrow and button.twichArrow.file == ICONS .. (key == "ScrollUpButton" and "eui-arrow-up3.png" or "eui-arrow-down3.png"),
      key .. " has EllesmereUI's arrow icon")
    assert(near(button.twichArrow.alpha, 0.6), "at rest")
    button.hooked.OnEnter(button)
    assert(near(button.twichArrow.alpha, 1), "bright under the pointer")
    button.hooked.OnLeave(button)
    button:Disable()
    assert(near(button.twichArrow.alpha, 0.25), "and quiet when it cannot scroll")
    button:Enable()
    assert(near(button.twichArrow.alpha, 0.6))
  end
  assert(bar.thumb:GetWidth() == 5 and near(bar.thumb.vertex[4], 0.5), "a thin thumb at half strength")
  assert(bar.ScrollUpButton.Normal.file == "rxp/ScrollUpButtonNormal", "RestedXP's own files are left in place under the fade")
  local made = #c.made
  RXP.RenderFrame(true)
  RXP.RenderFrame(true)
  assert(#c.made == made, "no icon or strip is made twice")
  assert(near(bar.ScrollUpButton.Normal.alpha, 0), "still faded after RestedXP's refresh")
  S.Text.Set("tintScrollbar", false); FlushTimers(); FlushTimers()
  assert(near(bar.thumb.vertex[1], 1) and near(bar.thumb.vertex[4], 0.3), "untinted: EllesmereUI's own white at a third")
  S.Text.Set("tintScrollbar", true); FlushTimers(); FlushTimers()

  -- the row highlight is a gentle lift, not the border colour as a slab
  local hl, rowbg = theme.bottomFrameHighlight, theme.bottomFrameBG
  assert(near(hl[4], 1), "an opaque fill")
  local border = { 0x8c / 255, 0x6e / 255, 0x38 / 255 }
  for i = 1, 3 do
    assert(near(hl[i], rowbg[i] + (border[i] - rowbg[i]) * 0.25), "a quarter of the way from the row colour to the border colour")
  end

  -- hovering a row: RestedXP's handler runs, then a dimmed row rises less than all the way
  local row = rows[1]
  assert(row.twichEnter and row.scripts.OnEnter ~= row.twichEnter, "the row's OnEnter is wrapped around RestedXP's")
  row:SetAlpha(0.5)
  row.scripts.OnEnter(row)
  assert(near(row:GetAlpha(), 0.5 + 0.5 * 0.4), "a done row eases up: " .. row:GetAlpha())
  row.scripts.OnLeave(row)
  assert(near(row:GetAlpha(), 0.5), "and returns to where it was")
  row:SetAlpha(1)
  row.scripts.OnEnter(row)
  assert(near(row:GetAlpha(), 1), "a row at full strength is unchanged")
  row.scripts.OnLeave(row)
  -- a guide load gives the rows new handlers; they are wrapped once, around the new one
  RXP.LoadRows()
  RXP.RenderFrame(true)
  local wrapped = row.scripts.OnEnter
  RXP.RenderFrame(true)
  assert(row.scripts.OnEnter == wrapped, "wrapped once, not again on every pass")
  row:SetAlpha(0.5)
  row.scripts.OnEnter(row)
  assert(near(row:GetAlpha(), 0.7), "around RestedXP's new handler")

  -- the step tab straddles the card's edge: solid, whatever the window's opacity, and above the card
  S.Look.Set("bgOpacity", 40); FlushTimers(); FlushTimers()
  assert(near(f.BottomFrame.bgColor[4], 0.4), "the window follows the opacity")
  assert(near(card.number.bgColor[4], 1), "the tab does not")
  assert(card.number:GetFrameLevel() == card:GetFrameLevel() + 4, "and sits above the card's own drawing")

  -- the list ends where the footer begins, rather than running behind it
  local p1, _, _, _, y1 = f.BottomFrame:GetPoint(1)
  local p2, _, _, x2, y2 = f.BottomFrame:GetPoint(2)
  assert(p1 == "TOPLEFT" and y1 == -3, "the top is RestedXP's")
  assert(p2 == "BOTTOMRIGHT" and x2 == -3 and y2 == 20, "the bottom edge is the footer's top: " .. tostring(y2))
  RXP.RenderFrame(true)
  assert(select(5, f.BottomFrame:GetPoint(2)) == 20 and f.BottomFrame:GetNumPoints() == 2, "and stays there")

  -- the menu button and resize handle can be hidden; the string takes the room they kept
  local footer = f.Footer
  assert(footer.cog.shown ~= false and footer.icon.shown ~= false, "both are RestedXP's own by default")
  S.Text.Set("showCog", false); FlushTimers(); FlushTimers()
  assert(footer.cog.shown == false and footer.icon.shown ~= false, "the cog hidden")
  assert(select(4, footer.text:GetPoint(1)) == 8 and select(4, footer.text:GetPoint(2)) == -16, "its room goes to the string")
  assert(footer.shown ~= false and select(5, f.BottomFrame:GetPoint(2)) == 20, "the bar stays while one button is there")
  S.Text.Set("showResizeHandle", false); FlushTimers(); FlushTimers()
  assert(footer.icon.shown == false, "the handle hidden")
  assert(footer.shown == false and footer.text.shown == false, "with neither button the whole bar goes, string included")
  assert(select(5, f.BottomFrame:GetPoint(2)) == 0, "and the list takes its room: " .. tostring(select(5, f.BottomFrame:GetPoint(2))))
  S.Text.Set("showResizeHandle", true); FlushTimers(); FlushTimers()
  assert(footer.shown == true and footer.text.shown ~= false and select(5, f.BottomFrame:GetPoint(2)) == 20, "one button brings it back")
  S.Text.Set("showResizeHandle", false); FlushTimers(); FlushTimers()
  f.TimersShow(true); f.TimersShow(false)   -- RestedXP's timers change strength only
  RXP.RenderFrame(true)
  assert(footer.cog.shown == false and footer.icon.shown == false, "still hidden after RestedXP's timers and refresh")
  S.Text.Set("showCog", true); S.Text.Set("showResizeHandle", true); FlushTimers(); FlushTimers()
  assert(footer.cog.shown == true and footer.icon.shown == true, "back")
  assert(select(4, footer.text:GetPoint(1)) == 40 and select(4, footer.text:GetPoint(2)) == -16, "with RestedXP's own anchors")

  -- the guide list fades as one piece: background, border, scroll bar, rows, and the footer with its menu
  -- button and string. The header and the current-step panel do not.
  assert(near(f.BottomFrame.alpha, 0.65), "the list container is faded: " .. f.BottomFrame.alpha)
  assert(near(footer.alpha, 0.65), "and the footer")
  assert(near(footer.cog.alpha, 0.65), "with its menu button")
  assert(near(footer.text.alpha, 0.7 * 0.65), "and its string, as subdued as before")
  assert(header.alpha == 1 and card.alpha == 1, "the header and the current step are not")
  assert(rows[2].alpha == 1 and rows[1].alpha == 1, "the rows keep RestedXP's own strength; the container carries the fade")
  -- RestedXP's timers hide and show those three themselves: a hidden one stays hidden, and a restored one is faded
  f.TimersShow(true)
  RXP.RenderFrame(true)
  assert(footer.cog.alpha == 0 and footer.text.alpha == 0 and footer.icon.alpha == 0, "a timer's footer is left alone")
  f.TimersShow(false)
  RXP.RenderFrame(true)
  assert(near(footer.cog.alpha, 0.65) and near(footer.text.alpha, 0.7 * 0.65), "and faded again when the timer ends")
  S.Text.Set("futureFade", 0); FlushTimers(); FlushTimers()
  assert(f.BottomFrame.alpha == 1 and footer.alpha == 1 and footer.cog.alpha == 1, "0 is RestedXP's own")
  S.Text.Set("futureFade", 60); FlushTimers(); FlushTimers()
  assert(near(f.BottomFrame.alpha, 0.4) and near(footer.cog.alpha, 0.4), "the strength is the setting")
  S.Text.Set("futureFade", 35); FlushTimers(); FlushTimers()
  local made2 = #c.made
  for _ = 1, 10 do RXP.RenderFrame(true); RXP.frame.CurrentStepFrame.UpdateText() end
  assert(#c.made == made2 and near(f.BottomFrame.alpha, 0.65), "repeated passes change nothing")

  -- the title can be hidden: a slim strip is left (it is still the window's handle and menu), and with
  -- no title its background and border go too
  assert(header.text.shown ~= false and Ours(RXP, header))
  S.Text.Set("showTitle", false); FlushTimers(); FlushTimers()
  assert(header.text.shown == false, "title hidden")
  assert(header:GetHeight() == 14, "a slim strip: " .. header:GetHeight())
  assert(header.backdropInfo == nil, "no background or border either")
  assert(not header.twichBevel.top.shown and not header.twichBevel.bottom.shown, "nor highlight lines")
  RXP.RenderFrame(true)
  assert(header.backdropInfo == nil, "and RestedXP's own repaint is taken off again")
  S.Text.Set("showTitle", true); FlushTimers(); FlushTimers()
  assert(Ours(RXP, header), "back with the title")
  S.Text.Set("showTitle", false); FlushTimers(); FlushTimers()
  local lines = {}
  c.GameTooltip = { SetOwner = function() end, AddLine = function(_, t) lines[#lines + 1] = t end, Show = function() end,
    Hide = function() end, IsForbidden = function() return false end, GetOwner = function() end }
  f.Footer.cog.hooked.OnEnter(f.Footer.cog)
  assert(table.concat(lines, "|"):find("Guide title", 1, true), "the title is in the menu button's tooltip: " .. table.concat(lines, "|"))
  S.Text.Set("showLogo", true); FlushTimers(); FlushTimers()
  assert(header:GetHeight() >= 42, "a logo still has room")
  S.Text.Set("showLogo", false); S.Text.Set("showTitle", true); FlushTimers(); FlushTimers()
  assert(header.text.shown == true and header:GetHeight() == 26, "and back")
  S.Text.Set("showTitle", false); FlushTimers(); FlushTimers()
  assert(header.backdropInfo == nil)

  -- off: everything of RestedXP's is back
  c.TwichUIDB.modules.restedxpSkin = false
  S.OnSwitch(); FlushTimers()
  assert(header.text.shown == true and header:GetHeight() == 35, "title and header")
  assert(footer.cog.shown == true and footer.icon.shown == true, "the menu button and handle")
  assert(footer.shown == true and footer.text.shown == true, "the bar and its string")
  assert(select(4, footer.text:GetPoint(1)) == 40, "and the footer string's anchors")
  assert(select(5, f.BottomFrame:GetPoint(2)) == 14, "the list runs where RestedXP put it")
  assert(header.backdropInfo == RXP.frame.backdrop.guideName, "the header's own background and border are back")
  assert(f.BottomFrame.alpha == 1 and f.Footer.alpha == 1 and f.Footer.cog.alpha == 1, "the list and footer at full strength")
  assert(f.Footer.text.alpha == 1 and rows[2].number.text.alpha == 1, "and their strings")
  for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    for _, piece in ipairs({ "Normal", "Highlight", "Pushed", "Disabled" }) do assert(near(bar[key][piece].alpha, 1), "art back") end
    assert(bar[key].twichArrow.shown == false, "icon hidden")
  end
  assert(row.scripts.OnEnter ~= nil and row.twichEnter == nil, "the row's own handler is back")
  row:SetAlpha(0.5)
  row.scripts.OnEnter(row)
  assert(near(row:GetAlpha(), 1), "RestedXP's full highlight again")
  assert(card.number:GetFrameLevel() == card:GetFrameLevel() + 1, "tab level")
end


-- The waypoint arrow: shape, colour, opacity, size and its string.
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  c.EllesmereUI = { ICONS_PATH = [[Interface\AddOns\EllesmereUI\media\icons\]] }
  local R = Start(c)
  local S = R.RestedXPSkin
  local RXP = MakeRestedXP(c, { arrow = true })
  RestedXPLoads(c, RXP)
  assert(S.UseTheme())
  FlushTimers(); FlushTimers()
  local arrow = RXP.arrowFrame
  local texture, text = arrow.texture, arrow.text
  local OWN = [[Interface\AddOns\RXPGuides\Textures\DarkMode\]] .. "rxp_navigation_arrow-1"

  local BRONZE = R.PATH .. [[media\textures\arrow-bronze]]
  assert(texture.file == BRONZE, "TwichUI's bronze plate by default: " .. tostring(texture.file))
  S.Text.Set("arrowShape", "default"); FlushTimers()
  assert(texture.file == OWN, "RestedXP's own for its theme when chosen: " .. tostring(texture.file))
  S.Text.Set("arrowShape", "bronze"); FlushTimers()
  assert(texture.file == BRONZE)
  RXP.RenderFrame(true)
  assert(texture.file == BRONZE, "kept through RestedXP's refresh")
  assert(arrow:GetWidth() == 32 and text.font[2] == 9 and text.shown ~= false, "RestedXP's own size and string")
  assert(near(texture.vertex[1], 1) and near(texture.vertex[4], 1), "untinted")

  -- shape: another theme's pointer, kept through RestedXP's own refreshes
  S.Text.Set("arrowShape", "RXP Gold"); FlushTimers()
  assert(texture.file == "y/rxp_navigation_arrow-1", "another theme's pointer: " .. tostring(texture.file))
  RXP.RenderFrame(true)
  assert(texture.file == "y/rxp_navigation_arrow-1", "kept after RestedXP's refresh")
  arrow:UpdateVisuals()
  assert(texture.file == "y/rxp_navigation_arrow-1", "and after its own UpdateVisuals")
  S.Text.Set("arrowShape", "v2:RXP Blue V2"); FlushTimers()
  assert(texture.file == "v2/rxp_navigation_arrow-1", "a v2 pointer")
  S.Text.Set("arrowShape", "eui-chevron"); FlushTimers()
  assert(texture.file == [[Interface\AddOns\EllesmereUI\media\icons\eui-arrow-up3.png]], "EllesmereUI's chevron")
  S.Text.Set("arrowShape", "Gone Theme"); FlushTimers()
  assert(texture.file == OWN, "a shape that is not there is RestedXP's own, and stays chosen")
  assert(c.TwichUIDB.ui.restedxpSkinText.arrowShape == "Gone Theme")
  local ids, labels = {}, {}
  for _, choice in ipairs(S.ArrowChoices("Gone Theme")) do ids[choice[1]] = true; labels[choice[1]] = choice[2] end
  assert(ids.bronze and ids.default and ids["RXP Gold"] and ids["RXP Blue"] and ids["v2:RXP Blue V2"] and ids["eui-chevron"], "the choices")
  assert(not ids.TwichUI, "its own is the default, not a second entry")
  assert(labels["Gone Theme"]:find("not available", 1, true), "a missing one stays listed, marked")
  S.Text.Set("arrowShape", "bronze"); FlushTimers()
  assert(texture.file == BRONZE)

  -- colour and opacity (the picture's, so RestedXP's own showing and hiding of the arrow is untouched)
  S.Text.Set("arrowColor", "ff80c0ff"); S.Text.Set("arrowOpacity", 60); FlushTimers()
  assert(near(texture.vertex[1], 0x80 / 255) and near(texture.vertex[2], 0xc0 / 255) and near(texture.vertex[4], 0.6), "tint and opacity")
  assert(arrow.alpha == 1, "the arrow frame's own strength is RestedXP's")

  -- size: a percentage of RestedXP's own, following its Arrow Scale option
  S.Text.Set("arrowSize", 150); FlushTimers()
  assert(arrow:GetWidth() == 48 and arrow:GetHeight() == 48, "150 % of 32")
  arrow:SetSize(64, 64)   -- RestedXP's Arrow Scale option, 2
  assert(arrow:GetWidth() == 96, "scaled again when RestedXP sets it: " .. arrow:GetWidth())
  arrow:SetSize(32, 32)
  assert(arrow:GetWidth() == 48, "and not accumulated")
  -- its string: size as a percentage, and shown or not
  S.Text.Set("arrowTextSize", 200); FlushTimers()
  assert(text.font[2] == 18, "200 % of 9: " .. text.font[2])
  text:SetFont(ORIGIN, 12, "OUTLINE")   -- RestedXP's Arrow Text Size option
  assert(text.font[2] == 24 and text.font[3] == "OUTLINE", "scaled when RestedXP sets it, outline kept")
  text:SetFont(ORIGIN, 9, "OUTLINE")
  assert(text.font[2] == 18)
  S.Text.Set("arrowTextShown", false); FlushTimers()
  assert(text.shown == false, "the string hidden")

  -- nothing is made or set again by repeated passes
  local made, sets = #c.made, texture.textureSets or 0
  for _ = 1, 10 do RXP.RenderFrame(true); RXP.frame.CurrentStepFrame.UpdateText() end
  assert(#c.made == made and arrow:GetWidth() == 48 and text.font[2] == 18, "stable")

  -- combat: held until it ends
  c.COMBAT = true
  S.Text.Set("arrowSize", 100); FlushTimers()
  assert(arrow:GetWidth() == 48, "nothing in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); FlushTimers(); FlushTimers()
  assert(arrow:GetWidth() == 32, "applied after: " .. arrow:GetWidth())

  -- off: RestedXP's own arrow
  S.Text.Set("arrowShape", "RXP Gold"); S.Text.Set("arrowSize", 200); S.Text.Set("arrowTextSize", 150); FlushTimers()
  c.TwichUIDB.modules.restedxpSkin = false
  S.OnSwitch(); FlushTimers()
  assert(texture.file == "x/rxp_navigation_arrow-1" or texture.file == RXP.activeTheme.texturePath .. "rxp_navigation_arrow-1", "its theme's pointer: " .. tostring(texture.file))
  assert(near(texture.vertex[1], 1) and near(texture.vertex[4], 1), "untinted")
  assert(arrow:GetWidth() == 32 and text.font[2] == 9 and text.shown ~= false, "its size and string")
  arrow:SetSize(64, 64)
  text:SetFont(ORIGIN, 12, "OUTLINE")
  assert(arrow:GetWidth() == 64 and text.font[2] == 12, "and its own options are no longer scaled")
end

-- Validation of the new settings.
do
  local c = Boot({ db = { modules = {} } })
  local R = Start(c)
  local S = R.RestedXPSkin
  assert(not S.Text.Set("listSize", 7) and not S.Text.Set("listSize", 21) and not S.Text.Set("listSize", 10.5) and not S.Text.Set("listSize", "12"))
  assert(not S.Text.Set("activeSize", 23) and not S.Text.Set("titleSize", 25) and not S.Text.Set("stepPadding", 11) and not S.Text.Set("lineSpacing", -1))
  assert(S.Text.Set("listSize", 8) and S.Text.Set("listSize", 20) and S.Text.Set("stepPadding", 0) and S.Text.Get("stepPadding") == 0, "limits are inclusive; 0 is a value")
  assert(not S.Text.Set("footer", "gone") and not S.Text.Set("dividers", "none") and not S.Text.Set("scrollbar", "huge") and not S.Text.Set("showLogo", "yes"))
  assert(S.Text.DEFAULTS.showLogo == false and S.Text.DEFAULTS.showClassIcon == false, "decoration hidden by default")
  assert(S.Text.DEFAULTS.customSizes == false, "RestedXP's sizes by default")
  -- bad saved values fall back, other saved values are kept (nothing is forced on an existing player)
  c.TwichUIDB.ui.restedxpSkinText = { bodyFont = "Saved Font", titleColor = "ff112233", listSize = 99, footer = 5 }
  assert(S.Text.Get("bodyFont") == "Saved Font" and S.Text.Get("titleColor") == "ff112233", "saved choices kept")
  assert(S.Text.Get("listSize") == S.Text.DEFAULTS.listSize and S.Text.Get("footer") == "subtle", "bad ones fall back")
  assert(S.Text.Get("showLogo") == false and S.Text.Get("scrollbar") == "slim", "new settings take their defaults")
  assert(c.TwichUIDB.ui.restedxpSkinText.bodyFont == "Saved Font", "and nothing was written to the saved table")
end

---------------------------------------------------------------------------
-- Troubleshooting report: states, no guide text, no names.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { restedxpSkin = true } } })
  local R = Start(c)
  local RXP = MakeRestedXP(c, { guideText = "SECRETGUIDE Elwynn Forest" })
  RXP.activeSteps = { { elements = { { text = "SECRETSTEP kill Hogger" } } } }
  RestedXPLoads(c, RXP)
  assert(R.RestedXPSkin.UseTheme())
  FlushTimers()
  local report = R.Diag.Build()
  assert(report:find("RestedXP skin", 1, true), "its section is there")
  assert(report:find("state: active", 1, true), "and says it is active")
  assert(report:find("hooks", 1, true) and report:find("frames drawn on", 1, true))
  assert(not report:find("SECRETGUIDE", 1, true) and not report:find("SECRETSTEP", 1, true), "no guide text")
  assert(not report:find("Hogger", 1, true) and not report:find("Rich", 1, true), "no names")
  -- a provider that fails does not break the report
  R.RestedXPSkin.Snapshot = function() error("boom") end
  local broken = R.Diag.Build()
  assert(broken:find("RestedXP skin", 1, true) and broken:find("Start-up", 1, true), "the rest of the report is intact")
end

print("RESTEDXP SKIN TESTS PASSED")
