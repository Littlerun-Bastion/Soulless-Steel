"""The Japanese Garden at its real place in Helwan: the street block south of
Sherif Street that holds the OSM "Japanese Garden Mosque", two ornamental
ponds, footbridges, steps up an artificial hill and a round plaza.

Built from the OSM data where it exists, so the garden reads as the real one:
  ponds          the OSM ponds, frozen: stone rims, dark ice, frost, cracks
  paths          the OSM footways (gravel), the paved east-west spine and the
                 round plaza; the OSM bridges as arched plank footbridges
  hill           the artificial hill the OSM steps climb, with a two-tier
                 pavilion on top (its upper roof in the talls, so it leans)
  pavilions      a round pavilion inside the small footway ring by the east
                 wall and water pavilions on the shores of both ponds, with
                 East-Asian hipped and pyramid roofs (buildings of their own
                 kinds, so they can be entered)
  statues        rows of seated Buddhas on plinths facing the spine, a large
                 Buddha in the round plaza; stone lanterns at the bridges,
                 gates, plaza and shores; rocks and bare trees round the ponds
  wall           a coped wall round the block with piers, a roofed gate where
                 the spine meets the street at each end and plain gates where
                 other paths leave
  gatehouse      the small OSM building at the west gate, where the spine
                 leaves the garden, kept with a hipped roof (it stands in for
                 that gate's roof)
  mosque         the OSM mosque kept as a building of its own kind (flat roof,
                 main dome) with a minaret in the talls, inside its footprint
                 at the corner nearest the street
  yard           a maintenance yard with a shed, a generator and a cable drum
                 on the free ground nearest the wall; a pump on the shore of
                 the largest pond (salvage sources)

The wall and everything in the garden but the buildings are drawn only:
mechas walk over the lawns, paths and the frozen ponds.
"""
import numpy as np
from shapely import prepare
from shapely.geometry import LinearRing, LineString, Point, Polygon, box
from shapely.ops import nearest_points, polylabel, unary_union

import buildings as bl
import equipment
import kit
import lmkit as K
import ruins

NAME = "Japanese Garden"
OWNER = "landmarks:japanese_garden"
# A point inside the garden's street block (between the two OSM ponds) and a
# box round the garden as the satellite image shows it; the box only guards
# against a block that runs on past the garden.
ANCHOR = (1880.0, -860.0)
BOX = (1750.0, -990.0, 2025.0, -720.0)
# The artificial hill: the OSM steps within HILL_REACH_M of this point climb
# it.
HILL_GUESS = (1848.0, -805.0)
HILL_REACH_M = 40.0
SEED = 9101

WALL_INSET_M = 1.5
GATE_GAP_M = 7.0
PATH_W = {"pedestrian": 5.0, "footway": 2.6, "path": 2.2, "steps": 2.8}
BRIDGE_W = 2.8
STATUE_STEP_M = 3.6
STATUE_OFF_M = 1.7
TREE_STEP_M = 10.0
TREE_CHANCE = 0.42
KIOSK_N = 8
MINARET_H = 30.0
MINARET_BASE_M = 3.4


def _kind(p):
    return p.get("highway")


