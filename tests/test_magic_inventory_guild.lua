-- Magic Inventory, guild bank rules and placement previews (inventory/GuildBank.lua, GuildPlan.lua, and the guild parts of
-- Rules.lua): synthetic data only; nothing here is the game.
--   * rules: the target stack size is kept clean (guild rules only), a guild tab is bound to its guild, tab names and icons
--     are remembered for choosing a tab with the bank closed;
--   * precedence: the first enabled rule that moves items owns an item; a bank or mail rule above keeps it out of a guild plan;
--   * stack sizes: compatible partial stacks, remainders, unstackable items, a target above an item's limit, item identity;
--   * deposit and reorganize use different sources: bags only, or the bank only;
--   * capacity, rights, unread/stale tabs, guild and tab identity, and what is never assumed (swaps, splits);
--   * read-only: inputs are not edited, the same inputs give the same plan, and no game call that moves or asks is made.
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MIClient("Rich")
local MI = c.TwichUI.MagicInventory
local GB = MI.GuildBank
Check(GB ~= nil and MI.BuildGuildPlan ~= nil and MI.CurrentGuildPlan ~= nil, "the guild bank files are loaded")

---------------------------------------------------------------------------
-- Helpers: a bank snapshot, rules, and items, built by hand
---------------------------------------------------------------------------
local FACTS = {}
local function Item(id, name, maxStack, class, sub)
  FACTS[id] = { id = id, name = name, icon = 1000 + id, quality = 1, classID = class or 7, subclassID = sub or 5, equipLoc = "",
    bindType = 0, maxStack = maxStack, equipment = false }
end
Item(2589, "Linen Cloth", 20)
Item(2592, "Wool Cloth", 20)
Item(2447, "Peacebloom", 20, 7, 9)
Item(3000, "Bolt of Silk", 200)
Item(9100, "Odd Trinket", 1, 15, 0)
Item(7777, "Other Linen Cloth", 20)   -- the same name as 2589 in the tests that look at identity
FACTS[7777].name = "Linen Cloth"
local function Facts(id) local f = FACTS[id]; if f then return f end return nil, false end

local function Rule(id, fields)
  local r = { id = id, name = id, kind = "guild", enabled = true, cats = {}, qualities = {}, include = {}, exclude = {}, equip = "any",
    bind = "any", keep = 0, stack = 0, dest = "d" .. id }
  for k, v in pairs(fields or {}) do r[k] = v end
  return r
end
local WHERE = {}
local function Where(rule, tab, name, guild)
  WHERE[rule.dest] = { kind = "guild", guild = guild or "Night Owls", tab = tab, tabName = name, label = name, id = rule.dest }
  return rule
end
local function Cells(slots)  -- { [slot] = { id, count } } or { [slot] = { id, count, locked } }
  local out = {}
  for s, v in pairs(slots or {}) do out[s] = { id = v[1], count = v[2], locked = v[3] or false, icon = 1000 + (v[1] or 0) } end
  return out
end
local NIL = {}   -- "the game didn't say": a field set to nothing
local function Tab(name, slots, extra)
  local t = { name = name, icon = 133, viewable = true, canDeposit = true, canWithdraw = true, state = "live", slots = Cells(slots or {}),
    readAt = 100, age = 0 }
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
local function Plan(mode, rules, bank, stacks, extra)
  local o = { mode = mode, rules = rules, bank = bank, stacks = stacks or {}, facts = Facts, guildNow = "Night Owls",
    resolve = function(dest) return WHERE[dest] end, never = function() return false end, split = false, made = 1, generation = 1 }
  for k, v in pairs(extra or {}) do o[k] = v end
  return MI.BuildGuildPlan(o)
end
local function OpsTo(plan, tab) local n = 0 for _, o in ipairs(plan.ops) do if o.to.tab == tab then n = n + 1 end end return n end
local function Proposed(plan, tab, slot) return plan.tabs[tab] and plan.tabs[tab].proposed and plan.tabs[tab].proposed[slot] end
local function Untouched(plan, id, reason)
  for _, u in ipairs(plan.untouched) do if u.id == id and (reason == nil or u.reason == reason) then return u end end
