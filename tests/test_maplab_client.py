"""Collector/transport/API-bridge contracts. Fixtures are NOT game artwork."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools/maplab"))
import clientdata as cd
import clientinput as ci
import collect
import run as lab


class Table:
    def __init__(self, rows=(), relations=None):
        self.data = list(rows)
        self.sections = [(len(self.data), None, None, None, [], None, relations or {})]

    def rows(self):
        return iter(self.data)


def bits(v):
    return struct.unpack("<I", struct.pack("<f", v))[0]


def fixture_tables():
    ids = [(947, 0, 1), (1415, 947, 2), (1414, 947, 2), (1434, 1415, 3),
           (1458, 1415, 3), (1429, 1415, 3), (1436, 1415, 3)]
    tables = {name: Table() for name in cd.TABLES}
    tables["UiMap"] = Table((ui, [0, 0, parent, 0, 0, kind]) for ui, parent, kind in ids)
    assigns = []
    def assignment(ui, cont, region, lo=(0, 0), hi=(1, 1)):
        rid = len(assigns) + 1
        assigns.append((rid, [[bits(v) for v in lo], [bits(v) for v in hi],
            [bits(v) for v in region], rid, ui, 0, cont, 0, 0, 0, 0]))
    continent = (-20000, -22500, 0, 10000, 22500, 0)
    assignment(947, 0, continent, (.6, .15), (.9, .45))
    assignment(947, 1, continent, (.1, .2), (.4, .5))
    assignment(1415, 0, continent); assignment(1414, 1, continent)
    assignment(1434, 0, (-15000, -2000, 0, -11000, 4000, 0))
    assignment(1458, 0, (1000, -100, 0, 2000, 1400, 0))
    assignment(1429, 0, (-10000, -1500, 0, -8000, 1500, 0), (.25, .25), (.75, .75))
    assignment(1436, 0, (-12000, 2000, 0, -8000, 8000, 0))
    tables["UiMapAssignment"] = Table(assigns)
    tables["UiMapArt"] = Table((100 + i, [0, 0, 1]) for i in range(len(ids)))
    tables["UiMapXMapArt"] = Table([(i + 1, [0, 100 + i]) for i in range(len(ids))],
                                         {i: ui for i, (ui, _, _) in enumerate(ids)})
    tables["UiMapArtStyleLayer"] = Table([(1, [0, 1002, 668, 256, 256, 0, 0, 0])], {0: 1})
    tile_rows, rel = [], {}
    for i in range(len(ids)):
        for r in range(3):
            for c in range(4):
                rel[len(tile_rows)] = 100 + i
                tile_rows.append((len(tile_rows) + 1, [r, c, 0, 10000000 + i * 12 + r * 4 + c]))
    tables["UiMapArtTile"] = Table(tile_rows, rel)
    return tables


def fixture_input():
    maps, reveal, point = cd.model(fixture_tables())
    data = dict(schema=1, kind="twichui-maplab-client-input", synthetic=True, clientBuild="1.60.1.70938",
        maps=list(maps.values()), reveal=reveal, minimap={"0": [], "1": []}, scenarios=cd.scenarios(maps, point),
        numericSources={name: hashlib.sha256((REPO / name).read_bytes()).hexdigest()
                        for name in ("!!!TwichUI/map/Data.lua", "!!!TwichUI/map/LocalData.lua")},
        tables={name: dict(fileId=fid, layout=f"{layout:08X}", tableHash=f"{table_hash:08X}")
                for name, (fid, layout, table_hash) in cd.TABLES.items()})
    return data, point


class ClientContracts(unittest.TestCase):
    def test_forever_subfolder_and_active_installed_product(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / "Data/data").mkdir(parents=True); (root / "_forever_").mkdir()
            (root / ".build.info").write_text(
                "Active!DEC:1|Product!STRING:0|Version!STRING:0\n"
                "0|wow_forever|1.60.1.70532\n1|wow_forever|1.60.1.70938\n1|wow|12.1.5.70938\n", encoding="utf-8-sig")
            found, product = collect.installation(root / "_forever_")
            self.assertEqual((found, product), (root.resolve(), "wow_forever"))
            self.assertEqual(collect.casc._build_info(found, product)["Version"], "1.60.1.70938")
            # Folder spelling never manufactures a product absent from metadata.
            (root / ".build.info").write_text("Product!STRING:0|Version!STRING:0\nactual_installed_id|1.60.1.70938\n")
            self.assertEqual(collect.installation(root / "_forever_")[1], "actual_installed_id")

    def test_product_ambiguity_and_explicit_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / "Data/data").mkdir(parents=True)
            (root / ".build.info").write_text("Product!STRING:0|Version!STRING:0|Active!DEC:1\n"
                                             "wow|12.1.5.70938|1\nwow_classic|1.15.7.70938|1\n")
            with self.assertRaisesRegex(cd.ClientInputError, "Multiple products found: wow, wow_classic"):
                collect.installation(root)
            with self.assertRaisesRegex(cd.ClientInputError, "Available products: wow, wow_classic"):
                collect.installation(root, "wow_forever")
            self.assertEqual(collect.installation(root, "wow_classic")[1], "wow_classic")

    def test_partial_ui_region_extrapolates_complete_art(self):
        maps, _, _ = cd.model(fixture_tables())
        self.assertEqual((maps[1429]["xN"], maps[1429]["yW"], maps[1429]["W"], maps[1429]["H"]),
                         (-7000, 3000, 6000, 4000))

    def test_unknown_schema_and_conflicting_assignments_refused(self):
        bad = type("BadSchema", (), {"layout_hash": 0, "table_hash": 0})()
        with self.assertRaisesRegex(cd.ClientInputError, "Unsupported"):
            cd.schema(bad, "UiMap")
        tables = fixture_tables()
        rid, columns = tables["UiMapAssignment"].data[4]
        other = list(columns); other[2] = list(columns[2]); other[2][0] = bits(-15500)
        tables["UiMapAssignment"].data.append((100, other))
        with self.assertRaisesRegex(cd.ClientInputError, "Conflicting"):
            cd.model(tables)

    def test_section_local_relations_and_copy_rows(self):
        t = Table([(1, [11]), (2, [22]), (3, [11]), (4, [44])])
        t.sections = [(2, None, None, None, [(3, 1)], None, {0: 100, 1: 200}),
                      (1, None, None, None, [], None, {0: 400})]
        self.assertEqual([fk for _, _, fk in cd.related_rows(t)], [100, 200, 100, 400])

    def test_collector_reads_only_requested_texture_and_preserves_installation(self):
        data, _ = fixture_input()
        class Storage:
            version = "1.60.1.70938"
            def __init__(self, *args, **kwargs): self.reads = []; self.closed = False
            def read(self, key): self.reads.append(key); return b"BLP2owned transport fixture, not game artwork"
            def close(self): self.closed = True
        storage = Storage()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); wow = root / "game"; (wow / "Data/data").mkdir(parents=True)
            (wow / ".build.info").write_text("Product!STRING:0|Version!STRING:0\nwow_forever|1.60.1.70938\n")
            before = {p.relative_to(wow): p.read_bytes() for p in wow.rglob("*") if p.is_file()}
            with patch.object(collect, "read_tables", return_value=({}, data["tables"])), \
                 patch.object(collect, "model", return_value=({m["id"]: m for m in data["maps"]}, {}, lambda *a: (0, 0))), \
                 patch.object(collect, "minimap", return_value={"0": [], "1": []}), \
                 patch.object(collect, "scenarios", return_value=data["scenarios"]), \
                 patch.object(collect, "candidate_ids", return_value=[123]), contextlib.redirect_stdout(io.StringIO()):
                paths = collect.collect(wow, root / "private.zip", storage_factory=lambda *a, **k: storage)
            self.assertEqual(storage.reads, [123]); self.assertTrue(storage.closed)
            self.assertEqual(before, {p.relative_to(wow): p.read_bytes() for p in wow.rglob("*") if p.is_file()})
            decoded = root / "input"; decoded.mkdir()
            imported, manifest = ci.unpack(paths, decoded)
            self.assertEqual(imported["clientBuild"], storage.version)
            self.assertEqual(imported["product"], "wow_forever")
            self.assertTrue((decoded / "assets/123.blp").is_file())
            self.assertEqual(set(json.loads(manifest.read_text())["assets"]), {"123"})

    def test_zip_path_escape_and_data_injection_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); path = root / "bad.zip"
            with zipfile.ZipFile(path, "w") as archive: archive.writestr("../WTF/account.txt", "do not extract")
            with self.assertRaisesRegex(ci.LabError, "Unexpected"):
                ci.unpack([path], root / "out")
            self.assertFalse((root / "WTF").exists())
            data, _ = fixture_input(); data["maps"][0]["id"] = "1; os.execute('bad')"
            with self.assertRaises(ci.LabError): ci.write_tables(data, root / "data.tsv")

    def test_small_valid_zip_parts_reassemble_and_missing_part_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source = root / "source"; (source / "assets").mkdir(parents=True)
            data, _ = fixture_input(); (source / "client.json").write_text(json.dumps(data))
            records = {}
            for file_id in (123, 124, 125):
                raw = b"BLP2" + os.urandom(10000)
                (source / f"assets/{file_id}.blp").write_bytes(raw)
                records[str(file_id)] = dict(file=f"{file_id}.blp", clientBuild=data["clientBuild"],
                    sha256=hashlib.sha256(raw).hexdigest())
            (source / "assets/manifest.json").write_text(json.dumps(dict(schema=1, clientBuild=data["clientBuild"], assets=records)))
            with patch.object(collect, "PART_BYTES", 24 * 1024):
                paths = collect.pack(source, root / "input.zip")
            self.assertGreater(len(paths), 1)
            self.assertTrue(all(path.stat().st_size < 24 * 1024 for path in paths))
            decoded, manifest = ci.unpack(paths, root / "decoded")
            self.assertEqual(len(json.loads(manifest.read_text())["assets"]), 3)
            with self.assertRaisesRegex(ci.LabError, "Missing"):
                ci.unpack(paths[1:], root / "incomplete")

    def test_source_kit_needs_only_python_standard_library(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); kit = collect.make_kit(root / "collector.zip")
            with zipfile.ZipFile(kit) as archive:
                self.assertFalse(any(name.endswith((".blp", ".png", ".tga")) for name in archive.namelist()))
                archive.extractall(root / "kit")  # source ZIP generated by this test, never an imported user ZIP
            process = subprocess.run([sys.executable, "-S", str(root / "kit/tools/maplab/collect.py"), "--help"],
                                     capture_output=True, text=True, timeout=10)
            self.assertEqual(process.returncode, 0, process.stderr)

    @unittest.skipUnless(shutil.which("lua5.1"), "existing Lua environment not activated")
    def test_table_input_runs_production_lua_without_synthetic_regression_catalog(self):
        data, _ = fixture_input()
        state, evidence = lab.production_export(data)
        self.assertEqual(len(state["scenes"]), 12)
        self.assertTrue(state["provenance"]["synthetic"], "owned unit fixture must never claim real artwork")
        self.assertFalse(state["provenance"]["nativeApiCaptured"])
        self.assertNotIn(5001, [t.get("fileId") for s in state["scenes"] for t in s["textures"]])
        self.assertTrue(any(s["id"] == "undercity-48" for s in state["scenes"]))
        self.assertIn("CLIENT-TABLE PRODUCTION", " ".join(evidence["stdoutTail"]))


if __name__ == "__main__":
    unittest.main()
