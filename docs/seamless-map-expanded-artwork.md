# Expanded Forever artwork: composition and native city repair

The corrected feedback bundle removes the previous input-coverage blocker. It
contains the exact expanded request, including native highlight candidates.
This checkpoint delivers a production Undercity banner repair and lazy city-art
bindings, plus stronger **private offline** continent-composition experiments.
It does not enable the experimental continent renderer or claim OpenMap parity.

## Validated input and real baseline

- Forever **1.60.1.71037**, product **wowf**; collector **2.2.0**, bundle schema 2.
- Request SHA-256 `ebed8819ab0b952ef07cd0d76ac781662111181c94c295530f5cfb62286fbc3c`.
- **1,693 direct IDs + 45 derived highlight IDs = 1,738 assets**, 90,295,096 bytes.
- All **1,738 textures also pixel-decode successfully** (100,655,104 pixels,
  zero errors; 37.603781 s streamed decode audit).
- Zero missing, unsupported, corrupt-hash or invalid-header records. Request,
  build, numeric-source and client-metadata binding all validate.
- The optional UiMapLink table has reviewed layout `712A46E6`; its exported
  supported-map link list is empty. No conditional overrides or atlas-only
  candidates were silently treated as supported file IDs.
- All 45 highlights decode. They are BLP2/DXT1 with **alphaDepth 0**: alpha is
  uniformly 255. Direct alpha reuse would yield rectangles, not territories.

The **62-camera feedback-v1** baseline now renders with actual source art:
**zero missing assets and zero state findings**, strict exit 0. It uses 1,039
unique source assets across 8,167 texture placements. The 124 PNGs took
**146.890975 s** to composite; the separate Lua export took **1.953043 s**.
These are development-machine measurements, not native client/GPU performance.
Jasperlode and previously missing Skull Rock are now inspectable. Their readable
local-chart treatment and 0/0.5/1 entry states are preserved; no new cave fix is
claimed by this checkpoint.

All artwork, derived masks and screenshots remain in ignored private outputs.
No extracted data or generated game-image cache is committed or released.

## Production correction: native Undercity backdrop

Direct inspection located the stray right-hand **Y** and scroll tail in Tirisfal
explored overlays **7958244/7958245**, a 320x256 piece at source `(463,361)`.
The correctly placed native **base** already contains terrain without that
banner. The city's own round mask cannot remove lettering outside its frame.

`map/Art.lua` now reveals a bounded native-base ROI `(480,470)–(758,558)` above
zone overlays and **below** terrain/city layers. It uses four cropped base
textures **7958258, 7958259, 7958251, 7958252**, the existing TwichUI-owned wide
feather mask, unmodified source RGB and unchanged source/world geometry. There
is no inpainting, edited game texture, new mask asset, format or additional
profiler. The repair follows the city's actual transition alpha and the
carrier's explored/dim/hidden state. Preference/exploration events update it
immediately; events while closed cannot reload its files.

The repair fails back to the original artwork unless version/build
`1.60.1 / 71037`, parent art ID 2126, 1002x668/256-tile layout, carrier identity
and geometry, and all four source IDs match the reviewed input. A rejected bind
releases the entire repair and emits bounded failure evidence. Missing or new
client builds retain the existing native rendering. At most **four** repair
textures and one existing mask are created; files release on view exit/close.
There is no idle updater. Snapshots report active bindings, alpha and fallback.

The primary agent inspected the **actual production-Lua** before/after images:

| Fixed camera | Actual city/repair alpha | Changed pixels | Result |
| --- | ---: | ---: | --- |
| Undercity 12 | 0.202302 | 27,705 | Gradual handoff; parent label still readable |
| Undercity 14 | 0.505770 | 41,908 | Continuous native-base transition |
| Undercity 16 | 0.807108 | 55,654 | Continuous native-base transition |
| Undercity 18 | 0.987328 | 50,159 | Banner nearly covered |
| Undercity 24 | 1 | 64,382 | Stray Y/right scroll removed without an obvious rectangle |
| Undercity 48 | 1 | **0** | Pixel-identical deep terrain/interior output |

Tirisfal 12 changes 27,776 pixels. Both seven-view before/after galleries are
strict successes with zero missing sources/findings (**26.269/25.996 s**).
Changed-pixel counts include all visible effects; they are not quality scores.
Baseline addon code is untouched `a5da312` in a detached checkout with the same
current camera/export fixture. All **71** before/after world camera rectangles
match, and all original texture geometry, alpha, tint and masks match after
excluding the four added ROI sources and sequence order indices. No quest,
marker, navigation or original cave placement changed.

