# UX01 visual artifacts

These are annotated **design wireframes**, not a running addon, pixel baselines,
finished high-fidelity mockups or native/simulator evidence. Read the
[design review and implementation specification](../qol-settings-redesign.md).

| Artifact | What it demonstrates |
| --- | --- |
| [A — overview](option-a-overview.png) | Compact primary rows, with no detail open; later groups remain below the viewport |
| [A — expanded](option-a.png) | One selected feature's secondary controls and explicit sample/help actions; combat-resurrection policy remains visible in its separate overview row |
| [A — minimum height](option-a-minimum.png) | Existing 936 × 480 logical shell with full-width controls and scrolling |
| [B — selected detail](option-b.png) | Feature rail and 432-unit detail pane, stacked labels, an intentionally open sample illustration |
| [B — minimum height](option-b-minimum.png) | Short independent panes and more inner scrolling at 936 × 480 |

All images are exported at 2×; annotation margins lie outside the 936-wide
Settings shell. The normal shell is 660 high. Existing minimum width is also
936: these shorter poses do not propose a new narrower window or smaller text.
Synthetic On/Off values demonstrate selection; they do not change or describe
new defaults. Nine real samples remain in the specification; B illustrates one
sample's subject, not a faithful redraw of its current animated popup.

Materials and provenance (existing files used for these documentation images):

- `!!!TwichUI/media/style-v2/craft/{frame,selection,field,button}.tga`: nine-slice
  frame/control relief following `CraftLook.Sheet` source-cut proportions.
- `!!!TwichUI/media/reminders/materials/grain-{outer,header,recess,viewport,card,editor}.tga`:
  quiet leather surface samples. Container outlines/switches are wireframe shapes,
  not a replacement for the actual Material/checkbox renderer.
- Existing `media/icons/` home, notifications, reminders, qualityOfLife,
  journeyChronicle, navigation, summons, resurrection and declineDuels artwork;
  `media/healerwatch/vessel.tga`. These remain bundled runtime files unchanged.
- Existing `media/fonts/AlegreyaSans-{Regular,Bold}.ttf` and
  `media/fonts/Spectral-Medium.ttf`; actual runtime locale/font fallback and
  final text measurement must be checked in the later implementation.

Coordinates and control hierarchy are in the linked specification. Raster
composition is a design aid only; no source artwork was regenerated or imported,
no runtime texture was edited, and no external stock images were used. The
actual native shell input, hover/focus, scroll behavior, font rendering, disabled
states and scale fidelity cannot be certified from these images.
