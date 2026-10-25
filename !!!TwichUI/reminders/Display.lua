-- TwichUI: Reminders, drawing
-- One frame per reminder id, made the first time that reminder shows (or is previewed) and kept for the session: a
-- reminder that is deleted gives its frame back for the next one, so nothing is made again while rules are decided.
-- A frame is drawn again only when its reminder's settings changed (its view's rev) or something every frame uses did
-- (a font arriving). The frames take no clicks; only the move handle does, and only while you are moving one.
--
--   D.SetLive(view, on, immediate)   the controller's decision; immediate: no fade (switched off, deleted, a profile)
--   D.Update(view)                   its settings changed: a frame on screen is drawn again
--   D.Release(id)                    deleted: hidden at once, its frame kept for reuse
--   D.HideAll()                      Reminders switched off: every frame hidden at once
--   D.PreviewStart(view, moving)     one reminder shown where it sits whatever its rules say, marked "Preview" (and
--                                    with a handle to drag while moving). Never two at once; never in combat.
--   D.PreviewStop(), D.PositionEnd() back to what the rules say / stop moving (the preview stays)
--   D.NewSurface(parent), D.DrawSurface(surface, view, maxW, maxH)   the settings window's inline preview, drawn by
--                                    the same layout code at a scale that fits its box
--
-- A preview never changes a rule, an observation or a decision: the live state is only hidden behind it, and comes back
-- when it ends (closing the settings, combat, deleting or turning off the reminder, a profile change).
-- Motion is optional and short: a 0.25 s fade in and 0.3 s fade out, and a pulse of three slow breaths, each only when
-- chosen, and neither with Notifications' Reduced motion on. Both are animation groups the game runs; no OnUpdate.

local R = TwichUI
local RM = R.Reminders
local MS = R.MenuStyle
local D = {}
R.ReminderDisplay = D

local QUESTION = [[Interface\Icons\INV_Misc_QuestionMark]]
local FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", shadow = "" }
local FADE_IN, FADE_OUT = 0.25, 0.3
local PULSE_HALF, PULSE_BREATHS = 0.7, 3
local GAP, MAX_TEXT_W = 6, 420
local PANEL_PAD = { none = 0, shade = 8, framed = 10 }
local PANEL_BG = { 0.08, 0.065, 0.05 }      -- warm charcoal
local PANEL_EDGE = { 0.55, 0.43, 0.22 }     -- aged bronze
local MARK = { 0.58, 0.78, 0.76 }           -- the preview outline: the settings window's accent
local MAX_ICON_ASK = 2

local frames = {}          -- [id] = frame
local spare = {}           -- frames of deleted reminders, for the next one
local made = 0
local preview = { id = nil, positioning = false }
local layoutRev = 1        -- bumped when something every frame is drawn from changed
local iconAsk, iconWait = {}, {}   -- [itemID] = times asked to load; [itemID] = true while a frame waits for its icon
local evf
local registered = {}

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Reduced() return R:Enabled("arrivalReducedMotion") end

---------------------------------------------------------------------------
-- Events: only while something needs one (an icon not loaded yet, a preview that combat ends)
---------------------------------------------------------------------------
local function SyncEvents()
    local want = {}
    if next(iconWait) then want.GET_ITEM_INFO_RECEIVED = true end
    if preview.id then want.PLAYER_REGEN_DISABLED = true end
    if not evf then
        if next(want) == nil then return end
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", function(_, event, id)
            if event == "PLAYER_REGEN_DISABLED" then
                D.PreviewStop()   -- a preview or a move never carries into a fight
            elseif event == "GET_ITEM_INFO_RECEIVED" then
                id = Plain(id)
                if id and iconWait[id] then
                    iconWait[id] = nil
                    for fid, f in pairs(frames) do
                        if f.view and f.view.display.item == id then f.drawnRev = nil; D.Render(fid) end
                    end
                    SyncEvents()
                end
            end
        end)
    end
    for e in pairs(registered) do
        if not want[e] then evf:UnregisterEvent(e); registered[e] = nil end
    end
    for e in pairs(want) do
        if not registered[e] then evf:RegisterEvent(e); registered[e] = true end
    end
end

