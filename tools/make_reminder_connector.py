#!/usr/bin/env python3
"""Prepare the generated bronze fitting using TwichUI's existing straight-alpha texture pipeline."""
from pathlib import Path

from make_map_tool_icons import read_png, content_box, resample
from make_settings_icons import bleed, write_tga
from make_style_v2_art import write_png_rgba


def main():
    root = Path(__file__).resolve().parent.parent
    source = root / "assets/reminder-connector-source.png"
    width, height, pixels, has_alpha = read_png(source)
    clear = sum(row[x] == 0 for row in pixels for x in range(3, len(row), 4))
    opaque = sum(row[x] == 255 for row in pixels for x in range(3, len(row), 4))
    if not has_alpha or clear == 0 or opaque == 0:
        raise SystemExit("Connector source needs visible artwork and actual transparent pixels.")
    box = content_box(width, height, pixels)
    print("source", width, height, "transparent", clear, "opaque", opaque, "bounds", box)
    runtime = root / "!!!TwichUI/media/reminders"
    inspection = root / "test-output/reminder-connector"
    inspection.mkdir(parents=True, exist_ok=True)
    for side, suffix in ((128, ""), (64, "-small")):
        scale = (side - 4) / max(box[2] - box[0], box[3] - box[1])
        out_w = max(1, round((box[2] - box[0]) * scale))
        out_h = max(1, round((box[3] - box[1]) * scale))
        artwork = resample(pixels, box, out_w, out_h)
        canvas = [bytearray(side * 4) for _ in range(side)]
        x, y = (side - out_w) // 2, (side - out_h) // 2
        for row in range(out_h):
            canvas[y + row][x * 4:(x + out_w) * 4] = artwork[row]
        bleed(canvas, side)
        write_tga(str(runtime / ("connector" + suffix + ".tga")), canvas, side)
        write_png_rgba(str(inspection / ("connector" + suffix + ".png")), side, side, canvas)
        print("runtime", side, "artwork", out_w, out_h)


if __name__ == "__main__":
    main()
