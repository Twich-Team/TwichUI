# Navigation

**TwichUI settings > Map > Navigation** (`nav/`; the switch is `modules.navigation`, off by default). Written against
the WoW: Forever UI source (`../wow-ui-source`, branch `forever`). **Nothing here has been run in the game yet.** The
route planning is tested offline on synthetic maps and on the real walking maps (`tests/test_nav_route.lua`), and the
controller, views and settings with mocked frames (`tests/test_nav.lua`, the settings tests). Movement, drawing, the
client's coordinates and how it feels to follow are for the game.

A journey to a place you choose, on this continent or another: walking, boats and zeppelins, flights you have learned, Mage
teleports and your Hearthstone, whichever is quickest by estimate. A compact frame with the next instruction, a direction
arrow, and the walks on the world map and the minimap. It never moves your character, turns the camera, casts, clicks or presses anything (the one exception is Take the flight for me, off by default, below), and
nothing another player sends you (a ping, a party pin) ever starts it or changes its destination.

## Starting and stopping

- A pin's menu (your own pins and party pins): **Navigate here** (`pins/Window.lua`, checked through `PN.Can("navigate")`).
- The world map's tool bar: **Navigate** (shown only while navigation is on), then click the map (`pins/MapTools.lua`;
  one-shot like the other tools, no modifier click of its own: Ctrl-click stays the game's waypoint, Shift-click other
  addons').
- `/tui nav 45.2 61.8` (coordinates on your current map), `/tui nav waypoint` (the game's own waypoint), `/tui nav stop`,
  `/tui nav recalc`; `/tui nav` alone says what it is doing. Listed on the settings page, not in `/tui help`.
- The frame's **Stop** and **Recalculate**. Arriving ends navigation after a few seconds.
- **Start when I place a marker** (`ui.navigation.autoStart`, off by default; `nav/Auto.lua`). A marker you place then starts
  navigation to it, in place of any destination: the game's own waypoint (`USER_WAYPOINT_UPDATED`, looked at 0.2 s later so
  one placement counts once) or a pin you place by hand (`Pins.OnPlaced`: the new pin window's Save, a single `/twichway`
  or `/way` pin). Not started by: a pin shared with you, a copy of a pin, a pasted list, an import, the Cozy Sleeping Bag
  guide's pins, or the waypoint the RestedXP step feature places (`QoLGuideWaypoint.OwnsWaypoint`). A waypoint already set
  when this is turned on (or at login) is left alone; only a new or moved one counts. A place navigation can't use is
  ignored without a message. Clicking a pin sets the game's waypoint (Party pins), so with this on that click also starts
  navigation. Counts are in the navigation diagnostics (`auto`).

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
| Going round mountains, cliffs, walls, buildings and barrier doodads (fences, palisades) | Lifts and elevators other than those listed under Journeys (the Deeprun Tram, the Undercity lift), the Darnassus portal: the server places them, so they aren't in the walking maps |
| Through gates, streets, bridges and tunnels the client's collision has | Instances (no position, no walking map) |
| Swimming across water when going round costs more (3x) | A destination in one of those cut-off places: "No way there" with the reason |
| Stepping or hopping up ledges up to 2 yards | Portals other than the Mage's own teleports, class-specific travel (Druid, Shaman), mounts' flight |
| Stacked floors, chosen by the larger connected area | Small isolated pockets (under 5,000 sq yd): left out; a destination there snaps to ground within 40 yd |
| Eastern Kingdoms, Kalimdor and Zephras Isle | Anything else (other maps): no walking map |

