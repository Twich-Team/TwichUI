-- Combo points: Rogues only, listeners only while on, the count and cap as the game reports
-- them, each visibility rule, target swaps without gain touches, gain and full touches (and
-- Animation / Reduced motion), a secret count never compared in Lua, the layouts, the settings'
-- ranges, the game's own combo points parked and given back (never in combat), Edit Mode, the
-- preview, and the options page for a Rogue.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI", "EllesmereUIUnitFrames"})

local frames = {}
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, events = {}, masks = {}, alpha = 1, scale = 1 }
  table.insert(frames, o)
  -- any other method is a no-op; a missing data field is nil
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
  RegisterEvent = function(s, e) s.events[e] = true end,
  RegisterUnitEvent = function(s, e, u) s.events[e] = u end,
  UnregisterAllEvents = function(s) s.events = {} end,
  SetFrameStrata = function(s, v) s.strata = v end,
  SetSize = function(s, w, h) s.w, s.h = w, h end,
  GetSize = function(s) return s.w or 0, s.h or 0 end,
  SetWidth = function(s, v) s.w = v end,
  SetHeight = function(s, v) s.h = v end,
  SetPoint = function(s, ...) s.point = {...} end,
  ClearAllPoints = function(s) s.point = nil end,
  SetAlpha = function(s, v) s.alpha = v end,
  SetScale = function(s, v) s.scale = v end,
  GetScale = function(s) return s.scale end,
  SetMinMaxValues = function(s, a, b) s.min, s.max = a, b end,
  SetValue = function(s, v) s.value = v end,
  GetStatusBarTexture = function(s) s.fillTex = s.fillTex or Fake("texture"); return s.fillTex end,
  SetStatusBarColor = function(s, ...) s.barColor = {...} end,
  SetOrientation = function(s, v) s.orientation = v end,
  CreateTexture = function() return Fake("texture") end,
  CreateFontString = function() return Fake("font") end,
  CreateMaskTexture = function() return Fake("mask") end,
  AddMaskTexture = function(s, m) s.masks[m] = true end,
  RemoveMaskTexture = function(s, m) s.masks[m] = nil end,
  SetColorTexture = function(s, ...) s.color = {...} end,
  SetText = function(s, v) s.text = v end,
  SetTextColor = function(s, ...) s.textColor = {...} end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; return true end,
  SetParent = function(s, p) s.parent = p end,
  GetParent = function(s) return s.parent end,
  GetCenter = function(s) return s.cx, s.cy end,
  CreateAnimationGroup = function(s) local g = Fake("group"); g.plays = 0; s.group = g; return g end,
  Play = function(s) s.plays = (s.plays or 0) + 1 end,
  CreateAnimation = function(s) local a = Fake("anim"); s.anims = s.anims or {}; table.insert(s.anims, a); return a end,
  SetFromAlpha = function(s, v) s.from = v end,
  SetToAlpha = function(s, v) s.to = v end,
}
c.CreateFrame = function(kind) return Fake(kind) end
c.UIParent = Fake("UIParent"); c.UIParent.cx, c.UIParent.cy = 512, 384
c.TargetFrame = Fake("TargetFrame")
c.ComboFrame = Fake("ComboFrame"); c.ComboFrame.parent = c.TargetFrame
c.EDITING = false
c.EventRegistry = { callbacks = {} }
function c.EventRegistry:RegisterCallback(event, fn, owner) assert(owner, "registered with an owner"); self.callbacks[event] = fn end
c.EditModeManagerFrame = { IsEditModeActive = function() return c.EDITING end }
c.GameTooltip = Fake("tooltip")
c.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- The game. A secret value is a table here, so any compare or sum of one in Lua errors.
c.CLASS, c.POINTS, c.MAXP, c.TARGET, c.TARGET_DEAD, c.DEAD, c.COMBAT = "ROGUE", 0, 5, nil, false, false, false
local function SecretOf(n) return { secret = true, n = n } end
c.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
c.UnitClass = function() return "Class", c.CLASS end
c.GetComboPoints = function(unit, target) assert(unit == "player" and target == "target"); return c.POINTS end
c.UnitPowerMax = function(unit, power) assert(unit == "player" and power == 4, "combo points (4)"); return c.MAXP end
c.UnitExists = function() return c.TARGET ~= nil end
c.UnitCanAttack = function() return c.TARGET == "enemy" end
c.UnitIsDead = function(unit) return unit == "target" and c.TARGET_DEAD or false end
c.UnitIsDeadOrGhost = function(unit) return unit == "player" and c.DEAD or false end
c.UnitAffectingCombat = function() return c.COMBAT end
c.InCombatLockdown = function() return c.COMBAT end

