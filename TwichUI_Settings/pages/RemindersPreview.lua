-- Reminders companion preview. Only this isolated renderer copy takes clicks. The live/world renderer stays
-- click-through. Navigation never calls a Config setter, plays a sound or evaluates the reminder's conditions.
local R = TwichUI
local PV = {}
R.RemindersPreview = PV
local WIDTH, PAD, BOX_H = 318, 16, 360
local PANEL_H, BOX_Y = 666, 66
local f, hooks, shifted
local enabled = true -- session preference; never written to the reminder or profile
local function Wg() return R.SettingsWidgets end
local function D() return R.ReminderDisplay end

-- Dock beside settings in physical coordinates. If the pair fits but neither current side has room, temporarily
-- move settings (no saved placement write). Otherwise show an accessible centred overlay with a Back/close action.
function PV.RestoreAnchor()
    if not shifted then return end
    local a, p = shifted.anchor, shifted.point
    local point, relative, relativePoint, x, y = a:GetPoint(1)
    if point == "TOPLEFT" and relative == UIParent and relativePoint == "TOPLEFT"
        and math.abs(x - shifted.x) < 0.1 and math.abs(y - shifted.y) < 0.1 then
        a:ClearAllPoints()
        a:SetPoint(unpack(p, 1, 5))
    end
    shifted = nil
end
function PV.Place(frame, context)
    frame:ClearAllPoints()
    if shifted and shifted.owner ~= frame then PV.RestoreAnchor() end
    local a = R.SettingsAnchor and R.SettingsAnchor()
    local us = UIParent:GetEffectiveScale() or 1
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = a and a:GetEffectiveScale() / us or 1
    if frame.companionHeight then
        frame:SetHeight(math.max(300, math.min(frame.companionHeight, (sh - 24) / scale)))
    end
    scale = math.min(scale, (sw - 24) / frame:GetWidth(), (sh - 24) / frame:GetHeight())
    frame:SetScale(scale)
    frame.placement = "overlay"
    if a then
        local left, right, top = a:GetLeft(), a:GetRight(), a:GetTop()
        local as = a:GetEffectiveScale() / us
        if type(left) == "number" and type(right) == "number" and type(top) == "number" then
            local fw = (frame:GetWidth() + 8) * scale
            local function DockRight(anchor, anchorRight, placement, offset)
                local shift = math.max(0, anchorRight + fw - (sw - 12))
                if left * as - shift < 12 then return false end
                if shift > 0 then
                    if not shifted then shifted = { anchor = a, owner = frame, point = { a:GetPoint(1) } } end
                    shifted.x, shifted.y = left * as - shift, -(sh - top * as)
                    a:ClearAllPoints(); a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", shifted.x, shifted.y)
                end
                frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, offset or 0)
                frame.placement = placement
                return true
            end
            if right * as + fw <= sw - 12 then
                frame:SetPoint("TOPLEFT", a, "TOPRIGHT", 8, 0); frame.placement = "right"; return
            elseif left * as - fw >= 12 then
                frame:SetPoint("TOPRIGHT", a, "TOPLEFT", -8, 0); frame.placement = "left"; return
            end
            if DockRight(a, right * as, "right") then return end
            local contextRight = context and context:GetRight()
            local contextTop = context and context:GetTop()
            if contextRight and contextTop then
                local contextScale = context:GetEffectiveScale() / us
                local offset = (top * as - contextTop * contextScale) / scale
                if DockRight(context, contextRight * contextScale, "context", offset) then return end
            end
        end
    end
    if shifted then PV.RestoreAnchor() end
    if frame.minimized then frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -12, -12)
    else frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
end

