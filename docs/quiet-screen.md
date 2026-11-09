# Quiet screen

A temporary switch for when the player is relaxing and doesn't want TwichUI's own pop-ups on the screen. It is on the
**TwichUI data bar entry's menu** (left click), as **Quiet the screen** (On/Off, the menu stays open), and the entry's
tooltip says `Quiet screen: On.` or `Off.`. Code: `!!!TwichUI/QuietScreen.lua` (`R.QuietScreen`).

## What it is, and is not

- **Session only, nothing saved.** It starts Off at every login and every `/reload`. It is not a setting: no key in
  `TwichUIDB`, not part of a profile, a backup or a share.
- **Silent.** It prints nothing in chat.
- **Not a pause of the features.** Everything keeps being decided in the background (reminders are evaluated, glows are
  worked out, buffs are noticed). Only what reaches the screen, and the sound that goes with it, is held back.
- **Nothing is shown afterwards for what happened meanwhile.** Turning it Off brings back what is *still true* (a
  reminder whose conditions hold, a glow still wanted, the Healer Watch panel) and nothing that came and went. A card
  for an event during the quiet (zone, training, friend login, party death ...) is not queued for later.
- **Previews ignore it.** The settings' previews are the player asking to see something.

## What it quiets

| Surface | While quiet | When turned Off |
|---|---|---|
| Notification cards (`modules/Notify.lua`: zone arrival, training, friend login, Welcome Back, party death, Cozy Sleeping Bag offer) | Real notices are refused (`quiet`, counted in the diagnostics `refused` table); ones waiting or showing are let go at once. Their sounds are part of showing, so they don't play. | New notices are accepted again. Nothing returns. |
| Reminders (`reminders/Display.lua`, `Controller.lua`) | Live frames are hidden (fade out as normal); no reminder sound (`soundsQuiet` in the snapshot). | Frames still wanted fade back in; the sound of something that appeared meanwhile is not played. |
| Action bar glows (`glows/Controller.lua`) | No glow, no message card, no sound; showing ones are cleared. Faded bars are a bar setting, not an alert, and are left as they are. | Glows still wanted are drawn again; no message or sound for what came up meanwhile. |
| Healer Watch (`healer/Watch.lua`, `Logic.lua`) | The live panel is hidden (status reason `quiet`); its flashes, particles and chat sound need the shown panel, so they don't happen. | The panel returns as the group stands. |
| Return the Favor (`buffback/Watch.lua`) | Treated like a place it pauses in (`Paused()` returns `"quiet"`): the list empties, new buffs are not listed, and a thank-you emote that was already waiting is skipped (the same pause check). | Listening again; the list starts empty. |

## What it deliberately leaves alone

Things the player opened or that are part of the interface, not alerts: the settings and other windows, the Chronicle,
the map and its pins and pings, class bars, the Camping bar, the marker bar, Food/Drink buttons, target art, the
RestedXP guide (it has its own auto hide), and the Restock question (it appears only at a merchant the player opened,
and an unanswered question would silently skip an action they asked for). Hazard alerts are sound only (no screen
element) and keep their own switch.

## Limits

- **Combat.** Return the Favor's list is a secure frame: its rows cannot change in combat, so turning Quiet on during
  combat takes effect when combat ends (or at once if the list was set to hide in combat). Everything else is plain
  frames and acts at once.
- A `/reload` turns it Off (nothing is saved). If that proves annoying, saving it for the reload only is a small, separate change.

## Tests

`tests/test_quiet_screen.lua` (the switch, Notify, load order); the rest are in each surface's own test:
`test_reminders_enchant_sound.lua`, `test_bar_glows.lua`, `test_healer_watch.lua`, `test_return_the_favor.lua`,
`test_settings_broker.lua`. All offline; none proves how it looks or behaves in the game.

## Diagnostics coverage

No scope or gauge: it adds no recurring work, timer or event. It is a boolean read at points that already run, plus a few
listeners (bounded, registered once at load). The refusals are counted in the existing notification and reminders snapshots.
