#!/usr/bin/env python3
"""Builds the Illustrated training card's artwork (media/training/*.tga) from assets/training-art-source.png.

Standard library only, like tools/make_target_art.py, whose PNG reader and premultiplied-alpha box filter this reuses.

The painting is one 8-bit RGBA image (genuine alpha, no background) holding an open spellbook above a thin horizontal
divider with faded ends. The two never touch: the rows between them (BOOK_ROWS / DIVIDER_ROWS below) are fully
transparent, so they are cut apart and kept in proportion, each to its own texture, and the card places them
separately (the book above the title, the divider beneath it):

    book.tga     128 x 64   the book, scaled uniformly to fit with a 1 px clear margin, centred
    divider.tga  512 x 8    the divider, scaled uniformly to the width, centred; its faded ends are kept

The game draws the whole texture. Colour is carried a little way into the clear pixels beside the painted ones, so no
dark matte bleeds in at the soft edges when the client filters the texture. Nothing is recoloured, sharpened or added.

    python3 tools/make_training_art.py [--src assets] [--out '!!!TwichUI/media/training'] [--check]

--check builds nothing and prints each piece's source bounds and size.
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box, resample  # noqa: E402

SOURCE = "training-art-source.png"

# name: (source rows y0..y1, canvas width, canvas height, clear margin in x and y). The divider is 7 px tall, so it
# keeps no margin above and below: its rows are already clear at the ends and its centre is a line, not a silhouette.
PIECES = {
    "book": ((0, 420), 128, 64, 1, 1),
    "divider": ((420, 793), 512, 8, 1, 0),
}


def build(w, h, pixels, rows, cw, ch, mx, my):
    y0, y1 = rows
    part = pixels[y0:y1]
    box = content_box(w, len(part), part)
    if box is None:
        raise ValueError("no visible content in rows %d-%d" % rows)
    bw, bh = box[2] - box[0], box[3] - box[1]
    scale = min((cw - 2 * mx) / float(bw), (ch - 2 * my) / float(bh))   # uniform: the proportions are the painting's
    ow, oh = max(1, int(round(bw * scale))), max(1, int(round(bh * scale)))
    body = resample(part, box, ow, oh)
    canvas = [bytearray(cw * 4) for _ in range(ch)]
    ox, oy = (cw - ow) // 2, (ch - oh) // 2
    for y in range(oh):
        canvas[oy + y][ox * 4:(ox + ow) * 4] = body[y]
    bleed(canvas, cw, ch)
    return canvas, (box[0], box[1] + y0, box[2], box[3] + y0), (ow, oh)


def bleed(canvas, cw, ch, passes=2):
    """Colour into clear pixels beside painted ones (alpha stays 0)."""
    for _ in range(passes):
        grown = [bytearray(row) for row in canvas]
        for y in range(ch):
            for x in range(cw):
                if canvas[y][x * 4 + 3]:
                    continue
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < ch and 0 <= xx < cw and canvas[yy][xx * 4 + 3]:
                            grown[y][x * 4:x * 4 + 3] = canvas[yy][xx * 4:xx * 4 + 3]
                            break
                    else:
                        continue
                    break
        canvas[:] = grown


def write_tga(path, canvas, cw, ch):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, cw, ch, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(canvas):
            out = bytearray(cw * 4)
            for x in range(cw):
                r, g, b, a = row[x * 4:x * 4 + 4]
                out[x * 4:x * 4 + 4] = bytes((b, g, r, a))
            f.write(out)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "training"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    w, h, pixels, has_alpha = read_png(os.path.join(args.src, SOURCE))
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % SOURCE)
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for name, (rows, cw, ch, mx, my) in PIECES.items():
        canvas, box, (ow, oh) = build(w, h, pixels, rows, cw, ch, mx, my)
        print("%-8s source %dx%d content %s (%dx%d) -> %dx%d in %dx%d" % (
            name, w, h, box, box[2] - box[0], box[3] - box[1], ow, oh, cw, ch))
        if not args.check:
            write_tga(os.path.join(args.out, name + ".tga"), canvas, cw, ch)


if __name__ == "__main__":
    main()
