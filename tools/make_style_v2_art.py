#!/usr/bin/env python3
"""Builds the settings redesign's material and edge textures (media/style-v2/*.tga) from assets/style-v2-assets.png.

Standard library only, like the other make_*.py tools (PNG reader and resampler: make_map_tool_icons.py; edge builder, its
8-cell layout and TGA writer: make_border_texture.py).

The source is ONE 1254 x 1254 8-bit RGB picture (no alpha) in four quadrants, with a seam near x = 627 / y = 627:

    top left      dark material (espresso leather)      -> dark.tga   256 x 256, tiled
    top right     warm material (chestnut leather)      -> warm.tga   256 x 256, tiled
    bottom left   window frame: a thin bronze rectangle on near-black     -> window-edge.tga
    bottom right  control frame: the same, shorter       -> control-edge.tga

Materials. Neither quadrant is tileable as drawn, so a 512 px square is cut well inside the quadrant (clear of the seam and
the picture's edge) and made seamless by cross-fading its left and top 64 px with the 64 px just beyond its right and
bottom edges (the standard offset blend: the tile's edge then continues into its opposite edge). It is shrunk 2x to 256
(area average) and its lighting gradient is removed (flatten: only the grain and the mean colour stay). --check prints how different opposite edges were before and after, and --preview writes a 3 x 3 tiling
to look for repetition.

Frames. The frames are NOT on transparency: they sit on a near-black ground (luminance about 6). No colour key is used,
because the bronze has dark shades of its own. The ring is found by geometry instead: its bounding box is the pixels brighter than
the ground, each side's depth is measured by walking in from the middle of that side to the first stretch of ground, and
alpha is 255 for the ring (its own dark rim included) and 0 for the outside and the hollow centre. That RGBA ring is
handed to make_border_texture's builder (corners cropped as drawn, each edge the averaged profile of its side) with the
tuning below, and the result is the 8-cell backdrop edge file the client draws with.

Rounded containers. The frame sources are square, so the two rounded treatments are NOT cut from the atlas: round-recess.tga and
round-raised.tga are drawn here from a signed-distance rounded rectangle (see ROUND below; 4 x 4 supersampling, so the corners
are antialiased with real alpha), each a 32 x 32 nine-slice sheet (corners 12 px, a 8 px stretched middle) with its fill, outline
and inner shading baked in. Nothing is stretched from square artwork, the fill follows the corner, and no colour behind it is
assumed. The grain over a raised card is the atlas's warm material, laid by the client in a plus shape clear of the corners.

    python3 tools/make_style_v2_art.py [--src ../assets/style-v2-assets.png] [--out '!!!TwichUI/media/style-v2'] [--check]
                                       [--preview DIR]   (development contact sheets, not shipped)
"""
import argparse
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_border_texture as BT  # noqa: E402
from make_map_tool_icons import read_png, resample  # noqa: E402

SEAM = 627
CUT, BLEND, OUT = 512, 64, 256     # source px cut, the cross-faded strip, the finished tile
MATERIALS = {"dark": (24, 24), "warm": (SEAM + 24, 24)}   # file -> top left of the cut (source px)
GROUND = 12                        # luminance at or under which a pixel is "the ground", not the frame

FRAMES = {   # file -> (quadrant x0, y0, x1, y1, border-builder tuning)
    "window-edge": ((0, SEAM, SEAM, 1254), {"PIECE": 40, "ARM_FREE": 26, "SPAN_SKIP": 100}),
    "control-edge": ((SEAM, SEAM, 1254, 1254), {"PIECE": 32, "ARM_FREE": 22, "SPAN_SKIP": 100}),
}


def lum(px, x, y):
    r, g, b = px[y][x * 4:x * 4 + 3]
    return (r + g + b) // 3


def seamless(px, x0, y0):
    """A CUT x CUT tile from the picture at (x0, y0), its left and top BLEND px cross-faded with the strip beyond the right
    and bottom edges. Returns rows of RGB tuples."""
    n, o = CUT, BLEND
    tile = [[tuple(px[y0 + y][(x0 + x) * 4:(x0 + x) * 4 + 3]) for x in range(n + o)] for y in range(n + o)]

    def mix(a, b, t):
        return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))
    for y in range(n + o):             # horizontally: column x < o becomes src[x + n] -> src[x]
        for x in range(o):
            tile[y][x] = mix(tile[y][x + n], tile[y][x], x / float(o))
    for y in range(o):                 # then vertically
        for x in range(n):
            tile[y][x] = mix(tile[y + n][x], tile[y][x], y / float(o))
    return [row[:n] for row in tile[:n]]


