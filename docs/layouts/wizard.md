# The layout setup wizard

`TwichUI_LayoutWizard/` is a load-on-demand sibling addon (`RequiredDeps: !!!TwichUI, TwichUI_Layouts`, no saved variables
of its own) that lets a recipient review compatibility, pick one of the two bundled layouts (Classic or Compact Adventure; Phase 5), look at it
to scale and then at full size over their own screen, choose a small TwichUI helper preset, adjust four personal choices (accent, size, tooltip placement, friendly player nameplates), review exactly what would change, apply it with a restore point (one short question, **Apply & Reload**, applies it and reloads the interface), see it
checked after the reload in a small result dialog, and put the previous setup back. It adds no engine of its own: everything that changes the game
is `TwichUI_Layouts`' pipeline, fed by the package and its resolved screen geometry. It also lists packages other players sent
(step 1), updates an installed layout keeping the player's changes (`updates.md`), and finishes or stops managing a setup. What a page shows
by default, and what is behind a button, is "Presentation" below.
Authoring is a separate workspace the wizard doesn't link to (`publishing.md`). Nothing here has been run on WoW: Forever
(`implementation-status.md`, RH-2). `architecture.md` is the contract.

## Opening it, and what loads when

| Entry | What it does |
|---|---|
| `/tui layout` (hidden command, like `/tui bars` and `/tui nav`: listed on the pages that use it) | `LayoutsLauncher.lua` `L.Command`: bare, `wizard`, `setup` or `open` open the wizard; any other word goes to the developer commands in `TwichUI_Layouts/Dev.lua` (`/tui layout help` lists them) |
| Settings > Home > **Interface layout** > Layout setup | closes the settings window and calls `L.OpenWizard()` |
| Settings > Troubleshooting > **Layout setup** > Open | the same; with an install recorded it opens on the result (and Restore) |
| After a reload the player started from the wizard | `L.Continue` (the check after login) opens it once on the result; see "Reload and resume" |
| A new installation | `Onboarding.lua` (core) opens it once the game is ready, as TwichUI's first-install setup, and holds EllesmereUI's own first-run picker for it: `docs/onboarding.md` is that policy (when, how often, Do this later, Skip, EllesmereUI) |

Not offered, deliberately: a Welcome-dialog button (the dialog's wrapped button row and its tests are a different
feature's, and the wizard is reachable from Home), a permanent minimap or broker button (nothing in the wizard's source
mentions a minimap or a broker; the test scans for it), and any login prompt other than the first-install offer. The
wizard's own files register no login event; a login with a stale note, or with nothing waiting, loads and opens nothing
(`test_layout_wizard.lua` §2, without the first-install offer loaded; the offer is `tests/test_onboarding.lua`).

Loading: `L.LoadWizard()` loads `TwichUI_LayoutWizard`, and the game loads `TwichUI_Layouts` first (its dependency). A
missing folder, a disabled addon, a missing dependency and an addon that loaded but never said it was ready are each said
in chat in plain words (`L.ExplainWizard`), kept for `/tui diagnostics` (`L.Snapshot().wizardFailed`), and leave the core
untouched. The window is built the first time it opens and kept; its pages are built when first shown; closing hides it.

## The workflow

Six steps, one window (780 × 590, TwichUI's own look, `Look.Shell`; fitted to small screens by `R.FitToScreen`; closes
with Escape through `UISpecialFrames`, never `RegisterGameMenuEscHandler`). A stepper at the top reaches only steps already
reached with Next: the step you are on has a heavy bar and a warm wash, a step behind you carries a small check, a step not
reached is quiet and can't be chosen. The footer holds Close (**Do this later** on a first install: closing it then puts the
setup off), Back, and one primary action in the same corner on every step: **Get started** on the first step, **Next**, **Apply & Reload**
on the review (**Apply** when the plan needs no reload), **Done** on the review when there is nothing to apply. The sixth step is not a page of this window: it is the compact
result dialog ("Applying and finishing" below), with no stepper and no footer. The footer's note says why a
button is disabled. The footer is outside the scrolling page, always. While the window
is shown the game behind it is dimmed a little by one click-through frame (`docs/onboarding.md`, "The dimming"); the
full-size preview has its own and the two are never shown together.

