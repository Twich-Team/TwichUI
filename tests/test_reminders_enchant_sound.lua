-- Reminders: the "Weapon enchant" condition (reminders/Conditions.lua, State.lua's "enchant" source) and a reminder's
-- optional sound (Config.lua's sound field, Controller.lua's playing of it). A fake world stands in for the game's
-- equipment and sound, so this checks our logic, not the game: the in-game checks are in docs/reminders.md.
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
  RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
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
local P = C.Get("weaponEnchant")

local function Cond(hand, what) return { type = "weaponEnchant", hand = hand, what = what } end
local function Eval(hand, what, state)
  local clean = assert(C.Check(Cond(hand, what)))
  return P.Evaluate(clean, state ~= false and { enchant = { [hand] = state } } or {})
end

---------------------------------------------------------------------------
-- 1. The condition: every state, both questions, and unknown never matching
---------------------------------------------------------------------------
do
  Check(P, "the kind is registered")
  Check((Eval("mainHand", "missing", "bare")) == MATCH, "missing: a weapon with none")
  Check((Eval("mainHand", "missing", "enchanted")) == NOMATCH, "missing: a weapon that has one")
  Check((Eval("mainHand", "missing", "noWeapon")) == NOMATCH, "missing: never true when there is nothing to enchant")
  Check((Eval("mainHand", "applied", "enchanted")) == MATCH, "applied: a weapon that has one")
  Check((Eval("mainHand", "applied", "bare")) == NOMATCH, "applied: a weapon with none")
  Check((Eval("mainHand", "applied", "noWeapon")) == NOMATCH, "applied: nothing to enchant")
  for _, what in ipairs({ "missing", "applied" }) do
    local result, why = Eval("offHand", what, nil)
    Check(result == UNKNOWN and type(why) == "string", what .. ": unread is unknown, with a reason")
    Check((Eval("offHand", what, false)) == UNKNOWN, what .. ": no enchant observation at all is unknown")
  end
  -- the other hand's state is not this hand's
  local clean = assert(C.Check(Cond("offHand", "missing")))
  Check(P.Evaluate(clean, { enchant = { mainHand = "bare" } }) == UNKNOWN, "a hand reads its own state only")

  local needs = {}
  P.Needs(clean, function(k) needs[#needs + 1] = k end)
  Check(#needs == 1 and needs[1] == "enchant", "it reads the enchant observation")

  -- words
  Check(P.Summary(assert(C.Check(Cond("mainHand", "missing")))) == "Main hand weapon has no temporary enchant", "summary: " .. P.Summary(assert(C.Check(Cond("mainHand", "missing")))))
  Check(P.Summary(assert(C.Check(Cond("offHand", "applied")))) == "Off hand weapon has a temporary enchant", "summary, applied")
  local m = assert(C.Check(Cond("mainHand", "missing")))
  Check(P.Observed(m, { enchant = { mainHand = "bare" } }) == "No temporary enchant", "saw: bare")
  Check(P.Observed(m, { enchant = { mainHand = "enchanted" } }) == "Has a temporary enchant", "saw: enchanted")
  Check(P.Observed(m, { enchant = { mainHand = "noWeapon" } }) == "No weapon that can take one", "saw: nothing to enchant")
  Check(P.Observed(m, {}) == "Not read yet", "saw: nothing")

  -- the Test section: the one it looks for first, and every scenario produces the answer its label says
  local sc = P.Scenarios(m)
  Check(sc[1].key == "bare" and sc[#sc].key == "unread", "scenarios: its own first, unread last")
  local want = { bare = MATCH, enchanted = NOMATCH, noWeapon = NOMATCH, unread = UNKNOWN }
  for _, s in ipairs(sc) do
    local obs = {}
    s.Apply(obs)
    Check(P.Evaluate(m, obs) == want[s.key], "scenario " .. s.key)
  end
  Check(P.Scenarios(assert(C.Check(Cond("mainHand", "applied"))))[1].key == "enchanted", "scenarios for applied start on enchanted")
end

---------------------------------------------------------------------------
-- 2. Stored form
---------------------------------------------------------------------------
do
  local clean = C.Check({ type = "weaponEnchant", hand = "offHand", what = "applied", negate = true, extra = 1 })
  Check(clean and clean.hand == "offHand" and clean.what == "applied" and clean.negate == nil and clean.extra == nil, "only its own fields are kept")
  Check(C.Check(clean).hand == "offHand", "round trip")
  Check(select(1, C.Check({ type = "weaponEnchant", hand = "ranged", what = "missing" })) == nil, "a hand it doesn't know is refused")
  Check(select(1, C.Check({ type = "weaponEnchant", hand = "mainHand", what = "sideways" })) == nil, "a question it doesn't know is refused")
  Check(select(1, C.Check({ type = "weaponEnchant", hand = "mainHand" })) == nil, "no question is refused")
  Check(select(1, C.Check({ type = "weaponEnchant" })) == nil, "nothing chosen is refused")
  local new = P.New()
  Check(new.hand == "mainHand" and new.what == "missing", "a new one asks about the main hand having none")

  -- the plain words and the editor's fields
  local sentence = Pl.CondSentence(new)
  Check(sentence == "Your main hand weapon has no temporary enchant", "sentence: " .. tostring(sentence))
  Check(not Pl.HasOperator(new) and not Pl.NeedsItem(new), "no is/is-not choice and no item")
  local subject, label = Pl.SubjectOf(new)
  Check(subject == "enchant:mainHand" and label == "Main hand weapon enchant", "its subject: " .. tostring(subject))
  local off = Pl.WithSubject(new, "enchant:offHand")
  Check(off.type == "weaponEnchant" and off.hand == "offHand" and off.what == "missing" and new.hand == "mainHand", "changing the hand makes a new condition and keeps the question")
  local applied = Pl.WithValue(off, "applied")
  Check(applied.what == "applied" and off.what == "missing" and applied.hand == "offHand", "changing the question never edits the one given")
  Check(Pl.WithSubject(applied, "enchant:mainHand").what == "applied", "the question survives a change of hand")
  Check(Pl.WithSubject(new, "enchant:ranged") == nil, "an unknown hand makes nothing")
  local equip = Pl.WithSubject(new, "slot:head")
  Check(equip and equip.type == "equipment" and equip.slot == "head", "and the subject can change to an equipment slot")
  local choices = Pl.ValueChoices(new)
  Check(#choices == 3 and choices[1].value == "missing" and choices[2].value == "applied" and choices[3].value == "expiring", "three questions to choose from (running out is the third)")
  Check(Pl.ValueLabel(new) == "Has no temporary enchant", "value label: " .. Pl.ValueLabel(new))
  local found
  for _, e in ipairs(Pl.Entries()) do if e.kind == "weaponEnchant" then found = e end end
  Check(found and found.category == "Equipment" and found.make().type == "weaponEnchant", "the picker offers it under Equipment")
  local subjects = {}
  for _, s in ipairs(Pl.Subjects()) do subjects[s.value] = true end
  Check(subjects["enchant:mainHand"] and subjects["enchant:offHand"], "the subject choices list both hands")
  Check(#Pl.Help(new) > 20, "it has help text")
end

---------------------------------------------------------------------------
-- 3. The source: reading the hands, and staying current
---------------------------------------------------------------------------
c.TwichUIDB.ui = c.TwichUIDB.ui or {}
local ID = "r1"
c.TwichUIDB.ui.reminders = { version = 1, nextId = 2, list = { { id = ID, name = "Oil", enabled = true, match = "all",
  conditions = { { type = "weaponEnchant", hand = "mainHand", what = "missing" } },
  display = { mode = "text", text = "Apply your oil" }, sound = "TwichUI Notification" } } }
EQ[16] = 100
RM.Invalidate()
CT.Refresh()
Fire("PLAYER_ENTERING_WORLD"); Settle()
local function Shown() local f = D.Frame(ID) return f ~= nil and f.shown end
local function Obs() return ST.Observations().enchant end

do
  Check(RM.Get(ID).valid, "the reminder is valid")
  Check(ST.Registered("WEAPON_ENCHANT_CHANGED") and ST.Registered("WEAPON_SLOT_CHANGED") and ST.Registered("PLAYER_EQUIPMENT_CHANGED"), "it listens for enchant and weapon changes")
  Check(Obs() and Obs().mainHand == "bare" and Obs().offHand == "noWeapon", "a sword with nothing on it; an empty off hand has nothing to enchant")
  Check(Shown(), "so the reminder shows")

  ENCH[0] = true
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Obs().mainHand == "enchanted" and not Shown(), "an oil goes on: it goes away")

  ENCH[0] = false
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Obs().mainHand == "bare" and Shown(), "the oil runs out: it comes back")

  EQ[16] = 102
  Fire("PLAYER_EQUIPMENT_CHANGED", 16); Settle()
  Check(Obs().mainHand == "noWeapon" and not Shown(), "a fishing pole takes no oil")
  EQ[16] = 100
  Fire("PLAYER_EQUIPMENT_CHANGED", 16); Settle()
  Check(Obs().mainHand == "bare" and Shown(), "the sword is back")

  EQ[17] = 101
  Fire("PLAYER_EQUIPMENT_CHANGED", 17); Settle()
  Check(Obs().offHand == "noWeapon", "a shield takes no oil")
  EQ[17] = 103
  Fire("PLAYER_EQUIPMENT_CHANGED", 17); Settle()
  Check(Obs().offHand == "noWeapon", "nor does an item held in the off hand")
  EQ[17] = 100
  Fire("PLAYER_EQUIPMENT_CHANGED", 17); Settle()
  Check(Obs().offHand == "bare", "a second weapon can")
  ENCH[1] = true
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Obs().offHand == "enchanted" and Obs().mainHand == "bare", "each hand has its own answer")
  ENCH[1] = nil
  EQ[17] = nil
  Fire("PLAYER_EQUIPMENT_CHANGED", 17); Settle()

  -- other equipment is not this source's business
  local before = CALLS.enchant
  Fire("PLAYER_EQUIPMENT_CHANGED", 5); Settle()
  Check(CALLS.enchant == before, "a chest piece change reads nothing")
  Settle(); Settle()
  Check(CALLS.enchant == before, "no polling: nothing is read without an event")

  -- not knowing is never "bare"
  EQ[16] = 999   -- an item the game has no details for
  Fire("PLAYER_EQUIPMENT_CHANGED", 16); Settle()
  Check(Obs().mainHand == nil and not Shown(), "an item without details is unknown, and does not show")
  EQ[16] = 100
  ENCH.secret = true
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Obs().mainHand == nil and not Shown(), "a secret answer is unknown, and does not show")
  ENCH.secret = nil
  local keep = c.C_Item.GetWeaponEnchantInfo
  c.C_Item.GetWeaponEnchantInfo = nil
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Obs().mainHand == nil and not Shown(), "no way to ask is unknown")
  c.C_PaperDollInfo = { GetTemporaryEnchantmentInfo = function(slot) if slot == 16 then return ENCH.paper and { enchantID = 1 } or nil end end }
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Obs().mainHand == "bare" and Shown(), "the older question is used when the newer one isn't there")
  ENCH.paper = true
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Obs().mainHand == "enchanted" and not Shown(), "and answers the same way")
  ENCH.paper = nil
  c.C_PaperDollInfo = nil
  c.C_Item.GetWeaponEnchantInfo = keep
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Obs().mainHand == "bare" and Shown(), "back to normal")

  -- Peek (the settings window's look at a reminder that isn't running)
  Check(ST.Peek(RM.Get(ID)).enchant.mainHand == "bare", "a peek reads it into a table of its own")
