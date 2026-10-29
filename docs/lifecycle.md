# Start-up, lifecycle and combat

For anyone adding a feature that listens to the game. Code is in `Core.lua` (`R.Life`, the event bus) and each module's
`Refresh`. Nothing here has been verified in the game yet; see "Manual acceptance test".

## Readiness is not "enabled"

| State | Meaning | Where |
|---|---|---|
| Code loaded | the file ran | (implicit) |
| Saved variables validated | `Persist.LoadMain` finished (`ready`) or failed (`failed`) | `R.Life.savedVariables` |
| Configuration ready | defaults filled; start-up hooks may run | `R.Life.configReady` |
| Module initialised | its `R:OnInit` hook ran (`hooksRun`, `hookFailures`) | `R.Life` |
| Module enabled | `R:Enabled(key)` — a *setting*, nothing more | `Core.lua` |
| Logged in | `PLAYER_LOGIN` seen | `R.Life.loggedIn` |
| In the world | between `PLAYER_ENTERING_WORLD` and `PLAYER_LEAVING_WORLD` | `R.Life.InWorld()` |
| Game data available | per feature: bags, item text, zone text, friend info | the module's own check |
| Optional integration usable | loaded *and* its API present | the module |

Start-up hooks run at `ADDON_LOADED`, **before** the world exists. A hook may register events and read saved
settings; it must not read bags, the zone, friends or the player's level as if they were final. Listen for
`PLAYER_ENTERING_WORLD` (or the data's own event) and look again then. No timer stands in for readiness.

`PLAYER_ENTERING_WORLD(isLogin, isReload)` is not a login. Only `isLogin`/`isReload` start a new baseline.

## The event bus (`R:On` / `R:Off`)

A listener may add or remove listeners, itself included, while its event is being delivered. Removal during
delivery marks the slot and tidies afterwards, so every remaining listener runs once, in order. `R:On` with the same
function twice is one registration. Modules still guard with their own `Want(event, handler, wanted)`.

## Rules every module follows

- `Refresh()` is safe to call any number of times: it registers exactly what is wanted and unregisters the rest.
- A delayed callback captures a generation (`pending`, `token`, `generation`, `baselineGen`) or its own object and
  compares it when it runs. Turning the feature off, a profile/setting change, a loading screen or a newer request
  bumps the generation. A callback whose generation is old does nothing (and may `R.Life.Note("cancelled-stale-…")`).
- Hooks that cannot be removed (`hooksecurefunc`, `HookScript`) are installed once and check the module's state.
- Cancelling a display never deletes recorded data. Previews are separate from real notices and never record.
- Pending work is never saved; a reload starts with none.

## Protected operations and their policy

| Operation | Protected in combat? | Policy |
|---|---|---|
| Food/Drink button attributes, size, position of the buttons' parent | yes (secure buttons) | **Defer**, coalesced to the latest state; run on `PLAYER_REGEN_ENABLED` after revalidating the setting. The tooltip says a change is waiting. |
| Food/Drink place from EllesmereUI's Unlock Mode (docs/food-drink-unlock.md) | the buttons' parent: not documented; EllesmereUI's anchor frame: no | EllesmereUI moves a **separate plain anchor**; the buttons' parent follows it **out of combat only**. In combat only the fact is kept (`unlock-deferred-combat`); at the end the parent goes to wherever the anchor is then. Dropped when the option or buttons are turned off. |
| Mage menu rows, shift-click cover | yes | **Reject** opening in combat; close at combat start (or when it ends); cover is put away out of combat only |
| Mage refreshments panel and its conjure buttons | yes (secure buttons) | **Reject** opening in combat; close at combat start (or when it ends). The buttons' spell **defers** to `PLAYER_REGEN_ENABLED`; turned on in combat, they are made when it ends (docs/refreshments.md) |
| Quick Keybind (`QuickKeybindFrame:Show()`) | yes | **Disable** the button in combat with the reason; never deferred (it must be the player's click) |
| Selling ordinary food and drink (`UseContainerItem` at a merchant; docs/mage-sell.md) | not documented | **Never started or continued in combat**; a run stops when combat begins, the merchant closes, another merchant opens, or the feature or an option changes. Whether the game allows an addon's sale is checked in the game: a block ends the run and stops automatic runs until reload. |
| Cards, movers, tooltips, the notification coordinator | no (plain frames) | act at once; previews clear at combat start |
| Chronicle window, note editor and date picker (their appearance) | no (plain frames) | one coalesced pass while open, none while closed; a waiting pass is dropped when the window closes (docs/chronicle-appearance.md) |
| `BNToastFrame` event list | no | act at once |
| Settings previews, apply/restore/reset buttons | n/a | **Reject** in combat with a message |
| Profile switch, New, Duplicate, Copy settings from, Reset (docs/profiles.md) | they re-apply the whole configuration, secure Food and Drink buttons included | **Reject** in combat in `Profiles.lua` itself, rechecked when a confirmation is accepted; Rename and Delete change no option and are allowed. A character named only at login switches after combat |

Mocked tests cannot show combat lockdown, protected-frame errors or taint. Those need the game.

## Reason codes (`/tui diagnostics` → "Start-up and lifecycle")

`waiting-for-world`, `deferred-combat`, `cancelled-stale-baseline`, `cancelled-stale-transfer`, `transfer-settled`,
`friend-bnet-baseline`, `friend-bnet-disconnected`, `init-failed`, `onboarding-waited`, `onboarding-load-failed`, `cancelled-stale-refreshments`,
`refreshments-reset-manual`, `refreshments-reset-left-group`, `trade-place-not-shown`, `trade-split-not-seen`,
`trade-not-completed`, `trade-move-blocked`, `trade-auto-blocked`, `trade-auto-limit`, `trade-auto-stopped-by-you`,
`trade-place-refused`, `cancelled-stale-mage-sell`, `unlock-deferred-combat`, `unlock-save-ignored`,
`unlock-save-refused`, `unlock-register-failed`, `profile-apply-failed`. Counts only; no names, places or items.

## Manual acceptance test

Test TwichUI alone first, then with EllesmereUI. After each step, check `/tui diagnostics` and that no Lua error or
"action blocked" message appeared. Turn on **Display Lua Errors** in the game's options.

1. **Fresh login and reload.** Log in with Food and Drink, zone cards, friend card and Welcome Back on. *Expect:* no
   zone card and no Chronicle "Arrived" entry for where you stood; Welcome Back once after a real login, not after
   `/reload`; Food/Drink buttons appear with the right items once the world loads; report shows "in the world: yes".
2. **Loading screens.** Take a flight path, walk into a dungeon, hearth, repeat several times quickly. *Expect:* one
   zone card for the final place; no card replayed after a screen; no entry for towns passed over on the flight.
3. **Death, ghost, resurrection.** Die, release, run back, resurrect. *Expect:* Food/Drink buttons keep their items
   (they stay clickable; the game decides if the click works); a Chronicle zone entry only if the graveyard is in
   another zone; no duplicates.
4. **Food/Drink around combat.** Note the shown items; start combat; eat/drink or buy an item. *Expect:* buttons keep
   their icon, count and click action during combat; the tooltip says a change is waiting; after combat they update
   once. The click always uses the item shown.
5. **Inventory change with an update pending.** In combat, change bags twice. *Expect:* one update after combat,
   reflecting the latest bags.
6. **Same setting changed repeatedly in combat.** Change button size three times in combat. *Expect:* nothing moves in
   combat; after it the buttons use the last value only.
7. **Disable with pending work.** In combat change a Food/Drink setting, then turn Food and Drink off. *Expect:* after
   combat nothing reappears. Turn it on again: buttons build once.
8. **Profile switch with things open.** Switch a TwichUI profile (Options > Profiles), and separately an EllesmereUI
   profile, with the settings window, a preview card and a mover open. *Expect:* nothing stuck on screen, no stale tooltip.
9. **Repeated enable/disable.** Toggle Zone card, Friend login, Welcome Back, Food/Drink and Chronicle zones 5 times
   each. *Expect:* each behaves as one copy (one card, one chime, one entry).
10. **Friends.** Log in with friends already online: no cards. A friend who signs in later gets one card and one
    chime. Disconnect Battle.net (or its network) and reconnect: no burst of cards for people already online.
11. **Notification interruption.** Open Preview sequence in options and enter combat, or reload, or zone mid-way.
    *Expect:* previews clear, later real cards still appear.
12. **Optional integrations.** With and without EllesmereUI, a data-bar addon (LibDataBroker), Auctionator,
    Leatrix_Plus. *Expect:* TwichUI loads either way; only the affected piece is missing; no Lua errors.
13. **Quick Keybind** (if enabled). Open the Game Menu in and out of combat. *Expect:* one button, disabled in combat
    with a reason; it enters the game's mode only when clicked out of combat.
14. **Sharing.** Send an offer, turn "Configuration sharing" off before the other side answers. *Expect:* sender ends
    "failed", receiver's prompt closes; nothing stored. Repeat with "Let friends send me…" off during a receive.
15. **Errors and taint.** Play 10 minutes including combat; check `/tui diagnostics` (no "init-failed") and the game's
    error display. Taint can only be judged in the game.

## Welcome dialog (`modules/Welcome.lua`): manual acceptance test

Nothing here has been verified in the game yet. Test TwichUI alone first, then with EllesmereUI. The dialog opens only when
asked: a new installation is offered the layout setup instead (`docs/onboarding.md` has its own checklist). A new
installation means moving `!!!TwichUI.lua` (and `.bak`) out of `SavedVariables` with the game closed; put it back afterwards.

1. **Fresh install.** *Expect:* no welcome dialog by itself (the layout setup opens instead). `/tui about` shows
   **Welcome to TwichUI**, centred a little above the middle, in the settings window's look. It holds a short intro, three
   features (cards, Journey Chronicle, gear hints), **What can act for you** and the buttons **Close**, **Preview
   notifications** and **Open Settings**. Under **On now** only the background features that are on by default (Group
   version check, Party pins, Hide addon welcome messages); everything else is under **Off until you turn them on**, and a
   Mage sees the Mage items too. `/tui diagnostics` → "welcome dialog (shown only when asked): marker seen". The settings
   window has not been loaded (`/tui diagnostics` → settings window: not loaded) until a button or link asks.
   Also open **Preview notifications** (a sample zone card and a friend card appear, silent, nothing in the
   Chronicle), press it again (it restarts, nothing piles up), then close the dialog: the sample cards go.
   In combat the button says previews wait. A link under **Review in settings** opens that page.
2. **Existing installation.** Install this build over a save from the previous one. *Expect:* no dialog by itself, on this
   or any character. Turn on Accept summons (Quality of life) and open `/tui about`: it is under **On now** with the people
   and wait you chose.
3. **Closing.** Close button, the **x** in the title area, and Escape each close it. None brings it back (reload, relog,
   change characters, enter and leave instances).
4. **Open Settings.** *Expect:* the dialog closes and TwichUI's settings window opens at Home. With the
   settings window unable to load (TwichUI_Settings turned off or missing), the dialog stays and chat says why.
5. **Manual reopening.** `/tui about`, and Help > Welcome > Show on the settings window's Home page (which closes the settings
   first). It opens any number of times as one frame and changes no setting.
6. **Reload, relog, characters, combat.** None of them ever shows it by itself.
7. **Profiles and resets.** Switch an EllesmereUI profile; press the options' Defaults button; use Appearance > Reset on
   Food and Drink. The dialog does not appear.
8. (Waiting for combat, flights, cinematics and cards is the first-install setup's now: `docs/onboarding.md`.)
9. **Chronicle Welcome Back.** On a character with Chronicle history, `/tui welcome` shows the bookmark; with the dialog
   open by hand, the bookmark and zone cards are neither dropped nor shortened.
10. **TwichUI alone, and with EllesmereUI.** The dialog looks the same either way: warm umber, bronze rim, no
    EllesmereUI window style.
11. **UI scale, window size, long text.** At the smallest and largest UI scale, a small window, and a font with taller
    lines (or a longer translation) the frame grows to fit its text, nothing is clipped, and the buttons stay inside it.
12. **Skinning.** No default-template leftovers; every text is readable against the frame; hovering and pressing the
    buttons changes their look.
13. **No side effects.** Compare `/tui diagnostics` and the options pages before and after: no feature was switched on or
    off and no value changed by opening or closing it.
