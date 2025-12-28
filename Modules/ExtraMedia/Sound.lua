local T, W, I, C = unpack(Twich)

--- @type MediaModule
local MM = T:GetModule("Media")

--- @class SoundModule
SM = MM.Sound or {}
MM.Sound = SM

local LSM = LibStub("LibSharedMedia-3.0")

SM.SOUNDS = {
    { name = "Game-Ping",    extension = "mp3" },
    { name = "Game-Success", extension = "mp3" },
    { name = "Ping",         extension = "mp3" },
    { name = "Notable-Loot", extension = "mp3" },
    { name = "Game-Error",   extension = "mp3" },
}

local MEDIA_ROOT = "Interface\\AddOns\\TwichUI\\Media\\"
local MEDIA_TYPE = LSM.MediaType.SOUND

--- Registers a font with LibSharedMedia.
--- @param soundName string The name of the sound to register.
--- @param soundExtension string The file extension of the sound.
local function RegisterSound(soundName, soundExtension)
    local soundPath = MEDIA_ROOT .. "Sounds\\" .. soundName .. "." .. soundExtension
    local name = string.gsub(soundName, "-", " ")
    LSM:Register(MEDIA_TYPE, name, soundPath)
end

do
    for _, sound in ipairs(SM.SOUNDS) do
        RegisterSound(sound.name, sound.extension)
    end
end
