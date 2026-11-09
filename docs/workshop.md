# Workshop (TwichUI_Workshop)

For anyone changing the feature. This is the one current reference and handoff for it; `STATUS_AND_BACKLOG.md` has the short status.
**Real-client status:** the player confirmed (2026-11-09) that after the anchor fix the window opens and works in game. That is the only in-game confirmation: none of the other
checks below was reported, and **nothing in milestone 2 (prices) has been tried in the game.** Evidence labels (CLAUDE.md) are used throughout: unit-tested, simulator-tested, real-client-tested, not tested.

## What it does (milestones 1 and 2)

Two views, switched by the **Crafting** / **Opportunities** buttons beside the title (it opens on Crafting; the choice is kept only while the game runs).

### Crafting (milestone 1)

A window opened with `/tui workshop` (a hidden command, like `/tui perf`: it keeps the help list short and is listed on the Workshop page), the **Workshop...** row of the TwichUI data bar menu, or the Workshop settings page.
- **Recipes** (left): the player's own open profession, with a search, one button per profession seen this session, and per row
  the icon, name, difficulty (Orange/Yellow/Green/Grey, word and colour) and what one craft makes. **Add** queues it.
- **Queue** (right): each recipe with its crafts, `-`/`+` (Shift: five), **Open recipe**, **Remove**; shows crafts and expected output
  ("3 crafts - makes 1-2 each, 3-6 in all"). A recipe whose materials aren't known says "Open profession to update."
- **Materials** (right, under the queue): needed, in bags, **Still needed**, per material, combined over the whole queue first; one sentence under it
  ("Still needed: 2 materials." / "All the materials are in your bags." / "1 recipe can't be counted yet. Open its profession to update.").
  The area says once that it counts **bags only**.
- It never crafts, buys, sells or sends; the queue is finished by hand (Remove). Collection progress is separate from crafting.

### Opportunities (milestone 2)
For every recipe read this session (all professions seen, not only the one browsed), **one craft**: item icon (hover for the item, Shift-click puts its link in an open chat box),
recipe name, what it makes, **Cost to make**, **Sell price**, **Estimated profit**, and **Add** (the same queue as Crafting). Default order: highest estimated profit first; the three
money headings sort (a second click reverses); profession buttons filter; **Profitable only** hides losses and unknown ones. Unknown estimates ("Unknown", with the reason under the name,
e.g. "1 material has no price") are always below every known one. Hovering a row shows its **basis**: each material with quantity, unit price and total, what it makes and its price,
the cut line, the profit, and the price age. An output range (e.g. makes 1-3) shows the low amount with "to <high>" under it and sorts/filters by its low end; the maximum is never assumed.
Empty states: no recipes, no prices saved, none could be priced, no profitable craft.
The **Scan prices** button (top right of the view) starts a scan only when pressed; its states are shown in one line (scanning, finished, stopped, failed, unavailable).

## Files

| Where | What |
|---|---|
| `!!!TwichUI/WorkshopLauncher.lua` | core: `R.WorkshopLauncher` (`Load`, `Open`, `Toggle`, `Command`, `Snapshot`); loads the addon on first use, never at login, never in combat (`COMBAT`), plain-words failures like `DiagnosticsLauncher.lua`; scope `workshop.load` |
| `TwichUI_Workshop/` | the addon (`## LoadOnDemand: 1`, `RequiredDeps: !!!TwichUI`, no SavedVariables of its own) |
| `Data.lua` | `R.Workshop` (W): limits, `Plain` (drops secret values), `Int`, `Text`, difficulty words, `PerCraft`, `Expected` (pure) |
| `Materials.lua` | `W.Materials.Rows`: combine first, then apply bag counts once per item; states empty/partial/short/ready (pure) |
| `Queue.lua` | the saved queue (`TwichUIDB.workshop`), checking every record, `Refresh` from an observation |
| `Observe.lua` | game reads: `Read` (own profession list), `Fill` (output + materials from the schematic), `BagCount`, `ItemFacts`, `OpenRecipe` |
| `Prices.lua` | **the price service**: stack-to-unit price, the batch that turns auction records into the cheapest buyout per item, the saved scans (`TwichUIDB.workshop.prices`), lookups, price age, the cut table, and `Estimate` (cost, sell price and profit of one craft) |
| `Opportunities.lua` | the list: rows, summary, filter, sort, "why unknown" words and the basis lines for the tooltip (pure) |
| `Scan.lua` | the price scan of the open auction house (`W.Scan`): state machine, event frame (registered only during a scan), bounded batches, plain-word messages |
| `Session.lua` | in-memory lists per profession, actions and their messages, the rows the window draws, and the Opportunities glue (`S.Opportunities`, `S.StartScan`, `S.Wanted`, `S.PriceSource`) (no frames) |
| `Window.lua` | the window (FrameLook, `L.EditBox`, pooled scroll lists); events registered only while shown; marks `W.ready` last |
| `TwichUI_Settings/pages/Workshop.lua` | settings page: works before the addon loads, through the launcher |
| `TwichUI_Diagnostics/*` | memory row, scopes `workshop.load/read/render/scan`, gauges `workshop.*` incl. `workshop.prices` (see `docs/diagnostics.md`) |
| `.pkgmeta`, `tools/release.py` | packaging (seven folders); `tests/test_release_tools.py` fixtures include it |
| `tests/test_workshop.lua`, `tests/test_workshop_window.lua`, `tests/test_workshop_prices.lua` | the tests |

