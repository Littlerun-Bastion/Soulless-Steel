"""Service sites built from templates on irregular lots: gas stations,
garages, car dealerships, truck repair yards, car parks, bus depots, and
parking in front of and beside large buildings.

Runs last of the site modules, on the land the others left; claims its land
with Site.claim. The templates (lot finders, lot shaper, pieces, apron and
islands, vehicles, the sites' building kinds) are in sitekit.py; the site
types other than gas stations are in sitelots.py.

The site types are the rows of SITE_TYPES (lot finder, count, spacing,
score, planner, builder). Every place is chosen over the whole map from
site.full_layout (roads, blocks, house lots, large roofs) and the
districts, with per-place random numbers, and built only when it touches
site.window, so a window preview shows what a full run makes there. The
types choose in the table's order, each keeping off the places the ones
before it chose: gas stations, dealerships, bus depots, truck yards, car
parks, garages, parking out front, side car parks. A chosen place whose
land another module took (sitekit.free_part) is built on what is free: a
station is laid out again on its corner lot less the land taken, the
others are cut back; a place is skipped when its pieces no longer fit.

Gas stations: STATIONS at street corners on main roads, at least
STATION_SPACING_M apart. The lot is the block corner; the pieces are a
kiosk (one of KIOSKS, a building) facing the main road, a canopy (one of
CANOPIES, a see-through deck) over 1-3 rows of pump islands (overheads;
the islands are ground obstacles with LANE_M lanes between the rows), a
price sign pylon on the corner island (talls), tank fill covers, an air
and water post and, on WASH_SHARE of them, a drive-through car wash (a
building). An entry and an exit on the
main road and a driveway on the side road; apron and islands by
sitekit.shape_ground. Cars at the pumps and the kiosk; on QUEUE_SHARE of
the stations an abandoned queue of cars from the entry back along the
road; a few wrecks. Pumps give nothing and do not explode (no fuel
sources).
"""
import numpy as np
from shapely import STRtree
from shapely.geometry import LineString, Point, box
from shapely.ops import nearest_points, unary_union

import obstacles
import props
import sitekit as sk
import sitelots as sl
import style
from districts import FARMLAND, INDUSTRIAL, MARKET, RESIDENTIAL
from frame import PLAY_HALF_M
from site_ctx import MARKER_CLEAR_M

MAIN_ROADS = props.MAIN_ROADS

## Gas stations: how many, how far apart (m), and the road kinds they front
## with a weight each (more on busier roads).
STATIONS = 23
STATION_SPACING_M = 330.0
STATION_ROADS = {"trunk": 1.0, "secondary": 0.85, "tertiary": 0.55}
## A station lot: metres along the main road and along the side road.
STATION_LOT_M = ((56.0, 76.0), (44.0, 64.0))
## Pump islands (m): length, width; clear lane between rows of islands (a
## mecha is about 10 m across; islands are ground obstacles); islands in a
## row along the road with this gap.
ISLAND_M = (6.0, 1.3)
LANE_M = 13.0
ISLAND_GAP_M = 7.5
## Canopy sizes, (rows of islands into the lot, islands per row along the
## road), with the weight of each; a station takes the first in a drawn
## order that fits its lot. One row makes a long canopy along the road.
CANOPIES = {(2, 2): 0.4, (1, 2): 0.2, (1, 3): 0.15, (2, 1): 0.12, (3, 2): 0.08, (3, 1): 0.05}
## Canopy overhang past the islands (m) and the paved ring round it.
OVERHANG_M = 4.5
RING_M = 6.5
## The lot is cut down to its paved ground plus this verge (m), and keeps
## the ground within CORNER_KEEP_M of the street corner (its island holds
## the price sign).
VERGE_M = 3.5
CORNER_KEEP_M = 16.0
## Radius (m) round the street corner that is an island unless a lane needs
## it; the price sign stands PYLON_KERB_M inside the kerb of the island
## nearest the corner.
CORNER_ISLAND_M = 13.0
PYLON_KERB_M = 1.5
## Nothing but the island and the sign within this distance (m) of the
## street corner: no canopy ring, kiosk or driveway.
CORNER_CLEAR_M = 10.0
## Kiosk outlines (local metres: x along the front, y back from the front
## edge at y=0), each over 60 m2.
KIOSKS = {
    "box": [(-6.0, 0.0), (6.0, 0.0), (6.0, 7.5), (-6.0, 7.5)],
    "ell": [(-7.0, 0.0), (7.0, 0.0), (7.0, 5.0), (3.0, 5.0), (3.0, 8.5), (-7.0, 8.5)],
    "porch": [(-8.0, 0.0), (-4.5, 0.0), (-4.5, 1.8), (4.5, 1.8), (4.5, 0.0), (8.0, 0.0), (8.0, 7.0), (-8.0, 7.0)],
    "wide": [(-9.0, 0.0), (9.0, 0.0), (9.0, 5.6), (-9.0, 5.6)],
}
## Car wash (m): length along its lane, width; share of stations that want
## one, and how many more layouts such a station tries to find room for it
## (about a third of the stations end up with one).
WASH_M = (15.5, 7.4)
WASH_SHARE = 0.42
WASH_TRIES = 60
## Share of stations with an abandoned queue of cars out into the road, and
## its length range (cars). Cars at the pumps: chance per pump side.
QUEUE_SHARE = 0.5
QUEUE_CARS = (6, 18)
PUMP_CAR_CHANCE = 0.65
## The queue leaves this much room (m) round the junctions it passes.
QUEUE_JUNCTION_M = 9.0
## Driveway width (m); the side road's driveway only where its lane to the
## canopy is at most SIDE_LANE_MAX_M long.
DRIVE_W_M = 8.0
SIDE_LANE_MAX_M = 22.0


