#!/usr/bin/env python3
"""Cuts the vendor and trainer artwork sheet (assets/npc-art-source.png) into media/npcs/*.tga, standard library only.

The sheet (1536 x 1024, 8-bit RGBA) is 6 x 3 painted icons on real transparency with a faint haze around some of them, the
same kind of sheet tools/make_settings_icons.py cuts, so that tool's shape-based cleaning, optical balance and TGA writer are
used as they are (nothing is keyed out by colour: ivory cloth, parchment and pale feathers keep their pixels). The source is
never changed. Names describe what is painted, in reading order; which kind wears which one is npcs/Kinds.lua (NK.ART).

Two sizes, because the game is not relied on to mipmap an addon texture: NAME.tga at 64 px and NAME-small.tga at 32 px (the
map markers, 18 UI units at 100%, use the small one).

    python3 tools/make_npc_art.py [--src assets/npc-art-source.png] [--out '!!!TwichUI/media/npcs'] [--check] [--contact-sheet PATH]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

COLS, ROWS = 6, 3
NAMES = [
    "reagent-pouch", "arrow-and-cartridge", "hammer", "cloth-bolts", "bread-and-tankard", "sealed-scroll",
    "leather-backpack", "balance-scales", "sword-and-shield", "hammer-and-chisel", "paw", "inscribed-stone",
    "coins", "gavel", "wing", "horse-head", "tabard", "hooded-winged-figure",
]
SIZES = [("", 64, 56), ("-small", 32, 28)]    # suffix, canvas side, content's longer side
BALANCE = 0.5


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "npc-art-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "npcs"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--contact-sheet")
    args = ap.parse_args()

    w, h, pixels, has_alpha = read_png(args.src)
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % args.src)
    alpha = [[row[x * 4 + 3] for x in range(w)] for row in pixels]
    lab, parts = SI.solid_parts(w, h, alpha)
    cells = {}
    for p in parts:
        if p[1] < 400:
            continue   # a speck of haze, not artwork
        col, row = min(COLS - 1, int(p[2] * COLS // w)), min(ROWS - 1, int(p[3] * ROWS // h))
        cells.setdefault(row * COLS + col, []).append(p)

    prepared = []
    for i, name in enumerate(NAMES):
        ps = cells.get(i)
        if not ps:
            raise SystemExit("cell %d (%s): no artwork found" % (i + 1, name))
        ids = {p[0] for p in ps}
        box = (min(p[4][0] for p in ps), min(p[4][1] for p in ps), max(p[4][2] for p in ps), max(p[4][3] for p in ps))
        rows, (W, H), holes = SI.clean_icon(pixels, alpha, lab, ids, box)
        cbox, area = SI.content_and_area(rows, W, H)
        prepared.append((name, rows, cbox, area, max(cbox[2] - cbox[0], cbox[3] - cbox[1]), box, len(ps), holes))
    fills = sorted((a ** 0.5) / lg for _, _, _, a, lg, _, _, _ in prepared)
    median = fills[len(fills) // 2]

    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    built = []
    for name, rows, cbox, area, longest, box, nparts, holes in prepared:
        balance = min(1.0, (median / ((area ** 0.5) / longest)) ** BALANCE)
        by_size, sizes = {}, []
        for suffix, side, fit in SIZES:
            canvas, (ow, oh) = SI.place(rows, cbox, fit / float(longest) * balance, side)
            by_size[side] = canvas
            sizes.append("%dx%d/%d" % (ow, oh, side))
            if not args.check:
                SI.write_tga(os.path.join(args.out, name + suffix + ".tga"), canvas, side)
        built.append((name, by_size))
        print("%-21s parts %d  box %s  balance %.2f  -> %s  holes: %s" % (
            name, nparts, box, balance, " ".join(sizes),
            ", ".join("%d px %s" % (n, kind) for n, _, kind, _ in holes) or "none"))
    if args.contact_sheet:
        SI.contact_sheet(args.contact_sheet, built)


if __name__ == "__main__":
    main()
