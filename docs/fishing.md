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

`TwichUIFishingDB` (account-wide; `schema = 1`; see `docs/persistence.md`):

- `config` holds preferences (the defaults are in `Store.lua` `S.DEFAULTS`; each leaf has a checker in `S.CHECK`).
- `client.saved` holds the targeting values to put back. `capability.autoOpen` records `"worked"` or `"blocked"`.
- `chars["Name - Realm"]` holds `nextSession`, `nextLot`, `session` (as for a summary, plus `recent`: the last 20 catches),
  `sessions[]` (at most `session.keep`, default 100, range 10 to 500), `totals`, `queue[]` (at most 200 lots),
  `gear = { state, snapshot = { at, kind, slots[slot] = { id, link, kept, missing, leave } } }`,
  `learned = { enchants[id] = lureItem, containers[id] = true }` (at most 200 each) and `zoneNames[mapID]`.
- A session summary or the totals hold `casts, catches, items, failed, interrupted, missed, line, seconds, first, last`, plus
  `species[id] = { q, c, f, l }`, `containers[id] = { caught, opened, failed, got[id] = q }`, `contents[id] = q` and
  `zones[mapID] = { casts, catches, items, line }`. A summary also has `id, start, last, stop, ended, zone, reason`.

Items are stored by id only, and no prices are stored. Lifetime totals are never trimmed; only summaries are. Migrations
(`S.MIGRATIONS`) are ordered and repeatable. An unversioned table becomes schema 1. A newer schema is held untouched:
nothing is recorded or changed for the session, and the key still casts.

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

Preferences live in `TwichUIFishingDB.config`, not in TwichUI profiles, sharing or backups. A settings page is Stage 2+.

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
| `test_fishing_store.lua` | New file, unversioned and damaged data repaired field by field, repeatable load, newer schema held, plain saved values, no prices |

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
captures ([docs/evidence/fishing-stage-2](evidence/fishing-stage-2/README.md)), or not tested.

### Presentations (`/tui fish mode immersive|compact|classic`)

| | Camera | Interface faded | Cast bar | Catch list | Notifications |
|---|---|---|---|---|---|
| `immersive` (default) | yes | yes | yes | yes | yes |
| `compact` | | | yes | | yes |
| `classic` | | | | | |

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

### Fading (`Fade.lua`)

- **Groups:** `fade bars|units|minimap|panels on|off`. Bars, units and the minimap are on, panels off.
  - Bars: the game's action, stance, pet and possess bars, the micro menu, the bags bar and the experience and reputation
    bars.
  - Units: the player, target, focus, pet and party frames, and EllesmereUI's unit frames by the names it gives them.
  - Minimap: the minimap cluster.
  - Panels: the quest tracker, buffs, debuffs and durability.
- **Your own frames:** `fade add <FrameName>` fades another addon's frame too, and `fade remove <FrameName>` stops it.
  `fade alpha` sets how far things fade (0 to 0.6, default 0).
- **Only alpha:** each frame's own alpha is read and then changed with `SetAlpha`. Nothing is hidden, moved, re-parented,
  hooked or saved, and nothing in another addon is called. A frame that is hidden, forbidden or missing is skipped.
- **Never faded:** UIParent, the world, errors, raid warnings, cast bars, loot, popups and the tooltip.
- **Coming back:** a frame returns to its own alpha only if it is still the alpha Fishing Mode set. Another addon's change
  is kept and counted (`/tui fish` shows it).
- **Fades:** 0.4 s, run on one driver frame whose OnUpdate exists only while something moves. There are none with
  `/tui fish motion off` or the Arrival reduced-motion setting.
- **TwichUI's own notices** (cards, reminders, glows) are held quiet with the Quiet screen's new hold (`fade notices on|off`).
  A hold is not your Quiet screen switch: it never turns that switch on or off, the data bar shows and toggles your own
  switch only, and nothing is saved.
- **EllesmereUI** replaces the game's bars and unit frames with its own. Its unit frames fade by name. Its bars do not,
  because their names are not known here: add them with `fade add`, or use EllesmereUI's own fading.
- **Dialogue UI** fades UIParent itself while a conversation is open. Fishing Mode never touches UIParent, so the two never
  fight, and Fishing Mode's pieces fade with UIParent then.

### Cast bar (`CastBar.lua`)

- **Look:** a compact walnut-and-bronze bar, 360 units wide at the bottom middle (`castbar.x/y/scale`; `/tui fish move`).
- **States, from events only:**
  - `Ready to cast`.
  - `Casting…`, on `UNIT_SPELLCAST_SENT` with a Fishing spell.
  - `Fishing…`, with the seconds left. The fill and the seconds come from the channel's own start and end times
    (`UnitChannelInfo`). Without them, the seconds count up and no fill is drawn.
  - The results: `Caught!`, `Nothing on the line`, `Interrupted` and `Couldn't cast`.