local function Build()
    local G, M = Wg(), R.SettingsMaterial
    f = CreateFrame("Frame", "TwichUIReminderPreview", UIParent)
    f:SetSize(WIDTH, PANEL_H); f:SetFrameStrata("HIGH"); f:SetToplevel(true); f:SetClampedToScreen(true)
    f:EnableMouse(true); f:Hide()
    M.Companion(f)
    M.HeaderBand(f, 60)
    f.connector = M.FrameConnector(f, 44)
    f.title = G.Text(f, "heading"); f.title:SetPoint("TOPLEFT", PAD, -16); f.title:SetWidth(WIDTH - 64)
    f.title:SetText("Live preview")
    M.ReminderFont(f.title, 21, true)
    f.sub = G.Text(f, "body"); f.sub:SetPoint("TOPLEFT", PAD, -42); f.sub:SetWidth(WIDTH - PAD * 2)
    f.sub:SetMaxLines(1)
    f.close = G.Button(f, "—", 24, "secondary", function()
        f.minimized = not f.minimized
        if hooks and hooks.Changed then hooks.Changed() end
    end)
    f.close:SetPoint("TOPRIGHT", -12, -12)
    M.ReminderControl(f.close)
    f.box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.box:SetSize(WIDTH - PAD * 2, BOX_H); f.box:SetPoint("TOPLEFT", PAD, -BOX_Y)
    f.box:SetClipsChildren(true)
    f.boxFace = M.PanelFace(f.box, "canvas")
    -- The shell is hollow. Four quiet strips surround the well so Transparent
    -- really exposes the world, rather than another opaque layer behind the well.
    f.workspaceGrain:Hide()
    f.backgroundStrips = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local strip = M.QuietTile(f, "outer", "BACKGROUND", -7)
        strip:ClearAllPoints()
        f.backgroundStrips[#f.backgroundStrips + 1] = strip
        if side == "TOP" then
            strip:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
            strip:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -3, -BOX_Y)
        elseif side == "BOTTOM" then
            strip:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", -PAD + 3, 0)
            strip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
        elseif side == "LEFT" then
            strip:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -BOX_Y)
            strip:SetPoint("BOTTOMRIGHT", f.box, "BOTTOMLEFT", 0, 0)
        else
            strip:SetPoint("TOPLEFT", f.box, "TOPRIGHT", 0, 0)
            strip:SetPoint("BOTTOMRIGHT", f.box, "BOTTOMRIGHT", PAD - 3, 0)
        end
    end
    f.backgroundArt = f.box:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.backgroundArt:SetPoint("TOPLEFT", 2, -2)
    f.backgroundArt:SetPoint("BOTTOMRIGHT", -2, 2)
    f.background = "dark"
    f.backgroundPick = G.Dropdown(f, WIDTH - PAD * 2, function(mode) PV.SetBackground(mode) end)
    f.backgroundPick:SetChoices(function() return {
        { value = "dark", label = "Dark" }, { value = "transparent", label = "Transparent" },
        { value = "landscape", label = "Landscape" }, { value = "parchment", label = "Parchment" },
    } end)
    f.backgroundPick:SetHeight(25)
    f.backgroundPick:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", 0, -85)
    M.ReminderControl(f.backgroundPick, "dropdown")
    M.ContextTip(f.backgroundPick, "Preview background", "Changes only this editing canvas. Your reminder and its saved background stay the same.")
    f.surface = D().NewSurface(f.box); f.surface:SetPoint("CENTER", f.box, "CENTER", 0, 0)
    f.tag = G.Tag(f.box, "PREVIEW"); f.tag:SetPoint("TOPLEFT", 8, -8); f.tag:Hide()
    f.hint = G.Text(f, "small"); f.hint:SetPoint("TOP", f.box, "BOTTOM", 0, -9)
    f.hint:SetText("Click an element to edit")
    f.hint:SetWidth(WIDTH - PAD * 2)
    f.hint:SetJustifyH("CENTER")
    -- Hit targets follow the renderer's actual regions, including text above/below and non-square art.
    for _, part in ipairs({ "visual", "text" }) do
        local hit = CreateFrame("Button", nil, f.surface)
        local region = part == "visual" and f.surface.art or f.surface.text
        hit:SetAllPoints(region)
        hit:SetScript("OnClick", function()
            if f.placement == "overlay" then
                f.minimized = true
                PV.Update(f.view)
            end
            if hooks and hooks.Reveal then hooks.Reveal(part) end
        end)
        local highlight = R.SettingsCraft.Sheet(hit, "hover-rim", { layer = "OVERLAY", corner = 8 })
        highlight:Hide()
        local fill = R.SettingsCraft.Sheet(hit, "selection-hot", { layer = "BACKGROUND", corner = 8 })
        fill:SetAlpha(.15); fill:Hide()
        hit:SetScript("OnEnter", function() highlight:Show(); fill:Show() end)
        local function Clear() highlight:Hide(); fill:Hide() end
        hit:SetScript("OnLeave", Clear); hit:HookScript("OnHide", Clear)
        M.ContextTip(hit, part == "visual" and "Edit artwork" or "Edit text", part == "visual" and "Reveal the artwork controls." or "Reveal the text field.")
        f[part .. "Hit"] = hit
    end
    local function Size(mode)
        f.mode = mode
        PV.Update(f.view)
    end
    f.modeWell = CreateFrame("Frame", nil, f)
    f.modeWell:SetFrameLevel(f:GetFrameLevel() or 0)
    f.modeWell:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", -2, -27)
    f.modeWell:SetSize(WIDTH - PAD * 2 + 4, 36)
    M.PanelFace(f.modeWell, "espresso")
    local segmentWidth = (WIDTH - 2 * PAD) / 2 - 2
    f.actual = M.Segment(f, "Actual size", segmentWidth, function() Size("actual") end)
    f.actual:SetHeight(29)
    f.actual:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", 0, -29)
    f.fit = M.Segment(f, "Fit", segmentWidth, function() Size("fit") end)
    f.fit:SetHeight(29)
    f.fit:SetPoint("LEFT", f.actual, "RIGHT", 4, 0)
    f.caption = G.Text(f, "small"); f.caption:SetPoint("TOPLEFT", f.actual, "BOTTOMLEFT", 0, -8)
    f.caption:SetWidth(WIDTH - PAD * 2)
    f.show = M.Pill(f, function()
        local v = f.view
        if not v then return end
        if D().PreviewId() == v.id then D().PreviewStop()
        elseif not D().PreviewStart(v, false) and hooks and hooks.Say then hooks.Say("The preview waits until you are out of combat.", "warn") end
        if hooks and hooks.Changed then hooks.Changed() end
    end)
    f.show:SetPoint("BOTTOMLEFT", PAD + 88, 19)
    f.place = G.Button(f, "Place…", 82, "secondary", function()
        if f.view and R.RemindersPlacement then R.RemindersPlacement.Start(f.view) end
    end)
    f.place:SetPoint("BOTTOMRIGHT", -PAD, 17)
    M.ReminderControl(f.place, "secondary")
    M.ContextTip(f.place, "Place on screen", "Hides settings while you move this reminder. Finish saves; Cancel restores its old position.")
    R.Interact.Tip(f.show, "Show on screen", "Shows it in its own position, marked Preview, without enabling it or playing sound. Closing settings or entering combat ends it.")
    f.showLabel = G.Text(f, "body"); f.showLabel:SetPoint("BOTTOMLEFT", PAD, 23)
    f.showLabel:SetWidth(88); f.showLabel:SetText("On screen")
    f.footerRule = G.Solid(f, "ARTWORK", G.pal.bronzeLo, 0.58)
    f.footerRule:SetHeight(1)
    f.footerRule:SetPoint("BOTTOMLEFT", PAD, 53)
    f.footerRule:SetPoint("BOTTOMRIGHT", -PAD, 53)
    f.visibility = G.Text(f, "heading"); f.visibility:SetPoint("BOTTOMLEFT", PAD, 109)
    f.visibility:SetText("Visibility"); M.ReminderFont(f.visibility, 16, true)
    f.visibility:SetWidth(145)
    f.live = G.Text(f, "body"); f.live:SetPoint("BOTTOMLEFT", PAD + 25, 90); f.live:SetWidth(WIDTH - PAD * 2 - 25)
    f.eye = f:CreateTexture(nil, "ARTWORK")
    f.eye:SetSize(20, 20)
    f.eye:SetPoint("CENTER", f.live, "LEFT", -14, 0)
    M.ReminderFont(f.sub, 14)
    M.ReminderFont(f.hint, 13)
    M.ReminderFont(f.live, 13, true)
    f.state = G.Text(f, "small"); f.state:SetPoint("BOTTOMLEFT", PAD, 69); f.state:SetWidth(WIDTH - PAD * 2)
    local anchor = R.SettingsAnchor and R.SettingsAnchor()
    if anchor then
        anchor:HookScript("OnSizeChanged", function()
            if f:IsShown() and f.view then PV.Update(f.view) end
        end)
    end
