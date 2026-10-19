#!/usr/bin/env python3
"""Draws navigation's textures (TwichUI's own art) into media/textures, standard library only.

    python3 tools/make_nav_textures.py [--out '!!!TwichUI/media/textures'] [--preview DIR]

  nav-arrow.tga        64 x 64  the direction arrow: a white arrowhead pointing up with a dark rim, tinted in game
                                (the rim stays dark under any tint, so the arrow reads on light and dark ground)
  nav-dot.tga          16 x 16  a soft white dot with a dark rim: the trail's dots on both maps, and its end
  maptool-navigate.tga 32 x 32  the world map tool bar's Navigate button, in the other tool icons' bronze and teal

Shapes are polygons and circles drawn at 8x and box-filtered down with premultiplied alpha (no fringe), written as the
uncompressed 32-bit, bottom-left-origin TGA the other media/textures files are. --preview also writes PNGs to look at.
"""
import argparse
import math
import os
import struct
import zlib

SS = 8   # supersampling


def inside_poly(px, py, pts):
    c = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def dist_to_poly_edge(px, py, pts):
    best = 1e9
    for i in range(len(pts)):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % len(pts)]
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(px - (ax + dx * t), py - (ay + dy * t)))
    return best


def render(size, shade):
    """shade(x, y) -> (r, g, b, a) in 0..1 at texture coordinates (top-left origin, pixels). Returns rows of RGBA bytes."""
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            pr = pg = pb = pa = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    r, g, b, a = shade(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
                    pr += r * a
                    pg += g * a
                    pb += b * a
                    pa += a
            n = SS * SS
            a = pa / n
            if a > 0:
                r, g, b = pr / pa, pg / pa, pb / pa
            else:
                r = g = b = 0
            row += bytes((round(r * 255), round(g * 255), round(b * 255), round(a * 255)))
        rows.append(row)
    return rows


def write_tga(path, size, rows):
    out = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8))
    for row in reversed(rows):                      # bottom-left origin
        for x in range(size):
            r, g, b, a = row[4 * x:4 * x + 4]
            out += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(out)


def write_png(path, size, rows, scale=6, bg=(40, 38, 35)):
    raw = bytearray()
    for row in rows:
        line = bytearray()
        for x in range(size):
            r, g, b, a = row[4 * x:4 * x + 4]
            al = a / 255
            px = bytes(int(c * al + k * (1 - al)) for c, k in zip((r, g, b), bg))
            line += px * scale
        for _ in range(scale):
            raw += b"\x00" + line

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size * scale, size * scale, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def arrow_points(size, margin):
    s = size
    return [(s / 2, margin), (s - margin - s * 0.06, s - margin), (s / 2, s * 0.70), (margin + s * 0.06, s - margin)]


def nav_arrow(size=64):
    pts = arrow_points(size, 4)
    rim = 2.6

    def shade(x, y):
        if not inside_poly(x, y, pts):
            return (0, 0, 0, 0)
        d = dist_to_poly_edge(x, y, pts)
        if d < rim:
            return (0.06, 0.05, 0.04, 0.88)
        # a faint lift toward the tip, so a flat tint still has some form
        k = 0.88 + 0.12 * (1 - y / size)
        return (k, k, k, 1)
    return render(size, shade)


def nav_dot(size=16):
    c = size / 2
    r_out, rim = 5.6, 1.2

    def shade(x, y):
        d = math.hypot(x - c, y - c)
        if d > r_out:
            return (0, 0, 0, 0)
        if d > r_out - rim:
            return (0.06, 0.05, 0.04, 0.85)
        return (1, 1, 1, 1)
    return render(size, shade)


BRONZE_HI = (0.86, 0.66, 0.40)
BRONZE = (0.62, 0.42, 0.22)
BRONZE_LO = (0.30, 0.19, 0.09)
EDGE = (0.10, 0.07, 0.04)
TEAL = (0.22, 0.47, 0.48)
TEAL_HI = (0.55, 0.80, 0.78)


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def maptool_navigate(size=32):
    pts = arrow_points(size, 2)
    gem_c, gem_r = (size / 2, size * 0.53), size * 0.13

    def shade(x, y):
        gd = math.hypot(x - gem_c[0], y - gem_c[1])
        if gd <= gem_r:
            if gd > gem_r - 1.0:
                return (*mix(BRONZE_LO, BRONZE_HI, 0.35), 1)          # its setting
            t = max(0.0, 1 - math.hypot(x - (gem_c[0] - 1.2), y - (gem_c[1] - 1.2)) / gem_r)
            return (*mix(TEAL, TEAL_HI, t * 0.8), 1)
        if not inside_poly(x, y, pts):
            return (0, 0, 0, 0)
        d = dist_to_poly_edge(x, y, pts)
        if d < 1.0:
            return (*EDGE, 1)
        # bevel: lit from the top left; the face darkens toward the bottom right and at its inner edge
        light = 0.5 + 0.5 * ((size - x) + (size - y)) / (2 * size) - 0.25
        bevel = min(1.0, (d - 1.0) / 2.5)
        base = mix(BRONZE_LO, BRONZE, bevel)
        return (*mix(base, BRONZE_HI, max(0.0, light) * bevel), 1)
    return render(size, shade)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join("!!!TwichUI", "media", "textures"))
    ap.add_argument("--preview")
    a = ap.parse_args()
    for name, size, fn in (("nav-arrow", 64, nav_arrow), ("nav-dot", 16, nav_dot), ("maptool-navigate", 32, maptool_navigate)):
        rows = fn(size)
        write_tga(os.path.join(a.out, name + ".tga"), size, rows)
        if a.preview:
            write_png(os.path.join(a.preview, name + ".png"), size, rows)
        print("wrote", name, size)


if __name__ == "__main__":
    main()
