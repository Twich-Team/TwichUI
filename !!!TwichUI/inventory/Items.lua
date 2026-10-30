-- TwichUI: Magic Inventory, reading items
-- What an item is (the game's class, subclass, quality, binding and equip slot), the categories a rule can choose
-- (the game's own names), whether a rule matches an item, and the carried bags as a list of stacks with what each
-- stack is (bound, locked, a quest item, conjured, in an equipment set). Reads only: nothing here moves, picks up or
-- uses anything. What an item is doesn't change in a session, so it is remembered by item ID (bounded); what a stack
-- is (bound, locked) is read each time.
--
-- Game calls (Forever 1.60.1 API documentation): C_Item.GetItemInfoInstant (class, subclass, equip slot; no cache
-- needed), C_Item.GetItemInfo (name, link, quality, max stack, class, subclass, bindType: Enum.ItemBind, 2 = on
-- equip), C_Item.GetItemSubClassInfo / GetItemClassInfo (the game's names), C_Item.RequestLoadItemDataByID,
-- C_Container.GetContainerItemInfo (isBound, isLocked, stackCount, hyperlink), GetContainerItemQuestInfo,
-- GetContainerItemEquipmentSetInfo, C_TooltipInfo.GetBagItem (only for the game's own ITEM_CONJURED words).

local R = TwichUI
local MI = R.MagicInventory
local Plain = MI.Plain

local MAX_CACHE = 512

---------------------------------------------------------------------------
-- One item
---------------------------------------------------------------------------
local cache, cacheSize = {}, 0
function MI.ClearItemCache() cache, cacheSize = {}, 0 end
function MI.ItemCacheSize() return cacheSize end

local function Num(v) v = Plain(v); return type(v) == "number" and v == v and v or nil end
local function Str(v) v = Plain(v); return type(v) == "string" and v or nil end

-- Mage-conjured items this client is known to have (modules/FoodDrink.lua and Mage selling's list): protection only.
local function KnownConjured(id)
    local FD, MS = R.FoodDrink, R.MageSell
    return (FD and FD.CONJURED and FD.CONJURED[id] == true) or (MS and MS.CONJURED_EXTRA and MS.CONJURED_EXTRA[id] == true) or false
end

-- { id, name, link, icon, quality, classID, subclassID, equipLoc, bindType, maxStack, equipment, conjured }, or nil
-- and true while the game is still loading it (it has been asked for), or nil and false for no such item.
function MI.ItemFacts(id)
    local hit = cache[id]
    if hit then return hit end
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil, false end
    local itemID, _, _, equipLoc, icon, classID, subclassID = C_Item.GetItemInfoInstant(id)
    if Num(itemID) == nil then return nil, false end
    local name, link, quality, _, _, _, _, maxStack, _, texture, _, classID2, subclassID2, bindType = C_Item.GetItemInfo(id)
    quality, bindType = Num(quality), Num(bindType)
    if Str(name) == nil or quality == nil or bindType == nil then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return nil, true
    end
    classID, subclassID = Num(classID2) or Num(classID), Num(subclassID2) or Num(subclassID)
    equipLoc = Str(equipLoc) or ""
    local facts = {
        id = id, name = Str(name), link = Str(link), icon = Num(texture) or Num(icon) or Str(texture), quality = quality,
        classID = classID, subclassID = subclassID, equipLoc = equipLoc, bindType = bindType,
        maxStack = Num(maxStack) or (C_Item.GetItemMaxStackSizeByID and Num(C_Item.GetItemMaxStackSizeByID(id))) or 1,
        conjured = KnownConjured(id),
    }
    -- weapons and armor that go in an equipment slot (a bag is a container, not equipment)
    facts.equipment = (classID == 2 or classID == 4) and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
    if cacheSize >= MAX_CACHE then MI.ClearItemCache() end
    cache[id] = facts
    cacheSize = cacheSize + 1
    return facts
end

---------------------------------------------------------------------------
-- Categories: "class" or "class:subclass", under the game's own names
---------------------------------------------------------------------------
function MI.CategoryOf(itemID)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local id, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    classID, subclassID = Num(classID), Num(subclassID)
    if not (Num(id) and classID and subclassID) then return nil end
    local key = classID .. ":" .. subclassID
    return key, MI.CategoryName(key)
end

function MI.CategoryName(key)
    if type(key) ~= "string" then return nil end
    local c, s = key:match("^(%d+):(%d+)$")
    if c then
        local name = C_Item and C_Item.GetItemSubClassInfo and Str((C_Item.GetItemSubClassInfo(tonumber(c), tonumber(s))))
        return name
    end
    local cls = tonumber(key)
    return cls and C_Item and C_Item.GetItemClassInfo and Str(C_Item.GetItemClassInfo(cls)) or nil
end

-- The categories offered when choosing items: Trade goods by subclass, Consumables by subclass, and a few whole
-- classes, each named as the game names it. Subclasses come from the game (C_AuctionHouse.GetAuctionItemSubClasses,
-- the list the Auction House browses by), so only what this client has is offered. Built when first asked for.
-- { { key, label, group }, ... }
local CLASS_GROUPS = {
    { class = 7, split = true },    -- Trade goods
    { class = 0, split = true },    -- Consumable
    { class = 5 },                  -- Reagent
    { class = 9, split = true },    -- Recipe
    { class = 3 },                  -- Gem
    { class = 6 },                  -- Projectile
    { class = 15 },                 -- Miscellaneous
}
local categories
function MI.Categories()
    if categories then return categories end
    local out = {}
    for _, g in ipairs(CLASS_GROUPS) do
        local groupName = MI.CategoryName(tostring(g.class))
        if groupName then
            local subs
            if g.split and C_AuctionHouse and C_AuctionHouse.GetAuctionItemSubClasses then
                local ok, list = pcall(C_AuctionHouse.GetAuctionItemSubClasses, g.class)
                if ok and type(list) == "table" then subs = list end
            end
            if subs and #subs > 0 then
                for _, s in ipairs(subs) do
                    s = Num(s)
                    local key = s and (g.class .. ":" .. s)
                    local label = key and MI.CategoryName(key)
                    if label then out[#out + 1] = { key = key, label = label, group = groupName } end
                end
            else
                out[#out + 1] = { key = tostring(g.class), label = groupName, group = groupName }
            end
        end
    end
    if #out > 0 then categories = out end   -- an empty answer (names not there yet) is asked again next time
    return out
end

MI.QUALITY_ORDER = { 0, 1, 2, 3, 4 }
local QUALITY_FALLBACK = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
function MI.QualityName(q)
    return Str(_G["ITEM_QUALITY" .. q .. "_DESC"]) or QUALITY_FALLBACK[q] or ("Quality " .. q)
end

---------------------------------------------------------------------------
-- Matching. facts: MI.ItemFacts; stack (optional): { bound } for the binding test of a stack. Pure.
-- Returns "included" (the rule's Also include list), "matched" (its filters), "excluded" (its Never include list),
-- or nil. An excluded item is never matched, whatever else is true; the hard protections and the Never transfer
-- list are applied by the plan, before any rule (Plan.lua).
---------------------------------------------------------------------------
local function CatMatch(rule, facts)
    if #rule.cats == 0 then return true end
    for _, key in ipairs(rule.cats) do
        if key == tostring(facts.classID) or key == (facts.classID .. ":" .. facts.subclassID) then return true end
    end
    return false
end

function MI.Match(rule, facts, stack)
    local id = facts.id
    if rule.exclude[id] then return "excluded" end
    if rule.include[id] then return "included" end
    -- a rule with no filters at all matches only what it lists
    if not (#rule.cats > 0 or next(rule.qualities) ~= nil or rule.equip ~= "any" or rule.bind ~= "any") then return nil end
    if not CatMatch(rule, facts) then return nil end
    if next(rule.qualities) ~= nil and not rule.qualities[facts.quality] then return nil end
    if rule.equip == "equipment" and not facts.equipment then return nil end
    if rule.equip == "other" and facts.equipment then return nil end
    if rule.bind == "boe" then
        if facts.bindType ~= 2 then return nil end
        if stack and stack.bound ~= false then return nil end   -- bound already, or not known: not "binds when equipped" any more
    elseif rule.bind == "nobind" then
        if facts.bindType ~= 0 then return nil end
    end
    return "matched"
end

---------------------------------------------------------------------------
-- The carried bags. { stacks = { stack, ... } in bag order, pending = n } where a stack is
-- { bag, slot, id, count, link, bound, locked, quest, conjured, inSet, facts } (facts nil while loading).
-- bound/locked/quest/inSet are true, false or nil (nil: the game didn't say).
---------------------------------------------------------------------------
local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end
MI.LastBag = LastBag

local function TooltipConjured(bag, slot)
    local marker = _G.ITEM_CONJURED
    if type(marker) ~= "string" or marker == "" or not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return nil end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    local lines = type(data) == "table" and data.lines
    if type(lines) ~= "table" or #lines == 0 then return nil end
    for _, line in ipairs(lines) do
        local text = type(line) == "table" and line.leftText
        if text ~= nil and issecretvalue and issecretvalue(text) then return nil end
        if type(text) == "string" and text:find(marker, 1, true) then return true end
    end
    return false
end

-- One slot, read now. nil for an empty slot.
function MI.ReadSlot(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local id = info and Num(info.itemID)
    if not id then return nil end
    local s = { bag = bag, slot = slot, id = id, count = Num(info.stackCount) or 0, link = Str(info.hyperlink),
        icon = Num(info.iconFileID), bound = Plain(info.isBound), locked = Plain(info.isLocked) }
    if type(s.bound) ~= "boolean" then s.bound = nil end
    if type(s.locked) ~= "boolean" then s.locked = nil end
    local facts, pending = MI.ItemFacts(id)
    s.facts, s.pending = facts, pending and true or nil
    if C_Container.GetContainerItemQuestInfo then
        local q = C_Container.GetContainerItemQuestInfo(bag, slot)
        if type(q) == "table" then s.quest = (q.isQuestItem == true or Plain(q.questID) ~= nil) end
    end
    if facts and (facts.classID == 12 or facts.bindType == 4) then s.quest = true end
    if facts and facts.equipment and C_Container.GetContainerItemEquipmentSetInfo then
        local inSet = C_Container.GetContainerItemEquipmentSetInfo(bag, slot)
        if type(Plain(inSet)) == "boolean" then s.inSet = inSet end
    elseif facts and not facts.equipment then
        s.inSet = false
    end
    -- conjured: the known IDs, else the tooltip's own words (only read for consumables and miscellaneous items, which
    -- is where conjured things are filed); nil while it can't be told
    s.conjured = (facts and facts.conjured) or nil
    if not s.conjured then
        if facts and facts.classID ~= 0 and facts.classID ~= 15 then s.conjured = false
        else s.conjured = TooltipConjured(bag, slot) end
    end
    return s
end

function MI.ReadBags()
    local out = { stacks = {}, pending = 0 }
    for bag = 0, LastBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local s = MI.ReadSlot(bag, slot)
            if s then
                out.stacks[#out.stacks + 1] = s
                if s.pending then out.pending = out.pending + 1 end
            end
        end
    end
    return out
end
