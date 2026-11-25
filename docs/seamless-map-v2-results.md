# Seamless Map V2 results

The branch preserves the original overhaul and adds a player-facing support
tool, a production-state visual lab, and verified interior corrections. It does
not establish OpenMap-level native appearance. No compatible client artwork or
game executable is available in this workspace.

## Player workflow

Open the world map, type **`/tui mapdiag`**, and choose **Capture Snapshot**.
For transitions, choose **Start Recording**, reproduce the problem, reopen the
window if needed, **Mark Issue**, then **Stop & Prepare Report**. Choose
**Copy for AI**, press **Ctrl+C**, and paste. **Select Again** reuses the text.
**Detailed Report** offers numbered Next/Previous chunks. Enable precise
view/cursor geometry before capture for a future partial offline reconstruction.
No upload, chat send, player-position query or clipboard API call occurs.

Recordings default to 90 seconds, capped at 180, with 256 events, 24 snapshots,
32 findings and eight preserved anomaly contexts. JSON is deterministic,
bounded to 96 KiB, with omission counters; quick reports stay below 12 KiB.
Missing APIs are explicit. The existing performance engine is reused, including
ownership checks if another performance capture replaces ours. See
[workflow/schema/AI guide](map-diagnostics.md) and the
[synthetic schema example](examples/map-diagnostics.json).

## Implemented visual and lifecycle corrections

- Cave and WMO detail fades through the outer 15% of its selected rectangle
  before center-based selection ends. A fine-step Lua regression prevents the
  former fully opaque disappearance. Centered floor controls remain tested.
- Interior selection releases pictures outside the budget before acquiring
  replacements. A demonstrated 300-picture pan regression now stays within
  256 textures per set, including transient allocation. Current real numeric
  records still peak at 217. Native rejected binds are reported and not retried
  on every view update; the painted fallback remains available.
- Diagnostics expose actual selected zone/city layers, terrain/interior levels,
  rejected textures and interior-budget evidence. Rendering calculations are
  not copied into the support tool.
- Visual inspection of simulator widgets caught a clipped report field. Its
  anchor, height, alignment and cursor position now make the selected report
  readable from its header.

No asset-dependent tint, brightness, coastline, city alignment or geographic
mask change is claimed. The existing detail fade/tint remains until real-art
evidence can support tuning. Fargodeep and the three edited references remain
precisely documented in [the audit](seamless-map-audit.md).

## Visual lab and inspect/fix/retest evidence

```sh
source /workspace/twichui-env/activate.sh
python3 tools/maplab/run.py --all
python3 tools/maplab/preprocess.py --output test-output/maplab-preprocess
```

Production Lua exports actual selected texture placements, masks, color veils,
UV crops, rotation, alpha and draw order. The Python compositor creates PNGs,
overlays, state JSON and an HTML gallery; it does not select geography. Viewport
pixels preserve the production aspect. Decoded source images have a separate
32-million-pixel retention cap. Difference images remain visibly opaque while
their metrics include original alpha differences.

The initial cave-edge sequence was inspected directly at
`test-output/maplab-before/cave-101-edge-{1,3,4}.png`, then compared with the
after images. Fourteen abrupt-alpha findings became zero with the runtime fade
fix. Both initial galleries retain 90 missing-art keys; none was hidden to
obtain a passing visual result. Final review also inspected the correctly shaped
tall viewport and a diagnostic-import PNG. This demonstrates a production-state
defect and correction with placeholder art, not native artwork acceptance.

Artifacts remain local and ignored:

- `test-output/maplab/index.html`: final 29-scene gallery.
- `test-output/maplab-before/index.html` and `maplab-after/index.html`:
  initial before/after evidence, with saved production state and differences.
- `test-output/maplab-diagnostic-import/index.html`: one production-captured
  selected-detail fixture imported through diagnostics; six missing keys remain.
- `test-output/maplab-preprocess/` and `maplab-preprocess-owned/`: measured
  mathematical fixture and actual TwichUI-owned mask preprocessing.

Diagnostic import is partial: it preserves selected rectangles and input events,
but cannot reconstruct native paintings, omitted pictures, uncaptured tint/masks
or unknown parent alpha. Generated replay limitations say so. Synthetic
provenance survives import and prevents accidental CASC extraction of fake IDs.
Real-art extraction remains unverified without `.build.info`, local CASC files
and verified native API geometry. No game assets or generated screenshots enter
the addon release. [Detailed lab instructions and hybrid evaluation](map-visual-lab.md).

## Verification

