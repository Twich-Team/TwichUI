# Party pins

**Options > AddOns > TwichUI > Party pins** (`pins/`, switch `modules.partyPins`, off by default). Written
against the WoW: Forever UI source (`../wow-ui-source`, branch `forever`). **Nothing here has been run in the
game yet**: everything below is source-verified and covered by offline tests, not seen working in play.

Named pins on the world map. **Local pins** are yours only and kept between sessions. **Party pins** are
shared with party members who have TwichUI with Party pins turned on, for as long as you are in that party.
Players without TwichUI see nothing: nothing is written in chat and there is no fallback to map links.

## Files

| File | Owns |
|---|---|
| `pins/Pins.lua` | the data: checks, local pins, the party session's pins, dismissals, removal records, permissions |
| `pins/Sync.lua` | the protocol, the party session's lifecycle, rate limits, `/reload` hand-over |
| `pins/Look.lua` | the click and label choices, the window's look (MenuStyle look, font, size, accent, rows) |
| `pins/Map.lua` | the world map: data provider, pin buttons, placing clicks, Show on map, Set waypoint |
| `pins/Editor.lua` | the name, color and kind editor |
| `pins/Window.lua` | the pin window and the action menu (also opened from a map pin) |
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

* `list`: local pins `{ id = "L<n>", map, x, y, name, color, created, copiedFrom? }`.
* `nextId`: never reuses an id, even one held by an entry that can't be read. Unreadable entries are
  skipped, never erased.
* `session`: the party session, written at logout and read by the next load only. See "Reload".

The pin window's choices live in `TwichUIDB.ui`: `partyPins` (clicks, labels, window position), `pinsLook`
`pinsAppearance` and `pinsMapText` (the names on the maps). Only changed values are stored. An unusable value reads as its default and is kept.

**Session only** (in memory): party pins keyed by *owner + id*. The owner is the sender's name as the game
reported it, never a field of the message. Ids are a random six-character word per session plus a running
number (`k3x9qa:4`). Also kept: dismissal records ("removed from my map") and removal records (tombstones).
Frames, timers, queues and rate buckets are never saved.

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
| Remove pin | local pins | nothing | deletes that local pin |
| Remove from my map | any party pin, yours too | nothing | hidden on your map; survives updates and resyncs; listed under **Removed**, from where **Restore to my map** brings it back. Kept up to 100, for this party session. |
| Remove all party pins from my map | you | nothing | the same for every party pin |
| Remove for entire party... | **the pin's creator only** | `del` | asks first; then removed from your map and from every member who receives it; a removal record (up to 200) stops a late or replayed copy coming back |
| Delete all local pins... | you | nothing | asks first; party pins untouched |
| Keep as local copy | any party pin | nothing | an independent local pin (`copiedFrom`); a party-wide removal of the original never touches it |

* **Authorization is structural.** A pin's key includes its sender, so a `del` or `put` from B naming A's id
  only ever addresses B's own pins. There is no leader moderation. Leadership isn't needed to identify the
  party, and a leader's say over other people's pins wasn't asked for.
* The window offers owner-only actions only to the owner. Each action checks again when it runs
  (`Pins.Can`).
* The removal confirmation says party members with TwichUI remove it "when your message reaches them".
  Nothing confirms delivery and nothing claims it did.

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

## Data bar

The data bar entry is `TwichUI Party Pins`: the text is "5 pins, 2 party", click opens the window,
right-click opens the options. LibDataBroker is not bundled. The object is made only when another addon
provides the library, as with TwichUI's other data sources.

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
9. On B, Keep as local copy, then remove the original on A. Check B's copy stays.
10. Join and leave, change the leader, `/reload` in a party, log out and in, and group in an instance
    (`INSTANCE_CHAT`). Convert to a raid and back.
11. Group with a member without TwichUI. Check they see nothing and no chat appears.
12. In the window, try search, each filter, a long list (scrolling), and each action.
13. With a data bar addon, check the text, tooltip, click and right-click.
14. Change the window's textures, font and accent. Remove EllesmereUI or a media pack and check the
    fallbacks.
15. Try different UI scales, long names (48 bytes, multibyte characters), and a full-screen map.
16. Check the player's own waypoint is unchanged until a pin is left-clicked on the map or minimap, or Set
    waypoint is picked (not by list rows, Show on map or saving a pin). Click the selected pin again and check
    it deselects and the waypoint stays.
17. Watch `/console scriptErrors 1` and the taint log (`/console taintLog 1`) for errors and "blocked"
    messages, especially opening the map and quest pins in combat after using pins.
18. Run `/tui diagnostics` and read the Party pins section.
