#!/usr/bin/env python3
"""Builds the Camping bar's settings icon (media/camping/settings.tga and settings-small.tga) from assets/camping-source.png,
standard library only like the other make_*.py tools.

The source (2172 x 724, 8-bit RGBA) is one banner on real transparency with four framed tiles: a campfire, a lute, a tent and a
rolled sleeping bag. The tiles are not separate shapes (the leather band joins them), so the campfire tile is cut by its
frame: an octagon (the frame's outer outline, chamfered corners), antialiased by 4 x 4 supersampling, so the band between the
tiles is left out. Only the campfire is used here; the other three tiles stay in the source. The picture is scaled into a
square canvas by its longer side with the margin the other settings icons have (3 px of 64), two sizes: 64 px, and -small, 32 px.

    python3 tools/make_camping_art.py [--src assets/camping-source.png] [--out '!!!TwichUI/media/camping'] [--check]
                                      [--preview scratch.png]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

# The campfire tile's frame, outer outline in source pixels: left, top, right, bottom, and how far each corner is cut.
TILE = (212, 160, 632, 558)
CHAMFER = 40
SIZES = [("", 64, 58), ("-small", 32, 29)]    # suffix, canvas side, content's longer side


def inside(px, py):
    """Whether a point is inside the octagon."""
    x0, y0, x1, y1 = TILE
    c = CHAMFER
    if not (x0 <= px <= x1 and y0 <= py <= y1):
        return False
    return (px - x0) + (py - y0) >= c and (x1 - px) + (py - y0) >= c and (px - x0) + (y1 - py) >= c and (x1 - px) + (y1 - py) >= c


def cut(w, h, pixels):
    x0, y0, x1, y1 = TILE
    W, H = x1 - x0, y1 - y0
    rows = []
    for y in range(H):
        src = pixels[y0 + y]
        row = bytearray(W * 4)
        for x in range(W):
            hits = 0
            for sy in range(4):
                for sx in range(4):
                    if inside(x0 + x + (sx + 0.5) / 4.0, y0 + y + (sy + 0.5) / 4.0):
                        hits += 1
            if hits:
                i = (x0 + x) * 4
                row[x * 4:x * 4 + 3] = src[i:i + 3]
                row[x * 4 + 3] = int(round(src[i + 3] * hits / 16.0))
        rows.append(row)
    return rows, (W, H)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "camping-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "camping"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview")
    args = ap.parse_args()
    w, h, pixels, has_alpha = read_png(args.src)
    if not has_alpha or (w, h) != (2172, 724):
        raise SystemExit("%s: expected a 2172 x 724 image with an alpha channel, got %d x %d" % (args.src, w, h))
    rows, (W, H) = cut(w, h, pixels)
    print("source %dx%d, campfire tile %dx%d" % (w, h, W, H))
    if args.preview:
        SI.write_png(args.preview, W, H, rows)
    c, _area = SI.content_and_area(rows, W, H)
    cw, ch = c[2] - c[0], c[3] - c[1]
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for suffix, side, fill in SIZES:
        canvas, (ow, oh) = SI.place(rows, c, fill / float(max(cw, ch)), side)
        print("settings%s %3d px: content %dx%d" % (suffix, side, ow, oh))
        if not args.check:
            SI.write_tga(os.path.join(args.out, "settings" + suffix + ".tga"), canvas, side)
    return 0


if __name__ == "__main__":
    sys.exit(main())