-- An item's icon, or nil while the game hasn't got it (it is asked for, at most twice).
local function ItemIcon(id)
    if not id then return nil end
    local tex
    if C_Item and C_Item.GetItemIconByID then tex = Plain(C_Item.GetItemIconByID(id)) end
    if tex == nil and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
        tex = Plain(icon)
    end
    return tex
end

local function WaitForIcon(id)
    if not id or (iconAsk[id] or 0) >= MAX_ICON_ASK then return end
    iconAsk[id] = (iconAsk[id] or 0) + 1
    iconWait[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    SyncEvents()
end

-- A wait for an icon lasts only while a frame on screen (or previewed) still shows that item's icon.
local function PruneWaits()
    if next(iconWait) == nil then return end
    local used = {}
    for fid, f in pairs(frames) do
        local d = f.view and f.view.display
        if d and d.iconSource == "item" and d.item and (f:IsShown() or preview.id == fid) then used[d.item] = true end
    end
    for item in pairs(iconWait) do
        if not used[item] then iconWait[item] = nil end
    end
    SyncEvents()
end

---------------------------------------------------------------------------
-- The parts every reminder is drawn with (a live frame and the settings window's inline preview alike)
---------------------------------------------------------------------------
local function Parts(f)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetAllPoints(f)
    f.bg = f.body:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f.body)
    f.edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = f.body:CreateTexture(nil, "BORDER")
        t:SetColorTexture(PANEL_EDGE[1], PANEL_EDGE[2], PANEL_EDGE[3], 0.9)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1)
            t:SetPoint(side .. "LEFT", f.body, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", f.body, side .. "RIGHT", 0, 0)
        else
            t:SetWidth(1)
            t:SetPoint("TOP" .. side, f.body, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, f.body, "BOTTOM" .. side, 0, 0)
        end
        f.edges[i] = t
    end
    f.art = f.body:CreateTexture(nil, "ARTWORK")
    f.text = f.body:CreateFontString(nil, "OVERLAY")
end

-- Draws a reminder's look into f (made by Parts). Returns its width and height.
function D.Layout(f, view)
    local d = view.display
    local mode = d.mode
    local visual = (mode == "artwork" or mode == "artworkText") and "art" or ((mode == "icon" or mode == "iconText") and "icon" or nil)
    local hasText = (mode == "text" or mode == "artworkText" or mode == "iconText") and d.text ~= ""
    local vw, vh = 0, 0
    if visual == "art" then
        local _, _, _, _, _, aspect = RM.ArtTexture(d.art, d.size)
        if not aspect then
            visual = nil   -- the artwork isn't there: such a reminder never shows live; the inline preview says why
        else
            if d.keepAspect then
                if aspect >= 1 then vw, vh = d.size, d.size / aspect else vw, vh = d.size * aspect, d.size end
            else
                vw, vh = d.width, d.height
            end
            local file, l, r, t, b = RM.ArtTexture(d.art, math.max(vw, vh))
            f.art:SetTexture(file)
            f.art:SetTexCoord(l, r, t, b)
            f.art:SetVertexColor(1, 1, 1, 1)
        end
    elseif visual == "icon" then
        if d.keepAspect then vw, vh = d.size, d.size else vw, vh = d.width, d.height end
        if d.iconSource == "item" then
            local tex = ItemIcon(d.item)
            if tex == nil then
                tex = QUESTION
                WaitForIcon(d.item)
            end
            f.art:SetTexture(tex)
            f.art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            f.art:SetVertexColor(1, 1, 1, 1)
        elseif R.Icons then
            R.Icons.Apply(f.art, d.icon, math.max(vw, vh))
        end
    end
    f.art:SetShown(visual ~= nil)
    if visual then f.art:SetSize(vw, vh) end

    local fs = f.text
    fs:SetShown(hasText)
    local tw, th = 0, 0
    if hasText then
        local fallback = rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]]
        local file = MS.Fonts.Resolve(d.font, fallback)
        local flags = FLAGS[d.outline] or ""
        if fs:SetFont(file, d.textSize, flags) == false then fs:SetFont(fallback, d.textSize, flags) end
        if d.outline == "shadow" then
            fs:SetShadowColor(0, 0, 0, 0.9)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
        local r, g, b = MS.ParseColor(d.textColor)
        fs:SetTextColor(r or 0.94, g or 0.91, b or 0.82)
        fs:SetWordWrap(true)
        fs:SetWidth(MAX_TEXT_W)
        fs:SetText(d.text)
        tw = math.min(math.ceil(fs:GetStringWidth() or 0) + 2, MAX_TEXT_W)
        fs:SetWidth(tw)
        th = math.ceil(fs:GetStringHeight() or d.textSize)
        local place = d.textPlace
        fs:SetJustifyH((not visual or place == "below" or place == "above") and "CENTER" or (place == "right" and "LEFT" or "RIGHT"))
    end

    local pad = PANEL_PAD[d.panel] or 0
    local gap = (visual and hasText) and GAP or 0
    local place = d.textPlace
    local w, h
    f.art:ClearAllPoints()
    fs:ClearAllPoints()
    if visual and hasText then
        if place == "below" or place == "above" then
            w, h = math.max(vw, tw), vh + gap + th
            if place == "below" then
                f.art:SetPoint("TOP", f.body, "TOP", 0, -pad)
                fs:SetPoint("TOP", f.art, "BOTTOM", 0, -gap)
            else
                fs:SetPoint("TOP", f.body, "TOP", 0, -pad)
                f.art:SetPoint("TOP", fs, "BOTTOM", 0, -gap)
            end
        else
            w, h = vw + gap + tw, math.max(vh, th)
            if place == "right" then
                f.art:SetPoint("LEFT", f.body, "LEFT", pad, 0)
                fs:SetPoint("LEFT", f.art, "RIGHT", gap, 0)
            else
                fs:SetPoint("LEFT", f.body, "LEFT", pad, 0)
                f.art:SetPoint("LEFT", fs, "RIGHT", gap, 0)
            end
        end
    elseif visual then
        w, h = vw, vh
        f.art:SetPoint("CENTER", f.body, "CENTER", 0, 0)
    elseif hasText then
        w, h = tw, th
        fs:SetPoint("CENTER", f.body, "CENTER", 0, 0)
    else
        w, h = 1, 1
    end

    local panel = d.panel
    f.bg:SetShown(panel ~= "none")
    if panel == "shade" then
        f.bg:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 0.55)
    elseif panel == "framed" then
        f.bg:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], 0.85)
    end
    for _, e in ipairs(f.edges) do e:SetShown(panel == "framed") end

    w, h = math.max(1, math.ceil(w + pad * 2)), math.max(1, math.ceil(h + pad * 2))
    f:SetSize(w, h)
    return w, h