class Ctx:
    """What every site type shares while it chooses and builds."""

    def __init__(self, site):
        self.site = site
        lay = site.full_layout or {"roads": site.roads, "blocks": site.blocks, "big": [],
                                   "lots": [b.poly for b in site.buildings if b.kind == "house"]}
        self.R = sk.Roads(lay["roads"])
        self.blocks = lay["blocks"]
        self.lots = list(lay["lots"])
        self.lot_tree = STRtree(self.lots) if self.lots else None
        self.lot_arr = np.asarray(self.lots, dtype=object)
        self.big = list(lay["big"])
        self.big_tree = STRtree(self.big) if self.big else None
        self.D = site.districts
        self.inner = box(-PLAY_HALF_M + 90, -PLAY_HALF_M + 90, PLAY_HALF_M - 90, PLAY_HALF_M - 90)
        # Ground no site may take, known alike in a window run and a full
        # run: round the markers and in the KeepOut areas.
        fixed = [Point(x, y).buffer(MARKER_CLEAR_M + 2.0) for _, x, y in site.markers]
        if site.keep_out is not None and not site.keep_out.is_empty:
            fixed.append(site.keep_out.buffer(2.0))
        self.fixed = unary_union(fixed) if fixed else None
        self.mine = []
        self.mine_tree = None
        self.cache = {}
        self.stats = {}

    def count(self, key, n=1):
        self.stats[key] = self.stats.get(key, 0) + n

    def place(self, kind, geom):
        """Lists a built site in the stats: kind and centre (m)."""
        c = geom.centroid
        self.stats.setdefault("places", []).append([kind, round(c.x, 1), round(c.y, 1)])

    def block_use(self, blk):
        """The district module that rebuilds a block, if any."""
        if self.D.share(blk, INDUSTRIAL) >= 0.5 and blk.area >= 2500:
            return "industrial"
        if self.D.share(blk, MARKET) >= 0.5 and blk.area >= 1500:
            return "market"
        if self.D.share(blk, FARMLAND) >= 0.3:
            return "farmland"
        return None

    def big_share(self, poly):
        if self.big_tree is None:
            return 0.0
        a = sum(self.big[i].intersection(poly).area for i in self.big_tree.query(poly) if self.big[i].intersects(poly))
        return a / max(poly.area, 1e-6)

    def house_cover(self, poly):
        return sk.houses_cover(self.lot_tree, self.lot_arr, poly) if self.lot_tree is not None else 0.0

    def blocked(self, poly):
        """True when poly reaches ground no site may take (markers,
        KeepOut)."""
        return self.fixed is not None and self.fixed.intersects(poly)

    def cut_big(self, lot, margin=2.0):
        """The lot without the large roofs (which stay) and margin m round
        them: its largest part, or None."""
        if lot is None or self.big_tree is None:
            return lot
        g = lot.poly.buffer(margin)
        near = [self.big[i] for i in self.big_tree.query(g) if self.big[i].intersects(g)]
        if not near:
            return lot
        rest = sk.largest(lot.poly.difference(unary_union(near).buffer(margin, join_style="mitre")))
        return None if rest is None else sk.Lot(rest.simplify(0.3), lot.F, lot.concrete, lot.kind)

    def reserve(self, poly):
        self.mine.append(poly)
        self.mine_tree = None

    def mine_hits(self, poly, margin=2.0):
        if not self.mine:
            return False
        if self.mine_tree is None:
            self.mine_tree = STRtree(self.mine)
        g = poly.buffer(margin)
        return any(self.mine[i].intersects(g) for i in self.mine_tree.query(g))


def frontage_range(lot, road_line, w):
    """Local x range of the lot's edge along a road (within 4 m of local y
    0)."""
    edge = lot.poly.exterior.intersection(road_line.buffer(w / 2 + sk.ROAD_SETBACK_M + 1.2))
    pts = [lot.F.to_local(x, y) for g in getattr(edge, "geoms", [edge]) if not g.is_empty
           for x, y in getattr(g, "coords", [])]
    xs = [p[0] for p in pts if p[1] < 4.0]
    return (min(xs), max(xs)) if xs else None


def traffic(c, F, mains, w):
    """Which way traffic runs past a corner lot's main frontage (it drives
    on the right): (side, travel, entry x): side +1 when the lot is to the
    right of the road line's own direction, travel the unit direction of the
    traffic on the lot's side, and the local x of the main driveway that
    traffic reaches first."""
    line = c.main[0]
    p = c.v + c.u * 20.0
    t = sk.tangent(line, *p)
    right = np.array([-t[1], t[0]])
    side = 1.0 if right @ c.n > 0 else -1.0
    travel = t * side
    xs = sorted(x for x in mains)
    entry = xs[0] if travel @ c.u > 0 else xs[-1]
    return side, travel, entry


# ------------------------------------------------------------ gas stations

class StationPlan:
    def __init__(self, c, lot, canopy, kiosk, kiosk_front, wash, mouths, lanes, ring, kiosk_pad):
        self.c, self.lot = c, lot
        self.canopy, self.rows, self.per_row = canopy, 0, 0
        self.kiosk, self.kiosk_front, self.wash = kiosk, kiosk_front, wash
        self.mouths, self.lanes, self.ring, self.kiosk_pad = mouths, lanes, ring, kiosk_pad


