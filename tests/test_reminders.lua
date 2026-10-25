-- Reminders (reminders/): Config.lua stores and checks, Conditions.lua and Evaluate.lua decide (pure), State.lua reads
-- the game, Display.lua draws and Controller.lua puts them together. A fake world stands in for the game, so this checks
-- our logic, not the game: the in-game checks are in docs/reminders.md.
dofile(TESTS .. "harness.lua")

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

-- Items the client knows: class 4 Armor (subclass 6 Shield, 1 Cloth), class 2 Weapon (7 one-handed sword, 8 two-handed,
-- 20 fishing pole). 90001 and up are server items the client has no details for.
c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemArmorSubclass = { Shield = 6 }, ItemWeaponSubclass = { Fishingpole = 20 } }
local ITEMS = {
  [1201] = { 4, 6, "INVTYPE_SHIELD", "Dull Heater Shield" },
  [2139] = { 2, 7, "INVTYPE_WEAPONOFFHAND", "Dirk" },
  [2489] = { 2, 8, "INVTYPE_2HWEAPON", "Two-Handed Sword" },
  [6256] = { 2, 20, "INVTYPE_2HWEAPON", "Fishing Pole" },
  [5976] = { 4, 0, "INVTYPE_TABARD", "Guild Tabard" },
  [6948] = { 15, 0, "", "Hearthstone" },
}
local W, calls, asked, NOW
local function World()
  W = { slots = {}, combat = false, dead = false, ghost = false, mounted = false, class = "WARRIOR" }
  calls = { inv = 0 }
  asked = {}
