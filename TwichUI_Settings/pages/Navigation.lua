-- TwichUI settings: Navigation (nav/). The switch, what navigation shows and when it counts you as arrived or off the
-- route, and (Appearance) the frame, the arrow and the trail. Every value goes through nav/Prefs.lua; nothing here starts,
-- stops or changes a route. The previews are the real frame and arrow showing sample values, labelled "Preview", and a
-- strip on this page drawn by the real trail painter (nav/Paint.lua) along a made-up shape; none is drawn on a map, and
-- none touches the destination you are navigating to. They go when the window closes.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.NavigationPage = P

local W = 644
local STRIP_H = 64

---------------------------------------------------------------------------
-- The trail preview: a strip with a sample shape, drawn the way the maps draw a route
---------------------------------------------------------------------------
local strip, painter, tag
local phase, wait = 0, 0
local SHAPE = { { 0.04, 0.70 }, { 0.22, 0.30 }, { 0.40, 0.55 }, { 0.58, 0.25 }, { 0.78, 0.62 }, { 0.96, 0.35 } }
local xs, ys, ax, ay = {}, {}, {}, {}

local function DrawStrip()
    local NP, NPaint = R.NavPrefs, R.NavPaint
    if not (strip and strip:IsVisible() and NP and NPaint) then return end
    local w, h = strip:GetWidth(), strip:GetHeight()
    for i, p in ipairs(SHAPE) do xs[i], ys[i] = p[1] * w, -p[2] * h end
    local r, g, b = NP.Rgb(NP.Get("trailColor"))
    local a = NP.Get("trailOpacity") / 100
    local width = NP.Get("trailWidth")
    local ants = NP.Get("ants") and not NP.ReducedMotion()
    painter:Begin()
    if NP.Get("trailStyle") == "dots" then
        local n = NPaint.Ants(xs, ys, #SHAPE, 12, ants and phase or 0, 200, ax, ay)
        for i = 1, n do painter:Dot(ax[i], ay[i], width + 3, r, g, b, a) end
    else
        for i = 1, #SHAPE - 1 do painter:Line(xs[i], ys[i], xs[i + 1], ys[i + 1], r, g, b, a, width) end
        if ants then
            local n = NPaint.Ants(xs, ys, #SHAPE, 22, phase, 80, ax, ay)
            for i = 1, n do painter:Dot(ax[i], ay[i], width + 2, math.min(1, r + 0.35), math.min(1, g + 0.35), math.min(1, b + 0.35), math.min(1, a + 0.1)) end
        end
    end
    painter:End()
end

local function OnUpdate(_, elapsed)
    wait = wait + elapsed
    if wait < 1 / 30 then return end
    phase = (phase + wait * R.NavPrefs.Get("antSpeed") * 12) % 10000
    wait = 0
    DrawStrip()
end

-- The strip moves only while it is shown, the ants are on and motion isn't reduced.
local function Animate()
    local NP = R.NavPrefs
    local want = strip and strip:IsVisible() and NP.Get("ants") and not NP.ReducedMotion()
    strip:SetScript("OnUpdate", want and OnUpdate or nil)
    DrawStrip()
end

function P.Strip()
    if strip then return strip end
    strip = CreateFrame("Frame", nil, nil, "BackdropTemplate")   -- Surface draws with a backdrop
    strip:SetSize(W - 8, STRIP_H)
    strip:Hide()
    local G = R.SettingsWidgets
    if G and G.Surface then G.Surface(strip, G.pal.well, 0.9, G.pal.bronzeLo, 0.5) end
    painter = R.NavPaint.New(strip)
    tag = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -6, -4)
    tag:SetText("Preview: a sample shape, not a route")
    tag:SetTextColor(0.62, 0.60, 0.56)
    strip:SetScript("OnShow", Animate)
    strip:SetScript("OnHide", function(f) f:SetScript("OnUpdate", nil) end)
    strip:SetScript("OnSizeChanged", DrawStrip)
    return strip
end

if R.NavPrefs then R.NavPrefs.Subscribe(function() if strip and strip:IsVisible() then Animate() end end) end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function On() return R:Enabled("navigation") end

local UNLOCK_STATUS = {
    off = { "Off" },
    ["no-eui"] = { "EllesmereUI isn't installed or turned on", "You drag the frame and arrow here until it is." },
    ["no-api"] = { "This EllesmereUI has no Unlock Mode", "You drag the frame and arrow here." },
    waiting = { "Waiting for EllesmereUI", "It hasn't finished loading yet." },
    ["register-failed"] = { "EllesmereUI didn't take the movers", "You drag the frame and arrow here." },
    ["module-off"] = { "Ready", "The movers appear in Unlock Mode while navigation is turned on." },
    active = { "In EllesmereUI's Unlock Mode", "Type /unlock and look for \"TwichUI Navigation\"." },
}

local function DataStatus()
    local ND = R.NavData
    local st = ND and ND.LoadState() or "no"
    if st == "loaded" then return "Loaded" end
    if st == "no" then return "Not loaded yet (loads with the first route)" end
    if st == "missing" then return "Missing" end
    if st == "disabled" then return "Turned off in the AddOns list" end
    if st == "format" then return "From another version" end
    return "Could not be loaded"
end

K.Page({
    key = "navigation", icon = "navigation", name = "Navigation", order = 75, group = "map",
    description = "A walking route to a place you choose, with a frame, a direction arrow and the route on your maps.",
    keywords = "navigation navigate route gps directions path walk arrow waypoint trail minimap world map destination travel",
    when = function() return R.Nav ~= nil and R.NavPrefs ~= nil end,
    overview = { label = "Navigation", tip = "Walking routes to a place you choose.", status = function() return K.OnOff(On()) end },
    build = function()
        local NP = R.NavPrefs
        local Header, Toggle, Under, Proxy, Slider = K.Header, K.Toggle, K.Under, K.Proxy, K.Slider
        local BOOL, NUMBER = K.BOOL, K.NUMBER
        local behavior = {}             -- what "Reset navigation settings" puts back (its question counts them)
        local function Check(variable, key, label, tooltip)
            local setting = Proxy(variable, BOOL, label, NP.DEFAULTS[key], function() return NP.Get(key) end,
                function(value) NP.Set(key, value and true or false) end)
            if setting then behavior[#behavior + 1] = { setting = setting, default = NP.DEFAULTS[key] } end
            return K.Checkbox(setting, tooltip)
        end
        local function Number(variable, key, label, tooltip)
            local setting = Proxy(variable, NUMBER, label, NP.DEFAULTS[key], function() return NP.Get(key) end,
                function(value) NP.Set(key, math.floor(value + 0.5)) end)
            if setting then behavior[#behavior + 1] = { setting = setting, default = NP.DEFAULTS[key] } end
            return Slider(setting, NP.LIMITS[key][1], NP.LIMITS[key][2], tooltip)
        end

        Header("Navigation", "Plans a way to a place you choose, on foot or by boat, zeppelin, flight, teleport or Hearthstone, and guides you along it. Off until you turn it on. It never moves your character, turns the camera, casts or clicks anything, and nothing another player sends you starts it.")
        local toggle = Toggle("navigation", "Turn on navigation",
            "Adds Navigate here to your pins' menus (Party pins) and a Navigate tool to the world map's tool bar, and /tui nav. Choosing one plans the way there and shows it.\n\nWalks are planned on maps made from the game's own terrain, buildings and water: they go round mountains, walls and lakes, and through gates and over bridges the maps know. Longer trips, and trips to another continent, are planned in steps with what you have (see Getting there). Lifts, the tram and portals aren't known. The walking maps (about 10 MB) load the first time you plan something, never at login and never in combat.")
        Under(K.Status("Walking maps", DataStatus, nil, "The walking maps are a separate addon, TwichUI_NavData, loaded the first time you plan a route."), toggle, On)

        Header("How to start", "Right-click one of your pins (or a party pin) and choose Navigate here; or press the Navigate button on the world map's tool bar and click the map; or type /tui nav followed by coordinates on your current map (/tui nav 45.2 61.8), /tui nav waypoint for the game's waypoint, or /tui nav stop.")

        Header("What it shows", "Each can be turned off on its own. Turning them all off leaves navigation running with nothing on screen.")
        Under(Check("navigationFrame", "frame", "Show the navigation frame", "The destination's name, the next instruction (from the route's own turns), and the distances: what is left along the route, to its next corner, and in a straight line. Stop and Recalculate are on it."), toggle, On)
        Under(Check("navigationArrow", "arrow", "Show the direction arrow", "Points at the route's next corner, not straight at the destination through what is in between. With no route it points straight at the destination, in grey, and says it is a direct bearing."), toggle, On)
        Under(Check("navigationWorldTrail", "worldTrail", "Draw the route on the world map", "The route from where you are to the destination, on whichever map of its continent you look at. Under the map's pins and labels."), toggle, On)
        Under(Check("navigationMinimapTrail", "minimapTrail", "Draw the route on the minimap", "The part of the route near you. It turns with the minimap when the minimap rotates."), toggle, On)

        Header("Getting there", "What a journey may use. A trip to another continent, or a long one, is planned in steps: walk, boat, zeppelin, flight, a Mage teleport, your Hearthstone. TwichUI never casts, rides or interacts for you: it says what to do and where.")
        Under(Check("navigationShips", "useShips", "Use boats and zeppelins", "Transports between docks, from the game's own data. How long you wait is an average: where a boat is right now isn't known."), toggle, On)
        Under(Check("navigationFlights", "useFlights", "Use flights you have learned", "Only flight points your character has learned (the game says which, with no flight master needed), and only your faction's."), toggle, On)
        Under(Check("navigationTeleports", "useTeleports", "Use Mage teleports", "Only the teleports you know, and only while you carry a Rune of Teleportation. It lands at the city's flight point, give or take some yards. TwichUI never casts it."), toggle, On)
        local hearth = Under(Check("navigationHearth", "useHearth", "Use the Hearthstone", "Only with a Hearthstone in your bags and your bind point known to TwichUI (it learns it when you bind, or when a journey uses the stone). What is left of its cooldown counts as time."), toggle, On)
        K.Note(hearth, function()
            local TV = R.NavTravel
            local why = TV and TV.HearthWhy()
            if why and NP.Get("useHearth") then return why, "warn" end
        end)
        local speedSetting = Proxy("navigationSpeed", K.STRING, "How you travel on the ground", NP.DEFAULTS.speed, function() return NP.Get("speed") end,
            function(value) NP.Set("speed", value) end)
        if speedSetting then behavior[#behavior + 1] = { setting = speedSetting, default = NP.DEFAULTS.speed } end
        Under(K.Dropdown(speedSetting, function() return NP.SPEEDS end,
            "Times in a journey assume this ground speed, and so decide whether a flight or a boat saves you anything. Mounts and buffs aren't read: choose what you usually have."), toggle, On)
        Header("Arriving and leaving the route", "When you count as there, and how far off the route counts as off it. Planning again waits a moment, so a quick step aside doesn't replan.")
        Under(Number("navigationArrival", "arrivalYards", "Arrived within", "How near the destination (in yards, straight line) counts as arrived. Navigation then ends by itself after a moment."), toggle, On)
        Under(Number("navigationOffRoute", "offRouteYards", "Off the route beyond", "How far from the route (in yards) counts as off it. Off it for a few seconds plans a new route from where you are. A teleport or a long jump plans again at once."), toggle, On)
        Under(Check("navigationSound", "arrivalSound", "Play a sound on arrival", "TwichUI's map pin sound, once, on the game's sound effects volume."), toggle, On)
        Under(Check("navigationReducedMotion", "reducedMotion", "Reduced motion", "Keeps the trail still (no moving ants). The arrow still turns and the trail still follows you: those are direction, not decoration."), toggle, On)
        K.ResetButton("Reset navigation settings", behavior, function() NP.Reset("behavior") end,
            "Puts what navigation shows, the arrival and off-route distances, the sound and reduced motion back to their defaults. Its look and the places of the frame and arrow are kept, and a route being followed continues.")
    end,
})

K.Page({
    key = "navigationLook", name = "Navigation appearance", nav = "Appearance", parent = "navigation", order = 76,
    description = "How the navigation frame, the arrow and the route on the maps look. Nothing here changes a route.",
    keywords = "navigation look frame arrow trail line dots ants colour color font size scale lock move position",
    when = function() return R.Nav ~= nil and R.NavPrefs ~= nil end,
    host = function() return P.Strip() end, hostAfter = "The trail", hostHeight = STRIP_H + 8,
    build = function()
        local NP = R.NavPrefs
        local Header, Under, Proxy = K.Header, K.Under, K.Proxy
        local STRING, NUMBER = K.STRING, K.NUMBER
        local toggle = nil              -- the switch is on the General tab; these rows grey out by On2 alone
        local function On2() return On() end
        local reset = {}
        local function Remember(variable, varType, label, key)
            local setting = Proxy(variable, varType, label, NP.DEFAULTS[key], function() return NP.Get(key) end,
                function(value)
                    if varType == NUMBER then value = math.floor(value + 0.5) end
                    NP.Set(key, value)
                end)
            if setting then reset[#reset + 1] = { setting = setting, default = NP.DEFAULTS[key] } end
            return setting
        end
        local function FontChoices(current)
            local Fonts = R.MenuStyle and R.MenuStyle.Fonts
            local first = { { "default", "Game font (default)" } }
            return Fonts and Fonts.Choices(current, first) or first
        end

        Header("Preview", "Shows the navigation frame and arrow beside this window with sample values, labelled Preview. They don't navigate, and a route you are following isn't changed. They go when this window closes.")
        K.Button("Preview", function() return R.NavFrame and R.NavFrame.PreviewShown() and "Hide preview" or "Show preview" end, function()
            local NF = R.NavFrame
            if not NF then return end
            if NF.PreviewShown() then NF.HidePreview() else NF.ShowPreview(R.SettingsAnchor and R.SettingsAnchor()) end
        end, "The real frame and arrow, showing a made-up destination and distances.")

        Header("Frame and arrow", "Where they sit, how big they are, and whether the arrow is part of the frame.")
        Under(K.Checkbox(Remember("navigationLocked", K.BOOL, "Lock the frame and arrow", "locked"),
            "Locked, they let clicks through to the world except the frame's two buttons. Unlock to drag them; their places are kept on this computer. With EllesmereUI's Unlock Mode turned on below, they are moved there instead and this does nothing."), toggle, On2)
        local NU = R.NavUnlock
        if NU then
            local unlockBase = "Move the frame and the arrow in EllesmereUI's Unlock Mode instead of dragging them here. A \"TwichUI Navigation\" and a \"TwichUI Navigation Arrow\" mover appear there, and you drag them, nudge them, type their X and Y or anchor them to other elements the way you do the rest of your interface. Turning this on keeps them where they are. Their places are still saved by TwichUI; EllesmereUI's anchor links are saved by EllesmereUI.\n\nOpen Unlock Mode with /unlock. It can't be opened in combat, and nothing is moved then. The arrow's mover is there while the arrow is on its own, not in the frame.\n\nOff, or without EllesmereUI, you drag them here while unlocked, as before. Your choice is kept while EllesmereUI is away."
            local unlock = K.Checkbox(K.Proxy("navigationUnlockMode", K.BOOL, "Move them in EllesmereUI's Unlock Mode", NP.DEFAULTS.unlockMode,
                function() return NP.Get("unlockMode") end, function(value) NP.Set("unlockMode", value and true or false) end), unlockBase)
            if unlock then
                -- read when the tooltip is shown, so the status is never stale
                local withParent = unlock.GetTooltip
                unlock.GetTooltip = function(self)
                    local code = NU.Status()
                    local text = UNLOCK_STATUS[code] or { code }
                    local color = (code == "active" and R.GREEN) or (code == "off" and R.GREY) or R.GOLD
                    return (withParent(self) or unlockBase) .. "\n\nStatus: " .. color .. text[1] .. "|r" .. (text[2] and ("\n" .. text[2]) or "")
                end
            end
        end
        Under(K.Checkbox(Remember("navigationArrowAttached", K.BOOL, "Show the arrow in the frame", "arrowAttached"),
            "The arrow sits at the left of the frame instead of on its own. Needs the frame shown."), toggle, On2)
        Under(K.Slider(Remember("navigationFrameScale", NUMBER, "Frame size", "frameScale"), NP.LIMITS.frameScale[1], NP.LIMITS.frameScale[2],
            "The frame's scale, in percent."), toggle, On2)
        Under(K.Slider(Remember("navigationArrowScale", NUMBER, "Arrow size", "arrowScale"), NP.LIMITS.arrowScale[1], NP.LIMITS.arrowScale[2],
            "The arrow's scale on its own, in percent. In the frame it follows the frame's size."), toggle, On2)
        Under(K.Swatch(Remember("navigationArrowColor", STRING, "Arrow color", "arrowColor"),
            "The arrow's color while it follows a route, over the same picture RestedXP's guide skin uses for its arrow (white is the picture as drawn). A direct bearing is always grey, so the two are never confused."), toggle, On2)
        K.Button("Put the frame and arrow back", "Put back", function()
            R.Interact.Confirm("TWICHUI_NAV_PLACE", "Put the navigation frame and arrow back in their default places?\n\nOnly their places change.", function() NP.Reset("position") end, { accept = "Put back" })
        end, "Moves the frame and the arrow back to their default places at the top of the screen. Asks first.").reset = true

        Header("Text", "The frame's font, size and colors.")
        Under(K.Dropdown(Remember("navigationFont", STRING, "Font", "font"), function() return FontChoices(NP.Get("font")) end,
            "A font that has gone (its media pack isn't loaded) is drawn as the game's own and stays chosen."), toggle, On2)
        Under(K.Slider(Remember("navigationTextSize", NUMBER, "Text size", "textSize"), NP.LIMITS.textSize[1], NP.LIMITS.textSize[2],
            "The instruction and destination are a point larger, the distances a point smaller."), toggle, On2)
        Under(K.Swatch(Remember("navigationTitleColor", STRING, "Destination color", "titleColor"), "The destination's name."), toggle, On2)
        Under(K.Swatch(Remember("navigationTextColor", STRING, "Text color", "textColor"), "The instruction; the distances and notes are a little dimmer."), toggle, On2)
        Under(K.Swatch(Remember("navigationAccent", STRING, "Accent color", "accentColor"), "The rule across the frame's top and the buttons under the pointer."), toggle, On2)

        Header("The trail", "How the route is drawn on the world map and the minimap. The strip below draws a sample shape the same way; it is not a route.")
        Under(K.Dropdown(Remember("navigationTrailStyle", STRING, "Style", "trailStyle"), function() return NP.TRAIL_STYLES end,
            "A line, or a row of dots."), toggle, On2)
        Under(K.Swatch(Remember("navigationTrailColor", STRING, "Trail color", "trailColor"), "The route's color on both maps."), toggle, On2)
        Under(K.Slider(Remember("navigationTrailOpacity", NUMBER, "Trail opacity", "trailOpacity"), NP.LIMITS.trailOpacity[1], NP.LIMITS.trailOpacity[2],
            "In percent. A route being replaced is drawn fainter."), toggle, On2)
        Under(K.Slider(Remember("navigationTrailWidth", NUMBER, "Trail thickness", "trailWidth"), NP.LIMITS.trailWidth[1], NP.LIMITS.trailWidth[2],
            "In screen pixels, at every zoom."), toggle, On2)
        Under(K.Checkbox(Remember("navigationAnts", K.BOOL, "Moving ants", "ants"),
            "Small lighter dots move along the route toward the destination. Off with reduced motion."), toggle, On2)
        Under(K.Slider(Remember("navigationAntSpeed", NUMBER, "Ant speed", "antSpeed"), NP.LIMITS.antSpeed[1], NP.LIMITS.antSpeed[2],
            "From slow (1) to brisk (4)."), toggle, On2)

        Header("Frame background and border", "The frame's background and border. It looks complete without EllesmereUI; EllesmereUI's and LibSharedMedia's textures are listed when they are there.")
        local lookReset = K.Appearance(NP.Look, "navigationLook", "frame",
            "Shows the frame beside this window with sample values.", function()
                local NF = R.NavFrame
                if NF then if NF.PreviewShown() then NF.HidePreview() else NF.ShowPreview(R.SettingsAnchor and R.SettingsAnchor()) end end
            end, "Reset the frame's background and border", "Puts the frame's background and border back to the defaults. Nothing else is changed.", toggle, On2)
        K.ResetButton("Reset navigation appearance", reset, function() NP.Reset("appearance") end,
            "Puts the frame's and the arrow's look and size, the text and the trail back to the defaults, with the frame's background and border. Their places, what navigation shows and a route being followed are kept.")
        for _, entry in ipairs(lookReset or {}) do reset[#reset + 1] = entry end
    end,
})
