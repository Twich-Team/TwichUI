#!/usr/bin/env python3
"""Builds the Data Broker launcher's state icons (media/textures/twichui-broker-*.tga, 64 x 64) from
assets/broker-state-*-source.png (copies of the supplied artwork; the originals are untouched).

Standard library only, reusing make_launcher_icon's helpers. The sources are 1254 x 1254 8-bit RGBA with real alpha, so no
background removal happens: each picture is cut to its content and shrunk to fit 64 x 64 with a 2 px margin, aspect
ratio kept, edges left transparent. No frame, tint or background.

    python3 tools/make_broker_state_icons.py [--src assets] [--out '!!!TwichUI/media/textures'] [--check] [--preview DIR]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box  # noqa: E402
from make_layout_wizard_art import fit, write_png, over  # noqa: E402
from make_training_art import write_tga  # noqa: E402

SIDE, MARGIN = 64, 2
ICONS = ("compass", "leave-alone", "quiet", "location", "multiple")


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "textures"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview")
    args = ap.parse_args()
    for key in ICONS:
        src = "broker-state-%s-source.png" % key
        w, h, rows, has_alpha = read_png(os.path.join(args.src, src))
        if not has_alpha:
            sys.exit("%s has no alpha channel; not guessing a background" % src)
        box = content_box(w, h, rows)
        canvas, size = fit(rows, w, h, box, SIDE, SIDE, MARGIN)
        name = "twichui-broker-" + key
        print("%s: content %s -> %dx%d in %dx%d" % (src, box, size[0], size[1], SIDE, SIDE))
        if args.preview:
            os.makedirs(args.preview, exist_ok=True)
            for bg, color in (("dark", (36, 34, 32)), ("light", (236, 232, 222))):
                write_png(os.path.join(args.preview, "%s-on-%s.png" % (name, bg)), SIDE, SIDE, over(canvas, color))
        if not args.check:
            os.makedirs(args.out, exist_ok=True)
            write_tga(os.path.join(args.out, name + ".tga"), canvas, SIDE, SIDE)
            print("wrote %s.tga" % name)


if __name__ == "__main__":
    main()
