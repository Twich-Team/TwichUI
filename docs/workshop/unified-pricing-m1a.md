# M1a unified pricing foundation

M0.5 research PR #20 merged into `feature/workshop` as `5b6e4e9f4dd3908042831bf6496133fbd8154960`; Market PR #6 merged into its integration branch as `4cb4d86f4402cd3c6508914549f697507d69c0c6`. The owner approved decisions D1–D5.

## Dormant implementation

`TwichUI_Workshop/PricingV1.lua` is a pure independently tested module outside every TOC. It creates no frames, timers, saved tables or data sources. Existing Market, Valuation, Prices, Advisor and Sell behavior stays unchanged. No production defaults, local history, cache generations or saved schema are migrated.

The module implements ceiling unit minimum, strict-quarter anchor and cheapest eligible 30% quantity-band Recent Price; complete market-scope UTC closes including absence; 4/2/1 lower weighted median over UTC ages 0..13; exact daily lower median over ages 0..59 requiring three priced dates; and coverage/quality projections. Missing dates are never zero-filled. Mixed variants/algorithms, future observations and unsupported arithmetic fail. Copper strings are checked lexically before number conversion. Lua rejects intermediates beyond exact-double integer range; it does not claim approximate results are canonical. Rust/Python can compute wider supported cases separately.

The history helper currently accepts integral UTC epoch seconds through 2100-01-01 and observation IDs through 2^53-1; it rejects fractional seconds. A future reader must preserve contract timestamp precision, use validated precomputed closes or extend exact timestamp comparison; truncation is not conformance.

The header capability check supports both `asking-v1-provisional` / `market_rolling_daily_means` and `twichui-pricing-v1` / `canonical_complete_scope_close`. It does not validate, ingest or accept a generation. Future imports require full schema, semantic and integrity checks.

## Shared evidence and contract

The unchanged Market research fixtures remain authoritative. Python, Rust and Lua agree on 19 supported priced snapshots and eight temporal calendars; empty/bid-only and out-of-range cases retain explicit null/refusal behavior. Lua additionally verifies eleven quality cases and both bridge header pairs. New mutation catalog entries target the half-anchor inclusion, three-date Historical minimum and exact rounding range. The [bridge mirror](../../tests/fixtures/market_bridge_v1/README.md) pins schema, synthetic generations and checksums to Market's implementation checkpoint.

Unit-tested: fast market passed 14 modules/files; the full Cloud run passed all 239 offline modules/files and 702 Lua syntax files. Simulator-tested: all ten full suites passed in a 2,370.634-second run, with the existing classified simulator runtime errors and no-assets limitations retained. Mutation-tested: all 201 market mutations killed with no survivors or infrastructure failures. Full Cloud is not the local milestone gate; screenshot review and real-client acceptance are not claimed. Final evidence-only documentation/pin changes do not alter the tested module or fixtures.

Read the final [Market acceptance report](https://github.com/Twich-Team/TwichUI-Market/blob/feature/m1a-unified-pricing/docs/unified-pricing-m1a-acceptance.md) for exact verification counts, performance and open gates. This milestone does not claim representative production history or real-client acceptance. No runtime diagnostics scope/gauge is added because this module is not loaded in the addon; M1b decoding/loading must add bounded scopes and retained-data gauges.

## Dependency and next milestone

Review and merge [Market M1a PR #7](https://github.com/Twich-Team/TwichUI-Market/pull/7) first, then this dependent addon PR. Both remain draft for owner review and are not automatically merged. Server export, desktop generation/atomic replacement and the non-executing Workshop reader are separately authorized M1b work. Preserve local scan history and algorithm-qualified imported sources. Full snapshot comparisons, Windows file replacement, Forever load/reload, memory/size limits, client persistence and Advisor/Sell confidence acceptance remain gates before activation or delivery.
