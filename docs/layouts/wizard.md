# The layout setup wizard

`TwichUI_LayoutWizard/` is a load-on-demand sibling addon (`RequiredDeps: !!!TwichUI, TwichUI_Layouts`, no saved variables
of its own) that lets a recipient review compatibility, pick one of the two bundled layouts (Classic or Compact Adventure; Phase 5), look at it
to scale and then at full size over their own screen, choose a small TwichUI helper preset, adjust four personal choices (accent, size, tooltip placement, friendly player nameplates), review exactly what would change, apply it with a restore point, see it
checked after the reload, and put the previous setup back. It adds no engine of its own: everything that changes the game
is `TwichUI_Layouts`' pipeline, fed by the package and its resolved screen geometry. It also lists packages other players sent
(step 1), updates an installed layout keeping the player's changes (`updates.md`), and finishes or stops managing a setup.
Authoring is a separate workspace the wizard doesn't link to (`publishing.md`). Nothing here has been run on WoW: Forever
(`implementation-status.md`, RH-2). `architecture.md` is the contract.

## Opening it, and what loads when

| Entry | What it does |
|---|---|
| `/tui layout` (hidden command, like `/tui bars` and `/tui nav`: listed on the pages that use it) | `LayoutsLauncher.lua` `L.Command`: bare, `wizard`, `setup` or `open` open the wizard; any other word goes to the developer commands in `TwichUI_Layouts/Dev.lua` (`/tui layout help` lists them) |
| Settings > Home > **Interface layout** > Layout setup | closes the settings window and calls `L.OpenWizard()` |
| Settings > Troubleshooting > **Layout setup** > Open | the same; with an install recorded it opens on the result (and Restore) |
| After a reload the player started from the wizard | `L.Continue` (the check after login) opens it once on the result; see "Reload and resume" |

Not offered, deliberately: a Welcome-dialog button (the dialog's wrapped button row and its tests are a different
feature's, and the wizard is reachable from Home), a permanent minimap or broker button (nothing in the wizard's source
mentions a minimap or a broker; the test scans for it), and any first-run or login prompt. A new installation, a login
with a stale note and a login with nothing waiting all load and open nothing (`test_layout_wizard.lua` §2).

Loading: `L.LoadWizard()` loads `TwichUI_LayoutWizard`, and the game loads `TwichUI_Layouts` first (its dependency). A
missing folder, a disabled addon, a missing dependency and an addon that loaded but never said it was ready are each said
in chat in plain words (`L.ExplainWizard`), kept for `/tui diagnostics` (`L.Snapshot().wizardFailed`), and leave the core
untouched. The window is built the first time it opens and kept; its pages are built when first shown; closing hides it.

## The workflow

Six steps, one window (780 × 590, TwichUI's own look, `Look.Shell`; fitted to small screens by `R.FitToScreen`; closes
with Escape through `UISpecialFrames`, never `RegisterGameMenuEscHandler`). A stepper at the top reaches only steps already
reached with Next; the footer holds Close, Back, and Next (Start on the first step, Apply on the review). The footer's
note says why a button is disabled.

