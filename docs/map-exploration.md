# World map exploration

**TwichUI settings > Map > World map** (`map/`; the switch is `modules.mapExplore`, off by default). Written against
the WoW: Forever UI source (`../wow-ui-source`, branch `forever`) and the Forever client's own map tables. **Nothing here
has been run in the game yet.** The view, the stitching geometry, the map underneath following, input routing and every
part on the map are tested offline on a synthetic world with a scroll container that follows the game's rules
(`tests/test_map_explore.lua`), and the data's shape in `tests/test_map_data.lua`. Drawing, seams between paintings, feel
and taint are for the game.

One seamless world map, in the spirit of OpenMap (`../reference_addons/OpenMap`, MIT code, read for its design; nothing of it
is used or called). Every continent's and zone's painting is stitched onto the world map at its real place, so the mouse
wheel goes from the whole world into any zone, city or cave and back without the map jumping. It only moves the map: it
never moves your character, starts a flight or a ride, casts, or talks to anyone.

## How it works

- **One world.** "World" coordinates are the world map's (uiMap 947) 0..1. Every continent's and zone's rectangle on it
  comes from the game (`C_Map.GetMapRectOnMap(map, 947)`, its own map tables), so every map's 0..1 converts to the world's
  and back with nothing of TwichUI's in between (`map/World.lua`).
- **The painting** (`map/Art.lua`) is the game's own textures, by file ID (`C_Map.GetMapArtLayerTextures`), on one frame on
  the game's canvas: the world's painting; each continent's, faded in as you zoom, its edge feathered wide into the world's;
  each zone's painted pieces, faded in closer (in this client a zone's base art is mostly blank parchment and its painting
  is its explored-area pieces: the explored ones from the game, `C_MapExplorationInfo.GetExploredMapTextures`, the rest
  from Forever's own `WorldMapOverlay` tables in `map/Data.lua`), a thin feather where neighbours meet; and each city's own
  map, round-feathered, faded in close. The feathers are TwichUI's own generated masks (`media/textures/map-feather-*.tga`,
  shapes only, `tools/make_map_place_icons.py`). Unexplored areas: shown, dimmed (default) or hidden, a choice.
- **The map underneath follows.** The game's map stays underneath the painting, with its pins, quest areas and
  coordinates. Once the view has been still for 0.6 s it becomes the map you are looking at: the deepest of world,
  continent, zone or city under the view's middle that you are zoomed in far enough for (90% of its whole-map zoom to enter,
  70% to stay). The view doesn't move when it does. In combat it waits until combat ends.
- **Zoom** is 1 where the whole world fits. The wheel zooms about the point under the pointer (that point stays put on
  every frame), eased over 0.18 s (or at once, "Smooth zoom and moves" off), out to the whole world and in to "Deepest
  zoom" (default 48 times; 1.5 times that over a city; over a cave as far as its map needs).
- **Panning** is the game's own drag, anywhere on the world whatever map is underneath.
- **Clicks:** a plain click goes into the next map down under the pointer (framed); a right-click goes out to the map
  above, then the world. The map's other click handlers (TwichUI's pins, pings, map tools, the game's waypoint) come first.
- **Back** returns to the view before a jump (a travel link, a cave, "World"), at most 12, this session only.

**How it touches the game's map** (as OpenMap does; approved): a data provider; hooks on the scroll container's wheel and
press and on its zoom-level set-up (`baseScale` lowered so it pans at every zoom); its `CalculateScrollExtentsAtScale`
replaced while installed (the original put back when off); its wheel zoom mode set to none while the stitched map shows;
its own `InstantPanAndZoom` to place the view; `SetMapID` to follow the view, never in combat. Writing those values from an
addon taints them, as any zoom addon's do; whether that matters anywhere in combat is for the game to show. Maps that
aren't part of the world (battlegrounds, Zephras Isle, which the world map doesn't place) are the game's own, with its own
zoom. Off, everything is put back and the map is shown whole.

## TwichUI's pins, pings and navigation

- A click lands on the map drawn under the pointer, not the map underneath clamped to its edge (`PinsMap.ClickPlace`, used
  by pin placement, pings and the Navigate tool): a pin placed just past the zone underneath is placed on its neighbour.
- Pins and pings of any stitched map are drawn on the map underneath through the world (`PinsMap.Position`), so a
  neighbouring zone's pins show before the map underneath switches.
- A drag that starts on a pin or a place pans the map and isn't a click on it.
- The navigation trail is drawn on the map underneath, over the painting (its frame was raised above the map's
  explored-area art for this).

## Terrain detail, caves, dungeons, places

- **Terrain detail** (`map/Detail.lua`): the client's minimap pictures of each terrain tile (Forever's own WDTs), in their
  real places, faded in from zoom 24 to 36 up to "Detail strength" (70%). At most 80 tiles have textures; not over
  Ironforge or the Undercity (their minimap is the ground above them), nor under a surfaced cave.
