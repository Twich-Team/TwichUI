"""Build the neutral, antialiased C1.1 marker material (stdlib only)."""
from pathlib import Path
import math
import struct


def build():
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, 16, 16, 32, 0x28)
    pixels = bytearray()
    for y in range(16):
        for x in range(16):
            alpha = round(255 * max(0, min(1, 7 - math.hypot(x - 7.5, y - 7.5))))
            pixels.extend((255, 255, 255, alpha))
    return header + pixels


if __name__ == '__main__':
    (Path(__file__).resolve().parents[1] / 'TwichUI_Workshop/media/chart-marker.tga').write_bytes(build())
