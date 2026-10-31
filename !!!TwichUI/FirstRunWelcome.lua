-- TwichUI: the welcome that bridges login to the layout setup on a new installation
-- Presentation only. Onboarding.lua decides whether the setup will open by itself this session and calls this at the first
-- world entry, so the few seconds before the setup is ready (it waits for the game to settle, loads its addons, builds its window)
-- are not a blank screen. It changes no setting, answers nothing for EllesmereUI and keeps no state of its own on disk: the
-- setup's own record (TwichUIDB.onboarding) stays the only one, and the setup does not depend on this working (every call from
-- Onboarding is protected, and a failure here is only noted).
--
--   F.Show()          the welcome, once per session (a second call, or one after it ended, does nothing). Returns true if shown.
--   F.Handoff()       the setup's window is open: fade out (0.2 s; none where motion is reduced) and release everything.
--   F.Release(why)    end it at once and release everything (the setup can't open, it is in the way, dismissed, timed out).
--   F.Snapshot()      read only: state, counts, the reason it ended.
--
-- What is drawn: a compact panel in the framed look (FrameLook.lua: the narrow frame and espresso interior, the brand icon, "Welcome
-- to TwichUI", "Preparing your setup") over a gentle dimming, at strata HIGH, level 0, where the setup's own dimming and window sit above it (they are
-- made later, and the window is on a higher level). Nothing takes the mouse except the small Dismiss, which appears only after
-- the welcome has waited a while. The motion is a fade-in (Look.Motion, the shared driver), one warm sweep across the title,
-- and MOTES gold motes that each drift up once; all of it is run by animation groups the game runs, so there is no per-frame
-- code here, and the motes and the sweep end by themselves about 2 s in. While it waits, one thin gold line breathes slowly (also
-- an animation group, stopped by every way out). No percentage, no stages: nothing says how far along the setup is.
-- Reduced motion (the settings window's, or the notifications' Reduced motion): a still panel shown and ended at once, no fade, motes or sweep.

local R = TwichUI
local F = {}
R.FirstRunWelcome = F

F.MOTES = 7             -- the most motes there are
F.FADE_IN = 0.5         -- seconds
F.FADE_OUT = 0.2
F.MAX_HOLD = 36         -- seconds a welcome waits at most (the setup's own looks stop at about 34 s)
F.DISMISS_AFTER = 6     -- seconds before the Dismiss button appears

local WIDTH, HEIGHT = 380, 176   -- panel size
local DIM = { 0.035, 0.030, 0.025, 0.30 }   -- warm charcoal, lighter than the setup's own dimming
local PUFF = R.PATH .. [[media\classbars\venom-puff.tga]]   -- a soft white puff, tinted here
local MOTE_LIFE = 1.5
-- where each mote starts relative to the panel's center (x, y), how far it rises, its size, and its delay: fixed, so every
-- first run looks the same
local MOTES = {
    { -118, -18, 30, 14, 0.00 }, { 96, -30, 26, 12, 0.12 }, { -62, 14, 34, 10, 0.24 }, { 134, 6, 28, 16, 0.30 },
    { -150, 22, 24, 12, 0.40 }, { 58, -6, 32, 10, 0.48 }, { 20, 30, 22, 14, 0.56 },
}

local state = { phase = "idle", why = nil, token = 0, shown = 0 }   -- phase: idle | showing | handoff | ended
local ui                                                              -- the frames, built on first Show

local function Look() return R.Look end

local function Still()
    local L = Look()
    if L and L.Motion and not L.Motion.Enabled() then return true end
    return R:Enabled("arrivalReducedMotion")
end

local function StopMotion()
    if not ui then return end
    for _, m in ipairs(ui.motes) do
        m.group:Stop()
        m.tex:SetAlpha(0)
        m.tex:Hide()
    end
    ui.sweepGroup:Stop()
    ui.sweep:SetAlpha(0)
    ui.pulseGroup:Stop()
    ui.line:SetAlpha(0.55)
end

local function End(why)
    if state.phase == "ended" or state.phase == "idle" then return end
    state.phase, state.why = "ended", why
    state.token = state.token + 1
    if ui then
        StopMotion()
        ui.fade:Set(0)
        ui.dismiss:EnableMouse(false)
        ui.dismiss:Hide()
        ui.root:Hide()
    end
end

local function Build()
    local L = Look()
    local pal = L.pal
    local root = CreateFrame("Frame", "TwichUIFirstRunWelcome", UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("HIGH")
    root:SetFrameLevel(0)
    root:EnableMouse(false)
    if root.EnableKeyboard then root:EnableKeyboard(false) end
    root:Hide()
    local dim = root:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(root)
    dim:SetColorTexture(DIM[1], DIM[2], DIM[3], DIM[4])

    local panel = CreateFrame("Frame", nil, root)
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("CENTER", root, "CENTER", 0, 0)
    panel:EnableMouse(false)
    -- the frame and interior, made once on a frame of their own under the panel's content (textures only, nothing takes the mouse). The
    -- panel keeps no fade of its own: the root's alpha, which F.Show and F.Handoff drive, is the only one.
    local shell = R.FrameLook.Shell(panel, { below = true })
    panel.shell = shell
    -- the panel's textures are on a frame above the shell
    local art = CreateFrame("Frame", nil, panel)
    art:SetAllPoints(panel)
    art:EnableMouse(false)

    local icon = art:CreateTexture(nil, "ARTWORK")
    icon:SetSize(56, 56)
    icon:SetPoint("TOP", panel, "TOP", 0, -24)
    icon:SetTexture(R.ICON)

    local title = L.Text(art, "brand")
    title:SetJustifyH("CENTER")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -12)
    title:SetText("Welcome to TwichUI")

    local sub = L.Text(art, "small")
    sub:SetJustifyH("CENTER")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -8)
    sub:SetText("Preparing your setup")

    -- the waiting accent: one thin gold line, breathing slowly
    local line = art:CreateTexture(nil, "ARTWORK")
    line:SetSize(96, 1)
    line:SetPoint("TOP", sub, "BOTTOM", 0, -12)
    line:SetColorTexture(pal.tealHi[1], pal.tealHi[2], pal.tealHi[3], 1)
    line:SetAlpha(0.55)
    local pulseGroup = line:CreateAnimationGroup()
    pulseGroup:SetLooping("BOUNCE")
    local pulse = pulseGroup:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.3)
    pulse:SetDuration(1.8)
    pulse:SetSmoothing("IN_OUT")

    -- the warm sweep: a soft tinted puff crossing the title once, clipped to the panel's width
    local clip = CreateFrame("Frame", nil, panel)
    clip:SetPoint("LEFT", panel, "LEFT", 4, 0)
    clip:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    clip:SetPoint("TOP", title, "TOP", 0, 8)
    clip:SetPoint("BOTTOM", title, "BOTTOM", 0, -8)
    clip:EnableMouse(false)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    local sweep = clip:CreateTexture(nil, "OVERLAY")
    sweep:SetTexture(PUFF)
    sweep:SetSize(110, 46)
    sweep:SetPoint("CENTER", clip, "LEFT", 0, 0)
    sweep:SetVertexColor(pal.tealHi[1], pal.tealHi[2], pal.tealHi[3])
    sweep:SetAlpha(0)
    local sweepGroup = sweep:CreateAnimationGroup()
    local sIn = sweepGroup:CreateAnimation("Alpha")
    sIn:SetOrder(1); sIn:SetFromAlpha(0); sIn:SetToAlpha(0.32); sIn:SetStartDelay(0.35); sIn:SetDuration(0.25)
    local sMove = sweepGroup:CreateAnimation("Translation")
    sMove:SetOrder(1); sMove:SetOffset(WIDTH - 8, 0); sMove:SetStartDelay(0.35); sMove:SetDuration(0.95); sMove:SetSmoothing("IN_OUT")
    local sOut = sweepGroup:CreateAnimation("Alpha")
    sOut:SetOrder(2); sOut:SetFromAlpha(0.32); sOut:SetToAlpha(0); sOut:SetDuration(0.25)
    sweepGroup:SetToFinalAlpha(true)

    -- a few slow gold motes round the branding, each rising once
    local motes = {}
    for i = 1, F.MOTES do
        local def = MOTES[i]
        local tex = art:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(PUFF)
        tex:SetSize(def[4], def[4])
        tex:SetPoint("CENTER", panel, "CENTER", def[1], def[2])
        tex:SetVertexColor(pal.gold[1], pal.gold[2], pal.gold[3])
        tex:SetAlpha(0)
        tex:Hide()
        local g = tex:CreateAnimationGroup()
        local move = g:CreateAnimation("Translation")
        move:SetOrder(1); move:SetOffset(0, def[3]); move:SetDuration(MOTE_LIFE); move:SetStartDelay(def[5]); move:SetSmoothing("OUT")
        local up = g:CreateAnimation("Alpha")
        up:SetOrder(1); up:SetFromAlpha(0); up:SetToAlpha(0.55); up:SetStartDelay(def[5]); up:SetDuration(MOTE_LIFE * 0.4)
        local down = g:CreateAnimation("Alpha")
        down:SetOrder(2); down:SetFromAlpha(0.55); down:SetToAlpha(0); down:SetDuration(MOTE_LIFE * 0.6)
        g:SetToFinalAlpha(true)
        g:SetScript("OnFinished", function() tex:Hide() end)
        motes[i] = { tex = tex, group = g }
    end

    -- a quiet way out, shown only after a wait; it ends the welcome and nothing else
    local dismiss = CreateFrame("Button", nil, panel)
    dismiss:SetSize(64, 18)
    dismiss:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)   -- inside the frame's rails
    local label = L.Text(dismiss, "meta")
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")
    label:SetText("Dismiss")
    dismiss:SetScript("OnClick", function() End("dismissed") end)
    dismiss:EnableMouse(false)
    dismiss:Hide()

    local fade = L.Motion.Fader(function(a) root:SetAlpha(a) end, 0)
    ui = { root = root, panel = panel, shell = shell, line = line, pulseGroup = pulseGroup, sweep = sweep, sweepGroup = sweepGroup,
        motes = motes, dismiss = dismiss, fade = fade, frames = 6 }