for _, f in ipairs({ "chronicle/Style.lua", "modules/ComboPoints.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { comboPoints = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local CP = R.ComboPoints
local M = c.TwichUIDB.modules

local function Close(a, b) return math.abs(a - b) < 1e-6 end
local function Find(test) for _, f in ipairs(frames) do if test(f) then return f end end end
local container = Find(function(f) return f.strata == "MEDIUM" end)
local events = Find(function(f) return f.scripts.OnEvent ~= nil end)
assert(container and events, "the display and its event frame")
local function Fire(event, ...)
  assert(events.events[event], event .. " is listened for")
  events.scripts.OnEvent(events, event, ...)
end
local function Segments()
  local list = {}
  for _, f in ipairs(frames) do if rawget(f, "flashGroup") then list[#list + 1] = f end end
  return list
end
local function Shown()
  local n = 0
  for _, s in ipairs(Segments()) do if s.shown then n = n + 1 end end
  return n
end
local function Values()
  local out = {}
  for i, s in ipairs(Segments()) do if s.shown then out[i] = s.bar.value end end
  return out
end
local function Flashes() local out = {} for i, s in ipairs(Segments()) do out[i] = s.flashGroup.plays end return out end
local fullGroup = Find(function(f) return f.kind == "group" and f.anims and #f.anims == 2 end)
assert(fullGroup, "the full-points rule's animation")

-- Listening and the cap.
assert(events.events.PLAYER_TARGET_CHANGED and events.events.UNIT_POWER_FREQUENT == "player" and events.events.UNIT_MAXPOWER == "player"
  and events.events.UNIT_HEALTH == "target" and events.events.PLAYER_REGEN_DISABLED and events.events.PLAYER_DEAD, "listens while on")
assert(Shown() == 5, "five points, as UnitPowerMax says: " .. Shown())
for i, s in ipairs(Segments()) do assert(s.bar.min == i - 1 and s.bar.max == i, "point " .. i .. " is a one-point bar") end

-- "When I have points" (the default): hidden with no target, and at 0.
assert(CP.Get("visibility") == "points")
assert(not container.shown, "no target: hidden")
c.TARGET = "enemy"; Fire("PLAYER_TARGET_CHANGED")
assert(not container.shown, "a target with no points: hidden")

-- Gaining: shown, the point filled, a brief light on the new point only.
c.POINTS = 1; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
assert(container.shown, "shown with a point")
local v = Values(); assert(v[1] == 1 and v[5] == 1, "every point is told the count; the bar decides")
local f = Flashes(); assert(f[1] == 1 and f[2] == 0, "a light on the point gained")
assert(Close(Segments()[1].flashFade.from, 0.6), "full strength by default")
Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")   -- energy: nothing to do
f = Flashes(); assert(f[1] == 1, "energy changes are ignored")

-- Full: lights on the new points, and the rule once.
c.POINTS = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
f = Flashes(); assert(f[1] == 1 and f[2] == 1 and f[5] == 1, "lights on points 2 to 5")
assert(fullGroup.plays == 1, "the full-points rule, once")
Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
assert(fullGroup.plays == 1 and Flashes()[5] == 1, "still full: no repeat")

-- Spending: no touches, and hidden at 0.
c.POINTS = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
assert(not container.shown and Flashes()[1] == 1, "spent: hidden, nothing lit")

-- Swapping to a target that already carries points: shown, but nothing was gained.
c.POINTS = 3; Fire("PLAYER_TARGET_CHANGED")
assert(container.shown and Flashes()[1] == 1 and Flashes()[3] == 1, "a new target's points aren't a gain")
c.POINTS = 4; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
assert(Flashes()[4] == 2, "then a real gain is")

-- The target dying hides it; a friendly target never shows it.
c.TARGET_DEAD = true; Fire("UNIT_HEALTH", "target")
assert(not container.shown, "a dead target: hidden")
c.TARGET_DEAD = false; c.TARGET = "friend"; c.POINTS = 0; Fire("PLAYER_TARGET_CHANGED")
assert(not container.shown)

-- "Whenever I have a target": shown at 0 with a living enemy.
assert(CP.Set("visibility", "target"))
assert(not container.shown, "a friendly target: hidden")
c.TARGET = "enemy"; Fire("PLAYER_TARGET_CHANGED")
assert(container.shown and Values()[1] == 0, "an enemy at 0: shown, empty")
c.TARGET = nil; Fire("PLAYER_TARGET_CHANGED")
assert(not container.shown, "no target: hidden")

-- "In combat": only then, target or not; never while dead.
assert(CP.Set("visibility", "combat"))
assert(not container.shown)
c.COMBAT = true; Fire("PLAYER_REGEN_DISABLED")
assert(container.shown, "in combat, even with no target")
c.DEAD = true; Fire("PLAYER_DEAD")
assert(not container.shown, "hidden while dead")
c.DEAD = false; c.COMBAT = false; Fire("PLAYER_ALIVE"); Fire("PLAYER_REGEN_ENABLED")
assert(not container.shown, "out of combat: hidden")
assert(CP.Set("visibility", "points"))

-- The cap: a new one re-lays the points; one the game can't give keeps the last.
c.MAXP = 6; Fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
assert(Shown() == 6, "six points")
c.MAXP = SecretOf(7); Fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
assert(Shown() == 6, "a secret cap keeps the last")
c.MAXP = 0; Fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
assert(Shown() == 6, "a cap of 0 keeps the last")
c.MAXP = 5; Fire("UNIT_MAXPOWER", "player", "COMBO_POINTS")
assert(Shown() == 5)

-- A secret count: handed to the bars as it is, never compared; shown with an enemy target.
do
  c.TARGET, c.POINTS = "enemy", 2; Fire("PLAYER_TARGET_CHANGED")
  local before, rule = Flashes(), fullGroup.plays
  local secret = SecretOf(4)
  c.POINTS = secret; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(Values()[1] == secret and Values()[5] == secret, "the bars get the secret value")
  assert(container.shown, "points rule falls back to having an enemy target")
  local after = Flashes()
  for i = 1, 5 do assert(after[i] == before[i], "no touches for a secret count") end
  assert(fullGroup.plays == rule)
  c.TARGET = nil; Fire("PLAYER_TARGET_CHANGED")
  assert(not container.shown, "and hidden with no target")
  c.TARGET = "enemy"; Fire("PLAYER_TARGET_CHANGED")
  c.POINTS = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(fullGroup.plays == rule, "plain again: settles on the count without a touch")
  Fire("UNIT_POWER_FREQUENT", "player", "SECRETLESS")
  c.POINTS = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
end

-- Animation: Off, and Subtle under Reduced motion.
do
  c.TARGET = "enemy"; c.POINTS = 0; Fire("PLAYER_TARGET_CHANGED")
  assert(CP.Set("animation", "off"))
  local before = Flashes()[1]
  c.POINTS = 1; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(Flashes()[1] == before, "Off: no light")
  assert(CP.Set("animation", "full"))
  M.arrivalReducedMotion = true
  c.POINTS = 2; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(Close(Segments()[2].flashFade.from, 0.3), "Reduced motion: subtle")
  M.arrivalReducedMotion = false
  c.POINTS = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
end

-- Layouts.
do
  c.POINTS = 2; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  local s = Segments()
  assert(s[1].w == 14 and s[1].h == 14, "points are 14 px by default")
  assert(s[1].point[4] == 4 and s[2].point[4] == 4 + 14 + 3, "side by side, from the left, 3 px apart")
  assert(container.w == 5 * 14 + 4 * 3 + 8 and container.h == 14 + 8, "the display fits the points")
  assert(CP.Set("direction", "reverse"))
  assert(s[5].point[4] == 4 and s[1].point[4] == 4 + 4 * 17, "reversed: the first point on the right")
  assert(CP.Set("orientation", "vertical"))
  assert(s[1].point[5] == 4 + 4 * 17 and s[1].point[4] == 4 and s[1].bar.orientation == "VERTICAL", "stacked")
  assert(CP.Set("direction", "forward") and CP.Set("orientation", "horizontal"))

  assert(CP.Set("style", "bar"))
  assert(Close(s[1].w, (150 - 3 * 4) / 5) and s[1].h == 6, "a thin bar: the length shared out")
  assert(CP.Set("shape", "round"))
  assert(next(s[1].well.masks) == nil, "round is only for points")
  assert(CP.Set("style", "pips"))
  assert(next(s[1].well.masks) ~= nil and next(s[1].rim.masks) ~= nil, "round points are masked")
  assert(CP.Set("shape", "square"))
  assert(next(s[1].well.masks) == nil and next(s[1].rim.masks) == nil, "square again: unmasked")

  assert(CP.Set("scale", 150) and container.scale == 1.5)
  assert(container.point[4] == 0 and Close(container.point[5], -170 / 1.5), "the place stays put at another scale")
  assert(CP.Set("opacity", 40) and Close(container.alpha, 0.4))
  assert(CP.Set("scale", 100) and CP.Set("opacity", 100))
end

-- Number style: the count, in the empty, filled or full colour.
do
  local number = Find(function(f) return f.kind == "font" end)
  assert(CP.Set("style", "number"))
  assert(number.shown and Shown() == 0, "only the number")
  assert(number.text == 2, "the count")
  local r, g, b = CP.ParseColor("fff0c76b")
  assert(Close(number.textColor[1], r) and Close(number.textColor[2], g) and Close(number.textColor[3], b), "filled colour")
  assert(number.font[2] == 28 and number.font[3] == "OUTLINE" and number.font[1]:find("Cinzel"), "TwichUI's Cinzel, outlined")
  c.POINTS = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  r = CP.ParseColor("ffd7b45a"); assert(Close(number.textColor[1], r), "full: the accent")
  assert(number.group.plays >= 1, "a gain touches the number")
  local secret = SecretOf(3)
  c.POINTS = secret; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(number.text == secret, "a secret count is drawn as it is")
  c.POINTS = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(CP.Set("style", "pips"))
  assert(not number.shown and Shown() == 5)
end

-- Settings: bad values are refused and bad saved ones ignored; colours follow the look.
do
  assert(CP.Set("pipSize", 99) == false and CP.Set("pipSize", 10.5) == false and CP.Set("style", "dots") == false
    and CP.Set("theme", "neon") == false and CP.Set("activeColor", "gold") == false and CP.Set("shadow", 1) == false
    and CP.Set("font", "bad|font") == false and CP.Set("nonsense", 1) == false, "bad values are refused")
  local saved = c.TwichUIDB.ui.comboPoints
  c.TwichUIDB.ui.comboPoints = { pipSize = "big", style = 3, theme = "x", activeColor = 5 }
  assert(CP.Get("pipSize") == 14 and CP.Get("style") == "pips" and CP.Get("theme") == "bronze" and CP.Get("activeColor") == "fff0c76b", "bad saved values are ignored")
  c.TwichUIDB.ui.comboPoints = saved
  local seg = Segments()[1]
  assert(CP.Set("theme", "poison"))
  local r = CP.ParseColor("ff8fb35a")
  assert(Close(seg.bar.barColor[1], r) and CP.Get("activeColor") == "ff8fb35a", "the look's colours")
  assert(CP.Set("activeColor", "ff102030"))
  assert(Close(seg.bar.barColor[1], r), "a colour of your own waits for Use my own colors")
  assert(CP.Set("customColors", true))
  assert(Close(seg.bar.barColor[1], 16 / 255), "then it is used")
  CP.ClearColors()
  assert(CP.Get("activeColor") == "ff8fb35a" and Close(seg.bar.barColor[1], r), "cleared: the look's again")
  assert(CP.Set("customColors", false) and CP.Set("theme", "bronze"))
  local back = Find(function(f) return f.kind == "texture" and f.color and Close(f.color[1], 0x30 / 255) end)
  assert(not back, "no backing in the bronze look")
  assert(CP.Set("theme", "leather"))
  back = Find(function(f) return f.kind == "texture" and f.shown and f.color and Close(f.color[1], 0x30 / 255) end)
  assert(back, "leather has a backing")
  assert(CP.Set("theme", "bronze"))
end

-- The game's own combo points: parked while on, given back when off; never in combat.
do
  local game = c.ComboFrame
  assert(game.parent ~= c.TargetFrame and CP.GameFrameHidden(), "parked under a frame of ours")
  M.comboPointsHideGame = false; CP.Refresh()
  assert(game.parent == c.TargetFrame and not CP.GameFrameHidden(), "given back to its parent")
  c.COMBAT = true
  M.comboPointsHideGame = true; CP.Refresh()
  assert(game.parent == c.TargetFrame, "not in combat")
  c.COMBAT = false; Fire("PLAYER_REGEN_ENABLED")
  assert(CP.GameFrameHidden(), "done when combat ends")
  -- turned off in combat: given back after it, though the display itself is off
  c.COMBAT = true
  M.comboPoints = false; CP.Refresh()
  assert(CP.GameFrameHidden() and events.events.PLAYER_REGEN_ENABLED and not events.events.PLAYER_TARGET_CHANGED,
    "still parked; waiting only for combat to end")
  c.COMBAT = false; Fire("PLAYER_REGEN_ENABLED")
  assert(game.parent == c.TargetFrame, "given back after combat")
  assert(next(events.events) == nil, "and nothing listened for")
  M.comboPoints = true; CP.Refresh()
  -- something else has taken it: given back to that, not to the target frame
  local other = Fake("hidden")
  M.comboPointsHideGame = false; CP.Refresh()
  game.parent = other
  M.comboPointsHideGame = true; CP.Refresh()
  M.comboPointsHideGame = false; CP.Refresh()
  assert(game.parent == other, "given back to whoever had it")
  game.parent = c.TargetFrame
  -- a protected frame is left alone
  game.IsProtected = function() return true end
  M.comboPointsHideGame = true; CP.Refresh()
  assert(game.parent == c.TargetFrame, "protected: untouched")
  game.IsProtected = nil; CP.Refresh()
end

-- Edit Mode: shown with sample points, no target needed; dragging saves the place.
do
  c.TARGET, c.POINTS = nil, 0; Fire("PLAYER_TARGET_CHANGED")
  assert(not container.shown)
  local before = Flashes()
  c.EDITING = true; c.EventRegistry.callbacks["EditMode.Enter"]()
  local mover = Find(function(f) return f.scripts.OnDragStop ~= nil end)
  assert(mover and mover.shown and container.shown, "the outline, over sample points")
  assert(Values()[1] == 3, "three sample points")
  assert(Flashes()[3] == before[3], "samples aren't a gain")
  mover.cx, mover.cy = 612, 304
  mover.scripts.OnDragStop(mover)
  assert(c.TwichUIDB.ui.comboPointsPosition.x == 100 and c.TwichUIDB.ui.comboPointsPosition.y == -80, "an offset from the centre")
  mover.scripts.OnMouseUp(mover, "RightButton")
  local x, y = CP.Position(); assert(x == 0 and y == -170, "right-click: back to the default")
  c.EDITING = false; c.EventRegistry.callbacks["EditMode.Exit"]()
  assert(not mover.shown and not container.shown, "outline gone; the real count again")
  c.TwichUIDB.ui.comboPointsPosition = { x = 1e9, y = 0 }
  x, y = CP.Position(); assert(x == 0 and y == -170, "a bad saved place is ignored")
  c.TwichUIDB.ui.comboPointsPosition = nil
end

-- Preview: fills one by one to full, holds, then the game's count again.
do
  local rule = fullGroup.plays
  c.SlashCmdList.TWICHUI("combo")
  assert(container.shown and Values()[1] == 0, "starts empty")
  for _ = 1, 5 do FlushTimers() end
  assert(Values()[1] == 5 and fullGroup.plays == rule + 1, "full, with the rule")
  FlushTimers(); RunLongTimers(3)
  assert(not container.shown, "back to the game's count (no target, nothing shown)")
end

-- Off: nothing listened for, nothing shown, the preview says why.
M.comboPoints = false; CP.Refresh()
assert(next(events.events) == nil and not container.shown, "off: no listeners")
local ok, why = CP.Preview(); assert(not ok and why:find("Turn on"), why)
M.comboPoints = true; CP.Refresh()

-- Not a Rogue: nothing at all.
c.CLASS = "MAGE"; CP.Refresh()
assert(next(events.events) == nil and not container.shown and not CP.ForPlayer())
ok, why = CP.Preview(); assert(not ok and why:find("Rogues"), why)
assert(c.ComboFrame.parent == c.TargetFrame, "the game's frame is given back")
c.CLASS = "ROGUE"; CP.Refresh()

-- Off by default.
local d = MakeClient("Pat", {"!!!TwichUI"})
d.LOADED["!!!TwichUI"] = true; d.FireEvent("ADDON_LOADED", "!!!TwichUI")
assert(d.TwichUIDB.modules.comboPoints == false and d.TwichUIDB.modules.comboPointsHideGame == true, "opt-in")

-- The options page, for a Rogue: its controls reach the module, the style-only ones depend on the
-- style, colours and the font are advanced, and EllesmereUI's own displays are named.
do
  local initializers, proxies, pages, dropdowns = {}, {}, {}, {}
  local function Initializer(name, tooltip)
    local i = { data = { name = name, tooltip = tooltip }, shown = {}, modify = {} }
    function i:AddShownPredicate(fn) table.insert(self.shown, fn) end
    function i:SetParentInitializer(parent, fn) self.parent = parent; if fn then table.insert(self.modify, fn) end end
    table.insert(initializers, i)
    return i
  end
  c.CreateSettingsListSectionHeaderInitializer = function(name, tooltip) return Initializer(name, tooltip) end
  c.CreateSettingsButtonInitializer = function(name, _, click, tooltip) local i = Initializer(name, tooltip); i.click = click; return i end
  c.Settings = {
    VarType = { Boolean = "boolean", String = "string", Number = "number" },
    RegisterVerticalLayoutCategory = function(name) return { GetID = function() return 1 end, name = name }, { AddInitializer = function() end } end,
    RegisterVerticalLayoutSubcategory = function(_, name) table.insert(pages, name); return { GetID = function() return #pages end, name = name }, { AddInitializer = function() end } end,
    RegisterAddOnSetting = function(_, variable, key, tbl, _, name, default)
      return { variable = variable, name = name, default = default, SetValueChangedCallback = function(self, fn) self.changed = fn end }
    end,
    RegisterProxySetting = function(_, variable, varType, name, default, get, set)
      local s = { variable = variable, varType = varType, name = name, default = default, get = get, set = set }
      s.SetValue = function(self, value) self.set(value) end
      proxies[variable] = s
      return s
    end,
    CreateSliderOptions = function(min, max, step) return { min = min, max = max, step = step } end,
    CreateSlider = function(_, setting, options, tooltip) local i = Initializer(setting.name, tooltip); i.setting = setting; i.options = options; return i end,
    CreateColorSwatch = function(_, setting, tooltip) local i = Initializer(setting.name, tooltip); i.setting = setting; return i end,
    CreateCheckbox = function(_, setting, tooltip) local i = Initializer(setting.name, tooltip); i.setting = setting; return i end,
    CreateDropdown = function(_, setting, options, tooltip) local i = Initializer(setting.name, tooltip); i.setting = setting; dropdowns[setting.variable] = options; return i end,
    CreateControlTextContainer = function()
      local data = {}
      return { Add = function(_, value, label, tip) table.insert(data, { value = value, label = label, tooltip = tip }) end, GetData = function() return data end }
    end,
    RegisterAddOnCategory = function() end,
  }
  c.StaticPopupDialogs = {}; c.StaticPopup_Show = function() end
  c.LOADED.EllesmereUIUnitFrames = true
  local chunk = assert(loadfile(ROOT .. "Settings.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  local build = R.initHooks[#R.initHooks]
  build()
  local list = table.concat(pages, ",")
  assert(list:find("Food and drink,Combo points,Journey Chronicle", 1, true), list)
  local named = {}
  for _, i in ipairs(initializers) do named[i.data.name] = i end
  assert(named["Show TwichUI combo points"] and named["Style"] and named["Look"] and named["Show it"], "the essentials are visible")
  assert(#named["Style"].shown == 0 and #named["Show it"].shown == 0)
  assert(#named["Use my own colors"].shown == 1 and #named["Filled point"].shown == 1 and #named["Number font"].shown == 1, "colours and font are advanced")
  local hide = named["Hide the game's combo points by the target portrait"]
  assert(hide and hide.data.tooltip:find("Enable Class Resource", 1, true) and not hide.data.tooltip:find("Resource Bars", 1, true),
    "names the EllesmereUI display that is installed, and only that")
  -- style-only controls follow the style
  local size = named["Point size"]
  assert(size.parent == named["Style"] and size.modify[1]() == true)
  proxies.TWICHUI_comboStyle.set("bar")
  assert(size.modify[1]() == false and named["Bar length"].modify[1]() == true, "greyed out for another style")
  proxies.TWICHUI_comboStyle.set("pips")
  -- the controls read and write the module's settings
  for variable, key in pairs({ TWICHUI_comboStyle = "style", TWICHUI_comboTheme = "theme", TWICHUI_comboVisibility = "visibility",
      TWICHUI_comboPipSize = "pipSize", TWICHUI_comboSpacing = "spacing", TWICHUI_comboScale = "scale", TWICHUI_comboAnimation = "animation" }) do
    assert(proxies[variable] and proxies[variable].default == CP.DEFAULTS[key] and proxies[variable].get() == CP.Get(key), variable)
  end
  proxies.TWICHUI_comboPipSize.set(18.4); assert(CP.Get("pipSize") == 18, "a slider value is kept whole")
  assert(proxies.TWICHUI_comboActiveColor.default == "fff0c76b", "a swatch's default is the default look's")
  assert(#dropdowns.TWICHUI_comboTheme() == 4 and dropdowns.TWICHUI_comboTheme()[1].value == "bronze")
  -- Reset puts the look back and forgets your colours
  proxies.TWICHUI_comboTheme.set("poison"); CP.Set("activeColor", "ff102030")
  named["Appearance"].click()
  assert(CP.Get("theme") == "bronze" and CP.Get("pipSize") == 14 and c.TwichUIDB.ui.comboPoints.activeColor == nil, "reset")
  -- a Mage gets no page
  c.CLASS = "MAGE"; pages = {}
  local mageInits = #initializers
  build()
  assert(not table.concat(pages, ","):find("Combo points"), "no page for other classes")
  assert(#initializers > mageInits)
  c.CLASS = "ROGUE"
end

print("COMBO POINTS TEST PASSED")
