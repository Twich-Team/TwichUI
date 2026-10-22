-- TwichUI settings: World map (map/). The switch, how the zoom behaves, the terrain detail, and (Places) which places
-- show and how. Every value goes through map/Prefs.lua; the map's own parts follow it. Nothing here opens, moves or
-- changes the world map except "Whole world", which only acts on a map you already have open.

local R = TwichUI
local K = R.SettingsKit

local function On() return R:Enabled("mapExplore") end

local function Status()
    local MV = R.MapView
    if not MV then return "Not loaded" end
    local blocker = MV.Blocker()
    if blocker then return ("Off while %s is loaded"):format(blocker) end
    if not On() then return "Off" end
    if not WorldMapFrame then return "Ready (the map loads when you first open it)" end
    return MV.Installed() and "On" or "Waiting for the map"
end

local function StatusTone()
    local MV = R.MapView
    if MV and MV.Blocker() then return "warn" end
    return On() and "ok" or "quiet"
end

-- What map/Data.lua covers, counted (the Places tab says it).
local function Coverage()
    local D = R.MapExploreData
    if not D then return "No data" end
    local entrances, maps, floors = 0, 0, 0
    for _, d in pairs(D.dungeons or {}) do
        if d.entrance then entrances = entrances + 1 end
        if #(d.floors or {}) > 0 then maps = maps + 1 floors = floors + #d.floors end
    end
    local caves, seen = 0, {}
    for _, c in ipairs(D.caves or {}) do
        local key = c[9] and ("g" .. c[9]) or ("c" .. c[1])
        if not seen[key] then seen[key] = true caves = caves + 1 end
    end
    local docks = 0
    for _ in pairs(D.docks or {}) do docks = docks + 1 end
    return ("%d dungeon entrances, %d dungeon maps (%d floors), %d caves, %d docks"):format(entrances, maps, floors, caves, docks)
end

