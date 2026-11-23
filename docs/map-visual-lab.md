# Map Visual Test Lab

The first native feedback refinement is documented in
[cave, marker and composition results](seamless-map-client-feedback.md).
Use `--scenario-set feedback-v1` with a client bundle for its 62 deterministic
cameras, and repeat `--scene <id>` for focused renders. Real-input galleries
write exact-build `asset-request.json` files for the existing collector.
The compositor clips rotated texture bounds before decoding; offscreen missing
files do not count as missing visible pixels. Partial input bundles still remain
partial even if a selected viewport is complete.

The lab executes production Lua map selection in the existing simulator fixture, then composites the exported draw state with Pillow. Python does **not** select map layers, invent city placement, or reimplement the renderer's geographic calculations. PNGs, layer overlays, machine-readable findings, image differences and an HTML gallery are written to ignored `test-output/`.

## Current evidence and asset blocker

This workspace still has no running Forever client or mounted game installation.
However, the owner supplied private **1.60.1.71037 / wowf** collector input with
52 map records and **1,812 actual textures**, all present and hash-verified.
The lab has now rendered and directly inspected real artwork, including a
production fix/rerender cycle. [Real-art results and limitations](maplab-real-art-results.md)
record the before/after evidence. Native screenshots and client measurements
remain unavailable; `SIMLAB_ASSETS=0` still describes the separate UI simulator.

The real-artwork input blocker is resolved for the supplied regions. The
[maintained collector/update workflow](../tools/maplab/README.md) supplies private
artwork plus schema-checked client-table geometry to production Lua. The adapter
approximates native zone/phase lookup; real pixels do not certify those native
semantics. The original no-assets catalog remains explicitly synthetic and
cannot authorize extraction against its fake IDs.

The source collector successfully produced the supplied three-part input on
the owner's gaming PC; the cloud lab validated and decoded its BLP artwork.
Local extraction reuses `tools/navbake/casc.py`. Artwork remains private and
ignored, with no automatic transfer or release packaging. The newer incremental
collector additionally has fixture-tested update/recovery behavior; native
Windows GUI acceptance and future schema compatibility remain distinct checks.

## Run and inspect

Use the existing repository Lua/Python environment (Lua 5.1, its existing `bit` module and Pillow):

```sh
source /workspace/twichui-env/activate.sh
python3 tools/maplab/run.py --all
python3 -B tests/test_maplab.py
```

Open `test-output/maplab/index.html` and inspect its PNGs with a vision-capable image tool. The no-assets command deliberately creates a useful gallery with warnings and returns zero; this is **not** a real-artwork test pass. Use `--strict` to fail on missing textures or visual-state errors. The report's `realArtworkVerified`, `syntheticGeography`, `nativeClientConfirmed`, missing-assets list and provenance must accompany any claimed result. `realArtworkVerified` means the referenced local artwork was available and composited; it does not certify native rendering or artistic quality.

The current catalog contains 29 states spanning synthetic world/continent/zone/interior contexts, cave and WMO edge sequences, and different viewports. Do not relabel these as real geographic previews. Each selected texture has an ID, placement and order from production Lua. The lab handles viewport clipping, UV crop including out-of-range transparent crop, radians of counterclockwise center rotation, alpha, tint, nearest/bilinear sampling, multiple world-space masks and frame/draw-layer/sublayer/creation order. Root-sized color veils are exported too. Pixel dimensions preserve the actual production viewport aspect, including 420×900 and 1400×500; the export asserts this against its world rectangle. Native GPU filtering, texture streaming, color space, exact mask edge sampling and native `SetRotation` equivalence still need reference screenshots. Text, markers and the entire native UI are not composited.

For a deterministic inspect/fix/retest loop:

```sh
python3 tools/maplab/run.py --all --output test-output/maplab-before
# Inspect images and report.json; identify a source-supported defect, then change Lua.
python3 tools/maplab/run.py --all --baseline test-output/maplab-before --output test-output/maplab-after
```

