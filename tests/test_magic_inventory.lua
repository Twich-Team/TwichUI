-- Magic Inventory (inventory/Rules.lua, Items.lua, Plan.lua): the rules, recipients and the dry-run plan.
--   * categories as the game files them, explicit "Also include" and "Never include", and the Never transfer list;
--   * the precedence: hard protections and the Never transfer list over everything, a rule's exclusions over its
--     inclusions, keep amounts before moving, per-destination restrictions (soulbound: bank yes, mail and guild no);
--   * unknown item data (still loading, binding or lock not said) is never treated as safe;
--   * keep amounts across several stacks and several rules, vendor restocking's target, whole stacks only (and
--     partial stacks only where splitting is allowed);
--   * one owner per item: priority across destinations, shadowed rules, a mailbox not taking what a bank rule owns;
--   * recipients per character (never another character's), shared only when chosen, exact and checked for form;
--   * guild tabs bound to the guild: another guild asks for review;
--   * leaving an entry out of one operation leaves the rule unchanged; mail batches of the game's attachment limit;
--   * templates start off and can't be turned on until their recipient is chosen; nothing real is shipped.
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MIClient("Rich", { files = { "inventory/Rules.lua", "inventory/Items.lua", "inventory/Plan.lua" } })
local MI = c.TwichUI.MagicInventory
Check(MI ~= nil, "Magic Inventory is loaded")
Check(c.TwichUIDB.modules.magicInventory == false, "off by default (explicit true only)")

c.ITEMS[9005] = { name = "Green Ring", class = 4, sub = 0, maxStack = 1, quality = 2, bind = 2, equipLoc = "INVTYPE_FINGER" }
local function Rule(fields)
  local r = { kind = "bank", enabled = true, cats = {}, qualities = {}, include = {}, exclude = {}, equip = "any", bind = "any", keep = 0 }
  for k, v in pairs(fields) do r[k] = v end
  return r
end
local function Save(fields) local id, why = MI.SaveRule(Rule(fields)); Check(id ~= nil, "saved: " .. tostring(why)); return id end
local function Reset()
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  c.TwichUIDB.ui.magicInventory = nil
  c.TwichUIDB.magicInventory = nil
end
local function Find(list, id, field, value)
  for _, e in ipairs(list) do
    if e.id == id and (field == nil or e[field] == value) then return e end
  end
end
local function Entry(plan, id)
  for _, g in ipairs(plan.groups) do
    for _, e in ipairs(g.entries) do if e.id == id then return e, g end end
  end
end

---------------------------------------------------------------------------
-- 1. Categories, explicit inclusion, exclusion
---------------------------------------------------------------------------
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2592, 15 }, [3] = { 2447, 10 }, [4] = { 2770, 5 } } } })
local cloth = Save({ name = "Cloth to bank", cats = { "7:5" } })
local plan = MI.CurrentPlan(nil)
Check(Entry(plan, 2589) and Entry(plan, 2592), "both cloths match the Cloth category")
Check(not Entry(plan, 2447) and not Find(plan.skipped, 2447), "a herb matches nothing and isn't listed")
local r = MI.Rule(cloth); r.include[2447] = true; MI.SaveRule(r)
plan = MI.CurrentPlan(nil)
Check(Entry(plan, 2447) ~= nil, "Also include: a listed item matches though its category doesn't")
r = MI.Rule(cloth); r.exclude[2592] = true; r.exclude[2447] = true; MI.SaveRule(r)
plan = MI.CurrentPlan(nil)
Check(not Entry(plan, 2592), "Never include: an excluded item never matches the rule")
Check(not Entry(plan, 2447), "Never include wins over Also include in the same rule")
Check(Entry(plan, 2589) ~= nil, "the rest of the category still matches")

-- a rule with nothing chosen matches nothing, and can't be turned on
local empty = Save({ name = "Empty", enabled = true })
Check(MI.Rule(empty).enabled == false, "a rule with no items is saved turned off")
local ok, why = MI.SetRuleEnabled(empty, true)
Check(not ok and why:find("Choose which items"), "and can't be turned on: " .. tostring(why))

