-- TwichUI Layout Setup: the miniature preview
-- A scene (Scene.lua: the engine's resolved screen geometry for the chosen layout, with the pieces inside it) drawn to
-- scale on a frame whose proportions are those of this player's game viewport (UIParent's width and height in its own
-- units). Each managed component is a box at its resolved centre offset and size, with sample shapes inside (text lines,
-- bars, a minimap square); the pieces inside the unit frames and bars block are drawn at their resolved places and sample
-- sizes. They are illustrations, not EllesmereUI's real frames, and the preview says so. Boxes and pieces are made once
-- and moved on every Set, so drawing again after a pick, a layout choice or a scenario makes nothing new (the number of
-- ids that can ever exist is bounded by the package). Nothing here touches the game's state: it reads a scene and draws.
--
--   Preview.Build(parent, handlers) -> view     view.frame is the viewport, view.caption the line under it
--     handlers = { scenario = fn(id), overlay = fn() } for the controls under the viewport
--   view:Set(scene, accent, issues)             accent = { r, g, b }; re-lays every box out. Records what it drew in view.drawn
--   view:Controls(scenario, blocked)            marks the scenario shown, and enables the full-size button or says why not
--   view:Clear()                                hides the boxes (no scene to draw)
--   view:Track(on)                              the sample tooltip of "Follow mouse" follows the pointer while it is over the miniature
--                                               (a throttled OnUpdate that exists only then; off, the sample sits at rest)
--   Preview.MAX_W, Preview.MAX_H                the largest the viewport is drawn

local R = TwichUI
local WZ = R.LayoutWizard
local Pv = {}
WZ.Preview = Pv

Pv.MAX_W, Pv.MAX_H = 330, 200
Pv.tracking = 0   -- miniatures whose sample tooltip is following the pointer now (0 or 1)
R.Perf.Gauge("layoutwizard.preview.follow", { label = "Layout setup preview: pointer tracking running (0 unless the pointer is over the sample)", unit = "count", kind = "listeners",
    group = "layouts", read = function() return Pv.tracking end })
Pv.CAPTION = "An illustration: the layout's places for your screen, to scale, with sample shapes in place of the real frames. The real look is EllesmereUI's and TwichUI's own."

