# Party pins

**TwichUI settings > Party pins** (`pins/`, switch `modules.partyPins`, on by default for a new profile; a profile that has already saved it as off keeps it off). Written
against the WoW: Forever UI source (`../wow-ui-source`, branch `forever`). **Nothing here has been run in the
game yet**: everything below is source-verified and covered by offline tests, not seen working in play.

Named pins on the world map. **Local pins** are yours only and kept between sessions. **Party pins** are
shared with party members who have TwichUI with Party pins turned on, for as long as you are in that party.
Players without TwichUI see nothing: nothing is written in chat and there is no fallback to map links.

## Files

| File | Owns |
|---|---|
| `pins/Pins.lua` | the data: checks, local pins, the party session's pins (and a saved pin's group copy), dismissals, removal records, permissions |
| `pins/Sync.lua` | the protocol, the party session's lifecycle, rate limits, `/reload` hand-over |
| `pins/Look.lua` | the click and label choices, the window's look (MenuStyle look, font, size, accent, rows), the data bar entry's text, icon and color, and the data bar menu's look |
| `pins/Map.lua` | the world map: data provider, pin buttons, placing clicks, Show on map, Set waypoint |
| `pins/Editor.lua` | the name, color and kind editor (the new pin window) |
| `pins/Window.lua` | the pin window and the action menu (also opened from a map pin) |
| `pins/Way.lua` | waypoint commands: `/twichway`, `/way` when free, the parser, the zone lookup and the paste window |
| `pins/Sound.lua` | the sound a pin arriving from another player plays (the choices are in `pins/Look.lua`, `PL.Sound`) |
| `pins/Ping.lua`, `pins/PingMap.lua` | map pings: the message, its checks and limits and the recent list (`Ping.lua`, no frames); the rings, the list on the map, the gesture and the replay (`PingMap.lua`). See `docs/map-pings.md` |
| `pins/BrokerMenu.lua` | the small pin menu a click on the data bar entry opens |
| `pins/Broker.lua` | the optional LibDataBroker data source |
| `diag/Pins.lua` | the troubleshooting section |

## Placing

* Map clicks are TwichUI's only when they match exactly. Defaults: **Alt-click** for a local pin,
  **Alt-Shift-click** for a party pin. Choices: Alt-click, Alt-Shift-click, Alt-right-click, Off. Picking the
  other kind's click swaps the two.
* Not offered, because they are taken: **Ctrl-click** is the game's waypoint
  (`WaypointLocationDataProvider.lua` `CanPlacePin`), **Shift-click** is ShortestPathForever's journey
  (`Journey/JourneyInput.lua`). Alt-click is used in the Forever source only by `WM_DebugDataProvider.lua`,
  which returns early unless `IsGMClient()`.
* The handler is the map's own extension point, `WorldMapFrame:AddCanvasClickHandler(fn, 95)`.
  `MapCanvasSecureUtil.CreateHandlerRegistry` calls addon handlers through `securecallfunction`. Priority 95
  runs before the waypoint handler (90). It returns false, so the click goes on to the map, for anything
  that isn't an exact match. Canvas handlers don't run over pins.
* **Place a pin** in the window arms one plain left-click for 60 seconds. TwichUI doesn't open the map for you
  (see "Taint").
* A click opens the editor at the clicked map and position (`ScrollContainer:NormalizeUIPosition`, already
  normalised by the map). Nothing is made or sent until **Save**. Save checks everything again: the name,
  being in a party, the limits.

## Data

Coordinates are whole steps of 1/10000 of the map, from 0 to 10000 (`x`, `y`). A map must be one
`C_Map.GetMapInfo` knows. Names are plain text, at most 48 bytes, cut on a UTF-8 character boundary. Color
escapes, links, textures, atlas and key escapes, stray `|` and control characters are removed. Colors are
stable ids: gold, ember, moss, river, violet, rose, parchment, slate.