## Saved data

`TwichUIDB.workshop = { v = 1, chars = { ["Name - Realm"] = { queue = { entry... } } } }`, account-wide, **never in a profile, share or backup**
(`Persist.CONTAINERS`, `Restore.OWN_LEFT_OUT`, `TwichConfig.LOCAL` as `other`).
`entry = { id (recipe spell), name, crafts (1-999), prof, profName, icon, outMin, outMax, mats = { { item, qty } }, seen }`.
At most 30 entries, 16 materials each. `mats` absent means "not known" (never zero). Reading never writes; an unreadable entry is left out of the
next write. `v` higher than 1 (a newer TwichUI) makes every change refuse with "held" and shows a read-only note. No window position is saved.
It is not a recipe database and keeps nothing for other characters, linked, guild or unqueued recipes.

**Prices** (milestone 2), in the same `workshop` key (so also never in a profile, share or backup; `v` stays 1 because the addition is compatible):
`prices = { v = 1, markets = { ["Realm|Side"] = { realm, side, at, complete, read, used, n, items = { [itemID] = { p, q, l, t } } } } }`
- `Side` is the auctioneer's faction from `UnitFactionGroup("npc")` at scan time, or `unknown` when the game gives none: a market of its own. Markets are never merged; the view uses the open
  auction house's market, or (house closed) the most recently scanned market of the current realm, and says which in words.
