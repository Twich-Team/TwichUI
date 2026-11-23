-- Production Art.lua safety/lifecycle contracts for a reviewed native city ROI.
-- Numeric fixture only: tests do not certify the appearance of Blizzard artwork.
local count = 0
local function Check(value, message) assert(value, message); count = count + 1 end
local function Near(a, b) return math.abs(a - b) < 1e-8 end
local BASE = { 7958250, 7958254, 7958255, 7958256, 7958257, 7958258, 7958259, 7958260, 7958261, 7958251, 7958252, 7958253 }
local function Copy(values) local out = {}; for i, value in ipairs(values) do out[i] = value end; return out end
local function Fixture(options)
    local o, R, objects, traces = options or {}, { PATH = "Interface\\AddOns\\!!!TwichUI\\" }, {}, {}
    local function Object(parent, kind, sub)
        local t = { parent = parent, kind = kind, sub = sub or 0, shown = true, alpha = 1, sets = 0, colorSets = 0, binds = {} }
        objects[#objects + 1] = t
        function t:ClearAllPoints() self.point = nil end
        function t:SetPoint(...) self.point = { ... } end
        function t:SetSize(w, h) self.w, self.h = w, h end
        function t:SetAllPoints(p) self.allPoints = p end
        function t:EnableMouse(value) self.mouse = value end
        function t:SetScale(value) self.scale = value end
        function t:SetFrameLevel(value) self.level = value end
        function t:GetFrameLevel() return self.level or 5 end
        function t:SetTexture(value)
            self.sets = self.sets + 1; self.binds[#self.binds + 1] = value or false
            if value and value == o.rejected then self.texture = nil; return false end
            self.texture = value; return true
        end
        function t:SetTexCoord(...) self.uv = { ... } end
        function t:AddMaskTexture(mask) self.mask = mask end
        function t:SetVertexColor(...) self.color = { ... }; self.colorSets = self.colorSets + 1 end
        function t:SetAlpha(value) self.alpha = value end
        function t:GetAlpha() return self.alpha end
        function t:SetShown(value) self.shown = value and true or false end
        function t:IsShown() return self.shown end
        function t:Show() self.shown = true end
        function t:Hide() self.shown = false end
        function t:CreateTexture(_, _, _, sublevel) return Object(self, "texture", sublevel) end
        function t:CreateMaskTexture() return Object(self, "mask") end
        return t
    end
    local canvas = Object(nil, "canvas"); canvas.level = 5
    local rects = { [947] = { 0, 1, 0, 1 }, [1415] = { .1, .9, .1, .9 },
                   [1420] = { .2, .8, .2, .8 }, [1458] = { .45, .55, .45, .55 } }
    local zoneFiles = Copy(BASE)
    if o.sourceIndex then zoneFiles[o.sourceIndex] = o.sourceValue end
    if o.shortSource then zoneFiles[12] = nil end
    local carrier = { x = o.carrierX or 463, y = o.carrierY or 361, w = o.carrierW or 320, h = o.carrierH or 256,
                      files = { o.carrierFirst or 7958244, o.carrierSecond or 7958245 } }
    local mode, explored = o.mode or "show", o.explored or false
    local prefListeners, viewListener = {}, nil
    R.MapExplorePrefs = { Get = function(key)
        if key == "unexplored" then return mode end
        if key == "detail" then return false end
        if key == "detailStrength" then return 70 end
    end, Subscribe = function(fn) prefListeners[#prefListeners + 1] = fn end }
    R.MapView = { Canvas = function() return canvas end, Subscribe = function(fn) viewListener = fn end,
                  FitZoom = function() return 100 end, Ready = function() return true end }
    R.MapWorld = { WORLD = 947, Rect = function(id) return unpack(rects[id]) end,
        Art = function(id) return { w = id == 1420 and (o.artW or 1002) or 1002,
            h = id == 1420 and (o.artH or 668) or 668, tw = id == 1420 and (o.tileW or 256) or 256, th = 256 } end,
        Size = function() return 1002, 668 end, IsCity = function(id) return id == 1458 end,
        Maps = function() return { { id = 1415, kind = 2 }, { id = 1420, kind = 3 }, { id = 1458, kind = 3 } } end }
    local artID = o.artID or 2126
    R.MapExploreData = { reveal = { [artID] = carrier.w .. ":" .. carrier.h .. ":" .. carrier.x .. ":" .. carrier.y
        .. ":" .. carrier.files[1] .. "," .. carrier.files[2] } }
    R.MapTrace = function(...) traces[#traces + 1] = { ... } end
    local env = setmetatable({ TwichUI = R,
        CreateFrame = function(_, _, parent) return Object(parent, "frame") end,
        GetBuildInfo = function()
            if o.buildError then error("missing client build API") end
            return o.version or "1.60.1", o.build or "71037"
        end,
        C_Map = {
            GetMapArtID = function(id) return id == 1420 and artID or id + 1000 end,
            GetMapArtLayerTextures = function(id)
                if id == 1420 then if o.sourceError then error("missing source API") end; return zoneFiles end
                local files = {}; for i = 1, 12 do files[i] = id * 100 + i end; return files
            end },
        C_MapExplorationInfo = { GetExploredMapTextures = function(id)
            if id == 1420 and explored then return { { textureWidth = carrier.w, textureHeight = carrier.h,
                offsetX = carrier.x, offsetY = carrier.y, fileDataIDs = carrier.files } } end
            return {}
        end } }, { __index = _G })
    for _, file in ipairs({ "map/ViewMath.lua", "map/Art.lua" }) do
        local fn = assert(loadfile((ROOT or "../!!!TwichUI/") .. file)); setfenv(fn, env); fn()
    end
    local A = R.MapArt; assert(A.Build())
    return { A = A, R = R, objects = objects, traces = traces, carrier = carrier,
        View = function(zoom, away) A.SetView(away and .01 or .4, away and .01 or .4, away and .05 or .6,
                                            away and .05 or .6, zoom or 40, R.MapView.FitZoom) end,
        SetMode = function(value) mode = value; for _, fn in ipairs(prefListeners) do fn("unexplored") end end,
        Explore = function(value) explored = value; A.RefreshExplored() end }
end

-- Hidden plans bind no city artwork at first construction or low zoom.
local f = Fixture(); local A, c = f.A, f.A.City(1458)
Check(#c.tex == 12 and not c.loaded and not c.cover, "city geometry lazy at first opening")
for _, tex in ipairs(c.tex) do Check(tex.texture == nil and tex.sets == 0, "hidden city file never bound") end
f.View(10)
Check(not c.loaded and A.Snapshot().cityTexturesBound == 0, "far-zoom city files remain unbound")
f.View(30)
Check(c.loaded and #c.cover.tex == 4 and c.cover.loaded, "visible city uses four bounded native ROI crops")
Check(c.coverReason == "native-base-roi" and A.Snapshot().cityCoverTexturesBound == 4, "bounded cover provenance/count")
Check(Near(c.frame:GetAlpha(), .5) and Near(c.cover.alpha, .5), "repair follows actual half-visible city")
local expected = {
    { 7958258, 480, 470, 32, 42, 224/256, 1, 214/256, 1 },
    { 7958259, 512, 470, 246, 42, 0, 246/256, 214/256, 1 },
    { 7958251, 480, 512, 32, 46, 224/256, 1, 0, 46/256 },
    { 7958252, 512, 512, 246, 46, 0, 246/256, 0, 46/256 } }
local mask = c.cover.tex[1].mask
Check(mask and mask.texture:match("map%-feather%-wide$"), "uses existing owned wide mask")
Check(Near(mask.point[4], .2 * 1002 + 480 * .6) and Near(-mask.point[5], .2 * 668 + 470 * .6)
    and Near(mask.w, 278 * .6) and Near(mask.h, 88 * .6), "single mask covers exact source ROI")
for i, box in ipairs(expected) do
    local tex = c.cover.tex[i]
    Check(tex.texture == box[1] and tex.twFile == box[1], "reviewed source base tile retained")
    Check(tex.parent == mask.parent and tex.sub == 2 and tex.parent:GetFrameLevel() < c.frame:GetFrameLevel(),
        "repair above explored zone pieces and below city plan")
    Check(tex.mask == mask and tex.shown, "all crops share same visible ROI mask")
    Check(Near(tex.point[4], .2 * 1002 + box[2] * .6) and Near(-tex.point[5], .2 * 668 + box[3] * .6)
        and Near(tex.w, box[4] * .6) and Near(tex.h, box[5] * .6), "crop geometry aligns to original art, without stretch")
    for j = 1, 4 do Check(Near(tex.uv[j], box[5 + j]), "crop UV remains inside native source tile") end
end
-- Regular zoom/pan changes opacity but never rebuild/rebind already loaded art.
local made, binds, colorSets, cityBinds = #f.objects, {}, {}, {}
for i, tex in ipairs(c.cover.tex) do binds[i], colorSets[i] = tex.sets, tex.colorSets end
for i, tex in ipairs(c.tex) do cityBinds[i] = tex.sets end
for _ = 1, 30 do f.View(30) end
Check(#f.objects == made, "repeated unchanged views reuse all cover objects")
for i, tex in ipairs(c.cover.tex) do Check(tex.sets == binds[i] and tex.colorSets == colorSets[i], "unchanged alpha/tint skips setters and rebinds") end
for i, tex in ipairs(c.tex) do Check(tex.sets == cityBinds[i], "unchanged visible city does not rebind its twelve files") end
local previous = 0
for i = 1, 100 do
    f.View(20 + i * .2)
    Check(c.cover.alpha >= previous and c.cover.alpha - previous < .02, "continuous city intro strength")
    local cityAlpha = c.frame:GetAlpha()
    Check(c.cover.alpha <= cityAlpha + 1e-8 and (cityAlpha <= .01 or Near(c.cover.alpha, cityAlpha)),
        "repair never leads city opacity; invisible threshold releases files")
    previous = c.cover.alpha
end
Check(previous == 1 and A.Snapshot().cityTexturesBound == 12, "city fully visible without exceeding tile budget")
-- Unexplored mode follows carrier state, and exploring restores visibility.
f.SetMode("dim")
for _, tex in ipairs(c.cover.tex) do Check(tex.color[1] == .55 and tex.color[2] == .55 and tex.color[3] == .55, "unexplored repair uses same dim tint as carrier") end
f.SetMode("hide")
Check(not c.cover.loaded and c.cover.alpha == 0 and A.Snapshot().cityCoverTexturesBound == 0, "unexplored hide releases repair pixels")
for _, tex in ipairs(c.cover.tex) do Check(not tex.shown and tex.texture == nil, "hidden unexplored patch cannot reveal base art") end
f.Explore(true)
Check(c.cover.loaded and c.cover.alpha == 1, "explored carrier restores repair even in hide mode")
for _, tex in ipairs(c.cover.tex) do Check(tex.color[1] == 1, "explored patch not dimmed") end
-- Release on view exit/close, restore by binding only the existing bounded set.
f.View(40, true)
Check(not c.loaded and not c.cover.loaded and A.Snapshot().cityTexturesBound == 0, "view exit releases city and cover files")
f.View(40); A.SetShown(false)
Check(not c.loaded and not c.cover.loaded and A.Snapshot().cityCoverTexturesBound == 0, "close releases both file sets")
for _, tex in ipairs(c.tex) do Check(tex.texture == nil, "close clears every city texture") end
for _, tex in ipairs(c.cover.tex) do Check(tex.texture == nil and not tex.shown, "close clears every repair texture") end
local retained = #f.objects
local closedBinds = c.cover.tex[1].sets
f.SetMode("show"); f.Explore(true)
Check(c.cover.tex[1].sets == closedBinds and not c.cover.loaded, "closed-map preference/exploration events cannot rebind repair files")
A.SetShown(true); f.View(40)
Check(#f.objects == retained and c.loaded and c.cover.loaded, "reopen reuses geometry and rebinds safely")
local revealed = Fixture({ explored = true }); revealed.View(40)
local repaired, zone = revealed.A.City(1458).cover, revealed.A.Zone(1420)
for _, source in ipairs(zone.tex) do
    Check(source.tex.sub == 1 and repaired.tex[1].sub > source.tex.sub and repaired.tex[1].parent == source.tex.parent,
        "repair above already explored carrier in same native artwork frame")
end

-- Fail closed before adding textures when source identity/layout differs.
for _, option in ipairs({ { version = "1.60.2" }, { build = "71038" }, { buildError = true }, { artID = 9999 },
    { artW = 1000 }, { tileW = 128 }, { carrierFirst = 999999 }, { carrierSecond = 999999 },
    { carrierX = 464 }, { carrierW = 319 }, { sourceIndex = 6, sourceValue = 999999 },
    { sourceIndex = 7, sourceValue = 0 }, { sourceIndex = 10, sourceValue = 999999 },
    { sourceIndex = 11, sourceValue = 999999 }, { shortSource = true }, { sourceError = true } }) do
    local bad = Fixture(option); bad.View(40); local city = bad.A.City(1458)
    Check(city.cover == nil and city.coverReason ~= "native-base-roi", "unreviewed source rejected before ROI creation")
    Check(city.loaded and #city.tex == 12 and bad.A.Snapshot().cityCoverTexturesBound == 0, "original city/zone fallback survives guard rejection")
end
local bad = Fixture({ rejected = 7958258 }); bad.View(40); local cover = bad.A.City(1458).cover
Check(cover and cover.failed and not cover.loaded and cover.alpha == 0, "native rejected bind releases entire repair")
for _, tex in ipairs(cover.tex) do Check(tex.texture == nil and not tex.shown, "rejected bind leaves no partial crop/holes") end
Check(bad.A.City(1458).coverReason == "texture-rejected" and #bad.traces == 1, "bind failure reports technical evidence once")
local attempted = cover.tex[1].sets
for _ = 1, 20 do bad.View(40) end
Check(cover.tex[1].sets == attempted and bad.A.Snapshot().cityCoverTexturesBound == 0, "failed record cannot repeatedly retry/bind")
Check(bad.A.City(1458).loaded, "native city plan remains available after repair rejection")
print("MAP CITY COVER PASSED: " .. count .. " assertions")
