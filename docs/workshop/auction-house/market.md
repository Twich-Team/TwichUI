# AH-6 — Auction House Market research

This campaign integrates infrastructure before building the approved fifth page.
AH-7, automatic replacement, transactions and desktop/server synchronization are
outside its scope. `/tui ahpreview` remains standalone; `/tui ahproof` acceptance
and recovery requirements are unchanged.

## Checkpoints and integrated foundation

1. Review/merge #15 Cloud verification, preserving local defaults and unexpected-error rejection.
2. Audit/merge #16 deterministic `gallery-rgba-stored-v1` PNG serialization.
3. Review #17 safety boundaries; verify the exact integrated tree comprehensively; merge.
4. Add a bounded presentation adapter over existing market services and item discovery.
5. Implement the approved Market item/chart/fact/context hierarchy.
6. Connect Browse, Shopping, Sell, owned listings and Item Advisor without queries or transactions.
7. Review synthetic captures, measure large fixtures, run feature/mutation/full verification; publish draft only.

| Integrated PR | Merge commit |
|---|---|
| #15 | `f70a7ab8bd65cf41db7b15a729fbd0daf2ef24de` |
| #16 | `bbe4653b9273318a616850fb40873ecb72fc4585` |
| #17 / final base | `9827418b0d3624d5077f0338290a7e9d97d53ed2` |

All merged in dependency order with normal merge commits and expected-head checks.
The pre-merge disposable candidate tree `9000eaef4486e0f014e3f0a863aac67fabfaf940`
exactly matches the remote integrated baseline. `./tests/run.sh full --profile cloud`
passed: 235 files/modules, 696 Lua syntax files, all ten simulator/guard suites,
176 launches / 27,452 structured assertions, 3019.411 s. No exclusions or weaker
assertions. This is Cloud verification, not the unchanged local milestone gate.

#15 review: intended nine infrastructure/docs files only, 23 focused Python cases
and 56-page smoke pass; UTF-8 classification requires the documented send stack.
#16 independent Git-object audit: 67 exact IHDR/decompressed scanline buffers,
including hidden RGB/alpha; 134 byte-identical runtime TGAs; inventory hashes and
unchanged manifest/ArtData/input sheets checked. Sixteen gallery/encoding cases
including corruption controls pass; two complete generations are byte-identical.
#17 review: core Host/Scan/Price/posting Window and auto-scan policy unchanged;
experimental read gate remains off, and every preview transaction remains disabled.

## Presentation/data boundary

`auction/MarketData.lua` consumes only existing supported services. It does not
decode saved strings, calculate market prices, change database schemas, scan,
import, access the network or read desktop files. Explicit missing markets never
fall back to another faction. A temporary research-market selector does not change
Workshop settings. Full item-key context is preserved; unsupported variants stay
unpriced and cannot be collapsed into base-item Browse/Advisor advice.

Discovery reuses `AuctionBrowseData.Job`: deduplicated union of existing latest
items/distribution/history keys, or the shared Advisor tracked set, or current bag
slots only. No invented item database and no bank-as-bag stock. The 20,000-identity
cap, cooperative catalog and merge sort are shared with Browse; rows never decode
histories. Only selection requests metadata. Item-name/ID substring search,
category and quality filters use existing metadata. Unknown names remain searchable
by ID. Metadata refreshes preserve selected identity, top identity and pixel offset.

The selected projection uses `Facts.Of`, `Facts.Rows`, `Market.History`,
`TrendOf`, `Posture` and `Distribution`, with the existing caches/quality decisions.
One selected history projection is retained, keyed by the cached facts object;
range changes reuse it. Hidden pages invalidate jobs/timers, unsubscribe frame
events and release rows/index/market/projection. Shared Facts remains bounded by
its established 48-entry policy. Diagnostics exposes `auction.marketDetails`.

## Metric provenance

| Display | Existing authoritative source / definition |
|---|---|
| Lowest seen | `Facts.min` / `Market.Value("min")`: cheapest buyout per item in the newest saved snapshot |
| Recent listing | `Facts.recent`: existing cheapest-band representative listing price |
| Market value · 14d | `Facts.mval`: existing 14-day reference of observed Recent Prices, with service safeguards |
| Historical · 60d | `Facts.hist`: existing 60-day reference, including eligible aggregates and qualifications |
| Observed supply | `Facts.supply`: quantities and listing count at the saved read, with completeness |
| Competing price | `Facts.comp`: existing cheapest competitive tier, not seller count or current availability |
| Listing quartiles | `Market.Distribution`: existing item-weighted listing-price distribution |
| Data quality | `Facts.quality`: established level, freshness, reasons and observed days; no confidence score |
| 14-day trend | `TrendOf("min",14)`: medians of the older/newer observed halves; insufficient if either has fewer than two days |
| Price context | `Posture`: qualified Recent versus Historical comparison; unknown when existing safeguards fail |