**Saved** (`TwichUIDB.pins`, account-wide like the rest of TwichUI's own data):

* `list`: local pins `{ id = "L<n>", map, x, y, name, color, created, copiedFrom?, kept? }`. `kept` is
  `true` for a kept pin (see "Keeping pins") and absent otherwise; a pin saved before it existed is an
  ordinary pin, and only an explicit `true` counts.
* `nextId`: never reuses an id, even one held by an entry that can't be read. Unreadable entries are
  skipped, never erased.
* `session`: the party session, written at logout and read by the next load only. See "Reload".

The pin window's choices live in `TwichUIDB.ui`: `partyPins` (clicks, labels, window position), `pinsLook`
`pinsAppearance` and `pinsMapText` (the names on the maps), `pinsBroker` (the data bar entry) and
`pinsBrokerMenu` (the data bar menu's look) and `pinsEditorLook` (the new pin window's look). Only changed values are stored. An unusable value reads as its default and is kept.

**Session only** (in memory): party pins keyed by *owner + id*. The owner is the sender's name as the game
reported it, never a field of the message. Ids are a random six-character word per session plus a running
number (`k3x9qa:4`). Also kept: dismissal records ("removed from my map") and removal records (tombstones).
Frames, timers, queues and rate buckets are never saved.

## Waypoint commands

`pins/Way.lua`. A TomTom/Wowhead style waypoint becomes a **local pin**, through the same `Pins.AddLocal` the
map click and the editor use, so it is saved in `TwichUIDB.pins.list`, drawn, listed and limited exactly like
one placed by hand. Needs the Party pins switch on; with it off the commands say so and make nothing.

```
/twichway <x> <y> [name]                 the map you are on
/twichway <zone name> <x> <y> [name]     a continent, zone or dungeon by its full name
/twichway #<mapID> <x> <y> [name]        a map by number
/twichway paste                          a window for several lines
```

`/way` accepts the same text when no other addon has it (see below). Coordinates are percentages from 0 to
100 inclusive, integers or decimals, `52.3 40.7`, `52.3, 40.7`, `52.3,40.7` or `52.3 , 40.7`. Only the first
two numbers are coordinates: everything after them is the name, numbers included
(`10 20 Camp 30 40` is a pin called "Camp 30 40"). Extra spaces are ignored. A name is plain text cut to 48
bytes by the pin rule (`Pins.CleanName`); the command says when it was shortened. No name gives the feature's
own default (`Pin <n>`).

* **Which map.** Coordinates alone use `C_Map.GetBestMapForUnit("player")`, never the map open in the world
  map window, which is neither read nor moved. `#mapID` must pass `Pins.ValidMap` (`C_Map.GetMapInfo` knows
  it), which is the check `AddLocal` makes for every pin: that is the whole of "supported by the pin system".
  A zone name is matched whole and case-insensitively against a list built once from the game's map tree
  (`GetMapChildrenInfo(top, nil, true)` from the top of the current map's parent chain, as the world map's own
  navigation climbs it, and the fallback world map). Continents, zones and dungeons are listed; micro and
  orphan maps are reached by `#mapID`. A name found on more than one map is **never guessed**: the message
  lists the candidates with their ids and suggests `#mapID`. A tree that doesn't hang off the player's is read
  the first time the player is in it, once. Nothing is read per command.
* **Coordinates.** Percent to the pin system's 0..10000 steps is `Quantize(pct / 100)`, once.
* **Duplicates.** The pin system has no duplicate policy: the editor and the map click both allow two pins at
  one place with one name, and so do these commands. Nothing is ever replaced or merged by name or place, so
  pasting the same list twice makes the pins twice.
* **Defaults and side effects.** The default color and id rules apply, and the new pin is picked out
  (`Pins.Select`) as the editor's Save does, so its name shows. Not done: opening or moving the world map,
  setting the game's waypoint, any navigation.
* **Paste.** `/twichway paste` builds a small window on first use (nothing exists until then), drawn with the
  new pin window's look. One waypoint per line, with or without a leading `/way` or `/twichway`; blank lines
  are skipped; lines are read in order and each is checked alone. A line that starts with any other slash
  command is refused, never run, and nothing pasted is evaluated as Lua. The pins are made inside one
  `Pins.Batch`, so the map, window and data bar refresh once. The result is a summary plus up to eight reasons
  with their line numbers in chat and five in the window. Lines that made a pin are blanked in place, so
  numbers still match and pressing the button again only tries what is left.
  Limits: 250 lines, 240 bytes a line, 30000 bytes in all, and the local pin limit (200), at which the rest
  is reported as not tried.
* **Combat.** Everything is plain data plus the existing refresh listeners. No secure or protected frame is
  touched, there is no `OnUpdate`, and the pin refresh is the one every pin change already causes.

### Who has `/way`

`/twichway` is registered when the file loads and always works. `/way` is added at `PLAYER_LOGIN` (after every
non-load-on-demand addon has registered its commands) and again when the switch is turned on, and only if it
is free:

* This client's chat frame moves each `SlashCmdList` entry into `hash_SlashCmdList` (keyed by the upper-cased
  tag) the first time it parses a command, empties the list, and lets the last one imported win
  (`ChatFrameUtil.lua` `ImportListToHash`, `ChatFrameSetup.lua`). So both are checked: the hash for an
  imported command, and the `SLASH_<key><n>` globals of the entries still in `SlashCmdList` for pending ones.
* If another addon has it, `/way` is not touched. Nothing is wrapped, hooked or overwritten. The Party pins
  options page names `/twichway`, and the usage text says `/way` belongs to another addon only when it is
  shown (an empty or malformed `/twichway`); nothing is printed unprompted.
* An addon that registers `/way` after TwichUI took it is imported later and wins; TwichUI doesn't fight it
  and `/twichway` keeps working. `/tui diagnostics` says who has it.
* **Also make a pin from /way (opt in, off by default; Party pins options > Waypoint commands).** When another
  addon has `/way` (WaypointUI, TomTom), TwichUI follows that entry's handler: it keeps the original function,
  calls it first with the same arguments, then makes a pin from the same text. This is the pattern
  WaypointUI itself uses on `TOMTOM_WAY` (`packages/slash-command/index.lua` `HookCommand`), and the one
  deliberate exception to "never wrap another addon's handler". The slash names, and every other entry, are
  untouched. The owner's key is found among the entries not yet imported, or in the list's proxy table
  (`getmetatable(SlashCmdList).__index`) when the game has imported it, preferring the entry whose handler is
  `hash_SlashCmdList["/WAY"]`. It is followed once per entry per session and gated on the choice on every
  call, so turning it off takes nothing back; if the owner later replaces its handler, the follow is lost
  until `/reload`. Text that doesn't read as a waypoint (`reset`, `paste`, `list`, a zone with no numbers) makes
  no pin and says nothing; a waypoint that can't be placed (unknown or ambiguous zone, pin limit) says why.
  The owner's own waypoint is still created, so you get both. Not applied when TwichUI has `/way` itself.
* The switch off after `/way` was taken: the command stays registered (a registered command can't be handed
  back to the game) and says Party pins are off.

## Rendering

* A `MapCanvasDataProviderMixin` provider (`AddDataProvider` / `RemoveDataProvider`) is told when the map, its
  zoom or its size changes. It lays out TwichUI's own buttons on `WorldMapFrame:GetCanvas()`, positioned as
  `MapCanvasMixin:ApplyPinPosition` does and scaled by `1 / GetCanvasScale()`. `AcquirePin` and Blizzard's
  pin pools are not used: those need an XML template, and HereBeDragons' pool injection writes into the
  map's private tables. Nothing runs per frame.
* Icon: TwichUI's own `media/textures/map-pin.tga` (64 x 64: a gray bevelled diamond with a see-through
  middle), tinted with the pin's color. It is cut from art supplied for this feature, trimmed to its opaque
  bounds, scaled by area with the aspect ratio kept (60 x 60 in the canvas), and its midtones are lifted a
  little (gamma 0.75) so a color tint isn't muddy. It is symmetric, so a pin is anchored by its center and
  the middle of the diamond is the place. A party pin adds a small parchment badge with a dark edge on the
  diamond's upper-right edge, so local and party pins differ by shape, not color alone.
