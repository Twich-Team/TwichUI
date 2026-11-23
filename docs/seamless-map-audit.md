# Seamless map audit and verification

V2 follow-up: [Map Diagnostics](map-diagnostics.md) and
[Map Visual Test Lab / hybrid pipeline evaluation](map-visual-lab.md). These
extend this audit; the original 322-pass/1-failure baseline below is preserved.

Baseline: `main` / `1a3d9eb`. Open PRs #91, #98, #117, #127, #131,
#133–#136 were reviewed for overlap; none changes the seamless map. No other
branch is integrated. Reference: OpenMap
[`6c2299f6`](https://github.com/openmap-world/openmap/tree/6c2299f6e1f9bdce1bbd92145f84a05b0c6c05a7),
including ARCHITECTURE.md, docs/testing.md, Map/Stitch.lua, WorldMap.lua,
Close.lua and Forever data/generators. Forever APIs were checked against the
read-only local `wow-ui-source` (MapCanvas and SharedMapDataProviders).
The five screenshots mentioned in the request were not attached to this chat.
No real-client appearance or input result is asserted here.

## Architecture before repairs

`map/Prefs.lua` owns profile preferences; `map/Data.lua` holds generated numeric
client data. `World.lua` caches API rectangles and converts each map to uiMap
947 normalized coordinates. `ViewMath.lua` separately converts continent yards
(north/west) to map coordinates (east/south). These are different spaces.
`View.lua` alone moves WorldMapFrame.ScrollContainer, installs one provider and
wheel/press hooks, and changes the native host after 0.6 s idle, outside combat.
`Art.lua` attaches a world-pixel root to that host; continents, explored zone
pieces and city base art fade on separate frames. `Detail.lua` pools terrain
tiles; `Caves.lua` surfaces verified micro maps; `DungeonView.lua` owns a separate
instance panel; `Places.lua` owns cave/transport/dungeon markers. Controls and
the native quest log remain on WorldMapFrame. Pins, pings, guild/NPC locations
and navigation use existing world conversions and inverse icon scaling.

The unit harness loads production modules, but its original fake map omits
native exploration artwork and zero-sized layout, uses only one synthetic
city, and tests very few overlapping animated wheel events. Existing simlab
smoke constructs settings, not a geographically accurate world map. Art files
and CASC game storage are unavailable in this environment; the installed
simulator runs with synthetic/no-assets data.

## Findings and correction matrix

| Subsystem | TwichUI before / evidence | OpenMap approach | Root cause / correction | Priority | Verification |
|---|---|---|---|---|---|
| Native artwork | Our art levels canvas+2..7; native MapExplorationPinTemplate is ~2002 | Puts native detail/exploration art away while stitched | **Confirmed:** opaque explored pieces cover cities, caves and minimap. Hide only owned replacement artwork; restore on detach/disable; retain quest/third-party providers | P1/P2 | Realistic native-art fixture, restore and refresh checks |
| Rapid wheel | Pending target clamped against min(pending,current); wheel delta reduced to sign | Pending target monotonic on inward scroll | **Confirmed:** crossing deep cave/city limit can reverse pending zoom. Accumulate actual finite delta and preserve pending inward target | P1 | In-flight limit crossing, batched/fractional deltas |
| Layout/inputs | FitPx divides zero-sized layouts; public glides admit NaN | Finite guards, valid positive layout | **Confirmed:** invalid values propagate to canvas/animation. Reject malformed motion; suspend rendering until dimensions exist; restore view on resize | P1 | Zero size, UI scale, malformed arguments/preferences |
| Host transforms | Single uniform K, root anchored in world pixels | Same world root / host transform | Architecture is repairable; assert host switches preserve world center/scale and marker placement | P1 | Round trips and host switch stress |
| Terrain IDs | WDT MAID numeric IDs, 736 EK / 988 Kalimdor | Same numeric IDs, same counts | **Verified equal:** no missing mainland tile-table explanation. Native artwork occlusion is the primary confirmed detail defect | P2 | Compare pinned data, file selection/placement fixtures |
| Detail budget | Counts empty grid cells, clears entire detail at >80 | Pooled visible native tiles, coarse baked LOD | **Confirmed:** abrupt all-or-nothing loss. Count real visible tiles; fade toward painted fallback as coverage exceeds budget | P2 | Tile budget/alpha sweep, bounded pools |
| Cities | No-overlay heuristic and API rectangles; all cities same level | City layers plus WMO interior minimaps; city plans lead surface detail | **Confirmed:** native overlays cover city art; surface exclusion removes whole touching tiles. Preserve city layer priority and blend terrain conservatively over city plans | P3 | All six city IDs, missing/invalid art |
| Underground | 29 verified micro maps only | Micro maps plus rotated WMO minimap pictures, underground city pictures | **Confirmed:** most caves have no micro artwork. Add numeric WMO picture data and reusable transforms; retain safe painted fallback where unsupported | P3 | Explicit Fargodeep data gap, WMO rotation/crop and city cases |
| Cave transitions | Detail listener runs before cave listener; binary detail cutoff | Shared view-derived close detail | **Confirmed:** previous cave state can suppress next frame, abrupt loss at 50%. Derive same-frame strength and fade underlying terrain proportionally | P2/P3 | Entry/exit frames, partial alpha, floors |
| Stitch presentation | Existing feathers and layer fades; no land/territory masks | Art-derived territory/core/land masks, ocean octaves, city cuts, baked LOD | **Known gap:** arbitrary artwork masks cannot be reconstructed without assets. Fix occlusion/order first; preserve existing identity; document asset pipeline follow-up | P4 | Layer geometry preview; native visual checklist |
| Cost/lifecycle | Tile pool bounded; decoded numeric strings; per-view work | Pools, culling, detached idle anchors, async texture checks | Keep bounded pools, no full rebuild per wheel, clear texture references on close; measure representative workload | P5 | Creation/set counts, stress and idle/close checks |
| Integrations | Native quest/Questie/TomTom remain on host; TwichUI pins cross zones | Native quest log retained; additional cross-zone provider adapters | Preserve contracts; host-only external pins outside host remain an existing limitation | P1/P5 | Existing navigation/pins/guild suites; native checklist |

## Design invariants

1. World center and zoom are finite; zoom >=1 and canvas scale >0. Invalid or
   zero-sized layouts never write to the canvas.
2. A host-map change alters only the representation of the same world view.
3. Wheel input accumulates into the pending target. An inward event cannot
   reduce it when the cursor leaves a deeper context.
4. At every animation sample the selected world anchor projects to the same
   cursor offset, except where the global view boundary clamps the center.
5. Art and markers share one world transform; icons counter-scale separately.
6. Only the native base/exploration painting is replaced. Quest log, quest pins,
   player markers and third-party providers keep their native ownership.
7. Missing detail leaves the existing painted map visible. No invented maps,
   uncontrolled magnification or unbounded texture pool.

## Reference and artwork licensing

OpenMap's code/data/tools are MIT (2026 OpenMap contributors); its LICENSE
explicitly excludes Blizzard artwork and art edits. Techniques above inform
independent repairs. Numeric WMO placement/picture tables may be reused with
the complete MIT notice, pinned source provenance and a strict offline importer.
No OpenMap runtime, baked textures, masks, edited artwork or library is added.
Client-owned texture IDs refer to assets the game must already provide; their
presence in a data table does not prove texture availability in this environment.

## Verification and delivery

The repair keeps the existing world root, scroll container, settings and marker
interfaces. It replaces ownership of the native painting, fixes wheel/context
limits and layout snapshots, and adds one shared close-detail picture renderer.
Native base/exploration frames restore on hide/disable; released pool objects
are never resurrected. The six known Forever cities always use city base art,
even if their APIs return explored pieces. Their surrounding zones stay in the
navigation chain; outer city parchment does not take clicks from the zone.
Zoom/mode changes do not write the native canvas during combat. This conservative
pause is unit-tested, **not a native taint/combat certification**.

`LocalData.lua` contains 248 WMO areas and 2 underground cities, 1,906 picture
references, from the pinned OpenMap Forever table. The original has 1,909
references: three uses of an edited Blizzard texture in two areas are omitted.
Those two areas retain their numeric neighbours and the underlying painting;
their omitted pictures are an explicit coverage gap. No edited asset path is
rewritten to a guessed file ID. The standalone importer requires the reviewed
source hash (normalized trailing newline) and parses numeric tuples without
executing Lua:

```sh
python3 tools/mapdata/import_local.py /path/to/pinned/OpenMap/Data/Forever/CaveMinimap.lua
```

The data is for build 1.60.1.70245, also the mainland terrain data baseline.
Newer client asset availability is **not tested** here. Original data generation
and the stricter TwichUI micro-map verification are not replaced by the importer.

### Offline coverage and measured costs

- `tests/test_map_explore.lua` plus `map_seamless_cases.lua`: production modules
  against a synthetic native-style scroll container; native painting ownership,
  missing context fallback, rapid fractional/batched wheel input,
  pending inward/outward limit crossing, 40 reversible animation cycles,
  center/edge/corner anchors, 0.65/1.25/2 UI cursor scales, interrupted drags,
  host switches, zero-sized opening/resizing, stale deferred map prevention,
  malformed preferences/motion, combat motion/disable deferral, cave blending,
  texture readiness/fade/deadline/release, and dense tall-viewport tile budgets.
  Lowering the live maximum also rebases and limits a pending animation; unrelated
  visual preference changes do not clamp a deeper in-flight view.
- Seed **73471**, **4,000 mixed operations**: approximately **1.7 s CPU** in this
  environment (includes synthetic frames/providers, not native GPU time). The
  warmed course creates **zero additional terrain textures**, at most **24 active**;
  the separate dense-viewport course crosses the 56–80 fade range and >80
  fallback, and asserts **at most 80 terrain textures created/in use**.
- `test_map_local_data.lua`: all **250 records / 1,906 references** checked for
  numeric shape, orientation, finite production transforms and pool lifecycle;
  all six city base maps construct even with explored API pieces. Drawing each
  record through one reused pool peaks at **217 textures** (the largest city).
  The renderer's safety bound is **256 per picture set**, with at most one cave
  and two underground city sets. Normal high zoom culls almost all distant
  pictures. This is a bounded count, not a promise of native frame time.
- Numeric local data retains **275.4 KiB** in isolated Lua 5.1 after collection;
  the generated source is **111,580 bytes**. Geometry and GPU allocations are
  additional. No gameplay code forces collection. Static data remains loaded
  when the map closes; bound picture pools remain but texture bindings clear.
- After settling/closing the synthetic course, **zero updaters** remain. Ready
  textures use no polling. Asynchronous detail uses native `IsObjectLoaded`,
  fades over 0.15 s, and stops waiting after 10 s; this deadline bounds work,
  not map navigation. A released texture cannot reappear from a late load.
- Existing `map.view.*` diagnostics include the view work. Added
  `map.interior.update`, `map.texture.load` scopes and active/pooled/pending
  gauges expose the new costs without location/name data.

These numbers establish bounds and allocation reuse; no overall speedup over
main or real-client frame-time improvement is claimed.

The offline preview runs the production layer selection through that same
fixture, records texture IDs/world bounds/alpha/rotation, then draws coloured
rectangles using Pillow:

```sh
python3 tools/mapdata/preview.py --output test-output/map-preview.png
```

It covers overview, zone border/terrain, city plan/interior, painted cave, WMO
interior and missing-detail fallback. It is **simulated synthetic geography**,
not a before/after terrain screenshot. It does not render real art, feather
masks or out-of-range texture crop transparency. Existing simlab smoke checks
addon loading and settings construction with assets disabled. Neither proves
native map fidelity, input, resource availability or taint.

### Location verification matrix

For every row, the manual pass must check geography, texture choice/alignment,
marker alignment, repeated cursor zoom, pan across boundaries, layer overlap
and a short diagnostics capture. “Mechanism tested” means synthetic coverage
of that production path; it is never a real-geography visual pass.

| Location | Offline evidence | Native verification / remaining limitation |
|---|---|---|
| Entire Eastern Kingdoms | Terrain table exactly equals pinned OpenMap's 736 entries; overview/host transforms tested | Trace continent outline, cross-zone geography, native art seams |
| Entire Kalimdor | Same comparison, 988 entries; overview/host transforms tested | Same, including city/continent borders |
| Stranglethorn Vale | Shared zone/terrain/marker mechanism tested | Pan north–south; align painted roads with minimap at 20–48x |
| Grom'gol | Shared terrain/marker path tested | Compare coast/roads, player and waypoint positions while zooming |
| Booty Bay | Mainland IDs present; close-detail path and missing-resource fallback tested | At 37–48x verify correct coastal tile IDs and detail visibility; do not assert detail loads from the screenshot claim |
| Tirisfal / Undercity | City classification, native-art suppression, real 217-picture interior data transforms tested | Surface → city → inside texture alignment, entrances/lifts; surface must not cover underground plan |
| Orgrimmar | Known city ID forced to base art; synthetic city construction tested | Durotar → city → back; player and quest marker alignment |
| Stormwind | Same; surrounding Elwynn included in city navigation relationship | Elwynn → city → back, quest log remains interactive |
| Ironforge / Thunder Bluff / Darnassus | All three base maps constructed; Ironforge WMO table tested | City edges, mountain/mesa/trees; native artwork feather/labels |
| Goldshire | Shared terrain path and cursor anchors tested | Close terrain should align; player and Questie icons remain screen-sized |
| Fargodeep Mine | **Explicit data gap**: no verified TwichUI micro maps 38/39; WMO reference excludes places covered by those legacy micro maps | Surface fallback only. Requires Forever-specific WMO extraction/validation before interior support can be claimed |
| Wailing Caverns | Existing entrance micro map 11 and dungeon entry retained; dungeon panel path tested synthetically | Compare Forever's rebuilt instance and entrance against actual art; no new retail geometry accepted |
| Representative unmapped cave | Missing-artwork and bounded fallback mechanisms tested | No invented floor/inside map; continue to use surface painting/minimap |
| Zone borders | Cross-zone pans, stable host switches, masks retained | Review overlapping painted terrain and labels with actual textures |
| Coast / ocean | Missing-detail cap, budget fade and overview tested | No abrupt square sea tiles, stretching or blank background at native aspect ratios |

### Exact owner-directed native checklist

1. Start with seamless mode **off**, open/close the world map and native quest
   log, inspect a dungeon map and place a normal waypoint. Turn seamless mode on
   in TwichUI's existing settings; window styling and quest-log layout should match.
2. On each continent zoom from world overview to a zone and back 20 times, with
   the cursor at center, four edges and four corners. Alternate rapid inward and
   outward scrolling, move the cursor away from a city/cave during an animation,
   drag during a zoom, and pan past the current host's map boundary. Only the
   global world boundary may displace the cursor anchor.
3. Follow every location row above, especially Booty Bay at 37–48x and Tirisfal
   into Undercity. Verify surface art never covers the inside map. Check one
   painted multi-floor cave and one WMO-only cave; switch floors and Leave,
   then zoom out. WMO rooms have no automatic floor detection.
4. Repeat with Questie and TomTom absent, then present. Check native player/group,
   Questie objectives, a TomTom waypoint, TwichUI local/party pins, navigation
   trail, guild locations and flight/transport markers at several zooms. Click a
   visible neighbouring zone before the native host follows. Keep icon size
   constant and inspect native quest-log selection during host changes.
5. Resize wide → narrow → tall and change UI scale; close/reopen during an ease.
   Turn terrain detail and caves off/on; disable seamless mode while deep, and
   verify the complete normal map and wheel/pan return. With OpenMap loaded,
   TwichUI must remain blocked as before.
6. Enter combat, open/close the map, try a wheel/glide and toggle seamless off.
   Motion/disable should defer without errors; after combat the default map
   should restore. Inspect quest tracker updates and blocked-action/taint logs.
   Synthetic checks cannot establish this native secure behavior.
7. Capture `/tui perf` while traversing borders/cities for several minutes;
   compare active/pool/pending counts after each close. Capture native texture
   loading, missing-resource and frame-time behavior. Do not broadcast locations
   merely to test map rendering; Guild Locations keeps its existing sharing preference.

### Prioritized remaining work

1. **P2/P3, data-dependent:** extract/validate Fargodeep and the three omitted
   picture references from current Forever WMO assets; confirm Wailing Caverns
   instance geometry and all new inside texture IDs on a current client.
2. **P4, assets required:** derive TwichUI-owned territory/core/land/city-cut masks,
   ocean grain octaves and optional coarse minimap LOD from licensed local client
   artwork. This branch fixes occlusion/order/blending, but does not reproduce
   OpenMap's extensive art-processing pipeline or claim equal visual polish.
3. **P5, measured native evidence required:** profile protected map refreshes,
   cold texture bursts, large city interiors and third-party pin providers;
   optimize the observed bottleneck. Cross-zone Questie/TomTom pins that their
   providers do not expose on the current host remain host-limited; no speculative
   provider internals are hooked here.
4. If actual native aspect ratios reveal nonuniform host geometry, extend the
   affine placement contract using captured client rectangles. Current matching
   art/rectangle aspect assumptions remain shared with the reference approach;
   synthetic tests alone cannot certify every real map.

This is a reviewable architectural repair with explicit remaining native/art
work, **not a declaration that all OpenMap visual acceptance criteria are met**.

### Viewport assessment

The seamless renderer consumes the native ScrollContainer's actual width and
height and does not impose a smaller fixed map rectangle. A focused source
search found no TwichUI resize/reanchor of WorldMapFrame or its quest-log split
in this feature. The confirmed viewport defect was invalid/changed dimensions
feeding the zoom calculations, repaired here. Tall/wide layouts are tested;
changing the native quest-log/window proportions without actual visual evidence
would risk the explicitly preserved integration. Its real-client usable space
and feather clipping still belong to the native checklist.

### Recorded verification checkpoints

- Baseline `1a3d9eb`; audit checkpoint `a34816a`; implementation checkpoint
  `a81b9b8c0aad5d20d5c7da0ec2ecd845d7a9f1e2`, all pushed to
  `feat/seamless-map-overhaul`. Draft [PR #138](https://github.com/Twich-Team/TwichUI/pull/138).
- **Unit-tested:** `./tests/run.sh development navigation --jobs 2`:
  **38 passed, 0 failed**, 14.786 s. Targeted map integration/local-data tests,
  diagnostics/performance-engine tests and importer deterministic rebuild plus
  untrusted-source rejection also passed.
- **Unit-/simulator-tested at `a81b9b8`:**
  `./tests/run.sh feature navigation --profile cloud --jobs 2`:
  **93 passed, 0 failed**, syntax passed, **1 simulator smoke suite passed**,
  87.749 s total. Smoke uses synthetic/no-assets cloud fixtures. Other simulator
  catalogs and native acceptance are not claimed.
- **Complete offline regression at `a81b9b8`:** `./tests/run.sh`:
  **322 passed, 1 failed**, 657.806 s. The failure is
  `test_welcome_back.lua:84: two days back is a date`. Exporting that test,
  its harness and every loaded dependency from untouched baseline `1a3d9eb`
  into a disposable fixture reproduces the same assertion. No map source is
  loaded by that test. It is an existing unrelated failure; assertions were not
  weakened and Welcome Back was not modified. The complete offline gate is
  therefore **FAIL**, not a full PASS or release certification.
- Final review found that a live maximum change could leave an older pending
  destination above the new limit. The subsequent focused fix and regression
  pass the map integration course; the final feature checkpoint is recorded
  below. The expensive unrelated offline suite is not repeated
  for this local animation-limit change.
- Main advanced to `2835d714` during work (separate Execute Range/healer batch).
  The newer main diff was reviewed for overlap; GitHub reports the draft PR is
  mergeable with no conflict. No main merge, force-push, deployment or release
  was performed. The exact baseline above remains the branch's test identity.

Full logs/reports remain in ignored `test-output/verification/`, and the exported
Welcome Back reproduction in `test-output/map-baseline/`. These are local test
evidence, not packaged addon files. The simulated geometry preview was inspected;
actual WoW appearance, live pointer input, secure combat behavior, other-addon
delivery and real asset availability remain **not tested**.

**Final executable checkpoint:** `9d24fa3`, pushed. The final
`./tests/run.sh feature navigation --profile cloud --jobs 2` passes
**93 tests, syntax and simulator smoke**, with **0 failures**, in **97.177 s**
(smoke 53.560 s). The runner records a complete result and unchanged source
during execution. This includes the pending preference-limit regression and
the entire 4,000-operation course. Subsequent delivery edits are documentation
only. The complete offline gate's baseline failure above remains disclosed.
