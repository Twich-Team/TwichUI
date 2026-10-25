# Map tools

**TwichUI settings > Map > Map Toolbar > Show the map tools bar** (`pins/MapTools.lua`; the choice is
`ui.partyPins.toolbar`, on by default). Written against the WoW: Forever UI source (`../wow-ui-source`, branch
`forever`). **Nothing here has been run in the game yet**: everything below is source-verified and covered by offline
tests with mocked frames (`tests/test_map_tools.lua`), not seen working in play, alone or in a group.

A small bar of four icon buttons in the world map's title row, for what Party pins and Map pings already do with modifier
clicks, so a player can find them without remembering the clicks: **Pin** (a personal pin), **Group pin**, **Group ping**
and **Help**. Their tooltips name them. The shortcuts are unchanged and stay the fast path.
This is an input and discoverability layer: it adds no pin storage, no message and no rule of its own.

## What a button does

A tool is one-shot. Clicking its button **arms** it: the button stays lit (fill and outline, so not by color alone), the
pointer takes the game's own pin cursor (`MAP_PIN_CURSOR`, as the game's waypoint tool uses) and a strip under the bar
says what the next click does ("Click the map to place a personal pin. Esc to cancel."). Arming opens, makes and sends
nothing. The next **plain left-click on the map** does the action once and puts the tool away.

| Tool | The action | Shared helper |
|---|---|---|
| Pin | opens the new pin window (a local pin); nothing is made until Save | `PinsMap.PlacePin("local", x, y)` |
| Group pin | opens the same window as a party pin; sent only on Save | `PinsMap.PlacePin("party", x, y)` |
| Group ping | sends one ping (the checks, limits and message in `docs/map-pings.md`) | `MapPingView.PingAt(x, y)` |

`PlacePin` and `PingAt` are what the modifier-click handlers (`pins/Map.lua`, `pins/PingMap.lua`) call too, so a shortcut
and a button give the same result, including the same refusals and sentences.

## One input, one action

The tool click is a map canvas click handler at **priority 110**, above the ping click (105), WaypointUI's (100) and the
pin clicks (95). It takes only a plain left-click while a tool is armed; the handler registry stops at the first handler
that answers true, so no other handler sees that click. The map only hands handlers a click when the pointer stayed
within a few pixels (`MapCanvasScrollControllerMixin:WouldCursorPositionBeClick`, `OnMouseUp`), so **a drag or pan never
places anything**; the bar adds no mouse scripts to the canvas. The place is the map's own normalized cursor position on
the map being viewed at the moment of the click (`Quantize`, `ValidMap` and `MP.Steps` decide whether it is usable).

A **shortcut used while a tool is armed** is that shortcut's, once: the tool's handler sees a click that matches a pin click
or the ping gesture, puts the tool away and lets the shortcut's own handler act. Shift-click, Ctrl-click and right-clicks
are the map's (or another addon's) and leave the tool armed. The older "Place a pin" (pin window) and "Ping the map"
(`/tui ping`) arms and the bar's tools cancel each other, so only one armed click exists at a time.

## Put away when

* **Esc** (below), or the active button again, or another tool (it replaces the first), or **Help** (the help and a tool
  don't share the strip's place).
* The map closes, the bar or Party pins is turned off, a profile changes, or the tool can't be used any more (you left the
  group, Map pings or sending was turned off, the game is holding addon messages). The reason is said once. A tool is also
  asked again at the click itself, so a group that went away just before the click opens nothing.
* A successful action, or the hand-over to the pin window.

**A map change does not cancel it.** The strip stays in view and the place is read from the map being viewed when you click,
so you can arm a tool and then pick the zone. A click on an invalid place (the cosmic map, a map the game doesn't know, a
place outside the map, pinging too quickly) says why in one sentence and leaves the tool armed to try another spot.
Clicking a pin or the bar itself is not a map click; clicks on the bar, the strip, the help and the note never reach the map.

## Esc

