# L1 scoped Market bridge consumer foundation

**Offline conformance prototype only.** No `TwichUI_Workshop` runtime file, TOC, SavedVariables schema, source default, UI or deployed addon changes. Market owns the proposed contract and fixtures; [UPSTREAM.json](../../tests/fixtures/market_bridge_scoped_l1/UPSTREAM.json) pins exact authoritative source and hashes. Full specification and L2 plan live at Market `contracts/bridge/scoped-l1/README.md` and `docs/workshop-scoped-bridge-l1.md` at that revision.

## Inputs and version decision

Addon base `732ccf87b825c7f93d7dbb73cae9fa9bfb001fd8`, Market base `73617a9e2ce6b32f539700c72caab4592a443a2f`. [Research PR #12](https://github.com/Twich-Team/TwichUI-Market/pull/12) was open/draft/unmerged, pinned `49cfa2bc5701657c054d01ee44817ad4a3662aa3`; it was read without merging or modifying its branch. Market's #10 provider management and #11 Explorer repair are preserved.

Selected **format twichui-market-bridge / contract 1 / schema 3 / transport 1**, with required feature `scoped_selection`, in separate proposed files. Existing readers reject unsupported schemas, so no major-version change is needed. Original schema-1/2 semantics and AMENDMENT-001 are untouched. Actual current runtime still supports **only 1/2**; schema-3 support below is proposed L3 behavior, not an enabled feature.

## Scope and exact identity

The request specifies issuer, full existing Forever market identity, sorted distinct `(item_id, full upstream variant SHA-256)` pairs, inclusive dates, algorithm/history basis, expected schema and `daily_research_v1` profile. Identical base IDs with different exact variants remain separate. Local item aggregates, item links, display names and another house/region/ruleset are not substitutes. Duplicate exact pairs refuse; distinct input order may be normalized before hashing.

`selection_id` hashes the normalized request excluding only history dates; `request_digest` includes dates; source generation ID hashes the complete source body including scope/watermark. The scope lists every requested/included identity, requested/delivered count, per-record SHA, calendar-day coverage and the exact request. `excluded=[]` means no **requested** record was dropped; the outside universe is defined by complement of the requested set and is never enumerated or priced as zero.

A published scoped generation must have `scope_complete=true`, `whole_market_complete=false` and `coverage.generation_complete=false`. Every eligible daily close for every selected record is present; `history_complete=true` means delivery completeness within scope, not that market observations exist daily. Distributions are explicitly not requested by this profile; null distributions and inherited omitted status are declared up front. Shorter chart ranges must retain source support/provenance and unchanged 14/60-day metric meaning.

Saved names and future tracked-item sets are desktop-local metadata resolving to explicit variants, not extra implemented scope types. Account/device/origin authorization and cache isolation stay outside game payloads. They must be bound to future authenticated requests/cursors and never written to game data or delivery receipts.

## Consumer outcome rules

| Situation | Required external-history behavior |
|---|---|
| Selected priced | Exact listing-price string and normal inherited numeric support checks |
| Selected bid-only | Known supply, no supported buyout price; null is not zero |
| Selected absent in complete market close | Explicit `absent`, zero counts, null price with source observation proof |
| Selected current unknown/incomplete | Null supply/counts/prices, unknown; never absent |
| Missing market date | `no_observation`, null reference, no fabricated row/interpolation |
| Only incomplete observations that date | `incomplete_only`; canonical daily close unavailable |
| Valid exact identity outside selection | `outside_scope`, no record or price; do not use existing `not_observed` as a substitute |
| Requested invalid/unavailable/not-authorized/unsupported identity or basis | Request-level failure, no partially satisfied source generation |
| Scope exceeds byte/count/window budget | Refuse entire candidate, retain last good; no silent pruning or shortened history |
| Corrupt/partial/future schema or mixed generations | Refuse activation and preserve active/previous |
| Exact signed-64 descriptive copper beyond Lua range | Keep exact string, return `unsupported` conversion |

The shared fixture has two priced items at exactly 100 copper, a historical-only item absent at the second complete close, bid-only supply ten, and a missing November 14 observation. Partial/unknown and large descriptive money examples are separate. Two available priced dates never establish the three-date Historical Value minimum. Existing source identity, upstream freshness, synthetic OR, quality/trading policy and local data remain separate.

## Minimal executable proof

`tests/prototypes/scoped_bridge_l1.lua` is **not in a TOC** and imports no networking/UI/storage code. The Python harness expands the authoritative schema plan using existing schema-2 properties; the test-only Lua proof reuses real `BridgeCodec` JSON/SHA and `BridgeValidate` Header/Record checks, adding scope membership, request hashes, per-record hashes, calendar coverage and candidate activation tests. No production implementation is forked/copied.

The inherited validator is invoked on a private validation view restoring schema-2 header preconditions. This is an internal check only: never expose its full-market flag or activate it as a legacy generation. The real schema-3 request/scope/body hashes are checked separately. L3 should factor shared evidence checks or maintain this strict private boundary. The proof does not implement cooperative scheduling or claim client responsiveness.

Source data is always parsed through existing strict data decoding. A trusted expanded **schema plan** exceeded the data-parser depth bound in the initial harness attempt; the correction constructs the trusted test plan directly, without widening production parser bounds. Data remains bounded/untrusted and no server-supplied code is evaluated. No `loadstring` or unsafe binary/compression library is added.

Lua proof validates canonical input/count bounds. Expanded Lua **source** size is a desktop pre-publication check: a Lua consumer cannot prevent a compile stall after its source has already loaded. The Market Python reference predicts exact expanded literal lengths and proves capacity refusal before its test activation. The Lua fixture path tests fixed quoted strings through the actual parser. Neither prototype is a shipped addon publisher.

## Capacity and compatibility

Initial operating proposal is default 100 exact variants intersected with ≤2 MiB canonical, ≤3 MiB Lua and ≤1,000 records. These are testing budgets, not established Forever limits. Proposed schema-3 hard bounds include 128 KiB request and 256 KiB manifest, inherited 32 MiB canonical, 64 KiB per record, 60 daily rows and 61 refs, plus 130 MiB source ceiling. V1's deployed 64 KiB manifest limit stays unchanged. Budget values may only tighten hard bounds; capacity is determined by actual bytes/history density.

Measured synthetic 100/dense-sixty: 1,298,121 canonical / 1,841,929 Lua bytes. 500/dense: 6,359,505 / 9,039,793, refused by policy; 500/sparse: 876,147 / 1,198,051, eligible by bytes. 1,000 dense/sparse exceeds proposed manifest bounds; nothing is published. Scope metadata itself is material (~31 KiB at 100). The protocol count ceiling does not guarantee every window fits.

Reuse existing M1.5 offline evidence rather than rerun a capacity matrix: 1k dense-sixty ~27 s validation CPU, ~112 ms median compile. This L1 proof adds exact bytes/hash-cost measurements only. No safe real-client bound follows from them.

| Combination | Proposed behavior |
|---|---|
| Old desktop + old addon | Valid schemas 1/2 unchanged |
| New desktop + old addon | Explicit legacy path or refuse scoped export; never label subset schema 2 |
| Old desktop + new addon | Continue to accept valid legacy data |
| New desktop + new addon | Explicit schema-3 negotiation, full scope validation |
| Future schema/features | Refuse and preserve last good |
| Interrupted/mixed update | No partial activation; complete source/receipt identity must agree |
| Wrong market/account/selection | Refuse/reset private staging; no cross-context active data leak |
| Valid legacy full-market data | Accept as legacy with original semantics |
| Valid scoped data | Only compatible new dispatch accepts it as scoped |
| Corrupt scoped data | Retain old active/previous |

Today the actual runtime reader is unchanged: tests confirm it refuses schema 3. L3 must explicitly add support; the test-only proof is not that runtime dispatch. Downgrade restores a complete supported artifact; old narrow desktop inspectors may refuse a newer artifact. `Previous.lua` is not automatically loaded by existing TOC, so cross-session publisher recovery must restore it explicitly.

## Verification

**Unit-tested:** 4 new Python-driven Lua conformance methods, including 11 shared invalid-generation mutations with last-good retention; 6 existing bridge reader methods pass unchanged. Lua syntax check passes. Market's 16 reference methods cover request-level rejection, independent hashes, all 18 negative cases, exact byte/source preflight, source archive preservation and deterministic examples.

Mirror: 15 hashed payload files (two schemas + thirteen fixture documents) plus hash manifest; all payload bytes match authoritative Market files. Hash manifest SHA-256 `c5a465e323005735444f3e5fe2ec48241f50942ebdfb7e7078049849206ec2a7`. Original v1 mirror unchanged. `UPSTREAM.json` records exact Market fixture commit/directory and file list. The proposed schema dependencies resolve to existing immutable v1 schema bytes, whose provenance remains in the v1 mirror's upstream file.

Reproduce from addon root with the existing Lua 5.1 + bit toolchain:

```sh
python3 -m unittest discover -s tests -p test_workshop_scoped_bridge_l1.py -v
python3 -m unittest discover -s tests -p test_workshop_bridge.py -v
luac5.1 -p tests/prototypes/scoped_bridge_l1.lua
git diff --check
```

No runtime reader changes were made, so no complete simulator/full suite was required for these isolated fixtures. No simulator/visual/real-client/Windows/genuine-history acceptance is claimed.

## L3 execution plan and dependencies

L2 in Market comes first: independently complete retained-history checkpoint streaming, normalized transactional desktop history/cache, persistent exact selection, authenticated scope-aware generation, streaming preflight, negotiated manual publisher with existing path/ACL/replace/readback/rollback safety, and genuine selected history acceptance. The current 32 MiB bridge generation cache is not an unlimited archive. Do not silently trim evidence or enable auto-installation to bypass its limits.

L3, separately authorized:

1. Add explicit schema 1/2/3 capability dispatch; pin independent fixtures to the accepted Market revision. Keep legacy validator behavior and exact precision/identity rules.
2. Validate scoped manifest/selection/calendar/index bounds, record/body hashes and receipt; retain immutable active while validating candidate and preserve prior distinct generation. Use source identity plus request scope in caches. Refuse unknown versions and unexpected request digests.
3. Extend external ServerMarket adapter and views with typed `outside_scope`, missing/partial/absent/unsupported/pending states. Catalogue enumerates only delivered identities; clearly label selected history. No new local-source fallback or default switch.
4. Preserve Prices/History2/local distributions/profile data and Advisor/Sell/Shopping/CraftPlanner gates. Exact variants remain explicit. Test local-state fingerprints, no eager source load, no AH action and every negative fixture.
5. Keep lazy encoded records and bounded 24-record decoded cache initially; bound added scope indexes. Instrument load/validation/history and retained/transient heaps through existing diagnostics policies. Measure the larger scoped manifest; do not assume current parser scheduling is sufficient. Focused affected tests during development; appropriate comprehensive verification once at frozen shared-runtime milestone.

L4 separately validates native Windows publisher safety, actual addon discovery/load/compile, timer cadence/readiness, p99/max frame tails, memory/global GC with representative addons, correct real retained daily history, corrupt-generation/cross-session recovery, combat behavior and byte-identical local SavedVariables. Proposed gates: nominal 2 ms, p99≤3/max≤10 ms slice, compile/load≤10 ms, incremental steady heap≤5 MiB, old+new≤16 MiB, owner-reviewed readiness. If unmet, reduce budget or separately investigate compact representation.

M2 only after L4: opt-in configured destination/account/market, automatic desktop sync and bounded/coalesced projection updates, explicit request workflow, actual source age separate from delivery time, recoverable previous data and player-confirmed apply boundary. Do not assume files can be dynamically reread or SavedVariables flushed live. Desktop-native selection avoids an extra request-flush reload; any future player-mediated text or read-only SV request queue needs its own bounded/parser/profile rules. No surprise reloads, freshness chips or automatic installation is included here.

Owner decisions for L2/L3: approve schema/profile and conservative budget layering; define desktop mirrored retention layer/disk budget; choose target capability/namespace setup and desktop-first selection; authorize acceptance hardware/profile/readiness gate. None blocks this completed L1 proof, and none authorizes production deployment.
