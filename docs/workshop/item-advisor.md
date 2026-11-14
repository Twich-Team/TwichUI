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

`AdvisorData` discovers identities from the selected market, bags, this
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
