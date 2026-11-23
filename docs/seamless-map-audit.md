# Seamless map audit and verification

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
| Underground | 29 verified micro maps only | Micro maps plus rotated WMO minimap pictures, underground city pictures | **Confirmed:** most caves have no micro artwork. Add numeric WMO picture data and reusable transforms; retain safe painted fallback where unsupported | P3 | Fargodeep coverage, WMO rotation/crop and city cases |
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

Implementation results, performance measurements, scenario matrix and native
checklist will be recorded here after the repaired production paths are tested.
