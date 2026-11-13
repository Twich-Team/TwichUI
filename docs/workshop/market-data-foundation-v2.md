# Workshop Market Data Foundation 2.0 (A1: architecture and data contract)

Status: **planning, revised after owner review** (first version `4c74e94f`, revision 2026-11-12, branch `feature/workshop`). **Milestones A2 and A3 are built** (see "A2 as built" and "A3 as built" after section 15); everything else here is still a plan. This document is the source of truth for the A2 to A12 implementation campaign; `docs/workshop.md` describes what exists.

Evidence labels used throughout:
- **[verified]**: read in this repository's code, in `git show v1.3.0:...`, or in the Forever UI source (`../wow-ui-source`, branch `forever`).
- **[measured]**: a throwaway prototype run offline (Lua 5.1, WSL dev machine, synthetic data). Scripts: [a1-prototypes/](a1-prototypes/). An offline figure never stands in for the client.
- **[real-client]**: observed in Forever 1.60.1 build 70888 (as recorded in `docs/testlab.md` or the testing roadmap).
- **[proposed]**: a design choice in this document. **[approved]**: an owner decision (section 14).
- **[unknown]**: needs a probe or an in-game check before anything relies on it.

### What changed in the revision
| Area | First A1 | Revised |
|---|---|---|
| Daily history | 14 days | **30 days for every item** (D2), measured +24% over 14 days in the worst schedule |
| Intraday | none per item | **8-point, 48-hour ring per item**, with an exact "unchanged" rule (D3) |
| Daily point | last scan's values only | last scan's values **plus the day's low/high** of minimum, Recent Price and supply, and the scan count (no extreme is erased by a later scan) |
| Buckets | 9 fields, means of Recent Price only | 13 fields: low/mean/high of minimum, Recent Price and supply, mean listings |
| Day and scan logs | 64-scan log | scan log covering at least 48 h, plus a **120-day day log** so every gap has a reason |
| Update method | decode and re-encode per scan | **append-only update** of the newest daily segment (measured about 15x cheaper, identical output) |
| Selling | Market Value → Recent → Minimum as a sell price | **Separate services**: valuation, competition, listing suggestion, proceeds, Advisor decision (D9); no valuation is ever a sell price |
| Large markets | not addressed | **budget guard** with an ordered, reported compaction ladder (D4) |
| Recent Price | 13 cases | **+10 adversarial cases**, the manipulation bound stated, thin-market reasons added; algorithm unchanged (D1) |
| Milestones | A2 to A7 | A2 to A7 adjusted; **A8 selling services and Item Advisor** split out; charts, variants, Ledger, import after |

---

## 1. Executive summary

