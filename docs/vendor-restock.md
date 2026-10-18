# Vendor restocking

For anyone changing the feature. Code: `modules/Restock.lua` (rules, plan, purchases, summary), `modules/RestockPrompt.lua` (the question's window), the settings in
`TwichUI_Settings/pages/Restock.lua` (on/off, purchase mode, spending limit) and `TwichUI_Settings/pages/RestockItems.lua`
(the list, adding items, class suggestions), `modules.restock` in `Core.lua`, the two sharing groups in
`setup/TwichConfig.lua`. Tests: `tests/test_restock.lua`, `tests/test_restock_prompt.lua`, `tests/test_restock_settings.lua`, and the coexistence block at
the end of `tests/test_mage_sell.lua`. **Nothing here has been tried in the game**, and no purchase has been made by it.

## What it does

The player lists items with a target: how many to keep in the carried bags. When a merchant that sells an item on the
list opens, TwichUI counts what the bags hold and, for each item that is on and below its target, plans to buy the
difference. "Ask before purchasing" (the default) shows the plan and buys only on Purchase; "Purchase automatically"
buys without asking, and only once the player has confirmed that on this account.

Off by default (`modules.restock`, only an explicit `true` is on), with an empty list and the mode on Ask. TwichUI never
adds a rule by itself; a class suggestion is added only by clicking it.

## Saved data

Per profile, `TwichUIDB.ui.restock`:

| Key | Meaning |
|---|---|
| `items` | `{ { id, target, enabled }, ... }`. Item ID, a whole number 1–9999, on/off. The order is the priority. At most 60. |
| `mode` | `"ask"` (default) or `"auto"`. |
| `useLimit` | `false` (default): no limit of TwichUI's own. `true`: at most `limit` per merchant visit. |
| `limit` | copper, 0–99,999,999 (default 10,000 = 1g). 0 is a real limit: nothing is bought. Kept while `useLimit` is off. |

The question window's look is its own table, `TwichUIDB.ui.restockPromptStyle` (a `MenuStyle` look: `bgTexture`,
`bgColor`, `bgOpacity`, `borderTexture`, `borderColor`, `borderOpacity`, `borderSize`; only values the player changed
are saved, and an invalid one reads as the default without being erased). Per profile and shared with the restock
settings, below.

Account-wide, never in a profile or a share: `TwichUIDB.ui.restockAck = true` once the player confirmed automatic
buying (`Profiles.ACCOUNT.ui`, `TwichConfig.LOCAL`). `RS.Mode()` is `"auto"` only with both `mode == "auto"` and the
confirmation, so a profile, an import or another computer can choose automatic buying but can't authorize it.

Reading never writes. A write stores the list as it reads: an entry that can't be read (not a table, a bad ID, a target
out of range, a repeat of an earlier item) is left out of that write; a damaged on/off reads as off. Nothing of a visit
(plans, purchases, counts, the question) is saved. `Persist.lua` treats `ui.restock` as a container (a non-table is
dropped and repaired). Backups (`point.own`) include it as part of TwichUI's settings.

## Client behavior, and where it comes from

Forever is the `camelot` game type, in the mainline family (`Blizzard_UIPanels_Game.toc`: `[Family]\…  [AllowLoadGameType
mainline] [ExcludeLoadGameType camelot]` lines), so `Mainline/MerchantFrame.lua` is the merchant window it loads. Every
merchant call TwichUI makes is one that file makes:

