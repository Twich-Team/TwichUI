# Advanced Market Charts C1.1 — owner acceptance

Continue draft PR #50; no merge, install, deployment, tag or publication. The native
owner report approves C1's direction but reports unreliable hover, failed dragging
and pixelated strokes. No owner client image was attached in this task: retained C1
captures and the owner's written observations are the comparison baseline.

## Findings and corrections

The source confirmed two teardown paths matching the reported symptoms. Market detail
refreshes create fresh series tables and call `Set()`. C1 unconditionally called
`ClearHover()`, removing its OnUpdate and drag state even if the cursor was still over
the same region. The engine need not send another OnEnter until a genuine boundary
crossing. C1's OnLeave also discarded the drag and updater, and mouse-up depended on
the original plot receiving it. These are concrete source failure paths; no native
input trace was collected to establish every contributor to the owner symptom.

C1.1 compares equivalent projections by value and supplies an explicit context containing
item, source, metric, variant, range and generation. Unchanged evidence preserves the
viewport and active input. Same-context updates (including moving recent time bounds)
retain owned input; genuine context replacements cancel it. Geometry repaint no longer
owns input teardown. A stationary pointer can reacquire inspection after replacement.

A single transparent Button owns the entire plot's hit plane above decoration. The
inspection panel is explicitly mouse-disabled. Its date, value and provenance are separate
font strings, with calm espresso and bronze material, and placement beside the selected
point. Crosshair position follows the cursor; the marker stays at an actual observation.
Text only changes when its evidence or gap date changes. Meaningful gaps show a supported
value-unavailable state, explicitly distinguishing observed absence, unsupported buyout
and unknown/missing coverage. No distant price is invented at the cursor.

Left drag owns OnUpdate and a temporary GLOBAL_MOUSE_UP registration only while active.
OnLeave hides inspection but preserves an active drag. Release outside clamps to the
plot, commits once and unregisters; IsMouseButtonDown is a drag-only fallback for lost
release/focus events. Hide, source replacement and cancellation remove owned work.
Tiny drags under six logical pixels leave the existing viewport intact. Either direction,
consecutive selections and reset are covered. During selection the panel is hidden so
it does not cover the bronze interval. The instruction is **Drag to zoom · Right-click
to reset**. No wheel binding, global permanent observer or gameplay action was added.

## Rendering decision

Forever's read-only API source documents CreateLine, SetThickness and endpoints relative
to ScriptRegion. GLOBAL_MOUSE_UP is documented with a button payload; the source also uses
IsMouseButtonDown for temporary interactions. C1.1 does not copy Blizzard implementation.

C1 used numeric plot-relative offsets and rejected native lines after scaled simulator
drift. C1.1 anchors each endpoint to the CENTER of its existing marker Texture with
zero offsets. Texture regions satisfy the documented ScriptRegion parameter; no per-point
frames are created. Ordinary and scaled simulator captures now keep lines on markers.
The native candidate uses a 1.25-pixel antique-gold core over a subdued 2.75-pixel bronze
supporting edge. A tiny neutral antialiased disc material gives normal and selected
markers a refined silhouette; the selected marker has a faint supporting halo.
The material is generated deterministically with stdlib Python, without dependencies.

The native candidate is selected when the line API succeeds. Failure of construction or
endpoint methods hides partial lines and selects the retained C1 texture-run fallback.
`SetStrokeMode('raster')` forces that fallback; `SetStrokeMode('native')` retries native.
The fallback retains portable geometry and its known stair-stepping limitation. It is
not claimed to have native-line smoothness. An alpha-UV material was considered but not
adopted: C1 evidence already showed inadequate simulator mapping and no native proof.
Area shading was omitted: additional objects and potential gap ambiguity bring little
benefit over the supporting edge. No curves, smoothed samples, resampled means or
connections across missing intervals were introduced. Aggregates remain interval bands.

**Native line and input acceptance remain open.** Simulator agreement is not proof of
Forever appearance or actual mouse delivery. The retained raster path provides a
compatibility escape hatch; the owner must test the candidate in Forever.

