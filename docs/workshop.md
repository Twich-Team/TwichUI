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
  Since the bank work (below) it also has **Stored** (what the bank and, if chosen, the guild bank cover: collect it) beside **In bags**, a **Use guild bank** toggle, a scope line ("Counts bags and bank.") and one note when a store was never seen.
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
e.g. "1 material has no price") are always below every known one. **Hovering** a row shows a short tooltip: name, **Cost to make**, **Sell price**, the profit (labelled **Profit before fees** while no auction cut is deducted, **Estimated profit** once one is; the column heading follows),
one status line ("4 hours ago · Partial scan", plus "Old prices" or "Cheapest listing only" when they apply), and "Hold Shift for details". An unknown estimate shows its reason as a warning line and no profit. **Shift** (held on hover, or pressed during it: the window listens for `MODIFIER_STATE_CHANGED` while shown) shows the **details**:
the auction house and scan age, each material with quantity, unit price and total, what it makes and its price, the cut line ("not deducted (not confirmed)" or the rate), the profit, and one line saying these are listings, not sales, and that deposits and unsold listings are not counted.
The **footer** is two short lines: "5 of 7 priced · 4 profitable · profit, highest first" and "Profit is before fees: the auction house's cut isn't confirmed." (plus "Some recipes may be missing." for filtered lists); the long explanation (listing is not a sale, deposits, filters) is behind the **About prices** button's hover. The price line is "Prices: <auction house> · <age> · Partial scan". An output range (e.g. makes 1-3) shows the low amount with "to <high>" under it and sorts/filters by its low end; the maximum is never assumed.
Empty states: no recipes, no prices saved, none could be priced, no profitable craft.
The **Scan prices** button (top right of the view) starts a scan only when pressed; its states are shown in one line (scanning, finished, stopped, failed, unavailable). While a scan runs an **overall progress bar**
(left of the button) shows the whole scan: asking and waiting for the game are the first 8%, the reading the rest (`Scan.Progress`, never backwards within a scan).

**On the auction house window** (`AuctionButton.lua`): the same **Scan prices** button sits under the window's lower right corner, with the same progress bar and message beside it while a scan runs and the last message
(not shown again after the window has been closed) afterwards. It is the same scan (`Session.StartScan`), so either button shows the other's progress. It exists once the Workshop has been loaded this session (the addon is
load on demand, nothing is built at login) and when Blizzard's auction house UI exists; the one event it waits for is dropped once it is made. **Limit:** the scan prices the Workshop's known
recipes (read this session or remembered from earlier ones), so the button works with the Workshop window closed once each profession has been read (with the addon loaded: the window may be hidden); until then it answers "Open the Workshop and one of your professions first".

### Bank and guild bank materials (2026-11-09)

Materials the player keeps in the personal bank or the guild bank are planned with **without being mistaken for what is in the bags**. Nothing is withdrawn, moved, bought or crafted; the Workshop only remembers counts it saw and says where to collect them.
- **Remembered, not live.** A recorder (`Bank.lua`) runs once the Workshop addon is loaded (it is still load on demand: nothing loads it when a bank opens), **with the window hidden**, and saves counts with the time they were seen (`Storage.lua`). A bank open when the addon loads is read at load.
  If a bank was never seen the Crafting/Shopping notes say so: "Open your bank with Workshop loaded to update." Every remembered count is labelled with its age in the tooltips and on collect rows ("seen 2 hours ago"); it is never shown as live stock.
- **Three stores, one allocation.** Bags (read live, bank not included), personal bank, guild bank stay separate numbers. `W.Split` (Data.lua) takes a need from the bags first, then the bank, then the guild bank; Materials, Shopping (the subcraft pool) and Opportunities all call it, so a material cannot be spent twice.
  The personal bank counts by default; **Use guild bank** (saved, off by default, in Crafting and in Shopping) adds the guild bank.
- **Crafting:** columns Need / In bags / **Stored** / Still needed (Stored is the part of the need that storage covers: collect it). The headline distinguishes **"Ready to craft: all the materials are in your bags."** (bags alone) from **"Collect materials: 2 from your bank and 1 from the guild bank."** and from "Still needed: 2 materials. 1 to collect from storage."
  Hovering a material shows bags, bank and guild bank apart, each with its age and why anything is not counted.
