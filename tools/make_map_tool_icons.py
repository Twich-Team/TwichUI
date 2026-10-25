#!/usr/bin/env python3
"""Builds the world-map toolbar's runtime icons (media/textures/maptool-*.tga) from the source artwork.

Standard library only (no Pillow, no ImageMagick): the sources are 8-bit RGBA PNGs, the output is the
uncompressed 32-bit TGA the other media/textures files already are (bottom-left origin, 8 alpha bits).

For each icon: find the visible content (alpha above a small threshold), crop to it, scale it to fit a common box
inside the texture with its aspect ratio kept (so every icon has the same optical size by its longer side and a
clear margin that bilinear filtering can't bleed past), and resample with a premultiplied-alpha box filter (no dark
or light fringe where the edge is soft). Colors are not touched beyond that: no recolor, no sharpening.

    python3 tools/make_map_tool_icons.py [--src assets] [--out '!!!TwichUI/media/textures'] [--check]

--check builds nothing: it reports the sources' size, transparency and content bounds and the planned output.
The source files stay where they are; copies of them live in assets/ beside the other *-source.png files.
"""
import argparse
import os
import struct
import sys
import zlib

SIZE = 32          # texture side (a power of two; shown at about 18 UI units, so a little over 1 px per pixel)
FIT = 30           # the content's longer side: a 1 px margin all round
THRESHOLD = 8      # alpha (0..255) at or below which a pixel is "not content"

ICONS = {
    # runtime name         source file
    "maptool-pin": "map-tool-pin-source.png",
    "maptool-group-pin": "map-tool-group-pin-source.png",
    "maptool-ping": "map-tool-ping-source.png",
    "maptool-help": "map-tool-help-source.png",
    "maptool-filter": "map-tool-filter-source.png",
}


def read_png(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s: not a PNG" % path)
    pos, idat, header = 8, [], None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    w, h, depth, ctype, _comp, _filt, interlace = header
    if depth != 8 or ctype not in (2, 6) or interlace != 0:
        raise ValueError("%s: only 8-bit RGB/RGBA, not interlaced (got depth %d, type %d, interlace %d)" % (path, depth, ctype, interlace))
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    rows, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        elif ft != 0:
            raise ValueError("%s: bad filter %d" % (path, ft))
        rows.append(line)
        prev = line
    pixels = []   # rows of r, g, b, a bytes
    for line in rows:
        if bpp == 4:
            pixels.append(line)
        else:
            out = bytearray(w * 4)
            for x in range(w):
                out[x * 4:x * 4 + 3] = line[x * 3:x * 3 + 3]
                out[x * 4 + 3] = 255
            pixels.append(out)
    # a faint haze (alpha 1..THRESHOLD, invisible on its own) is cleared so it can't become a soft fringe once shrunk
    for line in pixels:
        for x in range(w):
            if line[x * 4 + 3] <= THRESHOLD:
                line[x * 4:x * 4 + 4] = b"\x00\x00\x00\x00"
    return w, h, pixels, ctype == 6


def content_box(w, h, pixels):
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = pixels[y]
        for x in range(w):
            if row[x * 4 + 3] > THRESHOLD:
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    if x1 < 0:
        return None
    return x0, y0, x1 + 1, y1 + 1


def resample(pixels, box, out_w, out_h):
    """Premultiplied-alpha area average of the box's pixels onto out_w x out_h. Returns rows of RGBA bytes."""
    x0, y0, x1, y1 = box
    sw, sh = x1 - x0, y1 - y0
    out = []
    for oy in range(out_h):
        ya, yb = y0 + oy * sh / out_h, y0 + (oy + 1) * sh / out_h
        row = bytearray(out_w * 4)
        for ox in range(out_w):
            xa, xb = x0 + ox * sw / out_w, x0 + (ox + 1) * sw / out_w
            r = g = b = a = wsum = 0.0
            for sy in range(int(ya), min(int(yb) + 1, y1)):
                wy = min(yb, sy + 1) - max(ya, sy)
                if wy <= 0: continue
                line = pixels[sy]
                for sx in range(int(xa), min(int(xb) + 1, x1)):
                    wx = min(xb, sx + 1) - max(xa, sx)
                    if wx <= 0: continue
                    wt = wx * wy
                    al = line[sx * 4 + 3] / 255.0
                    r += line[sx * 4] * al * wt
                    g += line[sx * 4 + 1] * al * wt
                    b += line[sx * 4 + 2] * al * wt
                    a += al * wt
                    wsum += wt
            if wsum > 0 and a > 0:
                row[ox * 4] = min(255, int(round(r / a)))
                row[ox * 4 + 1] = min(255, int(round(g / a)))
                row[ox * 4 + 2] = min(255, int(round(b / a)))
                row[ox * 4 + 3] = min(255, int(round(255 * a / wsum)))
        out.append(row)
    return out


def build(path):
    w, h, pixels, has_alpha = read_png(path)
    box = content_box(w, h, pixels)
    if box is None:
        raise ValueError("%s: no visible content" % path)
    cw, ch = box[2] - box[0], box[3] - box[1]
    scale = FIT / float(max(cw, ch))
    ow, oh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    body = resample(pixels, box, ow, oh)
    # centered on the texture
    left, top = (SIZE - ow) // 2, (SIZE - oh) // 2
    canvas = [bytearray(SIZE * 4) for _ in range(SIZE)]
    for y in range(oh):
        canvas[top + y][left * 4:(left + ow) * 4] = body[y]
    return canvas, (w, h, has_alpha, box, (ow, oh))


def write_tga(path, canvas):
    # type 2 (uncompressed true color), 32 bpp, descriptor 8 (eight alpha bits, origin bottom-left): the repo's others
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(canvas):
            for x in range(SIZE):
                r, g, b, a = row[x * 4:x * 4 + 4]
                f.write(bytes((b, g, r, a)))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "textures"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    for name, src in ICONS.items():
        path = os.path.join(args.src, src)
        canvas, info = build(path)
        w, h, has_alpha, box, out = info
        print("%-18s source %dx%d alpha=%s content %s -> %dx%d in %dx%d" % (name, w, h, has_alpha, box, out[0], out[1], SIZE, SIZE))
        if not args.check:
            write_tga(os.path.join(args.out, name + ".tga"), canvas)
    return 0


if __name__ == "__main__":
    sys.exit(main())