Trees, boulders and lamp posts don't block a route: a player steers round them. The client gives no usable height, so
where floors stack the one in the larger connected area is taken (a city's street over the ground sealed under it), then
ground over water, then the lowest; once you are on a floor it is kept.

## Journeys

`nav/Journey.lua` plans a journey as legs: **walk**, **boat or zeppelin**, **flight**, **lift**, **teleport**, **Hearthstone**. A trip on
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
| Flights | both ends are flight points TwichUI has seen the character can fly to and your faction's. It records them each time a flight master's map opens (`C_TaxiMap.GetAllTaxiNodes`, state Current or Reachable), per character, and never forgets one; `GetTaxiNodesForMap`'s `isUndiscovered` gave every point as learned in play, so it is not used. Learned only while Navigation is on | the path's length at 32 yd/s, plus 12 s to board |
| Boats and zeppelins | both docks allow your faction | the ride (16 yd/s for a boat, 20 for a zeppelin), plus the expected wait (a transport visits a dock once a cycle and stays 60 s: someone arriving at random waits (cycle − stay)² / (2 · cycle) on average), plus 12 s to board |
| Mage teleports | the spell is known and a Rune of Teleportation is in the bags | the cast (10 s) plus a 20 s bias, because it uses a rune; it lands at the city's flight point (Darnassus: the middle of its map region) |
| Hearthstone | in the bags, and the bind point is known to TwichUI | the cast (10 s) plus what is left of the cooldown |

Walking is the weighted yards divided by your ground speed (7 yd/s on foot; the setting offers a mount at +60% and a fast
mount at +100%: mounts aren't read). **Every figure that isn't a distance is an estimate**, and the frame says so: the
client has no speeds, and where a boat is now isn't known. The plan is the cheapest under that model, not a proof of the
fastest way.

**Lifts** (`nav/Lifts.lua`). A lift is a hand-kept list entry: two stand points (x, y and the height of the floor) and an
estimate of the wait and ride (35 s). Each end is joined to the walking map at plan time, on the floor at its height, like
your position and the destination, so no re-bake is needed; the planner then rides between them both ways. The Great Lift,
the Freewind Post lift and Thunder Bluff's four lifts are listed. Their positions are the client's own: each is a placement of the
`thousandneedleselevator` WMO in Kalimdor's tiles (shaft axes (-4666, -1839) and (-5392, -2496)), and the stand points are
floors of the baked walking map at the bottom (z about -46) and the top (z about 86 and 89). Thunder Bluff's four lifts are in no
client file (the server spawns them; the AreaPOI, GameObjects and placement tables were searched), so theirs come from the
player's own position readings at each shaft. Each end is the nearest walking-map ground 14 to 19 yards from the shaft (the
mesa edge at the top, z 131 or 141; the lowland at the foot, z 59 to 61), so the walk ends at a spot beside the lift rather
than in the cabin. A lift is added to `LF.LIFTS` once its two stand points are known. A walk that ends at a lift says "walk to the Great Lift
(bottom)", the lift step says "Take the Great Lift up", and arriving within 10 yards of the other end plans again from
there. A plain walk that finds no way (`unreachable`) is tried again through the planner, which knows the lifts. Standing
on a pocket of ground the map doesn't join to the land (Freewind Post's plateau) normally counts as standing on the nearest
land; with a lift to that pocket on the map it doesn't.

**Stairs** are listed the same way (`stairs = true`, worded "Take the … stairs up"). Orgrimmar's flight master is the one entry:
the baked walking map doesn't join the foot of its tower to the top, so the walk there was a 900-yard loop round the east side
for a flight master 30 yards away. The top is the flight point's own stand point; the bottom is the street at the tower's west
foot, about 15 yards from the first step (the entrance isn't in any table), so **the position is approximate and unverified in
the game**. Other Orgrimmar stairs may be cut the same way; a scan found candidates but none were added without a position to
check. A short walk with the start or the destination within 250 yards of a lift or stairs end is planned with them (a plain walk
would take the loop); other short walks are just walked.

**The Hearthstone's bind point.** The game tells an addon only the name of the place (`GetBindLocation`), so TwichUI keeps
where the player stood when `HEARTHSTONE_BOUND` fired (at the innkeeper), per character, in `ui.navTravel` (account-wide,
never in a profile or shared). Without one the Hearthstone is not offered, and Navigation's settings say so.

**Reading a journey.** Steps are shown as "Step 2 of 4"; the note under the instruction says what comes next and the time
left. A walk before a boat ends at "Stormwind dock", before a zeppelin at "Orgrimmar zeppelin tower", before a flight at
"Stormwind flight master". A boat leg says to board it and what to expect ("Wait for it here: about 2 min, then about 3 min
aboard (estimates)"); a flight says to talk to the flight master and choose the destination; a teleport names the spell; the
Hearthstone shows a cooldown countdown when waiting plus the cast and onward travel is faster than the alternatives,
then says to use it. A missing, disabled or unreadable cooldown excludes the stone from new plans. Cooldowns are read
when planning; use Recalculate if availability changes during a journey. Nothing is ever cast, ridden or clicked for you.

**Following one.** A walk ends when you are within a few yards of its place and the next leg becomes the current one. Aboard
a boat or on a flight path (`UnitOnTaxi`) the state is "riding": nothing to follow, the plan is held. A boat's arrival (you
are within 150 yd of its arrival dock), a landing, a teleport or the Hearthstone (a jump of 120 yd or a new continent), or
walking well away from a dock you were to board, plans again from where you are.

**Flights** (`nav/Flight.lua`). When a journey's current step is a flight (or a walk to its flight master) and the flight master's
map is open, the flight point the journey lands at gets a glow, on whichever of the game's two flight windows is showing
(the flight map's pins or the older taxi frame's buttons), only if the map offers it as reachable from where you are.
**Highlight the flight to take** (`highlightFlight`) is on by default. **Take the flight for me** (`autoFlight`) is **off by
default** and does nothing until it has been confirmed on this account (`ui.flightAck`, like the restocking confirmation; a
profile or a shared setup can choose it but it waits for the confirmation here). When on: opening the map within 200 yards of
the flight's own flight master, with that flight as the journey's current step, asks the game for that one flight (the slot
the flight map gave for it), once (the same one is not tried again for 30 s). Never in combat, while already flying, from
another flight master, or for a point the map doesn't offer as reachable; it never opens a map or talks to a flight master.
**It is not known whether the client lets an addon call `TakeTaxiNode`** (the game's own windows call it from a click and it
isn't in the documented API). The call is guarded, and if the client reports it refused for TwichUI (`ADDON_ACTION_FORBIDDEN` or
`ADDON_ACTION_BLOCKED`) automatic flying turns itself off until a reload and the settings say so; the highlight stays. The
navigation diagnostics' `flight` entry has the counts (maps opened, glows shown, tries, flights taken, refusals), never a place.

**Known gaps.** The walking maps have no tram or Darnassus portal and only the lifts above, so Teldrassil is reached only by boat and
Darnassus (a teleport lands there) is cut off from the rest of Kalimdor; Thunder Bluff's other rises (Hunter, Spirit, Elder) are not joined to the main mesa in the map (their rope bridges aren't in it). A destination
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

