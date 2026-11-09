# Status and backlog

One short entry per feature that has a continuing handoff. Details live in the feature's doc; keep this current instead of adding session notes.

## Workshop (TwichUI_Workshop) - milestones 1 to 3 built, uncommitted on feature/workbench; the window opens and works in game (player-confirmed); milestone 2 reported complete by the player (not itemized); milestone 3 not tried in game

Reference: [docs/workshop.md](docs/workshop.md) (files, saved data, the exact pricing and shopping rules, scan facts and unknowns, client facts, licensing limits, evidence, checks).

- **Built (1, 2):** load-on-demand addon with `/tui workshop`, a data bar menu row and a settings page; recipes of the player's own professions (remembered between sessions), a per-character queue, combined materials against bags; a player-started **Scan prices**
  (one `ReplicateItems` scan, bounded batches, also a button on the auction house window), saved cheapest-buyout prices per auction house, the price service (`Prices.lua`) and the **Opportunities** view (cost, sell price, estimated profit for one craft; no auction house cut applied
  because none is confirmed, and it says so).
- **Built (3, this change):** a **Shopping** view: each missing material once (same combined requirements as Crafting), with a suggested source (**Vendor**, **Auction house**, **Make**), a source button to choose, estimated spending (known subtotal plus "Some prices missing", never a
  falsely complete total), price ages, estimates labelled; quantity-aware auction quotes (`Prices.Quote`: exact / estimate / not enough listed); saved vendor **purchase** prices (`Vendor.lua`, noted only while the Workshop window is shown and a merchant window is open; money-only
  listings; whole stacks); one-level making with rounded-up crafts and leftover shown, one shared pool of owned items, economic cost kept apart from cash; queued crafts count toward what they make (no double counting); **Show vendor** (the NPC collection's find on the world map, only
  for a seen place) and **Add to queue** for a suggested subcraft (explicit; idempotent). Nothing buys, crafts, posts or navigates.
- **Checked:** `luac5.1 -p` on every edited Lua file; unit-tested `tests/test_workshop_shopping.lua` (new), `tests/test_workshop.lua`, `tests/test_workshop_prices.lua`, `tests/test_workshop_window.lua` (new Shopping section); full `./tests/run.sh` result below;
  simulator: `smoke.sh` with the Workshop page passed (construction only; the Shopping view has no scenario). Real client: nothing for milestone 3.
- **Not checked:** everything that needs the game: the merchant reads (`C_MerchantFrame.GetItemInfo` fields), Show vendor on the real map, that quotes match the real auction house, the 54-pixel rows' appearance, performance with a large queue. List: docs/workshop.md "In-game checks for the shopping list".
- **Limitations:** bags only (no bank, mail, alts); recipes are those read or remembered (an unlearned recipe stays until its profession is read again; cooldowns, tools and stations are not checked); vendor prices exist only for materials seen while the Workshop was open at a merchant, and a vendor record is a guide, not proof of stock;
  auction quantity is known only for the cheapest price (more is an estimate); source choices are not saved; Opportunities still prices from the auction scan only; items with random properties are priced by item id only.
- **Next recommended small task:** run the in-game checks (milestone 3 list, and the milestone 2 list if not itemized), fix what they show, then fill `Prices.CUT` from a mailbox invoice. Candidate after that: vendor prices in Opportunities; a way to forget remembered recipes.
- **Blockers:** none. Later milestones (bank/mail/alt counts, guild sharing, cooldowns, leveling) each need a decision recorded in docs/workshop.md first (loading strategy for always-on events; a licensed recipe-source dataset; sharing defaults).
- **Follow-up (unrelated, not fixed):** `tests/test_guild_locations_search.lua` expects `SettingsBroker.BuildMenu` (replaced by `modules/SettingsBrokerMenu.lua` in "Leave me alone mode"); the test needs updating by whoever owns that feature.
- Unrelated: `TwichUI-Workbench-Session-Handoff-2026-11-03.md` at the repository root is about a different project (a task orchestrator); it was not used or changed.
