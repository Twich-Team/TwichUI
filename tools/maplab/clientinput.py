"""Bounded private ZIP import and a data-only bridge to the existing Lua fixture."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
import stat
import zipfile

from render import LabError, load_json
from clientdata import TABLES, OPTIONAL_TABLES, unsigned
from bundle import validate_manifest


def unpack(paths, target):
    if not 1 <= len(paths) <= 8:
        raise LabError("Supply all collector ZIP parts, at most eight")
    target = target.resolve()
    total, seen = 0, set()
    hashes = []
    for path in paths:
        if path.stat().st_size > 32 * 1024 * 1024:
            raise LabError("Collector ZIP part exceeds 32 MiB")
        hashes.append(hashlib.sha256(path.read_bytes()).hexdigest())
        try:
            archive = zipfile.ZipFile(path)
        except zipfile.BadZipFile as error:
            raise LabError("Collector ZIP is invalid") from error
        with archive:
            for member in archive.infolist():
                name = member.filename
                if not re.fullmatch(r"(?:client\.json|assets/manifest\.json|assets/[1-9][0-9]{0,9}\.blp)", name) or name in seen:
                    raise LabError("Unexpected or duplicate collector ZIP member")
                if member.flag_bits & 1 or stat.S_ISLNK(member.external_attr >> 16):
                    raise LabError("Collector ZIP must not contain encrypted files or symbolic links")
                limit = 8 * 1024 * 1024 if name.endswith(".json") else 16 * 1024 * 1024
                total += member.file_size
                if member.file_size > limit or total > 144 * 1024 * 1024 or len(seen) >= 2050:
                    raise LabError("Collector input byte/member budget exceeded")
                seen.add(name)
                destination = target / name
                if not destination.resolve().is_relative_to(target):
                    raise LabError("Collector ZIP output escapes its temporary input directory")
                destination.parent.mkdir(parents=True, exist_ok=True)
                try:
                    destination.write_bytes(archive.read(member))
                except (zipfile.BadZipFile, RuntimeError) as error:
                    raise LabError("Collector ZIP member is corrupt or unreadable") from error
    if not {"client.json", "assets/manifest.json"} <= seen:
        raise LabError("Missing collector metadata: supply every ZIP part")
    data, manifest = load_json(target / "client.json"), target / "assets/manifest.json"
    cached = load_json(manifest)
    write_tables(data)  # Validate the data-only API bridge before accepting input.
    validation = validate_manifest(cached, target / "assets", data)
    if validation["status"] == "failure":
        raise LabError("Collector bundle validation failed: " + "; ".join(validation["errors"][:6]))
    # Reject unmanifested payloads as well as records whose files are missing.
    expected = {"assets/" + record["file"] for record in cached["assets"].values()}
    if seen - {"client.json", "assets/manifest.json"} != expected:
        raise LabError("Collector texture members differ from the manifest; supply every matching ZIP part")
    data["bundleSha256"] = hashes
    data["bundleValidation"] = validation
    data["bundleIdentity"] = {key: cached[key] for key in ("schema", "tool", "clientBuild", "product", "locale", "settings") if key in cached}
    return data, manifest


def number(value, integer=False, limit=1e9):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or abs(value) > limit:
        raise LabError("Invalid numeric client API input")
    if integer and value != int(value):
        raise LabError("Client API identifier must be an integer")
    return str(int(value)) if integer else format(value, ".17g")


def write_tables(data, path=None):
    try:
        _write_tables(data, path)
    except (TypeError, KeyError, AttributeError, ValueError) as error:
        raise LabError("Invalid client input: " + str(error)[:160]) from error


def _write_tables(data, path):
    if type(data.get("schema")) is not int or data.get("schema") != 1 or data.get("kind") != "twichui-maplab-client-input":
        raise LabError("Expected collector client-input schema 1")
    build = data.get("clientBuild")
    if not isinstance(build, str) or len(build) > 40 or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,4}", build):
        raise LabError("Invalid client build identity")
    numeric_sources = data.get("numericSources")
    if not isinstance(numeric_sources, dict) or any(
        not isinstance(numeric_sources.get(name), str) or not re.fullmatch(r"[a-f0-9]{64}", numeric_sources[name])
        for name in ("!!!TwichUI/map/Data.lua", "!!!TwichUI/map/LocalData.lua")
    ):
        raise LabError("Missing or invalid production numeric-source hashes")
    for name, (file_id, layout, table_hash) in TABLES.items():
        entry = data.get("tables", {}).get(name, {})
        if (entry.get("fileId"), entry.get("layout"), entry.get("tableHash")) != (file_id, f"{layout:08X}", f"{table_hash:08X}"):
            raise LabError("Collector schema provenance differs from reviewed Forever definitions")
    for name, (file_id, layout, table_hash) in OPTIONAL_TABLES.items():
        entry = data.get("tables", {}).get(name)
        if entry is None: continue  # Existing supplied bundles predate optional highlight metadata.
        if not isinstance(entry, dict) or entry.get("fileId") != file_id or entry.get("optional") is not True or entry.get("status") not in ("available", "unavailable", "unsupported"):
            raise LabError("Invalid optional client-table provenance")
        if entry["status"] == "available" and ((entry.get("layout"), entry.get("tableHash")) != (f"{layout:08X}", f"{table_hash:08X}")
            or not isinstance(entry.get("sha256"), str) or not re.fullmatch(r"[a-f0-9]{64}", entry["sha256"])):
            raise LabError("Optional client-table schema/hash differs from reviewed Forever definitions")
    maps = data.get("maps")
    if not isinstance(maps, list) or not 7 <= len(maps) <= 2000:
        raise LabError("Invalid client map input count")
    lines = ["source\t" + build + "\t" + ("1" if data.get("synthetic") is True else "0")]
    seen, parents = set(), {}
    for m in maps:
        mid = m.get("id")
        if mid in seen:
            raise LabError("Duplicate client map ID")
        seen.add(mid)
        bounds, layer, files = m.get("world"), m.get("layer"), m.get("files")
        if not isinstance(bounds, list) or len(bounds) != 4 or not isinstance(layer, list) or len(layer) != 4:
            raise LabError("Client map needs world bounds and art dimensions")
        if not isinstance(files, list) or not 1 <= len(files) <= 256:
            raise LabError("Client base artwork needs bounded texture IDs")
        if not (bounds[1] > bounds[0] and bounds[3] > bounds[2]) or min(layer) <= 0:
            raise LabError("Invalid client map rectangle/art dimensions")
        values = [number(m[k], True) for k in ("id", "parent", "type", "art")]
        if m["id"] <= 0 or m["parent"] < 0 or m["type"] not in (1, 2, 3) or m["art"] <= 0:
            raise LabError("Invalid client map identity/type")
        parents[mid] = m["parent"]
        highlight = m.get("highlight")
        if "highlight" in m:
            if not isinstance(highlight, dict) or set(highlight) != {"fileId", "atlasId"}:
                raise LabError("Invalid native highlight metadata")
            for value in highlight.values():
                unsigned(value, "native highlight ID")
        if mid != 947 and (m.get("W", 0) <= 0 or m.get("H", 0) <= 0 or m.get("cont", -1) < 0):
            raise LabError("Client map is missing positive continent-yard geometry")
        values += [number(m.get("cont", -1), True)]
        values += [number(m.get(k, 0)) for k in ("xN", "yW", "W", "H")]
        values += [number(v) for v in bounds] + [number(v, True, 8192) for v in layer]
        if any(v <= 0 for v in files):
            raise LabError("Client artwork requires positive texture IDs")
        values += [",".join(number(v, True, 2**32 - 1) for v in files)]
        lines.append("map\t" + "\t".join(values))
    if not {947, 1415, 1414, 1434, 1458, 1429, 1436} <= seen:
        raise LabError("Required Forever geography is absent")
    if parents[947] != 0:
        raise LabError("Azeroth must be the root of client map ancestry")
    for mid in seen - {947}:
        ancestor, chain = mid, set()
        while ancestor != 947:
            if ancestor in chain or ancestor not in parents or len(chain) >= 4:
                raise LabError("Client map ancestry is missing, cyclic or exceeds the renderer's supported depth")
            chain.add(ancestor); ancestor = parents[ancestor]
    if "mapLinks" in data:
        links = data["mapLinks"]
        if not isinstance(links, list) or len(links) > 4096:
            raise LabError("Invalid optional map-link count")
        if links and data.get("tables", {}).get("UiMapLink", {}).get("status") != "available":
            raise LabError("Map links require reviewed available UiMapLink provenance")
        link_ids = set()
        integer_keys = {"id", "parentMapId", "childMapId", "orderIndex", "playerConditionId",
                        "overrideHighlightFileId", "overrideHighlightAtlasId", "flags"}
        for link in links:
            if not isinstance(link, dict) or set(link) != integer_keys | {"uiMin", "uiMax"}:
                raise LabError("Invalid optional map-link shape")
            for key in integer_keys:
                if type(link[key]) is not int: raise LabError("Map-link identifiers must be integers")
                number(link[key], True, 2**32 - 1)
                if link[key] < (-(2**31) if key == "orderIndex" else 0):
                    raise LabError("Invalid optional map-link identifier")
            if link["id"] in link_ids or link["parentMapId"] not in seen or link["childMapId"] not in seen:
                raise LabError("Duplicate map link or unsupported map ancestry")
            link_ids.add(link["id"])
            for key in ("uiMin", "uiMax"):
                if not isinstance(link[key], list) or len(link[key]) != 2:
                    raise LabError("Invalid raw map-link coordinates")
                for value in link[key]: number(value, limit=1e6)
    count = 0
    for cont, tiles in data.get("minimap", {}).items():
        if cont not in ("0", "1") or not isinstance(tiles, list) or len(tiles) > 4096:
            raise LabError("Invalid continent minimap input")
        for row in tiles:
            if not isinstance(row, list) or len(row) != 3:
                raise LabError("Invalid minimap tuple")
            if not (0 <= row[0] <= 63 and 0 <= row[1] <= 63 and row[2] > 0):
                raise LabError("Minimap coordinates/file ID outside supported range")
            lines.append("mini\t" + cont + "\t" + "\t".join(number(v, True, 2**32 - 1) for v in row))
    for art, pieces in data.get("reveal", {}).items():
        art = number(int(art), True)
        if not isinstance(pieces, list):
            raise LabError("Invalid overlay list")
        for p in pieces:
            count += 1
            if count > 10000 or not isinstance(p, list) or len(p) != 5 or not isinstance(p[4], list) or len(p[4]) > 256:
                raise LabError("Overlay input exceeds shape/count budget")
            if p[0] <= 0 or p[1] <= 0 or not p[4] or any(v <= 0 for v in p[4]):
                raise LabError("Overlay requires positive dimensions and file IDs")
            lines.append("reveal\t" + art + "\t" + "\t".join(number(v, True, 8192) for v in p[:4]) + "\t" +
                         ",".join(number(v, True, 2**32 - 1) for v in p[4]))
    scenes = data.get("scenarios")
    if not isinstance(scenes, list) or not 1 <= len(scenes) <= 24:
        raise LabError("Invalid client scenario count")
    scene_ids = set()
    for s in scenes:
        if not re.fullmatch(r"[a-z0-9-]{1,70}", s.get("id", "")) or s.get("mapId") not in seen:
            raise LabError("Invalid client scenario identity")
        if s["id"] in scene_ids:
            raise LabError("Duplicate client scenario ID")
        scene_ids.add(s["id"])
        label = s.get("label", s["id"])
        if not isinstance(label, str) or not re.fullmatch(r"[A-Za-z0-9 /.-]{1,120}", label):
            raise LabError("Invalid scenario label")
        if s["zoom"] < 1:
            raise LabError("Client scenario zoom must be at least world fit")
        lines.append("scene\t" + s["id"] + "\t" + number(s["mapId"], True) + "\t" +
                     "\t".join(number(s[k], limit=1000) for k in ("x", "y", "zoom")) + "\t" + label)
    if path is not None:
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
