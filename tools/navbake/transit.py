"""The travel network between places, from the client's own tables: flight points, flights, boats and zeppelins.

    python3 -I transit.py --wow "/path/to/World of Warcraft" --out ~/.cache/twichui-navbake/transit.json

Reads TaxiNodes, TaxiPath and TaxiPathNode (db2.py), and UiMapAssignment for a city whose arrival has no flight point,
and writes a spec pack.py bakes into the maps' graph records and TwichUI_NavData/Data/Transit.lua. Nothing here knows
where a player is or what they have learned: that is the game's to say at plan time (C_TaxiMap.GetTaxiNodesForMap).

What the client does not give, and what stands in (all labelled estimates in the interface):
  - speeds: flights are taken at FLIGHT_SPEED, boats at SHIP_SPEED, zeppelins at ZEPPELIN_SPEED yards a second;
  - where a boat is now: a visit every cycle, so the wait is the average one (see wait_seconds in nav/Journey.lua);
  - where a teleport lands: the city's flight point (or, for Darnassus, the middle of its map region).

File layouts and meanings, each checked against this client (README.md): TaxiNodes columns are (name, position x y z,
..., ID, continent, ..., CharacterBitNumber, flags, ..., mount creature per faction [Horde, Alliance]); TaxiPath is
(ID, from node, to node, cost); TaxiPathNode is (position, ID, path, index, continent, flags, delay, ...) with flag 1 a
teleport and flag 2 a stop where the transport waits `delay` seconds.
"""

import argparse
import json
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import casc  # noqa: E402
import db2   # noqa: E402

TAXI_NODES, TAXI_PATH, TAXI_PATH_NODE, UI_MAP, UI_MAP_ASSIGNMENT = 1068100, 1067802, 1000437, 1957206, 1957219

FLIGHT_SPEED = 32.0       # yards a second along a taxi path (an estimate: the client has no speed)
SHIP_SPEED = 16.0         # yards a second, on-map distance between stops (an estimate)
ZEPPELIN_SPEED = 20.0
FLIGHT, DOCK, LANDING = 1, 2, 3
ALLIANCE, HORDE = 1, 2
CAST_SECONDS = 10         # a teleport's cast time
DOCK_MERGE = 40.0         # yards: two stops this close are one dock
FACTION_REACH = 700.0     # yards: the flight points whose factions a dock inherits
PLACE_NAMES = {2991: "Zephras Isle"}   # maps without a flight point to name a dock after
SKIP_NAME = re.compile(r"^(generic|transport|quest path|zzold|programmer)|naxxramas", re.I)

# Teleports Forever teaches (modules/MageTravel.lua's M.SPELLS, checked there against What's Training?): spell, city, the
# flight point the city's arrival is taken to be near (None: the middle of the city's map region, UiMap id given)
TELEPORTS = (
    (3561, "Stormwind", 2, None), (3562, "Ironforge", 6, None), (3565, "Darnassus", None, 1457),
    (3567, "Orgrimmar", 23, None), (3563, "Undercity", 11, None), (3566, "Thunder Bluff", 22, None),
)


def short_name(name):
    return name.split(",")[0].strip()


def load(storage):
    f = db2.as_float
    t = db2.DB2(storage.read(TAXI_NODES))
    nodes = {}
    for i, (rid, c) in enumerate(t.rows()):
        horde, ally = c[14]
        nodes[rid] = dict(id=rid, name=t.string_at(i, 0), x=f(c[1][0]), y=f(c[1][1]), z=f(c[1][2]), cont=c[5],
                          bit=c[7], faction=(HORDE if horde else 0) | (ALLIANCE if ally else 0))
    paths = {}
    for rid, c in db2.DB2(storage.read(TAXI_PATH)).rows():
        paths[rid] = (c[1], c[2])
    path_nodes = {}
    for rid, c in db2.DB2(storage.read(TAXI_PATH_NODE)).rows():
        path_nodes.setdefault(c[2], []).append((c[3], [f(v) for v in c[0]], c[4], c[5], c[6]))
    for seq in path_nodes.values():
        seq.sort()
    return nodes, paths, path_nodes


def uimap_center(storage, uimap):
    f = db2.as_float
    for rid, c in db2.DB2(storage.read(UI_MAP_ASSIGNMENT)).rows():
        if c[4] == uimap and c[5] == 0:
            r = [f(v) for v in c[2]]
            return (r[0] + r[3]) / 2, (r[1] + r[4]) / 2
    raise RuntimeError("no region for UiMap %d" % uimap)


