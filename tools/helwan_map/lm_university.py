"""The south edge of Helwan University at its real place: the faculties OSM
maps at the north edge of the play area (Medicine, Law, Education,
Computers and Information, Nursing and their annexes); the rest of the
campus lies north of the play area.

  campus     the street blocks round the cluster of OSM university
             buildings (grown from the Faculty of Medicine), inside the play
             area; the generated houses and the reference image's roofs go,
             the real faculty buildings stay, and an OSM building the city
             layout lost (the Faculty of Education's ragged outline is left
             out of the large roofs) is put back from its OSM outline
  wall       a campus wall along the campus edge (open where the campus
             runs on north out of the play area), with gates where the
             campus roads leave it
  quad       the largest open ground on the campus paved as a quad: paving
             joints, a dry fountain basin, benches, lamp posts, a ring of
             bare trees
  main gate  where the street beside the quad meets the campus wall, facing
             the quad's middle: two pylons and a lintel standing in the
             talls (they lean with height), flagpoles inside
  grounds    rough lawns, paths along the OSM footways

Salvage: "lab_equipment" cases by two faculty buildings and a diesel
generator by the gate.
"""
import numpy as np
from shapely.geometry import LinearRing, LineString, Point, box
from shapely.ops import polylabel, unary_union

import buildings as bl
import equipment
import kit
import lmkit as K
from frame import PLAY_HALF_M

NAME = "Helwan University"
OWNER = "landmarks:university"
SEED = 9401

CLUSTER_M = 60.0
BLOCK_SHARE = 0.4
HULL_PAD_M = 45.0
CLOSE_GAPS_M = 6.0
THIN_M = 14.0
GATE_GAP_M = 16.0
SIDE_GATE_M = 8.0
PYLON_H = 11.0
QUAD_MIN_M2 = 2500.0
TREE_STEP_M = 12.0
# Nothing under 60 m2 is a building.
RESTORE_MIN_M2 = 60.0


def _is_uni(p):
    return p.get("building") == "university" or "جامعة حلوان" in str(p.get("operator", "")) + str(p.get("name", ""))


