#!/usr/bin/env python3
"""Prepare the original Home satchel with the established alpha-aware icon pipeline."""
from pathlib import Path
from make_map_tool_icons import read_png, content_box, resample
from make_settings_icons import bleed, write_tga

ROOT = Path(__file__).resolve().parent.parent


def main():
    width, height, pixels, alpha = read_png(str(ROOT / "assets/settings-satchel-source.png"))
    assert alpha, "the source needs real transparency"
    box = content_box(width, height, pixels)
    assert box, "the painting must be visible"
    for side, suffix in ((64, ""), (32, "-small")):
        scale = (side - 6) / max(box[2] - box[0], box[3] - box[1])
        w, h = round((box[2] - box[0]) * scale), round((box[3] - box[1]) * scale)
        body = resample(pixels, box, w, h)
        canvas = [bytearray(side * 4) for _ in range(side)]
        x, y = (side - w) // 2, (side - h) // 2
        for row in range(h):
            canvas[y + row][x * 4:(x + w) * 4] = body[row]
        bleed(canvas, side)
        target = ROOT / ("!!!TwichUI/media/icons/magicInventory" + suffix + ".tga")
        write_tga(str(target), canvas, side)
        print(target.relative_to(ROOT))


if __name__ == "__main__":
    main()
