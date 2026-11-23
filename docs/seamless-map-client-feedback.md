# First native feedback: cave, marker and composition refinement

The owner's three native screenshots and two quick schema-1 reports are evidence
of client behavior. The camera coordinates were withheld, so the lab cameras
approximate their locations and zooms; they are not exact native replays.
The work continues PR #138 and preserves its original audit/baseline evidence.

## Established causes and corrections

| Evidence | Established source behavior | Correction / limit |
| --- | --- | --- |
| Jasperlode is faint at close zoom; Skull Rock can appear abruptly | Cave strength multiplied zoom fade by a fixed outer-15%-of-cave center fade. Cursor anchoring can leave the camera in that band while much of the chart remains visible. `At(center)` then discarded it. | Enter a chart under the camera, retain it while visible, and fade by actual viewport/art overlap. No off-center corner activation. |
| Skull Rock has a rectangular ornamented border | Actual Jasperlode source has the same native parchment/title/gold-corner treatment; Skull Rock screenshot shows its own embedded border. | Painted maps deliberately remain local charts with a subtle bronze edge/shadow, original placement/crop and explicit floor limitation. WMO interiors remain frameless. This is not semantic landscape integration. |
| NPCs appear late and snap | `NS.ValidMap(nativeHost)` delayed eligibility until the native host settled; there was no coalesced camera subscription. Failed `Place` was still followed by `Show`. Native zoom percentage also changes with host. | Camera-based eligibility, placement into the actual host before showing, logical-entry opacity fade over 180 ms, constant stitched screen size, bounded event-invalidated projection cache, invalid geometry rejected. |
| Host 1415→1458 shows 214→0→214 interior pictures | Synchronous native callbacks observed the reset canvas before the world camera was restored. | Preserve the authoritative world camera through `SetMapID`, defer artwork attach until restoration, and retain unchanged interior bindings. |
| Overview has lettering, gaps and inconsistent regions | Overlay-only zones omit useful base mountains/coasts/rivers. Their bases also contain neighbor labels and ornaments. Native palettes and optional unexplored dimming differ. | Expose dim mode/counts in reports; prototype private source-aware underpainting. Reject grow-only masks for production because they expose labels/borders. Parent lettering remains unresolved. |

Detail below a partially visible chart no longer fades across the entire outdoor
viewport. Fully covered terrain can still be released. One chart/12 painted
tiles, terrain cap 80 and per-interior cap 256 remain. A transient 150 ms entry
fade also handles new-chart handoffs on that same layer. View changes do not
restart it, and completion/close/disable removes its updater. Actual displayed
strength and target strength are reported separately, with bounded transition
events. Terrain stays beneath a fading chart and fully covered terrain is
released only at complete opacity. There is no second artwork set, persistent
cave animator or profiler. Automatic cave floors are still unknown.

## Report interpretation and performance

The first report records `cave:5`→nil at 9.235–9.298 seconds during outward zoom;
it contains no captured camera rectangle. This supports investigating selection,
not inferring a texture load failure or incorrect geography.

The second records 80 `map.view.step` calls, maximum **43.1819 ms**, total
199.191 ms / self 63.8895 ms, and **15,143.5 KB** allocation. Interior update max
is 4.0313 ms; the host changes at 4.984 seconds, with 214 pictures restored at
5.018. These maxima need not be the same frame. Allocation sums positive
inclusive Lua heap deltas: nested scopes overlap, and this is neither unique
allocation nor retained memory. No leak or NPC-spike causality is established.

Existing diagnostics now expose `map.art.update`, `map.detail.update`,
`map.cave.update`, `map.cave.fade` and `npcs.map.fade`, alongside existing interior/view scopes.
Map reports retain NPC scopes, aggregate marker eligibility/fade/placement
events, unexplored dimming provenance and the allocation qualification.
With **Include precise view/cursor geometry** enabled, detailed reports also
retain up to twelve actual painted cave tile rectangles/UVs for partial lab
import. Player position remains unqueried; geometry is withheld by default.

Measured using shipped Undercity geometry and mock texture APIs, sequentially:

