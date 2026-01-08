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
