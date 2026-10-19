# navbake: TwichUI's walking maps

Builds `TwichUI_NavData` (the walking maps navigation plans on) from a local World of Warcraft: Forever installation.
Offline only; nothing here is packaged (the packager leaves `tools/` out) and nothing is ever written into the game's
folder.

```
tools/navbake/bake.sh "/path/to/World of Warcraft" [maps...]     # default maps: 0 1
```

Needs `python3` (standard library only), `g++` and `make`. `fetch_deps.sh` (run by `bake.sh`) clones the one third-party
dependency into `.deps/` (git-ignored). Intermediate files go to `~/.cache/twichui-navbake` (`NAVBAKE_CACHE`), which can be
deleted at any time. A full bake of both continents takes about five minutes on a many-core machine.

## Provenance and licences

| Part | Origin | Licence |
|---|---|---|
| `casc.py`, `wowfiles.py`, `extract.py`, `pack.py`, `cbor.py`, `fixtures.py`, `navbuild.cpp`, debug tools | TwichUI's own | MIT (TwichUI's) |
| Recast (`recastnavigation` v1.6.0, commit `6dc1667f`), fetched to `.deps/`, compiled into `build/navbuild` only | Mikko Mononen and contributors | zlib (see `.deps/recastnavigation/License.txt`); approved for offline use on 2026-10-19; not shipped |
| The walking maps in `TwichUI_NavData` | generated from the game client's terrain, buildings, doodads and liquid tables | derived from Blizzard Entertainment's game data; not covered by TwichUI's MIT licence |

No data or code from another addon is used. NaowhForever's Journeys data is "all rights reserved" and Shortest Path
Forever's is GPL-3.0; both were looked at only to learn what kind of data such a feature needs.

## The travel network (flights, boats, zeppelins, teleports)

