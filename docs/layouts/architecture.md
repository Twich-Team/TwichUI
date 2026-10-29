# Layout packages and installer: the contract

This is the one current contract for TwichUI's layout packages: two complete interface experiences, **Classic Adventure** and
**Compact Adventure**, built from shared configuration, installed and updated by a TwichUI wizard, and published by their author.
It was consolidated in the release-hardening pass **RH-1** (2026-10-28) from the Phase 1 contract and the revisions Phases 2 to 7
made to it; that history, and the phase records, are in `history.md` and are not the contract.

Where to find the rest:

| Document | What it is |
|---|---|
| `updates.md` | Updating an installed layout: the baseline, the three-way comparison, preservation, reset, switching, Undo |
| `wizard.md` | The setup wizard: steps, choices, preview, overlay, fit, result |
| `publishing.md` | Authoring, the envelope, the transport, receiving |
| `updating-the-bundled-layout.md` | Recapturing the package TwichUI ships (`tools/update_bundled_layout.sh`) |
| `presets.md` | The TwichUI helper presets: editing them in game, publishing them, bundling the published package (`--from-published`) |
| `adapter-capabilities.md` | Source evidence for each integration |
| `implementation-status.md` | What is built, tested offline, waiting for in-game checks, unsupported or deferred; open decisions; release blockers |

Status words used in every document: **offline-tested** (built, and the offline suite covers it), **in-game** (built, not yet
checked on WoW: Forever), **unsupported** (deliberately not done, with the reason), **deferred** (wanted, not built yet).
**Nothing in this project has been run on WoW: Forever**, so every behaviour below is at most offline-tested.

Words: **package** (the data for both layouts: layers, choices, geometry), **adapter** (TwichUI's code for one integration:
`twichui` or `ellesmereui`), **unit** (the smallest thing an adapter manages, records and compares), **install** (applying a
composed layout, reloading, checking it), **update** (installing again over an install TwichUI still manages).

## 1. Scope

| Adapter | Covers | Not covered |
|---|---|---|
| `twichui` | Every looks-and-behaviour field of TwichUI's shared-field-by-field groups that is profile-scoped and not in `TwichConfig.LOCAL`; the seven registered places (`PLACES`); a preset choice may set those fields (an older switch-on-only preset: feature switches **on** only; an editable preset, format 6: any of them, on or off, any valid value, or reset), never a place | List groups; anything that acts for the player, talks to other players or is a record; account-scoped settings; windows the player moves |
| `ellesmereui` | The suite's 18 module blobs, the layout links (`unlockLayout`), the look (`fonts`, `darkMode`, `euiAccent`, `_migrations`), through EllesmereUI's public partner-installer API; two allowlisted friendly-plate switches (`showFriendlyPlayers`, `classColorFriendly`) inside the nameplate blob; and, outside the import, the **tooltip placement** (the account-wide `tooltipAnchorCursor` flag and the install's profile's `tooltipFixedPos`, written by the adapter and read back) | UI scale, window skins and every other tooltip-skin setting (cursor offsets, growth direction, skin), spec and condition overrides, Cooldown Manager spells, click-cast, custom colours, other profiles, module enable states (all stripped from every payload) |

Unsupported in this release, each with its reason (`adapter-capabilities.md` has the evidence): Blizzard Edit Mode layouts (never
exercised; the objective tracker is placed by it, so it is illustrative only); chat windows and channels; game CVars and the UI
scale (EllesmereUI owns `UIParent:SetScale`; TwichUI never changes the scale, it only gives guidance); the tooltip skin as a whole
(its import resets a whole bundle of account-wide keys; only the placement is managed, narrowly, §4);
merging inside an EllesmereUI module blob; any third-party profile. EllesmereUI is required for the HUD; without it only TwichUI's
part can be planned.

## 2. Composition

```
shared base → layout variant → preset (and a picked preset) → picked choices → screen layer → the recipient's own (updates)
  (lowest)                                                                                                     (highest)
```

- **Per unit, the highest layer that names it decides it.** Below a unit nothing is merged: a module blob or a list is replaced
  whole. A unit inside another (an EllesmereUI field, position or text size inside its blob) is dropped when a higher layer
  replaces the whole blob it sits in, unless it names the unit itself. `LY.Compose` is pure and deterministic.
