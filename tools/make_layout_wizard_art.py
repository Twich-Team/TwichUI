#!/usr/bin/env python3
"""Builds the layout wizard's artwork (TwichUI_LayoutWizard/media/*.tga) from the four source images in assets/.

Standard library only, like the other tools/make_*.py, whose PNG reader and premultiplied-alpha box filter this reuses.
Nothing is generated, recoloured, sharpened or added: each runtime file is a crop and a shrink of a source that exists.
What each source needed (read from the files, not assumed):

  layout-wizard-emblem-source.png      1254 x 1254, 8-bit RGB, NO alpha channel: the "transparent" background is a grey
                                       checkerboard painted into the pixels. It is taken out by flooding from the border
                                       through neutral light-grey pixels only (the object is warm or dark; nothing the
                                       flood can't reach from outside is touched), and the soft rim is given an alpha by
                                       unmixing it from the local checker grey. Result: emblem.tga, 128 x 128.
  layout-wizard-classic-source.png     1536 x 1024 RGBA with genuine transparency (about three quarters of it alpha 0, a soft
                                       golden aura around the picture kept as painted). Cut to its content and shrunk to fit
                                       512 x 256, centred: classic.tga.
  layout-wizard-personalize-screenfit-source.png
                                       1774 x 887 RGBA, two separate pictures on a clear sheet. Split where the sheet is
                                       clear (the two runs of columns that hold any alpha are found, not assumed): left
                                       Personalize (colour swatches), right Screen Fit (a frame with an arrow). Each is cut
                                       to its content and shrunk: personalize.tga and screenfit.tga, 128 x 128.
  layout-wizard-compact-source.png     1536 x 1024 RGBA, built the same way. Reserved for Phase 5: not built unless --phase5
                                       is given (compact.tga), so it adds nothing to the package until it is used.
  layout-wizard-icons-source.png       1312 x 1199 RGBA ("Fantasy UI Icon Sheet.png", copied here), genuine transparency (about
                                       59% alpha 0; the painted parts sit at alpha 249-254, so a pixel at 240 or more is made fully
                                       opaque and the soft rim, which is a few pixels wide, is kept). Four pictures on a clear
                                       sheet in two rows of two, found by measurement (the rows and then the columns that hold any
                                       alpha, not assumed): a closed journal with a ribbon (keep.tga: "Keep my settings"), a
                                       resource bar, a pin and a cup (helpers.tga: "On-screen helpers"), a tooltip pinned in a
                                       screen's corner (tipfixed.tga: "Layout position") and a tooltip beside a cursor
                                       (tipcursor.tga: "Follow mouse"). Each is cut to its content and shrunk to fit 128 x 128
                                       (its longer side fills the same share of the file, so they look the same size).

  layout-wizard-curated-source.png     1254 x 1254 RGBA with genuine transparency: a brown leather satchel holding a scroll and a
                                       bottle (curated.tga: the "Curated" helper preset). Cut to its content and shrunk to fit
                                       128 x 128 like the icon sheet's pictures.

    python3 tools/make_layout_wizard_art.py [--src assets] [--out TwichUI_LayoutWizard/media] [--check] [--phase5]
                                            [--preview DIR]

--check builds nothing and prints each source's findings. --preview DIR also writes PNGs (the emblem and the four icons on dark and
light backgrounds, to look at the rim) there. Output TGAs are uncompressed 32-bit, bottom-left origin, 8 alpha bits: the format
of every other media file in the project.
"""
import argparse
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box, resample  # noqa: E402
from make_training_art import bleed  # noqa: E402

SOURCES = {
    "emblem": "layout-wizard-emblem-source.png",
    "classic": "layout-wizard-classic-source.png",
    "sheet": "layout-wizard-personalize-screenfit-source.png",
    "compact": "layout-wizard-compact-source.png",
    "icons": "layout-wizard-icons-source.png",
    "curated": "layout-wizard-curated-source.png",
}
ICON_NAMES = ("keep", "helpers", "tipfixed", "tipcursor")   # the sheet's pictures, row by row
ICON_OPAQUE = 240    # painted pixels at or above this alpha are made fully opaque (the source's interiors sit at 249-254)