end
local function Item1(plan, id) for _, it in ipairs(plan.items) do if it.id == id then return it end end end
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
local function Digest(plan)   -- the operations and the proposed cells, as text: for "the same inputs give the same plan"
  local out = {}
  for _, o in ipairs(plan.ops) do
    out[#out + 1] = ("%d %s %d id%d %s>%s status=%s"):format(o.n, o.kind, o.count, o.id,
      o.from.kind == "bag" and (o.from.bag .. ":" .. o.from.slot) or (o.from.tab .. "/" .. o.from.slot), o.to.tab .. "/" .. o.to.slot, o.status)
  end
  for i = 1, plan.numTabs or 0 do
    local v = plan.tabs[i]
    if v.proposed then
      for s = 1, 98 do local cell = v.proposed[s]; if cell then out[#out + 1] = ("%d/%d=%s x%s %s"):format(i, s, tostring(cell.id), tostring(cell.count), tostring(cell.change)) end end
    end
  end
  return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- 1. Rules: the target stack size, guild-bound tabs, remembered tab names
---------------------------------------------------------------------------
c.TwichUIDB.ui = nil
c.TwichUIDB.magicInventory = nil
local rid = MI.SaveRule({ kind = "guild", name = "Cloth", enabled = false, cats = { "7:5" }, stack = 20 })
Check(rid and MI.Rule(rid).stack == 20, "a guild rule keeps its target stack size")
local r2 = MI.Rule(rid); r2.stack = -4; MI.SaveRule(r2)
Check(MI.Rule(rid).stack == 0, "a negative target is not kept")
r2 = MI.Rule(rid); r2.stack = 2.5; MI.SaveRule(r2)
Check(MI.Rule(rid).stack == 0, "a fractional target is not kept")
r2 = MI.Rule(rid); r2.stack = MI.MAX_STACK + 1; MI.SaveRule(r2)
Check(MI.Rule(rid).stack == 0, "a target above the largest allowed is not kept")
r2 = MI.Rule(rid); r2.stack = "20"; MI.SaveRule(r2)
Check(MI.Rule(rid).stack == 0, "a target that isn't a number is not kept")
local bankRule = MI.SaveRule({ kind = "bank", name = "Bank", enabled = false, cats = { "7:9" }, stack = 50 })
Check(MI.Rule(bankRule).stack == 0, "only a guild bank rule has a target stack size")
local mailRules = MI.Rules()
Check(#mailRules == 2 and mailRules[1].stack == 0, "a rule that never set one has 0 (no target)")

-- a guild tab is the guild's: the same tab number in another guild is not the rule's tab
local dest = MI.AddDest("guild", "Mats")
Check(MI.SetGuildTab(dest, "Night Owls", 2, "Materials", 133), "a tab is chosen with its guild, name and icon")
local where = MI.Resolve(dest)
Check(where and where.guild == "Night Owls" and where.tab == 2 and where.tabName == "Materials" and where.tabIcon == 133, "and read back with them")
local rule3 = MI.SaveRule({ kind = "guild", name = "Mats", enabled = true, dest = dest, cats = { "7:5" }, stack = 10 })
Check(MI.Rule(rule3).enabled == true, "the rule can be on once its tab is chosen")
local code = MI.Problem(MI.Rule(rule3), "Night Owls")
Check(code == nil, "in the same guild nothing stops it")
code = MI.Problem(MI.Rule(rule3), "Other Guild")
Check(code == "guild-changed", "in another guild with the same tab number and name it asks for review: " .. tostring(code))
code = MI.Problem(MI.Rule(rule3), nil)
Check(code == "guild-changed", "with no guild it asks for review too")
code = MI.Problem(MI.Rule(rule3), false)
Check(code == nil, "while the guild isn't known yet it isn't judged")

MI.NoteGuildTabs("Night Owls", { [1] = { name = "Gear", icon = 5 }, [2] = { name = "Materials", icon = 133 }, [9] = { name = "Too many", icon = 1 } })
local seen = MI.GuildTabsSeen("Night Owls")
Check(seen[1] and seen[1].name == "Gear" and seen[2].icon == 133 and seen[9] == nil, "tab names and icons are remembered for the guild, up to the game's 8 tabs")
Check(next(MI.GuildTabsSeen("Another Guild")) == nil, "and not for another guild")
for i = 1, 12 do MI.NoteGuildTabs("Guild " .. i, { [1] = { name = "T", icon = 1 } }) end
local n = 0
for _ in pairs(c.TwichUIDB.magicInventory.guilds) do n = n + 1 end
Check(n <= MI.MAX_GUILDS, "the number of guilds remembered is bounded: " .. n)
Check(not tostring(c.TwichUIDB.ui.magicInventory):find("Night Owls"), "tab names stay out of the profile")

---------------------------------------------------------------------------
-- 2. Precedence and matching
---------------------------------------------------------------------------
WHERE = {}
local cloth = Where(Rule("cloth", { cats = { "7:5" } }), 2, "Cloth")
local herbs = Where(Rule("herbs", { cats = { "7:9" } }), 3, "Herbs")
local both = Where(Rule("both", { include = { [2589] = true } }), 4, "Everything")
local bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs"), [4] = Tab("Everything") })
local bags = { Bag(0, 1, 2589, 20), Bag(0, 2, 2447, 10), Bag(0, 3, 2592, 5), Bag(0, 4, 9100, 1) }
local plan = Plan("deposit", { cloth, herbs, both }, bank, bags)
Check(Item1(plan, 2589) and Item1(plan, 2589).tab == 2 and Item1(plan, 2589).rule == "cloth", "the first rule that matches owns the item: linen goes to the Cloth tab")
Check(Item1(plan, 2447).tab == 3, "a category rule routes herbs to their tab")
Check(Item1(plan, 2592).tab == 2, "wool follows the category too")
Check(Proposed(plan, 4, 1) == nil and OpsTo(plan, 4) == 0, "a later rule that also matches never gets it (no second copy, no other tab)")
Check(Item1(plan, 9100) == nil and Untouched(plan, 9100) == nil, "an item no rule picks out is simply left alone")
Check(plan.readOnly == true and plan.mode == "deposit", "a plan says it is a read-only preview of its mode")
local order = Rule("order", { cats = { "7:5" } })
-- the order of the list is the priority, whatever the order the items were met in
local planA = Plan("deposit", { both, cloth }, bank, bags)
Check(Item1(planA, 2589).tab == 4 and Item1(planA, 2592).tab == 2, "putting the listing rule first changes the owner of the listed item only")
local planB = Plan("deposit", { cloth, herbs, both }, bank, { bags[4], bags[3], bags[2], bags[1] })
Check(Digest(plan) == Digest(planB) or true, "(order check below)")
local ids = {}
for _, o in ipairs(plan.ops) do ids[#ids + 1] = o.id .. ">" .. o.to.tab end
local idsB = {}
for _, o in ipairs(planB.ops) do idsB[#idsB + 1] = o.id .. ">" .. o.to.tab end
table.sort(ids); table.sort(idsB)
Check(table.concat(ids, ",") == table.concat(idsB, ","), "the same items go to the same tabs whatever order the bags are met in")

-- a bank or mail rule above a guild rule owns the item: it stays in the bags, in this plan
local bankAbove = Rule("bankAbove", { kind = "bank", cats = { "7:5" }, dest = nil })
plan = Plan("deposit", { bankAbove, cloth }, bank, bags)
Check(Item1(plan, 2589) == nil and Untouched(plan, 2589, "elsewhere"), "a bank rule above owns the item: the guild plan leaves it and says which rule has it")
Check(Untouched(plan, 2589, "elsewhere").rule == "bankAbove", "and names that rule")
-- the Never transfer list and Never transfer rules
plan = Plan("deposit", { cloth }, bank, bags, { never = function(id) return id == 2589 end })
Check(Item1(plan, 2589) == nil and Untouched(plan, 2589, "never"), "the Never transfer list keeps it out")
local neverRule = Rule("nv", { kind = "never", dest = nil, include = { [2592] = true } })
plan = Plan("deposit", { neverRule, cloth }, bank, bags)
Check(Item1(plan, 2592) == nil and Untouched(plan, 2592, "never-rule"), "a Never transfer rule keeps it out")
-- a rule's own exclusion
local excl = Where(Rule("excl", { cats = { "7:5" }, exclude = { [2592] = true } }), 2, "Cloth")
plan = Plan("deposit", { excl }, bank, bags)
Check(Item1(plan, 2592) == nil and Item1(plan, 2589) ~= nil, "a rule's Never include list is respected")
-- keep amounts: they apply to the bags a deposit takes from
local keepRule = Where(Rule("keep", { cats = { "7:5" }, keep = 20 }), 2, "Cloth")
plan = Plan("deposit", { keepRule }, bank, { Bag(0, 1, 2589, 20), Bag(0, 2, 2589, 8) })
Check(Item1(plan, 2589) and Item1(plan, 2589).qty == 8, "a keep amount holds back what the bags should keep (20 of 28): the 8 moves")
-- item identity: the same name is not the same item
local twin = Where(Rule("twin", { include = { [2589] = true, [7777] = true }, stack = 0 }), 2, "Cloth")
local bankTwin = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", { [1] = { 7777, 10 } }) })
plan = Plan("deposit", { twin }, bankTwin, { Bag(0, 1, 2589, 5) })
Check(Proposed(plan, 2, 1).id == 7777 and Proposed(plan, 2, 1).count == 10 and Proposed(plan, 2, 2).id == 2589 and Proposed(plan, 2, 2).count == 5,
  "an item with the same display name but another ID is never merged")

---------------------------------------------------------------------------
-- 3. Stack sizes
---------------------------------------------------------------------------
-- 3a. no target: whole stacks, into a compatible stack with room, else a free slot
local plain = Where(Rule("plain", { cats = { "7:5" } }), 2, "Cloth")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", { [1] = { 2589, 12 }, [2] = { 2589, 20 } }) })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 8), Bag(0, 2, 2589, 15) })
-- the larger bag stack is placed first (15), then the 8
Check(plan.ops[1].kind == "deposit" and plan.ops[1].to.slot == 3 and Proposed(plan, 2, 3).count == 15, "without a target a stack that doesn't fit whole into the partial stack (12 + 15) takes the first free slot")
Check(plan.ops[2].kind == "merge" and plan.ops[2].to.slot == 1 and Proposed(plan, 2, 1).count == 20, "and one that fits whole joins a compatible partial stack (12 + 8)")
Check(plan.summary.splits == 0, "no stack was split")
Check(Proposed(plan, 2, 2).count == 20 and Proposed(plan, 2, 2).change == nil, "a full stack that is already there is left alone")

-- 3b. a target of 20 with whole stacks: two full stacks and a remainder of 5
local t20 = Where(Rule("t20", { cats = { "7:5" }, stack = 20 }), 2, "Cloth")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth") })
plan = Plan("deposit", { t20 }, bank, { Bag(0, 1, 2589, 20), Bag(0, 2, 2589, 20), Bag(0, 3, 2589, 5) })
Check(Proposed(plan, 2, 1).count == 20 and Proposed(plan, 2, 2).count == 20 and Proposed(plan, 2, 3).count == 5 and Proposed(plan, 2, 4) == nil,
  "a target of 20 over 45: two full stacks and one remainder of 5")
Check(plan.summary.splits == 0 and plan.summary.blockedOps == 0, "reachable with whole stacks: nothing to split or block")

-- 3c. a target that needs splitting: stacks of 120 and 30, target 50, over 150 total
local t50 = Where(Rule("t50", { include = { [3000] = true }, stack = 50 }), 2, "Cloth")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth") })
plan = Plan("deposit", { t50 }, bank, { Bag(0, 1, 3000, 120), Bag(0, 2, 3000, 30) })
Check(Proposed(plan, 2, 1).count == 50 and Proposed(plan, 2, 2).count == 50 and Proposed(plan, 2, 3).count == 50, "target 50 over 150: three stacks of 50")
Check(plan.summary.splits >= 1, "reaching it needs splits")
local blockedSplit = 0
for _, o in ipairs(plan.ops) do if o.split and o.status == "blocked" and o.code == "needs-split" then blockedSplit = blockedSplit + 1 end end
Check(blockedSplit == plan.summary.splits and plan.summary.blockedOps == blockedSplit, "while splitting isn't supported those operations are blocked, with a reason")
Check(Proposed(plan, 2, 1).blocked ~= nil, "and the stacks they make are marked as blocked in the preview")
plan = Plan("deposit", { t50 }, bank, { Bag(0, 1, 3000, 120), Bag(0, 2, 3000, 30) }, { split = true })
Check(plan.summary.splits >= 1 and plan.summary.blockedOps == 0, "where splitting is supported the same operations are fine")
local total = 0
for _, o in ipairs(plan.ops) do total = total + o.count end
Check(total == 150, "and they move exactly 150: " .. total)
-- a remainder stack when the total isn't divisible: 130 at a target of 50 is 50, 50, 30
plan = Plan("deposit", { t50 }, bank, { Bag(0, 1, 3000, 100), Bag(0, 2, 3000, 30) }, { split = true })
Check(Proposed(plan, 2, 1).count == 50 and Proposed(plan, 2, 2).count == 50 and Proposed(plan, 2, 3).count == 30, "130 at a target of 50: 50, 50 and one remainder of 30")
Check(Proposed(plan, 2, 4) == nil, "never a second remainder")

-- 3d. an existing partial stack receives up to the target; a larger one is left and explained
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", { [1] = { 2589, 8 }, [2] = { 2589, 30 } }) })
local t20b = Where(Rule("t20b", { cats = { "7:5" }, stack = 20 }), 2, "Cloth")
local bigBank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", { [1] = { 3000, 80 } }) })
plan = Plan("deposit", { t50 }, bigBank, { Bag(0, 1, 3000, 10) }, { split = true })
Check(Proposed(plan, 2, 1).count == 80 and Proposed(plan, 2, 1).change == nil, "an existing stack above the target is not moved or cut in a deposit")
Check(Proposed(plan, 2, 2).count == 10, "the new items go to a new stack")
Check(Item1(plan, 3000).note and Item1(plan, 3000).note:find("Reorganize"), "and the plan says Reorganize is what would split it")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", { [1] = { 2589, 8 } }) })
plan = Plan("deposit", { t20b }, bank, { Bag(0, 1, 2589, 12), Bag(0, 2, 2589, 18) })
Check(Proposed(plan, 2, 1).count == 20 and Proposed(plan, 2, 1).change == "changed" and Proposed(plan, 2, 1).was == 8, "a partial stack of 8 receives 12 to reach the target of 20")
Check(Proposed(plan, 2, 2).count == 18 and Proposed(plan, 2, 2).change == "added", "and the rest forms one remainder stack of 18")
Check(plan.summary.splits == 0, "(whole stacks suffice)")

-- 3e. unstackable items stay 1; a target above an item's limit blocks it
local t5 = Where(Rule("t5", { include = { [9100] = true, [2589] = true }, stack = 5 }), 2, "Cloth")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth") })
plan = Plan("deposit", { t5 }, bank, { Bag(0, 1, 9100, 1), Bag(0, 2, 9100, 1) })
Check(Proposed(plan, 2, 1).count == 1 and Proposed(plan, 2, 2).count == 1 and plan.summary.blockedOps == 0, "unstackable items stay one to a slot whatever the target")
local tBig = Where(Rule("tBig", { include = { [2589] = true }, stack = 50 }), 2, "Cloth")
plan = Plan("deposit", { tBig }, bank, { Bag(0, 1, 2589, 20) })
Check(Proposed(plan, 2, 1) == nil and #plan.ops == 0, "a target above the item's own limit places nothing")
Check(Untouched(plan, 2589, "target-too-big") and Untouched(plan, 2589, "target-too-big").text:find("20"), "and says the item stacks to 20, not silently cut down")
Check(Item1(plan, 2589).state == "blocked", "the item is blocked")
Check(plan.summary.blocked == 1, "and counted as blocked")
-- a rule with a target covers items with different limits: each is judged on its own limit
local mixed = Where(Rule("mixed", { include = { [2589] = true, [3000] = true }, stack = 40 }), 2, "Cloth")
plan = Plan("deposit", { mixed }, bank, { Bag(0, 1, 2589, 20), Bag(0, 2, 3000, 90) }, { split = true })
Check(Item1(plan, 2589).state == "blocked" and Item1(plan, 3000).state == "moves", "one item blocked by its limit while the other is placed")
Check(Proposed(plan, 2, 1).id == 3000 and Proposed(plan, 2, 1).count == 40 and Proposed(plan, 2, 2).count == 40 and Proposed(plan, 2, 3).count == 10, "(40, 40 and the remainder 10)")

---------------------------------------------------------------------------
-- 4. Deposit and reorganize read different places
---------------------------------------------------------------------------
local rule = Where(Rule("gather", { cats = { "7:5" }, stack = 20 }), 2, "Cloth")
bank = Bank({
  [1] = Tab("Gear", { [1] = { 2589, 12 }, [2] = { 2447, 5 } }),
  [2] = Tab("Cloth", { [1] = { 2589, 8 } }),
  [3] = Tab("Herbs", { [1] = { 2592, 15 } }),
})
bags = { Bag(0, 1, 2589, 30) }
local dep = Plan("deposit", { rule }, bank, bags)
local reo = Plan("reorganize", { rule }, bank, bags)
local bankSourceInDeposit, bagSourceInReorg = false, false
for _, o in ipairs(dep.ops) do if o.from.kind == "bank" then bankSourceInDeposit = true end end
for _, o in ipairs(reo.ops) do if o.from.kind == "bag" then bagSourceInReorg = true end end
Check(#dep.ops > 0 and not bankSourceInDeposit, "a deposit moves only what is in the bags")
Check(#reo.ops > 0 and not bagSourceInReorg, "a reorganize moves only what is in the bank")
Check(Proposed(dep, 1, 1).count == 12 and Proposed(dep, 3, 1).count == 15, "a deposit leaves the bank's own items in the tabs where they are")
-- reorganize: 12 linen (tab 1) + 8 (tab 2) + wool 15 (tab 3) gather in tab 2 at 20 each; the herb stays
local lin = Proposed(reo, 2, 1)
Check(lin and lin.id == 2589 and lin.count == 12 + 8, "reorganize gathers the linen into the rule's tab (12 + 8 = 20)")
local wool2
for s = 1, 98 do local cell = Proposed(reo, 2, s); if cell and cell.id == 2592 then wool2 = cell end end
Check(wool2 and wool2.count == 15, "and the wool, as the same category")
Check(Proposed(reo, 1, 1) == nil and Proposed(reo, 3, 1) == nil, "the tabs they left are empty of them")
Check(Proposed(reo, 1, 2) and Proposed(reo, 1, 2).id == 2447 and Proposed(reo, 1, 2).count == 5 and Proposed(reo, 1, 2).change == nil, "an item no rule picks out stays exactly where it is")
Check(reo.tabs[1].current[1].change == "leaves", "and the current view shows what leaves")
Check(Same(reo.tabs[1].current[2], reo.tabs[1].proposed[2]) or reo.tabs[1].current[2].count == reo.tabs[1].proposed[2].count, "unmatched cells are the same before and after")

-- reorganize with a target splits an oversized stack and gathers the rest
bank = Bank({
  [1] = Tab("Gear", { [1] = { 3000, 130 } }),
  [2] = Tab("Bolts", { [1] = { 3000, 20 } }),
})
local gather50 = Where(Rule("g50", { include = { [3000] = true }, stack = 50 }), 2, "Bolts")
reo = Plan("reorganize", { gather50 }, bank, {}, { split = true })
Check(Proposed(reo, 2, 1).count == 50 and Proposed(reo, 2, 2).count == 50 and Proposed(reo, 2, 3).count == 50, "150 bolts in two tabs become three stacks of 50 in the rule's tab")
Check(Proposed(reo, 1, 1) == nil, "and the source tab is empty of them")
total = 0
for _, o in ipairs(reo.ops) do total = total + o.count end
Check(total >= 100 and reo.summary.splits >= 1, "the operations move the surplus, some by splitting")
for _, o in ipairs(reo.ops) do
  local needsSplit = false
  for _, need in ipairs(o.needs) do if need == "split" then needsSplit = true end end
  Check(needsSplit == (o.split == true), "an operation lists the split it needs: op " .. o.n)
end
reo = Plan("reorganize", { gather50 }, bank, {})
Check(reo.summary.blockedOps == reo.summary.splits and reo.summary.splits >= 1, "without split support those operations are blocked")

-- a bag item is never pulled in by a reorganize, even with an Also include rule
reo = Plan("reorganize", { gather50 }, Bank({ [1] = Tab("Gear"), [2] = Tab("Bolts") }), { Bag(0, 1, 3000, 100) })
Check(#reo.ops == 0 and Proposed(reo, 2, 1) == nil, "a reorganize with nothing in the bank plans nothing, whatever is in the bags")
-- no target: stacks move whole to free slots, and stacks already there stay
bank = Bank({ [1] = Tab("Gear", { [1] = { 2589, 7 }, [2] = { 2589, 7 } }), [2] = Tab("Cloth", { [1] = { 2589, 5 } }) })
reo = Plan("reorganize", { plain }, bank, {})
Check(Proposed(reo, 2, 1).count == 5 and Proposed(reo, 2, 1).change == nil and Proposed(reo, 2, 2).count == 7 and Proposed(reo, 2, 3).count == 7, "without a target stacks keep their sizes and move whole")
Check(reo.summary.splits == 0, "(no splits)")
-- equipment-like protections: a locked stack stays, with its reason
bank = Bank({ [1] = Tab("Gear", { [1] = { 2589, 7, true } }), [2] = Tab("Cloth") })
reo = Plan("reorganize", { plain }, bank, {})
Check(#reo.ops == 0 and Untouched(reo, 2589, "locked"), "a locked stack stays where it is, and says so")
Check(reo.tabs[1].current[1].blocked ~= nil, "and the cell is marked blocked")

---------------------------------------------------------------------------
-- 5. Capacity, rights, unread and stale data, identity
---------------------------------------------------------------------------
-- a full destination tab: blocked, never redirected
local full = {}
for s = 1, 98 do full[s] = { 2447, 20 } end
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", full) })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20), Bag(0, 2, 2589, 18) })
Check(#plan.ops == 0 and Untouched(plan, 2589, "tab-full"), "a full tab: nothing is placed, and it says the tab is full")
Check(Untouched(plan, 2589, "tab-full").count == 38, "for all 38 items")
Check(plan.tabs[1].proposed[1] == nil, "and nothing goes to another tab instead")
-- room for some
local nearly = {}
for s = 1, 97 do nearly[s] = { 2447, 20 } end
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", nearly) })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20), Bag(0, 2, 2589, 18) })
Check(#plan.ops == 1 and Item1(plan, 2589).state == "partial", "one free slot: one stack is placed and the other is reported blocked")
-- a tab that is not read is unknown, not empty
bank = Bank({ [1] = Tab("Gear"), [2] = { name = "Cloth", icon = 1, viewable = true, canDeposit = true, canWithdraw = true, state = "unread" } })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(#plan.ops == 0, "an unread destination tab places nothing")
Check(plan.rules[1].status == "unknown", "and the rule is unknown, not ready: " .. tostring(plan.rules[1].status))
Check(plan.summary.unknown >= 1 and plan.summary.blocked == 0, "the items are counted as unknown")
Check(plan.tabs[2].current == nil and plan.tabs[2].note and plan.tabs[2].note:find("Not read"), "and the tab shows that it wasn't read rather than an empty grid")
-- reorganize: tabs not read are named, and nothing is invented for them
bank = Bank({ [1] = Tab("Gear", { [1] = { 2589, 7 } }), [2] = Tab("Cloth"), [3] = { name = "Herbs", state = "unread", viewable = true, canDeposit = true, canWithdraw = true } })
reo = Plan("reorganize", { plain }, bank, {})
Check(#reo.unreadTabs == 1 and reo.unreadTabs[1] == 3, "tabs not read are listed")
local noted = false
for _, k in ipairs(reo.constraints) do if k.code == "tabs-unread" and k.text:find("3") then noted = true end end
Check(noted, "and a note says items there are not in the preview")
-- no bank data at all (never opened)
plan = Plan("deposit", { plain }, { tabs = {} }, { Bag(0, 1, 2589, 20) })
Check(#plan.ops == 0 and plan.rules[1].status == "unknown", "with no guild bank read, a rule is unknown and nothing is placed")
Check(plan.freshness == "stale", "and the plan is not presented as current")
-- permissions
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", {}, { canDeposit = false }) })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(plan.rules[1].status == "blocked" and plan.rules[1].code == "no-deposit" and #plan.ops == 0, "a tab the rank can't deposit in blocks the rule")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", {}, { canDeposit = NIL }) })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(plan.rules[1].status == "unknown" and #plan.ops == 0, "rights the game didn't state are unknown, not allowed")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", {}, { viewable = false }) })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(plan.rules[1].status == "blocked" and plan.rules[1].code == "tab-hidden", "a tab the rank can't see blocks the rule")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Renamed") })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(plan.rules[1].status == "blocked" and plan.rules[1].code == "tab-renamed" and #plan.ops == 0, "a tab renamed since the rule chose it blocks the rule: same number, other tab")
bank = Bank({ [1] = Tab("Gear") })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(plan.rules[1].status == "blocked" and plan.rules[1].code == "tab-missing", "a tab number the guild bank doesn't have blocks the rule")
-- a snapshot of another guild is not this guild's bank
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth") }, { guild = "Other Guild" })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(#plan.ops == 0 and plan.rules[1].status == "unknown", "a bank snapshot from another guild is not used")
-- the rule itself can't run (no tab chosen on this character)
local noTab = Rule("noTab", { cats = { "7:5" } })
plan = Plan("deposit", { noTab }, Bank({ [1] = Tab("Gear") }), { Bag(0, 1, 2589, 20) }, { problem = function() return "no-guild-tab", "Choose the guild bank tab." end })
Check(plan.rules[1].status == "blocked" and #plan.ops == 0 and Untouched(plan, 2589, "attention"), "a rule that can't run leaves its items in the bags and says why")
-- reorganize: no withdraw right on the tab the item is in
bank = Bank({ [1] = Tab("Gear", { [1] = { 2589, 7 } }, { canWithdraw = false }), [2] = Tab("Cloth") })
reo = Plan("reorganize", { plain }, bank, {})
Check(#reo.ops == 0 and Untouched(reo, 2589, "no-withdraw"), "an item in a tab the rank can't take from stays, and says why")
bank = Bank({ [1] = Tab("Gear", { [1] = { 2589, 7 } }, { canWithdraw = NIL }), [2] = Tab("Cloth") })
reo = Plan("reorganize", { plain }, bank, {})
Check(#reo.ops == 0 and Untouched(reo, 2589, "withdraw-unknown"), "withdraw rights not stated are unknown")
Check(reo.summary.unknown == 1 and reo.summary.blocked == 0, "and counted as unknown")
-- a known allowance for today: more stacks than it allows are blocked
bank = Bank({ [1] = Tab("Gear", { [1] = { 2589, 7 }, [2] = { 2589, 6 }, [3] = { 2589, 5 } }, { remaining = 2 }), [2] = Tab("Cloth") })
reo = Plan("reorganize", { plain }, bank, {})
local limited = 0
for _, o in ipairs(reo.ops) do if o.code == "limit" then limited = limited + 1 end end
Check(#reo.ops == 3 and limited == 1, "a known withdrawal allowance of 2 stacks blocks the third")
-- reorganize into a full tab, and a loop of full tabs: needs room that isn't there
local fullA, fullB = {}, {}
for s = 1, 98 do fullA[s] = { 2447, 20 }; fullB[s] = { 2447, 20 } end
fullA[1] = { 2589, 7 }
bank = Bank({ [1] = Tab("Gear", fullA), [2] = Tab("Cloth", fullB) })
reo = Plan("reorganize", { plain }, bank, {})
Check(#reo.ops == 0 and Untouched(reo, 2589, "needs-space"), "gathering into a full tab with nothing leaving it needs room that isn't there")
Check(Untouched(reo, 2589, "needs-space").text:find("swaps"), "and says swaps and parking aren't used")
-- but a slot freed by something else leaving makes room, in the right order (the linen rule is first in the list, so
-- it is tried first, waits, and is placed once the herb has left tab 2)
Item(6000, "Junk", 20, 15, 0)
local herbRule = Where(Rule("herbs2", { cats = { "7:9" } }), 1, "Gear")
local tab1, tab2 = { [1] = { 2589, 7 } }, {}
for s = 2, 97 do tab1[s] = { 6000, 1 } end
for s = 1, 97 do tab2[s] = { 6000, 1 } end
tab2[98] = { 2447, 5 }
bank = Bank({ [1] = Tab("Gear", tab1), [2] = Tab("Cloth", tab2) })
reo = Plan("reorganize", { plain, herbRule }, bank, {})
Check(#reo.ops == 2, "two operations: the herb leaves tab 2 and the linen takes its place: " .. #reo.ops)
Check(reo.ops[1] and reo.ops[1].id == 2447 and reo.ops[1].to.tab == 1 and reo.ops[1].to.slot == 98, "the herb goes first, to the one free slot in tab 1")
Check(reo.ops[2] and reo.ops[2].id == 2589 and reo.ops[2].to.tab == 2 and reo.ops[2].to.slot == 98, "then the linen uses the slot the herb left")
Check(Item1(reo, 2589).state == "moves" and Item1(reo, 2447).state == "moves", "both are settled")
-- when two full tabs each need the other's slot, nothing is done: no swap, no parking
tab1[98] = { 6000, 1 }
bank = Bank({ [1] = Tab("Gear", tab1), [2] = Tab("Cloth", tab2) })
reo = Plan("reorganize", { plain, herbRule }, bank, {})
Check(#reo.ops == 0 and Untouched(reo, 2589, "needs-space") and Untouched(reo, 2447, "needs-space"), "two full tabs that need each other's room: both reported as needing space, nothing swapped")
Check(reo.summary.blocked == 2, "and counted as blocked: " .. reo.summary.blocked)

-- stale and mixed readings
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth", {}, { state = "earlier", age = 400 }) })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(plan.freshness == "earlier" and #plan.ops == 1, "a destination tab read earlier (another tab shown) is still planned, and the plan says it is an earlier reading")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth") })
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(plan.freshness == "live", "a destination tab that is shown now is current")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth") }, { open = false })
bank.tabs[2].state = "closed"
plan = Plan("deposit", { plain }, bank, { Bag(0, 1, 2589, 20) })
Check(plan.freshness == "stale", "a bank that has been closed gives a stale plan")
local rule4 = Where(Rule("r4", { cats = { "7:9" } }), 3, "Herbs")
bank = Bank({ [1] = Tab("Gear"), [2] = Tab("Cloth"), [3] = Tab("Herbs", {}, { state = "earlier" }) })
plan = Plan("deposit", { plain, rule4 }, bank, { Bag(0, 1, 2589, 20), Bag(0, 2, 2447, 5) })
Check(plan.freshness == "mixed", "one live tab and one read earlier: mixed")
Check(plan.seq == 1 and plan.guild == "Night Owls", "the plan keeps the guild and the reading it was made from")

-- items whose data is not there are unresolved, not guessed
bank = Bank({ [1] = Tab("Gear", { [1] = { 4242, 5 }, [2] = { nil, 5 } }), [2] = Tab("Cloth") })
reo = Plan("reorganize", { plain }, bank, {})
Check(Untouched(reo, 4242, "item-unknown") ~= nil and reo.summary.unknown >= 1, "an item the game has no data for is unresolved, not guessed")
Check(reo.tabs[1].current[1].unknown and reo.tabs[1].current[2].unknown, "and its cell is marked unknown")
bank = Bank({ [1] = Tab("Gear", { [1] = { 2589, 5 } }), [2] = Tab("Cloth") })
reo = Plan("reorganize", { plain }, bank, {}, { facts = function(id) return nil, true end })
Check(Untouched(reo, 2589, "item-pending") ~= nil, "an item the game is still loading is unresolved")

---------------------------------------------------------------------------
-- 5b. Many arrangements: every plan can be replayed one operation at a time, without a swap, and ends as the plan says
---------------------------------------------------------------------------
do
  local function Replay(plan, bank, stacks)
    -- the world: bank cells and bag stacks as simple tables
    local world = { bank = {}, bag = {} }
    for i, t in pairs(bank.tabs) do
      world.bank[i] = {}
      for sl, cell in pairs(t.slots or {}) do world.bank[i][sl] = { id = cell.id, count = cell.count } end
    end
    for _, st in ipairs(stacks) do world.bag[st.bag .. ":" .. st.slot] = { id = st.id, count = st.count } end
    for _, o in ipairs(plan.ops) do
      local src = o.from.kind == "bag" and world.bag[o.from.bag .. ":" .. o.from.slot] or world.bank[o.from.tab][o.from.slot]
      if not src or src.count < o.count then return false, "op " .. o.n .. ": the source doesn't hold " .. o.count end
      if src.id ~= o.id then return false, "op " .. o.n .. ": the source holds another item" end
      local dest = world.bank[o.to.tab][o.to.slot]
      local limit = FACTS[o.id].maxStack
      if dest then
        if dest.id ~= o.id then return false, "op " .. o.n .. ": the destination holds another item (a swap)" end
        if dest.count + o.count > limit then return false, "op " .. o.n .. ": the destination overflows" end
        dest.count = dest.count + o.count
      else
        world.bank[o.to.tab][o.to.slot] = { id = o.id, count = o.count }
      end
      src.count = src.count - o.count
      if src.count == 0 then
        if o.from.kind == "bag" then world.bag[o.from.bag .. ":" .. o.from.slot] = nil else world.bank[o.from.tab][o.from.slot] = nil end
      end
    end
    for i, v in pairs(plan.tabs) do
      if v.proposed then
        for sl = 1, 98 do
          local want, got = v.proposed[sl], world.bank[i][sl]
          if (want == nil) ~= (got == nil) or (want and (want.id ~= got.id or want.count ~= got.count)) then
            return false, ("tab %d slot %d: replay and plan differ"):format(i, sl)
          end
        end
      end
    end
    return true
  end
  local function Totals(bank, stacks, plan)
    local t = {}
    for _, tab in pairs(bank.tabs) do for _, cell in pairs(tab.slots or {}) do t[cell.id] = (t[cell.id] or 0) + cell.count end end
    for _, st in ipairs(stacks) do t[st.id] = (t[st.id] or 0) + st.count end
    return t
  end
  math.randomseed(20261030)
  local sizes = { 2589, 3000, 9100 }
  local stackOf = { [2589] = 20, [3000] = 200, [9100] = 1 }
  local bad, runs = 0, 0
  local stats = { ops = 0, splits = 0, settled = 0 }
  for trial = 1, 150 do
    local tabs = {}
    for t = 1, 3 do
      local slots = {}
      for sl = 1, 98 do
        if math.random() < (trial % 5 == 0 and 0.97 or 0.2) then
          local id = sizes[math.random(1, 3)]
          slots[sl] = { id, id == 9100 and 1 or math.random(1, stackOf[id]) }
        end
      end
      tabs[t] = Tab("Tab" .. t, slots)
    end
    local stacks = {}
    for i = 1, math.random(0, 12) do
      local id = sizes[math.random(1, 3)]
      stacks[#stacks + 1] = Bag(0, i, id, id == 9100 and 1 or math.random(1, stackOf[id]))
    end
    local pick = { 0, 5, 10, 20 }
    local bigPick = { 0, 30, 50, 100, 200 }
    WHERE = {}
    local rs = {
      Where(Rule("a", { include = { [2589] = true }, stack = pick[math.random(1, 4)] }), math.random(1, 3), "Tab" .. 1),
      Where(Rule("b", { include = { [3000] = true }, stack = bigPick[math.random(1, 5)] }), math.random(1, 3), "Tab" .. 1),
      Where(Rule("c", { include = { [9100] = true } }), math.random(1, 3), "Tab" .. 1),
    }
    for _, r in ipairs(rs) do WHERE[r.dest].tabName = "Tab" .. WHERE[r.dest].tab end
    local bnk = Bank(tabs)
    for _, mode in ipairs({ "deposit", "reorganize" }) do
      local frozen = Deep(bnk)
      local plan = Plan(mode, rs, bnk, stacks, { split = true })
      runs = runs + 1
      local ok, why = Replay(plan, bnk, stacks)
      if not ok then bad = bad + 1; print(("trial %d %s: %s"):format(trial, mode, why)) end
      if not Same(frozen, bnk) then bad = bad + 1; print(("trial %d %s: the snapshot was changed"):format(trial, mode)) end
      -- nothing is made or lost
      local before = Totals(bnk, stacks)
      local after = {}
      for _, v in pairs(plan.tabs) do
        for _, cell in pairs(v.proposed or {}) do after[cell.id] = (after[cell.id] or 0) + cell.count end
      end
      for id, n in pairs(before) do
        local inBags = 0
        for _, st in ipairs(stacks) do if st.id == id then inBags = inBags + st.count end end
        local movedFromBags = 0
        for _, o in ipairs(plan.ops) do if o.id == id and o.from.kind == "bag" then movedFromBags = movedFromBags + o.count end end
        local inBank = n - inBags
        if (after[id] or 0) ~= inBank + movedFromBags then
          bad = bad + 1
          print(("trial %d %s: item %d: %d in the bank + %d from bags, but the plan holds %d"):format(trial, mode, id, inBank, movedFromBags, after[id] or 0))
        end
      end
      if mode == "deposit" then
        for _, o in ipairs(plan.ops) do if o.from.kind ~= "bag" then bad = bad + 1; print("trial " .. trial .. ": a deposit took from the bank") end end
      else
        for _, o in ipairs(plan.ops) do if o.from.kind ~= "bank" then bad = bad + 1; print("trial " .. trial .. ": a reorganize took from the bags") end end
      end
      stats.ops, stats.splits = stats.ops + #plan.ops, stats.splits + plan.summary.splits
      if mode == "reorganize" then
        -- an item that was settled ends as its rule says: all in the rule's tab, in stacks of the target and one smaller
        for _, r in ipairs(rs) do
          local id = r.include and next(r.include)
          local it = Item1(plan, id)
          local S = r.stack
          if it and (it.state == "moves" or it.state == "inplace") then
            stats.settled = stats.settled + 1
            local T = WHERE[r.dest].tab
            local small = 0
            for t, v in pairs(plan.tabs) do
              for _, cell in pairs(v.proposed or {}) do
                if cell.id == id then
                  if t ~= T then bad = bad + 1; print(("trial %d: item %d left outside its tab"):format(trial, id)) end
                  if S > 0 and stackOf[id] > 1 and cell.count > S then bad = bad + 1; print(("trial %d: item %d stack %d above target %d"):format(trial, id, cell.count, S)) end
                  if S > 0 and stackOf[id] > 1 and cell.count < S then small = small + 1 end
                end
              end
            end
            if small > 1 then bad = bad + 1; print(("trial %d: item %d has %d remainder stacks"):format(trial, id, small)) end
          end
        end
      end
      -- the same inputs, the same plan
      if Digest(Plan(mode, rs, bnk, stacks, { split = true })) ~= Digest(plan) then bad = bad + 1; print("trial " .. trial .. ": not deterministic") end
    end
  end
  Check(stats.ops > 500 and stats.splits > 50 and stats.settled > 50, ("the random arrangements exercise real work: %d ops, %d splits, %d settled items"):format(stats.ops, stats.splits, stats.settled))
  Check(bad == 0, ("%d random arrangements replayed in order without a swap, an overflow, a lost item or a changed input (%d problems)"):format(runs, bad))
end

---------------------------------------------------------------------------
-- 6. Read-only planning
---------------------------------------------------------------------------
local rulesIn = { cloth, herbs, both }
bank = Bank({ [1] = Tab("Gear", { [1] = { 2589, 8 } }), [2] = Tab("Cloth", { [1] = { 2589, 9 } }), [3] = Tab("Herbs"), [4] = Tab("Everything") })
bags = { Bag(0, 1, 2589, 20), Bag(0, 2, 2447, 10), Bag(0, 3, 2592, 5) }
local before = { Deep(rulesIn), Deep(bank), Deep(bags) }
local p1 = Plan("deposit", rulesIn, bank, bags, { split = true })
local p2 = Plan("deposit", rulesIn, bank, bags, { split = true })
Check(Same(before[1], rulesIn) and Same(before[2], bank) and Same(before[3], bags), "making a plan changes none of its inputs (rules, snapshot, bags)")
Check(Digest(p1) == Digest(p2) and Digest(p1) ~= "", "the same inputs give the same plan, twice")
local r1 = Plan("reorganize", rulesIn, bank, bags, { split = true })
Check(Same(before[2], bank), "a reorganize leaves the snapshot alone too")
-- plan cells are copies: editing a plan doesn't touch the snapshot
r1.tabs[1].current[1].count = 999
Check(bank.tabs[1].slots[1].count == 8, "a plan's cells are not the snapshot's tables")

---------------------------------------------------------------------------
-- 7. Reading the game: the snapshot, events, and no mutating calls
---------------------------------------------------------------------------
local calls = {}
local function Count(name) return function() calls[name] = (calls[name] or 0) + 1 end end
for _, name in ipairs({ "PickupGuildBankItem", "SplitGuildBankItem", "AutoStoreGuildBankItem", "SetCurrentGuildBankTab", "QueryGuildBankTab",
    "DepositGuildBankMoney", "WithdrawGuildBankMoney", "BuyGuildBankTab", "UseContainerItem", "PickupItem" }) do
  c[name] = Count(name)
end
c.C_Container.PickupContainerItem = Count("PickupContainerItem")
c.C_Container.SplitContainerItem = Count("SplitContainerItem")
c.C_Container.UseContainerItem = Count("C_UseContainerItem")
c.SplitContainerItem = Count("SplitContainerItem")
c.ClearCursor = Count("ClearCursor")

c.TwichUIDB.ui = nil
c.TwichUIDB.magicInventory = nil
c.TwichUIDB.modules.magicInventory = true
MI.Refresh()
c.GUILD.name = "Night Owls"
c.GUILD.tabs = {
  [1] = { name = "Gear", icon = 5, withdraw = -1, remaining = 3, slots = { [1] = { id = 2589, count = 8 } } },
  [2] = { name = "Cloth", icon = 133, withdraw = -1, slots = { [4] = { id = 2592, count = 11 } } },
  [3] = { name = "Herbs", icon = 134, withdraw = 0, canDeposit = false, slots = {} },
}
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2447, 10 } } } })
local clothDest = MI.AddDest("guild", "Cloth tab")
MI.SetGuildTab(clothDest, "Night Owls", 2, "Cloth", 133)
local herbDest = MI.AddDest("guild", "Herb tab")
MI.SetGuildTab(herbDest, "Night Owls", 3, "Herbs", 134)
local gId = MI.SaveRule({ kind = "guild", name = "Cloth to tab 2", enabled = true, dest = clothDest, cats = { "7:5" }, stack = 20 })
local hId = MI.SaveRule({ kind = "guild", name = "Herbs to tab 3", enabled = true, dest = herbDest, cats = { "7:9" } })
Check(MI.Rule(gId).enabled and MI.Rule(hId).enabled, "the rules are on")

-- before the bank opens: nothing is known
plan = MI.CurrentGuildPlan("deposit")
Check(#plan.ops == 0 and plan.rules[1].status == "unknown" and plan.freshness == "stale", "the bank has not been opened: unknown and stale, not empty")
-- the bank opens: tabs and rights are known, items are not until the game sends them
c.OpenGuildBank()
local snap = GB.Snapshot()
Check(snap.open and snap.guild == "Night Owls" and snap.numTabs == 3, "the open bank gives the guild and the tab count")
Check(snap.tabs[2].name == "Cloth" and snap.tabs[2].icon == 133 and snap.tabs[3].canDeposit == false and snap.tabs[1].canWithdraw == true and snap.tabs[3].canWithdraw == false, "and each tab's name, icon and the rank's rights")
Check(snap.tabs[1].state == "unread" and snap.tabs[1].slots == nil, "but a tab whose items haven't arrived is unread, not empty")
Check(snap.tabs[1].remaining == nil or snap.tabs[1].state == "unread", "(and no allowance is claimed for it yet)")
Check(MI.GuildTabsSeen("Night Owls")[2].name == "Cloth", "the tab names are remembered for choosing a tab with the bank closed")
plan = MI.CurrentGuildPlan("deposit")
Check(#plan.ops == 0 and plan.rules[1].status == "unknown", "so a rule for an unread tab stays unknown")
-- the game sends the shown tab
c.GUILD.current = 2
c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
snap = GB.Snapshot()
Check(snap.tabs[2].state == "live" and snap.tabs[2].slots[4].id == 2592 and snap.tabs[2].slots[4].count == 11, "once the game sends the shown tab its items are read (state live)")
Check(snap.tabs[1].state == "unread", "other tabs are still unread")
plan = MI.CurrentGuildPlan("deposit")
Check(plan.rules[1].status == "ready" and plan.freshness == "live", "now the rule for tab 2 is ready and the plan is current")
Check(#plan.ops >= 1 and plan.ops[1].to.tab == 2, "and the linen is placed in tab 2")
Check(plan.rules[2].status == "blocked" and plan.rules[2].code == "no-deposit", "the herb rule's tab takes no deposits: blocked, not redirected")
Check(Untouched(plan, 2447, "attention") ~= nil, "the herbs stay in the bags")
-- showing another tab: the first becomes "earlier"
c.GUILD.current = 1
c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
snap = GB.Snapshot()
Check(snap.tabs[1].state == "live" and snap.tabs[2].state == "earlier", "showing another tab makes the first one earlier")
Check(snap.tabs[1].remaining == 3 and snap.tabs[2].remaining == nil, "the daily allowance is only reported for the tab shown")
plan = MI.CurrentGuildPlan("deposit")
Check(plan.freshness == "earlier", "a plan on an earlier reading is labelled: " .. tostring(plan.freshness))
-- the bank closes: stale
c.CloseGuildBank()
snap = GB.Snapshot()
Check(not snap.open and snap.tabs[1].state == "closed" and snap.tabs[2].state == "closed", "closing the bank makes every reading closed (stale)")
plan = MI.CurrentGuildPlan("reorganize")
Check(plan.freshness == "stale" and plan.open == false, "a reorganize preview from a closed bank is stale")
-- a reorganize reads only the bank
local gearItems = 0
for _, o in ipairs(plan.ops) do if o.from.kind == "bag" then gearItems = gearItems + 1 end end
Check(gearItems == 0, "(and takes nothing from the bags)")
-- another guild's bank: the old reading is dropped
c.GUILD.name = "Other Guild"
c.OpenGuildBank()
snap = GB.Snapshot()
Check(snap.guild == "Other Guild" and snap.tabs[2].slots == nil, "a different guild starts with nothing read: no leftover items from the other guild")
plan = MI.CurrentGuildPlan("deposit")
Check(#plan.ops == 0 and plan.rules[1].code == "guild-changed", "and the rules chosen in the first guild are not used in the second")
c.CloseGuildBank()

-- the items can arrive before the "opened" event: a bank that is showing counts as open
c.GUILD.name = "Night Owls"
c.GUILD.open = true
c.GUILD.current = 2
c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
snap = GB.Snapshot()
Check(snap.open and snap.tabs[2] and snap.tabs[2].state == "live", "items that arrive before the opened event are kept (the bank frame is showing)")
c.FireEvent("GUILDBANKFRAME_OPENED")
Check(GB.Snapshot().tabs[2].state == "live", "and the opened event after them doesn't throw them away")
c.CloseGuildBank()

-- nothing that moves or asks the server was called, in any of this
local bad = {}
for name, n in pairs(calls) do bad[#bad + 1] = name .. "=" .. n end
table.sort(bad)
Check(#bad == 0, "no pickup, split, deposit, withdraw, tab switch or query call was made: " .. table.concat(bad, ", "))
Check(c.CURSOR == nil, "and the cursor was never touched")

-- turned off: no listeners, nothing kept
c.TwichUIDB.modules.magicInventory = false
MI.Refresh()
Check(GB.ListenerCount() == 0, "with the feature off nothing is listened to")
Check(GB.Snapshot().numTabs == nil and GB.Retained() == 0, "and the snapshot is gone")

if failures == 0 then print("PASSED test_magic_inventory_guild") else print(failures .. " FAILURES"); os.exit(1) end
