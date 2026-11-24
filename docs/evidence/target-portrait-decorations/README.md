# Target Portrait Decorations: reviewed simulator captures

Captured on 2026-11-24 with the pinned wow-ui-sim v0.1.37 and the actual
TwichUI controllers/settings/artwork. Every image below was opened and inspected.
Reproduce with `SIMLAB_ASSETS=0 bash tools/simlab/run.sh portraits` using the
existing installed simulator runtime (see [simulator lab](../../simulator-lab.md)).

These are **screenshot-reviewed synthetic structural evidence**, not real-client
acceptance. The runtime views use a synthetic EllesmereUI-shaped unit button,
a colored square portrait, simple health/resource bars and sample text. Modern
artwork is supplied production art, rendered by the actual target display;
legacy and player artwork use their actual existing renderers. Settings views
open the actual page with an empty synthetic profile and the feature enabled.
No live SavedVariables or third-party addon is loaded.

No licensed native game assets are installed in this environment. Native art,
models and addon fonts, actual EllesmereUI integration, pointer input, combat
lockdown/taint and persistence across reloads remain **not tested**. The simulator
uses font fallbacks and leaves some unrelated native UI text in the background.
The unrelated “Issue Report” remnant over the settings sample is simulator UI,
not part of the feature.

| Capture | Reviewed result |
| --- | --- |
| [Modern boss](boss.png) | Right-side aperture contains the portrait; ridge extends left; bars/text remain readable. |
| [Modern elite](elite.png) | Same aperture center/scale as boss; horns and tusks remain unclipped. |
| [Modern rare](rare.png) | Same aperture center/scale; authored silver/violet colors and alpha retained. |
| [Compact](compact.png) | 36-unit square portrait, inherited frame scale 2.8; proportional fitting. |
| [Tall](tall.png) | 76-unit square portrait, inherited frame scale 2.8; proportional fitting. |
| [Legacy](legacy.png) | Original boss dragon, original frame-corner geometry and proportions. |
| [Modern settings](modern-settings.png) | Actual-art style cards, selected/default state, right-sided sample; legacy controls absent. |
| [Legacy settings](legacy-settings.png) | Scrolled to actual appearance controls: opacity, scale, anchors, offsets, mirror and layer; fine-tune/reset disclosures retained. |
| [Player class decoration](player.png) | Existing Paladin renderer, same synthetic square aperture; player art remains aligned and bars/text clear. |

Runtime captures passed six controller/state checks each (player passed four).
Final settings captures passed six construction/state checks each, including
legacy scale-control visibility matching the selected style. These checks do
not substitute for the visual inspection above or the focused native checklist
in [feature documentation](../../target-art.md).

Raw ignored logs/captures: `portraits-F6XbkLm9` (five modern runtime views),
`portraits-XKvfnTcd` (legacy), `portraits-fafSqYez` (player), and
`portraits-ADiFA3VW` (final settings), under `test-output/simlab/artifacts/`.
