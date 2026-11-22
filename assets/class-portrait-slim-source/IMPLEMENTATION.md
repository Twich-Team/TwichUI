# TwichUI compact alternate artwork — integration handoff

This package is a **review candidate**, not a verified production-ready texture set. All 9 files are separate 1536×1536 RGBA PNGs on transparent square canvases. Native art was not upscaled or cut from a contact sheet. Mage, Warlock and Druid currently use earlier rugged artwork, not new compact redraws.

## Integration guidance
- Keep the existing full-size class artwork and add a separate `Compact` style selection.
- Map class file tokens WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID to these files.
- **Do not assume identical portrait-opening bounds.** Inspect alpha masks and determine per-class transparent opening coordinates. Store opening rectangle in per-class metadata after validation.
- Align each opening to the EllesmereUI portrait using effective UI scale and preserve artwork aspect ratio. Let the player manually adjust size and x/y offsets per style.
- Validate transparent openings, pixel-alpha edge halos, visual appearance at real UI scales, texture format compatibility, and combat-safe anchoring in WoW Forever.
- Do not ship until the Mage, Warlock, Druid compact designs are approved and portrait alignment is tested.