def build(site, masks):
    uni = K.osm_polys(site, _is_uni)
    play = box(-PLAY_HALF_M, -PLAY_HALF_M, PLAY_HALF_M, PLAY_HALF_M)
    seeds = [g for g, p in uni if p.get("name") == "كلية الطب" and g.intersects(play)]
    if not seeds:
        return {"built": False, "why": "no Faculty of Medicine in OSM"}
    # Grow the cluster of university buildings from the Faculty of Medicine.
    cluster = [seeds[0]]
    rest = [g for g, _ in uni if g is not seeds[0] and g.intersects(play.buffer(50.0))]
    grew = True
    while grew:
        grew = False
        for g in list(rest):
            if any(g.distance(c) < CLUSTER_M for c in cluster):
                cluster.append(g)
                rest.remove(g)
                grew = True
    hull = unary_union(cluster).convex_hull.buffer(HULL_PAD_M)
    inner_play = box(-PLAY_HALF_M, -PLAY_HALF_M + 1.0, PLAY_HALF_M, PLAY_HALF_M)
    picked = []
    for blk in site.full_layout["blocks"]:
        if not blk.intersects(hull):
            continue
        part = blk.intersection(inner_play)
        # Thin strips between two roads stay outside: the wall runs along
        # the campus's own street.
        if part.is_empty or part.area < 200 or 2.0 * part.area / part.length < THIN_M:
            continue
        if part.intersection(hull).area >= BLOCK_SHARE * part.area:
            picked.append(part)
    if not picked:
        return {"built": False, "why": "no blocks"}
    campus = unary_union(picked).buffer(CLOSE_GAPS_M, join_style="mitre").buffer(-CLOSE_GAPS_M - 1.0,
                                                                                   join_style="mitre")
    campus = kit.largest(campus.intersection(inner_play))
    if campus is None:
        return {"built": False, "why": "no land"}
    if not K.land_free(site, campus):
        return {"built": False, "why": "land not free (KeepOut, marker or claim)"}
    site.claim(campus, OWNER)
    site.add_landmark(NAME, "university", campus)
    if not site.in_window(campus):
        return {"built": False, "why": "outside the window"}
    masks.append(campus)
    c0 = campus.centroid
    rng = K.seeded(SEED, c0.x, c0.y)
    stats = {"built": True, "faculties": len([g for g in cluster if g.intersects(campus)])}

    site.clear_area(campus)
    osm_all = K.osm_polys(site, lambda p: "building" in p, campus.buffer(20.0))
    osm_roofs = [g for g, p in osm_all]

    def real(b):
        return b.opts.get("stage") == "osm roofs" and K.is_osm_roof(b, osm_roofs)
    stats["buildings_removed"] = K.drop_buildings(site, campus, keep=real) + \
        site.remove_buildings_touching(campus, kinds=("house",), margin=0.5)
    site.solid_extra.append(campus)
    # The buildings left on the campus, from the whole map's roofs (a window
    # run lays the campus out as the full run does).
    kept = K.kept_roofs(site, campus, osm_roofs)
    # The faculties keep the plain large-roof look even where the district
    # modules restyled them as works buildings.
    for b in K.standing(site, kept):
        if b is not None and real(b) and b.kind != "big":
            b.kind = "big"
    # OSM buildings with no footprint on the map (the city layout drops large
    # roofs with ragged outlines) are put back from their outlines, trimmed
    # off the roads and the kept buildings.
    roads = K.roads_near(site, campus, 10.0)
    room = campus.buffer(-0.5, join_style="mitre")
    if roads is not None:
        room = room.difference(roads.buffer(K.ROAD_SETBACK_M))
    restored = []
    for g, p in sorted(osm_all, key=lambda t: -t[0].area):
        if g.area < RESTORE_MIN_M2 or not g.intersects(campus):
            continue
        covered = sum(g.intersection(k).area for k in kept + restored if k.intersects(g))
        if covered > 0.3 * g.area:
            continue
        part = g.intersection(room).difference(K.as_multi([k.buffer(1.0) for k in kept + restored]))
        part = kit.largest(part.buffer(-0.3, join_style="mitre").buffer(0.3, join_style="mitre"))
        if part is None or part.area < RESTORE_MIN_M2 or part.buffer(-2.5).is_empty:
            continue
        restored.append(part.simplify(0.2))
    for g in restored:
        b = bl.Building(g, float(site.sampler.value(g.centroid.x, g.centroid.y)), "big")
        site.buildings.append(b)
    stats["buildings_restored"] = len(restored)
    kept = kept + restored
    houses = K.as_multi(kept)

    roads_here = [(g, w, kind, line) for g, v, w, _, kind, line in site.full_layout["roads"]
                  if line is not None and not kind.startswith("rail:") and g.intersects(campus.buffer(8.0))]
    concrete = K.as_multi([g for g, *_ in roads_here])
    edge = LineString(campus.exterior.coords)
    gates = []
    for g, w, kind, line in roads_here:
        x = edge.intersection(line)
        for p in getattr(x, "geoms", [x]):
            if p.geom_type == "Point" and p.y > -PLAY_HALF_M + 5.0 and \
                    all(np.hypot(p.x - q[0], p.y - q[1]) > 15.0 for q in gates):
                gates.append((p.x, p.y))

    # The quad: the largest campus land with no building on it (nor an OSM
    # building outline); the main gate where it meets the street.
    free = campus.difference(K.as_multi([houses] + osm_roofs).buffer(8.0)).difference(concrete.buffer(2.0))
    parts = [g for g in K.style.polys(free) if g.area > QUAD_MIN_M2]
    quad = None
    if parts:
        quad = max(parts, key=lambda g: g.area)
        quad = kit.largest(quad.buffer(-2.0, join_style="mitre").simplify(0.5))
    main_gate = None
    if quad is not None:
        # The street: the road beside the quad that runs along the campus
        # edge the longest way; the gate faces the quad's middle on it.
        shut = edge.difference(LineString([(-PLAY_HALF_M - 10, -PLAY_HALF_M + 1.0),
                                           (PLAY_HALF_M + 10, -PLAY_HALF_M + 1.0)]).buffer(3.0))
        street = [(shut.intersection(g.buffer(4.0)).length, ln) for g, w, kind, ln in roads_here
                  if g.distance(quad) < 12.0 and w >= 3.0]
        if street:
            ln = max(street, key=lambda t: t[0])[1]
            qc = polylabel(quad, 0.5)
            p = ln.interpolate(ln.project(qc))
            e = edge.interpolate(edge.project(p))
            if e.distance(p) < 12.0:
                main_gate = (e.x, e.y)
    if main_gate is not None:
        gates = [g for g in gates if np.hypot(g[0] - main_gate[0], g[1] - main_gate[1]) > GATE_GAP_M] + [main_gate]
    stats["gates"] = len(gates)
    stats["main_gate"] = [round(main_gate[0], 1), round(main_gate[1], 1)] if main_gate is not None else None

    foot = K.osm_lines(site, lambda p: p.get("highway") in ("footway", "steps", "pedestrian", "corridor"), campus)
    paths = K.paths_geom([ln for ln, _ in foot], [2.4 for _ in foot]).difference(houses)
    lawn = campus.difference(houses.buffer(1.0)).difference(concrete.buffer(0.5)).difference(paths)
    if quad is not None:
        lawn = lawn.difference(quad.buffer(1.0))

    # Quad furniture.
    fountain = flags = None
    benches, lamps, trees = [], [], 0
    if quad is not None:
        fc = polylabel(quad, 0.5)
        fountain = (fc.x, fc.y, float(np.clip(quad.exterior.distance(fc) * 0.3, 2.5, 7.0)))
        if main_gate is not None:
            d = np.array([fc.x - main_gate[0], fc.y - main_gate[1]])
            n = np.hypot(*d) or 1.0
            d /= n
            flags = [(main_gate[0] + d[0] * 12.0 - d[1] * s * 7.0, main_gate[1] + d[1] * 12.0 + d[0] * s * 7.0)
                     for s in (-1, 0, 1)]
            flags = [f for f in flags if quad.contains(Point(f).buffer(1.0))]
        inset = kit.largest(quad.buffer(-3.0, join_style="mitre"))
        ring = LineString(inset.exterior.coords) if inset is not None else LineString()
        for t in np.arange(6.0, ring.length, 9.0):
            p = ring.interpolate(t)
            if main_gate is not None and p.distance(Point(main_gate)) < 14.0:
                continue
            trees += site.props.add("tree", p.x, p.y, rng.uniform(0, 6.28), (rng.uniform(8.0, 11.0),) * 2)
        fr = fountain[2]
        for k in range(8):
            a = 2 * np.pi * k / 8 + np.pi / 8
            r = fr + 6.0
            bx, by = fc.x + np.cos(a) * r, fc.y + np.sin(a) * r
            if quad.contains(Point(bx, by).buffer(1.2)):
                benches.append((bx, by, a + np.pi / 2))
            lx, ly = fc.x + np.cos(a + np.pi / 8) * (r + 3.0), fc.y + np.sin(a + np.pi / 8) * (r + 3.0)
            if quad.contains(Point(lx, ly).buffer(0.5)):
                lamps.append((lx, ly))
    taken = K.as_multi([houses.buffer(1.0), concrete.buffer(1.0), paths] + ([quad] if quad is not None else []))
    for x, y in K.free_spots(campus, taken.buffer(2.0), TREE_STEP_M, rng, clear=2.0):
        if rng.random() < 0.35:
            trees += site.props.add("tree", x, y, rng.uniform(0, 6.28), (rng.uniform(9.0, 13.0),) * 2)
    stats.update(trees=trees, benches=len(benches), quad=quad is not None)

    # Salvage: lab equipment by the two biggest faculty buildings, a
    # generator by the main gate.
    sources = []
    for fac in sorted(kept, key=lambda k: -k.area)[:2]:
        ring = LineString(fac.buffer(2.6, join_style="mitre").exterior.coords)
        for t in np.linspace(0, ring.length, 32, endpoint=False):
            p = ring.interpolate(t)
            q = ring.interpolate((t + 1.0) % ring.length)
            a = float(np.arctan2(q.y - p.y, q.x - p.x))
            g = K.rect_at(p.x, p.y, a, 3.2, 2.4)
            if campus.buffer(-1.0).contains(g) and not g.intersects(taken.difference(paths)):
                sources.append(("lab_equipment", p.x, p.y, a))
                taken = taken.union(g.buffer(2.0))
                break
    if main_gate is not None and quad is not None:
        fc = quad.centroid
        d = np.array([fc.x - main_gate[0], fc.y - main_gate[1]])
        d /= np.hypot(*d) or 1.0
        gx, gy = main_gate[0] + d[0] * 6.0 + d[1] * 13.0, main_gate[1] + d[1] * 6.0 - d[0] * 13.0
        if quad.contains(Point(gx, gy).buffer(2.5)):
            sources.append(("diesel_generator", gx, gy, float(np.arctan2(d[1], d[0]))))
    stats["sources"] = len(sources)

    seed = int(rng.integers(1 << 30))
    open_edge = LineString([(-PLAY_HALF_M - 10, -PLAY_HALF_M + 1.0), (PLAY_HALF_M + 10, -PLAY_HALF_M + 1.0)]).buffer(2.5)
    # The wall stops where it would run onto a building or across road
    # concrete (it runs along the streets close to their edge, so only
    # what reaches well onto the concrete counts); a side gate's piers move
    # out along the wall until they are off the road.
    wall_avoid = K.as_multi([houses, concrete.buffer(-0.5)])
    pier_avoid = K.as_multi([houses, concrete])

    def draw(L):
        r = np.random.default_rng(seed)
        K.lawn(L, lawn, r, 0.11, 0.5)
        K.gravel(L, paths.difference(concrete), 0.21, 0.9)
        if quad is not None:
            K.gravel(L, quad, 0.26, 0.95, 0.15)
            F = kit.Frame(quad)
            for x in np.arange(F.x0 + 4.0, F.x1, 4.0):
                L.line("groundlines", F.line([(x, F.y0), (x, F.y1)]).intersection(quad), 0.06, 0.18, 0.7)
            for y in np.arange(F.y0 + 4.0, F.y1, 4.0):
                L.line("groundlines", F.line([(F.x0, y), (F.x1, y)]).intersection(quad), 0.06, 0.18, 0.7)
            x, y, fr = fountain
            L.fill("groundlines", Point(x, y).buffer(fr + 1.4, quad_segs=8), 0.3)
            L.fill("groundlines", Point(x, y).buffer(fr, quad_segs=8), 0.13)
            L.strip("groundlines", LinearRing(Point(x, y).buffer(fr, quad_segs=8).exterior.coords), 1.2, +1, 0.5,
                    0.0)
            L.line("groundlines", Point(x, y).buffer(fr + 1.4, quad_segs=8).exterior, 0.14, K.STONE_EDGE_V)
            L.fill("interiors", Point(x, y).buffer(1.3, quad_segs=4), 0.3)
            L.fill("interiors", Point(x, y).buffer(0.6, quad_segs=3), 0.42)
            K.rocks(L, x, y, 4, r, fr * 0.4)
        parts = K.wall_parts(campus.exterior, [], GATE_GAP_M)
        parts = [q for p in parts for q in K.wall_parts(p, [g for g in gates if g != main_gate], SIDE_GATE_M)]
        if main_gate is not None:
            parts = [q for p in parts for q in K.wall_parts(p, [main_gate], GATE_GAP_M)]
        parts = [q for p in parts for q in getattr(p.difference(open_edge), "geoms", [p.difference(open_edge)])
                 if q.geom_type == "LineString" and q.length > 0.6]
        K.perimeter_wall(L, parts, 0.6, 0.3, pier_every=6.0, pier=1.0, avoid=wall_avoid)
        for g in gates:
            if g != main_gate:
                K.gate_piers(L, campus.exterior, g, SIDE_GATE_M, size=1.4, avoid=pier_avoid, slide=3.0)
        for x, y, a in benches:
            K.bench(L, x, y, a)
        for x, y in lamps:
            K.lamp_post(L, x, y)
        for kind, x, y, a in sources:
            if kind == "lab_equipment":
                K.cases(L, x, y, a, r)
                site.salvage.add(kind, x, y, a, 3.2, 2.4)
            else:
                equipment.add_source(site.salvage, L, kind, x, y, a, r)
        if main_gate is not None:
            a = K.ring_angle(campus.exterior, main_gate)
            P = K.local(main_gate[0], main_gate[1], a)
            for s in (-1, 1):
                px, py = P(s * (GATE_GAP_M / 2 + 1.3), 0.0)
                L.fill("interiors", K.cast(K.rect_at(px, py, a, 2.6, 2.6), 1.5), 0.0, 0.5)
                L.tall_prism(K.rect_at(px, py, a, 2.6, 2.6), 0.0, PYLON_H, 0.22, 0.36)
            L.tall_prism(K.rect_at(main_gate[0], main_gate[1], a, GATE_GAP_M + 5.2, 1.8), PYLON_H - 2.0,
                         PYLON_H - 0.4, 0.24, 0.4)
            L.tall_prism(K.rect_at(main_gate[0], main_gate[1], a, GATE_GAP_M + 6.4, 2.4), PYLON_H - 0.4,
                         PYLON_H + 0.3, 0.2, 0.3)
            for s in (-1, 1):
                px, py = P(s * (GATE_GAP_M / 2 + 1.3), 0.0)
                L.tall_prism(K.rect_at(px, py, a, 1.6, 1.6), PYLON_H + 0.3, PYLON_H + 1.6, 0.24, 0.42)
        if flags:
            fa = r.uniform(0, 2 * np.pi)
            for x, y in flags:
                L.fill("interiors", Point(x, y).buffer(0.7, quad_segs=3), 0.3)
                K.flagpole(L, x, y, 14.0, fa + r.normal(0, 0.2))
    site.drawers.append(draw)
    return stats
