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

-- At 1.2 s there is no update script. A single cancellable timer wakes the fade.
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

local PARTICLES = { { -8, -4, 10, "spark_small" }, { 14, -7, 8, "dust_soft" },
    { 7, 12, 12, "spark_small" }, { -15, 10, 7, "dust_micro" }, { 22, 3, 8, "dust_soft" } }
function V.Paint(f, t)
    local entry = f.entry
    local motion = entry.motion
    local reveal = motion and Smooth((t - 0.15) / 0.30) or 1
    f.title:SetAlpha(reveal); f.emblem:SetAlpha(reveal)
    f.title:ClearAllPoints(); f.title:SetPoint("TOP", f, "TOP", 0, -13 + 2 * (1 - reveal))
    f.emblem:ClearAllPoints(); f.emblem:SetPoint("TOPLEFT", f, "TOPLEFT", 134, -10 + 2 * (1 - reveal))
    local resolve = motion and Smooth(t / 0.2) or 1
    f.base:SetAlpha(resolve); f.content:SetAlpha(resolve)
    if entry.transition then
        local card = entry.card
        card.body:SetAlpha(1 - resolve); card.shell:SetAlpha(1 - resolve)
        if resolve >= 1 then card.body:Hide(); card.shell:Hide() end
    end
    local sweep = (t - 0.35) / 0.45
    local glint = motion and sweep > 0 and sweep < 1
    f.glint:SetAlpha(glint and math.sin(sweep * math.pi) * 0.6 or 0)
    f.sheen:SetAlpha(glint and math.sin(sweep * math.pi) * 0.25 or 0)
    local x = 30 + Smooth(sweep) * 336
    f.glint:ClearAllPoints(); f.glint:SetPoint("TOPLEFT", f, "TOPLEFT", x, -15)
    f.sheen:ClearAllPoints(); f.sheen:SetPoint("TOPLEFT", f, "TOPLEFT", x - 10, -16)
    local p = math.max(0, math.min(1, (t - 0.45) / 0.75))
    local intensity = entry.intensity == "full" and 0.8 or 0.45
    if entry.quality == 4 then intensity = intensity * 1.1 elseif entry.quality == 5 then intensity = intensity * 1.2 end
    for i, data in ipairs(PARTICLES) do
        local texture = f.particles[i]
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", f, "TOPLEFT", 74 + data[1] + data[1] * p * 0.12, -99 + data[2] + (8 + i % 3 * 2) * p)
        texture:SetAlpha(motion and p > 0 and p < 1 and math.sin(p * math.pi) * (1 - p) * intensity or 0)
    end
    if t >= 0.48 then Sound(entry) end
    f.phase = t < 0.2 and "resolve" or t < 0.45 and "reveal" or t < 0.8 and "sheen" or t < 1.2 and "particles" or "static"
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
    f.timer = C_Timer.NewTimer(math.max(0, f.entry.total - 0.3 - (GetTime() - f.entry.started)), Safe(function()
        f.timer = nil
        if not f.entry or not f:IsShown() then return end
        local started = GetTime()
        f.phase = "fade"
        f:SetScript("OnUpdate", R.Perf.Wrap("loot.victory.tick", Safe(function()
            local p = (GetTime() - started) / 0.3
            if p >= 1 then Finish(f.entry) else f:SetAlpha(1 - Smooth(p)) end
        end)))
    end))
end
local function Animate(f)
    V.Paint(f, 0)
    f:SetScript("OnUpdate", R.Perf.Wrap("loot.victory.tick", Safe(function()
        local t = GetTime() - f.entry.started
        V.Paint(f, math.min(t, 1.2))
        if t >= 1.2 then Rest(f) end
    end)))
end

local function Texture(parent, name, w, h, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    if t:SetTexture(ART .. name .. ".tga") == false then error("Missing loot victory texture: " .. name) end
    t:SetSize(w, h); t:SetBlendMode("BLEND")
    return t
end
local function Font(parent, size, serif)
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT, size, "")
    if R.CraftLook and R.CraftLook.Font then R.CraftLook.Font(f, size, false, serif and "serif" or nil) end
    f:SetTextColor(0.93, 0.87, 0.75); f:SetJustifyH("LEFT"); f:SetWordWrap(false)
    return f
