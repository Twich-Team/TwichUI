-- Reminders: the condition library (reminders/Auras.lua, Supplies.lua, Character.lua, Context.lua, the weapon enchant's
-- "running out" and the player's moving / flight path states), the controller's time boundaries and the builder's fields
-- for them (TwichUI_Settings/pages/RemindersPlain.lua). A fake world stands in for the game, so this checks our logic,
-- not the game: what has to be seen in the client is in docs/reminders-condition-expansion.md.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

---------------------------------------------------------------------------
-- Frames that record what they were told, and a clock with timers that wait for it
---------------------------------------------------------------------------
local frames = {}
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, events = {}, points = {}, alpha = 1, scale = 1, w = 10, h = 10 }
  frames[#frames + 1] = o
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
Methods = {
  Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end,
  IsShown = function(s) return s.shown end, SetShown = function(s, v) s.shown = v and true or false end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end, GetScript = function(s, n) return s.scripts[n] end,
  RegisterEvent = function(s, e) s.events[e] = true; s.units = s.units or {}; s.units[e] = nil end,
  RegisterUnitEvent = function(s, e, u) s.events[e] = true; s.units = s.units or {}; s.units[e] = u end,
  UnregisterEvent = function(s, e) s.events[e] = nil end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  SetText = function(s, v) s.text = v end, GetText = function(s) return s.text end,
  GetStringWidth = function(s) return #(s.text or "") * 8 end, GetStringHeight = function(s) return s.fontSize or 18 end,
  ClearAllPoints = function(s) s.points = {} end, SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
  GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  SetTexture = function(s, p) s.texture = p; return true end, SetTexCoord = function(s, ...) s.coords = { ... } end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; s.fontSize = size; return true end,
  CreateAnimationGroup = function(s)
    local g = Fake("group")
    g.Play = function(self) self.playing = true end
    g.Stop = function(self) self.playing = false end
    g.CreateAnimation = function() return Fake("anim") end
    return g
  end,
}
c.CreateFrame = function(kind, name, parent, template)
  local f = Fake(kind)
  f.name, f.parent, f.template = name, parent, template
  return f
end
c.UIParent = Fake("UIParent")
c.UIParent.w, c.UIParent.h = 1024, 768
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

local NOW = 1000
c.GetTime = function() return NOW end
local QUEUE = {}   -- { at, fn }
c.C_Timer = { After = function(d, fn) QUEUE[#QUEUE + 1] = { at = NOW + d, fn = fn } end,
  NewTicker = function() return { Cancel = function() end } end }
-- Moves the clock on, running each timer as its time comes (in order, those they add too).
local function Advance(seconds)
  local target = NOW + seconds
  while true do
    local best
    for i, t in ipairs(QUEUE) do if t.at <= target and (not best or t.at < QUEUE[best].at) then best = i end end
    if not best then break end
    local t = table.remove(QUEUE, best)
    if t.at > NOW then NOW = t.at end
    t.fn()
  end
  NOW = target
end
local function Pending(minAt)
  local n = 0
  for _, t in ipairs(QUEUE) do if t.at >= (minAt or 0) then n = n + 1 end end
  return n
end

---------------------------------------------------------------------------
-- The fake world
---------------------------------------------------------------------------
local SECRET = {}
c.issecretvalue = function(v) return v == SECRET end
c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemWeaponSubclass = { Fishingpole = 20 }, ItemArmorSubclass = { Shield = 6 },
  WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 }, PowerType = { Mana = 0, Rage = 1, Energy = 3 },
  UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
c.INVSLOT_MAINHAND, c.INVSLOT_OFFHAND = 16, 17
c.NUM_BAG_SLOTS = 4
c.UnitAffectingCombat = function() return false end
c.UnitIsDeadOrGhost = function(unit) return unit == "target" and W.targetDead or false end
c.UnitIsGhost = function() return false end
c.IsMounted = function() return false end
c.UnitClassBase = function() return "MAGE" end

W = { auras = { HELPFUL = {}, HARMFUL = {} }, aurasHidden = false, auraCalls = 0, counts = {}, bags = {}, dur = {},
  power = { [0] = { 300, 1000 }, [1] = { 0, 0 }, [3] = { 0, 0 } }, known = {}, exists = {}, cd = {}, form = 0, forms = {},
  level = 20, raid = false, group = false, map = 1429, maps = {}, inside = false, instance = nil,
  target = nil, moving = false, taxi = false, ench = {}, eq = {} }

c.C_Secrets = { ShouldAurasBeSecret = function() return W.aurasHidden end }
c.C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
  W.auraCalls = W.auraCalls + 1
  if W.auraError then error("hidden") end
  return W.auras[filter][i]
end }
c.C_Spell = {
  GetSpellName = function(id) return ({ [1459] = "Arcane Intellect", [10157] = "Arcane Intellect", [122] = "Frost Nova", [5487] = "Bear Form", [768] = "Cat Form" })[id] end,
  DoesSpellExist = function(id) return W.exists[id] ~= false end,
  GetSpellCooldown = function(id) return W.cd[id] end,
}
c.C_SpellBook = { IsSpellKnown = function(id) return W.known[id] == true end }
c.C_Item = {
  GetItemInfoInstant = function(id) if id == 100 then return id, "", "", "INVTYPE_WEAPON", 0, 2, 7 end end,
  GetItemNameByID = function(id) return ({ [17020] = "Arcane Powder" })[id] end,
  RequestLoadItemDataByID = function() end,
  GetItemCount = function(id, bank) Check(bank == false, "the bank is never counted"); return W.counts[id] or 0 end,
  GetWeaponEnchantInfo = function(ws)
    local e = W.ench[ws]
    if not e then return { { hasEnchant = false, timeLeft = 0, charges = 0 } } end
    return { { hasEnchant = true, timeLeft = e, charges = 0 } }
  end,
}
c.GetInventoryItemID = function(_, slot) return W.eq[slot] end
c.C_Container = {
  GetContainerNumSlots = function(bag) local b = W.bags[bag]; return b and b.slots or 0 end,
  GetContainerNumFreeSlots = function(bag) local b = W.bags[bag]; if not b then return 0, 0 end; return b.free, b.family end,
}
c.GetInventoryItemDurability = function(slot) local d = W.dur[slot]; if d then return d[1], d[2] end end
c.UnitPower = function(_, t) return W.power[t][1] end
c.UnitPowerMax = function(_, t) return W.power[t][2] end
c.GetShapeshiftForm = function() return W.form end
c.GetNumShapeshiftForms = function() return #W.forms end
c.GetShapeshiftFormInfo = function(i) return "icon", W.form == i, true, W.forms[i] end
c.UnitLevel = function() return W.level end
c.IsInRaid = function() return W.raid end
c.IsInGroup = function() return W.group or W.raid end
c.IsInInstance = function() return W.inside, W.inside and "party" or "none" end
c.GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, W.instance end
c.GetRealZoneText = function(id) return id == 36 and "The Deadmines" or "" end
c.C_Map = { GetBestMapForUnit = function() return W.map end,
  GetMapInfo = function(id) return W.maps[id] end }
