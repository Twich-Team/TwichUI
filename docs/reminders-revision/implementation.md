# Reminders revision verification

## Final Advanced layout correction (2026-11-11)

**Cause:** `PlacementSection:Layout` drew Position with a zero-height row advance, then drew Opacity at the
same anchor. Both the Position label/dropdown and Opacity were visible. This was an actual layout collision,
reproduced in `../wow-ui-sim-lab/artifacts/reminders-20261111-071326/scrollHeader.png`, not a material issue.

`pages/RemindersEditor.lua` now puts Position on its own row inside **More placement and appearance options**.
Opacity remains the first primary row. Primary and nested rows use a consistent 32-unit rhythm, with additional
header/disclosure/bottom padding. Slider widths respect the editor's right inset, equal numeric boxes remain aligned,
and Sound's dropdown/Play spacing adapts to the same bounds. The timing labels are shortened to **Show after** and
**Keep for**, retaining their settings and full explanation; the previous longer label overflowed its column in a render.

**Additional reflow defect found by testing:** closing long disclosures could leave the scroll offset beyond the new
content height. `Window.Layout` now clamps that stale offset for the existing fixed-chrome pages only, canceling any
pending wheel interpolation when clamping. Ordinary settings pages keep their prior layout path. No polling, new
assets, configuration changes or new event hooks are introduced; this is rare existing layout work, so no new
performance scope is warranted.

| Discrepancy | Correction and screenshot review |
|---|---|
| Position/Opacity overlap, P1 | Position is hidden with secondary options closed; its expanded row is between Background and Anchored to. Actual lower-area crop shows Opacity fully readable. |
| Row/column alignment, P2 | Equal 32-unit rows, common label/control columns, matching numeric widths and contained right edges. Reviewed at normal and .85 frame scale. |
| Crowded disclosure and bottom, P2 | Added header/disclosure clearance and bottom padding; Duplicate/Delete and Reset retain separate space. |
| Timing label overflow, P2 | Shorter player-facing labels fit their column and align with the sliders. |
| Stale scroll after collapse, P1 | Native scenario shrinks from Advanced + nested + Diagnostics at the old bottom, checks the new range and repeats three disclosure cycles. |

**Final screenshot-reviewed evidence**, all under `../wow-ui-sim-lab/artifacts/reminders-20261111-072004/`:
`advancedCollapsed.png`, `advancedExpanded.png`, `advancedNested.png`, `advancedNestedBottom.png`,
`advancedDiagnostics.png`, `advancedScaled.png`. The final captures put the window higher on screen so the simulator's
unrelated floating Issue report control does not cover the primary Advanced rows. It remains visible in the original
captures; no simulator internals were modified. The original preview mockup and supplied client captures were reopened.
Native-size crops `test-output/reminders-advanced/advanced-lower.png`, `nested-options.png`, and `before-after.png`
(baseline left, corrected right) preserve the comparison. The lower-area and comparison crops were also opened.

**Verified:** `luac5.1 -p` on both production files, both focused tests and the scenario; `git diff --check` clean.
Focused `test_reminders_settings.lua` and `test_settings_window.lua` pass; `./tests/run.sh` **187 passed, 0 failed**
(`test-output/reminders-advanced/unit-suite.log`). The six final simulator poses each pass **103 handler/state checks**.
They cover numeric entries, Words go, separate Position geometry, disclosure height/visibility, scroll bounds,
duplicate/delete confirmation, Edit conditions, preview lifecycle and both Place entry points via the existing prelude.
`bash tools/simlab/smoke.sh`: **56/56 page construction**, no captured error or missing TwichUI texture
(`smoke-20261111-072104`). Earlier `071549` captures preserve the failed collapse-range check; it passes in `071753`
and the final run. Early evidence framing initially reset the viewport to the top; the final poses expose the requested
lower controls without changing production behavior for screenshots.

Changed this pass: `RemindersEditor.lua`, `Window.lua`, `tests/test_reminders_settings.lua`,
`tests/test_settings_window.lua`, `tools/simlab/scenarios/reminders.lua`, this record, the brief and backlog.
Existing dirty work is preserved. No commit or deployment. **Not real-client-tested:** confirm actual wheel/thumb input,
font baselines, dropdown selection and repeated disclosure toggles at the player's usual UI scale. The simulator uses
handler calls and substituted fonts; screenshot review is structural evidence, not client visual acceptance.

## Placement, Reset and distinct condition art addendum (2026-11-11)

Current `feature/style` work is preserved. The user's successful deployment shown in chat belongs to the preceding
checkpoint; this addendum edits only the repository/lab and does not deploy. The approved Home frame/button and When
references were reopened. No global material or interface redesign.

| Requirement | Implementation | Verification |
|---|---|---|
| Primary placement | The **existing** `Editor` move button is reparented to the selected-reminder header and labelled **Place on screen**, beside Live preview. Advanced no longer places/hides it; presets, offsets, effects and all other controls remain. Companion Place still calls `RemindersPlacement.Start`. | Unit spy proves both entry points call the same transaction. Simulator clicks both, cancels, and checks enable state, data, Settings restoration and preview lifecycle. Main screenshot shows the action with Advanced closed. |
| Reset artwork | `Window` retains the existing confirmation callback/reset plan and applies `Material.ReminderControl(..., "danger")` only for `materialHeader` pages. Original destructive source, hover/pressed/disabled states and typography are reused. | Unit checks danger/hot/down states, confirmation cancel/accept and page-only scope; ordinary Food reset remains unstyled. Simulator confirms cancel keeps the master off and acceptance preserves every reminder. Normal/hover images opened. |
| Semantic icon distinction | `Plain.ArtFile` / `ApplyArt` use dedicated condition art; all catalog, basic/advanced cards, drag ghosts, illustrated summaries and diagnostic rows already consume this resolver. Reminder display art and template art are unchanged. | Distinct paths and 22/30/45-unit selection are unit-tested; native audit renders all 13 entries and target cards/palettes. No unrelated condition loses art. |

### Condition artwork audit

| Supported entry | Displayed artwork / decision |
|---|---|
| Equipment slot | Existing `gearComparison` painted breastplate; retain |
| Ammunition | Existing `ammunition` leather quiver; retain |
| Weapon enchant | **New broad enchanted steel blade**, bronze guard, chestnut grip and subdued sage-blue coating |
| Well Fed | Existing plate/cutlery reminder artwork; retain |
| Class | Existing `profiles` bronze portrait medallion; retain |
| Specialization | Existing `classResources` crystals; retain |
| Combat | **New crossed dark-steel swords**, no magic; distinct from enchant |
| Alive or dead | Existing `resurrection` winged ankh; retain |
| Ghost | Existing `releaseSpirit` wisp/banners; retain |
| Mounted | Reused original `media/npcs/horse-head{,-small}.tga`; replaces inventory-tile horse |
| Resting | Existing `sleepingBag` rolled bedroll; retain |
| Dungeon / Raid | Existing `mapsNavigation` map/pin; the two predicates share the legitimate unified Location identity |

Previously enchant and combat both used `Ability_DualWield`; Mounted used `Ability_Mount_RidingHorse`. These game-tile
shortcuts are removed. `Pl.Icon` retains semantic fallback IDs; dedicated type artwork is resolved independently of
`Config.ART` and catalog template illustrations.

### Generation, preparation and inspection

**Three built-in `image_gen.imagegen` calls:** enchant v1, Combat, and one targeted enchant v2 revision. The first sword
was too thin at 30 px; the broader v2 has similar visual weight to the other motifs. That is the sole refinement of
this asset. Exact prompts, selection rationale and reuse provenance are in
[assets/reminder-condition-sources.json](../../assets/reminder-condition-sources.json).

Original sources: `assets/reminder-condition-enchant-source.png` (retained v1),
`assets/reminder-condition-enchant-v2-source.png` and `assets/reminder-condition-combat-source.png`, all 1254x1254 RGBA.
Final runtime files: `!!!TwichUI/media/reminders/conditions/{enchant,combat}{,-small}.tga` at 64x64 / 32x32.
Mounted's original 64/32 assets are referenced directly, with no pixel changes or duplicate copy.

`python3 -B tools/make_reminder_condition_art.py` uses the existing shape-based alpha cleanup, optical balance,
premultiplied resampling and edge bleed. Full-square texcoords retain consistent padding. The 64-pixel enchant contains
**2,770 clear / 1,326 partial-alpha pixels**; Combat **2,664 / 1,432**. Both have real transparent exteriors, with no
inventory background/checkerboard. All six new/reused runtime files' format, byte length and alpha were checked in
`test-output/reminders-addendum/runtime-alpha.json`. Original source alpha/bounds and balancing are in `alpha.json`.

`runtime-sizes.png` preserves the first thin-sword review. `runtime-sizes-final.png` was opened at actual 30/45/22 sizes
over espresso and warm parchment. Blades retain readable silhouettes and subdued enchant color; horse lighting and
palette fit the retained family. Runtime art is included under core media; assets/tools/inspection output remain
excluded by existing packaging rules. No new dependencies, credentials, service changes or API/CLI fallback.

### Code and evidence

Changed: `pages/Reminders.lua` (primary action placement), `RemindersEditor.lua` (remove the Advanced row),
`RemindersPlain.lua` (single condition-art resolver), `Window.lua` (scoped Reset skin); focused settings/window tests;
existing simulator scenario; new preparation tool, three source PNGs, prompt manifest and four runtime TGAs.
The brief, feature doc, backlog and this record carry current behavior/progress. Other dirty work is preserved.
No saved schema, condition evaluation, reset scope, placement transaction or display-art values changed.

Captures below are relative to `../wow-ui-sim-lab/artifacts/` from the repository:

- `reminders-20261111-065629/editorTall.png`: main header with primary Place and retained companion button.
- `reminders-20261111-065629/resetNormal.png`, `resetHover.png`: actual Reset normal/hover treatment.
- `reminders-20261111-065901/conditionIcons.png`: three target cards plus default condition palette.
- `reminders-20261111-070108/mountedPalette.png`: complete filtered Mounted palette and three target cards.
- `reminders-20261111-065901/conditionAudit.png`: all 13 supported palette entries at 30 and 45 units.
- `reminders-20261111-065629/placement.png`: existing companion-triggered placement mode.
- `reminders-20261111-070108/placementPrimary.png`: the same toolbar/renderer entered from the main primary action.

These images were opened. Early `065629/conditionIcons` included an additional Location condition that pushed Mounted
below the viewport; the final synthetic pose isolates the three audited types without changing production layout.
The simulator omitted outer modal pieces in the first filtered-palette captures despite a visible frame tree; those
images are retained. The final `070108/mountedPalette` recapture contains the complete modal. It and the unfiltered
builder/audit establish integration; no engine fix or production rendering workaround was introduced.

Unit tests: `test_reminders_settings.lua` and `test_settings_window.lua` pass using the repository Lua 5.1 command.
`./tests/run.sh`: **187 passed, 0 failed**, `test-output/reminders-addendum/unit-suite.log`.
Syntax checks after each edit and final `luac5.1 -p` for all seven changed Lua files pass; `git diff --check` is clean.
`bash tools/simlab/reminders.sh editorTall resetNormal resetHover conditionIcons mountedPalette placement`:
**93–94 handler/state checks per pose**, all pass; final `conditionIcons mountedPalette conditionAudit`: **93 each**, pass.
The shared prelude also exercises preview lifecycle, silent disabled previews, creation, draft transactions and drag
identity. Final `mountedPalette resetNormal placementPrimary` also passed 93 checks each. `bash tools/simlab/smoke.sh`
passed 56/56 page construction with no captured error (`smoke-20261111-070305`). New actions are event-rare and use
existing bounded UI/renderer pools; no new hot-path scope/polling is needed.

**Not real-client-tested.** The simulator has no real mouse/keyboard injection and substitutes game fonts for addon
fonts. Check primary/companion Place via real dragging, Finish/Cancel/Esc/combat and reload; Reset hover/press and named
confirmation; icons at the player's UI scale and actual font. Verify the companion remains hidden in normal gameplay.
No new placeholders remain. No commit, push, publish or deployment was performed in this addendum.


## Interaction polish and contextual UX (2026-11-11)

The four approved images and all four newly supplied Nov 11 client screenshots were opened before changes.
The prior dirty `feature/style` work is preserved. Baseline actual addon captures are in
`../wow-ui-sim-lab/artifacts/reminders-20261111-054335/` (editorTall/details/when); they were opened.
This pass retains quiet leather, frames, hinge, selected-row sources, condition art, the rule engine and saved schema.

### Discrepancy register and results

