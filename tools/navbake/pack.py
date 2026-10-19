"""Pack navbuild's tile meshes into TwichUI_NavData: per-tile walking maps and each map's crossing graph.

    python3 -I pack.py --tnm ~/.cache/twichui-navbake/0nm --map 0 --out ../../TwichUI_NavData --client 1.60.1.70450

What it writes (Lua files of Base64 strings, zlib-compressed CBOR, decoded in game by C_EncodingUtil; see
TwichUI_NavData/README.md for the format):
  Data/Map<m>.lua        the map's graph: crossings between tiles, their costs, components, the tile list
  Data/Map<m>_<n>.lua    the map's tiles, in parts of at most PART_BYTES
It also prints the costs model and sizes, and checks every record decodes back to what was packed.

Costs (the same model nav/Route.lua uses in game): moving through a polygon costs its 2D distance in yards
times its area's factor (ground 1, water SWIM, ocean SEA), measured between portal midpoints, as Detour does.
"""

import argparse
import base64
import heapq
import math
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cbor  # noqa: E402
import tnm   # noqa: E402

FORMAT = 1
FACTOR = {1: 1.0, 2: 3.0, 3: 5.0}       # ground, water (swimming), ocean
LINK_DZ = 3.0                           # yards: two border edges further apart in height are different floors
RUN_GAP = 1                             # cells: links closer than this along a side make one run
RUN_SPLIT = 128.0                       # yards: a longer run is split, one crossing per piece
PART_BYTES = 2_000_000
# Which data files each map was packed into, for the .toc and for removing parts a map no longer has: kept with the
# tool (the packager leaves tools/ out), not in the addon.
MANIFESTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "manifest")
MIN_POCKET = 5000.0                     # square yards: isolated pockets smaller than this are left out (see prune)
# Directions in the packed data: 1 east (tx + 1), 2 north (ty - 1), 3 west (tx - 1), 4 south (ty + 1).
# Recast's edge directions: 0 x == 0 (world y min: east), 1 z == max (north), 2 x == max (west), 3 z == 0 (south).
RC_TO_DIR = {0: 1, 1: 2, 2: 3, 3: 4}
DIR_STEP = {1: (1, 0), 2: (0, -1), 3: (-1, 0), 4: (0, 1)}
OPPOSITE = {1: 3, 2: 4, 3: 1, 4: 2}


class Tile:
    def __init__(self, mesh):
        self.m = mesh
        self.key = (mesh.tx, mesh.ty)
        self.cells = round(tnm.TILE / mesh.cs)
        # local (u north, w west, z yards)
        self.verts = [(vz, vx, mesh.bmin[1] + vy * mesh.ch) for vx, vy, vz in mesh.verts]
        self.polys = mesh.polys
        self.adj = [[] for _ in self.polys]     # (edge index, neighbour poly) inside the tile
        for pi, p in enumerate(self.polys):
            for e, n in enumerate(p.neis):
                if n != tnm.NULL and not n & 0x8000:
                    self.adj[pi].append((e, n))
        self.links = []                         # (poly, edge, dir, nb poly, nb edge)

    def world(self, u, w):
        return self.m.wxmin + u * self.m.cs, self.m.wymin + w * self.m.cs

    def edge(self, pi, e):
        p = self.polys[pi]
        return self.verts[p.verts[e]], self.verts[p.verts[(e + 1) % len(p.verts)]]

    def portal_mid(self, pi, e):
        a, b = self.edge(pi, e)
        return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


def side_of(tile, pi, e, rc_dir):
    """(dir, along-coordinate interval, height at each end) of a border edge."""
    a, b = tile.edge(pi, e)
    d = RC_TO_DIR[rc_dir]
    if d in (1, 3):          # east or west side: along u
        return d, (a[0], a[2]), (b[0], b[2])
    return d, (a[1], a[2]), (b[1], b[2])


