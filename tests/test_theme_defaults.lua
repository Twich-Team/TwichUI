dofile(TESTS .. "harness.lua")
-- The framed look's colors as DEFAULTS (FrameLook.lua), adopted by the panels and the notification cards, and what that must not touch.
--   * a look whose values are missing inherits the new defaults; a partly saved one keeps what it saved and inherits the rest; a fully
--     saved one is read and drawn exactly as it was; a saved value equal to the OLD default is still the player's choice (no comparison,
--     no migration, nothing rewritten);
--   * valid false and zero values, and a notification card's complete own copy, survive; Reset puts back the new defaults;
--   * nothing is saved by reading, and the saved tables a test hands in come out as they went in;
--   * choosing a border texture derives a thickness and color only where the player has not set them, from the look's own defaults;
--   * the frame is a border choice of the adopted looks and nobody else's: the data bar menus, the Chronicle, the class, healer and
--     RestedXP and SpeakStone looks keep every default they had.
-- Synthetic: it proves what is read, resolved and saved, not how any of it is drawn (the simulator screenshots and the client do that).
local c = MakeClient("Rich", {"!!!TwichUI"})
local function Any() return setmetatable({}, { __index = function(t, k)
  if k == "CreateTexture" or k == "CreateFontString" then return Any end
  if type(k) == "string" and k:match("^%u") then return function() end end   -- a method; a field a frame does not have is nil
end }) end
c.CreateFrame = Any
c.UIParent = Any()
c.UnitClass = function() return "Warrior", "WARRIOR", 1 end   -- not a Mage: the Mage features stay off
c.EventRegistry = { RegisterCallback = function() end, UnregisterCallback = function() end }

for _, f in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Notify.lua",
  "modules/NotifyLook.lua", "modules/Interact.lua", "modules/SpellMenu.lua", "modules/TrainingData.lua", "modules/MageConjure.lua", "modules/FoodDrink.lua",
  "modules/Refreshments.lua", "modules/RefreshmentsPanel.lua", "modules/Restock.lua", "modules/RestockPrompt.lua", "pins/Pins.lua", "pins/Sync.lua",
  "pins/Look.lua", "nav/Prefs.lua", "chronicle/Appearance.lua", "classbars/Config.lua", "healer/Config.lua", "markers/Markers.lua", "markers/Bar.lua",
  "modules/RestedXPSkin.lua", "modules/RestedXPTimers.lua", "modules/SpeakStoneSkin.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local R = c.TwichUI
local F, NL, K = R.FrameLook, R.NotifyLook, R.ChronicleStyle.color

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local function Near(a, b) return math.abs(a - b) < 1e-9 end
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
local function Hex(c3) return ("ff%02x%02x%02x"):format(math.floor(c3[1] * 255 + 0.5), math.floor(c3[2] * 255 + 0.5), math.floor(c3[3] * 255 + 0.5)) end
local function Rgb(h) return { tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, tonumber(h:sub(7, 8), 16) / 255 } end
local function Ui() c.TwichUIDB.ui = c.TwichUIDB.ui or {}; return c.TwichUIDB.ui end
-- The notification look is worked out once per change; a load with the table already saved starts from a clean cache. (Another addon
-- appearing is one of the things that makes it work its colors out again, and it reads nothing but what is saved.)
local function Fresh() c.FireEvent("ADDON_LOADED", "EllesmereUI") end

---------------------------------------------------------------------------
-- 1. The constants: the framed look's own numbers, to the nearest byte
---------------------------------------------------------------------------
local ST = F.Style()
Check(F.PANEL_BG == Hex(ST.interior) and F.PANEL_BORDER == Hex(ST.bronzeHi), "the panel espresso and bronze are the frame's interior and aged bronze: " .. F.PANEL_BG .. " " .. F.PANEL_BORDER)

