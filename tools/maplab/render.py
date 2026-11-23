"""Offline texture compositor for production-selected map render state.

This module does no geographic/map-layer selection. It only draws exported
rectangles and their texture coordinates. Real artwork is optional and local;
missing files are visible placeholders, never silently substituted terrain.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
import struct
from typing import Any

from PIL import Image, ImageChops, ImageDraw

MAX_JSON = 8 * 1024 * 1024
MAX_SCENES = 96
MAX_TEXTURES = 2048
MAX_SCENE_PIXELS = 4_194_304
MAX_TOTAL_PIXELS = 96_000_000
MAX_DECODED_PIXELS = 32_000_000  # <=128 MB of retained RGBA sources, independent of destination budgets
DRAW_LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}


class LabError(ValueError):
    pass


def load_json(path: Path) -> Any:
    if path.stat().st_size > MAX_JSON:
        raise LabError("JSON input exceeds 8 MiB")
    def reject(value):
        raise LabError(f"non-finite JSON number: {value}")
    def object_fields(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise LabError("duplicate JSON object field")
            result[key] = value
        return result
    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=reject, object_pairs_hook=object_fields)
    except UnicodeError as error:
        raise LabError("JSON input is not valid UTF-8") from error


def finite(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise LabError(f"{label} must be a finite number")
    return float(value)


def rect(value, label="rectangle"):
    if isinstance(value, dict):
        value = [value.get(k) for k in ("u0", "v0", "u1", "v1")]
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        raise LabError(f"{label} needs u0,v0,u1,v1")
    out = tuple(finite(v, label) for v in value)
    if max(map(abs, out)) > 1e6 or out[2] <= out[0] or out[3] <= out[1]:
        raise LabError(f"{label} has no positive area")
    return out


def texture_rect(texture):
    return rect(texture.get("bounds", texture), "texture rectangle")


class Assets:
    """Hash-checked local cache, plus allowlisted TwichUI-owned map mask TGAs."""
    def __init__(self, manifest: Path | None = None, own_root: Path | None = None):
        self.root = manifest.resolve().parent if manifest else None
        self.records = {}
        self.loaded = {}
        self.used = {}
        self.missing = set()
        self.decoded_pixels = 0
        self.validation = None
        self.manifest = None
        self.own_root = own_root.resolve() if own_root else None
        if manifest:
            data = load_json(manifest)
            if not isinstance(data, dict) or type(data.get("schema")) is not int or data.get("schema") not in (1, 2) or not isinstance(data.get("assets"), dict):
                raise LabError("asset manifest requires supported schema 1/2 and an assets object")
            collector_cache = (data.get("clientBuild") and data["assets"] and all(
                isinstance(key, str) and key.isdecimal() and isinstance(record, dict)
                and record.get("file") == key + ".blp" for key, record in data["assets"].items()))
            if data["schema"] == 2 or collector_cache:
                from bundle import validate_manifest
                self.validation = validate_manifest(data, self.root)
                if self.validation["status"] == "failure":
                    raise LabError("Asset bundle validation failed: " + "; ".join(self.validation["errors"][:6]))
            self.manifest = data
            self.records = data["assets"]

    def _own(self, key):
        if not self.own_root or not isinstance(key, str):
            return None
        relative = key.replace("\\", "/")
        prefix = "Interface/AddOns/!!!TwichUI/"
        if relative.startswith(prefix):
            relative = relative[len(prefix):]
        if relative.startswith("!!!TwichUI/"):
            relative = relative[len("!!!TwichUI/"):]
        if relative.startswith("own:"):
            relative = relative[4:]
        if not re.fullmatch(r"media/textures/map-[A-Za-z0-9_-]+(?:\.(?:tga|png))?", relative):
            return None
        candidate = self.own_root / relative
        if not candidate.suffix:
            candidate = candidate.with_suffix(".tga")
        candidate = candidate.resolve()
        if not candidate.is_relative_to(self.own_root) or not candidate.is_file():
            return None
        return candidate

    def get(self, key):
        key = str(key)
        if key in self.loaded:
            return self.loaded[key]
        own = self._own(key)
        record = self.records.get(key)
        if own:
            path = own
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            provenance = "TwichUI-owned map mask from repository; no Blizzard terrain artwork"
            kind = "twichui-mask"
        elif record:
            if not isinstance(record, dict) or not isinstance(record.get("file"), str):
                raise LabError(f"invalid asset record {key}")
            path = (self.root / record["file"]).resolve()
            if not path.is_relative_to(self.root) or not path.is_file():
                raise LabError(f"asset path escapes cache or is absent: {key}")
            if path.stat().st_size > 64 * 1024 * 1024:
                raise LabError(f"asset {key} exceeds source byte limit")
            digest = record.get("sha256", "")
            if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
                raise LabError(f"asset {key} needs SHA-256 provenance")
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise LabError(f"asset hash mismatch: {key}")
            provenance = record.get("provenance")
            if not isinstance(provenance, str) or not provenance.strip():
                raise LabError(f"asset {key} has no provenance")
            kind = record.get("kind", "local-client-artwork")
            if kind == "local-client-artwork" and str(record.get("fileId")) != key:
                raise LabError(f"client asset {key} requires a matching fileId provenance record")
        else:
            self.missing.add(key)
            return None
        try:
            with Image.open(path) as raw:
                if raw.width * raw.height > 16_777_216:
                    raise LabError(f"asset {key} exceeds decode size limit")
                if record and self.manifest and self.manifest["schema"] == 2:
                    header = record["header"]
                    if (raw.width, raw.height) != (header["width"], header["height"]):
                        raise LabError(f"asset {key} decoded dimensions differ from declared source")
                pixels = raw.width * raw.height
                if self.decoded_pixels + pixels > MAX_DECODED_PIXELS:
                    raise LabError("cumulative decoded source pixel budget exceeded; split the gallery or use smaller sources")
                picture = raw.convert("RGBA")
        except (OSError, ValueError, RuntimeError, struct.error, Image.DecompressionBombError) as error:
            raise LabError(f"asset {key} could not be decoded: {error}") from error
        self.decoded_pixels += pixels
        self.loaded[key] = picture
        self.used[key] = {"sha256": digest, "provenance": provenance[:512], "kind": kind,
                          "width": picture.width, "height": picture.height}
        return picture

    def release_sources(self):
        """Retain provenance, release decoded input pixels between scenarios."""
        self.loaded.clear()
        self.decoded_pixels = 0


def placeholder(key):
    image = Image.new("RGBA", (128, 128), (83, 43, 90, 255))
    draw = ImageDraw.Draw(image)
    for x in (0, 64):
        for y in (0, 64):
            if (x + y) % 128 == 0:
                draw.rectangle((x, y, x + 63, y + 63), fill=(137, 83, 128, 255))
    draw.line((0, 0, 127, 127), fill=(240, 204, 225, 255), width=2)
    draw.line((127, 0, 0, 127), fill=(240, 204, 225, 255), width=2)
    draw.text((5, 55), str(key)[:18], fill=(255, 255, 255, 255))
    return image


def _uv(value):
    if value is None:
        return 0., 1., 0., 1.
    if not isinstance(value, list) or len(value) != 4:
        raise LabError("texCoord requires four numeric crop coordinates")
    uv = tuple(finite(v, "texture coordinate") for v in value)
    if max(map(abs, uv)) > 32:
        raise LabError("texture coordinates exceed supported clamp range")
    return uv


def _sampling_geometry(bounds, view, size, rotation):
    w, h = size
    l, t, r, b = view
    x0, y0 = (bounds[0] - l) / (r - l) * w, (bounds[1] - t) / (b - t) * h
    rw, rh = (bounds[2] - bounds[0]) / (r - l) * w, (bounds[3] - bounds[1]) / (b - t) * h
    cx, cy = x0 + rw / 2, y0 + rh / 2
    cosine, sine = math.cos(rotation), math.sin(rotation)
    corners = [(cx + dx * rw * cosine + dy * rh * sine,
                cy - dx * rw * sine + dy * rh * cosine)
               for dx, dy in ((-.5, -.5), (.5, -.5), (.5, .5), (-.5, .5))]
    box = (max(0, math.floor(min(x for x, y in corners))),
           max(0, math.floor(min(y for x, y in corners))),
           min(w, math.ceil(max(x for x, y in corners))),
           min(h, math.ceil(max(y for x, y in corners))))
    return rw, rh, cx, cy, cosine, sine, corners, box


def _sample(image, bounds, view, size, rotation=0, uv=None, box=None, filtering="linear", geometry=None):
    """Affine inverse sampling with transparent CLAMPTOBLACKADDITIVE semantics.

    Positive radians turn counter-clockwise on screen, matching the pinned
    OpenMap offline picture compositor. This convention still needs a native
    Texture:SetRotation comparison; it is not native visual certification.
    """
    rw, rh, cx, cy, cosine, sine, corners, natural_box = geometry or _sampling_geometry(bounds, view, size, rotation)
    if box is None: box = natural_box
    if box[2] <= box[0] or box[3] <= box[1]:
        return None, box
    u0, u1, v0, v1 = _uv(uv)
    du, dv = u1 - u0, v1 - v0
    a, bb = image.width * du * cosine / rw, -image.width * du * sine / rw
    d, e = image.height * dv * sine / rh, image.height * dv * cosine / rh
    c = image.width * (u0 + du * (.5 + (-cosine * cx + sine * cy) / rw))
    f = image.height * (v0 + dv * (.5 + (-sine * cx - cosine * cy) / rh))
    coefficients = (a, bb, c + a * box[0] + bb * box[1], d, e, f + d * box[0] + e * box[1])
    resample = Image.Resampling.NEAREST if filtering == "nearest" else Image.Resampling.BILINEAR
    tile = image.transform((box[2] - box[0], box[3] - box[1]), Image.Transform.AFFINE,
                           coefficients, resample=resample, fillcolor=(0, 0, 0, 0))
    clip = Image.new("L", tile.size)
    ImageDraw.Draw(clip).polygon([(x - box[0], y - box[1]) for x, y in corners], fill=255)
    tile.putalpha(ImageChops.multiply(tile.getchannel("A"), clip))
    return tile, box


def validate_export(data):
    if not isinstance(data, dict) or data.get("schema") != 1 or not isinstance(data.get("scenes"), list):
        raise LabError("render export requires schema 1 and scenes array")
    if not 1 <= len(data["scenes"]) <= MAX_SCENES:
        raise LabError("render export scene count is outside bounds")
    total = 0
    seen = set()
    for scene in data["scenes"]:
        key = scene.get("id")
        if not isinstance(key, str) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]{0,79}", key) or key in seen:
            raise LabError("scene IDs must be unique safe filenames")
        seen.add(key)
        width, height = scene.get("width", 800), scene.get("height", 534)
        if isinstance(width, bool) or isinstance(height, bool) or not isinstance(width, int) or not isinstance(height, int):
            raise LabError("integer viewport dimensions required")
        if width < 16 or height < 16 or width * height > MAX_SCENE_PIXELS:
            raise LabError("viewport pixel budget exceeded")
        total += width * height
        rect(scene.get("view"), "view")
        textures = scene.get("textures")
        if not isinstance(textures, list) or len(textures) > MAX_TEXTURES:
            raise LabError("texture count exceeds supported budget")
        for tex in textures:
            texture_rect(tex)
            alpha = finite(tex.get("alpha", 1), "alpha")
            if not 0 <= alpha <= 1:
                raise LabError("alpha outside 0..1")
            finite(tex.get("rotation", 0), "rotation")
            finite(tex.get("level", 0), "level")
            _uv(tex.get("texCoord"))
            masks = tex.get("masks", [])
            if not isinstance(masks, list) or len(masks) > 8:
                raise LabError("at most eight masks per texture are supported")
            if tex.get("mask"):
                masks = masks + [tex["mask"]]
            for mask in masks:
                if not isinstance(mask, dict):
                    raise LabError("mask must be an object")
                _uv(mask.get("texCoord"))
                if "bounds" in mask:
                    rect(mask["bounds"], "mask rectangle")
                elif all(k in mask for k in ("u0", "v0", "u1", "v1")):
                    rect(mask, "mask rectangle")
    if total > MAX_TOTAL_PIXELS:
        raise LabError("whole gallery pixel budget exceeded")
    return data


def composite_scene(scene, assets, debug=False):
    size = (scene.get("width", 800), scene.get("height", 534))
    view = rect(scene["view"])
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    missing, visible = set(), 0
    ordered = sorted(enumerate(scene["textures"]), key=lambda pair: (pair[1].get("level", 0),
        DRAW_LAYERS.get(pair[1].get("drawLayer", "ARTWORK"), 2),
        pair[1].get("sublevel", pair[1].get("sublayer", 0)), pair[1].get("order", pair[0])))
    for index, texture in ordered:
        if not texture.get("shown", True) or texture.get("alpha", 1) <= 0:
            continue
        bounds = texture_rect(texture)
        rotation = finite(texture.get("rotation", 0), "rotation")
        geometry = _sampling_geometry(bounds, view, size, rotation)
        visible_box = geometry[-1]
        if visible_box[2] <= visible_box[0] or visible_box[3] <= visible_box[1]:
            continue  # cull before decoding or counting missing pixels outside the viewport
        key = texture.get("fileId", texture.get("asset"))
        if "color" in texture:
            c = texture["color"]
            if not isinstance(c, list) or len(c) not in (3, 4):
                raise LabError("color needs RGB or RGBA components")
            values = [max(0, min(255, round(finite(v, "color") * 255))) for v in c]
            source = Image.new("RGBA", (2, 2), tuple(values + [255] if len(values) == 3 else values))
        else:
            source = assets.get(key)
            if source is None:
                missing.add(str(key)); source = placeholder(key)
        tile, box = _sample(source, bounds, view, size, rotation,
                            texture.get("texCoord"), filtering=texture.get("filtering", texture.get("filter", "linear")), geometry=geometry)
        if tile is None:
            continue
        visible += 1
        tint = texture.get("vertexColor", texture.get("tint", [1, 1, 1]))
        if isinstance(tint, list) and len(tint) >= 3:
            channels = list(tile.split())
            for i in range(3):
                factor = max(0, min(1, finite(tint[i], "tint")))
                channels[i] = channels[i].point(lambda v, factor=factor: round(v * factor))
            tile = Image.merge("RGBA", channels)
        alpha = tile.getchannel("A").point(lambda v: round(v * texture.get("alpha", 1)))
        masks = texture.get("masks", [])
        if texture.get("mask"):
            masks = masks + [texture["mask"]]
        for mask in masks:
            mkey = mask.get("asset", mask.get("fileId"))
            mask_image = assets.get(mkey)
            if mask_image is None:
                missing.add(str(mkey))
                continue  # explicitly unmasked placeholder; error is recorded, never a passing visual result
            mask_bounds = mask.get("bounds", mask if all(k in mask for k in ("u0", "v0", "u1", "v1")) else bounds)
            sampled, _ = _sample(mask_image, rect(mask_bounds), view, size,
                                  finite(mask.get("rotation", 0), "mask rotation"), mask.get("texCoord"), box=box)
            alpha = ImageChops.multiply(alpha, sampled.getchannel("A"))
        tile.putalpha(alpha)
        image.alpha_composite(tile, dest=(box[0], box[1]))
        if debug:
            draw = ImageDraw.Draw(image)
            draw.rectangle(box, outline=(255, 215, 60, 210), width=1)
            draw.text((max(0, box[0] + 2), max(0, box[1] + 2)), str(key)[:28], fill=(255, 255, 255, 255))
    histogram = image.getchannel("A").histogram()
    transparent = histogram[0] / (size[0] * size[1])
    findings = [{"code": "missing-texture", "severity": "error", "asset": key} for key in sorted(missing)]
    expected = scene.get("assertions", {})
    if transparent > expected.get("maxTransparentFraction", 1):
        findings.append({"code": "unexpected-transparency", "severity": "error", "fraction": round(transparent, 6)})
    minimum = expected.get("minimumVisibleTextures", 0)
    if visible < minimum:
        findings.append({"code": "visible-texture-count", "severity": "error", "actual": visible, "minimum": minimum})
    return image, {"id": scene["id"], "visibleTextures": visible, "missingAssets": sorted(missing),
                   "transparentFraction": round(transparent, 6), "findings": findings}


def compare_images(before, after):
    if before.size != after.size:
        return {"comparable": False, "reason": "different viewport dimensions"}, None
    difference = ImageChops.difference(before.convert("RGBA"), after.convert("RGBA"))
    channels = difference.split()
    changed = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), ImageChops.lighter(channels[2], channels[3]))
    hist = changed.histogram()
    pixels = before.width * before.height
    # Alpha differences still contribute to the metrics below. The displayed
    # difference must be opaque even when only RGB changed between opaque views.
    difference.putalpha(255)
    return {"comparable": True, "changedPixels": pixels - hist[0],
            "changedFraction": round((pixels - hist[0]) / pixels, 6),
            "meanChannelDifference": round(sum(i * n for c in channels for i, n in enumerate(c.histogram())) / (pixels * 4), 6)}, difference
