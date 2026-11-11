# Reminders style upgrade

The approved upgrade covers the compact editor, interactive preview, illustrated catalog and When companion end to end
on `feature/style`. Feature behavior and saved data are described in [reminders.md](reminders.md). Follow `AGENTS.md`,
`CLAUDE.md` and the applicable sections of `docs/dev-rules.md`.

The complete revision uses the supplied requirements handoff and [original mockups](reminders-revision/).
See the [requirement and visual verification record](reminders-revision/implementation.md) for the baseline, final captures,
remaining visual differences and real-client checks.

## Usability and condition artwork addendum (2026-11-11)

Final Advanced polish removes the zero-height Position row that overlapped Opacity. Position now has its own row
inside secondary placement options; primary/nested controls align with consistent spacing and right padding.
Scoped fixed-header layout clamps stale scroll offsets after disclosure collapse. Six final renders, comparison crops,
103 handler/state checks per pose, 187/0 unit results and 56/56 construction are recorded in the revision record.
Real-client input/font checks remain pending; current materials and functionality are retained.

Place on screen now appears in the selected-reminder header beside Live preview. It is the original placement control,
removed from Advanced's layout; both primary and companion entries use the existing private Finish/Cancel transaction.
Reset adopts the existing destructive art family only on scoped material pages, with confirmation and reset scope intact.
Condition artwork now distinguishes a broad enchanted blade, crossed combat swords and a reused painted horse head.
One resolver supplies palette/cards/summaries/diagnostics/drag ghosts, separately from reminder and template artwork.
Three bounded built-in calls include one targeted sword refinement; source/prompts, alpha checks, all-condition audit,
actual simulator captures and verification are in the [revision record](reminders-revision/implementation.md).

## Interaction polish (2026-11-11)

The current pass preserves the quiet leather and painted component family. Reminders and Known ammunition now own
fixed title/tab chrome above a real body viewport; other pages retain their original scroll geometry. Scoped scroll
rails and popup sliders share painted art, with cancelable 120 ms / 24-unit wheel movement and reduced-motion support.
Reminder rows fill their well and offer canonical Duplicate/Delete actions through compact menus and confirmation.
Popup/help placement accounts for nested scroll transforms as well as effective scale.

Placement is an explicit private coordinate transaction with a small Finish/Cancel toolbar and hidden Settings;
stale releases, combat, deletion and concurrent position changes are guarded. Four session-only preview backgrounds,
painted hover/navigation emphasis, font-name previews, illustrated complex-rule summaries, readable diagnostic result
rows and separate simulation/technical disclosures are integrated. The focused builder drops its redundant Edit
conditions button and uses original parchment behind its isolated appearance renderer.

Two built-in image-generation calls produced landscape and parchment sources. Runtime files and exact prompts,
comparison crops, final captures, regression results and client-only acceptance are in the
[existing revision record](reminders-revision/implementation.md). No new material overhaul, saved schema or wider rollout.

## Earlier implementation status (2026-11-11)

The art-backed pass uses `docs/reminders-revision/SETTINGS_HOME.png` as the shared shell/selection reference. Three
built-in image-generation calls produced standalone frame, button and selection sources; `tools/make_craft_art.py`
prepares 28 runtime textures. `SettingsCraft` supplies opt-in fixed-corner frames and painted control states, integrated
through Material into the editor, preview, builder and catalog. Quiet large-area materials, hinge and existing artwork
are retained. Header/search proportions improve only in the pilot context, including stable geometry during search;
other pages restore their previous shell. The reminder list now aligns with the primary editing stack.

Native component proofs preceded integration; repeated actual captures corrected label clipping, history alignment,
chip curvature and the dashed target. See the revision record for exact screenshots, comparisons, tests and remaining
client acceptance. No Home content or global navigation-row migration was implemented.

The component-fidelity pass retains those materials and adds hollow rounded bronze rims over the existing fills,
painted rails and hinge. Appearance groups the larger artwork/Choose area and integrates text color with Size.
Wide editors give the reminder list a bounded share of the extra width. Preview sizing controls share a recessed well;
visibility has its own icon. Cards, grip dots, disclosures and footer actions have locally refined alignment and relief.
The reference/before/after component crops and outstanding visual differences are in the revision record.

