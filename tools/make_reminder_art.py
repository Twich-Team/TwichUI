#!/usr/bin/env python3
"""Builds the Reminders artwork gallery (media/reminders/*.tga) from the source paintings in assets/.

Standard library only, like the other make_*.py tools: the PNG reader, content box and premultiplied-alpha box filter
are tools/make_map_tool_icons.py's, the colour bleed and TGA writer tools/make_settings_icons.py's. The sources are
8-bit RGBA PNGs with real transparency (straight alpha: an edge pixel's colour is the painting's own, not a black
matte), so nothing is keyed out.

For each painting: find the visible content (alpha above a small threshold), crop to it, scale it so its longer side
fills the texture less a 1 px clear margin at each end (the aspect ratio is kept), and place it at the top left of a
square canvas with that margin all round. Colour is carried a little way into the clear pixels so the client's filtering
shows no dark fringe. Nothing is recoloured, sharpened or given a glow. The game draws only the used part (texcoords from
the metadata printed here, which reminders/Config.lua's ART table holds), so the empty rest of the canvas is never sampled.

Two sizes, because the game is not relied on to make smaller copies of an addon texture: SIZE for a reminder drawn large
and SMALL for one drawn at or under SMALL_AT units (and for the settings window's thumbnails).

    python3 tools/make_reminder_art.py [--src assets] [--out '!!!TwichUI/media/reminders'] [--check]

--check builds nothing: it prints each source's size and content bounds, and the metadata the build would give.

Adding a picture: put its source in assets/ (a PNG with real transparency), add a line to ART below, run this, and copy
the printed line into reminders/Config.lua's ART table with a label. No other file needs to know about it.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box, resample  # noqa: E402
from make_settings_icons import bleed, write_tga  # noqa: E402

SIZE, SMALL = 256, 64   # texture sides (powers of two); a reminder is drawn at about 32 to 256 UI units

ART = {
    # runtime name   source file
    "shield": "reminder-art-shield-source.png",
    "ammo": "reminder-art-ammo-source.png",
}


def place(pixels, box, side):
    cw, ch = box[2] - box[0], box[3] - box[1]
    scale = (side - 2) / float(max(cw, ch))
    ow, oh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    body = resample(pixels, box, ow, oh)
    canvas = [bytearray(side * 4) for _ in range(side)]
    for y in range(oh):
        canvas[1 + y][4:(1 + ow) * 4] = body[y]
    bleed(canvas, side)
    return canvas, ow + 2, oh + 2   # the used part, with the clear margin on both sides


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "reminders"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for name, src in ART.items():
        w, h, pixels, has_alpha = read_png(os.path.join(args.src, src))
        if not has_alpha:
            raise SystemExit("%s: no alpha channel" % src)
        box = content_box(w, h, pixels)
        if box is None:
            raise SystemExit("%s: no visible content" % src)
        meta = []
        for suffix, side in (("", SIZE), ("-small", SMALL)):
            canvas, used_w, used_h = place(pixels, box, side)
            meta.append((side, used_w, used_h))
            if not args.check:
                write_tga(os.path.join(args.out, name + suffix + ".tga"), canvas, side)
        (s1, w1, h1), (s2, w2, h2) = meta
        print("%-8s source %dx%d content %s (%dx%d)" % (name, w, h, box, box[2] - box[0], box[3] - box[1]))
        print("         %s = { size = %d, width = %d, height = %d, smallSize = %d, smallWidth = %d, smallHeight = %d },"
              % (name, s1, w1, h1, s2, w2, h2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
