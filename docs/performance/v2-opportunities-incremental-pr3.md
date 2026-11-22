# Incremental Opportunities PR3

Stacked on unmerged PR2 #100 at `8b5865b20cec7d7f39af78de947b712a9c7c67e1`; PR1 #99 and Market #43/#44 remain dependencies. Market is read-only in this stage. No merge, deployment, release, contract or pricing-policy change.

## Focused baseline and design

One instrumented 1,000-recipe / 60-day / contract-3 UI workload uses the existing production harness and synthetic data. Actual CPU 5,562 ms; Craft accounts for 4,520 ms, Rows 4,578 ms inclusive of Craft, sorting 231 ms, chart reads 1.6 ms. These overlapping scopes must not be added together. 54 full lists / 54,000 Craft entries, 50 estimator instances; a compatible warm redraw still calls Craft 1,000 times and costs 36.8 ms. Worst scheduled callback 171.9 ms. Header admission and fixture construction are outside workload CPU. One diagnostic sample, not a statistical performance baseline; probes add overhead. [Raw phase sample](../evidence/v2-market-pr3/profile-pr2.json).

The partial pricing revision is part of Session.Estimator's context key. Every completion discards shared question memoization, builds all recipe result tables, sorts and refills visible rows. The existing virtualized list already pools frames; it does not need a replacement. Selected charts are not the primary CPU cost in this fixture.

Use one Workshop-specific recipe-result store with item→recipe dependencies. Keep the existing estimator memo, invalidate its affected item answers, and gate calculation until price questions have terminal answers. One tokenized coroutine worker handles invalidation, recipe computation, filtering and cooperative merge sorting under elapsed and operation budgets. Yield between material/questions as well as recipes; record indivisible service calls separately. Prices, formulas, quality and fee rules stay in Estimate/Market.

A changed context invalidates all results; changed prices invalidate dependent recipes only. Result validity must be checked against item/context versions before publication, including while a worker is suspended. Partial results retain stable provisional order, visibly labeled as refreshing; final ordering uses the existing comparator. Filter/sort changes reuse estimates. Visible rows can advance pending work without implying they are the best-profit recipes. Keep one bounded catalog, no historical payload cache, and no background worker when idle.

Context boundaries include actual source/generation, local scan sequence, fee evidence/duration, vendor changes, recipe catalog changes, freshness thresholds and cooldown time. Hiding cancels obsolete workers but retains compatible completed estimates; suspension clears transient engine state. Source changes cannot publish old profits.
