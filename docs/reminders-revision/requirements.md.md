# TwichUI Reminders — Requirements and Design Handoff

Prepared: November 10, 2026
Target: TwichUI addon for World of Warcraft Forever, branch `feature/style`.

## 1. Authority and evidence

This document consolidates the requirements established in the accessible conversation. It is not an independent repository audit. Claude/Codex implementation reports are reported evidence, not verified source inspection. The latest user-supplied client screenshots reject the visual completeness of the current implementation.

Authority order:
1. Explicit newer user decisions determine requested scope.
2. The three approved Reminders renders determine visual targets.
3. Written behavioral requirements and existing validated semantics determine safety and behavior.
4. Current source and fresh tests determine implementation state.
5. Older reports and planning snapshots are supporting context only.

Approved means a requested outcome, not proof that it has been implemented. Proposed means an assistant recommendation without explicit approval. Unresolved means the record does not settle a consequential detail.

## 2. Executive overview

Revise Reminders into a polished, approachable settings experience with a compact editor, attached interactive preview, illustrated template catalog, and attached When builder. Reminders is the initial prototype for a shared crafted fantasy style; this does not authorize an addon-wide rollout.

The current implementation reportedly provides functional companions, catalog creation, preview navigation, and a reused condition editor. The user rejected its styling: square checkboxes, legacy buttons, incorrect text hierarchy/colors, insufficient tab styling, inconsistent reminder selection, missing drag-and-drop, and overflowing When-picker categories.

The goal is faithful implementation and simulator-led refinement against the approved mockups, not merely a functional rearrangement or brown recoloring.

Out of scope: Workbench, addon-wide audits/restyling, replacement rule engine, unspecified new condition types, broad refactors, node-graph framework, simulator repairs, unauthorized dependencies, destructive cleanup, live game/WTF/SavedVariables changes, and unauthorized commits/pushes/publication.

## 3. Functional requirements

Unless stated otherwise, preserve existing defaults, validation, configuration, and saved-data behavior. Do not invent new settings. Exact numerical dimensions and timing are unspecified.