Compare the affected scene, its `*-layers.png`, `*-difference.png` and structured state. Pixel changes quantify change, not improvement. Assert missing textures, invalid/non-finite geometry, unexpected fully transparent visible layers and abrupt transition alpha. The alpha check treats disappearing textures as zero only when their rectangles materially overlap both viewports; normal viewport culling is excluded. Its threshold belongs to the sequence and is not a universal artistic judgment. Persistent layer order or alignment correctness requires an expected-state contract or actual reference, rather than an invented automatic pass.

### Observed production defect and retest

The recorded cave/WMO edge sequence exposed detail at full opacity immediately before it disappeared while still substantially visible. The parent agent inspected the generated before images and correlated this with production center-based interior activation. The production fix adds an outer-band fade and is tested separately in Lua at finer movement increments.

Using the saved before export with only sequence identifiers/thresholds copied from the after export, the lab detected **14 abrupt alpha steps before and zero after**. The original geometry, texture selections and alpha values in the before export were preserved. Before and after galleries continue to report the same **90 unique missing artwork keys** (1,327 and 1,330 selected missing-texture occurrences respectively); these errors were not suppressed to obtain a green result. This demonstrates a production visual-state correction over synthetic artwork, not native geographic visual acceptance.

Recorded output locations were `test-output/maplab-before/index.html` and `test-output/maplab-after/index.html`; cave edge-3/edge-4 and WMO edge images are useful inspection points. Gallery generation took approximately 9.18 seconds before and 10.46 seconds after including image comparisons on this cloud CPU. Another `--all` run including Lua export took 10.37 seconds, about 1.8 seconds of which was Lua export. These are offline whole-gallery costs, **not client frame times**. The initial sixteen focused Python contract/pixel tests ran in approximately 0.05 seconds; final review expands this to eighteen, adding cumulative source-memory and draw-layer/color-veil checks. Timing fields naturally vary; render-state hashes and pixel results are deterministic for fixed inputs/toolchain.

## Import an in-game diagnostic

Capture a Detailed Map Diagnostics report with precise view/cursor geometry enabled. Player position is not needed. Import the JSON, or save each numbered copy chunk as a separate UTF-8 file in order:

```sh
python3 tools/maplab/run.py --diagnostic report.json --output test-output/maplab-issue
python3 tools/maplab/run.py --diagnostic-piece part-1.txt --diagnostic-piece part-2.txt --output test-output/maplab-issue
```

Chunks must have intact report/part checksums, matching identities and correct order. Imports are bounded JSON, never executable Lua. The exported `diagnostic-scenario.json` retains the map ID, view/center, viewport and bounded allowlisted input events. Its replay field explicitly rejects complete native replay without captured native map-API bounds. Replaying a real map ID against synthetic fixture geometry would manufacture evidence.

The partial image uses **production-captured terrain/interior texture rectangles** directly. It prefers `effectiveAlpha` where captured, otherwise texture-local `alpha`. Current reports can omit parent-frame fades, so the generated replay explicitly warns that the preview may be too opaque; uncaptured tint/masks also limit appearance. Synthetic report provenance is preserved and cannot authorize CASC extraction. Only retained rectangles are rendered. Base paintings, complete masks, omitted pictures and uncaptured map-API state are unavailable. A partial snapshot is useful for alignment and missing texture investigation, but does not recreate an entire native map or replay its timeline.

### First actual-artwork proof when local assets exist

Prefer the [source-only collector kit and `--client-bundle` workflow](maplab-real-artwork.md)
when the gaming PC is separate from this workspace. It supplies base paintings,
selected-region candidates and table-derived API inputs in one collection,
without in-game reports or copying the full installation. The diagnostic path
below remains useful for reproducing a particular captured detail view.

1. Select a real Forever install containing `.build.info`, `Data/config` and `Data/data`. Probe without extracting:
   `python3 tools/maplab/run.py --probe-assets --wow /local/Forever`.