| Component / severity | Reference or requested intent; observed deficiency | Correction / responsible implementation | Rerender verification |
|---|---|---|---|
| Header/body ownership, P1 | Reminders title, master and tabs fixed; client scrollbar reached the tabs | `Window` separates scoped fixed chrome from a body viewport; `Cards` anchors the master there. Known ammunition opts in; ordinary pages restore original geometry. | Opened scrolled diagnostics, font picker, `scrollHeader`, `ammoTab` and constrained editor; body and scrollbar stop beneath tabs. |
| Scroll rails / feel, P1 | Narrow dimensional bronze; native main rail and coarse wheel steps | `Material.ScrollRail` reuses native slider with painted thumb/arrows; `Widgets.ScrollMotion` moves 24 units over <=120 ms, cancels on drag/reveal/hide, honors reduced motion. Menus use a native vertical slider. | Unit and simulator handler tests cover range, finish/cancel, shorter content and popup thumb callbacks. Real wheel/drag feel remains client-only. |
| List rows / actions, P1 | Rows fill list and provide direct contextual actions | Wider row geometry; right-click Duplicate/Delete via canonical APIs, named confirmation; left-click dismisses menu without toggling. | Screenshot-reviewed compact reminder menu and wider selected row; unit + simulator duplicate/delete/cancel checks. |
| Context menus, P1 | Compact labels; prior 340-wide condition menus and font popup offset | Content measurement bounded 112–280; concise move labels with full help. `Widgets.VisibleRect` includes nested scroll transforms before popup/help positioning; menu flips/clamps at edges. | Font popup now touches its visible scrolled owner; scale/context captures and geometry checks pass. |
| Summaries, P1 | Scan trigger/restrictions without a long sentence | `Plain.Explanation` supplies illustrated trigger/restriction rows for complex flat All rules, explicit nested All/Any for advanced trees. Simple rules remain concise. Main compact When and builder rail consume these rows. | Structured summary and basic/advanced tests preserve every condition, negation and saved node. Builder rail no longer repeats Edit conditions. |
| Placement transaction, P0 safety | See the world, Finish/Cancel, preserve old position on cancel | New `RemindersPlacement` toolbar hides Settings. `Display` keeps private coordinates, commits once through `SetPosition`; checks raw identity/concurrent position, combat/deletion and stale drag-stop. Settings restores selection/scroll/current size; explicit close stays closed. Exclusive catalog/When cannot start competing placement. | Unit + native simulator handler/state checks cover movement without writes, cancel, commit, late release, conflicting write, combat event, deletion, Esc, close/reopen and refresh attempts. No real pointer/combat test. |
| Font picker, P2 | Name previews in each supported typeface | Choices include resolved font files; per-row `SetFont` with fallback. Original list and selection persist; normal menu typography restores afterward. | File choice/callback tests pass. Simulator substitutes Friz for addon fonts, so actual face differences remain client-only. |
| Preview modes, P1 | Dark / true Transparent / original Landscape / Parchment | `Preview` owns session-only mode; hollow shell + four exterior strips leave a real hole. Actual/Fit, saved display and live visibility are untouched. | All modes opened; Transparent reveals an explicitly labelled **simulator-only underlay** below the actual companion (the simulator has no terrain). Repeated hidden-mode changes cannot reopen it. |
| Preview navigation, P1 | Visible artwork/text hover and rich destination emphasis | Painted hover rim/low-alpha selection, concise material tooltip; temporary selected-sheet/rim on destination with existing reveal and stale-timer cleanup. | Hover and destination screenshots opened and compared with the client thin-outline example and preview reference; no configuration writes. |
| Diagnostics, P1 | Overall outcome, distinct condition rows, simulation separated | `Editor.ResultRow/DrawResults` share icons, bold states, observations, separators and group indentation. Main Diagnostics separates overall result, technical disclosure and SIMULATED inputs/results; builder Details/Try reuse rows. | Opened live and expanded situation captures; source facts and simulated facts remain visibly distinct, with main content handling height. |
| Builder sample, P1 | Illustrated ivory parchment | Original parchment under isolated renderer; presentation ink only. No saved appearance changes. | Reference/before/after crop opened at runtime size; dark/warm alpha composites reviewed. Different content and retained icon/text layout are deliberate. |
| Disclosure glyphs, P2 | Readable arrows | Shared opt-in `Material.Disclosure` uses a texture chevron instead of the missing down-glyph visible in early captures. | Final expanded diagnostics/Advanced screenshot opened. |

### Files and reusable components

Changed this pass: core `reminders/Display.lua`; Settings `Window.lua`, `Widgets.lua`, `Material.lua`, `Cards.lua`, TOC;
`pages/Reminders.lua`, `RemindersPlain.lua`, `RemindersEditor.lua`, `RemindersBuilderRail.lua`, `RemindersDesigner.lua`,
`RemindersPreview.lua`, **new `RemindersPlacement.lua`**, and the related `AmmoItems.lua` header opt-in;
`tests/test_reminders_settings.lua`, `tests/test_settings_window.lua`; the existing simulator Reminders scenario and
new `tools/make_reminder_preview_art.py`; original sources/runtime art below; this record, brief, feature doc and backlog.
Unrelated existing changes (including inventory drag and the editor workspace) were not altered.

Reusable: painted scroll rail + native input, finite wheel motion, compact action popup, visible-rectangle conversion,
font-choice metadata, texture disclosure marks and existing selection sheets. `Plain.Explanation`, result-row data,
preview/background ownership and placement transactions remain Reminders-specific. No global theme migration.
One-off placement/mode/menu actions are rare and cheap; no new hot-path profiler scopes are warranted. Existing
Display positioning counts and designer layout scopes remain; all new pools are bounded and hooks installed once.

### Original artwork and pipeline

Exactly **two built-in `image_gen.imagegen` calls**: original landscape and parchment. No CLI/API fallback, packages,
credentials or configuration changes. Exact prompts: [assets/reminder-preview-sources.json](../../assets/reminder-preview-sources.json).
Sources: `assets/reminder-preview-{landscape,parchment}-source.png` (1536x1024 RGB; 1983x793 RGBA respectively).
Prepared with `python3 -B tools/make_reminder_preview_art.py`, reusing existing premultiplied resampling, color bleed
and rectangular TGA writer. Runtime `!!!TwichUI/media/reminders/preview-landscape.tga` is 512x512; parchment is 512x256;
both are uncompressed 32-bit straight-alpha TGAs. Landscape is fully opaque; parchment has **18,917 clear / 112,155
partial-alpha pixels** (near-opaque interior), so transparency is real. Source alpha: 236,424 clear pixels. No checkerboard.
Runtime paints were opened; parchment was composited at 248x111 over both dark leather and warm light material.
Evidence: `test-output/reminders-polish/assets.json`, `parchment-runtime-backgrounds.png`, `test-output/preview-art/alpha.json`.
Existing `.pkgmeta` excludes assets/tools/docs/test-output and includes runtime core media. TOC Interface/Version unchanged.

### Final visual evidence (opened, not client acceptance)

All paths below are under `../wow-ui-sim-lab/artifacts/` relative to the repository:

| Surface | Capture |
|---|---|
| Main editor + Dark preview | `reminders-20261111-062539/editorTall.png` |
| Focused When + parchment sample | `reminders-20261111-061540/when.png` |
| Template catalog | `reminders-20261111-061329/catalog.png` |
| Live Diagnostics / expanded simulation | `reminders-20261111-062314/editorDiagnostics.png`, `editorSituation.png` |
| Preview Landscape / Parchment | `reminders-20261111-060322/previewLandscape.png`, `previewParchment.png` |
| True Transparent with labelled test underlay | `reminders-20261111-061540/previewTransparent.png` |
| Preview hover / destination highlight | `reminders-20261111-061329/previewHover.png`, `destination.png` |
| Reminder context menu / font menu | `reminders-20261111-062539/reminderMenu.png`, `fontMenu.png` |
| Condition menu | `reminders-20261111-061329/conditionMenu.png` |
| Placement toolbar | `reminders-20261111-061540/placement.png` |
| Constrained editor / builder | `reminders-20261111-061329/narrowEditor.png`, `reminders-20261111-061827/narrow.png` |
| Builder Details / Try / drag / nested / scaled popup | `reminders-20261111-061827/{details,situation,drag,nested,scale}.png` |
| Scrolled fixed header / ammunition tab | `reminders-20261111-062314/scrollHeader.png`, `ammoTab.png` |

Comparison crops and exact rectangles are in `test-output/reminders-polish/crops.json`: header, selected row,
parchment, Diagnostics, destination, hover, four backgrounds, font popup and condition menu. Reference crops alone
are resized in three-column comparisons. No numerical similarity claims. Diagnostic before-state comes from the
supplied client screenshot, not a design target. Raw captures remain preserved, including failed intermediate runs.

Early `055902`/`055943` captures exposed unsupported general-control skinning on native scrollbar arrows; texture-only
native-arrow painting corrected it. `060655`/`060830`/`060942` exposed popup scroll-coordinate offsets; `061120` verified
the correction. Some software-rendered hover/destination captures omitted a companion whose tree said visible; those
images are retained and not counted as visual evidence for missing regions. The final hover/destination pair contains
the complete companion. The `061827/situation` image similarly omits the upper modal; it is handler evidence plus a
lower-region capture, not acceptance of the missing upper region. No simulator engine changes or production workarounds.

### Verification and remaining acceptance

- **Unit-tested:** `./tests/run.sh` — **187 passed, 0 failed**, final full output
  `test-output/reminders-polish/acceptance-unit-suite.log`. Focused `test_reminders_settings.lua`,
  `test_settings_window.lua`, `test_ammo_items_settings.lua` passed with the documented Lua 5.1 command.
  Final exclusive-placement guard was followed by the focused settings test again.
- **Syntax / repository-inspected:** `luac5.1 -p` after each Lua edit and across all 25 modified/new Lua files;
  `git diff --check` clean. TOC ordering, runtime dimensions/byte lengths/alpha and packaging exclusions checked.
- **Simulator construction-tested:** `bash tools/simlab/smoke.sh` — **56/56 pages**, no captured construction error;
  `smoke-20261111-062114`.
- **Simulator handler/state-tested:** exact batches used `bash tools/simlab/reminders.sh` with
  `editorTall when editorDiagnostics editorSituation placement previewTransparent` (81–82 checks),
  `when catalog previewHover destination conditionMenu narrowEditor` (80 each),
  `details situation nested drag narrow scale` (81–84),
  `editorDiagnostics editorSituation ammoTab scrollHeader` (81–82), and final
  `editorTall fontMenu reminderMenu` (**87 each**, including native menu-slider/font selection and context
  duplicate/delete/cancel callbacks). Background, lifecycle, Actual/Fit, disabled/silent preview, draft Save/Cancel,
  Undo/Redo, drag identity, targeting and creation/refusal checks run in the shared scenario prelude.
- **Screenshot-reviewed:** the principal surfaces, modes, menus, destination/hover, parchment, placement and constrained
  layouts above; crop comparisons opened. The earlier coarse texture and material palette were not regenerated.
- **Real-client-tested by this agent:** none. No true mouse/keyboard injection is available in this headless simulator.

Remaining visual differences are the existing shell/card sculpting and illustration proportions versus the renders,
content-dependent line wrapping, and simulator font substitution. The new parchment is lighter than the mockup's aged
sheet and deliberately has different edges. The native rendered reminder layout and chosen content are preserved.
At default window height, expanded diagnostics require the single main body scroll; narrow builder details use the
existing bounded lower drawer. There are no new placeholder assets. Visual approval remains with client review.

Client checklist: wheel + thumb + arrow behavior and easing at UI scales; popup/help alignment after scrolling;
font faces/fallback and selection persistence; all four preview modes over real terrain; artwork/text hover/click;
placement drag then Finish/Cancel/Esc, combat, close/reopen and reload persistence; repeated gameplay equipment/zone/
profile refreshes after closing Settings must leave the companion hidden. Check other addons/taint separately.
No commits, deployment, publishing, player SavedVariables or unrelated configuration changes were performed.


## Art-backed craftsmanship (2026-11-11)

Authority: `SETTINGS_HOME.png` is now the shared-shell/frame/selection reference; the three Reminders renders retain
authority over their feature layouts. All four actual images were opened. `docs/CODEX_RESUME.md` is absent. Work resumes
on the existing dirty `feature/style` tree; saved schemas and the rule model are unchanged. The earlier verification
records below describe prior passes, not acceptance of this one.

