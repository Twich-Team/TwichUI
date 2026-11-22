#!/usr/bin/env python3
"""Draws offline captures of TwichUI Fishing's Journal (Stage 3A) in the simulated client.

tests/journal_capture.lua runs TwichUI_Fishing's real Journal over seeded records and writes every visible texture and font
string with its resolved place on a 1366 x 768 screen; this draws that record with the real textures (TwichUI_Fishing/media)
and fonts, like tools/render_fishing_hud.py, over a dim painted scene (the game's world is not available here).

What it is not: the game's renderer. Text metrics, filtering and blending differ in the client, the item icons are the texture
pack's illustrative stand-ins (assets/fishing/standins), and the records are invented for the picture. A capture is a layout
and legibility review ("screenshot-reviewed", offline), never evidence from the real client.

    python3 tools/render_fishing_journal.py [--out test-output/journal-captures] [--pages overview,sessions,...] [--scale 2]
"""
import argparse
import json
import os
import subprocess
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_fishing_hud as hud  # noqa: E402

ROOT = hud.ROOT
PAGES = ["overview", "sessions", "collections", "locations", "treasures", "summary", "empty"]


def capture(page, path, select=""):
    cmd = ["lua5.1", "-e", 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"', "journal_capture.lua", path, page, select]
    res = subprocess.run(cmd, cwd=os.path.join(ROOT, "tests"), capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write(res.stdout + res.stderr)
        raise SystemExit("capture failed for %s" % page)
    with open(path) as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "test-output", "journal-captures"))
    ap.add_argument("--pages", default=",".join(PAGES))
    ap.add_argument("--scale", type=int, default=2)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for page in args.pages.split(","):
        data = capture(page, os.path.join(args.out, page + ".json"))
        img = hud.render(data, "dark", args.scale).convert("RGB")
        s = args.scale
        # the window (780 x 540 at the screen's middle, the summary 420 x 500 above it) with a margin
        box = (230, 100, 1136, 668) if page != "summary" else (440, 40, 926, 640)
        img = img.crop((box[0] * s, box[1] * s, box[2] * s, box[3] * s))
        path = os.path.join(args.out, "journal-%s.png" % page)
        img.save(path, optimize=True)
        print("%s: %d regions, wrote %s" % (page, len(data["regions"]), path))


if __name__ == "__main__":
    main()
