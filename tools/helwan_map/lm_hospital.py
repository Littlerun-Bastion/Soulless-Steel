"""The hospital campus at its real place: the cluster of OSM hospital
buildings in their gardens up the hill north of the Japanese Garden (the
wards "Ladies Ward", "Male 1 Ward", "Male 2 Ward", "Addiction Department",
"Old Age Department", "Rehabilitation Department", the outpatient clinics,
the administration, "The Lodge", the villas, the museum and archive).
OSM gives the campus no name, so it is registered as "Helwan Hospital".

  campus     every real building kept (their roofs and ruin states as the
             rest of the map); the generated houses and the reference
             image's roofs inside go; a campus wall round the cluster with a
             gate wherever a road or path enters, the main gate where the
             asphalt drive meets the street
  grounds    rough lawns between the wards, paved courtyards round them,
             the OSM footways and steps as paths, benches, bare trees
  entrance   an ambulance bay inside the main gate with ambulances (the
             "ambulance" car sprite), one abandoned askew in the gate, car
             wrecks round the gate
  salvage    two "medical_store" sources (cases marked with a cross) by the
             outpatient clinics and the largest ward, a diesel generator by
             the service buildings
  main block the six-storey hospital building on Ismail Kamel Street (also
             OSM building=hospital) gets ambulances and wrecks on its
             service drive; it keeps its own roof
"""
import numpy as np
from shapely.geometry import LineString, Point
from shapely.ops import unary_union

import district_life
import equipment
import kit
import lmkit as K
import props

NAME = "Helwan Hospital"
OWNER = "landmarks:hospital"
SEED = 9301

# Hospital buildings bigger than this are the separate main block.
MAIN_BLOCK_M2 = 3000.0
# How far the campus reaches round its outermost buildings.
CAMPUS_PAD_M = 14.0
# OSM buildings this close to the ward cluster belong to the campus.
CLUSTER_M = 22.0
WIDE_GATE_M = 9.0
PATH_GATE_M = 5.0
AMBULANCES = 4
BENCH_STEP_M = 22.0
TREE_STEP_M = 11.0
TREE_CHANCE = 0.45
MAIN_ROADS = ("trunk", "secondary", "tertiary", "primary")


def _ambulance():
    for i, e in enumerate(props.CATALOGUE.get("vehicle", [])):
        if e["file"] == "vehicle_ambulance.png":
            return i, (e["length_m"], e["width_m"])
    return -1, props.SIZE_M["vehicle"]


def build(site, masks):
    hosp = K.osm_polys(site, lambda p: p.get("building") == "hospital")
    wards = [(g, p) for g, p in hosp if g.area < MAIN_BLOCK_M2]
    main_blocks = [g for g, p in hosp if g.area >= MAIN_BLOCK_M2]
    if len(wards) < 3:
        return {"built": False, "why": "no ward cluster in OSM"}
    core = unary_union([g for g, _ in wards]).convex_hull
    others = [g for g, p in K.osm_polys(site, lambda p: "building" in p, core.buffer(CLUSTER_M))]
    cluster = unary_union([core] + [g for g in others if g.distance(core) < CLUSTER_M])
    campus = cluster.convex_hull.buffer(CAMPUS_PAD_M, join_style="round", quad_segs=4)
    main_roads = unary_union([g for g, v, w, _, kind, line in site.full_layout["roads"]
                              if kind in MAIN_ROADS and g.intersects(campus.buffer(10.0))])
    if not main_roads.is_empty:
        campus = campus.difference(main_roads.buffer(3.0))
    campus = kit.largest(campus.simplify(1.0))
    if campus is None or campus.area < 5000:
        return {"built": False, "why": "no land"}
    if not K.land_free(site, campus):
        return {"built": False, "why": "land not free (KeepOut, marker or claim)"}
    site.claim(campus, OWNER)
    site.add_landmark(NAME, "hospital", campus)
    stats = {"built": True, "wards": len(wards)}
    main_block = main_blocks[0] if main_blocks else None
    if site.in_window(campus):
        masks.append(campus)
        _campus(site, campus, wards, stats)
    else:
        stats["built"] = False
        stats["why"] = "outside the window"
    if main_block is not None and site.in_window(main_block.buffer(30.0)):
        stats["main_block"] = _main_block(site, main_block)
    return stats