| Component / priority | Current construction and limitation | Retain / correction | Responsible source | Proof |
|---|---|---|---|---|
| Outer frame, P1 | Guild-bank painted rails plus procedural inner rim; square fittings, thin relief | Retain geometry/input; purpose-built rounded sculpted corner/rail artwork | `Material.WorkspaceFrame`, `CalibrateSettings` | Screenshot-reviewed in proof and all three surfaces: shared folded corners and continuous rails replace square fittings; old rails restore on other pages. Sculpting differs from Home's rolled corners. |
| Selected rows/tabs, P1 | Quiet sheet with gold tint; weak carved edge and material relief | Dedicated painted selection family, independent from hover | `ReminderRow`, `ReminderControl`, catalog segments | Screenshot-reviewed: separate source, layered rim and burnished leather. A second local preparation retained more painted relief. No global navigation-row rollout. |
| Buttons, P1 | Rounded flat face plus procedural rim; state mainly tint | Painted button source; coordinated normal/hot/down/off/selected/primary/secondary/danger sheets | `ReminderControl` | Screenshot-reviewed state matrix and footer: depressed lighting, dark disabled state, gold primary and restrained burgundy. Clipped proof labels and shifted Undo/Redo were corrected before final review. |
| Cards/panels, P1 | Quiet grain and 32px rounded face | Retain grain; coordinated art-backed edge and inset/raised families | `PanelFace` | Screenshot-reviewed: hollow painted relief over unchanged fills; redundant rims removed. Actual condition dropdowns remain directly editable. |
| Dropdown/menu, P2 | Recess face; selected row tinted, generic arrow | Shared painted field shell, menu/popup rows, existing hit geometry | `Widgets`, `MenuStyle` | Screenshot-reviewed open menu and 72% scale; inset value text and native row selection retained. Ordinary menus restore their original styling. |
| Slider, P2 | Solid track/fill and reused pill thumb | Painted recessed track and sculpted thumb; native numeric callbacks remain | `Widgets.Slider` | Screenshot-reviewed: physical thumb and inset track/value box. Scripted slider/typed-value checks pass; real mouse drag remains a client check. |
| Header/branding/search, P1 | Small crest, small wordmark, square shallow search | Scoped Home-reference proportions/search/branding; preserve navigation workflows | `Window`, `CalibrateSettings` | Screenshot-reviewed: 44-unit existing emblem, larger wordmark and 30-unit recessed search. Search retains geometry while typing; clearing/navigating restores editor/original shell appropriately. |
| Hinge/artwork/toggles, P2 | Generated transparent bronze fitting; illustrated condition/art library, working pill states | Retain; adjust fit only if new rim requires it | `FrameConnector`, condition catalog | Screenshot-reviewed: retained hinge meets the new rims; recognizable existing condition/template art and working toggles retained without new icon placeholders. |
| Editor/preview, P1 | Improved grouped Appearance, isolated preview and exclusive companion guard | Apply proven components; tune section spacing without scale/config changes | Reminders pages | Screenshot-reviewed: list aligns with primary editing stack, capped at 560 for long diagnostics. Preview shares shell/insets. Actual size/Fit and temporary world preview remain separate. |

Material relationships stay fixed: outer espresso (29/24/20), darker header (24/20/17), walnut editing region (35/29/24),
chestnut raised cards (48/37/29), smooth recess (18/16/14), muted bronze rails, ivory text. Painted edges may introduce
local shallow highlights/shadows; they must not replace the quiet large-area grain or shift the overall palette.
Measured blank-region RGB medians before/final remain identical for all four surfaces: header 24/20/17,
editor 35/29/24, card 48/37/29 and outer 29/24/20. Source rectangles and measurements are retained in
`test-output/craft-review/palette-samples.json`.
Generation used **three built-in `image_gen.imagegen` calls**: hollow frame, dark-leather button, and a separate painted
selection plaque. Originals are `assets/craft-{frame,button,selection}-source.png`. Exact prompts are saved in
[assets/craft-sources.json](../../assets/craft-sources.json). No CLI/API fallback, credential/configuration changes or new
packages. All three originals were inspected; outside pixels and the frame center have real alpha, not checkerboard paint.

`python3 -B tools/make_craft_art.py` prepares **28 uncompressed 32-bit straight-alpha TGAs** under
`!!!TwichUI/media/style-v2/craft/`. Frame: 256 × 256; button/selection states and hollow rims: 256 × 64; capsule chips:
64 × 32; thumb: 32 × 32. Preparation preserves painted edge relief and reduces the source leather's red cast/coarse grain.
The existing twenty quiet face/grain files were not regenerated. Frame has 57,524 clear / 8,012 partial alpha pixels;
button has 99 clear / 16,285 partial; these generated sources are nearly opaque inside (rather than exactly alpha 255).
Formats, byte lengths, power-of-two sizes and identical alpha silhouettes within each state family were checked.
Prepared PNGs and complete alpha counts are in `test-output/craft-components/assets.json`. Sources, tools, docs and
inspection output remain excluded by `.pkgmeta`; runtime art stays in the core media directory.

### Proof, integration and comparison

Baseline `042437` rendered editor/When/catalog/dirty with 65–67 checks each. It and the supplied newest client image
(`ChatGPT Image Nov 10, 2026, 07_37_20 PM.png`) were opened. The initial native component proof `043422` exposed label
clipping; `043555` corrected it before integration. Integrated captures `044116` and `044631` exposed square Location
chips and shifted history labels. Prepared capsule geometry and explicit label insets fixed those, with targeted tests.
The next captures `045016`/`045309` prompted a localized selection/primary relief correction, not a new global palette.
The final dashed target uses a quiet full-area fill rather than a solid button rim or an inner stripe.

Final, opened images and reference/baseline/final comparison crops:

- [Main editor / live preview](../../../wow-ui-sim-lab/artifacts/reminders-20261111-045911/editorTall.png).
- [When builder](../../../wow-ui-sim-lab/artifacts/reminders-20261111-050656/when.png),
  [dirty footer / enabled Save](../../../wow-ui-sim-lab/artifacts/reminders-20261111-045911/dirty.png).
- [Template catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261111-045911/catalog.png).
- [Native component/state proof](../../../wow-ui-sim-lab/artifacts/reminders-20261111-045911/craftProof.png),
  [open dropdown](../../../wow-ui-sim-lab/artifacts/reminders-20261111-045309/menu.png),
  [scaled dropdown](../../../wow-ui-sim-lab/artifacts/reminders-20261111-045309/scale.png),
  [constrained workspace](../../../wow-ui-sim-lab/artifacts/reminders-20261111-050428/narrow.png).
- [Button states](../../test-output/craft-review/button-states.png),
  [additional states](../../test-output/craft-review/additional-states.png),
  [selected row](../../test-output/craft-review/selected-builder-row-comparison.png),
  [frame corner at comparable shell scale](../../test-output/craft-review/home-frame-corner-scaled-comparison.png),
  [header](../../test-output/craft-review/home-shell-header-comparison.png),
  [primary action](../../test-output/craft-review/primary-button-comparison.png),
  [condition card](../../test-output/craft-review/when-condition-card-comparison.png),
  [Appearance/slider](../../test-output/craft-review/editor-appearance-controls-comparison.png).

The crops were opened and compared, with equivalent component widths rather than similarity scores. Their manifest
records source coordinates and explicit recaptures. The JPEG catalog reference was opened intact. Relevant controls
were reviewed against espresso and chestnut runtime backgrounds. Palette samples are retained alongside the crops.

### Verification and boundaries

- **Unit-tested:** `./tests/run.sh` twice, **187 passed / 0 failed** each. The final full log is
  [unit-suite.log](../../test-output/craft-review/unit-suite.log). Focused `test_reminders_settings.lua`,
  `test_settings_window.lua`, `test_reminders_designer.lua` passed, with settings repeated after final local edits.
  New checks cover native callback preservation, painted press/disabled states, history/dropdown label alignment,
  field disable repaint, header/rail restoration and stable search geometry. Existing lifecycle, draft transaction,
  Location, profile/data compatibility and preview-isolation checks remain.
- **Syntax-tested:** `luac5.1 -p` on edited Lua; Python source compilation; `git diff --check` passed.
- **Simulator handler/state-tested:** existing runner batches all passed: `editor editorTall when catalog dirty craftProof`
  (`045016`), `craftProof menu scale narrow drag nested` (`045309`), `error empty hover palette situation` (`045609`),
  `editorTall when catalog dirty craftProof` (`045911`), `details actions wellfed itemAppearance artAppearance` (`050115`),
  `when drag narrow` (`050428`), and final `when` (`050656`). **65–68 checks per pose**. The proof uses native controls;
  hover/press/drag are scripted handlers and geometry, not actual pointer delivery.
- **Simulator construction-tested:** `bash tools/simlab/smoke.sh` — **PASS, 56/56 pages**, no captured Lua error or missing
  TwichUI texture (`smoke-20261111-050549`). New module load order and nonpilot page construction are covered.
- **Repository/asset-inspected:** runtime paths resolve; TGA headers/alpha/state silhouettes verified; `.toc` adds only
  `Craft.lua` for this pass, no Interface/Version change. No release, deployment, credentials, live data or commits.
- **Screenshot-reviewed:** full main/When/catalog and component/state comparisons described above. This is visual
  evidence from the simulator, not client acceptance. Its fonts substitute Friz; Issue Report overlaps some bottom
  regions, and earlier capture omissions remain recorded in the prior pass. The final principal captures were complete.
- **Real-client-tested:** not performed. Check fonts/wrapping, pointer hit regions, menu hover/scroll, slider drag, scaled
  modal drag/drop, Save/Cancel/Undo/Redo, reload persistence, combat and sustained closed-editor gameplay refreshes.
  The editing-preview guard and explicit world preview must remain independent.

Remaining visual differences: folded corners instead of Home's rolled sculpting, retained authentic TwichUI emblem
instead of the mockup's shield, subtler metal relief/primary illumination, existing global navigation row geometry and
different native condition/template illustrations. The preview remains deliberately quiet at actual size. There are no
new placeholder assets; wider visual rollout and final real-client acceptance remain pending.

### Reuse and changed files

`SettingsCraft.Sheet/Frame/Control/Thumb` are page-independent, opt-in visual helpers. They own textures and state paint,
not input, callbacks, persistence or rule data. Fixed corners and family-specific UV cuts avoid stretching fittings;
`SetSkin` is for states within the same geometry family. Control supports primary, secondary/default, danger, field,
dropdown, segment, chip and quiet dashed-target treatments. `craftLabelInset` supports icon-plus-label controls. Optional
activation restores an original control when the pilot context ends. `LegacyRails` preserves/restores an existing shell.
The Material adapter preserves its historical discovery-action semantics while using the new art-backed components.
These APIs currently load with the Settings addon; adopting them in other standalone addons requires a later load-owner
decision, not a global rollout now. `SettingsMaterial` remains the quiet surface/font/scrollbar facade. Reminders retains
selection, rule layout, companion and preview lifecycle responsibilities. Core Look only exposes the existing focus ring
to opt-in paint ownership; default rendering is unchanged.

Files changed this pass: `!!!TwichUI/Look.lua` (one ownership pointer); `TwichUI_Settings/Craft.lua` (new), `Material.lua`,
`Widgets.lua`, `Window.lua`, `.toc`; `pages/Reminders.lua`, `RemindersBuilderRail.lua`, `RemindersDesigner.lua`,
`RemindersEditor.lua`, `RemindersPreview.lua`; two settings tests; `tools/make_craft_art.py`,
`tools/simlab/scenarios/reminders.lua`, `tools/simlab/reminder_components.py`; three PNG sources and prompt JSON;
28 runtime textures; this record, `docs/reminders.md`, `docs/reminders-style-upgrade.md`, `STATUS_AND_BACKLOG.md`.
Branch remains `feature/style`; the existing uncommitted implementation and unrelated changes are preserved.

## Visual component fidelity (previous pass)

The existing quiet grain and palette are retained. Baseline captures are `reminders-20261110-202326` (When, tall editor,
catalog and dirty footer; 65–67 handler checks passed). The approved three renders and the newest available client
editor/preview capture, `ChatGPT Image Nov 10, 2026, 07_37_20 PM.png`, were opened. No newer focused-builder client image
is present in the supplied directory; the actual current builder is compared through the simulator.

