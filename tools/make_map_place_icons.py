#!/usr/bin/env python3
"""Draws the world map's place icons (TwichUI's own art) into media/textures, standard library only.

    python3 tools/make_map_place_icons.py [--out '!!!TwichUI/media/textures'] [--preview DIR]

Each is 32 x 32: a round badge (dark umber face, bronze ring, dark rim) with an ivory glyph, so a place reads apart from
TwichUI's pins (a bevelled diamond) by shape, not color alone, and each kind apart from the others by its glyph:

  place-dungeon.tga   an arched doorway        place-raid.tga      a battlemented tower
  place-cave.tga      a hill with a dark mouth place-boat.tga      a sailing ship
  place-zeppelin.tga  a balloon and gondola

And the stitched world map's edge masks (white, the fade in the alpha channel, 256 x 256, as the game's mask textures
take them; shapes only, no art):

  map-feather-thin.tga   a rectangle fading out over its outer 4% (a zone's pieces meeting its neighbours)
  map-feather-wide.tga   ... over its outer 20% (a continent's painting fading into the world's)
  map-feather-round.tga  an ellipse fading from 70% of its radius (a city's map, its frame dropping away)

Drawn at 8x and box-filtered with premultiplied alpha by tools/make_nav_textures.py's helpers, written as the same
uncompressed 32-bit bottom-left-origin TGA the other media/textures files are. --preview also writes PNGs to look at.
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_nav_textures import (BRONZE, BRONZE_HI, BRONZE_LO, EDGE, inside_poly, mix, render,  # noqa: E402
                               write_png, write_tga)

SIZE = 32
C = SIZE / 2
R_OUT, RIM, RING = 15.2, 1.1, 1.8
FACE = (0.17, 0.12, 0.08)
IVORY = (0.95, 0.90, 0.78)
DARK = (0.08, 0.06, 0.04)


def badge(glyph):
    """glyph(x, y) -> (r, g, b, a) or None where the badge's face shows."""
    def shade(x, y):
        d = math.hypot(x - C, y - C)
        if d > R_OUT:
            return (0, 0, 0, 0)
        if d > R_OUT - RIM:
            return (*EDGE, 1)
        if d > R_OUT - RIM - RING:
            t = 0.5 + 0.5 * ((C - x) + (C - y)) / (2 * C)     # lit from the top left
            return (*mix(BRONZE_LO, BRONZE_HI, max(0.0, min(1.0, t))), 1)
        g = glyph(x, y)
        if g:
            return g
        k = 0.85 + 0.15 * (1 - d / R_OUT)
        return (FACE[0] * k, FACE[1] * k, FACE[2] * k, 1)
    return shade


def in_rect(x, y, x0, y0, x1, y1):
    return x0 <= x <= x1 and y0 <= y <= y1


def dungeon(x, y):
    # an arched doorway: an ivory frame round a dark opening, on a step
    if in_rect(x, y, 8.5, 22.5, 23.5, 24.5):
        return (*IVORY, 1)
    outer = (in_rect(x, y, 10, 14, 22, 23)) or math.hypot(x - 16, y - 14) <= 6
    inner = (in_rect(x, y, 12.6, 14, 19.4, 23)) or math.hypot(x - 16, y - 14) <= 3.4
    if outer and not inner:
        return (*IVORY, 1)
    if inner:
        return (*DARK, 1)
    return None


def raid(x, y):
    # a tower with three merlons and a dark door
    body = in_rect(x, y, 10, 13, 22, 24.5)
    merlon = y >= 9 and y < 13 and any(in_rect(x, y, a, 9, a + 2.2, 13) for a in (10, 13.27, 16.53, 19.8))
    door = in_rect(x, y, 14.5, 20.5, 17.5, 24.5) or (math.hypot(x - 16, y - 20.5) <= 1.5 and y < 20.5)
    if door:
        return (*DARK, 1)
    if body or merlon:
        return (*IVORY, 1)
    return None


def cave(x, y):
    hill = [(5.5, 24), (13, 9.5), (17, 13.5), (19.5, 11), (26.5, 24)]
    mouth = (in_rect(x, y, 12.5, 18.5, 19.5, 24)) or math.hypot(x - 16, y - 18.5) <= 3.5
    if mouth and y <= 24:
        return (*DARK, 1)
    if inside_poly(x, y, hill):
        return (*mix(IVORY, BRONZE, 0.15 * (y - 9) / 15), 1)
    return None


def boat(x, y):
    hull = [(7, 19.5), (25, 19.5), (21.5, 24), (10.5, 24)]
    sail = [(16.6, 7.5), (16.6, 18), (24, 18)]
    jib = [(15.4, 9.5), (15.4, 18), (9.5, 18)]
    if in_rect(x, y, 15.4, 7, 16.6, 19.5):
        return (*IVORY, 1)
    if inside_poly(x, y, hull):
        return (*IVORY, 1)
    if inside_poly(x, y, sail) or inside_poly(x, y, jib):
        return (*mix(IVORY, BRONZE_HI, 0.25), 1)
    return None


def zeppelin(x, y):
    e = ((x - 16) / 9.5) ** 2 + ((y - 13) / 5.2) ** 2
    if e <= 1:
        if abs(y - 13) < 0.6:
            return (*mix(IVORY, BRONZE, 0.35), 1)       # a seam along the balloon
        return (*IVORY, 1)
    if inside_poly(x, y, [(24.5, 13), (27.5, 9.5), (27.5, 16.5)]):
        return (*IVORY, 1)                              # the fins
    if in_rect(x, y, 13, 20, 19, 23) or in_rect(x, y, 14.2, 17.5, 15, 20) or in_rect(x, y, 17, 17.5, 17.8, 20):
        return (*mix(IVORY, BRONZE_HI, 0.3), 1)        # the gondola and its ropes
    return None


ICONS = (("place-dungeon", dungeon), ("place-raid", raid), ("place-cave", cave), ("place-boat", boat),
         ("place-zeppelin", zeppelin))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def mask(size, alpha):
    """Rows of RGBA bytes: white, alpha(x, y) in 0..1 at the pixel's centre (x, y from 0 to 1)."""
    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            a = alpha((x + 0.5) / size, (y + 0.5) / size)
            row += bytes((255, 255, 255, round(a * 255)))
        rows.append(row)
    return rows


def feather(edge):
    return lambda x, y: smooth(min(x, 1 - x, y, 1 - y) / edge)


def round_feather(x, y):
    d = math.hypot(x - 0.5, y - 0.5) / 0.5
    return smooth((1 - d) / 0.3)


MASKS = (("map-feather-thin", feather(0.04)), ("map-feather-wide", feather(0.20)), ("map-feather-round", round_feather))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join("!!!TwichUI", "media", "textures"))
    ap.add_argument("--preview")
    a = ap.parse_args()
    for name, glyph in ICONS:
        rows = render(SIZE, badge(glyph))
        write_tga(os.path.join(a.out, name + ".tga"), SIZE, rows)
        if a.preview:
            write_png(os.path.join(a.preview, name + ".png"), SIZE, rows)
        print("wrote", name, SIZE)
    for name, alpha in MASKS:
        rows = mask(256, alpha)
        write_tga(os.path.join(a.out, name + ".tga"), 256, rows)
        print("wrote", name, 256)


if __name__ == "__main__":
    main()
