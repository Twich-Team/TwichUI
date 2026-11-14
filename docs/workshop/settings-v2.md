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

Implementation and verification results will be recorded here as checkpoints
complete. The original tooltip designer saves immediately; checkpoint 2 replaces
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
