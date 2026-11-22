# UX02 rule artwork integrations — consumer specification

**Status: consumer specifications awaiting owner review and separate authorization.** This Batch 5 document specifies future consumers; it adds no rule schema or builder behavior. Batch 6 implements the shared foundation and 20 approved catalog choices, not these consumers. UX02-C/D remain outside the Ready queue. Source baseline: `c7f8741` on `docs/ux02-shared-artwork-picker`.

The owner's scope is **rule identification in the settings list/editor only**. A custom image must never alter rule conditions, priority, activation, destinations, matching, transfers or loot actions. Runtime loot cards, countdowns, transfer review windows, guild arrangement tools and drag ghosts retain their current visuals. See the [shared picker contract](shared-artwork-picker.md), [UX02](../product-roadmap.md#ux02--reuse-the-reminders-image-picker-across-twichui-rule-builders) and [existing artwork workflow](../reminders-art.md).

## Source-grounded current behavior

| Consumer | Automatic identity and exact settings surfaces | Current editing model |
| --- | --- | --- |
| Loot rules | `ACTION_ICON` supplies Need/Greed/Pass art, with `lootRolls` fallback for other/no action. List `row.icon` is 30 px (`LootRules.lua:223`); editor `f.headIcon` is 36 px (`:339`). | Module setters commit immediately. Name commits on Enter/focus loss (`:555–562`); action toggles call `SetAction`. There is no whole-rule Save/Cancel transaction. |
| Magic Inventory | `RuleArtwork` (`MagicInventory.lua:613–624`) first uses an included item's available icon, then equipment/never sword-and-shield, one category's `CategoryArtwork`, empty-category keep backpack, otherwise magicReagents. This exact precedence remains automatic. List `ruleNart` is 36 px (`:829–831`); builder `summaryArt` is 40 px (`:1637`); builder's **Rule review** identity `reviewIdentityArt` is 40 px (`:1864`). | `StartEdit` binds a private rule copy (`:272–287`). `eSave` calls `SaveRuleDraft` (`:1932–1955`); `eCancel` ends the draft (`:1927–1931`). Recipient/destination and rule writes remain atomic. |

Sources: [`LootRules.lua`](../../TwichUI_Settings/pages/LootRules.lua), [`MagicInventory.lua`](../../TwichUI_Settings/pages/MagicInventory.lua), [`loot/Config.lua`](../../!!!TwichUI/loot/Config.lua), [`inventory/Rules.lua`](../../!!!TwichUI/inventory/Rules.lua). Line numbers are baseline navigation aids.

Magic Inventory's `PaintRuleArtwork` (`:626` onward) also manages portrait masks for native item art. A future renderer must remove a stale mask when switching to transparent bundled art and restore the current native-item treatment when switching back. Do not change the existing automatic function globally: the rule drag ghost also calls it (`:768`), and that surface is outside this slice. The **Rule review** named above is the builder panel, not the runtime transfer review window.

## Proposed editor surfaces and action legibility

- Add **Choose icon…** beside the Loot editor's existing identity header, below the name/summary when necessary at narrow widths. It opens the shared picker; it does not change the name, On switch or action. Use the selected identity in only the list icon and editor header.
- Add **Choose icon…** at the Magic Inventory builder's identity/summary banner. Use it in only the rules list, builder summary and builder Rule review identity. The chooser is separate from **Choose items…** and category/filter artwork; choosing an item image never edits `include`, `exclude` or `cats`.
- Both use the same categorized/searchable thumbnail picker, current choice, staged preview, Apply, Cancel and **Use automatic icon**. Keep the existing item/game-icon browsing available; an item ID is only a visual reference here.
- **Use automatic icon** selects a staged automatic candidate. It takes effect only on picker Apply, under the consumer's normal commit model. Cancelling after staging it preserves the previous choice.
- Loot action choices retain their dedicated Need/Greed/Pass artwork and words. List status must always include the action words, including when a rule needs attention; current `LayoutList` replaces the whole state with “Needs attention” for incomplete rules (`:225–228`), so the future integration must retain an explicit action cue alongside that warning. The custom picture cannot be the sole action cue. Preserve “Do not roll”/display-only meaning where applicable.
- Magic Inventory retains the action/destination/keep chips (`RowCells`, `:560`; list `:838` onward), builder behavior/destination summaries and review fields. Custom art never replaces category choices, movement controls, recipient warning, enabled state, validation text or destructive-action icons. At narrow widths and larger fonts, move the chooser to its own line before clipping any action text.
- An unavailable selection shows the automatic image and plain status such as **Selected icon unavailable — showing automatic** in the editor/picker and the list tooltip. Preserve the reference; the player can restore automatic or choose another image explicitly.

