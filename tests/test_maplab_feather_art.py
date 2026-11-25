"""Pixel/format contracts for an entirely mathematical TwichUI-owned mask."""
import contextlib
import io
from pathlib import Path
import struct
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))
import make_map_feather_art as feather


class FeatherArt(unittest.TestCase):
    def test_legacy_formula_reconstructs_shipped_thin_mask_exactly(self):
        previous = (REPO / "!!!TwichUI/media/textures/map-feather-thin.tga").read_bytes()
        self.assertEqual(feather.make_tga(right=.04), previous)

    def test_core_and_other_three_edges_unchanged_only_right_strip_softens(self):
        previous, current = feather.make_tga(right=.04), feather.make_tga()
        changed = 0
        for y in range(256):
            for x in range(256):
                at = 18 + (y * 256 + x) * 4
                old, new = previous[at + 3], current[at + 3]
                self.assertEqual(current[at:at + 3], b"\xff\xff\xff")
                self.assertLessEqual(new, old, "the new feather never increases alpha")
                if old != new:
                    changed += 1
                    self.assertGreaterEqual(x, 236, "only the last twenty columns may change")
                if x < 236:
                    self.assertEqual(new, old, "left/top/bottom and core remain exact")
        self.assertGreater(changed, 0)
        # Interior at 20.5 pixels from the right remains fully opaque; within
        # the new strip the midpoint alpha is lower than the old full core.
        def alpha(x, y=128): return current[18 + (y * 256 + x) * 4 + 3]
        self.assertEqual(alpha(235), 255)
        self.assertTrue(100 < alpha(246) < 150)

    def test_format_power_of_two_orientation_and_determinism(self):
        raw = feather.make_tga()
        self.assertEqual(raw, feather.make_tga())
        header = struct.unpack("<BBBHHBHHHHBB", raw[:18])
        self.assertEqual(header, (0, 0, 2, 0, 0, 0, 0, 0, 256, 256, 32, 8))
        self.assertEqual(len(raw), 18 + 256 * 256 * 4)
        self.assertEqual(256 & (256 - 1), 0)
        self.assertEqual(raw, feather.OUTPUT.read_bytes())

    def test_check_never_overwrites_invalid_or_missing_output(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            path = Path(temporary) / "mask.tga"
            self.assertEqual(feather.main(["--output", str(path), "--check"]), 1)
            self.assertFalse(path.exists())
            self.assertEqual(feather.main(["--output", str(path)]), 0)
            self.assertEqual(feather.main(["--output", str(path), "--check"]), 0)
            path.write_bytes(b"owned invalid fixture")
            self.assertEqual(feather.main(["--output", str(path), "--check"]), 1)
            self.assertEqual(path.read_bytes(), b"owned invalid fixture")
        for bad in (False, 0, -1, float("nan"), float("inf"), 2):
            with self.assertRaises(ValueError): feather.make_tga(right=bad)


if __name__ == "__main__":
    unittest.main()
