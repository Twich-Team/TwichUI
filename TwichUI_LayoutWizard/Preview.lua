-- TwichUI Layout Setup: the miniature preview
-- The package's resolved screen geometry (TwichUI_Layouts' Geometry.Resolve, the resolver the plan itself uses) drawn to
-- scale on a frame whose proportions are those of this player's game viewport (UIParent's width and height in its own
-- units). Each managed component is a box at its resolved centre offset and size, with sample shapes inside (text lines,
-- bars, a minimap square): illustrations, not EllesmereUI's real frames, and the preview says so. Boxes are made once and
-- moved on every Set, so drawing again after a pick or a screen change makes nothing new. Nothing here touches the game's
-- state: it reads a geometry and draws.
--
--   Preview.Build(parent) -> view        view.frame is the viewport, view.caption the line under it
--   view:Set(geometry, accent)           accent = { r, g, b }; re-lays every box out. Records what it drew in view.drawn
--   view:Clear()                         hides the boxes (no geometry to draw)
--   Preview.MAX_W, Preview.MAX_H         the largest the viewport is drawn

local R = TwichUI
local WZ = R.LayoutWizard
local Pv = {}
WZ.Preview = Pv

Pv.MAX_W, Pv.MAX_H = 330, 200
Pv.CAPTION = "An illustration: the layout's places for your screen, to scale, with sample shapes in place of the real frames. The real look is EllesmereUI's and TwichUI's own."

-- Sample shapes in a box, as fractions of it: { x, y, w, h, role }. role: "line" (a text line), "bar" (accent), "frame"
-- (a unit frame), "dot" (accent), "quiet" (a plain strip).
local SAMPLES = {
    central = {
        { 0.08, 0.30, 0.30, 0.06, "frame" }, { 0.62, 0.30, 0.30, 0.06, "frame" },
        { 0.32, 0.42, 0.36, 0.025, "bar" },
        { 0.12, 0.66, 0.76, 0.06, "quiet" }, { 0.12, 0.76, 0.76, 0.06, "quiet" }, { 0.12, 0.86, 0.76, 0.06, "quiet" },
    },
    focus = { { 0.06, 0.30, 0.88, 0.25, "frame" }, { 0.06, 0.66, 0.60, 0.12, "bar" } },
    chat = {
        { 0.05, 0.06, 0.30, 0.10, "quiet" },
        { 0.05, 0.26, 0.80, 0.06, "line" }, { 0.05, 0.40, 0.62, 0.06, "line" }, { 0.05, 0.54, 0.74, 0.06, "line" }, { 0.05, 0.68, 0.45, 0.06, "line" },
    },
    meter = { { 0.06, 0.20, 0.88, 0.12, "bar" }, { 0.06, 0.40, 0.62, 0.12, "bar" }, { 0.06, 0.60, 0.44, 0.12, "bar" }, { 0.06, 0.80, 0.28, 0.12, "bar" } },
    minimap = { { 0.42, 0.42, 0.16, 0.16, "dot" } },
    objectives = { { 0.08, 0.10, 0.60, 0.05, "line" }, { 0.08, 0.30, 0.80, 0.05, "line" }, { 0.08, 0.45, 0.55, 0.05, "line" }, { 0.08, 0.65, 0.75, 0.05, "line" } },
    notifications = { { 0.08, 0.30, 0.84, 0.14, "line" }, { 0.2, 0.70, 0.60, 0.06, "bar" } },
}

local function Look() return R.Look end

local function Rgb(c, fallback)
    if type(c) == "table" and c[1] then return c end
    if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    return fallback
end