W.maps = { [1429] = { mapID = 1429, name = "Elwynn Forest", mapType = 3, parentMapID = 1415 },
  [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
  [1453] = { mapID = 1453, name = "Stormwind City", mapType = 3, parentMapID = 1415 },
  [5001] = { mapID = 5001, name = "Fargodeep Mine", mapType = 5, parentMapID = 1429 } }
c.UnitExists = function(u) return u == "target" and W.target ~= nil end
c.UnitCanAttack = function() return W.target == "enemy" end
c.UnitIsFriend = function() return W.target == "ally" end
c.IsPlayerMoving = function() return W.moving end
c.UnitOnTaxi = function() return W.taxi end
local PLAYED = {}
c.PlaySoundFile = function(path) PLAYED[#PLAYED + 1] = path; return true end

local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function Settle() Advance(0.2) end
local function Registered(event)
  for _, f in ipairs(frames) do if f.events[event] then return true end end
  return false
end

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "Icons.lua",
  "gear/Weights.lua", "gear/Prefs.lua", "gear/Data.lua",
  "reminders/AmmoItems.lua", "reminders/Config.lua", "reminders/Conditions.lua", "reminders/Ammunition.lua", "reminders/Evaluate.lua", "reminders/State.lua",
  "reminders/Auras.lua", "reminders/Supplies.lua", "reminders/Character.lua", "reminders/Context.lua",
  "reminders/Display.lua", "reminders/Controller.lua", "setup/TwichConfig.lua", "../TwichUI_Settings/pages/RemindersPlain.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local RM, C, E, ST, D, CT, Pl = R.Reminders, R.ReminderConditions, R.ReminderEval, R.ReminderState, R.ReminderDisplay, R.ReminderController, R.RemindersPlain
local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN

local function Eval(raw, obs)
  local clean, problem = C.Check(raw)
  assert(clean, "usable: " .. tostring(problem))
  obs = obs or {}
  obs.now = obs.now or NOW
  return C.Get(raw.type).Evaluate(clean, obs), problem
end
local function Usable(raw) local clean, problem = C.Check(raw) return clean ~= nil and problem == nil end

---------------------------------------------------------------------------
-- 1. Buffs and debuffs (RC-003, RC-004, RC-018)
---------------------------------------------------------------------------
do
  local function Obs(set, filter) return { aura = { [filter or "HELPFUL"] = set } } end
  local AI = { 1459, 10157 }
  Check(Eval({ type = "aura", spells = AI, what = "present" }, Obs({ [10157] = { ends = NOW + 600 } })) == MATCH, "present: either rank counts")
  Check(Eval({ type = "aura", spells = AI, what = "present" }, Obs({ [999] = { ends = NOW + 600 } })) == NOMATCH, "present: another aura is not it")
  Check(Eval({ type = "aura", spells = AI, what = "missing" }, Obs({})) == MATCH, "missing: none on you")
  Check(Eval({ type = "aura", spells = AI, what = "missing" }, Obs({ [1459] = { ends = false } })) == NOMATCH, "missing: on you")
  Check(Eval({ type = "aura", spells = AI, what = "missing" }, Obs(nil)) == UNKNOWN and Eval({ type = "aura", spells = AI, what = "present" }, Obs(nil)) == UNKNOWN,
    "auras that can't be read are unknown, never missing or present")
  Check(Eval({ type = "aura", spells = AI, what = "missing" }, {}) == UNKNOWN, "not read at all: unknown")
  -- debuffs read their own list
  Check(Eval({ type = "aura", spells = { 6788 }, harmful = true, what = "present" }, Obs({ [6788] = { ends = NOW + 15 } }, "HARMFUL")) == MATCH, "a debuff on you")
  Check(Eval({ type = "aura", spells = { 6788 }, harmful = true, what = "present" }, Obs({ [6788] = { ends = NOW + 15 } }, "HELPFUL")) == UNKNOWN, "the helpful list says nothing about debuffs")
  -- running out: threshold, equality, permanent, unknown, absent, several instances
  local function Exp(set, s) return Eval({ type = "aura", spells = AI, what = "expiring", seconds = s or 60 }, Obs(set)) end
  Check(Exp({ [1459] = { ends = NOW + 59 } }) == MATCH, "expiring: 59 s left is less than 60")
  Check(Exp({ [1459] = { ends = NOW + 60 } }) == NOMATCH, "expiring: exactly 60 s left is not less than 60")
  Check(Exp({ [1459] = { ends = NOW + 61 } }) == NOMATCH, "expiring: 61 s left")
  Check(Exp({ [1459] = { ends = false } }) == NOMATCH, "expiring: one that never runs out never matches")
  Check(Exp({}) == NOMATCH, "expiring: not on you is not running out (that is missing)")
  Check(Exp({ [1459] = { ends = nil } }) == UNKNOWN, "expiring: a time that isn't given is unknown")
  Check(Exp({ [1459] = { ends = NOW + 10 }, [10157] = { ends = NOW + 900 } }) == NOMATCH, "expiring: the longest-lasting instance counts")
  Check(Exp({ [1459] = { ends = nil }, [10157] = { ends = NOW + 900 } }) == NOMATCH, "expiring: one known to last settles it")
  Check(Exp({ [1459] = { ends = nil }, [10157] = { ends = NOW + 5 } }) == UNKNOWN, "expiring: a short one beside an unknown one is unknown")
  -- stacks
  local function St(set, n, cmp) return Eval({ type = "aura", spells = AI, what = "stacks", stacks = n, compare = cmp }, Obs(set)) end
  Check(St({ [1459] = { ends = false, stacks = 3 } }, 3) == MATCH, "stacks: at least 3 with 3")
  Check(St({ [1459] = { ends = false, stacks = 2 } }, 3) == NOMATCH, "stacks: 2 is not at least 3")
  Check(St({ [1459] = { ends = false, stacks = 2 } }, 3, "below") == MATCH, "stacks: fewer than 3 with 2")
  Check(St({ [1459] = { ends = false, stacks = 0 } }, 1) == MATCH, "stacks: one that doesn't stack counts as one")
  Check(St({}, 1, "below") == NOMATCH, "stacks: not on you never matches, not even 'fewer than'")
  Check(St({ [1459] = { ends = false } }, 2) == UNKNOWN, "stacks: a count that isn't given is unknown")
  -- stored form
  Check(not Usable({ type = "aura", spells = {}, what = "missing" }) and C.Check({ type = "aura", spells = {}, what = "missing" }) ~= nil, "no spell chosen: kept as unfinished")
  Check(C.Check({ type = "aura", spells = { "x" }, what = "missing" }) == nil, "a spell that isn't an ID is refused")
  Check(C.Check({ type = "aura", spells = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }, what = "missing" }) == nil, "more than eight spells is refused")
  Check(#C.Check({ type = "aura", spells = { 5, 5, 6 }, what = "missing" }).spells == 2, "a spell named twice is kept once")
  Check(C.Check({ type = "aura", spells = { 1 }, what = "glowing" }) == nil, "an unknown question is refused")
  Check(not Usable({ type = "aura", spells = { 1 }, what = "expiring" }), "running out needs its time")
  Check(not Usable({ type = "aura", spells = { 1 }, what = "expiring", seconds = 0 }) and Usable({ type = "aura", spells = { 1 }, what = "expiring", seconds = 1 }), "a time of at least one second")
  local raw = { type = "aura", spells = { 1459 }, what = "missing", seconds = 30 }
  local clean = C.Check(raw)
  Check(clean.seconds == nil and clean.spells ~= raw.spells, "only its own fields are kept, in a list of its own")
  -- negation is not a choice: an unknown stays unknown for both present and missing (see above)
  local needs = {}
  C.Get("aura").Needs(C.Check({ type = "aura", spells = { 1 }, harmful = true, what = "present" }), function(k) needs[#needs + 1] = k end)
  Check(#needs == 1 and needs[1] == "aura:HARMFUL", "a debuff reads the harmful list only")
  -- time: the next boundary
  local P = C.Get("aura")
  local exp = C.Check({ type = "aura", spells = AI, what = "expiring", seconds = 60 })
  Check(math.abs(P.NextChange(exp, { now = NOW, aura = { HELPFUL = { [1459] = { ends = NOW + 100 } } } }) - 40) < 1e-6, "the next look is when it crosses 60 s left")
  Check(math.abs(P.NextChange(exp, { now = NOW, aura = { HELPFUL = { [1459] = { ends = NOW + 30 } } } }) - 30) < 1e-6, "then when it runs out")
  Check(P.NextChange(exp, { now = NOW, aura = { HELPFUL = { [1459] = { ends = false } } } }) == nil, "one that never runs out has no boundary")
  Check(P.NextChange(C.Check({ type = "aura", spells = AI, what = "missing" }), { now = NOW, aura = { HELPFUL = { [1459] = { ends = NOW + 30 } } } }) == nil,
    "presence has no time boundary of its own")
end

---------------------------------------------------------------------------
-- 2. Weapon enchant running out (RC-006)
---------------------------------------------------------------------------
do
  local function Obs(state, left) return { enchant = { mainHand = state, ends = { mainHand = left and NOW + left or nil } } } end
  local function X(state, left, s) return Eval({ type = "weaponEnchant", hand = "mainHand", what = "expiring", seconds = s or 300 }, Obs(state, left)) end
  Check(X("enchanted", 299) == MATCH and X("enchanted", 300) == NOMATCH and X("enchanted", 1800) == NOMATCH, "less than five minutes left; exactly five is not")
  Check(X("bare") == NOMATCH and X("noWeapon") == NOMATCH, "no enchant, or nothing to enchant, is not running out")
  Check(X("enchanted", nil) == UNKNOWN and X(nil) == UNKNOWN, "an end that isn't given, or nothing read, is unknown")
  Check(Eval({ type = "weaponEnchant", hand = "mainHand", what = "missing" }, Obs("bare")) == MATCH, "missing still works as before")
  Check(not Usable({ type = "weaponEnchant", hand = "mainHand", what = "expiring" }), "running out needs its time")
  Check(C.Check({ type = "weaponEnchant", hand = "mainHand", what = "missing", seconds = 5 }).seconds == nil, "missing keeps no time")
end

---------------------------------------------------------------------------
-- 3. Supplies, bags and durability (RC-005, RC-016, RC-015)
---------------------------------------------------------------------------
do
  local function IC(n, cmp, count) return Eval({ type = "itemCount", item = 17020, compare = cmp or "below", count = count or 10 }, { itemCount = { [17020] = n } }) end
  Check(IC(9) == MATCH and IC(10) == NOMATCH and IC(0) == MATCH, "fewer than 10: 9 and 0 yes, exactly 10 no")
  Check(IC(10, "atLeast") == MATCH and IC(9, "atLeast") == NOMATCH, "at least 10")
  Check(IC(nil) == UNKNOWN and IC(nil, "atLeast") == UNKNOWN, "a count that isn't read is unknown, never zero")
  Check(not Usable({ type = "itemCount", compare = "below", count = 5 }), "no item chosen: unfinished")
  Check(C.Check({ type = "itemCount", item = "x", compare = "below", count = 5 }) == nil and C.Check({ type = "itemCount", item = 1, compare = "most", count = 5 }) == nil, "bad item or comparison refused")
  Check(not Usable({ type = "itemCount", item = 1, compare = "below", count = 0 }) and not Usable({ type = "itemCount", item = 1, compare = "below", count = 1.5 }), "a count is a whole number from 1")

  local function BS(n, cmp, count) return Eval({ type = "bagSpace", compare = cmp or "below", count = count or 5 }, { bagFree = n }) end
  Check(BS(4) == MATCH and BS(5) == NOMATCH and BS(nil) == UNKNOWN, "free slots: boundary and unknown")
  Check(C.Get("bagSpace").Summary(C.Check({ type = "bagSpace", compare = "below", count = 1 })) == "Your bags are full", "fewer than one free slot reads as full bags")

  local function Dur(items, what, pct)
    local d = { items = items, broken = false }
    for _, it in ipairs(items) do if it[1] <= 0 then d.broken = true end end
    return Eval({ type = "durability", what = what, percent = pct }, { durability = d })
  end
  local many = {}
  for i = 1, 9 do many[i] = { 100, 100 } end
  many[10] = { 0, 80 }
  Check(Dur(many, "broken") == MATCH, "one broken item among nine at full: broken (an average would hide it)")
  Check(Dur(many, "below", 10) == MATCH, "and it is below 10%")
  Check(Dur({ { 50, 100 } }, "below", 50) == NOMATCH and Dur({ { 49, 100 } }, "below", 50) == MATCH, "below 50%: exactly half is not below")
  Check(Dur({}, "broken") == NOMATCH and Dur({}, "below", 90) == NOMATCH, "nothing that wears down: nothing to repair")
  Check(Eval({ type = "durability", what = "broken" }, {}) == UNKNOWN, "not read: unknown")
  Check(not Usable({ type = "durability", what = "below" }) and Usable({ type = "durability", what = "broken" }), "worn needs its share; broken doesn't")
end

---------------------------------------------------------------------------
-- 4. Resources, spells, forms, level, cooldowns (RC-008 to RC-011, RC-017)
---------------------------------------------------------------------------
do
  local function PW(f, cmp, pct) return Eval({ type = "power", power = "MANA", compare = cmp or "below", percent = pct or 30 }, { power = { MANA = f } }) end
  Check(PW({ cur = 299, max = 1000 }) == MATCH and PW({ cur = 300, max = 1000 }) == NOMATCH, "below 30%: 29.9% yes, exactly 30% no")
  Check(PW({ cur = 300, max = 1000 }, "atLeast") == MATCH, "exactly 30% is at least 30%")
  Check(PW("none") == NOMATCH and PW("none", "atLeast") == NOMATCH, "no mana pool matches neither way: it is not 0%")
  Check(PW(nil) == UNKNOWN, "secret or unread: unknown")
  Check(C.Check({ type = "power", power = "HEALTH", compare = "below", percent = 30 }) == nil, "health is not a resource here (always secret to addons)")
  Check(C.Check({ type = "power", power = "RAGE", compare = "below", percent = 30 }).power == "RAGE", "a saved resource is kept as it is, never reinterpreted")

  local function SK(v, negate) return Eval({ type = "spellKnown", spell = 122, negate = negate }, { spellKnown = { [122] = v } }) end
  Check(SK(true) == MATCH and SK(false) == NOMATCH and SK(false, true) == MATCH, "known, not known, don't know")
  Check(SK("invalid") == UNKNOWN and SK("invalid", true) == UNKNOWN, "a spell the game doesn't have never satisfies 'you don't know it'")
  Check(SK(nil, true) == UNKNOWN, "negating unknown stays unknown")
  Check(not Usable({ type = "spellKnown" }) and C.Check({ type = "spellKnown", spell = -1 }) == nil, "unchosen is unfinished; a bad ID is refused")

  local function FM(v, raw) raw.type = "form"; return Eval(raw, { form = v }) end
  Check(FM(5487, { form = 5487 }) == MATCH and FM(768, { form = 5487 }) == NOMATCH, "in Bear Form")
  Check(FM("none", { state = "none" }) == MATCH and FM(5487, { state = "none" }) == NOMATCH, "no form is a state of its own")
  Check(FM("none", { form = 5487, negate = true }) == MATCH, "a mage is not in Bear Form: said outright, never mapped to a mage's own forms")
  Check(FM(nil, { form = 5487, negate = true }) == UNKNOWN, "unknown form, negated: unknown")
  Check(C.Check({ type = "form", state = "none", form = 5487 }) == nil and C.Check({ type = "form", state = "flying" }) == nil, "ambiguous or unknown states refused")

  local function LV(v, cmp, n) return Eval({ type = "level", compare = cmp, level = n }, { level = v }) end
  Check(LV(59, "below", 60) == MATCH and LV(60, "below", 60) == NOMATCH and LV(60, "atLeast", 60) == MATCH, "level boundaries")
  Check(LV(nil, "below", 60) == UNKNOWN, "unread level")
  Check(Usable({ type = "level", compare = "atLeast", level = 85 }) and not Usable({ type = "level", compare = "atLeast", level = 1000 }), "no level cap is assumed below 999")

  local function CD(f, what, s) return Eval({ type = "cooldown", spell = 122, what = what, seconds = s }, { cooldown = { [122] = f } }) end
  local ready, cooling = { known = true, state = "ready" }, { known = true, state = "cooling", ends = NOW + 20 }
  Check(CD(ready, "ready") == MATCH and CD(cooling, "ready") == NOMATCH, "ready")
  Check(CD(cooling, "cooling") == MATCH and CD(ready, "cooling") == NOMATCH, "cooling")
  Check(CD({ known = false }, "ready") == NOMATCH and CD({ known = false }, "cooling") == NOMATCH, "a spell you don't know is neither ready nor cooling")
  Check(CD(cooling, "within", 21) == MATCH and CD(cooling, "within", 20) == NOMATCH and CD(ready, "within", 5) == MATCH, "ready within: boundary, and ready already counts")
  Check(CD({ known = true, state = "cooling" }, "within", 30) == UNKNOWN, "an end that isn't given is unknown")
  Check(CD({ known = true, state = "held" }, "within", 30) == NOMATCH and CD({ known = true, state = "held" }, "cooling") == MATCH, "on hold: cooling, not soon")
  Check(CD(nil, "ready") == UNKNOWN, "unread")
  local P = C.Get("cooldown")
  Check(math.abs(P.NextChange(C.Check({ type = "cooldown", spell = 122, what = "within", seconds = 5 }), { now = NOW, cooldown = { [122] = cooling } }) - 15) < 1e-6, "next look: 5 s before it ends")
  Check(math.abs(P.NextChange(C.Check({ type = "cooldown", spell = 122, what = "ready" }), { now = NOW, cooldown = { [122] = cooling } }) - 20) < 1e-6, "next look: when it ends")
end

---------------------------------------------------------------------------
-- 5. Group, place, target, moving (RC-012, RC-013, RC-019, RC-020)
---------------------------------------------------------------------------
do
  local function GT(v, what, negate) return Eval({ type = "groupType", what = what, negate = negate }, { groupType = v }) end
  Check(GT("solo", "solo") == MATCH and GT("party", "solo") == NOMATCH, "solo")
  Check(GT("raid", "party") == NOMATCH and GT("raid", "raid") == MATCH and GT("raid", "grouped") == MATCH and GT("party", "grouped") == MATCH, "a raid group is not a party; both are grouped")
  Check(GT(nil, "solo", true) == UNKNOWN, "unknown, negated")
  -- a raid group is not a raid instance: the place is the player kind's
  local both = Eval({ type = "player", state = "raid" }, { place = "none" })
  Check(both == NOMATCH and GT("raid", "raid") == MATCH, "a raid group in the open world is in a raid group, not in a raid")

  local here = { map = 5001, chain = { 5001, 1429, 1415 } }
  local function ZN(f, raw) raw.type = "zone"; return Eval(raw, { zone = f }) end
  Check(ZN(here, { map = 1429 }) == MATCH, "a cave inside Elwynn Forest is in Elwynn Forest")
  Check(ZN(here, { map = 1453 }) == NOMATCH and ZN(here, { map = 1453, negate = true }) == MATCH, "not in Stormwind")
  Check(ZN({ instance = 36, chain = {} }, { instance = 36 }) == MATCH and ZN(here, { instance = 36 }) == NOMATCH, "an instance by its ID")
  Check(ZN(nil, { map = 1453, negate = true }) == UNKNOWN, "where you are not known yet, negated: unknown, never 'elsewhere'")
  Check(not Usable({ type = "zone" }) and C.Check({ type = "zone", map = 1, instance = 2 }) == nil, "nothing chosen is unfinished; both is refused")

  local function TG(f, dead, what, negate) return Eval({ type = "target", what = what, negate = negate }, { target = f, targetLife = dead }) end
  local enemy = { exists = true, attackable = true, friendly = false }
  Check(TG(enemy, false, "attackable") == MATCH and TG(enemy, false, "friendly") == NOMATCH and TG(enemy, false, "friendly", true) == MATCH, "an enemy")
  Check(TG({ exists = false }, nil, "exists") == NOMATCH and TG({ exists = false }, nil, "exists", true) == MATCH, "no target")
  Check(TG({ exists = false }, nil, "friendly", true) == NOMATCH and TG({ exists = false }, nil, "dead", true) == NOMATCH, "no target never satisfies 'is not friendly' or 'is alive'")
  Check(TG(enemy, true, "dead") == MATCH and TG(enemy, nil, "dead") == UNKNOWN, "dead, and unread death")
  Check(TG(nil, nil, "exists", true) == UNKNOWN, "unread target, negated: unknown")

  Check(Eval({ type = "player", state = "moving" }, { moving = true }) == MATCH and Eval({ type = "player", state = "moving", negate = true }, { moving = false }) == MATCH, "moving and standing still")
  Check(Eval({ type = "player", state = "taxi" }, { taxi = true }) == MATCH and Eval({ type = "player", state = "taxi", negate = true }, {}) == UNKNOWN, "a flight path; unread negated is unknown")
end

---------------------------------------------------------------------------
-- 6. All / Any with the new kinds, and simulation
---------------------------------------------------------------------------
c.TwichUIDB.ui = c.TwichUIDB.ui or {}
local function Use(list)
  c.TwichUIDB.ui.reminders = { version = 1, nextId = 10, list = list }
  RM.Invalidate()
end
do
  Use({ { id = "r1", name = "A", enabled = true, match = "all", display = { mode = "text", text = "x" }, conditions = {
    { type = "power", power = "MANA", compare = "below", percent = 30 },
    { type = "player", state = "combat", negate = true },
    { type = "group", match = "any", conditions = {
      { type = "aura", spells = { 1459 }, what = "missing" },
      { type = "aura", spells = { 1459 }, what = "expiring", seconds = 60 } } } } } })
  local v = RM.Get("r1")
  Check(v.valid, "a rule of new kinds is valid")
  local obs = { now = NOW, combat = false, power = { MANA = { cur = 100, max = 1000 } }, aura = { HELPFUL = { [1459] = { ends = NOW + 30 } } } }
  Check(E.Run(v, obs, { simulated = true }).result == MATCH, "low mana, out of combat, buff running out: match")
  obs.aura.HELPFUL[1459].ends = NOW + 900
  Check(E.Run(v, obs, { simulated = true }).result == NOMATCH, "buff with plenty left: no match")
  obs.aura.HELPFUL = nil
  Check(E.Run(v, obs, { simulated = true }).result == UNKNOWN, "buffs hidden: unknown, never shown")
  obs.power.MANA = "none"
  Check(E.Run(v, obs, { simulated = true }).result == NOMATCH, "no mana pool settles an All as no match even with buffs unknown")
  local out = E.Simulate(v)
  Check(out.simulated and #out.conditions == 4, "a simulation runs every condition")
  local sentence = E.RuleSentence(v)
  Check(sentence:find("mana is below 30%%", 1) and sentence:find("Arcane Intellect", 1, true), "the rule's sentence names them: " .. sentence)
end

---------------------------------------------------------------------------
-- 7. Reading the game, events, time boundaries and sound
---------------------------------------------------------------------------
local function Shown(id) local f = D.Frame(id) return f ~= nil and f.shown end
do
  -- an aura reminder: only its own events, read on UNIT_AURA, shown when it runs low
  W.auras.HELPFUL = { { spellId = 1459, expirationTime = NOW + 100, duration = 1800, applications = 0 } }
  Use({ { id = "r2", name = "Buff", enabled = true, match = "all", display = { mode = "text", text = "Renew" }, sound = "TwichUI Notification",
    conditions = { { type = "aura", spells = { 1459 }, what = "expiring", seconds = 60 } } } })
  CT.Refresh()
  Fire("PLAYER_ENTERING_WORLD"); Settle()
  Check(Registered("UNIT_AURA") and not Registered("UNIT_POWER_UPDATE") and not Registered("BAG_UPDATE_DELAYED") and not Registered("SPELL_UPDATE_COOLDOWN"),
    "only the events the running conditions need")
  Check(not Shown("r2") and CT.Snapshot().timed == 1, "100 s left: hidden, one time boundary waiting")
  Advance(39); Check(not Shown("r2"), "61 s left: still hidden")
  local played = #PLAYED
  Advance(1.2); Check(Shown("r2") and #PLAYED == played + 1, "under 60 s left: shown once, with one sound")
  Advance(5); Check(Shown("r2") and #PLAYED == played + 1, "time passing while it stays up: no more sound")
  -- renewing the buff moves its end: UNIT_AURA for a timer refresh reads again
  W.auras.HELPFUL[1].expirationTime = NOW + 1800
  Fire("UNIT_AURA", "player", { updatedAuraInstanceIDs = { 1 } }); Settle()
  Check(not Shown("r2"), "renewed: gone")
  Check(CT.Snapshot().timed == 1, "and one boundary waits, at the new time")
  -- hidden auras: unknown, hidden, never "missing"
  W.aurasHidden = true
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(ST.Observations().aura.HELPFUL == nil and not Shown("r2"), "auras hidden from addons: unknown, not shown")
  W.aurasHidden = false
  -- more than 40 auras: unknown
  local long = {}
  for i = 1, 41 do long[i] = { spellId = 5000 + i, expirationTime = 0, duration = 0 } end
  W.auras.HELPFUL = long
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(ST.Observations().aura.HELPFUL == nil, "more auras than are looked at: unknown, not 'not there'")
  -- secret spell ID on one aura: unknown
  W.auras.HELPFUL = { { spellId = SECRET, expirationTime = 0, duration = 0 } }
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(ST.Observations().aura.HELPFUL == nil, "an aura that can't be named makes the list unknown")
  W.auras.HELPFUL = { { spellId = 1459, expirationTime = 0, duration = 0 }, { spellId = 1459, expirationTime = NOW + 20, duration = 30, applications = 2 } }
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  local a = ST.Observations().aura.HELPFUL[1459]
  Check(a and a.ends == false and a.stacks == 2, "two instances: never runs out wins, most stacks kept")
  Check(not Shown("r2") and CT.Snapshot().timed == 0, "one that never runs out: no time boundary")
end

do
  -- mana: value changes while it stays up sound once
  W.power[0] = { 200, 1000 }
  Use({ { id = "r3", name = "Mana", enabled = true, match = "all", display = { mode = "text", text = "Drink" }, sound = "TwichUI Notification",
    conditions = { { type = "power", power = "MANA", compare = "below", percent = 30 } } } })
  CT.Refresh(); Settle()
  Check(Registered("UNIT_POWER_UPDATE") and not Registered("UNIT_AURA"), "mana events only; the aura events are dropped")
  local played = #PLAYED
  Check(Shown("r3"), "20% mana: shown")
  for pct = 21, 28 do
    W.power[0] = { pct * 10, 1000 }
    Fire("UNIT_POWER_UPDATE", "player", "MANA"); Settle()
  end
  Check(Shown("r3") and #PLAYED == played, "mana changing below the threshold: no further sound")
  Check(CT.Snapshot().timed == 0, "no time boundary for a resource")
  W.power[0] = { 300, 1000 }
  Fire("UNIT_POWER_UPDATE", "player", "MANA"); Settle()
  Check(not Shown("r3"), "back to exactly 30%: hidden")
  W.power[0] = { SECRET, 1000 }
  Fire("UNIT_POWER_UPDATE", "player", "MANA"); Settle()
  Check(ST.Observations().power.MANA == nil and not Shown("r3"), "a secret value: unknown, never compared")
  W.power[0] = { 0, 0 }
  Fire("UNIT_MAXPOWER", "player", "MANA"); Settle()
  Check(ST.Observations().power.MANA == "none" and not Shown("r3"), "no mana pool: 'none', not 0%")
  local reads = ST.Snapshot().reads
  Fire("UNIT_POWER_UPDATE", "player", "RAGE"); Settle()
  Check(ST.Snapshot().reads == reads, "another resource's update reads nothing")
end

do
  -- bags, items, durability, spells, forms, level, cooldowns, group, place, target, moving, flight path: each read and updated
  W.bags = { [0] = { slots = 16, free = 2, family = 0 }, [1] = { slots = 18, free = 18, family = 1 }, [2] = { slots = 10, free = 1, family = 0 } }
  W.counts[17020] = 4
  W.dur = { [1] = { 50, 60 }, [5] = { 0, 100 }, [11] = nil }
  W.known[122], W.exists[99999] = true, false
  local cdStart = NOW
  W.cd[122] = { isEnabled = true, isActive = true, isOnGCD = false, startTime = cdStart, duration = 25 }
  W.forms, W.form = { 5487, 768 }, 2
  W.group = true
  W.map = 5001
  W.target = "enemy"
  Use({ { id = "r4", name = "All", enabled = true, match = "any", display = { mode = "text", text = "x" }, conditions = {
    { type = "bagSpace", compare = "below", count = 5 }, { type = "itemCount", item = 17020, compare = "below", count = 10 },
    { type = "durability", what = "broken" }, { type = "spellKnown", spell = 122 }, { type = "spellKnown", spell = 99999, negate = true },
    { type = "spellKnown", spell = 133 },
    { type = "form", form = 768 }, { type = "level", compare = "below", level = 60 }, { type = "cooldown", spell = 122, what = "within", seconds = 5 },
    { type = "groupType", what = "party" }, { type = "zone", map = 1429 }, { type = "target", what = "attackable" },
    { type = "player", state = "moving" }, { type = "player", state = "taxi" } } } })
  CT.Refresh(); Settle()
  local o = ST.Observations()
  Check(o.bagFree == 3, "free slots: the general bags only (a quiver's room doesn't count): " .. tostring(o.bagFree))
  Check(o.itemCount[17020] == 4, "item count read")
  Check(o.durability and o.durability.broken and #o.durability.items == 2, "durability item by item, items without it left out")
  Check(o.spellKnown[122] == true and o.spellKnown[99999] == "invalid", "known spell, and a spell the game doesn't have: " .. tostring(o.spellKnown[122]) .. " " .. tostring(o.spellKnown[99999]))
  Check(o.spellKnown[133] == false, "a real spell you don't know reads as not known, not unknown")
  Check(o.form == 768 and o.level == 20 and o.groupType == "party", "form by its spell ID, level, group")
  Check(o.zone and o.zone.chain[1] == 5001 and o.zone.chain[2] == 1429 and o.zone.chain[3] == 1415 and #o.zone.chain == 3, "the map and those it lies in, up to the continent")
  Check(o.target and o.target.exists and o.target.attackable and o.moving == false and o.taxi == false, "target, moving and flight path read")
  Check(o.cooldown[122].state == "cooling" and o.cooldown[122].ends == cdStart + 25, "a cooldown and its end")
  local out = CT.Inspect("r4")
  local seen = {}
  for _, row in ipairs(out.conditions) do seen[#seen + 1] = row.result end
  Check(seen[5] == UNKNOWN, "a spell the game doesn't have: unknown even under 'don't know'")
  Check(CT.Snapshot().timed == 1, "the cooldown's end is a time boundary")
  -- each changes with its event
  W.bags[0].free = 10; Fire("BAG_UPDATE_DELAYED"); Settle()
  Check(ST.Observations().bagFree == 11, "bags changed")
  W.level = 21; Fire("PLAYER_LEVEL_UP", 22); Settle()
  Check(ST.Observations().level == 22, "the level the event carries counts (UnitLevel can lag)")
  W.form = 0; Fire("UPDATE_SHAPESHIFT_FORM"); Settle()
  Check(ST.Observations().form == "none", "no form")
  W.raid = true; Fire("GROUP_ROSTER_UPDATE"); Settle()
  Check(ST.Observations().groupType == "raid", "now a raid group")
  W.map = 1453; Fire("ZONE_CHANGED_NEW_AREA"); Settle()
  Check(ST.Observations().zone.chain[1] == 1453, "moved to Stormwind")
  W.target = nil; Fire("PLAYER_TARGET_CHANGED"); Settle()
  Check(ST.Observations().target.exists == false, "target cleared")
  Fire("PLAYER_STARTED_MOVING"); Settle()
  Check(ST.Observations().moving == true, "started moving (the event says it)")
  W.taxi = true; Fire("PLAYER_CONTROL_LOST"); Settle()
  Check(ST.Observations().taxi == true, "on a flight path")
  W.dur[5] = { 100, 100 }; Fire("UPDATE_INVENTORY_DURABILITY"); Settle()
  Check(not ST.Observations().durability.broken, "repaired")
  -- the cooldown ends with no event: the boundary reads it again
  W.cd[122] = { isEnabled = true, isActive = false, isOnGCD = false, startTime = 0, duration = 0 }
  Advance(26)
  Check(ST.Observations().cooldown[122].state == "ready", "the cooldown's end is seen without an event")
  -- no polling: nothing is read without an event or a boundary
  local reads = ST.Snapshot().reads
  Advance(120)
  Check(ST.Snapshot().reads == reads and CT.Snapshot().timed == 0, "no polling")
  -- off: nothing listened for, nothing kept
  c.TwichUIDB.modules.reminders = false
  CT.Refresh()
  Check(not Registered("BAG_UPDATE_DELAYED") and not Registered("UNIT_AURA") and next(ST.Observations().slots) == nil and ST.Observations().zone == nil, "switched off: nothing heard or kept")
  c.TwichUIDB.modules.reminders = nil
  CT.Refresh(); Settle()
end

do
  -- weapon enchant running out, with an end the game gives in milliseconds and no event when it runs out
  W.eq[16] = 100
  W.ench[0] = 400 * 1000
  Use({ { id = "r5", name = "Oil", enabled = true, match = "all", display = { mode = "text", text = "Oil" },
    conditions = { { type = "weaponEnchant", hand = "mainHand", what = "expiring", seconds = 300 } } } })
  CT.Refresh(); Fire("PLAYER_ENTERING_WORLD"); Settle()
  Check(math.abs(ST.Observations().enchant.ends.mainHand - (NOW + 400)) < 0.5, "the end, from milliseconds")
  Check(not Shown("r5"), "400 s left: hidden")
  W.ench[0] = (400 - 101) * 1000
  Advance(101)
  Check(Shown("r5"), "under five minutes: shown at the boundary, with no event")
  local reads = ST.Snapshot().reads
  W.ench[0] = (400 - 101 - 1) * 1000; NOW = NOW + 1
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Shown("r5"), "a read a second later is the same end: still shown")
  W.ench[0] = nil
  Advance(300)
  Check(not Shown("r5") and ST.Observations().enchant.mainHand == "bare", "run out with no event: read at its end, gone (it is 'missing' now)")
  Check(ST.Snapshot().reads > reads, "it was read")
end

---------------------------------------------------------------------------
-- 8. The builder: entries, words, fields
---------------------------------------------------------------------------
do
  local byKey = {}
  for _, e in ipairs(Pl.Entries()) do byKey[e.key] = e end
  for key, cat in pairs({ aura = "Buffs", ["aura:harmful"] = "Buffs", itemCount = "Supplies", bagSpace = "Supplies", durability = "Equipment",
    power = "Character", spellKnown = "Character", form = "Character", level = "Character", cooldown = "Combat", target = "Combat",
    groupType = "Places and group", zone = "Places and group", ["player:moving"] = "Other", ["player:taxi"] = "Other" }) do
    Check(byKey[key] and byKey[key].category == cat, "the palette offers " .. key .. " under " .. cat)
  end
  for _, cat in ipairs(Pl.PALETTE_ORDER) do
    local known = false
    for _, c2 in ipairs(Pl.CATEGORIES) do if c2 == cat then known = true end end
    Check(known, cat .. " is a filter choice too")
  end
  Check(Pl.Matches(byKey.aura, "buff") and Pl.Matches(byKey["aura:harmful"], "debuff") and Pl.Matches(byKey.bagSpace, "bag")
    and Pl.Matches(byKey.durability, "durab") and Pl.Matches(byKey.cooldown, "cooldown") and not Pl.Matches(byKey.level, "zzz"), "search finds them")
  -- every new kind has its own picture or icon, not the default
  local art = {}
  for key, e in pairs(byKey) do
    local cond = e.make()
    local file = Pl.ArtFile(cond, 45)
    local id = file or Pl.Icon(cond)
    if key ~= "player:dungeon" and key ~= "player:raid" then
      Check(id ~= "reminderTest", key .. " has artwork of its own")
      if art[id] and not (key:find("^player:") and art[id]:find("^player:")) then
        Check(false, key .. " shares artwork with " .. art[id])
      end
      art[id] = art[id] or key
    end
  end
  -- sentences use the chosen values
  local function S(raw) return Pl.CondSentence(C.Check(raw)) end
  Check(S({ type = "aura", spells = { 1459 }, what = "missing" }) == "You are missing Arcane Intellect", S({ type = "aura", spells = { 1459 }, what = "missing" }))
  Check(S({ type = "aura", spells = { 1459, 10157 }, what = "present" }) == "You have Arcane Intellect", "two ranks of one name read as one")
  Check(S({ type = "aura", spells = { 1459 }, what = "expiring", seconds = 90 }) == "Your Arcane Intellect has less than 1 minute 30 seconds left", S({ type = "aura", spells = { 1459 }, what = "expiring", seconds = 90 }))
  Check(S({ type = "power", power = "MANA", compare = "below", percent = 30 }) == "Your mana is below 30%", "mana")
  Check(S({ type = "itemCount", item = 17020, compare = "below", count = 10 }) == "You carry fewer than 10 Arcane Powder", "item count")
  Check(S({ type = "weaponEnchant", hand = "mainHand", what = "expiring", seconds = 300 }) == "Your main hand weapon enchant has less than 5 minutes left", "enchant running out")
  Check(S({ type = "spellKnown", spell = 122, negate = true }) == "You don't know Frost Nova", "spell known")
  Check(S({ type = "zone", map = 1453 }) == "You are in Stormwind City", "place by its map's name")
  Check(S({ type = "groupType", what = "raid" }) == "You are in a raid group", "group")
  Check(S({ type = "target", what = "attackable", negate = true }) == "Your target can't be attacked", "target")
  Check(S({ type = "player", state = "moving", negate = true }) == "You are standing still", "standing still")
  -- fields: at most three on a card, the amount with quick choices and its own
  for _, raw in ipairs({ { type = "aura", spells = { 1 }, what = "stacks", stacks = 7, compare = "below" }, { type = "power", power = "MANA", compare = "below", percent = 33 },
    { type = "itemCount", item = 1, compare = "below", count = 3 }, { type = "weaponEnchant", hand = "offHand", what = "expiring", seconds = 45 },
    { type = "cooldown", spell = 1, what = "within", seconds = 10 }, { type = "durability", what = "below", percent = 20 }, { type = "zone", map = 1453 } }) do
    local fields = Pl.CardFields(C.Check(raw))
    Check(#fields >= 1 and #fields <= 3, raw.type .. ": fits a card")
  end
  local aura = C.Check({ type = "aura", spells = { 1459 }, what = "stacks", stacks = 7, compare = "below" })
  local amount = Pl.EditField(aura, "amount")
  Check(amount and amount.kind == "number" and amount.value == 7 and amount.label == "7 stacks", "the amount shows the stored number")
  local other = false
  for _, ch in ipairs(amount.choices) do if ch.value == Pl.OTHER then other = true end end
  Check(other, "and offers another amount")
  local five = Pl.WithCardField(aura, amount, 5)
  Check(five.stacks == 5 and aura.stacks == 7, "a quick choice makes a new condition, the old one untouched")
  Check(Pl.WithCardField(aura, amount, Pl.OTHER) == nil, "'Other amount' changes nothing by itself (the editor opens)")
  local value = Pl.EditField(aura, "value")
  local exp = Pl.WithCardField(aura, value, "expiring")
  Check(exp.what == "expiring" and exp.seconds == R.ReminderAuras.SECONDS_DEFAULT and C.Check(exp).stacks == nil, "switching to running out starts at a deliberate time")
  local deb = Pl.WithCardField(aura, Pl.EditField(aura, "subject"), "harmful")
  Check(deb.harmful == true and Pl.CardTitle(deb) == "Debuff", "buff or debuff")
  Check(Pl.WithNumber(aura, "stacks", 12).stacks == 12, "a typed number")
  local op = Pl.EditField(C.Check({ type = "itemCount", item = 1, compare = "below", count = 3 }), "op")
  Check(op.label == "Fewer than" and op.choices[2].label == "At least", "the comparison reads naturally")
  Check(Pl.HasOperator({ type = "spellKnown" }) and not Pl.HasOperator({ type = "itemCount" }) and not Pl.HasOperator({ type = "aura" }), "is / is not only where it is stored")
  -- IDs
  Check(Pl.NeedsId(aura) == "spell" and Pl.NeedsId({ type = "itemCount" }) == "item" and Pl.NeedsItem({ type = "equipment", what = "item" }) and Pl.NeedsId({ type = "level" }) == nil, "which ID a condition asks for")
  local ids = Pl.ParseSpells("1459, 10157 ,1459")
  Check(ids and #ids == 2 and ids[2] == 10157, "several spell IDs, once each")
  Check(Pl.ParseSpells("|cff71d5ff|Hspell:1459:0|h[Arcane Intellect]|h|r")[1] == 1459, "a spell link")
  Check(Pl.ParseSpells("Arcane Intellect") == nil, "a name is never taken as a spell")
  Check(select(2, Pl.ParseSpells("1 2 3 4 5 6 7 8 9", 8)) == "many", "too many is said")
  Check(Pl.WithIds(C.Check({ type = "aura", spells = {}, what = "missing" }), { 1, 2 }).spells[2] == 2 and Pl.WithIds({ type = "cooldown", what = "ready" }, { 9 }).spell == 9, "IDs into the condition")
  Check(Pl.IdButton(C.Check({ type = "aura", spells = {}, what = "missing" })) == "Choose buff" and Pl.IdButton(aura) == "Change buff", "the card's button")
  Check(Pl.SpellLine(aura) == "Arcane Intellect", "what the IDs are")
  -- an unsupported client says so
  local saved = c.GetShapeshiftForm
  c.GetShapeshiftForm = nil
  local _, problem = C.Check({ type = "form", state = "none" })
  local short = Pl.Capability({ cond = C.Check({ type = "form", state = "none" }) })
  Check(type(problem) == "string" and short ~= nil, "a client without forms: kept, said so, can't be turned on")
  c.GetShapeshiftForm = saved
end

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