- **Three different things a layer can say about a unit, never confused:**

  | The layer | Means | Representation |
  |---|---|---|
  | names a value | manage it, with this value | the value in the fragment |
  | says inherit | take the layer below's; with nothing below, the unit is not managed | `LY.REMOVE` (in code only; never published) |
  | says reset (format 4) | manage it, as the installed addon's own default | the fragment's `reset` list of unit ids, normalized to `LY.DEFAULT` |
  | doesn't name it | not managed by this package | absence |

  Absence never means reset. On an update, a unit the package stops naming is *released*: the recipient keeps what they have
  (`updates.md`).
- **Presets** (`presets.md`): the picked TwichUI preset is above the base and the variant, so for a setting both name the
  preset's value wins; a setting the preset doesn't name keeps the layers' value (and "Leave them as they are" names nothing, so the
  layout's own looks still apply with it). The other choices are above the preset, but never name what it names (two choices may
  not write one unit: `choice-conflict`); a preset never names a place, so the screen layer never adapts a preset's value.
- **The screen layer is a function, not stored values**: it moves registered positions with their components for this screen and
  scales the registered text sizes by the density (§5). A value the recipient keeps is never adapted.
- **Unmanaged units are never written.** Everything outside §1 keeps the recipient's value.

## 3. The package

Plain Lua data, never executed from text (no `loadstring`/`load`). `LY.Validate` is the one validator for the bundled package,
a draft and a received one; `Pub.Strict` adds what a package that travels must also meet (`publishing.md`).

| Format | Adds | Read by |
|---|---|---|
| 1 | `id`, `revision`, `title`, `dev`, `made`, `requires`, `targets`, `layers` (base, variants, presets) | every version |
| 2 | `geometry`, `source`; settings as data (EllesmereUI `root`, table `modules`, `layout`; TwichUI `places`) | Phase 3 on |
| 3 | `choices`: presets (switches on only), enums (only their `sets`), density | Phase 4 on |
| 4 | a fragment's `reset` list (TwichUI settings, EllesmereUI allowlisted fields; base and variant layers only) | RH-1 on |
| 5 | an EllesmereUI choice fragment's `tooltip` (`cursor`, `fixed`; a wizard choice only) and boolean allowlisted fields | tooltip and friendly-plate choices on |
| 6 | editable TwichUI presets: a preset choice's `mode = "settings"` (its options set any managed TwichUI field to any valid value, `false`, `0` included, or reset it through their fragment's `reset` list; no place, no other adapter), `retired = { option ids }` (never reused), an option's `keep = true` (names nothing; at most one) | the presets editor on |

A package newer than the reader is refused as `format-newer` (an older TwichUI refuses a format 6 package rather than misread it).
The bundled package declares the lowest format its choices need (`Classic.lua` `ChoicesFormat`): 5 with the switch-on-only presets
it has now, 6 once editable presets are bundled. A switch-on-only preset is never reread as an editable one (it still can't turn
anything off); an omitted setting is never a reset in either kind.

Bounds: canonical text ≤ 8 MB, ≤ 50,000 values, depth ≤ 16, ≤ 256 units per adapter fragment (one preset option included), ≤ 8
variants, ≤ 6 choices of ≤ 8 options, ≤ 32 retired option ids; a composed layout per adapter ≤ `LY.MAX_EXPECT` - 16 units
(`MAX_EXPECT` = 3 × 256 + 64: base, variant and a preset, plus the screen layer's places; the install record and baseline hold as many). Stable ids: lower-kebab variant, choice and option ids; units `<adapter>:<path>` (`twichui:ui.markerBarPosition`,
`ellesmereui:addons.EllesmereUIMinimap`, `ellesmereui:pos.minimap`, `ellesmereui:addons.EllesmereUIMinimap.minimap.coordsMode`).
The install's own profiles are one pair for both layouts: EllesmereUI and TwichUI `TwichUI Adventure` (D26).

The bundled package is `dev = true` until it has been checked on WoW: Forever (D20); a developer package may be tried on another
client (the plan says so). The developer flag is not a production compatibility path: a published or received package may not
carry it.

## 4. Adapters

Two adapters, plain tables in a registry (`LY.RegisterAdapter`); not a general framework. What each supplies, as built:
`Detect`, `TargetName`, `Normalize(fragment, ctx) -> units, parents`, `Capture` (the snapshot), `CleanSnapshot`, `Plan(composed,
ctx)` (read only, with its own key), `Apply(part)`, `Expect`, `Verify(expect, snapshot)`, `PlanRestore`, `Restore`, `VerifyRestore`,
the update functions `Normal`/`Schema`/`Baseline`, `PlanUndo`/`Undo`/`VerifyUndo`, and `Label`/`Show`. Only `Apply`, `Restore` and
`Undo` change game state; each refuses in combat itself.

