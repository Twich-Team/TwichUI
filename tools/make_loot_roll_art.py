#!/usr/bin/env python3
"""Builds the Loot Rolls artwork (media/loot/*.tga) from the two approved mockups, assets/LOOT_ROLLS_CARD_MOCKUP.png and
assets/LOOT_ROLLS_RULE_BUILDER_MOCKUP.png.

Standard library only, like the project's other art tools (it borrows their PNG reader, area-average resampler and TGA writer).

Each icon is one small painted glyph on a dark walnut button face in the mockup. It is cut from a hand-measured box, separated from
the face it sat on (the face colour is measured at the box's corners; a pixel's alpha is how far it is brighter than that face, and the
colour is the glyph's with the face taken out), fitted into a 64 px square (and a 32 px one, "-small") with its own margin, and written
as an RGBA TGA. Nothing is recoloured or redrawn. The panels, bevels, bars and text of a card are drawn by the addon in real frames.

    python3 tools/make_loot_roll_art.py [--src assets] [--out '!!!TwichUI/media/loot'] [--sheet contact-sheet.png]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, resample  # noqa: E402
from make_style_v2_art import write_png_rgba  # noqa: E402
from make_training_art import bleed, write_tga  # noqa: E402

CARD = "LOOT_ROLLS_CARD_MOCKUP.png"
RULES = "LOOT_ROLLS_RULE_BUILDER_MOCKUP.png"

# name: (source file, (x0, y0, x1, y1) in the mockup's pixels, keyed against the face colour or kept as painted)
ICONS = {
    # the three choices and the two controls beside the countdown
    "need": (CARD, (830, 240, 874, 287), "key"),
    "greed": (CARD, (1055, 240, 1107, 285), "key"),
    "pass": (CARD, (1290, 240, 1334, 285), "key"),
    "dice": (CARD, (897, 500, 929, 533), "key"),
    "stop": (CARD, (1183, 500, 1217, 534), "key"),
    # a card's marks
    "upgrade": (CARD, (1275, 120, 1299, 144), "key"),
    "crown": (CARD, (920, 803, 955, 830), "key"),
    "yourroll": (CARD, (810, 714, 846, 746), "key"),
    "gear": (CARD, (908, 426, 930, 446), "key"),
    "check": (CARD, (1311, 615, 1335, 636), "key"),
    # the rule builder's pictures (the list's and the conditions'), cut from the second mockup
    "scroll": (RULES, (273, 321, 334, 377), "key"),
    "scroll-no": (RULES, (273, 380, 330, 442), "key"),
    "crystals": (RULES, (276, 455, 330, 512), "key"),
    "gem": (RULES, (620, 330, 650, 362), "key"),
    "chest": (RULES, (617, 374, 652, 412), "key"),
    "door": (RULES, (617, 417, 653, 453), "key"),
    "hourglass": (RULES, (623, 692, 653, 724), "key"),
    "horn": (RULES, (618, 767, 654, 797), "key"),
    "autocheck": (CARD, (1301, 388, 1323, 409), "key"),
}
OUT = 64
SMALL = 32
FIT = 0.88       # of the square the glyph's longer side fills


def corner_face(w, h, px, box):
    x0, y0, x1, y1 = box
    samples = []
    for (cx, cy) in ((x0, y0), (x1 - 2, y0), (x0, y1 - 2), (x1 - 2, y1 - 2)):
        for dy in (0, 1):
            for dx in (0, 1):
                row = px[cy + dy]
                samples.append((row[(cx + dx) * 4], row[(cx + dx) * 4 + 1], row[(cx + dx) * 4 + 2]))
    samples.sort(key=lambda s: sum(s))
    mid = samples[len(samples) // 2]      # the median keeps a stray bright corner from becoming the face
    return mid


def key_icon(w, h, px, box):
    """Rows of RGBA for the box with the face taken out."""
    x0, y0, x1, y1 = box
    face = corner_face(w, h, px, box)
    fmax = max(face)
    rows = []
    for y in range(y0, y1):
        row = bytearray()
        for x in range(x0, x1):
            r, g, b = px[y][x * 4], px[y][x * 4 + 1], px[y][x * 4 + 2]
            lift = max(r, g, b) - fmax
            a = max(0.0, min(1.0, (lift - 6) / 46.0))
            if a <= 0:
                row += b"\x00\x00\x00\x00"
                continue
            fr = (r - (1 - a) * face[0]) / a
            fg = (g - (1 - a) * face[1]) / a
            fb = (b - (1 - a) * face[2]) / a
            row += bytes((max(0, min(255, int(fr))), max(0, min(255, int(fg))), max(0, min(255, int(fb))), int(a * 255)))
        rows.append(row)
    return rows


def fit(rows, size):
    """The rows' content (alpha over a little) fitted in a size x size canvas, centred."""
    bh, bw = len(rows), len(rows[0]) // 4
    # content bounds
    xs0, ys0, xs1, ys1 = bw, bh, -1, -1
    for y in range(bh):
        for x in range(bw):
            if rows[y][x * 4 + 3] > 24:
                xs0, xs1 = min(xs0, x), max(xs1, x)
                ys0, ys1 = min(ys0, y), max(ys1, y)
    if xs1 < 0:
        return [bytearray(size * 4) for _ in range(size)]
    cw, ch = xs1 - xs0 + 1, ys1 - ys0 + 1
    scale = size * FIT / float(max(cw, ch))
    ow, oh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    cut = resample(rows, (xs0, ys0, xs1 + 1, ys1 + 1), ow, oh)
    canvas = [bytearray(size * 4) for _ in range(size)]
    ox, oy = (size - ow) // 2, (size - oh) // 2
    for y in range(oh):
        canvas[oy + y][ox * 4:(ox + ow) * 4] = cut[y]
    return canvas


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "loot"))
    ap.add_argument("--sheet", default=None, help="also write a contact sheet PNG of every icon (for review)")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    pngs = {}
    built = {}
    for name, (src, box, mode) in ICONS.items():
        if src not in pngs:
            pngs[src] = read_png(os.path.join(args.src, src))
        w, h, px, _ = pngs[src]
        rows = key_icon(w, h, px, box)
        for size, suffix in ((OUT, ""), (SMALL, "-small")):
            canvas = fit(rows, size)
            bleed(canvas, size, size)
            write_tga(os.path.join(args.out, name + suffix + ".tga"), canvas, size, size)
            if size == OUT:
                built[name] = canvas
    if args.sheet:
        names = list(built)
        cols = 6
        rowsn = (len(names) + cols - 1) // cols
        sheet = []
        for ry in range(rowsn * OUT):
            sheet.append(bytearray(b"\x2a\x20\x18\xff" * (cols * OUT)))
        for i, name in enumerate(names):
            gx, gy = (i % cols) * OUT, (i // cols) * OUT
            canvas = built[name]
            for y in range(OUT):
                for x in range(OUT):
                    r, g, b, a = canvas[y][x * 4:x * 4 + 4]
                    base = sheet[gy + y][(gx + x) * 4:(gx + x) * 4 + 3]
                    al = a / 255.0
                    sheet[gy + y][(gx + x) * 4:(gx + x) * 4 + 3] = bytes(int(base[k] * (1 - al) + (r, g, b)[k] * al) for k in range(3))
        # enlarge x3 for viewing
        big = []
        for row in sheet:
            wide = bytearray()
            for x in range(cols * OUT):
                wide += row[x * 4:x * 4 + 4] * 3
            for _ in range(3):
                big.append(wide)
        write_png_rgba(args.sheet, cols * OUT * 3, rowsn * OUT * 3, big)
    print("wrote %d icons to %s" % (len(ICONS), args.out))


if __name__ == "__main__":
    main()
