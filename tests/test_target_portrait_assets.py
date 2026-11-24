"""Supplier source integrity, deterministic game textures and release boundary."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
spec = importlib.util.spec_from_file_location('target_portrait_art', ROOT / 'tools/make_target_portrait_art.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
HASHES = {
    'Boss': '1677252f4f6d4729e7f488066ff87e700964902e45f7f84388d87589f93efbb2',
    'Elite': 'f895214bd792528501b217a1d456fd6751d079c11f0129c5e2df81d61900998c',
    'Rare': '009f971f92025d8423af13507150cc6fbe081308bc609786699b377815091a2b',
}

class TargetPortraitAssets(unittest.TestCase):
    def test_sources_and_aperture(self):
        source = ROOT / 'assets/target-portrait-source'
        manifest = json.loads((source / 'manifest.json').read_text())
        self.assertEqual(manifest['recommended_common_opening_bbox_px'],
                         dict(left=672, top=406, right=1047, bottom=788, width=376, height=383))
        self.assertEqual({entry['variant'] for entry in manifest['assets']}, set(HASHES))
        for entry in manifest['assets']:
            with self.subTest(variant=entry['variant']):
                raw = (source / entry['filename']).read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), HASHES[entry['variant']])
                self.assertEqual(struct.unpack('>II', raw[16:24]), (1254, 1254))
                self.assertEqual(raw[25], 6)  # RGBA
                self.assertEqual(entry['notes']['frame_side'], 'right')
                self.assertEqual(entry['notes']['ridge_direction'], 'left')

    def test_runtime_rebuild_alpha_and_packaging(self):
        with tempfile.TemporaryDirectory() as folder:
            scratch = Path(folder)
            shutil.copytree(ROOT / 'assets/target-portrait-source', scratch / 'assets/target-portrait-source')
            original = build.ROOT
            try:
                build.ROOT = scratch
                build.main()
            finally:
                build.ROOT = original
            for variant in HASHES:
                name = variant.lower() + '.tga'
                relative = Path('!!!TwichUI/media/targetart/modern') / name
                generated = (scratch / relative).read_bytes()
                self.assertEqual(generated, (ROOT / relative).read_bytes(), name)
                self.assertEqual(generated[2], 2)  # uncompressed true color
                self.assertEqual(generated[16], 32)
                self.assertEqual(generated[17], 8)
                self.assertEqual(struct.unpack('<HH', generated[12:16]), (512,512))
                self.assertEqual(len(generated), 18+512*512*4)
                alpha = generated[21::4]
                self.assertEqual(min(alpha), 0)
                self.assertGreaterEqual(max(alpha), 250)
                self.assertTrue(any(0 < a < 255 for a in alpha))
                # Supplier aperture center, after full-canvas downsampling; no matte.
                self.assertEqual(alpha[(511-244)*512+351], 0)
        packaging = (ROOT / '.pkgmeta').read_text()
        self.assertIn('  - assets\n', packaging)
        self.assertNotIn('  - !!!TwichUI/media/targetart', packaging)
        self.assertIn('!!!TwichUI/!!!TwichUI: "!!!TwichUI"', packaging)
        config = (ROOT / '!!!TwichUI/targetart/Config.lua').read_text()
        self.assertIn('targetart\\', config)
        self.assertIn('targetart\\Config.lua', (ROOT / '!!!TwichUI/!!!TwichUI.toc').read_text())

if __name__ == '__main__':
    unittest.main()
