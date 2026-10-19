"""Putting places (flight points, docks, arrivals) on the walking maps, and the walking costs between them.

Used by pack.py's pack_map once a map's tiles, crossings and the costs between crossings are known, so a place's numbers
are in the same units and the same numbering as the graph record. For each place:

  snap     the nearest walkable ground (a polygon of the pruned mesh, in a tile or its neighbours) within SNAP_REACH
           yards, preferring the floor near the place's height when the place has one (a zeppelin tower's platform, a
           city's lower level). Where it ends up is the place's stand point: what a walk to it ends at.
  attach   the cost from that point to each crossing of its tile (the way a start or a goal of a route is joined to
           the crossing graph at plan time, nav/Route.lua's Seeds)
  pairs    the cost between every two places on the map (over the same crossing graph), kept when the walk is not
           longer than MAX_PAIR, so planning between places needs no searching at all

Costs are weighted yards, as everywhere: yards through a polygon times its area's factor (pack.FACTOR).
"""

import heapq
import math

import pack
import tnm

SNAP_REACH = 150.0        # yards from a place to ground that stands for it
LAND_AREA = 50000.0       # square yards: a boat dock's stand point is on a connected area at least this big (see snap)
Z_SLACK = 8.0             # yards of height difference that cost nothing when picking a floor
Z_WEIGHT = 0.4            # yards of snap distance per yard of height difference beyond that
MAX_PAIR = 30000.0        # weighted yards; longer walks between two places are not stored


