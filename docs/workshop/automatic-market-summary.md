# Workshop Market data integration — review candidate

This candidate connects delivered Market references to the Workshop calculations,
tooltips and embedded charts described under [Workshop price consumption](#workshop-price-consumption).
It uses the existing Companion beta.10 data format and preserves local scanning.
The following testing steps apply to this candidate; the delivery-only checkpoint
below is historical context.

## Testing this branch

1. Use addon branch `feature/workshop-market-consumption` with Companion beta.10.
   Sync the intended market, then reload the UI. Newly installed addon folders may
   require restarting WoW once for discovery. Saving refreshed data does not require
   closing the game.
2. In Settings → Workshop, inspect **Pricing source**, **Companion market** and
   **Loaded Market generation**. The chosen market's faction must match the character
   or current auctioneer; region/ruleset come from the selection in Companion.
3. Check a known base material and a recipe using it in Opportunities, Crafting and
   Shopping. Market prices must be marked as reference estimates, including amounts
   for multiple items. Advisor, bag tooltips and embedded charts should identify
   Market versus local observations. Market charts require delivered history and
   retain gaps where observations are missing.
4. Inspect Browse/Sell comparisons without buying or posting. Market references must
   not replace live offers or become a suggested posting price on their own.
5. With the generated `TwichUI_MarketData` addon disabled and after a reload, verify
   manual local scans, saved history and ordinary Workshop functionality still work.
   Keep saved data intact. Unknown item variants should stay unpriced rather than
   borrowing the base item's value.

## Historical automatic-delivery checkpoint

Owner-authorized source-only coordination with Market draft #31. Addon baseline `36697b14f2283303a926e5a068330916a3ec6381` includes the advanced Market charts. No release/version stamp, SavedVariables migration, local history rewrite, pricing-default change, native transaction, native item-link/upstream identity inference or automatic reload.

The Companion obtains a native-authenticated compact projection from genuine server observations, independently of its optional archive. It publishes a small root plus bounded load-on-demand parts to an explicitly authorized installation while WoW is closed. The paired contract is `twichui-workshop-summary` 1, separate from legacy detailed formats 1–3. Market preserves original U1 #21/U2 #22 histories as draft dependencies; the addon activates neither unverified identity mappings nor Advisor decisions.

An active, consented Workshop recognizes only summary-marked root metadata automatically. The root validates closed schema, canonical bytes, SHA-256, source clock, verified market/ruleset/faction and receipt; no whole-catalog startup scan runs. Requested modulo-64 partitions load independently and validate cooperatively before prices are exposed. The declaration is explicitly the current observed exact-variant universe, not all game items or historical-only records. Missing entries remain unavailable. Partition failures retain prior validated data when a previous generation exists in memory. The native publisher verifies the entire generation before installation.

Market server research shows exact-variant recent/minimum/market/historical references, observed variant supply and reference-day support. A unique *server research* variant may be selected automatically; ambiguous variants remain selectable as Observed variant 1/2. This never resolves a bag, equipment or crafting identity. Exact hashes remain in technical provenance. Charts explicitly explain that no detailed series was delivered, while genuine local charts and legacy detailed imports remain available. Local competition, Advisor, crafting queues and pricing defaults are unchanged.

Limits: 64 partitions, each 128 KiB, 8 MiB current raw data, 150,000 rows; capacity overflow refuses the whole generation rather than pruning. One decoded active partition is cached; a previous validated generation may temporarily remain for replacement refusal. Per-addon raw strings cannot be unloaded by Lua. Diagnostics separately report requested-part load, cooperative validation, exact lookup, retained bytes/rows/parts, and fixed A/B partition-addon memory. Native Forever compilation, frame/GC and gameplay acceptance are pending actual client execution.

## Verification in progress

New focused production-reader refusal checks and actual Market presentation tests are implemented. Existing legacy bridge/scoped/advanced-chart negatives are retained. Integration profile: `./tests/run.sh integration market --with-group item-advisor`; source is frozen during certification. Matching market mutations add route, historical-support and exact-variant controls. No installed simulator is available in this environment; attempted applicable scenarios must remain explicitly unverified. Actual Windows-generated artifacts will be run through this production reader and existing Market presentation in the coordinated end-to-end check.

## Owner Forever acceptance (pending)

Use a future verified/signed Companion and coordinated addon candidate after separate release authorization. Sign in, select the normal Market, Connect Workshop once, confirm the automatically detected Forever folder or select it through the native browser. Close WoW and synchronize. Record Companion's published generation, source observation, market/faction and file-write timestamp. Launch Forever, open Workshop Market, select Market server research and record the loaded generation from technical provenance. Compare an exact delivered server variant and its price references. Confirm local scans/history, Advisor safeguards and saved preferences remain intact. Capture diagnostics for root/partition compilation, largest validation callback, retained memory/GC and page responsiveness. Installing files alone does not pass in-game consumption or frame-time acceptance.

Checkpoint D evidence: 66 selected offline integration modules passed on frozen source; simulator Workshop/Auction Preview checks failed to start because no lab exists (also checked conventional installation paths). The later frozen focused Market profile passes 30 modules, including the new summary simulator-source syntax. Three new market-summary mutations are killed; complete market mutation results are recorded below when complete. The initial Market presentation test found a real lazy-load bug: an absent global became boolean false and skipped the partition loader. This is corrected and the actual presentation path now passes. Simulator valid/corrupt/future scenarios are prepared but unexecuted.

Final source checks: the frozen broad market campaign detects **255/255** mutations (547.6 s, two workers). An earlier run was invalidated because source changed and is retained as failed evidence. The later focused lookup improvement has **4/4** targeted mutation detections, including the new regression control proving an item-focused view loads only its required partition. The final selected integration run passes **66 offline modules**, including pricing/crafting/Advisor/legacy/advanced-chart regressions; simulator suites still cannot start because the lab is absent. Simulator catalog expectations are updated explicitly for the three new prepared scenarios. Full CI on the coordinated source remains the completion gate.

Focused research does not enumerate the whole current catalogue: the existing page can show one item after one validated partition. The broad list retains the established visible 20,000-item UI cap; it is distinct from complete delivered current-observed coverage and never truncates the native payload. Ambiguous server variants remain separate and do not auto-select; the tests assert distinct 120/999 copper references for two synthetic exact variants of one item.

## Workshop price consumption

`Pricing.lua` connects the validated delivered summaries to Workshop's existing
feature services. `Session.PriceSource` uses the Companion-selected market for
reference estimates and preserves independent local scans as the per-item fallback.
Overview, Opportunities, queue estimates, Shopping and multilevel strategies use
that service. Advisor and worth tooltips read its reference facts; embedded charts
use actual delivered daily Recent Price observations, with local history fallback.
AH Browse exposes reference comparisons alongside its existing native/stored rows.
Native `Market.Source`, auction listings and all purchase/posting actions retain
their original local/game paths.

Identity is deliberately exact: Market's `backend/market/ingest.py` normalizes an
upstream base item as canonical `{"id":ITEM_ID}` and hashes those bytes with SHA256.
The addon computes that same key and requests that exact record. It does not select
the first or only arbitrary server variant. Native items identified as variants
keep their existing refusal/fallback behavior. Bonus/suffix/modifier variants need
a separately verified mapping before automatic use. No transport/schema change or
new Companion build is required for this base-item integration; beta.10 already
delivers supported contract-2 summaries, and contract 1 remains reference-only.

Admission requires a validated summary, the canonical pricing algorithm, verified
server market metadata, non-synthetic observations no more than 24 hours old, and a
matching current auctioneer/player faction. Region/ruleset come from the market
explicitly selected in Companion; this does not claim independent native realm-to-
server mapping. Explicitly inspected different saved markets remain independent.
Missing, stale, unsupported, mismatched or still-loading references fall back to
local observations, and otherwise remain unknown. They never become zero.

Planning uses server Recent Price as an **estimate**. Server supply is not available
purchase depth, and reference price times quantity is neither a guaranteed total
nor a lower bound on live offers. Such plans carry a reference marker, show estimated
amounts, and do not claim proven savings or a verified optimum against actual
listings. Market minimum/recent/14-day/60-day reference facts keep per-value source
metadata and local fallback. Live competition retains its own local quality/age;
server confidence remains Limited. Reference-only Advisor advice is tentative and
provides no suggested posting price. Worth comparisons cannot declare a proven
vendor/auction winner from a reference. Vendor quotes, stock, recipes, owned
auctions and transaction confirmation remain native observations. Disenchant
uses the separately labeled bundled estimates described under [Disenchant support](#disenchant-support).

Partition/header completion coalesces dependent price/facts/plan refreshes. A
previously checked partition decoded solely for a chart wakes that pending chart
without repeatedly invalidating all plans. The adapter bounds cached compact price
records at 8,192 and retains one selected chart; it never copies delivered history
into local SavedVariables. Capacity exhaustion uses a bounded local/unknown
fallback and does not repeatedly evict/reload the same partitions. `workshop.pricingReferences` exposes the cache gauge.
The settings pricing-source status and per-item facts explain use; a loaded
Companion header alone remains distinct from a feature actually using a reference.

`tests/test_workshop_market_consumption.lua` exercises the actual validated reader
and feature services using disposable input: base matching, pending partitions,
quantity arithmetic, Opportunities, Shopping, multilevel estimates, facts, history,
source labels, tentative advice, action isolation and stale/faction fallback.
Independent repeated-addition examples check reference cost arithmetic. Mutation
cases cover variant/faction isolation, quantity multiplication and certainty claims.
These are offline tests, not real Forever acceptance. Reload persistence, native
pointer behavior and final visual appearance still require the actual client.

### Consumption verification and limits

Unit-tested with the existing Lua 5.1/bitop runtime in rootless Docker. The broad
first pass ran 279 modules: 275 passed and four artwork checks failed because this
new checkout initially omitted tracked `assets/`. Materializing those unchanged
tracked inputs resolved all four checks (21 Python cases plus the map-tool module).
The first complete affected Workshop run passed 73 modules; the final affected
run including the multi-partition regression passed 74 modules and syntax checks.
No simulator suite or real-client test is claimed: the local simulator installation
and Forever UI source are unavailable on this host.

The complete market/crafting mutation campaign killed all 392 selected mutations.
The subsequent refresh/cache changes have their own focused mutation checks. An
initial new cache-regression mutant survived a test that checked eventual completion
only; the stronger test also checks that completing another partition retains the
previously resolved price without another lookup. Failed evidence is retained in
`test-output/market-consumption-final-mutations.*`; the corrected focused campaign
is recorded separately. The multi-partition negative control fails before the fix,
then passes with complete prices, bounded work and stable idle. Actual feature
frames for Overview/Opportunities/Crafting/Shopping/Advisor are constructed/driven
in the synthetic integration case; this proves handlers, not real pointer input
or Forever appearance.

A read-only production snapshot-117 identity audit found 4,253 id-only base records
(1,301 commodities and 2,952 auctions), with 27,397 variant records kept separate.
This is evidence of current descriptor compatibility, not an owner-PC performance
or game-consumption observation. No production service, publisher, account, provider,
collector or game installation is modified. The owner requested a feature branch and draft PR for testing.
Main merge, production deployment and public addon publication are outside this
draft-review scope.

Final focused verification additionally passes all eight consumption mutations
(including capacity pressure), the two end-to-end consumption/refresh cases, and
12 Workshop/settings modules. Final production code changes after the broad
campaign are confined to reference caching/notifications, source labels and the
separate AH Sell comparison; financial/identity guards are rechecked by the focused
campaign. The final async case also verifies no lookup of an already resolved
price when a different partition completes. Main merge, production deployment and public addon publication are outside this
draft-review scope. No new Companion release is needed for this base-item integration.

### Market search and chart refresh regression

The Market research page now treats the validated generation and focused-item
scope as catalog identity. Partition loading is temporary work, so it no longer
invalidates a completed name-search index. A focused item-ID result is not reused
as if it contained the whole catalog. The page retains one selected validated
summary projection while other partitions decode; generation, validation failure,
item, exact variant, metric and date-window changes invalidate that snapshot, and
leaving the page releases it. This avoids repeatedly evicting/reloading the
selected chart's partition during search. An automatically changed selection also
resolves its own variant rather than inheriting the previous item's variant.

The real-reader regression uses three disposable contract-2 partitions, staggered
validation, and a name search started during another partition read. It checks
complete results, an uninterrupted existing chart, stable idle work, selection and
window changes, replacement generations, explicit research context and cleanup.
The original code fails the chart-retention assertion. Four focused mutations
restore transient catalog identity, incomplete focused-catalog reuse, repeated
chart reads and stale item variants; all four are detected. This is offline
handler/reader evidence. The reported Forever-client search and appearance still
need owner retesting; no simulator or real-client acceptance is claimed here.

The final frozen-source checks pass both `development market` (34 modules) and
`development auction-preview` (33 modules), including Lua syntax checks. The four
search mutations also pass on the final test. An earlier Market run passed its
modules but was rejected by the source-change guard while the new regression
coverage was still being edited; that evidence is retained separately. The later
frozen-source runs report unchanged source and PASS. The subsequent documentation
placement correction changes no executable source.

### Tooltip recommendations from available prices

Advisor policy 3 compares usable Market Recent Price references against the known
vendor value in both directions. The existing 1.5x vendor margin and the player's
minimum worthwhile gain still determine whether auctioning is worth the effort.
The primary tooltip says `Auction (Market estimate)` or `Vendor (Market comparison)`;
limited local observations can similarly support `Possible Vendor`. These remain
tentative comparisons and do not supply posting prices or predicted proceeds.
Missing or pending evidence gets a specific primary message, such as `Loading
Market price`, `Check variant price`, or `Auction price unavailable`. Crafting
reservations and pending plans still take precedence over a sale comparison.

Disenchant values are compared against the same available auction/vendor evidence
when the existing evaluator supplies a verified expected value. Production still
has no verified Forever outcome dataset, so this repair does not invent a
Disenchant recommendation. Relevant gear with unknown outcomes includes
`disenchant unpriced` on the primary recommendation, even with all detail rows
hidden. The new tests include an independent integer-margin model and the actual
tooltip adapter/renderer over the real validated Market reader. These are offline
synthetic checks; actual Forever hover appearance remains for owner retesting.

Verification for this repair: `development workshop --profile cloud` passes all
76 modules plus Lua syntax; `development workshop-settings --profile cloud`
passes all 12 modules plus syntax. Both report unchanged source. The complete
Market mutation campaign detects all 285 selected defects, including the eight
new recommendation defects. The original vendor fall-through is reproduced in
`test-output/tooltip-advice-negative-vendor.log`; final evidence is retained in
`test-output/tooltip-advice-{workshop,settings,mutations}.*`. The simulator is not
installed on this host, so simulator and real-client appearance are not claimed.

### Disenchant support

The owner approved bundling an outcome reference and implementing the feature.
`DisenchantData.lua` and `DisenchantExclusions.lua` adapt the MIT-licensed
[DisenchantForever](https://github.com/APGM82/DisenchantForever) data at immutable
commit `ab223e6750b8e1aa24b76f66437deee461c27b47`. Its copyright and complete license
ship in `licenses/MIT-DisenchantForever.txt`; blob identities are retained in
`tests/fixtures/disenchant_forever/UPSTREAM.json`. No third-party UI, transaction
code, updater, logging or Auctionator dependency is included.

The 54 captured weapon/armor brackets use Forever client build `1.60.1.70425`;
excluded/special-reward item flags come from build `1.60.1.70888`. Yield chances
and quantity ranges are Classic 1.12 references from vmangos, cross-checked by
upstream against cmangos, with their disagreements retained in source comments.
They are not newly confirmed Forever outcomes. Low-level rare brackets (5–15),
items outside supported ranges and special-reward items stay unavailable. Known
nondisenchantable items, shirts and tabards are excluded.

Expected copper is the sum of `probability × midpoint quantity × material unit
price`, rounded down once after summing. The midpoint is a modeling assumption,
not a measured quantity distribution. Every material needs a positive quote no
more than 24 hours old; absent, future-dated or stale prices do not become zero
or a partial total. Quotes use existing Market pricing and its local-scan fallback.
Asynchronous price completion refreshes an open tooltip through the existing
pricing notifications. Outcomes may still be displayed without a numeric value.
No new Companion format or server deployment is needed.

Tooltip reads retain the actual item-copy level. Generic unresolved variant rows
cannot substitute a base level. Character context reads numeric profession ID 333
and Disenchant spell knowledge through APIs already used in the project. A
known false spell result stays false. The bundled bracket source supplies no
per-item rank requirements, so the adapter does not invent a Classic/TBC skill
threshold. Character skill/spell events refresh the existing tooltip listener;
no new frame or recurring timer is added. Actual game eligibility remains a
required client check for this versioned reference.

Advisor and the tooltip numeric/outcome rows share one computed estimate. A
Disenchant recommendation is tentative and says `Disenchant (Classic estimate)`;
sale recommendations that compare it also retain the Classic source qualification.
The existing 1.5× margin, worthwhile-gain preference, crafting reservations and
unresolved-plan guards remain in force. Auction proceeds are cleared when
Disenchant wins. Estimates neither supply posting prices nor claim guaranteed
proceeds. Hiding detail rows cannot turn a Classic comparison into strong evidence.
Existing layouts/settings and all SavedVariables are preserved.

Tests cover both boundaries of all 54 captured brackets (52 supported, two
unconfirmed), hand-worked armor/weapon examples, an independent integer-arithmetic
reference over 96 deterministic cases, exclusions, missing/fresh material prices,
character ability, actual item levels and source labels. A real-reader synthetic
integration drives the actual tooltip through material validation/automatic refresh,
checks idle work settles, generation replacement discards old quotes, and verifies
local-only fallback without Companion. These prove offline handlers and arithmetic;
Forever hover appearance, current-build eligibility and actual yields remain for
owner acceptance. The simulator installation is unavailable on this host.

Diagnostics: the tooltip's existing `workshop.worth` scope covers this bounded work;
Market decoding/pricing retains its existing scopes and gauges. At most three
cached material quotes and a fixed bracket lookup are added per estimate. There
is no separate retained estimate cache, background loop or observation collection.

Final offline verification on the completed runtime passes 78 Workshop modules
and Lua syntax, 12 Workshop/settings modules and syntax, and 18 test/packaging
infrastructure modules. All report unchanged source. The final complete Market
campaign detects all 302 selected defects; the 19 focused disenchant mutations
also pass. Evidence is retained in `test-output/disenchant-release-check-*.log`,
`disenchant-test-tools.log`, `disenchant-copy-level-mutations.*` and
`disenchant-complete-market-mutations.*`. The log name `release-check` denotes
these development checks, not release certification. Earlier fixture-construction
failures and two intentionally stopped broad campaigns are retained; both stopped
campaigns preceded final comparison/copy-level review corrections and are not
counted as completed verification. Subsequent documentation-only evidence updates
change no tested executable input. Simulator and real-Forever acceptance remain
unrun. In-game acceptance: check a known enchanter's green armor/weapon, an excluded
wand/PvP item, a missing material price, an actual-level variant, spell/skill changes
with the tooltip open, and local-scan fallback after disabling delivered Market data.

Final staging normalized trailing blank lines in the new data/license/provenance
files. The two disenchant tests and both data-file syntax checks pass again after
that whitespace-only correction; the complete campaign's executable behavior is
unchanged. No other executable or fixture edits follow the complete campaign.
