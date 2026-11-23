#!/usr/bin/env python3
"""Private source-image study: native zone bases through overlay-alpha support.

Example: python3 tools/maplab/underpaint.py --client-input /private/client.json \
  --assets /private/assets/manifest.json --map 1429 --map 1436 \
  --output test-output/maplab-underpaint

This is not geographic selection, a semantic territory classifier, an addon
asset generator or a parent-label repair. It copies no OpenMap code/art. Source
RGB/geometry are preserved; extending alpha can expose native neighbor labels.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import time

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from bundle import validate_manifest
from clientinput import write_tables
from render import Assets, LabError, composite_scene, finite, load_json, texture_rect, validate_export

REPO = Path(__file__).resolve().parents[2]
LIMITATIONS = [
    "Private source-image comparison, not production-Lua geographic composition or native-client reproduction.",
    "Overlay alpha is artwork support, not authoritative land, territory, city, ocean or name geometry.",
    "Expanded support can expose neighbor lettering/decorative pixels; visual review is mandatory.",
    "No inpainting, source RGB modification, parent suppression, runtime activation or redistribution permission.",
]


def support_mask(alpha, grow=40, soft=14, frame=24):
    """Bounded approximate dilation; original overlay alpha is not modified."""
    if alpha.mode != "L" or not 1 <= alpha.width <= 8192 or not 1 <= alpha.height <= 8192:
        raise LabError("support mask needs bounded grayscale source alpha")
    if any(isinstance(n, bool) or not isinstance(n, int) or n < 0 or n > 96 for n in (grow, soft, frame)):
        raise LabError("grow, soft and frame must be integers in 0..96 source pixels")
    mask = alpha.copy()
    if grow:
        scale = max(1, math.ceil(max(alpha.size) / 256))
        small = alpha.resize((max(1, math.ceil(alpha.width / scale)), max(1, math.ceil(alpha.height / scale))), Image.Resampling.BOX)
        radius = math.ceil(grow / scale)
        small = small.filter(ImageFilter.MaxFilter(radius * 2 + 1))
        mask = small.resize(alpha.size, Image.Resampling.BILINEAR)
    if soft:
        mask = mask.filter(ImageFilter.GaussianBlur(soft))
    mask = ImageChops.lighter(mask, alpha)
    if frame:
        # Only the underpaint is clipped; native overlay pixels remain untouched.
        w, h = alpha.size
        x = Image.new("L", (w, 1)); x.putdata([round(255 * min(1, max(0, min(i, w - 1 - i) - frame) / frame)) for i in range(w)])
        y = Image.new("L", (1, h)); y.putdata([round(255 * min(1, max(0, min(i, h - 1 - i) - frame) / frame)) for i in range(h)])
        edge = ImageChops.darker(x.resize((w, h)), y.resize((w, h)))
        mask = ImageChops.multiply(mask, edge)
    return mask


def composite(base, overlay, grow=40, soft=14, frame=24):
    if base.mode != "RGBA" or overlay.mode != "RGBA" or base.size != overlay.size:
        raise LabError("matching RGBA base and overlay required")
    mask = support_mask(overlay.getchannel("A"), grow, soft, frame)
    under = base.copy()
    under.putalpha(ImageChops.multiply(base.getchannel("A"), mask))
    return Image.alpha_composite(under, overlay), mask


def assemble(data, mid, assets):
    """Assemble one native art canvas, not a world-space map renderer."""
    m = next((m for m in data["maps"] if m["id"] == mid), None)
    if not m or m["type"] != 3:
        raise LabError("study requires a declared zone map")
    w, h, tw, th = m["layer"]
    if w * h > 4_194_304:
        raise LabError("source canvas exceeds study pixel limit")
    base, overlay = Image.new("RGBA", (w, h)), Image.new("RGBA", (w, h))
    sources = set()
    def tile(fid):
        picture = assets.get(str(fid))
        if picture is None:
            raise LabError(f"required source texture {fid} unavailable; no complete study produced")
        if assets.used[str(fid)]["kind"] != "local-client-artwork":
            raise LabError("actual client artwork required")
        sources.add(fid)
        return picture
    cols = math.ceil(w / tw)
    for i, fid in enumerate(m["files"]):
        x, y = i % cols * tw, i // cols * th
        base.alpha_composite(tile(fid).crop((0, 0, min(tw, w - x), min(th, h - y))), (x, y))
    pieces = data["reveal"].get(str(m["art"]), [])
    if not pieces:
        raise LabError("zone has no declared native overlay support")
    for pw, ph, x, y, files in pieces:
        cols = math.ceil(pw / tw)
        for i, fid in enumerate(files):
            dx, dy = i % cols * tw, i // cols * th
            overlay.alpha_composite(tile(fid).crop((0, 0, min(tw, pw - dx), min(th, ph - dy))), (x + dx, y + dy))
    return base, overlay, sorted(sources)


def comparison(before, after, left="Native overlays only", right="PRIVATE alpha-support underpaint study"):
    w, h = before.size
    sheet = Image.new("RGB", (w * 2, h + 28), (34, 29, 24))
    draw = ImageDraw.Draw(sheet)
    for x, title, image in ((0, left, before), (w, right, after)):
        back = Image.new("RGBA", image.size, (100, 95, 85, 255))
        back.alpha_composite(image)
        sheet.paste(back.convert("RGB"), (x, 28))
        draw.text((x + 8, 8), title, fill=(240, 230, 210))
    return sheet


def selected_underpaints(scene, images):
    """Use only Lua-exported candidates; Python never chooses a geographic zone."""
    level = next((f["level"] for f in scene.get("metadata", {}).get("art", {}).get("layers", []) if f["kind"] == "zone"), None)
    if level is None:
        raise LabError("state lacks production zone-layer evidence")
    result, seen = [], set()
    candidates = scene.get("metadata", {}).get("baseCandidates", [])
    if not isinstance(candidates, list) or len(candidates) > 64:
        raise LabError("production base candidates exceed study limits")
    for candidate in candidates:
        if not isinstance(candidate, dict): raise LabError("invalid production base candidate")
        mid, tiles = candidate.get("mapId"), candidate.get("textures")
        if not isinstance(mid, int) or isinstance(mid, bool) or mid in seen:
            raise LabError("invalid or duplicate production candidate map ID")
        seen.add(mid)
        if mid not in images: continue
        if not isinstance(tiles, list) or not 1 <= len(tiles) <= 256:
            raise LabError("invalid production base candidate tile count")
        for tile in tiles: texture_rect(tile)
        alpha = finite(candidate.get("alpha"), "candidate alpha")
        if not 0 <= alpha <= 1: raise LabError("candidate alpha outside 0..1")
        result.append(dict(asset="underpaint:" + str(mid),
            u0=min(t["u0"] for t in tiles), u1=max(t["u1"] for t in tiles),
            v0=min(t["v0"] for t in tiles), v1=max(t["v1"] for t in tiles),
            alpha=alpha, level=level, drawLayer="ARTWORK", sublayer=-8,
            texCoord=[0, 1, 0, 1], masks=[], order=len(result)))
    return result


def run(client, manifest, maps, output, grow=40, soft=14, frame=24, state=None, scenes=()):
    started = time.perf_counter()
    if not maps or len(maps) > 8 or len(set(maps)) != len(maps):
        raise LabError("provide one to eight distinct zone map IDs")
    data, source_manifest = load_json(client), load_json(manifest)
    write_tables(data)
    validation = validate_manifest(source_manifest, manifest.parent, data)
    if validation["status"] == "failure":
        raise LabError("source bundle failed validation: " + "; ".join(validation["errors"][:3]))
    output = output.resolve()
    protected = [p.resolve() for p in REPO.iterdir() if p.is_dir() and any(p.glob("*.toc"))]
    if output == REPO or any(output == p or output.is_relative_to(p) for p in protected):
        raise LabError("private underpaint output cannot be inside an addon package")
    # Do not overwrite a baseline, imported cache or partially completed study.
    output.mkdir(parents=True, exist_ok=False)
    assets = Assets(manifest, REPO / "!!!TwichUI")
    report = dict(schema=1, kind="twichui-maplab-underpaint-study", runtimeEnabled=False,
        tool=dict(name="twichui-maplab-underpaint-study", version="1.0.0", sourceSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()),
        nativeClientConfirmed=False, semanticMasksVerified=False,
        clientBuild=data["clientBuild"], product=data.get("product", "unknown"),
        clientMetadataSha256=hashlib.sha256(client.read_bytes()).hexdigest(),
        manifestSha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),
        settings=dict(growSourcePixels=grow, softenSourcePixels=soft, frameSourcePixels=frame),
        sourceValidation=validation, limitations=LIMITATIONS, maps=[])
    images = {}
    for mid in maps:
        base, overlay, sources = assemble(data, mid, assets)
        after, mask = composite(base, overlay, grow, soft, frame)
        under = base.copy(); under.putalpha(ImageChops.multiply(base.getchannel("A"), mask))
        images[mid] = under
        comparison(overlay, after).save(output / f"{mid}-comparison.png")
        after.save(output / f"{mid}-candidate.png")
        mask.save(output / f"{mid}-support.png")
        histogram = ImageChops.subtract(after.getchannel("A"), overlay.getchannel("A")).histogram()
        report["maps"].append(dict(mapId=mid, dimensions=list(base.size), sourceIds=sources,
            addedSupportPixels=sum(histogram[1:]), changedFraction=round(sum(histogram[1:]) / (base.width * base.height), 6),
            rgbaPixelSha256=hashlib.sha256(after.tobytes()).hexdigest(),
            candidatePngBytes=(output / f"{mid}-candidate.png").stat().st_size,
            approval="unreviewed; source-aware alpha extension is not semantic territory"))
        assets.release_sources()
    if state:
        exported = load_json(state); validate_export(exported)
        if exported.get("provenance", {}).get("clientBuild") != data["clientBuild"]:
            raise LabError("production state and source client builds differ")
        if not scenes or len(scenes) > 8 or len(set(scenes)) != len(scenes):
            raise LabError("state comparison needs one to eight distinct --scene IDs")
        selected = [s for s in exported["scenes"] if s["id"] in scenes]
        if len(selected) != len(scenes): raise LabError("selected production scene absent")
        report["productionStateSha256"] = hashlib.sha256(state.read_bytes()).hexdigest()
        report["scenes"] = []
        for scene in selected:
            assets.release_sources()
            before, original = composite_scene(scene, assets)
            if original["missingAssets"]:
                raise LabError("production scene needs unavailable native artwork; no complete comparison claim")
            extra = selected_underpaints(scene, images)
            if not extra: raise LabError("selected scene contains none of the requested Lua-selected zones")
            # Generated images are private trusted study inputs, not imported art.
            for mid, image in images.items(): assets.loaded["underpaint:" + str(mid)] = image
            candidate = dict(scene, textures=scene["textures"] + extra)
            after, result = composite_scene(candidate, assets)
            comparison(before, after, left="Production Lua baseline").save(output / (scene["id"] + "-production-comparison.png"))
            delta = ImageChops.difference(before, after)
            diffmask = delta.getchannel("R")
            for channel in ("G", "B", "A"): diffmask = ImageChops.lighter(diffmask, delta.getchannel(channel))
            changed = sum(diffmask.histogram()[1:])
            report["scenes"].append(dict(id=scene["id"], addedUnderpaintLayers=len(extra),
                changedPixels=changed, changedFraction=round(changed / (before.width * before.height), 6),
                placementSource="Unmodified production Lua metadata.baseCandidates; native RGB and world bounds preserved",
                status="experimental; not artistic or native acceptance"))
    report["sources"] = assets.used
    report["seconds"] = round(time.perf_counter() - started, 6)
    (output / "report.json").write_text(json.dumps(report, sort_keys=True, indent=2), encoding="utf-8")
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--client-input", type=Path, required=True)
    p.add_argument("--assets", type=Path, required=True)
    p.add_argument("--map", dest="maps", type=int, action="append", required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--grow", type=int, default=40)
    p.add_argument("--soft", type=int, default=14)
    p.add_argument("--frame", type=int, default=24)
    p.add_argument("--state", type=Path, help="production export with inactive native baseCandidates")
    p.add_argument("--scene", action="append", default=[], help="production scene ID to compare; repeat up to eight")
    a = p.parse_args()
    try:
        result = run(a.client_input, a.assets, a.maps, a.output, a.grow, a.soft, a.frame, a.state, a.scene)
        print(f"Private underpaint study: {len(result['maps'])} zones, {result['seconds']:.3f}s; runtime disabled; semantic masks unverified")
        print(a.output.resolve() / "report.json")
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("underpaint study: " + str(error))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
