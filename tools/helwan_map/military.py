"""Military content: the places the tank, military_vehicle and relay_mast
salvage sources come from (section 13.3 of the districts brief). Energetics
come almost only from these, so they are rare and spread out.

  military sites  fenced compounds with rows of parked tanks, APCs and
                  military trucks, sandbag rings and sometimes a relay mast:
                  the airfield's hangar area (OSM hangars), and
                  EXTRA_SITES more on open ground in the play area
  checkpoints     CHECKPOINTS junctions of main roads, spread out: one or two
                  APCs or trucks askew, sometimes a tank, sandbag walls and a
                  barrier pole
  roadblocks      ROADBLOCKS points on main roads: a tank across the road
                  with car wrecks round it
  convoys         CONVOYS lines of 3 to 6 military trucks and APCs stopped in
                  a lane of a main road
  relay masts     on the highest open ground (the brightest bare rock in the
                  reference image) and at some military sites (RELAY_MASTS
                  in all)

Every military vehicle is a VehicleField vehicle (prop kind "military") and
a salvage source at the same spot: "tank" for tanks, "military_vehicle" for
the others.
"""
import numpy as np
from shapely.geometry import LineString, MultiPoint, Point, box
from shapely.ops import unary_union

import district_life
import equipment
import kit
import props
import ruins
from frame import PLAY_HALF_M
from gen_city import block_rng, to_frame_m
from zones import OPEN

EXTRA_SITES = 2
## Most vehicles parked at one military site.
SITE_VEHICLES = 16
CHECKPOINTS = 8
ROADBLOCKS = 4
CONVOYS = 3
RELAY_MASTS = 4
SITE_SIZE_M = ((110.0, 150.0), (80.0, 110.0))
MAIN = {"trunk", "secondary"}


def military_variants(source):
    """Indices of the military sprites that are this source kind."""
    cat = props.CATALOGUE.get("military", [])
    return [i for i, e in enumerate(cat) if e.get("source") == source]


def park(site, kind_source, x, y, ang, rng):
    cat = props.CATALOGUE.get("military", [])
    vs = military_variants(kind_source)
    if not cat or not vs:
        return False
    v = int(rng.choice(vs))
    e = cat[v]
    size = (e["length_m"], e["width_m"])
    if not site.props.clear_of(x, y, size[0] / 2):
        return False
    return props.add_vehicle(site.props, site.salvage, "military", x, y, ang, size, v)


def sandbags(L, line, rng):
    """A sandbag wall along a line: a row of rounded bags."""
    L.line("interiors", line, 1.1, 0.0, 0.35)
    d = 0.0
    while d < line.length:
        p = line.interpolate(d)
        L.fill("interiors", Point(p.x, p.y).buffer(0.45, quad_segs=2), rng.uniform(0.22, 0.3))
        d += 0.75
    L.line("interiors", line, 0.08, 0.38, 0.6)


def sandbag_ring(L, x, y, r, rng):
    a = np.linspace(0.3, 2 * np.pi - 0.3, 14)
    sandbags(L, LineString(np.stack([x + np.cos(a) * r, y + np.sin(a) * r], 1)), rng)


def camp(site, area, F, rng, rings):
    """The small things of a military site: rows of tents (huts that break
    like market stalls) along the far edge, and crates, jerrycans, tyres and
    sandbag stacks along the fence and by the vehicle rows."""
    made = site.stats.setdefault("military_camp", {"tents": 0, "clutter": 0})
    tent = district_life.variant_of("hut", "tent")
    x = F.x0 + 6.0
    y = F.y1 - 5.0
    while x < F.x1 - 30.0 and tent[0] >= 0:
        px, py = F.pt(x, y)
        if area.contains(Point(px, py).buffer(4.0)) and all(np.hypot(px - rx, py - ry) > 6.0 for rx, ry in rings) and                 site.props.clear_of(px, py, 3.0):
            ruin = ruins.state_at(px, py, 0) >= ruins.GUTTED
            v, size = district_life.variant_of("hut", "tent", ruin)
            made["tents"] += site.props.add("hut", px, py, F.rad, size, v)
        x += rng.uniform(6.5, 8.0)
    for _ in range(int(rng.integers(18, 30))):
        lx = rng.uniform(F.x0 + 3, F.x1 - 3)
        ly = rng.choice([F.y0 + 3.0, F.y1 - 3.0, rng.uniform(F.y0 + 3, F.y1 - 3)])
        px, py = F.pt(lx, ly)
        name = str(rng.choice(["crates", "jerrycans", "tyres", "sandbags", "crates", "tarp"]))
        v, size = district_life.variant_of("clutter", name)
        if v >= 0 and area.contains(Point(px, py).buffer(2.0)) and site.props.clear_of(px, py, max(size) / 2 + 0.3):
            made["clutter"] += site.props.add("clutter", px, py, F.rad + rng.choice([0, np.pi / 2]), size, v)


