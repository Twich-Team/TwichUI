#!/usr/bin/env python3
"""Crop actual Reminders captures for manual component comparison; no image synthesis.

Columns are approved reference, baseline, current. Reference crops alone are resized
to the current component width, keeping aspect ratio; simulator crops stay native size.
Requires only the repository's existing PNG reader/writer (standard library).
"""
import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from make_map_tool_icons import read_png
from make_style_v2_art import write_png_rgba

# Coordinates are recorded as evidence, not inferred similarity scores.
COMPONENTS = {
    "home-shell-header": ("editorTall", (326, 249, 1262, 316), "SETTINGS_HOME.png", (4, 4, 1440, 100)),
    "home-frame-corner": ("editorTall", (326, 249, 363, 286), "SETTINGS_HOME.png", (5, 3, 62, 60)),
    "selected-reminder-row": ("editorTall", (586, 442, 774, 511), "SETTINGS_HOME.png", (32, 111, 316, 176)),
    "selected-builder-row": ("when", (198, 275, 436, 319), "SETTINGS_HOME.png", (32, 111, 316, 176)),
    "primary-button": ("dirty", (1283, 941, 1401, 981), "REMINDERS_WHEN_BUILDER.png", (1400, 883, 1527, 924)),
    "secondary-button": ("dirty", (1165, 941, 1275, 981), "REMINDERS_WHEN_BUILDER.png", (1262, 883, 1390, 924)),
    "slider-numeric": ("editorTall", (946, 666, 1203, 697), "REMINDERS_PREVIEW.PNG", (781, 484, 1138, 539)),
    "when-header-frame": ("when", (490, 200, 1423, 300), "REMINDERS_WHEN_BUILDER.png", (415, 33, 1558, 138)),
    "when-condition-card": ("when", (764, 342, 1375, 440), "REMINDERS_WHEN_BUILDER.png", (731, 187, 1528, 296)),
    "when-location-controls": ("when", (764, 488, 1375, 620), "REMINDERS_WHEN_BUILDER.png", (732, 352, 1528, 506)),
    "when-status-footer": ("dirty", (500, 816, 1414, 990), "REMINDERS_WHEN_BUILDER.png", (422, 740, 1552, 935)),
    "editor-header-frame": ("editorTall", (326, 249, 1262, 392), "REMINDERS_PREVIEW.PNG", (20, 25, 1185, 186)),
    "editor-appearance-controls": ("editorTall", (805, 459, 1222, 714), "REMINDERS_PREVIEW.PNG", (587, 254, 1145, 551)),
    "editor-status-footer": ("editorTall", (805, 721, 1222, 970), "REMINDERS_PREVIEW.PNG", (587, 550, 1145, 893)),
    "preview-header-frame": ("editorTall", (1270, 249, 1587, 327), "REMINDERS_PREVIEW.PNG", (1202, 26, 1568, 120)),
    "preview-controls-status": ("editorTall", (1282, 868, 1577, 1060), "REMINDERS_PREVIEW.PNG", (1223, 588, 1548, 921)),
    # The approved render shows the closed targeting control, not an expanded menu.
    "when-expanded-dropdown": ("menu", (1174, 244, 1407, 370), "REMINDERS_WHEN_BUILDER.png", (1310, 84, 1542, 125)),
}


def crop(image, box):
    w, h, pixels, _ = image
    x, y, right, bottom = box
    if not (0 <= x < right <= w and 0 <= y < bottom <= h):
        raise ValueError((w, h, box))
    return right - x, bottom - y, [row[x * 4:right * 4] for row in pixels[y:bottom]]


def resize(image, width):
    w, h, pixels = image
    height = round(h * width / w)
    # Nearest-neighbour only for comparison; never touches runtime artwork.
    return width, height, [bytearray(v for x in range(width)
        for v in pixels[min(h - 1, y * h // height)][(x * w // width) * 4:(x * w // width) * 4 + 4])
        for y in range(height)]


def save(path, image):
    write_png_rgba(str(path), *image)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("current", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--capture", action="append", default=[], metavar="POSE=PNG",
                        help="Explicit pose recapture; recorded in crops.json")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    overrides = {pose: Path(path) for pose, path in (value.split("=", 1) for value in args.capture)}
    cache, manifest = {}, {}
    def load(path):
        if path not in cache:
            cache[path] = read_png(str(path))
        return cache[path]
    for name, (pose, actual_box, reference, reference_box) in COMPONENTS.items():
        before = args.baseline / (pose + ".png")
        after = overrides.get(pose, args.current / (pose + ".png"))
        ref = ROOT / "docs/reminders-revision" / reference
        if not after.exists():
            continue
        images = [crop(load(ref), reference_box)]
        labels = ["reference"]
        if before.exists():
            images.append(crop(load(before), actual_box))
            labels.append("before")
        images.append(crop(load(after), actual_box))
        labels.append("after")
        width = images[-1][0]
        images[0] = resize(images[0], width)
        for label, image in zip(labels, images):
            save(args.output / (name + "-" + label + ".png"), image)
        gap, height = 12, max(image[1] for image in images)
        rows = [bytearray((22, 20, 18, 255) * (len(images) * width + (len(images) - 1) * gap)) for _ in range(height)]
        for col, (_, _, pixels) in enumerate(images):
            for y, row in enumerate(pixels):
                start = col * (width + gap) * 4
                rows[y][start:start + width * 4] = row
        save(args.output / (name + "-comparison.png"), (len(images) * width + (len(images) - 1) * gap, height, rows))
        manifest[name] = {"columns": labels, "pose": pose, "reference": str(ref),
            "baseline": str(before), "current": str(after), "reference_box": reference_box, "actual_box": actual_box}
    # The catalog reference is a JPEG; keep it intact rather than adding a decoder dependency.
    for name, box in {"header-frame": (1084, 249, 1587, 373), "illustrated-card": (1100, 380, 1321, 578),
                      "footer-controls": (1098, 854, 1576, 942)}.items():
        for label, directory in (("before", args.baseline), ("after", args.current)):
            path = directory / "catalog.png"
            if path.exists():
                save(args.output / ("catalog-" + name + "-" + label + ".png"), crop(load(path), box))
    for kind in ("control", "frame"):
        path = ROOT / "!!!TwichUI/media/reminders/materials" / (kind + "-rim.tga")
        data = path.read_bytes()
        w, h = struct.unpack_from("<HH", data, 12)
        alpha = data[21::4]
        manifest[kind + "-rim"] = {"path": str(path), "format": "32-bit uncompressed TGA", "dimensions": [w, h],
            "transparent": sum(a == 0 for a in alpha), "partial": sum(0 < a < 255 for a in alpha), "opaque": sum(a == 255 for a in alpha)}
    (args.output / "crops.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
