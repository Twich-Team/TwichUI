# Workshop Settings 2.0

Campaign base: `83050a2b`, branch `feature/workshop`. Scope: Workshop's settings
content only; preserve the settings shell, left navigation, saved layouts and
existing pricing/planning services. The approved reference is **TwichUI Tooltip
Designer Workshop.png**; **ChatGPT Image Nov 14, 2026, 08_22_22 AM.png** records
the old page. Both were supplied and visually inspected on 2026-11-14.

## Checkpoints and acceptance

1. **Foundation:** General / Tooltip Designer / Market Data / Crafting & Shopping
   tabs through the existing task-strip components; remove obsolete explanation
   and loaded-status cards; genuine existing preferences and honest market states.
   Preserve profiles and the shell. Verify all four tabs, contract diff, saved
   values, fast + feature checks, and screenshots; commit and push.
2. **Designer:** reuse WorthLayout operations and renderer, saved v1 format and
   Always/Shift semantics. Two columns, searchable grouped catalog, selected-row
   actions, responsive preview, safe drag with click alternatives. Draft-only
   changes; Save validates atomically, Cancel discards, Undo/Redo restore complete
   state, Reset confirms. Verify four samples, existing layouts, profile changes,
   handler/reachability checks, six visual poses and checkpoint tests; commit/push.
3. **Integration:** opt-in profile preference for safe login loading, default off;
   no window, scan or plan computation. Reuse supported objective, guild stock,
   prices, notices and compact APIs with no conflicting saved keys. Verify off/on,
   lifecycle/combat/error/idempotence/profile behavior and realistic load costs;
   run relevant focused/feature/mutation checks; commit/push.
4. **Polish:** compare the approved reference, inspect wide/narrow/scaled captures,
   correct clipping, density, focus/hover and scroll ownership. Run the complete
   regression command, document real-client gaps and artifacts, commit/push, stop.

## Invariants

- `WorkshopAuto.POLICY == "manual"` and its capability gate remain unchanged.
- `Progress.auto == false`; manual Crafted one / Undo remains available.
- Opening settings/editor, searching, previewing and cancelling never writes
  observed prices/inventory or commits a tooltip draft.
- Preserve `TwichUIDB.ui.workshopWorth` v1 profile data; Never overwrite newer
  versions. Existing account-wide Workshop preferences retain their saved keys.
- Load-on-demand stays off until an explicit action or the opt-in login bootstrap;
  loading the separate market database may synchronously deserialize substantial
  data and cannot be made asynchronous by delaying the call.
- Simulator installation and all supporting repositories are read-only. Artifacts
  stay under ignored `test-output/`; no release or unrelated feature work.

## Evidence limits

Unit and native simulator checks establish handler/state, rendering structure,
layout and reachability facts over synthetic data. The simulator has no genuine
pointer stream and substitutes game fonts for addon fonts. Real-client dragging,
keyboard/focus, final typography, combat transitions and reload persistence must
be listed separately; screenshots do not prove real-client appearance or input.

## Checkpoint record

All four checkpoints are implemented and verified. Results follow. The original tooltip designer saves immediately; checkpoint 2 replaces
that interaction model while retaining the stored layout and renderer.

### Checkpoint 1 — four-tab foundation

- Unit-tested: fast group (8 files; the added settings test passed in the feature
  run), feature group **73 passed**, no failures; native Workshop design/craft/wrong
  scenario passed. Feature run: `test-output/workshop-settings-v2/feature-c1.log`,
  117.520 seconds including the selected native suite (63.890 seconds).
- Simulator-tested and screenshot-reviewed: all four tabs at 1240×960 in a
  1600×1200 viewport, each 17 Workshop handler/state checks plus 22 Home checks.
  Captures: `test-output/simlab/artifacts/settings-{z9l2FcKF,mmJmrQiI,IZGbZ7sc,LRTSq6As}/workshop.png`
  in tab order. Structural review only; font/input limitations above apply.
- Existing account preference keys retained; profile-scoped login preference
  defaults off. Its actual bootstrap and objective/compact integration follow
  in checkpoint 3. No inert objective or compact control is shown in this step.
- Shared settings contract unchanged; Workshop is conditional in that fixture,
  so a separate real-launcher description/persistence test covers its controls.

### Checkpoint 2 — visual draft editor

- Two columns reuse the existing materials, renderer, pure layout operations and
  Magic Inventory drag helper. The searchable catalog offers 12 implemented
  fields. Legacy `outcomes` entries are retained/editable but never offered.
