"""Map exploration data for TwichUI's world map (map/Data.lua), from the game clients installed on this computer.

    python3 -I tools/mapdata/build.py --wow "/path/to/World of Warcraft" [--transit ~/.cache/twichui-navbake/transit.json]

Offline only, like tools/navbake (whose CASC and DB2 readers this uses); nothing here is packaged and nothing is written
into the game's folder. The output holds numbers and names only: the file IDs of textures that are already in the
WoW: Forever client (the game draws them; TwichUI ships no map art), world rectangles, and places.

What is made, and from where:
  minimap   each continent tile's minimap texture: Forever's own WDT (MAID), the same tiles the game's minimap draws.
  reveal    every zone art's explored-area pieces (Forever's own WorldMapOverlay and WorldMapOverlayTile): where each
            piece sits on its zone's art and its texture files, so the stitched map can draw the pieces the player
            hasn't explored yet (the game's API gives only the explored ones).
  caves     the cave and pre-instance maps (Blizzard's "micro" maps). Forever's map tables have none of them, so their
            art, rectangle and floors are read from the retail client's map tables, and each is kept only when Forever
            verifiably has the same place: the WMO the map is drawn from (UiMapAssignment's WmoDoodadPlacementID, a MODF
            unique ID) is placed in Forever's terrain with the same file, position and rotation as in retail, and that
            WMO file's content is byte-identical in both clients (same content key). Its art must be in Forever's client.
  dungeons  dungeon and raid maps, the same way: retail's map tables for the floors and their art, kept only when the
            instance's WDT and its WMO are byte-identical in Forever, so the floors drawn are the ones Forever has.
            Entrances: retail Map.db2's ghost-return point (Corpse) of each kept instance, kept only when Forever's
            terrain at that point holds the same buildings as retail's (the WMO placements of the ADT tile there match).
  travel    boat and zeppelin docks and where each goes: TwichUI's own transit.json (tools/navbake/transit.py, read from
            Forever's TaxiPath tables), the same places Navigation uses.
Each place must lie on one of Forever's own maps (UiMapAssignment); which zone shows it is the game's to say at run
time (zone rectangles overlap, and only the game knows their shapes).

Anything that does not verify is left out and listed in the report (--report), with the reason.
"""

import argparse
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "navbake"))
import casc  # noqa: E402
import db2   # noqa: E402
import wowfiles as wf  # noqa: E402

FOREVER, RETAIL = "wow_classic_beta", "wow"
UI_MAP, UI_MAP_ASSIGNMENT, UI_MAP_X_ART, UI_MAP_ART, UI_MAP_ART_TILE = 1957206, 1957219, 1957217, 1957202, 1957210
UI_MAP_GROUP_MEMBER, MAP = 1957204, 1349477
WORLD_MAP_OVERLAY, WORLD_MAP_OVERLAY_TILE = 1134579, 1957212
CONTINENT_WDT = {0: 775971, 1: 782779, 2991: 7198644}   # Forever's continents (tools/navbake/extract.py's MAPS)
MICRO, DUNGEON = 5, 4                                     # Enum.UIMapType
ART_STYLE_CLASSIC = 1                                     # 1002 x 668 in 4 x 3 tiles of 256 (UiMapArtStyleLayer)
POS_TOLERANCE, ROT_TOLERANCE = 0.05, 0.01                 # yards, degrees: "the same placement"

f32 = db2.as_float


def ckey(storage, fdid):
    return storage._fdid.get(fdid)


def same_file(fv, rt, fdid):
    a, b = ckey(fv, fdid), ckey(rt, fdid)
    return a is not None and a == b


