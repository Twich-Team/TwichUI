-- Reminders about ammunition (reminders/Ammunition.lua, AmmoItems.lua, State.lua's "ammo" source): the judgement is pure,
-- the source reads the character and the bags, the condition goes through the same controller as every other. A fake
-- world stands in for the game, so this checks our logic, not the game: the in-game checks are in docs/reminders.md.
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

-- The items the client knows: class 6 is Projectile (subclass 2 arrows, 3 bullets, 0 something else), class 2 Weapon
-- (subclass 2 Bows, 3 Guns, 18 Crossbow, 19 Wand). 90001 and up are server items the client has no data for.
c.Enum = { ItemClass = { Weapon = 2, Armor = 4, Projectile = 6 }, ItemWeaponSubclass = { Bows = 2, Guns = 3, Crossbow = 18, Thrown = 16, Wand = 19, Fishingpole = 20 }, ItemArmorSubclass = { Shield = 6 } }
local ITEMS = {
  [2512] = { class = 6, sub = 2, icon = "arrow-icon" },   -- arrows
  [3030] = { class = 6, sub = 2, icon = "arrow2-icon" },  -- more arrows
  [2516] = { class = 6, sub = 3, icon = "bullet-icon" },  -- bullets
  [3033] = { class = 6, sub = 3, icon = "bullet2-icon" },
  [7000] = { class = 6, sub = 0, icon = "odd-icon" },     -- a projectile of a kind nothing here knows
  [2504] = { class = 2, sub = 2, icon = "bow-icon" },     -- a bow
  [2508] = { class = 2, sub = 3, icon = "gun-icon" },     -- a gun
  [2509] = { class = 2, sub = 18, icon = "xbow-icon" },   -- a crossbow
  [5000] = { class = 2, sub = 19, icon = "wand-icon" },   -- a wand
  [5001] = { class = 2, sub = 16, icon = "thrown-icon" }, -- a thrown weapon
  [8000] = { class = 0, sub = 0, icon = "potion-icon" },  -- not ammunition
}
local W, calls, asked, NOW
local function World(class)
  W = { class = class or "HUNTER", uses = true, ranged = 2504, ammo = 2512, count = 100, combat = false, bags = {}, slots = {},
    dead = false, ghost = false, mounted = false }
  calls = { uses = 0, inv = 0, bag = 0, count = 0 }
  asked = {}
end
World()
NOW = 1000
c.GetTime = function() return NOW end
c.UnitClassBase = function() return W.class end
c.UnitUsesAmmo = function() calls.uses = calls.uses + 1; return W.uses end
c.INVSLOT_AMMO, c.INVSLOT_RANGED = 0, 18
c.GetInventoryItemID = function(_, slot)
  calls.inv = calls.inv + 1
  if slot == 18 then return W.ranged end
  if slot == 0 then return W.ammo end
  return W.slots[slot]
end
c.GetInventoryItemCount = function(_, slot) calls.count = calls.count + 1; if slot == 0 then return W.count end return 1 end
c.C_Item = {
  GetItemInfoInstant = function(id)
    local it = ITEMS[id]
    if not it then return nil end
    return id, "type", "subtype", "", it.icon, it.class, it.sub
  end,
  GetItemIconByID = function(id) return ITEMS[id] and ITEMS[id].icon or nil end,
  GetItemNameByID = function() return nil end,
  RequestLoadItemDataByID = function(id) asked[id] = (asked[id] or 0) + 1 end,
}
c.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
c.C_Container = {
  GetContainerNumSlots = function(bag) return bag <= 12 and 6 or 0 end,   -- (bank bags answer too)
  GetContainerItemID = function(bag, slot) calls.bag = calls.bag + 1; return (W.bags[bag] or {})[slot] end,
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
  "reminders/AmmoItems.lua", "reminders/Config.lua", "reminders/Conditions.lua", "reminders/Ammunition.lua", "reminders/Evaluate.lua", "reminders/State.lua",
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
local A, AI = R.ReminderAmmo, R.AmmoItems
local function Changed(events)
  for _, e in ipairs(events or { "BAG_UPDATE_DELAYED" }) do
    Fire(e, e == "UNIT_INVENTORY_CHANGED" and "player" or (e == "PLAYER_EQUIPMENT_CHANGED" and 0 or nil))
  end
  Settle()
end
local function Bag(slot, id) W.bags[0] = W.bags[0] or {}; W.bags[0][slot] = id end
local function State() return (A.Judge(ST.Observations().ammo)) end
local function View(conds, match, scope)
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

---------------------------------------------------------------------------
-- 1. The judgement is pure
---------------------------------------------------------------------------
do
  local NIL = {}   -- (a key set to nil in a table constructor is not there to override)
  local function Judge(t)
    local f = { uses = true, ranged = true, needs = "arrow", carries = false }
    for k, v in pairs(t) do if v == NIL then f[k] = nil else f[k] = v end end
    return (A.Judge(f))
  end
  Check(Judge({ uses = false }) == "inactive", "the client says no ammunition is used")
  Check(Judge({ uses = NIL }) == "unknown", "no answer is not an answer")
  Check(select(2, A.Judge({ ranged = false, uses = true })), "ammunition used with no weapon is not settled, and says why")
  Check(Judge({ ranged = false }) == "unknown", "ammunition used with no weapon is not settled")
  Check(Judge({}) == "outOfAmmo", "nothing selected, none carried")
  Check(Judge({ carries = true }) == "noAmmo", "nothing selected, some carried")
  Check(Judge({ carries = NIL }) == "unknown", "the bags could not be read")
  Check(Judge({ id = 1, kind = "arrow", count = 10 }) == "ok")
  Check(Judge({ id = 1, kind = "arrow", count = 0 }) == "outOfAmmo", "a selected stack of none")
  Check(Judge({ id = 1, kind = "arrow", count = NIL }) == "unknown", "a count that has not arrived")
  Check(Judge({ id = 1, kind = "bullet", count = 10 }) == "wrong")
  Check(Judge({ id = 1, kind = "other", count = 10 }) == "ok", "an unknown kind of projectile is never called wrong")
  Check(Judge({ id = 1, kind = NIL, count = 10 }) == "ok", "an unrecognized item is never called wrong")
  Check(Judge({ id = 1, kind = "bullet", count = 10, needs = NIL }) == "ok", "a weapon of unknown type judges nothing")
  Check(A.Judge(nil) == "unknown", "no facts at all: unknown")
  Check(A.NeedsFor(2, 2) == "arrow" and A.NeedsFor(2, 18) == "arrow" and A.NeedsFor(2, 3) == "bullet")
  Check(A.NeedsFor(2, 19) == nil and A.NeedsFor(2, 16) == nil and A.NeedsFor(4, 2) == nil and A.NeedsFor(nil, nil) == nil,
    "a wand, a thrown weapon, armor and nothing take none")
end

---------------------------------------------------------------------------
-- 2. The condition: stored fields, the three answers, words, the Test section's situations
---------------------------------------------------------------------------
do
  for _, what in ipairs({ "problem", "noAmmo", "outOfAmmo", "wrong" }) do
    Check(View({ { type = "ammunition", what = what } }).valid, what .. " is a usable condition")
  end
  local bad = View({ { type = "ammunition", what = "plenty" } })
  Check(not bad.valid and bad.conditions[1].cond == nil and bad.problems[1]:find("ammunition"), "an unknown choice is flagged, not changed")
  local clean = C.Check({ type = "ammunition", what = "wrong", negate = true, junk = 1 })
  Check(clean and clean.what == "wrong" and clean.negate == nil and clean.junk == nil, "only its own fields are kept")

  local function Entry(what) return View({ { type = "ammunition", what = what } }).conditions[1] end
  local OUT = { ammo = { uses = true, ranged = true, needs = "arrow", carries = false } }
  local HAVE = { ammo = { uses = true, ranged = true, needs = "arrow", carries = true } }
  local WRONG = { ammo = { uses = true, ranged = true, needs = "arrow", id = 1, kind = "bullet", count = 5 } }
  local OK = { ammo = { uses = true, ranged = true, needs = "arrow", id = 1, kind = "arrow", count = 5 } }
  local NONE = { ammo = { uses = false, ranged = true } }
  Check(E.Condition(Entry("problem"), OUT) == MATCH and E.Condition(Entry("problem"), HAVE) == MATCH and E.Condition(Entry("problem"), WRONG) == MATCH, "any problem matches each of the three")
  Check(E.Condition(Entry("problem"), OK) == NOMATCH and E.Condition(Entry("problem"), NONE) == NOMATCH, "ready ammunition, or a weapon that takes none: no match")
  Check(E.Condition(Entry("outOfAmmo"), OUT) == MATCH and E.Condition(Entry("outOfAmmo"), HAVE) == NOMATCH, "used up is not 'carried but not selected'")
  Check(E.Condition(Entry("noAmmo"), HAVE) == MATCH and E.Condition(Entry("noAmmo"), OUT) == NOMATCH)
  Check(E.Condition(Entry("wrong"), WRONG) == MATCH and E.Condition(Entry("wrong"), OK) == NOMATCH)
  local result, observed, reason = E.Condition(Entry("problem"), { })
  Check(result == UNKNOWN and reason, "nothing read: unknown, with a reason")
  Check(E.Condition(Entry("problem"), { ammo = { ranged = true } }) == UNKNOWN, "the client's answer missing: unknown, never a problem")
  Check(E.Summary(Entry("outOfAmmo")) == "Ranged ammunition is used up" and E.Summary(Entry("problem")) == "Ranged ammunition has a problem", "the summaries read naturally")
  Check(select(2, E.Condition(Entry("problem"), OUT)) == "Used up" and select(2, E.Condition(Entry("problem"), {})) == "Not read yet", "what was observed, in words")

  -- the Test section: the situation this condition looks for comes first, and every key is distinct
  for _, what in ipairs({ "problem", "noAmmo", "outOfAmmo", "wrong" }) do
    local view = View({ { type = "ammunition", what = what } })
    local list = E.Scenarios(view.conditions[1])
    local seen = {}
    for _, s in ipairs(list) do Check(not seen[s.key], "distinct scenario keys"); seen[s.key] = true end
    Check(#list == 6 and E.Simulate(view).status == "showing", what .. ": the first situation is the one it looks for")
    Check(E.Simulate(view, { "ok" }).status == "hidden", what .. ": ammunition ready: hidden")
    Check(E.Simulate(view, { "inactive" }).status == "hidden", what .. ": a weapon that takes none: hidden")
    Check(E.Simulate(view, { "unread" }).status == "waiting", what .. ": not read: waiting")
  end
  Check(E.Simulate(View({ { type = "ammunition", what = "wrong" } }), { "outOfAmmo" }).status == "hidden", "'wrong' ignores a used-up supply")
end

---------------------------------------------------------------------------
-- 3. The template, and a draft that reads nothing
---------------------------------------------------------------------------
local id, wid
do
  World()
  CT.Refresh()
  Fire("PLAYER_ENTERING_WORLD"); Settle()
  Check(R.DEFAULT_MODULES.ammoWarning == nil and c.TwichUIDB.modules.ammoWarning == nil, "the old switch is gone")
  local ok
  ok, id = RM.Create("ammo")
  Check(ok, "the Ammunition template")
  local v = RM.Get(id)
  Check(v.valid and not v.enabled and v.name == "Ammunition reminder", "valid, and turned off")
  Check(v.conditions[1].cond.type == "ammunition" and v.conditions[1].cond.what == "problem", "any problem")
  Check(v.display.art == "ammo" and v.display.text == "Check your ammunition" and RM.Art("ammo"), "the arrows artwork and words")
  Check(v.scope.who == "characters" and #v.scope.characters == 1, "this character only")
  Check(ST.Snapshot().keys == 0 and not ST.Registered("BAG_UPDATE_DELAYED"), "a draft reads nothing and listens for nothing")
  local inv = calls.inv
  local out = CT.Inspect(id)
  Check(out.conditions[1].result == MATCH or out.conditions[1].result == NOMATCH, "Right now reads the draft once: " .. tostring(out.conditions[1].result))
  Check(out.conditions[1].observed == "Ammunition selected and some left", "and says what it found: " .. tostring(out.conditions[1].observed))
  Check(calls.inv > inv and ST.Snapshot().keys == 0 and not ST.Registered("BAG_UPDATE_DELAYED"), "without adding to what the live ones read")
  Check(RM.SetEnabled(id, true), "turned on")
end

---------------------------------------------------------------------------
-- 4. Live: the three problems, from what the game reports
---------------------------------------------------------------------------
do
  Check(ST.Registered("PLAYER_EQUIPMENT_CHANGED") and ST.Registered("BAG_UPDATE_DELAYED") and ST.Registered("UNIT_INVENTORY_CHANGED"), "it listens for the equipment, bag and inventory events")
  Check(not ST.Registered("PLAYER_REGEN_DISABLED") and not ST.Registered("GET_ITEM_INFO_RECEIVED"), "and for nothing else")
  Check(State() == "ok" and not Shown(id), "bow and arrows: nothing shows")
  Check(calls.bag == 0, "the bags are not read while ammunition is selected")

  -- the ammunition is gone from the slot and the bags hold some that fits
  W.ammo, W.count = nil, nil
  Bag(1, 2512)
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "noAmmo" and Shown(id), "arrows in the bags, none selected: shows")
  W.ammo, W.count = 2512, 40
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "ok" and not Shown(id), "selected again: gone")

  -- the selected stack is used up
  W.count = 0
  Changed({ "UNIT_INVENTORY_CHANGED" })
  Check(State() == "outOfAmmo" and Shown(id), "a stack of none")
  W.ammo, W.count, W.bags = nil, nil, {}
  Changed()
  Check(State() == "outOfAmmo" and Shown(id), "nothing selected, nothing carried")

  -- a bow with only bullets: they do not fit; a gun can use them; a crossbow takes arrows
  Bag(2, 2516)
  Changed()
  Check(State() == "outOfAmmo", "a bow cannot use the bullets in the bags")
  W.ranged = 2508
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "noAmmo", "a gun can")
  W.bags = {}; Bag(1, 2512)
  Changed()
  Check(State() == "outOfAmmo", "a gun cannot use arrows")
  W.ranged = 2509
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "noAmmo", "a crossbow takes arrows")

  -- the wrong kind selected, and put right by either swap
  W.ranged, W.ammo, W.count = 2504, 2516, 80
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "wrong" and Shown(id), "bullets selected for a bow")
  W.ranged, W.ammo = 2508, 2512
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "wrong", "arrows selected for a gun")
  W.ranged = 2504
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "ok" and not Shown(id), "a weapon swap puts it right")
  W.ammo, W.count = 2516, 30
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "wrong")
  W.ranged = 2508
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "ok", "and so does an ammunition swap")

  -- another projectile subclass is never called wrong, and never counted as a supply
  W.ammo, W.count = 7000, 10
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "ok", "an unknown kind of projectile selected judges nothing")
  W.ammo, W.count, W.bags = nil, nil, {}; Bag(1, 7000)
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "outOfAmmo", "an unknown kind of projectile in the bags is not a supply")
  W.bags = {}; Bag(1, 8000)
  Changed()
  Check(State() == "outOfAmmo", "an item that is not ammunition is not a supply")

  -- bank bags are not carried bags
  W.ranged, W.bags = 2504, {}
  W.bags[9] = { [1] = 2512 }
  Changed()
  Check(State() == "outOfAmmo", "a bank bag is not a carried bag")
  W.bags = {}
  W.ammo, W.count = 2512, 600
  Bag(1, 2512); Bag(2, 2512); Bag(3, 2512)
  local bagReads = calls.bag
  Changed({ "BAG_UPDATE_DELAYED" })
  Check(State() == "ok" and calls.bag == bagReads, "several stacks: the slot's count is the supply, the bags are not added up")
  Check(calls.bag == bagReads and OnUpdates() == 0, "no OnUpdate anywhere")
