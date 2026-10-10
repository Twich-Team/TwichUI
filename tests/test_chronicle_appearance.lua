-- Journey Chronicle appearance: the defaults are the look the window always had; every setting is
-- validated and saved on its own; background and border opacity are separate from the text; a media
-- choice that is not available is drawn safely and stays chosen; Reset touches only the appearance;
-- applying again adds no frame, texture, font string or hook; a waiting pass is dropped when nothing is
-- open; larger text and thicker borders make the window and its rows bigger instead of clipping; the
-- other windows that share chronicle/Style.lua keep their colours; and no Chronicle entry is touched.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local created = { frame = 0, texture = 0, font = 0, hooks = 0 }
local ALLFONTS, ALLFRAMES = {}, {}
local Methods
local FONT_OBJECTS = {
  GameFontNormalLarge = 16, GameFontNormal = 12, GameFontNormalSmall = 10, GameFontHighlightSmall = 10,
  GameFontDisableSmall = 10, GameFontDisable = 12, GameFontHighlight = 12, ChatFontNormal = 14,
}
local FRIZ = "Fonts\\FRIZQT__.TTF"
for name, size in pairs(FONT_OBJECTS) do
  c[name] = { GetFont = function() return FRIZ, size, "" end }
end
local function Fake(kind)
  local o = { kind = kind, shown = true, scripts = {}, points = {}, text = "", alphaSet = 1, spacing = 0, textColor = nil }
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
local function Lines(s)
  local font = s.font or { FRIZ, 10 }
  local size = font[2]
  local text = s.text or ""
  local w = #text * size * 0.5
  local n = select(2, text:gsub("\n", "")) + 1
  if s.width and s.width > 0 and s.wrap ~= false then n = math.max(n, math.ceil(w / s.width)) end
  return n, w, size
