#!/usr/bin/env python3
"""Build original AH subcategory paintings into transparent 64/32px TGAs.

Sources and filter contracts: assets/auction-subcategories/manifest.json. Each
source is a regular grid; cells are isolated before the existing shape-based
alpha cleaning and premultiplied resampling helpers run. Originals are untouched.

    python3 tools/make_auction_category_art.py [--out DIR] [--contact-sheet PNG]
    python3 tools/make_auction_category_art.py --write-mapping
"""
import argparse
import json
from pathlib import Path

from make_map_tool_icons import read_png
from make_layout_wizard_art import fit
import make_settings_icons as SI

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/auction-subcategories"
BEGIN = "-- BEGIN GENERATED SUBCATEGORY ART (tools/make_auction_category_art.py)"
END = "-- END GENERATED SUBCATEGORY ART"


def mapping(manifest):
    lines = [BEGIN, "local SUBCATEGORY_ART = {"]
    for icon in manifest["icons"]:
        if "class" not in icon:
            continue
        key = "%d:%d" % (icon["class"], icon["subclass"])
        if "inventory" in icon:
            key += ":%d" % icon["inventory"]
        lines.append('    ["%s"] = "%s",' % (key, icon["id"]))
    lines += ["}", "local GROUP_ART = {"]
    for icon in manifest["icons"]:
        if "filters" in icon:
            signature = ",".join(sorted({"%d:%d" % (f["classID"], f["subClassID"]) for f in icon["filters"]}))
            lines.append('    ["%s"] = "%s",' % (signature, icon["id"]))
    for signature, name in manifest["aliases"].items():
        lines.append('    ["%s"] = "%s",' % (signature, name))
    return "\n".join(lines + ["}", END])


def cell(sheet, grid, index):
    w, h, pixels = sheet
    col, row = index % grid["columns"], index // grid["columns"]
    x0, x1 = col * w // grid["columns"], (col + 1) * w // grid["columns"]
    y0, y1 = row * h // grid["rows"], (row + 1) * h // grid["rows"]
    # Padding lets the shared cleaner retain soft edges even at a cell boundary.
    pad = 12
    cw, ch = x1 - x0 + 2 * pad, y1 - y0 + 2 * pad
    rows = [bytearray(cw * 4) for _ in range(ch)]
    for y in range(y0, y1):
        rows[y - y0 + pad][pad * 4:(cw - pad) * 4] = pixels[y][x0 * 4:x1 * 4]
    alpha = [[r[x * 4 + 3] for x in range(cw)] for r in rows]
    labels, parts = SI.solid_parts(cw, ch, alpha)
    largest = max((p[1] for p in parts), default=0)
    parts = [p for p in parts if p[1] >= max(24, largest * 0.002)]
    if not parts:
        raise ValueError("empty source cell %d" % index)
    box = (min(p[4][0] for p in parts), min(p[4][1] for p in parts),
           max(p[4][2] for p in parts), max(p[4][3] for p in parts))
    clean, _, _ = SI.clean_icon(rows, alpha, labels, {p[0] for p in parts}, box)
    bounds, area = SI.content_and_area(clean, len(clean[0]) // 4, len(clean))
    if area < 100:
        raise ValueError("source cell has insufficient artwork")
    return clean, bounds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "!!!TwichUI/media/auction/categories")
    parser.add_argument("--contact-sheet", type=Path)
    parser.add_argument("--write-mapping", action="store_true")
    parser.add_argument("--only", nargs="+", help="rebuild selected manifest ids")
    args = parser.parse_args()
    manifest = json.loads((SOURCE / "manifest.json").read_text())
    sheets, built = {}, []
    if args.only and set(args.only) - {i["id"] for i in manifest["icons"]}:
        parser.error("--only contains an unknown icon id")
    args.out.mkdir(parents=True, exist_ok=True)
    for icon in manifest["icons"]:
        if args.only and icon["id"] not in args.only:
            continue
        number = str(icon["sheet"])
        grid = manifest["sheets"][number]
        if number not in sheets:
            w, h, rows, alpha = read_png(SOURCE / grid["file"])
            if not alpha:
                raise ValueError("source sheet requires real alpha")
            sheets[number] = (w, h, rows)
        pixels, bounds = cell(sheets[number], grid, icon["cell"])
        sizes = {}
        for side, suffix, margin in ((64, "", 4), (32, "-small", 2)):
            canvas, _ = fit(pixels, len(pixels[0]) // 4, len(pixels), bounds, side, side, margin)
            SI.write_tga(args.out / (icon["id"] + suffix + ".tga"), canvas, side)
            sizes[side] = canvas
        built.append((icon["id"], sizes))
        print(icon["id"], "sheet", number, "cell", icon["cell"], "bounds", bounds, flush=True)
    if args.contact_sheet:
        args.contact_sheet.parent.mkdir(parents=True, exist_ok=True)
        SI.contact_sheet(str(args.contact_sheet), built)
    if args.write_mapping:
        path = ROOT / "TwichUI_Workshop/auction/Categories.lua"
        text = path.read_text()
        start, end = text.index(BEGIN), text.index(END) + len(END)
        path.write_text(text[:start] + mapping(manifest) + text[end:])


if __name__ == "__main__":
    main()
