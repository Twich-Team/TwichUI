# Navigation

**TwichUI settings > Journey > Navigation** (`nav/`; the switch is `modules.navigation`, off by default). Written against
the WoW: Forever UI source (`../wow-ui-source`, branch `forever`). **Nothing here has been run in the game yet.** The
route planning is tested offline on synthetic maps and on the real walking maps (`tests/test_nav_route.lua`), and the
controller, views and settings with mocked frames (`tests/test_nav.lua`, the settings tests). Movement, drawing, the
client's coordinates and how it feels to follow are for the game.

A journey to a place you choose, on this continent or another: walking, boats and zeppelins, flights you have learned, Mage
teleports and your Hearthstone, whichever is quickest by estimate. A compact frame with the next instruction, a direction
arrow, and the walks on the world map and the minimap. It never moves your character, turns the camera, casts, clicks or presses anything, and
nothing another player sends you (a ping, a party pin) ever starts it or changes its destination.

## Starting and stopping

- A pin's menu (your own pins and party pins): **Navigate here** (`pins/Window.lua`, checked through `PN.Can("navigate")`).
- The world map's tool bar: **Navigate** (shown only while navigation is on), then click the map (`pins/MapTools.lua`;
  one-shot like the other tools, no modifier click of its own: Ctrl-click stays the game's waypoint, Shift-click other
  addons').
- `/tui nav 45.2 61.8` (coordinates on your current map), `/tui nav waypoint` (the game's own waypoint), `/tui nav stop`,
  `/tui nav recalc`; `/tui nav` alone says what it is doing. Listed on the settings page, not in `/tui help`.
- The frame's **Stop** and **Recalculate**. Arriving ends navigation after a few seconds.

One destination at a time; a new one replaces the last. Map pings are not offered as destinations. A destination on another
continent, or a long way off, becomes a journey (below).

## Routes

**Data.** `TwichUI_NavData`, a load-on-demand addon of walking maps baked from the client's own terrain, buildings,
doodads and liquids by TwichUI's tool (`tools/navbake/README.md`: provenance, licences, the settings and why, the checked
file facts). It loads the first time a route is planned, never at login and never in combat (navigation says it is
waiting for combat to end). About 9.8 MB of Lua strings for Eastern Kingdoms and Kalimdor; once loaded they stay in memory
until a reload (the game cannot unload an addon). Decoded tiles are kept for the walk (at most 16) and released when
navigation stops.

**Search** (`nav/Route.lua`). The walking map is a set of convex polygons per 533-yard tile. Across tiles the planner uses
A* over the crossings between tiles, with costs worked out by the bake inside each tile; then it finds the polygons inside
each tile between crossings and pulls the line tight with the funnel algorithm, so the route turns only at corners. It runs
three milliseconds a frame, so a long route never stalls the game; a newer request drops the older search.

**What "best" means for a walk.** The lowest-cost route under this model: 2D distance through each polygon times its area's
factor (ground 1, swimming 3, ocean 5), measured between the midpoints of the edges it passes, at the granularity of the
crossings (one per run of tile edge, up to 128 yards). It is not a proof of the shortest or the fastest path: heights,
slopes, mounts, speed and creatures aren't modelled.

**What it knows and doesn't.**

| Supported | Not supported (refused or not offered, never drawn through) |
|---|---|
| Going round mountains, cliffs, walls, buildings and barrier doodads (fences, palisades) | Lifts and elevators (Thunder Bluff's mesas, Freewind Post's plateau), the Deeprun Tram, the Darnassus portal: they aren't in the client's tables (the server places them) |
| Through gates, streets, bridges and tunnels the client's collision has | Instances (no position, no walking map) |
| Swimming across water when going round costs more (3x) | A destination in one of those cut-off places: "No way there" with the reason |
| Stepping or hopping up ledges up to 2 yards | Portals other than the Mage's own teleports, class-specific travel (Druid, Shaman), mounts' flight |
| Stacked floors, chosen by the larger connected area | Small isolated pockets (under 5,000 sq yd): left out; a destination there snaps to ground within 40 yd |
| Eastern Kingdoms, Kalimdor and Zephras Isle | Anything else (other maps): no walking map |

