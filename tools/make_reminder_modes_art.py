#!/usr/bin/env python3
"""Builds the three display-mode pictures on the Reminders editor's Appearance cards from one rendered sheet.

The source (docs/reminders-revision/artwork-mode-select.png, 8-bit RGBA, real transparency with a faint haze of pixels at
alpha 1..63 around the artwork) holds three drawings side by side: a framed painting with two bars of text beside it, the
framed painting alone, and three bars of text. Standard library only, like the other make_*.py tools; the PNG reader and
premultiplied-alpha filter are tools/make_map_tool_icons.py's and the haze cleaning and colour bleed are
tools/make_settings_icons.py's, so it is cut the way the feature icons are.

  1. The sheet is split into three equal-width columns. In each, the solid artwork (alpha >= CORE) is found as 8-connected
     parts; every part of at least MIN_AREA px belongs to that drawing (the frame and its bars are separate parts).
  2. A drawing keeps its solid pixels and its antialiased edge; the haze is cleared (make_settings_icons.clean_icon).
  3. All three are scaled by ONE factor, chosen so the widest fits the canvas, so the frame is the same size on the first
     two cards. Each is centred on a 128 x 64 canvas, and colour is carried into the clear pixels beside it so the client's
     filtering shows no dark fringe. Nothing is recoloured, sharpened or given a glow.

Files (TGA, 128 x 64; the editor shows them at 96 x 48 on the cards): media/reminders/mode-imageText.tga, mode-image.tga,
mode-text.tga, named for the display modes in reminders/Gallery.lua (UI_MODES).

    python3 tools/make_reminder_modes_art.py [--src docs/reminders-revision/artwork-mode-select.png]
                                             [--out '!!!TwichUI/media/reminders'] [--check]

--check builds nothing: it prints the source, each drawing's bounds and the planned sizes.
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, resample  # noqa: E402
import make_settings_icons as SI  # noqa: E402

MIN_AREA = 2000                       # source px: a frame or a bar, not a speck of the haze
NAMES = ["imageText", "image", "text"]   # left to right on the sheet
CANVAS_W, CANVAS_H = 128, 64
FILL_W, FILL_H = 124, 58              # the widest drawing may use this much of the canvas


def cut(path):
    w, h, pixels, has_alpha = read_png(path)
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % path)
    alpha = [[pixels[y][x * 4 + 3] for x in range(w)] for y in range(h)]
    lab, parts = SI.solid_parts(w, h, alpha)
    columns = [[] for _ in NAMES]
    for p in parts:
        if p[1] >= MIN_AREA:
            columns[min(len(NAMES) - 1, int(p[2] * len(NAMES) / w))].append(p)
    out = []
    for name, found in zip(NAMES, columns):
        if not found:
            raise SystemExit("%s: nothing found for %s" % (path, name))
        box = (min(p[4][0] for p in found), min(p[4][1] for p in found),
               max(p[4][2] for p in found), max(p[4][3] for p in found))
        rows, (W, H), _ = SI.clean_icon(pixels, alpha, lab, {p[0] for p in found}, box)
        content, _ = SI.content_and_area(rows, W, H)
        out.append((name, len(found), rows, content))
    return (w, h), out


def write_tga(path, canvas):
    # type 2 (uncompressed true colour), 32 bpp, descriptor 8 (eight alpha bits, origin bottom-left): the repo's others
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, CANVAS_W, CANVAS_H, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(canvas):
            out = bytearray(CANVAS_W * 4)
            for x in range(CANVAS_W):
                r, g, b, a = row[x * 4:x * 4 + 4]
                out[x * 4:x * 4 + 4] = bytes((b, g, r, a))
            f.write(out)


def place(rows, box, scale):
    cw, ch = box[2] - box[0], box[3] - box[1]
    ow, oh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    body = resample(rows, box, ow, oh)
    canvas = [bytearray(CANVAS_W * 4) for _ in range(CANVAS_H)]
    left, top = (CANVAS_W - ow) // 2, (CANVAS_H - oh) // 2
    for y in range(oh):
        canvas[top + y][left * 4:(left + ow) * 4] = body[y]
    # SI.bleed is square-only; this is the same two-pass nearest-colour spread over the 128 x 64 canvas
    for _ in range(2):
        grown = [bytearray(r) for r in canvas]
        for y in range(CANVAS_H):
            for x in range(CANVAS_W):
                if canvas[y][x * 4 + 3]:
                    continue
                for dx, dy in SI.N8:
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < CANVAS_H and 0 <= xx < CANVAS_W and canvas[yy][xx * 4 + 3]:
                        grown[y][x * 4:x * 4 + 3] = canvas[yy][xx * 4:xx * 4 + 3]
                        break
        canvas = grown
    return canvas, (ow, oh)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "docs", "reminders-revision", "artwork-mode-select.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "reminders"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    (w, h), drawings = cut(args.src)
    print("source %dx%d" % (w, h))
    sizes = [(c[2] - c[0], c[3] - c[1]) for _, _, _, c in drawings]
    scale = min(FILL_W / float(max(s[0] for s in sizes)), FILL_H / float(max(s[1] for s in sizes)))
    print("one scale for all three: %.4f" % scale)
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for (name, parts, rows, content), (cw, ch) in zip(drawings, sizes):
        canvas, (ow, oh) = place(rows, content, scale)
        print("  %-9s %d parts, source content %dx%d -> %dx%d on %dx%d" % (name, parts, cw, ch, ow, oh, CANVAS_W, CANVAS_H))
        if not args.check:
            write_tga(os.path.join(args.out, "mode-" + name + ".tga"), canvas)
    return 0


if __name__ == "__main__":
    sys.exit(main())
