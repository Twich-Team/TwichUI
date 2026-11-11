-- Pointer geometry for the When builder. The virtual cursor helper owns the ghost. The designer owns the
-- rule transaction and supplies the validator, so moving through a menu and dropping use the same model.
local R = TwichUI
local RD = {}
R.RemindersRuleDrag = RD

local function DragKit()
    local inventory = R.MagicInventoryPage
    return inventory and inventory.Drag
end

local function Bounds(frame)
    local l, r, b, t = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if not (l and r and b and t) then return end
    local scale = frame:GetEffectiveScale()
    return l * scale, r * scale, b * scale, t * scale
end

local function At(frame, x, y)
    if not frame:IsVisible() then return end
    local l, r, b, t = Bounds(frame)
    if l and x >= l and x <= r and y >= b and y <= t then return l, r, b, t end
end

function RD.New(clip, validate, commit)
    local drag = { rows = {}, groups = {} }
    local G = R.SettingsWidgets
    local marker = CreateFrame("Frame", nil, UIParent)
    marker:SetFrameStrata("TOOLTIP")
    marker:SetSize(1, 2)
    marker:EnableMouse(false)
    G.Solid(marker, "ARTWORK", G.pal.bronzeText, 1):SetAllPoints()
    marker:Hide()
    drag.marker = marker
    local ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(180, 33)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:EnableMouse(false)
    R.SettingsMaterial.PanelFace(ghost, "walnut")
    R.SettingsMaterial.Edge(ghost, "control", 8):SetBackdropBorderColor(0.72, 0.58, 0.36, 0.9)
    ghost.art = ghost:CreateTexture(nil, "OVERLAY")
    ghost.art:SetPoint("CENTER", ghost, "LEFT", 18, 0)
    ghost.title = G.Text(ghost, "body")
    ghost.title:SetWidth(139)
    ghost.title:SetMaxLines(1)
    ghost.title:SetPoint("LEFT", 36, 0)
    ghost:Hide()
    drag.ghost = ghost

    function drag:ClearTargets()
        self.rows, self.groups = {}, {}
        self:Paint(nil)
    end
    function drag:Row(frame, parent, index, group, fixed)
        self.rows[#self.rows + 1] = { frame = frame, parent = parent, index = index, group = group, fixed = fixed }
    end
    function drag:Group(frame, parent, count, depth)
        self.groups[#self.groups + 1] = { frame = frame, parent = parent, index = count + 1, depth = depth }
    end

    function drag:Find(x, y)
        local source = self.source
        if not source or not At(clip, x, y) then return end
        local target, after
        -- Cards take either insertion position. Group edges take siblings and the interior takes children.
        for _, row in ipairs(self.rows) do
            local l, _, b, t = At(row.frame, x, y)
            if l then
                local edge = 8 * row.frame:GetEffectiveScale()
                if not row.group or (source.raw and (y >= t - edge or y <= b + edge)) then
                    target, after = row, not row.fixed and y < (b + t) / 2
                    break
                end
            end
        end
        if not target then
            for _, group in ipairs(self.groups) do
                if (not target or group.depth > target.depth) and At(group.frame, x, y) then target = group end
            end
        end
        if not target then return end
        local index = target.index + (after and 1 or 0)
        if not validate(source, target.parent, index) then return end
        return { target = target, index = index, after = after, y = y }
    end

    function drag:Paint(drop)
        local previous = self.last and self.last.target.frame
        local current = drop and drop.target.frame
        if previous and previous ~= current and previous.SetDropHot then previous:SetDropHot(false) end
        self.last = drop
        if not drop then marker:Hide(); return end
        if current.SetDropHot then current:SetDropHot(true) end
        local l, r, b, t = Bounds(drop.target.frame)
        local cl, cr, cb, ct = Bounds(clip)
        if not (l and cl) then marker:Hide(); return end
        local y = drop.target.depth and drop.y or (drop.after and b or t)
        local scale = UIParent:GetEffectiveScale()
        marker:ClearAllPoints()
        marker:SetWidth(math.max(1, (math.min(r, cr) - math.max(l, cl)) / scale - 8))
        marker:SetPoint("LEFT", UIParent, "BOTTOMLEFT", math.max(l, cl) / scale + 4, math.max(cb + 2, math.min(ct - 2, y)) / scale)
        marker:Show()
    end

    function drag:Cancel()
        local kit = DragKit()
        if kit and self.source and kit.Source() == self.source then kit.Cancel() end
        self.source = nil
        self:Paint(nil)
    end

    function drag:Start(source, label)
        local kit = DragKit()
        if not (kit and source) then return false end
        self:Cancel()
        self.source = source
        ghost:SetScale(clip:GetEffectiveScale() / UIParent:GetEffectiveScale())
        ghost.title:SetText(label)
        R.RemindersPlain.ApplyArt(ghost.art, source.condition, 24)
        kit.Start({ src = source, ghost = ghost,
            find = function() return self:Find(GetCursorPosition()) end,
            hover = function(target) self:Paint(target) end,
            drop = function(src, target)
                self.source = nil
                commit(src, target.target.parent, target.index)
            end,
            cancel = function() self.source = nil end,
        })
        return true
    end

    function drag:Stop()
        local kit = DragKit()
        if kit and self.source and kit.Source() == self.source then kit.Stop() end
    end

    function drag:Bind(handle, source)
        handle:RegisterForDrag("LeftButton")
        handle:SetScript("OnDragStart", function()
            local payload, label = source()
            self:Start(payload, label)
        end)
        handle:SetScript("OnDragStop", function() self:Stop() end)
    end
    return drag
end
