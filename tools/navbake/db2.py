"""A reader for the client's DB2 tables (format WDC5), standard library only.

    t = DB2(storage.read(1068100))
    for row_id, fields in t.rows():       # fields: a list per column, each a number, a string or a list of numbers
        ...

Columns have no names in the file; callers know them by position (see transit.py, which says where each came from and
how it was checked against this client). Handles one or more sections, the ID list or an ID column, copy tables, the
per-column storage forms (plain, bit-packed, signed bit-packed, common-value, pallet and pallet arrays) and the string
table. Offset-map ("sparse") tables and encrypted sections are refused rather than guessed at.
"""

import struct

NONE, BITPACKED, COMMON, PALLET, PALLET_ARRAY, SIGNED = 0, 1, 2, 3, 4, 5


class DB2Error(Exception):
    pass


def _bits(data, bit_pos, n):
    """n bits (little endian) starting at bit_pos."""
    first = bit_pos >> 3
    last = (bit_pos + n + 7) >> 3
    v = int.from_bytes(data[first:last], "little")
    return (v >> (bit_pos & 7)) & ((1 << n) - 1)


class DB2:
    def __init__(self, data):
        if data is None or data[:4] != b"WDC5":
            raise DB2Error("not a WDC5 table")
        (self.record_count, self.field_count, self.record_size, self.string_size, self.table_hash, self.layout_hash,
         self.min_id, self.max_id, self.locale, self.flags, self.id_index, self.total_fields, self.bitpacked_offset,
         self.lookup_columns, fsi_size, common_size, pallet_size, nsec) = struct.unpack_from("<IIIIIIIIIHHIIIIIII", data, 136)
        if self.flags & 1:
            raise DB2Error("offset-map (sparse) tables are not supported")
        pos = 204
        sections = [struct.unpack_from("<QIIIIIIII", data, pos + 40 * i) for i in range(nsec)]
        pos += 40 * nsec
        pos += 4 * self.field_count                       # field structure (sizes and positions), not needed here
        self.fsi = []
        for i in range(fsi_size // 24):
            off, size, extra, kind, a, b, c = struct.unpack_from("<HHIIIII", data, pos + 24 * i)
            self.fsi.append((off, size, extra, kind, a, b, c))
        pos += fsi_size
        pallet = data[pos:pos + pallet_size]
        pos += pallet_size
        common = data[pos:pos + common_size]
        # per-column offsets into the pallet and common blocks, in column order
        self.pallet_at, self.common_at = [], []
        po = co = 0
        for off, size, extra, kind, a, b, c in self.fsi:
            self.pallet_at.append(po)
            self.common_at.append(co)
            if kind in (PALLET, PALLET_ARRAY):
                po += extra
            if kind == COMMON:
                co += extra
        self.pallet, self.common = pallet, common
        self.sections = []
        for key, file_off, rcount, ssize, rec_end, id_size, rel_size, map_count, copy_count in sections:
            if key != 0:
                raise DB2Error("encrypted section")
            rec_bytes = rcount * self.record_size
            rec = data[file_off:file_off + rec_bytes]
            strings = data[file_off + rec_bytes:file_off + rec_bytes + ssize]
            p = file_off + rec_bytes + ssize
            ids = struct.unpack_from("<%dI" % (id_size // 4), data, p) if id_size else ()
            p += id_size
            copies = [struct.unpack_from("<II", data, p + 8 * i) for i in range(copy_count)]
            p += 8 * copy_count + 6 * map_count
            # relationship block: the foreign key of a row (a column the file doesn't store in the record)
            rel = {}
            if rel_size:
                n = struct.unpack_from("<I", data, p)[0]
                for i in range(n):
                    foreign, index = struct.unpack_from("<II", data, p + 12 + 8 * i)
                    rel[index] = foreign
            self.sections.append((rcount, rec, strings, ids, copies, file_off + rec_bytes, rel))

    def _value(self, rec, base, col, row_id):
        off, size, extra, kind, a, b, c = self.fsi[col]
        bitpos = base * 8 + off
        if kind == NONE:
            if size > 32:                                  # an array column: whole 32-bit values
                return [_bits(rec, bitpos + 32 * i, 32) for i in range(size // 32)], size
            return (_bits(rec, bitpos, size) if size else 0), size
        if kind in (BITPACKED, SIGNED):
            v = _bits(rec, bitpos, b) if b else 0
            if kind == SIGNED and b and v >> (b - 1):
                v -= 1 << b
            return v, b
        if kind == COMMON:
            at = self.common_at[col]
            for i in range(extra // 8):
                rid, val = struct.unpack_from("<II", self.common, at + 8 * i)
                if rid == row_id:
                    return val, 0
            return a, 0
        if kind == PALLET:
            idx = _bits(rec, bitpos, b) if b else 0
            return struct.unpack_from("<I", self.pallet, self.pallet_at[col] + 4 * idx)[0], b
        if kind == PALLET_ARRAY:
            idx = _bits(rec, bitpos, b) if b else 0
            return list(struct.unpack_from("<%dI" % c, self.pallet, self.pallet_at[col] + 4 * c * idx)), b
        raise DB2Error("column storage %d" % kind)

    def relations(self, section=0):
        """{row index in the section: foreign key} (empty when the table has no relationship column)."""
        return self.sections[section][6]

    def rows(self):
        """(id, [column values]) for every row. A column is an int (raw bits: callers reinterpret floats with
        as_float), a list of ints for an array column, or a str for a string column named by `strings`."""
        seen = {}
        for rcount, rec, strings, ids, copies, _, _rel in self.sections:
            for r in range(rcount):
                base = r * self.record_size
                row_id = ids[r] if ids else None
                cols = []
                for col in range(len(self.fsi)):
                    v, _w = self._value(rec, base, col, row_id)
                    cols.append(v)
                if row_id is None:
                    row_id = cols[self.id_index]
                seen[row_id] = cols
                yield row_id, cols
            for new_id, old_id in copies:
                if old_id in seen:
                    yield new_id, seen[old_id]

    def raw(self, rec_index, section=0):
        rcount, rec, strings, ids, copies, _, _rel = self.sections[section]
        return rec[rec_index * self.record_size:(rec_index + 1) * self.record_size]

    def string_at(self, rec_index, col, section=0):
        """The string a string column of a row holds (the column holds an offset from its own position into the table)."""
        rcount, rec, strings, ids, copies, _, _rel = self.sections[section]
        off, size, extra, kind, a, b, c = self.fsi[col]
        base = rec_index * self.record_size
        v = _bits(rec, base * 8 + off, size) if size else 0
        field_addr = (base * 8 + off) // 8
        rel = field_addr + v - rcount * self.record_size      # from the start of the string table
        if rel < 0 or rel >= len(strings):
            return ""
        e = strings.find(b"\0", rel)
        return strings[rel:e].decode("utf-8", "replace")


def as_float(v):
    return struct.unpack("<f", struct.pack("<I", v & 0xFFFFFFFF))[0]
