"""Collision geometry from WoW map files: WDT tile lists, ADT terrain and liquid, M2 and WMO collision.

Every layout here was checked against this client's own files (build 1.60.1.70450) before it was used; see
README.md. Coordinates are returned in the world frame UnitPosition uses: x north, y west, z up, in yards.
"""

import math
import struct

TILE = 1600.0 / 3.0            # yards per ADT tile
CHUNK = TILE / 16.0            # yards per MCNK
UNIT = CHUNK / 8.0             # yards per terrain quad
ORIGIN = 32.0 * TILE

# Liquid kinds, from LiquidType.db2's 2-bit family field (0 water, 1 ocean, 2 magma, 3 slime). That field was
# identified by comparing it with every liquid's name in this client (README.md). Magma, slime, lava, fel and
# tar all fall in families 2 and 3 and are impassable here. A type missing from the table is treated as water
# and counted, so it shows in the bake log.
WATER, OCEAN, HAZARD = 1, 2, 3
LIQUID_TYPE_DB2 = 1371380
_FAMILY = {0: WATER, 1: OCEAN, 2: HAZARD, 3: HAZARD}
_LIQUID = {}
unknown_liquids = {}


def load_liquid_types(storage):
    """Fill the liquid table from the client's LiquidType.db2 (WDC5, one section, IDs in an ID list)."""
    d = storage.read(LIQUID_TYPE_DB2)
    if d is None or d[:4] != b"WDC5":
        raise RuntimeError("LiquidType.db2 unavailable or not WDC5")
    rc, fc, rs, sts = struct.unpack_from("<4I", d, 136)
    (flags,) = struct.unpack_from("<H", d, 172)
    fsis, _cds, _pds, nsec = struct.unpack_from("<4I", d, 188)
    p = 204
    sec = struct.unpack_from("<Q8I", d, p)
    p += 40 * nsec + 4 * fc
    fsi = [struct.unpack_from("<HHIIIII", d, p + 24 * i) for i in range(fsis // 24)]
    bit_off, bit_size, _, storage_type = fsi[3][0], fsi[3][1], fsi[3][2], fsi[3][3]
    if nsec != 1 or not flags & 0x4 or bit_size != 2 or storage_type != 1:
        raise RuntimeError("LiquidType.db2 layout changed; check the family field again")
    off, n = sec[1], sec[2]
    ids = struct.unpack_from("<%dI" % n, d, off + n * rs + sec[3])
    for r in range(n):
        rec = int.from_bytes(d[off + r * rs:off + (r + 1) * rs], "little")
        _LIQUID[ids[r]] = _FAMILY[(rec >> bit_off) & 3]
    return len(_LIQUID)


def liquid_kind(type_id):
    k = _LIQUID.get(type_id)
    if k is None:
        unknown_liquids[type_id] = unknown_liquids.get(type_id, 0) + 1
        return WATER
    return k


def wmo_liquid_kind(group_liquid, root_flags):
    """A WMO group's liquid: a LiquidType ID when the root's flag 0x4 is set; otherwise an old index whose
    family is (value - 1) & 3 (water, ocean, magma, slime)."""
    if root_flags & 0x4 or group_liquid >= 21:
        return liquid_kind(group_liquid)
    return _FAMILY[(max(group_liquid, 1) - 1) & 3]


def chunks(data, start=0, end=None, reverse=True):
    """(id, offset, size) for each chunk. ADT/WDT/WMO ids are stored reversed; M2's are not."""
    end = len(data) if end is None else end
    out = []
    p = start
    while p + 8 <= end:
        cid = data[p:p + 4]
        cid = (cid[::-1] if reverse else cid).decode("latin1")
        (size,) = struct.unpack_from("<I", data, p + 4)
        out.append((cid, p + 8, size))
        p += 8 + size
    return out


def first(chs, cid):
    for c in chs:
        if c[0] == cid:
            return c
    return None


# --- WDT --------------------------------------------------------------------------------------------------

def wdt_tiles(data):
    """{(x, y): (root_fdid, obj0_fdid)} for every tile the map has. x is the column (west to east)."""
    maid = first(chunks(data), "MAID")
    if maid is None:
        return {}
    out = {}
    for i in range(4096):
        e = struct.unpack_from("<8I", data, maid[1] + 32 * i)
        if e[0]:
            out[(i % 64, i // 64)] = (e[0], e[1])
    return out


def tile_bounds(tx, ty):
    """World (xmin, ymin, xmax, ymax) of an ADT tile."""
    xmax = ORIGIN - ty * TILE
    ymax = ORIGIN - tx * TILE
    return xmax - TILE, ymax - TILE, xmax, ymax


# --- Mesh accumulator ---------------------------------------------------------------------------------------

class Mesh:
    """Triangle soup with one area per triangle."""

    def __init__(self):
        self.verts = []        # flat x, y, z
        self.tris = []         # flat a, b, c
        self.areas = []

    def add(self, pts, tris, area):
        base = len(self.verts) // 3
        for p in pts:
            self.verts.extend(p)
        for a, b, c in tris:
            self.tris.extend((a + base, b + base, c + base))
            self.areas.append(area)

    def __len__(self):
        return len(self.areas)


# --- ADT terrain and liquid ---------------------------------------------------------------------------------

def _mh2o(root, mh, chunk_heights):
    """Liquid cells of an ADT: list of (kind, x0, y0, surface, depth) per 1x1 terrain-quad cell, plus the
    instances of hazard liquid. chunk_heights[(cx, cy)] gives terrain height at (row, col) quad corners."""
    base = mh[1]
    cells = []
    for ci in range(256):
        off_inst, layers, _attr = struct.unpack_from("<III", root, base + 12 * ci)
        if not layers or not off_inst:
            continue
        cx, cy = ci % 16, ci // 16
        for li in range(layers):
            p = base + off_inst + 24 * li
            ltype, lvf, hmin, hmax, xo, yo, w, h, off_bits, off_verts = struct.unpack_from("<HHffBBBBII", root, p)
            kind = liquid_kind(ltype)
            exists = None
            if off_bits:
                nbytes = (w * h + 7) // 8
                exists = root[base + off_bits:base + off_bits + nbytes]
            heights = None
            # Vertex formats 0, 1 and 3 begin with (w+1)*(h+1) float heights; 2 has none. A liquid object
            # (lvf >= 42) needs the client's tables to know its format, so its surface is taken as flat.
            if off_verts and lvf in (0, 1, 3):
                n = (w + 1) * (h + 1)
                heights = struct.unpack_from("<%df" % n, root, base + off_verts)
            for j in range(h):
                for i in range(w):
                    bit = j * w + i
                    if exists is not None and not (exists[bit >> 3] >> (bit & 7)) & 1:
                        continue
                    if heights:
                        s = max(heights[j * (w + 1) + i], heights[j * (w + 1) + i + 1],
                                heights[(j + 1) * (w + 1) + i], heights[(j + 1) * (w + 1) + i + 1])
                    else:
                        s = hmax
                    cells.append((kind, cx, cy, xo + i, yo + j, s))
    return cells


def adt_terrain(root, terrain, liquid_tris, volumes):
    """Adds an ADT's terrain triangles to `terrain`, deep liquid surfaces to `liquid_tris` and liquid volumes
    (convex quads with a height range and an area) to `volumes`. Returns the number of liquid cells."""
    chs = chunks(root)
    mcnks = [c for c in chs if c[0] == "MCNK"]
    corner = {}                                   # (cx, cy) -> (x0, y0, z0, heights, holes)
    for _, p, size in mcnks:
        flags, ix, iy = struct.unpack_from("<III", root, p)
        if flags & 0x10000:
            (holes,) = struct.unpack_from("<Q", root, p + 0x14)
        else:
            (low,) = struct.unpack_from("<H", root, p + 0x3C)
            holes = 0
            for b in range(16):                   # one low-res bit covers 2x2 quads
                if (low >> b) & 1:
                    r0, c0 = (b // 4) * 2, (b % 4) * 2
                    for dr in (0, 1):
                        for dc in (0, 1):
                            holes |= 1 << ((r0 + dr) * 8 + c0 + dc)
        x0, y0, z0 = struct.unpack_from("<3f", root, p + 0x68)
        sub = first(chunks(root, p + 128, p + size), "MCVT")
        if sub is None:
            continue
        hts = struct.unpack_from("<145f", root, sub[1])
        corner[(ix, iy)] = (x0, y0, z0, hts, holes)
        if terrain is None:
            continue

        # pts follow the MCVT order exactly (145 entries): outer row i at i*17, inner row i at i*17+9.
        pts = []
        for k in range(145):
            row, col = divmod(k, 17)
            if col < 9:
                pts.append((x0 - row * UNIT, y0 - col * UNIT, z0 + hts[k]))
            else:
                pts.append((x0 - (row + 0.5) * UNIT, y0 - (col - 9 + 0.5) * UNIT, z0 + hts[k]))
        tris = []
        for r in range(8):
            for c in range(8):
                if (holes >> (r * 8 + c)) & 1:
                    continue
                tl, tr = r * 17 + c, r * 17 + c + 1
                bl, br = (r + 1) * 17 + c, (r + 1) * 17 + c + 1
                m = r * 17 + 9 + c
                tris.extend(((tl, m, tr), (tr, m, br), (br, m, bl), (bl, m, tl)))
        terrain.add(pts, tris, 1)

    mh = first(chs, "MH2O")
    if mh is None:
        return 0
    cells = _mh2o(root, mh, corner)
    for kind, cx, cy, i, j, s in cells:
        ch = corner.get((cx, cy))
        if ch is None:
            continue
        x0, y0, z0, hts, _ = ch
        # terrain heights at the cell's corners (outer vertices)
        ground = min(z0 + hts[r * 17 + c] for r in (j, j + 1) for c in (i, i + 1))
        xa, xb = x0 - j * UNIT, x0 - (j + 1) * UNIT
        ya, yb = y0 - i * UNIT, y0 - (i + 1) * UNIT
        quad = ((xa, ya), (xa, yb), (xb, yb), (xb, ya))
        depth = s - ground
        if kind == HAZARD:
            volumes.append((quad, ground - 2.0, s + 1.0, 0))
            continue
        area = 2 if kind == WATER else 3
        if depth >= 1.5:
            # deep enough to swim: the surface is walkable (as swimming) and the floor under it costs the same
            liquid_tris.add([(xa, ya, s), (xa, yb, s), (xb, yb, s), (xb, ya, s)], ((0, 1, 2), (0, 2, 3)), area)
            volumes.append((quad, ground - 2.0, s - 1.5, area))
    return len(cells)


def adt_placements(obj):
    """(doodads, wmos) placed by an ADT's obj0 file, each a dict with fdid, uid, pos, rot, scale (and for a WMO
    its doodad set). Placements that name a file by string (not this client's format) are skipped."""
    chs = chunks(obj)
    doodads, wmos = [], []
    c = first(chs, "MDDF")
    if c:
        for i in range(c[2] // 36):
            nid, uid, px, py, pz, rx, ry, rz, scale, flags = struct.unpack_from("<II6fHH", obj, c[1] + 36 * i)
            if not flags & 0x40:
                continue
            doodads.append({"fdid": nid, "uid": uid, "pos": (px, py, pz), "rot": (rx, ry, rz),
                            "scale": scale / 1024.0})
    c = first(chs, "MODF")
    if c:
        for i in range(c[2] // 64):
            v = struct.unpack_from("<II3f3f6fHHHH", obj, c[1] + 64 * i)
            nid, uid = v[0], v[1]
            flags, dset, scale = v[14], v[15], v[17]
            if not flags & 0x8:
                continue
            wmos.append({"fdid": nid, "uid": uid, "pos": v[2:5], "rot": v[5:8],
                         "scale": (scale / 1024.0) if (flags & 0x4) and scale else 1.0, "set": dset,
                         "ext": v[8:14]})
    return doodads, wmos


# --- Placement transform ------------------------------------------------------------------------------------

def _rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "x":
        return ((1, 0, 0), (0, c, -s), (0, s, c))
    if axis == "y":
        return ((c, 0, s), (0, 1, 0), (-s, 0, c))
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))


def _mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def placement_matrix(pos, rot, scale):
    """3x3 matrix and offset taking model coordinates to world coordinates. Checked against MODF's own world
    extents: Rz(ry + 180) . Ry(rx) . Rx(rz), placed at (ORIGIN - pz, ORIGIN - px, py)."""
    rx, ry, rz = rot
    m = _mul(_mul(_rot("z", ry + 180.0), _rot("y", rx)), _rot("x", rz))
    m = tuple(tuple(v * scale for v in row) for row in m)
    px, py, pz = pos
    return m, (ORIGIN - pz, ORIGIN - px, py)


def transform(points, m, off):
    (a, b, c), (d, e, f), (g, h, i) = m
    ox, oy, oz = off
    return [(a * x + b * y + c * z + ox, d * x + e * y + f * z + oy, g * x + h * y + i * z + oz)
            for x, y, z in points]


# --- M2 collision -------------------------------------------------------------------------------------------

def m2_collision(data):
    """(points, triangles) of an M2's collision mesh (empty when it has none)."""
    if data is None:
        return [], []
    md = first(chunks(data, reverse=False), "MD21")
    base = md[1] if md else 0
    if data[base:base + 4] != b"MD20":
        return [], []
    ti_n, ti_o, cv_n, cv_o = struct.unpack_from("<IIII", data, base + 0xD8)
    if not ti_n or not cv_n:
        return [], []
    idx = struct.unpack_from("<%dH" % ti_n, data, base + ti_o)
    flat = struct.unpack_from("<%df" % (cv_n * 3), data, base + cv_o)
    pts = [flat[k:k + 3] for k in range(0, len(flat), 3)]
    tris = [(idx[k], idx[k + 1], idx[k + 2]) for k in range(0, ti_n - 2, 3)
            if max(idx[k], idx[k + 1], idx[k + 2]) < cv_n]
    return pts, tris


# --- WMO collision ------------------------------------------------------------------------------------------

def _collides(flags):
    # MOPY/MPY2 material flags: 0x04 detail, 0x08 collision, 0x20 render. A rendered face that is not detail
    # collides, and so does a collision-only face.
    return bool(flags & 0x08) or (bool(flags & 0x20) and not flags & 0x04)


def wmo_root(data):
    """(group fdids, root flags) of a WMO root file."""
    chs = chunks(data)
    mohd = first(chs, "MOHD")
    ngroups = struct.unpack_from("<I", data, mohd[1] + 4)[0]
    (rflags,) = struct.unpack_from("<H", data, mohd[1] + 60)
    gfid = first(chs, "GFID")
    if gfid is None:
        return [], rflags
    ids = struct.unpack_from("<%dI" % (gfid[2] // 4), data, gfid[1])
    return list(ids[:ngroups]), rflags


def wmo_group(data, root_flags):
    """(points, collision triangles, liquids) of one WMO group. liquids: list of (kind, quads) in model space,
    where each quad is (corner points, surface)."""
    chs = chunks(data)
    mogp = first(chs, "MOGP")
    if mogp is None:
        return [], [], []
    p, size = mogp[1], mogp[2]
    (group_liquid,) = struct.unpack_from("<I", data, p + 0x34)
    sub = {c[0]: c for c in chunks(data, p + 0x44, p + size)}
    if "MOVT" not in sub:
        return [], [], []
    c = sub["MOVT"]
    flat = struct.unpack_from("<%df" % (c[2] // 4), data, c[1])
    pts = [flat[k:k + 3] for k in range(0, len(flat) - 2, 3)]
    if "MOVX" in sub:
        c = sub["MOVX"]
        idx = struct.unpack_from("<%dI" % (c[2] // 4), data, c[1])
    elif "MOVI" in sub:
        c = sub["MOVI"]
        idx = struct.unpack_from("<%dH" % (c[2] // 2), data, c[1])
    else:
        idx = ()
    ntri = len(idx) // 3
    if "MPY2" in sub:
        c = sub["MPY2"]
        flags = [struct.unpack_from("<H", data, c[1] + 4 * i)[0] for i in range(c[2] // 4)]
    elif "MOPY" in sub:
        c = sub["MOPY"]
        flags = [data[c[1] + 2 * i] for i in range(c[2] // 2)]
    else:
        flags = [0x08] * ntri
    n = len(pts)
    tris = []
    for t in range(min(ntri, len(flags))):
        if not _collides(flags[t]):
            continue
        a, b, cc = idx[3 * t], idx[3 * t + 1], idx[3 * t + 2]
        if a < n and b < n and cc < n:
            tris.append((a, b, cc))

    liquids = []
    c = sub.get("MLIQ")
    if c is not None and c[2] >= 30:
        q = c[1]
        xv, yv, xt, yt = struct.unpack_from("<iiii", data, q)
        cx, cy, cz = struct.unpack_from("<3f", data, q + 16)
        (mat,) = struct.unpack_from("<H", data, q + 28)
        vstart = q + 30
        tstart = vstart + 8 * xv * yv
        if xv > 0 and yv > 0 and tstart + xt * yt <= q + c[2]:
            hts = [struct.unpack_from("<f", data, vstart + 8 * k + 4)[0] for k in range(xv * yv)]
            kind = wmo_liquid_kind(group_liquid or 1, root_flags)
            quads = []
            for j in range(yt):
                for i in range(xt):
                    tf = data[tstart + j * xt + i]
                    if (tf & 0x0F) == 0x0F:
                        continue
                    s = max(hts[j * xv + i], hts[j * xv + i + 1], hts[(j + 1) * xv + i], hts[(j + 1) * xv + i + 1])
                    x0, y0 = cx + i * UNIT, cy + j * UNIT
                    quads.append((((x0, y0), (x0 + UNIT, y0), (x0 + UNIT, y0 + UNIT), (x0, y0 + UNIT)), s))
            if quads:
                liquids.append((kind, quads))
    return pts, tris, liquids