| Workload | Before CPU | After CPU | After alpha/show writes |
| --- | ---: | ---: | ---: |
| 1,000 unchanged updates, 217 pictures | 90.331 ms | 0.143 ms | 0 / 0 (before: 217,000 / 217,000) |
| 1,000 changing-alpha updates | 89.042 ms | 51.079 ms | 217,000 / 217,000 |
| 1,000 pan updates, same selected set | 86.024 ms | 45.881 ms | 0 / 0 |
| 100 close/reopen cycles | 34.124 ms | 27.218 ms | same bindings/lifecycle |

Steady GC-stopped heap growth is zero; close/reopen adds approximately 4.039 KB
in both versions. Async readiness, timeout/retry, rejection and budget tests
remain. The new NPC camera path's 3,000-entry/500-view fixture takes 0.986192 s,
retaining a 300-frame pool and zero idle fades. That is a development-variant
measurement, not a previous-release speedup. These measurements do not certify
native CPU/GPU, streaming or the 43 ms spike's removal.

## Real-art inspection and reproducible cameras

`--scenario-set feedback-v1` exports 62 deterministic production-Lua views:
Eastern Kingdoms/Kalimdor overviews, regional borders/coasts, Tirisfal/Undercity,
Jasperlode and Skull Rock, including entry at 0/75/150 ms and fine cave exit sequences. The profile uses
the reports' maximum zoom 72. Original numeric geometry, actual selected layers,
renderer source hashes and inactive base candidates are retained. The default
12-view client catalog and 29-view synthetic catalog remain available.

```sh
python3 tools/maplab/run.py \
  --client-bundle /private/TwichUI-map-art-01.zip \
  --client-bundle /private/TwichUI-map-art-02.zip \
  --client-bundle /private/TwichUI-map-art-03.zip \
  --scenario-set feedback-v1 --scene jasperlode-edge-2 \
  --output test-output/map-feedback --strict
```

Repeat `--scene` for focused views; unknown IDs fail. Full and focused galleries
remain bounded. Before snapshots use unchanged addon sources at `9ada51f` in a
detached checkout, with the same export/compositor tools and private source set.
The primary agent directly inspected the before/after Jasperlode images,
source mosaic and private regional underpaint comparison. The source study was
also independently inspected by an agent.

At Jasperlode's center offset 0.48 cave widths, strength rises from approximately
0.04859 to 1; just beyond the old center boundary it remains readable, then
fades as the actual chart exits. A centered 124 view was already opaque before;
it alone would not reproduce the owner's faint off-center screenshot. The
complete deterministic exit states drop from **30 abrupt-alpha findings to 0**.
This verifies the sampled geometric sequence, not every possible native input.

Private artifacts, ignored and excluded from packages:

- `test-output/map-feedback-before/index.html`: before selected real-art views.
- `test-output/map-feedback-after/index.html`: production after views/differences.
- `test-output/map-feedback-after/cave-before-after.png`: inspected comparison.
- `test-output/maplab-underpaint-final/`: private source/mask and production-state
  comparisons, explicitly not runtime assets.

The underpaint study uses Elwynn/Westfall/Duskwood source alpha expanded over
unaltered native base RGB and Lua-exported geometry. At zoom 12 it changes
150,553 pixels (22.6056%); at 48 it changes none because native terrain covers it.
The comparison improves narrow coastal context but exposes neighbor lettering
and decorative fragments. Pixel changes are not an artistic quality score.
OpenMap's pinned `6c2299f6` source instead uses reviewed territory/core/band
masks, boundary grading and separate coastal/open-sea fallbacks. Those remain
the prioritized follow-up; no OpenMap processed art is copied or executed.

## Missing input and smallest next collection

The supplied bundle is complete for its original declared candidate set, not
every new camera. Jasperlode is present; all twelve Skull Rock files
611684–611695 and some wider Kalimdor/Eastern Kingdoms sources are absent.
Incomplete views remain explicitly partial. A complete 4.1 overview and offline
Skull Rock visual acceptance cannot be claimed from these inputs.

Real-input galleries now write `asset-request.json` from production-selected
numeric IDs and inactive native bases. The existing collector accepts that
exact-build request and can embed it in a source-only kit. From the extracted
feedback kit, the only gaming-PC step is:

