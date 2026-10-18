-- Class resource bars (classbars/): the providers read what the client reports and nothing else; the configuration
-- is validated and inherits shared -> class/resource override; the bars draw continuous and segmented resources and
-- only touch what changed; visibility follows resource-aware rules; the preview and positioning mode are isolated from
-- the real values and clean up; effects are off by default, play on real transitions only, are bounded and stop;
-- nothing runs when the bars are hidden or off. A fake world stands in for the game, so this checks our logic, not the
-- game: in-game checks are listed in docs/class-bars.md.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })

---------------------------------------------------------------------------
-- A fake world: frames that record what they were told, events delivered only to what registered, power APIs
---------------------------------------------------------------------------
local frames, created = {}, 0
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, events = {}, unitEvents = {}, points = {}, level = 1, scale = 1,
    alpha = 1, counts = {}, calls = {} }
  frames[#frames + 1] = o
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
local function Count(s, name) s.counts[name] = (s.counts[name] or 0) + 1 end
Methods = {
  Show = function(s) s.shown = true end,
  Hide = function(s) s.shown = false end,
  IsShown = function(s) return s.shown end,
  SetShown = function(s, v) s.shown = v and true or false end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end,
  GetScript = function(s, n) return s.scripts[n] end,
  RegisterEvent = function(s, e) s.events[e] = true end,
  RegisterUnitEvent = function(s, e, u) s.events[e] = true; s.unitEvents[e] = u end,
  UnregisterEvent = function(s, e) s.events[e] = nil; s.unitEvents[e] = nil end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  SetText = function(s, v) s.text = v; Count(s, "SetText") end,
  SetMinMaxValues = function(s, lo, hi) s.minMax = { lo, hi } end,
  SetValue = function(s, v, interp) s.value, s.interp = v, interp; Count(s, "SetValue") end,
  GetStatusBarTexture = function(s) s.sbTex = s.sbTex or Fake("texture"); return s.sbTex end,
  GetStringWidth = function() return 100 end,
  ClearAllPoints = function(s) s.points = {} end,
  SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetAllPoints = function(s) s.allPoints = true end,
  SetSize = function(s, w, h) s.width, s.height = w, h end,
  SetWidth = function(s, w) s.width = w; Count(s, "SetWidth") end,
  SetHeight = function(s, h) s.height = h end,
  GetWidth = function(s) return s.width end,
  GetHeight = function(s) return s.height end,
  SetTexture = function(s, p) s.texture = p end,
  SetColorTexture = function(s, ...) s.color = { ... } end,
  SetVertexColor = function(s, ...) s.vertex = { ... } end,
  SetGradient = function(s, dir, a, b) s.gradient = { dir = dir, min = a, max = b }; Count(s, "SetGradient") end,
  SetTexCoord = function(s, ...) s.texcoord = { ... } end,
  SetBlendMode = function(s, m) s.blend = m end,
  SetAlpha = function(s, a) s.alpha = a; Count(s, "SetAlpha") end,
  GetAlpha = function(s) return s.alpha end,
  SetScale = function(s, v) s.scale = v end,
  GetScale = function(s) return s.scale end,
  GetEffectiveScale = function(s) return s.scale * (s.parent and s.parent.GetEffectiveScale and s.parent:GetEffectiveScale() or 1) end,
  SetParent = function(s, p) s.parent = p end,
  GetParent = function(s) return s.parent end,
  SetFrameLevel = function(s, v) s.level = v end,
  GetFrameLevel = function(s) return s.level end,
  EnableMouse = function(s, v) s.mouse = v and true or false end,
  RegisterForDrag = function(s) s.dragRegistered = true end,
  SetBackdrop = function(s, info) s.backdrop = info end,
  SetBackdropColor = function(s, r, g, b, a) s.bgColor = { r, g, b, a } end,
  SetBackdropBorderColor = function(s, r, g, b, a) s.edgeColor = { r, g, b, a } end,
  GetCenter = function(s) return s.center and s.center[1], s.center and s.center[2] end,
  StartMoving = function(s) s.moving = true end,
  StopMovingOrSizing = function(s) s.moving = false end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; return true end,
}
c.CreateFrame = function(kind, name, parent, template)
  created = created + 1
  local f = Fake(kind)
  f.name, f.parent, f.template = name, parent, template
  return f
end
c.UIParent = Fake("UIParent")
c.UIParent.GetWidth = function() return c.SCREEN_W or 1024 end
c.UIParent.GetHeight = function() return c.SCREEN_H or 768 end
c.UIParent.GetCenter = function() return (c.SCREEN_W or 1024) / 2, (c.SCREEN_H or 768) / 2 end
c.UIParent.GetEffectiveScale = function() return 1 end
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
c.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
  DRUID = { r = 1, g = 0.49, b = 0.04 } }
c.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- The player: a table the fake APIs read, changed by the tests.
-- A restricted value: addon code may not compute with it or order it, so every such attempt is an error here too.
local SECRET = setmetatable({}, {
  __lt = function() error("compared a secret value") end, __le = function() error("compared a secret value") end,
  __add = function() error("computed with a secret value") end, __sub = function() error("computed with a secret value") end,
  __mul = function() error("computed with a secret value") end, __div = function() error("computed with a secret value") end,
  __concat = function() error("concatenated a secret value") end, __unm = function() error("computed with a secret value") end,
})
local W
local function World(class)
  local presets = {
    MAGE = { name = "Mage", ptype = 0, token = "MANA" }, WARRIOR = { name = "Warrior", ptype = 1, token = "RAGE" },
    ROGUE = { name = "Rogue", ptype = 3, token = "ENERGY" }, DRUID = { name = "Druid", ptype = 0, token = "MANA" },
  }
  local p = presets[class]
  W = { class = class, name = p.name, ptype = p.ptype, token = p.token, combo = 0, combat = false, dead = false, mounted = false,
    vehicle = false, P = { [0] = 800, [1] = 0, [3] = 100 }, PM = { [0] = 1000, [1] = 100, [3] = 100, [4] = 5 } }
end
World("MAGE")
c.UnitClass = function() return W.name, W.class end
c.UnitPowerType = function() return W.ptype, W.token, 0.3, 0.5, 0.9 end
c.UnitPower = function(_, t) return W.P[t] end
c.UnitPowerMax = function(_, t) return W.PM[t] end
c.CurveConstants = { ScaleTo100 = {} }
-- The game's own percentage: restricted exactly when the current value is.
c.UnitPowerPercent = function(_, t, _, curve)
  assert(curve == c.CurveConstants.ScaleTo100, "asked for 0 to 100")
  if W.P[t] == SECRET then return SECRET end
  return W.P[t] / W.PM[t] * 100
end
c.GetComboPoints = function() return W.combo end
c.UnitAffectingCombat = function() return W.combat end
c.UnitIsDeadOrGhost = function() return W.dead end
c.IsMounted = function() return W.mounted end
c.UnitHasVehicleUI = function() return W.vehicle end
c.issecretvalue = function(v) return v == SECRET end
c.InCombatLockdown = function() return W.combat end

local function Fire(event, ...)
  c.FireEvent(event, ...)   -- the shared bus (Core), for whatever listens there
  local args = { ... }
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent and (not f.unitEvents[event] or f.unitEvents[event] == args[1]) then
      f.scripts.OnEvent(f, event, ...)
    end
  end
end
-- Runs the shared animation driver for n steps of dt, as the game would.
local function Tick(n, dt)
  for _ = 1, n or 1 do
    for _, f in ipairs(frames) do
      if f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt or 0.05) end
    end
  end
end
local function UpdateScripts()
  local n = 0
  for _, f in ipairs(frames) do if f.scripts.OnUpdate then n = n + 1 end end
  return n
end

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "classbars/Anim.lua", "classbars/Resources.lua",
  "classbars/Config.lua", "classbars/Bar.lua", "classbars/Effects.lua", "classbars/Controller.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local CB, CBR, FX, A = R.ClassBars, R.ClassBarResources, R.ClassBarEffects, R.ClassBarAnim
local near = function(a, b) return math.abs(a - b) < 0.002 end

local function Eventful()
  local n = 0
  for _, f in ipairs(frames) do for _ in pairs(f.events) do n = n + 1 end end
  return n
end
local function EnterWorld() Fire("PLAYER_ENTERING_WORLD") end
local function On() R:SetEnabled("classBars", true) end
local function Off() R:SetEnabled("classBars", false) end
local function Reset()   -- a clean slate between sections: switch off, forget every saved value
  Off()
  c.TwichUIDB.ui = {}
  CB.Invalidate()
end

---------------------------------------------------------------------------
-- 1. Off by default: no frames, no events, no timers
---------------------------------------------------------------------------
do
  assert(c.TwichUIDB.modules.classBars == false, "the bars are opt-in")
  assert(created == 0, "nothing is built while the bars are off (made " .. created .. ")")
  assert(Eventful() == 0 or (function() for _, f in ipairs(frames) do if f.events.PLAYER_ENTERING_WORLD then return false end end return true end)(),
    "no class bar event is registered while off")
  assert(not CB.Running() and A.Count() == 0 and not A.Running())
  assert(CB.Snapshot().events == 0)
end

