-- Broker menu appearance: the shared look of the Mage menus. Defaults are the old look; each
-- setting is validated and saved on its own; background and border opacity are independent and
-- never touch the frame's alpha (so text and icons stay solid); "None" and unavailable textures
-- are safe; game and LibSharedMedia textures are offered, including ones registered later;
-- Reset touches only this appearance; borders are whole screen pixels and the menu keeps its
-- content clear of them; an open menu follows a change, but never in combat; the preview is a
-- sample that does nothing.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local frames = {}
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, attrs = {}, points = {}, calls = {}, backdropCalls = 0 }
  table.insert(frames, o)
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
  SetAttribute = function(s, k, v) s.attrs[k] = v end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  SetText = function(s, v) s.text = v end,
  ClearAllPoints = function(s) s.points = {} end,
  SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
  SetHeight = function(s, v) s.height = v end,
  SetColorTexture = function(s, r, g, b, a) s.color = { r, g, b, a } end,
  SetBackdrop = function(s, info) s.backdrop = info; s.backdropCalls = s.backdropCalls + 1 end,
  SetBackdropColor = function(s, r, g, b, a) s.bgColor = { r, g, b, a } end,
  SetBackdropBorderColor = function(s, r, g, b, a) s.edgeColor = { r, g, b, a } end,
  SetAlpha = function(s, a) s.alphaSet = a end,
  EnableMouse = function(s, v) s.mouse = v end,
  IsMouseOver = function() return false end,
  GetEffectiveScale = function() return 1 end,
}
c.CreateFrame = function(kind, name, parent, template)
  local f = Fake(kind); f.name, f.parent, f.template = name, parent, template; return f
end
c.UIParent = Fake("UIParent")
c.UIParent.GetEffectiveScale = function() return 1 end
c.UIParent.GetWidth = function() return 1024 end
c.UIParent.GetHeight = function() return 768 end
c.UISpecialFrames = {}
c.tinsert = table.insert
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
c.COMBAT = false
c.InCombatLockdown = function() return c.COMBAT end

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local MS, SM = R.MenuStyle, R.SpellMenu
local LSM = c.LibStub("LibSharedMedia-3.0")
local WHITE = [[Interface\Buttons\WHITE8x8]]
local function near(a, b) return math.abs(a - b) < 0.002 end

-- A fresh frame and what Apply drew on it.
local function Styled()
  local f = Fake("Frame")
  local edge = MS.Apply(f)
  return f, edge
end

-- Defaults: the look the menus had, with nothing saved.
do
  for key, value in pairs(MS.DEFAULTS) do assert(MS.Get(key) == value, key .. " default") end
  assert(c.TwichUIDB.ui == nil, "reading saves nothing")
  local f, edge = Styled()
  assert(f.backdrop.bgFile == WHITE and f.backdrop.edgeFile == WHITE and edge == 1, "a flat fill and a one pixel line")
  assert(f.backdrop.tile == false and f.backdrop.edgeSize == 1)
  assert(near(f.bgColor[1], 43 / 255) and near(f.bgColor[2], 33 / 255) and near(f.bgColor[3], 23 / 255) and f.bgColor[4] == 1,
    "the Chronicle's umber, fully solid")
  assert(near(f.edgeColor[1], 0x8c / 255) and near(f.edgeColor[2], 0x6e / 255) and near(f.edgeColor[3], 0x38 / 255)
    and near(f.edgeColor[4], 0.95), "the bronze line at 95%")
  assert(f.twichBevel.top.shown and f.twichBevel.bottom.shown, "the plain line keeps its faint highlight and shade")
  assert(f.alphaSet == nil, "the frame's own alpha is never used")
end

