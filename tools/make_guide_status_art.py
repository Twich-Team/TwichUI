#!/usr/bin/env python3
"""Builds the guide status icons (media/guides/status-*.tga) from assets/guide-status-source.png.

Standard library only, like the other make_*.py tools: the PNG reader is tools/make_map_tool_icons.py's; the haze cleaning
(solid part, kept antialiased edge), colour bleed and TGA writer are tools/make_settings_icons.py's.

The source (2172 x 724, 8-bit RGBA) is three separate paintings on real transparency, left to right a check, a cross and
an arrow. Nothing is keyed out by colour. Each painting is cut by itself (its solid pixels and antialiased edge, the faint
haze around it cleared) and scaled into a square canvas by its longer side, so all three share one canvas and one scale,
centred, with the same clear margin. Nothing is recoloured, sharpened or given a glow.

    status-done    the check: a step or task that is done
    status-failed  the cross: an explicit failed or error state only (never merely unfinished)
    status-current the arrow: the step to do now

Two sizes (the game is not relied on to make smaller copies of an addon texture): 64 px for 27 UI units and over, and
-small, 32 px, for 26 and under.

    python3 tools/make_guide_status_art.py [--src assets/guide-status-source.png] [--out '!!!TwichUI/media/guides'] [--check]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

NAMES = ["status-done", "status-failed", "status-current"]    # left to right in the source
MIN_AREA = 20000                                              # source px: a painting, not a speck
SIZES = [("", 64, 58), ("-small", 32, 29)]                    # suffix, canvas side, content's longer side


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "guide-status-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "guides"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    w, h, pixels, has_alpha = read_png(args.src)
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % args.src)
    alpha = [[pixels[y][x * 4 + 3] for x in range(w)] for y in range(h)]
    lab, parts = SI.solid_parts(w, h, alpha)
    big = sorted((p for p in parts if p[1] >= MIN_AREA), key=lambda p: p[2])    # by centre x
    if len(big) != len(NAMES):
        raise SystemExit("%s: expected %d paintings, found %d" % (args.src, len(NAMES), len(big)))
    print("source %dx%d, %d specks cleared with the haze" % (w, h, len(parts) - len(big)))
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    for name, part in zip(NAMES, big):
        rows, (W, H), _holes = SI.clean_icon(pixels, alpha, lab, {part[0]}, part[4])
        c, _area = SI.content_and_area(rows, W, H)
        cw, ch = c[2] - c[0], c[3] - c[1]
        for suffix, side, fill in SIZES:
            canvas, (ow, oh) = SI.place(rows, c, fill / float(max(cw, ch)), side)
            print("%-14s %3d px: source %s, content %dx%d" % (name, side, part[4], ow, oh))
            if not args.check:
                SI.write_tga(os.path.join(args.out, name + suffix + ".tga"), canvas, side)
    return 0


if __name__ == "__main__":
    sys.exit(main())
