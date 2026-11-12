# Batch 3: item and channel editor completion

Builds on Batch 1. Item names now occupy a bounded two-line region with a separate status baseline and full names
in the item tooltip. This keeps long names from colliding with classification or quantity controls. Success notices
no longer repeat arbitrarily long item names. Item rows use the shared recessed well without bright alternating fills.
Channel names also wrap; quiet bronze dividers separate their filter groups. Paused saved channels remain discoverable
when unjoined. Opening the page never joins or leaves channels. No engine, schema, defaults or validation changed.

No extra disclosure was added: these are direct editors, and the six named per-channel choices already fit two rows.
Restock mode/spending and other feature configuration remain on the existing parent page.

## Reusable coverage

The existing runner accepts `SIMLAB_SETTINGS_DATA` in addition to its prior filled/editor/narrow options:

```sh
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_DATA='"stress"' bash tools/simlab/settings.sh ammoCustom chatCleanChannels restockItems
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_EDITOR=true SIMLAB_SETTINGS_DATA='"unavailable"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh ammoCustom chatCleanChannels restockItems
SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_EDITOR=true SIMLAB_SETTINGS_DATA='"stress"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh ammoCustom chatCleanChannels restockItems
SIMLAB_SETTINGS_DATA='"empty"' bash tools/simlab/settings.sh ammoCustom chatCleanChannels restockItems
```

Fixtures replace item lookup/ScanBags and KnownChannels only inside the isolated simulator. Production resolution is
unchanged. Stress uses long names and lists, alternating joined/unjoined channels and paused choices; unavailable uses
unresolved item names and unknown bag counts. Empty removes item entries and supplies no channels. Existing handlers
cover registration/classification, filters, quantity edits, rejection/restoration of zero, menu/focus states, scrolling,
away/reopen and caching. Added assertions ensure name regions clear status regions. Unit coverage additionally checks
paused unjoined saved channels remain editable. These are handler tests, not actual pointer delivery or chat-server tests.

## Screenshot review

Untracked lab captures under `../wow-ui-sim-lab/artifacts/`, opened and inspected:

- `settings-20261111-102648/`: wide long-name/populated stress. Name/status separation and channel groups were readable;
  long success notices clipped and were shortened afterwards.
- `settings-20261111-102744/`: narrow unresolved names, dropdown and quantity editing; concise messages fit.
- Final stress and empty capture paths and verification results are recorded below.

These are reviewed structural captures, not approved pixel baselines. The simulator substitutes fonts and some game
textures. Full-name tooltips preserve access beyond the two-line row region. Unknown bag counts are never treated as
zero by production Status; unresolved item details remain an honest loading state.

## Client acceptance

All three pages are Substantially modernized, not Verified. Native item names/icons, localized channel names, real
pointer/keyboard focus and Escape, item drag/cursor return, reload/profile persistence, channel events and secure
client behavior remain client checks. No gameplay transaction was performed. No optional external addon is required.

Final captures (each opened and screenshot-reviewed):

- `settings-20261111-102834/{ammoCustom,chatCleanChannels,restockItems}.png`: final narrow stress/editing/validation;
  30/31/32 handler/state checks passed.
- `settings-20261111-102919/{ammoCustom,chatCleanChannels,restockItems}.png`: empty states; 20/25/22 checks passed.

## Regression commands

```sh
./tests/run.sh
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_ammo_items_settings.lua)
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_chat_clean.lua)
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_restock_settings.lua)
```

Focused tests pass. Existing unit cases retain validation, classification, ordering, cursor refusal/return and profile
refresh coverage. Saved-setting contract/default tests are unchanged. No live SavedVariables or deployment was touched.
For resolved items with unavailable bag counts, run
`SIMLAB_SETTINGS_FILLED=true SIMLAB_SETTINGS_DATA='"inventory"' bash tools/simlab/settings.sh restockItems`.
The scenario explicitly checks the unknown-count message rather than displaying zero.

Final verification: `./tests/run.sh` — 189 passed, 0 failed. Lua 5.1 syntax checks on all edited Lua files and
`bash -n tools/simlab/settings.sh` passed. `git diff --check` passed. The separate unknown-inventory capture
`settings-20261111-103020/restockItems.png` was opened and reviewed; all 24 scenario checks passed.
