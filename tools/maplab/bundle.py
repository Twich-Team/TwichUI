"""Versioned artwork-bundle contracts, shared by collector and offline importer.

Python standard library only. Header checks do not replace decoding/native tests.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import struct

SCHEMA = 2
TOOL_NAME = "twichui-maplab-collector"
TOOL_VERSION = "2.0.0"
MAX_TEXTURE_BYTES = 16 * 1024 * 1024
MAX_ASSETS = 2048
MAX_BYTES = 128 * 1024 * 1024
MAX_PIXELS = 16_777_216
LOCALE = {"requested": "reader-default", "selected": "enUS-compatible-root-blocks",
          "clientLocale": "unknown", "limitation": "The local CASC reader selects enUS-compatible root blocks; native client locale is not observed."}


class BundleError(ValueError):
    pass


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def texture_header(raw):
    """Validate bounded BLP/DDS structure and describe its declared source format.

    This is a header/mip-range validation, not successful pixel decoding. No
    guessed extension or locale is treated as evidence of the actual format.
    """
    if not isinstance(raw, bytes) or not 128 <= len(raw) <= MAX_TEXTURE_BYTES:
        raise BundleError("texture size outside 128 bytes..16 MiB")
    magic = raw[:4]
    if magic in (b"BLP1", b"BLP2"):
        minimum = 156 if magic == b"BLP1" else 148
        if len(raw) < minimum:
            raise BundleError("truncated BLP header")
        width, height = struct.unpack_from("<II", raw, 12)
        if magic == b"BLP2":
            version = struct.unpack_from("<I", raw, 4)[0]
            encoding, alpha, alpha_encoding, mips = raw[8:12]
            if version != 1 or encoding not in (1, 2, 3) or alpha not in (0, 1, 4, 8):
                raise BundleError("unsupported BLP2 encoding/type/alpha depth")
            fmt = {1: "paletted", 2: "DXT", 3: "BGRA"}[encoding]
            if encoding == 2:
                fmt = {0: "DXT1", 1: "DXT3", 7: "DXT5"}.get(alpha_encoding, "DXT-unknown")
                if fmt == "DXT-unknown":
                    raise BundleError("unsupported BLP2 DXT alpha encoding")
            offset_at, size_at = 20, 84
            extra = {"encoding": encoding, "alphaDepth": alpha, "alphaEncoding": alpha_encoding,
                     "hasMipmaps": bool(mips)}
        else:
            compression, alpha = struct.unpack_from("<II", raw, 4)
            if compression not in (0, 1):
                raise BundleError("unsupported BLP1 compression")
            fmt = "JPEG" if compression == 0 else "paletted"
            offset_at, size_at = 28, 92
            extra = {"compression": compression, "alphaDepth": alpha}
        offsets = struct.unpack_from("<16I", raw, offset_at)
        sizes = struct.unpack_from("<16I", raw, size_at)
        if not offsets[0] or not sizes[0]:
            raise BundleError("BLP has no base mip payload")
        if magic == b"BLP1" and compression == 0:
            if len(raw) < 160: raise BundleError("truncated BLP1 JPEG shared header")
            jpeg_size = struct.unpack_from("<I", raw, 156)[0]
            if jpeg_size < 2 or 160 + jpeg_size > offsets[0] or raw[160:162] != b"\xff\xd8":
                raise BundleError("invalid BLP1 JPEG shared header")
        if fmt == "paletted" and offsets[0] < minimum + 1024:
            raise BundleError("BLP palette is missing")
        if fmt == "paletted" and alpha not in (0, 1, 4, 8):
            raise BundleError("unsupported BLP palette alpha depth")
        for level, (offset, size) in enumerate(zip(offsets, sizes)):
            if bool(offset) != bool(size) or (size and (offset < minimum or offset + size > len(raw))):
                raise BundleError("BLP mip payload outside file")
            if size:
                w, h = max(1, width >> level), max(1, height >> level)
                required = 0
                if fmt.startswith("DXT"):
                    required = ((w + 3) // 4) * ((h + 3) // 4) * (8 if fmt == "DXT1" else 16)
                elif fmt == "BGRA": required = w * h * 4
                elif fmt == "paletted": required = w * h + (w * h * alpha + 7) // 8
                elif fmt == "JPEG": required = 2
                if size < required: raise BundleError("BLP mip payload is too short for declared dimensions")
        result = {"container": magic.decode(), "format": fmt, **extra}
    elif magic == b"DDS ":
        if struct.unpack_from("<I", raw, 4)[0] != 124 or struct.unpack_from("<I", raw, 76)[0] != 32:
            raise BundleError("unsupported DDS header size")
        height, width = struct.unpack_from("<II", raw, 12)
        flags = struct.unpack_from("<I", raw, 80)[0]
        fourcc = raw[84:88]
        if flags & 4:
            if fourcc not in (b"DXT1", b"DXT3", b"DXT5"):
                raise BundleError("unsupported DDS FourCC")
            fmt = fourcc.decode()
        elif flags & 0x40:
            bits = struct.unpack_from("<I", raw, 88)[0]
            if bits not in (16, 24, 32):
                raise BundleError("unsupported DDS RGB bit depth")
            fmt = f"RGB{bits}"
        else:
            raise BundleError("unsupported DDS pixel format")
        if len(raw) <= 128:
            raise BundleError("DDS has no image payload")
        if struct.unpack_from("<I", raw, 112)[0] & (0x200 | 0x200000):
            raise BundleError("DDS cubemaps/volume textures are unsupported")
        levels = struct.unpack_from("<I", raw, 28)[0] or 1
        if levels > 16: raise BundleError("DDS mip count exceeds bounds")
        required = 0
        for level in range(levels):
            w, h = max(1, width >> level), max(1, height >> level)
            required += (((w + 3) // 4) * ((h + 3) // 4) * (8 if fmt == "DXT1" else 16)
                         if fmt.startswith("DXT") else w * h * bits // 8)
        if len(raw) < 128 + required: raise BundleError("DDS payload is too short for declared dimensions/mips")
        result = {"container": "DDS", "format": fmt}
    else:
        raise BundleError("unsupported texture magic")
    if width <= 0 or height <= 0 or width * height > MAX_PIXELS:
        raise BundleError("texture dimensions outside decoded-pixel budget")
    return {**result, "width": width, "height": height, "headerValidated": True}


def json_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("utf-8")


def validate_manifest(manifest, asset_root, client=None, *, verify_files=True):
    """Return bounded status/findings rather than trusting a declared result.

    Schema 1 remains importable with explicit legacy limitations. Schema 2
    requires candidate accounting, hash/header/tool/locale provenance. Malformed
    inputs produce status=failure without attribute/type errors.
    """
    result = {"schema": None, "status": "failure", "errors": [], "warnings": [], "legacy": False,
              "scope": "Local payload SHA256 and declared BLP/DDS header/mip ranges; not pixel decoding or native rendering",
              "counts": {"candidates": 0, "assets": 0, "missing": 0, "unsupported": 0, "bytes": 0}}
    def error(message):
        if len(result["errors"]) < 32: result["errors"].append(str(message)[:240])
    def warning(message):
        if len(result["warnings"]) < 32: result["warnings"].append(str(message)[:240])
    if not isinstance(manifest, dict):
        error("manifest must be an object"); return result
    schema = manifest.get("schema")
    result["schema"], result["legacy"] = schema, schema == 1
    if schema not in (1, 2) or isinstance(schema, bool):
        error("unsupported artwork manifest schema"); return result
    build, product = manifest.get("clientBuild"), manifest.get("product")
    if not isinstance(build, str) or not build or len(build) > 80: error("missing/invalid client build")
    if schema == 2:
        if manifest.get("kind") != "twichui-maplab-artwork-bundle": error("unknown artwork manifest kind")
        tool = manifest.get("tool")
        if not isinstance(tool, dict) or tool.get("name") != TOOL_NAME or tool.get("schema") != SCHEMA or not isinstance(tool.get("version"), str) or not tool["version"].strip() or len(tool["version"]) > 80:
            error("unknown collector tool/schema/version")
        if not isinstance(product, str) or not product or len(product) > 80: error("missing/invalid installed product")
        if manifest.get("locale") != LOCALE: error("unknown or misleading reader locale selection")
        if not isinstance(manifest.get("settings"), dict): error("missing extraction settings")
        binding = manifest.get("clientMetadataSha256")
        if not isinstance(binding, str) or not re.fullmatch(r"[a-f0-9]{64}", binding): error("missing/invalid client metadata digest")
    else:
        warning("Legacy schema 1: source CKeys, texture header provenance, extraction settings and native locale were not recorded.")
    if client is not None:
        if not isinstance(client, dict): error("client metadata must be an object")
        elif client.get("clientBuild") != build or (product is not None and client.get("product") != product):
            error("client/manifest build or product mismatch")
        elif schema == 2:
            try:
                if manifest.get("clientMetadataSha256") != digest(json_bytes(client)): error("client metadata SHA256 differs")
            except (TypeError, ValueError): error("client metadata is not finite JSON")
    records = manifest.get("assets")
    if not isinstance(records, dict) or len(records) > MAX_ASSETS:
        error("assets must be a bounded object"); return result
    root = Path(asset_root).resolve()
    ids, total = set(), 0
    for key, record in records.items():
        if not isinstance(key, str) or not re.fullmatch(r"[1-9][0-9]{0,9}", key) or int(key) > 0xffffffff:
            error("invalid artwork file-data ID"); continue
        file_id = int(key)
        if not isinstance(record, dict): error(f"invalid asset record {key}"); continue
        ids.add(file_id)
        if record.get("clientBuild") != build: error(f"asset build differs: {key}")
        if schema == 2:
            if isinstance(record.get("fileId"), bool) or record.get("fileId") != file_id or record.get("kind") != "local-client-artwork": error(f"asset identity differs: {key}")
            if not isinstance(record.get("provenance"), str) or not record["provenance"].strip(): error(f"asset provenance missing: {key}")
            if not isinstance(record.get("header"), dict): error(f"asset header metadata missing: {key}")
            ckey = record.get("sourceCKey")
            if ckey is not False and (not isinstance(ckey, str) or not re.fullmatch(r"[a-f0-9]{32}", ckey)):
                error(f"invalid source CKey: {key}")
        name, sha = record.get("file"), record.get("sha256")
        if not isinstance(name, str) or name != f"{key}.blp": error(f"unsafe asset filename: {key}"); continue
        if not isinstance(sha, str) or not re.fullmatch(r"[a-f0-9]{64}", sha): error(f"invalid asset SHA256: {key}"); continue
        if schema == 2 and record.get("sourceSha256") != sha: error(f"source/output digest differs: {key}")
        if verify_files:
            path = root / name
            try:
                if path.is_symlink() or not path.resolve().is_relative_to(root):
                    raise BundleError("asset path escapes cache or is a symlink")
                size = path.stat().st_size
                if not 0 < size <= MAX_TEXTURE_BYTES: raise BundleError("asset file size exceeds bounds")
                total += size
                if total > MAX_BYTES: raise BundleError("whole artwork bundle exceeds 128 MiB")
                raw = path.read_bytes()
                if digest(raw) != sha: raise BundleError("asset SHA256 mismatch")
                header = texture_header(raw)
                if schema == 2 and header != record.get("header"): raise BundleError("asset header provenance differs")
            except (OSError, ValueError, struct.error) as exc:
                error(f"asset {key}: {exc}")
    missing = manifest.get("missing", [])
    missing_ids = set()
    if not isinstance(missing, list) or len(missing) > MAX_ASSETS:
        error("missing assets must be a bounded array"); missing = []
    for entry in missing:
        if not isinstance(entry, dict) or isinstance(entry.get("fileId"), bool) or not isinstance(entry.get("fileId"), int) or not 0 < entry["fileId"] <= 0xffffffff:
            error("invalid missing-asset record"); continue
        file_id = entry["fileId"]
        if file_id in missing_ids or file_id in ids: error("duplicate/conflicting missing-asset ID")
        missing_ids.add(file_id)
        if not isinstance(entry.get("reason"), str) or not entry["reason"]: error("missing-asset reason absent")
    unsupported = manifest.get("unsupported", [])
    if schema == 2:
        if not isinstance(unsupported, list) or len(unsupported) > MAX_ASSETS:
            error("unsupported assets must be a bounded array"); unsupported = []
        for entry in unsupported:
            if not isinstance(entry, dict) or isinstance(entry.get("fileId"), bool) or not isinstance(entry.get("fileId"), int) or entry["fileId"] not in missing_ids:
                error("unsupported asset must be declared missing")
        candidates = manifest.get("candidateTextureIds")
        if not isinstance(candidates, list) or len(candidates) > MAX_ASSETS or any(isinstance(v, bool) or not isinstance(v, int) or not 0 < v <= 0xffffffff for v in candidates):
            error("invalid candidate ID list"); candidates = []
        if len(candidates) != len(set(candidates)) or set(candidates) != ids | missing_ids:
            error("candidate IDs do not exactly account for assets and missing files")
        if isinstance(client, dict) and client.get("candidateTextureIds") != candidates:
            error("client/manifest candidate lists differ")
    else:
        candidates = list(ids | missing_ids)
        if isinstance(client, dict) and "candidateTextureIds" in client:
            declared = client["candidateTextureIds"]
            if not isinstance(declared, list) or len(declared) > MAX_ASSETS or any(isinstance(v, bool) or not isinstance(v, int) for v in declared):
                error("invalid legacy candidate ID list")
            elif len(declared) != len(set(declared)) or set(declared) != ids | missing_ids:
                error("legacy client candidates do not account for available/missing assets")
    result["counts"] = {"candidates": len(candidates), "assets": len(ids), "missing": len(missing_ids),
                        "unsupported": len(unsupported) if isinstance(unsupported, list) else 0, "bytes": total}
    if not ids: error("no verified artwork records")
    if not result["errors"]:
        result["status"] = "partial" if missing_ids else "success"
        if missing_ids: warning(f"{len(missing_ids)} candidate textures unavailable; no complete artwork claim")
    return result
