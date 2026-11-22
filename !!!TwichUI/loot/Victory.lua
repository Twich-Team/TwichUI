-- Confirmed self wins only. Owns one native event, never the global alert system.
-- Card artwork/timeline: assets/loot-victory; architecture: docs/loot-victory.md.
local R = TwichUI
local LR, Ro, C = R.LootRolls, R.LootRoll, R.LootCards
local V = {}
R.LootVictory = V
local ART = R.PATH .. [[media\loot\victory\]]
local FX = ART .. [[fx\]]
local EVENT = "LOOT_ITEM_ROLL_WON"
local entries, recent, departed = {}, {}, {}
local sequence, pool = 0, 0
local relay, owner, original
local preview, inFlight
local lastSound = -100
V.MAX_QUEUE = 32
V.MINI_HEIGHT = 80  -- reference pixels: 66.8 UI pixels at the established card width
V.DISPLAY_RETENTION = 60
-- Complete the choreographed afterglow before starting the configured hold.
V.HEIGHT, V.MOTION_END, V.HOLD_AT, V.SOUND_AT = 218, 1.85, 1.85, 0.30

local function Plain(v) if not (issecretvalue and issecretvalue(v)) then return v end end
local function Smooth(v) v = math.max(0, math.min(1, v)); return v * v * (3 - 2 * v) end
local function Cancel(f)
    f:SetScript("OnUpdate", nil)
    if f.timer then f.timer:Cancel(); f.timer = nil end
end
local function Forward(args)
    if owner and original then original(owner, EVENT, unpack(args, 1, args.n)) end
end
local function Enabled() return LR.IsOn() and LR.Get("victory") and C.Ready() end
local function Total() return ({ short = 3.5, normal = 4, long = 5 })[LR.Get("victoryDuration")] or 4 end
function V.Entries() return entries end
function V.Count() return #entries end
function V.RetainedDisplays() return #departed end
function V.PoolSize() return pool end
function V.Listening() return owner ~= nil end

local function Finish(entry)
    if entry.finished then return end
    entry.finished = true
    local source = not entry.preview and Ro.ByKey(entry.key)
    if source and source.victoryOwned then source.manualDisplay = nil end
    if entry.card then
        local f = entry.card.victory
        Cancel(f); f:Hide(); f.entry = nil
        if entry.preview then entry.card.view = nil end
        entry.card = nil
    end
    for i = #entries, 1, -1 do if entries[i] == entry then table.remove(entries, i) end end
    if entry.preview then
        if preview then preview.entry = nil; preview:Hide() end
    else C.Refresh() end
end

-- The reveal sound accompanies the banner/flourish, once per entry.
local function Sound(entry)
    if entry.sounded then return end
    entry.sounded = true
    local now = GetTime()
    if not LR.Get("victorySound") or now - lastSound < 0.8 then return end
    if GetCVarBool and (not GetCVarBool("Sound_EnableAllSound") or not GetCVarBool("Sound_EnableSFX")) then return end
    if type(PlaySoundFile) == "function" then
        lastSound = now
        pcall(PlaySoundFile, ART .. (entry.choice == "greed" and "loot_win_greed.ogg" or "loot_win_victory.ogg"), "SFX")
    end
end

-- Painted bounds are measured from the supplied straight-alpha PNG/TGA exports.
-- Cropping only transparent padding preserves the sprite's proportions and core.
local UV = {
    fx_sweep_trail = { 0.058594, 0.939453, 0.25, 0.75 },
    fx_emblem_final_star = { 0.058594, 0.9375, 0.203125, 0.792969 },
    fx_header_haze = { 0.05957, 0.939453, 0.132812, 0.863281 },
    fx_header_bloom = { 0.05957, 0.939453, 0.160156, 0.839844 },
    fx_glint_small = { 0.058594, 0.9375, 0.230469, 0.765625 },
    fx_icon_gold_haze = { 0.078125, 0.917969, 0.058594, 0.9375 },
    fx_icon_bloom = { 0.078125, 0.921875, 0.058594, 0.9375 },
    fx_sweep_haze = { 0.05957, 0.939453, 0.117188, 0.878906 },
    fx_sweep_core = { 0.05957, 0.939453, 0.195312, 0.800781 },
    fx_emblem_burst = { 0.058594, 0.939453, 0.210938, 0.787109 },
    fx_particle_star_4point = { 0.054688, 0.9375, 0.054688, 0.9375 },
    fx_particle_twinkle = { 0.054688, 0.9375, 0.054688, 0.9375 },
    -- Generic manifest bounds retain empty mote padding; measured alpha bounds plus 2 px.
    fx_particle_mote_medium = { 43 / 128, 99 / 128, 32 / 128, 89 / 128 },
    laurel_left = { 30 / 128, 77 / 128, 14 / 128, 91 / 128 },
    laurel_right = { 41 / 128, 91 / 128, 13 / 128, 89 / 128 },
    rim_glint = { 0, 1, 20 / 64, 45 / 64 },
    badge_backing = { 0, 1, 8 / 64, 58 / 64 },
    halo_uncommon = { 12 / 256, 244 / 256, 12 / 256, 244 / 256 },
    halo_rare = { 12 / 256, 244 / 256, 12 / 256, 244 / 256 },
    halo_epic = { 12 / 256, 244 / 256, 12 / 256, 244 / 256 },
    halo_legendary = { 12 / 256, 244 / 256, 12 / 256, 244 / 256 },
}
-- Twelve pooled sprites: first four in Subtle, all twelve in Full. Paths
-- originate on the icon, laurels and bronze corners; text always draws above FX.
-- x/y, travel x/y, w/h, texture, start/peak/end, alpha, optional laurel side/arc.
local PARTICLES = {
    { 48, 95, -12, -25, 24, 24, "fx_particle_star_4point", 0.78, 0.92, 1.45, 0.95 },
    { 0, 14, -6, -4, 32, 19, "fx_glint_small", 0.48, 0.60, 1.03, 0.90, -1 },
    { 96, 143, 10, -25, 24, 24, "fx_particle_twinkle", 0.90, 1.05, 1.65, 0.90 },
    { 40, 127, -12, -19, 12, 12, "fx_particle_mote_medium", 0.98, 1.15, 1.75, 0.70 },
    { 24, 17, -18, -30, 46, 31, "fx_emblem_final_star", 0.24, 0.40, 0.85, 1 },
    { 436, 16, 24, -42, 46, 31, "fx_emblem_final_star", 0.25, 0.40, 0.90, 1 },
    { 230, 69, 0, -2, 44, 30, "fx_emblem_final_star", 0.25, 0.40, 0.78, 1 },
    { 112, 19, -20, -39, 28, 28, "fx_particle_star_4point", 0.27, 0.45, 1.00, 0.95, nil, -9 },
    { 348, 21, 22, -43, 28, 28, "fx_particle_twinkle", 0.31, 0.48, 1.05, 0.95, nil, -7 },
    { 178, 10, -20, -34, 12, 12, "fx_particle_mote_medium", 0.40, 0.59, 1.25, 0.75 },
    { 95, 152, 14, -18, 10, 10, "fx_particle_mote_medium", 1.05, 1.20, 1.82, 0.75 },
    { 282, 12, 22, -35, 12, 12, "fx_particle_mote_medium", 0.37, 0.56, 1.20, 0.75 },
}
-- Same particle envelopes, deliberately authored Mini paths/sizes. Bright cores
-- stay legible; this is not a uniform shrink of the full celebration.
local MINI_PARTICLES = {
    { 112, 22, -12, -20, 24, 24 }, { 16, 10, -5, -5, 28, 17 },
    { 156, 61, 0, -17, 22, 22 }, { 104, 44, -12, -17, 11, 11 },
    { 12, 12, -12, -24, 36, 24 }, { 442, 12, 16, -24, 36, 24 },
    { 174, 56, 0, -2, 34, 23 }, { 90, 10, -17, -25, 26, 26 },
    { 330, 10, 20, -26, 26, 26 }, { 42, 8, -14, -20, 12, 12 },
    { 156, 62, 10, -16, 10, 10 }, { 278, 9, 16, -24, 12, 12 },
}
local function Clamp(v) return math.max(0, math.min(1, v)) end
local function EaseOut(v) v = 1 - Clamp(v); return 1 - v * v * v end
local function At(region, parent, x, y)
    region:ClearAllPoints(); region:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
