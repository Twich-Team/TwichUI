#!/usr/bin/env python3
"""Builds TwichUI's shared-media borders (media/borders/<style>.tga) from the paintings in assets/ (STYLES below:
"TwichUI - Aged Bronze", "Rounded Bronze", "Gilt Bronze" and "Dark Umber").

Standard library only, like tools/make_target_art.py, whose PNG reader and premultiplied-alpha box filter this reuses.

The painting is a whole rectangle; the client wants an edge file: Blizzard_SharedXML/Backdrop.lua (textureUVs) draws
eight pieces from one image, in eight equal cells left to right:

    0 left edge   1 right edge   2 top edge   3 bottom edge   4 top-left   5 top-right   6 bottom-left   7 bottom-right

Each cell holds its piece in the middle 14/16 (a 1/16 gutter on every side, so bilinear sampling never reaches a
neighbouring piece). The edge pieces are repeated along their length and wrap over the cell's whole height, so they must
be uniform along the line. The top and bottom edges are stored turned: the texture's x axis runs from the frame's
outside to its inside (top) or from its inside to its outside (bottom), as the piece appears on screen, because the
client rotates them. Left, right and the corners are stored as they appear.

How the painting becomes that, in source pixels (PIECE = 64 per piece, then scaled to CONTENT = 28 in a CELL = 32):

  * Corners are cropped from the painting's own four corners (the lighting is not the same on every side, so none is
    mirrored). Each is PIECE square, the corner joint and the first stretch of both straight arms.
  * Each straight edge is the average of that side's profile along the stretch between the corners, measured with
    premultiplied alpha. The painting's edges carry only a little grain, so the averaged strip repeats without a seam
    and keeps the side's own highlight and shade. Nothing is invented: every value comes from the painting.
  * The last stretch of each corner arm is cross-faded into that average profile, so the corner meets the edge
    exactly; the joint itself (ARM_FREE source pixels from the corner) is never touched.
  * Colour is carried into fully transparent pixels from the nearest painted ones, so no dark or white matte bleeds
    in at the border's soft edges when the client filters the texture. The centre of the painting is transparent and
    stays so; nothing opaque is carried over.

    python3 tools/make_border_texture.py [--style aged-bronze] [--check] [--preview sheet.png]

Every style is built unless --style names one. A new border is a new painting (8-bit RGBA, transparent centre, an even
band round the edge) and one STYLES row here plus its name in modules/Media.lua.

--check builds nothing and prints the painting's bounds, side profiles and the size of each adjustment.
--preview writes a development contact sheet (not shipped) that draws the finished TGA through the same nine-slice
rules as Backdrop.lua at several sizes, so seams and corner proportions can be judged without the game.
"""
import argparse
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box, resample  # noqa: E402

PIECE = 64        # source pixels per piece: the corner joint (about 48) plus a straight stretch beyond it
CELL = 32         # one cell of the texture (a power of two); 8 cells wide
CONTENT = 28      # the piece's pixels inside the cell: 14/16 of it, the client's texture coordinates
GUTTER = (CELL - CONTENT) // 2
WIDTH, HEIGHT = CELL * 8, CELL
ARM_FREE = 48     # source pixels from a corner that are left exactly as painted (the joint and its bevel end near 48)
SPAN_SKIP = 160   # source pixels at each end of a side left out of its profile (the corners)

STYLES = {   # style -> source painting in assets/; the runtime file is media/borders/<style>.tga
    "aged-bronze": "border-aged-bronze-source.png",
    "rounded-bronze": "border-rounded-bronze-source.png",
    "gilt-bronze": "border-gilt-bronze-source.png",
    "dark-umber": "border-umber-source.png",
}

LEFT, RIGHT, TOP, BOTTOM, TL, TR, BL, BR = range(8)


