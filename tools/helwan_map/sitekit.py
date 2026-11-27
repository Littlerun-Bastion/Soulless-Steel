"""Site templates: the reusable parts of the service sites (sites.py).

A site type is data plus three steps:

  lot finder   where the site may go: a street corner (two roads meeting at
               a block corner, street_corners) or a stretch of block edge
               along a road (frontages);
  lot shaper   the lot itself: the block clipped near the corner or along
               the frontage, kept ROAD_SETBACK_M off the road concrete
               (corner_lot, frontage_lot). Its outline follows the street
               layout, so no two lots are alike;
  pieces       fixed shapes (a kiosk outline, a canopy, a car wash, a
               showroom, rows of parking bays) placed in the lot's frame by
               rules ("faces the main road", "set back X m from the
               canopy", "drive-through, long side along the lane").

Then shape_ground() turns what is left into ground: driveways are cut where
the lot meets the roads, the driving lanes from the driveways round the
pieces are smoothed into curves (a closing of their union) and become the
apron (concrete, like the roads), and the leftover pieces of the lot become
islands and verges (darker rough ground with a kerb line), like the curved
islands of a real forecourt.

A Lot works in its own frame (LFrame): x along the road it fronts, y into
the block, origin at the street corner or at the frontage's start.

Also here: the building kinds of the sites (fuel kiosk, car wash, garage
workshop, showroom, workshop hall) with their roofs, the ground drawing of
aprons, islands, kerbs, bay lines and arrows, the canopy (overheads) and the
price sign pylon (talls), and Parker, which puts vehicles in bays and
queues without overlapping each other, buildings or obstacles.
"""
import numpy as np
import shapely
from shapely import STRtree, prepare
from shapely.geometry import LineString, LinearRing, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

import buildings as bl
import props
import ruins
import style
from frame import PLAY_HALF_M
from gen_city import ROAD_SETBACK_M, is_buildable, rng_at
from kit import largest
from site_ctx import MARKER_CLEAR_M

## Concrete of the aprons (as the roads), the darker asphalt of car parks
## and the rough ground of the islands and verges.
APRON_V = style.CONCRETE_V
ASPHALT_V = 0.215
ISLAND_V, ISLAND_A = 0.085, 0.8
KERB_V, KERB_W = 0.36, 0.2
MARK_V, MARK_W = 0.33, 0.14
## Rounding of the apron where lanes meet (closing radius, m) and of the
## islands' outer corners (opening radius, m).
FILLET_M = 3.0
ISLAND_ROUND_M = 1.2
## Islands smaller than this (m2) join the apron. Leftover ground thinner
## than twice THIN_ISLAND_M is paved, unless it is a verge within
## ROAD_VERGE_M of a road.
ISLAND_MIN_M2 = 5.0
THIN_ISLAND_M = 2.2
ROAD_VERGE_M = 5.0
## Parking bays (m): width, depth, aisle between rows.
BAY_W, BAY_D, AISLE_M = 2.8, 5.6, 6.5
## A driveway is paved across the verge to the road and this far (m) onto
## the road's concrete, under its edge line, so no seam shows where they
## meet; the carriageway beyond stays the road's.
DRIVE_ONTO_ROAD_M = 0.2
## Nothing smaller (m2) is a building; a house a site trims keeps to it.
BUILDING_MIN_M2 = 60.0
## Clutter keeps this far (m) off the sites' vehicles.
VEHICLE_CLEAR_M = 0.15
## The canopies over pumps and bus bays: the deck's alpha (what is under it
## shows through) and the bright fascia along its edge (width m, value).
CANOPY_A = 0.55
CANOPY_FASCIA_W, CANOPY_FASCIA_V = 0.5, 0.44
## How deep (m) a garage's open bay shows on its roof (at most half the
## roof's depth), and the light sign board along its street side (depth m,
## value).
GARAGE_MOUTH_M = 4.2
GARAGE_SIGN_M, GARAGE_SIGN_V = 0.9, 0.34
## The generic road vehicles (props.place_vehicles, place_traffic) test
## their room with circles a little smaller than their length; the site
## vehicles on the road are marked to them with a circle this much (m) wider
## than their own half diagonal, so none overlaps them (guard_vehicles).
GUARD_EXTRA_M = 0.9

# Road kinds by how much they count as a main road.
ROAD_RANK = {"trunk": 4, "secondary": 3, "tertiary": 2, "unclassified": 1, "residential": 1, "tertiary_link": 1,
             "secondary_link": 1, "trunk_link": 1, "service": 0, "construction": 0}


def unit(v):
    v = np.asarray(v, float)
    n = float(np.hypot(*v))
    return v / n if n > 1e-9 else v


def cross(a, b):
    """The z of the cross product of two 2D vectors."""
    return float(a[0] * b[1] - a[1] * b[0])


def sample_in(poly, rng, tries=20):
    """A random point inside poly, or None."""
    if poly is None or poly.is_empty:
        return None
    x0, y0, x1, y1 = poly.bounds
    for _ in range(tries):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if poly.contains(Point(x, y)):
            return x, y
    return None


def box_of(F, poly):
    """A polygon's extent in frame F: (x0, x1, y0, y1)."""
    loc = [F.to_local(x, y) for x, y in poly.exterior.coords]
    xs, ys = zip(*loc)
    return min(xs), max(xs), min(ys), max(ys)


def place_rng(seed, x, y):
    """A random generator for one place, seeded by its position, so a part
    of the map comes out the same in a window run as in a full run."""
    return rng_at(seed, x, y)


def place_hash(seed, x, y):
    """A number in [0, 1) fixed for a place."""
    return float(place_rng(seed, x, y).random())


class LFrame:
    """A local frame: origin o, x along unit u, y along unit n (n is u turned
    a quarter towards +y on the map, so y points into the block when u runs
    with the block on its right in the map's y-down view)."""

    def __init__(self, origin, u, n=None):
        self.o = np.asarray(origin, float)
        self.u = unit(u)
        self.n = np.array([-self.u[1], self.u[0]]) if n is None else unit(n)
        self.ang = float(np.arctan2(self.u[1], self.u[0]))

    def pt(self, x, y):
        p = self.o + self.u * x + self.n * y
        return float(p[0]), float(p[1])

    def pts(self, xy):
        return [self.pt(x, y) for x, y in xy]

    def poly(self, xy):
        return Polygon(self.pts(xy))

    def rect(self, x0, y0, x1, y1):
        return self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])

    def line(self, xy):
        return LineString(self.pts(xy))

    def to_local(self, x, y):
        d = np.array([x, y], float) - self.o
        return float(d @ self.u), float(d @ self.n)

    def dir(self, dx, dy):
        """The map direction of a local direction."""
        return unit(self.u * dx + self.n * dy)

    def heading(self, dx, dy):
        d = self.dir(dx, dy)
        return float(np.arctan2(d[1], d[0]))


