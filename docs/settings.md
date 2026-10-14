# Settings window: structure and conventions

For anyone adding or changing a TwichUI setting. TwichUI's settings live in a window of its own (`/tui options`).
Esc > Options > AddOns > TwichUI is a single page with one button, **Open TwichUI Settings**, that opens that window;
it holds no settings. Workflows with lists, previews or confirmations (sharing, backups, saved data, the pin window,
the troubleshooting report) stay in their own windows and are linked from the settings.

Nothing here has been checked in the game yet; see "In-game checklist".

## Two addons

| Folder | Loaded | Holds |
|---|---|---|
| `!!!TwichUI` | at login | every feature, defaults and saved data (`Persist.lua`), profiles (`Profiles.lua`), what each switch does (`Switches.lua`), and the launcher (`SettingsLauncher.lua`: `R:OpenSettings`, the AddOns entry) |
| `TwichUI_Settings` | the first time the settings are opened (`## LoadOnDemand: 1`, `## RequiredDeps: !!!TwichUI`, no saved variables) | the page descriptions, search, the window and its controls |

The release zip carries both folders side by side (`.pkgmeta` `move-folders`); `tools/deploy.sh` copies both.
`tests/test_settings_package.lua` keeps the two `.toc` files in step (interface, version, files listed).

TwichUI never needs `TwichUI_Settings` to run: switches, profile changes, `R:SetEnabled` and every feature's own
`Get`/`Set` are in the core (`tests/test_settings_lod.lua` runs with it never loaded). If it can't load
(missing folder, turned off in the AddOns list, an error in its files), `R:OpenSettings` says why in chat, returns
`false` and a reason code, and `/tui diagnostics` shows it under Environment. Nothing else is affected.

### What is loaded when

- **At login:** the core as before, minus the old options code. Nothing settings-only is built: no Blizzard
  setting objects, rows, closures or event listeners for the options (the old panel registered 283 settings and
  ~425 rows at login). `SettingsLauncher.lua` registers one canvas category whose few children are made the first
  time it is shown.