-- Each setting is validated and saved alone; only changed ones are saved.
do
  assert(not MS.Set("bgOpacity", 101) and not MS.Set("bgOpacity", -1) and not MS.Set("bgOpacity", 50.5)
    and not MS.Set("bgOpacity", "50") and not MS.Set("borderSize", 17) and not MS.Set("borderSize", 0 / 0))
  assert(not MS.Set("bgColor", "red") and not MS.Set("bgColor", "ff12345") and not MS.Set("borderColor", 5))
  assert(not MS.Set("bgTexture", "") and not MS.Set("bgTexture", "a|cffff0000b") and not MS.Set("borderTexture", {}))
  assert(not MS.Set("nonsense", 1))
  assert(c.TwichUIDB.ui == nil or c.TwichUIDB.ui.brokerMenu == nil, "refused values save nothing")
  c.TwichUIDB.ui = { brokerMenu = { bgOpacity = 999, bgColor = "nope", borderSize = "x", bgTexture = 7 } }
  assert(MS.Get("bgOpacity") == 100 and MS.Get("bgColor") == MS.DEFAULTS.bgColor and MS.Get("borderSize") == 1
    and MS.Get("bgTexture") == "solid", "bad saved values fall back to the defaults")
  c.TwichUIDB.ui = nil
end

-- Opacity: background and border are independent.
do
  assert(MS.Set("bgOpacity", 30))
  local f = Styled()
  assert(near(f.bgColor[4], 0.3) and near(f.edgeColor[4], 0.95), "background opacity leaves the border alone")
  assert(MS.Set("borderOpacity", 10))
  f = Styled()
  assert(near(f.bgColor[4], 0.3) and near(f.edgeColor[4], 0.1), "border opacity leaves the background alone")
  assert(near(f.twichBevel.top.color[4], 0.014) and near(f.twichBevel.bottom.color[4], 0.045), "the highlight and shade follow the border")
  assert(f.alphaSet == nil, "nothing fades the frame, so its text, icons and buttons stay solid")
  assert(MS.Set("bgOpacity", 0) and MS.Set("borderOpacity", 100))
  f = Styled()
  assert(f.bgColor[4] == 0 and f.edgeColor[4] == 1)
  assert(MS.Set("bgColor", "ff102030") and MS.Set("borderColor", "ffa0b0c0"))
  f = Styled()
  assert(near(f.bgColor[1], 0x10 / 255) and near(f.edgeColor[3], 0xc0 / 255), "colors apply to their own piece")
  assert(f.bgColor[4] == 0, "the swatch's alpha part is ignored")
  MS.Reset()
end

-- None: nothing drawn for that piece.
do
  assert(MS.Set("bgTexture", "none"))
  local f, edge = Styled()
  assert(f.backdrop.bgFile == nil and f.backdrop.edgeFile == WHITE and edge == 1, "no background, still a border")
  assert(MS.Set("borderTexture", "none"))
  f, edge = Styled()
  assert(f.backdrop.bgFile == nil and f.backdrop.edgeFile == nil and edge == 0, "neither: an empty backdrop")
  assert(not f.twichBevel.top.shown, "no line, no highlight")
  assert(MS.Set("bgTexture", "solid"))
  f, edge = Styled()
  assert(f.backdrop.bgFile == WHITE and f.backdrop.edgeFile == nil and edge == 0, "a background with no border")
  MS.Reset()
  assert(MS.Set("borderSize", 0))
  f, edge = Styled()
  assert(f.backdrop.edgeFile == nil and edge == 0 and f.backdrop.bgFile == WHITE, "thickness 0 is no border")
  MS.Reset()
end