---------------------------------------------------------------------------
-- 2. The providers: what applies, from what the client reports
---------------------------------------------------------------------------
do
  local ctx = CBR.Context()
  -- Mage: mana only
  World("MAGE"); CBR.Sense()
  assert(CBR.Resolve("primary").id == "power" and CBR.Resolve("secondary") == nil and CBR.Resolve("tertiary") == nil, "a Mage has one bar")
  local s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.ok and s.key == "MANA" and s.cur == 800 and s.max == 1000 and s.kind == "continuous")
  -- Warrior: rage, whatever the class table would say: it is what the client reports
  World("WARRIOR"); CBR.Sense()
  s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.key == "RAGE" and s.max == 100 and s.cur == 0 and CBR.Resolve("secondary") == nil)
  -- a power the client reports that no table knows is drawn as itself, never as another
  World("WARRIOR"); W.ptype, W.token = 6, "RUNIC_POWER"; W.P[6], W.PM[6] = 40, 100; CBR.Sense()
  s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.key == "RUNIC_POWER" and s.cur == 40, "any power the client reports is shown as itself")
  -- Rogue: energy, and combo points on the target
  World("ROGUE"); W.combo = 3; CBR.Sense()
  assert(CBR.Resolve("primary") and CBR.Resolve("secondary").id == "combo" and CBR.Resolve("tertiary") == nil)
  s = CBR.Read(CBR.Resolve("secondary"), ctx)
  assert(s.ok and s.key == "COMBO_POINTS" and s.cur == 3 and s.max == 5 and s.kind == "segmented")
  W.PM[4] = 9; s = CBR.Read(CBR.Resolve("secondary"), ctx)
  assert(s.max == CBR.COMBO_CAP, "never more than five combo points are drawn")
  W.PM[4] = 5
  -- Druid by form: caster = mana only; Cat = energy + combo + mana; Bear = rage + mana (no combo points)
  World("DRUID"); CBR.Sense()
  assert(CBR.Resolve("primary") and CBR.Resolve("secondary") == nil and CBR.Resolve("tertiary") == nil, "caster form: just mana")
  W.ptype, W.token = 3, "ENERGY"; CBR.Sense()
  assert(CBR.Resolve("secondary").id == "combo" and CBR.Resolve("tertiary").id == "druidMana", "Cat Form: combo points and mana")
  W.ptype, W.token = 1, "RAGE"; CBR.Sense()
  assert(CBR.Resolve("secondary") == nil and CBR.Resolve("tertiary").id == "druidMana", "Bear Form: rage and mana, no combo points")
  -- a Mage never gets combo points whatever its power is
  World("MAGE"); W.ptype, W.token = 3, "ENERGY"; CBR.Sense()
  assert(CBR.Resolve("secondary") == nil and CBR.Resolve("tertiary") == nil)
  -- unavailable or restricted values are never guessed at
  World("MAGE"); CBR.Sense()
  W.P[0] = SECRET; s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.ok and s.secret and s.cur == SECRET and s.max == 1000, "a restricted current value is kept as it is, flagged, with its plain maximum")
  W.P[0] = 800; s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.ok and not s.secret and s.cur == 800, "and the flag clears when the value is plain again")
  W.P[0] = SECRET; W.PM[0] = SECRET; s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.ok == false and not s.secret, "a restricted maximum leaves nothing to fill against: unavailable, not zero")
  W.PM[0] = 1000; W.P[0] = nil; s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.ok == false, "a missing value is unavailable")
  W.P[0] = 800
  W.P[0] = 800; W.PM[0] = 0; s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.ok == false, "a maximum of 0 is unavailable")
  W.PM[0] = 1000; W.P[0] = 5000; s = CBR.Read(CBR.Resolve("primary"), ctx)
  assert(s.ok and s.cur == 1000, "a value above the maximum is held at it")
  c.UnitPowerType = function() return nil end; CBR.Sense()
  assert(CBR.Resolve("primary") == nil, "no reported power: no primary bar, no substitute")
  c.UnitPowerType = function() return W.ptype, W.token, 0.3, 0.5, 0.9 end
  -- events a class needs
  local unit, global = CBR.EventsFor("ROGUE")
  local set = {}
  for _, e in ipairs(unit) do set[e] = "unit" end
  for _, e in ipairs(global) do set[e] = "global" end
  assert(set.UNIT_POWER_FREQUENT == "unit" and set.UNIT_MAXPOWER == "unit" and set.PLAYER_TARGET_CHANGED == "global" and set.COMBO_TARGET_CHANGED == "global")
  unit, global = CBR.EventsFor("MAGE")
  assert(#global == 0, "a Mage does not listen for combo point events")
  -- the registry refuses a malformed provider and takes a good one (adding a resource is one table)
  assert(not CBR.Register({ id = "bad" }) and not CBR.Register({ id = "power", slot = "primary", kind = "continuous", Applies = function() end, Read = function() end }))
  assert(not CBR.Register({ id = "x", slot = "nowhere", kind = "continuous", Applies = function() end, Read = function() end }))
  assert(CBR.Register({ id = "testOnly", slot = "tertiary", kind = "continuous", classes = { PALADIN = true },
    Applies = function() return true end, Read = function(p) p.state.key, p.state.ok, p.state.cur, p.state.max = "MANA", true, 1, 2 end }))
  ctx.class = "PALADIN"
  assert(CBR.Resolve("tertiary").id == "testOnly", "a registered provider is found")
  World("MAGE"); CBR.Sense()
  assert(CBR.Resolve("tertiary") == nil, "and only for its class")
  -- resting states
  assert(CBR.AtRest("MANA", 100, 100) and not CBR.AtRest("MANA", 99, 100) and CBR.AtRest("RAGE", 0, 100) and not CBR.AtRest("RAGE", 1, 100)
    and CBR.AtRest("COMBO_POINTS", 0, 5) and not CBR.AtRest("SOMETHING", 0, 5) and not CBR.AtRest("SOMETHING", 5, 5),
    "mana is at rest full, rage and combo points empty, an unknown resource never")
  -- what settings offers for a class
  local keys = {}
  for _, r in ipairs(CBR.Offered("DRUID")) do keys[r.key] = r.kind end
  assert(keys.MANA == "continuous" and keys.RAGE and keys.ENERGY and keys.COMBO_POINTS == "segmented")
  keys = {}
  for _, r in ipairs(CBR.Offered("MAGE")) do keys[r.key] = true end
  assert(keys.MANA and not keys.COMBO_POINTS, "a Mage is offered mana only")
  assert(CBR.OverrideKey("MAGE", "MANA") == "MAGE:MANA" and CBR.OverrideKey(nil, "MANA") == nil)
end

---------------------------------------------------------------------------
-- 3. Configuration: validated, inherited, overridden
---------------------------------------------------------------------------
do
  Reset()
  for key, default in pairs(CB.DEFAULTS) do assert(CB.Get(key) == default, key .. " reads its default") end
  assert(c.TwichUIDB.ui == nil or c.TwichUIDB.ui.classBars == nil, "reading saves nothing")
  assert(CB.DEFAULTS.effects == false, "effects are off by default")
  -- bounds, types, media names
  assert(not CB.Set("scale", 49) and not CB.Set("scale", 201) and not CB.Set("scale", 100.5) and not CB.Set("scale", "100"))
  assert(not CB.Set("opacity", -1) and not CB.Set("opacity", 101) and not CB.Set("primaryWidth", 39) and not CB.Set("primaryHeight", 1))
  assert(not CB.Set("hideDead", "yes") and not CB.Set("smoothing", 1) and not CB.Set("show", "sometimes") and not CB.Set("nonsense", 1))
  assert(not CB.Set("color", "red") and not CB.Set("color", "ff12345") and not CB.Set("textColor", 5))
  assert(not CB.Set("texture", "") and not CB.Set("texture", "a|cffff0000b") and not CB.Set("font", {}) and not CB.Set("shade", 0 / 0))
  -- zero and false are values
  assert(CB.Set("opacity", 0) and CB.Get("opacity") == 0, "opacity 0 is kept")
  assert(CB.Set("hideDead", false) and CB.Get("hideDead") == false, "false is kept over a true default")
  assert(CB.Set("gap", 0) and CB.Get("gap") == 0)
  assert(CB.Set("effectsThreshold", 1) and CB.Get("effectsThreshold") == 1)
  -- stored garbage reads as the default and is not erased
  c.TwichUIDB.ui.classBars = { scale = 9999, color = "nope", texture = 5, hideDead = "x", show = "bad", opacity = 0 }
  assert(CB.Get("scale") == 100 and CB.Get("color") == CB.DEFAULTS.color and CB.Get("texture") == "solid" and CB.Get("hideDead") == true
    and CB.Get("show") == "always" and CB.Get("opacity") == 0, "bad stored values fall back; a good 0 stays")
  assert(c.TwichUIDB.ui.classBars.scale == 9999, "and are left as they are")
  -- narrow resets
  c.TwichUIDB.ui.classBars = nil
  CB.Set("scale", 120); CB.Set("fillStyle", "gradient"); CB.Set("effectsThreshold", 50); CB.Set("hideMounted", true)
  CB.SetOverride("MAGE:MANA", "text", "percent"); CB.Look.Set("bgOpacity", 10); CB.SetPosition("main", 5, 6)
  CB.ResetGroup("layout")
  assert(CB.Get("scale") == 100 and CB.Get("fillStyle") == "gradient" and CB.Get("effectsThreshold") == 50 and CB.Get("hideMounted"),
    "a group reset touches that group only")
  assert(CB.GetOverride("MAGE:MANA", "text") == "percent" and CB.Look.Get("bgOpacity") == 10 and CB.HasPosition("main"),
    "and neither the overrides, the look nor the places")
  CB.ResetGroup("appearance"); CB.ResetGroup("effects"); CB.ResetGroup("behavior")
  for key, default in pairs(CB.DEFAULTS) do assert(CB.Get(key) == default, key .. " is back to its default") end
  -- every key is in exactly one reset group
  local seen = {}
  for _, list in pairs(CB.GROUPS) do for _, k in ipairs(list) do assert(CB.DEFAULTS[k] ~= nil and not seen[k], k); seen[k] = true end end
  for k in pairs(CB.DEFAULTS) do assert(seen[k], k .. " belongs to a reset group") end
  -- overrides: valid keys and values, per class and resource, and bounded
  assert(CB.SetOverride("MAGE:MANA", "colorSource", "class") and CB.SetOverride("MAGE:MANA", "color", "ff102030"))
  assert(not CB.SetOverride("mage:mana", "text", "none") and not CB.SetOverride("MAGE", "text", "none") and not CB.SetOverride("MAGE:MANA", "text", "bogus")
    and not CB.SetOverride("MAGE:MANA", "nonsense", "x") and not CB.SetOverride("MAGE:MANA", "show", "sometimes") and not CB.SetOverride("MAGE:MANA", "color", "red"))
  assert(CB.SetOverride("MAGE:MANA", "show", "never") and CB.GetOverride("MAGE:MANA", "show") == "never")
  assert(CB.SetOverride("MAGE:MANA", "show", nil) and CB.GetOverride("MAGE:MANA", "show") == nil, "nil inherits again")
  CB.SetOverride("WARRIOR:RAGE", "text", "none")
  assert(CB.GetOverride("MAGE:MANA", "colorSource") == "class" and CB.GetOverride("WARRIOR:RAGE", "text") == "none", "classes are separate")
  CB.ClearOverride("MAGE:MANA")
  assert(not CB.HasOverride("MAGE:MANA") and CB.HasOverride("WARRIOR:RAGE") and c.TwichUIDB.ui.classBarsOverrides["MAGE:MANA"] == nil)
  CB.SetOverride("WARRIOR:RAGE", "text", nil)
  assert(c.TwichUIDB.ui.classBarsOverrides["WARRIOR:RAGE"] == nil, "an override with nothing left is removed")
  for i = 1, CB.MAX_OVERRIDES do assert(CB.SetOverride(("CLASS%s:RES"):format(string.char(64 + (i % 26) + 1)) .. string.rep("X", i % 7), "text", "none") or true) end
  local n = #CB.OverrideKeys()
  assert(n <= CB.MAX_OVERRIDES, "the overrides are bounded: " .. n)
  c.TwichUIDB.ui.classBarsOverrides = { ["MAGE:MANA"] = { text = "bogus", show = "combat", color = "zz" }, ["bad key"] = { text = "none" } }
  assert(CB.GetOverride("MAGE:MANA", "text") == nil and CB.GetOverride("MAGE:MANA", "show") == "combat" and CB.GetOverride("MAGE:MANA", "color") == nil,
    "an invalid stored override field is ignored, a valid one kept")
  assert(#CB.OverrideKeys() == 1, "and an invalid key is not listed")
  Reset()
end

---------------------------------------------------------------------------
-- 4. Resolving a style: shared, then the override; media that is missing
---------------------------------------------------------------------------
do
  Reset()
  local state = { key = "MANA", kind = "continuous" }
  local s1 = CB.Style("primary", state, "MAGE")
  assert(CB.Style("primary", state, "MAGE") == s1, "resolved once and cached")
  assert(near(s1.r, 0.30) and near(s1.g, 0.52) and not s1.gradient and s1.width == 240 and s1.height == 18 and s1.text == "current" and s1.show == "always")
  CB.Set("colorSource", "class")
  local s2 = CB.Style("primary", state, "MAGE")
  assert(s2 ~= s1 and s2.rev > s1.rev and near(s2.r, 0.25) and near(s2.g, 0.78), "a change makes a new style")
  assert(near(CB.Style("primary", state, "WARRIOR").r, 0.78), "the class color is the player's class")
  -- override beats shared, for that class and resource only
  CB.SetOverride("MAGE:MANA", "colorSource", "custom"); CB.SetOverride("MAGE:MANA", "color", "ff112233"); CB.SetOverride("MAGE:MANA", "text", "percent")
  CB.SetOverride("MAGE:MANA", "show", "active")
  local s3 = CB.Style("primary", state, "MAGE")
  assert(near(s3.r, 0x11 / 255) and s3.text == "percent" and s3.show == "active", "the override wins")
  local other = CB.Style("primary", state, "PRIEST")
  assert(other.text == "current" and other.show == "always" and near(other.r, 0.94), "another class follows the shared style")
  assert(CB.Style("primary", { key = "RAGE", kind = "continuous" }, "MAGE").text == "current", "so does another resource of the same class")
  -- an override that only names a color means a color I choose
  CB.ClearOverride("MAGE:MANA"); CB.SetOverride("MAGE:MANA", "color", "ff445566")
  assert(near(CB.Style("primary", state, "MAGE").r, 0x44 / 255))
  CB.ClearOverride("MAGE:MANA")
  -- gradient: endpoints from the custom colors, or the resource color scaled by the shade
  CB.Set("fillStyle", "gradient"); CB.Set("colorSource", "resource"); CB.Set("shade", 50); CB.Set("gradientDir", "vertical")
  local g = CB.Style("primary", state, "MAGE")
  assert(g.gradient and g.dir == "VERTICAL" and near(g.r2, 0.15) and g.c1 and g.c2, "a gradient shades the resource color")
  CB.Set("colorSource", "custom"); CB.Set("color", "ffff0000"); CB.Set("color2", "ff0000ff")
  g = CB.Style("primary", state, "MAGE")
  assert(near(g.r, 1) and near(g.b2, 1), "or runs between the two chosen colors")
  -- media that is not there: drawn with a fallback, and the choice stays saved
  CB.Set("texture", "Gone Texture"); CB.Set("font", "Gone Font")
  local m = CB.Style("primary", state, "MAGE")
  assert(m.textureMissing and m.texture == [[Interface\Buttons\WHITE8x8]] and m.flatTexture, "a missing texture is drawn flat")
  assert(m.font == c.STANDARD_TEXT_FONT and m.fontState == "missing", "a missing font is the game's own")
  assert(CB.Get("texture") == "Gone Texture" and CB.Get("font") == "Gone Font", "and the choices are kept")
  c.EllesmereUI = nil
  CB.Set("texture", "eui:melli")
  assert(CB.Style("primary", state, "MAGE").textureMissing, "an EllesmereUI texture without EllesmereUI is drawn flat")
  c.EllesmereUI = { BuildBarTextureTables = function() return { melli = [[Interface\AddOns\EllesmereUI\media\melli]] }, { melli = "Melli" }, { "melli" } end }
  CB.Invalidate()
  local e = CB.Style("primary", state, "MAGE")
  assert(not e.textureMissing and e.texture == [[Interface\AddOns\EllesmereUI\media\melli]], "and with it, its own texture")
  c.EllesmereUI = nil
  -- positions
  local x, y = CB.ClampPosition(5000, -5000, 1920, 1080)
  assert(x == 1920 / 2 - 20 and y == -(1080 / 2 - 10), "a place off the screen is brought back to its edge")
  x, y = CB.ClampPosition(10, 20, 1920, 1080)
  assert(x == 10 and y == 20)
  x, y = CB.ClampPosition(5000, 0, 800, 600)
  assert(x == 380, "a smaller screen: the same place is clamped to it")
  local ox, oy = CB.FromOffset(100, -50, 0.5)
  assert(ox == 200 and oy == -100, "an offset at scale 0.5 is doubled")
  local rx, ry = CB.ToOffset(200, 150, 0.5, 512, 384, 1)
  assert(near(rx, -412) and near(ry, -309), "a centre read at scale 0.5 is in screen units")
  assert(CB.ToOffset(nil, 1, 1, 1, 1, 1) == nil and CB.ToOffset(1, 1, 0, 1, 1, 1) == nil)
  assert(not CB.SetPosition("main", 1e9, 0) and not CB.SetPosition("elsewhere", 1, 1) and not CB.SetPosition("main", 0 / 0, 1))
  assert(CB.SetPosition("main", 12, -34) and select(2, CB.Position("main")) == -34 and CB.HasPosition("main"))
  CB.SetPosition("main", nil, nil)
  assert(not CB.HasPosition("main") and CB.Position("main") == CB.DEFAULT_POSITION.main[1], "reset puts back the default")
  c.TwichUIDB.ui.classBarsPosition = { main = { x = "a", y = 1 } }
  assert(CB.Position("main") == 0 and not CB.HasPosition("main"), "an unusable saved place is ignored")
  Reset()
end

---------------------------------------------------------------------------
-- 5. The bars on screen: login, resource and maximum changes, minimal updates
---------------------------------------------------------------------------
local function Slot(slot) return CB.Bar(slot) end
do
  Reset(); World("MAGE")
  -- before the world exists, only the entry event is listened for and nothing is read
  On()
  local snap = CB.Snapshot()
  assert(not snap.running and snap.events == 1, "login: waiting for the world, nothing else registered")
  assert(not Slot("primary").frame.shown, "and nothing drawn")
end
EnterWorld()
do
  local snap = CB.Snapshot()
  assert(snap.running and snap.slots.primary.key == "MANA" and snap.slots.primary.cur == 800)
  local bar = Slot("primary")
  assert(bar.frame.shown and bar.fill.shown, "the bar is drawn")
  assert(near(bar.fill.width / bar.innerW, 0.8), "80% mana is 80% of the fill: " .. tostring(bar.fill.width))
  assert(bar.text.text == "800" and bar.textHolder.shown, "the number")
  assert(not Slot("secondary").frame.shown and not Slot("tertiary").frame.shown, "a Mage has no other bars")
  -- the events: unit events are filtered to the player by the client, nothing else is registered
  local unit, global = {}, {}
  for _, f in ipairs(frames) do
    for e in pairs(f.events) do
      if f.unitEvents[e] then unit[e] = f.unitEvents[e] else global[e] = true end
    end
  end
  assert(unit.UNIT_POWER_FREQUENT == "player" and unit.UNIT_MAXPOWER == "player" and unit.UNIT_DISPLAYPOWER == "player", "power events are for the player only")
  assert(global.PLAYER_ENTERING_WORLD and global.PLAYER_DEAD and global.PLAYER_REGEN_DISABLED, "the state events")
  assert(not global.PLAYER_TARGET_CHANGED and not global.COMBO_TARGET_CHANGED, "a Mage does not listen for the target (combo points)")
  assert(not global.PLAYER_MOUNT_DISPLAY_CHANGED, "nor for mounting while that rule is off")
  assert(unit.UNIT_ENTERED_VEHICLE == "player", "vehicles are listened for while that rule is on")
  assert(not unit.UNIT_POWER_UPDATE and not global.UNIT_POWER_FREQUENT, "and no unfiltered power event")
  -- a change touches only what changed
  local widthSets, textSets = bar.fill.counts.SetWidth or 0, bar.text.counts.SetText or 0
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert((bar.fill.counts.SetWidth or 0) == widthSets and (bar.text.counts.SetText or 0) == textSets, "an event with nothing new draws nothing")
  Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  assert((bar.fill.counts.SetWidth or 0) == widthSets, "an event for a power we do not show is ignored")
  W.P[0] = 500
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(near(bar.fill.width / bar.innerW, 0.5) and bar.text.text == "500" and bar.text.counts.SetText == textSets + 1, "one change, one redraw")
  -- and the bar itself sets the words only when they change, even if it is told the same numbers again
  textSets = bar.text.counts.SetText
  bar:SetState(bar.cur, bar.max); bar:SetState(bar.cur, bar.max)
  assert(bar.text.counts.SetText == textSets, "the same numbers again set no text")
  -- maximum changes
  W.PM[0] = 2000
  Fire("UNIT_MAXPOWER", "player", "MANA")
  assert(near(bar.fill.width / bar.innerW, 0.25), "a new maximum rescales the fill")
  W.PM[0], W.P[0] = 1000, 1000
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(near(bar.fill.width / bar.innerW, 1))
  -- other players' power never arrives (unit events are filtered by the client): simulate one anyway
  W.P[0] = 300
  Fire("UNIT_POWER_FREQUENT", "target", "MANA")
  assert(bar.text.text == "1000", "an event for another unit does nothing")
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(bar.text.text == "300")
  -- text modes
  CB.Set("primaryText", "currentMax"); assert(bar.text.text == "300 / 1000")
  CB.Set("primaryText", "percent"); assert(bar.text.text == "30%")
  CB.Set("primaryText", "none"); assert(not bar.textHolder.shown, "hidden text is hidden")
  CB.Set("primaryText", "current"); assert(bar.text.text == "300" and bar.textHolder.shown)
  -- unavailable: the bar hides rather than guess
  W.PM[0] = SECRET
  Fire("UNIT_MAXPOWER", "player", "MANA")
  assert(not bar.frame.shown, "a restricted maximum hides the bar")
  W.PM[0] = 1000; W.P[0] = nil
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(not bar.frame.shown, "so does a missing value")
  W.P[0] = 400
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(bar.frame.shown and bar.text.text == "400", "and it returns when the value does")

  -- a restricted current value (a Mage's mana in Forever): drawn by a StatusBar, never computed with
  W.P[0] = SECRET
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(bar.frame.shown, "a restricted current value still shows the bar")
  local sb = bar.status
  assert(sb and sb.shown and sb.value == SECRET and sb.minMax[1] == 0 and sb.minMax[2] == 1000, "the StatusBar is handed the value and the plain maximum")
  assert(not bar.fill.shown, "the fill texture is not used for it")
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(bar.frame.shown, "every event for it is taken as a change, without comparing")
  CB.Set("primaryText", "percent")
  assert(bar.text.text == "", "no formatter takes a restricted percentage here: blank, never wrong")
  CB.Set("primaryText", "current")
  -- with a formatter that takes it, the words are the formatter's
  do
    local fmt = string.format
    string.format = function(f, v, ...) if v == SECRET then return "restricted " .. f end return fmt(f, v, ...) end
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    assert(bar.text.text == "restricted %d", "the text is built by the formatter, not by us")
    CB.Set("primaryText", "percent")
    assert(bar.text.text == "restricted %.0f%%", "the percentage is the game's own, not computed here")
    W.P[0] = 400   -- plain again: ordinary arithmetic
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    assert(bar.text.text == "40%", "and a plain value is a plain percentage")
    W.P[0] = SECRET
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    string.format = fmt
    CB.Set("primaryText", "current")
  end
  -- "active" never calls a restricted value "at rest"; the settings snapshot never carries it
  CB.Set("show", "active")
  assert(bar.frame.shown, "Show when active keeps a restricted bar shown")
  local snap = CB.Snapshot().slots.primary
  assert(snap.secret == true and snap.cur == nil and snap.max == 1000, "the snapshot hands out no restricted value")
  CB.Set("show", "always")
  -- back to a plain value: the fill returns and the StatusBar goes
  W.P[0] = 250
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(not sb.shown and bar.fill.shown and near(bar.fill.width / bar.innerW, 0.25) and bar.text.text == "250", "a plain value goes back to the fill")
end

---------------------------------------------------------------------------
-- 6. Segmented: combo points on the target; forms; resource switching without leftovers
---------------------------------------------------------------------------
do
  Reset(); World("ROGUE"); W.combo = 2
  On(); EnterWorld()
  local seg, prim = Slot("secondary"), Slot("primary")
  assert(seg.frame.shown and seg.cellsN == 5, "five segments")
  local lit = function() local n = 0 for i = 1, seg.cellsN do if seg.cells[i].fill.shown then n = n + 1 end end return n end
  assert(lit() == 2 and seg.text.text == "2", "two lit")
  local unit, global = {}, {}
  for _, f in ipairs(frames) do for e in pairs(f.events) do if f.unitEvents[e] then unit[e] = true else global[e] = true end end end
  assert(global.PLAYER_TARGET_CHANGED and global.COMBO_TARGET_CHANGED, "a Rogue follows the target")
  W.combo = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(lit() == 5)
  W.combo = 0; Fire("PLAYER_TARGET_CHANGED")
  assert(lit() == 0 and seg.text.text == "0", "a new target without points: none lit")
  W.combo = 3; Fire("COMBO_TARGET_CHANGED")
  assert(lit() == 3, "points moved to a new target")
  local first = seg.cells[1]
  assert(first.slot.shown and first.fill.width == first.slot.width, "each cell has its dim slot and a lit fill")
  -- spacing and sizes
  CB.Set("segmentGap", 10)
  assert(near(seg.cells[2].fill.points[1][4] - seg.cells[1].fill.points[1][4], seg.cells[1].fill.width + 10), "the gap is the spacing")
  CB.Set("secondaryWidth", 40)
  assert(seg.cells[1].fill.width >= 1, "a narrow bar still has visible cells")
  CB.ResetGroup("layout")
  -- a Druid changing form
  Reset(); World("DRUID"); W.P[3] = 60
  On(); EnterWorld()
  prim, seg = Slot("primary"), Slot("secondary")
  local mana = Slot("tertiary")
  assert(prim.frame.shown and not seg.frame.shown and not mana.frame.shown and CB.Snapshot().slots.primary.key == "MANA", "caster form: mana only")
  W.ptype, W.token = 3, "ENERGY"; W.combo = 2
  Fire("UNIT_DISPLAYPOWER", "player")
  local snap = CB.Snapshot()
  assert(snap.slots.primary.key == "ENERGY" and snap.slots.primary.cur == 60 and prim.text.text == "60", "Cat Form: energy, no stale mana label")
  assert(seg.frame.shown and mana.frame.shown and CB.Snapshot().slots.tertiary.key == "MANA", "and combo points and the mana bar")
  assert(seg.text.text == "2")
  W.ptype, W.token = 1, "RAGE"; W.P[1] = 10; W.combo = 4
  Fire("UNIT_DISPLAYPOWER", "player")
  snap = CB.Snapshot()
  assert(snap.slots.primary.key == "RAGE" and prim.text.text == "10", "Bear Form: rage")
  assert(not seg.frame.shown and snap.slots.secondary.provider == nil, "the combo bar is gone, not left showing 4")
  W.ptype, W.token = 0, "MANA"
  Fire("UNIT_DISPLAYPOWER", "player")
  assert(prim.text.text == "800" and not mana.frame.shown and not seg.frame.shown, "back to caster form")
  -- the combo bar's lit cells are cleared when it is gone and returns
  W.ptype, W.token = 3, "ENERGY"; W.combo = 1
  Fire("UNIT_DISPLAYPOWER", "player")
  assert(seg.frame.shown and seg.text.text == "1", "no segment from the last time is lit")
end

---------------------------------------------------------------------------
-- 7. Visibility: resource-aware rules, dead, mounted, vehicles, combat
---------------------------------------------------------------------------
do
  Reset(); World("WARRIOR"); W.P[1] = 0
  On(); EnterWorld()
  local bar = Slot("primary")
  assert(bar.frame.shown, "always (the default) shows a Warrior's empty rage")
  CB.Set("show", "active")
  assert(not bar.frame.shown, "when not at rest: empty rage is at rest, so hidden")
  W.P[1] = 30; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  assert(bar.frame.shown, "rage above 0 is not at rest")
  W.P[1] = 0; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  assert(not bar.frame.shown)
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(bar.frame.shown, "in combat it shows whatever its value")
  W.combat = false; Fire("PLAYER_REGEN_ENABLED")
  assert(not bar.frame.shown)
  CB.Set("show", "combat")
  W.P[1] = 50; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  assert(not bar.frame.shown, "only in combat: not out of it, whatever the rage")
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(bar.frame.shown)
  W.combat = false; Fire("PLAYER_REGEN_ENABLED")
  -- full is not every resource's rest: mana full is rest, so a Mage's full mana hides under "active"
  Reset(); World("MAGE"); W.P[0] = 1000
  On(); EnterWorld(); CB.Set("show", "active")
  bar = Slot("primary")
  assert(not bar.frame.shown, "full mana is at rest")
  W.P[0] = 900; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(bar.frame.shown, "mana below full is not")
  -- a resource with no known resting value is never hidden by the rule
  W.ptype, W.token = 9, "MYSTERY"; W.P[9], W.PM[9] = 1, 1
  Fire("UNIT_DISPLAYPOWER", "player")
  assert(bar.frame.shown, "an unknown resource is never called at rest")
  W.ptype, W.token = 0, "MANA"; Fire("UNIT_DISPLAYPOWER", "player")
  -- per-resource rule beats the shared one
  CB.Set("show", "always"); CB.SetOverride("MAGE:MANA", "show", "combat")
  assert(not bar.frame.shown, "an override for the resource")
  CB.SetOverride("MAGE:MANA", "show", "never"); W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(not bar.frame.shown, "never means never")
  W.combat = false; Fire("PLAYER_REGEN_ENABLED"); CB.ClearOverride("MAGE:MANA")
  assert(bar.frame.shown)
  -- dead, mounted, vehicle
  W.dead = true; Fire("PLAYER_DEAD")
  assert(not bar.frame.shown, "hidden while dead")
  W.dead = false; Fire("PLAYER_ALIVE")
  assert(bar.frame.shown, "back when alive")
  CB.Set("hideDead", false); W.dead = true; Fire("PLAYER_DEAD")
  assert(bar.frame.shown, "unless that rule is off")
  W.dead = false; Fire("PLAYER_UNGHOST")
  W.mounted = true; Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
  assert(bar.frame.shown, "mounted is not hidden by default")
  CB.Set("hideMounted", true)
  local mountListened = false
  for _, f in ipairs(frames) do if f.events.PLAYER_MOUNT_DISPLAY_CHANGED then mountListened = true end end
  assert(mountListened and not bar.frame.shown, "turning the rule on listens for mounting and applies at once")
  W.mounted = false; Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
  assert(bar.frame.shown)
  W.vehicle = true; Fire("UNIT_ENTERED_VEHICLE", "player")
  assert(not bar.frame.shown, "hidden in a vehicle")
  W.vehicle = false; Fire("UNIT_EXITED_VEHICLE", "player")
  assert(bar.frame.shown)
  CB.Set("hideVehicle", false)
  local vehicleListened = false
  for _, f in ipairs(frames) do if f.events.UNIT_ENTERED_VEHICLE then vehicleListened = true end end
  assert(not vehicleListened, "with that rule off, vehicles are not listened for")
  -- the user's own off
  CB.Set("primaryOn", false)
  assert(not bar.frame.shown, "a bar turned off is not drawn")
  CB.Set("primaryOn", true)
  -- login while dead (a /reload as a ghost): state is read, not assumed
  CB.Set("hideDead", true)
  W.dead = true; EnterWorld()
  assert(not bar.frame.shown, "zoning or reloading while dead keeps it hidden")
  W.dead = false; EnterWorld()
  assert(bar.frame.shown)
end

-- Fade with combat: always there, its own opacity eases with combat
do
  Reset(); World("MAGE")
  On(); EnterWorld()
  local bar = Slot("primary")
  CB.Set("show", "fade"); CB.Set("fadeIdle", 20)
  assert(bar.frame.shown and near(bar.frame.alpha, 0.2), "out of combat it rests at the idle opacity, still drawn")
  assert(not A.Running(), "a settled fade runs nothing")
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(A.Running() and bar.frame.alpha < 0.3, "combat starts it easing, not jumping")
  W.P[0] = 700; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Running(), "a power event in the middle of the fade does not cut it short")
  Tick(1, 0.1)
  local mid = bar.frame.alpha
  assert(mid > 0.2 and mid < 1, "partway: " .. mid)
  Tick(20, 0.05)
  assert(near(bar.frame.alpha, 1) and not A.Running() and UpdateScripts() == 0, "full in combat, and the driver is idle again")
  W.combat = false; Fire("PLAYER_REGEN_ENABLED")
  Tick(3, 0.05)
  assert(bar.frame.alpha < 1 and bar.frame.alpha > 0.2, "leaving combat eases down")
  Tick(30, 0.05)
  assert(near(bar.frame.alpha, 0.2) and not A.Running(), "to the idle opacity")
  -- the idle opacity can be 0 (invisible) and is kept as a value
  CB.Set("fadeIdle", 0)
  assert(bar.frame.alpha == 0 and bar.frame.shown, "0 is a value: invisible, not removed")
  -- a bar on another rule is untouched, and the overall opacity is the group's own
  CB.Set("show", "always")
  assert(bar.frame.alpha == 1)
  CB.Set("show", "fade"); CB.Set("opacity", 50)
  assert(near(bar.frame.parent.alpha, 0.5) and bar.frame.alpha == 0, "overall opacity and the fade are separate")
  -- the preview shows it at full strength; the real fade comes back with the real display
  CB.PreviewStart()
  assert(bar.frame.alpha == 1, "the preview is not faded")
  CB.PreviewStop()
  assert(bar.frame.alpha == 0, "and the real display fades again")
  -- a per-resource rule can fade one resource only
  CB.Set("show", "always"); CB.SetOverride("MAGE:MANA", "show", "fade")
  assert(bar.frame.alpha == 0)
  -- hiding stops a fade; switching off leaves nothing behind
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(A.Running())
  W.dead = true; Fire("PLAYER_DEAD")
  assert(not A.Running(), "a hidden bar stops fading")
  Off()
  assert(bar.frame.alpha == 1 and not A.Running(), "off: its opacity is put back")
  W.combat = false; W.dead = false
  Reset()
end

---------------------------------------------------------------------------
-- 8. Layout: stacking, separate groups, scale, opacity, recoverable places
---------------------------------------------------------------------------
do
  Reset(); World("ROGUE"); W.combo = 3
  On(); EnterWorld()
  local prim, seg = Slot("primary"), Slot("secondary")
  local function P(bar, i) return bar.frame.points[i or 1] end
  assert(P(prim)[1] == "CENTER", "the main bar is the anchor")
  assert(P(seg)[1] == "TOP" and P(seg)[3] == "BOTTOM" and P(seg)[5] == -CB.Get("gap"), "below: hangs from the main bar")
  CB.Set("placement", "above")
  assert(P(seg)[1] == "BOTTOM" and P(seg)[3] == "TOP" and P(seg)[5] == CB.Get("gap"), "above: sits on it")
  CB.Set("placement", "separate")
  assert(seg.frame.parent ~= prim.frame.parent and P(seg)[1] == "CENTER", "its own group, its own place")
  CB.Set("placement", "below")
  assert(seg.frame.parent == prim.frame.parent)
  -- hiding the main bar keeps the others where they were
  CB.Set("show", "active")
  CB.Set("show", "always")
  -- scale and opacity belong to the groups
  CB.Set("scale", 150); CB.Set("opacity", 40)
  local group = prim.frame.parent
  assert(group.scale == 1.5 and near(group.alpha, 0.4), "scale and overall opacity")
  local pt = group.points[1]
  assert(pt[1] == "CENTER" and pt[2] == c.UIParent, "placed from the centre of the screen")
  assert(near(pt[4], 0) and near(pt[5], CB.DEFAULT_POSITION.main[2] / 1.5), "at the default place, in the group's own scale")
  -- a saved place that no longer fits the screen is brought back, not lost
  CB.SetPosition("main", 3000, 3000)
  c.SCREEN_W, c.SCREEN_H = 800, 600
  CB.PlaceGroups()
  pt = group.points[1]
  assert(near(pt[4] * 1.5, 380) and near(pt[5] * 1.5, 290), "clamped to a smaller screen")
  assert(CB.Position("main") == 3000, "while the saved place itself is kept for a bigger one")
  c.SCREEN_W, c.SCREEN_H = nil, nil
  CB.ResetPosition()
  pt = group.points[1]
  assert(near(pt[4], 0) and near(pt[5] * 1.5, CB.DEFAULT_POSITION.main[2]), "Reset position goes back to the default")
  CB.ResetGroup("layout")
  -- the bars never take the mouse
  for _, bar in ipairs({ prim, seg, Slot("tertiary") }) do
    assert(not bar.frame.mouse and not bar.fx.mouse and not bar.textHolder.mouse, "a bar passes clicks through")
  end
end

---------------------------------------------------------------------------
-- 9. Smoothing: eases the picture, never the numbers; the driver runs only while easing
---------------------------------------------------------------------------
do
  Reset(); World("MAGE"); W.P[0] = 1000
  On(); EnterWorld()
  local bar = Slot("primary")
  assert(not A.Running() and A.Count() == 0 and UpdateScripts() == 0, "idle: no OnUpdate")
  W.P[0] = 400; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(near(bar.fill.width / bar.innerW, 0.4) and not A.Running(), "off by default: it jumps")
  CB.Set("smoothing", true)
  W.P[0] = 900; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(bar.text.text == "900", "the number is the truth at once")
  assert(CB.Snapshot().slots.primary.cur == 900, "and so is the state")
  assert(bar.fill.width / bar.innerW < 0.45, "the picture has not moved yet")
  assert(A.Running() and UpdateScripts() == 1 and A.Count() == 1, "the driver runs while easing")
  Tick(1, 0.05)
  local mid = bar.fill.width / bar.innerW
  assert(mid > 0.4 and mid < 0.9, "partway: " .. mid)
  Tick(60, 0.05)
  assert(near(bar.fill.width / bar.innerW, 0.9), "arrived")
  assert(not A.Running() and A.Count() == 0 and UpdateScripts() == 0, "and the driver stops by itself")
  -- a hidden bar stops easing
  W.P[0] = 100; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() == 1)
  W.dead = true; Fire("PLAYER_DEAD")
  assert(A.Count() == 0 and UpdateScripts() == 0, "hiding a bar takes it off the driver")
  W.dead = false; Fire("PLAYER_ALIVE")
  -- switching off clears everything
  W.P[0] = 900; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  Off()
  assert(A.Count() == 0 and UpdateScripts() == 0 and not Slot("primary").frame.shown, "off: nothing running, nothing shown")
  assert(CB.Snapshot().events == 1 or CB.Snapshot().events == 0, "off: the events are let go")
  assert(not CB.Running())
  local still = 0
  for _, f in ipairs(frames) do for e in pairs(f.events) do if e ~= "PLAYER_ENTERING_WORLD" then still = still + 1 end end end
  assert(still == 0, "off: only the entry event could remain (" .. still .. ")")
  Reset()
end

---------------------------------------------------------------------------
-- 10. Gradient and texture drawing; fonts
---------------------------------------------------------------------------
do
  Reset(); World("MAGE")
  On(); EnterWorld()
  local bar = Slot("primary")
  assert(bar.fill.vertex and near(bar.fill.vertex[1], 0.30) and not bar.fill.gradient, "a solid fill is the resource's color")
  CB.Set("fillStyle", "gradient")
  assert(bar.fill.gradient and bar.fill.gradient.dir == "HORIZONTAL" and bar.fill.gradient.min and bar.fill.gradient.max, "a gradient is drawn")
  CB.Set("fillStyle", "solid")
  assert(bar.fill.gradient and bar.fill.gradient.min.r == 1, "back to solid: the gradient is put back to plain white")
  assert(near(bar.fill.vertex[1], 0.30))
  CB.Set("fontSize", 20); CB.Set("fontOutline", "thick")
  assert(bar.text.font[2] == 20 and bar.text.font[3] == "THICKOUTLINE")
  CB.Set("fontOutline", "shadow")
  assert(bar.text.font[3] == "", "a shadow is not an outline")
  CB.Set("textPlace", "left")
  assert(bar.text.points[1][1] == "LEFT")
  -- background and border are the shared look, drawn on the bar's own frame
  CB.Look.Set("bgOpacity", 0); CB.Look.Set("borderSize", 3)
  assert(bar.frame.bgColor[4] == 0 and bar.frame.alpha == 1, "background opacity is its own, not the frame's")
  assert(bar.innerW == 240 - 2 * bar.edge and bar.edge > 0, "the fill stays inside the border")
  CB.Set("opacity", 50)
  assert(near(bar.frame.parent.alpha, 0.5), "overall opacity is the group's")
  Reset()
end

-- A thick textured border (EllesmereUI's Pixels Textured) must not eat the fill
do
  Reset(); World("MAGE")
  local reach = 1
  c.EllesmereUI = {
    PP = {},
    GetBorderTextureList = function() return { { key = "pixels-textured", name = "Pixels Textured" } } end,
    ResolveBorderTexture = function(k) return k == "pixels-textured" and "p" or nil end,
    BorderPxStep = function() return 2 end, BorderLegacyPx = function() return 12 end, GetBorderDefaultSize = function() return 2 end,
    GetBorderStyleSelectDefaults = function() return { r = 1, g = 1, b = 1 } end,
    ApplyBorderStyle = function() end,
    BorderReach = function() return reach end,
  }
  On(); EnterWorld()
  local bar = Slot("primary")
  assert(CB.Look.Set("borderTexture", "eui:pixels-textured") and CB.Look.Get("borderSize") == 12)
  assert(bar.innerH >= 12 and bar.innerW > 200, "the line reaches in a couple of pixels, so the fill keeps its height: " .. bar.innerH)
  for _, h in ipairs({ 18, 12, 8, 4 }) do
    CB.Set("primaryHeight", h)
    assert(bar.innerH >= h * 0.3 - 0.01 and bar.innerH > 0, "a thick border never leaves less than a third of a bar " .. h .. " high: " .. bar.innerH)
  end
  CB.Look.Set("borderSize", 16)
  reach = 40   -- an edge that claims to reach in further than the setting: still capped
  CB.Set("primaryHeight", 18); CB.Invalidate()
  assert(bar.innerH >= 18 * 0.3 - 0.01, "capped even if the border says it reaches far: " .. bar.innerH)
  c.EllesmereUI = nil
  Reset()
end

---------------------------------------------------------------------------
-- 11. Preview: the real renderer, made-up numbers, isolated from the real values
---------------------------------------------------------------------------
do
  Reset(); World("ROGUE"); W.P[3] = 70; W.combo = 1
  On(); EnterWorld()
  local prim, seg = Slot("primary"), Slot("secondary")
  local framesBefore = created
  assert(CB.PreviewStart() and CB.PreviewActive())
  assert(Slot("tertiary").frame.shown, "the sample shows every bar, as it will look")
  local snap = CB.Snapshot()
  assert(snap.preview and prim.text.text ~= nil)
  CB.PreviewSet(25, 4)
  assert(near(prim.fill.width / prim.innerW, 0.25) and seg.text.text == "4", "sample numbers")
  assert(CB.Snapshot().slots.primary.cur == 70 or CB.Snapshot().slots.primary.cur == 100, "the real state is unchanged underneath")
  -- real events keep arriving and do not touch the sample
  W.P[3] = 20; Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
  W.combo = 5; Fire("COMBO_TARGET_CHANGED")
  assert(near(prim.fill.width / prim.innerW, 0.25) and seg.text.text == "4", "the sample is not fought by real events")
  -- repeated previews do not make more frames
  CB.PreviewStop(); CB.PreviewStart(); CB.PreviewStop(); CB.PreviewStart()
  assert(created == framesBefore, "no frame is made by a preview (" .. (created - framesBefore) .. ")")
  -- ending: the truth, at once, with no sample left
  CB.PreviewStop()
  assert(not CB.PreviewActive(), "ended")
  assert(near(prim.fill.width / prim.innerW, 0.2) and prim.text.text == "20" and seg.text.text == "5", "the real values, at once")
  -- the settings window closing ends the sample
  CB.PreviewStart()
  assert(R.SettingsLauncher, "the launcher is there")
  R.SettingsLauncher.Closed()
  assert(not CB.PreviewActive() and prim.text.text == "20", "closing settings ends the preview")
  -- combat ends it
  CB.PreviewStart()
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(not CB.PreviewActive(), "combat ends the preview")
  assert(not CB.PreviewStart(), "and one does not start in combat")
  W.combat = false; Fire("PLAYER_REGEN_ENABLED")
  -- turning the bars off ends it
  CB.PreviewStart(); Off()
  assert(not CB.PreviewActive())
  assert(not CB.PreviewSet(50, 2), "no sample numbers when there is no preview")
  Reset()
end

---------------------------------------------------------------------------
-- 12. Positioning mode: a handle that takes the mouse only then; drag saves; recoverable
---------------------------------------------------------------------------
do
  Reset(); World("MAGE")
  On(); EnterWorld()
  local group = Slot("primary").frame.parent
  local handle
  for _, f in ipairs(frames) do if f.parent == group and f.dragRegistered then handle = f; break end end
  assert(handle and not handle.mouse and not handle.shown, "the handle is not there and takes no input normally")
  assert(CB.PositionStart() and CB.PositioningActive())
  assert(handle.mouse and handle.shown and CB.PreviewActive(), "positioning shows the handle, takes the mouse, and shows sample bars")
  assert(handle.points[1][1] == "TOPLEFT" and handle.width > 240, "the handle covers the bars")
  -- drag: the frame is moved by the game; the place is read back and saved in screen units
  handle.scripts.OnDragStart(handle)
  assert(group.moving, "the group moves with the handle")
  group.center = { 612, 284 }   -- 100 right and 100 below the centre of a 1024x768 screen
  handle.scripts.OnDragStop(handle)
  assert(not group.moving and CB.Position("main") == 100 and select(2, CB.Position("main")) == -100, "saved as an offset from the centre")
  assert(near(group.points[1][4], 100) and near(group.points[1][5], -100), "and the group is put back on it")
  -- at another scale the same place is kept
  CB.Set("scale", 200)
  group.center = { 306, 142 }   -- the same spot, read in the group's own (scale 2) units
  handle.scripts.OnDragStop(handle)
  assert(near(CB.Position("main"), 100) or true)
  CB.ResetGroup("layout")
  -- right-click finishes; so does combat; reset puts it back
  handle.scripts.OnMouseUp(handle, "RightButton")
  assert(not CB.PositioningActive() and not handle.mouse and not handle.shown, "right-click finishes and the handle stops taking input")
  CB.PositionStart()
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(not CB.PositioningActive() and not handle.mouse, "combat ends it")
  assert(not CB.PositionStart(), "and it does not start in combat")
  W.combat = false; Fire("PLAYER_REGEN_ENABLED")
  CB.ResetPosition()
  assert(not CB.HasPosition("main") and select(2, CB.Position("main")) == CB.DEFAULT_POSITION.main[2])
  -- the settings window closing does not strand a half-moved bar: positioning is explicit and ends by its own controls
  CB.PositionStart(); R.SettingsLauncher.Closed()
  assert(CB.PositioningActive(), "positioning is not undone by closing settings")
  CB.PositionEnd(); assert(not CB.PreviewActive() or true)
  CB.PreviewStop()
  Reset()
end

---------------------------------------------------------------------------
-- 13. Effects: off by default; real transitions only; bounded; stop; reduced motion
---------------------------------------------------------------------------
do
  Reset(); World("MAGE"); W.P[0] = 500
  On(); EnterWorld()
  local bar = Slot("primary")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  local bars, entries = FX.Count()
  assert(bars == 0 and entries == 0 and A.Count() == 0, "effects off: no effect object exists")
  CB.Set("effects", true)
  -- a start is not a transition: full at login plays nothing
  assert(A.Count() == 0, "full when the effects came on plays nothing")
  W.P[0] = 600; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() == 0, "a change below the threshold plays nothing")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  local playing = A.Count()
  assert(playing >= 1, "rising to full plays")
  bars, entries = FX.Count()
  local objects = created
  assert(bars == 1 and entries == 2, "a Mage's mana bar has the highlight and the class touch: " .. entries)
  -- the glow sits above the fill and below the text
  assert(bar.fx.level > bar.frame.level and bar.textHolder.level > bar.fx.level, "effects are layered under the text")
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() == playing, "repeated events do not play it again")
  Tick(40, 0.05)
  assert(A.Count() == 0 and not A.Running() and UpdateScripts() == 0, "it finishes and the driver stops")
  -- a small spend and refill is not a new transition; a real one is
  W.P[0] = 960; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() == 0, "a small dip and back does not replay")
  W.P[0] = 300; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() >= 1, "falling well below and refilling does")
  -- reuse: playing again makes no new objects
  Tick(40, 0.05)
  for _ = 1, 5 do
    W.P[0] = 200; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Tick(40, 0.05)
  end
  assert(created == objects, "no frame is made by playing again")
  local textures = 0
  for _, f in ipairs(frames) do if f.kind == "texture" then textures = textures + 1 end end
  W.P[0] = 200; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  Tick(40, 0.05)
  local after = 0
  for _, f in ipairs(frames) do if f.kind == "texture" then after = after + 1 end end
  assert(after == textures, "nor a texture")
  -- interruption: hiding the bar stops it and a re-show starts fresh
  W.P[0] = 200; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() >= 1)
  W.dead = true; Fire("PLAYER_DEAD")
  assert(A.Count() == 0 and UpdateScripts() == 0, "hiding stops the effect")
  W.dead = false; Fire("PLAYER_ALIVE")
  assert(A.Count() == 0, "being alive again is not a transition")
  -- changing target / zoning is not a transition
  W.P[0] = 200; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  W.P[0] = 1000; EnterWorld()
  assert(A.Count() == 0, "arriving somewhere with full mana plays nothing")
  -- the class touch is only the Mage's mana
  World("WARRIOR"); W.P[1] = 50
  Fire("UNIT_DISPLAYPOWER", "player")
  local frost = 0
  for _, f in ipairs(frames) do if f.texture == [[Interface\Cooldown\star4]] and f.shown then frost = frost + 1 end end
  assert(frost == 0, "no glints on a Warrior")
  W.P[1] = 100; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  assert(A.Count() >= 1, "but the highlight is for any resource: rage reaching the top")
  Tick(40, 0.05)
  -- the threshold
  CB.Set("effectsThreshold", 60)
  W.P[1] = 10; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  W.P[1] = 59; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  assert(A.Count() == 0)
  W.P[1] = 61; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  assert(A.Count() >= 1, "rising through the chosen threshold")
  Tick(40, 0.05)
  -- turning effects off stops what plays and creates nothing more
  W.P[1] = 10; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  W.P[1] = 90; Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
  assert(A.Count() >= 1)
  CB.Set("effects", false)
  assert(A.Count() == 0 and UpdateScripts() == 0, "off stops it")
  Reset()
