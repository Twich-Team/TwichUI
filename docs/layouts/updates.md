# Updating an installed layout while keeping the player's changes

The full description of updates, the baseline, finishing a setup and Undo this update. `architecture.md` §6 and §7 hold the
contract this follows; this file is consistent with it (RH-1, 2026-10-28). Built in Phase 7 and hardened in RH-1, offline-tested
only: nothing here has run on WoW: Forever.

What it is: when a layout is installed again (a new revision of the package, other choices, the other layout), TwichUI compares
three things for every setting it manages and keeps the player's own changes, unit by unit where it can read them and whole
where it can't. What it is not: a general merge of arbitrary addon profiles. EllesmereUI module blobs are never merged inside.

## Two lifecycles

| Record | Saved as | What it is for | Ends when |
|---|---|---|---|
| Install record (rollback journal) | `TwichUIDB.layouts.install` | Restore (back to before the first install), Undo this update (back to just before the last update), finishing an install or restore after the reload | Restored; or the setup is finished (Keep this setup) |
| Management record | `TwichUIDB.layouts.managed` | Which package, revision, layout and choices are installed; which profiles are the install's own; where the first install came from; the last settled check's result (`check`) | Restored; or Stop managing |
| Baseline | `TwichUIDB.layouts.baseline` | What the last checked install left, unit by unit: what updates compare against | Restored; or Stop managing |

- **Keep this setup** (`LY.Finish`) finishes the setup: the install record goes (Restore and Undo this update are no longer
  offered; the EllesmereUI copy an update kept is removed), the management record and the baseline stay. Reopening the wizard
  shows "Installed and managed"; setting up again is an update into profiles still recognised as the install's own.
- **Stop managing** (`LY.Detach`) forgets all three records; nothing installed changes. It is the only way, short of Restore, to
  end management. "Forget the record" (an unreadable install record) does the same. A readable record of another character's
  install can't be forgotten from this character (`TwichUIDB` is account-wide).
- The management record is written at every **settled** check after a reload (match or mismatch, every step run), from the
  record: package, revision, layout, picks, character, the install's own profiles (made by it, or already recorded as its own),
  the profiles in use before the first install, and that check's result. A finished setup whose last check didn't match is shown
  as "Installed and managed, not verified".

## The baseline

```
baseline = { v = 1, package, char, at, parts = { [adapter] = {
    revision, variant, picks, key, merge (contract version), schema, screen ("w,h,density"), at,
    units = { [unit] = { p, a, l, s, k, o, u } } } } }
```

