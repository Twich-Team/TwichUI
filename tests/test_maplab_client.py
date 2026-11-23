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
import bundle
import run as lab
import render


class Table:
    def __init__(self, rows=(), relations=None):
        self.data = list(rows)
        self.sections = [(len(self.data), None, None, None, [], None, relations or {})]

    def rows(self):
        return iter(self.data)


def bits(v):
    return struct.unpack("<I", struct.pack("<f", v))[0]


def blp_fixture(side=4, noisy=False):
    """Owned paletted pixels with 8-bit alpha; never game artwork."""
    pixels = side * side
    payload = os.urandom(pixels * 2) if noisy else b"\x00" * pixels + b"\xff" * pixels
    header = bytearray(148)
    struct.pack_into("<4sI4BII", header, 0, b"BLP2", 1, 1, 8, 0, 0, side, side)
    palette = b"\x20\x40\x80\xff" * 256
    struct.pack_into("<I", header, 20, len(header) + len(palette))
    struct.pack_into("<I", header, 84, len(payload))
    return bytes(header) + palette + payload


def fixture_tables():
    ids = [(947, 0, 1), (1415, 947, 2), (1414, 947, 2), (1434, 1415, 3),
           (1458, 1415, 3), (1429, 1415, 3), (1436, 1415, 3), (1411, 1414, 3), (1420, 1415, 3)]
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
    assignment(1411, 1, (-2000, -6000, 0, 3000, -4000, 0))
    assignment(1420, 0, (0, -2000, 0, 4000, 2000, 0))
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


def fixture_bundle(missing=False):
    """Complete schema-2 transport with explicit synthetic pixel provenance."""
    data, _ = fixture_input()
    data.update(product="wowf", candidateTextureIds=[123, 124] if missing else [123])
    raw = blp_fixture()
    sha = bundle.digest(raw)
    manifest = dict(schema=2, kind="twichui-maplab-artwork-bundle",
        tool=dict(name=bundle.TOOL_NAME, version=bundle.TOOL_VERSION, schema=bundle.SCHEMA),
        clientBuild=data["clientBuild"], product=data["product"], locale=dict(bundle.LOCALE),
        settings={"fixture": True}, candidateTextureIds=data["candidateTextureIds"],
        clientMetadataSha256=bundle.digest(bundle.json_bytes(data)),
        assets={"123": dict(file="123.blp", fileId=123, sha256=sha, sourceSha256=sha,
            sourceCKey="a" * 32, header=bundle.texture_header(raw), kind="local-client-artwork",
            clientBuild=data["clientBuild"], provenance="owned synthetic transport fixture, not game artwork")},
        missing=[dict(fileId=124, reason="owned fixture deliberately absent")] if missing else [],
        unsupported=[], validation={"status": "success"})  # Deliberately untrusted declared status.
    return data, manifest, raw


