# AH-0: Implementation roadmap and acceptance gates

Research completed 2026-11-14 on `feature/workshop`, starting at `13aa14f1`.
This is the handoff for **separately authorized** implementation. AH-0 adds
documentation only. Do not automatically begin AH-1, C1 or another feature.

AH-1a follow-up: the disabled diagnostic lifecycle proof is implemented and
offline/simulator verification is recorded in [lifecycle-proof.md](lifecycle-proof.md).
Real Forever acceptance remains pending; AH-1b and all functional pages are blocked.

Read [API capabilities](api-capabilities.md), [architecture](architecture.md),
[integration and mockup fidelity](integration.md), `AGENTS.md`, `CLAUDE.md`,
[testing](../../testing.md), [testing performance](../../testing-performance.md)
and [Workshop verification policy](../testing-roadmap.md) before implementation.

## Investigation plan and result

The investigation followed four bounded checkpoints:

1. Establish clean branch/HEAD/upstream; inspect the pinned Forever branch,
   generated API contracts, Blizzard lifecycle/call sites, existing auction
   code and read-only reference addons. Produce a source-evidence capability
   matrix and separate native/runtime unknowns.
2. Design lifecycle/fallback, load-on-demand boundaries, shared shell, state,
   request ownership and performance; prioritize the Hide-closes-AH constraint.
3. Map the five reviewed images to existing Workshop engines and honest data
   requirements; define new adapters without new market schemas or optimizers.
4. Produce independently testable milestones, client gates and validation
   commands, verify the research documents and push reviewable checkpoints.

Result: **conditionally feasible**, with APIs sufficient to build all five
pages' core workflows. Actual replacement safety and consequential-action
permissions have not been established in a real client. No simulator result can
remove those gates. The source-backed findings, architecture and handoff are
complete; the future client gates are not AH-0 implementation work.

## Implementation readiness

| Page | Classification | Ready scope | Gate before enabling consequential use |
|---|---|---|---|
| Browse | Contract-ready; runtime-gated | Group/detail search, filters, current records, stored comparisons, tracking | AH-1 restoration; request ownership; mode-specific purchase completion/restrictions |
| Shopping | Engine-ready; acquisition adapter needed | Existing plan/stock/dependencies and supported source alternatives | Current plan and actual item mode; individual buy consent, excess quantity and delayed delivery |
| Sell | Engine/safeguard reuse ready; controller extraction needed | Bags, quantity/price/duration drafts, qualified Advisor and gross/deposit | Bag race validation, posting/warning permissions, native batch outcomes; arbitrary stack size unsupported |
| My Auctions | Read contracts ready; reconciliation/cancel gated | Active owned listing records, precise-or-banded expiry, qualified comparison | Actual owned event completeness, manual cancellation/cost; sale ledger and sell rate deferred |
| Market | Read-only services ready; presentation adaptation needed | Stored observations, values/provenance, quality, supply and gaps | Large-list/view performance and truthful chart range; demand/seller-population/forecast claims unsupported |

## Bounded development sequence

Every checkpoint below requires the relevant verification and a working
fallback. “Working” may mean a read-only page with unsupported actions clearly
disabled. Do not release an enabled mode that has not passed its client gate.
Continue between sub-checkpoints only within that future campaign's authorized
scope. Commit/push then requires that campaign's authorization, as AH-0 has here.