| ID | Requirement | Status | Acceptance / edge cases | Dependencies |
|---|---|---|---|---|
| FR-001 | Compact editor: prioritize Appearance, When, Sound; secondary Advanced/help/Test; consolidate redundant introductions. | Approved | Primary workflow follows approved composition while retaining existing capabilities. | UI-001–010 |
| FR-002 | Reminder list and selection: artwork, name, enable and meaningful live state. | Approved | List/editor/preview identify the same reminder; long names remain usable. | FR-004 |
| FR-003 | Preserve master and per-reminder enable behavior using pill switches. | Approved | Correct setters/validation; no visible legacy checkbox where switches are required. | UI-011 |
| FR-004 | Attached live preview, updated by selection and appearance edits, available while editor scrolls. | Approved | Existing renderer reused; correct reminder rendered. | Existing display path |
| FR-005 | Click preview artwork/text to reveal and briefly highlight corresponding controls without saving. | Approved | Correct destinations and hit targets; restrained discoverability. | FR-004, UI-018 |
| FR-006 | Isolated silent preview independent of enable state and live conditions. | Approved | Disabled stays disabled; no sound or live-state mutation. | Existing renderer |
| FR-007 | Preserve Show on screen / Hide preview and lifecycle cleanup. | Approved | No temporary orphan display after leaving/closing/reopening. Combat policy needs inspection. | FR-022 |
| FR-008 | Actual size / Fit sizing controls shown in approved render. | Unresolved functional specifics | Real distinct modes; fitting must not change saved reminder scale. Default/persistence not established. | FR-004 |
| FR-009 | Honest distinction between feature enable, reminder enable, live visibility, and preview visibility. | Approved principle | No misleading status; exact labels not all settled. | FR-019 |
| FR-010 | New reminder / + New opens catalog without creating or changing selection; cancellation creates nothing. | Approved | Close, Esc, page/settings closure preserve data. Exact entry label not settled. | FR-022 |
| FR-011 | Illustrated catalog: artwork, name, short description, Use template; supported entries plus distinct Custom reminder. | Approved | All five supported templates remain accessible, including additional row. | UI-013 |
| FR-012 | Canonical creation, independent deep copies, unique identity, initially disabled, select/open editor, close catalog on success. | Approved | Repeated copies share no mutable state; editing/deleting copy does not mutate template. | Existing validated creation |
| FR-013 | Preserve creation limits and compatibility refusals. | Approved | Reported limit 24; newer-format profile refusal; no partial creation; catalog stays open with reason. | FR-012 |
| FR-014 | Custom reminder uses existing creation path and safeguards. | Approved | Existing defaults retained; successful draft opens editor. | FR-013 |
| FR-015 | Essential missing configuration is apparent; invalid enabled state prevented. | Approved | Empty required conditions never mean always show; inspect incomplete equipment/item draft. | Validation |
| FR-016 | Catalog search and categories. | Unresolved current scope | Render contains Search templates…, All, Preparation, Equipment; functionality repeatedly deferred; later inclusion was assistant-proposed, not confirmed. | Catalog metadata |
| FR-017 | Attached/pop-out When builder opened by Edit conditions, reusing existing designer. | Approved | Correct return/state preservation; no duplicate rule implementation. | FR-022 |
| FR-018 | Understandable sentence-like rule cards, bounded All/Any groups, guided picker, targeting separate from predicates. | Approved | Grouping understandable without technical diagnostics. | FR-019 |
| FR-019 | Preserve rule semantics, negation, unknown states, identity, validation and supported configuration. | Approved | Equivalent evaluation; no lossy conversion or condition types added solely for mockup. | Existing rule model |
| FR-020 | Drag-and-drop arranging conditions into AND/OR groups. | Approved | Actual pointer workflow works; exact group dragging/nesting/drop mechanics need reference/code reconciliation. | FR-019 |
| FR-021 | Clear drag feedback, invalid/cancel rollback, reject cycles, ordinary editing alternatives. | Proposed mechanics | No partial tree mutation; non-drag alternatives were historically requested. | FR-020 |
| FR-022 | Preview/catalog/When share companion location and correct lifecycle. | Approved | One intended companion; correct restoration after cancel/create/refusal; no duplicate frames/listeners. | All companions |
| FR-023 | Accessible placement at supported sizes/scales and screen edges. | Approved | No clipped actions/categories or inaccessible overlap; exact constrained fallback unspecified. | UI-021 |
| FR-024 | Preserve naming, Duplicate, Delete, sound selection/test, placement/size/effects, diagnostics, profile context, reset. | Approved | Existing workflows remain reachable; existing values preserved. | Existing APIs |
| FR-025 | Generate/integrate missing standalone assets using tested image path; reuse suitable assets first. | Approved | Actual alpha, clean seams/slicing/scaling, small-size legibility, correct packaging; text stays in code. | Asset conventions |
| FR-026 | Simulator render, image inspection, mockup comparison and targeted iteration for all three surfaces. | Approved | Screenshot existence/construction alone is not acceptance. | Existing simulator |
| FR-027 | End-to-end execution; internal phases are not approval gates. | Approved | Continue full scope without routine restarts; ask only consequential decisions/authorization. | Safety constraints |
| FR-028 | Honest evidence and completion reporting. | Approved | Separate code, unit, simulator handlers, visual comparison, client evidence; disclose gaps/placeholders. | Verification |

### Catalog labels and content

Actual reported entries: Missing shield; Ammunition; Missing weapon enchant; Well Fed ran out; Missing equipment or item; Custom reminder.

Approved mockup illustrative entries:
- Weapon enchant — Remember your oil, stone, or poison.
- Well Fed — Remember to eat before heading out.
- Missing shield — Check your off hand before you go.
- Ammunition — Keep your ranged weapon supplied.
- Custom reminder — Start with your own conditions.

