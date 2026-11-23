"""Extract referenced client textures from a user-selected local CASC install.

The installation is read-only. No CDN, credentials, decryption or redistribution
is involved. Generated PNGs and manifests belong in ignored test-output only.
"""
from __future__ import annotations

import hashlib
import importlib.util
import io
from pathlib import Path

from PIL import Image

from render import LabError


def probe(root: Path | None = None):
    if root is None:
        return {"available": False, "missing": ["local WoW Forever .build.info", "Data/config and Data/data CASC archives"],
                "reason": "No client path selected; this cloud workspace was provisioned with SIMLAB_ASSETS=0."}
    return {"available": (root / ".build.info").is_file() and (root / "Data/config").is_dir() and (root / "Data/data").is_dir(),
            "buildInfo": (root / ".build.info").is_file(), "dataArchives": (root / "Data/data").is_dir(),
            "missing": [name for name in (".build.info", "Data/config", "Data/data") if not (root / name).exists()]}


def referenced_ids(export):
    ids = set()
    for scene in export["scenes"]:
        for texture in scene["textures"]:
            candidates = [texture, *texture.get("masks", [])]
            if texture.get("mask"):
                candidates.append(texture["mask"])
            for value in candidates:
                key = value.get("fileId")
                if isinstance(key, int) and not isinstance(key, bool) and 0 < key <= 0xffffffff:
                    ids.add(key)
    return sorted(ids)


def extract(export, wow: Path, output: Path, repo: Path, product="wow_classic_beta"):
    if not probe(wow)["available"]:
        raise LabError("Local Forever CASC input is missing .build.info, Data/config or Data/data. No artwork extraction was performed.")
    output = output.resolve()
    wow = wow.resolve()
    if output == wow or output.is_relative_to(wow):
        raise LabError("asset output must not be inside the game installation")
    spec = importlib.util.spec_from_file_location("twichui_maplab_casc", repo / "tools/navbake/casc.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    storage = module.Storage(str(wow), product=product)
    output.mkdir(parents=True, exist_ok=True)
    records, missing = {}, []
    try:
        for file_id in referenced_ids(export):
            try:
                raw = storage.read(file_id)
                if raw is None:
                    missing.append({"fileId": file_id, "reason": "not stored locally"})
                    continue
                if len(raw) > 64 * 1024 * 1024:
                    raise LabError("texture source exceeds decode byte limit")
                with Image.open(io.BytesIO(raw)) as image:
                    if image.width * image.height > 16_777_216:
                        raise LabError("texture source exceeds pixel limit")
                    converted = image.convert("RGBA")
                name = f"{file_id}.png"
                target = output / name
                converted.save(target)
                records[str(file_id)] = {"file": name, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                    "sourceSha256": hashlib.sha256(raw).hexdigest(), "fileId": file_id,
                    "kind": "local-client-artwork", "clientBuild": storage.version,
                    "provenance": f"Local CASC file-data ID {file_id}; {product}; build {storage.version}; extracted with TwichUI tools/navbake/casc.py; decoded with Pillow"}
            except (OSError, ValueError, module.CascError) as exc:
                missing.append({"fileId": file_id, "reason": type(exc).__name__ + ": " + str(exc)[:160]})
    finally:
        for archive in storage._archives.values():
            archive.close()
    return {"schema": 1, "clientBuild": storage.version, "product": product,
            "redistribution": "Private local preview cache only; no redistribution rights granted.",
            "assets": records, "missing": missing}