# Neutral light grey: the checkerboard's two greys (about 234 and 254, with a little noise) and nothing the object has.
NEUTRAL_SPREAD = 7      # max(r, g, b) - min(r, g, b) at most
NEUTRAL_MIN = 205       # and every channel at least this
RIM_REACH = 3           # pixels from the background that can be a soft rim
MIN_CONTRAST = 28       # a rim pixel closer to the checker grey than this to the picture's own edge colour stays opaque


def is_checker(row, x):
    r, g, b = row[x * 4], row[x * 4 + 1], row[x * 4 + 2]
    hi, lo = max(r, g, b), min(r, g, b)
    return hi - lo <= NEUTRAL_SPREAD and lo >= NEUTRAL_MIN


def remove_checkerboard(w, h, pixels):
    """Alpha for an opaque picture on a painted checkerboard. Returns (rows of RGBA, background pixel count, rim count)."""
    bg = [bytearray(w) for _ in range(h)]
    stack = []
    for x in range(w):
        for y in (0, h - 1):
            if is_checker(pixels[y], x) and not bg[y][x]:
                bg[y][x] = 1
                stack.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_checker(pixels[y], x) and not bg[y][x]:
                bg[y][x] = 1
                stack.append((x, y))
    while stack:
        x, y = stack.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not bg[ny][nx] and is_checker(pixels[ny], nx):
                bg[ny][nx] = 1
                stack.append((nx, ny))
    # distance (in steps) of every picture pixel from the background, out to RIM_REACH
    dist = [bytearray([255]) * w for _ in range(h)]
    frontier = []
    for y in range(h):
        for x in range(w):
            if bg[y][x]:
                dist[y][x] = 0
                frontier.append((x, y))
    for step in range(1, RIM_REACH + 1):
        nxt = []
        for x, y in frontier:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and dist[ny][nx] == 255:
                    dist[ny][nx] = step
                    nxt.append((nx, ny))
        frontier = nxt
    out = [bytearray(w * 4) for _ in range(h)]
    rim = 0
    nbg = 0
    for y in range(h):
        src, dst = pixels[y], out[y]
        for x in range(w):
            i = x * 4
            if bg[y][x]:
                nbg += 1
                continue   # alpha 0
            d = dist[y][x]
            r, g, b = src[i], src[i + 1], src[i + 2]
            a = 255
            if d <= RIM_REACH:
                # the checker grey beside it, and the picture's own colour just inside
                grey_sum = grey_n = inner_n = 0
                inner = [0, 0, 0]
                for dy in range(-RIM_REACH - 1, RIM_REACH + 2):
                    ny = y + dy
                    if not 0 <= ny < h:
                        continue
                    for dx in range(-RIM_REACH - 1, RIM_REACH + 2):
                        nx = x + dx
                        if not 0 <= nx < w:
                            continue
                        if bg[ny][nx]:
                            grey_sum += pixels[ny][nx * 4]
                            grey_n += 1
                        elif dist[ny][nx] > RIM_REACH:
                            for c in range(3):
                                inner[c] += pixels[ny][nx * 4 + c]
                            inner_n += 1
                if grey_n and inner_n:
                    grey = grey_sum / float(grey_n)
                    v = [inner[c] / float(inner_n) - grey for c in range(3)]
                    den = v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
                    if den >= MIN_CONTRAST * MIN_CONTRAST:
                        t = ((r - grey) * v[0] + (g - grey) * v[1] + (b - grey) * v[2]) / den
                        a = int(round(max(0.0, min(1.0, t)) * 255))
                        if a < 255:
                            rim += 1
                            if a > 0:
                                # the colour with the grey taken out
                                k = a / 255.0
                                r = int(round(max(0, min(255, (r - (1 - k) * grey) / k))))
                                g = int(round(max(0, min(255, (g - (1 - k) * grey) / k))))
                                b = int(round(max(0, min(255, (b - (1 - k) * grey) / k))))
            dst[i], dst[i + 1], dst[i + 2], dst[i + 3] = r, g, b, a
    return out, nbg, rim


