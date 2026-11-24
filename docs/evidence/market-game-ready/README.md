# Game-ready Market investigation evidence

Investigation only; no new-format native publisher or production activation.

- [Report and reproducible commands](../../performance/market-game-ready-data-investigation.md)
- [Campaigns, sample ranges and fixture inventories](results.json): 11 campaigns,
  69 measured cases, 206 measured samples plus discarded warm-ups; ten layouts
  explicitly rejected/not loaded. Includes the selective-only negative control.
- [Fast test receipt](development-verification.json): 13 modules pass in 9.829 s.
- [Verification scope, source revisions and host](verification.json).
- [Existing native-format producer/consumer control](native-contract3.json).
- [Two-day](stages-two.json) and [60-day](stages-sixty.json) producer/reference
  transform/durable I/O measurements. These are not Windows sync timings.
- [Interrupted receipt-aggregation run](interrupted-run.json): tooling failure,
  repair commit and regression guard; never treated as a passing product run.

`results.json` retains each measured sample and min/median/max for selected
metrics, exact benchmark helper hashes, economic snapshot digests and fixture
semantic/source inventories. The curator checks matching economic results across
campaigns. Fixtures are generated from committed fabricated templates through
Market's actual sealer; no production observations or private data are included.
Generation timing fields vary by host, so use semantic and source-content IDs to
compare reproduced fixtures rather than expecting an identical timed receipt hash.
Large Lua fixtures and full raw process output stay in disposable storage.

The fixed-current experiments do not exercise a complete new-format A/B
installation. Mixed layout folder totals compose separately measured current and
history components. Native Forever/Windows acceptance and migration tests remain
future work requiring implementation approval. The full release/simulator gate
was not run or claimed.