def canopy_size(rows, per_row):
    length = per_row * ISLAND_M[0] + (per_row - 1) * ISLAND_GAP_M + 2 * OVERHANG_M
    depth = (rows - 1) * (LANE_M + ISLAND_M[1]) + ISLAND_M[1] + 2 * OVERHANG_M
    return length, depth


def kiosk_poly(F, name, x, y, mirror):
    pts = [(-px if mirror else px, py) for px, py in KIOSKS[name]]
    return F.poly([(x + px, y + py) for px, py in pts]).buffer(0)


def plan_station(ctx, c, rng, free=None):
    """Lays out a station on a street corner, on its corner lot. free: for
    a station laid out again at build time, a function that cuts the lot
    down to the land still free for it (a polygon, or None). Returns a
    StationPlan or None when the pieces do not fit."""
    want_wash = rng.random() < WASH_SHARE
    grow = 1.18 if want_wash else 1.0
    along = rng.uniform(*STATION_LOT_M[0]) * grow, rng.uniform(*STATION_LOT_M[1]) * grow
    lot = ctx.cut_big(sk.corner_lot(c, ctx.R, *along))
    if lot is not None and free is not None:
        g = free(lot.poly)
        lot = None if g is None else sk.Lot(g, lot.F, lot.concrete, lot.kind)
    if lot is None or lot.poly.area < 1700 or (free is None and ctx.mine_hits(lot.poly, 10.0)):
        return None
    F = lot.F
    xmin, xmax, ymin, ymax = sk.box_of(lot.F, lot.poly)
    fr = frontage_range(lot, c.main[0], c.main[1])
    if fr is None or fr[1] - fr[0] < 34.0:
        return None
    options = list(CANOPIES)
    weights = np.array(list(CANOPIES.values()))
    order = list(rng.choice(len(options), size=len(options), replace=False, p=weights / weights.sum()))
    names = list(rng.permutation(list(KIOSKS)))
    mirror = rng.random() < 0.5
    pref = (fr[0] + fr[1]) / 2 + rng.uniform(-2.0, 4.0)
    corner = Point(*c.v).buffer(CORNER_CLEAR_M)
    # The canopy sizes in their drawn order; for each, the kiosk behind the
    # canopy first, then beside it on the far side (the corner keeps its
    # island), then beside it on the corner side. A station that wants a car
    # wash takes the first layout with room for one within WASH_TRIES more
    # layouts after the first that fits without; failing that, that one.
    fallback, extra = None, 0
    for oi in order:
        rows, per_row = options[oi]
        Lc, Dc = canopy_size(rows, per_row)
        for mode in ("behind", "far", "corner"):
            xs = np.arange(xmin + Lc / 2, xmax - Lc / 2 + 0.01, 2.0)
            if mode == "behind":
                xs = sorted(xs, key=lambda x: abs(x - pref))[:14]
            elif mode == "corner":
                xs = xs[::-1]
            for y0 in (11.0, 12.5, 14.0):
                for cx in xs:
                    canopy = F.rect(cx - Lc / 2, y0, cx + Lc / 2, y0 + Dc)
                    if not lot.fits(canopy, RING_M) or canopy.buffer(RING_M).intersects(corner):
                        continue
                    got = place_kiosk(lot, canopy, cx, Lc, y0, Dc, names, mirror, mode, corner)
                    if got is None:
                        continue
                    kiosk, kfront = got
                    wash = place_wash(lot, canopy, kiosk, kfront, cx, Lc, y0, Dc, rng, corner) if want_wash else None
                    plan = drives(c, lot, canopy, cx, Lc, y0, Dc, kiosk, kfront, wash, fr)
                    if plan is None:
                        continue
                    plan.rows, plan.per_row = rows, per_row
                    if want_wash and wash is None:
                        fallback = fallback or plan
                        extra += 1
                        if extra <= WASH_TRIES:
                            continue
                    return trim_station(fallback if want_wash and wash is None else plan)
    return trim_station(fallback) if fallback is not None else None


def trim_station(plan):
    """Cuts a station's lot down to the ground its pieces use (trim_lot),
    keeping the street corner for its island, unless that would cut a
    piece."""
    lot, wash = plan.lot, plan.wash
    used = unary_union([plan.ring, plan.kiosk_pad] + plan.lanes +
                       [m.intersection(lot.poly) for _, _, m in plan.mouths] +
                       ([wash.poly, wash.approach] if wash is not None else []))
    trimmed = sk.trim_lot(lot, used, keep=Point(*plan.c.v).buffer(CORNER_KEEP_M), verge=VERGE_M)
    if trimmed.poly.contains(plan.kiosk) and trimmed.poly.contains(plan.canopy) and \
            (wash is None or trimmed.poly.contains(wash.poly)):
        plan.lot = trimmed
    return plan