def fit(pixels, w, h, box, cw, ch, margin):
    """The box's pixels, scaled uniformly to fit cw x ch with a margin, centred. Returns the canvas rows."""
    bw, bh = box[2] - box[0], box[3] - box[1]
    scale = min((cw - 2 * margin) / float(bw), (ch - 2 * margin) / float(bh))
    ow, oh = max(1, int(round(bw * scale))), max(1, int(round(bh * scale)))
    body = resample(pixels, box, ow, oh)
    canvas = [bytearray(cw * 4) for _ in range(ch)]
    ox, oy = (cw - ow) // 2, (ch - oh) // 2
    for y in range(oh):
        canvas[oy + y][ox * 4:(ox + ow) * 4] = body[y]
    bleed(canvas, cw, ch)
    return canvas, (ow, oh)


def row_runs(w, h, pixels, floor=8):
    """Runs of rows that hold any alpha above the floor (the bands a sheet's pictures sit in)."""
    runs, start = [], None
    for y in range(h):
        row = pixels[y]
        has = any(row[x * 4 + 3] > floor for x in range(w))
        if has and start is None:
            start = y
        if not has and start is not None:
            runs.append((start, y))
            start = None
    if start is not None:
        runs.append((start, h))
    return [r for r in runs if r[1] - r[0] >= 40]


def solid_interior(rows):
    """Painted pixels a hair under opaque (alpha 240+) become opaque; the soft rim below that is left as it is."""
    for row in rows:
        for x in range(len(row) // 4):
            if row[x * 4 + 3] >= ICON_OPAQUE:
                row[x * 4 + 3] = 255


def column_runs(w, h, pixels, floor=8):
    cols = [0] * w
    for y in range(h):
        row = pixels[y]
        for x in range(w):
            if row[x * 4 + 3] > floor:
                cols[x] += 1
    runs, start = [], None
    for x in range(w):
        if cols[x] and start is None:
            start = x
        if not cols[x] and start is not None:
            runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, w))
    # a stray run of a few columns is not a picture
    return [r for r in runs if r[1] - r[0] >= 40]


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