end

function F.Show()
    if state.phase ~= "idle" or not (R.Look and R.Look.Motion and R.FrameLook and R.FrameLook.Ready()) then return false end
    if not ui then Build() end
    state.phase = "showing"
    state.shown = state.shown + 1
    local token = state.token + 1
    state.token = token
    ui.root:Show()
    if Still() then
        ui.fade:Set(1)
    else
        ui.fade:To(1, F.FADE_IN)
        ui.sweepGroup:Play()
        for _, m in ipairs(ui.motes) do
            m.tex:Show()
            m.group:Play()
        end
        ui.pulseGroup:Play()
    end
    C_Timer.After(F.DISMISS_AFTER, function()
        if token ~= state.token or state.phase ~= "showing" then return end
        ui.dismiss:Show()
        ui.dismiss:EnableMouse(true)
    end)
    C_Timer.After(F.MAX_HOLD, function()
        if token == state.token and state.phase == "showing" then End("timeout") end
    end)
    return true
end

function F.Handoff()
    if state.phase ~= "showing" then return end
    if Still() then End("handoff") return end
    state.phase = "handoff"
    local token = state.token + 1
    state.token = token
    StopMotion()
    ui.dismiss:EnableMouse(false)
    ui.dismiss:Hide()
    ui.fade:To(0, F.FADE_OUT)
    C_Timer.After(F.FADE_OUT + 0.05, function()
        if token == state.token and state.phase == "handoff" then
            End("handoff")
        end
    end)
end

function F.Release(why) End(why or "released") end

-- Read only: counts and fixed codes.
function F.Snapshot()
    return { phase = state.phase, why = state.why, shown = state.shown, frames = ui and ui.frames or 0,
        fading = ui ~= nil and ui.fade:Active() }
end
