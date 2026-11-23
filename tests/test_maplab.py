"""Pixel and contract checks for the offline compositor, independent of WoW assets."""
import hashlib
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest
import zlib

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools/maplab"))
import diagnostics
import preprocess
import render
import run as maprun
from assets import probe, referenced_ids


class Compositor(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="twichui-maplab-test-")
        self.root = Path(self.temp.name)
        self.assets = {}
        self.add("red", Image.new("RGBA", (16, 16), (255, 0, 0, 255)))
        self.add("blue", Image.new("RGBA", (16, 16), (0, 0, 255, 255)))

    def tearDown(self):
        self.temp.cleanup()

    def add(self, key, image):
        path = self.root / f"{key}.png"
        image.save(path)
        self.assets[key] = {"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                            "kind": "synthetic-test-texture", "provenance": "owned mathematical unit fixture"}
        self.manifest = self.root / "manifest.json"
        self.manifest.write_text(json.dumps({"schema": 1, "assets": self.assets}))

    def scene(self, textures, **kwargs):
        return dict(id="fixture", width=16, height=16, view=dict(u0=0, v0=0, u1=1, v1=1), textures=textures, **kwargs)

    def texture(self, key, **kwargs):
        return dict(asset=key, u0=0, v0=0, u1=1, v1=1, alpha=1, level=1, **kwargs)

    def draw(self, textures, **kwargs):
        scene = self.scene(textures, **kwargs)
        render.validate_export({"schema": 1, "scenes": [scene]})
        return render.composite_scene(scene, render.Assets(self.manifest))

    def test_layer_alpha_and_tint_are_composited(self):
        low = self.texture("red")
        high = self.texture("blue"); high.update(level=2, alpha=.5)
        image, report = self.draw([high, low])
        pixel = image.getpixel((8, 8))
        self.assertEqual(pixel[3], 255)
        self.assertTrue(126 <= pixel[0] <= 128 and 127 <= pixel[2] <= 129)
        self.assertEqual(report["transparentFraction"], 0)
        tinted = self.texture("red", tint=[.5, 1, 1])
        image, _ = self.draw([tinted])
        self.assertEqual(image.getpixel((8, 8)), (128, 0, 0, 255))

    def test_crop_and_transparent_out_of_range_not_stretch(self):
        split = Image.new("RGBA", (16, 16), (0, 0, 255, 255))
        for x in range(8):
            for y in range(16): split.putpixel((x, y), (255, 0, 0, 255))
        self.add("split", split)
        image, _ = self.draw([self.texture("split", texCoord=[.5, 1, 0, 1])])
        self.assertEqual(image.getpixel((3, 8)), (0, 0, 255, 255))
        image, _ = self.draw([self.texture("split", texCoord=[0, 2, 0, 1])])
        self.assertEqual(image.getpixel((13, 8))[3], 0)
        self.assertEqual(image.getpixel((2, 8))[3], 255)
        image, _ = self.draw([self.texture("split", texCoord=[0, 1, -1, 1])])
        self.assertEqual(image.getpixel((8, 2))[3], 0)
        self.assertEqual(image.getpixel((8, 13))[3], 255)

    def test_rotation_is_about_center(self):
        quad = Image.new("RGBA", (16, 16))
        colours = {(0, 0): (255, 0, 0, 255), (1, 0): (0, 255, 0, 255),
                   (0, 1): (0, 0, 255, 255), (1, 1): (255, 255, 0, 255)}
        for x in range(16):
            for y in range(16): quad.putpixel((x, y), colours[(x // 8, y // 8)])
        self.add("quad", quad)
        image, _ = self.draw([self.texture("quad", rotation=math.pi / 2, filter="nearest")])
        self.assertEqual(image.getpixel((3, 3)), colours[(1, 0)])
        self.assertEqual(image.getpixel((12, 3)), colours[(1, 1)])
        self.assertEqual(image.getpixel((3, 12)), colours[(0, 0)])

    def test_mask_uses_its_world_bounds_not_each_texture_tile(self):
        mask = Image.new("RGBA", (16, 16), (255, 255, 255, 255))
        for x in range(8):
            for y in range(16): mask.putpixel((x, y), (255, 255, 255, 0))
        self.add("mask", mask)
        tex = self.texture("red", masks=[dict(asset="mask", u0=0, v0=0, u1=1, v1=1)])
        tex["u1"] = .5
        image, _ = self.draw([tex])
        self.assertEqual(image.getpixel((6, 8))[3], 0)
        tex["u0"], tex["u1"] = .5, 1
        image, _ = self.draw([tex])
        self.assertEqual(image.getpixel((12, 8)), (255, 0, 0, 255))

    def test_multiple_masks_multiply_without_losing_alpha(self):
        self.add("half", Image.new("RGBA", (16, 16), (255, 255, 255, 128)))
        tex = self.texture("red", masks=[dict(asset="half"), dict(asset="half")])
        image, _ = self.draw([tex])
        self.assertTrue(63 <= image.getpixel((8, 8))[3] <= 65)

    def test_view_clipping_and_crop_do_not_bleed_beyond_rectangle(self):
        tex = self.texture("red", texCoord=[.25, .75, .25, .75]); tex["u1"] = .5
        image, _ = self.draw([tex])
        self.assertEqual(image.getpixel((12, 8))[3], 0)
        tex["u0"] = -.5
        image, _ = self.draw([tex])
        self.assertEqual(image.getpixel((3, 8))[3], 255)

    def test_missing_art_and_transparency_are_failures_not_passes(self):
        _, report = self.draw([self.texture("absent")])
        self.assertEqual(report["findings"][0]["code"], "missing-texture")
        tex = self.texture("red"); tex["u1"] = .5
        _, report = self.draw([tex], assertions={"maxTransparentFraction": .1})
        self.assertIn("unexpected-transparency", [f["code"] for f in report["findings"]])

    def test_asset_hash_and_path_provenance_enforced(self):
        self.assets["red"]["sha256"] = "0" * 64
        self.manifest.write_text(json.dumps({"schema": 1, "assets": self.assets}))
        with self.assertRaisesRegex(render.LabError, "hash mismatch"): render.Assets(self.manifest).get("red")
        self.assets["red"]["file"] = "../escape.png"
        self.manifest.write_text(json.dumps({"schema": 1, "assets": self.assets}))
        with self.assertRaisesRegex(render.LabError, "escapes cache"): render.Assets(self.manifest).get("red")

    def test_cumulative_decoded_source_budget(self):
        previous = render.MAX_DECODED_PIXELS
        try:
            render.MAX_DECODED_PIXELS = 300
            assets = render.Assets(self.manifest)
            assets.get("red")
            assets.get("red")  # a cached reference does not spend the budget twice
            with self.assertRaisesRegex(render.LabError, "cumulative decoded"):
                assets.get("blue")
            self.assertEqual(assets.decoded_pixels, 256)
        finally:
            render.MAX_DECODED_PIXELS = previous

    def test_color_veil_respects_native_draw_layer_order(self):
        foreground = self.texture("red", drawLayer="ARTWORK", order=1)
        background = self.texture("unused", color=[0, 0, 1, 1], drawLayer="BACKGROUND", order=99)
        image, report = self.draw([foreground, background])
        self.assertEqual(image.getpixel((8, 8)), (255, 0, 0, 255))
        self.assertEqual(report["missingAssets"], [])

    def test_actual_owned_mask_is_resolved_and_hash_recorded(self):
        assets = render.Assets(own_root=REPO / "!!!TwichUI")
        key = "!!!TwichUI/media/textures/map-feather-round.tga"
        image = assets.get(key)
        self.assertIsNotNone(image)
        self.assertEqual(assets.used[key]["kind"], "twichui-mask")
        self.assertIsNone(assets.get("!!!TwichUI/media/textures/map-../../Core.lua"))

    def test_invalid_geometry_and_resource_budgets_rejected(self):
        for bad in (float("nan"), float("inf"), True):
            tex = self.texture("red"); tex["u0"] = bad
            with self.assertRaises(render.LabError): render.validate_export({"schema": 1, "scenes": [self.scene([tex])]})
        scene = self.scene([]); scene["width"], scene["height"] = 4096, 4096
        with self.assertRaises(render.LabError): render.validate_export({"schema": 1, "scenes": [scene]})
        scene = self.scene([]); scene["id"] = "../escape"
        with self.assertRaises(render.LabError): render.validate_export({"schema": 1, "scenes": [scene]})

    def test_before_after_metrics_and_alpha_sequence_checks(self):
        before, _ = self.draw([self.texture("red")])
        after, _ = self.draw([self.texture("blue")])
        result, difference = render.compare_images(before, after)
        self.assertEqual(result["changedFraction"], 1)
        self.assertGreater(result["meanChannelDifference"], 100)
        self.assertIsNotNone(difference)
        self.assertEqual(difference.getpixel((8, 8))[3], 255, "RGB differences are visibly opaque")
        a = self.scene([self.texture("red")], metadata={"sequence": "test"})
        b = self.scene([self.texture("red")], metadata={"sequence": "test"}); b["id"] = "second"
        b["textures"][0]["alpha"] = 0
        self.assertEqual(maprun.transition_checks([a, b])[0]["code"], "abrupt-alpha-step")
        b["textures"] = []
        finding = maprun.transition_checks([a, b])[0]
        self.assertTrue(finding["disappeared"])
        b["view"] = dict(u0=2, v0=2, u1=3, v1=3)
        self.assertEqual(maprun.transition_checks([a, b]), [], "offscreen culling is legitimate")


class Contracts(unittest.TestCase):
    def report(self):
        return {"schema": 1, "kind": "twichui-map-diagnostics", "id": "MAP1-test", "events": [],
                "current": {"view": {"viewRect": [0, 0, 1, 1], "viewportWidth": 64, "viewportHeight": 64,
                    "nativeMap": 1429, "center": {"u": .5, "v": .5, "zoom": 1}},
                    "terrain": {"level": 6, "textures": [{"fileId": 123, "bounds": [0, 0, 1, 1], "alpha": .7}]}}}

    def test_diagnostic_import_is_deterministic_partial_not_native_replay(self):
        data = self.report()
        first = diagnostics.import_report(data)
        self.assertEqual(first, diagnostics.import_report(data))
        request, state = first
        self.assertFalse(request["replay"]["nativeClientConfirmed"])
        self.assertTrue(state["provenance"]["partial"])
        self.assertEqual(state["scenes"][0]["textures"][0]["fileId"], 123)
        self.assertIn("parent-layer fades are unknown", " ".join(state["provenance"]["limitations"]))
        data["synthetic"] = True
        self.assertTrue(diagnostics.import_report(data)[1]["provenance"]["synthetic"])
        render.validate_export(state)

    def test_withheld_geometry_and_wrong_schema_refused(self):
        data = self.report(); del data["current"]["view"]["viewRect"]
        with self.assertRaisesRegex(render.LabError, "withheld"): diagnostics.import_report(data)
        data["schema"] = 2
        with self.assertRaisesRegex(render.LabError, "schema 1"): diagnostics.import_report(data)

    def test_piece_checksums_and_order(self):
        text = json.dumps(self.report(), ensure_ascii=False)
        whole = f"{zlib.adler32(text.encode()):08x}"
        bodies = [text[:100], text[100:]]
        pieces = [f"TWICHUI-DIAGNOSTICS piece {i}/2 of MAP TEST | report {len(text.encode())} bytes, adler32 {whole} | this piece adler32 {zlib.adler32(body.encode()):08x} | join\n{body}"
                  for i, body in enumerate(bodies, 1)]
        self.assertEqual(diagnostics.join_pieces(pieces), text)
        with self.assertRaises(render.LabError): diagnostics.join_pieces(list(reversed(pieces)))
        with self.assertRaises(render.LabError): diagnostics.join_pieces([pieces[0], pieces[1] + "x"])

    def test_local_asset_probe_does_not_invent_game_storage(self):
        self.assertFalse(probe()["available"])
        self.assertIn("local WoW Forever .build.info", probe()["missing"])
        self.assertEqual(referenced_ids({"scenes": [{"textures": [{"fileId": 123}, {"fileId": False}, {"asset": "x"}]}]}), [123])

    def test_preprocessing_preserves_alpha_and_builds_edge_gutter(self):
        image = Image.new("RGBA", (16, 16), (100, 40, 20, 128))
        self.assertEqual(preprocess.alpha_mask(image).getpixel((0, 0)), 128)
        self.assertEqual(preprocess.lod(image, 8).size, (8, 8))
        expanded = preprocess.gutter(image, 2)
        self.assertEqual(expanded.size, (20, 20))
        self.assertEqual(expanded.getpixel((0, 0)), image.getpixel((0, 0)))
        self.assertEqual(preprocess.identity(expanded), preprocess.identity(expanded.copy()))
        with tempfile.TemporaryDirectory(prefix="maplab-preprocess-test-") as folder:
            preprocess.measure(image, Path(folder), "owned test fixture")
            with Image.open(Path(folder) / "source-alpha.png") as saved:
                self.assertEqual(saved.convert("RGBA").getpixel((0, 0))[3], 128, "mask payload is alpha, not opaque luminance")


if __name__ == "__main__":
    unittest.main()
