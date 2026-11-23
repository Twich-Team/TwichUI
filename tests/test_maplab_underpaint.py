"""Owned pixel fixtures for the private source-aware underpaint study."""
from pathlib import Path
import sys
import unittest

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools/maplab"))
import underpaint
from render import LabError


class Sources:
    def __init__(self, pictures):
        self.pictures = pictures
        self.used = {str(k): {"kind": "local-client-artwork"} for k in pictures}
    def get(self, key): return self.pictures.get(int(key))


class Underpaint(unittest.TestCase):
    def test_zero_extension_preserves_alpha_exactly_even_on_large_source(self):
        alpha = Image.new("L", (513, 267)); alpha.putpixel((251, 123), 255)
        self.assertEqual(underpaint.support_mask(alpha, 0, 0, 0).tobytes(), alpha.tobytes())

    def test_dilation_adds_context_and_guard_excludes_native_frame(self):
        alpha = Image.new("L", (128, 96))
        for y in range(30, 66):
            for x in range(35, 93): alpha.putpixel((x, y), 255)
        mask = underpaint.support_mask(alpha, 12, 3, 8)
        self.assertEqual(mask.getpixel((64, 48)), 255)
        self.assertGreater(mask.getpixel((29, 48)), 0)
        self.assertEqual(mask.getpixel((8, 48)), 0)
        self.assertEqual(mask.getpixel((64, 8)), 0)

    def test_source_rgb_and_opaque_overlay_pixels_are_not_repainted(self):
        base = Image.new("RGBA", (64, 64), (25, 80, 140, 255))
        overlay = Image.new("RGBA", (64, 64))
        overlay.putpixel((32, 32), (90, 70, 20, 255))
        before = (base.tobytes(), overlay.tobytes())
        after, mask = underpaint.composite(base, overlay, 7, 1, 0)
        self.assertEqual(after.getpixel((32, 32)), (90, 70, 20, 255))
        self.assertEqual(after.getpixel((35, 32))[:3], (25, 80, 140))
        self.assertEqual((base.tobytes(), overlay.tobytes()), before)
        again, againmask = underpaint.composite(base, overlay, 7, 1, 0)
        self.assertEqual((after.tobytes(), mask.tobytes()), (again.tobytes(), againmask.tobytes()))

    def test_partial_tiles_use_declared_source_geometry_without_stretch(self):
        data = {"maps": [{"id": 10, "type": 3, "art": 20, "layer": [6, 3, 4, 4], "files": [1, 2]}],
                "reveal": {"20": [[3, 2, 2, 1, [3]]]}}
        pictures = {1: Image.new("RGBA", (4, 4), (10, 20, 30, 255)),
                    2: Image.new("RGBA", (4, 4), (40, 50, 60, 255)),
                    3: Image.new("RGBA", (4, 2), (90, 80, 70, 255))}
        base, overlay, sources = underpaint.assemble(data, 10, Sources(pictures))
        self.assertEqual(base.size, (6, 3)); self.assertEqual(sources, [1, 2, 3])
        self.assertEqual(base.getpixel((3, 2)), (10, 20, 30, 255))
        self.assertEqual(base.getpixel((4, 2)), (40, 50, 60, 255))
        self.assertEqual(overlay.getpixel((4, 2)), (90, 80, 70, 255))
        self.assertEqual(overlay.getpixel((5, 2)), (0, 0, 0, 0))
        with self.assertRaisesRegex(LabError, "unavailable"):
            underpaint.assemble(data, 10, Sources({1: pictures[1]}))

    def test_nonclient_art_and_missing_overlay_support_are_rejected(self):
        data = {"maps": [{"id": 10, "type": 3, "art": 20, "layer": [4, 4, 4, 4], "files": [1]}], "reveal": {}}
        assets = Sources({1: Image.new("RGBA", (4, 4))})
        with self.assertRaisesRegex(LabError, "no declared"):
            underpaint.assemble(data, 10, assets)
        assets.used["1"]["kind"] = "synthetic"
        with self.assertRaisesRegex(LabError, "actual client"):
            underpaint.assemble(data, 10, assets)

    def test_only_lua_selected_candidates_are_placed_with_original_union_bounds(self):
        candidate = {"mapId": 10, "alpha": .8, "textures": [
            {"u0": .1, "v0": .2, "u1": .3, "v1": .4},
            {"u0": .3, "v0": .2, "u1": .5, "v1": .4}]}
        scene = {"metadata": {"art": {"layers": [{"kind": "zone", "level": 7}]}, "baseCandidates": [candidate]}}
        self.assertEqual(underpaint.selected_underpaints(scene, {11: object()}), [])
        result = underpaint.selected_underpaints(scene, {10: object()})
        self.assertEqual(len(result), 1)
        self.assertEqual(tuple(result[0][k] for k in ("u0", "v0", "u1", "v1", "alpha", "level")), (.1, .2, .5, .4, .8, 7))
        self.assertNotIn("asset", candidate)
        scene["metadata"]["baseCandidates"].append(candidate)
        with self.assertRaisesRegex(LabError, "duplicate"):
            underpaint.selected_underpaints(scene, {10: object()})
        with self.assertRaisesRegex(LabError, "evidence"):
            underpaint.selected_underpaints({}, {10: object()})

    def test_invalid_shape_and_unbounded_processing_settings_fail(self):
        for value in (-1, 97, True, 1.5):
            with self.assertRaises(LabError):
                underpaint.support_mask(Image.new("L", (8, 8)), value, 0, 0)
        with self.assertRaises(LabError):
            underpaint.support_mask(Image.new("RGB", (8, 8)))
        with self.assertRaises(LabError):
            underpaint.composite(Image.new("RGBA", (8, 8)), Image.new("RGBA", (4, 4)))


if __name__ == "__main__": unittest.main()
