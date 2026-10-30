#!/usr/bin/env python3
"""Builds the Data Broker launcher's icon (media/textures/twichui-broker.tga) from assets/twichui-launcher-source.png.

Standard library only, like the other tools/make_*.py, whose PNG reader, checkerboard remover and premultiplied-alpha box
filter this reuses. The source is 1254 x 1254, 8-bit RGB with NO alpha channel: the "transparent" background is a grey
checkerboard painted into the pixels, taken out by make_layout_wizard_art.remove_checkerboard (a flood from the border through
neutral light-grey pixels only, then an alpha for the soft rim). The picture is cut to its content and shrunk to fit 64 x 64, the
size of the other broker icons (media/textures/*-broker.tga). Nothing is recoloured or sharpened.

    python3 tools/make_launcher_icon.py [--src assets] [--out '!!!TwichUI/media/textures'] [--check] [--preview DIR]

--check builds nothing and prints what the source needed. --preview DIR also writes the icon on a dark and a light background.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box  # noqa: E402
from make_layout_wizard_art import remove_checkerboard, fit, write_png, over  # noqa: E402
from make_training_art import write_tga  # noqa: E402

SOURCE = "twichui-launcher-source.png"
NAME = "twichui-broker"
SIDE = 64
MARGIN = 2


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "textures"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview")
    args = ap.parse_args()
    w, h, px, has_alpha = read_png(os.path.join(args.src, SOURCE))
    print("%s: %dx%d alpha=%s" % (SOURCE, w, h, has_alpha))
    if has_alpha:
        rows = px
    else:
        rows, nbg, rim = remove_checkerboard(w, h, px)
        print("checkerboard flooded from the border: %d background pixels (%.1f%%), %d soft-rim pixels given a partial alpha"
              % (nbg, 100.0 * nbg / (w * h), rim))
    box = content_box(w, h, rows)
    canvas, size = fit(rows, w, h, box, SIDE, SIDE, MARGIN)
    print("content %s -> %dx%d in %dx%d" % (box, size[0], size[1], SIDE, SIDE))
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        for name, color in (("dark", (36, 34, 32)), ("light", (236, 232, 222))):
            write_png(os.path.join(args.preview, "%s-on-%s.png" % (NAME, name)), SIDE, SIDE, over(canvas, color))
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
        write_tga(os.path.join(args.out, NAME + ".tga"), canvas, SIDE, SIDE)
        print("wrote %s.tga" % NAME)


if __name__ == "__main__":
    main()
