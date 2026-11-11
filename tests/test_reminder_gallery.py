"""tools/make_reminder_gallery.py: the Reminders artwork library is a reproducible build of the two painted sheets in docs/reminders-revision/.

Checks the manifest (stable unique ids, categories, names, keywords, crop rectangles inside their sheet, every picture on a sheet either catalogued or
rejected with a reason), every individual source image (square RGBA, real transparency, a clear edge, the picture centred with its margin) and every
runtime texture, that ArtData.lua is what the manifest says, and that the tool rebuilds the manifest, ArtData.lua and a sample of the pictures byte for byte.

Run (from tests/): python3 -B -m unittest -q test_reminder_gallery
"""
import json
import re
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from make_map_tool_icons import read_png  # noqa: E402

ASSETS = ROOT / "assets" / "reminder-gallery"
MEDIA = ROOT / "!!!TwichUI" / "media" / "reminders" / "gallery"
ARTDATA = ROOT / "!!!TwichUI" / "reminders" / "ArtData.lua"
TOOL = ROOT / "tools" / "make_reminder_gallery.py"
SAMPLE = ("reminder-lion-shield", "reminder-expiring-buff", "reminder-fishing-rod", "reminder-low-mana")


def png_header(path):
    d = Path(path).read_bytes()[:33]
    assert d[:8] == b"\x89PNG\r\n\x1a\n", path
    w, h, depth, ctype = struct.unpack(">IIBB", d[16:26])
    return w, h, depth, ctype


def tga(path):
    d = Path(path).read_bytes()
    return d, d[12] + d[13] * 256, d[14] + d[15] * 256


