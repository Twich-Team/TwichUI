-- Class resource bars (classbars/Resources.lua): the provider layer, pinned directly instead of through the bars.
-- The primary bar follows the power the client reports (UnitPowerType), never an internal class table; colors and
-- resting values are ours only for mana, rage, energy, focus and runic power, and any other reported power uses the
-- color the client gives it with no known resting value (docs/class-bars.md:18). A slot has one active provider at a
-- time: the first registered one that applies (docs/class-bars.md:82). If the client reports a value TwichUI cannot
-- read (a restricted maximum, a maximum of 0, no power at all), the state is not ok, never a guess, and it returns
-- when the value does (docs/class-bars.md:32-33). A fake world stands in for the game, so this checks our logic, not
-- the game.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })

---------------------------------------------------------------------------
-- A fake world: the power APIs read one table the tests change
---------------------------------------------------------------------------
-- A restricted value: addon code may not compute with it or order it, so every such attempt is an error here too.
local SECRET = setmetatable({}, {
  __lt = function() error("compared a secret value") end, __le = function() error("compared a secret value") end,
  __add = function() error("computed with a secret value") end, __sub = function() error("computed with a secret value") end,
  __mul = function() error("computed with a secret value") end, __div = function() error("computed with a secret value") end,
  __concat = function() error("concatenated a secret value") end, __unm = function() error("computed with a secret value") end,
})
local W = { class = "WARRIOR", name = "Warrior", ptype = 1, token = "RAGE", r = 0.78, g = 0.61, b = 0.43,
  P = { [1] = 40 }, PM = { [1] = 100 } }
c.UnitClass = function() return W.name, W.class end
c.UnitPowerType = function() return W.ptype, W.token, W.r, W.g, W.b end
c.UnitPower = function(_, t) return W.P[t] end
c.UnitPowerMax = function(_, t) return W.PM[t] end
c.issecretvalue = function(v) return v == SECRET end
c.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
c.CurveConstants = { ScaleTo100 = {} }

