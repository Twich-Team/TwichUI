"""PNG decoding parity for all filters, row edges, byte overflow and alpha."""
import importlib.util
from pathlib import Path
import random
import struct
import tempfile
import unittest
import zlib

REPO = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('simlab_png', REPO / 'tools/simlab/verdict.py')
png = importlib.util.module_from_spec(spec)
spec.loader.exec_module(png)


def paeth(left, up, corner):
    estimate = left + up - corner
    # Independent reference, including the specified tie precedence.
    return min((abs(estimate - left), 0, left), (abs(estimate - up), 1, up),
               (abs(estimate - corner), 2, corner))[2]


def encode(rows, width, filters):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    raw = bytearray()
    previous = bytes(width * 4)
    for y, row in enumerate(rows):
        kind = filters[y % len(filters)]
        raw.append(kind)
        for x, value in enumerate(row):
            left, up, corner = (row[x - 4] if x >= 4 else 0), previous[x], (previous[x - 4] if x >= 4 else 0)
            predictor = [0, left, up, (left + up) // 2, paeth(left, up, corner)][kind] if kind < 5 else 0
            raw.append((value - predictor) % 256)
        previous = row
    header = struct.pack('>IIBBBBB', width, len(rows), 8, 6, 0, 0, 0)
    compressed = zlib.compress(raw)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', compressed[:9])
            + chunk(b'IDAT', compressed[9:]) + chunk(b'IEND', b''))


class Decoder(unittest.TestCase):
    def test_corrupt_inputs_are_rejected(self):
        def chunk(kind, body):
            return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
        valid = encode([bytes(8)], 2, [0])
        header = chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 1, 8, 6, 0, 0, 0))
        def image(raw):
            return valid[:8] + header + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
        cases = [b'', b'badbytes' + valid[8:], valid[:-1], valid + b'x',
                 valid[:40] + bytes([valid[40] ^ 1]) + valid[41:],
                 valid[:8] + header + valid[8:], image(bytes(8)), image(bytes(10)),
                 valid[:8] + header + chunk(b'IEND', b''),
                 valid[:8] + header + chunk(b'IDAT', b'bad zlib') + chunk(b'IEND', b'')]
        for width, height in ((0, 1), (1, 0), (16385, 1), (16384, 16384)):
            cases.append(valid[:8] + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) + valid[33:])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.png'
            for data in cases:
                with self.subTest(size=len(data), prefix=data[:12]):
                    path.write_bytes(data)
                    with self.assertRaises(ValueError):
                        png.read_rgba(path)

    def test_paeth_threshold_ties_and_extremes(self):
        # Force all predictor branches and exact threshold ties independently
        # of a screenshot's usual low-entropy pixels.
        rng = random.Random(921)
        rows = [bytes(rng.choice((0, 1, 10, 20, 30, 40, 127, 128, 254, 255))
                      for _ in range(1024)) for _ in range(64)]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'threshold.png'
            path.write_bytes(encode(rows, 256, [4]))
            self.assertEqual([bytes(r) for r in png.read_rgba(path)[2]], rows)

    def test_all_filters_reconstruct_exact_bytes(self):
        rng = random.Random(4901)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'test.png'
            for width in (1, 2, 17, 64):
                rows = [bytes(rng.randrange(256) for _ in range(width * 4)) for _ in range(13)]
                for filters in ([0], [1], [2], [3], [4], [0, 4, 1, 2, 3]):
                    with self.subTest(width=width, filters=filters):
                        path.write_bytes(encode(rows, width, filters))
                        w, h, actual = png.read_rgba(path)
                        self.assertEqual((w, h), (width, len(rows)))
                        self.assertEqual([bytes(r) for r in actual], rows)

    def test_flat_rows_and_paeth_ties(self):
        rows = [bytes([n] * 20) for n in (0, 255, 0, 128, 128)]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'ties.png'
            path.write_bytes(encode(rows, 5, [4]))
            self.assertEqual([bytes(r) for r in png.read_rgba(path)[2]], rows)

    def test_unknown_filter_cannot_produce_a_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.png'
            path.write_bytes(encode([bytes(8)], 2, [5]))
            with self.assertRaises(ValueError):
                png.read_rgba(path)

    def test_colour_count_crops_and_ignores_alpha(self):
        rows = [bytes([10, 20, 30, 0, 10, 20, 30, 255, 2, 3, 4, 255]),
                bytes([7, 8, 9, 255, 10, 20, 30, 2, 2, 3, 4, 3])]
        self.assertEqual(png.distinct_colours(rows, 0, 0, 3, 2), 3)
        self.assertEqual(png.distinct_colours(rows, 1, 0, 2, 2), 2)
        self.assertEqual(png.distinct_colours(rows, 1, 1, 1, 1), 1)


if __name__ == '__main__':
    unittest.main()
