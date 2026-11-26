"""Helwan Court at its real place: the OSM courthouse (amenity=courthouse,
"Helwan Court of First Instance") on Sherif Street, across the street from
the Japanese Garden's west wall.

The precinct is the building, a strip round it and its forecourt out to the
street its address names (the OSM street of that name; the nearest street
if there is none); the generated houses there go, the rest of the street
block stays as it is.

  court      the OSM building kept, a colonnade of light columns along its
             front, broad steps down to a paved forecourt that runs to the
             street, two flagpoles (talls), iron railings along the street
             with a gate and a guard hut, wrecked and parked cars
  yard       a generator against the back of the building
"""
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

import district_life
import equipment
import kit
import lmkit as K
import props

NAME = "Helwan Court"
OWNER = "landmarks:court"
SEED = 9501
COLUMN_STEP_M = 3.2
FLAG_H = 13.0
AROUND_M = 6.0
MAX_DEPTH_M = 45.0


def _is_court(p):
    return p.get("amenity") == "courthouse"


def build(site, masks):
    found = K.osm_polys(site, _is_court)
    if not found:
        return {"built": False, "why": "no courthouse in OSM"}
    court, tags = max(found, key=lambda t: t[0].area)
    c = court.centroid
    blk = K.block_at(site, c.x, c.y)
    if blk is None:
        return {"built": False, "why": "no block"}
    land = kit.largest(blk.buffer(-1.0, join_style="mitre"))

    # The front: the side of the building facing the street of its address.
    named = K.osm_lines(site, lambda p: p.get("name") and p.get("name") == tags.get("addr:street"),
                        court.buffer(150.0))
    target = unary_union([ln for ln, _ in named]) if named else K.roads_near(site, court, 60.0)
    if target is None or target.is_empty:
        return {"built": False, "why": "no street"}
    F = kit.Frame(court)
    sides = []
    for s, (x0, y0, x1, y1) in ((-1, (F.x0, F.y0, F.x1, F.y0)), (1, (F.x0, F.y1, F.x1, F.y1)),
                                (-2, (F.x0, F.y0, F.x0, F.y1)), (2, (F.x1, F.y0, F.x1, F.y1))):
        mid = Point(*F.pt((x0 + x1) / 2, (y0 + y1) / 2))
        sides.append((mid.distance(target), s, (x0, y0, x1, y1)))
    _, front, (fx0, fy0, fx1, fy1) = min(sides)
    if abs(front) == 1:
        sign, along, base = float(front), (fx0, fx1), fy0
    else:
        sign, along, base = float(np.sign(front)), (fy0, fy1), fx0

    def at(u, w):
        """Local point: u along the front, w out from the facade."""
        return F.pt(u, base + sign * w) if abs(front) == 1 else F.pt(base + sign * w, u)

    mid = (along[0] + along[1]) / 2
    half = (along[1] - along[0]) / 2 + 4.0
    zone = Polygon([at(mid - half, 0.0), at(mid + half, 0.0), at(mid + half, MAX_DEPTH_M),
                    at(mid - half, MAX_DEPTH_M)])
    precinct = kit.largest(K.as_multi([zone, court.buffer(AROUND_M, join_style="mitre")]).intersection(land))
    if precinct is None:
        return {"built": False, "why": "no land"}
    if not K.land_free(site, precinct):
        return {"built": False, "why": "land not free (KeepOut, marker or claim)"}
    site.claim(precinct, OWNER)
    site.add_landmark(NAME, "court", precinct)
    if not site.in_window(precinct):
        return {"built": False, "why": "outside the window"}
    masks.append(precinct)
    rng = K.seeded(SEED, c.x, c.y)
    stats = {"built": True}
    site.clear_area(precinct)
    osm_roofs = [g for g, p in K.osm_polys(site, lambda p: "building" in p, precinct.buffer(10.0))]

    def real(b):
        return b.opts.get("stage") == "osm roofs" and K.is_osm_roof(b, osm_roofs)
    stats["buildings_removed"] = K.drop_buildings(site, precinct, keep=real) + \
        site.remove_buildings_touching(precinct, kinds=("house",), margin=0.5)
    site.solid_extra.append(precinct)
    # The buildings left on the precinct, from the whole map's roofs (a
    # window run lays it out as the full run does).
    houses = K.as_multi(K.kept_roofs(site, precinct, osm_roofs))
    forecourt = kit.largest(zone.intersection(land).difference(houses.buffer(0.3)))

    cols = [at(u, 1.6) for u in np.arange(along[0] + 2.0, along[1] - 1.0, COLUMN_STEP_M)]
    steps_band = [LineString([at(along[0] + 3.0, 3.2 + k * 0.5), at(along[1] - 3.0, 3.2 + k * 0.5)])
                  for k in range(6)]
    flags = [at(mid - 8.0, 12.0), at(mid + 8.0, 12.0)]
    flags = [f for f in flags if forecourt is not None and forecourt.contains(Point(f).buffer(1.0))]
    ring = LineString(precinct.exterior.coords)
    edge = land.exterior
    open_ring = ring.difference(court.buffer(AROUND_M + 0.5))
    railing = [g for g in getattr(open_ring, "geoms", [open_ring])
               if g.geom_type == "LineString" and g.length > 2.0 and g.distance(edge) < 1.5]
    gate_pt = ring.interpolate(ring.project(Point(at(mid, MAX_DEPTH_M))))
    gate = (gate_pt.x, gate_pt.y)
    railing = [q for g in railing for q in K.wall_parts(g, [gate], 8.0)]

    wrecks = cars = 0
    if forecourt is not None:
        for _ in range(2):
            v, size = props.pick_vehicle("vehicle_wreck", rng)
            px, py = at(mid + rng.uniform(-12, 12), rng.uniform(14, 26))
            if forecourt.contains(Point(px, py).buffer(2.5)) and site.props.clear_of(px, py, size[0] / 2):
                wrecks += site.props.add("vehicle_wreck", px, py, rng.uniform(0, 2 * np.pi), size, v)
        for k in range(4):
            u = mid - half + 3.0 + k * 2.8
            px, py = at(u, 20.0)
            if rng.random() < 0.7 and forecourt.contains(Point(px, py).buffer(2.4)):
                v, size = props.pick_vehicle("vehicle", rng)
                if site.props.clear_of(px, py, size[0] / 2 - 0.2):
                    cars += props.add_vehicle(site.props, site.salvage, "vehicle", px, py,
                                              F.rad + (np.pi / 2 if abs(front) == 1 else 0.0) + rng.normal(0, 0.05),
                                              size, v)
        gv, gsize = district_life.variant_of("hut", "guard")
        hx, hy = at(mid + 7.5, 32.0)
        if gv >= 0 and forecourt.contains(Point(hx, hy).buffer(1.6)):
            site.props.add("hut", hx, hy, F.rad, gsize, gv)
    stats.update(cars=cars, wrecks=wrecks, columns=len(cols))
    gen = None
    back = court.buffer(AROUND_M / 2 + 0.6, join_style="mitre").exterior
    for t in np.linspace(0, back.length, 32, endpoint=False):
        p = back.interpolate(t)
        q = back.interpolate((t + 1.0) % back.length)
        a = float(np.arctan2(q.y - p.y, q.x - p.x))
        g = K.rect_at(p.x, p.y, a, 3.6, 2.0)
        if precinct.contains(g) and not g.intersects(houses) and \
                (forecourt is None or not g.intersects(forecourt.buffer(2.0))):
            gen = (p.x, p.y, a)
            break
    stats["sources"] = 1 if gen else 0
    seed = int(rng.integers(1 << 30))

    def draw(L):
        r = np.random.default_rng(seed)
        K.gravel(L, precinct.difference(forecourt) if forecourt is not None else precinct, 0.2, 0.85)
        if forecourt is not None:
            K.gravel(L, forecourt, 0.27, 0.95, 0.15)
            Ff = kit.Frame(forecourt)
            for x in np.arange(Ff.x0 + 3.0, Ff.x1, 3.0):
                L.line("groundlines", Ff.line([(x, Ff.y0), (x, Ff.y1)]).intersection(forecourt), 0.05, 0.2, 0.7)
            for y in np.arange(Ff.y0 + 3.0, Ff.y1, 3.0):
                L.line("groundlines", Ff.line([(Ff.x0, y), (Ff.x1, y)]).intersection(forecourt), 0.05, 0.2, 0.7)
        for ln in steps_band:
            L.line("groundlines", ln, 0.5, 0.31)
            L.line("groundlines", ln.offset_curve(0.25), 0.06, 0.12, 0.8)
        for x, y in cols:
            L.fill("interiors", K.cast(Point(x, y).buffer(0.55, quad_segs=3), 0.9), 0.0, 0.5)
            L.fill("interiors", Point(x, y).buffer(0.55, quad_segs=3), 0.4)
            L.fill("interiors", Point(x + K.LIGHT[0] * 0.12, y + K.LIGHT[1] * 0.12).buffer(0.3, quad_segs=2), 0.5)
        if len(cols) > 1:
            L.line("interiors", LineString(cols), 0.2, 0.34, 0.6)
        # Iron railings on a low stone plinth with piers.
        K.perimeter_wall(L, railing, 0.45, 0.3, pier_every=3.2, pier=0.75)
        for q in railing:
            kit.fence(L, q, r, v=0.44, post_every=1.2)
        K.gate_piers(L, precinct.exterior, gate, 8.0, size=1.3)
        for x, y in flags:
            L.fill("interiors", Point(x, y).buffer(0.8, quad_segs=3), 0.32)
            K.flagpole(L, x, y, FLAG_H, F.rad + r.normal(0, 0.3))
        if gen is not None:
            equipment.add_source(site.salvage, L, "diesel_generator", gen[0], gen[1], gen[2], r)
    site.drawers.append(draw)
    return stats
