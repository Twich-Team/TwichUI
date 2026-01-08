local _G = _G
---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

---@class DataModule : AceModule
---@field Handbook TwichUIDataHandbook|nil
---@type DataModule
local Data = T:GetModule("Data")

---@class TwichUIDataHandbook
---@field GearTracks TwichUIDataHandbookGearTrackEntry[]|nil
---@field Crests TwichUIDataHandbookCrestEntry[]|nil
---@field ItemUpgrades TwichUIDataHandbookItemUpgradeEntry[]|nil
---@field GearEnhancements TwichUIDataHandbookGearEnhancements|nil
local Handbook = Data.Handbook or {}
Data.Handbook = Handbook

---@class TwichUIDataHandbookGearTrackEntry
---@field level number Keystone level (e.g. 2 for +2)
---@field itemLevel number Reward item level
---@field track string Upgrade track label
---@field color string|nil Hex color code ("#RRGGBB") used to color the track text

--
-- Manual reference data for Mythic+ UI tables.
--
-- These are intentionally static (hand-entered).
--
local HERO_COLOR = '#3a72fe'
local MYTH_COLOR = '#ab3bfe'
Handbook.GearTracks = Handbook.GearTracks or {
    -- Example entry (replace/remove as desired)
    { level = 2,  itemLevel = 259, track = "Hero 1/6", color = HERO_COLOR },
    { level = 3,  itemLevel = 259, track = "Hero 1/6", color = HERO_COLOR },
    { level = 4,  itemLevel = 263, track = "Hero 2/6", color = HERO_COLOR },
    { level = 5,  itemLevel = 263, track = "Hero 2/6", color = HERO_COLOR },
    { level = 6,  itemLevel = 266, track = "Hero 3/6", color = HERO_COLOR },
    { level = 7,  itemLevel = 269, track = "Hero 4/6", color = HERO_COLOR },
    { level = 8,  itemLevel = 269, track = "Hero 4/6", color = HERO_COLOR },
    { level = 9,  itemLevel = 269, track = "Hero 4/6", color = HERO_COLOR },
    { level = 10, itemLevel = 272, track = "Myth 1/6", color = MYTH_COLOR },
    { level = 11, itemLevel = 272, track = "Myth 1/6", color = MYTH_COLOR },
    { level = 12, itemLevel = 276, track = "Myth 2/6", color = MYTH_COLOR },
    { level = 13, itemLevel = 276, track = "Myth 2/6", color = MYTH_COLOR },
    { level = 14, itemLevel = 276, track = "Myth 2/6", color = MYTH_COLOR },
    { level = 15, itemLevel = 279, track = "Myth 3/6", color = MYTH_COLOR },
    { level = 16, itemLevel = 279, track = "Myth 3/6", color = MYTH_COLOR },
    { level = 17, itemLevel = 279, track = "Myth 3/6", color = MYTH_COLOR },
    { level = 18, itemLevel = 282, track = "Myth 4/6", color = MYTH_COLOR },
}

---@class TwichUIDataHandbookCrestEntry
---@field keystoneLevel number|nil Keystone level (e.g. 2 for +2)
---@field delveLevel number|string|nil Delve tier/level (nil when no longer drops)
---@field raidLevel number|string|nil Raid difficulty/label
---@field crest string Crest name

Handbook.Crests = Handbook.Crests or {
    -- Example entry (replace/remove as desired)
    -- { keystoneLevel = 2, delveLevel = 1, raidLevel = 1, crest = "Weathered" },
    { keystoneLevel = 2, delveLevel = 6,   raidLevel = "Normal", crest = "Champion Crest" },
    { keystoneLevel = 4, delveLevel = 11,  raidLevel = "Heroic", crest = "Hero Crest" },
    { keystoneLevel = 9, delveLevel = nil, raidLevel = "Mythic", crest = "Mythic Crest" },
}

---@class TwichUIDataHandbookItemUpgradeEntry
---@field track string Track label (e.g. "Hero 1/6")
---@field crestCost number|string Crest cost to upgrade (can be a string like "15" or "15+15")

