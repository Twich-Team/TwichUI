-- Versioned cameras for the owner's first native feedback. Geometry, host and
-- artwork selection still come from production Lua, not Python calculations.
-- These are approximations: the quick reports withheld the actual view center.
return function(t, snapshot)
    local R, MV, MW = t.R, t.MV, t.MW
    t.MXP.Set("maxZoom", 72)  -- native quick reports' saved maximum
    local function View(id, label, u, v, zoom, sequence)
        assert(MV.GlideTo(u, v, zoom), "feedback camera has valid production geometry")
        t.Run(0.8)
        local scene = snapshot(id, label, not sequence)
        if sequence then scene.metadata.sequence, scene.metadata.maxAlphaStep = sequence, 0.5 end
    end
    local function Map(id, name, x, y, zooms)
        local u, v = MW.ToWorld(id, x, y)
        assert(u and v, "feedback map is in the supplied client geometry")
        for _, zoom in ipairs(zooms) do View(name .. "-" .. zoom, name .. " / zoom " .. zoom, u, v, zoom) end
    end
    -- Overview camera centers are deliberately fixed map fractions, not a claim
    -- that the screenshots' exact camera/host/phase has been recovered.
    Map(1415, "eastern-overview", .42, .58, { 2.4, 4.1, 6 })
    Map(1414, "kalimdor-overview", .55, .55, { 2.4, 4.1 })
    Map(1429, "elwynn-westfall-duskwood", .15, .85, { 4.1, 12, 24, 48 })
    Map(1420, "tirisfal", .62, .70, { 6, 12 })
    for _, s in ipairs(t.CLIENT.scenes) do
        if s.id == "booty-bay-12" or s.id == "booty-bay-24" or s.id == "booty-bay-48"
            or s.id == "undercity-24" or s.id == "undercity-48" then
            local u, v = MW.ToWorld(s.map, s.x, s.y)
            View(s.id, s.label, u, v, s.zoom)
        end
    end
    -- Keep feedback-v1's 62 cameras fixed. The composition profile adds a fine
    -- city handoff course at the same client-table camera, including deep LOD.
    if os.getenv("TWICHUI_MAPLAB_SCENARIO_SET") == "composition-v1" then
        Map(1458, "undercity-handoff", .5, .5, { 12, 14, 16, 18, 20, 22, 24, 36, 48 })
    end
    for _, item in ipairs({ { "cave:40", "jasperlode" }, { "cave:5", "skull-rock" } }) do
        local g = assert(R.MapCaves.Get(item[1]), "feedback cave is in production numeric data")
        local u, v = (g.u0 + g.u1) / 2, (g.v0 + g.v1) / 2
        for _, zoom in ipairs({ 32, 64, 124 }) do View(item[2] .. "-" .. zoom, item[2] .. " / zoom " .. zoom, u, v, zoom) end
        -- Actual-time frames cover entry as well as the geometric exit below.
        -- Suppress Snapshot's normal settling ticks to retain exact phases.
        R.MapCaves.Sink(); MV.GlideTo(u, v, 124); t.Tick(0)
        for i, seconds in ipairs({ 0, 0.075, 0.15 }) do
            if i > 1 then t.Tick(0.075) end
            local scene = snapshot(item[2] .. "-entry-" .. i, item[2] .. " / entry " .. seconds .. " seconds", false, false)
            scene.metadata.sequence, scene.metadata.maxAlphaStep = item[2] .. "-entry-time", 0.55
            scene.metadata.elapsedSeconds = seconds
        end
        -- Move the center through the old selection edge while holding the
        -- actual chart partly visible. Do not expand zoom beyond its current
        -- location-specific limit: each exported snapshot records actual zoom.
        for i, offset in ipairs({ .40, .48, .52, .65, .8, .9, 1, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.5, 1.7 }) do
            View(item[2] .. "-edge-" .. i, item[2] .. " / center offset " .. offset,
                u + (g.u1 - g.u0) * offset, v, 72, item[2] .. "-viewport-exit")
        end
    end
end
