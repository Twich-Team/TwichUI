# Seamless map composition: evidence and next input

This checkpoint fixes the artwork handoff and adds a private, source-aware
composition experiment. **Production composition is still unfinished.** The
experiment improves some shore/river joins, but does not remove continent titles,
replace the coarse ocean painting, supply missing Kalimdor regions, or establish
OpenMap-level fidelity. Cave, NPC, detail budgets and native fallback are preserved.

## Why the latest collection did not unblock the wider scenes

The three newly supplied ZIPs match the original ZIPs byte for byte. They contain
Forever **1.60.1.71037**, product **wowf**, legacy schema 1: 52 map records and
1,812 textures, with zero missing assets *within that original candidate set*.
They have no targeted-request identity, native highlight references or map links.
That is a valid original dataset, not the expanded feedback dataset.

The previous collector required an explicit `--asset-request` even when the kit
contained one. A double-click could consequently collect the default catalog.
Collector **2.2.0** now automatically selects the fixed kit-root request, prints
its build/product/count/SHA, uses a separate feedback cache and names its output
`TwichUI-map-art-feedback-<request SHA prefix>[-NN].zip`. An explicit request wins;
`--default-catalog` deliberately opts out. Invalid or incompatible bundled requests
fail closed. No current-directory probing or guessed asset IDs is involved.

The corrected source-only composition kit requests **1,693 direct production-Lua
IDs**, plus deduplicated highlight file IDs read from the reviewed client tables.
Final union counts are determined on the gaming PC, under 2,048 files / 128 MiB.
Unresolved atlas-only references and unavailable optional links remain explicit.

Smallest owner action: extract the corrected kit outside the game, double-click
`Collect-Map-Art.cmd`, choose `_forever_`, then return **all printed feedback ZIPs**.
The normal CLI and troubleshooting remain in [the collector README](../tools/maplab/README.md).
No installed game files are changed. Windows launcher acceptance still needs the
owner; Python selection/read-only/publication behavior has fixture coverage.

For a reproducible developer handoff, generate requests through the existing lab:

```sh
python3 tools/maplab/run.py --client-bundle /private/part-01.zip \
  --client-bundle /private/part-02.zip --client-bundle /private/part-03.zip \
  --scenario-set feedback-v1 --request-native-highlights \
  --output test-output/composition-inputs --strict
python3 tools/maplab/collect.py --make-kit test-output/map-composition-kit.zip \
  --asset-request test-output/composition-inputs/asset-request.json
```

A partial gallery exits nonzero under `--strict`; its exact-build request still
identifies absent inputs. Do not hand-edit IDs, hashes or builds to bypass checks.
The `--request-native-highlights` flag is opt-in and requires collector 2.2+.
Existing bundles remain importable without invented new provenance.

## What the private experiment actually does

`tools/maplab/composition.py` extends the existing compositor; it is not another
map selector or runtime renderer. Production Lua supplies selected zone IDs,
world rectangles, layer order, native edge masks and camera positions. Native
zone-overlay alpha supplies *painted support*, not an authoritative land mask.
Distance fields form territory/core/band masks, with reviewed approximate
name/frame exclusions and shared overlap claims. Only boundary chroma is graded;
per-pixel luminance and protected core RGB are retained. Five calibrated source
canvases have pixel-hash pins, so changed artwork cannot silently reuse the
exclusions. All processing and resulting Blizzard-derived pixels stay private.

Offline dependencies are Pillow, NumPy and SciPy. The gaming-PC collector remains
standard-library-only; the addon gains no dependencies or runtime work.

```sh
python3 tools/maplab/composition.py \
  --client-input /private/client.json --assets /private/assets/manifest.json \
  --state test-output/map-feedback-final/current-source-state.json \
  --scene elwynn-westfall-duskwood-12 --scene tirisfal-6 \
  --scene booty-bay-12 --scene undercity-24 \
  --output test-output/map-composition-review
```

Supply an existing production export whose eight renderer-source hashes match
the intended baseline. No precise native replay is claimed by the rectangle-based
API adapter. Up to twelve matching cameras produce before/after/comparison PNGs,
ownership masks, `report.json` and `index.html`. Uncalibrated views are unchanged
controls. Missing textures retain obvious placeholders and partial status.