| # | Step | Shows | Changes |
|---|---|---|---|
| 1 | Welcome | the emblem, what the setup does, and **Does it work here?**: EllesmereUI (present, usable, version, tested-with, Forever build, its own first-run setup pending), TwichUI profiles, the screen (size and UI scale, and for each layout at standard size whether it fits, fits but some pieces may overlap, or doesn't fit, with the problems and the UI scale at which it would), whether this is a preview build, combat, and an install already recorded (with a link to its result). Each line has a word (Ready, Check, Blocked, Note), not a colour alone. | nothing |
| 2 | Layout | a card for each layout, Classic and Compact Adventure (its picture, what it says, a Preview-build tag; the selected one unfolds what it covers), the preview, its scenario selector and the full-size button. Choosing a card re-draws the preview at once. | the layout choice is remembered |
| 3 | Helpers | the **TwichUI helpers** choice: one card per option the package offers (read from the package: its name, description and what it turns on and off and how many other settings it sets; the page scrolls, there is no fixed row), and the preview. A preset the player picked before, or the install recorded, that the package no longer offers is named and Next waits for a pick | the pick is remembered |
| 4 | Personalize | accent colour swatches (with the chosen one named), the size cards (Standard, Larger), **Tooltip placement** (Layout position, Follow mouse), **Friendly player nameplates** (Class colors, Standard blue, with a synthetic sample), Start over, and the preview, which follows each pick at once | the picks the player makes are remembered (a pick read from the game is not) |
| 5 | Review | the plan: your choices; TwichUI (at once, this character only): the profile copied and switched to, how many settings are set, what is turned on, how many on-screen pieces are placed; EllesmereUI (after a reload you start, every character on the account): the profile made and made active (and, on a repeat, that changes made in it since are replaced), what is replaced, positions and text sizes; **Left alone**; **Not placed** (the objectives, which Blizzard's Edit Mode places; the battle resurrection timer, left where the author had it); for an install again, **Updating your layout** (`updates.md`); the fit of the **final plan** (what Apply leaves, kept placements included) and what is kept where you have it; blockers with their reasons; what happens if a step fails. Apply is in the footer. | nothing until Apply is confirmed |
| 6 | Result | what the install record says now, with the actions that make sense: waiting for a reload (Reload now, Restore), checked after the reload (Restore, Keep this setup, Check again, Set up again), not everything reads back (the differences; Restore, Check again), only partly applied (what was done and what failed; Restore, Reload now), interrupted (Restore), restore waiting for a reload, restore not fully checked, restored, nothing changed (a clean failure, with its reason), a damaged, newer or other-character record (said, with only what is safe offered); for an update, **Undo this update** and **Keep the update**; a finished setup, **Installed and managed** (or "not verified" when its last check didn't match) with Set up again and Stop managing | only through its confirmed buttons |

### What never happens by itself

`Model.lua` is the whole of the wizard's behaviour, with no frames, so it is tested without a screen:

- Choosing remembers a pick (`TwichUIDB.layouts.wizard`) and re-draws the preview. It touches no profile, no EllesmereUI
  data and no feature (`test_layout_wizard.lua` §5 and §11 snapshot the game's saved data before and after, and count
  calls to `LY.Apply`, `LY.Restore`, `LY.Detach`, `ReloadUI` and EllesmereUI's import, switch and delete: all zero).
- The full plan (`LY.Plan`, read only) is computed only when the review is shown, again only when a pick or the screen
  changed, and dropped when the player leaves the review or closes the window (it holds the payload it would import:
  about 2 MB on the offline measurement).
- **Apply** is bound to the plan key the confirmation described: `Model.Apply(key)` refuses a different key ("stale"), the
  confirmation's `valid` check refuses it before that, and `LY.Apply` refuses it a third time. A screen that changes while
  the question is open cannot turn into a different install than the one approved.
- Apply, Restore, Keep this setup, Forget the record and Reload each sit behind a confirmation that names the exact scope
  (`R.Interact.Confirm`) and are refused in combat by the model, the confirmation (`combat = true`) and the engine.
- Nothing reloads by itself. **Reload now** is a button; it leaves a note (below) and calls `ReloadUI()`.

### Force re-apply

For an account an earlier install left stuck: a failed or stopped install, a Restore or Undo that never finished, another
package's record, a record that can't be read, or a profile with the install's name that no record claims. On the review, **Force
re-apply** (footer) is offered when an earlier install is recorded, or when every reason Apply is refused is one it can lift
(`Model.CanForce`); it is not offered on a clean first install. Pressing it changes nothing in the game: it makes the plan again
with `LY.Plan` `opts.force = true` (`session.force`, part of the plan signature and of the plan key, so a plain plan's key can't
apply a forced one), the review lists what it replaces, and **Apply** still asks, with the same lines in the question.
**Stop forcing**, leaving the review, changing layout and a successful Apply all drop the request; a refused Apply keeps it.

What a forced plan does (`Engine.lua` `DoPlan`/`DoApply`):

- This character's own install record, or one that can't be read, is set aside and the install is planned as a **new** install
  (no update comparison, no baseline); the management record of this character is set aside too. The new record has a new snapshot,
  so **Restore goes back to how things are when Apply is pressed, not to before the earlier install**; the review says so.
- A profile named for the install that no record claims (`target-taken`) is taken over: TwichUI's is written into (its other settings
  stay), EllesmereUI's is replaced by the layout's profile (EllesmereUI's `cleanSlate` import; what it held is not kept). It is
  recorded as not made by the install, so Restore never deletes it. If EllesmereUI's profile of that name is in use and nothing records
  what came before it, the install first switches to another profile (`Default` when there is one), which Restore goes back to.
- EllesmereUI's profile is imported again even when it already matches, and an install that matches is made again instead of being
  refused as "nothing to do".
- A forced install that then changes nothing puts the record it set aside back as it was.
- Another character's record (there is one install record for the account) is set aside the same way; the review and the question say it was theirs and that they can no longer Restore it from TwichUI. Their profiles are not deleted.
- **Not lifted:** a record from a newer TwichUI, combat, a missing or unusable EllesmereUI,
  EllesmereUI's first-run picker, a profile service that isn't available, a package that can't be used. Those still block, with their reasons.

Not available as a `/tui layout` developer option; the offline checks are `tests/test_layout_force.lua` and the Force section of
`tests/test_layout_wizard.lua`.

### Reload and resume

When the player presses **Reload now**, the wizard writes `layouts.wizard.resume = "install"` (or `"restore"` if the
record says a restore is waiting) just before `ReloadUI()`. At the next login `LayoutsLauncher.Continue` (3 seconds after
`PLAYER_LOGIN`, only while the install record says `applying`, `applied` or `restoring`) checks the install through the
engine as before and prints its chat line; **then, only if that note is set, it opens the wizard on the result** and the
wizard uses the note up. A reload the player made themselves gets the chat line only, and the wizard stays closed until it
is asked for. A leftover note with nothing waiting opens nothing. Verification itself is `LY.Continue`: read only.

## Choices

The package declares its `choices` (data in `TwichUI_Layouts/ChoicesData.lua`, written from a package published in game;
`presets.md`); the schema is in `architecture.md` §3. Each choice names exactly what it writes, and `Package.lua` refuses anything
else. The wizard shows nothing the package doesn't declare, and assumes no number of options.

| Choice | Kind | Options (default first) | Writes | Verified after the reload by |
|---|---|---|---|---|
| `helpers`: TwichUI helpers | preset (layer "preset") | as the package says. The bundled package today: **Leave them as they are** (nothing); **On-screen helpers** (`modules.classBars`, `modules.markersBar`, `modules.foodDrink` on); **Helpers and navigation** (the same, and `modules.navigation`) | a switch-on-only preset: TwichUI switches, turned on only. An editable preset (format 6, `presets.md`): any TwichUI setting the adapter manages, set to a value (off, 0 included) or reset; never a place, an EllesmereUI setting or another choice's setting. "Leave them as they are" (`keep`) writes none of them | the TwichUI adapter, by value |
| `accent`: Accent colour | enum (layer "choices"), `sets = { "ellesmereui:root.euiAccent" }` | **Aged gold** (the layout's own, `r .788 g .635 b .290`), **Your class colour** (`useClass = true`), **Verdigris** (`.36 .58 .57`, TwichUI's own teal), **Ember** (`.80 .45 .30`), **Dusk blue** (`.47 .60 .80`) | EllesmereUI's profile-root `euiAccent` and nothing else of its look (`EllesmereUI_Profiles.lua:3464`: `merged.euiAccent = DeepCopy(imported.euiAccent)`; `EllesmereUI_UICore.lua:527` `SetActiveProfileAccent` shows the shape `{ custom = { r, g, b }, useClass }`) | **by value**: `accent:class` or `accent:rgb:r,g,b` to three places (EllesmereUI's serializer keeps 14 digits, so an exact fingerprint of the floats would not match after the round trip) |
| `size`: Size | density | **Standard**, **Larger** | the geometry's density: component sizes (chat, damage meter, minimap, objectives) and the registered text sizes (chat text and tabs, meter text and bar height) | the placed positions and text sizes (Phase 3's checks) |

The bundled presets' three feature switches are the author-proposed set (D21): quiet, local, on-screen pieces that the layout
already has a place for (`class-bars`, `marker-bar`, `food-drink`, `nav-arrow`). No preset can name a key in `TwichConfig.LOCAL`
(nothing that shares, accepts setups, acts for you or talks to other players), an account-wide setting or a list: the adapter's
allowlist decides, for both kinds (`test_layout_wizard.lua` §5, `test_layout_presets.lua` §1).

**Presets on the Review step and on an update** (`Model.lua` `ReviewPreset`). The TwichUI section names the preset and lists what
it turns on, turns off, changes, resets and finds already set; what it leaves alone (settings only other presets manage); and which
of its settings stay as the player has them (kept or owned). With "Leave them as they are" it says it changes none of the settings
the presets manage, and how many of those the layout's own looks still set. On an install that already exists:

- **The same preset as installed**, updated by the package: its settings follow the update's rules (keep my customizations by
  default; `updates.md`), and the review says so.
- **Another preset, picked on purpose**: its settings take the preset's values (`PlanOpts`: "use recommended" for each of its
  settings the player hasn't answered themselves), so it does what it says. The review still offers "keep mine" for each; when a
  setting stays as the player has it (kept, or theirs: owned), the review says the preset won't be fully in effect.
- **A preset that is no longer offered** (an author removed it; its id is `retired`): the Helpers step says so with its id, the
  default is not applied in its place without a pick, and Next and Apply wait (`M.Missing`, `choose-preset`).

### Tooltip placement and friendly player nameplates (two choices of format 5)

Two more `enum` choices, asked on the Personalize step under the accent and size. Stable ids, labels and wording:

| Choice id | Label | Options (default first) | Writes | Verified after the reload by |
|---|---|---|---|---|
| `tooltip` | Tooltip placement | `layout` **Layout position** ("Show tooltips at this layout's configured location."); `cursor` **Follow mouse** ("Keep tooltips near your cursor.") | `layout`: the account-wide flag `EllesmereUIDB.tooltipAnchorCursor` off, and the install's profile's `tooltipFixedPos` at the layout's place. `cursor`: the flag on, and nothing else (the cursor position, offsets and growth direction, and the place the install's profile starts from, are left as they are) | **by value**: the flag as stored (an absent key reads as off), and the place within a unit |
| `friendly-plates` | Friendly player nameplates | `class` **Class colors** ("Use each friendly player's class color."); `blue` **Standard blue** ("Use the standard blue appearance for friendly players.") | `class`: `showFriendlyPlayers = true` and `classColorFriendly = true`. `blue`: `showFriendlyPlayers = false` (EllesmereUI > Nameplates > General > "Show EUI Friendly Player Nameplates" off), nothing else. Fields of the EllesmereUI nameplate blob | **by value** (booleans) |

