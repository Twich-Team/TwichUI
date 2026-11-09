-- Return the Favor (buffback/): Config.lua stores and checks, Spells.lua decides (pure), Watch.lua reads your auras,
-- List.lua draws the secure rows, Unlock.lua is EllesmereUI's mover. A fake world stands in for the game (units,
-- auras with sources, combat, secret values, emotes), so this checks our logic, not the game: the in-game checks
-- are in docs/return-the-favor.md.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

---------------------------------------------------------------------------
-- A fake world
---------------------------------------------------------------------------
local frames = {}
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, hooks = {}, events = {}, unitEvents = {}, points = {}, attrs = {},
    alpha = 1, scale = 1, w = 10, h = 10 }
  frames[#frames + 1] = o
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
local function RunHooks(s, n, ...) for _, fn in ipairs(s.hooks[n] or {}) do fn(s, ...) end end
Methods = {
  Show = function(s) s.shown = true end, Hide = function(s) if s.shown then s.shown = false; RunHooks(s, "OnHide") end end,
  IsShown = function(s) return s.shown end, SetShown = function(s, v) s.shown = v and true or false end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end, GetScript = function(s, n) return s.scripts[n] end,
  HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
  RegisterEvent = function(s, e) s.events[e] = true end,
  RegisterUnitEvent = function(s, e, u) s.events[e] = true; s.unitEvents[e] = u end,
  UnregisterEvent = function(s, e) s.events[e] = nil; s.unitEvents[e] = nil end,
  UnregisterAllEvents = function(s) s.events = {}; s.unitEvents = {} end,
  IsEventRegistered = function(s, e) return s.events[e] == true end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  SetText = function(s, v) s.text = v end, GetText = function(s) return s.text end,
  SetTextColor = function(s, r, g, b) s.color = { r, g, b } end,
  ClearAllPoints = function(s) s.points = {} end,
  SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  SetTexture = function(s, p) s.texture = p; return true end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  SetScale = function(s, v) s.scale = v end, GetScale = function(s) return s.scale end,
  GetEffectiveScale = function(s) return s.scale end,
  EnableMouse = function(s, v) s.mouse = v and true or false end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; return true end,
  SetDesaturated = function(s, v) s.desaturated = v end,
  SetBackdrop = function(s, info) s.backdrop = info end,
  SetAttribute = function(s, k, v) s.attrs[k] = v end, GetAttribute = function(s, k) return s.attrs[k] end,
  GetCenter = function(s)
    local p = s.points[#s.points]
    if p and p[1] == "CENTER" then return 500 + (p[4] or 0), 400 + (p[5] or 0) end
    return 500, 400
  end,
  StartMoving = function(s) s.moving = true end, StopMovingOrSizing = function(s) s.moving = false end,
}
-- The game blocks addon code from changing a protected frame in combat (ADDON_ACTION_BLOCKED): a secure button, or a
-- frame holding one. Every such change made here in combat is recorded, and there must be none.
local blocked = {}
local G
local PROTECTED = { "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints", "SetSize", "SetScale", "SetAttribute", "EnableMouse" }
local function Protect(f)
  for _, m in ipairs(PROTECTED) do
    local plain = Methods[m]
    f[m] = function(self, ...)
      if G and G.combat then blocked[#blocked + 1] = m .. " on " .. tostring(self.name) end
      return plain(self, ...)
    end
  end
end
c.CreateFrame = function(kind, name, parent, template)
  local f = Fake(kind)
  f.name, f.parent, f.template = name, parent, template
  if type(template) == "string" and template:find("Secure") then Protect(f) end
  return f
end
c.UIParent = Fake("UIParent")
c.UIParent.GetCenter = function() return 500, 400 end
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
c.hooksecurefunc = function(obj, name, fn)
  local orig = obj[name]
  obj[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
local drivers = {}
c.RegisterStateDriver = function(f, kind, cond) drivers[f] = cond end
c.UnregisterStateDriver = function(f) drivers[f] = nil end
c.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }

local SECRET_MT = { __lt = function() error("compared a secret value") end, __le = function() error("compared a secret value") end,
  __add = function() error("arithmetic on a secret value") end, __concat = function() error("formatted a secret value") end,
  __eq = function() error("compared a secret value") end }
local function SecretValue() return setmetatable({ secret = true }, SECRET_MT) end
c.issecretvalue = function(v) return type(v) == "table" and rawget(v, "secret") == true end

local NOW = 1000
c.GetTime = function() return NOW end

local NAMES = {
  [10938] = "Power Word: Fortitude", [1243] = "Power Word: Fortitude", [21564] = "Prayer of Fortitude",
  [1459] = "Arcane Intellect", [10157] = "Arcane Intellect", [14752] = "Divine Spirit", [976] = "Shadow Protection",
  [19742] = "Blessing of Wisdom", [19740] = "Blessing of Might", [20217] = "Blessing of Kings", [1126] = "Mark of the Wild",
  [9885] = "Mark of the Wild", [6673] = "Battle Shout", [5697] = "Unending Breath", [139] = "Renew",
}
c.C_Spell = { GetSpellName = function(id) return NAMES[id] end, GetSpellTexture = function(id) return 100000 + id end }

local function World()
  G = { class = "MAGE", known = { [1459] = true, [10157] = true }, combat = false, instance = nil, resting = false,
    group = false, raid = false, lockdown = false, units = {}, target = nil, emotes = {} }
  G.units.player = { name = "Rich", class = "MAGE", player = true }
end
World()
local function U(unit)
  if unit == "target" then return G.target and G.units[G.target] end
  return G.units[unit]
end
c.UnitName = function(u) local m = U(u); if m then return m.name, m.realm end end
c.UnitClass = function(u) local m = U(u); if m then return m.class, m.class end end
c.UnitExists = function(u) return U(u) ~= nil end
c.UnitIsUnit = function(a, b) return U(a) ~= nil and U(a) == U(b) end
c.UnitIsPlayer = function(u) local m = U(u); return m ~= nil and m.player == true end
c.UnitInParty = function(who)
  for k, m in pairs(G.units) do if (k == who or m.name == who) and m.party then return true end end
  return false
end
c.UnitInRaid = function() return nil end
c.IsInGroup = function() return G.group end
c.IsInRaid = function() return G.raid end
c.IsInInstance = function() if G.instance then return true, G.instance end return false, "none" end
c.IsResting = function() return G.resting end
c.InCombatLockdown = function() return G.combat end
c.IsSpellKnown = function(id) return G.known[id] == true end
c.C_Secrets = { ShouldAurasBeSecret = function() return false end }
-- your auras, by instance ID; others' auras by unit
local mine = {}
c.C_UnitAuras = {
  GetAuraDataByIndex = function(u, i)
    if u == "player" then
      local list = {}
      for _, a in pairs(mine) do list[#list + 1] = a end
      table.sort(list, function(a, b) return a.auraInstanceID < b.auraInstanceID end)
      return list[i]
    end
    local m = U(u)
    local a = m and m.auras and m.auras[i]
    if a then return { spellId = a, name = NAMES[a] } end
  end,
  GetAuraDataByAuraInstanceID = function(u, id) return u == "player" and mine[id] or nil end,
}
c.C_ChatInfo.InChatMessagingLockdown = function() return G.lockdown end
c.C_ChatInfo.PerformEmote = function(token, name) G.emotes[#G.emotes + 1] = { token, name }; return false end
-- anything that would act for the player without a click: none of it may ever be called
local acted = {}
for _, name in ipairs({ "SendChatMessage", "CastSpellByName", "CastSpellByID", "TargetUnit", "UseAction", "SpellTargetUnit" }) do
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

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "modules/SpellMenu.lua",
  "buffback/Config.lua", "buffback/Spells.lua", "buffback/Watch.lua", "buffback/List.lua", "buffback/Unlock.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local BB, S, W, L, UL = R.BuffBack, R.BuffBackSpells, R.BuffBackWatch, R.BuffBackList, R.BuffBackUnlock
Fire("PLAYER_LOGIN")

local inst = 0
-- Another player's buff lands on you: an added aura with them as its source.
local function Buff(unit, spellId, opts)
  opts = opts or {}
  inst = inst + 1
  local a = { auraInstanceID = inst, spellId = spellId, name = opts.name or NAMES[spellId], icon = 5000 + (spellId or 0), isHelpful = true,
    sourceUnit = unit, expirationTime = NOW + 1800 }
  if opts.secret then a.spellId, a.name, a.sourceUnit = SecretValue(), SecretValue(), SecretValue() end
  mine[inst] = a
  Fire("UNIT_AURA", "player", { addedAuras = { a } })
  return a
end
local function Recast(a)
  a.expirationTime = NOW + 1800
  Fire("UNIT_AURA", "player", { updatedAuraInstanceIDs = { a.auraInstanceID } })
end
local function Names()
  local out = {}
  for i, e in ipairs(W.Entries()) do out[i] = e.short end
  return table.concat(out, ",")
end
local function Row(i) return L.Rows()[i] end
local function Reset()
  for i = #W.Entries(), 1, -1 do W.Entries()[i] = nil end
  for k in pairs(mine) do mine[k] = nil end
  G.combat = false
  L.Render()
end

---------------------------------------------------------------------------
-- 1. Spells: what counts and what is given back (pure)
---------------------------------------------------------------------------
do
  Check(S.Family(10938).key == "fortitude", "a rank of Fortitude is a favor")
  Check(S.Family(21564).key == "fortitude", "Prayer of Fortitude is the same family")
  Check(S.Family(999999, "Power Word: Fortitude").key == "fortitude", "an unlisted rank counts by the client's name")
  Check(S.Family(139) == nil and S.Family(nil, "Renew") == nil, "a heal over time is not a favor")
  Check(S.Family(6673) == nil, "a warrior's shout never counts as received")
  local function Knows(...) local set = {} for _, id in ipairs({ ... }) do set[id] = true end return function(id) return set[id] == true end end
  local f, why = S.Pick("MAGE", { class = "PRIEST" }, Knows(1459))
  Check(f and f.key == "intellect", "a mage gives Arcane Intellect to a priest")
  f, why = S.Pick("MAGE", { class = "WARRIOR" }, Knows(1459))
  Check(f == nil and why == "mana", "Arcane Intellect is never offered to a warrior")
  f, why = S.Pick("MAGE", { class = "PRIEST" }, Knows())
  Check(f == nil and why == "unknown", "nothing learned yet: nothing offered")
  f, why = S.Pick("ROGUE", { class = "PRIEST" }, Knows(1459))
  Check(f == nil and why == "nothing", "a rogue has nothing to give")
  f = S.Pick("PALADIN", { class = "MAGE" }, Knows(19742, 19740, 20217))
  Check(f and f.key == "wisdom", "a paladin gives Wisdom to a mage")
  f = S.Pick("PALADIN", { class = "WARRIOR" }, Knows(19742, 19740, 20217))
  Check(f and f.key == "might", "a paladin gives Might to a warrior, first")
  f = S.Pick("PALADIN", { class = "WARRIOR" }, Knows(19742, 20217))
  Check(f and f.key == "kings", "without Might, Kings for a warrior (never Wisdom)")
  f = S.Pick("PRIEST", { class = "MAGE" }, Knows(1243, 14752, 976), { fortitude = true })
  Check(f and f.key == "spirit", "a priest skips Fortitude they already wear")
  f, why = S.Pick("PRIEST", { class = "WARRIOR" }, Knows(1243, 14752, 976), { fortitude = true, shadow = true })
  Check(f and f.key == "fortitude", "they wear all a priest can give a warrior: Fortitude is given anyway, to refresh it")
  f, why = S.Pick("WARRIOR", { class = "PRIEST", inParty = false }, Knows(6673))
  Check(f == nil and why == "party", "a shout only for your own party")
  f = S.Pick("WARRIOR", { class = "PRIEST", inParty = true }, Knows(6673))
  Check(f and f.key == "shout", "a shout for a party member")

  local fam = S.FAMILIES.intellect
  Check(S.Macro({ name = "Anna", inGroup = true }, fam, "Arcane Intellect") == "/cast [@Anna] Arcane Intellect", "a group member is cast on by name")
  Check(S.Macro({ name = "Anna" }, fam, "Arcane Intellect", { has = true }) == "/target Anna\n/cast Arcane Intellect\n/targetlasttarget",
    "outside the group: target, cast, your target back")
  Check(S.Macro({ name = "Anna-Other" }, fam, "Arcane Intellect", { has = false }) == "/target Anna-Other\n/cast Arcane Intellect\n/cleartarget",
    "no target before: cleared after")
  Check(S.Macro({ name = "Anna" }, fam, "Arcane Intellect", { has = true, isThem = true }) == "/cast [@target] Arcane Intellect", "already your target")
  Check(S.Macro({ name = "Anna" }, S.FAMILIES.shout, "Battle Shout") == "/cast Battle Shout", "a shout is just cast")
  Check(S.Macro({ name = "An na" }, fam, "Arcane Intellect") == nil and S.Macro({ name = "Anna;x" }, fam, "Arcane Intellect") == nil
    and S.Macro({ name = "Anna" }, fam, "Arcane\nIntellect") == nil, "a name or spell that could break the macro makes none")
end

---------------------------------------------------------------------------
-- 2. Settings: checked on the way in and out
---------------------------------------------------------------------------
do
  Check(BB.Get("duration") == 60 and BB.Get("thank") == false and BB.Get("hideRaid") == true, "defaults")
  Check(BB.Set("duration", 5) == false and BB.Set("duration", 30.5) == false and BB.Get("duration") == 60, "out of range or fractional refused")
  Check(BB.Set("growth", "sideways") == false and BB.Set("thankEmote", "DANCE") == false, "an unknown choice refused")
  Check(BB.Set("nameColor", "red") == false, "a color must be 8 hex digits")
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  c.TwichUIDB.ui.buffBack = c.TwichUIDB.ui.buffBack or {}
  c.TwichUIDB.ui.buffBack.duration = "long"
  Check(BB.Get("duration") == 60, "a bad stored value reads as the default")
  Check(BB.SetPlace(120, -40) and BB.Get("x") == 120 and BB.Get("y") == -40, "the place")
  BB.Set("width", 250)
  BB.ResetSettings()
  Check(BB.Get("width") == 200 and BB.Get("x") == 120, "Reset keeps the place")
  BB.ResetPlace()
  Check(BB.Get("x") == BB.DEFAULTS.x, "Reset position")
  Check(R.DEFAULT_MODULES.buffBack == false, "off by default")
end

---------------------------------------------------------------------------
-- 3. Off: nothing listened for
---------------------------------------------------------------------------
do
  G.units.party1 = { name = "Aldren", class = "PRIEST", player = true }
  Buff("party1", 10938)
  Check(#W.Entries() == 0, "off: nothing listed")
  Check(W.Snapshot().events == 0, "off: no events")
end

R:SetEnabled("buffBack", true)
Check(W.Snapshot().active and W.Snapshot().events > 0, "on: listening")

---------------------------------------------------------------------------
-- 4. Noticing a buff
---------------------------------------------------------------------------
do
  local a = Buff("party1", 10938)
  Check(Names() == "Aldren", "another player's buff lists them")
  local e = W.Entries()[1]
  Check(e.class == "PRIEST" and e.spellName == "Power Word: Fortitude" and e.icon == 5000 + 10938, "with their class, the buff and its icon")
  Buff("player", 10157)
  G.units.pet = { name = "Imp", class = "WARLOCK", player = false }
  Buff("pet", 10938)
  Check(Names() == "Aldren", "your own buffs and a pet's don't count")
  G.units.party2 = { name = "Brisa", class = "DRUID", player = true }
  Buff("party2", 139)
  Check(Names() == "Aldren", "a heal over time doesn't count")
  BB.Set("anyBuff", true)
  Buff("party2", 139)
  Check(Names() == "Brisa,Aldren", "\"Count any helpful spell\" lists it, newest first")
  BB.Set("anyBuff", false)
  Buff("party1", nil, { secret = true })
  Check(Names() == "Brisa,Aldren", "a secret aura is not noticed (and nothing errors)")
  NOW = NOW + 5
  Recast(a)
  Check(Names() == "Aldren,Brisa", "the same buff cast again moves them to the top")
  Fire("UNIT_AURA", "player", { isFullUpdate = true })
  Check(Names() == "Aldren,Brisa", "a full update notes nothing new")
  Fire("UNIT_AURA", "player", { isFullUpdate = SecretValue() })
  Check(true, "a secret full-update flag doesn't error")
  for i = 1, 7 do
    G.units["nameplate" .. i] = { name = "Extra" .. i, class = "PRIEST", player = true }
    Buff("nameplate" .. i, 10938)
  end
  Check(#W.Entries() == BB.Get("maxRows"), "at most maxRows names: " .. #W.Entries())
  Check(W.Entries()[1].short == "Extra7", "the newest stays")
end

---------------------------------------------------------------------------
-- 5. The rows: secure buttons running the macro; nothing happens without a click
---------------------------------------------------------------------------
do
  Reset()
  G.units.party1.party = true
  G.group = true
  Buff("party1", 10938)
  local row = Row(1)
  Check(row and row.template == "SecureActionButtonTemplate" and row.shown, "a secure row is shown")
  Check(row.attrs["*type1"] == "macro" and row.attrs["*macrotext1"] == "/cast [@Aldren] Arcane Intellect", "a group member: cast on them by name")
  Check(row.attrs.useOnKeyDown == false, "acts on the mouse button's release")
  Check(drivers[L.Frame()] == "show", "the list is driven shown")
  Check(row.skin.name.text == "Aldren" and row.skin.name.color[1] == 1, "the name in its class color")
  Check(row.skin.back.texture == 100000 + 1459, "the small icon is what a click casts")

  G.units.target1 = { name = "Corwyn", realm = "Faraway", class = "MAGE", player = true }
  G.target = "party1"
  Buff("target1", 10157)
  Check(Row(1).attrs["*macrotext1"] == "/target Corwyn-Faraway\n/cast Arcane Intellect\n/targetlasttarget", "outside your group: target, cast, back")
  G.target = nil
  Fire("PLAYER_TARGET_CHANGED")
  Fire("PLAYER_TARGET_CHANGED")
  local renders = L.Snapshot().renders
  FlushTimers()
  Check(L.Snapshot().renders == renders + 1, "a burst of changes re-arms once")
  Check(Row(1).attrs["*macrotext1"] == "/target Corwyn-Faraway\n/cast Arcane Intellect\n/cleartarget", "your target gone: re-armed out of combat")

  G.units.warrior = { name = "Daelin", class = "WARRIOR", player = true }
  Buff("warrior", 10938)
  Check(Row(1).attrs["*type1"] == nil and Row(1).why == "mana", "nothing to give a warrior: the row does nothing")
  Check(Row(1).skin.back.desaturated == true, "and its small icon is faded")

  -- right-click: gone
  Row(1).scripts.PostClick(Row(1), "RightButton")
  Check(Names() == "Corwyn,Aldren", "right-click removes the row")
  -- a click, then your own cast of that buff: gone
  local corwyn = Row(1)
  corwyn.scripts.PostClick(corwyn, "LeftButton")
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 10157)
  Check(Names() == "Aldren", "the buff landing after a click removes the row")
  Row(1).scripts.PostClick(Row(1), "LeftButton")
  NOW = NOW + 10
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 10157)
  Check(Names() == "Aldren", "a cast long after the click doesn't")
  Check(#acted == 0, "nothing was cast, targeted or said by the addon: " .. table.concat(acted, ","))
end

---------------------------------------------------------------------------
-- 6. Combat: nothing secure changes; new names wait, old ones dim
---------------------------------------------------------------------------
do
  Reset()
  Buff("party1", 10938)
  local before = L.Snapshot().renders
  Fire("PLAYER_REGEN_DISABLED")   -- the game can say this before it reports combat lockdown
  G.combat = true
  G.units.party2.party = true
  Buff("party2", 9885)
  Check(Names() == "Brisa,Aldren", "noticed in combat")
  Check(L.Snapshot().shown == 1 and L.Snapshot().renders == before and L.Snapshot().waiting, "but the list waits")
  NOW = NOW + 61
  RunLongTimers(100)
  Check(#W.Entries() == 2 and W.Entries()[2].faded and Row(1).skin.alpha < 0.5, "run out in combat: dimmed, not removed")
  G.combat = false
  Fire("PLAYER_REGEN_ENABLED")
  Check(#W.Entries() == 0 and L.Snapshot().shown == 0 and drivers[L.Frame()] == nil, "after combat: brought up to date")
  BB.Set("hideCombat", true)
  Buff("party1", 10938)
  Check(drivers[L.Frame()] == "[combat] hide; show", "hidden in combat by the state driver")
  BB.Set("hideCombat", false)
end

---------------------------------------------------------------------------
-- 7. Expiry and pauses
---------------------------------------------------------------------------
do
  Reset()
  Buff("party1", 10938)
  NOW = NOW + 30
  RunLongTimers(100)
  Check(#W.Entries() == 1, "still listed before its time")
  NOW = NOW + 31
  RunLongTimers(100)
  Check(#W.Entries() == 0, "gone when its time runs out")
  G.instance = "raid"
  Fire("PLAYER_ENTERING_WORLD")
  Buff("party1", 10938)
  Check(#W.Entries() == 0 and W.Paused() == "raid", "paused in a raid by default")
  G.instance = "party"
  Fire("PLAYER_ENTERING_WORLD")
  Buff("party1", 10938)
  Check(#W.Entries() == 1, "not paused in a dungeon by default")
  BB.Set("hideDungeon", true)
  Check(#W.Entries() == 0, "pausing where you are empties the list")
  BB.Set("hideDungeon", false)
  G.instance = nil
  G.resting = true
  BB.Set("hideResting", true)
  Buff("party1", 10938)
  Check(#W.Entries() == 0 and W.Paused() == "resting", "paused while resting when chosen")
  BB.Set("hideResting", false)
  G.resting = false
end

---------------------------------------------------------------------------
-- 8. Thanking: opt-in, delayed, rate-limited, only when allowed
---------------------------------------------------------------------------
do
  Reset()
  Buff("party1", 10938)
  RunLongTimers(100)
  Check(#G.emotes == 0, "no emote unless chosen")
  BB.Set("thank", true)
  NOW = NOW + 400
  Buff("party1", 10938)
  Check(#G.emotes == 0, "not at once")
  RunLongTimers(BB.Get("thankDelay") + 2)
  Check(#G.emotes == 1 and G.emotes[1][1] == "THANK" and G.emotes[1][2] == "Aldren", "then the chosen emote at them")
  NOW = NOW + 20
  Buff("party1", 10938)
  RunLongTimers(100)
  Check(#G.emotes == 1, "not the same player again within five minutes")
  NOW = NOW + 400
  G.combat = true
  Buff("party2", 9885)
  RunLongTimers(100)
  G.combat = false
  Check(#G.emotes == 1, "never in combat")
  NOW = NOW + 400
  G.lockdown = true
  Buff("party1", 10938)
  RunLongTimers(100)
  G.lockdown = false
  Check(#G.emotes == 1, "never while chat is restricted")
  NOW = NOW + 400
  G.units.away = { name = "Eshvar", class = "WARLOCK", player = true }
  Buff("away", 5697)
  G.units.away = nil
  RunLongTimers(100)
  Check(#G.emotes == 1, "not when they are no longer around")
  NOW = NOW + 400
  BB.Set("thankEmote", "BOW")
  Buff("party1", 10938)
  NOW = NOW + 2
  Buff("party2", 9885)
  RunLongTimers(100)
  Check(#G.emotes == 2 and G.emotes[2][1] == "BOW", "the chosen emote, and never two within ten seconds: " .. #G.emotes)
  BB.Set("thankEmote", "THANK")

  -- only after you buff them back
  BB.Set("thankAfterReturn", true)
  NOW = NOW + 400
  local before = #G.emotes
  Buff("party1", 10938)
  RunLongTimers(100)
  Check(#G.emotes == before, "after-return: their buff alone is not thanked")
  local row
  for _, r in ipairs(L.Rows()) do if r.shown and r.entry and r.entry.short == "Aldren" then row = r end end
  Check(row and row.fam, "their row can give a buff back")
  row.scripts.PostClick(row, "LeftButton")
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 10157)
  Check(#G.emotes == before, "not at once when yours lands")
  RunLongTimers(BB.Get("thankDelay") + 2)
  Check(#G.emotes == before + 1 and G.emotes[#G.emotes][2] == "Aldren", "thanked once your buff lands, after the delay")
  NOW = NOW + 400
  Buff("party2", 9885)
  RunLongTimers(100)
  Check(#G.emotes == before + 1, "someone you don't buff back is never thanked")
  BB.Set("thankAfterReturn", false)
  BB.Set("thank", false)
end

---------------------------------------------------------------------------
-- 9. The sample: not secure, does nothing, dragged to move the list
---------------------------------------------------------------------------
do
  Reset()
  Check(L.Preview(true) == true and L.Previewing(), "the sample shows")
  local s = L.Snapshot()
  Check(s.sampleRows == math.min(5, BB.Get("maxRows")), "with sample rows")
  local any
  for _, f in ipairs(frames) do if f.template == nil and f.kind == "Button" and f.entry and f.entry.short == "Aldren" then any = f end end
  Check(any and next(any.attrs) == nil, "a sample row has no secure action")
  Fire("PLAYER_REGEN_DISABLED")
  Check(not L.Previewing(), "it goes as combat starts")
  G.combat = true
  Check(L.Preview(true) == false, "and can't be shown in combat")
  G.combat = false
end

---------------------------------------------------------------------------
-- 10. EllesmereUI's Unlock Mode
---------------------------------------------------------------------------
do
  local registeredEls = {}
  c.EllesmereUI = {
    RegisterUnlockElements = function(_, list) for _, el in ipairs(list) do registeredEls[#registeredEls + 1] = el end end,
    MakeUnlockElement = function(t) return t end,
    RegisterUnlockModeListener = function() end,
  }
  BB.Set("unlockMode", true)
  Check(#registeredEls == 1 and registeredEls[1].key == "TwichUI_ReturnTheFavor", "one mover registered")
  Check(UL.Status() == "active" and UL.Drives(), "in charge")
  local el = registeredEls[1]
  el.savePos(el.key, "CENTER", "CENTER", 210, -30)
  Check(BB.Get("x") == 210 and BB.Get("y") == -30, "EllesmereUI's save is TwichUI's place")
  el.savePos(el.key, "TOPLEFT", "CENTER", 1, 1)
  Check(BB.Get("x") == 210, "anything but CENTER/CENTER refused")
  local load = el.loadPos()
  Check(load.x == 210 and load.y == -30, "the place handed back")
  -- the stand-in moved (an anchor link): the list follows, out of combat
  Reset()
  Buff("party1", 10938)
  local stand = el.getFrame()
  stand:ClearAllPoints()
  stand:SetPoint("CENTER", c.UIParent, "CENTER", 50, 60)
  local p = L.Frame().points[#L.Frame().points]
  Check(p and p[4] == 50 and p[5] == 60, "the list follows the stand-in")
  G.combat = true
  stand:SetPoint("CENTER", c.UIParent, "CENTER", 70, 80)
  p = L.Frame().points[#L.Frame().points]
  Check(p[4] == 50, "but not in combat")
  G.combat = false
  Fire("PLAYER_REGEN_ENABLED")
  p = L.Frame().points[#L.Frame().points]
  Check(p[4] == 70 and p[5] == 80, "and goes there after")
  Check(el.isHidden() == false, "shown in Unlock Mode while on")
  BB.Set("unlockMode", false)
  Check(el.isHidden() == true and not UL.Drives(), "hidden when the choice is off")
  c.EllesmereUI = nil
end

---------------------------------------------------------------------------
-- 11. Off again: everything let go
---------------------------------------------------------------------------
do
  Buff("party1", 10938)
  R:SetEnabled("buffBack", false)
  Check(#W.Entries() == 0 and W.Snapshot().events == 0 and not W.Snapshot().active, "off: list cleared, events let go")
  Check(drivers[L.Frame()] == nil, "and the list hidden")
end

---------------------------------------------------------------------------
-- 12. Configuration sharing and load order
---------------------------------------------------------------------------
do
  local TC = R.TwichConfig
  for _, key in ipairs({ "ui.buffBack.x", "ui.buffBack.y", "ui.buffBack.unlockMode", "ui.buffBack.thank", "ui.buffBack.thankEmote", "ui.buffBack.thankDelay" }) do
    Check(TC and TC.LOCAL[key] ~= nil, key .. " stays on this computer")
  end
  local toc = io.open(ROOT .. "!!!TwichUI.toc"):read("*a")
  local a, b, cc, d, e = toc:find("buffback\\Config.lua", 1, true), toc:find("buffback\\Spells.lua", 1, true), toc:find("buffback\\Watch.lua", 1, true),
    toc:find("buffback\\List.lua", 1, true), toc:find("buffback\\Unlock.lua", 1, true)
  Check(a and b and cc and d and e and a < b and b < cc and cc < d and d < e, "the .toc loads Return the Favor in order")
  Check(toc:find("modules\\MenuStyle.lua", 1, true) < a and toc:find("modules\\SpellMenu.lua", 1, true) < a, "after MenuStyle and SpellMenu")
end

Check(#blocked == 0, "no protected frame was changed in combat: " .. table.concat(blocked, ", "))

if failures > 0 then print(failures .. " FAILED") os.exit(1) end
print("RETURN THE FAVOR TESTS PASSED")