| Milestone | Concrete scope and dependency | Acceptance / usable stopping point |
|---|---|---|
| **AH-1a — Lifecycle and fallback proof** | Core Host with explicit transient diagnostic command, reversible anchor-only parking and independent Restore button; no saved switch, Workshop load, replacement root, shell, searches or transactions. See [proof contract and evidence](lifecycle-proof.md) | Offline/simulator recovery proof only; disabled default retained. Real Forever lifecycle acceptance pending, including combat deferral limitation; AH-1b blocked |
| **AH-1b — Approved shared shell** | Header, left five-page navigation, empty page bodies, responsive sizing and common style; depends AH-1a | Five destinations match approved shell; Browse default; repeat navigation/close doesn't grow frames/listeners; Blizzard switch reachable at constrained sizes; no fake financial data. This completes AH-1 |
| **AH-2a — Browse reads** | Request broker, normalized group/detail snapshots, filters, sorts, metadata, explicit continuation, selection and read-only comparison; adapt old targeted search to same owner. Depends AH-1 | Current query/state shown accurately, partial scope visible, throttles and timeout handled, no overlapping own searches, no buy action armed from stale/foreign result; existing Sell from Bags still works |
| **AH-2b — Explicit buying** | Separate item buyout and commodity quote flows; optional bidding can be a later small addition. Transaction harness, immutable preview, exact totals and completion. Depends AH-2a and each mode's client evidence | Test whole-record item buyout first; commodity mode remains disabled until signature/classification validated. Every operation needs consent; no retries/automatic next purchase; disappeared listings and quote change/expiry refuse safely |
| **AH-3 — Shopping** | Adapter to Session.ShoppingPlan/Stock/Strategy plus selected-row searches and individual purchases; depends AH-2b | No second plan or DB; ready/planning/basic preserved; queue/stock changes invalidate consent; exact missing quantity or disclosed excess; bought/in-transit is not in bags. Footer uses Review/Next purchase, not unattended Buy All |
| **AH-4a — Sell drafts and shared safeguards** | Extract reusable draft/validation controller behind existing tab and new page; bag list, runtime mode, price/quantity/duration, Advisor and deposit. Depends AH-2a | Old tab retains below-vendor hold and identity binding; no regression in its existing workflow; new draft edits never post; unsupported stack-size control replaced honestly; reservations and tentative advice retained |
| **AH-4b — Manual posting** | Post, server warning consent, created/multisell/error reconciliation; depends AH-4a and posting client gate | Exactly one validated submission from player; optional warning invokes correct new pending draft once; canceled/changed consent submits nothing; partial batch shown; timeout unknown; no automatic undercut/post loop |
| **AH-5a — Owned records** | Owned snapshot provider, completeness, ID reconciliation, exact/banded expiry and optional current competing reads; depends AH-2a | Accurate owned rows and stable selection; lower comparable external competition only gives qualified undercut; disappearing ID never means sold; sales stats unavailable |
| **AH-5b — Manual cancel and repost preparation** | Explicit cost-aware cancel intent and matching completion; prepare Sell after actual item return; depends AH-5a and AH-4b for repost | CanCancel/cost rechecked; cancel success requires ID evidence; no automatic cancel loop or post after event; separate Post click, uncertain results stay unknown |
| **AH-6 — Market and shared chart adaptation** | Approved tracked-list/fact/trend layout over existing services, sparse-history presentation, bounded shared one-metric chart adaptation; depends shell, Facts and tracking; no transaction dependency | Actual observation ranges/gaps and buckets, accurate metric names, honest competition/supply/quality, no demand or forecast; existing Workshop charts unchanged by default; C1 remains deferred |
| **AH-7 — Final integration and polish** | Five-page cross-navigation, accessibility/scale, failure recovery, coexistence, large database, regression and supervised acceptance | All enabled modes pass client gates; five images reviewed at real UI scale; full verification tier passes; release readiness reported without publishing a release |

Prefer this sequence for a functional minimum. AH-5a and AH-6 can be read-only
follow-ups if a consequential mode remains client-blocked, but don't skip the
shared lifecycle gate or make the disabled mode appear functional. Avoid adding
a new generic scheduler, new market database, transaction ledger or C1 engine.

## Risks and decisions