The primary agent directly inspected the matching real-art comparison images for
Eastern Kingdoms, Kalimdor, Elwynn/Westfall/Duskwood, Booty Bay and Tirisfal/Undercity.
The five calibrated zones are Elwynn, Westfall, Duskwood, Stranglethorn and Tirisfal.
Results from the frozen production baseline (`8b74f7a` addon source):

| Camera | Changed pixels | Missing visible native IDs | Assessment |
| --- | ---: | ---: | --- |
| Eastern Kingdoms 2.4 | 0% | 0 | Unchanged overview control |
| Eastern Kingdoms 4.1 | 5.8616% | 45 | Partial; lettering and geographic gaps persist |
| Kalimdor 2.4 | 0% | 0 | Unchanged overview control |
| Kalimdor 4.1 | 0% | 188 | Unchanged, incomplete control; no fidelity acceptance |
| Elwynn/Westfall/Duskwood 4.1 | 21.4727% | 3 | Partial; parent title remains |
| Elwynn/Westfall/Duskwood 12 | 35.7494% | 0 | Better shore/river context; regional seams remain |
| Tirisfal 6 / 12 | 12.4763% / 32.5221% | 0 / 0 | Better shore context; coarse parent ocean persists |
| Booty Bay 12 / 24 | 39.4194% / 66.0671% | 0 / 0 | Some coastline context recovered; coarse ocean remains |
| Undercity 24 / 48 | 39.5429% / 0% | 0 / 0 | Surface context changes; native banner remnants persist; deep view unchanged |

All twelve outputs have zero fully transparent pixels. This is compositing
coverage, not proof of correct geography. Border chroma distance to the fixed
reviewed palette decreases approximately **28–54%**, with **zero protected core
RGB pixels changed**. Neither changed-pixel fraction nor that palette metric is
an artistic-quality score. The 12-camera run took **53.256613 seconds** in this
development environment; there is no corresponding native CPU/GPU measurement.
A separate source-complete regional 48 view also remained pixel-identical.

Repeated title-removal experiments were directly inspected and **rejected**:
broad masks create blank patches; narrow ink masks leave smudges/bevel remnants.
They are off by default. `--rejected-title-study` reproduces the failed approach
for evidence only, labeled rejected in its report. No inpainted geography or
repaired parent textures are packaged. The native title is baked into the same
opaque pixels as land/coast information, so simply fading rectangles is unsound.

## OpenMap comparison and hybrid recommendation

Reference remains OpenMap commit
`6c2299f6e1f9bdce1bbd92145f84a05b0c6c05a7`. Its `tools/map-grade/grade.py`
creates territory/core/band fields; `tools/map-preview/render.py` combines them
with land ownership and city/banner exclusions; `sea.py` derives finer open-sea
paper/hatching from source artwork. Those tools were read, not executed, and no
OpenMap artwork was copied. Our prototype validates the usefulness of source
support, protected cores and boundary treatment; it does not duplicate its
complete land/ocean or LOD system. Source alpha is deliberately not relabeled as
semantic land. A shared grade should preserve biome luminance rather than flatten
Westfall and Duskwood to the same brightness.

| Approach | Verified benefit / cost | Compatibility / rights gate |
| --- | --- | --- |
| Existing native runtime art | No additional shipped game pixels; current budgets and fallback survive | Parent ink and coarse intermediate art remain |
| Native highlight masks at runtime | Potential geographic cuts without distributing derived pixels; alpha and placement are **not yet verified** | Need actual highlight payloads, native geometry and bounded copies; RGB glow/opaque alpha must be rejected |
| Private precomputed territory/core/band masks and grading | Working source-aware image generation, inspected local context improvements; offline 53.26 s for this 12-view study | Derived mask/art redistribution is not established; requires exact-source identity and native visual acceptance |
| Optional precomputed LOD/color tiles | Could reduce overlapping runtime passes and improve intermediate resolution; no native speedup demonstrated | Higher package/storage/streaming cost, source completeness, seams/filtering, rights and native loader validation |
| City cuts / ocean background | Needed to remove remaining banner remnants and coarse ocean/title context | Precise source-aware cuts and reviewed coast/open-sea sources still missing; rectangular fills are rejected |