def build(storage):
    nodes, paths, path_nodes = load(storage)
    places, by_node = [], {}

    def add(kind, cont, x, y, z, name, faction, node=0, town=None):
        places.append(dict(id=len(places) + 1, kind=kind, cont=cont, x=x, y=y, z=z, name=name, faction=faction, node=node,
                           town=town or name))
        return places[-1]

    # Flight points: those a character can learn (a nonzero CharacterBitNumber). The others are the pseudo-nodes
    # transports hang their paths on, quest flights, battleground flights and retired entries.
    real = {}
    for n in nodes.values():
        if n["bit"] > 0 and n["faction"] and not SKIP_NAME.search(n["name"]):
            p = add(FLIGHT, n["cont"], n["x"], n["y"], n["z"], short_name(n["name"]), n["faction"], n["id"])
            by_node[n["id"]] = p
            real[n["id"]] = n

    # Flights: a taxi path between two flight points, as long as its nodes (3D) at FLIGHT_SPEED. A path is directed.
    flights = {}
    for pid, (a, b) in paths.items():
        if a in by_node and b in by_node and pid in path_nodes:
            seq = path_nodes[pid]
            length = 0.0
            for i in range(len(seq) - 1):
                if seq[i][2] == seq[i + 1][2] and not seq[i][3] & 1:
                    length += math.dist(seq[i][1], seq[i + 1][1])
            key = (by_node[a]["id"], by_node[b]["id"])
            seconds = round(length / FLIGHT_SPEED)
            if key not in flights or seconds < flights[key]:
                flights[key] = seconds

    def nearest_real(cont, x, y):
        best, bd = None, 1e18
        for n in real.values():
            if n["cont"] == cont:
                d = math.hypot(n["x"] - x, n["y"] - y)
                if d < bd:
                    best, bd = n, d
        return best, bd

    def dock_faction(cont, x, y):
        mask = 0
        for n in real.values():
            if n["cont"] == cont and math.hypot(n["x"] - x, n["y"] - y) <= FACTION_REACH:
                mask |= n["faction"]
        return mask or (ALLIANCE | HORDE)

    docks = []

    def dock_at(cont, x, y, z, kind_zep):
        for d in docks:
            if d["cont"] == cont and math.hypot(d["x"] - x, d["y"] - y) <= DOCK_MERGE and (abs(d["z"] - z) < 30):
                return d
        n, dist = nearest_real(cont, x, y)
        base = short_name(n["name"]) if n else PLACE_NAMES.get(cont, "Dock")
        name = base + (" zeppelin" if kind_zep else " dock")
        if any(o["name"] == name and o["cont"] == cont for o in docks):
            # a second dock by the same place: say which side of it
            dx, dy = (x - n["x"], y - n["y"]) if n else (0, 0)
            side = ("north" if dx > 0 else "south") if abs(dx) > abs(dy) else ("west" if dy > 0 else "east")
            name = "%s (%s side)" % (name, side)
        d = add(DOCK, cont, x, y, z, name, dock_faction(cont, x, y), town=base)
        docks.append(d)
        return d

    # Boats and zeppelins: a transport path with stops is a loop (the last node wraps to the first). Between two
    # consecutive stops the transport covers the run of its nodes on one map (a jump to another map costs no distance
    # in the table: the transport sails off one map and in on the other).
    ferries = []
    for pid in sorted(path_nodes):
        a, b = paths.get(pid, (0, 0))
        if a in by_node and b in by_node:
            continue                       # a flight
        seq = path_nodes[pid]
        stops = [(i, n) for i, n in enumerate(seq) if n[3] & 2 and n[4] > 0]
        if len(stops) < 2:
            continue
        run, runs = 0.0, []
        for i, n in enumerate(seq):
            # a node after a teleport-flagged one, or on another map, is a jump: the transport vanishes and appears
            if i and seq[i - 1][2] == n[2] and not seq[i - 1][3] & 1:
                run += math.dist(seq[i - 1][1][:2], n[1][:2])
            runs.append(run)
        total = run
        zs = [abs(n[1][2]) for _, n in stops]
        zeppelin = sum(zs) / len(zs) > 20
        speed = ZEPPELIN_SPEED if zeppelin else SHIP_SPEED
        # clusters of stops at one dock, in loop order
        cl = []
        for i, n in stops:
            d = dock_at(n[2], n[1][0], n[1][1], n[1][2], zeppelin)
            cl.append((d, i, n[4]))
        cycle = round(total / speed + sum(delay for _, _, delay in cl))
        for k in range(len(cl)):
            d0, i0, dl0 = cl[k]
            d1, i1, _ = cl[(k + 1) % len(cl)]
            if d0["id"] == d1["id"]:
                continue
            leg = runs[i1] - runs[i0] if k + 1 < len(cl) else (total - runs[i0]) + runs[cl[0][1]]
            ferries.append(dict(a=d0["id"], b=d1["id"], travel=round(leg / speed), dwell=dl0, cycle=cycle,
                                kind=2 if zeppelin else 1, path=pid))

    # Teleport arrivals
    landings = []
    for spell, city, node, uimap in TELEPORTS:
        if node is not None:
            p = by_node[node]
        else:
            x, y = uimap_center(storage, uimap)
            p = add(LANDING, 1, x, y, 0.0, city, ALLIANCE | HORDE)
        landings.append(dict(spell=spell, city=city, place=p["id"], cast=CAST_SECONDS))

    return dict(version=1, places=places, flights=[[a, b, s] for (a, b), s in sorted(flights.items())],
                ferries=ferries, landings=landings,
                speeds=dict(flight=FLIGHT_SPEED, ship=SHIP_SPEED, zeppelin=ZEPPELIN_SPEED))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wow", required=True)
    ap.add_argument("--product", default="wow_classic_beta")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    s = casc.Storage(a.wow, a.product)
    spec = build(s)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w") as f:
        json.dump(spec, f, separators=(",", ":"))
    by = {p["id"]: p for p in spec["places"]}
    kinds = {}
    for p in spec["places"]:
        kinds[p["kind"]] = kinds.get(p["kind"], 0) + 1
    print("places", len(spec["places"]), "(flight %d, dock %d, landing %d)" % (kinds.get(1, 0), kinds.get(2, 0), kinds.get(3, 0)),
          "flights", len(spec["flights"]), "ferries", len(spec["ferries"]), "teleports", len(spec["landings"]))
    for fe in spec["ferries"]:
        pa, pb = by[fe["a"]], by[fe["b"]]
        print("  %s %s (%d) -> %s (%d): %ds, cycle %ds, factions %d/%d" % (
            "zeppelin" if fe["kind"] == 2 else "boat", pa["name"], pa["cont"], pb["name"], pb["cont"], fe["travel"], fe["cycle"],
            pa["faction"], pb["faction"]))


if __name__ == "__main__":
    main()
