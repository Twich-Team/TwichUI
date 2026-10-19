"""Read files from a local World of Warcraft CASC installation, by file data ID.

TwichUI's own reader (Python standard library only). It reads what the walking-map bake needs and nothing more:
the build's configuration, the local index files, the encoding table and the root table, then BLTE-encoded
files out of the data archives. It never writes to the installation, never contacts a CDN and never decrypts:
an encrypted file is reported as unavailable.

    storage = Storage("/path/to/World of Warcraft", product="wow_classic_beta")
    data = storage.read(775971)      # bytes, or None when the file is not stored locally
"""

import os
import struct
import zlib


class CascError(Exception):
    pass


class Encrypted(CascError):
    """A BLTE chunk is encrypted; this reader has no keys and never guesses."""


def _build_info(root, product):
    path = os.path.join(root, ".build.info")
    with open(path, "r", encoding="utf-8") as f:
        lines = [ln.rstrip("\r\n") for ln in f if ln.strip()]
    names = [h.split("!")[0] for h in lines[0].split("|")]
    for ln in lines[1:]:
        row = dict(zip(names, ln.split("|")))
        if row.get("Product") == product:
            return row
    raise CascError("product %r not in .build.info" % product)


def _config(root, key):
    path = os.path.join(root, "Data", "config", key[0:2], key[2:4], key)
    out = {}
    with open(path, "r", encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith("#") or "=" not in ln:
                continue
            k, v = ln.split("=", 1)
            out[k.strip()] = v.split()
    return out


def blte_decode(data, ekey=None):
    """Decode a BLTE stream (modes N, Z and F). Raises Encrypted on mode E."""
    if data[:4] != b"BLTE":
        raise CascError("not BLTE")
    header_size = struct.unpack(">I", data[4:8])[0]
    chunks = []
    if header_size == 0:
        chunks.append(data[8:])
    else:
        flags = data[8]
        count = int.from_bytes(data[9:12], "big")
        if flags != 0x0F:
            raise CascError("BLTE flags %#x" % flags)
        pos = 12
        sizes = []
        for _ in range(count):
            comp, _decomp = struct.unpack(">II", data[pos:pos + 8])
            sizes.append(comp)
            pos += 24
        pos = header_size
        for comp in sizes:
            chunks.append(data[pos:pos + comp])
            pos += comp
    out = []
    for c in chunks:
        mode = c[:1]
        if mode == b"N":
            out.append(c[1:])
        elif mode == b"Z":
            out.append(zlib.decompress(c[1:]))
        elif mode == b"F":
            out.append(blte_decode(c[1:]))
        elif mode == b"E":
            raise Encrypted(ekey.hex() if ekey else "encrypted")
        else:
            raise CascError("BLTE mode %r" % mode)
    return b"".join(out)


class Storage:
    def __init__(self, root, product="wow_classic_beta"):
        self.root = root
        self.data_dir = os.path.join(root, "Data", "data")
        info = _build_info(root, product)
        self.version = info.get("Version")
        build = _config(root, info["Build Key"])
        self._archives = {}
        self._index = {}
        self._load_indices()
        # build config: "encoding = <ckey> <ekey>", "root = <ckey>"
        enc_ekey = bytes.fromhex(build["encoding"][1])
        self._ckey_to_ekey = {}
        self._load_encoding(self._read_ekey(enc_ekey))
        root_ckey = bytes.fromhex(build["root"][0])
        self._fdid = {}
        self._load_root(self.read_ckey(root_ckey))

    # Local index: the first 9 bytes of an encoded key -> (archive, offset, size).
    def _load_indices(self):
        best = {}
        for name in os.listdir(self.data_dir):
            if not name.endswith(".idx") or len(name) != 14:
                continue
            bucket, version = int(name[0:2], 16), int(name[2:10], 16)
            if bucket not in best or version > best[bucket][0]:
                best[bucket] = (version, name)
        for _, name in best.values():
            with open(os.path.join(self.data_dir, name), "rb") as f:
                raw = f.read()
            (hsize,) = struct.unpack_from("<I", raw, 0)
            ver, _bucket, _extra, size_len, off_len, key_len, off_bits = struct.unpack_from("<HBBBBBB", raw, 8)
            if ver != 7:
                raise CascError("index version %d in %s" % (ver, name))
            pos = (8 + hsize + 15) & ~15
            (esize,) = struct.unpack_from("<I", raw, pos)
            pos += 8
            stride = key_len + off_len + size_len
            mask = (1 << off_bits) - 1
            end = pos + esize
            while pos + stride <= end:
                key = raw[pos:pos + key_len]
                loc = int.from_bytes(raw[pos + key_len:pos + key_len + off_len], "big")
                size = int.from_bytes(raw[pos + key_len + off_len:pos + stride], "little")
                if key not in self._index:
                    self._index[key] = (loc >> off_bits, loc & mask, size)
                pos += stride

    def _archive(self, n):
        f = self._archives.get(n)
        if f is None:
            f = open(os.path.join(self.data_dir, "data.%03d" % n), "rb")
            self._archives[n] = f
        return f

    def _read_ekey(self, ekey):
        loc = self._index.get(ekey[:9])
        if loc is None:
            return None
        archive, offset, size = loc
        f = self._archive(archive)
        f.seek(offset + 30)               # 30-byte local header before the BLTE stream
        return blte_decode(f.read(size - 30), ekey)

    def _load_encoding(self, raw):
        if raw is None or raw[:2] != b"EN":
            raise CascError("encoding file missing")
        ckey_len, ekey_len = raw[3], raw[4]
        ce_page_kb = struct.unpack(">H", raw[5:7])[0]
        ce_pages = struct.unpack(">I", raw[9:13])[0]
        espec_size = struct.unpack(">I", raw[18:22])[0]
        pos = 22 + espec_size + ce_pages * 32     # skip the ESpec strings and the page table
        page_size = ce_page_kb * 1024
        for _ in range(ce_pages):
            p, end = pos, pos + page_size
            while p < end:
                count = raw[p]
                if count == 0:
                    break
                ckey = raw[p + 6:p + 6 + ckey_len]
                ekey = raw[p + 6 + ckey_len:p + 6 + ckey_len + ekey_len]
                self._ckey_to_ekey[ckey] = ekey
                p += 6 + ckey_len + ekey_len * count
            pos = end

    def _load_root(self, raw):
        if raw is None:
            raise CascError("root file missing")
        if raw[:4] != b"TSFM":
            raise CascError("unsupported root (no TSFM)")
        hsize, version = struct.unpack_from("<II", raw, 4)
        if version not in (1, 2):
            raise CascError("root version %d" % version)
        pos = hsize
        n = len(raw)
        while pos < n:
            if version == 2:
                count, locale, f1, f2 = struct.unpack_from("<IIII", raw, pos)
                f3 = raw[pos + 16]
                content = f1 | f2 | (f3 << 17)
                pos += 17
            else:
                count, content, locale = struct.unpack_from("<III", raw, pos)
                pos += 12
            deltas = struct.unpack_from("<%di" % count, raw, pos)
            pos += 4 * count
            ckeys = pos
            pos += 16 * count
            if not (content & 0x10000000):    # no-name-hash flag: hashes are omitted
                pos += 8 * count
            # enUS (0x2) or locale-neutral blocks only; skip low-violence variants (0x80)
            if not (locale & 0x2) or (content & 0x80):
                continue
            fdid = -1
            for i in range(count):
                fdid += deltas[i] + 1
                if fdid not in self._fdid:
                    self._fdid[fdid] = raw[ckeys + 16 * i:ckeys + 16 * i + 16]

    def has(self, fdid):
        ck = self._fdid.get(fdid)
        if ck is None:
            return False
        ek = self._ckey_to_ekey.get(ck)
        return ek is not None and ek[:9] in self._index

    def read_ckey(self, ckey):
        ekey = self._ckey_to_ekey.get(ckey)
        if ekey is None:
            return None
        return self._read_ekey(ekey)

    def read(self, fdid):
        """The file's bytes, or None when it is not stored locally or is encrypted."""
        ck = self._fdid.get(fdid)
        if ck is None:
            return None
        try:
            return self.read_ckey(ck)
        except Encrypted:
            return None

    def close(self):
        for f in self._archives.values():
            f.close()
        self._archives.clear()
