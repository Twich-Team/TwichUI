#!/usr/bin/env python3
"""Draws the world map's vendor and trainer icons (TwichUI's own art) into media/textures, standard library only.

    python3 tools/make_npc_icons.py [--out '!!!TwichUI/media/textures'] [--preview DIR]

Each is 32 x 32: a rounded square plaque (dark umber face, bronze edge, dark rim) with an ivory glyph, so an NPC reads
apart from TwichUI's pins (a bevelled diamond) and the map's places (a round badge) by shape, not color alone, and each
kind apart from the others by its glyph (npcs/Kinds.lua names them; the file is npc-<kind>.tga):

  reagents   a stoppered flask        ammo         an arrow             repair      an anvil
  trade      a spool of thread        food         a mug                recipes     a rolled scroll
  bags       a tied pouch             vendor       a coin               classTrainer an open book
  profTrainer a hammer                petTrainer   a paw                innkeeper   a house
  banker     a chest                  auctioneer   a gavel              flight      a wing
  stable     a horseshoe              guild        a banner             spirit      an ankh

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
HALF, CORNER, RIM, RING = 14.6, 5.0, 1.1, 1.8
FACE = (0.17, 0.12, 0.08)
IVORY = (0.95, 0.90, 0.78)
DARK = (0.08, 0.06, 0.04)
C = SIZE / 2


def rounded(x, y, half, corner):
    """Distance outside a rounded square centred on the icon (negative inside)."""
    dx, dy = abs(x - C) - (half - corner), abs(y - C) - (half - corner)
    return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - corner


def plaque(glyph):
    def shade(x, y):
        d = rounded(x, y, HALF, CORNER)
        if d > 0:
            return (0, 0, 0, 0)
        if d > -RIM:
            return (*EDGE, 1)
        if d > -RIM - RING:
            t = 0.5 + 0.5 * ((C - x) + (C - y)) / (2 * C)     # lit from the top left
            return (*mix(BRONZE_LO, BRONZE_HI, max(0.0, min(1.0, t))), 1)
        g = glyph(x, y)
        if g:
            return g
        k = 0.85 + 0.15 * (1 + d / HALF)
        return (FACE[0] * k, FACE[1] * k, FACE[2] * k, 1)
    return shade


def rect(x, y, x0, y0, x1, y1):
    return x0 <= x <= x1 and y0 <= y <= y1


def circle(x, y, cx, cy, r):
    return math.hypot(x - cx, y - cy) <= r


def ring(x, y, cx, cy, r0, r1):
    d = math.hypot(x - cx, y - cy)
    return r0 <= d <= r1


def seg(x, y, ax, ay, bx, by, w):
    """Within w/2 of the segment a-b."""
    vx, vy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
    return math.hypot(x - (ax + t * vx), y - (ay + t * vy)) <= w / 2


I = (*IVORY, 1)
SOFT = (*mix(IVORY, BRONZE_HI, 0.3), 1)
D = (*DARK, 1)


def reagents(x, y):
    if rect(x, y, 14, 7.5, 18, 10):
        return SOFT                                      # the stopper
    if rect(x, y, 14.5, 10, 17.5, 14):
        return I                                         # the neck
    if circle(x, y, 16, 19.5, 6.2):
        if y > 19 and circle(x, y, 16, 19.5, 4.6):
            return SOFT                                  # what's inside
        return I
    return None


def ammo(x, y):
    if inside_poly(x, y, [(23.5, 8.5), (24, 14), (18, 10)]):
        return I                                         # the head
    if seg(x, y, 9, 23, 22, 10, 1.6):
        return I
    if seg(x, y, 8, 20, 11, 24.5, 1.4) or seg(x, y, 10.5, 18, 13.5, 22.5, 1.4):
        return SOFT                                      # the fletching
    return None


def repair(x, y):
    if inside_poly(x, y, [(7, 11), (25, 11), (25, 14), (21, 15.5), (19, 18), (13, 18), (11, 15.5), (7, 14)]):
        return I
    if inside_poly(x, y, [(13, 18), (19, 18), (21, 24), (11, 24)]):
        return SOFT
    return None


def trade(x, y):
    if rect(x, y, 10, 8, 22, 10.5) or rect(x, y, 10, 21.5, 22, 24):
        return I                                         # the spool's ends
    if rect(x, y, 12, 10.5, 20, 21.5):
        if (y - 10.5) % 2.2 < 1.1:
            return SOFT                                  # wound thread
        return I
    return None


def food(x, y):
    if ring(x, y, 22, 16.5, 2.4, 4.0) and x > 22:
        return I                                         # the handle
    if rect(x, y, 9, 10, 21, 24):
        if y < 13:
            return SOFT                                  # froth
        return I
    return None


def recipes(x, y):
    if rect(x, y, 10, 10, 22, 22):
        if rect(x, y, 12.5, 13, 19.5, 14) or rect(x, y, 12.5, 16, 19.5, 17) or rect(x, y, 12.5, 19, 17.5, 20):
            return D                                     # lines of writing
        return I
    if circle(x, y, 10, 10, 2.4) or circle(x, y, 22, 22, 2.4):
        return SOFT                                      # the rolled ends
    return None


def bags(x, y):
    if rect(x, y, 12, 11.5, 20, 13.5):
        return SOFT                                      # the drawstring
    if inside_poly(x, y, [(10.5, 7.5), (14, 9.5), (16, 8), (18, 9.5), (21.5, 7.5), (19.5, 11.5), (12.5, 11.5)]):
        return I                                         # the gathered top
    if inside_poly(x, y, [(12, 13.5), (20, 13.5), (24, 19), (23, 24), (9, 24), (8, 19)]):
        if seg(x, y, 13, 16, 11.5, 22, 1.0):
            return SOFT                                  # a fold
        return I
    return None


def vendor(x, y):
    if ring(x, y, 16, 16, 6.2, 8):
        return I
    if rect(x, y, 15, 11.5, 17, 20.5):
        return SOFT                                      # the coin's mark
    if circle(x, y, 16, 16, 6.2):
        return (*mix(IVORY, BRONZE, 0.45), 1)
    return None


def class_trainer(x, y):
    if rect(x, y, 15.4, 10, 16.6, 23):
        return D                                         # the spine
    left = inside_poly(x, y, [(7.5, 11), (15.4, 10), (15.4, 23), (7.5, 22)])
    right = inside_poly(x, y, [(16.6, 10), (24.5, 11), (24.5, 22), (16.6, 23)])
    if left or right:
        if (y - 12) % 3 < 0.9 and 13 < y < 21 and (9 < x < 14.5 or 17.5 < x < 23):
            return SOFT
        return I
    return None


def prof_trainer(x, y):
    if inside_poly(x, y, [(9, 9), (19, 9), (20.5, 11), (20.5, 13.5), (9, 13.5)]):
        return I                                         # the head
    if seg(x, y, 14.5, 13.5, 21, 24.5, 2.6):
        return SOFT                                      # the handle
    return None


def pet_trainer(x, y):
    if circle(x, y, 16, 19.5, 4.6):
        return I
    for cx, cy in ((10.5, 14.5), (14, 10.5), (18, 10.5), (21.5, 14.5)):
        if circle(x, y, cx, cy, 2.2):
            return I
    return None


def innkeeper(x, y):
    if inside_poly(x, y, [(16, 7.5), (25, 15), (7, 15)]):
        return SOFT                                      # the roof
    if rect(x, y, 9.5, 15, 22.5, 24):
        if rect(x, y, 14.5, 18.5, 17.5, 24):
            return D                                     # the door
        return I
    return None


def banker(x, y):
    if rect(x, y, 8, 15, 24, 23.5):
        if rect(x, y, 15, 15.5, 17, 18.5):
            return D                                     # the lock
        return I
    if rect(x, y, 8, 13.8, 24, 15):
        return D                                         # where the lid meets the box
    if rect(x, y, 8, 10, 24, 13.8) and rounded(x + 0, y + 5, 8, 3) <= 0:
        return SOFT                                      # the lid
    return None


def auctioneer(x, y):
    if seg(x, y, 8.5, 15.5, 15.5, 8.5, 5):
        return I                                         # the head, across the handle
    if seg(x, y, 12, 12, 23, 23, 2.2):
        return SOFT                                      # the handle
    if rect(x, y, 6.5, 22.5, 14.5, 24.5):
        return SOFT                                      # the block
    return None


def flight(x, y):
    for i, (ax, ay, bx, by) in enumerate(((8, 22, 23, 9), (9, 23, 24, 13), (10, 24, 24, 17), (12, 24.5, 23, 21))):
        if seg(x, y, ax, ay, bx, by, 2.2):
            return I if i % 2 == 0 else SOFT
    return None


def stable(x, y):
    if ring(x, y, 16, 14.5, 4.2, 7.4) and y < 20:
        if (circle(x, y, 10.2, 13, 0.8) or circle(x, y, 21.8, 13, 0.8)
                or circle(x, y, 11.8, 9, 0.8) or circle(x, y, 20.2, 9, 0.8)):
            return D                                     # nail holes
        return I
    if rect(x, y, 8.6, 19, 11.4, 22.5) or rect(x, y, 20.6, 19, 23.4, 22.5):
        return I                                         # the heels
    return None


def guild(x, y):
    if rect(x, y, 9, 7, 10.8, 25):
        return SOFT                                      # the pole
    if inside_poly(x, y, [(10.8, 8), (23.5, 8), (23.5, 19), (17, 16.5), (10.8, 19)]):
        if circle(x, y, 17, 12.5, 2):
            return D
        return I
    return None


def spirit(x, y):
    if ring(x, y, 16, 11, 2.4, 4.4):
        return I                                         # the loop
    if rect(x, y, 14.8, 15, 17.2, 25) or rect(x, y, 9.5, 15.5, 22.5, 17.8):
        return I
    return None


ICONS = (("reagents", reagents), ("ammo", ammo), ("repair", repair), ("trade", trade), ("food", food),
         ("recipes", recipes), ("bags", bags), ("vendor", vendor), ("classTrainer", class_trainer),
         ("profTrainer", prof_trainer), ("petTrainer", pet_trainer), ("innkeeper", innkeeper), ("banker", banker),
         ("auctioneer", auctioneer), ("flight", flight), ("stable", stable), ("guild", guild), ("spirit", spirit))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join("!!!TwichUI", "media", "textures"))
    ap.add_argument("--preview")
    a = ap.parse_args()
    for name, glyph in ICONS:
        rows = render(SIZE, plaque(glyph))
        write_tga(os.path.join(a.out, "npc-" + name + ".tga"), SIZE, rows)
        if a.preview:
            write_png(os.path.join(a.preview, "npc-" + name + ".png"), SIZE, rows)
        print("wrote", "npc-" + name, SIZE)


if __name__ == "__main__":
    main()
