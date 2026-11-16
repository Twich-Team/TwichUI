# L3 scoped Market reader

Workshop now consumes exact, scope-complete schema-3 history through its existing reader and Market view while retaining legacy and local behavior. Availability is explicit; imported data does not activate Advisor decisions. Capacity checks pass, but dense payload loading and the nominal 3 ms slice target still need real-client acceptance.

Implementation base: TwichUI `5133a43477237bf7cd97a429a680a751a9533f7c`.
Producer: Market PR #15, reviewed and merged as `6cef35797f28d562c7ee3db3aa290cfe876f418d` (source `15e2775dab6ceff7a4449d78d6c00c63afc54a60`). No deployment.

## Implementation plan

Extend BridgeSchema/BridgeValidate/Bridge rather than adding a reader. Compile the authoritative schema-3 plan from the unchanged pinned mirror. Validate the sealed request, exact sorted selection, per-record identities and calendar before atomic activation. Preserve streaming hashes, cooperative work and lazy bounded record decoding. Schemas 1/2 keep their meaning.

Expose scope and date availability separately from price. Extend ServerMarket and the existing Auction House Market detail; Workshop's existing Server history entry opens that same source. No external writes to Prices, History2, scan/quality/distribution tables or SavedVariables; no automatic valuation/source changes.

The Lua contract contains market/issuer/request identity, not account/device credentials. Authorization remains the producer/desktop boundary. Consumers may supply a trusted expected market/request to reject a mismatch; the addon cannot authenticate a desktop account or establish a player-facing realm mapping from an unverified mapping.

Keep broad summary coverage independent of detailed history. Specify a dormant evidence boundary; do not activate an Advisor source or let imported asking prices satisfy local competition.

Verify pinned positive/negative fixtures, local-state fingerprints, existing legacy reader/UI tests, actual authenticated L2 server → Rust publisher → production reader, targeted cooperative performance/mutations and representative simulator scenes. Run the full Cloud profile once after source freeze; report actual outcomes and remaining installed Windows/Forever gates. No real game files or player data are used.

## As-built reader and trust boundary

The wire contract remains **twichui-market-bridge / contract 1 / transport 1 / schema 3**, requiring the exact ordered feature list `exact_copper`, `current_summaries`, `daily_history`, `scoped_selection`. No Market contract, endpoint, publisher, provider or production behavior changes in L3. The L1 specification remains authoritative at Market `contracts/bridge/scoped-l1/README.md`; L2 implementation evidence is `docs/scoped-market-delivery-l2.md` at the producer revision above.

`tools/compile_bridge_schema.py` resolves only pinned local schema resources. `--check` verifies the checked-in trusted Lua plans. Schema 1/2 plans retain their canonical JSON meanings. The generic schema primitive now supports structured `const` values, including ordered feature arrays and empty exclusions.

`BridgeValidate.Header` validates the original scoped header directly. It does not convert a scoped candidate into a full-market generation. It checks request/selection digests, issuer and full market identity, algorithm/basis/window, counts, ordered unique exact membership, complete-scope and false whole-market declarations, omitted distributions, source/receipt separation and the entire consecutive date calendar. Calendar references must identify the actual latest complete close, latest incomplete-only observation, or no observation. Current/source references, snapshot provenance, UTC ordering and watermark checks remain shared with legacy validation.

`BridgeValidate.Record` reuses the existing strict currency, identity, daily-close, distribution and arithmetic rules. It additionally binds every record's canonical bytes to its per-record hash and requested exact identity. The reader reuses those encoded bytes for canonical comparison, rather than encoding the same record again. Complete eligible daily references are mandatory even when another valid record/hash could otherwise hide their omission.

`Bridge` streams the canonical records-array and complete-generation hashes. It retains original immutable strings and per-item sorted ranges, with at most **24 decoded records**, as before. No second materialized generation or expanded daily-history index is retained. Candidate activation occurs only after complete validation; activation clears the decoded cache. Scheduled work uses the existing token guards and timing scopes. An unchanged rejected data table is not repeatedly revalidated on navigation; an explicit `Begin` or a newly loaded table permits another attempt.

