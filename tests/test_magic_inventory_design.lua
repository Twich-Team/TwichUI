-- Magic Inventory, the guild bank arrangement (inventory/Design.lua, the design parts of Rules.lua and GuildPlan.lua):
-- synthetic data only; nothing here is the game.
--   * the draft: an item dropped on a tab or a slot, stacks moved, split, combined and returned to automatic placement;
--     quantities are conserved, stack limits hold, a refused or cancelled edit changes nothing;
--   * rules <-> draft: save and reopen gives destinations, exact slots and distinct quantities back; other rules are kept
--     exactly, in place; opening the editor writes nothing; the existing rules' priority is never changed;
--   * the planner: reserved stacks of different sizes for one item, shortages, extras (placed, ambiguous, no room), a reserved
--     slot that holds another item, conflicts with broader rules, unread tabs, read-only and deterministic;
--   * the existing review/deposit never acts on an arrangement rule.
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MIClient("Rich")
local MI = c.TwichUI.MagicInventory
local D = MI.Design
Check(D ~= nil and D.Commit ~= nil and MI.ReplaceRules ~= nil, "the arrangement files are loaded")

---------------------------------------------------------------------------
-- Items and helpers
---------------------------------------------------------------------------
local FACTS = {}
local function Item(id, name, maxStack, class, sub)
  FACTS[id] = { id = id, name = name, icon = 1000 + id, quality = 1, classID = class or 7, subclassID = sub or 5, equipLoc = "",
    bindType = 0, maxStack = maxStack, equipment = false }
end
Item(2589, "Linen Cloth", 20)
Item(2592, "Wool Cloth", 20)
Item(4306, "Silk Cloth", 200)
Item(2447, "Peacebloom", 20, 7, 9)
Item(6948, "Hearthstone", 1, 15, 0)
local function Facts(id) local f = FACTS[id]; if f then return f end return nil, false end
local ctx = { facts = function(id) return FACTS[id] end }

local function Digest(d) return D.Digest(d) end
local function Draft(guild)
  return D.New(guild or "Night Owls", { [1] = { name = "Gear", icon = 1 }, [2] = { name = "Cloth", icon = 2 }, [3] = { name = "Herbs", icon = 3 } }, 4)
end
local function Slot(d, tab, slot) local t = d.tabs[tab]; return t and t.slots[slot] end

---------------------------------------------------------------------------
-- The draft: dropping, moving, splitting, combining
---------------------------------------------------------------------------
do
  local d = Draft()
  local ok = D.AssignTab(d, ctx, 2589, 2)
  Check(ok and d.tabs[2].items[2589] and d.tabs[2].rest[2589], "an item dropped on a tab is assigned to it, with automatic placement")
  Check(next(d.tabs[2].slots) == nil, "an item dropped on a tab reserves no slot")
  local ok2 = D.AssignTab(d, ctx, 2589, 3)
  Check(ok2 and d.tabs[3].rest[2589] and not d.tabs[2].rest[2589] and not d.tabs[2].items[2589], "dropping it on another tab moves the automatic placement there")
  Check(not D.AssignTab(d, ctx, 2589, 9), "a tab that doesn't exist is refused")

  d = Draft()
  local ok3 = D.PlaceSlot(d, ctx, 2589, 2, 7)
  Check(ok3 and Slot(d, 2, 7).id == 2589 and Slot(d, 2, 7).count == 20, "an item dropped on a slot reserves a full stack there")
  Check(d.tabs[2].rest[2589], "the first reservation also says where the extras go")
  Check(not D.PlaceSlot(d, ctx, 2592, 2, 7), "a reserved slot refuses another item")
  Check(not D.PlaceSlot(d, ctx, 2589, 2, 99) and not D.PlaceSlot(d, ctx, 2589, 2, 0), "slots 0 and 99 don't exist")
  Check(D.PlaceSlot(d, ctx, 6948, 2, 8) and Slot(d, 2, 8).count == 1, "an unstackable item reserves one")
  Check(not D.PlaceSlot(d, { facts = function() return nil end }, 2589, 2, 9), "an item the game hasn't described yet can't be reserved")
  Check(D.PlaceSlot(d, ctx, 4306, 3, 1, 500) and Slot(d, 3, 1).count == 200, "a quantity above the stack limit is cut to it, never beyond")

  -- a second reservation in another tab doesn't take the extras from the first
  Check(D.PlaceSlot(d, ctx, 2589, 3, 5, 10) and d.tabs[2].rest[2589] and not d.tabs[3].rest[2589], "a second tab's reservation leaves the extras where they were")
  Check(D.SetExtras(d, ctx, 3, 2589) and d.tabs[3].rest[2589] and not d.tabs[2].rest[2589], "'Extras go here' moves the extras to one tab")
end

-- splitting
do
  local d = Draft()
  D.PlaceSlot(d, ctx, 2589, 2, 1, 20)
  local before = Digest(d)
  for _, q in ipairs({ 0, 20, 21, -3, 2.5 }) do
    Check(not D.Split(d, ctx, 2, 1, q, 2, 2), "splitting off " .. tostring(q) .. " of 20 is refused")
  end
  Check(Digest(d) == before, "refused splits changed nothing")
  Check(not D.Split(d, ctx, 2, 1, 5, 2, 1), "a split can't be placed back on its own slot")
  Check(not D.Split(d, ctx, 2, 5, 5, 2, 2), "a split of nothing is refused")
  Check(D.Split(d, ctx, 2, 1, 5, 2, 2) and Slot(d, 2, 1).count == 15 and Slot(d, 2, 2).count == 5, "a split leaves the remainder and places the new stack")
  Check(D.Split(d, ctx, 2, 1, 5, 3) and Slot(d, 2, 1).count == 10 and Slot(d, 3, 1).count == 5, "a split onto a tab takes its first free slot")
  -- into a stack of the same item: combined up to the limit, overflow stays
  D.PlaceSlot(d, ctx, 2589, 2, 10, 18)
  Check(D.Split(d, ctx, 2, 1, 6, 2, 10) and Slot(d, 2, 10).count == 20 and Slot(d, 2, 1).count == 8, "a split into a stack combines up to the limit and the rest stays in the source")
  Check(select(1, D.Split(d, ctx, 2, 1, 3, 2, 10)) == false and Slot(d, 2, 10).count == 20, "a full stack takes nothing more")
  -- incompatible
  D.PlaceSlot(d, ctx, 2592, 2, 20, 4)
  Check(not D.Split(d, ctx, 2, 1, 2, 2, 20) and Slot(d, 2, 20).count == 4 and Slot(d, 2, 1).count == 8, "another item's stack is never combined with")
  D.PlaceSlot(d, ctx, 6948, 2, 30)
  Check(not D.Split(d, ctx, 2, 30, 1, 2, 31), "a stack of one can't be split")
  local total = 0
  for _, t in pairs(d.tabs) do for _, s in pairs(t.slots) do if s.id == 2589 then total = total + s.count end end end
  Check(total == 38, "the reserved quantity of one item is what was designed: 20 + 18 in all, however it was split and combined (" .. total .. ")")
end

-- combining by moving
do
  local d = Draft()
  D.PlaceSlot(d, ctx, 2589, 2, 1, 12)
  D.PlaceSlot(d, ctx, 2589, 2, 2, 12)
  local ok, msg = D.MoveStack(d, ctx, 2, 2, 2, 1)
  Check(ok and Slot(d, 2, 1).count == 20 and Slot(d, 2, 2).count == 4, "combining 12 and 12 gives 20 and leaves 4 where it was: " .. tostring(msg))
  Check(D.MoveStack(d, ctx, 2, 2, 2, 5) and Slot(d, 2, 5).count == 4 and Slot(d, 2, 2) == nil, "a stack moves to an empty slot")
  D.PlaceSlot(d, ctx, 2592, 2, 6, 3)
  Check(not D.MoveStack(d, ctx, 2, 5, 2, 6) and Slot(d, 2, 5).count == 4 and Slot(d, 2, 6).count == 3, "an incompatible combination is refused and both stay")
  Check(not D.MoveStack(d, ctx, 2, 1, 2, 5) or Slot(d, 2, 1).count + Slot(d, 2, 5).count == 24, "combining never changes the total")
  Check(D.MoveToTab(d, ctx, 2, 5, 3) and Slot(d, 3, 1) ~= nil, "a stack dropped on a tab takes its first free slot")
  Check(D.MoveStack(d, ctx, 2, 1, 2, 1), "dropping a stack where it is changes nothing")
end

