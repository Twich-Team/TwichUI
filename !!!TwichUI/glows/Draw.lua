-- TwichUI: Action bar glows, the drawing
-- One glow per button, drawn over it in a frame of TwichUI's own (a child of the button, so it shows, hides, scales and
-- fades with it). Made the first time that button glows and kept for reuse; nothing is written on the button itself.
-- Every animation is an AnimationGroup the client runs: there is no OnUpdate and no Lua runs per frame.
-- Also the faded bars (a button's alpha while it does not glow). The messages are Notice.lua's.
--
-- The art is the client's own (checked in the Forever UI source): the spell alert loop "UI-HUD-ActionBar-Proc-Loop-Flipbook"
-- and the rotation helper's "rotationhelper_ants_flipbook" (each 6 x 5, 30 pictures, one turn a second:
-- Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml, ActionButtonComponentTemplate.xml), the soft square frame of a
-- stealable buff (Interface\TargetingFrame\UI-TargetingFrame-Stealable) and plain lines.
--
-- Shared by Action bar glows and Reminders (each an "owner", see "Owners" below): one overlay per button whoever asks.
--   D.Request / D.Release / D.ReleaseOwner / D.Sync   an owner's glows (the look of the first-ranked owner shows)
--   D.Set(button, style)   Action bar glows' own request; the same style again does nothing
--   D.Clear(button)        lets go of it (another owner's glow on that button stays)
--   D.ClearAll()           lets go of every Action bar glows request (the frames are kept)
--   D.Fade(button, alpha)  a faded bar's button; D.Unfade(button) puts its alpha back; D.UnfadeAll()

local R = TwichUI
local D = { made = 0, shown = 0 }
R.BarGlowDraw = D

local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local ANTS_ATLAS = "rotationhelper_ants_flipbook"
local SOFT_TEXTURE = [[Interface\TargetingFrame\UI-TargetingFrame-Stealable]]
local FLIP_ROWS, FLIP_COLUMNS, FLIP_FRAMES = 6, 5, 30
-- These atlases include transparent padding around the ring. Match the client's layout
-- (ActionButtonSpellAlerts.lua and ActionButtonComponentTemplate.xml), so the visible ring
-- sits on the button border rather than shrinking into its icon. Plain frames have no atlas padding.
local ART_SCALE = { proc = 1.4, ants = 66 / 45, soft = 1, pixel = 1 }
local BREATH_LOW = 0.35
local BREATH_SECONDS = 0.7

local overlays = {}      -- [button] = overlay
local glowing = {}       -- [button] = true while its glow is shown

local function Rgb(hex)
    local h = type(hex) == "string" and hex:match("^%x%x(%x%x%x%x%x%x)$")
    if not h then return 1, 1, 1 end
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
D.Rgb = Rgb

local function Number(v, fallback)
    if type(v) ~= "number" or v ~= v or (issecretvalue and issecretvalue(v)) then return fallback end
    return v
end

-- The size of one physical pixel in a frame's units (for the pixel border's thickness).
local function Pixel(frame)
    local scale = Number(frame.GetEffectiveScale and frame:GetEffectiveScale(), 1)
    local h = 768
    if GetPhysicalScreenSize then
        local _, ph = GetPhysicalScreenSize()
        h = Number(ph, 768)
    end
    if scale <= 0 or h <= 0 then return 1 end
    return 768 / h / scale
end

---------------------------------------------------------------------------
-- An overlay and its parts (each made on first use)
---------------------------------------------------------------------------
local function Layout(o)
    local w, h = Number(o:GetWidth(), 36), Number(o:GetHeight(), 36)
    if w < 8 or h < 8 then w, h = 36, 36 end
    local grow = o.grow or 1
    o.inner:SetSize(w * grow, h * grow)
end

