# Magic Inventory rule workspace

References: the supplied PNG files are named [`mockup`](mockup) and [`rule_builder`](rule_builder) without extensions.
The existing settings shell, materials and controls remain shared with Reminders/Home. No engine or rule schema changed.

## Manager

70-unit pooled rows replace the previous variable-height cards. Real priority numbers remain visible while searching
name/item/destination text or filtering enabled/disabled rules. Filtered views cannot drag or invoke priority actions;
hidden rules are never reordered. The manager keeps the existing 40-rule model limit rather than adding a new limit.
Native controls cover enabled state, Edit and the compact context menu (move, duplicate, confirmed delete). Selection,
hover and chips reuse SettingsCraft artwork. Drag uses an isolated walnut row-sized ghost with icon, title and detail,
retaining the pointer's offset; invalid drops/cancellation use the existing drag engine and no inventory API.

## Builder

The main screen presents What items, Where should they go, How should they move, What should stay and Rule review.
Three columns fit wide windows; two columns plus review below fit the supported smaller shell. Details scroll normally.
Live name/summary and readiness reflect the private draft. Save uses `MagicInventory.SaveRule`; Cancel drops the draft.
Back asks before discarding; closing/reopening settings retains the session draft. Profile application discards it, as
before. Duplicate in the builder makes a new disabled draft; manager Duplicate copies the saved rule. Deletion confirms.
Page reset is disabled during a draft and remains available in the manager, distinct from rule deletion.

| UI | Existing rule model |
|---|---|
| Cloth/herbs, consumables | Adds existing category keys; the full category catalog can edit/remove them |
| Equipment | Existing `equip` filter; no classifier changes |
| Specific items / picker / ID or link | `include`, removing corresponding `exclude` entries |
| Destination choices | Existing `kind`; incompatible `dest` references are cleared as in the old editor |
| Destination details | Existing named destinations, per-character recipients/guild tabs and shared-recipient choices |
| Movement | Existing `flow`; not applicable to keep/never/mail or guild design rules |
| Keep field and steppers | Draft `keep`, bounded by the existing MAX_KEEP; zero retains its original meaning |
| Exclusions and limits | Existing `exclude`, keep and guild stack/design controls |
| More item filters | Original category/quality/equipment/binding/inclusion editor, preserving advanced capabilities |
| Review | Existing CleanRule/Problem/Sentence; incomplete rules can save disabled and cannot be enabled |

The main item and exclusion wells show the first sorted identity by name, artwork and remove action, with a count of
additional entries. The detailed editors and bag picker retain access to every item.
No unavailable item identity is dropped. Rule exclusions and global Never transfer/protection categories remain distinct.
No click on a setting starts movement; Preview still opens the existing read-only review, and actual actions remain there.

## Art

Reused: SettingsCraft frame/field/chip/selection/button/segment sheets, canonical walnut panels, existing NPC coins,
tabard, scroll, backpack and shield illustrations; guide arrow and balance-scales artwork. Native game item icons are
used when a rule names an item. New: `assets/magic-reagents-source.png` →
`!!!TwichUI/media/icons/magicReagents{,-small}.tga` (64/32 RGBA). Build with
`python3 tools/make_magic_reagents_art.py`; uses the existing alpha-aware standard-library resample/bleed pipeline.
The same converter now builds `assets/magic-bank-source.png` → `media/icons/magicBank{,-small}.tga` (64/32 RGBA).
This transparent walnut/bronze vault illustration replaces ambiguous coins in bank choices, headings, tabs and chips.
Native square item art uses the existing `TempPortraitAlphaMask` silhouette in rule rows, banner, review and drag ghost;
item-picker wells keep the full native icon. Addon illustrations keep their original transparent silhouette.

Generated with the built-in image tool using the imagegen skill. Prompt:
“Use case: stylized-concept. Asset type: a single standalone transparent 64px game inventory interface icon (generate
high resolution for downsampling). A neatly rolled muted purple cloth beside a sprig of sage-green herbs, representing
profession reagents. Hand-painted premium fantasy game UI illustration, shallow dimensional relief, soft upper-left
lighting, aged bronze accents. Clear strong silhouette centered with generous transparent padding. Fine detail readable
at 32 pixels. No badge or frame, no backdrop, no letters, no text, no glow, no watermark. Restrained walnut/espresso
shadows, warm ivory highlights, desaturated purple and green.”