2. Capture a real Detailed Map Diagnostics report at Booty Bay, Undercity and a zone border with precise geometry. Never extract synthetic fixture IDs.
3. Run `python3 tools/maplab/run.py --diagnostic report.json --wow /local/Forever --output test-output/maplab-real --strict`.
4. The read-only CASC extractor writes only referenced local textures to `test-output/maplab-real/local-assets/`, with source/output SHA-256, file-data ID, client build, product and provenance in `manifest.json`. Missing, unavailable or encrypted files remain explicit failures. It uses the existing `wow_classic_beta` product default; a different installed product requires deliberate reader configuration rather than guessing.
5. Inspect actual output and compare an owner-provided native screenshot of the same view. Resolve sampling, mask, crop and rotation differences before treating it as faithful. This diagnostic path is selected-detail-only; the collector path also supplies base paintings and client-table geometry.

An existing local cache may be passed as `--assets path/to/manifest.json`. Schema 1 requires an `assets` object keyed by file ID or symbolic asset key. Each record requires `file` relative to the manifest directory, exact `sha256` and nonempty `provenance`; local-client-artwork also requires a matching numeric `fileId` and should record clientBuild/sourceSha256. Paths cannot escape the cache. Addon-owned `!!!TwichUI/media/textures/map-*.tga` masks resolve directly under the repository without copying assets.

No license to redistribute Blizzard or OpenMap-edited artwork is inferred from possession. Keep caches, generated images and derivatives local and ignored. Existing addon packaging excludes tools/tests/docs/test-output; this work does not change release packaging.

## Render-state contract

`tools/maplab/export.lua` captures real fixture texture objects after production `MapExplore`, detail and interior rendering. Input schema 1 is:

```json
{"schema":1,"provenance":{"source":"production Lua fixture","synthetic":true},
 "scenes":[{"id":"safe-name","label":"Synthetic example","width":900,"height":600,
 "view":{"u0":0,"v0":0,"u1":10,"v1":10},
 "textures":[{"fileId":123,"u0":0,"v0":0,"u1":10,"v1":10,
 "texCoord":[0,1,0,1],"rotation":0,"alpha":1,"level":6,"sublayer":0,
 "order":1,"filter":"linear","tint":[1,1,1],"shown":true,
 "masks":[]}],"metadata":{"sequence":"example","maxAlphaStep":0.35}}]}
```

All rectangles and rotation use exported world coordinates/radians; widths/heights are output pixels, alpha/tint are unit intervals. `bounds:[u0,v0,u1,v1]` aliases rectangle fields. `asset` aliases fileId for symbolic keys; `mask` aliases one entry in `masks`. Each mask can have independent world bounds and UV crop. Multiple masks multiply. There is no geographic selection in Python. Input JSON is capped at 8 MiB, 96 scenes, 2,048 textures per scene, 4,194,304 pixels per scene and 96 million pixels per gallery. Retained decoded sources also have a separate 32-million-pixel limit (128 MB RGBA pixel data, excluding object/work-buffer overhead); exceeding it fails explicitly. Filename checks and path containment bound output paths. Timings and findings live in `report.json`, alongside exact source state and asset hashes. Difference PNGs use opaque display alpha while their metrics still include original alpha changes.

## Build-time hybrid evaluation

Recommendation: preserve the production runtime architecture now. A **conditional hybrid** is the best next experiment: keep Lua coordinates/layer selection, native dynamic overlays/markers and current safe fallback; optionally add immutable, client-build-specific intermediate LOD assets and reviewed masks generated offline. The supplied private artwork now supports real-art rendering and a first downsampling proof; native placement/format acceptance and redistribution rights remain gates. Do not ship or activate the prototype assets.

