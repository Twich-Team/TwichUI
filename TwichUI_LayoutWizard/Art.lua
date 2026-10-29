-- TwichUI Layout Setup: the wizard's artwork
-- Nine pictures, made by tools/make_layout_wizard_art.py from the sources in assets/ (docs/layouts/wizard.md says what
-- each source needed and what was not built). The small ones (every square one) are registered with the icon registry (R.Icons), so
-- they are drawn the same way every other TwichUI icon is, including the fallback to TwichUI's own emblem when the game
-- refuses a file. The two larger ones (Classic and Compact Adventure's pictures) are drawn here with the same rule. A
-- picture is only ever decoration: a missing or refused file leaves the words, and the wizard works without it.
--
--   Art.Has(id)            whether a picture is shipped for this id (false for one that is reserved or unknown)
--   Art.Apply(texture, id) draws it; returns true, or false (the texture is hidden) when there is nothing to draw
--   Art.Missing()          the pictures the wizard would like and doesn't have, with why: for the report

local R = TwichUI
local WZ = R.LayoutWizard or {}
R.LayoutWizard = WZ
local Art = {}
WZ.Art = Art

local MEDIA = [[Interface\AddOns\TwichUI_LayoutWizard\media\]]

-- w, h: the file's size in pixels (power of two). icon: the id it has in R.Icons, for the small ones.
Art.FILES = {
    emblem = { file = MEDIA .. "emblem", w = 128, h = 128, icon = "layoutEmblem", what = "the setup emblem: a bound journal and a pocket compass" },
    classic = { file = MEDIA .. "classic", w = 512, h = 256, what = "Classic Adventure: an open journal, a shield and a map" },
    compact = { file = MEDIA .. "compact", w = 512, h = 256, what = "Compact Adventure: a belt pouch with a scroll and a dagger" },
    personalize = { file = MEDIA .. "personalize", w = 128, h = 128, icon = "layoutPersonalize", what = "colour swatches on a ring" },
    screenFit = { file = MEDIA .. "screenfit", w = 128, h = 128, icon = "layoutScreenFit", what = "a framed screen with a width arrow" },
    -- the icon sheet's four pictures (the helper presets and the two tooltip placements)
    keep = { file = MEDIA .. "keep", w = 128, h = 128, icon = "layoutKeep", what = "a closed journal with a ribbon: keep my settings" },
    helpers = { file = MEDIA .. "helpers", w = 128, h = 128, icon = "layoutHelpers", what = "a resource bar, a pin and a cup: on-screen helpers" },
    tipFixed = { file = MEDIA .. "tipfixed", w = 128, h = 128, icon = "layoutTipFixed", what = "a tooltip pinned in a screen's corner: layout position" },
    tipCursor = { file = MEDIA .. "tipcursor", w = 128, h = 128, icon = "layoutTipCursor", what = "a tooltip beside a cursor: follow mouse" },
}

-- Pictures that exist as sources but are not built into the package yet (none since Phase 5 built Compact Adventure's).
Art.RESERVED = {}

-- Registered with the icon registry once (it is shared by every TwichUI window; an id already there is left alone).
for _, e in pairs(Art.FILES) do
    if e.icon and R.Icons and R.Icons.list and R.Icons.list[e.icon] == nil then
        R.Icons.list[e.icon] = { file = e.file, size = e.w, pad = 4, source = "layoutWizard" }
    end
end

function Art.Has(id) return Art.FILES[id] ~= nil end

function Art.Apply(texture, id)
    local e = Art.FILES[id]
    if not e then
        texture:Hide()
        return false
    end
    if e.icon and R.Icons and R.Icons.Get(e.icon) then
        R.Icons.Apply(texture, e.icon, e.w)
        texture:Show()
        return true
    end
    -- SetTexture reports whether the game took the file (Forever's API documentation: `success`)
    local ok = texture:SetTexture(e.file)
    if ok == false then
        texture:Hide()
        return false
    end
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:Show()
    return true
end

function Art.Missing()
    local out = {}
    for id, why in pairs(Art.RESERVED) do out[#out + 1] = { id = id, why = why } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end