SHA-256 detects changes and binds identities; it is not a publisher signature. Trust still begins with the authenticated producer and companion's controlled assignment-only publisher. Runtime decoding is strict JSON, never executable deserialization. Workshop cannot authenticate an installed Lua addon or determine the desktop's account. Account/device authorization and checkpoint pinning are enforced by L2. The sealed schema-3 manifest contains the observation watermark, issuer, market, references and generation identity; it does **not** contain the private archive checkpoint ID. L3 does not invent such a field. The independent desktop receipt must match the generation and be completed no earlier than source generation time.

The no-bridge module startup comparison retained 223,790 bytes at the pinned baseline and 300,677 bytes in L3: **76,887 additional bytes**. Final three-sample L3 medians were 3.885 ms compilation and 0.189 ms initialization (worst 5.574 / 0.279 ms). It loaded no data addon, scheduled no timer, created no validation job and left local sentinels untouched. This measures six reader/adapter modules, not complete Workshop/client startup. Reproduce with `python3 tools/measure_scoped_reader.py --startup-only --report /tmp/l3-startup.json`.

### Consumer limits

| Constraint | L3 behavior |
|---|---|
| Schema-3 canonical working set | 2 MiB delivery policy, checked against declared size and independently summed actual chunk bytes before record decoding |
| Initial selection | Desktop default 100; not a reader/protocol hard maximum or a comfort guarantee |
| Schema-3 selection count | Approved contract maximum 1,000; actual bytes can refuse much earlier |
| Schema-3 request / manifest | 128 KiB / 256 KiB, as approved in L1 |
| Schema-1/2 manifest | Original 64 KiB limit retained |
| Individual record / receipt | 64 KiB / 4 KiB |
| Absolute canonical / source limits | Frozen 32 MiB canonical / 130 MiB expanded source remain separate |
| Proposed 3 MiB Lua delivery policy | Enforced by L2 publisher before publication; Lua cannot recover the original file length after assignment |

The parser's default remains 64 KiB. Only the manifest call opts into a maximum of 256 KiB; schema dispatch then enforces the version-specific bound. This resolves a measured legacy-parser mismatch without raising record or legacy limits. A falsely small `records_bytes` cannot bypass the actual-byte preflight. `Status().refusal == 'canonical_bytes'` identifies a policy refusal while the existing error result remains `invalid`. No variant or date is pruned, and no scope is shortened.

The data addon has already compiled by the time validation starts. These checks cannot undo compilation or prevent its earlier allocations. Last-good retention can temporarily keep both previous and candidate payloads resident. Retained heap measurements below do not bound all-addon global GC or candidate peak memory.

### Public read-only interfaces

Existing `Record`, `Value`, `History`, `Variants`, `EachItem`, `Manifest`, `Market`, `Receipt`, `Load` and `Status` remain. New interfaces are runtime API projections, not new wire fields:

* `Capabilities()` advertises schemas 1/2/3 and implemented features; `summary_index=false` explicitly refuses to claim Tier A support.
* `Scope()` reports full-market versus `explicit_variants`, completeness, selection/request identities, requested count, UTC window, watermark and active generation. Its legacy `full_market` tag describes the API result; it does not rewrite `coverage.scope`.
* `Availability(itemID, exactVariantSHA, optionalUTCDate)` separates membership, date inclusion, observation reference/completeness and state. `included` means exact-record membership, independently of `date_in_scope`.
* `Begin(raw, automatic, expected)` optionally pins a trusted expected market object (for example one returned by `Market()`) and/or `request_digest`. Internal request/header equality is always required. An intentional desktop market change is not silently equated with the player's local realm.

| Availability | Meaning and price behavior |
|---|---|
| `priced` | Supported Recent Price exists for that exact observation; references remain external asking/listing evidence |
| `supply_only` | Known supply, no supported buyout; price unavailable |
| `observed_absent` | Explicit zero supply from a complete observation; **price is unavailable**, never zero |
| `unknown_coverage` | Unknown variant state or no eligible close; calendar distinguishes incomplete-only and unobserved dates |
| `outside_scope` | Exact variant or requested date was not delivered; no statement about its market value or actual presence |
| `unsupported` | Required numeric/metric interpretation is unavailable; supported independent metrics need not become invalid |
| `invalid_generation` | No active generation survived candidate rejection |
| `unavailable` | No validated source is loaded |

Legacy missing records still return `not_observed`; that is not proof of absence. A failed replacement with an active predecessor continues answering from that predecessor, with `Status().error` describing the rejected candidate. `Value` continues returning nil/reason for unavailable values. Supply history may legitimately contain zero; price history never synthesizes zero for absence. Date-window intersections with no selected dates return `outside_scope` for schema 3. Missing dates are not interpolated or promoted from weekly aggregates.