def link_tiles(tiles):
    """Match border edges of adjacent tiles. Returns a list of (tileA, polyA, edgeA, tileB, polyB, edgeB, s0, s1, z)."""
    by_side = {}
    for t in tiles.values():
        for pi, p in enumerate(t.polys):
            for e, n in enumerate(p.neis):
                if n != tnm.NULL and n & 0x8000:
                    d, pa, pb = side_of(t, pi, e, n & 0x7FFF)
                    lo, hi = (pa, pb) if pa[0] <= pb[0] else (pb, pa)
                    if hi[0] - lo[0] <= 0:
                        continue
                    by_side.setdefault((t.key, d), []).append((lo, hi, pi, e))
    links = []
    for (key, d), edges in by_side.items():
        if d not in (1, 2):              # each pair once: from the west/south tile's east/north side
            continue
        dx, dy = DIR_STEP[d]
        nb = (key[0] + dx, key[1] + dy)
        other = by_side.get((nb, OPPOSITE[d]))
        if not other:
            continue
        other = sorted(other)
        for lo, hi, pi, e in edges:
            for olo, ohi, opi, oe in other:
                if olo[0] >= hi[0]:
                    break
                s0, s1 = max(lo[0], olo[0]), min(hi[0], ohi[0])
                if s1 - s0 < 0.25:
                    continue
                mid = (s0 + s1) / 2

                def z_at(l, h):
                    t = (mid - l[0]) / (h[0] - l[0]) if h[0] != l[0] else 0.5
                    return l[1] + (h[1] - l[1]) * t
                za, zb = z_at(lo, hi), z_at(olo, ohi)
                if abs(za - zb) > LINK_DZ:
                    continue
                links.append((key, pi, e, nb, opi, oe, d, s0, s1, (za + zb) / 2))
    return links


def inner_components(t):
    """Each polygon's connected area inside its own tile (neighbours across shared edges), numbered from 0. Cached."""
    if getattr(t, "inner", None) is None:
        comp = [-1] * len(t.polys)
        n = 0
        for start in range(len(t.polys)):
            if comp[start] >= 0:
                continue
            comp[start] = n
            stack = [start]
            while stack:
                p = stack.pop()
                for _, q in t.adj[p]:
                    if comp[q] < 0:
                        comp[q] = n
                        stack.append(q)
            n += 1
        t.inner = comp
    return t.inner


def crossings(tiles, links):
    """Group links into crossings. Returns list of dicts and fills each tile's link list.
    A run of linked edges along a tile side is one crossing (or one per RUN_SPLIT yards), represented by one polygon on each
    side. A run whose links touch polygons that are not connected to each other inside their tile (a pier's planks and the
    shore, side by side along the border) must not share one: only one of them would get a crossing, and the other would be
    cut off from the crossing graph while its polygons are in fact connected. So a run is first split by the pair of
    connected areas its links join."""
    for key, pi, e, nb, opi, oe, d, s0, s1, z in links:
        tiles[key].links.append((pi, e, d, opi, oe))
        tiles[nb].links.append((opi, oe, OPPOSITE[d], pi, e))
    groups = {}
    for ln in links:
        groups.setdefault((ln[0], ln[3], ln[6]), []).append(ln)
    out = []
    for (key, nb, d), lns in sorted(groups.items()):
        lns.sort(key=lambda ln: ln[7])
        runs, cur = [], [lns[0]]
        for ln in lns[1:]:
            prev = cur[-1]
            if ln[7] - prev[8] <= RUN_GAP and abs(ln[9] - prev[9]) <= LINK_DZ:
                cur.append(ln)
            else:
                runs.append(cur)
                cur = [ln]
        runs.append(cur)
        t = tiles[key]
        cs = t.m.cs
        ca, cb = inner_components(t), inner_components(tiles[nb])
        split = []
        for run in runs:
            by = {}
            for ln in run:
                by.setdefault((ca[ln[1]], cb[ln[4]]), []).append(ln)
            split.extend(by[k] for k in sorted(by))
        for run in split:
            s_lo, s_hi = run[0][7], max(ln[8] for ln in run)
            pieces = max(1, math.ceil((s_hi - s_lo) * cs / RUN_SPLIT))
            for k in range(pieces):
                target = s_lo + (k + 0.5) * (s_hi - s_lo) / pieces
                best = min(run, key=lambda ln: 0 if ln[7] <= target <= ln[8] else min(abs(ln[7] - target), abs(ln[8] - target)))
                s = min(max(target, best[7]), best[8])
                # the crossing's point, in tile A's local cells, on the shared side
                if d == 1:       # A's east side: w == 0, along u
                    u, w = s, 0
                else:            # A's north side: u == cells, along w
                    u, w = t.cells, s
                wx, wy = t.world(u, w)
                out.append({"a": key, "pa": best[1], "b": nb, "pb": best[4], "x": wx, "y": wy, "z": best[9],
                            "ua": (u, w)})
    return out


