-- TwichUI: media
-- Registers fonts and sounds with LibSharedMedia so EllesmereUI, BigWigs,
-- GTFO-style dropdowns and any other LSM-aware addon can pick them. It never
-- changes a font or plays a sound by itself.
local R = TwichUI

local FONTS = {
    ["Alegreya Sans"]            = "AlegreyaSans-Regular.ttf",
    ["Alegreya Sans Medium"]     = "AlegreyaSans-Medium.ttf",
    ["Alegreya Sans Bold"]       = "AlegreyaSans-Bold.ttf",
    ["Alegreya Sans SC Bold"]    = "AlegreyaSansSC-Bold.ttf",
    ["Alegreya"]                 = "Alegreya-Regular.ttf",
    ["Barlow SemiCond Medium"]   = "BarlowSemiCondensed-Medium.ttf",
    ["Barlow SemiCond SemiBold"] = "BarlowSemiCondensed-SemiBold.ttf",
    ["Cinzel"]                   = "Cinzel-SemiBold.ttf",
    ["Spectral"]                 = "Spectral-Regular.ttf",
    ["Spectral Medium"]          = "Spectral-Medium.ttf",
    ["Spectral SemiBold"]        = "Spectral-SemiBold.ttf",
    ["Spectral Bold"]            = "Spectral-Bold.ttf",
}

local SOUNDS = {
    ["Fallen Toll"]      = "Fallen_Toll.ogg",
    ["Single Knell"]     = "Single_Knell.ogg",
    ["Light Fades"]      = "Light_Fades.ogg",
    ["GTFO High Damage"] = "GTFO_High.ogg",
    ["GTFO Low Damage"]  = "GTFO_Low.ogg",
    ["GTFO Fail"]        = "GTFO_Fail.ogg",
    ["TwichUI Notification"] = "TwichUI_Notification.mp3",
}
R.MediaFonts, R.MediaSounds = FONTS, SOUNDS

-- Handy for GTFO, which takes a file path: /gtfo custom1 <path>
function R:SoundPath(file) return R.PATH .. [[media\sounds\]] .. file end

R:OnInit(function()
    if not R:Enabled("media") then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    for name, file in pairs(FONTS) do
        LSM:Register(LSM.MediaType.FONT, name, R.PATH .. [[media\fonts\]] .. file, LSM.LOCALE_BIT_western)
    end
    for name, file in pairs(SOUNDS) do
        LSM:Register(LSM.MediaType.SOUND, name, R:SoundPath(file))
    end
    R.mediaRegistered = true
end)