| Approach | Expected benefit | Storage/runtime cost | Compatibility and rights gate |
| --- | --- | --- | --- |
| Current painting plus native minimap tiles | Uses installed assets and existing runtime logic; no derivative art shipping | Close detail has bounded tile count, but no true intermediate-resolution source | Existing client IDs/geometry still need native validation |
| Entirely preprocessed replacement | Could unify seams/coast treatment when source and masks are correct | Largest build/cache surface; requires layers/locale/build variants, streaming and fallback | Unsafe to assume redistribution rights or compatibility; not recommended now |
| Optional hybrid LOD plus masks | Could fill intermediate zoom coverage and improve territory/city/ocean composition | Additional immutable assets, decode/bind budget and manifest validation; retain bounded existing layers | Requires lawful source, reviewed semantic masks, native alignment and explicit fail-safe to current runtime |

`preprocess.py` verifies reusable local building blocks, using only an owned mathematical fixture by default:

```sh
python3 tools/maplab/preprocess.py --output test-output/maplab-preprocess
# Optional private local image; this grants no redistribution rights:
python3 tools/maplab/preprocess.py --source /local/art.png --output test-output/maplab-local-preprocess
```

The pipeline produces Lanczos LODs, source-alpha/feathered-alpha masks and exact replicated edge gutters. It records pixel hashes, dimensions, PNG bytes and processing cost, with `runtimeEnabled:false`. On the owned 256×256 fixture:

| Output | PNG bytes | RGBA pixel-byte estimate | Measured processing seconds |
| --- | ---: | ---: | ---: |
| Native 256 | 17,803 | 262,144 | 0.00116 |
| LOD 64 | 7,578 | 16,384 | 0.00147 |
| LOD 16 | 723 | 1,024 | 0.00076 |
| Source alpha (white RGBA) | 1,922 | 262,144 | 0.00015 |
| Feathered alpha (white RGBA) | 7,935 | 262,144 | 0.00097 |
| LOD 64 with 1-pixel gutter (66×66) | 7,690 | 17,424 | 0.00219 |

LOD64 has 16 times fewer pixels, LOD16 256 times fewer. Keeping both adds 8,301 PNG bytes (46.6%) to this synthetic source, while its one-pixel gutter adds 6.35% pixels. These numbers validate prototype storage arithmetic and processing; they predict neither real-terrain compression/visual quality nor client GPU memory. Alpha mask output really carries alpha rather than opaque grayscale, and gutter edge values are pixel-tested.

After the first actual-art inspect/fix/retest loop, the same helper processed
private Forever tile 204423 (512×512): native PNG 168,477 bytes; LOD64 6,421;
LOD16 628; guttered LOD64 (66×66) 6,489. The two LODs add 7,049 PNG bytes
(approximately 4.2% of this native PNG), with 64× and 1,024× fewer RGBA pixels
than the source. This validates actual BLP decoding and offline downsampling,
not geographic atlas quality, native GPU cost or shipped-format compatibility.
Its source alpha is uniformly 255, so its feathered source-alpha output cannot
provide a semantic coastline or city cut. See [the real-art evidence](maplab-real-art-results.md).

Source alpha is **not** a territory, coastline, land, ocean or city-cut classifier. A generic RGB threshold cannot establish the correct geographic meaning of parchment/ocean or underground boundaries. Reviewed native artwork plus territory/city geometry and client placement fixtures are required. City cuts also need correct floor/layer and surface/interior transition contracts. Ocean/background synthesis may use reviewed numeric masks/geometry, but no such authoritative source is available here. Thus semantic-mask quality is explicitly unverified.

A future production experiment should gate every atlas/mask by client build, map identity, coordinate rectangle, resolution, locale where applicable, pixel/source hashes and provenance. Reject stale/missing assets and use the existing runtime path. Keep LOD crossfades continuous and explicit texture/decoded-pixel budgets; validate atlas gutters and edge UVs in the lab and client. Add no release assets until source rights and the chosen client formats are verified. Offline PNG support alone does not prove that Forever accepts a proposed shipped texture format. The pinned OpenMap reference (`6c2299f6e1f9bdce1bbd92145f84a05b0c6c05a7`) informs extraction, masks, atlas/LOD and cave rotation study; its processed Blizzard art is not copied or executed.