def dijkstra(tile, start_poly, start_pos, targets):
    """Costs from a point in start_poly to each (poly, (u, w)) target, over the tile's polygons. Portal-midpoint
    model; positions in cells, costs in yards."""
    cs = tile.m.cs
    dist = {start_poly: 0.0}
    pos = {start_poly: start_pos}
    heap = [(0.0, start_poly)]
    done = set()
    while heap:
        d, p = heapq.heappop(heap)
        if p in done:
            continue
        done.add(p)
        f = FACTOR.get(tile.polys[p].area, 1.0)
        pu, pw = pos[p]
        for e, q in tile.adj[p]:
            if q in done:
                continue
            mu, mw = tile.portal_mid(p, e)
            nd = d + math.hypot(mu - pu, mw - pw) * cs * f
            if nd < dist.get(q, math.inf):
                dist[q] = nd
                pos[q] = (mu, mw)
                heapq.heappush(heap, (nd, q))
    out = []
    for poly, (tu, tw) in targets:
        if poly in dist:
            pu, pw = pos[poly]
            f = FACTOR.get(tile.polys[poly].area, 1.0)
            out.append(dist[poly] + math.hypot(tu - pu, tw - pw) * cs * f)
        else:
            out.append(None)
    return out


def local_point(tile, c, side):
    """Crossing c's point in `side` tile's local cells."""
    t = tile
    u = (c["x"] - t.m.wxmin) / t.m.cs
    w = (c["y"] - t.m.wymin) / t.m.cs
    return (u, w)


def encode(obj):
    raw = cbor.dumps(obj)
    packed = zlib.compress(raw, 9)
    assert cbor.loads(zlib.decompress(packed)) == obj, "round trip"
    return base64.b64encode(packed).decode("ascii"), len(raw)


def components(tiles, links):
    """Polygon-level connected components: neighbours inside a tile and links across tile edges. Returns
    ({(tile, poly): id}, [area in square yards by id - 1]), ids numbered in tile order."""
    parent = {}

    def find(k):
        parent.setdefault(k, k)
        root = k
        while parent[root] != root:
            root = parent[root]
        while parent[k] != root:
            parent[k], k = root, parent[k]
        return root

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    for key, t in tiles.items():
        for pi in range(len(t.polys)):
            find((key, pi))
            for _, q in t.adj[pi]:
                union((key, pi), (key, q))
    for ln in links:
        union((ln[0], ln[1]), (ln[3], ln[4]))
    comp_ids, area, ground = {}, [], []
    poly_comp = {}
    for key in sorted(tiles):
        t = tiles[key]
        for pi, poly in enumerate(t.polys):
            r = find((key, pi))
            cid = comp_ids.get(r)
            if cid is None:
                cid = len(comp_ids) + 1
                comp_ids[r] = cid
                area.append(0.0)
                ground.append(0.0)
            poly_comp[(key, pi)] = cid
            pts = [t.verts[v] for v in poly.verts]
            a2 = 0.0
            for i in range(len(pts)):
                (u1, w1, _), (u2, w2, _) = pts[i], pts[(i + 1) % len(pts)]
                a2 += u1 * w2 - u2 * w1
            sq = abs(a2) / 2 * t.m.cs * t.m.cs
            area[cid - 1] += sq
            if poly.area == 1:
                ground[cid - 1] += sq
    components.ground = ground      # the same components' ground (not water) area, for the last call
    return poly_comp, area


def prune(tiles, poly_comp, area, min_area):
    """The tiles without every polygon whose component is smaller than min_area square yards: pockets nothing can walk
    into or out of (a roof, sealed ground under a city, a ledge). Unused vertices go too; a tile left empty goes."""
    out = {}
    for key, t in tiles.items():
        keep = [pi for pi in range(len(t.polys)) if area[poly_comp[(key, pi)] - 1] >= min_area]
        if not keep:
            continue
        pmap = {old: new for new, old in enumerate(keep)}
        vmap, verts, polys = {}, [], []
        for old in keep:
            p = t.polys[old]
            vs = []
            for v in p.verts:
                if v not in vmap:
                    vmap[v] = len(verts)
                    verts.append(t.m.verts[v])
                vs.append(vmap[v])
            neis = [pmap.get(n, tnm.NULL) if (n != tnm.NULL and not n & 0x8000) else n for n in p.neis]
            polys.append(tnm.Poly(vs, neis, p.area))
        m = t.m
        out[key] = Tile(tnm.TileMesh(m.tx, m.ty, m.cs, m.ch, m.bmin, verts, polys))
    return out


