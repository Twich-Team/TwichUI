#!/usr/bin/env python3
"""Prepare original painted frame/button/selection sources for opt-in settings components.

Uses the established PNG reader, premultiplied resampler, colour bleed and straight-alpha TGA writer.
The large-area leather is kept quiet; painted edge relief is retained. No reference screenshot is an input.
"""
import json
import math
from pathlib import Path

from make_map_tool_icons import read_png, content_box, resample
from make_settings_icons import bleed, write_tga
from make_style_v2_art import write_png_rgba

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "!!!TwichUI/media/style-v2/craft"
PREVIEW = ROOT / "test-output/craft-components"
STATES = {
    "button": ((40, 32, 25), 0.78, 1.0),
    "button-hot": ((47, 37, 28), 0.96, 1.0),
    "button-down": ((28, 24, 20), 0.70, -1.0),
    "button-off": ((27, 25, 22), 0.43, 0.4),
    "primary": ((108, 77, 35), 1.10, 1.0),
    "primary-hot": ((119, 86, 41), 1.20, 1.0),
    "primary-down": ((57, 43, 27), 0.86, -1.0),
    "danger": ((48, 28, 27), 0.68, 1.0),
    "danger-hot": ((59, 32, 29), 0.84, 1.0),
    "danger-down": ((35, 22, 21), 0.62, -1.0),
    "field": ((18, 16, 14), 0.63, -0.5),
    "field-hot": ((21, 18, 15), 0.90, -0.5),
    "field-off": ((19, 18, 16), 0.34, -0.4),
    "selection": ((74, 52, 29), 1.06, 1.0),
    "selection-hot": ((81, 59, 34), 1.16, 1.0),
    "segment": ((37, 30, 24), 0.61, 1.0),
    "segment-hot": ((44, 35, 26), 0.80, 1.0),
    "segment-down": ((27, 23, 19), 0.58, -1.0),
    "segment-off": ((26, 24, 21), 0.38, 0.4),
}


def source(name):
    path = ROOT / ("assets/craft-" + name + "-source.png")
    w, h, rows, alpha = read_png(str(path))
    clear = sum(r[i] == 0 for r in rows for i in range(3, len(r), 4))
    if not alpha or not clear:
        raise ValueError(str(path) + ": actual transparency required")
    box = content_box(w, h, rows)
    print(name, "source", w, h, "clear", clear, "bounds", box)
    return rows, box


