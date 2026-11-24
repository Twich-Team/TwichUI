"""Render production-selected map layers from the synthetic Lua MapCanvas fixture.

python3 tools/mapdata/preview.py --output test-output/map-preview.png
No game artwork is used. Colours identify texture IDs. This is a transform,
visibility and alpha diagnostic, never evidence of in-game appearance.
"""
import argparse
import math
import os
from pathlib import Path
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont


def render(lines):
    scenes = []
    for line in lines.splitlines():
        row = line.split('\t')
        if row[0] == 'scene':
            scenes.append((row[1], list(map(float, row[2:])), []))
        elif row[0] == 'texture':
            scenes[-1][2].append(list(map(float, row[1:])))
    width, height = 1400, 1040
    image = Image.new('RGB', (width, height), '#171d23')
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype('DejaVuSans.ttf', 18)
    small = ImageFont.truetype('DejaVuSans.ttf', 14)
    draw.text((26, 18), 'SIMULATED MAP LAYERS — synthetic geography / no game artwork', font=font, fill='#f1ddad')
    draw.text((26, 49), 'Actual Lua texture selection, world placement and alpha. Rectangles do not reproduce terrain or feather masks.', font=small, fill='#b6bec7')
    for n, (name, bounds, textures) in enumerate(scenes):
        x, y = 26 + n % 2 * 687, 90 + n // 2 * 312
        panel = Image.new('RGBA', (660, 260), '#c3a779')
        l, top, r, bottom = bounds
        for tex in sorted(textures, key=lambda row: row[-1]):
            fid, u, v, w, h, alpha, angle, level = tex
            pts = []
            for dx, dy in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
                # Apply the texture's rotation in its rendered square, including non-square world scaling.
                ru = u + w / 2 + (dx * math.cos(angle) - dy * math.sin(angle)) * w
                rv = v + h / 2 + (dx * math.sin(angle) + dy * math.cos(angle)) * h
                pts.append(((ru - l) / (r - l) * 660, (rv - top) / (bottom - top) * 260))
            # Offscreen art is clipped by the panel, like the MapCanvas viewport.
            if max(a for a, b in pts) < 0 or min(a for a, b in pts) > 660 or max(b for a, b in pts) < 0 or min(b for a, b in pts) > 260:
                continue
            colour = (70 + int(fid * 37) % 145, 65 + int(fid * 23) % 140, 65 + int(fid * 13) % 120, round(alpha * 200))
            layer = Image.new('RGBA', panel.size)
            ld = ImageDraw.Draw(layer)
            ld.polygon(pts, fill=colour, outline=(35, 40, 46, 160))
            if 8 < pts[0][0] < 600 and 8 < pts[0][1] < 230:
                ld.text(pts[0], str(int(fid)), font=small, fill=(255, 255, 255, 220))
            panel = Image.alpha_composite(panel, layer)
        image.paste(panel.convert('RGB'), (x, y + 29))
        draw.text((x, y), f'{name}   ({len(textures)} bound textures)', font=font, fill='#e9e1cf')
    return image


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='twichui-map-preview-') as temp:
        trace = Path(temp) / 'layers.tsv'
        # The trace path is data, never interpolated as executable Lua source.
        code = ('require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"; '
                'MAP_PREVIEW_FILE=os.getenv("TWICHUI_MAP_PREVIEW_TRACE"); dofile("test_map_explore.lua")')
        env = dict(os.environ, TWICHUI_MAP_PREVIEW_TRACE=str(trace))
        result = subprocess.run(['lua5.1', '-e', code], cwd=repo / 'tests', env=env,
                                text=True, capture_output=True, check=False)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        render(trace.read_text()).save(args.output)
        print(result.stdout.strip().splitlines()[-2])
        print(f'Simulated geometry preview: {args.output}')