def site_compound(site, area, rng, mast):
    F = kit.Frame(area)
    rows = int(rng.integers(2, 4))
    parked = 0
    xa = max(F.x0 + 10, -45.0)
    xb = min(F.x1 - 12, 45.0)
    for j in range(rows):
        y = F.y0 + 12 + j * 14
        if y > F.y1 - 10:
            break
        x = xa
        while x < xb and parked < SITE_VEHICLES:
            if rng.random() < 0.8:
                src = "tank" if rng.random() < 0.4 else "military_vehicle"
                px, py = F.pt(x, y)
                if area.contains(Point(px, py).buffer(5.0)):
                    parked += park(site, src, px, py, F.rad + np.pi / 2 + rng.normal(0, 0.03), rng)
            x += rng.uniform(6.5, 9.0)
    rings = [F.pt(rng.uniform(F.x0 + 8, F.x1 - 8), F.y1 - 10) for _ in range(int(rng.integers(2, 5)))]
    camp(site, area, F, rng, rings)
    mp = F.pt(F.x1 - 10, F.y1 - 12) if mast else None
    gate = kit.nearest_edge_point(area, site.road_union_near(area, 120.0), area.exterior.interpolate(0))
    seed = int(rng.integers(1 << 30))

    def draw(L):
        r = np.random.default_rng(seed)
        kit.pave(L, area, 0.16, 0.6, sub="groundlines", edge=False)
        kit.fence(L, area.exterior, r, gate=gate, v=0.32, post_every=2.0)
        kit.fence(L, area.buffer(-1.2, join_style="mitre").exterior, r, gate=gate, v=0.26, post_every=4.0)
        for x, y in rings:
            sandbag_ring(L, x, y, r.uniform(2.0, 3.0), r)
        if mp is not None:
            equipment.add_source(site.salvage, L, "relay_mast", mp[0], mp[1], F.rad, r)
    site.drawers.append(draw)
    site.solid_extra.append(area)


def open_spot(site, w, h, rng, avoid, tries=400):
    """A w x h box on open ground in the play area, away from buildings,
    roads, water and `avoid`."""
    lim = PLAY_HALF_M - 250
    built = site.building_tree()
    for _ in range(tries):
        x, y = rng.uniform(-lim, lim, 2)
        if site.sampler.zone_at(x, y) != OPEN:
            continue
        g = box(x - w / 2, y - h / 2, x + w / 2, y + h / 2)
        if len(built.query(g.buffer(60))):
            continue
        roads = site.road_union_near(g, 5.0)
        if roads is not None and roads.intersects(g):
            continue
        if site.water.intersects(g) or any(a.intersects(g.buffer(300)) for a in avoid):
            continue
        return g
    return None


def main_road_points(site, step=25.0):
    pts = []
    for _, _, w, _, kind, line in site.roads:
        if kind not in MAIN or line is None:
            continue
        for d in np.arange(step, line.length - step, step):
            p = line.interpolate(d)
            if abs(p.x) < PLAY_HALF_M - 120 and abs(p.y) < PLAY_HALF_M - 120:
                q = line.interpolate(d + 1.0)
                pts.append((p.x, p.y, float(np.arctan2(q.y - p.y, q.x - p.x)), w))
    return pts


def spread(points, n, rng, min_d=0.0):
    """n points picked from a list by farthest-point sampling."""
    if not points:
        return []
    arr = np.asarray([(p[0], p[1]) for p in points])
    first = int(rng.integers(len(points)))
    out = [first]
    d = np.hypot(*(arr - arr[first]).T)
    while len(out) < min(n, len(points)):
        i = int(np.argmax(d))
        if d[i] < min_d:
            break
        out.append(i)
        d = np.minimum(d, np.hypot(*(arr - arr[i]).T))
    return [points[i] for i in out]