- **Frame** (`nav/Frame.lua`): destination, instruction, distances, state, Stop and Recalculate. Its look starts from the framed look's espresso and aged bronze as a plain line (no artwork: it is a heads-up frame, not a window; a saved color is read as saved). A MenuStyle look
  (`ui.navigationLook`), so it looks complete without EllesmereUI; a teal rule across the top. Locked, only its two buttons
  take the mouse; unlocked, drag it. Text is set only when it changes; updated on events, never per frame.
  **Theme** (`ui.navigation.theme`, Appearance > Frame theme): `classic` (the default, as above) or `wayfarer`, a leather panel in a
  bronze frame (`media/nav/wayfarer.tga`: four corners and four rails in one 256 x 32 atlas; `wayfarer-leather.tga`: the centre, a
  seamless mirrored tile; built by `tools/make_nav_wayfarer_art.py` from `assets/nav-wayfarer-source.png`, which is wider than the
  frame and so is cut into a nine-slice, never stretched whole). Nine textures on the same frame, made the first time Wayfarer is used and
  shown only while it is chosen; Classic's background and border are cleared then and drawn again on switching back. Content sits 10
  units in instead of 8. Only the look's two opacities still apply (background: the leather; border: the frame). Appearance only: the
  route, the destination and every other behaviour are untouched.
- **Arrow** (`nav/Arrow.lua`, `media/textures/nav-arrow-bronze.tga`, built by `tools/make_nav_arrow_art.py` from `assets/nav-arrow-source.png`; white by default, no tint): aims 20 yards ahead along the current straight stretch, stopping at bends and the end of the walk.
  Passing beside a redundant straight-line waypoint continues forward. Route-bearing changes ease over about 0.12 seconds;
  your facing (`GetPlayerFacing`) stays immediate, at most 30 updates a second while shown. A direct bearing is grey and
  labelled "Direct bearing, not a route". With no position, no facing, while calculating or on arrival: a word, no arrow.
  On its own or in the frame.