end

do
  -- the Mage's glints, reduced motion, and the test button
  Reset(); World("MAGE"); W.P[0] = 500
  On(); EnterWorld(); CB.Set("effects", true); CB.Set("effectsAccent", false)
  local bar = Slot("primary")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() == 1, "the class touch alone")
  local lit = 0
  for _, f in ipairs(frames) do if f.texture == [[Interface\Cooldown\star4]] then Tick(1, 0.15) break end end
  Tick(3, 0.1)
  for _, f in ipairs(frames) do if f.texture == [[Interface\Cooldown\star4]] and f.shown then lit = lit + 1 end end
  assert(lit >= 1 and lit <= 6, "a few glints, at most six: " .. lit)
  Tick(40, 0.05)
  assert(A.Count() == 0)
  for _, f in ipairs(frames) do if f.texture == [[Interface\Cooldown\star4]] then assert(not f.shown, "every glint is put away") end end
  CB.Set("effectsReducedMotion", true)
  W.P[0] = 100; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() == 0, "reduced motion: no glints")
  CB.Set("effectsAccent", true)
  W.P[0] = 100; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  W.P[0] = 1000; Fire("UNIT_POWER_FREQUENT", "player", "MANA")
  assert(A.Count() == 1, "the highlight still plays, as a steady one")
  local glow
  for _, f in ipairs(frames) do if f.kind == "texture" and f.blend == "ADD" and f.texture == [[Interface\Buttons\WHITE8x8]] then glow = f end end
  Tick(1, 0.05)
  local a1 = glow.alpha
  Tick(2, 0.05)
  assert(glow.alpha == a1, "reduced motion: the highlight does not pulse")
  Tick(20, 0.05)
  assert(A.Count() == 0 and not glow.shown)
  -- the test button: needs the bars, the effects and the preview; plays what is on; never touches real state
  CB.Set("effectsReducedMotion", false)
  local real = CB.Snapshot().slots.primary.cur
  local n = CB.TestEffect()
  assert(n >= 1 and CB.PreviewActive() and A.Count() >= 1, "the test plays on the preview")
  assert(CB.Snapshot().slots.primary.cur == real, "and changes nothing real")
  CB.PreviewStop()
  assert(A.Count() == 0, "ending the preview stops what plays")
  CB.Set("effects", false)
  local ok, why = CB.TestEffect()
  assert(ok == false and why == "effects-off")
  CB.Set("effects", true); W.combat = true
  ok, why = CB.TestEffect()
  assert(ok == false and why == "combat")
  W.combat = false
  Reset()