| Question | What the source shows |
|---|---|
| A listing's data | `C_MerchantFrame.GetItemInfo(index)` (documented in `MerchantFrameDocumentation.lua`): `price`, `stackCount`, `numAvailable`, `isPurchasable`, `hasExtendedCost`, `currencyID`. `GetMerchantItemID(i)`, `GetMerchantItemLink(i)`, `GetMerchantNumItems()` are the frame's own calls. |
| What `price` is for | One purchase of `stackCount` items: `MerchantItemButton_BuyMultipleStacks` works out a single item's cost as `price / stackCount`. |
| What the quantity means | `BuyMerchantItem(index, n)` takes a count of **items**: the stack split frame starts at `stackCount` and moves in steps of it (`StackSplitMixin.minSplit`), up to `GetMerchantItemMaxStack(index)`, and `MerchantFrame_ConfirmExtendedItemCost` scales cost by `n / stackCount`. TwichUI only ever asks for a multiple of `stackCount`, at most `GetMerchantItemMaxStack` per call. |
| Stock | `numAvailable` is shown only when `> 0`, and 0 tints the listing as unavailable; RestedXP's own code (which lists 16001) notes -1 as unlimited. Whether a limited stock counts items or purchases isn't shown, so it is read as **items** (the smaller): at worst TwichUI buys less than it could. |
| Other costs | `hasExtendedCost`, a `currencyID` (the frame swaps in currency container info), or `GetMerchantItemCostInfo(i) > 0` cost items: all left out ("costs tokens, items or another currency"). A listing is bought only when all three say "money only" and `price > 0`. |
| Buyback | A separate list (`GetBuybackItemInfo`, the Buyback tab). `GetMerchantItemID(i)` for `i ≤ GetMerchantNumItems()` is only what is for sale. |
| Discounts | `price` is what the frame shows, which is the price after reputation discounts. It is read again before every purchase. |
| Not protected | `BuyMerchantItem` isn't in the API documentation. Blizzard calls it from click handlers; RestedXP (16001) calls it from a `MERCHANT_SHOW` handler. That suggests an addon may call it outside a hardware event, but it is **not verified on Forever**. `ADDON_ACTION_BLOCKED`/`FORBIDDEN` stop a run if it isn't allowed. |
| Bags | `C_Container.GetContainerNumSlots`, `GetContainerItemInfo` (`itemID`, `stackCount`), `GetContainerNumFreeSlots` (second result: the bag's family). `C_Item.GetItemFamily`, `GetItemMaxStackSizeByID`, `GetItemUniqueness` (all documented). |
| Merchant filter | The Mainline frame has a class filter (`SetMerchantFilter`). Whether `GetMerchantNumItems` lists filtered-out items on Forever isn't known; a listing the merchant doesn't show can't be bought. |

## A visit

1. `MERCHANT_SHOW` (listened to only while the feature is on): a new visit; anything from the last one is dropped.
2. 0.5 s later: if TwichUI's own Mage selling is running (`MageSell.Running()`), look again every 0.5 s, at most 20 s.
   Selling first frees room and brings money in; selling never touches an item an enabled rule keeps (below).
3. One plan (`RS.Plan`, read only). If a listing or an item's details haven't arrived, wait for `MERCHANT_UPDATE` /
   `GET_ITEM_INFO_RECEIVED` (or 1 s), at most three times, then plan with what is known; what isn't is left out with a
   reason.
4. Ask: the question is TwichUI's own window (`modules/RestockPrompt.lua`, drawn with the shared `Look`): one row per
   item (up to eight; the rest are counted in the total) with its icon, its name in the item's quality color, how many,
   what you carry against the target, and the price with the g/s/c letters colored (`RS.ColorMoney`); a row that falls
   short says how many and why; under the list a card with the total, your money and the limit, and what couldn't be
   bought. It is built the first time it is needed and reuses one frame and its rows; Esc closes it through
   `UISpecialFrames`. Where it can't be drawn, `RS.QuestionText` is asked with the game's own dialog, same words.
   Purchase buys that plan. Cancel, Esc, the merchant
   closing, combat, or any change to the settings buys nothing (the question is put away, and a stale Purchase only
   says nothing was bought). Auto: straight on.
5. One plan per visit. Bags changing afterwards, `MERCHANT_UPDATE`, or the question being cancelled never start
   another. Opening the merchant again is a new visit.

### The plan

For each enabled rule, in list order, whose item the merchant lists:

- **Carried**: the sum of `stackCount` for that item ID in bags 0 to `NUM_TOTAL_EQUIPPED_BAG_SLOTS` (else `NUM_BAG_SLOTS`).
  Never the bank, mail, auctions or anything equipped (`C_Item.GetItemCount` isn't used). A slot whose count can't be
  read makes the item "couldn't count it", not 0.
- **Deficit** = target − carried. Nothing when it is 0 or less (and nothing is said).
- **Listings** that can be bought with money only (above). Several for the same item: the one that buys the most toward
  the target; then the cheaper per item; then the first.
- **Units** = the deficit, capped by: limited stock; room (the free part of the item's own stacks, plus empty slots in
  ordinary bags and in special bags whose family shares a bit with the item's); a unique item's limit
  (`GetItemUniqueness`, less what the bags hold: the bank isn't counted, so the game may still refuse); money left;
  the spending limit left. Then rounded **down** to whole purchases of `stackCount`. A bundle never takes the bags past
  the target; the shortfall is reported with why (`bundle`, `stock`, `bags-full`, `unique`, `money`, `spend-limit`).
- Money, the spending limit and empty slots planned for an item are not there for the items after it, so a list that
  can't all be afforded is bought top first.

### Buying

`Begin` makes a queue from the plan: per item, the approved quantity and price, and the approved total. Each purchase:

1. Checked again: same visit and settings generation, feature on, merchant open, out of combat; the same item at that
   listing with the same bundle size, still money-only; a price **no higher** than approved (higher: the run stops; in
   Ask mode the question is asked again with the new price, at most three times a visit; a lower price is fine);
   bags counted again, room, money and the limit worked out again; never more than the approved quantity left, the
   approved total left, or `GetMerchantItemMaxStack` in one call.
2. `BuyMerchantItem(index, n)` in a `pcall`. While it waits: `BAG_UPDATE_DELAYED`, `UI_ERROR_MESSAGE`,
   `ADDON_ACTION_BLOCKED`/`FORBIDDEN`, and a 3 s timer.
3. Done only when the bags show `n` more of the item than before. Bag events before then change nothing. The next
   purchase starts only after that. If fewer arrive by the timeout (or the game blocked it), only what arrived is
   counted, and the run stops; nothing is retried. A red error message names why, but only if the purchase then
   doesn't arrive (it may be about something else).

The merchant closing, combat starting, the feature being turned off, any rule or setting changing, or a profile change
(`Profiles.OnApply("views")` calls `RS.Refresh`) drops the run at once. Waiting events are registered only while a
purchase waits; nothing polls; the only timers are the short look after opening and the per-purchase timeout.

### The summary

One line in your own chat after a run: `TwichUI: Restocked [Arcane Powder] ×13 for 65s.` Two items are joined with
"and"; three or more are `Restocked 3 items for 2g 20s: [A] ×20, [B] ×10, [C] ×400.` What it bought is what arrived
in the bags, never what was asked for. The cost is the listed price of what arrived; it says "for about" unless the
money you have went down by exactly that. Then what fell short and why (at most three, then "and N more"), a purchase
that didn't arrive ("was asked for but it didn't show up in your bags. Nothing more was tried."), and why it stopped
("Restocking stopped: the merchant closed."). Nothing is said for a visit with nothing to buy. An item the merchant
sells that can't be bought at all ("Couldn't restock [X] (costs tokens…)") is said once a session per item and reason.

## The question window's appearance

Vendor restocking settings end with **Question window appearance**: background texture, color and opacity, and border
texture, thickness, color and opacity, with **Preview** and **Reset**. It is the same choices as the refreshments
panel and the pin windows (`K.Appearance` over `MenuStyle.New("restockPromptStyle", ...)`, `RestockPrompt.Style`), and
changes only the frame: what is asked, the rows, the total and the Purchase and Cancel answers are untouched. The
section is not tied to the "Restock from merchants" switch, so the look can be set before restocking is on.

* **Default:** exactly what the window had: the TwichUI rim (`Look.Shell`'s bronze edge, corner brackets, grain and
  shade) over `ff232221` at 98 %. The rim is a border id of the look's own (`RestockPrompt.LEDGER`, "TwichUI rim
  (default)"); `MenuStyle.Apply` draws no edge for it and says `"custom"`, and the window then shows the rim.
* **Any other border** (none, a solid line, the game's, EllesmereUI's, LibSharedMedia's) hides the rim, the corner
  brackets, the grain and the shade (`Look.ShellParts`, which uses the pieces `Look.Frame` now keeps in
  `frame.twichShell`). The title band moves in to the border's reach (`frame.twichBand`), and a border thicker than the
  rim (4 px) pushes the content in by the difference and grows the window by twice it, so nothing is covered. A thinner
  border leaves the content where it was. A textured background also drops the rim's grain and shade.
* **Greyed out with a reason:** thickness, color and opacity while the rim is chosen (its width and colors are fixed) or
  no border is.
* **Not covered:** the title band, the list and the total panel keep their own tint (only the window behind them
  fades); text fonts, sizes and colors, the rim's color, and the Purchase and Cancel buttons are the shared look's.
* **Redraws:** a change while the window is open redraws it once, in place, with the same plan (`Redraw`; no frame,
  texture or hook is created). A profile change goes through `MenuStyle`'s own notification. Border thickness is in
  screen pixels, worked out when the window is shown or redrawn.
* **Preview** (`RestockPrompt.TogglePreview`): the real window with three made-up items (real Classic reagent IDs, for
  icons and names only), one short row and one "not bought" note, under a line saying it is a sample. Purchase and
  Cancel only close it: it is never a question (`Restock.Asking()` stays false), calls nothing, reads no bags and no
  merchant. It opens beside the settings window and goes with it (`R.OnSettingsClosed`). A real question that is up is
  never replaced by it; a real question that arrives replaces it and opens in the window's usual place.

## Coexistence with selling

`MageSell.Judge` keeps any item an enabled rule keeps stocked while restocking is on (reason `restock`, "On your vendor
restocking list"), in both its modes: selling it would only be bought back at the next merchant. Restocking waits for a
selling run to finish before it plans. EllesmereUI's own junk selling is outside TwichUI; a purchase is checked by item
count, so another addon's sales of other items don't confuse it.

## Class suggestions

`RS.SUGGESTIONS`, by class: item IDs, a suggested target and what each is for. Shown for your class (another can be
chosen); each is added only by its own click, on, with its target. Changing class, character or profile removes
nothing. Sources, both specific to Forever:

- EllesmereUI DataBars `Blocks/Supplies.lua` (`CLASS_ITEMS`, used only when `EllesmereUI.IS_FOREVER`): Mage 17020, 17031,
  17032, 17056; Priest 17028, 17029, 17056; Druid 17021, 17026, 17034–17038; Paladin 21177, 17033; Shaman 17030, 17057,
  17058; Warlock 5565, 16583; Rogue 5140.
- RestedXP's Forever guides (`.collect` lines naming the item): 2512 Rough Arrow, 2515 Sharp Arrow, 2516 Light Shot,
  2519 Heavy Shot, 2928 Dust of Decay, 3371 Empty Vial, 5140 Flash Powder, 17031, 17056.

IDs only were taken (facts, not code). Left out: what vendors don't sell (Soul Shard, Blinding Powder, the poisons),
what is never used up (Thieves' Tools), and the higher arrows, shot and poison ingredients neither source names; add
those by ID. Which reagent a spell needs depends on its rank and what you have learned; the suggestions don't check
that, and the page says so.

## Sharing and profiles

Two groups in TwichUI's own settings sharing: **Vendor restocking** (mode, `useLimit`, `limit`) and **Restock items**
(the list). Whether restocking is on and the confirmation stay local. An import merges the list by item ID (named items
take the share's target and on/off; new ones go at the end while there is room; nothing is removed) and Undo puts back
exactly what it replaced. The review says plainly what it means for spending (`plan.spending`): a mode change to
automatic and whether it is confirmed here, the limit, and how many items it turns on. Each profile has its own list
and mode; the confirmation is the account's.

## Known limits

- Nothing has been run in the game. `BuyMerchantItem` outside a click, the limited-stock unit, `GetItemUniqueness`'s
  numbers, bag families for quivers and ammo pouches, and the money string are all unverified.
- A limited stock with bundles of more than 1 may be bought less than it could (stock read as items).
- Unique limits count only the bags.
- A listing the merchant's class filter hides can't be matched.
- One listing per item per visit; an item isn't split across two listings.
- The spending limit counts listed prices of what arrived (a partial bundle that arrived is counted as its share).

## In-game checklist (low-value items; you choose when to spend)

Use cheap items (Light Feather, Rough Arrow, a vendor drink) at a merchant that sells them, with little gold at stake.

1. Fresh install: Vendor restocking is off, the list is empty, the mode is Ask; opening a merchant does nothing.
2. Add Light Feather by dropping it from your bags: it stays in your bags (same slot, same count). Add an item by ID;
   type a nonsense ID and see it refused. Add the same item twice: no second row, the row is focused.
3. Turn restocking on, target 5, carry 2: opening the merchant asks to buy 3 with the right price and total. Cancel:
   nothing bought, nothing asked again until you reopen.
4. Reopen and press Purchase: 3 arrive; chat says `Restocked [Light Feather] ×3 for …` with the cost the merchant took.
5. Reopen at the target: nothing asked or said.
6. Rough Arrow (bundles of 200), target 300, carry 0: asks for 200 only (a second bundle would pass the target) and says
   100 short. With a quiver equipped, check the arrows' room counts the quiver.
7. Spending limit on, 0: nothing bought, says why. Then a limit smaller than the plan: bought top of the list first.
8. Purchase automatically: the confirmation explains spending; afterwards a merchant buys without asking, within the limit.
9. While the question is open: change a target, or close the merchant, then press Purchase: nothing is bought.
10. Bags full: says not enough room; nothing is bought.
11. An item with an extended cost (token vendor) on the list: says it costs more than gold, once; nothing bought.
12. Mage with selling on and a restocked drink on the list: selling leaves it; restocking runs after selling finishes.
13. Switch profile mid-question: the question goes. The other profile has its own list.
14. Share TwichUI's settings with a second client: the review names the restock changes and spending; applying merges;
    Undo restores. Restocking stays off on the receiver until turned on there.
15. /reload: the list, mode and limit are kept; nothing of the last visit is.
16. Question window appearance, default: compare the question with how it looked before (rim, corner brackets, grain,
    title band, list, total panel, buttons).
17. Preview: opens beside the settings window with three items, one short, a "not bought" line and the sample line;
    Purchase closes it and buys nothing; pressing Preview again or Esc closes it; closing the settings closes it.
18. Each border kind (none, solid at 1 / 4 / 12 / 16 px, a game border, an EllesmereUI border): the rim goes, the
    title band and close box sit inside the border, the rows, the total and both buttons are clear of it, the window
    stays on screen. Background none, a color, a texture, opacity 0 and 100: text, icons and buttons stay solid.
19. Open the real question, then change the look in the settings: it redraws in place; Purchase and Cancel still answer.
20. A different UI scale and a small game window: the border is the thickness chosen and the window fits the screen.
21. Reset: the look is back; the list, mode and limit are as they were. Switch profiles: the look follows the profile.
22. Share TwichUI's settings: the Vendor restocking group includes the look; the review shows it; applying changes only
    the look.
