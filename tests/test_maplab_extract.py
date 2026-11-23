"""Reusable stdlib collector contracts; owned fixtures, never private game art."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools/maplab"))
import bundle
import collect


def blp(value=1):
    header = bytearray(148)
    header[:4] = b"BLP2"
    struct.pack_into("<I4BII", header, 4, 1, 3, 8, 0, 0, 4, 4)
    struct.pack_into("<I", header, 20, 148)
    struct.pack_into("<I", header, 84, 64)
    return bytes(header) + bytes((value, 40, 70, 255)) * 16


class Storage:
    version = "1.60.1.71037"
    def __init__(self, content, version=None, identity=True):
        self.content, self.reads, self.closed = content, [], False
        if version: self.version = version
        self._fdid = {key: hashlib.md5(raw).digest() for key, raw in content.items() if isinstance(raw, bytes)} if identity else {}
    def read(self, key):
        self.reads.append(key)
        value = self.content.get(key)
        if isinstance(value, BaseException): raise value
        return value
    def close(self): self.closed = True


class Extract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="maplab-extract-test-")
        self.root = Path(self.temp.name)
        self.wow = self.root / "client with spaces"
        (self.wow / "Data/data").mkdir(parents=True)
        (self.wow / ".build.info").write_text("Product!STRING:0|Version!STRING:0|Active!DEC:1\nwowf|1.60.1.71037|1\n")
        self.output = self.root / "private cache"
        self.ids = [123, 124]
        self.original_game = {p.relative_to(self.wow): p.read_bytes() for p in self.wow.rglob("*") if p.is_file()}
    def tearDown(self): self.temp.cleanup()
    def run_collect(self, storage, destination=None, asset_request=None):
        with patch.object(collect, "read_tables", return_value=({}, {"fixture": {"sha256": "0" * 64}})), \
             patch.object(collect, "model", return_value=({947: {"id": 947}}, {}, lambda *a: (0, 0))), \
             patch.object(collect, "minimap", return_value={"0": [], "1": []}), \
             patch.object(collect, "scenarios", return_value=[]), \
             patch.object(collect, "candidate_ids", side_effect=lambda *a: self.ids), contextlib.redirect_stdout(io.StringIO()):
            return collect.collect(self.wow, destination or self.output, storage_factory=lambda *a, **k: storage,
                                   asset_request=asset_request)
    def request(self, **changes):
        data = dict(schema=1, kind="twichui-maplab-asset-request", clientBuild="1.60.1.71037", product="wowf",
                    numericSources=collect.numeric_sources(), fileIds=[125, 126],
                    provenance="Owned test fixture standing in for production-Lua selected texture IDs")
        data.update(changes)
        path = self.root / "maplab-asset-request.json"; path.write_bytes(bundle.json_bytes(data))
        return path, data
    def version(self, pointer="current.json"):
        record = json.loads((self.output / pointer).read_text())
        folder = self.output / record["version"]
        return folder, json.loads((folder / "assets/manifest.json").read_text()), record

    def test_clean_collection_versioned_manifest_headers_and_read_only_install(self):
        storage = Storage({123: blp(), 124: blp(2)})
        outputs = self.run_collect(storage)
        folder, manifest, pointer = self.version()
        client = json.loads((folder / "client.json").read_text())
        self.assertEqual(manifest["schema"], 2)
        self.assertEqual(manifest["locale"]["clientLocale"], "unknown")
        self.assertEqual(manifest["locale"]["selected"], "enUS-compatible-root-blocks")
        self.assertEqual(manifest["validation"]["status"], "success")
        self.assertEqual(bundle.validate_manifest(manifest, folder / "assets", client)["status"], "success")
        self.assertEqual(manifest["assets"]["123"]["header"]["format"], "BGRA")
        self.assertEqual(manifest["clientMetadataSha256"], bundle.digest(bundle.json_bytes(client)))
        self.assertNotIn("assetRequest", client); self.assertNotIn("assetRequest", manifest["settings"])
        self.assertTrue(storage.closed); self.assertEqual(storage.reads, self.ids)
        self.assertEqual(self.original_game, {p.relative_to(self.wow): p.read_bytes() for p in self.wow.rglob("*") if p.is_file()})
        with zipfile.ZipFile(outputs[0]) as archive:
            self.assertEqual(set(archive.namelist()), {"client.json", "assets/manifest.json", "assets/123.blp", "assets/124.blp"})
            self.assertIsNone(archive.testzip())

    def test_exact_asset_request_overrides_default_ids_and_records_provenance(self):
        path, request = self.request()
        storage = Storage({125: blp(3), 126: blp(4)})
        self.run_collect(storage, asset_request=path)
        folder, manifest, _ = self.version()
        client = json.loads((folder / "client.json").read_text())
        self.assertEqual(storage.reads, [125, 126])
        self.assertEqual(manifest["candidateTextureIds"], [125, 126])
        self.assertEqual(client["candidateTextureIds"], [125, 126])
        identity = client["assetRequest"]
        self.assertEqual(identity["sha256"], bundle.digest(bundle.json_bytes(request)))
        self.assertEqual(identity["count"], 2)
        self.assertEqual(identity["provenance"], request["provenance"])
        self.assertEqual(manifest["settings"]["assetRequest"], identity)
        self.assertEqual(bundle.validate_manifest(manifest, folder / "assets", client)["status"], "success")

    def test_asset_request_rejects_old_build_product_and_numeric_data_before_texture_reads(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}))
        prior = (self.output / "current.json").read_bytes()
        for changes in ({"clientBuild": "1.60.1.70000"}, {"product": "wow_classic_beta"},
                        {"numericSources": {name: "0" * 64 for name in collect.NUMERIC_SOURCES}}):
            with self.subTest(changes=changes):
                path, _ = self.request(**changes); storage = Storage({125: blp(), 126: blp(2)})
                with self.assertRaisesRegex(collect.ClientInputError, "differs|hashes differ"):
                    self.run_collect(storage, asset_request=path)
                self.assertEqual(storage.reads, []); self.assertTrue(storage.closed)
                self.assertEqual(prior, (self.output / "current.json").read_bytes())

    def test_asset_request_rejects_malformed_unbounded_paths_and_duplicate_fields(self):
        cases = [dict(schema=True), dict(schema=99), dict(kind="not-an-art-request"), dict(fileIds=[]),
                 dict(fileIds=[126, 125]), dict(fileIds=[125, 125]), dict(fileIds=[True]), dict(fileIds=[1.5]),
                 dict(fileIds=[0]), dict(fileIds=[2**32]), dict(fileIds=list(range(1, 2050))),
                 dict(fileIds=[r"C:\\game\\texture.blp"]), dict(path="../outside"), dict(provenance={}),
                 dict(clientBuild="unknown"), dict(product="../game")]
        for changes in cases:
            with self.subTest(changes=str(changes)[:100]):
                path, _ = self.request(**changes)
                with self.assertRaises(collect.ClientInputError): collect.read_asset_request(path)
        path, _ = self.request()
        path.write_text('{"schema":1,"schema":1}')
        with self.assertRaisesRegex(collect.ClientInputError, "Duplicate"): collect.read_asset_request(path)
        for raw in (b"{", b"[]", b"\xff", b"[" * 2000):
            path.write_bytes(raw)
            with self.assertRaises(collect.ClientInputError): collect.read_asset_request(path)
        path.write_bytes(b" " * (128 * 1024 + 1))
        with self.assertRaisesRegex(collect.ClientInputError, "128 KiB"): collect.read_asset_request(path)

    def test_asset_request_source_kit_embeds_only_validated_data_and_runs_without_site_packages(self):
        path, request = self.request()
        kit = collect.make_kit(self.root / "request-kit.zip", path)
        with zipfile.ZipFile(kit) as archive:
            self.assertEqual(json.loads(archive.read("maplab-asset-request.json")), request)
            self.assertFalse(any(name.endswith((".blp", ".png", ".tga")) for name in archive.namelist()))
            archive.extractall(self.root / "request-kit")  # Test-generated code/data kit only.
        unpacked = self.root / "request-kit"
        process = subprocess.run([sys.executable, "-S", str(unpacked / "tools/maplab/collect.py"),
                                  "--make-kit", str(self.root / "second-kit.zip"),
                                  "--asset-request", str(unpacked / "maplab-asset-request.json")],
                                 capture_output=True, text=True, timeout=10)
        self.assertEqual(process.returncode, 0, process.stderr)
        with zipfile.ZipFile(self.root / "second-kit.zip") as archive:
            self.assertEqual(json.loads(archive.read("maplab-asset-request.json")), request)
        bad, _ = self.request(schema=99)
        with self.assertRaises(collect.ClientInputError): collect.make_kit(self.root / "bad-kit.zip", bad)
        self.assertFalse((self.root / "bad-kit.zip").exists(), "invalid request cannot leave a misleading kit")

    def test_unchanged_run_reuses_only_verified_current_source_and_same_version(self):
        first = self.run_collect(Storage({123: blp(), 124: blp(2)}))
        before = (self.output / "current.json").read_bytes()
        storage = Storage({123: blp(), 124: blp(2)})
        self.assertEqual(self.run_collect(storage), first)
        self.assertEqual(storage.reads, [])
        self.assertEqual(before, (self.output / "current.json").read_bytes())
        update = json.loads((self.output / "latest-update.json").read_text())
        self.assertEqual((update["reused"], update["freshReads"]), (2, 0))

    def test_changed_build_reuses_unchanged_source_but_updates_identity_and_diff(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}))
        previous, _, _ = self.version()
        storage = Storage({123: blp(), 124: blp(3)}, version="1.60.1.72000")
        self.run_collect(storage)
        folder, manifest, _ = self.version()
        self.assertNotEqual(folder, previous); self.assertTrue(previous.is_dir())
        self.assertEqual(storage.reads, [124])
        self.assertEqual(manifest["assets"]["123"]["clientBuild"], storage.version)
        update = json.loads((self.output / "latest-update.json").read_text())
        self.assertEqual(update["changed"], [124]); self.assertEqual(update["previousBuild"], "1.60.1.71037")

    def test_removed_and_new_ids_are_reported_and_not_silently_retained(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}))
        self.ids = [123, 125]
        storage = Storage({123: blp(), 125: blp(3)})
        self.run_collect(storage)
        _, manifest, _ = self.version()
        self.assertEqual(set(manifest["assets"]), {"123", "125"})
        update = json.loads((self.output / "latest-update.json").read_text())
        self.assertEqual(update["added"], [125]); self.assertEqual(update["removed"], [124])

    def test_absent_source_identity_forces_fresh_archive_reads(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}, identity=False))
        storage = Storage({123: blp(), 124: blp(2)}, identity=False)
        self.run_collect(storage)
        self.assertEqual(storage.reads, [123, 124])
        self.assertIs(self.version()[1]["assets"]["123"]["sourceCKey"], False)

    def test_corrupt_cache_forces_fresh_reads_without_overwriting_old_version(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}))
        old, _, _ = self.version()
        (old / "assets/123.blp").write_bytes(b"corrupt")
        storage = Storage({123: blp(), 124: blp(2)})
        self.run_collect(storage)
        new, manifest, _ = self.version()
        self.assertNotEqual(old, new)
        self.assertEqual(storage.reads, [123, 124])
        self.assertEqual((old / "assets/123.blp").read_bytes(), b"corrupt")
        self.assertEqual(bundle.validate_manifest(manifest, new / "assets")["status"], "success")

    def test_corrupt_transport_is_repaired_as_new_immutable_version(self):
        paths = self.run_collect(Storage({123: blp(), 124: blp(2)}))
        old, _, _ = self.version(); paths[0].write_bytes(b"not a zip")
        storage = Storage({123: blp(), 124: blp(2)})
        fresh = self.run_collect(storage)
        self.assertNotEqual(old, self.version()[0]); self.assertEqual(storage.reads, [])
        with zipfile.ZipFile(fresh[0]) as archive: self.assertIsNone(archive.testzip())

    def test_valid_crc_empty_or_stale_transport_cannot_be_reused(self):
        paths = self.run_collect(Storage({123: blp(), 124: blp(2)}))
        old, _, _ = self.version()
        with zipfile.ZipFile(paths[0], "w") as archive: pass
        fresh = self.run_collect(Storage({123: blp(), 124: blp(2)}))
        self.assertNotEqual(old, self.version()[0])
        # A structurally valid, complete member set still fails on stale bytes.
        with zipfile.ZipFile(fresh[0]) as archive:
            members = {entry.filename: archive.read(entry) for entry in archive.infolist()}
        members["assets/123.blp"] = blp(99)
        with zipfile.ZipFile(fresh[0], "w") as archive:
            for name, content in members.items(): archive.writestr(name, content)
        latest = self.run_collect(Storage({123: blp(), 124: blp(2)}))
        self.assertNotEqual(fresh, latest)
        with zipfile.ZipFile(latest[0]) as archive: self.assertEqual(archive.read("assets/123.blp"), blp())

    def test_partial_update_preserves_successful_pointer_and_lists_unsupported(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}))
        before = (self.output / "current.json").read_bytes()
        self.run_collect(Storage({123: blp(), 124: b"BLP2bad"}))
        self.assertEqual(before, (self.output / "current.json").read_bytes())
        folder, manifest, pointer = self.version("latest.json")
        self.assertEqual(manifest["validation"]["status"], "partial")
        self.assertEqual(manifest["unsupported"][0]["fileId"], 124)
        self.assertEqual(manifest["missing"][0]["fileId"], 124)
        self.assertTrue((folder / pointer["bundles"][0].split("/")[-1]).is_file())

    def test_all_missing_or_interrupted_update_cannot_replace_current(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}))
        before = (self.output / "current.json").read_bytes()
        absent = Storage({})
        with self.assertRaisesRegex(collect.ClientInputError, "failed validation"):
            self.run_collect(absent)
        self.assertTrue(absent.closed)
        interrupted = Storage({123: KeyboardInterrupt(), 124: blp(9)})
        with self.assertRaises(KeyboardInterrupt): self.run_collect(interrupted)
        self.assertTrue(interrupted.closed)
        self.assertEqual(before, (self.output / "current.json").read_bytes())
        self.assertEqual(list(self.output.glob(".maplab-stage-*")), [])

    def test_paths_zip_compatibility_and_failure_publication_cleanup(self):
        with self.assertRaisesRegex(collect.ClientInputError, "outside"):
            self.run_collect(Storage({123: blp(), 124: blp(2)}), self.wow / "output")
        for name in ("!!!TwichUI", "TwichUI_Diagnostics", "TwichUI_Settings", "TwichUI_NavData", "TwichUI_Workshop", "TwichUI_Layouts", "TwichUI_LayoutWizard", "TwichUI_FutureAddon"):
            with self.assertRaisesRegex(collect.ClientInputError, "addon package"):
                self.run_collect(Storage({123: blp(), 124: blp(2)}), REPO / name / "private-cache")
        output = self.root / "new.zip"
        self.run_collect(Storage({123: blp(), 124: blp(2)}), output)
        original = output.read_bytes()
        with self.assertRaisesRegex(collect.ClientInputError, "already exists"):
            self.run_collect(Storage({123: blp(4), 124: blp(5)}), output)
        self.assertEqual(original, output.read_bytes())
        def failed_link(*args): raise OSError("fixture filesystem interruption")
        with patch.object(collect.os, "link", side_effect=failed_link), self.assertRaises(OSError):
            self.run_collect(Storage({123: blp(), 124: blp(2)}), self.root / "failed.zip")
        self.assertFalse((self.root / "failed.zip").exists())
        self.assertEqual(list(self.root.glob(".maplab-pack-*")), [])

    def test_manifest_rejects_malformed_identity_geometry_hash_and_metadata(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}))
        folder, manifest, _ = self.version()
        client = json.loads((folder / "client.json").read_text())
        for malformed in [None, [], {"schema": 2, "assets": []}, {**manifest, "tool": None},
                          {**manifest, "locale": {"clientLocale": "enUS"}}, {**manifest, "candidateTextureIds": [123]},
                          {**manifest, "assets": {"123": []}}]:
            self.assertEqual(bundle.validate_manifest(malformed, folder / "assets", client)["status"], "failure")
        changed = dict(client, scenarios=[{"changed": True}])
        self.assertEqual(bundle.validate_manifest(manifest, folder / "assets", changed)["status"], "failure")
        record = manifest["assets"]["123"]
        for change in [{"file": "../../escape.blp"}, {"sha256": "0" * 64}, {"sourceCKey": "wrong"}, {"header": {}}]:
            bad = {**manifest, "assets": {**manifest["assets"], "123": {**record, **change}}}
            self.assertEqual(bundle.validate_manifest(bad, folder / "assets", client)["status"], "failure")

    def test_legacy_header_validation_and_explicit_provenance_limitations(self):
        assets = self.root / "legacy"; assets.mkdir()
        raw = blp(); (assets / "123.blp").write_bytes(raw)
        manifest = dict(schema=1, clientBuild="legacy", assets={"123": dict(file="123.blp", sha256=bundle.digest(raw), clientBuild="legacy")})
        result = bundle.validate_manifest(manifest, assets)
        self.assertEqual(result["status"], "success"); self.assertTrue(result["legacy"]); self.assertTrue(result["warnings"])
        bad = b"BLP2fake"; (assets / "123.blp").write_bytes(bad); manifest["assets"]["123"]["sha256"] = bundle.digest(bad)
        self.assertEqual(bundle.validate_manifest(manifest, assets)["status"], "failure")

    def test_header_bounds_formats_and_source_kit_standard_library_only(self):
        self.assertEqual(bundle.texture_header(blp())["width"], 4)
        for raw in [b"BLP2", b"not an image" * 15, blp()[:150], blp()[:12] + struct.pack("<II", 999999, 999999) + blp()[20:]]:
            with self.assertRaises(bundle.BundleError): bundle.texture_header(raw)
        kit = collect.make_kit(self.root / "kit.zip")
        with zipfile.ZipFile(kit) as archive:
            names = set(archive.namelist())
            self.assertIn("tools/maplab/bundle.py", names); self.assertIn("tools/maplab/README.md", names)
            self.assertFalse(any(name.endswith((".blp", ".png", ".tga")) for name in names))
            archive.extractall(self.root / "kit")  # test-generated source kit, never external untrusted ZIP
        process = subprocess.run([sys.executable, "-S", str(self.root / "kit/tools/maplab/collect.py"), "--help"], capture_output=True, text=True, timeout=10)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn("reusable", process.stdout)

    def test_declared_texture_payload_sizes_and_dds_formats(self):
        # Correctly sized DXT1 is accepted; dimension/header-only corruption is not.
        compressed = bytearray(148)
        compressed[:4] = b"BLP2"
        struct.pack_into("<I4BII", compressed, 4, 1, 2, 0, 0, 0, 8, 8)
        struct.pack_into("<I", compressed, 20, 148); struct.pack_into("<I", compressed, 84, 32)
        self.assertEqual(bundle.texture_header(bytes(compressed) + bytes(32))["format"], "DXT1")
        struct.pack_into("<I", compressed, 84, 1)
        with self.assertRaisesRegex(bundle.BundleError, "too short"):
            bundle.texture_header(bytes(compressed) + bytes(1))
        palette = bytearray(148 + 1024)
        palette[:4] = b"BLP2"
        struct.pack_into("<I4BII", palette, 4, 1, 1, 8, 0, 0, 4, 4)
        struct.pack_into("<I", palette, 20, len(palette)); struct.pack_into("<I", palette, 84, 32)
        self.assertEqual(bundle.texture_header(bytes(palette) + bytes(32))["format"], "paletted")
        palette[12:20] = struct.pack("<II", 512, 512)
        with self.assertRaisesRegex(bundle.BundleError, "too short"):
            bundle.texture_header(bytes(palette) + bytes(32))
        bgra = bytearray(blp()); bgra[12:20] = struct.pack("<II", 512, 512)
        with self.assertRaisesRegex(bundle.BundleError, "too short"): bundle.texture_header(bytes(bgra))
        dds = bytearray(128); dds[:4] = b"DDS "
        struct.pack_into("<I", dds, 4, 124); struct.pack_into("<II", dds, 12, 8, 8)
        struct.pack_into("<II", dds, 76, 32, 4); dds[84:88] = b"DXT1"
        self.assertEqual(bundle.texture_header(bytes(dds) + bytes(32))["container"], "DDS")
        with self.assertRaisesRegex(bundle.BundleError, "too short"): bundle.texture_header(bytes(dds) + bytes(1))
        dds[84:88] = b"DX10"
        with self.assertRaisesRegex(bundle.BundleError, "unsupported"): bundle.texture_header(bytes(dds) + bytes(32))

    def test_protocol_schema_accepts_recorded_tool_patch_versions(self):
        self.run_collect(Storage({123: blp(), 124: blp(2)}))
        folder, manifest, _ = self.version()
        manifest["tool"]["version"] = "2.0.1"
        self.assertEqual(bundle.validate_manifest(manifest, folder / "assets")["status"], "success")
        manifest["tool"]["schema"] = 999
        self.assertEqual(bundle.validate_manifest(manifest, folder / "assets")["status"], "failure")


if __name__ == "__main__": unittest.main()