`CloseAllWindows` closes the map's UI panel before it reads `UISpecialFrames`, so a stand-in special frame cannot get in
front of the map's own close, and `RegisterGameMenuEscHandler` taints the game's handler list (see the settings window's
history), so neither is used. Instead a one-pixel **keyboard catcher** (a child of the bar, no mouse) takes the keyboard
**only while a tool is armed or the help is open**: every key but Esc is passed on (`SetPropagateKeyboardInput(true)`),
and Esc is taken for that moment (`false`) and cancels the tool, or closes the help, instead of closing the map. It is the
same per-key pattern `setup/ExplorerWindow.lua` uses. `SetPropagateKeyboardInput` has restrictions in the API
documentation, so it is not used in combat (no catcher: Esc then does what it always does, and closing the map still puts
the tool away) and each call is guarded. **Unverified in the game:** that this Esc is really taken before the map closes.

## Unavailable tools

The three tools are always on the bar. One that can't be used is dimmed (an icon colored grey is not the only signal: the
tooltip names the reason) and is **not disabled**, so its tooltip stays readable; clicking it says the reason as a notice
and arms nothing:

* Group pin alone: "Join a party to place a group pin."; in a raid: "Party pins are paused while you are in a raid."; and the
  existing sentences for the game holding messages, not ready, and the per-owner and per-party limits.
* Group ping alone: "Join a party or raid to send a group ping."; with Map pings or sending off: "Map pings are turned off
  in the Pins and Pings options." / "Sending map pings is turned off in the Pins and Pings options."
* Pin with the list of local pins full: the same sentence Save gives.

