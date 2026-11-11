# Magic Inventory rule workspace

References: the supplied PNG files are named [`mockup`](mockup) and [`rule_builder`](rule_builder) without extensions.
The existing settings shell, materials and controls remain shared with Reminders/Home. No engine or rule schema changed.

## Manager

75-unit pooled rows replace the previous variable-height cards. Real priority numbers remain visible while searching
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

The compact item strip shows the first six sorted item identities; the detailed inclusion editor retains all items.
No unavailable item identity is dropped. Rule exclusions and global Never transfer/protection categories remain distinct.
No click on a setting starts movement; Preview still opens the existing read-only review, and actual actions remain there.

## Art

Reused: SettingsCraft frame/field/chip/selection/button/segment sheets, canonical walnut panels, existing NPC coins,
tabard, scroll, backpack and shield illustrations; guide arrow and balance-scales artwork. Native game item icons are
used when a rule names an item. New: `assets/magic-reagents-source.png` →
`!!!TwichUI/media/icons/magicReagents{,-small}.tga` (64/32 RGBA). Build with
`python3 tools/make_magic_reagents_art.py`; uses the existing alpha-aware standard-library resample/bleed pipeline.

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