| Component | Difference | Severity | Focused correction | Rerender result |
|---|---|---|---|---|
| Outer frames | Thin flat rim, disconnected edge highlights | P1 | Layered, rounded bronze/recess rim over retained painted rails and hinge | Screenshot-reviewed: deeper inner cut, existing corners retained. Partial: corner sculpting is still simpler than the render. |
| Controls | Square corner remnants and weak recess/bevel | P1 | Rounded transparent rim that follows the existing face geometry | Screenshot-reviewed: dropdowns, inputs, menus and buttons have continuous rounded edges. Hover keeps dropdown value text inset; numeric values stay right-aligned. |
| Appearance | Loose art/size/color form rows | P1 | Group art with Choose; integrate color/size in one inset row | Screenshot-reviewed: 72-unit art tile/Choose group, text entry and inset color/size row. Item and artwork-only alternatives also captured; item input no longer encroaches on the tile. |
| Main proportions | Fixed-width list weakens at wide sizes | P2 | Bounded proportional list width; preserve minimum editor width | Unit-tested responsive bounds; tall-editor screenshot-reviewed with primary sections and lower actions visible. The retained Settings shell differs from the illustration. |
| Preview | Large shallow well and disconnected sizing controls | P1 | Recess rim, joined mode well, clearer status icon and footer | Screenshot-reviewed: deeper well and sizing group. Actual reminder scale is preserved; calm empty space remains at actual size. Rounded rectangles retained after capsule attempt produced doubled outlines. |
| Condition cards | Icon/state/controls lack shared alignment and depth | P1 | Matched rim, slightly stronger padding/headings/grip | Screenshot-reviewed: larger framed icon/title, circular grip dots, unchanged hit geometry and clear state/control alignment. Reference art and edge lighting still differ. |
| Status/footer | Sparse status band, Details far from reason | P1 | Dedicated recessed band, aligned disclosures and stronger action geometry | Screenshot-reviewed clean/dirty states: compact framed Details, summary-aware band height and 38-unit Save/Cancel; only enabled Save gets the bronze crest highlight. Relief remains subtler than reference. |
| Chips/palette | Generic chip rim and narrow catalog rhythm | P2 | Matching rounded rims; preserve visible Choose and direct editing | Screenshot-reviewed: continuous chip rim and shaped native scrollbar thumb; Choose remains visible. Existing distinct illustrations and category hierarchy retained. |
| Typography | Ordinary labels and headings too similar | P2 | Keep existing serif/sans families; refine size/weight by role | 18-unit card titles and 14-unit controls configured; no all-caps conversion. Simulator substitutes Friz, so real font weight/wrapping acceptance remains pending. |

### Component evidence and iterations

Baseline `202326` was followed by `203631` (four poses, 65–67 checks each). Those renders and the first comparison
crops were opened. `204137` ended with exit **143** before its final verdict; its ten completed captures individually
passed the runner's handler/error criteria when checked, but the overall command is not called a pass.
`204519` passed six follow-up poses. Inspection rejected a capsule experiment because it visibly doubled outlines;
the cleaner rounded rectangle treatment was retained. The final runs below use that treatment. The later item/artwork-only
captures exposed and verified a spacing correction for the enlarged tile, without changing saved display values.

Final, opened full screenshots:

- [Main editor and live preview](../../../wow-ui-sim-lab/artifacts/reminders-20261110-205303/editorTall.png).
- [When builder, clean](../../../wow-ui-sim-lab/artifacts/reminders-20261110-205417/when.png) and
  [unsaved changes / enabled Save](../../../wow-ui-sim-lab/artifacts/reminders-20261110-205417/dirty.png).
- [Template catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261110-204650/catalog.png): retained composition/artwork,
  matching rounded control/card rims and native scrollbar treatment.
- [Nested rules](../../../wow-ui-sim-lab/artifacts/reminders-20261110-204813/nested.png),
  [drag](../../../wow-ui-sim-lab/artifacts/reminders-20261110-204813/drag.png),
  [constrained layout](../../../wow-ui-sim-lab/artifacts/reminders-20261110-204813/narrow.png),
  [situation disclosure](../../../wow-ui-sim-lab/artifacts/reminders-20261110-204945/situation.png),
  [Details](../../../wow-ui-sim-lab/artifacts/reminders-20261110-204945/details.png),
  [item appearance](../../../wow-ui-sim-lab/artifacts/reminders-20261110-205303/itemAppearance.png) and
  [artwork-only appearance](../../../wow-ui-sim-lab/artifacts/reminders-20261110-205303/artAppearance.png).

Component crops are under [test-output/reminders-components-final-crops](../../test-output/reminders-components-final-crops/).
Each comparison PNG is **reference / baseline / final**, with individual native crops alongside; `crops.json` records
source paths, coordinates and column order. Only reference crops are resized proportionally to the actual component width.
The JPEG catalog reference was opened intact; catalog baseline/final crops are kept without adding a JPEG dependency.
Examples: [Appearance](../../test-output/reminders-components-final-crops/editor-appearance-controls-comparison.png),
[condition card](../../test-output/reminders-components-final-crops/when-condition-card-comparison.png),
[header/frame](../../test-output/reminders-components-final-crops/when-header-frame-comparison.png),
[Location chips](../../test-output/reminders-components-final-crops/when-location-controls-comparison.png),
[status/footer](../../test-output/reminders-components-final-crops/when-status-footer-comparison.png),
[preview controls](../../test-output/reminders-components-final-crops/preview-controls-status-comparison.png) and
[expanded dropdown](../../test-output/reminders-components-final-crops/when-expanded-dropdown-comparison.png).
These were opened and compared, not scored for numerical similarity. The dropdown's reference is closed: the mockup
does not specify expanded menu rows.

One clean-builder image in `204650` omitted most of the modal despite its frame tree reporting visible content and
passing state checks. The same unchanged code rendered completely on recapture (`204945`, then `205417`). Several
disclosure images similarly omit some outer frame/footer drawing. This capture anomaly is retained as evidence;
its cause is not established, and partial images are not visual acceptance evidence for the omitted areas. No simulator
engine workaround or production behavior change was made to conceal it. The simulator's Issue Report widget also covers
part of the bottom region. Real-client confirmation is required for those areas.

### Assets and reusable components

Two new **64 × 64, uncompressed 32-bit TGA** rim sheets are built by the existing standard-library material pipeline:
`!!!TwichUI/media/reminders/materials/control-rim.tga` and `frame-rim.tga`. Hollow nine-slices add fixed-size corner relief,
dark edge cuts and restrained upper-left bronze highlights over the existing faces. Control rim: 2,280 clear / 688 partial /
1,128 opaque alpha pixels. Frame rim: 1,824 clear / 1,144 partial / 1,128 opaque. Both were opened as PNG inspections and
inspected in actual runtime captures. Twenty existing face/grain TGAs were retained; **no grain or palette regeneration**
was performed. No new AI image calls or illustrations were needed; the painted rails, hinge, icon library and reminder
artwork are reused.
Rebuild only the new edging with `python3 -B tools/make_reminder_materials.py --rims-only`; omitting that flag rebuilds
the existing quiet face/grain assets as well.

`M.Rim`, `ReminderControl`, `PanelFace`, `ScrollRail` and scoped fonts remain opt-in, with no Reminders-specific data in
the generic components. Rim textures take no mouse input and do not alter frame scale, hit rectangles or drag coordinates.
The scrollbar keeps its native thumb/hit geometry and 16-unit wheel increment. Dropdown hover reasserts the value-text
insets after the base button's centering hook; compact contextual menus remain centered. Ordinary menus restore their
existing appearance. Source generator, comparison tool and inspection files remain excluded by `.pkgmeta`.

### Checks and boundaries

- **Unit-tested:** `./tests/run.sh` — **187 passed, 0 failed**
  ([full log](../../test-output/reminders-components-final-crops/unit-suite.log)). Focused `test_reminders_settings.lua`,
  `test_reminders_designer.lua` and `test_settings_window.lua` also passed; settings was repeated after the final local
  appearance/primary-rim edits. Coverage retains transactions, Location semantics, drag rejection/cancel, identity,
  preview isolation and repeated closed-editor/gameplay refreshes, and adds dropdown hover-inset protection and updated
  responsive list bounds.
- **Syntax-tested:** `luac5.1 -p` on all eight edited Lua files (including the focused test and simulator scenario);
  Python source compilation for both tools; `git diff --check` passed.
- **Simulator handler/state-tested:**
  `bash tools/simlab/reminders.sh editor editorTall catalog when dirty menu` (`204650`, six poses, 65–68 checks),
  `bash tools/simlab/reminders.sh nested drag error narrow empty hover` (`204813`, six poses, 65–67),
  `bash tools/simlab/reminders.sh palette situation details actions scale wellfed when` (`204945`, seven poses, 65–68),
  `bash tools/simlab/reminders.sh itemAppearance artAppearance editorTall` (`205303`, three poses, 66–67), and
  `bash tools/simlab/reminders.sh dirty when` (`205417`, 67/65). All commands passed. The two extra appearance poses
  assert physical separation and item identity using existing harness APIs. These are scripted handlers/geometry,
  **not real pointer delivery**.
- **Simulator construction-tested:** `bash tools/simlab/smoke.sh` — **PASS**, all **56/56** pages constructed,
  no captured Lua errors or missing TwichUI textures (`smoke-20261110-205119`). Unlike earlier historical smoke runs,
  this run did not hit the UTF-8 error.
- **Asset/repository-inspected:** 22 material TGAs have correct headers and byte lengths; rim alpha verified above;
  runtime paths resolve in simulator captures; assets/tools/docs/test-output exclusions remain. No release built/published.
- **Real-client-tested:** not performed. Confirm real font size/wrapping, precise hover/tooltips, native slider/thumb and
  menu scrolling, pointer drag at several scales, Save/Cancel/Undo/Redo, reload persistence and combat behavior. Repeat
  sustained closed-editor gameplay refreshes to confirm the existing P0 preview fix, and verify explicit world preview
  stays separate. Keep visual acceptance pending until those client checks and remaining corner/control relief differences
  are reviewed.

Current-pass files: `Material.lua`, `Widgets.lua`, `pages/Reminders.lua`, `RemindersEditor.lua`, `RemindersPreview.lua`,
`RemindersDesigner.lua`, `tests/test_reminders_settings.lua`, `tools/simlab/scenarios/reminders.lua`,
`tools/make_reminder_materials.py`, `tools/simlab/reminder_components.py`, the two rim sheets, this record,
`docs/reminders.md`, `docs/reminders-style-upgrade.md` and `STATUS_AND_BACKLOG.md`. Branch remains `feature/style`;
the existing dirty tree and unrelated work are preserved. No commits, deployment or live data edits.

## P0: editing preview reappeared during gameplay

**Root cause (repository-inspected):** `RemindersPage.Refresh` accepted the hosted frame's `IsShown()` value. That can
remain true under a hidden Settings parent. Config subscriptions and controller state changes still called
`QueueRefresh`; the delayed refresh called `PV.Show` on the UIParent companion. The close hook hid it once, but a later
refresh could show it again. Catalog/designer close callbacks and pending relayout work were additional refresh routes.

**Correction:** `SettingsUI.IsPageActive` includes window visibility, selected page and search state. `P.EditorActive`
also requires effective host visibility. `PV.Allowed` is the authoritative show guard: active editor, session preference,
current existing selection and no catalog/designer replacing it. All public show/update paths obey it. `PV.Update`
updates content/placement without showing the root. Settings close and host hide clear held content and invalidate queued
refresh/relayout epochs. Inactive subscription/event callbacks return without scheduling editor work. One resize hook
updates an existing preview through the same guard; there is no polling or hide-every-frame workaround.

A **Live preview** switch beside Duplicate/Delete controls the companion for the session. It writes no player data.
The minus control still minimizes it. The explicit temporary world preview remains `ReminderDisplay.PreviewStart/Stop`;
it does not enable or show the editor companion. Closing Settings still ends that temporary world preview.

**Regression coverage (unit-tested):** deliberately keep the host individually shown after closing; schedule work before
close; then repeatedly change configuration, fire equipment/zone events, call Refresh/QueueRefresh/Show/Update and flush
queued timers. Each iteration asserts hidden. Further checks cover another active Settings page, reopening the same
pooled frame, content-only Update remaining hidden, When and catalog ownership/restoration, disabled preference across
refresh/reopen, explicit world preview independence and cleanup, and repeated close/reopen/refresh cycles. The real Window
unit test checks active-page state and restoration of opt-in materials on navigation. Simulator scenarios additionally
mutate and refresh three times after closing, try direct Show/Update, navigate away, disable/re-enable and verify normal
restoration. These checks run before the screenshot poses, rather than only checking the final hidden state.

**Affected files:** `Window.lua`, `pages/Reminders.lua`, `pages/RemindersPreview.lua`, `tests/test_reminders_settings.lua`,
`tests/test_settings_window.lua` and the existing simulator scenario. Core runtime evaluation, saved schemas and condition
transactions were not changed. **Real-client confirmation is still required:** after closing, spend time changing gear,
entering/leaving combat, changing zones/profiles and receiving ordinary reminder updates. The companion must stay hidden
until Reminders is explicitly reopened with Live preview enabled. Repeat after navigation, catalog/builder cancellation
and a disabled preview. Confirm Show on screen remains independent and temporary.

## Precision material calibration (previous pass)

