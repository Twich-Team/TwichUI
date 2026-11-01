-- TwichUI: the spectral mist behind the party member fallen card (modules/PartyDeath.lua)
-- A fixed pool of 12 soft textures drawn on the card itself, behind its text, tombstone and role icon, and moved only by
-- animation groups (no OnUpdate, no timers). Each pool slot lives a series of short, separate lives: it picks one of its
-- textures, a place inside its own region, a size, a strength, a lifetime and a drift (a straight leg plus a later sideways
-- leg, so the path bends), fades in, rises or drifts and fades out, rests a moment, then does it again with fresh values.
-- Slots start at different times and never share a lifetime, so the scene is never one sheet moving together. Every
-- life is planned to be over before the card's own length (LIFE_END) and no life begins that could not finish, so the whole
-- scene has thinned away as the card's exit ends. The card's alpha multiplies all of it. The strongest pieces sit by the
-- stone and the outer edges: the middle, where the title and the name are, is left clear.
--
-- The textures (media/partydeath/mist-*.tga) are drawn by tools/make_party_death_mist.py. Nothing here is interactive; the
-- card is not mouse-enabled and the textures are regions of it. Stop() puts every piece away.

local R = TwichUI
local M = {}
R.PartyDeathMist = M

local DIR = R.PATH .. [[media\partydeath\]]
local LIFE_END = 8.1                -- seconds: no life runs past this; the card's own length is 8.2 (FADE_IN + HOLD + FADE_OUT)
local MIN_LIFE = 2.0                -- a life shorter than this is not started

local FOG = { "mist-fog1", "mist-fog2", "mist-fog3" }
local WISP = { "mist-wisp1", "mist-wisp2", "mist-wisp3", "mist-wisp4", "mist-wisp5", "mist-wisp6" }
local MOTE = { "mist-mote" }

