# AH-7A: supervised native Auction House integration

The existing five-page Auction House now has a Host-owned auctioneer context.
**Default replacement is off. Forever acceptance remains pending.** This is a
supervised test implementation, not release readiness or permission to publish.
No purchasing, bidding, posting, cancel/repost, automatic searches or scans were
added. Existing manual scan policy, transaction/read gates, SavedVariables and
external Market contracts are unchanged.

## Implementation and ownership

The minimum integration reuses `!!!TwichUI/auction/Host.lua` for both its original
30-second proof and integrated visits. No second native lifecycle controller,
interaction registry override, panel-manager mutation or new addon was added.
`WorkshopLauncher.LoadAuctionUI()` reuses Workshop consent, load/error handling,
Resume and `workshop.load` instrumentation while deferring optional native scan
button attachment. It neither opens the crafting window nor requests Market data.

`W.AuctionUI.Prepare()` builds the existing shell and initial Browse page hidden.
`ShowIntegrated(visit)` requires a current Host visit, preparation state and owned
native anchors. It reuses the five lazy pages, materials, sizing, navigation and
cleanup. `/tui ahpreview` remains independent and does not change native geometry;
asking for preview while the integrated window is already open keeps that context.
Every entry to integrated presentation selects saved Browse, avoiding an implicit
external Market load when returning from Blizzard. Page frames and chart widgets
remain pooled; retained records, jobs and subscriptions follow existing Release
methods. The coalesced shell refresh timer is now cancellable on hide.

| Host state | Meaning and next safe action |
|---|---|
| `blizzard` | Native presentation active; a return button exists only in an explicitly enabled live visit |
| `preparing` | At most one bounded initialization timer; verify genuine interaction/native visibility, guards and recovery, then load/build before any native writes |
| `twichui` | Only owned native anchors are parked; existing independent shell presents this visit |
| `restoring` | Invalidate initialization callbacks, stop watchdog, suspend the integrated shell, restore owned anchors |
| `recovery` | Combat or a failed operation prevented restoration; retain the original snapshot and independent recovery action for retry |

Opening event families share one visit counter. Initialization uses a cancellable
single timer with at most 20 delayed retries over two seconds; duplicate events
cannot repeat loading. Visit and request tokens invalidate stale callbacks, and
each watchdog callback also captures its particular lease. Closing during loading,
construction or presentation cannot resurrect a window. Initial combat refusal
never queues takeover. Combat exit retries restoration only.

Before parking, require both Auctioneer interaction predicates, a shown/visible,
unprotected and unclamped native root under UIParent, idle Browse/Buy, no focused
descendant, known competing owner, native dialog/detached auction confirmation,
multisell progress, Sell from Bags operation or known scan. Missing/throwing APIs
refuse activation. Recovery is established before Workshop preparation; every
native guard is rechecked after preparation. Failure returns to Blizzard rather
than presenting a partially successful replacement.

Only anchors are changed. Native Show/Hide, scripts, scale, parent, alpha, input
flags, interaction manager and panel metadata are not changed by switching.
The active-only 0.25-second watchdog yields on native geometry/owner/focus/busy
changes, hidden controls, lost interaction or unavailable Workshop. A foreign
anchor change ends ownership and is preserved, without repeatedly reparking.
A failed restore retains its complete snapshot and partial restore points for a
later safe retry. UI cleanup errors do not skip native anchor restoration.

The header's **Blizzard Auction House** action restores without closing the
auctioneer. A small independent button near the bottom of the viewport returns
to **TwichUI Auction House** in the same visit. It disappears when the visit ends
or testing is disarmed. It never starts an interaction. Known activation failures
show a retry label and concise tooltip; detailed reason codes are in Host status.
There are no unsolicited chat errors on automatic openings.

Close/Escape first restore native anchors, then call the game's normal
`HideUIPanel` close path only for the same valid native visit outside combat.
This deliberately closes the interaction and invokes native bag/popup cleanup;
it is never the presentation-switching technique. During combat, safe restoration
can be deferred; the independent recovery button remains available. This is a
client acceptance blocker, not a claim of immediate recovery in all conditions.

## Source review

Read-only Forever reference: `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`,
`1.60.1.70938`; simulator reference: `ca8368f2f2380cbe696854f7f2646387c278a61b`,
`1.60.1.70532`. Reviewed native Auction House bootstrap, frame Lua/XML,
BrowseResults, generated PlayerInteractionManager/AuctionHouse documentation and
panel-manager behavior. Native OnHide still closes the auction interaction and
bags/popups, so hiding is unsuitable for switching. No reference code was copied
or changed. Relative native event/server/input timing is still unverified.

## Executable Forever acceptance checklist

