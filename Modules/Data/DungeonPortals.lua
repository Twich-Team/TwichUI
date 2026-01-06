local _G = _G
---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

---@class DataModule : AceModule
---@field DungeonPortals TwichUIDataDungeonPortals|nil
---@type DataModule
local Data = T:GetModule("Data")

---@class TwichUIDataDungeonPortals
---@field byMapId table<number, {mapId:number, name:string|nil, spellId:number}>
local DungeonPortals = Data.DungeonPortals or {}
Data.DungeonPortals = DungeonPortals

--
-- Manual data for Mythic+ dungeon teleport spells.
-- This is intentionally static: Blizzard does not provide a reliable API for mapping a dungeon mapId -> teleport spellId.
--
-- Fields:
-- - mapId: Mythic+ challenge map ID
-- - name: human-readable label (optional; UI can also derive the localized name from the mapId)
-- - spellId: the teleport spell ID (button is enabled only if the player knows this spell)
--
-- Tip for testing (since you said you don't have portals unlocked):
-- Temporarily set one entry's spellId to a spell your character *does* know.
--
DungeonPortals.byMapId = DungeonPortals.byMapId or {
    -- Example (fill with real IDs):
    -- [399] = { mapId = 399, name = "Halls of Atonement", spellId = 354462 },
    -- Midnight
    -- The War Within
    [499] = { mapId = 499, name = "Priory of the Sacred Flame", spellId = 445444 },
    [503] = { mapId = 503, name = "Ara-Kara, City of Echoes", spellId = 445417 },
    [505] = { mapId = 505, name = "The Dawnbreaker", spellId = 445414 },
    [525] = { mapId = 525, name = "Operation: Floodgate", spellId = 1216786 },
    [542] = { mapId = 542, name = "Eco-Dome Al'dani", spellId = 1237215 },
    -- Dragon Isles
    -- Shadowlands
    [378] = { mapId = 378, name = "Halls of Atonement", spellId = 354465 },
    [391] = { mapId = 391, name = "Tazavesh: Streets of Wonder", spellId = 367416 },
    [392] = { mapId = 392, name = "Tazavesh: So'leah's Gambit", spellId = 367416 },

    -- Battle for Azeroth
    -- Cataclysm
    -- Mists of Pandaria
    -- Wrath of the Lich King
    -- The Burning Crusade
    -- Vanilla
}

---@param mapId number|nil
---@return table|nil
function DungeonPortals:GetByMapId(mapId)
    mapId = tonumber(mapId)
    if not mapId then return nil end
    return self.byMapId and self.byMapId[mapId] or nil
end