def place_kiosk(lot, canopy, cx, Lc, y0, Dc, names, mirror, mode, corner):
    """The kiosk faces the main road: behind the canopy across a lane
    (mode "behind"), or beside it on the side away from the corner ("far")
    or towards it ("corner")."""
    F = lot.F
    near = canopy.buffer(3.0, join_style="mitre")
    for name in names:
        pts = KIOSKS[name]
        w = max(p[0] for p in pts) - min(p[0] for p in pts)
        tries = []
        if mode == "behind":
            for gap in (10.0, 12.0):
                for dx in (0.0, -6.0, 6.0, -12.0, 12.0):
                    tries.append((cx + dx, y0 + Dc + gap))
        else:
            side = 1 if mode == "far" else -1
            kx = cx + side * (Lc / 2 + 11.0 + w / 2)
            for ky in (y0 + 2.0, y0 + 6.0, y0):
                tries.append((kx, ky))
        for kx, ky in tries:
            k = kiosk_poly(F, name, kx, ky, mirror)
            if not lot.fits(k, 1.5):
                continue
            band = F.rect(kx - w / 2 - 2.0, ky - 7.0, kx + w / 2 + 2.0, ky)
            if band.intersects(near) or not lot.poly.buffer(1.0).contains(band) or k.buffer(1.6).intersects(corner):
                continue
            return k, (kx, ky, w)
    return None


class Wash:
    """A placed car wash: its footprint, its frame (x along the wash bay
    from its entrance end, y across) and the paved approaches at both
    ends."""

    def __init__(self, poly, frame, approach):
        self.poly, self.frame, self.approach = poly, frame, approach


def place_wash(lot, canopy, kiosk, kfront, cx, Lc, y0, Dc, rng, corner):
    """A drive-through car wash, its long side along a lane: beside the
    kiosk with its front in line, behind the canopy, or beside the canopy
    along a side lane (first on the side away from the kiosk); clear of
    the street corner's island."""
    F = lot.F
    kx, ky, kw = kfront
    L, W = WASH_M
    tries = []
    for side in (1, -1) if rng.random() < 0.5 else (-1, 1):
        for dy in (0.0, 2.0):
            tries.append(("x", kx + side * (kw / 2 + 8.5 + L / 2), ky + dy))
    for gap in (10.0, 13.0):
        for dx in (0.0, -6.0, 6.0, -12.0, 12.0):
            tries.append(("x", cx + dx, y0 + Dc + gap))
    away = 1.0 if kx < cx else -1.0
    for side in (away, -away):
        for dy in (2.0, 6.0, -2.0, 10.0):
            tries.append(("y", cx + side * (Lc / 2 + RING_M + 1.0 + W / 2), y0 + dy + L / 2))
    for axis, wx, wy in tries:
        if axis == "x":
            wash = F.rect(wx - L / 2, wy, wx + L / 2, wy + W)
            ends = F.rect(wx - L / 2 - 7.0, wy - 0.5, wx + L / 2 + 7.0, wy + W + 0.5)
            frame = sk.LFrame(F.pt(wx - L / 2, wy), F.u, F.n)
        else:
            wash = F.rect(wx - W / 2, wy - L / 2, wx + W / 2, wy + L / 2)
            ends = F.rect(wx - W / 2 - 0.5, wy - L / 2 - 7.0, wx + W / 2 + 0.5, wy + L / 2 + 7.0)
            frame = sk.LFrame(F.pt(wx + W / 2, wy - L / 2), F.n, -F.u)
        if not lot.fits(wash, 1.5) or not lot.poly.buffer(0.5).contains(ends):
            continue
        if ends.intersects(kiosk.buffer(1.5)) or wash.intersects(canopy.buffer(RING_M)) or \
                wash.buffer(1.6).intersects(corner):
            continue
        if axis == "x" and ends.intersects(canopy.buffer(4.0)):
            continue
        return Wash(wash, frame, ends)
    return None


def drives(c, lot, canopy, cx, Lc, y0, Dc, kiosk, kfront, wash, fr):
    """The driveways and lanes: an entry and an exit on the main road near
    the canopy's ends, one more on the side road, the paved ring round the
    canopy, the kiosk's front band and the car wash's approaches."""
    F = lot.F
    x_lo = fr[0] + DRIVE_W_M / 2 + CORNER_CLEAR_M
    x_hi = fr[1] - DRIVE_W_M / 2 - 2.0
    blocked = [kiosk.buffer(1.5)] + ([wash.poly.buffer(1.5), wash.approach] if wash is not None else [])

    def clear(x):
        m = sk.mouth(F, x, DRIVE_W_M, depth_in=y0 + 2.0, depth_out=2.5)
        return not any(m.intersects(b) for b in blocked)

    # The entry and exit as far apart as the frontage allows: one on the
    # corner side of the canopy, one towards the far end.
    xa = next((x for x in np.arange(x_lo, cx, 1.0) if clear(x)), None)
    if xa is None:
        return None
    xb = next((x for x in np.arange(x_hi, xa + DRIVE_W_M + 9.0, -1.0) if clear(x)), None)
    if xb is None:
        return None
    mouths = [("main", float(xa), sk.mouth(F, xa, DRIVE_W_M, depth_in=y0 + 2.0, depth_out=2.5)),
              ("main", float(xb), sk.mouth(F, xb, DRIVE_W_M, depth_in=y0 + 2.0, depth_out=2.5))]
    ring = canopy.buffer(RING_M, join_style="round", quad_segs=6)
    lanes = []
    if c.side_kind not in ("path", "track"):
        # The side driveway leads to the lane behind or beside the canopy.
        sy = c.s @ c.n
        if sy > 0.2:
            for ty in (y0 + Dc + 5.0, y0 + Dc * 0.6, y0 + Dc + 9.0):
                t = ty / sy
                poly, p, ns = sk.side_mouth(c, F, t, DRIVE_W_M, depth_in=3.0)
                if t < 14.0 or poly.intersection(lot.poly).area < 0.5 * DRIVE_W_M * 2.0:
                    continue
                target = ring.exterior.interpolate(ring.exterior.project(Point(p)))
                if np.hypot(target.x - p[0], target.y - p[1]) > SIDE_LANE_MAX_M:
                    continue
                lane = LineString([tuple(p), (target.x, target.y)]).buffer(DRIVE_W_M / 2, cap_style="flat")
                if lane.intersects(kiosk.buffer(1.0)) or (wash is not None and lane.intersects(wash.poly.buffer(1.0))):
                    continue
                mouths.append(("side", t, poly))
                lanes.append(lane)
                break
    for x in (xa, xb):
        lanes.append(F.rect(min(x, cx) - DRIVE_W_M / 2, y0 - 6.0, max(x, cx) + DRIVE_W_M / 2, y0 - 1.0)
                     .difference(kiosk.buffer(1.6, join_style="mitre")))
    kx, ky, kw = kfront
    kiosk_pad = unary_union([F.rect(kx - kw / 2 - 3.0, ky - 8.0, kx + kw / 2 + 3.0, ky + 0.5),
                             kiosk.buffer(1.6, join_style="mitre")])
    lanes.append(LineString([F.pt(kx, ky - 4.0), F.pt(cx, y0 + Dc / 2)]).buffer(4.0, cap_style="flat"))
    if wash is not None:
        lanes.append(wash.approach.difference(wash.poly))
    return StationPlan(c, lot, canopy, kiosk, kfront, wash, mouths, lanes, ring, kiosk_pad)