-- One entry per pool slot. Every range is { low, high }, drawn fresh at each life. layer: sublevel 1..7 (above the card's
-- backdrop, below its art and text). x, y: where the center is from the card's top center (y below it is negative; a y
-- of false is the card's bottom edge). first: when the first life starts; gap: the rest between lives; life: its length;
-- peak: its strongest alpha; dx, dy: the drift (positive dy is up); bend: a sideways drift added in the second half;
-- s0, s1: the scale it starts and ends at.
local SLOTS = {
    -- low fog: broad and faint, drifting at the outer edges and along the bottom
    { art = FOG, layer = 1, x = { -300, -190 }, y = { -120, -70 }, w = { 190, 270 }, h = { 90, 130 }, peak = { 0.10, 0.17 },
      first = { 0.0, 0.6 }, gap = { 0.2, 1.0 }, life = { 4.0, 5.4 }, dx = { 14, 34 }, dy = { 2, 12 }, bend = { -14, 14 }, s0 = { 0.85, 0.95 }, s1 = { 1.05, 1.2 } },
    { art = FOG, layer = 1, x = { 190, 300 }, y = { -120, -70 }, w = { 190, 270 }, h = { 90, 130 }, peak = { 0.09, 0.15 },
      first = { 0.4, 1.2 }, gap = { 0.2, 1.0 }, life = { 4.0, 5.4 }, dx = { -34, -14 }, dy = { 2, 12 }, bend = { -14, 14 }, s0 = { 0.85, 0.95 }, s1 = { 1.05, 1.2 } },
    { art = FOG, layer = 2, x = { -150, 150 }, y = false, w = { 240, 340 }, h = { 70, 100 }, peak = { 0.08, 0.14 },
      first = { 0.8, 1.8 }, gap = { 0.3, 1.2 }, life = { 4.2, 5.6 }, dx = { -40, 40 }, dy = { 0, 6 }, bend = { -18, 18 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.12 } },
    -- thin wisps near the stone and at the edges: each its own curl, speed and reach
    { art = WISP, layer = 3, x = { -120, -70 }, y = { -90, -50 }, w = { 70, 100 }, h = { 100, 140 }, peak = { 0.28, 0.42 },
      first = { 0.3, 1.5 }, gap = { 0.4, 1.6 }, life = { 3.0, 4.2 }, dx = { -30, -8 }, dy = { 24, 44 }, bend = { -12, 12 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.2 } },
    { art = WISP, layer = 3, x = { 70, 120 }, y = { -90, -50 }, w = { 70, 100 }, h = { 100, 140 }, peak = { 0.26, 0.40 },
      first = { 1.0, 2.2 }, gap = { 0.4, 1.6 }, life = { 3.0, 4.2 }, dx = { 8, 30 }, dy = { 24, 44 }, bend = { -12, 12 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.2 } },
    { art = WISP, layer = 3, x = { -270, -210 }, y = { -120, -80 }, w = { 70, 100 }, h = { 100, 140 }, peak = { 0.24, 0.36 },
      first = { 0.6, 2.0 }, gap = { 0.5, 1.8 }, life = { 3.2, 4.4 }, dx = { -34, -10 }, dy = { 30, 52 }, bend = { -14, 14 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.25 } },
    { art = WISP, layer = 3, x = { 210, 270 }, y = { -120, -80 }, w = { 70, 100 }, h = { 100, 140 }, peak = { 0.24, 0.36 },
      first = { 1.4, 2.6 }, gap = { 0.5, 1.8 }, life = { 3.2, 4.4 }, dx = { 10, 34 }, dy = { 30, 52 }, bend = { -14, 14 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.25 } },
    -- sparse, dim motes lifting and thinning
    { art = MOTE, layer = 5, x = { -200, -30 }, y = { -110, -50 }, w = { 14, 28 }, h = false, peak = { 0.22, 0.36 },
      first = { 0.8, 2.0 }, gap = { 0.6, 2.0 }, life = { 3.0, 4.6 }, dx = { -14, 14 }, dy = { 30, 62 }, bend = { -8, 8 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.3 } },
    { art = MOTE, layer = 5, x = { 30, 200 }, y = { -110, -50 }, w = { 14, 28 }, h = false, peak = { 0.22, 0.36 },
      first = { 1.4, 2.8 }, gap = { 0.6, 2.0 }, life = { 3.0, 4.6 }, dx = { -14, 14 }, dy = { 30, 62 }, bend = { -8, 8 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.3 } },
    { art = MOTE, layer = 5, x = { -280, -180 }, y = { -120, -60 }, w = { 14, 28 }, h = false, peak = { 0.2, 0.32 },
      first = { 1.0, 3.0 }, gap = { 0.8, 2.4 }, life = { 3.2, 4.8 }, dx = { -16, 8 }, dy = { 36, 70 }, bend = { -8, 8 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.3 } },
    { art = MOTE, layer = 5, x = { 180, 280 }, y = { -120, -60 }, w = { 14, 28 }, h = false, peak = { 0.2, 0.32 },
      first = { 1.8, 3.4 }, gap = { 0.8, 2.4 }, life = { 3.2, 4.8 }, dx = { -8, 16 }, dy = { 36, 70 }, bend = { -8, 8 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.3 } },
    { art = MOTE, layer = 5, x = { -90, 90 }, y = { -125, -95 }, w = { 12, 22 }, h = false, peak = { 0.16, 0.26 },
      first = { 2.2, 3.8 }, gap = { 1.0, 2.6 }, life = { 3.0, 4.2 }, dx = { -10, 10 }, dy = { 20, 40 }, bend = { -8, 8 }, s0 = { 0.9, 1.0 }, s1 = { 1.0, 1.2 } },
}
M.PIECES = #SLOTS

local pool = {}         -- built once: one per slot { tex, group, move, bendMove, grow, fadeIn, fadeOut, last }
local playing = false
local started = 0
local scene = 0         -- changes with every Play and Stop; a callback from an older scene does nothing
local lives = 0         -- lives begun in this scene, for the tests and the diagnostics
local random = math.random

-- Tests may replace the source of randomness (a function returning 0 <= n < 1) to make a scene reproducible; nil restores it.
function M.SetRandom(fn) random = fn or math.random end

local function Between(r) return r[1] + (r[2] - r[1]) * random() end
local function Now() return (GetTime and GetTime() or 0) - started end

local function Build(card)
    for i, slot in ipairs(SLOTS) do
        local tex = card:CreateTexture(nil, "BACKGROUND", nil, slot.layer)
        tex:SetAlpha(0)
        tex:Hide()
        local g = tex:CreateAnimationGroup()
        local m = { tex = tex, group = g, slot = slot }
        m.move = g:CreateAnimation("Translation")
        m.move:SetOrder(1)
        m.move:SetSmoothing("OUT")
        m.bendMove = g:CreateAnimation("Translation")
        m.bendMove:SetOrder(1)
        m.bendMove:SetSmoothing("IN_OUT")
        m.grow = g:CreateAnimation("Scale")
        m.grow:SetOrder(1)
        m.grow:SetSmoothing("OUT")
        m.fadeIn = g:CreateAnimation("Alpha")
        m.fadeIn:SetOrder(1)
        m.fadeIn:SetFromAlpha(0)
        m.fadeIn:SetSmoothing("OUT")
        m.fadeOut = g:CreateAnimation("Alpha")
        m.fadeOut:SetOrder(1)
        m.fadeOut:SetToAlpha(0)
        m.fadeOut:SetSmoothing("IN_OUT")
        g:SetToFinalAlpha(true)
        pool[i] = m
    end
