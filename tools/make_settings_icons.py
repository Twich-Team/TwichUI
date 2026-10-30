#!/usr/bin/env python3
"""Builds the feature icons (media/icons/*.tga) from the icon sheets in assets/ (SOURCES below; the first is the 4 x 4
sheet assets/settings-icons-source.png).

Standard library only, like the other make_*.py tools; the PNG reader and the premultiplied-alpha box filter are
tools/make_map_tool_icons.py's.

The sheet (1254 x 1254, 8-bit RGBA) already has a transparent background: no white needs removing. What it does have is
a faint haze left around most icons by however the transparency was made (red, yellow and near-black pixels at alpha
1..63, reaching across the grid lines), which would show as a smudge on a dark surface and would widen the content
bounds. It is removed by shape, never by colour:

  1. The solid artwork is alpha >= CORE. Its 8-connected parts are found over the whole sheet and each part goes to
     the icon whose grid cell holds its centre. The grid is only used for that assignment: the bounds come from the
     parts themselves (row 1 reaches below the cell line, for example), so nothing is clipped and no neighbour leaks in.
  2. A pixel below CORE is kept only within EDGE pixels of its icon's solid artwork (its antialiased edge), and its
     colour is taken from the nearest solid pixel, so the red or yellow haze can't tint the edge. Everything further
     out is cleared. Enclosed spaces get the same rule when they are background (mostly fully clear: the bell loop,
     the gap beside the pennant's pole, the spaces between the scale's chains, the frame corner's opening); an enclosed
     space that is painted see-through (fewer than HOLE_CLEAR of its pixels fully clear: the map pin's centre) is kept
     exactly as painted.
  3. Each icon is scaled to a square canvas with its aspect ratio kept and a clear margin, then optically balanced:
     an icon whose painted area is heavier than the set's median (shield, medallions) is shrunk part of the way towards
     the median, so a compact icon doesn't look bigger than a thin one (scales, feather). Then colour is carried a
     little way into the clear pixels so no dark matte shows when the client filters the texture.

Two sizes, because the game is not relied on to mipmap an addon texture: a 64 px texture for feature cards and the
Home page (shown at about 32..48 UI units) and a 32 px texture for navigation rows (shown at about 20..24), as the map
toolbar already does with its 32 px icons shown at 18. Nothing is recoloured, sharpened or given a glow.

    python3 tools/make_settings_icons.py [--src assets] [--out '!!!TwichUI/media/icons'] [--check]
                                         [--contact-sheet PATH]

--check builds nothing and prints each icon's source bounds, holes and planned size. --contact-sheet writes a PNG
of every icon at both sizes on a dark (settings-like) and a light surface, for inspection; it is not used in game.
"""
import argparse
import os
import struct
import sys
import zlib
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, resample  # noqa: E402

# file, columns, rows, opaque (True: no alpha channel, the white background is removed here). Sheets 1 and 2 are 4 x 4
# with real transparency; sheet 3 is two icons side by side on an opaque near-white background; sheet 4 (Reminders) is
# 3 x 2 with real transparency; sheet 5 (TwichUI Diagnostics' views) is 4 x 2 with real transparency.
SOURCES = [("settings-icons-source.png", 4, 4, False), ("settings-icons-2-source.png", 4, 4, False),
           ("settings-icons-3-source.png", 2, 1, True), ("settings-icons-4-source.png", 3, 2, False),
           ("settings-icons-5-source.png", 4, 2, False), ("settings-icons-6-source.png", 1, 1, False)]
# The sheets whose icons set the median the optical balance aims for. A sheet added later is balanced against the
# same median without moving it, so adding one never changes an icon that was already made.
MEDIAN_SHEETS = 3
COLS, ROWS = 4, 4
CORE = 128          # alpha at or above which a pixel is solid artwork
EDGE = 3            # how far (source px) the antialiased edge is kept beyond the solid artwork
HOLE_CLEAR = 0.25   # an enclosed space with at least this share of fully clear pixels is background
BALANCE = 0.6       # 0 = box fit only, 1 = equal painted area; part way keeps each icon's character

