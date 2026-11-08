-- TwichUI: Action bar glows, what is known about spells and items
-- The built-in list: which spells and items each kind of glow watches, per class. Pure data and lookups: nothing here
-- reads the game or touches a frame, so the tests can use it as it is. Config.lua stores the player's choices,
-- Logic.lua decides (pure), State.lua reads the game, Buttons.lua finds the buttons, Draw.lua draws, Controller.lua runs it.
--
-- The IDs are the game's own (WoW: Forever shares Classic Era's spell and item data). A spell is named by one ID, its
-- first rank: the client's name for it is what buttons and auras are matched by, so every rank counts and no rank list is
-- kept. Trained spells were checked against WhatsTraining's class lists (../reference_addons, read for data only); talents
-- and racials are marked `talent` or `racial` and were not in that list. Poison and reagent item IDs were checked
-- against two other reference addons' item tables. The English `label` is only a fallback while the client has no
-- name cached; nothing is decided by it.
--
--   C.TYPES, C.TYPE_ORDER       the kinds of glow, in the order the settings list them
--   C.ENTRIES                   every built-in entry; C.Find(type, key) one of them
--   C.For(type, class)          the entries of one kind for a class (racials and everyone's included), in order
--   C.Categories                exclusive groups (one armor, one aspect, one seal ...): [category] = { entries }

local R = TwichUI
local C = {}
R.BarGlowCatalog = C

-- The kinds, most urgent first when two want the same button (Draw shows the first).
C.TYPE_ORDER = { "proc", "readyCooldown", "missingSeal", "weaponBuff", "missingBuff", "missingTracking", "lowReagent", "lowStock", "oldRank" }
C.TYPES = {}
for i, t in ipairs(C.TYPE_ORDER) do C.TYPES[t] = i end
-- The order the settings window lists them in.
C.LIST_ORDER = { "missingBuff", "weaponBuff", "missingSeal", "missingTracking", "lowReagent", "lowStock", "readyCooldown", "proc", "oldRank" }

C.TYPE_INFO = {
    missingBuff = { label = "Missing buff", text = "Missing buff",
        tip = "A buff of yours that is not on you (or, out of combat, on group members in range). Its button glows until you cast it." },
    weaponBuff = { label = "Weapon buff", text = "Weapon buff",
        tip = "Your weapon has no temporary enchant: a shaman's imbue, a rogue's poison, or a stone or oil you added. The button that puts it on glows." },
    missingSeal = { label = "Missing seal", text = "Missing seal",
        tip = "A paladin with no seal up. The seal you used last glows (in combat, unless you choose otherwise)." },
    missingTracking = { label = "Missing tracking", text = "Missing tracking",
        tip = "No tracking is on (Find Herbs, Find Minerals, a hunter's tracks ...). The one you used last glows." },
    lowReagent = { label = "Low reagent", text = "Running low",
        tip = "You carry fewer of a spell's reagent than the limit. The spells that use it glow." },
    lowStock = { label = "Low stock", text = "Running low",
        tip = "You carry fewer of an item you added than its limit (food, potions, ammunition ...). Its button glows." },
    readyCooldown = { label = "Ready cooldown", text = "Cooldown ready",
        tip = "An important cooldown has come back. Its button glows for a moment (in combat, unless you choose otherwise)." },
    proc = { label = "Proc", text = "Proc",
        tip = "A spell the game only lets you use now and then (Overpower, Revenge, Execute, Riposte ...) can be used. It glows while it can." },
    oldRank = { label = "Old rank", text = "Old spell rank",
        tip = "A button holds a lower rank of a spell than the highest you know. Turn a spell off here if you keep a lower rank on purpose." },
}

C.ENTRIES = {}
local byKey = {}

-- def: { label, spell or item, class, talent, racial, default (false: off until turned on), when (its own default),
--   category (an exclusive group), group = { spell, reagents } (the group version, out of combat), mana (only for
--   classes with mana), slot ("mainHand" | "both"), items (item IDs: a poison's ranks), names (other aura names that
--   count, by spell ID), reagent (lowReagent: the item), spells (lowReagent: the spells that use it), below (its own limit) }
local function E(kind, key, def)
    def.type, def.key = kind, key
    assert(C.TYPES[kind], "a known kind")
    assert(not byKey[kind .. ":" .. key], "one entry per key")
    byKey[kind .. ":" .. key] = def
    C.ENTRIES[#C.ENTRIES + 1] = def
    return def
end

---------------------------------------------------------------------------
-- Missing buffs (on you; group versions out of combat)
---------------------------------------------------------------------------
-- Priest
E("missingBuff", "fortitude", { label = "Power Word: Fortitude", class = "PRIEST", spell = 1243,
    group = { spell = 21562, reagents = { 17028, 17029 } }, names = { 21562 } })
E("missingBuff", "innerFire", { label = "Inner Fire", class = "PRIEST", spell = 588 })
E("missingBuff", "divineSpirit", { label = "Divine Spirit", class = "PRIEST", spell = 14752, talent = true, mana = true,
    group = { spell = 27681, reagents = { 17029 } }, names = { 27681 } })
E("missingBuff", "shadowProtection", { label = "Shadow Protection", class = "PRIEST", spell = 976, default = false,
    group = { spell = 27683, reagents = { 17029 } }, names = { 27683 } })
-- Mage
E("missingBuff", "intellect", { label = "Arcane Intellect", class = "MAGE", spell = 1459, mana = true,
    group = { spell = 23028, reagents = { 17020 } }, names = { 23028 } })
E("missingBuff", "frostArmor", { label = "Frost Armor", class = "MAGE", spell = 168, category = "mageArmor" })
E("missingBuff", "iceArmor", { label = "Ice Armor", class = "MAGE", spell = 7302, category = "mageArmor" })
E("missingBuff", "mageArmor", { label = "Mage Armor", class = "MAGE", spell = 6117, category = "mageArmor" })
-- Warlock
E("missingBuff", "demonSkin", { label = "Demon Skin", class = "WARLOCK", spell = 687, category = "warlockArmor" })
E("missingBuff", "demonArmor", { label = "Demon Armor", class = "WARLOCK", spell = 706, category = "warlockArmor" })
-- Druid
E("missingBuff", "markOfTheWild", { label = "Mark of the Wild", class = "DRUID", spell = 1126,
    group = { spell = 21849, reagents = { 17021, 17026 } }, names = { 21849 } })
E("missingBuff", "thorns", { label = "Thorns", class = "DRUID", spell = 467, default = false })
E("missingBuff", "omenOfClarity", { label = "Omen of Clarity", class = "DRUID", spell = 16864, talent = true })
-- Paladin: one blessing on yourself (the one you used last), one aura
E("missingBuff", "blessingOfMight", { label = "Blessing of Might", class = "PALADIN", spell = 19740, category = "blessing",
    group = { spell = 25782, reagents = { 21177 } }, names = { 25782 } })
E("missingBuff", "blessingOfWisdom", { label = "Blessing of Wisdom", class = "PALADIN", spell = 19742, category = "blessing",
    group = { spell = 25894, reagents = { 21177 } }, names = { 25894 } })
E("missingBuff", "blessingOfKings", { label = "Blessing of Kings", class = "PALADIN", spell = 20217, talent = true, category = "blessing",
    group = { spell = 25898, reagents = { 21177 } }, names = { 25898 } })
E("missingBuff", "blessingOfSalvation", { label = "Blessing of Salvation", class = "PALADIN", spell = 1038, category = "blessing",
    group = { spell = 25895, reagents = { 21177 } }, names = { 25895 } })
E("missingBuff", "blessingOfLight", { label = "Blessing of Light", class = "PALADIN", spell = 19977, category = "blessing",
    group = { spell = 25890, reagents = { 21177 } }, names = { 25890 } })
E("missingBuff", "blessingOfSanctuary", { label = "Blessing of Sanctuary", class = "PALADIN", spell = 20911, talent = true, category = "blessing",
    group = { spell = 25899, reagents = { 21177 } }, names = { 25899 } })
E("missingBuff", "devotionAura", { label = "Devotion Aura", class = "PALADIN", spell = 465, category = "paladinAura" })
E("missingBuff", "retributionAura", { label = "Retribution Aura", class = "PALADIN", spell = 7294, category = "paladinAura" })
E("missingBuff", "concentrationAura", { label = "Concentration Aura", class = "PALADIN", spell = 19746, category = "paladinAura" })
E("missingBuff", "shadowResistanceAura", { label = "Shadow Resistance Aura", class = "PALADIN", spell = 19876, category = "paladinAura" })
E("missingBuff", "frostResistanceAura", { label = "Frost Resistance Aura", class = "PALADIN", spell = 19888, category = "paladinAura" })
E("missingBuff", "fireResistanceAura", { label = "Fire Resistance Aura", class = "PALADIN", spell = 19891, category = "paladinAura" })
E("missingBuff", "sanctityAura", { label = "Sanctity Aura", class = "PALADIN", spell = 20218, talent = true, category = "paladinAura" })
E("missingBuff", "righteousFury", { label = "Righteous Fury", class = "PALADIN", spell = 25780, default = false })
-- Warrior
E("missingBuff", "battleShout", { label = "Battle Shout", class = "WARRIOR", spell = 6673, when = "inCombat" })
E("missingBuff", "shieldBlock", { label = "Shield Block", class = "WARRIOR", spell = 2565, when = "inCombat", default = false })
-- Hunter
E("missingBuff", "aspectOfTheHawk", { label = "Aspect of the Hawk", class = "HUNTER", spell = 13165, category = "aspect" })
E("missingBuff", "aspectOfTheMonkey", { label = "Aspect of the Monkey", class = "HUNTER", spell = 13163, category = "aspect" })
E("missingBuff", "aspectOfTheCheetah", { label = "Aspect of the Cheetah", class = "HUNTER", spell = 5118, category = "aspect" })
E("missingBuff", "aspectOfThePack", { label = "Aspect of the Pack", class = "HUNTER", spell = 13159, category = "aspect" })
E("missingBuff", "aspectOfTheWild", { label = "Aspect of the Wild", class = "HUNTER", spell = 20043, category = "aspect" })
E("missingBuff", "aspectOfTheBeast", { label = "Aspect of the Beast", class = "HUNTER", spell = 13161, category = "aspect" })
E("missingBuff", "trueshotAura", { label = "Trueshot Aura", class = "HUNTER", spell = 19506, talent = true })
-- Shaman
E("missingBuff", "lightningShield", { label = "Lightning Shield", class = "SHAMAN", spell = 324 })

---------------------------------------------------------------------------
-- Weapon buffs
---------------------------------------------------------------------------
E("weaponBuff", "rockbiter", { label = "Rockbiter Weapon", class = "SHAMAN", spell = 8017, slot = "mainHand" })
E("weaponBuff", "flametongue", { label = "Flametongue Weapon", class = "SHAMAN", spell = 8024, slot = "mainHand" })
E("weaponBuff", "frostbrand", { label = "Frostbrand Weapon", class = "SHAMAN", spell = 8033, slot = "mainHand" })
E("weaponBuff", "windfury", { label = "Windfury Weapon", class = "SHAMAN", spell = 8232, slot = "mainHand" })
-- Poisons are items (each rank its own), put on with a click of the item
E("weaponBuff", "instantPoison", { label = "Instant Poison", class = "ROGUE", slot = "both", items = { 6947, 6949, 6950, 8926, 8927, 8928 } })
E("weaponBuff", "deadlyPoison", { label = "Deadly Poison", class = "ROGUE", slot = "both", items = { 2892, 2893, 8984, 8985, 20844 } })
E("weaponBuff", "cripplingPoison", { label = "Crippling Poison", class = "ROGUE", slot = "both", items = { 3775, 3776 } })
E("weaponBuff", "mindNumbingPoison", { label = "Mind-numbing Poison", class = "ROGUE", slot = "both", items = { 5237, 6951, 9186 } })
E("weaponBuff", "woundPoison", { label = "Wound Poison", class = "ROGUE", slot = "both", items = { 10918, 10920, 10921, 10922 } })

---------------------------------------------------------------------------
-- Seals (paladin), in combat by default
---------------------------------------------------------------------------
for _, s in ipairs({
    { "righteousness", "Seal of Righteousness", 21084 }, { "command", "Seal of Command", 20375, true },
    { "crusader", "Seal of the Crusader", 21082 }, { "justice", "Seal of Justice", 20164 },
    { "light", "Seal of Light", 20165 }, { "wisdom", "Seal of Wisdom", 20166 },
}) do
    E("missingSeal", s[1], { label = s[2], class = "PALADIN", spell = s[3], talent = s[4], category = "seal" })
end

---------------------------------------------------------------------------
-- Tracking (one at a time: the one used last)
---------------------------------------------------------------------------
for _, t in ipairs({
    { "findHerbs", "Find Herbs", 2383 }, { "findMinerals", "Find Minerals", 2580 },
    { "findTreasure", "Find Treasure", 2481, nil, true },
    { "trackBeasts", "Track Beasts", 1494, "HUNTER" }, { "trackHumanoids", "Track Humanoids", 19883, "HUNTER" },
    { "trackUndead", "Track Undead", 19884, "HUNTER" }, { "trackHidden", "Track Hidden", 19885, "HUNTER" },
    { "trackElementals", "Track Elementals", 19880, "HUNTER" }, { "trackDemons", "Track Demons", 19878, "HUNTER" },
    { "trackGiants", "Track Giants", 19882, "HUNTER" }, { "trackDragonkin", "Track Dragonkin", 19879, "HUNTER" },
    { "trackHumanoidsCat", "Track Humanoids (cat form)", 5225, "DRUID" },
    { "senseUndead", "Sense Undead", 5502, "PALADIN" }, { "senseDemons", "Sense Demons", 5500, "WARLOCK" },
}) do
    -- profession tracking (no class) and racials need no class
    E("missingTracking", t[1], { label = t[2], spell = t[3], class = t[4], racial = t[5] or nil, profession = (t[4] == nil and not t[5]) or nil, category = "tracking" })
end

---------------------------------------------------------------------------
-- Low reagents: an item, and the spells that need it
---------------------------------------------------------------------------
E("lowReagent", "arcanePowder", { label = "Arcane Powder", class = "MAGE", reagent = 17020, spells = { 23028 } })
E("lowReagent", "runeOfTeleportation", { label = "Rune of Teleportation", class = "MAGE", reagent = 17031,
    spells = { 3561, 3562, 3563, 3565, 3566, 3567 } })
E("lowReagent", "runeOfPortals", { label = "Rune of Portals", class = "MAGE", reagent = 17032,
    spells = { 10059, 11416, 11417, 11418, 11419, 11420 } })
E("lowReagent", "lightFeather", { label = "Light Feather", reagent = 17056, classes = { MAGE = true, PRIEST = true }, spells = { 130, 1706 } })
E("lowReagent", "holyCandle", { label = "Holy Candle", class = "PRIEST", reagent = 17028, spells = { 21562 } })
E("lowReagent", "sacredCandle", { label = "Sacred Candle", class = "PRIEST", reagent = 17029, spells = { 21562, 27681, 27683 } })
E("lowReagent", "wildBerries", { label = "Wild Berries", class = "DRUID", reagent = 17021, spells = { 21849 } })
E("lowReagent", "wildThornroot", { label = "Wild Thornroot", class = "DRUID", reagent = 17026, spells = { 21849 } })
E("lowReagent", "rebirthSeeds", { label = "Rebirth seeds", class = "DRUID", reagent = 17034, items = { 17034, 17035, 17036, 17037, 17038 }, spells = { 20484 }, below = 3 })
E("lowReagent", "symbolOfKings", { label = "Symbol of Kings", class = "PALADIN", reagent = 21177, spells = { 25782, 25894, 25898, 25895, 25890, 25899 }, below = 20 })
E("lowReagent", "symbolOfDivinity", { label = "Symbol of Divinity", class = "PALADIN", reagent = 17033, spells = { 19752 }, below = 1 })
E("lowReagent", "fishOil", { label = "Fish Oil", class = "SHAMAN", reagent = 17058, spells = { 546 }, below = 3 })
E("lowReagent", "shinyFishScales", { label = "Shiny Fish Scales", class = "SHAMAN", reagent = 17057, spells = { 131 }, below = 3 })
E("lowReagent", "soulShard", { label = "Soul Shard", class = "WARLOCK", reagent = 6265,
    spells = { 697, 712, 691, 698, 6201, 693, 6353, 17877, 2362, 6366 }, below = 3 })
E("lowReagent", "flashPowder", { label = "Flash Powder", class = "ROGUE", reagent = 5140, spells = { 1856 } })
E("lowReagent", "blindingPowder", { label = "Blinding Powder", class = "ROGUE", reagent = 5530, spells = { 2094 }, below = 3 })

---------------------------------------------------------------------------
-- Ready cooldowns (in combat by default)
---------------------------------------------------------------------------
local COOLDOWNS = {
    WARRIOR = { { "recklessness", "Recklessness", 1719 }, { "deathWish", "Death Wish", 12292, true }, { "bloodrage", "Bloodrage", 2687 },
        { "sweepingStrikes", "Sweeping Strikes", 12328, true }, { "berserkerRage", "Berserker Rage", 18499 },
        { "retaliation", "Retaliation", 20230 }, { "shieldWall", "Shield Wall", 871 }, { "lastStand", "Last Stand", 12975, true } },
    ROGUE = { { "adrenalineRush", "Adrenaline Rush", 13750, true }, { "bladeFlurry", "Blade Flurry", 13877, true },
        { "coldBlood", "Cold Blood", 14177, true }, { "preparation", "Preparation", 14185, true }, { "evasion", "Evasion", 5277 },
        { "vanish", "Vanish", 1856 }, { "sprint", "Sprint", 2983 } },
    MAGE = { { "presenceOfMind", "Presence of Mind", 12043, true }, { "arcanePower", "Arcane Power", 12042, true },
        { "combustion", "Combustion", 11129, true }, { "evocation", "Evocation", 12051 }, { "iceBlock", "Ice Block", 11958, true },
        { "coldSnap", "Cold Snap", 12472, true }, { "iceBarrier", "Ice Barrier", 11426, true } },
    PRIEST = { { "innerFocus", "Inner Focus", 14751, true }, { "powerInfusion", "Power Infusion", 10060, true },
        { "fade", "Fade", 586 }, { "psychicScream", "Psychic Scream", 8122 } },
    DRUID = { { "innervate", "Innervate", 29166 }, { "naturesSwiftnessDruid", "Nature's Swiftness", 17116, true },
        { "barkskin", "Barkskin", 22812 }, { "frenziedRegeneration", "Frenzied Regeneration", 22842 }, { "dash", "Dash", 1850 } },
    HUNTER = { { "rapidFire", "Rapid Fire", 3045 }, { "bestialWrath", "Bestial Wrath", 19574, true },
        { "deterrence", "Deterrence", 19263, true } },
    PALADIN = { { "divineShield", "Divine Shield", 642 }, { "divineProtection", "Divine Protection", 498 },
        { "layOnHands", "Lay on Hands", 633 }, { "divineFavor", "Divine Favor", 20216, true },
        { "blessingOfProtection", "Blessing of Protection", 1022 } },
    SHAMAN = { { "elementalMastery", "Elemental Mastery", 16166, true }, { "naturesSwiftnessShaman", "Nature's Swiftness", 16188, true },
        { "manaTide", "Mana Tide Totem", 16190, true } },
    WARLOCK = { { "deathCoil", "Death Coil", 6789 }, { "amplifyCurse", "Amplify Curse", 18288, true },
        { "felDomination", "Fel Domination", 18708, true } },
}
for _, class in ipairs({ "WARRIOR", "ROGUE", "MAGE", "PRIEST", "DRUID", "HUNTER", "PALADIN", "SHAMAN", "WARLOCK" }) do
    for _, c in ipairs(COOLDOWNS[class]) do
        E("readyCooldown", c[1], { label = c[2], class = class, spell = c[3], talent = c[4] })
    end
end
-- Racials: everyone's listed; only the ones you know ever glow
for _, c in ipairs({
    { "bloodFury", "Blood Fury", 20572 }, { "berserking", "Berserking", 20554 }, { "stoneform", "Stoneform", 20594 },
    { "willOfTheForsaken", "Will of the Forsaken", 7744 }, { "escapeArtist", "Escape Artist", 20589 },
    { "warStomp", "War Stomp", 20549 }, { "perception", "Perception", 20600 },
}) do
    E("readyCooldown", c[1], { label = c[2], spell = c[3], racial = true })
end

---------------------------------------------------------------------------
-- Procs: usable only now and then
---------------------------------------------------------------------------
E("proc", "overpower", { label = "Overpower", class = "WARRIOR", spell = 7384 })
E("proc", "revenge", { label = "Revenge", class = "WARRIOR", spell = 6572 })
E("proc", "execute", { label = "Execute", class = "WARRIOR", spell = 5308 })
E("proc", "riposte", { label = "Riposte", class = "ROGUE", spell = 14251, talent = true })
E("proc", "counterattack", { label = "Counterattack", class = "HUNTER", spell = 19306, talent = true })
E("proc", "mongooseBite", { label = "Mongoose Bite", class = "HUNTER", spell = 1495 })
E("proc", "hammerOfWrath", { label = "Hammer of Wrath", class = "PALADIN", spell = 24275 })

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
function C.Find(kind, key) return byKey[tostring(kind) .. ":" .. tostring(key)] end

-- Whether an entry is for this class (nil class: anyone; racials and professions: anyone who knows them).
function C.ForClass(entry, class)
    if entry.classes then return entry.classes[class] == true end
    return entry.class == nil or entry.class == class
end

-- Kept per kind and class (the list never changes in a session): the caller must not change what it gets.
local forCache = {}
function C.For(kind, class)
    local id = tostring(kind) .. ":" .. tostring(class)
    local out = forCache[id]
    if out then return out end
    out = {}
    for _, e in ipairs(C.ENTRIES) do
        if e.type == kind and (class == nil or C.ForClass(e, class)) then out[#out + 1] = e end
    end
    forCache[id] = out
    return out
end

C.Categories = {}
for _, e in ipairs(C.ENTRIES) do
    if e.category then
        local list = C.Categories[e.category] or {}
        C.Categories[e.category] = list
        list[#list + 1] = e
    end
end

-- The words for a category in a message ("an aspect"), for the settings.
C.CATEGORY_LABEL = {
    mageArmor = "armor", warlockArmor = "armor", blessing = "blessing", paladinAura = "aura", aspect = "aspect",
    seal = "seal", tracking = "tracking",
}

-- Classes whose power is mana: who can use Arcane Intellect or Divine Spirit (a druid in a form still can).
C.MANA = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, PALADIN = true, SHAMAN = true, HUNTER = true }

-- The class tokens, in the game's order (for names and checks).
C.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