end

---------------------------------------------------------------------------
-- 5. Each choice shows only for its own problem; "only in combat" is a condition
---------------------------------------------------------------------------
do
  wid = select(2, RM.Create("custom"))
  RM.AddCondition(wid, "ammunition")
  RM.SetCondition(wid, 1, { type = "ammunition", what = "wrong" })
  Check(RM.SetEnabled(wid, true), "a reminder for the wrong kind only")
  Check(not Shown(wid), "arrows for a bow: not wrong")
  W.ammo, W.count = 2516, 20
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(Shown(wid) and Shown(id), "bullets for a bow: both show")
  W.ammo, W.count, W.bags = nil, nil, {}
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(not Shown(wid) and Shown(id), "used up: only the general one")
  RM.Delete(wid)

  -- only in combat: one more condition, "Player is in combat"
  RM.AddCondition(id, "player")
  Check(not Shown(id) and ST.Registered("PLAYER_REGEN_DISABLED"), "out of combat: hidden, and combat is listened for now")
  W.combat = true; Fire("PLAYER_REGEN_DISABLED"); Settle()
  Check(Shown(id), "in combat: shown")
  W.combat = false; Fire("PLAYER_REGEN_ENABLED"); Settle()
  Check(not Shown(id), "out of combat again: gone")
  RM.RemoveCondition(id, 2)
  Check(Shown(id) and not ST.Registered("PLAYER_REGEN_DISABLED"), "removed: shown again, combat no longer listened for")