| Rank | Risk / evidence | Mitigation and decision gate |
|---|---|---|
| Critical | Blizzard root Hide closes AH (FRAME:OnHide); parking can interact with panel layout/input/bags | AH-1a restoration experiment + genuine repeated open/switch/combat checks; keep default off until passed. No global no-op/OnHide replacement |
| Critical | Restricted APIs and native click rules not exposed completely in Lua | Central explicit-action boundary, no programmatic action dispatch, typed draft/consent, real supervised transaction check per mode |
| High | No request IDs; same-key late replies, generic events and foreign addon queries | Serialized owner, bounded reads, context epochs, ambiguity disables action, no automatic transaction retry; yield to competing AH owner |
| High | Warning popup delegates to Blizzard sell drafts while new draft has another owner | AH-4b specifically verifies no wrong-draft/double confirmation and safe cancel/close |
| High | Forever commodity classification and quote signature discrepancy | Read-only classification first; supervised quote before spending; enable item/commodity modes independently |
| High | Bag movement/locks, late metadata, duplicate counts and crafting reservations | Revalidate live location/GUID/count; shared Stock/Strategy; stale/unknown means no armed action |
| High | Native money range exceeds safe arithmetic; unit versus total/precision | Preserve exact server totals, existing guarded bounds, rational comparison where appropriate, fixtures for non-divisible totals and max range |
| High | A8.1 viewport reset and large-history/catalog stalls | Stable ID+offset, cooperative work including sorts, pooled rows, Facts/valuation caching, selected-detail-only work and diagnostics |
| Medium | Faction/neutral partition and exact expiry/duration/cut not proven | Keep unknown market distinct; runtime labels/bands; no hard-coded cut or precise expiry; client observation gates |
| Medium | Mockup implies sales/demand/unique seller metrics unavailable today | Apply integration fidelity ledger; unavailable or qualified observations in same layout, no fabricated analytics |
| Medium | Optional addon hooks/layout ownership and downstream combat taint | Single gated hook installation, minimal state lease, no Tabs mutation, default-off coexistence policy and real reopen/combat test |

Recommended decisions are specified, so no routine owner answer blocks AH-0:
start default-off; enable automatically on visits after opt-in; reset each new
visit to Browse; support per-operation clicks; preserve manual scans; use runtime
quantity semantics; defer sales ledger and C1. Owner review is needed before the
next implementation campaign, and before changing any of those product/safety
boundaries. Technical unknowns are assigned to the milestones above, not
presented as optional acceptance work.

## Test infrastructure and command plan

Current commands/groups are defined by `tests/run.sh`, `tests/groups.json` and
`docs/testing.md`. There is **no current `auction-house` group or new transaction
harness**. The Workshop testing roadmap's M10 is planned for this implementation,
not already built. Add it in AH-2b alongside the first consequential path.
Use synthetic fixtures only; a “buy” fixture changes fake state, never the game.

For future code changes, add new tests and core auction syntax paths explicitly
to appropriate existing groups. `workshop` already selects `test_workshop*.lua`;
`core` does not automatically select a newly named `test_auction_host.lua`, and
its syntax globs originally did not cover every auction subdirectory. AH-1a now
adds the Host/old auction tests and auction syntax explicitly to `core`, plus the
`auctionproof` simulator to feature-core and full verification. Check `--list` after
editing group definitions so new tests actually run in the intended tier.
The old auction price/window tests are not assumed covered by a fast Workshop
group: run them directly or add them to the appropriate feature dependencies.

Existing commands available now, selected according to the future change:

```sh
./tests/run.sh fast core
./tests/run.sh feature core
./tests/run.sh fast workshop
./tests/run.sh feature workshop
./tests/run.sh fast crafting
./tests/run.sh feature crafting
./tests/run.sh fast market
./tests/run.sh feature market
./tests/run.sh fast item-advisor
./tests/run.sh feature item-advisor
./tests/run.sh fast settings
./tests/run.sh feature settings
./tests/run.sh full
```

These are alternatives by scope, not an instruction to run all of them before
every commit. Run fast checks during editing, the relevant feature tier before
code checkpoint commits, and full for major implementation milestones/shared
high-risk code as documented. Full includes serial simulator runs and is about
28 minutes in the current recorded baseline; do not run it for AH-0 docs only.
After any Lua edit run `luac5.1 -p '<file>'`. Money/quantity/ordering/eligibility
logic changes also need realistic new mutation entries and the matching existing
`bash tools/mutate.sh --group market` or `--group crafting` campaign. Do not
claim a mutation group covers new transaction semantics without fixtures.

Existing direct checks, from the repository root:

```sh
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_auction_price.lua)
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_auction_window.lua)
```

Use repository-local `bash tools/simlab/run.sh ...` entry points; the sibling
simulator installation and source remain read-only. New scenarios are added to
TwichUI's scenario files and group selections, not the separate simulator repo.
No source build/patch is implied. Simulator limitations are explicit below.

## Required fixture and verification matrix

