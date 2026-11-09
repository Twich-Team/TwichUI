# Workshop (TwichUI_Workshop)

For anyone changing the feature. This is the one current reference and handoff for it; `STATUS_AND_BACKLOG.md` has the short status.
**Real-client status:** the player confirmed (2026-11-09) that after the anchor fix the window opens and works in game, and later reported the auction scanning / pricing / profitability milestone (2) complete.
That report was not itemized: which of the checks below were run, and what they showed, is **not recorded here**. **Nothing in milestone 3 (shopping list, vendor prices, making) has been tried in the game.**
Evidence labels (CLAUDE.md) are used throughout: unit-tested, simulator-tested, real-client-tested, not tested.

## What it does (milestones 1 to 3)

Three views, switched by the **Crafting** / **Shopping** / **Opportunities** buttons beside the title (it opens on Crafting; the choice is kept only while the game runs).

### Crafting (milestone 1)

A window opened with `/tui workshop` (a hidden command, like `/tui perf`: it keeps the help list short and is listed on the Workshop page), the **Workshop...** row of the TwichUI data bar menu, or the Workshop settings page.
- **Recipes** (left): the player's own open profession (or, until one is opened this session, the one remembered from last time: "Remembered from 2 days ago. Open Alchemy to update it."), with a search, one button per profession seen this session, and per row
  the icon, name, difficulty (Orange/Yellow/Green/Grey, word and colour) and what one craft makes. **Add** queues it.
- **Queue** (right): each recipe with its crafts, `-`/`+` (Shift: five), **Open recipe**, **Remove**; shows crafts and expected output
  ("3 crafts - makes 1-2 each, 3-6 in all"). A recipe whose materials aren't known says "Open profession to update."
- **Materials** (right, under the queue): needed, in bags, **Still needed**, per material, combined over the whole queue first (and, since milestone 3, less what **queued crafts will make**: see Shopping); one sentence under it
  ("Still needed: 2 materials." / "All the materials are in your bags." / "1 recipe can't be counted yet. Open its profession to update.").
  The area says once that it counts **bags only**.
- It never crafts, buys, sells or sends; the queue is finished by hand (Remove). Collection progress is separate from crafting.

### Shopping (milestone 3)

What the queue still needs, **each material once**, built from the same combined materials as the Crafting view (`Materials.Rows`, so there is one set of requirements, not a second copy). Columns: icon + name (hover: the item; Shift-click puts its link in an open
chat box, to look it up), **Still needed**, **Source** (a button), **Estimated spending**, and one action. Under the name: what to make (if making), how the options compare, and notes. Hovering a row shows the full basis (needed / from queued crafts / in bags / still needed,
each option with its price and **how old it is**, the making plan with every reagent owned and bought). Under the list: **Estimated spending** (only what is priced) and notes. Nothing is bought, crafted, posted or sent.
- **Sources.** *Vendor* (a price a vendor charged, seen by the player), *Auction house* (the saved scan), *Make* (a recipe this character knows). The row shows **Suggested source** and the button cycles: suggestion, then each option that can really be chosen, then back. The choice
  lives in memory only (kept while the material is on the list).
- **Queued crafts count.** A craft in the queue that makes a material another queued recipe uses is credited toward that need (`outMin x crafts`: a range counts its low end and says so), so a subcraft added to the queue is **never also shopped for**. Recipes that depend on each other
  (a circle, or one that uses what it makes) get no credit and are reported.
- **Show vendor** (vendor rows only, only when the player's own NPC collection has a merchant that was seen to sell the item, for the player's side, on a map the game shows): opens the world map and uses the collection's own find (`NpcMap.Locate`: map goes to the area, a ring on the marker).
  No waypoint, no route, no pin. In combat it says the map can be opened when combat ends.
- **Add to queue** (make rows): the explicit action. It adds `crafts` of the recipe (or raises an existing entry by that many; never a second entry). The queue then makes the item, so the row disappears and the recipe's reagents are the queue's own needs, counted once.
  A repeated click finds nothing to add ("Nothing to add: your queue already covers that.").
