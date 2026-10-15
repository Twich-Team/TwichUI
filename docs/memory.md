# Memory and CPU: what TwichUI costs, and how to measure it

For anyone asking why TwichUI's memory figure is what it is, or changing something that might move it. The figures
below were measured **offline** on 2026-10-15 (Lua 5.1 outside the game, `tools/memory_probe.lua`), not in the game.
Nothing here has been measured in WoW: Forever yet; see "Measuring in the game".

## What the game's number is (and isn't)

- `GetAddOnMemoryUsage(name)` (after `UpdateAddOnMemoryUsage()`) is the Lua memory the game puts down to an addon, in
  KB. The Forever API documentation (`Blizzard_APIDocumentationGenerated/PerformanceDocumentation.lua`) lists the two
  functions and says nothing about how memory is attributed. Blizzard's own addon list
  (`Blizzard_AddOnList/AddonList.lua`) calls the update "Expensive" and runs it at most once every 15 seconds.
- **It includes garbage not yet collected.** One reading means little; the figure climbs between collections and
  drops after one. Compare readings taken the same way, after a collection, in the same situation.
- **It leaves out the game's own memory for frames, textures and fonts.** A frame's Lua side (its table and the
  fields the addon sets on it) is counted; the widget behind it is not.
- **Frames are never freed before a reload.** Hiding a frame or dropping every reference to it releases neither
  the widget nor, while the game holds it, its table. Only reusing frames limits how many exist.
- **Shared libraries.** LibStub keeps one copy of each library, and TwichUI (`!!!`) loads first. The library's code
  and tables, and possibly what other addons register in them, appear to count toward the addon that loaded the
  copy in use. This is not documented and has not been checked in the game.
- **Saved variables count toward their addon and are loaded whole at login**, every session, whether or not anything
  uses them that session. An addon's saved data can't be loaded later, except by giving it to a separate
  load-on-demand addon.
- **Closing a window doesn't unload code.** `TwichUI_Settings` is loaded the first time the settings open and stays
  loaded, with every page drawn so far, until a reload.
- **Opening the settings raises `!!!TwichUI`'s figure too.** The settings window draws its text, surfaces, buttons,
  checkboxes, edit boxes and fades with the core's `Look.lua` (`TwichUI_Settings/Widgets.lua` copies it into `Wg`),
  and memory appears to count toward the addon whose code makes it. In the probe (`--by-addon`), about two thirds of
  what drawing pages makes is made by `!!!TwichUI`'s code. Compare `!!!TwichUI` readings only with the settings in
  the same state (never opened, or the same pages drawn).

## Cost map

`tools/memory_probe.lua` loads the addon in `.toc` order under a stand-in for the game and measures the Lua heap after
full collections at each stage. Its stand-in answers most game calls with nothing (no bags, spells or group), so
runtime figures are a floor; code and saved data figures are what Lua 5.1 holds for them. The account figures come
from running it with `--saved` on one account's `!!!TwichUI.lua` (3.7 MB on disk) on 2026-10-15.

| Part | When it exists | Offline heap | Notes |
|---|---|---|---|
| **Saved data, this account** | login to logout | **10.0 MB** | 146,056 stored values: backups (`TwichUIRestoreDB`, 2 points, 89,748 values) 5.5–5.9 MB; your shareable setup (`TwichUIShareDB`, 53,057) 3.3 MB; Journey Chronicle 0.16 MB; settings, profiles and pins (`TwichUIDB`) 0.06 MB |
| … of which two of Attune's tables, kept in the setup and one backup | login to logout | **5.6 MB** | `Attune_Data` (37,698 values) and `AttuneLang` (3,132). In Attune's reference copy these are its built-in data, made by its own files at every load; its saved variables are `Attune_DB`, `AttuneLastViewed` and `TreeExpandStatus`. See "Decisions" |
| Core code: 116 files, 57,500 lines, and what they build when they run | login to logout | 4.4 MB | 3.8 MB of it is compiled code. Largest: `setup/Window.lua` 240 KB, `libs/LibDeflate` 190–210 KB (code and tables), `modules/RestedXPSkin.lua` 180 KB, `setup/ExplorerWindow.lua` 150 KB |
| Start-up and login | login to logout | 0.05 MB / 25 widgets (new install) to 0.12 MB / 145 widgets (this account's switches) | Food and Drink buttons, Mage menus, pins, cards |
| `TwichUI_Settings` code | first settings open to reload | 0.52 MB | 19 files |
| Page descriptions (`K.Describe`) | first open to reload | 0.91 MB | 20 pages, 437 rows: plain tables and closures, no frames |
| Window and the first page | first open to reload | 0.14 MB, about 350 widgets | |
| Every page drawn | each page's first visit to reload | 3.9 MB, about 6,900 widgets (about 3.6 MB without the stand-in's own fields on each widget) | about 16 widgets a row (pixel borders, depth layers) |
| Search index and result rows | first search to reload | 0.5–0.65 MB | at most 60 result rows, reused |
| Ten more rounds of open, every page, close | | 0 | no growth |