---------------------------------------------------------------------------
-- 2. The Never transfer list and Never transfer rules beat everything, Also include included
---------------------------------------------------------------------------
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2447, 10 } } } })
local inc = Save({ name = "Herbs", include = { [2447] = true }, cats = { "7:5" } })
MI.SetNever(2447, true)
plan = MI.CurrentPlan(nil)
Check(not Entry(plan, 2447), "the Never transfer list beats an explicit inclusion")
Check(Find(plan.skipped, 2447, "reason", "never"), "and the plan says why")
MI.SetNever(2447, false)
Save({ name = "Protect cloth", kind = "never", cats = { "7:5" } })
plan = MI.CurrentPlan(nil)
Check(not Entry(plan, 2589) and Find(plan.skipped, 2589, "reason", "never-rule"), "a Never transfer rule protects what it matches, even below the transfer rule")
Check(Entry(plan, 2447) ~= nil, "and nothing else")
-- the Never transfer list is account-wide, outside the profile
MI.SetNever(2770, true)
Check(c.TwichUIDB.magicInventory.never[2770] == true and c.TwichUIDB.ui.magicInventory.never == nil, "the Never transfer list is account-wide")
local _ = inc

---------------------------------------------------------------------------
-- 3. Hard protections per stack and per destination; unknown data is never safe
---------------------------------------------------------------------------
Reset()
c.Bags({ [0] = { size = 16, slots = {
  [1] = { 9001, 1 },                    -- BoE green, not bound
  [2] = { 9002, 1, bound = true },      -- a BoE green, now soulbound
  [3] = { 9004, 1, bound = true },      -- BoP green
  [4] = { 5000, 5, quest = true },      -- quest item
  [5] = { 8079, 10 },                   -- conjured water (known ID)
  [6] = { 9005, 1, inSet = true },      -- in an equipment set
  [7] = { 1179, 5, locked = true },     -- locked
} } })
local mailDest = MI.AddDest("mail", "Friend")
MI.SetRecipient(mailDest, "Friendname")
local greens = Save({ name = "Greens", kind = "mail", dest = mailDest, equip = "equipment", qualities = { [2] = true } })
Check(MI.Rule(greens).enabled, "a complete mail rule can be on")
plan = MI.CurrentPlan(nil)
Check(Entry(plan, 9001) ~= nil, "an unbound green goes by mail")
Check(Find(plan.skipped, 9002, "reason", "bound-mail") and Find(plan.skipped, 9004, "reason", "bound-mail"), "soulbound items can't be mailed")
-- the same items to the bank: soulbound is fine there
MI.SaveRule((function() local x = MI.Rule(greens); x.kind = "bank"; x.dest = nil; return x end)())
plan = MI.CurrentPlan(nil)
Check(Entry(plan, 9002) ~= nil and Entry(plan, 9004) ~= nil, "soulbound items may go to the bank")
Check(Find(plan.skipped, 9005, "reason", "equipment-set"), "an equipment-set item is protected")
-- BoE filter: a BoE item that is bound now doesn't count as binding on equip
local boe = Save({ name = "BoE", kind = "bank", bind = "boe", equip = "equipment" })
MI.MoveRule(boe, -1)
plan = MI.CurrentPlan(nil)
Check(Entry(plan, 9001) and Entry(plan, 9001).rule == "BoE", "the BoE rule (moved up) owns the unbound BoE item")
Check(Find(plan.skipped, 9002, "reason", "bound-now"), "a bound BoE item is not 'binds when equipped' any more")
Check(not Find(plan.skipped, 9004, "rule", "BoE"), "a BoP item never matched the BoE rule")
-- the game not saying whether a quest needs it is not "no"
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
local questInfo = c.C_Container.GetContainerItemQuestInfo
c.C_Container.GetContainerItemQuestInfo = function() return nil end
Save({ name = "Cloth", cats = { "7:5" } })
plan = MI.CurrentPlan(nil)
Check(Find(plan.skipped, 2589, "reason", "quest-unknown"), "quest state not said: it stays")
c.C_Container.GetContainerItemQuestInfo = questInfo
-- quest, conjured, locked
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 5000, 5, quest = true }, [2] = { 8079, 10, conjured = true }, [3] = { 1179, 5, locked = true }, [4] = { 1179, 5 } } } })
Save({ name = "Everything", include = { [5000] = true, [8079] = true, [1179] = true } })
plan = MI.CurrentPlan(nil)
Check(Find(plan.skipped, 5000, "reason", "quest"), "a quest item is protected even when included by ID")
Check(Find(plan.skipped, 8079, "reason", "conjured"), "a conjured item is protected even when included by ID")
Check(Find(plan.skipped, 1179, "reason", "locked"), "a locked stack stays")
local milk = Entry(plan, 1179)
Check(milk and milk.count == 5 and milk.stacks == 1, "the unlocked stack of the same item still moves")
-- unknown: binding not said, item still loading, tooltip unreadable
Reset()
c.UNKNOWN_BOUND = { [2589] = true }
c.UNLOADED[2592] = true
MI.ClearItemCache()
c.TOOLTIP_UNREADABLE[1179] = true
c.ITEMS[1179].conjuredUnknown = true
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2592, 20 }, [3] = { 1179, 5 } } } })
local friend = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(friend, "Bankalt")
Save({ name = "Mail it", kind = "mail", dest = friend, cats = { "7:5" }, include = { [1179] = true } })
plan = MI.CurrentPlan(nil)
Check(Find(plan.skipped, 2589, "reason", "binding-unknown"), "binding not said: not mailed")
Check(Find(plan.skipped, 2592, "reason", "pending") and plan.pending == 1, "an item still loading is left out and counted")
Check(c.REQUESTED[2592] ~= nil, "and the game is asked to load it")
Check(Find(plan.skipped, 1179, "reason", "conjured-unknown"), "a consumable whose tooltip can't be read isn't assumed unconjured")
c.UNKNOWN_BOUND, c.UNLOADED, c.TOOLTIP_UNREADABLE = nil, {}, {}
MI.ClearItemCache()

