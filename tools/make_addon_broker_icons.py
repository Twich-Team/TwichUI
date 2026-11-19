#!/usr/bin/env python3
"""Build five 64px broker TGAs from the supplied PNGs in assets/.

Keep the source artwork unchanged. Crop transparent padding, fit the content with
a 2px margin, and preserve its aspect ratio, colors and alpha using the existing
artwork helpers. No third-party packages are needed.

    python3 tools/make_addon_broker_icons.py [--src assets] [--out DIR] [--preview DIR]
"""
import argparse
from pathlib import Path

from make_map_tool_icons import content_box, read_png
from make_layout_wizard_art import fit, over, write_png
from make_training_art import write_tga

ICONS = ("attune", "chronicle", "dungeon-journal", "restedxp", "bugsack")
SIDE = 64


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", type=Path, default=root / "assets")
    parser.add_argument("--out", type=Path, default=root / "!!!TwichUI/media/textures")
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)
    for name in ICONS:
        source = args.src / (name + "-broker-source.png")
        w, h, rows, alpha = read_png(source)
        if not alpha:
            parser.error("%s has no alpha channel" % source)
        box = content_box(w, h, rows)
        canvas, size = fit(rows, w, h, box, SIDE, SIDE, 2)
        target = args.out / (name + "-broker.tga")
        write_tga(target, canvas, SIDE, SIDE)
        print("%s: %dx%d content -> %dx%d in %s" % (name, box[2] - box[0], box[3] - box[1], size[0], size[1], target.name))
        if args.preview:
            write_png(args.preview / (name + ".png"), SIDE, SIDE, over(canvas, (36, 34, 32)))


if __name__ == "__main__":
    main()
