"""The Helwan Observatory at its real place: Al Marsed (Observatory) Street on
the eastern hill, where OSM has the "Helwan Observatory Museum", two
man_made=observatory outlines (the telescope domes) and the institute's
buildings.

  compound   a walled compound on the dome's side of the street (the side
             away from the museum), its gate on the street: the OSM
             buildings (flat roofs with small observation domes on them),
             the main telescope dome at the OSM dome (a round building whose
             roof is a lit dome with its observing slit), a second dome,
             two outbuildings, a met enclosure, paved drives and paths
  mast       a guyed lattice radio and weather mast in the talls (it leans
             with height), with its control cabinet at the foot
  museum     the OSM museum across the street in a walled forecourt
  far dome   the second OSM observatory outline, up the street, as a dome of
             its own inside a fence

Salvage: a "telescope" source in each dome (motors, drives, optics in
aluminium, electronics), "lab_equipment" cases by an outbuilding, a
control cabinet at the mast.
"""
import numpy as np
from shapely.geometry import LinearRing, LineString, Point, Polygon
from shapely.ops import nearest_points, polylabel

import buildings as bl
import district_life
import equipment
import kit
import lmkit as K
import props
import ruins

NAME = "Helwan Observatory"
OWNER = "landmarks:observatory"
SEED = 9201

MAIN_DOME_R = 8.0
SECOND_DOME_R = 6.0
FAR_FENCE_M = 7.0
MAST_H = 48.0
GATE_GAP_M = 9.0
# How far the compound reaches past the outermost OSM feature along the
# street (each way) and back from the street.
REACH_ALONG_M = (22.0, 30.0)
REACH_BACK_M = 30.0
STREET_SETBACK_M = 3.0


def _is_museum(p):
    return p.get("tourism") == "museum" and "Observatory" in str(p.get("name:en", ""))


