#!/usr/bin/env python3
"""Cuts Guild Locations' artwork into media/guildloc/*.tga, standard library only.

Three sources in assets/ (8-bit RGBA, real transparency with a faint haze), cleaned by shape exactly as the other art tools
do (make_settings_icons.clean_icon: solid parts, kept antialiased edge, colour bleed; nothing keyed out by colour, so the
badges' pale frames, the eye whites and the parchment keep their pixels). The sources are never changed.

  guild-locations-badges-source.png    3 x 3 class badges. Assigned by GRID POSITION (cell of each part's centre), not by
                                       discovery order: WARRIOR PALADIN HUNTER / ROGUE PRIEST SHAMAN / MAGE WARLOCK DRUID.
                                       Output class-<token>.tga (64) and class-<token>-small.tga (32, the map markers).
  guild-locations-eyes-source.png      two eyes side by side: left open ("sharing"), right slashed ("hidden"). Checked by
                                       position and by the slash's missing iris. Output eye-open / eye-hidden, 64 and -small.
  guild-locations-settings-source.png  the parchment map and pennant: settings.tga (64) and settings-small.tga (32).

All badges share one canvas and one scale (the largest badge's longer side fits), so their frames match in size and none
is balanced against another: they are one family of shields. Eyes share one scale likewise. Which file a feature wears is
guildloc code's business (later milestones); the settings page uses Icons "guildLocations".

    python3 tools/make_guild_locations_art.py [--src assets] [--out '!!!TwichUI/media/guildloc'] [--check] [--contact-sheet PATH]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png  # noqa: E402
import make_settings_icons as SI  # noqa: E402

CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]   # reading order
EYES = ["eye-open", "eye-hidden"]                                                                     # left to right
MIN_AREA = 400            # source px: a speck of haze is not artwork
BADGE_SIZES = [("", 64, 58), ("-small", 32, 29)]        # suffix, canvas side, content's longer side
EYE_SIZES = [("", 64, 60), ("-small", 32, 30)]          # eyes are wide: the width fills the canvas
SETTINGS_SIZES = [("", 64, 58), ("-small", 32, 29)]     # the settings icons' convention


def load(path, need_alpha=True):
    w, h, pixels, has_alpha = read_png(path)
    if need_alpha and not has_alpha:
        raise SystemExit("%s: no alpha channel" % path)
    alpha = [[row[x * 4 + 3] for x in range(w)] for row in pixels]
    lab, parts = SI.solid_parts(w, h, alpha)
    return w, h, pixels, alpha, lab, [p for p in parts if p[1] >= MIN_AREA]


def clean(pixels, alpha, lab, ps):
    ids = {p[0] for p in ps}
    box = (min(p[4][0] for p in ps), min(p[4][1] for p in ps), max(p[4][2] for p in ps), max(p[4][3] for p in ps))
    rows, (W, H), holes = SI.clean_icon(pixels, alpha, lab, ids, box)
    cbox, area = SI.content_and_area(rows, W, H)
    return rows, cbox, box, holes


def emit(name, rows, cbox, longest, sizes, out, check, built, note):
    by_size, desc = {}, []
    for suffix, side, fit in sizes:
        canvas, (ow, oh) = SI.place(rows, cbox, fit / float(longest), side)
        by_size[side] = canvas
        desc.append("%dx%d/%d" % (ow, oh, side))
        if not check:
            SI.write_tga(os.path.join(out, name + suffix + ".tga"), canvas, side)
    built.append((name, by_size))
    print("%-18s %s -> %s" % (name, note, " ".join(desc)))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "guildloc"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--contact-sheet")
    args = ap.parse_args()
    if not args.check:
        os.makedirs(args.out, exist_ok=True)
    built = []

    # badges: by grid cell
    w, h, pixels, alpha, lab, parts = load(os.path.join(args.src, "guild-locations-badges-source.png"))
    cells = {}
    for p in parts:
        col, row = min(2, int(p[2] * 3 // w)), min(2, int(p[3] * 3 // h))
        cells.setdefault(row * 3 + col, []).append(p)
    cut = []
    for i, token in enumerate(CLASSES):
        if i not in cells:
            raise SystemExit("badges: cell %d (%s) has no artwork" % (i + 1, token))
        cut.append((token,) + clean(pixels, alpha, lab, cells[i]))
    longest = max(max(c[2][2] - c[2][0], c[2][3] - c[2][1]) for c in cut)
    for token, rows, cbox, box, holes in cut:
        emit("class-" + token, rows, cbox, longest, BADGE_SIZES, args.out, args.check, built,
             "cell box %s content %dx%d" % (box, cbox[2] - cbox[0], cbox[3] - cbox[1]))

    # eyes: left open, right slashed (the slash makes the right one's solid area wider-spread; position decides, shape checks)
    w, h, pixels, alpha, lab, parts = load(os.path.join(args.src, "guild-locations-eyes-source.png"))
    left = [p for p in parts if p[2] < w / 2.0]
    right = [p for p in parts if p[2] >= w / 2.0]
    if not left or not right:
        raise SystemExit("eyes: expected one eye on each half of the sheet")
    cut = [(n,) + clean(pixels, alpha, lab, ps) for n, ps in zip(EYES, (left, right))]
    longest = max(max(c[2][2] - c[2][0], c[2][3] - c[2][1]) for c in cut)
    for name, rows, cbox, box, holes in cut:
        emit(name, rows, cbox, longest, EYE_SIZES, args.out, args.check, built, "box %s" % (box,))

    # settings illustration
    w, h, pixels, alpha, lab, parts = load(os.path.join(args.src, "guild-locations-settings-source.png"))
    if not parts:
        raise SystemExit("settings: no artwork found")
    rows, cbox, box, holes = clean(pixels, alpha, lab, parts)
    longest = max(cbox[2] - cbox[0], cbox[3] - cbox[1])
    emit("settings", rows, cbox, longest, SETTINGS_SIZES, args.out, args.check, built,
         "%d part(s) box %s" % (len(parts), box))
    if args.contact_sheet:
        SI.contact_sheet(args.contact_sheet, built)
        print("contact sheet:", args.contact_sheet)


if __name__ == "__main__":
    main()