---------------------------------------------------------------------------
-- 2. Notification cards: lazy defaults, saved colors drawn as they always were
---------------------------------------------------------------------------
local OLD = { title = K.text, body = K.text, detail = K.stone, accent = K.bronze, bg = K.bg }
local NEW = { title = ST.primary.text, body = ST.quiet.text, detail = { 0.72, 0.67, 0.58 }, accent = ST.bronzeHi, bg = ST.interior }
local ROLEKEY = { title = "titleColor", body = "bodyColor", detail = "detailColor" }
local function Drawn(kind, role, base) return NL.Color(kind, role, base) end
local function IsColor(got, want, msg) Check(Near(got[1], want[1]) and Near(got[2], want[2]) and Near(got[3], want[3]), msg .. (": %.4f %.4f %.4f"):format(got[1], got[2], got[3])) end
-- what a saved color has always drawn: the card's tone, scaled by how far the color is from the old role color
local function Legacy(base, hex, ref) local c3 = Rgb(hex); local o = {} for i = 1, 3 do o[i] = math.min(1, base[i] * (ref[i] > 0 and c3[i] / ref[i] or 1)) end return o end

do
  -- empty: nothing saved, the new defaults, and reading writes nothing
  Check(Ui().notifyLook == nil, "a clean profile has no notification look saved")
  Check(NL.DEFAULTS.titleColor == Hex(NEW.title) and NL.DEFAULTS.bodyColor == Hex(NEW.body) and NL.DEFAULTS.detailColor == Hex(NEW.detail)
    and NL.DEFAULTS.accentColor == Hex(NEW.accent) and NL.DEFAULTS.bgColor == Hex(NEW.bg), "the defaults are ivory, a quiet detail, aged bronze and espresso")
  Check(NL.DEFAULTS.bgOpacity == 0 and NL.DEFAULTS.textScale == 100 and NL.DEFAULTS.outline == "shadow" and NL.DEFAULTS.padding == 10
    and NL.DEFAULTS.textOpacity == 100 and NL.DEFAULTS.accentOpacity == 100, "everything else the cards have is as it was (no backdrop, no new weight)")
  for _, kind in ipairs(NL.KINDS) do
    IsColor(Drawn(kind, "title"), NEW.title, kind .. " title: ivory")
    IsColor(Drawn(kind, "detail"), NEW.detail, kind .. " detail: quieter")
    local look = NL.Look(kind)
    IsColor(look.accent, NEW.accent, kind .. " rule: aged bronze")
    Check(look.bgAlpha == 0, kind .. ": still no backdrop")
  end
  -- a card's own tone for a role (a smaller place's name) stays a shade of the role, moved the way the default moved
  IsColor(Drawn("arrival", "detail", { 0.31, 0.29, 0.255 }), { 0.31 * NEW.detail[1] / OLD.detail[1], 0.29 * NEW.detail[2] / OLD.detail[2], 0.255 * NEW.detail[3] / OLD.detail[3] }, "a dimmer tone")
  Check(Ui().notifyLook == nil, "reading the defaults saved nothing")

  -- partial: one color saved. It is drawn as it always was; the rest are the new defaults; nothing else is written
  Ui().notifyLook = { titleColor = "ff3366aa" }
  local before = Deep(Ui().notifyLook)
  Fresh()
  IsColor(Drawn("arrival", "title"), Legacy(OLD.title, "ff3366aa", OLD.title), "the saved title color is drawn as it always was")
  IsColor(Drawn("arrival", "detail"), NEW.detail, "an unsaved detail color inherits the new default")
  IsColor(NL.Look("arrival").accent, NEW.accent, "... and so does the rule")
  Check(Same(Ui().notifyLook, before), "the saved table is not touched by reading")
  Check(NL.Set("shared", "textScale", 120) and Same(Ui().notifyLook, { titleColor = "ff3366aa", textScale = 120 }), "changing one field changes only that field")
  IsColor(Drawn("arrival", "title"), Legacy(OLD.title, "ff3366aa", OLD.title), "...and the saved color is still the same")

  -- fully customized: every color saved, drawn as before
  Ui().notifyLook = { titleColor = "ff112233", bodyColor = "ff445566", detailColor = "ff778899", accentColor = "ffaabbcc", bgColor = "ff0a0b0c", bgOpacity = 40 }
  local full = Deep(Ui().notifyLook)
  Fresh()
  IsColor(Drawn("training", "title"), Legacy(OLD.title, "ff112233", OLD.title), "full: title")
  IsColor(Drawn("training", "body"), Legacy(OLD.body, "ff445566", OLD.body), "full: body")
  IsColor(Drawn("training", "detail"), Legacy(OLD.detail, "ff778899", OLD.detail), "full: detail")
  IsColor(NL.Look("training").accent, Rgb("ffaabbcc"), "full: rule")
  IsColor(NL.Look("training").bg, Rgb("ff0a0b0c"), "full: backdrop color")
  Check(Same(Ui().notifyLook, full), "a fully saved look is not changed by being drawn")

  -- a saved value equal to the OLD default is still the player's choice, drawn with the old numbers exactly
  Ui().notifyLook = { titleColor = Hex(OLD.title), detailColor = Hex(OLD.detail), accentColor = Hex(OLD.accent), bgColor = Hex(OLD.bg), bodyColor = Hex(OLD.body), bgOpacity = 30 }
  local explicit = Deep(Ui().notifyLook)
  Fresh()
  IsColor(Drawn("arrival", "title"), OLD.title, "the old default, saved: the old title, exactly")
  IsColor(Drawn("arrival", "detail"), OLD.detail, "... the old detail")
  IsColor(Drawn("training", "body"), OLD.body, "... the old body")
  IsColor(NL.Look("arrival").accent, OLD.accent, "... the old rule")
  IsColor(NL.Look("arrival").bg, OLD.bg, "... the old backdrop")
  Check(NL.Get("arrival", "titleColor") == Hex(OLD.title) and Same(Ui().notifyLook, explicit), "it is still saved, and still the old value: no comparison, no migration")
  -- ... and a saved value equal to the NEW default is exact too
  Ui().notifyLook = { titleColor = NL.DEFAULTS.titleColor }
  Fresh()
  IsColor(Drawn("arrival", "title"), NEW.title, "the new default, saved, draws as the default does")

  -- valid zero and false survive
  Ui().notifyLook = { accentOpacity = 0, textOpacity = 30, bgOpacity = 0, own = false }
  Fresh()
  Check(NL.Get("arrival", "accentOpacity") == 0 and NL.Look("arrival").accentAlpha == 0, "an accent opacity of 0 is a value, not a missing one")
  Check(NL.Get("arrival", "bgOpacity") == 0 and NL.Get("arrival", "textOpacity") == 30, "zero and the minimum read as saved")
  Check(Ui().notifyLook.own == false and Ui().notifyLook.accentOpacity == 0, "and the saved false and 0 are still there")

  -- own copies
  Ui().notifyLook = nil
  Ui().notifyLookTraining = { own = true, titleFont = "default", textFont = "default", textScale = 90, outline = "outline", titleColor = Hex(OLD.title), bodyColor = Hex(OLD.body),
    detailColor = Hex(OLD.detail), textOpacity = 100, accentColor = Hex(OLD.accent), accentOpacity = 100, bgColor = Hex(OLD.bg), bgOpacity = 0, padding = 10 }
  local own = Deep(Ui().notifyLookTraining)
  Fresh()
  Check(NL.Own("training") and NL.Get("training", "textScale") == 90, "a complete own copy is read")
  IsColor(Drawn("training", "title"), OLD.title, "its title is the old one, as it was copied")
  IsColor(NL.Look("training").accent, OLD.accent, "its rule is the old one")
  IsColor(Drawn("arrival", "title"), NEW.title, "a card following the shared look gets the new default")
  Check(Same(Ui().notifyLookTraining, own), "the own copy is untouched by reading")
  NL.Set("shared", "titleColor", "ff00ff00")
  Check(Same(Ui().notifyLookTraining, own), "... and by a later change to the shared look")
  -- an own look that is short of a key reads the default for that key and writes nothing
  Ui().notifyLookTraining = { own = true, textScale = 90 }
  local short = Deep(Ui().notifyLookTraining)
  Fresh()
  IsColor(Drawn("training", "title"), NEW.title, "an own copy without a color reads the new default")
  Check(Same(Ui().notifyLookTraining, short), "... and is not completed behind the player's back")
  -- turning an own look on is the player's act: only then is a copy written, of what the card was drawn with
  Ui().notifyLookTraining = nil; Ui().notifyLook = nil
  Check(NL.SetOwn("friend", true), "turn a card's own look on")
  local copy = Ui().notifyLookFriend
  Check(copy.own == true and copy.titleColor == NL.DEFAULTS.titleColor and copy.bgOpacity == 0 and copy.padding == 10, "it starts as a complete copy of what it was drawn with")
  -- Reset
  NL.Set("shared", "titleColor", "ff00ff00"); NL.Set("shared", "detailColor", Hex(OLD.detail))
  NL.ResetShared()
  Check(Ui().notifyLook == nil, "Reset forgets the shared look")
  IsColor(Drawn("arrival", "title"), NEW.title, "... and the cards are back to the new defaults")
  Check(Ui().notifyLookFriend ~= nil and Ui().notifyLookFriend.own == true, "Reset of the shared look leaves a card's own look alone")
  NL.ResetCard("friend")
  Check(Ui().notifyLookFriend == nil, "a card's own reset forgets its copy")
  NL.ResetShared()
