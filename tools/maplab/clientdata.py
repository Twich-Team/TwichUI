"""Client-table API inputs, not a second map renderer. No network or game writes.

Layouts: wowdev/WoWDBDefs 3a7954cfb8ee4f1132c83cd1859753294ee8964b,
definitions/{UiMap,UiMapAssignment,UiMapArt,UiMapXMapArt,UiMapArtTile,
UiMapArtStyleLayer,WorldMapOverlay,WorldMapOverlayTile}.dbd (Forever 1.60.1).
Unknown layouts fail before interpreting columns. Coordinates are table-derived
API approximations; native area shapes/phase/condition selection remain unknown.
"""
from __future__ import annotations

import hashlib
import math
from pathlib import Path
import re
import struct
import sys

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools/navbake"))
import db2
import casc
import wowfiles

TABLES = {
    "UiMap": (1957206, 0xDB51D55F, 0x89927BF7),
    "UiMapAssignment": (1957219, 0xC9CC8DFB, 0x5153A338),
    "UiMapArt": (1957202, 0x3AE7D144, 0x05089A9C),
    "UiMapXMapArt": (1957217, 0xEAE7DA2A, 0xADB3FC8C),
    "UiMapArtTile": (1957210, 0x2DA5B77B, 0x9C7EC549),
    "UiMapArtStyleLayer": (1957208, 0x3F597F5A, 0x382DB23A),
    "WorldMapOverlay": (1134579, 0x9A196494, 0x1D740E72),
    "WorldMapOverlayTile": (1957212, 0x2C843422, 0xAC599725),
}
# Optional technical metadata: never turn an unavailable new table into a
# requirement for previously collected schema-1 client inputs.
OPTIONAL_TABLES = {"UiMapLink": (2030690, 0x712A46E6, 0x5578EDE9)}


class ClientInputError(ValueError):
    pass


def schema(table, name):
    _, layout, table_hash = (TABLES if name in TABLES else OPTIONAL_TABLES)[name]
    if table.layout_hash != layout or table.table_hash != table_hash:
        raise ClientInputError(f"Unsupported {name} schema: layout {table.layout_hash:08X}, table {table.table_hash:08X}; no columns guessed")


def read_tables(storage):
    tables, provenance = {}, {}
    for name, (file_id, _, _) in TABLES.items():
        raw = storage.read(file_id)
        if raw is None or len(raw) > 32 * 1024 * 1024:
            raise ClientInputError(f"Required local {name}.db2 unavailable or oversized ({file_id})")
        table = db2.DB2(raw)
        schema(table, name)
        tables[name] = table
        provenance[name] = dict(fileId=file_id, sha256=hashlib.sha256(raw).hexdigest(),
                                layout=f"{table.layout_hash:08X}", tableHash=f"{table.table_hash:08X}")
    for name, (file_id, _, _) in OPTIONAL_TABLES.items():
        info = dict(fileId=file_id, optional=True, status="unavailable")
        provenance[name] = info
        try:
            raw = storage.read(file_id)
            if raw is None:
                info["reason"] = "Optional local table is not stored or is encrypted"
                continue
            if len(raw) > 32 * 1024 * 1024: raise ClientInputError("Optional local table exceeds 32 MiB")
            info["sha256"] = hashlib.sha256(raw).hexdigest()
            table = db2.DB2(raw)
            info.update(layout=f"{table.layout_hash:08X}", tableHash=f"{table.table_hash:08X}")
            schema(table, name)
            # Validate the raw shape before describing optional metadata as available.
            list(_link_rows(table))
            tables[name] = table
            info["status"] = "available"
        except (casc.CascError, OSError) as error:
            info["reason"] = "Optional local table unavailable: " + type(error).__name__
        except (ClientInputError, db2.DB2Error, struct.error, IndexError, TypeError, ValueError) as error:
            info.update(status="unsupported", reason="Optional table was not interpreted: " + str(error)[:160])
    return tables, provenance


def floats(value, count):
    if not isinstance(value, (list, tuple)) or len(value) != count:
        raise ClientInputError("Client table array shape differs from reviewed schema")
    result = [db2.as_float(v) for v in value]
    if not all(math.isfinite(v) for v in result):
        raise ClientInputError("Non-finite client geometry")
    return result


def related_rows(table):
    """Use each section's local FK indices; copies inherit the source row FK."""
    rows, seen = iter(table.rows()), {}
    for section in table.sections:
        count, _, _, _, copies, _, relation = section
        for index in range(count):
            rid, columns = next(rows)
            foreign = relation.get(index)
            seen[rid] = foreign
            yield rid, columns, foreign
        for new, old in copies:
            # Match DB2.rows: it emits only copies of an existing original row.
            if old in seen:
                rid, columns = next(rows)
                yield rid, columns, seen[old]


