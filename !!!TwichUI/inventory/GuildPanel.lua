-- TwichUI: Magic Inventory, the panel at the guild bank window
-- A small strip attached to the guild bank window while it is open (and Magic Inventory is on): what is ready, and three
-- buttons, Deposit, Organize bank and Arrangement. Nothing in it moves an item by itself:
--   * opening the bank only makes GuildPrep.lua read the tabs and keep the summary ("Reading bank...", then "12 stacks ready to
--     deposit · 8 stacks to organize");
--   * Deposit or Organize bank makes sure every tab is current, then puts up ONE review (every tab it touches, quantities,
--     what is left out and why). Start is the player's approval of exactly that review (GuildRun.Start checks it is still true);
--   * while it runs the strip shows confirmed progress, Stop, and Continue when the game wants a click;
--   * the result (Completed / Partially completed / Stopped / Needs review) stays until dismissed; Details has the evidence.
-- The panel is built once, the first time the bank opens with the feature on, and reused. It hooks nothing of the game's: it
-- listens to the events Magic Inventory already listens to. It sits just outside the bank window (below it, else above it), so
-- it covers none of the game's controls.

local R = TwichUI
local MI = R.MagicInventory
local GB = MI.GuildBank
local GR = MI.GuildRun
local P = MI.GuildPrep

local Panel = {}
MI.GuildPanel = Panel

local NAME = "TwichUIGuildBankPanel"
local BAR_H, PAD, GAP = 58, 21, 4
local ICON, ICON_GAP, MAX_ICONS = 38, 6, 8
local MIN_W, MAX_W, SIDE_W = 520, 800, 400
local AMBER = { 0.93, 0.72, 0.38 }
local MAX_DETAIL = 14

local f
local review                 -- the review waiting for the player's approval
local awaiting               -- "deposit" | "reorganize" while the tabs are being made current for a review
local said                   -- one line of explanation (a refused action, a changed plan)
local detailsOpen = false
local dismissed              -- the result the player has dismissed
local queued = false

local function Look() return R.Look end
local function Plural(n, one, many) return ("%d %s"):format(n, n == 1 and one or (many or one .. "s")) end

local OUTCOME = { completed = "Completed", partial = "Partially completed", stopped = "Stopped", review = "Needs review" }

-- the words for why preparation is waiting; every one is something the player is doing or the game is, not a failure
local HOLD = {
    cursor = "Put down what is on your cursor and the bank will be read",
    combat = "Waiting for combat to end",
    mode = "Show the bank's items to read the other tabs",
    navigated = "Paused while you browse tabs",
    run = "A run is in progress",
    limit = "Not every tab was read",
    guild = "This isn't your guild's bank, as far as the game says",
    closed = "The bank is closed",
}

---------------------------------------------------------------------------
-- What the strip says
---------------------------------------------------------------------------
local function Guild() return MI.Plain((IsInGuild and IsInGuild() and GetGuildInfo and (GetGuildInfo("player"))) or nil) end

-- Returns the state of the bar: { kind, text, tone, deposit = { enabled, why }, organize = { enabled, why }, read = bool }
local function Compute()
    local prog = GR.Progress()
    if prog then
        local what = prog.mode == "deposit" and "Depositing" or "Organizing"
        local text = what .. "\226\128\166"
        if prog.stage == "refresh" then text = "Checking the bank\226\128\166"
        elseif prog.stage == "final" then text = "Checking the result\226\128\166" end
        if prog.needClick then text = what .. " \194\183 your click is needed"
        elseif prog.stopping then text = "Stopping\226\128\166" end
        return { kind = "run", text = text, prog = prog }
    end
    if review then return { kind = "review", text = "Ready when you are" } end
    local status = P.Status()
    if not status.arrangement then
        return { kind = "setup", text = ("No arrangement for %s yet"):format((Guild() and ("<" .. Guild() .. ">")) or "this guild") }
    end
    if awaiting or status.reading then
        local text = "Reading bank\226\128\166"
        if status.reading and status.tab and status.total > 0 then text = ("Reading bank\226\128\166 (tab %d)"):format(status.tab) end
        return { kind = "reading", text = text, tone = "dim", status = status }
    end
    local sum = P.Summary()
    if not sum then return { kind = "reading", text = "Reading bank\226\128\166", tone = "dim" } end
    local d, o = sum.deposit or {}, sum.organize or {}
    local bits = {}
    if (d.moves or 0) > 0 then bits[#bits + 1] = ("%s ready to deposit"):format(Plural(d.moves, "stack")) end
    if (o.moves or 0) > 0 then bits[#bits + 1] = ("%s to organize"):format(Plural(o.moves, "stack")) end
    local text
    if #bits > 0 then text = table.concat(bits, " \194\183 ")
    elseif d.code == "cursor" or d.code == "combat" or d.code == "closed" or d.code == "mode" then text = d.text or "Not ready"
    else text = "Nothing to move for your arrangement right now" end
    local missing = {}
    for tab in pairs(status.problems or {}) do missing[#missing + 1] = tab end
    table.sort(missing)
    local tone
    local read = false
    if #missing > 0 then
        local m = {}
        for _, t in ipairs(missing) do m[#m + 1] = tostring(t) end
        text = text .. (" \194\183 tab%s %s not read"):format(#m == 1 and "" or "s", table.concat(m, ", "))
        tone, read = "warn", true
    elseif status.state == "blocked" and HOLD[status.reason] then
        text = text .. " \194\183 " .. HOLD[status.reason]
        tone, read = "warn", status.reason == "limit" or status.reason == "navigated" or status.reason == "mode"
    end
    local function Why(x, label)
        if (x.moves or 0) > 0 then return true end
        if x.code == "nothing" or x.code == nil then return false, "Nothing for " .. label .. " to do right now." end
        return false, x.text
    end
    local de, dw = Why(d, "Deposit")
    local oe, ow = Why(o, "Organize bank")
    return { kind = "ready", text = text, tone = tone, read = read,
        deposit = { enabled = de, why = dw }, organize = { enabled = oe, why = ow } }
end

-- the evidence under Details: one line a move, every tab named (a review), or what the result recorded
local function ReviewDetails(rv)
    local out = {}
    if #rv.tabs > 1 or rv.crossTab > 0 then out[#out + 1] = "The bank window will show each tab in turn while this runs, and your own tab again at the end." end
    local function Name(id) local fa = id and MI.ItemFacts(id); return fa and fa.name or ("item " .. tostring(id)) end
    local function At(w) return w.kind == "bag" and ("bag %d slot %d"):format(w.bag, w.slot) or ("tab %d slot %d"):format(w.tab, w.slot) end
    for i, o in ipairs(rv.ops) do
        if i > MAX_DETAIL then out[#out + 1] = ("\226\128\166 and %d more"):format(#rv.ops - MAX_DETAIL) break end
        out[#out + 1] = ("%s \195\151%d: %s \226\134\146 %s%s"):format(Name(o.id), o.count, At(o.src), At(o.dst), o.cross and " (between tabs)" or "")
    end
    for _, b in ipairs(rv.blockedItems or {}) do
        out[#out + 1] = ("%s \195\151%d \226\128\148 %s"):format(Name(b.id), b.count or 0, b.text or "")
    end
    return out
end

---------------------------------------------------------------------------
-- The look: an art-direction PILOT for this one panel (provisional; nothing here is shared or a theme)
-- A continuous illustrated frame (four fixed corners and four rails, cut from one painting by tools/make_guild_frame_art.py) over a
-- dark espresso interior with a faint rock grain, an action strip over a deeper recessed result area, and walnut buttons with a
-- bevel (gold only on the primary one). Textures only: nothing here takes the mouse, animates or runs per frame. Every value to
-- adjust after review is in STYLE and the frame constants.
---------------------------------------------------------------------------
-- the frame's rails, in UI units from the panel's outer edge to the rail's inner edge (the files' pixels / 2): top, bottom, left, right
local FT, FB, FL, FR = 12, 13, 12, 12
local FRAME_DIR = R.PATH .. [[media\guildbank\frame-]]
-- how much darker each rail is at its far end than at the end it was sampled at (printed by tools/make_guild_frame_art.py): the painting
-- is lit unevenly, so a rail is tinted by this along its length to meet the corner at both ends (top and bottom run left to right, the
-- sides top to bottom)
local RAIL_END = { top = 0.80, bottom = 0.82, left = 0.96, right = 0.95 }
-- The frame is drawn at SCALE of the files' own size (a pixel of a file is half a unit at 1): the corners, the rails and the margin
-- under them shrink together, so their cross sections still match. The content's placement (FT.. above, PAD, BAR_H) does not move.
local SCALE = 0.75
local CORNER_UNITS = 32 * SCALE           -- a corner file is 64 px: 32 units at full size (the block and a stub of both rails)
local EDGE_UNITS = 16 * SCALE             -- a rail file's width across: 32 px
local AT, AB, AL, AR = FT * SCALE, FB * SCALE, FL * SCALE, FR * SCALE   -- where the rails end, inside
local UNDER = 2 * SCALE                         -- the interior is filled to this far from the edge, so nothing is clear beneath the rails
local ROCK = [[Interface\FrameGeneral\UI-Background-Rock]]   -- a client texture (the Forever UI source uses it too), tinted warm
local STYLE = {
    ink = { 0.106, 0.067, 0.055 },          -- the structural outer line and the shadows
    bronzeHi = { 0.66, 0.50, 0.29 },        -- aged bronze: the lit edge and the studs
    bronzeLo = { 0.42, 0.31, 0.19 },        -- ... its shaded side
    interior = { 0.105, 0.088, 0.073 },     -- the espresso inside the frame (neutral, not red)
    gold = { 0.84, 0.70, 0.42 },            -- antique gold: the primary action's lit edge only
    grain = { 0.95, 0.80, 0.60 },           -- the rock texture's tint, and how much of it shows
    grainInterior = 0.07,
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

local function Solid(host, layer, sub, c, a)
    local t = host:CreateTexture(nil, layer, nil, sub)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

-- a texture's corners placed `l, t, r, b` pixels inside `host`'s
local function Inset(tex, host, l, t, r, b)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", host, "TOPLEFT", l, -t)
    tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -r, b)
end

local function Grain(host, sub, a)
    local t = host:CreateTexture(nil, "BACKGROUND", nil, sub)
    t:SetTexture(ROCK, "REPEAT", "REPEAT")
    t:SetHorizTile(true)
    t:SetVertTile(true)
    t:SetVertexColor(STYLE.grain[1], STYLE.grain[2], STYLE.grain[3], a)
    return t
end

-- The frame and its interior, drawn on a frame of their own that sits under the content (same level as the panel, so the strip and the
-- block draw over it). The interior is filled to just under the rails; the four corners are fixed size and the four rails are
-- stretched along their sides (a rail's cross section does not change along it).
local function MakeShell(parent)
    local L, ST = Look(), STYLE
    local s = CreateFrame("Frame", nil, parent)
    s:SetFrameLevel(parent:GetFrameLevel())
    Inset(Solid(s, "BACKGROUND", -5, ST.interior), s, UNDER, UNDER, UNDER, UNDER)
    Inset(Grain(s, -4, ST.grainInterior), s, UNDER, UNDER, UNDER, UNDER)
    -- what the shell draws inside itself so it sits under the content AND under the frame: the strip's sheen, and the result
    -- area's recess (a step deeper than the strip), its top shadow and the quiet groove where the strip and the block meet
    s.sheen = s:CreateTexture(nil, "BACKGROUND", nil, -3)
    L.Fade(s.sheen, L.pal.text, 0.05, 0)
    s.recess = Solid(s, "BACKGROUND", -2, ST.ink, 0.30)
    s.shadow = s:CreateTexture(nil, "BACKGROUND", nil, -1)
    L.Fade(s.shadow, ST.ink, 0.40, 0)
    s.shadow:SetHeight(12)
    s.groove = Solid(s, "BACKGROUND", 0, ST.ink, 0.75)           -- a dark line over a faint lit one
    s.groove:SetHeight(1)
    s.lit = Solid(s, "BACKGROUND", 0, ST.bronzeHi, 0.22)
    s.lit:SetHeight(1)
    local function Art(name)
        local t = s:CreateTexture(nil, "ARTWORK", nil, 2)
        t:SetTexture(FRAME_DIR .. name .. ".tga")
        return t
    end
    s.corner = { tl = Art("corner-tl"), tr = Art("corner-tr"), bl = Art("corner-bl"), br = Art("corner-br") }
    s.edge = { top = Art("edge-top"), bottom = Art("edge-bottom"), left = Art("edge-left"), right = Art("edge-right") }
    for side, t in pairs(s.edge) do
        local k = RAIL_END[side]
        if t.SetGradient and CreateColor then       -- (where the client refuses a gradient the rail is simply untinted)
            local near, far = CreateColor(1, 1, 1, 1), CreateColor(k, k, k, 1)
            if side == "top" or side == "bottom" then pcall(t.SetGradient, t, "HORIZONTAL", near, far)
            else pcall(t.SetGradient, t, "VERTICAL", far, near) end     -- (a vertical gradient runs from the bottom color to the top one)
        end
    end
    -- Fits the frame to a shell `h` units high. A corner's stub is only rail, so when two corners would meet on a short side
    -- the stubs are cut (not squeezed) to half the height each.
    function s:Fit(h)
        local v = math.max(0, math.min(CORNER_UNITS, math.floor(h / 2)))
        local frac = v / CORNER_UNITS
        for name, t in pairs(self.corner) do
            local top, left = name:sub(1, 1) == "t", name:sub(2, 2) == "l"
            t:ClearAllPoints()
            t:SetPoint((top and "TOP" or "BOTTOM") .. (left and "LEFT" or "RIGHT"), self, (top and "TOP" or "BOTTOM") .. (left and "LEFT" or "RIGHT"), 0, 0)
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
    s:Fit(BAR_H)
    return s
end

-- The raised face of a button here: a lit upper edge and a soft sheen, a darker lower edge, and the four corner pixels clipped. It
-- follows the button's own states (the shared button repaints its face and rim; this paints only the layers on top): a little brighter
-- under the pointer, sunk (the lit edge goes dark, the sheen goes, an inset shade comes in) while pressed, and subdued when disabled.
local function Raise(b, tone)
    local ST = STYLE
    local sheen = b:CreateTexture(nil, "ARTWORK")
    sheen:SetPoint("TOPLEFT", 1, -2)
    sheen:SetPoint("TOPRIGHT", -1, -2)
    sheen:SetHeight(9)
    Look().Fade(sheen, { 1, 0.93, 0.8 }, 0.07, 0)
    local lit = Solid(b, "ARTWORK", 1, tone, 0.30)
    lit:SetHeight(1)
    lit:SetPoint("TOPLEFT", 1, -1)
    lit:SetPoint("TOPRIGHT", -1, -1)
    local dark = Solid(b, "ARTWORK", 1, ST.ink, 0.50)
    dark:SetHeight(1)
    dark:SetPoint("BOTTOMLEFT", 1, 1)
    dark:SetPoint("BOTTOMRIGHT", -1, 1)
    local inset = Solid(b, "ARTWORK", 0, ST.ink, 0.30)      -- the pressed state's shade, down the top and left
    inset:SetPoint("TOPLEFT", 1, -1)
    inset:SetPoint("BOTTOMRIGHT", -1, 1)
    local clip = {}
    for i, p in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local c = Solid(b, "BORDER", 7, ST.ink, 0.85)
        c:SetSize(1, 1)
        c:SetPoint(p, 0, 0)
        clip[i] = c
    end
    local over, down = false, false
    local function Paint()
        local on = b:IsEnabled()
        inset:SetShown(on and down)
        if not on then
            sheen:Hide()
            lit:SetColorTexture(tone[1], tone[2], tone[3], 0.07)
            dark:SetColorTexture(ST.ink[1], ST.ink[2], ST.ink[3], 0.25)
        elseif down then
            sheen:Hide()
            lit:SetColorTexture(ST.ink[1], ST.ink[2], ST.ink[3], 0.55)
            dark:SetColorTexture(tone[1], tone[2], tone[3], 0.10)
        else
            sheen:Show()
            lit:SetColorTexture(tone[1], tone[2], tone[3], over and 0.46 or 0.32)
            dark:SetColorTexture(ST.ink[1], ST.ink[2], ST.ink[3], 0.50)
        end
    end
    b:HookScript("OnEnter", function() over = true; Paint() end)
    b:HookScript("OnLeave", function() over, down = false, false; Paint() end)
    b:HookScript("OnMouseDown", function() down = true; Paint() end)
    b:HookScript("OnMouseUp", function() down = false; Paint() end)
    b:HookScript("OnEnable", Paint)
    b:HookScript("OnDisable", Paint)
    b:HookScript("OnHide", function() over, down = false, false; Paint() end)
    Paint()
end

-- A button of this panel: the shared button (its states, label, hit area) with this panel's espresso/chestnut colors, the raised
-- face above, and a dark socket with a lit lip under it so it sits in the strip. Danger keeps the shared rust. A button here takes
-- no keyboard focus, so there is no focused state.
local function Button(parent, label, w, kind, onClick)
    local L, ST = Look(), STYLE
    local pal = setmetatable({
        primary = ST.primary, quiet = kind == "danger" and L.pal.danger or ST.quiet,
        bronzeLo = ST.off.border, well = ST.off.bg, stone = ST.off.text,
    }, { __index = L.pal })
    local b = R.ChronicleStyle.Button(parent, label, w, kind == "primary" and "primary" or "secondary", onClick, pal)
    b:SetMotionScriptsWhileDisabled(true)
    Raise(b, kind == "primary" and ST.gold or ST.bronzeHi)
    local socket = Solid(b, "BACKGROUND", -8, ST.ink, 0.55)
    socket:SetPoint("TOPLEFT", -1, 1)
    socket:SetPoint("BOTTOMRIGHT", 1, -1)
    local lip = Solid(b, "BACKGROUND", -8, ST.bronzeHi, 0.12)
    lip:SetHeight(1)
    lip:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1)
    lip:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -1)
    return b
end

---------------------------------------------------------------------------
-- The frames (built once)
---------------------------------------------------------------------------
local function Build()
    if f then return true end
    local L = Look()
    if not (L and L.Button and L.Surface and L.Text and L.Shade and L.Fade and R.ChronicleStyle) then return false end
    f = CreateFrame("Frame", NAME, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetSize(MIN_W, BAR_H)
    f:Hide()
    f.shell = MakeShell(f)                  -- the frame around the strip (and the block, when it is joined to the strip)
    f.shellB = MakeShell(f)                 -- the block's own frame, when it sits apart from the strip
    f.shellB:Hide()
    f.bar = CreateFrame("Frame", nil, f)    -- the action strip's inside; Dress() fits it to the shell
    f.bar:SetAllPoints(f)
    f.status = L.Text(f.bar, "body")
    f.status:SetPoint("LEFT", f.bar, "LEFT", PAD, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)

    f.arrange = Button(f.bar, "Arrangement\226\128\166", 110, "secondary", function()
        if R.OpenSettings then R:OpenSettings("magicInventory") end
    end)
    f.arrange:SetPoint("RIGHT", f.bar, "RIGHT", -(FR + 9), 0)
    R.Interact.Tip(f.arrange, "Arrangement", "Opens the arrangement editor: where each item belongs in the guild bank.")
    f.organize = Button(f.bar, "Organize bank", 110, "secondary", function() Panel.Act("reorganize") end)
    f.organize:SetPoint("RIGHT", f.arrange, "LEFT", -8, 0)
    f.deposit = Button(f.bar, "Deposit", 90, "primary", function() Panel.Act("deposit") end)
    f.deposit:SetPoint("RIGHT", f.organize, "LEFT", -8, 0)
    f.setup = Button(f.bar, "Set up arrangement", 150, "primary", function()
        if R.OpenSettings then R:OpenSettings("magicInventory") end
    end)
    f.setup:SetPoint("RIGHT", f.bar, "RIGHT", -(FR + 9), 0)
    f.read = Button(f.bar, "Read again", 90, "secondary", function() Panel.ReadAgain() end)
    f.read:SetPoint("RIGHT", f.deposit, "LEFT", -8, 0)
    R.Interact.Tip(f.read, "Read again", "Reads the tabs that were not read, one at a time. Nothing moves.")
    f.stop = Button(f.bar, "Stop", 80, "danger", function() GR.Stop() end)
    f.stop:SetPoint("RIGHT", f.bar, "RIGHT", -(FR + 9), 0)
    R.Interact.Tip(f.stop, "Stop", "Ends the run after the move in progress. Nothing already moved is undone.")
    f.go = Button(f.bar, "Continue", 90, "primary", function() GR.Continue() end)
    f.go:SetPoint("RIGHT", f.stop, "LEFT", -8, 0)
    R.Interact.Tip(f.go, "Continue", "The game asked for a click before this move. One move per click.")
    for _, key in ipairs({ "deposit", "organize" }) do
        local b = f[key]
        R.Interact.Tip(b, key == "deposit" and "Deposit" or "Organize bank", function()
            if b.why then return b.why end
            if key == "deposit" then return "Moves eligible items from your bags into the tabs your arrangement names. You review, then approve." end
            return "Moves items already in the guild bank to where your arrangement wants them, including between tabs. You review, then approve."
        end)
    end

    f.detail = CreateFrame("Frame", nil, f)
    f.title = L.Text(f.detail, "title")                 -- the one big line: what this is, or how it went
    f.title:SetJustifyH("LEFT")
    f.sub = L.Text(f.detail, "body")                    -- one short line under it
    f.sub:SetJustifyH("LEFT")
    f.warn = L.Text(f.detail, "body")                   -- what needs a look, in amber, one short line
    f.warn:SetJustifyH("LEFT")
    f.more = L.Text(f.detail, "small")                  -- Details: the evidence, only when asked for
    f.more:SetJustifyH("LEFT")
    f.more:SetSpacing(2)
    f.icons = {}
    for i = 1, MAX_ICONS + 1 do
        local b = CreateFrame("Frame", nil, f.detail, "BackdropTemplate")
        b:SetSize(ICON, ICON)
        L.Surface(b, L.pal.well, 1, L.pal.bronzeLo, 0.9)
        L.Recess(b)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.count = L.Text(b, "body")
        b.count:SetPoint("BOTTOMRIGHT", -3, 3)
        b.count:SetJustifyH("RIGHT")
        b.count:SetShadowColor(0, 0, 0, 1)
        b.count:SetShadowOffset(1, -1)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1)
            if self.tip2 then GameTooltip:AddLine(self.tip2, AMBER[1], AMBER[2], AMBER[3], true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        f.icons[i] = b
    end
    -- the progress bar: a track, a fill and the count, drawn from textures (no template)
    f.progress = CreateFrame("Frame", nil, f.detail, "BackdropTemplate")
    f.progress:SetHeight(26)
    L.Surface(f.progress, L.pal.well, 1, L.pal.bronzeLo, 0.9)
    L.Recess(f.progress)
    f.progress.fill = f.progress:CreateTexture(nil, "ARTWORK")
    f.progress.fill:SetPoint("TOPLEFT", 2, -2)
    f.progress.fill:SetPoint("BOTTOMLEFT", 2, 2)
    f.progress.fill:SetWidth(1)
    f.progress.fill:SetColorTexture(L.pal.tealHi[1], L.pal.tealHi[2], L.pal.tealHi[3], 0.9)
    f.progress.text = L.Text(f.progress, "title")
    f.progress.text:SetPoint("CENTER", 0, 0)
    f.progress:Hide()
    f.curIcon = f.detail:CreateTexture(nil, "ARTWORK")
    f.curIcon:SetSize(24, 24)
    f.curIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cur = L.Text(f.detail, "body")                    -- the move in progress: "Linen Cloth > Cloth"
    f.cur:SetJustifyH("LEFT")
    f.start = Button(f.detail, "Start", 130, "primary", function() Panel.Start() end)
    f.cancel = Button(f.detail, "Cancel", 80, "secondary", function() Panel.Cancel() end)
    f.details = Button(f.detail, "Details", 80, "secondary", function() detailsOpen = not detailsOpen; Panel.Refresh() end)
    f.dismiss = Button(f.detail, "Dismiss", 80, "secondary", function() Panel.Dismiss() end)
    return true
end

local function Tone(fs, tone)
    local L, pal = Look(), Look().pal
    if tone == "warn" then L.Color(fs, AMBER)
    elseif tone == "dim" then L.Color(fs, pal.textDim)
    else L.Color(fs, pal.text) end
end

local function Edge(frame, name, default)
    local fn = frame and frame[name]
    local v = type(fn) == "function" and fn(frame) or nil
    return type(v) == "number" and v or default
end

-- The strip: below the bank window, else above it, else a quiet place at the top of the screen (another addon draws the bank).
-- Returns its width. f.near: "top" (below the window), "bottom" (above it) or nil (not attached).
local function PlaceBar()
    f:ClearAllPoints()
    f.near = nil
    local host = _G.GuildBankFrame
    local w = MIN_W
    if type(host) == "table" and host.IsShown and host:IsShown() then
        w = math.min(MAX_W, math.max(MIN_W, Edge(host, "GetWidth", MIN_W)))
        local bottom, top = Edge(host, "GetBottom", 0), Edge(host, "GetTop", 0)
        local screenTop = Edge(UIParent, "GetTop", Edge(UIParent, "GetHeight", 0))
        if bottom >= BAR_H + GAP * 2 then f:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -GAP); f.near = "top"
        elseif screenTop - top >= BAR_H + GAP * 2 then f:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, GAP); f.near = "bottom" end
    end
    if not f.near then f:SetPoint("TOP", UIParent, "TOP", 0, -110) end
    f:SetSize(w, BAR_H)
    return w
end

-- The review or result block: joined to the strip when the screen has room on that side, else beside the bank window (right,
-- then left), and only when there is room nowhere on top of the strip's own side (the last resort, which can cover the window).
-- fill(width, joined) lays the text out for a width (joined to the strip or not: the frame's rail is on one side less) and returns the block's height. Returns true when the block is joined to the strip
-- (no gap: one frame around both), nil when it sits apart.
local function PlaceDetail(barW, fill)
    local host = _G.GuildBankFrame
    local d = f.detail
    d:ClearAllPoints()
    local h = fill(barW, true)
    local attached = type(host) == "table" and host.IsShown and host:IsShown()
    if attached then
        local bottom, top = Edge(host, "GetBottom", 0), Edge(host, "GetTop", 0)
        local screenTop = Edge(UIParent, "GetTop", Edge(UIParent, "GetHeight", 0))
        if f.near == "top" and bottom - BAR_H - GAP * 2 >= h + GAP then
            d:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0); d:SetWidth(barW); d:SetHeight(h)
            return true
        elseif f.near == "bottom" and screenTop - top - BAR_H - GAP * 2 >= h + GAP then
            d:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0); d:SetWidth(barW); d:SetHeight(h)
            return true
        end
        local left, right = Edge(host, "GetLeft", 0), Edge(host, "GetRight", 0)
        local screenRight = Edge(UIParent, "GetRight", Edge(UIParent, "GetWidth", 0))
        h = fill(SIDE_W, false)
        if screenRight - right >= SIDE_W + GAP then
            d:SetPoint("TOPLEFT", host, "TOPRIGHT", GAP, 0); d:SetWidth(SIDE_W); d:SetHeight(h)
            return
        elseif left >= SIDE_W + GAP then
            d:SetPoint("TOPRIGHT", host, "TOPLEFT", -GAP, 0); d:SetWidth(SIDE_W); d:SetHeight(h)
            return
        end
        h = fill(barW, true)
    end
    -- nowhere beside the window: the block takes the strip's own side (it may overlap what is there)
    if f.near == "bottom" then d:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 0) else d:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0) end
    d:SetWidth(barW); d:SetHeight(h)
    return true
end

-- Fits the frames to what is shown. Joined: one shell around strip and block, the strip and block each fitted to its inside with a
-- quiet groove where they meet. Apart (or no block): the strip's shell alone, and the block's own shell.
local function Dress(joined)
    local d = f.detail
    local shown = d:IsShown()
    joined = joined and shown
    local above = joined and f.near == "bottom"                 -- the block is above the strip
    f.shell:ClearAllPoints()
    if joined and above then
        f.shell:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0); f.shell:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    elseif joined then
        f.shell:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); f.shell:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)
    else
        f.shell:SetAllPoints(f)
    end
    f.shellB:ClearAllPoints()
    if shown and not joined then f.shellB:SetAllPoints(d); f.shellB:Show() else f.shellB:Hide() end
    f.shell:Fit(joined and (BAR_H + d:GetHeight()) or BAR_H)
    f.shellB:Fit(d:GetHeight())
    -- the strip's inside: the frame on its outer sides, the groove on the side it shares with the block
    f.bar:ClearAllPoints()
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -((joined and above) and 0 or FT))
    f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, (joined and not above) and 0 or FB)
    Inset(f.shell.sheen, f.bar, AL, 0, AR, 0)
    f.shellB.sheen:Hide()
    -- the block's inside is drawn by the shell that holds it
    local s = joined and f.shell or f.shellB
    f.shell.recess:SetShown(joined); f.shell.shadow:SetShown(joined)
    f.shellB.recess:SetShown(shown and not joined); f.shellB.shadow:SetShown(shown and not joined)
    f.shell.groove:SetShown(joined); f.shell.lit:SetShown(joined)
    f.shellB.groove:Hide(); f.shellB.lit:Hide()
    if not shown then return end
    Inset(s.recess, d, AL, (joined and not above) and 2 or AT, AR, (joined and above) and 2 or AB)
    s.shadow:ClearAllPoints()
    s.shadow:SetPoint("TOPLEFT", s.recess, "TOPLEFT", 0, 0)
    s.shadow:SetPoint("TOPRIGHT", s.recess, "TOPRIGHT", 0, 0)
    if joined then
        s.groove:ClearAllPoints(); s.lit:ClearAllPoints()
        if above then          -- the dark line is the upper of the two
            s.lit:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", AL, 0); s.lit:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -AR, 0)
            s.groove:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", AL, 1); s.groove:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -AR, 1)
        else
            s.groove:SetPoint("TOPLEFT", d, "TOPLEFT", AL, 0); s.groove:SetPoint("TOPRIGHT", d, "TOPRIGHT", -AR, 0)
            s.lit:SetPoint("TOPLEFT", d, "TOPLEFT", AL, -1); s.lit:SetPoint("TOPRIGHT", d, "TOPRIGHT", -AR, -1)
        end
    end