## Proposed representation and ownership contract

Subject to owner review, each rule may have `artwork = Ref`; **absence (`nil`) means automatic**. No per-rule migration is implied: existing rules already omit it. These are bounded values, never texture paths, game links, frames, callbacks or arbitrary metadata:

| Ref | Structural validation proposal |
| --- | --- |
| `{ kind = "art", id = "shield" }` | String ID, 1–40 bytes, ASCII lower-case letters/digits/hyphens (`^[a-z0-9-]+$`). Existing stable artwork IDs stay unchanged. |
| `{ kind = "icon", id = "magicInventory" }` | Case-sensitive `R.Icons` key; string 1–64 bytes, ASCII letters/digits/underscore/hyphen (`^[A-Za-z0-9_-]+$`). Preserve camelCase; do not lower-case keys. Actual examples are in `Icons.lua:38` onward. |
| `{ kind = "item", id = 6948 }` | Finite integer 1–2147483647, matching `RM.ValidItem` (`reminders/Config.lua:73`), without a Workshop dependency. |

Only `kind` and `id` are copied into fresh references. Reject malformed types, unknown kinds, oversized strings, raw paths, links, nonfinite/fractional numbers and nested payloads. Distinguish **structurally valid but unresolved** art/icon/item IDs from malformed references: retain the former through read/write/duplicate/profile/backup paths and resolve to automatic art until usable. Do not require current catalog membership during persistence sanitation. Final field name and invalid-input reporting remain review decisions.

The shared picker's UI-only `{ kind = "automatic" }` is never serialized; Apply maps it to removing the override. A consumer resolver must not write during rendering or read-time fallback. Consumer setters and `CleanRule` own validated copies; no shared mutable reference table may connect the saved rule, picker, editor or duplicate.

Same-rule changes that affect automatic artwork or its label (Loot action; MI included items/categories/kind) invalidate/cancel the open session; reopen it with the current default. A staged candidate must not be applied against an outdated automatic preview. This adds no new callback API.

Align with the proposed shared API: `Open(owner, options)`, a single session token, `OnApply(ref) -> true | false, message`, `OnClosed(reason)`, and `Close(owner)`. Picker Apply succeeds only after the consumer accepts the candidate. Rejection leaves it open with the reason. `OnClosed` performs cleanup, never a save or draft reset. Revalidate owner token, original profile identity/generation, rule/draft identity and existence at Apply; a profile name alone is insufficient after reset/copy/switch-away-and-back. A stale callback must not write into whichever rule is now selected.

## Apply, cancel and lifecycle semantics

