# Status and backlog

One short entry per feature that has a continuing handoff. Details live in the feature's doc; keep this current instead of adding session notes.

## Workshop (TwichUI_Workshop) - milestone 1 built, uncommitted on feature/workbench, not tried in the game

Reference: [docs/workshop.md](docs/workshop.md) (files, saved data, client facts, licensing limits, evidence, checks).

- **Built:** load-on-demand addon with `/tui workshop`, a data bar menu row and a settings page; browse the open own profession's recipes, queue crafts, change
  quantities, remove, Open recipe, combined materials against bags, "Still needed"; per-character saved queue (max 30) that survives reloads and profession switches.
- **Checked:** syntax (`luac5.1 -p` on every new/edited Lua file); unit-tested (`tests/test_workshop.lua`, `tests/test_workshop_window.lua`, release fixtures); full `./tests/run.sh` = 177 passed, 1 failed (the failure,
  `tests/test_guild_locations_search.lua:368`, calls `SettingsBroker.BuildMenu`, which does not exist at HEAD either: confirmed on a clean `git archive HEAD` copy; unrelated, left alone);
  simulator-tested: `smoke.sh` with the Workshop page passed (construction only); real client: nothing.
- **Not checked:** everything that needs the game (recipe reads, schematic fields, `GetAllRecipeIDs`, Open recipe, bag counts, appearance). Exact list: docs/workshop.md "In-game checks".
- **Next recommended small task:** run those in-game checks; fix the recipe-read details they show.
- **Blockers:** none for the next task. Later milestones (bank/mail/alt counts, prices, guild sharing, cooldowns, leveling) each need a decision recorded in docs/workshop.md first
  (loading strategy for always-on events; a licensed recipe-source dataset; sharing defaults).
- **Follow-up (unrelated, not fixed):** `tests/test_guild_locations_search.lua` expects `SettingsBroker.BuildMenu` (replaced by `modules/SettingsBrokerMenu.lua` in "Leave me alone mode"); the test needs updating by whoever owns that feature.
- Unrelated: `TwichUI-Workbench-Session-Handoff-2026-11-03.md` at the repository root is about a different project (a task orchestrator); it was not used or changed.
