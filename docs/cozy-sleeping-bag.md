# Cozy Sleeping Bag guide

A small window that follows the hidden quest chain behind the Cozy Sleeping Bag. Open it with **Settings › Cozy Sleeping Bag › Open**,
`/tui bag` (alias `/tui cozybag`), or the small launcher button below. It never opens by itself, and while it is closed the only
things running are the invitation's few events (see "The invitation").

## Files
`guides/CozyBagData.lua` (the chain; no game calls) · `guides/CozyBagState.lua` (progression; pure) · `guides/CozyBag.lua` (reads the game,
events, position, pins) · `guides/CozyBagWindow.lua` (the window) · `guides/CozyBagOffer.lua` (when the bag is available, the per-character record, the
events) · `guides/CozyBagNotice.lua` (the unlock card) · `guides/CozyBagButton.lua` (the launcher button) ·
`TwichUI_Settings/pages/CozyBag.lua` (open, lock, reset, and the invitation's choices).
Pins: `pins/Pins.lua` gained a `guide` tag on saved pins (`PN.FindGuide`, `PN.GuidePins`, `PN.ValidGuideTag`); `pins/Map.lua` shows
"From the Cozy Sleeping Bag guide" in the pin's tooltip.

## The chain (facts from NaowhForever_Discovery, not checked in game)
Source: `reference_addons/NaowhForever_Discovery/Data/SleepingBag.lua` and `SleepingBag.lua`. That addon is all rights reserved, so only
the facts (quest IDs, map IDs, coordinates, order) are used; the wording is ours, and nothing of it is loaded or called.
It credits Wowhead Forever's quests and guide. The level (14) is its figure and is only shown.

| Step | Quest | Place (map, x, y) |
|---|---|---|
| Alliance 1: Burned-Out Remains, Westfall (starts it) | 79008 | 1436, 37.5, 50.7 |
| Alliance 2: Burned-Out Remains, The Barrens (finishes it) | 79008 | 1413, 46.4, 73.9 |
| Horde 1: The Barrens (starts it) | 79007 | 1413, 46.4, 73.9 |
| Horde 2: Westfall (finishes it) | 79007 | 1436, 37.5, 50.7 |
| Pocket Litter | 79192 | 1442, 40.8, 52.6 |
| Mound of Dirt | 79980 | 1442, 39.6, 49.9 |
| Carved Figurine | 79974 | 1432, 49.5, 12.8 |
| Messenger Bag | 79975 | 1417, 22.5, 24.2; and the cart to climb from: 1424, 87.3, 49.6 |
| Hastily Rolled-Up Satchel (holds the bag) | 79976 | 1417, 22.5, 24.2 |
| Firepit (optional, quest 80001, "Rekindle") | 80001 | 1442, 40.6, 52.4 |

Not established by the reference, so not claimed: that each quest requires the one before it, any experience or rest value, and any
reward other than the item.

## Progress
Read from the character's own history on every look, never saved:
`C_QuestLog.IsQuestFlaggedCompleted` (turned in, ever), `IsOnQuest`, `ReadyForTurnIn`. A step is done when its quest is turned in; a
"start" step is also done once its quest is taken (a turned-in quest was taken). The current step is the first required step not done.
Labels: Done, Current, In progress, Turn in (objectives complete, not turned in), Later, Optional. A quest in the log that is not the
current step is shown as In progress without moving "current". Abandoning puts the step back.

**Inference** is data-driven (`provedBy` on a step: later steps whose completion proves it). The real chain uses none, because the reference
does not establish prerequisites; a made-up chain in the tests exercises the mechanism. Consequence: if a later quest is flagged and an
earlier one is not, the earlier one stays current.

**History loading.** This client's documentation has no "request completed quests" call. The flag is answered from what the client
holds, but whether that is complete the moment the world loads is not shown, so the guide shows "Checking quest progress..." (no step
done, none selected) until the world is entered *and* the first `QUEST_LOG_UPDATE` has come, or three seconds after entering the world.
That is two events listened to from login until answered, then none, plus one 3-second timer. No polling.

**Not recorded anywhere:** nothing in the chain is a non-quest action, so there is no manual checklist. The reward item is never consulted.

## View
`view = { id, following }`. Following moves to the detected step as progress changes. Picking any other step stays put through every
update and never changes progress; "Back to current step" (or picking the current step) follows again. Closing resets it to following.

## Pins
Ordinary saved pins (`TwichUIDB.pins`), tagged `guide = "cozybag:<step>:<place>"`; named "Cozy Bag: <title>" (or the place's first label
for a two-place step); colour moss. Pin this step is idempotent (finds the tagged pin; never edits or moves it). The pin has no note
field, so instructions stay in the guide. Show on map uses the map's own action; Navigate (only if Navigation is on) uses
`Nav.StartAt`. Nothing is sent: a group copy built from a tagged pin never carries the tag. Pins need Party pins turned on (the guide says
so otherwise). **Remove pins...** asks first and removes only tagged pins that are not kept, judged again when accepted.

## Saved
`ui.cozyBag = { locked, x, y }` only (profile-scoped like the other positions, classed "place" in configuration sharing so it stays on
this computer). Progress, step choice and pending state are never saved. Pin tags live with the pins.

## The invitation: a card once, a button while it is available
Added 2026-10-29. Nothing in it opens the guide, makes a pin or route, sends anything or plays a sound.

**Available** is `CozyBagState.Offer`, one pure rule shared by the card and the button: level at least `D.level` (14, the guide's
own figure, now also the unlock level), the quest history trusted, the chain not finished (`CozyBag.Progress`, the guide's own
model, read afresh), the item not in bags or bank, and no record that it was got. Not knowing is never "not done": a history that
has not loaded, or an unreadable faction, offers nothing (`loading`, `unknown`) and is asked again when the history arrives
(`CozyBag.OnReady`), not by polling. Owning the item or a finished chain is remembered (`acquired`), so selling or banking the
bag never re-opens the offer. A count of zero proves nothing and is never used as evidence.

**The card** ("A new journey awaits / The Cozy Sleeping Bag can now be acquired / Open the guide from its button when you're
ready", or `/tui bag` when the button is off or hidden) is a Notify kind `cozybag`. Cards take no clicks, so it points at the
button rather than offering an action. It is queued at low priority 8 s after a login or reload, 6 s after a level-up (behind
the zone, Welcome Back and training cards) and waits for combat, banners and any card in its way (90 s). It borrows the New
training card's appearance and place, so it adds no appearance scope. It is marked told only when it is really on screen, never
when queued and never by a preview. A loading screen empties the coordinator's queue, so the card is asked for again at the next
world entry. It is cancelled if the chain is finished, the item is owned, the button is hidden, or its switch is turned off. While
the first-install setup is new, started or installing, the card is held back (the button is not); it comes at the first world
entry after the setup is answered. There is no watcher for the setup finishing without a reload, by design (no polling).

**The button** (`TwichUICozyBagButton`) is one plain, non-protected frame made the first time it is wanted: the sleeping-bag icon
(`R.Icons "sleepingBag"`) on a dark ground with a thin bronze outline, optionally with the words "Sleeping Bag". No glow, pulse or
animation. Left-click opens the guide (`O.OpenGuide`: pcall; on failure it says why in chat and stays); right-click: Open guide,
Move, Hide button. It steps aside while the guide is open and returns when it closes. Opening completes and dismisses nothing.
It can be dragged only in move mode (menu Move, or the settings' Button place); a click then does nothing, so a drag is never a
click. Move mode and previews end with Done, the settings closing (`R.OnSettingsClosed`), combat, or hiding. The place is an offset
from the screen centre (`ui.cozyBagButton.x/y`), validated, held on screen and placed again on `UI_SCALE_CHANGED` /
`DISPLAY_SIZE_CHANGED` (listened for only while shown). Default: against the left edge, a little above the middle.

**Saved.** Profile (shared as group "Cozy Sleeping Bag guide"): switches `cozyBagNotice` and `cozyBagButton` (both on), and
`ui.cozyBagButton.{label, size, opacity}`. Kept on this computer, never shared or published: `ui.cozyBagButton.x/y` (class
"place"; not a layout place either, like the guide window). Per character, account-wide, outside every profile
(`Profiles.ACCOUNT.ui.cozyBagOffer`, class "other"): `ui.cozyBagOffer[guid] = { announced, hidden, acquired }`, three separate
booleans (absent = false). Switching profile, applying a layout, or turning the switches off and on changes none of them. Turning
"Show the guide button" on does **not** undo a button the player hid; the explicit "Show the hidden button" row does (and turns the
switch on). Records are a few bytes per character and are not pruned.

**Cost.** Events, only while a switch is on and the bag is not known to be got: `PLAYER_LEVEL_UP`, `PLAYER_ENTERING_WORLD`,
`QUEST_TURNED_IN` (dropped at once unless the quest is one of the chain's). A look is the guide's quest reads plus one
`C_Item.GetItemCount`, once per such event, coalesced 0.5 s. No `OnUpdate`, no bag events, no timers but the delays above. Gauges:
`bag.offer.events`, `bag.offer.looks`, `bag.button.built`, `bag.button.shown`. No `Perf` scopes: the work is event-rare and trivial.

## In-game checks (none done yet)
- The invitation: a level 13 character crosses 14 (the card after the training card, the button at once); a level 14+ character
  without the bag at login (button, one card a few seconds later, none at the next login); a character who has the bag or finished
  the chain (nothing); sell or bank the bag (still nothing); `/reload` with the card queued (asked for again).
- Whether `C_Item.GetItemCount(211527, true)` answers 0 or the real count right at world entry, and whether
  `C_QuestLog.IsQuestFlaggedCompleted` is already final when `QUEST_TURNED_IN` fires (the offer waits 0.5 s; the guide does not).
- The card with the first-install setup open (it must not appear over it), and at login with Welcome Back and the zone card.
- The button: drag only in Move; click opens the guide and the button steps aside; Hide button then relog; Show the hidden button;
  UI scale and resolution changes keep it on screen; it does not sit under the character or the middle bars at a few resolutions.
- Whether `MenuUtil.CreateContextMenu` shows the three entries on this client.
- Fresh character: opens on "Burned-Out Remains" of the right side; nothing done.
- Partly done (turn in a few, `/reload`, with the guide closed): opens on the right step with earlier ones Done.
- Already done: "All 7 steps done", reopens following the last step; the bag need not be in your bags.
- First open right after login: "Checking quest progress..." then the answer, never a flash of "all incomplete".
- Whether the hidden quests appear in the quest log, and whether clicking an object ever leaves one "ready to turn in".
- Pin a two-place step; press again; Show on map; Remove pins...; confirm unrelated pins stay.
- Larger UI scale / small window: the window scales down; the detail area scrolls.
