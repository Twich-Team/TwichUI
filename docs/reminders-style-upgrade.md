# Reminders style upgrade: brief for the next implementation session

Read this first. It is a starting point, not a design to re-derive: the functional work (template catalog, attached
preview) is built and must be kept. What remains is **styling, a compact editor and an interactive preview**. Feature
behavior, saved data and tests are described in [reminders.md](reminders.md); the rule set is in `CLAUDE.md` (summarized
in `AGENTS.md`). Nothing here has been implemented as styling yet.

Written 2026-11-10, from reading the code. No runtime code was changed to write it. Rechecked 2026-11-10 (second pass):
branch `feature/style`, HEAD `2e0c5fe5` "Create templates frame and preview window", which is also the last commit touching
`RemindersCatalog.lua` and `RemindersPreview.lua`; the tree held no uncommitted Reminders changes. Re-run `git log -1 --
TwichUI_Settings/pages/RemindersCatalog.lua` before starting; do not assume these still hold.

## Approved visual targets (the three renders)

Stored as documentation references (not runtime artwork; `docs` is excluded from the package by `.pkgmeta`), original image
content unchanged, named as supplied:

| Path | Role |
|---|---|
| `docs/reminders-style-references/REMINDERS_PREVIEW.png` (1586x992) | Compact settings window with the Reminders page (list, name and switch, Appearance, When summary, Sound, collapsed Advanced, Duplicate/Delete) and the attached **Live preview** panel (preview well, "Click an element to edit", an element's **Edit icon** chip, Actual size / Fit, Visibility, Preview toggle). Target for milestones 1 and 2. |
| `docs/reminders-style-references/REMINDERS_TEMPLATE_CATALOG.jpg` (1586x992) | Settings window with Reminders and the **Create a reminder** catalog beside it: illustrated cards (Weapon enchant, Well Fed, Missing shield, Ammunition) with name, one line and **Use template**, a **Custom reminder** row, and the "Creates your own editable copy. Starts off." footer. Target for milestone 3. |
| `docs/reminders-style-references/REMINDERS_WHEN_BUILDER.png` (1586x992) | The condition-editing design: reminder list, a condition palette (search, categories, click or drag to add), the rule as cards ("Show a reminder when", "Only while", Add restriction, Advanced logic), a plain-language result with Hidden now / Details, Try a situation, Undo/Redo, Cancel/Save. Target for milestone 4. |

These are **approved targets**. Any screenshot of the current client or simulator is **before-state evidence only** and
never a target. The renders are mockups: where they show things outside the approved requirements (the Search templates box
and All / Preparation / Equipment tabs, faction icons and the profile footer, a global search box, new artwork for each
template, drag-to-add in the palette, a separate Save step) those are **not** implied scope. Treat the filters as the
deferred item in C; take the rest as styling guidance and confirm with the owner before building behavior the code does not
have. Where a render and CLAUDE.md or the safety rules differ, the rules win.

## A. Current implementation (verified by reading the code)

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

Two separate looks exist and **must not be mixed up**:

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
- The approved renders are targets, not assets: nothing is cut from them. The only artwork of the Reminders feature
  is in `media/reminders/` (see "Missing bespoke template artwork" below).

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

### Missing bespoke template artwork (separate from design references)

The renders show per-template illustrations (oil and sword, soup and bread, shield, quiver, scroll and quill). Runtime
artwork exists only for shield, ammo and well fed (`media/reminders/`, painted at 64 px for rows; not necessarily the
render's illustration style or size). Weapon enchant, item and custom have none. New artwork is **not** produced by this
brief; it needs a source image and a `tools/make_*` cut when requested. Until then the catalog uses icons for those cards
(milestone 3 may ship with that fallback; ask before generating art).

### When designer

The inline When designer (`RemindersDesigner.lua`, `RemindersPlain.lua`) is built and tested. **Reuse and adapt it; do not
rebuild it** unless the owner decides otherwise. The render shows a fuller layout (palette beside the rule, plain result,
Undo/Redo, Cancel/Save); compare it with the designer's existing picker (search, categories), copy-on-edit (Done/Cancel),
Undo and "Why would it show?" before changing anything, and change only what milestone 4 needs.

## B. Evidence

| Claim | Label |
|---|---|
| Items in section A (file paths, symbols, line numbers, relationships) | **Verified by this inspection** (read code, 2026-11-10) |
| 187 passing tests, Lua syntax checks, simulator construction smoke success | **Previously reported, not rerun**: historical |
| `test_reminders_settings.lua`, `test_settings_window.lua`, `test_settings_window_size.lua` each print `PASSED`; `luac5.1 -p` clean on `Reminders*.lua` (6 files) and `Material.lua` | **Fresh, run in this task** (offline unit tests only; the full `./tests/run.sh` and simulator were **not** run: documentation-only task) |
| The attached preview now works in the real client | **User-confirmed**. Not inferred: catalog behavior, Esc, close box, edge flipping, scaling, clamp, combat/cleanup and one-preview-after-reopen are **not** confirmed (docs/reminders.md checks 27-28 remain open) |
| Catalog in the real client | **Not tested** (no user confirmation recorded) |
| Warm styling of Reminders (companions, cards, editor), interactive preview, search/category filters, companion When editor | **Requested, not implemented** |

## C. Approved remaining requirements

- Reminders is the **prototype** for the shared polished settings style. It is not authorization to restyle other pages or
  windows. `Material.lua` stays settings-window-only; do not edit `Look.lua`/`FrameLook.lua` for other consumers.
- Look: warm espresso/walnut leather, chestnut surfaces, aged bronze, ivory text, selective antique gold, restrained depth,
  rounded controls, readable text. Targets are the three approved renders in `docs/reminders-style-references/` (top of this document).
- Compact editor: cut redundant introductory prose (the `Section` blurbs, the catalog/preview subtitles where they repeat
  the title), keep advanced diagnostics (Test, "Why would it show?", Try a situation) secondary.
- The preview stays usable beside the editor while editing.
- Clicking a configurable preview element **navigates to and highlights** the matching setting and **changes no reminder
  configuration** (navigation only; no write path).
- The catalog uses distinct illustrated cards in a consistent layout.
- Keep independent, initially disabled template creation (`P.Create` -> `RM.Create`). Keep validation, unknown-condition
  semantics (three answers, groups), profile compatibility and saved data unchanged. No schema change.
- Preview, catalog and a future When editor share the companion position and never show as competing frames.
- Search and category filters stay requested but **deferred**: a separate scope item, not a prerequisite for the visual work
  (the picker in the designer already has search and categories; the catalog has neither).
- When editor: inspected state above (already built, inline, pooled frames). Its remaining work is only visual consistency
  with the new style and, optionally, the companion placement (D4). Do not rebuild it.

## D. Milestones (each is one request)

1. **Shared styling foundation and compact editor.** Apply `Material` (cards, fields, button faces) consistently across the
   Reminders page and `Section` cards; shorten/remove `Section` blurbs and duplicate prose in `Reminders.lua`/`RemindersEditor.lua`;
   fold Test and "Why would it show?" behind secondary treatment (collapsed or last, no behavior change). Smallest set of
   shared helpers only if two files need the same function (e.g. a companion-frame dressing function in `Material.lua` or a
   local file): no new framework.
   Acceptance: `Reminders*.lua` unchanged in behavior (`test_reminders_settings.lua`, `test_reminders_designer.lua`,
   `test_settings_window*.lua`, `./tests/run.sh` pass); no new frames per redraw; blurbs gone or shortened with the tests that
   read them updated deliberately; `simlab/smoke.sh` constructs the page; screenshot reviewed structurally; real-client check
   of readability.
2. **Styled interactive preview.** Dress `RemindersPreview.lua` in the companion look; make configurable parts of the preview
   copy clickable (needs the `D.DrawSurface` part map, dependency 1) and add the reveal/highlight helper (dependency 2). Reveal
   goes through the editor's section frames; highlight is a transient texture and writes nothing.
   Acceptance: clicking a part reveals the right control and writes no saved value (unit test asserting `RM.Get` unchanged
   and no `Set*` call); preview still never plays sound or reads a condition; Show on screen unchanged; `PV` still makes its
   frame once; Esc/close/page-hide cleanup unchanged; real-client: click targets, scroll, highlight.
3. **Styled template catalog.** Cards with consistent layout and artwork per template (supply or decide art for `enchant`,
   `item`, `custom`, see F), same companion look as the preview, `Use template` primary, close box. Keep `Use` -> `P.Create`.
   Acceptance: the existing section 10 tests pass (independent copies and ids, starts off, refusals keep it open, cancel
   makes nothing); text fits at the real card size (screenshot, then real client); placement is the shared `PV.Place`.
4. **When editor consistency and companion sharing, only if needed.** Restyle the designer's cards to the finished style;
   decide whether it stays inline (recommended: yes, until a render says otherwise). If it becomes a companion, route it
   through the same placement and one-at-a-time rule with a test for the handoff.
   Acceptance: `test_reminders_designer.lua`, `test_reminders_groups.lua` unchanged in behavior; unknown-condition cards,
   Edit/Cancel copy semantics intact.

Order is by dependency: milestone 1 supplies the style the next two use; 2 before 3 because the placement/handoff rules the
catalog also follows are exercised first by the preview. Filters (catalog search/category) are outside all four.

## E. Verification map

Run from the repository root; the test harness also needs `lua5.1` + `bit`.

| Kind | Command | What it proves |
|---|---|---|
| Syntax | `luac5.1 -p '<file>'` after each Lua edit | parses |
| Focused behavior (unit) | `(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_reminders_settings.lua)`; same for `test_reminders_designer.lua`, `test_reminders_groups.lua`, `test_settings_window.lua`, `test_settings_window_size.lua`, `test_reminders.lua` | creation path, selection, catalog (section 10), preview handoff (section 11), settings window sizing |
| Full suite | `./tests/run.sh` (about 10 s) | required for code changes by `CLAUDE.md` |
| Simulator construction | `bash tools/simlab/smoke.sh` (all pages construct; run with bash, not zsh) | the page and companions build without a Lua error |
| Simulator interaction | `bash tools/simlab/interact.sh` drives only `notificationsLook`; **no Reminders scenario exists** | nothing for Reminders; do not claim it |
| Screenshot review | the simulator's page screenshot (`docs/simulator-lab.md`) | structure only (columns, fit); fonts fall back; **not** visual validation |
| Real client | `docs/reminders.md` in-game checklist, items 27-28 plus new items you add for the style | appearance, placement, scaling, Esc, click targets, taint-free behavior |

Limitations (not to be repaired in this work): the simulator cannot show real appearance, pointer input, combat or
reload persistence; companion frames and the preview surface are only constructed there.

## F. References and unresolved decisions

- References: the three renders in `docs/reminders-style-references/` (top of this document). No other design reference is
  needed; no guild-bank mockup is required. Guild-bank code and art (`FrameLook.lua`, `media/guildbank/`) are optional
  implementation reuse, not a competing target.
- Other images, unrelated to layout, for reuse only: `../assets/reminders.png`, `../assets/style-v2-assets.png`,
  `../assets/reminder-art-{ammo,shield,wellfed}-source.png`, `../assets/reminder-designer-source.png` (`../assets/` is a sibling
  folder outside the repository).
- Consequential questions only:
  1. Bespoke artwork for the Weapon enchant, item and custom cards (and whether to match the render's illustrations): new
     painted art, or icons for now? Not blocking milestones 1 and 2.
  2. Which render elements outside the approved requirements (see the table note) to build, if any.
  3. Does the When editor stay inline? (Recommended: yes, restyled, unless the owner wants the render's companion layout.)
- Not decided here, because the code already answers it: creation path, initial disabled state, companion position
  (`PV.Place`), preview safety rules, profile/schema (none).

## First Codex session prompt (copy and paste)

Model: choose the strongest available Codex coding model in your client, at **Medium** reasoning effort.

```
Read AGENTS.md and docs/reminders-style-upgrade.md first, then CLAUDE.md sections the task touches.
Implement only milestone 1 of that brief: shared styling foundation and compact Reminders editor
(Material.lua, pages/Reminders.lua, pages/RemindersEditor.lua; no other pages).
Keep the existing template creation path (P.Create -> RM.Create), the preview and catalog behavior, saved data,
validation and unknown-condition semantics unchanged. Preserve all existing user work; do not touch unrelated files.
Visual targets are the three approved renders in docs/reminders-style-references/ (REMINDERS_PREVIEW.png is the one for
this milestone; the other two are for later). Do not invent a design, generate artwork or add behavior the renders imply but
the brief does not approve (filters, drag-to-add).
Verify with luac5.1 -p on edited files, the focused tests listed in section E, ./tests/run.sh and bash tools/simlab/smoke.sh;
label each claim unit-tested / simulator-tested / screenshot-reviewed / not tested, and list the in-game checks still needed.
No plan-approval step is needed. Stop and ask before any material scope expansion, and after two substantive failed
approaches to one blocker, report what you know and the smallest next action. Do not commit, push, publish or change
.toc interface/version. Report as: Changed / Verified / Limitations / In-game checks / Follow-up, briefly.
```