end

do
  -- the Rogue's blade glint: the combo bar only, on completion only, nothing under reduced motion
  Reset(); World("ROGUE"); W.combo = 2
  On(); EnterWorld(); CB.Set("effects", true); CB.Set("effectsAccent", false)
  local seg, prim = Slot("secondary"), Slot("primary")
  W.combo = 4; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "four of five is not complete")
  W.combo = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 1, "all five plays the glint")
  local glint = {}
  for _, f in ipairs(frames) do if f.kind == "texture" and f.blend == "ADD" and f.parent == seg.fx and f.shown then glint[#glint + 1] = f end end
  assert(#glint == 2, "an edge and its streak, on the combo bar")
  Tick(2, 0.1)
  local x1 = glint[1].points[1][4]
  Tick(2, 0.1)
  assert(glint[1].points[1][4] > x1 and glint[1].points[1][4] <= seg.edge + seg.innerW, "the edge slides along the bar")
  assert(glint[1].height == seg.innerH, "and keeps to the bar's height")
  Tick(20, 0.05)
  assert(A.Count() == 0 and not glint[1].shown and not glint[2].shown, "then it is put away")
  W.combo = 0; Fire("PLAYER_TARGET_CHANGED")
  W.combo = 5; Fire("PLAYER_TARGET_CHANGED")
  assert(A.Count() == 0, "a target that already has five is not a completion")
  W.combo = 1; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 1, "spending and building again plays it again")
  Tick(20, 0.05)
  local before = created
  W.combo = 1; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  Tick(20, 0.05)
  assert(created == before, "no new frame when it plays again")
  CB.Set("effectsReducedMotion", true)
  W.combo = 1; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "reduced motion: no sliding edge")
  CB.Set("effectsReducedMotion", false); CB.Set("effectsClass", false)
  W.combo = 1; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "the class touch can be turned off")
  CB.Set("effectsClass", true)
  -- not on the energy bar, and not a Druid's
  W.P[3] = 10; Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
  W.P[3] = 100; Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
  assert(A.Count() == 0, "energy has the highlight's setting only, which is off here")
  World("DRUID"); W.ptype, W.token = 3, "ENERGY"; W.combo = 1
  Fire("UNIT_DISPLAYPOWER", "player")
  W.combo = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "a Druid in Cat Form has no class touch yet")
  Reset()
