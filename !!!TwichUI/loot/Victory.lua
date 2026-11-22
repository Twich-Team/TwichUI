-- Confirmed self wins only. Owns one native event, never the global alert system.
-- Card artwork/timeline: assets/loot-victory; architecture: docs/loot-victory.md.
local R = TwichUI
local LR, Ro, C = R.LootRolls, R.LootRoll, R.LootCards
local V = {}
R.LootVictory = V
local ART = R.PATH .. [[media\loot\victory\]]
local EVENT = "LOOT_ITEM_ROLL_WON"
local entries, recent = {}, {}
local sequence, pool = 0, 0
local relay, owner, original
local preview, inFlight
local lastSound = -100
V.MAX_QUEUE = 32
V.HEIGHT, V.MOTION_END, V.SOUND_AT = 218, 1.75, 0.30

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
function V.PoolSize() return pool end
function V.Listening() return owner ~= nil end

local function Finish(entry)
    if entry.finished then return end
    entry.finished = true
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
    spark_bright = { 11 / 128, 117 / 128, 6 / 128, 122 / 128 },
    spark_small = { 6 / 64, 58 / 64, 4 / 64, 60 / 64 },
    dust_soft = { 12 / 64, 52 / 64, 12 / 64, 52 / 64 },
    dust_micro = { 8 / 32, 24 / 32, 8 / 32, 24 / 32 },
    laurel_left = { 30 / 128, 77 / 128, 14 / 128, 91 / 128 },
    laurel_right = { 41 / 128, 91 / 128, 13 / 128, 89 / 128 },
    sheen_ribbon = { 0, 1, 40 / 128, 89 / 128 },
    rim_glint = { 0, 1, 20 / 64, 45 / 64 },
    badge_backing = { 0, 1, 8 / 64, 58 / 64 },
    halo_uncommon = { 12 / 256, 244 / 256, 12 / 256, 244 / 256 },
    halo_rare = { 12 / 256, 244 / 256, 12 / 256, 244 / 256 },
    halo_epic = { 12 / 256, 244 / 256, 12 / 256, 244 / 256 },
    halo_legendary = { 12 / 256, 244 / 256, 12 / 256, 244 / 256 },
}
-- Existing eight pooled sprites: six in Subtle, eight in Full. Principal stars
-- now share the 1.15–1.70 s finishing cue; supporting sparks retain the burst.
-- x/y, short drift x/y, canvas w/h, supplied sprite, stagger. A side anchor
-- follows the measured title/laurel group instead of floating near the corners.
local PARTICLES = {
    { 48, 96, -3, -3, 32, 35, "spark_bright", 0, finish = true },
    { 240, 64, 0, 0, 28, 30, "spark_bright", 0.04, finish = true },
    { 0, 49, -8, -10, 18, 19, "spark_small", 0.05, side = -1 },
    { 0, 49, 8, -10, 16, 17, "spark_small", 0.12, side = 1 },
    { 42, 133, -12, -16, 14, 14, "dust_soft", 0.08 },
    { 91, 137, 8, -18, 12, 12, "dust_micro", 0.18 },
    { 98, 142, 3, -3, 30, 33, "spark_bright", 0.08, finish = true },
    { 96, 102, 10, -12, 16, 17, "spark_small", 0.20 },
}
local function Clamp(v) return math.max(0, math.min(1, v)) end
local function EaseOut(v) v = 1 - Clamp(v); return 1 - v * v * v end
local function At(region, parent, x, y)
    region:ClearAllPoints(); region:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