end
function PV.Shown() return f ~= nil and f:IsShown() end
function PV.Parts() return f end
function PV.Hide() if f then f.view = nil; f:Hide() end end
function PV.SetBackground(mode)
    if mode ~= "dark" and mode ~= "transparent" and mode ~= "landscape" and mode ~= "parchment" then return false end
    if not f then return false end
    f.background = mode
    PV.Update(f.view)
    return true
end
function PV.Enabled() return enabled end
function PV.SetEnabled(on)
    enabled = on and true or false
    if not enabled then PV.Hide(); PV.RestoreAnchor() end
    if R.RemindersPage then R.RemindersPage.QueueRefresh() end
end

function PV.Allowed(view)
    local page = R.RemindersPage
    return enabled and page and page.EditorActive() and view and view.id == page.Selected()
        and R.Reminders.Get(view.id) ~= nil
        and not (R.RemindersCatalog and R.RemindersCatalog.Shown())
        and not (R.RemindersDesigner and R.RemindersDesigner.Shown())
end

local LIVE = {
    off = "Hidden in game · Reminders off", disabled = "Hidden in game · Reminder off",
    hidden = "Hidden in game · Conditions not met", invalid = "Hidden in game · Needs attention",
    notApplicable = "Hidden in game · Other character", world = "Waiting to enter the world",
    pending = "Hidden in game · Waiting for its delay", waiting = "Hidden in game · Waiting for information",
}

