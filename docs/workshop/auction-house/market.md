# AH-6 — Market research campaign

Plan: integrate #15/#16/#17 in order and verify their exact combined tree; add a
bounded market/history adapter; implement the approved Market page; connect
existing pages; inspect captures, measure fixtures and run comprehensive checks;
publish a draft PR and stop before AH-7, transactions, replacement or sync.

Integration is complete with normal merge commits:
#15 `f70a7ab8bd65cf41db7b15a729fbd0daf2ef24de`,
#16 `bbe4653b9273318a616850fb40873ecb72fc4585`,
#17/final base `9827418b0d3624d5077f0338290a7e9d97d53ed2`.
The exact integrated tree passed `./tests/run.sh full --profile cloud`:
235 files/modules, 696 Lua syntax files, all ten simulator/guard suites,
176 launches / 27,452 structured checks, 3019.411 s. This is Cloud evidence,
not WSL or real-client acceptance.

Checkpoint 4 adds only a presentation adapter over Workshop Facts, typed History,
TrendOf, Posture and Distribution, and reuses cooperative Browse discovery/sort.
Explicit missing markets never fall back. History-only items are discoverable;
weekly/fortnight aggregates remain ranges rather than fabricated daily samples.
The optional chart adapter preserves the default eight-dot behavior elsewhere.
No native query, transaction, schema, import or valuation engine is added.

Unit-tested: 11 fast files pass. Feature Cloud verification: 56 files, complete
19-pose preview and unchanged four-pose lifecycle-proof catalogs pass (306.590 s).
The feature run initially could not launch bwrap under restricted namespace
permissions; the unchanged permitted rerun passed. Assertions were unchanged.
Report: `test-output/verification/feature-auction-house-7_lhw_ag/`.
20k synthetic union catalog: 418 slices / 0.469 s / 11.551 ms longest observed
slice. Offline CPU only; not actual client frame time. Market mutations are
running against an immutable snapshot; no passing campaign is claimed yet.

Page UI and cross-page links follow in the next checkpoint. All prior safety
gates remain unchanged and AH-1a real-client acceptance is still pending.
