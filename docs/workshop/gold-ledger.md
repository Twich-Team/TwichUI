# Gold Ledger (Workshop)

What the player's gold did: how much arrived, how much left, and, only where a completed transaction proves it, where it came from.
Observed movement, **not profit**. No figure on the page is an estimate; an amount is either read from the game or shown as unavailable.

## Parts

| Part | File | Owns |
| --- | --- | --- |
| Recorder | `!!!TwichUI/auction/Ledger.lua` (core, `R.Ledger`) | The journal, day totals, baselines, evidence matching, retention, `TwichUILedgerDB`. Works with the Workshop addon **not loaded**. |
| Evidence: mailbox | `!!!TwichUI/auction/Mail.lua` (`R.MailGold`) | Reports each *matched* mailbox money gain (exact amount) once. Now also listens when only the ledger needs it. |
| Evidence: purchases | `TwichUI_Workshop/auction/Actions.lua` | Reports a completed Auction House purchase (`AUCTION_HOUSE_PURCHASE_COMPLETED` / `COMMODITY_PURCHASE_SUCCEEDED`) with its reviewed total. Nothing else reports. |
| Evidence: merchants | `!!!TwichUI/auction/Vendor.lua` (`R.VendorGold`) | Observes native requests and verified outcomes, then targets the corresponding existing journal entry. Works with Workshop unloaded. |
| Reading side | `TwichUI_Workshop/LedgerQuery.lua` | Pure: totals, daily series, source split, transaction merge, comparison. Cached. |
| Chart | `TwichUI_Workshop/LedgerChart.lua` | Pure geometry plus the pooled-region frame (`UI.GoldFlowChart`). |
| Page | `TwichUI_Workshop/ViewLedger.lua` | The registered **Gold Ledger** page (second navigation group). |

## Recording

* Opt-in boundary: the Workshop being turned on (`R.WorkshopLauncher.Enabled`). Off stops *new* records and keeps the old ones; on again re-baselines (the gap is never turned into income).
* One entry per observed change: the exact difference between two valid `GetMoney()` readings, in signed integer copper. The **first reading of a session is only a baseline** (no entry); an unchanged balance makes none; an unreadable, secret, negative, fractional or non-finite reading is ignored and changes nothing. A reload or login never treats the change since the last session as income or expense.
* Nothing before the world is entered is read (the balance may not be loaded yet). The recorder listens to `PLAYER_MONEY` (and `PLAYER_ENTERING_WORLD`, `PLAYER_LOGOUT` for bookkeeping) **only while recording**; there are no timers and no polling.
* Gold that changed while logged out, or while the Workshop was off, is not recorded, and history is never rebuilt from the current balance. The page says since when it records (UTC).

## Attribution (conservative)

Classification is metadata on the one money entry, attached only by **evidence** with an exact signed amount.

| Source | Evidence | Direction |
| --- | --- | --- |
| Mail collected | `R.MailGold` asked for the take **and** `PLAYER_MONEY` then showed a gain of exactly that amount | in |
| Auction sale | the same, and every message in the gain carries a seller's invoice (`GetInboxInvoiceInfo` = `"seller"`; **unverified in the real client**) | in |
| Auction purchase | a completed purchase through TwichUI's controller, and a loss of exactly the reviewed total | out |
| Vendor Purchase (`vendorBuy`) | one gold-only native request, exact carried item increase and matching observed expenditure | out |
| Vendor Sale (`vendorSell`) | one native bag-use request, exact carried stack decrease and a new matching buyback receipt with the observed payment | in |
| Repairs (`repair`) | player-paid repair-all request, verified full repair cost cleared and matching observed expenditure | out |
| Unclassified | everything else, including uncertain merchant activity, loot, quests, trades, postage and deposits | either |

Evidence waits up to 10 s for its money (and money for its evidence). It attaches to the entry of the same frame, otherwise to the **single** unclassified entry of exactly that amount; two candidates are *ambiguous* and attach nothing. A correlation id attaches at most once. Never evidence: a successful posting, a server-reported sold auction (not yet collected), an open vendor or mailbox, a refused/expired take, a failed or cancelled purchase. Evidence never creates an entry.

V1 did not attribute vendor activity. V2 adds the conservative merchant evidence below. Quest/loot, trades, deposits and fees, crafting costs remain Unclassified. `Fees` and `Crafting Profit` from the mockup are deliberately absent.

## Vendor attribution (V2)