end

---------------------------------------------------------------------------
-- Live frames
---------------------------------------------------------------------------
local function Place(f, view)
    local p, d = view.place, view.display
    f:SetFrameStrata(d.strata)
    f:SetAlpha(d.opacity / 100)
    f:ClearAllPoints()
    f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

-- The offset from a point of the screen to the same point of a frame, in screen units (the frames are UIParent's
-- children at scale 1).
local function OffsetFor(f, point)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    if not (l and r and t and b and W and H) then return nil end
    local x, y
    if point:find("LEFT") then x = l elseif point:find("RIGHT") then x = r - W else x = (l + r) / 2 - W / 2 end
    if point:find("TOP") then y = t - H elseif point:find("BOTTOM") then y = b else y = (t + b) / 2 - H / 2 end
    return x, y
end
D.OffsetFor = OffsetFor

local function StopMotion(f)
    f.fadeIn:Stop()
    f.fadeOut:Stop()
    f.pulse:Stop()
    f.leaving = false
    f.body:SetAlpha(1)   -- a stopped fade must not leave the reminder half-transparent for its next showing
end

local function Pulse(f)
    if not (f.view and f.view.display.pulse) or Reduced() then return end
    f.pulse.breaths = 0
    f.pulse:Play()
end

local function Build()
    local f = table.remove(spare)
    if f then return f end
    made = made + 1
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(10, 10)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)   -- click-through: only the move handle, while moving, takes the mouse
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end   -- TwichUI keeps the place, not the game's layout cache
    f:Hide()
    Parts(f)

    local fadeIn = f.body:CreateAnimationGroup()
    local a = fadeIn:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(FADE_IN)
    a:SetSmoothing("OUT")
    fadeIn:SetToFinalAlpha(true)
    fadeIn:SetScript("OnFinished", function() Pulse(f) end)
    f.fadeIn = fadeIn

    local fadeOut = f.body:CreateAnimationGroup()
    a = fadeOut:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    a:SetDuration(FADE_OUT)
    a:SetSmoothing("IN")
    fadeOut:SetToFinalAlpha(true)
    fadeOut:SetScript("OnFinished", function()
        if not f.leaving then return end
        f.leaving = false
        f.body:SetAlpha(1)
        f:Hide()
    end)
    f.fadeOut = fadeOut

    -- a few slow breaths, then still: never a loop that runs for as long as the reminder is up
    local pulse = f.body:CreateAnimationGroup()
    a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.6)
    a:SetDuration(PULSE_HALF)
    a:SetSmoothing("IN_OUT")
    pulse:SetLooping("BOUNCE")
    pulse:SetScript("OnLoop", function(self)
        self.breaths = (self.breaths or 0) + 1
        if self.breaths >= PULSE_BREATHS * 2 then
            self:Stop()
            f.body:SetAlpha(1)
        end
    end)
    f.pulse = pulse
    return f