def pack_map(tiles, map_id, quiet=False, min_area=0, places=None):
    """One map's graph record and tile records: ((base64, raw size), [((x, y), base64), ...]). Also used by
    fixtures.py, so the offline tests' synthetic maps go through exactly this. min_area: drop isolated pockets
    smaller than this (square yards) first. places: this map's places (transit.py's spec), put on the map and joined to
    it (places.py): the graph record then carries their stand points, attachments and the costs between them."""
    if min_area > 0:
        before = sum(len(t.polys) for t in tiles.values())
        poly_comp, area = components(tiles, link_tiles(tiles))
        tiles = prune(tiles, poly_comp, area, min_area)
        if not quiet:
            print("pruned pockets under", min_area, "sq yd:", before - sum(len(t.polys) for t in tiles.values()), "polys")
    links = link_tiles(tiles)
    cross = crossings(tiles, links)
    if not quiet:
        print("map", map_id, "tiles", len(tiles), "polys", sum(len(t.polys) for t in tiles.values()),
              "links", len(links), "crossings", len(cross))

    # which crossings touch each tile, and their poly and point there
    touch = {}
    for ci, c in enumerate(cross):
        touch.setdefault(c["a"], []).append((ci, c["pa"]))
        touch.setdefault(c["b"], []).append((ci, c["pb"]))
    edges = []
    for key, lst in touch.items():
        t = tiles[key]
        targets = [(p, local_point(t, cross[ci], key)) for ci, p in lst]
        for i, (ci, p) in enumerate(lst):
            costs = dijkstra(t, p, targets[i][1], targets[i + 1:])
            for j, cost in enumerate(costs):
                cj = lst[i + 1 + j][0]
                if cost is not None and cj != ci:
                    edges.append((ci, cj, cost, key))
    # Each polygon's component goes into its tile, each component's walkable area (square yards) into the graph: where
    # floors stack and the client gives no height, nav/Data.lua takes the floor in the larger connected area (a city's
    # street, not ground sealed under it). A crossing's component is its polygons'.
    poly_comp, area = components(tiles, links)
    ground = components.ground
    comp = [poly_comp[(c["a"], c["pa"])] for c in cross]
    if not quiet:
        print("intra-tile edges", len(edges), "components", len(area))

    pl, pw = [], []
    if places:
        import places as P
        snapped = {}
        pc_, _ = components(tiles, links)
        comp_area = {k: components.ground[c - 1] for k, c in pc_.items()}   # connected LAND, not the sea round a pier
        for p in places:
            s_ = P.snap(tiles, p, comp_area)
            if s_:
                snapped[p["id"]] = s_
            elif not quiet:
                print("  not on the map (no ground within %d yd): %s %s" % (P.SNAP_REACH, p["name"], (round(p["x"]), round(p["y"]))))
        attach, pairs, pstats = P.attach_and_pairs(tiles, cross, edges, snapped, touch)
        for pid in sorted(snapped):
            s_ = snapped[pid]
            t = tiles[s_["tile"]]
            wx, wy = t.world(s_["u"], s_["w"])
            at = [v for ci, c in attach[pid] for v in (ci + 1, max(1, math.ceil(c)))]
            pl.extend([pid, s_["tile"][0] * 64 + s_["tile"][1], s_["poly"] + 1, round(wx * 10), round(wy * 10),
                       len(attach[pid])] + at)
        for a, b, c in pairs:
            pw.extend((a, b, max(1, math.ceil(c))))
        if not quiet:
            worst = sorted(((s_["dist"], pid) for pid, s_ in snapped.items()), reverse=True)[:4]
            names = {p["id"]: p["name"] for p in places}
            print("places", len(snapped), "of", len(places), "joined,", pstats["pairs"], "walks between them; farthest snaps:",
                  ", ".join("%s %.0f yd" % (names[pid], d) for d, pid in worst))

    n = []
    for c in cross:
        n.extend((c["a"][0], c["a"][1], c["pa"] + 1, c["b"][0], c["b"][1], c["pb"] + 1,
                  round(c["x"] * 10), round(c["y"] * 10), round(c["z"])))
    e = []
    for ci, cj, cost, key in edges:
        e.extend((ci + 1, cj + 1, max(1, math.ceil(cost)), key[0] * 64 + key[1]))
    graph = {"f": FORMAT, "cells": next(iter(tiles.values())).cells, "n": n, "e": e, "k": comp,
             "ca": [max(1, round(a)) for a in area], "cg": [round(a) for a in ground],
             "t": sorted("%d_%d" % k for k in tiles), "factor": [FACTOR[1], FACTOR[2], FACTOR[3]]}
    if pl:
        graph["pl"], graph["pw"] = pl, pw
    records = []
    for key in sorted(tiles):
        t = tiles[key]
        # v: each vertex as the difference from the one before (u, w in cells, z in whole yards)
        v = []
        pu = pw = pz = 0
        for u, w, z in t.verts:
            z = round(z)
            v.extend((u - pu, w - pw, z - pz))
            pu, pw, pz = u, w, z
        # p: per polygon its vertex count, its area, then its vertices, each as the difference from the vertex
        # index before it (in the whole list; 1-based, so the first is the index itself)
        p = []
        last = 0
        for poly in t.polys:
            p.append(len(poly.verts))
            p.append(poly.area)
            for i in poly.verts:
                p.append(i + 1 - last)
                last = i + 1
        x = []
        for pi, e_, d, opi, oe in t.links:
            x.extend((pi + 1, e_ + 1, d, opi + 1, oe + 1))
        c = [poly_comp[(key, pi)] for pi in range(len(t.polys))]
        records.append((key, encode({"v": v, "p": p, "x": x, "c": c})[0]))
    return encode(graph), records


