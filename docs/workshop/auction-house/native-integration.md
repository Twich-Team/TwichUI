# Integrated Auction House (Experimental)

The existing five-page Auction House now has a Host-owned auctioneer context.
**Default replacement is off. Forever acceptance remains pending.** This is a
supervised test implementation, not release readiness or permission to publish.
Live searches and explicit purchase/post/cancel review controllers are implemented.
The owner has requested integrated purchase and posting activation for in-game
iteration. These four modes are enabled in `AuctionBuild.integrated`, separately
from the still-empty native `verified` evidence. Cancellation remains disabled.
Every purchase/post requires player confirmation; unavailable purchases may refresh
listings for a revised review, with no automatic spending or posting. Market Companion
and saved market contracts are unchanged.

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
Every entry to integrated presentation selects live Browse without sending a query, avoiding an implicit
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

## Normal owner workflow

Install TwichUI normally and follow the [short procedure](development-test.md).
Workshop's **Use TwichUI Auction House (Experimental)** setting and
`/tui ahdebug on | off | status` are the ordinary entry points. The existing
`ui.auctionDebug` preference is retained across reloads and profiles, off when
missing, and inactive while Workshop is disabled. Presentation has no build gate.
`auction/Build.lua` separates owner-requested integrated buy/post activation from
per-operation native verification. No acceptance evidence is inferred from activation.
The obsolete custom development archive builder has been removed; ordinary release
and internal packaging include the feature within the existing seven addons.

Debug presentation has no acknowledgement requirement or 30-second limit. The
old `/tui ahproof` lifecycle harness remains an optional developer tool.
`/tui ahproof restore` remains emergency recovery. Combat, genuine interaction,
competing ownership and native restoration guards remain in the same Host.

## Five pages and controllers

- Browse sends supported live queries only on Search, Inspect, More or Refresh.
  Filters form the native query. Saved prices are never substituted in live mode.
  Matching responses are bounded to 500 normalized rows; oversized/invalid/truncated
  snapshots remain partial, completed zero responses are empty, and failures/timeouts
  are unverified. Passive partial-result events update the current snapshot.
- Shopping offers Quick buy from actual missing quantities. Individual item
  buyouts review one item at the native buyout price; available stock is not a stack.
  Commodity Review total requests a native quote directly from the player's click,
  then requires Confirm bound to the displayed quote version, quantity and total. Purchase
  completion never decrements the plan speculatively; actual bag changes reconcile it.
- Sell uses selected bag identity, unreserved stock, native mode/count/deposit,
  `AuctionPrice.Check`, vendor warning/hold and duration. Both item and commodity
  competition can be searched explicitly. Confirmation rechecks bag quantity,
  identity, money, price/deposit and vendor value. Native warning acceptance is a
  separate player action, scoped to the sole pending draft.
- My Auctions explicitly refreshes owned data. Cancel reviews native permission,
  exact ID and cancellation cost, then revalidates. Repost preparation retains only
  this visit's intent: cancel separately, retrieve mail yourself, then review a fresh
  bag draft. Disappearance never confirms a sale. Multisell waits for its full result.
- Market retains its research/history/chart services and contracts.

`auction/Actions.lua` owns one transient reviewed intent, bounded completion
listeners and one cancellable deadline. Dispatch occurs only from explicit UI/native
warning acceptance. Events reconcile; they cannot send transactions. Foreign native
calls, lost visits, errors or timeouts invalidate ownership; unknown outcomes require
checking Blizzard before a new visit. A definitive unavailable/failed purchase can
refresh listings and open a revised review; a further player click is required.
Commodity retries request a fresh quote before a separate purchase confirmation.
Read refreshes wait on the existing throttle-ready event; no transaction queue exists.

Read events have no request IDs. Correlation is serialized local intent plus native
item identity, never advertised as server-token correlation. Foreign reads/timeouts
poison attribution until a fresh visit. Leaving with a read pending can require a new
visit, rather than attributing its late reply to a different search.

## Native activation gates

The ordinary installation enables opt-in presentation and read workflows. The
owner-requested buy/post iteration now enables the four corresponding modes via
`AuctionBuild.integrated`; cancellation remains gated. `AuctionBuild.verified` is
still empty. The current changes are syntax-checked only: unit, mutation, simulator
and packaging checks are deferred at the owner's request until in-game iteration
succeeds, and must run before merge. Runtime permission, appearance and completion
behavior still require actual Forever evidence.

| Mode | Implemented call/review | Exact remaining native evidence |
|---|---|---|
| Item buyout | `PlaceBid(id, exact full buyoutAmount)` | Hardware/permission behavior in this window; ID-correlated completion and rejection |
| Commodity purchase | `StartCommoditiesPurchase(itemID, quantity, unitPrice)`, quote, second-click `ConfirmCommoditiesPurchase` | Matches the native frame call (the generated documentation lists two arguments); confirm runtime signature/permissions, exact quotes and completion ownership in Forever |
| Item post | `PostItem(location, duration, quantity, nil, unitPrice)` and guarded `ConfirmPostItem` | Existing Sell from Bags native warning/hardware path in this integrated window; multisell completion |
| Commodity post | `PostCommodity` and guarded `ConfirmPostCommodity` | Deposit, native warning, hardware permissions and completion in this window |
| Cancel | `CanCancelAuction`, `GetCancelCost`, `CancelAuction(id)` | Native permissions/cost and ID-correlated cancellation completion |

No simulator or offline test may set a production native acceptance claim. The owner-requested activation above is not inferred from presentation or read tests.

## TSM comparison

The packaged TSM 4.15 Forever-compatible source was not present in this workspace.
The public [TSM-derived AuctionUI reference](https://github.com/Keoo88/TradeSkillMaster-3.3.5-backport/blob/fd89c63cdc13646447eaea301e0d456ede094458/TradeSkillMaster/Core/UI/AuctionUI/Core.lua)
was inspected read-only at `fd89c63cdc13646447eaea301e0d456ede094458`.
It is not evidence of TSM 4.15 behavior. No TSM or Blizzard code was copied.

| Public reference concept | Forever/Host decision |
|---|---|
| Independent auction window and return action/tab | Reuse the five-page shell and Host's same-visit return control |
| Auctioneer lifecycle ownership | Preserve the sole Host visit/restoration authority and genuine interaction checks |
| Native root reduced to scale `.001` | Retain anchor-only parking; leave native scale/input/parent untouched |
| Unregister native show events | Do not adopt: preserve native initialization and close/bag/popup behavior |
| Native close interception on an older path | Do not adopt; normal explicit close restores first, then uses `HideUIPanel` |

Native root OnHide closes the interaction, which is why hiding cannot implement a
same-visit switch. The current reversible anchor backend meets the presentation
needs; no additional backend is justified by the available evidence.
