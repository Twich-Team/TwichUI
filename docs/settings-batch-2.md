# Specialized settings Batch 2

Implementation uses the existing shared settings materials and controls. No defaults, computation, SavedVariables schema,
profile ownership, import formats, narration or guide content changed. The contract fixture diff changes presentation rows
only. Stat weights are TwichUI defaults plus manual overrides, with no optional weight provider.

| Page | Before | Implementation | Existing coverage | Added coverage |
|---|---|---|---|---|
| Stat weights | Long numeric grid, no focused browsing | Group filter, taller fields, explicit source/effect, concise restore instructions; priority mode retained | Gear window, gear evaluation/prefs | Group filtering preserves saved values; simulator filtering/restoration and unsupported-class state |
| SpeakStone | Integration status hidden in tooltips; playback controls among common reading settings | Visible availability/look status, gated sample command, Reading/Frame/Advanced tasks; optional playback disclosure | SpeakStone skin lifecycle/source-shaped fixture | Preference retention absent/available/disabled; action prerequisites; UI menus/navigation |
| RestedXP | Appearance enablement buried after guide automation | Setup first, visible availability/look status, readiness/conflict-gated theme action; separate behavior/style tasks | Skin, timers, waypoint, autohide and tracker tests | Preference retention and actions absent/available/disabled; UI task/menu/navigation; narrow task label bounds |

## Reuse the simulator coverage

Run from the repository root (bash):

```sh
SIMLAB_SETTINGS_INTEGRATION='"available"' bash tools/simlab/settings.sh statWeights speakstone restedxp
SIMLAB_SETTINGS_INTEGRATION='"absent"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh statWeights speakstone restedxp
SIMLAB_SETTINGS_INTEGRATION='"disabled"' SIMLAB_SETTINGS_POSE=narrow bash tools/simlab/settings.sh statWeights speakstone restedxp
SIMLAB_SETTINGS_INTEGRATION='"available"' SIMLAB_SETTINGS_EDITOR=true bash tools/simlab/settings.sh statWeights speakstone restedxp
```

The runner stages disposable addon copies. Integration fixtures override only the status contract and enable the
synthetic profile's look switch, without loading or calling third-party addons. Available means a supported provider
in the UI fixture; disabled means provider available with TwichUI's integration off. Absent preserves editable
preferences. Skin-engine tests use their existing more detailed source-shaped addon fixtures. Neither proves actual
installed-addon compatibility. Inputs invoke handlers; real pointer and keyboard delivery remain client checks.

## Screenshot review

Captures are untracked lab artifacts under `../wow-ui-sim-lab/artifacts/` (not production assets or approved golden images):

- `settings-20261111-101724/`: wide normal available captures of all three pages, opened and reviewed.
- `settings-20261111-101820/`: narrow absent captures of all three pages, opened and reviewed. RestedXP task label
  overflow was detected and corrected to “Arrow / timers”.
- `settings-20261111-101922/`: narrow disabled captures of all three, opened and reviewed; corrected task label fits.
- `settings-20261111-102008/`: focused group/appearance menus after refinement, opened and reviewed.
- `settings-20261111-102134/`: final absent-state rerun, both integration captures opened and reviewed; all checks pass.

Review shortened the weight explanation to clear the list, shortened the skin introductions while retaining full help,
and corrected the narrow task label. Materials reuse canonical walnut/espresso; no new artwork family or gameplay
preview was introduced. Native Cinzel/localized text, actual optional addon frames and input must be reviewed in client.

## Client acceptance

Stat weights: edit/clear/Escape, switch trees while editing, numeric/priority mode, reset scope and reload persistence.
SpeakStone: sample without narration, actual dialogue/queue, supported fonts, disable restoration and absent-addon values.
RestedXP: actual theme selection/restore, conflicting skins, v2 window, arrow/timer rendering, autohide combat deferral,
waypoint ownership and optional EllesmereUI tracker. No page is marked Verified until that evidence is recorded.

## Verification result

- Unit-tested: full suite 188 passed, 0 failed; new specialized-settings test and final gear/design/window tests passed separately.
- Simulator-tested: stat group browsing/unsupported class 16 checks; available editing captures SpeakStone 25, RestedXP 27;
  final absent captures 24/26; disabled narrow captures 22/24. Checks are handler/state assertions.
- Screenshot-reviewed: all sets listed above; no unresolved structural overlap in the reviewed states. Screenshot/font
  limitations remain as documented by the simulator lab.
- Real-client-tested: not performed. All three pages remain unverified in client.