end

---------------------------------------------------------------------------
-- 6. No ranged weapon, a weapon that takes no ammunition, and who it is for
---------------------------------------------------------------------------
do
  W.ranged, W.uses, W.ammo, W.count = nil, false, nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "inactive" and not Shown(id), "no ranged weapon: no missing-ammunition reminder")
  W.ranged = 5000   -- a wand: the client says it takes none
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  W.ranged = 5001   -- a thrown weapon
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "inactive" and not Shown(id), "a weapon that takes none")
  local inv, uses = calls.inv, calls.uses
  Changed({ "BAG_UPDATE_DELAYED" })
  Fire("UNIT_INVENTORY_CHANGED", "player"); Settle()
  Check(calls.inv == inv and calls.uses == uses, "with a weapon that takes none, bag and inventory events cost no read")
  Fire("PLAYER_EQUIPMENT_CHANGED", 5); Settle()
  Check(calls.inv == inv, "nor does another slot")
  -- the client's word wins over any table of ours: a bow it says takes none shows nothing
  W.ranged = 2504
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "inactive" and not Shown(id))
  W.uses = true
  Fire("PLAYER_EQUIPMENT_CHANGED", 18); Settle()
  Check(State() == "outOfAmmo" and Shown(id), "now it takes ammunition, and there is none")
  local before = calls.uses
  Fire("UNIT_INVENTORY_CHANGED", "target"); Settle()
  Check(calls.uses == before, "another unit's inventory changing is not ours")

  -- who it is for: another class never listens for anything
  RM.SetScope(id, "class", "WARRIOR")
  Check(CT.Status(id) == "notApplicable" and not Shown(id) and not ST.Registered("BAG_UPDATE_DELAYED"), "not for a Hunter: hidden, and no event registered")
  RM.SetScope(id, "class", nil)
  Check(Shown(id) and ST.Registered("BAG_UPDATE_DELAYED"), "any class again")
  W.class = "MAGE"
  W.ranged = 2508
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "outOfAmmo" and Shown(id), "what the weapon takes decides, whatever the class (a Mage with a gun)")
  W.class = "HUNTER"
