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

Unit tests run the actual reader, strict parser/hash properties, both schemas and negative fixtures; saved market/profile fingerprints remain identical. UI tests use the actual reader/adapter and sentinels that reject local-price calls and AH operations. Mutation coverage includes generation integrity, identity, history window, saved-history isolation, duplicate JSON and arithmetic precision. The simulator adds an external-history pose without weakening existing replay/negative controls. Final evidence and exact counts are recorded after the frozen milestone runs.

Market's `scripts/verify-bridge-e2e.py` starts a disposable authenticated FastAPI/SQLite server, forces four HTTP pages, invokes the actual Rust client/cache/exporter, syntax-checks the artifact and loads it through this actual Lua reader. Independently calculated shared expectations cover Nov 13 and Nov 15 synthetic observations, the Nov 14 gap, canonical 100/120 copper, exact variants, historical-only absence and bid-only listings. A separate process verifies the data addon alone does not create Workshop. This is synthetic cross-component evidence, not production acceptance.

Cloud cannot reach the authorized production endpoint (proxy 403); the owner confirmed no alternate export. Committed genuine Nov 14 listing excerpts are not complete books or two-day histories. The genuine-history gate remains open. No production state, owner installation or real SavedVariables were accessed.

Windows CI can establish compilation and disposable-host filesystem tests. Owner Windows reparse/ACL/antivirus/power-loss behavior, actual Forever addon load timing/fonts/combat/taint, full local PNG acceptance and installed real-history acceptance remain separate gates. Simulator output is handler/state evidence and structural screenshots only.

## Read-only acceptance and M2 sequence

After separately authorized server deployment, use the existing member/device connection and select the independently verified Forever market. Export to the displayed companion staging directory, record generation, algorithm, available UTC dates and source timestamps, and compare selected exact-variant daily records with authenticated retained server observations. Do not manufacture earlier dates, infer sales, or treat legacy means as canonical. Test interruption/auth expiry and verify the prior generation/artifact survives.

On a disposable Windows test profile, inspect the fixed TOC/no SavedVariables, luac syntax and Data.lua integrity; exercise SavedVariables/game-directory rejection, symlink/junction/reparse rejection, foreign ownership/broad ACL rejection, wrong-account/market and failed replacement. Keep actual installations untouched until M3 authorization. In a separately authorized disposable Forever profile, preserve byte-for-byte SavedVariables backups, explicitly load Workshop/source, compare exact dates/variants/provenance, try corrupt/future artifacts, and verify local histories unchanged and no scans/transactions/reload. Do not claim this client gate from the simulator.

M2 should first review and merge the coordinated contract/Market producer, then this pinned consumer; design explicit destination/account/market selection and atomic automatic delivery using the proven staging publisher; add separately approved freshness indicators and player-controlled reload handling. M3 supplies installed Windows and real Forever acceptance. Automatic delivery, freshness chips, reload integration, live deployment and pricing activation are outside this PR.