## Verification and limits

Full suite: 189 passed, 0 failed during implementation; focused Magic Inventory tests rerun after UI refinements.
`test_magic_inventory_settings.lua` retains save/cancel, inclusion/exclusion, recipient/tab, invalid enablement, stack,
withdrawal and handler drag coverage, and adds filtered priority safety. Existing engine/plan/run/guild tests remain.
The settings contract fixture and all defaults/write destinations are unchanged.

The existing settings simulator supports `SIMLAB_SETTINGS_COUNT=0|1|5|20|40` for Magic Inventory. It checks search,
filtering without priority writes, filtered drag refusal, private draft cancellation and original navigation/cache checks.
`SIMLAB_SETTINGS_EDITOR=true` opens an incomplete template; `SIMLAB_SETTINGS_TASK=5` gives it a bank/balance fixture.
`SIMLAB_SETTINGS_CATEGORIES=true` retains the advanced category catalog in the builder, or opens the rule context menu
in manager mode. Add `SIMLAB_SETTINGS_POSE=narrow` for the constrained shell. For example:

```sh
SIMLAB_SETTINGS_COUNT=40 bash tools/simlab/settings.sh magicInventory
SIMLAB_SETTINGS_COUNT=5 SIMLAB_SETTINGS_CATEGORIES=true bash tools/simlab/settings.sh magicInventory
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_EDITOR=true SIMLAB_SETTINGS_TASK=5 bash tools/simlab/settings.sh magicInventory
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_EDITOR=true SIMLAB_SETTINGS_CATEGORIES=true SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh magicInventory
```

Simulator input invokes handlers, not real pointer delivery. Actual drag hit regions, native item cache/category names,
localized Cinzel wrapping, client combat restrictions, reload/profile persistence and actual bank/mail/guild reviews
still require client acceptance. No gameplay transaction has been performed. No page is marked Verified.

Named destination creation and character/shared destination settings still use their existing immediate APIs; rule
criteria and rule edits are private until Save. Cancelling a rule does not delete a separately created destination.
This preserves the prior destination contract.

## Reviewed captures and differences

All paths below are untracked under `../wow-ui-sim-lab/artifacts/`, not runtime screenshots or approved golden images:

- `settings-20261111-104439/magicInventory.png`: first compact manager. Refinement moved inline metadata into badges.
- `settings-20261111-104630/magicInventory.png`: first builder. Refinement added illustrations, steppers, structured review,
  Back/discard and a full-width footer, and removed overlap between exclusion text and its action.
- `settings-20261111-104913/magicInventory.png`: 40-rule list, inspected; priority/order checks passed.
- `settings-20261111-105547/magicInventory.png`, `105604`, `105619`: 0, 1 and 20 rules; all scenarios passed.
- `settings-20261111-105829/magicInventory.png`: populated builder with bank/balance behavior, inspected.
- `settings-20261111-105845/magicInventory.png`: narrow incomplete builder with advanced criteria retained, inspected.
- Final toolbar/context and narrow-list captures are `settings-20261111-110217/magicInventory.png` and
  `settings-20261111-110234/magicInventory.png`; final empty is `settings-20261111-110250/magicInventory.png`.

The layout uses the existing shell rather than replacing Home/navigation. In constrained widths the review moves below
criteria, and detailed compatibility controls expand below the main cards. Complex predicates are summarized with full
help rather than pretending every rule is a single simple sentence. Font substitution, native item-cache content and
small intrinsic differences in existing component artwork prevent a pixel-identical simulator comparison. No simulator
engine was changed. No real pointer drag, client reload or actual movement acceptance is claimed.

Final structured builder: `settings-20261111-110302/magicInventory.png` (63 checks, opened and reviewed).
Final long-name narrow row: `settings-20261111-110617/magicInventory.png` (22 checks, opened and reviewed).
The long-name review increased the bounded title region and row height to 75 units; its measured text now fits.
The manager/context, narrow manager and empty captures listed above were also opened and reviewed.
All final focused Magic Inventory tests passed; full-suite result during the implementation was 189/189.
Final reviewed manager/context: `settings-20261111-110749/magicInventory.png` (23 checks passed).
Final reviewed builder: `settings-20261111-110806/magicInventory.png` (63 checks passed).
The final small-icon-variant builder capture is `settings-20261111-110941/magicInventory.png`: 63 checks passed,
opened and reviewed at actual UI scale. Source alpha ranges from 0 to 254; runtime files are 64/32 RGBA TGAs.

