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

In the repository the two addons are sibling folders under the root, named as they are installed: `!!!TwichUI/`
(`!!!TwichUI.toc`, `Core.lua`, `modules/`, `media/`, `libs/`, ...) and `TwichUI_Settings/`. Tests, tools, docs and
the release workflow stay at the root. The release zip carries both folders side by side (`.pkgmeta`
`move-folders`); `tools/deploy.sh` copies both. File names in these docs (`Core.lua`, `modules/...`) are relative to
the `!!!TwichUI/` folder unless they start with `tests/`, `tools/` or `docs/`.
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
| `TwichUI_Settings/Kit.lua` | `K.Page`, the controls pages describe themselves with (`K.Toggle`, `K.Proxy`, `K.ProxyToggle`, `K.Choice`, `K.Dropdown`, `K.Slider`, `K.Swatch`, `K.Checkbox`, `K.Button`, `K.ResetButton`, `K.Link`, `K.Status` (a read-only line: label, value, a sentence under it), `K.Header`, `K.Card` (a section drawn as a feature card), `K.Appearance`), `K.Under`, `K.Badge`, `K.InSection`, `K.Describe`, `K.NavOrder`, `K.SidebarOrder`, `K.Tabs`, `K.ResetPage`, `K.Changed` (settings that differ from their defaults), `K.ValueText` |
| `TwichUI_Settings/pages/<Page>.lua` | One page each (some hold a page under it too: Gear + Stat weights, Mage + Refreshment shares, Chronicle + appearance, Pins + appearance) |
| `TwichUI_Settings/Search.lua` | The index and ranking (descriptions only) |
| `Look.lua` (core) | The look TwichUI's own windows share: the palette, `Look.Text`, `Look.Surface`, `Look.Button`, `Look.Checkbox`, `Look.EditBox`, and the depth: `Look.Frame` / `Look.Header` (rim, corner brackets, tonal layers), `Look.Raise` (buttons), `Look.Recess` (inputs, checkbox, nav well), `Look.Panel` (section cards), `Look.Tag`, `Look.Fade` (a gradient that falls back to a flat fill), `Look.Motion`. The sharing window (`setup/Window.lua`) draws with it too |
| `TwichUI_Settings/Widgets.lua` | The shared look as `Wg.*`, plus the controls only this window needs: slider, dropdown and its list, color swatch, the scrolling content area |
| `TwichUI_Settings/Previews.lua` | Sample previews: `P.Register`, `P.Host` (create, Play, Reset, Stop, Release), `P.StopAll`, and inert drawing pieces (`P.Popup`, `P.FakeButton`, `P.Portrait`) |
| `TwichUI_Settings/previews/QoL.lua` | Quality of life's samples: summon, resurrection, battleground release, duel request, the Quick Keybind button's place |
| `TwichUI_Settings/Cards.lua` | Feature cards: the head (icon, title, sentence, switch with On/Off), rules line, what to know, Adjust rules, More about this, Play sample |
| `TwichUI_Settings/Home.lua` | The top of Home: Explore features, Adjust appearance, Review changed settings |
| `Icons.lua` (core) | `R.Icons`: every feature icon's file, size and fallback (`docs/settings-icons.md`) |
| `TwichUI_Settings/Window.lua` | The window, the left-hand list, a feature's tabs, pages, search results, footer, Esc |