`transit.py` reads the client's TaxiNodes, TaxiPath and TaxiPathNode tables with `db2.py` (our own reader for the client's
DB2 tables, format WDC5: sections, bit-packed, pallet and common columns, string tables, relationship blocks; checked against
LiquidType's known answers) and writes `transit.json`; `pack.py` bakes it into `Data/Transit.lua` and, per map, joins its
places to the walking map (`places.py`: stand point, attachment to the tile's crossings, walks between places).

Checked against this client:

- A flight point a character can learn has a nonzero `CharacterBitNumber`; the others are the pseudo-nodes transports hang
  their paths on ("Transport, Menethil Ships"), quest and battleground flights and retired entries ("zzOLD...").
- A node's mount creature per faction, `[Horde, Alliance]`, says whose it is (a nonzero entry each).
- A taxi path between two flight points is a flight, as long as its nodes (3D). A path with stops (a node flagged 2, with a
  delay) is a transport's loop: it wraps from its last node to its first. Between two stops it covers the on-map distance
  of its nodes; a node after a teleport-flagged one (flag 1), or on another map, is a jump the transport makes instantly.
  A zeppelin's stops are high above the ground (z over 20), a boat's at sea level.
- The client holds no speeds and no timetable. Speeds are estimates (flights 32 yd/s, boats 16, zeppelins 20), and a transport
  is taken to visit each dock once a cycle (its loop's length at that speed plus its stops' delays). The ride times it
  gives (a minute or two to three) agree with how long these rides take, as far as can be told without the game.
- Teleport arrivals: the client has no table of where a teleport lands (the server has it), so a city's arrival is taken to be its
  flight point (Darnassus, with none, the middle of its map region in UiMapAssignment).
- Forever's own additions are in the tables: a Stormwind harbour boat to Auberdine, Gadgetzan to Powderfuse Port, zeppelins
  from Undercity and Thunder Bluff to Zephras Isle, and flight points in Riverglades and Tidegear Coast.
- A ship dock's stand point: the boat's stop is on the water, and the walkable pier beside it is often a fragment the mesh
  doesn't join to the shore. A dock without a height stands on the nearest ground of a connected area of at least 50,000 sq yd
  of *ground* (the sea round a pier makes a large component that isn't land), up to 150 yd away.
- A run of linked edges along a tile side is split by the connected areas it joins inside the tile, so a pier's planks next to
  the shore don't share one crossing (which left them cut off in the crossing graph).

Not in the client, so not in the maps: lifts and elevators, the Deeprun Tram, the Darnassus portal (their destinations are the
server's).

## Pipeline

0. **`transit.py`** (once): the network above.
1. **`extract.py`** reads the client's CASC storage (`casc.py`: `.build.info`, build config, local `.idx` indices, the
   encoding and root tables, BLTE; encrypted files are skipped, never decrypted) and, for each ADT tile of a map, writes a
   `.tin`: the terrain's MCNK heights and hole masks, the collision triangles of every doodad and WMO reaching within
   12 yards of the tile, deep liquid surfaces, and liquid volumes.
2. **`navbuild`** (Recast) voxelises a tile with its neighbours' terrain, filters for a walking agent, marks the liquid
   volumes, and builds a polygon mesh (`.tnm`).
3. **`pack.py`** (with `--transit`) links polygons across tile edges, drops isolated pockets, groups the links into crossings, works out
   the cost between every pair of crossings inside each tile, and writes Base64, zlib-compressed CBOR records into
   `TwichUI_NavData/Data/Map<m>*.lua` (the format is in `TwichUI_NavData/README.md`), then the addon's `.toc`.

## Facts checked against this client (build 1.60.1.70450), not taken on trust

- WDT `MAID` gives each tile's root and obj0 file IDs; placements reference files by ID (`MDDF` flag 0x40, `MODF` 0x8).
- A tile is (x column, y row); MCNK `position` is (world x north, world y west, base height); `ix` runs east, `iy` south.
- High-resolution holes are row-major (`bit = row * 8 + column`): the two orders were compared at Ironforge's gate, where
  only this one gives one coherent opening.
- M2 collision is the `MD20` header's triangle and vertex arrays at 0xD8 / 0xE0.
- Placement: world = Rz(ry + 180°) · Ry(rx) · Rx(rz) · model + (32·T − pz, 32·T − px, py). Checked against `MODF`'s stored
  world extents for 40 WMOs (0.0 yards of error; all were turned about the vertical axis only, so the tilt terms are
  untested).
- Modern WMO groups use `MPY2` (4 bytes per face) and sometimes `MOVX`; faces and flags line up one to one. Collision is
  the classic rule: a face collides when it has the collision flag, or is rendered and not "detail".
- Liquid families come from `LiquidType.db2`'s 2-bit field 3 (0 water, 1 ocean, 2 magma, 3 slime), identified by comparing
  it with every liquid's name; the reader refuses to run if that field moves. Forever's new liquids (PBRWater…) classify
  correctly this way.

## Settings and why

| Setting | Value | Why |
|---|---|---|
| Cell size | TILE / 500 ≈ 1.07 yd | Doorways of about 2.2 yd stay open after erosion; finer cells cost data for no guidance value |
| Agent height / radius | 2.0 / 0.6 yd | A player character; erosion of one cell |
| Climb | 2.0 yd | At 1.2 yd Ironforge's gate steps cut the city off; a player steps or hops up a ledge this high |
| Max slope | 50° | |
| Island minimum / merge | 600 / 1500 cells | Specks on mountainsides go |
| Edge error | 2.5 cells | |
| Doodads | walls only when barrier-shaped (at their base at least 6 yd long and a third as wide); otherwise walkable surfaces only | A player steers round a tree; Forever's tree hulls are 15–30 yd wide and cost thousands of polygons |
| Deep water | surfaces where at least 1.5 yd deep are walkable as swimming; the floor under them costs the same | |
| Magma, slime | impassable | |
| Pockets | components under 5,000 sq yd dropped | Unreachable by walking; dropping them lets a destination snap to reachable ground |
| Crossings | one per run of linked edges, split every 128 yd |
| Edges between crossings | a 5% greedy spanner of each tile's pairs | Half the edges (and memory): every path through the stored graph is at most 5% longer than over all pairs, 0.5% on average, nothing disconnected. Measured on Kalimdor: 133,575 edges to 68,286; the same test at 10% keeps 38% and 20% keeps 27%, with mean paths 1.8% and 4.3% longer | |

## Sizes (both continents)

About 10 MB in Lua files: 8.7 MB of tiles (Eastern Kingdoms 3.7 MB, Kalimdor 4.8 MB, Zephras Isle 0.1 MB), 1.5 MB of crossing
graphs and 0.2 MB of places and the walks between them, and 4 KB of travel network. Zephras Isle's WDT is file 7198644 (its
name, `world/maps/2991/2991.wdt`, is in the community listfile; `Map.db2` isn't stored locally).

## Debugging a bake

`viz.py` renders tile meshes to a PNG (optionally a route over them, `--path`, and a world box, `--box`); `connect.py`
says whether two world points are connected and where two unconnected areas come closest.

## Tests

`fixtures.py` makes small synthetic maps and packs them with `pack.py` itself, into `tests/fixtures/nav_fixture.lua`;
`tests/test_nav_route.lua` plans routes on those and on the real data.