end

local function Rest(m)
    m.tex:SetAlpha(0)
    m.tex:Hide()
end

-- Plans and starts the slot's next life, beginning `startAt` seconds into the scene; puts the slot away when no life of at
-- least MIN_LIFE would end in time. reduced: no staggering, movement, growth or later lives; one slow fade in and out.
local function Arm(m, card, height, startAt, reduced)
    local slot = m.slot
    local life = Between(slot.life)
    if startAt + life > LIFE_END then life = LIFE_END - startAt end
    if life < MIN_LIFE then Rest(m); return end
    lives = lives + 1

    local art = slot.art
    local pick = art[math.floor(random() * #art) + 1] or art[1]
    if m.last == pick and #art > 1 then pick = art[(m.last == art[1]) and 2 or 1] end   -- never the same shape twice in a row
    m.last = pick
    local w = Between(slot.w)
    local h = slot.h and Between(slot.h) or w
    local x = Between(slot.x)
    local y = slot.y and Between(slot.y) or -(height - 8 + Between({ -6, 6 }))
    local peak = Between(slot.peak)
    local delay = startAt - Now()
    if delay < 0 then delay = 0 end
    local dx, dy, bend, s0, s1 = Between(slot.dx), Between(slot.dy), Between(slot.bend), Between(slot.s0), Between(slot.s1)
    if reduced then delay, dx, dy, bend, s0, s1 = 0, 0, 0, 0, 1, 1 end
    local tin = life * 0.32
    local tout = life * 0.46

    m.tex:SetTexture(DIR .. pick)
    m.tex:ClearAllPoints()
    m.tex:SetPoint("CENTER", card, "TOP", x, y)
    m.tex:SetSize(w, h)
    m.tex:SetAlpha(0)
    m.tex:Show()
    m.move:SetOffset(dx, dy)
    m.move:SetDuration(life)
    m.move:SetStartDelay(delay)
    m.bendMove:SetOffset(bend, 0)
    m.bendMove:SetDuration(life * 0.55)
    m.bendMove:SetStartDelay(delay + life * 0.45)
    m.grow:SetScaleFrom(s0, s0)
    m.grow:SetScaleTo(s1, s1)
    m.grow:SetDuration(life)
    m.grow:SetStartDelay(delay)
    m.fadeIn:SetToAlpha(peak)
    m.fadeIn:SetDuration(tin)
    m.fadeIn:SetStartDelay(delay)
    m.fadeOut:SetFromAlpha(peak)
    m.fadeOut:SetDuration(tout)
    m.fadeOut:SetStartDelay(delay + life - tout)
    m.group:Play()
end

-- Puts every piece away and stops its animation. Safe at any time, and when nothing was ever built.
function M.Stop()
    playing = false
    scene = scene + 1
    for i = 1, #pool do
        local m = pool[i]
        m.group:Stop()
        Rest(m)
    end
end

-- Starts the scene on `card` (whose height is `height`), from its beginning, replacing any scene still running.
function M.Play(card, height, reduced)
    if #pool == 0 then
        Build(card)
    end
    M.Stop()
    playing = true
    scene = scene + 1
    lives = 0
    started = (GetTime and GetTime()) or 0
    local mine = scene
    for i, m in ipairs(pool) do
        m.last = nil
        m.group:SetScript("OnFinished", function()
            if not playing or mine ~= scene then return end
            Rest(m)
            if reduced then return end
            Arm(m, card, height, Now() + Between(m.slot.gap), false)
        end)
        if reduced then
            if m.slot.art ~= MOTE then Arm(m, card, height, 0, true) end
        else
            Arm(m, card, height, Between(m.slot.first), false)
        end
    end
end

-- Counts only, for the diagnostics and the tests.
function M.Snapshot()
    local shown = 0
    for i = 1, #pool do if pool[i].tex:IsShown() then shown = shown + 1 end end
    return { built = #pool, shown = shown, playing = playing, lives = lives }
end
