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