Use a development install of this branch and its `TwichUI_TestLab` addon. Preserve
your usual addon installation and data. Record build, scale, resolution, competing
addons, errors/taint, actual pointer behavior and Diagnostics. No test below buys,
bids, posts, cancels, or starts a price scan. Load Test Lab and Diagnostics before
integrated testing: loading another addon intentionally restores Blizzard.

### A. Prove native presentation before enabling integration

1. Reload. `/tui ahproof status` must say test mode off. Visit an auctioneer;
   Blizzard opens normally. Perform one normal read-only native search manually,
   then return to idle Browse with no focus, popup or scan.
2. Run `/tui ahproof on`. The proof may refuse; record the reason and do not
   bypass a guard. If it parks, check within 30 seconds:

   ```lua
   /dump C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.Auctioneer), C_PlayerInteractionManager.IsValidNPCInteraction(Enum.PlayerInteractionType.Auctioneer), AuctionHouseFrame:IsShown(), AuctionHouseFrame:IsVisible()
   ```

   All must be true. Follow the existing [AH-1a read-response procedure](lifecycle-proof.md#real-forever-client-acceptance--pending)
   to prove a new explicit read-only response while parked, not just cached data.
3. Click Restore or `/tui ahproof off`. Verify exact previous geometry/scale,
   ordinary native search, bag controls, focus, mouse, keyboard and tooltips.
   Repeat close/reopen, Escape, natural proof expiry, UI-scale/resolution changes,
   reload, protected/combat refusal and a known conflicting AH addon.
4. Any lost interaction, unusable input, detached popup, blocked action, taint or
   unsafe recovery fails Phase A. Stop there and retain Blizzard as fallback.
   Record evidence in the PR; simulator results cannot satisfy this phase.

### B. Explicit integration testing after A succeeds

Enable Workshop — Experimental through existing Settings, then:

```text
/run C_AddOns.LoadAddOn("TwichUI_TestLab")
/tui perf
/tui ahproof confirm-native
/tui ahproof replacement on
/tui perf start auction 2
```

`confirm-native` is your acknowledgement of the completed Phase A result for
this reload. It is not automated proof, persisted acceptance or a release switch.
Close the Test Lab/Diagnostics windows before visiting the auctioneer.

1. Visit normally: the existing five-page window should open automatically under
   this explicit test gate. Navigate Browse, Shopping, Sell, My Auctions and
   Market. Transactions remain unavailable. No search or price scan starts.
2. Click **Blizzard Auction House**. Search manually using Blizzard; check bag
   windows, tabs, focus, popups/tooltips and native controls. Clear native focus
   and return to idle Browse before clicking **TwichUI Auction House**. Verify
   the same interaction predicates remain true throughout switching.
3. Physically click header controls, each page, dropdowns, scrollbar/scroll wheel,
   tooltips and disabled transaction controls. Check other screen areas for
   invisible native input interception. Repeat at narrow resolution and your
   normal/larger UI scales. A handler invocation is insufficient evidence.
4. For recorded pointer evidence, open `/tuilab`, tick **Auction House pointer
   (guided)**, and run its individual cases, one at a time:
   `ui.pointer.auction-blizzard`, `ui.pointer.auction-return`,
   `ui.pointer.auction-dropdown`. Follow each prompt and press F9 over the target.
   The Lab samples real `GetMouseFoci`; it never clicks or switches an interface.
   Change interfaces yourself between cases. Copy its report. Test Lab content
   steps aside during guided runs; move its prompt if it covers the target.
5. Close with the custom close button and Escape; walk away from the auctioneer;
   reopen ten times. Repeat switching ten times after visiting all five pages.
   Verify no ghost controls, stale jobs/popups/focus or growing frame pools.
   Exercise environmental changes and combat only in an appropriate test setting;
   leave combat and restore if recovery was deferred. Never bypass protection.
6. Record `/tui ahproof status`, `/dump TwichUI.AuctionHost.Snapshot()` and a
   Diagnostics capture covering cold opening, warm switches, restore and repeated
   visits. Existing `workshop.load` and new `auction.switch` scopes identify work.
   Compare timings and frame-time/resource gauges after warming all pages.
7. Emergency stop: `/tui ahproof off` disarms future automatic test visits and
   attempts restoration; `/tui ahproof replacement off` does the same. If deferred,
   leave combat and retry. If another writer owns the anchors, preserve them;
   close/reopen or reload rather than force a position fight.

### C. Default activation remains blocked

Reload resets both acknowledgement and test enablement. There is no saved
replacement setting, schema migration or production default activation in this
milestone. Owner review of successful Forever evidence and separate explicit
authorization are required before changing that policy or publishing a release.

## Automated evidence and performance

Verification completed on 2026-11-17; implementation source is `810e190`.
The final documentation-only commit is reported in the draft PR and delivery.

| Evidence | Result |
|---|---|
| `development auction-preview` on final implementation | **Unit-tested:** 23 modules, 90 Lua syntax files, including the complete performance-engine tests and 4,129 synthetic integrated lifecycle assertions; 10.455 s, exit 0 |
| `feature workshop --profile cloud --measure` on `84d09f8` | **Unit-/simulator-tested:** 87 modules, 217 Lua syntax files; full Workshop 38 launches/20,263 checks and Test Lab 9 launches/229 checks; source unchanged, 1,591.827 s, exit 0 |
| Complete standalone preview on `c413345` | **Simulator-tested:** all 49 launches/6,587 checks, replay and deliberate failure control; 806.074 s, passed |
| Final `auctionproof` catalog on `810e190` | **Simulator-tested:** all four original proof launches plus six integrated launches, 1,217 total structured checks; independent replay, narrow/scaled/restored poses and both deliberate failure controls passed |
| Final `diagnose` catalog on `810e190` | **Simulator-tested:** six launches/101 checks; existing voice-settings and invalid-UTF8 addon-message limitations reproduced and classified, no new error rule or suppression |
| Supplemental scoped-Diagnostics probe on `810e190` | **Simulator-tested:** 134 integrated assertions, 34 collected gauges under the unchanged 40-gauge cap, actual Host state/page-pool/failure reads passed |
| GitHub verification of `810e190` | **CI:** `verify` passed, [run 44196828335](https://github.com/Twich-Team/TwichUI/actions/runs/44196828335); internal publication/build job skipped |

Across these affected checks: 88 distinct offline modules and 113 simulator
launches with 28,531 structured assertions, including expected negative controls.
The full standalone catalog preceded Host-only callback hardening; the final
23-module checks, all 10 Host launches, performance-engine checks and diagnostics
probe cover those changes. Workshop/Test Lab ran on `84d09f8`; their source and
launcher/page behavior are unchanged by the later diagnostics registration/preset
adjustment. This is affected-feature coverage, not full/release certification.

The attempted combined integration run was interrupted by an environment
reconnect after its preview and Host catalogs passed. Its aggregate report remains
incomplete; it is not represented as a passing combined profile. The remaining
Workshop/Test Lab catalogs were rerun in the completed feature profile above.
An earlier development run invalidated by a concurrent edit, initial fixture
replay/count issues, and supplemental probe setup failures are retained as failed
or incomplete evidence; no failed assertion was relaxed to obtain the final pass.

### Synthetic timing and retention

One supplementary run with real Workshop loading and Diagnostics present measured:

| Measurement | Observed |
|---|---|
| Native-opening event to presentation | 50 ms of manual simulator clock; not CPU/wall latency |
| First Workshop load call | 23.059 ms |
| Warm cached load call | 0.006 ms |
| Native activation/parking | 0.084 ms |
| Restore and integrated cleanup | 2.219 ms |
| Warm return to TwichUI | 1.808 ms |
| Warm repeated switching | Zero frame growth; five pages, four pooled list rows, ten visible listeners, one shared subscription in the empty-data integration fixture |
| Closing | Zero pending page jobs, page listeners, refresh/initialization timers and shared subscriptions; watchdog cancelled |

Operation costs use `debugprofilestop` in the simulator. These are synthetic
empty-data measurements, not predictions of real-client loading or frame time.
The existing chart tests also preserve native-line and texture/stroke pool bounds.
Captures were screenshot-reviewed for the existing layout and reachable header,
normal/narrow/scaled sizing; no redesign or real-client appearance approval is
claimed. `shell.png` is the standalone capture; `integrated.png`,
`integratedsmall.png`, `integratedscaled.png`, `integratedblizzard.png` are the
integrated catalog captures. Raw logs/captures and the supplemental fixture remain
in ignored local test output, with exact build identity recorded in the delivered
archive manifest.
Synthetic timing is not native frame-time or server latency. Structural simulator
captures do not validate real fonts, real pointer/keyboard, bags, gamepad/narration,
combat protection, taint, server session preservation or actual addon coexistence.
A restored-native simulator image depicts a clearly labeled synthetic native
boundary, not Blizzard's real Auction House. Those remain mandatory client checks.

Diagnostics adds `auction.switch`, state codes 0–4, pending initialization timer,
activation/failure/restoration-failure/switch counters and last opening, first load,
load, activation, restoration and switch milliseconds. Existing proof watchdog and
preview page/listener/row/job/subscription gauges remain; the cancellable preview
refresh timer is counted as well. Use `/tui perf start auction 2` for the scoped
**Auction House lifecycle** preset: Host gauges and seven passive
`auction.lifecycle_*` resource projections fit within the existing 40-gauge limit.
These scoped builtin gauges do not displace legacy core/settings selections. No separate diagnostics subsystem was introduced.