end
local function Pulse(t, first, peak, last)
    if t <= first or t >= last then return 0 end
    if t < peak then return Smooth((t - first) / (peak - first)) end
    return 1 - Smooth((t - peak) / (last - peak))
end
function V.Paint(f, t, silent)
    f.paintTime = t
    local entry = f.entry
    local motion = entry.motion
    local reveal = motion and EaseOut(t / 0.45) or 1
    f.header:SetAlpha(reveal)
    f.header:ClearAllPoints(); f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -5 * (1 - reveal))
    local resolve = motion and Smooth(t / 0.20) or 1
    f.base:SetAlpha(resolve); f.miniBase:SetAlpha(resolve); f.content:SetAlpha(resolve)
    if entry.transition then
        local card = entry.card
        card.body:SetAlpha(1 - resolve); card.shell:SetAlpha(1 - resolve)
        if resolve >= 1 then card.body:Hide(); card.shell:Hide() end
    end
    local rich = entry.intensity == "full"
    local awaken = Smooth(t / 0.20)
    local settle = Smooth((t - 0.65) / 1.20)
    local expand = 0.88 + 0.12 * EaseOut(t / 0.20)
    f.atmosphere:SetAlpha(motion and 1 or 0)
    f.headerHaze:SetSize((312 + (rich and 38 * (1 - settle) or 0)) * expand, (65 + (rich and 23 * (1 - settle) or 0)) * expand)
    At(f.headerHaze, f, 230, 41 - (rich and 12 * (1 - settle) or 0))
    f.headerHaze:SetAlpha(motion and awaken * ((rich and 0.65 or 0.28) * (1 - settle) + (rich and 0.18 or 0.12) * settle) or 0)
    f.iconHaze:SetAlpha(motion and awaken * ((rich and 0.48 or 0.23) * (1 - settle) + (rich and 0.14 or 0.09) * settle) or 0)
    f.headerBloom:SetSize(rich and 265 or 214, rich and 51 or 41)
    f.headerBloom:SetAlpha(motion and (rich and 1 or 0.38) * Pulse(t, 0.20, 0.38, 0.66) or 0)
    f.emblemBurst:SetAlpha(motion and rich and 0.80 * Pulse(t, 0.08, 0.38, 0.70) or 0)
    -- A larger copy of the supplied radial artwork opens above the trim in Full.
    f.radiance:SetSize(150 * expand, 98 * expand)
    f.radiance:SetAlpha(motion and rich and 0.95 * Pulse(t, 0.18, 0.38, 0.70) or 0)
    f.iconBloom:SetAlpha(motion and (rich and 0.85 or 0.35) * Pulse(t, 0.75, 1.00, 1.65) or 0)
    -- No rectangular scissor: the full transparent fringe stays intact. Both
    -- endpoints keep the bright center on bronze; only feathered light escapes.
    local sweep = (t - 0.45) / 0.50
    local envelope = motion and Smooth(sweep / 0.12) * (1 - Smooth((sweep - 0.82) / 0.18)) or 0
    local x = 55 + Smooth(sweep) * 350
    if f.compact then x = 25 + Smooth(sweep) * 395 end
    At(f.sweepHaze, f.railCanvas, x - 16, f.compact and 10 or 16)
    At(f.sweepCore, f.railCanvas, x, f.compact and 10 or 15)
    At(f.sweepTail, f.railCanvas, x - 48, f.compact and 11 or 17)
    f.sweepHaze:SetAlpha(envelope * (rich and 0.60 or 0.28))
    f.sweepCore:SetAlpha(envelope * (rich and 1 or 0.75))
    f.sweepTail:SetAlpha(envelope * (rich and 0.65 or 0.20))
    f.trimGlints[1]:SetAlpha(motion and rich and Pulse(t, 0.45, 0.55, 0.72) or 0)
    f.trimGlints[2]:SetAlpha(motion and rich and Pulse(t, 0.72, 0.85, 1.04) or 0)
    for i, data in ipairs(PARTICLES) do
        local p = Clamp((t - data[8]) / (data[10] - data[8]))
        local pos = f.compact and MINI_PARTICLES[i] or data
        local x0 = not f.compact and data[12] and 230 + data[12] * (f.title:GetWidth() / 2 + 31) or pos[1]
        local y = pos[2] + pos[4] * EaseOut(p) + (data[13] or 0) * 4 * p * (1 - p)
        local texture = f.particles[i]
        At(texture, f.effects, x0 + pos[3] * EaseOut(p), y)
        texture:SetAlpha(motion and (rich or i <= 4) and data[11] * (rich and 1 or 0.85) * Pulse(t, data[8], data[9], data[10]) or 0)
    end
    f.arrivalGlint:SetSize(rich and 40 or 28, rich and 24 or 17)
    f.arrivalGlint:SetAlpha(motion and (rich and 1 or 0.80) * Pulse(t, 0.90, 1.08, 1.60) or 0)
    local rarity = motion and Pulse(t, 0.75, 1.00, 1.65) or 0
    f.halo:SetAlpha(f.haloRest + (f.hasHalo and (rich and 0.22 or 0.06) * rarity or 0))
    if f.compact then
        f.headerHaze:SetSize(124 * expand, 58 * expand); At(f.headerHaze, f, 55, 30)
        f.headerBloom:SetSize(120, 36); At(f.headerBloom, f, 55, 35)
        f.radiance:SetSize(100 * expand, 68 * expand)
        f.arrivalGlint:SetSize(rich and 32 or 26, rich and 19 or 16)
    end
    if not silent and t >= V.SOUND_AT then Sound(entry) end
    f.phase = not motion and "static" or t < 0.20 and "reveal" or t < 0.60 and "burst" or t < 0.95 and "sweep" or t < 1.40 and "arrival" or t < V.MOTION_END and "afterglow" or "static"
