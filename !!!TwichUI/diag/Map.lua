-- TwichUI: troubleshooting report, World map exploration
-- Reads the map parts' snapshots (map/View.lua, Art.lua, Detail.lua, Places.lua, Caves.lua, DungeonView.lua): whether it is on
-- or kept off (and by what), the view's zoom against its limit, how many places, detail tiles and textures are in use,
-- and counts of what was done. Counts and words only: no map names, places or coordinates. Nothing is asked of the game.

local R = TwichUI
local D = R.Diag

local function Snapshot()
    local MV = R.MapView
    if not (MV and MV.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local v = MV.Snapshot()
    local a = R.MapArt and R.MapArt.Snapshot() or {}
    local d = R.MapDetail and R.MapDetail.Snapshot() or {}
    local p = R.MapPlaces and R.MapPlaces.Snapshot() or {}
    local c = R.MapCaves and R.MapCaves.Snapshot() or {}
    local g = R.MapDungeonView and R.MapDungeonView.Snapshot() or {}
    local on = R:Enabled("mapExplore")
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; on the map: %s; stitched map up: %s; kept off by: %s; hooks: %s", on and "on" or "off", D.Flag(v.installed),
        D.Flag(v.active), v.blocker or "nothing", D.Flag(v.hooked))
    if v.zoom then Line("zoom: %.1f of at most %.0f times the whole world; easing: %s; following: %s", v.zoom, v.max, D.Flag(v.animating), D.Flag(v.following)) end
    Line("wheel zooms: %d; glides: %d; map underneath followed: %d times, waited for combat %d; clicks: %d; drags from TwichUI's buttons: %d of %d presses",
        v.wheel or 0, v.glides or 0, v.switches or 0, v.waits or 0, v.clicks or 0, v.dragged or 0, v.pressed or 0)
    Line("way back: %d views; map frames known: %d; resizes kept: %d", v.back or 0, v.frames or 0, v.resized or 0)
    Line("painting: built %s; zones %d (made %d, in view %d, files set %d; loads %d, let go %d); cities %d; textures %d",
        D.Flag(a.built), a.zones or 0, a.zonesBuilt or 0, a.shown or 0, a.loaded or 0, a.loads or 0, a.unloads or 0, a.cities or 0, a.textures or 0)
    Line("terrain detail: showing %s, %d tiles, %d textures made, %d pooled, continents decoded %d, too many to show %d",
        D.Flag(d.showing), d.tiles or 0, d.made or 0, d.pooled or 0, d.continents or 0, d.tooMany or 0)
    Line("places: %d known, %d shown, %d markers made, names shown %d; clicks %d, travel %d, menus %d, shortcuts passed on %d",
        p.places or 0, p.shown or 0, p.pool or 0, p.labels or 0, p.clicks or 0, p.travels or 0, p.menus or 0, p.forwarded or 0)
    Line("caves: %d known; one surfaced: %s; surfaced %d times; floor changes %d; dungeon maps: open %s, opened %d, pins refused %d",
        c.caves or 0, D.Flag(c.surfaced ~= nil), c.times or 0, c.floorChanges or 0, D.Flag(g.open), g.opened or 0, g.refused or 0)
    local status, reason = "ready", nil
    if not on then status = "off"
    elseif v.blocker then status, reason = "unavailable", "openmap-loaded"
    elseif not v.installed then status, reason = "waiting", "map-not-loaded" end
    return {
        configured = on, initialized = v.installed, status = status, reason = reason, lines = lines,
        limits = {
            "Zoom, detail, cave and dungeon maps and places have been checked offline only; docs/map-exploration.md lists the checks in the game.",
            "Your position isn't known on a dungeon's map, nor which floor of a cave you are on.",
        },
    }
end

D.Register("mapExplore", { title = "World map exploration", order = 48, snapshot = Snapshot })
