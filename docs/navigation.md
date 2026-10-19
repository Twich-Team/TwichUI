# Navigation

**TwichUI settings > Journey > Navigation** (`nav/`; the switch is `modules.navigation`, off by default). Written against
the WoW: Forever UI source (`../wow-ui-source`, branch `forever`). **Nothing here has been run in the game yet.** The
route planning is tested offline on synthetic maps and on the real walking maps (`tests/test_nav_route.lua`), and the
controller, views and settings with mocked frames (`tests/test_nav.lua`, the settings tests). Movement, drawing, the
client's coordinates and how it feels to follow are for the game.

A walking route to a place you choose, a compact frame with the next instruction, a direction arrow, and the route on the
world map and the minimap. It never moves your character, turns the camera, casts, clicks or presses anything, and
nothing another player sends you (a ping, a party pin) ever starts it or changes its destination.

## Starting and stopping

- A pin's menu (your own pins and party pins): **Navigate here** (`pins/Window.lua`, checked through `PN.Can("navigate")`).
- The world map's tool bar: **Navigate** (shown only while navigation is on), then click the map (`pins/MapTools.lua`;
  one-shot like the other tools, no modifier click of its own: Ctrl-click stays the game's waypoint, Shift-click other
  addons').
- `/tui nav 45.2 61.8` (coordinates on your current map), `/tui nav waypoint` (the game's own waypoint), `/tui nav stop`,
  `/tui nav recalc`; `/tui nav` alone says what it is doing. Listed on the settings page, not in `/tui help`.
- The frame's **Stop** and **Recalculate**. Arriving ends navigation after a few seconds.

One destination at a time; a new one replaces the last. Map pings are not offered as destinations.

## Routes

**Data.** `TwichUI_NavData`, a load-on-demand addon of walking maps baked from the client's own terrain, buildings,
doodads and liquids by TwichUI's tool (`tools/navbake/README.md`: provenance, licences, the settings and why, the checked
file facts). It loads the first time a route is planned, never at login and never in combat (navigation says it is
waiting for combat to end). About 9.8 MB of Lua strings for Eastern Kingdoms and Kalimdor; once loaded they stay in memory
until a reload (the game cannot unload an addon). Decoded tiles are kept for the walk (at most 24) and released when
navigation stops.

**Search** (`nav/Route.lua`). The walking map is a set of convex polygons per 533-yard tile. Across tiles the planner uses
A* over the crossings between tiles, with costs worked out by the bake inside each tile; then it finds the polygons inside
each tile between crossings and pulls the line tight with the funnel algorithm, so the route turns only at corners. It runs
three milliseconds a frame, so a long route never stalls the game; a newer request drops the older search.

**What "best" means.** The lowest-cost route under this model: 2D distance through each polygon times its area's factor
(ground 1, swimming 3, ocean 5), measured between the midpoints of the edges it passes, at the granularity of the
crossings (one per run of tile edge, up to 128 yards). It is not a proof of the shortest or the fastest path: heights,
slopes, mounts, speed and creatures aren't modelled. There is no travel time.

**What it knows and doesn't.**

| Supported | Not supported (refused or not offered, never drawn through) |
|---|---|
| Going round mountains, cliffs, walls, buildings and barrier doodads (fences, palisades) | Boats, zeppelins, flights, lifts, the tram, portals, teleports |
| Through gates, streets, bridges and tunnels the client's collision has | Instances (no position, no walking map) |
| Swimming across water when going round costs more (3x) | Another continent: "No walking route" with the reason |
| Stepping or hopping up ledges up to 2 yards | Map 2991 (Zephras Isle): not baked yet |
| Stacked floors, chosen by the larger connected area | Small isolated pockets (under 5,000 sq yd): left out; a destination there snaps to ground within 40 yd |

