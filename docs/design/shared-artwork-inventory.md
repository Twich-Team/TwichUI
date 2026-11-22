# UX02: existing artwork candidates

Discovery inventory for the proposed shared picker, not an implemented catalog or an approval to add entries. The current Reminders catalog has 79 entries: 67 generated pictures, four earlier artworks, and eight registered icons. `reminders/ArtData.lua` and `reminders/Gallery.lua` define those entries and their distinct saved targets. Preserve their existing IDs and mappings; none of the rows below is already a catalog entry. Subject overlap is noted where relevant. This selection is intentionally bounded, not an import list.

The **28 candidates** below have proposed names and categories. Proposed references for registered icons use their existing `R.Icons` keys; unregistered artwork uses provisional `art-...` IDs. These new IDs are not approved or persisted. A shared reference could use `{kind="icon", id=<existing key>}` or `{kind="art", id=<stable art ID>}`; preserve existing Reminders values and resolve unregistered artwork explicitly before exposing it. A catalog key such as `icon-<key>` is UI-only, not the saved icon ID. Do not infer that every registry entry is suitable or that a path is itself a saved identity.

## Candidates

Paths in the table are exact repository runtime files. For each pair, the first path is the 64 × 64 file and the second is its 32 × 32 small variant. In game they are addressed under `R.PATH` as `media\...`, normally without `.tga`. These files already exist. The 32 px file is the existing small variant, not a newly generated asset. Existing `R.Icons.Path` switches to the small variant at 26 UI units; other sources do not automatically acquire that behavior in a future shared picker.

| Proposed reference | Name | Category | Runtime files (`!!!TwichUI/media/`) | Existing registry key / rationale |
|---|---|---|---|---|
| `art:art-herbs` | Herbs | Supplies | `icons/magic-herbs.tga`, `icons/magic-herbs-small.tga` | Unregistered; clear material family. |
| `art:art-ore` | Ore and metal | Supplies | `icons/magic-ore.tga`, `icons/magic-ore-small.tga` | Unregistered; dark at 24 px. |
| `art:art-leather` | Leather | Supplies | `icons/magic-leather.tga`, `icons/magic-leather-small.tga` | Unregistered; rolled material. |
| `art:art-parts` | Engineering parts | Supplies | `icons/magic-parts.tga`, `icons/magic-parts-small.tga` | Unregistered; cog silhouette remains visible. |
| `art:art-elemental` | Elemental material | Supplies | `icons/magic-elemental.tga`, `icons/magic-elemental-small.tga` | Unregistered; blue spiral, interpretation benefits from label. |
| `art:art-explosives` | Explosives | Supplies | `icons/magic-explosives.tga`, `icons/magic-explosives-small.tga` | Unregistered; bomb is dark at 24 px. |
| `art:art-enchanting-materials` | Enchanting materials | Supplies | `icons/magic-enchanting.tga`, `icons/magic-enchanting-small.tga` | Unregistered; distinct from weapon oil; details are small. |
| `art:art-shipping-crate` | Shipping crate | Supplies | `icons/magic-waylaid-crate.tga`, `icons/magic-waylaid-crate-small.tga` | Unregistered; useful container distinct from backpack. |
| `art:art-unbound-chain` | Broken chain | Equipment | `icons/magic-unbound.tga`, `icons/magic-unbound-small.tga` | Unregistered; unbound equipment; thin at 24 px. |
| `art:art-cloth` | Cloth bolts | Supplies | `npcs/cloth-bolts.tga`, `npcs/cloth-bolts-small.tga` | Unregistered; materials rather than the existing stained cloth. |
| `art:art-tabard` | Tabard | Equipment | `npcs/tabard.tga`, `npcs/tabard-small.tga` | Unregistered; distinct equipment slot. |
| `art:art-paw` | Paw | Adventure | `npcs/paw.tga`, `npcs/paw-small.tga` | Unregistered; pet/companion symbol. |
| `art:art-gavel` | Gavel | General | `npcs/gavel.tga`, `npcs/gavel-small.tga` | Unregistered; auction or decision; small head at 24 px. |
| `art:art-wing` | Wing | Adventure | `npcs/wing.tga`, `npcs/wing-small.tga` | Unregistered; flight; thin at 24 px. |
| `icon:auctionHouse` | Merchant scales | General | `icons/auctionHouse.tga`, `icons/auctionHouse-small.tga` | `auctionHouse`; commerce, fine pans at 24 px. |
| `icon:vendors` | Market stall | General | `icons/vendors.tga`, `icons/vendors-small.tga` | `vendors`; vendor/trade. |
| `icon:appearance` | Palette and brush | General | `icons/appearance.tga`, `icons/appearance-small.tga` | `appearance`; customization/crafting. |
| `icon:explore` | Spyglass | Adventure | `icons/explore.tga`, `icons/explore-small.tga` | `explore`; discovery; narrow at 24 px. |
| `icon:navigation` | Compass | Adventure | `icons/navigation.tga`, `icons/navigation-small.tga` | `navigation`; navigation distinct from marked map. |
| `icon:mapPins` | Map pin | Adventure | `icons/mapPins.tga`, `icons/mapPins-small.tga` | `mapPins`; location marker with ripple. |
| `icon:markers` | Pennant | Adventure | `icons/markers.tga`, `icons/markers-small.tga` | `markers`; standalone flag, distinct from combat banners. |
| `icon:summons` | Portal | Adventure | `icons/summons.tga`, `icons/summons-small.tga` | `summons`; travel or summoning. |
| `icon:resurrection` | Resurrection | Character | `icons/resurrection.tga`, `icons/resurrection-small.tga` | `resurrection`; winged ankh differs from existing healing hand. |
| `icon:quickKeybind` | Key and keycap | General | `icons/quickKeybind.tga`, `icons/quickKeybind-small.tga` | `quickKeybind`; key silhouette, tiny keycap detail. |
| `art:art-dice` | Dice | General | `loot/dice.tga`, `loot/dice-small.tga` | Unregistered; random roll. |
| `art:art-crown` | Crown | General | `loot/crown.tga`, `loot/crown-small.tga` | Unregistered; winner/leadership. |
| `icon:lootGreed` | Coins | Supplies | `loot/greed.tga`, `loot/greed-small.tga` | `lootGreed` and `lootRolls` resolve to the same file; one entry only. |
| `icon:lootQuality` | Green gem | Supplies | `loot/gem.tga`, `loot/gem-small.tga` | `lootQuality`; distinct color and shape from existing red/blue crystals. |