end

-- The preview's outline and label, made the first time a frame is previewed.
local function BuildMark(f)
    if f.mark then return end
    local m = CreateFrame("Frame", nil, f)
    m:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    m:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    m:EnableMouse(false)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = m:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(MARK[1], MARK[2], MARK[3], 0.9)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1)
            t:SetPoint(side .. "LEFT", m, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", m, side .. "RIGHT", 0, 0)
        else
            t:SetWidth(1)
            t:SetPoint("TOP" .. side, m, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, m, "BOTTOM" .. side, 0, 0)
        end
    end
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 3)
    m:Hide()
    f.mark = m

    -- the move handle: over the frame, taking the mouse only while moving
    local h = CreateFrame("Frame", nil, f, "BackdropTemplate")
    h:SetFrameStrata("DIALOG")
    h:SetAllPoints(f)
    h:SetBackdrop({ bgFile = [[Interface\Buttons\WHITE8x8]] })
    h:SetBackdropColor(0.18, 0.33, 0.33, 0.35)
    h:RegisterForDrag("LeftButton")
    h:EnableMouse(false)
    h:Hide()
    h:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        f:StartMoving()
    end)
    h:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local v = f.view
        if v then
            local x, y = OffsetFor(f, v.place.point)
            if x then RM.SetPosition(v.id, v.place.point, x, y) end
            local now = RM.Get(v.id)
            if now then f.view = now end
            Place(f, f.view)   -- StartMoving re-anchored the frame: put it back on the saved place
        end
    end)
    h:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then D.PositionEnd() end
    end)
    f.handle = h
end

local function ShowMark(f, on, moving, view)
    if on then BuildMark(f) end
    if not f.mark then return end
    f.mark:SetShown(on)
    f.handle:SetShown(on and moving)
    f.handle:EnableMouse(on and moving)
    if on then
        f.mark.label:SetText(moving and ("Preview: %s. Drag to move; right-click to finish."):format(view.name) or ("Preview: %s"):format(view.name))
    end
end

local function Appear(f, view)
    f.leaving = false
    f.fadeOut:Stop()
    local wasShown = f:IsShown()
    f:Show()
    if wasShown then f.body:SetAlpha(1) return end   -- it never left (a fade out cut short): no second entrance
    if view.display.fade and not Reduced() then
        f.body:SetAlpha(0)
        f.fadeIn:Play()
    else
        f.body:SetAlpha(1)
        Pulse(f)
    end
end

local function Disappear(f, immediate)
    if not f:IsShown() then return end
    f.fadeIn:Stop()
    f.pulse:Stop()
    if not immediate and f.view and f.view.display.fade and not Reduced() then
        if f.leaving then return end
        f.leaving = true
        f.body:SetAlpha(1)
        f.fadeOut:Play()
    else
        StopMotion(f)
        f:Hide()
    end
end

-- What the frame of a reminder should show now: its preview, else its live state, else nothing.
function D.Render(id)
    local f = frames[id]
    if not f then return end
    local v = f.view
    local previewing = preview.id == id
    if v and (f.live or previewing) then
        if f.drawnRev ~= v.rev or f.drawnLayout ~= layoutRev then
            D.Layout(f, v)
            f.drawnRev, f.drawnLayout = v.rev, layoutRev
        end
        Place(f, v)
        ShowMark(f, previewing, previewing and preview.positioning, v)
        Appear(f, v)
    else
        ShowMark(f, false)
        Disappear(f, f.immediate)
    end
    f.immediate = false
    PruneWaits()