end
local function Build(card)
    pool = pool + 1
    local f = CreateFrame("Frame", nil, card)
    card.victory = f -- retain even a partial build: failed assets cannot grow the pool on each retry
    f:SetSize(460, 200); f:SetScale(384 / 460); f:SetPoint("TOPLEFT")
    f:SetFrameLevel(card.body:GetFrameLevel() + 4)
    f.base = Texture(f, "loot_won_frame", 460, 200, "BACKGROUND")
    f.base:SetAllPoints(); f.base:SetTexCoord(0, 1, 0, 444 / 512)
    f.title = Font(f, 25, true); f.title:SetText("YOU WON!"); f.title:SetTextColor(0.90, 0.75, 0.45)
    f.emblem = Texture(f, "emblem_need", 30, 30)
    f.content = CreateFrame("Frame", nil, f); f.content:SetAllPoints()
    f.halo = Texture(f.content, "halo_uncommon", 73, 73, "BACKGROUND")
    f.halo:SetPoint("CENTER", f, "TOPLEFT", 74, -99)
    f.icon = f.content:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(50, 50); f.icon:SetPoint("TOPLEFT", 49, -74)
    -- Four native one-pixel item-quality edges, the dynamic border specified by the art kit.
    f.edges = {}
    for i, pos in ipairs({ { "TOPLEFT", 48, -73, 52, 1 }, { "TOPLEFT", 48, -124, 52, 1 },
        { "TOPLEFT", 48, -73, 1, 52 }, { "TOPLEFT", 99, -73, 1, 52 } }) do
        local e = f.content:CreateTexture(nil, "OVERLAY"); e:SetPoint(pos[1], pos[2], pos[3]); e:SetSize(pos[4], pos[5]); f.edges[i] = e
    end
    f.name = Font(f.content, 18, true); f.name:SetPoint("TOPLEFT", 116, -73); f.name:SetWidth(308)
    f.sub = Font(f.content, 15, true); f.sub:SetPoint("TOPLEFT", 116, -98); f.sub:SetWidth(308)
    f.method = Font(f.content, 15, true); f.method:SetPoint("TOPLEFT", 116, -118); f.method:SetWidth(308)
    f.footer = Font(f.content, 15, true); f.footer:SetPoint("TOPLEFT", 47, -160); f.footer:SetWidth(250)
    f.badge = Texture(f.content, "badge_backing", 122, 24); f.badge:SetPoint("TOPRIGHT", -32, -156)
    f.upgrade = Font(f.content, 11); f.upgrade:SetPoint("CENTER", f.badge, "CENTER"); f.upgrade:SetText("Potential Upgrade")
    f.hit = CreateFrame("Button", nil, f.content); f.hit:SetPoint("TOPLEFT", 47, -68); f.hit:SetSize(378, 68)
    f.hit:RegisterForClicks("LeftButtonUp")
    f.hit:SetScript("OnEnter", function(self) if f.entry then C.ItemTip(self, f.entry) end end)
    f.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.hit:SetScript("OnClick", function()
        if f.entry and not f.entry.preview and f.entry.link and HandleModifiedItemClick then HandleModifiedItemClick(f.entry.link) end
    end)
    -- Trim overlays are physically limited to the top metal rail (no text region).
    f.glint = Texture(f, "rim_glint", 64, 4, "OVERLAY")
    f.sheen = Texture(f, "sheen_ribbon", 84, 3, "OVERLAY")
    f.particles = {}
    for i, data in ipairs(PARTICLES) do f.particles[i] = Texture(f.content, data[4], data[3], data[3], "OVERLAY") end
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
    if f.entry == entry then return 200 * 384 / 460 end
    V.ClearCard(card)
    entry.transition = card.view ~= nil and not card.view.victory and not entry.preview
    entry.card, f.entry = card, entry
    card.live, card.enter, card.view = false, 1, entry
    card:SetAlpha(1); card:SetHeight(200 * 384 / 460)
    card.rollID = nil -- victory cards never authorize automatic actions or park live native roll controls
    card.timer:Hide(); card.time:Hide()
    for _, b in pairs(card.buttons) do b:Disable() end
    card.body:EnableMouse(false)
    -- Mouse stays disabled throughout resolution; individual controls cannot submit another choice.
    card.iconHit:EnableMouse(false); card.close:Disable()
    if not entry.transition then card.body:Hide(); card.shell:Hide() end
    local qc = R.LootRules.QUALITY_COLOR[entry.quality] or R.LootRules.QUALITY_COLOR[1]
    local qname = R.LootRules.QualityName(entry.quality)
    f.name:SetText(entry.name or "Loot"); f.name:SetTextColor(qc[1], qc[2], qc[3])
    f.sub:SetText((entry.typeText and entry.typeText .. " · " or "") .. qname)
    f.method:SetText((entry.choice == "need" and "Need roll" or "Greed roll") .. (entry.value and (": " .. entry.value) or ""))
    f.footer:SetText(entry.preview and "Sample victory" or "Loot roll won")
    f.badge:SetShown(entry.upgrade == true and LR.Get("showUpgrade")); f.upgrade:SetShown(entry.upgrade == true and LR.Get("showUpgrade"))
    f.icon:SetTexture(entry.icon or [[Interface\Icons\INV_Misc_QuestionMark]])
    for _, e in ipairs(f.edges) do e:SetColorTexture(qc[1], qc[2], qc[3], 1) end
    local halos = { [2] = "uncommon", [3] = "rare", [4] = "epic", [5] = "legendary" }
    f.halo:SetTexture(halos[entry.quality] and ART .. "halo_" .. halos[entry.quality] .. ".tga" or nil)
    f.halo:SetAlpha(entry.intensity == "full" and 0.5 or 0.35)
    f.emblem:SetTexture(ART .. "emblem_" .. entry.choice .. ".tga")
    f:SetAlpha(1); f:Show()
    entry.started = GetTime()
    if entry.motion then Animate(f) else
        V.Paint(f, 1.2)
        f.timer = C_Timer.NewTimer(entry.total, Safe(function() f.timer = nil; Finish(entry) end))
    end
    return 200 * 384 / 460
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
            e.motion = false
            if e.card then
                local f = e.card.victory
                Cancel(f); V.Paint(f, 1.2)
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
function V.Preview(choice, quality)
    if C.Placing() or C.CardCount() > 0 then return false, "A loot card is showing right now." end
    C.PreviewStop(true); V.PreviewStop()
    if not preview then
        preview = CreateFrame("Frame", "TwichUILootVictoryPreview", UIParent)
        preview:SetSize(384, 200 * 384 / 460); preview:SetFrameStrata("DIALOG")
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
    e.motion, e.state = e.intensity ~= "off", "resolved"
    preview.entry = e
    preview:Show()
    local ok, err = pcall(V.Draw, preview.card, e)
    if not ok then
        V.PreviewStop(); R.Fault("loot victory preview", err)
        return false, "The victory artwork could not be loaded."
    end
    return true
end
function V.PreviewCard() return preview and preview.card end
LR.Subscribe(function() V.Sync() end)