end

---------------------------------------------------------------------------
-- 7. Information that is not there yet is never a reminder
---------------------------------------------------------------------------
do
  W.ranged, W.ammo, W.count, W.bags = 2504, 2512, 100, {}
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(not Shown(id))
  -- login: the client has not told us whether the weapon takes ammunition
  W.uses = nil
  local start = calls.uses
  Fire("PLAYER_ENTERING_WORLD"); Settle()
  Check(not Shown(id) and CT.Status(id) == "waiting", "no answer: waiting, never shown")
  for _ = 1, 20 do FlushTimers() end
  local looks = calls.uses
  Check(looks - start >= 2 and looks - start <= 8, "it looked again a bounded number of times: " .. (looks - start))
  for _ = 1, 10 do FlushTimers() end
  Check(calls.uses == looks, "and then stopped: nothing polls")
  -- the answer arrives with the next event
  W.uses = true
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "outOfAmmo" and Shown(id), "now it is known")

  -- a count that has not arrived is not "none"
  W.ammo, W.count = 2512, nil
  Changed({ "UNIT_INVENTORY_CHANGED" })
  Check(State() == "unknown" and not Shown(id), "a count that is not there is not a used-up stack")
  W.count = 50
  Changed({ "UNIT_INVENTORY_CHANGED" })
  Check(State() == "ok")
  -- a burst is one read
  local reads = calls.uses
  for _ = 1, 6 do Fire("BAG_UPDATE_DELAYED") end
  Fire("UNIT_INVENTORY_CHANGED", "player"); Fire("PLAYER_EQUIPMENT_CHANGED", 0)
  Settle()
  Check(calls.uses - reads == 1, "a burst of events is one read: " .. (calls.uses - reads))
