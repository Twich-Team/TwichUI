"""tools/make_layout_wizard_art.py: the layout wizard's artwork is a reproducible build of the sources in assets/.

Rebuilds every picture the tool builds without --phase5 into a temporary folder and compares each with the file shipped in
TwichUI_LayoutWizard/media/ byte for byte, so a changed source, a changed tool or a hand-edited texture is caught. Also checks the
shipped icon-sheet pictures' format (128 x 128, uncompressed 32-bit, 8 alpha bits), that they have real transparency (clear corners, an
opaque interior, nothing painted on the file's edge) and that no checkerboard was baked in.

Run: python3 -m unittest discover -s tests -p "test_wizard_art.py"
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "TwichUI_LayoutWizard" / "media"
TOOL = ROOT / "tools" / "make_layout_wizard_art.py"
BUILT = ("emblem", "classic", "personalize", "screenfit", "keep", "helpers", "tipfixed", "tipcursor")
ICONS = ("keep", "helpers", "tipfixed", "tipcursor")


def read_tga(path):
    d = Path(path).read_bytes()
    w, h = d[12] + d[13] * 256, d[14] + d[15] * 256
    return d, w, h


class WizardArt(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        r = subprocess.run([sys.executable, "-I", "-B", str(TOOL), "--out", cls.tmp.name], capture_output=True, text=True, cwd=str(ROOT))
        cls.run_result = r

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_tool_ran(self):
        self.assertEqual(self.run_result.returncode, 0, self.run_result.stderr)
        self.assertIn("keep      content", self.run_result.stdout)

    def test_shipped_files_are_what_the_tool_builds(self):
        for name in BUILT:
            built = Path(self.tmp.name) / (name + ".tga")
            self.assertTrue(built.exists(), name + " was not built")
            self.assertEqual(built.read_bytes(), (MEDIA / (name + ".tga")).read_bytes(), name + ".tga differs from its source build")

    def test_compact_is_not_rebuilt_without_its_flag(self):
        self.assertFalse((Path(self.tmp.name) / "compact.tga").exists())
        self.assertTrue((MEDIA / "compact.tga").exists())

    def test_icon_format_and_transparency(self):
        for name in ICONS:
            d, w, h = read_tga(MEDIA / (name + ".tga"))
            self.assertEqual((w, h), (128, 128), name)
            self.assertEqual((d[2], d[16], d[17]), (2, 32, 8), name + ": uncompressed, 32 bit, 8 alpha bits")
            self.assertEqual(len(d), 18 + w * h * 4, name)

            def alpha(x, y):   # bottom-left origin
                return d[18 + ((h - 1 - y) * w + x) * 4 + 3]
            self.assertEqual([alpha(0, 0), alpha(w - 1, 0), alpha(0, h - 1), alpha(w - 1, h - 1)], [0, 0, 0, 0], name + ": clear corners")
            clear = sum(1 for y in range(h) for x in range(w) if alpha(x, y) == 0)
            solid = sum(1 for y in range(h) for x in range(w) if alpha(x, y) == 255)
            self.assertGreater(clear, w * h * 0.15, name + ": a transparent surround")
            self.assertGreater(solid, w * h * 0.30, name + ": an opaque interior")
            edge = [alpha(i, 0) + alpha(i, h - 1) + alpha(0, i) + alpha(w - 1, i) for i in range(w)]
            self.assertEqual(sum(edge), 0, name + ": nothing painted touches the file's edge")
            # no baked-in checkerboard: the pixels that are fully clear carry colour from the picture (bled), never the checker greys
            greys = 0
            for y in range(h):
                for x in range(w):
                    if alpha(x, y) == 0:
                        o = 18 + ((h - 1 - y) * w + x) * 4
                        b, g, r = d[o], d[o + 1], d[o + 2]
                        if max(r, g, b) - min(r, g, b) <= 7 and min(r, g, b) >= 205:
                            greys += 1
            self.assertEqual(greys, 0, name + ": no checker grey in the clear pixels")

    def test_sources_are_kept(self):
        self.assertTrue((ROOT / "assets" / "layout-wizard-icons-source.png").exists())


if __name__ == "__main__":
    unittest.main()