- **TwichUI** reuses TwichConfig's schema, value checks and containers, and `Profiles` for every profile operation
  (`Duplicate`, `Switch`, `Delete`, `Refresh("layout")`). An install writes into its own per-character profile, a copy of the one
  in use. A reset clears the stored value (the feature then reads its default).
- **EllesmereUI** calls only public functions: `DecodeImportString`, `EncodePayload`, `ImportProfileSilent` (`cleanSlate`,
  `applyUIScale = false`, `autoAssignSpecs = false`; it never reloads), `GetProfileList`, `GetActiveProfileName`, `GetProfilesDB`
  (read), `SwitchProfile`, `DeleteProfile`, `RenameProfile` (updates only), `RegisterExternalInstaller`, and `ExportProfile` for a
  developer base. EllesmereUI's `_firstInstallPending` blocks a plan unless TwichUI is the registered installer
  (`A.HeldForUs`: then it is the handshake the install's import answers). The core's first-install offer
  (`docs/onboarding.md`) also calls the exported `ShowFirstInstallPopup` to hand EllesmereUI's first run back. It never writes `EllesmereUIDB` directly. Its active profile is **account-wide**: an install changes every
  character's HUD unless a spec is assigned to another profile (`spec_locked`, reported).
- **Inside an EllesmereUI blob**, only these are units of their own (comparable, carried, verified by value): the registered
  positions and sizes (`POSITIONS`, 40), the six density text sizes (`TEXT`), the allowlisted fields (`FIELDS`:
  `minimap.coordsMode`, `minimap.coordsPosition`, `nameplates.showFriendlyPlayers`, `nameplates.classColorFriendly`; a word or a boolean) wherever the payload holds them, and the accent. Everything else in a blob is
  opaque. Adding a field needs EllesmereUI source evidence for its path, values and default.
- **Outside the import**, two units of EllesmereUI's tooltip placement (a wizard choice's `tooltip` fragment only; `A.CURSOR_UNIT`,
  `A.FIXED_UNIT`), because no import can carry them without resetting a bundle: `ellesmereui:tooltip.cursor` is the **account-wide**
  `EllesmereUIDB.tooltipAnchorCursor` (written alone, as EllesmereUI's own option does, then read back), and
  `ellesmereui:tooltip.fixedPos` is the install's own profile's `tooltipFixedPos`, written after the import (the import copies the
  active profile's, never the payload's) and read back. Nothing else of the tooltip skin is read or written. Compared by value like any
  comparable unit; an update carries the player's own place into the new profile unless the decision is to apply the layout's. The flag
  is snapshotted before the first change that touches it (`snapshot.account`, extended by an update that newly manages it), recorded for
  Undo (`update.ellesmereui.account`), and put back by Undo and Restore **unless the player has changed it since** (then it is left, and
  the plan says so). A write that cannot be read back fails the step and puts the profiles back.

## 5. The screen layer and fit

Coordinates are UIParent units, centre offsets unless a registry says otherwise. A package's `geometry` names a canvas (the
author's UIParent size), components (boxes measured on the canvas, each anchored to a point of the area, the screen or another
component), densities, a narrow width, and attach maps (each registered position or place moves with a point of a component).
`Geometry.Resolve` places the components for this screen with two rules (room, above), clamps, and never shrinks below a
component's readable minimum. Screen-edge layout links are rewritten so EllesmereUI's own anchor pass puts each element where the
plan says; links to another element move with their target. Details: `wizard.md`, `adapter-capabilities.md`.

What a fit claim means (RH-1):

- **The components fit** (`geo.fits`): no managed component overlaps another or leaves the screen. A component the layout never
  applies (the objective tracker, `applied = "edit-mode"`) is **illustrative**: drawn, never counted.
- **The pieces are clear** (`LY.Fit(...).clear`): the pieces inside the components (unit frames, bars, cast bars, party frames,
  TwichUI's markers), with sample sizes from the layout's data, don't leave the screen or reach over a frame component (chat, the
  meter, the minimap), a piece of another block, or (a marker) a piece of another component. What the same check finds on the
  author's own canvas is the author's arrangement and is not reported. Pieces of one component over each other are not checked.
  Sample sizes: "may overlap", never a measurement.