The first prototype placed the patch above terrain and caused an ochre wedge at
48: it was rejected. Moving it to the zone layer restored pixel identity. The
city's own upper-left title fragment and illustrated-plan/WMO double texture
remain; globally tightening city ellipses would clip actual Orgrimmar districts
or Stormwind harbor. No such broad crop was enabled.

## City texture lifecycle

City plans retain geometry but now bind source files only while visible, and
release bindings on view exit/close. Previously all six twelve-tile plans bound
at construction even with hidden frames. A world overview now retains zero
city-plan bindings; a visible city binds twelve, plus at most four reviewed
repair crops. Unchanged views do not rebind files. Reopening reuses geometry.
The client's own texture-cache retention/streaming behavior is not measured by
`SetTexture(nil)`; these counts describe TwichUI-owned bindings, not freed VRAM.

`MapArt.Snapshot/Diagnostic` and troubleshooting output expose loaded city plans,
bound plan/repair textures and repair status. Existing terrain cap 80 and
interior cap 256 remain. There is no new persistent polling/profiling loop.

## Private continent-composition work

`tools/maplab/composition.py` remains an offline extension of the existing lab.
Production Lua selects geography and camera/layer geometry. All new modes are
**opt-in and runtime disabled**:

- `--regional-backdrop`: native source-alpha territory/core/band masks, border
  chroma treatment, complete selected zone bases, coarse registered land support
  and an owned mathematical paper/fine-hatched ocean field replace enlarged
  parent paintings. Parent titles disappear by replacing that layer, not by
  smudging their pixels. Protected core RGB and biome luminance are retained.
- `--extended-base-claims`: shares more already-positioned native base geography
  across unpainted areas while excluding other sources' strong cores and
  respecting each source's frame availability. It is a higher-coverage study,
  not an accepted production setting.

The new coastline inputs are RGB outline images: Kalimdor **137148**, Eastern
Kingdoms **8027540**. Direct square stretching is wrong. Cropping the square
power-of-two source to the map-aspect upper portion, then resizing to 1002x668,
visually registers both outlines against their native continent bases. Source
pixel hashes and reviewed coast checkpoints pin that empirical registration.
This proves private **source-image** alignment; it does not establish native
`GetMapHighlightInfoAtPosition` crop/size/offset values or a runtime mask API.
The outlines are filled only as coarse land context; lakes/islands and precise
zone ownership remain nonauthoritative. Unknown land is plain paper, not
invented geography or silently classified sea.

The primary agent inspected matching Eastern Kingdoms, Kalimdor,
Elwynn/Westfall/Duskwood, Stranglethorn/Booty Bay and Tirisfal/Undercity images.
The six-view conservative gallery has zero missing assets/transparent holes and
runs in **76.316950 s**. It cleanly removes the giant parent titles/coarse hatching,
but leaves visible plain land gaps. The final two-view extended experiment
processes 31 zones in **51.286452 s** with zero missing assets/holes and zero
protected core RGB changes. It restores substantial native mountain/coast
context, but exposes straight frame endings west of Dun Morogh and occasional
neighbor/sea-name fragments. **Neither result meets production world-composition
acceptance.** The rejected hard-edge attempt and fixed frame-ownership regression
are retained privately. Parent pixel-repair hacks remain rejected/off.

Missing selected-zone sources or unsupported pinned coastline inputs retain the
whole native parent view or stop the explicit study with a clear error. The
original legacy bundle still supports the original default study; it cannot
satisfy the new explicit highlight-registration mode. Optional Pillow/NumPy/SciPy
processing is offline only; the collector remains Python standard-library-only.

```sh
python3 tools/maplab/composition.py \
  --client-input /private/client.json --assets /private/assets/manifest.json \
  --state test-output/map-expanded-baseline/render-state.json \
  --scene eastern-overview-4.1 --scene kalimdor-overview-4.1 \
  --regional-backdrop --extended-base-claims \
  --output test-output/map-composition-review-new
```

Drop `--extended-base-claims` for the conservative backdrop. Generate fresh Lua
state with the existing lab; **composition-v1** preserves all 62 feedback-v1
cameras and adds nine Undercity handoff/deep-detail cameras (71 total):

```sh
python3 tools/maplab/run.py --client-bundle /private/part-01.zip \
  --client-bundle /private/part-02.zip --client-bundle /private/part-03.zip \
  --scenario-set composition-v1 --scene undercity-handoff-24 \
  --output test-output/map-composition --strict
```

Render states now use deterministic compact JSON so the 71-view catalog can be
reimported under the unchanged 8 MiB limit (about 4.7 MB, versus approximately
10 MB with whitespace). There is no relaxed input or texture budget.