def build(site, masks):
    museum = K.osm_polys(site, _is_museum)
    if not museum:
        return {"built": False, "why": "no museum in OSM"}
    museum = museum[0][0]
    domes = [g for g, p in K.osm_polys(site, lambda p: p.get("man_made") == "observatory")]
    near_bld = [g for g, p in K.osm_polys(site, lambda p: "building" in p, museum.buffer(140.0))]
    street = None
    for g, v, w, _, kind, line in site.full_layout["roads"]:
        if kind in ("tertiary", "secondary", "trunk") and line is not None and line.distance(museum) < 40.0:
            if street is None or line.distance(museum) < street[0].distance(museum):
                street = (line, w, g)
    if street is None or not domes:
        return {"built": False, "why": "no street or no domes"}
    line, _, street_geom = street
    main_dome = min(domes, key=lambda g: g.distance(museum))
    far_domes = [g for g in domes if g is not main_dome and g.distance(main_dome) > 60.0]

    # A frame on the street: u along it, w across it towards the main dome.
    s0 = line.project(main_dome.centroid)
    p0, p1 = line.interpolate(s0 - 5.0), line.interpolate(s0 + 5.0)
    ang = float(np.arctan2(p1.y - p0.y, p1.x - p0.x))
    ox, oy = line.interpolate(s0).x, line.interpolate(s0).y
    side = np.sign((main_dome.centroid.x - ox) * -np.sin(ang) + (main_dome.centroid.y - oy) * np.cos(ang)) or 1.0
    cu, cw = np.cos(ang), np.sin(ang)

    def to_uw(x, y):
        dx, dy = x - ox, y - oy
        return dx * cu + dy * cw, side * (-dx * cw + dy * cu)

    def from_uw(u, w):
        return ox + u * cu - side * w * cw, oy + u * cw + side * w * cu

    feats = [main_dome] + [g for g in near_bld if g.distance(museum) > 5.0 and to_uw(*g.centroid.coords[0])[1] > 0]
    uw = [to_uw(*q) for g in feats for q in g.exterior.coords]
    u0 = min(u for u, _ in uw) - REACH_ALONG_M[0]
    u1 = max(u for u, _ in uw) + REACH_ALONG_M[1]
    w1 = max(w for _, w in uw) + REACH_BACK_M
    rect = Polygon([from_uw(u0, 0.0), from_uw(u1, 0.0), from_uw(u1, w1), from_uw(u0, w1)])
    roads = K.roads_near(site, rect, 20.0)
    compound = rect if roads is None else rect.difference(roads.buffer(STREET_SETBACK_M + 1.0))
    compound = kit.largest(compound.buffer(-0.5, join_style="mitre"))
    if compound is None:
        return {"built": False, "why": "no land"}
    forecourt = museum.buffer(10.0, join_style="mitre")
    mroads = K.roads_near(site, forecourt, 20.0)
    if mroads is not None:
        forecourt = kit.largest(forecourt.difference(mroads.buffer(STREET_SETBACK_M)))
    fars = []
    for g in far_domes:
        c = g.centroid
        r = float(np.sqrt(g.area / np.pi))
        fars.append((c.x, c.y, r, K.ngon(c.x, c.y, r + FAR_FENCE_M, 16)))
    land = K.as_multi([compound, forecourt] + [f[3] for f in fars])
    if not K.land_free(site, land):
        return {"built": False, "why": "land not free (KeepOut, marker or claim)"}
    site.claim(land, OWNER)
    site.add_landmark(NAME, "observatory", K.as_multi([compound, forecourt]))
    if not site.in_window(land):
        return {"built": False, "why": "outside the window"}
    masks.append(land)
    rng = K.seeded(SEED, ox, oy)
    stats = {"built": True}

    site.clear_area(land)
    osm_roofs = [g for g, p in K.osm_polys(site, lambda p: "building" in p, land.buffer(30.0))]

    def real(b):
        return b.opts.get("stage") == "osm roofs" and K.is_osm_roof(b, osm_roofs)
    stats["buildings_removed"] = K.drop_buildings(site, land, keep=real) + \
        site.remove_buildings_touching(land, kinds=("house",), margin=1.0)
    site.solid_extra.append(compound)
    site.solid_extra.append(forecourt)

    mv = float(site.sampler.value(ox, oy))
    # The buildings left on the land, from the whole map's roofs (a window
    # run lays the compound out as the full run does).
    kept = K.kept_roofs(site, land, osm_roofs)
    kept_b = K.standing(site, kept)
    blocked = K.as_multi([g.buffer(5.0) for g in kept])

    def pin(b, intact=0.6):
        # Drawn whether or not the building stands in this run.
        state = ruins.INTACT if rng.random() < intact else ruins.DAMAGED
        if b is not None:
            b.opts["state"] = state

    # The institute's own buildings get observation domes on their roofs.
    for g, b in zip(kept, kept_b):
        if g.within(compound.buffer(2.0)) and g.area > 200:
            c = polylabel(g, 0.3)
            r = min(g.exterior.distance(c) - 1.5, 3.2)
            spots = []
            if r > 1.4:
                spots.append((c.x, c.y, r))
                rest = g.buffer(-1.2).difference(c.buffer(r + 2.5))
                if not rest.is_empty and g.area > 400:
                    part = kit.largest(rest)
                    q = polylabel(part, 0.3)
                    rq = min(part.exterior.distance(q) - 0.3, 2.2)
                    if rq > 1.2:
                        spots.append((q.x, q.y, rq))
            slits = [float(rng.uniform(0, 2 * np.pi)) for _ in spots]
            if b is not None:
                b.kind = "lm_flat_domes"
                b.opts["domes"] = spots
                b.opts["slits"] = slits
            pin(b)
    for g, b in zip(kept, kept_b):
        if g.intersects(museum) and g.within(forecourt.buffer(1.0)):
            pin(b, 0.75)

    new = []
    c = main_dome.centroid
    dome_g = K.ngon(c.x, c.y, MAIN_DOME_R, 24)
    if dome_g.within(compound) and not dome_g.buffer(2.0).intersects(K.as_multi(kept)):
        b = bl.Building(dome_g, mv, "lm_dome", dome=(c.x, c.y, MAIN_DOME_R), slit=float(rng.uniform(0, 2 * np.pi)))
        pin(b, 0.7)
        new.append(b)
    # The gate on the street side, in front of the main buildings; drives
    # from the gate to a turning circle and paths to each building.
    inside = [g for g in kept + [b.poly for b in new] if g.within(compound.buffer(2.0))]
    gate_u = float(np.mean([to_uw(*g.centroid.coords[0])[0] for g in inside] or [0.0]))
    ring = LineString(compound.exterior.coords)
    gx, gy = from_uw(gate_u, 0.0)
    gp = ring.interpolate(ring.project(Point(gx, gy)))
    gate = (gp.x, gp.y)
    hub = from_uw(gate_u, 17.0)
    walks = []
    for g in inside:
        e = g.exterior.interpolate(g.exterior.project(Point(hub)))
        walks.append(LineString([hub, (e.x, e.y)]))
    paved = K.as_multi([LineString([gate, hub]).buffer(4.0, cap_style="flat"), Point(hub).buffer(9.0)])
    paved = paved.intersection(compound)
    paths = K.as_multi([ln.buffer(1.3) for ln in walks]).difference(paved).intersection(compound)

    taken = K.as_multi([blocked, paved.buffer(3.0)] + [b.poly.buffer(8.0) for b in new])
    inner = compound.buffer(-4.0)
    grid = [(x, y) for x in np.arange(compound.bounds[0], compound.bounds[2], 3.0)
            for y in np.arange(compound.bounds[1], compound.bounds[3], 3.0)]

    def back(q):
        return -to_uw(*q)[1]

    # The second dome a little way from the first, then the mast and the met
    # enclosure at the back, the outbuildings between.
    grid.sort(key=lambda q: abs(np.hypot(q[0] - c.x, q[1] - c.y) - 34.0))
    spot = K.find_rect(grid, 2 * SECOND_DOME_R + 4.0, 2 * SECOND_DOME_R + 4.0, 0.0, inner, taken)
    if spot is not None:
        x, y, _ = spot
        g = K.ngon(x, y, SECOND_DOME_R, 20)
        b = bl.Building(g, mv, "lm_dome", dome=(x, y, SECOND_DOME_R), slit=float(rng.uniform(0, 2 * np.pi)))
        pin(b, 0.6)
        new.append(b)
        taken = taken.union(g.buffer(8.0))
    grid.sort(key=back)
    mast = K.find_rect(grid, 30.0, 30.0, ang, inner, taken)
    if mast is not None:
        taken = taken.union(K.rect_at(mast[0], mast[1], ang, 12.0, 12.0))
    met = K.find_rect(grid, 15.0, 15.0, ang, inner, taken)
    if met is not None:
        taken = taken.union(K.rect_at(met[0], met[1], ang, 19.0, 19.0))
    sheds = []
    grid.sort(key=lambda q: -back(q) * 0.3 + abs(to_uw(*q)[0] - (u0 + u1) / 2) * 0.1)
    for ln_, d in ((11.0, 8.0), (10.0, 7.5)):
        spot = K.find_rect(grid, ln_ + 8.0, d + 8.0, ang, inner, taken)
        if spot is None:
            continue
        g = K.rect_at(spot[0], spot[1], ang, ln_, d)
        if not K.road_clear(site, g):
            continue
        new.append(bl.Building(g, mv, "house"))
        sheds.append((spot[0], spot[1], ln_, d))
        taken = taken.union(g.buffer(6.0))
    for b in new:
        site.buildings.append(b)
        if not any(b.poly is g for g in inside) and b.poly.within(compound.buffer(2.0)):
            e = b.poly.exterior.interpolate(b.poly.exterior.project(Point(hub)))
            walks.append(LineString([hub, (e.x, e.y)]))
    paths = K.as_multi([ln.buffer(1.3) for ln in walks]).difference(paved).intersection(compound)
    stats["domes"] = sum(1 for b in new if b.kind == "lm_dome")
    stats["buildings_added"] = len(new)

    # The far dome keeps its OSM outline (a roof of the whole map's layout)
    # and gets a dome roof.
    far_b = []
    for x, y, r, fence in fars:
        disc = Point(x, y).buffer(r)
        roof = next((g for g in K.big_roofs_in(site, disc) if g.area < 400), None)
        slit = float(rng.uniform(0, 2 * np.pi))
        if roof is None:
            continue
        b = K.standing(site, [roof])[0]
        if b is not None:
            b.kind = "lm_dome"
            b.opts["dome"] = (x, y, r)
            b.opts["slit"] = slit
        pin(b, 0.5)
        far_b.append((x, y, r, fence))
    stats["far_domes"] = len(far_b)

    sources = []
    for x, y, r in [b.opts["dome"] for b in new if b.kind == "lm_dome"] + [f[:3] for f in far_b]:
        sources.append(("telescope", x, y, 0.0, r * 1.1, r * 1.1))
    for x, y, ln_, d in sheds[:1]:
        P = K.local(x, y, ang)
        sources.append(("lab_equipment",) + P(0.0, d / 2 + 2.6) + (ang, 3.2, 2.4))
    stats["sources"] = len(sources) + (1 if mast is not None else 0)

    # Bare trees along the drive and inside the wall, a wreck in the drive, a
    # guard hut by the gate.
    trees = 0
    for t in (7.0, 13.0):
        for s in (-1, 1):
            hx, hy = from_uw(gate_u + s * 7.0, t)
            if compound.contains(Point(hx, hy).buffer(1.5)) and not taken.contains(Point(hx, hy)):
                trees += site.props.add("tree", hx, hy, rng.uniform(0, 6.28), (rng.uniform(8, 11),) * 2)
    edge = kit.largest(compound.buffer(-4.0))
    edge = edge.exterior if edge is not None else LineString()
    for t in np.arange(10.0, edge.length, 16.0):
        q = edge.interpolate(t)
        if rng.random() < 0.65 and not taken.buffer(2.0).contains(q) and not paved.buffer(3.0).contains(q):
            trees += site.props.add("tree", q.x, q.y, rng.uniform(0, 6.28), (rng.uniform(8, 12),) * 2)
    # Avenues: trees either side of each path, alternating.
    for k, ln in enumerate(walks):
        for j, t in enumerate(np.arange(12.0, ln.length - 6.0, 9.0)):
            p = ln.interpolate(t)
            q = ln.interpolate(min(t + 1.0, ln.length))
            a = float(np.arctan2(q.y - p.y, q.x - p.x))
            s = 1 if (j + k) % 2 else -1
            tx, ty = p.x - np.sin(a) * 3.2 * s, p.y + np.cos(a) * 3.2 * s
            if compound.contains(Point(tx, ty).buffer(1.5)) and not taken.contains(Point(tx, ty)):
                trees += site.props.add("tree", tx, ty, rng.uniform(0, 6.28), (rng.uniform(7, 10),) * 2)
    # A few cars left round the turning circle.
    cars = 0
    for k in range(4):
        a = ang + np.pi * (0.25 + 0.5 * k) + rng.normal(0, 0.1)
        cx, cy = hub[0] + np.cos(a) * 6.0, hub[1] + np.sin(a) * 6.0
        if rng.random() < 0.7 and paved.contains(Point(cx, cy).buffer(2.0)):
            v, size = props.pick_vehicle("vehicle", rng)
            if site.props.clear_of(cx, cy, size[0] / 2 - 0.2):
                cars += props.add_vehicle(site.props, site.salvage, "vehicle", cx, cy,
                                          a + np.pi / 2 + rng.normal(0, 0.1), size, v)
    stats["cars"] = cars
    # The wreck stands at the first of these spots in the drive that is paved
    # and clear of the cars.
    v, size = props.pick_vehicle("vehicle_wreck", rng)
    wrot = ang + rng.uniform(-0.6, 0.6)
    wrecks = 0
    for du, dw in ((4.0, 12.0), (-4.0, 12.0), (1.5, 6.5)):
        wx, wy = from_uw(gate_u + du, dw)
        if paved.contains(Point(wx, wy)) and site.props.clear_of(wx, wy, size[0] / 2 - 0.2):
            wrecks += site.props.add("vehicle_wreck", wx, wy, wrot, size, v)
            break
    gv, gsize = district_life.variant_of("hut", "guard")
    hx, hy = from_uw(gate_u - GATE_GAP_M / 2 - 3.0, 3.5)
    if gv >= 0 and compound.contains(Point(hx, hy).buffer(1.5)):
        site.props.add("hut", hx, hy, ang, gsize, gv)
    stats.update(trees=trees, wrecks=wrecks)

    seed = int(rng.integers(1 << 30))
    # The walls stop at the buildings they meet (the museum stands close to
    # the street, so its front is the forecourt's street side); the museum
    # gate is the point of the forecourt wall clear of them nearest the
    # street in front of the museum.
    walled = K.as_multi([g for g in kept if g.intersects(land)])
    fring = LineString(forecourt.exterior.coords)
    front = line.interpolate(line.project(museum.centroid))
    open_ring = fring.difference(walled.buffer(7.0 / 2 + 1.5)) if not walled.is_empty else fring
    fg = nearest_points(open_ring if not open_ring.is_empty else fring, front)[0]
    museum_gate = (fg.x, fg.y)

    def draw(L):
        r = np.random.default_rng(seed)
        L.fill("groundlines", compound, 0.2, 0.45)
        K.lawn(L, compound.difference(paved), r, 0.14, 0.3)
        K.gravel(L, paved, 0.25, 0.95)
        K.gravel(L, paths, 0.22, 0.9)
        K.gravel(L, forecourt, 0.24, 0.9)
        K.perimeter_wall(L, K.wall_parts(compound.exterior, [gate], GATE_GAP_M), 0.5, 0.29, pier_every=6.0,
                         avoid=walled)
        K.gate_piers(L, compound.exterior, gate, GATE_GAP_M, size=1.5, avoid=walled)
        K.perimeter_wall(L, K.wall_parts(forecourt.exterior, [museum_gate], 7.0), 0.4, 0.29, pier_every=5.0,
                         pier=0.8, avoid=walled)
        K.gate_piers(L, forecourt.exterior, museum_gate, 7.0, size=1.2, avoid=walled)
        for x, y, rr, fence in far_b:
            K.gravel(L, Point(x, y).buffer(rr + 3.0).difference(Point(x, y).buffer(rr)), 0.23, 0.8)
            kit.fence(L, fence.exterior, r, gate=kit.nearest_edge_point(fence, street_geom), v=0.32, post_every=2.0)
        if met is not None:
            mx, my, ma = met
            sq = K.rect_at(mx, my, ma, 14.0, 14.0)
            K.lawn(L, sq, r, 0.13, 0.6)
            kit.fence(L, sq.exterior, r, gate=Point(*sq.exterior.coords[0]), v=0.34, post_every=1.8)
            P = K.local(mx, my, ma)
            scr = K.rect_at(*P(-2.0, -1.5), ma, 1.6, 1.1)
            L.fill("interiors", K.cast(scr, 0.8), 0.0, 0.5)
            L.fill("interiors", scr, 0.46)
            for k in range(4):
                L.line("interiors", LineString([P(-2.7, -1.9 + k * 0.25), P(-1.3, -1.9 + k * 0.25)]), 0.04, 0.3)
            for u, w in ((2.5, -2.0), (2.5, 2.5), (-2.5, 3.0)):
                L.fill("interiors", Point(*P(u, w)).buffer(0.35, quad_segs=3), 0.42)
                L.fill("interiors", Point(*P(u, w)).buffer(0.15, quad_segs=2), 0.1)
            ax, ay = P(0.5, 0.5)
            L.tall_post(ax, ay, 0.16, 0.0, 10.0, 0.4, 0.5)
            for k in range(3):
                a = k * 2.1
                L.tall_span((ax, ay), (ax + np.cos(a) * 0.9, ay + np.sin(a) * 0.9), 0.08, 10.0, 10.0, 0.45)
                L.fill("talls", Point(ax + np.cos(a) * 0.9, ay + np.sin(a) * 0.9).buffer(0.18, quad_segs=2), 0.5,
                       h=10.0)
        for kind, x, y, a, w, h in sources:
            if kind == "lab_equipment":
                K.cases(L, x, y, a, r)
            site.salvage.add(kind, x, y, a, w, h)
        if mast is not None:
            mx, my, _ = mast
            L.fill("interiors", K.rect_at(mx, my, ang, 2.2, 2.2), 0.26)
            P = K.local(mx, my, ang)
            equipment.add_source(site.salvage, L, "control_cabinet", *P(0.0, 3.4), ang, r)
            anchors = K.lattice_mast(L, mx, my, MAST_H, ang, guys=3, guy_r=13.0)
            for ax, ay in anchors:
                L.fill("interiors", K.rect_at(ax, ay, ang, 1.2, 1.2), 0.3)
                L.line("interiors", LinearRing(K.rect_at(ax, ay, ang, 1.2, 1.2).exterior.coords), 0.06, 0.42)
    site.drawers.append(draw)
    return stats
