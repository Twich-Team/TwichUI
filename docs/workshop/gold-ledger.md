# Gold Ledger (Workshop, V1)

What the player's gold did: how much arrived, how much left, and, only where a completed transaction proves it, where it came from.
Observed movement, **not profit**. No figure on the page is an estimate; an amount is either read from the game or shown as unavailable.

## Parts

| Part | File | Owns |
| --- | --- | --- |
| Recorder | `!!!TwichUI/auction/Ledger.lua` (core, `R.Ledger`) | The journal, day totals, baselines, evidence matching, retention, `TwichUILedgerDB`. Works with the Workshop addon **not loaded**. |
| Evidence: mailbox | `!!!TwichUI/auction/Mail.lua` (`R.MailGold`) | Reports each *matched* mailbox money gain (exact amount) once. Now also listens when only the ledger needs it. |
| Evidence: purchases | `TwichUI_Workshop/auction/Actions.lua` | Reports a completed Auction House purchase (`AUCTION_HOUSE_PURCHASE_COMPLETED` / `COMMODITY_PURCHASE_SUCCEEDED`) with its reviewed total. Nothing else reports. |
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
| Unclassified | everything else: loot, quests, vendors, repairs, trades, postage, deposits, other players' gold... | either |

Evidence waits up to 10 s for its money (and money for its evidence). It attaches to the entry of the same frame, otherwise to the **single** unclassified entry of exactly that amount; two candidates are *ambiguous* and attach nothing. A correlation id attaches at most once. Never evidence: a successful posting, a server-reported sold auction (not yet collected), an open vendor or mailbox, a refused/expired take, a failed or cancelled purchase. Evidence never creates an entry.

Not attributed in V1 (stay Unclassified): vendor sales and purchases, repairs, quest/loot, trades, deposits and fees, crafting costs. `Fees` and `Crafting Profit` from the mockup are deliberately absent.

## Saved variable

`TwichUILedgerDB = { version = 1, chars = { ["Name - Realm"] = record } }`, declared in the core `.toc`. A newer version is set aside untouched (`Persist.Hold`) and nothing is recorded to it. Damaged parts are repaired narrowly (dropped entries are counted as `ledger-entry-dropped`).

Record: `name`, `realm`, `since`, `nextId`, `entries` (oldest first), `days`.

* Entry: `id` (stable, never reused), `t` (unix), `a` (signed copper, never 0), optional `k` (source; absent = unclassified), `e` (evidence code), `i` (item id), `q` (quantity), `n` (note, <= 60 bytes, no control or `|`), `x` (correlation id).
* Day (`days[utcDay]`): `i`, `o` (copper in / out), `n` (entries), `ci`, `co` (the same split by source). A day **record** means "the recorder was running that day" (`n = 0`: nothing moved); **no record = outside coverage**, which is not the same as zero.
* Sums saturate at 2^53 - 1 (exact integers).

Retention: 90 UTC days of daily totals (today included); journal entries older than that are dropped with their days; at most **2,000 entries per character** (trimmed in one step once 50 over), the dropped entries' totals stay in their days; at most 100 characters. Compaction is deterministic and runs when a record is first read and when the day changes. Nothing in `TwichUIWorkshopDB` or `TwichUIDB` is touched.

Days and times are **UTC**, as the Workshop's market charts. (Local-day bucketing would need the zone at record time; not done.)

## The page (mockup mapping)

Header and filters: character (this / all), source, range (7/30/90 D, in the chart header), search. Cards: Net Change, Gold In, Gold Out, Attributed Income, Attributed Spending, Unclassified (the mockup's Revenue/Expenses/Auction Sales/Purchases/Fees are not all supportable). Gold Flow: green bars up, red bars down, antique-gold net line, grid, day labels, per-day hover; legend entries toggle a series. Gold by Source (the mockup's "Profit by Source"). Recent Transactions (Time / Source / Item-Note / Amount, newest first, pooled rows, item icon + tooltip when a real item is known, details on hover). Profit by Profession: an honest placeholder ("Profession profitability isn't available yet."); `LedgerQuery.SetProfessionProvider` is the seam for a later provider (a provider's rows are labelled partial; unknown amounts stay blank).

Character, source and range apply to every panel; search narrows the list only (daily totals are kept by source, not by item). Prior-period text is shown only when every day of the prior window was recorded; percentages only for gold in/out with a non-zero base. Multi-character totals carry a note: gold you moved between your own characters counts in and out.

## Verification

* `tests/test_ledger_journal.lua` (recorder, persistence, retention, safety), `tests/test_ledger_attribution.lua` (mailbox and purchase evidence), `tests/test_workshop_ledger.lua` (page, filters, reconciliation, chart, lifecycle, large history). Simulator poses `ledger` and `ledgersmall` in the `workshop` scenario (handler level + screenshot).
* Not verified without the real client: `PLAYER_MONEY`/`GetMoney()` timing at login (is the balance valid at `PLAYER_ENTERING_WORLD`?), whether `GetInboxInvoiceInfo` returns the seller invoice before the mail is opened, that the exact commodity quote equals the money that leaves, and `GetTime()` being constant inside a frame (the same-frame rule; the single-candidate rule covers a miss).

## Owner check in game

1. Update the addon from the branch, turn Workshop on, reload.
2. `/tui workshop` > **Gold Ledger**. It says when recording started and shows nothing for earlier days.
3. Gain or spend a little gold (sell a grey item, buy a drink). The transaction and the chart bar appear; the card figures move.
4. `/reload`: the history is still there and no phantom entry appeared for the reload.