TOC_HEAD = """## Interface: 16001
## Title: |cffC9A24ATwich|rUI Navigation Data
## Notes: The walking maps TwichUI's navigation plans routes on. Loaded only when a route is first planned; keep it turned on alongside TwichUI if you use navigation.
## Author: twichie
## Version: 1.0.0
## RequiredDeps: !!!TwichUI
## LoadOnDemand: 1
## IconTexture: Interface\\AddOns\\!!!TwichUI\\media\\icon
## X-License: Generated from World of Warcraft client data; see README.md
## Category: Interface Enhancements

# Generated by tools/navbake/pack.py --toc from the client %s. Each map's crossing graph, then its tiles.
"""


def write_toc(out, client):
    files = []
    for name in sorted(os.listdir(MANIFESTS)):
        if name.endswith(".files"):
            with open(os.path.join(MANIFESTS, name)) as f:
                files.extend(ln.strip() for ln in f if ln.strip())
    with open(os.path.join(out, "TwichUI_NavData.toc"), "w", newline="\n") as f:
        f.write(TOC_HEAD % client)
        f.write("\n".join(files) + "\n")
    print("toc lists", len(files), "files")


def transit_record(spec):
    """The travel network as one record (see TwichUI_NavData/README.md): identities, factions, flights, ferries, teleports.
    Positions are not here: a place's stand point is in its map's graph record (where it was joined to the map)."""
    places = spec["places"]
    rec = {"f": FORMAT,
           "p": [v for p in places for v in (p["id"], p["kind"], p["cont"], p["faction"], p["node"])],
           "n": [p["name"] for p in places], "t": [p["town"] for p in places],
           "fl": [v for fl in spec["flights"] for v in fl],
           "fe": [v for fe in spec["ferries"] for v in (fe["a"], fe["b"], fe["travel"], fe["dwell"], fe["cycle"], fe["kind"])],
           "tp": [v for tp in spec["landings"] for v in (tp["spell"], tp["place"], tp["cast"])],
           "sp": [round(spec["speeds"][k]) for k in ("flight", "ship", "zeppelin")]}
    return rec


