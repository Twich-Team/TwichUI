#!/usr/bin/env python3
"""Prepare the two original preview paintings with the existing premultiplied asset pipeline."""
import json
from pathlib import Path
from make_map_tool_icons import read_png, resample
from make_settings_icons import bleed
from make_style_v2_art import write_png_rgba, write_tga_rgba

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '!!!TwichUI/media/reminders'

def main():
    evidence = {}
    for name, width, height in [('landscape', 512, 512), ('parchment', 512, 256)]:
        source = ROOT / ('assets/reminder-preview-' + name + '-source.png')
        w, h, rows, alpha = read_png(str(source))
        clear = sum(row[x] == 0 for row in rows for x in range(3, len(row), 4))
        translucent = sum(0 < row[x] < 255 for row in rows for x in range(3, len(row), 4))
        if name == 'parchment' and (not alpha or clear == 0):
            raise ValueError('Parchment requires meaningful transparent exterior pixels')
        # The landscape's full composition is stored square, then restored to its original aspect by texcoords/layout.
        pixels = resample(rows, (0, 0, w, h), width, height)
        if name == 'parchment':
            padded = pixels + [bytearray(width * 4) for _ in range(width - height)]
            bleed(padded, width)
            pixels = padded[:height]
        write_tga_rgba(str(OUT / ('preview-' + name + '.tga')), pixels)
        preview = ROOT / 'test-output/preview-art'
        preview.mkdir(parents=True, exist_ok=True)
        write_png_rgba(str(preview / (name + '.png')), width, height, pixels)
        evidence[name] = dict(source=str(source.relative_to(ROOT)), source_size=[w,h], runtime_size=[width,height],
                              source_alpha=alpha, clear_pixels=clear, translucent_pixels=translucent)
    (ROOT / 'test-output/preview-art/alpha.json').write_text(json.dumps(evidence, indent=2)+'\n')
    print(json.dumps(evidence, indent=2))

if __name__ == '__main__':
    main()
