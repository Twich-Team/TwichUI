"""Read navbuild's per-tile polygon meshes (.tnm). See navbuild.cpp for the layout."""

import struct

TILE = 1600.0 / 3.0
ORIGIN = 32.0 * TILE
NULL = 0xFFFF


class Poly:
    __slots__ = ("verts", "neis", "area")

    def __init__(self, verts, neis, area):
        self.verts = verts
        self.neis = neis
        self.area = area


class TileMesh:
    def __init__(self, tx, ty, cs, ch, bmin, verts, polys):
        self.tx, self.ty = tx, ty
        self.cs, self.ch = cs, ch
        self.bmin = bmin
        self.verts = verts           # list of (vx, vy, vz) cells
        self.polys = polys
        self.wxmax = ORIGIN - ty * TILE
        self.wxmin = self.wxmax - TILE
        self.wymax = ORIGIN - tx * TILE
        self.wymin = self.wymax - TILE

    def world(self, vi):
        """World (x north, y west, z up) of vertex vi. Recast x is world y, Recast z is world x."""
        vx, vy, vz = self.verts[vi]
        return (self.bmin[2] + vz * self.cs, self.bmin[0] + vx * self.cs, self.bmin[1] + vy * self.ch)


def load(path):
    with open(path, "rb") as f:
        d = f.read()
    if d[:4] != b"TNM1":
        raise ValueError("not a tnm file: " + path)
    tx, ty = struct.unpack_from("<ii", d, 4)
    cs, ch, b0, b1, b2 = struct.unpack_from("<5f", d, 12)
    p = 32
    (nv,) = struct.unpack_from("<i", d, p)
    p += 4
    flat = struct.unpack_from("<%dH" % (nv * 3), d, p)
    p += 6 * nv
    verts = [flat[k:k + 3] for k in range(0, len(flat), 3)]
    np_, nvp = struct.unpack_from("<ii", d, p)
    p += 8
    polys = []
    for _ in range(np_):
        vals = struct.unpack_from("<%dH" % (nvp * 2), d, p)
        p += 4 * nvp
        area = d[p]
        p += 1
        vs = [v for v in vals[:nvp] if v != NULL]
        polys.append(Poly(vs, list(vals[nvp:nvp + len(vs)]), area))
    return TileMesh(tx, ty, cs, ch, (b0, b1, b2), verts, polys)
