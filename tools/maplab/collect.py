#!/usr/bin/env python3
"""Collect/update a private map-art cache using only Python's standard library.

py -3 tools/maplab/collect.py --wow "C:\\Games\\World of Warcraft" --output maplab-input

A directory preserves immutable validated versions and reuses current-source
assets. An explicit .zip destination keeps the earlier one-shot transfer mode.
No game writes, network, accounts, gameplay control, Pillow or Lua is involved.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import uuid
import zipfile

from clientdata import ClientInputError, REPO, candidate_ids, minimap, model, read_tables, scenarios
import clientdata
import casc
import db2
from bundle import (BundleError, LOCALE, MAX_ASSETS, MAX_BYTES, MAX_TEXTURE_BYTES, SCHEMA,
                    TOOL_NAME, TOOL_VERSION, digest, json_bytes, texture_header, validate_manifest)

PART_BYTES = 24 * 1024 * 1024
NUMERIC_SOURCES = ("!!!TwichUI/map/Data.lua", "!!!TwichUI/map/LocalData.lua")


def numeric_sources():
    return {name: digest((REPO / name).read_bytes()) for name in NUMERIC_SOURCES}


def read_asset_request(path, client_build=None, product=None):
    """Validate bounded data-only IDs against this kit and, when known, live CASC."""
    if path.stat().st_size > 128 * 1024:
        raise ClientInputError("Asset request exceeds 128 KiB")
    def fields(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise ClientInputError("Duplicate asset-request JSON field")
            result[key] = value
        return result
    try:
        request = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=fields,
                             parse_constant=lambda _: (_ for _ in ()).throw(ClientInputError("Invalid asset-request JSON number")))
    except (json.JSONDecodeError, UnicodeError, RecursionError) as error:
        raise ClientInputError("Malformed asset-request JSON") from error
    allowed = {"schema", "kind", "clientBuild", "product", "numericSources", "fileIds", "provenance", "includeNativeHighlights"}
    if not isinstance(request, dict) or set(request) - allowed:
        raise ClientInputError("Asset request must contain only reviewed data fields")
    if type(request.get("schema")) is not int or request["schema"] != 1 or request.get("kind") != "twichui-maplab-asset-request":
        raise ClientInputError("Unsupported asset-request schema/kind")
    build, requested_product = request.get("clientBuild"), request.get("product")
    if not isinstance(build, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,4}", build) or len(build) > 40:
        raise ClientInputError("Asset request requires an exact client build")
    if not isinstance(requested_product, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", requested_product):
        raise ClientInputError("Asset request requires an exact installed product")
    if request.get("numericSources") != numeric_sources():
        raise ClientInputError("Asset request numeric-source hashes differ from this collector kit; regenerate the request")
    ids = request.get("fileIds")
    if not isinstance(ids, list) or not 1 <= len(ids) <= MAX_ASSETS or any(
        isinstance(value, bool) or not isinstance(value, int) or not 0 < value <= 0xffffffff for value in ids
    ) or ids != sorted(set(ids)):
        raise ClientInputError("Asset request requires 1..2048 sorted unique uint32 file IDs")
    if "provenance" in request and (not isinstance(request["provenance"], str) or not request["provenance"].strip() or len(request["provenance"]) > 512):
        raise ClientInputError("Asset-request provenance must be a bounded technical description")
    if "includeNativeHighlights" in request and type(request["includeNativeHighlights"]) is not bool:
        raise ClientInputError("includeNativeHighlights must be a JSON boolean")
    if client_build is not None and build != client_build:
        raise ClientInputError(f"Asset request build {build} differs from installed CASC {client_build}; regenerate it for the updated client; no default fallback")
    if product is not None and requested_product != product:
        raise ClientInputError(f"Asset request product {requested_product} differs from selected product {product}; no default fallback")
    return request


def select_asset_request(explicit=None, default_catalog=False):
    """An extracted feedback kit must not silently collect the normal catalog.

    Only the kit's fixed root request is implicit; current working-directory
    files are never probed. Explicit selection wins; opting out is deliberate.
    Invalid/mismatched bundled requests fail validation rather than fall back.
    """
    if explicit is not None and default_catalog:
        raise ClientInputError("Choose --asset-request or --default-catalog, not both")
    if explicit is not None: return Path(explicit), "explicit"
    if default_catalog: return None, "default-catalog"
    bundled = REPO / "maplab-asset-request.json"
    if bundled.exists() or bundled.is_symlink(): return bundled, "bundled"
    return None, "default-catalog"


def native_highlight_candidates(maps, links, sources):
    """Conservative source IDs only; this does not activate or place any mask."""
    if not isinstance(maps, dict) or not 1 <= len(maps) <= 2000 or not isinstance(links, list) or len(links) > 8192:
        raise ClientInputError("Native highlight metadata exceeds reviewed shape/count limits")
    ids, map_refs, link_refs, atlas_only, conditional = set(), [], [], [], []
    def identity(value):
        return type(value) is int and 0 <= value <= 0xffffffff
    for mid in sorted(maps):
        row = maps[mid]
        highlight = row.get("highlight") if isinstance(row, dict) else None
        if not isinstance(highlight, dict) or not identity(highlight.get("fileId")) or not identity(highlight.get("atlasId")):
            raise ClientInputError("Native highlight fields unavailable or invalid; use an updated collector kit, never guessed texture IDs")
        fid, atlas = highlight["fileId"], highlight["atlasId"]
        if fid or atlas: map_refs.append(dict(mapId=mid, fileId=fid, atlasId=atlas))
        if fid: ids.add(fid)
        elif atlas: atlas_only.append(dict(source="UiMapArt", mapId=mid, atlasId=atlas,
                                          reason="atlas member ID is not a texture file-data ID; resolution unsupported"))
    for row in links:
        if not isinstance(row, dict) or not all(identity(row.get(key)) for key in
            ("id", "parentMapId", "childMapId", "playerConditionId", "overrideHighlightFileId", "overrideHighlightAtlasId")):
            raise ClientInputError("Native map-link highlight metadata is invalid")
        if row["parentMapId"] not in maps or row["childMapId"] not in maps:
            raise ClientInputError("Native highlight link refers to an unsupported map")
        if row["playerConditionId"] != 0:
            conditional.append(row["id"]); continue
        fid, atlas = row["overrideHighlightFileId"], row["overrideHighlightAtlasId"]
        if fid or atlas:
            link_refs.append(dict(linkId=row["id"], parentMapId=row["parentMapId"], childMapId=row["childMapId"],
                                  fileId=fid, atlasId=atlas, playerConditionId=0))
        if fid: ids.add(fid)
        elif atlas: atlas_only.append(dict(source="UiMapLink", linkId=row["id"], atlasId=atlas,
                                          reason="atlas member ID is not a texture file-data ID; resolution unsupported"))
    source = sources.get("UiMapLink", {"optional": True, "status": "unavailable", "reason": "UiMapLink metadata not supplied by this kit"})
    return sorted(ids), dict(enabled=True, derivation="reviewed UiMapArt.HighlightFileDataID and unconditional UiMapLink.OverrideHighlightFileDataID",
        selection="all supported modeled maps; candidate extraction only, not native highlight activation or placement",
        fileIds=sorted(ids), mapReferences=map_refs, linkReferences=link_refs,
        conditionalLinkIdsIgnored=sorted(conditional), atlasOnlyUnsupported=atlas_only, linkTable=source,
        limitations=["Atlas member IDs are never treated as file-data IDs.",
                     "Nonzero link player conditions are not activated or extracted as override candidates.",
                     "Link rectangles and highlight placement remain unverified against native APIs."])


def installation(selected, requested_product=None):
    """Accept a client subfolder; select only a product actually listed locally."""
    selected = selected.resolve()
    root = next((path for path in (selected, *list(selected.parents)[:2])
                 if (path / ".build.info").is_file() and (path / "Data/data").is_dir()), None)
    if root is None:
        raise ClientInputError("No .build.info and Data/data found in the selected folder or its two nearest parents")
    rows = [row for row in casc.builds(root) if row.get("Product")]
    products = sorted({row["Product"] for row in rows})
    if requested_product:
        if requested_product not in products:
            raise ClientInputError("Requested product is not installed. Available products: " + ", ".join(products))
        return root, requested_product
    # Folder spelling is a hint only: a matching product must exist in metadata.
    hint = selected.name.strip("_").lower()
    hinted = {p for p in products if p.lower().removeprefix("wow_") == hint}
    named = {p for p in products if "forever" in p.lower()}
    versioned = {row["Product"] for row in rows if row.get("Version", "").startswith("1.60.")}
    active = {row["Product"] for row in rows if row.get("Active") == "1"}
    choices = set(products)
    for candidates in (hinted, named, versioned, active):
        narrower = choices & candidates
        if narrower:
            choices = narrower
        if len(choices) == 1:
            return root, next(iter(choices))
    raise ClientInputError(("Multiple products found: " + ", ".join(sorted(choices)) if choices else "No products found in .build.info") +
                           ". Run again with --product followed by the desired listed product")


def make_kit(output, asset_request=None, default_catalog=False):
    """Small reusable source-only handoff; never includes private artwork."""
    asset_request, _ = select_asset_request(asset_request, default_catalog)
    request = read_asset_request(asset_request) if asset_request else None
    names = ["tools/maplab/collect.py", "tools/maplab/clientdata.py", "tools/maplab/bundle.py",
             "tools/maplab/README.md", "tools/maplab/Collect-Map-Art.cmd", "tools/navbake/casc.py",
             "tools/navbake/db2.py", "tools/navbake/wowfiles.py", "!!!TwichUI/map/Data.lua",
             "!!!TwichUI/map/LocalData.lua", "!!!TwichUI/LICENSES/OpenMap.txt", "LICENSE"]
    output = output.resolve(); output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in names: archive.write(REPO / name, name)
        archive.write(REPO / "tools/maplab/Collect-Map-Art.cmd", "Collect-Map-Art.cmd")
        archive.write(REPO / "tools/maplab/README.md", "READ-ME.md")
        if request: archive.writestr("maplab-asset-request.json", json_bytes(request))
    return output


def pack(folder, destination):
    """Publish complete independent ZIP parts without overwriting prior inputs.

    ZIPs are prepared privately first. Exclusive hard-link publication avoids
    exposing a half-written final ZIP or replacing an existing output. Directory
    mode additionally publishes the entire immutable version by atomic rename.
    """
    members = [folder / "client.json", folder / "assets/manifest.json", *sorted((folder / "assets").glob("*.blp"))]
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".maplab-pack-", dir=destination.parent) as temporary:
        files, archive = [], None
        try:
            for source in members:
                size = source.stat().st_size
                if archive is None or archive.fp.tell() + size + (len(archive.filelist) + 1) * 128 + 8192 >= PART_BYTES:
                    if archive: archive.close()
                    part = Path(temporary) / f"part-{len(files) + 1:02}.zip"
                    archive = zipfile.ZipFile(part, "w", compression=zipfile.ZIP_DEFLATED)
                    files.append(part)
                archive.write(source, source.relative_to(folder).as_posix())
            archive.close(); archive = None
            targets = [destination if len(files) == 1 else destination.with_name(f"{destination.stem}-{i:02}.zip")
                       for i in range(1, len(files) + 1)]
            if any(target.exists() for target in targets):
                raise ClientInputError("Output already exists; reuse a directory output for updates or choose another ZIP name")
            if any(source.stat().st_size >= PART_BYTES for source in files):
                raise ClientInputError("An output ZIP exceeded the transfer budget")
            published = []
            try:
                for source, target in zip(files, targets):
                    os.link(source, target)
                    published.append(target)
            except BaseException:
                for target in published: target.unlink(missing_ok=True)
                raise
            return targets
        finally:
            if archive: archive.close()


def atomic_json(path, value):
    """A pointer is visible only once its full JSON has been written."""
    descriptor, temporary = tempfile.mkstemp(prefix=".maplab-pointer-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(json_bytes(value)); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def previous_version(output):
    """Treat prior outputs as untrusted; corruption disables reuse, never fresh reads."""
    pointer = output / "current.json"
    if not pointer.is_file(): return None, None, None
    try:
        if pointer.stat().st_size > 65536: raise BundleError("oversized current pointer")
        data = json.loads(pointer.read_text(encoding="utf-8"))
        relative = data.get("version")
        if not isinstance(relative, str) or not re.fullmatch(r"versions/[A-Za-z0-9_.-]+", relative):
            raise BundleError("unsafe current version path")
        version = (output / relative).resolve()
        if not version.is_relative_to(output.resolve()) or version.is_symlink(): raise BundleError("unsafe current cache path")
        manifest_file, client_file = version / "assets/manifest.json", version / "client.json"
        if manifest_file.stat().st_size > 8 * 1024 * 1024 or client_file.stat().st_size > 8 * 1024 * 1024:
            raise BundleError("oversized cache metadata")
        manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
        client = json.loads(client_file.read_text(encoding="utf-8"))
        validation = validate_manifest(manifest, version / "assets", client)
        if validation["status"] != "success" or manifest.get("schema") != SCHEMA:
            raise BundleError("current cached version failed validation")
        if data.get("manifestSha256") != digest(json_bytes(manifest)):
            raise BundleError("current manifest digest differs")
        return version, manifest, None
    except (OSError, ValueError, TypeError, AttributeError) as error:
        return None, None, "Prior cache ignored: " + str(error)[:160]


def source_key(storage, file_id):
    keys = getattr(storage, "_fdid", None)
    key = keys.get(file_id) if isinstance(keys, dict) else None
    return key.hex() if isinstance(key, bytes) and len(key) == 16 else False


def validate_transport(paths, manifest, client):
    """CRC alone cannot detect a valid but stale/empty replacement ZIP."""
    expected = {"client.json": digest(json_bytes(client)), "assets/manifest.json": digest(json_bytes(manifest))}
    expected.update({"assets/" + record["file"]: record["sha256"] for record in manifest["assets"].values()})
    seen, total = set(), 0
    if not 1 <= len(paths) <= 64: raise BundleError("transport part count outside bounds")
    for path in paths:
        if path.is_symlink() or path.stat().st_size >= PART_BYTES: raise BundleError("invalid transport ZIP")
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                if member.filename not in expected or member.filename in seen or member.file_size > MAX_TEXTURE_BYTES:
                    raise BundleError("transport members differ from the immutable version")
                seen.add(member.filename); total += member.file_size
                if total > MAX_BYTES + 16 * 1024 * 1024: raise BundleError("transport exceeds input budget")
                if digest(archive.read(member)) != expected[member.filename]:
                    raise BundleError("transport content digest differs from the immutable version")
    if seen != set(expected): raise BundleError("transport is missing expected members")


def build_diff(previous, manifest, reused, fresh_reads):
    old, new = (previous or {}).get("assets", {}), manifest["assets"]
    old_ids, new_ids = set(old), set(new)
    changed = sorted(int(key) for key in old_ids & new_ids if old[key].get("sha256") != new[key]["sha256"])
    return {"previousBuild": previous.get("clientBuild") if previous else False,
            "currentBuild": manifest["clientBuild"], "added": sorted(map(int, new_ids - old_ids)),
            "changed": changed, "removed": sorted(map(int, old_ids - new_ids)),
            "unchanged": len(old_ids & new_ids) - len(changed), "reused": reused,
            "freshReads": fresh_reads, "missing": len(manifest["missing"])}


def collect(wow, output=None, product=None, storage_factory=casc.Storage, asset_request=None, default_catalog=False):
    asset_request, request_source = select_asset_request(asset_request, default_catalog)
    wow, product = installation(wow, product)
    output = (output or REPO / "test-output" / ("maplab-feedback-input" if asset_request else "maplab-client-input")).resolve()
    if output == wow or output.is_relative_to(wow): raise ClientInputError("Output must be outside the game installation")
    try:
        relative = output.relative_to(REPO.resolve())
    except ValueError:
        relative = None
    if relative and relative.parts and (relative.parts[0] == "!!!TwichUI" or relative.parts[0].startswith("TwichUI_")):
        raise ClientInputError("Private artwork output cannot be inside an addon package")
    zipped = output.suffix.lower() == ".zip"
    if output.exists() and not (output.is_file() if zipped else output.is_dir()):
        raise ClientInputError("Output type differs from requested ZIP/directory")
    if zipped and output.exists(): raise ClientInputError("Output ZIP already exists; use a reusable directory or another name")
    previous_path = previous = cache_warning = None
    if not zipped:
        output.mkdir(parents=True, exist_ok=True)
        previous_path, previous, cache_warning = previous_version(output)
        if cache_warning: print(cache_warning, flush=True)
    print(f"Selected installed product: {product}", flush=True)
    storage = storage_factory(str(wow), product=product)
    try:
        print(f"Installed client: build={storage.version} product={product}", flush=True)
        if asset_request:
            print(f"Collection scope: FEEDBACK ARTWORK REQUEST ({request_source}); no default-catalog fallback", flush=True)
        request = read_asset_request(asset_request, storage.version, product) if asset_request else None
        if request:
            print(f"Request: build={request['clientBuild']} product={request['product']} count={len(request['fileIds'])} sha256={digest(json_bytes(request))}", flush=True)
        else:
            print(f"Collection scope: DEFAULT CATALOG; build={storage.version} product={product}; request=none", flush=True)
        tables, sources = read_tables(storage)
        maps, reveal, world_point = model(tables)
        links = clientdata.map_links(tables, maps) if callable(getattr(clientdata, "map_links", None)) else []
        data = dict(schema=1, kind="twichui-maplab-client-input", synthetic=False,
            clientBuild=storage.version, product=product, maps=sorted(maps.values(), key=lambda m: m["id"]),
            minimap=minimap(storage), reveal=reveal, scenarios=scenarios(maps, world_point), tables=sources, mapLinks=links,
            numericSources=numeric_sources(),
            provenance="Local Forever CASC; table-derived API adapter, not native API capture",
            limitations=["Rectangle lookup cannot reproduce native zone shapes, phases or conditional artwork.",
                "Booty Bay locator is production dock 70, Data.lua build 1.60.1.70450; camera is a deterministic preset.",
                "City/WMO picture geometry remains the production pinned numeric data (1.60.1.70245), pending native alignment acceptance.",
                LOCALE["limitation"], "Private local artwork bundle; no redistribution rights inferred."])
        ids = request["fileIds"] if request else sorted(set(candidate_ids(data, world_point)))
        highlight_derivation = None
        if request and request.get("includeNativeHighlights") is True:
            extras, highlight_derivation = native_highlight_candidates(maps, links, sources)
            direct_count = len(ids)
            ids = sorted(set(ids) | set(extras))
            highlight_derivation.update(directRequestedCount=direct_count, additionalCount=len(ids) - direct_count,
                                        unionCount=len(ids))
            print(f"Native highlight candidates: {len(extras)} source file IDs, {len(ids) - direct_count} additional; union={len(ids)}; atlas-only unsupported={len(highlight_derivation['atlasOnlyUnsupported'])}", flush=True)
        if not ids or len(ids) > MAX_ASSETS or any(isinstance(v, bool) or not isinstance(v, int) or not 0 < v <= 0xffffffff for v in ids):
            raise ClientInputError("Candidate input must contain 1..2048 valid texture IDs")
        data["candidateTextureIds"] = ids
        request_identity = None
        if request:
            request_identity = dict(schema=1, sha256=digest(json_bytes(request)), count=len(ids),
                provenance=request.get("provenance", "Explicit production-Lua artwork request; provenance description unavailable"))
            data["assetRequest"] = request_identity
            if highlight_derivation:
                request_identity.update(includeNativeHighlights=True, directRequestedCount=len(request["fileIds"]),
                                        derivedHighlightCount=len(highlight_derivation["fileIds"]))
        print(f"Forever {storage.version}: {len(maps)} map records, {len(ids)} candidate textures", flush=True)
        # Directory-local staging makes version publication atomic on the same filesystem.
        stage_parent = output if not zipped else output.parent
        stage_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".maplab-stage-", dir=stage_parent) as temporary:
            folder = Path(temporary) / "version"; assets = folder / "assets"; assets.mkdir(parents=True)
            records, missing, unsupported, total, reused, fresh_reads = {}, [], [], 0, 0, 0
            prior_records = previous.get("assets", {}) if previous and previous.get("product") == product and previous.get("locale") == LOCALE else {}
            for n, file_id in enumerate(ids, 1):
                key, ckey = str(file_id), source_key(storage, file_id)
                try:
                    old = prior_records.get(key)
                    raw = None
                    if ckey and old and old.get("sourceCKey") == ckey:
                        # Recheck bytes at point of reuse as well as initial cache validation.
                        cached = previous_path / "assets" / old["file"]
                        candidate = cached.read_bytes()
                        if digest(candidate) == old["sha256"]:
                            raw = candidate; reused += 1
                    if raw is None:
                        fresh_reads += 1
                        raw = storage.read(file_id)
                    if raw is None:
                        missing.append(dict(fileId=file_id, reason="not stored locally or encrypted")); continue
                    try: header = texture_header(raw)
                    except BundleError as error:
                        issue = dict(fileId=file_id, reason=str(error)[:160]); missing.append(issue); unsupported.append(issue); continue
                    total += len(raw)
                    if total > MAX_BYTES: raise ClientInputError("Artwork input exceeded 128 MiB; no entire-game copy attempted")
                    (assets / f"{file_id}.blp").write_bytes(raw)
                    sha = digest(raw)
                    records[key] = dict(file=f"{file_id}.blp", fileId=file_id, sha256=sha, sourceSha256=sha,
                        sourceCKey=ckey, header=header, kind="local-client-artwork", clientBuild=storage.version,
                        provenance=f"Local Forever CASC; {product}; build {storage.version}; file-data ID {file_id}; {LOCALE['selected']}")
                except casc.CascError as error:
                    missing.append(dict(fileId=file_id, reason=str(error)[:160]))
                if n % 100 == 0: print(f"Read/reused {n}/{len(ids)} candidates", flush=True)
            (folder / "client.json").write_bytes(json_bytes(data))
            manifest = dict(schema=SCHEMA, kind="twichui-maplab-artwork-bundle", tool=dict(name=TOOL_NAME, version=TOOL_VERSION, schema=SCHEMA),
                assets=records, missing=missing, unsupported=unsupported, candidateTextureIds=ids,
                clientMetadataSha256=digest(json_bytes(data)),
                clientBuild=storage.version, product=product, locale=dict(LOCALE),
                settings=dict(maxTextures=MAX_ASSETS, maxRawBytes=MAX_BYTES, maxTextureBytes=MAX_TEXTURE_BYTES,
                              transferPartBytes=PART_BYTES, scenarioCatalog="booty-bay-undercity-zone-border-v1", nativeApiCaptured=False),
                redistribution="Private local debugging input only; do not commit or publish")
            if request_identity: manifest["settings"]["assetRequest"] = request_identity
            if request_identity: manifest["settings"]["scenarioCatalog"] = "production-lua-asset-request-v1"
            if highlight_derivation: manifest["settings"]["nativeHighlights"] = highlight_derivation
            validation = validate_manifest(manifest, assets, data)
            manifest["validation"] = validation
            if validation["status"] == "failure":
                raise ClientInputError("New artwork bundle failed validation; prior current version preserved: " + "; ".join(validation["errors"][:3]))
            (assets / "manifest.json").write_bytes(json_bytes(manifest))
            update = build_diff(previous, manifest, reused, fresh_reads)
            update.update(status=validation["status"], cacheWarning=cache_warning or False)
            if request_identity: update["assetRequest"] = request_identity
            if zipped:
                outputs = pack(folder, output)
            else:
                identity = digest(json_bytes(manifest))
                build_label = re.sub(r"[^A-Za-z0-9_.-]", "_", str(storage.version))[:80]
                version_name = f"{build_label}-{identity[:16]}"
                if request_identity: version_name = f"{build_label}-feedback-{request_identity['sha256'][:12]}-{identity[:16]}"
                versions = output / "versions"; versions.mkdir(exist_ok=True)
                if versions.is_symlink(): raise ClientInputError("Versions directory must not be a symlink")
                destination = versions / version_name
                valid_existing = False
                if destination.exists():
                    try:
                        if destination.is_symlink(): raise BundleError("version path is a symlink")
                        existing = destination / "assets/manifest.json"
                        if existing.is_symlink() or existing.stat().st_size > 8 * 1024 * 1024 or existing.read_bytes() != json_bytes(manifest):
                            raise BundleError("immutable version metadata differs")
                        if (destination / "client.json").read_bytes() != json_bytes(data): raise BundleError("immutable client metadata differs")
                        checked = validate_manifest(manifest, destination / "assets", data)
                        if checked["status"] != validation["status"]: raise BundleError("immutable asset validation failed")
                        outputs = sorted(destination.glob("TwichUI-map-art*.zip"))
                        if not outputs: raise BundleError("transport ZIPs are absent")
                        validate_transport(outputs, manifest, data)
                        valid_existing = True
                    except (OSError, ValueError, zipfile.BadZipFile):
                        # Do not overwrite even a damaged old version. A fresh validated
                        # copy gets its own immutable directory and pointer.
                        version_name += "-repair-" + uuid.uuid4().hex[:8]
                        destination = versions / version_name
                if not valid_existing:
                    zip_name = (f"TwichUI-map-art-feedback-{request_identity['sha256'][:12]}.zip"
                                if request_identity else "TwichUI-map-art.zip")
                    staged_outputs = pack(folder, folder / zip_name)
                    os.rename(folder, destination)
                    outputs = [destination / path.name for path in staged_outputs]
                pointer = dict(schema=1, version="versions/" + version_name, clientBuild=storage.version,
                               manifestSha256=identity, status=validation["status"],
                               bundles=[path.relative_to(output).as_posix() for path in outputs])
                if request_identity: pointer["assetRequest"] = request_identity
                atomic_json(output / "latest.json", pointer)
                if validation["status"] == "success": atomic_json(output / "current.json", pointer)
                else: print("PARTIAL: previous successful current.json retained; latest.json points to the inspectable partial version.")
                atomic_json(output / "latest-update.json", update)
            print(f"Prepared {len(records)} textures ({total / 1048576:.1f} MiB), {len(missing)} unavailable; validation={validation['status']}")
            if request_identity:
                print(f"FEEDBACK SCOPE VALIDATED: build={storage.version} product={product} requested={len(ids)} available={len(records)} missing={len(missing)} requestSha256={request_identity['sha256']}; status={validation['status']}")
            print(f"Update: build {update['previousBuild']} -> {update['currentBuild']}; reused {reused}, fresh {update['freshReads']}, added {len(update['added'])}, changed {len(update['changed'])}, removed {len(update['removed'])}")
            for target in outputs: print(f"PRIVATE INPUT: {target} ({target.stat().st_size / 1048576:.1f} MiB)")
            print("Return only these ZIP files through the existing private channel. No automatic upload occurs.")
            return outputs
    finally:
        storage.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow", type=Path, help="_forever_ or installation root; omitted opens a folder picker")
    parser.add_argument("--output", type=Path, help="reusable directory, or new .zip; default feedback/normal cache follows selected scope")
    parser.add_argument("--product", help="override automatic selection with an installed .build.info product")
    parser.add_argument("--make-kit", type=Path, help="make a reusable source-only gaming-PC handoff ZIP")
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--asset-request", type=Path, help="explicit exact artwork request; overrides a request bundled in this kit")
    scope.add_argument("--default-catalog", action="store_true", help="explicitly ignore a bundled request and collect the normal catalog")
    args = parser.parse_args()
    try:
        if args.make_kit:
            if args.wow: raise ClientInputError("Source-kit creation does not use a game installation")
            print(make_kit(args.make_kit, args.asset_request, args.default_catalog)); return 0
        if args.wow is None:
            try:
                import tkinter
                from tkinter import filedialog
                window = tkinter.Tk(); window.withdraw()
                chosen = filedialog.askdirectory(title="Select _forever_ or the WoW installation root (read-only)")
                window.destroy()
            except Exception as error:
                raise ClientInputError("Folder picker unavailable; run again with --wow followed by the installation path") from error
            if not chosen: print("Cancelled; no artwork collected."); return 0
            args.wow = Path(chosen)
        collect(args.wow, args.output, args.product, asset_request=args.asset_request, default_catalog=args.default_catalog)
        return 0
    except (OSError, ValueError, casc.CascError, db2.DB2Error) as error:
        print(f"maplab collector: {error}", file=sys.stderr); return 2


if __name__ == "__main__":
    raise SystemExit(main())