- Undo/Redo retain up to 50 complete drafts. Save validates the whole layout before
  atomically replacing its v1 record; invalid/duplicate/sparse/future layouts are
  refused. Cancel, reset confirmation, empty/off layouts, profile apply and
  Always/Shift behavior are unit-tested. Preview modes/search/samples never save.
- Unit-tested: fast **8 passed**, 1.134 s; feature **73 passed**, 119.973 s,
  including selected Workshop simulator scenarios (66.668 s). The legacy scenario
  now explicitly saves its edits before checking the live item tooltip; separate
  assertions check that draft edits, Undo/Redo and Cancel leave it unchanged.
- Simulator-tested: six requested poses passed (506 structured checks per launch),
  including catalog geometry reachability. Handler tests include add/reorder,
  pointer-outside cancellation and page hiding; they are not real pointer input.
- Screenshot-reviewed at 1380×1120 in a 1600×1200 viewport:
  `test-output/simlab/artifacts/workshop-{DeCOApNd,Kp6ovqvL,c5sOd7On,Yb9ZvZqe,EoePVQlg,QWDlJb8I}/design.png`
  (Normal, Shift, search, selection, reorder, reset). The wider capture contains
  the full editor. Small windows use the existing page scroll. Simulator game
  overlays and substituted fonts remain visible; these are structural captures.

### Checkpoint 3 — real preferences and opt-in login loading

- Login preference and tooltip layouts are profile-specific. Existing price,
  guild-stock and notice settings remain account-wide; objective and compact mode
  join that existing Workshop `view` record. Defaults are economic / Travel.
- Login OFF schedules no bootstrap timer. ON schedules one load two seconds after
  first world entry, after profile initialization. Combat and leaving the world
  defer it; stale profile work is cancelled. Repeated world/combat events cannot
  duplicate initialization; missing/disabled/error outcomes are recorded, with
  exceptions reported once through existing diagnostics. No unsolicited chat.
- Unit-tested: login/reload event paths, OFF/ON, later opt-in, cancellation, combat,
  zoning, manual pre-load, profile generation and errors. Actual module loading
  constructs no Workshop window, starts no plans/scans and decodes no history.
  `WorkshopAuto.POLICY = "manual"` and `Progress.auto = false` remain unchanged.
- Objective is forwarded to all four existing planner request paths and included
  in cache keys. A real integration case chooses buying under economic cost and
  crafting with owned inputs under cash cost; manual source choices survive.
  Compact mode persists and can change while hidden without opening either view.
- Unit-tested: final fast **11 passed**, 1.119 s. Feature **74 passed**, 121.703 s,
  including native Workshop scenarios (67.891 s). Crafting mutation group:
  **111/111 killed**, no survivors, invalid cases or timeouts, 40.9 s; includes the
  new objective-not-forwarded defect.
- Simulator-tested and screenshot-reviewed: actual settings controls load the
  module, change all five supported preferences, restore defaults and keep both
  windows closed, scans idle and unverified progress off. **37 Workshop checks**
  plus 22 Home checks; `test-output/simlab/artifacts/settings-9kRBQThv/workshop.png`.
- Performance observations: source initialization **10.509 ms** in the offline
  frame harness; native simulator's explicit Load options click **9.235 ms** with
  empty synthetic saved data. Neither establishes real-client startup cost with a
  large database. SavedVariables deserialization remains synchronous; opting in
  moves that cost to the delayed load rather than eliminating it. Login timing
  is exposed through the existing launcher's diagnostic snapshot.


### Checkpoint 4 — integrated polish and final verification

- Reused the existing icon registry for catalog rows, made saved/draft status
  explicit and disabled edits visibly for newer layout schemas. Updated player
  documentation and the continuing handoff.
- Unit-tested: fast **11 passed**, 1.352 s, including read-only future layouts and
  physical cursor coordinates at scale 0.8.
- Native narrow probe: **517 checks passed**, including actual Undo/Redo,
  Save/Cancel button handlers, unscrolled source stacking and scrolled bounds.
  `test-output/simlab/artifacts/workshop-bhjYVmMM/design.png` (936×660 window).
- Evidence correction: the raw simulator GetRect result stays in logical,
  unscrolled coordinates while its screenshot draws the child with the scroll
  offset. The initial raw reachability probe therefore reported visible scrolled
  actions as clipped. Scrolled probes now assert both drawn bounds using the
  explicit offset and report their narrower evidence. They do not establish
  stacking or pointer delivery after scrolling. Full stacking checks remain for
  unscrolled controls. No production geometry or simulator engine was patched.
