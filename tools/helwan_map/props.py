"""Works out where props go on the generated map, by rule, and writes the
spawn points as props.json for the Godot PropSpawner.

Kinds and rules:
  vehicle        parked along kerbs in uneven runs, kept clear of junctions;
                 on arterial roads also abandoned traffic queued across
                 the lanes
  truck          the same, on main roads only
  vehicle_wreck  some parked cars, abandoned cars askew at junctions, and
                 clusters in yards beside large buildings
  tree           bare husks (no light, so no leaves): rows along main roads
                 and trees found in the mockup; branches may overhang roofs
                 and roads
  bush           free ground near buildings, in clumps
  debris         along alleys and under elevated structures
  stall          market stalls (market.py); variants 0 lean-to, 1 canopy,
                 2 table with crates, 3 hand cart; no building, no wall
  bus            buses on main roads (and depots); each is a "bus" salvage
                 source
  military       tanks, APCs and military trucks at military sites and
                 checkpoints; tanks are "tank" salvage sources, the others
                 "military_vehicle"
  container      shipping containers in yards; each is a
                 "shipping_container" salvage source
Container trucks are a "truck" sprite; each one placed is a
"container_truck" salvage source.

Every point is checked against a 1 m grid of what is solid (buildings, roads,
water) so props get the room they need. All positions are in metres in the
map frame here, and written in world px.

Vehicles use the sprites listed in sprite_catalogue.json (see
prep_sprites.py). Each vehicle spawn picks one sprite, by its spawn weight,
and takes that sprite's real length and width as its footprint.

props.json: {"kinds": [...], "items": [[kind index, x, y, rotation (radians),
size x, size y, variant], ...]} with positions and sizes in px. variant is
the index into the kind's sprite list, or -1 to leave it to the game.
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from shapely import affinity, prepare
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

from gen_city import FRAME, HALF_M, MOCK_N, PX_PER_M
from zones import HOUSING, OPEN

KINDS = ["vehicle", "truck", "vehicle_wreck", "tree", "bush", "debris", "stall", "bus", "military", "container",
         "hut", "clutter"]
TREES = ("tree",)
# Wrecks use the car sprites, drawn darker.
SPRITE_KIND = {"vehicle_wreck": "vehicle"}
_CAT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sprite_catalogue.json")
CATALOGUE = json.load(open(_CAT_PATH, encoding="utf-8")) if os.path.exists(_CAT_PATH) else {}
SIZE_M = {
    "vehicle": (4.4, 1.8), "truck": (8.5, 2.5), "vehicle_wreck": (4.4, 1.9),
    "tree": (12.0, 12.0), "bush": (3.0, 3.0), "debris": (1.2, 1.2),
    "stall": (3.0, 2.2), "bus": (12.0, 2.55), "military": (7.0, 3.0), "container": (6.06, 2.44),
    "hut": (4.0, 3.0), "clutter": (1.5, 1.2),
}
PARKING_ROADS = {"residential", "unclassified", "tertiary", "tertiary_link", "secondary", "service"}
MAIN_ROADS = {"secondary", "trunk", "tertiary"}
# How busy each arterial road was: scales kerb parking and abandoned traffic.
ARTERIAL_BUSY = {"trunk": 1.0, "secondary": 0.5}
## Share of the vehicles on main roads that are buses (each one a "bus"
## salvage source).
BUS_SHARE = {"traffic": 0.045, "parked": 0.025}
LANE_M = 3.5
KERB_STRIP_M = 2.8
GRID_M = 1.0


class Props:
    def __init__(self, keep_out=None):
        self.items = []
        self._grid = {}
        self.keep_out = keep_out if keep_out is not None and not keep_out.is_empty else None
        if self.keep_out is not None:
            prepare(self.keep_out)

    def add(self, kind, x, y, rot, size=None, variant=-1):
        """Adds a spawn point unless it is off the map (the OSM roads run on
        past its edge) or falls in a hand-made keep-out area. Returns whether
        it was added."""
        if abs(x) > HALF_M or abs(y) > HALF_M:
            return False
        if self.keep_out is not None and self.keep_out.contains(Point(x, y)):
            return False
        sx, sy = size or SIZE_M[kind]
        self.items.append((KINDS.index(kind), x, y, rot, sx, sy, variant))
        self._grid.setdefault((int(x // 10), int(y // 10)), []).append((kind, x, y, max(sx, sy) / 2))
        return True

    def clear_of(self, x, y, r, kinds=None):
        """True when no placed prop (of the given kinds) is within r of its own
        radius from (x, y)."""
        cx, cy = int(x // 10), int(y // 10)
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for kind, px, py, pr in self._grid.get((cx + i, cy + j), ()):
                    if kinds and kind not in kinds:
                        continue
                    if (px - x) ** 2 + (py - y) ** 2 < (r + pr) ** 2:
                        return False
        return True

    def write(self, path):
        data = {
            "kinds": KINDS,
            "items": [[k, round(x * PX_PER_M, 1), round(y * PX_PER_M, 1), round(rot, 3),
                       round(sx * PX_PER_M, 1), round(sy * PX_PER_M, 1), v]
                      for k, x, y, rot, sx, sy, v in self.items],
        }
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, separators=(",", ":"))


class Space:
    """1 m grids over the map: what is solid, and how far each cell is from
    anything solid and from the nearest building."""

    def __init__(self, footprints_m, roads, water, under, extra=()):
        """extra: more solid ground (obstacles, yards, fields' furniture)."""
        n = int(2 * HALF_M / GRID_M)
        self.n = n
        bld = self._raster(footprints_m)
        road = self._raster([g for g, *_ in roads])
        wat = self._raster([water])
        self.under = self._raster([under]) if not under.is_empty else np.zeros((n, n), bool)
        self.solid = bld | road | wat
        if extra:
            self.solid |= self._raster(extra)
        self.road, self.water = road, wat
        self.free_dist = ndi.distance_transform_edt(~self.solid).astype(np.float32) * GRID_M
        self.bld_dist = ndi.distance_transform_edt(~bld).astype(np.float32) * GRID_M

    def _raster(self, geoms):
        im = Image.new("1", (self.n, self.n))
        d = ImageDraw.Draw(im)
        k = 1.0 / GRID_M
        for g in geoms:
            for p in getattr(g, "geoms", [g]):
                if p.geom_type != "Polygon" or p.is_empty:
                    continue
                d.polygon([((x + HALF_M) * k, (y + HALF_M) * k) for x, y in p.exterior.coords], fill=1)
                for hole in p.interiors:
                    d.polygon([((x + HALF_M) * k, (y + HALF_M) * k) for x, y in hole.coords], fill=0)
        return np.asarray(im, bool)

    def ij(self, x, y):
        i = np.clip(((np.asarray(y) + HALF_M) / GRID_M).astype(int), 0, self.n - 1)
        j = np.clip(((np.asarray(x) + HALF_M) / GRID_M).astype(int), 0, self.n - 1)
        return i, j

    def room(self, x, y):
        return float(self.free_dist[self.ij(x, y)])


def junction_points(roads):
    lines = [(line, w) for _, _, w, _, kind, line in roads if line is not None and not kind.startswith("rail:")]
    pts = []
    for line, _ in lines:
        pts += [line.coords[0], line.coords[-1]]
    for i, (a, _) in enumerate(lines):
        for b, _ in lines[i + 1:]:
            if not a.envelope.intersects(b.envelope):
                continue
            x = a.intersection(b)
            for g in getattr(x, "geoms", [x]):
                if g.geom_type == "Point":
                    pts.append((g.x, g.y))
    return np.asarray(pts)


def pick_vehicle(kind, rng):
    """A sprite for a vehicle spawn, by spawn weight: (index into the kind's
    sprite list, (length, width) in m)."""
    sprites = CATALOGUE.get(SPRITE_KIND.get(kind, kind), [])
    if not sprites:
        return -1, SIZE_M[kind]
    w = np.array([e.get("weight", 1.0) for e in sprites])
    i = int(rng.choice(len(sprites), p=w / w.sum()))
    return i, (sprites[i]["length_m"], sprites[i]["width_m"])


def car_rect(x, y, ang, size):
    hl, hw = size[0] / 2, size[1] / 2
    return affinity.rotate(box(x - hl, y - hw, x + hl, y + hw), ang, origin=(x, y), use_radians=True)


def vehicle_source(kind, variant):
    """The salvage source kind of a vehicle sprite (sprite_catalogue.json),
    or None."""
    sprites = CATALOGUE.get(SPRITE_KIND.get(kind, kind), [])
    return sprites[variant].get("source") if 0 <= variant < len(sprites) else None


def add_vehicle(P, salvage, kind, x, y, ang, size, variant):
    """Adds a vehicle spawn and, if its sprite is a salvage source (a bus, a
    container truck, a tank ...), the source at the same spot."""
    if not P.add(kind, x, y, ang, size, variant):
        return False
    src = vehicle_source(kind, variant) if kind != "vehicle_wreck" else None
    if src and salvage is not None:
        salvage.add(src, x, y, ang, size[0], size[1], vehicle=True)
    return True


def main_road_pick(rng, truck_share, bus_share):
    if rng.random() < truck_share:
        return "truck"
    if CATALOGUE.get("bus") and rng.random() < bus_share:
        return "bus"
    return "vehicle"


def place_vehicles(P, roads, concrete, junctions, rng, salvage=None):
    jtree = junctions
    for _, _, w, _, kind, line in roads:
        if kind not in PARKING_ROADS and kind != "trunk":
            continue
        main = kind in MAIN_ROADS or kind == "trunk"
        busy = ARTERIAL_BUSY.get(kind, 0.0)
        start_p = 0.45 if not main else 0.3 + 0.55 * busy
        run_max = 6 + int(4 * busy)
        for side in (-1, 1):
            off = side * (w / 2 - 1.4)
            curve = line.offset_curve(off) if abs(off) > 0.05 else line
            for seg in getattr(curve, "geoms", [curve]):
                if seg.is_empty or seg.length < 6:
                    continue
                dist = rng.uniform(0, 15)
                while dist < seg.length - 3:
                    if rng.random() > start_p:
                        dist += rng.uniform(10, 40) * (1.0 - 0.7 * busy)
                        continue
                    run = int(rng.integers(1, run_max))
                    for _ in range(run):
                        pk = main_road_pick(rng, 0.15, BUS_SHARE["parked"]) if main else "vehicle"
                        variant, size = pick_vehicle(pk, rng)
                        if dist + size[0] > seg.length:
                            break
                        p0 = seg.interpolate(dist)
                        p1 = seg.interpolate(dist + size[0])
                        cx, cy = (p0.x + p1.x) / 2, (p0.y + p1.y) / 2
                        ang = np.arctan2(p1.y - p0.y, p1.x - p0.x)
                        if rng.random() < 0.5:
                            ang += np.pi
                        askew = rng.random() < 0.1
                        ang += rng.normal(0, 0.03) + (rng.uniform(-0.45, 0.45) if askew else 0)
                        dist += size[0] + rng.uniform(0.6, 1.8)
                        if len(jtree) and np.min(np.hypot(jtree[:, 0] - cx, jtree[:, 1] - cy)) < 8:
                            continue
                        rect = car_rect(cx, cy, ang, size)
                        if not concrete.contains(rect) or not P.clear_of(cx, cy, size[0] / 2 - 0.4):
                            continue
                        k = pk if pk != "vehicle" else ("vehicle_wreck" if rng.random() < 0.08 else "vehicle")
                        add_vehicle(P, salvage, k, cx, cy, ang, size, variant)
                    dist += rng.uniform(12, 45) * (1.0 - 0.75 * busy)


def place_traffic(P, roads, concrete, junctions, rng, salvage=None):
    """Abandoned traffic on arterial roads: queues across the inner lanes in
    blocks 40-120 m long, half the lanes facing each way, more askew than
    parked cars and with more wrecks."""
    for _, _, w, _, kind, line in roads:
        busy = ARTERIAL_BUSY.get(kind, 0.0)
        if busy <= 0.0 or line is None:
            continue
        lanes = int((w - 2 * KERB_STRIP_M) // LANE_M)
        if lanes < 1:
            continue
        offsets = [(i - (lanes - 1) / 2) * LANE_M for i in range(lanes)]
        start = rng.uniform(0, 40)
        while start < line.length:
            block = rng.uniform(40, 120)
            for li, off in enumerate(offsets):
                lane = line.offset_curve(off) if abs(off) > 0.05 else line
                for seg in getattr(lane, "geoms", [lane]):
                    if seg.is_empty:
                        continue
                    facing = 0.0 if li < lanes / 2 else np.pi
                    dist = start + rng.uniform(0, 6)
                    while dist < min(start + block, seg.length - 3):
                        pk = main_road_pick(rng, 0.15, BUS_SHARE["traffic"])
                        variant, size = pick_vehicle(pk, rng)
                        gap = rng.uniform(1.0, 4.0)
                        if rng.random() > 0.55 + 0.3 * busy:
                            dist += size[0] + gap
                            continue
                        p0 = seg.interpolate(dist)
                        p1 = seg.interpolate(min(dist + size[0], seg.length))
                        dist += size[0] + gap
                        cx, cy = (p0.x + p1.x) / 2, (p0.y + p1.y) / 2
                        ang = np.arctan2(p1.y - p0.y, p1.x - p0.x) + facing
                        ang += rng.normal(0, 0.06) + (rng.uniform(-0.6, 0.6) if rng.random() < 0.25 else 0)
                        if len(junctions) and np.min(np.hypot(junctions[:, 0] - cx, junctions[:, 1] - cy)) < 6:
                            continue
                        if not concrete.contains(car_rect(cx, cy, ang, size)) or not P.clear_of(cx, cy, size[0] / 2 - 0.5):
                            continue
                        k = pk if pk != "vehicle" else ("vehicle_wreck" if rng.random() < 0.12 else "vehicle")
                        add_vehicle(P, salvage, k, cx, cy, ang, size, variant)
            start += block + rng.uniform(20, 80) / busy


def place_wrecks(P, S, junctions, concrete, big, rng):
    for x, y in junctions:
        if rng.random() > 0.06:
            continue
        for _ in range(int(rng.integers(1, 3))):
            cx, cy = x + rng.uniform(-5, 5), y + rng.uniform(-5, 5)
            ang = rng.uniform(0, 2 * np.pi)
            variant, size = pick_vehicle("vehicle_wreck", rng)
            if concrete.contains(car_rect(cx, cy, ang, size)) and P.clear_of(cx, cy, size[0] / 2 - 0.3):
                P.add("vehicle_wreck", cx, cy, ang, size, variant)
    for roof in big:
        if rng.random() > 0.35:
            continue
        c = roof.centroid
        r = np.sqrt(roof.area) / 2 + 8
        for _ in range(int(rng.integers(2, 6))):
            a = rng.uniform(0, 2 * np.pi)
            cx, cy = c.x + np.cos(a) * r * rng.uniform(0.9, 1.4), c.y + np.sin(a) * r * rng.uniform(0.9, 1.4)
            variant, size = pick_vehicle("vehicle_wreck", rng)
            if S.room(cx, cy) >= size[0] / 2 + 0.5 and P.clear_of(cx, cy, size[0] / 2):
                P.add("vehicle_wreck", cx, cy, rng.uniform(0, 2 * np.pi), size, variant)


def tree_crowns_from_mockup(f, zone):
    """Dark round blobs 4-10 m across in the mockup, outside dense housing."""
    mk = f["mk"]
    dog = ndi.gaussian_filter(mk, 1.0) - ndi.gaussian_filter(mk, 3.0)
    minima = (dog == ndi.minimum_filter(dog, size=5)) & (dog < -0.018)
    minima &= (zone == OPEN) & ~f["water"]
    i, j = np.nonzero(minima)
    k = 2 * HALF_M / MOCK_N
    return np.stack([(j + 0.5) * k - HALF_M, (i + 0.5) * k - HALF_M], 1), -dog[i, j]


def place_trees(P, S, roads, f, zone, rng):
    for _, _, w, _, kind, line in roads:
        if kind not in MAIN_ROADS:
            continue
        for side in (-1, 1):
            curve = line.offset_curve(side * (w / 2 + 3.5))
            for seg in getattr(curve, "geoms", [curve]):
                dist = rng.uniform(0, 8)
                while dist < seg.length:
                    p = seg.interpolate(dist)
                    dist += rng.uniform(8, 13)
                    if rng.random() < 0.35:
                        continue
                    add_tree(P, S, p.x, p.y, rng.uniform(9.0, 14.0), rng)
    crowns, strength = tree_crowns_from_mockup(f, zone)
    for (x, y), s in zip(crowns, strength):
        add_tree(P, S, x, y, float(np.clip(8.0 + s * 160, 9.0, 16.0)), rng)


def add_tree(P, S, x, y, size, rng):
    """A tree needs room for its trunk only; its branches may overhang roofs
    and roads, and may cross other trees' branches."""
    if S.room(x, y) >= 1.2 and P.clear_of(x, y, size * 0.3, TREES):
        P.add("tree", x, y, rng.uniform(0, 2 * np.pi), (size, size))


def place_bushes(P, S, rng):
    """Clusters of two to four bushes on free ground within 6 m of buildings.
    Cluster centres are denser where a low-frequency noise is high, so
    clusters gather in some yards and skip others."""
    near = (S.free_dist >= 1.5) & (S.bld_dist <= 6.0) & ~S.solid
    ii, jj = np.nonzero(near[::3, ::3])
    noise = ndi.gaussian_filter(rng.standard_normal((S.n // 8 + 1, S.n // 8 + 1)), 2)
    noise = (noise - noise.mean()) / noise.std()
    for idx in rng.permutation(len(ii)):
        i, j = ii[idx] * 3, jj[idx] * 3
        if rng.random() > 0.035 + 0.05 * max(noise[i // 8, j // 8], 0):
            continue
        cx = (j + rng.uniform(0, 3)) * GRID_M - HALF_M
        cy = (i + rng.uniform(0, 3)) * GRID_M - HALF_M
        if not P.clear_of(cx, cy, 3.0, ("bush",) + TREES):
            continue
        # Members may touch each other, so they are only kept off trees and
        # solid ground; the clear check on the centre keeps clusters apart.
        target = int(rng.integers(2, 5))
        placed = []
        for _ in range(target * 4):
            size = rng.uniform(1.8, 3.8)
            a = rng.uniform(0, 2 * np.pi)
            d = 0.0 if not placed else rng.uniform(1.0, 2.4)
            x, y = cx + np.cos(a) * d, cy + np.sin(a) * d
            if S.room(x, y) < size * 0.3 or not P.clear_of(x, y, size * 0.3, TREES):
                continue
            if any(np.hypot(x - px, y - py) < 0.8 for px, py in placed):
                continue
            P.add("bush", x, y, rng.uniform(0, 2 * np.pi), (size, size))
            placed.append((x, y))
            if len(placed) >= target:
                break


def place_debris(P, S, roads, rng):
    for _, _, w, _, kind, line in roads:
        if line is None or kind.startswith("rail:") or w > 4.5:
            continue
        for dist in np.arange(rng.uniform(0, 15), line.length, 15.0):
            if rng.random() > 0.4:
                continue
            p = line.interpolate(dist)
            side = rng.choice([-1, 1]) * (w / 2 - 0.6)
            q = line.interpolate(min(dist + 0.5, line.length))
            d = np.array([q.x - p.x, q.y - p.y])
            d /= np.hypot(*d) or 1.0
            x, y = p.x - d[1] * side, p.y + d[0] * side
            if P.clear_of(x, y, 0.8):
                P.add("debris", x, y, rng.uniform(0, 2 * np.pi), (rng.uniform(0.6, 1.6),) * 2)
    ii, jj = np.nonzero(S.under & ~S.solid)
    for idx in rng.permutation(len(ii))[: len(ii) // 60]:
        x, y = jj[idx] * GRID_M - HALF_M, ii[idx] * GRID_M - HALF_M
        if rng.random() < 0.15:
            variant, size = pick_vehicle("vehicle_wreck", rng)
            if S.room(x, y) >= size[0] / 2 + 0.5 and P.clear_of(x, y, size[0] / 2):
                P.add("vehicle_wreck", x, y, rng.uniform(0, 2 * np.pi), size, variant)
        elif S.room(x, y) >= 1.0 and P.clear_of(x, y, 1.0):
            P.add("debris", x, y, rng.uniform(0, 2 * np.pi))


def build(footprints_px, roads, water, under, big, f, zone, keep_out=None, seed=5, extra_solid=(), P=None,
          salvage=None, life=None):
    """P: a Props that the district modules already put their own spawns in
    (stalls, containers, tractors); the rules here keep clear of them.
    salvage: the salvage collector, for vehicles that are sources (buses,
    container trucks). life: called last as life(P, S, roads, junctions,
    rng), to add more props on the same free-space grid (district_life)."""
    rng = np.random.default_rng(seed)
    footprints_m = [Polygon(np.asarray(p) / PX_PER_M) for p in footprints_px]
    S = Space(footprints_m, roads, water, under, extra_solid)
    concrete = unary_union([g for g, *_, kind, _ in roads if not kind.startswith("rail:")]).buffer(-0.2)
    prepare(concrete)
    junctions = junction_points(roads)
    P = P if P is not None else Props(keep_out)
    place_traffic(P, roads, concrete, junctions, rng, salvage)
    place_vehicles(P, roads, concrete, junctions, rng, salvage)
    place_wrecks(P, S, junctions, concrete, big, rng)
    place_trees(P, S, roads, f, zone, rng)
    place_bushes(P, S, rng)
    place_debris(P, S, roads, rng)
    if life is not None:
        life(P, S, roads, junctions, rng)
    return P