| Event | Loot rules | Magic Inventory |
| --- | --- | --- |
| Open/browse/select | No saved writes; preview candidate only. | No saved or parent-draft writes; preview candidate only. |
| Picker Apply | Validate and commit only artwork through a future module setter to the bound existing rule; refresh list/header. This is the save for that setting, consistent with current immediate controls. Do not invent a whole-rule Save button. | Validate and copy only artwork into the bound private draft. Refresh draft identity previews. The saved list remains unchanged until rule Save. |
| Picker Cancel/Escape/close | Discard candidate; saved identity unchanged. | Discard candidate; restore pre-open parent draft identity, including any earlier applied but unsaved choice. |
| Rule Save/Cancel | No such whole-rule transaction currently exists. | Save uses existing `SaveRuleDraft`; Cancel/discard drops artwork with the rest of the private draft. A failed Save retains the draft choice for correction. |
| Rule selection/replacement/deletion | Close/cancel the old picker before selection changes; validate again if callback races deletion. | Close/cancel before replacing/duplicating/ending a draft. Callback must not reach a newly created draft. |
| Page hide/settings close | Cancel picker and release preview/session; previously applied immediate value remains saved. | Cancel picker only. Existing page hide intentionally retains the parent private draft (`OnHide :2049–2061`); already-applied unsaved art survives hide/reopen with that draft. Do not introduce discard-on-hide. |
| Reopen | Read the currently bound rule's saved reference; no leaked preview or stale owner. | Reopen from current private draft if retained, otherwise a fresh clean saved rule. A new picker starts from that owner's current choice. |
| Profile apply/reset/copy | Cancel before stale callbacks can commit; redraw from current profile. Existing Loot subscription refreshes on `rules`/`profile` (`:678`). | Cancel picker and discard whole old draft, consistent with `Profiles.OnApply`/`EndEdit` (`:2086–2095`). New profile cannot inherit old unsaved art. |

A failed shared picker launch leaves the editor and its draft intact. Reopening creates no duplicate callbacks/widgets and never accepts an abandoned session's Apply. Settings close must cancel even when frame coordination hides a different child first.

## Persistence, duplication, sharing and compatibility audit

These are current source behaviors, not proof that a new field already survives them:

| Path | Current behavior and required future integration |
| --- | --- |
| Loot storage/read | `loot/Config.lua` stores profile `TwichUIDB.ui.lootRolls`. `View` (`:221–247`) explicitly constructs known top-level fields and copies condition fields; it currently **omits any artwork field**. `Active` (`:263`) exposes saved records to the decision engine; keep artwork ignored there. Future `View` and the setter must validate/copy the reference without making it part of decision criteria. |
| Loot duplicate | `Duplicate` (`:314–333`) assigns a fresh ID, disables the copy, adjusts name, copies conditions, but shallow-copies other fields. Adding a table override without an explicit fresh copy would alias it. Keep exact selected identity, automatic absence and valid unknown reference, independently; preserve existing disabled-copy convention. |
| Magic Inventory read/write | `CleanRule` (`inventory/Rules.lua:207–266`) constructs a whitelist of fields, so unsupported fields are dropped from the clean view. `Rules`/`Rule` return these clean copies (`:277–294`). `WriteRules` (`:563–569`), `SaveRule`, `ReplaceRules`, destination writes and `SaveRuleDraft` clean again. A mutation such as enable/move/delete can rewrite the list from clean views and remove unsupported fields. Every copy must include the new validated reference before relying on persistence. |
| Magic Inventory duplicate | `DuplicateRule` (`:899–912`) uses clean copies, new ID, disabled state, copy name, then `WriteRules`. Builder Duplicate (`MagicInventory.lua:1918–1920`) calls `CleanRule`, removes ID, disables, starts an independent **unsaved** draft. Both must preserve the reference by value after sanitation is extended; builder duplication must still write no rule until Save. |
| Profiles | `Profiles.lua` Extract/Prepare (`:176–205`) deep-copy allowed `modules/ui/gear` settings, including feature subtrees, and `CopyFrom` (`:371`) prepares/commits copies. Rule identity belongs with the rule in profile `ui`, not a global selected-art map. Saved art follows shared-profile conventions and remains independent on profile duplicate/copy. Account `magicInventory` recipients/protections stay outside profiles. |
| Saved settings and newer versions | `Persist.lua:5–18` distinguishes `TwichUIDB.schema` (currently 2) from feature/release versions, preserves unknown fields at its own normalization layer, and holds newer-schema roots unchanged. That root policy **does not override feature sanitizers**: today's MI clean/write paths drop unsupported rule fields, and today's Loot View hides them. Do not claim older addon readers preserve overrides. Schema/version strategy and downgrade expectations need review before persistence implementation; this batch changes no version. |
| Local backup/restore and portable backup text | `setup/Restore.lua:44–46` captures `ui` and profile roots; `CaptureOwn`/`CaptureFrom` deep-copy settings (`:120–142`). Thus future recognized saved rule refs belong in own-settings snapshots, including profile copies. Account `magicInventory` is explicitly excluded (`:53`). `OwnProblem` (`:86–109`) rejects unknown outer keys/newer schema; nested copied settings are not a per-rule feature contract. Subsequent feature reads/writes still apply sanitizers. Backup portability is not rule sharing. |
| Friend/setup sharing and rule import/export | `setup/TwichConfig.lua:50–90` explicitly keeps `ui.lootRolls` local as “acts” and `ui.magicInventory`/account `magicInventory` local as “other”. No standalone rule import/export is added. `docs/magic-inventory.md` “Persistence, profiles and sharing” confirms rules are not exported. Preserve this policy: an icon feature must not silently start exporting rules, recipients or new categories of settings. Any future rule transport needs its own bounded validation/version review; unknown catalog IDs in an otherwise supported ref should survive only in paths explicitly implementing that contract. |