end

---------------------------------------------------------------------------
-- 3. The adopted panel looks: lazy defaults, derived border fields, the frame as a border choice
---------------------------------------------------------------------------
local LOOKS = {
  { name = "refreshmentsStyle", look = R.RefreshmentsPanel.Style, border = F.BORDER, opacity = 98, borderOpacity = 90, bg = "ff261d15" },
  { name = "restockPromptStyle", look = R.RestockPrompt.Style, border = F.BORDER, opacity = 98, borderOpacity = 90, bg = "ff232221" },
  { name = "pinsLook", look = R.PinsLook.Look, border = F.BORDER, opacity = 98, borderOpacity = 90, bg = "ff261d15" },
  { name = "pinsEditorLook", look = R.PinsLook.EditorLook, border = F.BORDER, opacity = 98, borderOpacity = 90, bg = "ff261d15" },
  { name = "navigationLook", look = R.NavPrefs.Look, border = "solid", opacity = 92, borderOpacity = 80, bg = "ff1e1b18" },
}
for _, e in ipairs(LOOKS) do
  local L, name = e.look, e.name
  Check(L and L.DEFAULTS.bgColor == F.PANEL_BG and L.DEFAULTS.borderColor == F.PANEL_BORDER, name .. ": espresso and aged bronze")
  Check(L.DEFAULTS.borderTexture == e.border and L.DEFAULTS.bgTexture == "solid" and L.DEFAULTS.bgOpacity == e.opacity
    and L.DEFAULTS.borderOpacity == e.borderOpacity and L.DEFAULTS.borderSize == 1, name .. ": everything but the colors (and the frame) is as it was")
  Check(e.border ~= F.BORDER or L.IsCustomBorder(F.BORDER), name .. ": the frame is its own border, drawn by its owner")

  -- empty
  Ui()[name] = nil
  Check(L.Get("bgColor") == F.PANEL_BG and L.Get("borderTexture") == e.border and L.Get("bgOpacity") == e.opacity, name .. ": nothing saved, the defaults")
  Check(Ui()[name] == nil, name .. ": reading writes nothing")
  -- partial: a saved color and opacity (zero is a value) are kept; the border is the default
  Ui()[name] = { bgColor = "ff102030", bgOpacity = 0 }
  local part = Deep(Ui()[name])
  Check(L.Get("bgColor") == "ff102030" and L.Get("bgOpacity") == 0 and L.Get("borderTexture") == e.border and L.Get("borderColor") == F.PANEL_BORDER,
    name .. ": saved values kept (0 included); the rest inherit")
  Check(Same(Ui()[name], part), name .. ": reading leaves the saved table alone")
  -- the OLD default, saved, is the player's choice: read as itself, not as the new default
  Ui()[name] = { bgColor = e.bg, borderColor = "ff8c6e38", borderTexture = "solid", borderSize = 1 }
  local oldSaved = Deep(Ui()[name])
  Check(L.Get("bgColor") == e.bg and L.Get("borderColor") == "ff8c6e38" and L.Get("borderTexture") == "solid", name .. ": a saved old default is read as saved")
  Check(L.Set("bgOpacity", 55) and Same(Ui()[name], { bgColor = e.bg, borderColor = "ff8c6e38", borderTexture = "solid", borderSize = 1, bgOpacity = 55 }),
    name .. ": changing one field changes only that field")
  Ui()[name] = oldSaved
  -- fully saved
  local fullSaved = { bgTexture = "solid", bgColor = "ff0a0b0c", bgOpacity = 70, borderTexture = "solid", borderColor = "ff0c0b0a", borderOpacity = 60, borderSize = 3 }
  Ui()[name] = Deep(fullSaved)
  local ok = true
  for k, v in pairs(fullSaved) do if L.Get(k) ~= v then ok = false end end
  Check(ok, name .. ": a fully saved look reads as saved")
  Check(Same(Ui()[name], fullSaved), name .. ": ... and stays as it is")

  -- derived border fields: from the effective values and the look's own defaults, and only what has to change is saved
  Ui()[name] = nil
  Check(L.Set("borderTexture", "solid"), name .. ": choose the plain line")
  Check(Same(Ui()[name], { borderTexture = "solid" }), name .. ": nothing derived that the default already suits (thickness 1, bronze)")
  Check(L.Get("borderColor") == F.PANEL_BORDER and L.Get("borderSize") == 1, name .. ": the line is the look's bronze, 1 pixel")
  if e.border ~= "solid" then   -- (a look that already draws the plain line has nothing to derive from choosing it)
    Ui()[name] = { borderSize = 9 }
    Check(L.Set("borderTexture", "solid") and Ui()[name].borderSize == 1, name .. ": a thick size goes back to a line's usual one")
  end
  Ui()[name] = { borderTexture = "solid", borderSize = 3, borderColor = "ff102030" }
  Check(L.Set("borderTexture", "Blizzard Tooltip") and Ui()[name].borderSize == 12 and Ui()[name].borderColor == "ff102030",
    name .. ": a textured border gets a thickness that suits it, and the player's color stays")
  Ui()[name] = nil
  Check(L.Set("borderTexture", "none") and Same(Ui()[name], { borderTexture = "none" }), name .. ": none derives nothing")
  -- Reset
  Ui()[name] = { bgColor = "ff102030", borderTexture = "none" }
  L.Reset()
  Check(Ui()[name] == nil and L.Get("bgColor") == F.PANEL_BG and L.Get("borderTexture") == e.border, name .. ": Reset forgets the look, the defaults are the new ones")
  if e.border == F.BORDER then
    Check(L.Set("borderTexture", F.BORDER) and Same(Ui()[name], { borderTexture = F.BORDER }), name .. ": choosing the frame derives nothing (it ignores thickness and color)")
    Check(L.Set("borderTexture", "solid") and L.Get("borderColor") == F.PANEL_BORDER and L.Get("borderSize") == 1, name .. ": and leaving it keeps the look's own line")
    L.Reset()
    local listed = false
    for _, ch in ipairs(L.BorderChoices()) do if ch[1] == F.BORDER and ch[2] == F.BORDER_LABEL then listed = true end end
    Check(listed, name .. ": the frame is in the border list")
  end