def unsigned(value, label):
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 0xffffffff:
        raise ClientInputError("Invalid numeric " + label)
    return value


def _link_rows(table):
    """Raw layout-712A46E6 fields, not native highlight-placement rectangles."""
    count = 0
    for rid, c in table.rows():
        count += 1
        if count > 16384 or not isinstance(c, (list, tuple)) or len(c) != 10:
            raise ClientInputError("Optional UiMapLink row shape/count differs from reviewed schema")
        lo, hi = floats(c[0], 2), floats(c[1], 2)
        if max(map(abs, lo + hi)) > 1e6:
            raise ClientInputError("Optional UiMapLink coordinates exceed numeric bounds")
        if isinstance(c[4], bool) or not isinstance(c[4], int) or not -(2**31) <= c[4] <= 0xffffffff:
            raise ClientInputError("Invalid numeric UiMapLink order")
        yield dict(id=unsigned(rid, "UiMapLink ID"), parentMapId=unsigned(c[3], "parent map ID"),
            childMapId=unsigned(c[5], "child map ID"), orderIndex=c[4], playerConditionId=unsigned(c[6], "player condition ID"),
            overrideHighlightFileId=unsigned(c[7], "highlight file ID"), overrideHighlightAtlasId=unsigned(c[8], "highlight atlas member ID"),
            flags=unsigned(c[9], "UiMapLink flags"), uiMin=lo, uiMax=hi)


def map_links(tables, maps):
    """Optional numeric links for offline study; conditional records stay explicit.

    UiMin/UiMax are link-selection rectangles, NOT verified highlight bounds.
    Atlas IDs identify UiTextureAtlasMember records, not SetAtlas name strings.
    """
    table = tables.get("UiMapLink")
    if table is None: return []
    schema(table, "UiMapLink")
    rows = [row for row in _link_rows(table) if row["parentMapId"] in maps and row["childMapId"] in maps]
    if len(rows) > 4096: raise ClientInputError("Supported UiMapLink metadata exceeds 4096 records")
    return sorted(rows, key=lambda row: (row["parentMapId"], row["orderIndex"], row["id"]))


