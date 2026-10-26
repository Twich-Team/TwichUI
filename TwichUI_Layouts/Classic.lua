-- TwichUI Layouts: Classic Adventure, the first author layout (package format 2)
-- The data is the author's own, captured by tools/layout_capture.lua into ClassicData.lua (LY.CLASSIC_CAPTURE):
-- docs/layouts/capture-classic-adventure.md says where it came from, what was kept and what was left out.
--
-- Layers. Shared suite base: the look (EllesmereUI's fonts, accent, dark-mode palette and migration stamps; TwichUI's
-- looks and behaviour settings that differ from TwichUI's defaults). Classic Adventure: every EllesmereUI module, its
-- layout links, and where TwichUI's own HUD pieces sit. Compact Adventure is not built yet; when it is, it gets its
-- own variant and the base stays shared.
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

LY.CLASSIC_VARIANT = "classic-adventure"
LY.CLASSIC_PACKAGE = {
    format = 2, id = "twichui-adventure", revision = 1,
    -- a developer package until it has been installed and checked on WoW: Forever (Phase 7): the capture is from the
    -- Retail client's saved files, and a developer package may be tried on Retail (architecture.md §11.13)
    dev = true,
    title = "TwichUI Adventure", made = C.source.made,
    source = "Captured from the author's Retail EllesmereUI " .. tostring(C.source.ellesmereui.version) .. " profile",
    requires = { ellesmereui = { min = "9.6.6", tested = "9.6.8" } },
    targets = { twichui = "Classic Adventure", ellesmereui = "TwichUI Classic" },
    layers = {
        base = {
            ellesmereui = { root = C.ellesmereui.root },
            twichui = { groups = C.twichui.groups },
        },
        variants = {
            ["classic-adventure"] = {
                ellesmereui = { modules = C.ellesmereui.modules, layout = C.ellesmereui.layout },
                twichui = { places = C.twichui.places },
            },
        },
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
    },
}