## Measurements

| Offline CPU µs | C1 | C1.1 native candidate | C1.1 forced raster |
|---|---:|---:|---:|
| full | 2936.80 | 850.82 | 3829.60 |
| refresh | 2361.99 | 50.15 | 52.01 |
| hover | 5.37 | 8.09 | 7.94 |
| idle | 0.57 | 2.01 | 2.36 |
| drag | 3.55 | 1.52 | 1.67 |
| select-reset | 4424.49 | 1105.08 | 3891.24 |
| resize | 2329.16 | 643.28 | 2205.82 |
| unchanged-scale | 0.27 | 0.28 | 0.29 |

Initial constructor means after a shared-style warmup: C1 1,392.07 µs; native candidate
328.33 µs; forced raster 328.63 µs. Initialization is especially sensitive to mock/GC
warmup and order; do not treat these numbers as a native loading-speed guarantee.
Preparation uses the unchanged algorithm; its 75–117 µs spread here is measurement noise.

| Recording-frame resource count | C1 | Native candidate | Forced raster |
|---|---:|---:|---:|
| Frames | 3 | 4 | 4 |
| Initial textures / font strings | 49 / 10 | 50 / 12 | 50 / 12 |
| Peak textures / native lines | 960 / 0 | 170 / 238 | 961 / 0 |
| Dynamic drawing pool | 911 | 358 | 911 |
| Mock heap allocated per full redraw, KiB | 375.388 | 167.678 | 414.795 |
| Mock heap allocated per idle inspection, KiB | 0.000 | 0.219 | 0.219 |
| Additional retained Lua heap after 200 replacement/clear cycles, KiB | 0.219 | 0.219 | 0.219 |

The heap-allocation proxy includes recording-stub tables for SetPoint. It is not a
measurement of actual native per-hover Lua allocation. Drawing-object allocations on
pointer movement are zero after construction. Changed/idle hover have a small additional
cost for cursor-following geometry, gap analysis and panel hierarchy. The forced raster
redraw is more expensive than C1 in this run because it retains the old backend while
also styling round markers; its unchanged-data path is much cheaper than C1. Native
redraw and region reductions are substantial in the harness, but client GPU cost is unknown.

Pools stay bounded after 200 replacement/clear cycles. Warming **both** backends on the
same chart retains 1,149 dynamic regions for this stress history, versus 358 when only
native is used; 400 backend switches add 0.000 KiB after warmup. This is an intentional
high-water cache, not free memory. Supported external histories have at most 60 exact
points: at most 178 native regions (N markers + 2(N−1) strokes). Aggregates add two textures
each; dense inputs retain the existing 1,024-column min/max representation. No per-point
frames are allocated. The optional halo adds one fixed texture, and the hit plane adds
one fixed Button. Area shading was omitted to avoid additional per-column resources.

Reproduce from the repository root (with Lua 5.1 and bitop available):

```sh
git show e4e1f08:TwichUI_Workshop/auction/AdvancedChart.lua > /tmp/c11-baseline.lua
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"; BASELINE="/tmp/c11-baseline.lua"' ../docs/evidence/advanced-market-charts-c1/c11/benchmark.lua)
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' ../docs/evidence/advanced-market-charts-c1/c11/mixed-pools.lua)
```


The harness loads the exact C1 git blob and the current C1.1 component into the same Lua
5.1 recording-frame environment, using identical volatile 120-sample histories and a
682 × 112 logical-pixel plot. Initializer cost is a 30-construction mean; other timings
are repeated CPU measurements in microseconds. Full redraw uses explicit changed context,
so the native renderer is not being compared through its unchanged-evidence fast path.
Native line calls are modeled; these are **not GPU or Forever frame times**.
Scale propagation is owned by the engine: unchanged logical geometry measures only the
component's skip path, not the engine cost. The narrow and 0.8-scale captures check layout.
Peak counters include inherited material textures and distinguish native lines from
textures. Pool objects stay allocated for reuse; small Lua heap deltas are not a claim
that retained regions cost no memory. See the raw results and reproducible harness.
Core chart preparation/draw scopes remain available; the pool gauge now counts native
regions too. Cheap pointer and selection movement is measured directly rather than
adding a permanent per-frame profiler wrapper. No Diagnostics addon is loaded by the chart.

