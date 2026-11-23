-- polish-v1: fixed, versioned cameras for regional appearance work. These are
-- repeatable map fractions, not recovered native screenshots or zone shapes.
-- Production Lua alone converts, clamps, selects layers and places textures.
return function(t, snapshot)
    t.MXP.Set("maxZoom", 72)
    local booty
    for _, s in ipairs(t.CLIENT.scenes) do
        if s.id == "booty-bay-12" then booty = s; break end
    end
    assert(booty, "polish-v1 requires the existing client Booty Bay camera")
    local cameras = {
        { "eastern-overview", 1415, .42, .58 },
        { "kalimdor-overview", 1414, .55, .55 },
        { "central-eastern", 1433, .1, .05 },
        { "southern-boundary", 1431, .95, .4 },
        { "badlands-boundary", 1418, .08, .75 },
        { "elwynn-westfall-duskwood", 1429, .15, .85 },
        { "stranglethorn", 1434, .5, .5 },
        { "booty-bay", booty.map, booty.x, booty.y, "existing-client-camera" },
        { "tirisfal", 1420, .62, .70 },
        { "undercity", 1458, .5, .5 },
    }
    for _, camera in ipairs(cameras) do
        local u, v = t.MW.ToWorld(camera[2], camera[3], camera[4])
        assert(u and v, "polish-v1 camera has validated client geography")
        for _, zoom in ipairs({ 4, 8, 12, 24 }) do
            assert(t.MV.GlideTo(u, v, zoom), "polish-v1 camera uses production navigation")
            t.Run(.8)
            local scene = snapshot(camera[1] .. "-" .. zoom, camera[1] .. " / zoom " .. zoom)
            local actualU, actualV, actualZoom = t.MV.View()
            scene.metadata.cameraPreset = { catalog = "polish-v1", mapId = camera[2], x = camera[3], y = camera[4],
                requestedZoom = zoom, requestedWorldCenter = { u = u, v = v },
                actualZoom = actualZoom, actualWorldCenter = { u = actualU, v = actualV },
                locator = camera[5] or "fixed-map-fraction", nativeReferenceMatched = false }
        end
    end
end
