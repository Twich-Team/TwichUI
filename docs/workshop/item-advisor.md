# A8 Item Advisor

Approved scope: one Workshop page in the existing left navigation. No Auction
House replacement, posting, automatic scans, selling automation or chart engine.

## Checkpoints and acceptance

1. Engine: versioned deterministic recommendations; competitive prices from
   Market.Competition; unknown fees and missing evidence remain explicit;
   disenchant expected-value evaluation with verified eligibility/outcomes only;
   focused edge cases, feature verification and market mutations pass.
2. Page: searchable real item identities, pooled results, selected-item advice,
   market cards, actual observed history, reasons, alternatives and actions;
   simulator state checks and personally inspected wide/narrow screenshots.
3. Workflow: cross-page item selection, Normal tooltip recommendation by default through the existing configurable
   recommendation field; Tooltip Designer fields, manually
   refreshed tracking and saved selection; existing layouts remain intact;
   settings/tooltip feature verification and large-data measurements.
4. Completion: visual review, edge-case/mutation coverage, full addon regression
   and all default simulator scenarios; final verified commit pushed.

## Evidence and policy

`Sell.Suggest` policy 1 matches the lowest competing tier supplied by the A5
market service. That service normalizes stack buyouts to units and excludes
low tiers beneath its existing anchor. A suggestion requires fair/good quality,
a complete scan no older than three days, and no mixed variants or suspicious
far-below signal. Historical values only add qualifications when current
competition is far above/below the reference; they never supply a posting price.

`Sell.Proceeds` reports gross unit price times quantity with bounded arithmetic.
Fees, deposit and sale probability remain unknown. It never reports net proceeds.

`Advisor.Decide` API/policy 1 keeps active-plan materials first, using the existing
planner's allocation. Known recipe uses alone never prove crafting profit. A
bound item may be vendored when its sell value is known. Missing disenchant
data never blocks a supported Vendor or Auction recommendation. Other uncertain auction comparisons
remain Unknown. A supported auction suggestion must exceed vendor by 1.5x and
the player's minimum worthwhile gain; that gain defaults to zero copper (no
universal gold floor). Auction advice says *consider*, uses gross value and
never promises a sale or profit. Watch is a choice with manual refresh, not a
prediction that an item will appreciate.

The policy is deliberately more conservative than the older A8 roadmap's
vendor fallback when auction evidence is missing, as required by this campaign.
Disenchant is a first-class alternative. Its pure evaluator accepts only explicit
verified Forever eligibility, skill requirements and complete probability/output
snapshots with reliable material values. No distributable verified dataset exists
in the inspected sources, so production reports uncertain outcomes. Synthetic
regressions cover expected gross material values and selection; no outcome tables
or game rules are invented.

`AdvisorData` discovers identities from the selected market's current price-entry identities, bags, this
character's remembered/available recipes, explicit tracking and saved selection.
It does not claim a global item database. Discovery yields every 160 identities;
price evaluation is reserved for visible rows and the selected item. MarketFacts
and A5 caches remain responsible for history and distribution reuse. Selected
crafting context reuses P2's cooperative queue job, never calls `CP.Plan`.

## Verification record

Checkpoint 1: focused Advisor tests and feature verification passed (43 test
files/modules; four simulator launches; 2,025 structured checks). Offline
20,002-item discovery: 251 slices, approximately 114 ms total, maximum 11 ms
on the measured run. 10,000 repeated recommendations: approximately 172 ms,
one cached fact entry. These are synthetic offline figures, not client timings.

The final report records commit hashes, final artifact paths, mutation totals
and comprehensive verification results. No real-client acceptance is claimed.

## Page and workflow as built

The fifth left-sidebar page preserves the Workshop shell and its movement and
screen-fitting behavior. Its two columns contain a pooled searchable list and
selected-item evidence. Source/category controls cycle supported choices; the
auctionable filter requires known eligibility. Market cards keep observed,
historical and suggested values separate. The existing chart displays up to
eight actual daily low observations, with real gaps, rather than the mockup's
illustrative continuous 60-day line. The shorter existing window uses a scrollable
evidence pane; three contextual actions remain at its foot.

