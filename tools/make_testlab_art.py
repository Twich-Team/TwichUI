#!/usr/bin/env python3
"""Cuts the Test Lab's seven summary-card icons into TwichUI_TestLab/media/summary/*.tga, standard library only.

Sources: docs/test-lab/ChatGPT Image Nov 12, 2026, ... .png (1254 x 1254, 8-bit RGBA, genuine transparency: alpha is 0 around the
artwork and about 253 inside it). They stay where they are. The cut follows the repo's other art tools (make_guild_locations_art.py,
make_settings_icons.clean_icon): solid parts only, specks and the faint haze around some edges dropped, the antialiased edge kept, colour
bled into clear pixels. Nothing is keyed out by colour, so no background is baked in. One extra step: alpha of 248 or more becomes 255
(the generator left the inside at 253, which would let the card show through the art by one percent).

All seven share ONE scale (the largest artwork's longer side fits FIT of SIDE), so the frames keep their real proportions to each other,
like the guild badges: they are one family. Each is centred in a SIDE x SIDE canvas by its own content box. The cards draw them at 28.

  card       source file stamp   output
  total      01_19_03 PM-1       total.tga      parchment checklist
  passed     01_21_04 PM         passed.tga     bronze medallion, green check
  failed     01_21_12 PM         failed.tga     bronze shield, red X
  skipped    01_21_49 PM         skipped.tga    skip symbol
  errors     01_22_02 PM         errors.tga     shield with exclamation mark
  timeouts   01_22_15 PM         timeouts.tga   hourglass
  duration   01_22_25 PM         duration.tga   pocket watch

    python3 tools/make_testlab_art.py [--src docs/test-lab] [--out TwichUI_TestLab/media/summary] [--check] [--contact-sheet PATH]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_guild_locations_art as GL  # noqa: E402
import make_settings_icons as SI  # noqa: E402

SIDE, FIT = 64, 62
ART = [   # (name, source file name)
    ("total", "ChatGPT Image Nov 12, 2026, 01_19_03 PM-1.png"),
    ("passed", "ChatGPT Image Nov 12, 2026, 01_21_04 PM.png"),
    ("failed", "ChatGPT Image Nov 12, 2026, 01_21_12 PM.png"),
    ("skipped", "ChatGPT Image Nov 12, 2026, 01_21_49 PM.png"),
    ("errors", "ChatGPT Image Nov 12, 2026, 01_22_02 PM.png"),
    ("timeouts", "ChatGPT Image Nov 12, 2026, 01_22_15 PM.png"),
    ("duration", "ChatGPT Image Nov 12, 2026, 01_22_25 PM.png"),
]
SOLID = 248


def solidify(rows):
    for row in rows:
        for i in range(3, len(row), 4):
            if row[i] >= SOLID:
                row[i] = 255


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "docs", "test-lab"))
    ap.add_argument("--out", default=os.path.join(root, "TwichUI_TestLab", "media", "summary"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--contact-sheet")
    args = ap.parse_args()
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    cut = []
    for name, fname in ART:
        w, h, pixels, alpha, lab, parts = GL.load(os.path.join(args.src, fname))
        if not parts:
            raise SystemExit("%s: no artwork found" % fname)
        rows, cbox, box, holes = GL.clean(pixels, alpha, lab, parts)
        solidify(rows)
        cut.append((name, rows, cbox, len(parts)))
    longest = max(max(c[2][2] - c[2][0], c[2][3] - c[2][1]) for c in cut)
    built = []
    for name, rows, cbox, n in cut:
        canvas, (ow, oh) = SI.place(rows, cbox, FIT / float(longest), SIDE)
        built.append((name, {SIDE: canvas, 32: SI.resample(canvas, (0, 0, SIDE, SIDE), 32, 32)}))   # 32 only for the contact sheet
        print("%-9s %d part(s), content %dx%d -> %dx%d in %dx%d" % (name, n, cbox[2] - cbox[0], cbox[3] - cbox[1], ow, oh, SIDE, SIDE))
        if not args.check:
            SI.write_tga(os.path.join(args.out, name + ".tga"), canvas, SIDE)
    if args.contact_sheet:
        SI.contact_sheet(args.contact_sheet, built)
        print("contact sheet:", args.contact_sheet)


if __name__ == "__main__":
    main()
