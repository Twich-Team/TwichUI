#!/usr/bin/env python3
"""Preserve target canvases; convert to alpha-filtered 512px runtime TGAs.

Sources and supplier aperture metadata stay byte-for-byte in assets/. Runtime
uses the same supported TGA convention and alpha-aware filter as class portraits.
"""
from pathlib import Path
import json
import struct
from make_map_tool_icons import read_png, resample

ROOT = Path(__file__).resolve().parents[1]
SIZE = 512

def main():
    source = ROOT / 'assets/target-portrait-source'
    manifest = json.loads((source / 'manifest.json').read_text())
    out = ROOT / '!!!TwichUI/media/targetart/modern'
    out.mkdir(parents=True, exist_ok=True)
    for art in manifest['assets']:
        w, h, pixels, alpha = read_png(source / art['filename'])
        assert alpha and (w, h) == (1254, 1254)
        rows = resample(pixels, (0, 0, w, h), SIZE, SIZE)
        with (out / (art['variant'].lower() + '.tga')).open('wb') as texture:
            texture.write(struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8))
            for row in reversed(rows):
                for x in range(SIZE):
                    r, g, b, a = row[x*4:x*4+4]
                    texture.write(bytes((b, g, r, a)))
        print(art['variant'], '1254 RGBA -> 512 BGRA; full canvas, unchanged orientation')

if __name__ == '__main__':
    main()