## Suggested first slice

Recommend **20 first-slice candidates**, with **eight conditional candidates** held
for closer 20–32 px/light-surface review: Ore and metal, Explosives, Enchanting
materials, Broken chain, Gavel, Wing, Spyglass, and Key and keycap. These are
priorities for owner review, not approved catalog entries. Keep their proposed
IDs reserved only if approved; do not import all 28 by default.

At implementation, include short lower-case search keywords alongside these
names/categories (for example Herbs: `herb plant reagent alchemy`, Shipping
crate: `crate cargo container supplies`, Merchant scales: `auction trade sell
balance`, and Paw: `pet companion animal`). Review synonyms in the same content
commit; a new metadata-only row must follow the existing plain-text search rules.

## Provenance and review

- The nine `magic-*` candidates are standalone Magic Inventory illustrations. `assets/magic-inventory/README.md` records generated transparent source PNGs, subject descriptions, 64/32 output and the `tools/make_magic_reagents_art.py` pipeline. Source for each is `assets/magic-inventory/<runtime stem without magic->-source.png`.
- NPC candidates come from `assets/npc-art-source.png`, cut by `tools/make_npc_art.py`; see the shared engineering rules and `!!!TwichUI/npcs/Kinds.lua`. The settings-sheet candidates come from `assets/settings-icons-source.png`, `assets/settings-icons-2-source.png`, or `assets/settings-icons-3-source.png` (`quickKeybind`), cut by `tools/make_settings_icons.py`; see `docs/settings-icons.md` and `!!!TwichUI/Icons.lua` for mappings. Loot glyphs come from the approved card mockup (`dice`, `crown`, `greed`) or rule-builder mockup (`gem`), via `tools/make_loot_roll_art.py`.
- **Screenshot-reviewed offline:** a temporary contact sheet of 103 full-size icon, loot and NPC files at up to 48 px, plus a 24 px rendering of selected 32 px files on a dark surface. This is a visual shortlist, not a systematic contrast or native-client test at every size/background. Fine details and dark shapes called out above may need further 20–32 px review; subject interpretation is sometimes aided by the label. No new artwork was created or generated.

## Exclusions and decisions

The existing 79 remain the baseline: skip copies or close subject alternatives such as the extra bell, food, bedroll, backpack, horse, hourglass, horn, staff, shield, potion and scroll variants unless a later review finds a compelling distinction. Skip duplicate registry aliases (`lootType`/`lootSlot`, `lootGreed`/`lootRolls`), UI-specific editor/diagnostics glyphs and feature logos without a useful rule identity. Quality-tier illustrations are attractive but their intended meaning depends on labels and color; choose whether quality semantics merit a cohesive group before adding any. Status checks, crosses and prohibition marks can imply application state rather than user-selected identity; assess them separately. Borders, panel faces, backgrounds, bars, textures, large illustrations and loot victory effects are not standalone symbolic picker art.

Open decisions: approve the shortlist and categories; confirm provisional art IDs and the proposed per-source resolution contract in [the picker design](shared-artwork-picker.md); preserve existing Reminders values and labels; review the weakest 20–32 px candidates on light and dark surfaces and in the actual consumers. This document makes no claim of real-client testing, and no schema, catalog, asset or picker behavior has changed.