def write_png(path, w, h, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def over(rows, color):
    """The rows composited over a flat colour (to look at a rim)."""
    out = []
    for row in rows:
        line = bytearray(len(row))
        for x in range(len(row) // 4):
            a = row[x * 4 + 3] / 255.0
            for c in range(3):
                line[x * 4 + c] = int(round(row[x * 4 + c] * a + color[c] * (1 - a)))
            line[x * 4 + 3] = 255
        out.append(line)
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "TwichUI_LayoutWizard", "media"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--phase5", action="store_true")
    ap.add_argument("--preview")
    args = ap.parse_args()
    built = {}

    # emblem
    w, h, px, has_alpha = read_png(os.path.join(args.src, SOURCES["emblem"]))
    print("emblem   source %dx%d alpha=%s" % (w, h, has_alpha))
    if has_alpha:
        rows = px
        print("         already has alpha: used as it is")
    else:
        rows, nbg, rim = remove_checkerboard(w, h, px)
        print("         checkerboard flooded from the border: %d background pixels (%.1f%%), %d soft-rim pixels given a partial alpha"
              % (nbg, 100.0 * nbg / (w * h), rim))
    box = content_box(w, h, rows)
    canvas, size = fit(rows, w, h, box, 128, 128, 4)
    print("         content %s -> %dx%d in 128x128" % (box, size[0], size[1]))
    built["emblem"] = (canvas, 128, 128)
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        for name, color in (("dark", (36, 34, 32)), ("light", (236, 232, 222))):
            write_png(os.path.join(args.preview, "emblem-on-%s.png" % name), 128, 128, over(canvas, color))

    # Classic Adventure's picture, and (Phase 5) Compact Adventure's: genuine alpha, cut to the content
    def picture(key):
        w, h, px, has_alpha = read_png(os.path.join(args.src, SOURCES[key]))
        if not has_alpha:
            raise SystemExit("%s has no alpha channel: refusing to guess where its picture ends" % SOURCES[key])
        box = content_box(w, h, px)
        canvas, size = fit(px, w, h, box, 512, 256, 2)
        print("%-8s source %dx%d alpha=%s content %s -> %dx%d in 512x256" % (key, w, h, has_alpha, box, size[0], size[1]))
        return canvas, 512, 256

    built["classic"] = picture("classic")

    # Personalize and Screen Fit
    w, h, px, has_alpha = read_png(os.path.join(args.src, SOURCES["sheet"]))
    runs = column_runs(w, h, px)
    print("sheet    source %dx%d alpha=%s, pictures at columns %s" % (w, h, has_alpha, runs))
    if not has_alpha or len(runs) != 2:
        raise SystemExit("the sheet is not two pictures on a clear background: refusing to guess")
    for name, (x0, x1) in zip(("personalize", "screenfit"), runs):
        part = [row[x0 * 4:x1 * 4] for row in px]
        box = content_box(x1 - x0, h, part)
        canvas, size = fit(part, x1 - x0, h, box, 128, 128, 4)
        print("         %-11s content %s -> %dx%d in 128x128" % (name, box, size[0], size[1]))
        built[name] = (canvas, 128, 128)

    # The icon sheet: two rows of two pictures, found by measurement
    w, h, px, has_alpha = read_png(os.path.join(args.src, SOURCES["icons"]))
    bands = row_runs(w, h, px)
    print("icons    source %dx%d alpha=%s, rows at %s" % (w, h, has_alpha, bands))
    if not has_alpha or len(bands) != 2:
        raise SystemExit("the icon sheet is not two rows of pictures on a clear background: refusing to guess")
    cells = []
    for (y0, y1) in bands:
        band = [row for row in px[y0:y1]]
        runs = column_runs(w, y1 - y0, band)
        print("         row %d-%d: pictures at columns %s" % (y0, y1, runs))
        if len(runs) != 2:
            raise SystemExit("a row of the icon sheet does not hold two pictures: refusing to guess")
        for (x0, x1) in runs:
            cells.append([bytearray(r[x0 * 4:x1 * 4]) for r in band])
    # a solid interior (the sheet's painted pixels are a hair under opaque) before the shrink
    for name, cell in zip(ICON_NAMES, cells):
        solid_interior(cell)
        cw_, ch_ = len(cell[0]) // 4, len(cell)
        box = content_box(cw_, ch_, cell)
        canvas, size = fit(cell, cw_, ch_, box, 128, 128, 4)
        print("         %-9s content %s -> %dx%d in 128x128" % (name, box, size[0], size[1]))
        built[name] = (canvas, 128, 128)
        if args.preview:
            os.makedirs(args.preview, exist_ok=True)
            for tone, color in (("dark", (36, 34, 32)), ("light", (236, 232, 222))):
                write_png(os.path.join(args.preview, "%s-on-%s.png" % (name, tone)), 128, 128, over(canvas, color))

    # The Curated preset's picture: one picture, genuine alpha
    w, h, px, has_alpha = read_png(os.path.join(args.src, SOURCES["curated"]))
    if not has_alpha:
        raise SystemExit("%s has no alpha channel: refusing to guess where its picture ends" % SOURCES["curated"])
    solid_interior(px)
    box = content_box(w, h, px)
    canvas, size = fit(px, w, h, box, 128, 128, 4)
    print("curated  source %dx%d alpha=%s content %s -> %dx%d in 128x128" % (w, h, has_alpha, box, size[0], size[1]))
    built["curated"] = (canvas, 128, 128)
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        for tone, color in (("dark", (36, 34, 32)), ("light", (236, 232, 222))):
            write_png(os.path.join(args.preview, "curated-on-%s.png" % tone), 128, 128, over(canvas, color))

    if args.phase5:
        built["compact"] = picture("compact")
    else:
        print("compact  not built: reserved for Phase 5 (--phase5)")

    if not args.check:
        os.makedirs(args.out, exist_ok=True)
        for name, (canvas, cw, ch) in built.items():
            write_tga(os.path.join(args.out, name + ".tga"), canvas, cw, ch)
            print("wrote %s.tga (%dx%d)" % (name, cw, ch))
    return 0


if __name__ == "__main__":
    sys.exit(main())
