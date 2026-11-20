-- TwichUI Workshop: small shared chart presentation primitives (W.ChartKit)
-- The pieces of the advanced Market chart (auction/AdvancedChart.lua) that are about presentation and input rather than about market data,
-- written once more for charts that draw something other than a price line. The Market chart itself is not changed. Nothing here knows
-- what a chart shows; nothing is saved; nothing runs per frame except while the pointer is over a chart or a drag is in progress.
--
--   Kit.Strokes(plot, solid)    a polyline drawn as two strokes (a faint bronze support under an antique-gold core) between REGIONS
--                               (the markers): native line objects anchored to the regions, or, when the client refuses them, bounded
--                               runs of solid textures (no rotation or UV behaviour is assumed). :Draw(segments, pw), :Hide(), .backend
--   Kit.Dock(tip, owner, o)     places an inspection card on the screen beside (never over) a chart, or inside its plot on the side away
--                               from the pointer; scale-aware, clamped to the screen
--   Kit.Pointer(hit, h)         hover, a drag with a six-logical-pixel threshold, release anywhere (GLOBAL_MOUSE_UP), right-click reset.
--                               The OnUpdate exists only while the pointer is inside or a drag is open; :Cancel() removes everything.

local R = TwichUI
local W = R.Workshop
local UI = W.UI
local Kit = { MAX_RASTER = 1024, DRAG = 6 }
W.ChartKit = Kit

local function Clamp(v, a, b) return math.max(a, math.min(b, v)) end
Kit.Clamp = Clamp

---------------------------------------------------------------------------
-- Strokes
---------------------------------------------------------------------------
-- solid(color, alpha, sublevel) makes one pooled Texture on the plot. Segments: { x1, y1, x2, y2, a = region, b = region } in plot pixels
-- from the bottom-left; a and b are the textures at the two ends (the native line is anchored to their centres, which removes any
-- offset or effective-scale ambiguity and needs no per-point frames).
function Kit.Strokes(plot, solid)
    local s = { native = {}, raster = {}, mode = nil, backend = "none", used = 0 }
    local K = UI.K
    function s:Hide()
        for _, l in ipairs(self.native) do l:Hide() end
        for _, t in ipairs(self.raster) do t:Hide() end
        self.used = 0
    end
    function s:Count() return #self.native + #self.raster end
    function s:SetMode(mode) self.mode = mode end
    local function Raster(self, segments, pw)
        local nl = 0
        local step = math.max(1, pw / Kit.MAX_RASTER)
        for _, v in ipairs(segments) do
            local dx = v.x2 - v.x1
            local first, last = math.floor(v.x1 / step), math.ceil(v.x2 / step) - 1
            local runX, runY, runH, runEnd
            local function Flush()
                if not runX then return end
                nl = nl + 1
                local p = self.raster[nl]
                if not p then p = solid(K.bronzeText, 0.9, 5); self.raster[nl] = p end
                p:ClearAllPoints(); p:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", runX, runY)
                p:SetSize(math.max(0.5, runEnd - runX), runH); p:Show()
            end
            for col = first, last do
                local x0, x1 = math.max(v.x1, col * step), math.min(v.x2, (col + 1) * step)
                local y0 = math.floor(v.y1 + (x0 - v.x1) / math.max(0.001, dx) * (v.y2 - v.y1) + 0.5)
                local y1 = math.floor(v.y1 + (x1 - v.x1) / math.max(0.001, dx) * (v.y2 - v.y1) + 0.5)
                local y, height = math.min(y0, y1) - 0.625, math.abs(y1 - y0) + 1.25
                if runX and (y ~= runY or height ~= runH) then Flush(); runX = nil end
                if not runX then runX, runY, runH = x0, y, height end
                runEnd = x1
            end
            Flush()
        end
        for i = nl + 1, #self.raster do self.raster[i]:Hide() end
        self.used = nl
    end
    -- Returns "native", "raster" or "none".
    function s:Draw(segments, pw)
        for _, l in ipairs(self.native) do l:Hide() end
        if #segments == 0 then
            for _, t in ipairs(self.raster) do t:Hide() end
            self.used, self.backend = 0, "none"
            return "none"
        end
        local useNative = self.mode ~= "raster" and type(plot.CreateLine) == "function"
        if useNative then
            local ok = pcall(function()
                local count = 0
                for _, v in ipairs(segments) do
                    for layer = 1, 2 do
                        count = count + 1
                        local line = self.native[count]
                        if not line then
                            line = plot:CreateLine(nil, "ARTWORK", nil, layer == 1 and 4 or 5)
                            assert(line and line.SetStartPoint and line.SetEndPoint and line.SetThickness, "line API unavailable")
                            self.native[count] = line
                        end
                        local color = layer == 1 and K.bronzeLo or K.bronzeText
                        line:SetColorTexture(color[1], color[2], color[3], layer == 1 and 0.30 or 0.95)
                        line:SetThickness(layer == 1 and 3 or 1.35)
                        line:SetStartPoint("CENTER", v.a, 0, 0)
                        line:SetEndPoint("CENTER", v.b, 0, 0)
                        line:Show()
                    end
                end
                for i = count + 1, #self.native do self.native[i]:Hide() end
                self.used = count
            end)
            if ok then
                for _, t in ipairs(self.raster) do t:Hide() end
                self.backend = "native"
                return "native"
            end
            for _, l in ipairs(self.native) do l:Hide() end
            self.mode = "raster"   -- the client refused the line object: the portable drawing from now on
        end
        Raster(self, segments, pw)
        self.backend = "raster"
        return "raster"
    end
    return s