end

---------------------------------------------------------------------------
-- 8. Ammunition you registered
---------------------------------------------------------------------------
do
  c.TwichUIDB.ui.ammoCustom = nil
  AI.Reindex()
  Check(AI.Count() == 0 and #AI.List() == 0)
  local ok, how, kind = AI.Add("90001", "bullet")
  Check(ok and how == "added" and kind == "bullet" and AI.Count() == 1)
  ok, how, kind = AI.Add("|cff1eff00|Hitem:90002::::::::70:::::|h[Strange Shot]|h|r", "arrow")
  Check(ok and how == "added" and kind == "arrow" and AI.Entry(90002).kind == "arrow", "an item link works")
  ok, how, kind = AI.Add(90001, "arrow")
  Check(ok and how == "exists" and kind == "bullet" and AI.Count() == 2, "a duplicate changes nothing")
  for _, bad in ipairs({ "", "abc", "0", "-5", "1.5", "99999999999", false, {}, "item:" }) do
    Check(AI.Add(bad, "arrow") == false, "invalid input refused: " .. tostring(bad))
  end
  Check(AI.Add(90003, "grenade") == false and AI.Count() == 2, "an unknown kind is refused; the list is left alone")
  ok, how, kind = AI.Add(3033)
  Check(ok and kind == "bullet", "the client's classification is the default kind")
  ok, how, kind = AI.Add(90004)
  Check(ok and kind == "arrow", "arrows when nothing says otherwise")
  Check(AI.SetKind(90004, "bullet") and AI.Entry(90004).kind == "bullet" and AI.SetKind(90004, "bullet") == true)
  Check(AI.SetKind(90004, "grenade") == false and AI.SetKind(424242, "arrow") == false)
  Check(AI.Remove(90004) == true and AI.Entry(90004) == nil and AI.Remove(90004) == false)
  AI.Remove(3033)
  for i = 1, AI.MAX do AI.Add(100000 + i, "arrow") end
  Check(AI.Count() == AI.MAX and AI.Add(777777, "arrow") == false, "the list is bounded")
  for i = 1, AI.MAX do AI.Remove(100000 + i) end
  Check(AI.Kind(90001) == "bullet" and select(2, AI.Kind(90001)) == "custom", "your registration first")
  Check(AI.Kind(2512) == "arrow" and select(2, AI.Kind(2512)) == "client", "then the client's word")
  Check(AI.Kind(8000) == nil and AI.Kind(31337) == nil, "not ammunition, or unknown to the client")
  Check(AI.Known(31337) == false and AI.Known(2512) == true)

  -- a server item the client has no data for, registered: bullets for a gun are fine, for a bow wrong
  AI.Remove(90002)
  W.ranged, W.ammo, W.count, W.bags = 2508, 90001, 25, {}
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "ok" and not Shown(id), "registered bullets are bullets for a gun")
  W.ranged = 2504
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "wrong" and Shown(id), "and wrong for a bow")
  AI.SetKind(90001, "arrow")
  Check(State() == "ok" and not Shown(id), "correcting it takes effect at once, without another event")
  AI.Remove(90001)
  Check(State() == "ok", "an item nobody recognizes is never called wrong")
  -- a supply from the bags; registering is not having
  AI.Add(90002, "arrow")
  W.ammo, W.count, W.bags = nil, nil, {}
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "outOfAmmo", "registering an item is not having it")
  Bag(3, 90002)
  Changed()
  Check(State() == "noAmmo", "registered arrows in the bags are a supply for a bow")
  AI.Add(2512, "bullet")
  W.bags = {}; Bag(1, 2512)
  Changed()
  Check(State() == "outOfAmmo", "arrows you registered as bullets are not a supply for a bow")
  AI.Remove(2512)
  Check(State() == "noAmmo", "removing it goes back to the client's word")
  AI.Remove(90002)

  -- the list follows the profile
  AI.Add(90001, "bullet")
  c.TwichUIDB.ui.ammoCustom = { items = { { id = 90005, kind = "arrow" } } }
  R.Profiles.Refresh("test")
  Check(AI.Kind(90005) == "arrow" and AI.Kind(90001) == nil, "another profile's list")
  c.TwichUIDB.ui.ammoCustom = nil
  R.Profiles.Refresh("test")
  Check(AI.Count() == 0)