end
function V.Paint(f, t, silent)
    local entry = f.entry
    local motion = entry.motion
    local reveal = motion and EaseOut(t / 0.45) or 1
    f.header:SetAlpha(reveal)
    f.header:ClearAllPoints(); f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -5 * (1 - reveal))
    local resolve = motion and Smooth(t / 0.20) or 1
    f.base:SetAlpha(resolve); f.content:SetAlpha(resolve)
    if entry.transition then
        local card = entry.card
        card.body:SetAlpha(1 - resolve); card.shell:SetAlpha(1 - resolve)
        if resolve >= 1 then card.body:Hide(); card.shell:Hide() end
    end
    -- Natural painted aspect ratios inside a true clipping frame. The white/gold
    -- core and short trailing ribbon travel over the metal rail, above all text.
    local sweep = (t - 0.30) / 0.75
    local envelope = motion and Smooth(sweep / 0.12) * (1 - Smooth((sweep - 0.82) / 0.18)) or 0
    local rich = entry.intensity == "full"
    local x = -58 + Smooth(sweep) * 508
    At(f.sheen, f.railCanvas, x - 22, 6)
    At(f.trail, f.railCanvas, x - 48, 6)
    At(f.glint, f.railCanvas, x, 6)
    At(f.sweepStar, f.railCanvas, x, 6)
    f.sheen:SetAlpha(envelope * (rich and 1 or 0.85))
    f.trail:SetAlpha(envelope * (rich and 0.50 or 0.38))
    f.glint:SetAlpha(envelope)
    f.sweepStar:SetAlpha(envelope * (rich and 0.8 or 0.65))
    local qualityGain = entry.quality == 5 and 1.10 or entry.quality == 4 and 1.05 or 1
    for i, data in ipairs(PARTICLES) do
        local start, duration = data.finish and 1.15 or 0.55, data.finish and 0.55 or 0.90
        local p = Clamp((t - start - data[8]) / (duration - data[8]))
        local strength = Smooth(p / 0.16) * (1 - Smooth((p - 0.28) / 0.72))
        local x0 = data.side and 230 + data.side * (f.title:GetWidth() / 2 + 18) or data[1]
        local texture = f.particles[i]
        At(texture, f.effects, x0 + data[3] * EaseOut(p), data[2] + data[4] * EaseOut(p))
        texture:SetAlpha(motion and (rich or i <= 6) and math.min(1, strength * qualityGain * (data.finish and 0.92 or 1)) or 0)
    end
    -- A delayed, single rarity rise follows the first finishing reflections.
    -- The supplied ring peaks just outside the icon rather than behind it.
    local glow = Clamp((t - 1.24) / 0.46)
    local rise = motion and Smooth(glow / 0.20) * (1 - Smooth((glow - 0.30) / 0.70)) or 0
    f.halo:SetAlpha(f.haloRest + (f.hasHalo and 0.16 * rise or 0))
    if not silent and t >= V.SOUND_AT then Sound(entry) end
    f.phase = t < 0.45 and "reveal" or t < 0.55 and "flourish" or t < 1.10 and "burst" or t < V.MOTION_END and "finish" or "static"
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
    if t:SetTexture(ART .. name .. ".tga") == false then error("Missing loot victory texture: " .. name) end
    t:SetSize(w, h); t:SetBlendMode(blend or "BLEND")
    if UV[name] then t:SetTexCoord(unpack(UV[name])) end
    return t
end
-- Fit once when drawing, retaining the unabridged name in the item tooltip.
-- Remove complete UTF-8 characters; never split a localized item's final glyph.
local function ItemName(label, name)
    label:SetText(name)
    local last = #name
    while last > 0 and label:GetStringWidth() > label:GetWidth() do
        last = last - 1
        while last > 0 and name:byte(last + 1) >= 128 and name:byte(last + 1) < 192 do last = last - 1 end
        label:SetText(name:sub(1, last) .. "...")
    end
