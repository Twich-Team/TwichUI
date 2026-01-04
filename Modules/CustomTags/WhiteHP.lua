-- ElvUI_WhiteFullHealthTag.lua
-- Add a custom ElvUI tag: [hp:whitefull]
-- 100% HP  => white text
-- <100% HP => standard ElvUI healthcolor text

local E = _G.ElvUI
if not E or not E.oUF or not E.AddTag then return end

local oUF = E.oUF

-- Tag method
oUF.Tags.Methods["hp:whitefull"] = function(unit)
    if not unit or not UnitExists(unit) then
        return ""
    end

    local cur = UnitHealth(unit)
    local max = UnitHealthMax(unit)
    if max == 0 then
        return ""
    end

    local perc = (cur / max) * 100

    -- Use ElvUI's health text formatting for the value itself
    -- You can change this line if you want different formatting
    local value = E:GetFormattedText("PERCENT", cur, max) -- e.g. "73%"
    -- If you want raw percent without sign, use:
    -- local value = tostring(E:Round(perc))

    if perc >= 100 then
        -- White at full HP
        return "|cFFFFFFFF" .. value .. "|r"
    else
        -- Use ElvUI health color for anything below full
        local r, g, b = E:ColorGradient(perc / 100, 1, 0, 0, 1, 1, 0, 0, 1, 0) -- red→yellow→green
        if not r then
            r, g, b = 1, 1, 1
        end
        return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, value)
    end
end

-- Tag events
oUF.Tags.Events["hp:whitefull"] = "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION PLAYER_TARGET_CHANGED GROUP_ROSTER_UPDATE"