# ------------------------------------------------------------------ roads

class Roads:
    """The road centrelines (no rail) with their width and kind, and their
    concrete, for the lot finders."""

    def __init__(self, roads):
        self.items = [(line, w, kind) for _, _, w, _, kind, line in roads
                      if line is not None and not kind.startswith("rail:")]
        self.tree = STRtree([it[0] for it in self.items])
        self.lines = np.asarray([it[0] for it in self.items], dtype=object)
        self.half_w = np.asarray([it[1] / 2 for it in self.items], float)
        self.rails = [(line, w) for _, _, w, _, kind, line in roads if line is not None and kind.startswith("rail:")]
        self.rail_tree = STRtree([r[0] for r in self.rails]) if self.rails else None
        self.rail_lines = np.asarray([r[0] for r in self.rails], dtype=object)
        self.rail_half_w = np.asarray([r[1] / 2 for r in self.rails], float)
        self.concrete = [g for g, *_, kind, _ in roads if not kind.startswith("rail:")]
        self.ctree = STRtree(self.concrete)

    def at(self, x, y, tol=3.0):
        """The road whose edge is within tol of (x, y): (line, width, kind,
        distance to its edge), the nearest edge first; or None."""
        p = Point(x, y)
        best = None
        for i in self.tree.query(p.buffer(30.0)):
            line, w, kind = self.items[i]
            d = line.distance(p) - w / 2
            if d < tol and (best is None or d < best[3]):
                best = (line, w, kind, d)
        return best

    def at_many(self, xy, tol=3.0):
        """Roads.at for many points (an n x 2 array): a list of (line,
        width, kind, distance to its edge) or None."""
        out = [None] * len(xy)
        if not len(xy) or not len(self.items):
            return out
        pts = shapely.points(xy)
        i, j = self.tree.query(pts, predicate="dwithin", distance=tol + float(self.half_w.max()))
        if not len(i):
            return out
        d = shapely.distance(self.lines[j], pts[i]) - self.half_w[j]
        keep = d < tol
        i, j, d = i[keep], j[keep], d[keep]
        order = np.lexsort((d, i))
        seen = set()
        for k in order:
            if i[k] not in seen:
                seen.add(i[k])
                line, w, kind = self.items[j[k]]
                out[i[k]] = (line, w, kind, float(d[k]))
        return out

    def rail_near_many(self, xy, dist=6.0):
        """Roads.rail_near for many points: a boolean array."""
        out = np.zeros(len(xy), bool)
        if self.rail_tree is None or not len(xy):
            return out
        pts = shapely.points(xy)
        i, j = self.rail_tree.query(pts, predicate="dwithin", distance=dist + float(self.rail_half_w.max()))
        if len(i):
            near = shapely.distance(self.rail_lines[j], pts[i]) - self.rail_half_w[j] < dist
            out[i[near]] = True
        return out

    def rail_near(self, x, y, dist=6.0):
        """True when a rail bed's edge is within dist of (x, y) (a street
        drawn under a rail line is not a street to front)."""
        if self.rail_tree is None:
            return False
        p = Point(x, y)
        return any(self.rails[i][0].distance(p) - self.rails[i][1] / 2 < dist
                   for i in self.rail_tree.query(p.buffer(dist + 10.0)))

    def concrete_near(self, geom, dist=30.0):
        idx = self.ctree.query(geom.buffer(dist))
        return unary_union([self.concrete[i] for i in idx]) if len(idx) else Polygon()

    def lines_near(self, geom, dist=60.0):
        g = geom.buffer(dist)
        return [self.items[i] for i in self.tree.query(g) if self.items[i][0].intersects(g)]

    def junctions_near(self, geom, dist=120.0):
        """Points where road centrelines meet or end near geom."""
        lines = [line for line, _, _ in self.lines_near(geom, dist)]
        pts = []
        for line in lines:
            pts += [line.coords[0], line.coords[-1]]
        for i, a in enumerate(lines):
            for b in lines[i + 1:]:
                x = a.intersection(b)
                for g in getattr(x, "geoms", [x]):
                    if g.geom_type == "Point":
                        pts.append((g.x, g.y))
        return np.asarray(pts) if pts else np.zeros((0, 2))


def tangent(line, x, y):
    d = line.project(Point(x, y))
    a = line.interpolate(max(d - 1.0, 0.0))
    b = line.interpolate(min(d + 1.0, line.length))
    return unit([b.x - a.x, b.y - a.y])


class Corner:
    """A street corner: a convex corner v of a block where a main road (unit
    u along its block edge, away from v) meets a side road (unit s)."""

    def __init__(self, block, v, u, s, main, side):
        self.block, self.v, self.u, self.s = block, np.asarray(v, float), unit(u), unit(s)
        self.main, self.side = main, side
        n = np.array([-self.u[1], self.u[0]])
        if n @ self.s < 0:
            n = -n
        self.n = n
        self.angle = float(np.degrees(np.arccos(np.clip(self.u @ self.s, -1, 1))))

    @property
    def main_kind(self):
        return self.main[2]

    @property
    def side_kind(self):
        return self.side[2]


def street_corners(blocks, R, main_kinds, side_kinds=None, angles=(40.0, 140.0), min_edge=8.0, area=None):
    """Convex block corners where a road of main_kinds meets another road
    (of side_kinds, any road when None). area: only blocks whose centre is
    in it."""
    out = []
    for blk in blocks:
        if blk.area < 600 or (area is not None and not area.contains(blk.centroid)):
            continue
        ring = blk.simplify(0.8).exterior
        pts = np.asarray(ring.coords)[:-1]
        n = len(pts)
        if n < 3:
            continue
        for i in range(n):
            p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
            a, b = p0 - p1, p2 - p1
            la, lb = float(np.hypot(*a)), float(np.hypot(*b))
            if la < min_edge or lb < min_edge:
                continue
            ang = float(np.degrees(np.arccos(np.clip((a @ b) / (la * lb), -1, 1))))
            if not angles[0] <= ang <= angles[1]:
                continue
            if not blk.contains(Point(p1 + (a / la + b / lb) * 1.5)):
                continue
            ra = R.at(*(p1 + a / la * 6.0))
            rb = R.at(*(p1 + b / lb * 6.0))
            if ra is None or rb is None or ra[0] is rb[0]:
                continue
            if R.rail_near(*(p1 + a / la * 6.0)) or R.rail_near(*(p1 + b / lb * 6.0)):
                continue
            for (rm, um), (rs, us) in (((ra, a / la), (rb, b / lb)), ((rb, b / lb), (ra, a / la))):
                if rm[2] not in main_kinds or (side_kinds is not None and rs[2] not in side_kinds):
                    continue
                if ROAD_RANK.get(rm[2], 0) < ROAD_RANK.get(rs[2], 0):
                    continue
                t = tangent(rm[0], *(p1 + um * 12.0))
                u = t if t @ um > 0 else -t
                out.append(Corner(blk, p1, u, us, rm, rs))
    return out


