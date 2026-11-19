-- Adapted from APGM82/DisenchantForever at ab223e6750b8e1aa24b76f66437deee461c27b47.
-- Copyright (c) 2026 APGM82. MIT: licenses/MIT-DisenchantForever.txt.
-- Forever item brackets; Classic-derived yield probabilities are ESTIMATES.
-- Kept separate from validated Market price data; no live outcome verification claim.
-- Lo que sale al desencantar cada objeto.
--
-- Los tramos son los del cliente de Forever (tabla ItemDisenchantLoot, build 1.60.1.70425): clase,
-- calidad y nivel de objeto. Lo que sale de cada tramo lo decide el servidor y no viene en el cliente,
-- asi que porcentajes y cantidades son los de vmangos (disenchant_loot_template, base del 28/09/2026),
-- que reproduce Classic 1.12. cmangos (classic-db z2815) da lo mismo salvo donde se dice.

local M = { VERSION = 1, BRACKETS_BUILD = '1.60.1.70425', FLAGS_BUILD = '1.60.1.70888' }
TwichUI.Workshop.DisenchantData = M

local STRANGE_DUST, SOUL_DUST, VISION_DUST, DREAM_DUST, ILLUSION_DUST = 10940, 11083, 11137, 11176, 16204
local LESSER_MAGIC, GREATER_MAGIC = 10938, 10939
local LESSER_ASTRAL, GREATER_ASTRAL = 10998, 11082
local LESSER_MYSTIC, GREATER_MYSTIC = 11134, 11135
local LESSER_NETHER, GREATER_NETHER = 11174, 11175
local LESSER_ETERNAL, GREATER_ETERNAL = 16202, 16203
local SMALL_GLIMMERING, LARGE_GLIMMERING = 10978, 11084
local SMALL_GLOWING, LARGE_GLOWING = 11138, 11139
local SMALL_RADIANT, LARGE_RADIANT = 11177, 11178
local SMALL_BRILLIANT, LARGE_BRILLIANT = 14343, 14344
local NEXUS = 20725

-- solo se ven si el juego aun no tiene cargado el nombre traducido
M.names = {
    [STRANGE_DUST] = "Strange Dust", [SOUL_DUST] = "Soul Dust", [VISION_DUST] = "Vision Dust",
    [DREAM_DUST] = "Dream Dust", [ILLUSION_DUST] = "Illusion Dust",
    [LESSER_MAGIC] = "Lesser Magic Essence", [GREATER_MAGIC] = "Greater Magic Essence",
    [LESSER_ASTRAL] = "Lesser Astral Essence", [GREATER_ASTRAL] = "Greater Astral Essence",
    [LESSER_MYSTIC] = "Lesser Mystic Essence", [GREATER_MYSTIC] = "Greater Mystic Essence",
    [LESSER_NETHER] = "Lesser Nether Essence", [GREATER_NETHER] = "Greater Nether Essence",
    [LESSER_ETERNAL] = "Lesser Eternal Essence", [GREATER_ETERNAL] = "Greater Eternal Essence",
    [SMALL_GLIMMERING] = "Small Glimmering Shard", [LARGE_GLIMMERING] = "Large Glimmering Shard",
    [SMALL_GLOWING] = "Small Glowing Shard", [LARGE_GLOWING] = "Large Glowing Shard",
    [SMALL_RADIANT] = "Small Radiant Shard", [LARGE_RADIANT] = "Large Radiant Shard",
    [SMALL_BRILLIANT] = "Small Brilliant Shard", [LARGE_BRILLIANT] = "Large Brilliant Shard",
    [NEXUS] = "Nexus Crystal",
}

-- { nivel minimo, nivel maximo, { %, cantidad minima, cantidad maxima, objeto }, ... }
local ARMOR_UNCOMMON = {
    { 5, 15,  { 80, 1, 2, STRANGE_DUST },  { 20, 1, 2, LESSER_MAGIC } },
    { 16, 20, { 75, 2, 3, STRANGE_DUST },  { 20, 1, 2, GREATER_MAGIC },   { 5, 1, 1, SMALL_GLIMMERING } },
    { 21, 25, { 75, 4, 6, STRANGE_DUST },  { 15, 1, 2, LESSER_ASTRAL },   { 10, 1, 1, SMALL_GLIMMERING } },
    { 26, 30, { 75, 1, 2, SOUL_DUST },     { 20, 1, 2, GREATER_ASTRAL },  { 5, 1, 1, LARGE_GLIMMERING } },
    { 31, 35, { 75, 2, 5, SOUL_DUST },     { 20, 1, 2, LESSER_MYSTIC },   { 5, 1, 1, SMALL_GLOWING } },
    { 36, 40, { 75, 1, 2, VISION_DUST },   { 20, 1, 2, GREATER_MYSTIC },  { 5, 1, 1, LARGE_GLOWING } },
    { 41, 45, { 75, 2, 5, VISION_DUST },   { 20, 1, 2, LESSER_NETHER },   { 5, 1, 1, SMALL_RADIANT } },
    { 46, 50, { 75, 1, 2, DREAM_DUST },    { 20, 1, 2, GREATER_NETHER },  { 5, 1, 1, LARGE_RADIANT } },
    { 51, 55, { 75, 2, 5, DREAM_DUST },    { 20, 1, 2, LESSER_ETERNAL },  { 5, 1, 1, SMALL_BRILLIANT } },
    { 56, 60, { 75, 1, 2, ILLUSION_DUST }, { 20, 1, 2, GREATER_ETERNAL }, { 5, 1, 1, LARGE_BRILLIANT } },
    -- cmangos: 2 esencias, no 2-3
    { 61, 99, { 75, 2, 5, ILLUSION_DUST }, { 20, 2, 3, GREATER_ETERNAL }, { 5, 1, 1, LARGE_BRILLIANT } },
}