Client evidence: `actual screenshots/ChatGPT Image Nov 10, 2026, 07_37_20 PM.png` (Wizard Oil Missing editor and preview).
The earlier client captures remain historical. Baseline simulator: `reminders-20261110-193657` (When, editor, catalog,
dirty footer; all passed 59–61 handler checks). The approved three mockups and actual baseline images were opened.

| Category | Reference | Baseline | Responsible source | Correction to verify | Rendered verification |
|---|---|---|---|---|---|
| Material colors | Neutral espresso / walnut / chestnut hierarchy | Similar brown across header, well and sample; orange When summary | `Material.PanelFace`, header/shell tiles | Scoped material roles; neutral When card | Reviewed in final When/editor: separate neutral roles replace the orange summary. |
| Texture frequency and strength | Fine, quiet grain | Strong wrinkles, diagonal mottling and repeated bands | style-v2 `dark/warm.tga` at native tiling scale | Derive fine high-pass grain from existing material; inspect tiled crops and runtime capture | Native crops reviewed; broad repeated wrinkles removed, finer residual grain retained. |
| Relative luminance | Dark header, walnut editor, warmer movable cards, recessed fields | Header continues editor leather; cards weakly separated | Workspace/preview faces and footer | Distinct baked surface fills and shallow relief | Final blank-region medians: header 24/20/17, editor 35/29/24, card 48/37/29. |
| Typography | Mixed-case serif headings, readable labels | Cinzel's small capitals and undersized controls | `ReminderFont` inherits title font; control size 12 | Scoped Spectral headings and readable sans labels; locale fallback preserved | Scoped Spectral/Alegreya fonts and 13–17 unit labels configured; actual font rendering remains a client check. |
| Geometry and spacing | Emphasized art/Choose, comfortable editing proportions | Compact art dropdown cluster; large unused client space | `ShowSection.Layout` | Larger art tile and explicit Choose control; measured spacing without stretching all panels | Final taller editor shows larger art/Choose area, wider text field and aligned matching-height preview. |
| Frames and borders | Layered aged-bronze relief | Thin straight rims and square fittings | `WorkspaceFrame` and guild-bank shell | Restrained inner rim; retain painted shell and hinge | Final normal/narrow frames reviewed; hinge retained, shallow inner rim added. Corners still differ. |
| Buttons and controls | Smooth wells, dimensional primary/secondary actions | Busy wells; weak enabled Save emphasis | `ReminderControl`, slider | Scoped calibrated sheets; antique-gold enabled Save | Enabled Save has strongest gold fill; catalog/New retain quieter faces. Diagnostics dropdown wrap corrected. |
| Artwork and icons | Condition identity separate from reminder artwork | Weapon-enchant condition uses the oil bottle | `Pl.ApplyArt` | Reuse suitable weapon icon for condition only; preserve chosen reminder art | Crossed weapons identify enchant conditions; saved reminder oil/staff artwork is preserved. |
| Interaction states | Restrained bronze hover, selected/disabled clear | Hover wash can cover art; selection weak | `MaterialHover`, selected slices | Put hover behind art; consistent rim and selected face | Hover, drag and scaled menu captures reviewed; real pointer delivery remains client-only. |
| Window consistency | Shared materials, distinct dark header bands | Settings, builder and preview repeat the same coarse grain | Window shell, companions | Opt-in shell overlays active only on Reminders; scoped companion roles | Taller preview matches editor height. Window unit test verifies ordinary page materials restore. |
| Location chips | Rounded chips and visible additive entry | Choose disappears when both supported places selected | `LayoutBasic`, `card.choose` | Retain visible disabled Choose when all available values selected, with explanation | Rounded chips and Choose remain visible; Choose disabled with explanatory help when both supported places are selected. |

### Calibration and comparison evidence

New materials are deterministic derivatives of the existing style-v2 leather, built with
`python3 -B tools/make_reminder_materials.py`. A periodic high-pass removes broad wrinkles before reduction to a fine
128-pixel tile; bounded residual grain is recolored by surface role. Existing source/runtime style-v2 files are unchanged.
The existing rounded-sheet builder supplies shallow beveled 32-pixel faces with real alpha. This creates twenty 32-bit
uncompressed TGAs under `!!!TwichUI/media/reminders/materials/` (ten roles, grain + face); runtime formats and clear/opaque
pixels were inspected. The generator and preview PNGs remain in excluded tools/test-output locations. No AI image calls,
new paid service or new illustration placeholders were needed. The previous hinge, illustrated frame, reminder art and
native crossed-weapons icon are reused.

- Baseline `193657` was followed by material passes `194621` and `194911`, all four poses in each passing 65–67 and
  65–67 checks respectively. The renders were opened. The first pass exposed a wrapped tab; the next fixed text
  measurement and the cramped Appearance layout.
- The expanded run `195441` passed seventeen poses and failed the new taller-preview geometry check. It showed the old
  height after a height-only resize. One guarded Settings resize hook corrected that issue; the next run passed it.
- `200019` passed all ten requested refinement poses, 65–68 checks each. Normal/tall editor, When, catalog, dirty footer,
  scaled menu, context help, drag insertion, narrow layout and situation disclosure were opened and compared. Review
  caught the situation selector's long label wrapping; its available width and single-line presentation were corrected.
- `200526` passed final taller editor and catalog, 66 and 65 checks, after quieter ordinary action buttons and consistent
  editor section headings. Both images were opened.

Crops: [header](../../test-output/reminders-calibration/header-reference-before-final.png),
[editing well](../../test-output/reminders-calibration/editor-reference-before-final.png),
[condition card](../../test-output/reminders-calibration/card-reference-before-final.png).
Each strip reads approved reference → baseline → final, at native scale with no contrast enhancement. Crop coordinates
and encoded RGB/luma samples are in `test-output/reminders-calibration/samples.txt`. They support tone/grain comparison,
not similarity percentages. The reference/header sample has a brighter local tone than its empty editing well; the
current explicit instruction to make the header darker is followed rather than mechanically reproducing those pixels.
Final header/editor/card medians are 24/20/17, 35/29/24 and 48/37/29. Encoded luma grain deviations are 0.87, 1.17 and 1.55,
compared with baseline 2.58, 2.61 and 1.86. Grain frequency and actual screenshots, not variance alone, informed acceptance.

Final screenshot paths:

- [When](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200019/when.png),
  [dirty footer](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200019/dirty.png),
  [scaled menu](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200019/scale.png),
  [hover/help](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200019/actions.png),
  [drag](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200019/drag.png) and
  [narrow](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200019/narrow.png).
- [Main editor + height-matched preview](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200526/editorTall.png),
  [default-size editor](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200019/editor.png),
  [situation disclosure](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200840/situation.png),
  [catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261110-200526/catalog.png).

**Remaining differences:** frame corners/rail construction retain the existing painted assets; the left sample is
walnut rather than parchment. The main editor retains the actual Settings navigation and compact window constraints;
at the minimum window height some secondary actions require scrolling. Preview uses a calm dark well rather than scene
art. The simulator substitutes Friz for every addon font and its Issue report overlay obscures small parts of several
captures. Actual Spectral/Alegreya typography, pointer precision, scaling and material contrast still require the client.
No numerical likeness score or real-client visual acceptance is claimed.

**Files changed in this pass:** `Material.lua`, `Widgets.lua`, `Window.lua`, `pages/Reminders.lua`, `RemindersEditor.lua`,
`RemindersDesigner.lua`, `RemindersPlain.lua`, `RemindersPreview.lua`, `RemindersBuilderRail.lua`; the Reminders settings
and Settings window tests; `tools/make_reminder_materials.py`, twenty material TGAs, existing simulator scenario/runner;
this record, `docs/reminders.md`, `docs/reminders-style-upgrade.md` and `STATUS_AND_BACKLOG.md`. The existing dirty core,
artwork, workspace and earlier implementation work is preserved on `feature/style`. No commits, deployment or live data
changes were made. The focused `test_reminders_settings.lua`, `test_reminders_wellfed.lua` and `test_settings_window.lua` runs passed.
Both full `./tests/run.sh` runs passed **187 tests, zero failures**, including the final full run recorded in
`/tmp/twichui-calibration-tests-final-20261110.log`. The first run is `/tmp/twichui-calibration-tests-20261110.log`. Lua 5.1 syntax, `bash -n tools/simlab/reminders.sh` and `git diff --check` pass. Material
TGAs were checked for format, dimensions and rounded-sheet alpha. Final simulator commands were:

- `bash tools/simlab/reminders.sh when editor editorTall catalog dirty scale actions drag narrow situation` — all ten
  poses passed, 65–68 checks each (`200019`).
- `bash tools/simlab/reminders.sh editorTall catalog` — 66 and 65 checks passed (`200526`).
- `bash tools/simlab/reminders.sh situation` — 65 checks passed after widening the long-value selector (`200840`).

All listed final screenshots were opened. The full eighteen-pose run's earlier tall-preview failure and correction are
recorded above; no blanket pass is claimed for that earlier run.

`SIMLAB_PAGE=reminders SIMLAB_TITLE=Reminders bash tools/simlab/smoke.sh` constructed 56/56 pages with no construction
error and no missing TwichUI texture. Its overall verdict is FAIL for the documented simulator addon-message limitation,
`Lua error: Lua Error: string at argument 2 is not valid UTF-8` (three occurrences in this run).
[Smoke evidence](../../../wow-ui-sim-lab/artifacts/smoke-20261110-200725/run.stderr).
Neither simulator internals nor runtime message behavior was changed to conceal it.

The P0 source fix and visual corrections are unit/handler tested and screenshot reviewed. Real-client acceptance is
pending, especially sustained ordinary gameplay after closing, installed fonts, actual pointer input, scaling,
combat cleanup and reload persistence.

## Modal alignment and material correction (previous pass)

This section supersedes the earlier connector, material and interaction notes below. The focus is the user's
modal correction brief. The workspace, private draft transaction and lossless Location adapter remain in place.
The approved When, preview and catalog images and supplied actual-client captures were reviewed. No later client
capture than `Screenshot 2026-11-10 165245.png` is present here, so the reported modal click problem was investigated
from code and simulator geometry rather than reproduced with real client input.

| Priority | Discrepancy | Correction and evidence | Remaining boundary |
|---|---|---|---|
| P0 | Invisible Settings controls could compete with modal input at HIGH strata | While mounted under the workspace, Settings moves to LOW and returns to its exact prior strata on close. The HIGH modal is top-level and raised on show. Unit tests cover repeated mounting and restoration; simulator checks cover Cancel, Save, direct Settings close and reopening. | True pointer hit routing requires the client. |
| P0 | Tooltip and drag coordinates did not follow modal scale | Context help matches the owner's effective scale before anchoring. All builder help uses it. The drag ghost uses its own effective scale for physical cursor coordinates and centers under the pointer. Tests check physical bounds, clipping, ghost center and tooltip ownership at multiple scales. Menu edge and owner scale checks pass at 72% workspace scale. | Real mouse hover/drop delivery is not simulated. |
| P1 | Ladder-like bridge and detached preview | One generated bronze fitting replaces the assembled rails. Preview uses the same fitting and illustrated corner/rail shell as Settings and the workspace. The fitting takes no mouse and hides when preview is minimized or overlaid. | Its leaf/rivet silhouette differs from the reference hinge. |
| P1 | Crushed backgrounds and inconsistent shell tones | Lifted neutral espresso leather in headers, navigation, wells, workspace, preview and footer. The main Reminders page opts into a leather header. Inner cards remain warmer and controls recessed. | Grain and corners retain the existing source asset treatment. |
| P1 | Appearance sample disappears into its well | Raised walnut sample, fine bronze rim and the existing isolated display renderer. Reviewed with the oil art and words at runtime size. | This remains walnut rather than the reference's parchment. |
| P1 | Default-looking numeric sliders and detached value boxes | Optional material slider uses the existing switch-thumb art tinted bronze, a recessed track, bronze fill, hover/drag states and framed value field. Reminders opts in. Native callbacks, typed entry and disabled-state refusal are simulator handler-tested. | Client drag feel and high-scale hit area remain acceptance checks. |
| P1 | Closed controls were styled but popup rows were generic | Opt-in leather menu, bronze selected/hover rows, rim, track and thumb. The reused popup restores its prior appearance for ordinary Settings controls. Unit tests cover selection, close, style restoration and listener reuse. | No addon-wide menu rollout. |
| P2 | Hover feedback weak or gray | Restrained gold rims on cards, rows and material controls, including focused text fields. Dropdown hover no longer adds the gray default wash. | Review contrast with installed fonts in game. |
| P2 | Wheel movement jumps too far | Existing native scrollbars use 16-unit wheel steps in palette, rules, diagnostics, list and catalog, preserving the template's thumb/arrow handlers. | Real wheel and thumb delivery remain client checks. |
| P2 | Well Fed wording was awkward | Cards offer Well fed / Not well fed; summaries say “you are not well fed.” Existing provider values and stored predicates are unchanged. | Advanced expressions retain explicit AND/OR language. |
| P2 | Save looked like a flat beige rectangle | Reused rounded raised texture with restrained additive antique-gold treatment and a bronze rim. Disabled state remains dark and cannot commit. | Its primary emphasis is subtler than the render's gold fill. |