---------------------------------------------------------------------------
-- 4. Keep amounts: each item, every carried stack, the most any rule keeps; whole stacks only
---------------------------------------------------------------------------
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2589, 20 }, [3] = { 2589, 8 }, [4] = { 2592, 20 }, [5] = { 2592, 5 } } } })
local keep20 = Save({ name = "Cloth", cats = { "7:5" }, keep = 20 })
plan = MI.CurrentPlan(nil)
local linen, wool = Entry(plan, 2589), Entry(plan, 2592)
Check(linen and linen.count == 28 and linen.stacks == 2, "keep 20 of 48 linen: the 20 and the 8 move, 20 stay")
Check(wool and wool.count == 5, "keep 20 of 25 wool: the 5 moves (the 20 would leave too few)")
-- the keep is per item, not shared across the category
Check(linen.keep == 20 and wool.keep == 20, "keep applies to each item")
MI.SaveRule((function() local x = MI.Rule(keep20); x.keep = 25; return x end)())
plan = MI.CurrentPlan(nil)
linen, wool = Entry(plan, 2589), Entry(plan, 2592)
Check(linen and linen.count == 20 and linen.stacks == 1, "keep 25 of 48 linen: one whole stack of 20 moves")
Check(linen and linen.extraKept == 3, "and the plan says 3 more than the keep amount stay: " .. tostring(linen and linen.extraKept))
Check(not wool and Find(plan.skipped, 2592, "reason", "keep"), "keep 25 of 25 wool: nothing moves, and it says so")
-- a Keep in bags rule raises it, whatever its place in the list
Save({ name = "Keep lots of linen", kind = "keep", include = { [2589] = true }, keep = 30 })
plan = MI.CurrentPlan(nil)
linen = Entry(plan, 2589)
Check(linen and linen.count == 8 and linen.keep == 30 and linen.extraKept == 10, "a Keep in bags rule raises the keep for that item (48 - 30 = 18: the 8 moves, 10 extra stay)")
-- two transfer rules can't combine to pass a keep amount: the second only shadows
local altDest = MI.DestNamed("mail", "Alt")
MI.SetRecipient(altDest, "Altname")
Save({ name = "Cloth by mail", kind = "mail", dest = altDest, cats = { "7:5" } })
plan = MI.CurrentPlan(nil)
Check(Find(plan.shadowed, 2589, "rule", "Cloth by mail"), "a later matching rule is shadowed")
local moved = 0
for _, g in ipairs(plan.groups) do for _, e in ipairs(g.entries) do if e.id == 2589 then moved = moved + e.count end end end
Check(moved == 8, "and the item is allocated once: " .. moved)
-- splitting: off by default; when allowed the keep amount is met exactly
local p2 = MI.BuildPlan({ stacks = MI.ReadBags().stacks, rules = MI.Rules(), never = MI.IsNever, resolve = MI.Resolve,
  problem = function(x) return MI.Problem(x, false) end, split = { bank = true } })