def edge_gap(tile):
    """Mean absolute difference between the left and right columns, and between the top and bottom rows."""
    n = len(tile)
    h = sum(abs(tile[y][0][c] - tile[y][n - 1][c]) for y in range(n) for c in range(3)) / (3.0 * n)
    v = sum(abs(tile[0][x][c] - tile[n - 1][x][c]) for x in range(n) for c in range(3)) / (3.0 * n)
    return h, v


def raw_gap(px, x0, y0):
    n = CUT
    h = sum(abs(px[y0 + y][x0 * 4 + c] - px[y0 + y][(x0 + n - 1) * 4 + c]) for y in range(n) for c in range(3)) / (3.0 * n)
    v = sum(abs(px[y0][(x0 + x) * 4 + c] - px[y0 + n - 1][(x0 + x) * 4 + c]) for x in range(n) for c in range(3)) / (3.0 * n)
    return h, v


def shrink(tile):
    f = len(tile) // OUT
    out = []
    for y in range(OUT):
        row = bytearray(OUT * 4)
        for x in range(OUT):
            for c in range(3):
                row[x * 4 + c] = int(round(sum(tile[y * f + j][x * f + i][c] for j in range(f) for i in range(f)) / float(f * f)))
            row[x * 4 + 3] = 255
        out.append(row)
    return out


def flatten(rows, radius=20):
    """Remove the picture's uneven lighting (what would repeat as visible bands): subtract a wrap-around box blur of the
    tile and add back its mean colour, so only the grain stays. Wrapping keeps the tile seamless."""
    n = len(rows)
    mean = [sum(rows[y][x * 4 + c] for y in range(n) for x in range(n)) / float(n * n) for c in range(3)]
    k = 2 * radius + 1
    out = [bytearray(r) for r in rows]
    for c in range(3):
        tmp = [[0.0] * n for _ in range(n)]
        for y in range(n):                       # horizontal running mean
            line = [rows[y][x * 4 + c] for x in range(n)]
            acc = sum(line[(i - radius) % n] for i in range(k))
            for x in range(n):
                tmp[y][x] = acc / k
                acc += line[(x + radius + 1) % n] - line[(x - radius) % n]
        for x in range(n):                       # vertical running mean
            col = [tmp[y][x] for y in range(n)]
            acc = sum(col[(i - radius) % n] for i in range(k))
            for y in range(n):
                low = acc / k
                acc += col[(y + radius + 1) % n] - col[(y - radius) % n]
                out[y][x * 4 + c] = max(0, min(255, int(round(rows[y][x * 4 + c] - low + mean[c]))))
    return out


def depth(px, start, step, probe):
    """How many pixels in from the side's outer bright edge the frame lasts: walk from the middle of the side inward until
    five ground pixels in a row, then count back to the first pixel brighter than the ground (+1 for the dark rim)."""
    i, first = start, None
    while True:
        v = probe(i)
        if first is None and v > GROUND:
            first = i
        if first is not None and all(probe(i + k * step) <= GROUND for k in range(5)):
            return abs(i - first) + 1 + 1   # the last bright pixel, and the dark rim outside the first
        i += step


def ring(px, quad):
    """The frame of a quadrant as RGBA rows (alpha 255 on the ring, 0 elsewhere), its measurements."""
    qx0, qy0, qx1, qy1 = quad
    xs, ys = [], []
    for y in range(qy0 + 8, qy1 - 8):
        for x in range(qx0 + 8, qx1 - 8):
            if lum(px, x, y) > GROUND:
                xs.append(x); ys.append(y)
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    mx, my = (x0 + x1) // 2, (y0 + y1) // 2
    dl = depth(px, x0, 1, lambda i: lum(px, i, my))
    dr = depth(px, x1 - 1, -1, lambda i: lum(px, i, my))
    dt = depth(px, y0, 1, lambda i: lum(px, mx, i))
    db = depth(px, y1 - 1, -1, lambda i: lum(px, mx, i))
    # one pixel of the dark rim outside the first bright one is kept
    x0 -= 1; y0 -= 1; x1 += 1; y1 += 1
    w, h = x1 - x0, y1 - y0
    rows = []
    for y in range(h):
        row = bytearray(w * 4)
        for x in range(w):
            inside = x >= dl and x < w - dr and y >= dt and y < h - db
            if not inside:
                row[x * 4:x * 4 + 3] = px[y0 + y][(x0 + x) * 4:(x0 + x) * 4 + 3]
                row[x * 4 + 3] = 255
        rows.append(row)
    return w, h, rows, (x0, y0, x1, y1, dl, dr, dt, db)


