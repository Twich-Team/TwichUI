local T, W, I, C = unpack(Twich)

--- @type MediaModule
local MM = T:GetModule("Media")

--- @class TextureModule
TM = MM.Texture or {}
MM.Texture = TM

local LSM = LibStub("LibSharedMedia-3.0")

TM.TEXTURES = {
    { name = "TwichUI-1", extension = "tga" },
    { name = "TwichUI-2", extension = "tga" },
    { name = "TwichUI-3", extension = "tga" },
    { name = "TwichUI-4", extension = "tga" },

}

local MEDIA_ROOT = "Interface\\AddOns\\TwichUI\\Media\\"
local MEDIA_TYPE = LSM.MediaType.STATUSBAR

--- Registers a font with LibSharedMedia.
--- @param textureName string The name of the texture to register.
--- @param textureExtension string The file extension of the texture.
local function RegisterTexture(textureName, textureExtension)
    local texturePath = MEDIA_ROOT .. "Textures\\" .. textureName .. "." .. textureExtension
    local name = string.gsub(textureName, "-", " ")
    LSM:Register(MEDIA_TYPE, name, texturePath)
end

do
    for _, texture in ipairs(TM.TEXTURES) do
        RegisterTexture(texture.name, texture.extension)
    end
end
