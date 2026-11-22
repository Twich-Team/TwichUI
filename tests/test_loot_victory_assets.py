"""Runtime exports retain the approved straight-alpha art, crop and OGG formats."""
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
        self.assertEqual(len(list(ART.glob('*.tga'))), 16)


if __name__ == '__main__':
    unittest.main()
