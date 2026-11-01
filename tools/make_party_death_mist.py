#!/usr/bin/env python3
"""Builds the party member fallen card's mist textures (media/partydeath/mist-*.tga). Original artwork, drawn by this
script (seeded, so a rebuild gives the same files); there is no source image and nothing is copied.

Standard library only. Every texture is one flat gray-ivory with a faint cool sage tint (RGB 224,228,216); only the alpha
carries the shape, always feathered to zero well inside the border, so there is no hard edge anywhere.

  mist-fog1..3 128 x 64   a soft, uneven, low cloud with no streaks and no straight edge (the drifting fog); three
                          different noise fields
  mist-wisp1..6 128 x 128 a thin curling strand, soft and broken into pieces along its length, six different curls; none
                          is a mirror of another
  mist-mote    32 x 32    a small soft vapor puff

    python3 tools/make_party_death_mist.py [--out '!!!TwichUI/media/partydeath'] [--check] [--contact-sheet PATH]
"""
import argparse
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_settings_icons as SI  # noqa: E402

TINT = (224, 228, 216)


class Noise:
    """Smooth value noise, tileless, seeded."""
    def __init__(self, seed, size=64):
        rnd = random.Random(seed)
        self.n = size
        self.g = [[rnd.random() for _ in range(size)] for _ in range(size)]

    def at(self, x, y):
        n = self.n
        x0, y0 = math.floor(x), math.floor(y)
        fx, fy = x - x0, y - y0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        x0, y0 = int(x0) % n, int(y0) % n
        x1, y1 = (x0 + 1) % n, (y0 + 1) % n
        g = self.g
        top = g[y0][x0] + (g[y0][x1] - g[y0][x0]) * fx
        bot = g[y1][x0] + (g[y1][x1] - g[y1][x0]) * fx
        return top + (bot - top) * fy

    def fbm(self, x, y, octaves=4):
        total, amp, norm = 0.0, 1.0, 0.0
        for _ in range(octaves):
            total += self.at(x, y) * amp
            norm += amp
            x, y, amp = x * 2.03 + 11.7, y * 2.03 + 5.3, amp * 0.5
        return total / norm


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def window(x, y, w, h, margin):
    """0 at and beyond the border, 1 from `margin` px in: nothing reaches the edge."""
    d = min(x, y, w - 1 - x, h - 1 - y)
    return smooth(d / margin)


def to_canvas(w, h, alpha):
    rows = []
    for y in range(h):
        row = bytearray(w * 4)
        for x in range(w):
            a = max(0.0, min(1.0, alpha[y][x]))
            row[x * 4:x * 4 + 4] = bytes((TINT[0], TINT[1], TINT[2], int(round(a * 255))))
        rows.append(row)
    return rows


def fog(seed):
    w, h = 128, 64
    nz = Noise(seed)
    a = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            u, v = (x - w / 2) / (w / 2), (y - h / 2) / (h / 2)
            fall = smooth(1.0 - math.sqrt(u * u + v * v * 1.3)) ** 1.3
            cloud = nz.fbm(x / 16.0 + seed, y / 16.0, 4)
            a[y][x] = fall * (0.25 + 0.75 * smooth((cloud - 0.25) / 0.5)) * 0.75 * window(x, y, w, h, 12)
    return w, h, a


def bezier(p, t):
    mt = 1 - t
    return (mt ** 3 * p[0][0] + 3 * mt * mt * t * p[1][0] + 3 * mt * t * t * p[2][0] + t ** 3 * p[3][0],
            mt ** 3 * p[0][1] + 3 * mt * mt * t * p[1][1] + 3 * mt * t * t * p[2][1] + t ** 3 * p[3][1])


def wisp(seed, pts, width, tail=0.0):
    """A strand along a cubic curve (points in 0..1 of the canvas, y down). The core is brightest toward the start; the
    tail thins and dissolves into noise. The sample position is warped by noise so the edge is ragged, not a clean tube."""
    w = h = 128
    nz = Noise(seed)
    curve = [bezier([(px * w, py * h) for px, py in pts], i / 79.0) for i in range(80)]
    a = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            wx = x + (nz.fbm(x / 17.0, y / 17.0, 3) - 0.5) * 20
            wy = y + (nz.fbm(x / 17.0 + 40, y / 17.0 + 40, 3) - 0.5) * 20
            best, bt = 1e9, 0.0
            for i, (cx, cy) in enumerate(curve):
                d = (wx - cx) ** 2 + (wy - cy) ** 2
                if d < best:
                    best, bt = d, i / 79.0
            dist = math.sqrt(best)
            taper = math.sin(math.pi * min(1.0, bt * (1.0 + tail * 0.0))) ** 0.8
            wid = max(0.5, width * (0.25 + 0.75 * taper) * (1.0 - 0.35 * bt))
            core = math.exp(-(dist / wid) ** 2 * 0.9)
            grain = (0.25 + 0.75 * nz.fbm(x / 6.0 + 3, y / 6.0 + 9, 3)) * (0.25 + 0.75 * smooth((nz.fbm(x / 10.0 + 70, y / 10.0 + 20, 3) - 0.3) / 0.35))
            fade = (1.0 - bt) ** 0.7 * 0.8 + 0.2      # the far end is the thinner, fainter one
            a[y][x] = core * grain * fade * window(x, y, w, h, 12) * 0.95
    return w, h, a


