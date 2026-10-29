#!/usr/bin/env python3
"""Builds the Reminders condition designer's emblem (media/reminders/designer*.tga) from assets/reminder-designer-source.png.

Standard library only, like the other make_*.py tools: the PNG reader and premultiplied-alpha box filter are
tools/make_map_tool_icons.py's; the haze cleaning (solid parts, kept antialiased edge), colour bleed and TGA writer are
tools/make_settings_icons.py's, so it is cut the way the feature icons are.

The source (1254 x 1254, 8-bit RGBA) is one painting, a bronze ring with a check mark joined by two rods to two smaller
rings, on real transparency, with a faint haze of pixels at alpha 1..63 around it left by however the transparency was
made. Nothing is keyed out by colour:

  1. The solid artwork is alpha >= CORE (make_settings_icons.CORE). Its 8-connected parts are found; the painting is the
     largest, and there must be only one of that size (a re-exported sheet with more than one fails instead of being cut
     wrong).
  2. It keeps its solid pixels and its antialiased edge within EDGE px (colour from the nearest solid pixel); the haze
     further out is cleared (make_settings_icons.clean_icon).
  3. It is scaled into a square canvas with its aspect ratio kept and a clear margin, and colour is carried into the clear
     pixels beside it so the client's filtering shows no dark fringe. Nothing is recoloured, sharpened or given a glow.

Two sizes, because the game is not relied on to make smaller copies of an addon texture: designer.tga (64 px, the Reminders
editor's When section and wherever it is drawn at 27 units or more) and designer-small.tga (32 px, 26 units and under).
Icons.lua names them (`reminderDesigner`); where the files are missing the editor falls back to the `reminderWhen` icon.

    python3 tools/make_reminder_designer_art.py [--src assets/reminder-designer-source.png] [--out '!!!TwichUI/media/reminders']
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
    ap.add_argument("--src", default=os.path.join(root, "assets", "reminder-designer-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "reminders"))
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
            SI.write_tga(os.path.join(args.out, "designer" + suffix + ".tga"), canvas, side)
    return 0


if __name__ == "__main__":
    sys.exit(main())