def build(site, masks):
    blk = K.block_at(site, *ANCHOR)
    if blk is None:
        return {"built": False, "why": "no block"}
    blk = kit.largest(blk.intersection(box(*BOX)))
    garden = kit.largest(blk.buffer(-WALL_INSET_M, join_style="mitre"))
    if garden is None or garden.area < 20000:
        return {"built": False, "why": "block too small"}
    if not K.land_free(site, blk):
        return {"built": False, "why": "land not free (KeepOut, marker or claim)"}
    site.claim(blk, OWNER)
    site.add_landmark(NAME, "garden", garden)
    if not site.in_window(blk):
        return {"built": False, "why": "outside the window"}
    masks.append(blk)
    rng = K.seeded(SEED, *ANCHOR)
    stats = {"built": True}

    osm_bld = K.osm_polys(site, lambda p: "building" in p, blk)
    mosque_osm = [g for g, p in osm_bld if p.get("building") == "mosque"]
    # The real buildings in the block (the mosque and the gatehouse), from
    # the whole map's roofs.
    real_osm = [g for g, p in osm_bld if g.area >= 60.0]
    fixed = [g for g in K.big_roofs_in(site, blk) if blk.contains(g.centroid) and K.is_osm_poly(g, real_osm)]
    mosque_poly = next((g for g in fixed if mosque_osm and K.is_osm_poly(g, mosque_osm)), None)
    lodges = [g for g in fixed if g is not mosque_poly and g.area < 400.0]
    fixed = ([mosque_poly] if mosque_poly is not None else []) + lodges
    ponds = [g.intersection(garden) for g, p in K.osm_polys(site, lambda p: p.get("natural") == "water", garden)]
    ponds = [g for g in ponds if not g.is_empty and g.area > 100]
    plaza = [g for g, p in K.osm_polys(site, lambda p: p.get("highway") == "pedestrian" and p.get("area") == "yes",
                                       garden)]
    lines = K.osm_lines(site, lambda p: _kind(p) in PATH_W, garden.buffer(6.0))
    bridges = [ln for ln, p in lines if p.get("bridge") == "yes"]
    walks = [(ln, p) for ln, p in lines if p.get("bridge") != "yes"]
    spine = [ln for ln, p in walks if _kind(p) == "pedestrian" and ln.length > 60]
    stair = [ln for ln, p in walks if _kind(p) == "steps"]

    # Land: everything the district modules or the city layout put in the
    # block goes, except the real mosque and gatehouse.
    site.clear_area(blk)
    keep_ids = {id(g) for g in fixed}
    removed = K.drop_buildings(site, blk, keep=lambda b: id(b.poly) in keep_ids)
    removed += site.remove_buildings_touching(garden, kinds=("house",), margin=0.0)
    stats["buildings_removed"] = removed
    site.solid_extra.append(garden)
    mosque, *lodge_b = K.standing(site, fixed) if mosque_poly is not None else [None] + K.standing(site, lodges)
    fixed_geom = K.as_multi(fixed)
    fixed_pad = fixed_geom.buffer(3.0)

    water = K.as_multi([g.buffer(1.2) for g in ponds])
    walk_geom = K.paths_geom([ln for ln, _ in walks], [PATH_W[_kind(p)] for _, p in walks])
    walk_geom = K.as_multi([walk_geom] + plaza).difference(water.buffer(-1.2))
    bridge_geom = K.as_multi([ln.buffer(BRIDGE_W / 2 + 0.4, cap_style="flat") for ln in bridges])

    # The hill and its pavilion.
    hill = None
    near = [ln for ln in stair if ln.distance(Point(*HILL_GUESS)) < HILL_REACH_M]
    if near:
        c = unary_union([ln.centroid for ln in near]).centroid
        r = float(np.mean([ln.centroid.distance(c) for ln in near])) + 7.0
        hill = (c.x, c.y, r)

    new_buildings = []

    def pin_state(b, intact=0.7):
        # The draw is made whether or not the building stands in this run
        # (a window run), so the draws after it do not shift.
        state = ruins.INTACT if rng.random() < intact else ruins.DAMAGED
        if b is not None:
            b.opts["state"] = state

    # The gatehouse gets a hipped roof over its outline's rectangle.
    for g, b in zip(lodges, lodge_b):
        frame = K.rect_frame(g)
        pin_state(b)
        if b is not None:
            b.kind = "lm_pavilion"
            b.opts["frame"] = frame

    mv = float(site.sampler.value(*ANCHOR))
    if hill is not None:
        hx, hy, _ = hill
        for kr in (5.4, 5.0):
            g = K.ngon(hx, hy, kr, KIOSK_N, np.pi / KIOSK_N)
            if garden.contains(g) and not g.buffer(0.3).intersects(water) and not g.intersects(bridge_geom) and \
                    not g.intersects(fixed_pad):
                b = bl.Building(g, mv, "lm_kiosk", kiosk=(hx, hy, kr, KIOSK_N, np.pi / KIOSK_N), tier=True)
                pin_state(b)
                new_buildings.append(b)
                break
    # Round pavilions inside the small closed footway rings where one of at
    # least 62 m2 fits (a building must be 60 m2 or more); a lantern marks
    # the centre of the smaller rings.
    rings = []
    for ln, p in walks:
        closed = Point(ln.coords[0]).distance(Point(ln.coords[-1])) < 0.5 and len(ln.coords) > 4
        if _kind(p) == "footway" and closed and ln.length < 70:
            c = Polygon(ln.coords).centroid
            rr = float(np.mean([Point(q).distance(c) for q in ln.coords]))
            rings.append((c.x, c.y, rr))
    rings_used = []
    for rx, ry, rr in rings:
        if any(g.buffer(2.0).contains(Point(rx, ry)) for g in plaza):
            continue
        kr = rr - PATH_W["footway"] / 2 - 0.2
        g = K.ngon(rx, ry, kr, KIOSK_N, np.pi / KIOSK_N)
        if g.area >= 62 and garden.contains(g) and not any(g.intersects(t) for t in (water, bridge_geom, fixed_pad)):
            b = bl.Building(g, mv, "lm_kiosk", kiosk=(rx, ry, kr, KIOSK_N, np.pi / KIOSK_N), tier=False)
            pin_state(b)
            new_buildings.append(b)
        else:
            rings_used.append((rx, ry, rr))
    # Water pavilions: on each pond's shore, half over the ice, along the
    # shore line, on the side nearest the spine.
    spine_line = spine[0] if spine else None
    pavilions = 0
    for pond in sorted(ponds, key=lambda g: -g.area):
        ring = LineString(pond.exterior.coords)
        cand = []
        for t in np.linspace(0, ring.length, 60, endpoint=False):
            p = ring.interpolate(t)
            q = ring.interpolate((t + 2.0) % ring.length)
            a = float(np.arctan2(q.y - p.y, q.x - p.x))
            score = spine_line.distance(p) if spine_line is not None else 0.0
            cand.append((score, p.x, p.y, a))
        cand.sort()
        L_, D_ = (12.0, 7.0) if pond.area > 2000 else (10.0, 6.5)
        for _, px, py, a in cand:
            nx, ny = -np.sin(a), np.cos(a)
            for side in (1, -1):
                cx, cy = px + nx * side * 1.2, py + ny * side * 1.2
                g = K.rect_at(cx, cy, a, L_, D_)
                wet = g.intersection(pond).area / g.area
                if not 0.25 < wet < 0.6:
                    continue
                gg = g.buffer(0.8)
                if not garden.contains(gg) or gg.intersects(walk_geom) or gg.intersects(bridge_geom):
                    continue
                if any(gg.intersects(nb.poly.buffer(2.0)) for nb in new_buildings):
                    continue
                if gg.intersects(fixed_pad):
                    continue
                b = bl.Building(g, mv, "lm_pavilion", frame=(cx, cy, a, L_, D_))
                pin_state(b)
                new_buildings.append(b)
                pavilions += 1
                break
            else:
                continue
            break
    stats["pavilions"] = pavilions
    stats["kiosks"] = sum(1 for b in new_buildings if b.kind == "lm_kiosk")

    # The mosque: its own roof (main dome, entrance dome) and a minaret
    # inside its footprint at the corner nearest the street.
    minaret_at = None
    if mosque_poly is not None:
        mp = mosque_poly
        # The main dome sits on the widest part of the prayer hall: the
        # centre of the largest circle inside the footprint.
        c = polylabel(mp, 0.2)
        dr = min(mp.exterior.distance(c) - 0.9, 6.5)
        dome = None
        if dr > 1.8:
            dome = (c.x, c.y, dr)
            rest = mp.difference(Point(c.x, c.y).buffer(dr + 1.5))
            small = []
            if not rest.is_empty:
                part = kit.largest(rest)
                sc = polylabel(part, 0.2)
                sr = min(part.exterior.distance(sc) - 0.6, 2.2)
                if sr > 1.0:
                    small = [(sc.x, sc.y, sr)]
            if mosque is not None:
                mosque.kind = "lm_mosque"
                mosque.opts.update(dome=dome, small_domes=small)
        pin_state(mosque, 0.65)
        # The minaret's base square (MINARET_BASE_M a side, any way round)
        # fits inside the footprint, clear of the main dome, as near the
        # chosen corner as it can.
        room = mp.buffer(-MINARET_BASE_M * 0.72)
        if dome is not None:
            room = room.difference(Point(dome[0], dome[1]).buffer(dome[2] + MINARET_BASE_M * 0.75))
        roads = K.roads_near(site, mp, 30.0)
        corners = np.asarray(mp.exterior.coords)[:-1]
        k = int(np.argmin([Point(*q).distance(roads) for q in corners])) if roads is not None else 0
        if not room.is_empty:
            q = nearest_points(room, Point(*corners[k]))[0]
            minaret_at = (q.x, q.y)

    # Statues: rows of seated Buddhas either side of the spine, facing it.
    statues = []
    if spine_line is not None:
        w = PATH_W["pedestrian"] / 2 + STATUE_OFF_M
        others = K.as_multi([ln.buffer(PATH_W[_kind(p)] / 2 + 0.6) for ln, p in walks if ln is not spine_line]
                            + plaza)
        block_s = K.as_multi([water.buffer(0.6), bridge_geom, others] + [b.poly.buffer(1.5) for b in new_buildings]
                             + [fixed_geom.buffer(1.5)]
                             + ([Point(hill[0], hill[1]).buffer(hill[2])] if hill else []))
        prepare(block_s)
        for t in np.arange(STATUE_STEP_M, spine_line.length - STATUE_STEP_M, STATUE_STEP_M):
            p = spine_line.interpolate(t)
            q = spine_line.interpolate(t + 1.0)
            a = float(np.arctan2(q.y - p.y, q.x - p.x))
            nx, ny = -np.sin(a), np.cos(a)
            for side in (1, -1):
                sx, sy = p.x + nx * side * w, p.y + ny * side * w
                foot = K.rect_at(sx, sy, a, 2.0, 2.0)
                if not garden.contains(foot.buffer(1.0)) or block_s.intersects(foot):
                    continue
                statues.append((sx, sy, a - side * np.pi / 2))
    big_buddha = None
    if plaza:
        c = plaza[0].centroid
        to_centre = np.arctan2(garden.centroid.y - c.y, garden.centroid.x - c.x)
        big_buddha = (c.x, c.y, float(to_centre))
    stats["statues"] = len(statues) + (1 if big_buddha else 0)

    # Lanterns: at bridge ends, gates, round the plaza and the small rings,
    # and along the pond shores.
    gates = K.gate_points(garden.exterior, [ln for ln, _ in walks], cluster=14.0)
    lanterns = []
    occupied = K.as_multi([water, walk_geom, bridge_geom] + [b.poly.buffer(1.0) for b in new_buildings]
                          + [K.rect_at(x, y, a, 2.2, 2.2) for x, y, a in statues]
                          + [fixed_geom.buffer(1.0)])

    def add_lantern(x, y, need=1.0):
        g = Point(x, y).buffer(need)
        if garden.buffer(-1.0).contains(g) and not occupied.intersects(g) and \
                all(np.hypot(x - lx, y - ly) > 3.0 for lx, ly in lanterns):
            lanterns.append((x, y))
            return True
        return False

    for ln in bridges:
        for end in (ln.coords[0], ln.coords[-1]):
            for a in np.linspace(0, 2 * np.pi, 8, endpoint=False):
                if add_lantern(end[0] + np.cos(a) * 2.8, end[1] + np.sin(a) * 2.8):
                    break
    for gx, gy in gates:
        c = garden.centroid
        d = np.array([c.x - gx, c.y - gy])
        d /= np.hypot(*d) or 1.0
        for s in (-1, 1):
            add_lantern(gx + d[0] * 5.0 - d[1] * s * 5.0, gy + d[1] * 5.0 + d[0] * s * 5.0)
    for g in plaza:
        c = g.centroid
        rr = np.sqrt(g.area / np.pi) + 1.8
        for a in np.linspace(0, 2 * np.pi, 6, endpoint=False):
            add_lantern(c.x + np.cos(a) * rr, c.y + np.sin(a) * rr)
    for rx, ry, rr in rings_used:
        add_lantern(rx, ry, 0.8)
    for pond in ponds:
        ring = LineString(pond.buffer(3.2).exterior.coords)
        for t in np.arange(8.0, ring.length, 22.0):
            p = ring.interpolate(t)
            add_lantern(p.x, p.y)
    stats["lanterns"] = len(lanterns)

    # Rock groups on the shores.
    rock_spots = []
    for pond in ponds:
        ring = LineString(pond.buffer(3.0).exterior.coords)
        for t in np.arange(rng.uniform(0, 15), ring.length, 31.0):
            p = ring.interpolate(t)
            if not occupied.intersects(p.buffer(2.0)) and garden.contains(p.buffer(3.0)):
                rock_spots.append((p.x, p.y))

    # The maintenance yard on the free ground nearest the wall, with a shed,
    # a generator and a cable drum; a pump on the shore of the largest pond.
    yard = None
    occupied2 = K.as_multi([occupied] + [Point(x, y).buffer(1.5) for x, y in lanterns]
                           + ([Point(hill[0], hill[1]).buffer(hill[2])] if hill else []))
    F = kit.Frame(garden)
    inner = garden.buffer(-1.0)
    edge = LineString(garden.exterior.coords)
    grid = [(x, y) for x in np.arange(garden.bounds[0], garden.bounds[2], 3.0)
            for y in np.arange(garden.bounds[1], garden.bounds[3], 3.0)]
    grid.sort(key=lambda q: edge.distance(Point(q)))
    if minaret_at is not None:
        occupied2 = occupied2.union(Point(*minaret_at).buffer(4.0))
    yard = K.find_rect(grid, 18.0, 11.0, F.rad, inner, occupied2)
    beds = []
    if yard is not None:
        occupied2 = occupied2.union(K.rect_at(yard[0], yard[1], yard[2], 20.0, 13.0))
    centre = garden.centroid
    grid.sort(key=lambda q: Point(q).distance(centre))
    for _ in range(2):
        bed = K.find_rect(grid, 15.0, 8.0, F.rad, inner, occupied2.union(walk_geom.buffer(1.5)))
        if bed is None:
            break
        beds.append(bed)
        occupied2 = occupied2.union(K.rect_at(bed[0], bed[1], bed[2], 30.0, 22.0))
    stats["raked_beds"] = len(beds)
    sources = []
    if yard is not None:
        yx, yy, ya = yard
        P = K.local(yx, yy, ya)
        shed = K.rect_at(*P(-3.5, -0.8), ya, 10.0, 7.0)
        b = bl.Building(shed, mv, "house")
        new_buildings.append(b)
        sources.append(("diesel_generator",) + P(5.0, -2.5) + (ya,))
        sources.append(("cable_drum",) + P(5.5, 2.6) + (ya,))
    pump_at = None
    if ponds:
        pond = max(ponds, key=lambda g: g.area)
        ring = LineString(pond.buffer(3.4).exterior.coords)
        for t in np.linspace(0, ring.length, 48, endpoint=False):
            p = ring.interpolate(t)
            q = ring.interpolate((t + 1.0) % ring.length)
            g = K.rect_at(p.x, p.y, np.arctan2(q.y - p.y, q.x - p.x), 3.6, 2.4)
            if garden.contains(g) and not occupied2.intersects(g) and not any(
                    g.intersects(b.poly.buffer(1.0)) for b in new_buildings):
                pump_at = (p.x, p.y, float(np.arctan2(q.y - p.y, q.x - p.x)))
                break
    if pump_at is not None:
        sources.append(("industrial_pump",) + pump_at)
    stats["sources"] = len(sources)

    # Trees and bushes on the lawns.
    blocked = K.as_multi([occupied2.buffer(2.0), walk_geom.buffer(1.0)]
                         + [b.poly.buffer(4.0) for b in new_buildings]
                         + ([K.rect_at(yard[0], yard[1], yard[2], 20, 13)] if yard else [])
                         + [K.rect_at(x, y, a, 17, 10) for x, y, a in beds])
    trees = 0
    for x, y in K.free_spots(garden, blocked, TREE_STEP_M, rng, clear=1.5):
        if rng.random() < TREE_CHANCE and site.props.add("tree", x, y, rng.uniform(0, 2 * np.pi),
                                                        (rng.uniform(8.0, 12.5),) * 2):
            trees += 1
    bushes = 0
    for pond in ponds:
        ring = LineString(pond.buffer(4.5).exterior.coords)
        for t in np.arange(rng.uniform(0, 6), ring.length, 7.0):
            p = ring.interpolate(t)
            if rng.random() < 0.55 and not blocked.contains(p) and garden.contains(p.buffer(2.0)):
                bushes += site.props.add("bush", p.x, p.y, rng.uniform(0, 2 * np.pi), (rng.uniform(1.8, 3.2),) * 2)
    stats.update(trees=trees, bushes=bushes)

    for b in new_buildings:
        site.buildings.append(b)
    stats["buildings_added"] = len(new_buildings)

    wall_cut = fixed_geom.buffer(0.8) if fixed else None
    spine_ends = []
    lodge_geom = K.as_multi(lodges)
    if spine_line is not None:
        for end in (spine_line.coords[0], spine_line.coords[-1]):
            g = min(gates, key=lambda q: np.hypot(q[0] - end[0], q[1] - end[1])) if gates else None
            if g is not None and np.hypot(g[0] - end[0], g[1] - end[1]) < 15 and \
                    (lodge_geom.is_empty or lodge_geom.distance(Point(g)) > GATE_GAP_M):
                spine_ends.append(g)
    seed = int(rng.integers(1 << 30))
    kiosks = [b for b in new_buildings if b.kind == "lm_kiosk" and b.opts.get("tier")]

    # The OSM footways and the plaza run on past the gates onto the street;
    # their paving stops at the street block's edge and off the road
    # concrete. Gate piers stay off the buildings (the gatehouse stands in
    # for its gate) and the street; a gate roof moves into the garden until
    # its eaves and corner tips are off the street.
    street = K.roads_near(site, blk, 12.0)
    ground = blk if street is None else blk.difference(street)
    paved_walks = walk_geom.difference(K.as_multi(plaza)).intersection(ground)
    paved_plaza = [g.intersection(ground) for g in plaza]
    built = K.as_multi([fixed_geom] + [b.poly for b in new_buildings])
    pier_avoid = built if street is None else K.as_multi([built, street])
    gate_roofs = []
    for g in spine_ends:
        a = K.ring_angle(garden.exterior, g)
        nx, ny = -np.sin(a), np.cos(a)
        if not garden.contains(Point(g[0] + nx, g[1] + ny)):
            nx, ny = -nx, -ny
        length, depth = GATE_GAP_M + 4.2, 4.2
        tip = min(1.0, depth * 0.14)
        for s in np.arange(0.0, depth / 2 + 0.01, 0.25):
            x, y = g[0] + nx * s, g[1] + ny * s
            if street is None or not K.rect_at(x, y, a, length + 2 * tip, depth + 2 * tip).intersects(street):
                break
        gate_roofs.append((x, y, a, length, depth))

    def draw(L):
        r = np.random.default_rng(seed)
        K.lawn(L, garden, r)
        if hill is not None:
            K.hill(L, hill[0], hill[1], hill[2], r)
        for pond in ponds:
            K.frozen_pond(L, pond, r)
        K.gravel(L, paved_walks, K.GRAVEL_V)
        for g, pg in zip(plaza, paved_plaza):
            K.gravel(L, pg, 0.25, 0.95, 0.14)
            c = g.centroid
            for rr in (np.sqrt(g.area / np.pi) * 0.55,):
                L.line("groundlines", Point(c.x, c.y).buffer(rr, quad_segs=8).exterior, 0.25, 0.3, 0.8)
        for ln in stair:
            K.steps(L, ln, PATH_W["steps"])
        for ln in bridges:
            K.bridge(L, ln, BRIDGE_W, r)
        if yard is not None:
            K.gravel(L, K.rect_at(yard[0], yard[1], yard[2], 18.0, 11.0), 0.18, 0.9)
        for x, y, a in beds:
            K.raked_bed(L, x, y, a, 15.0, 8.0, r)
        for x, y in rock_spots:
            K.rocks(L, x, y, int(r.integers(3, 6)), r, 1.6)
        for x, y, a in statues:
            K.buddha(L, x, y, a, 1.0)
        if big_buddha is not None:
            x, y, a = big_buddha
            L.fill("interiors", K.cast(Point(x, y).buffer(4.4, quad_segs=6), 1.8), 0.0, 0.5)
            L.fill("interiors", K.ngon(x, y, 4.3, 8, np.pi / 8), 0.17)
            L.fill("interiors", K.ngon(x, y, 3.7, 8, np.pi / 8), 0.21)
            L.line("interiors", LinearRing(K.ngon(x, y, 4.3, 8, np.pi / 8).exterior.coords), 0.12, 0.36)
            K.buddha(L, x, y, a, 3.6, plinth=False)
        for x, y in lanterns:
            K.lantern(L, x, y, r.uniform(0, np.pi))
        parts = K.wall_parts(garden.exterior, gates, GATE_GAP_M, wall_cut)
        K.perimeter_wall(L, parts, 0.55, 0.3)
        for g in gates:
            K.gate_piers(L, garden.exterior, g, GATE_GAP_M, size=1.4, avoid=pier_avoid)
        for x, y, a, length, depth in gate_roofs:
            K.gate_roof(L, x, y, a, length, depth, 0.1)
        for kind, x, y, a in sources:
            equipment.add_source(site.salvage, L, kind, x, y, a, r)
        for b in kiosks:
            x, y, kr, n, rot = b.opts["kiosk"]
            K.pagoda_tier(L, x, y, kr * 0.46, kr * 0.7, 4.6, 6.6, 9.2, 0.19, n, rot)
        if minaret_at is not None:
            K.minaret(L, minaret_at[0], minaret_at[1], MINARET_H, MINARET_BASE_M)
    site.drawers.append(draw)
    stats["gates"] = len(gates)
    stats["gatehouses"] = len(lodges)
    stats["minaret"] = minaret_at is not None
    return stats