Track/untrack saves at most 200 explicit item identities, using manually refreshed
observations only. Recipe uses opens this character's actual known recipes and
their existing crafting strategies. Shopping sources selects the material in the
active plan (disabled for unrelated items). Right-click Workshop item icons in
Opportunities, Crafting and Shopping to open that item in Advisor. Entry resets
old search filters and reveals the selected row. Selection and tracking use the
existing account-wide Workshop view record; tooltip layouts retain their existing
profile scope. No saved schema is migrated and newer records remain read-only.

The existing `recommend` Tooltip Designer field remains in Normal by default;
its saved id, order and Always/Shift semantics are preserved. Two optional fields,
Advisor explanation and Advisor evidence, are available in the Designer. Removing
the primary field or disabling tooltips remains effective. Hover reads cached
MarketFacts and direct/current cached plan demand; it never requests a planner
job or a scan. Unresolved plan dependencies stay conservative. Missing disenchant
data never blocks otherwise supported Vendor/Auction advice.

The minimum worthwhile gain setting is a single account preference: 0c (default),
1s, 10s or 1g. The API accepts other bounded copper values. Adapters snapshot it
into `Decide` input; the pure decision does not read changing preferences. The
1.5x gross vendor margin is also required. No net proceeds, demand estimate,
sale probability, appreciation forecast or automated posting is introduced.

Bag discovery keeps actual per-copy binding and variant evidence. Known unbound
copies can be considered separately; all-bound copies cannot receive Auction
advice. Missing bag quantities remain unknown. Only selected missing item data is
explicitly requested; failed loads cannot create a request loop. Discovery/search
are cancelled and catalog, row and popup references released on hide. Diagnostics
expose discovery/search scopes, catalog/result counts and existing bounded market
fact caches.

## Disenchant evidence audit (2026-11-14)

The local `wow-ui-source` Forever branch documents
`C_SpellBook.ContainsAnyDisenchantSpell` (SpellBookDocumentation.lua) and
`C_Item.GetItemQualityColor` (ItemDocumentation.lua). The former establishes
character spell knowledge, not item eligibility, required skill or outcomes.
No item outcome/probability API was found. Group-loot `canDisenchant` is about
that roll and is never treated as eligibility for an item in the bags.