-- back to automatic, removal
do
  local d = Draft()
  D.PlaceSlot(d, ctx, 2589, 2, 4, 10)
  Check(D.Unreserve(d, ctx, 2, 4) and Slot(d, 2, 4) == nil and d.tabs[2].items[2589] and d.tabs[2].rest[2589], "back to automatic placement keeps the item in the tab and drops the slot")
  D.PlaceSlot(d, ctx, 2589, 2, 4, 10)
  Check(D.RemoveStack(d, ctx, 2, 4) and d.tabs[2].items[2589] and d.tabs[2].rest[2589], "removing a stack keeps an item that is still placed automatically")
  Check(D.RemoveItem(d, ctx, 2, 2589) and D.TabEmpty(d.tabs[2]), "removing an item empties the tab")
  Check(D.AddCategory(d, ctx, 2, "7:5") and not D.AddCategory(d, ctx, 3, "7:5"), "a category goes to one tab")
  Check(D.RemoveCategory(d, ctx, 2, "7:5") and D.TabEmpty(d.tabs[2]), "a category can be taken out")
  Check(not D.AddCategory(d, ctx, 2, "bad"), "a bad category is refused")
end

-- a fixed random walk over every editing operation: conservation, limits, refusals change nothing
do
  local seed = 12345
  local function Rand(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
  local ids = { 2589, 2592, 4306, 6948 }
  local d = Draft()
  local ok = true
  local why
  local function Totals()
    local t = {}
    for _, tab in pairs(d.tabs) do for _, s in pairs(tab.slots) do t[s.id] = (t[s.id] or 0) + s.count end end
    return t
  end
  for step = 1, 600 do
    local before, totals = Digest(d), Totals()
    local op = Rand(7)
    local id = ids[Rand(#ids)]
    local tab, slot, tab2, slot2 = Rand(3), Rand(8), Rand(3), Rand(8)
    local r, kind
    if op == 1 then r = D.PlaceSlot(d, ctx, id, tab, slot, Rand(25)); kind = "place"
    elseif op == 2 then r = D.MoveStack(d, ctx, tab, slot, tab2, slot2); kind = "move"
    elseif op == 3 then r = D.Split(d, ctx, tab, slot, Rand(25), tab2, slot2); kind = "split"
    elseif op == 4 then r = D.MoveToTab(d, ctx, tab, slot, tab2); kind = "movetab"
    elseif op == 5 then r = D.Unreserve(d, ctx, tab, slot); kind = "unreserve"
    elseif op == 6 then r = D.AssignTab(d, ctx, id, tab); kind = "assign"
    else r = D.SetExtras(d, ctx, tab, id); kind = "extras" end
    local after = Totals()
    if not r and Digest(d) ~= before then ok, why = false, "a refused " .. kind .. " changed the draft at step " .. step end
    if kind == "move" or kind == "split" or kind == "movetab" or kind == "unreserve" and false then
      for _, i in ipairs(ids) do
        if (after[i] or 0) ~= (totals[i] or 0) then ok, why = false, kind .. " changed the total of " .. i .. " at step " .. step end
      end
    end
    for _, tb in pairs(d.tabs) do
      for sl, s in pairs(tb.slots) do
        if s.count < 1 or s.count > FACTS[s.id].maxStack then ok, why = false, "a stack of " .. s.count .. " at step " .. step end
        if not tb.items[s.id] then ok, why = false, "a reserved item missing from the tab's items at step " .. step end
        if sl < 1 or sl > 98 then ok, why = false, "slot out of range" end
      end
    end
    for _, i in ipairs(ids) do
      local n = 0
      for _, tb in pairs(d.tabs) do if tb.rest[i] then n = n + 1 end end
      if n > 1 then ok, why = false, "two tabs take the extras of " .. i .. " at step " .. step end
    end
    if not ok then break end
  end
  Check(ok, "600 random edits keep totals, limits and the one-tab-takes-extras rule: " .. tostring(why))
end

---------------------------------------------------------------------------
-- Rules <-> draft
---------------------------------------------------------------------------
do
  local clean = MI.CleanRule({ id = "rtest1", kind = "guild", enabled = true, design = true, dest = "dtest1",
    include = {}, place = { { slot = 7, id = 2589, count = 5 }, { slot = 7, id = 2592, count = 5 }, { slot = 0, id = 2589, count = 5 },
      { slot = 99, id = 2589, count = 5 }, { slot = 3, id = 2589, count = 0 }, { slot = 3, id = 2589, count = 10000 }, { slot = 4, id = 2589, count = 10 }, { slot = 1, id = "x", count = 1 } },
    rest = { [2589] = true, [2592] = true, [777] = true } })
  Check(clean and clean.design and #clean.place == 2, "only valid reserved stacks are kept (one per slot, 1..98, count 1..9999): " .. tostring(clean and #clean.place))
  Check(clean.place[1].slot == 4 and clean.place[2].slot == 7, "reserved stacks are in slot order")
  Check(clean.include[2589] and not clean.include[777] and not clean.rest[777], "every reserved item is in the include list, and rest holds only listed items")
  Check(MI.CleanRule({ id = "rtest2", kind = "bank", enabled = true, design = true, place = { { slot = 1, id = 2589, count = 1 } }, include = { [2589] = true } }).design == nil,
    "only a guild bank rule can be an arrangement rule")
  Check(MI.CleanRule({ id = "rtest3", kind = "guild", enabled = true, include = { [2589] = true } }).place == nil, "an ordinary rule gets no reserved stacks")
end

local WHERE = {}
local function Dest(tab, name, guild, id)
  id = id or ("dd" .. tab)
  WHERE[id] = { kind = "guild", guild = guild or "Night Owls", tab = tab, tabName = name, tabIcon = tab, id = id }
  return id
end
local function RLoad(rules, extra)
  local cx = { guild = "Night Owls", names = { [1] = { name = "Gear" }, [2] = { name = "Cloth" }, [3] = { name = "Herbs" } }, numTabs = 4,
    resolve = function(id) return WHERE[id] end, facts = Facts }
  for k, v in pairs(extra or {}) do cx[k] = v end
  return D.Load(rules, cx)
end
local function Persist(list)    -- what saving and reading back does to every rule
  local out = {}
  for i, r in ipairs(list) do
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    copy.id = copy.id or ("rnew" .. i)
    out[i] = MI.CleanRule(copy)
  end
  return out
end

do
  -- the example from the brief: two stacks of 5 and one of 10 of one item, plus other items, a category and an automatic item
  local d = Draft()
  D.PlaceSlot(d, ctx, 2589, 2, 3, 5)
  D.PlaceSlot(d, ctx, 2589, 2, 4, 5)
  D.PlaceSlot(d, ctx, 2589, 2, 10, 10)
  D.PlaceSlot(d, ctx, 2592, 2, 12, 20)
  D.AssignTab(d, ctx, 4306, 2)
  D.AddCategory(d, ctx, 3, "7:9")
  D.PlaceSlot(d, ctx, 2447, 3, 90, 7)
  D.PlaceSlot(d, ctx, 2589, 1, 98, 20)   -- the same item reserved in a second tab
  local digest = Digest(d)
  local rules = D.Commit(d, {}, { destFor = function(tab) return Dest(tab, d.names[tab].name) end })
  Check(#rules == 3, "one rule per tab with something in it (" .. #rules .. ")")
  local back = RLoad(Persist(rules))
  Check(Digest(back) == digest, "save and reopen gives every destination, slot and quantity back\n  was: " .. digest .. "\n  now: " .. Digest(back))
  Check(Slot(back, 2, 3).count == 5 and Slot(back, 2, 4).count == 5 and Slot(back, 2, 10).count == 10, "two stacks of 5 and one of 10 stay distinct")
  Check(back.tabs[2].rest[2589] and not back.tabs[1].rest[2589], "the tab that takes the extras is kept")
  Check(#back.advanced == 0, "an arrangement rule is shown, not set aside")
  local rules2 = D.Commit(back, Persist(rules), { destFor = function() error("a tab with a rule needs no new destination") end })
  Check(Digest(RLoad(Persist(rules2))) == digest, "saving what was just loaded changes nothing")
  for i, r in ipairs(rules2) do
    Check(r.id == Persist(rules)[i].id and r.dest == Persist(rules)[i].dest, "a rule keeps its id and destination when rewritten")
  end
end

-- other rules are kept exactly and in place; what the editor can't show is set aside, never rewritten
do
  local other = MI.CleanRule({ id = "rother1", kind = "mail", name = "Mail it", enabled = true, dest = "dmail", cats = { "7:5" } })
  local keep = MI.CleanRule({ id = "rkeep01", kind = "keep", name = "Keep", enabled = true, keep = 5, include = { [2589] = true } })
  local broad = MI.CleanRule({ id = "rbroad1", kind = "guild", name = "Herbs by category", enabled = true, dest = Dest(3, "Herbs"), cats = { "7:9" }, stack = 10 })
  local fancy = MI.CleanRule({ id = "rfancy1", kind = "guild", name = "Fancy", enabled = true, design = true, dest = Dest(2, "Cloth", nil, "ddfancy"), include = { [2592] = true },
    qualities = { [2] = true }, place = { { slot = 1, id = 2592, count = 5 } } })
  local off = MI.CleanRule({ id = "roff001", kind = "guild", name = "Off", enabled = false, design = true, dest = Dest(1, "Gear", nil, "ddoff"), include = { [6948] = true } })
  local elsewhere = MI.CleanRule({ id = "relse01", kind = "guild", name = "Other guild", enabled = true, design = true, dest = Dest(2, "Cloth", "Other Guild", "ddelse"), include = { [2589] = true } })
  local noTab = MI.CleanRule({ id = "rnotab1", kind = "guild", name = "No tab", enabled = true, design = true, dest = "dnowhere", include = { [2589] = true } })
  local renamed = MI.CleanRule({ id = "rrenam1", kind = "guild", name = "Renamed", enabled = true, design = true, dest = Dest(3, "Plants", nil, "ddren"), include = { [2447] = true } })
  local rules = { other, keep, broad, fancy, off, elsewhere, noTab, renamed }
  local d = RLoad(rules)
  Check(D.TabEmpty(d.tabs[1]) and D.TabEmpty(d.tabs[2]) and D.TabEmpty(d.tabs[3]), "none of those is drawn: nothing the editor can't show faithfully is turned into stacks")
  local whys = {}
  for _, a in ipairs(d.advanced) do whys[a.rule.id] = a.why end
  Check(whys.rbroad1 and whys.rfancy1 and whys.roff001 and whys.relse01 and whys.rnotab1 and whys.rrenam1, "each guild bank rule left out says why")
  Check(whys.rfancy1:find("quality") and whys.roff001:find("off") and whys.relse01:find("Other Guild") and whys.rrenam1:find("Plants"), "the reasons are the right ones")
  Check(whys.rother1 == nil and whys.rkeep01 == nil, "mail and keep rules aren't guild bank rules and are not listed")
  -- designing a tab adds a rule at the end and leaves every other rule the same table in the same place
  D.PlaceSlot(d, ctx, 2589, 2, 5, 10)
  local out = D.Commit(d, rules, { destFor = function(tab) return Dest(tab, "Cloth", nil, "ddnew") end })
  Check(#out == #rules + 1, "one rule was added")
  for i = 1, #rules do Check(out[i] == rules[i], "rule " .. i .. " is the same, in the same place") end
  Check(out[#out].design and out[#out].place[1].slot == 5, "the new rule is last: nothing above it changed priority")
  -- a rule rewritten in place keeps its place
  local mine = MI.CleanRule({ id = "rmine01", kind = "guild", name = "Mine", enabled = true, design = true, dest = Dest(2, "Cloth", nil, "ddmine"), include = { [2589] = true },
    place = { { slot = 1, id = 2589, count = 5 } }, rest = { [2589] = true } })
  local list = { other, mine, keep }
  local d2 = RLoad(list)
  Check(Slot(d2, 2, 1).count == 5, "the arrangement rule is loaded")
  D.Split(d2, ctx, 2, 1, 2, 2, 2)
  local out2 = D.Commit(d2, list, { destFor = function() error("no new destination") end })
  Check(#out2 == 3 and out2[1] == other and out2[3] == keep and out2[2].id == "rmine01" and #out2[2].place == 2, "an arrangement rule is rewritten where it was")
  D.RemoveItem(d2, ctx, 2, 2589)
  local out3 = D.Commit(d2, list, { destFor = function() error("no new destination") end })
  Check(#out3 == 2 and out3[1] == other and out3[2] == keep, "emptying a tab drops its arrangement rule and nothing else")
end

-- saving in the game's own storage
do
  c.TwichUIDB.ui = nil
  c.TwichUIDB.magicInventory = nil
  c.TwichUIDB.modules.magicInventory = true
  local clothDest = MI.AddDest("guild", "Old cloth tab")
  MI.SetGuildTab(clothDest, "Night Owls", 2, "Cloth", 133)
  MI.SaveRule({ kind = "mail", name = "Mail linen", enabled = false, cats = { "7:5" }, dest = MI.AddDest("mail", "Bank alt") })
  MI.SaveRule({ kind = "guild", name = "Herbs by category", enabled = true, dest = (function() local x = MI.AddDest("guild", "Herb tab"); MI.SetGuildTab(x, "Night Owls", 3, "Herbs", 134); return x end)(), cats = { "7:9" }, stack = 10 })
  local before = MI.Rules()
  local gen, nDests = MI.Generation(), #MI.Dests()

  local names = { [1] = { name = "Gear", icon = 131 }, [2] = { name = "Cloth", icon = 133 }, [3] = { name = "Herbs", icon = 134 } }
  local function Open()
    return D.Load(MI.Rules(), { guild = "Night Owls", names = names, numTabs = 4, resolve = MI.Resolve, facts = Facts })
  end
  local d = Open()
  Check(MI.Generation() == gen and #MI.Rules() == #before and #MI.Dests() == nDests, "opening the editor writes nothing: no rule, no destination, no change")
  Check(D.TabEmpty(d.tabs[2]) and D.TabEmpty(d.tabs[3]) and #d.advanced == 1, "the existing guild rule is set aside, not drawn")
  D.PlaceSlot(d, ctx, 2589, 2, 3, 5)
  D.PlaceSlot(d, ctx, 2589, 2, 4, 5)
  D.PlaceSlot(d, ctx, 2589, 2, 10, 10)
  D.AssignTab(d, ctx, 2592, 2)
  D.PlaceSlot(d, ctx, 2447, 1, 50, 20)
  local digest = Digest(d)
  Check(MI.Generation() == gen, "editing the draft saves nothing")
  local ok, why = D.Save(d)
  Check(ok, "saving works: " .. tostring(why))
  local after = MI.Rules()
  Check(#after == #before + 2, "two arrangement rules were added (tabs 1 and 2): " .. #after)
  for i = 1, #before do
    local a, b = before[i], after[i]
    local same = a.id == b.id and a.name == b.name and a.kind == b.kind and a.enabled == b.enabled and a.dest == b.dest and a.stack == b.stack and a.keep == b.keep
    Check(same, "existing rule " .. i .. " is untouched and in its place")
  end
  Check(after[#after - 1].design and after[#after].design, "the new rules come last, after every existing rule")
  local d2 = Open()
  Check(Digest(d2) == digest, "reopening shows the saved arrangement exactly\n  was: " .. digest .. "\n  now: " .. Digest(d2))
  Check(#d2.advanced == 1, "the advanced rule is still set aside, still listed")
  Check(#MI.Dests() == nDests + 1, "one destination was made (tab 1); the existing one for tab 2 was reused: " .. #MI.Dests() - nDests)
  -- change and save again: the same two rules, rewritten in place
  D.Split(d2, ctx, 2, 10, 4, 2, 11)
  D.Save(d2)
  Check(#MI.Rules() == #after, "saving again adds no rule")
  Check(Digest(Open()) == Digest(d2), "the second save reads back the same")
  -- the tab emptied: its rule goes
  D.RemoveItem(d2, ctx, 1, 2447)
  D.Save(d2)
  Check(#MI.Rules() == #after - 1, "an emptied tab's rule is dropped")

  -- a failed save writes nothing
  c.TwichUIDB.ui = nil
  c.TwichUIDB.magicInventory = nil
  for i = 1, MI.MAX_DESTS do MI.AddDest("mail", "Friend " .. i) end
  local full = D.Load(MI.Rules(), { guild = "Night Owls", names = names, numTabs = 4, resolve = MI.Resolve, facts = Facts })
  D.PlaceSlot(full, ctx, 2589, 2, 1, 5)
  local g2, n2 = MI.Generation(), #MI.Rules()
  local ok2, why2 = D.Save(full)
  Check(ok2 == false and why2 and MI.Generation() == g2 and #MI.Rules() == n2, "with no destination left to make, saving refuses and writes nothing: " .. tostring(why2))
  Check(D.Dirty(full), "an unsaved draft stays unsaved")
end

---------------------------------------------------------------------------
-- The planner
---------------------------------------------------------------------------
local NIL = {}
local function Cells(slots)
  local out = {}
  for s, v in pairs(slots or {}) do out[s] = { id = v[1], count = v[2], locked = v[3] or false, icon = 1000 + (v[1] or 0) } end
  return out
end
local function Tab(name, slots, extra)
  local t = { name = name, icon = 133, viewable = true, canDeposit = true, canWithdraw = true, state = "live", slots = Cells(slots or {}), readAt = 100, age = 0 }
  for k, v in pairs(extra or {}) do if v == NIL then t[k] = nil else t[k] = v end end
  return t
end
local function Bank(tabs, extra)
  local b = { guild = "Night Owls", open = true, current = 1, numTabs = 0, seq = 1, now = 100, tabs = tabs }
  for i in pairs(tabs) do if i > b.numTabs then b.numTabs = i end end
  for k, v in pairs(extra or {}) do b[k] = v end
  return b
end
local function Bag(bag, slot, id, count)
  return { bag = bag, slot = slot, id = id, count = count, link = "|Hitem:" .. id .. "|h", bound = false, locked = false, quest = false,
    conjured = false, inSet = false, facts = FACTS[id] }
end
local PW = {}
local function ARule(id, tab, fields)
  local r = { id = id, name = id, kind = "guild", enabled = true, design = true, cats = {}, qualities = {}, include = {}, exclude = {}, equip = "any",
    bind = "any", keep = 0, stack = 0, dest = "p" .. id, place = {}, rest = {} }
  for k, v in pairs(fields or {}) do r[k] = v end
  for _, p in ipairs(r.place) do r.include[p.id] = true end
  PW[r.dest] = { kind = "guild", guild = "Night Owls", tab = tab, tabName = (fields and fields.tabName) or ({ "Gear", "Cloth", "Herbs", "Ore" })[tab], label = id, id = r.dest }
  return r
end
local function Plain(id, tab, fields)
  local r = ARule(id, tab, fields)
  r.design, r.place, r.rest = nil, nil, nil
  return r
end
local function Plan(mode, rules, bank, stacks, extra)
  local o = { mode = mode, rules = rules, bank = bank, stacks = stacks or {}, facts = Facts, guildNow = "Night Owls",
    resolve = function(dest) return PW[dest] end, never = function() return false end, split = false, made = 1, generation = 1 }
  for k, v in pairs(extra or {}) do o[k] = v end
  return MI.BuildGuildPlan(o)
end
local function Proposed(plan, tab, slot) return plan.tabs[tab] and plan.tabs[tab].proposed and plan.tabs[tab].proposed[slot] end
local function Alloc(plan, tab, slot) for _, a in ipairs(plan.design.allocs) do if a.tab == tab and a.slot == slot then return a end end end
local function Untouched(plan, id, reason)
  for _, u in ipairs(plan.untouched) do if u.id == id and (reason == nil or u.reason == reason) then return u end end
end
local function Total(plan, id)
  local n = 0
  for i = 1, plan.numTabs or 0 do
    local v = plan.tabs[i]
    if v and v.proposed then for _, cell in pairs(v.proposed) do if cell.id == id and not cell.ghost then n = n + (cell.count or 0) end end end
  end
  return n
end
local function Deep(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local out = {}
  seen[t] = out
  for k, v in pairs(t) do out[Deep(k, seen)] = Deep(v, seen) end
  return out
end
local function Same(a, b, seen)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do if not Same(v, b[k], seen) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local LINEN = { { slot = 3, id = 2589, count = 5 }, { slot = 4, id = 2589, count = 5 }, { slot = 10, id = 2589, count = 10 } }

-- deposit: distinct reserved stacks of one item
do
  local rule = ARule("a1", 2, { place = LINEN, rest = { [2589] = true } })
  local bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") })
  local plan = Plan("deposit", { rule }, bank, { Bag(0, 1, 2589, 20), Bag(0, 2, 2589, 15) }, { split = true })
  Check(Proposed(plan, 2, 3).count == 5 and Proposed(plan, 2, 4).count == 5 and Proposed(plan, 2, 10).count == 10, "two stacks of 5 and one of 10 are reserved separately, not one global stack size")
  Check(Total(plan, 2589) == 35, "every item is somewhere: 35 held, 35 placed")
  local extras = 0
  for s, cell in pairs(plan.tabs[2].proposed) do
    if cell.id == 2589 and s ~= 3 and s ~= 4 and s ~= 10 then extras = extras + cell.count; Check(cell.count <= 20, "no extra stack is above the stack limit") end
  end
  Check(extras == 15, "the extras (15) went to free slots of the tab, outside the reserved slots")
  Check(plan.summary.design.reserved == 3 and plan.summary.design.filled == 3 and plan.summary.design.short == 0, "the summary counts three reserved stacks, all filled")
  Check(plan.design.overflow[1] and plan.design.overflow[1].state == "placed" and plan.design.overflow[1].qty == 15, "the extras are reported as placed")
  Check(Alloc(plan, 2, 3).want == 5 and Alloc(plan, 2, 3).have == 5 and Proposed(plan, 2, 3).want == 5 and Proposed(plan, 2, 3).reserved, "each reserved cell carries what was wanted beside what it holds")

  -- without splitting the planner can't take 5 out of a stack of 15 or 20: those operations are listed and blocked
  local blocked = Plan("deposit", { rule }, bank, { Bag(0, 1, 2589, 20), Bag(0, 2, 2589, 15) }, { split = false })
  Check(blocked.summary.blockedOps > 0 and blocked.summary.splits > 0, "operations that need a split are listed and blocked while splitting isn't checked")
  for _, o in ipairs(blocked.ops) do Check(not o.split or o.status == "blocked", "a splitting operation is never marked ok") end
  local exact = Plan("deposit", { rule }, bank, { Bag(0, 1, 2589, 5), Bag(0, 2, 2589, 5), Bag(0, 3, 2589, 10) }, { split = false })
  Check(exact.summary.blockedOps == 0 and exact.summary.design.filled == 3, "stacks that fit exactly need no split and nothing is blocked")
end

-- deposit: not enough stock
do
  local rule = ARule("a2", 2, { place = LINEN, rest = { [2589] = true } })
  local bank = Bank({ [2] = Tab("Cloth") })
  local plan = Plan("deposit", { rule }, bank, { Bag(0, 1, 2589, 8) }, { split = true })
  Check(Total(plan, 2589) == 8, "nothing is invented: 8 held, 8 placed")
  local a3, a4, a10 = Alloc(plan, 2, 3), Alloc(plan, 2, 4), Alloc(plan, 2, 10)
  Check(a3.have == 5 and a3.state == "ok" and a4.have == 3 and a4.state == "short" and a4.short == 2 and a10.have == 0 and a10.short == 10, "the first stack is filled, the next is short by 2, the last is empty")
  Check(plan.summary.design.short == 2 and plan.summary.design.shortQty == 12 and plan.summary.design.filled == 1, "the summary says what is missing: 12")
  local ghost = Proposed(plan, 2, 10)
  Check(ghost and ghost.ghost and ghost.count == 0 and ghost.want == 10 and ghost.short == 10, "an empty reserved slot is a labelled ghost: wanted 10, holds none")
  Check(Proposed(plan, 2, 4).count == 3 and Proposed(plan, 2, 4).short == 2, "a partly filled slot says how far it is from its target")
  Check(plan.tabs[2].changed == true, "the preview still shows real changes")
  -- nothing in the bags at all
  local none = Plan("deposit", { rule }, bank, {}, {})
  Check(none.summary.design.short == 3 and none.summary.design.shortQty == 20 and #none.ops == 0, "with nothing in the bags every reserved stack is short and no operation is made")
  Check(not none.tabs[2].changed, "ghosts alone are not changes")
end

-- deposit: extras (ambiguous, no room, a reserved slot that holds something else, top-ups)
do
  local bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") })
  local a = ARule("b1", 2, { place = { { slot = 3, id = 2589, count = 5 } } })
  local b = ARule("b2", 3, { place = { { slot = 1, id = 2589, count = 5 } } })
  local plan = Plan("deposit", { a, b }, bank, { Bag(0, 1, 2589, 5), Bag(0, 2, 2589, 5), Bag(0, 3, 2589, 7) }, { split = true })
  Check(Alloc(plan, 2, 3).state == "ok" and Alloc(plan, 3, 1).state == "ok", "reserved stacks in two tabs are both filled")
  local u = Untouched(plan, 2589, "extras-ambiguous")
  Check(u and u.count == 7 and u.class == "blocked", "with no tab that takes the extras they stay in the bags, and it says why")
  Check(plan.design.overflow[1].state == "unmanaged" and plan.design.overflow[1].code == "extras-ambiguous", "the overflow policy is reported as unmanaged")
  b.rest = { [2589] = true }
  local plan2 = Plan("deposit", { a, b }, bank, { Bag(0, 1, 2589, 5), Bag(0, 2, 2589, 5), Bag(0, 3, 2589, 7) }, { split = true })
  Check(Untouched(plan2, 2589, "extras-ambiguous") == nil and Total(plan2, 2589) == 17, "naming the tab that takes the extras places them all")
  local extraTab = 0
  for s, cell in pairs(plan2.tabs[3].proposed) do if cell.id == 2589 and s ~= 1 then extraTab = extraTab + cell.count end end
  Check(extraTab == 7, "the extras went to the tab that takes them (tab 3)")
  -- one tab only: no flag needed
  local solo = Plan("deposit", { ARule("b3", 2, { place = { { slot = 3, id = 2589, count = 5 } } }) }, bank, { Bag(0, 1, 2589, 12) }, { split = true })
  Check(Total(solo, 2589) == 12 and Untouched(solo, 2589) == nil, "an item in one tab only has an unambiguous place for its extras")

  -- no room for the extras
  local slots = {}
  for s = 1, 98 do slots[s] = { 6948, 1 } end
  slots[3] = nil
  local fullBank = Bank({ [2] = Tab("Cloth", slots) })
  local tight = Plan("deposit", { ARule("b4", 2, { place = { { slot = 3, id = 2589, count = 5 } }, rest = { [2589] = true } }) }, fullBank, { Bag(0, 1, 2589, 12) }, { split = true })
  Check(Proposed(tight, 2, 3).count == 5, "the reserved slot is still filled")
  local full = Untouched(tight, 2589, "tab-full")
  Check(full and full.count == 7 and full.class == "blocked", "extras with no free slot stay in the bags and say so")
  Check(tight.design.overflow[#tight.design.overflow].state == "unmanaged", "no room is reported as unmanaged extras")

  -- another item in the reserved slot is never moved
  local taken = Plan("deposit", { ARule("b5", 2, { place = LINEN, rest = { [2589] = true } }) }, Bank({ [2] = Tab("Cloth", { [3] = { 2447, 4 } }) }),
    { Bag(0, 1, 2589, 20) }, { split = true })
  local at = Alloc(taken, 2, 3)
  Check(at.state == "blocked" and at.code == "slot-taken" and at.why:find("Peacebloom"), "a reserved slot that holds another item is blocked, not cleared")
  Check(Proposed(taken, 2, 3).id == 2447 and Proposed(taken, 2, 3).count == 4, "the item there stays")
  Check(Proposed(taken, 2, 4).count == 5 and Proposed(taken, 2, 10).count == 10, "the other reserved stacks are still filled")
  Check(Total(taken, 2589) == 15 and Untouched(taken, 2589, "tab-full") == nil, "what the blocked slot was for stays in the bags: it isn't scattered as extras")
  for _, o in ipairs(taken.ops) do Check(not (o.to.tab == 2 and o.to.slot == 3), "nothing is deposited into the blocked slot") end
  -- a stack of the item already there is topped up, never emptied
  local topup = Plan("deposit", { ARule("b6", 2, { place = { { slot = 3, id = 2589, count = 10 } } }) }, Bank({ [2] = Tab("Cloth", { [3] = { 2589, 4 } }) }),
    { Bag(0, 1, 2589, 6) }, { split = true })
  Check(Proposed(topup, 2, 3).count == 10 and Alloc(topup, 2, 3).state == "ok" and topup.ops[1].kind == "merge", "an existing stack of the item is topped up to its target")
  local over = Plan("deposit", { ARule("b7", 2, { place = { { slot = 3, id = 2589, count = 5 } } }) }, Bank({ [2] = Tab("Cloth", { [3] = { 2589, 9 } }) }), {}, {})
  Check(Proposed(over, 2, 3).count == 9 and Alloc(over, 2, 3).state == "ok", "a stack above its target is left as it is (nothing is removed)")
  -- a reservation that asks for more than the item stacks to is blocked, never cut down
  local big = Plan("deposit", { ARule("b8", 2, { place = { { slot = 3, id = 2589, count = 50 } } }) }, bank, { Bag(0, 1, 2589, 20) }, { split = true })
  Check(Alloc(big, 2, 3).state == "blocked" and Alloc(big, 2, 3).code == "target-too-big", "a quantity above the item's stack limit is blocked")
end

-- a reserved slot is kept for its item
do
  local bank = Bank({ [2] = Tab("Cloth") })
  local design = ARule("c1", 2, { place = { { slot = 1, id = 2589, count = 5 }, { slot = 2, id = 2589, count = 5 }, { slot = 3, id = 2589, count = 5 } }, rest = { [2589] = true } })
  local wool = Plain("c2", 2, { include = { [2592] = true } })
  local plan = Plan("deposit", { design, wool }, bank, { Bag(0, 1, 2592, 8), Bag(0, 2, 2592, 9) }, { split = true })
  local used = {}
  for s, cell in pairs(plan.tabs[2].proposed) do if cell.id == 2592 then used[s] = true end end
  Check(next(used) ~= nil and not used[1] and not used[2] and not used[3], "another rule's items never take a reserved slot, even an empty one")
  for _, o in ipairs(plan.ops) do Check(o.id ~= 2592 or o.to.slot > 3, "no operation targets a reserved slot except for its own item") end
end

-- conflicts with broader rules, and who owns an item
do
  local bank = Bank({ [2] = Tab("Cloth"), [3] = Tab("Herbs") })
  local broadAbove = Plain("d1", 3, { cats = { "7:5" } })
  local design = ARule("d2", 2, { place = { { slot = 3, id = 2589, count = 5 } }, rest = { [2589] = true } })
  local plan = Plan("deposit", { broadAbove, design }, bank, { Bag(0, 1, 2589, 5) }, { split = true })
  local conflict = plan.design.conflicts[1]
  Check(conflict and conflict.kind == "overridden" and conflict.id == 2589 and conflict.by == "d1" and conflict.rule == "d2", "a broader rule above the arrangement is reported as taking the item")
  Check(Proposed(plan, 3, 1) and Proposed(plan, 3, 1).id == 2589 and not (Proposed(plan, 2, 3)), "the earlier rule keeps the item: priority is the list's order, nothing is overwritten")
  Check(#plan.design.allocs == 0 or Alloc(plan, 2, 3) == nil or Alloc(plan, 2, 3).have == 0, "the arrangement doesn't fill a slot for an item another rule owns")
  local broadBelow = Plain("d3", 3, { cats = { "7:5" } })
  local plan2 = Plan("deposit", { design, broadBelow }, bank, { Bag(0, 1, 2589, 5) }, { split = true })
  Check(plan2.design.conflicts[1] and plan2.design.conflicts[1].kind == "shadows" and plan2.design.conflicts[1].by == "d3", "a broader rule below is shadowed, and said to be")
  Check(Proposed(plan2, 2, 3) and Proposed(plan2, 2, 3).count == 5, "the arrangement owns the item when it comes first")
  -- the editor's own check agrees
  local list = { broadAbove, design }
  local cs = D.Conflicts(list, { resolve = function(id) return PW[id] end, facts = Facts })
  Check(#cs == 1 and cs[1].kind == "overridden" and cs[1].tab == 2, "Design.Conflicts finds it from the rules alone")
end

-- unread tabs, renamed tabs, protections
do
  local rule = ARule("e1", 2, { place = LINEN, rest = { [2589] = true } })
  local unread = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", nil, { slots = NIL, state = "unread" }) })
  local plan = Plan("deposit", { rule }, unread, { Bag(0, 1, 2589, 20) }, { split = true })
  Check(#plan.ops == 0 and plan.summary.design.unknown == 3, "an unread tab is unknown, not empty: nothing is planned into it")
  Check(Alloc(plan, 2, 3).state == "unknown", "its reserved stacks are 'can't tell'")
  local renamed = Plan("deposit", { ARule("e2", 2, { place = LINEN, tabName = "Old name" }) }, Bank({ [2] = Tab("Cloth") }), { Bag(0, 1, 2589, 20) }, { split = true })
  Check(#renamed.ops == 0 and renamed.summary.design.blocked == 3, "a renamed tab blocks the arrangement for it")
  local never = Plan("deposit", { rule }, Bank({ [2] = Tab("Cloth") }), { Bag(0, 1, 2589, 20) }, { split = true, never = function(id) return id == 2589 end })
  Check(#never.ops == 0 and Untouched(never, 2589, "never"), "the Never transfer list still protects an item the arrangement wants")
  local stale = Plan("deposit", { rule }, Bank({ [2] = Tab("Cloth") }, { open = false }), { Bag(0, 1, 2589, 20) }, { split = true })
  Check(stale.freshness == "stale", "a closed bank makes the plan stale")
end

-- reorganize
do
  local rule = ARule("f1", 2, { place = { { slot = 3, id = 2589, count = 20 } }, rest = { [2589] = true } })
  local bank = Bank({ [1] = Tab("Gear", { [5] = { 2589, 20 } }), [2] = Tab("Cloth", { [9] = { 2589, 10 } }) })
  local plan = Plan("reorganize", { rule }, bank, {}, { split = true })
  Check(Proposed(plan, 2, 3).count == 20, "a stack is gathered into its reserved slot")
  Check(Proposed(plan, 1, 5) == nil and Proposed(plan, 2, 9) == nil and Proposed(plan, 2, 1).count == 10, "the extra stack is laid out from the first slot (packed), leaving the reserved slot alone")
  Check(Total(plan, 2589) == 30 and #plan.ops == 2 and not plan.ops[1].split and not plan.ops[2].split, "two whole stacks moved: nothing lost, no split")

  -- not enough
  local short = Plan("reorganize", { ARule("f2", 2, { place = { { slot = 3, id = 2589, count = 20 }, { slot = 4, id = 2589, count = 20 } }, rest = { [2589] = true } }) },
    Bank({ [1] = Tab("Gear", { [5] = { 2589, 12 } }), [2] = Tab("Cloth") }), {}, { split = true })
  Check(Alloc(short, 2, 3).have == 12 and Alloc(short, 2, 3).state == "short" and Alloc(short, 2, 4).have == 0, "the bank has 12 of the 40 reserved: the first slot gets them, the rest is missing")
  Check(Total(short, 2589) == 12 and short.summary.design.shortQty == 28, "nothing is invented: 12 in the bank, 12 after, 28 missing")

  -- the item in the slot is another's
  local occupied = Plan("reorganize", { rule }, Bank({ [1] = Tab("Gear", { [5] = { 2589, 20 } }), [2] = Tab("Cloth", { [3] = { 2447, 4 } }) }), {}, { split = true })
  Check(Alloc(occupied, 2, 3).state == "ok" and Proposed(occupied, 2, 3).id == 2589 and Proposed(occupied, 2, 98).id == 2447, "an item the arrangement doesn't name is moved away to the far end, and the reserved slot is filled")
  Check(Total(occupied, 2589) == 20 and Total(occupied, 2447) == 4, "nothing is lost")
  local kept = Plan("reorganize", { rule }, Bank({ [1] = Tab("Gear", { [5] = { 2589, 20 } }), [2] = Tab("Cloth", { [3] = { 2447, 4 } }) }), {}, { split = true, never = function(id) return id == 2447 end })
  Check(Alloc(kept, 2, 3).state == "blocked" and Alloc(kept, 2, 3).code == "slot-taken" and Proposed(kept, 2, 3).id == 2447, "an item on the Never transfer list is left where it is, and the reservation is blocked")
  Check(Total(kept, 2589) == 20 and Proposed(kept, 1, 5).count == 20, "the stack that wanted the slot stays put")

  -- an arrangement item that has to leave first does, then the slot is filled
  local linenRule = ARule("f3", 2, { place = { { slot = 3, id = 2589, count = 20 } }, rest = { [2589] = true } })
  local woolRule = ARule("f4", 2, { place = { { slot = 7, id = 2592, count = 9 } }, rest = { [2592] = true } })
  local swap = Plan("reorganize", { linenRule, woolRule }, Bank({ [1] = Tab("Gear", { [5] = { 2589, 20 } }), [2] = Tab("Cloth", { [3] = { 2592, 9 } }) }), {}, { split = true })
  Check(Proposed(swap, 2, 3) and Proposed(swap, 2, 3).id == 2589 and Proposed(swap, 2, 7) and Proposed(swap, 2, 7).id == 2592, "a stack in the way that belongs elsewhere in the arrangement moves out first")
  Check(Alloc(swap, 2, 3).state == "ok" and Alloc(swap, 2, 7).state == "ok", "both reserved stacks are filled")

  -- extras: gathered into the tab that takes them, in stacks of at most the limit
  local extra = Plan("reorganize", { ARule("f5", 2, { place = { { slot = 3, id = 2589, count = 20 } }, rest = { [2589] = true } }) },
    Bank({ [1] = Tab("Gear", { [5] = { 2589, 20 }, [6] = { 2589, 20 }, [7] = { 2589, 10 } }), [2] = Tab("Cloth") }), {}, { split = true })
  Check(Total(extra, 2589) == 50, "50 in the bank, 50 after")
  local counts = {}
  for s, cell in pairs(extra.tabs[2].proposed) do if cell.id == 2589 then counts[#counts + 1] = cell.count; Check(cell.count <= 20, "no stack above the limit") end end
  table.sort(counts)
  Check(#counts == 3 and counts[1] == 10 and counts[2] == 20 and counts[3] == 20, "the reserved 20 and the extras 20 and 10 are all in tab 2")
  Check(extra.design.overflow[1] and extra.design.overflow[1].state == "placed", "extras placed are reported")

  -- ambiguous extras stay where they are
  local ambiguous = Plan("reorganize", { ARule("f6", 2, { place = { { slot = 3, id = 2589, count = 5 } } }), ARule("f7", 3, { place = { { slot = 1, id = 2589, count = 5 } } }) },
    Bank({ [1] = Tab("Gear", { [5] = { 2589, 12 } }), [2] = Tab("Cloth"), [3] = Tab("Herbs") }), {}, { split = true })
  Check(Untouched(ambiguous, 2589, "extras-ambiguous"), "extras with no single tab to go to stay where they are")

  -- splitting not allowed
  local nosplit = Plan("reorganize", { ARule("f8", 2, { place = { { slot = 3, id = 2589, count = 5 } }, rest = { [2589] = true } }) },
    Bank({ [1] = Tab("Gear", { [5] = { 2589, 20 } }), [2] = Tab("Cloth") }), {}, { split = false })
  Check(nosplit.summary.blockedOps == 1 and nosplit.ops[1].status == "blocked" and nosplit.ops[1].code == "needs-split", "taking 5 from a stack of 20 is a split, listed and blocked")
  -- unread tab and no withdraw
  local nowd = Plan("reorganize", { rule }, Bank({ [1] = Tab("Gear", { [5] = { 2589, 20 } }, { canWithdraw = false }), [2] = Tab("Cloth") }), {}, { split = true })
  Check(#nowd.ops == 0 and Untouched(nowd, 2589, "no-withdraw"), "a tab the rank can't take from gives nothing")
end

-- read-only, deterministic, conserving, over random banks
do
  local seed = 777
  local function Rand(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
  local ids = { 2589, 2592, 2447, 4306 }
  local bad
  for case = 1, 80 do
    local slots1, slots2 = {}, {}
    for _ = 1, Rand(12) do slots1[Rand(30)] = { ids[Rand(4)], Rand(20) } end
    for _ = 1, Rand(12) do slots2[Rand(30)] = { ids[Rand(4)], Rand(20) } end
    local place, rest = {}, {}
    local used = {}
    for _ = 1, Rand(5) do
      local s = Rand(30)
      if not used[s] then used[s] = true; local id = ids[Rand(2)]; place[#place + 1] = { slot = s, id = id, count = Rand(20) }; rest[id] = true end
    end
    local rules = { ARule("g1", 2, { place = place, rest = rest }) }
    if Rand(3) == 1 then rules[#rules + 1] = Plain("g2", 3, { include = { [2447] = true } }) end
    local bank = Bank({ [1] = Tab("Gear", slots1), [2] = Tab("Cloth", slots2), [3] = Tab("Herbs") })
    local stacks = {}
    for i = 1, Rand(4) do stacks[#stacks + 1] = Bag(0, i, ids[Rand(4)], Rand(20)) end
    for _, mode in ipairs({ "deposit", "reorganize" }) do
      for _, split in ipairs({ false, true }) do
        local inB, inS = Deep(bank), Deep(stacks)
        local plan = Plan(mode, rules, bank, mode == "deposit" and stacks or {}, { split = split })
        local again = Plan(mode, rules, bank, mode == "deposit" and stacks or {}, { split = split })
        if not (Same(inB, bank) and Same(inS, stacks)) then bad = "inputs were edited in case " .. case end
        if #plan.ops ~= #again.ops or plan.summary.design.short ~= again.summary.design.short then bad = "not deterministic in case " .. case end
        for _, id in ipairs(ids) do
          local before = 0
          for i = 1, 3 do for _, cell in pairs(bank.tabs[i].slots) do if cell.id == id then before = before + cell.count end end end
          local bags = 0
          if mode == "deposit" then for _, st in ipairs(stacks) do if st.id == id then bags = bags + st.count end end end
          local after = Total(plan, id)
          if mode == "reorganize" and after ~= before then bad = ("reorganize changed the total of %d (%d to %d) in case %d"):format(id, before, after, case) end
          if mode == "deposit" and (after < before or after > before + bags) then bad = ("deposit total out of range for %d in case %d"):format(id, case) end
        end
        for i = 1, 3 do
          for s, cell in pairs(plan.tabs[i].proposed or {}) do
            if not cell.ghost and FACTS[cell.id] and cell.count > FACTS[cell.id].maxStack and not (bank.tabs[i].slots[s] and bank.tabs[i].slots[s].count == cell.count) then
              bad = "a stack above the limit appeared in case " .. case
            end
          end
        end
        -- a reserved slot never ends up holding another item that wasn't already there
        for _, a in ipairs(plan.design.allocs) do
          local cell = plan.tabs[a.tab] and plan.tabs[a.tab].proposed and plan.tabs[a.tab].proposed[a.slot]
          local was = bank.tabs[a.tab] and bank.tabs[a.tab].slots[a.slot]
          if cell and not cell.ghost and cell.id ~= a.id and not (was and was.id == cell.id) then bad = "a foreign item took a reserved slot in case " .. case end
        end
      end
    end
    if bad then break end
  end
  Check(bad == nil, "320 random plans: inputs untouched, repeatable, totals conserved, limits kept, reserved slots kept" .. (bad and (": " .. bad) or ""))
end

-- the rules page's existing deposit never acts on an arrangement rule
do
  c.TwichUIDB.ui = nil
  c.TwichUIDB.magicInventory = nil
  c.TwichUIDB.modules.magicInventory = true
  c.IsInGuild = function() return true end
  c.GetGuildInfo = function() return "Night Owls", "Member", 3 end
  c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 10 }, [2] = { 2592, 6 } } } })
  local dest = MI.AddDest("guild", "Cloth tab")
  MI.SetGuildTab(dest, "Night Owls", 2, "Cloth", 133)
  MI.SaveRule({ kind = "guild", design = true, name = "Arrangement: Cloth", enabled = true, dest = dest, include = { [2589] = true },
    place = { { slot = 1, id = 2589, count = 5 } }, rest = { [2589] = true } })
  MI.SaveRule({ kind = "guild", name = "Wool", enabled = true, dest = dest, include = { [2592] = true } })
  local plan = MI.CurrentPlan("guild")
  local moves = {}
  for _, g in ipairs(plan.groups) do for _, e in ipairs(g.entries) do moves[e.id] = true end end
  Check(not moves[2589], "an arrangement item is never offered to the deposit review")
  local attention
  for _, a in ipairs(plan.attention) do if a.rule == "Arrangement: Cloth" then attention = a end end
  Check(attention and attention.code == "design-only", "it is listed as needing attention, with the reason")
  Check(moves[2592], "an ordinary rule below it is not affected")
end


---------------------------------------------------------------------------
-- Stack sizes and layouts: the player lists the items a tab takes and the size to spread them in; the slots are the addon's business
---------------------------------------------------------------------------
do
  -- the pure parts
  Check(table.concat(D.Pieces(45, 20), ",") == "20,20,5" and #D.Pieces(0, 20) == 0 and table.concat(D.Pieces(7, 20), ",") == "7", "a total is spread in stacks of the size, the last one smaller")
  local list = { { id = 1, pieces = { 5, 5, 5 } }, { id = 2, pieces = { 5 } }, { id = 3, pieces = { 5, 5 } } }
  local function Slots(style, blocked)
    local out = {}
    for _, c in ipairs((D.Layout(list, style, blocked))) do out[#out + 1] = c.id .. "@" .. c.slot end
    return table.concat(out, " ")
  end
  Check(Slots("packed") == "1@1 1@2 1@3 2@4 3@5 3@6", "packed: from the first slot, no gaps: " .. Slots("packed"))
  Check(Slots("spaced") == "1@1 1@2 1@3 2@5 3@7 3@8", "spaced: one empty slot between different items: " .. Slots("spaced"))
  Check(Slots("columns") == "1@1 1@2 1@3 2@15 3@29 3@30", "columns: each item starts a new column of 14: " .. Slots("columns"))
  Check(Slots("packed", function(s) return s == 2 end) == "1@1 1@3 1@4 2@5 3@6 3@7", "a blocked slot is stepped over")
  local many = {}
  for i = 1, 100 do many[i] = 5 end
  local _, unfit = D.Layout({ { id = 1, pieces = many } }, "packed")
  Check(unfit == 2, "stacks beyond the 98 slots are counted, not placed")

  -- the draft: a size, a layout, and saving and loading them
  local d = Draft()
  D.AssignTab(d, ctx, 2589, 2)
  Check(D.SetSize(d, ctx, 2, 2589, 5) and d.tabs[2].sizes[2589] == 5, "a size is set for an automatic item")
  Check(D.SetSize(d, ctx, 2, 2589, 500) and d.tabs[2].sizes[2589] == nil, "a size at or above the stack limit is the default (a full stack)")
  Check(not D.SetSize(d, ctx, 2, 2589, 0) and not D.SetSize(d, ctx, 2, 2592, 5), "no size of 0, and none for an item the tab doesn't take")
  D.SetSize(d, ctx, 2, 2589, 5)
  Check(D.SetLayout(d, 2, "spaced") and d.tabs[2].layout == "spaced" and not D.SetLayout(d, 2, "diagonal"), "a layout is chosen; an unknown one is refused")
  local before = D.Digest(d)
  d.saved = ""
  Check(D.Dirty(d), "a size or layout change is an unsaved edit")
  local rules = D.Commit(d, {}, { destFor = function(tab) return "dest" .. tab end })
  local rule = rules[1]
  rule.id = "r1"
  Check(rule.sizes[2589] == 5 and rule.layout == "spaced", "they are written into the rule")
  local clean = MI.CleanRule(rule)
  Check(clean.sizes[2589] == 5 and clean.layout == "spaced", "and survive the rule's own checking")
  local bad = {}
  for k, v in pairs(rule) do bad[k] = v end
  bad.sizes, bad.layout = { [2589] = 0, [99999999] = 5, [2592] = 5 }, "diagonal"
  local cleaned = MI.CleanRule(bad)
  Check(next(cleaned.sizes) == nil and cleaned.layout == "packed", "a bad size, an item not in the rule, or an unknown layout is dropped, never trusted")
  local back = D.Load(rules, { guild = "Night Owls", names = d.names, numTabs = 4, resolve = function() return { guild = "Night Owls", tab = 2, tabName = "Cloth" } end, facts = ctx.facts })
  Check(back.tabs[2].sizes[2589] == 5 and back.tabs[2].layout == "spaced" and D.Digest(back) == before, "loading gives the same draft back")
  D.RemoveItem(d, ctx, 2, 2589)
  Check(d.tabs[2].sizes[2589] == nil, "taking the item out forgets its size")

  -- the picture the editor draws: pinned stacks and the automatic items where the layout puts them
  local t = Draft()
  D.AssignTab(t, ctx, 2589, 2); D.AssignTab(t, ctx, 2592, 2)
  D.SetSize(t, ctx, 2, 2589, 5)
  D.PlaceSlot(t, ctx, 2447, 2, 1, 7)
  local cells = D.Theory(t, 2, ctx)
  Check(cells[1] and cells[1].id == 2447 and not cells[1].auto, "a pinned stack stays where it was pinned")
  Check(cells[2] and cells[2].id == 2589 and cells[2].count == 5 and cells[2].auto and cells[3] and cells[3].id == 2592 and cells[3].count == 20, "the automatic items follow, Linen in stacks of 5 and Wool as a full stack")
  local more = D.Theory(t, 2, ctx, function(id) return id == 2589 and 12 or nil end)
  Check(more[2].count == 5 and more[3].count == 5 and more[4].count == 2, "with a quantity: 5, 5 and 2")
end

-- the planner: sizes and layouts decide the slots; nothing is swapped, invented or moved out of the way
do
  local function Rule(layout, sizes)
    return ARule("L1", 2, { rest = { [2589] = true, [2592] = true }, include = { [2589] = true, [2592] = true }, sizes = sizes or {}, layout = layout })
  end
  local bags = { Bag(0, 1, 2589, 20), Bag(0, 2, 2592, 20) }
  local function Slots(plan)
    local out = {}
    for slot, c in pairs(plan.tabs[2].proposed) do if c.change == "added" then out[#out + 1] = ("%d:%d@%d"):format(c.id, c.count, slot) end end
    table.sort(out)
    return table.concat(out, " ")
  end
  local bank = function() return Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", { [1] = { 2447, 1 } }), [3] = Tab("Herbs") }) end
  local packed = Plan("deposit", { Rule("packed", { [2589] = 5 }) }, bank(), bags, { split = true })
  Check(Slots(packed) == "2589:5@2 2589:5@3 2589:5@4 2589:5@5 2592:20@6", "packed, Linen in stacks of 5: a foreign item in slot 1 is stepped over (never moved), Wool follows: " .. Slots(packed))
  Check(#packed.ops == 5, "five placements: four split off the Linen stack, one Wool")
  local spaced = Plan("deposit", { Rule("spaced", { [2589] = 10 }) }, bank(), bags, { split = true })
  Check(Slots(spaced) == "2589:10@2 2589:10@3 2592:20@5", "spaced: a free slot between Linen and Wool: " .. Slots(spaced))
  local cols = Plan("deposit", { Rule("columns", { [2589] = 10 }) }, bank(), bags, { split = true })
  Check(Slots(cols) == "2589:10@2 2589:10@3 2592:20@15", "columns: Wool starts the next column of 14: " .. Slots(cols))
  Check(packed.summary.design.reserved == 0 and packed.summary.design.extrasPlaced == 40, "the stacks the layout made are 'extras placed', not stacks the player reserved")
  Check(#packed.design.allocs > 0 and packed.design.allocs[1].auto == true, "and they are marked automatic")
  local def = Plan("deposit", { Rule(nil, nil) }, Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") }), bags, { split = true })
  Check(Slots(def) == "2589:20@1 2592:20@2", "no size and no layout: full stacks, packed from the first slot")

  -- Organize: what is in the bank is brought to the layout (merged, split, moved), nothing is lost
  local org = Plan("reorganize", { Rule("packed", { [2589] = 10 }) },
    Bank({ [1] = Tab("Gear", { [5] = { 2589, 14 } }), [2] = Tab("Cloth", { [7] = { 2589, 6 }, [9] = { 2592, 8 } }) }), {}, { split = true })
  Check(Total(org, 2589) == 20 and Total(org, 2592) == 8, "organize loses nothing")
  Check(Proposed(org, 2, 1) and Proposed(org, 2, 1).id == 2589 and Proposed(org, 2, 1).count == 10 and Proposed(org, 2, 2).count == 10 and Proposed(org, 2, 3).id == 2592,
    "20 Linen are two stacks of 10 in slots 1 and 2, the Wool after them in slot 3")

  -- a pinned stack is filled first and its slot is left to it
  local pin = ARule("L2", 2, { place = { { slot = 2, id = 2589, count = 7 } }, rest = { [2589] = true }, sizes = { [2589] = 10 }, layout = "packed" })
  local pp = Plan("deposit", { pin }, Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs") }), { Bag(0, 1, 2589, 20) }, { split = true })
  Check(Proposed(pp, 2, 2) and Proposed(pp, 2, 2).count == 7 and Proposed(pp, 2, 1) and Proposed(pp, 2, 1).count == 10 and Proposed(pp, 2, 3) and Proposed(pp, 2, 3).count == 3,
    "the pinned 7 is filled first, the rest (13) is spread in 10 and 3 around it")
end


---------------------------------------------------------------------------
-- The other items in an arrangement tab: merged, sorted, and moved to the far end, away from the arrangement
---------------------------------------------------------------------------
do
  local rule = ARule("T1", 2, { rest = { [2589] = true }, include = { [2589] = true }, layout = "packed" })
  local function Cloth(slots) return Bank({ [1] = Tab("Gear", { [3] = { 2770, 5 } }), [2] = Tab("Cloth", slots), [3] = Tab("Herbs") }) end
  Item(2770, "Copper Ore", 20, 7, 7)
  local function Where(plan, id)
    local out = {}
    for slot, c in pairs(plan.tabs[2].proposed) do if c.id == id then out[#out + 1] = ("%d:%d"):format(slot, c.count) end end
    table.sort(out)
    return table.concat(out, " ")
  end
  local bank = Cloth({ [1] = { 2447, 8 }, [2] = { 2770, 7 }, [4] = { 2447, 9 }, [6] = { 2770, 6 }, [9] = { 2589, 20 } })
  bank.tabs[1].slots[3] = nil                          -- (no Ore in another tab: an item is tidied only when all of it is in this tab)
  local plan = Plan("reorganize", { rule }, bank, {}, { split = true })
  Check(Where(plan, 2589) == "1:20", "the arrangement's Linen goes to the first slot: " .. Where(plan, 2589))
  Check(Where(plan, 2770) == "97:13" and Where(plan, 2447) == "98:17", "the others are merged into stacks (Ore 7+6, Peacebloom 8+9) and sorted at the far end: Ore " .. Where(plan, 2770) .. ", Peacebloom " .. Where(plan, 2447))
  Check(Total(plan, 2770) == 13 and Total(plan, 2447) == 17, "nothing is lost or invented")
  local elsewhere = Plan("reorganize", { rule }, Bank({ [1] = Tab("Gear", { [3] = { 2770, 5 } }), [2] = Tab("Cloth", { [2] = { 2770, 7 } }), [3] = Tab("Herbs") }), {}, { split = true })
  Check(Proposed(elsewhere, 1, 3) and Proposed(elsewhere, 1, 3).count == 5 and Proposed(elsewhere, 2, 2) and Proposed(elsewhere, 2, 2).count == 7,
    "an item that is also in another tab is not pulled together: both stay, and the other tab is left alone")

  -- a deposit never touches what is already in the bank
  local dep = Plan("deposit", { rule }, bank, { Bag(0, 1, 2589, 20) }, { split = true })
  Check(dep.tabs[2].proposed[2].id == 2770 and dep.tabs[2].proposed[4].id == 2447, "a deposit leaves the other items where they are")

  -- more than the tab can hold: whole items that fit, the rest stays (and is stepped over)
  local many = {}
  for slot = 1, 95 do many[slot] = { 2447, 1 } end
  local crowded = Plan("reorganize", { rule }, Cloth(many), {}, { split = true })
  Check(Total(crowded, 2447) == 95, "a crowded tab loses nothing")

  -- protected or owned elsewhere: left in place
  local plain = Plain("P1", 2, { include = { [2770] = true } })
  local owned = Plan("reorganize", { plain, rule }, bank, {}, { split = true })
  Check(Where(owned, 2770) == "2:7 6:6", "an item another rule owns is not tidied by this one (that rule decides): " .. Where(owned, 2770))
  local prot = Plan("reorganize", { rule }, bank, {}, { split = true, never = function(id) return id == 2770 end })
  Check(Where(prot, 2770) == "2:7 6:6", "an item on the Never transfer list is not moved")
  -- the same item in two arrangement tabs is tidied in one
  local rule3 = ARule("T3", 3, { rest = { [2592] = true }, include = { [2592] = true } })
  local two = Plan("reorganize", { rule, rule3 }, Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", { [4] = { 2770, 5 } }), [3] = Tab("Herbs", { [5] = { 2770, 6 } }) }), {}, { split = true })
  local at2, at3 = 0, 0
  for _, c in pairs(two.tabs[2].proposed) do if c.id == 2770 then at2 = at2 + c.count end end
  for _, c in pairs(two.tabs[3].proposed) do if c.id == 2770 then at3 = at3 + c.count end end
  Check(at2 == 5 and at3 == 6, "an item in two arrangement tabs is never gathered across them: " .. at2 .. "/" .. at3)
end

if failures == 0 then print("PASSED test_magic_inventory_design") else print(failures .. " FAILED") os.exit(1) end
