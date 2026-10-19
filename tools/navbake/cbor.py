"""A minimal CBOR (RFC 8949) encoder for the walking-map data: integers, floats, strings, lists, dicts.

The client decodes it with C_EncodingUtil.DeserializeCBOR, which gives Lua tables (lists as 1-based arrays).
Floats are written as 32-bit when that is exact enough for the data (callers round first) and 64-bit otherwise.
"""

import struct


def _head(major, n, out):
    if n < 24:
        out.append((major << 5) | n)
    elif n < 0x100:
        out += bytes(((major << 5) | 24, n))
    elif n < 0x10000:
        out.append((major << 5) | 25)
        out += struct.pack(">H", n)
    elif n < 0x100000000:
        out.append((major << 5) | 26)
        out += struct.pack(">I", n)
    else:
        out.append((major << 5) | 27)
        out += struct.pack(">Q", n)


def _enc(v, out):
    if v is True:
        out.append(0xF5)
    elif v is False:
        out.append(0xF4)
    elif v is None:
        out.append(0xF6)
    elif isinstance(v, int):
        if v >= 0:
            _head(0, v, out)
        else:
            _head(1, -1 - v, out)
    elif isinstance(v, float):
        f32 = struct.unpack(">f", struct.pack(">f", v))[0]
        if f32 == v:
            out.append(0xFA)
            out += struct.pack(">f", v)
        else:
            out.append(0xFB)
            out += struct.pack(">d", v)
    elif isinstance(v, str):
        b = v.encode("utf-8")
        _head(3, len(b), out)
        out += b
    elif isinstance(v, (list, tuple)):
        _head(4, len(v), out)
        for x in v:
            _enc(x, out)
    elif isinstance(v, dict):
        _head(5, len(v), out)
        for k, x in v.items():
            _enc(k, out)
            _enc(x, out)
    else:
        raise TypeError("cannot encode %r" % type(v))


def dumps(v):
    out = bytearray()
    _enc(v, out)
    return bytes(out)


def loads(data):
    """Decoder for the same subset, used by the bake's own checks and the offline tests."""
    pos = [0]

    def arg(info):
        p = pos[0]
        if info < 24:
            return info
        size = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        pos[0] += size
        return int.from_bytes(data[p:p + size], "big")

    def item():
        b = data[pos[0]]
        pos[0] += 1
        major, info = b >> 5, b & 31
        if major == 0:
            return arg(info)
        if major == 1:
            return -1 - arg(info)
        if major == 3:
            n = arg(info)
            s = data[pos[0]:pos[0] + n].decode("utf-8")
            pos[0] += n
            return s
        if major == 4:
            return [item() for _ in range(arg(info))]
        if major == 5:
            n = arg(info)
            out = {}
            for _ in range(n):
                k = item()
                out[k] = item()
            return out
        if major == 7:
            if info == 20:
                return False
            if info == 21:
                return True
            if info == 22:
                return None
            if info == 26:
                v = struct.unpack(">f", data[pos[0]:pos[0] + 4])[0]
                pos[0] += 4
                return v
            if info == 27:
                v = struct.unpack(">d", data[pos[0]:pos[0] + 8])[0]
                pos[0] += 8
                return v
        raise ValueError("unsupported CBOR item %#x" % b)

    return item()
