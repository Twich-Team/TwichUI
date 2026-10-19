"""Render navbuild's tile meshes (.tnm) top-down to a PNG, for checking a bake by eye.

    python3 -I viz.py <tnm dir> <out.png> 31_48 32_48 31_49 32_49 [--scale 0.5] [--path path.txt]

North is up and west is left, as on the world map. Ground is green, water blue, ocean dark blue, polygon edges
dark, and edges that cross to the next tile red. --path draws a polyline of world "x y" lines in yellow.
"""

import argparse
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tnm  # noqa: E402

COLORS = {1: (110, 160, 90), 2: (70, 130, 200), 3: (40, 70, 140)}


def png(path, w, h, rgb):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += rgb[y * w * 3:(y + 1) * w * 3]

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("out")
    ap.add_argument("tiles", nargs="+")
    ap.add_argument("--scale", type=float, default=1.0, help="pixels per yard")
    ap.add_argument("--path")
    ap.add_argument("--box", nargs=4, type=float, metavar=("XMIN", "YMIN", "XMAX", "YMAX"),
                    help="only this world box (x north, y west)")
    a = ap.parse_args()
    meshes = [tnm.load(os.path.join(a.dir, t + ".tnm")) for t in a.tiles]
    xs = [b for m in meshes for b in (m.wxmin, m.wxmax)]
    ys = [b for m in meshes for b in (m.wymin, m.wymax)]
    X1, Y1 = max(xs), max(ys)
    W = int((max(ys) - min(ys)) * a.scale)
    H = int((max(xs) - min(xs)) * a.scale)
    if a.box:
        X1, Y1 = a.box[2], a.box[3]
        W = int((a.box[3] - a.box[1]) * a.scale)
        H = int((a.box[2] - a.box[0]) * a.scale)
    img = bytearray(W * H * 3)

    def px(wx, wy):
        return (Y1 - wy) * a.scale, (X1 - wx) * a.scale

    def put(x, y, col):
        if 0 <= x < W and 0 <= y < H:
            i = (y * W + x) * 3
            img[i:i + 3] = bytes(col)

    def line(p, q, col):
        (x0, y0), (x1, y1) = p, q
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for k in range(n + 1):
            t = k / n
            put(int(x0 + (x1 - x0) * t), int(y0 + (y1 - y0) * t), col)

    for m in meshes:
        for poly in m.polys:
            pts = [px(*m.world(v)[:2]) for v in poly.verts]
            col = COLORS.get(poly.area, (200, 200, 200))
            ymin = max(0, int(min(p[1] for p in pts)))
            ymax = min(H - 1, int(max(p[1] for p in pts)) + 1)
            for yy in range(ymin, ymax + 1):
                yc = yy + 0.5
                xi = []
                for i in range(len(pts)):
                    (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
                    if (y0 <= yc < y1) or (y1 <= yc < y0):
                        xi.append(x0 + (yc - y0) * (x1 - x0) / (y1 - y0))
                xi.sort()
                for k in range(0, len(xi) - 1, 2):
                    for xx in range(max(0, int(xi[k])), min(W, int(xi[k + 1]) + 1)):
                        put(xx, yy, col)
        for poly in m.polys:
            pts = [px(*m.world(v)[:2]) for v in poly.verts]
            for i in range(len(pts)):
                edge = poly.neis[i] & 0x8000 and poly.neis[i] != 0xFFFF
                line(pts[i], pts[(i + 1) % len(pts)], (200, 40, 40) if edge else (40, 50, 40))
    if a.path:
        pts = []
        with open(a.path) as f:
            for ln in f:
                if ln.strip():
                    x, y = (float(v) for v in ln.split()[:2])
                    pts.append(px(x, y))
        for i in range(len(pts) - 1):
            line(pts[i], pts[i + 1], (250, 220, 60))
    png(a.out, W, H, img)
    print("wrote", a.out, W, "x", H)


if __name__ == "__main__":
    main()