local function Overlay(button)
    local o = overlays[button]
    if o then return o end
    o = CreateFrame("Frame", nil, button)
    o:SetAllPoints(button)
    o:Hide()
    -- inner: the part that breathes, so the overlay's own alpha (the opacity) is never overwritten
    o.inner = CreateFrame("Frame", nil, o)
    o.inner:SetPoint("CENTER", o, "CENTER", 0, 0)
    -- Only our unprotected overlay listens for size changes; the action button is untouched.
    -- Resizing adjusts geometry without restarting either animation group.
    o:SetScript("OnSizeChanged", Layout)
    local breath = o.inner:CreateAnimationGroup()
    local fade = breath:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(BREATH_LOW)
    fade:SetDuration(BREATH_SECONDS)
    breath:SetLooping("BOUNCE")
    o.breath, o.breathFade = breath, fade
    overlays[button] = o
    D.made = D.made + 1
    return o
end

local function Flip(o)
    if o.flip then return o.flip end
    local tex = o.inner:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(o.inner)
    tex:SetBlendMode("ADD")
    local group = tex:CreateAnimationGroup()
    local anim = group:CreateAnimation("FlipBook")
    anim:SetFlipBookRows(FLIP_ROWS)
    anim:SetFlipBookColumns(FLIP_COLUMNS)
    anim:SetFlipBookFrames(FLIP_FRAMES)
    anim:SetFlipBookFrameWidth(0)
    anim:SetFlipBookFrameHeight(0)
    anim:SetDuration(1)
    group:SetLooping("REPEAT")
    o.flip = { tex = tex, group = group, anim = anim }
    return o.flip
end

local function Soft(o)
    if o.soft then return o.soft end
    local tex = o.inner:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(o.inner)
    tex:SetTexture(SOFT_TEXTURE)
    -- the file's outermost pixel is cut off: added, its faint edge would show as a square
    tex:SetTexCoord(1 / 32, 31 / 32, 1 / 32, 31 / 32)
    tex:SetBlendMode("ADD")
    o.soft = tex
    return tex
end

local function Lines(o)
    if o.lines then return o.lines end
    local lines = {}
    for i = 1, 4 do lines[i] = o.inner:CreateTexture(nil, "OVERLAY") end
    o.lines = lines
    return lines
end

-- Always give the native flipbook the complete atlas bounds, including when paused.
-- Hand-cropping a cell for still/breathing takes a different rendering path and can
-- stretch the artwork inside the icon instead of retaining the moving ring's alignment.
local function Picture(tex, atlas)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return end
    local info = C_Texture.GetAtlasInfo(atlas)
    if type(info) ~= "table" then return end
    local l, r, t, b = Number(info.leftTexCoord, 0), Number(info.rightTexCoord, 1), Number(info.topTexCoord, 0), Number(info.bottomTexCoord, 1)
    tex:SetTexCoord(l, r, t, b)
end

local function HideParts(o)
    if o.flip then o.flip.group:Stop(); o.flip.tex:Hide() end
    if o.soft then o.soft:Hide() end
    if o.lines then for _, l in ipairs(o.lines) do l:Hide() end end
    o.breath:Stop()
end

local function StyleKey(s)
    return table.concat({ s.look, s.color, s.opacity, s.size, s.speed, s.motion, s.thickness }, "|")
end

