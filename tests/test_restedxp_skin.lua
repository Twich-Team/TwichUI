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
    CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
    CreateFontString = function(s) local t = Fake("font"); t.parent = s; t.font = { ORIGIN, 12, "" }; t.color = { 1, 1, 1 }; return t end,
    SetText = function(s, v) s.text = v end,
    ClearAllPoints = function(s) s.points = {} end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    SetHeight = function(s, v) s.height = v end,
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
    GetFrameLevel = function() return 1 end,
  }
  c.Fake, c.made = Fake, made
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind); f.name, f.parent = name, parent; return f end
  c.UIParent = Fake("UIParent")
  c.STANDARD_TEXT_FONT = ORIGIN
  c.GameFontNormal = { GetFont = function() return ORIGIN, 12, "" end }
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
  frame.ScrollFrame = { ScrollBar = bar }
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
  function csf.UpdateText()
    for i, step in ipairs(RXP.activeSteps) do
      local sf = csf.framePool[i]
      if not sf then
        sf = Fake("Frame")
        sf.number = Part()
        sf.elements = {}
        csf.framePool[i] = sf
      end
      if sf.theme ~= RXP.activeTheme then   -- RestedXP's own gate (GuideWindow.lua: stepframe.theme)
        sf.theme = RXP.activeTheme
        Paint(sf, edge)
        Paint(sf.number, edge)
      end
      for j, element in ipairs(step.elements) do
        local ef = sf.elements[j]
        if not ef then
          ef = { text = Fake("Frame"):CreateFontString() }
          ef.text:SetFont(RXP.font, RXP.settings.profile.guideFontSize + 2, "")
          ef.text:SetTextColor(unpack(RXP.activeTheme.textColor))
          sf.elements[j] = ef
        end
        ef.text:SetText(element.text)
      end
    end
  end
  function RXP.RenderFrame(themeUpdate, isLoading)   -- GuideWindow.lua addon.RenderFrame
    local name = RXP.settings.profile.activeTheme
    RXP.activeTheme = RXP.themes[name] or RXP.themes["RXP Blue"]
    RXP.colors, RXP.font = RXP.activeTheme, RXP.activeTheme.font
    RXP.renders = RXP.renders + 1
    for _, f in pairs(RXP.enabledFrames) do if f.UpdateVisuals then f:UpdateVisuals(true) end end
    if RXP.currentGuide and not isLoading then csf.UpdateText() end
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
  assert(bg.alpha == 1, "no frame is faded: text and buttons stay solid")
  assert(RXP.frame.GuideName.bg.alpha == 0 and RXP.frame.Footer.bg.alpha == 0, "the banner art steps aside")
  local up = RXP.frame.ScrollFrame.ScrollBar.ScrollUpButton.Normal
  assert(near(up.vertex[1], 0x8c / 255), "the scroll bar takes the border colour")
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
  assert(c.hookCount == 3 + 0 or c.hookCount == 4, "hooks are never added again: " .. c.hookCount)
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
  assert(#TIMERS == 0)
  assert(S.Snapshot().knownColors <= 6, "remembered colours are bounded")
  -- RestedXP's own gate (a new theme object) redraws cards; ours finishes them again
  RXP.frame.CurrentStepFrame.framePool[1].theme = nil
  RXP.frame.CurrentStepFrame.UpdateText()
  assert(Ours(RXP, RXP.frame.CurrentStepFrame.framePool[1]))
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
