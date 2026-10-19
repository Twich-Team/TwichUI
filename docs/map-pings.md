# Map pings

**TwichUI settings > Party pins > Map pings** (`pins/Ping.lua`, `pins/PingMap.lua`, preferences in `pins/Look.lua`
as `PL.Ping`). Switches `modules.mapPings`, `modules.mapPingsSend`, `modules.mapPingsReceive`, all on for a new
profile. Written against the WoW: Forever UI source (`../wow-ui-source`, branch `forever`). **Nothing here has been
run in the game yet**: everything below is source-verified and covered by offline tests with mocked frames and a
mocked network (`tests/test_map_ping.lua`), not seen working in play, with two players or alone.

A ping is a spot on the world map shown to your group for a few seconds, like a minimap ping: a marker with the
sender's name and, unless reduced motion is on, two soft rings. A short list at the top right of the map keeps the
latest ones, and clicking an entry opens its map and shows the ping again.

## What the game offers (and doesn't)

| Looked at | Finding |
|---|---|
| `MINIMAP_PING` (`MinimapDocumentation.lua`) | unit, x, y **on the minimap**, with `SecretPayloads` and `HasRestrictions`. No map id, nothing for the world map |
| `Blizzard_PingUI` (`C_PingSecure`) | `AllowLoadGameType: mainline`, `Environment = "SecureOnly"`; hit-test pings of the 3D world, units, spells and items. No map coordinates |
| `MapPinPingTemplate` / `MapCanvasDataProviderMixin:PingPin` | an animation for a pin the map already has; no sharing |

So there is **no native world-map ping**, and TwichUI sends a small message of its own.

## Compatibility

* **Receiving needs TwichUI**, with Party pins and Map pings on, on the other player's side. Players without it
  see nothing. Nothing is written in chat, and there is no fallback to chat links.
* No other addon's pings are read or written. There is no verified protocol shared with another addon, so none is
  claimed. (`reference_addons/PartyPins` is another addon with its own format; it is not used.)
* Map pings are part of Party pins: they do nothing while Party pins is off.

## Making a ping

* **Ctrl-Alt-click** on the world map (default). Also offered: **Ctrl-Alt-right-click**, or **Off**, which leaves
  **Ping the map** (`/tui ping`, or the button in the options): the next plain left-click within a minute.
* Why this click. Pin clicks hold Alt, or Alt and Shift, and never Ctrl (`pins/Look.lua`, `PL.CLICKS`), so no ping
  gesture can be a pin click (a test checks every pair). Ctrl-click alone is the game's waypoint
  (`WaypointLocationDataProvider.lua`, `CanPlacePin`), and **WaypointUI** runs its own handler for any Ctrl-left-click at
  priority 100 (`Code/Navigation/Navigation_WorldMap.lua`, `OnCanvasClick`). The ping handler is at priority 105 and
  takes only the exact keys, so Ctrl-Alt-click is ours when it is chosen, and every other click, Ctrl-click included,
  goes on as before. Shift-click is ShortestPathForever's journey, so Ctrl-Shift is not offered.
* The handler is the map's own `AddCanvasClickHandler`; the place is the map's normalized cursor position on the map
  being viewed (`MapCanvasScrollControllerMixin:OnMouseUp` hands handlers `NormalizeUIPosition(cursor)`), never the
  screen or the zone you are in. Only this click sends: browsing, dragging, zooming and pointer movement never do. A
  click that was a ping (or a refused one) does not also pan, zoom or set a waypoint.
* **The map tools bar** (`docs/map-tools.md`) has a **Group ping** button: click it, then click the map. It arms one plain
  left-click through the same `MapPingView.PingAt` the gesture uses, so it sends the same message under the same limits.
* **Hint.** While the gesture's keys are held with the pointer over the map, a small tooltip at the pointer says
  "Click to ping your group" (`MODIFIER_STATE_CHANGED`, no `OnUpdate`). It can be turned off. The list's title has a
  tooltip with the same line, and so does the settings page.
* Refused with one short sentence on screen (the same sentence is not repeated for three seconds): no group, the
  game holding addon messages, a map that can't be pinged (the cosmic map, a map the game doesn't know), a spot
  outside the map, pinging too quickly, or sending turned off. Nothing is sent in those cases.

## The message

Prefix `TwichUIPing` (its own), registered once through `AceComm-3.0`. Plain text, version 1, 40 bytes at most:

```
1:<map>:<x>:<y>:<seq>        e.g. 1:1429:4520:6130:17
```