- **For an update, the claim is about the final plan**, not the recommended placement: component frames the recipient keeps (the
  minimap, chat, the meter) take their own rect; positions and places they keep, own or that the package released are checked
  where they are; EllesmereUI kept as it is keeps all its own (`plan.final`). A kept placement is never moved to clear a warning.
- **Not placed by the screen layer, and said so**: positions stored in a form not read (the battle resurrection timer's
  `centerX/centerY`, Bags' `TOPLEFT`), positions with no attachment, and pieces with no size in the data. They are never part of a
  fit claim.
- **Scale guidance**: when the components don't fit, the wizard works out (with the same resolver, on screens of the same shape)
  the UI scale at which they would, and says it if it is at least 0.64; below that it suggests another layout or size. TwichUI
  never changes the UI scale.

## 6. Lifecycle and transaction policy

Three saved records in `TwichUIDB.layouts` (account-wide; each names the character that installed):

| Record | Holds | Lives until |
|---|---|---|
| `install` (the rollback journal) | state, steps, the first install's snapshot, what the check expects, what the baseline will take, and for an update the way back (`update`) | a Restore checks out; Keep this setup (`LY.Finish`); Stop managing |
| `managed` | package, revision, layout, picks, the install's own profiles, the first install's home profiles, the last recorded check's result | a Restore checks out; Stop managing |
| `baseline` | per adapter part, per unit: recommended, left, read back, stored, kept, owned, presence-only (`updates.md`) | a Restore checks out; Stop managing |

The policy, in one place:

1. **Nothing changes without the key of a plan the player was shown**, out of combat, after one confirmation that names the reload,
   the account-wide EllesmereUI change, and any loss of a way back (a second update replaces the copy kept by the first).
2. **The snapshot is complete and checked before the record is written; the record is written before the first change.**
   Installing again keeps the first snapshot: Restore always goes back to before the first install.
3. **Steps run EllesmereUI first, then TwichUI, and stop at the first failure.** Across addons this is not atomic. A failure that
   changed nothing leaves the previous record exactly as it was (or none). Otherwise the record is `partial`, with each step's
   state; nothing is undone behind the player's back; Undo this update and Restore are offered.
4. **A record is settled (`verified` or `mismatch`) only by a recorded check after every step ran.** A step still pending, failed
   or not run (a client that stopped mid-way leaves `applying`, found at login as `interrupted`) keeps the record `partial`: the
   check reports, but commits no baseline and doesn't move the management record. An unsettled update never appears installed.
5. **The baseline is committed per adapter, only from a settled record, only for an adapter whose check matched.** A mismatched
   adapter keeps its last good part. Nothing is committed because an install started.
6. **The management record is written at every settled check**, with that check's result; a finished setup whose last check
   didn't match is shown as "not verified", never as plainly installed.
7. **Resume**: setting up again with the same package, revision, layout and choices after a `partial` update plans the done steps
   as done; they are not applied again (no second import), and the way back from before the first attempt stands.
8. **Undo this update** (one level) puts back the record, management record and baseline from before the update once its check
   matches; until then the record says `undoing`/`undo-partial`. An Undo that stopped after the copy got its name back resumes
   from there (`renamed`). A Restore or Undo that stopped part way blocks a new update until it is finished.
9. **Finish (Keep this setup)** ends the journal only (and removes the update's copy, after a confirmation that says Restore and
   Undo end); management goes on. **Stop managing** forgets all three records and changes nothing installed; a readable record
   of another character's install can't be forgotten from this character.
10. **Restore** goes back to before the first install, removes the install's own profiles and the update's copy, after a reload,
    and is checked; a stopped restore is `restore-partial` and can be run again.

**What persistence can and can't promise.** Every record is saved variables: written by the client at logout or reload, not as
it changes. A client that crashes loses everything since the last write, including the record of an apply made in that session;
the game then holds whatever EllesmereUI and TwichUI themselves saved. Within a session the record is written before the first
change and after every step, so a reload or a Lua error part way leaves a record that says so. TwichUI can't reconstruct what
the client never wrote.

## 7. Updates, preservation and reset

`updates.md` is the full description. The contract:

- An install again is an update: each unit is compared three ways (baseline, current, new) and kept or applied per the policy
  (keep my customizations by default; reapply recommended on request; per-unit, per-group and whole-addon choices).
- **Preservation never depends on omitting a write.** What the recipient keeps, owns or the package released is written into the
  new payload as the recipient has it (or left absent where it is absent), because importing a parent blob replaces everything
  in it. A value TwichUI can't read is carried as it is. A unit the recipient owns that ends up in the atomic layout group keeps the
  whole group theirs until they hand it back (Manage again).
- **Reset versus stop managing**: a package resets only units with a known default (TwichUI settings; the EllesmereUI allowlisted
  fields). Reset follows the **installed** addon's default (the stored value is cleared), is compared by effective value, and is
  verified (a value stored again reads differently). A recipient who changed the setting keeps theirs unless they choose the
  layout's. Positions, text sizes, blobs and the look can't be reset; a package that stops naming one releases it.
- Versions: a baseline part from another merge contract, TwichUI schema, or EllesmereUI version/migration vintage is not compared
  (only ownership stands); a newer baseline or management record blocks an update and is never overwritten.

## 8. Verification

Verify reads, never repairs. Three kinds of result, never one count: **by value** (TwichUI settings and places; EllesmereUI
positions and sizes within a unit, text sizes, allowlisted fields by their effective value, the accent by its signature),
**presence only** (EllesmereUI module blobs, layout links, fonts and palette: EllesmereUI rewrites them as it loads), and
**unverifiable** (could not be read). The result, the chat line, the baseline (`u`) and the documents use these words. Visual
acceptance is a separate, in-game check.

## 9. Reload and combat

| Operation | In combat | Reload |
|---|---|---|
| Plan, preview, review, Verify, compare | allowed (read only) | no |
| Apply, Undo, Restore, Keep this setup, Keep the update | refused (engine and adapters) | EllesmereUI's part needs one, started by the player |
| Full-size preview | refused; closes when combat starts | no |
| A received package's check | waits until combat ends | no |

Nothing reloads by itself; the reload button is not offered in combat. No secure frame, binding or action slot is touched.

## 10. Publishing and transport

`publishing.md` is the full description. The contract: a publication is an immutable envelope whose facts are derived again by
every reader; the transport is the sharing code's, extended; an offer is always asked, never auto-accepted; receiving only stores;
the packed block is bounded before unpacking (768 KB, at most 4 pieces) and while unpacking (each piece at most one slice in and
out, 8 MB in all; a hostile piece can still expand once by deflate's ratio before it is refused); the check of an arrived package
waits for combat to end. The fingerprint detects accidents, not forgery; the sender is the game's word. Media must be portable
for every package: published, received and bundled (the release runs the check that refuses another addon's file).

The bundled package is made one of two explicit ways (`presets.md`, `updating-the-bundled-layout.md`): **recaptured** offline from
saved profiles (the layers only; it never writes the choices), or **imported** from a package published in game
(`tools/update_bundled_layout.sh --from-published`: the choices exactly, the layers when they differ, the revision; refused when the
hand-written screen rules, targets or requirements differ). An import is verified as a round trip: the bundled package must resolve
as the published one (`Pub.Compare`), with identical choices and the published revision; only the title, made, source, the developer
flag and the declared format may differ. `Pub.Compare` (and `/tui layout compare`) says whether any two packages resolve the same.

## 11. Packaging, saved data and diagnostics

- `TwichUI_Layouts` (engine, adapters, package data) and `TwichUI_LayoutWizard` (wizard and authoring) are load-on-demand
  siblings; the core keeps only `LayoutsLauncher.lua`. Core operation never depends on either. Release wiring as for the other
  siblings (`.pkgmeta`, `tools/release.py`, diagnostics memory).
- `TwichUIDB.layouts` holds `install`, `managed`, `baseline`, `wizard`, `published`, `received`: records, not settings
  (`TwichConfig.LOCAL`, `RS.OWN_LEFT_OUT`); bounded; never in backups or shares. Where the first-install offer has got to is
  `TwichUIDB.onboarding` (core; `docs/onboarding.md`), which reads `install` and `managed` and never writes them.
- Diagnostics scopes `layouts.load`, `.plan`, `.apply`, `.verify`, `.restore`, `layouts.capture`, `layouts.publish.build`,
  `.check`, `.compare`, `.receive`, `layouts.store.open`, `layoutwizard.presets.capture`; wizard gauges for frames and listeners,
  and `layoutwizard.author.presets` for the presets' draft (`docs/diagnostics.md`).
