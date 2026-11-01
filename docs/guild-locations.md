# Guild Locations

Guild members using TwichUI share their own current map position over the guild's hidden addon channel and (from M3) see one
another on the world map as class badges. **M0 to M3 exist: the policy wording, the core in `guildloc/`
(`State.lua`, `Roster.lua`, `Comm.lua`) with its tests, the settings page, the launcher's right-click menu and the map markers
(`Map.lua`).** No toolbar control or search exist yet (M4); the sections below that describe them are the plan, not the code.

## Current state (2026-11-01)

| | |
|---|---|
| M0 policy | **Done.** `CLAUDE.md`, `docs/dev-rules.md` and `.clinerules` carry the narrow exception (wording below). |
| M1 core | **Built, unit-tested** (`tests/test_guild_locations.lua`, 531 checks; mocked network, clock and map; the bundled AceComm and ChatThrottleLib are the real ones). **Not real-client-tested; not simulator-tested.** |
| M2 controls | **Built** (2026-11-01, uncommitted on `feature/guild-map`): settings page `guildLocations` and the launcher right-click menu. **Unit-tested** (`tests/test_guild_locations_settings.lua`, `tests/test_settings_broker.lua`, the contract fixture); the simulator's `smoke.sh` constructed the page (**construction only**; that run **preceded** the final icon change to `explore` and was not repeated). Final `./tests/run.sh` after the last M2 edit: **154 passed, 2 failed**, the same two pre-existing friend-chime files (no new failure). Not real-client-tested. See "What M2 built". |
| Behavior today | A character in a guild **sends its position by default** (state Sharing) and, from M3, draws guildmates' class badges on the world map. The player can change the state from the settings page or the launcher menu, both through `R.GuildLoc.SetState`. |
| M5 artwork | **Prepared and the settings illustration integrated** (2026-11-01, uncommitted): see "Artwork status". The class and eye assets are prepared but **not connected** to markers or a toolbar. Final `./tests/run.sh`: **154 passed, 2 failed** (`test_settings_contract.lua`, `test_settings_defaults.lua`), the documented baseline friend-chime failures; no new failure (`test_settings_window.lua`, with the icon checks, passes). Real-client communications checks and all visual checks (in-game appearance, actual-size readability) are **unverified**. |
| M3 markers | **Built** (2026-11-01, uncommitted on `feature/guild-map`): see "What M3 built". **Unit-tested** (`tests/test_guild_locations_map.lua`, 129 checks). Badge artwork **screenshot-reviewed** at 20, 26 and 32 px (a script-made contact sheet, not the game). **Not simulator-tested, not real-client-tested.** |
| Real-client checks | **User-confirmed in game (reported by the user, not re-run here):** GUILD delivery between two TwichUI clients and the sender name matching the roster (checklist items 1 and 2). **Not confirmed:** roster class and level return values, coordinates and placement, and how anything looks. |
| Pending | M4 toolbar/search, M6 remaining real-client checks. |
| M1 suite result | `./tests/run.sh` twice: **153 passed, 2 failed**, both times. The two failures (`test_settings_contract.lua`, `test_settings_defaults.lua`) are the friend-login chime default (`"TwichUI Friend"` where the tests expect `"TwichUI Notification"`) and reproduce on unchanged HEAD; they are not M1. The contract test also shows older border-texture drift (`"Steel & Bronze"` vs the fixture's `"Rounded Bronze"`) that the same two files already carried. Left unchanged. |

### What M3 built

- `guildloc/Map.lua` (TOC after `Comm.lua`): a map data provider and a pool of buttons on the world map canvas.
  - **Which:** `GL.Live()` (live, unexpired, ordered by `born` then key; never withdrawn records). Never the local player; never a
    guildmate in your party or raid (`GroupSet`, read at each layout and at each action; `GROUP_ROSTER_UPDATE` is listened for
    only while installed). Their record stays held and keeps updating. At most **150** drawn per viewed map, deterministic;
    undrawn records stay held. The "searched record is always drawn" exemption belongs to M4 and does not exist.
  - **Where:** same map, ancestor maps and the stitched map, through `NpcMap.Relevant` (now exported, one line in `npcs/Map.lua`) and
    `PinsMap.Position`. Unlike NPC plaques, guild badges are also drawn on continent and world views (the cap bounds them).
  - **Look:** `media/guildloc/class-<TOKEN>-small` for the nine classes; any other or unknown class token wears `R.ICON`. The
    class comes from the roster only. 20 units wide, growing to 26 at the closest zoom. Label (name) on hover, or always when the
    pins' label preference says so.
  - **Tooltip** (reads the record when shown, and again after a layout while hovered): name; "Level N Class", the part the roster
    knows, or "Class and level not known"; "Updated N s/min ago" from the receipt time; "Last known location. Their phase or
    layer may differ."; "Click for actions".
  - **Menu** (`PinsWindow.OpenMenu`): Set waypoint, Navigate to this spot (`Nav.StartAt`, source `"guild"`, disabled with Navigation's
    reason when off), Invite to party (`C_PartyInfo.InviteUnit`, greyed when `CanInvite` is false, the member is offline or already
    in the group). Each action asks again at the click: the record must still be held and unexpired and the roster must still
    list the member, and it uses the **current** position of that record (not the one when the menu opened). Otherwise it says
    "That guildmate's location is no longer shared." and does nothing. Alt/Shift/Ctrl clicks go to the map's handlers. Invite
    has no combat check of its own: it relies on `CanInvite` and the game (`InviteUnit` is called by Blizzard's own insecure
    code; not verified under combat in game).
  - **Lifecycle:** `Comm.lua` gained `GL.OnRecords` (told on any live change: store, withdrawal, expiry sweep, offline clear, wipe),
    `GL.Live`, `GL.Fresh`. Record changes ask for a layout through one timer, at most one pass per 0.5 s; a map change draws at
    once unless a pass ran in the last 0.5 s. While the map is hidden nothing is laid out (the change is remembered, the opening
    refreshes); closing releases every marker. Withdrawal, expiry (a layout also skips an expired record before the sweep), confirmed
    offline, guild change and leaving all reach the map through `OnRecords`. Off removes the provider, its timer and its event.
    Released markers lose key, texture, name, place and hover state and their tooltip is hidden; a marker stays bound to its record
    across layouts.
  - Diagnostics: scope `guildloc.map.layout`, gauges `guildloc.map.pool/.drawn/.layouts`, and the map's timer and event counted in
    the existing gauges (`docs/diagnostics.md`, `Gauges.lua`). Counts only.
  - Communications, privacy and protocol: unchanged.
- Test notes: the map, roster, clock and party are mocks; the core is real, fed through its receive path.

**M3 checks still to make in the game** are the checklist at the end of "Known limitations".

### Policy wording as applied (M0)

`CLAUDE.md` (Critical safety rules): "Never broadcast Chronicle feedback or Chronicle data. Never send the player's own live
position to other players, with one separately authorized exception: Guild Locations (`docs/guild-locations.md`) may default on
and send the local player's current map position over the GUILD addon channel only, never chat, with Sharing/Invisible/Off
controls, bounded expiry, no history and no relaying, and never with Chronicle data. Places the player chooses to share (party
pins, map pings, NPC lists) are separate features with their own rules and are not affected."

`docs/dev-rules.md` (Shared pins and location): "Live location is explicit opt-in with pause controls and expiry. No location
history by default. **The sole exception is Guild Locations ... on by default, the local player's own current position only, GUILD
addon channel only, Sharing/Invisible/Off controls, bounded expiry, no history, no relaying.** It never carries Chronicle data
(the Chronicle prohibition below is unchanged). Party pins and map pings share places the player chooses, not live position, and
keep their own rules." The Chronicle line in the same file is untouched.

`.clinerules` (Project): "Never send the player's own live position or Chronicle data to others. The only exception is Guild
Locations (`guildloc/`, `docs/guild-locations.md`), which has its own authorized design: do not change its default, privacy state
or protocol unless the task is about it. Party pins and map pings share places the player chooses and keep their own rules."

### What M1 built (files)

- `guildloc/State.lua`: the one authority. `GL.State / SetState / Toggle / Interval / SetInterval / OnChange`, epochs
  (`NextEpoch`), the owed-withdrawal flag (`Pending / SetPending`), `GL.NewTimer` (one timer per purpose, at most two engine
  timers each). Record `TwichUIDB.guildLoc = { state, interval, lastEpoch, wp }`.
- `guildloc/Roster.lua`: the guild roster index (one table read per lookup), coalesced rebuilds, one throttled refresh request.
- `guildloc/Comm.lua`: the protocol, receiver records, the send schedule, the transport gate, withdrawals, lifecycle,
  `GL.Snapshot`.
- `diag/GuildLoc.lua` plus scopes `guildloc.tick / .receive / .roster` and six gauges (`TwichUI_Diagnostics/Gauges.lua`,
  `docs/diagnostics.md`). The `.map.layout` and `.search` scopes come with M3/M4.
- Placement of the record: `setup/Restore.lua` `OWN_LEFT_OUT.guildLoc`, `setup/TwichConfig.lua` `TC.LOCAL.guildLoc = "network"`,
  `setup/Cleanup.lua` `TOP_PROTECTED.guildLoc` (deleting it would silently turn sharing back on). It is a top-level key, so
  profiles never contain it.
- `tests/harness.lua`: `REAL_COMM` (keeps the bundled AceComm) and a WoW-style `xpcall` that forwards arguments (ChatThrottleLib
  sends through it; stock Lua 5.1's does not).

### How the choice reads (State.lua)

- No record, or a record with no `state`: Sharing (the default; not written).
- A record that is not a table, or a `state` that is not `sharing`/`invisible`/`off`: **Invisible**, not rewritten. Only the
  player choosing a state replaces it.
- `TwichUIDB` held (newer schema): inactive for the session, reads as Off with reason `held`; nothing is written.
- An interval other than 10/15/30/60 reads as 15.
- `lastEpoch` present but unusable (not a whole number in 0..2^32-1): no epoch can be allocated, so **nothing is sent** until the
  player chooses a state again; it is never reused or wrapped. At 2^32-1 it fails the same way.
- Being outside a guild never prevents choosing or saving a state; the guild only decides whether anything can be sent.
- `Toggle` swaps Sharing and Invisible and does nothing from Off.

### Transport honesty

- The preflight (`Comm.lua Preflight`) is **best-effort congestion avoidance, not proof a position cannot be queued.** It reads
  ChatThrottleLib's `bQueueing`, `MSG_OVERHEAD` and `UpdateAvail()` and skips the tick when the library is queueing or
  `#text + framing + MSG_OVERHEAD >= UpdateAvail()` (the library's own test, plus AceComm's escape byte). The game can still
  throttle a send the library believed it had room for; the library then queues it and cannot cancel it. That case is detected
  (the callback had not run when the call returned), counted as `queued`, and holds the next position until released. It may
  still go out later.
- If AceComm, ChatThrottleLib, or any of `SendAddonMessage`, `UpdateAvail`, `MSG_OVERHEAD`, `bQueueing` (nil or boolean) is
  missing or not as expected, or `UpdateAvail` errors or returns a non-number: **no position is sent, never an ordinary queued
  one.** The troubleshooting report shows `transport: ctl-incompatible | no-acecomm | ctl-unreadable`. Receiving is unaffected.
- AceComm's callback is `(arg, bytes, total, accepted)`; `accepted` is the game taking the message, not any receiver.
- Withdrawals are ALERT priority and are not gated (they may queue, which is fine for a withdrawal).
- Healthy cadence only: with a valid position, scheduled timers and room in the throttle, the longest gap between positions is
  60 x 1.1 = 66 s. Loading, a late timer, a skipped send or a missing position make it longer; no count of tolerated misses is
  promised. Expiry stays 300 s (receiver clock).

### Withdrawals

- Leaving Sharing with a session running ends it, saves `wp = true`, takes a new epoch, and sends `w(E)`. Attempts at +0, +15 s,
  +45 s; the first one the **game accepts** ends it (acceptance is local, not receipt). After the last attempt and 15 s of grace
  the flag is cleared and the sender gives up (counted `wGaveUp`); receivers' 300 s expiry is then the only thing that removes
  the marker.
- After a reload with `wp` set, the same cycle runs with a fresh epoch even while Off; it starts no session, sends no position,
  records nothing and registers only the world-entry event, dropped once nothing is owed. No valid epoch: silent, counted.
- Choosing Sharing clears `wp` and makes every pending retry and old callback do nothing. A withdrawal the library already queued
  still goes out; receivers ignore it (its epoch is below the new session's).
- Leaving or changing guild ends the session without a withdrawal (the old guild is unreachable), clears `wp` and everything
  held, and a new session with a new epoch starts if Sharing.
- Receiver ordering lives only in the receiver's memory. After a record expires (300 s) or the receiver reloads, an old delayed
  message is first contact again and can show for up to 300 s. This is not permanent ordering and not remote erasure.
- Capacity: at 400 records (live plus tombstones) a new identity is refused (position or withdrawal); updates and withdrawals
  for held senders are still taken; unexpired tombstones and live records are never evicted; expired ones free room.
- Not covered: a logout without a withdrawal (receivers expire it in 300 s); a crash.

### What M2 built

- `TwichUI_Settings/pages/GuildLocations.lua` (TOC line after `WorldMap.lua`; top-level page, group `map`, order 77, `icon = "guildLocations"` (its own illustration since M5; it used the borrowed Home spyglass `explore` before). Two dropdowns and two status rows:
  - "Guild Locations": Sharing / Invisible (still see others) / Off. `TWICHUI_guildLocationsState`, **no default on purpose**, so
    "Reset this page" cannot restore Sharing (`tests/test_settings_defaults.lua` lists it in `NO_DEFAULT`). Reads `GL.State()`,
    writes only `GL.SetState`.
  - "Update interval while moving": 10 / 15 / 30 / 60 s, default 15, `GL.SetInterval`. The only thing a page reset changes.
  - Both are greyed with a reason while the saved data is held (or not loaded). Outside a guild both stay usable.
  - "Your choice" and "Status" rows: the saved choice, and whether anything can be sent now (Off, Invisible, Not in a guild,
    Sending, Waiting, Inactive). Counts and states only. The page subscribes once with `GL.OnChange` so a change made from
    the launcher menu redraws an open window.
- `SettingsBroker.lua`: right-click on the existing `TwichUI` launcher opens a `MenuUtil.CreateContextMenu` with a title, radios
  "Sharing my location" / "Invisible (still see others)" (`GL.SetState`) and "Guild Locations settings...". While **Off** there are
  no radios: a greyed "Off" line and "Turn on in settings..." (opens the page; never enables). While held: a greyed
  "Unavailable right now" and the settings entry. Without `MenuUtil`, right-click opens the page. The tooltip gains a third line,
  "Right-click for Guild Locations (<state>).", only when the core is loaded. Left-click is unchanged. No second Broker object.
- Combat: the launcher had no combat restriction (left-click calls `R:OpenSettings()` directly) and the menu's settings
  entry calls the same function, so it behaves the same. The earlier plan text "skipped in combat" was not implemented;
  say so if you want it added.
- Artwork: no prepared `guildLocations` settings icon exists in `media/icons` (the only related file in `assets/` is
  `guild-frame-source.png`, which is not this illustration), so nothing was processed. M5 adds the registry entry and the
  `tests/test_settings_window.lua` icon list.
- Tests changed deliberately: `tests/settings_mock.lua` now loads `guildloc/State.lua`, `Roster.lua`, `Comm.lua` (so the page
  exists in the contract); `tests/test_settings_defaults.lua` (page order, `NO_DEFAULT`); `tests/test_settings_broker.lua`
  (right-click and tooltip assertions, cases 7 to 9); new `tests/test_guild_locations_settings.lua`. The contract fixture was
  regenerated and then reduced to the Guild Locations lines only (pages, keys, settings, rows, changed, changedDB, defaulted,
  defaultedDB); the unrelated friend-chime and border-texture drift in the generated file was not kept.
- Not done by design: map markers, toolbar, search, protocol changes.

### Artwork status

All three supplied images were available (attached to the session, 8-bit RGBA with transparency) and were copied unchanged to
`assets/`. Nothing was generated, downloaded or substituted. Tool: `tools/make_guild_locations_art.py` (standard library; same
shape-based cleaning as the other art tools; `--check`, `--contact-sheet`). Output: `!!!TwichUI/media/guildloc/`, each at 64 px
and `-small` 32 px.

| Source (`assets/`) | Runtime files | Notes |
|---|---|---|
| `guild-locations-badges-source.png` (3 x 3) | `class-WARRIOR`, `-PALADIN`, `-HUNTER` (top), `-ROGUE`, `-PRIEST`, `-SHAMAN` (middle), `-MAGE`, `-WARLOCK`, `-DRUID` (bottom) | Assigned by grid cell of each part's centre, not discovery order. One shared canvas and scale (no per-badge balancing), so frames match. Map markers should use `-small`. |
| `guild-locations-eyes-source.png` | `eye-open` (Sharing), `eye-hidden` (Invisible) | Left and right half. Shared scale. For the M4 toolbar control. |
| `guild-locations-settings-source.png` | `settings` | Registered as Icons `guildLocations`; the Guild Locations page uses it. Replaces the borrowed `explore` spyglass. |

Final test outcome (2026-11-01): `./tests/run.sh` gave 154 passed, 2 failed: `test_settings_contract.lua` and
`test_settings_defaults.lua`, the same two as the M1/M2 baseline above. The error text of that final run was not kept (its
output was filtered to the FAIL lines); earlier runs of the same session printed the baseline cause for both:
`TWICHUI_friendLoginChime` expected `"TwichUI Notification"`, got `"TwichUI Friend"` (contract, `defaultedDB`), and an assert at
`test_settings_defaults.lua:158`. No failure mentions icons or Guild Locations. Still unverified: the real-client
communications checklist (M6) and every in-game visual check of this artwork.

To keep failure details next time without rerunning, save the whole output: `./tests/run.sh > <scratch>/suite.log 2>&1`
(`run.sh` itself prints each failing test's last five lines; it has no log convention of its own, so none was added).

Checked: contact sheet (64 and 32 px, and a further downscale) on dark and light surfaces showed full frames, pale details
(feather, helmet, blade) and clean edges with no matte. **Screenshot-reviewed, not real-client-tested.** Readability limit (from the contact sheet at 64, 32 and smaller sizes; not seen in game): at 32 px the badges separate by frame and colour (blue flame, orange leaf, red-brown ground); interior detail (totem bolt, crossed blades, bow) is small and below about 24 px is only suggested, so do not rely on it to tell classes apart. The open and hidden eyes differ mainly by the slash and the missing iris; at toolbar size they read as an eye against a crossed-out eye, no more.

### Real-client communications checklist (gate before M3)

Two accounts, A and B, in the same guild, both on this build, ideally the only TwichUI users online (the report holds counts, not
names, so a third sharing guildmate inflates the numbers; read changes, not totals). Stand still in the open world (not an
instance, not loading: `no-position` / `loading` skips mean no position). Read each client with `/tui diagnostics` (the
**Guild Locations** block; reopen it for each reading, do not use `clear`). Counters live in memory and **restart at 0 on every
reload**. "sent" means the game accepted the message, not that anyone received it.

Timing: a session's first send comes 5 to 20 s after it starts (login, reload, or choosing Sharing); then ticks every 15 s
(+/-10%) and, standing still, one position per 4 ticks, so the longest healthy gap is 66 s. Wait **30 s** for a first
position and **90 s** for any "next update" claim. A withdrawal goes out at once (retries at +15 s, +45 s); wait 10 s.

| # | Do | Expect on A (B for the mirror) |
|---|---|---|
| 0 | Both `/reload`. Open the report. | `state: sharing`, `transport: unchecked` until the first send, then `ok` (never `ctl-incompatible`, `no-acecomm`, `ctl-unreadable`), `roster` > 0 (open the guild panel once if 0), counters 0. |
| 1 | Both Sharing. Wait 90 s. | `session: yes`, `sent` >= 1, `refused 0`. On the other client `taken in` positions >= 1 and `held: 1 live`. `messages set aside` has no `not-in-roster`, `unknown-map`, `unreadable`, `channel`, `too-long`. **Passes steps "valid position accepted" and "sender name matches the roster"**: a record is only created after the roster lookup and the strict parse. |
| 2 | B chooses Invisible (settings or right-click). Wait 10 s, then 90 s. | B: `session: no`, withdrawals sent >= 1 and accepted by the game >= 1, `sent` stops rising. A: `taken in` withdrawals +1, `held: 0 live, 1 withdrawn`; A's positions-in stops rising over the 90 s. |
| 3 | A chooses Invisible. Then B chooses Sharing. Wait 90 s. | A: `session: no`, A's `sent` unchanged; **A still receives**: `held: 1 live`, positions-in rises, no `old-epoch` / `closed-epoch` / `old-number`. B: `sent` rises. **Passes "Invisible still receives" and "returning to Sharing gives a fresh accepted update"** (a new epoch above the closed one). |
| 4 | A chooses Off. Wait 90 s (B stays Sharing, so B's `sent` rises). | A: `state: off`, `held: 0 live, 0 withdrawn`, `roster` 0, `events` 0, positions-in **unchanged**. **Passes "Off stops recording".** |
| 5 | `/reload` A. Read before touching anything. | `state: off`, `session: no`, nothing held, owed withdrawal `no`. Then A chooses Invisible, `/reload` again: `state: invisible`, `session: no`; after 90 s `sent` is still 0 and `held` shows B's position (receiving after reload). **Passes "reload preserves Invisible/Off".** |
| 6 | A chooses Sharing. Wait 30 s, then 90 s. | A: `session: yes`, `sent` >= 1 within 30 s. B: positions-in +1, `held: 1 live`. Covers a new session after a reload (epoch above every earlier one). |

Failure reading: `not-in-roster` rising while `roster` > 0 and no record is the sender-name-form mismatch (check 2 of the
list below); `roster` 0 means the roster had not arrived yet, so open the guild panel and repeat. `blocked` / `outstanding` /
`refused` skips are transport; `no-position` / `loading` mean the sender could not read a position.

**Gaps in what the existing report can show (nothing added, by design: no names, places or payloads):**
1. A message discarded because the receiver is **Off** is not counted, so Off cannot be told apart from "never delivered"
   from the Off client alone. The other client's `sent` and step 6 (delivery works with the same pair) cover it.
2. The report cannot say **whose** record is held, or show the sender string next to the roster's form. A mismatch shows only
   as `not-in-roster`; finding out how the strings differ would need a local, temporary probe, which does not exist.
3. It cannot show the coordinates, so **a valid position** means it passed the strict parse and a known map, not that the point
   is right. That is for M3 (markers) to show.
4. A message from yourself echoed back is ignored without a count (expected; it just never appears).
5. Counters reset on reload, so reload persistence is read from the `state:` line, not from counts.

### Release gate

Do not ship a build containing M1/M2 before the real-client checks 1 and 2 below, because the default is Sharing. Do not begin
M3 before checks 1 to 4 show that delivery and the sender name form work. In-game checks for M2: the page opens and a choice
persists across a reload; the launcher right-click menu opens on a real data bar (and what the fallback does without one);
choosing Invisible from the menu updates an open settings window; Invisible and Off while not in a guild; the status row
reads "Sending" with a guildmate, and "Waiting" shows when expected.

## Requested behavior and approved defaults

- On by default, with an explicit opt-out. Three states through one authoritative API:
  - **Off:** nothing sent, nothing recorded, nothing drawn. A registered handler discards this feature's messages first thing.
  - **Sharing** (default): sends own position, shows received positions.
  - **Invisible:** sends nothing, still receives and shows others. It means hidden from this feature only, not from
    party pins, pings, the game's own group markers or other addons.
- Shares only: the player's own current map position, over the GUILD addon channel, to guild members running TwichUI.
  No relaying, no public chat, no persisted received records or history. Sharing continues with the map closed.
- **Account-wide state outside profiles, config sharing and backups.** One record `TwichUIDB.guildLoc = { state, interval, lastEpoch, wp }`.
  - A missing record means the default (Sharing). A present but unusable record reads as **Invisible** and is not rewritten.
  - A held `TwichUIDB` (`Persist.IsHeld("TwichUIDB")`, a newer-schema save set aside) means inactive for the session.
  - "Reset this page" must never change `state`. If the settings file is lost the default returns (known limitation).
  - Privacy is applied before the first outbound packet is scheduled.
- Explained in settings without a tutorial, notification or chat line. The state is controlled from settings, the
  TwichUI launcher's right-click menu and the map toolbar, all through `R.GuildLoc.State/SetState/Toggle`.
- Marker tooltip: name, localized class, level, "Updated N ago" (from local receipt time). Class and level come from the
  verified guild roster, not the packet; unknown stays unknown.
- Actions on a marker (a menu, nothing automatic): set waypoint, navigate (to a snapshot), invite to party. Each
  revalidates at click time.
- Search (map toolbar field) finds guildmates with live records. Choosing one shows the map and ring only.
- Duplicates: a guildmate in your party or raid gets no TwichUI marker (the game draws group members itself); the record
  stays searchable ("In your group"). Self is never recorded or drawn. TwichUI party pins are places, not players.

## Policy wording (authorized plan text; the applied wording is above)

`CLAUDE.md` line 54, replacing the sentence pair after "local.":
> Chat output is only a reply to the player's own command or click, and local. Never broadcast Chronicle feedback or location. The one separately authorized exception is Guild Locations (`docs/guild-locations.md`): the player's own current map position, to their guild's hidden addon channel only, never chat, with Sharing/Invisible/Off controls. It never includes Chronicle data. Never replace the global error handler.

`docs/dev-rules.md` line 91 (other sentences unchanged):
> Live location is explicit opt-in with pause controls and expiry. No location history by default. **The sole exception is Guild Locations (`docs/guild-locations.md`), separately authorized: on by default, own position only, GUILD addon channel only, Sharing/Invisible/Off controls, bounded expiry, no history, no relaying.** Do not infer shared layer or phase from matching coordinates. Keep labels, coordinates, identities and raw payloads out of routine diagnostics.

`.clinerules`, appended to the "Features are quiet and opt-in" sentence in Project:
> Never send a player's location or Chronicle data to others. The only exception is Guild Locations (`guildloc/`, `docs/guild-locations.md`), which has its own authorized design: do not change its default, privacy state or protocol unless the task is about it.

The Chronicle prohibition stays intact and is not narrowed to chat. Keep `.clinerules` consistent with `CLAUDE.md`.

## Milestones

| | Scope |
|---|---|
| **M0** | Done. |
| **M1** | Built (see above; key placement as listed there). Planned scope: `guildloc/State.lua`, `Roster.lua`, `Comm.lua`: account record, fail-closed behavior, epochs, transport gate, `wpending`, caps, timers, diagnostics scopes, key placement (Restore `OWN_LEFT_OUT`, TwichConfig `TC.LOCAL` as "network"), `tests/test_guild_locations.lua`, TOC entries after the `npcs\` block. Update this page with what was built and verified. |
| M2 | **Built** (see "What M2 built"). Settings page `guildLocations` (group `map`; the settings-contract fixture regenerated with a reviewed diff) and the TwichUI launcher right-click menu. |
| M3 | Map markers (own provider and pool), marker menu, group dedupe, fallback emblem `R.ICON`. |
| M4 | Map toolbar toggle (hidden while Off) and search integration. |
| M5 | Artwork: **prepared** (see "Artwork status"). |
| M6 | Real-client multi-account checks, then a readiness statement. |

## Protocol (version 1, plain text, no LibSerialize/LibDeflate, never deserialize Lua)

Prefix `TwichUIGuild` over `GUILD`.
- Position: `1:p:<E>:<n>:<map>:<x>:<y>`; withdraw: `1:w:<E>`. Under 64 bytes, strict anchored patterns.
- `x`, `y` are integers 0..10000 (zero is valid); `map` a known map of zone type or smaller; `E` in 1.6e9..2^32; `n` up to 2^20.
- No class or level in the packet (roster supplies them).
- **Epoch** `E = max(time(), lastEpoch + 1)`, taken at every Sharing session start and at every withdrawal. It only orders
  one sender's sessions; freshness is always local receipt time.

**Receive order, cheapest first:** feature not Off and not held; readable string text and sender; `dist == "GUILD"` and in a guild;
not self; length; **sender found in the roster index (O(1); unknown sender dropped, never shown, one throttled roster
request)**; per-sender bucket (burst 5, one per 4 s); strict parse and version; kind; field ranges.

**Receiver record** `{ e, n, closed, at, pos? }` keyed by normalized `SH.FullName(sender)`:
- `p(E,n)` dropped if a record exists and (`E < rec.e`, or `E == rec.e` and (`rec.closed` or `n <= rec.n`)); else it replaces the record.
- `w(E)` dropped if `E < rec.e`; else the record becomes a tombstone (position cleared), also with no prior record.
- **A withdrawal closes its own epoch and every lower epoch from that sender, including unseen ones; never a later session.**

**Sender transport** (plan text; M1 revised it, see "Transport honesty") (ChatThrottleLib v32, `libs/AceComm-3.0`, has no cancel API; the generation/`armed` guards stop our
own timers and callbacks only and do not retract anything handed to the library):
- Send a position only if it would go out immediately: read `CTL.bQueueing`, `CTL.MSG_OVERHEAD`, `CTL:UpdateAvail()` (type-checked);
  skip the tick if `bQueueing or #text + MSG_OVERHEAD >= UpdateAvail()`. A skipped send stays due.
- Otherwise `AceComm:SendCommMessage(prefix, text, "GUILD", nil, "NORMAL", cb)`. If the callback has not run when the call
  returns, the game throttled it and it was queued: count it. At most one position outstanding.
- Withdrawal is not gated, ALERT priority. (Revised in M1: if the library's fields are missing, positions are not sent at all and nothing falls back to an ordinary queued send; see "Transport honesty".)
- No raw `C_ChatInfo` send loop. Skip all sends while `SH.Blocked()` (chat messaging lockdown).
- `wpending` (a boolean in the account record) is set when moving to Invisible or Off and cleared when the game accepts the
  withdrawal. If a reload or lockdown prevented it, one `w` with a fresh epoch is sent after the next load: attempts at +0,
  +15 s, +45 s, then stop.

**Timelines** (epochs 100 session, 101 withdrawal, 102 resumed session):
1. Position queued, then Invisible: `w(101)` at ALERT. Receiver: `w` first gives a tombstone and the late `p(100,7)` is dropped; `p` first shows briefly and `w` removes it; `w` lost leaves it up to 300 s.
2. Withdrawal before any position: tombstone, no marker; a late `p(100,x)` is dropped.
3. Delayed position from an unseen older session after `w(101)` and `p(102,1)`: dropped. Residual: first contact being only a delayed old `p` cannot be distinguished and shows at most 300 s.
4. Resume then delayed prior traffic: a delayed `w(101)` after `p(102,1)` is dropped and does not kill the new session; a delayed `p(100,7)` is dropped.
5. Receiver reload: memory is empty, nothing persisted. A withdrawal sent during the reload is assumed lost (to verify). Sender reload: new epoch exceeds all earlier ones, `wpending` covers an unsent withdrawal.

**Enforced locally:** no position created after a state change; none handed to the transport unless immediately sendable; at
most one outstanding; stale callbacks do nothing; Off keeps no records; received data is memory-only; a lower epoch never
replaces a higher one. **Best-effort, not enforced:** a position already queued by the game's throttle may still go out; a
withdrawal can be lost; another addon may already hold the data; a receiver that missed everything can show a stale position
up to the expiry. Roster checks establish membership, not that a claimed position is true.

## Cadence

- Interval options 10, **15 (default)**, 30, 60 s; ±10% jitter per tick; first send 5 to 20 s after any start or resume.
- Movement sends at the tick. **Stationary heartbeat counted in ticks:** every K-th tick, K = 60 / interval (6, 4, 2, 1).
- **No automatic crowd-based interval change in v1.**
- Movement threshold: 20 yards, using `R.NpcSearch.Where()` / `.Distance()` ([npcs/Search.lua](../!!!TwichUI/npcs/Search.lua)),
  captured at each send; a map change counts as moved. Fallback when yards cannot be computed: same map and normalized
  Chebyshev delta below 0.005.
- Max gap between healthy packets is 60 x 1.1 = 66 s. Consecutive lost (or gated) packets give worst-case gaps of 198 s (2),
  264 s (3), 330 s (4). **Expiry is 300 s**: it tolerates 3 consecutive losses with 36 s margin; a fourth expires the marker
  until the next packet. (The first plan's 240 s with "3 lost" was wrong.) Tombstones are kept 300 s. No remote cadence field in v1.
- Location unavailable (loading, instance, secret value, lockdown, no guild): send nothing, never a heartbeat without a valid
  position. Receivers keep the last position only until its original expiry.
- Settings label "Update interval while moving": "How often your position is sent while you are moving. Standing still, it is
  sent about once a minute whatever you choose. Shorter keeps your marker fresher on guildmates' maps and sends a few more
  small guild-channel messages. It never changes by itself."
- Traffic (30 B payload, about 70 B as the throttle library counts it, 30% moving): about 0.6 msg/s received with 20 online
  participants, about 9.5 with 300; worst case 300 all moving at 10 s is about 30. Server fan-out is unmeasured.

## Resource policies

- **Record cap 400**, live plus tombstones. When full a verified newcomer frees expired entries; otherwise it is dropped and
  counted. (Revised in M1: tombstones are not evicted either; neither are live records.)
- **Drawn cap 150** per viewed map, ordered by `born` (monotonic counter set at record creation) then name key; the record
  chosen by search is always drawn. Markers are bound to records by key so a relayout moves markers instead of swapping them.
  Layout is coalesced to at most one pass per 0.5 s while the map is open, and does nothing while it is hidden.
- Search covers all live records, drawn or not; choosing one sets the "located" exemption (cleared by another pick, a clear,
  a map close or expiry).
- Buckets exist only for roster-verified senders; the sweep deletes buckets idle 60 s; never wipe all at the cap.
- **Timers by purpose, one `C_Timer.After` armed at a time each** (an `armed` flag plus a `nextDue` the callback re-reads; no
  per-player timer): send tick (Sharing only), withdrawal retry (max 3), expiry and bucket sweep (15 s, only while records
  or buckets exist), roster coalesce (1 s), map layout coalesce (0.5 s, map open). Search debounce is the existing one.
- Events (`GUILD_ROSTER_UPDATE`, `PLAYER_GUILD_UPDATE` with unit `player`, entering/leaving world) are registered only while
  the state is not Off. Off wipes records and buckets at once.
- Guild change or leaving the guild clears every record and starts a new epoch. Offline removal needs a roster snapshot newer
  than the record showing `online == false`; absence from the roster means unknown, never offline or left.
- Diagnostics: scopes `guildloc.tick`, `.receive`, `.roster`, `.map.layout`, `.search` and gauges (records, tombstones, pool,
  drawn, roster entries, pending timers, drop counters) in `DX.OPS` and `docs/diagnostics.md`; counts only, no names,
  places or payloads.

## Launcher menu (M2; built, with the differences listed under "What M2 built")

Right-click on the existing `TwichUI` launcher ([SettingsBroker.lua](../!!!TwichUI/SettingsBroker.lua)); left click still
opens settings. No separate data object. Use `MenuUtil.CreateContextMenu` (as `guides/CozyBagButton.lua` and
`healer/Watch.lua` do): title "Guild Locations"; radios "Sharing my location" and "Invisible (still see others)"; "Guild
Locations settings..." (`R:OpenSettings("guildLocations")`, skipped in combat). While Off, not in a guild or held, the radios
are greyed with a reason and the settings entry stays enabled; a menu click never starts broadcasting from Off. Without
`MenuUtil`, right-click opens the settings page. `SetTooltip` only if present. Update the file header and
`tests/test_settings_broker.lua` (it currently asserts right-click does nothing and the tooltip has one line).

## Current-code paths already investigated

| Area | Where |
|---|---|
| Closest template | `npcs/Map.lua` (`NMAP.Layout`, `Locate`, `Menu`), `npcs/Search.lua`, `npcs/SearchBar.lua` (`SB.Active`), `npcs/Prefs.lua` |
| Addon-message conventions | `pins/Sync.lua` (`OnMessage`), `pins/Ping.lua` (plain-text strict patterns), `npcs/Share.lua` (its guild receive only checks `IsInGuild()`: do not copy) |
| Identity and lockdown | `setup/Share.lua`: `SH.FullName`, `SH.SameName`, `SH.SelfName`, `SH.Blocked` |
| Map projection | `pins/Map.lua`: `PM.Position`, `PM.PlaceAt`, `PM.FrameLevel` |
| Menu and navigation | `pins/Window.lua` `OpenMenu`; `nav/Nav.lua` `NV.StartAt(map, x, y, name, source)` (`source` is a free label) |
| Own position | `nav/Nav.lua` `ReadPosition`, `npcs/Search.lua` `SR.Where`: `C_Map.GetBestMapForUnit("player")` then `GetPlayerMapPosition`, secret/finite guarded; never changes the visible map |
| Toolbar | `pins/MapTools.lua` (`LayoutBar`, `PaintButton`, `T.Refresh`; exists only with `partyPins` and the `toolbar` pref; the NPC filter button is the precedent; icons 32 px drawn at 18; the search width counts buttons) |
| Launcher | `SettingsBroker.lua`; `pins/Broker.lua` and `pins/BrokerMenu.lua` (pin menu, needs `partyPins`: not reused) |
| Saved data scope | `Profiles.lua` (`PF.ACCOUNT`), `Persist.lua` (`P.IsHeld`), `setup/Restore.lua` (`OWN_LEFT_OUT`), `setup/TwichConfig.lua` (`TC.LOCAL`); tests enforce key placement |
| Settings and art | `TwichUI_Settings/Kit.lua` (`K.Card`), `Cards.lua` (`ICON = 36`), `Icons.lua` (registry, `Icons.FALLBACK = R.ICON`), `tools/make_settings_icons.py`, `tools/make_npc_art.py` |
| Transport | `libs/AceComm-3.0/ChatThrottleLib.lua` v32 and `AceComm-3.0.lua` |
| Tests and simulator | `tests/harness.lua` (mocks `GUILD`, roster with name and online only, `Pump`), `tests/test_npcs.lua`, `tests/test_settings_contract.lua`, `tools/simlab/smoke.sh` |
| API evidence | `../wow-ui-source` (branch `forever`): `C_Map.GetPlayerMapPosition` (nilable), `SendAddonMessageResult` (includes `NotInGuild`, `AddOnMessageLockdown`), `GUILD_ROSTER_UPDATE`, `C_GuildInfo.GuildRoster`, `C_PartyInfo.InviteUnit/CanInvite`, `Blizzard_SharedMapDataProviders/GroupMembersDataProvider.lua` |

## Artwork (M5)

Three separate asset roles; do not merge them.

1. **Class badges** (map markers). One sheet, 3 x 3, assignments authoritative:
   - Top row: 1 Warrior, 2 Paladin, 3 Hunter.
   - Middle row: 4 Rogue, 5 Priest, 6 Shaman.
   - Bottom row: 7 Mage, 8 Warlock, 9 Druid.
   Key assets by class token (`WARRIOR`, `PALADIN`, `HUNTER`, `ROGUE`, `PRIEST`, `SHAMAN`, `MAGE`, `WARLOCK`, `DRUID`); unknown tokens use `R.ICON`.
   Measured: 1278 x 1231 RGBA, real transparency (corners alpha 0, 47.6% clear), nine solid parts of about 322 x 338 px, about
   5,000 haze pixels at alpha 1..63. Assign parts **by grid cell, not discovery order**. Keep the complete badges and pale
   artwork, one shared scale, no stretching, no tint. Markers 20 UI units growing to 26, so the 32 px file is near 1:1; the 64 px file
   ships only if the actual-size review wants larger markers.
2. **Toolbar eye pair** (sharing/invisible control): open eye with a small location motif, and the slashed eye. 1983 x 793
   RGBA, two solid parts (about 794 x 566 px), 69.8% clear; the slash tip extends above its cell, so bounds come from alpha.
   Standalone, no baked-in frame; 32 x 32 canvases, drawn wider than 18 (review at 18 and 22); the state is carried by shape and tooltip text.
3. **Settings illustration**: parchment map, three bronze markers, a plain chestnut-and-ivory pennant. 1312 x 1199 RGBA, one
   joined part (bbox 1102 x 1037). A new `guildLocations` entry in `Icons.lua` (64 px and 32 px), shown at 36 in the card;
   check it stays distinct from `mapToolbar` and `mapsNavigation`.

**Durable inputs: none yet.** The three images existed only in a session image cache (`.../images/9.png` class sheet,
`8.png` eye pair, `10.png` parchment map) and are not repository paths. `assets/` currently has no copies. Before M5 the user
must supply the three source PNGs, which are then copied into `assets/` (not packaged; `.pkgmeta` ignores it). Planned
tool: `tools/make_guild_class_art.py`, modelled on `make_npc_art.py` (reuses `make_settings_icons.py`'s shape-based haze
removal and TGA writer). M1 to M4 use the fallback emblem and do not wait for art.

## Known limitations and remaining checks

Safe behind guards (degrade rather than break; still confirm in game): `ChatThrottleLib` internals present or absent; roster
class and level return types (class unknown falls back to the emblem); nil position in instances; `InviteUnit` failure
(shows a notice); `MenuUtil` and `SetTooltip` presence; `GUILD_ROSTER_UPDATE` cadence; chat-lockdown results.

**Must be confirmed in the real client before claiming readiness:**
1. GUILD addon messages deliver between two TwichUI clients on Forever. **User-confirmed (2026-11-01).**
2. The `CHAT_MSG_ADDON` sender string matches the roster name form (otherwise every packet is dropped as unverified). **User-confirmed (2026-11-01).** Items 3 to 5 are not.
3. The roster class token at return 11, level at 4 (GUID at 17 is optional). These come from two reference addons, not from Blizzard's source or API docs.
4. Whether messages sent during a receiver's reload are lost (timeline 5 assumes yes).
5. Large-guild server fan-out, and how often the immediate-send gate skips right after zooming.

Limits that stay: withdrawal cannot erase what another addon already received; a lost settings file restores the default;
roster absence cannot prove a player left (no show-offline API on Forever); the position says nothing about shared phase or layer.

Tests planned for M1: each timeline (and with a receiver reset), epoch strictness across a same-second resume, the `wpending`
bound, the gate against the real bundled library with `C_ChatInfo` mocked, worst-case jitter gap at all four intervals, the
3-lost and 4-lost expiry boundary, the movement paths, cap admission order, timer ownership after rapid state toggling, and
key placement. The simulator can show page construction and load order only, never delivery or appearance.

### M3 in-game checklist

1. **Placement:** with a guildmate sharing nearby, a badge appears on the world map where they stand, on the zone map and on the continent map; it moves after they move (up to about a minute standing still).
2. **Class and level:** the badge matches their class; the tooltip shows "Level N Class", localized, and "Updated … ago"; a class without a badge shows the TwichUI emblem.
3. **Group deduplication:** after you invite them, their badge disappears and the game's own group marker is the only one; after they leave the group it returns.
4. **Withdrawal and removal:** they choose Invisible or Off and the badge goes within seconds; logging off removes it within about a minute (a roster refresh); a long silence expires it after 5 minutes.
5. **Waypoint:** the menu's Set waypoint places the game's waypoint at the spot, also after they have moved on the menu being open.
6. **Navigation:** Navigate to this spot starts a route to that fixed point (Navigation on); greyed with a reason when it is off.
7. **Invite:** Invite to party sends the game's invitation; it is greyed for an offline member or one in your group.
8. **Also:** the badges' size, position over the exact spot, readability at 20 to 26 units, hover label, layering against pins and NPC plaques, opening and closing the map repeatedly, and combat behaviour of the menu and invite.