`map` is a map id; `x`, `y` are whole steps 0..10000 of the map (the pin system's coordinates, `PN.COORD`); `seq` is
0..65535, one more than the sender's last, starting at a random number. Nothing else is in it: no name, no text, no
sound or asset, no format string, no command. It is read with one anchored pattern; nothing is deserialized, loaded
or run.

**Who sent it** is the sender the game reports for the addon message, normalised with `Share.FullName`. A message
can't name anyone.

**Where it goes.** One message to the group the game counts now (`Share.GroupDist`): `INSTANCE_CHAT` in an instance
group, `RAID` in a raid, else `PARTY`. A player in a home party and an instance group is sent exactly one message
(to the instance group). Never to the guild, a public channel or a whisper. Received pings are never passed on.

## What is checked on arrival, in order

1. Map pings on, and receiving on. 2. Readable (not a secret value; text and sender are strings). 3. The channel is
one of the three and fits your group now (`PARTY` only outside a raid, `RAID` only in one, `INSTANCE_CHAT` only in an
instance group). 4. The sender normalises to a name. 5. Not you (your own message, echoed back, is ignored, in a raid
too). 6. **The sender is in your current group**, compared with `Share.SameName`, so `Name`, `Name-Realm` and
`First Last` forms of one member agree (a member of another realm is not their same-named neighbour). 7. The sender's
rate bucket. 8. Size (40 bytes). 9. The version (a higher one is `newer-protocol`, another `bad-version`). 10. The
exact shape. 11. The map is one the game knows (`C_Map.GetMapInfo`) and not the cosmic map. 12. Both coordinates are
whole numbers in range. 13. Not a sequence number this sender used in the last eight messages.

A message that fails is dropped silently. Diagnostics only count it by reason code (`/tui diagnostics`, the Party pins
section): no name, place or text.

## Limits

| What | Bound |
|---|---|
| Pings you send | a burst of 3, then one every 3 seconds |
| Pings taken in, per sender | a burst of 4, then one every 2.5 seconds |
| Sounds | at most one every 1.5 seconds from anyone, one every 5 seconds from one sender |
| Replays (a click on an entry) | one every 0.6 seconds do anything; replay sounds one every 2 seconds |
| Recent list | `listSize` entries, 3 to 8, default 5; at most 2 per sender (a newer ping replaces their oldest) |
| An entry's life | `listMinutes`, 1 to 10, default 3, **counted from when it arrived here**: the sender's clock is never read |
| Pings on the map | at most 6 frames; a new ping from a sender takes that sender's; the oldest is reused when full |
| A ping on the map | `seconds`, 2 to 10, default 4 |
| Sender state | one rate bucket and eight sequence numbers per member of your group, at most 40; dropped when they leave |
| Expiry | one `C_Timer.After` at a time, for the oldest entry's end; the list's ages are redrawn every 5 seconds only while it is showing |

## What is shown

* **On the map** (`PingMap.lua`): a frame on the map's canvas for each ping, placed as pins are (`PM.PlaceAt`, the same
  scale rule as `MapCanvasMixin:ApplyPinPosition`) and placed again when the map, its zoom or its size changes. A bevelled
  marker (TwichUI's own `map-pin` texture, ivory over a dark edge), two rings (the game's own
  `Interface\minimap\UI-Minimap-Ping-Expand`, bright over a dark ring so they read on pale and dark maps), and the sender's
  name on a dark plate, in the map text font the player chose for pin names. No mouse, no particles, no flash, no map
  movement. A ping is drawn on its own map and on a **parent** of it through the game's world-position conversion, as pins
  are; never on a sibling or child map. On any other map nothing is drawn and the list has it.
* **Animation.** The marker pops in over a quarter second, the rings play a few times, everything fades over the last half
  second. It runs on one frame's `OnUpdate`, set only while a ping is showing and removed with the last one.
