# M1.5 Market bridge acceptance

Review drafts: [TwichUI #23](https://github.com/Twich-Team/TwichUI/pull/23) and [Market #9](https://github.com/Twich-Team/TwichUI-Market/pull/9). The [coordinated capacity report](https://github.com/Twich-Team/TwichUI-Market/blob/529e7ba354e1ceaec9a02fb0f7e2b089cf7af6a9/docs/workshop-bridge-m15.md) owns the complete before/after CPU, artifact, capacity and memory tables, raw samples, method and operational proposal. This milestone stops before activation or M2.

## Frozen source and changes

Baseline addon: `c0c9de1ef3242d5ca50c2c514cd481e81dfaf13b`, base `feature/workshop`. Baseline Market: `68c075138d5f50608c741b0e51b7013d9bf8769d`, base `integration/companion-v2-metadata-recovery`.

Measured addon runtime: `a779e227d32d65c90871c00c347f5dd9ce91ce31`; final code/test freeze: `febed289d7db429d00d02fcff73cdbf262d541c2`. Runtime bytes are identical between those two checkpoints; the latter strengthens the cross-item negative control. Market measured implementation: `d012c32513b4205eee4167db85aac065cbfdc84f`. Later acceptance documentation does not change runtime bytes.

The existing reader now uses fewer temporary JSON/string/hash allocations, yields within checksum work, and retains a compact sorted exact-variant index. A timed step reserves one millisecond of headroom and has a deterministic work ceiling; a clockless environment retains the original 32-resume cap. Repeated access to the same validated manifest avoids re-encoding it. No new parser architecture, dependency or game API is introduced.

Existing `workshop.bridgeLoad`, `workshop.bridgeValidate`, `workshop.bridgeRecord` and `workshop.bridgeHistory` performance scopes and record/byte/cache gauges remain the diagnostics entry points. Phase attribution and no-GC experiments are offline diagnostics, not a global runtime GC policy.

## Demonstrated improvement and unresolved scheduling

Five interleaved matched pairs per completed workload demonstrate roughly **30–35% lower validation CPU** and **65% smaller generated Lua**. For 1,000 variants/two dates, median validation CPU is 4.44 → 3.16 seconds; retained payload/index heap is approximately 2.00 → 1.79 MB. Source compilation, assignment, CPU, wall time, lookup, bounded-cache access, navigation, RSS and retained Lua heap are reported separately in the authoritative raw report. All unfavorable samples and exploratory pairs are retained.

Primary 1,000-variant/two-date descriptive medians (same 1,491,161 canonical bytes):

| Measurement | Baseline | Candidate |
|---|---:|---:|
| Generated Lua bytes | 5,965,402 | 2,082,736 |
| Expansion over canonical bytes | 4.00× | 1.40× |
| Rust artifact construction, elapsed ms | 108.446 | 41.620 |
| Rust manual export, elapsed ms | 317.396 | 220.498 |
| Rust canonical serialization, elapsed ms | 3.079 | 3.157 |
| Lua source compilation, CPU ms | 8.506 | 5.353 |
| Lua assignment, CPU ms | 0.007 | 0.007 |
| Reader module loading, CPU ms | 1.398 | 1.483 |
| Validation callbacks | 7,877 | 1,574 |
| 200 record/history navigation reads, CPU ms | 96.312 | 45.492 |
| Decoded cache entries | 24 | 24 |
| Cache exercise retained growth, bytes | 99,854 | 100,136 |
| Explicit offline collection, CPU ms | 0.464 | 0.757 |

These are separate phases, not additive independent costs: export includes construction/readback. Small descriptive differences are not improvement claims. Raw lookup/history probes and all ranges/MAD are preserved. Navigation here means API reads; the feature/simulator suite separately exercises actual handlers, not real rendered game-frame latency. Linux child peak RSS can include a fork/pre-exec floor. Whole-process totals include an extra repeated load in each shape's first pair, while the initial-validation measurements compare the same operation.

A [single exploratory actual-handler observation](../evidence/bridge-m15/exploratory-handler-note.json) also remains recorded: 50 page round trips, 32.884 ms CPU, 154,733 bytes retained growth, two pages and one decoded record. It is a transcription of tool output without preserved exact source/binary metadata, so it is not used for a paired improvement or client-comfort claim. No extra repetitions were run for this report.

**The 3 ms worst-slice target is unmet.** The final matrix includes 23.017 ms at 10,000 variants, 26.480 ms at 1,000 variants/14 dates, and 26.170 ms near the input ceiling. The primary two-date case reaches 8.595 ms. Timers cannot preempt C operations, compilation or global interpreter GC. Diagnostic tails also occur without collection; no single cause is claimed. These Cloud observations are not game frame times.

The unchanged **32 MiB cap applies to canonical serialized generation input**. The separate expanded-Lua bound is **130 MiB**. A 25,000-record/one-day generation passes offline at 31.50 MiB canonical, 43.87 MiB Lua and approximately 71 seconds validation CPU. That proves bounded offline acceptance, not WoW-client comfort. A 50,000-record historical-only generation exceeds the canonical cap and is refused before export, without trimming history or variants.

## Contract, isolation and compatibility

Bridge transport/contract v1, schemas 1/2 and AMENDMENT-001 are unchanged. All 14 authoritative files match the exact mirror pin `1f76f8468722f07430acb3a10d26d6ad2d20e9cd` in [UPSTREAM.json](../../tests/fixtures/market_bridge_v1/UPSTREAM.json). No independently edited fixtures or new algorithm semantics are introduced.

The Rust publisher emits safe printable bytes inside fixed quoted literals, retaining fixed-width decimal escapes for unsafe bytes. Both old/new Lua readers accept equivalent decoded v1 content. New desktop readback also accepts legacy artifacts; an older desktop inspector can refuse compact source on downgrade and fails closed. Actual Lua execution sentinels prove malicious source text remains data. No generated functions, dynamic decoding, SavedVariables or credentials are added.

The cross-component test uses authenticated HTTP, independent shared input/expected fixtures, the actual Rust client/cache/exporter and the actual Lua reader. Generation `4e6cea38071018d519682ba4690b79566303f8ce67039ef6e99472f107ee453f` survives all four pages and 7,702 canonical / 10,671 Lua bytes. Available November 13/15 dates and missing November 14 remain distinct. Exact copper, algorithms, variants and unavailable states agree; corruption preserves the previous validated snapshot. Local Workshop data stays unchanged, with no surprise load, scans, network requests or transactions. This is synthetic evidence; genuine history was not accessed.

## Verification

One comprehensive Cloud run passed at frozen code/test commit `febed289d7db429d00d02fcff73cdbf262d541c2`: **247 test modules**, **138 Python methods**, **10 simulator suites**, **192 simulator launches** and **30,552 scenario checks**, in **2446.279 seconds**. All **714 addon Lua files** passed syntax checks. The actual runner result and unsupported coverage are preserved in [full-cloud.json](../evidence/bridge-m15/full-cloud.json), with [console output](../evidence/bridge-m15/full-console.log) and [source verification](../evidence/bridge-m15/verification.json). This is a full **Cloud-profile** pass, not the local asset or real-client milestone gate.

| Check | Result |
|---|---|
| Fast Market | 18 modules passed |
| Affected Market feature | 42 modules and Workshop simulator catalog passed |
| Independent JSON/SHA + actual Lua reader | 6 methods passed |
| Deterministic scheduler/index/encoding/local-state tests | Passed, including the final foreign-item assertion |
| Focused bridge negative controls | 16/16 detected; no survivor, invalid, timeout or infrastructure failure |
| Full Market mutation campaign | 234/234 detected; no survivor, invalid, timeout or infrastructure failure |
| Mutation pattern validation | All 351 valid; 234 Market / 117 Craft |
| Locked Rust workspace | 80 passed; one new opt-in profiling test exercised separately |
| Workload/schema correctness | 3 passed |
| Legacy/compact + actual HTTP/Rust/Lua golden fixture | Passed; shared fixture bytes unchanged |

[Market campaign evidence](../evidence/bridge-m15/market-mutations.json) and [focused bridge evidence](../evidence/bridge-m15/bridge-mutations.json) preserve all verdicts. Craft implementation is unchanged, so its separate mutation campaign was not repeated. Full discovery retains deterministic PNG checks, independent replays and existing negative controls; no assertion was removed or softened. Subsequent changes are documentation/evidence only, with identical runtime and test source, so the comprehensive suite is not repeated.

## Conservative operating proposal and remaining gates

For owner review only, begin with all of **2 MiB canonical**, **1,000 exact-variant records**, and **3 MiB Lua**, rather than using record count alone. Proposed client targets are nominal 2 ms work, p99 ≤3 ms, max ≤10 ms, compile/load ≤10 ms, incremental steady heap ≤5 MiB and two-generation transient heap ≤16 MiB. These are not enforced or established by Cloud tests; even offline samples exceed some targets.

Readiness also needs a client budget: the primary median of 1,574 callbacks would take about 26 seconds at one callback per 60 Hz frame, or 52 seconds at 30 Hz. This is only a scheduling model; the actual timer cadence has not been established. Lower validation CPU alone cannot establish acceptable elapsed readiness.

Hold/refuse over-budget delivery and preserve the previous generation; do not sample required variants/history and call it complete. Before M2 activation, separately authorized Windows/Forever acceptance must measure compilation, callback cadence, changed-generation memory, frame tails, readiness and global GC pressure. Windows ACL/junction/reparse, replacement, restart/interruption and antivirus/power-loss acceptance remain open. The Cloud no-assets profile does not satisfy local asset/rendering or real-client acceptance.

Structural scheduling/representation changes, if required, belong in a separately reviewed follow-up. No further parser redesign or capacity campaign is part of M1.5. No automatic installation/delivery, freshness chips, Reload UI, production deployment/migration, pricing activation, source switching or Auction House actions are enabled. Local Prices, History2, distributions, logs, Advisor/Sell/CraftPlanner/Shopping confidence gates and default source behavior remain independent.