def write_bundle(path, data, manifest, raw):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("client.json", bundle.json_bytes(data))
        archive.writestr("assets/manifest.json", bundle.json_bytes(manifest))
        archive.writestr("assets/123.blp", raw)


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
            def read(self, key): self.reads.append(key); return blp_fixture()
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
            self.assertEqual(imported["bundleValidation"]["status"], "success")
            self.assertFalse(imported["bundleValidation"]["legacy"])

    def test_schema2_bundle_import_and_pixel_decode(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); data, manifest, raw = fixture_bundle()
            write_bundle(root / "input.zip", data, manifest, raw)
            imported, cached = ci.unpack([root / "input.zip"], root / "input")
            self.assertEqual(imported["bundleIdentity"]["tool"], manifest["tool"])
            self.assertEqual(imported["bundleValidation"]["counts"]["assets"], 1)
            assets = render.Assets(cached)
            self.assertEqual(assets.validation["status"], "success")
            self.assertEqual(assets.get("123").getpixel((0, 0)), (128, 64, 32, 255))

    def test_bundle_integrity_schema_build_and_metadata_mismatches(self):
        cases = {
            "schema": lambda d, m: m.update(schema=99),
            "tool-schema": lambda d, m: m["tool"].update(schema=99),
            "build": lambda d, m: m.update(clientBuild="1.60.1.99999"),
            "metadata": lambda d, m: d.update(product="different-installed-product"),
            "metadata-hash": lambda d, m: d.update(limitations=["changed after extraction"]),
            "digest": lambda d, m: m["assets"]["123"].update(sha256="0" * 64),
            "dimensions": lambda d, m: m["assets"]["123"]["header"].update(width=8),
            "candidate-coverage": lambda d, m: m.update(candidateTextureIds=[123, 124]),
            "windows-path": lambda d, m: m["assets"]["123"].update(file=r"C:\\game\\123.blp"),
        }
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, mutate in cases.items():
                with self.subTest(name=name):
                    data, manifest, raw = fixture_bundle(); mutate(data, manifest)
                    write_bundle(root / "input.zip", data, manifest, raw)
                    with self.assertRaisesRegex(ci.LabError, "validation failed"):
                        ci.unpack([root / "input.zip"], root / name)

    def test_invalid_legacy_texture_header_is_not_accepted_by_matching_hash(self):
        data, _ = fixture_input(); raw = b"BLP2not a valid texture"
        manifest = dict(schema=1, clientBuild=data["clientBuild"], assets={"123": dict(
            file="123.blp", clientBuild=data["clientBuild"], sha256=bundle.digest(raw))})
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); write_bundle(root / "bad.zip", data, manifest, raw)
            with self.assertRaisesRegex(ci.LabError, "validation failed"):
                ci.unpack([root / "bad.zip"], root / "out")

    def test_partial_bundle_remains_partial_even_when_selected_scene_is_complete(self):
        data, manifest, raw = fixture_bundle(missing=True)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); write_bundle(root / "partial.zip", data, manifest, raw)
            imported, cached = ci.unpack([root / "partial.zip"], root / "input")
            self.assertEqual(imported["bundleValidation"]["status"], "partial")
            scene = dict(id="fixture", width=16, height=16, view=dict(u0=0, v0=0, u1=1, v1=1),
                textures=[dict(fileId=123, u0=0, v0=0, u1=1, v1=1)])
            state = dict(schema=1, provenance=dict(synthetic=True, clientBuild=data["clientBuild"]), scenes=[scene])
            (root / "state.json").write_text(json.dumps(state))
            args = lab.parser().parse_args(["--state", str(root / "state.json"), "--assets", str(cached),
                                           "--output", str(root / "gallery"), "--strict"])
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(lab.run(args), 1)
            report = json.loads((root / "gallery/report.json").read_text())
            self.assertEqual(report["status"], "partial")
            self.assertEqual(report["missingAssets"], [])
            self.assertFalse(report["realArtworkVerified"])
            self.assertIn("incomplete-artwork-bundle", [f["code"] for f in report["findings"]])
            self.assertIn("partial", (root / "gallery/index.html").read_text())

    def test_windows_zip_paths_symlinks_and_duplicate_json_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); path = root / "bad.zip"
            for member in (r"assets\123.blp", r"C:\game\client.json", "//server/share/client.json"):
                with self.subTest(member=member):
                    with zipfile.ZipFile(path, "w") as archive: archive.writestr(member, b"fixture")
                    with self.assertRaisesRegex(ci.LabError, "Unexpected"):
                        ci.unpack([path], root / "out")
            link = zipfile.ZipInfo("assets/123.blp"); link.create_system = 3
            link.external_attr = (0o120777 << 16)
            with zipfile.ZipFile(path, "w") as archive: archive.writestr(link, "/private/input")
            with self.assertRaisesRegex(ci.LabError, "symbolic links"):
                ci.unpack([path], root / "out")
            duplicate = root / "duplicate.json"; duplicate.write_text('{"schema":1,"schema":2}')
            with self.assertRaisesRegex(ci.LabError, "duplicate JSON"):
                render.load_json(duplicate)

    def test_gallery_rejects_every_addon_package_and_cross_build_artwork(self):
        addons = [path for path in REPO.iterdir() if path.is_dir() and any(path.glob("*.toc"))]
        self.assertGreaterEqual(len(addons), 7)
        for addon in addons:
            with self.subTest(addon=addon.name), self.assertRaisesRegex(ci.LabError, "addon package"):
                lab.run(lab.parser().parse_args(["--probe-assets", "--output", str(addon / "private-artwork")]))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); data, manifest, raw = fixture_bundle()
            write_bundle(root / "input.zip", data, manifest, raw)
            _, cached = ci.unpack([root / "input.zip"], root / "input")
            state = dict(schema=1, provenance=dict(clientBuild="1.60.1.99999"),
                scenes=[dict(id="fixture", width=16, height=16,
                             view=dict(u0=0, v0=0, u1=1, v1=1), textures=[])])
            (root / "state.json").write_text(json.dumps(state))
            with self.assertRaisesRegex(ci.LabError, "client builds differ"):
                lab.run(lab.parser().parse_args(["--state", str(root / "state.json"), "--assets", str(cached),
                                                "--output", str(root / "gallery")]))

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
                raw = blp_fixture(64, noisy=True)
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
            self.assertTrue(decoded["bundleValidation"]["legacy"])
            self.assertEqual(decoded["bundleValidation"]["status"], "success")
            self.assertIn("Legacy schema 1", decoded["bundleValidation"]["warnings"][0])
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

    @unittest.skipUnless(shutil.which("lua5.1"), "existing Lua environment not activated")
    def test_feedback_cameras_use_production_caves_and_bound_geometry(self):
        data, _ = fixture_input()
        elwynn = next(m for m in data["maps"] if m["id"] == 1429)
        data["reveal"][str(elwynn["art"])] = [[100, 100, 0, 0, [123]]]
        state, _ = lab.production_export(data, "feedback-v1")
        self.assertEqual(len(state["scenes"]), 62)
        self.assertEqual(state["provenance"]["scenarioSet"], "feedback-v1")
        self.assertTrue(state["provenance"]["synthetic"], "fixture input stays explicitly synthetic")
        self.assertEqual(len(state["provenance"]["rendererSources"]["Caves.lua"]), 64)
        scenes = {s["id"]: s for s in state["scenes"]}
        self.assertEqual(scenes["jasperlode-124"]["metadata"]["cave"]["surfaced"], "cave:40")
        self.assertEqual(scenes["skull-rock-124"]["metadata"]["cave"]["surfaced"], "cave:5")
        self.assertTrue(any(s["metadata"]["baseCandidates"] for s in state["scenes"]))
        self.assertEqual(scenes["jasperlode-edge-2"]["metadata"]["sequence"], "jasperlode-viewport-exit")
        strengths = [scenes[f"jasperlode-entry-{i}"]["metadata"]["cave"]["strength"] for i in (1, 2, 3)]
        target = scenes["jasperlode-entry-3"]["metadata"]["cave"]["targetStrength"]
        self.assertGreater(target, 0)
        self.assertAlmostEqual(strengths[0], 0)
        self.assertAlmostEqual(strengths[1], target * .5)
        self.assertAlmostEqual(strengths[2], target)
        render.validate_export(state)


if __name__ == "__main__":
    unittest.main()