end

local function Fail(err)
    R.Fault("loot victory", err)
    V.Disable(true)
end
local function Safe(fn)
    return function(...) local ok, err = pcall(fn, ...); if not ok then Fail(err) end end
end
local function Rest(f)
    f:SetScript("OnUpdate", nil)
    f.timer = C_Timer.NewTimer(math.max(0, f.entry.total - 0.30 - (GetTime() - f.entry.started)), Safe(function()
        f.timer = nil
        if not f.entry or not f:IsShown() then return end
        local started = GetTime()
        f.phase = "fade"
        f:SetScript("OnUpdate", R.Perf.Wrap("loot.victory.tick", Safe(function()
            local p = (GetTime() - started) / 0.30
            if p >= 1 then Finish(f.entry) else f:SetAlpha(1 - Smooth(p)) end
        end)))
    end))
end
local function Animate(f)
    V.Paint(f, 0)
    f:SetScript("OnUpdate", R.Perf.Wrap("loot.victory.tick", Safe(function()
        local t = GetTime() - f.entry.started
        V.Paint(f, math.min(t, V.MOTION_END))
        if t >= V.MOTION_END then Rest(f) end
    end)))
end

local function Texture(parent, name, w, h, layer, blend)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    if t:SetTexture((name:find("^fx_") and FX or ART) .. name .. ".tga") == false then error("Missing loot victory texture: " .. name) end
    t:SetSize(w, h); t:SetBlendMode(blend or "BLEND")
    if UV[name] then t:SetTexCoord(unpack(UV[name])) end
    return t
end
local ItemName = C.FitItemName
local function Font(parent, size, serif)
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT, size, "")
    if R.CraftLook and R.CraftLook.Font then R.CraftLook.Font(f, size, false, serif and "serif" or nil) end
    f:SetTextColor(0.93, 0.87, 0.75); f:SetJustifyH("LEFT"); f:SetJustifyV("MIDDLE")
    f:SetWordWrap(false); f:SetMaxLines(1)
    f:SetShadowColor(0.035, 0.022, 0.014, 0.9); f:SetShadowOffset(1, -1)
    return f
