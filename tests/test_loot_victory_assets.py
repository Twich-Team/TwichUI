"""Runtime exports retain the approved straight-alpha art, crop and OGG formats."""
import hashlib
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / '!!!TwichUI/media/loot/victory'


class VictoryAssets(unittest.TestCase):
    def test_runtime_exports(self):
        manifest = json.loads((ROOT / 'assets/loot-victory/manifest.json').read_text())
        for path in ART.glob('*.tga'):
            with self.subTest(texture=path.name):
                data = path.read_bytes()
                width, height, depth, descriptor = struct.unpack_from('<HHBB', data, 12)
                self.assertEqual([width, height], manifest['textures'][path.stem]['canvas'])
                self.assertEqual(depth, 32)
                self.assertEqual(descriptor & 15, 8)
                self.assertEqual(data[2], 2)  # uncompressed true-color
                alpha = data[18 + data[0] + 3:18 + data[0] + width * height * 4:4]
                self.assertEqual([min(alpha), max(alpha)], manifest['textures'][path.stem]['alpha_min_max'])
        for path in ART.glob('*.ogg'):
            self.assertTrue(path.read_bytes().startswith(b'OggS'))
        self.assertEqual(len(list(ART.glob('*.ogg'))), 2)
        self.assertEqual(len(list(ART.glob('*.tga'))), 11)  # five superseded effects no longer ship

    def test_supplemental_runtime_subset(self):
        source = ROOT / 'assets/loot-victory-fx'
        manifest = json.loads((source / 'manifest.json').read_text())
        selected = {f['id']: f for f in manifest['files'] if f['recommended'] or f['id'] in {'fx_sweep_trail', 'fx_emblem_final_star'}}
        actual = {p.stem: p for p in (ART / 'fx').glob('*.tga')}
        self.assertEqual(set(actual), set(selected))
        self.assertEqual(len(actual), 13)
        for name, path in actual.items():
            with self.subTest(texture=name):
                data = path.read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), selected[name]['tga_sha256'])
                width, height, depth, descriptor = struct.unpack_from('<HHBB', data, 12)
                self.assertEqual([width, height], selected[name]['size_px'])
                self.assertEqual((data[2], depth, descriptor & 15), (2, 32, 8))
                alpha = data[18 + data[0] + 3:18 + data[0] + width * height * 4:4]
                self.assertGreater(max(alpha), 224)
                border = alpha[:width] + alpha[-width:] + alpha[::width] + alpha[width - 1::width]
                self.assertEqual(max(border), 0, 'additive sprite edges must remain transparent')
                # Check the actual sampled content UV border too, not only the file canvas.
                x, y, w, h = selected[name]['content_bbox_xywh']
                def at(px, py):
                    row = py if descriptor & 32 else height - 1 - py
                    return alpha[row * width + px]
                sampled_border = [at(px, py) for px in range(x, x + w) for py in (y, y + h - 1)]
                sampled_border += [at(px, py) for py in range(y, y + h) for px in (x, x + w - 1)]
                self.assertLessEqual(max(sampled_border), 1, 'sampled UVs must retain a clean feathered perimeter')
        # Authoring images/atlases never belong in the addon runtime tree.
        self.assertEqual(list(ART.rglob('*.png')) + list(ART.rglob('*.jpg')), [])
        self.assertIn('  - assets', (ROOT / '.pkgmeta').read_text())


if __name__ == '__main__':
    unittest.main()
