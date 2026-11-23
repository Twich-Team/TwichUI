-- Production Art.lua regional feather guard/lifecycle contracts on numeric fixtures.
-- These assertions do not certify native image appearance or semantic territory.
local checks = 0
local function Check(value, label) assert(value, label); checks = checks + 1 end
local function Fixture(options)
    local o, R, objects, listeners = options or {}, { PATH = "Interface\\AddOns\\!!!TwichUI\\" }, {}, {}
    local mode = o.mode or "show"
    local function Object(parent, kind, sub)
        local t = { parent = parent, kind = kind, sub = sub or 0, alpha = 1, shown = true, sets = 0, masks = {} }
        objects[#objects + 1] = t
        function t:ClearAllPoints() self.point = nil end
        function t:SetPoint(...) self.point = { ... } end
        function t:SetSize(w, h) self.w, self.h = w, h end
        function t:SetAllPoints(value) self.allPoints = value end
        function t:EnableMouse(value) self.mouse = value end
        function t:SetScale(value) self.scale = value end
        function t:SetFrameLevel(value) self.level = value end
        function t:GetFrameLevel() return self.level or 5 end
        function t:SetTexture(value)
            self.sets = self.sets + 1
            if o.failSoft and type(value) == "string" and value:match("map%-feather%-right%-soft$") then
                self.texture = nil; return false
            end
            self.texture = value; return true
        end
        function t:SetTexCoord(...) self.uv = { ... } end
        function t:AddMaskTexture(value) self.masks[#self.masks + 1] = value end
        function t:SetVertexColor(...) self.color = { ... } end
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
    local canvas = Object(nil, "canvas")
    local rects = { [947] = { 0, 1, 0, 1 }, [1415] = { .1, .9, .1, .9 },
        [1433] = { .2, .6, .2, .6 }, [2548] = { .6, .8, .2, .6 }, [1418] = { .2, .6, .6, .8 } }
    local art = o.artID or 2121
    local file = o.carrier or 7939758
    R.MapExploreData = { reveal = { [art] = "256:256:746:139:" .. file,
        [3548] = "256:256:100:100:9002548", [2418] = "256:256:100:100:9001418" } }
    R.MapExplorePrefs = { Get = function(key) if key == "unexplored" then return mode end end,
        Subscribe = function(fn) listeners[#listeners + 1] = fn end }
    R.MapView = { Canvas = function() return canvas end, Subscribe = function() end,
        FitZoom = function() return 100 end, Ready = function() return true end }
    R.MapWorld = { WORLD = 947, Size = function() return 1002, 668 end,
        Rect = function(id) return unpack(rects[id]) end,
        Art = function(id) return { w = id == 1433 and (o.artW or 1002) or 1002,
            h = id == 1433 and (o.artH or 668) or 668, tw = id == 1433 and (o.tileW or 256) or 256,
            th = id == 1433 and (o.tileH or 256) or 256 } end,
        IsCity = function() return false end,
        Maps = function() return { { id = 1415, kind = 2 }, { id = 1433, kind = 3 },
            { id = 2548, kind = 3 }, { id = 1418, kind = 3 } } end }
    local env = setmetatable({ TwichUI = R,
        GetBuildInfo = function()
            if o.buildError then error("missing build API") end
            return o.version or "1.60.1", o.build or "71037"
        end,
        CreateFrame = function(_, _, parent) return Object(parent, "frame") end,
        C_Map = { GetMapArtID = function(id) return id == 1433 and art or id + 1000 end,
            GetMapArtLayerTextures = function(id) local files = {}; for i = 1, 12 do files[i] = id * 100 + i end; return files end },
        C_MapExplorationInfo = { GetExploredMapTextures = function(id)
            if o.explored and id == 1433 then return { { textureWidth = 256, textureHeight = 256,
                offsetX = 746, offsetY = 139, fileDataIDs = { file } } } end
            return {}
        end } }, { __index = _G })
    for _, name in ipairs({ "map/ViewMath.lua", "map/Art.lua" }) do
        local fn = assert(loadfile((ROOT or "../!!!TwichUI/") .. name)); setfenv(fn, env); fn()
    end
    local A = R.MapArt; assert(A.Build())
    local function View() A.SetView(.1, .1, .85, .85, 8, R.MapView.FitZoom) end
    View()
    return { A = A, objects = objects, View = View,
        Mode = function(value) mode = value; for _, fn in ipairs(listeners) do fn("unexplored") end end }
end
local function Mask(z)
    local mask
    for _, e in ipairs(z.tex) do
        Check(#e.tex.masks == 1, "one preexisting mask slot per native texture")
        Check(mask == nil or mask == e.tex.masks[1], "zone textures share their one mask object")
        mask = e.tex.masks[1]
    end
    return mask
end
local function Suffix(mask, value) return mask and type(mask.texture) == "string" and mask.texture:match(value .. "$") end

local f, old = Fixture(), Fixture({ build = "71038" })
local z, baseline = f.A.Zone(1433), old.A.Zone(1433)
Check(z.edgeFeather == "right-soft" and Suffix(Mask(z), "map%-feather%-right%-soft"), "reviewed source selects its right-edge feather")
Check(type(z.edgeFeatherReason) == "string" and #z.edgeFeatherReason > 0, "selection has explicit source provenance")
Check(#z.tex == #baseline.tex and #f.objects == #old.objects, "feather uses no additional native textures or region objects")
for i, e in ipairs(z.tex) do
    local a, b = e.tex, baseline.tex[i].tex
    Check(a.twFile == b.twFile and a.texture == b.texture and a.alpha == b.alpha and a.shown == b.shown, "native identity/alpha/visibility unchanged")
    Check(a.point[4] == b.point[4] and a.point[5] == b.point[5] and a.w == b.w and a.h == b.h, "source geography and aspect unchanged")
    for j = 1, 4 do Check(a.uv[j] == b.uv[j], "native UV crop unchanged") end
    for j = 1, 3 do Check(a.color[j] == b.color[j], "native color unchanged") end
end
for _, id in ipairs({ 2548, 1418 }) do
    local other = f.A.Zone(id)
    Check(other.edgeFeather == "thin" and Suffix(Mask(other), "map%-feather%-thin"), "neighboring zones retain original feather")
end
local mask, count, binds = Mask(z), #f.objects, {}
for i, e in ipairs(z.tex) do binds[i] = e.tex.sets end
local maskSets = mask.sets
for _ = 1, 30 do f.View() end
Check(#f.objects == count and mask.sets == maskSets, "unchanged views neither allocate nor reset mask")
for i, e in ipairs(z.tex) do Check(e.tex.sets == binds[i], "unchanged views do not rebind native files") end
f.Mode("hide")
Check(z.edgeFeather == "thin" and Suffix(mask, "map%-feather%-thin"), "hide switches to original mask immediately")
for _, e in ipairs(z.tex) do Check(not e.tex.shown, "hidden unexplored tiles remain hidden") end
f.Mode("dim")
Check(z.edgeFeather == "right-soft" and Suffix(mask, "map%-feather%-right%-soft"), "dim restores reviewed feather immediately")
for _, e in ipairs(z.tex) do Check(e.tex.color[1] == .55 and e.tex.color[2] == .55 and e.tex.color[3] == .55, "dim tint preserved") end
f.Mode("show")
Check(z.edgeFeather == "right-soft", "show keeps reviewed feather")
for i, e in ipairs(z.tex) do Check(e.tex.sets == binds[i], "preference switches do not rebind art files") end
f.A.SetShown(false); f.A.SetShown(true); f.View()
Check(#f.objects == count and z.loaded and z.edgeFeather == "right-soft", "close/reopen reuses bounded geometry and mask")
for _, e in ipairs(z.tex) do Check(e.tex.texture == e.tex.twFile and #e.tex.masks == 1, "reopen retains original native identities and one mask") end
local explored = Fixture({ explored = true, mode = "hide" })
Check(explored.A.Zone(1433).edgeFeather == "thin", "hide never exposes parent artwork even on an explored carrier")
explored.Mode("show")
Check(explored.A.Zone(1433).edgeFeather == "right-soft", "explored carrier restores feather outside hide mode")
for _, options in ipairs({ { version = "1.60.2" }, { build = "71038" }, { buildError = true }, { artID = 9999 },
    { artW = 1000 }, { artH = 667 }, { tileW = 128 }, { tileH = 128 }, { carrier = 999999 } }) do
    local bad = Fixture(options); local source = bad.A.Zone(1433)
    Check(source.edgeFeather == "thin" and Suffix(Mask(source), "map%-feather%-thin"), "unreviewed source falls back to original feather")
    Check(source.edgeFeatherReason ~= z.edgeFeatherReason, "fallback cannot claim reviewed selection")
end
local failed = Fixture({ failSoft = true }); local failedZone = failed.A.Zone(1433); local failedMask = Mask(failedZone)
Check(failedZone.edgeFeather == "thin" and Suffix(failedMask, "map%-feather%-thin"), "rejected owned mask restores original artwork")
local attempts = failedMask.sets
failed.Mode("hide"); failed.Mode("show"); failed.Mode("dim")
for _ = 1, 20 do failed.View() end
Check(failedMask.sets == attempts and failedZone.edgeFeather == "thin", "failed mask cannot retry every view or preference change")
Check(#failed.objects == #f.objects, "failure fallback adds no mask/texture objects")
print("MAP REGIONAL FEATHER PASSED: " .. checks .. " assertions")