Handbook.ItemUpgrades = Handbook.ItemUpgrades or {
    -- Example entry (replace/remove as desired)
    -- { track = "Hero 1/6", crestCost = 15 },
    { track = "1/6", crestCost = 0 },
    { track = "2/6", crestCost = 10 },
    { track = "3/6", crestCost = 20 },
    { track = "4/6", crestCost = 30 },
    { track = "5/6", crestCost = 40 },
    { track = "6/6", crestCost = 50 },
}

---@class TwichUIDataHandbookGearEnhancements
---@field SlotOrder string[]|nil Order of slots for display (optional)
---@field Slots table<string, TwichUIDataHandbookGearEnhancementSlot>|nil Enhancements available per gear slot
---@field Gems TwichUIDataHandbookGemEntry[]|number[]|string|nil List of gems available for gem priority.
---@field GemsCSV string|nil Convenience: CSV of itemIDs (e.g. from WoWHead). If set, it is expanded into `Gems` on load.

---@class TwichUIDataHandbookGearEnhancementSlot
---@field label string Display label for the slot
---@field items TwichUIDataHandbookEnhancementItem[]|number[]|string|nil List of selectable enhancement items
---@field ItemsCSV string|nil Convenience: CSV of itemIDs for this slot. If set, it is expanded into `items` on load.