## Mockup fidelity correction pass — 2026-11-11

This supersedes the first-pass geometry above; it does not change the rule engine, profile storage or schema.
Both approved references were reopened, then actual manager/builder images were opened repeatedly after corrections.
The current shared Home shell remains intact. The manager now uses 70-unit rows, stronger rule names, 36-unit artwork,
25-unit wide-view chips and 19-unit constrained-view chips. The toolbar uses a primary New rule button opening the
existing template menu, a magnifier/placeholder search field, state filter and compact help. Review items remains a
separate explicit read-only action. Four 36-unit illustrated task tabs retain their original navigation.

The builder uses a 64-unit illustrated live summary, named removable item/exclusion wells, explicit ID/link guidance,
34–36-unit illustrated category/destination/movement choices with check indicators, aligned quantity steppers, concise
movement explanations and a label/value review with its own readiness surface. Save/Cancel and saved-rule Delete/Duplicate
use 32-unit buttons. Detailed criteria, destination contracts and exclusions remain available through the disclosures.
Excluding an included item preserves the separate inclusion; the existing exclusion precedence remains authoritative.

### Discrepancy register

| Severity | Finding | Correction / evidence | State |
|---|---|---|---|
| P0 | Empty chips despite populated display strings | Text was on the row behind its child badge. Text now belongs to the badge, with native OVERLAY ink, alpha 1 and bounded width. Unit ownership regression plus populated/context/drag screenshots below. | Resolved in code; screenshot-reviewed. Client regression remains. |
| P1 | Excess row whitespace and weak identity | 70-unit rows; 14-unit rule name; real priority, compact illustrated metadata and existing rich selection sheet for hover/selection. 40-rule and narrow screenshots reviewed. | Resolved for reviewed layouts. |
| P1 | Generic toolbar and tiny tabs | Primary template action, magnifier/placeholder, filter/help and 36-unit illustrated tabs. Existing search/filter ordering safeguards retained. | Simulator-tested and screenshot-reviewed. |
| P1 | Understated summary and generic choices | Art-backed live banner; larger illustrated choices, explicit check indicators, bank-first presentation order without changing stored kinds. All destination/movement handlers exercised. | Simulator-tested and screenshot-reviewed. |
| P1 | Isolated item icon; sparse quantities/exclusions | Named item wells and removal, visible additional-item count, aligned labeled stepper, direct exclusion picker and existing advanced editors. Unresolved IDs remain visible. | Unit-tested; named fixture screenshot-reviewed. |
| P1 | Review lacked hierarchy/readiness emphasis | Item identity, separate labels/values, concise keep value, illustrated readiness well and explicit review-before-transfer note. Actual Problem/CleanRule determines readiness. | Valid/incomplete screenshots reviewed; no movement executed. |
| P2 | Exclusion text overlap and safety text outside card | Repositioned item well/actions and shortened safety note; final wide and narrow captures reviewed. | Resolved for reviewed layouts. |
| P2 | Inconsistent square category icons; ambiguous Bank art | Reused transparent TwichUI category/status art, generated bank-vault icon, native-item portrait mask; drag ghost retains the same metadata surfaces and labels. | Alpha/dimensions checked; runtime art screenshot-reviewed; mask construction/removal unit-tested. Native item appearance needs client acceptance. |
| P2 | Understated editing footer | 32-unit secondary/destructive/primary buttons; illustrated Duplicate. Saved-rule screenshot includes all four actions. | Screenshot-reviewed; transactional behavior unit-tested. |
| Evidence gap | Scrolled label bounds disagree with rendered position | Two bounds checks failed although the catalog is visibly in view: label bounds −303/−324 vs viewport 797/351 in `113331`. No simulator patch or further bounds workaround. Keep scroll-state verification and human screenshot review separate. | Documented limitation; not a UI regression or proof of pointer reachability. |

### Correction-pass captures and reusable coverage

All entries are under `../wow-ui-sim-lab/artifacts/`, untracked and excluded from packages. They are current-state
captures, not approved golden baselines. Every image named here was opened and reviewed.

