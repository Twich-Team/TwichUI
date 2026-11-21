#!/usr/bin/env python3
"""Builds TwichUI Fishing's heads-up artwork (TwichUI_Fishing/media/*.tga) from the production texture pack.

Standard library only, like the other make_*.py tools: the PNG reader and the premultiplied-alpha box resampler are
tools/make_map_tool_icons.py's; the output is the uncompressed 32-bit TGA the repository's other media are (bottom-left
origin, eight alpha bits), on power-of-two canvases.

Sources (assets/fishing/, copied unchanged from TwichUI_Fishing_Production_Textures.zip; texture-pack-manifest.json is the
pack's own manifest). The pack's art was painted as a whole and cut out; it has never been drawn by the game. What is
corrected here, and why:

    castbar          hud/cast_bar_empty.png        the walnut-and-bronze bar with its hook, kept as painted (513 px wide
                                                   resampled to 512). Its trough's inside is measured below (TROUGH) so the
                                                   fill lands in it; the bar is drawn whole, never sliced.
    castfill         hud/progress_fill.png         the pack's fill is a flat, bright yellow rectangle. It is resampled to
                                                   the trough's own inside, toned from yellow towards a subtle antique amber,
                                                   given the trough's rounded left and right ends (a square fill would sit
                                                   over the rim), and a faint top highlight is kept.
    castspark        (made here)                   a small soft warm glow for the fill's moving edge.
    toast            hud/catch_toast_fish_reference.png    the notification's bronze icon frame and its fading band. The
    toast-treasure   hud/catch_toast_pearl_reference.png   pack's toasts have a sample fish and a sample pearl baked into the
                                                   icon well; the well is cut out (an octagon with the frame's chamfer, a
                                                   one-pixel feathered edge) so the caught item's real icon shows through
                                                   from under it. The well's bounds are WELL below.
    glint            effects/glint.png             a gold flare, behind a treasure notification's icon. Resampled only.
    divider          decoration/divider_lower.png  the thin bronze rule between the catch list's sections. Resampled only.
    mark             branding/mini_icon.png        the small fish mark beside the prompts. Resampled only.
    scrim            (made here)                   a soft, warm, very dark shade that fades to nothing towards the screen's
                                                   middle and at its top and bottom, under the catch list, so ivory text
                                                   reads over bright snow or water as well as at night. No hard edge.
    rowglow          (made here)                   a soft amber band, brightest in the middle, for a row that just changed.

Not used, deliberately: hud/catch_count_reference.png (baked "x3" text), hud/cast_bar_*_reference.png (references of the
fill), collection/* (illustrative fish, not real items: the game's own item icons are used), panels/*, controls/*,
nine_slice/* and decoration/* other than the rule (Journal and settings surfaces belong to later stages), effects/ripple and
effects/splash (saturated blue water effects that would read as a bite signal, which the game does not give).

    python3 tools/make_fishing_art.py [--src assets/fishing] [--out TwichUI_Fishing/media] [--check] [--sheet out.png]

--check builds nothing and only reports. --sheet also writes a contact sheet (each texture over a checkerboard).
"""
import argparse
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, resample  # noqa: E402

# Measured on cast_bar_empty.png (513 x 85): the dark trough's inside, left, top, right, bottom (exclusive), source px.
TROUGH = (103, 40, 461, 58)
# The icon well of each toast's frame: left, top, right, bottom (exclusive) and the chamfer of its corners, source px.
WELL = {
    "toast": (11, 10, 92, 87, 10),
    "toast-treasure": (11, 11, 79, 80, 9),
}
AMBER = (204, 146, 66)       # the tone the fill is moved towards
AMBER_MIX = 0.42             # how far (0 none, 1 all the way)
FILL_GAIN = 0.94             # and a little darker than the pack's


def blank(w, h):
    return [bytearray(w * 4) for _ in range(h)]


def paste(canvas, rows, left, top):
    for y, row in enumerate(rows):
        w = len(row) // 4
        canvas[top + y][left * 4:(left + w) * 4] = row


