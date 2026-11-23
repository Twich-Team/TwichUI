"""Bounded private ZIP import and a data-only bridge to the existing Lua fixture."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
import zipfile

from render import LabError, load_json
from clientdata import TABLES


def unpack(paths, target):
    if not 1 <= len(paths) <= 8:
        raise LabError("Supply all collector ZIP parts, at most eight")
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
                limit = 8 * 1024 * 1024 if name.endswith(".json") else 16 * 1024 * 1024
                total += member.file_size
                if member.file_size > limit or total > 144 * 1024 * 1024 or len(seen) >= 2050:
                    raise LabError("Collector input byte/member budget exceeded")
                seen.add(name)
                destination = target / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.read(member))
    if not {"client.json", "assets/manifest.json"} <= seen:
        raise LabError("Missing collector metadata: supply every ZIP part")
    data, manifest = load_json(target / "client.json"), target / "assets/manifest.json"
    cached = load_json(manifest)
    if cached.get("clientBuild") != data.get("clientBuild"):
        raise LabError("Client metadata and artwork build differ")
    for key, record in cached.get("assets", {}).items():
        if record.get("file") != key + ".blp" or record.get("clientBuild") != data.get("clientBuild"):
            raise LabError("Invalid client artwork identity")
        source = target / "assets" / record["file"]
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != record.get("sha256"):
            raise LabError("Collector texture absent or hash differs; supply every ZIP part")
    data["bundleSha256"] = hashes
    return data, manifest


def number(value, integer=False, limit=1e9):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or abs(value) > limit:
        raise LabError("Invalid numeric client API input")
    if integer and value != int(value):
        raise LabError("Client API identifier must be an integer")
    return str(int(value)) if integer else format(value, ".17g")


def write_tables(data, path):
    try:
        _write_tables(data, path)
    except (TypeError, KeyError, AttributeError, ValueError) as error:
        raise LabError("Invalid client input: " + str(error)[:160]) from error


def _write_tables(data, path):
    if data.get("schema") != 1 or data.get("kind") != "twichui-maplab-client-input":
        raise LabError("Expected collector client-input schema 1")
    build = data.get("clientBuild")
    if not isinstance(build, str) or not re.fullmatch(r"[0-9.]{3,40}", build):
        raise LabError("Invalid client build identity")
    for name, (file_id, layout, table_hash) in TABLES.items():
        entry = data.get("tables", {}).get(name, {})
        if (entry.get("fileId"), entry.get("layout"), entry.get("tableHash")) != (file_id, f"{layout:08X}", f"{table_hash:08X}"):
            raise LabError("Collector schema provenance differs from reviewed Forever definitions")
    maps = data.get("maps")
    if not isinstance(maps, list) or not 7 <= len(maps) <= 2000:
        raise LabError("Invalid client map input count")
    lines = ["source\t" + build + "\t" + ("1" if data.get("synthetic") is True else "0")]
    seen = set()
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
        values += [number(m.get("cont", -1), True)]
        values += [number(m.get(k, 0)) for k in ("xN", "yW", "W", "H")]
        values += [number(v) for v in bounds] + [number(v, True, 8192) for v in layer]
        values += [",".join(number(v, True, 2**32 - 1) for v in files)]
        lines.append("map\t" + "\t".join(values))
    if not {947, 1415, 1414, 1434, 1458, 1429, 1436} <= seen:
        raise LabError("Required Forever geography is absent")
    count = 0
    for cont, tiles in data.get("minimap", {}).items():
        if cont not in ("0", "1") or not isinstance(tiles, list) or len(tiles) > 4096:
            raise LabError("Invalid continent minimap input")
        for row in tiles:
            if not isinstance(row, list) or len(row) != 3:
                raise LabError("Invalid minimap tuple")
            lines.append("mini\t" + cont + "\t" + "\t".join(number(v, True, 2**32 - 1) for v in row))
    for art, pieces in data.get("reveal", {}).items():
        art = number(int(art), True)
        if not isinstance(pieces, list):
            raise LabError("Invalid overlay list")
        for p in pieces:
            count += 1
            if count > 10000 or not isinstance(p, list) or len(p) != 5 or not isinstance(p[4], list) or len(p[4]) > 256:
                raise LabError("Overlay input exceeds shape/count budget")
            lines.append("reveal\t" + art + "\t" + "\t".join(number(v, True, 8192) for v in p[:4]) + "\t" +
                         ",".join(number(v, True, 2**32 - 1) for v in p[4]))
    scenes = data.get("scenarios")
    if not isinstance(scenes, list) or not 1 <= len(scenes) <= 24:
        raise LabError("Invalid client scenario count")
    for s in scenes:
        if not re.fullmatch(r"[a-z0-9-]{1,70}", s.get("id", "")) or s.get("mapId") not in seen:
            raise LabError("Invalid client scenario identity")
        label = s.get("label", s["id"])
        if not isinstance(label, str) or not re.fullmatch(r"[A-Za-z0-9 /.-]{1,120}", label):
            raise LabError("Invalid scenario label")
        lines.append("scene\t" + s["id"] + "\t" + number(s["mapId"], True) + "\t" +
                     "\t".join(number(s[k], limit=1000) for k in ("x", "y", "zoom")) + "\t" + label)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
