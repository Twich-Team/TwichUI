#!/usr/bin/env python3
"""Writes media/textures/mist.tga: one soft wisp of mist for the combo points' poison mist.

Original, procedural art (seeded value noise under a round falloff), so it is covered by
TwichUI's own license. White, so the game tints it; the shape is all in the alpha.
64 x 64, uncompressed 32-bit TGA (the format of media/icon.tga). Run from the repository root:
    python3 tools/make_mist_texture.py
The same seed gives the same file.
"""
import math
import os
import random
import struct

SIZE = 64
SEED = 1719


def value_noise(rng, cells):
    grid = [[rng.random() for _ in range(cells + 1)] for _ in range(cells + 1)]

    def smooth(t):
        return t * t * (3 - 2 * t)

    def sample(x, y):
        gx, gy = x * cells, y * cells
        x0, y0 = int(gx), int(gy)
        x1, y1 = min(x0 + 1, cells), min(y0 + 1, cells)
        tx, ty = smooth(gx - x0), smooth(gy - y0)
        top = grid[y0][x0] * (1 - tx) + grid[y0][x1] * tx
        bottom = grid[y1][x0] * (1 - tx) + grid[y1][x1] * tx
        return top * (1 - ty) + bottom * ty

    return sample


def main():
    rng = random.Random(SEED)
    octaves = [(value_noise(rng, cells), weight) for cells, weight in ((3, 0.55), (6, 0.3), (12, 0.15))]
    alphas = []
    # TGA rows run bottom to top by default
    for row in range(SIZE - 1, -1, -1):
        for col in range(SIZE):
            x, y = (col + 0.5) / SIZE, (row + 0.5) / SIZE
            noise = sum(sample(x, y) * weight for sample, weight in octaves)
            # a round, soft-edged puff, slightly wider than tall, fading to nothing at the edge
            dx, dy = (x - 0.5) / 0.48, (y - 0.5) / 0.42
            r = math.sqrt(dx * dx + dy * dy)
            falloff = max(0.0, 1.0 - r) ** 1.6
            alphas.append(max(0.0, falloff * (0.35 + 0.95 * noise)))
    peak = max(alphas) / 0.9   # the densest part at 90%, so the game's alpha has the full range
    pixels = bytearray()
    for alpha in alphas:
        pixels += bytes((255, 255, 255, int(min(1.0, alpha / peak) * 255 + 0.5)))   # B, G, R, A
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "media", "textures", "mist.tga")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header + pixels)
    print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    main()