## Presentation and state isolation

The existing Market server selector stays opt-in. Workshop's existing **Server history** entry opens the same Auction House Market detail and exact-variant selector; local Price history stays local. The external adapter never feeds Prices, History2, scan logs, quality/distribution stores, Sell or crafting valuations. No startup bridge load, automatic Workshop opening, source switching, scan, transaction or reload is added.

The Market view shows source/house/ruleset, algorithm/basis, current supported references, supply, observed dates/gaps, source timestamp/age, requested UTC coverage, scope completeness and generation status. Full variant/generation/selection/request identities and watermark use the existing context tooltip. Compact context lines avoid overflowing the established cards. The Market chart allocates at most 60 markers for the complete external daily window; local projections explicitly retain their existing 30-marker cap, and other chart defaults stay unchanged. The current UTC day remains provisional. Unverified player-market mapping and provisional algorithms keep their existing warnings/labels.

A numeric item search or explicit navigation can show a valid item not delivered in this update, including another exact variant of the same item ID. Tracked/bag catalogs can also retain these unavailable identities. The detail says **“Market history not included in this update.”** and offers only a deferred, noninteractive future-selection explanation. It never substitutes an item-ID aggregate. External action buttons remain disabled.

Within a session, a rejected replacement preserves the previous validated source and its history. Across sessions, Workshop does not load `Previous.lua` itself: L2 publisher recovery must restore the prior complete artifact. Updating files while WoW runs does not dynamically reread an already loaded addon. Existing data remains until a later player-controlled login/reload; L3 neither requests nor triggers one.

## Item Advisor compatibility boundary

Current Advisor policy remains unchanged. `Advisor.Decide` and `Sell` consume local `Facts`; the sell suggestion requires local distribution/quality and competition rules, and tentative observations also come from local facts. Advisor prioritizes active crafting reservations and pending-plan checks, auction eligibility, variant uncertainty, known vendor value, the 1.5× vendor margin and configured minimum gain. Disenchant remains dependent on verified outcomes with explicit uncertainty. L3 does not modify any of those modules or decisions.

`ServerMarket.Evidence(itemID, exactVariantSHA)` is a dormant, read-only API 1 boundary. It returns `role='external_evidence'`, detailed-history state, exact source market identity, source/generation/window, limited or insufficient confidence, and supported Recent/Market references with their provenance. It explicitly says `local_competition=false` and `summary_coverage='unavailable'`. It is not a local Facts snapshot, posting suggestion or decision-engine registration and never loads a source. No current Advisor caller uses it.

Tier A broad summaries and Tier B detailed history have independent membership. A future Tier A lookup must not require `Bridge.Record` membership; a Tier B miss must not suppress an independently valid summary. If both tiers lack evidence, retain local Vendor/Keep/Disenchant behavior and explicit insufficient auction evidence. Unknown exact suffix/bonus variants remain unsupported; display names and base-item IDs cannot authorize exact valuation. Imported asking prices must never satisfy local competition, fees, sale probability or disenchant-yield requirements.

### Bounded broad-summary recommendation

Reuse L2's measured synthetic whole-index evidence: 45,125 all-priced rows produced approximately **5.78 MB Lua, 31.37 MB retained offline heap and 238 ms compilation in one sample**. Do not load it wholesale. Those are L2 observations, not L3 real-client measurements.

Start the separately authorized Tier A work with a bounded summary cache independent of detailed history: an initial **2,000-summary test candidate**, selected from legitimate bag/tracked/crafting/recent-item requirements, with exact byte and retained-memory gates. Linear projection from L2 is about **256 kB Lua / 1.39 MB heap / 10.5 ms compile**; these are estimates, not acceptance results. Actual density, exact-variant mapping, metadata and integrity overhead must be measured. This broad cache does not restrict Advisor candidates to 100 historical variants. New uncached items still receive the best supported local evaluation and an explicit insufficient external evidence result, with a future desktop request workflow. The addon cannot make arbitrary HTTP calls.

