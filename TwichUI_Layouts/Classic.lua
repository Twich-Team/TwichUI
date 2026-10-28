-- TwichUI Layouts: the Adventure package, with its two layouts, Classic Adventure and Compact Adventure (format 3)
-- (The file keeps its Phase 3 name; the package, `twichui-adventure`, has held both layouts since Phase 5.)
-- The data is the author's own, captured by tools/layout_capture.lua: Classic into ClassicData.lua (LY.CLASSIC_CAPTURE,
-- docs/layouts/capture-classic-adventure.md) and Compact into CompactData.lua (LY.COMPACT_CAPTURE,
-- docs/layouts/capture-compact-adventure.md), which says where it came from, what was kept and what was left out.
--
-- Layers. Shared suite base: the look (EllesmereUI's fonts, accent, dark-mode palette and migration stamps; TwichUI's
-- looks and behaviour settings that differ from TwichUI's defaults), every EllesmereUI module the two layouts hold
-- identically (Compact's capture lists them, with a fingerprint of each, so each is kept once) and where TwichUI's own
-- HUD pieces sit. Each variant: the modules and layout links that differ. Promoting a setting from a variant to the
-- base, or demoting one, is moving the module between the two tables below; nothing else changes.
--
-- Choices (what the wizard asks; docs/layouts/wizard.md): a TwichUI helpers preset (only turns switches on), the accent
-- colour (EllesmereUI's `euiAccent`, nothing else of its look) and the size (the geometry's density). Each names
-- exactly what it writes; the package checks refuse anything else.
--
-- Geometry. The author made this on a 3440 × 1440 screen at UI scale 0.64: UIParent is 2866.67 × 1200 units (the
-- canvas), which the stored positions confirm (the minimap's and the meter's links to the right edge both give it).
-- Each component below is a box on that canvas, measured from the captured positions and sizes, and an anchor that
-- says what it keeps its distance to. On another screen the resolver (Geometry.lua) places the boxes and every
-- attached position moves with its box. The rules are the author's to adjust: they are a reading of the layout, not
-- part of it.
--   central       the player, target and pet frames, the main bars, cooldowns and cast bars: one block that keeps
--                 its distance from the bottom centre and never resizes (x ±445: the unit frames and bars)
--   focus         the focus frame and its cast bar, to the right of the block, moving with it
--   chat          bottom left; scales with the density; gives up width (down to 280) rather than run into the block
--   meter         bottom right, the same; below the narrow width it moves under the minimap
--   minimap       top right; scales with the density
--   objectives    under the minimap, short of the focus frame. EllesmereUI leaves the objective tracker to Blizzard's Edit
--                 Mode, which layouts do not manage yet (D15): its place is worked out and shown, never applied
--   notifications TwichUI's training and welcome-back cards: top centre, kept clear above the block
--   top-edge, top-left  where things on the top edge and in the top-left corner keep their distance from

local LY = TwichUI.Layouts
local C = LY.CLASSIC_CAPTURE

local W, H = 2866.67, 1200            -- the canvas
local L, B, T = -W / 2, -H / 2, H / 2

local CENTRAL = { "bar-main", "bar-2", "bar-4", "bar-5", "bar-stance", "bar-pet", "uf-player", "uf-target", "uf-pet",
    "uf-targettarget", "uf-focustarget", "uf-class-power", "uf-player-cast", "uf-target-cast", "cdm-cooldowns",
    "cdm-buffs", "cdm-utility", "cdm-group-3", "rb-cast", "rb-swing", "combat-text" }
local euiAttach = {
    minimap = "minimap", chat = "chat", meter = "meter",
    ["chat-toast"] = "chat:TOPLEFT", ["bar-3"] = "chat:BOTTOMRIGHT", ["bar-xp"] = "chat:BOTTOMLEFT",
    ["uf-focus"] = "focus", ["uf-focus-cast"] = "focus",
    ["uf-buffs"] = "minimap:TOPLEFT", ["uf-debuffs"] = "minimap:LEFT", ["queue-status"] = "minimap:BOTTOMLEFT",
    ["databar-location"] = "minimap:BOTTOM",
    ["extra-button"] = "top-left", ["bar-rep"] = "top-left",
    ["databar-top"] = "top-edge", ["uf-boss"] = "top-edge",
}
for _, id in ipairs(CENTRAL) do euiAttach[id] = "central" end

local K = LY.COMPACT_CAPTURE
local EC, EK = C.ellesmereui, K.ellesmereui

-- The modules both captures hold identically are kept once, in the base; the rest belong to a variant.
local sharedModules, classicModules = {}, {}
for m, blob in pairs(EC.modules) do
    if K.sameAs.modules[m] then sharedModules[m] = blob else classicModules[m] = blob end
end

LY.CLASSIC_VARIANT = "classic-adventure"
LY.COMPACT_VARIANT = "compact-adventure"
LY.CLASSIC_PACKAGE = {
    -- format 4 only when the capture holds a reset (tools/layout_capture.lua --returned reset): an older TwichUI then refuses
    -- the package as newer instead of misreading it; without one the package stays readable by format 3
    format = C.twichui.reset and 4 or 3, id = "twichui-adventure", revision = 3,
    -- a developer package until it has been installed and checked on WoW: Forever (Phase 7): the capture is from the
    -- Retail client's saved files, and a developer package may be tried on Retail (architecture.md §3)
    dev = true,
    title = "TwichUI Adventure", made = C.source.made,
    source = "Captured from the author's Retail EllesmereUI " .. tostring(C.source.ellesmereui.version) .. " profiles",
    requires = { ellesmereui = { min = "9.6.6", tested = "9.6.8" } },
    -- one pair of profiles for the package: switching layouts is an install again into them (architecture.md §3)
    targets = { twichui = "TwichUI Adventure", ellesmereui = "TwichUI Adventure" },
    layers = {
        base = {
            ellesmereui = { root = EC.root, modules = sharedModules },
            twichui = { groups = C.twichui.groups, places = C.twichui.places, reset = C.twichui.reset },
        },
        variants = {
            ["classic-adventure"] = { ellesmereui = { modules = classicModules, layout = EC.layout } },
            ["compact-adventure"] = { ellesmereui = { modules = EK.modules, layout = EK.layout } },
        },
    },
    choices = {
        { id = "helpers", kind = "preset", label = "TwichUI helpers", default = "as-is",
            hint = "Which of TwichUI's own features the setup turns on. It only turns things on, never off. None of them shares anything, plays a sound or acts for you.",
            options = {
                { id = "as-is", label = "Leave them as they are",
                    hint = "No TwichUI feature is turned on or off. The layout still styles and places the ones you already use." },
                { id = "on-screen", label = "On-screen helpers",
                    hint = "Turns on the class resource bars, the marker bar and the food and drink buttons, in the places the layout leaves for them.",
                    twichui = { groups = { classBars = { modules = { classBars = true } }, markerBar = { modules = { markersBar = true } },
                        food = { modules = { foodDrink = true } } } } },
                { id = "finding-my-way", label = "Helpers and navigation",
                    hint = "The same, and Navigation: a walking arrow to a place you pick. Its map data loads the first time you ask for a route.",
                    twichui = { groups = { classBars = { modules = { classBars = true } }, markerBar = { modules = { markersBar = true } },
                        food = { modules = { foodDrink = true } }, navigation = { modules = { navigation = true } } } } },
            } },
        { id = "accent", kind = "enum", label = "Accent colour", default = "gold", sets = { "ellesmereui:root.euiAccent" },
            hint = "The colour EllesmereUI uses for highlights. Nothing else is recoloured.",
            options = {
                { id = "gold", label = "Aged gold", hint = "The layout's own.", swatch = { C.ellesmereui.root.euiAccent.custom.r, C.ellesmereui.root.euiAccent.custom.g, C.ellesmereui.root.euiAccent.custom.b },
                    ellesmereui = { root = { euiAccent = C.ellesmereui.root.euiAccent } } },
                { id = "class", label = "Your class colour", hint = "Follows the character you play.",
                    ellesmereui = { root = { euiAccent = { useClass = true } } } },
                { id = "verdigris", label = "Verdigris", swatch = { 0.36, 0.58, 0.57 },
                    ellesmereui = { root = { euiAccent = { useClass = false, custom = { r = 0.36, g = 0.58, b = 0.57 } } } } },
                { id = "ember", label = "Ember", swatch = { 0.80, 0.45, 0.30 },
                    ellesmereui = { root = { euiAccent = { useClass = false, custom = { r = 0.80, g = 0.45, b = 0.30 } } } } },
                { id = "dusk", label = "Dusk blue", swatch = { 0.47, 0.60, 0.80 },
                    ellesmereui = { root = { euiAccent = { useClass = false, custom = { r = 0.47, g = 0.60, b = 0.80 } } } } },
            } },
        { id = "size", kind = "density", label = "Size", default = "standard",
            hint = "How large chat, the damage meter and the minimap are drawn, and the text in chat and the meter. Positions follow.",
            options = {
                { id = "standard", label = "Standard", hint = "The size the layout was made at.", density = "standard" },
                { id = "larger", label = "Larger", hint = "About 15 percent bigger where there is room. Nothing is made smaller than is readable.", density = "larger" },
            } },
    },
    geometry = {
        canvas = { w = W, h = H, note = "3440 x 1440 at UI scale 0.64" },
        margin = 0,                         -- the author's minimap sits 2.5 units from the edge: a margin would move it
        area = { maxAspect = 2.4 },         -- the author's 21:9 screen is the composition area; only wider screens get a narrower one
        densities = { standard = 1, larger = 1.15 },
        narrow = 1700,
        components = {
            central = { label = "Unit frames and action bars", managed = true,
                ref = { x = 0, y = -337.5, w = 890, h = 525 },
                anchor = { point = "BOTTOM", to = "area", rel = "BOTTOM" } },
            focus = { label = "Focus frame", managed = true,
                ref = { x = 588.33, y = -240.2, w = 225, h = 59 },
                anchor = { point = "CENTER", to = "central", rel = "BOTTOM" } },
            chat = { label = "Chat", managed = true, density = true,
                ref = { x = L + 49.08 + 451 / 2, y = B + 62.42 + 186 / 2, w = 451, h = 186 },
                anchor = { point = "BOTTOMLEFT", to = "area", rel = "BOTTOMLEFT" },
                min = { w = 280, h = 120 }, max = { w = 640, h = 320 },
                room = { side = "right", of = "central", gap = 12 } },
            meter = { label = "Damage meter", managed = true, density = true,
                ref = { x = 1233.33, y = -504.17, w = 375, h = 150 },
                anchor = { point = "BOTTOMRIGHT", to = "area", rel = "BOTTOMRIGHT" },
                min = { w = 240, h = 100 }, max = { w = 560, h = 300 },
                room = { side = "left", of = "central", gap = 12 },
                narrow = { anchor = { point = "TOPRIGHT", to = "minimap", rel = "BOTTOMRIGHT", x = 0, y = -40 },
                    room = { side = "left", of = "focus", gap = 12 } } },
            minimap = { label = "Minimap", managed = true, density = true,
                ref = { x = 1330.83, y = 473.33, w = 200, h = 200 },
                anchor = { point = "TOPRIGHT", to = "area", rel = "TOPRIGHT" },
                min = { w = 140, h = 140 }, max = { w = 280, h = 280 } },
            objectives = { label = "Objectives", managed = true, applied = "edit-mode",
                size = { w = 280, h = 420 },
                anchor = { point = "TOPRIGHT", to = "minimap", rel = "BOTTOMRIGHT", x = 0, y = -56 },
                min = { w = 200, h = 160 },
                room = { side = "down", of = "focus", gap = 12 },   -- on narrower screens the focus frame comes under it first
                narrow = { anchor = { point = "TOPRIGHT", to = "meter", rel = "BOTTOMRIGHT", x = 0, y = -12 },
                    room = { side = "down", of = "focus", gap = 12 } } },
            notifications = { label = "TwichUI cards", managed = true,
                ref = { x = 0, y = T - 260 - 48, w = 520, h = 96 },
                anchor = { point = "TOP", to = "area", rel = "TOP" },
                above = { of = "central", gap = 12 } },
            ["top-edge"] = { ref = { x = 0, y = T, w = 0, h = 0 }, anchor = { point = "TOP", to = "area", rel = "TOP" } },
            ["top-left"] = { ref = { x = L, y = T, w = 0, h = 0 }, anchor = { point = "TOPLEFT", to = "area", rel = "TOPLEFT" } },
        },
        attach = {
            ellesmereui = euiAttach,
            twichui = { ["class-bars"] = "central", ["marker-bar"] = "central", ["nav-arrow"] = "central",
                ["food-drink"] = "chat:TOPRIGHT", ["healer-watch"] = "chat:TOPLEFT",
                ["training-card"] = "notifications", ["welcome-back"] = "notifications" },
        },
        -- What Compact Adventure does differently; everything else (chat, meter, minimap, objectives, the cards, the
        -- focus frame, densities, the narrow width) is Classic's. Its unit frames and action bars are one low, wide block
        -- along the bottom edge. The managed box is the core of it, measured from the captured positions and sizes: the
        -- left-hand bar's first button to the right-hand bar's last (1091 wide), and from the target-of-target's top to
        -- the screen edge (157.5 high). The pet frame and bar and the stance bar sit to its left, low and only for the
        -- classes that have them: they follow the block (and are drawn in the preview) but are not part of the box, which
        -- would otherwise push Chat down to its smallest on every 16:9 screen. A damage-meter bar sits on top of the
        -- meter, and the raid and party frames sit in from the left edge.
        variants = {
            ["compact-adventure"] = {
                components = {
                    central = { label = "Unit frames and action bars", managed = true,
                        ref = { x = -0.4, y = -521.25, w = 1091, h = 157.5 },
                        anchor = { point = "BOTTOM", to = "area", rel = "BOTTOM" } },
                    ["left-edge"] = { ref = { x = L, y = 0, w = 0, h = 0 }, anchor = { point = "LEFT", to = "area", rel = "LEFT" } },
                },
                attach = {
                    ellesmereui = { ["bar-6"] = "central", ["bar-7"] = "meter:TOP",
                        ["raid-frames"] = "left-edge", ["party-frames"] = "left-edge" },
                },
            },
        },
    },
}
-- Compact's chat is Classic's, and below its narrow width it sits above the low block instead of beside it (the block
-- is 1091 wide and Chat needs 280 beside it, so beside it stops fitting under about 1780 units; Classic's narrow
-- arrangement is for 1700). Built from Classic's own chat so the two cannot drift apart.
do
    local geo = LY.CLASSIC_PACKAGE.geometry
    local chat = {}
    for k, v in pairs(geo.components.chat) do chat[k] = v end
    chat.narrow = { anchor = { point = "BOTTOMLEFT", to = "area", rel = "BOTTOMLEFT", x = 49.08, y = 157.5 + 12 } }
    geo.variants["compact-adventure"].components.chat = chat
    geo.variants["compact-adventure"].narrow = 1780
end
LY.ADVENTURE_PACKAGE = LY.CLASSIC_PACKAGE   -- the same package, by the name that says it holds both layouts
