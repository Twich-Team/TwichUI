#!/usr/bin/env python3
"""Builds Healer Watch's three pictures (media/healerwatch/*.tga) from assets/healer-watch-source.png.

Standard library only, like the other make_*.py tools: the PNG reader and premultiplied-alpha box filter are
tools/make_map_tool_icons.py's; the haze cleaning (solid parts, kept antialiased edge), colour bleed and TGA writer are
tools/make_settings_icons.py's.

The source (2172 x 724, 8-bit RGBA) is three paintings side by side, left to right: a smoked-glass mana flask
("vessel"), a worn ceramic cup ("cup") and an ivory speech bubble with a blue droplet ("speech"). It has real
transparency: the paintings are alpha 248..255 throughout (the glass is painted, not see-through, so there is no
deliberate translucency to keep), and around them is a faint haze of white, red and black pixels at alpha 1..5 left by
however the transparency was made. Nothing is keyed out by colour:

  1. The solid artwork is alpha >= CORE (make_settings_icons.CORE). Its 8-connected parts are found over the sheet;
     there must be exactly three large ones. They are ordered by their centre from left to right, and the order is
     checked against NAMES by shape (the vessel is taller than wide, the other two wider than tall), so a re-exported
     sheet in another order fails instead of being cut wrong. No fixed coordinates are used.
  2. Each painting keeps its solid pixels and its antialiased edge within EDGE px (colour from the nearest solid pixel),
     and everything further out, the haze, is cleared (make_settings_icons.clean_icon).
  3. Each is scaled into a square canvas with its aspect ratio kept and a clear margin, centred, and optically balanced
     the way the settings icons are: one whose painted area is heavier than the median of the three is shrunk part of
     the way towards it, so the bubble doesn't look bigger than the flask. Colour is carried into the clear pixels
     beside the artwork so the client's filtering shows no dark fringe. Nothing is recoloured, sharpened or given a glow.

Three sizes, because the game is not relied on to make smaller copies of an addon texture: <name>-large.tga (256 px,
for artwork drawn over 64 UI units), <name>.tga (64 px, 33..64 units, also the settings window's icon) and
<name>-small.tga (32 px, 32 units and under: the small drinking and chat indicators). healer/Config.lua's ART table and
Icons.lua name them.

    python3 tools/make_healer_watch_art.py [--src assets/healer-watch-source.png] [--out '!!!TwichUI/media/healerwatch']
                                           [--check] [--contact-sheet PATH]

--check builds nothing: it prints the source, each painting's bounds and the planned sizes. --contact-sheet writes a
PNG of every size on a dark and a light surface, for inspection; it is not used in game.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, resample  # noqa: E402
import make_settings_icons as SI  # noqa: E402

NAMES = ["vessel", "cup", "speech"]          # left to right on the sheet
TALL = {"vessel": True, "cup": False, "speech": False}
MIN_AREA = 20000                             # source px: a painting, not a speck
SIZES = [("-large", 256, 240), ("", 64, 60), ("-small", 32, 30)]   # suffix, canvas side, content's longer side
BALANCE = SI.BALANCE


def cut(path):
    w, h, pixels, has_alpha = read_png(path)
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % path)
    alpha = [[pixels[y][x * 4 + 3] for x in range(w)] for y in range(h)]
    lab, parts = SI.solid_parts(w, h, alpha)
    big = sorted((p for p in parts if p[1] >= MIN_AREA), key=lambda p: p[2])
    if len(big) != len(NAMES):
        raise SystemExit("%s: expected %d paintings, found %d" % (path, len(NAMES), len(big)))
    small = sum(1 for p in parts if p[1] < MIN_AREA)
    out = []
    for name, part in zip(NAMES, big):
        box = part[4]
        bw, bh = box[2] - box[0], box[3] - box[1]
        if (bh > bw) != TALL[name]:
            raise SystemExit("%s: the painting at x %d..%d doesn't have the %s's shape; is the sheet in another order?"
                             % (path, box[0], box[2], name))
        # specks of solid haze inside a painting's box belong to it only if they touch its edge band (clean_icon keeps
        # only pixels within EDGE of the listed parts), so only the painting's own label is passed
        rows, (W, H), holes = SI.clean_icon(pixels, alpha, lab, {part[0]}, box)
        content, area = SI.content_and_area(rows, W, H)
        out.append({"name": name, "box": box, "rows": rows, "content": content, "area": area, "holes": holes})
    return (w, h), out, small


def plan(items):
    """The scale for each painting at a content side of 1 (box fit, then the optical balance)."""
    fits = []
    for it in items:
        cw, ch = it["content"][2] - it["content"][0], it["content"][3] - it["content"][1]
        fit = 1.0 / max(cw, ch)
        fits.append(fit)
        it["relative"] = it["area"] * fit * fit
    median = sorted(it["relative"] for it in items)[len(items) // 2]
    for it, fit in zip(items, fits):
        k = 1.0
        if it["relative"] > median:
            k = 1.0 - (1.0 - (median / it["relative"]) ** 0.5) * BALANCE
        it["scale"] = fit * k


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "healer-watch-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "healerwatch"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--contact-sheet")
    args = ap.parse_args()
    (w, h), items, specks = cut(args.src)
    plan(items)
    print("source %dx%d, %d paintings, %d solid specks cleared with the haze" % (w, h, len(items), specks))
    built = []
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for it in items:
        b, c = it["box"], it["content"]
        print("%-7s box %s content %dx%d relative area %.3f scale x%.3f" % (it["name"], b, c[2] - c[0], c[3] - c[1],
                                                                           it["relative"], it["scale"] * max(c[2] - c[0], c[3] - c[1])))
        by_size = {}
        for suffix, side, fill in SIZES:
            canvas, (ow, oh) = SI.place(it["rows"], c, it["scale"] * fill, side)
            by_size[side] = canvas
            print("        %3d px: content %dx%d" % (side, ow, oh))
            if not args.check:
                SI.write_tga(os.path.join(args.out, it["name"] + suffix + ".tga"), canvas, side)
        built.append((it["name"], {64: by_size[64], 32: by_size[32]}))
    if args.contact_sheet:
        SI.contact_sheet(args.contact_sheet, built)
        print("contact sheet: %s" % args.contact_sheet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
