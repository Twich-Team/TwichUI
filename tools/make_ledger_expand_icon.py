"""Build the Gold Flow "expand" icon (stdlib only): a diagonal double-headed arrow, each head an open corner, inside a rounded rim.
White with alpha, tinted by the addon. 32x32, antialiased by 4x4 supersampling."""
from pathlib import Path
import math
import struct

SIZE, SS = 32, 4


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def rim(px, py, lo=1.6, hi=30.4, r=5.0, half=0.8):
    # distance to a rounded rectangle's outline
    cx, cy = (lo + hi) / 2, (lo + hi) / 2
    qx, qy = abs(px - cx) - ((hi - lo) / 2 - r), abs(py - cy) - ((hi - lo) / 2 - r)
    d = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    return abs(d) - half


STROKES = [  # (ax, ay, bx, by): image coordinates, y down
    (9.5, 22.5, 22.5, 9.5),                  # the diagonal
    (22.5, 9.5, 14.5, 9.5), (22.5, 9.5, 22.5, 17.5),   # top-right head: an open corner
    (9.5, 22.5, 17.5, 22.5), (9.5, 22.5, 9.5, 14.5),   # bottom-left head
]
HALF = 1.45


def build():
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            arrow = rim_cov = 0
            for sy in range(SS):
                for sx in range(SS):
                    px, py = x + (sx + 0.5) / SS, y + (sy + 0.5) / SS
                    if min(seg_dist(px, py, *s) for s in STROKES) <= HALF:
                        arrow += 1
                    if rim(px, py) <= 0:
                        rim_cov += 1
            a = arrow / (SS * SS)
            r = 0.5 * rim_cov / (SS * SS)   # the rim is quieter than the arrow
            alpha = max(a, r)
            pixels.extend((255, 255, 255, round(255 * alpha)))
    return header + pixels


if __name__ == '__main__':
    (Path(__file__).resolve().parents[1] / 'TwichUI_Workshop/media/chart-expand.tga').write_bytes(build())