def write_tga(path, canvas):
    h, w = len(canvas), len(canvas[0]) // 4
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(canvas):
            out = bytearray(w * 4)
            for x in range(w):
                r, g, b, a = row[x * 4:x * 4 + 4]
                out[x * 4:x * 4 + 4] = bytes((b, g, r, a))
            f.write(out)


def write_png(path, rows):
    h, w = len(rows), len(rows[0]) // 4
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def pow2(n):
    p = 1
    while p < n:
        p *= 2
    return p


def fit(pixels, box, w, h):
    """The box resampled to w x h on the smallest power-of-two canvas, at its top left. Returns canvas, (w, h)."""
    body = resample(pixels, box, w, h)
    canvas = blank(pow2(w), pow2(h))
    paste(canvas, body, 0, 0)
    return canvas, (w, h)


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def capsule_alpha(x, y, w, h):
    """Coverage (0..1) of a w x h capsule (fully rounded ends) at pixel (x, y), with a one-pixel antialiased edge."""
    r = h / 2.0
    cx = min(max(x + 0.5, r), w - r)
    d = math.hypot(x + 0.5 - cx, y + 0.5 - r)
    return max(0.0, min(1.0, r - d + 0.5))


def castbar(src):
    w, h, px, _ = read_png(os.path.join(src, "cast_bar_empty.png"))
    canvas, size = fit(px, (0, 0, w, h), 512, 85)
    sx = 512.0 / w
    trough = (TROUGH[0] * sx, TROUGH[1], TROUGH[2] * sx, TROUGH[3])
    return canvas, size, {"trough": tuple(round(v, 1) for v in trough)}


def castfill(src):
    w, h, px, _ = read_png(os.path.join(src, "progress_fill.png"))
    fw = int(round((TROUGH[2] - TROUGH[0]) * 512.0 / 513.0))
    fh = TROUGH[3] - TROUGH[1]
    body = resample(px, (0, 0, w, h), fw, fh)
    for y, row in enumerate(body):
        for x in range(fw):
            r, g, b, a = row[x * 4:x * 4 + 4]
            r = (r * (1 - AMBER_MIX) + AMBER[0] * AMBER_MIX) * FILL_GAIN
            g = (g * (1 - AMBER_MIX) + AMBER[1] * AMBER_MIX) * FILL_GAIN
            b = (b * (1 - AMBER_MIX) + AMBER[2] * AMBER_MIX) * FILL_GAIN
            # a faint highlight along the top third, a little shade along the bottom: a shallow bevel, not a glow
            t = (y + 0.5) / fh
            lift = 1.0 + 0.10 * (1 - smooth(t / 0.4)) - 0.12 * smooth((t - 0.6) / 0.4)
            cov = capsule_alpha(x, y, fw, fh)
            alpha = min(255, int(round(max(a, 200) * cov)))
            row[x * 4:x * 4 + 4] = bytes((min(255, int(r * lift)), min(255, int(g * lift)), min(255, int(b * lift)), alpha))
    canvas = blank(pow2(fw), pow2(fh))
    paste(canvas, body, 0, 0)
    return canvas, (fw, fh), {}


def castspark(_src):
    side = 32
    canvas = blank(side, side)
    for y in range(side):
        for x in range(side):
            dx, dy = (x + 0.5 - side / 2) / (side / 2), (y + 0.5 - side / 2) / (side / 4.0)
            d = math.hypot(dx, dy)
            a = (1 - smooth(d)) ** 1.6
            canvas[y][x * 4:x * 4 + 4] = bytes((255, 222, 160, int(255 * a)))
    return canvas, (side, side), {}


def toast(src, name, file):
    w, h, px, _ = read_png(os.path.join(src, file))
    x0, y0, x1, y1, c = WELL[name]
    for y in range(y0, y1):
        row = px[y]
        for x in range(x0, x1):
            # distance inside the octagon (negative outside): the four edges and the four chamfers
            inside = min(x + 0.5 - x0, x1 - x - 0.5, y + 0.5 - y0, y1 - y - 0.5,
                         (x + 0.5 - x0 + y + 0.5 - y0 - c) / math.sqrt(2),
                         (x1 - x - 0.5 + y + 0.5 - y0 - c) / math.sqrt(2),
                         (x + 0.5 - x0 + y1 - y - 0.5 - c) / math.sqrt(2),
                         (x1 - x - 0.5 + y1 - y - 0.5 - c) / math.sqrt(2))
            keep = max(0.0, min(1.0, 1.0 - inside))   # 1 at and outside the edge, 0 one pixel in
            row[x * 4 + 3] = int(row[x * 4 + 3] * keep)
    canvas = blank(pow2(w), pow2(h))
    paste(canvas, px, 0, 0)
    return canvas, (w, h), {"well": (x0, y0, x1, y1)}


