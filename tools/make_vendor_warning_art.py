#!/usr/bin/env python3
"""Builds the Sell from Bags "below vendor value" warning icon (media/auction/vendor-warning*.tga) from
assets/vendor-warning-source.png.

Standard library only, like the other make_*.py tools: the PNG reader and resampler are tools/make_map_tool_icons.py's;
the haze cleaning (solid part, kept antialiased edge), colour bleed and TGA writer are tools/make_settings_icons.py's.

The source (1254 x 1254, 8-bit RGBA) is one painting, a worn gold coin with a slate down arrow and an amber warning
triangle, on real transparency. Nothing is keyed out by colour:

  1. The solid artwork is alpha >= CORE (make_settings_icons.CORE). There must be exactly one large part.
  2. It keeps its solid pixels and its antialiased edge within EDGE px, and everything further out, the faint haze of
     the transparency, is cleared (make_settings_icons.clean_icon).
  3. It is scaled into a square canvas with its aspect ratio kept and a small clear margin, centred. Colour is carried
     into the clear pixels beside the artwork so the client's filtering shows no dark fringe. Nothing is recoloured,
     sharpened or given a glow.

Two sizes, because the game is not relied on to make smaller copies of an addon texture: vendor-warning.tga (64 px,
for 27 UI units and over) and vendor-warning-small.tga (32 px, for 26 and under; the page draws it at 22).
auction/Window.lua names them and falls back to the game's own alert icon if the game refuses either.

    python3 tools/make_vendor_warning_art.py [--src assets/vendor-warning-source.png] [--out '!!!TwichUI/media/auction']
                                             [--check]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

NAME = "vendor-warning"
MIN_AREA = 20000                                  # source px: the painting, not a speck
SIZES = [("", 64, 60), ("-small", 32, 30)]        # suffix, canvas side, content's longer side


def cut(path):
    w, h, pixels, has_alpha = read_png(path)
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % path)
    alpha = [[pixels[y][x * 4 + 3] for x in range(w)] for y in range(h)]
    lab, parts = SI.solid_parts(w, h, alpha)
    big = [p for p in parts if p[1] >= MIN_AREA]
    if len(big) != 1:
        raise SystemExit("%s: expected one painting, found %d" % (path, len(big)))
    box = big[0][4]
    rows, (W, H), _holes = SI.clean_icon(pixels, alpha, lab, {big[0][0]}, box)
    content, _area = SI.content_and_area(rows, W, H)
    return (w, h), box, rows, content, sum(1 for p in parts if p[1] < MIN_AREA)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "vendor-warning-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "auction"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    (w, h), box, rows, c, specks = cut(args.src)
    cw, ch = c[2] - c[0], c[3] - c[1]
    print("source %dx%d, painting at %s, %d solid specks cleared with the haze" % (w, h, box, specks))
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for suffix, side, fill in SIZES:
        canvas, (ow, oh) = SI.place(rows, c, fill / float(max(cw, ch)), side)
        print("%3d px: content %dx%d" % (side, ow, oh))
        if not args.check:
            SI.write_tga(os.path.join(args.out, NAME + suffix + ".tga"), canvas, side)
    return 0


if __name__ == "__main__":
    sys.exit(main())