Catalog heading: Create a reminder.
Subtitle: Start with a template. Make it yours.
Action: Use template.
Quiet footer: Creates your own editable copy. Starts off.

Do not remove the fifth supported template because the mockup illustrates four. Final naming normalization is not settled. No linked-template synchronization, catalog updates overwriting player copies, mandatory wizard, or new template sharing/import system was requested.

## 4. Visual requirements

No exact hex palette, pixel measurements, font sizes, radii, or fixed margin system were established. Use approved renders and verify actual runtime fit.

| ID | Requirement | Status / acceptance |
|---|---|---|
| UI-001 | Match approved composition and hierarchy, not palette alone. | Approved |
| UI-002 | Warm worn leather, walnut/espresso interiors, chestnut surfaces, subtle texture. | Approved; no orange wash |
| UI-003 | Aged bronze, selective antique gold, ivory primary text, readable muted secondary text. | Approved |
| UI-004 | Narrow continuous frames with consistent corners/rails and modest fittings. | Approved |
| UI-005 | Restrained bevel/depth, recessed wells; highlights behind artwork/text. | Approved |
| UI-006 | Modest rounded corners on controls, cards, selection and containers. | Approved |
| UI-007 | Strong readable heading/control hierarchy; not universally tiny muted-gold labels. | Approved |
| UI-008 | Balanced spacing, consistent padding/alignment; real text fits. | Approved |
| UI-009 | Substantial reminder-list well and coherent editor proportions following preview target. | Approved visual target |
| UI-010 | Advanced/help/diagnostics secondary rather than oversized primary panels. | Approved |
| UI-011 | Pill switches replace rejected player-facing boolean checkboxes on redesigned surfaces. | Approved |
| UI-012 | Rounded shallow-beveled buttons, bronze rims, readable enabled/disabled labels. | Approved |
| UI-013 | Distinct illustrated catalog cards with consistent artwork/title/body/action structure. | Approved |
| UI-014 | Styled dropdowns, fields, tabs, segments and close/back controls; no category overflow. | Approved |
| UI-015 | Rounded richer selected-state gold; coherent reminder/navigation/editor treatment. | Approved |
| UI-016 | More prominent navigation artwork/text and stronger selected item. | Approved direction; no automatic global rollout |
| UI-017 | Clear hover, pressed, disabled, selected, applicable focus/error states. | Approved; exact error palette unknown |
| UI-018 | Restrained preview affordance and brief destination highlight. | Approved; no intrusive flashing |
| UI-019 | Standalone artwork readable at actual UI size, real transparency as appropriate, no baked-in text. | Approved |
| UI-020 | Preview frame/well/header/footer/controls match target hierarchy and distinguish states. | Approved target |
| UI-021 | Responsive sizing/wrapping, accessible controls at supported sizes/scales. | Approved |
| UI-022 | Preserve meaningful item/class/state colors and recognizable artwork. | Approved |
| UI-023 | Reject charcoal/teal dashboards, bright gold perimeters, heavy filigree, clutter, unnecessary glow/particles/animation, excessive prose. | Approved |
| UI-024 | Guild-bank code/assets are reuse candidates and historical material guidance, not a required missing mockup. | Approved clarification |
| UI-025 | Real composed UI, never a flattened screenshot masquerading as interactive controls. | Approved |

## 5. Authoritative references and asset inventory