class Frontage:
    """A point on a block edge along a road: p on the block edge, u along the
    road, n into the block."""

    def __init__(self, block, p, u, n, road):
        self.block, self.p, self.u, self.n, self.road = block, np.asarray(p, float), unit(u), unit(n), road

    @property
    def kind(self):
        return self.road[2]


def frontages(blocks, R, kinds, step=20.0, area=None, block_ok=None):
    """Points every step metres along the block edges that face a road of
    the given kinds."""
    out = []
    for blk in blocks:
        if blk.area < 800 or (area is not None and not area.contains(blk.centroid)):
            continue
        if block_ok is not None and not block_ok(blk):
            continue
        ring = orient(blk.simplify(0.8), 1.0).exterior
        ds = np.arange(step / 2, ring.length, step)
        if not len(ds):
            continue
        P = shapely.get_coordinates(shapely.line_interpolate_point(ring, ds))
        Q = shapely.get_coordinates(shapely.line_interpolate_point(ring, np.minimum(ds + 1.0, ring.length)))
        E = Q - P
        E = E / np.maximum(np.hypot(E[:, 0], E[:, 1]), 1e-9)[:, None]
        N = np.stack([-E[:, 1], E[:, 0]], axis=1)
        inside = shapely.contains_xy(blk, P[:, 0] + N[:, 0], P[:, 1] + N[:, 1])
        N[~inside] *= -1.0
        roads = R.at_many(P - N, tol=2.5)
        rails = R.rail_near_many(P)
        for k, r in enumerate(roads):
            if r is None or r[2] not in kinds or rails[k]:
                continue
            t = tangent(r[0], P[k, 0], P[k, 1])
            if abs(t @ E[k]) < 0.85:
                continue
            n = N[k]
            u = np.array([n[1], -n[0]])
            out.append(Frontage(blk, (float(P[k, 0]), float(P[k, 1])), u, n, r))
    return out


# -------------------------------------------------------------------- lots

class Lot:
    """A site's lot: its polygon (kept ROAD_SETBACK_M off the road concrete),
    its frame F (x along the main road, y into the block) and the concrete
    of the roads round it."""

    def __init__(self, poly, F, concrete, kind):
        self.poly = poly
        self.F = F
        self.concrete = concrete
        self.kind = kind
        prepare(self.poly)

    def fits(self, geom, margin=0.0):
        g = geom.buffer(margin, join_style="mitre") if margin > 0 else geom
        return self.poly.contains(g)


def corner_lot(c, R, along_main, along_side, setback=ROAD_SETBACK_M):
    """The lot at a street corner: the block inside the parallelogram spanned
    by along_main metres of the main road's edge and along_side of the side
    road's, cut back from the concrete. Returns a Lot or None."""
    sin = max(abs(cross(c.u, c.s)), 0.3)
    e = 5.0 / sin
    v, u, s = c.v, c.u, c.s
    quad = Polygon([v - u * e - s * e, v + u * along_main - s * e, v + u * along_main + s * along_side,
                    v - u * e + s * along_side])
    raw = c.block.intersection(quad)
    concrete = R.concrete_near(quad, 10.0)
    lot = largest(raw.difference(concrete.buffer(setback, join_style="mitre")) if not concrete.is_empty else raw)
    if lot is None:
        return None
    return Lot(lot.simplify(0.3), LFrame(v, u, c.n), concrete, "corner")


def frontage_lot(fr, R, length, depth, setback=ROAD_SETBACK_M, x0=0.0):
    """The lot along a frontage: the block inside a rectangle length along
    the road (from x0) and depth into the block, cut back from the
    concrete."""
    F = LFrame(fr.p, fr.u, fr.n)
    rect = F.rect(x0, -6.0, x0 + length, depth)
    raw = fr.block.intersection(rect)
    concrete = R.concrete_near(rect, 10.0)
    lot = largest(raw.difference(concrete.buffer(setback, join_style="mitre")) if not concrete.is_empty else raw)
    if lot is None:
        return None
    return Lot(lot.simplify(0.3), F, concrete, "frontage")


def trim_lot(lot, used, keep=None, verge=3.5, open_m=2.0):
    """The lot cut down to what its pieces use: the used ground grown by a
    verge, plus keep (e.g. the corner, for its island), opened so no spikes
    are left. The houses beyond stay. Returns a Lot (the same frame)."""
    g = used.buffer(verge, join_style="round", quad_segs=4)
    if keep is not None:
        g = g.union(keep)
    t = lot.poly.intersection(g).buffer(-open_m, join_style="round", quad_segs=4).buffer(
        open_m, join_style="round", quad_segs=4).intersection(lot.poly)
    t = largest(t)
    if t is None:
        return lot
    return Lot(t.simplify(0.3), lot.F, lot.concrete, lot.kind)


def free_part(site, poly, pad=0.5, whole=False):
    """What is left of poly once the land other modules took (claims, district
    content, markers, KeepOut, the border band) is cut out: its largest
    part, or all of it with whole."""
    g = poly.intersection(box(-PLAY_HALF_M, -PLAY_HALF_M, PLAY_HALF_M, PLAY_HALF_M))
    for taken in (site.claimed(), site.district_taken()):
        if taken is not None and taken.intersects(g):
            g = g.difference(taken.buffer(pad))
    if site.keep_out is not None and not site.keep_out.is_empty and site.keep_out.intersects(g):
        g = g.difference(site.keep_out.buffer(2.0))
    for _, mx, my in site.markers:
        m = Point(mx, my).buffer(MARKER_CLEAR_M + pad)
        if m.intersects(g):
            g = g.difference(m)
    return g if whole else largest(g)


def trimmed_house(poly, cut):
    """What is left of a generated house that a site's lot cuts: its largest
    part when that keeps at least half of it, is a buildable lot and stays a
    building (BUILDING_MIN_M2; a house already under it keeps nine tenths of
    itself), else None (the house is dropped)."""
    rest = largest(poly.difference(cut))
    if rest is None or rest.area < 0.5 * poly.area or not is_buildable(rest):
        return None
    if rest.area < (BUILDING_MIN_M2 if poly.area >= BUILDING_MIN_M2 else 0.9 * poly.area):
        return None
    return rest.simplify(0.05)