| Field | Meaning |
|---|---|
| `p` | The layout's **recommended** value at that install (the package's side, normalized) |
| `a` | The value that install **left in place**, where it differs from `p` (a value of the player's that was kept) |
| `k` | That value is a **retained personal override** |
| `l` | What was **read back** after the check, where it differs from `a` / `p` (EllesmereUI's load-time defaults, pixel snapping) |
| `s` | How it was stored: `x` stored, `d` nothing stored (the addon's default), `a` not there |
| `o` | The player's **own**: "Stop managing this setting"; never written or compared |
| `u` | Checked only for **presence** after the reload (an opaque unit), not by value |

**Values, not checksums, for every unit compared unit by unit.** A setting is stored as its whole canonical text (`LY.Value`:
sorted keys, `%.17g` numbers, `false`, `0`, `""` and absent all distinct), a position as `@x,y[,w,h],POINT[_REL]`, the accent as
its signature. Only a value longer than 256 bytes of canonical text (none in the current packages) falls back to a
fingerprint. Opaque units (EllesmereUI module blobs, layout links, look tables) are stored as fingerprints, because they are
only ever compared with themselves.

**Commit timing** (one policy, `architecture.md` §6). Nothing goes in the baseline because an install started. A record is
committed only once it is **settled**: every step done, skipped or kept, and a check recorded after the reload (or at once, for an
install with no reload). Then each adapter's part is written only if that adapter's check matched; an adapter that didn't match,
or was kept as it is, keeps its previous part. A failed or `partial` update, or one with a step that never ran (`interrupted`),
commits nothing and stays unsettled (`partial`) whatever its check reads. `j.verify.baseline` lists the parts committed; the
wizard says when one wasn't.

**Versions.** A part made under another merge contract, another TwichUI settings schema, or (EllesmereUI) another EllesmereUI
version or migration stamps is not compared: its units read as "can't tell" (only ownership still stands). A baseline from a
newer TwichUI blocks the update and is never overwritten; a damaged one is ignored, not repaired.

## Comparison (`TwichUI_Layouts/Merge.lua`)

For each unit: baseline B, current C (what the player has now, in the install's own profile), new N (the package now, for
this screen, layout and choices).

| Case | When | Keep my customizations | Reapply recommended |
|---|---|---|---|
| same | neither changed | nothing | nothing |
| package | only the layout changed | apply | apply |
| mine | only the player changed | keep | apply |
| both-same | both changed to the same value (comparable units only) | nothing | nothing |
| conflict | both changed differently; or an opaque unit both changed | **keep** (default) | apply |
| added | newly managed by the package | apply | apply |
| unknown | no usable baseline, and C differs from N | keep | apply |
| removed | the package no longer names it | stop managing | stop managing |
| owned | the player made it theirs | never written | never written |

- **"Changed by the player"** is C against what the last install left (`l`, else `a`, else `p`). A **retained override**
  (`k`) stays the player's while C differs from what the layout recommended (`p`); for an opaque unit, until they choose
  otherwise. So install v1 → change → v2 keeps it → v3 doesn't touch it → v4 changes it: the value is the player's at every
  step and v4 asks again. It never becomes the layout's default. Setting it back to the layout's value ends the override.
- **Inherited and reset.** A setting that was never stored on either side is not the player's change even if its value moved
  (the addon's own default changed). One that was stored and is now not (reset to the addon's default) is the player's change,
  kept by not writing it.
- **Removed / stop managing.** A package that stops naming a setting releases it: the recipient keeps what they have. For an
  EllesmereUI sub-unit (a position, a text size, a field) that means writing their value into the new payload's blob, because
  importing the layout's blob would otherwise replace it (RH-1). On a layout switch, a sub-unit only the old layout named that the
  recipient didn't change was the old layout's, not theirs: it follows the new layout's blob.
- **Reset** (package format 4). A package can put a setting back to the addon's default only where the default is known: a
  TwichUI setting, or an EllesmereUI allowlisted field. The stored value is cleared, so it follows the **installed** addon's
  default (and a later default change, since it is never stored). It is compared by its effective value (`p` is the default's
  value, `s` is "d"), so: a recipient who didn't touch it gets the default; one who changed it keeps theirs (a conflict) unless
  they choose the layout's; one who already has the default value is left as they are. The check reads the setting back: a value
  stored again reads differently and is a mismatch. Positions, text sizes, blobs and the look can't be reset; Undo this update
  puts the earlier value back.
- **Parent and child.** Whatever the recipient keeps, owns or the package released goes into the payload as they have it,
  absence included; a value TwichUI can't read is carried as it is (an owned one stays owned). Omitting a write never preserves
  anything inside a blob the import replaces. EllesmereUI may fill its own defaults into an absent key as it loads: an absent value
  then reads as that default, which is the same effective value.
- **Deleted entity.** An EllesmereUI module the player deleted can't stay deleted (EllesmereUI would take another profile's):
  the layout's goes back, and the row says why.
- Generated profile names, EllesmereUI's load-time defaults, transient keys (`STRIP`, per-character data, `phantomBounds`) and
  serialization order are not changes: the normalization leaves them out or reads them back into `l`.

**Choices per row** (the review's details): Keep mine, Use recommended, Stop managing (make it mine for good), Manage again (for
an owned one). They are different on purpose: **Manage again** hands one owned setting back to the layout (from now on it is
compared and updated like any other; this update applies the layout's value if it differs); **Reapply recommended** is the whole
update's policy (every managed setting takes the layout's value) and never takes back a setting the player made theirs.

## What is merged unit by unit, and what only whole

| Adapter | Unit by unit (comparable) | Whole only (opaque, an explicit fallback) |
|---|---|---|
| TwichUI | Every managed setting; every TwichUI place | — |
| EllesmereUI | Registered positions (and sizes), the six density text sizes, the allowlisted fields (`minimap.coordsMode`, `coordsPosition`) wherever the payload's blob holds them (RH-1: before, a field inside the blob was neither in the blob's fingerprint nor tracked), the accent | Each module blob (minus its sub-units and private keys), the layout links (minus registered edge-link offsets), the fonts and dark-mode look |

A whole unit is kept by carrying the player's blob into the new payload, or replaced by the layout's. The review labels it:
"Replaced whole … TwichUI can't merge inside it", "Your version is carried into the new install whole", and for a conflict that
keeping theirs skips the layout's changes to it and using the layout's drops theirs in it. Carrying a blob needs the player's
profile and the package to be of the same vintage (identical `_migrations`); otherwise TwichUI can't carry it, and EllesmereUI
as a whole is **kept as it is** (default: this update doesn't touch it, and its baseline part stays, so it is offered again) or
**replaced with the layout's** after the player's profile is kept for Undo. A package whose EllesmereUI part is one base profile
string (the developer test package) is labelled as replaced whole.

## Geometry

- **Independent:** TwichUI places; EllesmereUI positions with no layout link, or linked to a screen edge.
- **Edge-linked kept positions** keep a valid anchor: the link entry is moved by the difference between where the links in the
  payload would put the frame and where it was decided (the same edge formulas as the screen layer, `ShiftLink`). When that
  can't be worked out (a point change on a frame of unknown size), the link is left and the review says EllesmereUI may place
  it from the link.
- **Atomic group `layout`:** the layout links and every registered position linked to another element (bar 2, bar 5, cast
  bars, boss frames, combat text, a tracked-buff group). Kept or replaced together; a mix (the player moved one, the layout
  changed another) defaults to the player's, all of them, or the layout's on request. Never one link field alone. "Stop
  managing" is not offered inside the group. A setting the player made theirs before it joined the group (a position the layout
  now links to another element) keeps the whole group theirs, whatever the policy or the group's choice: the review says so and
  "Use the layout's (all)" is off until they use Manage again on it.
- **Density and text:** the density choice changes N for components and text sizes; text sizes are comparable units.
- **Check after merging:** each kept, owned or released place is looked at on this screen: off the screen, or over another
  managed component. Warnings only; a placement is never moved to clear one.
- **The final plan** (`plan.final`, RH-1): the recommended geometry with the component frames the player keeps (the minimap,
  chat, the meter) at their own rect, the pieces they keep moved to their place, and a whole EllesmereUI kept as it is marked as
  theirs. The Review preview draws it and the fit check reads it (`wizard.md`, "Preview and fit").

## Switching layouts

| Kind | Rule |
|---|---|
| Shared personal choices (the setting has the same value in both layouts) | Kept (the package didn't change) |
| Layout-specific personal choices (the value comes from the layout's own layer and differs) | Return to the new layout's value; Keep mine offered (`how = "switch"`) |
| Conflicts in shared settings (the update itself changed a shared setting the player changed) | Kept |
| The `layout` group | The new layout's, unless the player keeps theirs |
| Owned settings | Stay the player's in every layout |

## Applying, undoing, resuming

- The plan (and its key) includes every decision; the review shows it before Apply; Apply refuses a plan that changed.
- **EllesmereUI backup:** an update that re-imports first renames the install's profile to `TwichUI Adventure (previous)`
  (public `RenameProfile`; nothing is copied, CDM spells, keybinds and sync groups move with it). An older copy is moved aside
  and removed only after the import worked; any failure renames everything back. Only a name the install recorded as its own
  (`record.euiBackup`) is reused; another profile of that name blocks the update.
- **TwichUI way back:** the stored values of the units the update writes, and the profile in use before.
- **Undo this update** (`LY.PlanUndo` / `LY.Undo`): TwichUI values back and the previous profile in use; EllesmereUI: the
  update's profile removed, the copy renamed back, the previous profile in use; a reload; then checked
  (`LY.VerifyUndo`: every normalized unit as it was before the update). Once it checks out, the install record, the management
  record and the baseline are the ones from before the update (for an update after a finished setup: no install record again).
  One level only.
- **Keep the update** (`LY.ForgetUpdate`) removes the copy and the way back; Restore is unchanged.
- **Restore** still goes back to before the first install, and removes the copy too.
- **Partial and resumed.** EllesmereUI done and TwichUI failed: `partial`, nothing committed, Undo and Restore offered. A client
  that stopped between the steps leaves `applying`, found at login as `interrupted`; a check of it reports but leaves it `partial`
  (a step never ran). Setting up again with the same package, revision, layout and choices resumes: the done step is not planned or
  applied again (no second import), the way back from before the first attempt stands, and units a stopped attempt already wrote
  read as "both changed the same way" (not written twice). Setting up with other choices from a `partial` record replaces the
  install's profile in place and keeps the way back from before the first attempt.
- **Stopped Undo or Restore.** A new update is refused while an Undo or a Restore stopped part way (`undo-unfinished`,
  `restore-unfinished`): finish it first. An Undo that stopped after the copy got its name back records that (`renamed`), and
  doing it again only switches the profile.
- **A second update before the first is kept** replaces the copy the first one kept (the profile from before it), so the first
  can no longer be undone; the review and the confirmation say so. Restore is unaffected.
- **Nothing to write** is still recorded when the revision, layout or choices change, or a setting is released or claimed.

## Verification

Verify reads only, never repairs. TwichUI settings and places, EllesmereUI fields (by their effective value: a missing key is
EllesmereUI's default), positions, text sizes and the accent are read back by value; a setting reset to the default is read back
as its default. Module blobs, the layout links and the look tables are checked only for being there (EllesmereUI rewrites them
as it loads): `verify.checked` and `verify.presence` are reported apart, the baseline marks those units `u`, and the result says
"N EllesmereUI parts … TwichUI checked only that they are there, not what is inside."

## The wizard

The Review step adds **Updating your layout** for an install again: a summary, three ways (**Update while keeping my
customizations**, the default; **Reapply the recommended configuration**; **Review conflicts**), the whole-addon and group
questions when they arise, screen warnings, and the details behind a button: each setting with its current and recommended
value, the case, the plain-language effect, the ownership consequence and its choices, five at a time. The confirmation names
the update; the Result step offers Undo this update and Keep the update; a finished setup shows "Installed and managed" with
Set up again and Stop managing.

## Tooltip placement and friendly plates in an update

The two personal choices of format 5 (`wizard.md`) are ordinary comparable units: `ellesmereui:tooltip.cursor` (read live from
`EllesmereUIDB.tooltipAnchorCursor`, an absent key reading as off), `ellesmereui:tooltip.fixedPos` (the install's profile's
`tooltipFixedPos`, "@x,y,CENTER", the same within a unit), and the two nameplate switches. The same cases and policies apply, with these
points:

- **The place travels with the profile, not the payload.** The new profile is built on the profile in use, which has its own
  `tooltipFixedPos`; the adapter writes the decided one after the import: the layout's when the decision is to apply it, otherwise
  the install's old profile's value (or nothing, when it held none). A place the player set in Unlock Mode is therefore kept like any
  of their changes.
- **The flag is account-wide.** It is written alone, only when it differs from what is there, and read back. The first snapshot keeps
  its value from before the first install; an update that newly manages it adds it once (`snapshot.account`, via the adapter's
  `Extend`). Undo this update puts it back as it was just before the update, and Restore as it was before the first install, **unless the
  player has changed it since** (the plan lists it as left, not written).
- **A choice added after a setup** starts from the game's own settings (`LY.LivePick`) and keeps the player's value until they pick for
  themselves (the wizard asks the update to "keep mine" for each setting of such a choice). A choice the player changes from what the install
  recorded takes the layout's value (each row still offers "keep mine"); one they leave as it was keeps their changes since.
- **Baselines**: the nameplate blob's fingerprint leaves the two fields out now, so an older baseline reads that blob as updated once
  (applied unless the player changed it, then the usual conflict rules); the new units have no entry in an older baseline and read as
  newly managed.

## Unsupported, by design or for now

- Merging inside an EllesmereUI module blob, or any third-party profile. Curated fields beyond the registered positions, text
  sizes, two minimap fields and the accent need EllesmereUI source evidence per field before they are added.
- Resetting a position, a text size, a blob or the look to EllesmereUI's default (no default TwichUI can name); a TwichUI place.
- Per-character EllesmereUI data inside the install's own profile (`DataBars.characters`, `QoL.chars`) is never carried into a
  payload, so an update re-import starts it again (EllesmereUI rebuilds it); whether anything visible is lost is an in-game check.
- Carrying a player's blob across EllesmereUI migration vintages.
- Remembering layout-specific personal choices per layout for a later switch back (Undo this update covers the last switch).
- More than one level of Undo.
- Detecting a player's change to keys EllesmereUI writes at runtime that TwichUI doesn't know about: they read as the player's
  change (kept by default). Which keys those are is an in-game check.

## Tests

`tests/test_layout_hardening.lua` (RH-1): an owned, kept or released child surviving the replacement of its parent blob and
EllesmereUI's load-time defaults (value and absence); a field change seen and kept; an owned unit in the layout group and an
unreadable one; reset versus stop managing end to end (v1 non-default, v2 resets, recipients unchanged / changed / already
default, a reset that didn't take, Undo), validation of reset, an older reader refusing format 4; the authoring decision; an
interrupted record never settling; blocked updates after a stopped Undo or Restore; a retried Undo; the management record's
check; Stop managing from another character; a colliding and a missing copy, a replaced copy disclosed; the final plan and its
fit; screen coverage; portable media; comparing packages. `tests/test_layout_tools.lua`: the capture tool's decisions and the
script's stops.

`tests/test_layout_update.lua` (12 sections): every case table-driven (false / 0 / "" / absent, inherited and reset,
removed, owned, added, unknown, opaque, positions within a unit, a deleted entity), the choices, the switch rules, groups, the
whole-addon decision, tracking and the screen check; end to end (publish v1 and v2 with the real `Pub.Build`/`Pub.Check`, install
v1, change a font, a TwichUI place, the minimap and the chat text size, update keeping them, verify, undo, restore); commit timing
and partial checks; a clean failure; a partial update resumed without a second import; switching layouts and a base update
reaching both; versions (EllesmereUI, merge contract, newer and damaged baselines); opaque units across vintages (kept, replaced,
undone); the atomic group; ownership, reset, removal, a deleted module, an off-screen place; the wizard (three ways, details,
choices, confirmation, undo, keep the update, no frames made by switching); **consecutive updates v1 → v2 → v3 → v4**;
**Finish → reload → reopen wizard → update → undo → stop managing**; presence versus value. Changed expectations in
`test_layouts.lua` and `test_layout_wizard.lua` are listed in `implementation-status.md`. Hand mutations (override branch removed,
Finish forgetting everything, committing without a match, presence counted as checked, values replaced by checksums, the wizard
applying without the update choices) each fail the new tests.

## Manual acceptance checklist (WoW: Forever; none of this has been run)

1. Install Classic, reload: the result says how many EllesmereUI parts were checked only for presence.
2. Change a TwichUI look, move the marker bar, move the minimap in EllesmereUI's Unlock Mode, change the chat text size. Install a
   newer revision: the review lists each as yours; Apply; reload; all four as you left them, the layout's other changes in.
3. In Unlock Mode after that update: the minimap's link still shows, nothing jumps when Unlock Mode opens or closes (the edge-link
   fix-up), and EllesmereUI's profile list shows `TwichUI Adventure (previous)`.
4. Undo this update, reload: `TwichUI Adventure` is the one from before the update, the copy is gone, TwichUI's values are back.
5. Move a frame linked to another (bar 5) and install a revision that changes the links: the review offers "Keep mine (all)" /
   "Use the layout's (all)"; each gives the layout links and the frame together.
6. Switch to Compact: shared changes stay, Classic-only ones go to Compact's, Compact's bars and links are in.
7. Keep this setup, reload, `/tui layout`: "Installed and managed"; Set up again → a newer revision is an update that keeps your
   changes and never says the profiles aren't the install's.
8. Leave EllesmereUI to load a newer version between installs: the review says its changes can't be told apart; kept as it is by
   default; Replace works and Undo brings yours back.
9. Combat: Apply, Undo, Keep the update and Keep this setup are refused.
10. Find which EllesmereUI blob keys change at runtime without the player (open and close windows, change specs, log in on
    another character), so they can be left out of the comparison.
11. Change the minimap coordinates in EllesmereUI, install a revision that changes the minimap module: your coordinates stay.
12. Stop managing the minimap's place, then install a revision that links the minimap to another element: the review says the
    group stays yours; Manage again, and the layout's links come in.
13. A revision that resets a TwichUI setting you never touched: after the reload it reads the default and the check says
    verified; one you changed stays yours.

14. Tooltip placement. Pick Layout position, apply, reload: tooltips appear at the damage meter's left, bottom level with it, on every
    character; in Unlock Mode the "Tooltip" mover is there. Pick Follow mouse on an update: tooltips follow the cursor on every character;
    your cursor offsets and growth direction are as you left them. With the tooltip reskin off in EllesmereUI, neither does anything and
    the review said so.
15. Move the tooltip in Unlock Mode, then install again with the same picks: your place stays. Undo this update, reload: the flag and
    your profile are as before the update. Restore, reload: the flag is as before your first install (turn it on by hand first: Restore
    leaves it).
16. Friendly player nameplates, in a group with another player: Class colors shows class-coloured names (this layout is name-only).
    Standard blue: EllesmereUI > Nameplates > General > "Show EUI Friendly Player Nameplates" reads off after the reload, and the
    friendly plates are Blizzard's. Check what they look like (they may still be name only or class coloured from what EllesmereUI last
    set, until changed in Esc > Options > Nameplates). Enemy plates, NPCs, party and raid frames and your custom colours are as they were.