If the product requires immediate external prices for every recognized market variant throughout a session, a bounded summary working set alone is insufficient. The next candidate is a separate versioned compact, encoded summary format with bounded row decoding and a small fixed set of independently validated load-on-demand partitions. For illustration, 32 equal partitions of L2's existing table format average about 1,410 rows, 181 kB source and 0.98 MB heap each. Distribution skew and source-wide manifest costs invalidate any count-only guarantee. Group all variants of an item deterministically, bind each part to one source generation and require exact complete-versus-selected summary coverage semantics.

Partitions are not automatically unloadable. WoW's addon loader runs each addon once per session; discarding a loaded partition and calling LoadAddOn again will not reread it. Either retain bounded encoded strings/indexes for every loaded part (then test the eventual complete-session memory ceiling), or refuse additional loads when the active budget is exhausted and retain explicit unavailable coverage until a future update/login. Splitting the current table format into addons does not remove its eventual 31 MB cost or global GC. No hard frame-time guarantee or seamless partition eviction is claimed.

Future summary negotiation must use a separately specified format/schema/feature profile, its own generation identity, market identity, source watermark, exact copper, observation age/completeness and quality reasons. Unknown versions/features fail closed. Summary coverage cannot be inferred from schema-3 scope completeness, and mixed-generation Tier A/B evidence must remain separately attributed. Do not add unsupported candidate fields such as actual-sale prices, confidence probabilities or disenchant yields. Whether a complete compact encoded index fits safely remains an L4/research gate; the universal evidence-supported Advisor goal is preserved, not declared finished.

## Targeted synthetic loading evidence

Measured with offline Lua 5.1, global GC enabled, CPU clock, three samples per case. Compilation is `loadfile` of a **trusted generated fixture**, separately from assignment and validation; runtime reader code never executes input. These are not installed Forever frame times. The 155/166 cases are stress boundaries above the desktop default, not a proposed default increase.

| Exact variants / history | Canonical bytes | Lua bytes | Median compile / worst | Median validation CPU / worst | Median largest slice / worst | Retained payload / warm cache bytes |
|---|---:|---:|---:|---:|---:|---:|
| 10 / dense 60-day | 159,303 | 222,389 | 2.27 / 3.66 ms | 1.275 / 1.825 s | 5.90 / 6.70 ms | 319,193 / 859,606 |
| 100 / sparse 60-day (four closes) | 181,963 | 248,985 | 1.03 / 1.18 ms | 1.180 / 1.469 s | 6.77 / 31.81 ms | 322,870 / 454,792 |
| 100 / dense 60-day | 1,298,121 | 1,841,927 | 23.94 / 25.12 ms | 8.702 / 9.494 s | 7.76 / 8.08 ms | 1,528,147 / 2,695,646 |
| 155 / dense, near policy bound | 1,994,055 | 2,831,606 | 18.74 / 34.25 ms | 12.658 / 13.441 s | 61.59 / 69.08 ms | 2,278,103 / 3,441,921 |
| 166 / dense, refused | 2,133,249 | 3,029,573 | 40.41 / 52.42 ms | 0.510 / 0.655 s to refusal | 5.84 / 62.00 ms | Candidate strings remain until released; no activation |

| Workload | Median / worst first-record lookup | Median / worst history lookup | Median validation slices |
|---|---:|---:|---:|
| 10 dense | 4.437 / 5.926 ms | 0.125 / 0.140 ms | 566 |
| 100 sparse | 0.255 / 0.363 ms | 0.048 / 0.051 ms | 553 |
| 100 dense | 2.270 / 2.285 ms | 0.129 / 0.163 ms | 4,174 |
| 155 dense | 2.268 / 2.713 ms | 0.128 / 0.129 ms | 6,158 |

History timing follows the first record lookup, so it benefits from the bounded record cache. Assignment medians ranged from 2 to 5 microseconds. The scoped mock UI's 50 Browse/Market/Shopping/Sell navigation cycles took 0.295 seconds including final harness collection; worst whole iteration was 24.5 ms and retained growth 269,087 bytes. This is mock-handler timing, not a game frame measurement. Page counts, validation slices and addon load counts remained stable after initial construction.

Assignment alone was microseconds, distinct from compilation. First-record and history reads are measured in the reproduction output; lookup remains lazy and the decoded cache remains capped at 24. Retained values are incremental to already-loaded Workshop reader modules after explicit collection in the **test harness only**, not peak client/all-addon memory. Invalid replacement cases preserve active identity and local sentinels. An exploratory earlier 10/dense sample reached **86.5 ms** in a validation slice, and an earlier 100/dense compile sample reached **69.4 ms**. These unfavorable observations are not discarded as evidence of a hard bound.