-- Game textures, and a thickness that suits a textured border.
do
  assert(MS.Set("bgTexture", "Blizzard Dialog Background"))
  local f = Styled()
  assert(f.backdrop.bgFile == [[Interface\DialogFrame\UI-DialogBox-Background]] and f.backdrop.tile == true and f.backdrop.tileSize > 0)
  assert(MS.Set("borderTexture", "Blizzard Tooltip"))
  assert(MS.Get("borderSize") == 12, "a textured border is given room to read: " .. MS.Get("borderSize"))
  f = Styled()
  assert(f.backdrop.edgeFile == [[Interface\Tooltips\UI-Tooltip-Border]] and f.backdrop.edgeSize == 12)
  assert(f.backdrop.insets.left == 3, "the background stays off a rounded border's corners")
  assert(not f.twichBevel.top.shown, "the line's highlight is only for the plain line")
  assert(MS.Set("borderSize", 3) and MS.Set("borderTexture", "solid") and MS.Get("borderSize") == 3, "a thickness that suits a line is kept")
  assert(MS.Set("borderTexture", "Blizzard Dialog") and MS.Get("borderSize") == 12)
  assert(MS.Set("borderTexture", "solid") and MS.Get("borderSize") == 1, "back to a line, back to thin")
  assert(MS.Set("borderSize", 9) and MS.Set("borderTexture", "none") and MS.Get("borderSize") == 9, "None changes nothing else")
  MS.Reset()
end

-- Choices: None, Solid, the game's own, then LibSharedMedia's; never a list position.
do
  local function Ids(kind, current)
    local ids, labels = {}, {}
    for i, choice in ipairs(MS.Choices(kind, current)) do ids[i] = choice[1]; labels[choice[1]] = choice[2] end
    return ids, labels
  end
  local ids, labels = Ids("background", "solid")
  assert(ids[1] == "none" and ids[2] == "solid" and labels.solid == "Solid color" and labels.none == "None")
  assert(ids[3] == "Blizzard Tooltip" and ids[4] == "Blizzard Dialog Background", "the game's own come first, in order")
  local seen = {}
  for _, id in ipairs(ids) do assert(not seen[id], id .. " is listed once"); seen[id] = true end
  assert(not seen.None and not seen.Solid, "LibSharedMedia's None and Solid are ours already")
  assert(LSM:HashTable("background")["Blizzard Garrison Background"] and not seen["Blizzard Garrison Background"]
    and not seen["Blizzard Low Health"] and not seen["Blizzard Parchment"],
    "Blizzard textures from other versions of the game, which this client may lack, are not offered")
  ids, labels = Ids("border", "solid")
  assert(labels.solid == "Solid line" and ids[3] == "Blizzard Tooltip" and ids[5] == "Blizzard Dialog Gold")
  assert(not labels["Blizzard Achievement Wood"] and not labels["Blizzard Chat Bubble"])
end

