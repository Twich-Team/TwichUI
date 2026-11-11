-- TwichUI Settings: the materials of the settings window (the "style v2" look)
-- Leather and bronze for THIS window only: nothing here changes Look.lua or FrameLook.lua, so the sharing window, the guild bank
-- panel and every other TwichUI window keep the look they have. Each function dresses one thing the settings window already made
-- (its shell, a list, a card, a button) with textures; it never takes the mouse, never reads or writes saved data, and nothing
-- here runs per frame. Original style-v2 files are preserved; opt-in quiet materials are derived by tools/make_reminder_materials.py.
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
local QUIET_DIR = R.PATH .. [[media\reminders\materials\]]
for _, role in ipairs({ "outer", "header", "editor", "card", "recess", "button", "selected", "primary", "viewport", "chip" }) do
    FILE["quiet-" .. role] = QUIET_DIR .. "face-" .. role .. ".tga"
    FILE["grain-" .. role] = QUIET_DIR .. "grain-" .. role .. ".tga"
end
FILE.controlRim = QUIET_DIR .. "control-rim.tga"
FILE.frameRim = QUIET_DIR .. "frame-rim.tga"
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
function M.Slice(host, kind, layer, sub, ins, radius)
    local C, u, parts = radius or CORNER, { 0, 12 / 32, 20 / 32, 1 }, {}
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
function M.Grain(host, which, alpha, tint, sub, ins, layer)
    local C = CORNER
    local il, it, ir, ib = 0, 0, 0, 0
    if ins then il, it, ir, ib = ins[1], ins[2], ins[3], ins[4] end
    local parts = {}
    local function Piece(l, t, r, b)
        local g = M.Tile(host, layer or "BACKGROUND", sub or 1, which, alpha, tint)
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

-- Hollow nine-slice rims add relief without repainting the material or changing input geometry.
function M.Rim(host, frame, corner, ins)
    return R.SettingsCraft.Sheet(host, frame and "frame" or "inset-rim",
        { layer = "OVERLAY", sub = 3, corner = corner or (frame and 24 or 8), inset = ins or 0 })
end

-- The content well: one dark recessed rounded container behind the page area, the cards inside it.
function M.Well(host)
    M.Slice(host, "recess", "BACKGROUND", 0)
    M.Grain(host, "dark", 0.50, { 0.91, 0.96, 1.00 }, 1)
end

function M.Window(win)
    local shell = win.shell
    if shell.grain then shell.grain:Hide() end   -- the rock grain gives way to the leather
    M.Tile(shell, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 }):SetAllPoints(shell.interior)
end

function M.Band(strip)
    M.Tile(strip, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 })
    return M.Tile(strip, "BACKGROUND", -3, "warm", 0.04, LEVEL.cardTint)
end

function M.Nav(nav)
    nav:SetBackdropColor(0.075, 0.060, 0.048, 1)
    nav:SetBackdropBorderColor(0, 0, 0, 0)
    M.Tile(nav, "BACKGROUND", 1, "dark", 1, { 0.90, 0.94, 0.98 })
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
function M.Header(frame, content, shiftY, material)
    local h = { rects = {} }
    local function Rect(l, top, bottomInFrame)
        local solid = Wg.Solid(frame, "BACKGROUND", LEVEL.headerBase, material and 0 or 1)
        local grain = M.Tile(frame, "BACKGROUND", 1, material and "grain-header" or "warm",
            material and 1 or LEVEL.header, material and { 1, 1, 1 } or LEVEL.headerTint)
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

-- Opt-in Reminders companions retain the illustrated frame, with quiet leather and a shallow inner rim.
-- Nothing about other FrameLook consumers changes.
function M.Companion(frame, neutral)
    return M.WorkspaceFrame(frame)
end

-- These materials are opt-in; original style-v2 files and unrelated consumers are untouched.
function M.QuietTile(host, role, layer, sub)
    return M.Tile(host, layer or "BACKGROUND", sub or 0, "grain-" .. role, 1)
end