The nominal 3 ms scheduling target is **not met universally**. Cooperative CPU also accumulates across many callbacks; at one callback per game frame, wall-clock completion could be substantially longer than CPU time. Actual C_Timer scheduling, game startup order, compilation, global GC, other addons and combat must be measured in Forever. No GC tuning/stopping is added to runtime, no validation is weakened, and no limits are raised to hide the result.

Keep 100 as a desktop selection default proposal with exact-byte refusal, not a proven loading budget. Begin L4 with 10 dense or 100 sparse variants, progress to dense 100 only after client acceptance, and use 155 only as a stress/refusal boundary. Automatic delivery remains blocked on installed-client performance and recovery acceptance.

## Verification ledger and reproduction

Market PR #15's current required PostgreSQL, Windows, browser and signed-update checks were successful before merge. Fresh L1 reference tests passed (16), all 18 authoritative negative cases passed through native Rust validation, and every mirrored file matched. Provider clients/recovery and desktop scalar-cache/scheduler implementations were verified unchanged against the integrated base during review. Historical L2 counts (584 PostgreSQL / 90 local Rust / 92 Windows checks) remain historical evidence, not newly claimed runs.

The unchanged fixture manifest SHA-256 is `c5a465e323005735444f3e5fe2ec48241f50942ebdfb7e7078049849206ec2a7`: 15 authoritative hashed payloads, plus manifest and explicit upstream provenance pin `74686fefacb5e43d6ad9d02c827a859859d09082`. That revision remains an ancestor of the merged producer, whose authoritative fixture bytes match. No fixture or bridge-v1 contract was silently edited.

Production-reader tests include legacy schemas 1/2, future schema/features, all shared negative cases, separately resealed scope/request/record identities, missing closes, false whole-market completeness, exact-variant mismatch, unsupported copper, receipt time, byte-budget refusal (including a falsely small declared size), >64 KiB scoped headers, valid changed-window replacement/cache invalidation and last-good retention. UI tests fingerprint local state and trap AH/reload/addon-load calls, exercise exact variants, excluded identity, absence, unknown coverage, supply-only and repeated Browse/Shopping/Sell/Market navigation.

The actual disposable L2 server → Rust archive/projector/publisher → production reader → Market handlers test passed: 129 source variants, 100 selected, resumable bootstrap and an incremental observation, **141,703 canonical / 191,202 Lua bytes**, server/Rust equality, independently expected `[100,140]` prices and Market Value `100`, historical-only absence, bid supply `2`, 58 missing dates and exact-variant exclusion. This is genuine component integration over synthetic observations, not genuine production-history or Windows acceptance. A fresh native example was built from the merged producer. The acceptance harness initially omitted the verified synthetic player-market mapping; Rust correctly refused that market. The fixture now carries the same verified mapping required by L2; authorization was not relaxed.

Focused simulator evidence includes scoped priced, outside-scope, absent, unknown, corrupt, future-schema and legacy scenes, independent replay and a deliberately wrong expectation. Each scoped scene has 141 structured checks. Screenshots are structural only: the simulator uses fallback fonts/assets and older UI-source APIs. An early screenshot exposed overflowing provenance text; L3 moved full identities to the existing tooltip and retained compact visible context. No simulator or Cloud result establishes real-client visual acceptance.

Final feature/full/mutation outcomes are recorded below after source freeze. The first feature attempt had 44/44 offline files passing but simulator exit 1 because the outer sandbox denied bubblewrap's NETLINK_ROUTE socket. The rerun uses the already authorized simulator permissions. This is not a skipped gate. The repository also documents an existing byte-exact reminder-gallery PNG portability failure; L3 will report the full-profile result without weakening or updating those unrelated assertions.

Use the existing toolchains from `docs/cloud-environment.md` and `docs/testing.md` (Lua 5.1 + bit; Python Market dependencies; Rust). Commands from the addon root:

