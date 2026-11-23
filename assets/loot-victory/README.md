# TwichUI — Loot Victory asset kit

A production-exported **art kit** for a custom WoW loot roll **You Won** result; not an implemented addon feature.

## What is included

- `textures/tga`: 32-bit RGBA, power-of-two texture dimensions. **Recommended for maximum WoW client compatibility.**
- `textures/png`: matching source-compatible images, also power-of-two. PNG loading depends on the client build.
- `sources/loot_won_frame_master.png`: high-resolution artist-facing master for future re-export.
- `audio/*.ogg`: two original, restrained optional sounds (victory, greed).
- `audio/*.wav`: editable reference masters; **use .ogg for WoW**.
- `previews/victory_static_preview.png` and `victory_motion_preview.gif`: design preview, not game screenshots.
- `manifest.json`: texture sizes, UV crop, intended use, frame timings.
- `docs/IMPLEMENTATION_SPEC.md`: integration instructions and test criteria.

## Critical authoring rules

Render `YOU WON!`, item names, rarity, type, roll result, upgrade status, and inventory status dynamically in Lua. Do **not** crop these from concept images. The item icon in the preview is a placeholder; obtain the true icon from the game API. Do **not** display `Added to your inventory` until acquisition is independently confirmed, if at all.

The 1024×512 frame texture has an image area 1024×444 high; bottom remainder is intentionally transparent. Display with UV crop `0,1,0,444/512` at 460×200 UI pixels. Consider frame-size scaling separate from UI scale. Test on the actual Forever client before shipping.

Motion is restrained, one-shot, frame-time based. Emblems and small sprites are editable independent layers. No big zoom, bounce, looping gold shower or full-screen effects.

## Integration recommendation

Start with the static victory card and verified suppression of the **matching** default WoW alert, then add title reveal, trim sweep, particles, and optional sound in separate commits. Reuse TwichUI's existing loot card settings/positioning. Preserve normal Blizzard achievement and other alerts.

## Provenance and test status

The frame and bronze small decorative assets are newly generated artwork; several effect textures are newly composed using deterministic alpha shapes for reliable blending. No licensed WoW icon art is packaged. PNG and TGA alpha have been validated programmatically, but no real WoW Forever runtime or rendering test has been run.
