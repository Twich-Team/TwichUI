-- Healer Watch (healer/): Config.lua stores and checks, Logic.lua decides (pure), Drinks.lua recognizes drinking,
-- Watch.lua reads the game and Display.lua draws. A fake world stands in for the game (a group with roles, mana, auras,
-- chat and the game's secret values), so this checks our logic, not the game: the in-game checks are in
-- docs/healer-watch.md.
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
  local o = { kind = kind, shown = false, scripts = {}, events = {}, unitEvents = {}, points = {}, alpha = 1, scale = 1, w = 10, h = 10 }
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
  RegisterEvent = function(s, e) s.events[e] = true end,
  RegisterUnitEvent = function(s, e, u) s.events[e] = true; s.unitEvents[e] = u end,
  UnregisterEvent = function(s, e) s.events[e] = nil; s.unitEvents[e] = nil end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  SetText = function(s, v) s.text = v end, GetText = function(s) return s.text end,
  SetFormattedText = function(s, fmt, v) s.formatted = { fmt, v } end,
  GetStringWidth = function(s) return #(s.text or "") * 7 end,
  GetStringHeight = function(s) return s.fontSize or 12 end,
  ClearAllPoints = function(s) s.points = {} end,
  SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
  GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  SetTexture = function(s, p) s.texture = p; return true end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  SetScale = function(s, v) s.scale = v end, GetScale = function(s) return s.scale end,
  EnableMouse = function(s, v) s.mouse = v and true or false end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; s.fontSize = size; return true end,
  SetValue = function(s, v) s.value = v end, SetStatusBarColor = function(s, r, g, b) s.barColor = { r, g, b } end,
  SetDesaturated = function(s, v) s.desaturated = v end,
  SetFrameLevel = function(s, l) s.level = l end, GetFrameLevel = function(s) return s.level end,
  SetVertexColor = function(s, r, g, b) s.vertex = { r, g, b } end,
  SetColorTexture = function(s, r, g, b, a) s.color = { r, g, b, a } end,
  RegisterForClicks = function() end,
  SetStatusBarTexture = function(s, t) s.texture = t end, SetBackdrop = function(s, info) s.backdrop = info end,
  StartMoving = function(s) s.moving = true end, StopMovingOrSizing = function(s) s.moving = false end,
  GetLeft = function(s) return s.left end, GetRight = function(s) return s.left and s.left + s.w end,
  GetTop = function(s) return s.bottom and s.bottom + s.h end, GetBottom = function(s) return s.bottom end,
  CreateAnimationGroup = function(s)
    local g = Fake("group")
    g.owner, g.plays = s, 0
    g.Play = function(self) self.plays = self.plays + 1; self.playing = true end
    g.Stop = function(self) self.playing = false end
    g.CreateAnimation = function(_, kind)
      local a = Fake("anim")
      a.animKind = kind
      a.SetOffset = function(self, x, y) self.offset = { x, y } end
      a.SetToAlpha = function(self, v) self.toAlpha = v end
      a.SetFromAlpha = function(self, v) self.fromAlpha = v end
      a.SetStartDelay = function(self, v) self.delay = v end
      a.SetDuration = function(self, v) self.duration = v end
      return a
    end
    return g
  end,
}
c.CreateFrame = function(kind, name, parent, template)
  local f = Fake(kind)
  f.name, f.parent, f.template = name, parent, template
  f.level = ((parent and parent.level) or 0) + 1   -- a child is one level above its parent, as in the game
  return f
end
c.UIParent = Fake("UIParent")
c.UIParent.w, c.UIParent.h = 1024, 768
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- The game's secret values: a value an addon may pass on but must not compare, do arithmetic with or format. Any of
-- those on this table raises an error, as it would in the game.
local SECRET_MT = { __lt = function() error("compared a secret value") end, __le = function() error("compared a secret value") end,
  __add = function() error("arithmetic on a secret value") end, __div = function() error("arithmetic on a secret value") end,
  __concat = function() error("formatted a secret value") end, __eq = function() error("compared a secret value") end }
local function SecretValue() return setmetatable({ secret = true }, SECRET_MT) end
c.issecretvalue = function(v) return type(v) == "table" and rawget(v, "secret") == true end

local NOW = 1000
c.GetTime = function() return NOW end
c.Enum = { PowerType = { Mana = 0 }, LuaCurveType = { Linear = 0 } }

local G   -- the world
local function Member(guid, name, realm, role, mana, max)
  return { guid = guid, name = name, realm = realm, role = role or "NONE", connected = true, dead = false, mana = mana or 3000, max = max or 4000, auras = {} }
end
local function World()
  G = { group = true, raid = false, instance = "party", combat = false, aurasSecret = false, chatLockdown = false, secretMana = false,
    me = Member("Player-1-ME", "Rich", nil, "DAMAGER", 0, 0), party = {} }
  G.party[1] = Member("Player-1-TANK", "Borin", nil, "TANK", 1000, 2000)
  G.party[2] = Member("Player-1-HEAL", "Elyndra", nil, "HEALER", 3000, 4000)
  G.party[3] = Member("Player-1-DPS", "Kael", nil, "DAMAGER", 2000, 2000)
end
World()
local function ByUnit(unit)
  if unit == "player" then return G.me end
  local i = tonumber((unit or ""):match("^party(%d)$"))
  return i and G.party[i] or nil