* A pin is drawn on its own map, and on that map's **parents** (via `parentMapID`). On a parent it is placed
  with `C_Map.GetWorldPosFromMapPos` then `C_Map.GetMapPosFromWorldPos(continent, world, viewed)`, and only if
  that returns the viewed map and a position inside it. It is never drawn on a sibling or a child map, so it
  can't land on the wrong map.
* Labels show on hover and for the selected pin (the default), or always. The tooltip has the name, local or
  party and who made it, the map and coordinates.
* **Minimap** (`pins/Minimap.lua`, on by default with the feature; Party pins options > Show pins on the
  minimap). Pins within range of you are drawn as small buttons that are children of `Minimap`, same shape
  and color, with the party badge. Names are in the tooltip, which also says about how many yards away it is;
  a left click selects the pin and sets the waypoint there (as on the world map), right-click opens the same
  actions. No edge arrows or routes: a pin out of range isn't shown.
  * *Position.* From the game's map data, the way Blizzard's `HybridMinimap` works: the player's place on the
    pin's own map (`C_Map.GetPlayerMapPosition(pin.map, "player")`) and that map's size in yards
    (`C_Map.GetMapWorldSize`). The map's x runs east and y south, so the pin is
    `(x difference * width)` yards east and `(y difference * height)` yards south of you. Yards to pixels:
    the minimap's half width is `C_Minimap.GetViewRadius()` yards (as in `HybridMinimap:UpdateZoom`).
    `UnitPosition` and world coordinates aren't used, so no axis convention is assumed.
  * *Rotation.* With `rotateMinimap` on (`GetCVarBool`, as Blizzard's minimap reads it) the offset is turned
    by `GetPlayerFacing()` (counterclockwise from north). If the facing can't be read, nothing is placed.
  * *Which pins.* Those on the minimap's map (`C_Minimap.GetUiMapID`) or one of its parents. A pin on another
    map, or when the minimap has no map (a dungeon), isn't shown. Pins removed from your map aren't shown.
  * *Cost.* One updater, created only while the feature and the setting are on and a pin could be shown: every
    0.04 s while the minimap rotates, 0.1 s otherwise. Buttons are made once per pin and moved only when
    their place changed by half a pixel. Per update it makes one map-position call per distinct map that has
    a pin on it, and nothing while the minimap is hidden.
  * *Readings the game won't give.* This client has secret values, and other minimap addons here guard the
    view radius and facing for that reason. Every reading is checked for being secret or unusable before any
    arithmetic. If `C_Minimap.GetUiMapID` gives nothing, the player's map (`C_Map.GetBestMapForUnit("player")`)
    is used. If `C_Minimap.GetViewRadius` gives nothing usable, the radius comes from the minimap's zoom step
    and HereBeDragons' yard table (outdoor when the zoom is the one `minimapZoom` names), which is not verified
    in the game. If the facing is needed and unreadable, or nothing gives a radius, nothing is placed. An
    error inside an update is caught: it is counted, shown once through the error handler, and the pins carry
    on at the next update.
  * *Troubleshooting.* The Party pins section reads each input again when the report is made: whether the
    minimap is shown, the kind of each reading (number, nil, secret) and which source was used, the radius,
    whether the first pin's map is the minimap's or a parent with a known size and whether you have a place on
    it, and how many updates ended in each result (`ok`, `minimap-hidden`, `no-map`, `no-radius`,
    `no-width`, `no-facing`, `error`).
  * *The minimap's shape.* The range is a circle of the minimap's half width, so a square minimap (EllesmereUI)
    shows pins only within that circle; its corners stay empty.

## Removing

| Action | Who | Sends | Effect |
|---|---|---|---|
| Remove pin | local pins | nothing | deletes that local pin; refused for a kept one |
| Remove from my map | any party pin, yours too | nothing | hidden on your map; survives updates and resyncs; listed under **Removed**, from where **Restore to my map** brings it back. Kept up to 100, for this party session. |
| Remove all party pins from my map | you | nothing | the same for every party pin except kept ones |
| Share with group / Share again | a saved (local) pin | `put` | publishes a snapshot of it to your party; see "Sharing a saved pin". The saved pin is not changed, moved or protected differently. |
| Stop sharing... | a saved pin that is shared | `del` | asks first; takes only the shared copy off your party's maps. The saved pin stays. |
| Remove for entire party... | **the pin's creator only** | `del` | asks first; then removed from your map and from every member who receives it; a removal record (up to 200) stops a late or replayed copy coming back. Refused for a kept pin. |
| Delete unprotected local pins... | you | nothing | asks first, with the counts; party pins and kept pins untouched |
| Save to my pins... | any party pin | nothing | opens the new pin window filled in (kept by default); Save makes an independent local pin (`copiedFrom`); a party-wide removal of the original never touches it |

* **Authorization is structural.** A pin's key includes its sender, so a `del` or `put` from B naming A's id
  only ever addresses B's own pins. There is no leader moderation. Leadership isn't needed to identify the
  party, and a leader's say over other people's pins wasn't asked for.
* The window offers owner-only actions only to the owner. Each action checks again when it runs
  (`Pins.Can`).
* The removal confirmation says party members with TwichUI remove it "when your message reaches them".
  Nothing confirms delivery and nothing claims it did.

## Sharing a saved pin

**Share with group** publishes one of your saved (local) pins to your party without recreating it,
converting it or changing it. It is in the pin window's action menu (so also the right-click menu of a pin
on the map and on the minimap), in the data bar menu through a right-click on a pin's name (it opens that
same action menu; the rows gain no button), and as a **Share** button in the editor when you edit a local
pin (it saves your changes, then shares).

* **A snapshot, on request.** The party gets the pin's map, coordinates, name and color as they are at that
  moment. Editing the saved pin afterwards sends nothing; **Share again** sends the new state. Nothing is
  shared automatically: not at login, not when you join or rejoin a party, not when the pin changes.