There is no evidence here that an arbitrary old client, import route or cleanup preserves unsupported fields. In particular, a backup can retain bytes that a subsequent feature mutation removes. Future compatibility tests must cover the actual cleaner/write paths, not just root deep-copy behavior.

## Verification plan and review decisions

**Evidence for this document: source-inspected; addon behavior not tested in this docs-only batch.** Existing relevant tests establish patterns, not future artwork coverage:

- `tests/test_loot_rolls.lua`: rule validation/order, independent disabled duplication, profile notification, conservative automation and display-only behavior. `tests/test_loot_rolls_settings.lua`: settings serialization/load and legacy action/display behavior.
- `tests/test_magic_inventory.lua`: core rule management; `tests/test_magic_inventory_settings.lua`: private builder Save/Cancel, native-art mask cleanup, filter retention, page hide retaining draft, independent unsaved builder duplicate, bounded widget reuse. `tests/test_magic_inventory_recipient.lua`: atomic recipient/rule draft behavior. `tests/test_magic_inventory_editor.lua` covers the separate guild arrangement editor; retain its isolation.
- `tests/test_profiles.lua`, `tests/test_persist.lua`, `tests/test_group_restore.lua` and `tests/test_portable.lua` provide profile copy, root compatibility and backup validation coverage. They do not prove arbitrary new nested rule fields survive current feature sanitizers.

Focused future cases should cover: every ref type and boundary; malformed values; valid unknown IDs retained while fallback is visible; automatic restore Apply versus Cancel; Loot immediate persistence; MI picker Apply then rule Cancel/Save/failed Save; MI hide/reopen retaining draft; profile apply cancelling picker and draft; stale callbacks after selection/delete/profile replacement; independent override tables in both duplication routes and profile copies; read/write/enable/move/delete/backup round trips; existing friend-share exclusions; mask transitions; action words with incomplete Loot rules; unchanged loot decisions and inventory plans for identical behavioral fields with different artwork. Preview/runtime/drag visuals remain unchanged. Use the relevant settings simulator only when useful for layout/lifecycle evidence; it cannot certify real-client appearance or reload persistence.

Owner review is required for the proposed `rule.artwork` field, the kind/ID grammar and compatibility/version policy, the exact chooser placement and unavailable-status presentation, and the final shared picker contract. Confirm the agreed curated catalog and item/game-icon availability before extraction. This specification closes consumer discovery; it does not authorize either builder implementation. The shared foundation is implemented separately in Batch 6.
