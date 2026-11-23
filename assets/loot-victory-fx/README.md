# TwichUI — Supplemental Victory FX (v1)

This is a **lighting-only supplement** to the existing, already-implemented Loot Victory card and the prior `TwichUI_Loot_Victory_Assets.zip` package. It is **not a redesigned card or a full standalone victory system**.

## Handoff to Codex

1. Give Codex this ZIP plus the current in-game screenshot and the existing Loot Victory feature branch/PR.
2. Read `manifest.json` first, then `docs/INTEGRATION_AND_MOTION.md`.
3. Choose a small CORE set of assets, not every asset. These are separate transparent textures, **not** sprite sheets to display directly.
4. Copy only the chosen files from `runtime/tga/` into the addon. Keep `source/png` and `source/atlases` out of runtime builds.
5. Use client-owned item icons and existing card/frame artwork. Do not bake sample item names, quality labels, or roll values into images.
6. Use the existing animation timers / texture pool, with one-shot glows and small particle paths.
7. Demonstrate the animated effect via in-game preview and evaluate **normal UI scale**.

## Export details

- Every texture is **one individually cropped transparent FX overlay** on a power-of-two canvas.
- `runtime/tga/` contains 32-bit RGBA, uncompressed TGA texture files for conservative WoW-client compatibility.
- `source/png/` contains equivalent lossless alpha PNGs for editing.
- PNG and TGA pixel content was round-trip verified at export.
- `manifest.json` has each asset ID, role, coordinates, recommended vs optional, intrinsic canvas size, source atlas crop, useful content rectangle, and SHA-256 checksums.
- Source atlases are retained under `source/atlases/` for provenance. **Do not ship those atlases with the addon**.
- Use `previews/all_individual_textures.jpg` to see all assets against dark leather.
- `previews/comparison_illustrative.png` is a **composited illustration**, not a game screenshot or a validated in-client render.

## Important limitations

These textures were created from separate generative-image FX atlases; we cleaned faint alpha garbage and cropped/tiled them automatically. The production-format exports have passed structural and visual preview checks, but **no actual World of Warcraft Forever client has loaded them yet**. TGA support, additive blend appearance, clipping, layering, scale, and performance must be validated in the real client. Do not claim native visual acceptance before an in-game test.

There are **no new sound files** in this supplement. Existing victory sound assets and behavior remain unchanged.