local function Apply(o, button, s)
    HideParts(o)
    local look = s.look or "proc"
    o.grow = (Number(s.size, 100) / 100) * (ART_SCALE[look] or 1)
    Layout(o)
    o:SetFrameLevel((Number(button:GetFrameLevel(), 1)) + 6)
    o:SetAlpha(Number(s.opacity, 100) / 100)
    local r, g, b = Rgb(s.color)
    local speed = Number(s.speed, 100) / 100
    local motion = s.motion or "moving"
    if look == "proc" or look == "ants" then
        local f = Flip(o)
        local atlas = look == "proc" and PROC_ATLAS or ANTS_ATLAS
        f.tex:SetAtlas(atlas)
        Picture(f.tex, atlas)
        f.tex:SetDesaturated(true)
        f.tex:SetVertexColor(r, g, b, 1)
        f.tex:Show()
        if motion == "moving" then
            f.anim:SetDuration(1 / speed)
            f.group:Play()
        else
            -- The client's SpellBookFrame.lua uses Play then Pause to hold a flipbook
            -- on its first frame. Keep native frame selection and padding in every mode;
            -- breathing animates only the separate inner frame's alpha below.
            f.group:Play()
            f.group:Pause()
        end
    elseif look == "soft" then
        local t = Soft(o)
        t:SetDesaturated(true)
        t:SetVertexColor(r, g, b, 1)
        t:Show()
    else
        local lines = Lines(o)
        local bounds = o.inner
        local px = Pixel(o)
        local th = math.max(px, Number(s.thickness, 2) * px)
        local top, bottom, left, right = lines[1], lines[2], lines[3], lines[4]
        for _, l in ipairs(lines) do
            l:ClearAllPoints()
            l:SetColorTexture(r, g, b, 1)
            l:Show()
        end
        top:SetPoint("TOPLEFT", bounds, "TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", bounds, "TOPRIGHT", 0, 0); top:SetHeight(th)
        bottom:SetPoint("BOTTOMLEFT", bounds, "BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", bounds, "BOTTOMRIGHT", 0, 0); bottom:SetHeight(th)
        left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0); left:SetWidth(th)
        right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0); right:SetWidth(th)
    end
    -- breathing: the still picture (or the frame, or the lines; "moving" breathes for those two) fades out and in
    local breathes = motion == "breathing" or (motion == "moving" and (look == "soft" or look == "pixel"))
    if breathes then
        o.breathFade:SetDuration(BREATH_SECONDS / speed)
        o.breath:Play()
    end
end

---------------------------------------------------------------------------
-- Owners: more than one feature may want a button to glow (Action bar glows, Reminders, a settings sample). Each owner
-- asks and lets go on its own; the button keeps one overlay and shows the look of the owner that ranks first. No
-- owner ever clears another's request, so turning one feature off leaves the other's glows as they are.
--
--   D.Request(owner, button, style)  this owner wants the button to glow in this look (asking again only updates it)
--   D.Release(owner, button)         this owner no longer wants it
--   D.ReleaseOwner(owner)            every button this owner asked for
--   D.Sync(owner, desired)           desired = { [button] = style }: exactly these for this owner (one notice)
--   D.Owned(owner)                   { [button] = style } of this owner (read only)
--   D.HasOther(owner, button)        whether an owner other than this one wants the button
--   D.WinnerOf(button)               the owner whose look the button shows, or nil
--   D.OnRequests(fn)                 fn(owner) after the set of buttons an owner asks for changed (not a look alone)
--
-- Which look shows (deterministic, whatever the order the requests came in): the owner with the lowest rank (RANK;
-- an unknown owner after the known ones), then the owner's name. A Reminder is something the player made for that one
-- spell, so it ranks before Action bar glows' catalogue. A look that is the same as the one showing changes nothing:
-- the animation is not restarted.
--
-- The older single-owner calls are Action bar glows' own and keep their meaning for it:
--   D.Set(button, style) = D.Request("barGlows", ...), D.Clear(button), D.ClearAll(), D.IsGlowing(button), D.Glowing()
---------------------------------------------------------------------------
D.OWNER = "barGlows"
local RANK = { reminders = 1, barGlows = 2 }
local requests = {}      -- [button] = { [owner] = style }
local owned = {}         -- [owner] = { [button] = style }
local requestListeners = {}

local function Before(a, b)
    local ra, rb = RANK[a] or 100, RANK[b] or 100
    if ra ~= rb then return ra < rb end
    return a < b
end

local function Winner(button)
    local list = requests[button]
    if not list then return nil end
    local best
    for owner in pairs(list) do
        if not best or Before(owner, best) then best = owner end
    end
    return best, best and list[best]
end