end
local RP = R.RestockPrompt
Check(RP.Style.IsCustomBorder(RP.LEDGER) and RP.Style.IsCustomBorder(RP.FRAMED), "Restock offers its older rim as well as the frame")
Ui().restockPromptStyle = { borderTexture = RP.LEDGER }
Check(RP.Style.Get("borderTexture") == RP.LEDGER and RP.FRAMED ~= RP.LEDGER, "a saved rim is still the rim")
Ui().restockPromptStyle = nil

---------------------------------------------------------------------------
-- 4. Excluded consumers: every default they had
---------------------------------------------------------------------------
local EXCLUDED = {
  { "brokerMenu (the Mage menus, RestedXP's and the healer menu)", R.MenuStyle, "solid", "ff2b2117", 100, "solid", "ff8c6e38", 95, 1 },
  { "pinsBrokerMenu (a menu)", R.PinsLook.MenuLook, "solid", "ff2b2117", 100, "solid", "ff8c6e38", 95, 1 },
}
for _, e in ipairs(EXCLUDED) do
  local d = e[2].DEFAULTS
  Check(d.bgTexture == e[3] and d.bgColor == e[4] and d.bgOpacity == e[5] and d.borderTexture == e[6] and d.borderColor == e[7] and d.borderOpacity == e[8] and d.borderSize == e[9],
    e[1] .. ": unchanged")
  Check(not e[2].IsCustomBorder(F.BORDER), e[1] .. ": the frame is not one of its borders")
