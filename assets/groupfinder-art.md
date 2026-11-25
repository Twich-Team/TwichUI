# Group Finder dungeon icons

`groupfinder-dungeons-source.png` is original image-generated artwork created for the Group Finder implementation. The left square depicts a volcanic fortress entrance for Blackrock Depths; the right square depicts a purple gothic academy entrance for Scholomance. Neither illustration copies game assets or third-party artwork. The requested composition was two equally sized square illustrations in one transparent sheet, with aged bronze octagonal rims and no text.

The generator returned a 1774 × 887 RGBA PNG. Packaging crops the left and right 887 × 887 cells, then resizes each using Pillow's Lanczos filter to uncompressed 32-bit RGBA TGA files at 128 × 128 and 64 × 64 in `!!!TwichUI/media/groupfinder/`. The originals remain unchanged. Transparent corner pixels and visible doorways were checked in both packaged sizes against an espresso background.

The data adapter maps Scholomance through public map ID 289, verified in `!!!TwichUI/map/Data.lua` for Forever 1.60.1.70450, and exact public English activity names for both featured dungeons. Blackrock Depths is absent from the verified local map inventory, so its map ID is intentionally not inferred. Unmatched or localized activity names without a verified map match use TwichUI's existing painted dungeon entrance icon. No activity IDs are hardcoded.