**Money authority remains `Ledger.lua` / `PLAYER_MONEY`.** The observer never reads a balance delta, calls `Observe`, creates a journal entry, or initiates a gameplay action. A hook alone produces no evidence. Once an outcome is verified, `R.Ledger.Evidence` receives the exact signed amount of the already-recorded entry, its stable ID and current character key. An exact target cannot fall back to another equal-amount entry or enter the pending queue. Existing mailbox/Auction House evidence behavior is unchanged.

The observer caches bounded pre-action facts during an actual merchant visit, uses native `hooksecurefunc` post-hooks, then requires exactly one new, still-Unclassified journal entry and a consistent outcome. It coalesces relevant events with a 50 ms timer and expires a request after two seconds, with no polling. Close, world/logout, changed merchant/character, profile/consent refresh, errors and combat interruption invalidate outstanding work. Four context listeners are present while the Ledger records; five additional listeners and one Ledger subscription exist only during a merchant visit. At most one candidate, 512 carried slots, 256 listings and 12 buyback receipts are retained; timers are cancelled on close. Diagnostics scopes/gauges cover this work. No independent database or Workshop load is introduced.

### Source-grounded API behavior

Read-only reference: local `wow-ui-source` **forever**, commit `bebcb6b` (1.60.1 build 70938). Forever is Camelot in the Mainline family; the active merchant/container implementations are Mainline, not Vanilla.

| Native source/API | Observer rule |
| --- | --- |
| `Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua`: `BuyMerchantItem(index[, quantity])`, `C_MerchantFrame.GetItemInfo`, split/bulk purchase handlers | Reuse core `Restock.Listing` for item ID, gold-only price, stack size and eligibility. The price covers `stackCount` items; quantity is an item count in multiples of that size. Omitted quantity means one merchant stack. Require a current offer matching the cached offer, no extended cost, no currency ID and an explicit zero from `GetMerchantItemCostInfo`. Require the exact item increase and exact observed charge; do not assume fractional rounding or discounts beyond the returned quote. |
| Mainline `ContainerFrame.lua`, generated `ContainerDocumentation.lua`: `C_Container.UseContainerItem(bag, slot[, unitToken, bankType, reagentBankOpen])` | Capture the cached item ID/stack before the slot changes; refuse targeted/bank use, locks, repair/spell targeting or unknown identity. Only a matching carried-item decrease **and** a newly appended `GetBuybackItemInfo`/`GetBuybackItemLink` receipt can identify a sale. The buyback price must equal the actual observed gold gain. A disappearance or income alone proves nothing. |
| Mainline `MerchantFrame.xml`: `RepairAllItems()` and `RepairAllItems(true)`; `GetRepairAllCost`/`CanMerchantRepair` | Only the ordinary player-paid call qualifies, with a known positive pre-action cost, that cost cleared afterwards and the corresponding personal gold debit. Guild calls never supply spending evidence. The native single-item workflow uses the repair cursor; no verifiable partial-item quote/signature was established, so partial repairs stay Unclassified. |

**Deliberate refusals:** overlapping requests before settlement (including ambiguous external junk-seller bursts), multiple money movements in one candidate, mixed/unrelated spending, unsupported/changed offers or currencies, unknown prices/items, failed or cancelled requests, buyback purchases, cursor/drag sales, ambiguous full buyback lists, partial/unverified repairs, guild-funded repairs. A single bulk purchase request can identify one combined debit and its actual quantity; overlapping API calls are not split into artificial entries. Sequential requests with separately verified outcomes can each be attributed. EllesmereUI's marker/seller integration is unchanged; none of its internals are hooked or called.

Native event ordering and post-hook visibility still need owner testing. If data changes synchronously before it can be captured, an update is missing/late, or a transaction takes more than two seconds, attribution is refused. This affects descriptions only; the existing recorder still keeps every observed gold movement. Synthetic tests and UI fixtures are **not native V2 acceptance**.

## Saved variable

`TwichUILedgerDB = { version = 1, chars = { ["Name - Realm"] = record } }`, declared in the core `.toc`. A newer version is set aside untouched (`Persist.Hold`) and nothing is recorded to it. Damaged parts are repaired narrowly (dropped entries are counted as `ledger-entry-dropped`).

Record: `name`, `realm`, `since`, `nextId`, `entries` (oldest first), `days`.