Trees, boulders and lamp posts don't block a route: a player steers round them. The client gives no usable height, so
where floors stack the one in the larger connected area is taken (a city's street over the ground sealed under it), then
ground over water, then the lowest; once you are on a floor it is kept.

## Following

`nav/Nav.lua`. Where you are: `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition` and `C_Map.GetWorldPosFromMapPos`,
the same path a destination takes, ten times a second while navigating. Before anything is planned it checks the client's
world vectors run in the bake's frame (x north, y west) by moving a point east on your map; a client giving them the
other way round is read the other way round, anything else is refused ("axis").

| State | Shown | Notes |
|---|---|---|
| Loading | Loading walking maps… | Waits for combat to end |
| Calculating | Calculating route… | |
| Navigating | the instruction and distances | |
| Recalculating | Recalculating route…; the old route stays drawn, fainter | |
| Position unavailable | Position unavailable | An instance, a loading screen; continues by itself |
| No walking route | the reason; a direct bearing when on the destination's continent | Tries again after 5, 10, 20, 30 s, not every update |
| Arrived | Arrived | Within the arrival distance (default 8 yd), then ends |

Corners are passed in order: when you are within reach of the next one, or past it along the next leg and nearer that leg.
Never because a later corner is near in a straight line. Off the route by more than the chosen distance (default 20 yd)
for 2.5 seconds, and at least 4 seconds after the last plan, plans again from where you are; back within 60% of it clears
the count. A jump of 120 yards (a teleport, a graveyard, a landing) or a new continent plans again at once.

**Instructions** come from the route itself: the turn at the next corner by its angle (continue straight under 25°, bear
under 60°, turn under 120°, turn sharply beyond), "and swim" when the next leg is mostly water, "Destination ahead". No
names, landmarks or times.

**Distances** are labelled: Route (what is left along the route), Next (to its next corner), Straight (the straight line
to the destination). With no route only the straight line is given, and called a direct bearing.

## On screen

- **Frame** (`nav/Frame.lua`): destination, instruction, distances, state, Stop and Recalculate. A MenuStyle look
  (`ui.navigationLook`), so it looks complete without EllesmereUI; a teal rule on the left. Locked, only its two buttons
  take the mouse; unlocked, drag it. Text is set only when it changes; updated on events, never per frame.
- **Arrow** (`nav/Arrow.lua`, `media/textures/nav-arrow.tga`, TwichUI's own): points at the route's next corner, turned
  by the bearing less your facing (`GetPlayerFacing`), at most 30 times a second while shown. A direct bearing is grey and
  labelled "Direct bearing, not a route". With no position, no facing, while calculating or on arrival: a word, no arrow.
  On its own or in the frame.
- **World map** (`nav/MapTrail.lua`): a data provider; the route from where you are to the destination, clipped to the map
  shown and drawn only on its continent, under the map's pins. Thickness stays the same on screen at every zoom.
- **Minimap** (`nav/MinimapTrail.lua`): the part of the route near you, turned with a rotating minimap (as the party pins
  are placed, `pins/Minimap.lua`), clipped to the minimap's circle, or its square when `GetMinimapShape` says so
  (EllesmereUI's square minimap doesn't, so the circle inside it is used: less is shown, never a line past the edge).
- **Trail**: a line or dots; optional ants (small lighter dots moving toward the destination). A direct bearing is never
  drawn on a map.

## Settings and saved data

`ui.navigation` (what is shown, arrival and off-route distances, sound, reduced motion, the frame's and arrow's look and
size, the trail; the frame's and arrow's places as `position` and `arrowPosition`) and `ui.navigationLook`. In the profile;
shared through configuration sharing except the two places ("place"). Nothing else is saved: no destination, route,
progress, search or position history.

Reduced motion (navigation's own setting) keeps the trail still; the arrow still turns and the trail still follows you.
Previews (Appearance tab) are the real frame and arrow showing sample values, labelled Preview, and a strip on the page
drawn by the real trail painter along a made-up shape. None is drawn on a map; none touches a destination you are
following; they go when the settings window closes.

## Work and memory

- Off, or on with no destination: no driver, no ticker, no listener for navigation's events. Nothing is decoded.
- Navigating: one driver frame (`OnUpdate`) does the search steps, reads your position (10 Hz), updates progress (4 Hz) and
  calls the views that are shown (the arrow at 30 Hz, the minimap 10–20 Hz, the world map's ants at 30 Hz only while the map
  is open and ants are on). Lines and dots come from pools capped at 400 and 320 per view; nothing is allocated per frame
  in drawing.
- Searches allocate their working tables per plan (a plan happens at the start, when you leave the route, or after a
  jump).
- Not measured in the game. To measure: with only TwichUI loaded, `/run collectgarbage("collect") UpdateAddOnMemoryUsage()
  print(GetAddOnMemoryUsage("!!!TwichUI"), GetAddOnMemoryUsage("TwichUI_NavData"))` before the first route, after it, and
  after walking a while; for CPU, `/console scriptProfile 1`, reload, then `UpdateAddOnCPUUsage()` and
  `GetAddOnCPUUsage("!!!TwichUI")` around planning a long route and around five minutes of following one; turn profiling
  off afterwards. Expect the first route's load to be noticeable once (about 10 MB of Lua parsed).

## Files

| File | Holds |
|---|---|
| `nav/Prefs.lua` | the saved choices and the frame's look |
| `nav/Data.lua` | loading `TwichUI_NavData`, decoding, the tile cache, locating a point |
| `nav/Route.lua` | planning (no frames) |
| `nav/Nav.lua` | the destination, states, progress, the driver, `/tui nav` |
| `nav/Paint.lua` | drawing lines and dots, clipping, the minimap's projection |
| `nav/Frame.lua`, `nav/Arrow.lua`, `nav/MapTrail.lua`, `nav/MinimapTrail.lua` | the views |
| `TwichUI_Settings/pages/Navigation.lua` | the settings page and its Appearance tab |
| `TwichUI_NavData/` | the walking maps (format in its README) |
| `tools/navbake/` | the bake |

## In-game checklist

Turn on Display Lua Errors. Test alone, then with EllesmereUI.

1. **Off.** Fresh install: no frame, no Navigate button, no Navigate here; `TwichUI_NavData` not loaded
   (`/run print(C_AddOns.IsAddOnLoaded("TwichUI_NavData"))`).
2. **Frame check.** Turn it on; `/tui nav 50 50` in Elwynn. A route is drawn. If "axis" appears, report it: the client's
   coordinates are not as expected and nothing is guessed.
3. **Obstacle detour.** From Kharanos, navigate to Ironforge's gate (a pin there): the route follows the road through the
   pass, not over the mountain; the arrow points along the road. Also Goldshire → Darkshire.
4. **Cross-zone.** Goldshire → Stormwind (Trade District): through the gate and over the bridge, across the zone line.
5. **Deviation.** Walk well off the route: after a few seconds "Recalculating route…", then a new route from where you are;
   a quick step aside does not replan.
6. **Arrival.** Walk to the destination: "Arrived", one sound (if on), then everything goes.
7. **Teleport and death.** Hearth or die and release mid-route: one new plan from where you land; in an instance "Position
   unavailable", and back outside it continues.
8. **No route.** Navigate to Thunder Bluff from Bloodhoof Village (lifts aren't walked) and to the other continent: "No
   walking route" with the reason; the first shows a grey direct-bearing arrow, the second no arrow and nothing on the maps.
9. **Minimap.** Turn rotate minimap on and off, zoom in and out, indoors and out: the trail turns and scales with the minimap
   and never crosses its edge; with EllesmereUI's square minimap it stops at the inner circle.
10. **World map.** Pan, zoom, change maps (zone, continent, another continent, a dungeon): drawn only on the route's
    continent, never past the map's edge, the same thickness at every zoom, under pins and labels.
11. **Combat.** Navigate in combat (data already loaded): everything keeps working. First route in combat: "waiting for
    combat to end", then it plans.
12. **Settings.** Every control; Preview shows labelled samples and doesn't change a route being followed; Reset buttons
    say what they keep; Lock off lets you drag the frame and arrow, and Put back returns them.
13. **Cleanup.** Stop: frame, arrow and trails go; `/run local d=TwichUI.Nav.Diagnostics() print(d.driver, d.tickers,
    d.data.decodedTiles)` prints `false 0 0`.
14. **Pins and pings unchanged.** Party pins, map pings and the other map tools work as before; Ctrl-click still sets the
    game's waypoint.
