-- Interior hot-path contracts using the shipped Undercity numeric picture set.
-- Texture methods are deterministic stand-ins, not GPU/native-client benchmarks.
dofile(TESTS .. "harness.lua")
local function fixture()
    local calls = { alpha = 0, show = 0, bind = 0, point = 0, made = 0 }
    local frames = {}
    local function object()
        local tex = { alpha = 1, shown = true, loaded = true }
        function tex:SetTexture(file) calls.bind = calls.bind + 1; self.file = file; return file ~= 989999 end
        function tex:SetAlpha(a) calls.alpha = calls.alpha + 1; self.alpha = a end
        function tex:GetAlpha() return self.alpha end
        function tex:Show() calls.show = calls.show + 1; self.shown = true end
        function tex:Hide() self.shown = false end
        function tex:IsShown() return self.shown end
        function tex:IsObjectLoaded() return self.loaded end
        function tex:ClearAllPoints() end
        function tex:SetPoint() calls.point = calls.point + 1 end
        function tex:SetScript(event, fn) self[event] = fn end
        function tex:GetFrameLevel() return 10 end
        function tex:SetSize(w, h) self.w, self.h = w, h end
        function tex:CreateTexture() calls.made = calls.made + 1; return object() end
        for _, method in ipairs({ "SetTexCoord", "SetRotation", "SetDrawLayer", "SetVertexColor" }) do
            tex[method] = function() end
        end
        return tex
    end
    local env = setmetatable({ TwichUI = {} }, { __index = _G })
    env.CreateFrame = function() local f = object(); frames[#frames + 1] = f; return f end
    local R = env.TwichUI
    local size = { 10000, 10000 }
    R.MapWorld = {
        Size = function() return size[1], size[2] end,
        -- Linear continent-yard transform. Real picture placement/culling logic
        -- still runs in Pictures.lua; no assertion about native canvas geometry.
        YardsRect = function(_, x0, y0, x1, y1)
            return y0 / 10000, x0 / 10000, y1 / 10000, x1 / 10000
        end,
    }
    R.MapArt = { Root = function() return frames end }
    local function load(name, override)
        local f = assert(loadfile(override or ROOT .. "map/" .. name .. ".lua")); setfenv(f, env); f()
    end
    load("ViewMath"); load("LocalData"); load("Pictures", os.getenv("TWICHUI_PICTURES_SOURCE"))
    return R.MapPictures, R.MapExploreLocalData.cities[1458], object(), calls, frames, size
end

local function visible(set)
    local n = 0
    for _ in pairs(set.used) do n = n + 1 end
    return n
end

local function benchmark(label, count, setup, work)
    local MP, record, parent, calls = fixture()
    local set = MP.Create(parent); MP.Set(set, record)
    setup(MP, set)
    collectgarbage("collect"); collectgarbage("stop")
    local heap, start = collectgarbage("count"), os.clock()
    local binds, alphas, shows = calls.bind, calls.alpha, calls.show
    for i = 1, count do work(MP, set, i) end
    local elapsed, growth = (os.clock() - start) * 1000, collectgarbage("count") - heap
    collectgarbage("restart"); collectgarbage("collect")
    print(("PICTURES BENCH %s: %d updates, %d active, %.3f ms CPU, %.3f KB GC-stopped heap growth, %d bind/%d alpha/%d show calls"):format(
        label, count, visible(set), elapsed, growth, calls.bind - binds, calls.alpha - alphas, calls.show - shows))
end

if os.getenv("TWICHUI_PICTURES_BENCH") then
    local function warm(MP, set) MP.Update(set, -1, -1, 1, 1, 1) end
    benchmark("unchanged", 1000, warm, function(MP, set) MP.Update(set, -1, -1, 1, 1, 1) end)
    benchmark("alpha-only", 1000, warm, function(MP, set, i) MP.Update(set, -1, -1, 1, 1, .7 + (i % 30) / 100) end)
    benchmark("pan", 1000, warm, function(MP, set, i) MP.Update(set, -1 + i / 100000, -1, 1 + i / 100000, 1, 1) end)
    benchmark("close-reopen", 100, warm, function(MP, set) MP.Clear(set); MP.Update(set, -1, -1, 1, 1, 1) end)
    if os.getenv("TWICHUI_PICTURES_SOURCE") then return end -- The saved baseline only runs comparative measurements.
end

local MP, record, parent, calls, frames = fixture()
local set = MP.Create(parent); MP.Set(set, record)
MP.Update(set, -1, -1, 1, 1, 1)
assert(visible(set) == 217 and set.made == 217, "shipped Undercity set fits the 256-picture budget")
local binds, alphas, shows = calls.bind, calls.alpha, calls.show
for _ = 1, 80 do MP.Update(set, -1, -1, 1, 1, 1) end
assert(calls.bind == binds, "stable views never rebind artwork")
assert(calls.alpha == alphas and calls.show == shows, "stable views do not repeat texture alpha/visibility writes")
MP.Update(set, -1, -1, 1, 1, .6)
for _, tex in pairs(set.used) do assert(tex.alpha == .6, "alpha-only updates affect every active picture") end
MP.Update(set, 2, 2, 3, 3, .6)
assert(visible(set) == 0 and #set.free == 217, "panning away releases bindings into the bounded pool")
MP.Update(set, -1, -1, 1, 1, .6)
assert(visible(set) == 217 and set.made == 217, "panning back reuses every pooled texture")
MP.Clear(set); MP.Update(set, -1, -1, 1, 1, .6)
assert(visible(set) == 217 and set.made == 217, "explicit clear invalidates the selection cache")
MP.Update(set, -1, -1, 1, 1, 0)
assert(visible(set) == 0 and set.eligible == 0, "hidden interiors release their textures")
MP.Update(set, -1, -1, 1, 1, .6)
assert(visible(set) == 217, "hidden-to-visible invalidates cached selection")

-- Async readiness and failures remain independent of the cached view.
local first = next(set.used); local pending = set.used[first]
MP.Clear(set); pending.loaded = false
MP.Update(set, -1, -1, 1, 1, .8)
assert(MP.Snapshot().pending == 1, "unready reused texture enters the bounded loader")
MP.Update(set, -1, -1, 1, 1, .4)
pending.loaded = true
assert(frames[1] and frames[1].OnUpdate, "only pending loads install an updater")
frames[1].OnUpdate(frames[1], .2)
assert(pending.alpha == .4 and pending.shown, "readiness fade uses the latest alpha-only update")
assert(MP.Snapshot().pending == 0 and frames[1].OnUpdate == nil, "completed load removes the updater")
MP.Clear(set); pending.loaded = false
MP.Update(set, -1, -1, 1, 1, .4)
frames[1].OnUpdate(frames[1], 10)
assert(MP.Snapshot().pending == 0 and not pending.shown, "timed-out artwork cannot keep an updater alive")
MP.Update(set, -1, -1, 1, 1, .4)
assert(MP.Snapshot().pending == 1, "timeout invalidates the stable-view fast path and preserves retry behavior")
MP.Clear(set)
assert(MP.Snapshot().pending == 0 and frames[1].OnUpdate == nil, "clear cancels pending retries cleanly")
pending.loaded = true

-- A different record, rejected file, and oversubscribed view must not reuse stale selections.
local small = { 0, 0, 0, 1, 1, { 989999, 0, 0, 10, 0, 1, 0, 12345, 0, 0, 10, 0, 1, 0 } }
MP.Set(set, small); MP.Update(set, -1, -1, 1, 1, 1); MP.Update(set, -1, -1, 1, 1, 1)
assert(visible(set) == 1 and set.eligible == 1, "rejected files invalidate cached eligible counts without retry loops")
local many = { 0, 0, 0, 1, 1, {} }
for i = 1, 300 do
    local p = many[6]; for _, value in ipairs({ 50000 + i, 0, 0, 10, 0, 1, 0 }) do p[#p + 1] = value end
end
MP.Set(set, many); MP.Update(set, -1, -1, 1, 1, 1)
assert(visible(set) == 256 and set.made == 256 and set.eligible == 300, "selection caching preserves the 256-texture cap")
print("MAP PICTURE POLISH PASSED: selection, pooling, alpha, async readiness and budget")