local chunk = assert(loadfile(ROOT .. "classbars/Resources.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local CBR = c.TwichUI.ClassBarResources

local function near(a, b) return math.abs(a - b) < 0.002 end

---------------------------------------------------------------------------
-- 1. HasSlot: a slot is filled by the first registered provider that fits, and empty when none does
---------------------------------------------------------------------------
do
  -- The built-in providers: "power" fits every class on primary; "combo" is Rogue/Druid on secondary;
  -- "druidMana" is Druid on tertiary. A Warrior therefore has only the primary slot.
  assert(CBR.HasSlot("primary", "WARRIOR") == true, "the power provider fits every class")
  assert(CBR.HasSlot("secondary", "WARRIOR") == false, "combo points are not offered to a Warrior")
  assert(CBR.HasSlot("tertiary", "WARRIOR") == false, "no provider applies to a Warrior's tertiary slot")
  assert(CBR.HasSlot("secondary", "ROGUE") == true, "combo points are offered to a Rogue")

  -- Two registered providers apply to the same slot: the slot is filled, and the first registered one wins.
  W.useFirst = true
  local ok1 = CBR.Register({
    id = "tFirst", slot = "tertiary", kind = "continuous", classes = { WARRIOR = true },
    Applies = function() return W.useFirst end,
    Read = function(p) p.state.ok = true end,
  })
  local ok2 = CBR.Register({
    id = "tSecond", slot = "tertiary", kind = "continuous", classes = { WARRIOR = true },
    Applies = function() return true end,
    Read = function(p) p.state.ok = true end,
  })
  assert(ok1 and ok2, "the test providers register")
  CBR.Sense()
  assert(CBR.HasSlot("tertiary", "WARRIOR") == true, "a slot with two applying providers is not empty")
  assert(CBR.Resolve("tertiary").id == "tFirst", "the first registered provider that applies supplies the slot")
  W.useFirst = false
  assert(CBR.Resolve("tertiary").id == "tSecond", "when the first stops applying, the next registered one applies")
end

---------------------------------------------------------------------------
-- 2. ForClass: the resolved provider follows the client-reported power, not an internal class table
---------------------------------------------------------------------------
do
  -- A Warrior whose client reports focus: CLASS_POWERS lists only rage for a Warrior, so anything reading that
  -- table instead of UnitPowerType would resolve rage. The bar must show what the client reports.
  W.class, W.name = "WARRIOR", "Warrior"
  W.ptype, W.token, W.r, W.g, W.b = 2, "FOCUS", 0.85, 0.55, 0.30
  W.P[2], W.PM[2] = 60, 100
  CBR.Sense()
  local p = CBR.Resolve("primary")
  assert(p and p.id == "power", "the primary slot is the reported-power provider")
  local s = CBR.Read(p)
  assert(s.key == "FOCUS" and s.token == "FOCUS", "the primary bar follows the client-reported power token")
  assert(s.ok and s.cur == 60 and s.max == 100, "the reported numbers are read as they are")
end

---------------------------------------------------------------------------
-- 3. ClassColor and Color: ours for the five known powers, the client's for anything else, no resting value
---------------------------------------------------------------------------
do
  -- ClassColor: the game's class colors, ivory when the game gives none.
  local r, g, b = CBR.ClassColor("WARRIOR")
  assert(r == 0.78 and g == 0.61 and b == 0.43, "a known class takes the game's class color")
  r, g, b = CBR.ClassColor("NO_SUCH_CLASS")
  assert(r == 0.94 and g == 0.91 and b == 0.82, "a class the game gives no color for falls back to ivory")

  -- Color: ours only for mana, rage, energy, focus and runic power (docs/class-bars.md:18).
  assert(CBR.Color("MANA") == 0.30 and (function() local r, g, b = CBR.Color("MANA"); return g == 0.52 and b == 0.90 end)(),
    "mana keeps the addon's color")
  assert((function() local r, g, b = CBR.Color("RAGE"); return r == 0.78 and g == 0.25 and b == 0.20 end)(),
    "rage keeps the addon's color")
  assert((function() local r, g, b = CBR.Color("ENERGY"); return r == 0.92 and g == 0.80 and b == 0.28 end)(),
    "energy keeps the addon's color")
  assert((function() local r, g, b = CBR.Color("FOCUS"); return r == 0.85 and g == 0.55 and b == 0.30 end)(),
    "focus keeps the addon's color")
  assert((function() local r, g, b = CBR.Color("RUNIC_POWER"); return r == 0.20 and g == 0.72 and b == 0.90 end)(),
    "runic power keeps the addon's color")

  -- An unknown reported power: the color the client gives it, and no resting value we know.
  W.ptype, W.token, W.r, W.g, W.b = 7, "MYSTIC_STAMINA", 0.11, 0.22, 0.33
  W.P[7], W.PM[7] = 10, 20
  CBR.Sense()
  local r, g, b = CBR.Color("MYSTIC_STAMINA")
  assert(r == 0.11 and g == 0.22 and b == 0.33, "an unknown reported power uses the color the client gives it")
  assert(CBR.REST["MYSTIC_STAMINA"] == nil, "an unknown reported power has no resting value")
  assert(CBR.AtRest("MYSTIC_STAMINA", 0, 20) == false and CBR.AtRest("MYSTIC_STAMINA", 20, 20) == false,
    "without a resting value it is never called at rest")
end

---------------------------------------------------------------------------
-- 4. ReadContinuous: not ok when the maximum is 0, restricted or no power is reported; ok when the value returns
---------------------------------------------------------------------------
do
  W.class, W.name = "MAGE", "Mage"
  W.ptype, W.token, W.r, W.g, W.b = 0, "MANA", 0.30, 0.52, 0.90
  W.P[0], W.PM[0] = 800, 1000
  CBR.Sense()
  local p = CBR.Resolve("primary")
  assert(p and p.id == "power", "the primary slot is the reported-power provider")

  -- The value returns: ok with the reported numbers.
  local s = CBR.Read(p)
  assert(s.ok and s.cur == 800 and s.max == 1000 and s.secret == false, "a readable power is ok with the reported numbers")

  -- A maximum of 0: nothing to fill against, never a guess.
  W.PM[0] = 0
  s = CBR.Read(p)
  assert(s.ok == false and s.cur == 0 and s.max == 0, "a maximum of 0 makes the state not ok")

  -- A restricted maximum: the addon may not compute with it, so the state is not ok.
  W.PM[0] = SECRET
  s = CBR.Read(p)
  assert(s.ok == false and s.cur == 0 and s.max == 0, "a restricted maximum makes the state not ok")

  -- No power at all: the client reports nothing.
  W.ptype, W.token, W.r, W.g, W.b = nil, nil, nil, nil, nil
  CBR.Sense()
  assert(CBR.Resolve("primary") == nil, "with no power reported, no provider applies to the primary slot")
  s = CBR.Read(p)
  assert(s.ok == false and s.cur == 0 and s.max == 0, "with no power reported the state is not ok")

  -- And it returns when the value does.
  W.ptype, W.token, W.r, W.g, W.b = 0, "MANA", 0.30, 0.52, 0.90
  W.P[0], W.PM[0] = 800, 1000
  CBR.Sense()
  s = CBR.Read(p)
  assert(s.ok and s.cur == 800 and s.max == 1000, "the state is ok again when the value returns")
end

print("TEST_CLASS_BARS_PROVIDERS PASSED")
