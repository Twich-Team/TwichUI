local _G = _G
---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

---@class DataModule : AceModule
---@field DungeonPortals TwichUIDataDungeonPortals|nil
---@type DataModule
local Data = T:GetModule("Data")

---@class TwichUIDataDungeonPortals
---@field byMapId table<number, {mapId:number, name:string|nil, spellId:number, achievementId:number}>
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
-- - achievementId: achievement that unlocks the teleport (informational; not required for enable/disable)
--
-- Tip for testing (since you said you don't have portals unlocked):
-- Temporarily set one entry's spellId to a spell your character *does* know.
--
DungeonPortals.byMapId = DungeonPortals.byMapId or {
    -- Example (fill with real IDs):
    -- [399] = { mapId = 399, name = "Halls of Atonement", spellId = 354462, achievementId = 14352 },
}

---@param mapId number|nil
---@return table|nil
function DungeonPortals:GetByMapId(mapId)
    mapId = tonumber(mapId)
    if not mapId then return nil end
    return self.byMapId and self.byMapId[mapId] or nil
end
