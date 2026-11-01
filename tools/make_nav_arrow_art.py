#!/usr/bin/env python3
"""Builds the navigation arrow's artwork (media/textures/nav-arrow-bronze.tga, 128 x 128, pointing up) from
assets/nav-arrow-source.png, standard library only like the other make_*.py tools.

The source (1254 x 1254, 8-bit RGBA) is one arrowhead on transparency. Cleaned by shape as the other tools do
(make_settings_icons.clean_icon), cut to its content and scaled into a square canvas by its longer side, centred, with a
margin of about 3 %. The RestedXP skin's arrow is a different file (arrow-bronze.tga) and is not touched.

    python3 tools/make_nav_arrow_art.py [--src assets/nav-arrow-source.png] [--out '!!!TwichUI/media/textures'] [--check]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

MIN_AREA = 20000
SIDE, FILL = 128, 120    # canvas side, content's longer side


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "nav-arrow-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "textures"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    w, h, pixels, has_alpha = read_png(args.src)
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % args.src)
    alpha = [[pixels[y][x * 4 + 3] for x in range(w)] for y in range(h)]
    lab, parts = SI.solid_parts(w, h, alpha)
    big = [p for p in parts if p[1] >= MIN_AREA]
    if len(big) != 1:
        raise SystemExit("%s: expected one arrowhead, found %d" % (args.src, len(big)))
    part = big[0]
    print("source %dx%d, %d specks cleared with the haze" % (w, h, len(parts) - 1))
    rows, (W, H), _holes = SI.clean_icon(pixels, alpha, lab, {part[0]}, part[4])
    c, _area = SI.content_and_area(rows, W, H)
    cw, ch = c[2] - c[0], c[3] - c[1]
    canvas, (ow, oh) = SI.place(rows, c, FILL / float(max(cw, ch)), SIDE)
    print("nav-arrow-bronze %d px: content %dx%d" % (SIDE, ow, oh))
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
        SI.write_tga(os.path.join(args.out, "nav-arrow-bronze.tga"), canvas, SIDE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