def write_transit(spec_path, out, client):
    import json
    with open(spec_path) as f:
        spec = json.load(f)
    b64, raw = encode(transit_record(spec))
    os.makedirs(os.path.join(out, "Data"), exist_ok=True)
    with open(os.path.join(out, "Data", "Transit.lua"), "w", newline="\n") as f:
        f.write("-- Transit.lua: flights, boats, zeppelins and teleports, generated by tools/navbake/transit.py and pack.py from the client %s.\n" % client)
        f.write("local S = TwichUI and TwichUI.NavDataStore\nif not S then return end\n")
        f.write('S.transit = "%s"\n' % b64)
    os.makedirs(MANIFESTS, exist_ok=True)
    with open(os.path.join(MANIFESTS, "Transit.files"), "w", newline="\n") as f:
        f.write("Data\\Transit.lua\n")
    print("transit", raw, "raw", len(b64), "base64,", len(spec["places"]), "places")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tnm")
    ap.add_argument("--map", type=int)
    ap.add_argument("--out", required=True)
    ap.add_argument("--client", required=True, help="client version the bake was read from")
    ap.add_argument("--transit", help="transit.py's spec (JSON): put its places for this map on the map")
    ap.add_argument("--transit-lua", metavar="SPEC", help="write Data/Transit.lua from transit.py's spec")
    ap.add_argument("--toc", action="store_true", help="write TwichUI_NavData.toc from the maps packed so far")
    a = ap.parse_args()
    if a.transit_lua:
        write_transit(a.transit_lua, a.out, a.client)
        return
    if a.toc:
        write_toc(a.out, a.client)
        return
    if a.tnm is None or a.map is None:
        ap.error("--tnm and --map are needed to pack a map")

    tiles = {}
    for name in sorted(os.listdir(a.tnm)):
        if name.endswith(".tnm"):
            t = Tile(tnm.load(os.path.join(a.tnm, name)))
            if t.polys:
                tiles[t.key] = t
    places = None
    if a.transit:
        import json
        with open(a.transit) as f:
            places = [p for p in json.load(f)["places"] if p["cont"] == a.map]
    (g64, graw), records = pack_map(tiles, a.map, min_area=MIN_POCKET, places=places)
    os.makedirs(os.path.join(a.out, "Data"), exist_ok=True)
    # parts this map had last time and may not have now: only files the last run's manifest named are removed
    os.makedirs(MANIFESTS, exist_ok=True)
    manifest = os.path.join(MANIFESTS, "Map%d.files" % a.map)
    if os.path.exists(manifest):
        with open(manifest) as f:
            for ln in f:
                old = os.path.join(a.out, ln.strip().replace("\\", os.sep))
                if ln.strip() and os.path.basename(old).startswith("Map%d" % a.map) and os.path.isfile(old):
                    os.remove(old)
    files = []
    gpath = os.path.join(a.out, "Data", "Map%d.lua" % a.map)
    with open(gpath, "w", newline="\n") as f:
        f.write("-- Map%d.lua: map %d's crossing graph, generated by tools/navbake/pack.py from the client %s.\n"
                % (a.map, a.map, a.client))
        f.write("local S = TwichUI and TwichUI.NavDataStore\nif not S then return end\n")
        f.write('S.graph[%d] = "%s"\n' % (a.map, g64))
    files.append("Data\\Map%d.lua" % a.map)
    print("graph", graw, "raw", len(g64), "base64")

    # tile records
    part, size, total = 1, 0, 0
    out = None

    def open_part(k):
        fn = "Map%d_%d.lua" % (a.map, k)
        fh = open(os.path.join(a.out, "Data", fn), "w", newline="\n")
        fh.write("-- %s: walking tiles of map %d, part %d, generated by tools/navbake/pack.py.\n" % (fn, a.map, k))
        fh.write("local S = TwichUI and TwichUI.NavDataStore\nif not S then return end\n")
        fh.write("S.tiles[%d] = S.tiles[%d] or {}\nlocal T = S.tiles[%d]\n" % (a.map, a.map, a.map))
        files.append("Data\\" + fn)
        return fh
    out = open_part(part)
    for key, s64 in records:
        line = 'T["%d_%d"] = "%s"\n' % (key[0], key[1], s64)
        if size + len(line) > PART_BYTES and size > 0:
            out.close()
            part += 1
            size = 0
            out = open_part(part)
        out.write(line)
        size += len(line)
        total += len(s64)
    out.close()
    print("tiles base64", total, "bytes in", part, "parts")
    with open(manifest, "w", newline="\n") as f:
        f.write("\n".join(files) + "\n")


if __name__ == "__main__":
    main()
