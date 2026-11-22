# Incremental Opportunities PR3

Stacked on unmerged PR2 #100 at `8b5865b20cec7d7f39af78de947b712a9c7c67e1`; PR1 #99 and Market #43/#44 remain dependencies. Market is read-only in this stage. No merge, deployment, release, contract or pricing-policy change.

## Focused baseline and design

One instrumented 1,000-recipe / 60-day / contract-3 UI workload uses the existing production harness and synthetic data. Actual CPU 5,562 ms; Craft accounts for 4,520 ms, Rows 4,578 ms inclusive of Craft, sorting 231 ms, chart reads 1.6 ms. These overlapping scopes must not be added together. 54 full lists / 54,000 Craft entries, 50 estimator instances; a compatible warm redraw still calls Craft 1,000 times and costs 36.8 ms. Worst scheduled callback 171.9 ms. Header admission and fixture construction are outside workload CPU. One diagnostic sample, not a statistical performance baseline; probes add overhead. [Raw phase sample](../evidence/v2-market-pr3/profile-pr2.json).

The partial pricing revision is part of Session.Estimator's context key. Every completion discards shared question memoization, builds all recipe result tables, sorts and refills visible rows. The existing virtualized list already pools frames; it does not need a replacement. Selected charts are not the primary CPU cost in this fixture.

Use one Workshop-specific recipe-result store with item→recipe dependencies. Keep the existing estimator memo, invalidate its affected item answers, and gate calculation until price questions have terminal answers. One tokenized coroutine worker handles invalidation, recipe computation, filtering and cooperative merge sorting under elapsed and operation budgets. Yield between material/questions as well as recipes; record indivisible service calls separately. Prices, formulas, quality and fee rules stay in Estimate/Market.

A changed context invalidates all results; changed prices invalidate dependent recipes only. Result validity must be checked against item/context versions before publication, including while a worker is suspended. Partial results retain stable provisional order, visibly labeled as refreshing; final ordering uses the existing comparator. Filter/sort changes reuse estimates. Visible rows can advance pending work without implying they are the best-profit recipes. Keep one bounded catalog, no historical payload cache, and no background worker when idle.

Context boundaries include actual source/generation, local scan sequence, fee evidence/duration, vendor changes, recipe catalog changes, freshness thresholds and cooldown time. Hiding cancels obsolete workers but retains compatible completed estimates; suspension clears transient engine state. Source changes cannot publish old profits.

## Verified implementation checkpoint

The production TOC now loads `OpportunityEngine.lua` after Estimate. Completed recipe estimates survive compatible redraws; item versions invalidate dependent rows and estimator questions. Cold demand is reserved by partition before its shared decoder handoff, preventing progressive calculation from reintroducing partition churn. Cancellation releases only the unfinished demand lease, leaving shared decoding available to other consumers.

The worker targets 2 ms with an independent 1,024-resume cap (32 without a CPU clock), yielding after estimator service questions/materials, dependency updates and merge-sort steps. An indivisible service call can exceed the target: diagnostics record those calls separately. No CPU scope spans a yield. Provisional order is labeled, final order uses the existing comparator; pooled rows, money formatting and selected details are reused.

The ten-module development group passed in 4.423 seconds (cloud profile; 33 Lua syntax files). The targeted mutation campaign killed all 16 applied defects in 12.8 seconds, including elapsed budget, dependency fanout, mutable recipe snapshots, source/token guards and the preparation lease. The earlier invalid revision mutation was updated to match the refactored completion writer and rerun successfully; no assertions were weakened. Integration, comparable multi-sample benchmarks and native verification are reported below when complete.
