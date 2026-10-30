dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Reminders, the condition designer's model and words (reminders/Config.lua's node operations, TwichUI_Settings/pages/
-- RemindersPlain.lua). The frames the designer draws are in test_reminders_settings.lua; this is the part that decides:
--   * moving, copying and putting back conditions and groups: a reorder never changes what a rule says, a move into another
--     group keeps every condition, a refusal leaves the rule exactly as it was, limits and depth hold, and unsupported
--     conditions travel with everything else untouched;
--   * the plain words: a sentence for each kind, the rule as lines (nothing left out), who it is for, what the picker
--     offers from the registry, and the editor's fields never edit the condition they are given;
--   * why a rule would or would not show: true, false and unknown for conditions and groups, unknown beside an answer that
--     decides the group, a limit of the client said in a short line, and "conditions match" kept apart from "it is showing";
--   * none of that reads or writes anything it shouldn't: reading the words leaves the stored rule as it was.

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local UNITS = { uses = true }
local function World(c)
  c.UnitClassBase = function() return "WARRIOR" end
  c.UnitUsesAmmo = function() return UNITS.uses end
  c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemArmorSubclass = { Shield = 6 }, ItemWeaponSubclass = { Fishingpole = 20 } }
  c.C_Item = { GetItemInfoInstant = function() return nil end, GetItemNameByID = function(id) if id == 6948 then return "Hearthstone" end end }
end
local c, S = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
local RM, E, CT, ST, Pl, C = R.Reminders, R.ReminderEval, R.ReminderController, R.ReminderState, R.RemindersPlain, R.ReminderConditions

