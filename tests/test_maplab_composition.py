"""Owned pixel fixtures for the optional private composition experiment."""
from pathlib import Path
import sys
import unittest

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools/maplab"))
try:
    import numpy as np
    import composition
except ImportError:
    composition = None


@unittest.skipIf(composition is None, "optional offline composition requires NumPy/SciPy")
class Composition(unittest.TestCase):
    def test_masks_use_native_alpha_and_authored_exclusions_not_source_rgb(self):
        alpha = Image.new("L", (180, 140)); ImageDraw.Draw(alpha).rectangle((30, 30, 150, 110), fill=255)
        masks = composition.source_masks(alpha, [(80, 40, 110, 90)], frame=8, reach=30, band=15, core=12)
        self.assertGreater(masks["core"][70, 55], .99)
        self.assertLess(masks["territory"][65, 95], .01)
        self.assertEqual(masks["territory"][0, 70], 0)
        self.assertGreater(masks["territory"][25, 55], 0)
        for mask in (masks["core"], masks["territory"], masks["band"]):
            self.assertTrue(np.all(np.isfinite(mask)))
            self.assertGreaterEqual(float(mask.min()), 0)
            self.assertLessEqual(float(mask.max()), 1)

    def test_boundary_grade_keeps_core_and_unselected_pixels_exact(self):
        pixels = np.empty((24, 32, 4), dtype=np.uint8); pixels[:] = (100, 150, 70, 255)
        core = np.zeros((24, 32), dtype=np.float32); core[:, 16:] = 1
        band = np.ones((24, 32), dtype=np.float32); band[:3] = 0
        result, metrics = composition.border_grade(Image.fromarray(pixels), band, core, [145, 130, 105])
        after = np.asarray(result)
        self.assertTrue(metrics["applied"])
        self.assertEqual(metrics["corePixelsChanged"], 0)
        np.testing.assert_array_equal(after[:, 16:], pixels[:, 16:])
        np.testing.assert_array_equal(after[:3], pixels[:3])
        self.assertTrue(np.any(after[4:20, :16] != pixels[4:20, :16]))
        y = np.array([.2126, .7152, .0722])
        self.assertLess(float(np.max(np.abs(after[..., :3] @ y - pixels[..., :3] @ y))), 1)

    def test_no_boundary_samples_means_no_speculative_grading(self):
        im = Image.new("RGBA", (8, 8), (90, 120, 150, 255)); zero = np.zeros((8, 8), np.float32)
        result, metrics = composition.border_grade(im, zero, zero, [0, 0, 0])
        self.assertFalse(metrics["applied"]); self.assertEqual(result.tobytes(), im.tobytes())

    def test_overlap_claims_are_bounded_order_independent_and_respect_other_core(self):
        scene = {"width": 32, "height": 24, "view": {"u0": 0, "v0": 0, "u1": 1, "v1": 1}}
        one = np.ones((24, 32), np.float32); zero = np.zeros_like(one)
        def item(core):
            return {"bounds": {"u0": 0, "v0": 0, "u1": 1, "v1": 1},
                    "masks": {"territory": one, "distance": zero, "core": core}}
        a = composition.ownership_masks({10: item(zero), 20: item(zero)}, scene)
        b = composition.ownership_masks({20: item(zero), 10: item(zero)}, scene)
        np.testing.assert_array_equal(a[10], b[10]); np.testing.assert_allclose(a[10] + a[20], one)
        c = composition.ownership_masks({10: item(one), 20: item(zero)}, scene)
        self.assertEqual(float(c[20].max()), 0)
        self.assertTrue(np.all(c[10] + c[20] <= 1))

    def test_no_lua_selected_calibrated_zone_is_an_unchanged_control_not_an_error(self):
        scene = {"width": 32, "height": 24, "view": {"u0": 0, "v0": 0, "u1": 1, "v1": 1}}
        self.assertEqual(composition.ownership_masks({}, scene), {})

    def test_parent_title_correction_cannot_change_outside_roi_or_coast_guard(self):
        image = Image.new("RGBA", (1002, 668), (150, 140, 100, 255)); draw = ImageDraw.Draw(image)
        for x in range(350, 640, 18): draw.rectangle((x, 373, x + 3, 410), fill=(30, 25, 20, 255))
        result, mask, metrics = composition.parent_label_field(image)
        self.assertGreater(metrics["changedPixels"], 0)
        self.assertEqual(metrics["outsideRoiPixelsChanged"], 0)
        self.assertEqual(metrics["protectedCoastPixelsChanged"], 0)
        self.assertEqual(result.getchannel("A").tobytes(), image.getchannel("A").tobytes())
        self.assertEqual(mask.getpixel((100, 100)), 0)
        self.assertEqual(result.getpixel((100, 100)), image.getpixel((100, 100)))

    def test_authored_source_calibration_refuses_changed_pixels(self):
        with self.assertRaisesRegex(ValueError, "calibration"):
            composition.calibrated(Image.new("RGBA", (1002, 668), (80, 120, 160, 255)), 1415)

    def test_parent_calibration_refuses_other_canvas_dimensions(self):
        with self.assertRaisesRegex(ValueError, "calibration"):
            composition.parent_label_field(Image.new("RGBA", (501, 334)))

    def test_rasterization_uses_exact_exported_world_rectangle(self):
        values = np.ones((8, 8), np.float32)
        scene = {"width": 20, "height": 20, "view": {"u0": 0, "v0": 0, "u1": 1, "v1": 1}}
        r = composition.on_view(values, {"u0": .25, "v0": .25, "u1": .75, "v1": .75}, scene)
        self.assertEqual(r[0, 0], 0); self.assertEqual(r[10, 10], 1); self.assertEqual(r[-1, -1], 0)


if __name__ == "__main__": unittest.main()