- Corrected wrapped catalog-title/search spacing using the measured title height.
  Final narrow and scale-0.8 captures passed and were screenshot-reviewed:
  `test-output/simlab/artifacts/workshop-{bhjYVmMM,9Nk43Viy}/design.png`.
  The scale-0.8 case had 514 checks; narrow had 517. This is synthetic UI scaling,
  not a real-client scale/focus/input acceptance test. The login helper now warns
  that a large saved market database can pause the game while loading.
- Final feature check: **74 passed**, no failures, selected native suite passed;
  121.694 s total (native 66.878 s). Save also closes a pending reset confirmation.
- Comprehensive result: **PASS**, recorded below.

## Real-client acceptance and deliberate limits

- Test real dragging at normal and changed UI scale, including a scrolled preview,
  drops outside the window, Esc and closing/switching pages mid-drag. The simulator
  has no genuine pointer stream; its scrolled rectangle/stacking model is limited.
- Check final Cinzel/game typography, long labels, selected-row actions and reset
  confirmation at minimum and larger window sizes. The simulator substitutes fonts.
- Verify an actual login and reload with the preference OFF and ON, combat ending,
  profile switching and a representative large saved market database. The measured
  empty/synthetic loads cannot predict that database's synchronous startup pause.
- Confirm saved v1/empty/off layouts and account preferences survive real reloads,
  and manual Crafted one/Undo and explicitly clicked AH scans retain their behavior.

The approved mockup is followed through the existing shell, two material panels,
searchable grouped catalog, prominent tooltip and Normal/Shift controls. Save and
Cancel are explicit additions required by the mission; all twelve implemented
fields remain available. Existing icon/material components replace the mockup's
bespoke row art and parchment headings. Narrow windows scroll the page body.
There is no market-selection override because the existing source service offers
none; the page reports its actual automatic source selection. Unsupported outcome
data is not invented, and no new data-quality metric is calculated for a whole market.

Next recommended milestone: real-client acceptance of Settings 2.0. A8 Item Advisor
and all other mockup-dependent features remain unstarted and require separate scope.

The first comprehensive attempt was interrupted after the newly added catalog
geometry probe failed on the 1000×700 screen: it assumed the third catalog row
was already visible. The probe now asserts the first visible catalog row; the
wide Designer case separately checks an unused field's drag source. Both small
screen cases passed unchanged reachability assertions after this correction.
The interrupted log is retained as
`test-output/workshop-settings-v2/full-interrupted-small-probe.log`; it is not a
complete regression result. The full command was rerun from the beginning and passed.


## Final comprehensive result — PASS

`./tests/run.sh full` completed successfully with exit 0:

- **224 files/modules passed**, 0 failed (216 Lua and 8 Python modules;
  117 Python cases).
- **670 Lua files syntax-checked**, plus runner/simulator Python and shell checks.
- **8 suites passed**: seven native simulator suites plus the lab safety guard.
- **140 launches, 18,047 structured checks**, including the expected negative
  controls, **1,999.917 seconds (33m 20s)**.
- Report: `test-output/verification/full-all-tqkut2h7/report.json`.
  Console: `test-output/workshop-settings-v2/full-final.log`.

| Suite | Launches | Structured checks | Result |
|---|---:|---:|---|
| lab-guard | 0 | 0 | PASS |
| smoke | 2 | 0 | PASS |
| interact | 4 | 244 | PASS |
| diagnose | 6 | 101 | PASS |
| workshop | 25 | 12676 | PASS |
| testlab | 9 | 229 | PASS |
| settings | 58 | 1029 | PASS |
| reminders | 36 | 3768 | PASS |

Final wide Designer capture, simulator-tested and screenshot-reviewed:
`test-output/simlab/artifacts/workshop-snOk9To9/design.png`.
All full-run settings captures: `test-output/simlab/artifacts/settings-YXkiPsS3/`.
The checkpoint sections above locate the four tabs, six editing poses, actual
preference integration, narrow window and scale-0.8 captures.

The native verdicts retain their classified simulator API failures; this pass
means the assertions and scenario verdicts held, not that the real client was
exercised. Known font, pointer, scrolled geometry and large-database limits remain
as listed above. No release, deployment, metadata/library changes or A8 work.