end
Methods = {
  Show = function(s) if not s.shown then s.shown = true; if s.scripts.OnShow then s.scripts.OnShow(s) end
    for _, h in ipairs(s.hookList or {}) do if h[1] == "OnShow" then h[2](s) end end end end,
  Hide = function(s) if s.shown then s.shown = false; if s.scripts.OnHide then s.scripts.OnHide(s) end end end,
  IsShown = function(s) return s.shown end,
  SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end,
  GetScript = function(s, n) return s.scripts[n] end,
  HookScript = function(s, n, fn)
    s.hookList = s.hookList or {}
    table.insert(s.hookList, { n, fn })
    created.hooks = created.hooks + 1
  end,
  CreateTexture = function(s) created.texture = created.texture + 1; local t = Fake("texture"); t.parent = s; t.shown = true; return t end,
  CreateFontString = function(s, _, _, template)
    created.font = created.font + 1
    local t = Fake("font"); t.parent = s; t.template = template
    ALLFONTS[#ALLFONTS + 1] = t
    local size = FONT_OBJECTS[template or ""] or 12
    t.font = { FRIZ, size, "" }
    return t
  end,
  SetText = function(s, v) s.text = tostring(v or "") end,
  GetText = function(s) return s.text end,
  SetFont = function(s, path, size, flags)
    if type(path) == "string" and path:find("BADFONT") then return false end
    s.font = { path, size, flags or "" }; s.fontCalls = (s.fontCalls or 0) + 1
    return true
  end,
  SetFontObject = function(s, name)
    s.font = { FRIZ, FONT_OBJECTS[name] or 12, "" }; s.objectCalls = (s.objectCalls or 0) + 1
  end,
  GetFont = function(s) local f = s.font; if f then return f[1], f[2], f[3] end end,
  SetSpacing = function(s, v) s.spacing = v end,
  SetAlpha = function(s, a) s.alphaSet = a end,
  GetStringHeight = function(s) local n, _, size = Lines(s); return n * (size + (s.spacing or 0)) end,
  GetStringWidth = function(s) local _, w = Lines(s); return math.min(w, (s.width and s.width > 0) and s.width or w) end,
  SetWidth = function(s, v) s.width = v end,
  SetHeight = function(s, v) s.height = v end,
  SetSize = function(s, w, h) s.width, s.height = w, h end,
  GetWidth = function(s) return s.width or 100 end,
  GetHeight = function(s) return s.height or 20 end,
  SetWordWrap = function(s, v) s.wrap = v end,
  ClearAllPoints = function(s) s.points = {} end,
  SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
  SetColorTexture = function(s, r, g, b, a) s.color = { r, g, b, a } end,
  SetTextColor = function(s, r, g, b) s.textColor = { r, g, b } end,
  SetBackdrop = function(s, info) s.backdrop = info end,
  SetBackdropColor = function(s, r, g, b, a) s.bgColor = { r, g, b, a } end,
  SetBackdropBorderColor = function(s, r, g, b, a) s.edgeColor = { r, g, b, a } end,
  SetChecked = function(s, v) s.checked = v end,
  GetChecked = function(s) return s.checked end,
  SetEnabled = function(s, v) s.enabled = v and true or false end,
  IsEnabled = function(s) return s.enabled ~= false end,
  Enable = function(s) s.enabled = true end,
  Disable = function(s) s.enabled = false end,
  IsMouseOver = function() return false end,
  GetEffectiveScale = function() return 1 end,
  GetScale = function(s) return s.scale or 1 end,
  SetScale = function(s, v) s.scale = v end,
  GetFrameLevel = function() return 1 end,
  GetNormalTexture = function(s) s.normalTex = s.normalTex or Fake("texture"); return s.normalTex end,
  GetPushedTexture = function(s) s.pushedTex = s.pushedTex or Fake("texture"); return s.pushedTex end,
  GetDisabledTexture = function(s) s.disabledTex = s.disabledTex or Fake("texture"); return s.disabledTex end,
  GetHighlightTexture = function(s) s.highlightTex = s.highlightTex or Fake("texture"); return s.highlightTex end,
}
c.CreateFrame = function(kind, name, parent, template)
  created.frame = created.frame + 1
  local f = Fake(kind); f.name, f.parent, f.template = name, parent, template
  ALLFRAMES[#ALLFRAMES + 1] = f
  f.shown = true
  if template == "UIPanelScrollFrameTemplate" then
    local bar = Fake("slider")
    bar.ThumbTexture = Fake("texture")
    bar.ScrollUpButton, bar.ScrollDownButton = Fake("button"), Fake("button")
    f.ScrollBar = bar
  end
  if name then c[name] = f end
  return f
end
c.UIParent = Fake("UIParent")
c.UIParent.GetWidth = function() return 1920 end
c.UIParent.GetHeight = function() return 1080 end
c.UISpecialFrames = {}
c.tinsert = table.insert
c.GameTooltip = Fake("tooltip")
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function() end
c.CANCEL = "Cancel"; c.Settings = nil
c.GetRealZoneText = function() return "Elwynn Forest" end
c.TwichUIDB = {}
c.TwichUIChronicleDB = nil
c.SOUNDKIT = { IG_ABILITY_PAGE_TURN = 836 }
c.PlaySound = function() end
c.STANDARD_TEXT_FONT = FRIZ

for _, file in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "chronicle/Style.lua", "chronicle/Appearance.lua", "chronicle/Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local A, S, W, C, MS = R.ChronicleAppearance, R.ChronicleStyle, R.ChronicleWindow, R.Chronicle, R.MenuStyle
local LSM = c.LibStub("LibSharedMedia-3.0")
local function near(a, b, msg) assert(math.abs(a - b) < 1e-6, (msg or "") .. ": " .. tostring(a) .. " vs " .. tostring(b)) end
local function DeepCopy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = DeepCopy(v) end return o end
local function Equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local function Settle() FlushTimers() end

-- The palette Style.lua keeps for every other window, as it was, to compare against at the end.
local K0 = DeepCopy(S.color)
local DEFAULT_PALETTE = DeepCopy(S.palette)

-- Some Chronicle data, to show that none of it changes.
C.Add("note", { title = "Note", note = "A long note that wraps over more than one line of the entry list, with words enough to need it" })
C.Add("level", { title = "Reached level 5", level = 5 })
local dataBefore = DeepCopy(c.TwichUIChronicleDB)
assert(dataBefore and dataBefore.chars, "the Chronicle has data")

---------------------------------------------------------------------------
-- 1. Defaults are the look the window always had
---------------------------------------------------------------------------
assert(A.Look, "the look exists once the addon has loaded")
for key, default in pairs(A.DEFAULTS) do assert(A.Get(key) == default, key .. " default") end
for key, default in pairs(A.LOOK_DEFAULTS) do assert(A.Look.Get(key) == default, key .. " look default") end
assert(c.TwichUIDB.ui == nil or c.TwichUIDB.ui.chronicleAppearance == nil, "nothing is saved until a setting is changed")

W:Show()
local f = c.TwichUIChronicle
assert(f and f.shown, "the window opens")
assert(f.width == 540 and f.height == 580, "default size " .. tostring(f.width) .. "x" .. tostring(f.height))
-- the ledger rim: the pieces are shown, the border is drawn by Style.lua, the backdrop draws no edge
local parts = f.twichFrame
assert(parts.rim[1].shown and parts.corners[1].shown and parts.lit.top.shown, "ledger shown")
assert(parts.outer and parts.outer[1].shown, "the dark outer line is its own texture")
assert(f.backdrop.edgeFile == nil and f.backdrop.bgFile == [[Interface\Buttons\WHITE8x8]], "solid fill, no backdrop edge")
near(f.bgColor[1], S.color.bg[1], "fill color is the ledger's umber exactly"); near(f.bgColor[4], 0.98, "fill opacity")
near(parts.rim[1].color[1], S.color.bronze[1]); near(parts.rim[1].color[4], 0.9)
near(parts.corners[1].color[1], S.color.gold[1]); near(parts.corners[1].color[4], 0.9)
assert(parts.speckle[1].shown and parts.bands[1].shown, "worn surface on")
-- header band, list well, row art
local band = f.twichHeader.band
near(band.color[1], S.color.band[1]); assert(band.height == 56, "band height " .. tostring(band.height))
near(f.box.bgColor[1], S.color.well[1]); near(f.box.bgColor[4], 0.92)
-- text: title, details and notes
near(f.title.textColor[1], S.color.text[1]); near(f.sub.textColor[1], S.color.stone[1])
assert(f.title.font[2] == 16 and f.title.objectCalls == nil and f.title.fontCalls == nil, "the title is the game's own font, untouched")
-- the buttons
near(f.new.bgColor[1], 0.30); near(f.new.edgeColor[1], 0.79)

---------------------------------------------------------------------------
-- 2. Validation, saving, and that defaults never overwrite a saved false/0
---------------------------------------------------------------------------
assert(A.Set("hoverOpacity", 0) and A.Get("hoverOpacity") == 0, "0 is a value")
assert(A.Set("worn", false) and A.Get("worn") == false, "false is a value")
assert(not A.Set("hoverOpacity", 41) and A.Get("hoverOpacity") == 0, "out of range refused, the old value kept")
assert(not A.Set("hoverOpacity", 2.5) and not A.Set("hoverOpacity", "5"), "whole numbers only")
assert(not A.Set("accentColor", "red") and not A.Set("accentColor", "c9a34a"), "colors are AARRGGBB")
assert(not A.Set("outline", "glow") and not A.Set("buttonStyle", "neon") and not A.Set("unknown", 1))
assert(not A.Set("font", "bad|name") and not A.Set("font", ""), "names are plain text")
assert(not A.Set("windowOpacity", 10) and not A.Set("textOpacity", 5), "the window can't be made invisible")
assert(A.Set("windowOpacity", 40) and A.Set("textOpacity", 30))
-- damaged saved values read as defaults and are not erased
c.TwichUIDB.ui.chronicleAppearance.hoverOpacity = 999
c.TwichUIDB.ui.chronicleAppearance.accentColor = 17
assert(A.Get("hoverOpacity") == A.DEFAULTS.hoverOpacity and A.Get("accentColor") == A.DEFAULTS.accentColor)
assert(c.TwichUIDB.ui.chronicleAppearance.hoverOpacity == 999, "the saved value is left alone")
c.TwichUIDB.ui.chronicleAppearance.hoverOpacity = 0
-- the saved container is repaired by Persist when it is not a table
c.TwichUIDB.ui.chronicleAppearance = "oops"; c.TwichUIDB.ui.chronicleLook = 5
R.Persist.Normalize(c.TwichUIDB)
assert(c.TwichUIDB.ui.chronicleAppearance == nil and c.TwichUIDB.ui.chronicleLook == nil, "not tables: dropped for the owner to rebuild")
assert(A.Get("worn") == true and A.Look.Get("bgOpacity") == 98, "and read as defaults")
A.Reset(); Settle()

-- the look: its own validation and the optional keys
assert(A.Look.Set("bgTiling", "stretch") and A.Look.Get("bgTiling") == "stretch")
assert(not A.Look.Set("bgTiling", "zoom"), "tiling is auto, tile or stretch")
assert(A.Look.Set("bgTileSize", 128) and not A.Look.Set("bgTileSize", 8) and not A.Look.Set("bgTileSize", 300))
assert(A.Look.Set("bgInset", 6) and not A.Look.Set("bgInset", 17))
assert(A.Look.Set("borderTexture", "ledger") and A.Look.Get("borderTexture") == "ledger")
assert(MS.Get("bgTiling") == "auto" and MS.Get("bgTileSize") == 64 and MS.Get("bgInset") == 0,
  "a look that doesn't name them keeps the old behaviour")
A.Reset(); Settle()

---------------------------------------------------------------------------
-- 3. Background: texture, tint, opacity, tiling, inset; opacity touches the background only
---------------------------------------------------------------------------
A.Look.Set("bgOpacity", 40); A.Look.Set("bgColor", "ff204060")
Settle()
near(f.bgColor[4], 0.40, "background opacity"); near(f.bgColor[3], 0x60 / 255, "tint")
near(band.color[4], 0.40 / 0.98, "the header band follows the background")
near(f.box.bgColor[4], 0.92 * 0.40 / 0.98, "and so does the list")
near(f.title.textColor[1], S.color.text[1], "text color untouched")
assert(f.title.alphaSet == 1, "text opacity is its own setting")
near(parts.rim[1].color[4], 0.9, "border opacity untouched")
-- a background image: tiled by default, stretched when asked, with a tile size and an inset
LSM:Register("background", "Test Parchment", [[Interface\AddOns\Test\parchment]])
A.Look.Set("bgTexture", "Test Parchment"); Settle()
assert(f.backdrop.bgFile == [[Interface\AddOns\Test\parchment]] and f.backdrop.tile == true and f.backdrop.tileSize == 64)
assert(A.BackgroundIsImage() == true)
A.Look.Set("bgTileSize", 32); A.Look.Set("bgInset", 5); Settle()
assert(f.backdrop.tileSize == 32 and f.backdrop.insets.left == 5, "tile size and inset")
A.Look.Set("bgTiling", "stretch"); Settle()
assert(f.backdrop.tile == false and f.backdrop.tileSize == nil, "stretched, so no tile size")
A.Look.Set("bgTexture", "solid"); Settle()
assert(A.BackgroundIsImage() == false and f.backdrop.tile == false, "a plain color is neither")
A.Look.Set("bgTexture", "none"); Settle()
assert(f.backdrop.bgFile == nil, "None draws no fill")
A.Reset(); Settle()

---------------------------------------------------------------------------
-- 4. Border: style, color, opacity, thickness; a thicker border grows the window, not the content
---------------------------------------------------------------------------
A.Look.Set("borderTexture", "solid"); A.Look.Set("borderSize", 4); A.Look.Set("borderColor", "ff336699"); A.Look.Set("borderOpacity", 50)
Settle()
assert(not parts.rim[1].shown and not parts.corners[1].shown and not parts.outer[1].shown, "the ledger is hidden")
assert(f.backdrop.edgeFile == [[Interface\Buttons\WHITE8x8]] and f.backdrop.edgeSize == 4, "a 4 pixel line")
near(f.edgeColor[4], 0.5); near(f.edgeColor[3], 0x99 / 255)
assert(f.width == 540 and f.height == 580, "a 4 pixel border fits the rim's room")
A.Look.Set("borderSize", 16); Settle()
assert(f.width == 540 + 2 * 12 and f.height == 580 + 2 * 12, "16 pixels: the window grows by 12 a side: " .. f.width .. "x" .. f.height)
local boxTop = f.box.points[1]
assert(boxTop[1] == "TOPLEFT" and boxTop[2] == 16 + 12 and boxTop[3] == -(16 + 90), "the list sits in from the thicker border")
local first = f.points[1]
assert(first[1] == "CENTER", "the window's own place is not touched: " .. tostring(first[1]))
A.Look.Set("borderTexture", "none"); Settle()
assert(f.backdrop.edgeFile == nil and f.width == 540, "None: no border, the content keeps its 4 pixels")
assert(A.BorderIsShown() == false and A.BorderHasWidth() == false)
A.Look.Set("borderTexture", "ledger"); Settle()
assert(parts.rim[1].shown and A.BorderHasWidth() == false, "the ledger has a fixed width")
A.Reset(); Settle()
-- padding is separate from the border
A.Set("padding", 8); Settle()
assert(f.width == 540 + 16, "padding grows the window by 8 a side")
A.Set("padding", 0); Settle()

---------------------------------------------------------------------------
-- 5. Text: faces, sizes, outline, colors, spacing; rows and the header make room
---------------------------------------------------------------------------
W:Refresh()
local function ShownRowTitles()
  local out = {}
  for _, fs in ipairs(ALLFONTS) do
    if fs.template == "GameFontNormal" and fs.parent and fs.parent.entry then out[#out + 1] = fs end
  end
  return out
end
local titles = ShownRowTitles()
assert(#titles >= 2, "rows exist: " .. #titles)
local rowTall = titles[1].parent.height
-- a font from LibSharedMedia, as TwichUI and EllesmereUI register theirs
LSM:Register("font", "Test Serif", [[Interface\AddOns\Test\serif.ttf]])
A.Set("font", "Test Serif"); Settle()
assert(f.sub.font[1] == [[Interface\AddOns\Test\serif.ttf]] and f.sub.font[2] == 10, "face changed, size the game's own")
assert(f.title.font[1] == [[Interface\AddOns\Test\serif.ttf]], "headings follow the text font")
A.Set("headingFont", "default"); Settle()
assert(f.title.font[1] == FRIZ and f.sub.font[1] == [[Interface\AddOns\Test\serif.ttf]], "headings can have a face of their own")
A.Set("headingFont", "inherit")
A.Set("customSizes", true); A.Set("titleSize", 24); A.Set("headingSize", 18); A.Set("metaSize", 14); A.Set("bodySize", 12)
A.Set("outline", "outline"); A.Set("lineSpacing", 3)
Settle()
assert(f.title.font[2] == 24 and f.title.font[3] == "OUTLINE" and f.sub.font[2] == 14, "sizes and outline")
assert(f.title.spacing == 3, "line spacing")
assert(f.height > 580, "larger header text makes the window taller, not the list smaller: " .. f.height)
local boxRight = f.box.points[2]
assert(boxRight[1] == "BOTTOMRIGHT" and boxRight[3] == 4 + 48, "the list's bottom edge stays above the buttons")
titles = ShownRowTitles()
assert(titles[1].parent.height > rowTall, "rows grow with their text: " .. titles[1].parent.height .. " vs " .. rowTall)
assert(titles[1].width == 540 - 32 - 40 - 38, "the wrap width is the row's, so the text wraps rather than clips")
assert(f.new.width >= 120, "buttons never get narrower")
-- colors and opacity
A.Set("titleColor", "ff112233"); A.Set("metaColor", "ff445566"); A.Set("textOpacity", 60); Settle()
near(f.title.textColor[3], 0x33 / 255); near(f.sub.textColor[1], 0x44 / 255)
near(f.title.alphaSet, 0.6); near(f.sub.alphaSet, 0.6)
assert(f.new.text.alphaSet == 1, "control labels are not faded by the text opacity")
near(f.bgColor[4], 0.98, "the background is not text")
-- semantic colors stay: the delete link and the disabled button
local del = titles[1].parent.delete
near(del.text.textColor[1], S.color.ember[1], "Delete keeps its warning color")
-- back to the game's own fonts: given back through the font object
A.Reset(); Settle()
assert(f.title.font[1] == FRIZ and f.title.font[2] == 16 and f.title.font[3] == "", "default font restored")
assert(f.title.spacing == 0 and f.title.alphaSet == 1)
assert(f.height == 580 and f.width == 540, "default size restored: " .. f.height)

---------------------------------------------------------------------------
-- 6. Accents and controls
---------------------------------------------------------------------------
A.Set("accentColor", "ff3399cc"); A.Set("dividerColor", "ff223344"); A.Set("hoverOpacity", 20); A.Set("showDividers", false)
A.Set("scrollThumbColor", "ff00ff00"); A.Set("buttonStyle", "outline")
Settle()
near(f.new.edgeColor[3], 0xcc / 255, "the main button's border follows the accent")
near(f.new.bgColor[1], S.palette.quiet.bg[1], "outline: the quiet fill") -- default quiet fill (listColor unchanged)
near(f.twichHeader.line.color[4], 0, "dividers off")
near(f.twichFrame.corners[1].color[3], 0xcc / 255, "the rim's corners are accent")
A.Reset(); Settle()
near(f.new.bgColor[1], 0.30, "back to the filled button")

---------------------------------------------------------------------------
-- 7. Media that is missing: drawn safely, still chosen; found again when it appears
---------------------------------------------------------------------------
A.Set("font", "Late Font"); A.Look.Set("bgTexture", "Late Texture"); A.Look.Set("borderTexture", "Late Border"); Settle()
assert(f.sub.font[1] == FRIZ, "the game's own font is drawn")
assert(A.Get("font") == "Late Font" and A.Look.Get("bgTexture") == "Late Texture" and A.Look.Get("borderTexture") == "Late Border",
  "the choices are still saved")
assert(c.TwichUIDB.ui.chronicleAppearance.font == "Late Font" and c.TwichUIDB.ui.chronicleLook.bgTexture == "Late Texture")
local snap = A.Snapshot()
assert(#snap.fallbacks > 0, "the report says a font fell back")
local labels = {}
for _, ch in ipairs(A.Look.BackgroundChoices()) do labels[ch[1]] = ch[2] end
assert(labels["Late Texture"] and labels["Late Texture"]:find("not available"), "listed, marked unavailable")
local fontLabels = {}
for _, ch in ipairs(MS.Fonts.Choices(A.Get("font"), { { "default", "Game font (default)" } })) do fontLabels[ch[1]] = ch[2] end
assert(fontLabels["Late Font"] and fontLabels["Late Font"]:find("not available") and fontLabels["Test Serif"], "fonts listed too")
-- the pack arrives
LSM:Register("font", "Late Font", [[Interface\AddOns\Late\font.ttf]])
Settle()
assert(f.sub.font[1] == [[Interface\AddOns\Late\font.ttf]], "drawn as soon as the font is registered")
assert(#A.Snapshot().fallbacks == 0)
-- a font the game refuses
LSM:Register("font", "BADFONT", [[Interface\AddOns\Late\BADFONT.ttf]])
A.Set("font", "BADFONT"); Settle()
assert(f.sub.font[1] == FRIZ, "a font the game can't draw falls back")
assert(A.Get("font") == "BADFONT", "and stays chosen")
A.Reset(); Settle()

---------------------------------------------------------------------------
-- 8. Reset touches only the appearance
---------------------------------------------------------------------------
c.TwichUIDB.ui.chronicleClock = "24"
c.TwichUIDB.modules.chronicleSound = false
A.Set("accentColor", "ff3399cc"); A.Look.Set("bgOpacity", 30)
C.SetFilter("day", C.Today())
A.Reset(); Settle()
assert(c.TwichUIDB.ui.chronicleAppearance == nil and c.TwichUIDB.ui.chronicleLook == nil)
assert(c.TwichUIDB.ui.chronicleClock == "24" and c.TwichUIDB.modules.chronicleSound == false, "functional settings kept")
assert(C.FilterActive(), "the date filter is not appearance")
C.ClearFilter()
assert(Equal(c.TwichUIChronicleDB, dataBefore), "no Chronicle entry or note changed")

---------------------------------------------------------------------------
-- 9. Repeated changes add nothing; a change while closed costs nothing; a waiting pass is cancelled
---------------------------------------------------------------------------
local ed
local before = { frame = created.frame, texture = created.texture, font = created.font, hooks = created.hooks }
for i = 1, 25 do
  A.Set("accentColor", i % 2 == 0 and "ff3399cc" or "ff99cc33")
  A.Look.Set("borderSize", i % 2 == 0 and 3 or 5); A.Look.Set("borderTexture", i % 2 == 0 and "solid" or "ledger")
  A.Set("headingSize", 10 + i % 8); A.Set("customSizes", true)
  Settle()
end
A.Reset(); Settle()
assert(created.frame == before.frame and created.texture == before.texture and created.font == before.font
  and created.hooks == before.hooks, "no frame, texture, font string or hook was added by repeated changes")
local snap0 = A.Snapshot()
-- many changes in one moment are one pass
local applies = snap0.applies
for i = 1, 10 do A.Set("hoverOpacity", i) end
Settle()
assert(A.Snapshot().applies == applies + 1, "coalesced into one pass: " .. (A.Snapshot().applies - applies))
-- closing drops a waiting pass
applies = A.Snapshot().applies
A.Set("hoverOpacity", 12)
assert(A.Snapshot().waiting == true)
f:Hide()
assert(A.Snapshot().waiting == false, "closed: nothing waits")
Settle()
assert(A.Snapshot().applies == applies, "and the timer that was waiting does nothing")
-- changed while closed: no timer; drawn as the window opens, once
A.Set("hoverOpacity", 30)
assert(A.Snapshot().waiting == false, "closed: no timer scheduled")
W:Show()
assert(A.Snapshot().applies == applies + 1, "drawn once as it opens")
near(f.twichFrame.rim[1].color[4], 0.9)
assert(f.shown)

---------------------------------------------------------------------------
-- 10. The note editor and the date picker follow the same look
---------------------------------------------------------------------------
A.Set("accentColor", "ff3399cc"); A.Look.Set("borderTexture", "solid"); A.Look.Set("borderSize", 10)
Settle()
-- open the editor through its button
local function FindButton(label)
  for _, o in ipairs(ALLFRAMES) do
    if o.kind == "Button" and type(o.text) == "table" and o.text.text == label then return o end
  end
end
local write = FindButton("Write a note")
assert(write, "the Write a note button")
write.scripts.OnClick()
ed = c.TwichUIChronicleNote
assert(ed and ed.shown, "the editor opened")
assert(ed.width == 440 + 2 * 6 and ed.backdrop.edgeSize == 10, "the editor has the same border and room: " .. ed.width)
assert(ed.height > 190)
near(ed.save.edgeColor[3], 0xcc / 255, "its Save button uses the accent")
-- the hint's warning colour is semantic and survives a change
ed.box.scripts.OnEnterPressed()
near(ed.hint.textColor[1], S.color.ember[1], "a warning is in the warning color")
A.Set("metaColor", "ff445566"); Settle()
near(ed.hint.textColor[1], S.color.ember[1], "still after the palette changed")
ed:Hide()
-- the date picker
local filter = f.filter
filter.scripts.OnClick()
local pop = c.TwichUIChronicleDate
assert(pop and pop.shown, "the picker opened")
near(pop.edgeColor[4], 0.95, "its border")
A.Set("accentColor", "ff99cc33"); Settle()
near(pop.cells[1].today.color[1], 0x99 / 255, "the calendar's marks follow the accent")
pop:Hide()

---------------------------------------------------------------------------
-- 11. Nothing outside the Chronicle window changed
---------------------------------------------------------------------------
assert(Equal(S.color, K0), "Style.lua's colours are the ones every other window draws with")
assert(Equal(S.palette, DEFAULT_PALETTE), "and so is its default palette")
local plain = c.CreateFrame("Frame")
local other = S.Button(plain, "Fill", 80, "primary", function() end)
near(other.edgeColor[1], 0.79); near(other.bgColor[1], 0.30)
assert(f.new.edgeColor[3] ~= other.edgeColor[3], "this window's button differs; another window's is unchanged")

---------------------------------------------------------------------------
-- 12. Combat and scale: nothing here is protected, and a scale change is drawn again
---------------------------------------------------------------------------
c.InCombatLockdown = function() return true end
A.Set("accentColor", "ff553311"); Settle()
near(f.new.edgeColor[1], 0x55 / 255, "windows are not protected frames: a change in combat is drawn")
c.InCombatLockdown = function() return false end
applies = A.Snapshot().applies
c.FireEvent("UI_SCALE_CHANGED"); Settle()
assert(A.Snapshot().applies == applies + 1, "a UI scale change draws the window again")

-- a small screen: the window is fitted, and the border's pixels are worked out at the scale it ended with
f:Hide()
A.Reset(); Settle()
A.Look.Set("borderTexture", "solid"); A.Look.Set("borderSize", 6); Settle()
c.UIParent.GetWidth = function() return 500 end
W:Show()
assert(f.scale and f.scale < 1 and f.scale >= 0.6, "fitted to a small screen: " .. tostring(f.scale))
assert(f.paintScale == f.scale, "and drawn at that scale")
c.UIParent.GetWidth = function() return 1920 end
f:Hide(); f.scale = 1; W:Show()
assert(f.scale == 1, "back at full size when there is room")

-- the other cards and windows know nothing of this file
for _, file in ipairs({ "modules/Arrival.lua", "modules/WelcomeBack.lua", "modules/Welcome.lua", "modules/Training.lua",
  "modules/FriendLogin.lua", "auction/Window.lua", "modules/RefreshmentsPanel.lua", "modules/RefreshmentsTrade.lua" }) do
  local h = assert(io.open(ROOT .. file, "r")); local text = h:read("*a"); h:close()
  assert(not text:find("ChronicleAppearance", 1, true), file .. " is not drawn from the Chronicle's appearance")
end

print("CHRONICLE APPEARANCE OK")