# runtime name, row-major as on the sheet; (expected solid parts)
SHEETS = [
    [
        ("home", 1), ("notifications", 1), ("qualityOfLife", 1), ("markers", 1),
        ("chatCleaning", 1), ("foodAndDrink", 1), ("hazardAlerts", 1), ("vendorRestocking", 1),
        ("auctionHouse", 1), ("journeyChronicle", 1), ("sleepingBag", 1), ("mapsNavigation", 1),
        ("gearComparison", 1), ("classResources", 3), ("addonSkins", 1), ("profilesSharing", 1),
    ],
    [
        ("targetArt", None), ("mapPins", None), ("mapToolbar", None), ("vendors", None),
        ("mage", None), ("guide", None), ("ammunition", None), ("troubleshooting", None),
        ("navigation", None), ("profiles", None), ("explore", None), ("appearance", None),
        ("reviewChanges", None), ("summons", None), ("resurrection", None), ("releaseSpirit", None),
    ],
    [("declineDuels", None), ("quickKeybind", None)],
    [
        (None, None), ("reminderShow", None), ("reminderWhen", None),   # cell 1 was the bell; Reminders is now sheet 6's scroll
        ("reminderPlacement", 5), ("reminderPreview", None), ("reminderTest", None),
    ],
    [
        ("diagOverview", None), ("diagTimeline", None), ("diagMemory", None), ("diagOperations", None),
        ("diagEvents", None), ("diagCompare", None), ("diagErrors", None), ("diagExport", None),
    ],
    [("reminders", None)],   # sheet 6: a rolled parchment scroll with a bronze ribbon
]   # expected solid parts per icon; None: not known beforehand (any number, merged into one icon)

# output: suffix, canvas side, content's longer side (the rest is clear margin)
SIZES = [("", 64, 58), ("-small", 32, 29)]

N8 = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def solid_parts(w, h, alpha):
    """8-connected parts of the solid artwork: (label grid, [(label, area, cx, cy, box)])."""
    lab = [[0] * w for _ in range(h)]
    parts = []
    n = 0
    for y in range(h):
        arow = alpha[y]
        for x in range(w):
            if arow[x] >= CORE and not lab[y][x]:
                n += 1
                q = deque([(x, y)])
                lab[y][x] = n
                area = sx = sy = 0
                x0 = x1 = x
                y0 = y1 = y
                while q:
                    cx, cy = q.popleft()
                    area += 1
                    sx += cx
                    sy += cy
                    if cx < x0: x0 = cx
                    if cx > x1: x1 = cx
                    if cy < y0: y0 = cy
                    if cy > y1: y1 = cy
                    for dx, dy in N8:
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and not lab[ny][nx] and alpha[ny][nx] >= CORE:
                            lab[ny][nx] = n
                            q.append((nx, ny))
                parts.append((n, area, sx / area, sy / area, (x0, y0, x1 + 1, y1 + 1)))
    return lab, parts


BG_MIN = 236        # a background pixel's darkest channel is at least this: the background is a checker of about 241 and 253,
                    # while the palest artwork (a blade's edge highlight) tops out near 232
BG_WHITE = 247      # what the background is taken to be when an edge pixel's coverage is worked out (between the two tones)
SPECK = 400         # a piece of artwork smaller than this (px) is texture, not artwork
BAND = 3            # how deep (px) the matte reaches into the artwork from the background


