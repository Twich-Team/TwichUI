-- TwichUI: Navigation, the direction arrow
-- An arrow that points where to walk next: at the route's next corner (Nav.Target), not at the destination through
-- whatever is in between. Turned by the bearing from you to that corner (in continent yards, Nav.lua's checked frame)
-- less the way you face (GetPlayerFacing, counter-clockwise from north, as the bearing), so up on the arrow is ahead.
--   No route but on the destination's continent: the arrow points straight at the destination, drawn in stone grey and
--     labelled "Direct bearing, not a route". Arrived, calculating, no position or no facing: no arrow, a word instead.
--   On its own (movable when the frame is unlocked; ui.navigation.arrowPosition) or in the frame (Arrow attached).
--     Scaled by Arrow size. Takes no mouse input when locked. With "Use EllesmereUI Unlock Mode" on and EllesmereUI there
--     (nav/Unlock.lua), that mover places it instead: it is centred on the mover's stand-in, and dragging it here is off.
--   Turned at most 30 times a second, only while shown; the distance under it is set only when it changes by a yard.
-- The picture is the one RestedXP's guide skin uses for its arrow (its "bronze" shape, RestedXPSkin.lua: Arrow.BRONZE, which
-- is media/textures/arrow-bronze.tga, TwichUI's own, 128 x 128, pointing up). Its colour is the chosen one, white by default
-- (no tint), as the skin's; a direct bearing is still drawn grey.

local R = TwichUI
local NV, NP = R.Nav, R.NavPrefs
local NA = {}
R.NavArrow = NA

local TEXTURE = R.PATH .. [[media\textures\arrow-bronze]]   -- as RestedXPSkin.lua's Arrow.BRONZE
local SIZE = 40
local EVERY = 1 / 30
local STONE = { 0.62, 0.60, 0.56 }

local function NewArrow(parent, name)
    local h = CreateFrame("Frame", name, parent)
    h:SetSize(SIZE + 20, SIZE + 30)
    h:EnableMouse(false)
    h.tex = h:CreateTexture(nil, "ARTWORK")
    h.tex:SetTexture(TEXTURE)
    h.tex:SetSize(SIZE, SIZE)
    h.tex:SetPoint("TOP", h, "TOP", 0, 0)
    h.dist = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.dist:SetPoint("TOP", h.tex, "BOTTOM", 0, -1)
    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.label:SetPoint("TOP", h.dist, "BOTTOM", 0, -1)
    h.label:SetWidth(SIZE * 3)
    h.label:SetWordWrap(true)
    h.last = {}
    h:Hide()
    return h
end

local function Style(h)
    local font, size = NP.Font(), NP.Get("textSize")
    h.dist:SetFont(font, math.max(9, size - 1), "OUTLINE")
    h.label:SetFont(font, math.max(9, size - 2), "")
    local r, g, b = NP.Rgb(NP.Get("textColor"))
    h.dist:SetTextColor(r, g, b)
    h.label:SetTextColor(r * 0.8, g * 0.8, b * 0.8)
    h.last = {}
end

local function SetText(h, fs, key, text)
    if h.last[key] ~= text then
        h.last[key] = text
        fs:SetText(text or "")
    end
end

-- Draws one state. kind: "route", "direct", or nil (no arrow: `word` says why).
local function Show(h, angle, kind, dist, word)
    if kind and angle then
        h.tex:Show()
        h.tex:SetRotation(angle)
        if h.last.kind ~= kind then
            h.last.kind = kind
            if kind == "direct" then
                h.tex:SetVertexColor(STONE[1], STONE[2], STONE[3], 0.9)
            else
                local r, g, b = NP.Rgb(NP.Get("arrowColor"))
                h.tex:SetVertexColor(r, g, b, 1)
            end
        end
        SetText(h, h.dist, "dist", dist and NV.Yards(dist) or "")
        SetText(h, h.label, "label", kind == "direct" and "Direct bearing, not a route" or (word or ""))
    else
        h.tex:Hide()
        h.last.kind = nil
        SetText(h, h.dist, "dist", word or "")
        SetText(h, h.label, "label", "")
    end
end

---------------------------------------------------------------------------
-- The real arrow
---------------------------------------------------------------------------
local own, inFrame                -- the arrow on its own, and the one in the frame (each made when first needed)
local active                      -- the one in use
local ticking, wait = false, 0

local function Wanted() return NV.Enabled() and NP.Get("arrow") and NV.Active() end

local WORDS = { calculating = "Calculating…", recalculating = nil, loading = "Loading…", unavailable = "No position",
    arrived = "Arrived" }

local function Tick(elapsed)
    wait = wait + elapsed
    if wait < EVERY then return end
    wait = 0
    if not (active and active:IsShown()) then return end
    local snap = NV.Snapshot()
    local tx, ty, kind = NV.Target()
    local ok, _, px, py = NV.Position()
    if snap.state == "arrived" then return Show(active, nil, nil, nil, "Arrived") end
    if not (tx and ok) then return Show(active, nil, nil, nil, WORDS[snap.state] or "No route") end
    local facing = NV.Readable(GetPlayerFacing())
    if not facing then return Show(active, nil, nil, nil, "Facing unavailable") end
    local d = math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
    Show(active, NV.Bearing(px, py, tx, ty) - facing, kind, math.floor(d + 0.5))
end

local function SetTicking(on)
    if on and not ticking then NV.AddTicker(Tick) ticking = true
    elseif not on and ticking then NV.RemoveTicker(Tick) ticking = false end
end

local function PlaceOwn()
    own:ClearAllPoints()
    local stand = R.NavUnlock and R.NavUnlock.Anchor("arrow")
    if stand then own:SetPoint("CENTER", stand, "CENTER", 0, 0) return end
    local p = NP.Get("arrowPosition")
    local s = UIParent:GetScale() / own:GetScale()
    if p then own:SetPoint("CENTER", UIParent, "CENTER", p.x * s, p.y * s)
    else own:SetPoint("CENTER", UIParent, "CENTER", 0, 220 / own:GetScale()) end
end

local function MakeOwn()
    if own then return own end
    own = NewArrow(UIParent, "TwichUINavigationArrow")
    own:SetFrameStrata("MEDIUM")
    own:SetClampedToScreen(true)
    own:SetMovable(true)
    own:SetScript("OnDragStart", function(f) if not NP.Get("locked") then f:StartMoving() end end)
    own:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local cx, cy = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local s = f:GetScale() / UIParent:GetScale()
        if cx and ux then NP.Set("arrowPosition", { x = math.floor(cx * s - ux + 0.5), y = math.floor(cy * s - uy + 0.5) }) end
    end)
    return own