* **Reduced motion** (its own choice, `ui.pinsPing.reducedMotion`; no other feature's setting is read or changed): no
  rings, no pop. The marker and name stay, then fade.
* **The list**: top right of the world map, anchored 44 units left of the map's top right corner so it sits beside the
  game's two 32-unit buttons (`WorldMapMixin:AddOverlayFrames`) and not over them; hidden when empty, when the map is
  closed or when turned off. Width follows the text size and is held to 45% of the map's width. Each entry: the sender, how
  long ago ("now", "30s", "2m"), the map's name from `C_Map.GetMapInfo`, and in words what a click does: **Replay** for a
  ping on the map being viewed, **Open map** for another. It draws with the data bar menu's look (background, border) and
  the pin window's font.
* **Sound**: the game's own map ping (`SOUNDKIT.MAP_PING`, which Blizzard plays for its map pings) by default, or any
  TwichUI / LibSharedMedia sound on a chosen volume channel (`PlaySoundFile`). The game's own sound has no channel and
  ignores that choice. A chosen sound that has gone plays the game's own and stays chosen.

## Receiving, and clicking an entry

* A ping that arrives **never opens or moves the map**. With the map closed it is kept for the list's time, the sound
  policy applies, nothing is drawn, and nothing is said in chat. Opening the map later shows the list and replays nothing.
* **Click an entry**: if it expired, one sentence and nothing else. If it is on the map being viewed, it is replayed. If not,
  the map is asked once (`WorldMapFrame:SetMapID`, as pins' Show on map does); when the map announces itself
  (`OnMapChanged`) the ping is drawn there and its sound plays by the policy. A newer click, the player moving to another
  map, the map closing, the feature going off or two seconds passing cancels the wait (every callback carries a token), and
  nothing asks again. A replay adds no entry, is never sent, and honours mute and reduced motion.

## Settings (Party pins page > Map pings)

Map pings, Send pings with the gesture, Take in pings from my group (switches, kept local when a setup is shared);
Ping gesture, hint, **Ping the map**, Ping shown for (seconds), Reduced motion for pings, sound on/off, Ping sound,
Volume follows, **Hear the sound**, Show the recent pings list, Entries in the list, Keep an entry for (minutes),
**Test ping**, **Reset map pings** (only the choices above; not the switches, pins or other pin choices).

**Test ping** draws a ping named "Test ping" in the middle of the map being viewed with the real renderer and the real
sound policy. Nothing is sent, listed, saved or moved. With the map closed it waits for the map to be opened for half a
minute.

## Saved and not saved

Saved: the choices in `TwichUIDB.ui.pinsPing` (only once changed) and the three switches. Never saved: pings, senders,
names, coordinates, sequence numbers, the recent list, rate buckets, pending clicks. After `/reload`, leaving the group,
turning the feature off or Party pins off, all of it is empty. When a member leaves, their pings and state go with them;
the others' stay.

## Not verified

Everything about the real game: whether the addon channel delivers to another player, `INSTANCE_CHAT` and `RAID` in play,
how the rings and the list look and sit at real scales and with EllesmereUI's map skin, that the Blizzard button column
is as `AddOverlayFrames` says on this client, that WaypointUI's handler (priority 100) really runs after ours, that
`MODIFIER_STATE_CHANGED` and `GameTooltip:IsOwned` behave as in Blizzard's own use, and `PlaySound(SOUNDKIT.MAP_PING)`.

## Manual checklist (two clients, both with TwichUI, in one party)

1. **Same map.** Both open the world map on the same zone. A holds Ctrl-Alt over the map: a small hint shows. A
   Ctrl-Alt-clicks. A sees the ring and their own name; B sees A's name, the rings and hears one sound; the list shows
   A with **Replay**. Plain, Ctrl, Alt and Alt-Shift clicks by A did nothing new (Alt and Alt-Shift still make pins).
2. **Other map.** B opens another zone. A pings. B sees nothing on the map, one sound, and an entry marked **Open map**
   with A's name and the zone. B's map did not move. Clicking it opens A's zone once and shows the ping there; the
   sound follows the policy.
3. **Closed map.** B closes the map. A pings twice, a few seconds apart. B hears at most one sound per 1.5 seconds, sees
   nothing, nothing in chat. B opens the map: the list has both, no ring, no sound.
4. **Replay.** B clicks an entry on this map: ring again, one sound, no new entry; A sees and hears nothing. Muting the
   sound in the options silences the replay too. Reduced motion shows a still marker and name.
5. **Group changes.** A leaves the party: A's entries leave B's list. A rejoins and pings: it works. Convert to a raid, and
   ping from each: still works. If an instance group is available, ping inside it.
6. **Spam.** A Ctrl-Alt-clicks ten times quickly: three go out, the rest say "Pinging too quickly" once. B sees at
   most one frame for A, two entries for A, one or two sounds. Try a map where the game refuses (the cosmic map): one sentence.
7. **Switches.** B turns Take in pings off: A's pings are ignored. B turns Map pings off, then on: no duplicate
   clicks or frames. **Test ping** in the options shows a ping named Test ping and sends nothing (check A sees none).
8. **Reload.** B `/reload`s: the list is empty afterwards.
