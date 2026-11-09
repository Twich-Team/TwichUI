# Workshop (TwichUI_Workshop)

For anyone changing the feature. This is the one current reference and handoff for it; `STATUS_AND_BACKLOG.md` has the short status.
**Nothing here has been tried in the game.** Evidence labels (CLAUDE.md) are used throughout: unit-tested, simulator-tested, real-client-tested, not tested.

## What it does (milestone 1)

A window opened with `/tui workshop` (a hidden command, like `/tui perf`: it keeps the help list short and is listed on the Workshop page), the **Workshop...** row of the TwichUI data bar menu, or the Workshop settings page.
- **Recipes** (left): the player's own open profession, with a search, one button per profession seen this session, and per row
  the icon, name, difficulty (Orange/Yellow/Green/Grey, word and colour) and what one craft makes. **Add** queues it.
- **Queue** (right): each recipe with its crafts, `-`/`+` (Shift: five), **Open recipe**, **Remove**; shows crafts and expected output
  ("3 crafts - makes 1-2 each, 3-6 in all"). A recipe whose materials aren't known says "Open profession to update."
- **Materials** (right, under the queue): needed, in bags, **Still needed**, per material, combined over the whole queue first; one sentence under it
  ("Still needed: 2 materials." / "All the materials are in your bags." / "1 recipe can't be counted yet. Open its profession to update.").
  The area says once that it counts **bags only**.
- It never crafts, buys, sells or sends; the queue is finished by hand (Remove). Collection progress is separate from crafting.

## Files

| Where | What |
|---|---|
| `!!!TwichUI/WorkshopLauncher.lua` | core: `R.WorkshopLauncher` (`Load`, `Open`, `Toggle`, `Command`, `Snapshot`); loads the addon on first use, never at login, never in combat (`COMBAT`), plain-words failures like `DiagnosticsLauncher.lua`; scope `workshop.load` |
| `TwichUI_Workshop/` | the addon (`## LoadOnDemand: 1`, `RequiredDeps: !!!TwichUI`, no SavedVariables of its own) |
| `Data.lua` | `R.Workshop` (W): limits, `Plain` (drops secret values), `Int`, `Text`, difficulty words, `PerCraft`, `Expected` (pure) |
| `Materials.lua` | `W.Materials.Rows`: combine first, then apply bag counts once per item; states empty/partial/short/ready (pure) |
| `Queue.lua` | the saved queue (`TwichUIDB.workshop`), checking every record, `Refresh` from an observation |
| `Observe.lua` | game reads: `Read` (own profession list), `Fill` (output + materials from the schematic), `BagCount`, `ItemFacts`, `OpenRecipe` |
| `Session.lua` | in-memory lists per profession, actions and their messages, the rows the window draws (no frames) |
| `Window.lua` | the window (FrameLook, `L.EditBox`, pooled scroll lists); events registered only while shown; marks `W.ready` last |
| `TwichUI_Settings/pages/Workshop.lua` | settings page: works before the addon loads, through the launcher |
| `TwichUI_Diagnostics/*` | memory row, scopes `workshop.load/read/render`, gauges `workshop.*` (see `docs/diagnostics.md`) |
| `.pkgmeta`, `tools/release.py` | packaging (seven folders); `tests/test_release_tools.py` fixtures include it |
| `tests/test_workshop.lua`, `tests/test_workshop_window.lua` | the tests |

## Saved data

`TwichUIDB.workshop = { v = 1, chars = { ["Name - Realm"] = { queue = { entry... } } } }`, account-wide, **never in a profile, share or backup**
(`Persist.CONTAINERS`, `Restore.OWN_LEFT_OUT`, `TwichConfig.LOCAL` as `other`).
`entry = { id (recipe spell), name, crafts (1-999), prof, profName, icon, outMin, outMax, mats = { { item, qty } }, seen }`.
At most 30 entries, 16 materials each. `mats` absent means "not known" (never zero). Reading never writes; an unreadable entry is left out of the
next write. `v` higher than 1 (a newer TwichUI) makes every change refuse with "held" and shows a read-only note. No window position is saved.
It is not a recipe database and keeps nothing for other characters, linked, guild or unqueued recipes.

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
- **Real-client-tested:** nothing.

## Not built (decided)

Auction scanning, prices, profitability, bank/mail/alt counts, guild sharing, cooldowns, leveling plans, a recipe-source database, direct crafting buttons, automatic
queue completion, a saved window position, a Clear queue button, a settings option for opening it from a profession window.

## In-game checks (none done)

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

## Next small tasks (each its own request)

1. Run the in-game checks above and fix what they show (most likely the schematic reads and `GetAllRecipeIDs`).
2. Remember the window position; a "Clear queue" with a question.
3. Bank and mail counts with last-observed times (needs an ownership service; decide the loading strategy first because it needs always-on events).
