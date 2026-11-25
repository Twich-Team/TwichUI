"""TwichUI Fishing's heads-up artwork (TwichUI_Fishing/media, built by tools/make_fishing_art.py from assets/fishing).

Every file is the TGA the game reads (uncompressed 32-bit, eight alpha bits, power-of-two sides); its size and painted area are
what TwichUI_Fishing/Hud.lua says (H.ART), so texture coordinates land on the painting; a rebuild from the sources gives the
same bytes; the sample icons baked into the pack's notification art are gone (the well is transparent); and every texture the
Lua files name exists. It cannot show how the game draws them.
"""
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "TwichUI_Fishing" / "media"
HUD = ROOT / "TwichUI_Fishing" / "Hud.lua"


def read_tga(path):
    data = path.read_bytes()
    idlen, cmap, kind = data[0], data[1], data[2]
    w = data[12] | (data[13] << 8)
    h = data[14] | (data[15] << 8)
    bpp, desc = data[16], data[17]
    return {"kind": kind, "cmap": cmap, "w": w, "h": h, "bpp": bpp, "alphaBits": desc & 15, "size": len(data),
            "pixels": data[18 + idlen:]}


def pixel(t, x, y):
    """RGBA at (x, y) from the top-left (the files are stored bottom-up)."""
    row = t["h"] - 1 - y
    i = (row * t["w"] + x) * 4
    b, g, r, a = t["pixels"][i:i + 4]
    return r, g, b, a


LINE = re.compile(r'^\s*(?:\["([\w-]+)"\]|(\w+)) = \{ file = "([^"]+)", (.*)\},?\s*$')


def art_table():
    """H.ART from Hud.lua: name -> { file, w, h, cw, ch, well? } (one entry per line)."""
    out = {}
    for line in HUD.read_text().splitlines():
        m = LINE.match(line)
        if not m:
            continue
        name, rest = m.group(1) or m.group(2), m.group(4)
        entry = {"file": m.group(3)}
        well = re.search(r"well = \{ ([\d., ]+) \}", rest)
        if well:
            entry["well"] = [float(v) for v in well.group(1).split(",")]
            rest = rest[:well.start()]
        entry.update({k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", rest)})
        out[name] = entry
    return out


class FishingArt(unittest.TestCase):
    def test_files_are_game_textures(self):
        files = sorted(MEDIA.glob("*.tga"))
        self.assertEqual(len(files), 29)
        for p in files:
            t = read_tga(p)
            with self.subTest(p.name):
                self.assertEqual((t["kind"], t["cmap"], t["bpp"], t["alphaBits"]), (2, 0, 32, 8))
                for side in (t["w"], t["h"]):
                    self.assertTrue(side & (side - 1) == 0 and side <= 512, "power-of-two side, at most 512")
                self.assertEqual(t["size"], 18 + t["w"] * t["h"] * 4)

    def test_sizes_match_hud_lua(self):
        art = art_table()
        self.assertGreaterEqual(len(art), 14)
        for name, a in art.items():
            t = read_tga(MEDIA / (a["file"] + ".tga"))
            with self.subTest(name):
                self.assertEqual((t["w"], t["h"]), (a["w"], a["h"]))
                self.assertLessEqual(a["cw"], a["w"])
                self.assertLessEqual(a["ch"], a["h"])
                # nothing painted outside the area the coordinates use
                for x in range(int(a["cw"]), t["w"], 7):
                    for y in range(0, t["h"], 7):
                        self.assertEqual(pixel(t, x, y)[3], 0)

    def test_sample_icons_cut_out(self):
        art = art_table()
        for name in ("toast", "treasure", "iconframe"):
            a = art[name]
            t = read_tga(MEDIA / (a["file"] + ".tga"))
            well = [int(v) for v in a["well"]]
            cx, cy = (well[0] + well[2]) // 2, (well[1] + well[3]) // 2
            with self.subTest(name):
                for dx in range(-20, 21, 5):
                    for dy in range(-20, 21, 5):
                        self.assertEqual(pixel(t, cx + dx, cy + dy)[3], 0, "the well is transparent: no baked sample icon")
                self.assertGreater(pixel(t, well[0] - 4, cy)[3], 200, "the bronze frame around it is kept")

    def test_icon_frame_is_hollow_and_alone(self):
        t = read_tga(MEDIA / "iconframe.tga")
        self.assertEqual(pixel(t, 32, 32)[3], 0, "the well is empty: the item's own icon shows")
        self.assertGreater(pixel(t, 2, 32)[3], 200, "the bronze rim is kept")
        self.assertEqual(pixel(t, 63, 0)[3], 0, "no band outside the frame's chamfered corner")

    def test_logo_is_the_pack_logo(self):
        t = read_tga(MEDIA / "logo.tga")
        self.assertEqual((t["w"], t["h"]), (512, 256))
        self.assertGreater(pixel(t, 240, 98)[3], 200)

    def test_fill_has_rounded_ends(self):
        t = read_tga(MEDIA / "castfill.tga")
        self.assertEqual(pixel(t, 0, 0)[3], 0, "a rounded end, not a square corner")
        self.assertGreater(pixel(t, 0, 9)[3], 0)
        self.assertGreater(pixel(t, 178, 9)[3], 200)
        r, g, b, _ = pixel(t, 178, 9)
        self.assertTrue(r > g > b and b < 140, "an amber tone, not the pack's flat yellow")

    def test_rebuild_is_identical(self):
        with tempfile.TemporaryDirectory() as out:
            subprocess.run([sys.executable, str(ROOT / "tools" / "make_fishing_art.py"), "--out", out], check=True,
                           capture_output=True)
            for p in sorted(MEDIA.glob("*.tga")):
                with self.subTest(p.name):
                    self.assertEqual((Path(out) / p.name).read_bytes(), p.read_bytes())

    def test_every_named_texture_exists(self):
        art = art_table()
        names = set()
        for lua in (ROOT / "TwichUI_Fishing").glob("*.lua"):
            names.update(re.findall(r"H\.Texture\(\s*[\w.]+,\s*\"(\w+)\"", lua.read_text()))
        self.assertTrue(names)
        for n in names:
            with self.subTest(n):
                self.assertIn(n, art)
                self.assertTrue((MEDIA / (art[n]["file"] + ".tga")).is_file())


if __name__ == "__main__":
    unittest.main()