end
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
local function Build(card)
    pool = pool + 1
    local f = CreateFrame("Frame", nil, card)
    card.victory = f -- retain partial builds so missing assets cannot grow the pool on retry
    f:SetSize(460, V.HEIGHT); f:SetScale(384 / 460); f:SetPoint("TOPLEFT")
    f:SetFrameLevel(card.body:GetFrameLevel() + 4)
    f.base = FrameArtwork(f)
    f.header = CreateFrame("Frame", nil, f); f.header:SetSize(460, 80)
    f.header:SetFrameLevel(f:GetFrameLevel() + 2)
    f.title = Font(f.header, 24, true); f.title:SetText("YOU WON!")
    -- Measure real client font metrics so the laurels bracket the words closely
    -- and symmetrically. The title stays centered at x230 at every font fallback.
    f.title:SetSize(math.min(204, math.max(112, f.title:GetStringWidth() + 4)), 30)
    f.title:SetPoint("TOP", f.header, "TOP", 0, -24)
    f.title:SetJustifyH("CENTER"); f.title:SetTextColor(0.93, 0.79, 0.50)
    f.laurels = { Texture(f.header, "laurel_left", 19, 31), Texture(f.header, "laurel_right", 20, 31) }
    f.laurels[1]:SetPoint("RIGHT", f.title, "LEFT", -8, 0)
    f.laurels[2]:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
    f.dividers = { Texture(f.header, "rim_glint", 52, 5, "BORDER"), Texture(f.header, "rim_glint", 52, 5, "BORDER") }
    At(f.dividers[1], f.header, 186, 59); At(f.dividers[2], f.header, 274, 59)
    f.dividers[1]:SetAlpha(0.22); f.dividers[2]:SetAlpha(0.22)
    f.emblem = Texture(f.header, "emblem_need", 24, 24); At(f.emblem, f.header, 230, 64)
    f.content = CreateFrame("Frame", nil, f); f.content:SetAllPoints(); f.content:SetFrameLevel(f:GetFrameLevel() + 2)
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
    f.hit = CreateFrame("Button", nil, f.content); f.hit:SetPoint("TOPLEFT", 43, -76); f.hit:SetSize(380, 82)
    f.hit:RegisterForClicks("LeftButtonUp")
    f.hit:SetScript("OnEnter", function(self) if f.entry then C.ItemTip(self, f.entry) end end)
    f.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.hit:SetScript("OnClick", function()
        if f.entry and not f.entry.preview and f.entry.link and HandleModifiedItemClick then HandleModifiedItemClick(f.entry.link) end
    end)
    f.rail = CreateFrame("Frame", nil, f); f.rail:SetPoint("TOPLEFT", 34, -12); f.rail:SetSize(392, 12)
    f.rail:SetFrameLevel(f:GetFrameLevel() + 4); f.rail:SetClipsChildren(true)
    f.railCanvas = CreateFrame("Frame", nil, f.rail); f.railCanvas:SetAllPoints()
    f.sheen = Texture(f.railCanvas, "sheen_ribbon", 116, 11, "OVERLAY", "ADD")
    f.trail = Texture(f.railCanvas, "sheen_ribbon", 92, 9, "ARTWORK", "ADD")
    f.glint = Texture(f.railCanvas, "rim_glint", 64, 6, "OVERLAY", "ADD")
    f.sweepStar = Texture(f.railCanvas, "spark_bright", 34, 37, "OVERLAY", "ADD")
    f.effects = CreateFrame("Frame", nil, f); f.effects:SetAllPoints(); f.effects:SetFrameLevel(f:GetFrameLevel() + 4)
    f.effects:EnableMouse(false)
    f.particles = {}
    for i, data in ipairs(PARTICLES) do f.particles[i] = Texture(f.effects, data[7], data[5], data[6], "OVERLAY", "ADD") end
    f.finish = f.particles[1] -- existing finishing cue, now shared by two/three pooled glints
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
    if f.entry == entry then return V.HEIGHT * 384 / 460 end
    V.ClearCard(card)
    entry.transition = card.view ~= nil and not card.view.victory and not entry.preview
    entry.card, f.entry = card, entry
    card.live, card.enter, card.view = false, 1, entry
    card:SetAlpha(1); card:SetHeight(V.HEIGHT * 384 / 460)
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
    f.badge:SetShown(entry.upgrade == true and LR.Get("showUpgrade")); f.upgrade:SetShown(entry.upgrade == true and LR.Get("showUpgrade"))
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
    return V.HEIGHT * 384 / 460
end

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
    if count > 1 then return nil end -- cannot distinguish identical concurrent drops: native fallback
    local entry = match and C.View(match) or { link = link, state = "resolved" }
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
    entry.key = match and match.key or (1000000000 + sequence)
    entry.total, entry.intensity = Total(), LR.Get("victoryIntensity")
    entry.motion = entry.intensity ~= "off"
    entry.total = entry.total + (entry.motion and V.MOTION_END + 0.30 or 0)
    return entry, match
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
    local entry, match = Snapshot(link, quantity, kind, value)
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
    inFlight = nil
    return true
end

function V.Disable(replay)
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
    -- Optional synthetic fixtures for long-name/upgrade preview checks only.
    if type(sample) == "table" then
        if type(sample.name) == "string" and #sample.name <= 256 and not sample.name:find("[%c|]") then e.name = sample.name end
        if type(sample.upgrade) == "boolean" then e.upgrade = sample.upgrade end
    end
    e.sampleLines = { e.typeText .. " · " .. R.LootRules.QualityName(e.quality), "Example item for the victory preview." }
    e.sellPrice, e.upgradeLines = nil, nil
    e.motion, e.state = e.intensity ~= "off", "resolved"
    e.total = e.total + (e.motion and V.MOTION_END + 0.30 or 0)
    preview.entry = e
    preview:Show()
    local ok, err = pcall(V.Draw, preview.card, e)
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