The material foundation uses scoped fine leather and baked rounded faces, distinct header/editor/card/control
roles, mixed-case Spectral headings and readable sans controls. Reminders alone opts into the new Settings shell
materials; leaving the page restores existing materials. The hinge is retained, condition artwork is separated from
chosen reminder artwork, and the preview follows a taller editor. Source/inspection artifacts stay out of packages.

The P0 spontaneous-preview regression is corrected by an authoritative active-editor visibility predicate. Refreshing
content cannot show a hidden companion; close/navigation invalidate queued refreshes. Live preview is a session toggle,
separate from the explicit temporary world preview. Tests repeat closed refreshes and gameplay/configuration events.
Client confirmation remains required. See the revision record for comparisons, exact checks and limitations.

The UX refinement moves the master switch into the page header, gives Appearance an artwork tile, and consolidates
Advanced and Diagnostics. Flat All rules open with directly editable trigger and restriction cards. Positive Dungeon/Raid alternatives have lossless chip editing. Other grouped, Any and
unsupported rules open Advanced logic with their stored tree intact. The revision record compares the supplied client
captures, original mockups, baseline and final simulator renders.

- `TwichUI_Settings/pages/Reminders.lua` and `RemindersEditor.lua` put the list beside the editor, use a compact feature
  card with pill switches, and put placement, effects and test diagnostics behind disclosures. Long row names and rules are available in
  tooltips. `Material.lua` reuses the style-v2 leather, rounded slices and bronze edge for the Reminders controls and
  companions. The compact feature card is opt-in in `Cards.lua` and `Window.lua`.
- `RemindersPreview.lua` attaches hit targets to the existing renderer's art and text regions. They scroll to and
  highlight the matching field. The preview remains usable for disabled reminders, offers Actual size and Fit controls,
  and keeps the explicit Show on screen action. At narrow widths, a click to edit minimizes an overlaid
  preview so the field can be reached.
- `RemindersCatalog.lua` shows five illustrated cards and a Custom row, with search and category filtering. Creation still uses `P.Create` and `RM.Create`.
  Missing equipment or item needs an item for the condition and display, and the existing validation blocks enabling an
  unfinished draft. The catalog reports refusals and stays open. New enchant drafts use the bundled oil artwork.
- `RemindersDesigner.lua` keeps type-specific controls on basic cards and uses a dedicated When workspace.
  `RemindersBuilderRail.lua` supplies the reminder list, selection, summary and isolated sample beside the rule panel.
  Both frames reuse the existing illustrated bronze rails and neutral espresso material. Location alternatives use chips.
  Other grouped or Any rules retain their Advanced logic presentation.
  The When companion has a recessed search, divided palette, bronze scrollbar, contextual actions, a For dropdown,
  illustrated drag ghost and dashed restriction target. Its summary, current visibility and situation testing have
  separate roles, with controlled bottom disclosures and a persistent action footer. `Config.lua` keeps conditions and targeting in a private draft with Undo/Redo and validates a single
  Save. Cancel discards the draft and restores the preview.
- `PV.Place` positions the preview and catalog. The When workspace temporarily covers Settings and fits the complete
  paired frames to the screen without writing the saved placement. `PV.Place` tries either side for the preview and catalog, and can temporarily shift the settings window to fit
  both panels, and centers a companion when side-by-side placement is too narrow. Leaving the page closes the
  companions and world preview and restores the temporarily shifted anchor. The settings addon still loads on demand.
  Its Reminders controls are built when the page or catalog is first used and reused on redraw.

The simulator screenshots show the two-column editor, attached preview, two-column illustrated catalog and the
When palette beside the rule cards. The supported item template adds a third catalog row. At the default settings
height, Advanced and Duplicate/Delete are below the fold. The simulator substitutes fonts. Pointer delivery, typography,
scaling, Escape order and reload persistence still need a real-client pass.

