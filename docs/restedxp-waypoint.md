# RestedXP destination waypoint

**Quality of life > RestedXP guides > Mark RestedXP's destination** (`qol/GuideWaypoint.lua`, switch
`modules.qolGuideWaypoint`, off by default). Written against RestedXP Guides v4.11.22 and the WoW: Forever
UI source (1.60.1). Nothing here has been run in the game yet.

It puts the game's own waypoint (its map pin and in-world marker) on the place RestedXP's arrow is leading
to, and moves it on when RestedXP does. RestedXP's arrow, map pins, guide content and progress are not
changed. TwichUI draws no map pin of its own: RestedXP already pins the active step.

## Which place

* **RestedXP's arrow target**, `arrowFrame.element`: RestedXP's own choice across all active steps. Its
  priorities, completion, sticky steps and multi-coordinate steps are already resolved there
  (`map.lua` `updateArrowData`). It is not the first coordinate of the step.
* The field is not cleared when the arrow hides, so an element is used only when its step is active, it has
  an arrow, and it isn't skipped, hidden, or under a finished objective. Also required: RestedXP has
  active waypoints, and its arrow isn't hidden (in an instance, or with nothing left). On another continent
  the destination stands.
* **Hidden routing points** (`hidePin`: `.goto ...,radius,0` and `.waypoint`) stand for the next marked
  destination in the same step, so the waypoint doesn't hop along a route. With none after it (a kill-area
  loop), there is nothing to mark.
* **Points RestedXP makes up** (`generated`: corpse, spirit healer, route lines) are never used.
* The element's `zone` (a uiMapID) and `x`, `y` (percent) become `UiMapPoint.CreateFromCoordinates(zone,
  x / 100, y / 100)`, if `C_Map.CanSetUserWaypointOnMap(zone)` allows it.

## How it follows

`hooksecurefunc` on RestedXP's `UpdateMap`, `UpdateGotoSteps` and `ResetArrowPosition` (once; a hook can't
be removed, so they do nothing while the switch is off). `UpdateGotoSteps` runs about every 0.3 s. Each
call compares one reference and three numbers and returns; the waypoint is written only when the
destination changes. No polling, no `OnUpdate`. RestedXP is found through AceAddon (`RXPGuides`), at its
`ADDON_LOADED` (one frame later) or at login.

## The waypoint is the player's first

There is one user waypoint, shared by the player and every addon.

* It is placed only when the slot is empty or holds the point this placed. A waypoint the player placed is
  never moved or cleared, and turning this off leaves it.
* If the player clears or replaces the point this placed, that is respected: nothing is put back until the
  next destination, and then only into an empty slot.
* Each new destination is made the super-tracked one (the in-world marker). It is not taken back between
  destinations. RestedXP super-tracks quests itself when a step starts, and so may the player.
* Nothing to mark, a map the game refuses, or turning it off clears only its own point.
* The point it placed is kept per character in `ui.guideWaypoint[playerGUID] = { map, x, y }`, as the game
  read it back. After a reload, that point is then recognised as this one's (moved or cleared), not taken
  for the player's. No destination is acted on until that record has been read.
* Nothing is written in combat. The API documentation shows no combat restriction; this is a precaution.
  A change waits for `PLAYER_REGEN_ENABLED`.

## Status (in the switch's tooltip)

Off, RestedXP not installed or turned off, waiting for RestedXP, this RestedXP isn't supported, no
guide, no destination, no single destination (a route or area), can't mark this map, your waypoint is in
use, waiting for the next destination (ours was cleared or replaced), showing the destination.

## Limits

* `arrowFrame.element` and the element fields are RestedXP internals, not a public interface. A RestedXP
  update may change them; missing functions read as "isn't supported" and nothing is hooked.
* With RestedXP's **Number of Map Pins** at 0, RestedXP builds no waypoints, so there is nothing to follow.
* "Nearest point" steps (a negative radius) let RestedXP's arrow switch between points as you move, and the
  waypoint follows.
* Another addon writing the user waypoint (for example ShortestPathForever's *Follow RestedXP guides*) is
  treated like the player: this one steps aside.

## In-game checklist (not yet run)

1. Off by default; nothing changes with RestedXP until it is turned on.
2. On, with a guide: the game's map pin and in-world marker are on the step's destination. Is there a
   minimap marker? (the client draws it; not visible in the UI source)
3. Accept and turn-in steps with two NPCs: the waypoint moves from the first to the second when the first
   is done.
4. A step with a routing point before its destination: the waypoint is on the destination from the start.
5. A kill-area loop step: no waypoint; RestedXP's own pins and arrow are unchanged.
6. Go to step (RestedXP's menu), skip a step, switch guides: the waypoint follows; no guide clears it.
7. Place your own waypoint first: it is never moved. Clear it: the next destination is marked.
8. Clear or replace this one's waypoint: it is not put back for that destination.
9. `/reload` with a waypoint showing: it is moved or cleared afterwards, not left behind as "yours".
10. Combat: a destination change in combat is applied when combat ends.
11. Death: the corpse is not marked; the guide's destination returns after resurrection.
12. Instances: cleared inside; back on leaving.
13. Cities and other maps: `CanSetUserWaypointOnMap` answers; "Can't mark this map" when refused.
14. Turning it off clears its waypoint and leaves yours.
15. Does `SetUserWaypoint` work in combat? If so, the combat precaution could be relaxed.
