#!/usr/bin/env python3
"""Prepare original condition-type paintings, separate from reminder/template artwork.

Uses the established shape cleanup, optical balance, premultiplied resampling,
edge color bleed and straight-alpha TGA conventions. Existing NPC horse art is reused unchanged.
"""
import json
import math
from pathlib import Path
import make_settings_icons as SI
from make_map_tool_icons import read_png

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '!!!TwichUI/media/reminders/conditions'
REVIEW = ROOT / 'test-output/reminders-addendum'

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    evidence = {}
    for name in ('enchant', 'combat'):
        source = ROOT / ('assets/reminder-condition-' + name + ('-v2' if name == 'enchant' else '') + '-source.png')
        w, h, pixels, alpha = read_png(str(source))
        clear = sum(row[x] == 0 for row in pixels for x in range(3, len(row), 4))
        if not alpha or not clear:
            raise ValueError(str(source) + ': real transparent exterior required')
        alphas = [[row[x * 4 + 3] for x in range(w)] for row in pixels]
        labels, parts = SI.solid_parts(w, h, alphas)
        largest = max(p[1] for p in parts)
        chosen = [p for p in parts if p[1] >= max(16, largest * .002)]
        box = (min(p[4][0] for p in chosen), min(p[4][1] for p in chosen),
               max(p[4][2] for p in chosen), max(p[4][3] for p in chosen))
        rows, (cw, ch), holes = SI.clean_icon(pixels, alphas, labels, {p[0] for p in chosen}, box)
        bounds, area = SI.content_and_area(rows, cw, ch)
        longest = max(bounds[2] - bounds[0], bounds[3] - bounds[1])
        # Limit denser crossed blades while retaining a readable single-blade silhouette.
        balance = min(1., (.60 / (math.sqrt(area) / longest)) ** .5)
        sizes = {}
        for suffix, side, fit in [('', 64, 56), ('-small', 32, 28)]:
            canvas, used = SI.place(rows, bounds, fit * balance / longest, side)
            SI.write_tga(str(OUT / (name + suffix + '.tga')), canvas, side)
            SI.write_png(str(REVIEW / (name + suffix + '.png')), side, side, canvas)
            counts = [row[i] for row in canvas for i in range(3, len(row), 4)]
            sizes[side] = dict(content=list(used), clear=counts.count(0),
                               partial=sum(0 < a < 255 for a in counts))
        evidence[name] = dict(source=str(source.relative_to(ROOT)), dimensions=[w,h],
                              source_clear=clear, balance=balance, runtime=sizes)
    (REVIEW / 'alpha.json').write_text(json.dumps(evidence, indent=2)+'\n')
    print(json.dumps(evidence, indent=2))

if __name__ == '__main__':
    main()