end
-- the looks the OnInit-made and other families keep: read from what the code made, compared with the values they had
local function Row(L) local d = L.DEFAULTS return { d.bgTexture, d.bgColor, d.bgOpacity, d.borderTexture, d.borderColor, d.borderOpacity, d.borderSize } end
local function Bar(name, L, want)
  Check(L ~= nil, name .. " is made")
  if L then
    local got = Row(L)
    Check(got[2] ~= F.PANEL_BG and got[5] ~= F.PANEL_BORDER and got[4] ~= F.BORDER, name .. ": none of the framed look's defaults")
    Check(want == nil or Same(got, want), name .. ": its defaults are what they were")
    Check(not L.IsCustomBorder(F.BORDER), name .. ": the frame is not one of its borders")
  end
end
local chron = R.ChronicleAppearance and R.ChronicleAppearance.Look
Bar("chronicleLook", chron)
Check(chron and chron.IsCustomBorder(R.ChronicleAppearance.LEDGER), "the Chronicle keeps its ledger border")
Bar("classBarsLook", R.ClassBars and R.ClassBars.Look)
Bar("healerWatchBarLook", R.HealerWatch and R.HealerWatch.BarLook)
Bar("restedxpSkin", R.RestedXPSkin and R.RestedXPSkin.Look)
Bar("restedxpTimerLook", R.RestedXPSkin and R.RestedXPSkin.Timers and R.RestedXPSkin.Timers.Look)
Bar("speakstoneSkin", R.SpeakStoneSkin and R.SpeakStoneSkin.Look)
Bar("markerBarStyle", R.MarkerBar and R.MarkerBar.Style)

