#!/usr/bin/env python3
"""Builds the navigation frame's "Wayfarer" theme art (media/nav/) from assets/nav-wayfarer-source.png.

Standard library only, like tools/make_map_tool_icons.py (its PNG reader and premultiplied-alpha box filter are reused).

The painting is one wide leather-and-bronze plate (2172 x 724, exterior already transparent). The frame it draws is wider
and shallower than the navigation panel, so it is not stretched whole: it is cut into pieces the panel's nine-slice
(nav/Frame.lua, Shell) draws at any size.

  media/nav/wayfarer.tga          256 x 32, eight 32 x 32 cells left to right:
                                  0 top-left  1 top-right  2 bottom-left  3 bottom-right  (corner pieces, CORNER texels)
                                  4 top edge  5 bottom edge  6 left edge  7 right edge  (rails, RAIL texels deep)
  media/nav/wayfarer-leather.tga  512 x 128, the leather centre, tiled (REPEAT) at its own size

How the painting becomes that, in source pixels (the pieces are SCALE texels per source pixel; the panel draws two
texels per UI unit):

  * The frame is made fully opaque (the painting's alpha is 252/253 across the frame and leather); only the soft outer
    edge, below OPAQUE, keeps its antialiasing, so no matte or white fringe is introduced.
  * Corners are cropped from the painting's own four corners (the light is not the same on all four, so none is mirrored).
  * Each straight rail is the average of that side's profile along the stretch between the corners, so it repeats without
    a seam and keeps the side's own highlight and shade. The last FADE pixels of each corner arm are cross-faded into
    that profile so the corner meets the rail; the plate itself is never touched.
  * Every cell carries its piece with a replicated gutter, so bilinear sampling never reaches a neighbouring piece.
  * The leather is the painting's own interior (inside the inner shadow), mirrored into a 2 x 2 block so the tile wraps
    without a seam, then scaled to 512 x 128.

    python3 tools/make_nav_wayfarer_art.py [--check] [--preview sheet.png]

--check builds nothing: it prints the painting's bounds, each rail's grain and the size of every cross-fade.
--preview writes a development contact sheet (not shipped): the finished files drawn through the panel's nine-slice at
real gameplay sizes (and 2x), over a plain background, so seams and proportions can be judged without the game.
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box, resample  # noqa: E402
from make_border_texture import write_png  # noqa: E402

SRC = "nav-wayfarer-source.png"
OPAQUE = 200      # alpha at or above which a pixel is made fully opaque
SCALE = 0.25      # texels per source pixel (two texels per UI unit: UI units per source pixel = 0.125)
C_SRC = 120       # source pixels per corner piece: the plate (about 105) and a short stretch of both arms
D_SRC = 64        # source pixels of rail depth: the outer rail, the groove, the lip and its shadow
FADE = 14         # source pixels at the end of each corner arm cross-faded into the rail profile
SKIP = 24         # source pixels beyond the corner pieces left out of a rail's profile
CORNER = int(C_SRC * SCALE)    # 30 texels (15 UI units)
RAIL = int(D_SRC * SCALE)      # 16 texels (8 UI units)
ALONG = 8         # texels a rail piece is long (it is stretched along the panel's edge)
CELL, CELLS = 32, 8
LEATHER = (512, 128)
LEATHER_SRC = (1300, 325)      # source pixels of interior that become one quarter of the mirrored tile

TL, TR, BL, BR, TOP, BOTTOM, LEFT, RIGHT = range(8)


def load():
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", SRC)
    w, h, px, _ = read_png(path)
    for row in px:
        for x in range(w):
            if row[x * 4 + 3] >= OPAQUE:
                row[x * 4 + 3] = 255
    return w, h, px


def premul_row(px, coords):
    """Average of a list of (x, y) pixels, premultiplied by alpha. Returns (r, g, b, a) floats (colour not premultiplied)."""
    r = g = b = a = 0.0
    for x, y in coords:
        o = x * 4
        al = px[y][o + 3] / 255.0
        r += px[y][o] * al
        g += px[y][o + 1] * al
        b += px[y][o + 2] * al
        a += al
    n = float(len(coords))
    if a <= 0:
        return (0.0, 0.0, 0.0, 0.0)
    return (r / a, g / a, b / a, a / n * 255.0)


def profile(px, box, side):
    """Per depth step from the side's outer edge, the averaged pixel, and the largest spread along the side."""
    x0, y0, x1, y1 = box
    prof, spread = [], 0.0
    for d in range(D_SRC):
        if side in (TOP, BOTTOM):
            y = y0 + d if side == TOP else y1 - D_SRC + d
            coords = [(x, y) for x in range(x0 + C_SRC + SKIP, x1 - C_SRC - SKIP)]
        else:
            x = x0 + d if side == LEFT else x1 - D_SRC + d
            coords = [(x, y) for y in range(y0 + C_SRC + SKIP, y1 - C_SRC - SKIP)]
        mean = premul_row(px, coords)
        prof.append(mean)
        # spread of the red channel along the side, to say how much grain the average removes
        vals = [px[y][x * 4] for x, y in coords[::7]]
        mu = sum(vals) / len(vals)
        spread = max(spread, (sum((v - mu) ** 2 for v in vals) / len(vals)) ** 0.5)
    return prof, spread


