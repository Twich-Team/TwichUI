# Mage: sell ordinary food and drink

For anyone changing the feature. Code: `modules/MageSell.lua` (classifier, never-sell list, the run),
`modules/MageSellWindow.lua` (`/tui sell`, Options > Mage > Open), `diag/MageSell.lua`, the options in `Settings.lua`
(Mage page), `modules.mageSell*` in `Core.lua`. Tests: `tests/test_mage_sell.lua`. **Nothing here has been tried in the
game.** Selling is destructive, so read "What is not verified" before releasing.

## What it does, and what it never does

- Mages only, off by default (`modules.mageSell`). Other Mage features don't turn it on. On another class nothing is
  registered.
- Dry run (`modules.mageSellDryRun`) is on by default: opening a merchant says once what would be sold and sells
  nothing. The player turns it off in the Mage options.
- Sells plain food and drink from the carried bags when a merchant opens (one run per visit, 0.3 s after
  `MERCHANT_SHOW`), through the same classifier the preview uses.
- Never: destroys or discards, buys, touches the bank, mail or anything but the carried bags, uses the cursor, splits
  stacks, sells in combat, sends chat, or changes what the Food and Drink buttons choose.
- One chat line per run, local (`R.Print`). Nothing is said when there was nothing to do. A dry run with nothing to sell
  is silent too.

Switches (all in `TwichUIDB.modules`, read strictly: only an explicit `true` is on; dry run is on unless it is
explicitly `false`): `mageSell` (off), `mageSellFood` (on), `mageSellDrink` (on), `mageSellDryRun` (on). A combined
food-and-drink item needs both kinds on.

## Classification

An item is sold only when **all** of these hold (codes are what `/tui diagnostics` counts and the window prints):

| Check | Code when it fails |
|---|---|
| on the player's never-sell list | `excluded` |
| not a known conjured ID, not conjured by its tooltip | `conjured`, `conjured-check-unavailable` |
| the game files it under Food & Drink, its use-spell is the game's plain Food or Drink spell, and the spell text is only the restore sentence (`FoodDrink.Inspect`, the Food and Drink buttons' own reading) | `not-plain-food-or-drink`, `no-use-spell`, `item-data-pending`, `spell-text-pending` |
| quality Poor or Common | `special-quality` |
| a positive vendor price, at most 1 gold each | `no-sell-price`, `high-value` |
| not a quest item (the slot's quest info, and the tooltip's own "Quest Item" / "begins a quest" text) | `quest-item`, `quest-check-unavailable` |
| its kind is switched on | `category-off` |
| not locked, not bound, not `hasNoValue`, count at least 1 | `locked`, `bound`, `no-sell-price`, `empty` |

Anything not food and drink (potions, elixirs, flasks, reagents, cooking materials) is never looked at further and is
never listed. Buff food, feasts and special meals fail the plain-spell check and are kept: there is no option to sell
them. Missing item data, an unreadable spell text, spell names or words for health and mana that haven't loaded and
an unreadable tooltip all keep the item; nothing "unknown" is sold. Names are never used to classify.