```powershell
py -3 tools/maplab/collect.py --wow "D:\Games\World of Warcraft\_forever_" --output "test-output\maplab-feedback-input" --asset-request maplab-asset-request.json
```

Return every printed ZIP part. Requests are checked against the installed
build/product and current numeric-data hashes before texture reads. If the
client has updated, regenerate the request; do not edit its build or hashes.
The normal repeat-update command remains unchanged without `--asset-request`.
No installed files, account data or network services are changed/accessed.

## Acceptance remaining

In-game: anchored wheel zoom/pan around Jasperlode and Skull Rock, exit/reentry,
floor controls, NPC entry/hover/click and host handoffs, Undercity 214-picture
transitions, different viewports/UI scales, combat, disable/restore and existing
quest/navigation/Questie/TomTom behavior. These are owner-directed checks;
offline verification cannot establish native appearance or protected behavior.
No release, merge, production asset packaging or architecture switch occurred.

## Final verification

```sh
source /workspace/twichui-env/activate.sh
./tests/run.sh feature navigation --profile cloud --jobs 2
python3 -B tests/test_maplab.py
python3 -B tests/test_maplab_client.py
python3 -B tests/test_maplab_extract.py
python3 -B tests/test_maplab_underpaint.py
```

The final frozen-source feature gate passed **102 modules / zero failures**,
Lua syntax (309 files plus runner scripts) and simulator smoke in **66.358 s**.
Source fingerprints remained unchanged. The four Python modules contain
**21 + 17 + 20 + 7 = 65 passing cases**. Isolated cave production tests pass
**261 assertions**, including actual entry-time alpha, no restart, handoff,
close/disable cancellation and bounded transition traces. Multi-floor coverage
now checks the actual painted floor; sparse WMO rectangles keep terrain in
their gaps. The 4,000-operation final course passes at **1.6342 s fixture CPU**,
zero new warmed terrain textures and peak 24 active. This is not native CPU/GPU
or a controlled speedup claim.

Initial new-test integration recorded 100 pass / 2 runner-contract failures:
both new Lua tests exited zero but lacked the runner's uppercase `PASSED`/`OK`
footer. Correcting their success footers changed no assertions; that failed
evidence is retained. Subsequent entry-fade behavior warranted new verification;
the final gate above includes all final code and wording.

Actual-art evidence:

- Original-addon baseline: **17 scenes, zero missing**, strict success, 39.865 s.
- Final settled subset: **14 scenes, zero missing**, strict success, 38.628 s.
- Entry subset: **3 scenes, zero missing**, strict success, 7.127 s; actual
  Jasperlode alpha **0 / 0.5 / 1** at **0 / 75 / 150 ms**. The primary agent
  inspected `test-output/map-feedback-entry-after/entry-before-after.png`.
- Full feedback catalog: **62 scenes**, **35 complete** and **266 distinct
  visible texture IDs unavailable**, 114.131 s. Strict mode correctly returns
  nonzero and labels the overall gallery partial. Its checkerboards are missing
  private lab inputs, not proof that the native client lacks those assets.
- A final source export matches all 62 rendered texture/view primitives after
  the floor-coverage safeguard and help-text refinement; individual artifacts
  retain their actual source hashes. The regional 24 and Booty Bay 48 reference
  images are pixel-identical to the original-addon baseline. Undercity retains
  identical geometry/alpha, with small same-sublayer creation-order differences
  from changed pool reuse; native ordering remains an acceptance check.

The full gallery is `test-output/map-feedback-final/index.html`. Its automatic
asset request contains **1,693** exact-build IDs; **574** are absent from the
supplied cache, including inactive native bases for the private source study.
The source-only `test-output/TwichUI-map-feedback-71037.zip` contains that exact
request and 14 source/numeric files, **95,358 bytes**, no artwork. Extracted
request validation passes with Python site packages disabled.

The previous full suite on `70bd271` remains **324 passed / 1 unrelated Welcome
Back failure** (`tests/test_welcome_back.lua:84`, 668.519 s). Original 322/1
baseline and untouched reproduction evidence remain preserved. No Welcome Back
code/test changed. The full suite was not repeated for this bounded map/NPC/lab
refinement; the affected feature gate above was rerun. Cloud checks do not
satisfy native/local release acceptance. No merge or release was performed.