### Iteration and screenshots

- `reminders-20261110-191401`: initial corrected modal, main editor, targeting menu and 72% workspace. Four poses passed
  56–59 checks each. Opened all four images; checked fitting, leather contrast, popup edges and scaled layout.
- `reminders-20261110-191817`: all 17 poses passed 56–59 handler/state checks each. Opened editor, catalog, basic and nested
  When, drag ghost, constrained workspace, dirty footer, situation reveal and contextual help. These captures prompted
  replacing Save's flat fill and the main editor's gray header.
- `reminders-20261110-192141`: editor, scaled menu, help and Well Fed passed 59–62 checks each, adding native slider and
  typed numeric-field callbacks, disabled slider refusal and actual dropdown row selection.
- `reminders-20261110-192244/dirty.png`: final textured Save treatment, 61 checks passed; screenshot opened.
- Final correction captures: `reminders-20261110-192348` (links below). All eight poses passed 59–62 handler/state checks.
  All eight images were opened alongside the approved images. The main header now shares the shell leather, the
  dropdown and help follow their owners, and the textured Save state is distinguishable without a flat opaque fill.

Primary final images:

- [Main editor and preview](../../../wow-ui-sim-lab/artifacts/reminders-20261110-192348/editor.png).
- [When workspace](../../../wow-ui-sim-lab/artifacts/reminders-20261110-192348/when.png),
  [unsaved footer](../../../wow-ui-sim-lab/artifacts/reminders-20261110-192348/dirty.png),
  [targeting menu](../../../wow-ui-sim-lab/artifacts/reminders-20261110-192348/menu.png),
  [72% scale menu](../../../wow-ui-sim-lab/artifacts/reminders-20261110-192348/scale.png),
  [context help](../../../wow-ui-sim-lab/artifacts/reminders-20261110-192348/actions.png),
  [Well Fed](../../../wow-ui-sim-lab/artifacts/reminders-20261110-192348/wellfed.png).
- [Catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261110-192348/catalog.png).
- [Nested rule](../../../wow-ui-sim-lab/artifacts/reminders-20261110-191817/nested.png),
  [drag representation](../../../wow-ui-sim-lab/artifacts/reminders-20261110-191817/drag.png),
  [1280 × 800 layout](../../../wow-ui-sim-lab/artifacts/reminders-20261110-191817/narrow.png),
  [situation reveal](../../../wow-ui-sim-lab/artifacts/reminders-20261110-191817/situation.png).

### Final comparison findings

- **When:** the two-panel workspace, trigger/restriction organization, separate targeting, chips and persistent footer
  follow the approved composition. Neutral leather is visible throughout. Remaining differences are the existing square
  corner fittings, relatively fine trim, reused oil/map illustrations, walnut sample instead of parchment and subtler Save
  emphasis. Advanced rules deliberately retain explicit grouping. There are no new illustration placeholders.
- **Editor/preview:** the common illustrated shell and bronze fitting visually connect the preview; header, cards and
  controls now share neutral materials. The existing navigation and compact settings dimensions remain. The preview
  canvas is leather rather than the mockup's scenic backdrop, and its text/art follow the actual display configuration.
- **Catalog:** illustrated two-column cards, search/categories and separate Custom action remain intact, with matching
  shell and neutral surfaces. Its fifth supported template scrolls below the first four. Artwork silhouettes and card
  typography differ from the render; the simulator substitutes Friz for installed addon fonts.
- The simulator's own Issue report widget overlaps parts of the bottom region in several captures. It was not removed
  or worked around in production code. Screenshots were reviewed for layout/material evidence, not client acceptance.

### Connector source and runtime preparation

Generation method: one built-in imagegen call, using the already authorized Codex account route. No API fallback,
credential change, package installation or separately configured service was used. Generated original:
`/home/rich/.codex/generated_images/01a1c775-9ca2-7251-89ec-c08c2c88ab9a/exec-243db7ee-bf6c-49c6-a3ea-bd47d7b8e98f.png`.
The original was copied to [assets/reminder-connector-source.png](../../assets/reminder-connector-source.png).
The source is a 1254 × 1254 RGBA PNG. Exact decoding finds 1,213,549 alpha-zero pixels, 358,459 partially transparent
pixels and 508 fully opaque pixels, spanning alpha 0–255. Transparency is actual alpha, with no checkerboard.

`python3 -B tools/make_reminder_connector.py` uses the existing premultiplied resampler and RGB bleed helpers and writes
`!!!TwichUI/media/reminders/connector.tga` (128 × 128) and `connector-small.tga` (64 × 64), uncompressed 32-bit TGAs
with eight alpha bits. Their alpha ranges are 0–254 and 0–253, with 9,716 and 2,486 fully clear pixels respectively.
The 64-pixel inspection PNG was opened; the 64-unit builder and 44-unit preview fittings were also reviewed on their
actual dark leather surroundings. The silhouette remains recognizable and no opaque matte was visible.
Inspection PNGs are in `test-output/reminder-connector/`. `.pkgmeta` excludes `assets`, `tools`, `docs` and now
`test-output`; source and inspection images are outside runtime directories.

Exact generation prompt:

> Use case: stylized-concept. Asset type: one standalone reusable fantasy game UI frame connector on actual transparent background. A small vertically oriented hand-painted antique aged bronze hinge fitting joining two leather UI frames across a narrow gap. Frontal orthographic view, symmetric left and right short rounded mounting wings and a central raised leaf-shaped bronze knuckle, gently faceted and worn, tiny restrained rivets, dimensional painted highlights at upper left and dark patina in crevices. Quiet premium fantasy craftsmanship, warm neutral bronze and muted antique gold, blackened recesses, no copper-red wash. The fitting should occupy a compact approximately 4:5 silhouette and remain recognizable when displayed at 44 by 56 pixels. Center the complete fitting with comfortable transparent padding on square canvas. Only the fitting itself, no panels, no UI screenshots, no text, no letters, no border around canvas, no scaffolding, no ladder-like bars, no glow, no external cast shadow, no background. Save the generated image locally and report its exact local path.

### Code and evidence

This pass changes `Material.lua`, `Widgets.lua`, `Window.lua`, `pages/MagicInventoryDrag.lua`, the Reminders page,
editor, designer, rail, preview, catalog and plain-language helper; the corresponding Settings, Reminders and Well Fed
tests; the existing simulator scenario and runner; `.pkgmeta`; and the existing progress documents. It adds only the
connector source, its two runtime TGAs and `tools/make_reminder_connector.py`. Earlier dirty work is retained, including
other reminder art and `pins/TwichUI.code-workspace`. The saved-data schema and rule evaluation engine are unchanged.

Both full `./tests/run.sh` runs passed 187 tests, zero failures, including the final production Lua and material changes.
Focused commands for `test_reminders_settings.lua`, `test_settings_window.lua` and `test_reminders_wellfed.lua` passed.
Changed Lua and the scenario pass `luac5.1 -p`; the runner passes `bash -n`; the new Python preparation script parses;
`git diff --check` passes. Exact suite logs are `/tmp/twichui-reminders-tests-20261110.log` and
`/tmp/twichui-reminders-tests-final-20261110.log` (local test output, excluded from the addon).

`SIMLAB_PAGE=reminders SIMLAB_TITLE=Reminders bash tools/simlab/smoke.sh` constructed 56/56 pages without a construction
error and found no missing TwichUI textures. Its overall verdict is **FAIL**, from the same documented simulator
addon-message error: `Lua error: Lua Error: string at argument 2 is not valid UTF-8`.
[Smoke evidence](../../../wow-ui-sim-lab/artifacts/smoke-20261110-192556/run.stderr).
No simulator engine or production message behavior was changed to hide it.

Unit and scripted handler evidence cannot prove real cursor delivery. The modal should not be considered
client-accepted until the following checks pass:

1. At normal and higher UI scale, click visible field centers/edges, hover cards and help, open dropdown rows and verify
   selection exactly under the pointer. No invisible Settings row may react. Drag over insertion edges and cancel outside.
2. Check wheel increments and thumb drag; numeric slider drag, typed value and disabled state; menu hover and scrolling.
3. Change a draft, Undo/Redo, Cancel, reopen, Save, close via Escape and Settings, and reopen. Confirm Settings restores
   input and opacity, targeting is correct, no world preview is orphaned and saved values persist after `/reload`.
4. Review materials and text with actual fonts, test negative/mixed Advanced rules and check combat cleanup.

## Dedicated When workspace alignment

This pass compares the supplied [client screenshot](<actual screenshots/Screenshot 2026-11-10 165245.png>),
the preceding simulator build `reminders-20261110-180029` and the approved
[When composition](REMINDERS_WHEN_BUILDER.png). The client screenshot is the latest actual-client file available in this directory.
The following changes supersede the earlier shell and location-presentation limitations recorded below.

| Priority | Visible discrepancy | Implemented correction | Evidence |
|---|---|---|---|
| P1 | Full Settings competes with the attached builder | Dedicated left reminder rail and right rule panel. Settings remains mounted and returns on Save, Cancel or close. | Unit-tested and simulator handler-tested |
| P1 | Missing left summary and appearance sample | Scrollable, selectable reminder list, selected reminder well, concise When explanation, Edit conditions entry and isolated display-renderer sample. | Screenshot-reviewed |
| P1 | Flat frame and mismatched surfaces | Both panels reuse illustrated guild-bank corners and bronze rails over neutral espresso. Bronze straps and a pin join the frames. | Screenshot-reviewed |
| P1 | Reminder names truncate too early | A wider main list and two-line names. The builder rail also wraps names and makes full names available on hover. | Screenshot-reviewed with a long sample name |
| P1 | Weak palette hierarchy and button-like catalog entries | Larger headings, category dividers, larger art and restrained textured row hover. One Location entry, Class and Specialization precede Combat. Well Fed is under Other. Filters and search remain active. | Unit-tested, simulator handler-tested and screenshot-reviewed |
| P1 | Dense card alignment and prominent Actions dropdown | Larger card padding, aligned title/state/fields, a compact hover menu and a local material tooltip. | Screenshot-reviewed |
| P1 | Location alternatives require Advanced logic | Removable Dungeon/Raid chips over an existing Any group. Additive selection uses the validated draft mutation path. Other groups retain Advanced logic. | Unit-tested for OR, unknown, negation and refusal rollback |
| P1 | Advanced logic looks like a primary button | Quiet disclosure row. Complex rules keep their controls and original tree. | Screenshot-reviewed |
| P1 | Try a situation inserts controls among conditions | Details and situation testing reveal a separate bottom scroll region. Current saved visibility remains distinct from draft simulation. | Unit-tested, simulator handler-tested and screenshot-reviewed |
| P1 | Footer lacks icon and action hierarchy | Persistent separated band, Undo/Redo icons, centered unsaved indicator, secondary Cancel and antique-gold Save. | Screenshot-reviewed in clean and dirty states |
| P2 | Close, For and hover help clash with the shell | Material close control, larger framed targeting dropdown and opt-in context tooltip. | Screenshot-reviewed |

### Visual iteration

- `reminders-20261110-183113` established the dedicated pair. Review exposed a gray shell fill and absent crest sizing.
- `reminders-20261110-183416` corrected the shell material and rendered the location chips. The right card and left rail
  then shared the neutral palette.
- `reminders-20261110-183808` exposed a gray hover wash, an unsupported disclosure glyph and overlapping main-list state text.
  Textured hover, a drawn chevron and greater two-line row height corrected them. Increasing workspace height made the Combat
  catalog entry visible at the default scale.
- `reminders-20261110-184142` covered the paired shell, footer, chip group, contextual menu and constrained layout.
  The final capture set adds the direct Settings-close restoration check and sizes the bottom reveal to its content.

### Final captures

All links below point to actual addon screenshots. The relevant captures were opened and compared with the approved render.

- [Basic builder](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/when.png),
  [complex rule](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/nested.png),
  [1280 × 800 workspace](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/narrow.png).
- [Drag/drop](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/drag.png),
  [unsaved footer](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/dirty.png),
  [validation refusal](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/error.png).
- [Situation reveal](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/situation.png),
  [Details reveal](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/details.png),
  [contextual actions](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/actions.png).
- [Main editor and preview](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/editor.png),
  [template catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261110-184614/catalog.png).