## Approved visual targets

Stored as documentation references (not runtime artwork; `docs` is excluded from the package by `.pkgmeta`), original image
content unchanged, named as supplied:

| Path | Role |
|---|---|
| `docs/reminders-revision/SETTINGS_HOME.png` | Primary shared-shell, frame, header, material and premium selection reference; no Home content implementation. |
| `docs/reminders-revision/REMINDERS_PREVIEW.PNG` | Compact settings window, reminder list, Appearance, When, Sound, Advanced and attached preview with Actual size and Fit. |
| `docs/reminders-revision/REMINDERS_TEMPLATE_CATALOG.jpeg` | Illustrated template cards with search, categories, Use template actions and a Custom reminder row. |
| `docs/reminders-revision/REMINDERS_WHEN_BUILDER.png` | Condition palette, rule cards, targeting, live feedback, insertion feedback and edit actions. |

The complete revision authorizes search, category filtering, preview sizing and rule drag-and-drop.
The When editor applies conditions and targeting together on Save. Global navigation, faction chrome,
profile workflow and supported condition types continue to follow the addon contracts.

## A. Before the upgrade (historical source inspection, commit `2e0c5fe5`)

Everything is in the load-on-demand `TwichUI_Settings/` addon (load order: `TwichUI_Settings/TwichUI_Settings.toc`) except the
reminder model and drawing, which are core.