end
c.UnitGUID = function(u) local m = ByUnit(u); return m and m.guid end
c.UnitName = function(u) local m = ByUnit(u); if m then return m.name, m.realm end end
c.UnitGroupRolesAssigned = function(u) local m = ByUnit(u); return m and m.role or "NONE" end
c.UnitIsUnit = function(a, b) return ByUnit(a) == ByUnit(b) end
c.IsInGroup = function() return G.group end
c.IsInRaid = function() return G.raid end
c.GetNumGroupMembers = function() return G.group and #G.party + 1 or 0 end
c.GetNumSubgroupMembers = function() return G.group and #G.party or 0 end
c.IsInInstance = function() if G.instance then return true, G.instance end return false, "none" end
local powerAsked = {}
c.UnitPower = function(u, kind)
  powerAsked[#powerAsked + 1] = kind
  local m = ByUnit(u); if not m then return 0 end
  if G.secretMana then return SecretValue() end
  return m.mana
end
c.UnitPowerMax = function(u, kind)
  local m = ByUnit(u); if not m then return 0 end
  if G.secretMana then return SecretValue() end
  return m.max
end
local percentCalls = 0
c.UnitPowerPercent = function() percentCalls = percentCalls + 1; return SecretValue() end
c.C_CurveUtil = { CreateCurve = function() return { SetType = function() end, AddPoint = function() end } end }
c.UnitIsConnected = function(u) local m = ByUnit(u); return m and m.connected end
c.UnitIsDeadOrGhost = function(u) local m = ByUnit(u); return m and m.dead end
c.UnitAffectingCombat = function() return G.combat end
c.InCombatLockdown = function() return G.combat end
c.C_Spell = { GetSpellName = function(id) if id == 430 then return "Drink" end end }
c.C_Secrets = { ShouldAurasBeSecret = function() return G.aurasSecret end, GetPowerTypeSecrecy = function() return 2 end }
c.C_UnitAuras = {
  GetAuraDataByIndex = function(u, i, filter)
    local m = ByUnit(u)
    local a = m and m.auras[i]
    if not a then return nil end
    if G.aurasSecret then return { spellId = SecretValue(), name = SecretValue(), auraInstanceID = SecretValue() } end
    return { spellId = a.id, name = a.name, auraInstanceID = a.inst }
  end,
}
c.C_ChatInfo.InChatMessagingLockdown = function() return G.chatLockdown end
local sounds = {}
c.PlaySoundFile = function(path, channel) sounds[#sounds + 1] = { path, channel }; return true end
-- anything that would speak or act for the player: none of it may ever be called
local acted = {}
for _, name in ipairs({ "SendChatMessage", "CastSpellByName", "TargetUnit", "DoEmote", "AcceptTrade", "UseAction" }) do
  c[name] = function() acted[#acted + 1] = name end
end
c.C_ChatInfo.SendAddonMessage = function() acted[#acted + 1] = "SendAddonMessage" end

local function Fire(event, ...)
  c.FireEvent(event, ...)
  local arg1 = ...
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent and (not f.unitEvents[event] or f.unitEvents[event] == arg1) then
      f.scripts.OnEvent(f, event, ...)
    end
  end
end
local function Settle() for _ = 1, 6 do FlushTimers() end end
-- A chat message as the game delivers it: text, the sender's name, ... and the sender's GUID twelfth.
local function Say(event, text, guid, name)
  Fire(event, text, name or "Someone", "", "", name or "Someone", "", 0, 0, "", 0, 1, guid, 0, false, false, false, false)
  Settle()
end

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "Icons.lua", "modules/SpellMenu.lua",
  "healer/Config.lua", "healer/Logic.lua", "healer/Drinks.lua", "healer/Particles.lua", "healer/Display.lua", "healer/Picker.lua", "healer/Watch.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local HW, HL, HD, D, Wt = R.HealerWatch, R.HealerLogic, R.HealerDrinks, R.HealerDisplay, R.HealerWatcher

local function EventCount()
  local n = 0
  for _, f in ipairs(frames) do for _ in pairs(f.events) do n = n + 1 end end
  return n
end
local function Registered(event)
  for _, f in ipairs(frames) do if f.events[event] then return true, f.unitEvents[event] end end
  return false
end
local function OnUpdates()
  local n = 0
  for _, f in ipairs(frames) do if f.scripts.OnUpdate then n = n + 1 end end
  return n
end
local function Panel() return D.Frame() end
local function Shown() local f = Panel(); return f ~= nil and f.shown end
local function Status() return Panel() and Panel().status.text or nil end
local function Value() return Panel() and Panel().value.text or nil end
local function On() R:SetEnabled("healerWatch", true); Settle() end
local function Off() R:SetEnabled("healerWatch", false); Settle() end
local function EnterWorld() Fire("PLAYER_ENTERING_WORLD"); Settle() end
local function Mana(slot, mana)
  G.party[slot].mana = mana
  Fire("UNIT_POWER_UPDATE", "party" .. slot, "MANA")
  Settle()
end

---------------------------------------------------------------------------
-- 1. Off by default: nothing is built, listened for or read
---------------------------------------------------------------------------
do
  Check(c.TwichUIDB.modules.healerWatch == false and R.DEFAULT_MODULES.healerWatch == false, "Healer Watch is opt-in")
  Check(EventCount() == 0 and Panel() == nil, "no frame and no event while off")
  EnterWorld()
  Check(EventCount() == 0 and Panel() == nil and #powerAsked == 0, "entering the world while off reads nothing")
end

---------------------------------------------------------------------------
-- 2. Logic.lua on its own
---------------------------------------------------------------------------
do
  local t = HW.NormalizeThresholds(30, 35, 15, 20)
  local band, seq = nil, {}
  for _, pct in ipairs({ 50, 31, 29.9, 30, 33, 34.9, 35, 34, 14, 15, 19.9, 20, 25, 36 }) do
    band = HL.NextBand(band, pct, t)
    seq[#seq + 1] = band
  end
  Check(table.concat(seq, ",") == "ok,ok,low,low,low,low,ok,ok,critical,critical,critical,low,low,ok",
    "bands begin below the threshold and end at the clear point: " .. table.concat(seq, ","))
  Check(HL.NextBand("low", nil, t) == nil, "no measured mana is no band, never low")

  t = HW.NormalizeThresholds(30, 20, 40, 90)
  Check(t.low == 30 and t.lowClear == 30 and t.critical == 30 and t.criticalClear == 30, "critical never above low; clear points at or above their thresholds")
  t = HW.NormalizeThresholds(30, 35, 10, 50)
  Check(t.criticalClear == 35, "the critical clear point never above the low one")

  local P = HW.DEFAULT_PHRASES
  local function M(text, phrases) return (HL.Match(text, phrases or P)) end
  Check(M("oom") == 1 and M("OOM") == 1 and M("oom!") == 1 and M("  Oom  ") == 1 and M("going oom, sorry") == 1, "oom, in any case, with punctuation and in a sentence")
  Check(M("boom") == nil and M("ooms") == nil and M("zoom zoom") == nil, "never inside another word")
  Check(M("I'm OUT OF MANA") == 2 and M("need mana pls") == 3, "phrases of several words")
  Check(M("mana potion anyone?") == nil, "\"mana\" alone isn't a default phrase")
  Check(M("mana potion anyone?", { HW.BROAD_PHRASE }) == 1, "the broad keyword matches incidental mentions, as it says")
  Check(M("not oom") == 1, "no pretence of understanding negation: a whole-word match is just that")
  Check(M("o.m", { { text = "o.m", mode = "word" } }) == 1 and M("oom", { { text = "o.m", mode = "word" } }) == nil, "a phrase is literal, never a pattern")
  Check(M("o%m", { { text = "o%m", mode = "word" } }) == 1 and M("oom", { { text = "o%m", mode = "word" } }) == nil
    and M("x", { { text = "%a", mode = "word" } }) == nil, "pattern characters are plain")
  local exact = { { text = "oom", mode = "exact" } }
  Check(M("oom!", exact) == 1 and M(" OOM. ", exact) == 1 and M("oom please", exact) == nil, "a whole-message phrase ignores case and punctuation at the ends only")
  Check(M("élan oom", P) == 1 and M("éoom", P) == nil, "a letter of another alphabet counts as part of a word")

  local ex = HL.Excerpt("|cffff0000oom|r |TInterface\\Icons\\x:0|t |Hitem:1|h[Water]|h ||", 40)
  Check(ex == "oom [Water]", "markup is removed from an excerpt: " .. ex)
  Check(not HL.Excerpt("a|b|c"):find("|", 1, true), "no | survives")
  local long = HL.Excerpt(("abcdefghij"):rep(6), 40)
  Check(#long == 43 and long:sub(-3) == "...", "an excerpt is bounded")

  local cands = { { guid = "A", name = "Ann", unit = "party1", role = "HEALER" }, { guid = "B", name = "Bo", unit = "party2", role = "TANK" } }
  local s = HL.Resolve(cands, nil)
  Check(s.guid == "A" and s.source == "auto" and not s.problem, "the one with the Healer role, automatically")
  cands[2].role = "HEALER"
  Check(HL.Resolve(cands, nil).problem == "ambiguous", "two Healer roles: the player chooses")
  cands[1].role, cands[2].role = nil, nil
  Check(HL.Resolve(cands, nil).problem == "noRole", "no roles: the player chooses (never by class)")
  s = HL.Resolve(cands, { guid = "B", name = "Bo" })
  Check(s.guid == "B" and s.unit == "party2" and s.source == "manual", "a choice wins")
  s = HL.Resolve(cands, { guid = "Z", name = "Zed" })
  Check(s.problem == "away" and s.unit == nil and s.name == "Zed", "a chosen player who left: nobody else is watched in their place")

  local cfg = Wt.Config()
  local function V(input) local shown, why = HL.Visible(input, cfg); return shown, why end
  local sel = { guid = "A", name = "Ann", unit = "party1", source = "auto" }
  local okObs = { life = "alive", mana = { state = "ok", pct = 80 }, band = "ok", drink = { state = "no" } }
  Check(not V({ enabled = true, scopeActive = false, sel = sel, obs = okObs, now = 0 }), "scope is a gate")
  Check(V({ enabled = true, scopeActive = true, sel = sel, obs = okObs, now = 0 }), "always, by default")
  local att = setmetatable({ visibility = "attention" }, { __index = cfg })
  local function A(obs) return HL.Visible({ enabled = true, scopeActive = true, sel = sel, obs = obs, now = 100 }, att) end
  Check(not A(okObs), "attention: nothing to attend to")
  Check(not A({ life = "alive", mana = { state = "unknown" }, band = nil, drink = { state = "no" } }), "unknown mana never alerts")
  Check(not A({ life = "alive", mana = { state = "secret" }, band = nil, drink = { state = "no" } }), "restricted mana never alerts")
  Check(A({ life = "alive", mana = { state = "unknown" }, drink = { state = "yes" } }), "confirmed drinking alerts even with mana unknown")
  Check(A({ life = "alive", mana = { state = "ok", pct = 20 }, band = "low", drink = { state = "no" } }), "low mana alerts")
  Check(A({ life = "alive", mana = { state = "unknown" }, drink = { state = "hidden" }, chat = { phrase = "oom", at = 95 } }), "a current chat signal alerts on its own")
  Check(not A({ life = "alive", mana = { state = "unknown" }, drink = { state = "hidden" }, chat = { phrase = "oom", at = 80 } }), "an expired one doesn't")
  local noCombat = setmetatable({ showInCombat = false }, { __index = cfg })
  Check(not HL.Visible({ enabled = true, scopeActive = true, inCombat = true, sel = sel, obs = okObs, now = 0 }, noCombat), "hidden in combat when asked")
  Check(not V({ enabled = true, scopeActive = true, sel = { problem = "noRole" }, now = 0 }), "no healer: hidden during play by default")

  local v = HL.Present(sel, { life = "offline", mana = { state = "ok", pct = 10, cur = 1, max = 10 }, band = "critical", drink = { state = "yes" } }, cfg, 0)
  Check(v.status == "Offline" and v.manaText == "--" and not v.drinking, "offline comes first; stale readings aren't shown as current")
  v = HL.Present(sel, { life = "alive", mana = { state = "unknown" }, drink = { state = "no" } }, cfg, 0)
  Check(v.manaText == "--" and v.status:find("Mana not readable", 1, true), "unknown mana is \"--\", never 0%")
  v = HL.Present(sel, { life = "alive", mana = { state = "ok", pct = 34.9, cur = 1396, max = 4000 }, band = "ok", drink = { state = "yes" }, chat = { phrase = "oom", excerpt = "oom", at = 99 } }, cfg, 100)
  Check(v.manaText == "34%" and v.drinking and v.chat and v.status:find("Drinking", 1, true) and v.status:find("oom", 1, true), "drinking and chat together, neither hiding the other")
  local all = {}
  for _, sc in ipairs(HL.SCENARIOS) do
    local s2, o2 = HL.Scenario(sc[1], 100)
    local p = HL.Present(s2, o2, cfg, 100)
    all[#all + 1] = (p.status or "") .. (p.manaText or "")
  end
  local words = table.concat(all, " "):lower()
  Check(not words:find("ready") and not words:find("safe") and not words:find("pull"), "nothing ever says ready, safe or pull")
end

---------------------------------------------------------------------------
-- 3. Config.lua: what is stored, read through checks
---------------------------------------------------------------------------
do
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  c.TwichUIDB.ui.healerWatch = { lowAt = "x", scale = 9999, phrases = { { text = "OOM ", mode = "word" }, { text = "a|b" }, { text = "oom", mode = "word" } } }
  Check(HW.Get("lowAt") == 30 and HW.Get("scale") == 100, "an unusable stored value reads as its default")
  Check(c.TwichUIDB.ui.healerWatch.lowAt == "x", "and is left as it is")
  local list = HW.Phrases()
  Check(#list == 1 and list[1].text == "oom", "phrases are cleaned, deduplicated and bad ones dropped")
  c.TwichUIDB.ui.healerWatch = { phrases = {} }
  Check(#HW.Phrases() == 0, "an empty phrase list is the player's choice and kept")
  c.TwichUIDB.ui.healerWatch = {}
  Check(#HW.Phrases() == 3, "missing: the default three")
  for i = 1, 20 do HW.AddPhrase("p" .. i, "word") end
  Check(#HW.Phrases() == HW.MAX_PHRASES, "the phrase list is capped")
  Check(not HW.AddPhrase(("x"):rep(HW.PHRASE_MAX + 1)), "a phrase's length is capped")
  HW.ResetPhrases()
  Check(#HW.Phrases() == 3, "reset to the defaults")
  HW.Set("lowAt", 25); HW.Set("criticalAt", 40)
  Check(c.TwichUIDB.ui.healerWatch.criticalAt == 40 and HW.Thresholds().critical == 25, "inconsistent thresholds are used consistently, not rewritten")
  HW.SetPlace("TOPLEFT", 10.4, -20.6)
  HW.ApplyPreset("minimal")
  Check(HW.Get("preset") == "minimal" and HW.Get("showBar") == false, "a preset sets its values")
  HW.ResetSettings()
  Check(HW.Get("preset") == "compact" and HW.Get("lowAt") == 30 and HW.Get("point") == "TOPLEFT" and HW.Get("x") == 10 and HW.Get("y") == -21,
    "a reset keeps the place")
  HW.ResetPlace()
  c.TwichUIDB.ui.healerWatch = {}
end

---------------------------------------------------------------------------
-- 4. Watching: the one with the Healer role, in a dungeon
---------------------------------------------------------------------------
do
  On()
  local s = Wt.Snapshot()
  Check(s.running and s.scopeActive and s.unit == "party2" and s.source == "auto" and s.name == "Elyndra", "watches the Healer role in a dungeon")
  local reg, unit = Registered("UNIT_POWER_UPDATE")
  Check(reg and unit == "party2", "unit events for the watched unit alone")
  for _, k in ipairs(powerAsked) do Check(k == 0, "always asks for mana, never the current power type") end
  Check(Shown() and Value() == "75%" and Panel().name.text == "Elyndra", "shown with the measured mana")
  Check(Panel().mouse == false, "the panel takes no clicks")
  Check(not Registered("CHAT_MSG_SAY") and not Registered("CHAT_MSG_WHISPER") and Registered("CHAT_MSG_PARTY") and Registered("CHAT_MSG_INSTANCE_CHAT"),
    "chat: party and instance by default; say and whispers off")
  Check(not Registered("CHAT_MSG_CHANNEL") and not Registered("COMBAT_LOG_EVENT_UNFILTERED"), "never public channels or the combat log")
  Check(OnUpdates() == 0, "no OnUpdate")

  local before = Wt.Snapshot().manaReads
  Fire("UNIT_POWER_UPDATE", "party2", "ENERGY"); Settle()
  Fire("UNIT_POWER_UPDATE", "party1", "MANA"); Settle()
  Check(Wt.Snapshot().manaReads == before, "other power types and other units are dropped before any work")
  Mana(2, 1190)
  Check(Value() == "29%" and Status():find("Low mana", 1, true) and Wt.Snapshot().band == "low", "low below 30%")
  Mana(2, 1300)
  Check(Wt.Snapshot().band == "low", "still low under the clear point (no flicker)")
  Mana(2, 1400)
  Check(Wt.Snapshot().band == "ok" and not (Status() or ""):find("Low", 1, true), "clear at 35%")
  Mana(2, 400)
  Check(Wt.Snapshot().band == "critical" and Status():find("Critical mana", 1, true), "critical below 15%")
  G.party[2].max = 0
  Fire("UNIT_MAXPOWER", "party2", "MANA"); Settle()
  Check(Wt.Snapshot().mana == "none" and Value() == "--" and Wt.Snapshot().band == nil, "a zero maximum is no mana pool, not 0%")
  G.party[2].max = 4000
  Mana(2, 3000)
end

---------------------------------------------------------------------------
-- 5. Drinking: confirmed by an aura only
---------------------------------------------------------------------------
do
  local m = G.party[2]
  local function Aura(list) m.auras = list; Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle() end
  Aura({ { id = 430, name = "Drink", inst = 11 } })
  Check(Wt.Snapshot().drink == "yes" and Wt.Snapshot().drinkEvidence == "spell 430" and Status():find("Drinking", 1, true), "the registered drink aura")
  Check(Panel().drink.shown and not Panel().drink.desaturated, "a cup")
  Aura({ { id = 1135, name = "Drink", inst = 12 } })
  Check(Wt.Snapshot().drink == "yes" and Wt.Snapshot().drinkEvidence == "name", "another rank, by the client's own name for it")
  Aura({ { id = 9999, name = "Drinking Horn", inst = 13 }, { id = 29166, name = "Innervate", inst = 14 }, { id = 433, name = "Food", inst = 15 } })
  Check(Wt.Snapshot().drink == "no", "not a substring, not regeneration, not food")
  Aura({})
  m.mana = 3500; Fire("UNIT_POWER_UPDATE", "party2", "MANA"); Settle()
  Check(Wt.Snapshot().drink == "no", "rising mana is never drinking")
  local scans = Wt.Snapshot().auraScans
  Fire("UNIT_AURA", "party2", { addedAuras = { { spellId = 1243, name = "Power Word: Fortitude" } } }); Settle()
  Check(Wt.Snapshot().auraScans == scans and Wt.Snapshot().auraSkipped >= 1, "an update that can't be a drink is skipped")
  G.aurasSecret = true
  Aura({ { id = 430, name = "Drink", inst = 16 } })
  Check(Wt.Snapshot().drink == "hidden" and not Status():find("Drinking", 1, true), "hidden auras: drinking unseen, not confirmed")
  Check(Panel().drink.shown and Panel().drink.desaturated and Panel().drink.alpha < 1, "a faded cup says it can't be seen")
  G.aurasSecret = false
  Aura({})
end

---------------------------------------------------------------------------
-- 6. Chat: the watched healer only, in the channels chosen, for a while
---------------------------------------------------------------------------
do
  local heal = G.party[2]
  Say("CHAT_MSG_PARTY", "boom goes the dynamite", heal.guid, "Elyndra")
  Check(Wt.Snapshot().chatPhrase == nil, "boom isn't oom")
  Say("CHAT_MSG_PARTY", "oom", G.party[3].guid, "Kael")
  Check(Wt.Snapshot().chatPhrase == nil and Wt.Snapshot().chatOther == 1, "someone else saying oom is ignored")
  Say("CHAT_MSG_PARTY", "oom", nil, "Elyndra")
  Check(Wt.Snapshot().chatPhrase == nil and Wt.Snapshot().chatNoSender == 1, "a sender is never matched by name")
  Say("CHAT_MSG_PARTY", SecretValue(), SecretValue(), "Elyndra")
  Check(Wt.Snapshot().chatPhrase == nil and Wt.Snapshot().chatSecret == 1, "restricted chat is skipped and counted")
  Say("CHAT_MSG_SAY", "oom", heal.guid, "Elyndra")
  Check(Wt.Snapshot().chatPhrase == nil, "/say is off by default")
  local manaBefore = Wt.Snapshot().manaPct
  Say("CHAT_MSG_PARTY", "OOM! |cffff0000drinking|r", heal.guid, "Elyndra")
  local s = Wt.Snapshot()
  Check(s.chatPhrase == "oom" and s.manaPct == manaBefore and s.drink == "no", "a mana message: never a mana reading, never drinking")
  Check(Panel().chat.shown and Status():find("Said", 1, true) and not Status():find("|c", 1, true), "shown as said, cleaned")
  Check(#sounds == 0, "silent by default")
  Say("CHAT_MSG_PARTY", "oom!", heal.guid, "Elyndra")
  Check(Wt.Snapshot().chatDuplicates == 0 and Wt.Snapshot().chatMatched == 2, "a different message is a new one")
  Say("CHAT_MSG_PARTY", "OOM!", heal.guid, "Elyndra")
  Check(Wt.Snapshot().chatDuplicates == 1, "the same message again soon is the same signal")
  heal.auras = { { id = 430, name = "Drink", inst = 21 } }
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  Check(Status():find("Drinking", 1, true) and Status():find("Said", 1, true), "drinking and a message at once")
  NOW = NOW + 11
  RunLongTimers(20); Settle()
  Check(Wt.Snapshot().chatPhrase == nil and not Panel().chat.shown and not Status():find("Said", 1, true), "it expires")
  heal.auras = {}
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()

  HW.Set("chatWhisper", true); HW.Set("chatSound", true); Settle()
  Check(Registered("CHAT_MSG_WHISPER"), "whispers when chosen")
  Say("CHAT_MSG_WHISPER", "need mana", heal.guid, "Elyndra")
  Check(Wt.Snapshot().chatPhrase == "need mana" and #sounds == 1, "a whisper from the healer, with the chosen sound once")
  NOW = NOW + 11; RunLongTimers(20); Settle()
  Say("CHAT_MSG_WHISPER", "oom", heal.guid, "Elyndra")
  Check(#sounds == 1 and Wt.Snapshot().soundsHeld == 1, "sounds are kept apart")
  NOW = NOW + 11; RunLongTimers(20); Settle()
  HW.Set("chatWhisper", false); HW.Set("chatSound", false)
  HW.Set("chatDisplay", "off"); Settle()
  Check(not Registered("CHAT_MSG_PARTY"), "chat off: nothing listened to")
  HW.Set("chatDisplay", "text"); Settle()
end

---------------------------------------------------------------------------
-- 7. Who is watched when the group changes
---------------------------------------------------------------------------
do
  local heal = G.party[2]
  Say("CHAT_MSG_PARTY", "oom", heal.guid, "Elyndra")
  -- the healer moves from party2 to party1
  G.party[1], G.party[2] = G.party[2], G.party[1]
  G.party[2].mana = 100
  Fire("GROUP_ROSTER_UPDATE"); Settle()
  local s = Wt.Snapshot()
  Check(s.unit == "party1" and s.guid == heal.guid, "follows the player to their new slot")
  Check(select(2, Registered("UNIT_POWER_UPDATE")) == "party1", "unit events follow")
  Check(s.manaPct == heal.mana / heal.max * 100, "readings are their own, never the old slot's")
  Check(s.chatPhrase == "oom", "what they said is still theirs")
  NOW = NOW + 11; RunLongTimers(20); Settle()

  -- choosing someone else; then the chosen player leaves
  local tank = G.party[2]
  Check(Wt.Choose(tank.guid), "choose the tank")
  s = Wt.Snapshot()
  Check(s.source == "manual" and s.unit == "party2" and s.chatPhrase == nil, "a manual choice; nothing of the healer carries over")
  table.remove(G.party, 2)
  Fire("GROUP_ROSTER_UPDATE"); Settle()
  s = Wt.Snapshot()
  Check(s.problem == "away" and s.unit == nil and not Registered("UNIT_POWER_UPDATE"), "the chosen player left: nobody watched in their place")
  Check(not Shown(), "hidden during play by default")
  HW.Set("showSetup", true); Settle()
  Check(Shown() and Status() == "Borin isn't in your group", "or says so, when asked to")
  HW.Set("showSetup", false)
  table.insert(G.party, 2, tank)
  Fire("GROUP_ROSTER_UPDATE"); Settle()
  Check(Wt.Snapshot().unit == "party2" and Wt.Snapshot().source == "manual", "back when they return")
  Wt.Choose("auto"); Settle()
  Check(Wt.Snapshot().source == "auto" and Wt.Snapshot().guid == heal.guid, "back to automatic")

  -- the same name on another realm: chosen by identity, and only their own messages count
  local twin = Member("Player-2-TWIN", "Elyndra", "Otherrealm", "NONE", 500, 5000)
  G.party[#G.party + 1] = twin
  Fire("GROUP_ROSTER_UPDATE"); Settle()
  local seen
  for _, cand in ipairs(Wt.Candidates()) do if cand.guid == twin.guid then seen = cand end end
  Check(seen and seen.fullName == "Elyndra-Otherrealm", "a member from another realm is named with it")
  Say("CHAT_MSG_PARTY", "oom", twin.guid, "Elyndra-Otherrealm")
  Check(Wt.Snapshot().chatPhrase == nil, "the other Elyndra's message isn't the watched one's")
  Wt.Choose(twin.guid); Settle()
  Check(Wt.Snapshot().guid == twin.guid and Value() == "10%", "the chosen one, by identity")
  Wt.Choose("auto")
  table.remove(G.party)

  -- two healers, then none
  G.party[3].role = "HEALER"
  Fire("PLAYER_ROLES_ASSIGNED"); Settle()
  Check(Wt.Snapshot().problem == "ambiguous", "two Healer roles: choose")
  G.party[3].role, heal.role = "DAMAGER", "NONE"
  Fire("PLAYER_ROLES_ASSIGNED"); Settle()
  Check(Wt.Snapshot().problem == "noRole", "no Healer role: choose")
  Wt.Choose(G.me.guid); Settle()
  Check(Wt.Snapshot().unit == "player" and Wt.Snapshot().mana == "none", "you can watch yourself (no mana pool here: said so)")
  -- leaving the group ends a choice of someone else, not of yourself
  Wt.Choose(G.party[3].guid)
  G.group, G.party = false, {}
  Fire("GROUP_ROSTER_UPDATE"); Settle()
  Check(Wt.Choice() == "auto", "leaving the group ends the choice")
  World()
  Fire("GROUP_ROSTER_UPDATE"); Settle()
  Check(Wt.Snapshot().guid == "Player-1-HEAL", "a new group: automatic again")
end

---------------------------------------------------------------------------
-- 8. Life, scope, combat and restricted mana
---------------------------------------------------------------------------
do
  local heal = G.party[2]
  heal.connected = false
  Fire("UNIT_CONNECTION", "party2"); Settle()
  Check(Status() == "Offline" and Value() == "--", "offline first, no stale number")
  heal.connected = true
  heal.dead = true
  Fire("UNIT_CONNECTION", "party2"); Settle()
  Check(Status() == "Dead", "dead")
  heal.dead = false
  Fire("UNIT_HEALTH", "party2"); Settle()
  Check(Value() == "75%", "alive again, read again")

  HW.Set("showInCombat", false); Settle()
  G.combat = true
  Fire("PLAYER_REGEN_DISABLED"); Settle()
  Check(not Shown() and Wt.Snapshot().reason == "combat", "hidden in combat by choice")
  G.combat = false
  Fire("PLAYER_REGEN_ENABLED"); Settle()
  Check(Shown(), "back after combat")
  HW.Set("showInCombat", true)

  G.secretMana = true
  Mana(2, 1000)
  local s = Wt.Snapshot()
  Check(s.mana == "secret" and s.band == nil and s.manaPct == nil, "restricted mana: drawn, never judged")
  Check(percentCalls > 0 and Panel().valueSecret.shown and Panel().valueSecret.formatted, "the game's own value goes straight to the number")
  G.secretMana = false
  Mana(2, 3000)
  Check(Wt.Snapshot().mana == "ok" and not Panel().valueSecret.shown, "plain again")

  G.instance = nil
  Fire("PLAYER_ENTERING_WORLD"); Settle()
  Check(not Shown() and not Registered("UNIT_POWER_UPDATE") and not Registered("CHAT_MSG_PARTY") and Registered("GROUP_ROSTER_UPDATE"),
    "outside a dungeon: hidden, and only the roster is listened for")
  HW.Set("scope", "group"); Settle()
  Check(Shown() and Registered("UNIT_POWER_UPDATE"), "anywhere in a group, when chosen")
  HW.Set("scope", "dungeon"); Settle()
  G.instance = "party"
  Fire("PLAYER_ENTERING_WORLD"); Settle()
  Check(Shown(), "a dungeon again")
end

---------------------------------------------------------------------------
-- 9. Preview and simulation: isolated from the live readings
---------------------------------------------------------------------------
do
  local live = Wt.Snapshot()
  Check(Wt.PreviewStart(false), "preview starts")
  Wt.SetScenario("critical")
  Check(Panel().mark.shown and Value() == "9%" and Status():find("Critical", 1, true), "the scenario in the real panel, marked")
  local during = Wt.Snapshot()
  Check(during.guid == live.guid and during.manaPct == live.manaPct and during.drink == live.drink, "the live readings are untouched")
  Mana(2, 2000)
  Check(Value() == "9%", "a live change doesn't break into the preview")
  Wt.SetScenario("noHealer")
  Check(Status() == "Choose a healer", "every scenario draws")
  Wt.PreviewStop()
  Check(not Panel().mark.shown and Value() == "50%", "the live panel comes back with its own reading")
  Check(Wt.PreviewStart(true) and Wt.PositioningActive(), "moving")
  G.combat = true
  Fire("PLAYER_REGEN_DISABLED"); Settle()
  Check(not Wt.PreviewActive() and not Panel().mark.shown, "combat ends a preview")
  G.combat = false
  Fire("PLAYER_REGEN_ENABLED"); Settle()
  local stored = c.TwichUIDB.ui.healerWatch or {}
  for k in pairs(stored) do
    Check(HW.DEFAULTS[k] ~= nil or k == "phrases", "only settings are saved, not " .. tostring(k))
  end
  local v = Wt.ScenarioView("drinkChat")
  Check(v.drinking and v.chat and Wt.Snapshot().drink == "no", "an inline scenario is its own tables")
end

---------------------------------------------------------------------------
-- 9b. The mana bar's texture and border
---------------------------------------------------------------------------
do
  local bar = Panel().bar
  Check(bar.sb and bar.sb.texture == "Interface\\Buttons\\WHITE8x8", "a flat fill by default")
  Check(bar.backdrop ~= nil, "the default border is drawn on the bar's own frame")
  HW.Set("barBorder", false); Settle()
  Check(bar.backdrop == nil, "no border when it is off")
  HW.Set("barBorder", true)
  HW.BarLook.Set("borderSize", 3); Settle()
  Check(HW.BarLook.Get("borderSize") == 3 and bar.backdrop ~= nil, "the border's thickness is the shared look's")
  HW.BarLook.Reset()
  HW.Set("barTexture", "Gone Texture"); Settle()
  Check(bar.sb.texture == "Interface\\Buttons\\WHITE8x8" and HW.Get("barTexture") == "Gone Texture", "a texture that has gone is drawn flat and stays chosen")
  HW.ResetSettings()
  Check(HW.Get("barTexture") == "solid", "a reset puts the fill back")
end

---------------------------------------------------------------------------
-- 9c. Click the panel to choose a healer: only while it asks you to
---------------------------------------------------------------------------
do
  local menus = {}
  c.MenuUtil = { CreateContextMenu = function(owner, build)
    local m = { owner = owner, items = {} }
    build(owner, { CreateTitle = function(_, t) m.title = t end,
      CreateRadio = function(_, label, is, pick) m.items[#m.items + 1] = { label = label, pick = pick, is = is } end })
    menus[#menus + 1] = m
  end }
  local PK = R.HealerPicker
  local menu = function() for _, f in ipairs(frames) do if f.name == "TwichUIHealerPicker" then return f end end end
  local pick = Panel().pick
  Check(pick.mouse == false, "click-through while it shows a healer")
  G.party[2].role = "NONE"
  HW.Set("showSetup", true)
  Fire("PLAYER_ROLES_ASSIGNED"); Settle()
  Check(Shown() and Status() == "Choose a healer" and pick.mouse == true, "clickable while it asks you to choose")
  pick.scripts.OnClick(pick)
  Check(#menus == 0, "TwichUI's own menu opens, not the game's context menu")
  local m = menu()
  Check(m and m.shown and PK.IsOpen(), "the menu is open")
  Check(m.template == "BackdropTemplate" and m.backdrop ~= nil, "it wears the shared menu look")
  local rows = {}
  for _, f in ipairs(frames) do if f.parent == m and f.kind == "Button" then rows[#rows + 1] = f end end
  Check(#rows == 5, "five rows: automatic, you, and the group")
  Check(rows[1].name.text == "Automatic" and rows[1].dot.shown == true and rows[1].accent.shown == true, "automatic is marked")
  Check(rows[2].dot.shown == false, "the others are not")
  Check(m.points[1][1] == "TOPLEFT" and m.points[1][2] == pick, "it hangs below the panel")
  pick.scripts.OnClick(pick)
  Check(not m.shown and not PK.IsOpen(), "clicking the panel again closes it")
  pick.scripts.OnClick(pick)
  Check(m.shown, "and again opens it")
  Fire("GROUP_ROSTER_UPDATE")
  Check(not m.shown, "a change of group closes it")
  pick.scripts.OnClick(pick)
  local heal
  for _, r in ipairs(rows) do if r.name.text == "Elyndra" then heal = r end end
  Check(heal and heal.note.text == "", "a member without the Healer role has no mark")
  heal.scripts.OnClick(heal); Settle()
  Check(not m.shown, "choosing closes the menu")
  Check(Wt.Snapshot().guid == "Player-1-HEAL" and Wt.Snapshot().source == "manual" and pick.mouse == false, "choosing watches them, and the panel is click-through again")
  Check(#acted == 0, "choosing sends nothing")
  Wt.Choose("auto")
  G.party[2].role = "HEALER"
  HW.Set("showSetup", false)
  Fire("PLAYER_ROLES_ASSIGNED"); Settle()
  Wt.PreviewStart(false); Wt.SetScenario("noHealer")
  Check(pick.mouse == false, "a preview is never clickable")
  Wt.PreviewStop()
  -- the game's menu is the fallback when TwichUI's is missing
  G.party[2].role = "NONE"
  HW.Set("showSetup", true)
  Fire("PLAYER_ROLES_ASSIGNED"); Settle()
  R.HealerPicker = nil
  pick.scripts.OnClick(pick)
  local fm = menus[1]
  Check(fm and fm.owner == pick and fm.items[1].label:find("Automatic", 1, true) and #fm.items == 5, "fallback: the game's menu lists the same rows")
  Check(fm.items[1].is() == true, "fallback: automatic is marked")
  R.HealerPicker = PK
  G.party[2].role = "HEALER"
  HW.Set("showSetup", false)
  Fire("PLAYER_ROLES_ASSIGNED"); Settle()
end

---------------------------------------------------------------------------
-- 9d. The optional attention flash
---------------------------------------------------------------------------
do
  local fl = Panel().flash
  local function Plays() return fl.group.plays end
  local base = Plays()
  Wt.PreviewStop(); Settle()
  G.party[2].mana = 3000; Fire("UNIT_POWER_UPDATE", "party2", "MANA"); Settle()
  NOW = NOW + 5
  Mana(2, 300)
  Check(Plays() == base, "off by default: no flash when mana turns critical")
  HW.Set("effectCritical", "flash"); HW.Set("effectChat", "flash"); HW.Set("effectDrinking", "flash"); Settle()
  NOW = NOW + 5
  Mana(2, 3000); NOW = NOW + 5
  Mana(2, 300)
  Check(Plays() == base + 1, "flashes when mana becomes critical")
  Mana(2, 200)
  Check(Plays() == base + 1, "not again while it stays critical")
  NOW = NOW + 1
  Say("CHAT_MSG_PARTY", "oom", G.party[2].guid, "Elyndra")
  Check(Plays() == base + 1, "never twice within two seconds")
  NOW = NOW + 11; RunLongTimers(20); Settle()   -- the first signal has expired
  Say("CHAT_MSG_PARTY", "out of mana", G.party[2].guid, "Elyndra")
  Check(Plays() == base + 2, "flashes when they say something")
  NOW = NOW + 11; RunLongTimers(20); Settle()
  NOW = NOW + 3
  G.party[2].auras = { { id = 430, name = "Drink", inst = 77 } }
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  Check(Plays() == base + 3, "flashes when drinking begins")
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  NOW = NOW + 3
  Check(Plays() == base + 3, "not on a repeat look")
  c.TwichUIDB.modules.arrivalReducedMotion = true
  NOW = NOW + 5
  NOW = NOW + 11; RunLongTimers(20); Settle()
  Say("CHAT_MSG_PARTY", "need mana", G.party[2].guid, "Elyndra")
  Check(Plays() == base + 3, "never with reduced motion")
  c.TwichUIDB.modules.arrivalReducedMotion = false
  Check(Wt.PreviewStart(false) and Wt.TestFlash("chat") and Plays() == base + 4, "Try the flash plays in a preview, switched on or not")
  Wt.PreviewStop()
  G.party[2].auras = {}
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  HW.Set("effectCritical", "none"); HW.Set("effectChat", "none"); HW.Set("effectDrinking", "none")
  Mana(2, 3000)
end

---------------------------------------------------------------------------
-- 9e. The attention effect: a setting per trigger (None, Flash, Magical particles), read from the old flash checkboxes
-- until it is chosen, and the particles themselves
---------------------------------------------------------------------------
do
  local saved = c.TwichUIDB.ui.healerWatch
  local function Raw(t) c.TwichUIDB.ui.healerWatch = t end
  -- the migration reads, and never writes
  Raw({ flashChat = true, flashCritical = false })
  Check(HW.Get("effectChat") == "flash" and HW.Get("effectCritical") == "none" and HW.Get("effectDrinking") == "none",
    "an old ticked flash reads as Flash; unticked or never set as None")
  Check(c.TwichUIDB.ui.healerWatch.effectChat == nil and c.TwichUIDB.ui.healerWatch.flashChat == true, "reading the old checkbox writes nothing")
  Raw({ flashChat = true, effectChat = "none" })
  Check(HW.Get("effectChat") == "none", "a saved effect is never second-guessed by the old checkbox")
  Raw({ flashChat = true, effectChat = "sparkles" })
  Check(HW.Get("effectChat") == "none" and c.TwichUIDB.ui.healerWatch.effectChat == "sparkles", "an unknown effect reads as None and is left as it is")
  Raw({ particleColor = "zzz", particleIntensity = "huge" })
  Check(HW.Get("particleColor") == HW.DEFAULTS.particleColor and HW.Get("particleIntensity") == "standard", "an unusable color or strength reads as its default")
  Check(not HW.Set("particleColor", "ff00") and not HW.Set("particleIntensity", "loud") and not HW.Set("effectChat", "sparkles"), "unusable values are refused")
  Raw({ flashCritical = true })
  HW.ResetSettings()
  Check(HW.Get("effectCritical") == "none", "Reset puts the effect back to None, the old checkbox too")
  Raw(saved)
  -- the layout the Classic preset publishes still reads as Flash
  Raw({ flashChat = true, flashCritical = true, flashDrinking = true })
  Check(HW.Get("effectChat") == "flash" and HW.Get("effectCritical") == "flash" and HW.Get("effectDrinking") == "flash", "a published layout with the old checkboxes reads as Flash")
  Raw(saved)

  Wt.PreviewStop(); Settle()
  G.party[2].mana = 3000; Fire("UNIT_POWER_UPDATE", "party2", "MANA"); Settle()
  local fl = Panel().flash
  Check(Panel().particles == nil, "no particle texture exists until particles are played")
  local LV = R.HealerParticles.LEVELS
  local function Pool() return Panel().particles end
  local function Playing()
    local n = 0
    if Pool() and Pool().built then for _, m in ipairs(Pool().motes) do if m.group.playing then n = n + 1 end end end
    return n
  end
  local function EdgePlaying() return Pool() and Pool().built and Pool().edge.group.playing end
  local function Bursts() return R.HealerParticles.Stats().bursts end
  local function Trigger()   -- mana down into critical, from fine
    NOW = NOW + 5; Mana(2, 3000)
    NOW = NOW + 5; Mana(2, 300)
  end

  -- None: nothing plays
  Trigger()
  Check(Pool() == nil and not fl.group.playing, "None: no particles, no flash")

  -- Particles use the same trigger, once
  HW.Set("effectCritical", "particles"); Settle()
  local flashPlays = fl.group.plays
  local b0, frames0 = Bursts(), #frames
  Trigger()
  Check(Pool() and Playing() == LV.standard.motes and EdgePlaying() and Bursts() == b0 + 1, "critical mana plays one burst of the Standard motes and the edge glow")
  Check(fl.group.plays == flashPlays and fl:GetAlpha() == 0, "particles do not flash the panel")
  local nFrames = #frames
  Mana(2, 200); Mana(2, 250)
  Check(Bursts() == b0 + 1, "mana moving while it stays critical starts no new burst")
  Fire("UNIT_POWER_UPDATE", "party2", "MANA"); Settle()
  Check(Bursts() == b0 + 1, "an unchanged update starts none either")
  Mana(2, 3000); Mana(2, 300)   -- out and in again at once: folded into the burst that is playing
  Check(Bursts() == b0 + 1 and R.HealerParticles.Stats().coalesced >= 1, "a repeat trigger during a burst is coalesced")
  NOW = NOW + R.HealerParticles.DURATION + 1
  Mana(2, 3000); Mana(2, 300)
  Check(Bursts() == b0 + 2 and Playing() == LV.standard.motes, "after the burst is over the next trigger plays a new one, not a second one on top")
  for _ = 1, 6 do NOW = NOW + 4; Mana(2, 3000); Mana(2, 300) end
  Check(Playing() <= R.HealerParticles.MOTES and #Pool().motes == R.HealerParticles.MOTES and #frames == nFrames,
    "repeated triggers never grow the pool: no new texture or frame")
  Check(OnUpdates() == 0, "no OnUpdate script anywhere, playing or idle")
  for _, m in ipairs(Pool().motes) do
    Check(m.group.plays == 0 or m.move.offset ~= nil, "every mote that played has a drift")
  end
  local m1 = Pool().motes[1]
  do   -- from the middle: each puff starts within the central fifth of the panel and ends outside the panel
    local w, h = Panel():GetWidth(), Panel():GetHeight()
    local ok = true
    for i = 1, LV.standard.motes do
      local m = Pool().motes[i]
      local pt = m.tex.points[#m.tex.points]
      local x, y = pt[4], pt[5]
      local ex, ey = x + m.move.offset[1], y + m.move.offset[2]
      if math.abs(x - w / 2) > w * 0.1 + 0.01 or math.abs(y - h / 2) > h * 0.1 + 0.01 then ok = false end
      if ex > 0 and ex < w and ey > 0 and ey < h then ok = false end
    end
    Check(ok, "puffs start near the middle and finish outside the panel")
  end
  Check(math.abs(m1.move.offset[1]) + math.abs(m1.move.offset[2]) > 0 and math.abs(m1.move.offset[1]) < 400 and math.abs(m1.move.offset[2]) < 400, "every puff travels outward, a bounded distance")

  -- color and strength: the effect only
  local barColor = Panel().bar.sb.barColor
  local statusText, valueText = Status(), Value()
  HW.Set("particleColor", "ffff0000"); Settle()
  Check(Playing() == 0 and not EdgePlaying(), "a new color ends the burst in the old one")
  Check(Panel().bar.sb.barColor == barColor or (barColor and Panel().bar.sb.barColor[1] == barColor[1]), "the color does not touch the mana bar")
  Check(Status() == statusText and Value() == valueText, "or the words and numbers")
  HW.Set("particleIntensity", "strong"); Settle()
  NOW = NOW + 10; Mana(2, 3000); Mana(2, 300)
  local mote = Pool().motes[1]
  Check(Playing() == LV.strong.motes and mote.tex.vertex and mote.tex.vertex[1] == 1 and mote.tex.vertex[2] == 0, "Strong plays the Strong count of motes in the chosen color")
  HW.Set("particleIntensity", "subtle"); Settle()
  NOW = NOW + 10; Mana(2, 3000); Mana(2, 300)
  Check(Playing() == LV.subtle.motes, "Subtle plays its count")

  -- switching modes
  HW.Set("effectCritical", "flash"); Settle()
  Check(Playing() == 0 and not EdgePlaying(), "Particles to Flash: the particles stop at once")
  NOW = NOW + 10; Mana(2, 3000); Mana(2, 300)
  Check(fl.group.playing and Playing() == 0, "Flash plays only the flash")
  HW.Set("effectCritical", "particles"); Settle()
  Check(not fl.group.playing and fl:GetAlpha() == 0 and Panel().body:GetAlpha() == 1, "Flash to Particles: the flash stops and the panel's look is restored")
  NOW = NOW + 10; Mana(2, 3000); Mana(2, 300)
  Check(Playing() == LV.subtle.motes and not fl.group.playing, "then only the particles play")
  HW.Set("effectCritical", "none"); Settle()
  Check(Playing() == 0 and not EdgePlaying() and not fl.group.playing and fl:GetAlpha() == 0, "None leaves nothing running or altered")
  NOW = NOW + 10; Mana(2, 3000); Mana(2, 300)
  Check(Playing() == 0 and not fl.group.playing, "and nothing starts")

  -- the other triggers use the same effect, with their own setting
  HW.Set("effectChat", "particles"); HW.Set("effectDrinking", "particles"); Settle()
  NOW = NOW + 10; RunLongTimers(30); Settle()
  Say("CHAT_MSG_PARTY", "oom", G.party[2].guid, "Elyndra")
  Check(Playing() == LV.subtle.motes, "a mana message plays the particles when that trigger is set to them")
  NOW = NOW + R.HealerParticles.DURATION + 1; RunLongTimers(30); Settle()
  G.party[2].auras = { { id = 430, name = "Drink", inst = 78 } }
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  Check(Playing() == LV.subtle.motes and Bursts() >= 1, "confirmed drinking plays them too")
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  local after = Bursts()
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  Check(Bursts() == after, "a repeated look at the same drinking aura starts nothing")
  -- while they keep drinking: a burst, a rest, the next burst; never two at once and never a pile of timers
  local gap = R.HealerParticles.DURATION + 2
  NOW = NOW + gap; RunLongTimers(10); Settle()
  Check(Bursts() == after + 1 and Playing() == LV.subtle.motes, "still drinking: another burst follows")
  NOW = NOW + gap; RunLongTimers(10); Settle()
  Check(Bursts() == after + 2, "and another")
  G.party[2].auras = {}   -- drinking ends while the next burst's timer is waiting
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  NOW = NOW + gap; RunLongTimers(10); Settle()
  NOW = NOW + gap; RunLongTimers(10); Settle()
  Check(Bursts() == after + 2, "drinking over: the bursts stop")
  -- another healer, or a different effect, ends the repetition too
  G.party[2].auras = { { id = 430, name = "Drink", inst = 79 } }
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  local again = Bursts()
  Check(again == after + 3, "drinking again begins a new run")
  RunLongTimers(10); Settle()
  Check(Bursts() == again, "a rest timer that fires early starts nothing while a burst is still running")
  HW.Set("effectDrinking", "flash"); Settle()
  NOW = NOW + gap; RunLongTimers(10); Settle()
  Check(Bursts() == again and Playing() == 0, "changing the effect ends the repetition")
  HW.Set("effectDrinking", "particles"); Settle()
  G.party[2].auras = {}
  Fire("UNIT_AURA", "party2", { isFullUpdate = true }); Settle()
  -- behind the art, the text and the bar
  Check(Pool().frame.level < Panel().body.level, "the haze is drawn behind the panel's own parts")

  -- reduced motion: nothing, and no flash in its place
  HW.Set("effectCritical", "particles"); Settle()
  c.TwichUIDB.modules.arrivalReducedMotion = true
  local before = Bursts()
  NOW = NOW + 10; Mana(2, 3000); Mana(2, 300)
  Check(Bursts() == before and Playing() == 0 and not fl.group.playing, "Reduced motion: no particles and no flash instead")
  Check(select(2, D.PreviewParticles(D.NewSurface(Panel()), { particleColor = "ff3fc9bd", particleIntensity = "standard" })) == "motion", "the preview says so under Reduced motion")
  c.TwichUIDB.modules.arrivalReducedMotion = false

  -- a different healer: nothing carried over
  NOW = NOW + 10; Mana(2, 3000); Mana(2, 300)
  Check(Playing() == LV.subtle.motes, "particles playing for the first healer")
  G.party[2].role, G.party[3].role = "NONE", "HEALER"
  Fire("PLAYER_ROLES_ASSIGNED"); Settle()
  Check(Playing() == 0 and not EdgePlaying(), "watching someone else ends the first healer's particles")
  G.party[2].role, G.party[3].role = "HEALER", "NONE"
  Fire("PLAYER_ROLES_ASSIGNED"); Settle()
  Mana(2, 3000)

  -- hidden, switched off, profile change
  NOW = NOW + 10; Mana(2, 3000); Mana(2, 300)
  Check(Playing() == LV.subtle.motes, "particles playing again")
  HW.Invalidate("profile"); Settle()
  Check(Playing() == 0 and not EdgePlaying(), "a profile change ends them")
  Mana(2, 3000); NOW = NOW + 10; Mana(2, 300)
  Off()
  Check(Playing() == 0 and not EdgePlaying(), "switching off ends them")
  On()
  Mana(2, 3000)

  -- the preview: a sample surface, no healer, no trigger
  local surface = D.NewSurface(Panel())
  local snap = Wt.Snapshot()
  local liveBursts = Bursts()
  local cfgv = { particleColor = "ff3fc9bd", particleIntensity = "standard" }
  Check(D.PreviewParticles(surface, cfgv) == true and surface.particles and surface.particles.motes[LV.standard.motes].group.playing, "the sample plays a burst")
  local n1 = #frames
  local firstPlays = surface.particles.motes[1].group.plays
  D.PreviewParticles(surface, cfgv)
  local playing = 0
  for _, m in ipairs(surface.particles.motes) do if m.group.playing then playing = playing + 1 end end
  Check(playing == LV.standard.motes and #frames == n1 and surface.particles.motes[1].group.plays == firstPlays + 1, "playing it again restarts it, never layers it")
  Check(Playing() == 0 and Bursts() == liveBursts + 2 and Wt.Snapshot().chatSeen == snap.chatSeen
    and Wt.Snapshot().renders == snap.renders and #acted == 0, "the preview does not touch the live panel, its state or the group")
  R.SettingsLauncher.Closed()
  playing = 0
  for _, m in ipairs(surface.particles.motes) do if m.group.playing then playing = playing + 1 end end
  Check(playing == 0 and not surface.particles.edge.group.playing, "closing the settings ends it")
  D.PreviewParticles(surface, cfgv)
  HW.Set("particleColor", "ff112233"); Settle()
  Check(not surface.particles.motes[1].group.playing, "changing the color ends a running preview rather than recoloring half of it")
  HW.Set("particleColor", HW.DEFAULTS.particleColor)
  HW.Set("effectChat", "none"); HW.Set("effectCritical", "none"); HW.Set("effectDrinking", "none"); Settle()
  Mana(2, 3000)
end

---------------------------------------------------------------------------
-- 10. Switching off, a profile change and back: nothing left behind, nothing doubled
---------------------------------------------------------------------------
do
  local events = EventCount()
  Say("CHAT_MSG_PARTY", "out of mana", G.party[2].guid, "Elyndra")
  Off()
  Check(EventCount() == 0 and not Shown(), "off: no event and no panel")
  NOW = NOW + 30; RunLongTimers(60); Settle()
  Check(not Shown() and EventCount() == 0, "a timer from before does nothing")
  On()
  Check(EventCount() == events and Shown(), "on again: the same events, not doubled")
  Check(Wt.Snapshot().chatPhrase == nil, "nothing observed before survives switching off")
  Wt.PreviewStart(false)
  HW.Invalidate("profile"); Settle()
  Check(not Wt.PreviewActive() and Shown() and EventCount() == events, "a profile change ends the preview and reads everything again")
  Fire("PLAYER_LEAVING_WORLD"); Settle()
  Check(not Shown() and not Registered("UNIT_POWER_UPDATE"), "leaving the world puts it away")
  EnterWorld()
  Check(Shown(), "and the world brings it back")
end

---------------------------------------------------------------------------
-- 11. Never acts, never speaks; the artwork is there
---------------------------------------------------------------------------
do
  Check(#acted == 0, "nothing was sent or done for the player: " .. table.concat(acted, ", "))
  local function Tga(path)
    local f = io.open(ROOT .. path:gsub("^Interface\\AddOns\\!!!TwichUI\\", ""):gsub("\\", "/") .. ".tga", "rb")
    if not f then return nil end
    local head = f:read(18)
    local body = f:read("*a")
    f:close()
    local alpha = false
    for i = 4, #body, 4 do if body:byte(i) < 255 then alpha = true break end end
    return head:byte(3), head:byte(17), head:byte(18), head:byte(13) + head:byte(14) * 256, head:byte(15) + head:byte(16) * 256, alpha
  end
  for id in pairs(HW.ART) do
    for drawn, side in pairs({ [128] = 256, [64] = 64, [24] = 32 }) do
      local kind, bpp, desc, w, h, alpha = Tga(HW.ArtFile(id, drawn))
      Check(kind == 2 and bpp == 32 and desc == 8 and w == side and h == side and alpha, id .. " at " .. drawn .. ": a " .. side .. " px 32-bit TGA with alpha")
    end
  end
  local toc = io.open(ROOT .. "!!!TwichUI.toc"):read("*a")
  local a, b, cc, d, e = toc:find("healer\\Config.lua", 1, true), toc:find("healer\\Logic.lua", 1, true), toc:find("healer\\Drinks.lua", 1, true),
    toc:find("healer\\Display.lua", 1, true), toc:find("healer\\Watch.lua", 1, true)
  local pk = toc:find("healer\\Picker.lua", 1, true)
  Check(pk and d < pk and pk < e and toc:find("modules\\SpellMenu.lua", 1, true) < pk, "the picker loads after the display and the menu look, before Watch")
  Check(a and b and cc and d and e and a < b and b < cc and cc < d and d < e and toc:find("diag\\HealerWatch.lua", 1, true), "the .toc loads Healer Watch in order")
end

if failures > 0 then print(failures .. " FAILED") os.exit(1) end
print("HEALER WATCH TESTS PASSED")
