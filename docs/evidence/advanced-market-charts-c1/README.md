# Advanced Market Charts — C1 owner review

Presentation-only work based on protected main `36cdb04b35ca132650673463ecc09a0bbeadb6dc`.
No merge, deployment, release, beta.5 distribution, U1/U2 or M2 changes are authorized by this PR.

## Design and architecture

`auction/AdvancedChart.lua` is a Market-only component, lazily constructed when the
existing Market page builds. The original `UI.PriceChart` remains unchanged.
The interface is `Set(series, formatter)`, `Select(fromDay, toDay)` / `Select()` to reset,
`Inspect(day)` and `Clear()`. `Prepare`, `Geometry`, `Nearest`, and `Connected` separate
preparation, axes, geometry and arithmetic hit-testing. Rendering regions are reused.
The Market integration preserves source-generation cancellation and the existing item,
variant, metric, tracking, Browse and Advisor navigation and transaction gates.
No price service, history calculation, SavedVariables or external schema changes.

The inherited CraftLook materials provide espresso, walnut, leather and fine bronze.
The chart is 24 logical pixels taller; small warm-bronze markers sit on a 1.25-pixel
segmented line. Four quiet horizontal guides, padded value axes, UTC dates and source
coverage remain visible. Older aggregates use subdued interval bands and mean rules.
The inspection panel stays within chart bounds and anchors to the selected observation.
The lower cards were tightened to preserve their place in the existing shell.

Mouse hover performs a binary nearest-observation lookup over prepared data. It shows
exact copper, available exact UTC timestamps, daily-record dates where time is unavailable,
provenance and partial coverage. Aggregate hover explicitly names the interval and mean.
Drag selects and redraws a historical interval; right-click resets the selected range.
The existing historical-range selector remains unchanged. Wheel zoom is deferred to
avoid conflicting with page scrolling. No point buttons, permanent OnUpdate, background
rendering, history decoding or data preparation occur on pointer movement. Inspection
updates its text only when the selected record changes. Leaving, hiding, source/item
replacement and release clear interaction; release drops evidence and geometry references.

## Historical truth

Only existing typed observations are displayed. Daily gaps and gaps explicitly supplied
by the services break lines. Daily records more than one day apart never join. Aggregates
never become daily samples; their low/high and mean retain their original interval and
observed-day count. One observation draws one marker, never a fabricated flat trend.
An empty source states that no supported observations are available. Prices and quantities
use separate source metrics. Supply is labeled in items, price in copper; neither is
represented as completed sales, demand or guaranteed revenue.

When exact observations exceed horizontal drawing columns (capped at 1,024), a per-column
min/max envelope replaces connected segments. No mean or synthetic price is generated;
all original observations remain available to hover. A bin crossing discontinuities is
never connected to a neighbor. The chart labels this mode as pixel min/max ranges.

## Drawing APIs and compatibility

Read-only source inspection: the local Forever branch documents `CreateLine`,
`SetThickness`, `SetStartPoint(point, relativeTo, x, y)` and `SetEndPoint` under
`Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua` and
`SimpleLineAPIDocumentation.lua`. Blizzard's PowerDependencyLine uses these primitives.
They were evaluated, but the narrow simulator capture showed offset drift between
native lines and correctly scaled markers. That does not prove a Forever defect.
An eight-coordinate alpha-texture prototype also produced inadequate simulator geometry.
Neither implementation remains in production.

The final renderer uses only solid textures, positions, sizes and alpha, as the existing
Workshop and Diagnostics chart implementations do. It rasterizes each actual connected
segment into logical-pixel coverage columns and merges adjacent equal-coverage runs into
one texture. Stroke coverage is 1.25 logical pixels with at most half a pixel of vertical
rasterization error. No native line, rotation, UV transform, external library, artwork or
Diagnostics dependency is required. This trades higher bounded region counts for a
simple, portable drawing path. The line and markers share the same scaled coordinates.
Core Perf scopes `auction.chartPrepare`, `auction.chartDraw` and gauges
`auction.chartPool`, `auction.chartRecords` permit an opt-in native capture. Hover is
measured offline; its tiny lookup is deliberately not wrapped per frame in a Perf scope.