end
-- Preserve all four painted corners and both horizontal separators. Only the
-- leather strips inside the header/footer gain height, by 10/8 reference pixels.
local function FrameArtwork(parent)
    local base = CreateFrame("Frame", nil, parent)
    base:SetAllPoints(); base:SetFrameLevel(parent:GetFrameLevel())
    local xs, ys = { 0, 80, 944, 1024 }, { 0, 80, 108, 350, 364, 444 }
    local dx = { 0, 80 * 460 / 1024, 944 * 460 / 1024, 460 }
    local dy = { 0, 80 * 200 / 444, 108 * 200 / 444 + 10, 350 * 200 / 444 + 10, 364 * 200 / 444 + 18, V.HEIGHT }
    base.pieces = {}
    for row = 1, 5 do
        for column = 1, 3 do
            local t = Texture(base, "loot_won_frame", dx[column + 1] - dx[column], dy[row + 1] - dy[row], "BACKGROUND")
            t:SetPoint("TOPLEFT", base, "TOPLEFT", dx[column], -dy[row])
            t:SetTexCoord(xs[column] / 1024, xs[column + 1] / 1024, ys[row] / 512, ys[row + 1] / 512)
            base.pieces[#base.pieces + 1] = t
        end
    end
    return base
end
local function MiniArtwork(parent)
    local base = CreateFrame("Frame", nil, parent); base:SetSize(460, V.MINI_HEIGHT); base:SetPoint("TOPLEFT")
    base:SetFrameLevel(parent:GetFrameLevel())
    local xs, dx = { 0, 80, 944, 1024 }, { 0, 24, 436, 460 }
    local rows = { { 0, 80, 0, 24 }, { 130, 330, 24, 56 }, { 364, 444, 56, 80 } }
    for _, row in ipairs(rows) do for col = 1, 3 do
        local t = Texture(base, "loot_won_frame", dx[col + 1] - dx[col], row[4] - row[3], "BACKGROUND")
        t:SetPoint("TOPLEFT", base, "TOPLEFT", dx[col], -row[3])
        t:SetTexCoord(xs[col] / 1024, xs[col + 1] / 1024, row[1] / 512, row[2] / 512)
    end end
    return base
end
local function SizeFont(label, size)
    local file, _, flags = label:GetFont()
    if file then label:SetFont(file, size, flags or "") end
end
local function Layout(f, compact)
    if f.compact == compact then return false end
    f.compact = compact
    f:SetHeight(compact and V.MINI_HEIGHT or V.HEIGHT)
    f.base:SetShown(not compact); f.miniBase:SetShown(compact)
    f.title:SetShown(not compact); f.miniTitle:SetShown(compact)
    for i, laurel in ipairs(f.laurels) do
        laurel:ClearAllPoints()
        if compact then laurel:SetSize(14, 23); At(laurel, f.header, i == 1 and 17 or 94, 38)
        else
            laurel:SetSize(i == 1 and 19 or 20, 31)
            laurel:SetPoint(i == 1 and "RIGHT" or "LEFT", f.title, i == 1 and "LEFT" or "RIGHT", i == 1 and -8 or 8, 0)
        end
    end
    for _, divider in ipairs(f.dividers) do divider:SetShown(not compact) end
    f.emblem:SetSize(compact and 16 or 24, compact and 16 or 24); At(f.emblem, f.header, compact and 174 or 230, compact and 55 or 64)
    f.icon:ClearAllPoints(); f.icon:SetSize(compact and 44 or 52, compact and 44 or 52)
    f.icon:SetPoint("TOPLEFT", compact and 112 or 46, compact and -19 or -93)
    f.halo:SetSize(compact and 80 or 96, compact and 80 or 96); At(f.halo, f, compact and 134 or 72, compact and 41 or 119)
    local ex, ey, ew = compact and 111 or 45, compact and 18 or 92, compact and 46 or 54
    for i, edge in ipairs(f.edges) do
        edge:ClearAllPoints(); edge:SetPoint("TOPLEFT", ex + (i == 4 and ew - 1 or 0), -(ey + (i == 2 and ew - 1 or 0)))
        edge:SetSize(i <= 2 and ew or 1, i <= 2 and 1 or ew)
    end
    ex, ey, ew = ex - 1, ey - 1, ew + 2
    for i, edge in ipairs(f.outerEdges) do
        edge:ClearAllPoints(); edge:SetPoint("TOPLEFT", ex + (i == 4 and ew - 1 or 0), -(ey + (i == 2 and ew - 1 or 0)))
        edge:SetSize(i <= 2 and ew or 1, i <= 2 and 1 or ew)
    end
    f.name:ClearAllPoints(); f.name:SetPoint("TOPLEFT", compact and 170 or 120, compact and -18 or -84)
    f.name:SetSize(compact and 206 or 300, 24); SizeFont(f.name, compact and 17 or 19)
    f.sub:SetShown(not compact)
    f.method:ClearAllPoints(); f.method:SetPoint("TOPLEFT", compact and 188 or 120, compact and -46 or -134)
    f.method:SetSize(compact and 200 or 300, compact and 18 or 20); SizeFont(f.method, compact and 13 or 14)
    f.hit:ClearAllPoints(); f.hit:SetPoint("TOPLEFT", compact and 108 or 43, compact and -13 or -76)
    f.hit:SetSize(compact and 270 or 380, compact and 56 or 82)
    f.iconHaze:SetSize(compact and 78 or 96, compact and 82 or 100)
    At(f.iconHaze, f, compact and 134 or 72, compact and 41 or 116)
    f.iconBloom:SetSize(compact and 74 or 92, compact and 78 or 96)
    At(f.iconBloom, f, compact and 134 or 72, compact and 41 or 116)
    f.emblemBurst:SetSize(compact and 40 or 58, compact and 26 or 38)
    At(f.emblemBurst, f, compact and 174 or 230, compact and 55 or 64)
    At(f.headerBloom, f, compact and 55 or 230, compact and 35 or 55)
    At(f.radiance, f, compact and 55 or 230, compact and 12 or 24)
    At(f.arrivalGlint, f, compact and 152 or 97, compact and 20 or 96)
    f.sweepHaze:SetSize(compact and 96 or 115, compact and 28 or 36)
    f.sweepCore:SetSize(compact and 82 or 92, compact and 22 or 26)
    f.sweepTail:SetSize(compact and 96 or 110, compact and 27 or 31)
    At(f.trimGlints[1], f, compact and 26 or 108, compact and 10 or 14)
    At(f.trimGlints[2], f, compact and 426 or 350, compact and 10 or 14)
    for i, texture in ipairs(f.particles) do
        local pos = compact and MINI_PARTICLES[i] or PARTICLES[i]; texture:SetSize(pos[5], pos[6])
    end
    return true
end

local function Build(card)
    pool = pool + 1
    local f = CreateFrame("Frame", nil, card)
    card.victory = f -- retain partial builds so missing assets cannot grow the pool on retry
    f:SetSize(460, V.HEIGHT); f:SetScale(384 / 460); f:SetPoint("TOPLEFT")
    f:SetFrameLevel(card.body:GetFrameLevel() + 4)
    f.base = FrameArtwork(f)
    f.miniBase = MiniArtwork(f)
    f.atmosphere = CreateFrame("Frame", nil, f); f.atmosphere:SetAllPoints()
    f.atmosphere:SetFrameLevel(f:GetFrameLevel() + 1); f.atmosphere:EnableMouse(false)
    f.headerHaze = Texture(f.atmosphere, "fx_header_haze", 312, 65, "BACKGROUND", "ADD"); At(f.headerHaze, f, 230, 41)
    f.iconHaze = Texture(f.atmosphere, "fx_icon_gold_haze", 96, 100, "BACKGROUND", "ADD"); At(f.iconHaze, f, 72, 116)
    f.headerBloom = Texture(f.atmosphere, "fx_header_bloom", 214, 41, "ARTWORK", "ADD"); At(f.headerBloom, f, 230, 55)
    f.emblemBurst = Texture(f.atmosphere, "fx_emblem_burst", 58, 38, "ARTWORK", "ADD"); At(f.emblemBurst, f, 230, 64)
    f.iconBloom = Texture(f.atmosphere, "fx_icon_bloom", 92, 96, "ARTWORK", "ADD"); At(f.iconBloom, f, 72, 116)
    f.radiance = Texture(f.atmosphere, "fx_emblem_burst", 150, 98, "ARTWORK", "ADD"); At(f.radiance, f, 230, 24)
    f.header = CreateFrame("Frame", nil, f); f.header:SetSize(460, 80)
    f.header:SetFrameLevel(f:GetFrameLevel() + 6)
    f.title = Font(f.header, 24, true); f.title:SetText("YOU WON!")
    -- Measure real client font metrics so the laurels bracket the words closely
    -- and symmetrically. The title stays centered at x230 at every font fallback.
    f.title:SetSize(math.min(204, math.max(112, f.title:GetStringWidth() + 4)), 30)
    f.title:SetPoint("TOP", f.header, "TOP", 0, -24)
    f.title:SetJustifyH("CENTER"); f.title:SetTextColor(0.93, 0.79, 0.50)
    f.miniTitle = Font(f.header, 13, true); f.miniTitle:SetText("YOU WON!"); f.miniTitle:SetMaxLines(1)
    f.miniTitle:SetSize(72, 24); At(f.miniTitle, f.header, 55, 37); f.miniTitle:SetJustifyH("CENTER")
    f.laurels = { Texture(f.header, "laurel_left", 19, 31), Texture(f.header, "laurel_right", 20, 31) }
    f.laurels[1]:SetPoint("RIGHT", f.title, "LEFT", -8, 0)
    f.laurels[2]:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
    f.dividers = { Texture(f.header, "rim_glint", 52, 5, "BORDER"), Texture(f.header, "rim_glint", 52, 5, "BORDER") }
    At(f.dividers[1], f.header, 186, 59); At(f.dividers[2], f.header, 274, 59)
    f.dividers[1]:SetAlpha(0.22); f.dividers[2]:SetAlpha(0.22)
    f.emblem = Texture(f.header, "emblem_need", 24, 24); At(f.emblem, f.header, 230, 64)
    f.content = CreateFrame("Frame", nil, f); f.content:SetAllPoints(); f.content:SetFrameLevel(f:GetFrameLevel() + 6)
    f.halo = Texture(f.content, "halo_uncommon", 96, 96, "BACKGROUND"); At(f.halo, f, 72, 119)
    f.icon = f.content:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(52, 52); f.icon:SetPoint("TOPLEFT", 46, -93)
    f.edges = {}
    for i, pos in ipairs({ { 45, -92, 54, 1 }, { 45, -145, 54, 1 }, { 45, -92, 1, 54 }, { 98, -92, 1, 54 } }) do
        local e = f.content:CreateTexture(nil, "OVERLAY"); e:SetPoint("TOPLEFT", pos[1], pos[2]); e:SetSize(pos[3], pos[4]); f.edges[i] = e
    end
    f.outerEdges = {}
    for i, pos in ipairs({ { 44, -91, 56, 1 }, { 44, -146, 56, 1 }, { 44, -91, 1, 56 }, { 99, -91, 1, 56 } }) do
        local edge = f.content:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT", pos[1], pos[2]); edge:SetSize(pos[3], pos[4])
        edge:SetColorTexture(0.53, 0.40, 0.24, 1); f.outerEdges[i] = edge
    end
    f.name = Font(f.content, 19, true); f.name:SetPoint("TOPLEFT", 120, -84); f.name:SetSize(300, 24)
    f.sub = Font(f.content, 14, true); f.sub:SetPoint("TOPLEFT", 120, -112); f.sub:SetSize(300, 18)
    f.method = Font(f.content, 14, true); f.method:SetPoint("TOPLEFT", 120, -134); f.method:SetSize(300, 20)
    f.sub:SetTextColor(0.82, 0.77, 0.66); f.method:SetTextColor(0.82, 0.77, 0.66)
    f.badge = Texture(f.content, "badge_backing", 148, 29); At(f.badge, f, 230, 184)
    f.upgrade = Font(f.content, 14); f.upgrade:SetPoint("CENTER", f.badge, "CENTER"); f.upgrade:SetSize(140, 22)
    f.upgrade:SetJustifyH("CENTER"); f.upgrade:SetText("Potential Upgrade")
    f.miniUpgradeBadge = Texture(f.content, "badge_backing", 32, 28); At(f.miniUpgradeBadge, f, 391, 40)
    f.upgradeIcon = f.content:CreateTexture(nil, "OVERLAY"); f.upgradeIcon:SetSize(18, 18)
    f.upgradeIcon:SetTexture(R.PATH .. [[media\loot\upgrade]]); At(f.upgradeIcon, f, 391, 40)
    f.upgradeHit = CreateFrame("Frame", nil, f.content); f.upgradeHit:SetSize(24, 24); At(f.upgradeHit, f, 391, 40)
    f.upgradeHit:EnableMouse(true)
    f.upgradeHit:SetScript("OnEnter", function(self) if f.entry then C.PillTips.upgrade(self, f.entry.card, f.entry) end end)
    f.upgradeHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.hit = CreateFrame("Button", nil, f.content); f.hit:SetPoint("TOPLEFT", 43, -76); f.hit:SetSize(380, 82)
    f.hit:RegisterForClicks("LeftButtonUp")
    f.hit:SetScript("OnEnter", function(self) if f.entry then C.ItemTip(self, f.entry) end end)
    f.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.hit:SetScript("OnClick", function()
        if f.entry and not f.entry.preview and f.entry.link and HandleModifiedItemClick then HandleModifiedItemClick(f.entry.link) end
    end)
    f.rail = CreateFrame("Frame", nil, f); f.rail:SetAllPoints()
    f.rail:SetFrameLevel(f:GetFrameLevel() + 3); f.rail:SetClipsChildren(false); f.rail:EnableMouse(false)
    f.railCanvas = CreateFrame("Frame", nil, f.rail); f.railCanvas:SetAllPoints(); f.railCanvas:SetFrameLevel(f:GetFrameLevel() + 3)
    f.sweepHaze = Texture(f.railCanvas, "fx_sweep_haze", 115, 36, "ARTWORK", "ADD")
    f.sweepCore = Texture(f.railCanvas, "fx_sweep_core", 92, 26, "OVERLAY", "ADD")
    f.sweepTail = Texture(f.railCanvas, "fx_sweep_trail", 110, 31, "BACKGROUND", "ADD")
    f.effects = CreateFrame("Frame", nil, f); f.effects:SetAllPoints(); f.effects:SetFrameLevel(f:GetFrameLevel() + 4)
    f.effects:EnableMouse(false)
    f.trimGlints = { Texture(f.effects, "fx_glint_small", 32, 19, "OVERLAY", "ADD"), Texture(f.effects, "fx_glint_small", 32, 19, "OVERLAY", "ADD") }
    At(f.trimGlints[1], f, 108, 14); At(f.trimGlints[2], f, 350, 14)
    f.particles = {}
    for i, data in ipairs(PARTICLES) do f.particles[i] = Texture(f.effects, data[7], data[5], data[6], "OVERLAY", "ADD") end
    f.arrivalGlint = Texture(f.effects, "fx_glint_small", 30, 18, "OVERLAY", "ADD"); At(f.arrivalGlint, f, 97, 96)
    f:SetScript("OnHide", function() Cancel(f) end)
    f.built = true
    return f
end

function V.Suspend(card)
    local e = card.victory and card.victory.entry
    if e and not e.finished then e.started, e.card, e.transition = nil, nil, false end
    V.ClearCard(card)
end
function V.ClearCard(card)
    if card.victory then
        Cancel(card.victory); card.victory:Hide(); card.victory.entry = nil
    end
    card.body:SetAlpha(1); card.shell:SetAlpha(1); card.body:Show(); card.shell:Show()
end
function V.Draw(card, entry)
    local f = card.victory or Build(card)
    if not f.built then error("Loot victory artwork failed to construct; reload after repairing assets") end
    local changed = Layout(f, entry.displayMode == "collapsed")
    local h = (f.compact and V.MINI_HEIGHT or V.HEIGHT) * 384 / 460
    card:SetHeight(h); C.DisplayToggle(card, entry.displayMode, true)
    if f.entry == entry then
        if changed then
            ItemName(f.name, entry.name or "Loot")
            local upgrade = entry.upgrade == true and LR.Get("showUpgrade")
            f.badge:SetShown(upgrade and not f.compact); f.upgrade:SetShown(upgrade and not f.compact)
            f.miniUpgradeBadge:SetShown(upgrade and f.compact); f.upgradeIcon:SetShown(upgrade and f.compact); f.upgradeHit:SetShown(upgrade and f.compact)
            V.Paint(f, f.seeking and f.paintTime or math.min(GetTime() - entry.started, V.MOTION_END), true)
        end
        return h
    end
    V.ClearCard(card)
    entry.transition = card.view ~= nil and not card.view.victory and not entry.preview
    entry.card, f.entry = card, entry
    f.seeking = nil
    card.live, card.enter, card.view = false, 1, entry
    card:SetAlpha(1); card:SetHeight(h)
    card.rollID = nil -- victory cards never authorize automatic actions or park live native roll controls
    card.timer:Hide(); card.time:Hide()
    for _, b in pairs(card.buttons) do b:Disable() end
    card.body:EnableMouse(false)
    -- Mouse stays disabled throughout resolution; individual controls cannot submit another choice.
    card.iconHit:EnableMouse(false); card.close:Disable()
    -- Old item text must not ghost through the new title during the material fade.
    card.body:Hide()
    if not entry.transition then card.shell:Hide() end
    local qc = R.LootRules.QUALITY_COLOR[entry.quality] or R.LootRules.QUALITY_COLOR[1]
    local qname = R.LootRules.QualityName(entry.quality)
    ItemName(f.name, entry.name or "Loot"); f.name:SetTextColor(qc[1], qc[2], qc[3])
    f.sub:SetText((entry.typeText and entry.typeText .. " · " or "") .. qname)
    f.method:SetText((entry.choice == "need" and "Need roll" or "Greed roll") .. (entry.value and (": " .. entry.value) or ""))
    local upgrade = entry.upgrade == true and LR.Get("showUpgrade")
    f.badge:SetShown(upgrade and not f.compact); f.upgrade:SetShown(upgrade and not f.compact)
    f.miniUpgradeBadge:SetShown(upgrade and f.compact); f.upgradeIcon:SetShown(upgrade and f.compact); f.upgradeHit:SetShown(upgrade and f.compact)
    f.icon:SetTexture(entry.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
    for _, edge in ipairs(f.edges) do
        edge:SetColorTexture(qc[1] * 0.45 + 0.58 * 0.55, qc[2] * 0.45 + 0.43 * 0.55, qc[3] * 0.45 + 0.24 * 0.55, 1)
    end
    local halos = { [2] = "uncommon", [3] = "rare", [4] = "epic", [5] = "legendary" }
    f.halo:SetTexture(halos[entry.quality] and ART .. "halo_" .. halos[entry.quality] .. ".tga" or nil)
    f.halo:SetTexCoord(unpack(UV.halo_uncommon)) -- same painted bounds in all four supplied rings
    f.hasHalo = halos[entry.quality] ~= nil
    f.haloRest = f.hasHalo and 0.42 or 0
    f.emblem:SetTexture(ART .. "emblem_" .. entry.choice .. ".tga")
    f:SetAlpha(1); f:Show()
    entry.started = GetTime()
    if entry.motion then Animate(f) else
        V.Paint(f, V.MOTION_END)
        f.timer = C_Timer.NewTimer(entry.total, Safe(function() f.timer = nil; Finish(entry) end))
    end
    return h
end

function V.SetDisplay(entry, mode)
    if not entry or not entry.card or (mode ~= "expanded" and mode ~= "collapsed") then return false end
    entry.displayMode, entry.manualDisplay = mode, mode
    if entry.preview then
        local h = V.Draw(entry.card, entry); preview:SetHeight(h)
    else
        local roll = Ro.ByKey(entry.key)
        if roll and roll.victoryOwned then return Ro.SetDisplay(roll, mode) end
        C.Refresh()
    end
    return true
end

local function PruneDeparted()
    for i = #departed, 1, -1 do if departed[i].expires <= GetTime() then table.remove(departed, i) end end
end
Ro.Subscribe(function(kind, roll)
    if kind ~= "removed" or not owner or roll.victoryOwned or type(roll.link) ~= "string" then return end
    PruneDeparted()
    departed[#departed + 1] = { view = C.View(roll), key = roll.key, expires = GetTime() + V.DISPLAY_RETENTION }
    if #departed > V.MAX_QUEUE then table.remove(departed, 1) end
end)

-- Freeze only a unique matching roll. The win event is authoritative even after
-- the roll record expired. No guess based on selection, player name, or item ID.
local function Snapshot(link, quantity, kind, value)
    link, kind, value = Plain(link), Plain(kind), Plain(value)
    if type(link) ~= "string" or #link > 2048 or not link:find("item:", 1, true) or (kind ~= 1 and kind ~= 2) then return end
    local match, count = nil, 0
    for _, r in ipairs(Ro.Rolls()) do
        if r.link == link and not r.victoryOwned and r.choice ~= "pass" then
            local w = r.result and r.result.winner
            if not w or (w.self and (not w.roll or not value or w.roll == value)) then match, count = r, count + 1 end
        end
    end
    local cached
    PruneDeparted()
    for _, item in ipairs(departed) do
        local v, w = item.view, item.view.result and item.view.result.winner
        if v.link == link and v.choice ~= "pass" and (not w or (w.self and (not w.roll or not value or w.roll == value))) then
            count, cached = count + 1, item
        end
    end
    if count > 1 then return nil end -- ambiguous live/departed instances keep native fallback
    local entry = match and C.View(match) or cached and cached.view or { link = link, state = "resolved", displayMode = "expanded" }
    entry.victory, entry.choice, entry.rollID = true, kind == 1 and "need" or "greed", nil
    entry.value = LR.Whole(value) and value >= 1 and value <= 100 and value or nil
    quantity = Plain(quantity)
    entry.count = LR.Whole(quantity) and quantity > 0 and quantity or 1
    if not entry.name and C_Item and C_Item.GetItemInfo then
        local ok, name, _, quality, _, _, typeName, subType, _, _, icon = pcall(C_Item.GetItemInfo, link)
        if ok then entry.name, entry.quality, entry.typeText, entry.icon = Plain(name), Plain(quality), Plain(subType) or Plain(typeName), Plain(icon) end
    end
    if not entry.icon and C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, link)
        if ok then entry.icon = Plain(icon) end
    end
    entry.name = entry.name or link:match("%[([^%]]+)%]") or "Loot"
    entry.key = match and match.key or cached and cached.key or (1000000000 + sequence)
    entry.total, entry.intensity = Total(), LR.Get("victoryIntensity")
    entry.motion = entry.intensity ~= "off"
    entry.total = entry.total + (entry.motion and V.HOLD_AT + 0.30 or 0)
    return entry, match, cached
end

function V.Accept(...)
    if not Enabled() or not owner or C.Placing() then return false end
    local args = { n = select("#", ...), ... }
    local link, quantity, kind, value = Plain(args[1]), Plain(args[2]), Plain(args[3]), Plain(args[4])
    -- The native event has no id. A bounded 1 s replay guard is used only when
    -- there is no fresh matching record and the previous event had a unique
    -- source record. Uncorrelated identical events fall back to native rather
    -- than silently discard a potentially distinct late win.
    local fresh = false
    for _, r in ipairs(Ro.Rolls()) do if r.link == link and not r.victoryOwned then fresh = true break end end
    local fingerprint = tostring(link) .. "|" .. tostring(quantity) .. "|" .. tostring(kind) .. "|" .. tostring(value)
    if not fresh then
        for _, r in ipairs(Ro.Rolls()) do
            if r.victoryOwned and r.victoryFingerprint == fingerprint then return true end
        end
    end
    for i = #recent, 1, -1 do
        if GetTime() - recent[i].at > 1 then table.remove(recent, i)
        elseif not fresh and recent[i].id == fingerprint then return recent[i].matched end
    end
    if #entries >= V.MAX_QUEUE then return false end
    sequence = sequence + 1
    local entry, match, cached = Snapshot(link, quantity, kind, value)
    if not entry then return false end
    entry.args = args
    inFlight = entry
    entries[#entries + 1] = entry
    -- Fully construct/draw first; only then take responsibility for the native event.
    if match then
        match.victoryOwned, match.victoryFingerprint = true, fingerprint
        Ro.Resolve(match, "victory")
    end
    C.PreviewStop(true); V.PreviewStop()
    C.Refresh()
    if not C.Ready() then
        table.remove(entries); if match then match.victoryOwned, match.victoryFingerprint = nil, nil end
        return false
    end
    recent[#recent + 1] = { id = fingerprint, at = GetTime(), matched = match ~= nil }
    if #recent > 64 then table.remove(recent, 1) end
    if cached then for i, item in ipairs(departed) do if item == cached then table.remove(departed, i) break end end end
    inFlight = nil
    return true
end

function V.Disable(replay)
    departed = {}
    if not owner and #entries == 0 and not (preview and preview.entry) then return end
    if relay then relay:UnregisterAllEvents() end
    V.PreviewStop()
    local pending = entries; entries = {}; recent = {}
    for _, entry in ipairs(pending) do
        if entry.card then V.ClearCard(entry.card); entry.card = nil end
        if replay and entry.args and entry ~= inFlight then Forward(entry.args) end
    end
    if owner then owner:RegisterEvent(EVENT) end
    owner, original = nil, nil
    C.Refresh()
end
function V.Sync()
    if not Enabled() then if owner then V.Disable(true) end return end
    for _, e in ipairs(entries) do
        if e.motion and LR.Get("victoryIntensity") == "off" then
            e.motion, e.total = false, Total()
            if e.card then
                local f = e.card.victory
                Cancel(f); V.Paint(f, V.MOTION_END)
                f.timer = C_Timer.NewTimer(math.max(0, e.total - (GetTime() - e.started)), Safe(function() Finish(e) end))
            end
        end
    end
    if owner then return end
    local alert = AlertFrame
    -- Never steal from another replacement or a protected/unknown alert host.
    if not (alert and alert.IsEventRegistered and alert:IsEventRegistered(EVENT) and alert.GetScript
        and alert.IsProtected and not alert:IsProtected()) then return end
    local handler = alert:GetScript("OnEvent")
    if type(handler) ~= "function" then return end
    if not relay then
        relay = CreateFrame("Frame")
        relay:SetScript("OnEvent", R.Perf.Wrap("loot.victory.event", function(_, event, ...)
            if owner and owner:IsEventRegistered(EVENT) then V.Disable(true); return end
            local nativeOwner, nativeHandler = owner, original
            local ok, accepted = pcall(V.Accept, ...)
            if not ok then R.Fault("loot victory", accepted) end
            if (not ok or not accepted) and nativeOwner and nativeHandler then nativeHandler(nativeOwner, EVENT, ...) end
            if not ok then V.Disable(true) end
            inFlight = nil
        end))
    end
    relay:RegisterEvent(EVENT)
    alert:UnregisterEvent(EVENT)
    owner, original = alert, handler
end

function V.PreviewStop()
    if preview and preview.entry then Finish(preview.entry); preview.entry = nil; preview:Hide() end
end
function V.Preview(choice, quality, sample)
    if C.Placing() or C.CardCount() > 0 then return false, "A loot card is showing right now." end
    C.PreviewStop(true); V.PreviewStop()
    if not preview then
        preview = CreateFrame("Frame", "TwichUILootVictoryPreview", UIParent)
        preview:SetSize(384, V.HEIGHT * 384 / 460); preview:SetFrameStrata("DIALOG")
        preview.card = C.NewCard(preview, { preview = true }); preview.card:SetPoint("TOPLEFT")
        preview:RegisterEvent("START_LOOT_ROLL")
        preview:SetScript("OnEvent", V.PreviewStop)
    end
    local scale = LR.Get("scale") / 100
    local x, y = LR.Place()
    preview:SetScale(scale); preview:ClearAllPoints()
    preview:SetPoint(LR.Get("growth") == "up" and "BOTTOM" or "TOP", UIParent, "CENTER", x / scale, y / scale)
    local e = C.SampleView("manual")
    e.victory, e.choice, e.value = true, choice == "greed" and "greed" or "need", 87
    e.quality, e.total, e.intensity = quality or 2, Total(), LR.Get("victoryIntensity")
    local samples = {
        [2] = { "Verdant Scholar's Mantle", "Shoulder", [[Interface\Icons\INV_Shoulder_23]] },
        [3] = { "Shieldward Battleplate", "Chest", [[Interface\Icons\INV_Chest_Plate16]] },
        [4] = { "Stormrend Titanblade", "Two-Handed Sword", [[Interface\Icons\INV_Sword_62]] },
        [5] = { "Dawnfire Mantle", "Shoulder", [[Interface\Icons\INV_Shoulder_23]] },
    }
    local item = samples[e.quality] or samples[2]
    e.name, e.typeText, e.icon = item[1], item[2], item[3]
    e.displayMode = type(sample) == "table" and sample.display == "collapsed" and "collapsed" or "expanded"
    -- Optional synthetic fixtures for long-name/upgrade preview checks only.
    if type(sample) == "table" then
        if type(sample.name) == "string" and #sample.name <= 256 and not sample.name:find("[%c|]") then e.name = sample.name end
        if type(sample.upgrade) == "boolean" then e.upgrade = sample.upgrade end
    end
    e.sampleLines = { e.typeText .. " · " .. R.LootRules.QualityName(e.quality), "Example item for the victory preview." }
    e.sellPrice, e.upgradeLines = nil, nil
    e.motion, e.state = e.intensity ~= "off", "resolved"
    e.total = e.total + (e.motion and V.HOLD_AT + 0.30 or 0)
    preview.entry = e
    preview:Show()
    local ok, err = pcall(V.Draw, preview.card, e)
    if ok then preview:SetHeight(err) end
    if not ok then
        V.PreviewStop(); R.Fault("loot victory preview", err)
        return false, "The victory artwork could not be loaded."
    end
    return true
end
-- Developer/simulator pose capture. Synthetic preview only; never pauses a live
-- win, consumes a result, changes settings, or plays sound while seeking.
function V.PreviewAt(seconds)
    if not (preview and preview.entry and LR.Finite(seconds) and seconds >= 0) then return false end
    local e, f = preview.entry, preview.card.victory
    f.seeking = true
    Cancel(f)
    V.Paint(f, math.min(seconds, V.MOTION_END), true)
    if e.motion then
        f:SetAlpha(seconds < e.total - 0.30 and 1 or 1 - Smooth((seconds - e.total + 0.30) / 0.30))
        if seconds >= e.total - 0.30 then f.phase = "fade" end
    else
        f:SetAlpha(seconds < e.total and 1 or 0)
        f.phase = seconds < e.total and "static" or "finished"
    end
    return true
end
function V.PreviewCard() return preview and preview.card end
LR.Subscribe(function() V.Sync() end)
