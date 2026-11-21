#!/usr/bin/env python3
"""Draws offline captures of TwichUI Fishing's Fishing Mode over synthetic bright, dark and sunset backdrops.

The layout is the addon's own: tests/fishing_capture.lua runs TwichUI_Fishing in the simulated client (tests/fishing_mock.lua,
tests/ui_widgets.lua), plays a scripted session through Stage 1's key and records every visible texture and font string with
its resolved place on a 1366 x 768 screen. This script draws that record with the real textures (TwichUI_Fishing/media/*.tga)
and fonts (!!!TwichUI/media/fonts), at 2x.

What it is not: the game's renderer. Text metrics, filtering, blending and the world behind the interface differ in the client,
the backdrops are painted gradients, and the item icons are stand-ins (assets/fishing/standins: the texture pack's illustrative
collection art) because the game's own icons are not available outside it. Treat a capture as a layout and legibility review
("screenshot-reviewed", offline), never as real-client evidence.

    python3 tools/render_fishing_hud.py [--out test-output/fishing-captures] [--scenes immersive,compact,castbar]
                                        [--backdrops bright,dark,sunset] [--scale 2] [--compare mockup.png]

Needs lua5.1 (with the bit library, as tests/run.sh does) and Pillow.
"""
import argparse
import json
import math
import os
import random
import re
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STANDINS = os.path.join(ROOT, "assets", "fishing", "standins")
ADDONS = {"TwichUI_Fishing": os.path.join(ROOT, "TwichUI_Fishing"), "!!!TwichUI": os.path.join(ROOT, "!!!TwichUI")}
W, H = 1366, 768