-- Regions outside the clipped well must also stop taking mouse clicks at actual size.
local function ClipHit(hit, box, shown)
    hit:SetShown(shown)
    if not shown then return end
    local l, r, t, b = hit:GetLeft(), hit:GetRight(), hit:GetTop(), hit:GetBottom()
    local bl, br, bt, bb = box:GetLeft(), box:GetRight(), box:GetTop(), box:GetBottom()
    if not (l and r and t and b and bl and br and bt and bb) then return end
    local ratio = box:GetEffectiveScale() / hit:GetEffectiveScale()
    local x1, x2, y1, y2 = math.max(l, bl * ratio), math.min(r, br * ratio), math.max(b, bb * ratio), math.min(t, bt * ratio)
    if x1 >= x2 or y1 >= y2 then hit:Hide(); return end
    hit:SetHitRectInsets(x1 - l, r - x2, t - y2, y1 - b)
end

function PV.Update(view, h)
    if not PV.Allowed(view) then PV.Hide(); return false end
    if not f then return false end
    hooks = h or hooks
    f.view = view
    f.sub:SetText(view.name)
    f.close.text:SetText(f.minimized and "+" or "—")
    f.workspaceGrain:SetShown(f.minimized and true or false)
    for _, strip in ipairs(f.backgroundStrips) do strip:SetShown(not f.minimized) end
    for _, child in ipairs({ f.box, f.hint, f.actual, f.fit, f.caption, f.visibility, f.live, f.show, f.showLabel, f.footerRule, f.state, f.modeWell, f.eye, f.backgroundPick, f.place }) do
        child:SetShown(not f.minimized)
    end
    local anchor = R.SettingsAnchor and R.SettingsAnchor()
    local panelHeight = math.max(PANEL_H, anchor and anchor:GetHeight() or 0)
    BOX_H = panelHeight - (PANEL_H - 360)
    f.box:SetHeight(BOX_H)
    local mode = f.background or "dark"
    f.boxFace:SetShown(mode == "dark")
    f.backgroundArt:SetShown(mode == "landscape" or mode == "parchment")
    f.backgroundPick:SetValue(mode, "Background: " .. ({ dark = "Dark", transparent = "Transparent", landscape = "Landscape", parchment = "Parchment" })[mode])
    if mode == "landscape" or mode == "parchment" then
        f.backgroundArt:SetTexture(R.PATH .. [[media\reminders\preview-]] .. mode .. ".tga")
        local aspect = mode == "landscape" and 1.5 or 2.5
        local ratio = (f.box:GetWidth() / BOX_H) / aspect
        if ratio < 1 then f.backgroundArt:SetTexCoord((1-ratio)/2, (1+ratio)/2, 0, 1)
        else f.backgroundArt:SetTexCoord(0, 1, (1-1/ratio)/2, (1+1/ratio)/2) end
    end
    f:SetHeight(f.minimized and 62 or panelHeight)
    PV.Place(f)
    f.connector:ClearAllPoints()
    local docked = f.placement == "right" or f.placement == "left"
    local side = f.placement == "left" and "TOPRIGHT" or "TOPLEFT"
    f.connector:SetPoint("CENTER", f, side, f.placement == "left" and 4 or -4, -100)
    f.connector:SetShown(docked and not f.minimized)
    local actual = f.mode == "actual"
    local worldScale = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    local maxW, maxH = WIDTH - PAD * 2 - 24, BOX_H - 40
    local w, height, scale
    if actual then
        w, height, scale = D().DrawSurface(f.surface, view, math.huge, math.huge, worldScale)
    else
        w, height, scale = D().DrawSurface(f.surface, view, maxW, maxH, worldScale)
    end
    f.surface:Show()
    ClipHit(f.visualHit, f.box, f.surface.art:IsShown()); ClipHit(f.textHit, f.box, f.surface.text:IsShown())
    f.actual:SetSelected(actual); f.fit:SetSelected(not actual)
    local clipped = w * scale > f.box:GetWidth() or height * scale > BOX_H
    f.caption:SetText(actual and (clipped and "Edges clipped. Choose Fit to see all." or "Configured display size")
        or ("%d%% of actual size"):format(math.floor(scale / worldScale * 100 + 0.5)))
    local on = D().PreviewId() == view.id
    f.show:SetChecked(on)
    local controller = R.ReminderController
    local status = controller and controller.Status(view.id)
    local live = D().Frame(view.id)
    local visible = not on and live and live:IsShown() and controller and controller.Visible(view.id)
    local liveText = visible and "Visible in game" or LIVE[status] or "Hidden in game"
    if on and controller and controller.Visible(view.id) then liveText = "Live rule matched · temporary preview shown" end
    f.live:SetText(liveText)
    local tone = visible and Wg().pal.sage or (status == "invalid" and Wg().pal.bronzeText or Wg().pal.textDim)
    Wg().Color(f.live, tone)
    f.eye:SetTexture(R.PATH .. [[media\guildloc\]] .. (visible and "eye-open-small.tga" or "eye-hidden-small.tga"))
    f.eye:SetVertexColor(tone[1], tone[2], tone[3], 1)
    f.state:SetText(on and "On screen now · preview only" or "Preview stays visible while editing")
    Wg().Color(f.state, not view.valid and Wg().pal.danger.text or Wg().pal.textDim)
    return true
end

-- Only an active editor reconciliation may show the UIParent companion. Updating content cannot do it.
function PV.Show(view, h)
    if not PV.Allowed(view) then PV.Hide(); return false end
    if not f then Build() end
    if PV.Update(view, h) then f:Show(); return true end
    return false
end
if R.OnSettingsClosed then R.OnSettingsClosed(function() PV.Hide(); PV.RestoreAnchor() end) end
