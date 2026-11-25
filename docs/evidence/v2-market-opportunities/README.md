# V2 Market Opportunities audit evidence

[Audit and interpretation](../../performance/v2-market-opportunities-audit.md).
Offline Lua 5.1.5 + LuaBitOp; Linux x86_64 AMD EPYC 9V74 host, 5 visible logical CPUs,
4 CPU quota, 16 GiB cgroup memory limit. Serial workloads, no competing heavy
verification or simulator campaign. Python 3.12. Three fresh-process measurements
per case after one discarded fresh-process warm-up. Every dataset is fabricated.

The runtime source is TwichUI `725519e6be87f3e3b9c75d8f7ad271572cb60a1f`;
all of `TwichUI_Workshop/` is unchanged from released `v2.0.0` through this audit
base. Evidence JSON records source and benchmark harness SHA-256. Runtime and
fixture generation use fixed timestamps; no production database or network is
needed. Exact fixture identity is the committed `workshop_summary_v2/synthetic.json`
plus the harness hash/count/history-days. The new harness is not a native publisher
integration proof; use the existing paired publisher/consumer workflow for that.

Reproduce from repo root with Lua 5.1 and LuaBitOp available on PATH:

```sh
python3 tools/measure_market_opportunities.py --suite all --reps 3 --days 2 --report test-output/opportunities-2day.json
python3 tools/measure_market_opportunities.py --suite all --reps 3 --days 60 --case reader/single/32 --case reader/batched/32 --case opportunities/session/1000 --case memory/1/32 --case memory/2/32 --case memory/4/32 --case memory/8/32 --case memory/16/32 --case memory/64/32 --report test-output/opportunities-60day.json
```

In this managed workspace only, the preinstalled interpreters require
`source /workspace/twichui-env/activate.sh` first. This is environment setup, not a
portable project dependency; no system package or simulator was installed/modified.
The first bare interpreter invocation failed because Lua was not on PATH.

The 2-day suite exercises all 20/100/500/1,000 recipe sizes in Session and full
mock UI modes. The focused 60-day suite exercises cold/warm reader access, batch
locality, 1,000 recipes and every requested retention capacity. It deliberately
omits the thousand-redecode 60-day case from this run; its command remains available
with `--suite reader --days 60` and should be part of dedicated stress work.

Each JSON saves all measured runs and min/median/max. `cpu_ms` excludes fixture and
header creation/validation but includes the final compatible warm calculation;
`subprocess_wall_seconds` includes complete setup. `model_seconds` is virtual timer
advance, not elapsed client time. Timings are inclusive where scopes nest. The
reader's first blocked request is included in `record_calls`/lookup misses; 1,000
successful reader accesses are cache-ready hits. Remaining reader calls in that
case are pending misses/retries. Pricing's estimator warm draw makes no reader
calls; exact per-API price-cache hit ratios need the proposed aggregate diagnostic.

Memory deltas exclude pre-held fixture strings. `raw_loaded_bytes` reports those
loaded payload sizes separately; Lua interns identical fixture/assignment strings.
The original integrated `index_retained_kib` is biased by unrelated garbage collection and must not be used as index footprint. The numeric item-position index is measured separately and exact variants require
extra range structure. Sampled peak is a lower bound, heap drops are not GC cycles,
and explicit GC is reported separately. Memory retention uses real decoded rows,
not a predicted table-size formula. Mock frame memory cannot predict native UI RAM.

Exploratory runs were excluded from the baseline: the production JSON encoder
rejects fractional benchmark numbers, corrected by encoding diagnostic numeric
fields separately; an initial observer retained every historical estimator and
inflated GC/heap, corrected to counter-only instrumentation. Intermediate campaigns
were interrupted to freeze the corrected harness. None of their numbers is an
accepted baseline or claimed speedup. The final JSON's harness hash identifies
the corrected executable inputs.

No remediation implementation is timed. The batched case is the same production
reader and repeated-item request multiset in a different order; it demonstrates
locality benefit only. No automatic clock-dependent regression gate or baseline
refresh is added to routine tests.

Retained raw measurements: [2-day, 19 cases / 57 samples](baseline-2day.json) and [60-day, 9 cases / 27 samples](baseline-60day.json). Each also has one discarded warm-up per case. Fixture JSON SHA-256: `f266725c40b7dec92b9058242bdec335216c9aacfac0560660112136ab544495`.

[Focused verification receipt](verification.json): five modules passed in 2.131 s;
new invariant test 1.476 s; runner infrastructure 17 cases passed in 4.989 s.
Syntax, JSON/harness identity and local documentation links passed. No simulator,
full/release, native Windows or real-client acceptance is inferred. The self-test
prints deliberate failure cases; its final unittest result is OK.

Final review found negative integrated index net deltas. The original 84 samples
remain unchanged; their index field is excluded from conclusions.
[Controlled numeric-table footprint](index-memory.json) uses the separate
`tests/bench_market_index_memory.lua`, two full collections before and after
allocation, retained live tables and content checks. Reproduce with
`python3 tools/measure_market_opportunities.py --suite index --reps 3 --report test-output/index-memory.json`.
This adds three measured samples plus one discarded warm-up, without changing the
frozen reader/Opportunities harness. Final focused checks were repeated after the
new isolated script, additive syntax selection and driver dispatch were added.

Historical baseline retained during main integration. The original measurement inputs and JSON are unchanged. Current benchmark/test implementations come from #99/#100/#102; this audit contributes only documentation/evidence. See the PR3 report for final implementation measurements and simulator limitations.
