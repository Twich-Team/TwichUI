-- Reminders: the "Well Fed" condition (reminders/Conditions.lua, State.lua's "wellFed" source). A fake world stands in for the
-- game's buffs; this checks our logic, not the game: the in-game checks are in docs/reminders.md.
dofile(TESTS .. "harness.lua")
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

---------------------------------------------------------------------------
-- A fake world: frames that record what they were told, the character's equipment, combat, life and mount state
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
  GetStringWidth = function(s) return #(s.text or "") * 8 end,
  GetStringHeight = function(s) return s.fontSize or 18 end,
  ClearAllPoints = function(s) s.points = {} end,
  SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
  GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  SetTexture = function(s, p) s.texture = p; return true end, SetTexCoord = function(s, ...) s.coords = { ... } end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  SetScale = function(s, v) s.scale = v end, SetFrameStrata = function(s, v) s.strata = v end,
  EnableMouse = function(s, v) s.mouse = v and true or false end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; s.fontSize = size; return true end,
  StartMoving = function(s) s.moving = true end, StopMovingOrSizing = function(s) s.moving = false end,
  GetLeft = function(s) return s.left end, GetRight = function(s) return s.left and s.left + s.w end,
  GetTop = function(s) return s.bottom and s.bottom + s.h end, GetBottom = function(s) return s.bottom end,
  CreateAnimationGroup = function(s)
    local g = Fake("group")
    g.owner, g.plays, g.stops = s, 0, 0
    g.Play = function(self) self.plays = self.plays + 1; self.playing = true end
    g.Stop = function(self) if self.playing then self.stops = self.stops + 1 end self.playing = false end
    g.Finish = function(self) self.playing = false; if self.scripts.OnFinished then self.scripts.OnFinished(self) end end
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

c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemWeaponSubclass = { Fishingpole = 20 }, ItemArmorSubclass = { Shield = 6 } }
local NOW = 1000
c.GetTime = function() return NOW end
c.issecretvalue = function() return false end
c.UnitAffectingCombat = function() return false end
c.UnitIsDeadOrGhost = function() return false end
c.UnitIsGhost = function() return false end
c.IsMounted = function() return false end

---------------------------------------------------------------------------
-- A fake world: what is in the hands, which hands have a temporary enchant, and the sounds played
---------------------------------------------------------------------------
c.Enum.WeaponSlot = { MainHand = 0, OffHand = 1, Ranged = 2 }
local EQ = {}        -- [inventory slot] = item id
local ENCH = {}      -- [Enum.WeaponSlot value] = true when that hand has a temporary enchant
local ITEMS = {      -- item id -> class, subclass
  [100] = { 2, 7 },  -- a sword
  [101] = { 4, 6 },  -- a shield
  [102] = { 2, 20 }, -- a fishing pole
  [103] = { 4, 0 },  -- something held in the off hand
}
local CALLS = { enchant = 0 }
local SECRET = {}
c.INVSLOT_MAINHAND, c.INVSLOT_OFFHAND = 16, 17
c.GetInventoryItemID = function(_, slot) return EQ[slot] end
c.C_Item = {
  GetItemInfoInstant = function(id)
    local it = ITEMS[id]
    if not it then return nil end
    return id, "", "", "INVTYPE_WEAPON", 0, it[1], it[2]
  end,
  GetItemNameByID = function() return nil end,
  RequestLoadItemDataByID = function() end,
  GetWeaponEnchantInfo = function(ws)
    CALLS.enchant = CALLS.enchant + 1
    if ENCH.secret then return SECRET end
    return { { hasEnchant = ENCH[ws] == true } }
  end,
}
c.issecretvalue = function(v) return v == SECRET end
local PLAYED = {}
c.PlaySoundFile = function(path, channel) PLAYED[#PLAYED + 1] = { path = path, channel = channel }; return true end

local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function Settle() for _ = 1, 6 do FlushTimers() end end

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "Icons.lua",
  "gear/Weights.lua", "gear/Prefs.lua", "gear/Data.lua",
  "reminders/AmmoItems.lua", "reminders/ArtData.lua", "reminders/Config.lua", "reminders/Gallery.lua", "reminders/Conditions.lua", "reminders/Ammunition.lua", "reminders/Evaluate.lua", "reminders/State.lua",
  "reminders/Display.lua", "reminders/Controller.lua", "setup/TwichConfig.lua", "../TwichUI_Settings/pages/RemindersPlain.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local RM, C, E, ST, D, CT, Pl = R.Reminders, R.ReminderConditions, R.ReminderEval, R.ReminderState, R.ReminderDisplay, R.ReminderController, R.RemindersPlain
local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN
local P = C.Get("wellFed")

---------------------------------------------------------------------------
-- A fake world: the helpful auras on the player
---------------------------------------------------------------------------
local AURAS = {}            -- { { spellId =, name = }, ... }
local SECRET = {}
local HIDDEN = false        -- C_Secrets.ShouldAurasBeSecret()
local CALLS = 0
local SPELL_NAME = "Well Fed"
c.C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
  CALLS = CALLS + 1
  assert(unit == "player" and filter == "HELPFUL", "only the player's helpful auras are asked for")
  if AURAS.error then error("Auras cannot be accessed when secret while tainted") end
  if AURAS.secret then return SECRET end
  return AURAS[i]
end }
c.C_Secrets = { ShouldAurasBeSecret = function() return HIDDEN end }
c.C_Spell = { GetSpellName = function(id) if id == 19705 then return SPELL_NAME end end }
c.issecretvalue = function(v) return v == SECRET end