**The model [approved in principle]:** keep today's compact, 1.3-readable current-price entry unchanged and add beside it:
1. a **distribution summary** per item for the newest scan: the cheapest 6 price tiers (exact), a tail total, quantity-weighted quartiles and the **Recent Price** (band mean), computed at scan time from the full listing list;
2. a **per-item history** in three resolutions: an **8-observation intraday ring** (48 h, real timestamps), **30 days of daily points** (closing values and the day's ranges), then **weekly buckets to day 60 and two-week buckets to day 120** (low/mean/high of minimum, Recent Price and supply);
3. **market-level logs**: every scan of the last 48 h (at least 64), and every scan day of the last 120 days, with quality flags.

The existing minimum-only history is **frozen, never converted**; the database version goes from 1 to 2 so TwichUI 1.3 becomes read-only (1.3 rebuilds the whole market table on every commit and would otherwise drop the new fields) [verified].

**Cost [measured, synthetic]:** a full 40,000-item market after 120 days of three scans a day: **38.5 MB of history text, a 40 MB saved file, 47 MB resident after loading**, plus about 5 MB of snapshot data. A 20,000-item market at the same rate: about 19 MB. One scan a day: about 22 MB at 40,000 items. Today's format: about 8 MB worst. Offline, the 40 MB file loads in 0.19 s with plain `dofile`; the client's loader is [unknown] and is measured before history writes ship (A4 gate).

**Semantics:** a **valuation** (Market Value, Historical Value) says what something has been listed for; **competition** says what is listed now; a **listing suggestion** (later, A8) proposes a posting price from competition; **proceeds** subtract known fees and say what is unknown; the **Item Advisor** decides Vendor / Auction / Disenchant / Unknown from those, conservatively. They are separate result types and cannot be swapped by accident.

**Automatic scanning [approved]:** on by default, at most once per market per 60 minutes, 15-minute back-off after a refusal, once per visit, Stop on the bar, never in combat, after a client probe confirms the request is accepted without a click.

---

## 2. Verified current implementation and API constraints

### 2.1 Repository state
- Branch `feature/workshop`; A1 commit `4c74e94f` on top of M7.1 `2fd4b775`; tree clean at the start of the revision [verified].
- Released baseline `v1.3.0` saves `f = 2` markets in `v = 1`, 7 exact days + 3 x 28-day buckets, 120-day retention, and treats `v > 1` as held [verified with `git show v1.3.0:`].
- In `v1.3.0`, **only `Prices.lua` writes `TwichUIWorkshopDB`**: `Store(true)` (creates the table when absent) and `Job:Apply` (evicts the oldest market over 3, replaces `db.markets[key]` with a new table of known fields, deletes the legacy copy). `BeginCommit` and `Apply` both return `held` first when `p.v > 1`. No other file in the release names the global outside tests and docs [verified by grep over `git ls-tree v1.3.0`].
- Focused tests on the A1 base: `test_workshop_market.lua`, `test_workshop_market_reference.lua` (200 houses, 9,480 scans, 239,167 queries), `test_workshop_prices.lua`: all PASSED [verified]. No production file changed since.

### 2.2 Saved data today [verified, `Prices.lua`, `History.lua`]
```
TwichUIWorkshopDB = { v = 1, markets = { ["Realm|Side"] = market } }     -- Workshop's own LoD SavedVariables
market = { f = 2, scope = "full", realm, side, at, complete, cut, read, used, partial, n, hn,
           items = { [itemID] = "p,q,l,t,x" },
           hist  = { [itemID] = "d,p;d,p;...|b,lo,hi,sum,n;..." },
           sd    = { day, ... } }                                         -- at most 32 scan days
```
- `p` cheapest unit buyout (stack buyout / count, rounded up, at least 1 copper; the cheapest by exact fraction); `q` items at exactly that fraction; `l` buyout listings; `t` items; `x` next higher whole-copper price, 0 when none or when it rounds to `p`.
- History: one value per UTC day (the day's last whole-read scan), 7 exact observed days, 28-day buckets (`day // 28`), at most 3, 120-day retention. Cut or count-changed scans add nothing; whole reads with `hasAllInfo == false` records do.
- Limits: 40,000 items per market, 3 markets, 250,000 records, commit steps of 120 items, finalize steps of 400. A complete saved scan is never replaced by an incomplete one (`kept`); `Apply` writes everything at once.

### 2.3 Market API today [verified, `Market.lua`]
`Source, Info, Markets, Price, Quote, Stats, Trend, Compare, Observed, Series, Status, Freshness, AgeShort`, read-only, each with a `basis` sentence and a reason word for every "no". Consumers: `Session.Opportunities`/`Shopping` (through `Market.Price`, `Prices.Estimate`, `Prices.Quote`), `WorthTip`, `ViewOpportunities` (`Price`, `Stats week`, `Series`), `ViewOverview`, `Window` (`Info`, `Status`).

### 2.4 Scan lifecycle today [verified, `Scan.lua`]
Player click only. Throttle ready → `ReplicateItems` → first update (90 s) → 2 s quiet (at most 10) → read `0 .. n-1`, 400 per tick → stepped `ItemsJob` → restart on a count change (3) → re-read after 4 s for missing info (2) → stepped commit → atomic `Apply`. Closing before saving interrupts and writes nothing; during saving it finishes.

### 2.5 Forever auction API facts [verified, `AuctionHouseDocumentation.lua`, forever]
| Fact | Consequence |
|---|---|
| `ReplicateItems()` documented for whole-house queries; no restriction flag listed | Whether it needs a click is not stated [unknown]. |
| `GetReplicateItemInfo(index)`: 18 values incl. count, buyoutPrice, owner, itemID, hasAllInfo; `AllowedWhenUntainted` | Item id only per record; owner names are never stored. |
| `GetReplicateItemLink(index)`, `GetReplicateItemTimeLeft(index)` | Variants need a second call per record [cost unknown]. |
| `ItemKey = { itemID, itemLevel, itemSuffix, battlePetSpeciesID }` | The client treats suffix and level as identity. |
| `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, throttle events; the core already handles `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with `Auctioneer` (`modules/AuctionatorSkin.lua:412`) | The open signal is available to the always-loaded core. |
| `Blizzard_AuctionHouseUI` LoD with a camelot-specific data file | Commodity (any quantity) versus whole-auction buying is [unknown]. |
| No auction house cut or deposit formula in the source | Fees stay unknown until confirmed in the game. |

### 2.6 Performance facts carried forward
- [real-client] M7.1: one synchronous `Items()` was an 82 ms step at 12,000 items; now stepped. Client CPU was about 2.4 times offline in one comparison (order of magnitude only).
- [real-client] `string.format("%d")` refuses values above 2^31: encoders use `("%.0f")`. NaN compares equal to everything: `W.Finite` first.

---

## 3. Data schema [proposed; final for A2]

### 3.1 Database
```
TwichUIWorkshopDB = { v = 2, markets = { [key] = market } }
```
`v = 2` is written by the first commit of the new code inside `Apply`. 1.3 then holds (reads, never writes). `v > 2` is held by the new code. Imports are not stored here (section 9).

### 3.2 Market (`f = 3`)
```
market = {
  -- unchanged (1.3 reads these)
  f = 3, scope = "full", realm, side, at, complete, cut, read, used, partial, n, hn, sd,
  items = { [id] = "p,q,l,t,x" },     -- unchanged entry and rules
  hist  = { [id] = "<v1 string>" },   -- FROZEN legacy minimum history: trimmed by expiry, never extended
  -- new
  snap   = { seq, kind = "full", alg = 1, at, records, used, invalid, noBuyout, partial, items, auto, client },
  dist   = { [id] = "<distribution entry>" },   -- items with 2 or more distinct unit prices
  h2     = { [id] = "<ring>|<newest day>:<daily points>" },
  c2     = { [id] = "<buckets>" },
  scans  = { "seq,at,flags,items,records", ... },  -- oldest first: every scan of the last 48 h, at least 64, at most 256
  days   = { "day,scans,flags", ... },              -- oldest first: every scan day of the last 120 days (at most 120 entries)
  v2from = day,                                     -- first day of v2 history (legacy/v2 boundary)
  compact = { level, at, items },                   -- budget guard record (section 7.4), absent when never used
}
```
- `seq` increases by one per accepted scan. `flags` (digits of a bit set): whole read, complete, cut, count changed, partial info, fed history, automatic, imported (reserved).
- The **scan log** includes scans that could not feed history (cut, changed): a chart marks them as "incomplete scan" rather than treating the absence of points as "not listed".
- The **day log** keeps, per scan day, how many accepted scans happened and whether any was a whole read; a day with no entry had no scan. This is what separates "not scanned" from "scanned, not listed" for 120 days.
- `hn` keeps its 1.3 meaning (items with legacy history). `client` is the build string when readable.

### 3.3 Per-item entries

**`items[id]`: unchanged** (about 19 B per item [measured]).

**`dist[id]`** (decimal `%.0f`; about 99 to 107 B per multi-tier item [measured]):
```
"alg,r,a,q25,q50,q75,hi,near|p1:q1:l1:m1;...;p6:q6:l6:m6|tq:tl"
```
`r` Recent Price, `a` its anchor, `q25..q75` quantity-weighted quartiles, `hi` highest unit price, `near` items at or below 1.10 x `r`; tiers: the cheapest 6 distinct whole-copper unit prices (rounded up, as a buyer sees them) with items, listings and the largest single listing (`m`, omitted when `l = 1`); `tq:tl` items and listings beyond tier 6. One-price items have no entry (everything equals `p`). Minimum, total items and listings, next price, spread and flags are derived on read.

**`h2[id]`: intraday ring and daily points**
```
"<ring point>;<ring point>...|<newest day>:<daily point>;<daily point>;..."
ring point   "m,dm,p,dr,t,l[!]"
daily point  "dd,p,dr,t,l[,n,dpl,drl,drh,dtl,dth][!]"
```
| Field | Meaning |
|---|---|
| `m` | minute number (`floor(time / 60)`) of the first sighting; absolute for the first ring point, a delta from the previous point after that |
| `dm` | minutes the identical observation was seen again after `m` (0 = seen once) |
| `p`, `dr`, `t`, `l` | minimum, Recent Price minus minimum (`r = p + dr`), items listed, listings |
| `!` | a scan behind this point had records without all their information (`partial > 0`) |
| `newest day` | absolute UTC day of the newest daily point (so a new day is appended without decoding the string) |
| `dd` | first point: absolute day; later points: days after the previous point |
| daily `p, dr, t, l` | **closing values**: the last whole-read scan of that day that listed the item |
| `n, dpl, drl, drh, dtl, dth` | present only when 2 or more whole-read scans listed the item that day and some value moved: scan count; closing minimum minus the day's lowest minimum; closing Recent minus the day's lowest Recent; the day's highest Recent minus closing Recent; closing items minus the day's fewest; the day's most minus closing |

**`c2[id]`: buckets**
```
"k,s,n,plo,dpm,dph,rm,drl,drh,tm,dtl,dth,lm;..."
```
`s` is 7 (weekly) or 14 (two-week), `k = day // s`; `n` observed days; minimum: lowest of the days' lows (`plo`), mean of closing minimums (`plo + dpm`), highest closing minimum (`mean + dph`); Recent Price: mean of closing values (`rm`), lowest day low (`rm - drl`), highest day high (`rm + drh`); supply: mean closing items (`tm`), fewest (`tm - dtl`), most (`tm + dth`); `lm` mean listings. Means round half up; merging two buckets uses `round((m1 x n1 + m2 x n2) / (n1 + n2))`, so a two-week mean can differ from the exact mean of its days by at most 1 copper (stated in the API).

**Retention rules (exact):**
- Ring: at most 8 points, none whose last sighting (`m + dm`) is more than 48 hours before the market's newest whole-read scan. The read API also filters by the caller's window.
- Daily: points move to buckets only when the daily tier spans more than 36 days, a whole calendar week (`day // 7`) at a time, and only weeks entirely older than 30 days. **Guarantee: every observed day of the last 30 days is a daily point** (up to 36 can be).
- Weekly buckets are merged pairwise into two-week buckets (`k = week // 2`) once they end more than 60 days before the newest scan; nothing ending more than 120 days back is kept. Because 7, 14 and v1's 28 all divide 28, every tier falls on the same week boundaries.
- An item whose strings hold nothing after expiry is removed; a market whose newest scan is more than 120 days old is removed at the next commit of any market (its history has fully expired by definition).

### 3.4 How scans feed each tier (D3, section 4 of the brief)
| Scan kind | `items`/`dist` | ring | daily | day log / scan log |
|---|---|---|---|---|
| complete whole read | replaces (as today) | appended or extended | close values replaced, ranges and `n` updated | recorded |
| whole read with partial info | replaces unless a complete one is kept (as today) | appended with `!` | updated, `!` | recorded, partial flag |
| cut or count changed | may replace an incomplete one only (as today) | **nothing** | **nothing** | recorded as incomplete |
| interrupted, failed, stopped | nothing | nothing | nothing | nothing (nothing is accepted) |

**"Unchanged" (ring compression), exactly:** a new observation is merged into the newest ring point only when `p`, `r`, `t` and `l` are all identical **and** the partial flag is the same; then that point's `dm` grows to the new time. Anything else appends a point. A merged point means "seen at `m` and again at `m + dm` with identical values"; the chart draws it as a flat segment between those two real times and claims nothing between other points.

**Daily point from several scans:** the closing values come from the last whole-read scan that listed the item; the day's lows and highs keep every earlier extreme. A later scan therefore cannot erase evidence of a dip or a spike that day. After the ring expires the day keeps its closing values, its ranges and its scan count; **what is lost is when during the day each extreme happened and the order of changes.**

**Absent versus not scanned:** an item missing from a whole-read scan gets no point (never a zero). The day log and scan log tell the chart which of "not scanned", "scanned, not listed" or "only incomplete scans" applies.

### 3.5 Not stored
Seller names, bids, bidders, every listing of every scan (section 7, option R), and anything derivable on read (spreads, quality, posture, valuations).

### 3.6 Item identity and variants (D6 approved)
- Key: item id. The cheapest variant sets `p`; `dist` and history mix variants [verified: records carry the id only].
- `Market.*(item, { variant = true })` keeps answering `nil, "variant"`. For an item whose class can carry random suffixes (weapon or armor by `GetItemInfoInstant`, uncommon or better), every answer carries `mixedvariants`; Data Quality is at most `limited` for valuation of such items and the Advisor never recommends Auction from mixed data (section 4C).
- Later (A10, after a probe of `GetReplicateItemLink` cost and suffix frequency): suffix keys `"id:s<suffix>"` for weapons and armor only, snapshot first, history later. Stack size is never identity.

---

## 4. Price sources and services [proposed; D7 to D9 approved]

Every result carries `role`, one of `valuation`, `competition`, `suggestion`, `proceeds`, `advice`, plus `basis`, `at`, `age`, `freshness`, `quality`, `provenance` and reasons. A function of one role never returns a value of another role, and no service takes a `valuation` result as its price input (section 4C).

### 4A. Valuations (`role = "valuation"`): references, never a sell price
| Source | Meaning | Inputs, window | Missing | Never claims |
|---|---|---|---|---|
| **Minimum Buyout** | cheapest valid buyout per item, newest snapshot (`items.p`) | snapshot | `unlisted`, `outofscope`, `nomarket`, `variant` | a typical or sale price; more than tier 1 available at it |
| **Recent Price** | representative **listing** price: band mean (section 5) | snapshot, `dist.r` | as above; one price → `p` | a sale price or expected sale price |
| **Market Value** | recency-weighted median of daily closing Recent Prices over 14 days; weights 4 (age 0 to 2), 2 (3 to 6), 1 (7 to 13); weighted median = first value (ascending) whose cumulative weight reaches half the total | `h2`, 14 days | none in 14 days → `stale`; one day → value, quality `limited` | a sale average; legacy minimum days are never used |
| **Historical Value** | median of closing Recent Prices over observed days in 60 days; days 0 to 30 individually, weekly buckets by their mean weighted by `n` | `h2` + `c2`, 60 days | fewer than 3 days → `insufficient`; `aggregate = true` when buckets contributed | anything about days not scanned |
| **Long-term range** | lowest and highest Recent Price (day ranges included) and lowest minimum over 120 days; legacy days feed the minimum only, labelled | all tiers | `nodata` | a value (it is a range) |
| **Dispersion** | snapshot `spread = (q75 - q25) / q50`: `tight` < 0.10, `moderate` < 0.30, `wide`; `cheapoutlier` when `p < r / 2`; `farbelow` when fewer than 5 listings and `p` is under half the second tier | `dist` | — | sales volatility |
| **Supply** | items, listings, items near the Recent Price, at the minimum; history: closing items and day ranges | snapshot, history | — | demand or sales ("listed", never "sold") |
| **Trend** | one metric only (Recent, Minimum or Supply): median of the newer half of the window's observed days against the older half; 14-day default; 2 days per half; `flat` under 5% | history | `insufficient` | a forecast |
| **Posture** | Recent Price against Historical Value: `cheap` < 0.85, `expensive` > 1.15 **[approved D8]** | needs Historical from 5+ observed days, Quality at least `fair`, at least 3 listings | `unknown` with the reason | that a low minimum is a bargain (the minimum is never the compared value) |

Existing `Market.Price/Stats/Trend/Compare/Series/Observed` keep their minimum-based meanings and basis sentences.

**Data Quality [approved D7, policy version 1]:** a level and readable reasons, computed on read, **versioned** (`Market.QUALITY_POLICY = 1`); a later policy can change thresholds without touching saved data.

| Level | All of |
|---|---|
| `good` | snapshot complete, age ≤ 24 h, ≥ 5 listings, spread not `wide`, ≥ 7 observed days in 30, no `mixedvariants`, no `farbelow` |
| `fair` | age ≤ 3 days, ≥ 3 listings, not `cut`, no `mixedvariants` |
| `limited` | anything else **with a price** (a 1-listing, fresh, complete item is `limited` with "Only 1 listing", and its values are still returned) |
| `none` | no price (`unlisted`, `nomarket`, `variant`, `outofscope`) |

Thin markets are therefore never "worthless": they are shown, with their reason, and only the services that act on them (Posture, Advisor) become conservative.

### 4B. Competition (`role = "competition"`): what a seller would compete with now
`Market.Competition(item, qty, opt)`: the current tiers (6 exact, tail total), the lowest **competing** price (the cheapest tier at or above half the Recent Price anchor, so a bait listing under the band filter is shown but marked), items listed at or below a given price, how deep the cheapest tiers are relative to `qty`, the snapshot's age and quality. Evidence only; no suggested price.

### 4C. Listing suggestion (`role = "suggestion"`, A8): a candidate posting price, never a promise
`Sell.Suggest(item, qty, opt)` with `opt.strategy` (v1: only `"match"`, posting at the lowest competing price; undercut amounts and patient strategies are later choices).
- **Base price comes from competition only.** Valuations are used as **checks that add flags**, never as the price:
  - Market Value more than 1.5 x the competing price → keep the competing price, flag `belowusual` ("listed below its usual price").
  - Competing price more than 1.5 x Historical Value → flag `aboveusual` ("may not sell at this price").
  - Recent Price moved more than 15% since the previous day → flag `moving`.
- No competing listing → state `nocompetition`; the answer shows Market Value as a **reference**, not a suggestion.
- Quality below `fair`, snapshot older than 3 days, or `mixedvariants` → state `uncertain` (no price) with reasons.
- `qty` above the competing tier depth is fine (a seller does not need depth), but the answer says how many items already sit at or below the price.

### 4D. Proceeds (`role = "proceeds"`, A8)
`Sell.Proceeds(price, qty, opt)`: gross = price x qty; cut from `Prices.CUT` when confirmed for the side, else `cut = nil` and the label "before the auction house cut"; deposit `nil` and "deposit not known" until a formula is confirmed in the client; `sold = "notguaranteed"` always. **Never** multiplied by an invented sale probability. Sell-through arrives only with the Ledger (A11).

### 4E. Item Advisor (`role = "advice"`, A8): Vendor, Auction, Disenchant or Unknown
Inputs: vendor sell price (`Worth.lua` already reads it), binding, the suggestion, proceeds, quality, variant status. Policy version 1, conservative:
| Condition | Decision |
|---|---|
| bound or not auctionable | Vendor if it has a vendor price, else Unknown |
| `mixedvariants`, or suggestion state `uncertain`/`nocompetition` | Vendor if it has a vendor price ("auction value uncertain"), else Unknown |
| suggestion gross ≥ 1.5 x vendor price **and** gross - vendor ≥ policy minimum (proposed 1 gold), quality ≥ `fair` | Auction, with flags (`beforecut`, `deposit unknown`, `aboveusual`, `notguaranteed`) |
| otherwise with a vendor price | Vendor |
| Disenchant | always Unknown (no outcome data; never fabricated) |
| nothing known | Unknown |

The 1.5x margin stands in for unknown fees, deposits and the risk of an unsold listing; it is policy, versioned, and replaced by real figures when the cut, deposit and Ledger data exist.

**Fallbacks required by the brief, in one place:** old data → `uncertain` beyond 3 days; few listings → `limited`/`farbelow` reasons, Posture `unknown`; history disagrees with current → flags `belowusual`/`aboveusual`, the current competition still sets the price; Market Value much higher than competition → competition wins (`belowusual`); fees unknown → `beforecut`/deposit unknown, margin rule; sale probability unknown → `notguaranteed`, never a probability; variants mixed → no Auction advice; disenchant unknown → Unknown.

### 4F. Purchase cost (`Market.Cost`, A5)
Walks tiers 1 to 6 for the quantity needed: `exact`, `range` (whole-auction buying: up to `m - 1` items over-bought at the last tier; every multi-listing walk is a range until the commodity question is answered), `estimate` (beyond 6 tiers: "at least"), `few`, `none`. Never claims the listings still exist.

### 4G. Future sources
Actual sale prices, sell-through and fees from the Ledger (A11); external data (A12, section 9). Each arrives as its own `role`/`kind`, never written into `h2`.

---

## 5. Recent Price: the band mean [D1 approved provisionally]

### 5.1 Definition (unchanged)
Listings of one item in one snapshot: whole-copper unit price `u`, items `q`, ascending; `T` total items.
1. **Anchor** `a` = the price of the first listing whose cumulative items are **more than** 25% of `T`.
2. Ignore listings with `u < a / 2`.
3. **Recent Price** = item-weighted mean of the cheapest 30% of the remaining items (a fraction of a listing counts at the boundary), rounded half up, at least 1.

Labelled everywhere as a **representative listing price**, never an expected sale price.

### 5.2 Candidates and cases (copper; recomputed by [a1-prototypes/algos.lua](a1-prototypes/algos.lua) for the revision [measured])
A = weighted 25% point; B = cluster mode (clusters within 5%, the fullest that starts in the cheapest half); **C = band mean (approved)**.

| Case | Listings (price x items) | Min | A | B | **C** |
|---|---|---|---|---|---|
| 1 healthy spread | 9500x5, 9800x5, 10000x10, 10200x10, 10500x10, 11000x5 | 9500 | 10000 | 10233 | **9741** |
| 2 one 1c listing, deep market | 1x1, 5000x40, 5200x10 | 1 | 5000 | 5040 | **5000** |
| 3 thin, one cheap unit | 1000x1, 5000x3 | 1000 | 5000 | 5000 | **5000** |
| 4 one absurd high listing | 5000x10, 9990000x1 | 5000 | 5000 | 5000 | **5000** |
| 5a large wall just below | 4900x200, 5200x5 | 4900 | 4900 | 4900 | **4900** |
| 5b few cheap under a wall | 4500x5, 6000x200 | 4500 | 6000 | 6000 | **5878** |
| 6 two clusters | 100000x10, 200000x90 | 100000 | 200000 | 200000 | **166667** |
| 7 one listing | 300000x1 | 300000 | 300000 | 300000 | **300000** |
| 8 100 listings 1c apart | 5000..5099 x1 | 5000 | 5025 | 5050 | **5015** |
| 9 one 200-stack vs singles | 4000x200, 6000x5 | 4000 | 4000 | 4000 | **4000** |
| 10 rare, far apart | 800000, 1500000, 4000000 (x1) | 800000 | 800000 | 800000 | **800000** |
| 11 bait volume, 29% of supply | 2000x8, 5000x20 | 2000 | 2000 | 5000 | **2143** |
| 12 bait volume, 20% of supply | 2000x5, 5000x20 | 2000 | 5000 | 5000 | **5000** |
| **Adversarial (revision)** | | | | | |
| 13 thin, two far apart | 10000x1, 40000x1 | 10000 | 10000 | 10000 | **10000** |
| 14 thin, one 1c among three | 1x1, 9000x1, 9500x1 | 1 | 1 | 1 | **1** |
| 15 widely separated equal clusters | 10000x50, 1000000x50 | 10000 | 10000 | 10000 | **10000** |
| 16 large cheap wall | 4000x1000, 5000x20 | 4000 | 4000 | 4000 | **4000** |
| 17 large expensive wall | 5000x20, 9000x1000 | 5000 | 9000 | 9000 | **8739** |
| 18 manipulator: 24% of supply just over half | 2510x12, 5000x38 | 2510 | 5000 | 5000 | **3008** |
| 19 manipulator: 26% just over half | 2510x13, 5000x37 | 2510 | 2510 | 5000 | **2842** |
| 20 manipulator: 24% just under half | 2490x12, 5000x38 | 2490 | 5000 | 5000 | **5000** |
| 21 one 1000-stack cheap, two singles | 3000x1000, 5000x1, 5100x1 | 3000 | 3000 | 3000 | **3000** |
| 22 three singles under a 1000-stack | 5000x3, 9000x1000 | 5000 | 9000 | 9000 | **8960** |

Worked checks: case 1: T = 45, 25% = 11.25, cumulative 5, 10, 20 → anchor 10000; 13.5 items: 5 x 9500 + 5 x 9800 + 3.5 x 10000 = 131,500 / 13.5 = **9741**. Case 18: T = 50, cumulative 12 is not above 12.5 → anchor 5000; 2510 ≥ 2500, kept; 15 items: 12 x 2510 + 3 x 5000 = 45,120 / 15 = **3008**. Case 17: anchor 9000; 306 items: 20 x 5000 + 286 x 9000 = 2,674,000 / 306 = **8739**.

### 5.3 What the adversarial cases show
- **Manipulation bound (cases 18 to 20).** A seller with **less than 25% of supply** priced just over half the honest price can pull the band mean to about **0.58 x** the honest price at most ((0.25 x 0.5 + 0.05 x 1) / 0.3); priced under half it is ignored entirely (case 20). With **25% or more** of supply, the anchor moves to their price (case 19): that supply is real and buyable, so a listing estimate follows it. Market Value (14-day weighted median) and Historical Value (60-day median) dampen a one-day manipulation; Posture then reads `cheap`, which the Advisor treats as information, not advice.
- **Thin markets (13, 14).** With 1 to 3 listings every method returns about the minimum; case 14 shows a 1-copper listing **defeats all three** when it is a third of supply. The algorithm is not changed; instead the snapshot reason `farbelow` ("the lowest of few listings is far below the others") is raised, Quality becomes `limited`, Posture is `unknown` and the Advisor will not suggest an auction from it.
- **Separated clusters (6, 15).** C follows the cheaper cluster in proportion to its supply; `spread` is `wide`, so Quality cannot be `good`, and Competition shows both clusters.
- **Walls.** A cheap wall sets the value (16, correct: it is buyable). An expensive wall dominates the value (17, 22) while a few cheaper items exist: Recent Price says 87 to 90 silver and **Competition says 50 silver**. That difference is exactly why a listing suggestion is built from competition, not from Recent Price (section 4C).
- **Large single stacks (9, 21).** Prices are per item. Whether a buyer can take part of a 1000-stack is [unknown] (commodity question); `Cost` returns a range covering whole-stack buying.

### 5.4 Arithmetic and cost
Exact integer arithmetic while `u x q x 10 < 2^53` (weights in tenths of an item), otherwise double arithmetic, documented within 1 copper; round half up. Per item: one sort of distinct prices. Finalize at 10k / 20k / 30k / 40k items: 0.15 / 0.29 / 0.45 / 0.62 s total, worst 400-item step 7.5 to 12.9 ms offline [measured, wide synthetic spread, 7.6 to 9.4 tiers per item]: A3 steps by **distinct tiers** (about 1,000 per step), not by items.

---

## 6. History and chart support

### 6.1 Chart support matrix [proposed]
| Range | Resolution available | Metrics | Guarantee | Exact or aggregate | Min and Recent both? | Supply shown as | Missing shown as | Lost irreversibly |
|---|---|---|---|---|---|---|---|---|
| 24 h | ring points (real timestamps) + "now" snapshot | p, r, t, l | the last 8 distinct observations within 48 h | exact observations; merged points are flat segments between two real times | yes | items and listings per observation | gap between observations (no line beyond 3 h), incomplete-scan markers from the scan log | nothing within the ring's reach; anything older than 8 changes |
| 48 h | same | same | same | same | yes | same | same | same |
| 7 days | daily points + ring for the last 2 days | p, r, t, l closing + day lows/highs | every observed day | exact days; day ranges are exact extremes of that day's scans | yes | closing items with the day's fewest/most as a band | no point; gap reason `noscan`/`unlisted`/`incomplete` from the day log | time of day of each extreme after 48 h |
| 14 days | daily points | same | every observed day | exact days | yes | same | same | same |
| 30 days | daily points | same | every observed day of the last 30 | exact days | yes | same | same | same |
| 60 days | 30 daily + weekly buckets | buckets: min low/mean/high, Recent low/mean/high, supply fewest/mean/most, mean listings, observed days | weekly beyond day 30 | **aggregate** beyond day 30 (bands, never daily points) | yes | band per bucket | bucket with `n` < 7 says how many days it holds; missing weeks are gaps | individual days and their order inside a week |
| 120 days | + two-week buckets beyond day 60, + frozen legacy minimum | as above; legacy: minimum lo/hi/mean per 28 days | two-week beyond day 60, to day 120 | aggregate | Recent from `v2from` only; legacy feeds **minimum only** | as above | before `v2from`, Recent simply has no data (labelled "Recent Price recorded since ...") | weekly detail beyond 60 days; two-week means can differ by 1 copper from exact |

### 6.2 Chart-ready API [proposed; A4]
`Market.History(item, metric, opt)`; `metric` = `min`, `recent`, `supply`, `listings`; `opt = { market, now, from, to, sources }`.
```
{ item, metric, basis, unit = "copper" | "items" | "listings", market, label,
  points = { { kind = "obs" | "day" | "week" | "fortnight" | "legacy-day" | "legacy-bucket",
               at | from, to,          -- obs: real time (seconds); others: UTC day range
               v,                      -- obs/day: the observed (closing) value; buckets: the mean
               lo, hi,                 -- day: the day's extremes (when n > 1); buckets: lowest/highest
               n,                      -- obs: 1 or "seen again until" (until = at + dm*60); day: scans; buckets: observed days
               exact = true | false, partial, complete, provenance = "local" | "legacy" | "import:<id>" } ... },
  gaps  = { { from, to, reason = "noscan" | "unlisted" | "incomplete" | "notretained" | "beforev2" } ... },
  resolution = { { from, to, kind } ... },   -- where the chart switches between obs, day, week, fortnight, legacy
  today, v2from }
```
- Nothing is interpolated; a point exists only where something was observed. `exact = false` for every bucket, so a chart cannot draw a bucket as a day.
- Metric identity is strict: `recent` never contains legacy points; `min` joins legacy days before `v2from` with v2 days, each labelled.
- The UI never decodes saved strings. One chart engine (later, C1) serves Opportunities, Market Intelligence, the Item Advisor and the Ledger from this shape.

### 6.3 Storage by age, recommended layout [measured, 1,000-item sample scaled; mixed listing frequency: 30% of items on 90% of days, 40% on 35%, 30% on 6%]
Three scans a day (4 h apart), 30-day daily + 8-point ring + weekly to 60 + two-week to 120:

| After | Average per item | Worst item | 10k items | 20k | 40k |
|---|---|---|---|---|---|
| 1 day | 47 B | 162 B | 0.4 MB | 0.9 MB | 1.8 MB |
| 2 days | 91 B | 289 B | 0.9 MB | 1.7 MB | 3.5 MB |
| 7 days | 167 B | 509 B | 1.6 MB | 3.2 MB | 6.4 MB |
| 14 days | 277 B | 819 B | 2.6 MB | 5.3 MB | 10.6 MB |
| 30 days | 523 B | 1,540 B | 5.0 MB | 10.0 MB | 20.0 MB |
| 60 days | 726 B | 1,927 B | 6.9 MB | 13.8 MB | 27.7 MB |
| 120 days | 1,009 B | 2,543 B | 9.6 MB | 19.2 MB | 38.5 MB |

---

## 7. Storage strategies and performance [measured unless marked]

### 7.1 Daily retention options (D2), three scans a day, at 120 days, 40,000 items
| Option | Average / worst per item | 40k text | Saved file | Resident after load | Update per item, append path | Complexity |
|---|---|---|---|---|---|---|
| 14-day daily, no ring | 764 / 1,644 B | 29.1 MB | 30.7 MB | 37.4 MB | 6.2 µs | low |
| **A: uniform 30-day daily, no ring** | 954 / 2,362 B | 36.4 MB | 38.0 MB | 44.7 MB | 7.2 µs | low |
| B: adaptive (30 days for 10% tracked items) | 776 / 2,170 B | 29.6 MB | 31.2 MB | 37.9 MB | 6.3 µs | **per-item policy**: who is tracked, what happens when tracking stops, charts that differ by item |
| C: 30 days, day ranges only on the newest 14 | 801 / 1,893 B | 30.6 MB | 32.1 MB | 38.8 MB | **no append path**: a middle segment is rewritten daily, 123 µs | medium |
| 14-day + 4-point ring | 811 / 1,768 B | 30.9 MB | 32.5 MB | 39.2 MB | 11.1 µs | low |
| 30-day + 4-point ring | 1,001 / 2,484 B | 38.2 MB | 39.8 MB | 46.5 MB | 12.1 µs | low |
| **30-day + 8-point ring (recommended)** | 1,009 / 2,543 B | 38.5 MB | 40.0 MB | 46.7 MB | 13.0 µs | low |

Other schedules for the recommended layout: **one scan on 80% of days**: 30-day + ring about 586 B per item, 22.3 MB at 40,000 items (measured with the 4-point ring; with one scan a day the ring holds at most two points, so 8 points cost the same [estimate]); against 14-day + ring: 557 B (+5% for 30 days). **Eight scans a day** (90 min apart): 1,136 B, 43.3 MB text, 44.9 MB file, 51.6 MB resident (4-point ring: 1,092 B, so 8 points cost +4% there and +1% at three scans a day).

**Recommendation: Option A (uniform 30-day daily) with the 8-point ring.** It costs 24% more than 14 days at three scans a day and 5% more at one a day, keeps the real shape of every 30-day chart, and has the simplest code. Adaptive saves about 19% but makes history depend on a per-item tracking state that changes over time (a chart's resolution would depend on when an item was tracked), and its saving disappears if many items are tracked. Option C saves 16% but loses the append-only update (the main runtime win, below). The 8-point ring costs 1 to 4% more than 4 points and covers twice as many changes (with hourly automatic scans, 4 points span about 4 hours of changes; 8 span a working day).

### 7.2 Runtime [measured offline]
| Work | Figure |
|---|---|
| History update, decode + re-encode per item | 89 to 183 µs (11 to 22 ms per 120 items): too slow for a frame |
| **History update, append-only** (cut the ring, read the `newest day` header, replace or append the last daily segment) | **6 to 18 µs per item (0.8 to 2.2 ms per 120 items)**; output identical to the full encoder in **all 134,458 to 375,357 comparisons** |
| Fold (bucket rewrite) | 3 to 10% of updates (about weekly per item); uses the full path |
| Chart query, largest item (decode + build points) | 144 to 178 µs |
| Saved file 40k items, `dofile` | 0.15 to 0.22 s for 23 to 45 MB files |
| Snapshot finalize | 0.15 / 0.29 / 0.45 / 0.62 s at 10k / 20k / 30k / 40k items |
| Transient tier map during a scan (packed `items * 65536 + listings`) | 14.5 MB at 250,000 records / 30k items, 22.9 MB at 400,000 / 40k; about 4.6 / 9.3 MB at 80,000 / 160,000 records [estimate by records]; unpacked form 37.8 MB (rejected) |

Client figures are [unknown]: the client's saved-variables loader is a different implementation, and writing the file at logout or `/reload` costs time too. The figures say the format is not pathological; they are not a load-time claim.

### 7.3 Totals per market and the three-market worst case
| Market | History text | + snapshot (`items` + `dist`) | Saved file | Resident |
|---|---|---|---|---|
| 10k items, 3 scans/day, 120 d | 9.6 MB | +1.1 MB [measured] | about 11.5 MB [estimate] | about 14 MB [estimate] |
| 20k items, 3 scans/day | 19.2 MB | +2.2 MB [measured] | about 23 MB [estimate] | about 28 MB [estimate] |
| 40k items, 1 scan/day | 22.3 MB | +4.8 MB | about 29 MB [estimate] | about 35 MB [estimate] |
| 40k items, 3 scans/day | 38.5 MB | +4.8 MB | about 46 MB [estimate] | about 57 MB [estimate: 46.7 measured history + 10.7 measured snapshot] |
| 40k items, 8 scans/day | 43.3 MB | +4.8 MB | about 51 MB [estimate] | about 62 MB [estimate] |
| **three markets at the cap, 3 scans/day each** | | | **about 140 MB** [estimate] | **about 170 MB** [estimate] |

The three-market worst case needs a player scanning three 40,000-item houses three times a day for four months; the real size of a Forever house is [unknown] (the 40,000 cap is a design bound, not an observation). Peak memory during a commit adds the transient tier map, the batch (about 11 MB at 30k items [measured, M7]) and the replaced strings awaiting collection.

### 7.4 Large markets: the budget guard (D4) [proposed]
Three markets keep their own identities and histories [approved]. To bound the unusual case **without silently discarding the most valuable evidence**, each commit adds up the bytes of the market's strings (it already touches them) and applies an **ordered compaction ladder** to the market being committed when its history text exceeds the **per-market budget (proposed 48 MB)** or all markets together exceed **the account budget (proposed 96 MB)**, starting with the market scanned longest ago:
1. Drop the day-range extensions of daily points older than 14 days (closing values stay; measured −16%).
2. Fold days 15 to 30 into weekly buckets early **only for items observed on fewer than 4 of the last 30 days** (they have no daily shape to lose).
3. Drop supply fewest/most from buckets older than 60 days.

Never compacted: the ring, the last 14 daily points, closing minimum/Recent/supply, bucket means and ranges of prices, legacy history, the snapshot. Each step is recorded in `market.compact` and shown in `Market.Info` and the footer tooltip ("Older detail was condensed for 3,200 rarely listed items to keep the saved file small"). A market not scanned for 120 days is removed (its history has expired). Budgets are constants in one place, adjustable after real `workshop.load` figures.

### 7.5 Strategies considered
| | **Summary + rich history (recommended)** | Raw recent snapshots (R) |
|---|---|---|
| Keeps | 6 exact tiers, quartiles, band mean per scan; ring, 30 daily, buckets | every listing of the last 3 scans, plus the same history |
| Extra size | — | about 11 MB per 40k-item market [estimate] |
| Benefit | everything the product questions need | re-running a new algorithm on 3 scans |
| Verdict | chosen | rejected: three scans are not a history, and the quartiles and exact low tiers already allow approximate re-derivation of lower-band estimators |

---

## 8. Automatic scanning [D5 approved; A6]

**Trigger:** the core sees `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with `Auctioneer` (or `AUCTION_HOUSE_SHOW`); if the setting is on and the player is not in combat it loads the Workshop (`WorkshopLauncher.Load`, which refuses in combat) and starts `Session.StartScan({ auto = true })` once `AuctionHouseFrame` is shown (checked for at most 5 s, then gives up silently).

**Gates:** no scan running and the posting search not busy; the market's newest accepted scan older than **60 minutes**; no automatic attempt for this market refused (`dropped`, `throttled`, `noResponse`, `api`) in the last **15 minutes** (session memory only); not held; **once per visit**.

**Behaviour:** the same state machine, completeness rules, atomic commit and `kept` rule; `snap.auto` and the scan log mark it automatic; quiet progress text ("Updating prices... 40%"); a **Stop** control on the bar (also for manual scans) ends it `interrupted` with nothing written; if the player starts a search while the automatic scan still waits for the throttle, it gives up. Never buys, bids, posts or cancels.

**Client verification first (A6 step 1, Lab guided probe):** whether `ReplicateItems` is accepted from an event handler without a click; time to the first update; whether the player's own search right after is delayed; commodity versus whole-auction buying of stackables; whether `owner` is populated (count only). If the request needs a click, A6 falls back to a one-click "Update prices" prompt on the bar and the setting's text says so.

**Setting:** "Update prices automatically when I open the auction house", default on, note "Reads the auction house at most once an hour. Nothing is bought or posted." Stored through the core settings layer so the core can read it before the Workshop loads. Cost: each auction house visit loads the Workshop and its saved data (section 7.3).

---

## 9. External data [D10 deferred]

Workshop works fully without external data. The **transport is not chosen**: a generated load-on-demand data addon, a size-limited import string, or another method are all open; none is committed to (a generated Lua file is executed by the client as addon code, which needs its own decision against the project rule on executing data).

The **boundary** is fixed now so the schema does not need to change later:
- Record: `{ schema, source = { id, name, version }, generated, market = { realm, side }, kind = "daily" | "snapshot" | "sale", items = { [id] = "<h2/dist encodings>" } }`.
- Validation: known schema, bounded sizes, exact market match, timestamps not in the future and within 120 days, every value through `W.Int`; failures rejected per item.
- Storage: separate tables (never `h2`/`c2`); `opt.sources` defaults to `{ "local" }`; imported points carry `provenance = "import:<id>"`; same day in both: local wins for values, both visible on a chart; duplicates: newer `generated` wins; imported days never make the "Prices updated" chip fresh.

---

## 10. Public Market API [proposed]

`Market.API = 2`. Every existing function keeps its signature and meaning. New, all read-only, `(item, ..., opt)` with `opt = { market, now, variant, sources }`:

| Call | Role | Returns |
|---|---|---|
| `Value(item, kind, opt)` | valuation | `kind` = `min`, `recent`, `market`, `historical`: `{ role, kind, value, basis, at, age, freshness, window, n, aggregate, complete, quality, provenance, notes }` or `nil, reason` (`stale`, `insufficient`, ...) |
| `Range(item, days, opt)` | valuation | long-term low/high of Recent and minimum, observed days |
| `Distribution(item, opt)` | valuation | quartiles, `hi`, Recent, anchor, tiers, tail, spread class, flags, totals, `near` |
| `Supply(item, opt)` | valuation | items, listings, near, at minimum, 14-day median items, trend |
| `TrendOf(item, metric, days, opt)` | valuation | direction, change, percent, halves' sizes |
| `Posture(item, opt)` | valuation | `cheap/normal/expensive/unknown`, ratio, reference, quality |
| `Quality(item, opt)` | valuation | level, reasons, facts, `policy` version |
| `Competition(item, qty, opt)` | competition | section 4B |
| `Cost(item, qty, opt)` | (purchase) | section 4F |
| `History(item, metric, opt)` | valuation series | section 6.2 |
| `Sales(item, opt)` | reserved | `nil, "nosales"` until the Ledger |
| `W.Sell.Suggest`, `W.Sell.Proceeds` (A8) | suggestion, proceeds | sections 4C, 4D |
| `W.Advisor.Decide(item, ctx)` (A8) | advice | section 4E |

Cache: `Value(market)`, `Value(historical)`, `Quality` per `(market key, snap.seq, item)`, at most 2,000 entries, cleared on commit. Basis sentences always say "listing" or "listed".

---

## 11. Migration and compatibility [proposed]

**Read old data in place, write new data beside it, convert nothing, no load-time pass.**

| Case | Behaviour |
|---|---|
| `v = 1`, `f = 2` (1.3) | read as today; the first new commit writes `f = 3` with unchanged `items`, frozen `hist`, new tables, `v2from`, `db.v = 2`, all in `Apply` |
| legacy recipes-only (`TwichUIDB.workshop.prices`) | unchanged |
| `v = 2` under 1.3 | **held**: 1.3 reads `items` and `hist` (same encodings), refuses `BeginCommit`, `Apply` and `Scan.Start` with `held`; its only writers are behind that check [verified, 2.1] |
| `v > 2` | held |
| interrupted first commit | nothing written |
| repeated commits | nothing re-migrated; legacy `hist` only trimmed by expiry |
| malformed `dist`/`h2`/`c2`/log entry | treated as absent for that item or entry, never repaired; the next observation replaces it |
| clock moved back | an observation older than the newest kept one is ignored (ring, daily and buckets alike) |

**Meaning preserved:** a legacy point is "the cheapest buyout listing of that day's last whole-read scan"; a v2 daily closing `p` has the same meaning, so only the `min` series joins them. No v2 field is ever filled from v1 data; Recent Price history starts at `v2from`.

**How the old-client test proves protection, not just readability (A2):**
1. Build a v1 database with 1.3's own encoders (fixture copies of `Prices.lua`, `History.lua`, `Market.lua` from `git show v1.3.0:` in `tests/fixtures/workshop_v13/`), commit with the new code (now `v = 2`, `f = 3`, non-empty new tables in later milestones; A2 seeds them with synthetic strings for this test).
2. Load the **1.3** code against that database and call every write path it has: `PR.Commit`, `PR.BeginCommit` + `Step` + `Apply`, `Scan.Start` (with the fake house), and the 1.3 window's refresh path. Each must refuse (`held` or `unavailable`).
3. Deep-compare the whole database before and after (including `dist`, `h2`, `c2`, `scans`, `days`): identical.
4. Serialize it with the test round-trip writer (M9 or the minimal one A2 adds), reload, and repeat step 3: what a client would write back at logout is the same data.
5. Check 1.3's answers (`Price`, `Stats`, `Series`) on the legacy days are unchanged.

---

## 12. Test and performance requirements

### 12.1 Invariants (each with a test that fails on a plausible wrong answer)
| Area | Invariants |
|---|---|
| Tier map / dist | conservation (`sum tiers + tail = t`, listings likewise); tiers ascending; tier 1 = rounded `p`; records added twice double counts; shuffle-invariant; bid-only and invalid excluded and counted |
| Quantiles / Recent | equal to a brute force on expanded item lists; `p <= q25 <= q50 <= q75 <= hi`; `p <= r <= q50`; never removes more than 25% of supply; cases 1 to 22 exactly; scale invariance within rounding; a listing above the band never changes `r` |
| Ring | at most 8; 48 h bound against the newest whole-read scan; the unchanged rule merges only when p, r, t, l and the flag all match (mutants: compare `p` only; ignore the flag); `m + dm` never decreases; cut scans add nothing |
| Daily | one point per day; closing = last whole-read scan listing the item; lows/highs equal the extremes of that day's scans; extension present iff n ≥ 2 and a value moved; append path equals the full encoder; partial flag carried |
| Buckets | whole weeks only, only weeks entirely older than 30 days; daily guarantee of 30 observed days; weekly → two-week after 60; expiry at 120; `lo <= mean <= hi` per metric; `n` conserved by merges; merge rounding as specified; boundaries 29/30/31/36/37, 59/60/61, 119/120/121 |
| Logs | every accepted scan in the scan log; 48 h coverage with bounds 64/256; day log 120 days; gap reasons consistent with the logs |
| Values | weighted medians equal a brute force over the day list; missing days never count; `stale` exactly after 14 days; legacy never in Recent, Market, Historical |
| Services | no function of one role returns another; `Sell.Suggest` price never equals a valuation unless the competing price does (property over random fixtures); Advisor never says Auction for `mixedvariants`, `uncertain`, Disenchant data absent |
| History API | no point without an observation; buckets `exact = false`; metric identity; resolution list covers the range |
| Isolation, unknown vs zero, migration, cancellation | as section 11; no API returns 0 for missing data; Stop/close/failing step at every phase leave the database deep-equal |
| Budget guard | ladder order; never touches the protected data; recorded and reported |

### 12.2 Tools
- Reference models: a listing-level model (tiers, quantiles, band mean) and a scan-level history model (every whole-read scan kept in full, then the ring, days and buckets derived naively) in `test_workshop_market_reference.lua` and the Lab `Reference.lua`.
- Fixtures: `FX.Listings` (wide, narrow, walls, baits, thin, clusters) and scan calendars with several scans a day, partial and cut scans, and every retention boundary.
- Mutation catalog (`--group market`): anchor `>=`; gap filter off; 30% → 25%; unchanged rule on `p` only; ring bound by wall clock; daily close = first scan; day low not updated; fold of a partial week; two-week merge losing `n`; weights swapped; legacy in Recent; `v` not bumped; ladder touching the last 14 days; Suggest priced from Market Value.
- Simulator (`workshop.sh`): distributions in the fake house; several scans a session; auto start on open, Stop, close mid-read (A6).
- Test Lab: `market.aggregate.*` v3, `history.update.append`, `history.fold`, `market.history.query`, `market.value.6k`; probes for A6 and A10; **a saved-data load case** (A4 gate, below).

### 12.3 Performance acceptance (relative; no absolute targets until client figures exist)
- The scan's longest step is not longer than today's on the same fixture (M7.1 v2 baseline), using tier-budgeted finalize steps.
- History updates use the append path; the commit is time-budgeted (about 4 ms of work per tick, the Lab `Pace` pattern) because folds still use the full path.
- Retained memory after a scan returns to the pre-scan level plus the new data.
- **A4 gate:** in the client, the load time of a synthetic 40,000-item, 120-day database (about 46 MB) is recorded before history writes ship. Proposed method: a development-only Lab companion addon whose only content is a saved variable the Lab fills with synthetic data; after `/reload`, the Lab times `LoadAddOn` of it with `debugprofilestop` and the player times the `/reload` itself. Real saved data is never touched. If the load is unacceptable, the budgets in 7.4 are lowered before release.

---

## 13. Implementation milestones

Each is one request, follows roadmap section F, and ends with `./tests/run.sh`. Model guidance: **Opus/High** helps A3 (tier-budgeted finalize, exact arithmetic), A4 (ring/daily/bucket boundaries, append path, legacy join, budget guard) and A5 (statistics and their reference models); **Sonnet/Medium** suits A2, A6 (care with events), A7, A8 (rules are tabled here), C1.

| | Objective | Main files | Acceptance highlights | Out of scope |
|---|---|---|---|---|
| **A2** schema v2 and compatibility | the final schema of section 3 defined, validated and written (new tables empty except `snap`, `scans`, `days`, `v2from`); readers for `f = 2` and `f = 3` | `Prices.lua`, `Market.lua` (`Info`), new `test_workshop_schema.lua`, fixture `tests/fixtures/workshop_v13/` | every row of section 11; the five-step old-client protection test; dropped job writes nothing | dist, history, API, UI, auto-scan |
| **A3** observation collection | packed tier map; `dist` with Recent Price; the per-item observation each scan hands to history (`p, r, t, l`, partial) and the scan/day log entries for every scan kind | `Prices.lua` (Batch, ItemsJob), `Scan.lua`, new pure `Dist.lua` (+ `.toc` after `History.lua`) | 12.1 tier/quantile/Recent invariants; cases 1 to 22; longest step not above v2 | history tiers, API |
| **A4** history and chart API | ring, 30-day daily with ranges, buckets, append path, logs, `Market.History`, legacy join, budget guard, the load gate | new pure `History2.lua`, `Prices.lua` (Job phases, time budget), `Market.lua` | 12.1 ring/daily/bucket/log invariants; append equals full encode; load gate recorded | valuations, charts UI |
| **A5** valuation | `Value`, `Range`, `Distribution`, `Supply`, `TrendOf`, `Posture`, `Quality`, `Competition`, `Cost`, cache | `Market.lua` or new pure `Valuation.lua` | every row of 4A/4B/4F tested incl. "never claims"; quality policy versioned; thin items `limited`, not `none` | consumers, selling |
| **A6** automatic scanning | the Lab probe, then section 8 | core launcher hook (+ `.toc`), `Scan.lua` (`auto`, Stop), `AuctionButton.lua`, `Session.lua`, settings page, simulator | every gate tested; nothing in combat; Stop writes nothing; one request per visit | — |
| **A7** consumer integration (no selling advice) | Shopping and Opportunities materials use `Cost`; Opportunities keeps its labelled minimum-based profit and **adds** the output's Market Value and Competition columns; tooltip shows valuation lines with Quality | `Session.lua`, `Opportunities.lua`, `Shopping.lua`, `WorthTip.lua`, `WorthLayout.lua`, views | no consumer decodes saved strings; every figure names its role and source; unchanged results with v1-only data | suggestions, Advisor |
| **A8** selling services and Item Advisor v1 | `Sell.Suggest`, `Sell.Proceeds`, `Advisor.Decide` with policy version 1; Opportunities profit moves to the suggestion's proceeds; `Worth.Recommend` uses the Advisor | new pure `Sell.lua`, `Advisor.lua`, `Worth.lua`, `Opportunities.lua` | every rule of 4C to 4E tested; the role property tests; crafting reference model updated; `--group crafting` | sell-through, undercut strategies |
| **C1** chart engine | one renderer over `Market.History` | UI files | screenshots reviewed; no interpolation; bands for buckets | — |
| **A10** variants | probe, then suffix keys | | | |
| **A11** Ledger and sale sources | invoices, sell-through, fees | | | |
| **A12** import boundary | section 9 once the transport is chosen | | | |

Order: A2 → A3 → A4 → A5 → (A6 can start after A3) → A7 → A8 → C1. A3 must ship before A6 if automatic scans should already feed the ring and daily ranges.

---

## 14. Owner decisions

| # | Decision | Status | Final direction |
|---|---|---|---|
| D1 | Recent Price | **approved provisionally** | Band mean: anchor at more than 25% of supply, ignore below half the anchor, mean of the cheapest 30%. Adversarial cases 13 to 22 added; manipulation bound 0.58x with under 25% of supply; thin-market reason `farbelow`. Labelled a representative listing price. Revisit after real distributions are seen (A3 Lab report of tier counts). |
| D2 | Historical resolution | **revised and recommended** | Uniform 30-day daily for every item, weekly to 60, two-week to 120 (section 7.1). Adaptive and the 14-day hybrid rejected on complexity and the loss of the append path. |
| D3 | Intraday | **revised and recommended** | 8-point ring, 48 h, real timestamps, exact unchanged rule; daily points keep the day's lows and highs and scan count. |
| D4 | Market count | **approved** | Three markets with separate histories; budget guard 48 MB per market / 96 MB in all with the ladder of 7.4; A4 load gate before release. |
| D5 | Automatic scanning | **approved** | On by default, 60 min per market, 15 min back-off, once per visit, Stop, after the client probe. |
| D6 | Variants | **approved** | Item-id aggregate; `mixedvariants`; no confident equipment valuation or Auction advice from mixed data; variant keys after a probe (A10). |
| D7 | Data Quality | **approved** | Table in 4A as policy version 1; thin markets `limited` with reasons, never `none` while a price exists. |
| D8 | Posture | **approved** | ±15% against Historical Value; needs 5+ observed days, Quality fair, 3+ listings; never on the minimum. |
| D9 | Price-source priority | **revised** | No valuation is a sell price. Separate valuation, competition, suggestion, proceeds and advice services (section 4); conservative Advisor policy v1 with a 1.5x vendor margin. |
| D10 | External data | **deferred** | Versioned import boundary and provenance kept (section 9); transport undecided. |

**Remaining genuine choices (with recommendations):**
1. **Budget numbers** (7.4): 48 MB per market / 96 MB in all. Recommendation: keep them provisional until the A4 load gate; lower them if a 46 MB load is noticeable.
2. **Advisor minimum gain** (4E): Auction only if it beats vendor by 1.5x **and** at least 1 gold. Recommendation: 1 gold; it keeps trivial items on Vendor.
3. **The Lab load-test companion addon** (12.3): a development-only addon with one saved variable, never packaged. Recommendation: approve, it is the only way to measure load time without touching real saved data.

---

## 15. Known limitations, assumptions and deferred capabilities

**Requires real-client verification:**
- `ReplicateItems` without a click; the full-scan throttle; the player's search during an automatic scan.
- Commodity versus whole-auction buying of stackables (affects `Cost` ranges).
- How often records arrive with `hasAllInfo == false` (affects the partial flags and completeness).
- `GetReplicateItemLink` cost and suffix frequency (variants).
- `owner` population (seller counts, deferred).
- Saved-variables **load and write time** at 20 to 50 MB per market.
- Real Forever house size, tiers per item and listing frequency (every size figure here is synthetic and probably pessimistic in tiers per item).
- The auction house cut and deposit (proceeds).

**Inherent limits:** listing data only (no sales, demand or sell-through; disappearing listings are not sales); a snapshot sees nothing between scans; scan time is not sale time; buckets keep extremes and means, not the days; the ring keeps 8 changes, not every scan.

**Deferred:** charts UI (C1), variants (A10), Ledger and sale sources (A11), imports and the companion (A12), undercut and patient selling strategies, seller counts, time-left evidence.

---

## A2 as built (schema v2 and compatibility, 2026-11-12)

**Implemented** (`Prices.lua`, `Scan.lua`, `Market.lua`; unit-tested in `tests/test_workshop_schema.lua`, not real-client-tested):

| Area | What A2 does |
|---|---|
| Database | `TwichUIWorkshopDB.v = 2` (`PR.SAVED_VERSION`). Written only inside `Job:Apply` of an accepted commit, after everything fallible was built on copies; loading and reading never write. `v` above 2 is held (reads, refuses `BeginCommit`, `Apply`, `Scan.Start`). No startup migration, no eager rewrite of other markets. |
| Market | `f = 3` (`PR.MARKET_FORMAT`). Unchanged fields: `scope, realm, side, at, complete, cut, read, used, partial, n, hn, sd, items, hist`. New: `snap`, `scans`, `days`, `v2from`. A mixed database of `f = 2` and `f = 3` markets is normal; a market becomes `f = 3` when it is next committed. |
| `snap` | `seq` (+1 per accepted scan, after the highest valid logged number), `kind = "full"`, `at`, `records`, `used`, `invalid`, `noBuyout`, `partial`, `items`, `auto = false` (scans are manual), `client` (`GetBuildInfo` version.build, when readable). **`alg` is absent**: it names the distribution algorithm and there is no distribution until A3. `Scan.lua` now also hands over `invalid` and `noBuyout` (the batch already counted them). |
| `scans` | `"seq,at,flags,items,records"`, oldest first, every accepted scan: all of the last 48 h, never fewer than the newest 64, never more than 256. Flags (decimal bit set): 1 whole read, 2 complete, 4 cut, 8 count changed, 16 partial information, 32 automatic; 64 (fed history) and 128 (imported) are reserved and not written. A refused or interrupted scan is not logged. |
| `days` | `"day,scans,flags"`, oldest first, one entry per scan day of the last 120 days; flags 1 any whole read, 2 any cut/changed scan, 4 any scan with records lacking their information. A scan dated before the newest logged day adds no earlier entry. |
| `v2from` | The day of the first accepted format 3 scan of the market; never moved afterwards. |
| Later containers | `dist`, `h2`, `c2`, `compact` are **not created** (omitted, not empty). If a market already holds them as tables (a later build wrote them into the same database version, which will not bump `v` again), a commit carries them forward untouched; a value that is not a table is dropped. **There is no separate `ring` container**: the ring is part of each `h2` entry (section 3.3); the A2 brief's separate `ring` was not adopted. |
| Legacy history | `hist` and `sd` are **frozen**: an accepted scan only expires what `History.Trim` says is too old (and drops an item with nothing left; `hn` follows). Nothing is converted into price metrics. Consequence until A4: `Market.Stats/Series/Trend/Compare/Observed`, the chart and anything built on the history stop growing; they keep answering from the days already saved, and they age out after 120 days. The old feeding code stays behind `PR.FEED_LEGACY_HISTORY = false` so `History.lua`, the readers and the reference model are still exercised end to end (the tests turn it on; production never does). |
| Readers | `PR.Market` accepts `f = 2` and `f = 3`. `snap`, `v2from`, `compact` are validated on read; the logs are validated entry by entry on demand (`PR.ScanLog`, `PR.DayLog`). A malformed field is absent, never repaired, and never makes the price entries unreadable; the next commit writes only valid entries. |
| `Market.Info` | Adds `format` (2 or 3), `dbVersion`, `v2from`, `scanLog` and `dayLog` (counts of valid entries) and `compact`. The existing `scans` keeps its meaning (the legacy history's scan days). No other function was added to `W.Market` (tested). |

**Compatibility evidence** [unit-tested]: `tests/fixtures/workshop_v13/` holds byte-for-byte copies of `Data, Materials, Queue, History, Prices, Scan, Market` from the `v1.3.0` tag (`README.md` there gives the commands that prove it). The test builds the version-1 database with that released code, upgrades it with the new code, seeds the full shape (`dist`, `h2`, `c2`, `compact`, logs) and loads the released code against it: `Commit`, `BeginCommit`, `Scan.Start` and an `Apply` of a job begun before the upgrade are each refused with `held`; the whole database is deep-equal before and after, and after a serialize-and-reload round trip; 1.3's `Stats` and `Series` on the legacy days equal what it answered before the upgrade. 1.3's only writer of the database is in `Prices.lua` (`git grep TwichUIWorkshopDB v1.3.0`; the Workshop window only reads); a test also asserts that only `Prices.lua` names the database in the current Workshop.

**Persistence** [unit-tested]: a rejected (`kept`, `bad`), dropped, ready-but-never-applied, failing-step, failing-metadata and cancelled (auction house closed) commit leaves the database deep-equal, with no version bump and no orphaned field; a failing Apply on a version-2 database is the same. Repeated commits, eviction of the oldest market (unchanged rule) and market isolation are covered. Mutations `market.schema.*` (9) are killed by it.

**Performance** [measured, offline, synthetic 40,000-item market, six commits]: with the history frozen a commit has no per-item work (0.00 ms worst step; Apply about 0.1 ms, which includes building the metadata and the 256-entry log parse); the old feeding path on the same data is 6.8 ms worst step, 12 ms Apply, 0.56 s whole commit. A2 adds no allocation proportional to the number of items; the saved schema overhead is a few hundred bytes plus about 20 bytes per logged scan. Real-client load time is not claimed (A4 gate).

**Not built** (A3 and later): distributions, Recent Price, ring/daily/bucket history, valuations, new API, UI changes, automatic scanning, the compaction ladder and budget guard.

**Real-client acceptance (none done; all non-destructive):**
1. Back up nothing and corrupt nothing. Open the Workshop with your existing saved prices: the Overview shows prices and the history chart as before.
2. Run a normal price scan and let it finish. In `WTF/.../SavedVariables/TwichUIWorkshopDB.lua` the first lines read `["v"] = 2` and the market has `["f"] = 3` with `snap`, `scans`, `days`, `v2from` (after `/reload` or logout; the file is written then).
3. Opportunities and Shopping still show prices; the history chart still shows the days it had (it does not grow, by design).
4. `/reload`, open the Workshop again, check the file's modification time does not change by merely opening it.
5. Start a scan and close the auction house before it finishes, or let a scan be refused (open the Workshop away from an auction house and click Scan): the file keeps its previous version (still `v = 1` if no scan ever completed).

**A3 handoff:** write `dist` (tiers, quartiles, Recent Price) from a packed tier map in `ItemsJob`'s stepped finalize, set `snap.alg = 1`, add the per-item observation for A4 (`p, r, t, l`, partial) to the scan result, and keep committing through the same `Apply` (build first, assign last). `dist` is a per-scan snapshot: replace it wholesale each accepted scan and do not rely on A2's carry-forward, which only protects data from a downgrade. `BuildMarket` in `Prices.lua` is where new containers join. Do not bump `db.v` again for additive containers. Open decision for the owner: the legacy history is frozen from now on, so the existing trend/chart features go stale until A4; if that is unacceptable in the interim, `PR.FEED_LEGACY_HISTORY` is the single switch (it feeds the old history again; it is separate from version-2 history).

---

## A3 as built (price distribution collection, 2026-11-12)

**Implemented** (`Dist.lua` new and pure; `Prices.lua`, `Scan.lua`; unit-tested in `tests/test_workshop_dist.lua`, simulator-tested over a fake auction house, not real-client-tested). A full scan now keeps, beside the unchanged minimum entries, a **distribution entry for every item that has two or more whole-copper unit prices**, and says so in the snapshot (`snap.alg = 1`).

| Area | What A3 does |
|---|---|
| Tier accumulation | `Batch:Add` rounds each valid listing's unit price up to whole copper (the price a buyer sees) and adds it to the item's tiers. An item whose listings all share one price allocates nothing beyond its minimum record; the first listing at another price moves the item into **one table of packed numbers**: `m[unit] = items * 2^18 + listings`, and `m[-unit]` = the largest single listing of a tier (only for tiers with two or more listings; a negative key cannot meet a price). The pack is exact in a double up to 262,143 priced records (`Dist.MAX_RECORDS`; 2^18 is more than `Scan.MAX_RECORDS` = 250,000) and 2.6e9 items in a tier; beyond the record limit the batch sets `distBad = "records"` and **no** distribution is built (never a corrupted one). Accumulation is commutative: any order of the same records gives the same tiers. The legacy minimum (exact fraction comparison, `items[id]`) is untouched; only a `RoundUp` helper is shared with `PR.Unit` (same arithmetic, tested against it). |
| Finalization | `ItemsJob` builds the minimum entry and the distribution **of the same item in the same step**. A step stops after `ITEMS_STEP` (400) items or `TIERS_STEP` (600) **work units**, where a multi-tier item costs its tiers plus `TIER_ITEM_COST` (8; measured: the string of about 30 numbers costs more than the sort). The per-item work is: gather the prices from the item's table, one `table.sort` of the distinct prices, one pass for the quartiles and the anchor, one for the band, one for the near supply, one string. Scratch lists are reused from item to item and released at the end. `Scan.lua` runs steps for at most `BUILD_MS` (3 ms of `debugprofilestop`) per timer tick, then yields the frame; the token, generation and "auction house still open" guards are unchanged and are checked before every tick. **The one thing that cannot be split is one item's sort and summary**: about 0.5 ms per 1,000 distinct prices offline (7 ms for the widest item of the 250,000-record "deep" benchmark, 15,633 prices), so a step's length is bounded by the budget plus the widest item. |
| Failure | `pcall` guards the per-item build: one failure gives up the **whole** distribution (`distWhy = "failed"`), the minimum entries are complete, and the scan is saved without `dist` and without `snap.alg`. |
| Commit | `BeginCommit` accepts `scan.dist` only with `scan.alg == 1`, and a new first commit phase **checks every entry** (`Dist.Decode`, then agreement with the item's minimum entry: same minimum, same items, same listings, the minimum entry's quantity fits the first tier). One entry that does not agree rejects the **whole** distribution (the prices are still saved). `BuildMarket` writes `dist` and `snap.alg` only for a checked distribution and **never carries an old `dist` forward** (the A2 carry-forward of `dist` is removed; `h2`, `c2` and `compact` are still carried). A scan that is not accepted (`kept`, held, interrupted, failed) changes nothing. |
| `Dist.lua` | `Stats` (the numbers), `Encode` (the saved text), `Decode` (a strict reader that refuses anything the writer never makes: canonical numbers, ordering, conservation, `m` only where `l > 1`, the tail only after six tiers; with no tail every statistic is recomputed from the tiers and must match, with a tail the statistics the six tiers decide are checked and the rest bounded). |
| Readers | `Prices.Distribution(info, item)` returns the decoded entry, or `nil` and one of `unlisted`, `noevidence` (the scan carries no algorithm-1 distribution), `missing` (the minimum entry says the item has a second price but no entry exists), `malformed`. An item with one price has no entry by design and is answered as a one-tier distribution (`single = true`, Recent Price = minimum). `Prices.Observation(info, item)` is the A4 contract (below). Neither is exposed through `W.Market`: its set of functions is unchanged. |

**Saved text** (exactly as written; the tail is omitted when empty, as in the A1 prototype, and the reader refuses `|0:0`):
```
1,r,a,q25,q50,q75,hi,near|p1:q1:l1;p2:q2:l2:m2;...;p6:q6:l6:m6|tq:tl
```
`m` is written only where `l > 1`; tiers are the cheapest six distinct prices, ascending; `tq:tl` are the items and listings beyond the sixth. Example, case 1 of section 5.2: `1,9741,10000,10000,10200,10500,11000,40|9500:5:1;9800:5:1;10000:10:1;10200:10:1;10500:10:1;11000:5:1`.

**Definitions as implemented** (section 5, with the choices the document left open):
- **Anchor `a`**: the price of the first tier whose running total of items is **strictly more** than a quarter of all items (`4 x running > total`). Case 3 (`1000x1, 5000x3`) is the boundary: the running total after the cheap unit is exactly a quarter, so the anchor is 5000 and Recent Price 5000. A `>=` here gives 1667 (a mutant; killed).
- **Recent Price `r`**: ignore tiers priced below half the anchor (`2 x price < a`); of the items that remain take the cheapest 30% (`3 x eligible` in tenths of an item, a fraction of a listing counts at the edge) and average their prices, **rounded half up**. Computed in whole numbers: with `s` the sum of `tenths x (price - cheapest eligible price)` and `w` the tenths in the band, `r = cheapest + floor((2s + w) / 2w)`. Exact while `2s + w < 2^53` (offset from the cheapest eligible price, so even 1.9e9 items at 99,999,999,999 copper are exact when the prices are close); otherwise the same formula in doubles, within one copper, and `Dist.Stats` says `exact = false`. `min <= r <= q50` always (the band ends at rank 0.475 of the items or earlier).
- **Quartiles `q25 q50 q75`**: nearest rank: the price of the item at rank `ceil(p x total)` when every item is lined up by price (the first tier whose running total is at least `p x total`). The document gave no formula for the quartiles; the A1 prototype used exactly this (`cum >= need`). So `q25 <= a <= q50`, and `a = q25` except when a running total is exactly a quarter.
- **Near supply**: items at or below `1.10 x r`, compared as `price x 10 <= r x 11`. **`hi`**: the highest unit price. Totals, minimum and next price are derived on read.
- **Prototype discrepancy (documented, not silently changed):** `a1-prototypes/snapshot.lua` (size and timing prototype) anchored with `>=`; `algos.lua`, the document's section 5.1 and the worked examples use "strictly more". A3 follows section 5.1. All 22 cases of 5.2 reproduce (the document's `C` column), and were re-derived independently with exact fractions on expanded item lists (a throwaway Python script, same values).

**Snapshot fields now populated:** `snap.alg` (1, only for a distribution that passed the commit checks). `snap.partial` (records lacking information), `market.cut`, `market.complete` keep their A2 meaning and are how **incomplete evidence is told apart**: `alg = 1` means the distribution agrees with the `items` of the same scan under algorithm 1, not that the read was complete. **Still reserved / not written:** `h2`, `c2`, `compact`, scan flag 64 (fed history) and 128 (imported). `FEED_LEGACY_HISTORY` is still `false`.

**The A4 handoff: the observation contract.** `Prices.Observation(info, item)` (info = `PR.Market(key)`) returns, from one accepted scan, `{ item, market, seq, at, p (minimum), r (Recent Price), t (items), l (listings), partial, complete, cut, whole, auto, alg }` or `nil` and `noformat` / `nosnapshot` / `inconsistent` (the snapshot is not the market's newest scan) / `unlisted`; with no usable distribution `r` is nil and `noRecent` says why. It is a pure read of what `Apply` saved; **nothing is stored a second time and no daily value is calculated**. A4 should call it (or build the same table from the committing job's own `items` and `dist` once `seq` is known) and must not invent a second observation shape. Missing is never zero: an item absent from the scan has no observation.

**Compatibility** [unit-tested]: `db.v = 2`, `f = 3` unchanged; the minimum entries are **byte for byte** what the released 1.3 code writes for the same records (random houses, a 1.3 fixture batch beside the current one); the 1.3 write paths (`Commit`, `BeginCommit`, `Scan.Start`) still refuse a database holding a distribution, deep-equal before and after; 1.3 reads the same minimum prices. Single-price items have no entry, and an item that should have one but does not is `missing`, distinct from `noevidence` and `malformed`. A known blind spot: an item whose second price rounds to the same copper as its first can say `x = 0` without being single-priced; the scan writes an entry for any item with two whole-copper prices, so such an item lacks one only through damage, which no reader can see.

**Correctness evidence** [unit-tested; `tests/test_workshop_dist.lua`, about 12 s]: the 22 cases of 5.2 (23 listing sets) against the document's Recent Prices and against `REF.ExpectDist` (`Reference.lua`: lines every item up and reads ranks; shares no code with `Dist.lua`); 150 seeded random houses (`FX.Listings`, with garbage records) and 225 seeded adversarial markets (cheap walls, expensive walls, thin markets, low bait, high outliers, ties, fractional unit prices from stack buyouts) comparing the **whole saved text** with the model, plus conservation (tiers + tail = items and listings), ordering, tier 1 = the 1.3 entry, shuffle invariance, doubling, scale invariance within rounding; malformed records (NaN, infinities, fractions, strings, limits) leave the entry unchanged; numeric limits with expected values from exact fractions in Python; 30 refused spellings of an entry; the packed-record limit (given up, not corrupted); stepped finalization at five step sizes (identical output, bounded work per step); a failing build; whole scans against a fake auction house (replacement of the previous distribution, items no longer listed gone, another market untouched, a failed distribution leaves none and no `alg`, closing the auction house during reading, building and saving, a new scan started while an old build is pending, a failing commit step, entries that decode but do not belong to their items, `kept`, 1.3 protection). Rerun a seed: `DIST_SEED=7700042`; more scenarios: `DIST_SCENARIOS=3000`.

**Simulator and Test Lab** [simulator-tested; unit-tested]: `bash tools/simlab/workshop.sh` over the fake auction house: PASS WITH KNOWN SIMULATOR LIMITATIONS (the same two classified simulator errors as before), 438 checks per launch, 5 of them new: after a scan the market holds `snap.alg = 1`, `dist` for exactly the three items with two prices (118, 2447, 2841) and the hand-worked text of each, and the scan result names the algorithm. Not persistence, not the real client. The four `market.dist.*` Lab cases run in `test_testlab.lua` through the real Runner with every other core case (saved roots untouched); their in-game result is pending.

**Mutation results** [`bash tools/mutate.sh --group market.dist`]: the whole `market` group, **93 mutations, 93 killed** (31 new `market.dist.*`: the 25% boundary `>=`, the 30% band size, the low-outlier filter off and at its boundary, tiers dearest-first, a lost tier quantity (three places), a wrong tail count, the largest listing smallest / forgotten / not carried, rounding down, the upper quartile at the wrong weight, the median at a strict rank, near supply excluding exactly 110%, the step budget ignored, the packed-record limit ignored, a stale distribution kept after a failed build or carried over from the previous scan, the snapshot algorithm missing / wrong / claimed without evidence, the commit check skipped or ignoring price or totals, finalization continuing after the scan ended, the observation mixing snapshots, a one-price item reported when an entry is missing). The first run left one survivor (`finalize-after-cancel`): the two scans in the interruption test read the same records, so a zombie finalization saving the old data was invisible; the test now gives the second scan a different house and asserts that no step runs after the event ended, and the mutant dies. Three A2-era mutations (`stepped-boundary-item-lost`, `stepped-ranking-shifted`, `future-containers-dropped`) had to be re-pointed at the changed lines, and still die.

**Performance** [measured, offline Lua 5.1, WSL; `tests/bench_workshop.lua --only market.aggregate --xl --reps 5`; `market.aggregate.*` is now **v3**, so v2 numbers are the minimum-only aggregation and are not comparable by the framework; the table below is a manual comparison on the same fixture and seed]:

Same fixture, seed, machine and conditions, A2 commit `9cfe37a9` (v2: minimum entries only) against A3 (v3: minimum entries plus distributions), median of 5 repetitions; "longest step" is the longest bounded unit of work (a 400-record read step or a build step); heap is the transient allocation during one run (the retained memory afterwards is +6 KB in both: nothing accumulates, growth over repetitions +1 KB):

| Records / items (spread) | v2 total | v3 total | v2 longest step | v3 longest step | v2 heap | v3 heap |
|---|---|---|---|---|---|---|
| 1,000 / 300 | 2.09 ms | 2.84 ms | 1.00 ms | 0.64 ms | 185 KB | 319 KB |
| 10,000 / 3,000 | 22.9 ms | 31.4 ms | 1.70 ms | 0.93 ms | 1.6 MB | 2.9 MB |
| 50,000 / 12,000 | 120.7 ms | 173.6 ms | 1.82 ms | 1.54 ms | 6.3 MB | 12.9 MB |
| 250,000 / 30,000 (offline) | 585.9 ms | 836.5 ms | 2.74 ms | 1.60 ms | 15.5 MB | 39.5 MB |

The new work costs about **1.4 times** the time and **1.7 to 2.6 times** the transient heap of the minimum-only aggregation; it is not the same cost and is not claimed to be. The longest step did not grow in these runs (a read step now adds a rounding and a table update per record; the build step is budgeted). Offline variants of v3 (no v2 equivalent): `wide.10k` (up to 4,001 prices per item) 18.3 ms, longest step 0.83 ms, heap 1.2 MB; `narrow.10k` (2 prices) 27.9 ms, 1.27 ms, 2.3 MB; `wide.50k` 101.8 ms, 1.12 ms, 5.3 MB; `wide.250k` 853 ms, 1.78 ms, 40.6 MB; `deep.250k` (60 items, the widest with 15,633 prices) 462 ms, **longest step 3.13 ms** (the widest item's sort and summary), heap 16.1 MB. Runs taken while the simulator was busy on the same machine gave up to 4.4 ms for the 250,000-record step: the worst step is dominated by garbage-collector pauses in a large heap, not by the step budget (the worst step stayed 3.2 to 4.0 ms whether `TIERS_STEP` was 300, 500 or 1000 in a profiling run). Candidates were rejected on measurement: an `mx` side table and a per-item `u`/`v` pair (50 MB heap at 250,000 records) gave way to the one-table design above (40 MB); a 1,000-unit step with tiers counted alone gave 4 to 5 ms steps because the per-item string cost was not counted. Client figures are not known: the M7.1 client ran offline code about 2.4 times slower, which makes a 1.6 ms step about 4 ms and the deep case about 7 ms; `TIERS_STEP` and `BUILD_MS` are the two numbers to lower if the in-game report shows a hitch. The scan's total time grows by about the same 1.4 times (the build is spread over frames by the 3 ms tick).

**Remaining Forever-specific unknowns:** the client's CPU for the new work (the M7.1 client ran offline code about 2.4 times slower), the real number of price tiers per item in a Forever house (every figure here is synthetic), whether the transient memory of the tier tables matters at the client's real record counts, the garbage-collector pauses during the build (the worst offline step is dominated by them, not by the step budget), `debugprofilestop` resolution, and that nothing changes in the saved-variables load time (the snapshot grows by about 100 bytes per multi-price item: about 83 bytes per item with two or more prices, 2.3 MB of text for a 29,800-item synthetic house, no entry for single-price items).

**Real-client acceptance (none done; all non-destructive).**
1. Open the Workshop with your existing prices: the Overview, Opportunities, Crafting Plan, Shopping and the item tooltip show what they showed before; the history chart shows the days it had and does not grow (by design until A4).
2. Run a normal price scan to the end. Note the total time and whether anything stutters while "Saving prices" and while the bar fills (Test Lab: tick Performance, `perf.market.aggregate.10k` and `perf.market.aggregate.wide.10k`; read the longest segment).
3. `/reload` (or log out) and open `WTF/.../SavedVariables/TwichUIWorkshopDB.lua`: the market has `["snap"]["alg"] = 1` and a `["dist"]` table whose entries look like `"1,5,5,5,5,7,7,20|5:20:1;7:10:1"`; an item that was listed at a single price has no entry.
4. Scan again (after a few minutes, or on another day): `snap.seq` increased by one, `dist` holds the new scan's entries only (an item no longer listed is gone from both `items` and `dist`).
5. The `items` entries of the same item are what the previous build wrote for the same listings (the minimum price shown in the Workshop is unchanged).
6. Open the Test Lab (`/tuilab`), tick **Core** and run: `market.dist.recent`, `.quartiles`, `.numbers`, `.finalize` pass in Forever (they use the client's own number printing and `string.format`).
7. Record: the scan's total time, the Lab's `longest segments` line, and the saved file's size (compare with the file before the scan).
8. Do not edit or damage the saved file to test errors; malformed data is covered offline.

**Next: A4** (history and the chart API): the eight-point intraday ring, the 30-day daily points with their lows and highs, weekly and two-week buckets, the logs, `Market.History`, the append-only update, the budget guard and the load-time gate (section 12.3), all fed from `Prices.Observation` and switched on by setting `h2`; `PR.FEED_LEGACY_HISTORY` stays `false`.

---

## Appendix A. Prototype commands (offline, throwaway; not part of the addon or the suite)
```
lua5.1 docs/workshop/a1-prototypes/algos.lua                          # section 5.2 (cases 1 to 22)
lua5.1 docs/workshop/a1-prototypes/snapshot.lua 40000 400000          # dist sizes, finalize time (also 10000 80000, 20000 160000)
lua5.1 docs/workshop/a1-prototypes/storage.lua acc 30000 250000       # packed tier map memory
lua5.1 docs/workshop/a1-prototypes/history.lua all active 1000        # section 7.1 (about 4 min); designs and schedules: see its header
lua5.1 docs/workshop/a1-prototypes/history.lua d30ring8 heavy 1000
```
`storage.lua hist` is the first A1 history estimate (superseded by `history.lua`). Run them with bash or pass arguments literally (zsh does not split a quoted variable).

## Appendix B. Copy-ready prompt for A2 (do not run until approved)

> **TwichUI Workshop — Market Data Foundation 2.0, milestone A2: schema v2 and compatibility.**
> Branch `feature/workshop`. Read `CLAUDE.md`, `docs/workshop/market-data-foundation-v2.md` (sections 2, 3, 11, 12, 13 A2) and `docs/workshop/testing-roadmap.md` section F before editing.
> Implement only A2. In `Prices.lua`: `TwichUIWorkshopDB.v = 2` and markets `f = 3` exactly as section 3.1 to 3.2, written in `Job:Apply` on the first commit; `items`, `sd` and `hn` unchanged; `hist` frozen (trimmed by expiry in the existing "old" phase, never extended); new tables `dist`, `h2`, `c2` created empty; `snap` (seq, kind, alg = 1, at, records, used, invalid, noBuyout, partial, items, auto = false, client when readable); `scans` (encoding and bounds of 3.2: every scan of the last 48 h, at least 64, at most 256, including cut and changed scans with their flags); `days` (120-day day log, 3.2); `v2from`. Add validated readers for every new field (a malformed entry is absent, never repaired) and accept `f = 2` and `f = 3`; `v > 2` is held. `Market.Info` reports `f`, `v2from`, `scans` count and `compact`. No distribution, no ring, no daily or bucket writing, no new Market functions, no UI, no automatic scanning.
> Tests: new `tests/test_workshop_schema.lua` covering every row of section 11 and the **five-step old-client protection test** (fixture copies of `Prices.lua`, `History.lua`, `Market.lua` from `git show v1.3.0:TwichUI_Workshop/...` in `tests/fixtures/workshop_v13/`; seed `dist`/`h2`/`c2` with synthetic strings; every 1.3 write path refuses; deep-compare before and after, and after a text round trip), plus deep-compare after a dropped job, Stop and a failing step. Update `test_workshop_prices.lua` only where the stored shape changed. Run `luac5.1 -p` on edited files, the focused tests, `test_workshop_market_reference.lua`, `bash tools/mutate.sh --group market` (add catalog entries: "v not bumped", "legacy hist extended by a new scan", "1.3 field dropped from f = 3", "scan log drops cut scans"), `bash tools/simlab/workshop.sh`, then `./tests/run.sh`. Report with evidence labels; list `/reload` after a scan as the real-client check. Do not commit unless asked.
