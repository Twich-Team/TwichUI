-- TwichUI: Reminders, the picture catalog and the three display modes
-- One list of everything a reminder can show as its picture, so the player never has to know which of two systems a picture
-- belongs to: the artwork in media\reminders\ (RM.ART: the four first ones and the library ArtData.lua holds), and the TwichUI icons
-- (R.Icons) a reminder could already show. Game icons (an item's, by its ID or link) are the other source, not a catalog: they are chosen
-- by a number, so the picker has a box for them.
--
-- What is stored does not change (Config.lua's `display`): mode is still one of artworkText, artwork, iconText, icon, text, and art, iconSource,
-- icon and item still hold what they held. This file only reads and writes those through RM.SetDisplay / RM.SetDisplayMany, so every reminder
-- made before it exists keeps exactly the picture and mode it had. The player's three modes are a view of the five stored ones:
--     "imageText"  = artworkText | iconText      "image" = artwork | icon      "text" = text
-- and which of the two kinds a picture is stays in the values the stored mode names (art, or icon / item). Text only keeps the picture's
-- values untouched, so going back to a mode with a picture finds the same picture.
--
-- Pure: no frame, no event. The picker is TwichUI_Settings/pages/RemindersImagePicker.lua.

local R = TwichUI
local RM = R.Reminders
local G = {}
RM.Gallery = G

G.ALL = "All"
G.SOURCE_ART = "TwichUI artwork"
G.SOURCE_GAME = "Game icons"
G.UI_MODES = {
    { "imageText", "Image + text", "A picture with your words beside it." },
    { "image", "Image only", "A picture, nothing else." },
    { "text", "Text only", "Your words, nothing else." },
}

local FAMILY = {
    artworkText = { ui = "imageText", kind = "art" }, artwork = { ui = "image", kind = "art" },
    iconText = { ui = "imageText", kind = "icon" }, icon = { ui = "image", kind = "icon" },
    text = { ui = "text" },
}

---------------------------------------------------------------------------
-- The catalog
---------------------------------------------------------------------------
-- Catalog entries keep the legacy id/kind/target vocabulary for existing editor/runtime callers.
function G.Reset() R.Artwork.Reset() end
function G.Categories() return R.Artwork.Categories() end
function G.Entries() return R.Artwork.Entries() end
function G.Get(id)
    if type(id) ~= "string" then return nil end
    if id:sub(1, 5) == "icon-" then return G.ForIcon(id:sub(6)) end
    return G.ForArt(id)
end
function G.Count(category) return #R.Artwork.Search("", category) end
function G.ForArt(id) return R.Artwork.Get({ kind = "art", id = id }) end
function G.ForIcon(id) return R.Artwork.Get({ kind = "icon", id = id }) end
function G.Search(query, category) return R.Artwork.Search(query, category) end

---------------------------------------------------------------------------
-- The three modes, and what picture a stored display has
---------------------------------------------------------------------------
function G.UIMode(mode)
    local f = FAMILY[mode]
    return f and f.ui or "imageText"
end

-- "art", "icon" or "item": which source the picture of a stored display comes from. In text-only mode the stored values are all that is
-- left to go by: a reminder that has an item chosen, or an icon other than the default with the default artwork, was last an icon.
function G.Source(d)
    local f = FAMILY[d.mode]
    local kind = f and f.kind
    if not kind then
        local default = RM.DISPLAY_DEFAULTS
        if (d.iconSource == "item" and d.item) or (d.icon ~= default.icon and d.art == default.art) then kind = "icon" else kind = "art" end
    end
    if kind == "icon" and d.iconSource == "item" then return "item" end
    return kind
end

-- What a stored display shows as its picture: the catalog entry (nil for a game icon, or artwork this version doesn't have), the source
-- ("art", "icon", "item") and the entry's name and where it comes from, for the details line.
function G.Current(d)
    local source = G.Source(d)
    if source == "art" then
        local e = G.ForArt(d.art)
        return e, source, e and e.name or (RM.Art(d.art) and RM.Art(d.art).label) or "Artwork unavailable", G.SOURCE_ART
    elseif source == "icon" then
        local e = G.ForIcon(d.icon)
        return e, source, e and e.name or "TwichUI icon", G.SOURCE_ART
    end
    return nil, source, d.item and ("Item " .. d.item) or "No item chosen", "Game icon"
end

-- The mode `ui` would be for this display, in the stored vocabulary.
function G.StoredMode(d, ui)
    if ui == "text" then return "text" end
    local art = G.Source(d) == "art"
    if ui == "imageText" then return art and "artworkText" or "iconText" end
    return art and "artwork" or "icon"
end

-- The player's choice of mode. Only the stored mode changes: the words, colour, size and the picture's values stay as they are.
function G.SetUIMode(id, ui)
    local v = RM.Get(id)
    if not v then return false, RM.REFUSE.missing end
    if ui ~= "imageText" and ui ~= "image" and ui ~= "text" then return false, RM.REFUSE.value end
    return RM.SetDisplay(id, "mode", G.StoredMode(v.display, ui))
end

-- A candidate: a catalog entry, or { kind = "item", item = <number> } for a game icon. Valid when it can be applied.
function G.ItemCandidate(item)
    if RM.ValidItem(item) then return { kind = "item", item = item } end
end

function G.SameCandidate(a, b)
    if a == nil or b == nil then return a == b end
    if a.kind ~= b.kind then return false end
    if a.kind == "item" then return a.item == b.item end
    return a.target == b.target
end

-- The candidate a stored display amounts to right now (what the picker starts from).
function G.CandidateOf(d)
    local e, source = G.Current(d)
    if e then return e end
    if source == "item" and d.item then return { kind = "item", item = d.item } end
end

-- Commit a candidate: the mode, the picture and where it comes from, as one change checked as a whole. A reminder that shows only words
-- gets a picture and keeps its words (Image + text if it has words, else Image only).
function G.Choose(id, candidate)
    local v = RM.Get(id)
    if not v then return false, RM.REFUSE.missing end
    if type(candidate) ~= "table" then return false, RM.REFUSE.value end
    local d = v.display
    local ui = G.UIMode(d.mode)
    if ui == "text" then ui = d.text ~= "" and "imageText" or "image" end
    local values = {}
    if candidate.kind == "art" then
        values.art = candidate.target
        values.mode = ui == "imageText" and "artworkText" or "artwork"
    elseif candidate.kind == "icon" then
        values.iconSource, values.icon = "bundled", candidate.target
        values.mode = ui == "imageText" and "iconText" or "icon"
    elseif candidate.kind == "item" then
        values.iconSource, values.item = "item", candidate.item
        values.mode = ui == "imageText" and "iconText" or "icon"
    else
        return false, RM.REFUSE.value
    end
    return RM.SetDisplayMany(id, values)
end
