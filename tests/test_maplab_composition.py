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
    def test_zone_overlay_replacement_preserves_native_base_city_repairs(self):
        data = {"maps": [{"id": 1420, "art": 2126, "files": [7958258]}, {"id": 1, "art": 2}],
                "reveal": {"2126": [[320, 256, 463, 361, [7958244, 7958245]]],
                           "2": [[128, 128, 0, 0, [99]]]}}
        replacement = composition.overlay_file_ids(data, {1420})
        self.assertEqual(replacement, {7958244, 7958245})
        self.assertNotIn(7958258, replacement, "same-level production native-base patch must survive offline overlay replacement")
        self.assertNotIn(99, replacement, "only Lua-selected sources participate")

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

    def test_extended_claims_cannot_cancel_a_sources_frame_feather(self):
        one = np.ones((24, 32), np.float32); zero = np.zeros_like(one)
        scene = {"width": 32, "height": 24, "view": {"u0": 0, "v0": 0, "u1": 1, "v1": 1},
                 "textures": [{"fileId": 1, "u0": 0, "v0": 0, "u1": 1, "v1": 1}]}
        def item(avail, distance):
            return {"bounds": scene["view"], "masks": {"territory": zero, "core": zero,
                "availability": one * avail, "distance": one * distance}}
        coast = {1415: {"mask": one, "files": {1}}}
        result = composition.ownership_masks({10: item(.1, 300), 20: item(1, 400)}, scene, True, coast)
        self.assertLessEqual(float(result[10].max()), .100001)
        self.assertGreater(float(result[10].max()), 0)
        self.assertTrue(np.all(result[10] + result[20] <= 1.000001))
        # Without a registered source coastline, extended behavior cannot activate.
        self.assertEqual(float(composition.ownership_masks({10: item(.1, 300)}, scene, True, {})[10].max()), 0)

    def test_native_outline_rgb_padding_crop_is_distinct_from_opaque_alpha(self):
        raw = Image.new("RGBA", (128, 128), (0, 0, 0, 255))
        ImageDraw.Draw(raw).ellipse((39, 6, 81, 78), outline=(48, 48, 48, 255), width=2)
        mask, evidence = composition.filled_outline(raw, (1002, 668))
        self.assertEqual(evidence["crop"], [0, 0, 128, 85])
        self.assertEqual(mask.shape, (668, 1002))
        self.assertGreater(mask[335, 470], .99)
        self.assertEqual(mask[335, 5], 0)
        transparent = raw.copy(); transparent.putalpha(0)
        again, _ = composition.filled_outline(transparent, (1002, 668))
        np.testing.assert_array_equal(mask, again)
        for blank in (Image.new("RGBA", (128, 128)), Image.new("RGBA", (128, 128), "white")):
            with self.assertRaisesRegex(ValueError, "silhouette"):
                composition.filled_outline(blank, (1002, 668))

    def test_owned_paper_is_opaque_deterministic_and_anchored_to_world(self):
        a = {"width": 16, "height": 16, "view": {"u0": 0, "v0": 0, "u1": 1, "v1": 1}, "textures": []}
        b = {"width": 16, "height": 16, "view": {"u0": .5, "v0": 0, "u1": 1.5, "v1": 1}, "textures": []}
        first, _ = composition.regional_paper(a, {})
        same, _ = composition.regional_paper(a, {})
        shifted, _ = composition.regional_paper(b, {})
        self.assertEqual(first.tobytes(), same.tobytes())
        self.assertEqual(first.getchannel("A").getextrema(), (255, 255))
        np.testing.assert_array_equal(np.asarray(first)[:, 8:], np.asarray(shifted)[:, :8])

    def test_registered_coarse_context_keeps_unpainted_land_as_paper(self):
        scene = {"width": 32, "height": 24, "view": {"u0": 0, "v0": 0, "u1": 1, "v1": 1},
                 "textures": [{"fileId": 1, "u0": .25, "v0": .25, "u1": .75, "v1": .75}]}
        image, evidence = composition.regional_paper(scene, {}, {1415: {"mask": np.ones((8, 8), np.float32), "files": {1}}})
        self.assertGreater(evidence["unpaintedSourceLandPixels"], 0)
        self.assertEqual(evidence["registeredSourceContinents"], [1415])
        self.assertFalse(evidence["nativeApiHighlightGeometryVerified"])
        self.assertGreater(image.getpixel((16, 12))[0], image.getpixel((0, 0))[0])

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