- **First open:** `C_AddOns.LoadAddOn("TwichUI_Settings")` (reads and compiles its files), `K.Describe()` (runs
  every page's build function once, producing plain tables: rows, settings, sections; no frames), then the window
  frame, the left-hand list, and the rows of the one page shown.
- **Later:** a page's rows are made the first time that page is shown and kept for the session; showing a page
  again only redraws values and states. Search builds an index from the descriptions the first time something is
  searched for. Nothing runs while the window is shut.
- **Closing** hides the window and puts away sample previews (`R.OnSettingsClosed`). The loaded code and built
  pages stay in memory until a reload; the game can't unload an addon.

This is both: true load on demand (code) and lazy construction (frames per page). No memory or CPU figures are
claimed; see "Measuring".

## Files

| File | Holds |
|---|---|
| `Switches.lua` | Every switch's behaviour: the update to run, whether it needs a reload, whether its feature exists this session (`when`). `W.Set` (the one way to flip a switch), `W.Sync` (after a profile change), `W.ReloadPending` |
| `SettingsLauncher.lua` | `R:OpenSettings(page, setting)`, `R:CloseSettings`, `R:ToggleSettings`, `R.SettingsAnchor()`, `R.OnSettingsClosed(fn)`, the AddOns entry |
| `TwichUI_Settings/Kit.lua` | `K.Page`, the controls pages describe themselves with (`K.Toggle`, `K.Proxy`, `K.ProxyToggle`, `K.Choice`, `K.Dropdown`, `K.Slider`, `K.Swatch`, `K.Checkbox`, `K.Button`, `K.ResetButton`, `K.Link`, `K.Header`, `K.Appearance`), `K.Advanced`, `K.Under`, `K.Badge`, `K.InSection`, `K.Describe`, `K.NavOrder`, `K.SidebarOrder`, `K.Tabs`, `K.ResetPage` |
| `TwichUI_Settings/pages/<Page>.lua` | One page each (some hold a page under it too: Gear + Stat weights, Mage + Refreshment shares, Chronicle + appearance, Pins + appearance) |
| `TwichUI_Settings/Search.lua` | The index and ranking (descriptions only) |
| `Look.lua` (core) | The look TwichUI's own windows share: the palette, `Look.Text`, `Look.Surface`, `Look.Button`, `Look.Checkbox`, `Look.EditBox`, and the depth: `Look.Frame` / `Look.Header` (rim, corner brackets, tonal layers), `Look.Raise` (buttons), `Look.Recess` (inputs, checkbox, nav well), `Look.Panel` (section cards), `Look.Tag`, `Look.Fade` (a gradient that falls back to a flat fill), `Look.Motion`. The sharing window (`setup/Window.lua`) draws with it too |
| `TwichUI_Settings/Widgets.lua` | The shared look as `Wg.*`, plus the controls only this window needs: slider, dropdown and its list, color swatch, the scrolling content area |
| `TwichUI_Settings/Window.lua` | The window, the left-hand list, a feature's tabs, pages, search results, footer, Esc |

The palette lives at the top of `Look.lua` in the core (a copy of the Chronicle's, which is never changed; the sharing window draws with it too), by role:
bronze is crafted structure (rim, brackets, brand, section headings, the selection marker), charcoal is the list and the
header, neutral stone is the page and its cards, ivory is text, one muted teal (`pal.teal`, `tealHi`, `tealLo`) is what
is active (selected row, checked box, focus, slider fill, the one primary button), and rust is `pal.danger`. Interior
edges use `pal.bronzeLo` (neutral gray, despite the name) and a control's own boundary `pal.control`; the rim's old
brown is `pal.rimLo`. A new control takes its colors from these, not from a literal.

Motion is `Look.Motion` (`Wg.Motion`) in `Look.lua`: one table of timings (`TIME`), `Fader` objects that ease a single alpha, and
one driver frame whose `OnUpdate` exists only while a fader is running (none while idle or shut). The window fades in
on opening, a page's cards fade in on arrival (the title and tabs do not), and nav rows, tabs, buttons, dropdowns and
checkbox rows ease a wash under the pointer. Nothing moves or resizes. **Reduce window motion** (Home, saved
`ui.reduceSettingsMotion`, account-wide) makes every ease immediate; it is separate from Notifications' Reduced
motion, which is the cards' and is not read here. Closing, leaving a page, and changing the preference call
`Motion.Settle()` or `fade:Set(1)`, so no alpha is left part-way.

`gear/Window.lua` (Stat weights) and `modules/RefreshmentsShares.lua` (Refreshment shares) stay in the core: each
exposes `Frame()`, built the first time it is shown, which the window shows as a page.

## Pages

```
Home                      feature statuses (each opens its page), Help, General
Everyday                  Notifications, Quality of life, Food and drink, Auction House
Journey                   Journey Chronicle › Appearance, Party pins › Appearance
Gear & class              Gear comparison › Stat weights, Mage (Mages only) › Refreshment shares
Other addons              Addon skins › RestedXP guide window, SpeakStone speech frame
Your configuration        Configuration sharing, Profiles, Troubleshooting
```

`R:OpenSettings(key)` keys: `overview`, `notifications`, `qol`, `food`, `auction`, `chronicle`, `chronicleLook`, `pins`,
`pinsLook`, `gear`, `statWeights`, `mage`, `refreshmentShares`, `skins`, `restedxp`, `speakstone`, `sharing`,
`profiles`, `troubleshooting`. A second argument names a setting (`"arrivalHold"` or `"TWICHUI_arrivalHold"`) or a
row id: the window goes to its page, opens its Advanced section, scrolls to it and marks it for 2.5 seconds (no
animation). An unknown page opens Home; an unknown setting opens the page at its top. No argument reopens the page
shown last.

Each page has a title, one line saying what it is for, its sections (a heading, a sentence or two, and rows), and,
when it has settings with defaults, **Reset this page** at the bottom.

## Adding a page

```lua
K.Page({
    key = "example", name = "Example", order = 85,           -- order: its place within its group
    group = "everyday",                                       -- or parent = "<page key>": a tab of that feature's page
    -- tab = "General",                                       -- optional: a page with pages under it names its own tab
    -- nav = "Appearance",                                    -- optional: a page under another is labelled this in the tabs
    description = "One line under the title.",
    keywords = "other words search should find it by",
    when = function() return R.Example ~= nil end,           -- optional: whether it exists this session
    overview = { label = "Example", tip = "...",              -- optional: its row on Home
        status = function() return K.OnOff(R:Enabled("example")) end },
    build = function(page)
        K.Header("Example", "What it is for.")
        K.Toggle("example", "Do the thing", "What happens, in plain words.")
    end,
})
```

and list the file in `TwichUI_Settings/TwichUI_Settings.toc`. A new switch also needs its line in `Switches.lua`
(what a change does) and its default in `Core.lua`'s `DEFAULT_MODULES`. A page whose build fails says so on the page;
the others are unaffected. Hosted pages give `host = function() return frame end` instead of `build`.

A page with `parent` has no row in the left-hand list: it is a tab beside its parent's (the parent's own settings are
the first, "General" unless it sets `tab`). Its key, its rows and its search results are unchanged; opening it by key or
from a search result shows the parent's row selected and that tab. The tabs are drawn between the page title and its
one-line description, so the title is the feature's name and the line describes the tab shown.

## Rules for a setting

- **Persisted keys never change** for a label or a page move. A setting's variable (`TWICHUI_<name>`), its saved key
  and its default are part of the contract below. Row ids for settings are their names, so search and
  `R:OpenSettings(page, setting)` keep working.
- **The feature owns its data.** Read and write through its `Get`/`Set` (or its switch). A setter validates, refuses
  what it can't use, does nothing when the value is already the same, saves once, and redraws only what the key
  changes. A page never writes `TwichUIDB` itself.
- **Switches** (`K.Toggle(key, label, tooltip)`): what a change does is `Switches.lua`'s. It runs only on a real
  change; a reload is asked for only when the value differs from the one the UI loaded with (in the window: a
  footer notice with **Reload now**; outside it: the usual question). Code elsewhere calls
  `R:SetEnabled(key, on, alreadyApplied)`, never `TwichUIDB.modules[key] = ...`.
- **Reset buttons** (`K.ResetButton`) call the feature's own `Reset` once, then tell each control to show its value.
  They are drawn as ember-outlined buttons, separate from ordinary controls.
- **Reset this page** puts every setting on the page with a default back to it, one at a time through its setter (as
  Blizzard's Defaults did for "this page"). It asks first and names the page and how many settings. It never
  touches map pins, kept pins, the Chronicle, backups, stat weights or profiles (their controls have no default).
- **Advanced:** `K.Advanced(row)` marks a row; `K.Advanced(K.Header(...))` a whole section. A section's Advanced
  rows sit behind **Show advanced options (n)**; an Advanced section is a closed card with **Show**. Opened ones stay
  open for the session. **Show advanced options** on Home (saved `ui.showAdvanced`, account-wide) keeps them all open.
  Essential status, safety and recovery controls are never Advanced. An ordinary row described after an Advanced
  header belongs to the ordinary section before it (`K.InSection` places one elsewhere on purpose).
- **Greyed out:** `K.Under(row, parentRow, isOn, why)`. The row is indented under its parent and says why under its
  label (and in its tooltip) for as long as it is greyed out. The control ignores clicks.
- **Status** in a tooltip or a Home row is a function, read when it is shown: never captured at load, no polling.
- **Reload:** switches that need one show a **Reload** badge.
- **Combat:** the window does not decide. Features apply what they can and defer protected work, coalesced
  (`docs/lifecycle.md`); a section that waits says so (`K.Badge(header, "Waits for combat")`, Food and drink's
  Appearance). Profile changes are refused in combat by `Profiles.lua` itself.

## Search

The index holds every page (name, list name, keywords, description), every section heading and every row with a
label, with a few other words for some (`ALIASES` in `Search.lua`) and the row's tooltip. A query is lowercased plain
text split into words; every word must appear. Label matches rank first (exact, then prefix, then all words), then
page or section matches, then aliases; matches only in a tooltip come last under **Also mentioned in**. At most 60
results. Results show the label, `Page · Section`, and a note when the setting is Advanced, greyed out (and why) or
shown only with other choices. Enter opens the highlighted result, Up/Down move, Esc clears the box first and then
lets go of it. Choosing a result never changes a value or enables anything.

## Esc and keyboard

The window never takes keys unless a box has focus, so play keys work with it open. Esc order: a typing box first
(search clears, then lets go), then the game's dialogs, then TwichUI's open dropdown list, then the window. Through
Forever's `RegisterGameMenuEscHandler` (Menu and AddOn priorities, `Blizzard_GameMenuEsc.lua`); the window steps
aside while the game's color picker is open. Without that API it falls back to `UISpecialFrames`.

## The window

Drag it by its header. It is clamped to the screen and scaled down to fit a small screen (`R.FitToScreen`). Its
place is saved account-wide in `ui.settingsWindow` (`Profiles.ACCOUNT`, so a profile change never moves it). The
footer shows the profile in use and who shares it (click: Profiles page), and **Reload now** while a change waits for
a reload. Colors come from `chronicle/Style.lua` (copied; its own palette is never changed); EllesmereUI is not
needed. Fonts: Cinzel for the titles on Western clients, the game's fonts elsewhere and for all body text.

## Profiles

Values are read through each feature's `Get` whenever a page is drawn, so nothing holds an old profile's table.
After a profile change `Profiles.lua` runs `R.Switches.Sync()` (features follow their switches, with or without the
window) and, if the window is open, redraws the page shown and the footer. See `docs/profiles.md`.

## The contract test

`tests/test_settings_contract.lua` compares the pages with `tests/fixtures/settings_contract.lua`: pages, parents and
groups, `R:OpenSettings` keys, every setting's variable, kind, type, default and label, each page's rows (kind,
label, section, advanced, greyed-out-under, tooltip checksum), what `TwichUIDB` holds after every setting is
changed to another valid value, and after **Reset this page** on every page. After an **intended** change:

```
cd tests && TWICHUI_GENERATE_CONTRACT=1 lua5.1 -e 'require("bit"); ROOT="../"; TESTS="./"' test_settings_contract.lua
```

and review the fixture's diff. The `settings`, `changed`, `changedDB`, `defaulted` and `defaultedDB` sections were
identical before and after the move to the window (the old ones came from Blizzard's own Defaults).

## Measuring (in the game; none of this has been measured yet)

With only TwichUI (and the same other addons) loaded, in the same place:

1. **Login cost.** `/reload`, wait ~30 s, `/run collectgarbage("collect") UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("!!!TwichUI"), GetAddOnMemoryUsage("TwichUI_Settings"))`
   three times; note the lowest. `TwichUI_Settings` should read 0 before the first open. Compare `!!!TwichUI` with the
   previous release (whose options were built at login).
2. **First open.** Open the settings once and repeat step 1: the difference is the settings code plus the window and
   one page. Open every page and repeat: the rest of the pages' rows.
3. **Repeated use.** Open and close the window and walk every page ten times, search a few words; repeat step 1.
   Growth beyond the first full walk points at retained references.
4. **CPU:** `/console scriptProfile 1`, reload, `UpdateAddOnCPUUsage()` / `GetAddOnCPUUsage("TwichUI_Settings")`
   around the first open and around dragging one slider end to end; turn profiling off afterwards.

Libraries shared with other addons are counted to whichever addon loaded them first (TwichUI, as `!!!`).

## In-game checklist

Turn on Display Lua Errors. Test TwichUI alone, then with EllesmereUI. After each group, `/tui diagnostics`.

1. **Packaged install.** From the release zip: `!!!TwichUI` and `TwichUI_Settings` side by side in AddOns; the AddOns
   list shows both. Fresh install (no saved variables) and an upgrade with your normal save.
2. **Never opened.** Play a while without opening settings: every feature works; a profile switch (`/tui options` is
   not needed for it: use another character with another profile) updates looks and switches;
   `/tui diagnostics` says the settings window is not loaded.
3. **Launchers.** `/tui options`, `/tui settings`, `/tui config`, compartment right-click, the Welcome dialog's Open
   Settings, the Chronicle's Options button, the pin window's and pins data bar's settings, the Mage launchers' and
   Refreshments' right-click, `/tui gear` (Stat weights page): each opens the one window at the right page.
4. **AddOns entry.** Esc > Options > AddOns > TwichUI shows a title, one sentence and **Open TwichUI Settings**, and no
   settings. The button opens TwichUI's window and closes the game's options without bringing back the Game Menu.
   With a game setting changed and not applied, the game's window stays and TwichUI's opens in front.
5. **Missing or off.** Turn TwichUI_Settings off in the AddOns list, reload: `/tui options` says it is turned off,
   nothing else errors. Delete its folder: says it is missing.
6. **Every page.** Open each page; values match before the update. Change one control of each kind (checkbox,
   dropdown, slider by dragging and by typing a number, color with OK and with Cancel, button). Long labels wrap,
   nothing is clipped; badges sit after their label.
7. **Advanced.** Show and hide a section's advanced options; an Advanced section's Show/Hide; **Show advanced
   options** on Home keeps them all open on every page.
8. **Greyed out.** Turn Party pins off: its rows grey out with "Needs ..." under each, and don't respond.
9. **Search.** "minimap", "chime", "tomtom", "font", "how long": results from several pages, never-opened pages
   included; Up/Down/Enter; a result in an Advanced section opens it and marks the row; Esc clears, Esc again lets go;
   an empty and a no-match query read sensibly.
10. **Esc order.** With a dropdown list open, Esc closes the list only. With the color picker open, Esc is the
    picker's. With a confirmation open, Esc closes it only. Then Esc closes the window.
11. **Reset this page** on Food and drink: asks, names the page; after accepting, only that page's settings are back
    to their defaults; pins, kept pins and Chronicle entries are as they were. Each feature Reset button still works.
12. **Profiles.** Switch, create, duplicate, copy, rename, delete from the Profiles page: the footer and the page
    follow; a dropdown shows the new names; nothing stale. In combat: refused with a message.
13. **Combat.** Open the window and change Food and Drink's border and size in combat: they apply after combat; opacity
    at once. Nothing errors.
14. **Previews.** Mage menu, refreshments panel, pin menu, new pin window, RestedXP timer bars, SpeakStone sample, the
    Chronicle window: each appears beside the window; closing the window puts away the sample previews (not the real
    windows).
15. **Size and scale.** UI scale 0.64 and 1.15, a 1280x720 window: the settings window fits and can be moved; the
    position is kept after a reload; Stat weights and Refreshment shares fit their page.
16. **Repeated use.** Steps 3 of "Measuring"; no errors; no growing count of frames (`/fstack` spot checks).
17. **Without EllesmereUI.** The window looks complete; with it, nothing changes in the window.