def choose_stations(ctx):
    corners = sk.street_corners(ctx.blocks, ctx.R, set(STATION_ROADS), area=ctx.inner)
    cands = []
    for c in corners:
        if ctx.block_use(c.block) is not None or c.side_kind in ("path", "track"):
            continue
        if not ctx.inner.contains(Point(*c.v)):
            continue
        score = STATION_ROADS[c.main_kind] + 0.6 * sk.place_hash(301, *c.v)
        cands.append((score, c))
    cands.sort(key=lambda t: -t[0])
    chosen, pts = [], []
    for _, c in cands:
        if len(chosen) >= STATIONS:
            break
        if pts and np.min(np.hypot(*(np.asarray(pts) - c.v).T)) < STATION_SPACING_M:
            continue
        plan = plan_station(ctx, c, sk.place_rng(303, *c.v))
        if plan is None or ctx.blocked(plan.lot.poly):
            continue
        chosen.append(plan)
        pts.append(c.v)
        ctx.reserve(plan.lot.poly)
    ctx.stats["stations_chosen"] = len(chosen)
    return chosen


def build_station(ctx, plan):
    site = ctx.site
    c = plan.c
    free = sk.free_part(site, plan.lot.poly)
    if free is None or free.area < plan.lot.poly.area - 0.1:
        # Another module took part of the lot: the station is laid out
        # again on its whole corner lot less the land taken and the places
        # the other site types chose beside it.
        if free is None or free.area < 0.85 * plan.lot.poly.area:
            ctx.count("stations_skipped")
            return
        others = [m for m in ctx.mine if m is not plan.lot.poly and m.distance(plan.lot.poly) < 60.0]
        others = unary_union(others).buffer(2.0, join_style="mitre") if others else None

        def cut(poly):
            g = sk.free_part(site, poly)
            if g is not None and others is not None:
                g = sk.largest(g.difference(others))
            return g

        plan = plan_station(ctx, c, sk.place_rng(303, *c.v), free=cut)
        if plan is None:
            ctx.count("stations_skipped")
            return
        ctx.count("stations_replanned")
    lot, F = plan.lot, plan.lot.F
    rng = sk.place_rng(307, *c.v)
    lot, dropped = sk.take_land(site, lot, "sites:gas_station")
    ctx.count("houses_removed", dropped)
    kx, ky, kw = plan.kiosk_front
    sk.building(site, plan.kiosk, "fuel_kiosk", sk.LFrame(F.pt(kx, ky), F.u, F.n))
    pieces = [plan.kiosk]
    if plan.wash is not None:
        sk.building(site, plan.wash.poly, "car_wash", plan.wash.frame)
        pieces.append(plan.wash.poly)
        ctx.count("car_washes")
    mouth_polys = [sk.driveway(m, lot.poly, lot.concrete) for _, _, m in plan.mouths]
    paved = [plan.ring, plan.kiosk_pad] + plan.lanes
    apron, islands = sk.shape_ground(lot, paved, pieces, mouth_polys, keep=Point(*c.v).buffer(CORNER_ISLAND_M))
    # Pump islands in rows along the road, under the canopy.
    loc = [F.to_local(x, y) for x, y in plan.canopy.exterior.coords]
    cx0, cx1 = min(p[0] for p in loc), max(p[0] for p in loc)
    cy0, cy1 = min(p[1] for p in loc), max(p[1] for p in loc)
    # The fill points of the underground tanks: a row of covers on the
    # apron beside the canopy.
    covers = []
    inner = apron.buffer(-1.2)
    for lx in (cx1 + 2.6, cx0 - 2.6):
        n = int(rng.integers(3, 6))
        ly = (cy0 + cy1) / 2 - n * 0.65
        if inner.contains(F.rect(lx - 0.6, ly - 0.6, lx + 0.6, ly + n * 1.3 + 0.6)):
            covers = [F.pt(lx, ly + k * 1.3) for k in range(n)]
            break
    pumps, pillars, slots = [], [], []
    for j in range(plan.rows):
        yi = cy0 + OVERHANG_M + j * (LANE_M + ISLAND_M[1])
        for i in range(plan.per_row):
            xi = cx0 + OVERHANG_M + i * (ISLAND_M[0] + ISLAND_GAP_M)
            isl = F.rect(xi, yi, xi + ISLAND_M[0], yi + ISLAND_M[1])
            pumps.append((isl, xi + ISLAND_M[0] / 2, yi + ISLAND_M[1] / 2))
            for px in (xi + 0.45, xi + ISLAND_M[0] - 0.45):
                pillars.append(F.rect(px - 0.25, yi + 0.4, px + 0.25, yi + ISLAND_M[1] - 0.4))
            for side in (-1, 1):
                slots.append((xi + ISLAND_M[0] / 2, yi + ISLAND_M[1] / 2 + side * (ISLAND_M[1] / 2 + 2.0)))
    for isl, _, _ in pumps:
        site.obstacles.add(obstacles.PIPE, isl)
    for isl, x, y in pumps:
        for dx in (-1.5, 1.5):
            px, py = F.pt(x + dx, y)
            sk.clutter(site, "fuel_pump", px, py, F.ang, clear=-0.3)
    ctx.count("stations")
    ctx.place("gas_station", lot.poly)
    ctx.count("pump_islands", len(pumps))
    ctx.count(f"canopies_{plan.rows}x{plan.per_row}")
    # The price pylon on the island nearest the street corner, at the
    # island's point nearest the corner (PYLON_KERB_M inside its kerb).
    pylon, best = None, None
    corner_pt = Point(*c.v)
    for g in style.polys(islands):
        inner = g.buffer(-PYLON_KERB_M)
        if inner.is_empty:
            continue
        p = nearest_points(inner, corner_pt)[0]
        d = p.distance(corner_pt)
        if d < 26.0 and (best is None or d < best[0]):
            best = (d, p)
    if best is not None:
        pylon = (best[1].x, best[1].y, rng.uniform(8.0, 12.0))
    # Vehicles: at the pumps, in front of the kiosk, the queue, wrecks.
    avoid = [plan.kiosk.buffer(0.4)] + ([plan.wash.poly.buffer(0.4)] if plan.wash is not None else []) + \
            [isl.buffer(0.25) for isl, _, _ in pumps] + [g.buffer(-0.4) for g in style.polys(islands)]
    park = sk.Parker(site, rng, avoid, ctx.stats.setdefault("vehicles", {}))
    mains = [x for k, x, _ in plan.mouths if k == "main"]
    side, travel, entry_x = traffic(c, F, mains, c.main[1])
    queue = rng.random() < QUEUE_SHARE
    for x, y in slots:
        if rng.random() < (0.8 if queue else PUMP_CAR_CHANCE):
            px, py = F.pt(x + rng.uniform(-0.8, 0.8), y)
            ang = F.ang + (np.pi if travel @ F.u < 0 else 0.0) + rng.normal(0, 0.04)
            park.car(px, py, ang, wreck_share=0.1)
    bays = sk.bay_row(F, kx - kw / 2 + 0.3, kx + kw / 2 - 0.3, ky - 0.6 - sk.BAY_D, +1, apron.buffer(0.2))
    bays = [b for b in bays if not b.poly().intersects(plan.kiosk.buffer(0.3))]
    park.fill_bays(bays, rng.uniform(0.2, 0.7), wreck_share=0.08)
    if queue:
        ctx.count("queues")
        station_queue(ctx, plan, park, rng, side, travel, entry_x)
    for _ in range(int(rng.integers(0, 3))):
        p = sk.sample_in(apron.buffer(-2.0), rng)
        if p is not None:
            park.car(p[0], p[1], rng.uniform(0, 2 * np.pi), wreck_share=1.0)
    # Clutter by the kiosk: the air and water post, tyres, drums, crates.
    for name, dx in (("air_post", -(kw / 2 + 1.6)), ("tyre_stack", kw / 2 + 1.4), ("drums", kw / 2 + 1.2),
                     ("crates", -(kw / 2 + 1.4))):
        if name != "air_post" and rng.random() < 0.45:
            continue
        px, py = F.pt(kx + dx, ky - 1.2 + rng.uniform(-0.3, 0.3))
        sk.clutter(site, name, px, py, F.ang + rng.normal(0, 0.1))
    for g in style.polys(islands):
        if g.area > 18 and rng.random() < 0.35:
            for _ in range(int(rng.integers(1, 3))):
                p = sk.sample_in(g.buffer(-1.0), rng)
                if p is not None and site.props.clear_of(p[0], p[1], 1.5, ("bush", "tree")):
                    site.props.add("bush", p[0], p[1], rng.uniform(0, 6.28), (rng.uniform(1.6, 2.8),) * 2)
    seed = int(rng.integers(1 << 30))
    concrete, canopy, per_row = lot.concrete, plan.canopy, plan.per_row
    # The arrow and stop line of each main driveway are set from where the
    # lot begins across it (the frame's y = 0, the block edge, can run on the
    # road's concrete).
    marks = []
    for kind, t, _ in plan.mouths:
        if kind == "main":
            ey = next((float(y) for y in np.arange(-3.0, 8.0, 0.25) if lot.poly.contains(Point(*F.pt(t, y)))), 1.0)
            marks.append((t, ey))
    on_apron = unary_union(pieces + [isl for isl, _, _ in pumps])
    beside = unary_union([b.poly for b in sk.buildings_near(site, lot.poly, 1.0)])

    def draw(L):
        r = np.random.default_rng(seed)
        sk.draw_apron(L, apron, concrete, ang=F.ang, keep_off=on_apron)
        sk.draw_islands(L, islands)
        sk.lot_wall(L, lot, concrete, keep_off=beside)
        for isl, _, _ in pumps:
            L.fill("groundlines", isl.buffer(0.45, join_style="mitre"), 0.0, 0.35)
            L.fill("interiors", isl, 0.3)
            L.line("interiors", LineString(isl.exterior.coords), 0.12, 0.44)
        for p in pillars:
            L.fill("interiors", p, 0.1)
        for t, ey in marks:
            p = F.pt(t, ey + 3.5)
            if t == entry_x:
                sk.arrow(L, p[0], p[1], F.n)
            else:
                sk.arrow(L, p[0], p[1], -F.n)
                stop = F.line([(t - DRIVE_W_M / 2 + 0.6, ey + 0.7), (t + DRIVE_W_M / 2 - 0.6, ey + 0.7)])
                L.line("groundlines", stop, 0.35, sk.MARK_V, 0.85)
        sk.bay_lines(L, bays)
        for x, y in covers:
            L.fill("groundlines", Point(x, y).buffer(0.5, quad_segs=3), 0.12, 0.9)
            L.line("groundlines", Point(x, y).buffer(0.44, quad_segs=3).exterior, 0.08, 0.38, 0.9)
            L.fill("groundlines", Point(x, y).buffer(0.12, quad_segs=2), 0.3, 0.9)
        sk.canopy(L, canopy, F, r)
        # Lights over the lanes between the rows; under a one-row canopy,
        # over the pump sides.
        lanes_y = [y + ISLAND_M[1] / 2 + LANE_M / 2 for _, _, y in pumps[::per_row]][:-1]
        if not lanes_y:
            lanes_y = [pumps[0][2] - 3.0, pumps[0][2] + 3.0]
        sk.canopy_lights(L, F, [x for _, x, _ in pumps[:per_row]], lanes_y)
        if pylon is not None:
            sk.price_pylon(L, pylon[0], pylon[1], F.u, pylon[2], r)
    site.drawers.append(draw)