end

-- The frame (NavFrame) tells the arrow where it is; with Arrow attached, the arrow sits in it.
function NA.Attach(frameObj)
    if not frameObj then return end
    if not inFrame then
        inFrame = NewArrow(frameObj.f, nil)
        inFrame:SetScale(0.8)
    end
    NA.Refresh(frameObj)
end

function NA.Refresh(frameObj)
    frameObj = frameObj or (R.NavFrame and R.NavFrame.Main())
    local attached = NP.Get("arrowAttached") and NP.Get("frame") and frameObj ~= nil
    if not Wanted() then
        if own then own:Hide() end
        if inFrame then inFrame:Hide() end
        if frameObj then frameObj.arrowSlot = nil end
        active = nil
        SetTicking(false)
        return
    end
    if attached then
        if own then own:Hide() end
        if not inFrame then inFrame = NewArrow(frameObj.f, nil) inFrame:SetScale(0.8) end
        Style(inFrame)
        frameObj.arrowSlot = inFrame
        inFrame:Show()
        frameObj.dirty = true
        active = inFrame
    else
        if inFrame then inFrame:Hide() end
        if frameObj then frameObj.arrowSlot = nil; frameObj.dirty = true end
        MakeOwn()
        own:SetScale(NP.Get("arrowScale") / 100)
        Style(own)
        local unlocked = not NP.Get("locked") and not (R.NavUnlock and R.NavUnlock.Drives("arrow"))   -- or EllesmereUI moves it
        own:EnableMouse(unlocked)
        if unlocked then own:RegisterForDrag("LeftButton") else own:RegisterForDrag() end
        PlaceOwn()
        own:Show()
        active = own
    end
    wait = EVERY
    SetTicking(true)
end

NV.Subscribe(function(event)
    if event == "prefs" or event == "state" or event == "destination" or event == "route" then NA.Refresh() end
end)

---------------------------------------------------------------------------
-- The preview: the same arrow, still, labelled
---------------------------------------------------------------------------
local previewArrow

function NA.AttachPreview(frameObj)
    if not previewArrow then previewArrow = NewArrow(frameObj.f, nil) end
    local attached = NP.Get("arrowAttached")
    previewArrow:SetParent(attached and frameObj.f or UIParent)
    previewArrow:SetScale(attached and 0.8 or NP.Get("arrowScale") / 100)
    previewArrow:SetFrameStrata("DIALOG")
    Style(previewArrow)
    previewArrow.last = {}
    Show(previewArrow, math.rad(35), "route", 40)
    SetText(previewArrow, previewArrow.label, "label", attached and "" or "Preview")
    if attached then
        frameObj.arrowSlot = previewArrow
        frameObj.dirty = true
    else
        frameObj.arrowSlot = nil
        previewArrow:ClearAllPoints()
        previewArrow:SetPoint("TOP", frameObj.f, "BOTTOM", 0, -10)
    end
    previewArrow:Show()
    frameObj:Layout()
end

function NA.HidePreview() if previewArrow then previewArrow:Hide() end end

-- The arrow's size in screen units (its scale applied), for the Unlock Mode stand-in (nav/Unlock.lua).
function NA.Footprint()
    local scale = NP.Get("arrowScale") / 100
    return (SIZE + 20) * scale, (SIZE + 30) * scale
end

function NA.Diagnostics()
    return { ticking = ticking, attached = active ~= nil and active == inFrame, shown = active ~= nil and active:IsShown() or false }
end
