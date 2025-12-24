local T, W, I, C = unpack(Twich)

--- @type MediaModule
local MM = T:GetModule("Media")

--- @class FontModule
FM = MM.Font or {}
MM.Font = FM

local LSM = LibStub("LibSharedMedia-3.0")

FM.FONTS = {
    { name = "FunnelDisplay-Bold",      extension = "ttf" },
    { name = "FunnelDisplay-ExtraBold", extension = "ttf" },
    { name = "FunnelDisplay-Light",     extension = "ttf" },
    { name = "FunnelDisplay-Medium",    extension = "ttf" },
    { name = "FunnelDisplay-Regular",   extension = "ttf" },
    { name = "FunnelDisplay-SemiBold",  extension = "ttf" },
    { name = "Roboto-Bold",             extension = "ttf" },
    { name = "Roboto-Italic",           extension = "ttf" },
    { name = "Roboto-Light",            extension = "ttf" },
    { name = "Roboto-Regular",          extension = "ttf" },
}

local MEDIA_ROOT = "Interface\\AddOns\\TwichUI\\Media\\"
local MEDIA_TYPE = LSM.MediaType.FONT

--- Registers a font with LibSharedMedia.
--- @param fontName string The name of the font to register.
--- @param fontExtension string The file extension of the font.
local function RegisterFont(fontName, fontExtension)
    local fontPath = MEDIA_ROOT .. "Fonts\\" .. fontName .. "." .. fontExtension
    local name = string.gsub(fontName, "-", " ")
    LSM:Register(MEDIA_TYPE, name, fontPath)
end

do
    for _, font in ipairs(FM.FONTS) do
        RegisterFont(font.name, font.extension)
    end
end