```sh
python3 tools/compile_bridge_schema.py --check
python3 -m unittest discover -s tests -p 'test_workshop_bridge*.py'
python3 -m unittest discover -s tests -p test_workshop_scoped_bridge_l1.py
bash tests/run.sh feature market --profile cloud
bash tools/mutate.sh --group market.scoped --jobs 2
python3 tools/measure_scoped_reader.py --market-root /path/to/pinned/Market --report /tmp/l3-reader.json
python3 tools/verify_market_l2_consumer.py --market-root /path/to/pinned/Market --rust-client /path/to/archive_smoke --report /tmp/l3-consumer.json
SIMLAB_ONLY='shell replay marketbridge scopedpriced scopedoutside scopedabsent scopedunknown scopedcorrupt scopedfuture wrong' bash tools/simlab/run.sh auctionpreview
bash tests/run.sh full --profile cloud
```

Build `archive_smoke` with `cargo build --locked --manifest-path desktop/core/Cargo.toml --example archive_smoke` in the pinned merged Market checkout. The integration tool starts a localhost synthetic server with temporary test credentials/database, invokes the actual native client and publisher, compares server/Rust generations, then runs the production UI test on its artifact. It cleans its temporary data. No provider collection, game paths or real SavedVariables are used. Benchmark logs/artifacts remain outside commits; source tools and this report contain reproduction and measured results.

## Rollback, remaining gates and execution order

1. **L3 review:** review this draft and preserve the canonical fixture pin. Revert the isolated addon implementation to restore schema-1/2-only behavior if needed. Restore a valid legacy artifact through the companion for an older reader; never label a subset as legacy complete. Unsupported/corrupt candidates cannot replace active data.
2. **L4 Windows producer acceptance:** use the actual installed companion under separately authorized test paths. Verify owned staging, readback, manual file replacement, interrupted updates and prior-generation restore on Windows. Do not reuse synthetic Cloud success as installation evidence.
3. **L4 genuine retained history:** obtain authorized read-only acceptance of actual current counts, UTC gaps, exact variants, historical-only records and pinned archive checkpoint. Existing production history was not accessed in L3. No new provider collection is required.
4. **L4 Forever consumer acceptance:** separately authorize a test installation and player-controlled login/reload. Measure startup and explicit LoD compilation, per-frame and worst validation slices, wall completion, memory/global GC with other addons, cold/warm history reads and navigation. Fingerprint real SavedVariables before/after, test wrong market/unsupported/corrupt replacements and previous-artifact recovery. Include real fonts, assets and current Forever UI versions. Start small; approve a concrete operating envelope before larger defaults.
5. **Tier A separately authorized contract/proof:** decide whether immediate whole-market price availability is required, or bounded broad summaries with explicit insufficient evidence meet the initial product goal. Prove a compact summary profile/partition ceiling, exact identity resolution, source confidence/freshness, mixed-tier provenance and all-session retention behavior. Keep Advisor policy and competition safeguards unchanged until separately reviewed runtime integration.
6. **M2 only after those gates:** implement consented desktop working-set requests/selection persistence, installation path safety, version/capability negotiation, recoverable atomic delivery, generation freshness/status and player-confirmed reload. No arbitrary addon HTTP, surprise reload, automatic source switching or transaction activation.

Owner decisions are limited to the installed-client operating budget and Tier A coverage/representation tradeoff. L3 does not require a new contract major or a silent schema amendment. No server deployment, game installation, automatic delivery, pricing-default change or live Auction House operation is part of this milestone.

## Frozen verification status

Affected Market feature gate: **exit 0**, 44 offline files/modules and the four selected Workshop simulator launches passed (314.569 seconds). The final explicit-request label/clock text and additional fixture grouping are also covered by focused checks and the comprehensive run below. Auction House fast gate: **exit 0**, 18 files/modules. Production bridge Python: **exit 0**, 12 methods; L1 mirror/proof: **exit 0**, 4 methods. New scope mutation campaign plus existing generation/range controls: **exit 0**, 18/18 killed (16 assertion detections, two runtime detections), including external 60-marker/local 30-marker controls, zero survivors/invalid/timeouts/infrastructure errors. The legacy catalog-reuse mutation was updated to the renamed focus argument without changing its intent; the complete catalog pattern check is required before source freeze.

The first comprehensive attempt on `630d818` was deliberately interrupted with **exit 130** during offline verification, before simulator catalogs, when review found that the existing 30-marker chart cap hid older scoped dates. It is not a completed regression result. The fix permits all 60 external daily markers and preserves the local 30/default 8 caps, with explicit component controls. The final frozen comprehensive/native results below supersede that interrupted attempt; no assertions were weakened.