The composition now has the requested two-panel organization. Remaining material differences include simpler hinge
detail, the reused oil/map artwork, and the dark live-renderer sample in place of the mockup's parchment-backed card.
The grain and frame corners also retain the existing asset treatment. The simulator substitutes addon fonts and its
Issue report widget overlaps part of some captures. Client typography and pointer behavior require acceptance in game.

### Implementation files

- `TwichUI_Settings/pages/RemindersBuilderRail.lua` adds the paired workspace, rail, hinge and isolated sample.
- `RemindersDesigner.lua` and `RemindersPlain.lua` implement the revised card, location adapter and bottom evaluation layout.
- `Reminders.lua` and `RemindersEditor.lua` improve the main list and scoped material consistency.
- `TwichUI_Settings/Material.lua` adds opt-in workspace framing, textured hover, chips and context help.
- `Widgets.lua` adds compact menu buttons. `Window.lua` exposes the opt-in workspace presentation switch and preserves its mounted page.
- `TwichUI_Settings.toc` loads the rail before the designer. Interface and version metadata are preserved.
- `tests/test_reminders_settings.lua`, `test_reminders_designer.lua`, `test_reminders_wellfed.lua` and
  `test_settings_window.lua` cover the new behavior. The existing simulator scenario and runner include the additional poses.
- This record, `docs/reminders.md`, `docs/reminders-style-upgrade.md` and `STATUS_AND_BACKLOG.md` carry the current contract.

The existing `media/guildbank/frame-*.tga`, `media/style-v2/*.tga`, reminder artwork and game undo atlas are reused.
This pass adds no bitmap files or generated artwork. The saved rule schema and canonical configuration APIs are retained.
Changes remain uncommitted on `feature/style`. Existing uncommitted art, workspace and earlier implementation changes are preserved.

### Verification boundaries

`bash tools/simlab/reminders.sh` passed all 14 poses with 55–57 handler/state checks each. The scenario verifies alpha
restoration, clean rail selection, draft isolation, Save/Cancel, closing Settings with a dirty draft, condition movement,
canceled/rejected drops, preview isolation and narrow placement. The simulator drives registered handlers and a scripted
cursor. It does not establish real mouse delivery, combat safety, taint or saved data surviving a client reload.

`./tests/run.sh` passed 187 tests with zero failures. The focused Reminders settings, rule presentation, groups,
Well Fed, Settings window and packaging tests passed. `luac5.1 -p` passed on the changed Lua files,
`bash -n tools/simlab/reminders.sh` passed and `git diff --check` passed.

`SIMLAB_PAGE=reminders SIMLAB_TITLE=Reminders bash tools/simlab/smoke.sh` constructed 56 of 56 pages without
a construction error and found no missing TwichUI texture. Its screenshot verdict returned FAIL for the documented
addon-message limitation, `Lua error: Lua Error: string at argument 2 is not valid UTF-8`.
[Smoke log](../../../wow-ui-sim-lab/artifacts/smoke-20261110-184837/run.stderr).

Real-client acceptance should cover both scroll thumbs and wheel input, card and group drags, negative and mixed
Advanced rules, chip additions and removals with Undo/Redo, Save/Cancel and Escape confirmation, rail selection,
Settings restoration, higher UI scales and `/reload` persistence. Review the installed Cinzel typography and actual
frame/material contrast before visual acceptance.

## When builder usability corrections

Compared the supplied [client capture](<actual screenshots/Screenshot 2026-11-10 165245.png>), the preceding simulator
build and the approved [When render](REMINDERS_WHEN_BUILDER.png). The basic editor uses the first stored condition
as its trigger and the remaining flat All conditions as restrictions. Existing nested, Any and unsupported rules
open in Advanced logic. Scope remains a separate saved field.

| Priority | Discrepancy | Correction and evidence |
|---|---|---|
| P0 | Edits reached the live rule before the builder closed | Private rule and scope draft with validation, conflict detection, Undo/Redo, Save and Cancel. Unit and simulator handler tests verified one live revision on Save and none on Cancel, invalid Save or draft operations. |
| P0 | Player checks could show unrelated controls in secondary editors | Direct fields and secondary editors use the same provider choices. Unit tests checked mounted, location, shield and required item controls. |
| P1 | Red-brown surfaces and weak separation | Espresso wells, warm walnut cards and muted rails. The final nested capture replaced a flat gray group fill with the reusable espresso treatment. |
| P1 | Search, targeting and evaluation looked like form controls | Recessed Search... with magnifier, stronger category dividers, opt-in native scrollbar, header For dropdown, text-only evaluation states and a dedicated visibility region. |
| P1 | Drag preview hid the target and the restriction action lacked a drop outline | The leather ghost carries the originating icon and label beside the cursor. The dashed target and insertion line remain visible. Simulator handlers exercised valid, canceled and rejected drops. |
| P1 | The footer lacked Save and Cancel | Persistent footer with draft history and unsaved indicator. The validation capture shows the refusal above the footer. The narrow capture shows the footer inside the overlay. |

The revised captures were opened and compared. The last color pass increases contrast on Save while keeping its
antique-gold treatment. Existing runtime artwork and eye icons were reused. No new source or runtime bitmaps were
needed for this pass. The builder stays in the shared settings shell. Its art, frame details and proportions differ
from the dedicated mockup. Dungeon and Raid alternatives use an existing Any group in Advanced logic. The simulator
substitutes fonts and places its own Issue report overlay over parts of the left footer in some views.

- [Basic When](../../../wow-ui-sim-lab/artifacts/reminders-20261110-180029/when.png),
  [advanced When](../../../wow-ui-sim-lab/artifacts/reminders-20261110-180029/nested.png) and
  [1280 × 800 overlay](../../../wow-ui-sim-lab/artifacts/reminders-20261110-180029/narrow.png).
- [Unsaved changes](../../../wow-ui-sim-lab/artifacts/reminders-20261110-180320/dirty.png),
  [validation refusal](../../../wow-ui-sim-lab/artifacts/reminders-20261110-180320/error.png) and
  [drag insertion](../../../wow-ui-sim-lab/artifacts/reminders-20261110-180320/drag.png).
- [Editor and preview](../../../wow-ui-sim-lab/artifacts/reminders-20261110-180029/editor.png) and
  [template catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261110-180029/catalog.png) were opened for regression review.