### Concrete reference differences and production experiment order

The same pinned `tools/map-preview/minimaplod.py` groups tiles into 256-pixel
pieces at 64 and 16 pixels per original tile. Counting its numeric Forever
tile coordinates independently gives 60+76 fine pieces and 6+10 coarse pieces:
**152 atlas pieces**, approximately **38 MiB of uncompressed RGBA pixel data**
before gutters/masks/format overhead. This is a storage estimate, not a measured
addon download size or simultaneous resident GPU cost. Native tiles already
exist in the client and add no bundled artwork bytes today. The two prototypes
demonstrate downsampling and edge gutters, but do not generate those geographic
atlases without lawful client inputs.

Prioritize experiments as follows:

1. Intermediate LOD: solve the current tile-budget fade back to painting. Keep
   one coarse and one fine level beneath native detail, with weights summing to
   the intended detail mix and explicit combined texture limits. This is the
   strongest likely fidelity/runtime benefit, pending real-art validation.
2. Territory/core/land masks: pinned `map-grade/grade.py` composites explored
   pieces, measures a land-border band, and derives palette multipliers plus
   soft band/core/territory masks. `map-preview/render.py` widens those using
   continent art. TwichUI's rectangular feathers cannot infer that geography;
   our prototype preserves source alpha but does not claim semantic masks.
3. City cutouts: `map-preview/banners.py` uses reviewed, city-specific art
   outlines and banner cuts. Generic rectangular cropping is insufficient,
   particularly for Undercity/Ironforge surface versus interior. Validate those
   layer contracts first; do not import the reference's edited pixels.
4. Ocean/coast: `map-preview/sea.py` samples Blizzard continent parchment and
   coastal strokes, tiles/crossfades them, and uses coastal/land exclusion masks.
   These derivatives have the same rights gate as terrain. Actual native coastal
   tiles were inspected, but these reference ocean derivatives were neither
   generated nor visually validated here.

These scripts were inspected as source, not executed or imported into TwichUI.
No newer OpenMap revision was substituted. The supplied private cache now
supports the first real-art rendering loop; a bounded geographic intermediate
atlas remains the next experiment. Shipping a cache is a separate rights
and compatibility decision. The recommendation remains conditional rather
than a claim of proven OpenMap-level quality or a production architecture change.

## Optional native reference workflow

When the owner has a compatible client and graphical session, manually reproduce a fixed view, capture a report and take a normal screenshot. Associate it with the offline gallery using `--native-screenshot /local/screenshot.png`. This copies only decoded pixels (no EXIF), hashes them and labels them owner-provided. Screenshots can themselves contain private UI, so review before sharing. The tool does not launch or control gameplay, read client memory, inject code, bypass anti-cheat, capture an unavailable client or claim native reproduction.

AI assistants should inspect the gallery images, then use production texture IDs/geometry and the diagnostic timeline to find the responsible Lua module. Read report limitations first. If artwork is missing, resolve that input or continue with geometry/transition assertions; do not infer texture quality from checkerboards. Record the inspected image paths and before/after evidence. Native acceptance remains required for actual terrain appearance, city/cave alignment, quest/marker integrations, UI-scale behavior and client performance.

Source-aware composition experiments, current artwork gaps and the corrected
collector handoff are documented in [seamless map composition](seamless-map-composition.md).

The corrected expanded input, 71-camera composition profile, native city repair
and private continent experiments are documented in
[expanded-artwork results](seamless-map-expanded-artwork.md).

For the final bounded regional pass, `--scenario-set regional-polish-v1` exports
15 preset views at zoom 4/8/8.1/12/24. See the final regional-polish section of
[expanded-artwork results](seamless-map-expanded-artwork.md) for actual comparisons,
missing-input limits and the owned mathematical mask generator.
