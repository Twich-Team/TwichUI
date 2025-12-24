local T, W, I, C = unpack(Twich)
---@type ToolsModule
local TM = T:GetModule("Tools")

---@class TextTool
TextTool = TM.Text or {}
TM.Text = TextTool

local CreateFrame = CreateFrame
local UIParent = UIParent
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local TEXT_COLOR_TEMPLATE = "|cff%s%s|r"
local TEXTURE_TEMPLATE = "|T%s:16:16|t"
local ICON_TEMPLATE = "|T%s:16:16:0:0:64:64:4:60:4:60|t"
local iconResolutionCache = {}
local iconResolutionFrame = CreateFrame("Frame", "TwichIconResolutionFrame", UIParent, "BackdropTemplate")

--- Normalizes a Hex color by striping the leading '#'
--- @param hex string a hex color value
local function NormalizeHexValue(hex)
    if not hex then return "FFFFFF" end
    if hex:sub(1, 1) == "#" then
        return hex:sub(2)
    end
    return hex
end

--- Colors the provided text with the provided hex color. Default hex colors are provided via ToolsModule.Colors.*.
--- @param hex string a hex color value
--- @param text string the text to color.
--- @return string formattedString the formatted string. If the function was provided nil, an empty string will be returned.
function TextTool.Color(hex, text)
    if not text then return "" end
    if not hex then return text end

    hex = NormalizeHexValue(hex)
    return TEXT_COLOR_TEMPLATE:format(hex, text)
end

--- Colors the provided text with RGB components (0–255 each).
--- Internally converts RGB to a hex string and calls ColorText.
--- @param r integer Red component (0–255).
--- @param g integer Green component (0–255).
--- @param b integer Blue component (0–255).
--- @param text string The text to color.
--- @return string formattedText formatted string. If text is nil, an empty string will be returned.
function TextTool.ColorRGB(r, g, b, text)
    if not text then return "" end
    if not r or not g or not b then return text end

    -- If inputs look like 0–1 floats, scale to 0–255
    if r <= 1 and g <= 1 and b <= 1 then
        r, g, b = r * 255, g * 255, b * 255
    end

    -- clamp to 0–255 to be safe
    if r < 0 then r = 0 elseif r > 255 then r = 255 end
    if g < 0 then g = 0 elseif g > 255 then g = 255 end
    if b < 0 then b = 0 elseif b > 255 then b = 255 end

    local hex = string.format("%02X%02X%02X", r, g, b)
    return TextTool.Color(hex, text)
end

--- Takes an icon to produce a string with the icon in it.
--- @param iconPath string the icon to create a string for.
--- @return string iconStr string containing the icon.
function TextTool.CreateIconStr(iconPath)
    return ICON_TEMPLATE:format(iconPath)
end

--- Given the desired icon path, a fallback icon path, and a label, will determine if the primary icon is avaialble. If not, returns the fallback.
--- @param primaryPath string desired icon to use
--- @param fallbackPath string fallback icon to use
--- @return string resolvedItem the icon found to exist
function TextTool:ResolveIconPath(primaryPath, fallbackPath)
    if iconResolutionCache[primaryPath] then
        return iconResolutionCache[primaryPath]
    end

    -- Create a tiny throwaway texture on a hidden frame; GoblinMenuFrame is fine
    local tex = iconResolutionFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(primaryPath)

    local result = tex:GetTexture() -- nil or resolved texture string/fileID [web:168]
    tex:Hide()

    if result then
        iconResolutionCache[primaryPath] = primaryPath
        return primaryPath
    end

    -- Fallback + warning
    iconResolutionCache[primaryPath] = fallbackPath

    return fallbackPath
end

--- Colors text by class file token (e.g. "MAGE", "PRIEST").
--- @param classFile string the class to color as
--- @param text string the text string to color
--- @return string coloredText the text string that has been colored the class color
function TextTool.ColorByClass(classFile, text)
    local color = (RAID_CLASS_COLORS)[classFile]
    if not color or not text then return text end

    local hex = string.format("%02X%02X%02X", color.r * 255, color.g * 255, color.b * 255)
    return "|cff" .. hex .. text .. "|r"
end

--- Colors text by faction.
--- @param faction string "ALLIANCE" | "HORDE"
--- @param text string the string to color
--- @return string coloredText the text string that has been colored the faction color
function TextTool.ColorByFaction(faction, text)
    if faction:upper() == "ALLIANCE" then
        return TextTool.Color(TM.Colors.WARCRAFT.FACTION.ALLIANCE_BRIGHT, text)
    elseif faction:upper() == "HORDE" then
        return TextTool.Color(TM.Colors.WARCRAFT.FACTION.HORDE_BRIGHT, text)
    end
end

-- Outputs the provided text to the default chat frame
--- @param text string the text to output to the default chat frame
function TextTool.PrintToChatFrame(text)
    DEFAULT_CHAT_FRAME:AddMessage(text, 0.0, 1.0, 0.0)
end
