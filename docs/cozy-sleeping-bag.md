# Cozy Sleeping Bag guide

A small window that follows the hidden quest chain behind the Cozy Sleeping Bag. Open it with **Settings › Cozy Sleeping Bag › Open**
or `/tui bag` (alias `/tui cozybag`). It never opens by itself, and nothing runs while it is closed.

## Files
`guides/CozyBagData.lua` (the chain; no game calls) · `guides/CozyBagState.lua` (progression; pure) · `guides/CozyBag.lua` (reads the game,
events, position, pins) · `guides/CozyBagWindow.lua` (the window) · `TwichUI_Settings/pages/CozyBag.lua` (open, lock, reset).
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

## In-game checks (none done yet)
- Fresh character: opens on "Burned-Out Remains" of the right side; nothing done.
- Partly done (turn in a few, `/reload`, with the guide closed): opens on the right step with earlier ones Done.
- Already done: "All 7 steps done", reopens following the last step; the bag need not be in your bags.
- First open right after login: "Checking quest progress..." then the answer, never a flash of "all incomplete".
- Whether the hidden quests appear in the quest log, and whether clicking an object ever leaves one "ready to turn in".
- Pin a two-place step; press again; Show on map; Remove pins...; confirm unrelated pins stay.
- Larger UI scale / small window: the window scales down; the detail area scrolls.
