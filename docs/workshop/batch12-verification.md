# Batch 12 verification

Runtime source: `9467adb`, based on main `eb866ce`. Final documentation/evidence
commits do not change runtime source. All player/native checks remain unchecked.

## Unit-tested

The prepared Lua 5.1/simulator environment was initialized as documented in
[cloud environment setup](../cloud-environment.md). The affected selection was
previewed before execution:

```sh
./tests/run.sh integration workshop --with-group auction-house --profile cloud --list
./tests/run.sh integration workshop --with-group auction-house --profile cloud
```

All **130 selected offline modules passed**, with zero failures, and syntax
passed for **294 Lua files**, plus the runner's Python/shell checks. The broad
native-catalog phase was stopped and replaced with the focused commands below;
this is **not a complete integration-profile PASS** or full/release certification.
The initial integration attempt exposed four AH subscription-count regressions
from the merchant quote's global planner listener. `0511b05` scopes that listener
to visits; the unchanged cleanup assertions then pass. Review also found nested
unknown ownership; `9467adb` refuses that quote and adds regression coverage.
No existing assertion or negative control was weakened.

## Simulator-tested (focused, synthetic)

Commands, on frozen runtime source, with prepared cloud/no-assets environment:

```sh
SIMLAB_WORKER=1 SIMLAB_ONLY='craft shop small compact advisor ledger wrong' bash tools/simlab/run.sh workshop
SIMLAB_WORKER=2 SIMLAB_ONLY='guided mixed small' bash tools/simlab/run.sh testlab
SIMLAB_WORKER=2 SIMLAB_ONLY='shell replay wrong shopping sell owned' bash tools/simlab/run.sh auctionpreview
```

- Workshop assertion verdict: **PASS WITH KNOWN SIMULATOR LIMITATIONS**, six
  positive poses (533/533/534/534/537/540 assertions) and the deliberate
  wrong-material control. The outer wrapper exited 1 because an ignored
  `known_failures` Python cache was created during log review. No runtime source
  changed: all 391 staged Lua files compared byte-for-byte equal to the checkout.
  This is a wrapper failure, not a passing full command. A subsequent frozen
  `SIMLAB_ONLY='craft wrong'` run passed the wrapper and assertion verdict with
  the same known limitations; the existing negative control stayed intact.
- Test Lab: **PASS**, guided/mixed/small, no runtime errors classified in these
  selected logs. The script's generic screenshot inventory also names unrun
  poses; only these three were selected.
- AH preview: **PASS**, shell/replay/wrong/shopping/sell/owned, independent replay
  identical and wrong expectation retained other outcomes.
- Additional merchant capture: the existing Crafting fixture plus a final manual
  review step: **535 assertions, zero failed, no abort, quote visible and zero
  purchase calls**. Known voice-settings/UTF-8 simulator errors classified with
  the existing `known_failures` reader; no unknown/unexpected errors. See the
  [capture and reproduction](../evidence/batch12-merchant/README.md).

Workshop/merchant logs retain the existing simulator voice-settings and NPC
addon-message UTF-8 errors; these are not runs without runtime errors. Cloud
captures lack game assets and use fallback fonts. Structural screenshots and
handler-driven state do not establish native appearance/contrast, actual pointer
input, combat/taint, transaction delivery or persistence. Full default simulator
catalogs and the unrelated full/release gate were not completed. No live gameplay
action or purchase was performed. No performance claim or production mutation
campaign is implied by these results.

## Owner-directed native checks

Use the unchecked PR checklist and the feature-specific instructions:
[quality](batch12-quality.md), [merchant quote](batch12-vendor-assistance.md),
[craft evidence](batch12-craft-evidence.md),
[communication specification](../design/batch12-leave-me-alone.md), and
[party position finding](../design/batch12-party-death-markers.md).

Purchases require native stock/transaction evidence, F13 runtime waits for open
Fishing #143 and eligible audio capability proof, F18 needs fresh death-position
evidence, and automatic craft credit needs operation-correlated Forever events.
These evidence gates do not block review of the completed presentation/probe work.
