#!/usr/bin/env python3
"""Builds the party member fallen card's three role icons (media/partydeath/role-*.tga) from
assets/party-death-roles-source.png.

Standard library only, like the other make_*.py tools: the PNG reader is tools/make_map_tool_icons.py's; the white-background
removal (edge-connected bright space only, a matte against white on the edge band), the shape-based cleaning, colour bleed
and TGA writer are tools/make_settings_icons.py's.

The source (2137 x 736, 8-bit RGB) is three paintings side by side on an opaque white background, left to right: crossed
swords ("dps"), an open hand holding a glowing mote ("healer") and a shield ("tank"). Pale artwork (blade edges, the hand's
highlights, the mote) is kept: only white connected to the sheet's border goes. The paintings are found by shape, not
position, and the order is checked by each one's proportions.

One size: role-<name>.tga at 32 px, drawn by modules/PartyDeath.lua at 20 UI units beside the player's name.

    python3 tools/make_party_death_roles_art.py [--src assets/party-death-roles-source.png] [--out '!!!TwichUI/media/partydeath']
                                                [--check] [--contact-sheet PATH]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

NAMES = ["dps", "healer", "tank"]     # left to right on the sheet
MIN_AREA = 20000                      # source px: a painting, not a speck
SIDE, FILL = 32, 30                   # canvas side, content's longer side


def cut(path):
    w, h, pixels, has_alpha = read_png(path)
    if has_alpha:
        raise SystemExit("%s: expected an opaque sheet, found an alpha channel" % path)
    cleared = SI.remove_background(w, h, pixels)
    alpha = [[row[x * 4 + 3] for x in range(w)] for row in pixels]
    lab, parts = SI.solid_parts(w, h, alpha)
    big = sorted((p for p in parts if p[1] >= MIN_AREA), key=lambda p: p[2])
    # the healer's hand and mote may be separate parts: merge everything by thirds of the sheet
    groups = [[], [], []]
    for p in parts:
        if p[1] < 400:
            continue
        groups[min(2, int(p[2] * 3 // w))].append(p)
    if len(big) < 3 or not all(groups):
        raise SystemExit("%s: expected three paintings, found %d large parts" % (path, len(big)))
    out = []
    for name, ps in zip(NAMES, groups):
        ids = {p[0] for p in ps}
        box = (min(p[4][0] for p in ps), min(p[4][1] for p in ps), max(p[4][2] for p in ps), max(p[4][3] for p in ps))
        rows, (W, H), _holes = SI.clean_icon(pixels, alpha, lab, ids, box)
        content, area = SI.content_and_area(rows, W, H)
        out.append({"name": name, "box": box, "rows": rows, "content": content, "area": area, "parts": len(ps)})
    return (w, h), cleared, out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "party-death-roles-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "partydeath"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--contact-sheet")
    args = ap.parse_args()
    (w, h), cleared, items = cut(args.src)
    print("source %dx%d, background removed %s" % (w, h, cleared))
    # one shared scale from the content boxes' longer side keeps the apparent size even; the painted-area balance of the
    # other tools then pulls the heaviest (the shield) in a little
    for it in items:
        c = it["content"]
        it["fit"] = FILL / float(max(c[2] - c[0], c[3] - c[1]))
        it["relative"] = it["area"] * it["fit"] ** 2
    median = sorted(it["relative"] for it in items)[1]
    built = []
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for it in items:
        k = 1.0
        if it["relative"] > median:
            k = 1.0 - (1.0 - (median / it["relative"]) ** 0.5) * SI.BALANCE
        canvas, (ow, oh) = SI.place(it["rows"], it["content"], it["fit"] * k, SIDE)
        print("%-6s %d part(s) box %s content %dx%d -> %dx%d" % (it["name"], it["parts"], it["box"],
              it["content"][2] - it["content"][0], it["content"][3] - it["content"][1], ow, oh))
        big, _ = SI.place(it["rows"], it["content"], it["fit"] * k * 2, SIDE * 2)   # for the contact sheet only
        built.append((it["name"], {64: big, 32: canvas}))
        if not args.check:
            SI.write_tga(os.path.join(args.out, "role-" + it["name"] + ".tga"), canvas, SIDE)
    if args.contact_sheet:
        SI.contact_sheet(args.contact_sheet, built)
        print("contact sheet: %s" % args.contact_sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