def station_queue(ctx, plan, park, rng, side, travel, entry_x):
    """Cars abandoned in a queue: one or two nosed into the entry driveway,
    then a line from the entry back along the kerb lane of the main road,
    upstream (traffic drives on the right)."""
    c, F = plan.c, plan.lot.F
    line, w = c.main[0], c.main[1]
    into = F.heading(0.0, 1.0)
    for k, y in enumerate((3.0, 9.5)):
        if k and rng.random() < 0.5:
            break
        px, py = F.pt(entry_x + rng.uniform(-0.6, 0.6), y)
        park.car(px, py, into + rng.normal(0, 0.12), wreck_share=0.05)
    concrete = ctx.R.concrete_near(Point(*c.v), 160.0).buffer(-0.15)
    junctions = ctx.R.junctions_near(Point(*c.v), 160.0)
    lane_off = w / 2 - 1.9
    p_entry = F.pt(entry_x, -1.0)
    t0 = sk.tangent(line, *p_entry)
    # Upstream along the line: against the traffic.
    step = -1.0 if travel @ t0 > 0 else 1.0
    dist = line.project(Point(*p_entry)) + step * 1.0
    n = int(rng.integers(*QUEUE_CARS))
    placed, first = 0, True
    for _ in range(n + 8):
        if placed >= n:
            break
        got = park.pick("vehicle", 5.4)
        if got is None:
            break
        v, size = got
        dist += step * size[0] / 2
        if dist < 0 or dist > line.length:
            break
        q = line.interpolate(dist)
        tt = sk.tangent(line, q.x, q.y)
        pos = np.array([q.x, q.y]) + np.array([-tt[1], tt[0]]) * side * lane_off
        dist += step * (size[0] / 2 + rng.uniform(0.8, 2.2))
        # The queue leaves the junctions it crosses clear and runs on past
        # them.
        if len(junctions) and np.min(np.hypot(*(junctions - pos).T)) < QUEUE_JUNCTION_M:
            continue
        heading = tt if tt @ travel > 0 else -tt
        ang = float(np.arctan2(heading[1], heading[0])) + rng.normal(0, 0.05)
        if first:
            ang += 0.3 * (1.0 if sk.cross(heading, c.n) > 0 else -1.0)
        elif rng.random() < 0.15:
            ang += rng.uniform(-0.35, 0.35)
        first = False
        kind = "vehicle_wreck" if rng.random() < 0.1 else "vehicle"
        if park.put(kind, float(pos[0]), float(pos[1]), ang, v, size, on_road=True, concrete=concrete):
            placed += 1
    ctx.count("queue_cars", placed)


