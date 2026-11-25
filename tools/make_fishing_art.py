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
    mark             branding/mini_icon.png        the small fish mark, beside the catches under the cast bar. Resampled only.
    logo             branding/fishing_logo.png     the "TwichUI Fishing" emblem and plaque, top left in immersive Fishing Mode (as
                                                   in the approved mockup). Kept at its own size on a 512 x 256 canvas.
    iconframe        hud/catch_toast_fish_reference.png    the notification's bronze octagonal icon frame on its own, for the
                                                   catch list's item icons: the sample fish cut out of the well (as for toast)
                                                   and the band cut away outside the frame's outer octagon (OUTER).
    rule             decoration/divider_upper.png  the fine bronze rule with a small centre ornament: under the catch list's
                                                   heading and treasures heading, and faintly between its rows (as in the
                                                   mockup). Resampled only. (divider_lower, with three diamonds, read heavier
                                                   than the mockup's rules and is not used.)
    settings         branding/feature_icon.png     the leaping fish in its bronze frame: Fishing's icon in the TwichUI settings
                                                   window (Home, the page list, search). Written into the core,
                                                   !!!TwichUI/media/fishing/settings.tga (64 px) and settings-small.tga (32 px),
                                                   so it shows while TwichUI_Fishing has not loaded. Fitted with a 3 px margin.
    glyph-lure       icons/lure.png                the feather lure, beside the lure's time under the cast bar
    glyph-time       icons/bobber.png              the bobber, beside the session's length under the cast bar. Each glyph is
                                                   fitted to a 64 px square with its aspect kept, as the mockup's stat row shows
                                                   them; the catches use `mark` (the pack's collection fish are framed tiles,
                                                   not symbols, and are not used).
    j-*, glyph-hook|clam|treasure   (Stage 3A, the Journal; JOURNAL_FILES below) the pack's journal, recessed and chestnut
                                                   frames, rows, nav and compact buttons, close button, unknown tile and fish
                                                   watermark, and three more glyphs, each resampled onto a power-of-two canvas.
    scrim            (made here)                   a soft, warm, very dark oval, feathered to nothing on every side, drawn
                                                   faintly under the catch list and the cast bar's lines so ivory text reads
                                                   over bright snow or water as well as at night. No edge anywhere.
    rowglow          (made here)                   a soft amber band, brightest in the middle, for a row that just changed.

Not used, deliberately: hud/catch_count_reference.png (baked "x3" text), hud/cast_bar_*_reference.png (references of the
fill), collection/* other than the "unknown" tile (illustrative fish, not real items: the game's own item icons are used),
nine_slice/* (the Journal cuts the whole frames with texture coordinates instead) and decoration/* other than the rule and the fish
watermark, effects/ripple and
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
# The fish toast's frame on its own (iconframe): its outer octagon, left, top, right, bottom (exclusive), chamfer, source px.
OUTER = (3, 2, 99, 96, 14)
# The icon well of each toast's frame: left, top, right, bottom (exclusive) and the chamfer of its corners, source px.
WELL = {
    "toast": (11, 10, 93, 86, 10),
    "toast-treasure": (11, 12, 85, 83, 10),
}
AMBER = (204, 146, 66)       # the tone the fill is moved towards
AMBER_MIX = 0.28             # how far (0 none, 1 all the way): the mockup's warm gold, not the pack's flat yellow
FILL_GAIN = 0.98             # and a touch darker than the pack's


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


def octagon(x, y, box):
    """Signed distance (pixels, positive inside) from (x, y) to an octagon (left, top, right, bottom, chamfer)."""
    x0, y0, x1, y1, c = box
    r2 = math.sqrt(2)
    return min(x + 0.5 - x0, x1 - x - 0.5, y + 0.5 - y0, y1 - y - 0.5,
               (x + 0.5 - x0 + y + 0.5 - y0 - c) / r2, (x1 - x - 0.5 + y + 0.5 - y0 - c) / r2,
               (x + 0.5 - x0 + y1 - y - 0.5 - c) / r2, (x1 - x - 0.5 + y1 - y - 0.5 - c) / r2)


def iconframe(src):
    canvas, _, facts = toast(src, "toast", "catch_toast_fish_reference.png")
    x0, y0, x1, y1, _c = OUTER
    w, h = x1 - x0, y1 - y0
    rows = []
    for y in range(y0, y1):
        row = bytearray(canvas[y][x0 * 4:x1 * 4])
        for x in range(w):
            keep = max(0.0, min(1.0, octagon(x0 + x, y, OUTER) + 0.5))
            row[x * 4 + 3] = int(row[x * 4 + 3] * keep)
        rows.append(row)
    side = 64
    body = resample(rows, (0, 0, w, h), side, side)
    out = blank(side, side)
    paste(out, body, 0, 0)
    wx0, wy0, wx1, wy1 = facts["well"]
    sx, sy = side / float(w), side / float(h)
    well = (round((wx0 - x0) * sx, 1), round((wy0 - y0) * sy, 1), round((wx1 - x0) * sx, 1), round((wy1 - y0) * sy, 1))
    return out, (side, side), {"well": well}


def glyph(src, file):
    w, h, px, _ = read_png(os.path.join(src, file))
    side, fill = 64, 60
    s = fill / float(max(w, h))
    ow, oh = max(1, int(round(w * s))), max(1, int(round(h * s)))
    body = resample(px, (0, 0, w, h), ow, oh)
    out = blank(side, side)
    paste(out, body, (side - ow) // 2, (side - oh) // 2)
    return out, (side, side), {}


def logo(src):
    w, h, px, _ = read_png(os.path.join(src, "fishing_logo.png"))
    out = blank(pow2(w), pow2(h))
    paste(out, px, 0, 0)
    return out, (w, h), {}


def icon(src, side, pad):
    w, h, px, _ = read_png(os.path.join(src, "feature_icon.png"))
    fill = side - 2 * pad
    s = fill / float(max(w, h))
    ow, oh = max(1, int(round(w * s))), max(1, int(round(h * s)))
    body = resample(px, (0, 0, w, h), ow, oh)
    out = blank(side, side)
    paste(out, body, (side - ow) // 2, (side - oh) // 2)
    return out, (side, side), {}


def plain(src, file, ow, oh):
    w, h, px, _ = read_png(os.path.join(src, file))
    return fit(px, (0, 0, w, h), ow, oh) + ({},)


def scrim(_src):
    """A soft, warm, very dark oval: full in its middle, feathered to nothing on every side (no edge anywhere)."""
    w, h = 256, 128
    canvas = blank(w, h)
    ix, iy = 0.30, 0.30          # the solid middle reaches this far in from each side (as a share of the size)
    for y in range(h):
        v = (y + 0.5) / h
        dy = max(0.0, abs(v - 0.5) - (0.5 - iy)) / iy
        for x in range(w):
            u = (x + 0.5) / w
            dx = max(0.0, abs(u - 0.5) - (0.5 - ix)) / ix
            d = min(1.0, math.hypot(dx, dy))
            a = (1 - smooth(d)) ** 1.2
            canvas[y][x * 4:x * 4 + 4] = bytes((16, 11, 8, int(255 * a)))
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


# Stage 3A, the Fishing Journal. Each is the pack's own painting, resampled onto a power-of-two canvas and otherwise untouched
# (the pack's frames are nine-slice sources: the Journal cuts them with texture coordinates, a 24 px corner on the frames and a
# 10-12 px cap on the rows and buttons; Hud.lua ART lists the painted sizes).
JOURNAL_FILES = (
    ("j-frame", "journal_frame.png"), ("j-recess", "recessed_frame.png"), ("j-chest", "chestnut_frame.png"),
    ("j-row", "row_normal.png"), ("j-row-hover", "row_hover.png"), ("j-row-on", "row_selected.png"),
    ("j-nav-on", "button_gold.png"), ("j-nav", "button_dark.png"), ("j-btn", "button_compact.png"),
    ("j-close", "close.png"), ("j-unknown", "collection_unknown.png"), ("j-mark", "fish_watermark.png"),
)
JOURNAL_GLYPHS = (("glyph-hook", "hook.png"), ("glyph-clam", "clam.png"), ("glyph-treasure", "treasure.png"))


def JOURNAL(src):
    out = []
    for name, file in JOURNAL_FILES:
        w, h, px, _ = read_png(os.path.join(src, file))
        out.append((name, (lambda w=w, h=h, px=px: fit(px, (0, 0, w, h), w, h) + ({},))))
    for name, file in JOURNAL_GLYPHS:
        out.append((name, (lambda file=file: glyph(src, file))))
    return out


def builds(src):
    return JOURNAL(src) + [
        ("castbar", lambda: castbar(src)),
        ("castfill", lambda: castfill(src)),
        ("castspark", lambda: castspark(src)),
        ("toast", lambda: toast(src, "toast", "catch_toast_fish_reference.png")),
        ("toast-treasure", lambda: toast(src, "toast-treasure", "catch_toast_pearl_reference.png")),
        ("glint", lambda: plain(src, "glint.png", 128, 61)),
        ("mark", lambda: plain(src, "mini_icon.png", 63, 64)),
        ("logo", lambda: logo(src)),
        ("iconframe", lambda: iconframe(src)),
        ("rule", lambda: plain(src, "divider_upper.png", 256, 30)),
        ("glyph-lure", lambda: glyph(src, "lure.png")),
        ("glyph-time", lambda: glyph(src, "bobber.png")),
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
    ap.add_argument("--core", default=os.path.join(root, "!!!TwichUI", "media", "fishing"))
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
    # the settings icon lives in the core, beside the camping and guild icons
    os.makedirs(args.core, exist_ok=True)
    for name, side, pad in (("settings", 64, 3), ("settings-small", 32, 1)):
        canvas, _, _ = icon(args.src, side, pad)
        write_tga(os.path.join(args.core, name + ".tga"), canvas)
    if args.sheet:
        contact_sheet(args.sheet, built)


if __name__ == "__main__":
    main()