def skin(rows, target, edge_gain, relief, contrast=.33, light=2):
    """Compress broad grain/colour variation while retaining the artist's sculpted edge.

    All button states retain the original alpha silhouette. Pressed states reverse the
    lip's illumination and darken the upper recess, rather than only tinting the fill.
    """
    w, h = len(rows[0]) // 4, len(rows)
    values = [sum(r[x:x + 3]) / 3 for r in rows[h // 3:2 * h // 3] for x in range(w, 3 * w, 4)]
    mean = sum(values) / len(values)
    limit = 14 if contrast > .33 else 8
    result = []
    for y, original in enumerate(rows):
        row = bytearray(original)
        for x in range(w):
            o = 4 * x
            rgb, alpha = original[o:o + 3], original[o + 3]
            if not alpha:
                continue
            depth = min(x, w - 1 - x, y, h - 1 - y)
            # The generated bevel occupies the outer 6px at 64px source height.
            mix = max(0, min(1, (9 - depth) / 4))
            luminance = .3 * rgb[0] + .55 * rgb[1] + .15 * rgb[2]
            grain = max(-limit, min(limit, (sum(rgb) / 3 - mean) * contrast))
            broad = relief * light * (1 - 2 * y / max(1, h - 1))
            center = [v + grain + broad for v in target]
            metal = [luminance * k * edge_gain for k in (1.05, .87, .62)]
            if relief < 0:
                shift = (y / (h - 1) - .5) * 18
                metal = [v + shift for v in metal]
            for c in range(3):
                row[o + c] = round(max(0, min(255, center[c] * (1 - mix) + metal[c] * mix)))
        result.append(row)
    return result


def hollow(rows, depth=9):
    w, h = len(rows[0]) // 4, len(rows)
    out = [bytearray(row) for row in rows]
    for y, row in enumerate(out):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            fade = max(0, min(1, depth - d))
            row[4 * x + 3] = round(row[4 * x + 3] * fade)
    return out


def capsule(rows):
    """Wrap the painted bronze cross-section around a chip's existing capsule silhouette."""
    out = []
    for y in range(32):
        row = bytearray()
        for x in range(64):
            covered = 0
            for dy in (.125, .375, .625, .875):
                for dx in (.125, .375, .625, .875):
                    across = max(0, abs(x + dx - 32) - 16)
                    covered += math.hypot(across, y + dy - 16) <= 15.5
            depth = 15.5 - math.hypot(max(0, abs(x + .5 - 32) - 16), y + .5 - 16)
            sx = min(223, 32 + x * 3)
            sy = min(8, max(0, round(depth * 2))) if depth < 4 else 16 + y
            rgb = rows[sy][sx * 4:sx * 4 + 3]
            row.extend((*rgb, round(253 * covered / 16)))
        out.append(row)
    return out


def sample_nine(rows, w, h, cx=16, cy=16, corner=8):
    """Native-size proof, using the same UV splits as SettingsCraft.Sheet."""
    sw, sh = len(rows[0]) // 4, len(rows)
    def axis(pos, size, source_size, cut):
        if pos < corner:
            return min(cut - 1, int(pos * cut / corner))
        if pos >= size - corner:
            return source_size - cut + min(cut - 1, int((pos - size + corner) * cut / corner))
        return cut + min(source_size - 2 * cut - 1, int((pos - corner) * (source_size - 2 * cut) / max(1, size - 2 * corner)))
    return [bytearray(v for x in range(w) for v in rows[axis(y, h, sh, cy)][4 * axis(x, w, sw, cx):4 * axis(x, w, sw, cx) + 4]) for y in range(h)]


def save(name, rows):
    w, h = len(rows[0]) // 4, len(rows)
    # Existing writer is square; non-square TGA uses the equivalent established writer.
    if w == h:
        bleed(rows, w)
        write_tga(str(OUT / (name + ".tga")), rows, w)
    else:
        from make_style_v2_art import write_tga_rgba
        # Colour bleed for rectangular sheets, preserving every alpha value.
        original = [bytearray(row) for row in rows]
        for y, row in enumerate(rows):
            for x in range(w):
                if row[4 * x + 3]:
                    continue
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < w and 0 <= yy < h and original[yy][4 * xx + 3]:
                        row[4 * x:4 * x + 3] = original[yy][4 * xx:4 * xx + 3]
                        break
        write_tga_rgba(str(OUT / (name + ".tga")), rows)
    write_png_rgba(str(PREVIEW / (name + ".png")), w, h, rows)
    a = [v for row in rows for v in row[3::4]]
    return {"size": [w, h], "alpha_clear": a.count(0), "alpha_partial": sum(0 < v < 255 for v in a), "alpha_opaque": a.count(255)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEW.mkdir(parents=True, exist_ok=True)
    manifest = {}
    raw, box = source("frame")
    # Alpha, including the empty center, comes from the original painted frame.
    frame = resample(raw, box, 256, 256)
    for row in frame:
        for x in range(0, len(row), 4):
            for c, k in enumerate((.86, .82, .76)):
                row[x + c] = round(row[x + c] * k)
    manifest["frame"] = save("frame", frame)
    raw, box = source("button")
    button = resample(raw, box, 256, 64)
    raw, box = source("selection")
    selection = resample(raw, box, 256, 64)
    states = {}
    for name, (target, gain, relief) in STATES.items():
        selected = name.startswith(("selection", "segment"))
        emphasis = name.startswith(("selection", "primary"))
        rows = skin(selection if selected else button, target, gain, relief,
                    contrast=.55 if emphasis else .33, light=5 if emphasis else 2)
        states[name] = rows
        manifest[name] = save(name, rows)
        proof = sample_nine(rows, 200 if selected else 112, 38,
                            cx=32 if selected else 16, cy=24 if selected else 16)
        write_png_rgba(str(PREVIEW / (name + "-actual.png")), len(proof[0]) // 4, len(proof), proof)
    for name, parent in (("card-rim", "button"), ("inset-rim", "field"), ("hover-rim", "button-hot")):
        manifest[name] = save(name, hollow(states[parent]))
    for suffix, target, gain, relief in (("", (43, 39, 33), .66, 1), ("-hot", (50, 45, 36), .92, 1),
            ("-down", (31, 28, 24), .58, -1), ("-off", (28, 26, 23), .38, .4)):
        manifest["chip" + suffix] = save("chip" + suffix, capsule(skin(selection, target, gain, relief)))
    # Native slider thumb: a compact physical handle assembled from the same painted button corners.
    thumb = sample_nine(states["primary"], 32, 32, corner=12)
    manifest["slider-thumb"] = save("slider-thumb", thumb)
    (PREVIEW / "assets.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Prepared", len(manifest), "runtime TGAs at", OUT)


if __name__ == "__main__":
    main()
