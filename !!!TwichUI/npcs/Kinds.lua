-- TwichUI: Vendors and trainers, the kinds
-- What an NPC you visited is, in the words the map and the settings use, and how that is decided. An NPC is tagged only
-- with what it was seen to offer when you dealt with it, never from its name, its title or anyone's say-so:
--   a merchant     by what it had for sale (each item's class and subclass from C_Item.GetItemInfoInstant, which needs
--                  no item cache) and whether it repairs (CanMerchantRepair)
--   a trainer      by the client's own trainer type (C_Trainer.GetTrainerType: General, Tradeskills or Pet); a General
--                  trainer is recorded as a class trainer for the class of the character who saw it
--   a service      by the interaction the client opened (Enum.PlayerInteractionType: Banker, Binder, Auctioneer, ...)
-- One NPC can be several kinds (an innkeeper also sells food and drink). The values are from the Forever UI source
-- (Blizzard_APIDocumentationGenerated: ItemConstantsDocumentation, PlayerInteractionManagerConstantsDocumentation,
-- TrainerConstantsDocumentation); docs/npc-map.md lists which of them still have to be seen in the game.
-- Nothing here calls the game, draws or saves: Collect.lua reads the game and hands the facts to Classify.

local R = TwichUI
local NK = {}
R.NpcKinds = NK

-- id: saved and in the settings; code: on the wire (two letters, never reused); section: where the settings list it;
-- rank: which icon an NPC of several kinds wears (lowest first); on: shown by default.
NK.LIST = {
    { id = "classTrainer", code = "ct", section = "trainers", rank = 1, on = true, label = "Class trainers", noun = "Class trainer",
        tip = "Trainers of your class's spells and abilities. A trainer is recorded for the class of the character who visited it, so each class's trainers are found by players of that class." },
    { id = "profTrainer", code = "pt", section = "trainers", rank = 2, on = true, label = "Profession trainers", noun = "Profession trainer",
        tip = "Trainers of a profession (the game calls them trade skill trainers), with the profession's name where the game gave it." },
    { id = "petTrainer", code = "pe", section = "trainers", rank = 3, on = true, label = "Pet trainers", noun = "Pet trainer",
        tip = "Hunter pet trainers." },
    { id = "innkeeper", code = "in", section = "services", rank = 4, on = true, label = "Innkeepers", noun = "Innkeeper",
        tip = "Where you can make an inn your home." },
    { id = "banker", code = "bk", section = "services", rank = 5, on = true, label = "Bankers", noun = "Banker" },
    { id = "auctioneer", code = "au", section = "services", rank = 6, on = true, label = "Auctioneers", noun = "Auctioneer" },
    { id = "flight", code = "fl", section = "services", rank = 7, on = false, label = "Flight masters", noun = "Flight master",
        tip = "The game's own map already shows flight points; this marks the flight master who serves one." },
    { id = "stable", code = "st", section = "services", rank = 8, on = false, label = "Stable masters", noun = "Stable master" },
    { id = "guild", code = "gm", section = "services", rank = 9, on = false, label = "Guild masters", noun = "Guild master",
        tip = "Where guild charters are bought and turned in (the game's guild registrar)." },
    { id = "spirit", code = "sh", section = "services", rank = 10, on = false, label = "Spirit healers", noun = "Spirit healer" },
    { id = "reagents", code = "rg", section = "vendors", rank = 11, on = true, label = "Reagent vendors", noun = "Sells reagents",
        tip = "Merchants that had reagents for sale: what spells use up (the item class the game calls Reagent)." },
    { id = "ammo", code = "am", section = "vendors", rank = 12, on = true, label = "Ammunition", noun = "Sells ammunition",
        tip = "Merchants that had arrows or bullets for sale." },
    { id = "repair", code = "rp", section = "vendors", rank = 13, on = true, label = "Repairs", noun = "Repairs",
        tip = "Merchants that offered to repair your equipment." },
    { id = "trade", code = "tg", section = "vendors", rank = 14, on = true, label = "Trade supplies", noun = "Sells trade supplies",
        tip = "Merchants that had trade goods for sale: thread, dyes, vials, flux and the like." },
    { id = "food", code = "fd", section = "vendors", rank = 15, on = true, label = "Food and drink", noun = "Sells food and drink" },
    { id = "recipes", code = "rc", section = "vendors", rank = 16, on = false, label = "Recipes", noun = "Sells recipes",
        tip = "Merchants that had recipes, patterns, plans or formulas for sale." },
    { id = "bags", code = "bg", section = "vendors", rank = 17, on = false, label = "Bags and quivers", noun = "Sells bags" },
    { id = "vendor", code = "vd", section = "vendors", rank = 18, on = false, label = "Other merchants", noun = "Merchant",
        tip = "Merchants that sold none of the kinds above when you visited." },
}
NK.SECTIONS = {
    { id = "vendors", label = "Vendors" },
    { id = "trainers", label = "Trainers" },
    { id = "services", label = "Services" },
}
NK.BY_ID, NK.BY_CODE = {}, {}
for _, k in ipairs(NK.LIST) do
    NK.BY_ID[k.id] = k
    NK.BY_CODE[k.code] = k
    k.icon = R.PATH .. [[media\textures\npc-]] .. k.id