class Gallery(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = json.loads((ASSETS / "manifest.json").read_text())
        cls.art = cls.doc["artwork"]

    def test_manifest_shape(self):
        d = self.doc
        self.assertEqual(d["version"], 1)
        self.assertEqual(len(d["categories"]), 6)
        ids = [a["id"] for a in self.art]
        self.assertEqual(len(ids), len(set(ids)), "ids are unique")
        self.assertGreaterEqual(len(ids), 60)
        known = set(ids) | {l["id"] for l in d["legacy"]}
        for a in self.art:
            i = a["id"]
            self.assertRegex(i, r"^reminder-[a-z0-9-]+$", i)
            self.assertLessEqual(len(i), 40, i)
            self.assertIn(a["category"], d["categories"], i)
            self.assertTrue(a["name"].strip() and len(a["name"]) <= 40, i)
            self.assertGreater(len(a["description"]), 8, i)
            self.assertGreaterEqual(len(a["keywords"]), 3, i)
            for k in a["keywords"]:
                self.assertRegex(k, r"^[a-z0-9]+$", i + ": keyword " + k)
            for r in a["related"]:
                self.assertIn(r, known, i + ": related " + r)
                self.assertNotEqual(r, i)
            self.assertEqual(a["source"], "assets/reminder-gallery/%s.png" % i)
            self.assertEqual(a["texture"], "media/reminders/gallery/%s" % i)
        names = [a["name"] for a in self.art]
        self.assertEqual(len(names), len(set(names)), "display names are distinct")
        for cat in d["categories"]:
            self.assertTrue(any(a["category"] == cat for a in self.art), cat + " is not empty")

    def test_crops_lie_inside_their_sheets_and_nothing_is_unaccounted_for(self):
        sizes = {}
        for sheet, rel in self.doc["sheets"].items():
            w, h, depth, ctype = png_header(ROOT / rel)
            self.assertEqual((depth, ctype), (8, 6), rel + " keeps its alpha channel")
            sizes[int(sheet)] = (w, h)
        self.assertEqual(sizes, {1: (1536, 1024), 2: (1024, 1536)})
        taken = set()
        for a in self.art:
            c, (w, h) = a["crop"], sizes[a["sheet"]]
            self.assertTrue(c["x"] >= 0 and c["y"] >= 0 and c["width"] > 20 and c["height"] > 20, a["id"])
            self.assertTrue(c["x"] + c["width"] <= w and c["y"] + c["height"] <= h, a["id"] + ": crop inside the sheet")
            pos = (a["sheet"], a["position"]["row"], a["position"]["column"])
            self.assertNotIn(pos, taken, "one picture per position")
            taken.add(pos)
        for r in self.doc["rejected"]:
            pos = (r["sheet"], r["row"], r["col"])
            self.assertNotIn(pos, taken)
            taken.add(pos)
            self.assertTrue(r["reason"] and r["duplicate_of"], "a rejection says why")
        self.assertEqual(sum(1 for t in taken if t[0] == 1), 51, "sheet 1: 51 pictures, each catalogued or rejected")
        self.assertEqual(sum(1 for t in taken if t[0] == 2), 24, "sheet 2: 24 pictures, each catalogued or rejected")

    def test_source_images(self):
        side = self.doc["canvas"]["source"]
        for a in self.art:
            path = ROOT / a["source"]
            self.assertEqual(png_header(path)[:2], (side, side), a["id"])
            w, h, px, has_alpha = read_png(path)
            self.assertTrue(has_alpha, a["id"])
            x0, y0, x1, y1 = w, h, -1, -1
            solid = clear = 0
            for y in range(h):
                row = px[y]
                for x in range(w):
                    al = row[x * 4 + 3]
                    if al > 8:
                        x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
                    if al >= 250:
                        solid += 1
                    elif al == 0:
                        clear += 1
                    if (x in (0, w - 1) or y in (0, h - 1)) and al:
                        self.fail(a["id"] + ": paint on the edge of the file")
            self.assertGreater(solid, 0.03 * w * h, a["id"] + ": not empty")
            self.assertGreater(clear, 0.2 * w * h, a["id"] + ": real transparency")
            longer = max(x1 + 1 - x0, y1 + 1 - y0)
            self.assertTrue(0.60 <= longer / side <= 0.80, "%s: the picture fills %.0f%% of its canvas" % (a["id"], 100.0 * longer / side))
            self.assertLessEqual(abs((x0 + x1 + 1) / 2 - side / 2), side * 0.05, a["id"] + ": centred across")
            self.assertLessEqual(abs((y0 + y1 + 1) / 2 - side / 2), side * 0.05, a["id"] + ": centred down")

    def test_runtime_textures(self):
        large, small = self.doc["canvas"]["large"], self.doc["canvas"]["small"]
        for a in self.art:
            for suffix, side in (("", large), ("-small", small)):
                d, w, h = tga(MEDIA / (a["id"] + suffix + ".tga"))
                self.assertEqual((w, h), (side, side), a["id"] + suffix)
                self.assertEqual((d[2], d[16], d[17]), (2, 32, 8), a["id"] + suffix)
                self.assertEqual(len(d), 18 + w * h * 4, a["id"] + suffix)
                self.assertTrue(any(d[18 + i] for i in range(3, len(d) - 18, 4)), a["id"] + suffix + ": not empty")
        extra = {p.name for p in MEDIA.glob("*.tga")} - {a["id"] + s + ".tga" for a in self.art for s in ("", "-small")}
        self.assertEqual(extra, set(), "no stray textures")

    def test_artdata_matches_the_manifest(self):
        text = ARTDATA.read_text()
        self.assertIn("GENERATED", text)
        self.assertEqual(re.findall(r'^        \{ "(reminder-[a-z0-9-]+)", ', text, re.M), [a["id"] for a in self.art])
        for l in self.doc["legacy"]:
            self.assertIn('{ "%s", "%s", "%s"' % (l["kind"], l["id"], l["name"]), text)
        self.assertIn("large = %d, small = %d" % (self.doc["canvas"]["large"], self.doc["canvas"]["small"]), text)

    def test_contact_sheet_is_shipped(self):
        self.assertEqual(png_header(ROOT / "docs" / "reminders-art" / "contact-sheet.png")[2:], (8, 2))


class Rebuild(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.run_result = subprocess.run([sys.executable, "-I", "-B", str(TOOL), "--out-root", cls.tmp.name, "--only", *SAMPLE],
                                        capture_output=True, text=True, cwd=str(ROOT))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_tool_ran(self):
        self.assertEqual(self.run_result.returncode, 0, self.run_result.stderr)
        self.assertIn("rejected", self.run_result.stdout)

    def test_manifest_and_artdata_are_what_the_tool_builds(self):
        out = Path(self.tmp.name)
        self.assertEqual((out / "assets" / "reminder-gallery" / "manifest.json").read_bytes(), (ASSETS / "manifest.json").read_bytes())
        self.assertEqual((out / "!!!TwichUI" / "reminders" / "ArtData.lua").read_bytes(), ARTDATA.read_bytes())

    def test_sample_pictures_are_what_the_tool_builds(self):
        out = Path(self.tmp.name)
        for i in SAMPLE:
            self.assertEqual((out / "assets" / "reminder-gallery" / (i + ".png")).read_bytes(), (ASSETS / (i + ".png")).read_bytes(), i + ".png")
            for suffix in ("", "-small"):
                name = i + suffix + ".tga"
                self.assertEqual((out / "!!!TwichUI" / "media" / "reminders" / "gallery" / name).read_bytes(), (MEDIA / name).read_bytes(), name)


if __name__ == "__main__":
    unittest.main()
