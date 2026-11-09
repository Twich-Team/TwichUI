-- TwichUI: camping bar, the data (no game calls)
-- What WoW: Forever's camping lets a character put down: the campfire kits Cooking makes, and one camp object per
-- profession tier (Mana Well, Sharpening Wheel ...). Where these facts come from, and how sure they are:
--   * item IDs: the camp items of Forever, as EllesmereUI's bag categories list them (all rights reserved: only the
--     facts, IDs and names, are used; nothing of it is loaded or called);
--   * craft spell IDs and the skill each needs: NaowhForever's recipe data (same terms), and for Herbalism and
--     Skinning, which that data does not hold, a public camping guide (wow-professions.com). The pairing of those
--     six spells with their items is by name only and has not been checked in the game;
--   * the skill line IDs are the Classic ones (Herbalism 182 and Skinning 393 are not in the sources above).
-- None of it has been read from a Forever client. The bar only ever uses an ID to ask the game a question
-- (do I hold this, do I know this recipe), so a wrong ID means a missing button, never a wrong action.
-- The names are English and only a fallback for display: the game's own item name is used when it is loaded.

local R = TwichUI
local D = {}
R.CampingData = D

D.FIRE_SPELL = 818          -- Basic Campfire, the spell EllesmereUI's profession block casts
D.SLEEPING_BAG = 211527     -- the Cozy Sleeping Bag (guides/CozyBagData.lua's D.item)
D.NEARBY_AURA = 1283391     -- "Campfire Nearby": the aura the game gives while a campfire is in range

-- The Cozy Sleeping Bag's rest bonus (camping/Rest.lua). From two guide pages (warcraft.wiki.gg, warcrafttavern.com), NOT
-- read from a Forever client: you lie in the bag; each full minute adds one stack of "Well-Rested" (+1% experience), to 3.
-- The aura ID is the one the Warcraft Tavern guide links; it only ever confirms the clock, it never starts it (the player
-- has no aura during the first minute). `/tui camp probe` lists what the client really says.
D.REST_AURA = 429959
D.REST_STEP = 60            -- seconds in the bag for one stack
D.REST_STACKS = 3           -- the most stacks
D.REST_TOTAL = D.REST_STEP * D.REST_STACKS
D.REST_WINDOW = 300         -- seconds: a bag used this recently can be the one you are lying in

-- Campfire kits, smallest first. slots: how many camp objects the fire holds. skill: the Cooking skill the recipe needs.
D.FIRES = {
    { item = 279981, spell = 1229737, skill = 1,   slots = 3,  name = "Basic Campfire Kit" },
    { item = 279961, spell = 1283400, skill = 90,  slots = 5,  name = "Journeyman Campfire Kit" },
    { item = 279974, spell = 1291341, skill = 200, slots = 10, name = "Expert Campfire Kit" },
}
D.FIRE_LINE = 185           -- Cooking

-- The professions, in the order the bar shows them. line: the skill line. objects: lowest tier first.
-- skill is the recipe's skill requirement. Tier 1 is taught by a trainer; tiers 2 and 3 need a recipe that drops.
D.GROUPS = {
    { key = "alchemy", line = 171, name = "Alchemy", objects = {
        { tier = 1, item = 279956, spell = 1230564, skill = 20,  name = "Mana Well" },
        { tier = 2, item = 279970, spell = 1263005, skill = 140, name = "Fermenter" },
        { tier = 3, item = 279990, spell = 1263078, skill = 300, name = "Alchemy Laboratory" } } },
    { key = "blacksmithing", line = 164, name = "Blacksmithing", objects = {
        { tier = 1, item = 279944, spell = 1230171, skill = 20,  name = "Sharpening Wheel" },
        { tier = 2, item = 279988, spell = 1263041, skill = 140, name = "Anvil" },
        { tier = 3, item = 279955, spell = 1263073, skill = 300, name = "Master Forge" } } },
    { key = "cooking", line = 185, name = "Cooking", objects = {
        { tier = 2, item = 279957, spell = 1262978, skill = 140, name = "Cookie's Feast" },
        { tier = 3, item = 279982, spell = 1263067, skill = 300, name = "Iron Oven" } } },
    { key = "enchanting", line = 333, name = "Enchanting", objects = {
        { tier = 1, item = 279976, spell = 1230643, skill = 20,  name = "Enchanted Lute" },
        { tier = 2, item = 279985, spell = 1263056, skill = 140, name = "Arcane Salvager" },
        { tier = 3, item = 279987, spell = 1263082, skill = 300, name = "Arcane Forge" } } },
    { key = "engineering", line = 202, name = "Engineering", objects = {
        { tier = 1, item = 279950, spell = 1230656, skill = 20,  name = "Reagent Bot" },
        { tier = 2, item = 279949, spell = 1263034, skill = 140, name = "Repair Bot" },
        { tier = 3, item = 279989, spell = 1263083, skill = 300, name = "Anarchist's Workbench" } } },
    { key = "firstaid", line = 129, name = "First Aid", objects = {
        { tier = 1, item = 279968, spell = 1230117, skill = 20,  name = "First Aid Kit" },
        { tier = 2, item = 279940, spell = 1262996, skill = 140, name = "Toxin Study" },
        { tier = 3, item = 279951, spell = 1263001, skill = 300, name = "Plague Doctor's Laboratory" } } },
    { key = "fishing", line = 356, name = "Fishing", objects = {
        { tier = 1, item = 279967, spell = 1229745, skill = 20,  name = "Fish Bowl" },
        { tier = 2, item = 279965, spell = 1262990, skill = 140, name = "Fishing Rack" },
        { tier = 3, item = 279966, spell = 1262998, skill = 300, name = "Fishing Hut" } } },
    { key = "herbalism", line = 182, name = "Herbalism", objects = {
        { tier = 1, item = 279962, spell = 1229705, skill = 20,  name = "Incense Candle" },
        { tier = 2, item = 279964, spell = 1262980, skill = 140, name = "Greenhouse" },
        { tier = 3, item = 279947, spell = 1263070, skill = 300, name = "Seed Hybridizer" } } },
    { key = "leatherworking", line = 165, name = "Leatherworking", objects = {
        { tier = 1, item = 279978, spell = 1229432, skill = 20,  name = "Camp Tent" },
        { tier = 2, item = 279941, spell = 1263031, skill = 140, name = "Tanning Rack" },
        { tier = 3, item = 279945, spell = 1263079, skill = 300, name = "Sewing Machine" } } },
    { key = "mining", line = 186, name = "Mining", objects = {
        { tier = 1, item = 279960, spell = 1230161, skill = 20,  name = "Lodestone" },
        { tier = 2, item = 279948, spell = 1262975, skill = 140, name = "Rock Garden" },
        { tier = 3, item = 279952, spell = 1263071, skill = 300, name = "Molten Foundry" } } },
    { key = "skinning", line = 393, name = "Skinning", objects = {
        { tier = 1, item = 279979, spell = 1229517, skill = 20,  name = "Camp Chair" },
        { tier = 2, item = 279969, spell = 1262985, skill = 140, name = "Field Guide" },
        { tier = 3, item = 279938, spell = 1262982, skill = 300, name = "Trapper's Workbench" } } },
    -- Two tier-1 banners: the sources list one for each faction, and which is which isn't established; the recipe
    -- you know decides which one the bar offers.
    { key = "tailoring", line = 197, name = "Tailoring", objects = {
        { tier = 1, item = 279972, spell = 1229504, skill = 20,  name = "Faction Banner" },
        { tier = 1, item = 279973, spell = 1263425, skill = 20,  name = "Faction Banner" },
        { tier = 2, item = 279943, spell = 1263032, skill = 140, name = "Spinning Wheel" },
        { tier = 3, item = 279959, spell = 1263080, skill = 300, name = "Loom" } } },
}

D.GROUP_BY_KEY = {}
for _, g in ipairs(D.GROUPS) do D.GROUP_BY_KEY[g.key] = g end

-- Every item and every craft spell the bar can ask about, in one list each (built once).
D.ITEMS, D.SPELLS, D.LINES = {}, {}, {}
do
    local seenItem, seenSpell, seenLine = {}, {}, {}
    local function Item(id) if not seenItem[id] then seenItem[id] = true; D.ITEMS[#D.ITEMS + 1] = id end end
    local function Spell(id) if not seenSpell[id] then seenSpell[id] = true; D.SPELLS[#D.SPELLS + 1] = id end end
    local function Line(id) if not seenLine[id] then seenLine[id] = true; D.LINES[#D.LINES + 1] = id end end
    for _, fire in ipairs(D.FIRES) do Item(fire.item); Spell(fire.spell) end
    Line(D.FIRE_LINE)
    for _, g in ipairs(D.GROUPS) do
        Line(g.line)
        for _, o in ipairs(g.objects) do Item(o.item); Spell(o.spell) end
    end
    Item(D.SLEEPING_BAG)
end