This establishes source/API and simulator evidence, not Forever-runtime acceptance.
The owner must check actual texture rasterization, stroke weight and pointer input.

## Offline performance evidence

Lua 5.1 synthetic recording frames, identical 682 × 128 logical-pixel plots and price histories, 200 iterations per data
size. `old-redraw` uses the existing Market newest-30 limit; `new-set` includes preparing
and rendering every observation. These are CPU microbenchmarks, not GPU or frame-time
measurements. The harness is retained in `test_workshop_auction_market_chart.lua`.

| Observations | Prepare µs | Old redraw µs | New Set µs | Hit lookup µs | Markers / stroke textures |
|---:|---:|---:|---:|---:|---:|
| 2 | 2.79 | 27.26 | 476.23 | 0.12 | 2 / 81 |
| 7 | 3.74 | 36.86 | 1157.54 | 0.27 | 7 / 399 |
| 14 | 7.59 | 48.04 | 1444.49 | 0.26 | 14 / 586 |
| 30 | 15.22 | 79.30 | 1478.48 | 0.31 | 30 / 650 |
| 60 | 33.70 | 82.65 | 1779.29 | 0.38 | 60 / 717 |
| 120 | 67.53 | 84.41 | 2335.21 | 0.44 | 120 / 791 |

````text
C1 DETAIL old-init=644.40us new-init=299.53us changed-hover=9.74us idle-hover=0.65us resize=3355.75us unchanged=0.27us reopen-growth=0.00KiB pool=911
````

The detail line reports initialization, full changed/unchanged hover, forced geometry
resize, unchanged geometry, and additional GC-retained memory after 200 Set/Clear cycles.
UI scale changes with unchanged logical geometry require no chart reconstruction; the
unchanged-geometry figure excludes the game engine's scale propagation/GPU cost.

| State | Frames | Textures | Font strings | Native lines |
|---|---:|---:|---:|---:|
| Old chart initialized | 2 | 144 | 4 | 0 |
| New chart initialized | 3 | 49 | 10 | 0 |
| New chart, volatile 120-point history | 3 | 960 | 10 | 0 |
| After 200 Set/Clear cycles | 3 | 960 | 10 | 0 |

The measured stress dynamic peak is **911 regions**, including 120 markers and 791
stroke textures; it stays stable after repeated redraws. These counts include the
inherited panel material regions in the totals above. Additional retained memory of
0.00 KiB means no growth after warming the pool; it does not mean the cached pool is free.
[Raw CPU results](benchmark.txt) and [region counter](region-counts.lua) are retained.
Reproduce the benchmark with the standard direct Lua test command for
`tests/test_workshop_auction_market_chart.lua`; use `region-counts.lua` as its script
argument for the constructor counts. Run these without competing simulator work:

```sh
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_workshop_auction_market_chart.lua)
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' ../docs/evidence/advanced-market-charts-c1/region-counts.lua)
```


Initialization and redraw figures use recording frames and include inherited panel work;
these are not GPU timings. More complete rendering costs additional CPU and regions.
The final backend trades native-line efficiency for consistent scaled texture geometry.
Unchanged geometry is skipped; hover does not rasterize the graph.

Initial dynamic pool: zero. Current History2 retains 8 recent observations, 30 exact days
and bounded weekly/fortnight records over 120 days; external history is capped at 60 daily
observations. The 120 exact-sample volatile stress case exceeds current exact retention.
Raster work is capped at 1,024 horizontal columns. Across ordered disjoint segments,
column/segment boundaries bound the stroke pool by 2,048 runs; point markers add at most
1,024, plus two regions per existing supported aggregate interval. Dense geometry uses
at most 1,024 envelope textures. Aggregate input is the existing bounded typed service
output, not arbitrary third-party chart input. Pools retain their maximum allocation for
reuse and hide unused regions; cached evidence returns to zero on close. Native allocator
and GPU memory remain unmeasured.

## Verification and limitations

Unit-tested: focused chart tests cover empty/single, exact timestamps and copper,
local/external records, aggregate intervals, gap separation, axes/extrema, hit-testing,
selection/reset, texture pools and independence from native line APIs, release and dense 10,000-sample extrema.
Existing scoped Market assertions now verify the complete inspectable window instead
of requiring the retired newest-30 presentation cap. Existing validation and negative
controls remain intact. Development auction-preview: 19 files passed.