def _campus(site, campus, wards, stats):
    c0 = campus.centroid
    rng = K.seeded(SEED, c0.x, c0.y)
    site.clear_area(campus)
    osm_roofs = [g for g, p in K.osm_polys(site, lambda p: "building" in p, campus.buffer(20.0))]

    def real(b):
        return b.opts.get("stage") == "osm roofs" and K.is_osm_roof(b, osm_roofs)
    stats["buildings_removed"] = K.drop_buildings(site, campus, keep=real) + \
        site.remove_buildings_touching(LineString(campus.exterior.coords).buffer(1.0), kinds=("house",))
    site.solid_extra.append(campus)
    # The buildings left on the campus, from the whole map's roofs (a window
    # run lays the campus out as the full run does).
    kept = K.kept_roofs(site, campus, osm_roofs)
    stats["buildings_kept"] = len(kept)
    houses = K.as_multi(kept)

    roads_here = [(g, w, kind, line) for g, v, w, _, kind, line in site.full_layout["roads"]
                  if line is not None and not kind.startswith("rail:") and g.intersects(campus.buffer(5.0))]
    concrete = K.as_multi([g for g, *_ in roads_here])
    ring = LineString(campus.exterior.coords)
    gates = []
    for g, w, kind, line in roads_here:
        x = ring.intersection(line)
        for p in getattr(x, "geoms", [x]):
            if p.geom_type == "Point" and all(np.hypot(p.x - q[0], p.y - q[1]) > 10.0 for q in gates):
                gates.append((p.x, p.y, WIDE_GATE_M if w >= 3.0 else PATH_GATE_M, w))
    foot = K.osm_lines(site, lambda p: p.get("highway") in ("footway", "steps", "pedestrian"), campus)
    for x, y in K.gate_points(campus.exterior, [ln for ln, _ in foot], 10.0):
        if all(np.hypot(x - q[0], y - q[1]) > 10.0 for q in gates):
            gates.append((x, y, PATH_GATE_M, 2.0))
    # The main gate: the widest road crossing, nearest the street.
    street = K.roads_near(site, campus, 40.0)
    wide = [g for g in gates if g[3] >= 3.0] or gates
    main_gate = min(wide, key=lambda g: (-g[3], Point(g[0], g[1]).distance(street) if street is not None else 0.0)) \
        if wide else None

    courts = K.as_multi([g.buffer(3.5, join_style="mitre") for g in kept]).intersection(campus)
    paths = K.paths_geom([ln for ln, _ in foot], [2.2 for _ in foot])
    lawn = campus.difference(courts).difference(concrete.buffer(0.5)).difference(paths)

    # The ambulance bay: a paved apron just inside the main gate, beside the
    # drive.
    amb_v, amb_size = _ambulance()
    bay = None
    ambulances = wrecks = 0
    if main_gate is not None:
        gx, gy = main_gate[0], main_gate[1]
        d = np.array([c0.x - gx, c0.y - gy])
        d /= np.hypot(*d) or 1.0
        ang = float(np.arctan2(d[1], d[0]))
        cands = [(gx + u, gy + w) for u in np.arange(-45.0, 46.0, 3.0) for w in np.arange(-45.0, 46.0, 3.0)]
        cands.sort(key=lambda q: np.hypot(q[0] - gx, q[1] - gy))
        bay = K.find_rect(cands, 13.0, 18.0, ang, campus.buffer(-1.5),
                          K.as_multi([houses.buffer(2.0), concrete.buffer(0.5), paths]))
        if bay is not None and amb_v >= 0:
            bx, by, ang = bay
            P = K.local(bx, by, ang)
            for k in range(AMBULANCES):
                w = -6.75 + k * 4.5
                if rng.random() < 0.85:
                    ambulances += props.add_vehicle(site.props, site.salvage, "vehicle", *P(0.0, w),
                                                    ang + np.pi + rng.normal(0, 0.04), amb_size, amb_v)
        if amb_v >= 0:
            ax, ay = gx + d[0] * 3.0, gy + d[1] * 3.0
            ambulances += props.add_vehicle(site.props, site.salvage, "vehicle", ax, ay,
                                            ang + rng.uniform(0.5, 1.0), amb_size, amb_v)
        for _ in range(int(rng.integers(3, 6))):
            v, size = props.pick_vehicle("vehicle_wreck", rng)
            wx, wy = gx + rng.normal(0, 7.0), gy + rng.normal(0, 7.0)
            if not houses.buffer(1.0).contains(Point(wx, wy)) and site.props.clear_of(wx, wy, size[0] / 2):
                wrecks += site.props.add("vehicle_wreck", wx, wy, rng.uniform(0, 2 * np.pi), size, v)
    stats.update(ambulances=ambulances, wrecks=wrecks)

    # Stores and the generator.
    sources = []
    taken = K.as_multi([houses.buffer(1.0), concrete.buffer(1.0)] +
                       ([K.rect_at(bay[0], bay[1], bay[2], 15.0, 20.0)] if bay else []))

    def beside(g, l, w):
        ring_ = LineString(g.buffer(2.4, join_style="mitre").exterior.coords)
        for t in np.linspace(0, ring_.length, 24, endpoint=False):
            p = ring_.interpolate(t)
            q = ring_.interpolate((t + 1.0) % ring_.length)
            a = float(np.arctan2(q.y - p.y, q.x - p.x))
            r = K.rect_at(p.x, p.y, a, l, w)
            if campus.buffer(-1.0).contains(r) and not r.intersects(taken):
                return p.x, p.y, a
        return None

    by_name = {str(p.get("name", "")): g for g, p in wards}
    targets = [by_name.get("Outpatient clinics and Multiuse room"),
               max((g for g, _ in wards), key=lambda g: g.area)]
    for g in targets:
        if g is None:
            continue
        spot = beside(g, 3.0, 2.2)
        if spot is not None:
            sources.append(("medical_store",) + spot)
            taken = taken.union(Point(spot[0], spot[1]).buffer(3.0))
    # The generator stands by the largest service building that is on the
    # map (some OSM outlines are too small or too ragged to be buildings).
    service = [g for g, p in K.osm_polys(site, lambda p: p.get("building") == "service", campus)]
    service = [g for g in kept if service and K.is_osm_poly(g, service)]
    if service:
        spot = beside(max(service, key=lambda g: g.area), 4.0, 2.2)
        if spot is not None:
            sources.append(("diesel_generator",) + spot)
            taken = taken.union(Point(spot[0], spot[1]).buffer(3.0))
    stats["sources"] = len(sources)
    clutter = 0
    for kind, x, y, a in sources:
        if kind != "medical_store":
            continue
        for name in ("cabinet", "crates"):
            v, size = district_life.variant_of("clutter", name)
            px, py = x + np.cos(a) * 2.9, y + np.sin(a) * 2.9
            q = Point(px, py)
            if v >= 0 and site.props.clear_of(px, py, max(size) / 2) and campus.contains(q) and \
                    not houses.buffer(0.8).contains(q) and not concrete.buffer(0.5).contains(q):
                clutter += site.props.add("clutter", px, py, a, size, v)
            a += np.pi
    stats["clutter"] = clutter

    # Benches by the paths, trees on the lawns.
    benches = []
    for ln, _ in foot:
        for t in np.arange(BENCH_STEP_M / 2, ln.length, BENCH_STEP_M):
            p = ln.interpolate(t)
            q = ln.interpolate(min(t + 1.0, ln.length))
            a = float(np.arctan2(q.y - p.y, q.x - p.x))
            bx, by = p.x - np.sin(a) * 2.3, p.y + np.cos(a) * 2.3
            if lawn.contains(Point(bx, by)) and not taken.contains(Point(bx, by)):
                benches.append((bx, by, a))
    stats["benches"] = len(benches)
    blocked = K.as_multi([taken.buffer(2.0), paths.buffer(1.0), courts]
                         + [Point(x, y).buffer(2.0) for x, y, _ in benches])
    trees = 0
    for x, y in K.free_spots(campus, blocked, TREE_STEP_M, rng, clear=2.0):
        if rng.random() < TREE_CHANCE:
            trees += site.props.add("tree", x, y, rng.uniform(0, 2 * np.pi), (rng.uniform(9.0, 14.0),) * 2)
    stats["trees"] = trees

    seed = int(rng.integers(1 << 30))
    # The campus wall stops at the wards it meets (their walls close the
    # campus there); gate piers and step treads stay off the buildings and
    # the road concrete.
    solid = K.as_multi([houses, concrete])

    def draw(L):
        r = np.random.default_rng(seed)
        K.lawn(L, lawn, r, 0.11, 0.5)
        K.gravel(L, courts.difference(concrete), 0.22, 0.9)
        K.gravel(L, paths.difference(courts).difference(concrete), 0.2, 0.9)
        for ln, p in foot:
            if p.get("highway") == "steps":
                K.steps(L, ln, 2.2, avoid=solid)
        if bay is not None:
            bx, by, ang = bay
            apron = K.rect_at(bx, by, ang, 13.0, 18.0)
            K.gravel(L, apron, 0.25, 0.95)
            P = K.local(bx, by, ang)
            for k in range(AMBULANCES + 1):
                w = -9.0 + k * 4.5
                L.line("groundlines", LineString([P(-5.5, w), P(5.5, w)]), 0.15, 0.4, 0.85)
            L.line("groundlines", LineString([P(-5.5, -9.0), P(-5.5, 9.0)]), 0.15, 0.4, 0.85)
        parts = K.wall_parts(campus.exterior, [(g[0], g[1]) for g in gates if g[2] >= WIDE_GATE_M], WIDE_GATE_M)
        narrow = [(g[0], g[1]) for g in gates if g[2] < WIDE_GATE_M]
        if narrow:
            parts = [q for part in parts for q in K.wall_parts(part, narrow, PATH_GATE_M)]
        K.perimeter_wall(L, parts, 0.5, 0.29, pier_every=6.0, avoid=houses)
        for g in gates:
            K.gate_piers(L, campus.exterior, (g[0], g[1]), g[2], size=1.6 if g[2] >= WIDE_GATE_M else 1.1,
                         avoid=solid, slide=3.0)
        for x, y, a in benches:
            K.bench(L, x, y, a)
        for kind, x, y, a in sources:
            if kind == "medical_store":
                K.cases(L, x, y, a, r, mark="cross")
                site.salvage.add(kind, x, y, a, 3.2, 2.4)
            else:
                equipment.add_source(site.salvage, L, kind, x, y, a, r)
    site.drawers.append(draw)