The palette lives at the top of `Look.lua` in the core (a copy of the Chronicle's, which is never changed; the sharing window draws with it too), by role:
bronze is crafted structure (rim, brackets, brand, section headings, the selection marker), charcoal is the list and the
header, neutral stone is the page and its cards, ivory is text, one muted teal (`pal.teal`, `tealHi`, `tealLo`) is what
is active (selected row, checked box, focus, slider fill, the one primary button), and rust is `pal.danger`. Interior
edges use `pal.bronzeLo` (neutral gray, despite the name) and a control's own boundary `pal.control`; the rim's old
brown is `pal.rimLo`. A new control takes its colors from these, not from a literal.

Motion is `Look.Motion` (`Wg.Motion`) in `Look.lua`: one table of timings (`TIME`), `Fader` objects that ease a single alpha, and
one driver frame whose `OnUpdate` exists only while a fader is running (none while idle or shut). The window fades in
on opening, a page's cards fade in on arrival (the title and tabs do not), nav rows, tabs, buttons, dropdowns and
checkbox rows ease a wash under the pointer, a card's rules and details fade in as they open (`disclose`, 0.18 s), a
search result's mark fades after 2.5 s (`highlight`), and "Saved" fades after a change. Samples play once, for about
three seconds. Nothing moves or resizes, and nothing animates while idle: no moving backgrounds, no animated icons. **Reduce window motion** (Home, saved
`ui.reduceSettingsMotion`, account-wide) makes every ease immediate; it is separate from Notifications' Reduced
motion, which is the cards' and is not read here. Closing, leaving a page, and changing the preference call
`Motion.Settle()` or `fade:Set(1)`, so no alpha is left part-way.

`gear/Window.lua` (Stat weights) and `modules/RefreshmentsShares.lua` (Refreshment shares) stay in the core: each
exposes `Frame()`, built the first time it is shown, which the window shows as a page. A hosted page whose content
grows (Reminders' list and editor) gives `hostHeight` as a function and calls `R.SettingsUI.Refresh()`, on the next
frame, when its height changes; the window reads the height each time it lays the page out.

## Pages

```
Home                      Explore features / Adjust appearance / Review changed settings, Help, General
Everyday                  Notifications, Reminders, Quality of life, Chat cleaning › Channels, Custom rules, Live view, Food and drink, Vendor restocking › Restock items, Auction House
Journey                   Journey Chronicle › Appearance, Cozy Sleeping Bag
Map                       Pins and Pings (Pins, Pings, Appearance), Map Toolbar, World map › Places, Navigation › Appearance, Vendors and trainers › Your list and sharing
Gear & class              Gear comparison › Stat weights, Mage (Mages only) › Refreshment shares, Ammunition warning › Custom ammunition, Class resource bars › Layout, Appearance, Effects
Other addons              Addon skins › SpeakStone speech frame, RestedXP (map waypoint, guide window look, timer bars), Target dragon artwork
Your configuration        Configuration sharing, Profiles, Troubleshooting
```

`R:OpenSettings(key)` keys: `overview`, `notifications`, `reminders`, `qol`, `chatClean`, `chatCleanChannels`, `chatCleanRules`, `chatCleanLive`, `food`, `restock`, `restockItems`, `auction`, `chronicle`, `chronicleLook`, `pins`,
`pinsLook`, `mapToolbar`, `gear`, `statWeights`, `mage`, `refreshmentShares`, `ammo`, `ammoCustom`, `classBars`, `classBarsLayout`, `classBarsLook`, `classBarsEffects`, `skins`, `restedxp`, `speakstone`, `targetArt`, `sharing`,
`profiles`, `troubleshooting`. A second argument names a setting (`"arrivalHold"` or `"TWICHUI_arrivalHold"`) or a
row id: the window goes to its page, scrolls to it and marks it for 2.5 seconds (no
animation). An unknown page opens Home; an unknown setting opens the page at its top. No argument reopens the page
shown last.

Each page has a title, one line saying what it is for, its sections (a heading, a sentence or two, and rows), and,
when it has settings with defaults, **Reset this page** at the bottom. A top-level page names an icon
(`icon = "<R.Icons id>"`) for its row in the list and its tile on Home; the label is always drawn beside it.

**Home** opens with three ways in, side by side; choosing one shows it beneath (kept for the session, never saved):
**Explore features** (every page in the list with its icon and its `overview.status`, each opening its page),
**Adjust appearance** (the Appearance tabs, Addon skins and Target dragon artwork) and **Review changed settings**
(`K.Changed()`: every setting whose value now differs from its default, compared with the feature's own `DEFAULTS` or
`DEFAULT_MODULES`, each opening its control; opening pages or playing samples never counts). Nothing is turned on from
Home and there is no wizard. Help and General follow.

## Feature cards

`K.Card` describes a section that is drawn as one feature (Quality of life is the reference page; the other pages
still use plain sections). It holds no setting and no state of its own: the rows after it are ordinary rows with
their usual ids, tooltips, greyed-out reasons and resets.

```lua
local from
K.Card({
    title = "Accept summons",                                   -- the feature's name
    what = "Accepts a summon from the people you choose ...",   -- one plain sentence, under the title and in search
    summary = function() return K.ValueText(from.data.setting) .. "  \194\183  waits 3 seconds" end,   -- the rules as set
    consequence = "You arrive wherever the summoner stands. ...",  -- always shown, never only in a tooltip
    preview = "qol.summons",                                    -- optional: a Previews id
    details = { { "When does it apply?", "..." } },             -- optional: under "More about this"
    -- inline = true,                                           -- the rules are always shown (no "Adjust rules")
    -- icon = "qualityOfLife",                                  -- optional: an R.Icons id
})
local summons = K.Toggle("qolSummons", "Accept summons", "...")  -- the first checkbox: the card's switch
from = K.Under(K.Choice(...), summons, IsOn, "Turn on \"Accept summons\" to choose who and how long.")   -- a rule
```

The head shows the switch with **On** or **Off** written beside it and, for a moment after a change, **Saved**; under
the sentence, anything the switch is waiting on (a reload, another addon doing the same, why it is greyed out). The
rules line and what to know are always visible. **Adjust rules (n)** and **More about this** open in place (the text
says whether they are open; the chevron agrees); opening changes no setting, and which are open is kept for the
session in the page's view. A rule found by search or a link opens its card first (`Cards.Reveal`), then is scrolled
to and marked. A greyed-out rule says which switch to turn on, in the row itself.

## Sample previews

A preview is a drawing of what a feature does, made of the window's own textures and text with sample names, marked
**SAMPLE**. It never calls a feature's handler or a game action and never writes a setting; it reads the settings it
illustrates when it is reset or played.

```lua
local P = R.SettingsPreviews
P.Register("example.thing", {
    height = 84,
    Sample = function() return { wait = R.Example.Get("wait") } end,       -- read only
    Duration = function(s) return 1.5 + math.min(s.wait, 2) end,            -- or duration = 3
    Create = function(stage, s) local sc = {}; sc.text = R.SettingsWidgets.Text(stage, "small"); sc.text:SetPoint("TOPLEFT", 12, -12); return sc end,
    Reset = function(sc, s) sc.text:SetText("Before") end,
    Update = function(sc, t, s) sc.text:SetText(t < 1 and "Waiting..." or "Done soon") end,
    Final = function(sc, s) sc.text:SetText("After") end,
    Caption = function(s) return "The whole sample in words, the current settings included." end,
})
```

and name it in a card (`preview = "example.thing"`); list a new previews file in `TwichUI_Settings.toc` after
`Previews.lua`. `static = true` makes a still picture (no Play button). A play runs once through the host frame's
`OnUpdate`, set only while it plays; it stops (back to its "before" picture) when the page changes, the window closes
or its frame hides (`P.StopAll`). With **Reduce window motion** on, Play shows the "after" picture at once and the
caption says so. The caption is always there, so nothing is shown only as motion. Working previews: Quality of life's
five cards. Every other page: none yet.

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
- **Reset buttons** (`K.ResetButton`) are a section's reset. They **ask first**: the question is the button's label,
  its tooltip (the feature's own sentence about what is reset and what is kept) and a count made from the settings as
  they are (`K.ResetPlan` / `K.ResetEffects`: "N of the M settings shown here differ from their defaults", plus
  "Turns on / Turns off" for on/off settings and the reload some need). Accepting calls the feature's own `Reset`
  once, then tells each control to show its value. Drawn as ember-outlined buttons, apart from ordinary controls.
- **Reset this page** puts every setting on the page with a default back to it, one at a time through its setter (as
  Blizzard's Defaults did for "this page"). It asks first, names the page and says how many of its settings differ
  from their defaults (counted, never fixed), which on/off settings it turns on or off, and which of those need a
  reload (only when the default is not what this session loaded with: putting back a change that was not reloaded for
  clears it instead). When nothing differs it asks nothing. It never touches map pins, kept pins, the Chronicle,
  backups, stat weights or profiles (their controls have no default). A per-card or per-feature **override** reset
  (Notification appearance › Reset this card) only forgets that override, so the card follows the shared look again.
- **No hidden settings:** every setting is shown, in the section of the controls it relates to (a wait beside the
  option it waits for, a font beside the colour it belongs with). There is no Advanced marking, section or
  preference. `ui.showAdvanced`, saved by the old "Show advanced options", is deleted on load (`Persist.lua`) and
  nothing reads it. Safety gates are separate and stay: the Saved Data Explorer's advanced cleanup is a mode that
  must be turned on and confirmed before anything can be deleted. `K.InSection(row, header)` places a row in a
  section other than the one it was described under (a page's own Reset).
- **Greyed out:** `K.Under(row, parentRow, isOn, why)`. The row is indented under its parent and says why under its
  label (and in its tooltip) for as long as it is greyed out. The control ignores clicks. For a reason that is not a
  parent switch, `row:AddModifyPredicate(fn)` with `row.why` (Profiles: "Profile changes wait until combat ends.";
  the window redraws as combat starts and ends). Wording: "Needs ... turned on" for a parent that is off, "follows
  ..." for inherited, "not available" for a missing addon or class, and "wait until combat ends" for combat.
- **Notes:** `K.Note(row, fn)` puts a short line under a row's label while it is *not* greyed out: what it is doing
  that its label doesn't say. `fn()` returns the sentence and a tone (`"warn"` for something chosen that can't work as
  set, `"reload"` for a change waiting on a reload, nil for quiet). The words carry the meaning, never the color alone.
  In use: a skin that is on without EllesmereUI, Mage selling in EllesmereUI mode while it is unusable (the chosen mode
  is kept, nothing is sold by TwichUI), a data bar entry with no LibDataBroker provider (`K.DataBarNote`; read from
  `DiagStatus.DataBarLibrary()`, the same answer as Troubleshooting). A color swatch's tooltip says which picker a
  click opens (EllesmereUI's, or the game's own when it isn't there); neither is an error.
- **Status** in a tooltip or a Home row is a function, read when it is shown: never captured at load, no polling.
- **Reload:** switches that need one show a **Reload** badge. `Switches.lua` is the one record of what waits
  (`W.IsPending(key)`, `W.ReloadPending()`, `W.PendingReloads()`): a switch is pending only when its value now
  differs from the one this session loaded with (or a Mage launcher is waiting to leave the data bar), so turning it
  back, resetting it, importing, or switching profile clears or sets it correctly, and a click that changes nothing
  waits for nothing. A pending row says "Reload your UI to apply this change." under its label; the footer says "Reload
  your UI to apply: <name> [and N more]." beside **Reload now** (its tooltip lists all). Nothing reloads by itself.
  Troubleshooting's "Reload needed" reads the same record and names. Not every switch needs a reload for the same
  reason: `groupCheck` and `setupSharing` are read live by their handlers (`setup/Group.lua`, `setup/Share.lua`) and
  may not need one; they are left as they were until checked in the game.
- **Combat:** the window does not decide. Features apply what they can and defer protected work, coalesced
  (`docs/lifecycle.md`); a section that waits says so (`K.Badge(header, "Waits for combat")`, Food and drink's
  Appearance). Profile changes are refused in combat by `Profiles.lua` itself.

## Search

The index holds every page (name, list name, keywords, description), every section heading and every row with a
label, with a few other words for some (`ALIASES` in `Search.lua`) and the row's tooltip. A query is lowercased plain
text split into words; every word must appear. Label matches rank first (exact, then prefix, then all words), then
page or section matches, then aliases; matches only in a tooltip come last under **Also mentioned in**. At most 60
results. Results show the label, `Page · Section`, and a note when the setting is greyed out (and why) or
shown only with other choices, and a line saying what it is (a card's own sentence for the card and the settings in
it, else the first sentence of the row's description, or the page's). A card whose switch has the card's name is one
result, not two. Enter opens the highlighted result, Up/Down move, Esc clears the box first and then
lets go of it. Choosing a result never changes a value or enables anything; a rule folded in a card is opened to be
shown. Leaving the results, or clearing the box, returns a page to where it was scrolled.

## Esc and keyboard

The window never takes keys unless a box has focus, so play keys work with it open. Esc order: a typing box first
(search clears, then lets go), then TwichUI's open dropdown list, then the window. Through the game's
`UISpecialFrames` list, with one stand-in entry (`TwichUISettingsEsc`) that closes the list before the window; an
open color picker closes on its own first. The window deliberately does not call `RegisterGameMenuEscHandler`: that
writes into the game's own handler table from addon code, which taints the Esc path and makes the game's
`SpellStopCasting` report `ADDON_ACTION_FORBIDDEN` against TwichUI_Settings.

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
label, section, greyed-out-under, tooltip checksum), what `TwichUIDB` holds after every setting is
changed to another valid value, and after **Reset this page** on every page. After an **intended** change:

```
cd tests && TWICHUI_GENERATE_CONTRACT=1 lua5.1 -e 'require("bit"); ROOT="../"; TESTS="./"' test_settings_contract.lua
```

and review the fixture's diff. The `settings`, `changed`, `changedDB`, `defaulted` and `defaultedDB` sections were
identical before and after the move to the window (the old ones came from Blizzard's own Defaults).

## Measuring (in the game; none of this has been measured yet)

Offline figures for the window (code, page descriptions, pages drawn, search) and a fuller procedure using
`/tui diagnostics memory collect` are in `docs/memory.md`.

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
7. **No hidden settings.** Home has no "Show advanced options". Quality of life shows **Wait before accepting a
   summon** under **Accept summons from** in Summons and resurrection, and **Wait before releasing** under Release in
   battlegrounds; Gear comparison, Notifications, Configuration sharing, Chronicle appearance, RestedXP and
   SpeakStone speech frame show their former Advanced rows in their sections. With an old save that had the option on or
   off, nothing is hidden and nothing errors.
8. **Greyed out.** Turn Party pins off: its rows grey out with "Needs ..." under each, and don't respond.
9. **Search.** "minimap", "chime", "tomtom", "font", "how long": results from several pages, never-opened pages
   included; Up/Down/Enter; a result, including a former Advanced setting, goes to its section and marks the row; Esc clears, Esc again lets go;
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
18. **Reload feedback.** On Home, turn **Custom fonts and sounds** off: the row says "Reload your UI to apply this
    change.", the footer says "Reload your UI to apply: Custom fonts and sounds." beside **Reload now**, and nothing
    reloads. Turn it back on: both go away. Change it again and press **Reload now**: the game reloads and the change
    holds. Switch to a profile that differs from the one you loaded with: the same notice appears and clears the same way.
    Troubleshooting › Reload needed names the same thing.
19. **Reset questions.** **Reset this page** on a page with a changed setting: the question counts what differs, names any
    feature it turns on or off, and says if a reload follows; on a page already at its defaults it asks nothing. A section
    **Reset** (Food and drink › Appearance, Chronicle appearance, ...) asks first and repeats what it keeps. **Reset this
    card** (Notification appearance) makes the card follow the shared look again and leaves the shared look alone.
20. **Unavailable controls.** In combat, the Profiles page's New, Duplicate, Copy, Current and Reset controls grey out
    with "Profile changes wait until combat ends." and wake when combat ends. With Party pins off, its rows say they need
    it. Without a data bar addon, a Mage launcher you turned on says it has nowhere to appear; with it, nothing.
21. **Integrations.** Without EllesmereUI: a skin you turned on says what is missing, and a color swatch's tooltip says the
    game's picker opens; Mage selling set to EllesmereUI marking says nothing is marked or sold until it is usable, and
    the mode stays chosen. With it: the picker is EllesmereUI's; Cancel in it puts the color back.
22. **Import review.** Receive a TwichUI share (or **Test on myself**): the review names the sender and version, the
    profile it changes, "Replaces only the values listed", any features it turns on or off, the reload it needs, what it
    skipped and that Undo keeps the last import. Open the confirmation, then switch profile (or change a listed setting)
    before accepting: it refuses, says to review again, and changes nothing.
23. **Feature cards (Quality of life).** Each card: icon-free head with title, sentence, the switch and On/Off beside it;
    "Saved" appears briefly after clicking the box or the On/Off word. Adjust rules opens and folds the rules (text and
    chevron agree); More about this shows the answers; neither changes a value (Home › Review changed settings stays the
    same). The resurrection card shows "Also accept combat resurrections" without opening anything. With Decline duel
    requests off, its rules say "Turn on "Decline duel requests" to choose exceptions." and don't respond; turning it on
    wakes them at once. Changing Accept summons from updates the Rules line at once.
24. **Samples.** Play sample on each card: it plays once (about three seconds), ends on what happened, and the caption
    describes it. Nothing happens in the game (no summon accepted, no release, nothing in chat). Start one and change
    page or close the window: it stops at once, with no error; coming back shows its "before" picture. With Reduce window motion on: the end at once, with the caption saying so. The portrait is your
    character's face (or the medallions icon if the game gives none).
25. **Search into cards.** "summon delay", "battle res", "block duel": the result says what the feature does; choosing it
    opens the card, scrolls to the setting and marks it once (no mark animation with Reduce window motion on).
26. **Icons.** In the list at UI scale 0.64, 1.0 and 1.15: every icon sits beside its label, crisp enough to tell
    apart, no white or green squares, no halo on the dark list; the selected row stays clear. Home's tiles show the
    64 px art. Rename a file in `media/icons` and reload: the emblem shows instead and the list still works.
27. **Home.** Explore features lists every feature with its status; each opens its page. Review changed settings
    lists exactly what differs from TwichUI's defaults (change one, see it; put it back, it goes) and each opens its
    control. Adjust appearance lists the appearance pages. Switching between them makes no new frames.
28. **Long text.** With a large UI font or a long profile name, card titles, rules lines and Home's tiles wrap or
    end with "..." without overlapping the switch.