- **No bite signal:** the timer times the line. The game gives no bite signal, and none is shown or guessed.
- **Under the bar:**
  - The session's length and catches, and the lure's time left.
  - The estimated value, only from a connected valuation.
  - A warning when your own gear is still to go back on (and the key that does it), or when the saved data is held.
    Otherwise the prompts: your fishing key, the reveal key and how to leave, with gamepad buttons named when a gamepad is
    in use.

### Catch list (`CatchList.lua`)

- **Look:** on the right, drawn straight over the world: the game's item icons in a thin bronze rim, and ivory type with a
  soft shadow. Under it is a faint, feathered warm shade with no edge, so it reads over snow as well as at night.
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
  - `Caught!` with the item's own icon, name and quantity.
  - `Treasure!`, a warmer frame with a gold glint, for what came out of a fishing container and for items the game rates
    rare or better. Nothing else is called a treasure.
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

### Settings

- **Saved:** `TwichUIFishingDB.config`, the new groups `present`, `camera`, `fade`, `castbar`, `list` and `toast`
  (defaults in `Store.lua`; schema 1, missing values filled, no migration).
- **Changing them:** `/tui fish help` lists the words, and `/tui fish move` drags the pieces. A change applies at once.
- **Not yet:** a settings page is Stage 4's.

### For Stages 3 and 4 (`R.Fishing.Present`)

- `P.SetValueProvider(fn)`: Stage 3's valuation.
  - For `fn("session")` it returns `{ text, items = { [itemID] = text } }`, and for `fn("item", itemID, q)` a text.
  - The session's answer is kept until the records change, and the item answer is asked when a catch arrives. Neither is
    ever asked from a timer or an animation.
  - A failing provider shows nothing and is noted.
- `P.Configure(path, value)`: `Store.Set`, applied live, for a Stage 4 settings page.
- `P.State()`, `P.Parts()`, `P.Enter/Leave/Toggle/Reveal/Recover`, `P.Subscribe(fn)`, and the `PRESENT` notification.

### Diagnostics

- **Scopes:** `fishing.castbar` (the cast bar's OnUpdate, after its throttle, only while a line is out) and `fishing.list`
  (a catch list redraw).
- **Gauge:** `fishing.toasts`.
- **Notes:** `present-error`, `camera-unsupported`, `camera-no-effect`, `camera-kept`, `fade-refused`, `art-missing` and
  `value-error`.
- **Status:** `/tui fish` adds Fishing Mode's state, what the camera supports and how many frames are faded.
- **Test Lab:** the case `fishing.client.presentation` reads the camera, gamepad and frame facts in the client (read only).

### Performance

- **Idle:** with Fishing Mode off, nothing is built or shown, and no ticker, OnUpdate or extra event runs. The only extra
  work is Stage 2's notification listeners, which return at once.
- **Pieces:** built the first time they are shown and reused, rows, notices and animations included.
- **On:** the cast bar's OnUpdate runs only while a line is out (about 30 updates a second). There is a one-second ticker
  each for the cast bar's figures and the list's duration, and the fades' OnUpdate runs only while a fade moves.
- **Never:** prices asked per frame, or frames scanned. Faded frames are looked up by name once per Fishing Mode.

### In-game verification (Stage 2)

None of these has been done.

- [ ] Fish with the fishing key: Fishing Mode comes on at the first line. The camera eases in once, and bars, unit frames
      and the minimap fade. TwichUI's cards stay away, and the data bar still shows your Quiet screen switch as off.
- [ ] Scroll the camera while fishing: it is never pulled back. `/tui fish stop`: your distance is kept.
- [ ] `/tui fish stop` without touching the camera: it returns to where you had it, and every faded frame returns to its
      own alpha.
- [ ] `/reload` mid-session and log out mid-session: the camera is back after the reload and at the next login.
- [ ] `camera offset 1`: note whether the client asks to confirm an experimental setting, and whether it is put back.
- [ ] Pull a mob: everything is back at once, with no "action blocked". After combat the next line brings Fishing Mode back.
- [ ] Hold the reveal key: the interface returns, then fades again on release.
- [ ] Bind the fishing, mode and reveal keys to gamepad buttons: the prompts name them and all three work without a mouse.
      `vibrate on`: note whether a catch pulses.
- [ ] The cast bar's fill matches the line's real time. Check that the line's maximum is the channel's end time.
- [ ] The catch list, the notices and their art at UI scales 0.8, 1.0 and 1.25, over bright snow or water and at night.
      Check that the TGAs draw with clean alpha and no fringe, and that the toast wells show the item icon cleanly.
- [ ] With EllesmereUI: its unit frames fade, its bars do not (add them with `fade add`), and its own fading still works.
      With Dialogue UI: talk to an NPC while fishing, and nothing is left faded or zoomed afterwards.
- [ ] Run the Test Lab case `fishing.client.presentation` and keep the facts.

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