- **Caves** (`map/Caves.lua`): zoom onto a cave and its own map surfaces where it is, the land round it dimming; zoom out
  and it sinks. One at a time (the one under the view's middle). A bar names it, with its floors (remembered this session)
  and Leave. Your arrow is the game's own on the zone underneath; which floor you are on isn't known.
- **Dungeon maps** (`map/DungeonView.lua`): a dungeon is a world of its own, so its map opens on a panel over the map (its
  own wheel zoom, dragging, floors), from its entrance's marker or the "Inside" button while you are in it. No position;
  pins and pings refused there with a notice.
- **Places** (`map/Places.lua`): round markers (dungeon, raid, cave, boat, zeppelin), from a continent's worth of zoom
  (caves from closer), names when closer still and never overlapping. They hang from anchors in the painting, so they
  follow every zoom and pan with nothing done per frame. Left-click: a dungeon's map; a cave: glide onto it (it surfaces);
  a dock: the view glides to the other end of the ride (two ends: the choice; Zephras Isle: its own map). Right-click: those,
  Pin this place (named, never twice), Navigate here. Alt, Shift, Ctrl clicks: the map's shortcuts at the place. Whether you
  can board isn't checked or implied.

## Data and provenance (`map/Data.lua`, `tools/mapdata/build.py`)

Made offline from the game clients installed on this computer, with `tools/navbake`'s CASC and DB2 readers. Numbers and
names only: texture file IDs, world rectangles, places. The game draws its own textures; TwichUI ships no map art. Derived
from Blizzard Entertainment's game data and not covered by TwichUI's MIT licence (as `TwichUI_NavData`).

```
python3 -I tools/mapdata/build.py --wow "/path/to/World of Warcraft" [--report report.json]
```

| Part | From | Verified how |
|---|---|---|
| Zones' explored-area pieces (84 arts, 1,073 pieces) | Forever's own `WorldMapOverlay`, `WorldMapOverlayTile` | Forever's own; every texture present in its client |
| Minimap tiles (736 Eastern Kingdoms, 988 Kalimdor, 72 Zephras Isle) | Forever's own continent WDTs (`MAID`) | Forever's own |
| Caves (29 maps, 25 caves) | Retail's map tables (Forever has no cave maps) | Kept only where the building the map is drawn from is placed identically in Forever and byte-identical in both clients |
| Dungeon maps (13 dungeons, 35 floors) | The same retail tables | The same building check. Forever rebuilt Wailing Caverns, Sunken Temple, Blackrock Mountain's dungeons, Scarlet Monastery, Stratholme, Blackfathom Deeps: left out |
| Dungeon entrances (12) | Retail `Map.db2`'s ghost-return point | Kept only where Forever's buildings at the point match retail's |
| Docks and routes (25 docks, 26 legs) | `tools/navbake/transit.py` (Forever's `TaxiPath` tables) | Forever's own; the same places Navigation uses |

## Settings and saved data

- `modules.mapExplore` (off). Takes effect at once.
- `ui.mapExplore` (profile; shared as the "World map" group): `maxZoom` 16-192 (48), `wheelStep` 10-50% (25), `smooth` (on),
  `controls` (on), `unexplored` show/dim/hide (dim), `detail` (on), `detailStrength` 20-100% (70), `caves`, `dungeons`,
  `travel`, `labels` (on), `iconSize` 70-150% (100), `iconOpacity` 40-100% (100).
- Never saved: the view, the way back, a cave's floor, an open dungeon map.

## Work and memory

Nothing runs while the map is closed or still. An ease runs per frame while it lasts; the parts that follow the view
(which zones show, detail tiles, caves, places' culling and names, the readout) run once a frame at most after it moves;
the map underneath is checked after 0.6 s of stillness, then nothing. The world's and continents' textures (and cities')
are made when the map is first shown; a zone's when it first comes into view close enough, its files set only while it is
in view (at most 16 zones keep theirs). The data is about 70 KB of Lua, kept as strings until needed. Not measured in game.

## OpenMap

While OpenMap is loaded map exploration stays off and the settings say why; nothing of OpenMap's is touched.

## Files

`map/Prefs.lua`, `map/Data.lua` (generated), `map/ViewMath.lua`, `map/World.lua` (geometry), `map/View.lua` (the view,
following, clicks, lifecycle), `map/Art.lua` (the painting), `map/Detail.lua`, `map/Controls.lua`, `map/Caves.lua`,
`map/Places.lua`, `map/DungeonView.lua`, `diag/Map.lua`, `TwichUI_Settings/pages/WorldMap.lua`, `tools/mapdata/build.py`,
`tools/make_map_place_icons.py`, `media/textures/place-*.tga`, `media/textures/map-feather-*.tga`.

## In-game checklist

1. Off: the map is the game's own. On with the map open: the zone you're in, as the game shows it.
2. Wheel out from a zone to the whole world and back in to another zone on the other continent: no jumps, the point under
   the pointer stays put, zones' paintings come in over the continent's, the edges between zones read acceptably.
3. Stop over a zone: after a moment its quest areas and the game's pins appear (the map underneath followed). Not in combat.
4. Drag across a zone's edge into the next; click to go in, right-click to come out.
5. Unexplored areas: dimmed by default; Shown and Hidden.
6. Close in: terrain detail lines up with roads and coasts; deepest zoom; a city (Stormwind) comes in close.
7. Caves: zoom onto Burning Blade Coven (Durotar), Jasperlode Mine (Elwynn), Ban'ethil Barrow Den (two floors): the
   cave's map lines up, your arrow walks through it, floors switch, zooming out sinks it.
8. Places: Ratchet's dock glides to Booty Bay, Back returns; the Thunder Bluff zeppelin to Zephras Isle opens its map;
   Shadowfang Keep's entrance opens its floors; Alt-click on a place makes a pin.
9. Your pins and party pins at every zoom, including a neighbouring zone's before the map underneath switches; Alt-click
   and the map tools place where you click, even past the edge of the map underneath; pings; the navigation trail.
10. Turn it off while zoomed deep into a cave: everything goes, the map is whole and the game's own.
11. `/tui diagnostics`: the World map exploration section reads sensibly, with no names.