| Asset | Role and authority | Transfer requirement |
|---|---|---|
| REMINDERS_PREVIEW / REMINDERS_PREVIEW.jpg | Approved primary editor/preview target: list, switches, rounded controls, preview, Actual size/Fit, visibility hierarchy. | Attach actual file; repository path in local brief |
| REMINDERS_TEMPLATE_CATALOG | Approved catalog target. | Attach actual file |
| REMINDERS_WHEN_BUILDER | Approved builder target; not visually reviewed in this document’s source context. | Attach actual file |
| Latest client editor/preview screenshot, Nov 10 3:53 PM | Rejected implementation evidence, not target. | Attach |
| Latest client When screenshot, Nov 10 3:53 PM | Rejected implementation; overflowing categories. | Attach |
| Earlier client screenshots, Nov 10 1:21 PM | Before-state catalog and inline preview. | Optional historical evidence |
| TWICHUI_APPROVED_STYLE_2026-10-31.png | Historical approved guild-bank implementation screenshot/material baseline. No separate guild-bank mockup required. | Optional |
| REMINDERS-V2-MOCKUP.jpg | Listed historical attachment; authority/content not established here. | Do not elevate over three approved targets |
| media/style-v2/ | Existing materials, reported by Claude. | Inspect repository |
| media/guildbank/, FrameLook.lua | Existing frame reuse candidates. | Inspect repository |
| Generated amber oil vial | Generation/save test succeeded; reportedly reused. | Locate actual asset |
| Generated leather gauntlet | Codex reported generated art; not independently visually accepted. | Locate actual asset |
| Existing scroll, shield, arrows, food plate | Reported catalog art. | Locate actual assets |

Reported Codex screenshots, not independently reviewed here:
`/home/rich/dev/personal/wow-ui-sim-lab/artifacts/reminders-20261110-154138/`
- editor.png
- catalog.png
- when.png
- narrow.png

Reported inspection composite:
`test-output/reminders-art-inspection/runtime-on-two-backgrounds.png`

These are local paths, not public download links. Images cannot be transferred to another chat by naming them alone.

## 6. Screens and interaction flows

### Main settings
Title/master enable → reminder list/create → selected reminder name/enable → Appearance → When summary/Edit conditions → Sound → Advanced and secondary diagnostics. Preserve profile/reset and Duplicate/Delete in a coherent location. Existing General/Known ammunition functionality must not disappear; applicable tabs must be styled.

### Preview
Live preview heading, selected name, preview drawing, interactive image/text, sizing/status controls as resolved, isolated on-screen preview controls. Empty-selection behavior is unspecified; inspect current code rather than inventing a tutorial.

### Create from template
1. Open catalog without changing existing reminder.
2. Choose Use template.
3. Validate through canonical creation.
4. Create unique independent disabled copy.
5. Select/open editor and restore appropriate preview.
6. Highlight/expose required missing configuration where needed.

### Cancel/refusal
Cancel creates nothing and restores prior selection/companion. Limit/incompatible profile leaves catalog open with reason, without partial creation.

### Preview navigation
Click artwork/words → reveal associated settings → brief highlight → no save until actual user editing.

### When editing
Open companion → inspect targeting/grouping → add/edit/rearrange → preserve semantics → apply/cancel according to existing transaction contract → return to appearance. Codex reported per-condition Done/Cancel; exact save boundaries require inspection.

### Placement/cleanup
Only intended companion visible. Edge/constrained layout keeps controls reachable. Leaving page/settings removes temporary companions/on-screen previews. No duplicate frames after reopen.

No asynchronous loading workflow was established.

## 7. Current implementation and code map

All source details below are agent-reported, not independently inspected.

- Catalog creation uses P.Create → RM.Create.
- TemplateDisplay(kind) provides read-only display metadata.
- Existing D.NewSurface / D.DrawSurface render preview.
- PV.Place reportedly places companions.
- Existing inline designer was adapted into companion; do not assume it must be built from scratch.

Relevant paths:
- TwichUI_Settings/pages/Reminders.lua
- TwichUI_Settings/pages/RemindersCatalog.lua
- TwichUI_Settings/pages/RemindersPreview.lua
- TwichUI_Settings/pages/RemindersEditor.lua
- TwichUI_Settings/pages/RemindersDesigner.lua
- !!!TwichUI/reminders/Config.lua
- reminders/Display.lua (verify full path)
- Material.lua (verify full path)
- FrameLook.lua (verify full path)
- Window.lua (reveal/scroll integration)
- docs/reminders-style-upgrade.md
- AGENTS.md
- CLAUDE.md
- STATUS_AND_BACKLOG.md

