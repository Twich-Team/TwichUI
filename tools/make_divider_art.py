#!/usr/bin/env python3
"""Builds the notification cards' Illustrated divider (media/notify/divider.tga) from assets/divider-bar-source.png.

Standard library only, like tools/make_training_art.py, whose TGA writer and clear-edge colour bleed this reuses
(and, through it, tools/make_map_tool_icons.py's PNG reader and premultiplied-alpha resampler).

The painting is one 8-bit RGBA image (real alpha, no background): a thin bronze rule with a diamond at its centre
and a pointed end on each side. It is cropped to its visible content, scaled uniformly to 510 px wide (the aspect
ratio is the painting's) and centred in a 512 x 64 canvas, so the diamond is at the canvas centre both ways.
modules/Arrival.lua draws the whole canvas at its width / 8 high, over a card's rule. Nothing is recoloured,
sharpened or added.

    python3 tools/make_divider_art.py [--src assets] [--out '!!!TwichUI/media/notify'] [--check]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box, resample  # noqa: E402
from make_training_art import bleed, write_tga  # noqa: E402

SOURCE = "divider-bar-source.png"
CW, CH = 512, 64


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "notify"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    w, h, pixels, has_alpha = read_png(os.path.join(args.src, SOURCE))
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % SOURCE)
    box = content_box(w, h, pixels)
    if box is None:
        raise SystemExit("%s: no visible content" % SOURCE)
    bw, bh = box[2] - box[0], box[3] - box[1]
    scale = (CW - 2) / float(bw)
    ow, oh = CW - 2, max(1, int(round(bh * scale)))
    body = resample(pixels, box, ow, oh)
    canvas = [bytearray(CW * 4) for _ in range(CH)]
    ox, oy = (CW - ow) // 2, (CH - oh) // 2
    for y in range(oh):
        canvas[oy + y][ox * 4:(ox + ow) * 4] = body[y]
    bleed(canvas, CW, CH)
    print("divider source %dx%d content %s (%dx%d) -> %dx%d in %dx%d" % (w, h, box, bw, bh, ow, oh, CW, CH))
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
        write_tga(os.path.join(args.out, "divider.tga"), canvas, CW, CH)


if __name__ == "__main__":
    main()