# ------------------------------------------------------------------ build

class SiteType:
    """A site type as data. kind names it; its places are chosen over the
    whole map either by choose(ctx) (a type with its own chooser) or from
    find(ctx), the candidate places (the lot finder), by score(ctx, cand)
    (a rank, or None to pass a candidate over), up to count of them at
    least spacing metres apart, each laid out by plan(ctx, cand, rng) (the
    lot shaper and the pieces with their placement rules: a plan, or None
    when they do not fit) with random numbers seeded by seed and the
    place; build(ctx, plan) builds a chosen place, where(plan) is its
    ground (to test against the window)."""

    def __init__(self, kind, build, choose=None, find=None, count=0, spacing=0.0, score=None, plan=None, seed=0,
                 where=None):
        self.kind, self.build, self.choose_fn = kind, build, choose
        self.find, self.count, self.spacing, self.score, self.plan, self.seed = find, count, spacing, score, plan, seed
        self.where = where or (lambda p: p.lot.poly)

    def choose(self, ctx):
        if self.choose_fn is not None:
            return self.choose_fn(ctx)
        return sl.pick_sites(ctx, self.kind, self.find(ctx), self.count, self.spacing,
                             lambda cand: self.score(ctx, cand), lambda cand, rng: self.plan(ctx, cand, rng),
                             self.seed)


