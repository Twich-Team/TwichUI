# AH-1a: lifecycle and fallback proof

Date: 2026-11-14. Scope: diagnostic lifecycle infrastructure only. No replacement
window, pages, transactions or scan policy changes. **Real-client acceptance is
pending; native replacement is blocked.** The proof must stay disabled by default. Later authorization permits the independent [presentation preview](presentation.md); it does not accept this lifecycle mechanism or activate replacement.

## Source review and decision

Reviewed on clean `feature/workshop` at `b89f84b9`. Forever source is read-only
`../wow-ui-source`, branch `forever`, revision
`4cd0ab752a77164f654ccbca9d0c1fe8dafceebe`, version `1.60.1.70888`.
Locators below are relative to its `Interface/AddOns/` directory. These are
**source-confirmed contracts**, not real-client evidence.

| Concern | Evidence and consequence |
|---|---|
| Opening/load order | `Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseUI_Bootstrap.lua`: registers Auctioneer with the interaction manager; loads the addon then calls `ShowUIPanel`. The TOC is load-on-demand. Leave this path and its trial restriction intact. Activation must inspect an already loaded, visible root; never manufacture a session or load the native UI itself. |
| Availability | Generated `PlayerInteractionManagerDocumentation.lua`: SHOW/HIDE carry interaction type and are synchronous; `IsInteractingWithNpcOfType` and `IsValidNPCInteraction` return booleans. Generated `AuctionHouseDocumentation.lua`: SHOW/CLOSED/DISABLED events have no payload. Relative ordering between event families and actual server usability remain unverified. Require both interaction checks; visibility alone is insufficient. |
| Show effects | `Blizzard_AuctionHouseFrame.lua`, `OnLoad`, `OnEvent`, `OnShow`: initializes tabs, queries bids at addon load, may query favorites on show, selects Buy, opens bags, registers events and plays sound. Moving a shown root must not invoke Show again. Native queries are distinct from proof-issued queries. |
| Hide effects | Same file, `OnHide`: unregisters events, clears posting, resets Browse, calls `C_AuctionHouse.CloseAuctionHouse`, hides popups/progress and closes bags. Hiding the root or a parent is unsuitable for presentation switching. A post-hook cannot prevent that close. |
| Structure/input | `Blizzard_AuctionHouseFrame.xml`: root under UIParent, initially hidden, mouse enabled, portrait template; search, sell/buy views and tabs descend from it. Ancestor hiding affects effective visibility. Moving it does not disable child keyboard focus, handlers, timers, narration or detached popups. |
| Panel positioning | `Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua`, `FramePositionDelegate:UpdateUIPanelPositions`, `ShowUIPanel`, `HideUIPanel`: secure delegation and repeated ClearAllPoints/SetPoint; local getter lazily initializes layout attributes. The proof should change anchors only, avoid all panel attributes, and yield when layout changes rather than continuously repark. |
| Combat/protection | Same panel functions check protected-function permission. Frame APIs mark many mutations protected. Lack of a secure template on the AH root proves nothing about descendants, hooks or future taint. Refuse takeover in combat; retain a failed/deferred restoration for retry outside combat. Never queue takeover. |
| Existing TwichUI hooks | `auction/Window.lua`: independent Sell from Bags holder, native display/overlay hooks and explicit posting state; `auction/Scan.lua`: explicit searches. Refuse proof while the custom page or any known scanner is active. Do not cancel or hide a posting operation as part of activation. |
| Workshop | `WorkshopLauncher.lua`: lazy guarded service load, optional delayed login load, no window opened by Load. Workshop `Window.lua` only subscribes while shown; `AuctionButton.lua` can attach to native AH after service load; `Scan.lua` checks native visibility; `WorkshopAuto.POLICY` is manual. Host should neither load Workshop nor duplicate its observation/scan listeners. Test loaded and unloaded cases. |
| Other AH owners | Read-only TSM `LibTSMWoW/Source/Service/Move.lua`: Forever lock checks, pending restoration, offscreen anchors, panel attributes and position hooks. This corroborates the idea, not compatibility. Refuse known loaded AH owners; unknown hooks/layout changes remain possible. No code copied. |

