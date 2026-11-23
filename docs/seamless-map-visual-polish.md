# Seamless map visual polish

## Accepted starting point

PR [#138](https://github.com/Twich-Team/TwichUI/pull/138) merged into `main` as
`7fbebd3b6ddd2143d6445b0f1eead58ca487023e`. Required PR verification passed
340 modules / zero failures, as did Market regressions; the automatic main
verification also passed. The separate local complete run retained the documented
Welcome Back baseline failure (339 pass / one failure at
`test_welcome_back.lua:84`); its code and assertions remain unchanged.
No publication or deployment occurred.

`feature/seamless-map-visual-polish` starts at that exact merged main. Navigation,
terrain/interior budgets, cave/city/NPC behavior, diagnostics, the real-art lab
and collector are preserved. The accepted `map-regional-after` and earlier
reference galleries remain untouched.

## Matching cameras

`polish-v1` adds ten fixed production-Lua cameras at 4/8/12/24: Eastern Kingdoms,
Kalimdor, central Eastern Kingdoms, the southern boundary, Badlands,
Elwynn/Westfall/Duskwood, Stranglethorn, Booty Bay, Tirisfal and Undercity.
Requested and actual centers/zoom are exported separately. These are repeatable
presets, not recovered player screenshots. Existing catalogs are unchanged.

```sh
python3 tools/maplab/run.py --client-bundle /private/part-01.zip \
  --client-bundle /private/part-02.zip --client-bundle /private/part-03.zip \
  --scenario-set polish-v1 --output test-output/map-polish-review --strict
```

Private baseline: `test-output/map-polish/baseline/index.html`, built from the
accepted production sources with Forever 1.60.1.71037 artwork and the previously
validated same-build legacy supplement. Lua export: 1.713402 s; composition:
165.055305 s. Offline wall times do not measure native CPU/GPU performance.
The state records all eight production-renderer source hashes.

36 of 40 views have complete visible artwork. Eastern overview, Kalimdor,
Badlands and Stranglethorn at 24 are partial for 44 unique uncollected textures.
The lab retains explicit placeholders/findings; these are missing lab inputs,
not evidence of missing installed-client artwork. The generated private
`asset-request.json` identifies inputs for a future refresh. No additional input
is required to investigate the complete regional views.

All source artwork, derived studies and comparison screenshots remain ignored
private files. No Blizzard-derived pixels are packaged or committed.

## Native regional mountain connection

Direct inspection found a parent-letter stem in the gap between Elwynn,
Burning Steppes and Redridge. Two **native base** mountain bands occupy that
same geographic position without the parent lettering:

| Native source | Art | Source-pixel rectangle | Original base files |
| --- | --- | --- | --- |
| Burning Steppes 1428 | 2149 | (390,450)–(665,645) | 8060555, 8060556, 8060548, 8060549 |
| Elwynn 1429 | 2153 | (800,150)–(990,430) | 8061964, 8061968 |

`map/Art.lua` crops those installed sources at their original world coordinates,
through two existing owned WIDE mask regions, **below every regional explored
piece**. Source RGB, tile UV alignment, camera geometry, overlay feathers and
biome colors are unchanged. In particular the accepted Redridge right-edge mask
remains untouched. This restores mountain context instead of widening a fade
into blurry parent art. It is not a replacement continent renderer.

The first private single-source probe restored the upper mountains but left the
lower letter stem. The paired source removes that fragment and joins the mountain
band in the directly inspected 8/12 views; matching 4/24 and the adjacent
Elwynn/Westfall/Duskwood view were also inspected. These probes informed the
production change; final production-Lua comparisons are recorded below.

Exact Forever 1.60.1/71037, art/canvas/tile layout, reviewed explored-piece IDs
and geometry, and all cropped base file IDs gate activation. Unknown inputs,
missing owned mask or a rejected crop retain native fallback. A rejected file
releases every crop in that source region. At most **six textures** and **two
mask regions** are made, once. Only a region intersecting the actual view binds
its files; exit/close releases them and reopening reuses geometry. Hide mode
suppresses the extra context; dim follows the adjacent reviewed piece's discovery.
Preference/exploration changes update immediately. “Loaded” means addon-bound
files, not a claim about native GPU streaming completion.

Existing `map.art.update` measures the work; there is no new polling, updater,
profiler or player-position query. `MapArt.Snapshot/Diagnostic` exposes the six-file
budget, made/bound counts and each region's status, source IDs/pixel rectangle,
tint and failure. AI map reports consume that actual production state.

## Largest title and ocean: reviewed limitation

The giant title farther northwest remains. Among the supplied artwork, neither
world 947 nor continent 1415 provides a complete text-free alternative there.
A new same-world-source experiment used world art 2141, files 8025437/8025438,
ROI (638,336)–(806,368), below the zones. It removes the upper EASTERN fragments
at 4 and around Badlands 8.1; 12 private probes rendered with zero missing inputs
in 28.394 s. Primary inspection of the matching coastline crop found an obvious
hatching/shore transition. WIDE leaked letter edges; THIN exposed a strip. The
world's own lettering also overlaps the lower KINGDOMS row, preventing a clean
extension. **This experiment was rejected for production.** It does not justify
arbitrary cuts, blurred replacements or geographically relocated terrain.

All 45 collected native highlights have opaque DXT1 alpha, so they cannot supply
filled native territory masks directly. Existing RGB coastline studies are
empirically aligned source-image studies, not authoritative native mask API
geometry. The earlier plain-paper/extended-base backdrop variants remain off.
The western enlarged hatching and incomplete regional frame support therefore
remain unresolved, rather than being disguised by a smoother empty fill.

## Intermediate detail and longer-term hybrid

The current terrain transition and budgets are preserved. At Booty Bay 24 the
native renderer requests 24 tiles (below its 80 cap) at alpha 0.109375; at 48 it
uses six opaque tiles. The deep water seam is partly present in adjacent native
204423/204463 sources. No placement/filter defect was established. All 79
collected mainland minimap files have one mip; pinned OpenMap also uses LINEAR.
A filter switch or stronger global opacity is not an evidence-supported repair.
The preload-margin budget may be worth a separate tall-viewport investigation,
but it was not reproduced as a defect in these real-art cameras.

Retain dynamic native terrain/interiors/markers plus reviewed native base fills.
A future optional bake should supply semantic territory/core/boundary masks,
source-specific city cuts, reviewed coast/ocean support and a bounded intermediate
LOD, with exact build/source manifests and atomic native fallback. It still needs
complete geographic coverage, native loader/filter/streaming tests and an
established redistribution basis. OpenMap's MIT code/data/tools license excludes
its generated Blizzard and edited artwork; it grants no blanket derivative-art
rights. No rasterized game silhouettes or edited source art are shipped here.

Measured private storage: 79 native 512-square DXT1 minimap files total
10,447,276 bytes. Equivalent uncompressed RGBA TGA is approximately 7.93 times
larger. The earlier five-zone three-level study costs 22,285,980 bytes plus
983,700 mask bytes. These are storage examples, not complete-world package sizes,
GPU memory measurements or runtime speedups. The production correction adds
**zero packaged map-art bytes** and uses established texture/mask APIs.

## Production comparisons and bounded cost

All **40** production-Lua camera rectangles and existing texture primitives match
the accepted baseline exactly after excluding the six added source crops and
sequence indices. The final full revised gallery takes **157.449 s**, with the
same four partial deep views/44 absent inputs as baseline. Those timings are
not a before/after native speed comparison. The strict five-view production
checkpoint on the final renderer has zero missing assets/findings (28.447 s). Final source-ROI culling
changes bindings outside the visible region rather than its appearance.

Primary inspected actual source canvases, matching 4/8/12/24 regional images,
neighbors and the rejected experiments. The retained change removes the central
parent-letter stem and restores the illustrated mountain connection at 8/12.
Giant northwest lettering, western ocean hatching, and the separate southern
parent-backed gap remain. No whole-continent fidelity claim is made.

Private matching gallery: `test-output/map-polish/revised/comparisons.html`;
`central-eastern-8-comparison.png`, `central-eastern-12-comparison.png` and
`central-eastern-24-comparison.png` show accepted main on the left. Full original
and revised galleries retain layer overlays, coverage findings and source hashes.
The accepted reference gallery has not been overwritten.

A separate Duskwood native-band experiment was rejected: its two clean native
sources sharpen a short band but make the remaining rectangular green gap more
obvious. The requested gap point maps to native source (951.9,636.61), which is
blank parchment. No invented terrain or frame expansion was enabled.

A deterministic **two-zone Lua/mock microbenchmark** compares accepted `Art.lua`
against the changed module using the same fixture (three runs, median below).
It excludes native graphics/file streaming, markers and other map modules.

| Batch | Accepted main CPU, ms | Revised CPU, ms |
| --- | ---: | ---: |
| 100 cold regional reveals | 8.128 | 12.869 |
| 10,000 unchanged views | 9.581 | 14.016 |
| 10,000 small pans | 10.935 | 14.685 |
| 1,000 close/reopen cycles | 3.634 | 7.962 |
| 1,000 region exit/reentry pairs | 6.588 | 12.677 |

The fixture retains a stable object count, makes zero texture writes on steady
views, and retains zero additional KiB after GC across a further 1,000 close
cycles. This is a bounded mock result, not proof of no native leak or a native
performance improvement. Six original source files total 269,256 bytes on disk;
binding counts do not measure freed VRAM. The test's GC is offline only.

## Verification and native acceptance

`./tests/run.sh feature navigation --profile cloud --jobs 2`: **108 modules
passed / zero failures**, **96 Python cases**, **314 Lua syntax checks** plus
runner/simulator scripts, and simulator smoke (41.323 s). Total **76.712566 s**;
source fingerprint unchanged. Receipt:
`test-output/verification/feature-navigation-dyy4bufv/report.json`.
The native mountain fixture passes **407 assertions**; existing city-cover
passes **345**. Focused client/transport/catalog validation passes 22 tests.
Cloud/synthetic checks do not establish native rendering, combat or taint acceptance.
The full-suite Welcome Back baseline evidence remains preserved; no unrelated
code/assertions were changed or complete suite rerun for this scoped checkpoint.

The final strict production gallery command is:

```sh
python3 tools/maplab/run.py \
  --state test-output/map-polish/revised/render-state.json \
  --assets test-output/map-regional-assets/manifest.json \
  --scene central-eastern-4 --scene central-eastern-8 \
  --scene central-eastern-12 --scene central-eastern-24 \
  --scene elwynn-westfall-duskwood-12 \
  --output test-output/map-polish/verified-keyviews \
  --baseline test-output/map-polish/baseline --strict
```

First native check: pan between northeast Elwynn, southern Burning Steppes and
northwest Redridge at **4→8→12→24→48 and back**. Confirm the mountain connection
replaces the central letter fragment without a rectangular flash, shifted roads,
changed biome cores or deep-terrain regression. Check cold close/reopen and
unexplored show/dim/hide. This is a build-71037 correction: a newer/unreviewed
client deliberately retains the accepted fallback. Capture `/tui mapdiag` with
precise geometry for a mismatch; source IDs and fallback status are in the report.
Retain ordinary cave/city, quest/marker, UI-scale and combat/taint acceptance.
No native client was launched or controlled; no release or deployment is authorized
by this draft polish PR.