- **EllesmereUI's Unlock Mode** (`nav/Unlock.lua`, optional): Appearance > Frame and arrow > **Move them in EllesmereUI's Unlock Mode**,
  off by default and only with EllesmereUI installed. `/unlock` then shows a **TwichUI Navigation** mover and a **TwichUI
  Navigation Arrow** mover (the arrow's only while it sits on its own), with EllesmereUI's own dragging, snapping, nudging,
  X and Y boxes and anchoring (no size boxes: the size is Frame size and Arrow size). Each mover is a small stand-in frame
  the size of what it stands for, scale applied; the frame or arrow is centred on it, so it follows with no hook and no
  per-frame work. The place is still `position` / `arrowPosition`, so Reset position, Save & Exit, a discard and configuration
  sharing ("place") behave as before; a place never set stays unset. While it is in charge, dragging in the game is off
  (Lock does nothing). The frame's stand-in is as tall as the frame once it has been laid out, else a typical three-line
  frame, so its outline can be a little off until a route has been followed once. Registered once and never unregistered
  (that would delete the player's anchor links in EllesmereUI); a mover is hidden from Unlock Mode instead. Same interface
  as `modules/FoodDrinkUnlock.lua`. Nothing is secure, so combat needs nothing special; Unlock Mode can't be opened in
  combat.
- **World map** (`nav/MapTrail.lua`): a data provider; the route from where you are to the destination, clipped to the map
  shown and drawn only on its continent, under the map's pins. Thickness stays the same on screen at every zoom.
- **Minimap** (`nav/MinimapTrail.lua`): the part of the route near you, turned with a rotating minimap (as the party pins
  are placed, `pins/Minimap.lua`), clipped to the minimap's circle, or its square when `GetMinimapShape` says so
  (EllesmereUI's square minimap doesn't, so the circle inside it is used: less is shown, never a line past the edge).
- **Trail**: a line or dots; optional ants (small lighter dots moving toward the destination). A direct bearing is never
  drawn on a map.

## Settings and saved data

`ui.navigation` (what is shown, starting by itself, arrival and off-route distances, sound, reduced motion, the frame's and arrow's look and
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
| `nav/Unlock.lua` | the optional EllesmereUI Unlock Mode movers for the frame and the arrow |
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
8. **No route.** Navigate to Thunder Bluff's Hunter Rise (not joined to the main mesa) and to the other continent: "No
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
    TwichUI learns flight points from the flight master's map: open one and Navigation's settings count the points learned;
    open another later and any new points are added. A point it has never seen on a flight map is never used.
16. **Journeys: a teleport and the Hearthstone** (a Mage with a Rune of Teleportation; anyone with a Hearthstone). Navigate
    somewhere far where a teleport or the Hearthstone saves time: the step says "Cast Teleport: ..." or "Use your
    Hearthstone" and nothing is cast for you. Do it: a new plan from where you land. The Hearthstone is offered only once
    your bind point is known (bind again at an innkeeper, or use the stone once during a journey); Navigation's settings say
    when it isn't. With the stone on cooldown the plan counts what is left.
17. **Journeys: leaving the plan.** Walk away from the dock you were to board; stand on the pier by it; swim; fly a different
    flight. A new plan after a few seconds each time, never one every update. Turn the options off one by one (boats, flights,
    teleports, Hearthstone): the plan changes, and with all four off another continent says there is no way.
18. **Cut-off places.** Navigate to Darnassus and to Thunder Bluff's Hunter Rise (the main mesa and Freewind Post are reached by lift; see Lifts):
    "No way there" with the reason, never a line through the air.
19. **Faction.** An Alliance character is never sent by a Horde zeppelin or flight, and the other way round.
14. **Pins and pings unchanged.** Party pins, map pings and the other map tools work as before; Ctrl-click still sets the
    game's waypoint.
19b. **Wayfarer theme** (nothing here has been seen in the game). Appearance > Frame theme > Wayfarer, with the preview shown, then
    while following a route: the frame turns to leather and bronze with no second border or Classic background behind it; the
    route, destination and arrow are unchanged. At actual size the corners keep their shape and the rails one thickness; check at
    Frame size 60, 100 and 160, with a long destination name and a wrapping instruction, that no text touches the frame or the Stop and
    Recalculate buttons, and that no white fringe or seam shows. Switch to Classic and back several times: the Classic frame returns
    exactly, with no leftover edge. Drag it (unlocked), `/reload`: the theme is kept.
20. **EllesmereUI Unlock Mode** (needs EllesmereUI; nothing here has been seen in the game). Turn on Appearance > Move them in
    EllesmereUI's Unlock Mode: the frame and arrow do not move. `/unlock` lists "TwichUI Navigation" and "TwichUI Navigation
    Arrow" (with the arrow in the frame, only the first) even when no route is being followed. Drag both, nudge with the arrow
    keys, type X and Y, anchor one to another element, Save & Exit: follow a route, the frame and arrow are where you left
    them, also after `/reload`. Repeat and discard: they go back. Check the outlines are about the right size (the frame's
    may be a little off before the first route), change Frame size and Arrow size and look at them again. With Lock off,
    the frame can't be dragged in the game while this is on; turn it off and it can. Reset position puts both at the top
    of the screen again. Disable EllesmereUI: they sit at the saved places and the tooltip says why.