def build_profiles(px, box):
    """Per side, PIECE premultiplied RGBA tuples by depth from the side's outer edge, averaged along the side."""
    x0, y0, x1, y1 = box
    prof = {}
    for side in (LEFT, RIGHT, TOP, BOTTOM):
        horizontal = side in (TOP, BOTTOM)
        lo, hi = (x0, x1) if horizontal else (y0, y1)
        acc = [[0.0, 0.0, 0.0, 0.0] for _ in range(PIECE)]
        n = 0
        for pos in range(lo + SPAN_SKIP, hi - SPAN_SKIP):
            n += 1
            for d in range(PIECE):
                if side == LEFT:
                    o = px[pos][(x0 + d) * 4:(x0 + d) * 4 + 4]
                elif side == RIGHT:
                    o = px[pos][(x1 - 1 - d) * 4:(x1 - 1 - d) * 4 + 4]
                elif side == TOP:
                    o = px[y0 + d][pos * 4:pos * 4 + 4]
                else:
                    o = px[y1 - 1 - d][pos * 4:pos * 4 + 4]
                a = o[3] / 255.0
                acc[d][0] += o[0] * a
                acc[d][1] += o[1] * a
                acc[d][2] += o[2] * a
                acc[d][3] += a
        prof[side] = [(r / n, g / n, b / n, a / n) for r, g, b, a in acc]  # premultiplied, alpha 0..1
    return prof


def blank():
    return [bytearray(PIECE * 4) for _ in range(PIECE)]


def put(rows, x, y, pm):
    r, g, b, a = pm
    o = x * 4
    if a > 1e-6:
        rows[y][o], rows[y][o + 1], rows[y][o + 2] = (min(255, int(round(c / a))) for c in (r, g, b))
    rows[y][o + 3] = min(255, int(round(a * 255)))


def edge_piece(side, prof):
    """An edge piece at source size. Left/right: x is depth (right is turned to read as drawn); top/bottom: x is the
    depth too, from the frame's outside (top) or inside (bottom), the same line on every row."""
    rows = blank()
    for x in range(PIECE):
        d = x if side in (LEFT, TOP) else PIECE - 1 - x
        for y in range(PIECE):
            put(rows, x, y, prof[side][d])
    return rows


def crop(px, x, y):
    return [bytearray(px[y + j][x * 4:(x + PIECE) * 4]) for j in range(PIECE)]


def fade_arm(rows, prof, side, positions, along_x, depth_of, ramp_of):
    """Cross-fade the pixels of one corner arm toward that side's average profile.
    positions: the coordinate range (along the arm) to treat; ramp_of(c): 0..1 weight of the profile at that coordinate."""
    worst = 0
    for c in positions:
        t = ramp_of(c)
        if t <= 0:
            continue
        for k in range(PIECE):                      # k runs across the arm
            x, y = (c, k) if along_x else (k, c)
            d = depth_of(k)
            pr, pg, pb, pa = prof[side][d]
            o = x * 4
            a0 = rows[y][o + 3] / 255.0
            src = (rows[y][o] * a0, rows[y][o + 1] * a0, rows[y][o + 2] * a0, a0)
            mix = tuple(s * (1 - t) + p * t for s, p in zip(src, (pr, pg, pb, pa)))
            worst = max(worst, abs(mix[3] - a0) * 255, *(abs(m - s) for m, s in zip(mix[:3], src[:3])))
            put(rows, x, y, mix)
    return worst


def corner_piece(px, box, which, prof):
    x0, y0, x1, y1 = box
    cx = x0 if which in (TL, BL) else x1 - PIECE
    cy = y0 if which in (TL, TR) else y1 - PIECE
    rows = crop(px, cx, cy)
    right = which in (TR, BR)
    low = which in (BL, BR)
    ramp = lambda dist: min(1.0, max(0.0, (dist - ARM_FREE) / float(PIECE - 1 - ARM_FREE)))
    # the horizontal arm (top or bottom edge) runs away from the corner along x; the vertical one along y
    h_side, v_side = (BOTTOM if low else TOP), (RIGHT if right else LEFT)
    h_depth = (lambda k: PIECE - 1 - k) if low else (lambda k: k)
    v_depth = (lambda k: PIECE - 1 - k) if right else (lambda k: k)
    h_ramp = (lambda c: ramp(PIECE - 1 - c)) if right else (lambda c: ramp(c))
    v_ramp = (lambda c: ramp(PIECE - 1 - c)) if low else (lambda c: ramp(c))
    # the rows of the horizontal arm and the columns of the vertical one cross only in the (empty) inside corner
    w1 = fade_arm(rows, prof, h_side, range(PIECE), True, lambda k: h_depth(k), h_ramp)
    w2 = fade_arm(rows, prof, v_side, range(PIECE), False, lambda k: v_depth(k), v_ramp)
    return rows, max(w1, w2)