def capture(scene, path):
    tests = os.path.join(ROOT, "tests")
    cmd = ["lua5.1", "-e", 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"', "fishing_capture.lua", path, scene]
    res = subprocess.run(cmd, cwd=tests, capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write(res.stdout + res.stderr)
        raise SystemExit("capture failed for %s" % scene)
    with open(path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------------------------------------------------------
# Backdrops (painted, not the game)
# ---------------------------------------------------------------------------------------------------------------------------
def gradient(img, stops, top, bottom):
    d = ImageDraw.Draw(img)
    for y in range(top, bottom):
        t = (y - top) / max(1, bottom - top - 1)
        for i in range(len(stops) - 1):
            a, b = stops[i], stops[i + 1]
            if a[0] <= t <= b[0]:
                u = (t - a[0]) / max(1e-6, b[0] - a[0])
                c = tuple(int(a[1][k] + (b[1][k] - a[1][k]) * u) for k in range(3))
                d.line([(0, y), (img.width, y)], fill=c)
                break


def backdrop(kind, scale):
    w, h = W * scale, H * scale
    img = Image.new("RGB", (w, h))
    rnd = random.Random(7)
    horizon = int(h * 0.46)
    if kind == "bright":
        gradient(img, [(0, (196, 218, 238)), (1, (246, 248, 250))], 0, horizon)
        gradient(img, [(0, (232, 236, 238)), (0.25, (205, 220, 228)), (1, (226, 234, 238))], horizon, h)
        d = ImageDraw.Draw(img)
        for _ in range(1600):      # sun glitter and snow
            x, y = rnd.randrange(w), rnd.randrange(horizon, h)
            r = rnd.choice((1, 2, 2, 3)) * scale
            d.ellipse([x, y, x + r * 3, y + r], fill=(255, 255, 255))
        d.polygon([(0, horizon), (w * 0.32, horizon - h * 0.16), (w * 0.55, horizon)], fill=(238, 242, 246))
        d.polygon([(w * 0.6, horizon), (w * 0.86, horizon - h * 0.2), (w, horizon - h * 0.08), (w, horizon)], fill=(232, 238, 244))
    elif kind == "dark":
        gradient(img, [(0, (6, 9, 20)), (1, (22, 30, 52))], 0, horizon)
        gradient(img, [(0, (12, 18, 32)), (1, (4, 6, 12))], horizon, h)
        d = ImageDraw.Draw(img)
        for _ in range(260):
            x, y = rnd.randrange(w), rnd.randrange(horizon)
            d.point((x, y), fill=(200, 210, 230))
        d.ellipse([w * 0.7, h * 0.1, w * 0.7 + 60 * scale, h * 0.1 + 60 * scale], fill=(226, 230, 214))
        for i in range(140):       # the moon's path on the water
            y = horizon + i * (h - horizon) / 140
            half = (8 + i * 0.6) * scale
            x = w * 0.7 + 30 * scale + rnd.uniform(-6, 6) * scale
            d.line([(x - half, y), (x + half, y)], fill=(70, 76, 82), width=max(1, scale))
        d.polygon([(0, horizon), (w * 0.2, horizon - h * 0.12), (w * 0.45, horizon)], fill=(4, 6, 12))
    else:  # sunset, the mockup's palette
        gradient(img, [(0, (58, 52, 92)), (0.55, (210, 112, 72)), (1, (250, 196, 120))], 0, horizon)
        gradient(img, [(0, (230, 150, 92)), (0.3, (120, 70, 66)), (1, (28, 22, 30))], horizon, h)
        d = ImageDraw.Draw(img)
        d.ellipse([w * 0.6, horizon - 50 * scale, w * 0.6 + 70 * scale, horizon + 20 * scale], fill=(255, 226, 160))
        d.polygon([(0, horizon), (w * 0.25, horizon - h * 0.18), (w * 0.5, horizon)], fill=(52, 38, 54))
        d.polygon([(w * 0.55, horizon), (w * 0.8, horizon - h * 0.14), (w, horizon)], fill=(60, 42, 60))
        for _ in range(500):
            x, y = rnd.randrange(w), rnd.randrange(horizon, h)
            d.line([(x, y), (x + rnd.randrange(10, 60) * scale, y)], fill=(250, 190, 120), width=1)
    return img.filter(ImageFilter.GaussianBlur(scale * 0.6))


# ---------------------------------------------------------------------------------------------------------------------------
# Drawing the record
# ---------------------------------------------------------------------------------------------------------------------------
_tex, _fonts = {}, {}


def game_path(p):
    """Interface\\AddOns\\<addon>\\... -> a file in the repository; Interface\\Icons\\<name> -> a stand-in."""
    if not p:
        return None
    parts = p.replace("/", "\\").split("\\")
    if len(parts) >= 3 and parts[0].lower() == "interface" and parts[1].lower() == "addons" and parts[2] in ADDONS:
        rel = os.path.join(ADDONS[parts[2]], *parts[3:])
        for cand in (rel, rel + ".tga", rel + ".png"):
            if os.path.isfile(cand):
                return cand
        return None
    if len(parts) >= 3 and parts[1].lower() == "icons":
        name = parts[2].lower()
        cand = os.path.join(STANDINS, name + ".png")
        return cand if os.path.isfile(cand) else os.path.join(STANDINS, "unknown.png")
    return None


def texture(path):
    if path not in _tex:
        img = Image.open(path).convert("RGBA")
        if "standins" in path:            # a stand-in icon: squared and given the game's dark icon ground
            side = max(img.size)
            sq = Image.new("RGBA", (side, side), (24, 34, 44, 255))
            sq.alpha_composite(img, ((side - img.width) // 2, (side - img.height) // 2))
            img = sq
        _tex[path] = img
    return _tex[path]


def font(path, px):
    key = (path, px)
    if key not in _fonts:
        try:
            _fonts[key] = ImageFont.truetype(path, px)
        except OSError:
            _fonts[key] = ImageFont.load_default()
    return _fonts[key]


def to_px(rect, scale):
    l, b, w, h = rect
    return l * scale, (H - (b + h)) * scale, w * scale, h * scale


def blit(canvas, img, x, y, alpha, add=False):
    if alpha < 1:
        img = img.copy()
        img.putalpha(img.getchannel("A").point(lambda v: int(v * alpha)))
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(img, (int(round(x)), int(round(y))))
    if add:     # additive: the layer's color, weighted by its alpha, added to what is under it
        black = Image.new("RGB", canvas.size, (0, 0, 0))
        glow = Image.composite(layer.convert("RGB"), black, layer.getchannel("A"))
        rgb = ImageChops.add(canvas.convert("RGB"), glow)
        rgb.putalpha(canvas.getchannel("A"))
        canvas.paste(rgb)
        return
    canvas.alpha_composite(layer)


def draw_texture(canvas, r, scale):
    x, y, w, h = to_px(r["rect"], scale)
    if w < 1 or h < 1:
        return
    alpha = r["alpha"]
    if r.get("color"):
        c = r["color"]
        lay = Image.new("RGBA", (int(round(w)), int(round(h))), tuple(int(v * 255) for v in c[:3]) + (int(255 * c[3] * alpha),))
        blit(canvas, lay, x, y, 1)
        return
    path = game_path(r.get("file"))
    if not path:
        return
    src = texture(path)
    l, rr, t, b = r.get("coords") or [0, 1, 0, 1]
    box = (int(round(l * src.width)), int(round(t * src.height)), max(int(round(rr * src.width)), int(round(l * src.width)) + 1),
           max(int(round(b * src.height)), int(round(t * src.height)) + 1))
    x0, y0 = math.floor(x), math.floor(y)
    img = src.crop(box).resize((max(1, int(math.ceil(x + w)) - x0), max(1, int(math.ceil(y + h)) - y0)), Image.LANCZOS)
    blit(canvas, img, x0, y0, alpha, add=r.get("blend") == "ADD")


TOKEN = re.compile(r"\|c([0-9a-fA-F]{8})|\|r|\|T(.*?)\|t")


def segments(text, base):
    """Text and inline textures in order: ("text", s, color) and ("tex", path, size, coords)."""
    out, pos, color = [], 0, base
    for m in TOKEN.finditer(text):
        if m.start() > pos:
            out.append(("text", text[pos:m.start()], color))
        tok = m.group(0)
        if tok.startswith("|c"):
            hx = m.group(1)
            color = (int(hx[2:4], 16), int(hx[4:6], 16), int(hx[6:8], 16))
        elif tok == "|r":
            color = base
        else:
            parts = m.group(2).split(":")
            size = float(parts[1]) if len(parts) > 1 and parts[1] else 14.0
            coords = None
            if len(parts) >= 11:
                tw, th, l, r, t, b = (float(v) for v in parts[5:11])
                coords = (l / tw, r / tw, t / th, b / th)
            out.append(("tex", parts[0], size, coords))
        pos = m.end()
    if pos < len(text):
        out.append(("text", text[pos:], color))
    return out


def seg_width(f, seg, unit):
    return f.getlength(seg[1]) if seg[0] == "text" else seg[2] * unit


def draw_text(canvas, r, scale):
    text = r.get("text") or ""
    if not text:
        return
    path = game_path(r.get("font")) or os.path.join(ADDONS["!!!TwichUI"], "media", "fonts", "AlegreyaSans-Medium.ttf")
    unit = scale * r.get("scale", 1)
    px = max(6, int(round(r["size"] * unit)))
    f = font(path, px)
    c = r.get("color") or [1, 1, 1, 1]
    base = tuple(int(v * 255) for v in c[:3])
    segs = segments(text, base)
    width = sum(seg_width(f, sg, unit) for sg in segs)
    x, y, w, h = to_px(r["rect"], scale)
    anchor, justify = r.get("hanchor"), r.get("justify") or "CENTER"
    if r.get("fixedWidth"):
        if justify == "RIGHT":
            tx = x + w - width
        elif justify == "LEFT" or width > w + 1:
            tx = x
        else:
            tx = x + (w - width) / 2
    elif anchor == "R":
        tx = x + w - width
    elif anchor == "C":
        tx = x + w / 2 - width / 2
    else:
        tx = x
    asc, desc = f.getmetrics()
    ty = y + h / 2 - (asc + desc) / 2
    mid = y + h / 2
    alpha = r["alpha"] * (c[3] if len(c) > 3 else 1)
    lay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    if r.get("shadow"):
        sx, sy = r["shadow"]
        d = ImageDraw.Draw(lay)
        cx = tx
        for sg in segs:
            if sg[0] == "text":
                d.text((cx + sx * scale, ty - sy * scale), sg[1], font=f, fill=(0, 0, 0, int(235 * alpha)))
            cx += seg_width(f, sg, unit)
        lay = lay.filter(ImageFilter.GaussianBlur(scale * 0.45))
    d = ImageDraw.Draw(lay)
    cx = tx
    for sg in segs:
        if sg[0] == "text":
            d.text((cx, ty), sg[1], font=f, fill=sg[2] + (int(255 * alpha),))
        else:
            src_path = game_path(sg[1])
            side = int(round(sg[2] * unit))
            if src_path and side > 0:
                src = texture(src_path)
                if sg[3]:
                    l, rr, t, b = sg[3]
                    src = src.crop((int(l * src.width), int(t * src.height), int(rr * src.width), int(b * src.height)))
                img = src.resize((side, side), Image.LANCZOS)
                if alpha < 1:
                    img.putalpha(img.getchannel("A").point(lambda v: int(v * alpha)))
                lay.alpha_composite(img, (int(round(cx)), int(round(mid - side / 2))))
        cx += seg_width(f, sg, unit)
    if r.get("fixedWidth"):
        mask = Image.new("L", canvas.size, 0)
        ImageDraw.Draw(mask).rectangle([x - 2 * scale, 0, x + w + 2 * scale, canvas.height], fill=255)
        lay.putalpha(Image.composite(lay.getchannel("A"), Image.new("L", canvas.size, 0), mask))
    canvas.alpha_composite(lay)


def render(data, kind, scale):
    canvas = backdrop(kind, scale).convert("RGBA")
    for r in data["regions"]:
        if r["kind"] == "Texture":
            draw_texture(canvas, r, scale)
        else:
            draw_text(canvas, r, scale)
    return canvas


# The mockup's pieces (its own pixels, 1672 x 941) and the same pieces of a capture (screen units, 1366 x 768).
PIECES = [
    ("Emblem", (20, 10, 205, 90), (10, 8, 205, 92)),
    ("Catch list", (1280, 40, 1672, 410), (995, 60, 1366, 500)),
    ("Notification", (20, 360, 560, 465), (55, 395, 535, 495)),
    ("Cast bar", (590, 355, 1130, 475), (470, 545, 896, 662)),
]


def compare(mockup_path, capture_path, out_path):
    """The approved mockup beside a capture, piece by piece, each pair at the same height."""
    mock = Image.open(mockup_path).convert("RGB")
    cap = Image.open(capture_path).convert("RGB")
    k = cap.width / float(W)
    rows, width = [], 0
    for label, mbox, cbox in PIECES:
        m = mock.crop(mbox)
        c = cap.crop(tuple(int(v * k) for v in cbox))
        h = 300 if label == "Catch list" else 150
        m = m.resize((int(m.width * h / m.height), h), Image.LANCZOS)
        c = c.resize((int(c.width * h / c.height), h), Image.LANCZOS)
        rows.append((label, m, c))
        width = max(width, m.width + c.width + 60)
    height = sum(m.height + 40 for _, m, _ in rows) + 20
    sheet = Image.new("RGB", (width, height), (22, 18, 16))
    d = ImageDraw.Draw(sheet)
    f = font(os.path.join(ADDONS["!!!TwichUI"], "media", "fonts", "AlegreyaSans-Medium.ttf"), 18)
    y = 10
    for label, m, c in rows:
        d.text((10, y), label + ": approved mockup (left), offline capture (right)", font=f, fill=(226, 210, 180))
        sheet.paste(m, (10, y + 28))
        sheet.paste(c, (m.width + 40, y + 28))
        y += m.height + 40
    sheet.save(out_path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "test-output", "fishing-captures"))
    ap.add_argument("--scenes", default="immersive,compact,castbar")
    ap.add_argument("--backdrops", default="bright,dark,sunset")
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--compare", help="the approved mockup image: also writes compare-mockup.png beside the captures")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for scene in args.scenes.split(","):
        data = capture(scene, os.path.join(args.out, scene + ".json"))
        print("%s: %d regions, facts %s" % (scene, len(data["regions"]), data["facts"]))
        for kind in args.backdrops.split(","):
            img = render(data, kind, args.scale)
            if scene == "castbar":     # a close crop of the bar
                img = img.crop((380 * args.scale, 520 * args.scale, 986 * args.scale, 660 * args.scale))
            path = os.path.join(args.out, "%s-%s.png" % (scene, kind))
            img.convert("RGB").save(path, optimize=True)
            print("  wrote", path)
    if args.compare:
        out = os.path.join(args.out, "compare-mockup.png")
        compare(args.compare, os.path.join(args.out, "immersive-sunset.png"), out)
        print("wrote", out)


if __name__ == "__main__":
    main()
