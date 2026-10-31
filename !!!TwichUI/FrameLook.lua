-- TwichUI: the framed window look
-- The treatment approved on the guild bank panel (inventory/GuildPanel.lua), shared: a continuous illustrated frame (four fixed corners
-- and four rails, cut from one painting by tools/make_guild_frame_art.py) over a neutral espresso interior with a faint rock grain, and
-- shallow beveled buttons (walnut and chestnut, antique gold only on the primary one). Textures only: nothing here takes the mouse, runs
-- per frame or reads or writes saved data. It draws; a consumer keeps its own click handlers, state, position and lifecycle.
--
--   F.Ready()                         true when the pieces it draws with (Look.lua, chronicle/Style.lua) are loaded
--   F.ContentInsets()                 l, t, r, b: where a window's content begins inside its frame (UI units; fixed)
--   F.RailInsets()                    l, t, r, b: where the rails end (a surface that meets the frame is inset by these)
--   F.Style(overrides)                a resolved style: the defaults with `overrides` on top (a copy; the defaults never change)
--   F.BORDER, F.BORDER_LABEL          the border id (and its list label) of a window whose background and border the player sets through a
--                                     MenuStyle look: offered as one of that look's own borders (options.extraBorders), it is the default
--   F.PANEL_BG, F.PANEL_BORDER        the espresso and aged bronze (as "AARRGGBB") such a look starts from; the look's owner puts them in its
--                                     own defaults, so a look that does not is never touched
--   F.Frame(frame, look)              the frame only (no interior) on `frame` while `look`'s border is F.BORDER, hidden otherwise; returns
--                                     how far content must sit in from the edge (0 when it is not drawn). Call it after look.Apply(frame):
--                                     the player's background, and any border they chose instead, are theirs and are never drawn over
--   F.Shell(parent, opts)             the frame and interior on a frame of its own, under the parent's content
--       opts.style    overrides (see STYLE below) for this one shell
--       opts.below    sit one frame level under `parent`, so text that is the parent's own is drawn over it (default: the same level)
--       opts.follow   fit the frame to the shell's height whenever it changes size (a window that FitToScreen may shrink)
--       opts.bare     the frame only: no interior and no grain, so the background under it (the player's own) shows
--     s:Fit(h)                        the four corners and rails for a shell `h` units high (cheap when `h` is unchanged)
--     s:Restyle(overrides)            repaint with the defaults plus `overrides`; makes no texture
--     s:Sheen() / s:Recess() / s:Groove()   one optional piece each (see below); asking again returns the same one
--     s:Header(h)                     a title strip `h` units high (its sheen and groove); returns the window's frame that marks its place
--   F.Button(parent, label, w, kind, onClick, opts)   kind: "primary" | "secondary" | "danger"; opts.style; b:Restyle(overrides)
--   F.Close(parent, onClick, opts)    the small close box in the same material; the caller anchors it
--   F.Toggle(parent, label, w, onClick, opts)   a two-state button (b:SetOn(bool)) with the same bevel; opts.style; b:Restyle(overrides)
--   F.FadeIn(frame)                   the opening fade (opacity only; the player's reduced-motion setting is honored)
--
-- STYLE (all colors are { r, g, b }): ink, bronzeHi, bronzeLo, interior, gold, grain (the rock tint), grainInterior (its alpha), and
-- the button sets quiet, primary, danger ({ border, bg, text, hotBorder, hotBg, hotText }) and off ({ border, bg, text }).
-- A consumer whose player can change the appearance reads that setting itself and passes it as `style`: the player's value wins over
-- every default here, and Restyle applies a changed setting without rebuilding anything. A consumer with a fixed look passes nothing and
-- saves nothing. The styles are per instance: nothing a consumer does to its own can reach another's or the defaults.
--
-- A shell sits at its parent's frame level (or one under it, with `below`); everything a window shows is a child frame above it.
-- Layers on a shell: the interior and grain are BACKGROUND sub-levels -5 and -4; Sheen -3, Recess -2 (its shadow -1) and Groove 0 are
-- there for the consumer's use; the frame's art is ARTWORK sub-level 2.
-- Buttons draw the bevel above the button's own face and under its label, and hover, pressed and disabled states are repainted from
-- the button's own scripts (hooked, once). Buttons take no keyboard focus, so there is no focused state.

local R = TwichUI
local S = R.ChronicleStyle
local F = {}
R.FrameLook = F

local function Look() return R.Look end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
-- Content begins this far in from the window's edge: the frame's rails and the margin under them, in UI units. The frame itself is drawn
-- at SCALE of the files' own size (a pixel of a file is half a unit at 1): the corners, the rails and the margin under them shrink
-- together, so their cross sections still match. The content's placement does not move with SCALE.
local CL, CT, CR, CB = 12, 12, 12, 13
local SCALE = 0.75
local CORNER_UNITS = 32 * SCALE           -- a corner file is 64 px: 32 units at full size (the block and a stub of both rails)
local EDGE_UNITS = 16 * SCALE             -- a rail file's width across: 32 px
local RL, RT, RR, RB = CL * SCALE, CT * SCALE, CR * SCALE, CB * SCALE
local UNDER = 2 * SCALE                   -- the interior is filled to this far from the edge, so nothing is clear beneath the rails
local FRAME_DIR = R.PATH .. [[media\guildbank\frame-]]
-- how much darker each rail is at its far end than at the end it was sampled at (printed by tools/make_guild_frame_art.py): the painting
-- is lit unevenly, so a rail is tinted by this along its length to meet the corner at both ends (top and bottom run left to right, the
-- sides top to bottom)
local RAIL_END = { top = 0.80, bottom = 0.82, left = 0.96, right = 0.95 }
local ROCK = [[Interface\FrameGeneral\UI-Background-Rock]]   -- a client texture (the Forever UI source uses it too), tinted warm

-- What a MenuStyle look starts from when its window wears this frame: the interior's espresso and the frame's aged bronze, as the look stores
-- a color (the two numbers in DEFAULT below, to the nearest byte; tests/test_frame_look.lua keeps them together).
F.BORDER = "twichui-frame"
F.BORDER_LABEL = "TwichUI frame (default)"
F.PANEL_BG = "ff1b1613"
F.PANEL_BORDER = "ffa8804a"

function F.ContentInsets() return CL, CT, CR, CB end
function F.RailInsets() return RL, RT, RR, RB end

function F.Ready()
    local L = Look()
    return L ~= nil and L.Fade ~= nil and L.pal ~= nil and S ~= nil and S.Button ~= nil and S.Close ~= nil
end

---------------------------------------------------------------------------
-- Style
---------------------------------------------------------------------------
local DEFAULT = {
    ink = { 0.106, 0.067, 0.055 },          -- the structural outer line and the shadows
    bronzeHi = { 0.66, 0.50, 0.29 },        -- aged bronze: the lit edge and the studs
    bronzeLo = { 0.42, 0.31, 0.19 },        -- ... its shaded side
    interior = { 0.105, 0.088, 0.073 },     -- the espresso inside the frame (neutral, not red)
    gold = { 0.84, 0.70, 0.42 },            -- antique gold: the primary action's lit edge only
    grain = { 0.95, 0.80, 0.60 },           -- the rock texture's tint
    grainInterior = 0.07,                   -- ... and how much of it shows
    quiet = {                               -- an ordinary button: a dark espresso face, a narrow muted bronze rim; hover lifts both
        border = { 0.40, 0.30, 0.20 }, bg = { 0.150, 0.112, 0.086 }, text = { 0.94, 0.90, 0.80 },
        hotBorder = { 0.56, 0.42, 0.27 }, hotBg = { 0.205, 0.154, 0.115 }, hotText = { 0.99, 0.96, 0.89 },
    },
    primary = {                             -- the one primary action: a richer chestnut face and an antique gold rim, no gold fill
        border = { 0.66, 0.52, 0.29 }, bg = { 0.255, 0.168, 0.108 }, text = { 0.98, 0.94, 0.84 },
        hotBorder = { 0.80, 0.65, 0.38 }, hotBg = { 0.315, 0.210, 0.135 }, hotText = { 1, 0.97, 0.89 },
    },
    off = { border = { 0.25, 0.19, 0.135 }, bg = { 0.115, 0.092, 0.075 }, text = { 0.52, 0.47, 0.40 } },   -- unavailable: subdued, still legible
}
local SETS = { quiet = true, primary = true, danger = true, off = true }

local function Valid(c) return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" end
local function CopyColor(c) return { c[1], c[2], c[3] } end
local function CopySet(set)
    local out = {}
    for name, c in pairs(set) do out[name] = CopyColor(c) end
    return out
end

-- The defaults with `overrides` on top, as a table of its own. A button set is overridden color by color; an unknown name or a
-- value that is not a color (or number) is ignored, never half applied. Danger is the shared rust (Look.lua) unless overridden.
function F.Style(overrides)
    local st = {}
    for key, v in pairs(DEFAULT) do
        if SETS[key] then st[key] = CopySet(v)
        elseif type(v) == "table" then st[key] = CopyColor(v)
        else st[key] = v end
    end
    local L = Look()
    st.danger = CopySet((L and L.pal and L.pal.danger) or st.quiet)
    if type(overrides) == "table" then
        for key, v in pairs(overrides) do
            local cur = st[key]
            if SETS[key] and type(v) == "table" then
                for name, c in pairs(v) do
                    if cur[name] ~= nil and Valid(c) then cur[name] = CopyColor(c) end
                end
            elseif type(cur) == "table" and Valid(v) then st[key] = CopyColor(v)
            elseif type(cur) == "number" and type(v) == "number" then st[key] = v end
        end
    end
    return st
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local function Solid(host, layer, sub, c, a)
    local t = host:CreateTexture(nil, layer, nil, sub)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

-- a texture's corners placed `l, t, r, b` units inside `host`'s
local function Inset(tex, host, l, t, r, b)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", host, "TOPLEFT", l, -t)
    tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -r, b)
end

local function Paint(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or 1) end

---------------------------------------------------------------------------
-- The shell
---------------------------------------------------------------------------
-- The frame and its interior, drawn on a frame of their own that sits under the content. The interior is filled to just under the
-- rails; the four corners are fixed size and the four rails are stretched along their sides (a rail's cross section does not change
-- along it). Every texture is made here, once.
function F.Shell(parent, opts)
    opts = opts or {}
    local s = CreateFrame("Frame", nil, parent)
    local level = parent:GetFrameLevel() or 0
    s:SetFrameLevel(opts.below and math.max(0, level - 1) or level)
    s:SetAllPoints(parent)
    s.style = F.Style(opts.style)
    s.parts = {}                       -- what repaints from the style (one function a piece)
    local bare = opts.bare
    if not bare then
        s.interior = Solid(s, "BACKGROUND", -5, s.style.interior)
        Inset(s.interior, s, UNDER, UNDER, UNDER, UNDER)
        s.grain = s:CreateTexture(nil, "BACKGROUND", nil, -4)
        s.grain:SetTexture(ROCK, "REPEAT", "REPEAT")
        s.grain:SetHorizTile(true)
        s.grain:SetVertTile(true)
        Inset(s.grain, s, UNDER, UNDER, UNDER, UNDER)
    end
    local function Art(name)
        local t = s:CreateTexture(nil, "ARTWORK", nil, 2)
        t:SetTexture(FRAME_DIR .. name .. ".tga")
        return t
    end
    s.corner = { tl = Art("corner-tl"), tr = Art("corner-tr"), bl = Art("corner-bl"), br = Art("corner-br") }
    s.edge = { top = Art("edge-top"), bottom = Art("edge-bottom"), left = Art("edge-left"), right = Art("edge-right") }
    local L = Look()
    for side, t in pairs(s.edge) do
        local k = RAIL_END[side]
        if t.SetGradient and CreateColor then       -- (where the client refuses a gradient the rail is simply untinted)
            local near, far = CreateColor(1, 1, 1, 1), CreateColor(k, k, k, 1)
            if side == "top" or side == "bottom" then pcall(t.SetGradient, t, "HORIZONTAL", near, far)
            else pcall(t.SetGradient, t, "VERTICAL", far, near) end     -- (a vertical gradient runs from the bottom color to the top one)
        end
    end

    local function Repaint()
        local st = s.style
        if not bare then
            Paint(s.interior, st.interior)
            s.grain:SetVertexColor(st.grain[1], st.grain[2], st.grain[3], st.grainInterior)
        end
        for _, part in ipairs(s.parts) do part(st) end
    end

    -- Fits the frame to a shell `h` units high. A corner's stub is only rail, so when two corners would meet on a short side
    -- the stubs are cut (not squeezed) to half the height each.
    function s:Fit(h)
        h = tonumber(h) or 0
        if self.fitH == h then return end
        self.fitH = h
        local v = math.max(0, math.min(CORNER_UNITS, math.floor(h / 2)))
        local frac = v / CORNER_UNITS
        for name, t in pairs(self.corner) do
            local top, left = name:sub(1, 1) == "t", name:sub(2, 2) == "l"
            local point = (top and "TOP" or "BOTTOM") .. (left and "LEFT" or "RIGHT")
            t:ClearAllPoints()
            t:SetPoint(point, self, point, 0, 0)
            t:SetSize(CORNER_UNITS, v)
            t:SetTexCoord(0, 1, top and 0 or 1 - frac, top and frac or 1)
        end
        local e = self.edge
        e.top:ClearAllPoints(); e.top:SetHeight(EDGE_UNITS)
        e.top:SetPoint("TOPLEFT", self, "TOPLEFT", CORNER_UNITS, 0); e.top:SetPoint("TOPRIGHT", self, "TOPRIGHT", -CORNER_UNITS, 0)
        e.bottom:ClearAllPoints(); e.bottom:SetHeight(EDGE_UNITS)
        e.bottom:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", CORNER_UNITS, 0); e.bottom:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -CORNER_UNITS, 0)
        e.left:ClearAllPoints(); e.left:SetWidth(EDGE_UNITS)
        e.left:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -v); e.left:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, v)
        e.right:ClearAllPoints(); e.right:SetWidth(EDGE_UNITS)
        e.right:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -v); e.right:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, v)
        e.left:SetShown(h > 2 * v); e.right:SetShown(h > 2 * v)
    end

    function s:Restyle(overrides)
        self.style = F.Style(overrides)
        Repaint()
    end

    -- A soft sheen along the top of a strip (the header, the action strip): light falling on it.
    function s:Sheen()
        if self.sheenPiece then return self.sheenPiece end
        local tex = self:CreateTexture(nil, "BACKGROUND", nil, -3)
        L.Fade(tex, L.pal.text, 0.05, 0)
        local piece = { tex = tex }
        function piece:Place(host, l, t, r, b) Inset(tex, host, l, t, r, b) end
        function piece:SetShown(v) tex:SetShown(v) end
        self.sheenPiece = piece
        return piece
    end

    -- A recessed area (a step deeper than the interior) with a shadow along its top, for the result or the list.
    function s:Recess()
        if self.recessPiece then return self.recessPiece end
        local fill = Solid(self, "BACKGROUND", -2, self.style.ink, 0.30)
        local shadow = self:CreateTexture(nil, "BACKGROUND", nil, -1)
        shadow:SetHeight(12)
        local piece = {}
        function piece:Place(host, l, t, r, b)
            Inset(fill, host, l, t, r, b)
            shadow:ClearAllPoints()
            shadow:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
            shadow:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
        end
        function piece:SetShown(v) fill:SetShown(v); shadow:SetShown(v) end
        self.parts[#self.parts + 1] = function(st)
            Paint(fill, st.ink, 0.30)
            L.Fade(shadow, st.ink, 0.40, 0)
        end
        self.parts[#self.parts](self.style)
        self.recessPiece = piece
        return piece
    end

    -- A quiet groove where two areas meet: a dark line over a faint lit one. :Place(host, edge, offset, l, r) lays it along `host`'s
    -- "TOP" or "BOTTOM" edge, `offset` units in, `l` and `r` units in from the sides.
    function s:Groove()
        if self.groovePiece then return self.groovePiece end
        local dark = Solid(self, "BACKGROUND", 0, self.style.ink, 0.75)
        dark:SetHeight(1)
        local lit = Solid(self, "BACKGROUND", 0, self.style.bronzeHi, 0.22)
        lit:SetHeight(1)
        local piece = {}
        function piece:Place(host, edge, offset, l, r)
            dark:ClearAllPoints(); lit:ClearAllPoints()
            if edge == "BOTTOM" then       -- the dark line is the upper of the two
                lit:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", l, offset); lit:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -r, offset)
                dark:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", l, offset + 1); dark:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -r, offset + 1)
            else
                dark:SetPoint("TOPLEFT", host, "TOPLEFT", l, -offset); dark:SetPoint("TOPRIGHT", host, "TOPRIGHT", -r, -offset)
                lit:SetPoint("TOPLEFT", host, "TOPLEFT", l, -(offset + 1)); lit:SetPoint("TOPRIGHT", host, "TOPRIGHT", -r, -(offset + 1))
            end
        end
        function piece:SetShown(v) dark:SetShown(v); lit:SetShown(v) end
        self.parts[#self.parts + 1] = function(st)
            Paint(dark, st.ink, 0.75)
            Paint(lit, st.bronzeHi, 0.22)
        end
        self.groovePiece = piece
        return piece
    end

    -- The title strip of a window: a sheen across the top of the interior and a groove under it, `h` units from the window's top. Returns
    -- a frame of the window's own that marks the strip's place, above the shell and not on the mouse: the window's icon and anything
    -- else drawn as a texture goes on it (a window's own textures can lie under a shell that is its child), and the title and close
    -- box are anchored to it. Asking again returns the same one (and ignores `h`: the strip is as high as it was first made).
    local headPiece
    function s:Header(h)
        if headPiece then return headPiece end
        headPiece = CreateFrame("Frame", nil, parent)
        headPiece:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        headPiece:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
        headPiece:SetHeight(h)
        self:Sheen():Place(headPiece, RL, RT, RR, 0)
        self:Groove():Place(headPiece, "BOTTOM", 0, RL, RR)
        return headPiece
    end

    Repaint()
    s:Fit(parent:GetHeight())
    if opts.follow then
        s:HookScript("OnSizeChanged", function(self, _, h) self:Fit(h or self:GetHeight()) end)
    end
    return s
end

-- The frame alone on a window whose background and border are the player's (a MenuStyle look: look.Apply(frame) has drawn them). While the
-- look's border is F.BORDER the frame is drawn, one shell made the first time it is wanted; for any other border it is hidden, so the
-- artwork is never laid over a border or background the player chose. Returns how far content sits in from the edge (0: not drawn).
function F.Frame(frame, look)
    local on = look.Get("borderTexture") == F.BORDER
    local s = frame.twichFrame
    if not s then
        if not on then return 0 end
        s = F.Shell(frame, { bare = true, follow = true })
        frame.twichFrame = s
    end
    s:SetShown(on)
    return on and math.max(CL, CT, CR, CB) or 0
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- The raised face over a button's own: a lit upper edge and a soft sheen, a darker lower edge, the four corner pixels clipped, and a dark
-- socket with a lit lip under it so the button sits in what it is on. It follows the button's states (the shared button repaints its face
-- and rim from its own scripts; this paints only the layers on top): a little brighter under the pointer, sunk (the lit edge goes dark,
-- the sheen goes, an inset shade comes in) while pressed, and subdued when disabled. All of it is made here, once, and hooked once.
local function Bevel(b, primary, style)
    local L = Look()
    local lk = { primary = primary, style = style, over = false, down = false }
    b.twichLook = lk
    local sheen = b:CreateTexture(nil, "ARTWORK")
    sheen:SetPoint("TOPLEFT", 1, -2)
    sheen:SetPoint("TOPRIGHT", -1, -2)
    sheen:SetHeight(9)
    L.Fade(sheen, { 1, 0.93, 0.8 }, 0.07, 0)
    local lit = Solid(b, "ARTWORK", 1, style.bronzeHi, 0.30)
    lit:SetHeight(1)
    lit:SetPoint("TOPLEFT", 1, -1)
    lit:SetPoint("TOPRIGHT", -1, -1)
    local dark = Solid(b, "ARTWORK", 1, style.ink, 0.50)
    dark:SetHeight(1)
    dark:SetPoint("BOTTOMLEFT", 1, 1)
    dark:SetPoint("BOTTOMRIGHT", -1, 1)
    local inset = Solid(b, "ARTWORK", 0, style.ink, 0.30)      -- the pressed state's shade
    inset:SetPoint("TOPLEFT", 1, -1)
    inset:SetPoint("BOTTOMRIGHT", -1, 1)
    local clip = {}
    for i, p in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local c = Solid(b, "BORDER", 7, style.ink, 0.85)
        c:SetSize(1, 1)
        c:SetPoint(p, 0, 0)
        clip[i] = c
    end
    local socket = Solid(b, "BACKGROUND", -8, style.ink, 0.55)
    socket:SetPoint("TOPLEFT", -1, 1)
    socket:SetPoint("BOTTOMRIGHT", 1, -1)
    local lip = Solid(b, "BACKGROUND", -8, style.bronzeHi, 0.12)
    lip:SetHeight(1)
    lip:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1)
    lip:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -1)
    lk.bevel = { sheen = sheen, lit = lit, dark = dark, inset = inset, clip = clip, socket = socket, lip = lip }

    -- what the style colors and the state does not change
    function lk.Still()
        local ST = lk.style
        for _, c in ipairs(clip) do Paint(c, ST.ink, 0.85) end
        Paint(socket, ST.ink, 0.55)
        Paint(lip, ST.bronzeHi, 0.12)
    end
    -- what the state changes: resting, under the pointer, pressed, unavailable
    function lk.State()
        local ST = lk.style
        local tone = lk.primary and ST.gold or ST.bronzeHi
        local ink = ST.ink
        local on = b:IsEnabled()
        inset:SetShown(on and lk.down)
        if not on then
            sheen:Hide()
            Paint(lit, tone, 0.07)
            Paint(dark, ink, 0.25)
        elseif lk.down then
            sheen:Hide()
            Paint(lit, ink, 0.55)
            Paint(dark, tone, 0.10)
        else
            sheen:Show()
            Paint(lit, tone, lk.over and 0.46 or 0.32)
            Paint(dark, ink, 0.50)
        end
        Paint(inset, ink, 0.30)
    end
    b:HookScript("OnEnter", function() lk.over = true; lk.State() end)
    b:HookScript("OnLeave", function() lk.over, lk.down = false, false; lk.State() end)
    b:HookScript("OnMouseDown", function() lk.down = true; lk.State() end)
    b:HookScript("OnMouseUp", function() lk.down = false; lk.State() end)
    b:HookScript("OnEnable", function() lk.down = false; lk.State() end)
    b:HookScript("OnDisable", function() lk.down = false; lk.State() end)
    -- a button that is hidden under the pointer (or mid-press) comes back resting: its face as well as its bevel
    b:HookScript("OnHide", function()
        lk.over, lk.down = false, false
        if b.Repaint then b:Repaint() end
        lk.State()
    end)
    lk.Still()
    lk.State()
end

-- The palette the shared button (chronicle/Style.lua) paints a face from: per button, filled from the button's style, falling back to
-- Look's for the names this look does not set. Filled again in place when the style changes (the button holds this table).
local function Fill(pal, style, danger)
    pal.primary, pal.quiet = style.primary, danger and style.danger or style.quiet
    pal.bronzeLo, pal.well, pal.stone = style.off.border, style.off.bg, style.off.text
    return pal
end

-- A button of this look: the shared button (its states, label, hit area) with this look's colors and the bevel. kind: "primary" (the one
-- richer action), "secondary", or "danger" (the shared rust). b:Restyle(overrides) applies a changed style; b.twichLook.bevel has the pieces.
function F.Button(parent, label, w, kind, onClick, opts)
    local style = F.Style(opts and opts.style)
    local danger = kind == "danger"
    local pal = Fill(setmetatable({}, { __index = Look().pal }), style, danger)
    local b = S.Button(parent, label, w, kind == "primary" and "primary" or "secondary", onClick, pal)
    b:SetMotionScriptsWhileDisabled(true)
    Bevel(b, kind == "primary", style)
    function b:Restyle(overrides)
        local lk = self.twichLook
        lk.style = F.Style(overrides)
        Fill(pal, lk.style, danger)
        if self.Repaint then self:Repaint() end
        lk.Still()
        lk.State()
    end
    return b