end

-- The class tokens a class trainer can carry (UnitClassBase); anything else is not stored or accepted.
NK.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
NK.IS_CLASS = {}
for _, c in ipairs(NK.CLASSES) do NK.IS_CLASS[c] = true end

---------------------------------------------------------------------------
-- The client's numbers (with the documented values when the client has no Enum table for them)
---------------------------------------------------------------------------
local function Value(group, name, fallback)
    local E = Enum and Enum[group]
    local v = E and E[name]
    return type(v) == "number" and v or fallback
end
NK.INTERACTION = {
    merchant = Value("PlayerInteractionType", "Merchant", 5), flight = Value("PlayerInteractionType", "TaxiNode", 6),
    trainer = Value("PlayerInteractionType", "Trainer", 7), banker = Value("PlayerInteractionType", "Banker", 8),
    guild = Value("PlayerInteractionType", "Registrar", 11), spirit = Value("PlayerInteractionType", "SpiritHealer", 18),
    innkeeper = Value("PlayerInteractionType", "Binder", 20), auctioneer = Value("PlayerInteractionType", "Auctioneer", 21),
    stable = Value("PlayerInteractionType", "StableMaster", 22),
}
-- An interaction that is a service by itself (merchants and trainers are read from their own windows).
NK.SERVICE = {}
for _, id in ipairs({ "flight", "banker", "guild", "spirit", "innkeeper", "auctioneer", "stable" }) do
    NK.SERVICE[NK.INTERACTION[id]] = id
end

local CLASS = {
    consumable = Value("ItemClass", "Consumable", 0), container = Value("ItemClass", "Container", 1),
    reagent = Value("ItemClass", "Reagent", 5), projectile = Value("ItemClass", "Projectile", 6),
    tradegoods = Value("ItemClass", "Tradegoods", 7), recipe = Value("ItemClass", "Recipe", 9),
    quiver = Value("ItemClass", "Quiver", 11),
}
local FOOD_AND_DRINK = Value("ItemConsumableSubclass", "Fooddrink", 5)
NK.TRAINER = { general = Value("TrainerType", "General", 0), tradeskills = Value("TrainerType", "Tradeskills", 2),
    pet = Value("TrainerType", "Pet", 3) }

-- The kind an item for sale makes its merchant, or nil.
function NK.ItemKind(classID, subClassID)
    if classID == CLASS.reagent then return "reagents" end
    if classID == CLASS.projectile then return "ammo" end
    if classID == CLASS.consumable and subClassID == FOOD_AND_DRINK then return "food" end
    if classID == CLASS.tradegoods then return "trade" end
    if classID == CLASS.recipe then return "recipes" end
    if classID == CLASS.container or classID == CLASS.quiver then return "bags" end
    return nil
end

---------------------------------------------------------------------------
-- Classify: facts seen at one NPC -> { tags = { [kind] = true }, cls = class token or nil, prof = text or nil }, or nil
-- facts: { service = interaction type, items = { { classID, subClassID }, ... }, repair = bool, merchant = bool,
--          trainerType = number, playerClass = "MAGE", profession = text }
---------------------------------------------------------------------------
function NK.Classify(facts)
    local tags, any = {}, false
    local function Tag(id) tags[id], any = true, true end
    local service = facts.service and NK.SERVICE[facts.service]
    if service then Tag(service) end
    if facts.merchant then
        for _, item in ipairs(facts.items or {}) do
            local kind = NK.ItemKind(item[1], item[2])
            if kind then Tag(kind) end
        end
        if facts.repair then Tag("repair") end
        if not any then Tag("vendor") end
    end
    local out = { tags = tags }
    local t = facts.trainerType
    if t ~= nil then
        if t == NK.TRAINER.tradeskills then
            Tag("profTrainer")
            out.prof = facts.profession
        elseif t == NK.TRAINER.pet then
            Tag("petTrainer")
        elseif t == NK.TRAINER.general and NK.IS_CLASS[facts.playerClass] then
            Tag("classTrainer")
            out.cls = facts.playerClass
        end
    end
    if not any then return nil end
    return out
end

-- The kind an NPC's marker shows: the lowest rank among its kinds that pass `shown(kind)`, or nil.
function NK.Primary(tags, shown)
    local best
    for id in pairs(tags) do
        local k = NK.BY_ID[id]
        if k and (not shown or shown(id)) and (not best or k.rank < best.rank) then best = k end
    end
    return best
end

-- Its kinds in rank order, as words ("Innkeeper, Sells food and drink").
function NK.Describe(tags)
    local list = {}
    for id in pairs(tags) do
        if NK.BY_ID[id] then list[#list + 1] = NK.BY_ID[id] end
    end
    table.sort(list, function(a, b) return a.rank < b.rank end)
    local words = {}
    for i, k in ipairs(list) do words[i] = k.noun end
    return table.concat(words, ", ")
end