def model(tables):
    maps = {rid: dict(id=rid, parent=c[2], type=c[5]) for rid, c in tables["UiMap"].rows()}
    assignments = {}
    for rid, c in tables["UiMapAssignment"].rows():
        assignments.setdefault(c[4], []).append(dict(id=rid, lo=floats(c[0], 2), hi=floats(c[1], 2),
            region=floats(c[2], 6), order=c[5], continent=c[6], area=c[7], wmo=c[8], group=c[9]))
    for rows in assignments.values():
        rows.sort(key=lambda row: (row["order"], row["id"]))
    world = assignments.get(947, [])

    def world_point(cont, x, y):
        choices = [row for row in world if row["continent"] == cont]
        if not choices:
            raise ClientInputError(f"No world assignment for continent {cont}")
        values = []
        for a in choices:
            r, lo, hi = a["region"], a["lo"], a["hi"]
            if r[4] <= r[1] or r[3] <= r[0]:
                raise ClientInputError("Degenerate world assignment")
            values.append([lo[0] + (r[4] - y) / (r[4] - r[1]) * (hi[0] - lo[0]),
                           lo[1] + (r[3] - x) / (r[3] - r[0]) * (hi[1] - lo[1])])
        if any(abs(v[k] - values[0][k]) > 1e-6 for v in values for k in (0, 1)):
            raise ClientInputError(f"Ambiguous world assignments for continent {cont}")
        return values[0]

    art_of = {}
    for _, c, ui in related_rows(tables["UiMapXMapArt"]):
        if c[0] == 0:
            if ui in art_of and art_of[ui] != c[1]:
                raise ClientInputError("Ambiguous phase-zero map artwork")
            art_of[ui] = c[1]
    styles, highlights = {}, {}
    for rid, c in tables["UiMapArt"].rows():
        if len(c) != 3: raise ClientInputError("UiMapArt shape differs from reviewed schema")
        styles[rid] = c[2]
        highlights[rid] = dict(fileId=unsigned(c[0], "map highlight file ID"), atlasId=unsigned(c[1], "map highlight atlas member ID"))
    layers = {}
    for _, c, foreign in related_rows(tables["UiMapArtStyleLayer"]):
        if c[0] == 0:
            layers[foreign] = c[1:5]
    files = {}
    for _, c, foreign in related_rows(tables["UiMapArtTile"]):
        if c[2] == 0:
            files.setdefault(foreign, {})[(c[0], c[1])] = c[3]
    result = {}
    for ui, m in maps.items():
        if m["type"] not in (1, 2, 3) or ui not in art_of:
            continue
        # Only the stitched world's ancestry. No retail/instance maps imported.
        ancestor, seen = ui, set()
        while ancestor in maps and ancestor != 947 and ancestor not in seen:
            seen.add(ancestor); ancestor = maps[ancestor]["parent"]
        if ancestor != 947:
            continue
        art = art_of[ui]; layer = layers.get(styles.get(art)); tiles = files.get(art)
        if not layer or not tiles:
            continue
        width, height, tw, th = layer
        if min(layer) <= 0 or width > 8192 or height > 8192:
            raise ClientInputError("Invalid client artwork dimensions")
        cols, rows = math.ceil(width / tw), math.ceil(height / th)
        if cols * rows > 256 or any((r, c) not in tiles for r in range(rows) for c in range(cols)):
            raise ClientInputError(f"Incomplete base-art tile grid for map {ui}")
        row = dict(m, art=art, layer=layer, files=[tiles[(r, c)] for r in range(rows) for c in range(cols)],
                   highlight=highlights[art])
        if ui == 947:
            row["world"] = [0, 1, 0, 1]
        else:
            choices = [a for a in assignments.get(ui, []) if any(w["continent"] == a["continent"] for w in world)]
            if not choices:
                continue
            a = choices[0]
            r, lo, hi = a["region"], a["lo"], a["hi"]
            if r[3] <= r[0] or r[4] <= r[1] or hi[0] <= lo[0] or hi[1] <= lo[1]:
                continue
            # Region describes UiMin..UiMax, not necessarily the complete art.
            yW = r[4] + lo[0] * (r[4] - r[1]) / (hi[0] - lo[0])
            xN = r[3] + lo[1] * (r[3] - r[0]) / (hi[1] - lo[1])
            W, H = (r[4] - r[1]) / (hi[0] - lo[0]), (r[3] - r[0]) / (hi[1] - lo[1])
            u0, v0 = world_point(a["continent"], xN, yW)
            u1, v1 = world_point(a["continent"], xN - H, yW - W)
            row.update(world=[u0, u1, v0, v1], cont=a["continent"], xN=xN, yW=yW, W=W, H=H,
                       assignment=a["id"])
            # Multiple area/WMO records may describe one affine rectangle. Only
            # accept that equivalence; never guess which conflicting floor wins.
            for other in choices[1:]:
                rr, ll, hh = other["region"], other["lo"], other["hi"]
                if hh[0] <= ll[0] or hh[1] <= ll[1]:
                    raise ClientInputError(f"Invalid alternate assignment for map {ui}")
                ww, ht = (rr[4] - rr[1]) / (hh[0] - ll[0]), (rr[3] - rr[0]) / (hh[1] - ll[1])
                xn, yw = rr[3] + ll[1] * ht, rr[4] + ll[0] * ww
                if other["continent"] != a["continent"] or any(abs(p - q) > .05 for p, q in zip((xn, yw, ww, ht), (xN, yW, W, H))):
                    raise ClientInputError(f"Conflicting area/WMO assignments for map {ui}; native API capture required")
        result[ui] = row
    required = (947, 1415, 1414, 1434, 1458, 1429, 1436)
    if any(ui not in result for ui in required):
        raise ClientInputError("Client tables lack one of the required Forever maps: " + str(required))
    # A missing intermediate parent must not disconnect a required target.
    for m in result.values():
        if m["id"] != 947 and m["parent"] not in result:
            raise ClientInputError(f"Map {m['id']} has an unavailable parent; no ancestry guessed")
    reveal = {}; pieces = {}
    for rid, c in tables["WorldMapOverlay"].rows():
        if c[10] == 0:  # conditional overlays are not assumed active
            pieces[rid] = [c[1], c[2], c[3], c[4], c[5], {}]
    for _, c, foreign in related_rows(tables["WorldMapOverlayTile"]):
        piece = pieces.get(foreign)
        if piece and c[2] == 0:
            piece[5][(c[0], c[1])] = c[3]
    for _, (art, w, h, x, y, tiles) in sorted(pieces.items()):
        if 0 < w <= 8192 and 0 < h <= 8192:
            rows, cols = math.ceil(h / 256), math.ceil(w / 256)
            if all((r, c) in tiles for r in range(rows) for c in range(cols)):
                reveal.setdefault(str(art), []).append([w, h, x, y, [tiles[r, c] for r in range(rows) for c in range(cols)]])
    return result, reveal, world_point