The inspected NaowhForever_Professions README explicitly attributes its outcome
bands/odds to Classic-era Warcraft Wiki facts and says Forever item skill
requirements may differ. Its addon code is all-rights-reserved. TradeSkillMaster
also restricts reuse/distribution. Neither table was copied. The
[Forever spell entry](https://www.wowhead.com/forever/spell=13262/disenchant)
corroborates the general weapon/armor action, but its inherited cross-version
comments do not validate Forever output probabilities. The linked Wiki table
could not be fetched (403) and would still require Forever-specific validation.

`Disenchant.Evaluate` requires an explicitly verified Forever snapshot matching
the item, authoritative eligibility and required skill, known character ability,
complete probabilities totaling 1, and reliable values for every material. It
sums probability × expected material quantity × gross material listing value,
rounding only the final copper result. Expected material value is never guaranteed
proceeds. Production has no verified snapshot provider and therefore cannot issue
a Disenchant winner yet. Tests use conspicuously synthetic snapshots to verify
eligibility, skill, complete/missing prices, probability weighting and selection.
A verified, distributable Forever dataset is intentionally deferred; no logging
campaign, import UI or data-sharing service is started.

## Checkpoint evidence

- Engine `aac4b4bc`: 43 feature test files/modules, four simulator launches,
  2,025 structured checks; initial market campaign 179/179 detected.
- Page `3c08abdd`: 44 feature files/modules, six launches, 3,048 checks.
  Wide, narrow, scaled and missing-market screenshots personally reviewed.
- Integration `ca4df5ca`: Workshop Settings feature 76 files/modules, three
  launches/1,556 checks; Advisor feature 44 files/modules, six launches/3,108
  checks. Advisor/disenchant focused mutants 6/6; crafting campaign 112/112.
- Final polish: fast Advisor and Workshop Settings checks plus explicit long-name,
  empty-catalog and alternatives poses; screenshots personally reviewed.
  Complete milestone verification is recorded after it finishes below.

Five offline Lua 5.1 runs (synthetic data; simulator also active) measured:

| Work | Median | MAD | Bound/evidence |
|---|---:|---:|---|
| 10,000 cached recommendations | 195.6 ms | 2.1 ms | one cached market-facts entry |
| Discovery of 20,002 identities | 136.9 ms | 3.2 ms | 251 cooperative slices in every run |
| Worst discovery slice per run | 11.253 ms | 0.307 ms | observed maximum across runs 11.563 ms |

Raw measurements: ignored `test-output/a8-performance.log`. This is CPU evidence
on synthetic offline fixtures, not client frame-time or live-market evidence.

## Remaining real-client acceptance

Check actual fonts/materials and quality colors at the player's UI scales; real
pointer/wheel and right-click input; tooltip rebuilds with Shift/custom layouts;
character binding and late item-data events; persisted selection/tracking across
reload and profile switching; a representative live market database and the
Diagnostics discovery/search scopes. Confirm no new protected operations, taint
or Auction House requests occur. Offline/simulator evidence cannot establish
these. Automatic craft-completion detection remains disabled.

## Final comprehensive verification — passed

`./tests/run.sh full` completed with **226 passed, 0 failed**, **677 Lua syntax
checks**, the simulator workspace guard and all seven default regression suites.
It executed **147 simulator launches and 21,930 structured checks** in **1,810.935 s**
(30 min 10.94 s). Exit status: **0**. No filters, assertions, scenario catalogs or
negative controls were removed. The first full attempt was externally interrupted
during Settings and produced no complete report; the entire command was rerun
from the beginning under separate process supervision. Only the complete rerun
is counted as milestone evidence.

| Suite | Launches | Structured checks | Result |
|---|---:|---:|---|
| Smoke | 2 | 0 | pass |
| Interaction | 4 | 244 | pass |
| Diagnostics | 6 | 101 | pass |
| Workshop | 32 | 16,559 | pass |
| Test Lab | 9 | 229 | pass |
| Settings | 58 | 1,029 | pass |
| Reminders | 36 | 3,768 | pass |

Final market mutation campaign: **183/183 detected**, zero survivors, invalid
mutations, timeouts or infrastructure errors. Crafting campaign: **112/112
detected**, also without survivors/invalid/timeouts/infrastructure errors.
Focused fast checks passed (2 Advisor modules and 11 Workshop Settings modules).
Feature checkpoint results are recorded above. No real-client test is claimed.
The simulator retains its existing classified voice-settings and NPC UTF-8
limitations; no classification exceptions were added for A8.

Ignored local evidence paths (relative to repository root):

- Complete structured report: `test-output/verification/full-all-9wujqs1a/report.json`.
- Complete runner log: `test-output/a8-full-retry.log`; exit record
  `test-output/a8-full-retry.exit`.
- Final market/crafting mutation logs: `test-output/a8-market-verified.log`,
  `test-output/a8-crafting-mutations.log`.
- Reviewed screenshots: `test-output/simlab/artifacts/workshop-UsyuF4J4/`:
  `advisor.png`, `advisorsmall.png`, `advisorscaled.png`, `advisorlong.png`,
  `advisorempty.png`, `advisorvacant.png`, `advisoralt.png`.
- Settings preference capture:
  `test-output/simlab/artifacts/settings-j3ZTb4GQ/workshop.png`.

The screenshots were personally inspected (including the same frozen-source
images from the interrupted attempt). They establish structural layout evidence,
not real-client appearance, actual fonts, pointer input or reload persistence.
Game/simulator overlays in captures are not Advisor controls.

Intentional scope limits: search enumerates bags, current market price entries,
this character's known recipes, tracking and saved selection, not a global item
database. History-only identities must also be reachable through one of those
sources. Existing Opportunities profit estimates keep their previous semantics;
this campaign does not claim to migrate them to a selling strategy. The shorter
shell, scrollable evidence, cycle filters and existing eight-observation chart
are the documented adaptations of the mockup. No Auction House replacement,
automated posting, advanced selling strategy, shared chart engine, Ledger,
profession guide redesign or market-server integration was started.

## A8.1 refinement checkpoints (active)

The real-client screenshot and refinement request retain the approved page layout.
The original A8 engine, Tooltip Designer integration and verified disenchant
limitations remain in force. Stop after these four checkpoints:

1. Native source/category dropdowns; In bags first-use default; saved source
   preference; direct selection/dismissal/combined filters and open-menu captures.
2. Reproduce metadata-driven scroll resets, then preserve viewport and selection
   across asynchronous/same-set refreshes and page return. Exercise large lists,
   wheel/scrollbar handlers, search/category and nonzero-scroll captures.
3. Separate supported/tentative/insufficient advice in page, rows and the existing
   configurable Normal tooltip field. Preserve supported pricing safeguards,
   ownership, plan protection, disenchant eligibility/expected-value checks and
   missing-data behavior. Add evidence/tooltip regressions and market mutations.
4. Review every relevant visual state and run the complete full verification
   tier once at the final source state. Record evidence, commit/push and stop.

Checkpoint 1 sources deliberately use the three existing supported discovery
sources: In bags, Tracked items, All known items. No bank freshness is implied.
The source preference uses the existing account view record, defaults narrowly
when absent/invalid, and respects the newer-schema write guard. External item
navigation temporarily reveals All known items without overwriting that preference.
Native Forever radio menus own scale, positioning, selection and dismissal; the
Workshop uses the existing core dropdown trigger and material styling.

A8.1 checkpoint 1 verified: fast Advisor 2/2; feature Advisor 44/44 test
files/modules and eight simulator launches passed (188.903 s total). Native
source/category menus personally screenshot-reviewed in
`test-output/simlab/artifacts/workshop-e1xTxWMj/`: both open beneath their
controls, above the evidence panel, with direct radio choices. No live-client
pointer or reload test is claimed. The first capture exposed cursor anchoring;
the corrected final run uses the native anchored-menu API.

A8.1 checkpoint 2: the new 3,000-identity regression first failed on the old
code (`metadata refresh ... expected 641, got 0`). `ItemReady` unconditionally
marked search dirty and every completed search called `ScrollTop`; page hide
also forced a new selected-row reveal. The fix separates intentional filter
resets from background refreshes, preserves the live top identity/within-row
offset at search completion, and keeps only that scalar viewport on hide.
Metadata reruns filtering only when it can affect active-filter membership.
Catalog/pooled-row references are still released on hide.

Fast Advisor 2/2 and feature Advisor 44/44 passed; nine simulator launches,
211.268 s total. The personally reviewed capture
`test-output/simlab/artifacts/workshop-rMR6K6su/advisorscroll.png` shows 818
results and selected Stored Herb 10005 after native wheel/scrollbar handlers,
metadata updates and page return, all retaining offset 1379. Unit coverage also
checks bags/all-known, active search/category, repeated advice paints, selection,
menu dismissal, cooperative refresh during scrolling and bounded row pooling.
Two preliminary simulator runs failed in test instrumentation (a shadowed
native menu name and the 40-second simulated-time budget); neither is counted
as passing evidence. The final scenario retains every assertion and has a
45-second resource allowance for the additional interactions. Real pointer
wheel/drag input still needs client acceptance.