linen = Entry(p2, 2589)
Check(linen and linen.count == 18, "with splitting allowed, exactly carried - keep moves: " .. tostring(linen and linen.count))
local partial = false
for _, t in ipairs(linen.take) do if t.partial then partial = true end end
Check(partial, "and one stack is partial")
-- vendor restocking's target counts as a keep amount (only while it protects the item)
local restockOn = true
c.TwichUI.Restock = { Protects = function(id) return restockOn and id == 2589 end, Rule = function() return { target = 40 } end }
plan = MI.CurrentPlan(nil)
linen = Entry(plan, 2589)
Check(linen and linen.keep == 40 and linen.count == 8, "a restocking target of 40 keeps 40 of the 48: " .. tostring(linen and linen.keep))
restockOn = false
plan = MI.CurrentPlan(nil)
Check(Entry(plan, 2589).keep == 30, "and stops counting when restocking no longer protects it")
c.TwichUI.Restock = nil
local _ = keep20

---------------------------------------------------------------------------
-- 5. Priority across destinations; the mailbox doesn't take what a bank rule owns; no reroute
---------------------------------------------------------------------------
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 }, [2] = { 2589, 20 } } } })
local bankAlt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(bankAlt, "bankalt")
local herbsBank = Save({ name = "Herbs to bank", cats = { "7:9" } })
local allMail = Save({ name = "Trade goods to alt", kind = "mail", dest = bankAlt, cats = { "7" } })
plan = MI.CurrentPlan("mail")
Check(not Entry(plan, 2447), "at a mailbox, herbs owned by the bank rule above aren't mailed")
local res = Find(plan.reserved, 2447)
Check(res and res.rule == "Herbs to bank", "they are shown as reserved by \"Herbs to bank\"")
Check(Entry(plan, 2589) ~= nil, "cloth goes to the alt")
-- reorder: now the mail rule owns herbs too
MI.MoveRule(allMail, -1)
plan = MI.CurrentPlan("mail")
Check(Entry(plan, 2447) ~= nil, "after moving the mail rule up it owns the herbs")
-- a destination that is unavailable: the item waits, it is not rerouted
MI.SetRecipient(bankAlt, nil)
plan = MI.CurrentPlan("bank")
Check(not Entry(plan, 2447) and Find(plan.reserved, 2447), "with the mail rule's recipient cleared the bank still doesn't take its items")
plan = MI.CurrentPlan("mail")
Check(Find(plan.skipped, 2447, "reason", "attention") and #plan.attention == 1, "at the mailbox the rule needs attention")
local _2 = herbsBank

---------------------------------------------------------------------------
-- 6. Recipients: exact, per character, shared only when chosen; form only
---------------------------------------------------------------------------
Reset()
Check(MI.NormalizeRecipient("  bankALT ") == "Bankalt", "trimmed and capitalized as the game does")
Check(MI.NormalizeRecipient("Bankalt-Other Realm") == "Bankalt-OtherRealm", "another realm, spaces removed")
Check(MI.NormalizeRecipient("Bank alt") == nil, "a space is refused")
Check(MI.NormalizeRecipient("B") == nil, "too short is refused")
Check(MI.NormalizeRecipient("Abcdefghijklm") == nil, "13 letters is refused")
Check(MI.NormalizeRecipient("Rich") == nil, "this character is refused")
Check(MI.NormalizeRecipient("Zoë") == "Zoë", "letters beyond ASCII are kept as typed")
local d = MI.AddDest("mail", "Bank alt")
Check(MI.Resolve(d) == nil, "a new destination has no recipient")
MI.SetRecipient(d, "Bankalt")
Check(MI.Resolve(d).recipient == "Bankalt", "this character's recipient")
Check(c.TwichUIDB.ui.magicInventory.dests[1].recipient == nil, "the profile holds only the name, never the recipient")
-- another character on the same profile and account: no recipient
c.UnitName = function() return "Other" end
Check(MI.Resolve(d) == nil, "another character never uses this character's recipient")
local saved = MI.Rule(Save({ name = "Cloth", kind = "mail", dest = d, cats = { "7:5" } }))
Check(saved.enabled == false, "and its rule is saved off there (needs a recipient)")
-- shared on purpose
c.UnitName = function() return "Rich" end
MI.SetRecipient(d, "Bankalt", true)
c.UnitName = function() return "Other" end
local w = MI.Resolve(d)
Check(w and w.recipient == "Bankalt" and w.shared, "a recipient shared with all characters is used, and marked shared")
MI.SetRecipient(d, "Otherbank")
Check(MI.Resolve(d).recipient == "Otherbank" and not MI.Resolve(d).shared, "a character's own recipient wins over the shared one")
c.UnitName = function() return "Rich" end

---------------------------------------------------------------------------
-- 7. Guild tabs belong to a guild
---------------------------------------------------------------------------
Reset()
c.GUILD.name = "Hearth Guild"
local g = MI.AddDest("guild", "Mats tab")
local gr = Save({ name = "Mats", kind = "guild", dest = g, cats = { "7" } })
Check(MI.Problem(MI.Rule(gr), "Hearth Guild") == "no-guild-tab", "a guild rule needs a tab chosen on this character")
MI.SetGuildTab(g, "Hearth Guild", 2, "Mats")
Check(MI.Problem(MI.Rule(gr), "Hearth Guild") == nil, "chosen in this guild: fine")
local code, text = MI.Problem(MI.Rule(gr), "Another Guild")
Check(code == "guild-changed" and text:find("Hearth Guild") and text:find("Another Guild"), "another guild: needs review, naming both")
Check(MI.Problem(MI.Rule(gr), nil) == "guild-changed", "no guild now: needs review")
local where = MI.Resolve(g)
Check(where.guild == "Hearth Guild" and where.tab == 2 and where.tabName == "Mats", "the exact guild and tab are kept")

---------------------------------------------------------------------------
-- 8. Leaving out of one operation; attachment batching
---------------------------------------------------------------------------
Reset()
local slots = {}
for i = 1, 13 do slots[i] = { 2589, 20 } end
slots[14] = { 2447, 5 }
c.Bags({ [0] = { size = 16, slots = slots } })
local alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
local rid = Save({ name = "Cloth and herbs", kind = "mail", dest = alt, cats = { "7:5", "7:9" } })
plan = MI.CurrentPlan("mail")
local grp = plan.groups[1]
Check(grp and grp.stacks == 14 and grp.mails == 2, "14 stacks to one recipient: 2 mails: " .. tostring(grp and grp.mails))
Check(#grp.batches[1] == 12 and #grp.batches[2] == 2, "12 then 2")
local herbKey = Entry(plan, 2447).key
local before = c.TwichUIDB.ui.magicInventory.rules[1]
local copy = {}
for k, v in pairs(before) do copy[k] = v end
plan = MI.CurrentPlan("mail", { [herbKey] = true })
grp = plan.groups[1]
Check(grp.stacks == 13 and grp.mails == 2 and #grp.batches[2] == 1, "leaving the herbs out removes them from this operation")
Check(Entry(plan, 2447).leftOut == true, "and the entry is still listed as left out")
local after = c.TwichUIDB.ui.magicInventory.rules[1]
local same = true
for k, v in pairs(copy) do if after[k] ~= v then same = false end end
Check(same and #after.cats == 2, "the saved rule is unchanged")
local _3 = rid

---------------------------------------------------------------------------
-- 9. Templates
---------------------------------------------------------------------------
Reset()
for _, t in ipairs(MI.TEMPLATES) do
  local rule, label = MI.FromTemplate(t.key)
  Check(rule.enabled == false, t.key .. ": starts off")
  if t.kind == "mail" then
    rule.dest = MI.DestNamed("mail", label)
    local id = MI.SaveRule(rule)
    Check(MI.Rule(id).enabled == false and MI.Resolve(rule.dest) == nil, t.key .. ": saved without any recipient")
    local ok2 = MI.SetRuleEnabled(id, true)
    Check(not ok2, t.key .. ": can't be turned on until a recipient is chosen")
  end
end
local clothRule = MI.FromTemplate("cloth")
Check(clothRule.cats[1] == "7:5" and clothRule.name == "Cloth to bank alt", "the cloth template uses the game's category for Linen Cloth and its name")
local oreRule = MI.FromTemplate("ore")
Check(oreRule.name == "Metal & Stone to bank", "the ore template is named for what the game puts with ore: " .. oreRule.name)
local boeRule = MI.FromTemplate("boe")
Check(boeRule.bind == "boe" and boeRule.qualities[2] and boeRule.equip == "equipment", "BoE uncommon equipment")
Check(not boeRule.name:lower():find("disenchant"), "never promised as disenchantable")
for _, t in ipairs(MI.TEMPLATES) do Check(t.recipient == nil, "templates name no recipient") end

---------------------------------------------------------------------------
-- 10. Reading never writes; damaged entries are left out
---------------------------------------------------------------------------
Reset()
c.TwichUIDB.ui.magicInventory = { rules = { "junk", { id = "x", kind = "teleport" }, { id = "rgood", kind = "bank", name = "Good", enabled = true, cats = { "7:5", "bad", 7 } } } }
local rules = MI.Rules()
Check(#rules == 1 and rules[1].id == "rgood" and #rules[1].cats == 1, "only usable rules and categories are read")
Check(type(c.TwichUIDB.ui.magicInventory.rules[1]) == "string", "reading changed nothing saved")

---------------------------------------------------------------------------
-- 11. Nothing private leaves: recipients are outside the profile, shares and backups
---------------------------------------------------------------------------
Reset()
local privateDest = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(privateDest, "Secretalt")
MI.SaveRule({ name = "Cloth", kind = "mail", dest = privateDest, enabled = true, cats = { "7:5" } })
local function Holds(t, text, seen)
  seen = seen or {}
  if seen[t] then return false end
  seen[t] = true
  for k, v in pairs(t) do
    if v == text or k == text then return true end
    if type(v) == "table" and Holds(v, text, seen) then return true end
  end
  return false
end
Check(Holds(c.TwichUIDB.magicInventory, "Secretalt"), "the recipient is saved in the account's own table")
Check(not Holds(c.TwichUIDB.ui, "Secretalt"), "and nowhere in the profile")
local RS = c.TwichUI.Restore
Check(RS.OWN_LEFT_OUT.magicInventory ~= nil, "backups leave recipients out")
for _, key in ipairs(RS.OWN_KEYS) do Check(key ~= "magicInventory", "and don't list them as a setting") end
local TC = c.TwichUI.TwichConfig
Check(TC.LOCAL["magicInventory"] and TC.LOCAL["ui.magicInventory"] and TC.LOCAL["modules.magicInventory"], "sharing keeps the switch, the rules and the recipients local")
-- what a copied profile carries: the rule, off for anyone without a recipient of their own
local copied = MI.CleanRule(c.TwichUIDB.ui.magicInventory.rules[1])
c.UnitName = function() return "Other" end
Check(MI.Resolve(copied.dest) == nil and MI.Problem(copied, false) == "no-recipient", "a rule reaching another character needs its own recipient there")
local planned = MI.BuildPlan({ stacks = {}, rules = { copied }, resolve = MI.Resolve, problem = function(x) return MI.Problem(x, false) end })
Check(#planned.groups == 0, "and moves nothing there")
c.UnitName = function() return "Rich" end

if failures == 0 then print("PASSED test_magic_inventory") else print(failures .. " failures") os.exit(1) end