def place(canvas, cell, rows, uniform=False):
    """Scale a PIECE square to CONTENT and set it in the middle of the cell, then replicate its border pixels into the
    gutter (clamp), which for the uniform edge pieces is also the continuation the client's repeat wraps into.
    uniform: an edge piece, every row the same line exactly (the filter's rounding must not differ between rows)."""
    small = resample(rows, (0, 0, PIECE, PIECE), CONTENT, CONTENT)
    if uniform:
        small = [small[CONTENT // 2]] * CONTENT
    for y in range(CELL):
        sy = min(CONTENT - 1, max(0, y - GUTTER))
        for x in range(CELL):
            sx = min(CONTENT - 1, max(0, x - GUTTER))
            canvas[y][(cell * CELL + x) * 4:(cell * CELL + x) * 4 + 4] = small[sy][sx * 4:sx * 4 + 4]


def bleed_colour(canvas):
    """Give fully transparent pixels the colour of their nearest painted neighbours (alpha stays 0)."""
    h, w = len(canvas), WIDTH
    known = [[canvas[y][x * 4 + 3] > 0 for x in range(w)] for y in range(h)]
    for _ in range(24):
        grown = []
        for y in range(h):
            for x in range(w):
                if known[y][x]:
                    continue
                near = [(nx, ny) for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                        if 0 <= nx < w and 0 <= ny < h and known[ny][nx]]
                if near:
                    grown.append((x, y, near))
        if not grown:
            break
        for x, y, near in grown:
            for c in range(3):
                canvas[y][x * 4 + c] = sum(canvas[ny][nx * 4 + c] for nx, ny in near) // len(near)
        for x, y, _ in grown:
            known[y][x] = True


def build(src):
    w, h, px, has_alpha = read_png(src)
    if not has_alpha:
        sys.exit("%s has no alpha channel: the painting's centre must be transparent" % src)
    box = content_box(w, h, px)
    prof = build_profiles(px, box)
    canvas = [bytearray(WIDTH * 4) for _ in range(HEIGHT)]
    worst = {}
    for cell in (LEFT, RIGHT, TOP, BOTTOM):
        place(canvas, cell, edge_piece(cell, prof), True)
    for cell in (TL, TR, BL, BR):
        rows, dev = corner_piece(px, box, cell, prof)
        worst[cell] = dev
        place(canvas, cell, rows)
    bleed_colour(canvas)
    return canvas, (w, h, box, prof, worst)


def write_tga(path, canvas):
    # type 2 (uncompressed true color), 32 bpp, descriptor 8 (eight alpha bits, origin bottom-left): the repo's others
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, WIDTH, HEIGHT, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(canvas):
            for x in range(WIDTH):
                r, g, b, a = row[x * 4:x * 4 + 4]
                f.write(bytes((b, g, r, a)))


def read_tga(path):
    data = open(path, "rb").read()
    idl, _, typ, _, _, _, _, _, w, h, bpp, desc = struct.unpack("<BBBHHBHHHHBB", data[:18])
    assert typ == 2 and bpp == 32, "expected an uncompressed 32-bit TGA"
    body = data[18 + idl:]
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
    return w, h, rows


# ---- development preview: Backdrop.lua's nine-slice, from the finished TGA -------------------------------------

def sample(rows, u, v):
    """Bilinear, the texture wrapping (the client's SetTexture(file, true, true) on the edge pieces)."""
    fx, fy = u * WIDTH - 0.5, v * HEIGHT - 0.5
    ix, iy = int(fx // 1), int(fy // 1)
    tx, ty = fx - ix, fy - iy
    out = [0.0] * 4
    for dy, wy in ((0, 1 - ty), (1, ty)):
        for dx, wx in ((0, 1 - tx), (1, tx)):
            o = ((ix + dx) % WIDTH) * 4
            px = rows[(iy + dy) % HEIGHT]
            for c in range(4):
                out[c] += px[o + c] * wx * wy
    return out


def over(dst, color, tint):
    a = color[3] / 255.0 * tint[3]
    for c in range(3):
        dst[c] = dst[c] * (1 - a) + color[c] * tint[c] * a
    return dst


def draw_frame(img, ox, oy, fw, fh, edge, tga, tint=(1, 1, 1, 1), bg=(46, 40, 34), panel=(34, 30, 26)):
    """Draw a frame fw x fh screen pixels with an edge of `edge` pixels at (ox, oy), using the client's pieces."""
    u = lambda cell, f: (cell * CELL + GUTTER + f * CONTENT) / float(WIDTH)   # f in 0..1 within the content
    gv = lambda f: (GUTTER + f * CONTENT) / float(HEIGHT)
    rep_x = max(0.0, fw / float(edge) - 2 - 1 / 16.0)
    rep_y = max(0.0, fh / float(edge) - 2 - 1 / 16.0)
    for y in range(fh):
        for x in range(fw):
            px = list(panel)
            c = None
            inl, inr, int_, inb = x < edge, x >= fw - edge, y < edge, y >= fh - edge
            if inl and int_:
                c = sample(tga, u(TL, x / float(edge)), gv(y / float(edge)))
            elif inr and int_:
                c = sample(tga, u(TR, (x - (fw - edge)) / float(edge)), gv(y / float(edge)))
            elif inl and inb:
                c = sample(tga, u(BL, x / float(edge)), gv((y - (fh - edge)) / float(edge)))
            elif inr and inb:
                c = sample(tga, u(BR, (x - (fw - edge)) / float(edge)), gv((y - (fh - edge)) / float(edge)))
            elif inl or inr:
                cell = LEFT if inl else RIGHT
                fx = (x if inl else x - (fw - edge)) / float(edge)
                c = sample(tga, u(cell, fx), 1 / 16.0 + (y - edge) / float(fh - 2 * edge) * rep_y)
            elif int_ or inb:
                cell = TOP if int_ else BOTTOM
                fy = (y if int_ else y - (fh - edge)) / float(edge)
                # the top/bottom pieces are turned: screen y reads along the texture's x, screen x along its v
                c = sample(tga, u(cell, fy), 1 / 16.0 + (x - edge) / float(fw - 2 * edge) * rep_x)
            if c is not None:
                px = over(px, c, tint)
            img[oy + y][ox + x] = tuple(int(max(0, min(255, round(v)))) for v in px)
    return img


def write_png(path, img):
    h, w = len(img), len(img[0])
    raw = b"".join(b"\x00" + bytes(c for p in row for c in p) for row in img)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) +
                chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def preview(path, tga_path):
    _, _, tga = read_tga(tga_path)
    # (width, height, edge) in screen pixels: a unit frame, a tooltip, a damage-meter window, at EllesmereUI's edge steps
    cases = [(220, 48, 12), (220, 48, 16), (200, 90, 12), (200, 90, 16), (320, 220, 16), (320, 220, 24), (150, 150, 32)]
    pad = 14
    img = [[(24, 21, 18)] * (pad + 760) for _ in range(pad * (len(cases) + 1) + sum(c[1] for c in cases))]
    y = pad
    for fw, fh, edge in cases:
        draw_frame(img, pad, y, fw, fh, edge, tga)
        draw_frame(img, pad + fw + pad, y, fw, fh, edge, tga, tint=(0.9, 0.55, 0.3, 1))   # a tinted use
        y += fh + pad
    write_png(path, img)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument("--style", choices=sorted(STYLES))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview", help="contact sheet path; with several styles its name gets the style appended")
    args = ap.parse_args()
    for style in ([args.style] if args.style else sorted(STYLES)):
        src = os.path.join(root, "assets", STYLES[style])
        out = os.path.join(root, "!!!TwichUI", "media", "borders", style + ".tga")
        canvas, (w, h, box, prof, worst) = build(src)
        print("%s: source %dx%d, border box %s (%dx%d)" % (style, w, h, box, box[2] - box[0], box[3] - box[1]))
        for name, side in (("left", LEFT), ("right", RIGHT), ("top", TOP), ("bottom", BOTTOM)):
            print("  %-6s painted %d px deep" % (name, sum(1 for p in prof[side] if p[3] > 0.5)))
        for name, cell in (("TL", TL), ("TR", TR), ("BL", BL), ("BR", BR)):
            print("  corner %s: largest change from the painting while joining its arms to the edges: %.1f / 255" % (name, worst[cell]))
        print("  texture %dx%d, cells of %d (content %d, gutter %d), 32-bit TGA" % (WIDTH, HEIGHT, CELL, CONTENT, GUTTER))
        if not args.check:
            os.makedirs(os.path.dirname(out), exist_ok=True)
            write_tga(out, canvas)
            print("  wrote", out)
        if args.preview:
            sheet = args.preview if args.style else args.preview.replace(".png", "-%s.png" % style)
            preview(sheet, out)
            print("  wrote", sheet)


if __name__ == "__main__":
    main()
