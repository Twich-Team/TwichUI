# Batch 12 quality presentation capture

`craft.png`: structural simulator capture from the W27 worktree based on main
`eb866ce`, with the W27 shared quality helper and Crafting material-row changes.
Command: `SIMLAB_ONLY='craft shop small compact advisor ledger wrong' bash tools/simlab/run.sh workshop`, cloud environment activation, `SIMLAB_ASSETS=0`.

Screenshot-reviewed: the existing Crafting layout, recipe names, quantity and
status columns remain distinct. The fixture uses common materials; it does not
prove multiple rarity colors. Missing icons/fonts/game surfaces in the no-assets
cloud mode make this unsuitable for native visual acceptance or contrast approval.
The material-row unit regression separately supplies verified enum values 0–8
through a synthetic quality provider. No in-game test is checked off.

## Follow-up: visible colors across the reported lists

The original common-material capture above did not demonstrate multiple colors.
These follow-up captures use the real revised Workshop UI with **synthetic item
quality metadata and a test color provider**. They are not live-client captures
or claims about the actual rarity of the named example items.

- [Craft Queue and materials](craft-colored.png): 540 assertions passed.
- [Shopping rows and selection](shop-colored.png): 543 assertions passed.
- [Opportunities rows, selection and materials](opps-colored.png): 545 assertions passed.

The checks read actual FontString RGB values and require uncommon, rare and epic
names in every selected list. Screenshot-reviewed: green/blue/purple names are
visible; prices, quantities, source/status text and action recipes (Smelt Bronze)
retain their original colors. Test quality enums 1–4 are declared by Forever
ItemQualitiesDocumentation. The test provider reads the repository's established
`R.LootRules.QUALITY_COLOR` palette (`!!!TwichUI/loot/Rules.lua`). Production still
uses verified live metadata and the client's quality colors/overrides.

Reproduce: generate the existing craft/shop/opps fixtures with
`tools/simlab/run.sh workshop`, insert [mixed-quality-step.lua](mixed-quality-step.lua)
before the disposable fixture's final `Lab.Finish()`, then run that fixture with
the existing sandboxed `tools/simlab/sim.sh` screenshot command, 1600x1200,
no saved variables, no game assets. The added step exercises the actual Window
metadata handler with item-ID/success payloads, redraws, then checks the fonts.

Preliminary test fixtures exposed simulator limitations: the native quality
getter was unavailable and its native palette was white for every quality. The
scenario's Event(name) helper discarded item IDs, causing unrelated Blizzard
popup/trade-frame errors when broadcast, and the added work exceeded the baseline
45-second limit. The final fixture supplies the existing TwichUI palette only in
test data, calls the Workshop metadata handler with the proper payload, and uses
a 60-second budget for the added step. Baseline checks were not shortened;
production and simulator implementations were not patched to mask these failures.

Final captures finish without failed assertions or aborts, and the existing error
classifier finds zero unknown/unexpected errors. Existing voice-settings
and NPC addon-message UTF-8 simulator errors remain in the logs. No native
installation, real item metadata, game icons/fonts or client appearance is
verified by this fixture.
