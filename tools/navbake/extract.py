"""Extract one map's collision geometry from the local client into per-tile build inputs for navbuild.

    python3 -I extract.py --wow "/path/to/World of Warcraft" --map 0 --out ~/.cache/twichui-navbake
    python3 -I extract.py ... --tiles 32_48,31_48        # only these tiles

Each tile's file (<out>/<map>/<x>_<y>.tin) holds:
  - its terrain, as each MCNK's corner, hole mask and 145 heights (navbuild triangulates it);
  - every collision triangle of a doodad or WMO, and every deep-liquid surface, that reaches within BORDER
    yards of the tile;
  - liquid volumes (convex quads with a height range) that mark swimming or impassable liquid.
Nothing is written into the client's folder.
"""

import argparse
import array
import math
import os
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import casc            # noqa: E402
import wowfiles as wf  # noqa: E402

BORDER = 12.0            # yards of neighbouring geometry each tile carries (navbuild's border is smaller)
MAPS = {0: 775971, 1: 782779}
# Doodads (M2s) block only when they are barrier-shaped: at their base (BASE yards up from their lowest point)
# at least BARRIER_LENGTH long and at most a third as wide, like a fence or a palisade. Every other doodad, a
# tree, a boulder or a lamp post, gives only its walkable surfaces (a bridge deck, a dock, a platform). A player
# steers round a tree without help, and each one would cost the walking map a ring of polygons: in Elwynn,
# Forever's tree collision hulls are 15-30 yards across at the base.
BASE = 3.0
BARRIER_LENGTH = 6.0
WALKABLE_COS = 0.64          # cos(50 degrees), navbuild's MAX_SLOPE


def is_barrier(pts):
    zmin = min(p[2] for p in pts)
    low = [p for p in pts if p[2] <= zmin + BASE]
    best = None
    for k in range(8):                       # the narrowest of eight orientations is close enough
        a = math.pi * k / 8
        c, s = math.cos(a), math.sin(a)
        u = [p[0] * c + p[1] * s for p in low]
        v = [-p[0] * s + p[1] * c for p in low]
        du, dv = max(u) - min(u), max(v) - min(v)
        length, width = max(du, dv), min(du, dv)
        if best is None or width < best[1]:
            best = (length, width)
    return best[0] >= BARRIER_LENGTH and best[1] * 3 <= best[0]


def faces_up(pts, tri):
    a, b, c = pts[tri[0]], pts[tri[1]], pts[tri[2]]
    e0 = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    e1 = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    nx = e0[1] * e1[2] - e0[2] * e1[1]
    ny = e0[2] * e1[0] - e0[0] * e1[2]
    nz = e0[0] * e1[1] - e0[1] * e1[0]
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    return length > 0 and abs(nz) / length > WALKABLE_COS

AREA_GROUND, AREA_WATER, AREA_OCEAN = 1, 2, 3


def write_tile(path, chunks, objects, volumes):
    out = bytearray(b"TIN1")
    out += struct.pack("<I", len(chunks))
    for x0, y0, z0, holes, hts in chunks:
        out += struct.pack("<3fQ", x0, y0, z0, holes)
        out += array.array("f", hts).tobytes()
    out += struct.pack("<I", len(objects.verts) // 3)
    out += array.array("f", objects.verts).tobytes()
    out += struct.pack("<I", len(objects.areas))
    out += array.array("I", objects.tris).tobytes()
    out += bytes(objects.areas)
    out += struct.pack("<I", len(volumes))
    for quad, hmin, hmax, area in volumes:
        for x, y in quad:
            out += struct.pack("<2f", x, y)
        out += struct.pack("<2fB", hmin, hmax, area)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, path)