function M.HeaderBand(frame, height)
    local band = M.QuietTile(frame, "header", "BACKGROUND", -5)
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", 9, -9)
    band:SetPoint("TOPRIGHT", -9, -9)
    band:SetHeight(height - 9)
    local seam = Wg.Solid(frame, "BORDER", { 0.29, 0.23, 0.16 }, 0.50)
    seam:SetHeight(1)
    seam:SetPoint("TOPLEFT", 12, -height)
    seam:SetPoint("TOPRIGHT", -12, -height)
end

function M.CalibrateSettings(win, on)
    if not win or not win.materialHosts then return end
    win.craftActive = on and true or false
    if not win.quietMaterials and on then
        win.quietMaterials = {}
        for _, entry in ipairs(win.materialHosts) do
            local tile = M.QuietTile(entry[1], entry[2], "BACKGROUND", entry[3])
            tile:SetAllPoints(entry[4] or entry[1])
            win.quietMaterials[#win.quietMaterials + 1] = tile
        end
    end
    if on and not win.quietFrame then
        win.quietFrame = R.SettingsCraft.Frame(win.shell)
    end
    R.SettingsCraft.LegacyRails(win.shell, not on)
    if win.quietFrame then win.quietFrame:SetShown(on and true or false) end
    for _, tile in ipairs(win.quietMaterials or {}) do tile:SetShown(on and true or false) end
    local e = win.craftElements
    if e and on and not e.original then
        e.original = {}
        e.originalSize = {}
        for _, key in ipairs({ "brand", "subtitle", "search", "hint", "close" }) do
            local target = key == "close" and e.close.text or e[key]
            e.original[key] = { target:GetFont() }
            e.originalSize[key] = { target:GetWidth(), target:GetHeight() }
        end
        e.closeSize = { e.close:GetWidth(), e.close:GetHeight() }
        local function Active() return win.craftActive end
        e.searchArt = R.SettingsCraft.Control(e.search, "field", Active)
        e.closeArt = R.SettingsCraft.Control(e.close, nil, Active)
    end
    if e and e.original then
        e.crest:SetSize(on and 44 or 24, on and 44 or 24)
        e.search:SetSize(on and 280 or 260, on and 30 or 24)
        e.close:SetSize(on and 28 or e.closeSize[1], on and 28 or e.closeSize[2])
        if on then
            M.ReminderFont(e.brand, 25, true, "serif")
            e.brand:SetSize(110, 34)
            M.ReminderFont(e.subtitle, 14)
            e.subtitle:SetSize(68, 20)
            M.ReminderFont(e.search, 14, true)
            M.ReminderFont(e.hint, 14)
            e.hint:SetSize(226, 22)
            M.ReminderFont(e.close.text, 16, true)
        else
            for key, font in pairs(e.original) do
                local target = key == "close" and e.close.text or e[key]
                if font[1] then target:SetFont(unpack(font)) end
                if key ~= "search" and key ~= "close" then target:SetSize(unpack(e.originalSize[key])) end
            end
        end
        e.searchArt.Refresh(); e.closeArt.Refresh()
    end
end

function M.WorkspaceFrame(frame)
    local shell = R.FrameLook.Shell(frame, { below = true, bare = true })
    local grain = M.QuietTile(frame, "outer", "BACKGROUND", -7)
    grain:ClearAllPoints()
    grain:SetPoint("TOPLEFT", 3, -3)
    grain:SetPoint("BOTTOMRIGHT", -3, 3)
    R.SettingsCraft.LegacyRails(shell, false)
    R.SettingsCraft.Frame(shell)
    frame.workspaceGrain = grain
    return shell
end

function M.FrameConnector(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    frame:SetFrameLevel((parent:GetFrameLevel() or 0) + 3)
    frame:EnableMouse(false)
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture(R.PATH .. [[media\reminders\connector]] .. (size <= 64 and "-small.tga" or ".tga"))
    return frame
end

function M.MaterialHover(frame, when)
    local parts = R.SettingsCraft.Sheet(frame, "selection-hot", { layer = "BACKGROUND", sub = 2, corner = 10 })
    parts:SetAlpha(0.22)
    parts:Hide()
    local rim = R.SettingsCraft.Sheet(frame, "hover-rim", { layer = "OVERLAY", sub = 3 })
    rim:Hide()
    local function Paint(shown)
        local active = shown and frame:IsEnabled() and (not when or when())
        parts:SetShown(active)
        rim:SetShown(active)
    end
    frame:HookScript("OnEnter", function() Paint(true) end)
    frame:HookScript("OnLeave", function() Paint(false) end)
    frame:HookScript("OnHide", function() Paint(false) end)
    frame:HookScript("OnDisable", function() Paint(false) end)
end

function M.MenuStyle(menu, on)
    menu.materialMode = on
    if not menu.materialBackground and not on then return end
    if not menu.materialBackground then
        local bg = CreateFrame("Frame", nil, menu)
        bg:SetAllPoints()
        bg:SetFrameLevel(menu:GetFrameLevel() or 0)
        M.PanelFace(bg, "espresso")
        menu.materialBackground = bg
        local track = Wg.Solid(bg, "ARTWORK", { 0.055, 0.043, 0.031 }, 1)
        track:SetWidth(5)
        track:SetPoint("TOPRIGHT", -4, -4)
        track:SetPoint("BOTTOMRIGHT", -4, 4)
        local bevel = Wg.Solid(bg, "OVERLAY", pal.bronzeText, 0.32)
        bevel:SetWidth(1)
        bevel:SetPoint("TOPLEFT", menu.thumb, "TOPLEFT")
        bevel:SetPoint("BOTTOMLEFT", menu.thumb, "BOTTOMLEFT")
        menu.materialTrack, menu.materialThumbBevel = track, bevel
        menu.materialThumb = bg:CreateTexture(nil, "OVERLAY")
        R.SettingsCraft.Thumb(menu.materialThumb)
        menu.materialThumb:SetAllPoints(menu.thumb)
        for _, row in ipairs(menu.rows) do
            row.materialSelected = R.SettingsCraft.Sheet(row, "selection", { layer = "BACKGROUND", sub = 1, corner = 8 })
            M.MaterialHover(row, function() return menu.materialMode end)
            row.materialFont = { row.text:GetFont() }
        end
    end
    menu.materialBackground:SetShown(on)
    menu.materialTrack:SetShown(on and #menu.choices > #menu.rows)
    menu.materialThumbBevel:SetShown(on and #menu.choices > #menu.rows)
    if on then
        menu:SetBackdropColor(0, 0, 0, 0)
        menu:SetBackdropBorderColor(0, 0, 0, 0)
    else
        menu:SetBackdropColor(pal.bg[1] * 1.12, pal.bg[2] * 1.12, pal.bg[3] * 1.12, 1)
        menu:SetBackdropBorderColor(pal.control[1], pal.control[2], pal.control[3], 1)
    end
    for _, piece in pairs(menu.twichPopover or {}) do piece:SetShown(not on) end
    for _, row in ipairs(menu.rows) do
        row.materialSelected:SetShown(false)
        row.hover:SetAlpha(on and 0 or 1)
        if on then M.ReminderFont(row.text, 13)
        elseif row.materialFont[1] then row.text:SetFont(unpack(row.materialFont)) end
        local c = on and pal.bronzeText or pal.teal
        row.mark:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local c = on and pal.bronzeText or pal.thumb
    menu.thumb:SetColorTexture(c[1], c[2], c[3], 0.8)
    menu.thumb:SetWidth(on and 7 or 3)
    menu.thumb:SetAlpha(on and 0 or 1)
    menu.materialThumb:SetShown(on and #menu.choices > #menu.rows)
end

-- Reminders uses darker editing wells and warmer movable cards over the same leather.
-- Non-overlapping strips preserve the rounded corners and avoid multiple grain layers.
function M.QuietGrain(frame, role)
    local pieces = {}
    local middle = M.QuietTile(frame, role, "BACKGROUND", 1)
    middle:ClearAllPoints()
    middle:SetPoint("TOPLEFT", 1, -CORNER)
    middle:SetPoint("BOTTOMRIGHT", -1, CORNER)
    pieces[#pieces + 1] = middle
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        local tile = M.QuietTile(frame, role, "BACKGROUND", 1)
        pieces[#pieces + 1] = tile
        tile:ClearAllPoints()
        tile:SetPoint(side .. "LEFT", CORNER, side == "TOP" and -1 or 1)
        tile:SetPoint(side .. "RIGHT", -CORNER, side == "TOP" and -1 or 1)
        tile:SetHeight(CORNER - 1)
    end
    return pieces
end

function M.PanelFace(frame, kind)
    local role = (kind == "card" or kind == "walnut") and "card"
        or kind == "canvas" and "viewport" or kind == "espresso" and "outer" or "editor"
    local pieces = M.Slice(frame, "quiet-" .. role, "BACKGROUND", 0)
    for _, tile in ipairs(M.QuietGrain(frame, role)) do pieces[#pieces + 1] = tile end
    local fill = Group(pieces)
    fill.rim = R.SettingsCraft.Sheet(frame, role == "card" and "card-rim" or "inset-rim", { layer = "BORDER", sub = 3 })
    return fill
end

function M.SearchDecoration(box, placeholder)
    box:SetTextInsets(26, 8, 0, 0)
    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetAtlas("common-search-magnifyingglass")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetVertexColor(0.78, 0.71, 0.60)
    local hint = M.ReminderFont(Wg.Text(box, "small"), 14)
    hint:SetPoint("LEFT", 26, 0)
    hint:SetWidth(box:GetWidth() - 34)
    hint:SetText(placeholder)
    local function Paint()
        local focus = box:HasFocus()
        hint:SetShown(not focus and box:GetText() == "")
    end
    for _, event in ipairs({ "OnEnter", "OnLeave", "OnEditFocusGained", "OnEditFocusLost" }) do box:HookScript(event, Paint) end
    Paint()
    return hint
end

-- Skin the existing slider geometry. The native bar retains its full hit and drag region.
function M.ScrollRail(scroll, active)
    if scroll.materialRail then return scroll.materialRail.Fit end
    local bar = scroll.ScrollBar
    if type(bar) ~= "table" then return end
    bar.scrollStep = 16
    Wg.ScrollMotion(scroll, active)
    local thumb = bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture())
    if not thumb then return end
    local track = Wg.Solid(bar, "BACKGROUND", { 0.070, 0.059, 0.048 }, 1)
    track:SetWidth(5)
    track:SetPoint("TOP", 0, -2)
    track:SetPoint("BOTTOM", 0, 2)
    thumb:SetAlpha(0)
    local face = Wg.Solid(bar, "OVERLAY", { 0.43, 0.36, 0.27 }, 0.9)
    R.SettingsCraft.Thumb(face)
    face:SetVertexColor(0.80, 0.80, 0.80, 0.9)
    face:SetPoint("TOP", thumb, "TOP", 0, 0)
    face:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    face:SetWidth(5)
    local bevel = Wg.Solid(bar, "OVERLAY", { 0.73, 0.64, 0.50 }, 0.44)
    bevel:SetWidth(1)
    bevel:SetPoint("TOPLEFT", face, "TOPLEFT")
    bevel:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT")
    local arrows = {}
    for i, arrow in pairs({ bar.ScrollUpButton, bar.ScrollDownButton }) do
        if type(arrow) == "table" then
            local old = {}
            for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                local texture = arrow[getter] and arrow[getter](arrow)
                if type(texture) == "table" then old[#old + 1] = texture; texture:SetAlpha(0) end
            end
            local art = R.SettingsCraft.Sheet(arrow, "button", { layer = "BACKGROUND", corner = 4 })
            local function Paint()
                local on = not active or active()
                art:SetShown(on)
                if on then art:SetSkin(not arrow:IsEnabled() and "button-off" or arrow:IsMouseOver() and "button-hot" or "button") end
            end
            for _, event in ipairs({ "OnEnter", "OnLeave", "OnEnable", "OnDisable" }) do arrow:HookScript(event, Paint) end
            arrow:HookScript("OnMouseDown", function() if not active or active() then art:SetSkin("button-down") end end)
            arrow:HookScript("OnMouseUp", Paint)
            Paint()
            local chevron = Wg.Chevron(arrow, arrow, "CENTER", 0, 0, i == 2, pal.bronzeText)
            arrow:SetAlpha(.7)
            arrows[#arrows + 1] = { button = arrow, old = old, chevron = chevron, art = art }
        end
    end
    bar:HookScript("OnEnter", function() face:SetAlpha(1); bevel:SetAlpha(0.8) end)
    bar:HookScript("OnLeave", function() face:SetAlpha(0.9); bevel:SetAlpha(0.44) end)
    local full = 0
    local function Fit()
        local height = scroll:GetHeight()
        if height and height > 0 then bar:SetShown(full > height + 1) end
    end
    scroll:HookScript("OnSizeChanged", Fit)
    local rail = { Fit = function(contentHeight) full = contentHeight; Fit() end }
    function rail:SetShown(on)
        for _, piece in ipairs({ track, face, bevel }) do piece:SetShown(on) end
        thumb:SetAlpha(on and 0 or 1)
        for _, arrow in ipairs(arrows) do
            arrow.button:SetAlpha(on and .7 or 1)
            for _, texture in ipairs(arrow.old) do texture:SetAlpha(on and 0 or 1) end
            for _, piece in ipairs(arrow.chevron) do piece:SetShown(on) end
            arrow.art:SetShown(on)
        end
    end
    scroll.materialRail = rail
    return rail.Fit
end

function M.DashedBorder(frame, width, height)
    local dashes = {}
    local function Side(edge, length, horizontal)
        local count = math.floor((length - 4) / 8)
        for i = 1, count do
            local dash = Wg.Solid(frame, "OVERLAY", { 0.68, 0.54, 0.35 }, 1)
            dash:SetSize(horizontal and 5 or 1, horizontal and 1 or 5)
            local offset = (i - (count + 1) / 2) * 8
            dash:SetPoint(edge, frame, edge, horizontal and offset or 0, horizontal and 0 or offset)
            dashes[#dashes + 1] = dash
        end
    end
    Side("TOP", width, true); Side("BOTTOM", width, true)
    Side("LEFT", height, false); Side("RIGHT", height, false)
    local function Paint()
        local alpha = frame.dropHot and 1 or (frame:IsMouseOver() and 0.84 or 0.55)
        for _, dash in ipairs(dashes) do dash:SetAlpha(alpha) end
    end
    function frame:SetDropHot(value) self.dropHot = value; Paint() end
    frame:HookScript("OnEnter", Paint)
    frame:HookScript("OnLeave", Paint)
    Paint()
end

-- Texture chevrons avoid font-dependent disclosure glyphs. The native button
-- retains its callback, hit region and painted interaction states.
function M.Disclosure(button)
    button.craftLabelInset = 24
    local right = M.ReminderFont(Wg.Text(button, "body"), 16, true)
    right:SetPoint("LEFT", 10, 0); right:SetText("›")
    local down = Wg.Chevron(button, button, "LEFT", 13, 0, true, pal.bronzeText)
    function button:SetExpanded(open)
        right:SetShown(not open)
        for _, piece in ipairs(down) do piece:SetShown(open and true or false) end
    end
    button:SetExpanded(false)
end

-- Rounded Reminders controls, opt-in: keep their existing scripts, labels and state handling.
function M.ReminderControl(control, kind)
    if not control or control.twichReminderMaterial then return end
    control.twichReminderMaterial = true
    -- This adapter historically uses "primary" for quiet discovery actions; confirmation is the gold action.
    R.SettingsCraft.Control(control, kind == "primary" and "action" or kind)
    if kind == "field" then
        control:SetJustifyH("LEFT")
        M.ReminderFont(control, 14)
    end
    if control.text and type(control.text) ~= "string" then
        M.ReminderFont(control.text, 14)
        if kind == "dropdown" then control.text:SetWordWrap(false)
        else control.text:SetWidth(math.max(1, control:GetWidth() - 12)) end
    end
end

-- A local help surface for opt-in material controls. It does not alter the game's tooltip.
local help
function M.ContextTip(owner, title, body)
    owner:HookScript("OnEnter", function()
        if not help then
            help = CreateFrame("Frame", nil, UIParent)
            help:SetFrameStrata("TOOLTIP")
            help:SetClampedToScreen(true)
            help:EnableMouse(false)
            help:SetWidth(246)
            M.PanelFace(help, "espresso")
            help.title = M.ReminderFont(Wg.Text(help, "heading"), 14, true)
            help.title:SetPoint("TOPLEFT", 12, -10)
            help.title:SetWidth(222)
            help.body = M.ReminderFont(Wg.Text(help, "body"), 13)
            help.body:SetPoint("TOPLEFT", 12, -31)
            help.body:SetWidth(222)
        end
        help.owner = owner
        help:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
        help.title:SetText(title)
        local bodyText, extra = body
        if type(body) == "function" then bodyText, extra = body(owner) end
        help.body:SetText((bodyText or "") .. (extra and "\n" .. extra or ""))
        help:SetHeight(43 + help.body:GetStringHeight())
        help:ClearAllPoints()
        local _, right, _, top = Wg.VisibleRect(owner)
        if right and top then
            local ratio = owner:GetEffectiveScale() / help:GetEffectiveScale()
            help:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right * ratio, top * ratio + 8)
        else help:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 8) end
        help:Show()
    end)
    local function Hide()
        if help and help.owner == owner then help:Hide(); help.owner = nil end
    end
    owner:HookScript("OnLeave", Hide)
    owner:HookScript("OnHide", Hide)
end

function M.ReminderFont(text, size, ivory, role)
    local file, _, flags = text:GetFont()
    local locale = GetLocale and GetLocale()
    local western = locale ~= "koKR" and locale ~= "zhCN" and locale ~= "zhTW" and locale ~= "ruRU"
    if western then
        local serif = role == "serif" or size >= 17 or (file and file:find("Cinzel", 1, true))
        local name = serif and "Spectral-SemiBold.ttf" or role == "strong" and "AlegreyaSans-Bold.ttf" or "AlegreyaSans-Medium.ttf"
        local chosen = R.PATH .. [[media\fonts\]] .. name
        if text:SetFont(chosen, size, "") == false and file then text:SetFont(file, size, flags or "") end
    elseif file then text:SetFont(file, size, flags or "") end
    if ivory then Wg.Color(text, pal.text) end
    return text
end

function M.Segment(parent, label, width, onClick)
    local b = Wg.Button(parent, label, width, "secondary", onClick)
    M.ReminderControl(b, "segment")
    return b
end

-- Same contract as the settings checkbox, with separate hit, track and thumb regions.
function M.Pill(parent, onToggle, small)
    local b = CreateFrame("Button", nil, parent)
    local w, h = small and 32 or 42, small and 16 or 21
    b:SetSize(w, h)
    local track = b:CreateTexture(nil, "ARTWORK")
    track:SetTexture(DIR .. "switch-track.tga")
    track:SetAllPoints()
    local thumb = b:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(DIR .. "switch-thumb.tga")
    thumb:SetSize(h - 4, h - 4)
    local checked, active, hot, down = false, true, false, false
    local function Paint()
        local c = checked and { 0.93, 0.69, 0.36 } or { 0.55, 0.49, 0.43 }
        local light = down and 0.77 or (hot and 1 or 0.86)
        track:SetVertexColor(c[1] * light, c[2] * light, c[3] * light, active and 1 or 0.62)
        thumb:SetVertexColor(0.99, 0.93, 0.81, active and 1 or 0.62)
        thumb:ClearAllPoints()
        local side = checked and "RIGHT" or "LEFT"
        thumb:SetPoint(side, b, side, checked and -3 or 3, 0)
    end
    function b:SetChecked(v) checked = not not v; Paint() end
    function b:GetChecked() return checked end
    function b:SetActive(v) active = not not v; Paint() end
    function b:SetHot(v) hot = not not v; Paint() end
    b:HookScript("OnEnter", function() b:SetHot(true) end)
    b:HookScript("OnLeave", function() down = false; b:SetHot(false) end)
    b:HookScript("OnMouseDown", function() down = active; Paint() end)
    b:HookScript("OnMouseUp", function() down = false; Paint() end)
    b:SetScript("OnClick", function() if active and onToggle then onToggle(not checked) end end)
    Paint()
    return b
end

function M.ReminderRow(row)
    row.sel = R.SettingsCraft.Sheet(row, "selection", { layer = "BACKGROUND", sub = 1, corner = 12 })
    row.sel:SetShown(false)
end