def take_land(site, lot, owner, keep_houses=False):
    """Takes a lot's land: trims or drops the generated houses it cuts
    (trimmed_house), grows the lot over the ground the dropped houses leave
    (so no bare patch is left between the site and the houses that stay),
    then claims it, keeps the generic props out of it and clears what the
    district modules put in it. Returns (the lot, grown, as a Lot; houses
    dropped)."""
    poly = lot.poly
    dropped, gone = 0, []
    if not keep_houses:
        cut = poly.buffer(0.6, join_style="mitre")
        keep = []
        hits = shapely.intersects(np.array([b.poly for b in site.buildings], dtype=object), cut)
        for b, hit in zip(site.buildings, hits):
            if hit and b.opts.get("stage") == "lots":
                rest = trimmed_house(b.poly, cut)
                if rest is not None:
                    b.poly = rest
                    keep.append(b)
                else:
                    gone.append(b.poly)
                    dropped += 1
                continue
            keep.append(b)
        site.buildings = keep
    if gone:
        grow = unary_union([g.buffer(0.8, join_style="mitre") for g in gone])
        near = grow.buffer(2.0)
        stay = [b.poly.buffer(0.6, join_style="mitre") for b in buildings_near(site, near, 0.0)]
        grow = grow.difference(unary_union(stay)) if stay else grow
        roads = site.road_union_near(grow, 5.0)
        if roads is not None and not roads.is_empty:
            grow = grow.difference(roads.buffer(ROAD_SETBACK_M, join_style="mitre"))
        free = free_part(site, grow, whole=True)
        if free is not None and not free.is_empty:
            g = largest(unary_union([poly, free]).buffer(0.05).buffer(-0.05))
            if g is not None and g.area > poly.area:
                poly = g.simplify(0.2)
    site.claim(poly, owner)
    site.clear_area(poly)
    site.solid_extra.append(poly)
    return Lot(poly, lot.F, lot.concrete, lot.kind), dropped


def buildings_near(site, geom, dist):
    """The buildings within dist of geom."""
    if not site.buildings:
        return []
    near = shapely.dwithin(np.array([b.poly for b in site.buildings], dtype=object), geom, dist)
    return [b for b, n in zip(site.buildings, near) if n]


def houses_cover(lot_tree, lot_polys, poly):
    """Share of poly covered by the generated house lots (lot_polys: the
    lots as a list or an array, lot_tree their STRtree)."""
    idx = lot_tree.query(poly, predicate="intersects")
    if not len(idx):
        return 0.0
    arr = lot_polys if isinstance(lot_polys, np.ndarray) else np.asarray(lot_polys, dtype=object)
    return float(shapely.area(shapely.intersection(arr[idx], poly)).sum()) / max(poly.area, 1e-6)


# ------------------------------------------------------------------ ground

def opening(g, r, segs=4):
    return g.buffer(-r, join_style="round", quad_segs=segs).buffer(r, join_style="round", quad_segs=segs)


def closing(g, r, segs=6):
    return g.buffer(r, join_style="round", quad_segs=segs).buffer(-r, join_style="round", quad_segs=segs)


def shape_ground(lot, paved, pieces, mouths=(), fillet=FILLET_M, keep=None, road_verge=ROAD_VERGE_M,
                 thin=THIN_ISLAND_M):
    """Splits a lot into apron and islands. paved: the lanes and aprons the
    pieces need (polygons), pieces: the footprints that are neither (the
    buildings), mouths: driveway mouths that join the apron to the road
    concrete, keep: ground that is an island unless a lane needs it (the
    street corner).

    The paved parts and the mouths are closed with radius fillet (curves
    where lanes meet and where driveways leave the road). What is left of the
    lot round them becomes islands where it is a verge along a road (within
    road_verge of the concrete), where it is wide enough (an opening by
    thin survives it) or where keep asks for it; thinner leftovers (strips
    along the back of the lot) are paved. Islands are rounded
    (ISLAND_ROUND_M) and the ones under ISLAND_MIN_M2 are paved. Returns
    (apron, islands)."""
    mouths = [m for m in mouths if m is not None and not m.is_empty]
    lot_plus = unary_union([lot.poly] + mouths)
    need = unary_union([g for g in paved if g is not None and not g.is_empty] + mouths)
    need = closing(need, fillet).intersection(lot_plus)
    solid = unary_union([p.buffer(0.15, join_style="mitre") for p in pieces]) if pieces else Polygon()
    rest = lot.poly.difference(need).difference(solid)
    parts = [opening(rest, thin)]
    if lot.concrete is not None and not lot.concrete.is_empty:
        parts.append(rest.intersection(lot.concrete.buffer(ROAD_SETBACK_M + road_verge)))
    if keep is not None:
        parts.append(keep.intersection(rest))
    islands = unary_union([p for p in parts if not p.is_empty]).intersection(rest)
    islands = opening(islands, ISLAND_ROUND_M).intersection(rest)
    islands = unary_union([g for g in style.polys(islands) if g.area >= ISLAND_MIN_M2])
    if islands.is_empty:
        islands = Polygon()
    apron = lot_plus.difference(islands).difference(solid)
    return apron.simplify(0.15), islands.simplify(0.15)


def mouth(F, x, width, depth_in=4.0, depth_out=2.5, y0=0.0):
    """A driveway mouth across a frontage at local x: from depth_out metres
    into the road concrete to depth_in metres into the lot (y0 the lot's
    edge)."""
    return F.rect(x - width / 2, y0 - depth_out, x + width / 2, y0 + depth_in)


def side_mouth(c, F, t, width, depth_in=4.0, depth_out=2.5):
    """A driveway mouth on the side road of a corner lot, t metres from the
    corner along the side road's edge, as a polygon in map metres."""
    s = c.s
    ns = np.array([s[1], -s[0]])
    if ns @ c.u < 0:
        ns = -ns
    p = c.v + s * t
    a, b = p - s * width / 2, p + s * width / 2
    return Polygon([a - ns * depth_out, b - ns * depth_out, b + ns * depth_in, a + ns * depth_in]), p, ns


def driveway(m, lot_poly, concrete, onto=DRIVE_ONTO_ROAD_M):
    """The paved part of a driveway mouth m: what lies in the lot or in the
    verge between the lot and the road concrete, reaching onto the concrete
    by only `onto` m. Verge that m reaches across the road (the far side of
    a narrow street) is left out: only the parts touching the lot stay."""
    if concrete is None or concrete.is_empty:
        return m.intersection(lot_poly)
    verge = concrete.buffer(ROAD_SETBACK_M + 0.4, join_style="mitre")
    g = m.intersection(lot_poly.union(verge)).difference(concrete.buffer(-onto, join_style="mitre"))
    parts = [p for p in style.polys(g) if p.intersects(lot_poly)]
    return unary_union(parts) if parts else Polygon()


