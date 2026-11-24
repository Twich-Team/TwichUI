-- Data-only TSV emitted after bounded Python validation. Never evaluates input.
return function(path)
    local client = { maps = {}, minimap = {}, reveal = {}, scenes = {} }
    for line in io.lines(path) do
        local row = {}; for word in (line .. "\t"):gmatch("([^\t]*)\t") do row[#row + 1] = word end
        local kind = row[1]
        if kind == "source" then client.build, client.synthetic = row[2], row[3] == "1"
        elseif kind == "map" then
            local n = {}; for i = 2, 18 do n[i] = assert(tonumber(row[i]), "numeric client map field") end
            local files = {}; for id in row[19]:gmatch("%d+") do files[#files + 1] = tonumber(id) end
            client.maps[n[2]] = { name = "Map " .. n[2], parent = n[3], mapType = n[4], art = n[5],
                cont = n[6] >= 0 and n[6] or nil, xN = n[7], yW = n[8], W = n[9], H = n[10],
                world = { n[11], n[12], n[13], n[14] }, layer = { n[15], n[16], n[17], n[18] }, files = files }
        elseif kind == "mini" then
            local cont = assert(tonumber(row[2]))
            client.minimap[cont] = (client.minimap[cont] or "") .. table.concat(row, ",", 3, 5) .. " "
        elseif kind == "reveal" then
            local art = assert(tonumber(row[2]))
            client.reveal[art] = (client.reveal[art] or "") .. table.concat(row, ":", 3, 6) .. ":" .. row[7] .. " "
        elseif kind == "scene" then
            client.scenes[#client.scenes + 1] = { id = row[2], map = assert(tonumber(row[3])),
                x = assert(tonumber(row[4])), y = assert(tonumber(row[5])), zoom = assert(tonumber(row[6])), label = row[7] }
        else error("Unknown client input row") end
    end
    assert(client.maps[947] and #client.scenes > 0, "client input incomplete")
    return client
end