A private format/storage example used the five actual **1,002×668** graded zone
canvases. Splitting levels 1, 1/2 and 1/4 into padded 256×256 RGBA TGA tiles produced
**85 tiles / 22,285,980 bytes**. Fifteen 128×128 RGBA TGA territory/core/band masks
added **983,700 bytes**. Generation took **0.476229 s**. This is a storage example,
not a baked world LOD, full package estimate or client benchmark. PNG is used for
offline previews only. Power-of-two uncompressed 32-bit TGA follows the existing
owned feather-mask asset family, but newly generated textures still need native
loader/filtering/seam testing. No new format, mip-chain or GPU claim is inferred
from successful Pillow round trips; compressed-format savings are unmeasured.

**Recommendation:** retain native runtime fallback and existing dynamic terrain,
city/interior/marker layers. First verify native geographic highlight candidates;
then evaluate private precomputed territory/core/band data, an owned/licensed
fine ocean treatment, and one bounded intermediate LOD. Keep camera selection,
coordinates, transition policy and explicit budgets in production Lua. Bind any
optional bake to build, source hashes and settings; reject mismatches atomically.
Do not switch architecture or package derived pixels at this checkpoint.
OpenMap's MIT license explicitly excludes generated Blizzard and edited artwork;
it grants no rights to redistribute our new derivatives either. Numeric
OpenMap data licensing is not blanket permission to distribute rasterized game
silhouettes. Obtain actual permission or a separately lawful asset strategy first.

Native highlight investigation must validate a filled geographic **alpha**
silhouette, not just an RGB glow. Forever's MapHighlightDataProvider uses ADD
blending, and native mask UV changes are unsupported. For a native cropped
highlight rectangle `(x,y,w,h)` with UV extents `(pX,pY)`, an unmodified full-UV
mask would occupy `(x,y,w/pX,h/pY)` with output clipped to the intended rectangle.
Require finite positive values, correct child identity and transparent/clipped
padding. Raw UiMapLink rectangles are not verified native highlight placement.
Use at most two masks per base copy and a hard copy budget; unavailable APIs,
atlas resolution, wrong alpha or geometry must retain the current native art.

## Verification and remaining acceptance

Final command: `./tests/run.sh feature navigation --profile cloud --jobs 2`:
**103 modules passed / zero failures**, including **85 Python cases** (22
compositor/report, 20 client/transport, 27 collector, 9 composition, 7 underpaint),
309 Lua syntax checks plus runner scripts, and simulator smoke. Total
**67.614833 s**, source fingerprint unchanged. The cloud profile does not certify
a local release or native client. The two Lua-dependent client cases skipped in
an earlier unactivated Python-only check passed under this activated gate.
The previous feature baseline was 102 modules / zero failures, 66.358 s;
different wall times are not a native performance comparison. No full-suite
rerun was warranted by these offline-only changes. Its preserved result remains
324 pass / 1 unrelated Welcome Back failure, including the earlier 322/1 baseline.

The 2.2 source-only kit was separately extracted and executed with Python `-S`:
15 members, 101,164 bytes, bundled request selected automatically, no art payloads
or site packages. SHA-256:
`d580a42ab42f451df5bb4e94f8b12aad9cd9d0b59c8fd537a052ad5aab56d99a`.

Collector/client/compositor fixtures cover request precedence, strict optional
highlight settings, derived-ID deduplication, limits, corrupt/missing metadata,
legacy imports and source-only kits. Composition fixtures cover bounded masks,
exclusions, overlap ownership, exact geometry, core/luminance preservation,
source calibration and unchanged controls. No native game was launched.

Ignored private artifacts: `test-output/map-composition-review/index.html`,
`report.json`, `format-study.json`, source masks and matching comparison PNGs;
`test-output/TwichUI-map-composition-71037-v22.zip` is source-only. The old and new
ZIP input SHA values and metadata prove the unchanged-input limitation. No raw
or generated Blizzard pixels enter Git or addon packages.

After the genuinely expanded collection arrives, inspect actual highlight alpha,
finish complete continent/neighbor coverage, rerun these identical cameras and
reject city/shore/title regressions. Player tests should then cover native map
highlight placement, rapid zoom and city floor transitions, different UI scales,
cold/open/reopen streaming and mask cost. The last unrelated Welcome Back full
suite failure remains documented in the audit/client-feedback evidence; no
unrelated tests were changed.
