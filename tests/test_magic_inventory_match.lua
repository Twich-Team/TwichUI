-- Magic Inventory (inventory/Items.lua): MI.Match and MI.QualityName, called directly.
--   * MI.Match returns "included" (the rule's Also include list), "matched" (its filters), "excluded"
--     (its Never include list) or nil (Items.lua:138-139);
--   * an excluded item is never matched, whatever else is true; a rule with no filters at all matches
--     only what it lists (Items.lua:154-155);
--   * bind "boe" requires bindType 2 and a stack not already bound -- bound or unknown: not "binds when
--     equipped" any more (Items.lua:160-162); bind "nobind" requires bindType 0;
--   * equip "equipment"/"other" filter on facts.equipment;
--   * MI.QualityName falls back to Poor..Legendary when the game's ITEM_QUALITY*_DESC globals are absent.
dofile(TESTS .. "harness.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MakeClient("Rich", { "!!!TwichUI" })
for _, f in ipairs({ "inventory/Rules.lua", "inventory/Items.lua" }) do
  local chunk = assert(loadfile(ROOT .. f))
  setfenv(chunk, c)
  chunk("!!!TwichUI", {})
end
local MI = c.TwichUI.MagicInventory
Check(MI ~= nil and MI.Match ~= nil and MI.QualityName ~= nil, "Magic Inventory's Match and QualityName are loaded")

local function Rule(fields)
  local r = { kind = "bank", enabled = true, cats = {}, qualities = {}, include = {}, exclude = {}, equip = "any", bind = "any", keep = 0 }
  for k, v in pairs(fields) do r[k] = v end
  return r
end
-- facts as MI.ItemFacts would hand them over; only the fields Match reads matter
local function Facts(fields)
  local f = { id = 1, classID = 7, subclassID = 5, quality = 1, bindType = 0, equipment = false }
  for k, v in pairs(fields) do f[k] = v end
  return f
end

---------------------------------------------------------------------------
-- 1. Excluded wins over included and over every filter
---------------------------------------------------------------------------
Check(MI.Match(Rule({ include = { [1] = true }, exclude = { [1] = true }, cats = { "7" }, qualities = { [1] = true } }),
    Facts({ id = 1 }), nil) == "excluded", "an item in both lists is excluded, not included")
Check(MI.Match(Rule({ exclude = { [2] = true }, cats = { "7" }, qualities = { [1] = true }, equip = "other", bind = "nobind" }),
    Facts({ id = 2 }), nil) == "excluded", "an excluded item is never matched, whatever else is true")

---------------------------------------------------------------------------
-- 2. Included: a listed item matches even when the filters would not
---------------------------------------------------------------------------
Check(MI.Match(Rule({ include = { [5] = true }, cats = { "4" }, qualities = { [2] = true } }),
    Facts({ id = 5, classID = 7, quality = 1 }), nil) == "included", "Also include: a listed item matches though its category and quality don't")

---------------------------------------------------------------------------
-- 3. A rule with no filters at all matches only what it lists
---------------------------------------------------------------------------
local listed = Rule({ include = { [10] = true }, exclude = { [11] = true } })
Check(MI.Match(listed, Facts({ id = 10 }), nil) == "included", "no filters: a listed item is included")
Check(MI.Match(listed, Facts({ id = 11 }), nil) == "excluded", "no filters: a listed item is excluded")
Check(MI.Match(listed, Facts({ id = 12 }), nil) == nil, "no filters: an unlisted item matches nothing")

---------------------------------------------------------------------------
-- 4. Category filter: whole class key and class:subclass key, others rejected
---------------------------------------------------------------------------
Check(MI.Match(Rule({ cats = { "7" } }), Facts({ classID = 7, subclassID = 5 }), nil) == "matched", "the whole class key matches")
Check(MI.Match(Rule({ cats = { "7:5" } }), Facts({ classID = 7, subclassID = 5 }), nil) == "matched", "the class:subclass key matches")
Check(MI.Match(Rule({ cats = { "7:9" } }), Facts({ classID = 7, subclassID = 5 }), nil) == nil, "another subclass of the class doesn't match")
Check(MI.Match(Rule({ cats = { "0" } }), Facts({ classID = 7, subclassID = 5 }), nil) == nil, "another class doesn't match")

---------------------------------------------------------------------------
-- 5. Quality and equip filters
---------------------------------------------------------------------------
Check(MI.Match(Rule({ qualities = { [2] = true } }), Facts({ quality = 2 }), nil) == "matched", "the chosen quality matches")
Check(MI.Match(Rule({ qualities = { [3] = true } }), Facts({ quality = 2 }), nil) == nil, "an unchosen quality doesn't match")
Check(MI.Match(Rule({ equip = "equipment" }), Facts({ equipment = true }), nil) == "matched", "equip=equipment matches equipment")
Check(MI.Match(Rule({ equip = "equipment" }), Facts({ equipment = false }), nil) == nil, "equip=equipment rejects non-equipment")
Check(MI.Match(Rule({ equip = "other" }), Facts({ equipment = false }), nil) == "matched", "equip=other matches non-equipment")
Check(MI.Match(Rule({ equip = "other" }), Facts({ equipment = true }), nil) == nil, "equip=other rejects equipment")

---------------------------------------------------------------------------
-- 6. bind=boe: bindType 2 and a stack not already bound (bound or unknown: no)
---------------------------------------------------------------------------
local boe = Rule({ bind = "boe" })
Check(MI.Match(boe, Facts({ bindType = 2 }), { bound = false }) == "matched", "boe: an unbound binds-when-equipped item matches")
Check(MI.Match(boe, Facts({ bindType = 2 }), { bound = true }) == nil, "boe: a bound stack no longer binds on equip")
Check(MI.Match(boe, Facts({ bindType = 2 }), { bound = nil }) == nil, "boe: a stack whose binding is unknown doesn't count")
Check(MI.Match(boe, Facts({ bindType = 2 }), nil) == "matched", "boe: with no stack to check, the item still binds on equip")
Check(MI.Match(boe, Facts({ bindType = 1 }), { bound = false }) == nil, "boe: soulbound (bindType 1) is not binds-when-equipped")
Check(MI.Match(boe, Facts({ bindType = 0 }), { bound = false }) == nil, "boe: never-bound items don't match")

---------------------------------------------------------------------------
-- 7. bind=nobind: only bindType 0
---------------------------------------------------------------------------
local nobind = Rule({ bind = "nobind" })
Check(MI.Match(nobind, Facts({ bindType = 0 }), nil) == "matched", "nobind: bindType 0 matches")
Check(MI.Match(nobind, Facts({ bindType = 1 }), nil) == nil, "nobind: soulbound doesn't match")
Check(MI.Match(nobind, Facts({ bindType = 2 }), nil) == nil, "nobind: binds-when-equipped doesn't match")

---------------------------------------------------------------------------
-- 8. QualityName: the fallback words when the game's ITEM_QUALITY*_DESC globals are absent
---------------------------------------------------------------------------
for q = 0, 5 do
  Check(c["ITEM_QUALITY" .. q .. "_DESC"] == nil, "the game's ITEM_QUALITY" .. q .. "_DESC global is absent in the test")
end
Check(MI.QualityName(0) == "Poor", "quality 0 falls back to Poor")
Check(MI.QualityName(1) == "Common", "quality 1 falls back to Common")
Check(MI.QualityName(2) == "Uncommon", "quality 2 falls back to Uncommon")
Check(MI.QualityName(3) == "Rare", "quality 3 falls back to Rare")
Check(MI.QualityName(4) == "Epic", "quality 4 falls back to Epic")
Check(MI.QualityName(5) == "Legendary", "quality 5 falls back to Legendary")

if failures > 0 then
  print("TEST_MAGIC_INVENTORY_MATCH FAILED: " .. failures .. " failure(s)")
  os.exit(1)
end
print("TEST_MAGIC_INVENTORY_MATCH PASSED")