Trees, boulders and lamp posts don't block a route: a player steers round them. The client gives no usable height, so
where floors stack the one in the larger connected area is taken (a city's street over the ground sealed under it), then
ground over water, then the lowest; once you are on a floor it is kept.

## Journeys

`nav/Journey.lua` plans a journey as legs: **walk**, **boat or zeppelin**, **flight**, **teleport**, **Hearthstone**. A trip on
one continent shorter than 700 yards, or with nothing but walking on offer, is just walked; anything else is planned over
the network below, and the plain walk is always one of the candidates.

**The network** (`TwichUI_NavData/Data/Transit.lua`, from the client's TaxiNodes, TaxiPath and TaxiPathNode tables by
`tools/navbake/transit.py`): 68 flight points, 25 docks (boats and zeppelins, including Forever's new ones: Stormwind harbour,
Gadgetzan to Powderfuse Port, the zeppelins to Zephras Isle) in 27 directed ferry legs, 288 flights, six teleport
arrivals. A place on the walking map is joined to it at the bake: its stand point, its walking cost to the crossings of its
tile and to every other place within reach (so planning between places needs no search at all).

**What it uses** (settings, Navigation › Getting there, each can be turned off):

| Mode | When it is offered | Cost in the plan |
|---|---|---|
| Flights | both ends are flight points the character has learned (`C_TaxiMap.GetTaxiNodesForMap`, `isUndiscovered` false; no flight master needed) and your faction's | the path's length at 32 yd/s, plus 12 s to board |
| Boats and zeppelins | both docks allow your faction | the ride (16 yd/s for a boat, 20 for a zeppelin), plus the expected wait (a transport visits a dock once a cycle and stays 60 s: someone arriving at random waits (cycle − stay)² / (2 · cycle) on average), plus 12 s to board |
| Mage teleports | the spell is known and a Rune of Teleportation is in the bags | the cast (10 s) plus a 20 s bias, because it uses a rune; it lands at the city's flight point (Darnassus: the middle of its map region) |
| Hearthstone | in the bags, and the bind point is known to TwichUI | the cast (10 s) plus what is left of the cooldown |

Walking is the weighted yards divided by your ground speed (7 yd/s on foot; the setting offers a mount at +60% and a fast
mount at +100%: mounts aren't read). **Every figure that isn't a distance is an estimate**, and the frame says so: the
client has no speeds, and where a boat is now isn't known. The plan is the cheapest under that model, not a proof of the
fastest way.

**The Hearthstone's bind point.** The game tells an addon only the name of the place (`GetBindLocation`), so TwichUI keeps
where the player stood when `HEARTHSTONE_BOUND` fired (at the innkeeper), per character, in `ui.navTravel` (account-wide,
never in a profile or shared). Without one the Hearthstone is not offered, and Navigation's settings say so.

**Reading a journey.** Steps are shown as "Step 2 of 4"; the note under the instruction says what comes next and the time
left. A walk before a boat ends at "Stormwind dock", before a zeppelin at "Orgrimmar zeppelin tower", before a flight at
"Stormwind flight master". A boat leg says to board it and what to expect ("Wait for it here: about 2 min, then about 3 min
aboard (estimates)"); a flight says to talk to the flight master and choose the destination; a teleport names the spell; the
Hearthstone says to use it. Nothing is ever cast, ridden or clicked for you.

**Following one.** A walk ends when you are within a few yards of its place and the next leg becomes the current one. Aboard
a boat or on a flight path (`UnitOnTaxi`) the state is "riding": nothing to follow, the plan is held. A boat's arrival (you
are within 150 yd of its arrival dock), a landing, a teleport or the Hearthstone (a jump of 120 yd or a new continent), or
walking well away from a dock you were to board, plans again from where you are.

**Known gaps.** The walking maps have no lifts, the tram or the Darnassus portal, so Teldrassil is reached only by boat and
Darnassus (a teleport lands there) is cut off from the rest of Kalimdor; Thunder Bluff's mesas likewise. A destination
inside a cut-off place is refused, and a teleport into one is never chosen for somewhere else. A ship dock's stand point is
the nearest connected land (the shore end of its pier, up to about 90 yards from the boat's stop): the walk ends there and
the last steps onto the pier are yours.

## Following

`nav/Nav.lua`. Where you are: `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition` and `C_Map.GetWorldPosFromMapPos`,
the same path a destination takes, ten times a second while navigating. Before anything is planned it checks the client's
world vectors run in the bake's frame (x north, y west) by moving a point east on your map; a client giving them the
other way round is read the other way round, anything else is refused ("axis").

| State | Shown | Notes |
|---|---|---|
| Loading | Loading walking maps… | Waits for combat to end |
| Calculating | Calculating route… | |
| Navigating | the instruction and distances (a walk), or what to do and expect (a boat, flight, teleport or Hearthstone) | |
| Riding | "Under way" or "In flight" | Aboard a boat or on a flight path; held, and planned again on arrival |
| Recalculating | Recalculating route…; the old route stays drawn, fainter | |
| Position unavailable | Position unavailable | An instance, a loading screen; continues by itself |
| No way there | the reason; a direct bearing when on the destination's continent | Tries again after 5, 10, 20, 30 s, not every update |
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
- Memory, measured offline on the real data (`tools/navbake/memory_probe.lua`, steady sizes after a collection; the game's
  decoders are native, so only the Lua tables are comparable): the data addon's strings are 10 MB and stay as long as the
  game runs (an addon can't be unloaded); a long trip on one continent adds 6 MB (one crossing graph), a trip to another
  continent 14 MB more (two), the tiles a route touches about 0.35 MB each (at most 16 kept). All of it but the strings is let go
  when navigation stops. Two things keep it small: an edge of a crossing graph is one packed number (neighbour, cost and tile),
  and the graph is a 5% spanner of the pairs inside each tile (half the edges; see `tools/navbake/README.md`). A map's
  places and the walks between them are a record of their own, so a journey that merely passes through a map doesn't decode
  its graph. These are not in-game figures. To measure in the game, with only TwichUI loaded: `/run collectgarbage("collect")
  UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("!!!TwichUI"), GetAddOnMemoryUsage("TwichUI_NavData"))` before the first
  route, after it, and after walking a while; `TwichUI_NavData` counts the strings, `!!!TwichUI` the decoded tables. For
  CPU, `/console scriptProfile 1`, reload, then `UpdateAddOnCPUUsage()` and `GetAddOnCPUUsage("!!!TwichUI")` around planning
  a long route and around five minutes of following one; turn profiling off afterwards.

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
14. **Journeys: a boat.** Alliance in Stormwind, navigate to a pin in Darkshore (Auberdine): the frame shows Step 1 of 3, a walk
    to "Stormwind dock" with "Then take the boat to Auberdine" and a time (an estimate). At the dock the step becomes
    "Take the boat to Auberdine" with the wait and ride, and the arrow goes away. Board it: "Under way". At Auberdine the
    walk to the destination appears by itself. Note the real wait and ride; if they are far from the estimates, say so.
15. **Journeys: a zeppelin and a flight.** Horde in Orgrimmar to a pin in Undercity (the zeppelin), and a trip that includes a
    flight between flight points you have learned: the step says who to talk to and where to fly. Take the flight: "In
    flight". Land: a new plan from where you land. A flight point you haven't learned is never used.
16. **Journeys: a teleport and the Hearthstone** (a Mage with a Rune of Teleportation; anyone with a Hearthstone). Navigate
    somewhere far where a teleport or the Hearthstone saves time: the step says "Cast Teleport: ..." or "Use your
    Hearthstone" and nothing is cast for you. Do it: a new plan from where you land. The Hearthstone is offered only once
    your bind point is known (bind again at an innkeeper, or use the stone once during a journey); Navigation's settings say
    when it isn't. With the stone on cooldown the plan counts what is left.
17. **Journeys: leaving the plan.** Walk away from the dock you were to board; stand on the pier by it; swim; fly a different
    flight. A new plan after a few seconds each time, never one every update. Turn the options off one by one (boats, flights,
    teleports, Hearthstone): the plan changes, and with all four off another continent says there is no way.
18. **Cut-off places.** Navigate to Thunder Bluff's mesa top from below, to Darnassus, and to a spot on a lift-only plateau:
    "No way there" with the reason, never a line through the air.
19. **Faction.** An Alliance character is never sent by a Horde zeppelin or flight, and the other way round.
14. **Pins and pings unchanged.** Party pins, map pings and the other map tools work as before; Ctrl-click still sets the
    game's waypoint.