def mote(seed):
    w = h = 32
    nz = Noise(seed)
    a = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r = math.hypot(x - w / 2 + 0.5, y - h / 2 + 0.5) / (w / 2)
            warp = 0.75 + 0.5 * nz.fbm(x / 6.0, y / 6.0, 3)
            a[y][x] = smooth(1.0 - r * warp) ** 1.6 * 0.9 * window(x, y, w, h, 6)
    return w, h, a


# the strands' control points: rising from the lower part, each curling differently (y is down, so smaller is higher)
TEXTURES = [
    ("mist-fog1", lambda: fog(11)),
    ("mist-fog2", lambda: fog(23)),
    ("mist-fog3", lambda: fog(37)),
    ("mist-wisp1", lambda: wisp(21, [(0.30, 0.92), (0.78, 0.74), (0.18, 0.40), (0.62, 0.08)], 12.0)),
    ("mist-wisp2", lambda: wisp(33, [(0.55, 0.94), (0.52, 0.55), (0.20, 0.30), (0.46, 0.14)], 11.0)),
    ("mist-wisp3", lambda: wisp(47, [(0.14, 0.88), (0.45, 0.62), (0.58, 0.44), (0.90, 0.12)], 12.5)),
    ("mist-wisp4", lambda: wisp(59, [(0.78, 0.90), (0.30, 0.78), (0.72, 0.36), (0.40, 0.10)], 11.5)),
    ("mist-wisp5", lambda: wisp(71, [(0.40, 0.95), (0.70, 0.60), (0.35, 0.50), (0.55, 0.06)], 12.0)),
    ("mist-wisp6", lambda: wisp(83, [(0.66, 0.92), (0.40, 0.66), (0.62, 0.34), (0.30, 0.12)], 11.0)),
    ("mist-mote", lambda: mote(67)),
]


def contact_sheet(path, built):
    bg = (20, 18, 24)
    W = 8 + sum(w + 8 for w, _h, _c in built)
    H = max(h for _w, h, _c in built) + 16
    img = [bytearray(bytes(bg) * W) for _ in range(H)]
    x0 = 8
    for w, h, canvas in built:
        for y in range(h):
            for x in range(w):
                r, g, b, a = canvas[y][x * 4:x * 4 + 4]
                al = a / 255.0
                img[8 + y][(x0 + x) * 3:(x0 + x) * 3 + 3] = bytes(int(round(c * al + k * (1 - al))) for c, k in zip((r, g, b), bg))
        x0 += w + 8
    SI.write_png(path, W, H, img)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "partydeath"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--contact-sheet")
    args = ap.parse_args()
    built = []
    for name, make in TEXTURES:
        w, h, alpha = make()
        canvas = to_canvas(w, h, alpha)
        edge = max(max(row[x * 4 + 3] for x in (0, w - 1)) for row in canvas)
        top = max(canvas[0][x * 4 + 3] for x in range(w))
        print("%-11s %dx%d, peak alpha %d, edge alpha %d" % (name, w, h, max(max(r[3::4]) for r in canvas), max(edge, top)))
        built.append((w, h, canvas))
        if not args.check:
            os.makedirs(args.out, exist_ok=True)
            write_tga_rect(os.path.join(args.out, name + ".tga"), canvas, w, h)
    if args.contact_sheet:
        contact_sheet(args.contact_sheet, built)
    return 0


def write_tga_rect(path, canvas, w, h):
    import struct
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(canvas):
            out = bytearray(w * 4)
            for x in range(w):
                r, g, b, a = row[x * 4:x * 4 + 4]
                out[x * 4:x * 4 + 4] = bytes((b, g, r, a))
            f.write(out)


if __name__ == "__main__":
    sys.exit(main())