Totals in the probe, this account: about **14.6 MB** after login, about **20.8 MB** after every settings page and a
search.

**One in-game reading to check the model against** (2026-10-15, this account, `/tui diagnostics memory collect`, the
settings opened with 13 of 20 pages drawn and no search): `!!!TwichUI` 19,935 KB, `TwichUI_Settings` 2,443 KB. The
probe with `--saved`, `--pages 13` and `--by-addon` puts `TwichUI_Settings` at about 2,300 KB (its code 524, page
descriptions 909, about 50 of the first open and about 815 of the 13 pages), within about 6% of the game's, and puts
about 2,000 KB of those pages on `!!!TwichUI`. So a collected reading before the settings are opened is expected
near 17.9 MB on this account; that has not been read yet. The game's 18–19 MB is consistent with that, plus uncollected garbage and library attribution, but the two
can't be compared directly (different Lua, different counting, frames the stand-in doesn't draw). What remains
unexplained can only be found with in-game readings.

### Lifetimes checked in the source

| What | Kept until | Bound |
|---|---|---|
| Saved Data Explorer: the tree, searches, the exact-share preview, advanced cleanup state | the window closes (`ExplorerWindow` `OnHide` → `EX.Release`) | |
| Cleanup's Undo copy | reload, or the next cleanup | 50,000 values |
| Find settings (a reload, then a scan): a copy of **every** addon table found, ticked or not (`ST.capture`) | the end of that session, so you can tick again and save again | tables over the size cap are listed, not copied |
| Find settings / addon data scan: the list of global names before addons load | the end of the scan (`PLAYER_LOGIN`, or the scan's end) | |
| Addon data sizes (`SD.sizes`) | reload | one entry per addon |
| Gear judgements | gear, talents, level, skills or options change | 300 items |
| Training data | one class built per use; the Mage menus keep their few spells' levels | |
| Notification queue; diagnostic trace; lifecycle codes | until shown or released; Clear; reload | 6; 200 records; 32 kinds |
| Sharing transfers | the next transfer | counters and the offer only; AceComm holds message pieces |
| Quiet login: chat wrapped | 10 seconds after the loading screen | held messages kept for `/tui hidden` |
| `/tui diagnostics memory` | its last reading of the game's count | one number per addon |

### CPU, by reading the source

- **No permanent OnUpdate.** Looks' fades, minimap pins (only while a pin is eligible), the RestedXP current-step
  button (while shown) and job runners (while a job runs) set it and remove it.
- **Bag changes.** Food and Drink, Mage selling's junk marks and Mage refreshments each fold a burst of
  `BAG_UPDATE_DELAYED` into one look of their own, only while switched on. With all three on, a burst means three
  reads of the bags.
- **Tooltips and bag icons** reuse one judgement per item (and its tooltip lines).
- **RestedXP skin.** Its hooks are on RestedXP's refreshes, not its frames' updates. RestedXP's per-frame arrow
  drawing (reference copy, `map.lua` `addon.DrawArrow`) calls none of the hooked functions.
- **Addon messages.** With sharing on, each `CHAT_MSG_ADDON` costs one table lookup.
- **Settings search** ran its match once per keystroke and made a joined copy of each entry's text and tooltip:
  about 132 KB of garbage per keystroke. It no longer joins them (below).

## Changes made in this pass

1. **Settings search** (`TwichUI_Settings/Search.lua`): each word is looked for in an entry's text or its tooltip
   separately, the start-of-label test no longer cuts a substring, and the word-start pattern is made once per query.
   Garbage per keystroke in the probe: about 132 KB before; 2 KB (no match) to 44 KB (many matches) after, the rest
   being the result list. Results, scores and order are unchanged: `tests/test_settings_window.lua` compares them
   with the old method for whole and partial words, many matches, none, and words split between a name and a tooltip.
2. **`/tui diagnostics memory [collect]`** and a **Memory** section in the troubleshooting report
   (`diag/Memory.lua`). Off until used: no events, timers or hooks. It reads the game's count (at most every 15
   seconds in the report; fresh when typed), says how much of the settings window exists, and counts the saved data
   by part. In chat it also names the largest other addons' tables kept in backups and setups. `collect` runs one full
   garbage collection of every addon first, for readings to compare; TwichUI never collects by itself. Counting this
   account's 146,056 values took about 18 ms in the probe. The report never names characters, backups or tables.
