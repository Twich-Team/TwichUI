-- Target Portrait Decorations: one controller, holder and texture for both styles.
-- Legacy dragons retain their frame-height/crook placement and customization.
-- Modern frames use the verified direct portrait backdrop and supplier aperture;
-- movement and scaling inherit from that parent. Observe only the named frame and
-- backdrop, once per reference, plus bounded startup retries; no polling/OnUpdate.
-- Create, reparent and modern geometry writes wait for combat end. Target texture
-- changes on an existing valid attachment affect only our unprotected texture.
-- Unit API values are secret-checked before classification. Off unregisters every
-- event and restores native art; settings/profile changes share this lifecycle.

local R = TwichUI
local Perf = R.Perf
local TA = R.TargetArt
local E = R.TargetArtEllesmere
local D = {}
R.TargetArtDisplay = D

local FRONT_LEVELS = 12   -- over EllesmereUI's border (+10), under its aura and text hosts (+18 and up)

local portrait, attachedStyle, refreshing
local hooked = setmetatable({}, { __mode = "k" })
local retryGeneration = 0
local holder, tex, host   -- our frame and texture, and the target frame they are on
local evf
local registered = {}
local status = "off"      -- "off", "waiting" (not logged in), "combat" (made after combat), "ready", or E.Find's why
local shown               -- the art id on the frame now, or nil
local placed = {}         -- what the texture was last laid out for: id, height, rev
local layoutRev = 1
local preview = { active = false, art = "boss" }
local stats = { updates = 0, layouts = 0 }
local placement = {}

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Modern() return TA.Get("style") == "modern" end
local function On() return R:Enabled("targetArt") end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local SyncEvents, Retry

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if preview.active then D.PreviewStop() end   -- a sample never carries into a fight
        return
    end
    -- one global lookup: finds the frame once EllesmereUI has made it, or a new one if it made its frames again
    if Modern() or event ~= "UNIT_CLASSIFICATION_CHANGED" then D.Attach() end
    D.Update()
    if Modern() and (event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD") then Retry() end
end

function SyncEvents()
    local want = {}
    if On() then
        want.PLAYER_ENTERING_WORLD, want.PLAYER_TARGET_CHANGED, want.UNIT_CLASSIFICATION_CHANGED = true, true, true
        if status == "combat" or Modern() then want.PLAYER_REGEN_ENABLED = true end
        if Modern() then
            want.ADDON_LOADED, want.UI_SCALE_CHANGED, want.DISPLAY_SIZE_CHANGED = true, true, true
        end
        if preview.active then want.PLAYER_REGEN_DISABLED = true end
    end
    if not evf then
        if next(want) == nil then return end
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", Perf.Wrap("targetart.event", OnEvent))
    end
    for event in pairs(registered) do
        if not want[event] then
            evf:UnregisterEvent(event)
            registered[event] = nil
        end
    end
    for event in pairs(want) do
        if not registered[event] then
            if event == "UNIT_CLASSIFICATION_CHANGED" and evf.RegisterUnitEvent then evf:RegisterUnitEvent(event, "target")
            else evf:RegisterEvent(event) end
            registered[event] = true
        end
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function HostHeight()
    local h = host and host:GetHeight()
    if Plain(h) and type(h) == "number" and h >= 1 then return h end
    return nil
end

local function ApplyLevel()
    local level = Plain(host:GetFrameLevel()) or 0
    if Modern() then
        if holder.SetFrameStrata and host.GetFrameStrata then holder:SetFrameStrata(host:GetFrameStrata()) end
        -- Portrait and border above our art, bars/text above it as on the player
        -- feature. No external frame level/strata setters are called.
        holder:SetFrameLevel(math.max(0, level - 1))
        return
    end
    if TA.Get("layer") == "behind" then holder:SetFrameLevel(math.max(0, level - 1))
    else holder:SetFrameLevel(level + FRONT_LEVELS) end
end

local function Layout(id)
    if Modern() then
        if not portrait or E.Portrait(host) ~= portrait then return false end
        local w, h = Plain(portrait:GetWidth()), Plain(portrait:GetHeight())
        local p = TA.ModernPlacement(id, w, h, placement)
        if not p then return false end
        -- Existing geometry may be retained in combat; new layout waits safely.
        if InCombat() then
            if not (placed.style == "modern" and placed.width == w and placed.height == h
                and placed.rev == layoutRev and placed.portrait == portrait) then return false end
            if placed.id ~= id then
                if tex:SetTexture(TA.MODERN[id].path) == false then return false end
                placed.id = id
            end
            return true
        end
        if placed.style ~= "modern" or placed.id ~= id then
            if tex:SetTexture(TA.MODERN[id].path) == false then return false end
        end
        if placed.style ~= "modern" or placed.width ~= w or placed.height ~= h
            or placed.rev ~= layoutRev or placed.portrait ~= portrait then
            stats.layouts = stats.layouts + 1
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetSize(p.w, p.h)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", portrait, "CENTER", p.x, p.y)
            tex:SetAlpha(1)
            ApplyLevel()
        end
        ApplyLevel()
        placed.id, placed.style, placed.width, placed.height, placed.rev, placed.portrait = id, "modern", w, h, layoutRev, portrait
        return true
    end
    local h = HostHeight()
    if placed.style == "legacy" and placed.id == id and placed.height == h and placed.rev == layoutRev then return true end
    stats.layouts = stats.layouts + 1
    local p = TA.Placement(id, h, nil, placement)
    if placed.id ~= id or placed.style ~= "legacy" then tex:SetTexture(TA.ART[id].path) end
    tex:SetTexCoord(p.l, p.r, p.t, p.b)
    tex:SetSize(p.w, p.h)
    tex:ClearAllPoints()
    tex:SetPoint(p.point, host, p.relPoint, p.x, p.y)
    tex:SetAlpha(TA.Get("opacity") / 100)
    ApplyLevel()
    placed.id, placed.height, placed.rev, placed.style = id, h, layoutRev, "legacy"
    return true
end

-- Which artwork the frame should show now: the preview's, else the target's (nil: none).
local function Wanted()
    if preview.active then return preview.art end
    if not (UnitExists and Plain(UnitExists("target"))) then return nil end
    local classification = Plain(UnitClassification and UnitClassification("target"))
    local isBoss = Plain(UnitIsBossMob and UnitIsBossMob("target"))
    if Modern() then return TA.PickModern(classification, isBoss) end
    return TA.Pick(classification, isBoss)
end

function D.Update()
    if not (holder and host and status == "ready") then return end
    stats.updates = stats.updates + 1
    local id = On() and Wanted() or nil
    if id and Modern() and not TA.MODERN[id] then id = nil end
    if id and not Layout(id) then id = nil end
    if id then
        tex:Show()
        holder:Show()
    else
        tex:Hide()
    end
    shown = id
    E.HideNative(host, id ~= nil and On() and (Modern() or TA.Get("hideEllesmere")))
end

local function OnSized()
    if shown then D.Update() end   -- Layout sees the new height
end

---------------------------------------------------------------------------
-- Attaching
---------------------------------------------------------------------------
-- Finds EllesmereUI's target frame and puts the holder on it. Safe at any time; does nothing new when attached.
local function Observe(f)
    if hooked[f] or type(f.HookScript) ~= "function" then return end
    hooked[f] = true
    local function Changed() if On() and Modern() then D.Refresh() end end
    for _, event in ipairs({ "OnSizeChanged", "OnShow", "OnHide" }) do f:HookScript(event, Changed) end
    if hooksecurefunc then
        hooksecurefunc(f, "SetFrameStrata", Changed)
        hooksecurefunc(f, "SetFrameLevel", Changed)
    end
end

Retry = function()
    retryGeneration = retryGeneration + 1
    local generation = retryGeneration
    if not (On() and Modern() and C_Timer and C_Timer.After) then return end
    for _, delay in ipairs({ 0, 0.5, 2, 5 }) do
        C_Timer.After(delay, function()
            if generation == retryGeneration and On() and Modern() then D.Refresh() end
        end)
    end
end

function D.Attach()
    if not On() then return end
    if not (R.Life and R.Life.loggedIn) then status = "waiting"; return end
    local frame, why = E.Find()
    local p = Modern() and frame and E.Portrait(frame) or nil
    if Modern() and frame then Observe(frame); if p then Observe(p) end end
    if not frame or (Modern() and (not p or not p:IsShown())) then
        status = why or "portrait"
        if holder then tex:Hide() end
        E.RestoreNative()
        shown = nil
        SyncEvents()
        return
    end
    local style = TA.Get("style")
    if holder and host == frame and portrait == p and attachedStyle == style then
        if status ~= "ready" then status = "ready"; SyncEvents() end
        return
    end
    if Modern() or attachedStyle ~= style then
        if tex then tex:Hide(); shown = nil end
        E.RestoreNative()
    end
    if InCombat() then
        status = "combat"
        SyncEvents()
        return
    end
    if host and host ~= frame then E.RestoreNative() end
    local parent = p or frame
    if not holder then
        holder = CreateFrame("Frame", nil, parent)
        holder:EnableMouse(false)
        tex = holder:CreateTexture(nil, "ARTWORK")
        tex:Hide()
        holder:SetScript("OnSizeChanged", OnSized)
    else
        holder:SetParent(parent)
    end
    -- SetFrameStrata in modern mode fixes the strata. Restore the original
    -- inherited legacy behavior when returning to the frame (Forever PlayerFrame
    -- uses SetFixedFrameStrata(false) for the same parent-inheritance contract).
    if not Modern() and holder.SetFixedFrameStrata then holder:SetFixedFrameStrata(false) end
    holder:ClearAllPoints()
    holder:SetAllPoints(parent)
    host, portrait, attachedStyle = frame, p, style
    placed.id, placed.style = nil, nil
    status = "ready"
    SyncEvents()
end

---------------------------------------------------------------------------
-- Refresh: everything, from the top. Safe to call at any time.
---------------------------------------------------------------------------
function D.Refresh()
    if refreshing then return end
    refreshing = true
    if not On() then
        retryGeneration = retryGeneration + 1
        preview.active = false
        if holder then tex:Hide() end
        shown = nil
        E.RestoreNative()
        status = "off"
        SyncEvents()
        refreshing = false
        return
    end
    local starting = status == "off"
    if starting then status = "waiting" end
    SyncEvents()
    D.Attach()
    D.Update()
    refreshing = false
    if starting then Retry() end
end

---------------------------------------------------------------------------
-- Preview (settings)
---------------------------------------------------------------------------
function D.PreviewActive() return preview.active end
function D.PreviewArt() return preview.art end

-- Which artwork the preview shows (any of the three). Changes nothing saved.
function D.SetPreviewArt(id)
    if not (Modern() and TA.MODERN[id] or not Modern() and TA.ART[id]) then return false end
    preview.art = id
    if preview.active then D.Update() end
    return true
end

-- Shows the preview artwork on the target frame whatever the target is (the frame itself only shows while you have a
-- target). Only while the feature is on, and not in combat. Ends with the settings, combat or switching off.
function D.PreviewStart()
    if not On() then return false, "off" end
    if InCombat() then return false, "combat" end
    if not preview.active then
        preview.active = true
        SyncEvents()
        D.Update()
    end
    return true
end

function D.PreviewStop()
    if not preview.active then return end
    preview.active = false
    SyncEvents()
    D.Update()
end

---------------------------------------------------------------------------
-- Status, for settings and the tests: plain values
---------------------------------------------------------------------------
function D.Status() return status end

function D.Snapshot()
    local events = 0
    for _ in pairs(registered) do events = events + 1 end
    return { enabled = On(), status = status, shown = shown, preview = preview.active, previewArt = preview.art,
        style = TA.Get("style"), portrait = portrait,
        events = events, built = holder ~= nil, host = host, updates = stats.updates, layouts = stats.layouts,
        nativeHidden = E.NativeHidden(), hasNative = host ~= nil and E.HasNative(host) }
end

function D.Texture() return tex end
function D.Holder() return holder end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
TA.Subscribe(function(key)
    if key == "style" or key == nil then
        layoutRev = layoutRev + 1
        if Modern() and not TA.MODERN[preview.art] then preview.art = "boss" end
        D.Refresh()
        if status ~= "ready" then Retry() end
    elseif Modern() then
        -- Legacy preferences stay saved without changing the modern appearance.
        return
    elseif not (holder and shown) then
        D.Refresh()
    elseif key == "opacity" then
        tex:SetAlpha(TA.Get("opacity") / 100)
    elseif key == "layer" then
        ApplyLevel()
    elseif key == "hideEllesmere" or (key and key:find("^map")) then
        D.Update()
    else
        layoutRev = layoutRev + 1
        D.Update()
    end
end)

R:OnInit(function() if On() then D.Refresh() end end)
R:On("PLAYER_LOGIN", function() if On() then D.Refresh(); Retry() end end)
R.Profiles.OnApply("layout", "targetArt", function() preview.active = false; D.Refresh(); Retry() end)
R.OnSettingsClosed(function() D.PreviewStop() end)