def write_png_rgba(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) +
                chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def write_tga_rgba(path, rows):
    h, w = len(rows), len(rows[0]) // 4
    with open(path, "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8))
        for row in reversed(rows):
            for x in range(w):
                r, g, b, a = row[x * 4:x * 4 + 4]
                f.write(bytes((b, g, r, a)))


# ---- rounded containers ----------------------------------------------------------------------------------------------------
SHEET, CORNER_PX, RADIUS, LINE = 32, 12, 10.0, 2.0     # texels; the client draws a texel at half a UI unit
SS = 4
ROUND = {   # colours 0..1; alpha where it is not 1
    "recess": {"fill": (0.082, 0.064, 0.050), "line": (0.40, 0.30, 0.19, 0.72), "shadow": (0.02, 0.014, 0.01, 0.70),
               "lip": (0.66, 0.50, 0.31, 0.12), "hi": None, "lo": None},
    "raised": {"fill": (0.150, 0.112, 0.085), "line": (0.36, 0.265, 0.17, 0.55), "shadow": None, "lip": None,
               "hi": (0.66, 0.50, 0.29, 0.30), "lo": (0.02, 0.014, 0.01, 0.50)},
}


def sdf(px, py):
    """Signed distance to the sheet's rounded rectangle (negative inside) and the outward normal there."""
    h = SHEET / 2.0
    dx, dy = px - h, py - h
    qx, qy = abs(dx) - (h - RADIUS), abs(dy) - (h - RADIUS)
    ox, oy = max(qx, 0.0), max(qy, 0.0)
    out = (ox * ox + oy * oy) ** 0.5
    d = out + min(max(qx, qy), 0.0) - RADIUS
    if out > 0:
        nx, ny = (ox / out) * (1 if dx >= 0 else -1), (oy / out) * (1 if dy >= 0 else -1)
    elif qx > qy:
        nx, ny = (1 if dx >= 0 else -1), 0.0
    else:
        nx, ny = 0.0, (1 if dy >= 0 else -1)
    return d, nx, ny


def over(base, c, a):
    return tuple(base[i] * (1 - a) + c[i] * a for i in range(3))


def shade_point(spec, px, py):
    """The finished colour and alpha of one subsample of the sheet, or None outside the shape."""
    d, nx, ny = sdf(px, py)
    if d > 0:
        return None
    col = spec["fill"]
    if spec["shadow"]:       # inner shadow, falling from the top and the left
        w = max(0.0, min(1.0, -ny * 0.85 - nx * 0.35 + 0.15))
        depth = -d - LINE
        if depth > 0:
            col = over(col, spec["shadow"][:3], spec["shadow"][3] * w * max(0.0, 1 - depth / 9.0))
    if spec["lip"] and -3.5 <= d < -LINE:   # a faint lit lip along the bottom
        col = over(col, spec["lip"][:3], spec["lip"][3] * max(0.0, ny))
    if spec["hi"] and -3.5 <= d < -LINE:    # a light along the upper edge, fading round the corners
        col = over(col, spec["hi"][:3], spec["hi"][3] * max(0.0, -ny) ** 1.5)
    if spec["lo"] and -3.5 <= d < -LINE:    # a darker lower edge
        col = over(col, spec["lo"][:3], spec["lo"][3] * max(0.0, ny) ** 1.5)
    if d >= -LINE:                          # the outline
        col = over(col, spec["line"][:3], spec["line"][3])
    return col


def round_sheet(kind):
    spec = ROUND[kind]
    rows = []
    for y in range(SHEET):
        row = bytearray(SHEET * 4)
        for x in range(SHEET):
            acc, n = [0.0, 0.0, 0.0], 0
            for j in range(SS):
                for i in range(SS):
                    c = shade_point(spec, x + (i + 0.5) / SS, y + (j + 0.5) / SS)
                    if c:
                        n += 1
                        for k in range(3):
                            acc[k] += c[k]
            if n:
                row[x * 4:x * 4 + 3] = bytes(int(round(255 * acc[k] / n)) for k in range(3))
            else:
                row[x * 4:x * 4 + 3] = bytes(int(round(255 * spec["fill"][k])) for k in range(3))   # no dark fringe when filtered
            row[x * 4 + 3] = int(round(255 * n / float(SS * SS)))
        rows.append(row)
    return rows


def nine(sheet, w, h, bg):
    """The sheet nine-sliced to w x h texels over a flat background (development preview of what the client draws)."""
    c = CORNER_PX
    mid = SHEET - 2 * c
    out = []
    for y in range(h):
        sy = y if y < c else (SHEET - (h - y) if y >= h - c else c + (y - c) % mid)
        row = bytearray()
        for x in range(w):
            sx = x if x < c else (SHEET - (w - x) if x >= w - c else c + (x - c) % mid)
            r, g, b, a = sheet[sy][sx * 4:sx * 4 + 4]
            a /= 255.0
            row += bytes((int(r * a + bg[0] * (1 - a)), int(g * a + bg[1] * (1 - a)), int(b * a + bg[2] * (1 - a)), 255))
        out.append(row)
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(os.path.dirname(root), "assets", "style-v2-assets.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "style-v2"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview")
    args = ap.parse_args()
    w, h, px, _ = read_png(args.src)
    if (w, h) != (1254, 1254):
        sys.exit("unexpected atlas size %dx%d (expected 1254x1254)" % (w, h))
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)

    for name, (x0, y0) in sorted(MATERIALS.items()):
        tile = seamless(px, x0, y0)
        mean = [sum(tile[y][x][c] for y in range(0, CUT, 4) for x in range(0, CUT, 4)) / float((CUT // 4) ** 2) for c in range(3)]
        print("%s: cut at %d,%d; opposite-edge difference raw %.1f / %.1f -> %.1f / %.1f (of 255); mean colour %d %d %d" % (
            name, x0, y0, raw_gap(px, x0, y0)[0], raw_gap(px, x0, y0)[1], edge_gap(tile)[0], edge_gap(tile)[1], *mean))
        rows = flatten(shrink(tile))
        if not args.check:
            write_tga_rgba(os.path.join(args.out, name + ".tga"), rows)
            print("  wrote %s.tga (%dx%d, 32-bit)" % (name, OUT, OUT))
        if args.preview:
            big = [bytearray(b"".join(bytes(r[x * 4:x * 4 + 4]) for _ in range(3) for x in range(OUT))) for r in rows] * 3
            write_png_rgba(os.path.join(args.preview, name + "-3x3.png"), OUT * 3, OUT * 3, big)

    for kind in sorted(ROUND):
        sheet = round_sheet(kind)
        if not args.check:
            write_tga_rgba(os.path.join(args.out, "round-%s.tga" % kind), sheet)
            print("round-%s.tga: %dx%d nine-slice sheet, corners %d px, radius %g px" % (kind, SHEET, SHEET, CORNER_PX, RADIUS))
        if args.preview:
            big = nine(sheet, 240, 120, (30, 24, 20))
            k = 3
            rows = [bytearray(b"".join(bytes(r[x * 4:x * 4 + 4]) * k for x in range(240))) for r in big for _ in range(k)]
            write_png_rgba(os.path.join(args.preview, "round-%s.png" % kind), 240 * k, 120 * k, rows)

    for name, (quad, tuning) in sorted(FRAMES.items()):
        fw, fh, rows, m = ring(px, quad)
        print("%s: frame %dx%d at %s, depth left %d right %d top %d bottom %d" % (name, fw, fh, m[:4], m[4], m[5], m[6], m[7]))
        if args.preview:
            write_png_rgba(os.path.join(args.preview, name + "-ring.png"), fw, fh, rows)
        work = os.path.join(args.preview or os.path.join(root, "tools"), name + "-ring.tmp.png")
        write_png_rgba(work, fw, fh, rows)
        try:
            BT.__dict__.update(BT.DEFAULTS)
            BT.__dict__.update(tuning)
            canvas, (_, _, box, prof, worst) = BT.build(work)
        finally:
            os.remove(work)
        print("  border box %s; corner changes while joining arms to edges: %s" % (
            box, " ".join("%.1f" % worst[c] for c in (BT.TL, BT.TR, BT.BL, BT.BR))))
        out = os.path.join(args.out, name + ".tga")
        if not args.check:
            BT.write_tga(out, canvas)
            print("  wrote %s.tga (%dx%d, cells of %d)" % (name, BT.WIDTH, BT.HEIGHT, BT.CELL))
            if args.preview:
                BT.preview(os.path.join(args.preview, name + "-preview.png"), out)


if __name__ == "__main__":
    main()
