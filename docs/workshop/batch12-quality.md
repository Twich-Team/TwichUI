# W27 — Workshop item-quality presentation

Implemented for review, with the Opportunities material list deferred to avoid
competing with open PR #117. No price, recommendation, ordering, ownership,
recipe identity, tooltip or transaction behavior changed.

`Style.lua` provides two small presentation helpers: `UI.ItemQuality` for an
item-only font string and `UI.QualityText` for an item name sharing text with
quantity or status. Each fill uses current verified quality, preferring the
client's `C_Item.GetItemQualityColor` and then `ITEM_QUALITY_COLORS`. Unknown
quality uses Workshop's readable ivory text, rather than assuming common.
Recycled font strings reset on every fill. No quality is inferred from a name,
price or category.

## Surface audit

| Surface | Treatment |
|---|---|
| Overview | Its opportunity and queue entries name recipes; profession, status and action labels retain semantic colors. No actual material-name list is present. |
| Opportunities | Recipe headings/rows remain recipe labels. Its actual material names need the same helper, but changes to `ViewOpportunities.lua` are deferred while #117 remains open. |
| Item Advisor | Existing item-name coloring now shares the helper, including neutral unknown metadata and selected-item resets. |
| Craft Queue and selected craft | Entries/heading name recipes and retain their original text color. Their **Materials needed** list colors actual material names only. |
| Shopping | Actual materials in rows/details and verified recipe-output names in consumer rows use quality colors. Recipe-only consumer fallbacks stay neutral. |
| Compact Travel | Only the material-name span is colored; quantity and source/status stay unchanged. Compact Craft entries name recipes and remain neutral. |
| Crafting Strategy | Buy/collect material-name suffixes use quality; action words and counts retain their original color. Craft steps identify recipes. |
| Gold Ledger | Actual identified transaction item-name prefixes and realized-result names use current item quality. Counts, character suffixes, money, source labels and unattributed notes keep their colors. No recorder/query changes overlap #98. |
| AH Browse/Owned/Sell/Shopping/Market | Existing item-name coloring shares the verified-quality helper; selected details and empty selections reset consistently. Category/data-quality labels retain their original colors. |

Workshop and Compact already listen for delayed `GET_ITEM_INFO_RECEIVED`;
`ITEM_DATA_LOAD_RESULT` now also schedules their existing redraw path. AH pages
retain their existing metadata listeners and refresh scheduling. No new ticker,
frame or retained item cache is introduced. No extra diagnostic gauge is needed
for this bounded presentation-only helper.

## Evidence and limits

Source evidence: read-only Forever UI source branch `forever`, commit `bebcb6b`:
`Blizzard_APIDocumentationGenerated/ItemQualitiesDocumentation.lua` defines
Poor=0, Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Artifact=6,
Heirloom=7, WoWToken=8. `Blizzard_Colors/Mainline/ColorManager.lua` populates
`ITEM_QUALITY_COLORS` from client color overrides; native merchant UI uses
`C_Item.GetItemQualityColor`. Runtime uses these providers rather than copied
RGB constants. Test RGBs are explicitly synthetic provider values.

Unit-tested: `test_workshop_item_quality.lua` covers every supported quality,
unknown/invalid/secret quality, provider failure/fallback, pooled reset, and
bounded inline name coloring. `test_workshop_window.lua` exercises actual
material rows with qualities 0–8, both metadata events, recycled unknown items
and normal/narrow row widths while preserving recipe/quantity text.
`test_workshop_strategy_ui.lua` passes with the final strategy adaptation.

The initial development Workshop run passed 102 selected modules; the new
quality test assertions passed but its output lacked the runner-required uppercase
`PASSED` marker, and its source-integrity guard also rejected edits made during
the run. The marker was corrected and the focused test passed. The consolidated
branch must be checked frozen; the initial run is not a passing profile.

Native acceptance remains unchecked. In game, inspect common, uncommon, rare
and epic actual materials in Crafting/Shopping and item lists in Advisor,
Ledger and AH. Switch selection, scroll recycled rows, reopen after delayed
item loading, and try a narrow window. Confirm counts, prices, statuses and
recipe/action/category labels retain their original colors. Review poor-item
contrast on the actual dark surface; simulator fonts/artwork are not visual
acceptance. No player checklist is checked off by offline tests.

Focused simulator check: `SIMLAB_ONLY='craft shop small compact advisor ledger wrong'
bash tools/simlab/run.sh workshop` passed with known simulator limitations:
Craft/Shopping 533 assertions each, narrow/Compact 534 each, Advisor 537,
Ledger 540; the deliberate wrong-material expectation failed exactly once and
all other controls held. Classified existing simulator UTF-8 addon-message and
voice-settings errors remain in the log; this is not a runtime-error-free run or
complete regression coverage. [Representative capture and limits](../evidence/batch12-quality/README.md).
The simulator roots were prepared before the final Ledger suffix refinement;
the final Ledger unit test passes, and combined frozen-source verification is
required for final-branch evidence.

Final combined-branch evidence, including the wrapper cache exception and passing
Crafting/negative-control rerun: [Batch 12 verification](batch12-verification.md).
