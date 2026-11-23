-- Fixed regional polish cameras. The referenced native screenshot was not
-- attached: these locate the described Badlands/southern boundaries, not a
-- recovered native view. Production Lua owns all coordinate/layer selection.
return function(t, snapshot)
    t.MXP.Set("maxZoom", 72)
    for _, camera in ipairs({
        { "central-eastern", 1433, .1, .05 },
        { "badlands-boundary", 1418, .08, .75 },
        { "southern-boundary", 1431, .95, .4 },
    }) do
        local u, v = t.MW.ToWorld(camera[2], camera[3], camera[4])
        assert(u and v, "regional camera has validated client geography")
        for _, zoom in ipairs({ 4, 8, 8.1, 12, 24 }) do
            assert(t.MV.GlideTo(u, v, zoom), "regional camera uses production navigation")
            t.Run(.8)
            local scene = snapshot(camera[1] .. "-" .. zoom, camera[1] .. " / zoom " .. zoom)
            scene.metadata.cameraPreset = { mapId = camera[2], x = camera[3], y = camera[4],
                requestedZoom = zoom, nativeReferenceMatched = false }
        end
    end
end