What each one is, from source (EllesmereUI 9.6.8; `adapter-capabilities.md`, "Tooltip placement and friendly plates"):

- **The flag is account-wide.** `tooltipAnchorCursor` is a root key of `EllesmereUIDB`, shared by every character and every profile;
  switching profiles does not change it. The place is per profile (`profiles[name].tooltipFixedPos = { centerX, centerY }`). The
  wizard's Review and confirmation say so, and say that the cursor settings, the tooltip skin and the growth direction are not
  touched. Nothing EllesmereUI's import offers can carry either key without resetting a whole bundle of skin settings, so the
  adapter writes them itself, after the import, and reads each back (`AdapterEllesmere.lua` `A.WriteTip`).
- **Layout position** is the author's own place (`tooltipFixedPos = (900.83, -496.67)` on the 2866.67 × 1200 canvas, the same in every
  profile read), attached to the damage meter's bottom-left corner (the author's tooltip sits against it, bottoms level, 5 units
  short): `attach.ellesmereui.tooltip = "meter:BOTTOMLEFT"`, placed with the same call as every other position (`A.TipPlace`) and
  kept on the screen. It is in both layouts' package. A layout whose tooltip should sit elsewhere gives its own attach in its
  geometry variant.
- **Both tooltip modes only work while EllesmereUI's tooltip reskin is on** (`customTooltips ~= false`, and the Blizzard UI module
  loaded): off, the game's own place stands. The plan says so in a note; the settings are still recorded.