| Capture folder (`settings-20261111-…`) | Pose | Handler/state checks |
|---|---|---|
| `112343`, `112709` | Iterative wide builder; fixes to identity, review, exclusions and safety spacing | 63, 84 |
| `112801` | Populated manager, enabled/disabled, selected row and context menu | 31 |
| `112817` | 40 rules, real priority and scrolling | 142 |
| `112836` | 20 rules, long name, constrained layout | 82 |
| `112855`, `112916` | Empty / one-rule manager | 20, 25 |
| `112936` | Complete bank/balance draft and readable review quantity | 84 |
| `112956` | Constrained incomplete builder | 82 |
| `113116`, `113138` | Saved-rule editor/footer and incomplete rule readiness | 84, 82 |
| `113158`, `113331` | Expanded constrained category catalog, visually in view | 82 passed; experimental bounds assertion failed; see limitation above |
| `113310` | Row drag picture with readable chips; unchanged rule order | 32 |
| `113349` | Final saved-rule editor, category checks, icon-bearing Duplicate, stronger footer | 84 |
| `113448` | Final populated manager, enabled/disabled, selected row, context menu and corrected Mail art | 31 |
| `113511` | Final expanded constrained catalog and supported scroll-state check | 83 |

New scenario branches reuse `tools/simlab/settings.sh` and its isolated fixtures:

```sh
# Populated manager / menu; count=0,1,20,40 use the same count fixture.
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_CATEGORIES=true bash tools/simlab/settings.sh magicInventory
SIMLAB_SETTINGS_COUNT=40 bash tools/simlab/settings.sh magicInventory
# Saved-rule editing and all footer actions, rather than only a new template.
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_EDITOR='"existing"' SIMLAB_SETTINGS_TASK=5 bash tools/simlab/settings.sh magicInventory
# Missing recipient / invalid enablement, with real draft validation.
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_EDITOR=true bash tools/simlab/settings.sh magicInventory
# Expanded catalog, scrolled into view in a constrained shell.
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_EDITOR=true SIMLAB_SETTINGS_CATEGORIES=true SIMLAB_SETTINGS_DATA='"advanced"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh magicInventory
# Virtual drag handler and unchanged saved order; no real pointer delivery.
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_DATA='"drag"' bash tools/simlab/settings.sh magicInventory
```

The scenario now checks each visible behavior label's ownership/content and row height; exercises every destination
and applicable movement choice; verifies stepper changes and restoration; removes/restores a named item fixture; and
checks that all these edits leave saved rules unchanged. Saved-rule and new-template flows reuse actual addon controls.
The fixture's Linen Cloth name/art is explicitly synthetic; production item resolution is unchanged.
Unit regressions add badge ownership, native mask lifecycle and inclusion/exclusion independence to the existing
save/cancel, invalid enablement, field validation, profile/schema and drag safety coverage. Full suite: 189 passed,
0 failed during this correction pass. Syntax checks cover changed Lua files.

The bank source was generated with the built-in image tool and imagegen skill. Full prompt:

> Use case: stylized-concept. Asset type: standalone transparent fantasy game UI icon for TwichUI, readable at 22 to
> 40 pixels. Primary request: a small closed bank vault chest, broad silhouette, dark walnut wood and aged bronze
> reinforced edges, a prominent simple antique gold lock at center. Premium hand-painted fantasy game interface
> illustration, shallow sculpted relief, soft upper-left lighting, warm ivory edge highlights, espresso shadows,
> restrained muted bronze and chestnut. Composition: one centered isolated object, three-quarter front view, generous
> transparent padding, no square background, no decorative badge/frame, no floor or backdrop. No text, no letters,
> no glow, no bright yellow gold, no heavy filigree. Must have genuine transparent alpha.

Source: 1536×1024 RGBA, alpha 0–254 with 955,825 fully transparent pixels. Conversion keeps genuine alpha, common optical
size, premultiplied resampling and RGB bleed. Existing reagent outputs remain byte-identical after rebuilding.

Remaining differences/acceptance: existing shell geometry and shared artwork are retained, rather than copying the
mockup's shell or replacing controls with a flattened image. Dense advanced predicates use structured summaries and
disclosures; narrow review flows below the two-column grid. Native font metrics, localized wrapping, actual item art
and masks, pointer/keyboard focus and dragging, combat, reload/profile persistence, and real bank/mail/guild reviews
remain **not real-client-tested**. No actual inventory action occurred. Status remains Substantially modernized,
not Verified; no pixel-identical or real-client visual acceptance is claimed.
