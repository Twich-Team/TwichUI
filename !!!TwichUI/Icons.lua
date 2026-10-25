-- TwichUI: feature icons
-- One registry of the small pictures TwichUI's own windows put beside a feature's name (the settings window's
-- list, its feature cards and its Home page). An icon is artwork only: it never decides anything about a feature,
-- and a label is always shown beside it. Nothing here makes a texture until a window asks for one.
--
--   Icons.Get(id)                         the entry, or nil: { file, small, coords, tint, size, pad, source }
--   Icons.Path(id, size)                  the texture path for an icon shown `size` UI units square (the 32 px file
--                                         at about 26 and under, where it has one), or the fallback's
--   Icons.Apply(texture, id, size)        sets a texture to it (coordinates and tint too); falls back to the addon's
--                                         emblem when the id is unknown or the game refuses the file. Returns the
--                                         id drawn ("fallback" when it fell back).
--
-- Every icon comes from one of three sheets (assets/settings-icons-source.png, -2- and -3-source.png),
-- cut and cleaned by tools/make_settings_icons.py into media/icons/<id>.tga (64 px, for cards and Home) and
-- <id>-small.tga (32 px, for list rows). docs/settings-icons.md lists every one and what it is for.

local R = TwichUI
local Icons = {}
R.Icons = Icons

local ICONS = R.PATH .. [[media\icons\]]

-- The addon's own emblem: shipped with TwichUI and drawn by every TwichUI window's header, so it is there
-- whenever an icon file isn't.
Icons.FALLBACK = R.ICON

-- Shown at or under this many UI units, a sheet icon uses its 32 px file (the game isn't relied on to make
-- smaller copies of an addon's texture when it draws it small).
Icons.SMALL_AT = 26

-- size: the logical size the artwork was cut for (its longer side fills `size - 2 * pad` of the square file).
local function Sheet(id)
    return { file = ICONS .. id, small = ICONS .. id .. "-small", size = 64, pad = 3, source = "sheet" }
end

local list = {
    -- the first sheet, row by row
    home = Sheet("home"),                         -- a cottage
    notifications = Sheet("notifications"),       -- a bell
    qualityOfLife = Sheet("qualityOfLife"),       -- a feather and a cog
    markers = Sheet("markers"),                   -- a pennant
    chatCleaning = Sheet("chatCleaning"),         -- a speech bubble and a brush
    foodAndDrink = Sheet("foodAndDrink"),         -- bread and a cup
    hazardAlerts = Sheet("hazardAlerts"),         -- a warning shield
    vendorRestocking = Sheet("vendorRestocking"), -- a supply pouch with vials
    auctionHouse = Sheet("auctionHouse"),         -- merchant's scales and a coin
    journeyChronicle = Sheet("journeyChronicle"), -- an open journal with a ribbon
    sleepingBag = Sheet("sleepingBag"),           -- a rolled bedroll
    mapsNavigation = Sheet("mapsNavigation"),     -- a folded map and a location pin
    gearComparison = Sheet("gearComparison"),     -- a breastplate and an arrow
    classResources = Sheet("classResources"),     -- three resource crystals
    addonSkins = Sheet("addonSkins"),             -- a paintbrush and a frame corner
    profilesSharing = Sheet("profilesSharing"),   -- two portrait medallions
    -- the second sheet (assets/settings-icons-2-source.png)
    targetArt = Sheet("targetArt"),               -- a dragon head in a bronze corner frame
    mapPins = Sheet("mapPins"),                   -- a red map pin with teal ripple rings
    mapToolbar = Sheet("mapToolbar"),             -- a parchment map with a brass compass
    vendors = Sheet("vendors"),                   -- a merchant stall with a striped awning
    mage = Sheet("mage"),                         -- an arcane staff with a glowing blue orb
    guide = Sheet("guide"),                       -- a blue guidebook with a route arrow
    ammunition = Sheet("ammunition"),             -- a leather quiver of arrows
    troubleshooting = Sheet("troubleshooting"),   -- a magnifying glass over a scroll with a cog
    navigation = Sheet("navigation"),             -- an antique-gold compass rose
    profiles = Sheet("profiles"),                 -- one bronze portrait medallion with a red ribbon
    explore = Sheet("explore"),                   -- a brass spyglass (Home)
    appearance = Sheet("appearance"),             -- a painter's palette and brush (Home)
    reviewChanges = Sheet("reviewChanges"),       -- a ledger with a gold checkmark and quill (Home)
    summons = Sheet("summons"),                   -- a stone portal (Quality of life)
    resurrection = Sheet("resurrection"),         -- angelic wings around a gold ankh (Quality of life)
    releaseSpirit = Sheet("releaseSpirit"),       -- crossed battleground banners and a wisp (Quality of life)
    -- the third sheet (assets/settings-icons-3-source.png: an opaque background, removed by the tool)
    declineDuels = Sheet("declineDuels"),         -- crossed swords behind a red prohibition seal (Quality of life)
    quickKeybind = Sheet("quickKeybind"),         -- a gold key on a dark keyboard key (Quality of life)
}
Icons.list = list

function Icons.Get(id)
    return id and list[id] or nil
end

function Icons.Path(id, size)
    local e = Icons.Get(id)
    if not e then return Icons.FALLBACK end
    if e.small and size and size <= Icons.SMALL_AT then return e.small end
    return e.file
end

-- Sets texture to icon `id` shown `size` units square. The texture's size and points are the caller's.
function Icons.Apply(texture, id, size)
    local e = Icons.Get(id)
    local drawn = e and id or "fallback"
    local ok = texture:SetTexture(Icons.Path(id, size))
    -- SetTexture reports whether the game took the file (Forever's API documentation: `success`); a refused
    -- file falls back to the emblem rather than leaving an empty or green square beside the label
    if e and ok == false then
        texture:SetTexture(Icons.FALLBACK)
        drawn, e = "fallback", nil
    end
    if e and e.coords then texture:SetTexCoord(unpack(e.coords)) else texture:SetTexCoord(0, 1, 0, 1) end
    local tint = e and e.tint
    if tint then texture:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1) else texture:SetVertexColor(1, 1, 1, 1) end
    return drawn
end