**Decision:** test anchor-only parking of the already shown native root with an
independent diagnostic Restore button. Compared with Hide/hidden-parent/alpha-0,
this avoids known interaction closure or invisible onscreen click regions.
Compared with registry replacement or TSM-style panel mutations it leases less
state and does not claim another owner's registry. It is only a candidate:
the native UI still occupies a panel slot and can be hidden or repositioned by
Blizzard. If the test cannot keep interaction and input usable, reject the
mechanism; do not suppress OnHide, replace globals, or force a position fight.

## Risks and acceptance boundary

- Offscreen descendants may retain focus or bindings; independently positioned
  popups/tooltips and narration/gamepad navigation may escape root geometry.
  Refuse an AH-focused edit box, observe real input and accessibility behavior.
- Different scales, resolution changes, clamping, skin offsets and external
  anchors can defeat parking. Preserve scale and all original anchors, refuse
  clamped roots, check root geometry and monitor only while the proof owns it.
- Secure hooks do not establish taint safety. Real combat, blocked actions,
  Escape, bag behavior and later reopen require client acceptance.
- Out-of-combat restoration can be immediate; no promise of immediate protected
  frame restoration in combat or after arbitrary engine/addon corruption is
  possible. A retained restoration and recovery instructions are essential.
  Deferred restoration is a **release blocker**, not acceptance of the AH-0
  switch-at-any-time contract.
- Restore only owned anchors. Preserve another owner's later anchors; do not
  clobber external scale, parent, input, panel attributes or scripts. No automatic
  reactivation after a close, error, combat, login or reload.

## Implemented lifecycle contract

`!!!TwichUI/auction/Host.lua` is the only presentation owner. It loads after the
existing posting window. `/tui ahproof` prints help; `on` attempts one lease,
`off` (or `restore`) releases it, and `status` reports its current fixed reason.
There is no saved switch, replacement root, page construction or Workshop load.
Opening, login and reload never activate it. Reopening needs another explicit
`on`. This deliberately narrows the AH-0 proposal for AH-1a.

Activation requires both auctioneer predicates, a visible native root directly
under UIParent, idle native Browse/Buy mode, no native buy dialog/overlay, no
focused descendant, no current Sell from Bags page/post, no known TwichUI scan,
no known competing AH owner, no clamping/protected root and no combat. Missing
or throwing APIs refuse activation. The known-owner list is conservative and
incomplete: TSM, Auctionator, Auctioneer, AuctionLite and aux-addon. It is not a
general addon-compatibility guarantee.

Before mutation, create/show one independent, clamped UIParent button labeled
**AH-1a proof: Restore Blizzard (30s limit)**. Capture every native anchor, parent
and scale. Change only anchors: native TOPLEFT to UIParent TOPRIGHT +4096 units.
An interrupted button setup is retried on the same hidden frame and must finish
before a later activation can lease native anchors.
Check that it remains visible, has the leased anchor and is beyond the viewport
using effective scales. Do not change scale, alpha, parent, mouse/keyboard,
strata, scripts, tabs, globals, interaction ownership or panel attributes.
The one post-OnHide callback is installed lazily, once per native root; it only
releases an existing lease and cannot prevent native closure.

One 0.25 s ticker checks the lease for at most 30 seconds outside combat. It
restores on timeout, lost context, hidden/replaced native root, hidden recovery
control, known competitor, busy page, focus, clamping, parent/scale/anchor or
geometry changes. Close/disabled/auctioneer-hide/leaving-world, addon load,
resolution/scale change also restore. No panel hook continually reparks it.
Duplicate end events are harmless. Returning to Blizzard never calls Show,
Hide, ShowUIPanel, HideUIPanel or any auction API. Closing never resurrects it.

Restoration cancels the ticker first. If the parked anchors are still owned,
restore the complete original list; if another writer changed them, yield and
preserve those anchors. Parent/scale changes are observed but never overwritten.
Each original SetPoint is attempted even if an earlier anchor failed. A failed
restore retains its snapshot and recovery button for an explicit retry. A later
foreign move also ends a partially restored lease. Own errors go to `R.Fault`
and the normal game error handler; no global error handling changes or Blizzard
error suppression. A foreign owner can still put the frame somewhere unusable:
yielding is not proof that its geometry is safe. Close/reopen/reload are then the
recovery path, and such a client result fails acceptance.

Combat refuses all takeover and native restoration mutations. Combat entry
cancels watching and retains a pending lease; combat exit retries restoration
only. A close during combat still preserves the snapshot until safe cleanup.
The control stays present but cannot restore anchors until combat ends.
**This does not satisfy production switch-at-any-time recovery.** Do not enable
a replacement or begin AH-1b based on this deferred path. The 30-second limit
also cannot override combat protection or a failed engine operation.