def terrain_chunks(root):
    """(x0, y0, z0, holes, heights) per MCNK, in the form navbuild reads."""
    out = []
    for cid, p, size in wf.chunks(root):
        if cid != "MCNK":
            continue
        flags = struct.unpack_from("<I", root, p)[0]
        if flags & 0x10000:
            (holes,) = struct.unpack_from("<Q", root, p + 0x14)
        else:
            (low,) = struct.unpack_from("<H", root, p + 0x3C)
            holes = 0
            for b in range(16):
                if (low >> b) & 1:
                    r0, c0 = (b // 4) * 2, (b % 4) * 2
                    for dr in (0, 1):
                        for dc in (0, 1):
                            holes |= 1 << ((r0 + dr) * 8 + c0 + dc)
        x0, y0, z0 = struct.unpack_from("<3f", root, p + 0x68)
        sub = wf.first(wf.chunks(root, p + 128, p + size), "MCVT")
        if sub is None:
            continue
        out.append((x0, y0, z0, holes, struct.unpack_from("<145f", root, sub[1])))
    return out


class Models:
    """Model-space collision of M2s and WMOs, read once per file."""

    def __init__(self, storage):
        self.s = storage
        self.m2 = {}
        self.wmo = {}
        self.missing = set()

    def get_m2(self, fdid):
        v = self.m2.get(fdid)
        if v is None:
            data = self.s.read(fdid)
            if data is None:
                self.missing.add(fdid)
            v = wf.m2_collision(data)
            self.m2[fdid] = v
        return v

    def get_wmo(self, fdid):
        v = self.wmo.get(fdid)
        if v is None:
            v = []
            data = self.s.read(fdid)
            if data is None:
                self.missing.add(fdid)
            else:
                groups, rflags = wf.wmo_root(data)
                for g in groups:
                    gd = self.s.read(g)
                    if gd is None:
                        self.missing.add(g)
                        continue
                    v.append(wf.wmo_group(gd, rflags))
            self.wmo[fdid] = v
        return v


def placed_object(models, kind, plc):
    """World-space (points, tris, areas, volumes, bbox) of one placement."""
    m, off = wf.placement_matrix(plc["pos"], plc["rot"], plc["scale"])
    pts, tris, areas, volumes = [], [], [], []
    if kind == "m2":
        mp, mt = models.get_m2(plc["fdid"])
        if mt:
            pts = wf.transform(mp, m, off)
            if is_barrier(pts):
                tris = list(mt)
            else:
                tris = [t for t in mt if faces_up(pts, t)]
                if not tris:
                    return None
            areas = [AREA_GROUND] * len(tris)
    else:
        for gp, gt, liquids in models.get_wmo(plc["fdid"]):
            base = len(pts)
            if gt:
                pts.extend(wf.transform(gp, m, off))
                tris.extend((a + base, b + base, c + base) for a, b, c in gt)
                areas.extend([AREA_GROUND] * len(gt))
            for lkind, quads in liquids:
                for corners, s in quads:
                    w = wf.transform([(x, y, s) for x, y in corners], m, off)
                    if lkind == wf.HAZARD:
                        volumes.append(([(p[0], p[1]) for p in w], w[0][2] - 4.0, w[0][2] + 1.0, 0))
                        continue
                    area = AREA_WATER if lkind == wf.WATER else AREA_OCEAN
                    b = len(pts)
                    pts.extend(w)
                    tris.extend(((b, b + 1, b + 2), (b, b + 2, b + 3)))
                    areas.extend((area, area))
                    # inside a WMO the floor under a canal is at most a few yards down; don't reach further
                    volumes.append(([(p[0], p[1]) for p in w], w[0][2] - 12.0, w[0][2] - 1.5, area))
    if not pts:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return pts, tris, areas, volumes, (min(xs), min(ys), max(xs), max(ys))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wow", required=True)
    ap.add_argument("--product", default="wow_classic_beta")
    ap.add_argument("--map", type=int, required=True)
    ap.add_argument("--wdt", type=int, help="WDT file data ID (default: known continents)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--tiles", help="comma-separated x_y list")
    args = ap.parse_args()

    t0 = time.time()
    s = casc.Storage(args.wow, args.product)
    print("client", s.version, "liquid types", wf.load_liquid_types(s))
    wdt_id = args.wdt or MAPS.get(args.map)
    if not wdt_id:
        sys.exit("unknown map; pass --wdt")
    tiles = wf.wdt_tiles(s.read(wdt_id))
    want = set(tiles)
    if args.tiles:
        want = {tuple(int(v) for v in t.split("_")) for t in args.tiles.split(",")}
    outdir = os.path.join(os.path.expanduser(args.out), str(args.map))
    os.makedirs(outdir, exist_ok=True)

    # Every placement that could reach a wanted tile is listed by that tile or a neighbour; read those obj0s.
    need = set()
    for (x, y) in want:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) in tiles:
                    need.add((x + dx, y + dy))
    placements = {}          # uid -> (kind, placement)
    for key in sorted(need):
        obj = s.read(tiles[key][1])
        if obj is None:
            continue
        doodads, wmos = wf.adt_placements(obj)
        for d in doodads:
            placements.setdefault(("m2", d["uid"]), ("m2", d))
        for w in wmos:
            placements.setdefault(("wmo", w["uid"]), ("wmo", w))
    print("placements", len(placements), "from", len(need), "tiles")

    models = Models(s)
    placed = []
    for kind, plc in placements.values():
        v = placed_object(models, kind, plc)
        if v:
            placed.append(v)
    print("placed objects", len(placed), "missing files", len(models.missing), "%.0fs" % (time.time() - t0))

    done = 0
    for key in sorted(want):
        if key not in tiles:
            continue
        root = s.read(tiles[key][0])
        if root is None:
            print("tile", key, "not stored locally")
            continue
        xmin, ymin, xmax, ymax = wf.tile_bounds(*key)
        bx0, by0, bx1, by1 = xmin - BORDER, ymin - BORDER, xmax + BORDER, ymax + BORDER

        chunks = terrain_chunks(root)
        objects = wf.Mesh()
        volumes = []
        liquid = wf.Mesh()
        wf.adt_terrain(root, None, liquid, volumes)
        if len(liquid):
            objects.add([liquid.verts[k:k + 3] for k in range(0, len(liquid.verts), 3)],
                        [liquid.tris[k:k + 3] for k in range(0, len(liquid.tris), 3)], 0)
            objects.areas[-len(liquid):] = liquid.areas
        for pts, tris, areas, vols, bb in placed:
            if bb[2] < bx0 or bb[0] > bx1 or bb[3] < by0 or bb[1] > by1:
                continue
            base = len(objects.verts) // 3
            keep = []
            for (a, b, c), ar in zip(tris, areas):
                pa, pb, pc = pts[a], pts[b], pts[c]
                if max(pa[0], pb[0], pc[0]) < bx0 or min(pa[0], pb[0], pc[0]) > bx1:
                    continue
                if max(pa[1], pb[1], pc[1]) < by0 or min(pa[1], pb[1], pc[1]) > by1:
                    continue
                keep.append((a, b, c, ar))
            remap = {}
            for a, b, c, ar in keep:
                for v in (a, b, c):
                    if v not in remap:
                        remap[v] = base + len(remap)
                        objects.verts.extend(pts[v])
                objects.tris.extend((remap[a], remap[b], remap[c]))
                objects.areas.append(ar)
            for quad, hmin, hmax, ar in vols:
                if any(bx0 <= x <= bx1 and by0 <= y <= by1 for x, y in quad):
                    volumes.append((quad, hmin, hmax, ar))
        write_tile(os.path.join(outdir, "%d_%d.tin" % key), chunks, objects, volumes)
        done += 1
        if done % 25 == 0:
            print("tiles", done, "/", len(want), "%.0fs" % (time.time() - t0))
    if wf.unknown_liquids:
        print("liquid types not in the table (treated as water):", dict(sorted(wf.unknown_liquids.items())))
    print("done", done, "tiles in %.0fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
