-- TwichUI Settings: the materials of the settings window (the "style v2" look)
-- Leather and bronze for THIS window only: nothing here changes Look.lua or FrameLook.lua, so the sharing window, the guild bank
-- panel and every other TwichUI window keep the look they have. Each function dresses one thing the settings window already made
-- (its shell, a list, a card, a button) with textures; it never takes the mouse, never reads or writes saved data, and nothing
-- here runs per frame. The files come from assets/style-v2-assets.png (tools/make_style_v2_art.py, media/style-v2/).
--
--   M.Tile(host, layer, sub, which, alpha, tint)   a tiled material texture ("dark" or "warm") over the whole host
--   M.Edge(host, which, size)                      a bronze edge ("window" or "control") on a frame of its own over the host's edge
--   M.Window(win)           the shell: dark leather interior and the thin bronze window frame (instead of the guild-bank rails)
--   M.Band(strip)           the header or footer: a faint chestnut warmth on the leather
--   M.Nav(nav)              the page list: pressed-in leather with a bronze edge
--   M.NavItem(item)         the chosen row's rounded gold-edged face (item.sel) and its hover (item.hover)
--   M.Header(frame, content, shiftY)   a page header: a leather band across the page area with a seam; :Fit(bottom)
--   M.Well(host)            the content well: a dark recessed container with small rounded corners
--   M.Slice(host, kind)     a rounded container drawn from a nine-slice sheet ("recess" or "raised"); M.Grain lays leather over it
--   M.Card(frame, lines)    a raised rounded card: walnut, fine leather, light upper edge, darker lower edge
--   M.SelectedRow(row)      replaces row.sel with a chestnut surface and bronze hairlines (row.sel:SetShown still works)
--   M.Field(editBox)        a recessed input: the leather darkened under the field's own shade
--   M.Face(button, kind)    a leather face under a button's bevel ("secondary" or "primary"; "danger" is left rust)

local R = TwichUI
local Wg = R.SettingsWidgets
local pal = Wg.pal
local M = {}
R.SettingsMaterial = M

local DIR = R.PATH .. [[media\style-v2\]]
local FILE = {
    dark = DIR .. "dark.tga", warm = DIR .. "warm.tga",
    window = DIR .. "window-edge.tga", control = DIR .. "control-edge.tga",
    recess = DIR .. "round-recess.tga", raised = DIR .. "round-raised.tga",   -- rounded nine-slice sheets (tools/make_style_v2_art.py)
}
M.FILE = FILE