## Verification and evidence

- Unit-tested and simulator-tested: `./tests/run.sh feature advanced-market-chart --profile cloud`:
  **24 test files/modules passed, 15 launches, 1,984 structured assertions**, 293.026 seconds, PASS.
- `development auction-preview`: 20 passed; `development verification-tools`: 4 passed.
- Infrastructure runner: 16 tests passed; mutation harness: 29 tests passed.
- All 376 mutation patterns match and parse. Six selected presentation mutations are
  killed by assertions (refresh, leave-drag, endpoint anchors, resize labels, local source,
  and full-window preservation). No negative control was removed or relaxed.
- Earlier fixture/debug runs are retained locally as failures, not acceptance evidence.
  The new gap-date assertion was initially duplicated into a drag step where inspection
  is intentionally hidden; its placement was corrected. A standalone infrastructure run
  lacked the prepared Lua PATH and was rerun in the normal activated environment.
  The earlier failed profile was interrupted and remains incomplete; the final frozen
  profile above passed. No native-client testing was performed.

[Open the C1/C1.1 comparison gallery](GALLERY.md). Implementation commit:
`f526f69680ed00ebbdbadad8dea89a258798bf9b` (pushed with the evidence commit to PR #50).


Input tests use the existing Press eligibility dispatcher and a modeled registered-event
router, beyond isolated method calls. The simulator's Reach analysis inspects nine
positions over the real plotting frames, including positions far from the stroke and
beneath the inspection panel. The simulator has no headless OS pointer injection: its
GetMouseFoci can be forced but does not discover frames from cursor coordinates. Therefore
these results are labeled modeled hit-testing and handler/event routing, not native input.
The default and selected catalogs retain replay, deliberate wrong expectations and their
strict counts. Presentation mutations cover refresh teardown, leaving during a drag,
endpoint-offset regression, external resize labels and local source preservation.
Pricing, history services, schemas, SavedVariables, ingestion, M2/U1/U2/beta.5 and auction
transactions are untouched. The original UI.PriceChart remains unchanged.

The C1.1 captures are unedited; the gallery also offers identically sized, pixel-preserving
crops of C1 and C1.1. Original C1 evidence remains in the parent directory. Cloud lacks
native fonts, currency icons and game assets; repository CraftLook materials are reused.
Screenshots were reviewed for plot alignment, gaps, panel clipping, selected-point
visibility, selection visibility and narrow/scaled geometry. There is no native client
visual, taint, combat, input or performance acceptance claim.

## Forever owner checks

Open the existing Market research page and inspect at standard, 0.8 and smaller UI scales.
Hover near every corner and through gaps, away from the line, while metadata refreshes;
inspect exact copper, aggregate labels, provenance and observed-absence wording. Drag
both ways, leave every edge before release, cancel with reset, change item/source/metric,
and hide/reopen during dragging. Verify no stuck cursor work or stale values.

While that page is open, the backend can be inspected with:

```lua
/dump TwichUI.Workshop.AuctionUI.Page('market').chart.backend
/run TwichUI.Workshop.AuctionUI.Page('market').chart:SetStrokeMode('raster')
/run TwichUI.Workshop.AuctionUI.Page('market').chart:SetStrokeMode('native')
```

Compare native stroke weight, antialiasing and marker alignment at steep and nearly
horizontal slopes, resize repeatedly, and run opt-in Diagnostics captures for redraws,
retained pools and repeated open/close behavior. Review the supporting edge and compact
panel hierarchy for design approval. If the native candidate is rejected, retain/force
raster while reporting the specific client error or visual defect. Do not merge before
owner acceptance, and do not publish this draft.