---@class TwichUIDataHandbookEnhancementItem
---@field itemId number ItemID used to create an item link via GetItemInfo (required)
---@field itemLink string|nil Optional explicit item link string (use when you need a specific variant)
---@field label string|nil Optional label override (shown if GetItemInfo isn't cached yet)

---@class TwichUIDataHandbookGemEntry
---@field itemId number ItemID used to create an item link via GetItemInfo (required)
---@field itemLink string|nil Optional explicit item link string (use when you need a specific variant)

local function BuildGemEntriesFromCSV(csv)
    if type(csv) ~= "string" then return {} end
    local out = {}
    local seen = {}
    for num in csv:gmatch("%d+") do
        local id = tonumber(num)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            table.insert(out, { itemId = id })
        end
    end
    return out
end

local function BuildEnhancementItemsFromCSV(csv)
    if type(csv) ~= "string" then return {} end
    local out = {}
    local seen = {}
    for num in csv:gmatch("%d+") do
        local id = tonumber(num)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            table.insert(out, { itemId = id })
        end
    end
    return out
end

local function NormalizeEnhancementItemList(items)
    if items == nil then
        return {}
    end

    if type(items) == "string" then
        return BuildEnhancementItemsFromCSV(items)
    end

    if type(items) ~= "table" then
        return {}
    end

    local out = {}
    local seen = {}
    for _, v in ipairs(items) do
        if type(v) == "number" then
            local id = tonumber(v)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                table.insert(out, { itemId = id })
            end
        elseif type(v) == "table" then
            local id = tonumber(v.itemId)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                table.insert(out, { itemId = id, itemLink = v.itemLink, label = v.label })
            end
        end
    end
    return out
end

local function NormalizeGemList(gems)
    if gems == nil then
        return {}
    end

    if type(gems) == "string" then
        return BuildGemEntriesFromCSV(gems)
    end

    if type(gems) ~= "table" then
        return {}
    end

    local out = {}
    local seen = {}
    for _, v in ipairs(gems) do
        if type(v) == "number" then
            local id = tonumber(v)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                table.insert(out, { itemId = id })
            end
        elseif type(v) == "table" then
            local id = tonumber(v.itemId)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                table.insert(out, { itemId = id, itemLink = v.itemLink })
            end
        end
    end
    return out
end

Handbook.GearEnhancements = Handbook.GearEnhancements or {
    -- Optional: provide a stable, preferred display order.
    SlotOrder = {
        "HEAD",
        "NECK",
        "SHOULDERS",
        "BACK",
        "CHEST",
        "WRISTS",
        "HANDS",
        "WAIST",
        "LEGS",
        "FEET",
        "FINGER1",
        "FINGER2",
        "TRINKET1",
        "TRINKET2",
        "MAINHAND",
        "OFFHAND",
    },
    -- Populate per-slot enhancements you want players to pick from.
    -- NOTE: itemId is the primary key needed to build a full item link at runtime.
    Slots = {
        MAINHAND = {
            label = "Main Hand",
            itemsCSV =
            [[244029, 244026, 244030, 243970, 243973, 244000, 243996, 243998, 244027, 243969, 243968, 243972, 243997, 243999, 244001, 244031, 243971, 244028]],
        },
        OFFHAND = {
            label = "Off Hand",
            itemsCSV =
            [[244029, 244026, 244030, 243970, 243973, 244000, 243996, 243998, 244027, 243969, 243968, 243972, 243997, 243999, 244001, 244031, 243971, 244028]],

        },
        RING = {
            label = "Rings",
            itemsCSV =
            [[244015, 243987, 243959, 244012, 243984, 243957, 243985, 244011, 244014, 244017, 243955, 244010, 244016, 243954, 243986, 244013, 243956, 243958]],
        },
        LEGS = {
            label = "Legs",
            itemsCSV = [[244641, 240133, 240156, 244642, 240155, 244644, 240157, 240094, 244640, 244643, 244645, 240154]]
        },
        CHEST = {
            label = "Chest",
            itemsCSV = [[243977, 243947, 243946, 243976, 244002, 243975, 243974, 244003]],
        },
        SHOULDERS = {
            label = "Shoulders",
            itemsCSV =
            [[243991, 244021, 243960, 243963, 243434, 243961, 244019, 244020, 243988, 243962, 243989, 244018, 243442, 243990]],
        },
        FEET = {
            label = "Boots",
            itemsCSV = [[243983, 243953, 243982, 244008, 244009, 243952]],
        },
        HEAD = {
            label = "Helm",
            itemsCSV = [[244007, 243949, 243951, 243979, 243981, 244006, 243948, 243950, 243978, 243980, 244005, 244004]],
        }
    },
    -- Populate gems players can choose from in the Gem Priority section.
    -- Option A (recommended): paste WoWHead-style CSV.
    GemsCSV = [[
240983, 240967, 240894, 240917, 240855, 240879, 240890, 240871, 240877, 240892, 240900, 240859, 240893, 240966,
240857, 240898, 240905, 240906, 240908, 240913, 241142, 240889, 240911, 240915, 240971, 240982, 241143, 241144,
240867, 240872, 240874, 240904, 240866, 240884, 240888, 240891, 240902, 240910, 240858, 240860, 240863, 240870,
240878, 240881, 240896, 240907, 240909, 240856, 240865, 240875, 240880, 240883, 240886, 240897, 240899, 240903,
240918, 240861, 240862, 240868, 240869, 240873, 240876, 240882, 240885, 240887, 240895, 240901, 240914, 240968,
240970, 240864, 240912, 240916, 240969
    ]],
    -- Option B: provide a list (tables or raw numbers). If `GemsCSV` is set, it wins.
    Gems = {
        -- { itemId = 241143 },
        -- 241143,
    },
}

do
    local ge = Handbook.GearEnhancements
    if type(ge) == "table" then
        if type(ge.Slots) == "table" then
            for _, slot in pairs(ge.Slots) do
                if type(slot) == "table" then
                    local csv = slot.ItemsCSV
                        or slot.itemsCSV
                        or slot.itemsCsv
                        or slot.ItemsCsv
                        or slot.items_csv

                    if type(csv) == "string" and csv ~= "" then
                        slot.items = BuildEnhancementItemsFromCSV(csv)
                    else
                        slot.items = NormalizeEnhancementItemList(slot.items)
                    end
                end
            end
        end

        if type(ge.GemsCSV) == "string" and ge.GemsCSV ~= "" then
            ge.Gems = BuildGemEntriesFromCSV(ge.GemsCSV)
        else
            ge.Gems = NormalizeGemList(ge.Gems)
        end
    end
end
