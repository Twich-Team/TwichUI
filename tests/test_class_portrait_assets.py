"""Source preservation, generated metadata/alpha, and packaging boundary checks."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('class_art', ROOT / 'tools/make_class_portrait_art.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

class Artwork(unittest.TestCase):
    def test_rebuild_and_alpha(self):
        with tempfile.TemporaryDirectory() as temp:
            scratch = Path(temp)
            shutil.copytree(ROOT / 'assets/class-portrait-source', scratch / 'assets/class-portrait-source')
            (scratch / '!!!TwichUI/classportrait').mkdir(parents=True)
            original = build.ROOT
            try:
                build.ROOT = scratch
                build.main()
            finally:
                build.ROOT = original
            self.assertEqual((scratch / '!!!TwichUI/classportrait/Art.lua').read_bytes(),
                             (ROOT / '!!!TwichUI/classportrait/Art.lua').read_bytes())
            files = list((scratch / '!!!TwichUI/media/classportrait').glob('*.tga'))
            self.assertEqual(len(files), 9)
            for p in files:
                with self.subTest(token=p.stem):
                    self.assertEqual(p.read_bytes(), (ROOT / '!!!TwichUI/media/classportrait' / p.name).read_bytes())
                    header = p.read_bytes()[:18]
                    self.assertEqual(header[2], 2)  # uncompressed true color
                    self.assertEqual(header[16], 32)
                    self.assertEqual(header[17] & 15, 8)  # eight alpha bits
                    self.assertEqual(struct.unpack('<HH', header[12:16]), (512,512))
                    def alpha(x,y): return p.read_bytes()[18+((511-y)*512+x)*4+3]
                    self.assertEqual(alpha(228,253), 0)  # portrait interior
                    self.assertEqual(alpha(511,511), 0)
    def test_packaging(self):
        self.assertIn('  - assets\n', (ROOT / '.pkgmeta').read_text())
        self.assertEqual(len(list((ROOT / 'assets/class-portrait-source').glob('*.png'))), 9)
        self.assertEqual(len(list((ROOT / '!!!TwichUI/media/classportrait').glob('*'))), 9)
        for name in ['Config','Art','Display']:
            self.assertIn('classportrait\\' + name + '.lua', (ROOT / '!!!TwichUI/!!!TwichUI.toc').read_text())

if __name__ == '__main__':
    unittest.main()