def plain(src, file, ow, oh):
    w, h, px, _ = read_png(os.path.join(src, file))
    return fit(px, (0, 0, w, h), ow, oh) + ({},)


def scrim(_src):
    w, h = 128, 256
    canvas = blank(w, h)
    for y in range(h):
        v = smooth((y + 0.5) / (h * 0.22)) * smooth((h - y - 0.5) / (h * 0.22))
        for x in range(w):
            u = smooth((x + 0.5) / w) ** 1.3
            canvas[y][x * 4:x * 4 + 4] = bytes((16, 11, 8, int(255 * u * v)))
    return canvas, (w, h), {}


def rowglow(_src):
    w, h = 256, 32
    canvas = blank(w, h)
    for y in range(h):
        v = 1 - smooth(abs((y + 0.5) / h - 0.5) * 2)
        for x in range(w):
            u = 1 - smooth(abs((x + 0.5) / w - 0.5) * 2) ** 0.8
            canvas[y][x * 4:x * 4 + 4] = bytes((232, 178, 92, int(255 * u * v)))
    return canvas, (w, h), {}


def builds(src):
    return [
        ("castbar", lambda: castbar(src)),
        ("castfill", lambda: castfill(src)),
        ("castspark", lambda: castspark(src)),
        ("toast", lambda: toast(src, "toast", "catch_toast_fish_reference.png")),
        ("toast-treasure", lambda: toast(src, "toast-treasure", "catch_toast_pearl_reference.png")),
        ("glint", lambda: plain(src, "glint.png", 128, 61)),
        ("divider", lambda: plain(src, "divider_lower.png", 256, 26)),
        ("mark", lambda: plain(src, "mini_icon.png", 63, 64)),
        ("scrim", lambda: scrim(src)),
        ("rowglow", lambda: rowglow(src)),
    ]


def contact_sheet(path, built):
    pad = 8
    W = max(len(c[0]) // 4 for _, c, _, _ in built) + pad * 2
    H = sum(len(c) + pad for _, c, _, _ in built) + pad
    sheet = blank(W, H)
    y = pad
    for _, canvas, _, _ in built:
        ch, cw = len(canvas), len(canvas[0]) // 4
        for yy in range(ch):
            out = sheet[y + yy]
            for xx in range(cw):
                check = 70 if ((xx // 8 + (y + yy) // 8) % 2) else 40
                r, g, b, a = canvas[yy][xx * 4:xx * 4 + 4]
                al = a / 255.0
                X = (pad + xx) * 4
                out[X:X + 4] = bytes((int(r * al + check * (1 - al)), int(g * al + check * (1 - al)),
                                      int(b * al + check * (1 - al)), 255))
        y += ch + pad
    write_png(path, sheet)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "fishing"))
    ap.add_argument("--out", default=os.path.join(root, "TwichUI_Fishing", "media"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--sheet")
    args = ap.parse_args()
    built = []
    for name, make in builds(args.src):
        canvas, size, facts = make()
        cw, ch = len(canvas[0]) // 4, len(canvas)
        print("%-15s %4dx%-4d content %dx%d %s" % (name, cw, ch, size[0], size[1], " ".join("%s=%s" % kv for kv in facts.items())))
        built.append((name, canvas, size, facts))
    if args.check:
        return
    os.makedirs(args.out, exist_ok=True)
    for name, canvas, _, _ in built:
        write_tga(os.path.join(args.out, name + ".tga"), canvas)
    if args.sheet:
        contact_sheet(args.sheet, built)


if __name__ == "__main__":
    main()