Claude reported catalog/preview committed in 2e0c5fe5 on feature/style, superseding earlier uncommitted assumptions. Current Git state must be checked.

Latest Codex report claims 187 passing tests, 83 handler/state checks across four simulator scenarios, 56 constructed settings pages, screenshot review, and generated/reused catalog artwork. User confirms basic preview worked but rejects visual completeness and reports no drag-and-drop.

## 8. Data, persistence, and compatibility

Preserve existing storage/defaults, identities, profile compatibility/sharing, validation and rule semantics. Do not perform lossy migration for visual layout. Template copies must not share mutable state. Preview navigation must not save; fitting should not change saved reminder scale.

Unknown: exact saved schema/version keys, ID allocator, import/export format, selection persistence, preview preference persistence, transaction model and need for migration. Inspect actual code. No new persistence model is authorized.

Reopening an in-memory settings frame does not prove reload/disk persistence. Separate reload testing from handler tests.

## 9. Technical constraints

- WoW Forever Lua addon; reports use Lua 5.1 syntax validation.
- Preserve real TOC/load order and existing frame/render/rule architecture.
- No new framework or dependencies approved.
- Inspect affected callers before shared helper changes; use opt-in adoption to avoid unrelated pages changing.
- Inspect current runtime texture conventions before selecting format, dimensions, conversion or slicing.
- Keep development references/source assets out of release package as appropriate.
- Tested image generation is available; do not switch to separately billed API generation, alter credentials, or purchase credits without authorization.
- No numeric performance budget established; avoid unnecessary idle animation, duplicate frames/listeners and unbounded loops.

Historical simulator: wow-ui-sim v0.1.37, Forever Linux x86-64; external lab ../wow-ui-sim-lab; bwrap isolation, no network, read-only game assets, software rendering. Verify actual current pins. Known custom-font substitution means actual-client typography still requires review. Do not repair simulator internals as part of this revision.

## 10. Decisions and supersessions

| Older approach | Current authority |
|---|---|
| Per-template buttons | Illustrated catalog |
| Inline preview | Attached companion |
| Display-only live preview | Interactive click-to-setting preview |
| Stop after milestone 1 | End-to-end execution; internal phases only |
| Drag/drop optional or conditional | User explicitly requires drag/drop |
| Bespoke artwork deferred | Tested image generation may produce needed assets |
| Missing guild-bank mockup blocker | Only three approved Reminders renders required |
| When designer assumed new | Reuse/adapt existing designer |
| Upgrade complete because tests pass | Visual acceptance withheld until substantial mismatch corrected |
| Search/categories deferred | Still unresolved; later inclusion was assistant-proposed |

Do not reintroduce routine phase-approval gates, palette-only approximations, claims from uninspected screenshots, flattened UI images, or unnecessary renderer/rule-engine replacements.

## 11. Dependencies and execution

This is preliminary dependency analysis, not a new design proposal.
1. Confirm current branch/diff, instructions, references and scope conflicts.
2. Establish appropriate local/shared visual components, checking callers.
3. Correct compact editor and selection presentation.
4. Correct preview styling/navigation and sizing/status behavior.
5. Correct catalog cards/assets and accessible layout.
6. Correct When composition, drag/drop and picker overflow.
7. Verify companion transitions, constrained layouts, regressions and packaging.
8. Compare integrated screenshots and refine meaningful discrepancies.

Independent groups may proceed without waiting for unrelated blockers. After two substantive unsuccessful approaches to one blocker, report evidence/smallest next action; continue independent scope safely. No automatic stop after a phase.

## 12. Testing and visual acceptance

Reported commands; inspect current scripts/policy before running:

