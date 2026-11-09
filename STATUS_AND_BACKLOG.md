# Status and backlog

One short entry per feature that has a continuing handoff. Details live in the feature's doc; keep this current instead of adding session notes.

## Workshop (TwichUI_Workshop) - milestones 1 and 2 built, uncommitted on feature/workbench; the window opens and works in game (player-confirmed), nothing else tried

Reference: [docs/workshop.md](docs/workshop.md) (files, saved data, the exact pricing basis, scan facts and unknowns, client facts, licensing limits, evidence, checks).

- **Built (milestone 1):** load-on-demand addon with `/tui workshop`, a data bar menu row and a settings page; browse the open own profession's recipes, queue crafts, change
  quantities, remove, Open recipe, combined materials against bags, "Still needed"; per-character saved queue (max 30) that survives reloads and profession switches.
- **Built (milestone 2):** a **Scan prices** button (auction house open, player-started only) doing one full `ReplicateItems` scan in bounded batches with scanning/finished/stopped/failed/unavailable states;
  saved cheapest-buyout prices per auction house (`TwichUIDB.workshop.prices`, bounded); a price service (`Prices.lua`); an **Opportunities** view (cost to make, sell price, estimated profit for one craft,
  sort/filter, basis on hover, Add to the existing queue). Basis: cheapest buyout listing of the newest scan, per item; full materials; ranges for uncertain output; **no auction house cut is applied
  (unconfirmed for this client), so profit is before the cut and says so**; no vendor prices (none stored); unknown inputs make the estimate unknown, never zero.
- **Checked:** syntax (`luac5.1 -p` on every edited Lua file); unit-tested `tests/test_workshop.lua`, `tests/test_workshop_window.lua`, new `tests/test_workshop_prices.lua` (fake auction house and virtual clock); full `./tests/run.sh` = 179 passed, 0 failed;
  simulator: `smoke.sh` with the Workshop page passed (construction only; no scenario covers the new view or the auction house); real client: nothing for milestone 2.
- **Not checked:** everything that needs the game: whether `ReplicateItems` works and how often, whether a scan is marked complete, prices against the real auction house, the auctioneer side for neutral houses, the cut,
  appearance and performance on a large realm. Exact list: docs/workshop.md "In-game checks for the price scan".
- **Limitations:** Opportunities and the scan's item list come from recipes read **this session** (open each profession once after opening the Workshop); the posting page can still start its own search during a scan;
  items with random properties are priced by item id only.
- **Next recommended small task:** run the in-game scan probe/checks, fix what they show, then fill `Prices.CUT` from a mailbox invoice.
- **Opening problem (2026-11-09):** the Workshop window frame was never anchored (no `SetPoint`), so `/tui workshop` showed an invisible window and no message. Fixed in `Window.lua` with a regression test; the player confirmed the window now shows and works (docs/workshop.md, "Opening problem").
- **Blockers:** none for the next task. Later milestones (bank/mail/alt counts, guild sharing, cooldowns, leveling) each need a decision recorded in docs/workshop.md first
  (loading strategy for always-on events; a licensed recipe-source dataset; sharing defaults).
- **Follow-up (unrelated, not fixed):** `tests/test_guild_locations_search.lua` expects `SettingsBroker.BuildMenu` (replaced by `modules/SettingsBrokerMenu.lua` in "Leave me alone mode"); the test needs updating by whoever owns that feature.
- Unrelated: `TwichUI-Workbench-Session-Handoff-2026-11-03.md` at the repository root is about a different project (a task orchestrator); it was not used or changed.