The offline replacement pass now distinguishes actual overlay IDs from native
base IDs. This preserves the production city repair when composing a new
snapshot; a dedicated regression covers that integration. The combined real-art
Undercity 24 study also renders successfully with zero missing assets. It does
not turn the private continent variants into production settings.

## Hybrid recommendation and remaining acceptance

Keep the native fallback and dynamic close terrain/interior/marker layers.
Use source-aware native-base corrections when an exact reviewed source/base
pair exists, as demonstrated here. Continue private build-time masks, boundary
grading and an intermediate LOD study for continent-level composition. The
previous [format/storage measurements](seamless-map-composition.md) remain valid:
85 uncompressed RGBA TGA tiles for only five zones cost 22,285,980 bytes before
983,700 mask bytes. No native streaming/GPU benefit or full package size has been
measured. The pinned OpenMap reference remains `6c2299f6`; its territory/core/band,
map grading and ocean design inform the experiments, but its game artwork was
not copied or executed.

A production bake still needs reviewed semantic frame/name/city exclusions,
complete geographic coverage, a continuous ocean/shore composition, source/build
binding, loader/filtering/seam tests, explicit texture budgets and an established
redistribution basis. OpenMap's MIT code/tools/data license excludes its Blizzard
and edited artwork and grants no automatic rights to our derivatives. Therefore
no derived continent pixels or new production architecture are packaged here.
The native Undercity correction ships only Lua plus references to installed game
files and an already-owned mask.

The expanded input also reveals a Booty Bay deep-terrain seam partly present in
adjacent native source tiles 204423/204463 (one-pixel edge mean absolute RGB
change approximately 17.55/9.80/4.08). This separates source-art mismatch from a
missing coverage bug; native filtering still needs inspection. No GPU seam fix
is claimed. Ironforge's separate plan is outside this request's exercised visible
views, and no unsupported city crop was inferred.

Suggested first native acceptance: Undercity/Tirisfal, zoom 12→24→48 and back,
with unexplored show/dim/hide, then close/reopen. Confirm the stray right-hand Y
and scroll disappear during takeover, terrain remains unchanged at deep zoom,
and no rectangular flash appears during cold loading. Capture `/tui mapdiag`
with precise view geometry enabled if anything differs. Also retain cave/marker,
UI scale, combat/taint and quest/navigation integration checks. No native client
was launched or controlled in this session.

## Final verification and delivery

`./tests/run.sh feature navigation --profile cloud --jobs 2` passes **104
modules / zero failures**, including **90 Python cases** (22 compositor/report,
20 client/transport, 27 collector, 14 composition, 7 underpaint), **310 Lua syntax
checks** plus runner scripts, and simulator smoke. **66.384750 s**, source
fingerprint unchanged. This cloud profile does not certify local/native release
acceptance. The new city-cover module passes **345 assertions**, covering
geometry/order, smooth alpha, source guards, rejected binds, immediate preference
updates, close/reopen and bounded reuse. An earlier frozen gate passed 104/0 in
65.473 s; the final rerun followed the offline repair-preservation fix, rather
than retrying an unchanged failure.

The old full-suite evidence is retained: **324 pass / 1 unrelated Welcome Back
failure** on `70bd271`, and original 322/1 baseline/untouched reproduction. No
Welcome Back code or assertions changed; this scoped checkpoint did not repeat
the unrelated full suite. Current main `84ca484` was reviewed and left separate.
The first checkpoint is `87e1223` (native correction/lifecycle); the subsequent
composition tools/docs checkpoint follows it on the existing draft PR #138.
No force-push, merge, deployment, release packaging or version bump occurred.

Private artifacts: `test-output/map-expanded-baseline/index.html`,
`test-output/map-city-cover-before/index.html`,
`test-output/map-city-cover-after/index.html`,
`test-output/map-composition-regional-v2/index.html`,
`test-output/map-composition-regional-v4/index.html`,
`test-output/map-composition-integrated-city/report.json`, and
`test-output/maplab-expanded-input/pixel-decode-validation.json`.

## Final regional polish: Redridge edge

The follow-up keeps the renderer, zoom transitions, biome colors and earlier
cave/city/NPC work. One reviewed Redridge **right** edge now blends more softly
into the actual regional painting underneath it. Only that edge changes: left,
top and bottom retain THIN. Source RGB, UVs, positions, draw order and opacity
policy are unchanged. All fifteen camera exports match baseline after replacing
the one mask identity; texture counts are identical.

