# M1b: separate Market history source

M1a foundations were reviewed and merged in dependency order: Market #7 as `2f0b6c850a767c82fe176932326b8086589a3253`, then addon #21 as `572da3a04fe1a64581b3d1cd0208038c0104cfe3`. Implementation targets remain Market's `integration/companion-v2-metadata-recovery` and addon's `feature/workshop`. Main is not the authority.

## Contract and boundaries

Market [PR #8](https://github.com/Twich-Team/TwichUI-Market/pull/8) owns `twichui-market-bridge`, contract/transport 1. The exact fixture revision is pinned in [UPSTREAM.json](../../tests/fixtures/market_bridge_v1/UPSTREAM.json). Original schema-1 bytes are preserved. Coordinated amendment 001 introduces schema 2: a source-sealed generation cannot contain its future desktop completion timestamp, so that field is null and the actual delivery receipt is separately validated. Schema 2 also fixes fractional UTC timestamps. Review the amendment on both PRs together; unsupported versions fail closed. Pricing (`twichui-pricing-v1` or explicitly labeled `asking-v1-provisional`), history basis, quality policy and generation identity remain independent.

The companion's manual **Export for Workshop testing** downloads through existing device authentication into separate `bridge-v1.sqlite`; it stages pages, validates the entire generation, then atomically promotes with previous-generation retention. Output goes only to owned companion staging, never a discovered game installation. Data.lua is a fixed assignment with decimal-escaped strings, no calls/functions/decoding code; its LoD TOC declares no SavedVariables. A separate receipt contains no account identity or credentials. Atomic replacement and readback preserve recoverable prior output.

Workshop's TOC adds BridgeCodec, generated BridgeSchema, BridgeValidate, Bridge and ServerMarket. Merely loading Workshop does not load the data addon. `Bridge.Load()` guards explicit LoD loading and combat, `Status()` reports validation, `Market()` and `Manifest()` return copies, `Record(item, exactVariant)`, `Value(...)` and `History(..., metric, {days=...})` read only validated data. Begin/Step also support the offline harness. A candidate is fully validated before becoming visible. Failed candidates leave the preceding generation usable.

Validation checks strict bounded JSON (no executable deserialization), schema/features/algorithm/basis, exact market and variant identities, canonical integrity hashes, record/chunk bounds, date ordering and exact upstream timestamps, observation/daily-close references, absent versus unknown, signed-64 copper strings, distributions, coverage and completeness. Full daily coverage cannot silently omit eligible included dates. Lua's supported price range is checked before conversion; oversized values remain exact strings and return unsupported. No zero price is invented.

Records remain encoded. Cooperative validation builds the bounded index; only individual requested records/history are decoded, with a 24-record cache. Three milliseconds is a scheduling target, not a real-client promise. Registered diagnostics cover load/validation/record/history cost, retained payload/record/cache gauges and data-addon memory.

## Player presentation

An explicit **Market server (external)** source uses the existing Auction House Market presentation, also reachable through **Server history** beside Workshop Price history. Item selection requires an exact server variant. Recent/minimum/supply charts display actual dates, missing observations and absent/unknown/omitted states with source identity, basis, generation and synthetic labels. Canonical and provisional means have distinct labels. Two dates remain two dates; sparse observations do not establish a mature 14/60-day model.

Imported data has its own namespace. No import writes Prices, History2, local distributions, logs, quality or local valuations. Advisor, Sell, Shopping and CraftPlanner keep their existing inputs. External prices never satisfy local competition gates; external research disables trading shortcuts. No network, scan, buying/posting/cancellation, automatic source switching, Workshop window opening or reload occurs on data-addon load.

## Verification and remaining gates

Unit tests run the actual reader, strict parser/hash properties, both schemas and negative fixtures; saved market/profile fingerprints remain identical. UI tests use the actual reader/adapter and sentinels that reject local-price calls and AH operations. Mutation coverage includes generation integrity, identity, history window, saved-history isolation, duplicate JSON and arithmetic precision. The simulator adds an external-history pose without weakening existing replay/negative controls. Final evidence and exact counts are recorded below and in the linked verification JSON.

Market's `scripts/verify-bridge-e2e.py` starts a disposable authenticated FastAPI/SQLite server, forces four HTTP pages, invokes the actual Rust client/cache/exporter, syntax-checks the artifact and loads it through this actual Lua reader. Independently calculated shared expectations cover Nov 13 and Nov 15 synthetic observations, the Nov 14 gap, canonical 100/120 copper, exact variants, historical-only absence and bid-only listings. A separate process verifies the data addon alone does not create Workshop. This is synthetic cross-component evidence, not production acceptance.

Cloud cannot reach the authorized production endpoint (proxy 403); the owner confirmed no alternate export. Committed genuine Nov 14 listing excerpts are not complete books or two-day histories. The genuine-history gate remains open. No production state, owner installation or real SavedVariables were accessed.

Windows CI can establish compilation and disposable-host filesystem tests. Owner Windows reparse/ACL/antivirus/power-loss behavior, actual Forever addon load timing/fonts/combat/taint, full local PNG acceptance and installed real-history acceptance remain separate gates. Simulator output is handler/state evidence and structural screenshots only.

## Read-only acceptance and M2 sequence

After separately authorized server deployment, use the existing member/device connection and select the independently verified Forever market. Export to the displayed companion staging directory, record generation, algorithm, available UTC dates and source timestamps, and compare selected exact-variant daily records with authenticated retained server observations. Do not manufacture earlier dates, infer sales, or treat legacy means as canonical. Test interruption/auth expiry and verify the prior generation/artifact survives.

On a disposable Windows test profile, inspect the fixed TOC/no SavedVariables, luac syntax and Data.lua integrity; exercise SavedVariables/game-directory rejection, symlink/junction/reparse rejection, foreign ownership/broad ACL rejection, wrong-account/market and failed replacement. Keep actual installations untouched until M3 authorization. In a separately authorized disposable Forever profile, preserve byte-for-byte SavedVariables backups, explicitly load Workshop/source, compare exact dates/variants/provenance, try corrupt/future artifacts, and verify local histories unchanged and no scans/transactions/reload. Do not claim this client gate from the simulator.

M2 should first review and merge the coordinated contract/Market producer, then this pinned consumer; design explicit destination/account/market selection and atomic automatic delivery using the proven staging publisher; add separately approved freshness indicators and player-controlled reload handling. M3 supplies installed Windows and real Forever acceptance. Automatic delivery, freshness chips, reload integration, live deployment and pricing activation are outside this PR.

## Final verification evidence

The frozen runtime is `4be53dbf105e8b1c3f552040afcb7aeadb0b853e`; Market's final code is `e2116007638b23228eace44d524b9fe2a43c2249`. The final documentation/probe commit changes no runtime files. [Machine-readable results](market-bridge-m1b-verification.json) record exact commits, fixture hashes, suite counts and limits.

- **Unit-tested:** `./tests/run.sh full --profile cloud --jobs 1`: 242 offline modules passed (134 Python cases), 709 Lua files syntax-checked, zero failed modules; all 10 simulator-suite verdicts passed in 2437.592 seconds. No suite, replay comparison or expected-wrong control was removed. This Cloud result explicitly does **not** satisfy the full local milestone/rendering gate.
- **Simulator-tested:** 189 launches and 29298 handler assertions across the complete default catalogs (counts include intentional negative-control assertions). The added external-source pose passes 120 checks, including idle bridge/initially unloaded Workshop, exact variant, two available dates, 100/120 prices, microsecond provenance, disabled trading shortcuts and unchanged local observations.
- **Mutation-tested:** market campaign 207/207 killed, zero survivors/invalid/timeouts/infrastructure errors. The campaign was repeated after the bit-API correction. The later six-line caption amendment changes no pricing/reader logic. The affected bridge subgroup also passed 6/6.
- **Cross-component-tested:** real authenticated disposable FastAPI requests through actual Rust download/cache/promotion/export, luac syntax and the actual Workshop reader agree on generation `4e6cea38071018d519682ba4690b79566303f8ce67039ef6e99472f107ee453f`. Four pages, 7,702 canonical bytes / 31,566 Lua bytes; independently hand-calculated synthetic expectations, dates Nov 13/15 and the Nov 14 gap; exact copper/variants/algorithm, historical-only absence, bid-only unavailability, corruption rejection, previous good retention, no surprise Workshop loading/frames/AH calls and saved-data fingerprints are checked. The final caption amendment does not change any producer or reader bytes used by this replay.
- **Backend/native-tested:** final Market CI [Backend 43749501744](https://github.com/Twich-Team/TwichUI-Market/actions/runs/43749501744), [Windows 43749501734](https://github.com/Twich-Team/TwichUI-Market/actions/runs/43749501734) and [website 43749501736](https://github.com/Twich-Team/TwichUI-Market/actions/runs/43749501736) are green. Counts: 503 PostgreSQL tests, 34 migration/tool tests, 115 website unit tests, 39 browser tests, 81 Windows core tests; Linux Rust 79 and focused Python canonical/bridge 118 pass. Alembic parity, populated-data preservation and destructive-downgrade refusal pass on disposable databases. Tauri has one passing unit test and one pre-existing ignored owner-signed-installer test; its required installer is unavailable. Existing disposable installed-app regression passes, but the new bridge UI action is not owner-installed or real-client-tested.
- **Adversarial reader/UI-tested:** exact signed-64 descriptive copper remains the string `9223372036854775807`; numeric conversion returns unsupported. Oversized canonical prices, invalid integrity/identity, duplicate keys/records, future versions, wrong dates/references and silent daily omissions fail safely. The actual UI consumes the pinned partial fixture and labels a single Recent Price, minimum or supply observation by its own metric; it does not inherit the local chart's “Cheapest seen” caption.
- **Screenshot-reviewed:** the normal external two-date pose is structurally legible with source/algorithm/synthetic labels and disabled trading shortcuts. Cloud fallback fonts/assets and screenshots are not visual or real-client acceptance.

## Performance observations and interpretation

These are offline Lua 5.1 CPU measurements, not installed-client budgets. The data-assignment timing starts after reader modules are loaded; retained-heap figures are **incremental** over that module baseline. No total Workshop startup or full-capacity claim is made.

| Workload | Observed result |
| --- | --- |
| 1,000 synthetic records, two dates, three processes | 1,517,404 canonical bytes; 6,070,374 Lua bytes |
| Data.lua assignment load | 8.37–13.05 ms, excluding preloaded reader modules |
| Cooperative validation | 4.52–4.65 s total; largest slices 4.87–27.00 ms; **3 ms target unmet** |
| First record / selected history | 233–291 µs / 13 µs |
| Incremental payload/index heap | ~2.02 MB after collection; decoded cache 24 entries |
| 200 record/history reads serving navigation | 51.61–51.90 ms; 109,736 bytes growth while filling the cache, not proof of steady-state client memory |
| Actual UI handler probe, 50 Browse → external Market round trips | 31.879–40.553 ms total across three processes; 140,493 incremental retained bytes; 2 retained pages; 1 decoded record |

The UI probe uses the actual page handlers/adapter/reader with the offline frame fixture, warmed pages and explicit collection; it verifies unchanged local data, no AH calls and exactly one data-addon load. It does not measure game rendering or establish a leak/non-leak claim for a real client. Reproduce it with the normal `test_workshop_auction_market_server.lua` command; it prints `BRIDGE_UI_BENCH`. Reader benchmarking is reproducible with Market's `benchmark-bridge-reader.py`; exact measurements are in its committed JSON.

Full 32 MiB / long-window capacity, complete module/startup memory, real frame-time tails and owner Windows durability/antivirus behavior remain acceptance targets. Do not interpret synthetic 60-day-capable structures or two available observations as full-horizon pricing validation.

## Final boundaries and next approval

Fourteen authoritative mirror files match pinned Market revision `1f76f8468722f07430acb3a10d26d6ad2d20e9cd`. Schema-2 schema SHA256 is `da57e252913b68f9e60d0b7787e6975ba525176834bb40ef0adcfd6054864653`; checksum-manifest hashes are in the verification JSON. Original schema-1 bytes and pricing research fixtures are unchanged. Review coordinated amendment 001 before merging the producer/consumer PR pair.

Genuine retained production-history transfer remains **open**: Cloud proxy 403 and no alternate export. One-date genuine listing excerpts are not complete scopes or two-day bridge acceptance. The manual read-only procedure above remains required after separately authorized deployment. Owner Windows/Forever, combat/taint/fonts, real load behavior and full local PNG gates remain open. No game directory or real SavedVariables were written, no production migration/deployment or pricing activation occurred, and no automatic source switching/scans/transactions/reload was added.

Stop at M1b with both implementation PRs draft and unmerged. M2 requires separate authorization after contract/producer/consumer review: explicit destination/account/market handling, automatic atomic delivery, then separately approved freshness indicators and player-controlled reload integration. M3 supplies installed Windows and genuine Forever acceptance.
