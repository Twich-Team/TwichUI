#!/usr/bin/env python3
"""Builds the guild bank panel's frame (media/guildbank/frame-*.tga) from assets/guild-frame-source.png.

Standard library only, like tools/make_divider_art.py (PNG reader, premultiplied resampler, clear-edge colour bleed, TGA writer).

The painting is one 8-bit RGBA picture of a whole rectangular frame with real alpha: a hollow centre and a clear outside, four
rails and four corner blocks. It is not stretched over the panel. It is cut into four fixed corners and four rails:
  * each rail is a thin sample (8 px along it) of that rail just past the stub of the corner it starts at, cut from the rail's outer
    visible bound to its inner edge, which the panel stretches along the side (the cross section never changes along a rail, so
    nothing repeats). The painting is lit unevenly along its rails, so the tool also prints how much darker or lighter the rail is
    just before the stub of the corner it ends at (RAIL_END in the panel): the panel tints the stretched rail by that gradient so
    both ends meet their corners;
  * each corner is the corner block plus a short stub of both rails, cut from the same rows and columns as the rails next to it,
    so the corner and the rails join at exactly the same thickness. The four are separate cuts: the painting is not symmetric.
Each band is resampled to a whole number of pixels (BAND_*), which the panel's FT/FB/FL/FR constants repeat in UI units (px / 2).
Nothing is recoloured, sharpened or added.

    python3 tools/make_guild_frame_art.py [--src assets] [--out '!!!TwichUI/media/guildbank'] [--check]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_map_tool_icons import read_png, content_box, resample  # noqa: E402
from make_training_art import bleed, write_tga  # noqa: E402

SOURCE = "guild-frame-source.png"
CORNER = 64                        # px: the corner files are 64 x 64
# band thickness in pixels (outer visible bound to the rail's inner edge); the panel shows it at half size
BAND = {"top": 24, "bottom": 26, "left": 24, "right": 24}
LONG = 8                           # px along a rail in its file
STUB_GAP = 8                       # a rail's sample is taken this far past the end of the corner stub at its start


def runs(vals, th=128):
    out, s = [], None
    for i, v in enumerate(vals):
        if v > th and s is None:
            s = i
        if v <= th and s is not None:
            out.append((s, i)); s = None
    if s is not None:
        out.append((s, len(vals)))
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(root, "assets"))
    ap.add_argument("--out", default=os.path.join(root, "!!!TwichUI", "media", "guildbank"))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    w, h, px, has_alpha = read_png(os.path.join(args.src, SOURCE))
    if not has_alpha:
        raise SystemExit("%s: no alpha channel" % SOURCE)
    box = content_box(w, h, px)
    if box is None:
        raise SystemExit("%s: no visible content" % SOURCE)
    x0, y0, x1, y1 = box
    A = lambda x, y: px[y][x * 4 + 3]
    if A(w // 2, h // 2) != 0:
        raise SystemExit("%s: the centre is not clear (a baked fill)" % SOURCE)
    # the rails' inner edges, measured on quiet columns/rows
    top = runs([A(1000, y) for y in range(h)])
    left = runs([A(x, 400) for x in range(w)])
    if len(top) != 2 or len(left) != 2:
        raise SystemExit("%s: expected two rails per axis, found %s / %s" % (SOURCE, top, left))
    inner = {"top": top[0][1], "bottom": top[1][0], "left": left[0][1], "right": left[1][0]}
    outer = {"top": y0, "bottom": y1, "left": x0, "right": x1}
    src_band = {"top": inner["top"] - outer["top"], "bottom": outer["bottom"] - inner["bottom"],
                "left": inner["left"] - outer["left"], "right": outer["right"] - inner["right"]}
    print("visible %s; rail inner edges %s; bands in source px %s" % (box, inner, src_band))
    # corner cuts (source px along each axis), needed to find where each rail's stubs end
    def cut(side_axis_band, which):
        return int(round(CORNER / (BAND[which] / float(src_band[which]))))
    stub = {"left": cut(0, "left"), "right": cut(0, "right"), "top": cut(0, "top"), "bottom": cut(0, "bottom")}
    os.makedirs(args.out, exist_ok=True) if not args.check else None

    def save(name, canvas, cw, ch):
        bleed(canvas, cw, ch)
        if not args.check:
            write_tga(os.path.join(args.out, "frame-%s.tga" % name), canvas, cw, ch)

    # the rails
    for side in ("top", "bottom", "left", "right"):
        n = BAND[side]
        horizontal = side in ("top", "bottom")
        start = (x0 + stub["left"] if horizontal else y0 + stub["top"]) + STUB_GAP
        s = start
        stop = (x1 - stub["right"] if horizontal else y1 - stub["bottom"]) - STUB_GAP - LONG
        lo, hi = (outer[side], inner[side]) if side in ("top", "left") else (inner[side], outer[side])
        def mean(at):
            tot, cnt = 0.0, 0
            for k in range(at, at + LONG):
                for m in range(lo, hi):
                    xx, yy = (k, m) if horizontal else (m, k)
                    q = px[yy][xx * 4:xx * 4 + 4]
                    if q[3] > 200:
                        tot += q[0] + q[1] + q[2]; cnt += 1
            return tot / max(cnt, 1)
        print("rail %-6s sample at %d, end sample at %d: RAIL_END = %.2f" % (side, start, stop, mean(stop) / mean(start)))
        if horizontal:
            rows = (outer[side], inner[side]) if side == "top" else (inner[side], outer[side])
            body = resample(px, (s, rows[0], s + LONG, rows[1]), LONG, n)
            cw, ch = LONG, 32
            canvas = [bytearray(cw * 4) for _ in range(ch)]
            at = 0 if side == "top" else ch - n
            for i in range(n):
                canvas[at + i][:] = body[i]
        else:
            cols = (outer[side], inner[side]) if side == "left" else (inner[side], outer[side])
            body = resample(px, (cols[0], s, cols[1], s + LONG), n, LONG)
            cw, ch = 32, LONG
            canvas = [bytearray(cw * 4) for _ in range(ch)]
            at = 0 if side == "left" else cw - n
            for i in range(LONG):
                canvas[i][at * 4:(at + n) * 4] = body[i]
        save("edge-" + side, canvas, cw, ch)
    # the corners: each cut as wide as 64 px is at its two rails' scales, from the outer corner of the visible content
    for name, (vs, hs) in {"tl": ("top", "left"), "tr": ("top", "right"), "bl": ("bottom", "left"), "br": ("bottom", "right")}.items():
        sx, sy = BAND[hs] / float(src_band[hs]), BAND[vs] / float(src_band[vs])
        cw_src, ch_src = int(round(CORNER / sx)), int(round(CORNER / sy))
        bx0 = x0 if hs == "left" else x1 - cw_src
        by0 = y0 if vs == "top" else y1 - ch_src
        body = resample(px, (bx0, by0, bx0 + cw_src, by0 + ch_src), CORNER, CORNER)
        save("corner-" + name, [bytearray(r) for r in body], CORNER, CORNER)
        print("corner %s: source (%d,%d) %dx%d -> %dx%d" % (name, bx0, by0, cw_src, ch_src, CORNER, CORNER))


if __name__ == "__main__":
    main()