| # | Step | Shows by default (the rest is behind a button) | Changes |
|---|---|---|---|
| 1 | Welcome | the emblem, **Make yourself at home** and one line, three points (choose a layout, add your preferences, review then apply: nothing changes until you apply, and the current setup is backed up when you do), that EllesmereUI's part applies to every character on the account, and a verdict: **Ready**, **Items to review** or **Setup blocked**, with every warning and blocker and its short explanation at once. On a first install (`Pages.FIRST`): **Skip setup** and, when EllesmereUI's first run was held for it, **Use EllesmereUI's setup instead**. Behind **Compatibility details**: every check (EllesmereUI present, usable, version, tested-with, Forever build, its own first-run setup pending; TwichUI profiles; the screen's size and UI scale, and for each layout at standard size whether it fits, fits but some pieces may overlap, or doesn't fit, with the problems and the UI scale at which it would; a preview build; combat; an install already recorded, with a link to its result), each with a word (Ready, Check, Blocked, Note), not a colour alone | nothing |
| 2 | Layout | one card for each layout: its picture, title, one short description, up to three traits, the selected one with a check, an outline and the word Selected (a Preview-build tag on a preview package); both Classic and Compact Adventure are fully in view at the standard window size. The preview, its scenario selector and the full-size button. Behind **Layout details**: what the chosen layout covers. Choosing a card re-draws the preview at once | the layout choice is remembered |
| 3 | Helpers | the **TwichUI helpers** choice: one full-width card for each preset the package offers, whatever its number (read from the package: its label, a one-sentence description, a picture), the chosen one selected; one line saying the layout's look and places apply whichever is chosen. Behind **View included settings** on each card: the author's full description, what it turns on, what it turns off, how many other settings it changes or resets, what it leaves alone. A preset the player picked before, or the install recorded, that the package no longer offers is named and Next waits for a pick. No layout preview here: it shows nothing of what a helper does | the pick is remembered |
| 4 | Personalize | the accent swatches (each named, the chosen one checked, the class colour carrying the class's own icon), the size cards (Standard, Larger, each showing "Aa" at its relative size, and what the package says the choice changes), **Tooltip placement** (Layout position, Follow mouse, each with its illustration; "Applies to every character on this account."), **Friendly player nameplates** (Class colors, Standard blue, each showing three synthetic sample players), Start over. The page fits the standard viewport at its defaults. No large layout preview here: the preview follows these picks on the Layout and Review steps | the picks the player makes are remembered (a pick read from the game is not) |
| 5 | Review | a receipt: **Ready to apply** (a fresh installation), **Ready to update** (an install again), **You're already up to date.** or **Can't apply yet**, the choices in six rows (Layout, Helpers, Accent, Tooltip placement, Friendly nameplates, Size), and short statements of what it means: what is set in TwichUI (this character only) and in EllesmereUI (every character on the account), that tooltip placement is account-wide, that **Apply & Reload** applies and then reloads your interface (you are asked first), the restore point, what isn't placed (for example "Objectives position isn't changed"), a fit warning or a blocker in words ("Check:", "Blocked:"). An update adds one row, **Update: Keep my customizations** [Change], the counts (recommended changes, personal settings kept, conflicts, parts checked for presence only) and the decisions an update needs (an addon kept or replaced whole, linked frames, warnings). Behind **View changes**: the account of every change, **Left alone**, **Not placed**, **If something goes wrong**, and the update's long summary. Behind **Change**: the three policies and every setting with its choices. Behind **Advanced**: **Force re-apply** (opened for you when a blocked review needs it). **Apply & Reload** (or **Apply**) is in the footer | nothing until the question is accepted |
| 6 | Result | the compact result dialog ("Applying and finishing" below), not a page of the six-step window: its own heading for the outcome, the layout's name, one sentence, at most one quiet note, and the actions that make sense. **Details** and **Manage layout** are folded | only through its confirmed buttons |

### What never happens by itself

`Model.lua` is the whole of the wizard's behaviour, with no frames, so it is tested without a screen:

- Choosing remembers a pick (`TwichUIDB.layouts.wizard`) and re-draws the preview. It touches no profile, no EllesmereUI
  data and no feature (`test_layout_wizard.lua` §5 and §11 snapshot the game's saved data before and after, and count
  calls to `LY.Apply`, `LY.Restore`, `LY.Detach`, `ReloadUI` and EllesmereUI's import, switch and delete: all zero).
- The full plan (`LY.Plan`, read only) is computed only when the review is shown, again only when a pick or the screen
  changed, and dropped when the player leaves the review or closes the window (it holds the payload it would import:
  about 2 MB on the offline measurement).
- **Apply** is bound to the plan key the confirmation described: `Model.Apply(key)` / `Model.ApplyAndReload(key, announced)` refuse a
  different key ("stale"), the confirmation's `valid` check refuses it before that, and `LY.Apply` refuses it a third time. A screen
  that changes while the question is open cannot turn into a different install than the one approved.
- Apply, Restore, Keep this setup, Forget the record and Reload each sit behind a confirmation that names the exact scope
  (`R.Interact.Confirm`) and are refused in combat by the model, the confirmation (`combat = true`) and the engine.
- The only reload that happens without a further click is the one **Apply & Reload** announced (below). Restore and Undo this update
  still end on **Reload now**, a button; it leaves a note and calls `ReloadUI()`.

### Force re-apply

For an account an earlier install left stuck: a failed or stopped install, a Restore or Undo that never finished, another
package's record, a record that can't be read, or a profile with the install's name that no record claims. On the review,
**Force re-apply** is under **Advanced** (not a normal step): offered when an earlier install is recorded, or when every reason Apply is
refused is one it can lift (`Model.CanForce`); it is not offered on a clean first install. **Advanced** is folded unless a blocked review
needs it or a forced plan is on, when it is open and the blocker is in view beside it. When there is nothing to apply (already up to
date) the page says so and the footer's primary action is **Done**; Force re-apply is still there under Advanced. Pressing it changes nothing in the game: it makes the plan again
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
  EllesmereUI's first-run picker (unless it is held for TwichUI's own setup, when it never blocked), a profile service that isn't available, a package that can't be used. Those still block, with their reasons.

Not available as a `/tui layout` developer option; the offline checks are `tests/test_layout_force.lua` and the Force section of
`tests/test_layout_wizard.lua`.

### Reload and resume

The reload is either the one **Apply & Reload** started (below) or **Reload now** (a Restore, an Undo, or an apply whose automatic reload
did not start). Both write `layouts.wizard.resume = "install"` (or `"restore"` if the record says a restore is waiting), read it back, and
only then call `ReloadUI()`. At the next login `LayoutsLauncher.Continue` (3 seconds after
`PLAYER_LOGIN`, only while the install record says `applying`, `applied` or `restoring`) checks the install through the
engine as before and prints its chat line; **then, only if that note is set, it opens the wizard on the result** (the compact dialog)
and the wizard uses the note up. A reload the player made themselves gets the chat line only, and the wizard stays closed until it
is asked for. A leftover note with nothing waiting opens nothing. A reload whose call was refused takes its note back. Verification
itself is `LY.Continue`: read only. An install made from the first-install setup is followed by `Onboarding.lua` too: it is `done`
only once that check says verified (or the player kept it), and an unfinished one reopens on its result (`docs/onboarding.md`). A
reload alone never marks onboarding complete.

## Applying and finishing

This is the contract for the end of the wizard (the engine's guarantees are `architecture.md` §8; this is what the player is asked and shown).
Three levels of information are kept apart: the **Review** (the choices and the meaningful changes, with **View changes**), the
**question** (consent and the most consequential effects, nothing more) and the **technical detail** (counts, the steps, what was
checked: **Details** on the result, and the review's own sections).

### The question

`Model.Confirmation()` builds it from the approved plan and its review (never from the adapters' own plan text; `Model.ConfirmText()`
formats the same thing for the game's dialog): `{ title, intro, rows, warnings, reload, accept, key }`.

> **Apply Compact Adventure?**
> Your interface will reload to finish setup.
> - Your current setup will be backed up, so you can put it back.
> - EllesmereUI layout changes apply to every character on this account.
> - Your key bindings, action bars and other profiles are left as they are.

Buttons: **Apply & Reload**, **Cancel**, **View details** (back to the review with **View changes** open; nothing is applied; the
dialog's third button, `Interact.Confirm` `opts.alt`). A plan that needs no reload says "The layout is applied right away. No reload is
needed." and the button is **Apply** (the footer's label follows the plan too). An update's rows say "Your current setup will be backed
up, and you can undo this update afterwards." and, when the policy keeps the player's changes, "Your personal customizations will be
kept." A received package adds one row naming it and who sent it (shown as plain text). Normal confirmations are four to six lines.

Exceptional cases are short sentences added as `warnings` (shown as "Note:"), each with its full explanation still in the review's
details: a forced re-apply (an earlier install is set aside; Restore goes back to how things are now, not to before it; another
character's install can no longer be restored from here), a profile taken over (said to be one "this install didn't make", never as
recognised), the recommended configuration replacing the player's own changes, parts of EllesmereUI replaced whole because their
changes can't be carried over one by one, a profile that is gone so nothing can be compared, a second update replacing the copy that
the first kept (the first can no longer be undone), and a layout that doesn't fit or may overlap. A forced apply does not promise the
ordinary backup.

### Apply & Reload

Accepting the question is the player's authorisation for both the apply and the reload it announced. `Model.ApplyAndReload(key, announced)`:

1. refuses a second call while one is under way (`busy`), a stale key, combat, and everything `CanApply` refuses;
2. applies exactly the approved plan (`LY.Apply`, unchanged: snapshot first, record before the first change);
3. reloads **in the same click**, with the same `ReloadUI()` call as Reload now (it is `C_UI.Reload`; the API documentation lists no
   restriction on it), only when the question announced a reload, the engine says `applied`, the record reads back as this character's
   with a reload pending and its restore point, it is not combat, and the note for the result was written and read back.

There is no timer, countdown or deferred callback, so nothing can fire after a cancel, a failure or a later operation, and combat ending
never reloads. If the reload does not start (combat, a note that could not be saved, a record that isn't as expected, a refused call) the
apply stands, nothing is retried, and the dialog is **One more step** with the reason and the player's own **Reload now**. A failed,
partial or refused apply never reloads. While the reload is under way the dialog shows **Applying your layout...** and **Your interface will
reload shortly.** and offers nothing to press twice; there is no spinner, percentage or delay (the apply is synchronous, and the client
may reload before the text is drawn).

### The result dialog

Step 6 is a compact dialog in the wizard's window (520 wide, as tall as its content up to 600, fitted to small screens by `R.FitToScreen`;
no stepper, no footer; the same dimming behind it; Escape and the close box close it). It is one `Pages.lua` page over `Model.Result()`
and the same actions as before; **Set up again** goes back into the six steps. Only a setup that was read back as planned (or one the
player finished) is the success dialog, with the layout's picture.

| State | Heading | Sentence / note |
|---|---|---|
| checked, supported checks passed | **Your interface is ready** | the layout's name; "Your layout has been applied. Make yourself at home." When some parts could only be checked for being there: the quiet note "Some addon settings could not be fully verified." (not an error) |
| a value differs after the reload, or couldn't be read | **Setup needs attention** | "A few settings did not match after reloading." or "...couldn't be read back, so they aren't confirmed."; up to three differences named, the rest under **Details**. **Check again** finding a difference does the same, without rewriting the record |
| partly applied / the game stopped | **Setup needs attention** | "Part of the setup didn't finish: <part>." / "The game stopped before the setup finished." |
| nothing could be applied | **Setup could not be completed** | "Nothing was changed, and your setup is as it was." and the part that failed |
| reload pending (or not started) | **One more step** | "Reload your interface to finish applying <layout>."; why it did not start, when it did not |
| the check after a reload is scheduled and has not run | **Setup is still being checked** | only while it is really to come (`LayoutsLauncher.CheckPending()`) |
| restored / update undone | **Previous setup restored** / **Update undone** | "Everything the setup changed is back as it was." / "Your layout is back to how it was before the update." (an undone update is known in the session that undid it) |

Counts and breakdowns ("N settings read back by value; M EllesmereUI parts were checked only for being there"), the status, what was
changed and its scope, the revision, the check's time, what was chosen and each step are under **Details**. A step that needs the
player (reload, check, set up again, undo, restore, forget) has its button in view; **Manage layout** holds the maintenance actions of a
settled setup (check, set up again, keep this setup, keep the update, undo, restore, stop managing, forget) and, while a setup needs the
player, the ones that are not recovery (keep, keep the update, stop). An action that does not apply is not shown.

### Done, Keep and recovery

- **Done** (and Open settings, Escape, the close box) only closes the dialog. It does not call `LY.Finish` or `LY.Detach`, discards
  nothing and changes no record: the layout stays managed, and **Restore previous setup** and **Undo this update** stay offered under
  **Manage layout** until the player chooses **Keep this setup** (which asks, and says Restore and Undo end) or **Keep the update**.
- **Stop managing** and **Forget the record** are separate, confirmed, and only offered when they apply.
- Four things are kept separate: onboarding complete (the install checked out), the dialog dismissed (nothing), the installation managed
  (until Stop managing), and the restore point (until Keep this setup). The dialog opens by itself only after a reload the wizard started
  and a first-install setup still under way (bounded, `docs/onboarding.md`); a login after it was dismissed loads and opens nothing, and
  `/tui layout` brings the same dialog back, recovery included.

## Presentation

The pages are for scanning: a heading, at most one short line, and the choices or the result as the main content. Detail is behind a
labelled button, built the first time it is opened; what a player must know stays in view as a short statement.

- **One selection grammar** (`Controls.lua`, `Controls.Choice`): layouts, helper presets, size, tooltip placement, friendly nameplates, the update
  policy and the layout packages are the same card. Selected: a check in a fixed 18-unit square at the top right, a 2-unit bronze outline
  all round, a warm fill and, where there is room, the word **Selected** beside the check. Hover: a lighter 1-unit edge and a quiet wash,
  never the check or the outline. A card keeps its size when its state changes, and its title is given only the width left of the
  indicator and the word, so they cannot meet (`tests/test_layout_wizard_ui.lua` measures this on every card). The check, the outline and
  the swatches are drawn from flat textures, never from artwork. The accent swatches use the same check, an outline, and a name under each, so
  no choice is colour alone. Buttons are the same controls as before, so focus and Escape are unchanged.
- **Behind a button** (`Controls.Disclosure`, a chevron and a label): Compatibility details, Layout details, View included settings,
  View changes, Change (the update policy), Details and Manage layout (the result), Advanced. Each builds its text the first time it is
  opened and is kept; opening and closing them changes no pick and makes no frame. Their open state is the page's, kept while the window is
  built. The small **i** beside the preview's caption (`Controls.Info`) holds what the preview is and isn't.
- **Stays in view**: a blocker or a warning and its short reason (Welcome, Review); that EllesmereUI's part and tooltip placement are
  account-wide; the reload; the restore point; what isn't placed; what a result checked only for being there; a failed or partial outcome
  with its recovery actions; the nameplate limit while Standard blue is picked; "The layout's own look and places apply whichever you choose" on Helpers.
- **Presets are read, not named** (`Model.PresetCard`): a card's short sentence is the author's first sentence, unless the preset is exactly
  one of the bundled shapes (the three on-screen helpers; and navigation too), when it is the shorter wording ("Keep my current helper
  preferences.", "Useful resource and utility displays.", "On-screen helpers, plus navigation."). A preset the author changed is not given
  those. Its picture follows its shape (the journal for one that changes nothing, the bar, pin and cup for the on-screen shape, TwichUI's
  compass when it turns navigation on, TwichUI's generic icon otherwise); its details are the author's whole text, what it turns on and off,
  how many other settings it changes or resets, what it leaves alone, and that the layout's look still applies. Nothing in a card says a
  preset only turns things on.
- **Scrolling**: the page scrolls inside the window; the scroll bar is the template's own hideable one (`scrollBarHideable`, as Blizzard's
  `ScrollFrame_OnScrollRangeChanged` reads it), so it shows only while a page overflows. The footer is outside the scrolling area. At the
  standard window every page fits at its defaults except when there are more presets than fit.
- **Cost**: no new `OnUpdate`, event or timer; every frame is made once with its page; a hover is a texture wash through the shared motion
  (which respects "Reduce window motion"); no plan is worked out for a hover or an expand.

## Choices

The package declares its `choices` (data in `TwichUI_Layouts/ChoicesData.lua`, written from a package published in game;
`presets.md`); the schema is in `architecture.md` §3. Each choice names exactly what it writes, and `Package.lua` refuses anything
else. The wizard shows nothing the package doesn't declare, and assumes no number of options.

| Choice | Kind | Options (default first) | Writes | Verified after the reload by |
|---|---|---|---|---|
| `helpers`: TwichUI helpers | preset (layer "preset") | as the package says, any number. The bundled package today: **Leave them as they are** (nothing); **On-screen helpers** (`modules.classBars`, `modules.markersBar`, `modules.foodDrink` on); **Helpers and navigation** (the same, and `modules.navigation`). The wizard's cards describe each from its own settings (Presentation) | a switch-on-only preset: TwichUI switches, turned on only. An editable preset (format 6, `presets.md`): any TwichUI setting the adapter manages, set to a value (off, 0 included) or reset; never a place, an EllesmereUI setting or another choice's setting. "Leave them as they are" (`keep`) writes none of them | the TwichUI adapter, by value |
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
| Layout | the layout's **recommended** placement, at once, for this screen and size | the recommended placement |
| Review, first install | the plan's own placement (the same as the recommended one) | that placement |
| Review, update | the **final plan**: your kept minimap, chat and meter at your own rect and size, the pieces you keep at your places (sample sizes), and the caption says which of your placements it draws and which it can't (a form TwichUI can't read); with EllesmereUI kept as it is, it says so instead of claiming the layout's fit. Where the final result can't be drawn, it says "This shows the recommended layout, not your exact final result." | what Apply leaves |

The caption under every preview is one line, "Layout preview · Sample content". What a preview is and isn't (sample shapes in place of the real frames, to scale; the
real look is EllesmereUI's and TwichUI's own) is behind the small **i** beside it, not repeated on each page. A limit of the
preview that matters (what isn't applied, the update's kept placements, a fit problem) is a short statement under it.

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

Five sources exist in `../assets/` (names are the author's: `wizard_suite_emblem.png`, `wizard_classic_adventure.png`,
`wizard_personalize_screenfit.png`, `wizard_compact_adventure.png`, `Fantasy UI Icon Sheet.png`). Their contents and geometry were read from the files,
not assumed, by `tools/make_layout_wizard_art.py` (standard library only, like the other `tools/make_*.py`; `--check`
builds nothing and prints the findings; `tests/test_wizard_art.py` rebuilds and compares). Copies are kept in `assets/layout-wizard-*-source.png` (not packaged).

| Source | Found | Runtime file | How it was made |
|---|---|---|---|
| Setup emblem | 1254 × 1254, 8-bit **RGB, no alpha**: the transparency is a grey checkerboard painted into the pixels | `media/emblem.tga`, 128 × 128 | Background removed by flooding from the border through neutral light-grey pixels only (the picture is warm or dark; nothing the flood can't reach from outside is touched: 62.6% of the pixels), and the soft rim (4,226 pixels) given an alpha by unmixing it from the local checker grey. Inspected at full size on dark and light backgrounds: no halo. Then cropped to content and shrunk. |
| Classic Adventure | 1536 × 1024 RGBA, genuine transparency (about three quarters alpha 0, a soft aura kept as painted) | `media/classic.tga`, 512 × 256 | cropped to content (938 × 659) and shrunk to fit, centred |
| Personalize and Screen Fit | one 1774 × 887 RGBA sheet; the two pictures are separate runs of columns holding any alpha (126–811 and 925–1629), found by measurement | `media/personalize.tga`, `media/screenfit.tga`, 128 × 128 each | split at the clear gap; each cut to content and shrunk to fit |
| Compact Adventure | 1536 × 1024 RGBA, same kind as Classic's (a belt pouch with a scroll and a dagger) | `media/compact.tga`, 512 × 256 | built in Phase 5 with `--phase5`: cropped to content (a 226 × 252 picture centred in the 512 × 256 file, like Classic's) |
| Icon sheet | 1312 × 1199 RGBA, genuine transparency (59% alpha 0, the painted parts at alpha 249–254; no baked-in checkerboard or matte). Two rows of two pictures, found by measurement (the rows that hold alpha, then the columns in each): a closed journal with a ribbon, a resource bar with a pin and a cup, a tooltip pinned in a screen's corner, a tooltip beside a cursor | `media/keep.tga`, `media/helpers.tga`, `media/tipfixed.tga`, `media/tipcursor.tga`, 128 × 128 each | each cell cut to its content and shrunk to fit with a 4 px margin (the longer side of every picture fills the same share of the file, so the four look the same size); painted pixels at alpha 240 or more are made fully opaque first (the interiors sit at 249–254), the soft rim is kept; premultiplied resampling and colour carried 2 px into the clear pixels leave no halo. Inspected on dark and light backgrounds and at 44 px: the journal, the bar, pin and cup and both tooltip diagrams read |

The icon sheet supplies supporting illustrations only: the selection check, the outline, the swatches, the "Aa" samples and the nameplate samples are drawn in code. Navigation's preset reuses TwichUI's existing compass icon (`R.Icons` `navigation`); a preset with no artwork of its own gets `qualityOfLife`.

All TGAs are uncompressed 32-bit, bottom-left origin, 8 alpha bits (the format of every other `media/` file), power-of-two
sizes, with colour carried 2 px into the clear pixels so bilinear filtering shows no dark matte. Total shipped: about 1.5 MB (Compact's picture is 524 KB).
Nothing was recoloured, sharpened or generated; no replacement was made for anything missing.

Runtime: every square picture is registered in the icon registry (`Art.lua` adds `layoutEmblem`, `layoutPersonalize`,
`layoutScreenFit`, `layoutKeep`, `layoutHelpers`, `layoutTipFixed` and `layoutTipCursor` to `R.Icons.list`) and drawn with `R.Icons.Apply`, so a file the game refuses falls back to
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
  `layoutwizard.frames` (does not grow when reopened; it counts the dimming's frame and texture), `layoutwizard.overlay.events` (3 while the preview is shown, 0
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
`tests/test_layout_wizard_ui.lua` (with `tests/wizard_probe.lua`, which works out where each stand-in frame and text ends up from its
anchors) measures the presentation on the real page builders: the viewport, a card's title against its indicator and hint, selected, hover
and unselected states, both layouts in view, a third layout, six presets with custom ones and the generic icon, no switch-on-only claim, every
personalize choice reachable and changing nothing, the review's receipt (fresh, update, nothing to do, blocked) with Force under Advanced,
each result outcome's heading and the actions kept in view, the stepper's checks, the footer's corner, the footer outside the scrolling
area, reopening making nothing, and the four new pictures (format, real transparency, nothing touching the file's edge, registered).
`tests/test_wizard_art.py` rebuilds the pictures from the sources and compares them with the shipped files. The existing tests were
changed only where text moved behind a button (they open the disclosure first). Mutations made and reverted, each failing a test: a title
allowed under the indicator, a selected card without its outline, the second layout card pushed out of the viewport, a partial install
wearing the success heading.
`tests/test_layout_complete.lua` covers the end of the flow ("Applying and finishing"): the question's content and length (no profile names, counts or
adapter text), its exceptional warnings, Cancel, View details and a stale key, the reload (once, after the record, snapshot and note are
written; never after a failed, partial, refused, unannounced or no-reload apply; not in combat, nor when combat ends; not when the note can't be
saved; a refused call tried once and its note taken back; no timer; no second apply), each result state's heading, Done leaving management and
recovery alone, no reopening at later logins, Keep this setup as the explicit act, repeated use making no frames, and small screens.
`test_layout_wizard_ui.lua` §7b measures the compact dialog (inside the window, no overlapping buttons, no narrow columns, its height).
Mutations made by hand and reverted, each failing a test: the reload not gated on the question announcing it; no combat check before the
reload; the note not read back; no duplicate guard; Done calling Keep; a mismatch wearing the success heading; presence-only checks turned into
an error.
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
   Troubleshooting buttons open it; no minimap or broker button exists; a new character on a set-up account gets no prompt
   (a new installation's first-install offer is `docs/onboarding.md`'s checklist).
2. The pictures draw (emblem, Classic, Compact, the journal, the bar, pin and cup, both tooltip diagrams) with no green or white square, with
   transparent backgrounds, at 1080p, 1440p and an ultrawide.
3. Welcome: the EllesmereUI line reads right (version, Forever build); with EllesmereUI disabled, Get started is blocked with
   the reason; in combat, the line says so.
4. Each step; Back; the stepper; Close at each step changes nothing (compare `/tui` settings and EllesmereUI's profile list
   before and after).
5. Picks: each accent recolours the preview's outlines (Layout and Review steps); Larger enlarges chat, the meter and the minimap boxes; every
   card selects with a check, an outline and "Selected" where it fits.
6. Review matches what the apply then does: profile names, the account-wide note, the reload, "Left alone", "Not placed".
7. Apply & Reload: the question is short (the layout, the reload, the backup, the account-wide part); Cancel and Escape change nothing and
   reload nothing; View details returns to the review with the changes open.
8. Accept: the interface reloads by itself, once, with no second question; after it the compact dialog opens on **Your interface is ready**
   (verified). A reload made with `/reload` instead of the wizard's prints the chat line and leaves the wizard closed.
9. The accent shows in EllesmereUI (its accent swatch reads the picked colour); the picked helpers are on in
   `/tui options`; the size you picked is the size you see; positions match the preview on your screen (screenshots).
10. Restore previous setup: the question lists what it does; after the reload the wizard says "Restored", EllesmereUI is
    back on your profile, the install's profiles are gone, your TwichUI profile is as it was.
11. Set up again with another accent: applies, reloads, verifies; Restore goes back to before the first install.
12. In combat: Apply, Restore and Reload now are refused with a reason; they work again after combat. Pulling a mob between accepting the
    question and the reload (hard to time; `/run` a combat flag is not possible) is covered offline only: **One more step**, no reload when
    combat ends.
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

## Presentation manual checks (none done; on WoW: Forever)

24. Each page at the standard window, 1080p and 1440p: Welcome, Layout (both cards whole), Helpers, Personalize and Review need no scrolling at their
    defaults; nothing is clipped; no scroll bar is visible until a page overflows (add presets or raise the UI's font size to see one).
25. Selected and hover on a layout card, a helper card, a size card, a tooltip card, a nameplate card and an accent swatch: the check, the
    outline and "Selected" are clear on the real fonts; a title never touches the check; hover is quieter than selected and distinct from it.
26. The pixel-drawn check and the stepper's small check read at your UI scale (the 2-unit squares are not blurred or uneven); the heavy bar on the
    current step is visible; a step not reached looks quiet.
27. The four new pictures at their drawn sizes (56 for presets, 88 × 70 for tooltips, 128 × 64 beside a layout): readable, no halo on the dark
    card, the same optical size.
28. "Aa" for Larger is plainly larger than Standard's; the class swatch shows the class icon; the nameplate samples' class colours differ from
    each other and Standard blue's are one colour.
29. Welcome in a normal session, with EllesmereUI missing (Setup blocked, the reason at once), and on a first installation (Skip setup, the
    EllesmereUI line, Do this later).
30. Review for a fresh install, an update (Change opens the three ways and every setting), nothing to do (You're already up to date, Done,
    Advanced > Force re-apply still asks) and a blocked account (Advanced open, Blocked: in words).
31. Result after a real reload: the small dialog, Your interface is ready with the layout, Done, Open settings; Details and Manage layout open and
    close and the dialog grows and shrinks with them; a partial or mismatched install (an edited saved variable) shows Setup needs attention
    with Restore in view and no success picture. Done closes it, and the next `/tui layout` shows the same dialog with Restore still under
    Manage layout. The dimming goes with it; Escape does the same.
33. Does `ReloadUI()` work from the question's accept click in the client (it does from the Reload now click)? If a client refuses it, the
    dialog says One more step and Reload now works: report it.
32. The window opened and closed ten times with every disclosure open in a `/tui perf` capture: `layoutwizard.frames` and `.events` stay flat.
