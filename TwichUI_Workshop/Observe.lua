-- TwichUI Workshop: what the profession window offers
-- Reads the recipes of the player's OWN open profession from the game's profession interface (C_TradeSkillUI, the one Forever's
-- profession window is built on). It only reads: it never changes Blizzard's filters, windows or recipes.
--
-- Game calls (Forever UI source, Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua and TradeSkillUITypesDocumentation.lua):
--   GetBaseProfessionInfo (professionID, professionName), GetRecipeInfo (learned, name, icon, relativeDifficulty, isRecraft, ...),
--   GetRecipeSchematic (quantityMin/Max, outputItemID, reagentSlotSchematics: reagentType, reagents[].itemID, quantityRequired, required),
--   IsTradeSkillLinked / IsTradeSkillGuild / IsNPCCrafting / IsDataSourceChanging (Blizzard's own profession frame reads them), OpenRecipe.
--   GetFilteredRecipeIDs and GetRecipeCooldown are used by Blizzard's own code. GetAllRecipeIDs is in neither the documentation nor
--   Blizzard's code; the reference addons call it when it exists, so it is tried and not relied on.
--
-- A list is "complete" only when GetAllRecipeIDs gave it. Otherwise it is the profession window's FILTERED list (search text,
-- "can make", unlearned...), which may leave recipes out: those are not "forgotten" or "unlearned", just not shown by the window.
--
-- Only a profession the game confirms is the player's own is read: a linked profession, a guild view or crafting at an NPC is
-- refused, and so is any window the game can't say that about (a missing answer is never treated as "own").

local R = TwichUI
local W = R.Workshop
local Int, Text, Plain = W.Int, W.Text, W.Plain
local O = {}
W.Observe = O

local MAX_RECIPES = 1500
local MAX_CACHE = 800

---------------------------------------------------------------------------
-- A recipe's output and materials (read when first wanted, remembered while the window is open)
---------------------------------------------------------------------------
local cache, cacheSize = {}, 0
function O.ClearCache() cache, cacheSize = {}, 0 end
function O.CacheSize() return cacheSize end

-- Enum.CraftingReagentType: Modifying 0, Basic 1, Finishing 2, Automatic 3
local function Parse(s)
    local d = {}
    local lo, hi = Int(s.quantityMin, 1, W.MAX_QTY), Int(s.quantityMax, 1, W.MAX_QTY)
    if lo and not hi then hi = lo elseif hi and not lo then lo = hi end
    if lo and hi and hi >= lo then d.outMin, d.outMax = lo, hi end
    d.outItem = Int(s.outputItemID, 1, W.MAX_ID)
    local slots = Plain(s.reagentSlotSchematics)
    if type(slots) ~= "table" then d.why = "unsupported"; return d end
    local basic = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
    local modifying = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Modifying) or 0
    local finishing = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Finishing) or 2
    local mats = {}
    for i = 1, #slots do
        local slot = Plain(slots[i])
        if type(slot) ~= "table" then d.why = "unsupported"; return d end
        local kind = Plain(slot.reagentType)
        if kind == basic then
            local reagents = Plain(slot.reagents)
            local only = type(reagents) == "table" and #reagents == 1 and Plain(reagents[1]) or nil
            local item = type(only) == "table" and Int(only.itemID, 1, W.MAX_ID) or nil
            local qty = Int(slot.quantityRequired, 1, W.MAX_QTY)
            local vq = Plain(slot.variableQuantities)
            if not item or not qty or (type(vq) == "table" and next(vq) ~= nil) then d.why = "unsupported"; return d end
            mats[#mats + 1] = { item = item, qty = qty }
        elseif (kind == modifying or kind == finishing) and Plain(slot.required) ~= true then
            -- an optional slot (an extra the player may add): not part of what is needed
        else
            d.why = "unsupported"   -- a required extra, an automatic reagent or a kind this version doesn't know
            return d
        end
    end
    d.mats = W.Queue.CleanMats(mats)
    if not d.mats then d.why = "unsupported" end
    return d
end

local function Details(id)
    local hit = cache[id]
    if hit then return hit end
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic) then return { why = "unread" } end
    local ok, s = pcall(T.GetRecipeSchematic, id, false)
    s = ok and Plain(s) or nil
    if type(s) ~= "table" then return { why = "unread" } end
    local d = Parse(s)
    if cacheSize >= MAX_CACHE then O.ClearCache() end
    cache[id] = d
    cacheSize = cacheSize + 1
    return d
end

