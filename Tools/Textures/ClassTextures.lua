local T = unpack(Twich)

---@type ToolsModule
local TM = T:GetModule("Tools")

---@class TexturesTool
local Textures = TM.Textures or {}
TM.Textures = Textures


local TEXTURE_PATH = "Interface\\AddOns\\TwichUI\\Media\\Textures\\fabled.tga"

local textureHelper = {
    WARRIOR = {
        texString = '0:128:0:128',
        texStringLarge = '0:500:0:500',
        texCoords = { 0, 0, 0, 0.125, 0.125, 0, 0.125, 0.125 },
    },
    MAGE = {
        texString = '128:256:0:128',
        texStringLarge = '500:1000:0:500',
        texCoords = { 0.125, 0, 0.125, 0.125, 0.25, 0, 0.25, 0.125 },
    },
    ROGUE = {
        texString = '256:384:0:128',
        texStringLarge = '1000:1500:0:500',
        texCoords = { 0.25, 0, 0.25, 0.125, 0.375, 0, 0.375, 0.125 },
    },
    DRUID = {
        texString = '384:512:0:128',
        texStringLarge = '1500:2000:0:500',
        texCoords = { 0.375, 0, 0.375, 0.125, 0.5, 0, 0.5, 0.125 },
    },
    EVOKER = {
        texString = '512:640:0:128',
        texStringLarge = '2000:2500:0:500',
        texCoords = { 0.5, 0, 0.5, 0.125, 0.625, 0, 0.625, 0.125 },
    },
    HUNTER = {
        texString = '0:128:128:256',
        texStringLarge = '0:500:500:1000',
        texCoords = { 0, 0.125, 0, 0.25, 0.125, 0.125, 0.125, 0.25 },
    },
    SHAMAN = {
        texString = '128:256:128:256',
        texStringLarge = '500:1000:500:1000',
        texCoords = { 0.125, 0.125, 0.125, 0.25, 0.25, 0.125, 0.25, 0.25 },
    },
    PRIEST = {
        texString = '256:384:128:256',
        texStringLarge = '1000:1500:500:1000',
        texCoords = { 0.25, 0.125, 0.25, 0.25, 0.375, 0.125, 0.375, 0.25 },
    },
    WARLOCK = {
        texString = '384:512:128:256',
        texStringLarge = '1500:2000:500:1000',
        texCoords = { 0.375, 0.125, 0.375, 0.25, 0.5, 0.125, 0.5, 0.25 },
    },
    PALADIN = {
        texString = '0:128:256:384',
        texStringLarge = '0:500:1000:1500',
        texCoords = { 0, 0.25, 0, 0.375, 0.125, 0.25, 0.125, 0.375 },
    },
    DEATHKNIGHT = {
        texString = '128:256:256:384',
        texStringLarge = '500:1000:1000:1500',
        texCoords = { 0.125, 0.25, 0.125, 0.375, 0.25, 0.25, 0.25, 0.375 },
    },
    MONK = {
        texString = '256:384:256:384',
        texStringLarge = '1000:1500:1000:1500',
        texCoords = { 0.25, 0.25, 0.25, 0.375, 0.375, 0.25, 0.375, 0.375 },
    },
    DEMONHUNTER = {
        texString = '384:512:256:384',
        texStringLarge = '1500:2000:1000:1500',
        texCoords = { 0.375, 0.25, 0.375, 0.375, 0.5, 0.25, 0.5, 0.375 },
    },
}

local ATLAS_W, ATLAS_H = 1024, 1024

function Textures:GetClassTextureString(classFile, size)
    if not classFile then return nil end
    size = size or 16

    local info = textureHelper[classFile]
    if not info or not info.texCoords then return nil end

    -- texCoords: { l, t, l, b, r, t, r, b }
    local left   = info.texCoords[1] * ATLAS_W
    local top    = info.texCoords[2] * ATLAS_H
    local right  = info.texCoords[5] * ATLAS_W
    local bottom = info.texCoords[8] * ATLAS_H

    return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t"):format(
        TEXTURE_PATH,
        size, size,
        ATLAS_W, ATLAS_H,
        left, right, top, bottom
    )
end

function Textures:GetPlayerClassTextureString(size)
    local _, classFile = UnitClass("player")
    return self:GetClassTextureString(classFile, size)
end