| Command | Result |
|---|---|
| `./tests/run.sh unit --profile cloud --jobs 2` | At frozen `70bd271`: **324 passed, 1 failed**, 668.519 s; source unchanged throughout |
| `./tests/run.sh feature navigation --profile cloud --jobs 2` | Final production/artifact changes: **97 passed, 0 failed**, syntax plus simulator smoke, 72.065 s |
| `python3 -B tests/test_maplab.py` | Final **18 passed**, 0.062 s |
| `bash tools/simlab/run.sh mapdiag` | Final **17 handler/geometry checks passed**, structural PNG produced |
| `python3 tools/maplab/run.py --all` | Final **29 scenes**, 90 missing keys explicitly reported; 17.453 s while simulator ran concurrently |
| `python3 tools/maplab/run.py --diagnostic /tmp/map-v2-selected-diagnostic.json --output test-output/maplab-diagnostic-import` | Synthetic production-capture import: **1 scene**, six missing keys, 0.190 s |

The optional synthetic capture was generated by running
`test_map_diagnostics.lua` with Lua global `MAPLAB_DIAGNOSTIC_FILE` set to that
temporary path; the fixture explicitly enables detail and settles an instant
view before capture. It is not a native report. Unit tests also verify chunks,
checksums, deterministic import and omission of withheld geometry. The strict
missing-art gallery returns failure; the no-assets default remains useful with
visible warnings. A synthetic diagnostic CASC request was independently rejected
before any asset read.

The full-suite failure is unchanged: `test_welcome_back.lua:84`, “two days back
is a date.” Original evidence remains **322 passed, 1 failed** at `a81b9b8`,
including reproduction against untouched `1a3d9eb` dependencies. No Welcome Back
code/test was changed. After the full run, the final artifact/snapshot refinements
received the affected feature gate and focused checks above; the full offline
suite was not rerun for those bounded changes. The default full simulator
catalog, native acceptance and release certification were not run or claimed.

## Performance and build-time recommendation

Three matched 4,000-operation courses compared `f756c1a` with the V2 runtime:

| Measurement | Before | After |
|---|---:|---:|
| CPU seconds, three runs | 1.6989 / 1.8831 / 1.6964 | 1.8096 / 1.7631 / 1.7358 |
| Median CPU seconds | 1.6989 | 1.7631 |
| New warmed terrain textures | 0 | 0 |
| Peak active terrain textures | 24 | 24 |

The median is approximately 3.8% slower, not a speedup. These are offline Lua
fixture costs, not GPU/client frame times. Cold opening, real streaming bursts,
deep city transitions and memory retained by native texture caches still require
client measurements. Isolated initial gallery runs were approximately 9–10.5 s;
concurrent simulator rendering increased the final wall time above.

Keep production runtime rendering. The best next experiment is a conditional
hybrid: native paintings/dynamic markers and close-detail fallback, plus optional
immutable intermediate LODs and reviewed masks built offline. The owned-fixture
pipeline actually generates 64/16-pixel LODs, alpha masks and gutters, recording
hashes, bytes and processing time. It does not generate semantic geographic masks.

The pinned OpenMap numeric tile layout implies 152 256-pixel atlas pieces, about
38 MiB raw RGBA before masks/gutters. Current native artwork adds no bundled
artwork bytes. Treat additional texture binds, decode/memory budgets, build and
locale identity, client formats and stale-asset fallback as experiment gates.
Prefer keeping any future combined terrain LOD allocation within the existing
80-texture terrain ceiling. This is a proposed budget, not an activated layer.

Real-art quality, encoded package size and GPU cost remain unmeasured. OpenMap's
MIT code license excludes Blizzard artwork/edits; possession of client files
does not establish redistribution rights. Keep generated caches private until
rights are resolved. Territory/core masks, city cuts and ocean/coast derivatives
require reviewed source artwork and geometry. No architecture switch, release
asset addition, metadata change, merge or deployment was performed.

## Checkpoints and first native test

- `9e192f1`: diagnostics foundation, committed/pushed after focused checks.
- `756cc9e`: visual lab and verified cave/pool corrections.
- `70bd271`: simulator support workflow and hybrid investigation.
- `327be11`: final source-memory/aspect/difference/replay hardening and selected
  zone context. All four checkpoints were pushed to the existing feature branch.

PR #138 remains the existing draft. New main `364c4c2` was reviewed for overlap;
no unnecessary rebase or history rewrite was performed.

First native test: **Undercity**, from surface/continent view into its interior,
then rapid wheel reversal and a pan across the city boundary. Record with precise
view geometry, mark the defect if one appears, and copy the report. This tests
high-risk underground layering, loading, transitions and navigation together.
Then try a known painted cave boundary to judge the new fade. Native Ctrl+C,
actual artwork alignment, third-party markers and combat/taint remain owner
acceptance checks.