-- Fills in a recipe's output and materials (once). rec.mats stays nil, with rec.why, when they can't be read or aren't supported.
function O.Fill(rec)
    if rec.filled then return rec end
    local d = Details(rec.id)
    if d.why == "unread" then return rec end   -- try again later; the game may not have the data yet
    rec.filled = true
    rec.outMin, rec.outMax, rec.outItem, rec.mats, rec.why = d.outMin, d.outMax, d.outItem, d.mats, d.why
    return rec
end

---------------------------------------------------------------------------
-- The open profession
---------------------------------------------------------------------------
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    return Plain(a)
end

-- Returns { prof, profName, complete, recipes = { { id, name, icon, diff, prof, profName }, ... } }, or nil and why:
--   "api" (the game offers no profession interface), "combat", "busy" (the window is still loading its list), "not-own"
--   (linked, guild, NPC or unconfirmed), "none" (no profession is open), "empty" (it has no recipe list yet)
function O.Read()
    local T = C_TradeSkillUI
    if not (T and T.GetBaseProfessionInfo and T.GetRecipeInfo) then return nil, "api" end
    if InCombatLockdown and InCombatLockdown() then return nil, "combat" end
    if Call(T.IsDataSourceChanging) == true then return nil, "busy" end
    if Call(T.IsNPCCrafting) ~= false or Call(T.IsTradeSkillGuild) ~= false or Call(T.IsTradeSkillLinked) ~= false then
        return nil, "not-own"
    end
    local base = Call(T.GetBaseProfessionInfo)
    local prof = type(base) == "table" and Int(base.professionID, 1, W.MAX_ID) or nil
    local profName = type(base) == "table" and Text(base.professionName, 40) or nil
    if not prof or not profName then return nil, "none" end

    local ids, complete
    local all = Call(T.GetAllRecipeIDs)
    if type(all) == "table" and #all > 0 then
        ids, complete = all, true
    else
        local filtered = Call(T.GetFilteredRecipeIDs)
        if type(filtered) == "table" and #filtered > 0 then ids, complete = filtered, false end
    end
    if not ids then return nil, "empty" end

    local recipes, seen = {}, {}
    for i = 1, math.min(#ids, MAX_RECIPES) do
        local id = Int(ids[i], 1, W.MAX_ID)
        if id and not seen[id] then
            seen[id] = true
            local info = Call(T.GetRecipeInfo, id)
            if type(info) == "table" and Plain(info.learned) == true
                and Plain(info.isRecraft) ~= true and Plain(info.isDummyRecipe) ~= true
                and Plain(info.isGatheringRecipe) ~= true and Plain(info.isSalvageRecipe) ~= true then
                local name = Text(info.name, 80)
                if name then
                    recipes[#recipes + 1] = {
                        id = id, name = name, icon = Int(info.icon, 0, W.MAX_ID), diff = Int(info.relativeDifficulty, 0, 3),
                        prof = prof, profName = profName,
                    }
                end
            end
        end
    end
    table.sort(recipes, function(a, b)
        local x, y = a.name:lower(), b.name:lower()
        if x ~= y then return x < y end
        return a.id < b.id
    end)
    return { prof = prof, profName = profName, complete = complete, recipes = recipes }
end

-- Opens the recipe in the game's own profession window. Returns true, or false when the game wouldn't.
function O.OpenRecipe(id)
    local T = C_TradeSkillUI
    id = Int(id, 1, W.MAX_ID)
    if not (id and T and T.OpenRecipe) then return false end
    return (pcall(T.OpenRecipe, id))
end

---------------------------------------------------------------------------
-- Items (names and icons come from the game; nothing of them is saved)
---------------------------------------------------------------------------
-- How many the bags hold (the bank, the reagent bank and other characters are not counted), or nil when the game can't say
function O.BagCount(item)
    local f = C_Item and C_Item.GetItemCount
    if not f then return nil end
    local ok, n = pcall(f, item)
    n = ok and Plain(n) or nil
    if type(n) ~= "number" or n ~= n or n < 0 then return nil end
    return n
end

-- name, icon (either may be nil while the game loads the item; it is asked once per call and GET_ITEM_INFO_RECEIVED follows)
function O.ItemFacts(item)
    local name, icon
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, tex = pcall(C_Item.GetItemInfoInstant, item)
        if ok then icon = Int(tex, 0, W.MAX_ID) end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, n = pcall(C_Item.GetItemInfo, item)
        if ok then name = Text(n, 80) end
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, item) end
    return name, icon
end
