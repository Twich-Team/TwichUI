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
| Mage menu rows, shift-click cover | yes | **Reject** opening in combat; close at combat start (or when it ends); cover is put away out of combat only |
| Quick Keybind (`QuickKeybindFrame:Show()`) | yes | **Disable** the button in combat with the reason; never deferred (it must be the player's click) |
| Cards, movers, tooltips, the notification coordinator | no (plain frames) | act at once; previews clear at combat start |
| `BNToastFrame` event list | no | act at once |
| Settings previews, apply/restore/reset buttons | n/a | **Reject** in combat with a message |

Mocked tests cannot show combat lockdown, protected-frame errors or taint. Those need the game.

## Reason codes (`/tui diagnostics` → "Start-up and lifecycle")

`waiting-for-world`, `deferred-combat`, `cancelled-stale-baseline`, `cancelled-stale-transfer`, `transfer-settled`,
`friend-bnet-baseline`, `friend-bnet-disconnected`, `init-failed`. Counts only; no names, places or items.

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
8. **Profile switch with things open.** (TwichUI has no profiles; switch an EllesmereUI profile.) With the options
   panel, a preview card and a mover open. *Expect:* nothing stuck on screen, no stale tooltip.
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
