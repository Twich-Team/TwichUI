"""Check a bake's connectivity between two world points, and where two unconnected areas come closest.

    python3 -I connect.py <tnm dir> <x1> <y1> <x2> <y2>

Polygon-level: neighbours inside a tile and links across tile edges, as pack.py makes them. For checking a bake,
not part of it.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack  # noqa: E402
import tnm   # noqa: E402


def inside(t, poly, x, y):
    pts = [t.world(*t.verts[v][:2]) for v in poly.verts]
    sign = 0
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
        cr = (bx - ax) * (y - ay) - (by - ay) * (x - ax)
        if cr > 1e-6:
            if sign < 0:
                return False
            sign = 1
        elif cr < -1e-6:
            if sign > 0:
                return False
            sign = -1
    return True


def main():
    d = sys.argv[1]
    x1, y1, x2, y2 = (float(v) for v in sys.argv[2:6])
    tiles = {}
    for name in os.listdir(d):
        if name.endswith(".tnm"):
            t = pack.Tile(tnm.load(os.path.join(d, name)))
            if t.polys:
                tiles[t.key] = t
    links = pack.link_tiles(tiles)
    parent = {}

    def find(k):
        parent.setdefault(k, k)
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    for key, t in tiles.items():
        for pi, nbs in enumerate(t.adj):
            for _, q in nbs:
                union((key, pi), (key, q))
    for key, pi, e, nb, opi, oe, *_ in links:
        union((key, pi), (nb, opi))

    def locate(x, y):
        tx = int((tnm.ORIGIN - y) // tnm.TILE)
        ty = int((tnm.ORIGIN - x) // tnm.TILE)
        t = tiles.get((tx, ty))
        if not t:
            return None
        hits = [pi for pi, p in enumerate(t.polys) if inside(t, p, x, y)]
        if not hits:
            return None
        hits.sort(key=lambda pi: min(t.verts[v][2] for v in t.polys[pi].verts))
        return (t.key, hits[0])
    a, b = locate(x1, y1), locate(x2, y2)
    print("start", a, "goal", b)
    if not a or not b:
        return
    ca, cb = find(a), find(b)
    print("connected" if ca == cb else "NOT connected")
    if ca == cb:
        return
    sizes = {}
    for k in list(parent):
        r = find(k)
        sizes[r] = sizes.get(r, 0) + 1
    print("component sizes: start", sizes.get(ca), "goal", sizes.get(cb))
    # closest vertices between the two components, near the goal
    def verts_of(comp, cx, cy, reach):
        out = []
        for key, t in tiles.items():
            if abs(t.m.wxmin + tnm.TILE / 2 - cx) > reach + tnm.TILE or abs(t.m.wymin + tnm.TILE / 2 - cy) > reach + tnm.TILE:
                continue
            for pi, p in enumerate(t.polys):
                if find((key, pi)) == comp:
                    for v in p.verts:
                        wx, wy = t.world(*t.verts[v][:2])
                        if abs(wx - cx) <= reach and abs(wy - cy) <= reach:
                            out.append((wx, wy, t.verts[v][2], key, pi))
        return out
    va = verts_of(ca, x2, y2, 400)
    vb = verts_of(cb, x2, y2, 400)
    best = None
    for p in va:
        for q in vb:
            dd = math.hypot(p[0] - q[0], p[1] - q[1])
            if best is None or dd < best[0]:
                best = (dd, p, q)
    if best:
        dd, p, q = best
        print("closest gap %.1f yd: start side (%.1f, %.1f, z %.1f) tile %s poly %d, goal side (%.1f, %.1f, z %.1f) tile %s poly %d"
              % (dd, p[0], p[1], p[2], p[3], p[4], q[0], q[1], q[2], q[3], q[4]))


if __name__ == "__main__":
    main()
