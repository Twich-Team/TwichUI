#!/usr/bin/env python3
"""Builds the target-frame dragon artwork (media/targetart/*.tga) from the source paintings in assets/.

Standard library only, like tools/make_map_tool_icons.py, whose PNG reader and premultiplied-alpha box filter this
reuses: the sources are 8-bit RGBA PNGs with real transparency, the output is the uncompressed 32-bit TGA the other
media files are (bottom-left origin, 8 alpha bits).

For each painting: find the visible content (alpha above a small threshold), crop to it, scale it so its longer side
fills the texture less a 1 px clear margin at each end (the aspect ratio is kept, so the other side is whatever the
painting's is), and place it at the top left of a SIZE x SIZE canvas with a 1 px clear margin all round. The game draws
only the used part (texcoords from the metadata), so the empty rest of the canvas is never sampled. The corner pieces
are taller than wide; the "wide" ones (a longer arm, wings) are wider than tall. Colors
are not touched beyond the resampling: no recolor, no sharpening, no background.

It also finds each dragon's crook: the inside corner of the curve between its head and its tail, measured as the
top-right corner of the largest empty rectangle in the bottom-left of the painting (the space a frame can sit in
without touching the art). targetart/Config.lua places every dragon by its crook, so the three line up the same way
on the frame however much empty space their paintings had.

    python3 tools/make_target_art.py [--src assets] [--out '!!!TwichUI/media/targetart'] [--check]

--check builds nothing: it prints the sources' size and content bounds, and the metadata the build would give.
The printed metadata is what targetart/Config.lua's ART table holds; after a rebuild, copy any changed numbers there.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box, resample, THRESHOLD  # noqa: E402

SIZE = 256         # texture side (a power of two). Drawn at roughly 70 to 270 UI units tall, so this is near 1:1.

ART = {
    # runtime name   source file
    "rare": "target-art-rare-source.png",
    "boss": "target-art-boss-source.png",
    "elite": "target-art-elite-source.png",
    "rare-wide": "target-art-rare-wide-source.png",
    "boss-wide": "target-art-boss-wide-source.png",
    "elite-wide": "target-art-elite-wide-source.png",
}


def crook(w, h, pixels, box):
    """(cx, cy) in source pixels: the corner of the largest content-free rectangle at the content's bottom left."""
    x0, y0, x1, y1 = box
    left = [w] * (h + 1)   # left[y]: the leftmost content column in rows y and below
    for y in range(y1 - 1, y0 - 1, -1):
        row, lx = pixels[y], w
        for x in range(x0, x1):
            if row[x * 4 + 3] > THRESHOLD:
                lx = x
                break
        left[y] = min(lx, left[y + 1])
    best = None
    for cy in range(y0, y1):
        cx = left[cy + 1]
        area = (cx - x0) * (y1 - cy)
        if best is None or area > best[0]:
            best = (area, cx, cy)
    return best[1], best[2]


def build(path):
    w, h, pixels, has_alpha = read_png(path)
    if not has_alpha:
        raise ValueError("%s: no alpha channel" % path)
    box = content_box(w, h, pixels)
    if box is None:
        raise ValueError("%s: no visible content" % path)
    cx, cy = crook(w, h, pixels, box)
    cw, ch = box[2] - box[0], box[3] - box[1]
    scale = (SIZE - 2) / float(max(cw, ch))
    ow, oh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    body = resample(pixels, box, ow, oh)
    canvas = [bytearray(SIZE * 4) for _ in range(SIZE)]
    for y in range(oh):
        canvas[1 + y][4:(1 + ow) * 4] = body[y]
    used_w, used_h = ow + 2, oh + 2   # with the clear margin on both sides
    meta = {
        "width": used_w, "height": used_h,
        "crookX": (1 + (cx - box[0]) * scale) / used_w,
        "crookY": (1 + (cy - box[1]) * scale) / used_h,
    }
    return canvas, (w, h, box, (cx, cy), meta)


def write_tga(path, canvas):
    import struct
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(canvas):
            out = bytearray(SIZE * 4)
            for x in range(SIZE):
                r, g, b, a = row[x * 4:x * 4 + 4]
                out[x * 4:x * 4 + 4] = bytes((b, g, r, a))
            f.write(out)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "targetart"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for name, src in ART.items():
        canvas, info = build(os.path.join(args.src, src))
        w, h, box, ck, meta = info
        print("%-6s source %dx%d content %s crook %s -> %dx%d of %dx%d" % (name, w, h, box, ck, meta["width"] - 2,
                                                                       meta["height"] - 2, SIZE, SIZE))
        print("       { width = %d, height = %d, crookX = %.3f, crookY = %.3f }" % (meta["width"], meta["height"],
                                                                                    meta["crookX"], meta["crookY"]))
        if not args.check:
            write_tga(os.path.join(args.out, name + ".tga"), canvas)
    return 0


if __name__ == "__main__":
    sys.exit(main())