def build(site):
    rng = np.random.default_rng(71)
    sites = []
    hangars = [to_frame_m(rings[0]).mean(0) for kind, rings, p in (site.feats or [])
               if kind == "poly" and p.get("building") == "hangar"]
    hangars = [h for h in hangars if abs(h[0]) < PLAY_HALF_M - 100 and abs(h[1]) < PLAY_HALF_M - 100]
    if len(hangars) >= 3:
        c = MultiPoint([tuple(h) for h in hangars]).centroid
        hull = box(c.x - 90, c.y - 70, c.x + 90, c.y + 70)
        area = kit.largest(hull.difference(unary_union([g.buffer(2) for g, *_, k, _ in site.roads
                                                        if not k.startswith("rail:") and g.intersects(hull)])))
        if area is not None and area.area > 3000:
            free = kit.largest(area.difference(unary_union([b.poly.buffer(6) for b in site.buildings
                                                            if b.poly.intersects(area)])))
            if free is not None and free.area > 2000:
                sites.append(free)
    for _ in range(EXTRA_SITES):
        g = open_spot(site, rng.uniform(*SITE_SIZE_M[0]), rng.uniform(*SITE_SIZE_M[1]), rng, sites)
        if g is not None:
            sites.append(g)
    masts = 0
    for k, area in enumerate(sites):
        mast = k % 2 == 0
        masts += mast
        site_compound(site, area, block_rng(73, area), mast)

    pts = main_road_points(site)
    for x, y, a, w in spread(pts, CHECKPOINTS, rng, 500.0):
        r = block_rng(79, Point(x, y))
        n = int(r.integers(1, 3))
        for i in range(n):
            off = (i - (n - 1) / 2) * 4.0
            nx, ny = -np.sin(a), np.cos(a)
            park(site, "military_vehicle", x + nx * off + np.cos(a) * r.uniform(-3, 3),
                 y + ny * off + np.sin(a) * r.uniform(-3, 3), a + r.uniform(-0.5, 0.5), r)
        if r.random() < 0.35:
            park(site, "tank", x + np.cos(a) * 14, y + np.sin(a) * 14, a + r.uniform(-0.3, 0.3), r)
        walls = [LineString([(x + np.cos(a) * d - np.sin(a) * s * (w / 2 + 1.5), y + np.sin(a) * d + np.cos(a) * s * (w / 2 + 1.5))
                             for d in (-6, 6)]) for s in (-1, 1)]
        pole = LineString([(x - np.sin(a) * w / 2 - np.cos(a) * 9, y + np.cos(a) * w / 2 - np.sin(a) * 9),
                           (x - np.cos(a) * 9, y - np.sin(a) * 9)])
        site.drawers.append(lambda L, walls=walls, pole=pole, s=int(r.integers(1 << 30)):
                            ([sandbags(L, wl, np.random.default_rng(s)) for wl in walls],
                             L.line("interiors", pole, 0.25, 0.45)))
    for x, y, a, w in spread(pts, ROADBLOCKS + CHECKPOINTS, rng, 400.0)[CHECKPOINTS:]:
        r = block_rng(83, Point(x, y))
        park(site, "tank", x, y, a + np.pi / 2 + r.uniform(-0.25, 0.25), r)
        for _ in range(int(r.integers(2, 4))):
            vv, size = props.pick_vehicle("vehicle_wreck", r)
            wx, wy = x + r.uniform(-9, 9), y + r.uniform(-9, 9)
            if site.props.clear_of(wx, wy, size[0] / 2):
                site.props.add("vehicle_wreck", wx, wy, r.uniform(0, 2 * np.pi), size, vv)
    trunk = [(line, w) for _, _, w, _, kind, line in site.roads if kind in MAIN and line is not None and line.length > 200]
    for _ in range(CONVOYS):
        if not trunk:
            break
        line, w = trunk[int(rng.integers(len(trunk)))]
        d = rng.uniform(50, line.length - 120)
        lane = line.offset_curve(rng.choice([-1, 1]) * min(3.0, w / 4))
        if lane.is_empty or lane.geom_type != "LineString":
            continue
        for i in range(int(rng.integers(3, 7))):
            p = lane.interpolate(min(d + i * 11.0, lane.length))
            q = lane.interpolate(min(d + i * 11.0 + 1.0, lane.length))
            if abs(p.x) > PLAY_HALF_M - 50 or abs(p.y) > PLAY_HALF_M - 50:
                continue
            park(site, "military_vehicle", p.x, p.y, float(np.arctan2(q.y - p.y, q.x - p.x)) + rng.normal(0, 0.05), rng)
    bright = []
    for _ in range(3000):
        x, y = rng.uniform(-PLAY_HALF_M + 300, PLAY_HALF_M - 300, 2)
        if site.sampler.zone_at(x, y) == OPEN:
            bright.append((x, y, float(site.sampler.value(x, y))))
    bright.sort(key=lambda t: -t[2])
    chosen = []
    for x, y, v in bright:
        if len(chosen) >= RELAY_MASTS - masts:
            break
        if any(np.hypot(x - cx, y - cy) < 900 for cx, cy in chosen):
            continue
        if len(site.building_tree().query(Point(x, y).buffer(30))):
            continue
        chosen.append((x, y))
    for x, y in chosen:
        site.drawers.append(lambda L, x=x, y=y, s=int(rng.integers(1 << 30)):
                            equipment.add_source(site.salvage, L, "relay_mast", x, y, 0.0, np.random.default_rng(s)))
    site.stats["military"] = {"sites": len(sites), "relay_masts": masts + len(chosen)}
    return site
