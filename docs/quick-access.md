# Quick access

The settings window's left-hand list offers up to three shortcuts to the features the current character opens
most. Nothing is configured: there is no page, pin, ordering or explanation. Code: `TwichUI_Settings/QuickAccess.lua`
(learning and choosing, no frames) and `Window.lua` (`UI.Navigate`, `UI.Open`, `BuildNav`). Tests:
`tests/test_settings_quick_access.lua` (the learning) and the last section of `tests/test_settings_window.lua`
(which navigation counts, the list).

## What the player sees

A **QUICK ACCESS** heading after Tools, with up to three rows drawn exactly like the other rows (same item, same
icon, same selection), and a heading tooltip "Features you visit often or recently." With nothing to offer the whole
section is absent. "All features..." stays anchored below the scrolling list, so a small window scrolls the list and
loses neither it nor the fixed groups. The "More features" row (the page on screen when it has no row of its own) now
also skips a page that is a shortcut.

Offered: a top-level page in the Everyday, Journey, Map, Gear & class or Other addons group that is not already in the
fixed groups. Never offered: Home, the configuration group (Profiles, Configuration sharing, Troubleshooting), tab
pages (a tab counts for its parent), pages a build does not have or that failed to describe. New pages are picked up
from the page registry; there is no list to maintain.

## What counts as a visit

`UI.Navigate` is the one route (sidebar rows, Home cards, All features, search, tabs, links, `R:OpenSettings`), so
it is where a visit is counted. Counted: arriving at a *different feature* (the page's top-level root), or opening
the window with `R:OpenSettings(page)` naming a page. Not counted: Home and configuration pages, the fixed features,
the same feature again (a tab, a row on it, a refresh, the row clicked again), `R:OpenSettings()` with no page (the
window returning to where it was left), and a feature again within ten minutes (`QA.COOLDOWN`).

## Scoring

Each counted visit adds 1 to the feature's score; the score halves every 14 days (`QA.HALF_LIFE`), computed from
the stored `{ s, t }` when read, so nothing runs while a feature is unused. A feature is offered at a score of 1.5
(`QA.MIN_SCORE`: in effect a second visit on another occasion), the top three by score. A shortcut already shown keeps
its place unless a challenger scores 25% more (`QA.KEEP`), and shortcuts that stay keep their order, so using one
never moves it. Scores within a tenth are ordered by the shown one, the later visit, then the key.

The list is looked at when the window opens and when a visit is counted, never otherwise.

## Saved data

`TwichUIDB.quickAccess = { v = 1, chars = { ["Name - Realm"] = { seen, f = { [pageKey] = { s, t } } } } }`. Per
character, in the account-wide variable (there is no per-character variable; see `docs/persistence.md`). Outside
profiles, configuration sharing and backups (`Restore.OWN_LEFT_OUT`, `TwichConfig.LOCAL`), so a shared profile does
not share habits. Bounded: 24 features per character, 30 characters (the longest unused goes), a record faded below
0.05 dropped on the next write. Reading never writes; nothing is written while `TwichUIDB` is held; a record with a
higher `v` is never read or changed; a damaged root is replaced by the next counted visit (it holds nothing but a
habit). No schema step: the key is absent until the first counted visit, and an absent key is the empty state.

## Real-client checks (not done)

1. Open settings with a character that has never used it: no QUICK ACCESS heading. Visit Pins and Pings, then
   (after ten minutes) another feature and Pins again: the heading appears with Pins after Tools, without `/reload`.
2. Click the shortcut: the page opens and the row stays where it was. Hover the heading for its tooltip.
3. `/reload`: the shortcut is still there. Log another character: none.
4. Click rows quickly and repeatedly: nothing moves. Reopen with `/tui` (no page): the last page returns and no score
   changes.
5. Shrink the window and the UI scale: the list scrolls, "All features..." stays at the bottom, the selected row is
   scrolled into view.

## Diagnostics coverage

No scope or gauge: there is no timer, event or per-frame work. A counted visit writes a few numbers and prunes at
most 24 records; choosing sorts at most 24; both run on a click or when the window opens.