local function Cond(what) return { type = "wellFed", what = what } end
local function Eval(what, obs) return P.Evaluate(assert(C.Check(Cond(what))), obs) end

---------------------------------------------------------------------------
-- 1. The condition
---------------------------------------------------------------------------
do
  Check(P, "the kind is registered")
  Check((Eval("missing", { wellFed = false })) == MATCH, "missing: no Well Fed")
  Check((Eval("missing", { wellFed = true })) == NOMATCH, "missing: Well Fed on")
  Check((Eval("applied", { wellFed = true })) == MATCH, "applied: Well Fed on")
  Check((Eval("applied", { wellFed = false })) == NOMATCH, "applied: no Well Fed")
  for _, what in ipairs({ "missing", "applied" }) do
    local result, why = Eval(what, {})
    Check(result == UNKNOWN and type(why) == "string", what .. ": unread is unknown, with a reason")
  end
  local needs = {}
  P.Needs(assert(C.Check(Cond("missing"))), function(k) needs[#needs + 1] = k end)
  Check(#needs == 1 and needs[1] == "wellFed", "it reads the wellFed observation")

  local m = assert(C.Check(Cond("missing")))
  Check(P.Summary(m) == "You are not Well Fed", "summary: " .. P.Summary(m))
  Check(P.Summary(assert(C.Check(Cond("applied")))) == "You are Well Fed", "summary, applied")
  Check(P.Observed(m, { wellFed = true }) == "Well Fed" and P.Observed(m, { wellFed = false }) == "Not Well Fed" and P.Observed(m, {}) == "Not read yet", "what it saw")

  local sc = P.Scenarios(m)
  Check(sc[1].key == "hungry" and sc[#sc].key == "unread", "scenarios: its own first, unread last")
  local want = { hungry = MATCH, fed = NOMATCH, unread = UNKNOWN }
  for _, s in ipairs(sc) do
    local obs = {}
    s.Apply(obs)
    Check(P.Evaluate(m, obs) == want[s.key], "scenario " .. s.key)
  end
  Check(P.Scenarios(assert(C.Check(Cond("applied"))))[1].key == "fed", "scenarios for applied start on fed")

  -- stored form
  local clean = C.Check({ type = "wellFed", what = "applied", negate = true, extra = 1 })
  Check(clean and clean.what == "applied" and clean.negate == nil and clean.extra == nil, "only its own field is kept")
  Check(select(1, C.Check({ type = "wellFed", what = "expiring" })) == nil, "a question it doesn't know is refused")
  Check(select(1, C.Check({ type = "wellFed" })) == nil, "no question is refused")
  Check(P.New().what == "missing", "a new one asks about not being Well Fed")

  -- which aura counts: any food's buff spell, told by the client's name for the spell or by its ID
  Check(C.IsWellFed(19705, nil, nil) and C.IsWellFed(555, "Well Fed", nil) and C.IsWellFed(555, "well fed", "Well Fed"), "by ID, by name, case aside")
  Check(C.IsWellFed(555, "Gut gesättigt", "Gut gesättigt") and not C.IsWellFed(555, "Well Fed", "Gut gesättigt"), "a translated client's own name is the one used")
  Check(not C.IsWellFed(555, "Food", "Well Fed") and not C.IsWellFed(555, "Nutritious Food", nil) and not C.IsWellFed(nil, nil, nil) and not C.IsWellFed(555, "", nil), "eating itself and nothing are not Well Fed")
end

---------------------------------------------------------------------------
-- 2. The settings words
---------------------------------------------------------------------------
do
  local new = P.New()
  Check(Pl.CondSentence(new) == "You are not well fed", "sentence: " .. tostring(Pl.CondSentence(new)))
  Check(not Pl.HasOperator(new) and not Pl.NeedsItem(new), "no is/is-not choice and no item")
  local subject, label = Pl.SubjectOf(new)
  Check(subject == "wellFed" and label == "Well Fed buff", "its subject: " .. tostring(subject))
  local applied = Pl.WithValue(new, "applied")
  Check(applied.what == "applied" and new.what == "missing", "changing the question never edits the one given")
  local made = Pl.WithSubject(Pl.WithSubject(new, "ammo"), "wellFed")
  Check(made.type == "wellFed" and made.what == "missing", "the subject can change to it and back")
  Check(Pl.WithSubject(applied, "wellFed").what == "applied", "choosing it again keeps the question")
  local choices = Pl.ValueChoices(new)
  Check(#choices == 2 and choices[1].value == "missing" and choices[2].value == "applied", "two questions to choose from")
  Check(Pl.ValueLabel(new) == "Is not Well Fed", "value label: " .. Pl.ValueLabel(new))
  local found
  for _, e in ipairs(Pl.Entries()) do if e.kind == "wellFed" then found = e end end
  Check(found and found.category == "Other" and found.make().type == "wellFed", "the picker offers the same Well Fed predicate under Other")
  local subjects = {}
  for _, s in ipairs(Pl.Subjects()) do subjects[s.value] = true end
  Check(subjects.wellFed, "the subject choices list it")
  Check(#Pl.Help(new) > 20, "it has help text")
  local tpl
  for _, t in ipairs(RM.TEMPLATES) do if t[1] == "wellFed" then tpl = t end end
  Check(tpl, "there is a template")

  -- the template: the plate artwork, drawn smaller than the default, saying what to do
  local ok, id = RM.Create("wellFed")
  local v = ok and RM.Get(id)
  Check(v and v.display.mode == "artworkText" and v.display.art == "wellfed" and v.display.text == "Eat something", "the template shows the plate artwork and its words")
  Check(v and v.display.size == 48 and v.display.size < RM.DISPLAY_DEFAULTS.size, "drawn smaller than the default size")
  Check(v and #v.conditions == 1 and v.conditions[1].cond.type == "wellFed" and v.conditions[1].cond.what == "missing", "and it asks about not being Well Fed")
  local art = RM.Art("wellfed")
  Check(art and art.label == "Plate and cutlery" and art.width == 256 and art.height == 186, "the artwork is registered")
  local listed = false
  for _, ch in ipairs(RM.CHOICES.art) do if ch[1] == "wellfed" then listed = true end end
  Check(listed, "and offered in the artwork choices")
  for _, name in ipairs({ "wellfed.tga", "wellfed-small.tga" }) do
    local f = io.open(ROOT .. "media/reminders/" .. name, "rb")
    Check(f ~= nil, name .. " is built")
    if f then f:close() end
  end
  if ok then RM.Delete(id) end
end

---------------------------------------------------------------------------
-- 3. The source: reading the auras, and staying current
---------------------------------------------------------------------------
c.TwichUIDB.ui = c.TwichUIDB.ui or {}
local ID = "r1"
c.TwichUIDB.ui.reminders = { version = 1, nextId = 2, list = { { id = ID, name = "Food", enabled = true, match = "all",
  conditions = { { type = "wellFed", what = "missing" } },
  display = { mode = "text", text = "Eat something" } } } }
AURAS[1] = { spellId = 1459, name = "Arcane Intellect" }
RM.Invalidate()
CT.Refresh()
Fire("PLAYER_ENTERING_WORLD"); Settle()
local function Shown() local f = D.Frame(ID) return f ~= nil and f.shown end
local function Obs() return ST.Observations().wellFed end

do
  Check(RM.Get(ID).valid, "the reminder is valid")
  local evf
  for _, f in ipairs(frames) do if f.units and f.units.UNIT_AURA then evf = f end end
  Check(evf and evf.units.UNIT_AURA == "player", "UNIT_AURA is listened for on the player only")
  Check(Obs() == false and Shown(), "buffed, but not Well Fed: the reminder shows")

  AURAS[2] = { spellId = 18125, name = "Well Fed" }
  Fire("UNIT_AURA", "player", { addedAuras = { {} } }); Settle()
  Check(Obs() == true and not Shown(), "the buff arrives: it goes away")

  AURAS[2] = nil
  Fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 7 } }); Settle()
  Check(Obs() == false and Shown(), "the buff runs out: it comes back")

  -- the names the client gives
  AURAS[2] = { spellId = 9999, name = "Gut gesättigt" }
  SPELL_NAME = "Gut gesättigt"
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == true, "a translated client: its own name for the spell")
  SPELL_NAME = "Well Fed"
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == false, "the other language's name is not Well Fed")
  AURAS[2] = { spellId = 19705, name = "Whatever" }
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == true, "the spell ID counts too")
  AURAS[2] = nil
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()

  -- events that cannot change the answer read nothing
  local before = CALLS
  Fire("UNIT_AURA", "player", { updatedAuraInstanceIDs = { 3 } }); Settle()
  Check(CALLS == before, "a timer refresh reads nothing")
  Fire("UNIT_AURA", "target", { addedAuras = { {} } }); Settle()
  Check(CALLS == before, "another unit's auras read nothing")
  Settle(); Settle()
  Check(CALLS == before, "no polling: nothing is read without an event")

  -- in a fight the payload's own fields can be secret: they are never compared, and an update that can't be read is looked at
  before = CALLS
  Fire("UNIT_AURA", "player", { isFullUpdate = SECRET, removedAuraInstanceIDs = SECRET }); Settle()
  Check(CALLS > before, "secret payload fields can't be told apart, so the auras are read")
  before = CALLS
  Fire("UNIT_AURA", "player", SECRET); Settle()
  Check(CALLS > before, "a secret payload too")
  before = CALLS
  Fire("UNIT_AURA", "player", { isFullUpdate = false }); Settle()
  Check(CALLS == before, "a plain update that changes no aura reads nothing")

  -- not knowing is never "not Well Fed"
  AURAS.error = true
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == nil and not Shown(), "an error from the game is unknown, and does not show")
  AURAS.error = nil
  AURAS.secret = true
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == nil and not Shown(), "a secret answer is unknown, and does not show")
  AURAS.secret = nil
  HIDDEN = true
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == nil and not Shown(), "auras hidden from addons are unknown, and do not show")
  HIDDEN = false
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == false and Shown(), "back to normal")
  local keep = c.C_UnitAuras
  c.C_UnitAuras = nil
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == nil and not Shown(), "no way to ask is unknown")
  c.C_UnitAuras = keep

  -- more auras than are looked at, none of them Well Fed: a guess, so unknown
  local many = {}
  for i = 1, 45 do many[i] = { spellId = 100 + i, name = "Buff " .. i } end
  local saved = {}
  for k, v in pairs(AURAS) do saved[k] = v; AURAS[k] = nil end
  for i, a in ipairs(many) do AURAS[i] = a end
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == nil, "a list longer than what is looked at, without Well Fed in it, is unknown")
  AURAS[3] = { spellId = 18125, name = "Well Fed" }
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()
  Check(Obs() == true, "but Well Fed found inside it is found")
  for k in pairs(AURAS) do AURAS[k] = nil end
  for k, v in pairs(saved) do AURAS[k] = v end
  Fire("UNIT_AURA", "player", { isFullUpdate = true }); Settle()

  -- Peek (the settings window's look at a reminder that isn't running)
  Check(ST.Peek(RM.Get(ID)).wellFed == false, "a peek reads it into a table of its own")

  -- Reminders off: nothing kept, nothing listened for
  c.TwichUIDB.modules.reminders = false
  CT.Refresh(); Settle()
  Check(not Shown() and Obs() == nil, "Reminders off: nothing shows and the value is forgotten")
  Check(not ST.Registered("UNIT_AURA"), "and UNIT_AURA is no longer listened for")
end

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