| Behavior | Offline / simulator checks | Genuine client gate |
|---|---|---|
| Lifecycle/fallback | Duplicate/open/late load/close/disabled event permutations; missing or partially initialized Workshop; injected build/render/park failure; repeat restoration; no load when off | NPC distance, real event order, actual frame/panel/input behavior, Escape/bags, trial condition where applicable |
| Search/filters | Group→detail, class/quality/exact/local stack filters, nil metadata, empty vs partial; explicit continuation cap, quota/readiness/drop/failure | Actual results/filter meanings, required-level label, readiness/minute throttle, page sizes |
| Stale data | Old visit/old query, same-key late replies, foreign send, changed auctionID/price, cached record removal | Listing expires/sells during preview; no unintended substitute purchase |
| Price normalization | Unit/total distinction, non-divisible total, nil buyout, own quantity, precision step, out-of-range/secret/NaN refusal | Copper support and server accepted amounts; BigUInteger representation |
| Shopping | Reference-model inputs; stale/basic/ready state, bank scope, shared reservation, delivery pending, excess from whole listing, changed queue | Bag delivery delay and no duplicate acquisition; vendor and recipe launch behavior |
| Posting | No side effects from render/search/suggestion; bound draft, below-vendor hold, warning accept once/cancel, moved slot, low money, partial batch | Deposit, allowed duration/mode/count, native warning/restriction/completion; no accidental second post |
| Purchase | One explicit action per spend, quote unavailable/changed/expired, delayed/missing confirmation, no retry, own item refusal | Actual item buyout ID completion; commodity quote signature and success; delayed delivery |
| Owned/cancel | Incomplete snapshots, vanished ID→unknown, Sold→not collected; cost/CanCancel changes, matched cancel, timeout, return pending | Real owned timing/expiry/quantity; one supervised cancellation and returned item |
| Advice/tooltip | Policy 2 levels, gain/margin, reservation and variant refusal, missing disenchant evidence, no duplicate tooltip hook | Real item tooltip identity, pointer/modifier state and native data arrival |
| Charts/history | No observations, one day, gaps, buckets/window edges, range/metric labels, bounded textures and no hidden-page work | Real fonts/scale/readability; avoid invented continuous 14 days |
| Large database/scroll | 3,000/6,000/20,000 identity fixtures as appropriate; selected item/top identity+offset stable across metadata and page return; bounded slices/pools/cache/listeners | Diagnostics on real frame budget; native wheel, scrollbar drag, dropdown positioning and hit regions |
| Combat/reload/coexistence | Mock restrictions, profile/disable teardown, old callback refusal, no action restored from save | Secure/taint checks in combat and after AH close; reload; Auctionator/TSM present/absent; open other panels |

The simulator can establish handler/state behavior with fake APIs and structural
frame construction. It cannot prove hardware-event restrictions, taint/combat,
server delivery/event ordering, actual pointer reachability, visual fidelity or
reload persistence. Capture only sanitized counts/build/timing and evidence
labels in diagnostics; avoid names, owner lists, links and personal market data.

## Real-client acceptance runbook (later, player supervised)

**None of these actions was performed during AH-0.** This checklist is for later
authorized implementation with the player controlling every transaction.
Use low-value items and a small agreed spending limit. Never drive it through
an unattended probe, macro loop or programmatic button click.

1. Record `GetBuildInfo`, loaded AH addon and available relevant API types using
   a bounded read-only diagnostic. Existing Test Lab `cases/Client.lua` and
   `cases/Api.lua` offer presence/read-only/guided infrastructure; inspect actual
   cases before invoking. Type presence alone is not a behavioral pass.
2. With replacement off, open/close a real auctioneer twice. Confirm original
   Browse/Sell/Auctions, bags and Escape still work and Workshop does not load
   solely for disabled replacement. Repeat with Workshop unavailable/disabled.
3. Enable replacement outside combat. Open: TwichUI Browse and all five nav
   destinations are reachable. Switch to Blizzard and back several times;
   original controls, bags, mouse/keyboard focus and price fields remain usable.
   Close, walk away, reopen and check default Browse and no stuck offscreen UI.
4. Search a common inexpensive item by text/category/quality/exact name. Compare
   with Blizzard results, inspect detailed K/quantity/total and mode read-only.
   Check incomplete results/Load more and a late item-name load without scroll
   reset. Verify the level filter's true meaning.