The verdict on the item itself is remembered by item ID (at most 128, cleared when the feature turns off or the never-sell list changes; the
player's switches are applied after it, never remembered); only final answers are kept, never "still loading".

## Conjured items

There is no conjured flag in the Forever UI source or API documentation (searched: `ITEM_CONJURED`, "conjured",
`IsConjured`; the only hit is the Auction House error text). Protection is therefore layered, and each layer can only
*keep* an item:

1. **Item IDs**: `FoodDrink.CONJURED` (the Classic-era ranks 1 to 6, not read from this client) and
   `MageSell.CONJURED_EXTRA` (rank 7 water 8079 and food 22895, and Mountain Spring Water 231778; from Water Dispenser's
   Forever data for build 1.60.1.70291, whose notes call 231778 unconfirmed). A wrong entry only keeps an item.
2. **Bound flag**: Water Dispenser's notes say conjured items report bound on this client. Bound items are kept.
3. **Sell price**: Classic-era conjured items have none. No price means kept.
4. **Tooltip text**: the line equal to the game's own `ITEM_CONJURED` ("Conjured Item" in English) on the exact bag
   slot, read through `C_TooltipInfo.GetBagItem` (the call `/tui probe` already uses). Compared with the client's
   global, so it holds in any language. If the client doesn't define `ITEM_CONJURED`, or the tooltip can't be read,
   the item is kept (`conjured-check-unavailable`): in that case **nothing is sold**, and diagnostics says why.

An unfamiliar new rank is kept when any layer catches it. It would be sold only if it were unbound, priced, Common,
plain food or drink, **and** its tooltip said nothing: no layer can see that case. Maintenance: when the client
adds a rank, add its item to `CONJURED_EXTRA` (and `FoodDrink.CONJURED` / `Refreshments.ITEMS` if the buttons should
know it). `/tui probe` prints an item's ID.

## Quest items

Kept when the slot's `C_Container.GetContainerItemQuestInfo` says quest item or gives a quest ID, or when the tooltip
carries `ITEM_BIND_QUEST` / `ITEM_STARTS_QUEST`. Not detectable: an ordinary item a quest asks for that the game
doesn't flag (for example "bring me 5 Tough Hunks of Bread"). The never-sell list is the answer to those.

## The never-sell list

`TwichUIDB.ui.mageSell.exclude = { [itemID] = true }`, account-wide, IDs only, at most 200. Added in the window by
dropping an item from the bags on the add area (the item is put back with `ClearCursor`), by pasting a link or ID, or
with Never sell beside any listed row; removed with Remove. A damaged value is never read as a list and is rebuilt on
the next add. Applies to every stack of that item and to any item, food or not. It is not shared (setups share other
addons' data, never `TwichUIDB`).

## The run

`MS.Begin` looks at the bags once (`MS.Scan`), keeps the first `MS.Limit()` stacks in bag order, and sells them one at
a time:

1. `Valid` (feature on, Mage, same visit, merchant open and Blizzard's window shown, not in combat, dry run not turned
   on mid-run, same generation).
2. The slot is judged again with the same classifier: the same item ID and the same count, still eligible. Anything
   else is skipped and counted as changed; the old list is never trusted.
3. `C_Container.UseContainerItem(bag, slot)` under `pcall`, with `BAG_UPDATE_DELAYED` and `ADDON_ACTION_BLOCKED`
   registered for the run only.
4. The sale is **counted only when the slot shows it**: empty, another item, or a smaller stack. A change that never
   comes ends the run after 2 s (`unconfirmed`): nothing more is tried and the summary says the game didn't show it.
   A block from the game (`ADDON_ACTION_BLOCKED` for TwichUI) ends it and stops automatic runs until reload; the
   Sell now button may still be tried.

A run is dropped, never resumed: merchant closed, `MERCHANT_SHOW` for another merchant, combat, loading screen, the
feature or any of its options changed (`MS.Refresh`, which the options call). Pending timers carry a generation and do
nothing when it is old. Nothing is saved, and there is no always-running listener: bag events are heard only while a
run waits for a sale.

### Buyback

The Forever UI shows `BUYBACK_ITEMS_PER_PAGE` = 12 buyback slots in both its Vanilla and Mainline merchant files, one
per stack sold, and `GetNumBuybackItems` / `GetBuybackItemInfo` exist there. A run sells at most that number less 2
(10), so its own first sales are still on the Buyback tab at its end. This does **not** protect earlier sales
by hand or by another addon: the list is shared, oldest out first. The summary says so and doesn't promise any sale
can be undone. If more are eligible the summary says how many; nothing starts a second batch by itself. Sell now
(window, at an open merchant, Dry run off) is the deliberate way to continue; its tooltip says older buyback entries
can be pushed out.

### Other auto-vendor features

TwichUI has none (the Auction House tab lists items; it doesn't sell to merchants). Another addon that sells junk when a
merchant opens works on grey items, which this never touches; if it sells a stack first, the slot has changed and is
skipped. Both use the one buyback list.

## Preview and window

`MS.Scan(false)` is the preview: the same function the run calls, reading only. The window (`/tui sell`, hidden from the
help list like `saved`; Options > Mage) lists what would be sold (grouped by item, with quantity, why it is ordinary,
and value from sell prices), what is kept and why (only Food & Drink items; never a dump of the bags), and the
never-sell list. While open it listens to bag, item-data, merchant and combat events and redraws once per burst; closed,
it listens to nothing. Drawn with the Chronicle palette. Sell now is enabled only at an open merchant, out of
combat, with the feature on and Dry run off.

## Saved and not saved

- Saved: the four `modules.mageSell*` switches and `ui.mageSell.exclude`. `Persist.lua` checks `ui.mageSell` is a table.
- Not saved: the run, the queue, bag places, the verdict cache, counts, the last result.

## Diagnostics

`/tui diagnostics` > "Mage: sell ordinary food and drink": switches and dry run, listening, merchant state, run
progress, limit, never-sell count, which conjured checks this client supports (tooltip API, `ITEM_CONJURED` defined,
quest API), session counts by stop reason, the last run, and a read-only look at the bags as counts by reason code. No
names, IDs of items or bag places. Status "waiting / conjured-check-unavailable" means nothing can be sold.
Life note: `cancelled-stale-mage-sell`.

## What is not verified

All of it, in the game. Specifically:

- That a non-secure `C_Container.UseContainerItem` sells at an open merchant, outside combat and without a hardware
  event. The UI source doesn't say; the code stops and reports if the game blocks it.
- That `ITEM_CONJURED` is defined by the client and matches the tooltip line, that conjured items report bound and have
  no sell price on Forever, and that `C_TooltipInfo.GetBagItem` lines carry `leftText` for bag items (the probe uses it).
- That `BAG_UPDATE_DELAYED` follows a sale, and that the slot has changed by then. If not, the run ends `unconfirmed`
  after one sale.
- That the buyback list holds 12 on Forever (the UI source says so).
- The 1 gold "high value" cap is a guess, in `HIGH_VALUE`.

## Manual in-game checklist

Use a Mage with low-value stacks you don't mind losing to a merchant (Buyback can return them). Turn on Display Lua
Errors. Put on the bag: a few stacks of plain food and drink (vendor bread, water), one conjured food and water, a
buff food or feast, a potion, a quest item if one is at hand, a locked stack (put it in a trade or mail draft), a
soulbound one if you have it, and one item you add to the list.

1. **Feature off.** Open a merchant: nothing is sold, no chat line, `/tui diagnostics` says off.
2. **Dry run.** Turn the feature on (Dry run stays on). Open a merchant: one line saying what would be sold; bags
   unchanged; a second open says it again, once.
3. **Preview.** `/tui sell`: the same stacks are listed; conjured, special food, quest and excluded items appear under
   Kept with a reason; potions don't appear. Add an item by dropping it, by link and by ID; Remove it. Nothing in the
   bags moved; the cursor is empty afterwards.
4. **Diagnostics.** "conjured checks": tooltip API yes, "Conjured Item" text defined yes, and the same counts.
   If `ITEM_CONJURED` isn't defined, stop here: nothing will sell.
5. **Eligible items sell.** Turn Dry run off, open a merchant: the plain stacks sell one by one, one summary line,
   Buyback tab lists them, gold went up by about the figure.
6. **Conjured stays.** Conjured food and water in the bags are still there after the run, including water from another
   Mage if you can get some. Check `/tui diagnostics` for them under `conjured`.
7. **Special, quest and excluded items stay.** Feast or buff food, the quest item and the listed item are untouched.
8. **Missing or locked.** A stack in a trade window or mail draft (locked) is skipped. Right after login, with item
   data not yet loaded, items are kept and sold at a later visit once loaded, not guessed.
9. **Closing mid-run.** With more than a few stacks, close the merchant right after the first sale: the run stops,
   the summary says the merchant closed, nothing is sold at the next merchant until its own run starts fresh.
10. **Buyback and limit.** With 12 or more eligible stacks, one visit sells 10 and says how many are left; opening
    the merchant again in the same visit does not start another batch; Sell now continues. Buyback shows what
    the visit sold and note which earlier entries were pushed out.
11. **Auto-vendor compatibility.** With Leatrix_Plus's junk selling (or any junk seller) on, open a merchant:
    junk and food are both handled once, no Lua errors, no stack sold twice.
12. **Reload, profiles and errors.** `/reload` mid-visit: nothing resumes. Switch an EllesmereUI profile: nothing changes
    (TwichUI has no profiles). Turn the feature off while a run is going: it stops with no summary. Watch for Lua
    errors and "action blocked" messages; a block shows as "the game blocked the sale" and `blocked` in diagnostics.