def minimap(storage):
    result = {}
    for cont, file_id in ((0, 775971), (1, 782779)):
        raw = storage.read(file_id)
        if raw is None:
            raise ClientInputError(f"Missing local continent WDT {file_id}")
        maid = wowfiles.first(wowfiles.chunks(raw), "MAID")
        if not maid or maid[2] < 4096 * 32:
            raise ClientInputError("Unsupported continent WDT/MAID")
        result[str(cont)] = [[i % 64, i // 64, struct.unpack_from("<8I", raw, maid[1] + i * 32)[7]]
                             for i in range(4096) if struct.unpack_from("<8I", raw, maid[1] + i * 32)[7]]
    return result


def scenarios(maps, world_point):
    booty = world_point(0, -14277.7, 582.9)  # production Data.lua dock 70, build 1.60.1.70450
    m = maps[1434]; l, r, t, b = m["world"]
    centers = [("booty-bay", "Booty Bay dock", 1434, (booty[0] - l) / (r - l), (booty[1] - t) / (b - t))]
    centers.append(("undercity", "Undercity", 1458, .5, .5))
    a, b = maps[1429]["world"], maps[1436]["world"]
    u, v = (max(a[0], b[0]) + min(a[1], b[1])) / 2, (max(a[2], b[2]) + min(a[3], b[3])) / 2
    centers.append(("zone-border", "Elwynn / Westfall rectangle boundary region", 1429,
                    (u - a[0]) / (a[1] - a[0]), (v - a[2]) / (a[3] - a[2])))
    return [dict(id=f"{name}-{zoom}", label=f"{label} / zoom {zoom}", mapId=ui, x=x, y=y, zoom=zoom)
            for name, label, ui, x, y in centers for zoom in (12, 24, 36, 48)]


def center(m, x, y):
    l, r, t, b = m["world"]
    return l + x * (r - l), t + y * (b - t)


def intersects(a, b):
    return a[0] < b[1] and a[1] > b[0] and a[2] < b[3] and a[3] > b[2]


def candidate_ids(data, world_point, repo=REPO):
    """Conservative extraction windows only. Final visible selection is Lua's."""
    maps = {m["id"]: m for m in data["maps"]}
    points = [center(maps[s["mapId"]], s["x"], s["y"]) for s in data["scenarios"]]
    windows = [[u - .09, u + .09, v - .09, v + .09] for u, v in points]
    ids = set()
    for m in maps.values():
        if m["type"] in (1, 2) or any(intersects(m["world"], w) for w in windows):
            ids.update(m["files"])
            for p in data["reveal"].get(str(m["art"]), []):
                ids.update(p[4])
    for cont, tiles in data["minimap"].items():
        for col, row, file_id in tiles:
            # The minimap grid's cell in continent yards, as Detail.lua.
            xN, yW = (32 - row) * (1600 / 3), (32 - col) * (1600 / 3)
            u0, v0 = world_point(int(cont), xN, yW)
            u1, v1 = world_point(int(cont), xN - 1600 / 3, yW - 1600 / 3)
            if any(intersects([u0, u1, v0, v1], w) for w in windows):
                ids.add(file_id)
    # Production numeric WMO records, read as numeric data, never executed.
    text = (repo / "!!!TwichUI/map/LocalData.lua").read_text(encoding="utf-8")
    for line in text.splitlines():
        match = re.fullmatch(r'\s*(?:\[\d+\] = )?\{ ([^{}]+), \{ ([^{}]+) \} \},?', line)
        if not match:
            continue
        values = [float(x) for x in match[1].split(",")]
        pictures = [float(x) for x in match[2].split(",")]
        if len(values) != 5 or len(pictures) % 7:
            raise ClientInputError("Production numeric WMO tuple shape changed")
        cont, x0, y0, x1, y1 = values
        u0, v0 = world_point(int(cont), x1, y1); u1, v1 = world_point(int(cont), x0, y0)
        if any(intersects([u0, u1, v0, v1], w) for w in windows):
            ids.update(int(pictures[i]) for i in range(0, len(pictures), 7))
    text = (repo / "!!!TwichUI/map/Data.lua").read_text(encoding="utf-8")
    caves = text.split("D.caves = {", 1)[1].split("\n}", 1)[0]
    for line in caves.splitlines():
        match = re.search(r'\{ \d+, "[^"]+", ([01]), ([^{}]+), \{ ([\d, ]+) \}', line)
        if match:
            x0, y0, x1, y1 = [float(x) for x in match[2].split(",")]
            cont = int(match[1])
            u0, v0 = world_point(cont, x1, y1); u1, v1 = world_point(cont, x0, y0)
            if any(intersects([u0, u1, v0, v1], w) for w in windows):
                ids.update(int(x) for x in match[3].split(","))
    return sorted(ids)