* **One group copy per saved pin.** The first share makes a party pin of yours (a normal one, with an id like
  `k3x9qa:5`, counting against the 20 per player and 60 per session) and links it to the saved pin by a
  session-only `source` (the saved id, `L12`). It is not in the message, not in the saved data and not
  something a message can set. Sharing again gives that pin a new revision under the same id, so recipients
  update it in place and never see two. The link survives a `/reload` in the same party (it travels with the
  session) and is dropped with the session.
* **Preserved.** The saved pin keeps its id, place, name, color, Keep and everything else; the share only
  reads it. Kept is never sent and the group copy is not kept (so Stop sharing works). There is no hidden
  state on a local pin in this addon, so "hidden" pins don't come up.
* **One marker for you.** While a saved pin has its group copy, the copy is not listed or drawn for you as a
  second pin: the saved pin stands for both (its row says "shared", its tooltip says "Shared with your
  party"), and the party pin counts, Clear and Remove all leave the copy alone. For everyone else it is a
  normal party pin from you.
* **Saved pin deleted.** Deleting it (or clearing it) sends nothing and does not take the shared copy back; it
  becomes an ordinary party pin of yours, listed as such, removable with Remove for entire party. This
  matches "Clear unprotected pins": nothing is sent and what you shared stays with your party. A kept pin
  can't be deleted; to take back its shared copy, use Stop sharing.
* **Catch-up.** A member who joins, reloads or says hello gets your party pins (the existing `hi` / `all`
  answer), including the group copies, as they were last shared. This is the existing behavior of party pins
  while you stay in the party, not new publication: the copy is the snapshot, never the saved pin's current
  state. Leaving the party ends the session and the copies; rejoining publishes nothing.
* **Recipients.** An ordinary party pin: their window, map and tooltip say it is yours. They can remove it from
  their own map, or **Save to my pins** for an independent local copy with a new id (kept by default, as
  before). Nothing they do reaches your saved pin: a message from them addresses their own pins only.
* **Not shareable.** Someone else's party pin is offered greyed out with "Save it to your pins first, then
  share your own copy.": sharing it would pass it off as yours. One of your own party pins is already shared.
* **When it can't run**, the action is greyed with the reason (and the same sentence is the message if it is
  picked anyway, so nothing is printed over and over): "Join a party to share this pin." when not grouped;
  "Pins can only be shared with a party, not a raid." in a raid; the game's own message lockdown; the limits
  (20 per player, 60 per session); a map the game doesn't know. It works in combat: it is only a message.
