"""The complete shipped art contract, plus localized/reordered native filters."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets/auction-subcategories/manifest.json"


class CategoryArtTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads(MANIFEST.read_text())

    def test_every_picture_is_shipped_and_distinct(self):
        pictures = self.manifest["icons"]
        self.assertEqual(len(pictures), 143)
        self.assertEqual(len({p["id"] for p in pictures}), len(pictures))
        signatures = set()
        for icon in pictures:
            for suffix, side in (("", 64), ("-small", 32)):
                data = (ROOT / "!!!TwichUI/media/auction/categories" / (icon["id"] + suffix + ".tga")).read_bytes()
                header = struct.unpack("<BBBHHBHHHHBB", data[:18])
                self.assertEqual(header[2], 2, icon["id"])
                self.assertEqual(header[8:], (side, side, 32, 8), icon["id"])
                self.assertEqual(len(data), 18 + side * side * 4)
                alpha = data[21::4]
                self.assertEqual(min(alpha), 0)
                self.assertGreaterEqual(max(alpha), 240)
                self.assertGreater(sum(a > 128 for a in alpha), 30)
                border = list(alpha[:side]) + list(alpha[-side:]) + list(alpha[::side]) + list(alpha[side - 1::side])
                self.assertFalse(any(border), icon["id"] + " needs a transparent sampling margin")
                if not suffix:
                    digest = hashlib.sha256(data).digest()
                    self.assertNotIn(digest, signatures, icon["id"] + " reuses another picture")
                    signatures.add(digest)
        grid_cells = {(p["sheet"], p["cell"]) for p in pictures}
        self.assertEqual(len(grid_cells), len(pictures))

    def test_native_filter_contract(self):
        lua = shutil.which("lua5.1")
        self.assertIsNotNone(lua, "Lua 5.1 is required")
        script = ['TwichUI={Workshop={Text=function(s) return s end}}',
                  'dofile("TwichUI_Workshop/auction/Categories.lua")',
                  'local C=TwichUI.Workshop.AuctionCategories']
        for icon in self.manifest["icons"]:
            filters = icon.get("filters") or [dict(classID=icon["class"], subClassID=icon["subclass"],
                                                  **({"inventoryType": icon["inventory"]} if "inventory" in icon else {}))]
            values = ["{" + ",".join("%s=%d" % pair for pair in f.items()) + "}" for f in filters]
            node = '{depth=2,key="native:92.17.4",name="Translated category",filters={%s}}' % ",".join(values)
            script += ['do local n=%s; local want="auction:%s"' % (node, icon["id"]),
                       'assert(C.Art(n)==want, want..": "..tostring(C.Art(n)))',
                       'local first=n.filters[1];local reversed={};for i=#n.filters,1,-1 do reversed[#reversed+1]=n.filters[i] end',
                       'n.filters=reversed;n.key="native:3.1";n.name="Another language";assert(C.Art(n)==want)',
                       'assert(first.classID~=nil) end']
        script += [
            'assert(C.Art({depth=0,key="native:1",filters={{classID=2}}})=="npc:sword-and-shield")',
            'assert(C.Art({key="all"})=="auctionHouse")',
            'assert(C.Art({depth=2,filters={{classID=4,subClassID=1,inventoryType=5},{classID=4,subClassID=1,inventoryType=20}}})=="auction:cloth-chest")',
            'assert(C.Art({depth=1,filters={{classID=4,subClassID=0,inventoryType=2},{classID=4,subClassID=1,inventoryType=16},{classID=4,subClassID=6}}})=="auction:armor-misc")',
            'assert(C.Art({depth=1,filters={{classID=2,subClassID=999}}})=="npc:sword-and-shield")',
            'assert(C.Art({depth=1,filters={}})=="npc:balance-scales")',
            'print("PASSED all 143 art mappings, translated/reordered filters, robes, roots and unknowns")',
        ]
        result = subprocess.run([lua, "-"], input="\n".join(script), text=True, cwd=ROOT,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