-- Texture contribution, tint and base colour are set apart on purpose. The material's own grain is gentle (about +-4 of 255 at full
-- strength), so a surface keeps its character only if the grain is laid at a high alpha with a tint that brings its brightness down
-- to the colour wanted: alpha says how much leather shows, the tint says how bright it is, and the flat colour under it (the base, or a
-- sheet's baked fill) the rest. Loudest grain to quietest: the header and footer, a card, the page list, the window behind the well, a
-- button, a field, the well.
local LEVEL = {
    band = 0.50,                          -- header and footer
    bandWarm = 0.10,
    shell = 0.55, shellTint = 0.75,       -- the window behind the content well: dark espresso
    nav = 0.55, navTint = 0.85,           -- the page list: darker than the window
    well = 0.35, wellTint = 0.60,         -- the content well: near-black, only a trace of grain
    card = 0.60, cardTint = { 0.70, 0.83, 0.96 },   -- a card: walnut, fine leather, the orange taken out of the warm material
    field = 0.50, fieldTint = 0.55,       -- an input: dark and nearly smooth
    face = 0.26, facePrimary = 0.32, faceTint = { 0.80, 0.85, 0.90 },   -- a button's face
    row = 0.20, rowWash = 0.06,           -- the chosen row: a localized warm emphasis by colour, little grain, a thin gold wash
    navRow = 0.30,                        -- the chosen page: grain over its raised face
    navGold = { 0.95, 0.72, 0.35, 0.90 }, -- ... and the antique gold laid over the sheet (ADD): face to chestnut, outline to bronze
    header = 0.50, headerTint = { 0.62, 0.74, 0.86 }, headerBase = { 0.100, 0.076, 0.058 },   -- a page's header: a step warmer than the well
}
M.LEVEL = LEVEL
local CORNER = 6   -- a rounded container's corner, in units (12 texels of its 32 texel sheet)

function M.Tile(host, layer, sub, which, alpha, tint)
    local t = host:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(FILE[which], "REPEAT", "REPEAT")
    t:SetHorizTile(true)
    t:SetVertTile(true)
    t:SetAllPoints(host)
    if type(tint) == "number" then tint = { tint, tint, tint } end
    tint = tint or { 1, 1, 1 }
    t:SetVertexColor(tint[1], tint[2], tint[3], alpha or 1)
    return t
end

-- A frame of its own (a texture cannot draw a backdrop edge) laid over the host (a child frame sits above its parent); it takes no mouse. `size` is the edge's units.
function M.Edge(host, which, size)
    local e = CreateFrame("Frame", nil, host, "BackdropTemplate")
    e:SetAllPoints(host)
    e:SetBackdrop({ edgeFile = FILE[which], edgeSize = size })
    return e
end

-- A rounded container drawn from a nine-slice sheet (`kind`: "recess" or "raised"): four corners at their own size and the edges and
-- middle stretched. The sheet's fill is part of its alpha shape, so no square fill shows at a corner and nothing assumes the colour
-- behind it. `ins` = { left, top, right, bottom } sets it that many units inside the host. Returns the nine textures.
function M.Slice(host, kind, layer, sub, ins)
    local C, u, parts = CORNER, { 0, 12 / 32, 20 / 32, 1 }, {}
    local il, it, ir, ib = 0, 0, 0, 0
    if ins then il, it, ir, ib = ins[1], ins[2], ins[3], ins[4] end
    -- per column: where its left and right edges are, as { side of the host, offset from it }
    local cols = { { { "LEFT", il }, { "LEFT", il + C } }, { { "LEFT", il + C }, { "RIGHT", -(ir + C) } }, { { "RIGHT", -(ir + C) }, { "RIGHT", -ir } } }
    local rows = { { { "TOP", -it }, { "TOP", -(it + C) } }, { { "TOP", -(it + C) }, { "BOTTOM", ib + C } }, { { "BOTTOM", ib + C }, { "BOTTOM", ib } } }
    for r = 1, 3 do
        for c = 1, 3 do
            local t = host:CreateTexture(nil, layer, nil, sub)
            t:SetTexture(FILE[kind])
            t:SetTexCoord(u[c], u[c + 1], u[r], u[r + 1])
            local x1, x2, y1, y2 = cols[c][1], cols[c][2], rows[r][1], rows[r][2]
            t:SetPoint("TOPLEFT", host, y1[1] .. x1[1], x1[2], y1[2])
            t:SetPoint("BOTTOMRIGHT", host, y2[1] .. x2[1], x2[2], y2[2])
            parts[#parts + 1] = t
        end
    end
    return parts
end

-- Grain over a rounded container: three tiled rectangles in a plus shape (the corners' squares are left out), inside its 1 unit line.
-- Grain at a corner's outer square would stand outside the curve, so none is drawn there. `ins` as for Slice.
function M.Grain(host, which, alpha, tint, sub, ins)
    local C = CORNER
    local il, it, ir, ib = 0, 0, 0, 0
    if ins then il, it, ir, ib = ins[1], ins[2], ins[3], ins[4] end
    local parts = {}
    local function Piece(l, t, r, b)
        local g = M.Tile(host, "BACKGROUND", sub or 1, which, alpha, tint)
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT", host, "TOPLEFT", il + l, -(it + t))
        g:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(ir + r), ib + b)
        parts[#parts + 1] = g
    end
    Piece(1, C, 1, C)       -- the middle band, the full width
    Piece(C, 1, C, 0)       -- the top strip and ...
    Piece(C, 0, C, 1)       -- ... the bottom strip, between the corners
    return parts
end

-- Several textures moved as one (a hover fader's SetAlpha, a selection's SetShown).
local function Group(parts)
    local g = {}
    function g.SetAlpha(_, a) for _, p in ipairs(parts) do p:SetAlpha(a) end end
    function g.SetShown(_, v) for _, p in ipairs(parts) do p:SetShown(v) end end
    g.parts = parts
    return g
end

-- The content well: one dark recessed rounded container behind the page area, the cards inside it.
function M.Well(host)
    M.Slice(host, "recess", "BACKGROUND", 0)
    M.Grain(host, "dark", LEVEL.well, LEVEL.wellTint, 1)
end

function M.Window(win)
    local shell = win.shell
    if shell.grain then shell.grain:Hide() end   -- the rock grain gives way to the leather
    M.Tile(shell, "BACKGROUND", -4, "dark", LEVEL.shell, LEVEL.shellTint):SetAllPoints(shell.interior)
    -- the guild bank panel's rails and corners are hidden (alpha, so the shell's own refitting cannot bring them back)
    for _, t in pairs(shell.corner) do t:SetAlpha(0) end
    for _, t in pairs(shell.edge) do t:SetAlpha(0) end
    shell.edgeFrame = M.Edge(shell, "window", 16)
end

function M.Band(strip)
    M.Tile(strip, "BACKGROUND", -4, "dark", LEVEL.band)
    return M.Tile(strip, "BACKGROUND", -3, "warm", LEVEL.bandWarm)
end

function M.Nav(nav)
    nav:SetBackdropColor(0.075, 0.060, 0.048, 1)
    nav:SetBackdropBorderColor(0, 0, 0, 0)
    M.Tile(nav, "BACKGROUND", 1, "dark", LEVEL.nav, LEVEL.navTint)
    -- the window frame stays the strongest line: the list's own edge is held back
    M.Edge(nav, "control", 8):SetBackdropBorderColor(0.72, 0.60, 0.48, 0.55)
end

-- A page-list row: a small rounded raised face for the chosen one, a fainter one under the pointer. The chosen row is the raised sheet
-- (walnut, a light along its upper edge, a darker lower edge) with the same sheet laid again with ADD blending in antique gold: that
-- warms the face to chestnut and lifts the sheet's baked outline to a richer bronze, so one rounded shape carries all of it.
-- item.sel and item.hover are Groups (SetShown / SetAlpha); Window.lua drives them.
local NAV_INSET = { 4, 1, 4, 1 }
function M.NavItem(item)
    local base = M.Slice(item, "raised", "BACKGROUND", 2, NAV_INSET)
    local gold = M.Slice(item, "raised", "BACKGROUND", 3, NAV_INSET)
    for _, t in ipairs(gold) do
        t:SetBlendMode("ADD")
        t:SetVertexColor(LEVEL.navGold[1], LEVEL.navGold[2], LEVEL.navGold[3], LEVEL.navGold[4])
    end
    local grain = M.Grain(item, "warm", LEVEL.navRow, LEVEL.cardTint, 4, NAV_INSET)
    local parts = {}
    for _, set in ipairs({ base, gold, grain }) do for _, p in ipairs(set) do parts[#parts + 1] = p end end
    item.sel = Group(parts)
    item.sel:SetShown(false)
    local soft = M.Slice(item, "raised", "BACKGROUND", 1, NAV_INSET)
    item.hover = Group(soft)
    item.hover:SetAlpha(0)
end

-- The header of a page: a band of leather across the top of the page area (it is part of the scrolling page, so it goes with it),
-- with the two top corners stepped to the well's curve (a 2 unit and a 1 unit inset, the inner radius being 4), and a quiet
-- seam under it. `content` is the scroll child the band spans; `shiftY` how far the page frame sits below its top.
function M.Header(frame, content, shiftY)
    local h = { rects = {} }
    local function Rect(l, top, bottomInFrame)
        local solid = Wg.Solid(frame, "BACKGROUND", LEVEL.headerBase, 1)
        local grain = M.Tile(frame, "BACKGROUND", 1, "warm", LEVEL.header, LEVEL.headerTint)
        for _, t in ipairs({ solid, grain }) do
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", content, "TOPLEFT", l, -top)
        end
        h.rects[#h.rects + 1] = { solid, grain, l = l, top = top, bottom = bottomInFrame }
    end
    Rect(2, 0); Rect(1, 1); Rect(0, 2, true)
    h.dark = Wg.Solid(frame, "ARTWORK", pal.ink, 0.55)
    h.lit = Wg.Solid(frame, "ARTWORK", pal.bronzeHi, 0.16)
    function h:Fit(bottom)   -- bottom: where the band ends, in the page frame's units
        local y = shiftY + bottom
        for i, r in ipairs(self.rects) do
            local stop = (i < #self.rects) and (r.top + 1) or y
            for _, t in ipairs({ r[1], r[2] }) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", content, "TOPLEFT", r.l, -r.top)
                t:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -r.l, -stop)
            end
        end
        self.dark:ClearAllPoints()
        self.dark:SetHeight(1)
        self.dark:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        self.dark:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        self.lit:ClearAllPoints()
        self.lit:SetHeight(1)
        self.lit:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + 1))
        self.lit:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(y + 1))
    end
    return h
end

-- A raised card: a rounded sheet (walnut, a light along its upper edge, a darker lower edge, a restrained bronze outline) with fine
-- leather over it. `lines` is what Wg.Panel returned (its square inner shade lines, which would show at a rounded corner): they are put away,
-- and so are the frame's own square fill and border.
function M.Card(frame, lines)
    for _, t in pairs(lines or {}) do t:Hide() end
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    M.Slice(frame, "raised", "BACKGROUND", 0)
    M.Grain(frame, "warm", LEVEL.card, LEVEL.cardTint, 1)
end

function M.SelectedRow(row)
    local base = Wg.Solid(row, "BACKGROUND", { 0.27, 0.18, 0.10 }, 0.62)   -- chestnut by colour
    base:SetAllPoints()
    local tile = M.Tile(row, "BACKGROUND", 2, "warm", LEVEL.row)
    local wash = row:CreateTexture(nil, "BACKGROUND", nil, 3)   -- a gold wash fading to the right
    wash:SetAllPoints()
    Wg.Fade(wash, pal.teal, LEVEL.rowWash, 0, "HORIZONTAL")
    local top = Wg.Solid(row, "BACKGROUND", pal.tealHi, 0.20)   -- the lit and the shaded edge of the chosen row
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", 0, 0)
    local low = Wg.Solid(row, "BACKGROUND", pal.ink, 0.55)
    low:SetHeight(1)
    low:SetPoint("BOTTOMLEFT", 0, 0)
    low:SetPoint("BOTTOMRIGHT", 0, 0)
    local parts = { base, tile, wash, top, low }
    for _, p in ipairs(parts) do p:Hide() end
    row.sel = {
        SetShown = function(_, shown) for _, p in ipairs(parts) do p:SetShown(shown) end end,
        Show = function() for _, p in ipairs(parts) do p:Show() end end,
        Hide = function() for _, p in ipairs(parts) do p:Hide() end end,
    }
end

function M.Field(eb)
    M.Tile(eb, "ARTWORK", -2, "dark", LEVEL.field, LEVEL.fieldTint)
end

function M.Face(b, kind)
    if kind == "danger" then return end   -- Delete and Reset stay plain rust: no material may soften what they do
    local primary = kind == "primary"
    local t = M.Tile(b, "ARTWORK", -1, "warm", primary and LEVEL.facePrimary or LEVEL.face, LEVEL.faceTint)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", 1, -1)
    t:SetPoint("BOTTOMRIGHT", -1, 1)
    b.twichMaterial = t
    -- unavailable: the leather goes quiet with the face
    b:HookScript("OnDisable", function() t:SetAlpha(0.12) end)
    b:HookScript("OnEnable", function() t:SetAlpha(1) end)
    if not b:IsEnabled() then t:SetAlpha(0.12) end
end
