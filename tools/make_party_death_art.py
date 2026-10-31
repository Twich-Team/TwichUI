#!/usr/bin/env python3
"""Builds the party member fallen card's tombstone (media/partydeath/tombstone.tga) from
assets/party-death-tombstone-source.png.

Standard library only, and the same cutting as tools/make_vendor_warning_art.py (one painting on real transparency,
haze cleared, aspect ratio kept, colour carried into the clear pixels). One size: 128 px, drawn by modules/PartyDeath.lua
at 64 UI units, so it stays sharp on a scaled interface.

    python3 tools/make_party_death_art.py [--src assets/party-death-tombstone-source.png] [--out '!!!TwichUI/media/partydeath']
                                          [--check]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_settings_icons as SI  # noqa: E402
from make_vendor_warning_art import cut  # noqa: E402

NAME = "tombstone"
SIDE, FILL = 128, 120     # canvas side, content's longer side


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets", "party-death-tombstone-source.png"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "partydeath"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    (w, h), box, rows, c, specks = cut(args.src)
    cw, ch = c[2] - c[0], c[3] - c[1]
    print("source %dx%d, painting at %s, %d solid specks cleared with the haze" % (w, h, box, specks))
    canvas, (ow, oh) = SI.place(rows, c, FILL / float(max(cw, ch)), SIDE)
    print("%3d px: content %dx%d" % (SIDE, ow, oh))
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
        SI.write_tga(os.path.join(args.out, NAME + ".tga"), canvas, SIDE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
