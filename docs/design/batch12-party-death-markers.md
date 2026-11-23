# F18 — Party death map markers: evidence finding

Batch 12: **Investigated; marker implementation Blocked on position freshness**.
No markers or Party Wipe effects were added. Main baseline `eb866ce`; Forever
source `bebcb6b` (`1.60.1 (70938)`). No real-client evidence was collected.

## What is established

`!!!TwichUI/modules/PartyDeath.lua` confirms other party players (party1–4,
GUID identity, no raid/self/pets), ignores feign death, and announces only a
known alive → dead transition. It tracks unknown/disconnected states and clears
on roster/world changes. Its notification payload contains name/class/role,
**no location or capture timestamp**. A delayed queued card is not a position
sample. Keep its tombstone artwork (`media/partydeath/tombstone`) for future pins.

Forever `Blizzard_APIDocumentationGenerated/MapDocumentation.lua` declares:

- `C_Map.GetBestMapForUnit(unitToken)` returns a map, possibly nothing.
- `C_Map.GetPlayerMapPosition(uiMapID, unitToken)` explicitly supports player and
  party members, returning a nullable vector2. It does not specify freshness,
  corpse vs ghost position, range, phase or behavior at a death transition.
- World/map conversion APIs exist, but cannot make an unreliable sample reliable.

`UnitDocumentation.lua` declares `UnitPosition(unit)` with world X/Y/Z/mapID;
that mapID must not be assumed to be a UI map ID. No freshness or death-position
contract is established there either. Current Guild Locations reads only the
local player's position; received guild positions expire and are not death proof.
Never borrow those coordinates, the player's map position, or last-alive samples.

`pins/Map.lua` uses a MapCanvas data provider, pooled buttons and verified parent
map/world conversions, with no per-frame work. It owns personal/shared pins and
waypoint interactions. Future death pins should use a separate transient provider
or a small read-only adapter; never persist deaths as personal pins, broadcast
positions, overwrite waypoints or open the map automatically. No map code changed.

## Why no marker yet

A synchronous position query is a plausible candidate, but source declarations
do not prove the returned position is current at the confirmed death rather than
a cached last position or a released ghost. The request explicitly forbids stale
or approximate death locations. Installing a marker now would make that claim
without evidence. There is no suitable native recording; synthetic coordinates
can only validate rendering/lifecycle, not freshness. This is a narrow evidence
blocker, not an assertion that Forever lacks party position APIs.

## Owner-directed test (two cooperating clients)

Use a disposable/manual diagnostic session; do not log names, GUIDs or positions
in routine exports. Keep any location notes private and report outcomes rather
than raw coordinates.

1. Same zone, visible party member: note their recognizable map landmark. At the
   alive → dead transition, read that **same party token**, checking plain GUID
   before/after, connected/player/non-feign dead state, BestMapForUnit and
   GetPlayerMapPosition for that unit/map in the same callback. Record whether
   all checks were readable and the map landmark matched; do not substitute
   `player` on nil. Compare the cooperating client's death location.
2. Repeat after moving immediately before death, at distance/out of sight, in an
   instance/different floor and with different maps/phases. Verify nil/restricted
   results reject placement. A matching zone alone proves nothing.
3. Release spirit and move the ghost. Determine whether the party API follows
   ghost or corpse, and whether the original death sample can remain justified.
   Never update a death pin to the ghost. If identity/state is unknown, invalidate.
4. Resurrect, die again, disconnect, leave/rejoin, reuse party tokens, enter raid,
   zone/reload, and change viewed maps. Verify membership/state events can remove
   or invalidate the exact member's record promptly, including during combat.
5. Return client build, scenarios, event order, readability/freshness results and
   mismatches. Do not mark native checks complete from mocks. If death samples
   remain stale/ambiguous, retain the existing notification only.

Once evidence passes, implement at most four in-memory GUID-keyed records with
sample time/map/coordinate and verified lifecycle, no history or transmission.
Capture only in the confirmed transition; recheck identity/dead state before and
after the read. Remove on resurrection, departure, raid/world transition,
disable or unknown identity/state. Never backfill a missed death from later
coordinates. Test same-map/ancestor-map placement and pooled cleanup synthetically;
verify actual accuracy and combat behavior in the client before claiming it.