-- Sample shapes in a component's box, as fractions of it: { x, y, w, h, role }. role: "line" (a text line), "bar" (accent),
-- "dot" (accent), "quiet" (a plain strip). Only for the components whose inside is sample content; the unit frames and
-- bars block and the focus frame are drawn from their resolved pieces instead.
local SAMPLES = {
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

local function Box(view, kind)
    local L, pal = Look(), Look().pal
    local box = CreateFrame("Frame", nil, view.frame, "BackdropTemplate")
    L.Surface(box, pal.surface, 0.9, pal.control, 1)
    box.label = L.Text(box, "meta")
    box.label:SetPoint("TOPLEFT", 3, -2)
    box.pieces = {}
    for _, s in ipairs(SAMPLES[kind] or {}) do
        local t = box:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(1, 1, 1, 1)
        box.pieces[#box.pieces + 1] = { tex = t, spec = s }
    end
    view.made = view.made + 1
    return box
end

-- How a piece of a given kind is tinted: { colour key, alpha }
local ROLE = { unit = { "bronzeText", 0.55 }, cast = { "accent", 0.75 }, bar = { "stone", 0.45 }, party = { "bronzeText", 0.45 },
    marker = { "teal", 0.85 } }

local function Draw(view, scene, accent)
    local pal = Look().pal
    local sw, sh = scene.screen.w, scene.screen.h
    local sc = math.min(Pv.MAX_W / sw, Pv.MAX_H / sh)
    local pw, ph = sw * sc, sh * sc
    view.frame:SetSize(pw, ph)
    view.frame:Show()
    local acc = Rgb(accent, pal.teal)
    local drawn = { scale = sc, w = pw, h = ph, boxes = {}, elements = {}, aspect = sw / sh, scenario = scene.scenario, variant = scene.variant }
    for _, c in ipairs(scene.components) do
        local box = view.boxes[c.id]
        if not box then box = Box(view, c.kind); view.boxes[c.id] = box end
        local r = c.rect
        local w, h = math.max(1, r.w * sc), math.max(1, r.h * sc)
        box:ClearAllPoints()
        box:SetPoint("CENTER", view.frame, "CENTER", r.x * sc, r.y * sc)
        box:SetSize(w, h)
        local edge = c.troubled and pal.danger.border or acc
        box:SetBackdropBorderColor(edge[1], edge[2], edge[3], c.troubled and 1 or 0.9)
        box.label:SetText(c.label .. (c.troubled and " !" or "") .. (c.applied and " (not applied)" or ""))
        box.label:SetShown(w >= 46 and h >= 16)
        box:Show()
        for _, p in ipairs(box.pieces) do
            local x, y, fw, fh, role = unpack(p.spec)
            local col, a = pal.stone, 0.35
            if role == "bar" or role == "dot" then col, a = acc, 0.75
            elseif role == "quiet" then col, a = pal.control, 0.55 end
            p.tex:SetColorTexture(col[1], col[2], col[3], a)
            p.tex:ClearAllPoints()
            p.tex:SetPoint("TOPLEFT", box, "TOPLEFT", x * w, -y * h)
            p.tex:SetSize(math.max(1, fw * w), math.max(1, fh * h))
        end
        drawn.boxes[c.id] = { x = r.x * sc, y = r.y * sc, w = w, h = h, troubled = c.troubled }
    end
    for id, box in pairs(view.boxes) do
        if not drawn.boxes[id] then box:Hide() end
    end
    -- the pieces inside the components, at their resolved places
    for _, e in ipairs(scene.elements) do
        local t = view.elems[e.id]
        if not t then
            t = view.frame:CreateTexture(nil, "OVERLAY")
            view.elems[e.id] = t
            view.made = view.made + 1
        end
        local role = ROLE[e.kind] or ROLE.bar
        local col = role[1] == "accent" and acc or pal[role[1]] or pal.stone
        t:SetColorTexture(col[1], col[2], col[3], role[2])
        local w, h = math.max(1, e.rect.w * sc), math.max(1, e.rect.h * sc)
        t:ClearAllPoints()
        t:SetPoint("CENTER", view.frame, "CENTER", e.rect.x * sc, e.rect.y * sc)
        t:SetSize(w, h)
        t:Show()
        drawn.elements[e.id] = { x = e.rect.x * sc, y = e.rect.y * sc, w = w, h = h }
    end
    for id, t in pairs(view.elems) do
        if not drawn.elements[id] then t:Hide() end
    end
    -- the sample tooltip
    if scene.tooltip then
        local tip = view.boxes.tooltip
        if not tip then tip = Box(view, "tooltip"); view.boxes.tooltip = tip end
        local r = scene.tooltip.rect
        local w, h = math.max(1, r.w * sc), math.max(1, r.h * sc)
        tip:ClearAllPoints()
        tip:SetPoint("CENTER", view.frame, "CENTER", r.x * sc, r.y * sc)
        tip:SetSize(w, h)
        tip:SetBackdropBorderColor(pal.stone[1], pal.stone[2], pal.stone[3], 1)
        tip.label:SetText(scene.tooltip.follow and "Follows mouse" or "Tooltip")
        tip.label:SetShown(w >= 30 and h >= 12)
        tip:Show()
        drawn.tooltip = { x = r.x * sc, y = r.y * sc, w = w, h = h, follow = scene.tooltip.follow }
        if scene.tooltip.follow then
            local cur = scene.tooltip.cursor
            view.follow = { rest = { x = r.x * sc, y = r.y * sc }, w = w, h = h, cursor = { x = cur.x * sc, y = cur.y * sc }, pw = pw, ph = ph }
            if not view.mark then
                view.mark = view.frame:CreateTexture(nil, "OVERLAY")
                view.mark:SetSize(5, 5)
                view.mark:SetColorTexture(pal.text[1], pal.text[2], pal.text[3], 1)
                view.made = view.made + 1
            end
            view.mark:ClearAllPoints()
            view.mark:SetPoint("CENTER", view.frame, "CENTER", cur.x * sc, cur.y * sc)
            view.mark:Show()
        end
    elseif view.boxes.tooltip then
        view.boxes.tooltip:Hide()
    end
    if not (scene.tooltip and scene.tooltip.follow) then
        view.follow = nil
        if view.mark then view.mark:Hide() end
        view:Track(false)
    end
    view.drawn = drawn
end

function Pv.Build(parent, handlers)
    handlers = handlers or {}
    local L, pal = Look(), Look().pal
    local view = { boxes = {}, elems = {}, made = 0, tabs = {} }
    view.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    L.Surface(view.frame, pal.well, 0.95, pal.bronzeLo, 0.9)
    view.frame:SetSize(Pv.MAX_W, Pv.MAX_H)
    view.tag = L.Tag(view.frame, "Illustration")
    view.tag:SetPoint("BOTTOMRIGHT", view.frame, "TOPRIGHT", 0, 3)

    -- the controls: which scenario the sample shows, and the full-size preview
    view.controls = CreateFrame("Frame", nil, parent)
    view.controls:SetSize(Pv.MAX_W, 62)
    view.controls:SetPoint("TOPLEFT", view.frame, "BOTTOMLEFT", 0, -8)
    local x = 0
    local WIDTHS = { solo = 52, target = 62, party = 58, objectives = 88, tooltip = 66 }
    for _, sc in ipairs(WZ.Scene.SCENARIOS) do
        local w = WIDTHS[sc.id] or 64
        local tab = L.Tab(view.controls, sc.short, w, function() if handlers.scenario then handlers.scenario(sc.id) end end)
        tab:SetPoint("TOPLEFT", x, 0)
        R.Interact.Tip(tab, sc.label, sc.hint)
        view.tabs[sc.id] = tab
        x = x + w + 2
    end
    view.full = L.Button(view.controls, "See it full size", 150, "secondary", function() if handlers.overlay then handlers.overlay() end end)
    view.full:SetHeight(24)
    view.full:SetPoint("TOPLEFT", 0, -34)
    R.Interact.Tip(view.full, "See it full size", "Shows this layout over your screen at its real size and place, with sample content. Your interface is dimmed behind it, not hidden or moved, and nothing is applied. Needs you out of combat.")
    view.fullNote = L.Text(view.controls, "small")
    view.fullNote:SetWidth(Pv.MAX_W - 160)
    view.fullNote:SetWordWrap(true)
    view.fullNote:SetPoint("LEFT", view.full, "RIGHT", 8, 0)

    view.caption = L.Text(parent, "small")
    view.caption:SetWidth(Pv.MAX_W)
    view.caption:SetWordWrap(true)
    view.caption:SetText(Pv.CAPTION)
    view.caption:SetPoint("TOPLEFT", view.controls, "BOTTOMLEFT", 0, -2)
    view.issues = L.Text(parent, "small")
    view.issues:SetWidth(Pv.MAX_W)
    view.issues:SetWordWrap(true)
    view.issues:SetPoint("TOPLEFT", view.caption, "BOTTOMLEFT", 0, -6)
    view.issues:SetTextColor(pal.danger.text[1], pal.danger.text[2], pal.danger.text[3])
    view.notes = L.Text(parent, "small")
    view.notes:SetWidth(Pv.MAX_W)
    view.notes:SetWordWrap(true)
    view.notes:SetPoint("TOPLEFT", view.issues, "BOTTOMLEFT", 0, -6)

    -- The pointer sample of Follow mouse. Isolated: it moves only this miniature's own sample box and never reads or changes the
    -- game's tooltip. While the pointer is outside the miniature (or the page is hidden) the sample sits at its rest place.
    function view:RestTip()
        local f, tip = self.follow, self.boxes.tooltip
        if not (f and tip) then return end
        tip:ClearAllPoints()
        tip:SetPoint("CENTER", self.frame, "CENTER", f.rest.x, f.rest.y)
        if self.mark then
            self.mark:ClearAllPoints()
            self.mark:SetPoint("CENTER", self.frame, "CENTER", f.cursor.x, f.cursor.y)
        end
    end
    function view:MoveTip()
        local f, tip = self.follow, self.boxes.tooltip
        if not (f and tip) then return end
        local frame = self.frame
        local px, py = GetCursorPosition()
        local es = frame:GetEffectiveScale()
        local cx, cy = frame:GetCenter()
        if not (px and es and es > 0 and cx and cy) then return end
        local dx, dy = px / es - cx, py / es - cy
        dx = math.max(-f.pw / 2, math.min(f.pw / 2, dx))
        dy = math.max(-f.ph / 2, math.min(f.ph / 2 - f.h, dy))
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOM", frame, "CENTER", dx, dy)
        if self.mark then
            self.mark:ClearAllPoints()
            self.mark:SetPoint("CENTER", frame, "CENTER", dx, dy)
        end
    end
    function view:Track(on)
        local frame = self.frame
        if on and self.follow and self.boxes.tooltip and frame:IsShown() then
            if self.tracking then return end
            self.tracking = true
            Pv.tracking = Pv.tracking + 1
            local acc = 0
            frame:SetScript("OnUpdate", function(_, dt)
                acc = acc + (dt or 0)
                if acc < 0.03 then return end   -- about 30 moves a second, only while the pointer is over the miniature
                acc = 0
                local pt = R.Perf.on and R.Perf.Start("layoutwizard.preview.follow")
                self:MoveTip()
                if pt then R.Perf.Stop(pt) end
            end)
        elseif self.tracking then
            self.tracking = false
            Pv.tracking = Pv.tracking - 1
            frame:SetScript("OnUpdate", nil)
            self:RestTip()
        end
    end
    view.frame:EnableMouse(true)
    view.frame:SetScript("OnEnter", function() view:Track(true) end)
    view.frame:SetScript("OnLeave", function() view:Track(false) end)
    view.frame:SetScript("OnHide", function() view:Track(false) end)

    function view:Controls(scenario, blocked)
        for id, tab in pairs(self.tabs) do tab:SetSelected(id == scenario) end
        self.full:SetEnabled(blocked == nil)
        self.fullNote:SetText(blocked or "")
        self.fullNote:SetShown(blocked ~= nil)
    end
    function view:Set(scene, accent, issues)
        if not scene then self:Clear() return end
        R.Perf.Call("layoutwizard.preview", Draw, self, scene, accent)
        self.issues:SetText(issues and #issues > 0 and ("Doesn't fit: " .. table.concat(issues, " ")) or "")
        self.issues:SetShown(issues ~= nil and #issues > 0)
        local unapplied = {}
        for _, c in ipairs(scene.components) do
            if c.applied then unapplied[#unapplied + 1] = c.label end
        end
        self.notes:SetText(#unapplied > 0 and ("Shown, but not applied: " .. table.concat(unapplied, ", ") .. ". EllesmereUI leaves it to Blizzard's Edit Mode.") or "")
        self.notes:SetShown(#unapplied > 0)
        self.caption:Show()
    end
    function view:Clear()
        self.follow = nil
        if self.mark then self.mark:Hide() end
        self:Track(false)
        for _, box in pairs(self.boxes) do box:Hide() end
        for _, t in pairs(self.elems) do t:Hide() end
        self.drawn = nil
        self.issues:SetText("")
        self.issues:Hide()
        self.notes:SetText("")
        self.notes:Hide()
        self.frame:SetSize(Pv.MAX_W, Pv.MAX_H)
    end
    return view
end