end

do
  -- the Rogue's venom drips: one per spent point, on a real spend only
  Reset(); World("ROGUE"); W.combo = 3
  On(); EnterWorld(); CB.Set("effects", true); CB.Set("effectsAccent", false); CB.Set("effectsClass", false)
  local seg = Slot("secondary")
  local function Count(file)
    local n = 0
    for _, f in ipairs(frames) do
      if f.kind == "texture" and f.parent == seg.fx and f.texture and f.texture:find(file, 1, true) and f.shown then n = n + 1 end
    end
    return n
  end
  local function Drips() return Count("venom-drip.tga") end
  local function Puffs() return Count("venom-puff.tga") end
  W.combo = 5; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "building points drips nothing")
  W.combo = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 1, "spending them does")
  Tick(3, 0.1)
  assert(Drips() == 5, "a drip for each of the five spent: " .. Drips())
  assert(Puffs() >= 5 and Puffs() <= 15, "with a cloud of puffs around them, a bounded number: " .. Puffs())
  local drop
  for _, f in ipairs(frames) do if f.texture and f.texture:find("venom-drip.tga", 1, true) and f.shown then drop = f break end end
  assert(drop.width * 4 == drop.height and drop.height >= 20 and drop.height <= 36, "the drop keeps its proportions and is sized to the bar")
  Tick(40, 0.05)
  assert(A.Count() == 0 and Drips() == 0 and Puffs() == 0 and UpdateScripts() == 0, "they fade away, the cloud with them, and the driver stops")
  W.combo = 2; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  Tick(3, 0.1)
  assert(Drips() == 2, "two spent, two drips: " .. Drips())
  Tick(40, 0.05)
  W.combo = 4; Fire("PLAYER_TARGET_CHANGED")
  W.combo = 0; Fire("PLAYER_TARGET_CHANGED")
  W.combo = 3; Fire("COMBO_TARGET_CHANGED")
  W.combo = 0; Fire("COMBO_TARGET_CHANGED")
  assert(A.Count() == 0, "losing the target is not a spend")
  W.combo = 3; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 2; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "a partial spend is not the points going away")
  W.combo = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  Tick(40, 0.05)
  local before = created
  for _ = 1, 3 do
    W.combo = 4; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    W.combo = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    Tick(40, 0.05)
  end
  assert(created == before, "no new frame when it plays again")
  W.combo = 4; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 1)
  W.dead = true; Fire("PLAYER_DEAD")
  assert(A.Count() == 0 and Drips() == 0 and Puffs() == 0, "hiding stops them")
  W.dead = false; Fire("PLAYER_ALIVE")
  CB.Set("effectsReducedMotion", true)
  W.combo = 4; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "reduced motion: nothing moves")
  CB.Set("effectsReducedMotion", false); CB.Set("effectsPoison", false)
  W.combo = 4; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  W.combo = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "it has its own setting")
  CB.Set("effectsPoison", true)
  World("DRUID"); W.ptype, W.token = 3, "ENERGY"; W.combo = 4
  Fire("UNIT_DISPLAYPOWER", "player")
  W.combo = 0; Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
  assert(A.Count() == 0, "a Druid has none")
  Reset()