end

---------------------------------------------------------------------------
-- Docking an inspection card
---------------------------------------------------------------------------
-- tip: the card (parented to UIParent so no scroll frame clips it). owner: the chart frame. o.plot / o.side: where to sit inside the plot
-- ("left" or "right": the half the pointer is NOT in) when there is no room outside; o.inside = true prefers that over the screen edge.
function Kit.Dock(tip, owner, o)
    o = o or {}
    local scale = owner:GetEffectiveScale() or 1
    local screenScale = UIParent:GetEffectiveScale() or 1
    tip:SetScale(scale / screenScale)
    local w = tip:GetWidth() or 300
    local right = (UIParent:GetRight() or UIParent:GetWidth() or 1920) * screenScale / scale
    local top = (UIParent:GetTop() or UIParent:GetHeight() or 1080) * screenScale / scale
    local need = w + 16
    tip:ClearAllPoints()
    if not o.inside then
        if right - (owner:GetRight() or right) >= need then tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0) return "right"
        elseif (owner:GetLeft() or 0) >= need then tip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -12, 0) return "left"
        elseif top - (owner:GetTop() or top) >= (tip:GetHeight() or 120) + 16 then tip:SetPoint("BOTTOM", owner, "TOP", 0, 12) return "top" end
    end
    local plot = o.plot or owner
    if o.side == "left" then tip:SetPoint("TOPLEFT", plot, "TOPLEFT", 10, -10) else tip:SetPoint("TOPRIGHT", plot, "TOPRIGHT", -10, -10) end
    return "inside"
end

---------------------------------------------------------------------------
-- Pointer: hover, drag to select, right-click reset
---------------------------------------------------------------------------
-- hit: one transparent Button over the plot. h = {
--   ready()        -> true when there is something to inspect
--   x()            -> the pointer's x in plot pixels (unclamped)
--   width()        -> the plot's width
--   hover(x)       the pointer is over the plot at x (called while inside and not dragging)
--   dragging(x0, x)  a drag is open (the selection band)
--   leave()        the pointer left (inspection hides; an open drag survives)
--   commit(x0, x1) a drag of at least Kit.DRAG pixels ended (left to right or right to left)
--   reset()        right-click
--   cancelled()    everything was cancelled (hidden, replaced)
-- }
function Kit.Pointer(hit, h)
    local p = { inside = false, drag = nil }
    local function Finish()
        local from = p.drag
        if not from then return end
        local x = Clamp(h.x(), 0, h.width())
        p.drag = nil
        hit:UnregisterEvent("GLOBAL_MOUSE_UP")
        if math.abs(x - from) >= Kit.DRAG then h.commit(from, x) end
        if h.dragging then h.dragging(nil) end
        if not p.inside then hit:SetScript("OnUpdate", nil); if h.leave then h.leave() end end
    end
    local function Update()
        if not h.ready() then return end
        local x = h.x()
        if p.drag then
            h.dragging(p.drag, Clamp(x, 0, h.width()))
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then Finish() end
        elseif p.inside then
            h.hover(Clamp(x, 0, h.width()))
        end
    end
    function p:Cancel()
        hit:SetScript("OnUpdate", nil)
        hit:UnregisterEvent("GLOBAL_MOUSE_UP")
        self.inside, self.drag = false, nil
        if h.dragging then h.dragging(nil) end
        if h.leave then h.leave() end
    end
    -- After a redraw or a replacement of the data: a stationary pointer takes inspection back without waiting for a new OnEnter
    function p:Resume()
        if h.ready() and hit:IsShown() and hit:IsMouseOver() == true then
            self.inside = true
            hit:SetScript("OnUpdate", Update)
            Update()
        elseif self.inside and h.ready() then
            Update()
        end
    end
    hit:SetScript("OnEnter", function()
        if not h.ready() then return end
        p.inside = true
        hit:SetScript("OnUpdate", Update)
        Update()
    end)
    hit:SetScript("OnLeave", function()
        p.inside = false
        if h.leave then h.leave() end
        if not p.drag then hit:SetScript("OnUpdate", nil) end
    end)
    hit:SetScript("OnMouseDown", function(_, button)
        if h.ready() and button == "LeftButton" then
            if h.leave then h.leave() end
            p.drag = Clamp(h.x(), 0, h.width())
            hit:RegisterEvent("GLOBAL_MOUSE_UP")
            hit:SetScript("OnUpdate", Update)
        end
    end)
    hit:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            p:Cancel()
            h.reset()
            p:Resume()
        elseif button == "LeftButton" then
            Finish()
        end
    end)
    hit:SetScript("OnEvent", function(_, event, button)
        if event == "GLOBAL_MOUSE_UP" and button == "LeftButton" then Finish() end
    end)
    return p
end