5. Under explicit player control, preview one inexpensive **item** auction.
   Verify exact ID/whole quantity/total, cancel once, then confirm one purchase.
   Observe matching completion, money change and delivery separately. Repeat
   commodity quote checks only if the item really classifies Commodity; resolve
   the two-versus-three-argument signature before confirming any commodity buy.
   Change quantity/allow quote expiry and verify a new consent is required.
6. Choose a low-value unbound bag item. Compare validity, available count,
   precision, duration labels and deposit with Blizzard. Edit draft, test Cancel
   and the below-vendor consent if practical. Only after player agreement,
   click Post once. If warning appears, accept/cancel explicitly; verify created
   ID or native batch count and owned state, never just the API return value.
7. View that owned listing: check quantity, time/band and comparable competition.
   Player requests Cancel, checks any cost and accepts once. Require matching
   cancellation evidence; wait for item return. Repost may only prepare a new
   draft, with a separate player Post; no need to repost to pass cancellation.
8. Let a preview become invalid or arrange a benign unavailable listing; test
   failed search, throttled read or timeout with safe fixtures/observation where
   a real condition cannot be produced. Do not spend repeatedly to manufacture
   failures. Stale/unknown state must offer refresh/reconciliation, not retry.
9. Test reload while idle in both modes, leave/reopen, profile disable, and
   controlled build/render error recovery. Ensure no intent resumes after reload.
   Check actual combat behavior and taint both at the AH where practical and
   after leaving it. Any unreachable fallback blocks enabling the feature.
10. Repeat lifecycle with optional AH addons absent/present, preserving their
    settings. Confirm conservative conflict fallback instead of layout fights.
    Check at different UI scales/constrained height with real pointer scrolling,
    dropdowns, tooltips and all five images side by side. Capture Diagnostics
    for a large observed database and repeated navigation.

Never parse localized notifications into financial records. If sale data is
later investigated, inspect owned Sold status and seller invoice fields read-only;
pending invoice, expected payment and actually collected money are distinct.
Do not add a ledger or fill a universal cut constant from one unvalidated example.

## AH-0 verification and checkpoints

AH-0 intentionally changes only these four Markdown files. Static validation
checks source locators/important API names against the pinned source, checks
local document links and whitespace, reviews the full diff, and verifies no
production/testing-infrastructure/supporting repository changes. No Lua edit,
schema change or runtime diagnostic is necessary to establish the source facts.

- **Source-verified:** pinned Forever generated contracts and UI functions;
  modern reference-addon parking pattern read only. No server or client runtime
  semantics were inferred as a verified test result.
- **Screenshot-reviewed:** all five supplied reference images, as visual targets.
- **Static checks passed:** `git diff --check` / `git diff --cached --check`;
  Python validation of 19 client source locators at the pinned clean revision,
  key API names, OnHide closure, documented throttle and quote-signature
  discrepancy; 34 cited Workshop function definitions; all local document
  links/anchors, balanced fences and existing test-group names. The changed-file
  scope is exactly the four requested research documents.
- **Unit-tested baseline only:** `./tests/run.sh fast item-advisor` passed
  **2 test files, 0 failures**, 45 Lua syntax files plus runner checks, no
  simulator suites, **0.441 s**. Both direct commands above for
  `test_auction_price.lua` and `test_auction_window.lua` printed **PASSED**.
  These check the cited existing Advisor/posting safeguards, not a new UI.
  The runner report is ignored at
  `test-output/verification/fast-item-advisor-xd98dp7_/report.json`.
- **Not tested:** replacement in simulator or real client, pointer/taint/combat,
  native restrictions, transactions, runtime performance and visual acceptance.
  Full/feature simulator suites are not required by this documentation-only scope.
- API research checkpoint: `e5bc58d7`, committed and pushed to
  `origin/feature/workshop`. Architecture/integration/roadmap follow in the final
  research checkpoint; final hash and push verification are reported in the chat
  to avoid a document trying to contain its own commit hash.

No remaining AH-0 blocker requires owner input. The next recommended authorized
task is **AH-1a: lifecycle and fallback proof**, with real-client acceptance
before consequential actions. Stop here for review.
