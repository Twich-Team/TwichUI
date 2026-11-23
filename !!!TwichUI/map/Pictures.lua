-- WMO minimap pictures in continent yards, shared by underground cities and caves.
-- Geometry is prepared once per active place; only intersecting pictures bind textures.
-- Numeric data's provenance: LocalData.lua / LICENSES/OpenMap.txt. Independent renderer.
local R = TwichUI
local VM, MW = R.MapViewMath, R.MapWorld
local MP = {}
R.MapPictures = MP
local MAX_PICTURES = 256
local sets = setmetatable({}, { __mode = "k" })
local pending, loader, loadTick = {}, nil, nil

function MP.Forget(tex)
    pending[tex] = nil
    if loader and not next(pending) then loader:SetScript("OnUpdate", nil) end
end

local function LoadStep(_, elapsed)
    for tex, entry in pairs(pending) do
        entry.age = entry.age + elapsed
        if tex:IsObjectLoaded() then
            entry.fade = (entry.fade or 0) + elapsed
            tex:SetAlpha(entry.alpha * VM.Fade(entry.fade, 0, 0.15))
            tex:Show()
            if entry.fade >= 0.15 then pending[tex] = nil end
        elseif entry.age >= 10 then
            -- Failed/absent assets cannot keep an updater alive indefinitely. Painted art stays visible.
            tex:Hide()
            pending[tex] = nil
        end
    end
    if not next(pending) then loader:SetScript("OnUpdate", nil) end
end

-- IsObjectLoaded is the Forever TextureLoadingGroupMixin's own readiness check.
-- No updater is needed for synchronously available textures or clients without this API.
function MP.Show(tex, alpha)
    local entry = pending[tex]
    if alpha <= 0.005 then MP.Forget(tex); tex:SetAlpha(0); tex:Hide(); return end
    if entry then entry.alpha = alpha return end
    if tex.IsObjectLoaded and tex:IsObjectLoaded() == false then
        pending[tex] = { alpha = alpha, age = 0 }
        tex:Hide()
        if not loader then
            loader = CreateFrame("Frame")
            loadTick = R.Perf and R.Perf.Wrap("map.texture.load", LoadStep) or LoadStep
        end
        loader:SetScript("OnUpdate", loadTick)
    else
        tex:SetAlpha(alpha)
        tex:Show()
    end
end

function MP.Create(parent)
    local set = { parent = parent, free = {}, used = {}, geometry = {}, made = 0, binds = 0 }
    sets[set] = true
    return set
end

function MP.Clear(set)
    for i, tex in pairs(set.used) do
        MP.Forget(tex)
        tex:Hide()
        tex:SetTexture(nil)
        tex:ClearAllPoints()
        set.free[#set.free + 1] = tex
        set.used[i] = nil
    end
end

function MP.Set(set, record)
    if set.record == record then return end
    MP.Clear(set)
    set.record, set.geometry = record, {}
    if not record then return end
    local pictures = record[6]
    if type(pictures) ~= "table" or #pictures % 7 ~= 0 then return end
    for i = 1, #pictures, 7 do
        local file, x, y, side, angle, u1, v0 = unpack(pictures, i, i + 6)
        if VM.Finite(file) and file > 0 and VM.Finite(x) and VM.Finite(y) and VM.Finite(side) and side > 0
            and VM.Finite(angle) and VM.Finite(u1) and VM.Finite(v0) then
            local u0, top, right, bottom = MW.YardsRect(record[1], x - side / 2, y - side / 2, x + side / 2, y + side / 2)
            if u0 then
                local n = #set.geometry + 1
                -- Rotation can carry a corner beyond the unrotated square. Cull its bounding circle.
                local padU, padV = (right - u0) * 0.21, (bottom - top) * 0.21
                set.geometry[n] = { file, u0, top, right, bottom, angle, u1, v0,
                    u0 - padU, top - padV, right + padU, bottom + padV }
            end
        end
    end
end

local function Update(set, u0, v0, u1, v1, alpha)
    local W, H = MW.Size()
    -- Release first, so a pan never transiently doubles the pool.
    for i, tex in pairs(set.used) do
        local g = set.geometry[i]
        if alpha <= 0.005 or g[11] < u0 or g[9] > u1 or g[12] < v0 or g[10] > v1 then
            MP.Forget(tex)
            tex:Hide(); tex:SetTexture(nil); tex:ClearAllPoints()
            set.used[i] = nil
            set.free[#set.free + 1] = tex
        end
    end
    if alpha <= 0.005 then return end
    local active = 0
    for i, g in ipairs(set.geometry) do
        if g[11] >= u0 and g[9] <= u1 and g[12] >= v0 and g[10] <= v1 and active < MAX_PICTURES then
            active = active + 1
            local tex = set.used[i]
            if not tex then
                tex = table.remove(set.free)
                if not tex then tex = set.parent:CreateTexture(nil, "ARTWORK"); set.made = set.made + 1 end
                tex:SetTexture(g[1], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR")
                tex:SetTexCoord(0, g[7], g[8], 1)
                tex:SetRotation(g[6])
                tex:SetDrawLayer("ARTWORK", math.min(7, math.floor((i - 1) * 16 / #set.geometry) - 8))
                tex:SetVertexColor(1, 0.95, 0.86)
                tex:SetPoint("TOPLEFT", R.MapArt.Root(), "TOPLEFT", g[2] * W, -g[3] * H)
                tex:SetSize((g[4] - g[2]) * W, (g[5] - g[3]) * H)
                set.used[i] = tex
                set.binds = set.binds + 1
            end
            MP.Show(tex, alpha)
        end
    end
end
MP.Update = R.Perf and R.Perf.Wrap("map.interior.update", Update) or Update

function MP.Snapshot(set)
    if not set then
        local total = { active = 0, pooled = 0, made = 0, binds = 0, pending = 0 }
        for live in pairs(sets) do
            local s = MP.Snapshot(live)
            for k, v in pairs(s) do total[k] = total[k] + v end
        end
        for _ in pairs(pending) do total.pending = total.pending + 1 end
        return total
    end
    local n = 0
    for _ in pairs(set.used) do n = n + 1 end
    return { active = n, pooled = #set.free, made = set.made, binds = set.binds }
end