end

-- The close box: the shared one, its face and rim from the quiet button set (a little lighter under the pointer), and the same bevel.
-- The caller places it.
function F.Close(parent, onClick, opts)
    local style = F.Style(opts and opts.style)
    local pal = setmetatable({}, { __index = Look().pal })
    local function Colors(st)
        pal.bronzeLo, pal.well, pal.stone = st.quiet.border, st.quiet.bg, st.quiet.text
        pal.bronze, pal.band, pal.text = st.quiet.hotBorder, st.quiet.hotBg, st.quiet.hotText
    end
    Colors(style)
    local b = S.Close(parent, onClick, pal)
    Bevel(b, false, style)
    function b:Restyle(overrides)
        local st = F.Style(overrides)
        Colors(st)
        self.twichLook.style = st
        if self.Repaint then self:Repaint() end
        self.twichLook.Still()
        self.twichLook.State()
    end
    return b
end

-- A two-state button (the shared S.Toggle: b:SetOn(bool), the primary set while on) in this look, with the same bevel. The caller keeps
-- the state and places it. b:Restyle(overrides) applies a changed style.
function F.Toggle(parent, label, w, onClick, opts)
    local style = F.Style(opts and opts.style)
    local pal = Fill(setmetatable({}, { __index = Look().pal }), style, false)
    local b = S.Toggle(parent, label, w, onClick, pal)
    Bevel(b, false, style)
    function b:Restyle(overrides)
        local lk = self.twichLook
        lk.style = F.Style(overrides)
        Fill(pal, lk.style, false)
        if self.Repaint then self:Repaint() end
        lk.Still()
        lk.State()
    end
    return b
end

---------------------------------------------------------------------------
-- The opening fade
---------------------------------------------------------------------------
-- A window that is shown comes in from transparent (opacity only; a window shown again after closing starts the fade again), unless the
-- player has turned the settings window's motion down. Made once per frame.
function F.FadeIn(frame)
    local M = Look() and Look().Motion
    if not M or frame.twichFade then return end
    local fade = M.Fader(function(a) frame:SetAlpha(a) end, 1)
    frame.twichFade = fade
    frame:HookScript("OnShow", function()
        if M.Enabled() then
            fade:Set(0)
            fade:To(1, M.TIME.window)
        else
            fade:Set(1)
        end
    end)
    frame:HookScript("OnHide", function() fade:Set(1) end)
end