K.Page({
    key = "worldMap", name = "World map", tab = "Zoom", order = 73, group = "journey",
    description = "One seamless world map: zoom from the whole world into any zone, with terrain detail, caves' and dungeons' maps.",
    keywords = "world map seamless stitched zoom pan drag wheel detail minimap terrain unexplored reveal cave caves interior dungeon dungeons raid map floors explore exploration openmap world back",
    when = function() return R.MapView ~= nil and R.MapExplorePrefs ~= nil end,
    overview = { label = "World map", tip = "One seamless world map, from the whole world to street level.", status = function() return K.OnOff(On()) end },
    build = function()
        local MXP = R.MapExplorePrefs
        local Header, Toggle, Under, Proxy, Slider = K.Header, K.Toggle, K.Under, K.Proxy, K.Slider
        local BOOL, NUMBER = K.BOOL, K.NUMBER
        local all = {}
        local function Check(variable, key, label, tooltip)
            local setting = Proxy(variable, BOOL, label, MXP.DEFAULTS[key], function() return MXP.Get(key) end,
                function(value) MXP.Set(key, value and true or false) end)
            if setting then all[#all + 1] = { setting = setting, default = MXP.DEFAULTS[key] } end
            return K.Checkbox(setting, tooltip)
        end
        local function Number(variable, key, label, tooltip)
            local setting = Proxy(variable, NUMBER, label, MXP.DEFAULTS[key], function() return MXP.Get(key) end,
                function(value) MXP.Set(key, math.floor(value + 0.5)) end)
            if setting then all[#all + 1] = { setting = setting, default = MXP.DEFAULTS[key] } end
            return Slider(setting, MXP.LIMITS[key][1], MXP.LIMITS[key][2], tooltip)
        end

        Header("World map", "One seamless world map: every continent's and zone's painting stitched onto the world, so the mouse wheel goes from the whole world into any zone, city or cave and back without the map jumping. Terrain detail up close, caves' maps surfacing as you zoom onto them, dungeons' own maps, and boats and zeppelins that take the map where they go. Off until you turn it on. It only moves the map: it never moves your character, starts a flight or a ride, or casts anything.")
        local toggle = Toggle("mapExplore", "Turn on map exploration",
            "The mouse wheel zooms at the pointer from the whole world down to street level; drag to move anywhere on the world; click to go into a map, right-click to come out. Once you stop, the game's map underneath becomes the one you are looking at, so its quest areas, pins and coordinates match what is on screen (it waits while you are in combat). Your pins, pings and navigation trail stay in place at every zoom. Everything drawn is the game's own art.\n\nOpenMap does the same to the same map in its own way: while it is loaded, this stays off.\n\nOff, the map works exactly as the game's.")
        Under(K.Status("Status", Status, nil, "Whether map exploration is running. It changes the map as soon as it is turned on or off; nothing waits for a reload.", StatusTone), toggle, On)

        Header("Zoom and panning", "The mouse wheel zooms about the point under the pointer; drag to move the map anywhere on the world. A drag never counts as a click, so it never places a pin.")
        Under(Number("mapExploreMaxZoom", "maxZoom", "Deepest zoom",
            "How far in you can go, in times the whole world. A little further over a city, and as far as a cave's own map needs over a cave. Past the paintings' own detail the terrain detail below takes over; with it off, the zoom readout says when a painting is only enlarged."), toggle, On)
        Under(Number("mapExploreWheelStep", "wheelStep", "Zoom per wheel notch",
            "How much one notch of the mouse wheel zooms, in percent."), toggle, On)
        Under(Check("mapExploreSmooth", "smooth", "Smooth zoom and moves",
            "Zooms and jumps ease over a fraction of a second. Off, the view changes at once (for reduced motion)."), toggle, On)
        Under(Check("mapExploreControls", "controls", "Show the zoom buttons on the map",
            "+, -, World and Back at the map's bottom right, with how far in you are. Hover the number to see what the map is showing. Without them the wheel, dragging and clicks still work."), toggle, On)
        local unexplored = Proxy("mapExploreUnexplored", K.STRING, "Unexplored areas", MXP.DEFAULTS.unexplored,
            function() return MXP.Get("unexplored") end, function(value) MXP.Set("unexplored", value) end)
        if unexplored then all[#all + 1] = { setting = unexplored, default = MXP.DEFAULTS.unexplored } end
        Under(K.Dropdown(unexplored, function() return MXP.UNEXPLORED end,
            "The parts of each zone you haven't explored yet, from the game's own map art: shown as explored ones are, dimmed, or hidden as the game's own map hides them (the continent's painting shows there instead)."), toggle, On)
        K.Button("Current view", "Whole world", function()
            local MV = R.MapView
            if MV and not MV.World() then MV.Notice("Open your map with map exploration on first.") end
        end, "Glides your open map out to the whole world. Back returns. Nothing is changed if the map is closed.")

        Header("Detail", "Close in, the paintings run out of pixels.")
        Under(Check("mapExploreDetail", "detail", "Terrain detail up close",
            "Lays the game's own minimap pictures of the ground over the map as you zoom past the paintings' resolution: trees, rocks, roads and buildings. They are the game's textures, drawn by the game; nothing is painted or guessed. On Eastern Kingdoms and Kalimdor, not over Ironforge or the Undercity (their minimap is the ground above them)."), toggle, On)
        Under(Number("mapExploreDetailStrength", "detailStrength", "Detail strength",
            "How strongly the terrain detail shows over the painted map, in percent, once fully zoomed in."), toggle, On)

        K.ResetButton("Reset map exploration settings", all, function() R.MapExplorePrefs.Reset("behavior") R.MapExplorePrefs.Reset("detail") end,
            "Puts the zoom, the buttons and the detail back to their defaults. Places (their own tab), your pins, pings and routes are kept, and the switch stays as it is.")
    end,
})

K.Page({
    key = "worldMapPlaces", name = "World map places", nav = "Places", parent = "worldMap", order = 74,
    description = "Dungeon entrances, caves, and boat and zeppelin docks on the world map, and what clicking them does.",
    keywords = "places dungeon entrance raid cave caves boat zeppelin dock travel transport link icons labels names size opacity",
    when = function() return R.MapView ~= nil and R.MapExplorePrefs ~= nil end,
    build = function()
        local MXP = R.MapExplorePrefs
        local Header, Under, Proxy = K.Header, K.Under, K.Proxy
        local toggle = nil
        local function On2() return On() end
        local reset = {}
        local function Check(variable, key, label, tooltip)
            local setting = Proxy(variable, K.BOOL, label, MXP.DEFAULTS[key], function() return MXP.Get(key) end,
                function(value) MXP.Set(key, value and true or false) end)
            if setting then reset[#reset + 1] = { setting = setting, default = MXP.DEFAULTS[key] } end
            return K.Checkbox(setting, tooltip)
        end
        local function Number(variable, key, label, tooltip)
            local setting = Proxy(variable, K.NUMBER, label, MXP.DEFAULTS[key], function() return MXP.Get(key) end,
                function(value) MXP.Set(key, math.floor(value + 0.5)) end)
            if setting then reset[#reset + 1] = { setting = setting, default = MXP.DEFAULTS[key] } end
            return K.Slider(setting, MXP.LIMITS[key][1], MXP.LIMITS[key][2], tooltip)
        end

        Header("Places", "Small round markers, apart from your pins (diamonds). Left-click does the place's main thing; right-click lists its actions, Pin this place and Navigate here among them. Alt, Shift and Ctrl clicks on a place are the map's shortcuts, as anywhere else.")
        Under(K.Status("What is known", Coverage, nil, "Only places and maps checked against WoW: Forever's own files are listed: a cave's or dungeon's map is shown only where its building is the same in Forever's client, and an entrance only where the buildings round it are."), toggle, On2)
        Under(Check("mapExploreDungeons", "dungeons", "Dungeon and raid entrances",
            "Where a dungeon or raid is entered (where a ghost comes back to). Click for the dungeon's own map, one floor at a time, where one is known. Your position isn't shown on a dungeon's map. Level ranges and entry requirements aren't shown."), toggle, On2)
        Under(Check("mapExploreCaves", "caves", "Caves",
            "Caves and underground places with a map of their own. Zoom in on one (or click its marker) and its map surfaces where the cave is, with its floors, and your arrow stays on it. The marker is at the middle of the cave's map, not at its entrance. Off, caves never surface and their markers are hidden."), toggle, On2)
        Under(Check("mapExploreTravel", "travel", "Boat and zeppelin docks",
            "Where boats and zeppelins leave from, and where they go, from the game's own routes. Click one and the map glides to the other end; Back returns. Whether you can board (faction, a learned route) isn't checked."), toggle, On2)
        Under(Check("mapExploreLabels", "labels", "Names when zoomed in",
            "A place's name under it once you zoom in, never where two names would overlap (dungeons keep theirs first)."), toggle, On2)
        Under(Number("mapExploreIconSize", "iconSize", "Marker size", "In percent. The same size on screen at every zoom."), toggle, On2)
        Under(Number("mapExploreIconOpacity", "iconOpacity", "Marker opacity", "In percent."), toggle, On2)
        K.ResetButton("Reset places", reset, function() R.MapExplorePrefs.Reset("places") end,
            "Puts which places show, their names, size and opacity back to the defaults. Nothing else changes.")
    end,
})