def lerp(p, q, t):
    """Blend pixel p (r, g, b, a bytes) toward q over t, in premultiplied colour."""
    pa, qa = p[3] / 255.0, q[3] / 255.0
    a = pa + (qa - pa) * t
    if a <= 0:
        return (0, 0, 0, 0)
    out = []
    for c in range(3):
        v = (p[c] * pa * (1 - t) + q[c] * qa * t) / a
        out.append(int(round(max(0, min(255, v)))))
    out.append(int(round(a * 255)))
    return tuple(out)


def corner(px, box, which, profs):
    """A C_SRC square from one corner of the painting, its two arms' ends faded into the rails. Returns rows of RGBA."""
    x0, y0, x1, y1 = box
    left = which in (TL, BL)
    top = which in (TL, TR)
    cx = x0 if left else x1 - C_SRC
    cy = y0 if top else y1 - C_SRC
    rows = []
    for j in range(C_SRC):
        row = bytearray(C_SRC * 4)
        for i in range(C_SRC):
            row[i * 4:i * 4 + 4] = px[cy + j][(cx + i) * 4:(cx + i) * 4 + 4]
        rows.append(row)
    ph = profs[TOP if top else BOTTOM][0]
    pv = profs[LEFT if left else RIGHT][0]
    for j in range(C_SRC):
        for i in range(C_SRC):
            o = i * 4
            # distance from the corner along each axis, and the depth across the arm that runs along the other
            ax = i if left else C_SRC - 1 - i          # along the horizontal arm: 0 at the corner's outer side
            ay = j if top else C_SRC - 1 - j
            cur = tuple(rows[j][o:o + 4])
            # horizontal arm (top or bottom rail): depth ay, position ax; its end is at ax = C_SRC
            if ay < D_SRC and ax >= C_SRC - FADE:
                t = (ax - (C_SRC - FADE) + 1) / float(FADE)
                t = t * t * (3 - 2 * t)
                q = tuple(int(round(v)) for v in ph[ay if top else D_SRC - 1 - ay])
                cur = lerp(cur, q, t)
            if ax < D_SRC and ay >= C_SRC - FADE:
                t = (ay - (C_SRC - FADE) + 1) / float(FADE)
                t = t * t * (3 - 2 * t)
                q = pv[ax if left else D_SRC - 1 - ax]
                q = tuple(int(round(v)) for v in q)
                cur = lerp(cur, q, t)
            rows[j][o:o + 4] = bytes(cur)
    return rows


def to_pixels(rows):
    return [bytearray(r) for r in rows]


def piece_rail(prof, vertical):
    """A rail's piece as rows of RGBA: RAIL texels deep, ALONG long. vertical: the depth runs across (left/right)."""
    depth_px = [tuple(int(round(v)) for v in p) for p in prof]
    if not vertical:    # top/bottom: rows are depth
        img = []
        for d in range(D_SRC):
            row = bytearray()
            for _ in range(ALONG * 4):
                row += bytes(depth_px[d])
            img.append(row)
        return resample(img, (0, 0, ALONG * 4, D_SRC), ALONG, RAIL)
    img = []
    for _ in range(ALONG * 4):
        row = bytearray()
        for d in range(D_SRC):
            row += bytes(depth_px[d])
        img.append(row)
    return resample(img, (0, 0, D_SRC, ALONG * 4), RAIL, ALONG)