`bash tools/simlab/reminders.sh` passed 49–51 handler and state checks in each of 11 poses. The final dirty, error and
drag captures passed 51, 51 and 50 checks. Lua 5.1 syntax, `git diff --check` and `./tests/run.sh` passed
(187 passed, 0 failed). The focused settings and rule tests cover existing condition data, group folding and restoration, conflicting saves, targeting isolation,
required item validation and inferred icon cleanup. Real-client checks are in [the Reminders checklist](../reminders.md#in-game-checklist).
In particular, verify mouse drag delivery, wheel and thumb scrolling, typography at different UI scales, Escape
and confirmation handling, persistence after `/reload` and behavior around combat.

## UX simplification and visual refinement

The before-state client captures are [editor help](<actual screenshots/Screenshot 2026-11-10 164816.png>), [editor and preview](<actual screenshots/Screenshot 2026-11-10 165221.png>) and [nested When builder](<actual screenshots/Screenshot 2026-11-10 165245.png>). These were reviewed beside the original mockups. They show the prior implementation running in the client.

### Baseline discrepancies

Fresh simulator baseline `reminders-20261110-165438` covers the editor, preview, catalog, simple rule, nested rule and constrained layout. P0 indicates a functional or access problem. P1 indicates a material composition, hierarchy or readability issue. P2 and P3 indicate secondary styling and polish.

| Rank | Editor | Live preview | When builder | Catalog |
|---|---|---|---|---|
| 1 | P1 Expanded feature help displaces editing | P1 Canvas blends into its surround | P0 Common values require opening the separate editor | P1 Cards and shell are too close in tone |
| 2 | P1 Appearance reads as a stack of fields | P1 World preview button reads as a momentary action | P1 Flat rules expose Boolean controls | P1 Illustration has too little presence |
| 3 | P1 Appearance lacks an artwork picker tile | P1 Header and reminder name sit too close | P1 Trigger and restrictions have nearly equal presentation | P1 Custom action looks like another narrow button |
| 4 | P1 Advanced and Test occupy separate large cards | P1 Visibility and sample information compete | P1 Edit and More repeat on every card | P2 Shorter card title and action hierarchy than reference |
| 5 | P1 Master control occupies a second heading row | P1 Size segments have small hit areas | P1 Tiny, sometimes repeated condition artwork | P2 Search and filters feel detached from cards |
| 6 | P1 When repeats the full rule sentence | P2 Lower actions lack a divider | P1 Background, groups and cards lack depth separation | P2 Third row starts within first viewport |
| 7 | P1 Group and item warnings are wordy | P2 Canvas is short relative to window | P1 Status is hidden behind a long explanation | P2 Footer copy has little separation |
| 8 | P2 Selected row leans on a bright straight bar | P2 Fit readout crowds visibility | P1 Add restriction looks like a secondary row button | P2 Hover can obscure card artwork |
| 9 | P2 List artwork and name feel undersized | P2 Panel moves more than needed when docking | P1 The active reminder list is obscured in the default overlay | P2 Original shell is thinner than the target |
| 10 | P2 Default settings height hides advanced controls | P3 Game-renderer layout varies with each reminder | P2 Scope editor dominates the top of the rule pane | P3 Standalone illustrations have different silhouettes than the mockup |

### Implementation and mapping

- The basic view applies to flat, supported All rules. The first stored condition appears under Show a reminder when. Subsequent conditions appear under Only while. All conditions still use the same conjunction. A reorder changes the presentation and stored order through the existing move validator.
- Any roots, nested groups and unreadable or unsupported rules open Advanced logic. Known provider-level negation appears as a real operator in the basic view when it can be represented directly. No conversion is performed to enter either view. Same-provider edits retain the existing node table and its extension fields. Switching provider continues to replace the predicate through the existing validated editor.
- Basic cards have a restrained grip, one contextual menu, observed state and inline fields. Item conditions provide a direct choose/change action. A palette drop opens a draft at the intended slot and checks for stale rules before confirmation. Canceled and rejected operations retain the existing rule.
- The page header carries the master switch and short help. Appearance has an artwork tile and grouped controls. A concise When summary and actionable warnings replace the large blocks. Advanced and Diagnostics share one row. Preview rendering and scale remain isolated, with the explicit on-screen preview on a pill switch.
- Opt-in `SettingsMaterial.PanelFace` centralizes raised cards, editing wells and inset canvases using existing style-v2 slices and grain. The shared Cards header placement and switch labels are opt-in. The layouts and rule presentation remain feature-specific. This is the Reminders prototype. A TwichUI-wide pattern guide follows visual and functional acceptance.
- Artwork is reused. Oil and plate use `!!!TwichUI/media/reminders/enchant*.tga` and `wellfed*.tga`. Equipment, ammo, location, class, specialization, death, ghost and resting use `!!!TwichUI/media/icons/{gearComparison,ammunition,mapsNavigation,profiles,classResources,resurrection,releaseSpirit,sleepingBag}[-small].tga`. Combat and mounted use the client's `Interface/Icons/Ability_DualWield` and `Ability_Mount_RidingHorse` with a mild tint. This pass adds no bitmap files.

### Iteration and remaining differences

- The first revised run `reminders-20261110-170526` separated primary and restriction cards, added inline editing and removed duplicate explanations. Its lighter surround, long enchant choice, low priority for location in the palette and wasted space above the rule were visible in the captures.
- The second run `reminders-20261110-171201` darkened the surround, shortened choices, moved targeting into the header, raised location and class entries and introduced list-adjacent docking. It showed that the builder needed to align with the top of settings and that the master switch still consumed useful editor height.
- The final run aligns the builder to settings, retains the list when it fits and moves the master switch into the page header. At constrained width the builder uses a scrollable overlay. It retains the existing settings navigation and per-edit transaction contract. Location alternatives involving Any remain in Advanced logic. The catalog continues to show five templates and preserves the shared settings shell. The simulator uses substitute fonts, so client typography and actual pointer interaction remain pending.

### Final simulator captures

- [Editor and preview](../../../wow-ui-sim-lab/artifacts/reminders-20261110-171453/editor.png), [basic When](../../../wow-ui-sim-lab/artifacts/reminders-20261110-171453/when.png), [nested When](../../../wow-ui-sim-lab/artifacts/reminders-20261110-171453/nested.png), [catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261110-171453/catalog.png) and [1280 × 800 overlay](../../../wow-ui-sim-lab/artifacts/reminders-20261110-171453/narrow.png) were opened and reviewed.
- [Drag insertion](../../../wow-ui-sim-lab/artifacts/reminders-20261110-171453/drag.png) and [condition artwork](../../../wow-ui-sim-lab/artifacts/reminders-20261110-171453/palette.png) show the insertion line and the mount, ghost, death and resting artwork at palette scale.
- `bash tools/simlab/reminders.sh` passed 45–47 handler and state checks per pose. It exercised same-node inline editing, draft confirmation at the indicated insertion slot, reorder, regrouping, cancellation, preservation of nested rules, filtering and preview isolation.
- `SIMLAB_PAGE=reminders SIMLAB_TITLE=Reminders bash tools/simlab/smoke.sh` constructed all 56 pages. The screenshot pass returned FAIL with `string at argument 2 is not valid UTF-8` from the simulator's documented addon-message limitation in the group hello. [Smoke log](../../../wow-ui-sim-lab/artifacts/smoke-20261110-171616/run.stderr)
- Lua 5.1 syntax, `git diff --check`, the eight focused Reminders and settings tests, and the full `./tests/run.sh` passed. The full run reported 187 passed and 0 failed.

### Earlier implementation verification

The complete revision follows the [requirements handoff](<../../Project Revision - Complete Requirements and Design Handoff.md>) and the three original renders in this directory. The current scope includes Actual size and Fit, catalog filters and rule drag-and-drop. The revision is uncommitted on `feature/style`.

## Implementation paths

- The editor, preview, catalog and When builder live under [TwichUI_Settings/pages](../../TwichUI_Settings/pages/). `RemindersRuleDrag.lua` binds the card, group and palette handles. The settings TOC includes that file.
- `Material.lua`, `Cards.lua` and `Window.lua` provide the opt-in control treatments, compact header and companion Escape behavior. [TwichUI_Settings](../../TwichUI_Settings/)
- The core move validator and shared display scale are in `Config.lua` and `Display.lua`. [Core reminders](../../%21%21%21TwichUI/reminders/)
- The focused settings test and isolated scenario cover the changed flows. [Settings test](../../tests/test_reminders_settings.lua), [simulator scenario](../../tools/simlab/scenarios/reminders.lua), [simulator runner](../../tools/simlab/reminders.sh)
- This record, the starter brief and the backlog reflect the new scope. The supplied handoff, original mockups, existing art sources, test outputs and workspace edit were preserved. [Upgrade brief](../reminders-style-upgrade.md), [backlog](../../STATUS_AND_BACKLOG.md)

## Visual comparison

Baseline screenshots were captured and opened before editing. [Editor](../../../wow-ui-sim-lab/artifacts/reminders-20261110-160647/editor.png), [catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261110-160647/catalog.png), [When](../../../wow-ui-sim-lab/artifacts/reminders-20261110-160647/when.png).

| Area | Severity | Baseline discrepancy | Revision result |
|---|---|---|---|
| Composition and proportions | High | Short reminder card, redundant header space, Sound below the fold and a narrow When pane. | The editor has a substantial scrolling list, compact header and visible Sound. The When palette and rules have independent scroll areas. Advanced and Duplicate/Delete still require scrolling at the default settings height. |
| Materials, edges and depth | Medium | Leather and bronze were present. The control faces and selected rows had little visual distinction. | Used chestnut faces, recessed fields, shallow rounded slices and localized bronze accents. The shared shell still has squarer, more continuous rails and more visible grain than the references. |
| Typography and color | High | Labels and headings were similar in size and weight. | Increased heading hierarchy and explicit text bounds after the first revised captures showed clipping. Readable in the final simulator poses. The game font fallback and game UI scale still require client comparison. |
| Controls and states | High | Square enable controls and subdued selection. Missing preview size controls and catalog filters. | Pill switches, rounded segments, stronger selected rows, catalog card hover, disabled Play and clearly separate preview visibility. Existing global settings search and navigation chrome remain. |
| Artwork | Medium | Illustrations were distinct but the card hierarchy was compressed. | Larger image wells and consistent card titles, descriptions and actions. There are five illustrated templates and a fixed Custom row. The fifth template scrolls into view. |
| Preview, filtering and When | High | The preview only reported fit. Catalog had no filters. When lacked a persistent palette. | Actual size and Fit, searchable catalog and persistent searchable condition palette exercised through their handlers. Condition feedback appears when expanded. |
| Drag and drop | High | No pointer-driven editing or insertion feedback. | Frame drag scripts, cursor ghost and valid insertion line reviewed in the simulator. The handlers exercise reorder, regrouping, canceled and rejected drops. Real mouse delivery is pending. |
| Overflow and narrow layout | High | The picker exceeded its container. Companions relied on whole-frame scaling. | The builder uses bounded scroll regions and an overlay fallback. The constrained screenshot shows both panes and its footer actions. Multi-scale client checks are pending. |

The final screenshots use 1600 × 1200 except the 1280 × 800 constrained pose. The simulator substitutes Friz Quadrata for addon fonts, uses an older Blizzard UI build and does not provide real mouse-event delivery for the scripted checks. The visible Issue Report control belongs to the simulator's Blizzard UI.

- [Editor and live preview](../../../wow-ui-sim-lab/artifacts/reminders-20261110-163556/editor.png) compared with [REMINDERS_PREVIEW.PNG](REMINDERS_PREVIEW.PNG). The scrollable list, selected row, pill switches, compact Appearance and When sections, visible Sound and attached preview follow the composition. The oil is shown at configured scale for this draft. The mockup's inline art picker and footer arrangement differ from the existing editor controls. The settings shell, feature tabs and profile bar remain.
- [Catalog](../../../wow-ui-sim-lab/artifacts/reminders-20261110-163556/catalog.png) compared with [REMINDERS_TEMPLATE_CATALOG.jpeg](REMINDERS_TEMPLATE_CATALOG.jpeg). Search, category segments, a two-column illustrated grid, Use template and a fixed Custom row are visible. The oil, shield, arrows and plate are standalone illustrations. A fifth card is accessible by scrolling. [Hover](../../../wow-ui-sim-lab/artifacts/reminders-20261110-163556/hover.png) and [no results](../../../wow-ui-sim-lab/artifacts/reminders-20261110-163556/empty.png) are separate poses.
- [When](../../../wow-ui-sim-lab/artifacts/reminders-20261110-163556/when.png) compared with [REMINDERS_WHEN_BUILDER.png](REMINDERS_WHEN_BUILDER.png). The searchable palette sits beside the targeting and rule cards, with group controls, restrictions and observed state. The 1600-wide viewport requires a centered overlay for the full settings window plus builder. The mockup uses a dedicated reminder rail, larger illustrations and inline edit controls. The implementation uses the existing per-edit controls and Back to appearance. [Drag](../../../wow-ui-sim-lab/artifacts/reminders-20261110-163556/drag.png) shows the scripted cursor ghost and insertion line. [Constrained layout](../../../wow-ui-sim-lab/artifacts/reminders-20261110-163556/narrow.png) shows the overlay and reachable controls.

## Requirements coverage

Complete means implemented and checked to the evidence level stated here. Partial means a visual or verification gap remains. Deliberately unchanged means the earlier runtime or shared UI contract continues.

| Requirement | Status | Evidence |
|---|---|---|
| FR-001–FR-003 | Complete | Compact editor, selected-row consistency and real pill switches. Unit and screenshot checks. |
| FR-004–FR-009 | Complete | Shared renderer, clickable appearance navigation, silent disabled sample, explicit world preview, scale modes and visibility wording. Unit and simulator handler checks. |
| FR-010–FR-016 | Complete | Filterable five-template catalog, Custom, cancel/refuse behavior, disabled independent copies and required item validation. Unit and simulator handler checks. |
| FR-017–FR-019 | Complete | Persistent palette and existing All/Any model, condition identity, negation, unknown state and character targeting. Unit, simulator and screenshot checks. |
| FR-020 | Partial verification | Pointer bindings and insertion feedback are implemented. Simulator handlers reorder and regroup real nodes. Mouse-event delivery and cursor geometry in the client remain unverified. |
| FR-021 | Complete at handler level | Invalid and canceled drops preserve the rule. Menu alternatives remain. A move can be undone or redone once and a palette drop requires confirmation. |
| FR-022–FR-023 | Complete at simulator level | Exclusive companions, layered Escape handling, disabled world-preview cleanup, side placement and constrained overlay. The client Escape key and additional UI scales remain to check. |
| FR-024 | Complete | Existing editor actions, validation, profile compatibility and condition types retained. Unit and repository checks. |
| FR-025 | Complete at repository and simulator level | Existing illustrations reused, switch texture alpha inspected and runtime textures rendered. Settings TOC/package test passed. No release archive was built. |
| FR-026–FR-028 | Complete | Baseline, intermediate and final screenshots inspected. Implementation continued through all surfaces and remaining gaps are recorded here. |
| UI-001 | Partial | Main editor, preview and catalog compositions are recognizable. The builder overlays at the captured widths and retains the per-edit flow. |
| UI-002–UI-006 | Complete at simulator level | Warm leather and chestnut, aged bronze and ivory, rounded control faces and restrained contrast. The existing settings shell retains its frame construction. |
| UI-007–UI-008 | Partial verification | Heading hierarchy and observed clipping corrected in simulator captures. Client typography and long localized labels remain unverified. |
| UI-009–UI-015 | Complete at simulator level | Substantial list, secondary disclosures, pill switches, rounded controls, illustrated cards, scoped tabs and selected states. |
| UI-016 | Deliberately unchanged outside Reminders | The shared navigation layout and artwork are retained. Reminders row selection and reminder tabs have scoped treatment. |
| UI-017–UI-020 | Complete at simulator level | Hover, disabled, focus affordances, navigation highlight, transparent standalone art and separate preview/live presentation. Real hover and tooltip timing remain client checks. |
| UI-021 | Partial verification | The 1280 × 800 overlay fits. Additional UI scales, edge placement and real font metrics remain to check. |
| UI-022–UI-025 | Complete at repository and simulator level | Existing artwork and semantic colors retained. Style-v2 materials and actual controls used. The mockups remain documentation references. |

The builder retains its per-edit Done/Cancel contract. A validated drop moves the original node as one operation. Undo/Redo apply to the latest move while its revision remains current. The More menu still offers non-drag alternatives. A palette drop chooses the destination and opens a draft. Closing discards the draft. The settings Escape handler cancels a drag first, then returns the open companion to the preview. Explicit preview uses the selected reminder's appearance and never enables the reminder.

## Artwork and packaging

The oil vial, leather gauntlet and parchment scroll already had integrated sources under `assets/reminder-art-*-source.png` and full/small runtime TGAs under `!!!TwichUI/media/reminders/`. This pass reused them and the existing plate, shield and arrows. No image generation calls or new illustration placeholders were needed. `python3 -B tools/make_style_v2_art.py --switches-only` produced the 64 × 32 track and 32 × 32 thumb in `!!!TwichUI/media/style-v2/`. Byte-level alpha inspection found 348 and 284 fully transparent pixels respectively, and partial edge pixels in both. All inspected reminder TGAs also have fully transparent pixels. The simulator rendered the runtime files. Existing packaging excludes `docs/` and `assets/`.

## Verification and client acceptance

- `luac5.1 -p` passed for all touched Lua files. `git diff --check` passed.
- Focused Lua 5.1 tests passed for `test_reminders_settings.lua`, `test_reminders_groups.lua`, `test_reminders_designer.lua`, `test_reminders_enchant_sound.lua`, `test_settings_window.lua`, `test_settings_window_size.lua`, `test_settings_contract.lua` and `test_settings_package.lua`.
- The final `./tests/run.sh` finished with 187 passed and 0 failed. An intermediate run failed `test_onboarding.lua` during settings mock setup. It passed in isolation and in the final suite.
- `bash tools/simlab/reminders.sh` passed 41–42 handler and state checks in each of seven poses using synthetic data and cursor coordinates.
- `SIMLAB_PAGE=reminders SIMLAB_TITLE=Reminders bash tools/simlab/smoke.sh` passed initialization, texture and 56-page construction checks. The interaction run allows the known simulator-only `C_VoiceChat.CanAccessSettings: settings access has not been supplied` error.

### Real-client acceptance

1. At normal and reduced UI scales, drag a card between siblings and into an Any group, drag a group, reject a self-drop, cancel outside, then check Undo/Redo. Drag a palette entry and cancel its draft. Repeat with the More menu.
2. On a disabled reminder, use Actual size, Fit and both artwork/text reveal targets. Show and hide the world preview, enter combat and leave settings. Confirm silence, correct hit regions, and no orphaned preview.
3. Create two copies of the same template, edit one, refuse an incomplete item draft and use Escape/Back from each companion. Reload and verify IDs, saved rules and selection behavior against the addon contract.
4. Check fonts, long names, hover tooltips, disabled states and close actions at the screen edges. Compare all three panels at normal client scale.