The checks are the features' own (`PN.SendBlocked`, `MP.Route`, the switches). The bar looks again, one tick after
`GROUP_ROSTER_UPDATE` (so Party pins' own listener has run, whatever the order), and when pins or the ping choices change; it
rebuilds nothing. It never turns group sharing on or bypasses a switch.

## Tooltips and help

Each tool's tooltip says what it does, "Click this button, then click the map. Esc cancels.", its **shortcut**, and the
reason when it is unavailable. Personal pins are private and kept; group pins are shared with the party members who have
TwichUI with Party pins on, last while you stay in the party and are sent only on Save; group pings are a temporary signal
for a few seconds, not saved, and reach members with TwichUI (Party pins and Map pings on). Nothing promises another addon
will see anything.

The shortcut phrases are built each time from the saved choices (`PL.Pref("localClick")`, `PL.Pref("partyClick")`, the ping
gesture): "Alt-click the map", or "No shortcut is set" when a choice is Off. **Help** opens a small panel listing the three
tools and their shortcuts, closable by its Close, the Help button, Esc or the map closing. It is not a tutorial and not modal.

## The note shown once

"Map tools / Add personal pins, share locations, or ping your group. Use these buttons or hover to learn shortcuts. / Got it",
under the bar. It shows the first time the bar is available **in a session** and is kept for good by **Got it** or by using
any control on the bar (arming a tool, Help). It never has to be dismissed to use the map, and it does not come back
on later map openings, logins or profile switches once seen. The record is `TwichUIDB.ui.mapToolsIntro = true`: account-wide
(listed in `Profiles.lua`'s `ACCOUNT.ui`, so no profile change touches it), and kept local in configuration sharing
(`TC.LOCAL["ui.mapToolsIntro"]`). It does not use the Welcome dialog's `welcome.state`. A user who has never seen it (every
existing user) sees it once; one who closes the map without using it sees it again next session, until they have.

## Place, size and look

In the map's **title row** (`Blizzard_WorldMap.lua` `AddOverlayFrames`: the `NavBar` fills the row from the breadcrumbs to
the game's button at the right): the bar's right end is anchored 6 units in from the navigation bar's right end, centered on
it, so it takes the empty stretch beside the breadcrumbs, and sits 5 frame levels above the navigation bar. It has no
labels: four 24-unit icon buttons (the tooltips name them) about 150 units wide, so a long breadcrumb trail on a small map
can still run under it; the only remedy is the **Show the map tools bar** switch. If the map has no `NavBar` (another
addon or client change) it falls back to the top left of the canvas, 4 units in and 30 down. The strip and the help sit
there too, at the canvas's top left below the floor list and clear of the recent-pings list (the help is held to 45% of the
map's width); the once-only note hangs from the bar's lower right corner so it points at it. Drawn with the data bar menu's
look (charcoal stone, bronze line; the player's `Menu look`, `PL.MenuLook`), ivory text, the shared teal for hover and the
armed tool, the pin window's font and size. No animation of its own (so nothing to reduce) and no persistent effect. The border
is drawn through `PL.Surface`, which takes an EllesmereUI textured border's real line into account, and is drawn again when the
map's size (so scale) or the look changes; the frames are first made when the map is first shown, after every addon has loaded.

## NPC search (optional)

**TwichUI settings > Map > Map Toolbar > Show NPC search** (`npcs/SearchBar.lua`, `npcs/Search.lua`; the choice is
`ui.partyPins.npcSearch`, **off by default**, so an existing bar keeps its layout; it is greyed out, with the reason, while the bar,
Party pins or Vendors and trainers is off). A field to the left of the buttons that searches the NPCs in your own list
(`docs/npc-map.md`: what you dealt with and what others sent you, never the world) and shows one on the map. It adds no
command, key binding or database.

* **The field.** "Search known NPCs..." Made the first time the bar is laid out with the choice on; the rows only when a result
  first needs one (at most 8, reused). It never takes the keyboard by itself (not when the map opens, not when the bar is
  drawn); a click does. It takes what the map's navigation bar has left after the buttons and 220 units for the breadcrumbs,
  90 to 170 wide, and is left out when that is under 90.
* **Matching.** Typing waits 0.2 s and then searches once. Every word has to appear in the name, area, role, title or
  profession, in any case and any order, as plain text (the World Knowledge tab's own filter, `NpcKnowledge.Filter`, so the two
  agree). An empty field says what it is for rather than listing the list; no match says "No known NPCs match.".
* **A result is one place.** An NPC with several known places is several results (that is how the list stores it), and two of
  the same name in one area also show their coordinates. They are told apart by `creature:map:x:y`, never the name. A place on a
  map this client doesn't know as a zone or smaller is left out, since choosing it could not work.
* **Nearest first.** Your place is read once per search and both places are turned into continent yards
  (`C_Map.GetWorldPosFromMapPos`, as Navigation does). Only places on the same continent (or instance) are compared, and the
  number is the straight line: the footer and the tooltip say so; it is not a walking distance or a time. Order: (1) places with
  a distance, nearest first; (2) places on the map you are on whose distance can't be told (no position of yours, as in an
  instance, or no world position), marked "this area"; (3) every other place by area, name, then key. Ties break the same way,
  so the order never shuffles. Every match is ranked and the nearest 8 kept, so a cap never drops a nearer place for an earlier
  one. Nothing is given a distance to complete the list. Rows stay put while you choose: no polling. A change to the list
  while the results are open searches again once, for the place they were made for.
* **Keys and mouse.** Up/Down (wrapping), Enter, a click on a row; Esc closes the list and lets go of the field (the text
  stays). A click on a row is not lost when the field loses focus first (the list stays while the pointer is on it); a click on
  the map, another tool, the help, the map closing or the feature going off closes it. The map click is only noted, never taken
  (a handler at priority 120, present only while the field is on).
* **Choosing** (`NpcMap.Locate`): the entry is checked to be still in the list; the map goes to the NPC's area
  (`SetMapID`, which is synchronous and tells its data providers); once the map has finished laying itself out its marker gets a
  brief ring (`pins/Pulse.lua`, the ping's ring; 2.6 s; the ping's own "reduced motion" choice makes it a fixed outline). A wait
  for a map is bounded (2 s), and a newer choice cancels it by token. It sets no waypoint, starts no route, sends nothing,
  plays no sound and changes no saved choice. A marker the chosen kinds hide is drawn for as long as it is picked out, and only
  that one; the pick ends when another is made, when the field is emptied or cleared (the x), when the map closes or goes to a map
  the NPC isn't on, or when the NPC leaves the list.
* **Limits.** The map supports going to an area, not arbitrary panning or zooming, so "bring into view" means the area's map. Not
  checked in the game: the field's look and width in the real title row, `OnArrowPressed` and focus behavior, a click on a row
  while the field has focus, that a map-canvas click handler at priority 120 sees a click first, and the ring on the marker.

## NPC filter button

**TwichUI settings > Map > Map Toolbar > Show NPC filter button** (`npcs/FilterMenu.lua`; the choice is `ui.partyPins.npcFilter`,
**on by default**; it is greyed out, with the reason, while the bar, Party pins or Vendors and trainers is off). A funnel button
before Help that opens a menu of the kinds of NPC the world map shows. It is there only while Vendors and trainers is on, as
Navigate is there only while Navigation is, and it is not a tool: nothing is armed. It adds no command, key binding or database.

* **One set of choices.** The checkboxes are `NpcPrefs`' `show.<kind>` (`npcs/Prefs.lua`), the same ones as Vendors and trainers in the
  settings: no copy, no key of its own. A change is drawn by the map's existing path (`NpcMap.Layout`, one call per change) and an
  open settings window is told to redraw; a change made in the settings (or by a profile) shows in an open menu.
* **The menu.** One row per kind of `NpcKinds.LIST` (18), under Vendors, Trainers and Services as in the settings, each a
  checkbox, the kind's icon and its name; the whole row is the click target and the kind's own tooltip is on it. All kinds are
  always listed, whether or not the area has any. It stays open while you check several. **Show all** and **Hide all** change
  only these kinds, in one write and one drawing (`NpcPrefs.SetAllShown`), and are dim when they would change nothing. They never
  touch pins, pings, a route or the NPC list, and send nothing. A list taller than the room under the button scrolls (a UIPanelScrollFrameTemplate as the
  pin menu uses, its bar hidden until needed); it is otherwise one panel at its full height, kept inside the map.
* **Several roles.** Not new: an NPC shows while any one of its kinds is checked and wears the icon of its first checked kind
  (`NpcKinds.Primary` through `NpcMap.ShownKind`). A merchant that repairs and sells food stays when only one of the two is hidden.
  A record with no known kind was never drawn and still isn't; nothing is discarded or invented.
* **Search.** Filters control normal visibility only. The search still finds an NPC whose kind is unchecked, and Locate draws that
  one NPC while it is picked out (`docs/npc-map.md`). The pick checks nothing and saves nothing. Changing the filter while an NPC is
  picked out redraws the rest by the new choices and leaves the pick as it is, **including unchecking the picked NPC's own kind**:
  it stays drawn until the pick ends (another pick, the box cleared, the map closing, going to a map it isn't on), and then
  the filtered view is back with no marker left behind.
* **Closing.** A click anywhere else (`GLOBAL_MOUSE_DOWN`, registered only while it is open; a press on the button is left to the
  button's own click), Esc (a `UISpecialFrames` entry, never the game menu's handler list), the same button, arming a tool or opening
  the help or the search list, the map closing, the bar, the button or Vendors and trainers going off. Opening it puts away an
  armed tool, the help and the search list. The menu takes the clicks on itself and none of the map's.
* **Cost.** Made the first time it opens (18 rows, 3 headings, one note; memory not measured), then repainted
  and laid out each time it opens; opening reads nothing from the NPC list. One listener (the prefs' change notice) repaints only an
  open menu. No timer, no `OnUpdate`.
* **Icon.** `media/textures/maptool-filter.tga`, 32 x 32 uncompressed RGBA TGA like the other tool icons, built from the supplied
  funnel artwork `assets/map-tool-filter-source.png` (1254 x 1254, real alpha, visible 737 x 640) by `tools/make_map_tool_icons.py`:
  cropped to the visible artwork, longer side 30 of 32 with a clear 1-pixel margin, premultiplied area-average downsample, no recolor
  or sharpening, centred; shown at 18 x 18 like its neighbours with the button's own hover and lit states. The artwork's own brass is
  kept, so it is a little brighter than the bronze of the other icons.
* **Not verified in the game:** the funnel's look and weight in the toolbar next to the other icons, the menu's placement under the
  button at real sizes and UI scales, scrolling on a short map, that Esc closes the menu before the map, that the global mouse event
  reaches the menu's close, and the look with EllesmereUI's border skins.

## Saved and not saved

Saved: `ui.partyPins.toolbar` and `ui.partyPins.npcFilter` (booleans, only once changed; they are the profile's and part of a shared
setup with the other Party pins choices; the filter menu's own checkboxes are `ui.npcMap["show.<kind>"]`, saved by Vendors and
trainers whoever changed them), and `ui.mapToolsIntro`. Never saved: the armed tool, the help being open,
a pending click, the strip. After `/reload`, a profile change, the map closing or the feature going off, all of that is gone.

## Not verified

Everything about the real game: how the bar sits in the title row beside the breadcrumbs and the other addons' header controls at real sizes
and UI scales, that `MAP_PIN_CURSOR` and look right, that the Esc catcher is taken before the map closes and `SetPropagateKeyboardInput` behaves outside combat as the
documentation says, that handlers at priority 110 run before WaypointUI's at 100 and every other addon's, that a drag never
reaches the handler (the map's own code says it can't), and the look with EllesmereUI's skins.

## Manual checklist

**Alone** (no group):
1. Open the map. The bar is in the title row, right of the breadcrumbs; the note shows once beneath it. Use any control, or press **Got it**:
   close and open the map, `/reload`, and it does not come back.
2. Hover each button: tooltips with the shortcut; Group pin and Group ping are dim and say to join a party.
3. **Pin**, then click the map: the new pin window opens at that spot; Save makes a local pin. A second plain click is the map's
   again. **Pin**, then click it again, press Esc, close the map: each puts it away (Esc must not also close the map).
4. Arm Pin, then drag the map: it pans and places nothing. Arm Pin, zoom out with a right-click: still armed.
5. Alt-click still makes a pin. With Pin armed, Alt-click makes one pin window, not two.
6. Help: the panel lists the three tools and your shortcuts. Change a click in the options: it follows.
7. Turn **Show the map tools bar** off: the bar and its handler go. On: it is back, once.
8. A minimized map with a deep breadcrumb trail (World > continent > zone > sub-zone): note whether the bar covers it.

**In a party** (two clients with TwichUI, one party; do not use a real group's channel for anything else):
1. Group pin and Group ping come alive without reopening the map. **Group ping** then click: the other client sees the ping
   once and one entry in its list. **Group pin** then click: the window opens as a party pin; nothing reaches the other
   client until Save.
2. Arm Group ping, then leave the party: it is put away with "Join a party or raid to send a group ping."
3. In a raid: Group ping works, Group pin says it is paused.
4. Ping four times quickly: the fourth says it is too quick and the tool stays armed.

**NPC filter** (with Vendors and trainers on and a few NPCs known; none of this needs a group):
1. The funnel is before Help, the same size as its neighbours and not clipped; its tooltip says "NPC Filters". Compare its brightness and
   weight with the other icons; hover and click states match theirs.
2. Click it: the menu opens under it, inside the map. Uncheck Auctioneers: their markers go at once and the others stay. Check three more
   without the menu closing.
3. Open the Vendors and trainers page in the settings beside it: the same boxes follow every click, both ways.
4. Show all, Hide all: the map redraws once; pins, pings and the NPC list are unchanged.
5. A merchant that repairs and sells food: hide one of the two, it stays; hide both, it goes.
6. Hide a kind, search for an NPC of it, choose it: it shows and is ringed; the box for the kind stays unchecked. Uncheck/check other kinds:
   the pick stays. Clear the search: the marker goes.
7. Close the menu by clicking the map, with Esc (the map must stay open), with the same button, by arming Pin, by opening Help or the
   search list, and by closing the map.
8. Shrink the map window until the list can't fit: it scrolls and its last row, and the note, can be reached.
9. `/reload`: the kinds are as you left them. Turn Show NPC filter button off: the button goes and the filters still apply.