This uses one original **mathematical** 256x256 BGRA mask (262,162 bytes), not
Blizzard-derived artwork. `python3 tools/make_map_feather_art.py --check` verifies
its deterministic bytes. The same generator reproduces existing THIN exactly
at its old parameter. Header/format match that already-shipped asset. No new
rendering layer, texture region, mask slot, updater or profiling engine is added.
It runs inside existing `map.art.update`; diagnostics expose `edgeFeather` and
`edgeFeatherReason` per zone. Exact build/art/canvas/carrier guards retain THIN
for unreviewed sources or missing owned artwork. Unexplored **hide** also retains
THIN because it can remove the neighbor painting; show/dim switch immediately.

The source study found **94.4–94.5% mean other-regional alpha** beneath the changed
band at 8.1/12; approximately 88% of changed pixels have alpha at least .85 and
none are parent-only. Broader left/top/right softening was rejected because it
widens blurry parent gaps. Riverglades-bottom softening was also rejected: its
changed band has no regional painting underneath. Badlands' own source edges
already have transparent native feathers. No global tint/brightness changes or
source-frame expansion was applied.

Fixed `regional-polish-v1` cameras cover central Eastern Kingdoms, the Badlands
boundary and the southern green/yellow boundary at **4, 8, 8.1, 12 and 24**:

```sh
python3 tools/maplab/run.py --client-bundle /private/part-01.zip \
  --client-bundle /private/part-02.zip --client-bundle /private/part-03.zip \
  --scenario-set regional-polish-v1 --output test-output/regional --strict
```

The mentioned new native screenshot was not attached. These are fixed regional
presets approximating the described area, not an exact recovered camera.
Primary directly inspected actual production before/after PNGs and a seam crop.
Central camera changed pixels: **891 at 4, 3,518 at 8, 3,600 at 8.1, 4,114 at 12,
zero at 24**. The improvement is deliberately small and boundary-local; terrain
and zone interiors retain their appearance. Native acceptance is still pending.

The original same-build cache supplied 50 additional detail/interior files for
these new cameras. Both build/product, all eight mandatory table hashes,
numeric sources/reveal/minimap data and 1,119 overlapping asset hashes match.
The private supplement retains **schema-1 provenance limitations** instead of
claiming fresh CKeys. A genuine legacy pixel-decoder regression (the original
collector did not repeat `fileId`) was reproduced and fixed; conflicting declared
IDs still fail. Source collections remain untouched and private.

Fourteen of fifteen before/after views have all visible artwork. The Badlands
24 preset is explicitly partial: **204569, 204611, 204651, 204691, 204731** are
uncollected terrain tiles, not confirmed missing client artwork. The original
1738-file cache alone has 55 absent inputs for these new cameras. Both complete
15-view runs therefore correctly exit nonzero under strict mode; before/after
with the supplement take **99.024943 / 84.619719 s**. Offline timings are not
native performance comparisons. Source counts and missing IDs remain visible.

The giant continent letters are baked into both parent paintings and extend
outside all available neighboring zone frames. Clean removal cannot be achieved
with this small edge fix; smudging, blank fills, exaggerated underpainting and
the rejected private background replacement were not enabled. The remaining
Riverglades/green-yellow gaps also expose parent art; wider fades would worsen
them. Two faint Redridge padding discrepancies do not explain these large seams,
and the production UV algorithm matches Forever's native provider, so no
unverified texture-layout override was introduced.

Private matching screenshots: `test-output/map-regional-after/comparisons.html`
(all three cameras/five zooms), `central-eastern-8.1-comparison.png`, and
`seam-closeup.png` in the same directory. The baseline is addon `6717e3a`.
Relevant native check: pan across Redridge's eastern frame toward Riverglades,
zoom 4→8→12→24 and toggle show/dim/hide. Confirm subtle smoothing without a new
blurred gap, unchanged roads/detail and the expected hide-mode fallback. Use
`/tui mapdiag` for unexpected results. No native client was controlled here.

Regional final gate: `./tests/run.sh feature navigation --profile cloud --jobs 2`
passes **106 modules / zero failures**, including **95 Python cases**, 311 Lua
syntax checks plus runner scripts and simulator smoke, in **70.204039 s**;
source fingerprint unchanged. Focused regional source/lifecycle tests pass 75
assertions, existing city-cover tests 345, and four deterministic owned-art tests
pass. The strict central 4/8/12/24 subset passes with zero missing assets in
22.443 s. Cloud/offline checks do not establish native acceptance. The prior
324-pass/one-unrelated-Welcome-Back full-suite evidence and original 322/1
baseline remain; no unrelated tests were changed or full suite repeated.