| What | Where | Notes |
|---|---|---|
| Page and list | `TwichUI_Settings/pages/Reminders.lua` | `P.Create(kind)` (l.94), `P.Select`, `P.QueueRefresh`, `P.Refresh` (l.405, draws the preview unless the catalog is shown), `Build` (l.313: list card, name/switch/Duplicate/Delete card, then `R.RemindersEditor.Build`). Hides catalog, preview and designer when the page hides (l.457-459). "New reminder" button (l.326) calls `R.RemindersCatalog.Toggle()`. |
| Editor | `pages/RemindersEditor.lua` | `Ed.Build` (l.661) returns five card sections: Show, When, Placement, Sound, Test. Local `Section(parent, icon, title, blurb)` (l.68) makes each card with a one-line **blurb** (the introductory prose to trim). |
| When designer | `pages/RemindersDesigner.lua` (1148 lines), words in `pages/RemindersPlain.lua` | `Dz.Build` (l.151) is the "When" section (called from `RemindersEditor.lua` `WhenSection`). Already built and working: bounded groups, condition cards, one editor on a copy, a picker, "Why would it show?". Uses the same `Section` card family. It is an inline section, **not** a companion frame. |
| Catalog | `pages/RemindersCatalog.lua` (144 lines, new) | `R.RemindersCatalog`: `C.Toggle`, `C.Hide`, `C.Shown`, `C.Frame`, `C.Say`. 420 px frame, two-column cards (`CARD_W`, `CARD_H` 132, `THUMB` 40) over `RM().TEMPLATES` (all but `custom`), then a "Custom reminder" button. `Use(kind)` calls `P.Create`; success hides, a refusal is said in `f.say` and the catalog stays open. Esc via `UISpecialFrames`; also closes with the settings window (`R.OnSettingsClosed`). |
| Preview | `pages/RemindersPreview.lua` (126 lines, new) | `R.RemindersPreview`: `PV.Show(view, hooks)`, `PV.Hide`, `PV.Shown`, `PV.Parts`, `PV.Place(frame)`. 360 px frame; draws with `D.NewSurface` / `D.DrawSurface` (core `!!!TwichUI/reminders/Display.lua`, the reminder's own layout code) inside a well, a PREVIEW tag, a caption, and the explicit **Show on screen** / **Hide preview** button (`D.PreviewStart/Stop/PreviewId`). Nothing is made clickable. |
| Companion place | `PV.Place` (Preview l.21-41), `R.SettingsAnchor()` (`!!!TwichUI/SettingsLauncher.lua` l.79) | Beside the window on its right (`TOPLEFT` of anchor `TOPRIGHT`, 8, -48), flipped to the left when it would leave the screen, centred when the settings are not up. The catalog calls the same `PV.Place`. |
| Lifecycle between them | `C.Toggle` hides the preview and places the catalog; `C.Hide` calls `P.QueueRefresh`, which redraws the preview for the selection. `Reminders.lua` `P.Refresh` skips the preview while `C.Shown()`. One companion at a time, by this convention only (no shared owner object). |
| Creation | `!!!TwichUI/reminders/Config.lua`: `RM.TEMPLATES` (l.550: `{kind, name, long description, short line}`), `RM.TemplateDisplay(kind)`, `RM.Create(kind)` (l.616), `RM.Art`, `RM.ArtTexture` | The one checked path: fresh copy, own id, turned off, limit and newer-profile refusals. The catalog goes through `P.Create`, never around it. Do not change. |
| Artwork | `!!!TwichUI/media/reminders/` (`shield`, `ammo`, `wellfed`, `designer`, each with `-small`), `R.Icons` | Templates `enchant`, `item` and `custom` have no artwork; the catalog falls back to an icon (`Picture`, `RemindersCatalog.lua` l.26). "Distinct illustrated cards" therefore needs new art for at least those three, or a deliberate choice to use icons. |

### Shared styling components that exist

Two reusable treatments existed at this baseline. The dedicated When workspace now combines the illustrated outer frame
with the opt-in leather interiors and controls described below.

1. **Settings "style v2"** (leather and bronze), `TwichUI_Settings/Material.lua` (`R.SettingsMaterial`, built in commit 29819a33).
   Header comment lists the API: `M.Window`, `M.Band`, `M.Nav`, `M.NavItem`, `M.Header`, `M.Well`, `M.Slice(host, "recess"|"raised")`,
   `M.Card(frame, lines)`, `M.SelectedRow`, `M.Field(editBox)`, `M.Face(button, "secondary"|"primary")` (danger stays rust).
   Tunable levels in `M.LEVEL`. Assets: `!!!TwichUI/media/style-v2/` (`dark`, `warm`, `window-edge`, `control-edge`,
   `round-raised`, `round-recess`, all `.tga`), built by `tools/make_style_v2_art.py` from `../assets/style-v2-assets.png`.
   Already used by the page's list/head cards and the editor's `Section` cards (`Mat().Card`, `Mat().Face`, `Mat().Field`).
2. **Framed look from the approved guild-bank panel**, `!!!TwichUI/FrameLook.lua` (`R.FrameLook`: `F.Shell`, `F.Button`,
   `F.Close`, `F.Toggle`, `F.Style`), with the painted frame in `!!!TwichUI/media/guildbank/frame-{corner-*,edge-*}.tga`.
   This is what the **catalog and preview companion frames use today** (`F.Shell(f, {below=true, follow=true})`, `F.Close`).
   The cards and buttons inside them use `G.Button`/`G.Text`/`G.Well` plain, **not** `Material`, so the companions do not
   yet look like the window beside them.

Widgets and type: `TwichUI_Settings/Widgets.lua` (`R.SettingsWidgets`: `Wg.Button/Dropdown/Slider/Swatch/Scroll/...`) and the
`G.Text(parent, "heading"|"body"|"small"|"meta")`, `G.Panel`, `G.Well`, `G.Tag`, `G.pal` helpers it/`Window.lua` provide.
Kit (`Kit.lua`) is the page/registration layer, not needed for a visual pass.

### Reusable versus not

- Reusable now: everything in `Material.lua`, `FrameLook.lua`, the guild-bank frame art, `media/reminders/*`, `R.Icons`.
- `Material.lua` was written for the settings window and its pages ("THIS window only"); applying it to the companion frames
  is new use, so check each function against a frame that is a child of `UIParent` at `HIGH` strata (it assumes nothing about
  the parent, but it was not written for that).
- The approved renders are targets, not assets: nothing is cut from them. The runtime paintings that existed at the start are listed in the table above.

### Artwork produced and integrated

The scope permits producing missing standalone assets while reusing suitable existing art. One built-in generation call
produced the leather gauntlet for the item template. The earlier capability-test oil vial was reused for enchant, and the
existing unlettered Golden-Bound Parchment Scroll was reused for Custom. The shield, arrows and plate paintings remain in
use. The PNG sources are `assets/reminder-art-{enchant,item,custom}-source.png`, and the runtime TGAs are under
`!!!TwichUI/media/reminders/`. `assets/` and the reference images under `docs/` are excluded by `.pkgmeta`.

All three source PNGs have real alpha. The runtime artwork was screenshot-reviewed at 48 and 76 pixels on espresso and
lighter stone backgrounds. The catalog has no placeholder artwork. An unset item in a draft still has the existing
question-mark preview until the player chooses an item. New asset work uses the built-in route with bounded authorization.
Stop after two unsuccessful substantive attempts at the same asset and record the gap. An API fallback or credit purchase
requires separate authorization.

### Preparation blockers: none

The three approved renders are stored (above). Nothing blocks starting milestone 1.

### Implementation dependencies (belong to the milestones, not to preparation)

1. **Preview click handling (milestone 2).** The preview surface (`D.NewSurface`, `Display.lua` l.607) is click-through
   (`EnableMouse(false)`); `PV.Show` draws it as one block. Which parts are configurable (picture or icon, words, size, place)
   and which editor control each maps to is not recorded; derive it from `D.DrawSurface`'s parts, with the render
   ("Click an element to edit", "Edit icon") as the guide. Only the preview copy in the companion may take clicks, never
   the world frame.
2. **Scroll and highlight support (milestone 2).** `Window.lua` has a local `ScrollTo(offset)` (l.867) and a scroll-into-view
   for search results (l.1168-1182), neither exported to pages. A small exported scroll-to-frame (or an editor-level
   `Ed.Reveal(name)`) and a transient highlight are needed. Section frames are positioned by `Reminders.lua` layout
   (`P.Refresh`), so offsets must be read after layout.
3. **Companion ownership is convention (milestones 2-4).** Catalog and preview hide each other by direct calls. A
   companion When editor, if built, joins this convention (or a tiny shared slot); see D4.
4. Catalog and preview frames are fixed-size (420 and 360 wide) and place only at `SettingsAnchor` right or left; narrow
   screens and large scales are unverified (docs/reminders.md checks 27-28).

### Starting point for the condition designer

The inline designer already had pooled controls, a searchable condition picker, copy-on-edit, Undo and the explanation
view. The upgrade reuses those pieces inside the companion and keeps their existing save and validation behavior.

## B. Verification evidence

- **Unit-tested:** focused Reminders settings, designer, groups and enchant/sound tests and the settings window and size
  tests passed. The settings contract test also passed. Preview click checks compare the stored draft and revision and
  count calls to the display setter and condition inspection. `./tests/run.sh` finished with **187 passed, 0 failed**.
  `luac5.1 -p` passed on every edited or new Lua file.
- **Simulator construction-tested:** `SIMLAB_PAGE=reminders SIMLAB_TITLE=Reminders bash tools/simlab/smoke.sh`
  opened Reminders and constructed all 56 settings pages without a captured Lua error.
- **Simulator interaction-tested:** `bash tools/simlab/reminders.sh` passed 20 editor, 20 catalog, 21 When and 22 narrow
  handler/state checks. The scenario opens the real settings page, changes the companion through its controls, exercises
  an invalid item draft and verifies a disabled on-screen preview is removed on close.
- **Screenshot-reviewed:** `../wow-ui-sim-lab/artifacts/reminders-20261110-154138/{editor,catalog,when,narrow}.png`.
  The before-state capture is `../wow-ui-sim-lab/artifacts/smoke-20261110-150530/settings.png`.
- **Not tested in the real client:** visual acceptance, pointer interactions, UI scale, Escape order, combat cleanup and
  reload. The simulator's font substitution and handler-level interaction limit what its captures prove.

## C. Approved requirements

- Reminders is the **prototype** for the shared polished settings style. It is not authorization to restyle other pages or
  windows. `Material.lua` stays settings-window-only; do not edit `Look.lua`/`FrameLook.lua` for other consumers.
- Look: warm espresso/walnut leather, chestnut surfaces, aged bronze, ivory text, selective antique gold, restrained depth,
  rounded controls, readable text. Targets are the three approved renders listed above.
- Compact editor: cut redundant introductory prose (the `Section` blurbs, the catalog/preview subtitles where they repeat
  the title), keep advanced diagnostics (Test, "Why would it show?", Try a situation) secondary.
- The preview stays usable beside the editor while editing.
- Clicking a configurable preview element **navigates to and highlights** the matching setting and **changes no reminder
  configuration** (navigation only; no write path).
- The catalog uses distinct illustrated cards in a consistent layout.
- Keep independent, initially disabled template creation (`P.Create` -> `RM.Create`). Keep validation, unknown-condition
  semantics (three answers, groups), profile compatibility and saved data unchanged. No schema change.
- Preview, catalog and the When editor share the companion position and never show as competing frames.
- Search and category filters are in scope for both the catalog and the condition palette.
- The When editor adapts the existing condition designer to the companion layout and preserves its pooled controls,
  All/Any grouping and validation. Drag-and-drop uses the existing tree. A validated Save applies the draft, Cancel
  discards it, and Undo and Redo apply to draft changes.

## D. Implementation checkpoints

1. **Shared styling foundation and compact editor.** Apply `Material` (cards, fields, button faces) consistently across the
   Reminders page and `Section` cards; shorten/remove `Section` blurbs and duplicate prose in `Reminders.lua`/`RemindersEditor.lua`;
   fold Test and "Why would it show?" behind secondary treatment (collapsed or last, no behavior change). Smallest set of
   shared helpers only if two files need the same function (e.g. a companion-frame dressing function in `Material.lua` or a
   local file): no new framework.
   Acceptance: preserve reminder behavior and validation (`test_reminders_settings.lua`, `test_reminders_designer.lua`,
   `test_settings_window*.lua`, `./tests/run.sh` pass); no new frames per redraw; blurbs gone or shortened with the tests that
   read them updated deliberately; `simlab/smoke.sh` constructs the page; screenshot reviewed structurally; real-client check
   of readability.
2. **Styled interactive preview.** Dress `RemindersPreview.lua` in the companion look; make configurable parts of the preview
   copy clickable (needs the `D.DrawSurface` part map, dependency 1) and add the reveal/highlight helper (dependency 2). Reveal
   goes through the editor's section frames; highlight is a transient texture and writes nothing.
   Acceptance: clicking a part reveals the right control and writes no saved value (unit test asserting `RM.Get` unchanged
   and no `Set*` call); preview still never plays sound or reads a condition; Show on screen unchanged; `PV` still makes its
   frame once and cleans up when settings close or the player leaves the page. Real-client checks cover click targets, scroll and highlight.
3. **Styled template catalog.** Cards with consistent layout and artwork per template (supply or decide art for `enchant`,
   `item`, `custom`, see F), same companion look as the preview, `Use template` primary, close box. Keep `Use` -> `P.Create`.
   Acceptance: the existing section 10 tests pass (independent copies and ids, starts off, refusals keep it open, cancel
   makes nothing); text fits at the real card size (screenshot, then real client); placement is the shared `PV.Place`.
4. **When editor and companion sharing.** Restyle the existing designer and use the shared companion placement.
   The page keeps a rule summary and opens the editor through Edit conditions.
   Acceptance: `test_reminders_designer.lua`, `test_reminders_groups.lua` unchanged in behavior; unknown-condition cards,
   Edit/Cancel copy semantics intact.

Order is by dependency: milestone 1 supplies the style the next two use; 2 before 3 because the placement/handoff rules the
catalog also follows are exercised first by the preview. Preview sizing, catalog filtering and pointer operations are
verified with their corresponding surfaces.

## E. Verification map

Run from the repository root; the test harness also needs `lua5.1` + `bit`.

| Kind | Command | What it proves |
|---|---|---|
| Syntax | `luac5.1 -p '<file>'` after each Lua edit | parses |
| Focused behavior (unit) | `(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_reminders_settings.lua)`; same for `test_reminders_designer.lua`, `test_reminders_groups.lua`, `test_settings_window.lua`, `test_settings_window_size.lua`, `test_reminders.lua` | creation path, selection, catalog (section 10), preview handoff (section 11), settings window sizing |
| Full suite | `./tests/run.sh` | required for code changes by `CLAUDE.md` |
| Simulator construction | `bash tools/simlab/smoke.sh` (all pages construct; run with bash, not zsh) | the page and companions build without a Lua error |
| Simulator interaction | `bash tools/simlab/reminders.sh` | Reminders companion transitions, preview navigation, item validation and close cleanup through handlers |
| Screenshot review | the simulator's page screenshot (`docs/simulator-lab.md`) | structure only (columns, fit); fonts fall back; **not** visual validation |
| Real client | `docs/reminders.md` in-game checklist, items 27-28 plus new items you add for the style | appearance, placement, scaling, Esc, click targets, taint-free behavior |

The simulator exercises companion handlers and produces structural screenshots. Real-client typography, pointer input,
combat and reload persistence need client checks. Simulator infrastructure is outside this upgrade.

## F. Real-client acceptance

1. Open a disabled weapon enchant draft. Check the list, rounded controls, oil artwork and text at normal and higher UI
   scales. Click the artwork and words and confirm each field scrolls into view and gets a short highlight.
2. Use Show on screen and Hide preview. Check that the draft remains off and silent, then close settings or leave the
   Reminders page and confirm the sample disappears. Check that combat ends an explicit world preview.
3. Open the catalog, check the artwork and long labels, and close it with Escape. Confirm selection returns. Create two
   copies and check they start off. Try enabling the equipment/item draft before and after supplying required inputs.
4. Open When at normal and constrained widths. Check scrollbar and close/back access, edit and cancel a nested condition,
   and switch between companions. Verify Escape with a dropdown open, then with a dirty draft. Save a different rule
   and targeting together and verify them after `/reload`. Reopen settings after moving the window.

## Codex implementation prompt (copy and paste)

```
Read AGENTS.md, the applicable CLAUDE.md and dev-rules sections, and this brief. Confirm the branch is feature/style
and report if it differs. Preserve existing work and implement or finish the approved Reminders style upgrade end to end.
Use the three supplied renders as visual targets. Treat the checkpoints as internal sequencing without approval gates.

Deliver the compact editor, interactive preview, illustrated catalog and When companion. Reuse the existing renderer,
validated template creation path and condition designer. Preserve disabled defaults, independent copies, input validation,
unknown states, All/Any grouping, saved configuration and world-preview cleanup. Make preview navigation write-free.
Implement Actual size and Fit, catalog search and categories, and pointer drag-and-drop for existing rule nodes and
palette entries. Preserve menu alternatives and the When draft with Save, Cancel, Undo and Redo. Keep companion placement usable at
supported sizes, including a narrow-width fallback. Scope visual changes to the Reminders surfaces.

Reuse suitable artwork and style-v2 materials. Generate only missing standalone assets with the authorized built-in tool.
Verify alpha, actual-size readability and source/runtime packaging separation. Keep text in code. Do not purchase credits,
use a separately billed API or change credentials. Stop after two unsuccessful substantive attempts at one asset or blocker
and continue independent work. Preserve all repo and simulator isolation rules. Do not install dependencies, deploy, commit,
push, publish, change TOC metadata or touch the live install and saved variables.

Run Lua 5.1 syntax checks, focused tests, the full suite, Reminders simulator interaction and construction smoke.
Inspect the actual screenshots and compare each surface with its approved reference. Update this brief and backlog with
verified progress and remaining gaps. Report evidence levels, screenshot paths, artwork and the real-client checklist.
```
