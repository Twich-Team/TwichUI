# Gold Ledger (Workshop)

What the player's gold did: how much arrived, how much left, and, only where a completed transaction proves it, where it came from.
Observed movement, **not profit**, except in the separate *Realized Results* view, where a profit appears only when both the collected gold and the cost of exactly the units sold were verified. No figure on the page is an estimate; an amount is either read from the game or shown as unavailable.

## Parts

| Part | File | Owns |
| --- | --- | --- |
| Recorder | `!!!TwichUI/auction/Ledger.lua` (core, `R.Ledger`) | The journal, day totals, baselines, evidence matching, retention, `TwichUILedgerDB`. Works with the Workshop addon **not loaded**. |
| Evidence: mailbox | `!!!TwichUI/auction/Mail.lua` (`R.MailGold`) | Reports each *matched* mailbox money gain (exact amount) once. Now also listens when only the ledger needs it. |
| Evidence: purchases | `TwichUI_Workshop/auction/Actions.lua` | Reports a completed Auction House purchase (`AUCTION_HOUSE_PURCHASE_COMPLETED` / `COMMODITY_PURCHASE_SUCCEEDED`) with its reviewed total. Nothing else reports. |
| Evidence: merchants | `!!!TwichUI/auction/Vendor.lua` (`R.VendorGold`) | Observes native requests and verified outcomes, then targets the corresponding existing journal entry. Works with Workshop unloaded. |
| Cost basis (V4) | `!!!TwichUI/auction/LedgerCost.lua` (`R.LedgerCost`), `LedgerCostWatch.lua` | Lots, realized results and verified crafts, stored inside `TwichUILedgerDB.cost`. A separate interpretation of already-verified activity; never records or changes money. |
| Reading side | `TwichUI_Workshop/LedgerQuery.lua` | Pure: totals, daily series, source split, transaction merge, comparison. Cached. |
| Chart | `TwichUI_Workshop/LedgerChart.lua`, `ChartKit.lua` | Pure geometry and columns plus the pooled-region frame (`UI.GoldFlowChart`); ChartKit holds the strokes, card docking and pointer shared in spirit with the Market chart. |
| Coins | `TwichUI_Workshop/Coins.lua` | `UI.Coins`: exact copper as gold / silver / copper coin artwork. Presentation only. |
| Page | `TwichUI_Workshop/ViewLedger.lua` | The registered **Gold Ledger** page (second navigation group). |

## Recording

* Opt-in boundary: the Workshop being turned on (`R.WorkshopLauncher.Enabled`). Off stops *new* records and keeps the old ones; on again re-baselines (the gap is never turned into income).
* One entry per observed change: the exact difference between two valid `GetMoney()` readings, in signed integer copper. The **first reading of a session is only a baseline** (no entry); an unchanged balance makes none; an unreadable, secret, negative, fractional or non-finite reading is ignored and changes nothing. A reload or login never treats the change since the last session as income or expense.
* Nothing before the world is entered is read (the balance may not be loaded yet). The recorder listens to `PLAYER_MONEY` (and `PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT` for bookkeeping) **only while recording**; there are no timers and no polling.
* Gold that changed while logged out, or while the Workshop was off, is not recorded, and history is never rebuilt from the current balance. The page says since when it records (your local date).

## Attribution (conservative)

Classification is metadata on the one money entry, attached only by **evidence** with an exact signed amount.

| Source | Evidence | Direction |
| --- | --- | --- |
| Mail collected | `R.MailGold` asked for the take **and** `PLAYER_MONEY` then showed a gain of exactly that amount | in |
| Auction sale | the same, and every message in the gain carries a seller's invoice (`GetInboxInvoiceInfo` = `"seller"`; **unverified in the real client**) | in |
| Quest reward (`quest`) | `QUEST_TURNED_IN(questID, xpReward, moneyReward)` with a positive `moneyReward` (`auction/LedgerQuest.lua`), and a gain of exactly that amount | in |
| Auction purchase | a completed purchase through TwichUI's controller, and a loss of exactly the reviewed total | out |
| Vendor Purchase (`vendorBuy`) | one gold-only native request, exact carried item increase and matching observed expenditure | out |
| Vendor Sale (`vendorSell`) | one native bag-use request, exact carried stack decrease and a new matching buyback receipt with the observed payment | in |
| Repairs (`repair`) | player-paid repair-all request, verified full repair cost cleared and matching observed expenditure | out |
| Unclassified | everything else, including uncertain merchant activity, loot, quests, trades, postage and deposits | either |

Evidence waits up to 10 s for its money (and money for its evidence). It attaches to the entry of the same frame, otherwise to the **single** unclassified entry of exactly that amount; two candidates are *ambiguous* and attach nothing. A correlation id attaches at most once. Never evidence: a successful posting, a server-reported sold auction (not yet collected), an open vendor or mailbox, a refused/expired take, a failed or cancelled purchase. Evidence never creates an entry.

V1 did not attribute vendor activity. V2 adds merchant evidence; V3 adds the supported auction evidence below. Quest/loot, trades, unsupported deposits/fees and crafting costs remain Unclassified. Fees deducted before a seller payment are settlement details, not another expense or a seventh summary card. Full crafting profit remains unavailable.

## Vendor attribution (V2)