- **Auction search:** not offered. No existing safe integration starts a general auction search (`auction/Scan.lua` is the posting page's one-item search), so the row gives the item link/tooltip instead.

### Opportunities (milestone 2)
For every recipe read this session (all professions seen, not only the one browsed), **one craft**: item icon (hover for the item, Shift-click puts its link in an open chat box),
recipe name, what it makes, **Cost to make**, **Sell price**, **Estimated profit**, and **Add** (the same queue as Crafting). Default order: highest estimated profit first; the three
money headings sort (a second click reverses); profession buttons filter; **Profitable only** hides losses and unknown ones. Unknown estimates ("Unknown", with the reason under the name,
e.g. "1 material has no price") are always below every known one. Hovering a row shows its **basis**: each material with quantity, unit price and total, what it makes and its price,
the cut line, the profit, and the price age. An output range (e.g. makes 1-3) shows the low amount with "to <high>" under it and sorts/filters by its low end; the maximum is never assumed.
Empty states: no recipes, no prices saved, none could be priced, no profitable craft.
The **Scan prices** button (top right of the view) starts a scan only when pressed; its states are shown in one line (scanning, finished, stopped, failed, unavailable). While a scan runs an **overall progress bar**
(left of the button) shows the whole scan: asking and waiting for the game are the first 8%, the reading the rest (`Scan.Progress`, never backwards within a scan).

**On the auction house window** (`AuctionButton.lua`): the same **Scan prices** button sits under the window's lower right corner, with the same progress bar and message beside it while a scan runs and the last message
(not shown again after the window has been closed) afterwards. It is the same scan (`Session.StartScan`), so either button shows the other's progress. It exists once the Workshop has been loaded this session (the addon is
load on demand, nothing is built at login) and when Blizzard's auction house UI exists; the one event it waits for is dropped once it is made. **Limit:** the scan prices the Workshop's known
recipes (read this session or remembered from earlier ones), so the button works with the Workshop window closed once each profession has been read with the Workshop open; until then it answers "Open the Workshop and one of your professions first".

## Files