def remove_background(w, h, pixels):
    """Opaque sheet -> RGBA, in place. The background is the bright, edge-connected part (4-connected from the sheet's
    border) plus any enclosed bright space of at least 30 px (the gap in a key's bow), and nothing else, so pale
    material inside an icon (a keycap's beige, a blade's highlight) is kept: it is darker than BG_MIN or not connected
    to the outside. Edge pixels within BAND of the background are then matted against white: each takes the colour of
    the nearest artwork deeper in, and the coverage that colour over white would need to give the pixel it has. That
    removes the white halo an opaque edge carries without touching colours inside."""
    light = bytearray(w * h)
    for y in range(h):
        row = pixels[y]
        for x in range(w):
            if min(row[x * 4], row[x * 4 + 1], row[x * 4 + 2]) >= BG_MIN:
                light[y * w + x] = 1
    bg = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if light[y * w + x] and not bg[y * w + x]:
                bg[y * w + x] = 1; q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if light[y * w + x] and not bg[y * w + x]:
                bg[y * w + x] = 1; q.append((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in N4:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and light[ny * w + nx] and not bg[ny * w + nx]:
                bg[ny * w + nx] = 1; q.append((nx, ny))
    # enclosed bright spaces
    pockets = 0
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if light[i] and not bg[i]:
                comp, q = [i], deque([(x, y)])
                bg[i] = 2
                while q:
                    cx, cy = q.popleft()
                    for dx, dy in N4:
                        nx, ny = cx + dx, cy + dy
                        j = ny * w + nx
                        if 0 <= nx < w and 0 <= ny < h and light[j] and not bg[j]:
                            bg[j] = 2; comp.append(j); q.append((nx, ny))
                if len(comp) < 30:
                    for j in comp: bg[j] = 0     # a few bright pixels of artwork (a glint)
                else:
                    pockets += 1
                    for j in comp: bg[j] = 1
    # fragments of the background's texture that came out just under the threshold: small and not joined to the artwork
    specks = 0
    seen = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if bg[i] or seen[i]:
                continue
            comp, q = [i], deque([(x, y)])
            seen[i] = 1
            while q:
                cx, cy = q.popleft()
                for dx, dy in N8:
                    nx, ny = cx + dx, cy + dy
                    j = ny * w + nx
                    if 0 <= nx < w and 0 <= ny < h and not bg[j] and not seen[j]:
                        seen[j] = 1; comp.append(j); q.append((nx, ny))
            if len(comp) < SPECK:
                specks += 1
                for j in comp: bg[j] = 1
    # depth into the artwork from the background (chessboard), up to BAND
    depth = [0] * (w * h)
    q = deque()
    for i in range(w * h):
        if bg[i]:
            q.append(i)
    while q:
        i = q.popleft()
        d = depth[i]
        if d >= BAND:
            continue
        x, y = i % w, i // w
        for dx, dy in N8:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if not bg[j] and depth[j] == 0:
                    depth[j] = d + 1; q.append(j)
    # the colour behind the band: the nearest pixel deeper than BAND, found by growing inward from them
    src = {}
    q = deque()
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if not bg[i] and depth[i] == 0:
                src[i] = i
    for i in list(src):
        x, y = i % w, i // w
        for dx, dy in N8:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if depth[j] and j not in src:
                    src[j] = i; q.append(j)
    while q:
        j = q.popleft()
        x, y = j % w, j // w
        for dx, dy in N8:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                k = ny * w + nx
                if depth[k] and k not in src:
                    src[k] = src[j]; q.append(k)
    for y in range(h):
        row = pixels[y]
        for x in range(w):
            i = y * w + x
            o = x * 4
            if bg[i]:
                row[o:o + 4] = b"\x00\x00\x00\x00"
            elif depth[i] and i in src:
                f = pixels[src[i] // w][(src[i] % w) * 4:(src[i] % w) * 4 + 3]
                a = 0.0
                for c in range(3):
                    room = BG_WHITE - f[c]
                    if room >= 24:
                        a = max(a, (BG_WHITE - row[o + c]) / float(room))
                a = 1.0 if a == 0.0 and max(BG_WHITE - f[0], BG_WHITE - f[1], BG_WHITE - f[2]) < 24 else min(1.0, a)
                if a < 0.05:
                    row[o:o + 4] = b"\x00\x00\x00\x00"
                else:
                    row[o:o + 3] = bytes(f)
                    row[o + 3] = int(round(a * 255))
    return pockets, specks


def clean_icon(pixels, alpha, lab, ids, box):
    """The icon's pixels inside box (grown by EDGE + 1), with the haze cleared. Returns (rows, holes report)."""
    x0, y0 = box[0] - EDGE - 1, box[1] - EDGE - 1
    W, H = box[2] - box[0] + 2 * (EDGE + 1), box[3] - box[1] + 2 * (EDGE + 1)
    solid = [[lab[y0 + y][x0 + x] in ids for x in range(W)] for y in range(H)]

    # background reachable from the border (4-connected, so a diagonal gap in the artwork doesn't count as open)
    outside = [[False] * W for _ in range(H)]
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if not solid[y][x] and not outside[y][x]:
                outside[y][x] = True
                q.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            if not solid[y][x] and not outside[y][x]:
                outside[y][x] = True
                q.append((x, y))
    while q:
        cx, cy = q.popleft()
        for dx, dy in N4:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < W and 0 <= ny < H and not outside[ny][nx] and not solid[ny][nx]:
                outside[ny][nx] = True
                q.append((nx, ny))

    # enclosed spaces: background (cleaned like the outside) or painted see-through (kept)
    painted = [[False] * W for _ in range(H)]
    seen = [[False] * W for _ in range(H)]
    holes = []
    for y in range(H):
        for x in range(W):
            if solid[y][x] or outside[y][x] or seen[y][x]:
                continue
            pts = []
            q = deque([(x, y)])
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                pts.append((cx, cy))
                for dx, dy in N4:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and not solid[ny][nx] and not outside[ny][nx]:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            clear = sum(1 for px, py in pts if alpha[y0 + py][x0 + px] == 0)
            keep = clear < HOLE_CLEAR * len(pts)
            if keep:
                for px, py in pts:
                    painted[py][px] = True
            if len(pts) >= 12:
                holes.append((len(pts), round(clear / len(pts), 2), "kept" if keep else "background",
                              (x0 + min(p[0] for p in pts), y0 + min(p[1] for p in pts))))

    # distance (chessboard) from the solid artwork, carrying the nearest solid pixel's position for its colour
    near = [[None] * W for _ in range(H)]
    q = deque()
    for y in range(H):
        for x in range(W):
            if solid[y][x]:
                near[y][x] = (x, y, 0)
                q.append((x, y))
    while q:
        cx, cy = q.popleft()
        sx, sy, d = near[cy][cx]
        if d >= EDGE:
            continue
        for dx, dy in N8:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < W and 0 <= ny < H and near[ny][nx] is None:
                near[ny][nx] = (sx, sy, d + 1)
                q.append((nx, ny))

    rows = []
    for y in range(H):
        src = pixels[y0 + y]
        row = bytearray(W * 4)
        for x in range(W):
            sx4 = (x0 + x) * 4
            if solid[y][x] or painted[y][x]:
                row[x * 4:x * 4 + 4] = src[sx4:sx4 + 4]
            elif near[y][x] is not None:
                nx, ny, _ = near[y][x]
                n4 = (x0 + nx) * 4
                row[x * 4:x * 4 + 3] = pixels[y0 + ny][n4:n4 + 3]
                row[x * 4 + 3] = src[sx4 + 3]
        rows.append(row)
    return rows, (W, H), holes


def content_and_area(rows, W, H):
    x0, y0, x1, y1 = W, H, -1, -1
    area = 0.0
    for y in range(H):
        row = rows[y]
        for x in range(W):
            a = row[x * 4 + 3]
            if a > 8:
                area += a / 255.0
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    return (x0, y0, x1 + 1, y1 + 1), area


def bleed(canvas, side, passes=2):
    """Colour into clear pixels beside painted ones (alpha stays 0)."""
    for _ in range(passes):
        grown = [bytearray(row) for row in canvas]
        for y in range(side):
            for x in range(side):
                if canvas[y][x * 4 + 3]:
                    continue
                for dx, dy in N8:
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < side and 0 <= xx < side and canvas[yy][xx * 4 + 3]:
                        grown[y][x * 4:x * 4 + 3] = canvas[yy][xx * 4:xx * 4 + 3]
                        break
        canvas[:] = grown


def place(rows, box, scale, side):
    cw, ch = box[2] - box[0], box[3] - box[1]
    ow, oh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    body = resample(rows, box, ow, oh)
    canvas = [bytearray(side * 4) for _ in range(side)]
    left, top = (side - ow) // 2, (side - oh) // 2
    for y in range(oh):
        canvas[top + y][left * 4:(left + ow) * 4] = body[y]
    bleed(canvas, side)
    return canvas, (ow, oh)


def write_tga(path, canvas, side):
    # type 2 (uncompressed true color), 32 bpp, descriptor 8 (eight alpha bits, origin bottom-left): the repo's others
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, side, side, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(canvas):
            out = bytearray(side * 4)
            for x in range(side):
                r, g, b, a = row[x * 4:x * 4 + 4]
                out[x * 4:x * 4 + 4] = bytes((b, g, r, a))
            f.write(out)


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def contact_sheet(path, built):
    """Each icon at 64 (shown 1:1 and at 40) and 32 (shown 1:1 and at 22), on dark then light; nearest-free box scale."""
    surfaces = [(30, 26, 22), (226, 220, 206)]   # warm charcoal like the settings window; a light parchment-grey
    cell_w, cell_h = 64 + 40 + 32 + 22 + 5 * 8, 72
    W = 8 + cell_w * 4
    nrows = (len(built) + 3) // 4
    H = 8 + cell_h * nrows * len(surfaces) + 8 * len(surfaces)
    img = [bytearray(W * 3) for _ in range(H)]
    for si, bg in enumerate(surfaces):
        top0 = 8 + si * (cell_h * nrows + 8)
        for y in range(top0 - 4, top0 + cell_h * nrows - 4):
            img[y][:] = bytes(bg) * W
        for i, (name, by_size) in enumerate(built):
            cx = 8 + (i % 4) * cell_w
            cy = top0 + (i // 4) * cell_h
            x = cx
            for side, show in ((64, 64), (64, 40), (32, 32), (32, 22)):
                canvas = by_size[side]
                if show != side:
                    canvas = resample(canvas, (0, 0, side, side), show, show)
                for yy in range(show):
                    row = canvas[yy]
                    out = img[cy + yy + (64 - show) // 2]
                    for xx in range(show):
                        r, g, b, a = row[xx * 4:xx * 4 + 4]
                        al = a / 255.0
                        o = (x + xx) * 3
                        out[o:o + 3] = bytes(int(round(c * al + k * (1 - al))) for c, k in zip((r, g, b), bg))
                x += show + 8
    write_png(path, W, H, img)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "icons"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--contact-sheet")
    args = ap.parse_args()

    prepared = []
    in_median = []
    for sheet, ((source, ncols, nrows, opaque), icons) in enumerate(zip(SOURCES, SHEETS)):
        w, h, pixels, has_alpha = read_png(os.path.join(args.src, source))
        if opaque:
            if has_alpha:
                raise SystemExit("%s: listed as opaque but has an alpha channel" % source)
            print("%s: opaque; background removed (%d enclosed gap(s) and %d speck(s) cleared)" % ((source,) + remove_background(w, h, pixels)))
        elif not has_alpha:
            raise SystemExit("%s: no alpha channel (list it as opaque to have its background removed)" % source)
        alpha = [[row[x * 4 + 3] for x in range(w)] for row in pixels]
        lab, parts = solid_parts(w, h, alpha)
        cells = {}
        for p in parts:
            col, row = min(ncols - 1, int(p[2] * ncols // w)), min(nrows - 1, int(p[3] * nrows // h))
            cells.setdefault(row * ncols + col, []).append(p)
        for i, (name, expect) in enumerate(icons):
            if name is None:
                continue
            ps = cells.get(i, [])
            if not ps or (expect is not None and len(ps) != expect):
                raise SystemExit("%s: %s: expected %s solid part(s) in cell %d, found %d" % (source, name, expect or "some", i + 1, len(ps)))
            ids = {p[0] for p in ps}
            box = (min(p[4][0] for p in ps), min(p[4][1] for p in ps), max(p[4][2] for p in ps), max(p[4][3] for p in ps))
            rows, (W, H), holes = clean_icon(pixels, alpha, lab, ids, box)
            cbox, area = content_and_area(rows, W, H)
            longest = max(cbox[2] - cbox[0], cbox[3] - cbox[1])
            prepared.append((name, rows, cbox, area, longest, box, holes if expect is not None else holes))
            in_median.append(sheet < MEDIAN_SHEETS)
            if len(ps) > 1 and expect is None:
                print("note: %s is %d separate pieces (merged into one icon)" % (name, len(ps)))

    # optical balance: fill = sqrt(painted area) / longer side at box fit; heavier than the median is shrunk part way
    fills = sorted((area ** 0.5) / longest for (_, _, _, area, longest, _, _), counted in zip(prepared, in_median) if counted)
    median = fills[len(fills) // 2]

    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    built = []
    for name, rows, cbox, area, longest, box, holes in prepared:
        fill = (area ** 0.5) / longest
        balance = min(1.0, (median / fill) ** BALANCE)
        by_size = {}
        sizes = []
        for suffix, side, fit in SIZES:
            canvas, (ow, oh) = place(rows, cbox, fit / float(longest) * balance, side)
            by_size[side] = canvas
            sizes.append("%dx%d/%d" % (ow, oh, side))
            if not args.check:
                write_tga(os.path.join(args.out, name + suffix + ".tga"), canvas, side)
        built.append((name, by_size))
        print("%-17s solid %s  balance %.2f  -> %s%s" % (
            name, box, balance, "  ".join(sizes),
            "".join("\n%19shole %d px, %.0f%% clear, %s at %s" % ("", n, c * 100, kind, at) for n, c, kind, at in holes)))
    if args.contact_sheet:
        contact_sheet(args.contact_sheet, built)
        print("contact sheet:", args.contact_sheet)


if __name__ == "__main__":
    main()