**Sale batches (EllesmereUI's junk selling and the Sell All Junk button).** A single sale is the rare case: EllesmereUI's Junk Marker sells with one `UseContainerItem` about every 0.08 s, and its other mode and Blizzard's button call `SellAllJunkItems()` (repeated passes). The sale half of the observer therefore works on a **batch**. A request, or a junk-button press, only opens or extends it (it proves nothing). What is attributed comes from outcomes the game reports, matched exactly:

* each **new buyback receipt** (item, quantity, exact payment), found by aligning the buyback list with its previous reading (a full list that rolls its oldest receipts off is aligned; if two alignments fit, e.g. identical stacks, nothing is claimed; a shift of the whole list is never claimed);
* each **new ledger entry equals the sum of the next consecutive receipts** (prices are positive, so the split is unique); money that is not such a sum, or spending, refuses the batch;
* the **carried bag counts fell by exactly the quantity of every receipt so far** and nothing else changed;
* with individual requests, **every receipt was asked for** (item and quantity); the junk button vouches for no item.

An entry covering one receipt keeps its item and quantity and is matched to cost as before; one covering several receipts says "N items sold to a vendor" and is not matched to cost. A batch closes after one quiet second, a settled batch yields at once to a purchase or repair, and an unsettled one is refused after three seconds. A drag or buyback, a UI error, combat, a purchase in the middle, an unaligned list or an unrequested receipt refuse the whole batch. Purchases and repairs keep the single-request rules below.

**What the first real-client report showed.** The right-click sale was refused because the merchant frame passes a bank argument (`UseContainerItem(bag, slot, nil, <active bank type>, false)`) even with no bank open, and EllesmereUI's sweep starts at `MERCHANT_SHOW`, before the merchant frame is shown, which a visible-frame test turned into a silent shutdown of the whole visit. A visit is now the interaction (`MERCHANT_SHOW` to `MERCHANT_CLOSED`), only a unit target or an open bank refuses a use, the post-hooks are installed as soon as recording starts, and a call that reaches no open visit or a lost context is counted (`no-merchant-visit-open`, `merchant-context-lost`). The diagnostics line also shows `visits`, `calls` and `batches`.

**Why a purchase or sale can stay Unclassified, and how to see it.** Vendor attribution is deliberately strict and, until a real-client run, has not been verified natively. Every request the observer does not attribute is counted under a fixed code (no item, name, price or copper), and **/tui diagnostics > Gold Ledger evidence** lists them on a `vendor not attributed:` line, for example `overlapping-requests`, `cursor-or-buyback:PickupContainerItem`, `sell-slot-not-in-snapshot`, `sell-item-locked`, `buy-offer-changed-or-extended-cost`, `no-money-seen`, `several-money-changes`, `no-matching-buyback-receipt`, `receipts-do-not-sum-to-money`, `receipt-without-request`, `bag-count-differs`, `buyback-list-unaligned`, `money-wrong-direction`, `amount-differs-from-price`. Counters never change what is attributed.

The observer caches bounded pre-action facts during an actual merchant visit, uses native `hooksecurefunc` post-hooks, then requires exactly one new, still-Unclassified journal entry and a consistent outcome. It coalesces relevant events with a 50 ms timer and expires a request after two seconds, with no polling. Close, world/logout, changed merchant/character, profile/consent refresh, errors and combat interruption invalidate outstanding work. Four context listeners are present while the Ledger records; five additional listeners and one Ledger subscription exist only during a merchant visit. At most one candidate, 512 carried slots, 256 listings and 12 buyback receipts are retained; timers are cancelled on close. Diagnostics scopes/gauges cover this work. No independent database or Workshop load is introduced.

### Source-grounded API behavior

Read-only reference: local `wow-ui-source` **forever**, commit `bebcb6b` (1.60.1 build 70938). Forever is Camelot in the Mainline family; the active merchant/container implementations are Mainline, not Vanilla.

| Native source/API | Observer rule |
| --- | --- |
| `Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua`: `BuyMerchantItem(index[, quantity])`, `C_MerchantFrame.GetItemInfo`, split/bulk purchase handlers | Reuse core `Restock.Listing` for item ID, gold-only price, stack size and eligibility. The price covers `stackCount` items; quantity is an item count in multiples of that size. Omitted quantity means one merchant stack. Require a current offer matching the cached offer, no extended cost, no currency ID and an explicit zero from `GetMerchantItemCostInfo`. Require the exact item increase and exact observed charge; do not assume fractional rounding or discounts beyond the returned quote. |
| Mainline `ContainerFrame.lua`, generated `ContainerDocumentation.lua`: `C_Container.UseContainerItem(bag, slot[, unitToken, bankType, reagentBankOpen])` | Capture the cached item ID/stack before the slot changes; refuse targeted/bank use, locks, repair/spell targeting or unknown identity. Only a matching carried-item decrease **and** a newly appended `GetBuybackItemInfo`/`GetBuybackItemLink` receipt can identify a sale. The buyback price must equal the actual observed gold gain. A disappearance or income alone proves nothing. |
| Mainline `MerchantFrame.xml`: `RepairAllItems()` and `RepairAllItems(true)`; `GetRepairAllCost`/`CanMerchantRepair` | Only the ordinary player-paid call qualifies, with a known positive pre-action cost, that cost cleared afterwards and the corresponding personal gold debit. Guild calls never supply spending evidence. The native single-item workflow uses the repair cursor; no verifiable partial-item quote/signature was established, so partial repairs stay Unclassified. |

**Deliberate refusals:** overlapping purchase/repair requests before settlement (sale bursts are matched as batches, above), multiple money movements in one candidate, mixed/unrelated spending, unsupported/changed offers or currencies, unknown prices/items, failed or cancelled requests, buyback purchases, cursor/drag sales, ambiguous full buyback lists, partial/unverified repairs, guild-funded repairs. A single bulk purchase request can identify one combined debit and its actual quantity; overlapping API calls are not split into artificial entries. Sequential requests with separately verified outcomes can each be attributed. EllesmereUI's marker/seller integration is unchanged; none of its internals are hooked or called.

Native event ordering and post-hook visibility still need owner testing. If data changes synchronously before it can be captured, an update is missing/late, or a transaction takes more than two seconds, attribution is refused. This affects descriptions only; the existing recorder still keeps every observed gold movement. Synthetic tests and UI fixtures are **not native V2 acceptance**.

## Cost basis and realized results (V4)

**Cash stays the only authority.** `Ledger.lua` (`PLAYER_MONEY` / `GetMoney()`) alone creates cash entries. The cost basis never reads a balance, never creates, edits or reclassifies an entry, and no cash number (cards, Gold Flow, Gold by Source, transaction amounts) depends on it. It runs only when the recorder has *already attached evidence* to an entry (`Lg.OnAttached`, called after the attach) and the observer passed bag facts (`stock`, session-only). A test (`test_ledger_cost.lua`, section I) compares journals and day totals byte for byte with and without the component.

### What becomes a lot (acquisition cost)

| Source | Evidence required | Result |
| --- | --- | --- |
| Vendor purchase | the existing V2 verified outcome (exact price, exact item increase) **and** the carried quantity of that exact identity before the purchase equals the identified lots of it | a lot: identity, quantity, exact gold, journal entry id |
| Auction House purchase | completed TwichUI purchase receipt (exact reviewed total, item, quantity) | a lot **in transit**. It joins the carried stock only when the player takes a **buyer-invoice** mail attachment and the bags then gain exactly that count of that exact identity (`LedgerCostWatch.lua`; one request at a time). The requested quantity is never trusted by itself. |
| Verified craft | below | a lot whose cost is the allocated cost of the consumed materials, or **unknown** |
| Gathering, quest rewards, trades, other mail, bank withdrawals, starting inventory | none | **Unknown cost.** Never zero. No lot. |

Identity is `i<itemID>` plus the supported variant fields (enchant, gems, random suffix, bonus ids, in that order, bonus ids sorted); unique id, level and spec are ignored. An unreadable link yields the plain-id key, never a guess. A bonus-id variant is never pooled with the plain item.

### The identified-stock rule (why a sale may or may not get a cost)

A sale is matched to cost only if the carried quantity of that identity equals the quantity of its identified lots (so every carried unit is a known lot unit) and covers the sale. Otherwise (older stock, loot, a trade, units in the bank or mail) the sold units cannot be told apart, the result is **unavailable**, and the pool's lots are forgotten: their units can no longer be separated from the other stock, and a later sale must not inherit a stale cost. Unknown starting stock mixed with a purchase means that purchase is never identified. No FIFO guess is made across unidentified stock.

Inside a set of genuinely identified lots of one identity the allocation is **FIFO** (oldest lot first). Cost is apportioned in whole copper: the cost of the first *u* of a lot's *q* units is `floor(cost * u / q)`, so the pieces always add up to exactly the lot's cost. Known limitation: stock moved out of and back into the bags without any evidence, in amounts that cancel exactly, is not detectable.

### Realized results

* **Vendor resale** (`vendorSell`): collected = the buyback receipt amount the V2 evidence already matched; cost = the allocated cost of the exact units. One result per sale entry (a repeated evidence is ignored).
* **Auction sale**: kept with collected, gross, fee and returned deposit from the verified seller invoice; **never matched to a lot.** A seller invoice carries an item *name* and count, no item id, no auction id; the posting deposit entries carry an id but nothing links them to the invoice. Names and prices that look alike are not lineage, so these rows read *Cost basis unavailable*. Deposit and fee are therefore not subtracted a second time: collected already includes the returned deposit and excludes the fee.
* A result is `ok` only with a verified cost; `incomplete` when it drew on units whose cost is unknown (crafts with unverified materials); `unknown` otherwise, with a reason (*no verified purchase*, *mixed with other stock*, ...). Only verified profit enters totals.
* A result drawn from several origins is merged by origin (at most six); more than that is *incomplete*.

### Crafts

Only the game's own signals count: `TRADE_SKILL_CRAFT_BEGIN(recipeSpellID)`, `TRADE_SKILL_ITEM_CRAFTED_RESULT(data)` and the bags. A craft is recorded only when the recipe is the player's own learned recipe, its schematic is fixed (every material one basic item at a fixed quantity, one output item), exactly one craft is in flight, the results name only that output and the bags gain exactly the reported quantity, and every material left the bags in exactly the schematic quantity (so nothing was returned and no other movement overlapped). Multi-output crafts, returned resources/ingenuity, quality reagents, interrupted or overlapping crafts and any transfer during the craft are **not verified**: the materials' identified lots are forgotten rather than guessed. The queue's *Crafted one* button and `Progress.lua` are **not** evidence and are unchanged (automatic queue counting stays off).

Materials are taken from identified stock with the same rule, so a bar's cost passes into the armor made from it (ore → bars → armor is counted once, at the sale). Unknown material cost makes the craft and its output lot *incomplete*; the output's sale then has no profit. The craft's profession comes from `GetProfessionInfoByRecipeID` (the parent profession when the game gives one).

### The page

The **Recent Transactions** panel has two views (*Transactions*, *Item Results*); the six cards, Gold Flow, Gold by Source and all filters are unchanged. *Item Results* groups the window's sales by item identity: collected, verified cost, realized result (`+` sage / `-` ember), `*` when only some sales are verified, *Unknown* / *Unavailable* otherwise, with the reason and per-sale detail in the hover. **Profit by Profession** uses `LedgerQuery.SetProfessionProvider`: a profession shows a result only from sales whose units all came from verified crafts of that profession with every cost verified (*N sales verified*); crafts with no such sale read *Insufficient verified data*. Vendor resale of bought goods and gathered goods are never attributed. With no craft data the original *not available yet* state remains.

### Stored data and retention

`TwichUILedgerDB.cost = { v = 1, chars = { [key] = { lots, results, crafts, profs, nextLot, nextResult, nextCraft } } }` (field list in `LedgerCost.lua`). It is created the first time something is verified; existing V1-V3 data are not touched or migrated, and `version` stays 1. A newer `cost.v` is left untouched and never read (cash keeps recording). Corrupt parts are dropped one row at a time (`ledger-cost-dropped`); a result claiming `ok` without a cost is demoted to `incomplete`. Per character: at most **400 open lots** (oldest forgotten first), a lot open longer than **180 days** is forgotten, an Auction House lot not delivered within **45 days** is forgotten, **500 results** and **200 crafts** within the **90-day** window of the journal. A forgotten lot's units become unknown cost; nothing is reconstructed. Characters and realms are separate records. Downgrading to a V3 binary ignores the extra field and keeps cash history.

Diagnostics: scopes `ledger.cost`, `ledger.costquery`; gauges `ledger.cost.lots/results/crafts/transit/events`.

### Not verified in the real client

That Forever fires `TRADE_SKILL_CRAFT_BEGIN` / `TRADE_SKILL_ITEM_CRAFTED_RESULT` with the documented payload and in what order against the bag update; that an Auction House purchase arrives as a mail with a *buyer* invoice (`GetInboxInvoiceInfo`) and `TakeInboxItem` is the call used; the real item links' bonus-id layout; commodity purchase delivery split across several attachments (the cost is kept in transit until a single attachment of the right count arrives). If any of these differ, the result is *unavailable*, never a wrong profit.

## Saved variable

### Auction Accounting V3 capability contract

Source reviewed: Forever `bebcb6b` (1.60.1, build 70938), generated `AuctionHouseDocumentation.lua`,
native Auction House sell/cancellation handlers and `Blizzard_MailFrame/MailFrame.lua` seller-invoice rendering.
V3 is stacked on V2; neither branch has native V2/V3 acceptance yet. Existing transaction capability gates stay unchanged.

| Supported signal | Expected order / required money evidence | Classification / limits |
| --- | --- | --- |
| Existing core and Workshop posting controllers; `CalculateItemDeposit(location,duration,quantity)` / `CalculateCommodityDeposit(itemID,duration,quantity)` | Review/recheck native quote, dispatch owned post, native completion and one new exact debit (either completion/money order) | Auction Deposit. Item quantity >1 additionally requires exact final `AUCTION_MULTISELL_UPDATE(createdCount,totalToCreate)`; partial/multiple debits remain Unclassified. Whole-silver rounding follows the existing native-frame quote convention. |
| Native posting warning | No successful post is established until the owner accepts and the controller re-dispatches | No attribution while warning is pending/rejected; restart money correlation at accepted confirmation. Changed/unavailable quotes refuse attribution. |
| Existing owned-auction cancellation review; `GetCancelCost(auctionID)` / `CanCancelAuction` | Recheck exact ID/status/fee, dispatch, `AUCTION_CANCELED(auctionID)` and one exact new debit | Auction Cancellation Fee. Zero cost creates nothing; missing/wrong completion or changed/stale identity cannot classify. |
| Seller invoice from `GetInboxInvoiceInfo`: type, item name, bid, deposit, consignment, count | Explicit mailbox take and exact collected payment. Native invoice arithmetic is `bid + deposit - consignment` | Auction Sale stays one cash entry. Gross, fee and returned deposit are settlement metadata only when all invoice fields reconcile with that payment. Buyer/temporary invoices are not seller receipts; item IDs are not inferred from names. |
| Several explicit money takes | One actual combined gain; every selected receipt must be uniquely supported | All seller invoices can describe one combined sale entry, with bounded invoice details. Mixed personal/auction mail remains Mail Collected; ambiguous matches remain Unclassified. |
| Sold/expired/cancelled listing notifications or remembered deposits | No independently identified refund payment or standalone refund-kind invoice found in the supported source | No guessed Auction Refund category. Bundled returned deposits remain seller-invoice details; other collected payments keep their existing classification. |

Posting creation events have no request token. Only one owned operation may supply evidence; foreign operations,
overlap, interruption and expired outcomes invalidate correlation. No new native-interface observer or gameplay action is introduced.
Actual native event ordering, quote/charge equality and invoice availability remain deferred owner checks.

### V3 implementation and boundaries

`auction/LedgerAuction.lua` is a small core-owned adapter shared by core **Sell from Bags** and
Workshop's existing action controller. It never calls a transaction API. Each explicit dispatch captures
the current character and next journal ID, item/quantity and native deposit or cancellation quote.
The owning controller supplies its completion proof. Exactly one new debit of the quoted amount is
required, and evidence targets that ID rather than another equal-amount entry. Completion and cash
may arrive in either order; deadlines are checked against the clock as well as cancellable timers.

There is at most one candidate, one settlement callback and one eight-second expiry. Foreign native
transactions, overlap, multiple balance changes, errors, profile/consent changes, combat and leaving the
auctioneer invalidate it. A failed/ambiguous attempt blocks further cash attribution in that visit until
the auctioneer is reopened, because tokenless late posting events cannot safely belong to a new request.
Native warning previews clear correlation without creating expense; accepted confirmation captures a
fresh cursor/quote. Multisell only qualifies after exact final counts and one combined charge; partial
completion and separately charged multisell movements stay Unclassified. Native action ownership guards
are installed once, run only while a candidate exists and never replace protected functions. Accounting
failures are isolated from controller dispatch. No Workshop load, gold polling or history search is added.

**Cancellation attribution is wired to the existing ID/fee review and completion path. Its existing
per-build/native-acceptance capability gates remain unchanged.** V3 does not enable disabled integrated
post/cancel modes. Arbitrary Blizzard/addon posting or cancellation stays Unclassified; no broad native
interface observer was introduced to bypass those protections. Core Sell from Bags deposit attribution
and mailbox settlement are available through their existing workflows.

`Mail.lua` preserves the existing mailbox-money chat summary, including its duplicate-request timing.
It now targets the exact new journal ID (with a bounded deferred offer when the recorder's event handler
runs second). Uniquely supported seller receipts remain Auction Sale; mixed payments remain Mail
Collected. Equal-amount/competing-subset or duplicate requests supply no attribution. Invoice requests
expire safely even if timer delivery is delayed. No mail collection is initiated.

Only a complete native seller breakdown that reconciles to the actual collected payment is retained:
gross = native `bid`, returned deposit = `deposit`, fee = `consignment`, collected = gross + deposit − fee.
Advertised `buyout` and historical prices are not used. Up to eight individually supported invoices may
describe one combined cash entry; larger batches retain the cash/source without a breakdown. Missing or
mismatched values preserve V1 seller-receipt classification but show **Fee unavailable**. Buyer names,
senders, subjects and mail bodies are never stored in the extension. Item names/counts come from the
invoice; no item ID is inferred from a name. Standalone refunds remain unsupported because no distinct
authoritative refund signal was found. Bundled returned deposits are never counted as extra cash.

The six cards, chart, filters, source panel and profession placeholder remain. New sources use existing
rows/icons; the long cancellation label can wrap within its row. Hover details show collected cash,
verified gross/fee/returned deposit and at most three individual invoice summaries, or Fee unavailable.
Native auction IDs are retained on supported deposit/cancellation entries and shown only in their hover.

For one immediate sanitized diagnostic after an optional owner action, open **`/tui diagnostics`**, Refresh,
then copy the **Gold Ledger evidence** section from the report box. It contains session reason counters
and pending/held state only; no timed capture, extra test build, personal names, item/auction/mail IDs,
mail text or copper values. Ordinary performance scopes/gauges are also registered for auction and mail.

`TwichUILedgerDB = { version = 1, chars = { ["Name - Realm"] = record } }`, declared in the core `.toc`. A newer version is set aside untouched (`Persist.Hold`) and nothing is recorded to it. Damaged parts are repaired narrowly (dropped entries are counted as `ledger-entry-dropped`).

Record: `name`, `realm`, `since`, `tz` (1 = local days), `nextId`, `entries` (oldest first), `days`.

* Entry: `id` (stable, never reused), `t` (unix), `a` (signed copper, never 0), optional `k` (source; absent = unclassified), `e` (evidence code), `i` (item id), `q` (quantity), `n` (note, <= 60 bytes, no control or `|`), `x` (correlation id).
* V3 optional entry fields: `u` (validated native auction ID for deposits/cancellation fees), `s` (seller settlement). `s = {v=1,g,f,d,c,invoices={...}}`; each invoice retains only `g,f,d,c,n,q` (gross, fee, returned deposit, actual collected amount, safe item name and optional quantity). At most eight invoices, exact finite integer copper, validated equation and aggregates. Corrupt metadata is dropped narrowly without dropping the cash entry; unknown newer extension versions are retained untouched and not interpreted. No migration/root-version change is needed.
* Optional deposit field (2026-11-20): `r` on an `ahDeposit` entry is the listing duration the poster chose (1 to 3, the client's three durations). Older entries simply lack it; an invalid value is dropped. Workshop's deposit estimates read it (`TwichUI_Workshop/Fees.lua`).
* Day (`days[utcDay]`): `i`, `o` (copper in / out), `n` (entries), `ci`, `co` (the same split by source). A day **record** means "the recorder was running that day" (`n = 0`: nothing moved); **no record = outside coverage**, which is not the same as zero.
* Sums saturate at 2^53 - 1 (exact integers).

Retention: 90 local days of daily totals (today included); journal entries older than that are dropped with their days; at most **2,000 entries per character** (trimmed in one step once 50 over), the dropped entries' totals stay in their days; at most 100 characters. Compaction is deterministic and runs when a record is first read and when the day changes. Nothing in `TwichUIWorkshopDB` or `TwichUIDB` is touched.

V2 is additive: schema version remains 1; source/evidence definitions and existing optional item/quantity/note fields suffice. No migration, retention change, reset or retrospective reclassification occurs. Existing IDs, amounts and daily totals remain intact. New source splits survive the same cleaning/reload path; future schemas remain held aside. Downgrading to a V1 binary does not understand the new source codes, so use the V2 branch for the reload check.

V3 retains root schema 1 and the same retention policy. Old entries, IDs, amounts and source totals are preserved;
new source definitions and versioned metadata are additive. Older V1/V2 binaries do not understand the new
source codes and may strip that attribution while cleaning; avoid downgrading recorded V3 history. The
V3 branch starts from V2 `aa51de8`; its draft PR targets the V2 branch. Once V2 passes native acceptance
and is merged, retarget V3 to `main`, reconcile and reverify against that merged source before review/merge.

Days and times are the player's **local** calendar days and clock. A change is filed under the local day it happened on (`Lg.DayOf(t)`; the offset is read from the client's `date("*t")` / `date("!*t")` at that moment, so a daylight-saving change is followed), a day begins at local midnight (`Lg.DayStart(day)`), and the page's windows, "today", timestamps and day labels use the same two functions. A client that cannot give an offset falls back to UTC days. A day is filed once, when it is recorded: travelling to another zone does not re-file earlier days.

**Move from UTC days (one time, per record).** Records made before this carried no `tz` marker and their `days` were UTC days. On first read each is rebuilt from its journal into local days (`rec.tz = 1`): every entry is counted again into its local day with its source, a recorded UTC day keeps a record on each local day it overlapped (coverage is unchanged), and no entry changes. Where the journal no longer reaches back (its oldest entry is not number 1, because the entry bound or retention trimmed it) the old totals of the UTC days up to and including that entry's day cannot be re-split, so each is carried whole onto the local day of its middle: the only approximation, only for days older than the journal, and totals are never lost (`test_ledger_journal.lua` 8c). A record needs no second move; a client in UTC gets the same numbers as before.

## The page (mockup mapping)

Header and filters: character (this / all), source, range (7/30/90 D, in the chart header; days are local days), search. Cards: Net Change, Gold In, Gold Out, Attributed Income, Attributed Spending, Unclassified (the mockup's Revenue/Expenses/Auction Sales/Purchases/Fees are not all supportable). Gold Flow: green bars up, red bars down, antique-gold net line, grid, day labels, per-day hover; legend entries toggle a series. Gold by Source (the mockup's "Profit by Source"). Recent Transactions (Time / Source / Item-Note / Amount, newest first, pooled rows, item icon + tooltip when a real item is known, details on hover). Profit by Profession: an honest placeholder ("Profession profitability isn't available yet."); `LedgerQuery.SetProfessionProvider` is the seam for a later provider (a provider's rows are labelled partial; unknown amounts stay blank).

Character, source and range apply to every panel; search narrows the list only (daily totals are kept by source, not by item). Prior-period text is shown only when every day of the prior window was recorded; percentages only for gold in/out with a non-zero base. Multi-character totals carry a note: gold you moved between your own characters counts in and out.

Vendor sources use the same six cards, filters, item icons and hover details. Gold by Source retains its panel and row styling; it scrolls when all eight signed source rows are present, so totals are never hidden by a five-row limit.

## Presentation: coins and the Gold Flow chart

*Money.* Every amount the page draws (cards, legend, chart card and axis, Gold by Source, transactions and their hover, Item Results and their hover, profession rows) is exact copper shown as **coin artwork** by `UI.Coins`: `1[gold] 55[silver] 24[copper]`, `-97[silver] 85[copper]`, `16[copper]`. Zero parts are left out, zero is `0[copper]`, gold has thousands separators. The coin texture paths are read once from `C_CurrencyInfo.GetCoinTextureString` (the documented helper; its text is not reused because it cannot group, sign or compact) and fall back to `Interface\MoneyFrame\UI-{Gold,Silver,Copper}Icon`; the deprecated global is never called. Icons are cut to the font size (8-32 px). Where a figure will not fit, the font shrinks a little (never below a stated minimum), then a **compact level** is used (no copper; largest part only; `1.2k` gold) and the exact amount stays on the font string for the hover ("Exact: ..."). `LedgerQuery.Money` is untouched: it is still the pure text form used by queries, descriptions and tests; `Compare`, `AuctionDetails` and `ResultLines` take an optional formatter so tooltips can use the artwork.

*Gold Flow.* A recessed plotting well with a faint warm sheen; muted sage income columns above a stronger zero baseline and rust expense columns below it (each a vertical tone and a lit end, two regions); the net change as an antique-gold line over a bronze support stroke with round `chart-marker` markers (native lines anchored to the markers, or bounded raster runs when the client refuses lines); thin guides; compact coin axis labels. A day outside recording coverage is a faint empty column named "Not recorded" (never zero); a recorded quiet day is a tick on the zero line; the net line is never drawn across an unrecorded day, into or out of a partly recorded column. Scales are exact (a very small amount keeps a 2 px minimum mark, noted as a marker, not as area).

*Inspection.* One transparent button over the plot (hover, drag, release, right-click) with an OnUpdate only while the pointer is inside or a drag is open. Hover shows the column's interval band, a crosshair, the net marker with a halo and one espresso card (day, Gold In / Gold Out / Net Change in coins, changes recorded, "partly recorded" notes) docked beside the chart or, in the expanded view, inside the plot on the side away from the pointer. **Drag** over columns (6 px threshold, release anywhere) zooms to that interval; **right-click** resets; the 7D/30D/90D buttons stay authoritative (a change of range, character or source clears a zoom). A window too long for its width is added into 7-, 14- or 30-day columns from the exact recorded copper of their days; the card says "N days" and "x of N days recorded" and never presents a longer column as one day.

*Expanded view.* The expand icon in the panel header opens an overlay over the Ledger page inside the Workshop window (one more chart object, made on first use, over the same `LedgerQuery.Summary`; no second journal read or listener) with its own range buttons and *Back to Ledger*. It closes when the page is hidden or left.

*Gold by Source.* Two-line rows (name and amount over a full-width bar), the same scrollable list, hover with the exact amount and its share of gold in/out; bars are proportional to the largest source with a minimum visible tick, so a dominant Unclassified source does not hide small ones. Nothing is relabelled.

Region budget (7 days, populated): about 20-30 pooled textures for the plot plus a few font strings; 90 days adds at most two regions per column and is bounded by the plot width. Diagnostics: scope `ledger.chartDraw`, gauge `ledger.chartPool`.

## Verification

* `tests/test_ledger_journal.lua` (recorder, persistence, retention, safety), `tests/test_ledger_attribution.lua` (mailbox and purchase evidence), `tests/test_workshop_ledger.lua` (page, filters, reconciliation, chart, lifecycle, large history). Simulator poses `ledger` and `ledgersmall` in the `workshop` scenario (handler level + screenshot).
* V2: `tests/test_ledger_vendor.lua` drives the real recorder, native-request observer and `Restock.Listing` with independent synthetic outcomes. `./tests/run.sh feature ledger --profile cloud` selects focused tests/core dependencies, syntax, smoke and `ledgervendor`/`ledgervendorsmall`; `bash tools/mutate.sh --group ledger` includes the vendor accounting defects. New simulator poses preserve all old Ledger assertions before adding vendor UI fixtures. The 27 existing Workshop tooltip assertion failures were reproduced identically on pre-Ledger `main` (`fda7d00`) during V1 reconciliation; these remain failed evidence, never an exception converted to PASS.
* V3: `test_ledger_auction.lua` drives the real action controller and shared evidence adapter; core `test_auction_window.lua` checks the legacy posting handoff. `test_ledger_settlement.lua` covers mailbox order, independently delivered invoice/payment facts, double-counting, mixed/ambiguous mail, safe serializer text round trips, old V1/V2 data and future/corrupt metadata. The Ledger group also includes existing AH actions/reads/Owned/Sell/lifecycle and diagnostics regressions. Feature selection runs smoke plus `ledgerauction`/`ledgerauctionsmall`, which preserve all V1/V2 pose checks before adding V3 assertions. Production and CI protections are unchanged; stacked PRs whose base is a feature branch are outside the current main-only automatic workflow filter.
* V3 checkpoint: **unit-tested**, 43 offline modules and syntax for 104 Lua files passed; **mutation-tested**, 41/41 Ledger mutations killed (13 new auction/settlement defects), none invalid/surviving. Runner regression: 17 cases; simulator workflow regression: 12 cases, passed. An earlier duplicate-take chat timing regression was corrected while preserving its original assertion. **Simulator-tested**, cloud smoke passed; normal/narrow auction poses each passed 533 assertions including all 30 Ledger checks, while retaining the 27 identical baseline tooltip failures. The complete feature profile remains **FAIL**. Screenshots were reviewed for structure only. No native V3 acceptance is claimed; no full/release certification campaign was run.
* V4: `tests/test_ledger_cost.lua` (lots, resale, partial/fractional, FIFO lots, unknown/mixed stock, variants, deliveries, crafts, subcrafts, persistence, retention, timing), the page and profession cases in `tests/test_workshop_ledger.lua`; 17 added mutations (`--group ledger`: 58/58 killed).
* Not verified without the real client: `PLAYER_MONEY`/`GetMoney()` timing at login (is the balance valid at `PLAYER_ENTERING_WORLD`?), whether `GetInboxInvoiceInfo` returns the seller invoice before the mail is opened, that the exact commodity quote equals the money that leaves, and `GetTime()` being constant inside a frame (the same-frame rule; the single-candidate rule covers a miss).

## Owner check in game

Deferred until the owner is available; all real-game actions below are optional and performed by the owner.

1. Update the regular installation from the V3 branch, with Workshop enabled; buy and sell one inexpensive vendor item.
2. If needed, perform a small player-paid Repair All.
3. Make one low-value post through existing Sell from Bags (or an already-permitted TwichUI posting mode).
4. Cancel only if safely possible through an already-permitted controller; ordinary native cancellations may remain Unclassified.
5. Collect a genuine auction payment through normal mailbox use when one is available; do not manufacture a sale to test.
6. Inspect Workshop → Gold Ledger: exact totals, source/item descriptions and available invoice hover details.
7. Reload and confirm history/classifications/details persist. If something remains Unclassified, copy the immediate sanitized diagnostic above.

### Owner check for V4 (short)

1. Update the regular installation from this branch; confirm the existing Ledger history, cards and transactions are unchanged.
2. Pick a vendor item you hold **none** of; buy a few, then sell the same stack back. Open Gold Ledger, switch the lower-left panel to **Item Results**: the item shows its collected gold, verified cost and a result.
3. Buy the same item while already holding some: the later sale must read *Unavailable* (mixed stock), not a profit.
4. If you craft a recipe whose materials you bought from a vendor, sell the product to a vendor: the profession panel shows the result; a craft from materials you did not buy shows *Insufficient verified data*.
5. Reload; the results persist. Native V2/V3 acceptance remains a separate open item.

## V5: Open All and seller payments

**Reported:** after collecting many auction payments with Open All, only a couple of entries were Auction Sale.

**Root cause (reproduced, `tests/test_ledger_openall.lua`; V4 output kept in `tests/fixtures/ledger_openall/v4-baseline.txt`).**
Blizzard's Open All (classic-era `OpenAllMailMixin`) takes one message at a time, at least 0.15 s apart, waiting while
`C_Mail.IsCommandPending()`, and restarts at position 1 after the inbox count changes. A seller's mail with nothing else is deleted once
paid, so every take is `TakeInboxMoney(1)`. When a payment's `PLAYER_MONEY` arrived after the next take, V4 took the second call on
position 1 for a duplicate of the first, marked both ambiguous, then marked **every** waiting request ambiguous. With money after the
next take V4 recognised 0 of 12 sales; with jittered latency 2 of 12; with money first, 12 of 12.

**Fix (`auction/Mail.lua`).**
* In-flight positions are forgotten at each `MAIL_INBOX_UPDATE`; a repeat needs the same position, header and amount with no update
  between, and it is then a *spare* (never matched, only expires).
* No ambiguity spreads to other requests. A gain is matched against every set of waiting requests that adds up to it (oldest 12,
  at most 16 explanations; more and nothing is claimed). The ledger is told only what all explanations agree on: Auction Sale only if
  every explanation is seller mail; item name and invoice details only if they are identical in all. Otherwise Mail collected. Requests
  of an explanation that was not taken keep no item/invoice details later, and become plain mail if the explanations differed in kind.
* Expiry waits while a mail command is pending, a second at a time, never past 15 s.
* **Unread mail.** Blizzard's mail frame reads `GetInboxText` (its `isInvoice`) before `GetInboxInvoiceInfo`; an unopened message may
  give no invoice. Without one, the Auction House's own sold-auction mail is still recognised: the client's `AUCTION_SOLD_MAIL_SUBJECT`
  on a message that cannot be answered (`canReply == false`), not from a GM, not returned, with no attachment. It is an Auction Sale with
  evidence `mailauction`; fee and deposit are unavailable, never guessed. An invoice of another type is never overruled by a subject.
  A player's letter titled the same way can be answered, so it stays Mail collected. TwichUI never opens or marks a message read.
* Mixed batches keep the combined cash entry as Mail collected; several seller invoices in one change stay one Auction Sale entry with
  each invoice in its settlement.

**Diagnostics.** `/tui diagnostics` → Gold Ledger evidence → `mail:` shows requests, verified invoices, sold-auction mails, combined
payments and exact journal matches; `mail reasons:` gives fixed codes (`invoice-missing`, `sold-mail`, `plain-mail`, `duplicate`,
`ambiguous`, `equal-alternatives`, `mixed`, `expired`, `unmatched-gain`, `too-many-ways`, `no-target`, `deferred-full`, `ledger-*`).
No names, subjects, senders, items or copper values.

**Unverified in the real client:** that Forever's Open All and its server behave like the classic-era source, whether
`GetInboxInvoiceInfo` answers for an unread message, and that `AUCTION_SOLD_MAIL_SUBJECT` and `canReply` read as modelled.

## V5: auction-to-item lineage

**Capability matrix** (Forever API names as used by the existing controllers; native behaviour unverified without the client):

| Stage | Available evidence | Can identity be proven? |
|---|---|---|
| Item in bags | `C_Container.GetContainerItemInfo`: item id, stack count, hyperlink → `LedgerCost.Key` (id plus enchant/gems/suffix/bonus ids) | **Yes**: exact identity and count |
| Auction posted (TwichUI Sell) | The reviewed draft: bag `ItemLocation`, link, quantity, unit price, deposit, duration; `AUCTION_HOUSE_AUCTION_CREATED(auctionID)` (one unit or a commodity), `AUCTION_MULTISELL_UPDATE(n, n)` (multi-post, ids optional) | **Yes**: identity, quantity, price, deposit and the native auction id(s) the game created |
| Auction sold | `C_AuctionHouse.GetOwnedAuctions()`: `auctionID`, `status` (1 = sold), quantity, prices; `AUCTION_CANCELED(auctionID)` | **Yes, by auction id**, only while the Auction House is open and its list is read |
| Sale mail received | `GetInboxInvoiceInfo`: type, item **name**, buyer, bid, buyout, deposit, consignment, count. No auction id, no item id | **No**. Identity is lost here |
| Gold collected | Ledger cash entry (exact `PLAYER_MONEY` change) with seller settlement | Already supported (V1–V5) |

**Where identity is lost:** the seller's mail. Nothing in it names the auction or the exact item, and a name, a count and a price that
match a posting are a candidate, never a proof. Another posting of the same item can hold the same tuple: one made outside TwichUI or before
it ran, one whose mail is still waiting, or one sold while this posting's mail is delayed. So V5 does **not** tie a collected sale to a posting or a
cost lot. Its Item Result keeps the confirmed sale, collected gold, verified fee and returned deposit, item name and count, and
**Cost basis unavailable** (`w = "auctionid"`).

**What V5 records (posting provenance, `LedgerCost.lua`, `posts` in the cost component).** A TwichUI posting is kept only when the game
created it. Kept: identity key, item id, name from the link, quantity, unit price, deposit, duration, native auction id(s), and the cost of
the posted units. That cost is taken out of the identified stock under the existing rule: every carried unit of that identity must be an
identified lot unit, and the bags must have lost exactly the posted units. Otherwise the cost is `mixed`/`missing`/`short`/`nostock` and
the pool is forgotten, or `nolot` for stock with no verified acquisition, or `unknown` for an identified lot of unknown cost. This also
keeps the pool equal to the carried units after a posting, where V4 would later have found a mismatch and forgotten the lots. State
changes only by the posting's own native id: `sold` from the owned list, `cancelled` on `AUCTION_CANCELED`, `ended` when a **complete**
owned list no longer has it. Returned (cancelled or expired) units come back by mail as unknown-cost stock; the reserved cost is never moved back to a lot.
Bounded: 200 postings per character, 35 days (an auction lasts two days and its mail thirty). Intent, a failed post, a dismissed
review or a repeated creation event keep nothing. The list is optional inside cost component version 1: older builds leave it untouched.

**Realized profit.** Unchanged: verified vendor sales of identified (bought or crafted) stock. No Auction House sale produces realized profit
in V5, because the link between its payment and its posting cannot be proven from native evidence. If Forever exposes an auction id on the
seller invoice (or on the sold-auction mail), the provenance above is the half of the chain that is already in place.

## V5: combined seller payments and the page

* One Open All change that paid several seller mails stays **one** cash entry. With every invoice it carries the existing settlement
  (gross, fee, returned deposit, each invoice). Without full invoices (sold-auction mails), each mail's own collected amount and item
  are passed to the cost basis as session-only components (`parts`, never saved on the cash entry, at most eight, summing exactly to the
  payment, none from a request whose item could be another payment's). Each sale is then an Item Result of its own (two sales of the
  same item are two results; V4 kept only the first of the same name). The transaction details list them, with any unexplained remainder
  named **Unidentified**, never spread.
* Item Results for an auction sale add, as facts beside it, the player's own TwichUI postings of that item in the period: how many, how
  many were seen sold, and the verified cost of their units. They are **not matched** to the payment: no profit, status or total changes.

## V5 verification and owner check

* `tests/test_ledger_openall.lua` (Open All simulation, components, diagnostics), `tests/test_ledger_lineage.lua` (posting provenance
  through the real action controller), additions to `test_ledger_settlement.lua` and `test_workshop_ledger.lua`. Mutations: `bash
  tools/mutate.sh --group ledger` (95, including 14 new Open All and lineage defects). **Unit-tested only**; not simulator-tested
  (no simulator in the cloud environment), not real-client-tested.
* Owner check (normal play, no special build):
  1. Install the regular build from the V5 branch.
  2. Collect several genuine auction-sale payments with Open All.
  3. Workshop → Gold Ledger: they are Auction Sale; hover one for its invoice details or its sold-auction mails.
  4. Item Results: one row per item sold; any TwichUI postings of it are listed beside it, not as profit.
  5. `/reload`: entries and results are unchanged.
  6. If any payment is not an Auction Sale, open `/tui diagnostics` and copy the **Gold Ledger evidence** section (counters only).

### V5 follow-up on current main (2026-11-21)

Base `725519e` already contains V5 from PR #81 (`700f18d`); the owner request's
V4 baseline is historical. Reused its posting/cost architecture and preserved the
original V4 failure receipt. New current-main failure receipt:
`tests/fixtures/ledger_openall/v5-search-window-baseline.txt`.

Checkpoint A reproduces two further defects: a complete 13-message payment could
not be found in the 12-request subset window; a personal payment outside that
window could be ignored and falsely allow Auction Sale attribution. Positive
amounts make a gain equal to **all** nonduplicate pending requests uniquely
identifiable, so that case now uses an O(50) complete-batch path. Otherwise only
amounts no larger than the gain enter the bounded subset search. An incomplete
search cannot authorize classification, and potentially consumed requests lose
kind/item authority for later payments. No queue, timer or persisted-detail limits
are increased. Diagnostics adds `search-limit`, `detail-limit` (classification may
succeed although the eight-invoice breakdown cannot fit), and `no-request`.

Unit-tested checkpoint A: development Ledger 25 modules pass (8.55 s); Ledger
mutation campaign kills all 98 mutations, including three new search defects
(46.7 s). One cash entry per observed gain and the mailbox summary remain covered.
This is not confirmation of the owner's actual native event sequence.

Checkpoint B rechecked the installed Forever reference tree at
`bebcb6bf309cf41b41bd74f8ca651e6a105b2676`: `Blizzard_MailFrame/MailFrame.lua`
OpenAllMailMixin waits for command completion and restarts on count changes; its
invoice consumer reads through count/commerce flag, not an auction or item ID.
`Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua` declares a
non-nil auction ID on auction-created events and native IDs on owned auctions.
A missing creation ID previously confirmed a Workshop commodity posting and
consumed cost units; it is now ignored until a valid confirmation arrives.
Lineage/action regressions pass; the targeted missing-ID mutation is killed.
No third-party Open All source was installed in the workspace. Read-only follow-up
inspected [Postal Community Edition OpenAll](https://github.com/paradosi/postal-community-edition/blob/f2a182149146bf4077946629bd9ad745c7ceaacd/Modules/OpenAll.lua)
(commit `f2a182149146bf4077946629bd9ad745c7ceaacd`): it traverses backwards,
resets when first-mail days-left changes, waits for inventory/money progress, and
uses TakeInboxMoney/TakeInboxItem. Its configurable delays differ from Blizzard;
no assumption is made that the owner used this addon, and no third-party code is
copied or executed. Core Sell from Bags still has cash/deposit
attribution, but no new cost posting observer is installed there: its controller
would need the same competing-operation provenance guarantees as Workshop before
cost can safely be reserved. Existing Workshop posting provenance is reused.
No seller-name/price heuristic can close the native invoice identity gap, so no
auction realized profit or profession profit is invented in checkpoint C.


Checkpoint C / D adds securely reconciled seller components to **mixed** mail.
The parent cash entry stays Mail collected; validated session-only `parts` sum to
the entire cash amount, mark seller portions explicitly, strip personal-mail
names and retain each seller's reconciled invoice. The existing cost-basis Item
Results store only the seller amounts and existing fee/deposit fields; unknown
portions appear as **Unidentified** in transaction details. Unknown cost remains
unknown; no lot is consumed, no realized auction/profession profit is created,
and no fee or returned deposit is added/subtracted again. Components are capped
at eight; no journal schema, cost component version or SavedVariables name changes.
Old Unclassified records are not retrospectively reclassified.

A second independent regression reverses collector/recorder event order and
pays 20 requests before zero-delay callbacks run: the old deferred buffer retains
only eight exact targets (receipt `v5-deferred-baseline.txt`). That buffer now holds
one inbox-sized burst (50), below the recorder's 64 recent-entry slots. Both 20
and 50 events settle once; the queue and component caps stay 50 and eight, and
the 4-second / command-pending / 15-second deadline policy is unchanged. Snapshot
caches still have no stable native message ID. A gain before any hook, vanished
headers/invoices, duplicate-looking messages, overflow, expired/ambiguous evidence
remain unavailable rather than guessed; `no-request`/`search-limit`/`expired` and
other sanitized counters explain the refusal.

Performance: only one bounded O(50) pass is added before the existing at-most
12-candidate subset search; no polling, journal scan, listener, Workshop load or
background service is added. Deferred memory is O(50), session components O(8),
and persisted results retain their existing 500-row limit. This is a structural
bound, not a measured native frame-time or byte-allocation claim.

Final verification: all 48 feature-selected offline modules and syntax pass;
smoke passes. **The feature profile FAILS** on the four selected Workshop poses,
each with 40 scenario failures (first: unchanged Worth tooltip lacks the expected
“Workshop: Not enough data” line). Existing docs already record tooltip-scenario
failures, but the exact 40-failure set was not rerun on main; do not treat it as a
proved identical baseline or a passing simulator gate. No assertions were removed
or weakened, and no unrelated simulator/tooltip fix was attempted. The retained
verification receipt records this failed verdict. The Ledger mutation campaign
kills 102/102 applied mutants (47.9 s), including complete-batch, incomplete-search,
eligible-window, missing posting ID, mixed-component kind/fees and burst deferral.
No native acceptance, screenshot visual acceptance or full/release certification
is claimed.

Later owner check: install the ordinary branch build; use Open All on genuine
seller payments; inspect Auction Sale / mixed Mail collected details and Item
Results; reload and confirm persistence. Auction cost basis must remain unavailable
unless an authoritative receipt-to-posting identifier becomes available. If a
classification is missing, copy `/tui diagnostics` → Gold Ledger evidence; no
special build, payload log or engineering commands are needed.


[Retained final verification](../evidence/ledger-v5-followup/verification.json) and
[simulator failure summaries](../evidence/ledger-v5-followup/simulator-failures.txt)
keep the failed feature verdict explicit. Final checkpoint D changes after that
frozen run are documentation/comments only; executable behavior is unchanged.
Rollback is an ordinary revert of these follow-up commits: no migration is needed,
existing cash/history/results remain readable, and restored older code simply
stops collecting the new mixed-payment detail on future payments.
