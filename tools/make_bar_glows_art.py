#!/usr/bin/env python3
"""Builds the Action bar glows settings illustration (media/barglows/settings*.tga) from assets/bar-glows-source.png.

Standard library only, like the other make_*.py tools: the PNG reader and premultiplied-alpha box filter are
tools/make_map_tool_icons.py's; the haze cleaning (solid parts, kept antialiased edge), colour bleed and TGA writer are
tools/make_settings_icons.py's, so it is cut the way the feature icons are.

The source (2172 x 724, 8-bit RGBA) is one painting on transparency: a leather and bronze action bar strip holding
three ability icons, the middle one glowing. It is cut exactly as the other feature illustrations are (solid parts, kept
antialiased edge, colour bleed; nothing keyed out by colour, nothing recoloured). The strip is three times as wide as it
is tall, so its width fills the square canvas.

Two sizes, because the game is not relied on to make smaller copies of an addon texture: settings.tga (64 px, the feature card and Home) and settings-small.tga (32 px, the list row, 26 units and under). Icons.lua
names them (`barGlows`).

    python3 tools/make_bar_glows_art.py [--src assets/bar-glows-source.png] [--out '!!!TwichUI/media/barglows']
                                                [--check]

--check builds nothing: it prints the source, the painting's bounds and the planned sizes.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

MIN_AREA = 20000                     # source px: the painting, not a speck
SIZES = [("", 64, 60), ("-small", 32, 30)]   # suffix, canvas side, content's longer side


def cut(path):
    w, h, pixels, has_alpha = read_png(path)
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % path)
    alpha = [[pixels[y][x * 4 + 3] for x in range(w)] for y in range(h)]
    lab, parts = SI.solid_parts(w, h, alpha)
    big = sorted((p for p in parts if p[1] >= MIN_AREA), key=lambda p: -p[1])
    if len(big) != 1:
        raise SystemExit("%s: expected one painting, found %d large parts" % (path, len(big)))
    part = big[0]
    rows, (W, H), holes = SI.clean_icon(pixels, alpha, lab, {part[0]}, part[4])
    content, area = SI.content_and_area(rows, W, H)
    return (w, h), part[4], rows, content, sum(1 for p in parts if p[1] < MIN_AREA)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "bar-glows-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "barglows"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    (w, h), box, rows, content, specks = cut(args.src)
    cw, ch = content[2] - content[0], content[3] - content[1]
    print("source %dx%d, the painting %s, content %dx%d, %d specks cleared with the haze" % (w, h, box, cw, ch, specks))
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for suffix, side, fill in SIZES:
        scale = fill / float(max(cw, ch))
        canvas, (ow, oh) = SI.place(rows, content, scale, side)
        print("  %3d px: content %dx%d" % (side, ow, oh))
        if not args.check:
            SI.write_tga(os.path.join(args.out, "settings" + suffix + ".tga"), canvas, side)
    return 0


if __name__ == "__main__":
    sys.exit(main())