* **Rate.** Sharing a saved pin again within 3 seconds with nothing changed sends nothing ("Already sent to
  your party a moment ago."); a change goes out at once. Receivers' per-sender rate limit (a burst of 15)
  is unchanged. If the game refuses the send, the player is told once ("The game didn't take the shared pin.").
  "Pin sent to your party." is all that is claimed: acceptance by the game is not proof anyone received it.
* **Raids are not supported.** Party pins pause in a raid (nothing sent or taken in), and raid sharing would
  need more than this feature: a roster check over `raid1..40` instead of `party1..4`, a different answer to
  `hi` (up to 39 members each answering with a full list), per-sender rate buckets sized for 40, and session
  limits that a raid fills at once. That is a protocol and lifecycle change, so it was not done; the action
  says so in a raid. Instance groups (`INSTANCE_CHAT`) work as they did for party pins.
* **Protocol:** unchanged, version 1. A group copy is an ordinary `put`; older TwichUI versions that speak
  version 1 show it as a party pin from you. Nothing new is added to the wire.

## Keeping pins

One protection, **Keep**, on a pin of your own: a persistent landmark you don't want lost to a slip, a bulk
clear or a cleanup. There is no separate favorite or lock.

* **Data.** `pin.kept = true` on a local pin (saved, account-wide with the list). On one of your own party
  pins it is a session field: carried across a `/reload` with the session (`k` in the saved session) and
  gone with the session when you leave the party or log out, like the pin itself. It is **never sent**: it
  isn't in the wire form of a pin (`Wire`), and `Accept` writes only name, color, place and revision, so a
  message can't set, clear or read it. A pin received from another player is never kept.
* **Enforced in `pins/Pins.lua`**, not by disabling controls:

  | Function | Kept pin |
  |---|---|
  | `RemoveLocal(id)` | refused, `false, "kept"` |
  | `ClearLocal(only?)`, `ClearUnprotected(scope?)` | skipped, and judged pin by pin when it runs |
  | `DeleteOwn(key)` (and so `PinSync.RemoveForParty`) | refused, `nil, "kept"` |
  | `UpdateLocal(id, fields)` with `map`, `x` or `y` | refused, `false, "kept"`, unless the same call sets `kept = false` |
  | `DismissAll()` | skipped (hiding one pin from its row stays possible) |
  | `Can("delete" / "removeParty", entry)` | `false` and a sentence, so menus say why |

  Renaming, recoloring and hiding (Remove from my map) are not blocked. Nothing in the UI moves a pin today
  (no drag, no coordinate field), so the move guard is defense in depth for a later feature, and is tested
  at the data layer. The normal way to delete a kept pin is Edit pin, turn off Keep, Save, then delete. There
  is no force-delete.
* **Paths audited** (everything that deletes, replaces, expires or moves a pin): `RemoveLocal` (the pin
  window's Remove pin, the data bar menu's remove button), `ClearLocal` (the window's "Delete unprotected
  local pins...", the menu's clear), `ClearUnprotected`, `DeleteOwn` / `RemoveForParty` (window, menu),
  `DismissAll`, `ApplyDel` / `ApplyAll` / `RemoveOwner` / `EndSession` (other players' pins and the session;
  they can't reach yours, which `SameName` already refuses, and a kept party pin of yours is not theirs to
  remove), `ImportSession`, `/way` and paste (`AddLocal` only: they create and never replace, so there is no
  duplicate resolution to guard), and the Persist container check (it drops a `pins` value that isn't a
  table, a corruption case that isn't new). No path expires a local pin; the only cap is `MAX_LOCAL`, which
  refuses new pins. Backups, restore points and sharing don't contain pins.
* **The editor** has a "Keep this pin" box under the colors. It is a draft until Save; Cancel and Esc change
  nothing. Turning only Keep on or off on one of your own party pins sends nothing (no revision change), so
  it works while nothing can be sent (paused in a raid, or held by the game): the editor opens and says so,
  and a new name or color is refused with the reason when saved.
* **The data bar menu** lists kept pins first, under "Kept" (and "Other pins" when both groups have pins), in
  the same order as before within each. A kept row shows a padlock in muted gold where the x was; clicking it
  opens the editor and unlocks nothing. Its title is "Map pins" since the list is local and party pins.
* **Clear unprotected pins...** keeps the scope of the old Clear all: your local pins are deleted and party
  pins on your map are taken off it (nothing is sent, nothing is deleted for anyone else), minus kept pins.
  The question has the counts of exactly those pins ("Remove 3 unprotected pins? ... Your 2 kept pins will
  remain.") and, when accepted, only the pins it named are touched, each judged again: one made since the
  question is left, and one that has become kept stays. If nothing is left to clear, nothing is done and it
  says so.
* **Save to my pins...** (a party pin's action) opens the new pin window with its place, name and color,
  kept by default and local only. Save makes a local pin with a new id (`copiedFrom` set when someone else
  made it). The original is untouched and nothing is sent; later messages about the original can't reach the
  copy, which is a different record. It never replaces an existing pin (there is no duplicate policy to
  overrule, and a kept pin is never overwritten).
* **Presentation.** The window has a Kept filter and a padlock on kept rows; the marker tooltip says
  "Kept · Local pin" (or "Kept · Your party pin"); the data bar tooltip (headed "Map pins") shows the kept
  count when there is one. The diamonds themselves are unchanged. The padlock is the
  game's `Interface\PetBattles\PetBattle-LockIcon` (used by Blizzard's Classic mount collection frame),
  tinted muted gold: not verified in the game.

## Protocol (version 1)

Prefix `TwichUIPins`, its own, never mixed with configuration transfers. Sent with AceComm on `PARTY`, or
`INSTANCE_CHAT` in an instance group (`Share.GroupDist`). Serialized with LibSerialize and encoded with
LibDeflate's addon-channel encoding. Not compressed, so nothing grows on arrival.

| Message | Sent when |
|---|---|
| `{ v=1, o="put", p={ id, r, m, x, y, n, c } }` | you make or change one of your party pins |
| `{ v=1, o="del", id, r }` | you remove one for the party |
| `{ v=1, o="hi" }` | 3 s after your session starts, after a `/reload`, or back from a raid, so the others' rosters show you first. Rate-limited to one per 15 s; dropped if the session ends meanwhile. |
| `{ v=1, o="all", l={ pins } }` | answer to `hi`, once per 6 s, 1.5 to 3.5 s later; several hellos get one answer; only from someone who has made a party pin this session. Unlisted pins of the sender are removed (and recorded removed) by receivers. |

Taken in only when every check passes:

* the switch is on, the channel is `PARTY` or `INSTANCE_CHAT`, and you are not in a raid;
* the sender is in your party now (`party1..4`), and it isn't your own echo;
* the sender is within the rate: a burst of 15, then one every 2 s;
* the message is at most 4000 characters, decodes to a table, and has `v == 1` (a newer version is set aside,
  not guessed at);
* every field of the pin checks out, as above. An unknown color id from a newer version is drawn in the
  default.

Revisions: a `put` is kept only if its revision is higher than the one held. A removed key never comes back,
whatever its revision. A `del` seen before its `put` still wins.

Limits: 200 local pins, 20 party pins per player, 60 in the session, 100 dismissal records, 200 removal
records, at most 20 pins in a list. Reasons for setting a message aside are counted by code for
troubleshooting.

## The party session

| Event | Behavior |
|---|---|
| join a party, or turn Party pins on in one | session starts (new id word), `hi` sent |
| a member leaves | their pins go (yours never do) |
| leave the party, or turn Party pins off | session ends: party pins, dismissals and removal records go; local pins and copies stay. A timer from the old session does nothing. |
| join another party | starts empty; nothing carries over |
| party becomes a raid | **paused**: nothing sent or taken in, pins stay as they are, party-wide actions say why they can't run |
| raid becomes a party again | members who left are dropped, `hi` sent to catch up |
| leader changes | nothing (the leader plays no part) |
| `/reload` while still in the party | the session (your pins and id word, others' pins, dismissals, removal records) is written at logout and read back, checked as if it had just arrived, then `hi` |
| login (not a reload), or reload outside a party | starts empty; the saved session is cleared either way |

The game may still hold an already queued message in ChatThrottleLib when you leave a party. TwichUI can't
take it back.

## Taint and protected actions

* TwichUI never opens the world map (`ToggleWorldMap` / `OpenWorldMap` would run `ShowUIPanel` from addon
  code). EllesmereUI's quest tracker notes that this can leave the map unable to do some things in combat.
  **Show on map** moves a map the player already opened (`SetMapID`), or waits up to 2 minutes for them to
  open it.
* **Set waypoint** is `C_Map.SetUserWaypoint` (`PM.SetWaypoint`), and only where
  `C_Map.CanSetUserWaypointOnMap` allows it. It replaces the player's waypoint, as setting one on the map
  does. TwichUI doesn't super-track. It runs when **Set waypoint** is picked and when a pin is left-clicked
  on the world map or minimap, which also selects it (`PM.Activate`). Clicking the selected pin again
  deselects it and leaves the waypoint as it is. Selecting from the window's list, Show on map and saving a
  pin select without touching the waypoint.
* Nothing is protected: no secure buttons, no casting, nothing deferred for combat.

## Window and appearance

`/tui pins` (listed under Party pins options; not in `/tui help`, which is kept short), the data bar, or the
options' **Your pins**. It holds a count, a search box (names and map names), the filters All, Local, Party
and Removed, and rows with icon, name, map and coordinates, and who made it. Right-click or **...** opens the
actions. **More** has the bulk actions and the options.

Appearance is under Party pins options > Window appearance:

* background and border, as MenuStyle looks: the game's textures, LibSharedMedia's, and EllesmereUI's while
  it is installed;
* font (LibSharedMedia), text size, accent color, and comfortable or compact rows.

A missing texture or font is drawn plainly and stays chosen. **Reset window appearance** resets only these;
pins and the click and label choices stay. It looks complete without EllesmereUI.

### Map text

Party pins options > **Map text** styles the names drawn under pins on the world map and beside them on the
minimap, one look for both: font (LibSharedMedia), size 8 to 20, color, outline (none, outline, thick) and
shadow (on or off). Saved in `TwichUIDB.ui.pinsMapText`, only once changed. The defaults are the game's own
`GameFontHighlightSmallOutline` as this client defines it (`SystemFont_Shadow_Small`: Friz Quadrata 10, white,
1 pixel black shadow, no outline), so nothing changes until a choice is made. A name's width grows with its
size. A font that is missing or can't be drawn is drawn as the game's own and stays chosen. **Reset map text**
resets only this; the window's look, pins and the click and label choices stay (and **Reset window
appearance** leaves the map text alone).

**Pin names on the minimap** (Never, On hover and for the selected pin, Always; Never by default, so the minimap
is as it was) puts a name under each minimap pin in the same text look. The tooltip still has the name.

## Arrival sound

`pins/Sound.lua`. When a pin arrives from another player, one short sound plays (`PN.OnReceived`, the same
hook as the data bar highlight, so the same meaning of "arrives": a pin that was not in the session before,
not an update, a stale copy, a pin you already held or your own). It does not need a data bar addon.

* **Play a sound when a party pin arrives**: on by default.
* **Sound**: a LibSharedMedia sound name. TwichUI's own come first (`R.MediaSounds`, `modules/Media.lua`;
  the default is **TwichUI Map Pin**, `media/sounds/TwichUI_MapPin.mp3`), then every sound other addons have
  registered. TwichUI's are found by file, so they play with the "Custom fonts and sounds" switch off and
  without LibSharedMedia. A saved name that is no longer available stays chosen and the default plays
  in its place.
* **Volume follows**: the game channel the sound is played on (Sound Effects by default, Dialog, Ambience
  or Master). `PlaySoundFile(file, channel)` takes no volume, so this is the only volume control there is:
  the loudness is that channel's slider in the game's Audio options, and a muted channel is silent. This
  is the same limit and the same choice as the Friend login chime.
* **Hear the sound** plays it now, on the chosen channel.

Several arrivals within two seconds give one sound (a member placing several pins, or a burst of
messages). A full list that brings pins you did not have (joining a party that already has pins) plays it
once, as it highlights once. Pins you place yourself, and updates, play nothing. Nothing is written in chat.

Saved in `TwichUIDB.ui.pinsSound`, only once changed (`enabled`, `sound`, `channel`).

## Data bar

The data bar entry is `TwichUI Party Pins`. Click opens the pin menu, right-click opens the options.
LibDataBroker is not bundled. The object is made only when another addon provides the library, as with
TwichUI's other data sources. A data object can't be taken away, so with Party pins off it reads "Off"
until a reload.

Party pins options > **Data bar**:

* **Text on the data bar**: the count ("5 pins, 2 party", the default, as it always was), the number alone,
  "Map Pins", or none. With none the icon stays, so the entry is never empty.
* **Show the icon on the data bar**: on by default. Off sets the object's `icon` to nil, which a data bar
  reads as no icon (EllesmereUI's Broker Plugin block hides it).
* **Use my own text color** and its color: off by default, so the data bar's own text color applies. On, the
  text is wrapped in a color code. This is a limit of the object, not of TwichUI: a data bar may strip color
  codes from plugin text. EllesmereUI's Broker Plugin block does by default (its **Strip Colors** option, in
  the block's settings), so there the color shows only once that is off for this block. Source:
  `EllesmereUIDataBars/Blocks/LDB.lua`, `LDBStripColors` and `stripColors`.

* **Point out a new pin on the data bar** (on by default), **New pin shown for (seconds)** (2 to 30, 8 by
  default) and **New pin color**: when a pin arrives from someone else in the party, the text changes to
  "New pin: <name>" (a name is cut to 24 bytes; "2 new pins" when several arrive within the time), in the
  chosen color, then goes back to what it was. Nothing in chat; the sound is separate (see Arrival sound below). The icon is tinted the same
  through `iconR`/`iconG`/`iconB`, which EllesmereUI's Broker Plugin block honors
  (`Blocks/LDB.lua`, `IconTint`), so there is still a color change when it strips the text's color codes.

  What counts as arriving: a pin that was not in the session before, from `PN.ApplyPut`, or new in a
  member's full list (`PN.ApplyAll`, so joining a party that already has pins says "N new pins" once).
  Not: updates and stale copies, pins you already held (a hello after `/reload`), your own, or a restored
  session. Another arrival restarts the time (the older timer is ignored by a token), and the highlight
  ends at once if the option is turned off or Party pins is. `PN.OnReceived(fn)` is the hook.

Saved in `TwichUIDB.ui.pinsBroker`, only once changed (`text`, `icon`, `customColor`, `color`, `flash`,
`flashSeconds`, `flashColor`).

### The pin menu

`pins/BrokerMenu.lua`. It opens beside the data bar entry, on the side with room (the same placement the
Mage launchers use, `SpellMenu.PlaceNear`), and closes on Esc, a click elsewhere, or a second click on the
entry. A pared-down pin window: a row for each pin on your map (not the ones you removed from it), at most
seven in view and a scroll bar for more.

* The **pin icon** is the color: click it for a row of the pin colors.
* The **name**: click it to rename in place. Enter keeps it, Esc or clicking elsewhere leaves it. Nothing is
  changed until Enter.
* **x** removes: a local pin is deleted (no question; it can't be undone); one of your own party pins asks
  first and is removed for the whole party, the same question as in the window; someone else's party pin is
  taken off your map only, and the window's Removed filter restores it. A kept pin has a padlock instead
  (see "Keeping pins"): it opens the editor.
* **Open the pin window**, and **Clear unprotected pins...**. It asks first, with the numbers: it deletes
  your unprotected local pins and takes unprotected party pins off your map, and says how many kept pins
  remain. Nothing is sent, and party pins you made stay on your party's maps.

Rename and recolor are for local pins and your own party pins only, as in the window, and every action is
checked again when it runs (`PN.Can`). There is nothing secure in the menu, so it works in combat. While a
name is being typed the list isn't redrawn, so a message from the party doesn't take the text away.

Its **background and border** are its own look (`pinsBrokerMenu`, Party pins options > Data bar menu
appearance, with a Preview that opens the real menu beside the options). Its defaults are the Mage launchers'
menu defaults, so they match until one is changed; changing one doesn't change the other. Its text follows
the pin window's font and size.

## The new pin window

The editor that opens for a new pin, and to rename or recolor one, has its **background and border** as its
own look (`pinsEditorLook`, Party pins options > New pin window appearance, with a **Preview** that opens
the real window beside the options with a made-up pin; its Save does nothing). The choices are the pin
window's: background and border texture, color, opacity and border thickness. Its defaults are the pin
window's, so the two match until one is changed; changing one doesn't change the other, and resetting it
touches nothing else. The window grows by the border's reach so a thick border never covers its content.
For an EllesmereUI texture that reach is the visible line's, not the whole thickness (`Borders.Inside`): the
texture's edge cell is centered on the frame's edge and its line is only a fraction of the cell, so the
cell's size is not empty margin. The pin window and the data bar menu use the same rule (`PL.Surface`).
Its text follows the pin window's font, text size and accent. Before this it drew the Chronicle's ledger
frame regardless of the pin window's choices.

## References and licenses

* **PartyPins 0.9.0** (`../reference_addons/PartyPins`, Interface 16001; files examined: `PartyPins.lua`,
  `PartyPins.toc`). It has no license file and no `X-License`, so nothing was copied. It shares markers as map
  links in party chat, takes over the game's single user waypoint, and redraws minimap pins every frame (TwichUI throttles its updater and moves a button only when it needs to).
  TwichUI does none of these.
* **MapPinEnhanced 3.2.2** (`~/Downloads/MapPinEnhanced-3.2.2.zip`, read in place and not extracted; Interface
  120007, so Retail; files examined: `modules/pins/pinFactory.lua`, `pinManager.lua`,
  `modules/constants/constants.lua`, `modules/misc/blizz.lua`, `modules/sets/setManager.lua`,
  `utils/persist.lua`, `modules/core.lua`). Its code is GPLv3 and its assets are CC BY-NC-ND 4.0, neither
  compatible with TwichUI's MIT code. It informed only the idea of named, colored pins with a per-pin menu.
  No code, colors or assets were taken: TwichUI's colors are its own.
* Blizzard source was read for behavior, not copied.
* The layout screenshot mentioned in the request was not available. The window follows the structure it was
  described as having.

## Manual checklist (two or more clients)

1. Create several local pins (Alt-click) and party pins (Alt-Shift-click). Cancel one party pin and confirm
   nobody receives it.
2. On the other client, check names, colors, the party badge and the tooltip's "Party pin from ...".
3. Rename and recolor an owned party pin. Check it changes on the other client, with no duplicate.
4. On B, Remove from my map. Check A and C still see it.
5. Have C `/reload` (A answers B's or C's hello). Check B still has it removed.
6. On B, Restore it from the Removed filter.
7. On A, Remove for entire party. Check the confirmation, then that it is gone on B and C.
8. On B, try to remove or edit A's pin. Check those actions aren't offered.
9. On B, Save to my pins on A's pin: the new pin window opens filled in with Keep on; Cancel makes nothing,
   then again and Save. Remove the original on A, move A's pin (re-place it), have A leave the party. Check
   B's copy stays, is unchanged, shows as Kept and was never sent (A and C see nothing new).
10. Join and leave, change the leader, `/reload` in a party, log out and in, and group in an instance
    (`INSTANCE_CHAT`). Convert to a raid and back.
11. Group with a member without TwichUI. Check they see nothing and no chat appears.
12. In the window, try search, each filter, a long list (scrolling), and each action.
12b. Keep: see "Keeping pins checklist" below.
13. With a data bar addon, check the text, tooltip, click and right-click. Try each text choice, the icon
    off (and text None with the icon off: the icon stays), and a text color, with and without the bar's
    color stripping. Have another member place a pin: the text and icon change for the set time and then
    go back; place several quickly; join a party that already has pins. In the menu: rename (Enter, Esc, clicking away), recolor, remove a local pin, remove one
    of your own party pins (it asks), remove another member's (off your map only, restorable under
    Removed), open the window from it, and Clear unprotected pins (it asks, with counts; check the other
    client still has your party pins and your kept pins are still there). Open it in combat, with the bar at the top and at the bottom of the screen, and with more
    than seven pins.
14. Change the window's textures, font and accent. Remove EllesmereUI or a media pack and check the
    fallbacks.
15. Try different UI scales, long names (48 bytes, multibyte characters), and a full-screen map.
16. Check the player's own waypoint is unchanged until a pin is left-clicked on the map or minimap, or Set
    waypoint is picked (not by list rows, Show on map or saving a pin). Click the selected pin again and check
    it deselects and the waypoint stays.
17. Watch `/console scriptErrors 1` and the taint log (`/console taintLog 1`) for errors and "blocked"
    messages, especially opening the map and quest pins in combat after using pins.
18. Run `/tui diagnostics` and read the Party pins section.
19. Arrival sound: have another member place a pin and check the sound plays once, on the channel chosen
    (Sound Effects by default), and not for your own pins, for an update to one, or after a `/reload`. Turn
    Sound Effects off in the game's Audio options and check it is silent, then pick Master and check it
    plays. Try Hear the sound, another sound from the list, and the toggle off. Have the member place
    several pins in a second or two and check there is one sound.

### Sharing a saved pin checklist (two clients A and B in a party; items 12 to 14 need a third or a raid)

1. A: a local pin "Reagent vendor" on a map A isn't on, not kept. Not grouped: right-click it in the window,
   Share with group is greyed with "Join a party to share this pin." Picking it prints nothing else.
2. Group A and B. A: Share with group. B sees "Reagent vendor" at the saved coordinates (not A's position),
   color and name, as a party pin from A; A sees one marker, whose row says "shared".
3. A: Keep this pin on, then Share again; the same pin updates on B (no duplicate). Turn Keep off and delete
   the saved pin: nothing is sent, B keeps the pin, and A now lists it as "Your party pin" and can remove it
   for the party.
4. A: a kept pin. Share it. Check it stays kept, can't be deleted, B's copy isn't kept (B: Edit pin isn't
   offered), and Stop sharing... asks first and removes only B's copy.
5. A: rename and recolor the saved pin. B sees no change until A chooses Share again; then B updates the
   same pin.
6. A: the editor's Share button: changes are saved and sent in one step; Save alone sends nothing; Enter in
   the name box saves without sharing. The status line says "Shared with your party..." afterwards.
7. A: share on the minimap and map pins' right-click menu, and from the data bar menu's name right-click (the
   menu stays open; the row changes to "shared").
8. B: Save to my pins from A's shared pin: a new, independent local pin. A deletes or changes the shared
   pin: B's copy is unchanged. B tries Share with group on A's pin: greyed with the reason; B shares its
   saved copy: C (if present) sees it as B's.
9. A leaves the party and rejoins: A's saved pins are all still there and nothing is published; B has none of
   them until A shares again. `/reload` in the party: the saved pin still reads "shared" and sharing again
   updates the same pin on B.
10. A shares, B `/reload`s or rejoins: B receives A's copy once (the existing catch-up), as last shared.
11. In a raid: Share with group is greyed with "Pins can only be shared with a party, not a raid."
12. Share 20 saved pins: the 21st says why. `/tui diagnostics` shows the count of shared copies and no names.
13. In combat (a target dummy): the action works and no taint messages appear.
14. During an encounter or other chat lockdown: greyed with "The game is holding addon messages here right
    now."; no error. After it ends, sharing works.

### Keeping pins checklist (one client; the last item needs a second)

1. Make a local pin, edit it, tick Keep this pin, Cancel: nothing changed. Edit again, tick it, Save. The
   data bar menu lists it under Kept with a padlock and the marker tooltip says "Kept · Local pin".
2. `/reload` and log out and in: it is still kept. An older saved pin (made before this) is not.
3. Rename and recolor it while kept (editor and menu). Both work.
4. Click the padlock in the menu: the editor opens, the pin is still kept. Check its tooltip.
5. Try to delete it: the window's Remove pin is greyed with the reason; there is no x in the menu.
6. Make a few ordinary pins. Clear unprotected pins: the question's numbers match what you have (kept pins
   not counted as removed), and after Remove only the kept pins remain. With one pin and one kept pin, check
   the singular wording. With only kept pins the link is greyed out and says why.
7. Open the question, then (with the window) turn Keep on for one of the pins it counted, and accept: that
   pin stays. Open it again, make a pin with /way, and accept: the new pin stays.
8. The window's More menu: Delete unprotected local pins... asks with counts and leaves kept pins.
9. Edit a kept pin, untick Keep, Save: it can be deleted again, and nothing was deleted by unticking alone.
10. Hide a kept party pin of yours (Remove from my map): it comes back under Removed and is still kept.
11. Make a party pin with Keep ticked: Remove for entire party is greyed. `/reload` in the party: still
    kept. Leave the party: the pin ends with the session, as every party pin does.
12. Kept filter in the window; a long list of kept pins in the menu (heading, scrolling).
13. On a second client: Keep on one of your own party pins and check nothing is sent and the other client
    sees no difference (`/tui diagnostics`: sent count unchanged).
14. `/console scriptErrors 1`: no errors from the padlock texture, the heading rows or opening the editor
    from the menu in combat.

### Waypoint commands (one client; the last two with and without TomTom)

1. Party pins on. `/twichway 52.3 40.7` on a zone map: a pin there, named "Pin n", the chat line names the zone
   and coordinates. Compare its place with the same spot on the world map.
2. `/twichway 52.3 40.7 Rare spawn`: named "Rare spawn". `/twichway Nagrand 45 50 Rare spawn` and a
   multiword zone (`/twichway Elwynn Forest 45 50 Hidden chest`) land on those zones.
3. `/twichway #<a map id> 67.2 49.6 Name`; an id the game doesn't have is refused and makes nothing.
4. Decimals (`12.34 56.78`), the corners `0 0` and `100 100`, `52.3, 40.7`, `52.3,40.7`, extra spaces,
   `10 20 Camp 30 40` (one pin, name "Camp 30 40").
5. Refused with a message and no pin: no coordinates, one coordinate, `101 5`, `-1 5`, `5.5.5 4`, an unknown
   zone, a name that matches two maps (it lists them and suggests `#mapID`).
6. Coordinates only, with the world map closed, and with it open on another zone: always your own map, and
   the world map isn't moved or opened. Same while in combat.
7. `/reload`: the pins are still there. Existing placing (Alt-click, Place a pin) still works.
8. `/twichway paste`: paste several `/way` lines with a blank, a bad number and a `/run ...` line. The good
   ones become pins in order, the bad ones stay in the box with line numbers in the messages, `/run` is not
   executed. Press the button again: nothing is made twice. Open it in combat.
9. Without TomTom: `/way 52.3 40.7` makes a pin. With TomTom enabled: `/way` stays TomTom's, `/twichway` still
   works and an empty `/twichway` mentions it. `/tui diagnostics` shows who has `/way`.
10. Turn Party pins off in options: `/twichway ...` explains and makes nothing.
11. With WaypointUI (and no TomTom): `/way 52.3 40.7 Name` makes only WaypointUI's waypoint. Turn on
    "Also make a pin from /way": the same command makes WaypointUI's waypoint *and* a pin, and `/way reset`
    or `/way paste` make no pin. Turn it off again: back to the waypoint only, no reload needed. Check
    `/tui diagnostics` for "following it".
