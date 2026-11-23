"""Bounded, non-executable imports of Map Diagnostics schema 1 exports."""
from __future__ import annotations

import re
import zlib

from render import LabError, finite, rect


def join_pieces(texts):
    if not 1 <= len(texts) <= 64 or sum(map(len, texts)) > 8 * 1024 * 1024:
        raise LabError("diagnostic pieces exceed input bounds")
    bodies, identity = [], None
    for i, text in enumerate(texts, 1):
        header, separator, body = text.partition("\n")
        match = re.search(r"piece (\d+)/(\d+) of (.*?) \| report (\d+) bytes, adler32 ([0-9a-f]+) \| this piece adler32 ([0-9a-f]+)", header)
        if not separator or not match:
            raise LabError("diagnostic piece header is missing or unreadable")
        index, count, label, size, whole, own = match.groups()
        if int(index) != i or int(count) != len(texts):
            raise LabError("diagnostic pieces missing or out of order")
        if f"{zlib.adler32(body.encode('utf-8')):08x}" != own:
            raise LabError("diagnostic piece checksum differs")
        current = (label, int(size), whole)
        if identity is not None and current != identity:
            raise LabError("pieces belong to different reports")
        identity = current
        bodies.append(body)
    result = "".join(bodies)
    if len(result.encode("utf-8")) != identity[1] or f"{zlib.adler32(result.encode('utf-8')):08x}" != identity[2]:
        raise LabError("joined diagnostic report checksum differs")
    return result


def import_report(data):
    if not isinstance(data, dict) or data.get("schema") != 1 or data.get("kind") != "twichui-map-diagnostics":
        raise LabError("expected a Detailed Map Diagnostics report, schema 1")
    current = data.get("current")
    if not isinstance(current, dict) or not isinstance(current.get("view"), dict):
        raise LabError("diagnostic report has no captured current view")
    view = current["view"]
    bounds = view.get("viewRect")
    if bounds is None:
        raise LabError("Precise view geometry was withheld. Capture again with Include precise view/cursor geometry enabled; no player position is needed.")
    bounds = rect(bounds, "diagnostic view")
    width = round(finite(view.get("viewportWidth"), "diagnostic viewport width"))
    height = round(finite(view.get("viewportHeight"), "diagnostic viewport height"))
    if width < 16 or height < 16 or width * height > 4_194_304:
        raise LabError("diagnostic viewport exceeds supported image budget")
    textures = []
    for row in current.get("terrain", {}).get("textures", [])[:128]:
        if not row.get("bounds"):
            continue
        textures.append({"fileId": row.get("fileId"), "bounds": rect(row["bounds"]),
                         "alpha": finite(row.get("effectiveAlpha", row.get("alpha", 1)), "terrain alpha"), "shown": row.get("shown", True),
                         "level": current.get("terrain", {}).get("level", 6)})
    for row in current.get("interiors", {}).get("pictures", [])[:128]:
        if not row.get("bounds"):
            continue
        textures.append({"fileId": row.get("fileId"), "bounds": rect(row["bounds"]),
                         "alpha": finite(row.get("effectiveAlpha", row.get("alpha", 1)), "interior alpha"), "shown": row.get("shown", True),
                         "rotation": finite(row.get("angleRadians", 0), "interior angle"),
                         "texCoord": [0, row.get("cropU1", 1), row.get("cropV0", 0), 1], "level": row.get("level", 8)})
    if not textures:
        raise LabError("diagnostic captured no selected terrain/interior texture rectangles; there is no image state to reconstruct")
    center = view.get("center", {})
    request = {"schema": 1, "kind": "twichui-maplab-scenario-request", "reportId": str(data.get("id", "unavailable"))[:100],
               "mapId": view.get("nativeMap"), "center": {k: center[k] for k in ("u", "v", "zoom") if k in center},
               "viewRect": bounds, "viewport": {"width": width, "height": height, "uiScale": view.get("uiScale")},
               "events": [{k: event[k] for k in ("kind", "atSeconds", "notches", "width", "height", "mapId") if k in event}
                          for event in data.get("events", [])[-256:] if isinstance(event, dict)],
               "replay": {"nativeClientConfirmed": False, "fullMapReplay": False,
                          "reason": "No captured native map-API fixture is available; replaying these map IDs against synthetic bounds would invent geography."}}
    exported = {"schema": 1, "provenance": {"source": "Map Diagnostics production-selected texture rectangles",
                "synthetic": False, "partial": True, "reportId": request["reportId"],
                "limitations": ["Only selected detail rectangles retained in this diagnostic schema are rendered.",
                    "Painted base art, missing/omitted picture records and complete native map geometry are not reconstructed.",
                    "Older reports without explicit interior frame levels use relative terrain/interior order 6/8.",
                    "This is an offline partial snapshot, never confirmed native-client replay."]},
                "scenes": [{"id": "diagnostic-selected-detail", "label": "Captured selected detail (partial reproduction)",
                    "width": width, "height": height, "view": dict(zip(("u0", "v0", "u1", "v1"), bounds)),
                    "textures": textures, "metadata": {"reportId": request["reportId"], "partial": True}}]}
    return request, exported