end


-- the words and pictures of the block under the strip, for what is going on: a review waiting, a run, the last result, or a line
-- of explanation. Short on purpose: the evidence is under Details.
local function ItemName(id) local fa = id and MI.ItemFacts(id); return fa and fa.name or ("item " .. tostring(id)) end
local function ItemIcon(id) local fa = id and MI.ItemFacts(id); return fa and fa.icon or "Interface\\Icons\\INV_Misc_QuestionMark" end

local function TabNames(rv)
    local names = {}
    for _, tab in ipairs(rv.tabs) do
        local t = rv.tabInfo[tab]
        names[#names + 1] = (t and t.name) or ("tab " .. tab)
    end
    if #names <= 1 then return names[1] or "the bank" end
    local last = table.remove(names)
    return table.concat(names, ", ") .. " and " .. last
end

local function Content(state, result)
    local c = { icons = {} }
    if state.kind == "run" then
        local prog = state.prog
        c.run = true
        c.title = prog.mode == "deposit" and "Depositing" or "Organizing"
        if prog.stage == "refresh" then c.title = "Checking the bank" elseif prog.stage == "final" then c.title = "Checking the result" end
        c.frac = prog.stage == "final" and 1 or (prog.total > 0 and prog.confirmed / prog.total or 0)
        c.barText = prog.stage == "refresh" and "\226\128\166" or ("%d of %d"):format(prog.confirmed, prog.total)
        if prog.current and prog.stage == "ops" then
            c.cur = { id = prog.current.id, text = ("%s \195\151%d"):format(ItemName(prog.current.id), prog.current.count) }
        end
        if prog.needClick then c.warn = "The game wants a click: press Continue."
        elseif prog.stopping then c.warn = "Stopping after this move."
        elseif prog.reading then c.warn = ("Reading tab %d\226\128\166"):format(prog.reading) end
    elseif state.kind == "reading" and state.status and state.status.total > 0 then
        -- reading the bank: a bar of the tabs that are read (the shown tab and the ones already asked for count)
        local stt = state.status
        c.run = true
        c.title = "Reading the bank"
        c.frac = math.min(1, stt.done / stt.total)
        c.barText = ("%d of %d tabs"):format(math.min(stt.done, stt.total), stt.total)
    elseif state.kind == "review" and review then
        local rv = review
        c.review, c.hasDetails = true, true
        c.title = rv.mode == "deposit" and "Deposit" or "Organize"
        c.sub = (rv.mode == "deposit" and "%s into %s" or "%s in %s"):format(Plural(rv.moves, "stack"), TabNames(rv))
        for _, it in ipairs(rv.items) do c.icons[#c.icons + 1] = { id = it.id, qty = it.qty } end
        c.more = #rv.itemsMore
        local bits = {}
        if rv.crossTab > 0 then bits[#bits + 1] = ("%d between tabs"):format(rv.crossTab) end
        if #rv.dropped > 0 then bits[#bits + 1] = ("%d left out"):format(#rv.dropped) end
        if rv.planBlocked > 0 then bits[#bits + 1] = ("%d blocked"):format(rv.planBlocked) end
        if #rv.unread > 0 then bits[#bits + 1] = ("tab%s %s not read"):format(#rv.unread == 1 and "" or "s", table.concat(rv.unread, ", ")) end
        if #bits > 0 then c.note = table.concat(bits, " \194\183 ") end
        c.warn = said
        c.start = rv.mode == "deposit" and "Start deposit" or "Start organizing"   -- a partial plan says so in the line above (what is left out)
    elseif state.kind ~= "run" and result then
        c.result, c.hasDetails = true, #result.lines > 0
        c.title = OUTCOME[result.outcome] or result.outcome
        c.good = result.outcome == "completed"
        c.sub = ("%d of %d stacks moved"):format(result.confirmed, result.total)
        local seen, order = {}, {}
        for _, o in ipairs(result.ops) do
            local e = seen[o.id]
            if not e then e = { id = o.id, qty = 0, state = "ok" }; seen[o.id] = e; order[#order + 1] = e end
            if o.status == "confirmed" then e.qty = e.qty + o.count
            elseif o.status == "uncertain" then e.state = "warn"
            elseif e.state ~= "warn" then e.state = "dim" end
        end
        for _, e in ipairs(order) do c.icons[#c.icons + 1] = e end
        local bits = {}
        if result.reason and not c.good then bits[#bits + 1] = result.reason:gsub("^%l", string.upper) end
        if result.unreadTabs and #result.unreadTabs > 0 then bits[#bits + 1] = Plural(#result.unreadTabs, "tab") .. " not read" end
        if result.cursor then
            local w = result.cursor.where
            bits[#bits + 1] = ("Your cursor holds %s: put it back in %s"):format(ItemName(result.cursor.id), w.kind == "bag" and ("bag %d slot %d"):format(w.bag, w.slot) or ("tab %d slot %d"):format(w.tab, w.slot))
        end
        if #bits > 0 then c.warn = table.concat(bits, " \194\183 ") end
        c.dismiss = true
    elseif said then
        c.say, c.warn = true, said
    end
    return c
end

local function Layout(state)
    local barW = PlaceBar()
    local L, pal = Look(), Look().pal
    local result = GR.Last()
    if result and result == dismissed then result = nil end
    local c = Content(state, result)
    if not (c.run or c.review or c.result or c.say) then f.progress:Hide(); f.detail:Hide(); Dress(false) return end
    f.detail:Show()
    -- what is shown
    f.title:SetText(c.title or "")
    if c.good then L.Color(f.title, pal.sage) elseif c.result then L.Color(f.title, AMBER) else L.Color(f.title, pal.text) end
    f.sub:SetText(c.sub or "")
    L.Color(f.sub, pal.textDim)
    local warn = c.warn
    if c.note and c.review then warn = warn and (c.note .. " \194\183 " .. warn) or c.note end
    f.warn:SetText(warn or "")
    L.Color(f.warn, AMBER)
    local details = c.hasDetails and detailsOpen
    if details and c.review then f.more:SetText(table.concat(ReviewDetails(review), "\n"))
    elseif details and c.result then
        local det = {}
        for i, l in ipairs(result.lines) do
            if i > MAX_DETAIL then det[#det + 1] = ("\226\128\166 and %d more lines"):format(#result.lines - MAX_DETAIL) break end
            det[#det + 1] = l
        end
        f.more:SetText(table.concat(det, "\n"))
    else f.more:SetText("") end
    if c.review then f.start.text:SetText(c.start); f.start:SetWidth(math.max(130, #c.start * 8 + 28)) end
    f.start:SetShown(c.review == true); f.cancel:SetShown(c.review == true); f.dismiss:SetShown(c.dismiss == true or c.say == true)
    f.progress:SetShown(c.run == true)
    if c.run then
        f.progress.text:SetText(c.barText)
        f.curIcon:SetShown(c.cur ~= nil); f.cur:SetShown(c.cur ~= nil)
        if c.cur then f.curIcon:SetTexture(ItemIcon(c.cur.id)); f.cur:SetText(c.cur.text) end
    else
        f.curIcon:Hide(); f.cur:Hide()
    end
    -- the icons: what is moving (or moved), with its quantity; a tile for the rest
    local nIcons = math.min(#c.icons, MAX_ICONS)
    for i, b in ipairs(f.icons) do
        local e = c.icons[i]
        if i <= nIcons and e then
            b.tex:SetTexture(ItemIcon(e.id))
            b.count:SetText((e.qty or 0) > 1 and tostring(e.qty) or "")
            b.tex:SetAlpha(e.state == "dim" and 0.4 or 1)
            local edge = e.state == "warn" and AMBER or pal.bronzeLo
            b:SetBackdropBorderColor(edge[1], edge[2], edge[3], e.state == "warn" and 1 or 0.9)
            b.tip = ("%s%s"):format(ItemName(e.id), (e.qty or 0) > 1 and (" \195\151" .. e.qty) or "")
            b.tip2 = e.state == "warn" and "Not confirmed" or (e.state == "dim" and "Not moved" or nil)
            b:Show()
        elseif i == nIcons + 1 and ((c.more or 0) > 0 or #c.icons > MAX_ICONS) then
            b.tex:SetTexture(nil)
            b.count:SetText("+" .. ((c.more or 0) + math.max(0, #c.icons - MAX_ICONS)))
            b.tip, b.tip2 = nil, nil
            b:SetBackdropBorderColor(pal.bronzeLo[1], pal.bronzeLo[2], pal.bronzeLo[3], 0.9)
            b:Show()
        else
            b:Hide()
        end
    end
    local overflow = ((c.more or 0) > 0 or #c.icons > MAX_ICONS) and 1 or 0
    local shownIcons = nIcons + overflow

    -- laid out for a width; returns the block's height
    local function Fill(width, joined)
        local textW = width - PAD * 2
        local above = joined and f.near == "bottom"      -- the block is above the strip: its lower edge is the shared one
        local ti = (joined and not above) and 10 or FT + 8
        local bi = above and 10 or FB + 8
        local y = ti
        local function Line(fs, gap)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
            fs:SetWidth(textW)
            if (fs:GetText() or "") == "" then fs:Hide() return end
            fs:Show()
            y = y + (fs:GetStringHeight() or 14) + (gap or 4)
        end
        Line(f.title, 4)
        Line(f.sub, 8)
        if shownIcons > 0 then
            local per = math.max(1, math.floor((textW + ICON_GAP) / (ICON + ICON_GAP)))
            for i = 1, shownIcons do
                local b = f.icons[i]
                local col, row = (i - 1) % per, math.floor((i - 1) / per)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD + col * (ICON + ICON_GAP), -(y + row * (ICON + ICON_GAP)))
            end
            y = y + math.ceil(shownIcons / per) * (ICON + ICON_GAP) + 4
        end
        if c.run then
            f.progress:ClearAllPoints()
            f.progress:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
            f.progress:SetWidth(textW)
            f.progress.fill:SetWidth(math.max(1, math.floor((textW - 4) * math.min(1, math.max(0, c.frac or 0)))))
            f.progress.fill:SetShown((c.frac or 0) > 0)
            y = y + 26 + 10
            if c.cur then
                f.curIcon:ClearAllPoints(); f.curIcon:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
                f.cur:ClearAllPoints(); f.cur:SetPoint("LEFT", f.curIcon, "RIGHT", 8, 0); f.cur:SetWidth(textW - 32)
                y = y + 24 + 8
            end
        end
        Line(f.warn, 8)
        Line(f.more, 8)
        f.start:ClearAllPoints(); f.cancel:ClearAllPoints(); f.details:ClearAllPoints(); f.dismiss:ClearAllPoints()
        if c.review or c.dismiss or c.say then
            if c.review then
                f.start:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
                f.cancel:SetPoint("LEFT", f.start, "RIGHT", 6, 0)
            else
                f.dismiss:SetPoint("TOPLEFT", f.detail, "TOPLEFT", PAD, -y)
            end
            if c.hasDetails then
                f.details.text:SetText(detailsOpen and "Hide details" or "Details")
                f.details:SetWidth(math.max(80, #f.details.text:GetText() * 8 + 24))
                f.details:Show()
                f.details:SetPoint("TOPRIGHT", f.detail, "TOPRIGHT", -PAD, -y)
            else
                f.details:Hide()
            end
            y = y + 26 + 4
        else
            f.details:Hide()
        end
        return y + bi - 4
    end
    Dress(PlaceDetail(barW, Fill))
end

---------------------------------------------------------------------------
-- Drawing (coalesced: any number of events is one redraw)
---------------------------------------------------------------------------
local function Open()
    if not (MI.Enabled() and GB.IsOpen()) then return false end
    local frame = _G.GuildBankFrame
    if type(frame) == "table" and frame.IsShown and not frame:IsShown() then return false end   -- (whatever the events said)
    return true
end

local function Draw()
    queued = false
    if not Open() then
        if f then f:Hide() end
        return
    end
    if not Build() then return end
    local st = Compute()
    f:Show()
    f.status:SetText(st.text)
    Tone(f.status, st.tone)
    for _, key in ipairs({ "deposit", "organize", "arrange", "setup", "read", "stop", "go" }) do f[key]:Hide() end
    local busy = st.kind == "run"
    if st.kind == "run" then
        f.stop:Show(); f.stop.text:SetText(st.prog.stopping and "Stopping\226\128\166" or "Stop"); f.stop:SetEnabled(not st.prog.stopping)
        if st.prog.needClick then f.go:Show() end
    elseif st.kind == "setup" then
        f.setup:Show()
    else
        f.arrange:Show()
        f.deposit:Show(); f.organize:Show()
        local locked = st.kind == "reading" or st.kind == "review"
        local d, o = st.deposit or {}, st.organize or {}
        f.deposit:SetEnabled(not locked and d.enabled == true)
        f.organize:SetEnabled(not locked and o.enabled == true)
        f.deposit.why = locked and (st.kind == "review" and "Finish or cancel the review first." or "Reading the bank first.") or d.why
        f.organize.why = locked and (st.kind == "review" and "Finish or cancel the review first." or "Reading the bank first.") or o.why
        if st.read and not locked then f.read:Show() end
    end
    f.status:ClearAllPoints()
    f.status:SetPoint("LEFT", f.bar, "LEFT", PAD, 0)
    local rightmost = busy and (st.prog.needClick and f.go or f.stop) or (st.kind == "setup" and f.setup) or (st.read and f.read:IsShown() and f.read) or f.deposit
    f.status:SetPoint("RIGHT", rightmost, "LEFT", -8, 0)
    Layout(st)
end

function Panel.Refresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        local ok, err = pcall(Draw)
        if not ok then queued = false; R.Fault("magic inventory guild panel", err) end
    end)
end

---------------------------------------------------------------------------
-- The player's actions
---------------------------------------------------------------------------
function Panel.Act(mode)
    if review or awaiting or GR.Busy() or not Open() then return end
    said, dismissed = nil, GR.Last()
    awaiting = mode
    Panel.Refresh()
    -- the tabs are made current first (immediately when they already are), then ONE review is made from them
    P.EnsureFresh(function(ok, state, reason)
        awaiting = nil
        if not Open() then Panel.Refresh() return end
        local rv = GR.Review(mode)
        if rv.ok then
            review, said = rv, nil
        else
            review = nil
            said = rv.refuse.text
            if state == "blocked" and HOLD[reason] and rv.refuse.code == "unread" then said = HOLD[reason] .. "." end
        end
        Panel.Refresh()
    end)
end

function Panel.Cancel()
    review, said = nil, "Nothing was moved."
    Panel.Refresh()
end

function Panel.Dismiss()
    said, dismissed = nil, GR.Last()
    review = nil
    detailsOpen = false
    Panel.Refresh()
end

function Panel.ReadAgain()
    P.EnsureFresh(function() Panel.Refresh() end)
    Panel.Refresh()
end

-- The approval: exactly the review on the panel, or nothing. A changed bank or rules gives a NEW review to read.
function Panel.Start()
    local rv = review
    if not rv or GR.Busy() then return end
    local ok, code, text, fresh = GR.Start(rv)
    if ok then
        review, said, dismissed = nil, nil, nil
        detailsOpen = false
    else
        review = (fresh and fresh.ok) and fresh or nil
        said = text .. (review and " The new plan is below." or "")
    end
    Panel.Refresh()
end

-- read only, for the tests and the diagnostics
function Panel.Review() return review end
function Panel.FrameCount()
    if not f then return 0 end
    return 5 + (MAX_ICONS + 1) + 1 + 11
end
function Panel.Visible() return f ~= nil and f:IsShown() end
function Panel.DetailFrame() return f and f.detail end
-- the progress bar as drawn: { shown, text, fill (pixels), track (pixels) }
function Panel.Progress()
    if not f then return nil end
    return { shown = f.detail:IsShown() and f.progress:IsShown(), text = f.progress.text:GetText(), fill = f.progress.fill:IsShown() and f.progress.fill:GetWidth() or 0,
        track = (f.progress:GetWidth() or 0) - 4 }
end
function Panel.Texts()
    if not f then return nil end
    return { status = f.status:GetText(), title = f.title:GetText(), sub = f.sub:GetText(), warn = f.warn:GetText(), more = f.more:GetText() }
end

---------------------------------------------------------------------------
-- Events: redraw when anything the strip says may have changed
---------------------------------------------------------------------------
GB.Watch(function(what)
    if what == "close" then
        review, awaiting, said, dismissed, detailsOpen = nil, nil, nil, nil, false
    end
    Panel.Refresh()
end)
P.OnUpdate(function() Panel.Refresh() end)
GR.OnUpdate(function(what)
    if what == "done" then
        local res = GR.Last()
        -- the plan changed before anything moved: its new review is put up to read and approve, never started
        if res and res.fresh and res.code == "stale" then
            review, dismissed = res.fresh, res
            said = "The bank, your bags or your rules changed since the review, so nothing was moved. The new plan is below."
        end
    end
    Panel.Refresh()
end)
MI.OnChange(function()
    if review and review.fingerprint then
        -- a rules change withdraws a review that was made from the old rules (Start would refuse it anyway)
        review, said = nil, "Your rules changed, so that review was withdrawn."
    end
    Panel.Refresh()
end)

if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("inventory.guildPanel", { label = "Magic Inventory guild bank panel (frames)", unit = "count", kind = "pool",
        read = function() return Panel.FrameCount() end })
end