local function Deep(v)   -- a string for a whole stored value, to see that nothing changed
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Deep(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

-- (class Warrior; ammunition problem) and (any: class Hunter, class Rogue) and combat: the tree the tests share
local function Make(shape)
  local ok, id = RM.Create("custom")
  assert(ok, id)
  shape(id)
  return id
end
local function Raw(id) return RM.Get(id).raw end
local function Cond(kind, extra)
  local t = { type = kind }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
local function Put(id, groupPath, cond) assert(RM.AddCondition(id, cond.type, groupPath, cond)) end

-- A rule: all of [ammunition problem, any of [Warrior, Hunter], in combat]
local function Screenshot()
  return Make(function(id)
    Put(id, nil, Cond("ammunition", { what = "problem" }))
    assert(RM.AddGroup(id, nil, "any"))
    Put(id, { 2 }, Cond("class", { class = "WARRIOR", negate = false }))
    Put(id, { 2 }, Cond("class", { class = "HUNTER", negate = false }))
    Put(id, nil, Cond("player", { state = "combat", negate = false }))
  end)
end

---------------------------------------------------------------------------
-- 1. Adding with a prepared condition, and a group that starts as asked
---------------------------------------------------------------------------
local id = Screenshot()
local v = RM.Get(id)
Check(v.valid and #v.conditions == 3 and v.conditions[2].group and v.conditions[2].match == "any", "the rule is made: all of [ammo, any of [classes], combat]")
Check(RM.AddCondition(id, "class", nil, Cond("equipment")) == false, "a prepared condition of another kind is refused")
Check(RM.AddCondition(id, "class", nil, { type = "class", class = "NOTACLASS" }) == false, "one the provider can't use at all is refused")
local before = Deep(Raw(id))
local ok, why = RM.AddGroup(id, nil, "maybe")
Check(not ok and Deep(Raw(id)) == before, "a group that is neither all nor any is refused, and nothing changed")
local ok2, gp = RM.AddGroup(id, nil, "all")
Check(ok2 and RM.Get(id).raw.conditions[4].match == "all", "a group can start as all in a list that matches all (the default would have been any)")
RM.RemoveCondition(id, { 4 })

---------------------------------------------------------------------------
-- 2. Reordering never changes what a rule says; moving into another group keeps every condition
---------------------------------------------------------------------------
local function Outcomes(id)
  -- the decision over every combination of what the rule's three subjects can be
  local seen = {}
  local v = RM.Get(id)
  for _, ammo in ipairs({ "ok", "problem", "unread" }) do
    for _, class in ipairs({ "WARRIOR", "HUNTER", "MAGE", "unread" }) do
      for _, combat in ipairs({ true, false, "unread" }) do
        local obs = { slots = {} }
        if ammo == "ok" then obs.ammo = { uses = true, ranged = true, needs = "arrow", id = 0, kind = "arrow", count = 50 }
        elseif ammo == "problem" then obs.ammo = { uses = true, ranged = true, needs = "arrow", carries = false } end
        if class ~= "unread" then obs.class = class end
        if combat ~= "unread" then obs.combat = combat end
        seen[#seen + 1] = E.Run(v, obs, { simulated = true }).result
      end
    end
  end
  return table.concat(seen, ",")
end
local baseline = Outcomes(id)
local node2 = Raw(id).conditions[2]
local node3 = Raw(id).conditions[3]
local ok3, at = RM.MoveNode(id, { 3 }, {}, 1)
Check(ok3 and Raw(id).conditions[1] == node3 and Raw(id).conditions[3] ~= node3 and at[1] == 1, "reorder: the combat condition is first, the same stored table")
Check(Outcomes(id) == baseline, "reordering inside one list does not change what the rule decides, for any facts")
ok3 = RM.MoveNode(id, { 1 }, {}, 99)
Check(ok3 and Raw(id).conditions[3] == node3, "an index past the end puts it last")
Check(RM.MoveNode(id, { 3 }, {}, 3) == true and Raw(id).conditions[3] == node3, "moving to where it is changes nothing")
local rev = RM.Rev()
RM.MoveNode(id, { 3 }, {}, 3)
Check(RM.Rev() == rev, "and tells nobody")

-- inside the group: swap its two classes
local g = Raw(id).conditions[2]
local c1, c2 = g.conditions[1], g.conditions[2]
Check(RM.MoveNode(id, { 2, 2 }, { 2 }, 1) and g.conditions[1] == c2 and g.conditions[2] == c1, "reordered inside a group")
Check(Outcomes(id) == baseline, "and still decides the same")

-- into another group: the condition leaves one list and joins the other, nothing lost, identity kept
local count = RM.Get(id).counts.conditions
local ok4, at4 = RM.MoveNode(id, { 3 }, { 2 }, nil)
Check(ok4 and g.conditions[3] == node3 and #Raw(id).conditions == 2 and at4[1] == 2 and at4[2] == 3, "moved into the group, as its last")
Check(RM.Get(id).counts.conditions == count and RM.Get(id).valid, "the counts are the same")
Check(Outcomes(id) ~= baseline, "moving across groups changes what the rule says (combat is now one of the alternatives): that is why it is said when it happens")
-- and out again, to the top level
local ok5 = RM.MoveNode(id, { 2, 3 }, {}, 1)
Check(ok5 and Raw(id).conditions[1] == node3 and Outcomes(id) == baseline, "moved back out: the original meaning again")
-- the group itself moves like a condition
local ok6, at6 = RM.MoveNode(id, { 3 }, {}, 1)
Check(ok6 and Raw(id).conditions[1] == node2 and at6[1] == 1, "a group moves with what is in it")
Check(#node2.conditions == 2, "what was in it is still in it")
RM.MoveNode(id, { 3 }, {}, 1)   -- back to: ammunition, the group, combat
Check(Raw(id).conditions[2] == node2 and Raw(id).conditions[3] == node3, "(the rule is as it began)")

---------------------------------------------------------------------------
-- 3. What is refused, and that a refusal leaves everything as it was
---------------------------------------------------------------------------
local snap = Deep(Raw(id))
local okA, whyA = RM.MoveNode(id, { 2 }, { 2 }, nil)
Check(not okA and whyA:find("itself") and Deep(Raw(id)) == snap, "a group can't be moved into itself")
-- a group inside a group, then try to move the outer into the inner
assert(RM.AddGroup(id, { 2 }, "all"))
snap = Deep(Raw(id))
okA, whyA = RM.MoveNode(id, { 2 }, { 2, 3 }, nil)
Check(not okA and Deep(Raw(id)) == snap, "or into a group inside it")
-- depth: a group with a group in it can't go into a group (that would be four levels)
RM.RemoveCondition(id, { 2, 3 })
assert(RM.AddGroup(id, nil, "any"))           -- a new top-level group at 4
Check(RM.Get(id).conditions[4] and RM.Get(id).conditions[4].group, "an empty group to move into")
assert(RM.AddGroup(id, { 2 }, "all"))         -- a group inside the group at 2: the group at 2 now needs two levels
snap = Deep(Raw(id))
okA, whyA = RM.MoveNode(id, { 2 }, { 4 }, nil)
Check(not okA and whyA == RM.REFUSE.tooDeep and Deep(Raw(id)) == snap, "a group two levels deep can't go into a group: " .. tostring(whyA))
Check(RM.MoveNode(id, { 2, 3 }, { 4 }, nil), "but a group of conditions can")
RM.RemoveCondition(id, { 3, 1 }) RM.RemoveCondition(id, { 3 })
Check(RM.MoveNode(id, { 99 }, {}, 1) == false and RM.MoveNode(id, {}, {}, 1) == false and RM.MoveNode(id, { 1 }, { 1 }, 1) == false, "a path that leads nowhere, the top itself, or a condition as destination are refused")
Check(RM.MoveNode("r999", { 1 }, {}, 1) == false, "and a reminder that isn't there")

---------------------------------------------------------------------------
-- 4. Copies, and putting a removed node back
---------------------------------------------------------------------------
local id2 = Screenshot()
local before2 = Deep(Raw(id2))
local okD, atD = RM.DuplicateNode(id2, { 2 })
local r = Raw(id2)
Check(okD and #r.conditions == 4 and r.conditions[3] ~= r.conditions[2] and Deep(r.conditions[3]) == Deep(r.conditions[2]) and atD[1] == 3, "a group is copied right after itself, with what is in it")
Check(r.conditions[3].conditions[1] ~= r.conditions[2].conditions[1], "the copy shares no table with the original")
r.conditions[3].conditions[1].class = "ROGUE"
Check(r.conditions[2].conditions[1].class == "WARRIOR", "changing the copy leaves the original")
Check(RM.Get(id2).counts.groups == 2 and RM.Get(id2).counts.conditions == 6, "the counts include the copy")
-- limits: fill to 16 conditions
local id3 = Make(function(id)
  for _ = 1, RM.MAX_CONDITIONS do Put(id, nil, Cond("player", { state = "combat", negate = false })) end
end)
snap = Deep(Raw(id3))
local okF, whyF = RM.DuplicateNode(id3, { 1 })
Check(not okF and whyF == RM.REFUSE.conditionsFull and Deep(Raw(id3)) == snap, "a copy that would pass the limit on conditions is refused")
-- groups: six, then no copy of a group
local id4 = Make(function(id)
  for _ = 1, RM.MAX_GROUPS do assert(RM.AddGroup(id, nil, "any")) end
end)
okF, whyF = RM.DuplicateNode(id4, { 1 })
Check(not okF and whyF == RM.REFUSE.groupsFull, "and one that would pass the limit on groups")

-- remove, then put back where it was
local id5 = Screenshot()
local node = Raw(id5).conditions[2]
local snap5 = Deep(Raw(id5))
RM.RemoveNode(id5, { 2 })
Check(#Raw(id5).conditions == 2, "the group is removed with what is in it")
local okI, atI = RM.InsertNode(id5, {}, 2, node)
Check(okI and Raw(id5).conditions[2] == node and Deep(Raw(id5)) == snap5 and atI[1] == 2, "and put back as it was: the same table, the same place")
RM.RemoveNode(id5, { 2, 1 })
local lone = node.conditions
Check(RM.InsertNode(id5, {}, 1, "not a node") == false, "something that isn't a node is not put anywhere")
local loop = { type = "group", match = "any", conditions = {} }
loop.conditions[1] = loop
Check(RM.InsertNode(id5, {}, 1, loop) == false, "a loop in memory is refused, not followed")

---------------------------------------------------------------------------
-- 5. A condition this version doesn't know travels untouched
---------------------------------------------------------------------------
local id6 = Make(function(id)
  Put(id, nil, Cond("player", { state = "combat", negate = false }))
  assert(RM.AddGroup(id, nil, "any"))
end)
local foreign = { type = "future", payload = { x = 1, y = { 2, 3 } } }
Raw(id6).conditions[3] = foreign   -- as an import or a newer version would leave it
RM.Invalidate()
local view = RM.Get(id6)
Check(view.conditions[3] and view.conditions[3].provider == nil and view.conditions[3].cond == nil, "read as a condition of an unknown kind")
Check(not view.valid and view.problems[1] and not RM.SetEnabled(id6, true), "it can't be turned on while it is there")
local fsnap = Deep(foreign)
Check(RM.MoveNode(id6, { 3 }, { 2 }, nil) and Raw(id6).conditions[2].conditions[1] == foreign, "it moves into a group like any other")
Check(RM.DuplicateNode(id6, { 2, 1 }) and #Raw(id6).conditions[2].conditions == 2 and Deep(Raw(id6).conditions[2].conditions[2]) == fsnap, "and is copied as it is")
Check(Deep(foreign) == fsnap, "nothing about it changed")
Check(Pl.Sentence(RM.Get(id6).conditions[2].children[1]) == "Unsupported condition", "it reads as an unsupported condition")
Check(Pl.Technical(RM.Get(id6).conditions[2].children[1]):find("\"future\""), "its kind is in the detail line")
Check(Pl.Problem(RM.Get(id6).conditions[2].children[1]):find("kept as saved"), "and the card says it is kept")
Check(RM.SetCondition(id6, { 2, 1 }, Cond("player", { state = "combat" })) == true, "(the model does let one be replaced; the designer only offers Remove and Move for it)")

---------------------------------------------------------------------------
-- 6. The words
---------------------------------------------------------------------------
local id7 = Screenshot()
local v7 = RM.Get(id7)
local function Sent(path) return Pl.Sentence(RM.Node(v7, path)) end
Check(Sent({ 1 }) == "Ranged ammunition needs attention", "the ammunition problem: " .. Sent({ 1 }))
Check(Sent({ 2, 1 }) == "Your class is Warrior" and Sent({ 3 }) == "You are in combat", "a class, combat")
Check(Pl.CondSentence({ type = "player", state = "combat", negate = true }) == "You are not in combat", "not in combat")
Check(Pl.CondSentence({ type = "player", state = "dead", negate = true }) == "You are alive" and Pl.CondSentence({ type = "player", state = "mounted", negate = false }) == "You are mounted", "alive, mounted")
Check(Pl.CondSentence({ type = "equipment", slot = "offHand", what = "shield", negate = true }) == "Your off hand is not a shield", "an off hand without a shield")
Check(Pl.CondSentence({ type = "equipment", slot = "shoulder", what = "empty", negate = false }) == "Your shoulders are empty", "a plural slot")
Check(Pl.CondSentence({ type = "equipment", slot = "any", what = "item", item = 6948, negate = true }) == "You don't have Hearthstone equipped", "a specific item anywhere: " .. tostring(Pl.CondSentence({ type = "equipment", slot = "any", what = "item", item = 6948, negate = true })))
Check(Pl.CondSentence({ type = "ammunition", what = "outOfAmmo" }) == "Ranged ammunition is used up", "ammunition used up")
Check(Pl.CondSentence({ type = "class", negate = false }) == "Your class (none chosen yet)", "an unfinished class")
Check(Pl.CondSentence({ type = "nothing" }) == nil, "a kind it has no words for gives nil (the caller uses the provider's own)")
Check(Pl.Words("all").heading == "All of these must be true" and Pl.Words("any").heading == "At least one of these must be true", "group headings")
Check(Pl.Words("any").short == "Any" and Pl.Words("all").technical:find("AND") and Pl.Words("any").technical:find("OR"), "short and technical forms")

-- the rule as lines: the example from the request
local lines = Pl.SummaryLines(v7)
local texts = {}
for _, l in ipairs(lines) do texts[#texts + 1] = (("  "):rep(l.depth)) .. (l.bullet and "- " or "") .. l.text end
Check(texts[1] == "Shows when all of these are true:", "heading: " .. texts[1])
Check(texts[2] == "  - Ranged ammunition needs attention" and texts[3] == "  - Your class is Warrior or Hunter" and texts[4] == "  - You are in combat",
  "ammunition, a run of classes said once, combat: " .. table.concat(texts, " | "))
Check(#lines == 4, "four lines for three items")
Check(Pl.SummaryLines(v7) == lines, "the same view gives the same lines, from the cache")
-- nothing is left out: every leaf's words are in the lines (a run of classes counts as one)
local function AllText(ls) local t = {} for _, l in ipairs(ls) do t[#t + 1] = l.text end return table.concat(t, "\n") end
local id8 = Make(function(id)
  Put(id, nil, Cond("equipment", { slot = "offHand", what = "shield", negate = true }))
  assert(RM.AddGroup(id, nil, "any"))
  Put(id, { 2 }, Cond("equipment", { slot = "mainHand", what = "empty", negate = false }))
  assert(RM.AddGroup(id, { 2 }, "all"))
  Put(id, { 2, 2 }, Cond("player", { state = "combat", negate = false }))
  Put(id, { 2, 2 }, Cond("player", { state = "mounted", negate = true }))
end)
local text8 = AllText(Pl.SummaryLines(RM.Get(id8)))
for _, want in ipairs({ "Your off hand is not a shield", "Your main hand is empty", "You are in combat", "You are not mounted" }) do
  Check(text8:find(want, 1, true), "nothing left out: " .. want)
end
Check(text8:find("At least one of these is true:") and text8:find("All of these are true:"), "each group has a heading of its own")
-- one condition, an empty group, nothing
local id9 = Make(function(id) Put(id, nil, Cond("player", { state = "combat", negate = false })) end)
Check(Pl.SummaryLines(RM.Get(id9))[1].text == "Shows when: You are in combat.", "one condition is one line")
local id10 = Make(function() end)
Check(Pl.SummaryLines(RM.Get(id10))[1].text:find("add a condition"), "none says to add one, and that it can never show")
local id11 = Make(function(id) assert(RM.AddGroup(id, nil, "any")) end)
Check(Pl.SummaryLines(RM.Get(id11))[1].text:find("nothing in it"), "an empty group says so")
-- reading the words never writes
local before7 = Deep(Raw(id7))
Pl.SummaryLines(RM.Get(id7)); Pl.Entries(); Pl.Explain(RM.Get(id7), E.Run(RM.Get(id7), { slots = {} }, { simulated = true }), "disabled")
Check(Deep(Raw(id7)) == before7, "reading a rule in words changes nothing stored")

-- who it is for
local me = RM.CharacterKey()
Check(Pl.Targeting(RM.Get(id9), me) == "Every character", "every character")
RM.SetScope(id9, "who", "characters"); RM.AddCharacter(id9, me)
Check(Pl.Targeting(RM.Get(id9), me) == "This character only", "this character")
RM.AddCharacter(id9, "Other - Realm")
Check(Pl.Targeting(RM.Get(id9), me) == "2 chosen characters, this one included", "two characters")
RM.SetScope(id9, "class", "HUNTER")
Check(Pl.Targeting(RM.Get(id9), me):find(", only for Hunters"), "a class: " .. Pl.Targeting(RM.Get(id9), me))
Check(RM.Get(id9).scope.class == "HUNTER" and #RM.Get(id9).conditions == 1, "a class in who it is for is not a condition, and the rule has no class in it")
-- the class in a rule stays in the rule: nothing here turns one into the other
local sc = RM.Get(id7).scope
Check(sc.class == nil and RM.Get(id7).conditions[2].group, "the example's classes are conditions in a group, and who it is for has no class")

---------------------------------------------------------------------------
-- 7. The picker: from the registry
---------------------------------------------------------------------------
local entries = Pl.Entries()
local byKey = {}
for _, e in ipairs(entries) do byKey[e.key] = e end
Check(byKey.equipment and byKey["player:combat"] and byKey["player:dead"] and byKey["player:ghost"] and byKey["player:mounted"] and byKey.class and byKey.ammunition, "an entry for each kind, the player's states one each")
Check(byKey["player:combat"].category == "Combat" and byKey.class.category == "Character" and byKey.equipment.category == "Equipment" and byKey.ammunition.category == "Equipment", "categories")
Check(byKey["player:combat"].name == "You are in combat" and byKey["player:combat"].make().state == "combat", "an entry says what it checks and makes the condition for it")
Check(byKey.ammunition.note == nil, "no limit to note here (the client reports ammunition)")
for _, e in ipairs(entries) do Check(e.name ~= "" and e.blurb ~= "" and e.icon and R.Icons.Get(e.icon), "every entry has a name, a line and an icon that exists: " .. e.key) end
Check(Pl.Matches(byKey.class, "clas") and Pl.Matches(byKey.class, "") and not Pl.Matches(byKey.class, "zzz") and Pl.Matches(byKey.ammunition, "EQUIP"), "search: a name, nothing, no match, a category")
-- a kind registered later is offered under Other
C.Register({ type = "future2", label = "A later kind", New = function() return { type = "future2" } end, Check = function(r) return { type = "future2" } end,
  Needs = function() end, Evaluate = function() return "nomatch" end, Summary = function() return "Later" end, Observed = function() return "" end, Scenarios = function() return {} end })
local found
for _, e in ipairs(Pl.Entries()) do if e.key == "kind:future2" then found = e end end
Check(found and found.category == "Other" and found.name == "A later kind", "a kind added later is offered under Other with its own label")
C.providers.future2 = nil
for i, k in ipairs(C.order) do if k == "future2" then table.remove(C.order, i) break end end

---------------------------------------------------------------------------
-- 8. The editor's fields: a change makes a new condition, never edits the one it is given
---------------------------------------------------------------------------
local cond = { type = "equipment", slot = "offHand", what = "shield", negate = true }
local keep = Deep(cond)
local n1 = Pl.WithSubject(cond, "slot:mainHand")
Check(n1.slot == "mainHand" and n1.negate == true and n1.what == "empty", "another slot keeps \"is not\" and takes a value it can have")
Check(Pl.WithSubject(cond, "slot:nothere") == nil, "a slot that doesn't exist makes nothing")
local n2 = Pl.WithSubject(cond, "player")
Check(n2.type == "player" and n2.state == "combat", "the player's kind starts as combat")
Check(Pl.WithSubject(n2, "player").state == "combat" and Pl.WithSubject(n2, "player") ~= n2, "the same kind again is a copy of what it was")
Check(Pl.WithNegate(cond, false).negate == false and Pl.WithValue(cond, "weapon").what == "weapon" and Pl.WithItem(cond, 6948).item == 6948, "operator, value and item")
Check(Pl.WithValue({ type = "player", state = "combat" }, "dead").state == "dead" and Pl.WithValue({ type = "class" }, "MAGE").class == "MAGE", "value of a state and of a class")
Check(Deep(cond) == keep, "none of them touched the condition they were given")
Check(not Pl.HasOperator({ type = "ammunition" }) and Pl.HasOperator(cond), "ammunition has no \"is not\"")
Check(Pl.NeedsItem({ type = "equipment", what = "item" }) and not Pl.NeedsItem(cond), "an item asks for the item")
Check(Pl.ValueLabel({ type = "class" }) == "Choose a class" and Pl.ValueLabel(cond) == "Shield", "labels")
-- Talent specialization in the editor: one value choice names a tree (with its class) or a state
do
  local t = Pl.WithSubject(cond, "talent")
  Check(t.type == "talent" and t.negate == false, "the talent subject makes a talent condition")
  local before = Deep(t)
  local picked = Pl.WithValue(t, "SHAMAN:374")
  Check(picked.class == "SHAMAN" and picked.tree == 374 and picked.state == nil and Deep(t) == before, "a tree choice sets class and tree, and copies")
  local state = Pl.WithValue(picked, "tied")
  Check(state.state == "tied" and state.class == nil and state.tree == nil, "a state choice clears the tree")
  Check(Pl.WithValue(state, "WARRIOR:257").state == nil, "and a tree clears the state")
  Check(Pl.ValueKey(picked) == "SHAMAN:374" and Pl.ValueKey(state) == "tied" and Pl.ValueKey(Pl.WithSubject(cond, "talent")) ~= "tied", "the selected key")
  Check(Pl.ValueLabel(picked) == "Restoration (Shaman)" and Pl.ValueLabel(state) == "Tied talent trees", "labels: " .. Pl.ValueLabel(picked))
  Check(Pl.ValueLabel({ type = "talent" }) == "Choose a specialization", "nothing chosen yet")
  Check(Pl.CondSentence(picked) == "Talent specialization is Restoration (Shaman)" and Pl.CondSentence(Pl.WithNegate(state, true)) == "Talent specialization is not Tied talent trees", "sentences")
  Check(#Pl.ValueChoices(picked) == 2 + 3 * 9 and Pl.HasOperator(picked), "every tree and both states, with is / is not")
  Check(Pl.Help(picked) == "Uses the talent tree with the most spent points. Equal highest totals count as tied.", "help")
  local sv = Pl.SubjectOf(picked)
  Check(sv == "talent", "its subject")
  local found
  for _, e in ipairs(Pl.Entries()) do if e.kind == "talent" then found = e end end
  Check(found and found.category == "Character" and found.make().type == "talent", "the picker offers it")
end
Check(#Pl.Subjects() == #C.SLOTS + 4, "subjects: every slot, ammunition, the player, the class, the talent specialization")
Check(Pl.Help({ type = "ammunition", what = "outOfAmmo" }):find("none your weapon can use"), "help for a choice comes from the choice")

---------------------------------------------------------------------------
-- 9. Why it would or would not show
---------------------------------------------------------------------------
local ctxMage = { character = me, class = "MAGE" }
local function Obs(t)
  local o = { slots = {} }
  for k, val in pairs(t) do o[k] = val end
  return o
end
local AMMO_BAD = { uses = true, ranged = true, needs = "arrow", carries = false }
local AMMO_OK = { uses = true, ranged = true, needs = "arrow", id = 0, kind = "arrow", count = 50 }

-- the example, with a Hunter who needs ammunition and is in combat: all three hold
local v8 = RM.Get(id7)
RM.SetEnabled(id7, true)
local out = E.Run(v8, Obs({ ammo = AMMO_BAD, class = "HUNTER", combat = true }), { character = me, class = "HUNTER" })
local ex = Pl.Explain(v8, out, "showing", { character = me, class = "HUNTER" })
Check(ex.state == "show" and ex.head == "Would show now" and ex.status:find("showing on screen"), "true and showing: would show now")
local met = ex.cards[v8.conditions[1].raw]
Check(met.state == "met" and met.word == "Met" and met.seen == "Used up", "a met condition says Met and what it saw: " .. tostring(met.seen))
Check(ex.groups[v8.conditions[2].raw] == "Met: Your class is Hunter.", "the group says which is met: " .. tostring(ex.groups[v8.conditions[2].raw]))
Check(ex.groups.top == "Every item is met.", "the top level: every item is met")
-- the same facts, but turned off: the conditions match, nothing is on screen
RM.SetEnabled(id7, false)
v8 = RM.Get(id7)
out = E.Run(v8, Obs({ ammo = AMMO_BAD, class = "HUNTER", combat = true }), { character = me, class = "HUNTER" })
ex = Pl.Explain(v8, out, "disabled", { character = me, class = "HUNTER" })
Check(ex.state == "match" and ex.head == "Conditions match now" and ex.status:find("turned off"), "turned off: the conditions match, and it says nothing appears: " .. ex.head)
-- false: the ammunition is fine
out = E.Run(v8, Obs({ ammo = AMMO_OK, class = "HUNTER", combat = true }), { character = me, class = "HUNTER" })
ex = Pl.Explain(v8, out, "hidden", { character = me, class = "HUNTER" })
Check(ex.state == "hidden" and ex.head == "Would stay hidden", "false: would stay hidden")
Check(ex.cards[v8.conditions[1].raw].state == "unmet" and ex.cards[v8.conditions[1].raw].word == "Not met", "the ammunition condition is not met")
Check(ex.groups.top == "Not met: Ranged ammunition needs attention.", "the top level says which: " .. ex.groups.top)
-- a class that isn't one of the two
out = E.Run(v8, Obs({ ammo = AMMO_BAD, class = "MAGE", combat = true }), ctxMage)
ex = Pl.Explain(v8, out, "hidden", ctxMage)
Check(ex.groups[v8.conditions[2].raw] == "None of them is met.", "none of the classes: " .. tostring(ex.groups[v8.conditions[2].raw]))
-- unknown: the class isn't read yet
out = E.Run(v8, Obs({ ammo = AMMO_BAD, combat = true }), { character = me, class = "HUNTER" })
ex = Pl.Explain(v8, out, "waiting", { character = me, class = "HUNTER" })
Check(ex.state == "unknown" and ex.head == "Cannot determine", "unknown: cannot determine")
Check(ex.cards[v8.conditions[2].children[1].raw].state == "unknown" and ex.cards[v8.conditions[2].children[1].raw].word == "Cannot check yet", "the class condition can't be checked yet")
Check(ex.groups[v8.conditions[2].raw] == "None is met so far. Cannot check yet: Your class is Warrior and Your class is Hunter. So this can't be decided yet.", "its group can't be decided: " .. ex.groups[v8.conditions[2].raw])
Check(ex.groups.top:find("Cannot check yet") and ex.groups.top:find("can't be decided"), "and so can't the top: " .. ex.groups.top)
-- an answer that decides the group beside one that can't be checked: said not to change it
local id12 = Make(function(id)
  Put(id, nil, Cond("player", { state = "combat", negate = false }))
  Put(id, nil, Cond("class", { class = "MAGE", negate = false }))
end)
RM.SetMatch(id12, "any")
local v12 = RM.Get(id12)
out = E.Run(v12, Obs({ combat = true }), { simulated = true })
ex = Pl.Explain(v12, out, "disabled", { simulated = true })
Check(out.result == "match" and ex.groups.top == "Met: You are in combat. Something else can't be checked yet, which doesn't change the outcome.", "any: one met, one unknown: decided, and it says the other doesn't matter: " .. ex.groups.top)
RM.SetMatch(id12, "all")
v12 = RM.Get(id12)
out = E.Run(v12, Obs({ combat = false }), { simulated = true })
ex = Pl.Explain(v12, out, "disabled", { simulated = true })
Check(out.result == "nomatch" and ex.groups.top == "Not met: You are in combat. Something else can't be checked yet, which doesn't change the outcome.", "all: one not met, one unknown: not met, and the other doesn't matter: " .. ex.groups.top)
Check(ex.state == "hidden", "and so it would stay hidden, not \"cannot determine\"")
-- not for this character
out = E.Run(v8, Obs({ ammo = AMMO_BAD, class = "HUNTER", combat = true }), { character = me, class = "HUNTER" })
RM.SetScope(id7, "who", "characters"); RM.AddCharacter(id7, "Someone - Else")
v8 = RM.Get(id7)
ex = Pl.Explain(v8, out, "notApplicable", { character = me, class = "HUNTER" })
Check(ex.state == "hidden" and ex.head == "Would stay hidden" and ex.reason:find("other characters") and ex.status:find("not for this character"), "for someone else: hidden, and it says who it is for")
RM.SetScope(id7, "who", "all")

-- a limit of the client, said in a short line
UNITS.uses = nil
c.UnitUsesAmmo = nil
Check(not R.ReminderAmmo.Supported(), "(this client has no way to say whether a weapon takes ammunition)")
RM.Invalidate()
local v13 = RM.Get(id7)
local leaf = v13.conditions[1]
Check(leaf.why and Pl.Capability(leaf) == "Cannot check ammunition on this client.", "the short line: " .. tostring(Pl.Capability(leaf)))
Check(select(2, Pl.Capability(leaf)) == "The client does not report whether this ranged weapon uses ammunition.", "and the longer one, for a tooltip")
Check(Pl.Problem(leaf) == "Cannot check ammunition on this client.", "a card shows the short line, not the technical paragraph")
out = E.Run(v13, Obs({ class = "HUNTER", combat = true }), { simulated = true })
ex = Pl.Explain(v13, out, "invalid", { simulated = true })
Check(ex.state == "invalid" and ex.head == "Cannot determine" and ex.reason == "Cannot check ammunition on this client.", "the whole rule can't be determined, and says why: " .. tostring(ex.reason))
local card = ex.cards[leaf.raw]
Check(card.capability == "Cannot check ammunition on this client." and card.long and card.word == "Cannot check", "the card is marked as a limit of the client")
Check(out.status == "invalid", "the runtime's own handling is unchanged: the rule is invalid and never shows")
-- an old condition of the group at a depth the model reads is not changed by any of this
local entriesNow = Pl.Entries()
for _, e in ipairs(entriesNow) do if e.key == "ammunition" then Check(e.note and e.note:find("can't be turned on here"), "the picker notes it before it is added") end end

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
