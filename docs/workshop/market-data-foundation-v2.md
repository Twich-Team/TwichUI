# Workshop Market Data Foundation 2.0 (A1: architecture and data contract)

Status: **planning only** (2026-11-12, branch `feature/workshop`, base commit `2fd4b775`, M7.1). Nothing here is built. This document is the source of truth for the A2 to A7 implementation campaign; `docs/workshop.md` still describes what exists.

Evidence labels used throughout:
- **[verified]**: read in this repository's code or in the Forever UI source (`../wow-ui-source`, branch `forever`).
- **[measured]**: a throwaway prototype run offline (Lua 5.1, WSL dev machine, synthetic data). The scripts are in [a1-prototypes/](a1-prototypes/). An offline figure never stands in for the client.
- **[real-client]**: observed in Forever 1.60.1 build 70888, as recorded in `docs/testlab.md` or the roadmap.
- **[proposed]**: a design choice in this document.
- **[unknown]**: needs a probe or an in-game check before anything relies on it.

---

## 1. Executive summary

**The model [proposed]:** keep today's compact, 1.3-readable current-price entry exactly as it is, and add three new things beside it:
1. a **distribution summary** of each item in the newest scan: the cheapest 6 price tiers (exact), a tail total, quantity-weighted quartiles and a robust **Recent Price**, all computed at scan time from the complete listing list;
2. a **two-tier listing history** per item: one point per observed day for 14 days (minimum, Recent Price, supply, listings), then weekly buckets to day 60 and two-week buckets to day 120 (low, mean and high of the Recent Price, low and mean of the minimum, mean supply);
3. a **market-level scan log** (the last 64 accepted scans with time and quality), which tells a chart "scanned, not listed" apart from "not scanned".

The existing minimum-only history is **frozen, not converted**: it keeps its exact meaning, is still read for the minimum series, and expires on its own schedule. The database version goes from 1 to 2 so that TwichUI 1.3 becomes read-only instead of overwriting the new fields (1.3 rebuilds the whole market table on every commit [verified]).

**Price sources [proposed]:** Minimum Buyout, Recent Price (band mean), Market Value (recency-weighted median of daily Recent Prices over 14 days), Historical Value (median over 60 days), Long-term range (120 days), Dispersion, Supply, Trend (same metric only), Posture (cheap/normal/expensive), Data Quality (a level plus reasons, not a number), and a **purchase cost that walks the stored price tiers** for the quantity actually needed. Every answer says what it is, how old it is, how many observations it rests on and why it might be missing.

**Why this one:** it is the smallest design that answers every product question in the brief from listing evidence alone, keeps the measured worst step bounded, needs **no startup migration** (old data is read in place), and keeps the raw evidence that matters (exact low tiers, quartiles, daily points) so later algorithms can be revised without throwing data away. Measured cost: about **20 MB of saved text for a full 40,000-item market after 120 days** of daily scanning (mixed listing frequency), about 14 MB for a sparser market, against about 8 MB worst for today's format. That is the main owner decision (section 14).

**Automatic scanning [proposed]:** on by default, started from the core when the auction house opens (it loads the Workshop if needed), at most once per market per 60 minutes, never in combat, never retried automatically after a refusal within 15 minutes, read-only, with a Stop control on the progress bar. Whether the client accepts `ReplicateItems` without a click is **unknown** and is the first check of A6.

---

## 2. Verified current implementation and API constraints

### 2.1 Repository state
- Branch `feature/workshop`, HEAD `2fd4b775` (M7.1), working tree clean at start [verified].
- Released baseline `v1.3.0` saves the same shape described here (`f = 2`, `v = 1`, 7 exact days + 3 x 28-day buckets, 120-day retention) [verified with `git show v1.3.0:...`].
- Focused tests on HEAD: `test_workshop_market.lua` PASSED, `test_workshop_market_reference.lua` PASSED (200 houses, 9,480 scans, 239,167 queries compared, 7.5 s), `test_workshop_prices.lua` PASSED [verified, run for A1].