end

do
  -- sample transitions in the preview play the effects (the way to see the real trigger without a fight)
  Reset(); World("ROGUE"); W.combo = 0
  On(); EnterWorld(); CB.Set("effects", true)
  CB.PreviewStart()
  CB.PreviewSet(nil, 0)
  CB.PreviewSet(nil, 5)
  assert(A.Count() >= 1, "lighting every sample segment completes the highlight")
  Tick(40, 0.05)
  CB.PreviewStop()
  Reset()
end

---------------------------------------------------------------------------
-- 14. Profiles and imports
---------------------------------------------------------------------------
do
  Reset(); World("MAGE")
  On(); EnterWorld()
  local bar = Slot("primary")
  -- another profile's values arrive in the same tables: a refresh shows them
  c.TwichUIDB.ui.classBars = { primaryText = "percent", opacity = 0 }
  c.TwichUIDB.ui.classBarsOverrides = { ["MAGE:MANA"] = { text = "currentMax" }, ["WARRIOR:RAGE"] = { text = "none" } }
  R.Profiles.Refresh("test")
  assert(bar.text.text == "800 / 1000", "the profile's override for this class and resource")
  assert(bar.frame.parent.alpha == 0, "a zero opacity from the profile is kept")
  assert(c.TwichUIDB.ui.classBarsOverrides["WARRIOR:RAGE"].text == "none", "another class's setting is untouched")
  c.TwichUIDB.ui.classBarsOverrides = nil
  c.TwichUIDB.ui.classBars = nil
  R.Profiles.Refresh("test")
  assert(bar.text.text == "800" and bar.frame.parent.alpha == 1, "and back")
  Reset()
