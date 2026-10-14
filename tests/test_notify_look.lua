dofile(TESTS .. "harness.lua")
-- Notification appearance (modules/NotifyLook.lua) through the real renderers: the zone arrival, new training,
-- friend login and Welcome Back cards, drawn by the coordinator from their own samples.
--   * the defaults are the look the cards had before this existed (fonts, sizes, colors, shadow, no backdrop);
--   * the shared look, a card's own look, inheritance, turning it off and on, and the two resets;
--   * validation, zero opacity, an unusable font, a missing font and the card's own face coming back;
--   * a change reaching a card that is up without replaying its entrance, coalesced, and nothing leaking into
--     the next card shown;
--   * previews: isolated from real state, silent, allowed when the feature is off, pinned, put away on a real
--     notice, combat, the settings closing and a profile change;
--   * reduced motion, text size and the room a card takes.
-- A recording frame stands in for the game's: it keeps what each FontString and texture was last given.
local c = MakeClient("Rich", {"!!!TwichUI"})

local groups, frames = {}, 0
local function Fake(o)
  o = o or {}
  o.shown, o.scripts, o.hooks, o.pts = false, {}, {}, {}
  return setmetatable(o, {__index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = fn end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetFont" then return function(s, path, size, flags)
      if c.BAD_FONTS and c.BAD_FONTS[path] then return false end
      s.font = { path = path, size = size, flags = flags }
      return true
    end end
    if k == "GetFont" then return function(s) return "Fonts\\FRIZQT__.TTF", 14, "" end end
    if k == "SetTextColor" then return function(s, r, g, b, a) s.color = { r, g, b, a } end end
    if k == "SetShadowColor" then return function(s, r, g, b, a) s.shadow = { r, g, b, a } end end
    if k == "SetShadowOffset" then return function() end end
    if k == "SetAlpha" then return function(s, a) s.alpha = a end end
    if k == "SetColorTexture" then return function(s, r, g, b, a) s.ctex = { r, g, b, a } end end
    if k == "SetWidth" then return function(s, w) s.width = w end end
    if k == "GetWidth" then return function(s) return s.width or 100 end end
    if k == "SetHeight" then return function(s, h) s.height = h end end
    if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
    if k == "SetPoint" then return function(s, ...) s.pts[#s.pts + 1] = { ... } end end
    if k == "ClearAllPoints" then return function(s) s.pts = {} end end
    if k == "GetStringWidth" or k == "GetUnboundedStringWidth" then
      return function(s) return #(s.text or "") * 8 * ((s.font and s.font.size or 15) / 15) end
    end
    if k == "SetFrameStrata" then return function(s, v) s.strata = v end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    if k == "CreateAnimationGroup" then return function(s)
      local g = Fake({ owner = s, plays = 0, anims = {} })
      g.Play = function(self) self.playing = true; self.plays = self.plays + 1 end
      g.Stop = function(self) self.playing = false end
      g.CreateAnimation = function(self, kind)
        local a = Fake({ kind = kind })
        a.SetOffset = function(x, ox, oy) x.ox, x.oy = ox, oy end
        a.SetStartDelay = function(x, d) x.delay = d end
        a.SetDuration = function(x, d) x.duration = d end
        self.anims[#self.anims + 1] = a
        return a
      end
      groups[#groups + 1] = g
      return g
    end end
    return function() end
  end})
end
c.CreateFrame = function() frames = frames + 1; return Fake() end
c.UIParent = Fake()
c.UIParent.GetWidth = function() return 1024 end
c.UIParent.GetHeight = function() return 768 end
c.EventRegistry = { RegisterCallback = function() end, UnregisterCallback = function() end }
c.EditModeManagerFrame = { IsEditModeActive = function() return false end }
c.NOW = 1700000000
c.time = function() return c.NOW end
c.GetTime = function() return c.NOW end
c.COMBAT = false
c.InCombatLockdown = function() return c.COMBAT end
c.UnitFactionGroup = function() return "Alliance" end
c.UnitOnTaxi = function() return false end
c.EventToastManagerFrame = Fake()
c.EventToastManagerFrame.IsCurrentlyToasting = function() return false end
c.sounds = 0
c.PlaySoundFile = function() c.sounds = c.sounds + 1; return true end
c.PlaySound = function() c.sounds = c.sounds + 1; return true end
c.C_Texture = { GetAtlasInfo = function() return nil end }

for _, f in ipairs({ "chronicle/Style.lua", "modules/Notify.lua", "modules/NotifyLook.lua", "modules/Arrival.lua",
  "modules/WelcomeBack.lua", "modules/Training.lua", "modules/FriendLogin.lua", "modules/Borders.lua", "modules/MenuStyle.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local R = c.TwichUI
local N, NL, A = R.Notify, R.NotifyLook, R.Arrival
local K = R.ChronicleStyle.color
assert(NL and NL.Look, "the look is loaded")
c.TwichUIDB.ui = c.TwichUIDB.ui or {}   -- the settings window makes it when it opens; nothing else here does

local function Eq(a, b) return math.abs(a - b) < 1e-9 end
local function Color(fs, r, g, b, a, msg)
  assert(fs.color, msg .. ": has a color")
  assert(Eq(fs.color[1], r) and Eq(fs.color[2], g) and Eq(fs.color[3], b), msg .. (": %.3f %.3f %.3f"):format(fs.color[1], fs.color[2], fs.color[3]))
  assert(Eq(fs.color[4] or 1, a or 1), msg .. ": alpha")
end
local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function Deep(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = Deep(x) end
  return o
end
local function Same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- The cards' frames, found through the previews they are shown for.
local function Show(kind, extra)
  N.ClearPreviews()
  local ok, why = N.Preview(kind, nil, extra)
  assert(ok, kind .. " preview accepted: " .. tostring(why))
  return ok
end
local function CardOf(field)
  for _, g in ipairs(groups) do
    if rawget(g.owner, field) ~= nil then return g.owner, g end
  end
end

---------------------------------------------------------------------------
-- 1. The defaults are the look the cards have always had
---------------------------------------------------------------------------
Show("arrival")
local arrival, ag = CardOf("sub")
assert(arrival and arrival.shown and ag.playing, "the zone card is up")
assert(arrival.title.font.path == A.FONT_TITLE and arrival.title.font.size == 30 and arrival.title.font.flags == nil, "zone title: Cinzel 30, plain")
Color(arrival.title, K.text[1], K.text[2], K.text[3], 1, "zone title color")
assert(arrival.sub.font.path == A.FONT_LINE and arrival.sub.font.size == 17, "zone's smaller place: Alegreya 17")
Color(arrival.sub, K.stone[1], K.stone[2], K.stone[3], 1, "smaller place color")
assert(arrival.title.shadow[4] == 0.85 and arrival.sub.shadow[4] == 0.85, "the soft shadow")
assert(arrival.title.alpha == 1 and arrival.sub.alpha == 1, "text fully solid")
assert(arrival.width == 600 and arrival.height == 120, "the card is 600 by 120")
local rule = arrival.rule
assert(rule.alpha == 1, "rule at full strength")
for _, part in ipairs(rule.parts) do
  local want = part.tone == "mark" and K.gold or (part.tone == "shadow" and K.bronzeLo or K.bronze)
  assert(Eq(part.texture.ctex[1], want[1]) and Eq(part.texture.ctex[2], want[2]) and Eq(part.texture.ctex[3], want[3]), "rule parts keep their bronze and gold")
  assert(Eq(part.texture.ctex[4], part.alpha), "rule parts keep their strength")
end
assert(Count(NL.Snapshot().own) == 0 and NL.Snapshot().shared.backdrop == false, "nothing of the player's is saved")
assert(c.TwichUIDB.ui.notifyLook == nil, "no table is written until something is changed")

local l, b, r, t = A.Bounds()
assert(Eq(r - l, 600) and Eq(t - b, 120), "bounds are the card's own size")

Show("training")
local training, tg = CardOf("rowFrames")
assert(training.title.font.size == 18 and training.title.font.path == A.FONT_TITLE, "training title: Cinzel 18")
assert(training.foot.font.size == 13 and training.foot.font.path == A.FONT_LINE, "training line: Alegreya 13")
local row1 = training.rowFrames[1]
assert(row1.text.font.size == 15 and row1.text.font.path:find("AlegreyaSans%-Bold"), "spell lines: Alegreya Sans Bold 15")
Color(row1.text, K.text[1], K.text[2], K.text[3], 1, "spell color")
assert(row1.text.text:find("|cff", 1, true), "rank in its own tone")
assert(row1.text.text:find(("|cff%02x%02x%02x"):format(K.stone[1] * 255, K.stone[2] * 255, K.stone[3] * 255), 1, true), "rank tone is the stone color")
assert(training.rowFrames[1].height == 20 and training.width == 520, "rows 20, card 520 wide")

Show("friend")
local friend = CardOf("sub") and (function()
  for _, g in ipairs(groups) do if rawget(g.owner, "flow") ~= nil then return g.owner end end
end)()
assert(friend and friend.title.font.size == 20 and friend.sub.font.size == 15, "friend card: 20 and 15")
Color(friend.sub, K.stone[1], K.stone[2], K.stone[3], 1, "friend sub color")
assert(friend.width == 360 and friend.height == 64, "friend card 360 by 64")

Show("welcome")
local welcome
for _, g in ipairs(groups) do if rawget(g.owner, "open") ~= nil then welcome = g.owner end end
assert(welcome and welcome.title.font.size == 18 and welcome.line.font.size == 15 and welcome.more.font.size == 13, "Welcome Back: 18, 15, 13")
assert(welcome.width == 520 and welcome.height == 96, "welcome card 520 by 96")
N.ClearPreviews()

---------------------------------------------------------------------------
-- 2. Validation, and what the shared look changes
---------------------------------------------------------------------------
assert(NL.Set("shared", "textScale", 200) == false and NL.Set("shared", "textScale", 70) == false, "size bounds")
assert(NL.Set("shared", "textScale", 110.5) == false, "whole numbers only")
assert(NL.Set("shared", "titleColor", "red") == false and NL.Set("shared", "titleColor", "ff12345") == false, "colors are AARRGGBB")
assert(NL.Set("shared", "outline", "glow") == false, "outline is one of the known")
assert(NL.Set("shared", "titleFont", "a|b") == false and NL.Set("shared", "titleFont", "") == false, "a font name is plain text")
assert(NL.Set("shared", "nonsense", 1) == false and NL.Set("shared", "own", true) == false, "unknown keys and `own` are refused")
assert(NL.Set("shared", "textOpacity", 29) == false and NL.Set("shared", "textOpacity", 101) == false, "text opacity 30 to 100")
assert(c.TwichUIDB.ui.notifyLook == nil, "a refused value writes nothing")
assert(NL.Set("shared", "bgOpacity", 0) and NL.Set("shared", "accentOpacity", 0), "zero opacity is a value")
assert(c.TwichUIDB.ui.notifyLook.bgOpacity == 0 and c.TwichUIDB.ui.notifyLook.accentOpacity == 0, "and it is kept as 0, not dropped")
assert(NL.Get("arrival", "accentOpacity") == 0, "and read back as 0, not the default")
NL.ResetShared()
assert(c.TwichUIDB.ui.notifyLook == nil, "reset forgets the shared look")

-- a damaged saved value is read as its default and left where it is
c.TwichUIDB.ui.notifyLook = { textScale = "big", bgOpacity = -4, titleColor = 12, outline = {} }
assert(NL.Get("arrival", "textScale") == 100 and NL.Get("arrival", "bgOpacity") == 0 and NL.Get("arrival", "outline") == "shadow", "damaged values read as defaults")
assert(c.TwichUIDB.ui.notifyLook.textScale == "big", "and are not erased")
c.TwichUIDB.ui.notifyLook = nil

-- the shared look reaches every card as it is shown
assert(NL.Set("shared", "textScale", 120))
assert(NL.Set("shared", "outline", "outline"))
assert(NL.Set("shared", "titleColor", "ff102030"))
assert(NL.Set("shared", "detailColor", "ff405060"))
assert(NL.Set("shared", "textOpacity", 60))
Show("arrival")
assert(arrival.title.font.size == 36 and arrival.title.font.flags == "OUTLINE", "title 30 at 120% with an outline")
assert(arrival.sub.font.size == 20 and arrival.sub.font.flags == "OUTLINE", "17 at 120% is 20")
assert(arrival.title.shadow[4] == 0, "an outline replaces the shadow")
Color(arrival.title, 0x10 / 255, 0x20 / 255, 0x30 / 255, 1, "title color follows")
Color(arrival.sub, 0x40 / 255, 0x50 / 255, 0x60 / 255, 1, "detail color follows")
assert(arrival.title.alpha == 0.6 and arrival.sub.alpha == 0.6, "text opacity applies to the text")
assert(arrival.rule.alpha == 1 and NL.BackdropOf(arrival) == nil, "and not to the rule or any backdrop")
assert(arrival.height == 144, "the card makes room for larger text: 120 * 1.2")
local _, bb, _, tt = A.Bounds()
assert(Eq(tt - bb, 144), "and the coordinator is told")
-- the territory line keeps what its color means
Show("arrival", { pvpText = "Contested", pvpType = "contested" })
Color(arrival.pvp, 0.79, 0.64, 0.29, 0.9, "territory tint is kept")

-- a smaller place keeps being quieter than a zone's title
N.ClearPreviews()
NL.ResetShared()
NL.Set("shared", "titleColor", "ff808080")
N.Preview("arrival", nil, { kind = "subzone" })
local dim = arrival.title.color
assert(dim[1] < 0.5 + 1e-9 and dim[1] > 0.5 * 0.78 / 0.93 - 1e-9 and Eq(dim[1], 0.5019607843137255 * K.textDim[1] / K.text[1]), "the smaller place's card is a shade under the chosen title color")
N.ClearPreviews()
NL.ResetShared()

---------------------------------------------------------------------------
-- 3. A card's own look
---------------------------------------------------------------------------
NL.Set("shared", "textScale", 110)
NL.Set("shared", "titleColor", "ffaa0000")
assert(NL.Set("training", "titleColor", "ff00aa00") == false, "a card that follows the shared look takes no value of its own")
assert(NL.Own("training") == false and NL.Get("training", "textScale") == 110, "it follows the shared look")
assert(NL.SetOwn("training", true) and NL.Own("training"), "turned on")
local saved = c.TwichUIDB.ui.notifyLookTraining
assert(saved.own == true and saved.textScale == 110 and saved.titleColor == "ffaa0000", "it starts as a copy of what it was drawn with")
assert(saved.bodyColor and saved.detailColor and saved.accentColor and saved.bgOpacity == 0 and saved.padding == 10, "complete")
assert(NL.Set("training", "titleColor", "ff00aa00") and NL.Set("training", "textScale", 90))
assert(NL.Get("training", "titleColor") == "ff00aa00" and NL.Get("arrival", "titleColor") == "ffaa0000", "only that card changed")
NL.Set("shared", "titleColor", "ff0000aa")
assert(NL.Get("training", "titleColor") == "ff00aa00", "later shared changes don't reach a card with its own look")
assert(NL.Applies("arrival", "bodyColor") == false and NL.Applies("friend", "bodyColor") == false and NL.Applies("training", "bodyColor"), "the cards with no main text have no color for it")
NL.SetOwn("arrival", true)
assert(NL.Set("arrival", "bodyColor", "ff123456") == false, "and a value for it is refused")
NL.SetOwn("arrival", false)
Show("training")
assert(training.title.font.size == 16 and training.rowFrames[1].text.font.size == 14, "90%: 18 is 16, 15 is 14")
Color(training.title, 0, 0xaa / 255, 0, 1, "its own title color")
-- turning it off keeps the values and goes back to the shared look; on again restores them
assert(NL.SetOwn("training", false) and NL.Own("training") == false)
assert(NL.Get("training", "titleColor") == "ff0000aa" and NL.Get("training", "textScale") == 110, "follows the shared look again")
assert(c.TwichUIDB.ui.notifyLookTraining.titleColor == "ff00aa00", "its values are kept")
Show("training")
assert(training.title.font.size == 20, "18 at 110% - and nothing left over from the card's own look: " .. tostring(training.title.font.size))
NL.SetOwn("training", true)
assert(NL.Get("training", "titleColor") == "ff00aa00" and NL.Get("training", "textScale") == 90, "turned on again, it is as it was")
-- resets are scoped
NL.SetOwn("friend", true)
NL.Set("friend", "textScale", 130)
NL.ResetCard("training")
assert(c.TwichUIDB.ui.notifyLookTraining == nil and NL.Own("training") == false, "the card forgets its own look")
assert(NL.Own("friend") and NL.Get("friend", "textScale") == 130, "another card is left alone")
assert(c.TwichUIDB.ui.notifyLook.textScale == 110, "so is the shared look")
NL.ResetShared()
assert(c.TwichUIDB.ui.notifyLook == nil and NL.Get("friend", "textScale") == 130, "resetting the shared look leaves a card's own")
NL.ResetCard("friend")
assert(NL.SetOwn("nope", true) == false and NL.SetScope("nope") == false and NL.SetScope("friend") and NL.Scope() == "friend", "unknown scopes are refused")
NL.SetScope("shared")
assert(c.TwichUIDB.modules.arrival == true and c.TwichUIDB.modules.trainingNotice == true, "no reset changed whether a card is on")

---------------------------------------------------------------------------
-- 4. Fonts
---------------------------------------------------------------------------
local LSM = c.LibStub("LibSharedMedia-3.0")
LSM:Register("font", "Test Face", "Interface\\AddOns\\Test\\Face.ttf")
LSM:Register("font", "Broken Face", "Interface\\AddOns\\Test\\Broken.ttf")
c.BAD_FONTS = { ["Interface\\AddOns\\Test\\Broken.ttf"] = true }
assert(NL.Set("shared", "titleFont", "Test Face") and NL.Set("shared", "textFont", "Gone Face"))
Show("arrival")
assert(arrival.title.font.path == "Interface\\AddOns\\Test\\Face.ttf" and arrival.title.font.size == 30, "a chosen font is used")
assert(arrival.sub.font.path == A.FONT_LINE, "a font that isn't there is drawn as the card's own")
assert(NL.Get("arrival", "textFont") == "Gone Face", "and the choice stays")
local snap = NL.Snapshot()
assert(snap.fallbackFonts[1] == "Gone Face" and #snap.fallbackFonts == 1, "the report lists it")
NL.Set("shared", "titleFont", "Broken Face")
Show("arrival")
assert(arrival.title.font.path == A.FONT_TITLE, "a font the game can't draw is drawn as the card's own")
NL.Set("shared", "titleFont", "default")
NL.Set("shared", "textFont", "default")
Show("arrival")
assert(arrival.title.font.path == A.FONT_TITLE and #NL.Snapshot().fallbackFonts == 0, "back to the card's own, nothing left over")
c.BAD_FONTS = nil
-- with the game's own fallback for scripts the bundled fonts lack, the card's own choice is unchanged
NL.ResetShared()

---------------------------------------------------------------------------
-- 5. Backdrop and accent
---------------------------------------------------------------------------
NL.Set("shared", "bgOpacity", 40)
NL.Set("shared", "bgColor", "ff102030")
NL.Set("shared", "padding", 14)
NL.Set("shared", "accentColor", "ff336699")
NL.Set("shared", "accentOpacity", 50)
NL.Set("shared", "textOpacity", 80)
Show("arrival")
local bg = NL.BackdropOf(arrival)
assert(bg and bg.shown, "the backdrop is there")
assert(Eq(bg.ctex[1], 0x10 / 255) and Eq(bg.ctex[2], 0x20 / 255) and Eq(bg.ctex[3], 0x30 / 255) and Eq(bg.ctex[4], 0.4), "its color, at its own opacity")
assert(bg.width and bg.width > 28, "sized to the text and its padding of 14 each side: " .. tostring(bg.width))
assert(bg.pts[1][1] == "TOP" and bg.pts[1][2] == arrival.title and bg.pts[1][5] == 14, "anchored above the heading by the padding")
assert(bg.pts[2][1] == "BOTTOM" and bg.pts[2][5] == -14, "and below the last line")
local texts = { arrival.title, arrival.sub }
assert(texts[1].alpha == 0.8, "text opacity is the text's own")
assert(arrival.rule.alpha == 0.5, "accent opacity fades the rule")
for _, part in ipairs(arrival.rule.parts) do
  if part.tone == "line" then
    assert(Eq(part.texture.ctex[1], 0x33 / 255) and Eq(part.texture.ctex[3], 0x99 / 255), "the rule takes the accent color")
  elseif part.tone == "mark" then
    assert(part.texture.ctex[1] > K.gold[1] * (0x33 / 255) / K.bronze[1] - 1e-9 or part.texture.ctex[1] == 1, "the mark follows it, brighter")
  end
end
N.ClearPreviews()
NL.ResetShared()

---------------------------------------------------------------------------
-- 6. A change reaches a card that is up, once, without replaying it
---------------------------------------------------------------------------
Show("arrival", { pinned = true })
local plays = ag.plays
assert(ag.anims[#ag.anims].delay == N.PIN_SECONDS, "a pinned preview holds for the pin time, not the card's own")
local fadeIn = ag.anims
for _ = 1, 5 do NL.Set("shared", "textScale", 100 + (NL.Get("arrival", "textScale") - 99)) end
assert(NL.Get("arrival", "textScale") == 105, "five changes")
local passes = NL.Snapshot().passes
assert(arrival.title.font.size == 30, "nothing is drawn until the short pass")
FlushTimers()
assert(arrival.title.font.size == 32 and NL.Snapshot().passes == passes + 1, "one pass drew the card for all five")
assert(ag.plays == plays and ag.playing, "its entrance was not replayed")
assert(NL.Snapshot().coalesced == 4 or NL.Snapshot().coalesced >= 4, "the others were folded in")
NL.Set("shared", "titleColor", "ff00ff00"); FlushTimers()
Color(arrival.title, 0, 1, 0, 1, "a color change reaches it too")
assert(ag.plays == plays, "still the same entrance")
-- a card that is not up is untouched, and is drawn right when it is shown
local before = Deep(training.title.font)
NL.Set("shared", "textScale", 120); FlushTimers()
assert(Same(training.title.font, before), "a card that is not showing was not touched")
Show("training")
assert(training.title.font.size == 22, "and is drawn with the look when it is shown")
Color(training.title, 0, 1, 0, 1, "with the new color")
-- no stale values on the next card: back to the defaults
NL.ResetShared(); FlushTimers()
Show("training")
assert(training.title.font.size == 18 and training.title.font.flags == nil, "the pooled card was restyled, nothing leaked")
Color(training.title, K.text[1], K.text[2], K.text[3], 1, "default title color again")

---------------------------------------------------------------------------
-- 7. Previews are isolated, silent and allowed with the feature off
---------------------------------------------------------------------------
N.ClearPreviews()
local M = c.TwichUIDB.modules
M.arrival, M.friendLogin, M.trainingNotice, M.welcomeBack = false, false, false, false
local db = Deep(c.TwichUIDB)
c.sounds = 0
local frameCount = frames
for _, kind in ipairs(NL.KINDS) do
  local ok = NL.Pin(kind)
  assert(ok, kind .. " pinned with its feature off")
end
local state = N.State()
assert(#state.active + #state.waiting == 4, "all four are accepted (those sharing the top of the screen take turns)")
assert(NL.Pinned("arrival") and NL.Pinned("friend"), "and they say so")
assert(Same(c.TwichUIDB, db), "previews wrote nothing anywhere in the saved data")
assert(M.arrival == false and M.friendLogin == false, "and turned nothing on")
assert(c.sounds == 0, "previews are silent")
local counts = N.Snapshot()
assert(counts.shown["arrival preview"] and not counts.shown.arrival, "counted as previews, not real notices")
N.ClearPreviews()
assert(not NL.Pinned("arrival") and #N.State().active == 0 and #N.State().waiting == 0, "cleared")
M.arrival, M.friendLogin, M.trainingNotice, M.welcomeBack = true, true, true, true

-- the chime plays only when previews are allowed sound, as before
N.SetPreviewSounds(true)
NL.Pin("friend")
assert(c.sounds == 1, "the chime with its preview when previews may make sound")
N.SetPreviewSounds(false)
N.ClearPreviews()

-- a second Show starts over: one preview per card, nothing accumulates
for _ = 1, 4 do NL.Pin("arrival") end
local n = 0
for _, k in ipairs(N.State().active) do if k:find("^arrival") then n = n + 1 end end
for _, k in ipairs(N.State().waiting) do if k:find("^arrival") then n = n + 1 end end
assert(n == 1, "pinning again starts over rather than stacking: " .. n)
local made = frames
for _ = 1, 5 do NL.Pin("arrival") end
assert(frames == made, "the card's frames are reused")
NL.Unpin("arrival")
assert(not NL.Pinned("arrival"), "hidden by its own button")

-- a real notice comes first
NL.Pin("arrival")
assert(NL.Pinned("arrival"))
assert(N.Submit({ kind = "arrival", id = "zone:Real Place", replace = true, payload = { kind = "zone", title = "Real Place" } }))
assert(arrival.title.text == "Real Place", "the real card took its place")
assert(not N.State().active[1]:find("preview"), "and it is the real one that is showing")
assert(not NL.Pinned("arrival"), "the preview is gone")
N.Cancel("arrival")

-- combat, the settings closing and a profile change put previews away
NL.Pin("training")
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not NL.Pinned("training"), "combat puts it away")
c.COMBAT = false
NL.Pin("training"); NL.Pin("friend")
R.SettingsLauncher.Closed()
assert(not NL.Pinned("training") and not NL.Pinned("friend"), "closing the settings puts previews away")
NL.Pin("friend")
R.Profiles.Refresh("refresh")
assert(not NL.Pinned("friend"), "a profile change puts them away")

-- a waiting redraw is dropped when settings close (nothing runs after)
NL.Set("shared", "textScale", 130)
R.SettingsLauncher.Closed()
FlushTimers()
assert(NL.Snapshot().waiting == false, "no redraw waits after the settings closed")
NL.ResetShared()

---------------------------------------------------------------------------
-- 7b. Profiles: each has its own look; changing profile redraws and puts previews away
---------------------------------------------------------------------------
do
  NL.Set("shared", "textScale", 125)
  NL.SetOwn("welcome", true)
  NL.Set("welcome", "titleColor", "ff778899")
  local first = R.Profiles.Current()
  Show("arrival", { pinned = true })
  assert(NL.Pinned("arrival"))
  local ok = R.Profiles.Create("Plain")
  assert(ok, "a new profile")
  assert(not NL.Pinned("arrival"), "the preview was put away by the change")
  assert(NL.Get("arrival", "textScale") == 100 and not NL.Own("welcome"), "the new profile has the default look")
  assert(c.TwichUIDB.ui.notifyLook == nil and c.TwichUIDB.ui.notifyLookWelcome == nil, "and none of the other's tables")
  NL.Set("shared", "textScale", 90)
  assert(R.Profiles.Switch(first))
  assert(NL.Get("arrival", "textScale") == 125 and NL.Own("welcome") and NL.Get("welcome", "titleColor") == "ff778899",
    "switching back brings the first profile's look, own look included")
  assert(R.Profiles.Switch("Plain") and NL.Get("arrival", "textScale") == 90, "and the second's")
  -- a card that is up is drawn for the new profile (the redraw is requested, then run)
  Show("arrival")
  assert(arrival.title.font.size == 27, "90% of 30")
  R.Profiles.Switch(first)
  FlushTimers()
  assert(NL.Get("arrival", "textScale") == 125, "back")
  Show("arrival")
  assert(arrival.title.font.size == 38, "125% of 30 is 37.5, drawn as 38")
  N.ClearPreviews()
  NL.ResetShared(); NL.ResetCard("welcome")
end

---------------------------------------------------------------------------
-- 8. Reduced motion, and the room larger text takes
---------------------------------------------------------------------------
M.arrivalReducedMotion = true
NL.Pin("arrival")
local moves = {}
for _, a in ipairs(ag.anims) do if a.kind == "Translation" then moves[#moves + 1] = a end end
assert(moves[1].oy == 0 and moves[2].oy == 0, "reduced motion: a pinned preview only fades")
M.arrivalReducedMotion = false
N.ClearPreviews()

NL.Set("shared", "textScale", 140)
local lt, bt, rt, tt2 = R.Training.Bounds(3)
assert(Eq(rt - lt, 728) and (tt2 - bt) > 64 + 3 * 20, "training bounds grow with the text: " .. (rt - lt))
local fl, fb, fr, ft = R.FriendLogin.Bounds()
assert(Eq(fr - fl, 504 + 28) and Eq(ft - fb, 90), "friend bounds grow: " .. (fr - fl) .. " x " .. (ft - fb))
NL.Set("shared", "textScale", 80)
local sl, sb, sr, st = R.Training.Bounds(3)
assert(Eq(sr - sl, 520), "smaller text never makes a card smaller than it was")
NL.ResetShared()
local dl, db2, dr, dt = R.Training.Bounds(3)
assert(Eq(dr - dl, 520) and Eq(dt - db2, 64 + 60), "default bounds are the original")

-- the game's UI scale changes the screen's size in units: bounds follow it, not a stored number
c.UIParent.GetWidth = function() return 1280 end
local ul, _, ur = A.Bounds()
assert(Eq(ul, 340) and Eq(ur, 940), "centered on the screen at another scale")
c.UIParent.GetWidth = function() return 1024 end

---------------------------------------------------------------------------
-- 9. Cards with no look module (it failed to load) still draw as they always did
---------------------------------------------------------------------------
do
  local saved = R.NotifyLook
  R.NotifyLook = nil
  Show("arrival")
  assert(arrival.title.font.size == 30 and arrival.title.font.path == A.FONT_TITLE, "the card's own font and size")
  Color(arrival.title, K.text[1], K.text[2], K.text[3], 1, "the card's own color")
  Show("welcome")
  Show("training")
  Show("friend")
  R.NotifyLook = saved
  N.ClearPreviews()
end

-- the diagnostics read the state without writing it
local snapshot = NL.Snapshot()
assert(type(snapshot.shared.textScale) == "number" and snapshot.scope == "shared")

print("PASSED")