-- las armas dan sobre todo esencia
local WEAPON_UNCOMMON = {
    { 5, 15,  { 80, 1, 2, LESSER_MAGIC },    { 20, 1, 2, STRANGE_DUST } },
    { 16, 20, { 75, 1, 2, GREATER_MAGIC },   { 20, 2, 3, STRANGE_DUST },  { 5, 1, 1, SMALL_GLIMMERING } },
    { 21, 25, { 75, 1, 2, LESSER_ASTRAL },   { 15, 4, 6, STRANGE_DUST },  { 10, 1, 1, SMALL_GLIMMERING } },
    { 26, 30, { 75, 1, 2, GREATER_ASTRAL },  { 20, 1, 2, SOUL_DUST },     { 5, 1, 1, LARGE_GLIMMERING } },
    { 31, 35, { 75, 1, 2, LESSER_MYSTIC },   { 20, 2, 5, SOUL_DUST },     { 5, 1, 1, SMALL_GLOWING } },
    { 36, 40, { 75, 1, 2, GREATER_MYSTIC },  { 20, 1, 2, VISION_DUST },   { 5, 1, 1, LARGE_GLOWING } },
    { 41, 45, { 75, 1, 2, LESSER_NETHER },   { 20, 2, 5, VISION_DUST },   { 5, 1, 1, SMALL_RADIANT } },
    { 46, 50, { 75, 1, 2, GREATER_NETHER },  { 20, 1, 2, DREAM_DUST },    { 5, 1, 1, LARGE_RADIANT } },
    { 51, 55, { 75, 1, 2, LESSER_ETERNAL },  { 22, 2, 5, DREAM_DUST },    { 3, 1, 1, SMALL_BRILLIANT } },
    { 56, 60, { 75, 1, 2, GREATER_ETERNAL }, { 22, 1, 2, ILLUSION_DUST }, { 3, 1, 1, LARGE_BRILLIANT } },
    -- cmangos: 2 esencias, no 2-3
    { 61, 99, { 75, 2, 3, GREATER_ETERNAL }, { 22, 2, 5, ILLUSION_DUST }, { 3, 1, 1, LARGE_BRILLIANT } },
}

-- los azules son iguales en armas y armaduras
local RARE = {
    -- tramo nuevo de Forever, sin datos de ningun servidor: lo de 16-20, sin confirmar
    { 5, 15,  { 100, 1, 1, SMALL_GLIMMERING }, unconfirmed = true },
    { 16, 20, { 100, 1, 1, SMALL_GLIMMERING } },
    { 21, 25, { 100, 1, 1, SMALL_GLIMMERING } },
    { 26, 30, { 100, 1, 1, LARGE_GLIMMERING } },
    { 31, 35, { 100, 1, 1, SMALL_GLOWING } },
    { 36, 40, { 100, 1, 1, LARGE_GLOWING } },
    { 41, 45, { 100, 1, 1, SMALL_RADIANT } },
    { 46, 50, { 100, 1, 1, LARGE_RADIANT } },
    { 51, 55, { 100, 1, 1, SMALL_BRILLIANT } },
    -- vmangos: los de nivel 60 ya llevan el 1% de cristal de abajo
    { 56, 60, { 100, 1, 1, LARGE_BRILLIANT } },
    -- cmangos: nada de cristal hasta el nivel 66, y entonces un 0.5%
    { 61, 99, { 99, 1, 1, LARGE_BRILLIANT }, { 1, 1, 1, NEXUS } },
}

local EPIC = {
    { 40, 45, { 100, 2, 4, SMALL_RADIANT } },
    { 46, 50, { 100, 2, 4, LARGE_RADIANT } },
    { 51, 55, { 100, 2, 4, SMALL_BRILLIANT } },
    { 56, 60, { 100, 1, 1, NEXUS } },
    { 61, 99, { 100, 1, 2, NEXUS } },
}

local CLASS_WEAPON, CLASS_ARMOR = 2, 4
local TABLES = {
    [CLASS_ARMOR]  = { [2] = ARMOR_UNCOMMON, [3] = RARE, [4] = EPIC },
    [CLASS_WEAPON] = { [2] = WEAPON_UNCOMMON, [3] = RARE, [4] = EPIC },
}

-- el tramo de un objeto, o nil si no se desencanta
function M.Find(classID, quality, level)
    local byQuality = TABLES[classID]
    local rows = byQuality and quality and byQuality[quality]
    if not rows or not level then return nil end
    for _, row in ipairs(rows) do
        if level >= row[1] and level <= row[2] then return row end
    end
    return nil
end