### 2.2 Saved data today [verified, `Prices.lua`, `History.lua`]
```
TwichUIWorkshopDB = { v = 1, markets = { ["Realm|Side"] = market } }     -- Workshop's own LoD SavedVariables
market = { f = 2, scope = "full", realm, side, at, complete, cut, read, used, partial, n, hn,
           items = { [itemID] = "p,q,l,t,x" },
           hist  = { [itemID] = "d,p;d,p;...|b,lo,hi,sum,n;..." },
           sd    = { day, ... } }                                         -- at most 32 scan days
```
- `p` cheapest unit buyout (stack buyout / count, rounded **up**, at least 1 copper; the cheapest is chosen by exact fraction comparison); `q` items at exactly that fraction; `l` buyout listings; `t` items in them; `x` next higher whole-copper unit price, 0 when none or when it rounds to `p` (M2 finding 1: 261 such items in the reference run).
- History: one value per UTC day (the day's last whole-read scan), 7 exact observed days, older days folded into 28-day buckets (`day // 28`: lo, hi, sum, n), at most 3 buckets, nothing older than 120 days before the newest scan. A cut scan, or one whose count kept changing, adds nothing to history; a whole read with `hasAllInfo == false` records does.
- Limits: `MAX_ITEMS = 40000` per market, `MAX_MARKETS = 3`, `MAX_RECORDS = 250000`, `COMMIT_STEP = 120`, `ITEMS_STEP = 400`. Over the item cap the kept items are recipe items first, then most listings, then lowest id; the scan is `cut` and not complete.
- A complete saved scan is never replaced by an incomplete one (`kept`). `Apply` writes everything at once; a dropped job writes nothing. 1.3's `Apply` writes a **new** market table containing only the fields it knows.
- Legacy recipe-only `TwichUIDB.workshop.prices` is read, never rewritten, classified `scope = "recipes"`, replaced by the first full scan.

### 2.3 The Market API today [verified, `Market.lua`]
`Source, Info, Markets, Price, Quote, Stats, Trend, Compare, Observed, Series, Status, Freshness, AgeShort`, all read-only, each answer with a `basis` sentence and a reason word for every "no" (`baditem badqty nomarket variant unlisted outofscope nodata insufficient badperiod`). Consumers: `Session.Opportunities`/`Shopping` (through `Market.Price` lookups fed into `Prices.Estimate` and `Prices.Quote`), `WorthTip` (`Market.Price` with `variant`), `ViewOpportunities` (`Price`, `Stats week`, `Series`), `ViewOverview` and `Window` (`Info`, `Status`). Nothing outside `Market.lua`/`Prices.lua` decodes saved strings.

### 2.4 Scan lifecycle today [verified, `Scan.lua`]
Player click only. `IsThrottledMessageSystemReady` → `ReplicateItems` → wait for `REPLICATE_ITEM_LIST_UPDATE` (90 s) → quiet for 2 s (at most 10 s) → read records `0 .. n-1`, 400 per timer tick → stepped `ItemsJob` (400 items per tick, M7.1) → restart if the count changed (at most 3) → re-read after 4 s if records lacked info (at most 2) → stepped commit (120 items per tick) → atomic `Apply`. Closing the house before saving interrupts and writes nothing; closing during saving finishes the save. Tokens end every timer and event of an ended scan.

### 2.5 Forever auction API facts [verified, `Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua`, forever branch]
| Fact | Consequence |
|---|---|
| `ReplicateItems()`: "should be used in place of an 'allItem' QueryAuctionItems call to query the entire auction house". No restriction flag in the documentation entry. | Whether it needs a hardware event (a click) is **not stated** [unknown]. |
| `GetReplicateItemInfo(index)` returns 18 values: name, texture, count, qualityID, usable, level, levelType, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo. `SecretArguments = "AllowedWhenUntainted"`. | Per record: **item id only**, no link, no suffix. Owner names are other players' data: never stored (section 3.4). |
| `GetReplicateItemLink(index)` → itemLink (nilable); `GetReplicateItemTimeLeft(index)` → timeLeft. | Variants are knowable only by a second call per record; its cost is [unknown]. Time left could support "about to expire" evidence later. |
| `ItemKey = { itemID, itemLevel, itemSuffix, battlePetSpeciesID }` | The client itself treats suffix and item level as identity. |
| Events `AUCTION_HOUSE_SHOW` (synchronous), `AUCTION_HOUSE_CLOSED`, `REPLICATE_ITEM_LIST_UPDATE`, throttle events. The core already listens to `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with `Enum.PlayerInteractionType.Auctioneer` (`modules/AuctionatorSkin.lua:412`). | The open signal exists in the always-loaded core; the Workshop is LoD (`WorkshopLauncher.Load`, refuses in combat). |
| `Blizzard_AuctionHouseUI` is LoD, with a camelot-specific `Blizzard_AuctionData.lua`. | Whether stackable goods are bought as **commodities** (any quantity) or as **whole auctions** in Forever is [unknown]. The purchase-cost design handles both (section 4.10). |
| No auction house cut in the source (`Prices.CUT = {}`). | Unchanged: profit stays "before the cut" until a side is confirmed. |

### 2.6 Measured performance facts carried forward
- **[real-client]** M7.1: the single `Items()` call was a live hitch (82 ms focused step at 12,000 items; 135 to 145 ms offline at 40,000); now stepped. Commit steps measured at most 4 ms offline. Client CPU was about 2.4 times offline in the crafting fingerprint comparison (one data point; use it as an order of magnitude only).
- **[real-client]** `string.format("%d")` refuses values above 2^31 (the `perf.market.stats.6k` overflow). All encoders must keep using `("%.0f")`.
- **[real-client]** NaN compares equal to everything; `W.Finite` must run before any comparison of a value read from the game.
- **[measured, earlier]** current market at 23,439 items: 8.3 MB Lua memory, 3.2 MB saved text; history string 72 B average, 175 B worst by construction.

---

## 3. Proposed data schema [proposed]

### 3.1 Database
```
TwichUIWorkshopDB = { v = 2, markets = { [key] = market } }
```
- `v = 2` is written by the first commit of the new code (inside the same `Apply`). Effect on 1.3: `PR.Held()` is true, so 1.3 reads prices and the frozen history and refuses to scan ("held"); it can no longer rebuild a market and drop the new fields. Effect on future code: `v > 2` is held, as today.
- Imports are **not** in this database (section 9).

### 3.2 Market (`f = 3`)
```
market = {
  -- unchanged fields and meanings (1.3 reads these)
  f = 3, scope = "full", realm, side, at, complete, cut, read, used, partial, n, hn, sd,
  items = { [id] = "p,q,l,t,x" },          -- unchanged entry, same rules (exact-fraction minimum, q, x)
  hist  = { [id] = "<v1 string>" },        -- FROZEN legacy minimum history: never extended, trimmed by expiry only
  -- new
  snap  = { seq, kind = "full", alg = 1, at, records, used, invalid, noBuyout, partial, items, client },
  dist  = { [id] = "<distribution entry>" },   -- only items with 2 or more distinct unit prices
  h2    = { [id] = "<daily tier>" },           -- v2 history, days 0..13
  c2    = { [id] = "<bucket tier>" },          -- v2 history, weekly to day 60, two-week to day 120
  scans = { "seq,at,flags,items,records", ... },   -- last 64 accepted scans, oldest first
  v2from = day,                                -- first day of v2 history in this market (the legacy/v2 boundary)
}
```
- `seq` increases by one per accepted scan of the market. `flags` is a small bit set written as digits: complete, cut, changed, partial, fed history, automatic, imported (reserved).
- `client` is the build string when readable (`GetBuildInfo`), otherwise absent. It is provenance, not a key.
- `hn` keeps counting items with **legacy** history (its 1.3 meaning). New counts live in `snap`.

### 3.3 Per-item entries

**Current entry `items[id]`: unchanged.** Keeping it costs about 19 B per item [measured] and buys full 1.3 readability, the cheapest lookup path and unchanged `Market.Price`.

**Distribution entry `dist[id]`** (decimal, `%.0f`, no escaping needed):
```
"alg,r,a,q25,q50,q75,hi,near|p1:q1:l1:m1;p2:q2:l2:m2;...;p6:q6:l6:m6|tq:tl"
```
| Field | Meaning | Stored or derived |
|---|---|---|
| `alg` | Recent Price algorithm version (1) | stored |
| `r` | Recent Price (section 5) | stored: needs the full list |
| `a` | its anchor (weighted 25% point) | stored: needed to explain `r` |
| `q25 q50 q75` | quantity-weighted quartiles of unit price (whole copper) | stored: need the full list |
| `hi` | highest unit price listed | stored (outlier evidence) |
| `near` | items priced at or below 1.10 x `r` | stored ("supply near the price") |
| `pk:qk:lk:mk` | cheapest 6 distinct whole-copper unit prices: price, items, listings, largest single listing | stored, exact |
| `tq:tl` | items and listings beyond tier 6 | stored (conservation) |
| min, q at min, total items, total listings, next price | | **derived** from `items` and tier 1 |
| spread, cheap-outlier flag, depth covered | | **derived** |

- An item with one distinct unit price has **no** `dist` entry: every quartile, `r` and tier are its `p`. In the prototype's wide-spread synthetic market 99% of items had 2 or more tiers [measured]; a real house is likely sparser [unknown].
- Tiers use the **rounded-up whole-copper** unit price, as a buyer sees it. Tier 1's quantity may exceed `items.q` (which counts the exact fraction); that is documented, not reconciled.
- `m` (largest listing in the tier) bounds over-buying when auctions are bought whole (section 4.10). Omitted when `l = 1` (then `m = q`).
- Size: 100 to 107 B per multi-tier item [measured], about 4 MB of text for 40,000 items.

**Daily tier `h2[id]`**: one point per observed day, newest last, day as a delta from the previous point:
```
"d,p,dr,t,l;d,p,dr,t,l;..."        dr = r - p (0 when r = p), t = items listed, l = listings
```
All five values come from the **same** scan (the last accepted whole-read scan that listed the item that day), as v1 does for its one value. Optional trailing `!` on a point: the feeding scan had `partial > 0`.

**Bucket tier `c2[id]`**:
```
"k,s,n,plo,pmean,rmean,rlo,rhi,tmean;..."    s = 7 or 14 (bucket length), k = day // s
```
Points leave the daily tier only when it spans more than 14 + 6 days, a whole week at a time (so `c2` is rewritten about once a week per item, not every scan). Weekly buckets older than 60 days are merged pairwise into two-week buckets (`k = week // 2`). Nothing older than 120 days before the newest scan is kept. Because 28 = 4 x 7 and 14 = 2 x 7, v1's 28-day buckets, v2's weekly and two-week buckets all fall on the same week boundaries.

### 3.4 What is deliberately not stored
- **Seller names** (`owner`, `ownerFullName`): other players' data; never saved. A distinct-seller **count** could be computed transiently later if the field proves populated [unknown]; deferred.
- Bids, bid amounts, high bidders. Bid-only auctions remain counted (`noBuyout`) and excluded from prices.
- Every listing of every scan (section 7, option C).
- Anything derived cheaply on read: spreads, quality levels, posture, Market and Historical Value.

### 3.5 Item identity and variants
- **Key: item id** (unchanged). A full scan gives the id per record and nothing else [verified]; the cheapest variant of an id sets `p`, and `dist` mixes variants.
- **Fallback policy:** `Market.*(item, { variant = true })` keeps answering `nil, "variant"` (as now). A non-variant caller whose item is of a class that *can* have random suffixes (weapon or armor by `GetItemInfoInstant`, uncommon or better) gets the note `mixedvariants` on every answer and Data Quality at most `fair`.
- **Later (A8, after a probe):** for weapon and armor records only, call `GetReplicateItemLink`, parse the suffix, and keep `vitems`/`vdist` under keys `"id:s<suffix>"` with no history at first. Not before a Lab probe measures the call's cost and how often suffixes appear. Item level is not split (Forever items have fixed levels as far as the source shows [unknown]). Battle pets are not split (out of scope; noted).
- Stack size is never part of identity: prices are per unit; stacks only matter for purchase cost (`m`).

---

## 4. Price-source definitions [proposed]

One table per source. "Latest snapshot" = the newest accepted scan of the market. "Daily value" = the h2 point of that day.

### 4.1 Minimum Buyout
- **Meaning:** the cheapest valid buyout unit price in the latest snapshot (`items.p`). **Inputs:** `items`. **Window:** one snapshot.
- **Missing:** `unlisted` (full scope), `outofscope` (legacy recipes), `nomarket`, `variant`.
- **Qualifications:** age, completeness, `thin` (1 listing), `cheapoutlier` when `p < r / 2`.
- **Consumers:** "lowest price now", posting undercut reference (future AH Sell), minimum history chart.
- **Never claims:** a typical price, a sale price, that more than tier 1's quantity is available at it.

### 4.2 Recent Price
- **Meaning:** a robust estimate of the current listing price: the mean price of the cheapest 30% of the listed items, after ignoring listings priced below half of the weighted 25% point (section 5). **Inputs:** the full listing list at scan time; stored as `dist.r` (or `p` for one-tier items).
- **Window:** one snapshot. **Missing:** as Minimum. **Qualifications:** `thin` (fewer than 3 listings), `wide` spread, completeness, age.
- **Storage:** `dist`. **Consumers:** current worth, Market Value input, posture, history chart.
- **Never claims:** a sale price, that the item sells at this price, that it is "fair".

### 4.3 Market Value
- **Meaning:** a recency-weighted median of daily Recent Prices over the last 14 days. Weights by age in days: 4 (0 to 2), 2 (3 to 6), 1 (7 to 13). Weighted median = the smallest daily value whose cumulative weight (values sorted ascending) reaches half the total weight. Integer weights keep the reference model exact.
- **Inputs:** `h2` (`p + dr`). **Window:** 14 days ending today.
- **Missing:** no daily point in 14 days → `nil, "stale"`; one point → that value, quality `limited`; legacy minimum days are **never** used.
- **Consumers:** Item Advisor sell value, Opportunities sell side (A7), posture's current side.
- **Never claims:** a sale average or expected sale price; it is a smoothed listing estimate.

### 4.4 Historical Value
- **Meaning:** the median, over observed days in the last 60 days, of daily Recent Prices. Days 0 to 13 count individually; each weekly bucket contributes its `rmean` with weight `n` (its observed days).
- **Window:** 60 days. **Missing:** fewer than 3 observed days → `insufficient`; buckets present → the answer carries `aggregate = true` (a median taken from bucket means is approximate).
- **Consumers:** posture reference, Item Advisor "usual price", charts' reference line.
- **Never claims:** anything about days not scanned (missing days are not imputed and do not count).

### 4.5 Long-term range (120 days)
- **Meaning:** low and high of Recent Price (`rlo`, `rhi`, daily values) and low of Minimum over the retained 120 days, plus observed-day count. Legacy v1 minimum points and buckets contribute **to the minimum low only**, labelled `legacy`.
- **Missing:** `nodata`. **Never claims:** a value; it is a range.

### 4.6 Dispersion
- **Meaning (snapshot):** `spread = (q75 - q25) / q50`; classes `tight` < 0.10, `moderate` < 0.30, `wide` otherwise; plus `cheapoutlier` and `hi / r`. **Meaning (history):** the daily range `rlo..rhi` per bucket.
- **Consumers:** Data Quality, Item Advisor ("prices vary a lot"). **Never claims:** volatility of sales.

### 4.7 Available Supply
- **Meaning:** items and listings in the latest snapshot (`t`, `l`), items near the Recent Price (`near`), items at the minimum; history: daily `t`, `l` and bucket `tmean`.
- **Never claims:** demand, sales, sell-through. A falling supply may mean sales, cancellations or expiries; the text says "listed", never "sold".

### 4.8 Trend
- **Meaning:** for one metric (Recent Price, Minimum or Supply, never mixed), the median of the newer half of the window's observed days against the median of the older half. Default window 14 days; each half needs 2 observed days; `flat` when the change is under 5%.
- **Missing:** `insufficient`. Existing `Market.Trend` (first vs last minimum, 7 days) is unchanged and stays labelled as such.
- **Never claims:** a forecast.

### 4.9 Price Posture
- **Meaning:** Recent Price against Historical Value: `cheap` below 0.85, `expensive` above 1.15, `normal` between (thresholds: decision D8).
- **Requires:** Historical Value from at least 5 observed days and Data Quality at least `fair`; otherwise `unknown` with the reason.
- **Never claims:** that buying now is a good deal; it compares listing prices only.

### 4.10 Purchase cost (quantity-aware)
- **Meaning:** what buying `n` items is expected to cost, walking tiers 1 to 6 cheapest first.
  - `exact`: `n` fits inside the stored tiers and auctions are bought per item, or every tier used has uniform listings that sum exactly.
  - `range`: auctions are bought whole (or that is not known): low = per-item walk; high = low plus at most `m - 1` items of over-buy at the last tier used. Until the commodity question is answered (A6 probe) every multi-listing walk is a `range`.
  - `estimate`: `n` exceeds the six tiers but not `t`: the tiers' cost plus the rest at tier 6's price, marked "at least".
  - `few`: `n > t`. `none`: no data.
- **Replaces** today's `Prices.Quote` "estimate" state for consumers that opt in (A7); `Quote` itself is unchanged.
- **Never claims:** that listings still exist; another buyer may take them.

### 4.11 Data Quality
A level (`good`, `fair`, `limited`, `none`) and the list of reasons that set it, computed on read. No numeric score [proposed rule table, decision D7]:

| Level | All of |
|---|---|
| `good` | snapshot complete, age at most 24 h, at least 5 listings, spread not `wide`, at least 7 observed days in the last 30, no `mixedvariants` |
| `fair` | age at most 3 days, at least 3 listings, not `cut` |
| `limited` | anything else with a price |
| `none` | no price (`unlisted`, `nomarket`, `variant`, `outofscope`) |

Reasons are words the UI can print ("Only 2 listings", "Scanned 4 days ago", "Prices vary a lot", "Seen on 2 days this month", "Several versions of this item are mixed").

### 4.12 Future sources (extension points, not designed in detail)
| Source | Needs | Hook |
|---|---|---|
| Actual sale price | the player's own mail invoices (`Mail.lua` already reads money gains) | `kind = "sale"` series in a separate Ledger store, never in `h2` |
| Observed sale rate / sell-through | the player's own posted vs sold auctions | Ledger; never inferred from listing disappearance |
| Deposits and fees | the cut per side (`Prices.CUT`), deposit formula from the client | `MK.Fees`, reserved |
| Character/account transactions | Gold Ledger | its own saved data |
| External data | section 9 | `opt.sources` |

---

## 5. Representative-price algorithms

### 5.1 Candidates (all on the full listing list of one item: whole-copper unit price `u`, items `q`, sorted ascending; `T` = total items)
- **A. Weighted percentile:** the price of the first listing whose cumulative items exceed 25% of `T`.
- **B. Price-tier mode:** group consecutive prices into clusters (a new cluster starts above 1.05 x the cluster's first price); among clusters that start inside the cheapest 50% of supply, take the one holding the most items; its item-weighted mean.
- **C. Band mean (recommended):** anchor `a` = A; ignore listings with `u < a / 2`; of the rest, the item-weighted mean of the cheapest 30% of their items (a fraction of a listing counts at the boundary).

### 5.2 Hand examples (copper; recomputed by [a1-prototypes/algos.lua](a1-prototypes/algos.lua) [measured])
| Case | Listings (price x items) | Min | A | B | C |
|---|---|---|---|---|---|
| 1 healthy spread | 9500x5, 9800x5, 10000x10, 10200x10, 10500x10, 11000x5 | 9500 | 10000 | 10233 | **9741** |
| 2 one 1c listing, deep market | 1x1, 5000x40, 5200x10 | 1 | 5000 | 5040 | **5000** |
| 3 thin, one cheap unit | 1000x1, 5000x3 | 1000 | 5000 | 5000 | **5000** |
| 4 one absurd high listing | 5000x10, 9990000x1 | 5000 | 5000 | 5000 | **5000** |
| 5a large wall just below | 4900x200, 5200x5 | 4900 | 4900 | 4900 | **4900** |
| 5b few cheap under a wall | 4500x5, 6000x200 | 4500 | 6000 | 6000 | **5878** |
| 6 two clusters | 100000x10, 200000x90 | 100000 | 200000 | 200000 | **166667** |
| 7 one listing | 300000x1 | 300000 | 300000 | 300000 | **300000** |
| 8 100 listings, 1c apart | 5000..5099 x1 | 5000 | 5025 | 5050 | **5015** |
| 9 one 200-stack vs singles | 4000x200, 6000x5 | 4000 | 4000 | 4000 | **4000** |
| 10 rare, far apart | 800000, 1500000, 4000000 (x1) | 800000 | 800000 | 800000 | **800000** |
| 11 bait volume, 29% of supply | 2000x8, 5000x20 | 2000 | 2000 | 5000 | **2143** |
| 12 bait volume, 20% of supply | 2000x5, 5000x20 | 2000 | 5000 | 5000 | **5000** |

Worked check of case 1 for C: T = 45; 25% = 11.25; cumulative 5, 10, 20 → anchor 10000; nothing below 5000; 30% of 45 = 13.5 items: 5 x 9500 + 5 x 9800 + 3.5 x 10000 = 131,500 / 13.5 = 9740.7 → **9741**.
Case 6 for C: anchor 200000 (cumulative 10 is not above 25); 100000 is not below 100000, so kept; 30 items: 10 x 100000 + 20 x 200000 = 5,000,000 / 30 = **166667**.

### 5.3 Where they disagree and why C
- **A** is a single listing's price: it jumps between tiers (case 8 moves with one listing) and ignores everything below its point (case 5b says 6000 although 5 items are buyable at 4500). Simple, but it hides real cheap supply.
- **B** finds "where most of it sits", which suits valuing a big stack but **ignores 29% of supply in case 11** and the whole cheaper cluster in case 6. Its clustering threshold (5%) is a tuning knob players cannot see, and it is discontinuous at cluster boundaries.
- **C** moves smoothly (case 8: 5015), keeps real cheap supply in proportion (5b: 5878, 6: 166667, 11: 2143), and drops a cheap listing only if it is both **under 25% of supply and under half the anchor** (cases 2, 3, 12). It never removes more than 25% of supply, which bounds how much a filter can hide. High outliers never enter (case 4). One sentence explains it: *"the average price of the cheapest 30% of what is listed, leaving out a few listings far below the rest."*
- **Thin markets:** with 1 to 2 listings every method returns roughly the minimum; C does too, and Data Quality says `limited` ("Only 2 listings").
- **Edge fixed during A1:** with "at least 25%" instead of "more than 25%" in the anchor, case 3 gave 1667 (a single cheap unit out of four pulled the value down by two thirds). The rule is strictly "more than".

### 5.4 Manipulation and the limits of listing data
- A seller posting a large cheap volume (case 11) **does** move every robust estimate, because that supply is real and buyable. That is correct for a listing estimate.
- A seller buying out the cheap supply and relisting high is **invisible** to snapshot data except as a jump in Recent Price with a drop in supply; Market Value (14-day weighted median) and Historical Value (60-day median) dampen a one-day jump; Posture would say `expensive`.
- Nothing here knows what sold. A price with no buyers looks identical to a price with many.

### 5.5 Arithmetic and cost
- Exact integer arithmetic is used while `u x q x 10 < 2^53` (weights in tenths of an item: 30% of `T` items = `3T/10`); above that, double arithmetic with the result documented as within 1 copper. The reference model uses the same rule.
- Rounding: half up to whole copper; at least 1.
- Cost per item: one sort of its **distinct** prices (k log k), one pass. Prototype: 236,500 distinct tiers from 250,000 records over 29,937 items, finalize 0.46 s total, worst 400-item step 12.9 ms offline [measured, wide synthetic spread]. That step is too long for a frame: A3 steps by **work units** (distinct tiers, about 1,000 per step) instead of items.

---

## 6. Historical storage and chart support

### 6.1 Tiers and what each period holds [proposed]
| Age | Resolution | Fields |
|---|---|---|
| latest snapshot | per scan | everything in `items` + `dist` |
| 0 to 13 days | one point per observed day | min, Recent Price, items, listings, partial flag |
| 14 to 60 days | weekly buckets | observed days, min low, min mean, Recent mean/low/high, items mean |
| 61 to 120 days | two-week buckets | same |
| legacy (frozen v1) | 7 exact days + 28-day buckets, until expired | minimum only (lo, hi, mean) |
| market level | last 64 scans | time, quality flags, item and record counts |

**Intraday:** no per-item intraday points [decision D3]. A chart can show the latest snapshot as "now" beside today's daily point, and the scan log shows how often the house was scanned. A per-item ring (4 points in 48 h) would add about 50 to 80 B per item; deferred unless the owner wants intraday item charts.

### 6.2 Chart-ready read API (A4) [proposed]
`Market.History(item, metric, opt)` with metric `min`, `recent`, `supply`, `listings`, `range`:
```
{ item, metric, basis, unit = "copper" | "items" | "listings",
  points = { { from, to, kind = "day" | "week" | "fortnight" | "legacy-day" | "legacy-bucket",
               v, lo, hi, n, partial, provenance = "local" | "legacy" } ... },     -- oldest first
  gaps   = { { from, to, reason = "noscan" | "unlisted" | "notretained" | "cut" } ... },
  today, v2from, resolutionChanges = { day, ... } }
```
Rules: a point exists only for an observed day or a bucket of observed days; **nothing is interpolated**. A gap is any run of days between points; its reason comes from the scan log (`noscan` when no accepted scan that day, `unlisted` when scans happened without the item, `notretained` before the retention, `cut` for scans that could not feed history). A chart draws a line only between points closer than a gap threshold (suggested 3 days for daily points, one bucket for buckets) and a dashed or no line otherwise; bucket points are drawn as bands (`lo..hi`) with their mean, never as daily points. Legacy points appear in `min` and `range` only.

### 6.3 Coverage after N days of daily scanning [measured, synthetic, 3,000-item sample scaled to 40,000]
Recommended layout ("lean, two-week tail"), mixed market (30% of items listed on 90% of days, 40% on 35%, 30% on 6%):

| After | Average per item | Worst item | 40,000 items |
|---|---|---|---|
| 7 days | 52 B | 164 B | 2.0 MB |
| 30 days | 184 B | 504 B | 7.0 MB |
| 60 days | 328 B | 775 B | 12.5 MB |
| 120 days | 509 B | 1,053 B | 19.4 MB |

Sparser market (10% / 30% / 60% of items): 365 B average, 13.9 MB at 120 days. Adding listings to the daily points (not in the measured variant) is estimated at under 1 MB more.

---

## 7. Storage strategies compared

| | **A. Compact summary** (recommended, section 3) | **B. Richer daily, same tail** | **C. Raw recent snapshots** |
|---|---|---|---|
| Snapshot | v1 entry + dist (6 tiers, quartiles, r) | same | every listing of the last 3 scans |
| Daily tier | 14 days: d, p, r, t, l | 30 days: d, p, r, q75, t, l | 14 days as A |
| Older | weekly to 60, two-week to 120 | weekly to 120 | as A |
| History text, 40k items, 120 d (mixed) | **19.4 MB** [measured] | 30.1 MB [measured] | A + raw |
| Snapshot text, 40k multi-tier items | 4.1 MB dist + 0.7 MB entries [measured] | same | about 250,000 records x 3 x ~15 B = **11 MB** [estimate] |
| Lua memory | about the text size (798 B resident per item for 788 B of text in two id-keyed string tables) [measured] | same ratio | raw tables 3 to 5x text [estimate] |
| Scan finalize | 0.46 s CPU at 30k items; stepped by tiers [measured] | same | + serialization of every record |
| Commit (history), per 120 items | about 7 ms offline (decode + encode) [measured] → time-budgeted steps | about 10 ms [measured] | as A |
| History query | one decode of a < 1.1 KB string | < 2 KB | as A |
| Migration | none (legacy frozen) | none | none |
| Chart accuracy | daily for 2 weeks, weekly bands to 60 d, 2-week bands to 120 d | daily for a month | as A + re-derivable snapshots |
| Item Advisor / AH | Recent, Market, Historical, tiers for cost | same | could re-run new algorithms on 3 scans |
| Evidence discarded | listings beyond tier 6 (kept as totals); intraday changes; individual days after 2 weeks | days after 30 | the same after 3 scans |

Today's format for comparison: about 72 B of history per item (175 B worst), about 8 MB per full market worst [verified measurement from 2026-11-11].

**Choice: A.** B costs 55% more for daily resolution between 14 and 30 days, which a two-week chart does not need and a month chart shows acceptably as weekly bands. C is the only way to re-run a future algorithm on raw data, but three scans of raw evidence is not a history and costs more than the whole snapshot summary; the quartiles and six exact tiers keep enough to compute any lower-band estimator approximately. **Totals for A** (one full 40,000-item market after 120 days, mixed): about 24 MB of saved text including keys, about 20 to 25 MB resident while the Workshop is loaded; a 20,000-item sparse market about 8 MB [estimate from the measured rates]. Three markets at the cap would be about 70 MB worst, hence decision D4.

Transient memory during a scan: the per-item tier map, packed as `qty * 65536 + listings` per distinct price, measured **14.5 MB** for 250,000 records / 30k items and 22.9 MB for 400,000 records / 40k items, in addition to today's batch table (11 MB) [measured]. Unpacked `{qty, listings}` tables measured 37.8 MB, so A3 must use the packed form. Released after the commit.

---

## 8. Automatic scan policy [proposed; A6]

**Trigger:** the core (always loaded) sees `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` with type `Auctioneer` (or `AUCTION_HOUSE_SHOW`). If the setting is on and the player is not in combat, it loads the Workshop through `WorkshopLauncher.Load` (which already refuses in combat), then calls `Session.StartScan({ auto = true })` once `AuctionHouseFrame` is shown (checked over at most 5 s of timer ticks, then gives up silently).

**Gates (all must pass, else nothing is sent and the bar shows nothing or one quiet line):**
1. No scan running; the posting page's search is not busy (`R.AuctionScan.Busy`, as today).
2. The market's newest accepted scan is older than **60 minutes** (decision D5). A complete scan within the last 60 minutes means no request.
3. No automatic attempt for this market ended `dropped`, `throttled`, `noResponse` or `api` in the last **15 minutes** (session memory only, nothing saved).
4. `PR.Held()` is false.
5. Once per auction house visit: closing and reopening within 60 minutes does not retry.

**Behaviour:**
- Same state machine, same completeness rules, same atomic commit, same `kept` rule. The only differences: `snap.flags` marks it automatic, and its messages are quieter (no failure line unless the player opens the Workshop; the bar shows "Updating prices... 40%").
- **Stop** control on the progress bar (new): ends the scan as `interrupted` with nothing written (the existing token path). Also available for manual scans.
- Closing the house before saving interrupts it (as today); during saving it finishes (as today).
- Browsing and buying: the scan sends one request and then only reads local results; it never calls a search, buy, bid, post or cancel function. Whether `ReplicateItems` delays the player's own searches through the throttle is [unknown] and is an A6 real-client check. If the player's search starts while the scan is still `waiting` for the throttle, the automatic scan gives up (it never competes with a player action).
- If the client refuses `ReplicateItems` outside a hardware event [unknown], A6 falls back to a one-click "Update prices" prompt on the bar (no popup, no chat), and the setting's text says so.

**Setting (A6, not now):** one row in the Workshop settings page: **"Update prices automatically when I open the auction house"**, default on, with a one-line note "Reads the auction house once an hour at most. Nothing is bought or posted." Stored through the core's settings layer so the core can read it before the Workshop loads (the exact switch name is an A6 detail).

**Cost of the default:** every auction house visit loads the Workshop and its saved variables (up to about 24 MB per full market). This is the price of auto-scanning and is measured in A6 (`workshop.load` scope already times the load).

---

## 9. External data and a desktop companion [proposed boundary; not built]

- **Transport:** addons cannot read files at runtime. A companion would write a separate load-on-demand data addon (for example `TwichUI_WorkshopData`) while the game is closed, containing **one global table of strings**. That file is executed by the client as addon code (like any addon); this is the owner's call (D10) because the project rule forbids executing untrusted data. Our own parser then validates every string; nothing inside is executed by TwichUI.
- **Record:** `{ schema, source = { id, name, version }, generated = time, market = { realm, side, region? }, kind = "daily" | "snapshot" | "sale", items = { [id] = "<same encodings as h2/dist>" } }`.
- **Validation:** schema known, sizes bounded (items, string length, days), market key matches a known `Realm|Side` exactly, timestamps not in the future and inside 120 days, values pass `W.Int`; anything else rejected whole per item.
- **Never merged:** imported observations live in their own tables and are never written into `h2`/`c2`. The API takes `opt.sources = { "local" }` by default; `{ "local", "import" }` fills days without a local observation, each point carrying `provenance = "import:<source>"`. Same day in both: local wins for values; both are visible in a chart.
- **Duplicates:** same source, market, item and day → the newer `generated` wins. **Freshness:** an imported day never makes the "Prices updated" chip fresh; the chip describes local scans only.

---

## 10. Public Market API extensions [proposed; A4 and A5]

`Market.API = 2`. Every existing function keeps its signature and meaning (they describe the minimum and the v1 statistics). New functions, all read-only, all `(item, ..., opt)` with `opt = { market, now, variant, sources }`:

| Call | Returns |
|---|---|
| `Value(item, kind, opt)` | `kind` = `"min" \| "recent" \| "market" \| "historical"`: `{ kind, value, basis, at, age, freshness, window = { from, to, days }, n, aggregate, complete, quality = { level, reasons }, provenance, notes }` or `nil, reason` (adds `stale`, `mixedvariants` note) |
| `Distribution(item, opt)` | `{ min, q25, q50, q75, hi, recent, anchor, tiers = { { price, items, listings, largest } }, tail = { items, listings }, spread, spreadClass, cheapOutlier, total, listings, near }` |
| `Supply(item, opt)` | `{ items, listings, near, atMin, typical = median daily items over 14 days, trend }` |
| `Cost(item, qty, opt)` | section 4.10: `{ state, low, high, unitLow, unitHigh, tiersUsed, covered, granularity = "item" \| "auction" \| "unknown" }` |
| `Quality(item, opt)` | `{ level, reasons, facts = { age, complete, listings, days30, days60, spreadClass, variant } }` |
| `Posture(item, opt)` | `{ posture, ratio, current, reference, n, quality }` |
| `History(item, metric, opt)` | section 6.2 |
| `TrendOf(item, metric, days, opt)` | section 4.8: `{ direction, from, to, change, percent, nOlder, nNewer, metric }` |
| `Sales(item, opt)` | reserved: `nil, "nosales"` until the Ledger exists |

Caching: `Value("market")`, `Value("historical")` and `Quality` are cached per `(market key, snap.seq, item)` in one bounded table (at most 2,000 entries, cleared on commit). Nothing else is cached. Basis sentences: one per kind in `Market.BASIS`, all containing the word "listing" or "listed".

---

## 11. Migration and backward compatibility [proposed]

**Principle: read old data in place, write new data beside it; convert nothing.**

| Case | Behaviour |
|---|---|
| `v = 1`, `f = 2` market (1.3) | Read as today. The first new commit writes `f = 3` with the same `items` rules, keeps `hist` (now frozen: trimmed by expiry, never extended), starts `h2`/`c2`/`dist`/`scans`, sets `v2from` to the scan's day and `db.v = 2`, all inside `Apply`. |
| legacy recipes-only (`TwichUIDB.workshop.prices`) | Unchanged (replaced by the first full scan). |
| `v = 2` read by 1.3 | 1.3 is held: prices and frozen history read correctly (same `items` and `hist` encodings); scans refused. Verified against 1.3's code path in A2 tests. |
| `v > 2` | Held (unchanged rule). |
| interrupted first commit | Nothing written (the existing job contract); the next scan tries again. |
| repeated commits | Idempotent with respect to migration: `f = 3` markets are never "migrated" again; the legacy `hist` is only trimmed. |
| malformed `dist`/`h2`/`c2` string | Treated as absent for that item (as v1 does), never repaired by guessing; the next scan's observation replaces it. A malformed `scans` entry is skipped. |
| clock moved back | As v1: an observation older than the newest kept day is ignored. |
| startup work | None: no load-time migration pass. Legacy `hist` trimming stays inside the commit's existing "old" phase. |

**Meaning preserved:** a legacy point is "the cheapest buyout listing of that day's last whole-read scan"; a v2 daily `p` has exactly that meaning, so the `min` series joins them (legacy before `v2from`, v2 from `v2from`), each point labelled. Legacy points never appear in Recent, Market or Historical Value, nor in a Recent Price chart. No v2 field is ever filled from v1 data.

**Rollout check:** A2's tests load a fixture saved by 1.3's encoder, commit with the new code, then read the result with a copy of 1.3's reader (`Prices.lua`/`History.lua`/`Market.lua` at `v1.3.0`, stored as a test fixture) and require identical `Price`/`Stats`/`Series` answers for the legacy days. The Test Lab gets a read-only integrity case (counts of `f = 2`/`f = 3` markets, malformed strings per table).

---

## 12. Test and performance requirements

### 12.1 Invariants per algorithm (each needs a test that would fail on a plausible wrong answer)
| Area | Invariants |
|---|---|
| Tier map / dist | conservation: `sum tier items + tail items = t`, `sum listings + tail listings = l`; tiers strictly ascending; tier 1 price = `p` rounded rule; no record counted twice (every record added twice doubles every count); shuffled input gives the same entry; bid-only and invalid records excluded and counted |
| Quantiles | weighted quantile equals the brute-force answer on the expanded item list; `p <= q25 <= q50 <= q75 <= hi`; one-tier items have no dist entry |
| Recent Price | equals the independent reference on random lists; `p <= r <= q50` (the band ends by 25% + 30% x 75% = 47.5% of supply); never removes more than 25% of supply; cases 1 to 12 of section 5.2 exactly; scaling all prices by k scales r by k (within rounding); adding a listing above the band never changes r |
| Daily tier | at most one point per day; points from one scan only; cut scans add nothing; partial flag carried; delta encoding round-trips |
| Buckets | fold only whole weeks; `rlo <= rmean <= rhi`; `n` equals the observed days folded; nothing older than 120 days; weekly-to-two-week merge preserves n and sums; boundaries at days 13/14, 60/61, 119/120/121 |
| Market/Historical Value | weighted median equals the brute force over the day list; missing days never count; `stale` exactly after 14 days without a point |
| History API | no point on a day without an observation; every gap has a reason consistent with the scan log; legacy points only in `min`/`range` |
| Isolation | another market's scans change nothing; imports never change local answers with default `sources` |
| Unknown vs zero | no API returns 0 for missing data; every nil has a reason |
| Migration | 1.3 fixture → commit → 1.3 reader gives identical legacy answers; second commit changes nothing in `hist` except expiry; `v > 2` held |
| Cancellation | Stop, close and a failed step at every phase leave the saved database byte-identical (deep compare) |

### 12.2 Tools to extend
- **Reference models:** extend `test_workshop_market_reference.lua` (and the Lab `Reference.lua`) with an independent listing-level model (expanded item lists, sorted exact fractions) for tiers, quantiles and Recent Price, and a full day-list model for h2/c2 and the values.
- **Fixtures:** a new seeded listing-distribution generator with wide and narrow spreads, walls, cheap baits and thin items (`FX.Listings`), and calendars that exercise every tier boundary.
- **Mutation catalog** (`tools/mutations/workshop.py`, group `market`): at least anchor `>=` vs `>`, half-anchor gap off, 30% → 25%, tier order, tail dropped, fold of a partial week, two-week merge losing `n`, weights 4/2/1 swapped, legacy points leaking into Recent series, `v` not bumped.
- **Simulator** (`tools/simlab/workshop.sh`): the fake house serves listing distributions; scenario for automatic start on open, Stop, close mid-read; settings page row (A6).
- **Test Lab:** benchmarks `market.aggregate.*` **v3** (tier map + dist finalize), `history.commit.v2.120d`, `market.value.6k`; probes for A6 and A8 (below).
- **Persistence:** M9's saved-variables round trip is a prerequisite for A2's fixture tests (or A2 builds the minimal writer/reader it needs).

### 12.3 Performance acceptance (relative, no absolute targets until client figures exist)
- Longest production step of a scan with the new finalize is **no longer than today's longest step** on the same fixture in both interpreters (M7.1 v2 figures are the baseline), using work-unit or time-budgeted steps.
- Commit steps are time-budgeted (about 4 ms of work per tick, the Lab's `Pace` pattern) rather than fixed at 120 items, because the measured per-120-item cost rises from about 4 to about 7 ms offline with v2 strings.
- Retained memory after a scan returns to the pre-scan level plus the new saved data (forced-collection case, offline and `perf.retained.*`).
- In the client: `workshop.load` time for a synthetic 40,000-item, 120-day database, recorded before A4 ships (the SavedVariables parse cost at 20+ MB is [unknown]).

---

## 13. Implementation milestones

Each is one request, follows the roadmap's verification policy (section F) and ends with `./tests/run.sh`. Reasoning: **Opus or High** helps A3 (finalize stepping and exact arithmetic), A4 (fold/expiry boundaries and the legacy join) and A5 (statistic definitions and the reference model); **Sonnet Medium** suits A2, A6 (with care on events) and A7.

**A2. Schema v2 and compatibility (no new data yet)**
- Objective: the `v = 2` / `f = 3` contract, readers that accept both, the frozen-legacy rule, held behaviour, the 1.3-compatibility fixture.
- Files: `Prices.lua` (Store, Checked, Held, Apply writing `f = 3` with empty new tables, `snap`, `scans`, `v2from`), `Market.lua` (`Info` reports `f`, `v2from`), tests: `test_workshop_prices.lua`, new `test_workshop_schema.lua`, fixture `tests/fixtures/workshop_v13/` (1.3's three files from `git show v1.3.0:`).
- Accept: section 11 table holds case by case; commits keep all existing answers; 1.3 reader on a v2 database gives identical answers; a dropped job writes nothing.
- Simulator: `workshop.sh` unchanged pass. Real client: `/reload` after one scan; 1.3 downgrade check optional.
- Out of scope: dist, h2, auto-scan, UI.

**A3. Rich snapshot collection**
- Objective: packed tier map in `Batch:Add`, dist entries and Recent Price built in the stepped finalize by work units, `snap` counts.
- Files: `Prices.lua` (Batch, ItemsJob), `Scan.lua` (steps unchanged in shape), new pure `Dist.lua` (encode/decode/Recent/quantiles; the only code that knows the string), `.toc` (after `History.lua`), tests + reference model + mutants.
- Accept: section 12.1 tier/quantile/Recent invariants; cases 1 to 12; benchmark v3 longest step not above v2's; transient memory reported.
- Real client: a scan's `workshop.scan` worst step; dist entry count vs items.
- Out of scope: history, API beyond an internal `Prices.Dist(market, item)`.

**A4. History v2 and chart API**
- Objective: h2/c2 recording in the commit, folds, expiry, scans log use, `Market.History`, legacy join for `min`.
- Files: new pure `History2.lua`, `Prices.lua` (Job phases, time budget), `Market.lua` (`History`), tests + day-list reference + mutants, Lab benchmark `history.commit.v2.120d`.
- Accept: bucket and boundary invariants; gaps with reasons; no point invented; legacy only in `min`; commit step bound per 12.3; `workshop.load` measured on a synthetic full database in the client before release.
- Out of scope: values, charts UI.

**A5. Valuation**
- Objective: `Value`, `Distribution`, `Supply`, `Cost`, `Quality`, `Posture`, `TrendOf`, bounded cache.
- Files: `Market.lua` (or a new pure `Valuation.lua` it calls), tests, reference model for weighted medians and the tier walk, mutants.
- Accept: every source's "missing" and "never claims" rules in section 4 have a test; basis sentences say "listing".
- Out of scope: consumers.

**A6. Automatic scanning**
- Objective: section 8. First step: a Lab probe (guided, read-only besides one request the player approves) recording whether `ReplicateItems` is accepted from an event handler without a click, the time to first update, whether a player search right after is delayed, whether stackables buy per item (commodity) or per auction, and whether `owner` is populated (count only).
- Files: core `WorkshopLauncher.lua` or a small core hook file (+ `.toc`), `Scan.lua` (`auto` flag, Stop), `AuctionButton.lua` (Stop, quiet text), `Session.lua`, `TwichUI_Settings/pages/Workshop.lua`, settings contract tests, simulator scenario.
- Accept: gates of section 8 each tested; no request in combat or when held; Stop writes nothing; one request per visit.
- Real client: the probe results, then normal play with the setting on.

**A7. Consumer integration**
- Objective: Opportunities and Shopping use `Cost` for materials and `Value("market")` (fallback `recent`, then `min`, labelled) for outputs; `WorthTip` shows the chosen source and Quality; Overview shows Posture where quality allows.
- Files: `Session.lua`, `Opportunities.lua`, `Shopping.lua`, `Worth.lua`, `WorthLayout.lua`, views; crafting reference model update; `--group crafting` mutants.
- Accept: no consumer decodes saved strings; every displayed figure names its source; unchanged results when only v1 data exists.

**Later:** A8 variants (probe first), A9 Ledger and sale sources, A10 import boundary, charts UI.

---

## 14. Product decisions requiring owner approval

| # | Decision | Recommendation | Trade-off / example |
|---|---|---|---|
| D1 | Recent Price algorithm | **C, band mean** (anchor > 25%, ignore below half the anchor, cheapest 30%) | Case 6 (10 at 10g, 90 at 20g): C says 16.67g, A and B say 20g. C keeps real cheap supply in proportion; A/B are simpler but hide it. |
| D2 | History resolution and retention | **Daily 14 days, weekly to 60, two-week to 120** | Daily for 30 days costs about 55% more (30 vs 19 MB per full market) for daily points in days 15 to 30. |
| D3 | Intraday item history | **None per item**; scan log + latest snapshot | A 4-point/48 h ring adds about 2 to 3 MB per full market. |
| D4 | Storage budget and market count | **Keep 3 markets**, accept about 20 to 25 MB worst per full market (typical much less); revisit after real `workshop.load` figures | Alternative: 2 markets, or rich history only for the 2 most recently scanned markets (the third keeps snapshot + legacy-style minimum). |
| D5 | Automatic scan frequency | **On by default; at most once per market per 60 min; 15 min back-off after a refusal; once per visit** | 30 min gives fresher intraday data but more throttle risk (other addons claim one full scan per 15 min [unknown]). |
| D6 | Variant handling | **Item-id aggregate with a `mixedvariants` note until a probe**; then suffix keys for weapons/armor only | Splitting all records needs 250,000 link calls per scan [cost unknown]. |
| D7 | Data Quality thresholds | **The table in 4.11** (good: complete, ≤ 24 h, ≥ 5 listings, not wide, ≥ 7 days in 30) | Stricter thresholds make most items "limited" in a small house. |
| D8 | Posture thresholds | **±15% against the 60-day Historical Value, at least 5 observed days** | ±10% flags more items as cheap/expensive; more noise. |
| D9 | Source priority in consumers | **Buying: `Cost` of the real quantity. Selling/worth: Market Value → Recent → Minimum, always labelled** | Using Minimum for selling (today) overstates profit when the cheapest listing is a bait; using Market Value lags a crash by days. |
| D10 | External data transport | **Defer; if built, a generated LoD data addon validated by our parser, local data always first** | A generated Lua file is executed by the client as addon code; the alternative (pasted strings) cannot carry MBs (`docs/workshop.md`, large paste capture). |

Related open roadmap decisions this design touches: "the profit bound" (roadmap decision 3) is **superseded** by tier-walk `Cost` (D9); "market side when the house is closed" (decision 2) is unchanged and independent.

---

## 15. Known limitations and deferred capabilities

- Listing data only: no sales, demand, sell-through or real price paid; disappearing listings are not sales.
- One snapshot per scan: anything listed and bought between scans is invisible.
- Forever specifics [unknown]: full-scan throttle, `ReplicateItems` without a click, `hasAllInfo` frequency, commodity vs whole-auction buying, `GetReplicateItemLink` cost, `owner` population, SavedVariables parse time at 20+ MB, neutral auctioneer side.
- Variants are mixed per item id until A8.
- Buckets keep low/mean/high, not daily shapes; medians that use buckets are approximate (flagged).
- The prototype used **synthetic** price distributions (log-uniform base prices, up to ±50% spread, 1% outliers, Zipf-like popularity); real Forever houses may have fewer tiers per item and fewer items, which would make every size figure smaller.
- Deferred: per-item intraday history, seller counts, time-left evidence, variant keys, sale/Ledger sources, imports and the companion, charts UI, Auction House Browse/Sell replacement.

---

## Appendix A. Prototype commands (offline, throwaway; not part of the addon or the test suite)
```
lua5.1 docs/workshop/a1-prototypes/algos.lua                  # section 5.2 table
lua5.1 docs/workshop/a1-prototypes/snapshot.lua 30000 250000  # dist sizes, finalize time, first history estimate
lua5.1 docs/workshop/a1-prototypes/storage.lua acc 30000 250000          # packed tier map memory
lua5.1 docs/workshop/a1-prototypes/storage.lua hist                      # history variants (several minutes)
```

## Appendix B. Copy-ready prompt for A2 (do not run until approved)

> **TwichUI Workshop — Market Data Foundation 2.0, milestone A2: schema v2 and compatibility.**
> Branch `feature/workshop`. Read `CLAUDE.md`, `docs/workshop/market-data-foundation-v2.md` (sections 2, 3, 11, 12, 13 A2) and `docs/workshop/testing-roadmap.md` section F before editing.
> Implement only A2: `TwichUIWorkshopDB.v = 2` and markets `f = 3` as specified in section 3.1 to 3.2, written atomically in `Prices` `Job:Apply` on the first commit; `items` and `sd` unchanged; `hist` frozen (trimmed by expiry in the existing "old" phase, never extended by new scans); new empty `dist`, `h2`, `c2`; `snap` (seq, kind, alg = 1, at, records, used, invalid, noBuyout, partial, items, client when readable); `scans` (last 64 accepted scans, the encoding in 3.2); `v2from`. Readers accept `f = 2` and `f = 3`; `v > 2` is held; malformed new fields are treated as absent. `Market.Info` reports `f` and `v2from`. No distribution, no new history, no API beyond that, no UI, no auto-scan.
> Tests: new `tests/test_workshop_schema.lua` covering every row of section 11's table, including a fixture database written by 1.3's encoders and read back through 1.3's reader (copy `Prices.lua`, `History.lua` and `Market.lua` from `git show v1.3.0:TwichUI_Workshop/...` into `tests/fixtures/workshop_v13/`), deep-compare of the saved database after a dropped job, Stop and a failing step. Update `test_workshop_prices.lua` only where the stored shape changed. Run `luac5.1 -p` on edited files, the focused tests, `test_workshop_market_reference.lua`, `bash tools/mutate.sh --group market` (add catalog entries for "v not bumped", "legacy hist extended by a new scan", "1.3 field dropped from f = 3"), `bash tools/simlab/workshop.sh`, then `./tests/run.sh`. Report with evidence labels; list `/reload` after a scan as the real-client check. Do not commit unless asked.