def draw_apron(L, apron, concrete, v=APRON_V, joints=5.0, ang=0.0, keep_off=None):
    """Concrete like the roads, an edge line where it meets the islands and
    the ground (not along the road), and slab joints every `joints` m.
    keep_off: what stands on the apron and draws its own edge (buildings,
    pump islands): no edge line runs round it and no joints under it."""
    if apron.is_empty:
        return
    L.fill("ground", apron, v)
    near_road = concrete.buffer(ROAD_SETBACK_M + 0.6) if concrete is not None and not concrete.is_empty else None
    off = keep_off.buffer(0.45, join_style="mitre") if keep_off is not None and not keep_off.is_empty else None
    for g in style.polys(apron):
        for ring in [g.exterior] + list(g.interiors):
            edge = LineString(ring.coords)
            if near_road is not None:
                edge = edge.difference(near_road)
            if off is not None:
                edge = edge.difference(off)
            if not edge.is_empty:
                L.line("groundlines", edge, style.EDGE_LINE_W, style.EDGE_LINE_V, 0.8)
    if joints:
        c = apron.centroid
        F = LFrame((c.x, c.y), (np.cos(ang), np.sin(ang)))
        x0, y0, x1, y1 = (-1, -1, 1, 1)
        loc = [F.to_local(x, y) for x, y in apron.envelope.exterior.coords] if not apron.envelope.is_empty else []
        if loc:
            xs, ys = zip(*loc)
            r = max(max(map(abs, xs)), max(map(abs, ys))) * 1.5
            x0, y0, x1, y1 = -r, -r, r, r
        lines = [F.line([(x, y0), (x, y1)]) for x in np.arange(x0, x1, joints)]
        lines += [F.line([(x0, y), (x1, y)]) for y in np.arange(y0, y1, joints)]
        grid = unary_union(lines).intersection(apron.buffer(-0.3))
        if off is not None:
            grid = grid.difference(off)
        if not grid.is_empty:
            L.line("groundlines", grid, 0.05, 0.19, 0.6)


def draw_islands(L, islands, v=ISLAND_V, a=ISLAND_A, kerb=True):
    """Rough dark ground with a light kerb line round it."""
    if islands.is_empty:
        return
    L.fill("ground", islands, v, a)
    if kerb:
        for g in style.polys(islands):
            L.line("groundlines", LinearRing(g.exterior.coords), KERB_W, KERB_V, 0.9)


def arrow(L, x, y, d, length=4.0, v=MARK_V):
    """A painted arrow at (x, y) pointing along unit d: a shaft and a head."""
    d = unit(d)
    n = np.array([-d[1], d[0]])
    tail = np.array([x, y]) - d * length / 2
    tip = np.array([x, y]) + d * length / 2
    neck = tip - d * 1.2
    L.line("groundlines", LineString([tail, neck]), 0.3, v, 0.85)
    L.fill("groundlines", Polygon([tip, neck + n * 0.7, neck - n * 0.7]), v, 0.85)


def bay_lines(L, bays, v=MARK_V, w=MARK_W):
    """The painted lines of parking bays: the two sides of each bay (shared
    sides drawn once) as short quads."""
    seen = set()
    tris, grey, alpha = [], [], []
    for b in bays:
        for a, c in b.sides():
            key = (round(a[0] + c[0], 1), round(a[1] + c[1], 1))
            if key in seen:
                continue
            seen.add(key)
            d = unit(np.subtract(c, a))
            n = np.array([-d[1], d[0]]) * w / 2
            q = np.array([a + n, c + n, c - n, a - n])
            tris += [q[[0, 1, 2]], q[[0, 2, 3]]]
    if tris:
        t = np.array(tris)
        L.add_tris("groundlines", t, v, 0.85)


class Bay:
    """One parking bay: centre, unit heading (nose direction), width and
    depth."""

    def __init__(self, x, y, d, w=BAY_W, depth=BAY_D):
        self.x, self.y, self.d, self.w, self.depth = x, y, unit(d), w, depth

    def poly(self):
        d, n = self.d, np.array([-self.d[1], self.d[0]])
        c = np.array([self.x, self.y])
        hw, hd = self.w / 2, self.depth / 2
        return Polygon([c - d * hd - n * hw, c + d * hd - n * hw, c + d * hd + n * hw, c - d * hd + n * hw])

    def sides(self):
        d, n = self.d, np.array([-self.d[1], self.d[0]])
        c = np.array([self.x, self.y])
        hw, hd = self.w / 2, self.depth / 2
        return [(c - d * hd - n * hw, c + d * hd - n * hw), (c - d * hd + n * hw, c + d * hd + n * hw)]


def bay_row(F, x0, x1, y, facing, area, w=BAY_W, depth=BAY_D, angle=90.0):
    """A row of bays in frame F along x from x0 to x1, their mouth edge on
    the line y, noses pointing local +y when facing is +1 (-y when -1).
    angle 90 is straight in; less makes angled bays leaning towards +x.
    Only bays wholly inside area are kept."""
    out = []
    a = np.radians(angle)
    pitch = w / np.sin(a)
    dloc = (np.cos(a), np.sin(a) * facing)
    for x in np.arange(x0 + pitch / 2, x1 - pitch / 2 + 1e-6, pitch):
        cx = x + dloc[0] * depth / 2
        cy = y + dloc[1] * depth / 2
        px, py = F.pt(cx, cy)
        b = Bay(px, py, F.dir(*dloc), w, depth)
        if area.contains(b.poly()):
            out.append(b)
    return out


def bay_grid(F, area, rng=None, w=BAY_W, depth=BAY_D, aisle=AISLE_M, y_start=None, angle=90.0):
    """Fills area (frame F) with rows of bays along x: an aisle, then a pair
    of rows back to back, then an aisle, and so on into +y. An area in
    several parts is filled part by part; an empty one gets nothing.
    Returns (bays, aisles), aisles as polygons."""
    bays, aisles = [], []
    for part in style.polys(area) if area is not None else []:
        if part.area < depth * w:
            continue
        loc = [F.to_local(x, y) for x, y in part.exterior.coords]
        xs, ys = zip(*loc)
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        y = y0 if y_start is None else y_start
        while y + aisle + depth <= y1 + 0.01:
            aisles.append(F.rect(x0 - 2, y, x1 + 2, y + aisle).intersection(part))
            y += aisle
            bays += bay_row(F, x0, x1, y, +1, part, w, depth, angle)
            if y + 2 * depth <= y1 + 0.01:
                bays += bay_row(F, x0, x1, y + 2 * depth, -1, part, w, depth, angle)
                y += 2 * depth
            else:
                y += depth
    return bays, [a for a in aisles if not a.is_empty]


# --------------------------------------------------------------- vehicles

def car_rect(x, y, ang, size, pad=0.0):
    return props.car_rect(x, y, ang, (size[0] + 2 * pad, size[1] + 2 * pad))