3. **`tools/memory_probe.lua`**, the offline probe above (not packaged; `tools/` is ignored by `.pkgmeta`).

## Measuring in the game

Same character, profile, saved data, addons and UI settings for every reading, in a quiet place (a city's inn).
Write down the client build (`/run print(GetBuildInfo())`) and which addons are on.

1. **After login.** `/reload`, wait 30 seconds, then `/tui diagnostics memory collect` three times about 20 seconds
   apart. Note the lowest `!!!TwichUI` figure: the **baseline**. `TwichUI_Settings` should be 0.
2. **Garbage, not retention.** Without `collect`, `/tui diagnostics memory` every few minutes while playing normally
   shows how fast garbage builds; with `collect`, whether anything is kept.
3. **First settings open.** `/tui options`, close it, read with `collect`. Then visit every page, read again; then
   open, visit every page and close ten times and read again. Expect the third reading to equal the second.
4. **Search.** Open the settings, type several queries, close, read with `collect`.
5. **Saved Data Explorer.** `/tui saved`, browse, open the share preview, close, read with `collect`; do it twice
   more. Expect a rise the first time (the window's own frames stay) and none after: what it read is let go.
6. **Notifications.** Preview each card 20 times (settings), read with `collect`; real cards in play the same way.
7. **Sharing.** Export a backup and import it back using a test backup (`/tui restore`), read with `collect`, then
   delete the test backup. Only with data you can lose.
8. **Normal play.** 20 minutes of questing or a dungeon, readings with `collect` at 5 and 20 minutes. A plateau is
   normal; steady growth with nothing new happening is worth a trace.
9. **CPU.** The game's profiler, as in `docs/release-hardening.md` ("Measuring"): `C_AddOnProfiler` metrics for
   `!!!TwichUI` around the same steps.

To turn it off: there is nothing to turn off. The command keeps only its last reading and collects only when
`collect` is typed. If `/console scriptProfile 1` was used for CPU figures, set it back to 0 and reload.

A collection's drop is not an improvement; compare collected readings with collected readings, from the same
steps, and only across a change you are testing.

## Decisions (not made; for the owner)

1. **Attune's built-in data in your setup and backup.** About 5.6 MB of the 10 MB, kept twice. How it was ticked
   can't be told from the data: today's rules would tick `Attune_DB` and leave `Attune_Data` and `AttuneLang`
   unticked. Removing it is your choice and changes what you share: run Find settings (Share setup), untick both
   and save the setup again (a save without a new scan keeps every table it had); a backup can only be deleted whole
   (`/tui restore`), which also removes the other addons' tables in it.
2. **Tables that aren't saved variables.** Find settings lists any table an addon made while loading. Telling saved
   variables apart (for example from the addon's `.toc`, if `C_AddOns.GetAddOnMetadata(name, "SavedVariables")`
   answers in Forever, which is unverified) would keep built-in data out of setups and backups. A behaviour change.
3. **Backups you make yourself have no limit** (already pending in `docs/release-hardening.md`).
4. **Storing backups and your setup packed** (LibSerialize and LibDeflate, as sharing already sends them) instead of
   as tables would hold far less while playing; how much less is unmeasured. It costs unpacking time when a backup is
   previewed, applied or exported, a migration, and the Explorer and cleanup decoding to show contents. Moving them
   to a load-on-demand companion addon's saved variables would keep them out of memory until opened, at a packaging
   cost. Both are designs of their own.

Recommendations without a data decision, by likely value:

- **Settings pages share their rows.** Pages are kept once drawn, and frames can't be freed; reusing rows by kind
  would cap the window at about one page's widgets instead of about 6,900. Risky (stale looks, callbacks bound to
  the page shown before), so only if the in-game reading in step 3 shows it matters.
- **Rarely used windows load on demand.** The sharing window, Saved Data Explorer, cleanup and addon data window are
  about 0.8 MB of compiled code at login. An offer from a friend needs its prompt without the window, so it needs a
  design like the settings window's.
- **One bag read per burst** shared by Food and Drink, Mage selling and Mage refreshments. Measure with the profiler
  first; each look is already coalesced.
- **Other classes' training data builders** (about 0.1 MB) could be dropped after login. Low value.
