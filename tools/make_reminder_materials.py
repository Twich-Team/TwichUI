#!/usr/bin/env python3
"""Scoped Reminders materials derived from the existing leather, never the approved mockup.

Remove broad wrinkles with a periodic high-pass, reduce to a fine 128px tile, and bound its contrast.
Reuse the established 32px rounded sheet geometry for shallow edges. Standard library only.
"""
import math
import struct
import argparse
from pathlib import Path

import make_style_v2_art as art
from make_settings_icons import write_tga

ROOT = Path(__file__).resolve().parent.parent
ROLES = {
    "outer": ((29, 24, 20), 1.0), "header": ((24, 20, 17), 0.80),
    "editor": ((35, 29, 24), 1.10), "card": ((48, 37, 29), 1.55),
    "recess": ((18, 16, 14), 0.35), "button": ((40, 32, 25), 0.65),
    "selected": ((66, 49, 29), 0.75), "primary": ((116, 80, 33), 0.80),
    "viewport": ((20, 21, 21), 0.45), "chip": ((43, 39, 33), 0.45),
}


def fine_grain():
    data = (ROOT / "!!!TwichUI/media/style-v2/dark.tga").read_bytes()
    w, h = struct.unpack_from("<HH", data, 12)
    if data[2] != 2 or data[16] != 32 or w != h:
        raise ValueError("Expected the existing square 32-bit uncompressed leather TGA")
    values = [[sum(data[18 + 4 * (y * w + x):21 + 4 * (y * w + x)]) / 3 for x in range(w)] for y in range(h)]
    # Remove medium and broad features before reducing frequency to the runtime tile.
    radius = 5
    horizontal = [[sum(row[(x + k) % w] for k in range(-radius, radius + 1)) / 11 for x in range(w)] for row in values]
    residual = [[values[y][x] - sum(horizontal[(y + k) % h][x] for k in range(-radius, radius + 1)) / 11 for x in range(w)] for y in range(h)]
    side = 128
    step = w // side
    small = [[sum(residual[y * step + j][x * step + i] for i in range(step) for j in range(step)) / step ** 2
              for x in range(side)] for y in range(side)]
    sigma = math.sqrt(sum(v * v for row in small for v in row) / side ** 2) or 1
    return [[max(-2.2, min(2.2, v / sigma)) for v in row] for row in small]


def rim_sheet(frame):
    """Transparent 64px nine-slice edging; existing fills/grain stay visible underneath.

    A narrow metal crest between dark edge cuts, followed by a shallow inner recess.
    Corners use the same 3/8 slicing ratio as the existing controls.
    """
    side, radius, rows = 64, 20, []
    for y in range(side):
        row = bytearray()
        for x in range(side):
            acc, coverage = [0.0, 0.0, 0.0], 0.0
            for j in range(4):
                for i in range(4):
                    px, py = x + (i + .5) / 4, y + (j + .5) / 4
                    qx, qy = abs(px - 32) - (32 - radius), abs(py - 32) - (32 - radius)
                    distance = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius
                    d = -distance
                    limit = 12 if frame else 9
                    if d < 0 or d >= limit:
                        continue
                    light = max(0, min(1, (64 - px - py) / 40 + .5))
                    if d < 1:
                        color, alpha = (13, 10, 8), 1
                    elif d < (3 if frame else 4):
                        color, alpha = tuple(a + (b - a) * light for a, b in zip((64, 49, 33), (112, 91, 61))), 1
                    elif d < (6 if frame else 6):
                        color, alpha = (55, 42, 29), 1
                    elif d < (8 if frame else 7):
                        color, alpha = (11, 9, 7), .9
                    else:
                        color, alpha = (10, 8, 6), .5 * (limit - d) / (limit - (8 if frame else 7))
                    coverage += alpha
                    for c in range(3):
                        acc[c] += color[c] * alpha
            color = [round(v / coverage) for v in acc] if coverage else [55, 42, 29]
            row.extend((*color, round(255 * coverage / 16)))
        rows.append(row)
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rims-only", action="store_true", help="Preserve all existing grain and face files")
    args = parser.parse_args()
    out = ROOT / "!!!TwichUI/media/reminders/materials"
    preview = ROOT / "test-output/reminder-materials"
    out.mkdir(exist_ok=True)
    preview.mkdir(parents=True, exist_ok=True)
    for kind in ("control", "frame"):
        rows = rim_sheet(kind == "frame")
        write_tga(str(out / (kind + "-rim.tga")), rows, 64)
        art.write_png_rgba(str(preview / (kind + "-rim.png")), 64, 64, rows)
    if args.rims_only:
        return
    grain = fine_grain()
    for role, (fill, strength) in ROLES.items():
        rows = [bytearray(value for v in row for value in (*[max(0, min(255, round(c + v * strength))) for c in fill], 255)) for row in grain]
        write_tga(str(out / ("grain-" + role + ".tga")), rows, 128)
        art.write_png_rgba(str(preview / ("grain-" + role + ".png")), 128, 128, rows)
        spec = dict(art.ROUND["raised"])
        spec.update(fill=tuple(c / 255 for c in fill), line=(0.38, 0.30, 0.20, 0.48),
                    hi=(0.55, 0.43, 0.28, 0.19), lo=(0.015, 0.012, 0.009, 0.65))
        if role in ("outer", "header", "editor", "recess", "viewport"):
            spec.update(hi=None, shadow=(0.01, 0.008, 0.006, 0.30), line=(0.30, 0.24, 0.17, 0.36))
        if role == "primary":
            spec.update(line=(0.67, 0.50, 0.26, 0.78), hi=(0.81, 0.65, 0.37, 0.38))
        art.ROUND[role] = spec
        sheet = art.round_sheet(role)
        write_tga(str(out / ("face-" + role + ".tga")), sheet, 32)
        art.write_png_rgba(str(preview / ("face-" + role + ".png")), 32, 32, sheet)
        sigma = math.sqrt(sum((row[i] - fill[0]) ** 2 for row in rows for i in range(0, len(row), 4)) / 128 ** 2)
        print(role, "RGB", fill, "grain deviation", round(sigma, 2))


if __name__ == "__main__":
    main()