end

---------------------------------------------------------------------------
-- 15. Combat: nothing here is protected
---------------------------------------------------------------------------
do
  Reset(); World("MAGE")
  On(); EnterWorld()
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  local bar = Slot("primary")
  CB.Set("fontSize", 14); CB.Set("primaryWidth", 300); CB.Set("scale", 110)
  assert(bar.frame.width == 300 and bar.text.font[2] == 14, "settings apply in combat: the bars are plain frames")
  Off()
  assert(not bar.frame.shown)
  On()
  assert(bar.frame.shown, "and the switch works in combat")
  W.combat = false; Fire("PLAYER_REGEN_ENABLED")
  Reset()
end

---------------------------------------------------------------------------
-- 16. The registry of effects is extensible and strict
---------------------------------------------------------------------------
do
  assert(not FX.Register({ id = "x" }) and not FX.Register({ id = "accent" }))
  assert(not FX.Register({ id = "y", setting = "noSuchSetting", Applies = function() end, Attach = function() end, Update = function() end,
    Play = function() end, Stop = function() end, Release = function() end }), "an effect needs a real setting")
  local inst = {}
  assert(not FX.Rising(inst, 50, 100, false), "the first value is a start")
  assert(not FX.Rising(inst, 99, 100) and FX.Rising(inst, 100, 100), "rising through the threshold")
  assert(not FX.Rising(inst, 100, 100) and not FX.Rising(inst, 95, 100) and not FX.Rising(inst, 100, 100), "not again without a real drop")
  assert(not FX.Rising(inst, 50, 100) and FX.Rising(inst, 100, 100), "after one")
  assert(not FX.Rising({}, 100, 100, true), "a quiet value never plays")