- **Standard blue is EllesmereUI letting go.** With "Show EUI Friendly Player Nameplates" off, EllesmereUI relinquishes friendly player
  nameplates to Blizzard's own nameplates and their settings (the toggle's own tooltip says so; `GeneralPage_Options.lua` 59–90). There is
  no blue in EllesmereUI to set; the blue is Blizzard's. Nothing else is written: not name-only mode, class colours, the bar colour,
  friendly NPC colours, enemy plates, party or raid frames, custom colours or any CVar. **Limit:** EllesmereUI's own switch also resets
  three CVars it manages (`nameplateShowOnlyNameForFriendlyPlayerUnits`, `ShowClassColorInFriendlyNameplate`,
  `nameplateUseClassColorForFriendlyPlayerUnitNames`) to Blizzard's defaults, but only when the player flips it in its own window; at load
  it merely stops writing them. The adapter does not touch CVars, so after an install the client keeps whatever EllesmereUI last set until the
  player changes it in Esc > Options > Nameplates. The page, the review and the sample say so. **Class colors** turns EllesmereUI's
  friendly plates back on if they were off (the layout's own state).

**Defaults.** A new setup: the layout's own recommendation (Layout position; Class colors, the author's `classColorFriendly = true`),
whatever the game has now. A setup that already exists whose player never made the choice (it was added after): the option the game's
own settings match (`LY.LivePick`, read only: the flag, the two plate switches), else the default, shown as "Shown as your game has it now"
and **not remembered** until they pick. Until then the plan keeps what they have for every setting of that choice (the update's
"keep mine"). A choice they changed from what the install recorded takes the layout's value for its settings (the review still offers
"keep mine" for each); one they left as it was keeps their own changes since, as an update does. A choice an earlier install
recorded keeps that pick. Plan and Apply take the same options (`Model.lua` `PlanOpts`).

**Previews.** *Tooltip visible* draws, for Layout position, the sample at EllesmereUI's box (280 × 165, corner nearest the screen
corner) at the layout's place for this screen, or on Review the plan's own row (so a place the player keeps is drawn where they
have it). For Follow mouse it draws the sample at rest (bottom at the middle of the screen, the cursor marked) and moves it with the
pointer **only while the pointer is over the miniature**: one throttled `OnUpdate` (about 30 a second) set on entering and removed on
leaving, hiding, another scenario or closing, clamped inside the miniature, never reading or moving the game's tooltip
(`Preview.lua` `view:Track`; scope `layoutwizard.preview.follow`, gauge of the same name). The full-size overlay draws it at rest
and never follows. A package with no tooltip choice still draws the game's own default place. The friendly-plate sample is three
synthetic players on the page (EllesmereUI's class colours, names only in a name-only layout; a plain blue bar for Standard blue, Blizzard's plate) and a caption; it is never a real nameplate.

## Saved state

`TwichUIDB.layouts.wizard = { v = 1, variant = "<layout id>", picks = { [choice id] = option id }, resume = "install" | "restore" }`, beside the
install record (`layouts.install`, `Journal.lua`), covered by the same `layouts` entries in `TwichConfig.LOCAL` and
`RS.OWN_LEFT_OUT` (records, not settings: a backup or a share never carries them). Read-only reading, narrow repair
(`State.lua`):

- not a table, or `v` not a whole number ≥ 1: defaults; nothing is written by reading;
- `v` newer than this version: defaults are used and **a pick never overwrites it** (`test_layout_wizard.lua` §9);
- a pick that isn't an option of its choice goes back to that choice's default and the others are kept, and is reported
  (`dropped`): for a preset, the wizard says the option is gone and waits for a pick; unknown choices
  and a bad `resume` are ignored; a `variant` that isn't one of the package's goes back to the first (Classic); a record
  with no `variant` (from Phase 4) reads as Classic; the next save writes a clean record. Every writer (a pick, the layout
  choice, the reload note, using the note up) saves the chosen layout with the picks, so none forgets it;
- bounded: one layout id and at most one entry per choice the package declares (5 in the Adventure package; the bound is 6, `LY.MAX_CHOICES`, and a record holds at most `S.MAX_PICKS` = 8). The scenario and the open state of the
  full-size preview are never saved.

## How it uses the pipeline

