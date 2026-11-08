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
--   D.Set(button, style)   shows the glow a style describes (Config.lua's fields); the same style again does nothing
--   D.Clear(button)        hides it
--   D.ClearAll()           hides every glow (the frames are kept)
--   D.Fade(button, alpha)  a faded bar's button; D.Unfade(button) puts its alpha back; D.UnfadeAll()

local R = TwichUI
local D = { made = 0, shown = 0 }
R.BarGlowDraw = D

local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local ANTS_ATLAS = "rotationhelper_ants_flipbook"
local SOFT_TEXTURE = [[Interface\TargetingFrame\UI-TargetingFrame-Stealable]]
local FLIP_ROWS, FLIP_COLUMNS, FLIP_FRAMES = 6, 5, 30
-- How much bigger than the button each look is drawn at 100%: the spell alert is drawn 1.4 times the button by
-- the game itself (ActionButtonSpellAlerts.lua), the ants 66 on 45 (its template); the soft frame a little outside.
local SCALE = { proc = 1.4, ants = 66 / 45, soft = 1.2, pixel = 1 }
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
local function Overlay(button)
    local o = overlays[button]
    if o then return o end
    o = CreateFrame("Frame", nil, button)
    o:SetPoint("CENTER", button, "CENTER", 0, 0)
    o:Hide()
    -- inner: the part that breathes, so the overlay's own alpha (the opacity) is never overwritten
    o.inner = CreateFrame("Frame", nil, o)
    o.inner:SetAllPoints(o)
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

-- The first picture of a flipbook atlas, for a glow that stands still.
local function FirstPicture(tex, atlas)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return end
    local info = C_Texture.GetAtlasInfo(atlas)
    if type(info) ~= "table" then return end
    local l, r, t, b = Number(info.leftTexCoord, 0), Number(info.rightTexCoord, 1), Number(info.topTexCoord, 0), Number(info.bottomTexCoord, 1)
    tex:SetTexCoord(l, l + (r - l) / FLIP_COLUMNS, t, t + (b - t) / FLIP_ROWS)
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
    local w = Number(button:GetWidth(), 36)
    local h = Number(button:GetHeight(), 36)
    if w < 8 or h < 8 then w, h = 36, 36 end
    local grow = (Number(s.size, 100) / 100) * (SCALE[look] or 1)
    o:SetSize(w * grow, h * grow)
    o:SetFrameLevel((Number(button:GetFrameLevel(), 1)) + 6)
    o:SetAlpha(Number(s.opacity, 100) / 100)
    local r, g, b = Rgb(s.color)
    local speed = Number(s.speed, 100) / 100
    local motion = s.motion or "moving"
    if look == "proc" or look == "ants" then
        local f = Flip(o)
        local atlas = look == "proc" and PROC_ATLAS or ANTS_ATLAS
        f.tex:SetAtlas(atlas)
        f.tex:SetDesaturated(true)
        f.tex:SetVertexColor(r, g, b, 1)
        f.tex:Show()
        if motion == "moving" then
            f.anim:SetDuration(1 / speed)
            f.group:Play()
        else
            FirstPicture(f.tex, atlas)
        end
    elseif look == "soft" then
        local t = Soft(o)
        t:SetDesaturated(true)
        t:SetVertexColor(r, g, b, 1)
        t:Show()
    else
        local lines = Lines(o)
        local px = Pixel(o)
        local th = math.max(px, Number(s.thickness, 2) * px)
        local top, bottom, left, right = lines[1], lines[2], lines[3], lines[4]
        for _, l in ipairs(lines) do
            l:ClearAllPoints()
            l:SetColorTexture(r, g, b, 1)
            l:Show()
        end
        top:SetPoint("TOPLEFT", o, "TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", o, "TOPRIGHT", 0, 0); top:SetHeight(th)
        bottom:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", 0, 0); bottom:SetHeight(th)
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

function D.Set(button, style)
    if not (button and style) then return end
    local o = Overlay(button)
    local key = StyleKey(style)
    if o.key ~= key or not o:IsShown() then
        o.key = key
        Apply(o, button, style)
        o:Show()
    end
    if not glowing[button] then
        glowing[button] = true
        D.shown = D.shown + 1
    end
end

function D.Clear(button)
    local o = overlays[button]
    if not o or not glowing[button] then return end
    glowing[button] = nil
    D.shown = D.shown - 1
    HideParts(o)
    o:Hide()
    o.key = nil
end

function D.ClearAll()
    for button in pairs(glowing) do D.Clear(button) end
end

function D.IsGlowing(button) return glowing[button] == true end
function D.Glowing() return glowing end

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