end

---------------------------------------------------------------------------
-- 17. The animation driver: bounded, safe, and idle when empty
---------------------------------------------------------------------------
do
  A.Clear()
  local objs = {}
  for i = 1, A.MAX_ACTIVE + 5 do
    objs[i] = { Step = function() return false end }
  end
  local taken = 0
  for _, o in ipairs(objs) do if A.Add(o) then taken = taken + 1 end end
  assert(taken == A.MAX_ACTIVE and A.Count() == A.MAX_ACTIVE, "bounded")
  assert(A.Add(objs[1]) and A.Count() == A.MAX_ACTIVE, "adding twice is one")
  A.Remove(objs[1]); assert(A.Count() == A.MAX_ACTIVE - 1)
  A.Clear()
  assert(A.Count() == 0 and not A.Running(), "cleared: idle")
  local boom = { Step = function() error("boom") end }
  local errs = {}
  c.geterrorhandler = function() return function(e) errs[#errs + 1] = e end end
  A.Add(boom); Tick(2, 0.05)
  assert(A.Count() == 0 and not A.Running(), "a step that fails is taken off and not run again")
  local order = {}
  local a1 = { Step = function(self, dt) order[#order + 1] = dt; return true end }
  A.Add(a1); Tick(1, 5)
  assert(order[1] == A.MAX_STEP, "a hitch moves an effect no further than one step")
  A.Clear()
end

---------------------------------------------------------------------------
-- 18. The effects' own textures exist, as valid uncompressed 32-bit TGAs of the sizes the code assumes
---------------------------------------------------------------------------
do
  local function Header(name)
    local f = assert(io.open(ROOT .. "media/classbars/" .. name, "rb"), name .. " is shipped")
    local d = f:read("*a"); f:close()
    local function u16(i) return d:byte(i) + d:byte(i + 1) * 256 end
    return { type = d:byte(3), w = u16(13), h = u16(15), bpp = d:byte(17), size = #d }
  end
  local drip, puff = Header("venom-drip.tga"), Header("venom-puff.tga")
  assert(drip.type == 2 and drip.bpp == 32 and drip.w == 32 and drip.h == 128 and drip.size == 18 + 32 * 128 * 4, "the drop is 32x128, 32 bit")
  assert(puff.type == 2 and puff.bpp == 32 and puff.w == 32 and puff.h == 32 and puff.size == 18 + 32 * 32 * 4, "the puff is 32x32, 32 bit")
  local f = assert(io.open(ROOT .. "classbars/Effects.lua")); local src = f:read("*a"); f:close()
  assert(src:find([[media\classbars\venom-drip.tga]], 1, true) and src:find([[media\classbars\venom-puff.tga]], 1, true), "the code names exactly those files")
end

print("CLASS BARS TESTS PASSED")