-- Another addon's media, including registered after TwichUI is up.
do
  local changed = 0
  MS.Subscribe(function() changed = changed + 1 end)
  assert(LSM:Register("background", "Pack Slate", [[Interface\AddOns\Pack\slate]]))
  assert(LSM:Register("border", "Pack Edge", [[Interface\AddOns\Pack\edge]]))
  assert(changed == 0, "media nobody chose changes nothing")
  local function Has(kind, id) for _, ch in ipairs(MS.Choices(kind, "solid")) do if ch[1] == id then return true end end end
  assert(Has("background", "Pack Slate") and not Has("border", "Pack Slate") and Has("border", "Pack Edge"),
    "each kind lists its own")
  assert(MS.Set("bgTexture", "Pack Slate") and MS.Set("borderTexture", "Pack Edge"))
  local f = Styled()
  assert(f.backdrop.bgFile == [[Interface\AddOns\Pack\slate]] and f.backdrop.edgeFile == [[Interface\AddOns\Pack\edge]])
  -- a status bar texture is offered as a background (as EllesmereUI offers them), stretched; never as a border
  assert(LSM:Register("statusbar", "Pack Bar", [[Interface\AddOns\Pack\bar]]))
  assert(Has("background", "bar:Pack Bar") and not Has("border", "bar:Pack Bar") and not Has("border", "Pack Bar"))
  assert(MS.Set("bgTexture", "bar:Pack Bar"))
  f = Styled()
  assert(f.backdrop.bgFile == [[Interface\AddOns\Pack\bar]] and not f.backdrop.tile, "stretched, not repeated")
  assert(LSM:Register("statusbar", "play_icon", [[Interface\AddOns\Pack\play]]))
  assert(not Has("background", "bar:play_icon"), "an icon a pack calls a status bar isn't offered")
  assert(MS.Set("bgTexture", "bar:Gone Bar"))
  f = Styled()
  assert(f.backdrop.bgFile == WHITE and MS.BackgroundChoices()[#MS.BackgroundChoices()][2] == "Gone Bar (not available)")
  changed = 0
  assert(LSM:Register("statusbar", "Gone Bar", [[Interface\AddOns\Gone\bar]]))
  assert(changed == 1, "a status bar the look was waiting for redraws it")
  f = Styled()
  assert(f.backdrop.bgFile == [[Interface\AddOns\Gone\bar]])
  -- a saved choice whose pack arrives later
  changed = 0
  assert(MS.Set("bgTexture", "Late Pack Wood"))
  changed = 0
  local before = changed
  f = Styled()
  assert(f.backdrop.bgFile == WHITE, "an unavailable background is drawn as the flat color")
  assert(c.TwichUIDB.ui.brokerMenu.bgTexture == "Late Pack Wood", "the saved choice is kept")
  local listed = MS.BackgroundChoices()
  assert(listed[#listed][1] == "Late Pack Wood" and listed[#listed][2] == "Late Pack Wood (not available)", "and stays listed, marked")
  assert(MS.Resolve("background", "Late Pack Wood") == WHITE and select(2, MS.Resolve("background", "Late Pack Wood")) == "missing")
  assert(LSM:Register("background", "Late Pack Wood", [[Interface\AddOns\Late\wood]]))
  assert(changed == before + 1, "the menus are told when the awaited media arrives")
  f = Styled()
  assert(f.backdrop.bgFile == [[Interface\AddOns\Late\wood]], "and then it is used")
  -- a border whose pack is gone: the plain line
  assert(MS.Set("borderTexture", "Gone Edge"))
  f = Styled()
  assert(f.backdrop.edgeFile == WHITE, "an unavailable border is drawn as the plain line")
  -- an empty path is not a texture
  LSM:HashTable("border")["Empty Edge"] = ""
  assert(select(2, MS.Resolve("border", "Empty Edge")) == "missing")
  -- a global override for a whole kind doesn't replace the player's choice
  LSM:SetGlobal("background", "Pack Slate")
  assert(MS.Resolve("background", "Late Pack Wood") == [[Interface\AddOns\Late\wood]])
  LSM:SetGlobal("background", nil)
  MS.Reset()
end

-- EllesmereUI's own border textures (Pixels Textured and the rest): offered and drawn through its
-- API only while it is installed, for borders only; nothing is copied.
do
  local calls, fail = {}, false
  c.EllesmereUI = {
    PP = {},
    GetBorderTextureList = function()
      return { { key = "solid", name = "Solid" }, { key = "glow", name = "Glow" }, { key = "shadow", name = "Shadow" },
        { key = "pixels-textured", name = "Pixels Textured" }, { key = "dialog", name = "Blizzard Dialog" },
        { key = "sm:Test Edge", name = "Test Edge" } }
    end,
    ResolveBorderTexture = function(k) return ({ glow = "g", ["pixels-textured"] = "p", dialog = "d" })[k] end,
    BorderPxStep = function() return 2 end,
    BorderLegacyPx = function() return 12 end,
    GetBorderDefaultSize = function() return 2 end,
    GetBorderStyleSelectDefaults = function() return { r = 1, g = 1, b = 1 } end,
    ApplyBorderStyle = function(frame, step, r, g, b, a, key, ...)
      if fail then error("boom") end
      calls[#calls + 1] = { frame = frame, r = r, g = g, b = b, a = a, key = key, edge = select(8, ...) }
    end,
  }
  local labels, count = {}, {}
  for _, ch in ipairs(MS.Choices("border", "solid")) do labels[ch[1]] = ch[2]; count[ch[2]] = (count[ch[2]] or 0) + 1 end
  assert(labels["eui:pixels-textured"] == "Pixels Textured" and labels["eui:glow"] == "Glow", "EllesmereUI's borders are listed")
  assert(not labels["eui:shadow"] and not labels["eui:solid"] and not labels["eui:sm:Test Edge"])
  assert(count["Blizzard Dialog"] == 1, "a name already listed from the game isn't listed twice")
  for _, ch in ipairs(MS.Choices("background", "solid")) do assert(not ch[1]:find("^eui:"), "it has no backgrounds to offer") end

  assert(MS.Set("borderTexture", "eui:pixels-textured"))
  assert(MS.Get("borderSize") == 12 and MS.Get("borderColor") == "ffffffff", "seeded with a size and tint that suit it")
  assert(MS.Set("borderOpacity", 50))
  local f, edge = Styled()
  assert(#calls == 1 and calls[1].key == "pixels-textured" and calls[1].edge == 12, "drawn through EllesmereUI at the exact pixels")
  assert(calls[1].a == 0.5 and calls[1].r == 1, "its opacity and color reach it")
  assert(calls[1].frame ~= f and calls[1].frame.shown, "on a frame of ours")
  assert(f.backdrop.edgeFile == nil and f.backdrop.bgFile == WHITE and edge == 12, "the backdrop draws only the background")
  assert(near(f.bgColor[4], 1), "the border's opacity doesn't touch the background")
  assert(not f.twichBevel.top.shown)
  assert(MS.Set("borderSize", 0))
  local g = Styled()
  assert(#calls == 1 and g.twichBorders.ellesmere == nil and g.backdrop.edgeFile == nil, "no thickness, no border")
  assert(MS.Set("borderSize", 12))
  f = Styled()
  local euiFrame = calls[#calls].frame
  assert(euiFrame.shown)
  assert(MS.Set("borderTexture", "solid"))
  MS.Apply(f)
  assert(not euiFrame.shown and f.backdrop.edgeFile == WHITE, "back to a line: its frame is put away")
  fail = true
  assert(MS.Set("borderTexture", "eui:glow"))
  f = Styled()
  assert(f.backdrop.edgeFile == WHITE and f.twichBevel.top.shown, "a failure in EllesmereUI draws the plain line")
  fail = false
  c.EllesmereUI = nil
  f = Styled()
  assert(f.backdrop.edgeFile == WHITE, "EllesmereUI gone: the plain line")
  assert(MS.Get("borderTexture") == "eui:glow", "the choice is kept for when it comes back")
  local listed
  for _, ch in ipairs(MS.BorderChoices()) do if ch[1] == "eui:glow" then listed = ch[2] end end

-- The textures EllesmereUI offers for its own backgrounds (its chat, its bars): offered as backgrounds,
-- read through its own BuildBarTextureTables while it is installed, stretched as it draws them.
do
  local EUI_TEX = [[Interface\AddOns\EllesmereUI\media\textures\]]
  c.EllesmereUI = {
    BuildBarTextureTables = function()
      return { melli = EUI_TEX .. "melli.tga", glass = EUI_TEX .. "glass.tga", ["pixels-bg"] = EUI_TEX .. "pixels-bg.tga" },
        { none = "None", melli = "Melli (ElvUI)", glass = "Glass", ["pixels-bg"] = "Pixels Background" },
        { "none", "melli", "glass", "pixels-bg" }
    end,
  }
  assert(LSM:Register("statusbar", "Melli Copy", EUI_TEX .. "melli.tga"))   -- a pack registering the same file
  local ids, labels = {}, {}
  for i, ch in ipairs(MS.Choices("background", "solid")) do ids[i] = ch[1]; labels[ch[1]] = ch[2] end
  assert(ids[8] == "eui:melli" and ids[9] == "eui:glass" and ids[10] == "eui:pixels-bg", "after the game's own, in EllesmereUI's order: " .. tostring(ids[8]))
  assert(labels["eui:melli"] == "Melli (ElvUI)" and labels["eui:pixels-bg"] == "Pixels Background", "by EllesmereUI's names")
  assert(not labels["eui:none"], "its None is ours already")
  assert(not labels["bar:Melli Copy"], "the same file isn't offered twice")
  for _, ch in ipairs(MS.Choices("border", "solid")) do assert(not ch[1]:find("^eui:melli"), "a background isn't offered as a border") end
  assert(MS.Set("bgTexture", "eui:pixels-bg") and MS.Set("bgColor", "ffffffff"))
  local f = Styled()
  assert(f.backdrop.bgFile == EUI_TEX .. "pixels-bg.tga" and not f.backdrop.tile, "drawn stretched, as EllesmereUI draws it")
  assert(near(f.bgColor[1], 1) and near(f.bgColor[4], 1), "tinted by the color")
  c.EllesmereUI = nil
  f = Styled()
  assert(f.backdrop.bgFile == WHITE, "without EllesmereUI: the flat color")
  local listed = MS.BackgroundChoices()
  assert(listed[#listed][1] == "eui:pixels-bg" and listed[#listed][2] == "pixels-bg (not available)", "and the choice stays listed, marked")
  assert(c.TwichUIDB.ui.brokerMenu.bgTexture == "eui:pixels-bg", "and saved")
  MS.Reset()
end
  assert(listed == "glow (not available)", "and stays listed, marked: " .. tostring(listed))
  MS.Reset()
end

-- Reset: only this appearance.
do
  c.TwichUIDB.ui = { mageTravelText = "none", showAdvanced = true, foodDrink = { size = 50 } }
  assert(MS.Set("bgOpacity", 20) and MS.Set("borderTexture", "Blizzard Dialog"))
  MS.Reset()
  assert(c.TwichUIDB.ui.brokerMenu == nil and MS.Get("bgOpacity") == 100 and MS.Get("borderTexture") == "solid" and MS.Get("borderSize") == 1)
  assert(c.TwichUIDB.ui.mageTravelText == "none" and c.TwichUIDB.ui.showAdvanced == true and c.TwichUIDB.ui.foodDrink.size == 50,
    "nothing else is touched")
  c.TwichUIDB.ui = nil
end

-- Screen pixels: a border is a whole number of them at any UI scale.
do
  c.GetPhysicalScreenSize = function() return 1920, 1080 end
  local factor = 0.5   -- UI units per pixel for the frame being drawn, as PixelUtil would work it out
  c.PixelUtil = { ConvertPixelsToUIForRegion = function(pixels) return pixels * factor end }
  assert(MS.Set("borderSize", 4))
  local f, edge = Styled()
  assert(edge == 2 and f.backdrop.edgeSize == 2, "4 pixels is 2 units at this scale")
  factor = 1.25
  f, edge = Styled()
  assert(edge == 5 and f.backdrop.edgeSize == 5, "and 5 at another")
  assert(f.twichBevel.top.height == 1.25, "the hairline too")
  c.PixelUtil, c.GetPhysicalScreenSize = nil, nil
  MS.Reset()
end

---------------------------------------------------------------------------
-- A menu: it takes the look when it opens, follows changes while open, and keeps its content
-- clear of a thick border. Never touches anything in combat.
---------------------------------------------------------------------------
local spec = {
  key = "mageTravel", name = "Test", label = "Test Menu", menuName = "TestMenu", icon = 1, page = "mage",
  textKey = "testText", texts = { { "a", "A" } }, defaultText = "a", hint = "h", empty = "none",
  forPlayer = function() return true end,
  entries = function()
    return { { label = "Things", rows = { { id = 1, text = "One", known = true }, { id = 2, text = "Two", known = false, note = "Level 9" } } } }
  end,
  learnLines = function() end,
}
local L = SM.New(spec)
c.FireEvent("PLAYER_LOGIN")
local function Menu() for _, f in ipairs(frames) do if f.name == "TestMenu" then return f end end end
local function MenuRows(menu)
  local rows = {}
  for _, f in ipairs(frames) do
    if f.template == "SecureActionButtonTemplate" and f.parent == menu then rows[#rows + 1] = f end
  end
  return rows
end
local bar = { GetRect = function() return 100, 100, 60, 20 end, GetEffectiveScale = function() return 1 end,
  IsMouseOver = function() return false end }

assert(Menu() == nil, "no frame until the menu is first opened")
assert(L.Open(bar))
local menu = Menu()
assert(menu.template == "BackdropTemplate" and menu.backdrop.bgFile == WHITE and menu.backdropCalls == 1, "drawn as it opens")
assert(menu.alphaSet == nil)
local rows = MenuRows(menu)
assert(rows[1].points[1][4] == 8 and rows[1].points[1][5] == -(8 + 26 + 22), "the usual margin with the default line")
local top = rows[1].points[1][5]

-- changed while open: drawn again at once
assert(MS.Set("bgOpacity", 40))
assert(menu.backdropCalls == 2 and near(menu.bgColor[4], 0.4), "an open menu follows the change")
assert(menu.shown and rows[1].attrs.type == "spell" and rows[1].attrs.spell == 1, "and its secure rows are as they were")
-- a thick border moves the content in
c.PixelUtil = nil
assert(MS.Set("borderTexture", "Blizzard Dialog Gold") and MS.Get("borderSize") == 12)
assert(rows[1].points[1][4] == 12 and rows[1].points[1][5] == -(12 + 26 + 22), "content clears a 12 unit border: " .. rows[1].points[1][4])
assert(MS.Set("borderSize", 3))
assert(rows[1].points[1][4] == 8 and rows[1].points[1][5] == top, "a thin border keeps the usual margin")
-- the scale changing re-draws it, and only while it is open
local calls = menu.backdropCalls
c.FireEvent("UI_SCALE_CHANGED")
assert(menu.backdropCalls == calls + 1)
c.FireEvent("DISPLAY_SIZE_CHANGED")
assert(menu.backdropCalls == calls + 2)

-- combat: closing as it starts; a change then draws nothing, and the next opening has it
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not L.IsOpen())
c.COMBAT = true
calls = menu.backdropCalls
local point = rows[1].points[1]
assert(MS.Set("bgOpacity", 70) and MS.Set("borderSize", 16))
assert(menu.backdropCalls == calls and rows[1].points[1] == point, "nothing is drawn or moved in combat")
assert(not L.Open(bar), "and it doesn't open")
c.COMBAT = false
c.FireEvent("UI_SCALE_CHANGED")
assert(menu.backdropCalls == calls, "a closed menu isn't listening for the scale")
assert(L.Open(bar))
assert(near(menu.bgColor[4], 0.7) and menu.backdrop.edgeSize == 16 and rows[1].points[1][4] == 16, "drawn with the new look when opened")
L.Close()

-- the secure rows are never made or changed by styling
local secure = #MenuRows(menu)
MS.Set("bgTexture", "none")
assert(#MenuRows(menu) == secure and menu.backdrop.bgFile == nil)
MS.Reset()

-- the preview: a sample that does nothing, shown only on request
assert(not SM.PreviewShown())
local before = #frames
SM.TogglePreview()
local pv
for _, f in ipairs(frames) do if f.name == "TwichUIMenuPreview" then pv = f end end
assert(pv and SM.PreviewShown() and pv.shown, "shown when asked")
assert(pv.mouse == nil, "it takes no mouse")
for i = before, #frames do assert(frames[i].template ~= "SecureActionButtonTemplate", "nothing secure in the preview") end
assert(pv.backdrop.bgFile == WHITE)
MS.Set("bgTexture", "none")
assert(pv.backdrop.bgFile == nil, "it follows the settings")
MS.Set("borderTexture", "Blizzard Dialog Gold")
MS.Set("borderSize", 16)
assert(pv.height > 0, "sized to its content, margin included")
SM.TogglePreview()
assert(not SM.PreviewShown() and not pv.shown, "and put away")
local calls2 = pv.backdropCalls
MS.Set("bgOpacity", 10)
assert(pv.backdropCalls == calls2, "a hidden preview isn't redrawn")
MS.Reset()

print("PASSED")
