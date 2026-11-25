"""Small deterministic build-time helpers; never enabled as runtime map assets.

Only source alpha is preserved automatically. A geographic territory/city/ocean
mask needs reviewed artwork and alignment evidence; thresholding arbitrary RGB
pixels is deliberately not called a geographic mask here.
"""
from __future__ import annotations

import hashlib
import argparse
import json
from pathlib import Path
import time
from PIL import Image, ImageFilter


def alpha_mask(image: Image.Image, feather_pixels=0):
    if not isinstance(feather_pixels, (int, float)) or not 0 <= feather_pixels <= 64:
        raise ValueError("feather radius outside 0..64")
    alpha = image.convert("RGBA").getchannel("A")
    return alpha.filter(ImageFilter.GaussianBlur(feather_pixels)) if feather_pixels else alpha


def lod(image: Image.Image, side: int):
    if isinstance(side, bool) or not isinstance(side, int) or not 8 <= side <= 2048:
        raise ValueError("LOD side outside 8..2048")
    return image.convert("RGBA").resize((side, side), Image.Resampling.LANCZOS)


def gutter(image: Image.Image, pixels=1):
    if not isinstance(pixels, int) or not 1 <= pixels <= 8:
        raise ValueError("gutter outside 1..8")
    source = image.convert("RGBA")
    out = Image.new("RGBA", (source.width + 2 * pixels, source.height + 2 * pixels))
    out.paste(source, (pixels, pixels))
    out.paste(source.crop((0, 0, 1, source.height)).resize((pixels, source.height), Image.Resampling.NEAREST), (0, pixels))
    out.paste(source.crop((source.width - 1, 0, source.width, source.height)).resize((pixels, source.height), Image.Resampling.NEAREST), (pixels + source.width, pixels))
    out.paste(out.crop((0, pixels, out.width, pixels + 1)).resize((out.width, pixels), Image.Resampling.NEAREST), (0, 0))
    out.paste(out.crop((0, source.height + pixels - 1, out.width, source.height + pixels)).resize((out.width, pixels), Image.Resampling.NEAREST), (0, source.height + pixels))
    return out


def identity(image):
    return {"width": image.width, "height": image.height,
            "pixelSha256": hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()}


def own_fixture():
    """Mathematical colour/alpha fixture, not WoW terrain or geographic evidence."""
    from PIL import ImageDraw
    image = Image.new("RGBA", (256, 256))
    pixels = image.load()
    for y in range(256):
        for x in range(256):
            pixels[x, y] = (80 + (x * 17 + y * 3) % 61, 70 + (x * 3 + y * 11) % 71,
                            35 + (x * 7 + y * 5) % 51, 255 if (x - 128) ** 2 + (y - 128) ** 2 < 120 ** 2 else 0)
    draw = ImageDraw.Draw(image)
    draw.line([(20, 170), (70, 170), (110, 90), (190, 90), (235, 20)], fill=(220, 190, 130, 255), width=3)
    return image


def measure(source, output, provenance):
    output.mkdir(parents=True, exist_ok=True)
    report = {"schema": 1, "kind": "maplab-build-time-prototype", "provenance": provenance,
              "runtimeEnabled": False, "measurements": [],
              "limitations": ["No geographic land/territory/city/ocean classification is inferred from arbitrary RGB pixels.",
                  "Uncompressed RGBA bytes are a pixel-count estimate, not measured client GPU memory.",
                  "Real terrain fidelity and redistribution rights require current licensed local source artwork."]}
    products = [("native", lambda: source.convert("RGBA")),
                ("lod64", lambda: lod(source, 64)), ("lod16", lambda: lod(source, 16)),
                ("source-alpha", lambda: alpha_mask(source)),
                ("feathered-alpha", lambda: alpha_mask(source, 2)),
                ("gutter64", lambda: gutter(lod(source, 64), 1))]
    for name, build in products:
        start = time.perf_counter()
        image = build()
        if image.mode == "L":
            # A mask's information belongs in alpha, not opaque grayscale RGB.
            mask = Image.new("RGBA", image.size, (255, 255, 255, 255))
            mask.putalpha(image)
            image = mask
        elapsed = time.perf_counter() - start
        target = output / f"{name}.png"
        image.save(target)
        report["measurements"].append({"stage": name, **identity(image), "pngBytes": target.stat().st_size,
            "uncompressedRgbaBytes": image.width * image.height * 4, "processingSeconds": round(elapsed, 7)})
    (output / "preprocess-report.json").write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="optional local artwork; outputs remain private local previews")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    target = args.output.resolve()
    if any(target == (repo / name).resolve() or target.is_relative_to((repo / name).resolve()) for name in ("!!!TwichUI", "TwichUI_Diagnostics", "TwichUI_Settings")):
        parser.error("preprocessing output cannot be inside an addon package")
    if args.source:
        with Image.open(args.source) as raw:
            if raw.width * raw.height > 16_777_216:
                parser.error("source artwork exceeds pixel limit")
            source = raw.convert("RGBA")
        provenance = "Explicit local source; no redistribution permission inferred"
    else:
        source, provenance = own_fixture(), "TwichUI mathematical colour/alpha fixture; synthetic, not geography"
    result = measure(source, target, provenance)
    print(json.dumps(result, indent=2, sort_keys=True))