- `p` cheapest unit price in whole copper, `q` items listed at that exact price, `l` buyout listings seen, `t` items in them. Only items the recipes read **at scan time** are kept
  (`S.Wanted`: outputs and materials of this session's recipes), at most 2000 per market and 4 markets (the longest-ago scan goes first). `at` is the scan time; `complete` is the completeness.
- A scan that is not complete never replaces an older complete one (`Commit` answers "kept"); a failed or interrupted scan writes nothing. A newer `prices.v` or `workshop.v` makes everything read-only.
- Not saved: individual auctions, owners, bid-only listings, sale history. Nothing is collected at login or in the background.

## How recipes are read (client facts)

Target client: Forever 1.60.1, UI source `forever` branch. Forever has no classic `GetNumTradeSkills`; the profession window is built on `C_TradeSkillUI`.
- **Code-verified (UI source/documentation):** `GetBaseProfessionInfo`, `GetRecipeInfo` (`learned`, `name`, `icon`, `relativeDifficulty` 0-3, `isRecraft`...),
  `GetRecipeSchematic` (`quantityMin/Max`, `outputItemID`, `reagentSlotSchematics[].reagentType/reagents/quantityRequired/required/variableQuantities`),
  `OpenRecipe`; `GetFilteredRecipeIDs`, `IsTradeSkillLinked`, `IsTradeSkillGuild`, `IsNPCCrafting`, `IsDataSourceChanging` are called by Blizzard's own profession code.
- **Not in the Forever source:** `GetAllRecipeIDs` (the reference addons call it when it exists). It is tried first; a list from it is "complete".
  Otherwise the list is the profession window's **filtered** list and the window says so; omitted recipes are never treated as unlearned or forgotten.
- Recipes are read only from the open window and **only if the game says it is the player's own** (not linked, guild or NPC; a missing answer counts as not own).
  Blizzard's filters are never changed (the tests make any `Set*/Clear*/Close*` call on `C_TradeSkillUI` an error).
- Materials: only `Basic` slots with exactly one item choice and a fixed quantity count. A choice of items, automatic or required extra reagents, currencies or
  variable quantities make the recipe's materials "not supported" (unknown, shown as such); optional extras are ignored.
- Bags: `C_Item.GetItemCount(id)` (bank not included). Unreadable is unknown, not zero.
- `GetRecipeInfo`/`OpenRecipe` take `SecretArguments = "AllowedWhenUntainted"`; every value read goes through `Plain` and `Int`/`Text`.

## Prices: the exact basis (milestone 2)

- **Latest-listing estimate.** A price is the **cheapest buyout among the listings the newest scan of that auction house saw**, per single item: stack buyout / stack count, rounded **up** to whole copper, never
  below 1. It is a **listing** price, not a sale price, not a "market value", not a sale rate; no history, no averages, no external data.
- Bid-only auctions (buyout 0) are ignored. A price, count or item id that is not a whole number in range (or is a secret value) is an invalid record and is skipped. A missing or invalid price is **unknown**
  (`nil`), never 0; any unknown input makes the whole cost, and so the profit, unknown. If the cheapest listing holds fewer than a craft needs the price is still used and flagged "cheapest listing only";
  if the whole market lists fewer than a craft needs, that material counts as having no price.
- **One craft**, with the **full** material list (owning the materials does not make them free; bags are not consulted). **Cost to make** = sum of quantity x unit price. **Sell price** = unit price of the
  recipe's output item x the output per craft; an output range (`quantityMin`..`quantityMax`) gives a low and a high, and the profit is a range. **Estimated profit** = sell price - auction house cut - cost.
- **Cut.** The Forever UI source states no auction house cut anywhere (searched `Blizzard_AuctionHouseUI`, the API documentation and the mail invoice strings), and other versions differ between auction
  houses, so **no cut is assumed**: `Prices.CUT` is an empty table keyed by auction house side. Until a side is confirmed in the game, profit is shown **before the cut** and the view, the notes and the
  tooltip say so. When a side is added (read the sale invoice in the mailbox: sale price versus "House cut"), the cut is rounded to whole copper and shown on its own tooltip line.
- Always stated in the view: a listing does not guarantee a sale; failed listings, deposits and selling time are not counted; some professions only list what their window's filters allow, so the list
  may not be every recipe.
- **Supported recipes:** those the window read this session whose materials were supported by milestone 1's rules (basic reagents, one item per slot, fixed quantities) **and** that make a single item
  (`outputItemID`) in a known quantity. Enchants (no item), recipes with item choices, required extra reagents or variable quantities, and recipes whose output isn't known are listed as **Unknown**
  with the reason. Items with random properties are priced by the cheapest listing of their item id only (no variant matching).
- **Vendor prices:** none are used. The NPC collection stores item ids only ("no names, prices or counts"), so there is no verified vendor **purchase** price to use; vendor **sell** value is never used
  as a cost. A material sold only by vendors therefore shows "no price" unless it is on the auction house.

## The price scan: what the source says and what it does not (milestone 2)

- **Used:** `C_AuctionHouse.ReplicateItems()`, event `REPLICATE_ITEM_LIST_UPDATE`, `GetNumReplicateItems()`, `GetReplicateItemInfo(i)` (18 values; used: `count`, `buyoutPrice`, `itemID`, `hasAllInfo`),
  `IsThrottledMessageSystemReady()` and the throttle events. **Source-verified:** all of these exist in the target client's API documentation (`AuctionHouseDocumentation.lua`, 1.60.1), and the
  documentation says `ReplicateItems` "should be used in place of an 'allItem' QueryAuctionItems call to query the entire auction house" while search queries are restricted to 100 per minute and "should not
  be used to query the entire auction house". The Forever UI itself **never calls** `ReplicateItems` (the auction house UI is the "Classic family" variant, `AllowLoadGameType: mainline, cata, mists`).
- **Not established by any source here (so nothing assumes it):** how often a full request is allowed, whether the event fires once or repeatedly, whether `buyoutPrice`/`count` are valid when
  `hasAllInfo` is false, whether `ReplicateItems` consumes the throttled-message budget, and what `UnitFactionGroup("npc")` returns for a neutral auctioneer.
- **What the code does about that:** sends only when the game says its throttled-message system is ready (else waits up to 30 s, then "wasn't ready"); waits up to 90 s for the first update ("didn't send its
  listings"); reads only after the update has been quiet for 2 s, restarts the read if more arrive (at most 3 times, then "kept changing"); reads in batches of 400 on timer ticks; if any record said it lacked
  information, waits 4 s and reads again (at most twice) and otherwise **saves the scan as not complete**. A scan is **complete** only if no record lacked information, nothing was cut off (250,000 records,
  the wanted list, 2000 items) and the scan finished. This is a full-house request, **not** a partial search presented as a market scan; if the game refuses it, the scan fails or is unavailable.
- Starts only on the button. Refused (state **unavailable**, nothing sent): auction house not open (`AuctionHouseFrame` shown), API missing, nothing to price (no recipes read), the posting page's own
  search running (`R.AuctionScan.Busy()`), realm unknown, saved prices held by a newer TwichUI. A click while a scan runs does nothing. The posting page is **not changed**: it can still start its own search
  during a scan (it checks the throttle itself); the scan then only waits or fails on the throttle.
- Ends once. **Interrupted** (auction house closed or disabled, mid-wait or mid-read); **failed** (no response, dropped by the throttle, never ready, listings kept changing, none, unreadable, request error,
  not saved, not complete while a complete scan exists); **done**. Every timer and step carries a token that ends with the scan, so a callback from an earlier scan never touches a later one. Events are
  registered only while a scan runs. Hiding the Workshop window does not stop a scan; closing the auction house does.
- It never buys, bids, cancels or posts, and calls no function other than the read-only ones above.

## Investigation summary (so it is not repeated)

- Both Mastercraft and Profession Master read recipes only while the profession window is open and save them per character (reference-only; Profession Master says so for Forever).
- Profession Master guild sync (hello/digest/request/cooldown messages, paced pushes, `shareCooldowns` and `respondToWho` default on, `!who` answers in chat) is a
  reference for later milestones only; TwichUI's rule is opt-in, bounded, no unsolicited chat (`docs/dev-rules.md`, `guildloc/Comm.lua` for the transport pattern).
- Its leveling planner assumes a linear skill-up chance and ships its own difficulty data; Mastercraft counts owned/farmed items as free. Neither is a model for the
  planned semantics (owned materials are not zero cost; uncertain skill gains; replan from progress).
- TwichUI has no inventory ownership service for bank/mail/alts, no price API (`auction/Scan.lua` is a one-item posting search), no money helper (`GetMoneyString`).
  Useful for later: `inventory/Items.lua` item facts, `pins/Pins.lua` `PN.AddLocal`, `nav/Nav.lua` `NV.StartAt`, `npcs/` (observed merchants/trainers), `reminders/Conditions.lua` providers.
- **Licensing:** TradeSkillMaster is all rights reserved (no derivatives; permission only by contacting its owner). Profession Master is "All Rights Reserved" in its source.
  Mastercraft has no license file (no permission). Nothing was copied from any of them: no code, data, artwork or branding. Their recipe-source datasets are Wowhead-derived and
  not reusable. A future source database needs its own provenance and license; until then "where to learn" is only what the player's own game or the NPC collection observed.

## Evidence

- **Unit-tested** (`tests/test_workshop.lua`, `tests/test_workshop_window.lua`, with a fake `C_TradeSkillUI`, bags and window): crafts against output including ranges; combined
  materials without double counting; unknown/unsupported materials and bag counts never zero or ready; the saved queue (per character, limit, reload, bad entries, newer version,
  no saved variables yet); refresh without losing known data; own-profession-only reads, complete vs filtered lists, switching professions, incomplete lists never removing queued
  recipes; secret values; launcher at login/combat/failures; the window's lifecycle (events only while shown, forgets lists when hidden, dropped stale redraws, buttons).
- **Simulator-tested:** `SIMLAB_PAGE=workshop SIMLAB_TITLE=Workshop bash tools/simlab/smoke.sh` passed (the real core TOC including `WorkshopLauncher.lua` loads, the Workshop settings page
  opens and constructs, all 55 described pages construct, no Lua error). Construction only: the Workshop window itself was not run in the simulator (no scenario exists for it), and nothing about
  looks, input or the real recipe interface is shown by it.
- **Unit-tested (milestone 2, `tests/test_workshop_prices.lua`, plus a section of `tests/test_workshop_window.lua`):** stack/unit conversion (rounding up, never 0, exact comparison); invalid, bid-only,
  secret and unwanted auction records; saved scans (markets kept apart, age words, bounds, a complete scan kept over an incomplete one, bad saved entries never a price, newer version held, the queue
  unaffected); cost with full materials, multi-output and range outputs, cut arithmetic and the unconfirmed cut, losses, every unknown reason, "not enough listed", price age and completeness;
  sort/filter/unknown-last; the scan against a **fake** auction house with a virtual clock (refusals, repeated click, throttle wait and give-up, bounded batches, restart on change, no response, dropped,
  closed mid-wait and mid-read, stale timers from an earlier scan, empty list, not-complete scans, the earlier scan preserved); the Opportunities view on stand-in frames (rows, ranges, unknown, sorting,
  Profitable only, empty states, the basis tooltip, Add to the one queue, the scan button states, hidden window leaves nothing running).
- **Simulator-tested (milestone 2):** `SIMLAB_PAGE=workshop SIMLAB_TITLE=Workshop bash tools/simlab/smoke.sh` passed again after the settings page text changed (construction only, 55 of 55 pages, no Lua error).
- **Mocked, not real:** all auction results above come from a fake. They show our logic, not what the real auction house returns. No simulator scenario covers the auction house or this view.
- **Real-client-tested:** only that the window opens and works after the anchor fix (reported by the player). Nothing else.

## Not built (decided)

Sale history, "market value", sale rates, external price sources, recursive buy-versus-craft, vendor purchase prices, saved known-recipe summaries (so Opportunities need a profession read this session), bank/mail/alt counts, guild sharing, cooldowns, leveling plans, a recipe-source database, direct crafting buttons, automatic
queue completion, a saved window position, a Clear queue button, a settings option for opening it from a profession window.

## In-game checks (milestone 1: none reported; milestone 2 below)

1. Open `/tui workshop` at login-time-free (the addon must not appear in the AddOns memory list until opened) and in combat (must refuse with the plain message).
2. With Alchemy (or any profession) open: do recipes appear, with correct learned flags, difficulty colours and "Makes" numbers? Does a window with no search give a complete list?
3. Does `C_TradeSkillUI.GetAllRecipeIDs` exist? (`/dump C_TradeSkillUI.GetAllRecipeIDs ~= nil`.) If not, the "follows the filters" note should show; toggle a window filter and see the list follow it.
4. `GetRecipeSchematic(recipeID, false)`: for a normal recipe, are the materials `Basic` slots with one `reagents` entry? Do enchants/special recipes show "can't be counted yet"?
5. Add recipes from two professions; close and reopen the window; `/reload`: the queue and its materials remain; switching professions keeps the queue.
6. Bags: gather/drop a material while the window is open; "In bags" and "Still needed" follow within a moment; closing and reopening shows fresh counts.
7. Link a profession in chat / open a guildmate's recipes: the Workshop says it is not your own and records nothing.
8. **Open recipe** opens the game's profession window on that recipe, also when no profession window is open.
9. Esc closes the Workshop; the window drags; text fits at the usual UI scales and larger fonts; the guild-bank look matches.
10. Does `C_Item.GetItemCount(id)` count the reagent bag, and nothing from the bank, as intended?

## In-game checks for the price scan (milestone 2; none done)

Open two professions first (so the scan knows which items to keep), then at an auction house open `/tui workshop` > **Opportunities**.
1. **The probe (do this first).** Press **Scan prices**. Does the status go "Asking the auction house..." > "Receiving listings..." > "Reading listings..." > "Scan finished"? If it says it didn't send its listings, or was
   turned down, note which and when you last scanned: that shows the real limit on full scans. `/run print(C_AuctionHouse.ReplicateItems ~= nil, C_AuctionHouse.GetNumReplicateItems())` before and after tells whether the function exists and the listing count.
2. Is the finished scan marked complete (no "may be incomplete" line)? If not, how many records lacked information (`/run print(C_AuctionHouse.GetReplicateItemInfo(1))` shows the 18 values, the last is `hasAllInfo`)?
3. Do the prices match what you see in the auction house for 3 items (cheapest buyout, per item for a stack)? Is a stack's unit price right?
4. `/run print(UnitFactionGroup("npc"))` at a faction auctioneer and at a neutral one (Booty Bay): what comes back? The view says "the Alliance auction house on <realm>" / "the auction house on <realm>" (unknown side).
5. Scan again right away: is it allowed, refused, or does it return the same data? Close the auction house during a scan: it should say it stopped, and keep the earlier prices.
6. After a sale, read the invoice in the mailbox: sale price versus "House cut". If it is the same percentage for that auction house, add its side to `Prices.CUT` (one line and a test).
7. Profit for one craft you know: do the cost, sell price and profit match your own arithmetic (cut not taken off)? Does an output range (makes 1-3) show a low and "to" high? Does hovering show the basis?
8. Does the list stay smooth while reading (no stall) on a large realm? Does `/tui perf` show `workshop.scan` per batch and `workshop.prices`?
9. Do the money columns line up, the coin icons show, and does Shift-click on an icon link into an open chat box?
10. Do the column headings sort (is the order what the line under the list says), do the profession buttons and Profitable only work, and does Add show "Queued" and appear in Crafting?

## Next small tasks (each its own request)

0. **Run the milestone 2 checks above, fix what they show (most likely the scan's completeness rule and the neutral-auctioneer side), then fill `Prices.CUT` from the invoice.**
0b. Then: remember known recipes' output and materials (bounded, per character) so Opportunities and the scan work without a profession window open this session. Needs a decision: it is a recipe-summary store.

1. Run the in-game checks above and fix what they show (most likely the schematic reads and `GetAllRecipeIDs`).
2. Remember the window position; a "Clear queue" with a question.
3. Bank and mail counts with last-observed times (needs an ownership service; decide the loading strategy first because it needs always-on events).

## Opening problem: `/tui workshop` showed nothing (2026-11-09)

**Cause (found from the files, not yet confirmed in the game):** `Window.lua` `Build()` created the main frame, sized it, but **never anchored it** (no
`SetPoint`). An unanchored frame reports `IsShown() == true` but is never drawn, so the command ran, loaded the addon and "opened" an invisible window, with
no error and no message. The unit test's fake frames could not notice. Fix: `f:SetPoint("CENTER")` in `Build()`.

The player's earlier in-game output (`TwichUI_Workshop ... false DEMAND_LOADED INSECURE`) was normal for a load-on-demand addon that has not been loaded yet
(it only shows the folder is installed). **Correction:** my first look at the AddOns folder used the `_classic_beta_` client, which has an old release; the
game in use is `_forever_`, whose `!!!TwichUI` and `TwichUI_Workshop` match the repository (read only compare; the sibling `.toc` there also lists a second
Interface number, which is the player's own edit). Packaging and the launcher path were fine.

**Changed:** `TwichUI_Workshop/Window.lua` (the anchor). `tests/test_workshop_window.lua` fails without the anchor and passes with it; `tests/test_workshop.lua` also has a
packaging block (TOC, load on demand, file list, `.pkgmeta`).

**Local results (unit-tested):** both Workshop tests pass; the anchor test was shown to fail on the old code. **Real client: the player later confirmed the window shows and works.**

**Next in-game check:** copy `TwichUI_Workshop/Window.lua` into the `_forever_` AddOns folder (not done here: no live files were changed), `/reload`, then `/tui workshop`. The
window should appear in the screen's centre. If not, `/run print(TwichUIWorkshop and TwichUIWorkshop:IsShown(), TwichUIWorkshop and TwichUIWorkshop:GetNumPoints())`
tells shown/anchored from missing.