end

local function Acquire(id)
    local f = frames[id]
    if f then return f end
    f = Build()
    f.drawnRev, f.drawnLayout, f.live = nil, nil, false
    frames[id] = f
    return f
end

function D.SetLive(view, on, immediate)
    local f = frames[view.id]
    if on then f = f or Acquire(view.id) end
    if not f then return end
    f.view = view
    f.live = on and true or false
    f.immediate = immediate and true or false
    D.Render(view.id)
end

function D.Update(view)
    local f = frames[view.id]
    if not f then return end
    f.view = view
    if f:IsShown() or preview.id == view.id then D.Render(view.id) end
end

function D.Release(id)
    local f = frames[id]
    if not f then return end
    if preview.id == id then
        preview.id, preview.positioning = nil, false
        SyncEvents()
    end
    ShowMark(f, false)
    StopMotion(f)
    f:Hide()
    f.view, f.live = nil, false
    frames[id] = nil
    spare[#spare + 1] = f
    PruneWaits()
end

-- Every frame whose reminder isn't in `present` (deleted, or another profile's) is released.
function D.Prune(present)
    local gone = {}
    for id in pairs(frames) do
        if not present[id] then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do D.Release(id) end
end

function D.HideAll()
    D.PreviewStop()
    for _, f in pairs(frames) do
        f.live = false
        ShowMark(f, false)
        StopMotion(f)
        f:Hide()
    end
    PruneWaits()
end

-- Something every frame is drawn from changed (a font was registered): frames on screen are drawn again.
function D.Invalidate()
    layoutRev = layoutRev + 1
    for id, f in pairs(frames) do
        if f:IsShown() then D.Render(id) end
    end
end
MS.Fonts.Subscribe(function() D.Invalidate() end)

---------------------------------------------------------------------------
-- Preview and moving
---------------------------------------------------------------------------
function D.PreviewStart(view, moving)
    if InCombatLockdown() then return false, "combat" end
    local old = preview.id
    preview.id, preview.positioning = view.id, moving and true or false
    local f = Acquire(view.id)
    f.view = view
    if old and old ~= view.id then
        local of = frames[old]
        if of then of.immediate = true end
        D.Render(old)
    end
    SyncEvents()
    D.Render(view.id)
    return true
end

function D.PreviewStop()
    local old = preview.id
    if not old then return end
    preview.id, preview.positioning = nil, false
    SyncEvents()
    local f = frames[old]
    if f then
        f.immediate = true
        D.Render(old)
    end
end

function D.PositionEnd()
    if not (preview.id and preview.positioning) then return end
    preview.positioning = false
    D.Render(preview.id)
end

function D.PreviewId() return preview.id end
function D.Positioning() return preview.id ~= nil and preview.positioning end

---------------------------------------------------------------------------
-- The settings window's inline preview: the same parts and layout on a frame of its own, scaled to fit
---------------------------------------------------------------------------
function D.NewSurface(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(10, 10)
    s:EnableMouse(false)
    Parts(s)
    return s
end

function D.DrawSurface(s, view, maxW, maxH)
    local w, h = D.Layout(s, view)
    local scale = math.min(1, maxW / w, maxH / h)
    s:SetScale(math.max(0.2, scale))
    s:SetAlpha(view.display.opacity / 100)
    return w, h, scale
end

---------------------------------------------------------------------------
-- For /tui diagnostics and the tests: counts only
---------------------------------------------------------------------------
function D.Snapshot()
    local n, shown = 0, 0
    for _, f in pairs(frames) do
        n = n + 1
        if f:IsShown() then shown = shown + 1 end
    end
    local waiting = 0
    for _ in pairs(iconWait) do waiting = waiting + 1 end
    return { frames = n, spare = #spare, made = made, shown = shown, preview = preview.id ~= nil,
        positioning = preview.positioning, iconsWaiting = waiting }
end

function D.Frame(id) return frames[id] end

-- The sample goes away with the settings window; moving (an explicit, visible mode) is left to its own end.
R.OnSettingsClosed(function()
    if preview.id and not preview.positioning then D.PreviewStop() end
end)
