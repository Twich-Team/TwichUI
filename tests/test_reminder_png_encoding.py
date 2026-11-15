"""Canonical source PNG bytes are independent of host compression settings."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import unittest
from unittest import mock
import zlib

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from make_reminder_gallery import stored_zlib, png_rgba_bytes


def chunks(data):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('PNG signature')
    pos, result = 8, []
    while pos < len(data):
        size = int.from_bytes(data[pos:pos + 4], 'big')
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + size]
        crc = int.from_bytes(data[pos + 8 + size:pos + 12 + size], 'big')
        if crc != zlib.crc32(kind + body) & 0xffffffff:
            raise ValueError('PNG CRC')
        result.append((kind, body))
        pos += 12 + size
    if pos != len(data):
        raise ValueError('PNG length')
    return result


class StoredEncoding(unittest.TestCase):
    def test_rfc_vectors(self):
        self.assertEqual(stored_zlib(b''), bytes.fromhex('7801010000ffff00000001'))
        self.assertEqual(stored_zlib(b'abc'), bytes.fromhex('7801010300fcff616263024d0127'))

    def test_block_boundaries_and_exact_bytes(self):
        for size in (0, 1, 65535, 65536, 131070):
            raw = bytes(i % 256 for i in range(size))
            encoded = stored_zlib(raw)
            self.assertEqual(zlib.decompress(encoded), raw)
            offset = 2
            for start in range(0, size or 1, 65535):
                flag, length, inverse = struct.unpack('<BHH', encoded[offset:offset + 5])
                self.assertEqual(length, min(65535, size - start))
                self.assertEqual(inverse, length ^ 65535)
                self.assertEqual(flag, int(start + length == size))
                self.assertEqual(encoded[offset + 5:offset + 5 + length], raw[start:start + length])
                offset += 5 + length
            self.assertEqual(offset, len(encoded) - 4)

    def test_no_compressor_and_no_metadata(self):
        row = b'\x12\x34\x56\x00'  # Hidden RGB must survive zero alpha.
        with mock.patch.object(zlib, 'compress', side_effect=AssertionError('host compressor used')):
            data = png_rgba_bytes(1, 1, [row])
        c = chunks(data)
        self.assertEqual([k for k, _ in c], [b'IHDR', b'IDAT', b'IEND'])
        self.assertEqual(c[0][1], struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0))
        self.assertEqual(zlib.decompress(c[1][1]), b'\x00' + row)
        corrupt = bytearray(data)
        corrupt[-5] ^= 1
        with self.assertRaisesRegex(ValueError, 'CRC'):
            chunks(corrupt)

    def test_invalid_dimensions_fail(self):
        for w, h, rows in ((0, 1, [b'']), (1, 1, [b'bad']), (1, 2, [b'abcd'])):
            with self.assertRaises(ValueError):
                png_rgba_bytes(w, h, rows)

    def test_all_migrated_files_match_inventory_and_canonical_encoder(self):
        doc = json.loads((ROOT / 'docs/reminder-png-migration.json').read_text())
        for image in doc['images']:
            data = (ROOT / image['path']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), image['new_sha256'], image['path'])
            c = chunks(data)
            self.assertEqual([k for k, _ in c], [b'IHDR', b'IDAT', b'IEND'])
            w, h = struct.unpack('>II', c[0][1][:8])
            raw = zlib.decompress(c[1][1])
            self.assertEqual(hashlib.sha256(raw).hexdigest(), image['scanlines_sha256'])
            self.assertEqual(len(raw), h * (1 + w * 4))
            rows = []
            for i in range(h):
                start = i * (1 + w * 4)
                self.assertEqual(raw[start], 0)
                rows.append(raw[start + 1:start + 1 + w * 4])
            self.assertEqual(png_rgba_bytes(w, h, rows), data)
        for path, digest in {**doc['tgas'], **doc['others']}.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest, path)