def place(canvas, cell, rows, ox, oy):
    """Put a piece (rows of RGBA) in a cell at (ox, oy), then replicate its edge pixels outward through the gutter."""
    h, w = len(rows), len(rows[0]) // 4
    for y in range(CELL):
        for x in range(CELL):
            sy = min(max(y - oy, 0), h - 1)
            sx = min(max(x - ox, 0), w - 1)
            canvas[y][(cell * CELL + x) * 4:(cell * CELL + x) * 4 + 4] = rows[sy][sx * 4:sx * 4 + 4]


def atlas():
    w, h, px = load()
    box = content_box(w, h, px)
    profs = {s: profile(px, box, s) for s in (TOP, BOTTOM, LEFT, RIGHT)}
    canvas = [bytearray(CELL * CELLS * 4) for _ in range(CELL)]
    for which in (TL, TR, BL, BR):
        rows = resample(corner(px, box, which, profs), (0, 0, C_SRC, C_SRC), CORNER, CORNER)
        place(canvas, which, rows, (CELL - CORNER) // 2, (CELL - CORNER) // 2)
    place(canvas, TOP, piece_rail(profs[TOP][0], False), (CELL - ALONG) // 2, (CELL - RAIL) // 2)
    place(canvas, BOTTOM, piece_rail(profs[BOTTOM][0], False), (CELL - ALONG) // 2, (CELL - RAIL) // 2)
    place(canvas, LEFT, piece_rail(profs[LEFT][0], True), (CELL - RAIL) // 2, (CELL - ALONG) // 2)
    place(canvas, RIGHT, piece_rail(profs[RIGHT][0], True), (CELL - RAIL) // 2, (CELL - ALONG) // 2)
    # colour carried into the fully transparent texels from their painted neighbours, so filtering can't pull in black
    bleed(canvas)
    return canvas, box, profs


def bleed(canvas):
    h, w = len(canvas), len(canvas[0]) // 4
    for _ in range(3):
        snap = [bytearray(r) for r in canvas]
        for y in range(h):
            for x in range(w):
                if snap[y][x * 4 + 3] == 0:
                    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < h and 0 <= xx < w and snap[yy][xx * 4 + 3] > 0:
                            canvas[y][x * 4:x * 4 + 3] = snap[yy][xx * 4:xx * 4 + 3]
                            break


def leather():
    w, h, px = load()
    x0, y0, x1, y1 = content_box(w, h, px)
    cw, ch = LEATHER_SRC
    cx, cy = (x0 + x1) // 2 - cw // 2, (y0 + y1) // 2 - ch // 2
    quarter = resample(px, (cx, cy, cx + cw, cy + ch), LEATHER[0] // 2, LEATHER[1] // 2)
    out = []
    for r in quarter:
        flipped = bytearray()
        for x in range(len(r) // 4 - 1, -1, -1):
            flipped += r[x * 4:x * 4 + 4]
        out.append(bytearray(r) + flipped)
    out += [bytearray(r) for r in reversed(out)]
    for r in out:
        for x in range(LEATHER[0]):
            r[x * 4 + 3] = 255
    return out


def write_tga(path, rows):
    h, w = len(rows), len(rows[0]) // 4
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(rows):
            for x in range(w):
                r, g, b, a = row[x * 4:x * 4 + 4]
                f.write(bytes((b, g, r, a)))


def read_tga(path):
    data = open(path, "rb").read()
    _, _, typ, _, _, _, _, _, w, h, bpp, desc = struct.unpack("<BBBHHBHHHHBB", data[:18])
    assert typ == 2 and bpp == 32
    body = data[18:]
    rows = []
    for y in range(h):
        row = bytearray(w * 4)
        src = body[y * w * 4:(y + 1) * w * 4]
        for x in range(w):
            b, g, r, a = src[x * 4:x * 4 + 4]
            row[x * 4:x * 4 + 4] = bytes((r, g, b, a))
        rows.append(row)
    if not desc & 0x20:
        rows.reverse()
    return rows


# ---- development preview: nav/Frame.lua's nine-slice, drawn from the finished files ------------------------------

def sample(rows, u, v):
    h, w = len(rows), len(rows[0]) // 4
    x, y = u * w - 0.5, v * h - 0.5
    x0, y0 = int(x // 1), int(y // 1)
    fx, fy = x - x0, y - y0
    out = [0.0] * 4
    for dy, wy in ((0, 1 - fy), (1, fy)):
        for dx, wx in ((0, 1 - fx), (1, fx)):
            xx = min(max(x0 + dx, 0), w - 1)
            yy = min(max(y0 + dy, 0), h - 1)
            o = xx * 4
            al = rows[yy][o + 3] / 255.0
            out[0] += rows[yy][o] * al * wx * wy
            out[1] += rows[yy][o + 1] * al * wx * wy
            out[2] += rows[yy][o + 2] * al * wx * wy
            out[3] += al * wx * wy
    if out[3] > 0:
        return (out[0] / out[3], out[1] / out[3], out[2] / out[3], out[3])
    return (0, 0, 0, 0)


def draw(img, ox, oy, fw, fh, at, lea, k):
    """The panel's nine-slice at fw x fh UI units, k screen pixels per UI unit, over (60, 70, 50)."""
    cu, ru = CORNER / 2.0, RAIL / 2.0       # UI units
    for Y in range(int(fh * k)):
        for X in range(int(fw * k)):
            x, y = (X + 0.5) / k, (Y + 0.5) / k
            px = [60, 70, 50]
            # centre: inset ru - 1 from the edge, tiled at its own size (1 texel = 1 UI unit)
            if ru - 1 <= x < fw - ru + 1 and ru - 1 <= y < fh - ru + 1:
                c = lea[int((y - (ru - 1)) % LEATHER[1])][int((x - (ru - 1)) % LEATHER[0]) * 4:][:4]
                px = [float(c[0]), float(c[1]), float(c[2])]
            layers = []
            inl, inr, int_, inb = x < cu, x >= fw - cu, y < cu, y >= fh - cu
            o = (CELL - CORNER) // 2

            def uv(cell, fx, fy, ow, oh, pw, ph):
                return ((cell * CELL + ow + fx * pw) / float(CELL * CELLS), (oh + fy * ph) / float(CELL))
            ra, rb = (CELL - ALONG) // 2, (CELL - RAIL) // 2
            if (inl or inr) and (int_ or inb):
                cell = (TL if int_ else BL) if inl else (TR if int_ else BR)
                fx = x / cu if inl else (x - (fw - cu)) / cu
                fy = y / cu if int_ else (y - (fh - cu)) / cu
                layers.append(uv(cell, fx, fy, o, o, CORNER, CORNER))
            elif y < ru:
                layers.append(uv(TOP, 0.5, y / ru, ra, rb, ALONG, RAIL))
            elif y >= fh - ru:
                layers.append(uv(BOTTOM, 0.5, (y - (fh - ru)) / ru, ra, rb, ALONG, RAIL))
            elif x < ru:
                layers.append(uv(LEFT, x / ru, 0.5, rb, ra, RAIL, ALONG))
            elif x >= fw - ru:
                layers.append(uv(RIGHT, (x - (fw - ru)) / ru, 0.5, rb, ra, RAIL, ALONG))
            for u, v in layers:
                r, g, b, a = sample(at, u, v)
                px = [px[0] * (1 - a) + r * a, px[1] * (1 - a) + g * a, px[2] * (1 - a) + b * a]
            img[oy + Y][ox + X] = tuple(int(max(0, min(255, round(v)))) for v in px)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview")
    args = ap.parse_args()
    canvas, box, profs = atlas()
    print("content box", box, "corner", CORNER, "texels,", "rail", RAIL, "texels")
    for s, name in ((TOP, "top"), (BOTTOM, "bottom"), (LEFT, "left"), (RIGHT, "right")):
        print("  %-6s rail: grain (red stddev along the side) %.1f" % (name, profs[s][1]))
    if args.check:
        return
    out = os.path.join(root, "!!!TwichUI", "media", "nav")
    os.makedirs(out, exist_ok=True)
    write_tga(os.path.join(out, "wayfarer.tga"), canvas)
    lea = leather()
    write_tga(os.path.join(out, "wayfarer-leather.tga"), lea)
    print("wrote", os.path.join(out, "wayfarer.tga"), "and wayfarer-leather.tga")
    if args.preview:
        at = read_tga(os.path.join(out, "wayfarer.tga"))
        le = read_tga(os.path.join(out, "wayfarer-leather.tga"))
        cases = [(250, 70), (250, 96), (250, 130), (330, 96), (375, 120)]
        pad = 16
        k = 2
        width = pad * 2 + 375 * k
        height = pad + sum(c[1] * k + pad for c in cases)
        img = [[(24, 21, 18)] * width for _ in range(height)]
        y = pad
        for fw, fh in cases:
            draw(img, pad, y, fw, fh, at, le, k)
            y += fh * k + pad
        write_png(args.preview, img)


if __name__ == "__main__":
    main()