def _tile_of(x, y):
    return int((tnm.ORIGIN - y) // tnm.TILE), int((tnm.ORIGIN - x) // tnm.TILE)


def _poly_distance(t, pi, u0, w0):
    """(distance in cells from (u0, w0) to polygon pi, nearest point). 0 and the point itself when inside."""
    pts = [t.verts[v] for v in t.polys[pi].verts]
    n = len(pts)
    sign = 0
    inside = True
    for i in range(n):
        (au, aw, _), (bu, bw, _) = pts[i], pts[(i + 1) % n]
        cr = (bu - au) * (w0 - aw) - (bw - aw) * (u0 - au)
        if cr > 1e-9:
            if sign < 0:
                inside = False
                break
            sign = 1
        elif cr < -1e-9:
            if sign > 0:
                inside = False
                break
            sign = -1
    if inside:
        return 0.0, (u0, w0)
    best, bp = math.inf, (u0, w0)
    for i in range(n):
        (au, aw, _), (bu, bw, _) = pts[i], pts[(i + 1) % n]
        du, dw = bu - au, bw - aw
        len2 = du * du + dw * dw
        s = 0.0 if len2 == 0 else max(0.0, min(1.0, ((u0 - au) * du + (w0 - aw) * dw) / len2))
        pu, pw = au + du * s, aw + dw * s
        d = math.hypot(u0 - pu, w0 - pw)
        if d < best:
            best, bp = d, (pu, pw)
    return best, bp


def snap(tiles, place, comp_area=None):
    """The place's stand point: dict(tile, poly, u, w) in the tile's cells, plus dist (yards), or None.
    comp_area: {(tile key, polygon): square yards of the connected area it is in}. A boat's stop is on the water, and the
    walkable pier by it is often a fragment the mesh doesn't join to the shore (a step too tall, a ramp too narrow): so a
    dock without a height (a ship's z is the sea's) stands on the nearest ground of a connected area of LAND_AREA or more,
    the shore end of its pier, and the walk to it ends there. Where no such ground is within reach, any ground will do."""
    x, y, z = place["x"], place["y"], place["z"]
    tx, ty = _tile_of(x, y)
    hint = abs(z) > 1.0
    want_land = bool(comp_area) and place.get("kind") == 2 and not hint
    for need_land in ((True, False) if want_land else (False,)):
        found = _snap(tiles, place, x, y, z, tx, ty, hint, comp_area if need_land else None)
        if found:
            return found
    return None


def _snap(tiles, place, x, y, z, tx, ty, hint, comp_area):
    best = None
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            t = tiles.get((tx + dx, ty + dy))
            if t is None:
                continue
            cs = t.m.cs
            u0, w0 = (x - t.m.wxmin) / cs, (y - t.m.wymin) / cs
            reach = SNAP_REACH / cs + 2
            for pi, poly in enumerate(t.polys):
                if poly.area != 1:
                    continue
                if comp_area is not None and comp_area.get((t.key, pi), 0) < LAND_AREA:
                    continue
                zs = [t.verts[v][2] for v in poly.verts]
                # cheap rejection by the polygon's box
                us = [t.verts[v][0] for v in poly.verts]
                ws = [t.verts[v][1] for v in poly.verts]
                if u0 < min(us) - reach or u0 > max(us) + reach or w0 < min(ws) - reach or w0 > max(ws) + reach:
                    continue
                d, (pu, pw) = _poly_distance(t, pi, u0, w0)
                score = d * cs
                if hint:
                    score += Z_WEIGHT * max(0.0, abs(sum(zs) / len(zs) - z) - Z_SLACK)
                if best is None or score < best[0]:
                    best = (score, t, pi, pu, pw, d * cs)
    if best is None or best[5] > SNAP_REACH:
        return None
    _, t, pi, pu, pw, dist = best
    # a hair inside the polygon, so the point is on it and not just on its edge
    pts = [t.verts[v] for v in t.polys[pi].verts]
    cu = sum(p[0] for p in pts) / len(pts)
    cw = sum(p[1] for p in pts) / len(pts)
    lu, lw = cu - pu, cw - pw
    ln = math.hypot(lu, lw)
    if ln > 0.05:
        pu, pw = pu + lu / ln * 0.05, pw + lw / ln * 0.05
    return dict(tile=t.key, poly=pi, u=pu, w=pw, dist=dist)


def attach_and_pairs(tiles, cross, edges, snapped, touch):
    """snapped: {place id: snap dict}. Returns (attach {place id: [(crossing index, cost)]}, pairs [(a, b, cost)], stats)."""
    attach, direct = {}, {}
    by_tile = {}
    for pid, s in snapped.items():
        by_tile.setdefault(s["tile"], []).append(pid)
    for pid, s in snapped.items():
        t = tiles[s["tile"]]
        lst = touch.get(s["tile"], [])
        targets = [(p, pack.local_point(t, cross[ci], s["tile"])) for ci, p in lst]
        costs = pack.dijkstra(t, s["poly"], (s["u"], s["w"]), targets)
        attach[pid] = [(ci, c) for (ci, _), c in zip(lst, costs) if c is not None]
        # places in the same tile: directly (an exact search over the tile's polygons)
        others = [q for q in by_tile[s["tile"]] if q != pid]
        if others:
            tg = [(snapped[q]["poly"], (snapped[q]["u"], snapped[q]["w"])) for q in others]
            for q, c in zip(others, pack.dijkstra(t, s["poly"], (s["u"], s["w"]), tg)):
                if c is not None:
                    direct[(pid, q)] = c
    adj = {}
    for ci, cj, cost, _ in edges:
        adj.setdefault(ci, []).append((cj, cost))
        adj.setdefault(cj, []).append((ci, cost))
    ids = sorted(snapped)
    pairs = {}
    for a in ids:
        dist = {}
        heap = []
        for ci, c in attach[a]:
            if c < dist.get(ci, math.inf):
                dist[ci] = c
                heap.append((c, ci))
        heapq.heapify(heap)
        done = set()
        while heap:
            d, ci = heapq.heappop(heap)
            if ci in done or d > MAX_PAIR:
                continue
            done.add(ci)
            for cj, w in adj.get(ci, ()):
                nd = d + w
                if nd < dist.get(cj, math.inf):
                    dist[cj] = nd
                    heapq.heappush(heap, (nd, cj))
        for b in ids:
            if b <= a:
                continue
            best = direct.get((a, b))
            for ci, c in attach[b]:
                d = dist.get(ci)
                if d is not None and d + c < (best if best is not None else math.inf):
                    best = d + c
            if best is not None and best <= MAX_PAIR:
                pairs[(a, b)] = best
    return attach, [(a, b, c) for (a, b), c in sorted(pairs.items())], dict(places=len(ids), pairs=len(pairs))