local function Box(view, id)
    local L, pal = Look(), Look().pal
    local box = CreateFrame("Frame", nil, view.frame, "BackdropTemplate")
    L.Surface(box, pal.surface, 0.9, pal.control, 1)
    box.label = L.Text(box, "meta")
    box.label:SetPoint("TOPLEFT", 3, -2)
    box.pieces = {}
    for _, s in ipairs(SAMPLES[id] or {}) do
        local t = box:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 1)
        box.pieces[#box.pieces + 1] = { tex = t, spec = s }
    end
    view.made = view.made + 1
    return box
end

local function Draw(view, geo, accent)
    local pal = Look().pal
    local sw, sh = geo.screen.w, geo.screen.h
    local sc = math.min(Pv.MAX_W / sw, Pv.MAX_H / sh)
    local pw, ph = sw * sc, sh * sc
    view.frame:SetSize(pw, ph)
    view.frame:Show()
    local acc = Rgb(accent, pal.teal)
    local troubled = {}
    for _, d in ipairs(geo.diagnostics or {}) do
        if d.code == "overlap" or d.code == "offscreen" then troubled[d.id] = true if d.other then troubled[d.other] = true end end
    end
    local drawn = { scale = sc, w = pw, h = ph, boxes = {}, aspect = sw / sh }
    for _, id in ipairs(geo.order) do
        local c = geo.components[id]
        if c.managed and c.rect.w > 0 and c.rect.h > 0 then
            local box = view.boxes[id]
            if not box then box = Box(view, id); view.boxes[id] = box end
            local r = c.rect
            local w, h = math.max(1, r.w * sc), math.max(1, r.h * sc)
            box:ClearAllPoints()
            box:SetPoint("CENTER", view.frame, "CENTER", r.x * sc, r.y * sc)
            box:SetSize(w, h)
            local edge = troubled[id] and pal.danger.border or acc
            box:SetBackdropBorderColor(edge[1], edge[2], edge[3], troubled[id] and 1 or 0.9)
            local name = (c.label or id) .. (troubled[id] and " !" or "") .. (c.applied and " (not applied)" or "")
            box.label:SetText(name)
            box.label:SetShown(w >= 46 and h >= 16)
            box:Show()
            for _, p in ipairs(box.pieces) do
                local x, y, fw, fh, role = unpack(p.spec)
                local col = pal.stone
                local a = 0.35
                if role == "bar" or role == "dot" then col, a = acc, 0.75
                elseif role == "frame" then col, a = pal.bronzeText, 0.45
                elseif role == "quiet" then col, a = pal.control, 0.55 end
                p.tex:SetColorTexture(col[1], col[2], col[3], a)
                p.tex:ClearAllPoints()
                p.tex:SetPoint("TOPLEFT", box, "TOPLEFT", x * w, -y * h)
                p.tex:SetSize(math.max(1, fw * w), math.max(1, fh * h))
            end
            drawn.boxes[id] = { x = r.x * sc, y = r.y * sc, w = w, h = h, troubled = troubled[id] or nil }
        end
    end
    for id, box in pairs(view.boxes) do
        if not drawn.boxes[id] then box:Hide() end
    end
    view.drawn = drawn
end

function Pv.Build(parent)
    local L, pal = Look(), Look().pal
    local view = { boxes = {}, made = 0 }
    view.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    L.Surface(view.frame, pal.well, 0.95, pal.bronzeLo, 0.9)
    view.frame:SetSize(Pv.MAX_W, Pv.MAX_H)
    view.tag = L.Tag(view.frame, "Illustration")
    view.tag:SetPoint("BOTTOMRIGHT", view.frame, "TOPRIGHT", 0, 3)
    view.caption = L.Text(parent, "small")
    view.caption:SetWidth(Pv.MAX_W)
    view.caption:SetWordWrap(true)
    view.caption:SetText(Pv.CAPTION)
    view.caption:SetPoint("TOPLEFT", view.frame, "BOTTOMLEFT", 0, -6)
    view.issues = L.Text(parent, "small")
    view.issues:SetWidth(Pv.MAX_W)
    view.issues:SetWordWrap(true)
    view.issues:SetPoint("TOPLEFT", view.caption, "BOTTOMLEFT", 0, -6)
    view.issues:SetTextColor(pal.danger.text[1], pal.danger.text[2], pal.danger.text[3])
    view.notes = L.Text(parent, "small")
    view.notes:SetWidth(Pv.MAX_W)
    view.notes:SetWordWrap(true)
    view.notes:SetPoint("TOPLEFT", view.issues, "BOTTOMLEFT", 0, -6)

    function view:Set(geo, accent, issues)
        if not geo then self:Clear() return end
        R.Perf.Call("layoutwizard.preview", Draw, self, geo, accent)
        self.issues:SetText(issues and #issues > 0 and ("Doesn't fit: " .. table.concat(issues, " ")) or "")
        self.issues:SetShown(issues ~= nil and #issues > 0)
        local unapplied = {}
        for _, id in ipairs(geo.order) do
            local c = geo.components[id]
            if c.managed and c.applied then unapplied[#unapplied + 1] = c.label or id end
        end
        self.notes:SetText(#unapplied > 0 and ("Shown, but not applied: " .. table.concat(unapplied, ", ") .. ". EllesmereUI leaves it to Blizzard's Edit Mode.") or "")
        self.notes:SetShown(#unapplied > 0)
        self.caption:Show()
    end
    function view:Clear()
        for _, box in pairs(self.boxes) do box:Hide() end
        self.drawn = nil
        self.issues:SetText("")
        self.issues:Hide()
        self.notes:SetText("")
        self.notes:Hide()
        self.frame:SetSize(Pv.MAX_W, Pv.MAX_H)
    end
    return view
end
