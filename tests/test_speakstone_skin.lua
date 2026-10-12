-- SpeakStone skin (modules/SpeakStoneSkin.lua): off by default and silent when off; silent without SpeakStone;
-- found through CreateFont and the frame's own SetScale/SetHeight, once, however often it is switched; drawn
-- before SpeakStone lays any text out; the height is the skin's rows, not SpeakStone's base; settings changes are
-- coalesced and a colour change does not make SpeakStone lay its text out again; turning it off puts every
-- recorded piece back; an unexpected frame or an error leaves SpeakStone's frame as it was; nothing allocated by
-- a long session; the troubleshooting section carries no text.
-- SpeakStone is simulated from the source of SpeakStone Forever - Main 3.1.6 (SpeechFrame.lua): the same names
-- and the same order of calls in Build and Fill, not the game.
dofile(TESTS .. "harness.lua")

local ORIGIN = [[Fonts\FRIZQT__.TTF]]
local MASK_FILE = [[Interface\CharacterFrame\TempPortraitAlphaMask]]
local WHITE = [[Interface\Buttons\WHITE8x8]]

---------------------------------------------------------------------------
-- A small fake of the game's frames: enough of frames, regions, fonts, buttons and bars.
---------------------------------------------------------------------------
local function Boot(opts)
  opts = opts or {}
  local addons = { "!!!TwichUI" }
  if opts.speakstone ~= false then addons[#addons + 1] = "SpeakStone_Forever_Main" end
  local c = MakeClient("Rich", addons)
  local made = {}
  local Methods
  local function Fake(kind, parent)
    local o = {
      kind = kind, parent = parent, shown = true, points = {}, alpha = 1, scripts = {}, regions = {},
      vertex = { 1, 1, 1, 1 }, masks = {}, level = (parent and parent.level or 0) + 1,
    }
    made[#made + 1] = o
    return setmetatable(o, { __index = function(_, k)
      if Methods[k] then return Methods[k] end
      if type(k) == "string" and k:find("^%u") then return function() end end
    end })
  end
  local function Region(self, kind, layer)
    local t = Fake(kind, self)
    t.layer = layer or "ARTWORK"
    table.insert(self.regions, t)
    return t
  end
  Methods = {
    GetObjectType = function(s) return s.kind end,
    Show = function(s) s.shown = true end,
    Hide = function(s) s.shown = false end,
    IsShown = function(s) return s.shown end,
    SetShown = function(s, v) s.shown = v and true or false end,
    SetScript = function(s, n, fn) s.scripts[n] = fn end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooked = s.hooked or {}; s.hooked[n] = fn end,
    SetFrameLevel = function(s, v) s.level = v end,
    GetFrameLevel = function(s) return s.level end,
    GetParent = function(s) return s.parent end,
    CreateTexture = function(s, _, layer) return Region(s, "Texture", layer) end,
    CreateMaskTexture = function(s) return Region(s, "MaskTexture", "ARTWORK") end,
    CreateFontString = function(s, _, layer, template)
      local fs = Region(s, "FontString", layer)
      fs.font = { ORIGIN, 12, "" }
      fs.color = { 1, 1, 1, 1 }
      fs.spacing = 0
      if template then fs:SetFontObject(c[template]) end
      return fs
    end,
    GetRegions = function(s) return unpack(s.regions) end,
    GetDrawLayer = function(s) return s.layer, 0 end,
    ClearAllPoints = function(s) s.points = {} end,
    -- (point, relativeTo, [relativePoint,] [x, y]); a point already set is replaced, as in the game
    SetPoint = function(s, point, a, b, d, e)
      local rel, rp, x, y
      if type(a) == "number" then rel, rp, x, y = s.parent, point, a, b
      elseif a == nil or type(a) == "table" then
        if type(b) == "string" then rel, rp, x, y = a, b, d, e else rel, rp, x, y = a, point, b, d end
      elseif type(a) == "string" then rel, rp, x, y = s.parent, a, b, d end
      local entry = { point, rel or s.parent, rp or point, x or 0, y or 0 }
      for i, p in ipairs(s.points) do if p[1] == point then s.points[i] = entry; return end end
      s.points[#s.points + 1] = entry
    end,
    SetAllPoints = function(s, rel)
      s.points = { { "TOPLEFT", rel or s.parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel or s.parent, "BOTTOMRIGHT", 0, 0 } }
    end,
    GetNumPoints = function(s) return #s.points end,
    GetPoint = function(s, i) local p = s.points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end,
    SetSize = function(s, w, h) s.width, s.height = w, h end,
    SetWidth = function(s, v) s.width = v end,
    SetHeight = function(s, v) s.height = v end,
    GetWidth = function(s) return s.width or 0 end,
    GetHeight = function(s) return s.height or 0 end,
    SetAlpha = function(s, a) s.alpha = a end,
    EnableMouse = function(s, v) s.mouse = v and true or false end,
    IsMouseEnabled = function(s) return s.mouse ~= false end,
    Click = function(s) if s.scripts.OnClick then s.scripts.OnClick(s) end end,
    GetAlpha = function(s) return s.alpha end,
    SetScale = function(s, v) s.scale = v end,
    GetScale = function(s) return s.scale or 1 end,
    GetEffectiveScale = function() return 1 end,
    -- backdrops
    SetBackdrop = function(s, info) s.backdropInfo = info end,
    ClearBackdrop = function(s) s.backdropInfo = nil end,
    SetBackdropColor = function(s, r, g, b, a) s.bgColor = { r, g, b, a } end,
    SetBackdropBorderColor = function(s, r, g, b, a) s.edgeColor = { r, g, b, a } end,
    -- textures
    SetColorTexture = function(s, r, g, b, a) s.colorTex = { r, g, b, a }; s.file = nil end,
    SetTexture = function(s, f) s.file = f; s.colorTex = nil end,
    GetTexture = function(s) return s.file end,
    SetVertexColor = function(s, r, g, b, a) s.vertex = { r, g, b, a or 1 } end,
    GetVertexColor = function(s) return s.vertex[1], s.vertex[2], s.vertex[3], s.vertex[4] end,
    SetDesaturated = function(s, v) s.desaturated = v and true or false end,
    IsDesaturated = function(s) return s.desaturated == true end,
    AddMaskTexture = function(s, m) s.masks[m] = true end,
    RemoveMaskTexture = function(s, m) s.masks[m] = nil end,
    -- fonts (strings and Font objects alike)
    SetFont = function(s, path, size, flags)
      if s.throwOn and path:find(s.throwOn, 1, true) then error("boom: " .. path) end
      if path == "Bad\\File.ttf" then return false end
      s.font = { path, size, flags or "" }
      s.fontSets = (s.fontSets or 0) + 1
      return true
    end,
    GetFont = function(s) return s.font[1], s.font[2], s.font[3] end,
    SetFontObject = function(s, o)
      s.fontObject = o
      s.font = { o.font[1], o.font[2], o.font[3] }
      s.color = { o.color[1], o.color[2], o.color[3], o.color[4] }
      s.spacing = o.spacing
    end,
    GetFontObject = function(s) return s.fontObject end,
    CopyFontObject = function(s, o)
      s.font = { o.font[1], o.font[2], o.font[3] }
      s.color = { o.color[1], o.color[2], o.color[3], o.color[4] }
      s.spacing = o.spacing
    end,
    SetTextColor = function(s, r, g, b, a) s.color = { r, g, b, a or 1 } end,
    GetTextColor = function(s) return s.color[1], s.color[2], s.color[3], s.color[4] end,
    SetSpacing = function(s, v) s.spacing = v end,
    GetSpacing = function(s) return s.spacing or 0 end,
    SetText = function(s, v) s.text = v end,
    GetText = function(s) return s.text end,
    GetStringHeight = function(s)
      local size, lines = s.font and s.font[2] or 12, s.lines or 1
      return size * lines + (s.spacing or 0) * (lines - 1)
    end,
    GetStringWidth = function(s) return #(s.text or "") * (s.font and s.font[2] or 12) * 0.5 end,
    -- buttons
    SetNormalTexture = function(s, f) s.normalTex = s.normalTex or Fake("Texture", s); s.normalTex.file = f end,
    GetNormalTexture = function(s) return s.normalTex end,
    SetPushedTexture = function(s, f) s.pushedTex = s.pushedTex or Fake("Texture", s); s.pushedTex.file = f end,
    GetPushedTexture = function(s) return s.pushedTex end,
    SetDisabledTexture = function(s, f) s.disabledTex = s.disabledTex or Fake("Texture", s); s.disabledTex.file = f end,
    GetDisabledTexture = function(s) return s.disabledTex end,
    GetHighlightTexture = function(s) return s.highlightTex end,
    SetNormalFontObject = function(s, o) s.normalFont = o end,
    GetNormalFontObject = function(s) return s.normalFont end,
    SetHighlightFontObject = function(s, o) s.highlightFont = o end,
    GetHighlightFontObject = function(s) return s.highlightFont end,
    SetDisabledFontObject = function(s, o) s.disabledFont = o end,
    GetDisabledFontObject = function(s) return s.disabledFont end,
    -- status bars and scroll frames
    SetStatusBarColor = function(s, r, g, b, a) s.barColor = { r, g, b, a }; end,
    GetStatusBarColor = function(s) return s.barColor[1], s.barColor[2], s.barColor[3], s.barColor[4] end,
    GetStatusBarTexture = function(s) return s.fill end,
    SetScrollChild = function(s, ch) s.child = ch end,
    SetVerticalScroll = function(s, v) s.vscroll = v end,
    GetVerticalScroll = function(s) return s.vscroll or 0 end,
  }
  c.made = made
  c.UIParent = Fake("Frame")
  c.STANDARD_TEXT_FONT = ORIGIN
  -- the game's Font objects SpeakStone uses
  local function FontObject(size, r, g, b)
    local o = Fake("Font")
    o.font, o.color, o.spacing = { ORIGIN, size, "" }, { r or 1, g or 1, b or 1, 1 }, 0
    return o
  end
  c.GameFontNormalLarge = FontObject(16, 1, 0.82, 0)
  c.GameFontNormalSmall = FontObject(10, 1, 0.82, 0)
  c.GameFontHighlightSmall = FontObject(10)
  c.GameFontDisableSmall = FontObject(10, 0.5, 0.5, 0.5)
  c.GameFontHighlight = FontObject(12)
  c.CreateFont = function(name)
    local o = FontObject(12)
    c[name] = o
    c.fontsMade = (c.fontsMade or 0) + 1
    return o
  end
  c.CreateFrame = function(kind, name, parent, template)
    local f = Fake(kind, parent)
    if name then c[name] = f end
    if template == "UIPanelButtonTemplate" then
      f.Left, f.Middle, f.Right = Region(f, "Texture", "BACKGROUND"), Region(f, "Texture", "BACKGROUND"), Region(f, "Texture", "BACKGROUND")
      f.highlightTex = Fake("Texture", f)
      f.normalFont, f.highlightFont, f.disabledFont = c.GameFontNormal or c.GameFontNormalSmall, c.GameFontHighlight, c.GameFontDisableSmall
    elseif template == "UIPanelCloseButton" then
      f.normalTex, f.pushedTex, f.disabledTex, f.highlightTex =
        Fake("Texture", f), Fake("Texture", f), Fake("Texture", f), Fake("Texture", f)
      f.normalTex.file, f.pushedTex.file, f.disabledTex.file, f.highlightTex.file =
        "atlas:RedButton-Exit", "atlas:RedButton-exit-pressed", "atlas:RedButton-Exit-Disabled", "atlas:RedButton-Highlight"
    end
    return f
  end
  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
  c.hookCount = 0
  c.hooksecurefunc = function(a, b, d)
    local tbl, name, fn = a, b, d
    if type(a) == "string" then tbl, name, fn = c, a, b end   -- hooksecurefunc("GlobalName", fn)
    local orig = assert(tbl[name], "hooking something that is not there: " .. tostring(name))
    c.hookCount = c.hookCount + 1
    tbl[name] = function(...)
      local r = { orig(...) }
      fn(...)
      return unpack(r)
    end
  end
  c.errors = {}
  c.geterrorhandler = function() return function(e) c.errors[#c.errors + 1] = tostring(e) end end
  c.TwichUIDB = opts.db or { modules = {} }
  for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpeakStoneSkin.lua",
      "diag/Diagnostics.lua", "diag/SpeakStoneSkin.lua" }) do
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
-- SpeakStone, from SpeechFrame.lua (Build, SetPortrait's texture, Fill, Refresh): the same calls in the same order.
---------------------------------------------------------------------------
local function MakeSpeakStone(c, opts)
  opts = opts or {}
  local WIDTH, HEIGHT, PORTRAIT, TEXT_LINES = 660, 130, 72, 4
  local SS = { builds = 0, dismissed = 0, menus = 0 }
  local frame
  local function MakeButton(parent, label, width)
    local button = c.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(label)
    button:SetNormalFontObject(c.GameFontNormalSmall)
    button:SetHighlightFontObject(c.GameFontHighlightSmall)
    button:SetDisabledFontObject(c.GameFontDisableSmall)
    return button
  end
  function SS.Build()
    if frame then return frame end
    SS.builds = SS.builds + 1
    frame = c.CreateFrame("Frame", "SpeakStoneSpeechFrame", c.UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    SS.mouseUp = function(self, button)   -- SpeakStone: a right-click opens its menu
      if button == "RightButton" then SS.menus = SS.menus + 1 end
    end
    frame:SetScript("OnMouseUp", SS.mouseUp)
    local band = frame:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints()
    band:SetColorTexture(1, 1, 1, 1)
    local lineTop = frame:CreateTexture(nil, "BORDER")
    local lineBottom = frame:CreateTexture(nil, "BORDER")
    -- a decoration on a layer nobody would guess is still SpeakStone's, so it goes too
    local glow = frame:CreateTexture(nil, "OVERLAY")
    frame.bandPieces = { band, lineTop, lineBottom, glow }
    frame.portrait = frame:CreateTexture(nil, "ARTWORK")
    frame.portrait:SetSize(PORTRAIT, PORTRAIT)
    frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(HEIGHT - PORTRAIT) / 2)
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(MASK_FILE)
    mask:SetAllPoints(frame.portrait)
    frame.portrait:AddMaskTexture(mask)
    frame.portraitMask = mask
    if opts.missing ~= "close" then
      frame.close = c.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
      frame.close:SetSize(22, 22)
      frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
      frame.close:SetScript("OnClick", function() SS.dismissed = SS.dismissed + 1 end)   -- Dismiss
    end
    local controls = c.CreateFrame("Frame", nil, frame)
    controls:SetSize(1, 20)
    controls:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -8)
    frame.controls = controls
    controls.gear = c.CreateFrame("Button", nil, controls)
    controls.gear:SetSize(18, 18)
    controls.gear:SetPoint("RIGHT", controls, "RIGHT", 0, 0)
    controls.gear:SetNormalTexture([[Interface\WorldMap\Gear_64Grey]])
    controls.gear.highlightTex = controls.gear:CreateTexture(nil, "HIGHLIGHT")
    controls.gear.highlightTex.file = [[Interface\WorldMap\Gear_64Grey]]
    controls.time = controls:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    controls.time:SetPoint("RIGHT", controls.gear, "LEFT", -8, 0)
    controls.time:SetTextColor(0.75, 0.72, 0.65)
    controls.replay = MakeButton(controls, "Replay", 56)
    controls.replay:SetPoint("RIGHT", controls.time, "LEFT", -8, 0)
    controls.stop = MakeButton(controls, "Stop", 46)
    controls.stop:SetPoint("RIGHT", controls.replay, "LEFT", -4, 0)
    controls.pause = MakeButton(controls, "Pause", 60)
    controls.pause:SetPoint("RIGHT", controls.stop, "LEFT", -4, 0)
    controls.next = MakeButton(controls, "Next", 50)
    controls.next:SetPoint("RIGHT", controls.pause, "LEFT", -4, 0)
    controls.next:Hide()
    frame.name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.name:SetPoint("LEFT", frame.portrait, "RIGHT", 14, 0)
    frame.name:SetPoint("TOP", frame, "TOP", 0, -32)
    frame.name:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    local textFont = c.CreateFont("SpeakStoneSpeechTextFont")
    textFont:CopyFontObject(c.GameFontHighlight)
    textFont:SetFont((c.GameFontHighlight:GetFont()), 13, "")
    textFont:SetSpacing(2)
    local lineHeight = 13 + 2
    local scroll = c.CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    scroll:SetHeight(lineHeight * TEXT_LINES)
    frame.lineHeight = lineHeight
    local child = c.CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    frame.scroll, frame.scrollChild = scroll, child
    frame.text = child:CreateFontString(nil, "ARTWORK")
    frame.text:SetFontObject(textFont)
    frame.text:SetPoint("TOPLEFT")
    if opts.missing ~= "progress" then
      frame.progress = c.CreateFrame("StatusBar", nil, frame)
      frame.progress.fill = frame.progress:CreateTexture(nil, "ARTWORK")
      frame.progress:SetStatusBarColor(0.94, 0.76, 0.35, 0.9)
      frame.progress:SetHeight(2)
      frame.progress:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -4)
      frame.progress:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
      frame.track = frame.progress:CreateTexture(nil, "BACKGROUND")
      frame.track:SetAllPoints()
      frame.track:SetColorTexture(1, 1, 1, 0.1)
    end
    -- ApplyPosition: the last thing Build does
    frame:SetScale(1)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOM", c.UIParent, "BOTTOM", 0, 190)
    return frame
  end
  -- Fill, as SpeechFrame.lua does it (sd: { name, text, lines, fit })
  function SS.Fill(sd)
    frame.name:SetText(sd.name or "Speaker")
    local width = frame.scroll:GetWidth()
    if not width or width <= 0 then width = WIDTH - PORTRAIT - 12 - 14 - 16 end
    frame.text:SetWidth(width)
    frame.text:SetText(sd.text or "text")
    frame.text.lines = sd.lines or 1
    local textHeight = math.max(1, frame.text:GetStringHeight())
    frame.scrollChild:SetSize(width, textHeight)
    local lines = TEXT_LINES
    if sd.fit then lines = math.max(TEXT_LINES, math.min(24, math.ceil(textHeight / frame.lineHeight))) end
    local scrollHeight = frame.lineHeight * lines
    frame.scroll:SetHeight(scrollHeight)
    frame:SetHeight(HEIGHT + scrollHeight - frame.lineHeight * TEXT_LINES)
    frame.scroll:SetVerticalScroll(0)
    frame.filledFor = sd
  end
  function SS.Refresh(sd)
    if frame.filledFor ~= sd then SS.Fill(sd) end
  end
  function SS.Frame() return frame end
  return SS
end

local function Anchor(region, i) local p, _, rp, x, y = region:GetPoint(i or 1); return p, x, y, rp end
local function near(a, b) return math.abs(a - b) < 0.0001 end
local function Skinned(db) return { modules = { speakstoneSkin = true }, ui = db and db.ui } end

---------------------------------------------------------------------------
-- Off by default, and silent: no hook, nothing drawn, nothing changed.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = {} } })
  local R = Start(c)
  local S = R.SpeakStoneSkin
  assert(R:Enabled("speakstoneSkin") == false, "opt-in")
  assert(c.hookCount == 0, "no hook while it is off: " .. c.hookCount)
  local SS = MakeSpeakStone(c)
  local f = SS.Build()
  SS.Fill({ name = "Hogger", text = "Grr" })
  assert(S.Status().code == "off")
  assert(f.lineHeight == 15 and f:GetHeight() == 130, "SpeakStone's own numbers")
  assert(f.bandPieces[1].alpha == 1 and f.name.fontObject == c.GameFontNormalLarge)
  assert(f.name:GetNumPoints() == 3, "its own three anchors")
  assert(#c.errors == 0)
end

---------------------------------------------------------------------------
-- SpeakStone not installed, or turned off in the AddOns list: nothing hooked, a neutral status.
---------------------------------------------------------------------------
do
  local c = Boot({ db = Skinned(), speakstone = false })
  local R = Start(c)
  assert(c.hookCount == 0, "nothing to hook")
  assert(R.SpeakStoneSkin.Status().code == "speakstone-missing")
  assert(#c.errors == 0)
  OFF = { SpeakStone_Forever_Main = true }
  local d = Boot({ db = Skinned() })
  local Rd = Start(d)
  assert(d.hookCount == 0 and Rd.SpeakStoneSkin.Status().code == "speakstone-disabled")
  OFF = nil
  assert(#d.errors == 0)
end

---------------------------------------------------------------------------
-- On: found when SpeakStone builds its frame, drawn before the first Fill, hooked once.
---------------------------------------------------------------------------
local function Ready(opts)
  local c = Boot({ db = opts and opts.db or Skinned() })
  local R = Start(c)
  local SS = MakeSpeakStone(c, opts and opts.ss)
  return c, R, R.SpeakStoneSkin, SS
end

do
  local c, R, S, SS = Ready()
  assert(c.hookCount == 1, "one hook before SpeakStone has built anything: " .. c.hookCount)
  assert(S.Status().code == "waiting", "enabled, the frame not built yet")
  c.CreateFont("SomebodyElsesFont")
  assert(c.hookCount == 1 and S.Snapshot().frameHooked == false, "another font is nothing")
  local f = SS.Build()
  assert(c.hookCount == 3, "CreateFont, then the frame's SetScale and SetHeight: " .. c.hookCount)
  assert(S.Status().code == "active", "drawn at the end of Build, before any text: " .. S.Status().code)
  assert(S.Snapshot().draws == 1)
  -- native decoration is faded, and ours is behind everything
  for _, piece in ipairs(f.bandPieces) do
    assert(piece.alpha == 0 and piece.shown == false, "SpeakStone's band and hairlines give way, whatever their layer")
  end
  assert(f.portrait.alpha == 1 and f.portrait.shown, "the portrait is not decoration")
  assert(f.track.alpha == 0, "and its track")
  local bg
  for _, o in ipairs(c.made) do if o.kind == "Frame" and o.parent == f and o.backdropInfo then bg = o end end
  assert(bg and bg.level == f.level - 1 and bg.points[1][2] == f, "one child frame under the frame's own level")
  assert(bg.bgColor and near(bg.bgColor[4], 0.9) and bg.edgeColor, "the look is drawn on it")
  -- layout, at the defaults (SpeakStone's own numbers at a padding of 12)
  local p, x, y = Anchor(f.portrait)
  assert(p == "TOPLEFT" and x == 14 and y == -14 and f.portrait:GetWidth() == 72, "portrait at the padding, inside its ring")
  assert(f.portrait.masks[f.portraitMask] and f.portraitMask.file == MASK_FILE, "round, as SpeakStone draws it")
  p, x, y = Anchor(f.name, 1)
  assert(p == "TOPLEFT" and x == 12 + 4 + 72 + 14 and y == -32, "name: " .. tostring(x) .. "," .. tostring(y))
  p, x, y = Anchor(f.name, 2)
  assert(p == "TOPRIGHT" and x == -16 and y == -32)
  assert(f.name:GetNumPoints() == 2, "two top anchors, no centre ones")
  p, x, y = Anchor(f.controls)
  assert(p == "TOPRIGHT" and x == -12 and y == -8 and f.controls:GetHeight() == 20,
    "controls: at the padding, where the close button was (it is out of the way by default)")
  p, x, y = Anchor(f.close)
  assert(p == "TOPRIGHT" and x == -2 and y == -2)
  p, x, y = Anchor(f.scroll)
  assert(p == "TOPLEFT" and x == 0 and y == -6 and f.scroll:GetNumPoints() == 2)
  p, x, y = Anchor(f.progress)
  assert(p == "TOPLEFT" and y == -6 and f.progress:GetHeight() == 2 and f.progress:GetNumPoints() == 2)
  assert(f.lineHeight == 16, "13 + 3: the number SpeakStone's Fill multiplies by")
  -- text
  assert(f.name.font[1]:find("Cinzel", 1, true) and f.name.font[2] == 16, "the title face")
  assert(f.text.font[1] == ORIGIN and f.text.font[2] == 13 and f.text.spacing == 3)
  assert(f.controls.time.font[2] == 11)
  assert(f.progress.barColor[1] == 0xc9 / 255 and f.progress.barColor[4] == 0.9)
  -- Fill, the way SpeakStone does it: the height is the rows above and below, not 130 + the growth
  SS.Fill({ name = "Hogger", text = "Grr", lines = 2 })
  assert(f.scroll:GetHeight() == 64 and f:GetHeight() == 32 + 16 + 6 + 64 + 6 + 2 + 12,
    "height " .. f:GetHeight())
  SS.Fill({ name = "Hogger", text = "Grr", lines = 9, fit = true })
  assert(f.scroll:GetHeight() == 16 * 9 and f:GetHeight() == 32 + 16 + 6 + 144 + 6 + 2 + 12, "grows with the text: " .. f:GetHeight())
  -- buttons: their art is faded, fill and edge are ours, fonts are ours; labels, handlers and widths are SpeakStone's
  local pause = f.controls.pause
  assert(pause.Left.alpha == 0 and pause.Middle.alpha == 0 and pause.Right.alpha == 0 and pause.highlightTex.alpha == 0)
  assert(pause.normalTex.file == WHITE and pause.pushedTex.file == WHITE and pause.disabledTex.file == WHITE)
  assert(pause.normalFont == c.TwichUISpeakStoneButton and pause.highlightFont == c.TwichUISpeakStoneButtonHot
    and pause.disabledFont == c.TwichUISpeakStoneButtonOff)
  assert(pause:GetText() == "Pause" and pause:GetWidth() == 60 and pause:GetHeight() == 20)
  assert(c.TwichUISpeakStoneButton.font[2] == 11 and c.TwichUISpeakStoneButtonHot.color[1] ~= c.TwichUISpeakStoneButton.color[1],
    "hover is another colour")
  assert(f.close.normalTex.desaturated and f.close.normalTex.vertex[1] < 1, "the close button keeps its art, tinted")
  assert(f.controls.gear.normalTex.vertex[1] < 1)
  assert(#c.errors == 0)
  assert(c.hookCount == 3, "nothing further was hooked")
end

---------------------------------------------------------------------------
-- A setting change: coalesced into one pass; a colour does not make SpeakStone lay its text out again.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local f = SS.Build()
  local sd = { name = "Hogger", text = "Grr", lines = 3 }
  SS.Fill(sd)
  local before = S.Snapshot()
  for i = 0, 19 do assert(S.Style.Set("nameColor", ("ff%02x%02x%02x"):format(40 + i, 90, 120))) end
  assert(S.Snapshot().passes == before.passes, "nothing happens until the timer")
  FlushTimers()
  local after = S.Snapshot()
  assert(after.passes == before.passes + 1, "one pass for twenty changes")
  assert(after.layouts == before.layouts and f.filledFor == sd, "a colour is not a layout: SpeakStone is not made to fill again")
  assert(near(f.name.color[1], 59 / 255) and near(f.name.color[3], 120 / 255), "and it is drawn")
  -- the same value again changes nothing and redraws nothing
  assert(S.Style.Set("nameColor", "ff3b5a78"))
  FlushTimers()
  assert(S.Snapshot().passes == after.passes)
  -- a size is: the number SpeakStone multiplies by changes and it is told to fill again
  assert(S.Style.Set("textSize", 16))
  FlushTimers()
  assert(f.lineHeight == 19 and f.filledFor == nil and f.text.font[2] == 16, "line height " .. f.lineHeight)
  SS.Refresh(sd)
  assert(f.scroll:GetHeight() == 19 * 4 and f:GetHeight() == 32 + 16 + 6 + 76 + 6 + 2 + 12)
  -- the look: a border thickness pushes the content in and lays it out again
  local layouts = S.Snapshot().layouts
  assert(S.Look.Set("borderSize", 12))
  FlushTimers()
  local p, x, y = Anchor(f.name, 1)
  assert(S.Snapshot().layouts == layouts + 1 and f.filledFor == nil, "a thick border changes the layout")
  -- padding 16 (the border and 4), the ring both sides, portrait, gap; the controls row starts 4 above the padding
  assert(x == 16 + 4 + 72 + 14 and y == -(12 + 20 + 4), "content clears it: " .. x .. "," .. y)
  -- no portrait: its room is given back, and the frame still holds the column
  assert(S.Look.Set("borderSize", 1))
  assert(S.Style.Set("showPortrait", false))
  FlushTimers()
  p, x, y = Anchor(f.name, 1)
  assert(x == 12 and f.portrait:GetWidth() == 1 and f.portrait.alpha == 0, "no empty column: " .. x)
  -- square: the mask is given a file that clips nothing, and the ring loses its circle
  assert(S.Style.Set("showPortrait", true) and S.Style.Set("portraitShape", "square"))
  FlushTimers()
  assert(f.portraitMask.file == WHITE, "SpeakStone's one mask, so later portraits are square too")
  assert(S.Style.Set("portraitShape", "round"))
  FlushTimers()
  assert(f.portraitMask.file == MASK_FILE, "and round again")
  -- the progress line can go, and the frame is that much shorter
  SS.Fill(sd)
  local tall = f:GetHeight()
  assert(S.Style.Set("showProgress", false))
  FlushTimers()
  SS.Fill(sd)
  assert(f.progress.shown == false and f:GetHeight() == tall - 6 - 2, "height without it: " .. f:GetHeight())
  assert(#c.errors == 0)
end

---------------------------------------------------------------------------
-- A larger portrait than the text column holds makes the frame as tall as it needs; buttons keep their labels whole.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready({ db = { modules = { speakstoneSkin = true },
    ui = { speakstoneSkinStyle = { portraitSize = 96, portraitBorderSize = 4, textSize = 10, lineSpacing = 0,
      nameSize = 10, buttonSize = 14, padding = 16 } } } })
  local f = SS.Build()
  SS.Fill({ name = "A", text = "b", lines = 1 })
  local want = 16 + 8 + 96 + 16   -- padding, the ring both sides, the portrait, padding
  assert(f:GetHeight() >= want, "the portrait's column: " .. f:GetHeight() .. " vs " .. want)
  -- a 14 px label is wider than SpeakStone's 56 px for "Replay": the button widens, never clips
  assert(f.controls.replay:GetWidth() == 6 * 14 * 0.5 + 16, "widened: " .. f.controls.replay:GetWidth())
  assert(f.controls.stop:GetWidth() == 46, "the others keep SpeakStone's width")
  assert(f.controls.pause:GetHeight() == 22 and f.controls:GetHeight() == 22, "the row grows with the label")
end

---------------------------------------------------------------------------
-- Turning it off puts every recorded piece back (no reload); hooks stay but do nothing; on again draws once more.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local f = SS.Build()
  local sd = { name = "Hogger", text = "Grr", lines = 3 }
  SS.Fill(sd)
  local hooks, made = c.hookCount, #c.made
  c.TwichUIDB.modules.speakstoneSkin = false
  S.OnSwitch()
  assert(S.Status().code == "off" and S.Snapshot().restores == 1)
  for _, piece in ipairs(f.bandPieces) do assert(piece.alpha == 1 and piece.shown == true, "SpeakStone's band is back") end
  assert(f.track.alpha == 1)
  assert(f.name.fontObject == c.GameFontNormalLarge and f.name.font[2] == 16 and f.name.font[1] == ORIGIN)
  assert(f.name.color[1] == 1 and near(f.name.color[2], 0.82))
  assert(f.name:GetNumPoints() == 3 and select(1, f.name:GetPoint(1)) == "LEFT" and select(1, f.name:GetPoint(2)) == "TOP"
    and select(1, f.name:GetPoint(3)) == "RIGHT", "its own three anchors")
  assert(select(4, f.name:GetPoint(1)) == 14 and select(5, f.name:GetPoint(2)) == -32)
  assert(f.text.fontObject == c.SpeakStoneSpeechTextFont and f.text.spacing == 2 and f.text.font[2] == 13)
  assert(f.controls.time.fontObject == c.GameFontHighlightSmall and near(f.controls.time.color[1], 0.75)
    and near(f.controls.time.color[2], 0.72), "the grey SpeakStone set by hand")
  local pause = f.controls.pause
  assert(pause.Left.alpha == 1 and pause.highlightTex.alpha == 1 and pause.normalFont == c.GameFontNormalSmall
    and pause.highlightFont == c.GameFontHighlightSmall and pause.disabledFont == c.GameFontDisableSmall)
  assert(pause.normalTex.file == "" and pause:GetHeight() == 20 and pause:GetWidth() == 60)
  assert(f.close.normalTex.desaturated == false and f.close.normalTex.vertex[1] == 1)
  assert(f.progress:GetHeight() == 2 and f.progress.shown == true and near(f.progress.barColor[1], 0.94))
  assert(f.portrait:GetWidth() == 72 and select(4, f.portrait:GetPoint()) == 12 and f.portrait.alpha == 1)
  assert(f.lineHeight == 15 and f.filledFor == nil, "SpeakStone fills again with its own numbers")
  assert(f.controls:GetNumPoints() == 1 and select(4, f.controls:GetPoint()) == -28)
  SS.Refresh(sd)
  assert(f:GetHeight() == 130 and f.scroll:GetHeight() == 60, "its own height again: " .. f:GetHeight())
  assert(#c.made == made and c.hookCount == hooks, "nothing was made or hooked by turning it off")
  -- a setting changed while it is off does nothing
  assert(S.Style.Set("textSize", 18))
  FlushTimers()
  assert(f.text.font[2] == 13 and f.lineHeight == 15)
  S.Style.Reset()
  -- and on again: drawn once more, with no new hook
  c.TwichUIDB.modules.speakstoneSkin = true
  S.OnSwitch()
  assert(S.Status().code == "active" and f.lineHeight == 16 and f.filledFor == nil)
  assert(c.hookCount == hooks, "no hook added: " .. c.hookCount .. " vs " .. hooks)
  assert(#c.made == made, "the same objects are used again: " .. (#c.made - made))
  SS.Refresh(sd)
  assert(f:GetHeight() == 138)
  for i = 1, 3 do
    c.TwichUIDB.modules.speakstoneSkin = false; S.OnSwitch()
    c.TwichUIDB.modules.speakstoneSkin = true; S.OnSwitch()
  end
  assert(c.hookCount == hooks and S.Snapshot().frameHooked, "still the same hooks after more switching")
  assert(#c.errors == 0)
end

---------------------------------------------------------------------------
-- Close with a right-click: the button is out of the way and the frame's right-click clicks it; turned off, or
-- with the skin off, both are SpeakStone's again.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local f = SS.Build()
  assert(S.Style.Get("rightClickClose") == true, "on by default")
  assert(f.close.alpha == 0 and f.close.mouse == false, "invisible and click-through")
  assert(f.controls:GetPoint() == "TOPRIGHT" and select(4, f.controls:GetPoint()) == -12,
    "the controls take its place: " .. tostring(select(4, f.controls:GetPoint())))
  local onUp = f:GetScript("OnMouseUp")
  assert(onUp ~= SS.mouseUp, "the frame's script is ours")
  onUp(f, "RightButton")
  assert(SS.dismissed == 1 and SS.menus == 0, "SpeakStone's Dismiss ran, its menu did not")
  onUp(f, "LeftButton")
  assert(SS.dismissed == 1 and SS.menus == 0, "other buttons do nothing")
  -- off: SpeakStone's button and menu come back, the controls move back
  assert(S.Style.Set("rightClickClose", false))
  FlushTimers()
  assert(f.close.alpha == 1 and f.close.mouse == true and f:GetScript("OnMouseUp") == SS.mouseUp)
  assert(select(4, f.controls:GetPoint()) == -28, "the controls make room for it again")
  f:GetScript("OnMouseUp")(f, "RightButton")
  assert(SS.menus == 1 and SS.dismissed == 1, "its menu is back")
  assert(S.Style.Set("rightClickClose", true))
  FlushTimers()
  assert(f.close.alpha == 0 and f:GetScript("OnMouseUp") ~= SS.mouseUp)
  -- the skin off puts it all back, and a stray call of ours does nothing
  local ours = f:GetScript("OnMouseUp")
  c.TwichUIDB.modules.speakstoneSkin = false; S.OnSwitch()
  assert(f.close.alpha == 1 and f.close.mouse == true and f:GetScript("OnMouseUp") == SS.mouseUp)
  ours(f, "RightButton")
  assert(SS.dismissed == 1, "ours is inert while the skin is off")
  assert(select(4, f.controls:GetPoint()) == -28)
  c.TwichUIDB.modules.speakstoneSkin = true; S.OnSwitch()
  assert(f.close.alpha == 0 and f:GetScript("OnMouseUp") ~= SS.mouseUp)
  assert(#c.errors == 0)
end

---------------------------------------------------------------------------
-- A portrait SpeakStone captured for a queued quest is a Texture of the frame too, and is never faded.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local f = SS.Build()
  local captured = f:CreateTexture(nil, "ARTWORK")   -- SpeechFrameCapturePortrait makes these after Build
  f.captured = { captured }
  assert(S.Style.Set("textSize", 14))
  FlushTimers()
  assert(captured.alpha == 1 and captured.shown, "not touched by a later pass")
  c.TwichUIDB.modules.speakstoneSkin = false; S.OnSwitch()
  c.TwichUIDB.modules.speakstoneSkin = true; S.OnSwitch()   -- recorded afresh: it is in the frame's regions now
  assert(captured.alpha == 1 and captured.shown, "nor by recording the frame again")
  for _, piece in ipairs(f.bandPieces) do assert(piece.alpha == 0 and piece.shown == false) end
  assert(S.Snapshot().hidden == 4, "only SpeakStone's decoration: " .. S.Snapshot().hidden)
end

---------------------------------------------------------------------------
-- Turned off before SpeakStone ever builds its frame: the CreateFont hook (which cannot be removed) is inert.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  assert(c.hookCount == 1)
  c.TwichUIDB.modules.speakstoneSkin = false
  S.OnSwitch()
  local f = SS.Build()
  SS.Fill({ name = "Hogger", text = "Grr" })
  assert(c.hookCount == 1, "the frame is not hooked while the skin is off: " .. c.hookCount)
  assert(S.Status().code == "off" and f.lineHeight == 15 and f:GetHeight() == 130 and f.bandPieces[1].alpha == 1)
  assert(f.name:GetNumPoints() == 3 and #c.errors == 0)
  -- turned on afterwards: found then, hooked then
  c.TwichUIDB.modules.speakstoneSkin = true
  S.OnSwitch()
  assert(S.Status().code == "active" and c.hookCount == 3)
end

---------------------------------------------------------------------------
-- Turned on while SpeakStone's frame already exists: found, drawn, and made to lay out again.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = {} } })
  local R = Start(c)
  local S = R.SpeakStoneSkin
  local SS = MakeSpeakStone(c)
  local f = SS.Build()
  local sd = { name = "Hogger", text = "Grr", lines = 1 }
  SS.Fill(sd)
  assert(f:GetHeight() == 130 and c.hookCount == 0)
  c.TwichUIDB.modules.speakstoneSkin = true
  S.OnSwitch()
  assert(S.Status().code == "active" and c.hookCount == 3 and f.filledFor == nil and f.lineHeight == 16)
  SS.Refresh(sd)
  assert(f:GetHeight() == 138)
end

---------------------------------------------------------------------------
-- An unexpected frame (a piece missing) is left exactly as it is; saying so, not erroring.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready({ ss = { missing = "progress" } })
  local f = SS.Build()
  assert(S.Status().code == "unsupported", S.Status().code)
  assert(f.lineHeight == 15 and f.name:GetNumPoints() == 3 and f.bandPieces[1].alpha == 1, "nothing was changed")
  SS.Fill({ name = "Hogger", text = "x" })
  assert(f:GetHeight() == 130, "SpeakStone's own height")
  assert(#c.errors == 0)
end

---------------------------------------------------------------------------
-- A missing optional piece (the close button) is not a reason to do nothing.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready({ ss = { missing = "close" } })
  local f = SS.Build()
  assert(S.Status().code == "active" and f.close == nil)
  assert(#c.errors == 0)
end

---------------------------------------------------------------------------
-- An error while drawing: the frame is put back as it was, the error goes to the game's handler, and nothing is
-- tried again until the switch is turned off and on.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local f = SS.Build()
  assert(S.Status().code == "active")
  f.name.throwOn = "Cinzel"   -- the title face's file makes SetFont throw, as a broken font file can
  S.Style.Set("nameSize", 17)
  FlushTimers()
  assert(S.Status().code == "error", "the pass failed: " .. S.Status().code)
  assert(#c.errors == 1 and c.errors[1]:find("boom", 1, true), "to the game's error handler, once")
  assert(f.lineHeight == 15 and f.name:GetNumPoints() == 3 and f.bandPieces[1].alpha == 1, "put back")
  S.Style.Set("nameSize", 18)
  FlushTimers()
  assert(#c.errors == 1 and S.Status().code == "error", "not retried")
  f.name.throwOn = nil
  c.TwichUIDB.modules.speakstoneSkin = false; S.OnSwitch()
  c.TwichUIDB.modules.speakstoneSkin = true; S.OnSwitch()
  assert(S.Status().code == "active", "turned off and on, it tries again")
end

---------------------------------------------------------------------------
-- Settings: validation, defaults, reset's scope.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = {} } })
  local R = Start(c)
  local S = R.SpeakStoneSkin
  assert(c.TwichUIDB.ui == nil or c.TwichUIDB.ui.speakstoneSkinStyle == nil, "nothing is saved until a setting is changed")
  assert(not S.Style.Set("textSize", 99) and not S.Style.Set("textSize", 9) and not S.Style.Set("textSize", "13")
    and not S.Style.Set("textSize", 13.5))
  assert(not S.Style.Set("nameColor", "gold") and not S.Style.Set("nameColor", "ffff") and not S.Style.Set("nameFont", "a|cffff0000b"))
  assert(not S.Style.Set("showPortrait", "yes") and not S.Style.Set("portraitShape", "hexagon") and not S.Style.Set("nonsense", 1))
  assert(S.Style.Set("showProgress", false) and S.Style.Get("showProgress") == false, "false is a value")
  assert(S.Style.Set("lineSpacing", 0) and S.Style.Get("lineSpacing") == 0, "zero is a value")
  assert(not S.Look.Set("bgOpacity", 101) and not S.Look.Set("bgColor", "red"))
  c.TwichUIDB.ui.speakstoneSkinStyle = { textColor = "zzz", textSize = 3, portraitShape = 7, showProgress = "x", nameFont = {} }
  assert(S.Style.Get("textColor") == S.Style.DEFAULTS.textColor and S.Style.Get("textSize") == 13
    and S.Style.Get("portraitShape") == "round" and S.Style.Get("showProgress") == true
    and S.Style.Get("nameFont") == "Cinzel", "bad saved values fall back, and are left in the file")
  assert(c.TwichUIDB.ui.speakstoneSkinStyle.textSize == 3)
  -- reset: the look and the style, not the switch or anything else
  c.TwichUIDB.modules.speakstoneSkin = true
  c.TwichUIDB.ui.somethingElse = { keep = 1 }
  S.Look.Set("bgOpacity", 50)
  S.Reset()
  assert(c.TwichUIDB.ui.speakstoneSkin == nil and c.TwichUIDB.ui.speakstoneSkinStyle == nil)
  assert(c.TwichUIDB.modules.speakstoneSkin == true and c.TwichUIDB.ui.somethingElse.keep == 1)
  assert(S.Look.Get("bgOpacity") == 90 and S.Look.Get("borderSize") == 1)
end

---------------------------------------------------------------------------
-- Fonts: a name that is gone is drawn as SpeakStone's own and stays chosen; one that arrives is used.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local LSM = c.LibStub("LibSharedMedia-3.0")
  local f = SS.Build()
  assert(S.Style.Set("textFont", "Pack Font"))
  FlushTimers()
  assert(f.text.font[1] == ORIGIN and S.Snapshot().fallbackText and S.Style.Get("textFont") == "Pack Font")
  local listed = false
  for _, choice in ipairs(S.FontChoices("Pack Font")) do if choice[1] == "Pack Font" then listed = true end end
  assert(listed, "the saved choice stays listed")
  LSM:Register("font", "Pack Font", [[Interface\AddOns\Pack\Pack.ttf]], LSM.LOCALE_BIT_western)
  FlushTimers()
  assert(f.text.font[1] == [[Interface\AddOns\Pack\Pack.ttf]] and not S.Snapshot().fallbackText, "now it can be drawn")
  LSM:Register("font", "Broken", "Bad\\File.ttf", LSM.LOCALE_BIT_western)
  assert(S.Style.Set("timeFont", "Broken"))
  FlushTimers()
  assert(f.controls.time.font[1] == ORIGIN and S.Snapshot().fallbackTime, "a file the game refuses falls back")
  assert(#c.errors == 0)
end

---------------------------------------------------------------------------
-- Bounds: many lines, many settings passes and many switches create nothing and hook nothing more.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local f = SS.Build()
  local sd = { name = "Hogger", text = "Grr", lines = 2 }
  SS.Fill(sd)
  S.Style.Set("textSize", 14); FlushTimers()
  local made, hooks, fonts = #c.made, c.hookCount, c.fontsMade
  for i = 1, 200 do
    SS.Fill({ name = "N" .. i, text = "t" .. i, lines = 1 + i % 5, fit = i % 2 == 0 })
  end
  for i = 1, 40 do
    S.Style.Set("textColor", ("ff%02x%02x%02x"):format(i, 100, 200)); FlushTimers()
    S.Style.Set("progressHeight", 1 + i % 6); FlushTimers()
  end
  assert(#c.made == made, "no new objects: " .. (#c.made - made))
  assert(c.hookCount == hooks and c.fontsMade == fonts)
  assert(S.Snapshot().layouts <= 1 + 40, "layouts are done for the numbers that changed, not for colours")
  assert(#c.errors == 0)
end

---------------------------------------------------------------------------
-- Combat: SpeakStone's frame and buttons are plain, so the skin is drawn there too; the pass is not deferred.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local f = SS.Build()
  c.COMBAT = true
  assert(S.Style.Set("nameSize", 20))
  FlushTimers()
  assert(f.name.font[2] == 20, "applied in combat")
  c.COMBAT = false
end

---------------------------------------------------------------------------
-- The sample line: SpeakStone's own command, called as typing it does; nothing when it is not there.
---------------------------------------------------------------------------
do
  local c, R, S = Ready()
  assert(S.TogglePreview() == false, "no command, no error")
  local got
  c.SlashCmdList.SPEAKSTONE = function(msg) got = msg end
  assert(S.TogglePreview() == true and got == "frame")
  c.SlashCmdList.SPEAKSTONE = function() error("boom") end
  assert(S.TogglePreview() == false and #c.errors == 1, "its error is reported, not thrown")
end

---------------------------------------------------------------------------
-- The troubleshooting section: words and counts, never what is being said or by whom.
---------------------------------------------------------------------------
do
  local c, R, S, SS = Ready()
  local f = SS.Build()
  SS.Fill({ name = "SECRETSPEAKER", text = "SECRETLINE of dialogue" })
  local snap = S.Snapshot()
  assert(snap.createHook and snap.frameHooked and snap.draws == 1 and snap.hidden == 4 and snap.trackFound)
  local report = R.Diag.Build()
  assert(report:find("SpeakStone skin", 1, true), "its section is there")
  assert(report:find("state: active", 1, true), "and says it is active")
  assert(report:find("hooks", 1, true) and report:find("put back", 1, true))
  assert(not report:find("SECRETSPEAKER", 1, true) and not report:find("SECRETLINE", 1, true), "no text")
  assert(not report:find("Rich", 1, true), "no names")
  S.Snapshot = function() error("boom") end
  local broken = R.Diag.Build()
  assert(broken:find("SpeakStone skin", 1, true) and broken:find("Start-up", 1, true), "the rest of the report is intact")
end

print("SPEAKSTONE SKIN TESTS PASSED")
