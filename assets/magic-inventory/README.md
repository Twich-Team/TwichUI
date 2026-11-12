# Magic Inventory illustration sources

Generated for the final Magic Inventory refinement using the built-in image generation tool, one standalone
asset per request, with `transparent_background: true`. Source PNG alpha is retained. No labels or UI screenshots
are embedded in these files. The first three subject descriptions below record the intended object; the remaining
subjects and shared prompt are the generation text.

## Shared prompt

> Use case: stylized-concept. Asset type: ONE standalone transparent small fantasy inventory UI illustration for TwichUI, designed to read at 20–28 pixels. Premium hand-painted Warcraft-like fantasy interface craftsmanship, shallow sculpted relief, broad simple silhouette, soft upper-left lighting, muted aged bronze, dark walnut/espresso shadows, warm ivory highlights, fine restrained detail. Centered isolated object, generous transparent padding. No background, no square tile, no frame, no badge, no text, no letters, no glow, no neon, no heavy ornament. Genuine transparent alpha. Subject:

## Subjects

- `quality-poor-source.png`: a battered pewter cup with a small crack, dull grey metal, simple worn everyday object.
- `quality-common-source.png`: a simple unadorned iron ring with a warm ivory inset, plain common-quality everyday object.
- `quality-uncommon-source.png`: a small bronze-and-leather talisman with a muted sage-green stone, uncommon-quality treasure.
- `quality-rare-source.png`: a refined silver brooch holding a faceted desaturated blue sapphire; rare-quality treasure; strong diamond silhouette, restrained bronze accents.
- `quality-epic-source.png`: an angular amethyst crystal set in a small aged-bronze claw mount; epic-quality treasure; muted violet crystal, tall prismatic silhouette, no magical glow.
- `herbs-source.png`: three sage-green medicinal leaves and a short root bound loosely with twine, recognizable herb bundle; no cloth, no bottle.
- `leather-source.png`: a short rolled piece of tawny leather with one stitched edge and a loose leather strip, recognizable leatherworking material.
- `ore-source.png`: two rough dark iron ore nuggets beside one small muted silver ingot, mineral and metal crafting materials.
- `enchanting-source.png`: a small open bronze-rimmed dish of muted purple arcane dust beside two ivory crystalline shards; enchanting materials, no glow.
- `elemental-source.png`: a single blue-grey swirling elemental stone core encircled by a shallow bronze band; physical coiled shape, no glow or aura.
- `elixir-source.png`: a squat amber glass alchemy flask with a narrow neck, a dark leather stopper and aged bronze collar; a restrained gold-brown medicinal elixir.
- `explosives-source.png`: one round dark iron engineering bomb with a short unlit rope fuse and aged-bronze cap; absolutely no spark or fire.
- `parts-source.png`: one small aged-bronze cogwheel leaning against two short steel bolts; recognizable engineering spare parts.
- `unbound-source.png`: a short open bronze chain with one clearly separated broken link, arranged in a compact diagonal silhouette; free and unbound equipment, no lock.

## Runtime preparation

Run `python3 tools/make_magic_reagents_art.py` from the repository root. The established alpha-aware pipeline crops
transparent padding, resamples to fit a 6-pixel outer margin, bleeds RGB beneath alpha and emits
`!!!TwichUI/media/icons/magic-<name>{,-small}.tga` at 64 and 32 pixels, 32-bit RGBA.
The 32-pixel assets are displayed at 18–26 units in native controls; the larger variants serve rule identities.
All 14 sources and 28 runtime textures were checked for transparent alpha and expected dimensions.
Sources stay outside production packages via the existing `assets` exclusion.

Existing cloth, food, potion, scroll, shield, pack, tabard and reagent-pouch illustrations complement this set.
Artwork selection is presentation only. Unknown/unlocalized category families use the neutral reagent pouch;
item classification and saved category keys are unchanged.

See [implementation evidence](../../docs/magic-inventory-revision/implementation.md) for screenshot review and limits.
