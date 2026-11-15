# Auction House refinement

Current integration status: see [PR #19 integration verification](integration-verification.md).
The branch now includes `feature/workshop` `572da3a`; focused verification passes
and the smoke failure is diagnosed/corrected. The new comprehensive run still
exits 1, now on the existing Workshop guild-bank timing/replay checks. The
original campaign and its earlier failed full result are preserved below.

Task branch: `codex/auction-house-ux-revision`, based on verified
`feature/workshop` `8c1ffad9fb08e91d95c6d921e9e3b4543fe05b0c`.
The task branch also includes `feature/workshop` `5b6e4e9` via a normal merge
(`d8327dc`): approved pricing fixtures/documentation only, with no runtime changes.
No transactions, automatic queries, takeover or desktop synchronization.

Implementation and reviewable draft publication are complete for the safe portions
of this campaign. Unit/feature checks and all 215 market mutations pass. The full
Cloud run completes 241 offline files and 191 launches / 30,221 structured checks,
with nine simulator suites passing and smoke alone failing on a documented native
simulator voice-settings error. Both isolated smoke comparisons pass afterward;
the full result remains FAIL. Real-client, original-mockup and activation gates
remain open, as detailed below.


## Checkpoints

1. Fix Browse/Market catalog ownership, metadata updates, cancellation and diagnostics.
2. Clarify saved/live search and native category hierarchy.
3. Clarify Shopping sources with existing artwork and concise controls.
4. Refine Sell competition, money inputs, stack quantity and financial summary.
5. Refine My Auctions states and Market presentation.
6. Inspect simulator captures, run regression/mutation/performance verification,
   publish a draft PR to `feature/workshop`, retain client gates.

## Loading diagnosis and implementation

Both page stamps included an ever-increasing metadata counter. Browse also
counted unrelated metadata and bag/native events. Discovery reads item metadata;
late responses changed that stamp while a job was running. The previous fix
let the job finish, but the next render immediately discovered the stale stamp
and cleared/rebuilt all rows. Market explicitly scheduled that next render.
Sustained metadata could therefore finish and rediscover indefinitely. Existing
tests stopped their storm at completion and did not check continued stability.
This reproduces a defect consistent with the client report; the specific client
trace remains unrecorded and requires follow-up Diagnostics.

Metadata now queues deduplicated identities, patches only changed information,
and adjusts filter membership without rediscovery. Full candidate membership
includes filtered-out items. Completed catalog identities are reused by local
filter projections; filter changes during discovery wait for that job, then
project the latest controls. Cooperative merge sorting and the 20,000-item bound
remain. Genuine backing-store/generation changes invalidate; fresh read facades
from `Prices.Market` do not. Refresh retains rows until replacement, except when
the actual market changes. Selection/top identity/offset are restored. Hidden,
superseded and timed-out jobs are explicitly canceled and stale callbacks cannot
adopt results. Shared Strategy subscriptions are visible-only and coexist with
Workshop/Shopping observers.

Diagnostics exposes bounded discovery/projection/metadata/patch/paint/invalidation
counters, terminal counts, active jobs and longest slice through the existing
Auction House gauges. No unbounded logging, data writes or metadata request loop.

Unit regression: 6,000 items on each page; sustained duplicate and unrelated
metadata before and after completion; repeated bag events; late filtered names;
selection/top identity/offset; filter changes during discovery; generation
refresh; interleaved page switching and abandoned timers. Existing callback
failure, source failure, timeout, cap, arithmetic and stale-session tests remain.

## Reference and verification limits

Only the pasted request was attached. The five original approved mockups and
real-client captures are absent from both attachments and this repository.
The existing shell and integration.md fidelity ledger are available references;
no direct image comparison with missing attachments can be claimed.

Current Forever source was fetched read-only on its `forever` branch; the
simulator separately reads pinned `ca8368f2` / 1.60.1.70532 objects. No reference
source, simulator binary/source, proprietary game assets, PNG baseline, third
party addon or real SavedVariables is edited.

The environment was initially the separate TwichUI-Market checkout. The target
addon was cloned independently. Lua 5.1/bitop/rsync are extracted from authenticated
Debian packages into a workspace-only runtime. The existing simulator setup
verifies the pinned v0.1.37 release and ICU/ALSA hashes. Elevated execution is
needed for nested Bubblewrap; a workspace launcher adds an empty tmpfs `/mnt`
parent before the original `/mnt/c` mask because this host lacks that mountpoint.
All original read-only binds, isolated writable state and no-network namespace
are retained. These are setup files outside the repository, not shipped code.

Evidence to date: baseline fast Auction House 12/12; loading fast 13/13,
including the new sustained-pressure test; no-assets smoke passes both launches
and 56 page constructions. Subsequent checkpoint and final results are recorded below.
Cloud captures are structural only; client fonts/assets/input and actual runtime
auction behavior require the unchanged local/client acceptance gates.

The independent before/after replay against the original Git revision fails on
both pages at the first post-completion metadata delivery; the revised code keeps
6,000 results through 50 continued deliveries on each page. Completion callback
exceptions (including row patches after coroutine completion) now have a terminal
error boundary and an explicit regression case. A retained selection is never
injected into a different catalog as an extra item; only explicit cross-page
item focus can add a missing identity.

First broad feature attempt: 58 offline files pass and the four lifecycle proof
launches pass. The preview catalog was not accepted: extra report files created
during capture correctly failed its status guard. Its unchanged verdict additionally
caught an obsolete zero-observer expectation (Browse now owns one) and the extra
selected identity described above. Both are corrected; the exact one-observer
bound still detects leaked Shopping listeners. All existing 109 assertions per
pose, replay, wrong control and image checks remain. Verification now runs on a
frozen source copy, so independent work cannot change its repository status.

Two targeted catalog mutations are killed by assertions, without invalids,
survivors, timeouts or infrastructure errors. A broad 200-mutation market run was
interrupted after 118 kills to defer its full repetition until Sell arithmetic is
integrated. This is partial evidence, not a 200/200 score.

### Loading checkpoint accepted in Cloud

`feature auction-house --profile cloud`: PASS, 58 offline files, 31 preview
launches / 3,379 structured assertions, four unchanged lifecycle-proof launches /
431 assertions, 1,113.532 s. Both Git index trees were exactly
`fd472c9d946c73baab434306c3de93a036453fe0` before the report-only update.
Every original pose/assertion, replay, deliberate wrong control and PNG check
ran with a stable repository guard. Report:
`TwichUI-checkpoint1/test-output/verification/feature-auction-house-vviyj47g/report.json`.
This is simulator/unit evidence, not real-client or full local visual acceptance.

## Browse, Shopping, Sell and My Auctions refinement

Browse's primary action is now **Search Saved Data**. The secondary prepared-live
query is explicit and remains broker-gated. Saved tables label seen quantity and
estimated aggregate value; live item responses retain exact totals independently
of rounded unit prices, and grouped minima remain distinct. Views copy broker
records rather than annotating its snapshot. Full-key selection, stale epochs,
late live metadata and variant exclusions have dedicated regressions. Local
filter edits return to saved research, and switching to live cancels any pending
saved job. No broad query runs on opening, selecting, filtering or changing pages.

Native category names, hierarchy and filter IDs are retained. The 222-unit tree
uses 42-unit rows, indentation, expanding chevrons, wrapping and full-name
tooltips. The top dropdown and side tree share one category state; selecting a
descendant expands its ancestors. Before Blizzard's category data loads, the
fallback is honestly titled Saved item groups. Duplicate quality buttons were
removed. Name and ascending/descending observed-price sorting reuse discovery.
Unknown prices sort last. The query builder refuses invalid level restrictions
instead of dropping them into a broader query. Continuation remains deferred.

Shopping uses the existing auction gavel, vendor coins, crafting hammer,
collection pouch and inventory backpack artwork with adjacent source text.
Auction rows have a restrained accent. The planner and player's source choice
remain authoritative; acquisition buttons and cross-page Browse routing still
work. Quantity, source, cost and Needed For are shown once; uncertain prices,
unknown availability, stale plans and bank-stock qualifications remain visible
or in the existing evidence tooltips.

Sell now has bag inventory on the left, posting preparation in the center, and
competition/Advisor/history on the right. Selecting a stack defaults quantity to
its usable maximum; Max uses **only that stack**, capped by the native available
count when known. Locked, bound, reserved, pending-plan and known-ineligible
items cannot supply a usable maximum. No combining, splitting or item movement
is introduced. Binding/eligibility and quantity semantics still need client proof.

Gold, silver and copper are separate digit-validated fields with native
`coin-gold`, `coin-silver`, `coin-copper` atlases and tab traversal. Silver/copper
are 0–99, the internal total is integer copper and the existing money bound and
proceeds overflow checks apply. The inputs have no Search decoration. Deferred
native text callbacks preserve a programmatically copied price's provenance and
selected tier; manual edits clear that match. Hiding the page releases its rows,
references and work, including callbacks that arrive after hiding.

Competition is either clearly historical aggregate tiers or an attributable
current experimental response. Live copying requires the selected exact key,
matching bag identity, market backing/generation, request intent, visit epoch,
snapshot identity, age under 30 seconds, a complete response and known external
ownership. Own/account rows are excluded; unknown ownership, bid-only prices,
partial responses, duplicates, stale/foreign rows and unsupported bonus-ID
identity cannot provide a live match. Historical tiers never become exact stacks.
A row click or lowest-price button only edits the draft. No undercut is added.

Existing Sell/Item Advisor policy supplies a default only with supported evidence,
valid context and no protected crafting materials. Tentative evidence stays
qualified; far-below-usual competition suppresses automatic filling. Partial live
results cannot fall back to a historical posting suggestion. Historical medians
are not substituted for live competition. Reset and Use suggested price reuse
this policy. Find competition is an explicit, gated item-mode request; selection
never sends it. Commodity transport and arbitrary bonus-variant matching remain
unavailable pending client evidence.

The summary separates price per item, quantity, gross **if sold** and deposit
**upfront**. Deposits use only the appropriate native quote for an exact valid
draft and current gated context with known money precision; zero is distinct
from unknown. A whole-silver auctioneer rounds the quote upward to silver,
matching Forever SellFrame.UpdateDeposit and the unchanged posting controller.
Rounded overflow and unknown precision leave the quote unavailable. Duration uses
native index 1–3 and localized labels, with no invented hour mapping. No verified
prospective commission API exists in the inspected Forever contract. Commission,
net and refund treatment therefore remain unavailable/unverified. Deposits are
not subtracted as a permanent fee. Posting has no handler and stays disabled.
The old working Sell from Bags controller is unchanged.

My Auctions retains its layout, differentiates unavailable/loading/empty/partial
responses and shows one list-state message. Refresh is explicit and only enabled
in an available broker context. Own status is reported as returned; disappearing
listings never become inferred sales. Variant details exclude base-item advice.
Cancel and Repost have no handlers. Market keeps the stable catalog and its
tracking, selectors, range controls and gap semantics; its chart is larger and
repeated provenance text is shorter.

## Screenshot review and comparison limits

**Screenshot-reviewed, simulator fixtures only.** The generated catalog retains
all original poses and adds saved-discovery loading, gated native preparation
and historical Sell competition. Sell's existing poses now contain exact-key
synthetic bag/competition/deposit fixtures; the fixture does not activate the
production broker or transaction paths. Every pose retains the original checks
and adds 21 Sell checks (130 total, nine steps), including the deferred-callback
regression. The deliberate wrong expectation, independent replay, image checks
and existing narrow error classifier remain mandatory.

The earlier simulator Sell screenshot has a raw-copper field and a largely empty
preparation column. The refined capture has three denomination fields, Max,
competing rows, matching controls and a readable financial summary. Expanded
categories have separate rows/chevrons; Shopping source icons keep text labels;
Market's larger chart retains gaps. Full-size and narrow/scaled captures are
reviewed for structure and clipping. Simulator inspection found and fixed the
FontString chevron API misuse, hidden Sell callback resurrection and delayed
match-label loss. This is not real-client appearance acceptance: cloud has no
proprietary item/coin art and falls back from addon fonts. Pointer, wheel,
keyboard, localization, actual client art and UI scale need the client run.
Original approved mockups and real-client screenshots were not provided, so no
direct match to those images is claimed.

## Real-client acceptance procedure — still pending

1. Record build, locale, resolution, UI scale and other AH addons. With the read
   gate off, open `/tui ahpreview` away from an auctioneer and during a normal
   native AH visit. Observe that opening, selecting, local filtering, scrolling,
   changing pages and Max/price edits issue no native query or transaction.
   Native Blizzard access and the existing lifecycle proof remain separate.
2. Follow **all** acceptance/recovery steps in [lifecycle-proof.md](lifecycle-proof.md)
   before considering live replacement. Do not enable takeover as part of this
   refinement. Record actual native interaction, input, combat/reload, restoration
   and coexistence evidence; synthetic lifecycle success cannot close that gate.
3. Under owner-supervised read-only testing after lifecycle review, load Workshop
   and explicitly opt in **before a fresh visit**:
   `/run TwichUI.Workshop.AuctionReads.EnableExperimental(true)`.
   Close/reopen the auctioneer normally. Check both interaction-context booleans,
   broker epoch, event timing and request ownership. This opt-in is ephemeral,
   disabled by default and is not a release switch.
4. In separate fresh visits, explicitly click Prepare live search for a narrow
   localized item/category/quality/exact-name/sort query; Inspect live listings
   for a returned item group; Find competition for a verified item-mode bag
   stack; and Refresh listings for owned auctions. Capture the native cache and
   corresponding events once. Compare item keys, quantity, bid/buyout, exact
   total, rounded unit, owner/account flags, completeness and returned metadata.
   There are no request IDs: the one-request-per-kind/visit rule stays intact.
5. Exercise timeout, close/reopen, a foreign native query, same-key delayed event,
   partial response, duplicate rows, old snapshot and expiry. The broker must
   refuse ambiguity/repeats, cancel safely and require a fresh visit; no automatic
   retry or continuation. Never infer ownership from itemID or display a saved
   tier as an available live listing. Verify market identity at faction and
   neutral auctioneers before claiming their partitions match.
6. For bags, check exact variant/link/key, lock/binding, crafting reservations,
   native item/commodity classification and `GetAvailablePostCount` semantics.
   Inspect Max on one stack only, native duration labels, copper precision and
   read-only deposit quotes at each supported duration/quantity. Test unknown
   quote and zero separately. No prospective cut/refund assumptions or net should
   appear. Do not click old or new Post, buy/bid, cancel or repost controls.
7. Leave metadata arriving after catalog completion and across page switches.
   In Diagnostics, record catalog starts/completions/cancellations/errors/active,
   projections, metadata, patches, row updates, paints, invalidations and longest
   slice. Ordinary late events must not create another discovery generation,
   empty the viewport, grow pooled frames or move selection/top identity. Hide
   releases jobs/listeners; a genuine saved-market generation refresh completes
   once. Capture an actual client trace if the original symptom persists.
8. Check native artwork/font/localized long names, tooltips, denomination tabbing,
   category expansion/scrollbar, row clicks, price provenance after deferred
   text events, narrow/scaled layouts and all page scrollers with real input.
   End the experiment with
   `/run TwichUI.Workshop.AuctionReads.EnableExperimental(false)`, close the AH,
   and verify normal native operation. Any taint, lost interaction or ambiguity
   keeps the gate closed; use the documented lifecycle recovery path.

Deferred: real-client acceptance, live activation, commodity detail transport,
continuation, bonus-ID comparison beyond the verified four-part key, authoritative
commission/net/refund semantics, original-mockup comparison, and all transactions.
No buying/bidding/posting/cancel/repost, automatic takeover/search, Market desktop
sync, Gold Ledger, Recipe Guide redesign, separate chart engine or AH-7 activation.

## Large-data and failure-control evidence

Paired offline replay against `8c1ffad` and the final production code, identical
6,000-item catalogs and 20 changed-metadata deliveries after completion:

| Page/revision | New catalog generations | Viewport clears | CPU total | Pooled rows |
|---|---:|---:|---:|---:|
| Browse before | 20 | 20 | 6,058.011 ms | 8 |
| Browse after | 0 | 0 | 14.152 ms | 8 |
| Market before | 20 | 20 | 6,283.754 ms | 8 |
| Market after | 0 | 0 | 58.536 ms | 8 |

Both versions preserved selected/top identity after each finite completion;
the original still cleared on every delivery. Neither grew frames. The separate
persistent-pressure proof keeps delivering metadata rather than waiting for each
rebuild, and reproduces the original post-completion failure on both pages.
The unit regression additionally verifies that offscreen metadata paints no
unrelated rows and visible metadata patches its exact pooled frame without a
list reconstruction.

The existing 20,000-item benchmark passes on both revisions: 418 operation-bounded
catalog slices, eight pooled rows, no frame growth across ten Market/Shopping
switch pairs, zero native AH operations and hidden jobs/events/selected cache all
zero. Initial catalog CPU totals were 1,006.197 ms before / 1,125.979 ms after;
maximum slices 31.371 / 115.184 ms. This offline harness has no advancing native
slice clock, so those maxima do not establish the client's 2 ms target. A second
paired measurement with an advancing CPU clock, during concurrent verification,
completed in 923 / 684 slices, 2,206.316 / 1,345.084 ms total, with maximum slices
57.033 / 24.862 ms. Native calls and garbage collection can exceed a cooperative
boundary. **No native frame-time budget or general discovery-speed improvement
is claimed**; record actual client longest-slice Diagnostics before acceptance.
The measured functional improvement is removal of repeated discovery/clearing.

The first final mutation attempt stopped before classifying any mutant because
the unchanged history baseline exceeded its default 120 s deadline. That same
baseline passed the feature runner in 128.229 s. The complete mutation rerun uses
the existing `--timeout 300` option, unchanged workloads/assertions and disposable
copies. Earlier interrupted campaigns and baseline failures are not included in
the final mutation score. All 332 mutation patterns validate after updating two
stale exact-text patterns to the refined source; the unrelated-metadata assertion
is stronger and checks that no irrelevant work is queued.

Screenshot review found that the eight-item loading fixture finished before the
image was taken. The corrected fixture uses a real catalog with 6,000 additional identities with one
item per discovery slice and explicitly asserts active discovery/empty initial
results. It changes no production loading code or failure classifier. The simulator drains zero-delay callbacks within one manual-clock tick, so
the capture-only fixture schedules those callbacks on separate 0.05-second ticks.
The actual discovery, deadline and completion code remains unchanged. It adds
one loading-pose assertion beyond the 130 common assertions, and is included in
the comprehensive final run. The earlier feature image is not loading-state
screenshot evidence.


The long-name Market capture also exposed heading clipping. The header now uses
the existing native two-line FontString pattern with room for category/source
labels; an additional metadata-pose assertion checks native truncation and text
height. Both native checks pass in Cloud, but its image still crops this extreme
long-name fixture. After two presentation attempts, no further simulator/font
workaround was added. Full text remains in the item tooltip. Native font wrapping
and localized long names are an explicit real-client acceptance item, not claimed
visual acceptance. The baseline's overlaid Issue report label and missing native
item/coin art also limit interpretation of Cloud captures.

Before/after screenshots compare layout over synthetic fixtures; their item and
price values are not a market-price comparison. The earlier loading capture was
rejected as screenshot evidence rather than relabeled as a passing loading state.

## Verification ledger

| Check | Outcome |
|---|---|
| Final fast Auction House | 16 files pass, 13.268 s after deposit-precision review |
| Fast market | 12 files pass, 179.085 s |
| Fast settings | 23 files pass, 17.122 s |
| Fast shared UI | 9 files pass, 0.610 s |
| Integrated feature Cloud | 61 files pass; 34 preview launches / 4,420 checks; four lifecycle launches / 431 checks; 1,248.842 s |
| Market mutations | Final 215/215 killed: 210 assertions, five runtime errors; no survivors/invalids/timeouts/infra or source drift; 1,218.9 s with timeout 300 s |
| Focused Sell mutations | 14/14 killed by assertions after deposit correction; 3.8 s |
| Mutation catalog | 332/332 patterns validate |
| Final focused captures | Loading 131/131; Market metadata/truncation 131/131; narrow Market 130/130 |
| Final Auction House catalog within full | 34 launches / 4,422 checks pass, 939.712 s; common original assertions, replay and negative control retained |
| Comprehensive Cloud | **FAIL**: 241/241 offline files and 704 Lua syntax checks pass; 9/10 simulator suites pass; 191 launches / 30,221 structured checks; smoke alone fails on forbidden `voice-settings-unsupplied`; 7,123.143 s |

The integrated feature run precedes the capture-only loading correction and
Market heading presentation change. Those received focused simulator/fast checks
and are included in the final comprehensive run. A final native-contract review
then caught the missing whole-silver deposit rounding rule. Its correction adds
zero/overflow/unknown-precision regressions and two mutations; the comprehensive
run was restarted rather than accepting the interrupted result. All runtime, tests and tool
files in the 1,394-file verification manifest match the frozen full checkout:
SHA-256 `c33b6dfc12de288daedf34674bc00354a5ff6d11f17043de234a6aa57d6d9ac3`.
The manifest covers core, Workshop, Diagnostics, Settings, Test Lab, tests and
tools; subsequent report/publication edits do not change verified code.

Artifacts (local workspace, ignored and not committed):

- Feature: `TwichUI-final-verification/test-output/verification/feature-auction-house-zor8_k96/report.json`
- Feature screenshots: `TwichUI-final-verification/test-output/simlab/artifacts/auctionpreview-EeoPpMFA/`
- Final Auction House catalog: `TwichUI-final-verification/test-output/simlab/artifacts/auctionpreview-J6GUXaQR/`
- Corrected loading: `TwichUI-final-verification/test-output/simlab/artifacts/refinement-loading-nOU3atbe/loading.png`
- Heading check: `TwichUI-final-verification/test-output/simlab/artifacts/refinement-marketmetadata-kVO4IvFv/marketmetadata.png`
- Mutations: `TwichUI/test-output/refinement-market-mutations-complete.json`
- Paired benchmarks: `twichui-env/paired-benchmarks.log`, `twichui-env/advancing-clock-benchmarks.log`
- Full: `TwichUI-final-verification/test-output/verification/full-all-ivkazc66/report.json`

## Published checkpoints

Draft PR: https://github.com/Twich-Team/TwichUI/pull/19, target `feature/workshop`.

- `e088afc`: loading root cause, stable catalogs, diagnostics and pressure regression.
- `d8327dc`: incorporate the current base's approved fixtures/documentation without rewriting history.
- `f8ab833`: saved/live distinctions, native categories, local sorting and affected-row updates.
- `0248d3b`: Shopping source artwork and concise acquisition presentation.
- `d411afd`: Sell competition/money/quantity preparation, My Auctions states, Market polish and integrated regressions.
- `be45000`: native whole-silver deposit precision, unknown-precision/overflow safeguards and two additional mutation cases.

The shared Sell/Owned/Market simulator fixture changes ship together so code and
its consumer assertions remain coherent. All commits are pushed normally; the
PR remains a draft and is not merged. No release or deployed-client edit occurred.

## Local before/after screenshot index

These ignored workspace artifacts are not repository assets. Before images are
from the accepted loading checkpoint, before the visual refinement. Every image
uses synthetic fixtures; none is a supplied real-client screenshot or mockup.

| Page | Before | After |
|---|---|---|
| Browse saved data | [Before](../../../test-output/auction-refinement-review/before/browse.png) | [Populated](../../../test-output/auction-refinement-review/after/shell.png) |
| Native categories | [Before](../../../test-output/auction-refinement-review/before/categories.png) | [Expanded](../../../test-output/auction-refinement-review/after/categories.png) |
| Shopping | [Before](../../../test-output/auction-refinement-review/before/shopping.png) | [Source cues](../../../test-output/auction-refinement-review/after/shopping.png) |
| Sell | [Before](../../../test-output/auction-refinement-review/before/sell.png) | [Current fixture](../../../test-output/auction-refinement-review/after/sell.png), [historical tiers](../../../test-output/auction-refinement-review/after/sellobserved.png) |
| My Auctions | [Before](../../../test-output/auction-refinement-review/before/owned.png) | [Populated](../../../test-output/auction-refinement-review/after/owned.png), [partial empty](../../../test-output/auction-refinement-review/after/ownedempty.png) |
| Market | [Before](../../../test-output/auction-refinement-review/before/market.png) | [Populated](../../../test-output/auction-refinement-review/after/market.png), [sparse history](../../../test-output/auction-refinement-review/after/marketsparse.png) |

Additional reviewed states: [loading](../../../test-output/auction-refinement-review/after/loading.png),
[Browse empty](../../../test-output/auction-refinement-review/after/empty.png),
[gated native preparation](../../../test-output/auction-refinement-review/after/liveprepare.png),
[narrow Browse](../../../test-output/auction-refinement-review/after/small.png),
[narrow Shopping](../../../test-output/auction-refinement-review/after/shoppingsmall.png),
[narrow Sell](../../../test-output/auction-refinement-review/after/sellsmall.png),
[scaled Sell](../../../test-output/auction-refinement-review/after/sellscaled.png),
[narrow Market](../../../test-output/auction-refinement-review/after/marketsmall.png),
[scaled Market](../../../test-output/auction-refinement-review/after/marketscaled.png),
and [long metadata heading / Cloud wrapping limitation](../../../test-output/auction-refinement-review/after/marketmetadata.png).


### Comprehensive smoke exception and isolated comparison

The final full run completes every offline file and then reports a smoke failure:
`C_VoiceChat.CanAccessSettings: settings access has not been supplied`. The existing
[known failure catalog](../../../tools/simlab/known_failures.py) describes this
native simulator behavior, its no-addon reproduction, and the absence of an
A_Admin setter. Smoke's existing contract permits only the narrowly identified
group-hello UTF-8 error, so it correctly rejects this voice error. Initialization,
all 56 settings-page constructions, pixels/textures and process exits otherwise
pass. No classifier, required error, negative control or assertion is relaxed.
The full result is **not green**. Every default catalog completed. Serial isolated
smoke runs then passed on both unchanged base `5b6e4e9` and final source, each with
two launches and all 56 described pages constructed. Both used the existing Cloud
setup and unchanged error contract. The comprehensive failure did not reproduce
in either isolated run; no deterministic baseline failure or timing cause is
claimed. These clean retries do not replace or waive the failed full result.

Comparison logs: `twichui-env/unchanged-base-smoke.log`,
`twichui-env/final-isolated-smoke.log`, `twichui-env/smoke-contrast.json`.
Artifacts: `TwichUI-baseline-verification/test-output/simlab/artifacts/smoke-ZWWJZDKy/`
and `TwichUI-final-verification/test-output/simlab/artifacts/smoke-fuDSduS0/`.
No simulator repair, new shim, native API override, error allowance, skipped
assertion or PNG-baseline update was introduced to turn the full result green.
A clean comprehensive run remains an infrastructure/client acceptance follow-up.


### Complete Cloud catalog results

| Suite | Launches | Structured checks | Verdict |
|---|---:|---:|---|
| lab-guard | 0 | 0 | PASS |
| smoke | 2 | 0 | **FAIL** |
| interact | 4 | 244 | PASS |
| diagnose | 6 | 101 | PASS |
| auctionproof | 4 | 431 | PASS |
| auctionpreview | 34 | 4422 | PASS |
| workshop | 38 | 19997 | PASS |
| testlab | 9 | 229 | PASS |
| settings | 58 | 1029 | PASS |
| reminders | 36 | 3768 | PASS |

The deliberate wrong controls count as structured checks; their expected failures
remain required for a passing suite. No suite timed out. Cloud explicitly leaves
`local_milestone_passed=false`. The 1,394-file manifest still matches the published
code byte for byte after all catalogs finish; source drift is empty. No baseline
PNG, error classifier, release version, native posting controller, lifecycle proof
or user SavedVariables was modified.