Earlier development attempts caught a native endpoint signature error, and presentation
assertions requiring the old dot pool. Both were corrected. One early gallery and one
focused test attempt were invalidated by edits during execution; those artifacts are
not final acceptance evidence. The new hover pose initially failed the strict expected
assertion count because it adds one check; the count now explicitly includes that check.

Screenshots use the existing simulator, real addon code, synthetic histories and the
repository's available art. Native game fonts, currency icons and game textures are
unavailable in cloud no-assets mode; fonts fall back and currency denominations may
appear without icons. Screenshots support structural owner review, not true Forever
appearance or input acceptance. Native pointer capture, drag cancellation, tooltip
readability, scales, fonts, combat/taint and GPU/frame-time behavior require client tests.
No release certification or live-game testing was run. Pricing mutation campaigns were
not triggered because pricing, quantities, rounding and eligibility logic are unchanged.

## Owner review

Please judge stroke weight and contrast, the balance of chart height against the lower
cards, aggregate-band clarity, and inspection-panel placement in the gallery. Native
acceptance should include repeated open/close and item/source/metric changes, narrow and
scaled windows, drag/reset, long copper labels, and an opt-in Diagnostics capture.
Do not merge before owner visual review. Do not publish this draft.

## Delivery and final verification

Final implementation commit: `346e3c6b35e0a20f257b7c274d6282c687d1652e` (initial component checkpoint: `979281404d7729fbd8e0cf0ba592240f64e0f566`).

- `./tests/run.sh development auction-preview`: 19 passed after the interval-preserving
  resize change, including actual scaled pointer-handler coverage.
- `./tests/run.sh feature advanced-market-chart --profile cloud`: 23 passed, 0 failed; 14 simulator launches and 1,847 structured assertions; 270.215 seconds, PASS.
  This profile retains the Auction House shell replay and deliberate-wrong-expectation
  control. No full release certification was run.
- The final renderer's ordinary, hover, interval, sparse, single, empty, narrow, scaled,
  aggregate and external captures were screenshot-reviewed; the large-copper capture
  also checks compact axis units. [Open the before/after gallery](GALLERY.md).
- The cloud long-item-title pose visibly clips the pre-existing shell title despite
  its unchanged wrapping assertion passing. C1 does not alter that native-font layout;
  the review gallery uses the dedicated large-copper stress for long chart-label review.
- Native API/texture rasterization, actual mouse input and drag cancellation, clipping
  with native fonts, combat/taint, reload behavior and real frame-time acceptance remain
  **not tested**. Owner review is required before merge; publication remains prohibited.

Changed files (plus the approved evidence in this directory):

- `TwichUI_Workshop/auction/AdvancedChart.lua`
- `TwichUI_Workshop/auction/ViewMarket.lua`
- `TwichUI_Workshop/TwichUI_Workshop.toc`
- `TwichUI_Diagnostics/Gauges.lua`
- `docs/diagnostics.md`
- `tests/groups.json`
- `tests/test_workshop_auction_market_chart.lua`
- `tests/test_workshop_auction_market_scoped.lua`
- `tests/test_workshop_auction_market_ui.lua`
- `tools/simlab/auctionpreview.sh`
- `tools/simlab/auctionpreview_verdict.py`
- `tools/simlab/scenarios/auctionpreview.lua`

## CI catalog follow-up

The first PR CI run passed 259 offline modules and failed two infrastructure tests:
`test_test_runner.py` still expected the old 44-pose catalog, and `test_mutate.py`
found three mutation patterns tied to the replaced chart. The count now remains exact
at 48 and explicitly checks the four C1 poses and replay/negative-control inclusion.
Mutation entries now target the current resize render path and complete-window
preparation. The retired local-cap mutant is replaced with loss of local chart evidence,
matching C1's intentional removal of that cap. All three refreshed mutations are killed
by assertions in their existing focused tests; all 373 catalog entries match and parse.
Runner tests: 16 passed; mutation harness tests: 29 passed. This follow-up changes no
runtime code or visual geometry, so the retained gallery and performance evidence still
represent the implementation. The GitHub PR checks record the complete CI rerun.
