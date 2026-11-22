# TwichUI Fishing (Stage 1: foundation; Stage 2: Fishing Mode)

One key that takes the next fishing step on each press, a record of what you catch (Stage 1), and Fishing Mode, an
immersive way to fish with it (Stage 2, [below](#fishing-mode-stage-2)). It is a load-on-demand addon,
`TwichUI_Fishing/`, with a small core launcher. Client evidence and limits are in
[fishing-feasibility.md](fishing-feasibility.md). **Nothing here has been checked in the real client.** Every claim is
unit-tested against `tests/fishing_mock.lua` or not tested at all (see "In-game verification").

## Loading

`!!!TwichUI/FishingLauncher.lua` (always loaded, about 125 lines) names the two key bindings and loads `TwichUI_Fishing` on
`/tui fish` (any subcommand; `/tui fishing` is an alias), or at `PLAYER_LOGIN` and after `UPDATE_BINDINGS` when one of its
keys is bound. It never loads in combat: a request waits for `PLAYER_REGEN_ENABLED`. The bindings live in the core
`Bindings.xml` under Key Bindings > TwichUI. TwichUI never binds a key.

- `CLICK TwichUIFishingButton:LeftButton`: "Fishing: the next step".
- `CLICK TwichUIFishingOpen:LeftButton`: "Fishing: open the next fishing container".

Loading the addon is the player's opt-in, so the module defaults to on (`/tui fish off` turns it off). Packaging: `.pkgmeta`
moves `TwichUI_Fishing` beside the core, and `tools/release.py` expects it in the release zip as load-on-demand with
`RequiredDeps: !!!TwichUI`.

## Files (TwichUI_Fishing.toc order)

| File | Owns |
|---|---|
| `Data.lua` | `R.Fishing` (F), seed data (spell, lure and clam ids), limits, helpers, notifications (`F.Subscribe/Emit`), runtime notes (`F.Note`), `F.Say` |
| `Store.lua` | `TwichUIFishingDB`: schema, migrations, narrow repair, newer-schema hold, preferences (`S.Get/S.Set`), learned enchants and containers |
| `Session.lua` | Sessions, casts, catches, items, failures, per-species and per-zone totals, idle end, retention |
| `Gear.lua` | Pole and outfit choice, the original-equipment snapshot, restoration, the player's own changes |
| `Lure.lua` | Lure status, choice and application bookkeeping; learning which enchant id is a lure |
| `Containers.lua` | Recognising fishing containers, the queue, opening (by press, or opt-in automatic), contents attribution |
| `Loot.lua` | Loot windows: catches, items taken, dedupe, auto-loot confirmation, container windows |
| `Action.lua` | The secure buttons, the decision (`A.Decide`, pure), reel overrides, the recast guard, combat, interaction targeting |
| `Api.lua` | Read-only interface for later stages; diagnostics and `/tui fish status` |
| `Journal.lua`, `JournalUI.lua` | Stage 3A: the Journal's data (from `R.Fishing.API` only) and its window and session summary |
| `Main.lua` | Start-up, event wiring (core bus `R:On`), `/tui fish` commands, gauges |

## Public interface (for Stages 2 to 5)

Everything returns a copy. Nothing builds frames or loads anything. `R.Fishing.API`:

- `State()` returns `"idle"` (no session), `"ready"`, `"line"` or `"looting"`.
- `Session()` returns the session in progress plus `elapsed`, or nil. `Sessions(n)` returns the newest summaries first.
  `Totals()` returns the lifetime totals.
- `Provenance(scope)` takes `"session"`, `"lifetime"` or a session id. It returns `{ direct, containers = { caught, opened,
  unopened }, contents }`. Containers are never in `direct`, and contents are never catches. Valuation must count an opened
  container by its contents and an unopened one, at most, as itself.
- `Lure()` returns `{ state, seconds, enchantID, lure, identified, choice, why }`. `state` is `no-pole`, `none`, `active`,
  `expiring` or `unknown`.
- `Gear()` returns `{ state = none|fishing|pending, poleWorn, outstanding, kept, missing, leftOn, since, kind }`.
- `Queue()` returns `{ { item, n, sid, t, locked } }`, oldest first. `Next()` returns `{ kind, why }` for the next press.
  `ZoneName(mapID)` returns the remembered zone name. `Diagnostics()` and `Report()` return the status as a table and as lines.
- Stage 3A adds `SessionByID(id)` (one kept session, or the one in progress), `Treasures(scope)` (`{ containers = { [id] = {
  caught, opened, failed, unopened, got = { [item] = q } } }, contents }`, scope as `Provenance`) and `Retention()`
  (`{ kept, limit, held, available }`).

`R.Fishing.Subscribe(event, fn)` delivers `fn(event, ...)` for these events: `STATE(new, old)`,
`SESSION_START(id, reason)`, `SESSION_END(id, reason)`, `CAST(guid)`, `CAST_FAILED(kind)`, `CATCH(sid, slots)`,
`ITEM(itemID, q, "direct"|"content", sid, containerID)`, `CONTAINER(what, item, ...)`, `QUEUE`, `LURE(what, ...)`,
`GEAR(what, ...)`, `NOTICE(text)`, `CONFIG(path, value)` and (Stage 2) `PRESENT(on, mode)`. A failing listener is reported with `R.Fault`, and the other
listeners still run.

## The fishing key

Each press is one step, decided in the button's `PreClick` out of combat by `A.Decide(A.Context())`. Priority order:

1. `none` when the module is off, in combat, while a line is out (that press should have been the reel override), while
   channelling something else, while a loot window is open, or within `action.guard` seconds (default 1) after a fishing
   line or fishing loot window ended.
2. `restore` (secure `/equipslot` macro) when no session is in progress and gear is still to be put back.
3. `outfit` / `equip` (the configured outfit, or the preferred pole, else the best-quality pole in the bags). Skipped with
   "bags full" when the off-hand item would have nowhere to go. With no pole anywhere, the key casts and the game decides.
4. `open` the oldest queued fishing container (`containers.openWithKey`, at least `containers.minFree` free slots).
5. `lure` when the pole has no temporary enchant (or, with `lure.early`, one ending within that many seconds).
6. `cast` Fishing (the first known id of the seed list). Otherwise `none` ("you don't know Fishing").

A press that equips, lures or casts begins a session. When the line starts, the player's keys get an override to
`action.reel` (`INTERACTTARGET` by default; `/tui fish reel mouseover` switches to `INTERACTMOUSEOVER`). The override is
inert while the soft target is positively an NPC or a player. It is removed when the line ends. A `none` the player can
act on shows one short line in the game's error area (never chat).

**States:** `idle` → (equip, lure or cast press) → `ready` → (channel start) `line` → (loot) `looting` → `ready` …
(`/tui fish stop` or idle timeout) → `idle`.

**Combat:** `PLAYER_REGEN_DISABLED`, while changes are still allowed, removes the overrides. With
`gear.combatWeapons` (default on) and fishing gear on, it arms the key with the weapons-back macro; otherwise the key is
inert until combat ends. Nothing is changed during lockdown.

## Lures

The pole's main-hand temporary enchant comes from `C_Item.GetWeaponEnchantInfo`, read only while a pole is worn. An enchant
id counts as a lure once one appeared within 4 s of the key applying a lure (`learned.enchants`). Any other temporary enchant
is reported as unidentified, and no lure is used over it. Choice: `lure.preferred` when it is in the bags. Otherwise, when
none is preferred or `lure.alternative` is on, the highest-bonus seed lure. A missing lure is reported and the key simply
casts. An expiring lure never touches a line that is out.

## Equipment and recovery

`Capture` stores, just before the press acts, the item id and link of each slot the change will touch: the weapon slots for
a pole, every slot for an outfit. It runs only when no snapshot exists, so the original gear is never replaced by fishing
gear. The record is saved immediately (`chars[...].gear`), so it survives reloads and disconnects.

- **Restore** happens at session end (`gear.restoreOnEnd`), on `/tui fish restore`, after combat when pending, and 2 s after
  login when a reload or disconnect ended the session. It uses `C_Item.EquipItemByName(link, slot)` out of combat, main hand
  first. If the changes are not seen within 2.5 s, the state becomes `pending`, a line says so, and the fishing key
  performs the secure macro.
- **The player's own changes:** a slot changed by hand to anything but a pole (or the off hand emptied by the pole) is
  marked `kept` and never overwritten. A slot put back by hand counts as restored.
- **Interrupted swaps:** if an equip press produces no change, the snapshot made for it is dropped (`equip-failed`).
- **Missing items** (sold while fishing) are reported, and the rest goes back. A slot that was empty and that the outfit
  filled is left on (`leftOn`).
- **The snapshot is cleared** only when every slot is back or kept, or by `/tui fish forget`. A damaged record keeps its
  snapshot as `pending`.

## Catches

Each loot window gets one capture. A window with `IsFishingLoot()` is one catch. Each item is counted when its
`LOOT_SLOT_CLEARED` arrives, once per slot. A slot still uncleared at close waits 2 s for the client's own `CHAT_MSG_LOOT`
line before counting; otherwise it was left (full bags). Duplicate `LOOT_READY`, `LOOT_OPENED`, `LOOT_CLOSED` and slot
events are ignored, and money slots are not items. Loot that is neither fishing nor a fishing container is unrelated and
never recorded. A fishing line that ends with no fishing loot within 1.5 s, and was not interrupted, counts as `missed`.
Bag changes are never evidence of a catch.

## Containers

Only items from fishing loot are considered. A container is recognised either from the seed clam list, or because the bags
call the item openable (`hasLoot`), which is then learned. It joins the queue as a lot `{ id, item, n, sid, t }`.

- **Modes** (`/tui fish containers queue|auto|off`): `queue`, the default, opens only on a press of the fishing key between
  casts or the open key. `auto` also opens from addon code after a catch, but never in combat, during a line or while
  looting; the first block (`ADDON_ACTION_BLOCKED`/`FORBIDDEN`) stops it for good (`capability.autoOpen`). `off` records
  only.
- **Attribution:** the loot window that opens within 3 s of an opening press belongs to that lot. A clam the player opens by
  hand is matched only when exactly one queued item has exactly one fewer in the last settled bag counts.
- **Opened or not:** a container counts as opened once it leaves the bags. One that stays (loot left in it) stays queued,
  marked `partial`.
- **Failures:** a press with no loot window is counted as `failed`. A locked container (`ERR_ITEM_LOCKED`) is marked
  `locked` and skipped.
- **Reconciliation:** the queue never claims more than the bags hold, and is trimmed newest-first when items leave.
- **Credit:** contents go to the session the container was caught in, even if that session is already in the history.

## Saved data

`TwichUIFishingDB` (account-wide; `schema = 2`; see `docs/persistence.md`):

- `config` holds preferences (the defaults are in `Store.lua` `S.DEFAULTS`; each leaf has a checker in `S.CHECK`).
- `client.saved` holds the targeting values to put back. `capability.autoOpen` records `"worked"` or `"blocked"`.
- `chars["Name - Realm"]` holds `nextSession`, `nextLot`, `session` (as for a summary, plus `recent`: the last 20 catches),
  `sessions[]` (at most `session.keep`, default 100, range 10 to 500), `totals`, `queue[]` (at most 200 lots),
  `gear = { state, snapshot = { at, kind, slots[slot] = { id, link, kept, missing, leave } } }`,
  `learned = { enchants[id] = lureItem, containers[id] = true }` (at most 200 each) and `zoneNames[mapID]`.
- A session summary or the totals hold `casts, catches, items, failed, interrupted, missed, line, seconds, first, last`, plus
  `species[id] = { q, c, f, l }`, `containers[id] = { caught, opened, failed, got[id] = q }`, `contents[id] = q` and
  `zones[mapID] = { casts, catches, items, line }`. A summary also has `id, start, last, stop, ended, zone, reason`.
- **Where things were caught (schema 2).** Each summary and the totals also hold `spz[mapID][itemID] = { q, c, f, l }`
  (quantity, times caught, first and last catch there, direct catches only), `ctz[mapID][containerID] = { caught, opened, failed,
  got[itemID] = q }` (containers by the zone they were *caught* in) and `spn` (how many `spz` entries: capped at 4000 for the
  lifetime totals, so the file stays small however much is fished; an entry is per species per zone, never per catch). Map 0 is
  a catch whose zone the game did not give. The character also has `locSince` (when recording began) and each queued lot has
  `zone` (where it was caught; nil on a lot saved before schema 2).

Items are stored by id only, and no prices are stored. Lifetime totals are never trimmed; only summaries are. Migrations
(`S.MIGRATIONS`) are ordered and repeatable. An unversioned table becomes schema 1, then 2. A newer schema is held untouched:
nothing is recorded or changed for the session, and the key still casts.

**Schema 2 migration.** It changes nothing that exists: every lifetime total, session, zone total, container record, queued lot,
gear snapshot and setting is kept as it was. It adds the empty location records (when each record is next normalised) and
stamps `locSince`. It invents nothing: a species caught before schema 2 has a quantity and the zones fished in, but nothing says it
was caught *there*, so it gets no species-by-zone entry. The Journal separates, for each species, what has a confirmed zone, what
was caught where the zone could not be read (map 0) and the rest ("earlier"), which is the difference between the species'
quantity and the placed quantity. A queued container from before schema 2 stays without a zone, and what it held is
recorded as before but never attributed to the zone it happens to be opened in. A damaged location entry is dropped on its
own at load; the rest is kept. An older TwichUI_Fishing reading a schema 2 file holds it untouched (the newer-schema rule).

**How the zone is attributed.** The zone is read once, when the fishing loot window opens (`IsFishingLoot()`, `Loot.lua`
`Begin`), and carried on that capture: every item of the window is attributed to it however late its slot is cleared or its loot
line confirms it, so a catch is where the line was, not where the player is when the item reaches the bags. A zone the game does
not give is map 0, never a guess. A container goes into the queue with that zone; its lot is saved, so a reload keeps it; opening
it (by the key, automatically or by hand, in any zone, in any later session) credits what it held to the zone it was caught in. A
lot has one zone: clams from another zone make another lot. Duplicate loot events are ignored (one window is one capture).

## Settings (Stage 1: `/tui fish help`)

| Command | Effect |
|---|---|
| `on`, `off` | Turns the whole module on or off |
| `start`, `stop` | Begins or ends a session |
| `restore`, `forget` | Puts the original gear back, or drops the snapshot without restoring |
| `pole <item\|none>`, `outfit <set\|none>`, `gear on\|off`, `combatweapons on\|off` | Equipment |
| `lure <item\|none>`, `lure auto\|alternative on\|off`, `lure early <s>` | Lures |
| `containers queue\|auto\|off`, `containers key on\|off` | Containers |
| `idle <min>` | Session idle timeout |
| `reel target\|mouseover` | What the reel override uses |
| `interact on\|off` | Lets TwichUI set the soft-target settings while a line is out, and put them back after. A value you changed meanwhile is kept |

Preferences live in `TwichUIFishingDB.config`, not in TwichUI profiles, sharing or backups. Since Stage 2 they are also on the
Fishing page of the TwichUI settings window ([below](#settings-the-twichui-settings-window-adventure--fishing)).

## Diagnostics

`/tui fish` prints the state, keys, next press, session counts, lure, gear, queue and the last 10 notes. Notes are a bounded
runtime list of codes such as `equip-failed`, `restore-failed`, `blocked`, `open-failed` and `left-in-loot`. TwichUI
Diagnostics has the scopes `fishing.load`, `fishing.decide`, `fishing.loot` and `fishing.bags`, and the gauges
`fishing.queue`, `fishing.sessions` and `fishing.listeners`. It also reports the addon's memory. The Test Lab category
`fishing` records the client facts above (`TwichUI_TestLab/cases/Fishing.lua`).

## Automated tests (`./tests/run.sh feature fishing`)

| File | Covers |
|---|---|
| `test_fishing_action.lua` | Loading rules, decision table, the full equip → lure → cast → reel cycle, recast guard, missed / interrupted / failed casts, duplicate starts, soft-target hold, combat (weapons-back macro, nothing set in lockdown), targeting settings, open key, off |
| `test_fishing_gear_lure.lua` | Lure choice, preference and alternative, application and learning, expiry during a line, early renewal, unknown enchants; snapshot and restore, full bags, interrupted swap, blocked restoration then key-press macro, missing items, the player's own changes, outfits, reload / disconnect / combat recovery |
| `test_fishing_loot.lua` | No catch from bags or other loot, multi-item catches, duplicate events, auto-loot with loot-line confirmation, left items, money, delayed loot after the line, duration, history, idle end, retention, zones, API copies |
| `test_fishing_containers.lua` | Queueing with provenance, key and open-key opening, contents attribution, several containers, learning, full bags, failed and locked opens, partial opens, hand-opened matching, unrelated containers, reconciliation, reload credit, provenance without double counting, automatic mode worked / blocked / off |
| `test_fishing_zones.lua` | Where fish were caught: one species in one and several zones, several species in one zone, sessions spanning zones, the zone read at the window (items taken after the player moved, loot confirmed later by the loot line), duplicate events, auto-loot, an unreadable zone (0), containers caught in one zone and opened elsewhere / later / after the session ended / after a reload, an older lot with no zone, schema 1 to 2 migration (nothing lost, nothing invented, repeatable), damaged location records, bounded growth |
| `test_fishing_location_limits.lua` | Approaching and exceeding the location bounds (species and containers), exact totals, overflow counted and shown by the Journal, sessions bounded too, reload, damaged overflow fields, a file already full before overflow was counted, migration from schema 1 then filling, very large quantities, and recording immediate with the Journal open (one redraw per burst) |
| `test_fishing_journal_zones.lua` | The Journal's place lists and the Collections to Locations navigation, old and new records together, multi-zone sessions, empty and interrupted sessions, the summary card, the window's remembered position (drag, reopen, reload, size, Reset, off-screen recovery), extension points, and a large history (measurements printed) |
| `test_fishing_store.lua` | New file, unversioned and damaged data repaired field by field, repeatable load, newer schema held, plain saved values, no prices |
| `test_fishing_present.lua` | Stage 2: Fishing Mode's lifecycle, presentations, camera, fading policy, combat, reload and logout recovery, errors, missing client functions, controller keys, Stage 1 underneath, preview |
| `test_fishing_hud.lua` | Stage 2: the cast bar, catch list and notifications, missing art and fonts, late item names, moving and scaling |
| `test_fishing_ellesmere.lua` | Stage 2: EllesmereUI (`tests/ellesmere_mock.lua`, modelled on its source): detection, bars, unit frames through their parent, portraits, minimap, its own writes, mouse-over, combat, frames made or rebuilt, contested frames, turning it off and on, repeated use, errors, absent |
| `test_fishing_settings.lua` | Stage 2: the settings page: found without loading, loading on visit, greyed states and their reasons, saved values, changes through Fishing's validation, keys and Key Bindings, preview, recovery, combat, missing addon, held data |
| `test_fishing_art.py` | Stage 2: the heads-up artwork's files, sizes, cut-out wells and rebuild |

The mock simulates secure actions the way `SecureTemplates.lua` reads attributes, and refuses attribute and override changes
in combat. It cannot prove taint, real event order or timing. Mutation checks (guard removed, double slot counting,
snapshot overwrite, acting in combat, partial open counted as opened, newer schema overwritten, player change overwritten,
unrelated container attributed, all loot taken as fishing, lure over an active one) were each caught by these tests.

## In-game verification

None of these has been done. Use a fishing-capable character with no other fishing addon, then repeat with Better Fishing
and EllesmereUI's fishing feature installed to check that they coexist.

- [ ] Bind the key in Key Bindings > TwichUI; `/reload`. The addon loads at login (`/tui fish` shows the key).
- [ ] With sword and shield: press 1 equips the pole (shield to bags), press 2 applies a lure, press 3 casts, a press after
      the bite reels and loots, an immediate extra press does nothing, and the next press casts. No double actions on release.
- [ ] Reeling finds the bobber with your interaction settings; then with `/tui fish interact on`. Check the values are put
      back after the line and after `/reload` mid-line.
- [ ] Early press: the line comes in empty (missed). Stand next to an NPC: the key never talks to it.
- [ ] Pull a mob with the pole on: the next press re-equips the weapons in combat; no "action blocked" error.
- [ ] `/tui fish stop`: your gear returns (addon-code restoration). If it is blocked, the key's macro does it.
- [ ] Change a weapon by hand while fishing; stop: your choice is kept.
- [ ] Full bags with a shield on: the key says so and does not swap.
- [ ] Catch clams: they queue, the next press opens one, `/tui fish` shows the contents credited, and a hand-opened clam is
      matched. A locked fishing chest is skipped.
- [ ] `/tui fish containers auto`: note whether the client allows it (`/tui fish` shows worked or blocked).
- [ ] Auto-loot on and off, and full bags during a catch: item counts match what reached the bags.
- [ ] `/reload` and log out mid-session, and disconnect for longer than the idle time: the session continues or ends at its
      last activity, and the gear snapshot survives.
- [ ] Run the Test Lab category Fishing and keep the facts (spell id, `hasLoot`, CVars) for the docs.

## Fishing Mode (Stage 2)

How fishing looks while you fish with TwichUI. **Nothing in it has been checked in the real client**: every claim is
unit-tested (`tests/test_fishing_present.lua`, `tests/test_fishing_hud.lua`, `tests/test_fishing_art.py`), reviewed in offline
captures ([docs/evidence/fishing-stage-2](evidence/fishing-stage-2/README.md), including a piece-by-piece comparison with the
approved mockup), or not tested.

### Presentations (`/tui fish mode immersive|compact|classic`)

| | Camera | Interface faded | Cast bar | Catch list | Notifications | Emblem |
|---|---|---|---|---|---|---|
| `immersive` (default) | yes | yes | yes | yes | yes | yes |
| `compact` | | | yes | | yes | |
| `classic` | | | | | | |

The emblem is the texture pack's "TwichUI Fishing" logo, at the top left as in the approved mockup (`/tui fish brand off`). It sits 26 units in and 60 down (`Present.lua`, `P.BRAND`), below the top status strip, at 0.36 of the art's size; the in-game check showed the first placement (22, -16) crowding the strip. The notification's lines are centred between the frame's gold borders (`Hud.lua` `ART.*.inner`, `Toast.lua` `T.Stack`), so "Caught!" no longer touches the top border, and the lines stay balanced with or without a value line.

A part's own switch (`camera on|off`, `fade on|off`, `list on|off`, `toasts on|off`) only ever takes that part away.
Classic is Stage 1 alone: the key fishes, nothing more is drawn.

### On, off, reveal

- **On:** by itself when a fishing line goes out (`present.auto`, default on; `/tui fish mode auto off`). Also when you
  ask: the "Fishing Mode: on or off" key (Key Bindings > TwichUI) or `/tui fish mode`.
- **Off:** at the session's end, when you ask, in combat (at once, before the lockdown), on death, on a loading screen and
  at logout. Once you turn it off, the next line does not bring it back for the rest of that session, unless you ask again.
- **Reveal:** hold the "Fishing Mode: reveal the interface (hold)" key, or type `/tui fish reveal`, to see the faded
  interface for a moment. It fades again when you let go.
- **Recover:** `/tui fish recover` puts the camera and the interface back whatever changed them since, and turns Fishing
  Mode off. Use it when another addon or a crash left something odd.

Both keys are new bindings in the core `Bindings.xml`. TwichUI binds nothing. A bound mode or reveal key also loads the
addon at login, as the fishing key does.

### Camera (`Camera.lua`)

- **What changes:** the camera's distance moves once, on the way in, to `camera.zoom` yards (default 7). It moves back
  once on the way out, with `CameraZoomIn`/`CameraZoomOut`, so it moves as smoothly as your own zooming. In between, your
  zooming and turning are never corrected.
- **Shoulder offset:** off by default. `camera offset <n>` sets the `test_cameraOverShoulder` setting if the client has
  it. The client may ask you once to confirm an experimental camera setting, and TwichUI never suppresses that question.
- **Never used:** view slots (`SetView`/`SaveView` would overwrite one of yours), pitch, and per-frame camera control.
- **Recording first:** the values are saved in `TwichUIFishingDB.client.camera` before anything changes. A reload, a
  disconnect or an error therefore still puts them back at the next start-up. At logout the offset is put back at once.
  The zoom's record is kept, and the next start-up finishes the move.
- **Your changes win:** a value is put back only if it is still Fishing Mode's: the zoom within 0.75 yards, the offset
  exactly. Your own change, or another addon's, is kept.
- **The client's limit:** the client's distance cap is read back after the move, so a far target still returns.
- **Missing functions:** a zoom that does not move is noted (`camera-no-effect`) and not tried again that session. Missing
  functions turn the camera off (`camera-unsupported`), and the rest of Fishing Mode works without it.
- **Held saved data:** while it is held, the record stays in memory only, because nothing is written.

### Fading (`Fade.lua`, `Ellesmere.lua`)

- **Groups:** `fade bars|units|minimap|panels|meters|twichui on|off`. Everything but panels is on.
  - Bars: the game's action, stance, pet and possess bars, the micro menu, the bags bar and the experience and reputation
    bars.
  - Units: the game's player, target, focus, pet and party frames.
  - Minimap: the minimap cluster and the pieces around the map (tracking, mail, battlefield, calendar, clock, zone text, the
    landing page button); with EllesmereUI, the frame it keeps the map in, which carries its border and buttons.
  - Meters: EllesmereUI's damage meters (`EllesmereUIDMFrame1`..`5`) and, if present, Details! (`DetailsBaseFrame1`..`4`),
    Recount and Skada windows. Names a missing addon doesn't have are skipped silently. (Unverified in the real client.)
  - TwichUI: the camping bar (its frame, through `R.Camping.Frame()`) and the sleeping bag bar. Only their alpha is
    changed, while Fishing Mode is on, and each returns to its own value; the camping bar's own fade is covered like any
    owner's write. Absent or switched off: nothing happens.
  - **The minimap is concealed, not just faded** (`Conceal.lua`, switch `fade.minimap`). The engine draws the map's blips
    (arrow, tracking dots, quest markers) regardless of frame alpha, which EllesmereUI's own source says too, and its own idle
    states use a real `Hide()` for that reason. So in Immersive Mode the `Minimap` frame is hidden with `Hide()`; everything
    parented to it (EllesmereUI parents its buttons and border pieces to the map) goes with it and leaves no clickable area.
    Moving the map off screen was rejected: it needs the anchors saved and put back while EllesmereUI re-anchors the map and
    owns its saved position, so it would drift or fight it. `Hide()` touches no anchor, no parent and no saved setting. If the
    map's owner calls `Show()` meanwhile, the map is hidden again at once (one post-hook on `Show`/`Hide`, inert when not
    concealed) and the owner's wish is remembered; coming back, the map is shown only if its owner wants it (a map hidden by an
    EllesmereUI visibility rule is never shown by Fishing). Holding the reveal key shows it; release hides it. Compact and
    Classic never touch it. In combat the map's `Show`/`Hide` are never called if the client protects it: the restoration waits
    for `PLAYER_REGEN_ENABLED` (so a protected map stays hidden through the first fight after Fishing Mode ends, unless
    EllesmereUI's own combat visibility driver shows it). Nothing is saved or polled; a reload makes a new, shown map.
    **Unverified in the real client** (the AzeriteUI changelog describing the off-screen technique could not be read from
    here); if `Hide()` fails to remove the blips on Forever, move to off-screen placement.
  - **Chat is never faded.** Chat frames, tabs, the dock, and any frame that holds a chat frame are refused by `Fade.lua`
    (even named with `fade add`), and the minimap and meter groups never reach them.
  - Panels: the quest tracker, buffs, debuffs and durability.
- **Hidden frames:** faded too, so a target frame that appears while you fish appears faded.
- **Your own frames:** `fade add <FrameName>` fades another addon's frame too, and `fade remove <FrameName>` stops it.
  `fade alpha` sets how far things fade (0 to 0.6, default 0).
- **Never faded:** UIParent, the world, errors, raid warnings, cast bars, loot, popups, the tooltip, Fishing's own pieces,
  and EllesmereUI's secure micro menu (EllesmereUI warns that changing its alpha breaks its secure buttons).
- **TwichUI's own notices** (cards, reminders, glows) are held quiet with the Quiet screen's hold (`fade notices on|off`).
  A hold is not your Quiet screen switch: it never turns that switch on or off, the data bar shows and toggles your own
  switch only, and nothing is saved.
- **Dialogue UI** fades UIParent itself while a conversation is open. Fishing Mode never touches UIParent, so the two never
  fight.

**Ownership: how Fishing Mode and other addons share a frame.** Fishing Mode owns what a faded frame *shows* while it is on.
The frame's owner (the game, EllesmereUI, another addon) keeps its *preference*.

- **One hook per frame:** each faded frame gets a post-hook on its own `SetAlpha` (`hooksecurefunc`, installed once, never
  removed, inert while Fishing Mode is off).
- **Covered at once:** when the owner writes an alpha, that value becomes its preference, and the faded alpha is put back
  in the same instant. Nothing flashes, nothing loops, and the owner's own records (EllesmereUI's `_fadeAlpha`) stay as it
  wrote them.
- **The pointer wins:** an owner's write while your pointer is on the frame is shown (a mouse-over bar reveals as usual).
  The frame fades again once the pointer has left.
- **Never fought:** a frame its owner writes more than 24 times in two seconds is left to it for the rest of the time.
- **Coming back:** each frame returns to its owner's *latest* preference. An owner that writes during that last fade has
  the last word. Put things back (`/tui fish recover`) returns every frame regardless.
- **Upkeep:** once a second while faded, and only then. It picks up frames made since, puts back the old frame of one
  rebuilt under the same name and fades the new one, and fades hovered frames again.
- **Only alpha:** nothing is hidden, shown, moved, re-parented or saved, no visibility driver is touched, and no function
  of another addon is called or replaced.
- **Fades:** 0.4 s, on one driver frame whose OnUpdate exists only while something moves (none with `/tui fish motion off`
  or reduced motion).

**EllesmereUI** (`fade ellesmere on|off`, on by default; it acts only when EllesmereUI is loaded). Read from EllesmereUI's
public source at 9.9.1, whose .toc lists interface 16001 and whose `EllesmereUI_ClientGate.lua` supports WoW: Forever. Nothing
of EllesmereUI is called, hooked, replaced or saved; only the frames below have their alpha changed, under the policy above.

| Group | EllesmereUI frames | Notes |
|---|---|---|
| bars | `EABBar_MainBar`, `EABBar_Bar2`..`Bar10`, `EABBar_StanceBar`, `EABBar_PetBar`, `EABPagingFrame`, `EllesmereEAB_XPBar` / `RepBar` / `FavorBar`, the bar caps `EllesmereEAB_MicroBar` / `BagBar` | EllesmereUI writes these bars' alpha itself (mouse-over, Advanced Fade, visibility passes); its writes are covered and kept as preferences. The micro menu and bags themselves are the game's `MicroMenuContainer` and `BagsBar` |
| units | `EllesmereUIUnitFrames_Hider`: the one parent of every unit frame EllesmereUI spawns, which EllesmereUI never writes; the 3D portrait models under it; `EllesmereUIRaidFrameContainer`; `EllesmereUIResourceBarsFrame` | Fading the parent fades every unit frame with no write EllesmereUI undoes; its pet-battle visibility driver stays its own. 3D models don't inherit a parent's alpha, so each is faded by itself (found by a bounded walk, every fifth upkeep pass) |
| minimap | `Minimap` (EllesmereUI takes it out of `MinimapCluster`, which it sets to 0): hidden completely with `Hide()`, see "The minimap is concealed" above; the frame EllesmereUI parents it to and the game's companion pieces are also faded | Blips ignore alpha, so alpha alone is not enough; unverified that `Hide()` removes them on Forever |
| meters | `EllesmereUIDMFrame1`..`5` (EllesmereUIDamageMeters) | Its own writes (alpha 1 when it shows a window) are covered like any bar's |
| panels | `EllesmereUIPlayerAuraBars_Buffs` / `_Debuffs` | Off by default, with the other panels |

Not faded: the extra action button and the encounter bar (gameplay), EllesmereUI's cast bars, and anything not listed: its
other modules' frames can be added by name. `/tui fish fade` lists, for this session, every frame found, faded, written by
its owner, left to its owner or skipped (and why), and how the interface came back last time.

### Cast bar (`CastBar.lua`)

- **Look:** the texture pack's walnut-and-bronze bar, 400 units wide at the bottom middle (`castbar.x/y/scale`;
  `/tui fish move`), with a warm gold fill in its trough.
- **States, from events only:**
  - `Ready to cast`.
  - `Casting…`, on `UNIT_SPELLCAST_SENT` with a Fishing spell.
  - `Fishing…`, with the seconds left. The fill and the seconds come from the channel's own start and end times
    (`UnitChannelInfo`). Without them, the seconds count up and no fill is drawn.
  - The results: `Caught!`, `Nothing on the line`, `Interrupted` and `Couldn't cast`.
- **No bite signal:** the timer times the line. The game gives no bite signal, and none is shown or guessed.
- **Under the bar:**
  - The session's length and catches, and the lure's time left, each after its glyph from the texture pack (the bobber, the
    fish mark, the feather), as in the mockup.
  - The estimated value, only from a connected valuation.
  - A warning when your own gear is still to go back on (and the key that does it), or when the saved data is held.
    Otherwise the prompts: your fishing key, the reveal key and how to leave, with gamepad buttons named when a gamepad is
    in use.

### Catch list (`CatchList.lua`)

- **Look:** on the right, drawn straight over the world, as in the approved mockup.
  - "Today's Catch" (or "This Session's Catch" for a session that began on an earlier day) and how long it has lasted.
  - The game's item icons in the texture pack's bronze icon frame, with the quantity on the icon's corner.
  - Ivory names, warm "N caught" lines and a large "×N".
  - The pack's fine bronze rule under the headings and, faintly, between the rows.
  - Under it, a faint feathered warm shade with no edge, so it reads over snow as well as at night.
- **Value area:** it keeps its place. With no valuation it says "Not available yet" (`list value hide` leaves it out).
- **Data:** from `API.Session()` and `API.Provenance("session")` only.
  - Catches: what the line brought up, with `N caught` and `xN`. Sorted by `list sort count|recent|name`. At most
    `list rows` rows (3 to 12, default 6), then `+N more kinds`.
  - Other treasures: what came out of fishing containers, then the containers themselves (`n unopened`). Provenance keeps
    them apart, so nothing counts twice.
  - Totals: catches, items, and the catch rate (catches per cast).
- **Highlights:** a row whose item was just caught glows. A new row fades in, with no slide when motion is reduced.
- **Names:** an item the game has not described yet shows `Item <id>` until `GET_ITEM_INFO_RECEIVED`.
- **Colors:** the game's quality color is used for rare and better items only.

### Notifications (`Toast.lua`)

- **Kinds, for each confirmed item (Stage 1's `ITEM`):**
  - `Caught!` with the item's own icon, name and quantity, and warm light behind the frame.
  - `Treasure!`, a warmer frame with a gold glint, for what came out of a fishing container and for items the game rates
    rare or better. Nothing else is called a treasure.
- **Art:** the pack's notification frame and band in three slices (frame, band and fading end). The band lengthens for a
  long name, so the frame and its end are never stretched.
- **Placement:** left of the middle, clear of the bobber and the cast bar (`toast.x/y/scale`).
- **Merging:** the same item again while its notice is up adds to it (`x3`). At most three show at once, and up to six
  wait.
- **Timing:** each shows for `toast.hold` seconds (default 3.5) with a short slide and fade. `toasts off` turns them off.
- **Value line:** shown only with a connected valuation, and asked when the catch arrives.

### Controller

- **Keys:** the fishing key, the mode key and the reveal key are ordinary bindings, and work with the client's own gamepad
  bindings (bind a pad button in Key Bindings). TwichUI never binds or changes a key, and never presses anything. Casting
  and reeling stay Stage 1's secure press, through `A.Decide`. Fishing Mode sets no secure attribute or override binding.
  A test checks that Stage 2's files call none of those functions.
- **Prompts:** buttons are named with the game's `GetBindingText` first, then as `A`, `B`, `X`, `Y`, `LB`, `RB`, `LT`,
  `RT`, `Start` and `Back`. `C_GamePad.IsEnabled`/`GetActiveDeviceID` decide which binding is shown.
- **Vibration:** none on a bite, because no bite signal exists. `/tui fish vibrate on` (default off) gives a short low
  pulse on a confirmed catch, if the client has `C_GamePad.SetVibration`. **Unverified.**

### Settings (the TwichUI settings window: Adventure > Fishing)

- **Finding it:** Fishing is in the page list under Adventure, featured on Home with the texture pack's leaping-fish
  icon, and found by search ("fishing", "lure", "ellesmereui", "fishing mode", "cast bar" and more).
- **Loading:** describing the page never loads TwichUI Fishing. Going to the page loads it, never in combat (it waits until
  combat ends). Until then every control is greyed out and says why: loading, combat, a missing or disabled folder, or
  records held by a newer TwichUI.
- **Five tabs:**
  - Fishing: the switch and status, your Fishing key and the Fishing Mode keys. Open Key Bindings opens the game's Key
    Bindings at TwichUI's header. Also Start / Leave Fishing Mode, your gear (pending restoration shows here), and Put
    things back, which recovers the camera and interface and puts your own gear back or says how.
  - Assistance: equipment, preferred pole and lure (from your bags), alternative lures, containers
    (queued / automatic where allowed / off), opening clams with the key, putting gear back, weapons in combat.
  - Fishing Mode: presentation, start on cast, camera distance and side offset (each with a note where this client doesn't
    offer it), fading, smooth transitions, key prompts, the gamepad pulse, the emblem.
  - Fading: the groups, TwichUI's notices, faded opacity, Include EllesmereUI (with the version and modules detected), what
    can be faded now, how the interface came back last time, and the frames you added (with Clear the list).
  - HUD: show each piece, its size, catches shown and their order, the value area, Place on screen, Reset positions, and
    Try Fishing Mode.
- **Saving:** every change goes through Fishing's own validation (`Present.Configure` → `Store.Set`), applies at once, and is
  saved in `TwichUIFishingDB.config`. Preferences stay outside TwichUI profiles and sharing, as in Stage 1. TwichUI never
  binds a key.
- **Preview** (Try Fishing Mode, `/tui fish preview`):
  - What it shows: the chosen presentation with sample figures, plainly marked as samples (the list says "Preview: sample
    catches, not your records"), for 15 seconds, with the interface faded and the camera moved.
  - What it never does: cast, equip, use, open or record anything.
  - How it ends: by itself (the settings page comes back), on Stop the preview, the Fishing Mode key, `/tui fish preview`,
    combat, death, a loading screen or logout. A real line during a preview takes over its faded interface and camera, so
    the camera never moves twice.
- **Commands:** `/tui fish help` lists the words.

### For Stages 3 and 4 (`R.Fishing.Present`)

- `P.SetValueProvider(fn)`: Stage 3's valuation.
  - For `fn("session")` it returns `{ text, items = { [itemID] = text } }`, and for `fn("item", itemID, q)` a text.
  - The session's answer is kept until the records change, and the item answer is asked when a catch arrives. Neither is
    ever asked from a timer or an animation.
  - A failing provider shows nothing and is noted.
- `P.Configure(path, value)`: `Store.Set`, applied live, for a Stage 4 settings page.
- `P.State()`, `P.Parts()`, `P.Enter/Leave/Toggle/Reveal/Recover`, `P.Subscribe(fn)`, and the `PRESENT` notification.

### Diagnostics

- **Scopes:** `fishing.castbar` (the cast bar's OnUpdate, after its throttle, only while a line is out), `fishing.list` (a
  catch list redraw) and `fishing.fade` (the fading upkeep, once a second while faded).
- **Gauge:** `fishing.toasts`.
- **Notes:** `present-error`, `camera-unsupported`, `camera-no-effect`, `camera-kept`, `fade-refused`, `fade-contested`,
  `art-missing` and `value-error`.
- **Status:** `/tui fish` adds Fishing Mode's state, what the camera supports and how many frames are faded. `/tui fish fade`
  reports EllesmereUI (version, modules) and each frame. The settings page's Fading tab says the same in a few lines.
- **Diagnostics export:** `API.Diagnostics()` carries `fade` (counts only) and `ellesmere` (detected, version, modules,
  counts).
- **Test Lab:** the case `fishing.client.presentation` reads the camera, gamepad, frame and EllesmereUI facts (version,
  modules, frames found, portrait models) in the client (read only).

### Performance

- **Idle:** with Fishing Mode off, nothing is built or shown, and no ticker, OnUpdate or extra event runs. The only extra
  work is Stage 2's notification listeners, which return at once.
- **Pieces:** built the first time they are shown and reused, rows, notices and animations included.
- **On:** the cast bar's OnUpdate runs only while a line is out (about 30 updates a second). There is a one-second ticker
  each for the cast bar's figures and the list's duration, and the fades' OnUpdate runs only while a fade moves.
- **Fading:** a known list of names, looked up once when Fishing Mode starts and once a second while faded (about 50
  lookups). There is no scan of the interface. EllesmereUI's portrait models are found by a walk of its unit frames'
  children, bounded at 400 frames, every fifth second. A post-hook costs one table lookup when the owner writes an alpha,
  and nothing at all while Fishing Mode is off.
- **Never:** prices asked per frame, or the whole interface scanned.

### In-game verification (Stage 2)

None of these has been done yet. In this order, on WoW: Forever:

1. [ ] Open TwichUI Settings (`/tui options`, or the data bar entry).
2. [ ] Find Fishing at once: Adventure in the page list, on Home, or by searching "fishing".
3. [ ] Configure without slash commands: its page loads Fishing (the status reads On). Try each tab and see each change
       apply.
4. [ ] Open Key Bindings from the Fishing tab: it should open at TwichUI. Bind "Fishing: the next step", and optionally
       the two Fishing Mode keys (a gamepad button works too). Back on the page, Your Fishing key shows it.
5. [ ] Choose Immersive under Fishing Mode.
6. [ ] HUD > Try Fishing Mode:
       - the cast bar, sample catches and a notice show for 15 seconds;
       - the interface fades and the camera moves;
       - nothing is cast or equipped;
       - everything comes back and the settings reopen.
7. [ ] Start fishing with your key: Fishing Mode comes on with the first line.
8. [ ] With EllesmereUI: its action bars, unit frames (with their 3D portraits), damage meter and minimap fade; the camping
       bar fades; chat stays fully visible; the emblem clears the top strip and "Caught!" clears the gold border. A mouse-over bar still
       shows under your pointer. Target something: its frame doesn't flash.
9. [ ] Hold the reveal key (or `/tui fish reveal`): the interface comes back, as EllesmereUI wants it, then fades on
       release.
10. [ ] `/tui fish stop`: every frame returns as EllesmereUI wants it (mouse-over bars hidden again, opacity settings
        intact), and the camera returns.
11. [ ] Pull a mob while fishing: everything is back at once, with no "action blocked". EllesmereUI's own combat fading
        still works.
12. [ ] `/reload` mid-session: your settings are kept, the camera comes back after the reload, and nothing is left
        faded. Then log out mid-session and log back in.

**Which EllesmereUI was detected:**

- The Fishing page's Fading tab: the EllesmereUI line gives its version and modules, and "Fishing Mode can fade" gives the
  frames found.
- `/tui fish fade`: one line per frame, and what happened to it.
- Test Lab, category Fishing: the facts `fishing.ellesmere.detected` / `.modules` / `.found` / `.models`.

**Also worth checking:**

- [ ] The catch list, notices and their art at UI scales 0.8, 1.0 and 1.25, over bright and dark scenery.
- [ ] The cast bar's fill matches the line's real time.
- [ ] Scroll the camera while fishing: it is never pulled back, and your distance is kept at the end.
- [ ] `camera offset`: whether the client asks to confirm an experimental setting.
- [ ] Whether `GetCameraZoom` exists in this client: the Fishing Mode tab says so if it doesn't, and the camera is then
      left alone.
- [ ] With Dialogue UI: talk to an NPC while fishing, and nothing is left faded or zoomed afterwards.
- [ ] Run the Test Lab case `fishing.client.presentation` and keep the facts.

## The Fishing Journal (Stage 3A)

A premium, non-economic look at what the fishing records hold: `/tui fish journal [overview|sessions|collections|locations|treasures]`,
or **Open Fishing Journal** on the Fishing page of the TwichUI settings window (Adventure > Fishing). It is a window in the pack's
walnut-and-bronze frames (journal, recessed and chestnut panels, rows and buttons, cut with `H.Slice`), the game's own item
icons and names, and the Spectral and Alegreya fonts. Nothing in it prices anything: it never loads Workshop, calls a pricing
API, or shows money, and a test greps its files for that.

| Page | Shows | From |
|---|---|---|
| Overview | fish caught, casts, time fishing, catch rate; the three favourite catches; the three newest sessions; what history is kept | `API.Totals`, `API.Session`, `API.Sessions` |
| Sessions | every kept session (the one in progress first, its length moving), newest first, named for the zone it fished most with "+N" when it spanned more; the detail: start to end and length, how it ended, a breakdown of the zones it fished with each one's catches, casts, catches, items (kept distinct from catches), catch rate, line time, missed lines, its catches by species, containers opened (their contents are said not to be catches), and where a session's records have no locations | `API.Sessions`, `API.SessionByID`, `API.Treasures(id)` |
| Collections | every kind of fish caught, with its icon, quantity, times caught, first and latest catch; sort by most caught, latest, first caught or name; 14 to a page. The chosen kind lists **where it was caught**: each confirmed zone with its quantity, catches, first and latest there (a scrolling list), then "Zone not readable" and "Earlier catches" (before locations were recorded) kept apart. A zone row opens that zone in Locations | `API.Totals().species`, `API.Zones` (containers excluded) |
| Locations | each zone: casts, catches, catch rate, time on the line (exact lifetime totals), kinds confirmed there, the kept sessions that fished there; the chosen zone lists its fish with quantities (a fish opens in Collections, pointing back at the zone), says how much of its items that breakdown covers, and lists recent sessions (each opens in Sessions). Zone 0 is "Unknown zone" | `API.Totals().zones`, `API.Zones`, `API.ZoneName` |
| Treasures | containers caught, opened, waiting and failed; what each is confirmed to have held; items found | `API.Treasures("lifetime")` (the queue and the per-container `got`) |

**Session summary.** When a session you stopped (`/tui fish stop`) or left idle ends with something caught, a **Session Summary**
card shows its place (or places: "first +N" and a list), length, catches, kinds of fish, catch rate, the fish by quantity with the
most caught marked, the treasures that came out of its containers, and **Open Fishing Journal**. It waits out combat, is off with
`/tui fish journal summary off` (or the settings switch), and is never shown for a session with no catch.

**How it is built.** `Journal.lua` answers each page as plain tables from `R.Fishing.API` only (no saved variable is read or
written by the Journal's files), cached until the records change; `JournalUI.lua` draws them with a fixed pool of rows per
list (the cost of a page does not grow with the history), wheel scrolling and paged grids. Each row and stat has an `extra`
list that is simply not drawn yet, `U.SUMMARY_COLUMNS` is the summary's column list, and `J.Overview().extra` adds stat cells,
so Stage 3B adds figures without moving a layout. New in the interface: `API.Treasures(scope)` (per-container counts and
contents), `API.SessionByID(id)` and `API.Retention()`.

**What the records cannot tell (shown honestly, never invented).**

- **Per-session records are kept for the newest `session.keep` sessions only** (default 100, 10 to 500). Older sessions exist
  only inside the lifetime totals; the Journal says how many ("N earlier sessions are only in the totals").
- **Catches from before schema 2 have no species-by-zone record.** Their zone totals (casts, catches, items, line time) are exact,
  and the species' lifetime quantities are exact, but nothing says which species came from which zone, so the Journal shows
  them as "Earlier catches" and never places them. Catches from schema 2 on are placed by the zone read at the loot window.
  A session from before schema 2 has no breakdown of its fish by zone and says so.
- **There is no catalogue of fish**, so no "N of M discovered": only what has been caught is listed, and one "?" tile ends the
  list as a reminder that more exist.
- **First and latest catch dates** come from the records' own `first` and `last` and are "not recorded" when absent.
- **Catch rate** is catches (fishing loot windows) over casts. **Time fishing** is the sessions' lengths including the one in
  progress; **time on the line** is the seconds a line was out. Neither is a per-hour or a value figure.
- **Containers opened before the Journal's records, or without their contents being seen, show counts only.** Contents are
  listed only when seen coming out of a container.
- Item names arrive from the game a moment after an item is first seen; until then a row says "Item <id>" and fills in by itself.

**The window's place.** Drag it by its title bar: where it is dropped is saved (`journal.x` / `journal.y`, the window centre's
offset from the screen's, in UIParent units, whatever its scale) and used the next time, after a reload too; `journal.scale`
(Fishing settings: Journal size, 60 to 140%) keeps its centre. The saved offset is only clamped for display: at least 140 units
across and the title bar (90 units) always stay on the screen, so a smaller screen or a larger window never loses the player's place
or leaves the window out of reach, and a bigger screen later restores it. **Reset Journal position** (Fishing settings) puts it
back in the middle. The window is not a protected frame: it opens and moves in combat. The summary card opens in the middle.

**Cost.** Nothing runs while no Journal window is open. A catch touches one aggregate (not a log): 0.4 to 0.5 ms with or without
a Journal open (the redraw is on a 0.3 s timer, once per burst of events, and never part of recording). Two changes keep the
window cheap over a large history: `API.Totals()` no longer copies the location tables (they have their own calls, so it is
unchanged for older callers), and the Journal asks the interface for digests (`SessionDigest`, `ZoneDigest`, `ItemZones`,
`ZoneSpecies`) instead of copying records: a kind's places are worked out only when it is chosen, and finished sessions are
digested again only when a session starts or ends or a container changes. The displayed results are identical. Measured with
`tests/bench_fishing_journal.lua` (500 sessions, 60 zones, 90 kinds, 3,600 species-in-zone entries; simulated client, Lua 5.1 on
this machine, so only the ratio carries over to the game):

| | before | after |
|---|---|---|
| Open the Journal (Overview) | 151 ms | 26 ms |
| Sessions / Locations / Treasures page, first time | 13 / 25 / 12 ms | 2 / 2 / 0 ms |
| All five pages again | 41 ms | 4 ms |
| Rebuild Locations + Collection after a catch | 88 ms | 2 ms |
| Locations / Overview redraw after a catch | 58 / 65 ms | 2 / 3 ms |
| Three navigations | 15 ms | 5 ms |
| Record a catch, Journal closed / open | 0.35 / 0.37 ms | 0.47 / 0.47 ms |
| The debounced redraw that follows a catch | 30 ms | 6 ms |

**When the location records are full.** Per record (the lifetime totals and each session) a species-in-a-zone entry is made for
each new pair until `LIMITS.zoneSpecies` (4000); a container-in-a-zone entry until `LIMITS.zoneContainers` (800). Beyond that
nothing is lost from the totals and nothing reads as complete: a species caught in a new pair has its quantity added to
`spo[itemID]` (one number per species, so growth is bounded by the number of kinds), and a container event with no entry adds 1 to
`ctl`. A pair that already has an entry keeps counting exactly. The Journal then shows, for a kind, *confirmed zones*, *zone not
readable*, **Beyond the storage limit** (the overflow) and *Earlier catches* (the remainder), which always add up to the kind's
quantity; Locations says a zone's missing breakdown is "past the storage limit" when the list is full. A file that was already
at the bound when it loaded, with no overflow count (written before overflow was counted), is flagged (`spx`): its unplaced fish
are shown as "before locations were recorded, or past the limit". `API.ZoneLimits()` reports `entries`, `max`, `full`,
`overflowTotal`, `unknownOverflow`, `containerEntries`, `containerMax` and `containersLost`. The new fields are optional and
normalised at load (a damaged one is dropped alone), so they need no schema bump.

**Artwork.** 15 new textures (`j-*`, `glyph-hook|clam|treasure`; `tools/make_fishing_art.py`) from the pack's `journal_frame`,
`recessed_frame`, `chestnut_frame`, rows, nav and compact buttons, close button, unknown tile and fish watermark. The window frame
is cut with a 54 px corner (its ornaments reach about 52 px; the pack's 24 px margin would smear them along the edges). The pack's
item art is illustrative and is not used: icons are the game's.

**Captures.** `python3 tools/render_fishing_journal.py` runs `tests/journal_capture.lua` (the real Journal over seeded records in
the simulated client) and draws `docs/evidence/fishing-stage-3a/journal-*.png` with the real textures and fonts. They are
screenshot-reviewed offline layout captures, not game screenshots: the world is painted, the icons are the pack's illustrative
stand-ins, and text metrics differ in the client.

**Tests.** `tests/test_fishing_journal.lua`: the model (overview, sessions, detail, collection, zones from kept sessions,
locations and rates, treasure provenance, the cache), navigation and selection, the Collections grid, sorting and paging, empty
states, 500 sessions of 40 species (bounded time, no new frames), records held by a newer version, missing dates and zones, the
summary (offered, off, no catch, waits for combat), and the boundaries (no Workshop, no price, no direct store access).

**Not in 3A:** any value, price or gold per hour (Stage 3B), charts, pool maps, a Journal key binding.

## Stage boundaries and notes for Stage 3

Not implemented in Stage 2:

- Workshop valuation and gold per hour (Stage 3).
- The Journal, the collection catalog, zone analytics, history charts and the fishing settings page (Stages 3 and 4).

Stage 3 connects its valuation with `Present.SetValueProvider` and must use `API.Provenance`, so a container and its
contents are never both valued. Stage 4 configures Fishing Mode through `Present.Configure`.

## Stage boundaries and notes for Stage 2 (written with Stage 1)


Not implemented: camera, fading, cast bar, HUD, Journal, valuations, gold per hour, collection, charts, pool maps. Stage 2
should respect the following:

- Read `R.Fishing.API` and subscribe to notifications. Never write `TwichUIFishingDB`, and never change secure attributes or
  overrides outside `Action.lua`.
- Keep one decision path (`A.Decide`). New immersive controls must press the same secure buttons, never cast or interact
  from addon code.
- Show a `pending` restoration and a `held` store clearly. Settings belong in the TwichUI settings window and call
  `Store.Set`. Moving preferences into profiles needs a migration.
- Workshop valuation (Stage 3) must use `API.Provenance` so that a container and its contents are never both valued.