-- Chronicle's own palette, which the notification defaults used to read, is not changed by the framed look
Check(Near(K.text[1], 0.93) and Near(K.text[2], 0.88) and Near(K.text[3], 0.76) and Near(K.stone[1], 0.62) and Near(K.bronze[1], 0.55) and Near(K.bg[1], 0.150),
  "the Chronicle's colors are what they were")

---------------------------------------------------------------------------
-- 5. The frame helper
---------------------------------------------------------------------------
do
  local border = "solid"
  local look = { Get = function(k) return k == "borderTexture" and border or nil end }
  local function Frame() return Any() end
  local frame = Frame()
  Check(F.Frame(frame, look) == 0 and rawget(frame, "twichFrame") == nil, "another border: nothing is made, nothing is reserved")
  local fr = Frame()
  border = F.BORDER
  Check(F.Frame(fr, look) == 13 and rawget(fr, "twichFrame") ~= nil, "the default border: the shell is made once and the reach is the frame's (13)")
  local shell = rawget(fr, "twichFrame")
  Check(shell.interior == nil and shell.grain == nil, "... with no interior and no grain: the player's background shows")
  F.Frame(fr, look)
  Check(rawget(fr, "twichFrame") == shell, "asking again makes no second shell")
  border = "none"
  Check(F.Frame(fr, look) == 0, "a border chosen later: nothing reserved")
end

if failures == 0 then print("PASSED test_theme_defaults") else print(failures .. " failures") os.exit(1) end
