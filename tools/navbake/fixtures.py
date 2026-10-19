"""Synthetic walking maps for TwichUI's offline navigation tests, packed by pack.py exactly as a real bake is.

    python3 -I tools/navbake/fixtures.py tests/fixtures/nav_fixture.lua

Each map is a few hand-made convex polygons on a coarse grid (40 cells a tile, ~13.3 yards a cell), chosen so the
right route is known in advance. Coordinates below are tile-local cells: u counts north from the tile's south edge,
w counts west from its east edge (the bake's frame). See tests/test_nav_route.lua for what each map checks.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pack  # noqa: E402
import tnm   # noqa: E402

CELLS = 40
CS = tnm.TILE / CELLS


def rect(w0, w1, u0, u1, z=0):
    """A rectangle as vertex list (w, u, z), wound consistently (Recast's frame: x = w, z = u)."""
    return [(w0, u0, z), (w0, u1, z), (w1, u1, z), (w1, u0, z)]


def make_tile(tx, ty, shapes):
    """shapes: list of (vertices, area). Builds a TileMesh with shared vertices and Recast-style neighbour info."""
    verts, index = [], {}
    polys = []
    for pts, area in shapes:
        vs = []
        for w, u, z in pts:
            key = (w, u, z)
            if key not in index:
                index[key] = len(verts)
                verts.append((w, round(z / 0.25), u))     # (vx, vy in ch units, vz)
            vs.append(index[key])
        polys.append(tnm.Poly(vs, [tnm.NULL] * len(vs), area))
    # neighbours: shared edges inside the tile; edges on the tile's side get 0x8000 | dir
    edges = {}
    for pi, p in enumerate(polys):
        for j in range(len(p.verts)):
            a, b = p.verts[j], p.verts[(j + 1) % len(p.verts)]
            edges.setdefault((min(a, b), max(a, b)), []).append((pi, j))
    for (a, b), users in edges.items():
        if len(users) == 2:
            (p1, j1), (p2, j2) = users
            polys[p1].neis[j1] = p2
            polys[p2].neis[j2] = p1
        else:
            pi, j = users[0]
            va, vb = verts[a], verts[b]
            if va[0] == 0 and vb[0] == 0:
                polys[pi].neis[j] = 0x8000 | 0
            elif va[2] == CELLS and vb[2] == CELLS:
                polys[pi].neis[j] = 0x8000 | 1
            elif va[0] == CELLS and vb[0] == CELLS:
                polys[pi].neis[j] = 0x8000 | 2
            elif va[2] == 0 and vb[2] == 0:
                polys[pi].neis[j] = 0x8000 | 3
    wxmax = tnm.ORIGIN - ty * tnm.TILE
    wymax = tnm.ORIGIN - tx * tnm.TILE
    mesh = tnm.TileMesh(tx, ty, CS, 0.25, (wymax - tnm.TILE, 0.0, wxmax - tnm.TILE), verts, polys)
    return pack.Tile(mesh)


def maps():
    out = {}
    # 9001: the U. Walkable: a west strip, an east strip and the south between them; the middle north is not.
    out[9001] = {(32, 32): make_tile(32, 32, [
        (rect(30, 40, 10, 40), 1), (rect(30, 40, 0, 10), 1), (rect(10, 30, 0, 10), 1),
        (rect(0, 10, 0, 10), 1), (rect(0, 10, 10, 40), 1),
    ])}
    # 9002: two tiles side by side (33 is east of 32). The east tile has a wall from its north edge down to u = 8,
    # leaving a gap in the south: walls are just missing ground.
    out[9002] = {
        (32, 32): make_tile(32, 32, [(rect(0, 40, 0, 40), 1)]),
        (33, 32): make_tile(33, 32, [
            (rect(20, 40, 0, 8), 1), (rect(20, 40, 8, 40), 1),     # west half (against tile 32)
            (rect(16, 20, 0, 8), 1),                               # the gap
            (rect(0, 16, 0, 8), 1), (rect(0, 16, 8, 40), 1),       # east half
        ]),
    }
    # 9003: islands. Tile 40_40 has two pieces with no shared edge and no link; tile 41_40 an island in its middle.
    out[9003] = {
        (40, 40): make_tile(40, 40, [(rect(24, 40, 0, 40), 1), (rect(0, 16, 0, 40), 1)]),
        (41, 40): make_tile(41, 40, [(rect(10, 30, 10, 30), 1)]),
    }
    # 9004: a lake (area 2) in the middle, ground all round. Crossing is 20 cells of water; going round adds less
    # than three times that, so walking round is cheaper. (Shores are split where the lake's sides meet them: polygons
    # inside a Recast tile always share whole edges, never a T-junction.)
    out[9004] = {(50, 50): make_tile(50, 50, [
        (rect(30, 40, 0, 10), 1), (rect(30, 40, 10, 30), 1), (rect(30, 40, 30, 40), 1),     # west shore
        (rect(10, 30, 30, 40), 1), (rect(10, 30, 10, 30), 2), (rect(10, 30, 0, 10), 1),
        (rect(0, 10, 0, 10), 1), (rect(0, 10, 10, 30), 1), (rect(0, 10, 30, 40), 1),        # east shore
    ])}
    # 9005: a narrow lake (8 cells) whose only way round is a loop to the north edge: swimming across costs about
    # 36 cells of walking, going round over 90, so the route swims.
    out[9005] = {(50, 50): make_tile(50, 50, [
        (rect(24, 40, 0, 38), 1), (rect(24, 40, 38, 40), 1),
        (rect(16, 24, 38, 40), 1), (rect(16, 24, 0, 38), 2),
        (rect(0, 16, 0, 38), 1), (rect(0, 16, 38, 40), 1),
    ])}
    # 9006: two floors over the same ground: a street (z 0) and a walkway above it (z 20) that ends on the street at
    # its east end only.
    out[9006] = {(50, 50): make_tile(50, 50, [
        (rect(0, 40, 0, 20, 0), 1),
        (rect(10, 30, 0, 20, 20), 1),
    ])}
    return out


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else "tests/fixtures/nav_fixture.lua"
    lines = ["-- Generated by tools/navbake/fixtures.py: synthetic walking maps, packed by pack.py. Do not edit.",
             "NAV_FIXTURE = { graph = {}, tiles = {} }"]
    for m, tiles in maps().items():
        (g64, _), records = pack.pack_map(tiles, m, quiet=True)
        lines.append('NAV_FIXTURE.graph[%d] = "%s"' % (m, g64))
        lines.append("NAV_FIXTURE.tiles[%d] = {" % m)
        for (x, y), s in records:
            lines.append('  ["%d_%d"] = "%s",' % (x, y, s))
        lines.append("}")
    with open(dest, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", dest)


if __name__ == "__main__":
    main()
