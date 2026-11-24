TwichUI Target Frame Variants Production

Contents
- TwichUI_Target_Boss.png
- TwichUI_Target_Elite.png
- TwichUI_Target_Rare.png
- manifest.json
- README.txt

Purpose
Mirrored decorative target-frame portrait borders intended for boss, elite, and rare enemy variants.
These attach to the RIGHT-side target portrait, with the long decorative ridge extending LEFT.

Implementation Notes for AI
- Preserve alpha transparency.
- Do not crop or flatten the PNGs.
- Use Boss as the geometry anchor.
- Use manifest.json for exact canvas dimensions and portrait opening bbox metadata.
- If you need one normalized alignment target for all three variants, use recommended_common_opening_bbox_* from manifest.json.

Variant Summary
- Boss: dark iron, aged gold, crimson cloth, skull crest.
- Elite: dark iron/bronze, horns and tusks, crimson cloth.
- Rare: weathered silver/steel, subtle violet accents.
