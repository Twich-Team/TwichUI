#!/usr/bin/env python3
"""Private source-aware world-composition experiment, never a runtime asset build.

Requires Pillow, NumPy and SciPy in the OFFLINE development environment only.
Example:
  python3 tools/maplab/composition.py --client-input /private/client.json \
    --assets /private/assets/manifest.json --state /private/source-state.json \
    --scene elwynn-westfall-duskwood-12 --output test-output/map-composition

Native zone/source selection and world placement come exclusively from production
Lua metadata.baseCandidates. Source alpha is painted support, not a land oracle.
Reviewed numeric exclusions/parent title ROI below are approximate authored art
support for Forever 1.60.1.71037; no source artwork or derived pixels may be shipped.
OpenMap reference: MIT code/data/tools (6c2299f6), excluding Blizzard artwork.
No reference script is executed; no OpenMap pixels are read or copied.
The parent pixel-repair experiment is REJECTED visually and disabled by default;
--rejected-title-study exists solely to reproduce why it was rejected.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import html
import json
import math
from pathlib import Path
import time

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from scipy import ndimage, __version__ as SCIPY_VERSION
from PIL import __version__ as PILLOW_VERSION

from bundle import validate_manifest
from clientinput import write_tables
from render import Assets, LabError, composite_scene, load_json, texture_rect, validate_export
from underpaint import assemble, comparison, selected_underpaints

REPO = Path(__file__).resolve().parents[2]
VERSION = "1.0.0"
# Equal-zone mean of the five reviewed native alpha-border samples. Fixed across
# camera subsets, so selecting a different gallery cannot recolor an old view.
BORDER_TARGET_RGB = [143.0780239367152, 112.49565621920298, 46.957604929170046]
CALIBRATED_BASE_PIXELS = {
    1415: "ae6486160dba6ac6521c798736ca1373ee950b9d01767ae2a4dbe3025dae7b25",
    1420: "bec3ad2b2ca5c3d90024135edb6fb54fd12b94b970aa5904558e7c6947254249",
    1429: "ca1d7eb10a5f3e1854bcf5f489b766475308c290713eebab6053260fdba72f7f",
    1431: "b7b34ea69a307fd11207fd5d980eef08d6ca7fd179e841ad85655e6ff2800cb8",
    1434: "646e7c1f767591405f67452336124639844182e16fc3bb329359264da0a89f9e",
    1436: "6df4a51ea8b4a54aef52ef14eabff252c57ca8855979da93df478709f463f02c",
}


def calibrated(image, map_id):
    actual = hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()
    if CALIBRATED_BASE_PIXELS.get(map_id) != actual:
        raise LabError("native base pixels differ from authored calibration; review new source art first")
    return actual
# Authored after inspecting native base canvases with a 100-source-pixel grid.
# These exclude known neighbor/ocean labels, not the zone's own detailed labels.
EXCLUSIONS = {
    1429: [(0, 535, 180, 590), (560, 600, 785, 666), (660, 45, 1002, 140)],
    1436: [(755, 45, 1002, 145), (735, 345, 1002, 435), (50, 230, 275, 345)],
    1431: [(35, 25, 335, 95), (210, 585, 680, 668)],
    1434: [(760, 45, 1002, 150), (510, 440, 750, 565)],
    1420: [(535, 30, 775, 150), (170, 520, 500, 625), (720, 565, 1002, 666)],
}
# The title crosses both shores. These guards prevent treating shoreline ink as
# title ink. They are deliberately labeled approximate; not recovered geography.
PARENT_ROI = (335, 352, 665, 446)
TITLE_ROWS = [(346, 364, 540, 398), (406, 399, 651, 433)]
TITLE_GLYPHS = [(350, 370), (382, 405), (408, 429), (433, 457), (460, 481), (486, 510), (512, 538)]
TITLE_GLYPHS_2 = [(408, 438), (440, 458), (458, 485), (495, 524), (526, 554), (557, 586), (589, 623), (628, 651)]
COAST_GUARDS = [
    [(394, 349), (400, 360), (396, 375), (406, 390), (401, 406), (393, 421), (403, 441)],
    [(590, 350), (599, 369), (601, 389), (621, 406), (640, 421), (629, 441)],
]
LIMITATIONS = [
    "Private offline hybrid experiment; runtimeEnabled=false; no redistribution rights inferred.",
    "Native RGB/placement retained for zones except explicitly measured border-only grading.",
    "Overlay alpha is painted support, not complete land/territory or native phase geometry.",
    "Authored exclusions/title ROI/coast guards are approximate art support for reviewed build only.",
    "Parent ink is suppressed onto a color/paper fallback, not recovered or invented geographic detail.",
    "No cave/city semantic cuts, new LOD atlases or native-client performance/acceptance established.",
]


def smooth(value):
    value = np.clip(value, 0, 1)
    return value * value * (3 - 2 * value)


def source_masks(alpha, exclusions=(), frame=28, reach=65, band=50, core=36):
    """Native painted support -> bounded territory/core/band, never RGB rules."""
    a = np.asarray(alpha, dtype=np.float32) / 255
    if a.ndim != 2 or a.size > 4_194_304 or min(a.shape) < 2:
        raise LabError("bounded source alpha canvas required")
    h, w = a.shape
    owned = ndimage.binary_fill_holes(ndimage.binary_closing(a > .65, iterations=3))
    inside = ndimage.distance_transform_edt(owned)
    outside = ndimage.distance_transform_edt(~owned)
    yy, xx = np.indices(a.shape)
    edge = np.minimum.reduce((xx, yy, w - 1 - xx, h - 1 - yy))
    frame_keep = smooth((edge - frame) / max(1, frame))
    allowed = Image.new("L", (w, h), 255); draw = ImageDraw.Draw(allowed)
    for rectangle in exclusions: draw.rectangle(rectangle, fill=0)
    allowed = np.asarray(allowed.filter(ImageFilter.GaussianBlur(5)), dtype=np.float32) / 255
    territory = smooth((reach - outside) / max(1, reach)) * frame_keep * allowed
    core_mask = smooth((inside - 12) / max(1, core))
    band_mask = smooth((band - inside) / max(1, band)) * (a > .65) * allowed
    # Never claim another source mask is authoritative land classification.
    return {"territory": territory.astype(np.float32), "core": core_mask.astype(np.float32),
            "band": band_mask.astype(np.float32), "distance": outside.astype(np.float32),
            "support": a}


def border_grade(image, band_mask, core_mask, target):
    """Correct boundary chroma only; preserve luminance and opaque core RGB."""
    raw = np.asarray(image).copy()
    rgb = raw[..., :3].astype(np.float32)
    select = (band_mask > .65) & (raw[..., 3] > 220) & (core_mask < .1)
    if np.count_nonzero(select) < 32:
        return image.copy(), dict(applied=False, samples=int(np.count_nonzero(select)))
    mean = np.mean(rgb[select], axis=0)
    lum = np.array([.2126, .7152, .0722], dtype=np.float32)
    own_luma, target_luma = float(mean @ lum), float(np.asarray(target) @ lum)
    if own_luma <= 0 or target_luma <= 0:
        return image.copy(), dict(applied=False, samples=int(np.count_nonzero(select)))
    desired = np.asarray(target, dtype=np.float32) * own_luma / target_luma
    gain = np.clip(desired / np.maximum(mean, 1), .84, 1.16)
    strength = band_mask * (1 - core_mask) * .65
    graded = rgb * gain
    # Per-pixel luminance is retained, rather than making all biomes equally bright.
    y0, y1 = rgb @ lum, graded @ lum
    graded *= (y0 / np.maximum(y1, 1e-6))[..., None]
    rgb = rgb * (1 - strength[..., None]) + graded * strength[..., None]
    result = raw.copy(); result[..., :3] = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    result[core_mask >= .999] = raw[core_mask >= .999]
    return Image.fromarray(result), dict(applied=True, samples=int(np.count_nonzero(select)),
        meanRgb=[round(float(x), 4) for x in mean], chromaGain=[round(float(x), 6) for x in gain],
        corePixelsChanged=int(np.count_nonzero(np.any(result[core_mask >= .999] != raw[core_mask >= .999], axis=1))),
        beforeBoundaryChromaDistance=round(float(np.linalg.norm(mean / own_luma - np.asarray(target) / target_luma)), 6),
        afterBoundaryChromaDistance=round(float(np.linalg.norm(np.mean(result[..., :3][select], axis=0) / float(np.mean(result[..., :3][select], axis=0) @ lum) - np.asarray(target) / target_luma)), 6))


def parent_label_field(image):
    """Suppress reviewed title ink; preserve source/coast outside bounded ROI."""
    if image.size != (1002, 668): raise LabError("parent calibration requires 1002x668 native canvas")
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    light = np.mean(rgb, axis=2)
    roi = Image.new("L", image.size); d = ImageDraw.Draw(roi)
    for box in TITLE_ROWS: d.rectangle(box, fill=255)
    guard = Image.new("L", image.size); g = ImageDraw.Draw(guard)
    for points in COAST_GUARDS: g.line(points, fill=255, width=10, joint="curve")
    roi_a = np.asarray(roi, dtype=np.float32) / 255
    guard_a = np.asarray(guard.filter(ImageFilter.GaussianBlur(1.2)), dtype=np.float32) / 255
    # Authored character cells bound detection to the reviewed English title.
    # This avoids deleting similarly dark parchment grain throughout a rectangle.
    # Thresholds describe known title ink, never land/ocean classification.
    ink = np.zeros_like(light, dtype=np.float32)
    components = 0
    for boxes, row in ((TITLE_GLYPHS, TITLE_ROWS[0]), (TITLE_GLYPHS_2, TITLE_ROWS[1])):
        for x0, x1 in boxes:
            y0, y1 = row[1], row[3]
            selected = light[y0:y1, x0:x1] < 70
            ink[y0:y1, x0:x1] = selected.astype(np.float32)
            components += bool(np.any(selected))
    ink = ndimage.gaussian_filter(ndimage.maximum_filter(ink, size=5), .8) * roi_a * (1 - guard_a)
    # A low-frequency color field is deliberately devoid of invented features.
    field = np.asarray(image.convert("RGB").filter(ImageFilter.GaussianBlur(22)), dtype=np.float32)
    yy, xx = np.indices(light.shape)
    grain = (np.sin(xx * 1.618 + yy * 2.414) + np.sin(xx * .47 - yy * .83)) * .8
    field = np.clip(field + grain[..., None], 0, 255)
    result = np.asarray(image).copy()
    result[..., :3] = np.clip(np.rint(rgb * (1 - ink[..., None]) + field * ink[..., None]), 0, 255).astype(np.uint8)
    outside = roi_a == 0
    protected = np.asarray(guard) == 255
    result[outside | protected] = np.asarray(image)[outside | protected]
    return Image.fromarray(result), Image.fromarray(np.rint(ink * 255).astype(np.uint8)), dict(
        roi=list(PARENT_ROI), titleRows=TITLE_ROWS, titleGlyphCells=[TITLE_GLYPHS, TITLE_GLYPHS_2], detectedComponents=int(components), coastGuardPolylines=COAST_GUARDS,
        changedPixels=int(np.count_nonzero(np.any(result != np.asarray(image), axis=2))),
        protectedCoastPixelsChanged=int(np.count_nonzero(np.any(result[protected] != np.asarray(image)[protected], axis=1))),
        outsideRoiPixelsChanged=int(np.count_nonzero(np.any(result[outside] != np.asarray(image)[outside], axis=1))),
        status="heuristic authored title support; not recovered underlying geography")


def base_canvas(data, mid, assets):
    m = next((m for m in data["maps"] if m["id"] == mid), None)
    if not m: raise LabError("declared source map absent")
    w, h, tw, th = m["layer"]; out = Image.new("RGBA", (w, h)); cols = math.ceil(w / tw)
    for i, fid in enumerate(m["files"]):
        tile = assets.get(str(fid))
        if tile is None: raise LabError("native parent texture unavailable")
        x, y = i % cols * tw, i // cols * th
        out.alpha_composite(tile.crop((0, 0, min(tw, w - x), min(th, h - y))), (x, y))
    return out, m


def image_float(values):
    return Image.fromarray(np.asarray(values, dtype=np.float32))


def on_view(values, bounds, scene):
    """Rasterize only an already-selected Lua rectangle; no geographic choice."""
    l, t, r, b = texture_rect(bounds)
    v = scene["view"]; width, height = scene["width"], scene["height"]
    h, w = values.shape
    return np.asarray(image_float(values).transform((width, height), Image.Transform.AFFINE,
        ((v["u1"] - v["u0"]) / width / (r - l) * w, 0, (v["u0"] - l) / (r - l) * w,
         0, (v["v1"] - v["v0"]) / height / (b - t) * h, (v["v0"] - t) / (b - t) * h),
        Image.Resampling.BILINEAR, fillcolor=0), dtype=np.float32)


def ownership_masks(items, scene):
    claims, cores = {}, {}
    for mid, item in items.items():
        support = on_view(item["masks"]["territory"], item["bounds"], scene)
        distance = on_view(item["masks"]["distance"], item["bounds"], scene)
        core = on_view(item["masks"]["core"], item["bounds"], scene)
        claims[mid] = support * np.exp(-np.minimum(distance, 160) / 28)
        cores[mid] = core
    result = {}
    total = sum(claims.values()) if claims else np.zeros((scene["height"], scene["width"]), dtype=np.float32)
    for mid, claim in claims.items():
        others = np.maximum.reduce([c for k, c in cores.items() if k != mid]) if len(cores) > 1 else np.zeros_like(claim)
        # Share overlap; another zone's strong core remains exclusively its own.
        result[mid] = claim / np.maximum(total, 1) * (1 - others)
    return result


def run(client, manifest, state_path, scene_ids, output, rejected_title_study=False):
    started = time.perf_counter()
    data, manifest_data, state = load_json(client), load_json(manifest), load_json(state_path)
    write_tables(data); validate_export(state)
    if data["clientBuild"] != "1.60.1.71037" or state["provenance"].get("clientBuild") != data["clientBuild"]:
        raise LabError("authored prototype calibration requires matching reviewed Forever1.60.1.71037 inputs")
    validation = validate_manifest(manifest_data, manifest.parent, data)
    if validation["status"] == "failure": raise LabError("source bundle failed validation")
    if not scene_ids or len(scene_ids) > 12 or len(set(scene_ids)) != len(scene_ids): raise LabError("one to twelve distinct scenes required")
    scenes = [s for s in state["scenes"] if s["id"] in scene_ids]
    if any(s.get("metadata", {}).get("art", {}).get("unexploredMode") != "show" for s in scenes):
        raise LabError("prototype requires Lua-exported unexplored=show; no exploration state is guessed")
    if len(scenes) != len(scene_ids): raise LabError("selected Lua scene absent")
    output = output.resolve()
    protected = [p.resolve() for p in REPO.iterdir() if p.is_dir() and any(p.glob("*.toc"))]
    if output == REPO or any(output == p or output.is_relative_to(p) for p in protected): raise LabError("private output cannot be in addon package")
    output.mkdir(parents=True, exist_ok=False)
    assets = Assets(manifest, REPO / "!!!TwichUI")
    report = dict(schema=1, kind="twichui-maplab-composition-prototype", tool=dict(version=VERSION,
        sourceSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()), runtimeEnabled=False,
        nativeClientConfirmed=False, semanticMasksVerified=False, clientBuild=data["clientBuild"],
        clientMetadataSha256=hashlib.sha256(client.read_bytes()).hexdigest(),
        manifestSha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),
        productionStateSha256=hashlib.sha256(state_path.read_bytes()).hexdigest(),
        sourceValidation=validation, limitations=LIMITATIONS, sourceZones={}, scenes=[],
        dependencies=dict(Pillow=PILLOW_VERSION, numpy=np.__version__, scipy=SCIPY_VERSION),
        settings=dict(frameSourcePixels=28, territoryReachSourcePixels=65,
            bandSourcePixels=50, coreSourcePixels=36, fixedBorderTargetRgb=BORDER_TARGET_RGB,
            boundarySampleProvenance="Equal-zone mean of calibrated1420/1429/1431/1434/1436 source-alpha border bands"))
    # Only process zones that production Lua selected for one of these scenes.
    selected = {c["mapId"] for s in scenes for c in s["metadata"].get("baseCandidates", [])}
    prepared = {}
    for mid in sorted(selected & EXCLUSIONS.keys()):
        base, overlay, ids = assemble(data, mid, assets)
        calibrated(base, mid)
        masks = source_masks(overlay.getchannel("A"), EXCLUSIONS[mid])
        prepared[mid] = dict(base=base, overlay=overlay, masks=masks, ids=ids)
        assets.release_sources()
    target = np.array(BORDER_TARGET_RGB, dtype=np.float32)
    for mid, item in prepared.items():
        item["graded"], grade = border_grade(item["overlay"], item["masks"]["band"], item["masks"]["core"], target)
        for key in ("territory", "core", "band"):
            Image.fromarray(np.rint(item["masks"][key] * 255).astype(np.uint8)).save(output / f"{mid}-{key}.png")
        item["graded"].save(output / f"{mid}-graded-overlay.png")
        report["sourceZones"][str(mid)] = dict(sourceIds=item["ids"], authoredExclusions=EXCLUSIONS[mid], grade=grade,
            classification="native painted support with authored label/frame exclusions, not complete geography")
    parent, parent_map = base_canvas(data, 1415, assets)
    calibrated(parent, 1415)
    cleaned_parent, title_mask, title = parent_label_field(parent)
    title.update(appliedToComparison=bool(rejected_title_study), acceptance="REJECTED: patch/letter remnants remain; not production ready")
    cleaned_parent.save(output / "1415-private-title-field.png"); title_mask.save(output / "1415-title-mask.png")
    comparison(parent, cleaned_parent, left="Native parent", right="REJECTED PRIVATE title repair").save(output / "1415-rejected-title-comparison.png")
    report["parentTitle"] = title
    parent_tiles = {}
    w, h, tw, th = parent_map["layer"]; cols = math.ceil(w / tw)
    for i, fid in enumerate(parent_map["files"]):
        x, y = i % cols * tw, i // cols * th
        tile = Image.new("RGBA", (tw, th));tile.alpha_composite((cleaned_parent if rejected_title_study else parent).crop((x, y, min(x + tw, w), min(y + th, h))))
        parent_tiles[fid] = tile
    for scene in scenes:
        assets.release_sources(); before, before_state = composite_scene(scene, assets)
        # Retain explicit placeholders if native inputs are absent; never claim full verification.
        candidate = copy.deepcopy(scene)
        items = {}
        for record in scene["metadata"].get("baseCandidates", []):
            mid = record["mapId"]
            if mid not in prepared: continue
            geometry = selected_underpaints(scene, {mid: None})[0]
            items[mid] = dict(prepared[mid], bounds=geometry, alpha=record["alpha"])
        claims = ownership_masks(items, scene)
        candidate["textures"] = []
        overlay_ids = {fid for item in items.values() for fid in item["ids"]}
        styles = {}
        zone_level = next(f["level"] for f in scene["metadata"]["art"]["layers"] if f["kind"] == "zone")
        for t in scene["textures"]:
            if t.get("fileId") in overlay_ids and t.get("level") == zone_level:
                for mid, item in items.items():
                    if t["fileId"] in item["ids"] and mid not in styles:
                        styles[mid] = dict(masks=copy.deepcopy(t.get("masks", [])),
                            sublayer=t.get("sublayer", 0), order=t.get("order", 0))
                continue
            tex = copy.deepcopy(t)
            fid = tex.get("fileId")
            if fid in parent_tiles:
                key = "composition-parent:" + str(fid);assets.loaded[key] = parent_tiles[fid]
                tex.pop("fileId");tex["asset"] = key
            candidate["textures"].append(tex)
        # Native base images are composited through view-space shared claims.
        for mid, item in items.items():
            geometry = item["bounds"];mask = Image.fromarray(np.rint(claims[mid] * 255).astype(np.uint8))
            mask_key, key = f"composition-mask:{mid}", f"composition-base:{mid}"
            assets.loaded[mask_key] = Image.merge("RGBA", (Image.new("L", mask.size, 255),) * 3 + (mask,))
            assets.loaded[key] = item["base"]
            tex = dict(geometry, asset=key, alpha=item["alpha"], sublayer=-8,
                masks=[dict(asset=mask_key, **scene["view"], texCoord=[0, 1, 0, 1])] + styles.get(mid, {}).get("masks", []))
            candidate["textures"].append(tex)
            # Native full-canvas coordinates are the union of Lua base tiles;
            # replace the selected overlays, do not draw them twice.
            overlay_key = f"composition-grade:{mid}";assets.loaded[overlay_key] = item["graded"]
            candidate["textures"].append(dict(geometry, asset=overlay_key, alpha=item["alpha"], **styles.get(mid, {"masks": []})))
            mask.save(output / f"{scene['id']}-{mid}-ownership.png")
        after, after_state = composite_scene(candidate, assets)
        comparison(before, after, left="Production Lua baseline", right="PRIVATE composition hybrid prototype").save(output / f"{scene['id']}-comparison.png")
        before.save(output / f"{scene['id']}-before.png");after.save(output / f"{scene['id']}-after.png")
        difference = ImageChops.difference(before, after);diff = difference.getchannel("R")
        for channel in ("G", "B", "A"): diff = ImageChops.lighter(diff, difference.getchannel(channel))
        changed = sum(diff.histogram()[1:])
        report["scenes"].append(dict(id=scene["id"], processedMapIds=sorted(items),
            missingSourceAssets=after_state["missingAssets"], partial=bool(after_state["missingAssets"]),
            comparisonKind="changed private study" if changed else "unchanged control",
            modified=bool(changed),
            controlReason=("" if changed else "No calibrated Lua-selected zones" if not items else "Higher layers cover changes or source pixels remain equal"),
            changedPixels=changed, changedFraction=round(changed / (scene["width"] * scene["height"]), 6),
            transparentOutputPixels=after.getchannel("A").histogram()[0],
            nativeGeometry="Unmodified production Lua candidate bounds; native edge masks, overlay order and pixel placement retained",
            ownership={str(mid): dict(bounds=items[mid]["bounds"], alpha=items[mid]["alpha"],
                maskPixelSha256=hashlib.sha256(claims[mid].tobytes()).hexdigest(),
                maximum=float(np.max(claims[mid])), units="normalized claim; source-alpha support, not semantic land") for mid in items},
            maximumCombinedOwnership=float(np.max(sum(claims.values()))) if claims else 0,
            acceptance="unreviewed private prototype"))
    report["sources"] = assets.used
    report["seconds"] = round(time.perf_counter() - started, 6)
    report["status"] = "partial" if any(s["partial"] for s in report["scenes"]) else "source-complete-experiment"
    (output / "report.json").write_text(json.dumps(report, sort_keys=True, indent=2), encoding="utf-8")
    cards = []
    for entry in report["scenes"]:
        sid = html.escape(entry["id"])
        cards.append(f'<article><h2>{sid}</h2><p>{html.escape(entry["comparisonKind"])}; '
            f'{len(entry["missingSourceAssets"])} missing native assets; '
            f'changed {entry["changedFraction"]:.2%}</p><img src="{sid}-comparison.png" alt="{sid} comparison"></article>')
    (output / "index.html").write_text('<!doctype html><meta charset="utf-8"><title>Private map composition study</title>'
        '<style>body{background:#211d19;color:#e8dfd0;font:16px system-ui;margin:24px}article{margin:24px 0}img{max-width:100%;height:auto}a{color:#d6bd89}</style>'
        '<h1>Private map composition study</h1><p>Experimental derived artwork; runtime disabled. Parent title repair is rejected and off by default. '
        'Missing artwork and unchanged controls remain explicit. This is not native-client acceptance.</p>'
        '<p><a href="report.json">Provenance, ownership fields, measurements and limitations</a></p>' + ''.join(cards), encoding="utf-8")
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--client-input", type=Path, required=True);p.add_argument("--assets", type=Path, required=True)
    p.add_argument("--state", type=Path, required=True);p.add_argument("--scene", action="append", required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--rejected-title-study", action="store_true", help="apply rejected parent pixel-repair experiment for inspection only; default OFF")
    a = p.parse_args()
    try:
        r = run(a.client_input, a.assets, a.state, a.scene, a.output, a.rejected_title_study)
        print(f"Private composition: {len(r['scenes'])} scenes, {r['seconds']:.3f}s; {r['status']}; runtime disabled")
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("composition prototype: " + str(error));return 2


if __name__ == "__main__": raise SystemExit(main())