```bash
./tests/run.sh
luac5.1 -p <edited-or-new-Lua-files>
git diff --check
bash tools/simlab/reminders.sh
SIMLAB_PAGE=reminders SIMLAB_TITLE=Reminders bash tools/simlab/smoke.sh
```

Use focused tests first, final checks per repository policy. Do not run unrelated messaging/group diagnostics for routine styling.

### Required functional checks
- Selection/name/appearance updates target correct preview (FR-002–005).
- Preview clicks reveal correct controls without saving (FR-005).
- Disabled preview remains off/silent (FR-006).
- On-screen show/hide and cleanup (FR-007/022).
- Repeated copies independent, unique, disabled (FR-012).
- Cancel/refusal no mutation; limits retained (FR-010/013).
- Missing input safely handled (FR-015).
- Conditions/unknown/negation preserved (FR-019).
- Pointer drag/drop and invalid/cancel behavior (FR-020/021).
- Companion selection/lifecycle and reopen (FR-022).
- Size/edge/scale accessibility, no tab overflow (FR-023/UI-021).
- Existing editor actions, persistence and compatibility retained (FR-024).
- Runtime assets/package exclusions correct (FR-025).

### Required visual loop
For editor/preview, catalog and When:
1. Render actual changed addon using existing simulator.
2. Open capture and approved reference.
3. Compare at comparable displayed size/content.
4. Check composition, proportions, switches, controls, hierarchy/colors, selection, frame/material, art size, alignment/wrapping/clipping.
5. Correct meaningful differences and recapture.
6. Track matched/adapted-with-reason/still-different/blocked in existing brief.

No numeric similarity threshold established. Major legacy styling is not an acceptable adaptation. No claim of visual acceptance from file existence, construction or green tests.

### Evidence boundaries
Unit tests do not prove untested behavior. Handler simulation does not prove pointer hit testing. Screenshots do not prove persistence. Simulator font substitution does not excuse all spacing/color/size defects. Real client still needed for true fonts/wrapping, pointer interaction, reload persistence, combat/taint, optional integrations and packaged install.

## 13. Unknowns and unresolved decisions

Must resolve before affected behavior:
- Search/category functionality inclusion versus repeated deferral.
- Exact drag/group/nesting scope and drop/save contract from reference/current model.
- Actual size/Fit default/persistence.
- Actual current reference paths and current checkout ownership.

Resolve through inspection:
- Schema/setters, save/cancel semantics, missing-item validation.
- Nesting restrictions and existing sizing/visibility APIs.
- Shared callers, asset formats and packaging rules.
- Current diff/commit, navigation styling extent, minimization behavior.
- Current final-test requirements and simulator scenario coverage.

Safely defer:
- Unspecified new condition types, global rollout, template-sharing/synchronization, broad import/export changes, simulator font-engine fixes and unrelated audits.

Do not reopen established decisions: close visual matching, switches, interactive preview, drag/drop, simulator comparison, end-to-end execution.

## 14. Completion and transfer checklist

Completed means approved interactions work; existing semantics/data retained; all three surfaces closely match authoritative renders; legacy control mismatches/overflow corrected; drag/drop implemented and appropriately verified; assets integrated; tests pass; actual screenshot comparisons inspected; limitations and real-client checks honestly separated. Functional completion is not visual acceptance.

Update existing brief/backlog rather than create recurring standalone reports. No unauthorized commits/pushes/publication.

Provide to the next ChatGPT/Codex session:
- [ ] All three approved renders as actual image files.
- [ ] Latest rejected real-client editor/preview and When screenshots.
- [ ] Current docs/reminders-style-upgrade.md.
- [ ] AGENTS.md, CLAUDE.md and applicable scoped instructions.
- [ ] Current STATUS_AND_BACKLOG.md.
- [ ] Current feature/style diff or repository access and Git state.
- [ ] Actual simulator editor/catalog/when/narrow captures.
- [ ] Asset paths/inspection composite and relevant simulator scripts if needed.

No separate guild-bank mockup is required.
