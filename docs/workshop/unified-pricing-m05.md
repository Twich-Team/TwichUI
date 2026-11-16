# TwichUI unified pricing M0.5 handoff

Status: specification and shared fixtures for owner approval. No addon runtime, TOC, SavedVariables, pricing, Advisor or synchronization behavior changes in this PR.

The authoritative Market research PR supplies `docs/unified-pricing-m05.md`, `docs/unified-pricing-m05-research.md`, `docs/unified-pricing-m05-migration.md` and `contracts/pricing/v1`. The exact Market source commit for this mirror is recorded in `tests/fixtures/pricing_v1/UPSTREAM.json`. Pricing authority was inspected on integration `7202e07a62f1770642b50afe5a3ec671d9b488cf`; its pricing/companion blobs match the current reviewed polish branch. This addon branch starts at `feature/workshop` `8c1ffad9fb08e91d95c6d921e9e3b4543fe05b0c`.

## Recommended shared policy

Reserve `twichui-pricing-v1`: ceiling unit-price tiers; current strict-quarter/half-anchor/cheapest-30% band mean for Recent Price; UTC age 0..13 Market Value with lower weighted median and 4/2/1 recency weights; UTC age 0..59 Historical Value as an exact daily lower median requiring three priced dates. Keep Market's all-listing weighted mean as a separately named descriptive statistic. Two dates can draw two historical points but do not establish canonical Historical Value or validate either full horizon.

Canonical daily history selects the latest complete scope observation, including explicit absence, rather than the last listed item observation. Incomplete evidence cannot replace that close. Older weekly means stay legacy aggregate results; they are not relabeled exact canonical days. These are deliberate differences from parts of the existing Workshop history model and require owner approval.

Competition, purchase costs, suggested posting and confirmed proceeds retain distinct roles. Preserve Advisor's variant/eligibility/reservation checks, 1.5x vendor margin and player threshold; Sell still needs reliable current competition, complete evidence, good/fair quality, no farbelow and current age <=72 hours. Synthetic, unverified market, unknown content age and unresolved precision cannot qualify strong advice. No historical value substitutes for competition.

## Evidence and limitations

The live Market route was blocked by the Cloud proxy; the owner had no alternate export. Four committed genuine listing excerpts were retained with source hashes, variants and capture timestamps. Each is a one-listing item excerpt, not a full variant book or a multi-day history. The remaining scenarios are explicitly synthetic.

The research checker passes 61 specification cases. Existing Market pure snapshot functions agree on 23 cases; existing Lua Dist/weighted-median arithmetic agrees on 19 supported priced cases. This does not establish full temporal API, Rust, simulator or real-client conformance. The fixture's `thin-cheap-third` result of 1c demonstrates why band arithmetic must not imply safe advice. See the Market report for alternatives and exact source-execution limits.

## Compatibility and later work

Keep `TwichUIWorkshopDB.v=2`, market format 3 and every local history string intact. Dist alg=1 alone does not prove canonical observation selection, exact arithmetic or variant identity. Existing h2/c2/legacy histories keep their original basis. Add a canonical source/projection only after reviewing saved-data compatibility; do not reconstruct missing closes from the bounded ring.

The future M1 bridge must carry pricing algorithm, quality policy, metric role, history/identity basis, arithmetic status, input generation, per-value coverage and observation/upstream timestamps. Its current scalar Market `recent_price` is not a canonical band mean. Preserve separate imports and M0's dedicated data-only addon, atomic generation and explicit reload boundary. No bridge is implemented here.

Python/Rust/Lua consumers must use the byte-identical JSON/schema/checksum files under `tests/fixtures/pricing_v1`. Copper remains strings; unsupported unit prices and unsafe Lua intermediates return a range/support reason, never rounded/clamped canonical results. Future implementation tests must include the existing independent references, mutation groups, held/corrupt saved-data cases and full verification tiers required by CLAUDE.md. No new runtime perf scope is needed for these static fixtures; a later loader/calculator needs decode/calculation scopes and bounded-cache gauges.

Owner approval requested: the band parameters, calendar/median reference definitions, complete day-close and exact-daily history policy, unchanged selling safeguards, and real-data shadow gate before a separately authorized rollout. Approving this specification does not authorize implementation or deployment.