- **Shopping:** rows are **Collect from bank** / **Collect from guild bank** (first; no source button, "Already owned", no action), then the rows to buy, then Make. Stored materials lower what is bought (and let a "not enough listed" item become buyable) but never what a craft *costs*: the Make option's economic cost still values an owned reagent at its price wherever it lies. The "Still needed" column is now **To get**.
- **Opportunities:** a row says "Ready to craft" (one craft's materials all in the bags) or "Collect materials" (some in storage); otherwise nothing. Cost to make, sell price and profit are exactly what they were: the full material list is priced, and the availability is carried beside the estimate, never in it (a test and the simulator compare them).
- **Guild bank rules** (`Stock.lua`): counted only when the choice is on, the character is in the guild whose bank it was, the tab was read, is not uncertain, **and this character's own observation of the tab says its rank can take items** (`numWithdrawals ~= 0`). Viewing a tab does not establish that: a tab seen only by another character, one the rank cannot withdraw from, or one whose daily allowance was 0 when seen
  (believed for 6 hours: `Stock.REM_FRESH`, the daily reset time is not known) is shown as information, not counted. A finite or unknown allowance is "potentially withdrawable": counted but flagged ("a withdrawal limit may apply"), the quantity is never promised. Guild stock is shared; counting it is not a reservation. Unread tabs are *not* empty ("2 guild bank tabs not seen yet.").
- **Out of scope:** mail, other characters' banks, guild synchronization, the warband (account) bank, automatic withdrawals.

## Files

| Where | What |
|---|---|
| `!!!TwichUI/WorkshopLauncher.lua` | core: `R.WorkshopLauncher` (`Load`, `Open`, `Toggle`, `Command`, `Snapshot`); loads the addon on first use, never at login, never in combat (`COMBAT`), plain-words failures like `DiagnosticsLauncher.lua`; scope `workshop.load` |
| `TwichUI_Workshop/` | the addon (`## LoadOnDemand: 1`, `RequiredDeps: !!!TwichUI`, no SavedVariables of its own) |
| `Data.lua` | `R.Workshop` (W): limits, `Plain` (drops secret values), `Int`, `Text`, difficulty words, `PerCraft`, `Expected` (pure) |
| `Materials.lua` | `W.Materials.Rows`: combine first, then apply bag counts once per item; states empty/partial/short/ready (pure) |
| `Queue.lua` | the saved queue (`TwichUIDB.workshop`), checking every record, `Refresh` from an observation |
| `Known.lua` | the remembered recipes: `Load` / `Store` of a character's professions (`TwichUIDB.workshop.chars[..].known`), checked on the way in, bounded (pure data, no game calls) |
| `Watch.lua` | reads the player's own open profession while the addon is loaded and the window is **hidden** (one small event frame: `TRADE_SKILL_SHOW`, `_LIST_UPDATE`, `_DATA_SOURCE_CHANGED`, `PLAYER_REGEN_ENABLED`; a burst becomes one read after 0.5 s; also one read at load for an already-open profession), fills in the recipes' details in batches, then lets go of the memory copy; steps aside while the window is shown |
| `Observe.lua` | game reads: `Read` (own profession list), `Fill` (output + materials from the schematic), `BagCount`, `ItemFacts`, `OpenRecipe`, `ReadMerchant` (the open merchant's money-only listings) |
| `Storage.lua` | the remembered bank and guild bank counts (`TwichUIDB.workshop.storage`): checked on the way in and out, bounded, per character (bank) and per guild (guild bank, one record per tab), `u` (uncertain) marks (pure) |
| `Stock.lua` | **the material-availability service** (`W.Stock`): `Sources` (the view: what is planned with, what is information and why), `Counted`/`Fn`, `Craft` (one craft: ready / collect / short / unknown), `Notes`, `Scope`, `Lines` (tooltips) (pure) |
| `Bank.lua` | the recorder: reads the open character bank (tabs are bags) and the shown guild bank tab, only while open, events registered only while open; marks stock pending/uncertain on bag changes; `Pending()`, `Events()`; scope `workshop.bank` |
| `Prices.lua` | **the price service**: stack-to-unit price, the batch that turns auction records into the cheapest buyout per item, the saved scans (`TwichUIDB.workshop.prices`), lookups, price age, the cut table, `Estimate` (cost, sell price and profit of one craft) and `Quote` (what buying n of an item costs: exact / estimate / few / none) |
| `Vendor.lua` | saved vendor **purchase** prices (`TwichUIDB.workshop.vendor`), `Quote` (whole stacks, limited stock), and `Sellers`/`Places` (merchants of the NPC collection that were seen to sell an item) (pure) |
| `Shopping.lua` | the planner `Plan`: one list of what to get and where, the shared pool, making, totals; `Explain`, `Basis`, `Choices` (pure) |
| `Opportunities.lua` | the list: rows, summary, filter, sort, "why unknown" words and the basis lines for the tooltip (pure) |
| `Worth.lua` | **"What's it worth?"** (pure): `Evaluate` (vendor / auction / disenchant for one item, unavailable vs unknown), `Recommend` (the one short suggestion, or why none), `LinkVariant` |
| `WorthLayout.lua` | **the tooltip section as the player arranged it** (pure): the eight line types, the saved layout (`TwichUIDB.ui.workshopWorth`, profile), the layout operations (`Add`/`Remove`/`Move`/`Step`/`SetWhen`), the preview examples, and the ONE builder (`Rows`/`Lines`/`Style`) the live tooltip and the designer share |
| `WorthTip.lua` | the tooltip hook (`TooltipDataProcessor` post call on `GameTooltip`, registered when the addon loads), game reads (item location, binding, stack, info), draws `WorthLayout`'s lines, Shift rebuild, late item information; scope `workshop.worth` |
| `Scan.lua` | the price scan of the open auction house (`W.Scan`): state machine, event frame (registered only during a scan), bounded batches, plain-word messages |
| `AuctionButton.lua` | the progress bar (`W.NewBar`) and the Scan prices button on `AuctionHouseFrame` (`W.AuctionButton`); follows `Scan.Listen` |
| `Session.lua` | in-memory lists per profession, actions and their messages, the rows the window draws, the Opportunities glue (`S.Opportunities`, `S.StartScan`, `S.Wanted`, `S.PriceSource`) and the Shopping glue (`S.Shopping`, `S.PickSource`, `S.CycleSource`, `S.AddSubcraft`, `S.ShowVendor`, `S.ReadMerchant`) (no frames) |
| `Window.lua` | the window (FrameLook, `L.EditBox`, pooled scroll lists); events registered only while shown; marks `W.ready` last |
| `TwichUI_Settings/pages/Workshop.lua` | settings page: works before the addon loads, through the launcher; hosts the tooltip designer |
| `TwichUI_Settings/pages/WorkshopWorth.lua` | **the "What's it worth?" tooltip designer** (`R.WorkshopWorthDesigner`): list of lines, tooltip mockup, drag/click editing; reuses Magic Inventory's virtual drag (`MagicInventoryDrag.lua`) |
| `TwichUI_Diagnostics/*` | memory row, scopes `workshop.load/read/render/scan`, gauges `workshop.*` incl. `workshop.prices` (see `docs/diagnostics.md`) |
| `.pkgmeta`, `tools/release.py` | packaging (seven folders); `tests/test_release_tools.py` fixtures include it |
| `tests/test_workshop.lua`, `tests/test_workshop_window.lua`, `tests/test_workshop_prices.lua`, `tests/test_workshop_shopping.lua`, `tests/test_workshop_memory.lua`, `tests/test_workshop_storage.lua`, `tests/test_workshop_worth.lua`, `tests/test_workshop_worth_layout.lua`, `tests/test_workshop_worth_designer.lua` | the tests |

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
**When recipes are read (refresh rules, 2026-11-09).** Workshop stays load on demand: nothing exists at login and there is no always-on recorder. Once the addon is loaded (the player opened it, or anything asked the launcher to load it), `Watch.lua` reads the player's own open profession
when a profession window opens or its recipe list changes, **with the Workshop window hidden**; the first read happens at load (an already-open profession). While the window is shown it does the same reading itself (`Window.lua`; `Watch` does nothing then), and on opening it reads an already-open valid own profession.
Nothing opens a profession or changes Blizzard's filters. A profession is read only when the game says it is the player's own (not linked, guild, NPC or an unconfirmed view), not while the list is still loading (`IsDataSourceChanging`), not in combat, and not when `IsTradeSkillReady()` says no profession is ready.
**Merge, not replace:** a read adds new recipes and refreshes the ones listed; every remembered recipe the list leaves out (filters, an empty or partial list) stays, in `extra`. A remembered recipe is removed **only when the game lists it with `learned == false`** (`Observe.Read` collects these as `unlearned`);
absence from a list is never evidence. An empty or not-yet-loaded list ("empty"/"busy"/"none"/"not-own") changes nothing. Characters and professions are separate (`chars[key].known[professionID]`). Saved per recipe: id, name, icon, output item and quantities, materials, and per profession the observation time and whether the list was complete.
**Not saved:** difficulty, bag counts, what can be crafted now, cooldowns. They are recalculated (bags are read live; cooldowns, tools and stations are never checked), so a remembered recipe means "previously observed as learned", not "can be made now". The record format is unchanged (older saves load; queue, prices and vendor data are untouched);
a newer `v` is never written. Remembered recipes are not re-read from the game while their profession is closed (the game may not give the details of one that isn't open): they stand until it is read again.
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

**Bank and guild bank records** (2026-11-09), `workshop.storage = { v = 1, useGuild = true|nil, chars = { ["Name - Realm"] = { bank = { u = true|nil, tabs = { [bagID] = { at, n = { [itemID] = count } } } } } },
guilds = { ["Guild-Realm"] = { name, club, nt, at, tabs = { [1..8] = { at, n, by, w, lim, rem, remAt, u } } } } }` (never in a profile, share or backup; `v` newer than 1 or a newer `workshop.v` makes every change refuse with "held"). The bank is **per character** and never added to another's; the guild bank is **per guild** (name and realm; `club` from `C_Club.GetGuildClubId`
when known, a different id under the same name is another guild), **one record per tab**, so two characters of one guild never produce two snapshots to add together: the newer observation of a tab replaces the older. A tab is replaced only by a complete observation, as a whole; a tab never read has no record (unread, not empty). `by`/`w`/`lim`/`rem` are what the *observing character* may do on that tab (`w` 1 can take, 0 cannot;
`rem` stacks left today, -1 unlimited). Bounds: 14 bank tabs, 8 guild tabs, 150 different items per tab (a tab with more is refused whole, never cut: a cut tab would look complete), 1,000,000 per item, 3 guilds (the one observed longest ago goes). Bad saved entries are skipped, never turned into zeros.

## How the bank is read (client facts, Forever 1.60.1 UI source; none verified in the game yet)

- **Personal bank:** the Camelot bank (`Blizzard_UIPanels_Game/Camelot/BankFrame.lua`): tabs are bags listed by `C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)` (bag ids 6 to 14), read with `C_Container.GetContainerNumSlots` / `GetContainerItemInfo` (`itemID`, `stackCount`). Opened through the player interaction manager (`Banker` 8, `CharacterBanker` 67; `AccountBanker` 68, the warband bank, is not read);
  `BANKFRAME_OPENED`/`_CLOSED` are documented and also listened to. Changes: `BANK_TABS_CHANGED(bankType)`, `PLAYERBANKSLOTS_CHANGED(slot)`, `BAG_UPDATE_DELAYED`. `C_Item.GetItemCount(id, includeBank, ...)` defaults to bags only; the Workshop never passes the include flags (a test fails if it does) because the stored counts are added separately.
- **Guild bank:** `GetNumGuildBankTabs`, `GetCurrentGuildBankTab`, `GetGuildBankTabInfo(tab)` (`isViewable`, `numWithdrawals`: 0 means this rank cannot take from the tab; `remainingWithdrawals`: stacks left today, 0 none, -1 unlimited; the game keeps it current only for the shown tab: `Blizzard_GuildBankUI.lua` reads them exactly so), `GetGuildBankItemInfo`/`GetGuildBankItemLink(tab, slot)` (98 slots),
  `GUILDBANKBAGSLOTS_CHANGED` (the shown tab's items arrived or changed; it carries no tab).
- **Trust rules in `Bank.lua`:** personal bank read only while open and only when every slot of a tab read as a whole number or empty; the guild bank only for the shown, viewable tab after the event. The game gives the same empty answer for an empty slot and a tab it has not sent, so an **empty answer is believed only when the same tab was already shown at the previous answer** (a real change); an empty answer right after a tab change, or at load, is not. A non-empty answer cannot come from an unsent tab.
- **Moving materials:** while a bank is open a bag change marks that store *pending* (not planned with) until it is read again; a bank that closes with a change unread, and a guild tab no answer followed (checked 1.4 s after the bag change, unless an answer came within the second before), are saved `u` (uncertain: shown, not planned with) until the next complete read. So a withdrawal or deposit never makes the same items count in the bags and in storage.
  **Not caught:** a visit with the Workshop addon not loaded (the record stays as it was and shows its age; stored counts never produce "Ready to craft", only "Collect materials", so a stale count cannot fake readiness).

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
  opens and constructs, all 55 described pages construct, no Lua error). Construction only; the window itself is covered by `tools/simlab/workshop.sh` ("Simulator coverage" below).
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
- **Simulator-tested (milestone 3):** `SIMLAB_PAGE=workshop SIMLAB_TITLE=Workshop bash tools/simlab/smoke.sh` passed after the settings page text changed (construction only, 56 of 56 pages). The Shopping view is covered by `workshop.sh` (below).
- **Unit-tested (bank and guild bank materials, `tests/test_workshop_storage.lua`, plus a section of `tests/test_workshop_window.lua`):** the one allocation (bags, bank, guild bank; nil/negative/NaN as none); `Materials.Rows` with and without stock; bank by default, guild bank only by choice; unseen/uncertain/pending bank counted as nothing with the first-note sentence; guild permissions (viewable but cannot withdraw, rights unknown, rights seen by another character, allowance 0 recently and hours ago, finite and unlimited allowance, uncertain tab, pending read);
  other guild / same name with another id / not in a guild / id not known yet; records (bounds, oversized and bad tabs refused whole, junk saved data, newer version held, two characters of one guild keep one snapshot per tab, banks per character, a tab the game stops listing goes, partial reads keep the old tab and mark uncertain, an empty tab list erases nothing, at most 3 guilds); the saved choice; Shopping collect rows (bank first, then guild bank, nothing to buy, partial buy priced for what is missing,
  one pool for a queue and its subcraft with exactly the bank's stock spent once, economic cost and cash equal whether the reagent lies in the bags or the bank); Opportunities estimates identical with and without stock and the ready/collect words; the recorder against a fake `C_Bank`/`C_Container`/guild bank API (events registered only while open, no timers or reads while closed, two stacks added, partial tab, delayed update, withdrawal and deposit, close before the read,
  no tab list, bank not viewable, warband bank ignored, bank/guild bank already open at load, guild: empty-after-switch not believed, non-empty believed, unviewable tab, unidentifiable slot, bag change before and after the answer, unanswered bag change, close, another guild, no guild) and a new client on the saved data (times back, ages, the choice, corrupt records). All with a fake game; none against the real client.
- **Mocked, not real:** all auction results above come from a fake. They show our logic, not what the real auction house returns. The simulator scenario below runs the real scan against a fake listing table, which shows the same thing.
- **Real-client-tested:** only that the window opens and works after the anchor fix (reported by the player). Nothing else.

## Simulator coverage (the window itself, 2026-11-09; bank steps added the same day)

**Run it:** `bash tools/simlab/workshop.sh` from the repository root (bash, never zsh; about 30 s; needs the lab, `docs/simulator-lab.md`). Files: `tools/simlab/workshop.sh` (runner), `tools/simlab/scenarios/workshop.lua` (the scenario; its header says exactly what is real and what is fake),
`tools/simlab/workshop_verdict.py` (judges the five launches). It stages `TwichUI_Workshop` through `SIMLAB_EXTRA=TwichUI_Workshop` (an opt-in addition to `simlab_stage`; the other lab commands stage what they always did).
Results and screenshots go to `../wow-ui-sim-lab/artifacts/workshop-<time>/` (`craft.png`, `opps.png`, `shop.png`, `design.png`, `*.stdout`, `*.stderr`); they hold Blizzard art, keep them local.

**What runs for real:** the launcher and `/tui workshop` (the addon loads on demand), every Workshop file, the window and its controls, the saved-data layers (in memory), the price scan state machine, the NPC collection noting a merchant. **What is fake**, at the game-API boundary:
two professions with seven recipes (`C_TradeSkillUI`; no `GetAllRecipeIDs`, as in the Forever source), item names and bag counts (`C_Item`), a 17-listing auction house (`C_AuctionHouse` + a shown `AuctionHouseFrame`), a merchant window (`GetMerchant*`, `UnitGUID/UnitName("npc")`),
and, in the Show vendor step only, **stand-ins for `ToggleWorldMap` and `NpcMap.Locate`** (Blizzard's world map cannot run in the simulator: it raises many Blizzard Lua errors). A 5% auction cut is **test input** for one step (the real cut is unconfirmed; `Prices.CUT` stays empty) and is removed again.
Every expected value is typed from hand arithmetic written beside it in the scenario, never from the code under test.

**Checks per launch: 344 (ends on Crafting), 345 (Opportunities), 346 (Shopping), 345 (the settings window at the tooltip designer); the first 344 are identical in all four** (2026-11-10: includes the step "what's it worth: tooltip designer", about 50 checks, see "The tooltip designer" below; the scenario then uses 28.7 to 29.5 of the lab's 30 simulated seconds, so **no further step fits without a decision about `Lab.BUDGET`**) (2026-11-09 later: includes the 17 checks of the "what's it worth: item tooltip lines" step, see "What's it worth?" below) (2026-11-09: includes the short tooltip, Shift details, the one-line footer, the "remembered recipes: closed window, background read, nothing open" step and four bank steps; in-memory, not a reload). The scenario uses almost all of the lab's 30 simulated seconds (`Lab.BUDGET`, a resource limit): a further step needs a decision about that limit. Layers: *init* (the window opens), *display* (text read from the drawn frames), *click* (`Button:Click()`, **handler level**: no pointer, hit test, focus or keyboard exists in the simulator), *event*
(`A_Admin.FireEvent`: `BAG_UPDATE_DELAYED`, `TRADE_SKILL_LIST_UPDATE`, `MERCHANT_SHOW`, `REPLICATE_ITEM_LIST_UPDATE`), *direct* (a Session function called by the scenario: only the repeated `AddSubcraft`), *state* (queue, saved vendor/price records, picks).
- **Opening/navigation:** opens on Crafting; the three tabs switch views; close, `/tui workshop` again: same view, queue, rows and total.
- **Crafting:** add, `+`/`-`, Remove through the controls; output quantities ("3 crafts - makes 1 each, 3 in all"); two recipes sharing Peacebloom (need 7, bags 4, short 3); bag changes by event (rows, headline); an unreadable count shows Unknown, never ready; an unsupported recipe is never "all in your bags"; a second profession and its chip; Open recipe; empty states.
- **Opportunities:** scan through the real button and state machine (17 records read, 15 used, 12 items priced; bid-only and unwanted listings ignored); cost, sell, profit and "to" ranges for seven recipes; default order, sort by cost and reversal, profession filter, Profitable only; unknown rows with reasons (a missing price, unsupported materials); Add to queue changes the real queue; the test-input cut; scrolling.
- **Shopping:** combined shortages; priced and unpriced rows; the total with its "Some prices missing" warning; the source button cycle (estimate, make, suggestion); buy-versus-make with rounding (5 short, output 2: 3 crafts, 1 left over), a vendor stack (80c for 5 buys 3, 2 left over), an auction estimate and a "not enough listed" row; Add to queue adds the subcraft once, its ingredients appear once, a repeat adds nothing; bag changes update rows and total; Show vendor asks for the map once and calls `Locate` once with the merchant's entry, and sets no waypoint, pin or route; scrolling to the Make row.
- **Bank and guild bank (four steps, fake data):** bank read with the window closed (recorder events only: 8, 11 while a bank is open) and its times; Crafting columns, scope line, headline and order with and without the bank; Shopping collect rows apart from buy rows with exact money; the guild choice through the real toggle (saved), bank first then guild bank, a viewable-but-no-withdraw tab shown as information, a finite allowance flagged, an unanswered bag change making the tab uncertain and the list fall back, a fresh answer bringing it back, off again; a withdrawal (pending, then read, "7/7/-/0": nothing counted twice) and a deposit; Opportunities cost | sell | profit identical before and after the bank, with "Collect materials" / "Ready to craft" / nothing; everything wiped afterwards. The bank is opened with `BANKFRAME_OPENED` (the interaction manager's events would reach Blizzard's own bank frame, which the simulator cannot run; the unit tests cover them). Stand-ins: `C_Bank`, bags 6 and 7, `BankFrame`, `GuildBankFrame`, the guild bank reads.
- **Negative control:** a launch with one expectation made wrong fails on that check and no other.
- **Verdict:** `PASS WITH KNOWN SIMULATOR LIMITATIONS`: the log holds Blizzard's voice-settings error and one refusal of an addon message from `npcs/Share.lua` (the NPC collection sharing the newly noted merchant; the simulator's string rule, classified, not the Workshop).

**Not covered (still needs the real game):** the real recipe interface, real auction and merchant APIs and their timing, the real world map and `Locate`, real pointer and keyboard input (hover tooltips were not read), taint and combat, saved data across a reload (reopening is not persistence), performance with a large queue, how anything looks in the game's fonts (coins are inline textures the simulator does not draw, so amounts read as bare numbers in the screenshots).

**Screenshots (reviewed 2026-11-09, structural only: fonts fall back, coin icons are not drawn, Blizzard's Issue Report button overlaps):** Crafting (4 queued entries, materials with a scroll bar), Opportunities (seven rows, ordered, ranges and Unknown readable), Shopping scrolled to the Make row. Seen: no overlap in Crafting or Opportunities; a long recipe name is cut at its column with no ellipsis (Crafting list, Opportunities row); lists scroll **`design.png` (2026-11-10, reviewed structurally):** the settings window on the Workshop page scrolled to the designer in the Hold Shift preview with Auction value selected: the list of eight lines with check marks, the mockup (tooltip border and background, gold heading, coin values as bare numbers, dim placeholder for the empty disenchant line, bars on the Hold Shift lines, a gold wash on the selected row), the Move up / Move down / Remove and Always / Hold Shift buttons, the caption "Preview data". A grey strip along the mockup's top edge is the simulator drawing the tooltip border's edge texture (the tree shows nothing else there); the long note wraps to two lines (the real client's fonts will differ).
(the Make row is below the fold of the Shopping list until scrolled); **on a Make row the detail text runs to the edge of the Source column and, in the simulator's font, the right-aligned note "materials, counted in their rows" is clipped on its left: check this in the game's font.** Observed, not changed: a Shopping row with no priced option (Silverleaf: "not enough listed") still has an enabled Source button, and one click picks "Auction house" (still Unknown, the total is unchanged).

**For future Workshop changes:** run `workshop.sh` after touching `Window.lua`, `Session.lua`, `Shopping.lua`, `Opportunities.lua`, `Prices.lua`, `Scan.lua`, `Queue.lua`, `Materials.lua` or `Vendor.lua`, and add a check there (with its arithmetic) instead of building a new scenario. The unit tests (`tests/test_workshop*.lua`) stay the main check for logic.

## Not built (decided)

Sale history, "market value", sale rates, external price sources, recursive buy-versus-craft (making is one level), using vendor prices in Opportunities, vendor price collection when the Workshop window is closed, saved source choices, an auction search, a control to forget remembered recipes, noticing dropped professions, mail and alt counts, the warband (account) bank, a recorder that loads the addon when a bank opens (an always-on recorder), a control to forget remembered bank counts, guild sharing, cooldowns, leveling plans, a recipe-source database, direct crafting buttons, automatic
queue completion, a saved window position, a Clear queue button, a settings option for opening it from a profession window.

## Remembered recipes and shorter text (2026-11-09): checks and limits

**Checked:** unit-tested (`tests/test_workshop_memory.lua`, new; plus `test_workshop.lua`, `test_workshop_prices.lua`, `test_workshop_window.lua`): two professions restored in a fresh session with nothing open; Opportunities, Shopping and the price wish list from remembered recipes before any profession is opened; a new recipe merging into saved knowledge;
filtered, empty and no list, linked, guild, NPC, still-loading, combat and nothing-open views leaving saved knowledge unchanged; removal only on an explicit "not learned"; a second character separate; junk, older and newer-version saves; queue and prices intact; nothing live saved; the watcher stepping aside while the window is shown;
the short tooltip (few lines, "Profit before fees", unknown price visible), Shift details through the modifier event, the one-line footer, the heading label. Simulator-tested (`workshop.sh`, handler level, fake game data): the same tooltip/Shift/footer behavior in the real window, a profession opened while the window is closed being saved, and the saved recipes working with no profession open after closing and reopening the window.
Screenshot-reviewed (structural; fonts fall back, coin icons are not drawn): Opportunities header, one-line footer and About prices button fit; nothing clipped.
**Not tested:** `/reload` persistence (a seeded save, a new test client and a window reopen are not a reload), the real `TRADE_SKILL_*` event timing and `IsTradeSkillReady` in Forever, real hover tooltips and the Shift redraw, real fonts.

**Limitations:** knowledge is only as current as the last read of each profession (a recipe the player unlearns is removed only when a read lists it as not learned); `GetAllRecipeIDs` is absent in Forever so lists follow the profession window's filters and a never-browsed filtered-out recipe is unknown; the watcher runs only after the addon has been loaded this session (a session where Workshop was never opened records nothing);
cooldowns, tools and stations are not checked; at most 5 professions and 600 recipes each; no control to forget remembered recipes.

**In-game checks (exact):**
1. Log in, open `/tui workshop` once (this loads the addon), close it. Open each of two professions (do not reopen the Workshop). `/reload`. Open `/tui workshop` **without opening any profession**: both professions appear (chips), Crafting says "Remembered from ...", Opportunities lists their recipes (after a scan), Shopping works from the queue.
2. Before the reload, with the Workshop closed, open a profession with a search/filter active, then clear the filter: no recipe disappears. Learn a recipe, open the profession: it appears and stays after a reload.
3. Open a profession while the Workshop window is hidden, then `/tui diagnostics` or `/tui perf`: the `workshop.read` scope shows reads, no error, no hitch when opening large professions (e.g. 300+ recipes).
4. Open someone else's profession (inspect/link) and a guild profession view: the remembered list is unchanged.
5. Log an alt: it starts with nothing remembered and keeps its own.
6. Opportunities: hover a row (short tooltip, coin icons aligned, no reagent list), hold Shift while hovering and release (details appear/disappear without moving the mouse), check an unknown-price row, the column heading "Profit before fees", the one-line footer, and the **About prices** hover; the text must not clip in the game's font.

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

## In-game checks for bank and guild bank materials (2026-11-09; none done)

Bank (Workshop loaded first: `/tui workshop`, close it; do **not** keep it open):
1. `/dump C_Item.GetItemCount(<item in both bags and bank>)` equals the bags alone and `(<item>, true)` is bags + bank (so the Workshop's bags-only count really excludes the bank). `/dump C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character)` lists bag ids (6, 7, ...) and `C_Container.GetContainerItemInfo(6, 1)` gives `itemID`/`stackCount`.
2. Open the bank at the banker. Within a second, `/dump TwichUIDB.workshop.storage.chars` shows your character with `bank.tabs` and counts that match the bank, with `at`. `/tui perf` shows `workshop.bank`, a small number of calls, no hitch. Does `/run print(TwichUI.Workshop.Bank.IsOpen().bank)` say true while it is open (it listens to the interaction manager's `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` for `Banker` 8 / `CharacterBanker` 67 and to `BANKFRAME_OPENED`; which of them this client sends is not known)?
3. Open `/tui workshop` Crafting with a recipe queued: "Counts bags and bank.", the **Stored** column, the headline "Collect materials: ..." when the bank covers the rest, and the tooltip with the bank's age. With a character that never opened the bank: "Open your bank with Workshop loaded to update."
4. With the bank open: take a stack out and put it back. The material must never count in both places (watch "Stored" and "Still needed" while moving: pending, then correct after about half a second). Close the bank with the stack on the cursor / right after a move: next time the Workshop shows "Your bank may have changed" until the bank is opened again.
5. The warband (account) bank only: nothing is recorded or changed. A bank tab you buy or a tab the game stops listing: the record follows after `BANK_TABS_CHANGED`.
6. With the bank open and the Workshop not yet opened this session, type `/tui workshop` (this loads the addon): is the already-open bank read at load (`/dump TwichUIDB.workshop.storage.chars`)? Does a bank tab with 98 slots read without a visible hitch?

Guild bank (a character with a guild and a bank you can view):
7. Turn on **Use guild bank** (Crafting or Shopping). Open the guild bank on a tab, then another: `/dump TwichUIDB.workshop.storage.guilds` shows one record with `tabs[i]` for the tabs you looked at, `by` your character, `w` 1 on a tab you can take from and 0 on a view-only tab, `rem`/`lim` from `GetGuildBankTabInfo`. Is `numWithdrawals` really 0 for a tab your rank cannot take from, and what do leader and members see (-1?)?
8. A tab that is empty: look at it twice (the second answer is believed) or deposit something: does `GUILDBANKBAGSLOTS_CHANGED` fire for the shown tab only, and after the tab's data arrives (not before)? Does it ever fire for the tab you just left, late?
9. Deposit and withdraw one stack: the Workshop must not show it in both the bags and the guild bank; a tab with no answer after a bag change shows "Some guild bank tabs may have changed."
10. Shopping: guild stock appears as **Collect from guild bank** with "Shared stock" (and "a withdrawal limit may apply" when `remainingWithdrawals` is finite); a tab you can only view appears in the tooltip as "not counted: your guild rank can't take items from that tab". Leave the guild or switch to a character in another guild: nothing of the old guild is counted.
11. `C_Club.GetGuildClubId()` after login: a value, nil, or late? (Only used to tell two guilds of one name apart.)

## What's it worth? (built 2026-11-09: vendor and auction only; DISENCHANT NOT BUILT; tooltip designer 2026-11-10)

**Status: partly implemented, honestly.** The tooltip comparison of **Vendor** and **Auction** exists, with a short **Suggested:** line, and the player can choose and order its lines in a visual **designer** on the Workshop settings page (below). The **Disenchant** estimate does **not** exist: no legally reusable, Forever-appropriate source of disenchant outcomes could be established (below, re-checked: nothing changed), so a disenchantable-looking item shows **"Disenchant (average) | no data"** and a disenchant winner is never named. Nothing invents a chance or a quantity. **The user reported (2026-11-10) that the tooltip works in the real game** (before the designer; not itemized against the checks below). The designer and the new lines are **not real-client-tested**, and real pointer-driven drag-and-drop has never been run.

### Disenchant outcome data: what was checked and why it is blocked

| Candidate | Finding |
|---|---|
| `reference_addons/TradeSkillMaster/LibTSMData/Destroy/Disenchant.lua` | The real, structured table (item class, quality, item level range, `matRate`, min/max amount). Its `LICENSE.md`: **"All rights are reserved by TradeSkillMaster LLC"**; only personal modification is allowed, derivative works, modified sections and distribution are **prohibited** without the owner's express consent ("permission ... is very likely to be granted upon contacting" them: `admin@tradeskillmaster.com`). **Not reusable.** |
| `reference_addons/Mastercraft/ProfData.lua` (`ns.DisenchantResults`, `ns.AllDisenchantMats`), `MatData.lua` text, `Extras.lua` | Structured per-quality / item-level disenchant results and per-material text such as "green / blue items of item level 16-32 (75% of the time)". **No license file** in the folder (the README only licenses a font), so no permission ("no license is not permission"). Its README says the data is "checked against Wowhead Forever's disenchant data": a third party's collected data with its own terms. **Not reusable.** |
| `wow-ui-source` (`forever` branch) | No API or data for disenchant outcomes. The only client evidence is `GetLootRollItemInfo(rollID)`'s `canDisenchant` flag in the group loot frame, which is about a roll, not an item in the bags. `C_Item.GetItemInfo` has no disenchant field. The client cannot be asked "what does this disenchant into". |
| `reference_addons/NaowhForever_Professions/Data/DisenchantValues.lua` (with `Disenchant.lua`, `DisenchantDeals.lua`) | **The only Forever-targeted table found**: "expected Forever disenchant outcomes, skill bands and auction values" (its README calls it "compact classic-era disenchant outcomes"): rows by item level band with material ids, chances and quantities, for uncommon, rare and epic weapons and armour (shirts and tabards never). `NaowhForever/README.md`: "Copyright 2026 the Naowh Forever authors, **all rights reserved**" (only the bundled libraries have their own licenses), and the folder has no license of its own. **Not copied or reproduced here; not reusable without the authors' permission.** Its provenance is not stated, and "classic-era" means it may not be Forever-verified. Useful only as corroboration: Disenchant takes uncommon-to-epic weapons and armour, never shirts or tabards. |
| `Leatrix_Plus`, `NaowhForever` core/`_QoL`, `NaowhForever_SearchIndex` / `_DiscoveryData`, EllesmereUI | Only event names, locale strings, feature descriptions and quest text for the disenchant roll button / window; no outcome data. (`Attune`, `ProfessionMaster`, `WhatsTraining`, `GuildBankSort` and `EUI-RestedXP` have none; `RXPGuides` only mentions disenchanting in a few guide step texts.) |

**Smallest next action (needs the owner's decision; not started):** either (a) ask for written permission for one specific table: the Naowh Forever authors (`github.com/naowh-gaming/NaowhForever`) for `DisenchantValues.lua`, which targets Forever, or TradeSkillMaster LLC for theirs (their license says permission is likely to be granted); or (b) the owner supplies a dataset they have the right to ship, with its provenance, or (c) the player's own logged disenchants are used (a bounded, opt-in recording of real results; this is a data-gathering project and needs approval first). Whichever is chosen, the data must also be checked against **Forever** (item level bands and rates differ between versions), and the tests below for "multiple outcomes and quantities" and "average" get written then, against that table. Until then the code has no disenchant calculation at all (no empty table, no placeholder).

### What it does now

An item tooltip (**GameTooltip only**, for an item in the player's **bags or bank**: the tooltip data must carry a `guid` that `C_Item.GetItemLocation` resolves to a bag slot; links, vendor and auction listings, mail and equipped items get nothing) gets a short section, per item (a stack says "(each)"):

```
What's it worth?
Suggested: Vendor                   (or "Suggested: Auction house" / "Suggested: Disenchant", or a quiet reason why not)
Vendor                              <coin graphics>
Auction (before fees)               <coin graphics>
Disenchant (average)                no data          (only for uncommon-to-epic armour and weapons)
Hold Shift for details              (only when Shift would show something more)
```

That is the **default layout**; the player can change which lines show, their order and when (Always / Hold Shift): see "The tooltip designer". Hold Shift adds, in order: **Scanned | 3 days ago**, **Prices from | <market>** and one **Estimates, not sales. Deposits and failed listings aren't counted.** line.

- **Vendor:** `C_Item.GetItemInfo` sell price, one item. 0 is "no sell value" (an unavailable action), not an estimate of 0.
- **Auction:** the cheapest buyout from the Workshop's saved scan (`Prices.lua`, the same market the window shows: the open auction house's, else this realm's newest), per item, **minus the cut only when `Prices.CUT` confirms it for that auction house side** (it is empty in the product, so today every auction figure is labelled **"before fees"**; a confirmed cut would read **"after fees"**; old prices / a partial scan are added to that label). The tooltip never queries the auction house.
- **The suggestion (`Worth.Recommend`)** compares **estimated proceeds, not guaranteed sales**, and names a winner only when the evidence proves one. Options are the actions that can be done now (a bound item cannot be auctioned; an item with no sell value cannot be sold to a vendor: those are *unavailable*, not unknown). In order:
  1. a competing **price** is unknown (no scan, no listing, unknown vendor value): **"More prices needed"**; a variant: "No suggestion: this variant isn't priced"; unknown listability: "No suggestion: can't tell if it can be listed";
  2. **disenchant** is relevant but has no value (always, today): **"Disenchant value unknown"**, unless vendor and auction compare provably, then the qualified **"Vendor beats auction (disenchant unknown)"** / "Auction beats vendor (disenchant unknown)" (the qualification is part of that line, so it can't be hidden separately; it never says disenchant was weighed);
  3. otherwise **"Suggested: Vendor"** / **"Suggested: Auction house"** / **"Suggested: Disenchant"** (the last only if a disenchant value were ever supplied; no code produces one); equal best values: **"Similar value"**; with the cut unconfirmed the auction value is only a ceiling, so the vendor is suggested when it is at least that ceiling and an auction that looks higher gives **"No suggestion: auction fee unknown"** (a before-fees figure is never presented as take-home proceeds);
  4. one real option and nothing unknown: no line (nothing to compare). Old prices or a partial scan are added in brackets when the line leans on the auction figure.
- **Unavailable vs unknown:** a bound item (`C_Item.IsBound`) or bind-on-pickup / quest item (`bindType` 1 / 4) **cannot be listed** ("can't be listed (bound)"): that is unavailable and blocks nothing. A missing price, an unscanned realm, an unrecognised binding or a variant is **unknown** ("no price", "not scanned yet", "can't tell if it can be listed", "this variant isn't priced") and blocks a best option. Nothing unknown is ever zero.
- **Variants:** the scan keeps **one price per item id** (`Scan.lua` reads `ReplicateItems`, which has no variant key), so an item with a suffix ("of the Bear"), bonus IDs in its link, or an item level that differs from the base is **not priced** from the base item's listings.
- **Shift (details):** the default layout's Hold Shift lines, label/value rows rather than paragraphs: age ("Scanned | 3 days ago", ", partial scan"), the market name once ("Prices from | ..."), and the one exclusion note (only when there is an auction estimate). Hidden when irrelevant (no scan, a variant or an unlistable item shows no price details). Pressing or releasing Shift rebuilds the open tooltip once (`GameTooltip:RefreshData`); Ctrl/Alt do nothing.
- **Repeated updates / tooltip reuse:** the post call runs on every rebuild and a rebuild starts from an empty tooltip, so lines are never added twice; the section is dropped when the tooltip moves to something else. A fault inside the section is caught (`pcall`) so the item's own tooltip and other addons' lines survive, and is reported **once** through `R.Fault`.
- **Late item information:** if `GetItemInfo` has nothing yet, no lines are added, the item is asked for (`RequestLoadItemDataByID`) and `GET_ITEM_INFO_RECEIVED` is registered **only while a tooltip waits** for that one item; it rebuilds once when it arrives (or gives up quietly on a failed load).
- **Load on demand:** the hook exists only after the Workshop addon has been loaded in the session (the first `/tui workshop`); nothing makes it load because a tooltip appeared. The Workshop settings page says so. **Enable tooltip** (in the designer, default on) turns the section off; it is a presentation choice in the layout record, not a core switch.
- **Diagnostics:** scope `workshop.worth` (`Perf.Wrap` around the post call; registered in `DX.OPS`, documented in `docs/diagnostics.md`). No gauge: it keeps no cache, one event frame, and the item-information event only while waiting. The layout builder runs inside that same scope. The designer is a settings page with no recurring work (no timer, no event, one deferred relayout when its height changes), so it gets no scope or gauge; its frames are bounded (8 list buttons, at most 8 mockup rows).

### The tooltip designer (built 2026-11-10)

On the **Workshop** page of the TwichUI settings window, below the "What's it worth?" text. Scope: **only this section** of an item tooltip; no other TwichUI tooltip, Blizzard line or other addon's line is touched.

- **Layout:** a list of the eight line types on the left (Recommendation, Vendor value, Auction value, Disenchant value (average), Price age / status, Price source, Disenchant outcomes, Limits note), a tooltip mockup on the right (a real-tooltip look: the tooltip background and border, the game's tooltip fonts, the coin graphics), a **Normal / Hold Shift** preview selector, an **example** selector, **Enable tooltip** and **Reset layout**, and one instruction: "Drag lines into the preview."
- **Editing:** drag a line from the list into the mockup (a label follows the pointer, a gold insertion marker shows the gap, letting go outside the mockup changes nothing and says "Nothing changed."); drag a mockup row to move it. Alternatives for every drag: **click a line in the list to add it** (at the end); **click a row to select it**, then **Move up / Move down / Remove** and **Always / Hold Shift** for when it shows. No duplicate line types (a second click only selects the existing one). A new line starts **Always** in the Normal preview (so it is seen where you are looking) and with its usual choice in the Hold Shift preview; setting a line to Hold Shift from the Normal preview switches to the Hold Shift preview so the row stays in view. Move up/down steps past the next line **shown in the preview you are looking at**. Rows that have nothing to say for the chosen example (a disenchant row on a trade good, the outcomes line) stay in the mockup as dim "(... nothing to show for this example)" places so they can still be moved or removed; they are the designer's own placeholders and are never in the live tooltip.
- **Same code, preview and live:** the mockup is made by `WorthLayout.Rows`/`Style` over a made-up item (`WorthLayout.Example`, run through the real `Worth.Evaluate`), the tooltip by `WorthLayout.Lines` over the real item: one builder, one set of colours. Examples (labelled "Preview data: a made-up item. Nothing is read from your game."): **Ordinary item**, **Auction looks higher**, **Missing prices**, **Can't be auctioned** (an unavailable action next to an unknown value). No scan or real item is needed, and the examples keep the product's real state (no confirmed cut), so no preview shows something the tooltip cannot.
- **Visibility:** each selected line is **Always** or **Hold Shift**. Shift shows the Always lines plus the Hold Shift lines in the configured order, never twice. "Hold Shift for details" appears only when a Hold Shift line would have something to say. A line with nothing to say is not drawn; with no content at all there is no heading.
- **Qualifications cannot be customised away:** "before fees" / "after fees", "old prices" and "partial scan" are on the **Auction value** row, "(average)" and "no data" on the **Disenchant** row, and "(disenchant unknown)" on the **Recommendation** line itself. The **Limits note** is extra explanation, not the only place a caveat lives. Hiding a row never changes a figure or the suggestion (every line is built from the same evaluation whether shown or not).
- **Saved** at once, in the profile in use: `TwichUIDB.ui.workshopWorth = { v = 1, enabled?, lines = { { id, when = "always"|"shift" }, ... } }`; presentation only (no price, scan or item data; those stay account-wide in `TwichUIDB.workshop`). Missing = the short default; an unusable entry is skipped when read, narrowly, without rewriting the save; the player's own empty list is kept; a table with a **newer** `v` reads as the default and is never overwritten (changes are refused with a sentence). Reset layout removes only `lines` (Enable tooltip stays). Profile changes bring the other profile's layout. It is a `ui` entry like the other presentation settings, so profiles carry it; its place in **configuration sharing** (`TwichConfig.lua`) is a decision, see the status entry.
- **Load on demand:** until the Workshop is loaded the designer is one sentence and an **Open the designer** button, which loads the Workshop through the normal safe launcher (never in combat; no window opens). Hovering an ordinary item never loads anything. There is no second tooltip hook.
- **The drag** is Magic Inventory's virtual drag (`MagicInventoryDrag.lua`): the game's cursor is never touched, and closing the page mid-drag cancels it.
- **Not built:** a text or formula editor; per-line colours; other tooltips; a scan-free "learn disenchant" anything.

### Assumptions to confirm (they are not client facts)

- **Which items "might disenchant"** (so that missing disenchant data blocks a best option): item class Weapon or Armor, quality uncommon to epic, not a shirt or tabard (`INVTYPE_BODY` / `INVTYPE_TABARD`; the exclusion matches the game's rule and the Naowh README, but is not verified in Forever). This is only the reason the `Disenchant (average) | no data` line appears, not a rule of the game; the client offers no per-item eligibility, and other exceptions (items flagged non-disenchantable, other classes in Forever) are not modelled. Nothing says an item **can** be disenchanted, or by whom: the profession/skill and "needs another character" cases cannot arise until a disenchant estimate exists.
- **`bindType` values** 0 none, 1 pickup, 2 equip, 3 use, 4 quest (as in `C_Item.GetItemInfo`'s documentation); any other value is "can't tell". Conjured items, damaged items, containers with items and other listing restrictions are **not** detected (`C_AuctionHouse.IsSellItemValid(itemLocation, false)` exists in the Forever documentation, but whether it answers with the auction house closed is unverified, so it is not used).
- **Variant detection** reads the item link fields `suffix` (7th) and `numBonusIDs` (13th) and compares `GetDetailedItemLevelInfo`'s effective and base item level. Whether Forever puts bonus IDs on ordinary items (which would mark them all as variants, a safe failure) is unknown.

### Verification

- **Unit-tested (`tests/test_workshop_worth.lua`, in `./tests/run.sh`):** vendor and auction values; the cut as a **test input** (5%: 150 -> cut 8, net 142; ties; the vendor winning on an upper bound; an impossible rate ignored); missing price / unscanned market / no sell value / unknown or fractional or negative sell value (never zero); bound, pickup, quest, equip, use and unknown binding; variant links (suffix, bonus IDs, plain, malformed) and a changed item level; disenchant relevant or not by class and quality, **never a number**, blocking a best option; the words (four to six lines, "(each)", old prices and partial scans on the line); the details (source, age, cut, one exclusion line); and, over a fake `GameTooltip`: one section after five rebuilds, tooltip reuse (no guid, equipped, unknown or bad guid, another tooltip), Shift press/release/Ctrl/hidden tooltip, late item information (other item ignored, rebuilt once, listener removed, failed load, tooltip moved on), no auction house access (a trap that errors on any `C_AuctionHouse` use), a fault reported once, TOC order. Mutation checks: weakening the vendor-at-least-the-upper-bound rule, disabling the unknown-competitor rule and breaking the Shift bookkeeping each failed the tests. **Not in the unit tests, because the data does not exist: multiple disenchant outcomes, quantities and the average.**
- **Unit-tested, the designer's pure parts (`tests/test_workshop_worth_layout.lua`):** the suggestion for known, unknown, tied and unavailable options, an unknown cut (before fees: only the vendor can be proven; an auction that looks higher names no winner), missing disenchant data (never a number; the qualified comparison; "Disenchant value unknown"), a disenchant value supplied as a **test input** (suggested, tied, beaten, and not proven better than a before-fees ceiling); add / remove / move / step / set-when and duplicate refusal; Always vs Hold Shift (order, no repeats, the hint, the empty section, a stack); every subset of the eight lines in both modes, each with its qualifications intact and the suggestion unchanged by hiding rows; saved settings (defaults are copies, validation, damaged and older saves, an empty list kept, a saved `false` kept, a newer schema read as default and never written, presentation only); the four examples. Mutation checks (each failed the tests): the move arithmetic, duplicate refusal, the before-fees ceiling rule, the "disenchant unknown" qualification, the "before fees" tag, the hint rule, the newer-schema guard, "Enable tooltip" off, visible-step skipping, gap-to-place mapping.
- **Unit-tested, over stand-in frames (`tests/test_workshop_worth_designer.lua`) and the fake tooltip (`tests/test_workshop_worth.lua`):** the invitation and the load button (refused in combat is said), the list, the mockup equal to the builder for every example in both previews, click-to-add / select / Move / Remove / Always-Hold Shift / Reset layout / Enable tooltip and what they save, the **drag handlers with a faked pointer** (add by drop, move by drop, a drop outside, the marker, the carried row dimmed, hiding the page cancels), no new frames after many redraws, a newer schema refused; and, live: the tooltip draws the layout, Shift press/release with a custom layout shows no repeated or stale lines, Enable tooltip off, a layout change on the next hover, no empty heading.
- **Simulator-tested (`bash tools/simlab/workshop.sh`):** the step "what's it worth: item tooltip lines" calls the product's `WorthTip.OnItem` against the real saved scan with a captured `GameTooltip` and fake item APIs (lines for six kinds of item, a stack, repeat, Shift details, release, a 5% test-input cut and its removal, no auction request); the step "what's it worth: tooltip designer" opens the real settings window on the Workshop page and drives the actual designer controls with `Button:Click()` (**handler level**), compares the mockup with the live tooltip text, calls the drag handlers (`OnDragStart`/`OnDragStop`, pointer position faked: **handler checks, not pointer-driven drag-and-drop**) and the click alternatives. The simulator does not draw tooltips, so **no tooltip screenshot exists**; `design.png` (the settings window at the designer) is a fifth screenshot, which a script cannot judge.
- **Not tested:** everything in the real client (below).

### In-game checks (none done)

1. Load the Workshop (`/tui workshop`), close it, open your bags and hover a plain item you hold (a trade good or a consumable). Do you see "What's it worth?" with Vendor and "Auction (before fees)" or "not scanned yet"? Does the vendor value match what a vendor really pays for **one** item (try a stack)?
2. Hover the same item in a chat link, at a vendor window, in an auction listing and on your character sheet: nothing should be added. Hover it in a bank slot: it should be added.
3. Hold Shift while hovering (and release): the details appear and go away without doubling lines. Does the tooltip also get your gear-upgrade hint's Shift details (both expand on Shift)? Do Ctrl/Alt do nothing?
4. Scan prices at the auction house, then hover an item you hold that is listed: does "Auction" show the cheapest buyout per item and "scanned just now"? Does anything happen at the auction house when you only hover (it must not)?
5. Hover a soulbound item, a bind-on-equip item you have not equipped, and a quest item: "can't be listed (bound)" for the bound ones, a price for the unbound one. Does `/dump C_Item.IsBound(C_Item.GetItemLocation(<guid>))` agree?
6. Hover a green weapon "of the Bear" (random suffix): "this variant isn't priced". Hover a plain green armour piece: "Disenchant (average) | no data" and a "Disenchant value unknown" (or "... beats ... (disenchant unknown)") suggestion, never "Suggested:". If ordinary items are all reported as variants, Forever puts bonus IDs on every item: report it.
7. Hover an item right after login or `/reload` (item information not cached): do the lines appear on their own a moment later without moving the mouse?
8. Does `/dump TooltipDataProcessor ~= nil` hold, and does the tooltip data of a bag item carry `guid` (`TooltipUtil.SurfaceArgs` / `/dump` of the data in a post call)? If not, the section never appears: that is the first thing to check.
9. `/tui perf` capture while hovering bags for a few seconds: the `workshop.worth` scope should be small.
10. The cut: confirm the real cut from a mailbox invoice and fill `Prices.CUT`; the auction figure then loses "before fees" and a winner can be named.

**The tooltip designer (none done):**

11. `/tui` -> Workshop. With the Workshop not loaded yet (`/reload`, then open the page): one sentence and **Open the designer**; hover a bag item first: no section appears (the Workshop is not loaded). Click the button: the designer appears and no Workshop window opens.
12. **Real drag-and-drop (never run on a real pointer):** hold the mouse button on a line in the list and drag into the mockup. Does the label follow the pointer? Does the gold marker jump between rows? Does letting go add the line at the marker? Drag a mockup row up and down: does it move? Let go outside the mockup, on another window, and over the list: nothing changes and "Nothing changed." appears. Does an Esc or closing the settings window mid-drag leave nothing stuck to the cursor? (If the buttons don't start a drag at all, the click alternatives still work: report it.)
13. Click a list line (adds at the end), click a row (selects: gold wash), Move up / Move down / Remove, Always / Hold Shift. Does every change show in the mockup at once, and on the next hover of a real bag item, with no reload? Hold Shift while hovering: your Hold Shift lines join the Always lines, in your order, none twice?
14. Switch the example selector through all four: do "Missing prices" and "Can't be auctioned" read clearly (an unavailable action next to an unknown value)? Is "Auction (before fees)" always on the auction line, and "(disenchant unknown)" on a qualified comparison?
15. **Enable tooltip** off: hover a bag item, nothing added. On again: back. **Reset layout** after rearranging: the short default returns and Enable tooltip stays as it was.
16. Switch profile (Profiles page) to one with a different layout and back: does the designer and the tooltip follow? Does the mockup look like a tooltip next to your tooltip skin (EllesmereUI)? Does the text fit (the long "Auction (before fees, old prices, partial scan)" line wraps in the mockup; a real tooltip widens instead)?

### Limitations

Disenchant is not estimated (above), so "Suggested: Disenchant" can never appear and the disenchant outcomes line is always empty; the auction figure is before fees until `Prices.CUT` is filled, so "Suggested: Auction house" can't appear until then either (the examples show the real state); the designer's mockup is a close imitation, not the game's tooltip (fixed width, wrapping where the game widens); real pointer-driven dragging is untested; only items in bags or the bank, only `GameTooltip`; only after the Workshop has been loaded in the session; prices are the last scan's cheapest buyout (not sales, not per-variant); no deposit or failed-listing arithmetic (stated once in the details); the vendor and auction comparison is advice and assumes a vendor and a posting are available now.

## Next small tasks (each its own request)

0. **Run the milestone 2 checks above if they have not been itemized, then the milestone 3 checks; fix what they show. Then fill `Prices.CUT` from the invoice.**
0c. (Candidate, small) Use the saved vendor prices in Opportunities' "Cost to make", with the same age and "vendor price" labels; mark unlearned recipes (a way to forget remembered ones) so Make can't suggest one the character no longer knows.
0b. (Done 2026-11-09, `Known.lua`: remembered recipes, see Saved data.) Not done: dropped professions and unlearned recipes aren't noticed; no "Forget remembered recipes" control.

1. Run the in-game checks above and fix what they show (most likely the schematic reads and `GetAllRecipeIDs`).
2. Remember the window position; a "Clear queue" with a question.
3b. (Partly done: vendor and auction 2026-11-09; the suggestion and the tooltip designer 2026-11-10) "What's it worth?": see the section above. **Next:** the owner decides how to get legal disenchant outcome data (permission from TradeSkillMaster LLC, a dataset they can ship, or opt-in logging); then add the average, the outcomes line's text and their tests. Independently: run the in-game checks (including real drag-and-drop) and fill `Prices.CUT`.
3. (Done 2026-11-09 for the personal bank and the current guild bank, load on demand: see "Bank and guild bank materials".) Mail and alt counts remain; they need a loading strategy decision.

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
