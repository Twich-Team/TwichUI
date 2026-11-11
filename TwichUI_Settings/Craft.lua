-- Opt-in painted settings components. Artwork owns relief; native frames own input and geometry.
-- No page names, saved data, timers or configuration behavior belong here.
local R = TwichUI
local C = {}
R.SettingsCraft = C
local DIR = R.PATH .. [[media\style-v2\craft\]]

-- Fixed UI corners with independent horizontal/vertical source cuts. Edges stretch only along their length.
function C.Sheet(host, skin, opts)
    opts = opts or {}
    local frame = skin == "frame"
    local selected = skin:find("selection", 1, true) ~= nil or skin:find("segment", 1, true) ~= nil
    local chip = skin:find("chip", 1, true) ~= nil
    local u = chip and 1 / 4 or frame and 1 / 8 or selected and 1 / 8 or 1 / 16
    local v = chip and 1 / 2 or frame and 1 / 8 or selected and 3 / 8 or 1 / 4
    local corner = opts.corner or (frame and 24 or 8)
    local ins = opts.inset or 0
    local left, top, right, bottom
    if type(ins) == "table" then left, top, right, bottom = ins[1], ins[2], ins[3], ins[4]
    else left, top, right, bottom = ins, ins, ins, ins end
    local uvx, uvy = { 0, u, 1 - u, 1 }, { 0, v, 1 - v, 1 }
    local x = { { "LEFT", left }, { "LEFT", left + corner }, { "RIGHT", -(right + corner) }, { "RIGHT", -right } }
    local y = { { "TOP", -top }, { "TOP", -(top + corner) }, { "BOTTOM", bottom + corner }, { "BOTTOM", bottom } }
    local group = { parts = {}, skin = nil }
    for row = 1, 3 do
        for col = 1, 3 do
            local texture = host:CreateTexture(nil, opts.layer or "ARTWORK", nil, opts.sub or 1)
            texture:SetTexCoord(uvx[col], uvx[col + 1], uvy[row], uvy[row + 1])
            texture:SetPoint("TOPLEFT", host, y[row][1] .. x[col][1], x[col][2], y[row][2])
            texture:SetPoint("BOTTOMRIGHT", host, y[row + 1][1] .. x[col + 1][1], x[col + 1][2], y[row + 1][2])
            group.parts[#group.parts + 1] = texture
        end
    end
    function group:SetSkin(value)
        if value == self.skin then return end
        self.skin = value
        for _, texture in ipairs(self.parts) do texture:SetTexture(DIR .. value .. ".tga") end
    end
    function group:SetShown(on) for _, texture in ipairs(self.parts) do texture:SetShown(on and true or false) end end
    function group:SetAlpha(alpha) for _, texture in ipairs(self.parts) do texture:SetAlpha(alpha) end end
    function group:SetTint(r, g, b, alpha)
        for _, texture in ipairs(self.parts) do texture:SetVertexColor(r, g, b, alpha or 1) end
    end
    function group:Show() self:SetShown(true) end
    function group:Hide() self:SetShown(false) end
    group:SetSkin(skin)
    return group
end

function C.Frame(host)
    return C.Sheet(host, "frame", { layer = "OVERLAY", sub = 5 })
end

-- The original shell is kept for restoration. SetAlpha avoids its resize hook reshowing old rails.
function C.LegacyRails(shell, shown)
    for _, set in ipairs({ shell.corner or {}, shell.edge or {} }) do
        for _, texture in pairs(set) do texture:SetAlpha(shown and 1 or 0) end
    end
end

function C.Control(control, kind, when)
    if control.twichCraft then return control.twichCraft end
    local field = kind == "field" or kind == "dropdown" or kind == "drop" or kind == "target"
    local primary = kind == "primary" or kind == "confirmation"
    local danger = kind == "danger"
    local selectedFamily = kind == "segment"
    -- One silhouette per family, including disabled/pressed states. Selection has its own painted source.
    local sheet = C.Sheet(control, kind == "chip" and "chip" or selectedFamily and "selection" or field and "field" or "button",
        { layer = "ARTWORK", sub = 4, corner = kind == "chip" and 12 or 8 })
    control.twichCraft = sheet
    if kind == "target" then
        -- Let a caller's dashed insertion outline carry the edge, rather than a solid button rim.
        for i, texture in ipairs(sheet.parts) do texture:SetAlpha(i == 5 and 0.55 or 0) end
        sheet.parts[5]:ClearAllPoints()
        sheet.parts[5]:SetAllPoints(control)
    end
    local bevel = control.twichLook and control.twichLook.bevel
    local function Bevel(alpha)
        for _, part in pairs(bevel or {}) do
            if part.SetAlpha then part:SetAlpha(alpha) else for _, texture in pairs(part) do texture:SetAlpha(alpha) end end
        end
    end
    local bg = control.GetBackdropColor and { control:GetBackdropColor() } or {}
    local edge = control.GetBackdropBorderColor and { control:GetBackdropBorderColor() } or {}
    local originalInk = kind == "field" and { control:GetTextColor() } or {}
    local over, down, wasActive = false, false, false
    local function Paint()
        if when and not when() then
            sheet:Hide()
            if wasActive then
                Bevel(1)
                if control.Repaint then control:Repaint()
                else
                    local pal = R.SettingsWidgets.pal
                    control:SetBackdropColor(unpack(bg[1] and bg or { pal.well[1], pal.well[2], pal.well[3], 1 }))
                    control:SetBackdropBorderColor(unpack(edge[1] and edge or { pal.control[1], pal.control[2], pal.control[3], 1 }))
                end
                if control.PaintEdge then control:PaintEdge() end
                if originalInk[1] then control:SetTextColor(unpack(originalInk)) end
                if control.twichLook then control.twichLook.State() end
            end
            wasActive = false
            return
        end
        wasActive = true
        sheet:Show()
        Bevel(0)
        for _, line in pairs(control.twichFieldRing or {}) do line:Hide() end
        control:SetBackdropColor(0, 0, 0, 0)
        control:SetBackdropBorderColor(0, 0, 0, 0)
        local enabled = control:IsEnabled()
        local focus = kind == "field" and control:HasFocus()
        local base = kind == "chip" and "chip" or field and "field" or danger and "danger" or primary and "primary" or "button"
        if selectedFamily then
            -- Inactive segments keep quiet leather; UVs remain those of the selected-source family.
            base = control.twichSelected or kind == "chip" and true
            base = base and "selection" or "segment"
        end
        local skin
        if not enabled then skin = kind == "chip" and "chip-off" or field and "field-off" or selectedFamily and "segment-off" or "button-off"
        elseif down and not field then skin = (base == "selection" and "segment" or base) .. "-down"
        elseif over or focus then skin = base .. "-hot"
        else skin = base end
        sheet:SetSkin(skin)
        local pal = R.SettingsWidgets.pal
        local ink = not enabled and pal.stone or danger and pal.danger.text or kind == "target" and pal.bronzeText or pal.text
        if kind == "field" then R.SettingsWidgets.Color(control, ink) end
        if control.text and type(control.text) ~= "string" then
            R.SettingsWidgets.Color(control.text, ink)
            if control.craftLabelInset then
                control.text:ClearAllPoints()
                control.text:SetPoint("LEFT", control.craftLabelInset, 0)
                control.text:SetPoint("RIGHT", -10, 0)
                control.text:SetJustifyH("LEFT")
            elseif kind == "dropdown" and not control.compactMenu then
                control.text:ClearAllPoints()
                control.text:SetPoint("LEFT", 10, 0)
                control.text:SetPoint("RIGHT", -26, 0)
                control.text:SetJustifyH("LEFT")
            end
        end
    end
    control:HookScript("OnEnter", function() over = true; Paint() end)
    control:HookScript("OnLeave", function() over, down = false, false; Paint() end)
    control:HookScript("OnMouseDown", function() down = true; Paint() end)
    control:HookScript("OnMouseUp", function() down = false; Paint() end)
    control:HookScript("OnHide", function() over, down = false, false; Paint() end)
    control:HookScript("OnSizeChanged", Paint)
    if kind == "field" then
        control:HookScript("OnEditFocusGained", Paint)
        control:HookScript("OnEditFocusLost", Paint)
    end
    control:HookScript("OnEnable", Paint)
    control:HookScript("OnDisable", Paint)
    if kind == "segment" then
        function control:SetSelected(value) self.twichSelected = value; Paint() end
    end
    sheet.Refresh = Paint
    Paint()
    if control.text and type(control.text) ~= "string" and kind ~= "dropdown" then
        control.text:SetWidth(math.max(16, control:GetWidth() - 12))
        control.text:SetWordWrap(false)
    end
    return sheet
end

function C.Thumb(texture)
    texture:SetTexture(DIR .. "slider-thumb.tga")
    texture:SetVertexColor(1, 1, 1, 1)
end