Diagnostics scopes: `auction.proof`, `auction.proofWatch`; gauges
`auction.proofLease`, `auction.proofTimer` (0/1). No retained item records,
transaction intents, history, additional saved data or unbounded log are added.
The only existing posting-window change is the read-only `LifecycleBusy` guard.

## Automated evidence and limits

The offline test drives the real core command/event router and Host with
synthetic frames, interaction booleans, timers, fault injection and auction APIs
that fail if called. It covers initial/default behavior, 100 repeated switches,
all anchors at a nondefault scale, command/button fallback, closed/reopen,
fresh-load state, missing prerequisites, independent event families, combat
deferral, partial activation/restoration errors, foreign writers and retry.
The existing posting-window test checks its new lifecycle busy guard.

`bash tools/simlab/run.sh auctionproof` runs four independent fresh processes:
Workshop unloaded, identical replay, real Workshop loaded without building its
window, and one deliberately wrong expectation. It uses real Host code,
simulator frames, timers, core handlers and Restore button. The auctioneer
predicates, native root/display mode, native close effects and combat flag are
**synthetic**. A bounded query/scan/transaction sentinel must observe zero calls.
Injected own errors are observed explicitly in the fixture; the global error
handler and existing simulator-error classifier stay untouched. Replay and the
negative control are required for a pass. Native frame API float precision is
handled by comparing captured scales exactly, not by weakening preservation.

This proves handler/state recovery, not native AH search or usability. The
simulator uses older Forever UI `1.60.1.70532`; source review uses `70888`.
Known voice-settings simulator errors remain visible and classified. Combat,
taint, protected actions, real input, accessibility, addon coexistence, server
interaction and reload persistence remain **not real-client-tested**.

Verification in native WSL (no game deployment or real transactions):

| Check | Actual evidence |
|---|---|
| `./tests/run.sh fast core` | **Unit-tested:** 15 files pass, including 2,619 synthetic Host assertions and existing posting/price tests; 52 Lua syntax files, final run 1.915 s |
| `./tests/run.sh feature core` | **Unit-/simulator-tested:** 24 files pass; smoke 2 launches, diagnostics 6/101 checks, AH proof 4/431 checks; final run 62.219 s, exit 0 |
| `./tests/run.sh full` | **Unit-/simulator-tested:** 227 files/modules (219 Lua, 8 Python/117 cases), 679 Lua syntax files, lab guard plus all eight default simulator suites; 157 launches/25,799 structured checks including intentional failure controls; 2,021.248 s, exit 0 |
| Full simulator catalogs | Smoke 2; interaction 4/244 checks; diagnostics 6/101; AH proof 4/431; Workshop **38/19,997**; Test Lab 9/229; settings 58/1,029; Reminders 36/3,768. No original default selection was narrowed |
| Unexpected intercepted-fault control | A disposable copy of native proof logs with an extra intercepted fault is rejected by the verdict (exit 1), as required |
| Static review | Lua syntax, whitespace, AH document local links, TOC order and changed-file scope checked; reference source remains clean; no third-party, version/interface, market schema or gameplay-policy changes |

The full run preceded final review hardening of interrupted recovery-button
setup and fixture error forwarding. Both were then rechecked by the final fast
and feature-core runs above; all affected production paths and the tightened
simulator verdict pass. The full catalog was not repeated for these local fixes.
Only the intentional injected activation fault is intercepted by the final
fixture; every other fault is forwarded to normal error handling.

Ignored raw evidence: `test-output/verification/full-all-c4eohin0/`,
`fast-core-q0e39_r1/` and `feature-core-bua_czpn/` (the latter two also under
`test-output/verification/`). Each report records exact selection and per-test
logs; simulator paths are in its `report.json`. Initial scenario failures
(missing manual-clock setup, then comparison with decimal literals instead of
captured frame scales) were test-fixture issues and are not passing evidence.
Known simulator errors remain classified, visible and unchanged.

Source-review checkpoint: `536d39b3`, committed and pushed. Implementation and
evidence form the next verified checkpoint; final hash is reported in chat.
**No real-client, appearance, actual addon compatibility, taint or gold-spending
acceptance is claimed.** No release was published.