| Where | What |
|---|---|
| `!!!TwichUI/WorkshopLauncher.lua` | core: `R.WorkshopLauncher` (`Load`, `Open`, `Toggle`, `Command`, `Snapshot`); loads the addon on first use, never at login, never in combat (`COMBAT`), plain-words failures like `DiagnosticsLauncher.lua`; scope `workshop.load` |
| `TwichUI_Workshop/` | the addon (`## LoadOnDemand: 1`, `RequiredDeps: !!!TwichUI`, no SavedVariables of its own) |
| `Data.lua` | `R.Workshop` (W): limits, `Plain` (drops secret values), `Int`, `Text`, difficulty words, `PerCraft`, `Expected` (pure) |
| `Materials.lua` | `W.Materials.Rows`: combine first, then apply bag counts once per item; states empty/partial/short/ready (pure) |
| `Queue.lua` | the saved queue (`TwichUIDB.workshop`), checking every record, `Refresh` from an observation |
| `Known.lua` | the remembered recipes: `Load` / `Store` of a character's professions (`TwichUIDB.workshop.chars[..].known`), checked on the way in, bounded (pure data, no game calls) |
| `Observe.lua` | game reads: `Read` (own profession list), `Fill` (output + materials from the schematic), `BagCount`, `ItemFacts`, `OpenRecipe`, `ReadMerchant` (the open merchant's money-only listings) |
| `Prices.lua` | **the price service**: stack-to-unit price, the batch that turns auction records into the cheapest buyout per item, the saved scans (`TwichUIDB.workshop.prices`), lookups, price age, the cut table, `Estimate` (cost, sell price and profit of one craft) and `Quote` (what buying n of an item costs: exact / estimate / few / none) |
| `Vendor.lua` | saved vendor **purchase** prices (`TwichUIDB.workshop.vendor`), `Quote` (whole stacks, limited stock), and `Sellers`/`Places` (merchants of the NPC collection that were seen to sell an item) (pure) |
| `Shopping.lua` | the planner `Plan`: one list of what to get and where, the shared pool, making, totals; `Explain`, `Basis`, `Choices` (pure) |
| `Opportunities.lua` | the list: rows, summary, filter, sort, "why unknown" words and the basis lines for the tooltip (pure) |
| `Scan.lua` | the price scan of the open auction house (`W.Scan`): state machine, event frame (registered only during a scan), bounded batches, plain-word messages |
| `AuctionButton.lua` | the progress bar (`W.NewBar`) and the Scan prices button on `AuctionHouseFrame` (`W.AuctionButton`); follows `Scan.Listen` |
| `Session.lua` | in-memory lists per profession, actions and their messages, the rows the window draws, the Opportunities glue (`S.Opportunities`, `S.StartScan`, `S.Wanted`, `S.PriceSource`) and the Shopping glue (`S.Shopping`, `S.PickSource`, `S.CycleSource`, `S.AddSubcraft`, `S.ShowVendor`, `S.ReadMerchant`) (no frames) |
| `Window.lua` | the window (FrameLook, `L.EditBox`, pooled scroll lists); events registered only while shown; marks `W.ready` last |
| `TwichUI_Settings/pages/Workshop.lua` | settings page: works before the addon loads, through the launcher |
| `TwichUI_Diagnostics/*` | memory row, scopes `workshop.load/read/render/scan`, gauges `workshop.*` incl. `workshop.prices` (see `docs/diagnostics.md`) |
| `.pkgmeta`, `tools/release.py` | packaging (seven folders); `tests/test_release_tools.py` fixtures include it |
| `tests/test_workshop.lua`, `tests/test_workshop_window.lua`, `tests/test_workshop_prices.lua`, `tests/test_workshop_shopping.lua` | the tests |

## Saved data

`TwichUIDB.workshop = { v = 1, chars = { ["Name - Realm"] = { queue = { entry... } } } }`, account-wide, **never in a profile, share or backup**
(`Persist.CONTAINERS`, `Restore.OWN_LEFT_OUT`, `TwichConfig.LOCAL` as `other`).
`entry = { id (recipe spell), name, crafts (1-999), prof, profName, icon, outItem, outMin, outMax, mats = { { item, qty } }, seen }` (`outItem`, the item one craft makes, was added in milestone 3: compatible, `v` stays 1; an older entry without it learns it from the known recipe, in memory).
At most 30 entries, 16 materials each. `mats` absent means "not known" (never zero). Reading never writes; an unreadable entry is left out of the
next write. `v` higher than 1 (a newer TwichUI) makes every change refuse with "held" and shows a read-only note. No window position is saved.
It is not a recipe database and keeps nothing for other characters, linked or guild recipes.

**Remembered recipes** (`Known.lua`), in the same character slot: `known = { [professionID] = { name, at, complete, r = { recipe, ... } } }`, `recipe = { id, name, icon, outItem, outMin, outMax, state, item1, qty1, ... }`
(a flat list; `state` 0 = not read yet, 1 = materials follow, 2 = read but not supported; 0 means "not known" for the numbers). Written when a profession is read in the player's own window (and again when its recipes' details have all been
read, and when the window closes), so the next session knows the recipes, what they make and need without opening anything. A new read of a profession replaces its entry's data, keeps what is remembered until the game has been asked again, and,
when the list follows the window's filters, keeps the recipes the filters left out (`extra`: still known, not browsed). Difficulty is **not** kept (it depends on the character's skill). At most 5 professions (the one read longest ago goes) and 600 recipes
each. Same rules as the queue: never written when `v` is higher than understood, bad records skipped, never in a profile, share or backup. Not noticed: a profession the character drops, or a recipe unlearned, stays remembered until that profession is read
again and its list is complete (the recipes then shown replace the old ones).
**Learning needs the Workshop window open:** a profession is read only while the Workshop window is shown (it listens to nothing otherwise), so open the Workshop first, then your professions. Remembered recipes are not re-read from the game while their
profession is closed (the game may not give the details of one that isn't open): they stand until it is read.

**Prices** (milestone 2), in the same `workshop` key (so also never in a profile, share or backup; `v` stays 1 because the addition is compatible):
`prices = { v = 1, markets = { ["Realm|Side"] = { realm, side, at, complete, read, used, n, items = { [itemID] = { p, q, l, t } } } } }`
- `Side` is the auctioneer's faction from `UnitFactionGroup("npc")` at scan time, or `unknown` when the game gives none: a market of its own. Markets are never merged; the view uses the open
  auction house's market, or (house closed) the most recently scanned market of the current realm, and says which in words.
- `p` cheapest unit price in whole copper, `q` items listed at that exact price, `l` buyout listings seen, `t` items in them. Only items the recipes read **at scan time** are kept
  (`S.Wanted`: outputs and materials of this session's recipes), at most 2000 per market and 4 markets (the longest-ago scan goes first). `at` is the scan time; `complete` is the completeness.
- A scan that is not complete never replaces an older complete one (`Commit` answers "kept"); a failed or interrupted scan writes nothing. A newer `prices.v` or `workshop.v` makes everything read-only.
- Not saved: individual auctions, owners, bid-only listings, sale history. Nothing is collected at login or in the background.

**Vendor prices** (milestone 3), `workshop.vendor = { v = 1, items = { [itemID] = { p, s, a, at, npc } } }` (also never in a profile, share or backup): `p` copper for **one purchase of `s` items**, `a` how many the merchant had (-1 unlimited, 0 sold out),
`at` when seen, `npc` the merchant's creature id. Written only while the **Workshop window is shown** (it listens for `MERCHANT_SHOW`/`MERCHANT_UPDATE` only then, and reads a merchant window already open when it opens), only for items that are materials of the queue or of
known recipes, only for listings paid with money alone (an extended cost, a currency or a cost item is skipped, as in `modules/Restock.lua`), at most 400 items (the one seen longest ago goes). The same merchant's newer price replaces the old; another merchant's cheaper price is kept.
A vendor's **sell** value is never read or stored. A newer `vendor.v` makes it read-only.

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
- **Vendor prices:** Opportunities still uses none (it prices from the auction scan only; using the vendor prices there is a possible next task). The NPC collection stores item ids only ("no names, prices or counts"); the vendor **purchase** prices the
  Shopping view uses are the Workshop's own record (Saved data above). A vendor **sell** value is never used as a cost.

## The price scan: what the source says and what it does not (milestone 2)

- **Used:** `C_AuctionHouse.ReplicateItems()`, event `REPLICATE_ITEM_LIST_UPDATE`, `GetNumReplicateItems()`, `GetReplicateItemInfo(i)` (18 values; used: `count`, `buyoutPrice`, `itemID`, `hasAllInfo`),
  `IsThrottledMessageSystemReady()` and the throttle events. **Source-verified:** all of these exist in the target client's API documentation (`AuctionHouseDocumentation.lua`, 1.60.1), and the
  documentation says `ReplicateItems` "should be used in place of an 'allItem' QueryAuctionItems call to query the entire auction house" while search queries are restricted to 100 per minute and "should not
  be used to query the entire auction house". The Forever UI itself **never calls** `ReplicateItems` (the auction house UI is the "Classic family" variant, `AllowLoadGameType: mainline, cata, mists`).
- **Not established by any source here (so nothing assumes it):** how often a full request is allowed, whether the event fires once or repeatedly, whether `buyoutPrice`/`count` are valid when
  `hasAllInfo` is false, whether `ReplicateItems` consumes the throttled-message budget, and what `UnitFactionGroup("npc")` returns for a neutral auctioneer.
- **What the other scanners do (read 2026-11-09, reference only, nothing copied):** Naowh's AuctionPrices and Profession Master (which names WoW Forever) call `ReplicateItems` and act on the **first**
  `REPLICATE_ITEM_LIST_UPDATE` only (they unregister it), read records **0 .. n-1** (TSM's wrapper passes `index - 1`), ignore `hasAllInfo`, keep bid-only listings out, and both say the server allows one full scan
  every 15 minutes (a claim in their comments; not confirmed here, so TwichUI enforces no cooldown). Mastercraft does not use `ReplicateItems` here: it pages an empty browse query (`SendBrowseQuery`, then
  `RequestMoreBrowseResults` until `HasFullBrowseResults`) for each item's lowest price and amount, hooks other searches and stops without saving if one replaces its list, then fetches depth for shopping-list
  items. That browse path is the fallback to build if `ReplicateItems` proves unusable; it is not built.
- **What the code does about that:** sends only when the game says its throttled-message system is ready (else waits up to 30 s, then "wasn't ready"); waits up to 90 s for the first update ("didn't send its
  listings"); reads only after the update has been quiet for 2 s (a steady stream of updates holds the read back at most 10 s); reads records **0 .. n-1** in batches of 400 on timer ticks. **Updates during the read
  never stop or restart it** (the first version treated them as "the listings changed" and failed with "kept changing" after three). Only a different **count** at the end of the read starts it over (at most 3 times); if the
  count never holds still the read is kept as **not complete** (never a failure). If a **wanted** record said it lacked information, waits 4 s and reads again (at most twice) and otherwise **saves the scan as not complete**
  (records of items nobody asked about no longer count). A scan is **complete** only if no wanted record lacked information, the count held still, nothing was cut off (250,000 records,
  the wanted list, 2000 items) and the scan finished. This is a full-house request, **not** a partial search presented as a market scan; if the game refuses it, the scan fails or is unavailable.
- Starts only on the button. Refused (state **unavailable**, nothing sent): auction house not open (`AuctionHouseFrame` shown), API missing, nothing to price (no recipes read), the posting page's own
  search running (`R.AuctionScan.Busy()`), realm unknown, saved prices held by a newer TwichUI. A click while a scan runs does nothing. The posting page is **not changed**: it can still start its own search
  during a scan (it checks the throttle itself); the scan then only waits or fails on the throttle.
- Ends once. **Interrupted** (auction house closed or disabled, mid-wait or mid-read); **failed** (no response, dropped by the throttle, never ready, none, unreadable, request error,
  not saved, not complete while a complete scan exists); **done**. Every timer and step carries a token that ends with the scan, so a callback from an earlier scan never touches a later one. Events are
  registered only while a scan runs. Hiding the Workshop window does not stop a scan; closing the auction house does.
- It never buys, bids, cancels or posts, and calls no function other than the read-only ones above.

## The shopping list: the exact rules (milestone 3)

Pure code (`Shopping.lua`), same inputs always give the same plan; `tests/test_workshop_shopping.lua` covers each rule.
- **Needs** = the queue's materials added up first, **less** what queued crafts will make (above), **less** what the bags hold, once per item. A bag count that can't be read leaves the item out of the list (counted in a note), never as zero.
- **One shared pool of owned items.** The queue's own craft needs take what is owned first. A made material (a "subcraft") draws its reagents from what is **left**, and each reagent spent leaves the pool, so nothing owned is spent twice (a subcraft and a main craft
  competing for one ore: the main craft's need is met first). What a subcraft still lacks is **bought**; all buying of one item is added up and priced once, in one row (the main shortage plus the subcraft's reagents), so cheap listings are not counted twice.
- **One level.** A made material's reagents are bought, never made in turn. Making is also refused when a reagent is itself being made, when another made material already counts the item as a reagent, and when the recipe uses the item it makes (reason shown). Candidate recipes per
  material: at most 4 (by recipe id). Work is bounded by the queue's size (30 recipes x 16 materials); measured with 480 materials x 8 candidates.
- **Output.** Only a **fixed** output (min = max) is used to suggest making: crafts = ceil(short / output) (at most 999), made = crafts x output, **leftover = made - short**, shown. A recipe that makes a range, whose output is unknown, whose materials can't be counted
  (unsupported) or that uses its own output is listed with the reason and is never suggested, and can't be chosen. **Not checked:** cooldowns, tools, crafting stations, whether the recipe was unlearned since it was remembered (Known.lua does not notice that). The tooltip says so.
- **Costs.** *Vendor:* whole stacks (`ceil(n / stack) x price`), leftover shown; if the merchant had fewer when seen it is "limited" (no price). A merchant known to sell it (from the NPC collection) but with no price seen is "price not seen yet", not a price.
  *Auction house:* `Prices.Quote`: **exact** only up to the number of items the scan saw at the cheapest price; beyond that, if enough are listed in all, an **estimate** (the unit price x n is the least it could cost, shown "about" and in the total's "includes estimates");
  if fewer are listed in all, "not enough listed" (no cost); nothing seen: no cost. *Make:* the **economic cost** (reagents bought + owned reagents valued at what they would cost; an owned reagent with no price makes it unknown) is what is compared; the **cash** (only what must be bought) is
  what counts toward spending. Owned materials lower what you spend but are not free for profit.
- **Suggested source** = the lowest known cost among the options; a tie goes vendor, then auction, then making. It compares what is known one material at a time: it does not claim the cheapest plan, and says "looks cheaper", never "cheapest". An auction estimate or a making plan with an
  estimate is marked uncertain. A player's choice is used first (decided before suggestions, so a suggestion never takes its place) and is dropped, with a note, if its option no longer exists.
- **Spending** adds only priced rows. Unpriced rows are counted ("Some prices missing: 2 materials have no price") and the total reads "so far"; it is never shown as complete. Each row shows its price's age ("3 days ago", "(old)" after a day for the auction scan, after 7 days for a vendor price).
- **Recalculation.** Everything is recomputed from the queue, the bags, the saved prices and the saved vendor prices at each draw (queue edits, bag updates, a finished scan, a merchant window, a choice), so a changed observation or choice is simply a new plan.

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
- **Unit-tested (milestone 3, `tests/test_workshop_shopping.lua`, plus a Shopping section of `tests/test_workshop_window.lua`):** queued-craft credit, ranges and circles; `Prices.Quote` exact / estimate / few / none; vendor prices (stacks, limited stock, invalid and corrupt records,
  cheaper-merchant rule, bounds, newer version held); the merchant read (money-only listings, creature id, missing API); two queued recipes sharing a material (one row, bags once); a subcraft competing with a main craft for owned reagents (pool arithmetic: 3 owned, 2 for the main
  craft, 1 for the bars, 7 bought); output rounding and leftovers; buy-versus-make with missing prices, owned unpriced reagents, old prices; insufficient auction quantity; unknown vendor price / stock / location; circular, unsupported, range, chained and over-limit recipes; the cap on work;
  queue edits, bag updates, source choice and cycling, a changed price; **adding a suggested subcraft counts nothing twice and a repeated click adds nothing**; the window (rows, columns, ages, estimates, tooltip, actions, total with and without missing prices, events only while shown, a
  burst of merchant events is one redraw). All with a fake game; none against the real client.
- **Simulator-tested (milestone 3):** `SIMLAB_PAGE=workshop SIMLAB_TITLE=Workshop bash tools/simlab/smoke.sh` passed after the settings page text changed (construction only, 56 of 56 pages). The Shopping view itself is not run in the simulator (no scenario exists for it).
- **Mocked, not real:** all auction results above come from a fake. They show our logic, not what the real auction house returns. No simulator scenario covers the auction house or this view.
- **Real-client-tested:** only that the window opens and works after the anchor fix (reported by the player). Nothing else.

## Not built (decided)

Sale history, "market value", sale rates, external price sources, recursive buy-versus-craft (making is one level), using vendor prices in Opportunities, vendor price collection when the Workshop window is closed, saved source choices, an auction search, a control to forget remembered recipes, noticing dropped professions, bank/mail/alt counts, guild sharing, cooldowns, leveling plans, a recipe-source database, direct crafting buttons, automatic
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
1b. **If it still fails or looks wrong**, right after a scan run `/run print(TwichUI.Workshop.Scan.state, TwichUI.Workshop.Scan.why)` and, for a finished one,
   `/run for k,v in pairs(TwichUI.Workshop.Scan.result or {}) do print(k,v) end`: `updates` is how many `REPLICATE_ITEM_LIST_UPDATE` came, `restarts` how often the count changed under a read, `changed` whether it never held still.
   Also check the index base once: `/run print(C_AuctionHouse.GetReplicateItemInfo(0))` should give a listing and `GetReplicateItemInfo(C_AuctionHouse.GetNumReplicateItems())` nothing (the code assumes 0-based, as the other scanners do; the UI source cannot confirm it).
2. Is the finished scan marked complete (no "may be incomplete" line)? If not, how many records lacked information (`/run print(C_AuctionHouse.GetReplicateItemInfo(1))` shows the 18 values, the last is `hasAllInfo`)?
3. Do the prices match what you see in the auction house for 3 items (cheapest buyout, per item for a stack)? Is a stack's unit price right?
4. `/run print(UnitFactionGroup("npc"))` at a faction auctioneer and at a neutral one (Booty Bay): what comes back? The view says "the Alliance auction house on <realm>" / "the auction house on <realm>" (unknown side).
5. Scan again right away: is it allowed, refused, or does it return the same data? Close the auction house during a scan: it should say it stopped, and keep the earlier prices.
6. After a sale, read the invoice in the mailbox: sale price versus "House cut". If it is the same percentage for that auction house, add its side to `Prices.CUT` (one line and a test).
7. Profit for one craft you know: do the cost, sell price and profit match your own arithmetic (cut not taken off)? Does an output range (makes 1-3) show a low and "to" high? Does hovering show the basis?
8. Does the list stay smooth while reading (no stall) on a large realm? Does `/tui perf` show `workshop.scan` per batch and `workshop.prices`?
9. Do the money columns line up, the coin icons show, and does Shift-click on an icon link into an open chat box?
9b. **Progress and the auction house button:** does the bar fill steadily from asking to reading (no jumps backwards), in the Workshop and on the auction house window (lower right, below the frame; is it clear of other
    addons' tabs and EllesmereUI's skin)? Does pressing either button show progress on both? Does the message stay readable (not cut off) at your UI scale? Does the button vanish with the auction house window?
10. Do the column headings sort (is the order what the line under the list says), do the profession buttons and Profitable only work, and does Add show "Queued" and appear in Crafting?

## In-game checks for the shopping list (milestone 3; none done)

Open the Workshop with a few professions read and a scan done (prices saved), queue two recipes that share a material, then open the **Shopping** view.
1. Does each missing material appear once, with the right "Still needed" (needed - bags)? Drop or gather a material: does the row follow within a moment? Change a craft count: does it follow?
2. Is the spending what you expect for a material you can see at the auction house? Is "estimate"/"about" shown when you need more than the cheapest listing holds? Do the age words match the scan?
3. **Vendor price noting:** with the Workshop open, open a vendor that sells one of the materials. Does the row's Source become Vendor with the price you see in the merchant window (per stack: buy 1 stack, check the total)? Open a vendor that sells for a token/currency/item: is it ignored? `/run for k,v in pairs(TwichUIDB.workshop.vendor.items) do print(k,v.p,v.s,v.a) end` shows what was kept (`C_MerchantFrame.GetItemInfo` fields are source-verified from `MerchantFrameDocumentation.lua` and `modules/Restock.lua`, not yet seen working).
4. **Show vendor:** for a vendor row whose merchant your NPC list knows (visit it first with Vendors and trainers on), does the world map open on the right area with a ring on the marker, and nothing else (no waypoint, no route)? Does the button vanish when no place is known?
5. A recipe that makes one of your missing materials (a bar from ore): does the row say Make (when cheaper) with the crafts, leftover and reagents in the tooltip? Click **Add to queue**: the recipe is queued with those crafts, the row disappears, the ore appears once, and a second click is impossible. Does the Crafting view's Materials agree?
6. Does the Source button cycle suggestion / vendor / auction / make, and does a choice survive a bag update but not an item leaving the list?
7. Does the window read well at your UI scale (the 54-pixel rows, the detail line, the Spending column's age line)? Does `/tui perf` show `workshop.render` and the new gauges `workshop.vendor` and `workshop.picks`?

## Next small tasks (each its own request)

0. **Run the milestone 2 checks above if they have not been itemized, then the milestone 3 checks; fix what they show. Then fill `Prices.CUT` from the invoice.**
0c. (Candidate, small) Use the saved vendor prices in Opportunities' "Cost to make", with the same age and "vendor price" labels; mark unlearned recipes (a way to forget remembered ones) so Make can't suggest one the character no longer knows.
0b. (Done 2026-11-09, `Known.lua`: remembered recipes, see Saved data.) Not done: dropped professions and unlearned recipes aren't noticed; no "Forget remembered recipes" control.

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
