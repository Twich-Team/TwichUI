#!/usr/bin/env python3
"""Render a bounded production-Lua map state into PNGs and an HTML gallery.

Examples:
  python3 tools/maplab/run.py --all
  python3 tools/maplab/run.py --all --assets test-output/map-assets/manifest.json --strict
  python3 tools/maplab/run.py --diagnostic report.json --output test-output/maplab-issue

No network, game control, source-art redistribution or runtime addon dependency.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageDraw

from assets import extract, probe
from diagnostics import import_report, join_pieces
from render import Assets, LabError, compare_images, composite_scene, load_json, rect, texture_rect, validate_export

REPO = Path(__file__).resolve().parents[2]


def production_export():
    with tempfile.TemporaryDirectory(prefix="twichui-maplab-") as folder:
        destination = Path(folder) / "render-state.json"
        env = dict(os.environ, TWICHUI_MAPLAB_EXPORT=str(destination))
        code = ('require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"; '
                'MAPLAB_EXPORT_FILE=os.getenv("TWICHUI_MAPLAB_EXPORT"); dofile("test_map_explore.lua")')
        started = time.perf_counter()
        try:
            process = subprocess.run(["lua5.1", "-e", code], cwd=REPO / "tests", env=env,
                                     capture_output=True, text=True, timeout=120)
        except FileNotFoundError as exc:
            raise LabError("lua5.1 is unavailable; activate the repository's existing Lua environment first") from exc
        except subprocess.TimeoutExpired as exc:
            raise LabError("production render-state export exceeded 120 seconds") from exc
        if process.returncode:
            raise LabError("production Lua export failed:\n" + (process.stdout + process.stderr)[-6000:])
        if not destination.is_file():
            raise LabError("production Lua export did not create render-state.json; the maplab export hook must be loaded")
        return load_json(destination), {"seconds": round(time.perf_counter() - started, 6),
                                        "source": "tests/test_map_explore.lua production map fixture",
                                        "stdoutTail": process.stdout.splitlines()[-3:]}


def transition_checks(scenes):
    groups, findings = {}, []
    for scene in scenes:
        metadata = scene.get("metadata", {})
        sequence = metadata.get("sequence")
        if sequence:
            groups.setdefault(str(sequence), []).append(scene)
    for name, frames in groups.items():
        for previous, current in zip(frames, frames[1:]):
            def selected(scene):
                return {(str(t.get("fileId", t.get("asset"))), texture_rect(t)): t.get("alpha", 1)
                        for t in scene["textures"] if t.get("shown", True)}
            old, new = selected(previous), selected(current)
            old_view, new_view = rect(previous["view"]), rect(current["view"])
            def material_overlap(bounds, view):
                area = max(0, min(bounds[2], view[2]) - max(bounds[0], view[0])) * max(0, min(bounds[3], view[3]) - max(bounds[1], view[1]))
                return area / min((bounds[2] - bounds[0]) * (bounds[3] - bounds[1]), (view[2] - view[0]) * (view[3] - view[1])) > .05
            limit = current.get("metadata", {}).get("maxAlphaStep", .35)
            for key in sorted(old.keys() | new.keys()):
                # A disappeared/new texture is a fade defect only if its world rectangle was
                # materially inside both views. Ordinary viewport culling is not an anomaly.
                if key not in old or key not in new:
                    if not material_overlap(key[1], old_view) or not material_overlap(key[1], new_view):
                        continue
                delta = abs(old.get(key, 0) - new.get(key, 0))
                if delta > limit:
                    findings.append({"code": "abrupt-alpha-step", "severity": "error", "sequence": name,
                                     "before": previous["id"], "after": current["id"], "asset": key[0],
                                     "delta": round(delta, 6), "limit": limit,
                                     "disappeared": key not in new, "appeared": key not in old})
    return findings


def annotated(image, title, warning):
    result = Image.new("RGBA", (image.width, image.height + 48), (27, 25, 24, 255))
    result.alpha_composite(image, dest=(0, 48))
    draw = ImageDraw.Draw(result)
    draw.text((10, 7), title[:120], fill=(239, 222, 186, 255))
    draw.text((10, 27), warning[:150], fill=(255, 185, 160, 255))
    return result


def gallery(output, report, scenes):
    cards = []
    by_id = {row["id"]: row for row in report["scenes"]}
    for scene in scenes:
        key, label = scene["id"], str(scene.get("label", scene["id"]))
        entry = by_id[key]
        text = html.escape(json.dumps(entry, sort_keys=True, indent=2))
        comparison = ""
        if entry.get("comparison", {}).get("comparable"):
            comparison = f'<a href="{key}-difference.png">Difference image</a>'
        cards.append(f'<article><h2>{html.escape(label)}</h2><a href="{key}.png"><img loading="lazy" src="{key}.png" alt="{html.escape(label, quote=True)}"></a>'
                     f'<p><a href="{key}-layers.png">Layer debug overlay</a> {comparison}</p><details><summary>State / assertions</summary><pre>{text}</pre></details></article>')
    warning = html.escape(report["visualEvidence"])
    native = ('<p><a href="native-reference.png">Owner-provided native reference screenshot</a> — associated with the report; not captured by this tool.</p>'
              if report.get("nativeReference") else "")
    content = f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TwichUI Map Visual Test Lab</title><style>
body{{background:#211d19;color:#e8dfd0;font:16px system-ui;margin:24px}}h1,h2{{color:#cda65d}}p{{max-width:100ch}}
.warning{{background:#493326;padding:16px;border:1px solid #916448}}main{{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:20px}}
article{{padding:14px;background:#2e2720;border:1px solid #594033}}img{{max-width:100%;height:auto}}a{{color:#d6bd89}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}}
</style><h1>TwichUI Map Visual Test Lab</h1><p class="warning">{warning}</p>
<p>Production Lua selects layers and placements. This page composites their state. Missing assets remain explicit checkerboards. Pixel differences measure change, not artistic quality or native-client fidelity.</p>
<p><a href="report.json">Machine-readable findings and provenance</a> · <a href="render-state.json">Production render state</a></p>{native}<main>{''.join(cards)}</main></html>'''
    (output / "index.html").write_text(content, encoding="utf-8")


def run(args):
    output = args.output.resolve()
    protected = [REPO / name for name in ("!!!TwichUI", "TwichUI_Diagnostics", "TwichUI_Settings", "TwichUI_NavData")]
    if any(output == path.resolve() or output.is_relative_to(path.resolve()) for path in protected):
        raise LabError("gallery output cannot be inside an addon package")
    if args.probe_assets:
        print(json.dumps(probe(args.wow), indent=2, sort_keys=True))
        return 0
    started = time.perf_counter()
    lua = {"source": "explicit render-state JSON", "seconds": 0}
    request = None
    if args.diagnostic or args.diagnostic_piece:
        if args.diagnostic_piece:
            if not 1 <= len(args.diagnostic_piece) <= 64 or sum(path.stat().st_size for path in args.diagnostic_piece) > 8 * 1024 * 1024:
                raise LabError("diagnostic pieces exceed input byte limit")
            raw = join_pieces([path.read_text(encoding="utf-8") for path in args.diagnostic_piece])
            if len(raw.encode()) > 8 * 1024 * 1024:
                raise LabError("diagnostic exceeds input byte limit")
            data = json.loads(raw, parse_constant=lambda value: (_ for _ in ()).throw(LabError("non-finite diagnostic number")))
        else:
            data = load_json(args.diagnostic)
        request, state = import_report(data)
    elif args.state:
        state = load_json(args.state)
    else:
        state, lua = production_export()
    validate_export(state)
    output.mkdir(parents=True, exist_ok=True)
    if request:
        (output / "diagnostic-scenario.json").write_text(json.dumps(request, indent=2, sort_keys=True), encoding="utf-8")
    manifest = args.assets
    if args.wow:
        if state.get("provenance", {}).get("synthetic", True):
            raise LabError("Synthetic fixture texture IDs are not verified client file IDs. Use a captured diagnostic/state with real production IDs before local CASC extraction.")
        asset_output = output / "local-assets"
        result = extract(state, args.wow, asset_output, REPO)
        manifest = asset_output / "manifest.json"
        manifest.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    assets = Assets(manifest, REPO / "!!!TwichUI")
    provenance = state.get("provenance", {})
    report = {"schema": 1, "kind": "twichui-maplab-result", "sourceProvenance": provenance, "luaExport": lua,
              "nativeClientConfirmed": False, "scenes": [], "findings": transition_checks(state["scenes"])}
    for scene in state["scenes"]:
        picture, entry = composite_scene(scene, assets)
        debug, _ = composite_scene(scene, assets, debug=True)
        partial = bool(provenance.get("partial")) or bool(scene.get("metadata", {}).get("partial"))
        synthetic = provenance.get("synthetic", True) or scene.get("synthetic", False)
        warning = ("PLACEHOLDERS: map artwork unavailable" if entry["missingAssets"] else
                   "ACTUAL TEXTURES / SYNTHETIC GEOGRAPHY" if synthetic else
                   "PARTIAL OFFLINE SNAPSHOT / NOT NATIVE REPLAY" if partial else
                   "OFFLINE ARTWORK PREVIEW / NOT NATIVE VALIDATION")
        annotated(picture, str(scene.get("label", scene["id"])), warning).save(output / f'{scene["id"]}.png')
        annotated(debug, str(scene.get("label", scene["id"])), warning).save(output / f'{scene["id"]}-layers.png')
        if args.baseline:
            prior = args.baseline / f'{scene["id"]}.png'
            if prior.is_file():
                with Image.open(prior) as before:
                    comparison, difference = compare_images(before, annotated(picture, str(scene.get("label", scene["id"])), warning))
                entry["comparison"] = comparison
                if difference:
                    difference.save(output / f'{scene["id"]}-difference.png')
        report["scenes"].append(entry)
        report["findings"].extend(entry["findings"])
    report["assetsUsed"] = assets.used
    report["missingAssets"] = sorted(assets.missing)
    report["realArtworkVerified"] = not assets.missing and any(v["kind"] == "local-client-artwork" for v in assets.used.values())
    report["syntheticGeography"] = provenance.get("synthetic", True)
    report["visualEvidence"] = ("Actual map artwork is unavailable: this gallery validates production-selected geometry, compositing and TwichUI-owned masks using explicit placeholders. It does not establish geographic or in-game visual quality."
                                if assets.missing else "Local textures were hash-checked and composited offline. Synthetic or partial geometry remains labelled. Native-client visual acceptance is outstanding.")
    report["seconds"] = round(time.perf_counter() - started, 6)
    report["renderStateSha256"] = hashlib.sha256(json.dumps(state, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if args.native_screenshot:
        if args.native_screenshot.stat().st_size > 64 * 1024 * 1024:
            raise LabError("native screenshot exceeds 64 MiB")
        with Image.open(args.native_screenshot) as screenshot:
            if screenshot.width * screenshot.height > 16_777_216:
                raise LabError("native screenshot exceeds pixel budget")
            # Re-encode pixels only: do not propagate EXIF or private local filenames.
            screenshot.convert("RGBA").save(output / "native-reference.png")
        report["nativeReference"] = {"source": "owner-provided screenshot; not captured by this tool",
            "sha256": hashlib.sha256((output / "native-reference.png").read_bytes()).hexdigest(),
            "reportId": request.get("reportId") if request else False}
    (output / "render-state.json").write_text(json.dumps(state, indent=2, sort_keys=True), encoding="utf-8")
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    gallery(output, report, state["scenes"])
    print(f'{len(state["scenes"])} scenarios, {len(assets.missing)} missing assets, {report["seconds"]:.3f}s; real artwork verified: {report["realArtworkVerified"]}')
    print(f'Gallery: {output / "index.html"}')
    return 1 if args.strict and any(f.get("severity") == "error" for f in report["findings"]) else 0


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--all", action="store_true", help="export the complete bounded production-Lua scenario catalog")
    p.add_argument("--state", type=Path, help="existing production render-state JSON")
    p.add_argument("--assets", type=Path, help="local SHA-256 asset manifest")
    p.add_argument("--wow", type=Path, help="read-only local Forever game installation; extract referenced artwork")
    p.add_argument("--probe-assets", action="store_true")
    p.add_argument("--diagnostic", type=Path, help="Detailed Map Diagnostics schema 1 JSON")
    p.add_argument("--diagnostic-piece", action="append", type=Path, help="numbered report pieces, supplied in order")
    p.add_argument("--output", type=Path, default=REPO / "test-output/maplab")
    p.add_argument("--baseline", type=Path, help="earlier gallery for image-difference metrics")
    p.add_argument("--native-screenshot", type=Path, help="optional owner-provided native screenshot; no client control or injection")
    p.add_argument("--strict", action="store_true", help="nonzero exit for missing assets or failed visual-state assertions")
    return p


if __name__ == "__main__":
    try:
        raise SystemExit(run(parser().parse_args()))
    except (LabError, OSError, json.JSONDecodeError) as exc:
        print(f"maplab: {exc}", file=sys.stderr)
        raise SystemExit(2)
