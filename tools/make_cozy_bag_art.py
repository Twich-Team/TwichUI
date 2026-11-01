#!/usr/bin/env python3
"""Builds the Cozy Sleeping Bag launcher's artwork (media/guides/cozy-bag.tga and cozy-bag-small.tga) from
assets/cozy-sleeping-bag-source.png, standard library only like the other make_*.py tools.

The source (1536 x 1024, 8-bit RGBA) is one painting on real transparency (about 0.1% of its pixels are partly transparent: the
antialiased edge and a faint haze). Cleaned by shape as the other tools do (make_settings_icons.clean_icon: the solid part, its
kept antialiased edge, colour bleed); nothing is keyed out by colour, so the pale fabric keeps its pixels. The picture is cut to
its content and scaled into a square canvas by its longer side, centred, so the sides keep a clear margin. The artwork is wider
than tall: the launcher shows the band of the canvas the artwork occupies (CozyBagButton.lua, ART_TOP/ART_BOTTOM), so the
button hugs it. Two sizes: 64 px, and -small, 32 px, for launcher sizes of 26 and under.

    python3 tools/make_cozy_bag_art.py [--src assets/cozy-sleeping-bag-source.png] [--out '!!!TwichUI/media/guides'] [--check]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

MIN_AREA = 20000
SIZES = [("", 64, 60), ("-small", 32, 30)]    # suffix, canvas side, content's longer side


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "cozy-sleeping-bag-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "guides"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    w, h, pixels, has_alpha = read_png(args.src)
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % args.src)
    alpha = [[pixels[y][x * 4 + 3] for x in range(w)] for y in range(h)]
    lab, parts = SI.solid_parts(w, h, alpha)
    big = [p for p in parts if p[1] >= MIN_AREA]
    if len(big) != 1:
        raise SystemExit("%s: expected one painting, found %d" % (args.src, len(big)))
    part = big[0]
    print("source %dx%d, %d specks cleared with the haze" % (w, h, len(parts) - 1))
    rows, (W, H), _holes = SI.clean_icon(pixels, alpha, lab, {part[0]}, part[4])
    c, _area = SI.content_and_area(rows, W, H)
    cw, ch = c[2] - c[0], c[3] - c[1]
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for suffix, side, fill in SIZES:
        canvas, (ow, oh) = SI.place(rows, c, fill / float(max(cw, ch)), side)
        print("cozy-bag%s %3d px: content %dx%d, rows %d-%d" % (suffix, side, ow, oh, (side - oh) // 2, (side - oh) // 2 + oh))
        if not args.check:
            SI.write_tga(os.path.join(args.out, "cozy-bag" + suffix + ".tga"), canvas, side)
    return 0


if __name__ == "__main__":
    sys.exit(main())
