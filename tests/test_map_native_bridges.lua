-- Production Art.lua contracts for two reviewed native mountain underpaints.
-- Geometry/file IDs are fixture metadata; no artwork pixels are distributed or visually certified here.
local assertions = 0
local function Check(value, reason) assert(value, reason); assertions = assertions + 1 end
local function Near(a, b) return math.abs(a - b) < 1e-8 end
local SOURCE = {
    [1428] = { art = 2149, rect = { .2, .6, .15, .55 }, roi = { 390, 450, 665, 645 },
        files = { 8060547, 8060551, 8060552, 8060553, 8060554, 8060555, 8060556, 8060557, 8060558, 8060548, 8060549, 8060550 },
        carrier = { 377, 285, 320, 288, { 8060647, 8060648, 8060650, 8060651 } },
        crops = { { 8060555, 390, 450, 122, 62, 134/256, 1, 194/256, 1 },
                  { 8060556, 512, 450, 153, 62, 0, 153/256, 194/256, 1 },
                  { 8060548, 390, 512, 122, 133, 134/256, 1, 0, 133/256 },
                  { 8060549, 512, 512, 153, 133, 0, 153/256, 0, 133/256 } } },
    [1429] = { art = 2153, rect = { .4, .8, .45, .85 }, roi = { 800, 150, 990, 430 },
        files = { 8061958, 8061962, 8061963, 8061964, 8061965, 8061966, 8061967, 8061968, 8061969, 8061959, 8061960, 8061961 },
        carrier = { 587, 190, 320, 256, { 8061978, 8061979 } },
        crops = { { 8061964, 800, 150, 190, 106, 32/256, 222/256, 150/256, 1 },
                  { 8061968, 800, 256, 190, 174, 32/256, 222/256, 0, 174/256 } } },
}
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, item in pairs(value) do out[key] = Copy(item) end; return out
end
local function Fixture(options)
    local o, R, objects, traces, specs = options or {}, { PATH = "Interface\\AddOns\\!!!TwichUI\\" }, {}, {}, Copy(SOURCE)
    local target = o.target or 1428
    local changed = specs[target]
    if o.art then changed.art = o.art end
    if o.sourceIndex then changed.files[o.sourceIndex] = o.sourceValue end
    if o.shortFiles then changed.files[12] = nil end
    if o.carrierField then changed.carrier[o.carrierField] = o.carrierValue end
    if o.carrierFile then changed.carrier[5][o.carrierFile] = o.carrierValue end
    local function Object(parent, kind, sub)
        local obj = { parent = parent, kind = kind, sub = sub or 0, alpha = 1, shown = true,
                      sets = 0, colors = 0, points = 0, scripts = {} }; objects[#objects + 1] = obj
        function obj:ClearAllPoints() self.point = nil end
        function obj:SetPoint(...) self.point = { ... }; self.points = self.points + 1 end
        function obj:SetSize(w, h) self.w, self.h = w, h end
        function obj:SetAllPoints(p) self.allPoints = p end
        function obj:EnableMouse(value) self.mouse = value end
        function obj:SetScale(value) self.scale = value end
        function obj:SetFrameLevel(value) self.level = value end
        function obj:GetFrameLevel() return self.level or 5 end
        function obj:SetTexture(value)
            self.sets = self.sets + 1
            if value and (value == o.rejected or o.rejectWide and type(value) == "string" and value:match("map%-feather%-wide$")) then
                self.texture = nil; return false
            end
            self.texture = value; return true
        end
        function obj:SetTexCoord(...) self.uv = { ... } end
        function obj:AddMaskTexture(mask) self.mask = mask end
        function obj:SetVertexColor(...) self.color = { ... }; self.colors = self.colors + 1 end
        function obj:SetAlpha(value) self.alpha = value end
        function obj:GetAlpha() return self.alpha end
        function obj:SetShown(value) self.shown = value and true or false end
        function obj:IsShown() return self.shown end
        function obj:Show() self.shown = true end
        function obj:Hide() self.shown = false end
        function obj:SetScript(key, fn) self.scripts[key] = fn end
        function obj:CreateTexture(_, _, _, sublevel) return Object(self, "texture", sublevel) end
        function obj:CreateMaskTexture() return Object(self, "mask") end
        return obj
    end
    local canvas = Object(nil, "canvas"); canvas.level = 5
    local preferences, explored, listeners = { unexplored = o.mode or "show" }, {}, {}
    if o.explored then explored[1428], explored[1429] = true, true end
    R.MapExplorePrefs = { Get = function(key) return preferences[key] end,
        Subscribe = function(fn) listeners[#listeners + 1] = fn end }
    R.MapView = { Canvas = function() return canvas end, Subscribe = function() end,
        FitZoom = function() return 100 end, Ready = function() return true end }
    R.MapWorld = { WORLD = 947, Size = function() return 1002, 668 end,
        Rect = function(id)
            if specs[id] then return unpack(specs[id].rect) end
            if id == 1415 then return .1, .9, .1, .9 end
            return 0, 1, 0, 1
        end,
        Art = function(id) return { w = id == target and (o.artW or 1002) or 1002,
            h = id == target and (o.artH or 668) or 668, tw = id == target and (o.tileW or 256) or 256,
            th = id == target and (o.tileH or 256) or 256 } end,
        IsCity = function() return false end,
        Maps = function() return { { id = 1415, kind = 2 }, { id = 1428, kind = 3 }, { id = 1429, kind = 3 } } end }
    R.MapExploreData = { reveal = {} }
    for _, spec in pairs(specs) do
        local p = spec.carrier
        R.MapExploreData.reveal[spec.art] = p[3] .. ":" .. p[4] .. ":" .. p[1] .. ":" .. p[2] .. ":" .. table.concat(p[5], ",")
    end
    R.MapTrace = function(...) traces[#traces + 1] = { ... } end
    local mapAPI = {
        GetMapArtID = function(id)
            if o.artError and id == target then error("unavailable art API") end
            return specs[id] and specs[id].art or id + 1000
        end,
        GetMapArtLayerTextures = function(id)
            if id == target and o.sourceError then error("unavailable source API") end
            if specs[id] then return specs[id].files end
            local files = {}; for i = 1, 12 do files[i] = id * 100 + i end; return files
        end,
    }
    if o.noSourceAPI then mapAPI.GetMapArtLayerTextures = nil end
    if o.noArtAPI then mapAPI.GetMapArtID = nil end
    local env = setmetatable({ TwichUI = R, C_Map = mapAPI,
        CreateFrame = function(_, _, p) return Object(p, "frame") end,
        GetBuildInfo = function()
            if o.buildError then error("unavailable build API") end
            return o.version or "1.60.1", o.build or "71037"
        end,
        C_MapExplorationInfo = { GetExploredMapTextures = function(id)
            if explored[id] then
                local p = specs[id].carrier
                return { { textureWidth = p[3], textureHeight = p[4], offsetX = p[1], offsetY = p[2], fileDataIDs = p[5] } }
            end
            return {}
        end } }, { __index = _G })
    if o.noBuildAPI then env.GetBuildInfo = false end
    for _, file in ipairs({ "map/ViewMath.lua", "map/Art.lua" }) do
        local path = file == "map/Art.lua" and o.artSource or nil
        local fn = assert(loadfile(path or (ROOT or "../!!!TwichUI/") .. file)); setfenv(fn, env); fn()
    end
    local A = R.MapArt; assert(A.Build())
    return { A = A, objects = objects, traces = traces, specs = specs,
        View = function(zoom, rect)
            local v = rect or { .3, .35, .82, .75 }
            A.SetView(v[1], v[2], v[3], v[4], zoom or 12, R.MapView.FitZoom)
        end,
        SetMode = function(mode) preferences.unexplored = mode; for _, fn in ipairs(listeners) do fn("unexplored") end end,
        Explore = function(id) explored[id] = true; A.RefreshExplored() end }
end

local f = Fixture(); f.View(1, { 0, 0, 1, 1 })
Check(f.A.Snapshot().regionalBaseTexturesBound == 0, "world overview below zone intro binds no mountain textures")
f.View(12)
Check(f.A.Snapshot().regionalBaseTexturesBound == 6, "both reviewed ROIs use exactly six crops")
for _, id in ipairs({ 1428, 1429 }) do
    local z, spec = f.A.Zone(id), SOURCE[id]
    Check(z.baseReason == "reviewed-native-mountains" and z.nativeBase.loaded, "reviewed numeric source accepted")
    Check(#z.nativeBase.tex == #spec.crops, "crop count bounded to reviewed ROI")
    local mask = z.nativeBase.tex[1].mask
    Check(mask and mask.texture:match("map%-feather%-wide$"), "one existing wide mask per ROI")
    local roi, rect = spec.roi, spec.rect
    local left, top = rect[1] * 1002, rect[3] * 668
    Check(Near(mask.point[4], left + roi[1] * .4) and Near(-mask.point[5], top + roi[2] * .4)
        and Near(mask.w, (roi[3] - roi[1]) * .4) and Near(mask.h, (roi[4] - roi[2]) * .4), "mask follows original world ROI")
    for i, box in ipairs(spec.crops) do
        local tex = z.nativeBase.tex[i]
        Check(tex.texture == box[1] and tex.twFile == box[1] and tex.shown, "only reviewed source files bound")
        Check(tex.mask == mask and tex.sub == -1, "shared feather with underlay draw sublevel")
        for _, overlay in ipairs(z.tex) do
            Check(tex.parent == overlay.tex.parent and tex.sub < overlay.tex.sub, "native base is below every zone overlay")
        end
        Check(Near(tex.point[4], left + box[2] * .4) and Near(-tex.point[5], top + box[3] * .4)
            and Near(tex.w, box[4] * .4) and Near(tex.h, box[5] * .4), "unaltered native world geometry")
        for j = 1, 4 do Check(Near(tex.uv[j], box[j + 5]), "source tile UV crop remains exact") end
    end
end
local made, calls = #f.objects, {}
for _, id in ipairs({ 1428, 1429 }) do
    for _, tex in ipairs(f.A.Zone(id).nativeBase.tex) do calls[tex] = { tex.sets, tex.colors, tex.points } end
end
for _ = 1, 100 do f.View(12) end
Check(#f.objects == made, "steady view allocates no new frames/masks/textures")
for tex, old in pairs(calls) do Check(tex.sets == old[1] and tex.colors == old[2] and tex.points == old[3], "steady view skips bindings/tint/placement work") end
for _, object in ipairs(f.objects) do Check(next(object.scripts) == nil, "no permanent update driver") end
-- Preference and exploration callbacks update without waiting for another pan.
f.SetMode("dim")
for _, id in ipairs({ 1428, 1429 }) do
    for _, tex in ipairs(f.A.Zone(id).nativeBase.tex) do Check(tex.color[1] == .55, "unexplored source follows dim preference immediately") end
end
f.Explore(1428)
for _, tex in ipairs(f.A.Zone(1428).nativeBase.tex) do Check(tex.color[1] == 1, "explored carrier restores full tint immediately") end
for _, tex in ipairs(f.A.Zone(1429).nativeBase.tex) do Check(tex.color[1] == .55, "exploring another zone does not reveal this carrier") end
f.SetMode("hide")
Check(f.A.Snapshot().regionalBaseTexturesBound == 0, "hide conservatively suppresses all cross-piece underpaint even if carrier explored")
for _, id in ipairs({ 1428, 1429 }) do
    for _, tex in ipairs(f.A.Zone(id).nativeBase.tex) do Check(not tex.shown and tex.texture == nil, "hide releases all crops immediately") end
end
f.SetMode("show"); Check(f.A.Snapshot().regionalBaseTexturesBound == 6, "show restores only existing bounded crops")
-- An in-zone camera outside both ROIs must not retain invisible base bindings.
f.View(12, { .25, .2, .3, .25 })
Check(f.A.Zone(1428).shown and f.A.Snapshot().regionalBaseTexturesBound == 0, "outside ROI no binding even while source zone remains visible")
f.View(12)
f.A.SetShown(false)
Check(f.A.Snapshot().regionalBaseTexturesBound == 0, "close releases native source bindings")
local sets = f.A.Zone(1428).nativeBase.tex[1].sets
f.SetMode("dim"); f.Explore(1429)
Check(f.A.Zone(1428).nativeBase.tex[1].sets == sets, "closed-map callbacks cannot rebind")
f.A.SetShown(true); f.View(12)
Check(#f.objects == made and f.A.Snapshot().regionalBaseTexturesBound == 6, "reopen reuses original geometry/masks")
f.View(12, { .01, .01, .05, .05 })
Check(f.A.Snapshot().regionalBaseTexturesBound == 0, "view exit releases both ROIs")
f.View(12)
local diagnostics = f.A.Diagnostic()
Check(diagnostics.regionalBaseTexturesBound == 6, "diagnostics count actual bound crops")
for _, row in ipairs(diagnostics.zoneLayers) do
    Check(row.nativeBaseUnderpaint.status == "reviewed-native-mountains" and row.nativeBaseUnderpaint.loaded,
        "diagnostics report native underpaint provenance")
end

for _, target in ipairs({ 1428, 1429 }) do
    local sourceIndices = target == 1428 and { 6, 7, 10, 11 } or { 4, 8 }
    local badOptions = { { version = "1.60.2" }, { build = "71038" }, { buildError = true }, { noBuildAPI = true },
        { art = 9999 }, { artW = 1000 }, { artH = 669 }, { tileW = 128 }, { tileH = 128 },
        { carrierField = 1, carrierValue = 999 }, { carrierField = 2, carrierValue = 999 },
        { carrierField = 3, carrierValue = 319 }, { carrierField = 4, carrierValue = 255 },
        { carrierFile = 1, carrierValue = 999999 }, { carrierFile = 2, carrierValue = 999999 },
        { shortFiles = true }, { sourceError = true }, { noSourceAPI = true }, { rejectWide = true },
        { artError = true, explored = true }, { noArtAPI = true, explored = true } }
    for _, index in ipairs(sourceIndices) do badOptions[#badOptions + 1] = { sourceIndex = index, sourceValue = 999999 } end
    for optionIndex, option in ipairs(badOptions) do
        option.target = target
        local bad = Fixture(option); bad.View(12); local z = bad.A.Zone(target)
        Check(z and z.built and not z.nativeBase and z.baseReason ~= "reviewed-native-mountains",
            "unreviewed/missing source fails closed before crops: " .. target .. " case " .. optionIndex)
        local reason = (option.version or option.build or option.buildError or option.noBuildAPI) and "unreviewed-client"
            or (option.art or option.artW or option.artH or option.tileW or option.tileH or option.artError or option.noArtAPI) and "unreviewed-art"
            or option.rejectWide and "owned-mask-unavailable" or "source-unavailable"
        Check(z.baseReason == reason, "guard diagnostics distinguish client/art/source/mask failures")
        for _, overlay in ipairs(z.tex) do Check(overlay.tex.texture == overlay.tex.twFile, "original overlay remains available on fallback") end
    end
    -- Rejection within one ROI must release every one of its crops while the
    -- independent reviewed ROI remains usable, with no repeated rejected binds.
    local rejected = Fixture({ rejected = SOURCE[target].crops[1][1] }); rejected.View(12)
    local failed = rejected.A.Zone(target).nativeBase
    Check(failed.failed and not failed.loaded and rejected.A.Zone(target).baseReason == "texture-rejected", "rejected native texture marks this ROI failed")
    for _, tex in ipairs(failed.tex) do Check(tex.texture == nil and not tex.shown, "per-ROI rejection releases all its crops") end
    local other = target == 1428 and 1429 or 1428
    Check(rejected.A.Zone(other).nativeBase.loaded, "independent ROI survives another ROI's rejected texture")
    Check(#rejected.traces == 1 and rejected.traces[1][3] == "regional-base-rejected", "one technical texture failure event")
    local attempts = failed.tex[1].sets
    for _ = 1, 20 do rejected.View(12) end
    Check(failed.tex[1].sets == attempts, "failed source does not retry forever")
end
print("MAP NATIVE BRIDGES PASSED: " .. assertions .. " assertions")
return Fixture
