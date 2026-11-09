-- Action bar glows (glows/): Catalog.lua is the built-in list, Config.lua stores and checks, Logic.lua decides (pure),
-- Buttons.lua finds the buttons, State.lua reads the game, Draw.lua draws, Controller.lua runs it. A fake world stands in
-- for the game (action slots, auras, cooldowns, weapons, tracking, a group, secret values), so this checks our logic,
-- not the game: the in-game checks are in docs/bar-glows.md.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

---------------------------------------------------------------------------
-- A fake world
---------------------------------------------------------------------------
local frames = {}
local Methods
local onUpdates = 0
local function Fake(kind)
  local o = { kind = kind, shown = kind ~= "Frame" and kind ~= "Button", scripts = {}, events = {}, unitEvents = {}, points = {}, attrs = {},
    alpha = 1, w = 36, h = 36, level = 5, children = {} }
  frames[#frames + 1] = o
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
local function Anim()
  local a = Fake("anim")
  a.playing = false
  a.CreateAnimation = function(self) local x = Fake("animation"); x.group = self; return x end
  a.Play = function(self) self.playing = true end
  a.Stop = function(self) self.playing = false end
  a.IsPlaying = function(self) return self.playing end
  return a
end
Methods = {
  Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end,
  IsShown = function(s) return s.shown end, SetShown = function(s, v) s.shown = v and true or false end,
  IsVisible = function(s) return s.shown end,
  SetScript = function(s, n, fn) s.scripts[n] = fn; if n == "OnUpdate" and fn then onUpdates = onUpdates + 1 end end,
  GetScript = function(s, n) return s.scripts[n] end,
  HookScript = function(s, n) if n == "OnUpdate" then onUpdates = onUpdates + 1 end end,
  RegisterEvent = function(s, e) s.events[e] = true end,
  RegisterUnitEvent = function(s, e, u) s.events[e] = true; s.unitEvents[e] = u end,
  UnregisterEvent = function(s, e) s.events[e] = nil; s.unitEvents[e] = nil end,
  UnregisterAllEvents = function(s) s.events = {}; s.unitEvents = {} end,
  IsEventRegistered = function(s, e) return s.events[e] == true end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; s.children[#s.children + 1] = t; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  CreateAnimationGroup = function(s) local a = Anim(); a.parent = s; return a end,
  SetText = function(s, v) s.text = v end, GetText = function(s) return s.text end,
  SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end, ClearAllPoints = function(s) s.points = {} end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  GetEffectiveScale = function() return 1 end,
  SetFrameLevel = function(s, l) s.level = l end, GetFrameLevel = function(s) return s.level end,
  SetAtlas = function(s, a) s.atlas = a end, SetTexture = function(s, p) s.texture = p end,
  SetVertexColor = function(s, r, g, b) s.color = { r, g, b } end, SetColorTexture = function(s, r, g, b) s.color = { r, g, b } end,
  SetTextColor = function(s, r, g, b) s.color = { r, g, b } end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; return true end,
  GetStringWidth = function(s) return #(s.text or "") * 8 end,
  GetAttribute = function(s, k) return s.attrs[k] end, SetAttribute = function(s, k, v) s.attrs[k] = v end,
}
c.CreateFrame = function(kind, name, parent)
  local f = Fake(kind)
  f.name, f.parent = name, parent
  if name then c[name] = f end
  return f
end
c.UIParent = Fake("UIParent")
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
c.Enum = { PowerType = { ComboPoints = 4, Mana = 0 }, ItemClass = { Weapon = 2 }, SpellBookSpellBank = { Player = 0 } }

local SECRET_MT = { __lt = function() error("compared a secret value") end, __le = function() error("compared a secret value") end,
  __eq = function() error("compared a secret value") end, __concat = function() error("formatted a secret value") end,
  __index = function() error("indexed a secret value") end }
local function SecretValue() return setmetatable({}, SECRET_MT) end
local secrets = setmetatable({}, { __mode = "k" })
c.issecretvalue = function(v) return type(v) == "table" and secrets[v] == true end
local function Secret() local s = SecretValue(); secrets[s] = true; return s end

local NOW = 1000
c.GetTime = function() return NOW end

-- spells: id -> { name, rank }
local SPELLS = {
  [1459] = { "Arcane Intellect", 1 }, [10157] = { "Arcane Intellect", 5 }, [23028] = { "Arcane Brilliance", 1 },
  [168] = { "Frost Armor", 1 }, [7302] = { "Ice Armor", 1 }, [6117] = { "Mage Armor", 1 },
  [12051] = { "Evocation" }, [12043] = { "Presence of Mind" }, [3561] = { "Teleport: Stormwind" },
  [116] = { "Frostbolt", 1 }, [205] = { "Frostbolt", 2 }, [10181] = { "Frostbolt", 11 },
  [1243] = { "Power Word: Fortitude", 1 }, [21562] = { "Prayer of Fortitude", 1 },
  [7384] = { "Overpower", 1 }, [6572] = { "Revenge", 1 }, [5308] = { "Execute", 1 },
  [2383] = { "Find Herbs" }, [2580] = { "Find Minerals" }, [8017] = { "Rockbiter Weapon", 1 }, [8232] = { "Windfury Weapon", 1 },
  [21084] = { "Seal of Righteousness", 1 }, [21082] = { "Seal of the Crusader", 1 },
}
local ITEMS = { [17020] = "Arcane Powder", [17031] = "Rune of Teleportation", [6947] = "Instant Poison", [8079] = "Conjured Crystal Water", [4306] = "Silk Cloth" }

local G
local function World()
  G = { class = "MAGE", known = {}, auras = {}, combat = false, resting = false, dead = false, group = nil, units = {},
    slots = {}, cooldowns = {}, usable = {}, counts = {}, weapon = { main = 25, off = nil, mainEnchant = false, offEnchant = false },
    tracking = {}, target = nil, power = 0, secretAuras = false }
end
World()
c.UnitClass = function(u)
  if u == "player" then return G.class, G.class end
  local m = G.units[u]
  if m then return m.class, m.class end
end
c.UnitName = function(u) if u == "player" then return "Rich" end local m = G.units[u]; return m and m.name end
c.GetRealmName = function() return "Forever" end
c.InCombatLockdown = function() return G.combat end
c.UnitAffectingCombat = function() return G.combat end
c.IsResting = function() return G.resting end
c.UnitIsDeadOrGhost = function(u) if u == "player" then return G.dead end local m = G.units[u]; return m and m.dead or false end
c.UnitOnTaxi = function() return false end
c.UnitExists = function(u) if u == "target" then return G.target ~= nil end return G.units[u] ~= nil end
c.UnitCanAttack = function() return G.target == "enemy" end
c.UnitIsDead = function() return false end
c.IsInRaid = function() return G.group == "raid" end
c.IsInGroup = function() return G.group ~= nil end
c.UnitIsUnit = function(a, b) return a == b end
c.UnitIsConnected = function() return true end
c.UnitCanAssist = function() return true end
c.UnitPower = function() return G.power end
c.C_SpellBook = {
  IsSpellKnown = function(id) return G.known[id] == true end,
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() local n = 0 for _ in pairs(G.known) do n = n + 1 end return { itemIndexOffset = 0, numSpellBookItems = n } end,
  GetSpellBookItemInfo = function(i)
    local ids = {}
    for id in pairs(G.known) do ids[#ids + 1] = id end
    table.sort(ids)
    local id = ids[i]
    local s = id and SPELLS[id]
    if not s then return nil end
    return { spellID = id, name = s[1], subName = s[2] and ("Rank " .. s[2]) or "", isPassive = false }
  end,
}
c.C_Spell = {
  GetSpellName = function(id) local s = SPELLS[id]; return s and s[1] end,
  GetSpellSubtext = function(id) local s = SPELLS[id]; return s and s[2] and ("Rank " .. s[2]) or nil end,
  GetSpellTexture = function(id) return 100000 + id end,
  GetSpellCooldown = function(id)
    local cd = G.cooldowns[id]
    if cd == "secret" then return { isEnabled = true, isActive = true, startTime = Secret(), duration = Secret() } end
    if not cd then return { isEnabled = true, isActive = false, startTime = 0, duration = 0 } end
    return { isEnabled = true, isActive = true, startTime = cd.start, duration = cd.duration }
  end,
  IsSpellUsable = function(id) return G.usable[id] == true, false end,
  IsSpellInRange = function(_, unit) local m = G.units[unit]; return m and m.inRange ~= false end,
}
c.C_UnitAuras = {
  GetAuraDataByIndex = function(u, i)
    if G.secretAuras then return Secret() end
    local list = u == "player" and G.auras or (G.units[u] and G.units[u].auras) or {}
    local name = list[i]
    if name then return { name = name } end
  end,
}
c.C_Item = {
  GetItemCount = function(id) return G.counts[id] or 0 end,
  GetItemNameByID = function(id) return ITEMS[id] end,
  GetItemInfoInstant = function(id) if id == 25 then return id, nil, nil, nil, nil, 2 end if ITEMS[id] then return id, nil, nil, nil, nil, 0 end end,
  GetItemSpell = function(id) if id == 6947 then return "Instant Poison" end end,
  GetItemIconByID = function() return 1 end,
}
c.GetInventoryItemID = function(_, slot) if slot == 16 then return G.weapon.main end if slot == 17 then return G.weapon.off end end
c.C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(slot)
  if slot == 16 and G.weapon.mainEnchant then return { enchantID = 1 } end
  if slot == 17 and G.weapon.offEnchant then return { enchantID = 2 } end
end }
c.C_Minimap = {
  GetNumTrackingTypes = function() return #G.tracking end,
  GetTrackingInfo = function(i) local t = G.tracking[i]; return t and { name = t.name, active = t.active, type = "spell", spellID = t.id } end,
}
c.GetNumShapeshiftForms = function() return 0 end
-- action slots: slot -> { "spell", id } | { "macro", id, spell } | { "item", id }
c.GetActionInfo = function(slot) local s = G.slots[slot]; if s then return s[1], s[2] end end
c.GetMacroSpell = function(id) for _, s in pairs(G.slots) do if s[1] == "macro" and s[2] == id then return s[3] end end end
c.GetMacroItem = function() return nil end
local sounds = {}
c.PlaySoundFile = function(path) sounds[#sounds + 1] = path; return true end
-- nothing may ever act for the player
local acted = {}
for _, name in ipairs({ "CastSpellByName", "CastSpellByID", "UseAction", "UseItemByName", "SendChatMessage", "TargetUnit", "PickupAction", "PlaceAction" }) do
  c[name] = function() acted[#acted + 1] = name end
end

local function Fire(event, ...)
  c.FireEvent(event, ...)
  local arg1 = ...
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent and (not f.unitEvents[event] or f.unitEvents[event] == arg1) then
      f.scripts.OnEvent(f, event, ...)
    end
  end
end

-- Buttons: Blizzard's bar 1 (slots 1-12) and EllesmereUI's bar 2 (EABButton61-72, slot from its attribute)
local function Button(name, slot, attr)
  local b = Fake("CheckButton")
  b.shown = true
  b.name = name
  if attr then b.attrs.action = slot else b.action = slot end
  c[name] = b
  return b
end
local AB = {}
for i = 1, 12 do AB[i] = Button("ActionButton" .. i, i) end
local EAB = {}
for i = 0, 11 do EAB[i + 1] = Button("EABButton" .. (61 + i), 61 + i, true) end

for _, f in ipairs({ "modules/Media.lua", "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "modules/Notify.lua", "modules/NotifyLook.lua", "modules/Arrival.lua", "glows/Catalog.lua", "glows/Config.lua", "glows/Logic.lua", "glows/Buttons.lua", "glows/State.lua",
  "glows/Draw.lua", "glows/Notice.lua", "glows/Controller.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local CAT, BG, LG, BT, ST, D, CT = R.BarGlowCatalog, R.BarGlows, R.BarGlowLogic, R.BarGlowButtons, R.BarGlowState, R.BarGlowDraw, R.BarGlowController
local NT = R.BarGlowNotice

local function Settle() for _ = 1, 4 do FlushTimers() end end
local function Glowing(b) return D.IsGlowing(b) end

---------------------------------------------------------------------------
-- 1. The catalogue
---------------------------------------------------------------------------
do
  local seen, ok = {}, true
  for _, e in ipairs(CAT.ENTRIES) do
    local id = e.type .. ":" .. e.key
    if seen[id] then ok = false end
    seen[id] = true
    if not (e.spell or e.items or e.reagent) then ok = false; print("no spell or item: " .. id) end
    if e.type == "lowReagent" and not (e.spells and #e.spells > 0) then ok = false end
  end
  Check(ok, "every entry has a unique key and something to watch")
  Check(#CAT.For("missingBuff", "MAGE") >= 4 and CAT.Find("missingBuff", "intellect").group.spell == 23028, "the mage's buffs, with the group version")
  Check(#CAT.Categories.aspect == 6 and #CAT.Categories.seal == 6, "exclusive groups: six aspects, six seals")
  local racials = 0
  for _, e in ipairs(CAT.For("readyCooldown", "MAGE")) do if e.racial then racials = racials + 1 end end
  Check(racials == 7, "everyone's racials are listed for every class")
  Check(CAT.ForClass(CAT.Find("lowReagent", "lightFeather"), "PRIEST") and CAT.ForClass(CAT.Find("lowReagent", "lightFeather"), "MAGE")
    and not CAT.ForClass(CAT.Find("lowReagent", "lightFeather"), "ROGUE"), "a reagent shared by two classes")
end

---------------------------------------------------------------------------
-- 2. Settings: checked on the way in and out; defaults are read, never written
---------------------------------------------------------------------------
do
  Check(BG.Get("partyGroupFrom") == 2 and BG.Get("quietInTowns") == true, "defaults")
  Check(BG.Set("partyGroupFrom", 9) == false and BG.Set("partyGroupFrom", 2.5) == false and BG.Get("partyGroupFrom") == 2, "out of range refused")
  Check(c.TwichUIDB.ui == nil or c.TwichUIDB.ui.barGlows == nil, "nothing stored by reading")
  Check(BG.SetBar("bar3", false) and BG.BarOn("bar3") == false and BG.BarOn("bar1"), "a bar turned off is kept")
  Check(BG.SetBar("bar3", true) and c.TwichUIDB.ui.barGlows.bars.bar3 == nil, "back on: nothing stored")
  Check(BG.SetBar("bar99", false) == false, "an unknown bar refused")
  Check(BG.SetTypeEnabled("proc", false) and not BG.TypeEnabled("proc") and BG.SetTypeEnabled("proc", true) and BG.TypeEnabled("proc"), "a kind off and on")
  Check(BG.SpellEnabled("missingBuff", "thorns") == false and BG.SpellEnabled("missingBuff", "intellect"), "built-in defaults: Thorns off, Intellect on")
  BG.SetSpellEnabled("missingBuff", "thorns", true)
  Check(BG.SpellEnabled("missingBuff", "thorns"), "Thorns turned on")
  BG.SetSpellEnabled("missingBuff", "thorns", false)
  Check(c.TwichUIDB.ui.barGlows.spells == nil or c.TwichUIDB.ui.barGlows.spells["missingBuff:thorns"] == nil, "back to its default: nothing left stored")
  -- looks: the kind's, the built-in entry's own "when", then the entry's own
  Check(BG.Style("missingBuff", "battleShout").when == "inCombat" and BG.Style("missingBuff", "intellect").when == "always", "Battle Shout ships for combat")
  Check(BG.SetTypeField("missingBuff", "color", "ff00ff00") and BG.Style("missingBuff", "intellect").color == "ff00ff00", "the kind's color reaches its rows")
  Check(BG.SetSpellField("missingBuff", "intellect", "color", "ffff0000") and BG.Style("missingBuff", "intellect").color == "ffff0000"
    and BG.Style("missingBuff", "fortitude").color == "ff00ff00", "a row's own color wins for that row only")
  Check(BG.SetSpellField("missingBuff", "intellect", "when", "townAlert") == false, "Alert in town is only for reagents and stock")
  Check(BG.SetSpellField("missingBuff", "intellect", "opacity", 5) == false and BG.SetSpellField("missingBuff", "intellect", "look", "neon") == false, "bad values refused")
  BG.SetSpellEnabled("missingBuff", "intellect", false)
  BG.ResetSpell("missingBuff", "intellect")
  Check(BG.Style("missingBuff", "intellect").color == "ff00ff00" and not BG.SpellEnabled("missingBuff", "intellect"), "Reset keeps the on/off")
  BG.SetSpellEnabled("missingBuff", "intellect", true)
  BG.SetTypeField("missingBuff", "color", BG.TYPE_DEFAULTS.missingBuff.color)
  Check(c.TwichUIDB.ui.barGlows.types == nil or c.TwichUIDB.ui.barGlows.types.missingBuff == nil, "the default color itself is not stored")
  -- limits
  Check(BG.Below("lowReagent", "soulShard") == 3 and BG.Below("lowReagent", "arcanePowder") == 10, "a reagent's own limit, else the setting")
  BG.Set("reagentBelow", 15)
  Check(BG.Below("lowReagent", "arcanePowder") == 15, "the setting")
  Check(BG.SetBelow("lowReagent", "arcanePowder", 4) and BG.Below("lowReagent", "arcanePowder") == 4, "a row's own limit")
  Check(BG.SetBelow("missingBuff", "intellect", 4) == false, "only reagents and stock have limits")
  BG.ResetSpell("lowReagent", "arcanePowder")
  BG.Set("reagentBelow", 10)
  -- adding
  local ok, key = BG.Add({ kind = "lowStock", item = 8079 })
  Check(ok and key == "i8079" and BG.Below("lowStock", key) == 20, "an item added as low stock")
  Check(select(2, BG.Add({ kind = "lowStock", item = 8079 })) == "duplicate", "twice refused")
  Check(select(2, BG.Add({ kind = "lowStock", spell = 12051 })) == "invalid", "low stock takes an item, not a spell")
  Check(select(2, BG.Add({ kind = "readyCooldown", spell = 12051 })) == "builtin", "a built-in spell is not added again")
  Check(BG.Add({ kind = "weaponBuff", item = 4306 }) and BG.FindAdded("weaponBuff", "i4306").slot == "both", "a weapon item: either hand by default")
  Check(BG.Remove("weaponBuff", "i4306") and BG.FindAdded("weaponBuff", "i4306") == nil, "removed")
  for i = 1, BG.MAX_ADDED do BG.Add({ kind = "proc", spell = 50000 + i }) end
  Check(select(2, BG.Add({ kind = "proc", spell = 59999 })) == "full", "bounded")
  for i = 1, BG.MAX_ADDED do BG.Remove("proc", "s" .. (50000 + i)) end
  -- the per-character record, kept out of profiles
  Check(BG.Remember("aspect", "aspectOfTheHawk") and BG.Remembered("aspect") == "aspectOfTheHawk", "what was used last")
  Check(c.TwichUIDB.ui.barGlowsMemory["Rich - Forever"].last.aspect == "aspectOfTheHawk", "kept per character")
  Check(R.Profiles and R.Profiles.ACCOUNT.ui.barGlowsMemory == true, "never part of a profile")
  Check(BG.Remember("aspect", "bad key!") == false, "a key must be plain")
  Check(BG.SetWeapon("mainHand", "windfury") and BG.Weapon("mainHand") == "windfury" and BG.SetWeapon("mainHand", "auto") and BG.Weapon("mainHand") == "auto", "the weapon choice")
  Check(R.DEFAULT_MODULES.barGlows == true, "on by default")
  local TC = R.TwichConfig
  Check(TC.LOCAL["ui.barGlows"] == "other" and TC.LOCAL["ui.barGlowsMemory"] == "other", "the choices and the record stay out of a shared setup")
end

---------------------------------------------------------------------------
-- 3. The decisions (pure)
---------------------------------------------------------------------------
local function Obs(t)
  local o = {
    class = t.class or "MAGE", ctx = t.ctx or { combat = false, resting = false, group = "none" },
    auras = t.auras, name = function(id) local s = SPELLS[id]; return s and s[1]:lower() end,
    display = function(id) local s = SPELLS[id]; return s and s[1] end,
    itemDisplay = function(id) return ITEMS[id] end, itemSpell = function() return nil end,
    known = function(id) return (t.known or {})[id] == true end,
    onBars = function(n) return t.bars == nil or t.bars[n] == true end,
    count = function(id) return (t.counts or {})[id] or 0 end,
    weapon = t.weapon, tracking = t.tracking, members = t.members, ranks = t.ranks,
    ready = function(id) local r = (t.ready or {})[id]; if r == nil then return true end return r end,
    usable = function(id) return (t.usable or {})[id] == true end,
    window = function(key) return (t.window or {})[key] == true end,
    remembered = function(cat) return (t.remembered or {})[cat] end,
    blessing = function(class) return (t.blessings or {})[class] end,
  }
  return o
end
local function Ids(due)
  local out = {}
  for _, r in ipairs(due) do out[#out + 1] = r.id end
  return table.concat(out, ",")
end
local function Find(due, id) for _, r in ipairs(due) do if r.id == id then return r end end end

do
  local ctx = { combat = false, resting = true }
  Check(select(1, LG.When("missingBuff", { when = "always" }, ctx, true)) == false, "quiet in towns: no glow while resting out of combat")
  local glow, alert = LG.When("lowReagent", { when = "townAlert" }, { resting = false }, true)
  Check(glow and not alert, "Alert in town: glows anywhere, message only in town")
  glow, alert = LG.When("lowReagent", { when = "townAlert" }, { resting = true }, true)
  Check(glow and alert, "... and in town both")
  Check(LG.When("x", { when = "inCombat" }, { combat = true }) and not LG.When("x", { when = "inCombat" }, { combat = false }), "in combat")
  Check(LG.When("x", { when = "enemyTargeted" }, { enemy = true }) and not LG.When("x", { when = "always" }, { dead = true }), "an enemy targeted; never while dead")

  -- your own buffs
  local mage = { [1459] = true, [168] = true, [7302] = true, [6117] = true }
  local due = LG.Due(Obs({ known = mage, auras = {} }), BG)
  Check(Find(due, "missingBuff:intellect") and Find(due, "missingBuff:frostArmor"), "Intellect and an armor missing: " .. Ids(due))
  Check(Find(due, "missingBuff:intellect").spells[1] == "arcane intellect", "matched by name, every rank")
  due = LG.Due(Obs({ known = mage, auras = { ["arcane brilliance"] = true, ["mage armor"] = true } }), BG)
  Check(not Find(due, "missingBuff:intellect") and not Find(due, "missingBuff:frostArmor"), "the group version counts; any armor counts: " .. Ids(due))
  due = LG.Due(Obs({ known = mage, auras = nil }), BG)
  Check(#due == 0 or not Find(due, "missingBuff:intellect"), "auras unknown: nothing glows")
  due = LG.Due(Obs({ known = mage, auras = {}, remembered = { mageArmor = "mageArmor" } }), BG)
  Check(Find(due, "missingBuff:mageArmor") and not Find(due, "missingBuff:frostArmor"), "the armor used last glows")
  due = LG.Due(Obs({ known = { [1459] = true, [168] = true }, auras = {}, remembered = { mageArmor = "mageArmor" } }), BG)
  Check(Find(due, "missingBuff:frostArmor"), "the one used last not known: the first one known")
  BG.SetSpellEnabled("missingBuff", "intellect", false)
  due = LG.Due(Obs({ known = mage, auras = {} }), BG)
  Check(not Find(due, "missingBuff:intellect"), "a spell turned off")
  BG.SetSpellEnabled("missingBuff", "intellect", true)
  BG.SetTypeEnabled("missingBuff", false)
  due = LG.Due(Obs({ known = mage, auras = {} }), BG)
  Check(not Find(due, "missingBuff:intellect") and not Find(due, "missingBuff:frostArmor"), "the kind turned off")
  BG.SetTypeEnabled("missingBuff", true)
  due = LG.Due(Obs({ known = mage, auras = {}, bars = {} }), BG)
  Check(Find(due, "missingBuff:intellect").notOnBars, "not on your bars: said so")

  -- group members
  local function Member(name, class, auras, inRange) return { name = name, class = class, mana = CAT.MANA[class] == true, auras = auras or {}, inRange = function() return inRange ~= false end } end
  local party = { ctx = { group = "party" }, known = { [1459] = true, [23028] = true }, auras = { ["arcane intellect"] = true },
    members = { Member("Anna", "PRIEST"), Member("Bo", "WARRIOR"), Member("Cy", "DRUID"), Member("Di", "PALADIN", nil, false) } }
  due = LG.Due(Obs(party), BG)
  local r = Find(due, "missingBuff:intellect")
  Check(r and r.spells[1] == "arcane intellect" and r.text:find("Anna") and r.text:find("Cy") and not r.text:find("Bo") and not r.text:find("Di"),
    "two mana users in range miss it; no reagent: the single spell: " .. tostring(r and r.text))
  party.counts = { [17020] = 5 }
  r = Find(LG.Due(Obs(party), BG), "missingBuff:intellect")
  Check(r and r.spells[1] == "arcane brilliance", "with Arcane Powder, two missing: the group version")
  Check(r.detail == "Missing on Anna, Cy" and r.icon.spell == 23028, "its card: who is missing it, and the group spell's icon: " .. tostring(r.detail))
  party.members = { Member("Anna", "PRIEST") }
  r = Find(LG.Due(Obs(party), BG), "missingBuff:intellect")
  Check(r and r.spells[1] == "arcane intellect", "one missing in a party (from 2): the single spell")
  party.auras = {}
  r = Find(LG.Due(Obs(party), BG), "missingBuff:intellect")
  Check(r and r.spells[1] == "arcane brilliance" and #r.spells == 1, "you and one other missing it count two: the group version only")
  party.ctx = { group = "party", combat = true }
  r = Find(LG.Due(Obs(party), BG), "missingBuff:intellect")
  Check(r and r.spells[1] == "arcane intellect" and not r.group, "in combat: only your own")
  BG.Set("partyBuffs", false)
  party.ctx = { group = "party" }
  r = Find(LG.Due(Obs(party), BG), "missingBuff:intellect")
  Check(r and not r.group, "party buffs off: only your own")
  BG.Set("partyBuffs", true)
  -- blessings by class
  local pal = { class = "PALADIN", ctx = { group = "party" }, known = { [19740] = true, [19742] = true }, auras = { ["blessing of might"] = true },
    members = { Member("Bo", "WARRIOR"), Member("Anna", "PRIEST") }, blessings = { WARRIOR = "blessingOfMight" } }
  SPELLS[19740], SPELLS[19742], SPELLS[25782] = { "Blessing of Might", 1 }, { "Blessing of Wisdom", 1 }, { "Greater Blessing of Might", 1 }
  r = Find(LG.Due(Obs(pal), BG), "missingBuff:blessingOfMight")
  Check(r and r.text:find("Bo") and not r.text:find("Anna"), "a blessing only on the class you gave it: " .. tostring(r and r.text))

  -- weapons
  local sham = { class = "SHAMAN", known = { [8017] = true, [8232] = true }, weapon = { mainHand = false, offHandWeapon = false } }
  SPELLS[8024], SPELLS[8033] = { "Flametongue Weapon", 1 }, { "Frostbrand Weapon", 1 }
  due = LG.Due(Obs(sham), BG)
  Check(Find(due, "weaponBuff:rockbiter") and not Find(due, "weaponBuff:windfury"), "automatic: the first known")
  sham.remembered = { weaponmainHand = "windfury" }
  Check(Find(LG.Due(Obs(sham), BG), "weaponBuff:windfury"), "automatic: the one used last")
  BG.SetWeapon("mainHand", "rockbiter")
  Check(Find(LG.Due(Obs(sham), BG), "weaponBuff:rockbiter"), "a chosen one")
  BG.SetWeapon("mainHand", "auto")
  sham.weapon.mainHand = true
  Check(not Find(LG.Due(Obs(sham), BG), "weaponBuff:windfury"), "enchanted: nothing")
  local rogue = { class = "ROGUE", weapon = { mainHand = true, offHand = false, offHandWeapon = true }, counts = { [6947] = 10 } }
  r = Find(LG.Due(Obs(rogue), BG), "weaponBuff:instantPoison")
  Check(r and r.items[1] == 6947 and r.text:find("off hand"), "a poison you carry, for the off hand")
  rogue.counts = {}
  Check(not Find(LG.Due(Obs(rogue), BG), "weaponBuff:instantPoison"), "a poison you don't carry: nothing")

  -- seals, tracking
  local paladin = { class = "PALADIN", known = { [21084] = true, [21082] = true }, auras = {}, remembered = { seal = "crusader" } }
  Check(Find(LG.Due(Obs(paladin), BG), "missingSeal:crusader"), "the seal used last")
  paladin.auras = { ["seal of righteousness"] = true }
  Check(not Find(LG.Due(Obs(paladin), BG), "missingSeal:crusader"), "any seal up: nothing")
  local miner = { known = { [2580] = true }, tracking = false }
  Check(Find(LG.Due(Obs(miner), BG), "missingTracking:findMinerals"), "no tracking on")
  miner.tracking = nil
  Check(not Find(LG.Due(Obs(miner), BG), "missingTracking:findMinerals"), "tracking unknown: nothing")

  -- reagents, stock
  local port = { known = { [3561] = true }, counts = { [17031] = 2 }, bars = { ["teleport: stormwind"] = true } }
  r = Find(LG.Due(Obs(port), BG), "lowReagent:runeOfTeleportation")
  Check(r and r.text == "Running low: Rune of Teleportation (2)", "a reagent running low")
  Check(r.detail == "Running low: 2 left" and r.icon.item == 17031, "its card: how many are left, the reagent's icon")
  port.bars = {}
  Check(not Find(LG.Due(Obs(port), BG), "lowReagent:runeOfTeleportation"), "its spells not on your bars: nothing")
  r = Find(LG.Due(Obs({ counts = { [8079] = 3 } }), BG), "lowStock:i8079")
  Check(r and r.items[1] == 8079, "an added item low")

  -- cooldowns, procs
  local cd = { known = { [12051] = true }, ready = { [12051] = true } }
  r = Find(LG.Due(Obs(cd), BG), "readyCooldown:evocation")
  Check(r and r.pulse, "a ready cooldown is a moment")
  cd.ready[12051] = false
  Check(not Find(LG.Due(Obs(cd), BG), "readyCooldown:evocation"), "on cooldown: nothing")
  local war = { class = "WARRIOR", known = { [7384] = true, [6572] = true, [5308] = true }, usable = { [5308] = true }, window = { revenge = true } }
  due = LG.Due(Obs(war), BG)
  Check(Find(due, "proc:execute") and Find(due, "proc:revenge") and not Find(due, "proc:overpower"), "usable, or its moment told another way: " .. Ids(due))
  war.ready = { [6572] = false }
  Check(not Find(LG.Due(Obs(war), BG), "proc:revenge"), "a proc on cooldown: nothing")
  Check(Ids(LG.Due(Obs(war), BG)):find("^proc:") ~= nil, "procs come first")

  -- old ranks
  local b1 = {}
  r = Find(LG.Due(Obs({ ranks = { { key = "frostbolt", name = "frostbolt", display = "Frostbolt", buttons = { b1 } } } }), BG), "oldRank:frostbolt")
  Check(r and r.buttons[1] == b1, "an old rank: those buttons only")
  BG.SetSpellEnabled("oldRank", "frostbolt", false)
  Check(not Find(LG.Due(Obs({ ranks = { { key = "frostbolt", name = "frostbolt", display = "Frostbolt", buttons = { b1 } } } }), BG), "oldRank:frostbolt"), "kept on purpose: turned off")
  BG.SetSpellEnabled("oldRank", "frostbolt", true)
end

---------------------------------------------------------------------------
-- 4. The buttons
---------------------------------------------------------------------------
do
  G.slots[1] = { "spell", 1459 }
  G.slots[2] = { "macro", 7, 12051 }
  G.slots[61] = { "item", 17020 }
  G.slots[62] = { "spell", 116 }
  BT.Map()
  Check(BT.ForSpell("arcane intellect")[1] == AB[1] and BT.Bar(AB[1]) == "bar1", "a spell on Blizzard's bar 1")
  Check(BT.ForSpell("evocation")[1] == AB[2], "a macro's spell")
  Check(BT.ForItem(17020)[1] == EAB[1] and BT.Bar(EAB[1]) == "bar2", "an item on EllesmereUI's bar 2, by its attribute")
  EAB[2].attrs.action = 1
  BT.Map()
  local list = BT.ForSpell("arcane intellect")
  Check(#list == 2 and BT.Bar(EAB[2]) == "bar2", "paged: the button shows what its slot holds now")
  G.slots[1] = { "spell", Secret() }
  BT.Map()
  Check(#BT.ForSpell("arcane intellect") == 0, "a secret action is skipped (both buttons showing it), nothing errors")
  G.slots[1] = { "spell", 1459 }
  EAB[2].attrs.action = 62
  BT.Map()
  -- old ranks: Frostbolt rank 2 on a bar, rank 11 in the book
  G.known = { [10181] = true, [1459] = true }
  ST.ReadBook()
  local ranks = ST.Ranks()
  Check(ranks and #ranks == 1 and ranks[1].key == "frostbolt" and ranks[1].buttons[1] == EAB[2], "an old rank found")
  G.slots[62] = { "macro", 9, 205 }
  BT.Map()
  Check(#ST.Ranks() == 0, "a macro's rank is on purpose: not an old rank")
  G.slots[62] = nil
  BT.Map()
end

-- weapon enchants: the way the game's buff frame reads them first; a broken compatibility wrapper never errors
do
  c.C_Item.GetWeaponEnchantInfo = function(ws) if ws == 0 then return { { hasEnchant = true } } end return {} end
  local w = ST.Weapon()
  Check(w and w.mainHand == true, "C_Item.GetWeaponEnchantInfo, as the buff frame reads it")
  c.C_Item.GetWeaponEnchantInfo = nil
  local pd = c.C_PaperDollInfo
  c.C_PaperDollInfo = {}
  c.GetWeaponEnchantInfo = function() error("attempt to call field 'GetTemporaryEnchantmentInfo' (a nil value)") end
  w = ST.Weapon()
  Check(w and w.mainHand == nil, "a wrapper that fails: unknown, and nothing errors")
  c.C_PaperDollInfo, c.GetWeaponEnchantInfo = pd, nil
end

---------------------------------------------------------------------------
-- 5. Drawing: no per-frame Lua; the same look twice does nothing; faded bars put back
---------------------------------------------------------------------------
do
  local b = AB[5]
  local s = BG.Style("proc", "overpower")
  D.Set(b, s)
  Check(D.IsGlowing(b) and D.shown == 1, "a glow shown")
  local made = D.made
  D.Set(b, s)
  Check(D.made == made and D.shown == 1, "the same look again: nothing new")
  D.Set(b, BG.Style("lowStock", "i8079"))
  Check(D.made == made and D.shown == 1, "another look: the same frame")
  D.Clear(b)
  Check(not D.IsGlowing(b) and D.shown == 0, "cleared")
  b.alpha = 0.8
  D.Fade(b, 0.5)
  Check(math.abs(b.alpha - 0.4) < 0.001, "faded from its own alpha")
  D.Unfade(b)
  Check(b.alpha == 0.8, "its alpha back")
  Check(onUpdates == 0, "no OnUpdate anywhere")
end

---------------------------------------------------------------------------
-- 6. Running: events, timing, messages, off
---------------------------------------------------------------------------
do
  World()
  BG.Remove("lowStock", "i8079")   -- added above; its message would be a second card here
  G.known = { [1459] = true, [12051] = true }
  G.slots[1] = { "spell", 1459 }
  G.slots[2] = { "spell", 12051 }
  c.FireEvent("PLAYER_LOGIN")
  Fire("PLAYER_ENTERING_WORLD")
  Settle()
  Check(CT.running and CT.Snapshot().events > 0, "on at entering the world")
  Check(Glowing(AB[1]), "Arcane Intellect missing: its button glows")
  Check(not Glowing(AB[2]), "Evocation ready out of combat: no glow (in combat by default)")
  G.auras = { "Arcane Intellect" }
  Fire("UNIT_AURA", "player")
  Settle()
  Check(not Glowing(AB[1]), "cast: the glow goes")

  -- a cooldown: a fight starting is not news; coming back is
  G.combat = true
  Fire("PLAYER_REGEN_DISABLED")
  Settle()
  Check(not Glowing(AB[2]), "a fight starts with Evocation ready: no glow")
  BG.SetSpellField("readyCooldown", "evocation", "repeat", 5)
  Settle()
  RunLongTimers(5)
  Settle()
  Check(not Glowing(AB[2]), "held back at a fight's start: its repeat doesn't bring it back")
  BG.SetSpellField("readyCooldown", "evocation", "repeat", nil)
  Settle()
  G.cooldowns[12051] = { start = NOW, duration = 60 }
  Fire("SPELL_UPDATE_COOLDOWN")
  Settle()
  G.cooldowns[12051] = nil
  NOW = NOW + 61
  Fire("SPELL_UPDATE_COOLDOWN")
  Settle()
  Check(Glowing(AB[2]), "it comes back in combat: it glows")
  RunLongTimers(3)
  Check(not Glowing(AB[2]), "for its glow time (3 s)")
  G.combat = false
  Fire("PLAYER_REGEN_ENABLED")
  Settle()
  BG.Set("cooldownsAtFightStart", true)
  G.combat = true
  Fire("PLAYER_REGEN_DISABLED")
  Settle()
  Check(Glowing(AB[2]), "\"also at the start of a fight\": it glows as a fight starts")
  RunLongTimers(3)
  BG.Set("cooldownsAtFightStart", false)
  G.combat = false
  Fire("PLAYER_REGEN_ENABLED")
  Settle()

  -- a secret cooldown end is polled, never compared
  G.combat = true
  G.cooldowns[12051] = "secret"
  Fire("SPELL_UPDATE_COOLDOWN")
  Settle()
  Check(not Glowing(AB[2]) and CT.needsPoll, "a cooldown whose end is secret: not ready, and looked at again")
  G.cooldowns[12051] = nil
  G.combat = false
  Fire("PLAYER_REGEN_ENABLED")
  Settle()

  -- secret auras: nothing on a guess
  G.auras = {}
  G.secretAuras = true
  Fire("UNIT_AURA", "player")
  Settle()
  Check(not Glowing(AB[1]), "secret auras: nothing glows")
  G.secretAuras = false
  Fire("UNIT_AURA", "player")
  Settle()
  Check(Glowing(AB[1]), "readable again: missing, it glows")

  -- message, sound, repeat
  BG.SetSpellField("missingBuff", "intellect", "message", true)
  BG.SetSpellField("missingBuff", "intellect", "sound", "TwichUI Friend")
  BG.SetSpellField("missingBuff", "intellect", "repeat", 5)
  Settle()
  local shown = NT.Shown()
  local card = shown[1] and shown[1].frame
  Check(#shown == 1 and shown[1].title == "Arcane Intellect" and shown[1].detail == "Missing buff", "its message card: the spell, and what is wanted")
  Check(card and card.title.font and card.title.font[1] == R.Arrival.FONT_TITLE and card.detail.font[1] == R.Arrival.FONT_LINE,
    "in the zone arrival card's fonts")
  Check(card and card.icon.shown and card.icon.texture == 100000 + 1459, "with the spell's icon")
  Check(shown[1].fading, "it fades in time")
  Check(#sounds == 1, "and its sound, once")
  RunLongTimers(5)
  Settle()
  Check(#sounds == 2 and Glowing(AB[1]), "repeated after 5 s")
  Check(#NT.Shown() == 1, "a repeat shows the same card again, never a second one")
  -- the icon left out; staying until done
  BG.Set("noticeIcon", false)
  Check(not card.icon.shown, "the icon can be left out (the card is drawn again at once)")
  BG.Set("noticeIcon", true)
  BG.Set("noticeFade", false)
  RunLongTimers(5)
  Settle()
  Check(#NT.Shown() == 1 and not NT.Shown()[1].fading, "fading off: it stays")
  -- done: it goes
  G.auras = { "Arcane Intellect" }
  Fire("UNIT_AURA", "player")
  Settle()
  Check(#NT.Shown() == 1 and NT.Shown()[1].fading, "its reminder done: the card fades out at once")
  card.leave.scripts.OnFinished(card.leave)
  Check(#NT.Shown() == 0, "and is gone")
  G.auras = {}
  Fire("UNIT_AURA", "player")
  Settle()
  BG.Set("noticeFade", true)
  BG.ResetSpell("missingBuff", "intellect")
  Settle()
  -- at most three, the newest on top
  for i = 1, 5 do NT.Show("test:" .. i, { label = "Test " .. i, kind = "proc" }) end
  shown = NT.Shown()
  Check(#shown == 3 and shown[1].title == "Test 5" and shown[1].detail == "Proc", "at most three cards, the newest on top")
  Check(shown[1].frame.points[1][5] == -282 and shown[2].frame.points[1][5] < -282, "stacked under the arrival card's place")
  NT.HideAll()
  Check(#NT.Shown() == 0, "all gone")

  -- bars and faded bars
  BG.SetBar("bar1", false)
  Settle()
  Check(not Glowing(AB[1]), "bar 1 kept quiet")
  BG.SetBar("bar1", true)
  BG.SetFaded("bar1", true)
  Settle()
  Check(Glowing(AB[1]) and AB[1].alpha == 1 and math.abs(AB[3].alpha - 0.5) < 0.001, "faded bar: the glowing button in full, the rest faded")
  BG.SetFaded("bar1", false)
  Settle()
  Check(AB[3].alpha == 1, "not faded any more: alpha back")

  -- quiet in towns, and alert in town
  G.resting = true
  Fire("PLAYER_UPDATE_RESTING")
  Settle()
  Check(not Glowing(AB[1]), "quiet in towns")
  G.resting = false
  Fire("PLAYER_UPDATE_RESTING")
  Settle()

  -- remembering what you cast
  G.class = "HUNTER"
  CT.Refresh()
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1459)
  Check(true, "a cast that is no group's: nothing remembered, nothing errors")
  G.class = "MAGE"
  CT.Refresh()
  Settle()

  -- The Quiet screen switch (QuietScreen.lua): no glow, card or sound while it is on; the glow still wanted comes back
  -- when it is off, and the message and sound of what started meanwhile are not given afterwards.
  do
    G.auras = {}
    Fire("UNIT_AURA", "player")
    Settle()
    Check(Glowing(AB[1]), "quiet test: Arcane Intellect missing, its button glows")
    NT.Show("quiet:1", { label = "Quiet test", kind = "proc" })
    Check(#NT.Shown() == 1, "quiet test: a card is up")
    local n = #sounds
    R.QuietScreen.Set(true)
    Check(not Glowing(AB[1]) and #NT.Shown() == 0, "quiet: the glow and the card go at once")
    G.auras = { "Arcane Intellect" }
    Fire("UNIT_AURA", "player")
    Settle()
    G.auras = {}
    Fire("UNIT_AURA", "player")
    Settle()
    Check(not Glowing(AB[1]), "quiet: it is wanted again but stays off the screen")
    R.QuietScreen.Set(false)
    Check(Glowing(AB[1]) and #NT.Shown() == 0 and #sounds == n, "quiet off: the glow still wanted is back, nothing else")
  end

  -- off
  BG.SetFaded("bar1", true)
  Settle()
  R:SetEnabled("barGlows", false)
  Check(not CT.running and CT.Snapshot().events == 0 and D.shown == 0, "off: no glow, no event")
  Check(AB[3].alpha == 1, "off: faded buttons put back")
  BG.SetFaded("bar1", false)
  Fire("UNIT_AURA", "player")
  Settle()
  Check(D.shown == 0, "off: nothing comes back")
  G.class = "MAGE"
  R:SetEnabled("barGlows", true)
  Settle()
  Check(CT.running and Glowing(AB[1]), "on again")
  Check(#acted == 0, "nothing was ever cast, used or said: " .. table.concat(acted, ","))
end

if failures == 0 then print("PASSED") else print(failures .. " FAILED") os.exit(1) end