def tile_of(x, y):
    """The ADT tile (column, row) holding world point (x north, y west)."""
    return int((wf.ORIGIN - y) // wf.TILE), int((wf.ORIGIN - x) // wf.TILE)


def tiles_in(x0, y0, x1, y1):
    ax, ay = tile_of(max(x0, x1), max(y0, y1))
    bx, by = tile_of(min(x0, x1), min(y0, y1))
    return [(tx, ty) for tx in range(min(ax, bx), max(ax, bx) + 1) for ty in range(min(ay, by), max(ay, by) + 1)]


class Placements:
    """The WMO placements (MODF) of a continent's ADT tiles in one client, read on demand."""

    def __init__(self, storage, wdt_fdid):
        self.s = storage
        data = storage.read(wdt_fdid)
        self.tiles = wf.wdt_tiles(data) if data else {}
        self.cache = {}

    def tile(self, t):
        if t not in self.cache:
            out = {}
            ids = self.tiles.get(t)
            obj = ids and self.s.read(ids[1])
            if obj:
                _, wmos = wf.adt_placements(obj)
                for w in wmos:
                    out[w["uid"]] = w
            self.cache[t] = out
        return self.cache[t]

    def find(self, uid, tiles):
        for t in tiles:
            w = self.tile(t).get(uid)
            if w:
                return w
        return None

    def find_same(self, other, tiles):
        """This client's placement of the same file at the same place as `other` (another client's), whatever its
        unique ID (a re-exported tile can number its placements afresh)."""
        for t in tiles:
            for w in self.tile(t).values():
                if same_placement(w, other):
                    return w
        return None

    def holding(self, x, y):
        """The placements whose bounds (MODF extents) hold world point (x, y)."""
        px, pz = wf.ORIGIN - y, wf.ORIGIN - x
        return [w for w in self.tile(tile_of(x, y)).values()
                if w["ext"][0] <= px <= w["ext"][3] and w["ext"][2] <= pz <= w["ext"][5]]


def same_placement(a, b):
    if not a or not b or a["fdid"] != b["fdid"]:
        return False
    if any(abs(p - q) > POS_TOLERANCE for p, q in zip(a["pos"], b["pos"])):
        return False
    return all(abs(p - q) <= ROT_TOLERANCE for p, q in zip(a["rot"], b["rot"]))


def same_wmo(fv, rt, fdid):
    """Whether a WMO is byte-identical in both clients: its root and every group file (GFID)."""
    if not same_file(fv, rt, fdid):
        return False
    data = fv.read(fdid)
    g = wf.first(wf.chunks(data), "GFID") if data else None
    if not g:
        return False
    ids = struct.unpack_from("<%dI" % (g[2] // 4), data, g[1])
    return all(same_file(fv, rt, i) for i in ids if i)


def verify_building(fv, rt, fvP, rtP, uid, tiles):
    """None when the building a map is drawn from (a MODF unique ID in retail's tables) is in Forever's terrain as the
    same file at the same place, byte-identical; otherwise why not."""
    r = rtP.find(uid, tiles)
    if not r:
        return "its building is not in retail's terrain"
    f = fvP.find_same(r, tiles)
    if not f:
        return "its building is not where retail has it in Forever's terrain"
    if not same_wmo(fv, rt, f["fdid"]):
        return "its building's files differ in Forever"
    return None


def read_maps(storage):
    t = db2.DB2(storage.read(UI_MAP))
    out = {}
    for i, (rid, c) in enumerate(t.rows()):
        out[rid] = dict(name=t.string_at(i, 0), parent=c[2], type=c[5])
    return out


def read_assignments(storage):
    """[uiMap] = list of { inst, region (x0, y0, x1, y1), uid, group, order }"""
    out = {}
    for rid, c in db2.DB2(storage.read(UI_MAP_ASSIGNMENT)).rows():
        r = [f32(v) for v in c[2]]
        out.setdefault(c[4], []).append(dict(inst=c[6], x0=r[0], y0=r[1], x1=r[3], y1=r[4], uid=c[8], wmoGroup=c[9],
                                             order=c[5]))
    return out


def read_art(storage):
    """[uiMap] = (style, [12 file IDs, row by row]) for maps whose art is one layer of tiles."""
    xa = db2.DB2(storage.read(UI_MAP_X_ART))
    rel = xa.relations()
    art_of = {}
    for i, (rid, c) in enumerate(xa.rows()):
        if c[0] == 0:                                     # phase 0: the map as everyone sees it
            art_of[rel.get(i)] = c[1]
    styles = {rid: c[2] for rid, c in db2.DB2(storage.read(UI_MAP_ART)).rows()}
    tl = db2.DB2(storage.read(UI_MAP_ART_TILE))
    trel = tl.relations()
    tiles = {}
    for i, (rid, c) in enumerate(tl.rows()):
        row, col, layer, fdid = c[0], c[1], c[2], c[3]
        if layer == 0:
            tiles.setdefault(trel.get(i), {})[(row, col)] = fdid
    out = {}
    for ui, art in art_of.items():
        t = tiles.get(art)
        if t and len(t) == 12:
            out[ui] = (styles.get(art), [t[(r, c)] for r in range(3) for c in range(4)])
    return out


def read_groups(storage):
    """[uiMap] = (group, floor order, floor name)"""
    g = db2.DB2(storage.read(UI_MAP_GROUP_MEMBER))
    out = {}
    for i, (rid, c) in enumerate(g.rows()):
        out[c[2]] = (c[1], c[3], g.string_at(i, 0))
    return out


def read_instances(storage):
    t = db2.DB2(storage.read(MAP))
    out = {}
    for i, (rid, c) in enumerate(t.rows()):
        corpse = [f32(v) for v in c[6]]
        out[rid] = dict(name=t.string_at(i, 1), instanceType=c[8], expansion=c[9], corpseMap=c[17], wdt=c[21],
                        corpse=corpse)
    return out


def wdt_wmo(data):
    """The global WMO an instance's WDT places (MODF), or None (a terrain instance)."""
    chs = wf.chunks(data)
    c = wf.first(chs, "MODF")
    if not c or c[2] < 64:
        return None
    v = struct.unpack_from("<II3f3f6fHHHH", data, c[1])
    return {"fdid": v[0], "uid": v[1], "pos": v[2:5], "rot": v[5:8]}


class Zones:
    """Forever's own maps: which one a world point lies on (the smallest that holds it)."""

    def __init__(self, maps, assignments):
        self.rows = []
        for ui, rows in assignments.items():
            m = maps.get(ui)
            if not m or m["type"] not in (3,):            # zones and cities
                continue
            for a in rows:
                lo_x, hi_x = sorted((a["x0"], a["x1"]))
                lo_y, hi_y = sorted((a["y0"], a["y1"]))
                self.rows.append((a["inst"], lo_x, hi_x, lo_y, hi_y, (hi_x - lo_x) * (hi_y - lo_y), ui))

    def at(self, inst, x, y):
        best = None
        for r in self.rows:
            if r[0] == inst and r[1] <= x <= r[2] and r[3] <= y <= r[4]:
                if not best or r[5] < best[5]:
                    best = r
        return best and best[6]


def build(wow, transit_path):
    fv = casc.Storage(wow, FOREVER)
    rt = casc.Storage(wow, RETAIL)
    report = {"forever": fv.version, "retail": rt.version, "skipped": []}

    def skip(kind, ident, name, why):
        report["skipped"].append({"kind": kind, "id": ident, "name": name, "why": why})

    fmaps, fassign = read_maps(fv), read_assignments(fv)
    zones = Zones(fmaps, fassign)
    rmaps, rassign = read_maps(rt), read_assignments(rt)
    rart, rgroups, rinst = read_art(rt), read_groups(rt), read_instances(rt)

    # --- minimap tiles ---------------------------------------------------------------------------------
    minimap = {}
    for cont, wdt in CONTINENT_WDT.items():
        data = fv.read(wdt)
        maid = wf.first(wf.chunks(data), "MAID") if data else None
        rows = []
        if maid:
            for i in range(4096):
                e = struct.unpack_from("<8I", data, maid[1] + 32 * i)
                if e[7] and fv.has(e[7]):
                    rows.append((i % 64, i // 64, e[7]))
        minimap[cont] = rows
    report["minimapTiles"] = {c: len(v) for c, v in minimap.items()}

    # --- reveal: each zone art's explored-area pieces ------------------------------------------------------------
    pieces = {}
    for rid, c in db2.DB2(fv.read(WORLD_MAP_OVERLAY)).rows():
        pieces[rid] = dict(art=c[1], w=c[2], h=c[3], x=c[4], y=c[5], tiles={})
    tl = db2.DB2(fv.read(WORLD_MAP_OVERLAY_TILE))
    trel = tl.relations()
    for i, (rid, c) in enumerate(tl.rows()):
        piece = pieces.get(trel.get(i))
        if piece and c[2] == 0:
            piece["tiles"][(c[0], c[1])] = c[3]
    reveal = {}
    for rid in sorted(pieces):
        piece = pieces[rid]
        cols, rows = -(-piece["w"] // 256), -(-piece["h"] // 256)
        files = [piece["tiles"].get((r, c)) for r in range(rows) for c in range(cols)]
        if piece["w"] <= 0 or piece["h"] <= 0 or not all(files) or not all(fv.has(f) for f in files):
            skip("reveal", rid, str(piece["art"]), "a piece's textures are missing")
            continue
        reveal.setdefault(piece["art"], []).append((piece["w"], piece["h"], piece["x"], piece["y"], files))
    report["reveal"] = {"arts": len(reveal), "pieces": sum(len(v) for v in reveal.values())}

    # --- caves -------------------------------------------------------------------------------------------
    fvP = {c: Placements(fv, w) for c, w in CONTINENT_WDT.items() if c in (0, 1)}
    rtP = {c: Placements(rt, w) for c, w in CONTINENT_WDT.items() if c in (0, 1)}
    caves = []
    for ui in sorted(rmaps):
        m = rmaps[ui]
        if m["type"] != MICRO:
            continue
        rows = [a for a in rassign.get(ui, []) if a["inst"] in (0, 1)]
        if not rows:
            continue
        inst = rows[0]["inst"]
        x0 = min(min(a["x0"], a["x1"]) for a in rows)
        x1 = max(max(a["x0"], a["x1"]) for a in rows)
        y0 = min(min(a["y0"], a["y1"]) for a in rows)
        y1 = max(max(a["y0"], a["y1"]) for a in rows)
        uids = sorted({a["uid"] for a in rows if a["uid"]})
        if not uids:
            skip("cave", ui, m["name"], "no WMO placement to verify against")
            continue
        tiles = tiles_in(x0, y0, x1, y1)
        bad = None
        for uid in uids:
            bad = verify_building(fv, rt, fvP[inst], rtP[inst], uid, tiles)
            if bad:
                break
        if bad:
            skip("cave", ui, m["name"], bad)
            continue
        art = rart.get(ui)
        if not art or art[0] != ART_STYLE_CLASSIC:
            skip("cave", ui, m["name"], "no map art in the classic layout")
            continue
        if not all(fv.has(t) for t in art[1]):
            skip("cave", ui, m["name"], "its map art is not in Forever's client")
            continue
        if not zones.at(inst, (x0 + x1) / 2, (y0 + y1) / 2):
            skip("cave", ui, m["name"], "not on any of Forever's maps")
            continue
        g = rgroups.get(ui)
        caves.append(dict(id=ui, name=m["name"], cont=inst, x0=x0, y0=y0, x1=x1, y1=y1, tiles=art[1],
                          group=g and g[0], floor=g and g[1], floorName=g and g[2]))

    # a cave's floors: kept as a set only when every floor of its group verified
    kept = {c["id"] for c in caves}
    for c in caves:
        if c["group"]:
            members = [ui for ui, g in rgroups.items() if g[0] == c["group"]]
            if not all(ui in kept for ui in members):
                c["group"], c["floor"], c["floorName"] = None, None, None

    # --- dungeons -------------------------------------------------------------------------------------------
    # The classic dungeons and raids Forever has (its client holds the instance's WDT).
    dungeons = {}
    for inst, row in sorted(rinst.items()):
        if inst in (0, 1) or row["expansion"] != 0 or row["instanceType"] not in (1, 2) or not row["wdt"]:
            continue
        if not fv.has(row["wdt"]):
            continue
        dungeons[inst] = dict(inst=inst, name=row["name"], raid=row["instanceType"] == 2, floors=[])

    # Floors: each kept when the building it is drawn from is the same in Forever (in the instance's WDT for a
    # building-only instance, in its terrain otherwise).
    instP = {}

    def inst_placements(inst):
        if inst not in instP:
            w = rinst[inst]["wdt"]
            fdata, rdata = fv.read(w), rt.read(w)
            instP[inst] = (Placements(fv, w), Placements(rt, w), fdata and wdt_wmo(fdata), rdata and wdt_wmo(rdata))
        return instP[inst]

    for ui in sorted(rmaps):
        m = rmaps[ui]
        if m["type"] != DUNGEON:
            continue
        rows = rassign.get(ui, [])
        insts = {a["inst"] for a in rows}
        if len(insts) != 1:
            continue
        inst = insts.pop()
        if inst not in dungeons:
            continue
        fP, rP, fG, rG = inst_placements(inst)
        uids = sorted({a["uid"] for a in rows if a["uid"]})
        if not uids and rG:
            uids = [rG["uid"]]                            # a building-only instance: the WDT's own building
        why = None if uids else "no building to verify against"
        for uid in uids:
            if rG and rG["uid"] == uid:
                if not (fG and same_placement(fG, rG)):
                    why = "its building is placed differently in Forever"
                elif not same_wmo(fv, rt, fG["fdid"]):
                    why = "its building's files differ in Forever"
            else:
                x0 = min(min(a["x0"], a["x1"]) for a in rows)
                x1 = max(max(a["x0"], a["x1"]) for a in rows)
                y0 = min(min(a["y0"], a["y1"]) for a in rows)
                y1 = max(max(a["y0"], a["y1"]) for a in rows)
                why = verify_building(fv, rt, fP, rP, uid, tiles_in(x0, y0, x1, y1))
            if why:
                break
        if why:
            skip("dungeon floor", ui, dungeons[inst]["name"] + ": " + m["name"], why)
            continue
        art = rart.get(ui)
        if not art or art[0] != ART_STYLE_CLASSIC or not all(fv.has(t) for t in art[1]):
            skip("dungeon floor", ui, m["name"], "its map art is missing or not in the classic layout")
            continue
        g = rgroups.get(ui)
        dungeons[inst]["floors"].append(dict(id=ui, name=(g and g[2]) or m["name"], order=g[1] if g else 0,
                                             tiles=art[1]))
    for d in dungeons.values():
        d["floors"].sort(key=lambda fl: (fl["order"], fl["id"]))

    # Entrances: the ghost-return point (retail Map.db2's Corpse), kept when the buildings that hold that point in
    # Forever's terrain are the same files at the same places as in retail's (at least one must hold it: open
    # ground can't be checked this way).
    for inst, d in sorted(dungeons.items()):
        row = rinst[inst]
        cont = row["corpseMap"]
        x, y = row["corpse"]
        if cont not in (0, 1) or (x == 0 and y == 0):
            skip("entrance", inst, d["name"], "no entrance on Eastern Kingdoms or Kalimdor")
            continue
        holders = fvP[cont].holding(x, y)
        tiles = [tile_of(x, y)]
        if not holders:
            skip("entrance", inst, d["name"], "no building holds the entrance in Forever to verify against")
            continue
        if not all(rtP[cont].find_same(w, tiles) and same_wmo(fv, rt, w["fdid"]) for w in holders):
            skip("entrance", inst, d["name"], "Forever's buildings at the entrance differ from retail's")
            continue
        if not zones.at(cont, x, y):
            skip("entrance", inst, d["name"], "not on any of Forever's maps")
            continue
        d["entrance"] = dict(cont=cont, x=x, y=y)
    # A dungeon with neither a verified map nor a verified entrance has nothing to show
    for inst in [i for i, d in dungeons.items() if not d["floors"] and not d.get("entrance")]:
        del dungeons[inst]

    # --- travel ---------------------------------------------------------------------------------------------
    travel = []
    if transit_path and os.path.exists(transit_path):
        tr = json.load(open(transit_path))
        places = {p["id"]: p for p in tr["places"]}
        seen = set()
        for fe in tr["ferries"]:
            a, b = places[fe["a"]], places[fe["b"]]
            key = (a["id"], b["id"])
            if key in seen:
                continue
            seen.add(key)
            if not (zones.at(a["cont"], a["x"], a["y"]) and zones.at(b["cont"], b["x"], b["y"])):
                skip("travel", key, a["name"] + " to " + b["name"], "not on Forever's maps")
                continue
            travel.append(dict(kind="zeppelin" if fe["kind"] == 2 else "boat", a=a["id"], b=b["id"]))
        report["travel"] = len(travel)
        docks = {}
        for leg in travel:
            for pid in (leg["a"], leg["b"]):
                p = places[pid]
                docks[pid] = dict(id=pid, name=p["name"], town=p["town"], cont=p["cont"], x=p["x"], y=p["y"])
    else:
        docks = {}
        report["travel"] = "no transit.json"

    report["caves"] = len(caves)
    report["dungeons"] = {d["name"]: len(d["floors"]) for d in dungeons.values()}
    report["entrances"] = sum(1 for d in dungeons.values() if d.get("entrance"))
    return dict(build=fv.version, retail=rt.version, minimap=minimap, reveal=reveal, caves=caves, dungeons=dungeons, docks=docks,
                travel=travel), report


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(v):
    return ("%.1f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def write_lua(data, path):
    L = []
    w = L.append
    w("-- TwichUI: map exploration data. Generated by tools/mapdata/build.py from the game clients; regenerate, don't edit.")
    w("-- Forever build %s (minimap, travel, the maps places lie on); retail build %s (cave and dungeon maps, each kept only" % (
        data["build"], data["retail"]))
    w("-- where Forever's files verifiably match: tools/mapdata/build.py). Numbers are the client's own texture file IDs and")
    w("-- world yards (x north, y west); nothing here is art. Names are the client's (English); the map shows the game's own")
    w("-- name for a dungeon where it has one.")
    w("")
    w("local R = TwichUI")
    w("local D = { build = %s }" % lua_str(data["build"]))
    w("R.MapExploreData = D")
    w("")
    w("-- The game's minimap textures per continent tile: \"column,row,fileID\" separated by spaces (map/Detail.lua decodes a")
    w("-- continent's the first time it is needed). A tile is 533.33 yards; column runs east, row south.")
    w("D.minimap = {")
    for cont in sorted(data["minimap"]):
        rows = data["minimap"][cont]
        w("    [%d] = %s," % (cont, lua_str(" ".join("%d,%d,%d" % r for r in rows))))
    w("}")
    w("")
    w("-- Each zone art's explored-area pieces (by UiMapArtID, C_Map.GetMapArtID): \"w:h:x:y:file,file\" separated by spaces,")
    w("-- in the art's pixels (1002 x 668), files row by row in 256-pixel tiles (map/Art.lua decodes a zone's when it is drawn)")
    w("D.reveal = {")
    for art in sorted(data["reveal"]):
        w("    [%d] = %s," % (art, lua_str(" ".join("%d:%d:%d:%d:%s" % (p[0], p[1], p[2], p[3], ",".join(str(f) for f in p[4]))
                                               for p in data["reveal"][art]))))
    w("}")
    w("")
    w("-- Caves and pre-instance areas: { id, name, continent, x0, y0, x1, y1 (world yards), tiles (12 file IDs, 4 x 3, row")
    w("-- by row), floor group, floor order, floor name }")
    w("D.caves = {")
    for c in data["caves"]:
        w("    { %d, %s, %d, %s, %s, %s, %s, { %s }, %s, %s, %s }," % (
            c["id"], lua_str(c["name"]), c["cont"], num(c["x0"]), num(c["y0"]), num(c["x1"]), num(c["y1"]),
            ", ".join(str(t) for t in c["tiles"]), num(c["group"]) if c["group"] else "nil",
            num(c["floor"]) if c["group"] else "nil", lua_str(c["floorName"]) if c["group"] else "nil"))
    w("}")
    w("")
    w("-- Dungeons and raids: [instance] = { name, raid, entrance = { continent, x, y } or nil,")
    w("-- floors = { { id, name, tiles }, ... } in the game's order }")
    w("D.dungeons = {")
    for inst in sorted(data["dungeons"]):
        d = data["dungeons"][inst]
        e = d.get("entrance")
        w("    [%d] = { name = %s, raid = %s, entrance = %s, floors = {" % (
            inst, lua_str(d["name"]), "true" if d["raid"] else "false",
            ("{ %d, %s, %s }" % (e["cont"], num(e["x"]), num(e["y"]))) if e else "nil"))
        for fl in d["floors"]:
            w("        { %d, %s, { %s } }," % (fl["id"], lua_str(fl["name"]), ", ".join(str(t) for t in fl["tiles"])))
        w("    } },")
    w("}")
    w("")
    w("-- Boat and zeppelin docks: [id] = { name, town, continent, x, y };")
    w("-- the same places as Navigation's (TwichUI_NavData's Transit.lua, from Forever's taxi tables)")
    w("D.docks = {")
    for pid in sorted(data["docks"]):
        p = data["docks"][pid]
        w("    [%d] = { %s, %s, %d, %s, %s }," % (pid, lua_str(p["name"]), lua_str(p["town"]), p["cont"], num(p["x"]),
                                                num(p["y"])))
    w("}")
    w("")
    w("-- Where each goes: { kind, from dock, to dock } (a ride both ways is two lines)")
    w("D.travel = {")
    for leg in data["travel"]:
        w("    { %s, %d, %d }," % (lua_str(leg["kind"]), leg["a"], leg["b"]))
    w("}")
    with open(path, "w", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--wow", required=True, help="the World of Warcraft folder (holds Data/ and .build.info)")
    ap.add_argument("--transit", default=os.path.expanduser("~/.cache/twichui-navbake/transit.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "!!!TwichUI", "map", "Data.lua"))
    ap.add_argument("--report", help="write what was kept and what was left out (JSON)")
    args = ap.parse_args()
    data, report = build(args.wow, args.transit)
    write_lua(data, args.out)
    if args.report:
        with open(args.report, "w") as fh:
            json.dump(report, fh, indent=1)
    print(json.dumps({k: v for k, v in report.items() if k != "skipped"}, indent=1))
    reasons = {}
    for s in report["skipped"]:
        reasons[(s["kind"], s["why"])] = reasons.get((s["kind"], s["why"]), 0) + 1
    for (kind, why), n in sorted(reasons.items()):
        print("left out: %3d %s: %s" % (n, kind, why))


if __name__ == "__main__":
    main()