Prices are copper per item rendered by Workshop money formatting. Observations
are listings, never confirmed sales, income, demand, sellers, forecasts or profit.
Historical coverage and the 14/60-day value definitions remain independent of the
chosen chart window. Stale, partial, damaged, missing and newer-format data retain
unavailable/qualified states from the engines.

## Chart adaptation

Recent 48h uses typed retained observation records at their actual last-sighting
timestamps. The 7/14/30/60/120-day windows show only supported daily/legacy-day
closings. Weekly, fortnight and legacy aggregates remain intact ranges, described
separately with their full boundaries/counts/provenance; they never become daily
samples. An overlapping bucket is not clipped into invented evidence. Empty
windows and one-point histories have honest text states. Requested windows do
not promise continuous coverage. No line interpolates missing observations.

The existing `UI.PriceChart` accepts optional maximum 30 markers, requested-window
placement and antique-gold coloring. Its default eight-point behavior for all
other pages stays unchanged. Only the newest 30 exact points are drawn when more
exist, with a visible disclosure; older range detail remains available in the
chart/context tooltip. This is the bounded AH-6 adapter, not a shared chart-engine
redesign.

## Cross-page and future synchronization

History buttons pass the selected item and supported market/item-key context.
They never issue Auction House reads or change queue/source choices, apply a Sell
price, infer a sale, cancel or repost. Open Browse remains saved-data research and
preserves an explicit research market. Use in Advisor opens the existing item
selection and shared track list; Advisor retains its own market settings, explained
on the action. There is no second watch database.

A future companion must validate/version/attribute imported observations through
supported Workshop ingestion/history/valuation services. The page consumes typed
facts and histories with market identity, time, source and provenance; it must
never parse external files directly. No companion, importer, server API or new
SavedVariables schema is introduced here. Existing local observations are sufficient.

## Acceptance and evidence

Implementation and final measurements are recorded below after verification.
Cloud captures are structural only: no game assets or Cinzel font evidence, no
actual pointer/keyboard, reload persistence, addon-message delivery, combat/taint,
auctioneer attribution or transaction acceptance. Neither WSL nor the real Forever
client ran in this environment.

Real-client procedure, with all existing gates left off:

1. Open `/tui ahpreview` offline; compare Market normal/narrow/scaled/long-name
   layouts to the approved mockup using actual fonts and materials.
2. Inspect locally saved markets and a missing faction; verify explicit identity,
   freshness/partial labels and empty/sparse/aggregated windows against Workshop.
3. Search/filter, track/untrack, scroll deeply and wait for metadata; selection and
   viewport must hold. Change bags and revisit pages; no background catalog remains.
4. Open history from every related page and return to Browse/Advisor. Confirm the
   crafting plan is unchanged and Sell never receives an automatic price.
5. Visit/leave an auctioneer without pressing any experimental read action. Verify
   Market causes no query, replacement, gold change or auction-state change.
6. Complete the separate AH-1a and native-read/transaction procedures in
   lifecycle-proof.md and overnight.md under their own authorization. This campaign
   does not accept or activate them. AH-7 remains a separate milestone.

### Page and cross-page checkpoint

Data adapter commit: `019bf21`. Market mutation campaign: **196/196 detected**,
zero survivors/invalids/timeouts/infrastructure errors, 832.0 s. Source remained
byte-identical throughout. Page and cross-page feature verification in an isolated
checkout: **57 files pass**, 161 Lua syntax files, **29 preview launches / 3,161
structured checks** plus unchanged **4 proof launches / 431 checks**, **454.178 s**.
All original assertions, replay and wrong-expectation controls remain active.
Report: `/workspace/ah6-ui-verification/test-output/verification/feature-auction-house-m3t4gdao/`.
All 14 page/test/simulator files transferred byte-identically to the development
branch. Reviewed all ten new Market poses; final polish will address the clipped
empty-list message and explicit UTC date formatting before comprehensive checks.