end

---------------------------------------------------------------------------
-- 4. The sound: stored form
---------------------------------------------------------------------------
do
  Check(RM.ValidSound("Fallen Toll") and RM.ValidSound("a"), "a name is a sound")
  Check(not RM.ValidSound("") and not RM.ValidSound("   ") and not RM.ValidSound(nil) and not RM.ValidSound(5) and not RM.ValidSound({}), "nothing, blanks and non-text are not")
  Check(not RM.ValidSound("a|cffff0000b") and not RM.ValidSound("a\nb") and not RM.ValidSound(("x"):rep(101)), "markup, control characters and long names are not")
  Check(RM.Get(ID).sound == "TwichUI Notification", "the view reads it")

  local ok = RM.SetSound(ID, "Fallen Toll")
  Check(ok and c.TwichUIDB.ui.reminders.list[1].sound == "Fallen Toll" and RM.Get(ID).sound == "Fallen Toll", "set")
  Check(RM.SetSound(ID, "Fallen Toll") == true, "setting the same again is fine")
  local ok2, why = RM.SetSound(ID, "bad|name")
  Check(ok2 == false and type(why) == "string" and c.TwichUIDB.ui.reminders.list[1].sound == "Fallen Toll", "a bad name is refused and changes nothing")
  Check(RM.SetSound("r99", "Fallen Toll") == false, "an unknown reminder is refused")
  Check(RM.SetSound(ID, nil) and c.TwichUIDB.ui.reminders.list[1].sound == nil and RM.Get(ID).sound == nil, "cleared")

  -- a stored value that can't be used reads as none and is left as saved
  c.TwichUIDB.ui.reminders.list[1].sound = "bad|name"
  RM.Invalidate()
  Check(RM.Get(ID).sound == nil and RM.Get(ID).valid and c.TwichUIDB.ui.reminders.list[1].sound == "bad|name", "an unusable sound reads as none, is kept as saved, and is not a problem")
  c.TwichUIDB.ui.reminders.list[1].sound = 42
  RM.Invalidate()
  Check(RM.Get(ID).sound == nil, "a number is not a sound")

  -- told once, as a "sound" change, and a copy keeps it
  RM.SetSound(ID, "Fallen Toll")
  local told = {}
  RM.Subscribe(function(id, what) told[#told + 1] = tostring(id) .. ":" .. tostring(what) end)
  RM.SetSound(ID, "Single Knell")
  Check(#told == 1 and told[1] == ID .. ":sound", "told once: " .. table.concat(told, ","))
  local ok3, copyId = RM.Duplicate(ID)
  Check(ok3 and RM.Get(copyId).sound == "Single Knell" and RM.Get(copyId).enabled == false, "a copy keeps the sound and starts turned off")
  RM.Delete(copyId)

  -- the template
  local made, tid = RM.Create("enchant")
  local tv = made and RM.Get(tid)
  Check(tv and tv.valid and tv.enabled == false and tv.sound == nil, "the template makes a valid reminder, turned off, with no sound")
  Check(tv and #tv.leaves == 1 and tv.leaves[1].cond.type == "weaponEnchant" and tv.leaves[1].cond.what == "missing", "asking about the main hand having none")
  if made then RM.Delete(tid) end
  RM.SetSound(ID, "TwichUI Notification")
end

---------------------------------------------------------------------------
-- 5. The sound: when it plays
---------------------------------------------------------------------------
do
  local function Plays() return #PLAYED end
  local function Stats() return CT.Snapshot() end

  -- start from a known place: reminder off, then on with the conditions true
  RM.SetEnabled(ID, false); Settle()
  for k in pairs(PLAYED) do PLAYED[k] = nil end
  NOW = NOW + 100
  ENCH[0] = false
  RM.SetEnabled(ID, true); Settle()
  Check(Shown() and Plays() == 1, "it appears and sounds once: " .. Plays())
  Check(PLAYED[1] and PLAYED[1].channel == "SFX" and PLAYED[1].path:find("TwichUI_Notification", 1, true), "on the sound-effects channel, the sound that was chosen")

  -- staying up, deciding again, a loading screen, a settings change: no more sound
  Fire("PLAYER_ENTERING_WORLD"); Settle()
  Fire("PLAYER_EQUIPMENT_CHANGED", 16); Settle()
  RM.SetDisplay(ID, "opacity", 80); Settle()
  CT.Refresh(); Settle()
  Check(Shown() and Plays() == 1, "while it stays up it doesn't sound again: " .. Plays())

  -- changing the sound while it is up doesn't play it either
  RM.SetSound(ID, "Fallen Toll"); Settle()
  Check(Plays() == 1, "choosing another sound plays nothing by itself")

  -- gone and back: sounds again (outside the gap)
  NOW = NOW + 30
  ENCH[0] = true
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(not Shown() and Plays() == 1, "going away makes no sound")
  NOW = NOW + 30
  ENCH[0] = false
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Shown() and Plays() == 2 and PLAYED[2].path:find("Fallen_Toll", 1, true), "coming back sounds again, with the new sound")

  -- a reminder that flaps is held to one sound per gap
  local held = Stats().soundsHeld
  ENCH[0] = true
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  NOW = NOW + 0.5
  ENCH[0] = false
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Shown() and Plays() == 2 and Stats().soundsHeld == held + 1, "back within the gap: held, and counted")
  ENCH[0] = true
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  NOW = NOW + 5
  ENCH[0] = false
  Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Shown() and Plays() == 3, "after the gap it sounds again")

  -- no sound chosen: nothing plays
  RM.SetSound(ID, nil)
  NOW = NOW + 30
  ENCH[0] = true; Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  NOW = NOW + 30
  ENCH[0] = false; Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Shown() and Plays() == 3, "no sound chosen, no sound")

  -- a sound that isn't installed plays nothing and is counted
  RM.SetSound(ID, "No Such Sound")
  local missing = Stats().soundsMissing
  NOW = NOW + 30
  ENCH[0] = true; Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  NOW = NOW + 30
  ENCH[0] = false; Fire("WEAPON_ENCHANT_CHANGED"); Settle()
  Check(Shown() and Plays() == 3 and Stats().soundsMissing == missing + 1, "a sound that has gone plays nothing")
  local ok, why = CT.PlaySound("No Such Sound")
  Check(ok == false and why == "missing", "and says why for the Play button")
  ok, why = CT.PlaySound(nil)
  Check(ok == false and why == "none", "no sound says so")
  ok = CT.PlaySound("Fallen Toll")
  Check(ok == true and Plays() == 4, "the Play button plays it")
  c.PlaySoundFile = function() return false end
  ok, why = CT.PlaySound("Fallen Toll")
  Check(ok == false and why == "refused", "a game that refuses is said so")
  c.PlaySoundFile = function(path, channel) PLAYED[#PLAYED + 1] = { path = path, channel = channel }; return true end

  -- a preview never sounds
  RM.SetSound(ID, "Fallen Toll")
  local n = Plays()
  D.PreviewStart(RM.Get(ID), false)
  Settle()
  D.PreviewStop(); Settle()
  Check(Plays() == n, "a preview makes no sound")

  -- an unknown condition keeps it hidden and silent, and it sounds when the answer arrives
  NOW = NOW + 30
  EQ[16] = 999
  Fire("PLAYER_EQUIPMENT_CHANGED", 16); Settle()
  Check(not Shown() and Plays() == n, "unknown: hidden and silent")
  EQ[16] = 100
  Fire("PLAYER_EQUIPMENT_CHANGED", 16); Settle()
  Check(Shown() and Plays() == n, "known again: it appears again, without a second sound for the same stretch")

  -- turned off and on again with the conditions still true: it sounds again
  NOW = NOW + 30
  RM.SetEnabled(ID, false); Settle()
  Check(not Shown(), "turned off")
  RM.SetEnabled(ID, true); Settle()
  Check(Shown() and Plays() == n + 1, "turned on again: it appears and sounds")

  -- Reminders switched off and on
  NOW = NOW + 30
  c.TwichUIDB.modules.reminders = false
  CT.Refresh(); Settle()
  Check(not Shown(), "Reminders off")
  c.TwichUIDB.modules.reminders = true
  CT.Refresh(); Settle()
  Check(Shown() and Plays() == n + 2, "Reminders on again: it appears and sounds")

  -- The Quiet screen switch (QuietScreen.lua): the frame goes away and comes back with the switch, and it is silent
  -- meanwhile, also for one that appears during the quiet, which does not sound afterwards either.
  do
    local before = Plays()
    R.QuietScreen.Set(true); Settle()
    Check(not Shown() and Plays() == before, "quiet: the shown reminder goes away")
    NOW = NOW + 30
    c.TwichUIDB.modules.reminders = false
    CT.Refresh(); Settle()
    c.TwichUIDB.modules.reminders = true
    CT.Refresh(); Settle()
    Check(not Shown() and Plays() == before, "quiet: it appears again to the controller but not on screen, and makes no sound")
    Check(CT.Snapshot().soundsQuiet >= 1, "quiet: the silenced sound is counted")
    R.QuietScreen.Set(false); Settle()
    Check(Shown() and Plays() == before, "quiet off: it is back on screen, without a sound for what appeared meanwhile")
  end

  -- the diagnostics counts exist and are numbers
  local snap = CT.Snapshot()
  Check(type(snap.sounds) == "number" and snap.sounds >= 4 and type(snap.soundsHeld) == "number" and type(snap.soundsRefused) == "number", "the counts are kept")
end

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