class Placed:
    """The vehicles the sites put down (for every Parker of a run, kept on
    the Site): their spawn tuples and outlines, on a 10 m grid, so the
    clutter can keep off them, the generic road vehicles can be kept off
    them (guard_vehicles) and what is still on the map can be counted."""

    CELL = 10.0

    def __init__(self):
        self.items = []
        self.grid = {}

    def add(self, kind, x, y, ang, size, variant, rect, on_road=False):
        i = len(self.items)
        self.items.append((kind, x, y, ang, size, variant, rect, on_road))
        x0, y0, x1, y1 = rect.bounds
        for cx in range(int(x0 // self.CELL), int(x1 // self.CELL) + 1):
            for cy in range(int(y0 // self.CELL), int(y1 // self.CELL) + 1):
                self.grid.setdefault((cx, cy), []).append(i)

    def hits(self, geom):
        x0, y0, x1, y1 = geom.bounds
        seen = set()
        for cx in range(int(x0 // self.CELL), int(x1 // self.CELL) + 1):
            for cy in range(int(y0 // self.CELL), int(y1 // self.CELL) + 1):
                for i in self.grid.get((cx, cy), ()):
                    if i not in seen:
                        seen.add(i)
                        if self.items[i][6].intersects(geom):
                            return True
        return False

    def present(self, P):
        """The placed vehicles still among P's spawns (a later site's
        clear_area may have taken some)."""
        have = {(props.KINDS[k], round(x, 4), round(y, 4)) for k, x, y, *_ in P.items}
        return [it for it in self.items if (it[0], round(it[1], 4), round(it[2], 4)) in have]


def placed(site):
    """The site's Placed record, made on first use."""
    p = getattr(site, "sites_placed", None)
    if p is None:
        p = site.sites_placed = Placed()
    return p


def guard_vehicles(site):
    """Marks every site vehicle on the road (queues, cars at a garage's
    kerb) that is still on the map in the props' room grid with a circle
    round its whole outline, so the generic road vehicles placed later
    (props.build) keep off it. The marks are not spawns; a clear_area
    afterwards would drop them, so this runs last."""
    P = site.props
    for kind, x, y, ang, size, variant, rect, on_road in placed(site).present(P):
        if not on_road:
            continue
        r = 0.5 * float(np.hypot(*size)) + GUARD_EXTRA_M
        P._grid.setdefault((int(x // 10), int(y // 10)), []).append((kind, x, y, r))


class Parker:
    """Puts vehicles down without overlapping each other, buildings or
    obstacles. avoid: polygons to keep clear of (buildings, pump islands,
    kerbs). Inside a lot that is the site's own (cleared and claimed), only
    the vehicles the sites parked are checked; on the road, the other
    modules' props too (props.clear_of)."""

    def __init__(self, site, rng, avoid=(), stats=None):
        self.site, self.rng = site, rng
        self.avoid = [g for g in avoid if g is not None and not g.is_empty]
        self.tree = STRtree(self.avoid) if self.avoid else None
        self.placed = placed(site)
        self.stats = stats if stats is not None else {}

    def _free(self, rect):
        if self.tree is not None:
            for i in self.tree.query(rect):
                if self.avoid[i].intersects(rect):
                    return False
        return not self.placed.hits(rect)

    def pick(self, kind="vehicle", max_len=None, names=None):
        """A sprite variant of kind (by spawn weight), at most max_len long, or
        one of the named sprites: (variant, (length, width)) or None."""
        cat = props.CATALOGUE.get(props.SPRITE_KIND.get(kind, kind), [])
        idx = []
        for i, e in enumerate(cat):
            name = e["file"][len("vehicle_"):-4]
            if names is not None:
                if name in names:
                    idx.append(i)
            elif e.get("weight", 1.0) > 0 and (max_len is None or e["length_m"] <= max_len):
                idx.append(i)
        if not idx:
            return None
        w = np.array([cat[i].get("weight", 1.0) if names is None else 1.0 for i in idx], float)
        i = int(idx[int(self.rng.choice(len(idx), p=w / w.sum()))])
        return i, (cat[i]["length_m"], cat[i]["width_m"])

    def put(self, kind, x, y, ang, variant, size, on_road=False, concrete=None, pad=0.15, source=True):
        """Puts a vehicle down if it has room. source False: no salvage
        source with it, even for a sprite that is one (a tanker or dump
        truck stripped in a repair yard)."""
        rect = car_rect(x, y, ang, size)
        if not self._free(rect.buffer(pad)):
            return False
        if concrete is not None and not concrete.contains(rect):
            return False
        if on_road and not self.site.props.clear_of(x, y, size[0] / 2 - 0.6):
            return False
        if not self.site.salvage.allowed(x, y, *size):
            return False
        if source:
            if not props.add_vehicle(self.site.props, self.site.salvage, kind, x, y, ang, size, variant):
                return False
        elif not self.site.props.add(kind, x, y, ang, size, variant):
            return False
        self.placed.add(kind, x, y, ang, size, variant, rect, on_road)
        self.stats[kind] = self.stats.get(kind, 0) + 1
        return True

    def car(self, x, y, ang, wreck_share=0.1, max_len=5.4, on_road=False, concrete=None, names=None):
        got = self.pick("vehicle", max_len, names)
        if got is None:
            return False
        v, size = got
        kind = "vehicle_wreck" if self.rng.random() < wreck_share else "vehicle"
        return self.put(kind, x, y, ang, v, size, on_road, concrete)

    def in_bay(self, bay, wreck_share=0.06, reverse_share=0.3, names=None):
        """A car in a bay, nose in (sometimes reversed in), a little off
        straight."""
        got = self.pick("vehicle", bay.depth - 0.3, names)
        if got is None:
            return False
        v, size = got
        d = bay.d if self.rng.random() > reverse_share else -bay.d
        ang = float(np.arctan2(d[1], d[0])) + self.rng.normal(0, 0.035)
        off = self.rng.uniform(-0.25, 0.25)
        x, y = bay.x + bay.d[0] * off, bay.y + bay.d[1] * off
        kind = "vehicle_wreck" if self.rng.random() < wreck_share else "vehicle"
        return self.put(kind, x, y, ang, v, size, pad=0.05)

    def fill_bays(self, bays, share, wreck_share=0.06, reverse_share=0.3, names=None):
        n = 0
        for b in bays:
            if self.rng.random() < share:
                n += self.in_bay(b, wreck_share, reverse_share, names)
        return n


def clutter(site, name, x, y, rot, clear=0.2):
    """A clutter prop by sprite name (district_life names), if there is
    room among the clutter and huts already placed (clear m between their
    circles) and it keeps VEHICLE_CLEAR_M off the sites' vehicles."""
    import district_life
    v, size = district_life.variant_of("clutter", name)
    if v < 0 or not site.props.clear_of(x, y, max(size) / 2 + clear, ("clutter", "hut")):
        return False
    if placed(site).hits(car_rect(x, y, rot, size, VEHICLE_CLEAR_M)):
        return False
    return site.props.add("clutter", x, y, rot, size, v)


# -------------------------------------------------------------- overheads

def canopy(L, poly, F, rng, v=0.21, a=CANOPY_A):
    """A forecourt canopy over the pumps (overheads: above mechas, fades near
    the player): a see-through deck (alpha a, so the pump islands, pumps and
    cars under it show and it does not read as a roof), panel joints across,
    its shadow round the edge and a thin bright fascia along the edge in
    place of a building's outline. The light fittings are canopy_lights."""
    L.fill("overheads", poly.buffer(0.9, join_style="mitre").difference(poly), 0.0, 0.3)
    L.fill("overheads", poly, v, a)
    loc = [F.to_local(x, y) for x, y in poly.exterior.coords]
    xs, ys = zip(*loc)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    for x in np.arange(x0 + 2.5, x1 - 1.0, 2.5):
        L.line("overheads", F.line([(x, y0 + 0.8), (x, y1 - 0.8)]), 0.06, v * 0.6, a)
    edge = poly.buffer(-CANOPY_FASCIA_W / 2, join_style="mitre")
    L.line("overheads", LinearRing(edge.exterior.coords), CANOPY_FASCIA_W, CANOPY_FASCIA_V)


def canopy_lights(L, F, xs, ys, v=0.42):
    for x in xs:
        for y in ys:
            L.fill("overheads", F.rect(x - 0.9, y - 0.25, x + 0.9, y + 0.25), v)


# ------------------------------------------------------------------ talls

def price_pylon(L, x, y, d, height, rng):
    """The price sign of a gas station (talls, so it leans like a tall thing
    seen from above): two thin legs and a board on top, the board's face
    across d (the road it is read from)."""
    d = unit(d)
    n = np.array([-d[1], d[0]])
    board_w, board_t = rng.uniform(2.2, 3.0), 0.45
    top, bottom = height, height - rng.uniform(4.0, 5.5)
    for s in (-1, 1):
        p = np.array([x, y]) + n * s * (board_w / 2 - 0.35)
        L.tall_post(p[0], p[1], 0.3, 0.0, bottom + 0.3, 0.2, 0.3, ang=float(np.degrees(np.arctan2(d[1], d[0]))))
    c = np.array([x, y])
    hw, ht = board_w / 2, board_t / 2
    board = Polygon([c - n * hw - d * ht, c + n * hw - d * ht, c + n * hw + d * ht, c - n * hw + d * ht])
    L.tall_prism(board, bottom, top, 0.13, 0.32)
    L.tall_span(tuple(c - n * (hw - 0.1)), tuple(c + n * (hw - 0.1)), 0.12, top + 0.02, top + 0.02, 0.45)


def sign_pole(L, x, y, d, height, board=(2.0, 1.2)):
    """A pole sign (talls): one post and a board across d."""
    d = unit(d)
    n = np.array([-d[1], d[0]])
    L.tall_post(x, y, 0.35, 0.0, height - board[1], 0.2, 0.3)
    c = np.array([x, y])
    hw, ht = board[0] / 2, 0.25
    poly = Polygon([c - n * hw - d * ht, c + n * hw - d * ht, c + n * hw + d * ht, c - n * hw + d * ht])
    L.tall_prism(poly, height - board[1], height, 0.13, 0.3)


# -------------------------------------------------------------- buildings

def front_frame(b):
    """The building's frame from b.opts: origin and unit x along its front
    (the side that faces the lane or road), unit y into the building."""
    o, u = b.opts.get("front_o"), b.opts.get("front_u")
    if o is None:
        ang, c = style.frame_of(b.poly)
        return LFrame((c.x, c.y), (np.cos(np.radians(ang)), np.sin(np.radians(ang))))
    return LFrame(o, u, b.opts.get("front_n"))


def roof_kiosk(L, b, rng):
    """The shop of a gas station: a flat roof with its parapet, a light
    fascia band along the front, AC units and a tank."""
    F = front_frame(b)
    g = b.poly
    v = style.roof_value(b.mv) * rng.uniform(0.9, 1.1)
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    band = g.intersection(F.rect(-60, -1.0, 60, 1.1))
    R.fill(band, 0.3)
    R.stroke(F.line([(-60, 1.1), (60, 1.1)]).intersection(g), 0.12, 0.42)
    inner = style.set_inner(R, g.difference(band.buffer(0.3)), 0.45)
    R.shade_in(inner, 1.0, 0.4)
    R.ring(inner, style.PARAPET_W, style.PARAPET_V)
    for fn in (style.item_vents, style.item_tanks, style.item_stair):
        if rng.random() < 0.75:
            fn(R, 1.0)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return R


def roof_wash(L, b, rng):
    """A drive-through car wash: a sheet roof along the bay, open at both
    ends (the wash floor shows at each end), with the brush gantry's rail
    lines along it."""
    F = front_frame(b)
    g = b.poly
    loc = [F.to_local(x, y) for x, y in g.exterior.coords]
    xs, ys = zip(*loc)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    v = style.roof_value(b.mv) * rng.uniform(1.0, 1.25)
    R = style.Roof(L, g, v, rng)
    roof = F.rect(x0 + 1.4, y0, x1 - 1.4, y1).intersection(g)
    for xe in ((x0, x0 + 1.4), (x1 - 1.4, x1)):
        end = F.rect(xe[0], y0, xe[1], y1).intersection(g)
        R.fill(end, APRON_V * 0.8)
        R.fill(F.rect(xe[0], y0, xe[1], y0 + 0.3).intersection(g), 0.05)
        R.fill(F.rect(xe[0], y1 - 0.3, xe[1], y1).intersection(g), 0.05)
    R.fill(roof, v)
    for y in np.arange(y0 + 0.6, y1, 0.7):
        R.stroke(F.line([(x0 + 1.4, y), (x1 - 1.4, y)]).intersection(g), 0.05, v * 0.55)
    for y in (y0 + (y1 - y0) * 0.3, y1 - (y1 - y0) * 0.3):
        R.stroke(F.line([(x0 + 1.4, y), (x1 - 1.4, y)]).intersection(g), 0.14, style.DETAIL_LINE_V)
    R.ring(roof, style.OUTLINE_W, style.OUTLINE_V)
    return None


def roof_garage(L, b, rng):
    """A backstreet workshop: a corrugated sheet roof with a light sign board
    along the street side and, cut into it, the open bay seen from above: a
    dark floor GARAGE_MOUTH_M deep with an inspection pit, between two light
    jambs, the rolled-up shutter's drum (a light band) along its front and
    the lintel's edge behind it; and a roof light."""
    F = front_frame(b)
    g = b.poly
    loc = [F.to_local(x, y) for x, y in g.exterior.coords]
    xs, ys = zip(*loc)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    v = min(style.roof_value(b.mv) * rng.uniform(1.4, 1.8), 0.17)
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    for x in np.arange(x0 + 0.35, x1, 0.55):
        R.stroke(F.line([(x, y0), (x, y1)]).intersection(g), 0.06, v * 0.55)
    bay_x = b.opts.get("bay_x", (x0 + x1) / 2)
    bw = min(b.opts.get("bay_w", 4.0), x1 - x0 - 1.0)
    depth = min(GARAGE_MOUTH_M, (y1 - y0) * 0.5)
    R.fill(F.rect(x0 - 1.0, y0 - 1.0, x1 + 1.0, y0 + GARAGE_SIGN_M).intersection(g), GARAGE_SIGN_V)
    R.stroke(F.line([(x0 - 1.0, y0 + GARAGE_SIGN_M), (x1 + 1.0, y0 + GARAGE_SIGN_M)]).intersection(g), 0.12, 0.04)
    R.fill(F.rect(bay_x - bw / 2 - 0.4, y0, bay_x + bw / 2 + 0.4, y0 + depth + 0.3).intersection(g), 0.32)
    R.fill(F.rect(bay_x - bw / 2, y0, bay_x + bw / 2, y0 + depth).intersection(g), 0.02)
    if depth > 3.0:
        pit = F.rect(bay_x - 0.45, y0 + 1.4, bay_x + 0.45, y0 + depth - 0.3)
        R.fill(pit.intersection(g), 0.0)
        R.stroke(LinearRing(pit.exterior.coords).intersection(g), 0.12, 0.2)
    R.fill(F.rect(bay_x - bw / 2, y0 + 0.1, bay_x + bw / 2, y0 + 0.8).intersection(g), 0.36)
    R.stroke(F.line([(bay_x - bw / 2, y0 + depth), (bay_x + bw / 2, y0 + depth)]).intersection(g), 0.12, 0.42)
    if rng.random() < 0.6 and y1 - y0 > 5:
        ym = (y0 + y1) / 2
        R.fill(F.rect(x0 + 1.5, ym - 0.6, min(x1 - 1.5, x0 + 4.5), ym + 0.6).intersection(g), 0.16)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return None


def roof_showroom(L, b, rng):
    """A car showroom: a flat roof whose front is a deep glass band with
    mullions (the glazed front and its canopy), AC units on the rest."""
    F = front_frame(b)
    g = b.poly
    v = style.roof_value(b.mv) * rng.uniform(0.9, 1.1)
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    depth = b.opts.get("glass_m", 3.5)
    glass = g.intersection(F.rect(-200, -1.0, 200, depth))
    R.fill(glass, 0.21)
    loc = [F.to_local(x, y) for x, y in g.exterior.coords]
    xs = [p[0] for p in loc]
    for x in np.arange(min(xs) + 1.6, max(xs), 1.6):
        R.stroke(F.line([(x, 0.0), (x, depth)]).intersection(glass), 0.07, 0.42)
    R.stroke(F.line([(-200, depth), (200, depth)]).intersection(g), 0.16, 0.45)
    inner = style.set_inner(R, g.difference(glass.buffer(0.3)), 0.6)
    R.shade_in(inner, 1.2, 0.4)
    R.ring(inner, style.PARAPET_W, style.PARAPET_V)
    for _ in range(int(rng.integers(1, 3))):
        style.item_vents(R, 1.3)
    R.ring(g, style.OUTLINE_W * 1.2, style.OUTLINE_V)
    return R


def roof_hall(L, b, rng):
    """A workshop hall (truck repair, bus depot): a sheet roof and, along the
    yard side, a door strip for each bay."""
    F = front_frame(b)
    g = b.poly
    loc = [F.to_local(x, y) for x, y in g.exterior.coords]
    xs, ys = zip(*loc)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    v = style.roof_value(b.mv) * rng.uniform(1.0, 1.3)
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    for x in np.arange(x0 + 0.4, x1, 0.7):
        R.stroke(F.line([(x, y0), (x, y1)]).intersection(g), 0.05, v * 0.6)
    ym = (y0 + y1) / 2
    R.stroke(F.line([(x0, ym), (x1, ym)]).intersection(g), 0.16, style.DETAIL_LINE_V)
    for x in np.arange(x0 + 2.0, x1 - 2.0, 6.0):
        R.fill(F.rect(x, ym - 1.5, x + 1.2, ym + 1.5).intersection(g), 0.14)
    for xd in b.opts.get("doors", []):
        R.fill(F.rect(xd - 2.5, y0, xd + 2.5, y0 + 0.8).intersection(g), 0.02)
        R.stroke(F.line([(xd - 2.5, y0 + 0.8), (xd + 2.5, y0 + 0.8)]).intersection(g), 0.1, 0.32)
    R.ring(g, style.OUTLINE_W * 1.2, style.OUTLINE_V)
    return None


bl.KINDS["fuel_kiosk"] = (roof_kiosk, False, style.HALO_HOUSE_M)
bl.KINDS["car_wash"] = (roof_wash, False, style.HALO_HOUSE_M)
bl.KINDS["garage"] = (roof_garage, False, style.HALO_HOUSE_M)
bl.KINDS["showroom"] = (roof_showroom, True, style.HALO_BIG_M)
bl.KINDS["workshop_hall"] = (roof_hall, True, style.HALO_BIG_M)


def pin_state(site, b, worst=ruins.GUTTED):
    """Pins a site building's ruin state: the damage map's state for its
    place, but never worse than `worst`, so the site keeps the building that
    makes it readable (a collapsed building is drawn as a rubble heap)."""
    c = b.poly.centroid
    b.opts["state"] = min(ruins.state_at(c.x, c.y, site.districts.of_geom(b.poly)), worst)


def building(site, poly, kind, F, district_mv=None, **opts):
    """Adds a building of a site kind, its front frame from F, its ruin state
    pinned by pin_state."""
    c = poly.centroid
    mv = district_mv if district_mv is not None else float(site.sampler.value(c.x, c.y))
    b = bl.Building(poly, mv, kind, front_o=tuple(F.o), front_u=tuple(F.u), front_n=tuple(F.n), **opts)
    pin_state(site, b)
    site.buildings.append(b)
    return b


def lot_wall(L, lot, concrete, v=0.3, width=0.35, keep_off=None):
    """A low wall along the lot's sides that do not face a road, cut where
    it would come within 0.1 m of keep_off (the buildings beside the
    lot)."""
    edge = LineString(lot.poly.exterior.coords)
    if concrete is not None and not concrete.is_empty:
        edge = edge.difference(concrete.buffer(ROAD_SETBACK_M + 2.0))
    if keep_off is not None and not keep_off.is_empty:
        edge = edge.difference(keep_off.buffer(width / 2 + 0.1, join_style="mitre"))
    for part in getattr(edge, "geoms", [edge]):
        if part.length > 1.0:
            L.line("interiors", part, width + 0.3, 0.02, 0.5)
            L.line("interiors", part, width, v)
