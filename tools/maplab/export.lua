-- Export the actual production renderer's selections and geometry from the shared
-- native-style MapCanvas fixture. No Python-side geography or LOD selection.
return function(t, path)
    local R, c, MV, MW, MA, MXP = t.R, t.c, t.MV, t.MW, t.MA, t.MXP
    if not R.DiagnosticsKit or not R.DiagnosticsKit.Json then
        for _, file in ipairs({ "Base.lua", "Json.lua" }) do
            local f = assert(loadfile(REPO .. "TwichUI_Diagnostics/" .. file)); setfenv(f, c); f()
        end
    end
    local scenes = {}
    local drawRank = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 }
    t.tidy(); t.closeMap()
    if t.CLIENT then R:SetEnabled("mapExplore", true) end
    t.openMap(1429); MXP.Set("smooth", false)
    local function Bounds(obj)
        if obj.allPoints == MA.Root() then return 0, 0, 1, 1 end
        local p = obj.point
        if not p or p[1] ~= "TOPLEFT" or p[2] ~= MA.Root() or not obj.width or not obj.height then return nil end
        local W, H = MW.Size()
        return p[4] / W, -p[5] / H, (p[4] + obj.width) / W, (-p[5] + obj.height) / H
    end
    local function Asset(obj)
        if obj.fill then return { color = obj.fill } end
        if type(obj.tex) == "number" then return { fileId = obj.tex } end
        if type(obj.tex) == "string" then
            local relative = obj.tex:match("Interface\\AddOns\\!!!TwichUI\\(.+)")
            if relative then return { asset = "!!!TwichUI/" .. relative:gsub("\\", "/") .. ".tga" } end
        end
        return nil
    end
    local function Effective(obj)
        local alpha, p, level = 1, obj, obj.parent and obj.parent.level or 0
        while p do
            if not p.shown then return 0, level end
            alpha = alpha * (p.alpha or 1); p = p.parent
        end
        return alpha, level
    end
    local function Snapshot(id, label)
        t.Tick(); t.Tick()
        local u0, v0, u1, v1 = MV.ViewRect()
        local scene = { id = id, label = label, width = t.VIEW.w, height = t.VIEW.h,
            view = { u0 = u0, v0 = v0, u1 = u1, v1 = v1 }, textures = {},
            metadata = { syntheticGeography = not t.CLIENT or t.CLIENT.synthetic, nativeMap = MV.MapID(), view = MV.Diagnostic(true),
                terrain = R.MapDetail.Diagnostic(true), interiors = R.MapPictures.Diagnostic(true), cave = R.MapCaves.Snapshot(),
                limitation = t.CLIENT and "Client-table rectangle API adapter; native area shapes, phases and conditions unavailable."
                    or "Synthetic native API fixture; texture IDs such as 900000 are synthetic, not client artwork identifiers." } }
        local W, H = MW.Size()
        assert(math.abs(scene.width / scene.height - (u1 - u0) * W / ((v1 - v0) * H)) < 1e-6,
            "exported pixels preserve the production viewport aspect")
        for _, obj in ipairs(t.OBJECTS) do
            if obj.kind == "CreateTexture" then
                local l, top, r, bottom = Bounds(obj)
                local alpha, level = Effective(obj)
                local a = Asset(obj)
                if l and alpha > 0.001 and a then
                    a.u0, a.v0, a.u1, a.v1, a.alpha, a.level = l, top, r, bottom, alpha, level
                    a.rotation, a.sublayer = obj.rotation or 0, obj.subLayer or 0
                    a.drawLayer = obj.drawLayer or "ARTWORK"
                    a.order = #scene.textures + 1
                    a.texCoord = obj.coord or { 0, 1, 0, 1 }
                    a.tint, a.filter, a.masks = obj.color or { 1, 1, 1 }, "linear", {}
                    for _, mask in ipairs(obj.masks or {}) do
                        local ml, mt, mr, mb = Bounds(mask)
                        local asset = Asset(mask)
                        if ml and asset then
                            asset.u0, asset.v0, asset.u1, asset.v1 = ml, mt, mr, mb
                            asset.texCoord = mask.coord or { 0, 1, 0, 1 }
                            a.masks[#a.masks + 1] = asset
                        end
                    end
                    scene.textures[#scene.textures + 1] = a
                end
            end
        end
        table.sort(scene.textures, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            if drawRank[a.drawLayer] ~= drawRank[b.drawLayer] then return drawRank[a.drawLayer] < drawRank[b.drawLayer] end
            if a.sublayer ~= b.sublayer then return a.sublayer < b.sublayer end
            return a.order < b.order
        end)
        scenes[#scenes + 1] = scene
    end
    local function At(id, label, u, v, z)
        MV.GlideTo(u, v, z); Snapshot(id, label)
    end
    if t.CLIENT then
        MXP.Set("unexplored", "show")
        for _, s in ipairs(t.CLIENT.scenes) do
            local u, v = MW.ToWorld(s.map, s.x, s.y)
            assert(u and v, "client scenario has production world placement")
            MV.GlideTo(u, v, s.zoom); t.Run(0.8)
            Snapshot(s.id, s.label)
        end
        local result = { schema = 1, provenance = { source = "Production Lua with local Forever table-derived API adapter",
            synthetic = t.CLIENT.synthetic, clientBuild = t.CLIENT.build, nativeApiCaptured = false,
            limitation = "Actual local client input when supplied; rectangle-based context lookup, not native phase/zone shapes." }, scenes = scenes }
        local f = assert(io.open(path, "w")); f:write(R.DiagnosticsKit.Json.Encode(result, 17)); f:close()
        return
    end
    At("world", "Synthetic world overview", 0.5, 0.5, 1)
    local u, v = t.WorldOf(1429, 0.5, 0.5)
    for _, z in ipairs({ 12, 20, 24, 28, 32, 36, 40, 48 }) do
        At("terrain-" .. z, "Synthetic zone / terrain zoom " .. z, u, v, z)
    end
    local bu, bv = t.WorldOf(1429, 0, 0.5)
    At("zone-border", "Synthetic zone border with actual TwichUI feather masks", bu, bv, 30)
    local cu, cv = t.WorldOf(1455, 0.5, 0.5)
    for _, z in ipairs({ 24, 36, 48, 64 }) do At("city-" .. z, "Synthetic city/interior zoom " .. z, cu, cv, z) end
    for _, caveId in ipairs({ "cave:101", "wmo:1" }) do
        local g = R.MapCaves.Get(caveId)
        local x, y = (g.u0 + g.u1) / 2, (g.v0 + g.v1) / 2
        local z = MV.MaxZoomAt(x, y)
        At(caveId:gsub(":", "-"), "Synthetic " .. caveId .. " interior", x, y, z)
        -- Deterministic edge crossing reveals abrupt cave selection transitions.
        for i = 0, 4 do
            At(caveId:gsub(":", "-") .. "-edge-" .. i, "Synthetic cave edge step " .. i,
                g.u1 - (g.u1 - g.u0) * (0.12 - i * 0.04), y, z)
            scenes[#scenes].metadata.sequence = caveId .. "-edge"
            scenes[#scenes].metadata.maxAlphaStep = 0.45
        end
    end
    for _, size in ipairs({ { 420, 900 }, { 1400, 500 } }) do
        t.VIEW.w, t.VIEW.h = size[1], size[2]; t.Providers("OnCanvasSizeChanged"); t.Tick()
        At("viewport-" .. size[1], "Synthetic viewport " .. size[1] .. "x" .. size[2], bu, bv, 30)
    end
    t.VIEW.w, t.VIEW.h = 1000, 666; t.Providers("OnCanvasSizeChanged"); t.Tick()
    At("ocean", "Synthetic ocean / missing detail fallback", 0.5, 0.8, 4)
    local result = { schema = 1, provenance = { source = "production Lua in native-style fixture", synthetic = true,
        texturePixels = "Unavailable client art. Local TwichUI masks are actual owned artwork; numeric fixture textures are placeholders.",
        rotation = "native Texture:SetRotation radians; positive counter-clockwise on screen", baseline = "PR 138 map renderer" }, scenes = scenes }
    local f = assert(io.open(path, "w")); f:write(R.DiagnosticsKit.Json.Encode(result, 17)); f:close()
end