-- Shows the winning look on the button's one overlay, or hides it when nobody wants it.
local function Paint(button)
    local owner, style = Winner(button)
    if owner then
        local o = Overlay(button)
        local key = StyleKey(style)
        if o.key ~= key or not o:IsShown() then
            o.key = key
            Apply(o, button, style)
            o:Show()
        end
        o.owner = owner
        if not glowing[button] then
            glowing[button] = true
            D.shown = D.shown + 1
        end
        return
    end
    local o = overlays[button]
    if not o or not glowing[button] then return end
    glowing[button] = nil
    D.shown = D.shown - 1
    HideParts(o)
    o:Hide()
    o.key, o.owner = nil, nil
end

local function Notify(owner)
    for _, fn in ipairs(requestListeners) do
        local ok, err = pcall(fn, owner)
        if not ok and R.Fault then R.Fault("glow owners", err) end
    end
end

-- Returns whether the set of buttons this owner wants changed.
local function Put(owner, button, style)
    if not (owner and button and style) then return false end
    local mine = owned[owner]
    if not mine then mine = {}; owned[owner] = mine end
    local list = requests[button]
    if not list then list = {}; requests[button] = list end
    local added = mine[button] == nil
    mine[button], list[owner] = style, style
    Paint(button)
    return added
end

local function Drop(owner, button)
    local mine = owned[owner]
    if not (mine and button and mine[button]) then return false end
    mine[button] = nil
    local list = requests[button]
    if list then
        list[owner] = nil
        if next(list) == nil then requests[button] = nil end
    end
    Paint(button)
    return true
end

function D.Request(owner, button, style)
    if Put(owner, button, style) then Notify(owner) end
end

function D.Release(owner, button)
    if Drop(owner, button) then Notify(owner) end
end

function D.ReleaseOwner(owner)
    local mine = owned[owner]
    if not (mine and next(mine)) then return end
    local list = {}
    for button in pairs(mine) do list[#list + 1] = button end
    for _, button in ipairs(list) do Drop(owner, button) end
    Notify(owner)
end

function D.Sync(owner, desired)
    local changed = false
    local mine = owned[owner]
    if mine then
        local gone = {}
        for button in pairs(mine) do
            if not desired[button] then gone[#gone + 1] = button end
        end
        for _, button in ipairs(gone) do changed = Drop(owner, button) or changed end
    end
    for button, style in pairs(desired) do changed = Put(owner, button, style) or changed end
    if changed then Notify(owner) end
end

local NONE = {}
function D.Owned(owner) return owned[owner] or NONE end
function D.HasOther(owner, button)
    local list = requests[button]
    if not list then return false end
    for other in pairs(list) do if other ~= owner then return true end end
    return false
end
function D.WinnerOf(button) return (Winner(button)) end
function D.IsShown(button) return glowing[button] == true end

function D.OnRequests(fn)
    for _, existing in ipairs(requestListeners) do if existing == fn then return end end
    requestListeners[#requestListeners + 1] = fn
end

-- Action bar glows' own calls (and its settings sample): the "barGlows" owner.
function D.Set(button, style) D.Request(D.OWNER, button, style) end
function D.Clear(button) D.Release(D.OWNER, button) end
function D.ClearAll() D.ReleaseOwner(D.OWNER) end
function D.IsGlowing(button, owner)
    local list = requests[button]
    return list ~= nil and list[owner or D.OWNER] ~= nil
end
function D.Glowing(owner) return D.Owned(owner or D.OWNER) end

---------------------------------------------------------------------------
-- Faded bars: a button's alpha while it does not glow. The alpha it had is kept and put back.
---------------------------------------------------------------------------
local faded = {}   -- [button] = the alpha it had

function D.Fade(button, alpha)
    if not button then return end
    if faded[button] == nil then faded[button] = Number(button:GetAlpha(), 1) end
    local target = faded[button] * alpha
    if math.abs(Number(button:GetAlpha(), 1) - target) > 0.001 then button:SetAlpha(target) end
end

function D.Unfade(button)
    local was = faded[button]
    if was == nil then return end
    faded[button] = nil
    button:SetAlpha(was)
end

function D.UnfadeAll()
    for button in pairs(faded) do D.Unfade(button) end
end

function D.Faded() return faded end

function D.Snapshot() return { made = D.made, shown = D.shown } end