def _main_block(site, block):
    """Ambulances and wrecks along the service drive round the six-storey
    hospital block."""
    c = block.centroid
    rng = K.seeded(SEED + 1, c.x, c.y)
    amb_v, amb_size = _ambulance()
    made = {"ambulances": 0, "wrecks": 0}
    drives = [line for g, v, w, _, kind, line in site.full_layout["roads"]
              if kind == "service" and line is not None and line.distance(block) < 15.0]
    for line in drives:
        for t in np.arange(rng.uniform(4, 10), line.length - 4.0, rng.uniform(9.0, 13.0)):
            if made["ambulances"] + made["wrecks"] >= 8:
                break
            p = line.interpolate(t)
            q = line.interpolate(min(t + 1.0, line.length))
            a = float(np.arctan2(q.y - p.y, q.x - p.x))
            if rng.random() < 0.55 and amb_v >= 0:
                if site.props.clear_of(p.x, p.y, amb_size[0] / 2):
                    made["ambulances"] += props.add_vehicle(site.props, site.salvage, "vehicle", p.x, p.y,
                                                            a + rng.normal(0, 0.15), amb_size, amb_v)
            elif rng.random() < 0.5:
                v, size = props.pick_vehicle("vehicle_wreck", rng)
                if site.props.clear_of(p.x, p.y, size[0] / 2):
                    made["wrecks"] += site.props.add("vehicle_wreck", p.x, p.y, a + rng.uniform(-0.8, 0.8), size, v)
    return made