end

---------------------------------------------------------------------------
-- 9. Sharing: only the list travels; the old warning's groups are gone
---------------------------------------------------------------------------
do
  local TC = R.TwichConfig
  local ids = {}
  for _, g in ipairs(TC.Groups()) do ids[g.id] = g end
  Check(ids.ammoCustom and not ids.ammo and not ids.ammoLook, "the list is a group; the warning's are not")
  Check(TC.LOCAL["ui.ammoPosition"] == nil, "no place of its own any more")
  local L = ids.ammoCustom.custom
  Check(L.usable() and L.count() == 0 and L.export() == nil, "an empty list shares nothing")
  AI.Add(90001, "bullet"); AI.Add(90002, "arrow")
  local exported = L.export()
  Check(#exported.items == 2 and exported.items[1].id == 90001 and exported.items[2].kind == "arrow")
  Check(L.clean({ items = { { id = 5, kind = "arrow" }, { id = 6, kind = "bullet" } } }))
  Check(L.clean(nil) == nil and L.clean({}) == nil and L.clean({ items = {} }) == nil, "shape and empty")
  Check(L.clean({ items = { { id = 5, kind = "grenade" } } }) == nil, "an unknown kind")
  Check(L.clean({ items = { { id = 0, kind = "arrow" } } }) == nil and L.clean({ items = { { id = "5", kind = "arrow" } } }) == nil, "an unusable id")
  Check(L.clean({ items = { { id = 5, kind = "arrow" }, { id = 5, kind = "bullet" } } }) == nil, "a repeated id")
  Check(L.clean({ items = { x = { id = 5, kind = "arrow" } } }) == nil, "not a list")
  local big = {}
  for i = 1, AI.MAX + 1 do big[i] = { id = 500 + i, kind = "arrow" } end
  Check(L.clean({ items = big }) == nil, "too many")
  local clean = L.clean({ items = { { id = 90001, kind = "arrow" }, { id = 90009, kind = "bullet" } } })
  local plan = L.plan(clean)
  Check(#plan == 2 and plan.full == 0 and #L.review(clean) == 2)
  local undo = L.apply(clean, plan)
  Check(AI.Entry(90001).kind == "arrow" and AI.Entry(90009).kind == "bullet" and AI.Entry(90002).kind == "arrow" and AI.Count() == 3, "merged; nothing removed")
  -- a running reminder reads the new list at once
  W.ranged, W.ammo, W.count, W.bags = 2508, 90009, 5, {}
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(State() == "ok", "an imported kind is used straight away")
  Check(L.restore(undo) == 2 and AI.Entry(90001).kind == "bullet" and AI.Entry(90009) == nil and AI.Count() == 2, "the undo puts the list back")
  Check(State() == "ok", "and the reminder follows it (90009 is nobody's again)")
  AI.Remove(90001); AI.Remove(90002)
end

---------------------------------------------------------------------------
-- 10. Off, deleted, and nothing acts
---------------------------------------------------------------------------
do
  W.ranged, W.ammo, W.count, W.bags, W.uses = 2504, nil, nil, {}, true
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  Check(Shown(id))
  Fire("BAG_UPDATE_DELAYED")            -- a read is queued ...
  R:SetEnabled("reminders", false)      -- ... and Reminders is switched off before it runs
  local snapshot = { inv = calls.inv, bag = calls.bag, uses = calls.uses }
  Check(not Shown(id) and EventCount() == 0, "off hides it at once and unregisters everything")
  Settle()
  Check(calls.inv == snapshot.inv and calls.bag == snapshot.bag and calls.uses == snapshot.uses, "the queued read did nothing")
  R:SetEnabled("reminders", true)
  Settle()
  Check(Shown(id) and ST.Registered("BAG_UPDATE_DELAYED"), "on again: it looks at once")
  RM.Delete(id)
  Check(D.Frame(id) == nil and not ST.Registered("BAG_UPDATE_DELAYED") and not ST.Registered("UNIT_INVENTORY_CHANGED"), "deleted: its frame and its events go")
  Check(OnUpdates() == 0)
  Check(#acted == 0, "nothing equipped, moved, used, cast or sent: " .. table.concat(acted, ","))
  Check(ST.Snapshot().keys == 0 and ST.Observations().ammo == nil, "nothing about ammunition is kept once nothing reads it")
end

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
