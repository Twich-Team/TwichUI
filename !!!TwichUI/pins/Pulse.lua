-- TwichUI: the soft expanding rings of a map ping, for anything that wants to pick out a spot on the world map
-- Only the look: a frame gets two pairs of textures (a dark ring under a bright one, so the ring reads on a pale map and
-- on a dark one), and Step sets their size and fade for a moment in the pulse's life. Nothing here sends, plays a sound,
-- keeps time or listens: the caller owns the frame, the clock and the driver. Map pings (pins/PingMap.lua) and the NPC
-- search's highlight (npcs/Map.lua) draw their rings through it, so the two look the same.

local R = TwichUI
local MP = {}
R.MapPulse = MP

MP.TEXTURE = [[Interface\minimap\UI-Minimap-Ping-Expand]]   -- the game's own, as MapPinPingTemplate uses it
MP.FROM, MP.TO = 26, 104                                    -- the ring's diameter at the start and at the end
MP.TIME, MP.STAGGER = 1.2, 0.4                              -- one ring's life, and how long after the last one the next starts
local FROM, TO, TIME, STAGGER = MP.FROM, MP.TO, MP.TIME, MP.STAGGER

-- Adds `count` ring pairs to a frame. Returns them: { { dark, ring, shown }, ... }.
function MP.AddRings(f, count)
    local rings = {}
    for i = 1, count do
        local dark = f:CreateTexture(nil, "ARTWORK", nil, 0)
        dark:SetTexture(MP.TEXTURE)
        dark:SetVertexColor(0.05, 0.03, 0.02, 1)
        dark:SetPoint("CENTER")
        local ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
        ring:SetTexture(MP.TEXTURE)
        ring:SetVertexColor(0.96, 0.80, 0.38, 1)
        ring:SetPoint("CENTER")
        rings[i] = { dark = dark, ring = ring }
    end
    return rings
end

function MP.Hide(rings)
    for _, r in ipairs(rings) do
        r.ring:Hide(); r.dark:Hide(); r.shown = false
    end
end

-- One step. t: seconds into the pulse; ringsEnd: when the rings stop (the pulse fades after it). reduced: no motion; with
-- `still` the first ring stays as one fixed outline until ringsEnd (so a pulse that is the only sign of a place is still
-- there to see), without it no ring is drawn at all (a ping has a marker of its own).
function MP.Step(rings, t, ringsEnd, reduced, still)
    for i, r in ipairs(rings) do
        local rt = t - (i - 1) * STAGGER
        if reduced and still and i == 1 and t <= ringsEnd then
            local d = FROM + (TO - FROM) * 0.45
            r.ring:SetSize(d, d); r.ring:SetAlpha(0.9)
            r.dark:SetSize(d + 6, d + 6); r.dark:SetAlpha(0.65)
            if not r.shown then r.ring:Show(); r.dark:Show(); r.shown = true end
        elseif reduced or rt < 0 or t > ringsEnd then
            if r.shown then r.ring:Hide(); r.dark:Hide(); r.shown = false end
        else
            local phase = (rt % TIME) / TIME
            local grow = 1 - (1 - phase) * (1 - phase)
            local d = FROM + (TO - FROM) * grow
            local a = (1 - phase) ^ 1.4
            r.ring:SetSize(d, d); r.ring:SetAlpha(a * 0.95)
            r.dark:SetSize(d + 6, d + 6); r.dark:SetAlpha(a * 0.7)
            if not r.shown then r.ring:Show(); r.dark:Show(); r.shown = true end
        end
    end
end