| Phase 2 stage | In the wizard |
|---|---|
| Validate | `LY.Plan` validates the package, including its choices (the wizard does not validate on its own) |
| Resolve | the picks go to `LY.Resolve` as `opts.picks`; the geometry for the preview is `LY.Geometry.Resolve` for the same screen and density |
| Review | `LY.Plan` → `Model.Review()` (text only) |
| Snapshot, Apply | `LY.Apply(pkg, variant, key, { picks })`: the snapshot is taken and checked before the record is written; the record keeps the picks |
| Verify | after the reload (`LY.Continue`), or `LY.Verify(false)` from Check again (read only; nothing is repaired) |
| Restore | `LY.PlanRestore` → the confirmation → `LY.Restore(key)` → after the reload `LY.VerifyRestore` |
| Finish / Detach | "Keep this setup": `LY.Finish` (ends the restore point and Undo, keeps managing). "Forget the record" and "Stop managing": `LY.Detach` after a confirmation (refused for another character's readable record) |

Engine changes this needed (all in `TwichUI_Layouts`, `architecture.md` §3): package format 3 with `choices`;
`LY.Resolve` `opts.picks` and `resolved.picks`; the picks in the plan key and in the install record (validated, at most 8);
the EllesmereUI adapter's acceptance of `root.euiAccent` (and only that) from a choice, and its by-value check.

## The preview, the scenarios and the full-size overlay

One **scene** (`Scene.lua`, no frames) feeds both drawings, so the miniature, the overlay and the install cannot disagree:

- the **components** are `LY.Geometry.Resolve`'s result for the chosen layout (`opts.variant`), this screen and the picked size:
  the same call `LY.Plan` makes, so the plan, the miniature and the overlay hold the same rects (`test_layout_wizard.lua` §15
  compares them for four screens, both layouts and both sizes);
- the **pieces inside them** (unit frames, cast bars, the action bars, the party frames, TwichUI's own markers) are
  `LY.Elements` for that geometry: the install's own position math (`EllesmereAdapter.Resolved`, `TwichUIAdapter.PlaceOne`)
  applied to the same stored records. §15 compares every EllesmereUI piece with what the install then **writes** into the
  profile, using a centre-from-record formula written out independently in the test;
- what is drawn **inside a component** (chat lines, meter bars, objectives text) and the tooltip is sample content, chosen by
  the scenario; plain sample text, nothing from the player's game.

Nothing is a hand-coded coordinate of the layout: the only fractions in the code are the miniature's sample shapes inside a
chat, meter, minimap or objectives box.

**Scenarios** (Solo, Target selected, Dungeon party, Long objectives, Tooltip visible) change only what the sample shows, never
where anything is (a test compares every component's rect across all five). Solo: your frame, pet and bars. Target: adds the
target, its target, its cast bar and yours. Party: the party frames (five members in a column, or a row with `partyHorizontal`,
the arrangement being a sample), the focus frame and its cast bar, five meter rows, six chat lines. Long objectives: two long
quests that wrap, drawn at the box's width; if they need more height than the box has, the overlay says "The text runs past this
box" instead of hiding it. Tooltip: a sample tooltip where the "Tooltip placement" pick puts it (above); for a package with no such choice, at
`GameTooltipDefaultContainer`'s first point, read the way Blizzard's `GameTooltip_SetDefaultAnchor` reads it (only when it is
placed against the screen), else Forever's own default (bottom right, 9 in, 85 up). A scenario is not remembered.

**The miniature** (`Preview.lua`) draws the scene to scale on a frame with the viewport's proportions (330 × 200 at most): each
managed component a box with sample shapes, each piece a flat rectangle, accent outlines, overlapping or off-screen components
outlined in the warning colour with "!". Boxes and pieces are made once and moved on every draw. Under it: the scenario tabs and
**See it full size**.

**The full-size overlay** (`Overlay.lua`) draws the same scene at the real size and place, in UIParent's own units from the centre of
the screen, with sample content (unit frames with health and power, action bars as button squares, cast bars, party blocks,
chat lines, meter bars, objectives text, a tooltip, TwichUI's pieces as labelled markers). What it is and is not:

| | |
|---|---|
| Preview, and says so | a bar of controls with "PREVIEW  <layout> - nothing is applied", the sentence that your interface is dimmed behind it and not hidden or moved, "(sample)" on every box, "Doesn't fit this screen: …" when it doesn't |
| Click-through | the covering frame and every box take no mouse and no keyboard; only the control bar does (a test walks the frame tree) |
| Inert | no secure template, no `SetAttribute`, no action or spell call, no hook, no timer, no `OnUpdate`, no `ReloadUI`, no `LY.Apply`/`Restore` and no saved variable named in `Overlay.lua` (the source is scanned); the mock buttons are textures |
| No writes | opening, switching layout, changing scenario and closing change no profile and call no install; the only thing remembered is the layout choice, as in the wizard |
| Out of combat | it will not open in combat (the button says why) and closes when combat starts |
| The live interface | **not hidden or moved**: hiding UIParent would hide the preview with it, and moving or hiding protected frames is not allowed, so the screen behind is dimmed (an opaque-ish scrim) instead. EllesmereUI's real bars, frames and chat stay visible behind it. If the dimming is not enough on someone's screen, the answer is the miniature, not forcing the live UI away |
| Controls | **Back** (the wizard where it was left), **Switch to <other layout>** (shows the other layout at once; nothing applied), **Exit** (closes the preview and the wizard, nothing changed), the five scenario tabs, Escape (the game's own list, once: closes the preview and returns to the wizard) |
| Cleanup | it listens for `PLAYER_REGEN_DISABLED` (closes), `DISPLAY_SIZE_CHANGED` and `UI_SCALE_CHANGED` (re-draws for the new screen) only while shown; it closes when the wizard closes, when combat starts and when a profile changes (`Profiles.OnChange`, one listener added once for the session); asking for the wizard again (`/tui layout`) brings the setup back |

The wizard window is **set aside, not closed**, while the preview is up (`Window.Suspend` / `Resume`): the session, its step and
its picks stay, and closing the window while it is set aside ends the session as closing always does.

**Fidelity limits** (what the preview does not claim): EllesmereUI draws the real frames, snaps them to its pixel grid and can
differ by a few units from a sample size; third-party styling (borders, textures, fonts, colours) is not reproduced, only
illustrated; a piece whose size the layout's data doesn't give (the Cooldown Manager's bars, class power, the data bars, the
raid frames, the minimap's shape) is not drawn at all; TwichUI's own pieces are 26-unit markers because their size belongs to
their features; the pet and stance pieces sit outside Compact's checked box (they follow it, are drawn, and since RH-1 their
overlap with chat is reported as "may overlap", D44); the quest tracker is placed by Blizzard's Edit Mode and is shown but not
applied or counted; the sample tooltip's size is a sample, and EllesmereUI's real tooltip pins its own corner to the box. Offline: the geometry takes about 0.12 ms and a miniature draw
about 0.14 ms on stand-in frames (the client's `SetPoint` and `SetSize` cost more; not measured).

## Preview and fit (RH-1)

What the preview shows, and what a fit claim means:

| Step | The preview shows | The fit claim is about |
|---|---|---|
| Welcome (each layout) | nothing drawn | the recommended placement at standard size: fits; fits but some pieces may overlap; or doesn't fit, with the UI scale at which it would |
| Layout, Helpers, Personalize | the layout's **recommended** placement, at once, for this screen and size | the recommended placement |
| Review, first install | the plan's own placement (the same as the recommended one) | that placement |
| Review, update | the **final plan**: your kept minimap, chat and meter at your own rect and size, the pieces you keep at your places (sample sizes), and the caption says which of your placements it draws and which it can't (a form TwichUI can't read); with EllesmereUI kept as it is, it says so instead of claiming the layout's fit | what Apply leaves |

- **Three levels**: the components (Geometry), the pieces inside them (`LY.Fit`, sample sizes, so "may overlap"), and what is
  only illustrative (the objective tracker, never applied, never counted). What the same check finds on the author's own canvas is
  the author's arrangement and is not reported.
- **Never moved to clear a warning**: a placement you keep stays where you put it; the review says it is off screen or over
  something.
- **Scale guidance**: when the components don't fit, the welcome step and the review give the UI scale at which they would (the
  same resolver on screens of your proportions; never below 0.64), and say the setup never changes the UI scale. The UI scale
  shown is the setting (768 / UIParent height), not the effective scale.
- **Nothing is changed to draw it**: the final plan is the read-only plan (`LY.Plan`); a test compares every profile before and after.

## Artwork

Four sources existed in `../assets/` (names are the author's: `wizard_suite_emblem.png`, `wizard_classic_adventure.png`,
`wizard_personalize_screenfit.png`, `wizard_compact_adventure.png`). Their contents and geometry were read from the files,
not assumed, by `tools/make_layout_wizard_art.py` (standard library only, like the other `tools/make_*.py`; `--check`
builds nothing and prints the findings). Copies are kept in `assets/layout-wizard-*-source.png` (not packaged).

| Source | Found | Runtime file | How it was made |
|---|---|---|---|
| Setup emblem | 1254 × 1254, 8-bit **RGB, no alpha**: the transparency is a grey checkerboard painted into the pixels | `media/emblem.tga`, 128 × 128 | Background removed by flooding from the border through neutral light-grey pixels only (the picture is warm or dark; nothing the flood can't reach from outside is touched: 62.6% of the pixels), and the soft rim (4,226 pixels) given an alpha by unmixing it from the local checker grey. Inspected at full size on dark and light backgrounds: no halo. Then cropped to content and shrunk. |
| Classic Adventure | 1536 × 1024 RGBA, genuine transparency (about three quarters alpha 0, a soft aura kept as painted) | `media/classic.tga`, 512 × 256 | cropped to content (938 × 659) and shrunk to fit, centred |
| Personalize and Screen Fit | one 1774 × 887 RGBA sheet; the two pictures are separate runs of columns holding any alpha (126–811 and 925–1629), found by measurement | `media/personalize.tga`, `media/screenfit.tga`, 128 × 128 each | split at the clear gap; each cut to content and shrunk to fit |
| Compact Adventure | 1536 × 1024 RGBA, same kind as Classic's (a belt pouch with a scroll and a dagger) | `media/compact.tga`, 512 × 256 | built in Phase 5 with `--phase5`: cropped to content (a 226 × 252 picture centred in the 512 × 256 file, like Classic's) |

All TGAs are uncompressed 32-bit, bottom-left origin, 8 alpha bits (the format of every other `media/` file), power-of-two
sizes, with colour carried 2 px into the clear pixels so bilinear filtering shows no dark matte. Total shipped: about 1.2 MB (Compact's picture is 524 KB).
Nothing was recoloured, sharpened or generated; no replacement was made for anything missing.

Runtime: the three small pictures are registered in the icon registry (`Art.lua` adds `layoutEmblem`, `layoutPersonalize`
and `layoutScreenFit` to `R.Icons.list`) and drawn with `R.Icons.Apply`, so a file the game refuses falls back to
TwichUI's own emblem. Classic's and Compact's pictures are drawn by `Art.Apply` with the same rule (refused: hidden). A picture is
decoration only: with every file refused the whole wizard, an install included, still works (`test_layout_wizard.lua`
§10). Nothing is reserved or missing any more (`Art.Missing()` is empty). The sources' dimensions and what each needed are in the tool's header.

## Packaging, release and diagnostics

- `.pkgmeta` `move-folders`, `tools/release.py` (`WIZARD`, `ADDONS`, `LOAD_ON_DEMAND`, and `REQUIRED_DEPS`: the wizard
  requires `!!!TwichUI, TwichUI_Layouts`, every other load-on-demand addon only the core), `tests/test_release_tools.py`,
  `RELEASING.md` (six folders), and the git-ignored `tools/deploy.sh`.
- Diagnostics (`CLAUDE.md`, "Diagnostics coverage"): scopes `layoutwizard.load` (`LayoutsLauncher.lua`),
  `layoutwizard.build` (the first open) and `layoutwizard.preview` (each draw), and from Phase 5
  `layoutwizard.overlay.build` (the first time the full-size preview opens) and `layoutwizard.overlay` (each draw of it),
  registered in `DX.OPS` and `docs/diagnostics.md`; gauges `layoutwizard.events` (4 while open, 0 closed),
  `layoutwizard.frames` (does not grow when reopened), `layoutwizard.overlay.events` (3 while the preview is shown, 0
  closed) and `layoutwizard.overlay.frames` (frames and textures it keeps, bounded by the package); the addon's memory is read and reported (`Base.lua`, `Collect.lua` `ReadMemory` and `OURS`, `Export.lua`,
  `Findings.lua`, `Session.lua`, `Window.lua`). The plan, apply, verify and restore scopes are `layouts.*` (Phase 2),
  already around the engine calls the wizard makes. Nothing personal is in a report: the wizard stores picks (option ids)
  only.
- Not scoped, and why: the pages' text refreshes (each runs only on a click, a pick or an event while the window is open,
  with no per-frame work); `Model.Compat()` (a few reads); the footer; building the scene (`Scene.Build`, `LY.Elements`: table
  reads and arithmetic, cached until a pick, layout, scenario or the screen changes). No `OnUpdate` or timer is installed,
  and the only hook is one `Profiles.OnChange` listener per piece (the window's, the overlay's), added once.

## Checks

`tests/test_layout_wizard.lua` (with `tests/layouts_mock.lua`) drives the real window, through its buttons, with stand-in
frames, the real engine and a stand-in EllesmereUI of the real functions' shape. It covers: the `.toc`, files and that the
source has no minimap button, no Escape handler call, no code loaded from text and no login event; loading on demand, the
entries, and that failures are explained; that nothing opens by itself; every compatibility case (no, old, other-client,
newer-than-tested EllesmereUI; its first-run setup; an unreadable and a too-small and a narrow screen; combat); every step,
Back, the stepper, cancelling at each step and reopening; the preview's proportions for five screens and that its boxes
are the resolved geometry to scale; that a pick changes the preview, the plan, the payload and the key together; that
choosing changes nothing in the game; the confirmation's text; apply, the reload the player starts, the check after it and
the wizard opening on it; a reload the player made themselves; Restore (declined, confirmed, after its reload); setting up
again and restoring to before the first install; an interrupted install; a clean failure and a part-way failure; combat
(window, model, engine); a plan that went stale; a profile of the package's name that isn't ours; reopening six times
with no new frames, listeners or hooks; the gauges and scopes; saved wizard state that is junk, partly invalid, newer, or
a leftover note; a damaged, newer or other-character install record; the artwork (TGA headers, sizes, the reserved file
absent, every picture refused).
`tests/test_layouts.lua` §17 covers the engine side: every refusal of a malformed `choices` section, picks resolving into
the layers, the plan key and the record following the picks, and the accent read back by value (including a number that
went through EllesmereUI's serializer). `test_release_tools.py`, `test_perf_engine.lua` and the settings contract fixture
cover the wiring.

Mutations made by hand and reverted, each failing a test: apply without the shown key; pages rebuilt on every show;
saved picks not validated; a newer state overwritten; the wizard always opening after a check; never opening; no resume
note; a preview ignoring the viewport's proportions; events left registered; a preset allowed to turn things off; two
choices allowed to write one unit; the accent checked only for presence; combat not refused by the model; a refused picture
not handled; a missing EllesmereUI not blocking; the session surviving close; a pick that mutates the game; the record's
picks unchecked; the release tool accepting the wrong dependencies.

Measured offline (Lua 5.1 on the development machine, not the game): the wizard's code adds about 170 KB of Lua heap when
loaded; `LY.Plan` for the review takes about 32 ms and allocates about 8 MB of garbage (it is computed once per review, not
per click); the plan, while held, is about 2 MB and is released when the player leaves the review. In-game memory and CPU
are not measured: a `/tui perf` General capture with the wizard closed, and one opening it ten times, are among the
checks below.

### Phase 5 checks

`test_layout_geometry.lua` §8–§10: the variant mechanism on a synthetic layout (merge by id, the shared spec unchanged, caching,
every refusal, a variant for a layout the package lacks); Compact on nine screens × two densities (fits, on screen, never
under a minimum, fixed sizes kept); the author's own screen gives back what was captured (41 positions, every link offset, every
TwichUI place), the 1080p moves (bottom row, raid frames from the left edge, the bar on the meter's top), narrow chat above the
block, 1365 × 768 honestly not fitting; `LY.Elements` (sizes, the bar rule against the author's own 377 vs 375, notes, markers)
and every piece compared with what `Adapt` writes on five screens × two densities; the capture (no TwichUI side, nothing
personal, 11 shared modules proven by fingerprint, 7 + 7 own), and promoting a setting between the layers. `test_layouts.lua` §18:
both layouts through plan/apply/verify, the switch (same profiles, first snapshot kept, no profile added, four more switches),
unrelated data untouched, restore from either layout, narrow and small screens, the developer command (`compact`).
`test_layout_wizard.lua` §12–§17: both cards and the preview following at once, forty switches making nothing, choices and the
review and question naming the layout and saying it is a switch, apply/reload/resume/restore through a switch, the five
scenarios (what each shows, nothing moving, the tooltip place and its fallback, not remembered), scene = plan = miniature =
overlay = what the install writes, the overlay's source scan, click-through, inertness, Back/Exit/Escape/switch/scenario, combat,
profile change, wizard close, screen change, ten opens and closes making nothing, long text and overflow, narrow Compact, and
saved state with a layout. Mutations made and reverted, each failing a test: the overlay taking the mouse, variants ignored by
`Geometry.Spec`, the combat close removed, the profile listener removed, scenarios not filtering pieces, shared modules not
shared.

## Manual acceptance checklist (none done; on WoW: Forever)

1. `/tui layout` opens the window; it is complete without EllesmereUI's skins; Escape closes it; the Home and
   Troubleshooting buttons open it; no minimap or broker button exists; a new character gets no prompt.
2. The pictures draw (emblem, Classic, Personalize, Screen Fit) with no green or white square, with transparent
   backgrounds, at 1080p, 1440p and an ultrawide.
3. Welcome: the EllesmereUI line reads right (version, Forever build); with EllesmereUI disabled, Start is blocked with
   the reason; in combat, the line says so.
4. Each step; Back; the stepper; Close at each step changes nothing (compare `/tui` settings and EllesmereUI's profile list
   before and after).
5. Picks: each accent recolours the preview's outlines; Larger enlarges chat, the meter and the minimap boxes; the
   helpers cards select with a bar and "Selected".
6. Review matches what the apply then does: profile names, the account-wide note, the reload, "Left alone", "Not placed".
7. Apply: the question names both profiles; Cancel changes nothing; Apply makes both profiles and nothing reloads.
8. Reload now: after the reload the wizard opens on "Checked after the reload" (verified). A reload made with `/reload`
   instead prints the chat line and leaves the wizard closed.
9. The accent shows in EllesmereUI (its accent swatch reads the picked colour); the picked helpers are on in
   `/tui options`; the size you picked is the size you see; positions match the preview on your screen (screenshots).
10. Restore previous setup: the question lists what it does; after the reload the wizard says "Restored", EllesmereUI is
    back on your profile, the install's profiles are gone, your TwichUI profile is as it was.
11. Set up again with another accent: applies, reloads, verifies; Restore goes back to before the first install.
12. In combat: Apply, Restore and Reload now are refused with a reason; they work again after combat.
13. Interrupt (`/reload` the moment after Apply, or kill the client): next login says interrupted; Restore works.
14. Open and close the window ten times in a `/tui perf` capture: the `layoutwizard.events` and `layoutwizard.frames`
    gauges stay flat; `TwichUI_LayoutWizard` memory is reported.
15. A Forever EllesmereUI: the Retail-captured blobs load; the accent is read back (`accent:rgb` matches live).

## Phase 5 manual checks (none done; on WoW: Forever)

16. Step 2 shows both pictures with transparent backgrounds; clicking a card re-draws the miniature at once; nothing in
    EllesmereUI's profile list or TwichUI's profiles changes (compare before and after).
17. **See it full size** at 1080p, 1440p and the ultrawide: the boxes and pieces sit where the install then puts the real ones
    (apply, reload, screenshot, compare), including Compact's bottom strip, the bar on the damage meter and the party frames.
18. The dimming: is the live interface behind it too distracting? Click-through works (a world click, a target click, moving
    the camera); keys still work; Escape returns to the wizard; nothing of EllesmereUI is hidden or moved.
19. Combat: the button is refused in combat; pulling a mob with the overlay open closes it; a profile switch (`/tui` profiles)
    closes it; `/reload` with it open leaves nothing behind.
20. Switch layout in the overlay and in the wizard; apply Compact over Classic: the review says it is a switch, the same two
    profiles are rewritten, the check after the reload says verified, Restore goes back to before the first install.
21. Compact on the author's own screen reproduces their `TwichUI - Minimal Adventure` look (positions of bars, unit frames,
    cast bar, raid and party frames, the bar on the meter); on a 1920 × 1080 screen the bottom row sits on the bottom edge; on a
    narrower screen chat is above the strip.
22. TwichUI's pieces in Compact: class bars, marker bar, navigation arrow and food/drink sit where Classic's capture put them
    (D31); look at the markers in the overlay first, then in game. The food and drink proxy is also linked to bar 3 in
    Compact's layout links.
23. `/tui perf`: open the overlay ten times; `layoutwizard.overlay.events` and `.frames` stay flat; the addon's memory with both
    layouts' data loaded (about 1.6 MB of Lua tables offline) is reported.