## Real Forever client acceptance — pending

Use a disposable test session and record `/dump GetBuildInfo()`, UI scale,
loaded AH addons, error/taint messages and each result. Do not change live gold,
post, bid, buy, cancel or start Scan prices. Start without other AH addons and
with Workshop login loading off; repeat later with Workshop already opened and
closed. The proof does not load Workshop itself.

1. Log in/reload, run `/tui ahproof status`: it must report Blizzard/disabled.
   Visit an auctioneer normally. Native AH must open and an ordinary explicit
   native search must work. Return to idle Browse with no popup or focused edit
   box. Record normal geometry and bag behavior.
2. Run `/tui ahproof on`. Native presentation should move away and the labeled
   Restore button should stay reachable. If refused, record the reason; do not
   bypass the guard. Within 30 seconds run this read-only context check:

   ```lua
   /dump C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.Auctioneer), C_PlayerInteractionManager.IsValidNPCInteraction(Enum.PlayerInteractionType.Auctioneer), AuctionHouseFrame:IsShown(), AuctionHouseFrame:IsVisible()
   ```

   All four should be true. This is necessary but insufficient for search proof.
   Optionally issue exactly one explicit read query while parked (no scan):

   ```lua
   /run C_AuctionHouse.SendBrowseQuery({searchString="Copper Ore",sorts={}})
   /dump #C_AuctionHouse.GetBrowseResults()
   ```

   Use a localized known item name if needed; await the browse-updated event
   (for example in the native Event Trace). Cached/nonzero results alone do not
   prove a new response. Record event/response and any native error. No scripted
   polling, continuation, detail sweep or transaction is part of this check.
3. Click Restore immediately. Native AH must return to its exact prior anchors
   and scale with interaction intact. Perform another native search manually;
   verify results, tabs, bag controls, mouse and keyboard. Repeat `on` → `off`
   several times, then let one activation expire naturally. Check narration,
   gamepad/focus, popups and no invisible click interception, including other
   screen areas. A lost interaction or inaccessible control fails acceptance.
4. Activate, then press Escape or leave the auctioneer. Reopen normally: native
   AH must be reachable, with no proof automatically active. Repeat close/reopen
   and resolution/UI-scale changes; a native reposition should end the lease.
5. Reload once while native and once while parked. Both must return to default
   native mode with no persisted proof or resuming action. Visit/reopen and do a
   native search again. This is real reload evidence; fresh simulator processes
   are not a substitute.
6. Check activation during combat is refused. Where the real client allows a
   safe test of combat entry during a lease, verify no blocked mutation/taint,
   native close/Escape or leaving remains available, and combat end restores
   remaining owned anchors. Do not manufacture danger at the auctioneer. If this
   cannot be exercised safely, label it untested and retain the blocker. Capture
   unexpected errors; do not deliberately throw faults into the live native UI.
7. Repeat at different UI scales and with optional AH addons. Known owners must
   refuse activation without moving their UI. Unknown layout changes must end
   the lease without a position fight. Check native AH and bags again after
   closing and entering combat. Offline injection covers controlled failures;
   real error recovery is unverified unless an actual safe failure is observed.

**Recovery:** click Restore or `/tui ahproof off`. In combat, leave the interaction
with native Escape/distance and wait for combat to end; retry `off`. If restoration
fails, close/leave and `/reload`, then reopen native AH. The proof has no saved
enable state. Never run an OnHide/global replacement workaround. Any need for
this emergency route, interaction loss, trapped input or taint is a failed client
gate to investigate before AH-1b, not a passing fallback result.

## Architecture decision and handoff

AH-0 remains a proposed full architecture; this checkpoint implements only
Host's diagnostic anchor lease. It intentionally has no persistent module
switch, automatic visit takeover, Workshop loading, preparing/page states,
return-to-replacement control, shell or request/transaction service. Do not
interpret the absence of those as permission to build them within AH-1a.

**AH-1b cannot safely proceed yet.** A genuine Forever client run must establish
native search/interaction continuity, immediate fallback, close/reopen/reload,
input/accessibility, combat and coexistence. If anchor-only parking fails, the
least-risk alternative is to leave Blizzard visible and use an independent
companion UI; adopting that product change needs separate authorization. Registry
replacement and OnHide suppression remain rejected. Stop at this checkpoint with
the proof disabled; no functional pages or gold-spending tests are authorized.