def all_streets(ctx):
    """Half the frontages on every street a garage may front (by a fixed
    hash of the place)."""
    return sl.frontage_points(ctx, set(sl.GARAGE_STREETS) | MAIN_ROADS, 607, share=0.5)


## The site types, in the order they choose their places (each keeps off
## the places the ones before it chose) and build them.
SITE_TYPES = [
    SiteType("gas_station", lambda ctx, p: build_station(ctx, p), choose=lambda ctx: choose_stations(ctx)),
    SiteType("dealer", sl.build_dealer,
             find=lambda ctx: sl.frontage_points(ctx, MAIN_ROADS, 601),
             count=sl.DEALERSHIPS, spacing=sl.DEALER_SPACING_M,
             score=lambda ctx, fr: sl.DEALER_ROADS.get(fr.kind), plan=sl.plan_dealer, seed=603),
    SiteType("bus_depot", sl.build_depot,
             find=lambda ctx: sl.frontage_points(ctx, MAIN_ROADS, 601),
             count=sl.BUS_DEPOTS, spacing=sl.DEPOT_SPACING_M,
             score=lambda ctx, fr: 0.6 - 0.5 * ctx.house_cover(Point(*fr.p).buffer(30.0)),
             plan=sl.plan_depot, seed=605),
    SiteType("truck_yard", sl.build_truck_yard,
             find=lambda ctx: [fr for fr in all_streets(ctx) if int(ctx.D.at(*fr.p)) == INDUSTRIAL],
             count=sl.TRUCK_YARDS, spacing=sl.TRUCK_SPACING_M,
             score=lambda ctx, fr: 0.5, plan=sl.plan_truck_yard, seed=609),
    SiteType("car_park", sl.build_car_park,
             find=lambda ctx: [fr for fr in all_streets(ctx) if fr.kind in sl.CAR_PARK_ROADS
                               and int(ctx.D.at(*fr.p)) in (RESIDENTIAL, MARKET)],
             count=sl.CAR_PARKS, spacing=sl.CAR_PARK_SPACING_M,
             score=lambda ctx, fr: sl.CAR_PARK_ROADS[fr.kind] + 0.4 * (int(ctx.D.at(*fr.p)) == MARKET)
             - 0.5 * ctx.house_cover(Point(*fr.p).buffer(20.0)),
             plan=sl.plan_car_park, seed=611),
    SiteType("garage", sl.build_garage, choose=sl.choose_garages),
    SiteType("front_parking", lambda ctx, s: sl.build_front(ctx, *s), choose=sl.front_strips, where=lambda s: s[0]),
    SiteType("side_park", lambda ctx, s: sl.build_side_park(ctx, *s), choose=sl.side_parks, where=lambda s: s[0]),
]


def build(site):
    """Builds the service sites. Returns the module's stats. The site types
    (SITE_TYPES) choose their places over the whole map in their order,
    each keeping off the places the ones before it chose; then each place
    that touches the window is built, type by type."""
    ctx = Ctx(site)
    first_drawer = len(site.drawers)
    chosen = [(t, t.choose(ctx)) for t in SITE_TYPES]
    # Every chosen place over the whole map (kind, centre in m), also in a
    # window run: where to aim a window to look at one.
    ctx.stats["chosen"] = [[t.kind, round(t.where(p).centroid.x, 1), round(t.where(p).centroid.y, 1)]
                           for t, plans in chosen for p in plans]
    for t, plans in chosen:
        for plan in plans:
            if site.in_window(t.where(plan)):
                t.build(ctx, plan)
    # The vehicles still on the map (a later place's clear_area can take a
    # few an earlier one put down), and the marks that keep the generic road
    # vehicles off the ones on the road.
    put = ctx.stats.get("vehicles", {})
    have = sk.placed(site).present(site.props)
    v = {}
    for it in have:
        v[it[0]] = v.get(it[0], 0) + 1
    ctx.stats["vehicles"] = v
    ctx.stats["vehicles_total"] = len(have)
    ctx.stats["vehicles_cleared_later"] = int(sum(put.values())) - len(have)
    sk.guard_vehicles(site)
    site.drawers[first_drawer:] = [counted(fn, ctx.stats) for fn in site.drawers[first_drawer:]]
    return ctx.stats


def counted(draw, stats):
    """A drawer that adds the triangles it draws to stats["triangles"] (the
    sites' ground, overheads and talls; their buildings are drawn with the
    others)."""

    def run(L):
        put, own = L._put, "_put" in L.__dict__

        def counting(sub, key, tris, *args, **kw):
            stats["triangles"] = stats.get("triangles", 0) + int(np.asarray(tris).size // 6)
            return put(sub, key, tris, *args, **kw)

        L._put = counting
        try:
            draw(L)
        finally:
            if own:
                L._put = put
            else:
                del L._put

    return run