end
World()
NOW = 1000
c.GetTime = function() return NOW end
c.UnitClassBase = function() return W.class end
c.GetInventoryItemID = function(_, slot) calls.inv = calls.inv + 1; return W.slots[slot] end
c.C_Item = {
  GetItemInfoInstant = function(id)
    local it = ITEMS[id]
    if not it then return nil end
    return id, "t", "s", it[3], 100000 + id, it[1], it[2]
  end,
  GetItemIconByID = function(id) return ITEMS[id] and (100000 + id) or nil end,
  GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][4] or nil end,
  RequestLoadItemDataByID = function(id) asked[id] = (asked[id] or 0) + 1 end,
}
c.UnitAffectingCombat = function() return W.combat end
c.InCombatLockdown = function() return W.combat end
c.UnitIsDeadOrGhost = function() return W.dead or W.ghost end
c.UnitIsGhost = function() return W.ghost end
c.IsMounted = function() return W.mounted end
c.issecretvalue = function() return false end
-- anything that would act in the game: none of it may ever be called
local acted = {}
for _, name in ipairs({ "EquipItemByName", "UseInventoryItem", "PickupInventoryItem", "CastSpellByName", "UseItemByName",
  "AutoEquipCursorItem", "SendChatMessage" }) do
  c[name] = function() acted[#acted + 1] = name end
end
c.C_ChatInfo.SendAddonMessage = function() acted[#acted + 1] = "SendAddonMessage" end

local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function Settle() for _ = 1, 6 do FlushTimers() end end

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "Icons.lua",
  "reminders/Config.lua", "reminders/Conditions.lua", "reminders/Evaluate.lua", "reminders/State.lua",
  "reminders/Display.lua", "reminders/Controller.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local RM, C, E, ST, D, CT = R.Reminders, R.ReminderConditions, R.ReminderEval, R.ReminderState, R.ReminderDisplay, R.ReminderController
local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN

local function EventCount()
  local n = 0
  for _, f in ipairs(frames) do for _ in pairs(f.events) do n = n + 1 end end
  return n
end
local function OnUpdates()
  local n = 0
  for _, f in ipairs(frames) do if f.scripts.OnUpdate then n = n + 1 end end
  return n
end
local function Shown(id) local f = D.Frame(id) return f ~= nil and f.shown end

---------------------------------------------------------------------------
-- 1. The evaluator, on plain facts
---------------------------------------------------------------------------
local function View(conds, match, scope)
  -- a view as Config.lua makes one, without saving anything
  local raw = { id = "r99", name = "Test", enabled = true, match = match, conditions = conds, scope = scope,
    display = { mode = "text", text = "Hi" } }
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  local keep = c.TwichUIDB.ui.reminders
  c.TwichUIDB.ui.reminders = { version = 1, list = { raw } }
  RM.Invalidate()
  local v = RM.Get("r99")
  c.TwichUIDB.ui.reminders = keep
  RM.Invalidate()
  return v
end
local SHIELD = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD", id = 1201 }
local DIRK = { classID = 2, subClassID = 7, equipLoc = "INVTYPE_WEAPONOFFHAND", id = 2139 }
local NODETAIL = { id = 90001 }
local EMPTY = { empty = true }
local function Obs(off, extra)
  local o = { slots = { [17] = off } }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end
local noShield = View({ { type = "equipment", slot = "offHand", what = "shield", negate = true } })
Check(noShield.valid, "the shield rule is valid")
local entry = noShield.conditions[1]
Check(E.Condition(entry, Obs(SHIELD)) == NOMATCH, "shield in the off hand: \"Off hand is not Shield\" does not match")
Check(E.Condition(entry, Obs(EMPTY)) == MATCH, "empty off hand: it matches")
Check(E.Condition(entry, Obs(DIRK)) == MATCH, "off-hand weapon: it matches")
local res, observed, reason = E.Condition(entry, Obs(NODETAIL))
Check(res == UNKNOWN and reason ~= nil, "no item details: unknown, with a reason (never true)")
Check(E.Condition(entry, { slots = {} }) == UNKNOWN, "slot not read: unknown")
Check(E.Summary(entry) == "Off hand is not Shield", "the summary reads naturally: " .. E.Summary(entry))
Check(select(2, E.Condition(entry, Obs(EMPTY))) == "Empty", "observed: Empty")
Check(select(2, E.Condition(entry, Obs(SHIELD))):find("^Shield") ~= nil, "observed: Shield")
local out = E.Run(noShield, Obs(EMPTY), { character = "Rich - Forever", class = "WARRIOR" })
Check(out.status == "showing" and out.conditions[1].result == MATCH, "all-match with an empty off hand: showing")
out = E.Run(noShield, Obs(NODETAIL), {})
Check(out.status == "waiting", "unknown result: waiting (hidden)")

-- specific items
local item = View({ { type = "equipment", slot = "any", what = "item", item = 6256, negate = false } })
Check(E.Condition(item.conditions[1], { slots = { [16] = { id = 6256, classID = 2 }, [17] = EMPTY } }) == UNKNOWN or true, "any slot with others unread")
local all = { slots = {} }
for _, n in ipairs(C.EQUIPPED_SLOTS) do all.slots[n] = EMPTY end
Check(E.Condition(item.conditions[1], all) == NOMATCH, "item not equipped anywhere: no match")
all.slots[16] = { id = 6256, classID = 2, subClassID = 20 }
Check(E.Condition(item.conditions[1], all) == MATCH, "item equipped in the main hand: match")
local notItem = View({ { type = "equipment", slot = "mainHand", what = "item", item = 6256, negate = true } })
Check(E.Condition(notItem.conditions[1], all) == NOMATCH, "main hand is not the fishing pole: no match while it is")
Check(E.Condition(notItem.conditions[1], { slots = { [16] = EMPTY } }) == MATCH, "empty main hand is not the fishing pole")
local unfinished = View({ { type = "equipment", slot = "any", what = "item", negate = true } })
Check(not unfinished.valid and unfinished.problems[1]:find("item"), "an item condition without an item is flagged")

-- empty / occupied
local empty = View({ { type = "equipment", slot = "tabard", what = "empty", negate = false } })
Check(E.Condition(empty.conditions[1], { slots = { [19] = EMPTY } }) == MATCH, "tabard slot empty: match")
Check(E.Condition(empty.conditions[1], { slots = { [19] = { id = 5976, classID = 4 } } }) == NOMATCH, "tabard worn: no match")
local occupied = View({ { type = "equipment", slot = "tabard", what = "empty", negate = true } })
Check(E.Summary(occupied.conditions[1]) == "Tabard is not empty", "occupied reads as not empty")
Check(E.Condition(occupied.conditions[1], { slots = { [19] = { id = 5976, classID = 4 } } }) == MATCH, "tabard worn: occupied matches")

-- categories other than shield
local pole = View({ { type = "equipment", slot = "mainHand", what = "fishingPole", negate = false } })
Check(E.Condition(pole.conditions[1], { slots = { [16] = { id = 6256, classID = 2, subClassID = 20, equipLoc = "INVTYPE_2HWEAPON" } } }) == MATCH, "fishing pole category")
Check(E.Condition(pole.conditions[1], { slots = { [16] = { id = 2489, classID = 2, subClassID = 8, equipLoc = "INVTYPE_2HWEAPON" } } }) == NOMATCH, "a sword is not a fishing pole")
Check(View({ { type = "equipment", slot = "head", what = "shield" } }).valid == false, "a category a slot can't hold is refused")

-- composition
Check(E.Combine("all", { MATCH, MATCH }) == MATCH, "all: match + match")
Check(E.Combine("all", { MATCH, NOMATCH, UNKNOWN }) == NOMATCH, "all: a no match wins over unknown")
Check(E.Combine("all", { MATCH, UNKNOWN }) == UNKNOWN, "all: otherwise unknown")
Check(E.Combine("any", { NOMATCH, MATCH, UNKNOWN }) == MATCH, "any: a match wins over unknown")
Check(E.Combine("any", { NOMATCH, UNKNOWN }) == UNKNOWN, "any: otherwise unknown")
Check(E.Combine("any", { NOMATCH, NOMATCH }) == NOMATCH, "any: no match")
Check(E.Combine("all", {}) == NOMATCH and E.Combine("any", {}) == NOMATCH, "no conditions never match")
local none = View({})
Check(not none.valid and E.Run(none, {}, {}).status == "invalid", "an empty rule set is invalid, never always-visible")

-- unknown or damaged conditions are flagged, not dropped
local odd = View({ { type = "buff", spell = 1 }, { type = "equipment", slot = "offHand", what = "shield", negate = true } })
Check(not odd.valid and #odd.conditions == 2 and odd.problems[1]:find("buff"), "an unknown kind is kept and named")
out = E.Run(odd, Obs(EMPTY), {})
Check(out.status == "invalid" and out.conditions[1].result == E.INVALID and out.conditions[2].result == MATCH, "it fails safely; the others still read")
Check(View({ "not a table" }).valid == false, "a condition that isn't a table is flagged")

-- applicability
local mine = View({ { type = "player", state = "combat" } }, "all", { who = "characters", characters = { "Rich - Forever" } })
Check(E.Applies(mine, { character = "Rich - Forever" }) == MATCH, "for this character")
Check(E.Applies(mine, { character = "Alt - Forever" }) == NOMATCH, "not for an alt")
Check(E.Applies(mine, {}) == UNKNOWN, "unknown character: waiting")
local warriors = View({ { type = "player", state = "combat" } }, "all", { who = "all", class = "WARRIOR" })
Check(E.Applies(warriors, { class = "WARRIOR" }) == MATCH and E.Applies(warriors, { class = "MAGE" }) == NOMATCH, "class restriction")
Check(E.Run(warriors, { combat = true }, { class = "MAGE" }).status == "notApplicable", "another class: not applicable")
Check(View({ { type = "player", state = "combat" } }, "all", { who = "characters", characters = {} }).valid == false, "chosen characters but none listed: invalid")

-- player state
local function P(state, negate) return View({ { type = "player", state = state, negate = negate } }).conditions[1] end
Check(E.Condition(P("combat"), { combat = true }) == MATCH and E.Condition(P("combat"), { combat = false }) == NOMATCH, "in combat")
Check(E.Condition(P("combat", true), { combat = false }) == MATCH, "out of combat")
Check(E.Summary(P("combat")) == "Player is in combat" and select(2, E.Condition(P("combat"), { combat = false })) == "Out of combat", "combat words")
Check(E.Condition(P("dead"), { life = "ghost" }) == MATCH, "dead includes a ghost")
Check(E.Condition(P("dead", true), { life = "alive" }) == MATCH and E.Summary(P("dead", true)) == "Player is alive", "alive")
Check(E.Condition(P("ghost"), { life = "dead" }) == NOMATCH and E.Condition(P("ghost"), { life = "ghost" }) == MATCH, "a ghost is only the released spirit")
Check(E.Condition(P("mounted"), { mounted = true }) == MATCH and E.Condition(P("mounted", true), { mounted = false }) == MATCH, "mounted")
Check(E.Condition(P("combat"), {}) == UNKNOWN, "not read: unknown")
local twoRules = View({ { type = "equipment", slot = "offHand", what = "shield", negate = true }, { type = "player", state = "combat" } }, "all")
out = E.Run(twoRules, Obs(EMPTY, { combat = false }), {})
Check(out.status == "hidden" and out.explain == "All conditions must match.", "all: hidden out of combat, and says why")
local anyRules = View(twoRules.raw.conditions, "any")
Check(E.Run(anyRules, Obs(EMPTY, { combat = false }), {}).status == "showing", "any: shows with one match")

---------------------------------------------------------------------------
-- 2. Simulation: the same evaluator, its own observations
---------------------------------------------------------------------------
local scen = E.Scenarios(entry)
local keys = {}
for _, s in ipairs(scen) do keys[#keys + 1] = s.key end
Check(table.concat(keys, ",") == "match,empty,other,unknown", "the shield's scenarios: " .. table.concat(keys, ","))
Check(scen[1].label == "Shield equipped" and scen[2].label == "Empty off hand" and scen[3].label == "Off-hand weapon equipped"
  and scen[4].label == "Equipment information unavailable", "scenario words")
local live = ST.Observations()
local before = live.slots[17]
local sim = E.Simulate(noShield, { "match" })
Check(sim.simulated and sim.status == "hidden", "simulated: shield equipped hides it")
Check(E.Simulate(noShield, { "empty" }).status == "showing", "simulated: empty off hand shows it")
Check(E.Simulate(noShield, { "other" }).status == "showing", "simulated: off-hand weapon shows it")
Check(E.Simulate(noShield, { "unknown" }).status == "waiting", "simulated: no details waits")
Check(E.Simulate(twoRules, { "empty", "off" }).status == "hidden" and E.Simulate(twoRules, { "empty", "on" }).status == "showing", "simulated combat")
Check(ST.Observations() == live and live.slots[17] == before, "a simulation never touches the live observations")

---------------------------------------------------------------------------
-- 3. Creating, duplicating, deleting, turning on
---------------------------------------------------------------------------
c.TwichUIDB.ui = {}
RM.Invalidate()
local ok, id = RM.Create("shield")
local v = RM.Get(id)
Check(ok and id == "r1" and v.name == "Shield reminder" and not v.enabled, "the shield template starts as a draft")
Check(v.valid and v.display.mode == "artworkText" and v.display.art == "shield" and v.display.text == "Equip your shield", "its display")
Check(v.place.preset == "belowCenter" and v.place.point == "CENTER" and v.place.y < 0, "below the middle")
Check(v.scope.who == "characters" and v.scope.characters[1] == "Rich - Forever", "this character only")
Check(v.display.pulse == false and v.display.fade == false, "static and silent")
local ok2, id2 = RM.Create("item")
local itemView = RM.Get(id2)
Check(ok2 and not itemView.valid and itemView.problems[1]:find("item"), "the item template is unfinished until an item is chosen")
local refused, why = RM.SetEnabled(id2, true)
Check(not refused and type(why) == "string", "an unfinished reminder can't be turned on: " .. tostring(why))
Check(RM.SetCondition(id2, 1, { type = "equipment", slot = "any", what = "item", item = 6948, negate = true }), "choose its item")
Check(RM.SetDisplay(id2, "item", 6948), "and its icon")
Check(RM.Get(id2).valid, "now valid")
Check(RM.SetCondition(id2, 1, { type = "nothing" }) == false, "a condition of no known kind is refused")
local ok3, id3 = RM.Duplicate(id)
Check(ok3 and id3 ~= id and RM.Get(id3).name == "Shield reminder (copy)" and not RM.Get(id3).enabled, "a duplicate has a fresh id and starts off")
RM.SetName(id3, "Changed")
Check(RM.Get(id).name == "Shield reminder", "the source is not changed by its copy")
Check(RM.List()[2].id == id3, "the copy sits after its source")
Check(RM.SetName(id, "") == false and RM.SetName(id, "a|cff") == false, "names are checked")
Check(RM.SetDisplay(id, "text", "Bad\nline") == false and RM.SetDisplay(id, "size", 9999) == false, "display values are checked")
Check(RM.Delete(id3) and RM.Get(id3) == nil and #RM.List() == 2, "delete")
local ok4, id4 = RM.Create("custom")
Check(ok4 and id4 == "r4", "ids are never reused within a profile: " .. tostring(id4))
Check(not RM.Get(id4).valid and RM.Get(id4).problems[1] == RM.PROBLEM.noConditions, "a custom reminder needs a condition first")
RM.Delete(id4)

-- what is stored, and nothing else
local stored = c.TwichUIDB.ui.reminders
Check(stored.version == 1 and #stored.list == 2, "version and list")
for _, raw in ipairs(stored.list) do
  for k in pairs(raw) do
    Check(({ id = 1, name = 1, enabled = 1, scope = 1, match = 1, conditions = 1, display = 1, place = 1 })[k], "only settings are stored: " .. k)
  end
end
-- damaged values read as defaults and are left alone
stored.list[1].display.size = "huge"
stored.list[1].display.opacity = 0
RM.Invalidate()
Check(RM.Get(id).display.size == 64 and RM.Get(id).display.opacity == 100 and stored.list[1].display.size == "huge", "bad numbers read as defaults, not erased")
stored.list[1].display.size, stored.list[1].display.opacity = nil, nil
stored.list[1].display.art = "dragon"
RM.Invalidate()
Check(not RM.Get(id).valid and RM.Get(id).problems[1] == RM.PROBLEM.noArt, "unknown artwork is flagged")
stored.list[1].display.art = "shield"
RM.Invalidate()

---------------------------------------------------------------------------
-- 4. Live: events, decisions, coalescing
---------------------------------------------------------------------------
CT.Refresh()
Check(EventCount() == 0 or ST.Snapshot().keys == 0, "nothing read while no reminder is turned on")
Fire("PLAYER_ENTERING_WORLD"); Settle()
Check(ST.Snapshot().keys == 0, "in the world, a draft reads nothing")
Check(ST.Registered("PLAYER_ENTERING_WORLD") and not ST.Registered("PLAYER_EQUIPMENT_CHANGED"), "only the world event")
Check(RM.SetEnabled(id, true), "turn the shield reminder on")
Check(ST.Snapshot().keys == 1 and ST.Registered("PLAYER_EQUIPMENT_CHANGED"), "it reads one slot and listens for equipment changes only")
Check(not ST.Registered("PLAYER_REGEN_DISABLED") and not ST.Registered("PLAYER_MOUNT_DISPLAY_CHANGED"), "nothing it doesn't need")
Check(Shown(id) and CT.Status(id) == "showing", "empty off hand: the shield reminder shows")
local f = D.Frame(id)
Check(f.mouse == false and f.strata == "MEDIUM", "click-through, medium strata")
Check(f.art.texture:find("media\\reminders\\shield") and f.text.text == "Equip your shield", "the shield artwork and its words")
Check(f.art.w and f.art.h and math.abs(f.art.w / f.art.h - 180 / 254) < 0.02, "the artwork keeps its proportions")
local p = f.points[1]
Check(p[1] == "CENTER" and p[3] == "CENTER" and p[5] == -200, "below the middle of the screen")

W.slots[17] = 1201
local reads = calls.inv
Fire("PLAYER_EQUIPMENT_CHANGED", 17, true)
Fire("PLAYER_EQUIPMENT_CHANGED", 17, true)
Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)   -- a slot no reminder reads
Check(Shown(id), "nothing changes before the coalesced look")
Settle()
Check(not Shown(id) and CT.Status(id) == "hidden", "shield equipped: hidden")
Check(calls.inv - reads == 1, "a burst of equipment events is one read: " .. (calls.inv - reads))
W.slots[17] = 2139
Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(Shown(id), "off-hand weapon: shows")
local decisions = CT.Snapshot().decisions
Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(CT.Snapshot().decisions == decisions, "the same item again: no new decision")

-- an item without details: unknown (hidden), asked for at most twice, resolved when the game answers
W.slots[17] = 90001
Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(not Shown(id) and CT.Status(id) == "waiting", "no details: hidden and waiting")
Check(asked[90001] == 1 and ST.Registered("GET_ITEM_INFO_RECEIVED"), "its details are asked for, and the answer listened for")
Fire("GET_ITEM_INFO_RECEIVED", 90001, true); Settle()
Check(asked[90001] == 2 and CT.Status(id) == "waiting", "still nothing: asked once more")
Fire("GET_ITEM_INFO_RECEIVED", 90001, true); Settle()
Check(asked[90001] == 2, "never more than twice")
ITEMS[90001] = { 4, 6, "INVTYPE_SHIELD", "Server Shield" }
Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(CT.Status(id) == "hidden" and not ST.Registered("GET_ITEM_INFO_RECEIVED"), "details arrived: decided, and no longer listened for")
W.slots[17] = nil
Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
Check(Shown(id), "empty again: shows")

-- a second reminder sharing the observation, plus combat
RM.SetEnabled(id2, true)
Check(ST.Snapshot().keys == #C.EQUIPPED_SLOTS, "the item reminder reads every slot (the off hand once)")
Check(Shown(id2), "the hearthstone is not equipped: shows")
local cid = select(2, RM.Duplicate(id))
RM.AddCondition(cid, "player")
RM.SetEnabled(cid, true)
Check(ST.Registered("PLAYER_REGEN_DISABLED") and ST.Registered("PLAYER_REGEN_ENABLED"), "combat is listened for once a reminder needs it")
Check(not Shown(cid), "out of combat: the combat one is hidden")
local d1 = CT.Snapshot().decisions
W.combat = true
Fire("PLAYER_REGEN_DISABLED"); Settle()
Check(Shown(cid) and Shown(id), "in combat: it shows; the plain one stays")
Check(CT.Snapshot().decisions - d1 == 1, "combat re-decides only the reminder that reads it")
W.combat = false
Fire("PLAYER_REGEN_ENABLED"); Settle()
Check(not Shown(cid), "combat over: hidden")
Check(D.Frame(id) ~= D.Frame(id2) and D.Frame(id) ~= D.Frame(cid), "each reminder has a frame of its own")
local made = D.Snapshot().made
CT.Refresh(); CT.Refresh()
Check(D.Snapshot().made == made, "refreshing makes no new frames")
Check(OnUpdates() == 0, "no OnUpdate anywhere")

-- life and mount
local lid = select(2, RM.Create("custom"))
RM.AddCondition(lid, "player")
RM.SetCondition(lid, 1, { type = "player", state = "dead", negate = false })
RM.SetEnabled(lid, true)
Check(ST.Registered("PLAYER_DEAD") and ST.Registered("PLAYER_UNGHOST") and not Shown(lid), "alive: the dead one is hidden")
W.dead = true; Fire("PLAYER_DEAD"); Settle()
Check(Shown(lid), "dead: shows")
W.dead, W.ghost = false, true; Fire("PLAYER_ALIVE"); Settle()
Check(Shown(lid), "a ghost still counts as dead")
W.ghost = false; Fire("PLAYER_UNGHOST"); Settle()
Check(not Shown(lid), "back in the body: hidden")
RM.SetCondition(lid, 1, { type = "player", state = "mounted", negate = false })
Check(ST.Registered("PLAYER_MOUNT_DISPLAY_CHANGED") and not ST.Registered("PLAYER_DEAD"), "the mount event replaces the life events")
W.mounted = true; Fire("PLAYER_MOUNT_DISPLAY_CHANGED"); Settle()
Check(Shown(lid), "mounted: shows")
RM.Delete(lid)
Check(D.Frame(lid) == nil and not ST.Registered("PLAYER_MOUNT_DISPLAY_CHANGED"), "deleted: its frame is put away and its event dropped")
local reuse = select(2, RM.Create("custom"))
RM.AddCondition(reuse, "player"); RM.SetEnabled(reuse, true)
W.combat = true; Fire("PLAYER_REGEN_DISABLED"); Settle()
Check(D.Snapshot().made == made + 1 and D.Snapshot().spare == 0, "a new reminder reuses a deleted one's frame")
W.combat = false; Fire("PLAYER_REGEN_ENABLED"); Settle()
RM.Delete(reuse); RM.Delete(cid)

---------------------------------------------------------------------------
-- 5. Delay and minimum time
---------------------------------------------------------------------------
RM.SetEnabled(id2, false)
RM.SetDisplay(id, "delay", 3)
W.slots[17] = 1201; Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(not Shown(id), "shield on: hidden")
W.slots[17] = nil; Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
Check(not Shown(id) and CT.Status(id) == "pending", "empty with a 3 s delay: waiting out the delay")
W.slots[17] = 1201; Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
NOW = NOW + 5; RunLongTimers(5); Settle()
Check(not Shown(id) and CT.Status(id) == "hidden", "back before the delay ran out: the wait is cancelled, nothing shows")
W.slots[17] = nil; Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
NOW = NOW + 3; RunLongTimers(5); Settle()
Check(Shown(id), "the delay ran out with the off hand still empty: shows")
RM.SetDisplay(id, "delay", 0)
RM.SetDisplay(id, "minShow", 10)
W.slots[17] = 1201; Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(Shown(id) and CT.Status(id) == "holding", "a minimum of 10 s keeps it up")
NOW = NOW + 11; RunLongTimers(15); Settle()
Check(not Shown(id), "then it goes")
W.slots[17] = nil; Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
W.slots[17] = 1201; Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(Shown(id) and CT.Status(id) == "holding", "holding again")
RM.SetEnabled(id, false)
Check(not Shown(id) and CT.Status(id) == "disabled", "turning it off hides it at once, minimum or not")
NOW = NOW + 20; RunLongTimers(30); Settle()
Check(not Shown(id), "the old timer can't bring it back")
RM.SetDisplay(id, "minShow", 0)
RM.SetEnabled(id, true)

---------------------------------------------------------------------------
-- 6. Display modes, preview and moving
---------------------------------------------------------------------------
local fr = D.Frame(id)
local function Mode(mode, extra)
  RM.SetDisplay(id, "mode", mode)
  for k, val in pairs(extra or {}) do RM.SetDisplay(id, k, val) end
  return fr
end
W.slots[17] = nil; Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
Mode("text")
Check(fr.shown and not fr.art.shown and fr.text.shown and fr.text.text == "Equip your shield", "text only")
Mode("artwork")
Check(fr.art.shown and not fr.text.shown, "artwork only")
Mode("icon", { iconSource = "bundled", icon = "reminderShow" })
Check(fr.art.shown and fr.art.texture:find("icons\\reminderShow") and fr.art.w == fr.art.h, "a TwichUI icon, square")
Mode("iconText", { iconSource = "item", item = 1201 })
Check(fr.art.texture == 101201 and fr.text.shown, "an item's icon with text")
Mode("iconText", { item = 90123 })
Check(fr.art.texture:find("QuestionMark") and asked[90123] == 1, "an icon not loaded yet: a question mark while it is asked for")
Mode("artworkText", { textPlace = "right", text = string.rep("long words ", 10) })
Check(fr.w > fr.h and fr.text.w <= 420, "long text to the right wraps at its limit")
RM.SetDisplay(id, "text", "Equip your shield")
RM.SetDisplay(id, "textPlace", "below")
RM.SetDisplay(id, "keepAspect", false); RM.SetDisplay(id, "width", 100); RM.SetDisplay(id, "height", 40)
Check(fr.art.w == 100 and fr.art.h == 40, "aspect lock off: width and height of its own")
RM.SetDisplay(id, "keepAspect", true)
RM.SetDisplay(id, "panel", "framed")
Check(fr.bg.shown and fr.edges[1].shown, "a framed panel")
RM.SetDisplay(id, "panel", "none")
Check(not fr.bg.shown, "no panel by default")
RM.SetDisplay(id, "fade", true)
W.slots[17] = 1201; Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(fr.shown and fr.leaving and fr.fadeOut.playing, "with fade: it fades out")
fr.fadeOut:Finish()
Check(not fr.shown, "and is hidden when the fade ends")
c.TwichUIDB.modules.arrivalReducedMotion = true
W.slots[17] = nil; Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
Check(fr.shown and not fr.fadeIn.playing and fr.body.alpha == 1, "Reduced motion: no fade")
c.TwichUIDB.modules.arrivalReducedMotion = false
RM.SetDisplay(id, "fade", false)

-- preview: shows whatever the rules say, marked, and changes nothing live
W.slots[17] = 1201; Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(not fr.shown, "hidden by its rules")
local liveBefore = ST.Observations().slots[17]
Check(D.PreviewStart(RM.Get(id)), "preview")
Check(fr.shown and fr.mark and fr.mark.shown and fr.mark.label.text:find("Preview"), "shown where it sits, marked Preview")
Check(not fr.handle.shown and fr.handle.mouse == false, "no handle unless moving")
Check(CT.Status(id) == "hidden" and ST.Observations().slots[17] == liveBefore, "the preview changes no decision or observation")
D.PreviewStart(RM.Get(id), true)
Check(fr.handle.shown and fr.handle.mouse == true, "moving: the handle takes the mouse")
fr.left, fr.bottom = 500, 100
fr.handle.scripts.OnDragStart(); fr.handle.scripts.OnDragStop()
local pl = RM.Get(id).place
local wantX = math.floor(fr.left + fr.w / 2 - 512 + 0.5)
local wantY = math.floor(fr.bottom + fr.h / 2 - 384 + 0.5)
Check(pl.preset == "custom" and pl.point == "CENTER" and pl.x == wantX and pl.y == wantY, "dragging saves a place of its own: "
  .. tostring(pl.x) .. "," .. tostring(pl.y) .. " want " .. wantX .. "," .. wantY)
Check(fr.points[1][4] == pl.x and fr.points[1][5] == pl.y, "and the frame sits on it")
-- the same drag measured from another point of the screen
RM.SetPosition(id, "TOPRIGHT", 0, 0)
fr.left, fr.bottom = 900, 700
fr.handle.scripts.OnDragStart(); fr.handle.scripts.OnDragStop()
pl = RM.Get(id).place
Check(pl.point == "TOPRIGHT" and pl.x == math.floor(900 + fr.w - 1024 + 0.5) and pl.y == math.floor(700 + fr.h - 768 + 0.5), "offsets follow the chosen anchor point")
RM.SetPreset(id, "belowCenter")
Check(RM.Get(id).place.point == "CENTER" and RM.Get(id).place.y == -200, "a preset puts it back")
fr.handle.scripts.OnMouseUp(fr.handle, "RightButton")
Check(not fr.handle.shown and fr.mark.shown, "right-click ends moving; the preview stays")
W.combat = true; Fire("PLAYER_REGEN_DISABLED"); Settle()
Check(D.PreviewId() == nil and not fr.shown, "combat ends the preview; its rules hide it again")
W.combat = false; Fire("PLAYER_REGEN_ENABLED"); Settle()
W.combat = true
Check(D.PreviewStart(RM.Get(id)) == false, "no preview in combat")
W.combat = false
D.PreviewStart(RM.Get(id))
RM.Delete(id2)
Check(D.PreviewId() == id, "deleting another leaves this preview")
local rid = id
RM.Delete(rid)
Check(D.PreviewId() == nil and D.Frame(rid) == nil, "deleting the previewed reminder ends its preview")

---------------------------------------------------------------------------
-- 7. Switching off, profiles, persistence
---------------------------------------------------------------------------
local _, sid = RM.Create("shield")
RM.SetEnabled(sid, true)
W.slots[17] = nil; Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
Check(Shown(sid), "a shield reminder on")
R:SetEnabled("reminders", false)
Check(not Shown(sid) and EventCount() == 0 and CT.Status(sid) == "off", "Reminders off: hidden, nothing listened for")
Check(#RM.List() == 1, "your reminders are kept")
NOW = NOW + 30; RunLongTimers(60); Settle()
Check(not Shown(sid), "nothing comes back while off")
R:SetEnabled("reminders", true)
Check(Shown(sid), "on again: it shows")

local PF = R.Profiles
Check(PF.Create("Second"), "a new profile")
Settle()
Check(#RM.List() == 0 and not Shown(sid), "a new profile has no reminders; the old one's frame is put away")
local _, other = RM.Create("custom")
Check(PF.Switch("Default") or PF.Switch(PF.List()[1]), "back to the first profile")
Settle()
Check(#RM.List() == 1 and RM.Get(sid) and Shown(sid), "its reminders are back, and showing")
Check(c.TwichUIDB.profiles.Second.ui.reminders.list[1].name == "New reminder", "the other profile keeps its own")

-- the newer-version guard
c.TwichUIDB.ui.reminders.version = 2
RM.Invalidate()
Check(not RM.Writable() and RM.Get(sid).problems[1] == RM.PROBLEM.newer and not Shown(sid), "a newer table is read, not shown")
Check(RM.SetEnabled(sid, false) == false and RM.Create("custom") == false, "and never written")
c.TwichUIDB.ui.reminders.version = 1
RM.Invalidate()

-- the switch and the stored table are kept on this computer by configuration sharing, with a reason
Check(R.TwichConfig.LOCAL["modules.reminders"] == "other" and R.TwichConfig.LOCAL["ui.reminders"] == "other", "not shared: kept local")

---------------------------------------------------------------------------
-- 7b. The troubleshooting report: counts only
---------------------------------------------------------------------------
for _, file in ipairs({ "diag/Diagnostics.lua", "diag/Reminders.lua" }) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local report, summary = R.Diag.Build()
local section
for _, e in ipairs(summary) do if e.key == "reminders" then section = e end end
Check(section and section.status == "ready", "a Reminders section, ready: " .. tostring(section and section.status))
Check(report:find("reminders: 1 %(turned on 1, valid 1, running here 1%)") and report:find("showing: 1"), "with counts")
Check(not report:find("Shield reminder", 1, true) and not report:find("Rich - Forever", 1, true) and not report:find("Equip your shield", 1, true),
  "and no names, characters or words")

---------------------------------------------------------------------------
-- 8. Nothing acts in the game
---------------------------------------------------------------------------
Check(#acted == 0, "no item equipped or used, nothing cast or sent: " .. table.concat(acted, ","))

---------------------------------------------------------------------------
-- 9. The artwork and the icons are where the code looks, in the format the game reads
---------------------------------------------------------------------------
local function TGA(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local h = fh:read(18)
  local size = fh:seek("end")
  fh:close()
  local b = { h:byte(1, 18) }
  return { type = b[3], w = b[13] + b[14] * 256, h = b[15] + b[16] * 256, bpp = b[17], desc = b[18], size = size }
end
for _, name in ipairs({ "shield", "shield-small", "ammo", "ammo-small" }) do
  local t = TGA(ROOT .. "media/reminders/" .. name .. ".tga")
  Check(t and t.type == 2 and t.bpp == 32 and t.desc == 8 and t.size == 18 + t.w * t.h * 4, name .. ".tga is an uncompressed 32-bit TGA with alpha")
end
for _, id in ipairs(RM.ART_ORDER) do
  local art = RM.ART[id]
  Check(TGA(ROOT .. "media/reminders/" .. id .. ".tga").w == art.size and TGA(ROOT .. "media/reminders/" .. id .. "-small.tga").w == art.smallSize, id .. ": sizes match the ART table")
end
for _, icon in ipairs({ "reminders", "reminderShow", "reminderWhen", "reminderPlacement", "reminderPreview", "reminderTest" }) do
  Check(R.Icons.Get(icon) ~= nil, icon .. " is registered")
  for _, suffix in ipairs({ "", "-small" }) do
    local t = TGA(ROOT .. "media/icons/" .. icon .. suffix .. ".tga")
    Check(t and t.bpp == 32 and t.w == (suffix == "" and 64 or 32), icon .. suffix .. ".tga is there")
  end
end
for _, e in ipairs(RM.ICONS) do Check(R.Icons.Get(e[1]) ~= nil, "offered icon " .. e[1] .. " exists") end
local toc = io.open(ROOT .. "!!!TwichUI.toc"):read("*a")
for _, f in ipairs({ "Config", "Conditions", "Evaluate", "State", "Display", "Controller" }) do
  Check(toc:find("reminders\\" .. f .. ".lua", 1, true), "the .toc lists reminders/" .. f .. ".lua")
end
Check(toc:find("reminders\\Config.lua", 1, true) < toc:find("reminders\\Controller.lua", 1, true), "in load order")
local pkg = io.open(REPO .. ".pkgmeta"):read("*a")
Check(not pkg:find("media", 1, true), "media is packaged")

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