* Entry: `id` (stable, never reused), `t` (unix), `a` (signed copper, never 0), optional `k` (source; absent = unclassified), `e` (evidence code), `i` (item id), `q` (quantity), `n` (note, <= 60 bytes, no control or `|`), `x` (correlation id).
* Day (`days[utcDay]`): `i`, `o` (copper in / out), `n` (entries), `ci`, `co` (the same split by source). A day **record** means "the recorder was running that day" (`n = 0`: nothing moved); **no record = outside coverage**, which is not the same as zero.
* Sums saturate at 2^53 - 1 (exact integers).

Retention: 90 UTC days of daily totals (today included); journal entries older than that are dropped with their days; at most **2,000 entries per character** (trimmed in one step once 50 over), the dropped entries' totals stay in their days; at most 100 characters. Compaction is deterministic and runs when a record is first read and when the day changes. Nothing in `TwichUIWorkshopDB` or `TwichUIDB` is touched.

V2 is additive: schema version remains 1; source/evidence definitions and existing optional item/quantity/note fields suffice. No migration, retention change, reset or retrospective reclassification occurs. Existing IDs, amounts and daily totals remain intact. New source splits survive the same cleaning/reload path; future schemas remain held aside. Downgrading to a V1 binary does not understand the new source codes, so use the V2 branch for the reload check.

Days and times are **UTC**, as the Workshop's market charts. (Local-day bucketing would need the zone at record time; not done.)

## The page (mockup mapping)

Header and filters: character (this / all), source, range (7/30/90 D, in the chart header), search. Cards: Net Change, Gold In, Gold Out, Attributed Income, Attributed Spending, Unclassified (the mockup's Revenue/Expenses/Auction Sales/Purchases/Fees are not all supportable). Gold Flow: green bars up, red bars down, antique-gold net line, grid, day labels, per-day hover; legend entries toggle a series. Gold by Source (the mockup's "Profit by Source"). Recent Transactions (Time / Source / Item-Note / Amount, newest first, pooled rows, item icon + tooltip when a real item is known, details on hover). Profit by Profession: an honest placeholder ("Profession profitability isn't available yet."); `LedgerQuery.SetProfessionProvider` is the seam for a later provider (a provider's rows are labelled partial; unknown amounts stay blank).

Character, source and range apply to every panel; search narrows the list only (daily totals are kept by source, not by item). Prior-period text is shown only when every day of the prior window was recorded; percentages only for gold in/out with a non-zero base. Multi-character totals carry a note: gold you moved between your own characters counts in and out.

Vendor sources use the same six cards, filters, item icons and hover details. Gold by Source retains its panel and row styling; it scrolls when all eight signed source rows are present, so totals are never hidden by a five-row limit.

## Verification

* `tests/test_ledger_journal.lua` (recorder, persistence, retention, safety), `tests/test_ledger_attribution.lua` (mailbox and purchase evidence), `tests/test_workshop_ledger.lua` (page, filters, reconciliation, chart, lifecycle, large history). Simulator poses `ledger` and `ledgersmall` in the `workshop` scenario (handler level + screenshot).
* V2: `tests/test_ledger_vendor.lua` drives the real recorder, native-request observer and `Restock.Listing` with independent synthetic outcomes. `./tests/run.sh feature ledger --profile cloud` selects focused tests/core dependencies, syntax, smoke and `ledgervendor`/`ledgervendorsmall`; `bash tools/mutate.sh --group ledger` includes the vendor accounting defects. New simulator poses preserve all old Ledger assertions before adding vendor UI fixtures. The 27 existing Workshop tooltip assertion failures were reproduced identically on pre-Ledger `main` (`fda7d00`) during V1 reconciliation; these remain failed evidence, never an exception converted to PASS.
* Not verified without the real client: `PLAYER_MONEY`/`GetMoney()` timing at login (is the balance valid at `PLAYER_ENTERING_WORLD`?), whether `GetInboxInvoiceInfo` returns the seller invoice before the mail is opened, that the exact commodity quote equals the money that leaves, and `GetTime()` being constant inside a frame (the same-frame rule; the single-candidate rule covers a miss).

## Owner check in game

1. Update the regular addon installation from `feature/ledger-v2-vendor-attribution`, with Workshop enabled.
2. Buy one inexpensive vendor item, then sell one inexpensive bag item (allow each to settle).
3. Optionally perform a small player-paid Repair All.
4. Open Workshop → Gold Ledger and inspect source names, item quantities and amounts.
5. Reload and confirm the classifications persist and no phantom transaction appears.
