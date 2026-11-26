"""Building sites: half-built concrete frames you can see and shoot through,
tower cranes, and the fenced yards round them.

Where (choose(), over the whole map's layout):
  road site    a large site beside the OSM road under construction
               (highway=construction), as near its concrete as there is
               room, over generated lots if need be (they are taken out);
               the road itself gets its works (road_works)
  large sites  LARGE_SITES more on open ground beside streets in the
               residential and market districts, inside the city
               (URBAN_LOTS generated lots within URBAN_R_M), spread out
  infill       INFILL_SITES small sites in dense residential blocks: the two
               to five generated lots along a street that a frame's plot
               covers are taken out
Every plot keeps ROAD_SETBACK_M off all road concrete besides its own
street's gap, and is kept clear of the generic props (Site.solid_extra).

A frame is a building of kind "frame" pinned to the collapsed state, so the
game gives it no walls, no slow, no light occluder and no route cost:
mechas walk in and see and shoot through it. It draws itself (draw_frame):
the ground slab with its column bases and some brick infill on the ground;
the upper floors, FLOOR_M apart, in the talls sublayer: the columns between
floors as posts, the poured bays as translucent slabs (SLAB_A each, less on
tall frames, so that all the floors stacked straight above a mecha cover at
most SLAB_COVER of it), the beams along the column lines, rebar sticking
out of the top floor's columns and a few columns of the next storey
started; the top floor is only partly poured. The stair and lift core is a
solid prism and a ground obstacle.

Large sites also get a tower crane (draw_crane: a 6 m base pad that is a
ground obstacle, with a control_cabinet source behind it at CABINET_AT,
whose spot the yard layout keeps clear, a lattice mast
CRANE_H_M high, the jib and counter-jib with its counterweight, the cab, the
trolley and the hook with a load), sometimes a mobile crane (its chassis an
obstacle), a fence with a gate, portacabins and a guard hut (hut props),
and a materials yard: rebar stacks (a "building_materials" salvage source),
sand and gravel heaps, formwork, pallets and sacks, a cable drum (a salvage
source) and a genset (a clutter prop with no source: the sites give no
fuel). Infill sites get a fence along the street, some pallets in their
yard (what the lots they take out leave beside the frame) and a heap on the
free ground beside the frame where it fits whole, shadow and all, else on
the frame's ground floor (drawn by draw_frame over its slab); the yard and
the heap's spot are claimed with the plot (infill_yard). No dump trucks or
tankers: they belong to the industrial district only.

A frame draws its site's cranes after itself, so the jib is drawn over the
floors. The biggest large site is a landmark, named after its crane.
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from shapely import STRtree, contains_xy
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import polylabel, substring, unary_union

import buildings as bl
import district_life
import equipment
import kit
import obstacles
import ruins
import style
from frame import PLAY_HALF_M
from gen_city import HALF_M, ROAD_SETBACK_M, block_rng, to_frame_m
from zones import WATER

LARGE_SITES = 4
INFILL_SITES = 7
## Large site plot: length along the street and depth (ranges, m); infill
## plot likewise.
LARGE_SIZE_M = ((50.0, 72.0), (38.0, 52.0))
INFILL_SIZE_M = ((15.0, 23.0), (12.0, 17.0))
LARGE_SPACING_M = 550.0
INFILL_SPACING_M = 320.0
## Sites stay this far inside the play area's edge (m).
SITE_MARGIN_M = 250.0
## Gap between a street's concrete and a large site's fence (m), and
## between the concrete and an infill plot.
ROAD_GAP_M = 3.0
INFILL_GAP_M = 1.2
## Gaps (m) tried, nearest first, between the road under construction and
## its site.
ROAD_SITE_GAPS_M = (3.0, 12.0, 24.0, 32.0, 40.0)
## A large site is in the city with at least URBAN_LOTS generated lots
## within URBAN_R_M; an infill site needs DENSE_LOTS.
URBAN_R_M = 150.0
URBAN_LOTS = 60
DENSE_LOTS = 160
## Streets that large and infill sites face.
LARGE_STREETS = {"residential", "unclassified", "tertiary", "tertiary_link", "secondary", "service"}
INFILL_STREETS = {"residential", "unclassified", "tertiary"}
## An infill plot takes out the lots it covers; each must lie at least
## INFILL_COVER of its area inside the plot.
INFILL_COVER = 0.6
## A heap's outline (ruins.noisy_disc at HEAP_ROUGH) reaches out to
## HEAP_REACH times its radius, and its shadow HEAP_SHADOW_M beyond that.
HEAP_ROUGH = 0.18
HEAP_REACH = 1.24 + HEAP_ROUGH / 2
HEAP_SHADOW_M = 0.9
## An infill site's heap (radius range, m) stands on the free ground within
## INFILL_HEAP_REACH_M of its plot, at least INFILL_HEAP_FRAME_M off the
## frame, shrunk to fit; where less than INFILL_HEAP_MIN_M fits there, it
## stands on the frame's ground floor, INFILL_HEAP_FRAME_M off the core.
INFILL_HEAP_M = (1.2, 1.8)
INFILL_HEAP_REACH_M = 5.0
INFILL_HEAP_FRAME_M = 0.4
INFILL_HEAP_MIN_M = 0.8
## The road under construction's gravel heaps (radius range, m) stand
## ROAD_HEAP_OFF_M to one side of its centre line, moved in and shrunk so
## they stay on its concrete, outline and shadow; left out under
## ROAD_HEAP_MIN_M.
ROAD_HEAP_M = (1.0, 1.5)
ROAD_HEAP_OFF_M = 1.6
ROAD_HEAP_MIN_M = 0.6

FLOOR_M = 3.2
BAY_M = (4.6, 6.2)
FLOORS = {"large": (3, 7), "infill": (2, 6)}
SLAB_V, SLAB_A = 0.22, 0.35
## The most that the slabs of all a frame's floors cover together where they
## stack (straight below the camera); each floor's alpha follows from it.
SLAB_COVER = 0.55
BEAM_V, COLUMN_V, REBAR_V = 0.27, 0.3, 0.42
CORE_SIDE_V, CORE_TOP_V = 0.19, 0.14
CRANE_H_M = (35.0, 50.0)
## The biggest large site is "the Big Crane" when its crane is at least
## this high (m), else "the Crane".
BIG_CRANE_M = 44.0
JIB_M = (40.0, 60.0)
COUNTER_JIB_M = (12.0, 17.0)
MAST_V, JIB_V, CW_V = 0.33, 0.36, 0.2
## Where the crane's control cabinet (a salvage source, turned across the
## jib) stands, in the crane's frame (x along the jib): behind the base pad.
CABINET_AT = (-4.5, 0.0)
MOBILE_CRANE_CHANCE = 0.4
GRID_M = 2.0
## Street blocks with this share of the industrial, market or farmland
## district are rebuilt by those modules; sites keep out of them.
REBUILT_SHARE = 0.45
## OSM land uses kept clear (see reserved_area), and the boxes (x0, y0,
## x1, y1, m) of the real places the other site modules build: the Japanese
## Garden, the hospital campus, the Helwan Metro Station, the Helwan General
## Club, the Helwan Observatory, Ain Helwan Metro Station, the university.
OSM_RESERVED = {"landuse": {"cemetery", "plant_nursery", "quarry", "industrial", "commercial"},
                "natural": {"water"}, "amenity": {"grave_yard", "school", "hospital", "university"},
                "leisure": {"park", "pitch", "sports_centre", "stadium", "garden"}}
RESERVED_GROW_M = 25.0
RESERVED_PLACES = [(1480.0, -1220.0, 2120.0, -780.0), (1660.0, -1640.0, 1860.0, -1230.0),
                   (1180.0, -1090.0, 1390.0, -880.0), (1560.0, -180.0, 1800.0, 60.0),
                   (1930.0, -2110.0, 2230.0, -1800.0), (300.0, -2500.0, 500.0, -2280.0),
                   (-800.0, -2500.0, -120.0, -2330.0)]


def count(name, n):
    style.KIT_TRIS[name] = style.KIT_TRIS.get(name, 0) + n


class Ground:
    """A GRID_M grid over the map: what the whole map's layout has taken
    (occ: lots, large roofs, roads and rail; hard: the same less the lots),
    and how many lots are near each cell. The road and rail concrete is also
    kept as polygons, for road_gap."""

    def __init__(self, site):
        n = int(round(2 * HALF_M / GRID_M))
        self.n = n
        im, hard = Image.new("1", (n, n)), Image.new("1", (n, n))
        d, dh = ImageDraw.Draw(im), ImageDraw.Draw(hard)
        k = 1.0 / GRID_M
        lay = site.full_layout
        self.roads = [g for g, *_ in lay["roads"]]
        for g in list(lay["lots"]) + list(lay["big"]) + self.roads:
            for p in style.polys(g):
                d.polygon([((x + HALF_M) * k, (y + HALF_M) * k) for x, y in p.exterior.coords], fill=1)
        for g in list(lay["big"]) + self.roads:
            for p in style.polys(g):
                dh.polygon([((x + HALF_M) * k, (y + HALF_M) * k) for x, y in p.exterior.coords], fill=1)
        self.occ = np.asarray(im, bool)
        self.hard = np.asarray(hard, bool)
        self.road_tree = STRtree(self.roads)
        cell = 25.0
        m = int(np.ceil(2 * HALF_M / cell))
        cen = np.array([[p.centroid.x, p.centroid.y] for p in lay["lots"]]) if lay["lots"] else np.zeros((0, 2))
        hist = np.histogram2d(cen[:, 1], cen[:, 0], bins=m, range=[[-HALF_M, HALF_M]] * 2)[0]
        r = int(URBAN_R_M / cell)
        yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
        self.lots = ndi.convolve(hist, (xx ** 2 + yy ** 2 <= r * r).astype(float), mode="constant")
        self.cell = cell
        self.sampler = site.sampler
        self.blocks = lay["blocks"]
        self.block_tree = STRtree(self.blocks)

    def lots_near(self, x, y):
        i = int(np.clip((y + HALF_M) / self.cell, 0, self.lots.shape[0] - 1))
        j = int(np.clip((x + HALF_M) / self.cell, 0, self.lots.shape[1] - 1))
        return float(self.lots[i, j])

    def _taken(self, pts, occ):
        i = np.clip(((pts[:, 1] + HALF_M) / GRID_M).astype(int), 0, self.n - 1)
        j = np.clip(((pts[:, 0] + HALF_M) / GRID_M).astype(int), 0, self.n - 1)
        return occ[i, j].any() or (self.sampler.zone_at(pts[:, 0], pts[:, 1]) == WATER).any()

    def free(self, poly, grow=0.0, lots=False):
        """True when nothing of the layout and no water is under poly
        (grown by grow), sampled every GRID_M / 2; with lots, lots may be
        under it (the site takes them out)."""
        occ = self.hard if lots else self.occ
        g = poly.buffer(grow, join_style="mitre") if grow else poly
        quick = np.asarray(g.exterior.coords)[:-1]
        c = g.centroid
        if self._taken(np.concatenate([quick * 0.7 + np.array([c.x, c.y]) * 0.3, [[c.x, c.y]]]), occ):
            return False
        x0, y0, x1, y1 = g.bounds
        xs, ys = np.meshgrid(np.arange(x0, x1, GRID_M / 2), np.arange(y0, y1, GRID_M / 2))
        pts = np.stack([xs.ravel(), ys.ravel()], 1)
        pts = pts[contains_xy(g, pts[:, 0], pts[:, 1])]
        return len(pts) > 0 and not self._taken(pts, occ)

    def road_gap(self, poly):
        """The distance (m) from poly to the nearest road or rail concrete
        (up to 20 m)."""
        idx = self.road_tree.query(poly.buffer(20.0))
        return min((float(self.roads[i].distance(poly)) for i in idx), default=20.0)


def plot_on_street(line, w, dist, side, length, depth, gap):
    """A plot length x depth beside a street (centre line, width w) at dist
    along it, on one side, gap off its concrete. Returns (polygon, centre,
    angle in degrees of a frame whose x runs along the street and whose y
    runs away from it, the point on the street)."""
    p, q = line.interpolate(dist), line.interpolate(min(dist + 1.0, line.length))
    a = float(np.arctan2(q.y - p.y, q.x - p.x))
    ux, uy = np.cos(a), np.sin(a)
    nx, ny = -uy * side, ux * side
    off = w / 2 + gap + depth / 2
    cx, cy = p.x + nx * off, p.y + ny * off
    hl, hd = length / 2, depth / 2
    pts = [(cx + ux * sx * hl + nx * sy * hd, cy + uy * sx * hl + ny * sy * hd)
           for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    ang = np.degrees(a) if side > 0 else np.degrees(a) + 180.0
    return Polygon(pts), (cx, cy), ang, (p.x, p.y)


def inside_play(poly, margin):
    x0, y0, x1, y1 = poly.bounds
    lim = PLAY_HALF_M - margin
    return min(x0, y0) > -lim and max(x1, y1) < lim


def city_share(site, poly):
    return site.districts.share(poly, 0) + site.districts.share(poly, 2)


def rebuilt_block(site, blk):
    """True for a street block that a district module rebuilds (its
    industrial, market or farmland share, over its bounding box as
    Site.blocks_of measures it, is at least REBUILT_SHARE)."""
    return any(site.districts.share(blk, code) >= REBUILT_SHARE for code in (1, 2, 3))


def in_rebuilt_block(site, blocks, tree, poly):
    return any(rebuilt_block(site, blocks[i]) for i in tree.query(poly) if blocks[i].intersects(poly))


def road_site(site, G, claimed):
    """The large site beside the OSM road under construction: as close to
    its concrete as ROAD_SITE_GAPS_M allows, on open ground if there is
    some at that gap, else over generated lots (which it takes out); along
    the road, nearest its middle first. None when there is no such road."""
    for _, _, w, _, kind, line in site.full_layout["roads"]:
        if kind != "construction" or line is None:
            continue
        dists = sorted(np.arange(20.0, line.length - 20.0, 8.0), key=lambda t: abs(t - line.length / 2))
        for gap in ROAD_SITE_GAPS_M:
            for lots in (False, True):
                for dist in dists:
                    for side in (1, -1):
                        rng = block_rng(503, Point(line.interpolate(dist).coords[0]))
                        length, depth = rng.uniform(58.0, 74.0), rng.uniform(40.0, 50.0)
                        poly, c, ang, at = plot_on_street(line, w, dist, side, length, depth, gap)
                        if not inside_play(poly, SITE_MARGIN_M) or not G.free(poly, 0.5, lots):
                            continue
                        if G.road_gap(poly) < min(gap, ROAD_GAP_M) - 0.5:
                            continue
                        if in_rebuilt_block(site, G.blocks, G.block_tree, poly):
                            continue
                        if claimed is not None and claimed.intersects(poly.buffer(2.0)):
                            continue
                        return {"kind": "large", "poly": poly, "c": c, "ang": ang, "gate": at, "w": length,
                                "d": depth, "name": "road", "road": (road_geom(site, line), line)}
    return None


def road_geom(site, line):
    """The concrete of the road whose centre line is line."""
    for g, _, _, _, kind, ln in site.full_layout["roads"]:
        if ln is line:
            return g
    return None


def road_works(site, concrete, line, rng):
    """A drawer for the road under construction itself: graded gravel over
    its concrete with tyre tracks along it, a row of barrier blocks across
    each end where it leaves the streets it joins, and a few gravel heaps
    along it, on its concrete. Its concrete is kept clear of the generic
    props."""
    seed = int(rng.integers(1 << 30))
    others = unary_union([g for g, _, _, _, kind, ln in site.full_layout["roads"]
                          if ln is not line and not kind.startswith("rail:") and g.distance(line) < 1.0])
    ends = []
    for t0, step in ((0.0, 1.0), (line.length, -1.0)):
        t = t0
        while 0.0 <= t <= line.length and not others.is_empty and others.distance(line.interpolate(t)) < 2.5:
            t += step
        ends.append(float(np.clip(t + step * 1.5, 0.0, line.length)))
    own = None
    if concrete is not None:
        own = concrete.difference(others) if not others.is_empty else concrete
        site.solid_extra.append(own)
    heaps = []
    for t in rng.uniform(0.2, 0.8, int(rng.integers(2, 4))) * line.length:
        p, q = line.interpolate(t), line.interpolate(min(t + 1.0, line.length))
        a = np.arctan2(q.y - p.y, q.x - p.x)
        side = 1.0 if rng.random() < 0.5 else -1.0
        rad, off = float(rng.uniform(*ROAD_HEAP_M)), ROAD_HEAP_OFF_M
        if own is not None:
            half = float(own.boundary.distance(p)) if own.contains(p) else 0.0
            off = min(off, max(0.0, half - rad * HEAP_REACH - HEAP_SHADOW_M))
            rad = min(rad, (half - off - HEAP_SHADOW_M) / HEAP_REACH)
            if rad < ROAD_HEAP_MIN_M:
                continue
        heaps.append((p.x - np.sin(a) * side * off, p.y + np.cos(a) * side * off, rad))

    def draw(L):
        r = np.random.default_rng(seed)
        if own is not None:
            L.fill("groundlines", own, 0.13, 0.8)
        T = style.Batch((0.0, 0.0), 0.0)
        pts = np.asarray(substring(line, ends[0] - 1.5, ends[1] + 1.5).coords)
        for (xa, ya), (xb, yb) in zip(pts[:-1], pts[1:]):
            n = np.hypot(xb - xa, yb - ya)
            if n < 0.1:
                continue
            nx, ny = -(yb - ya) / n, (xb - xa) / n
            for off in (-1.6, -0.7, 0.7, 1.6):
                T.line(xa + nx * off, ya + ny * off, xb + nx * off, yb + ny * off, 0.3, 0.07, 0.3)
        count("site_ground", T.flush(L, "groundlines", None))
        for end in ends:
            p, q = line.interpolate(min(end, line.length - 1.0)), line.interpolate(min(end + 1.0, line.length))
            B = style.Batch((p.x, p.y), np.degrees(np.arctan2(q.y - p.y, q.x - p.x)))
            for y in (-2.0, 0.0, 2.0):
                B.rect(-0.6, y - 1.05, 0.6, y + 1.05, 0.0, 0.35)
                B.rect(-0.35, y - 0.8, 0.35, y + 0.8, 0.3)
                B.line(0.0, y - 0.75, 0.0, y + 0.75, 0.12, 0.36)
            count("site_yard", B.flush(L, "interiors", style.chunk_key(Point(p.x, p.y))))
        for x, y, rad in heaps:
            heap(L, x, y, rad, r, True)
    return draw


def large_sites(site, G, claimed, taken):
    """Large sites on open ground beside streets, inside the city."""
    cands = []
    for _, _, w, _, kind, line in site.full_layout["roads"]:
        if kind not in LARGE_STREETS or line is None or line.length < 80:
            continue
        for dist in np.arange(40.0, line.length - 40.0, 35.0):
            p = line.interpolate(dist)
            if G.lots_near(p.x, p.y) < URBAN_LOTS:
                continue
            rng = block_rng(509, p)
            length, depth = rng.uniform(*LARGE_SIZE_M[0]), rng.uniform(*LARGE_SIZE_M[1])
            for side in (1, -1):
                poly, c, ang, at = plot_on_street(line, w, dist, side, length, depth, ROAD_GAP_M)
                if not inside_play(poly, SITE_MARGIN_M) or city_share(site, poly) < 0.8:
                    continue
                if not G.free(poly, 0.5) or G.road_gap(poly) < ROAD_GAP_M - 0.5:
                    continue
                if in_rebuilt_block(site, G.blocks, G.block_tree, poly):
                    continue
                if claimed is not None and claimed.intersects(poly.buffer(2.0)):
                    continue
                cands.append((-G.lots_near(c[0], c[1]), round(c[0], 1), round(c[1], 1),
                              {"kind": "large", "poly": poly, "c": c, "ang": ang, "gate": at, "w": length,
                               "d": depth}))
    cands.sort(key=lambda t: t[:3])
    out = []
    for _, x, y, s in cands:
        if len(out) >= LARGE_SITES:
            break
        if any(np.hypot(x - px, y - py) < LARGE_SPACING_M for px, py in taken):
            continue
        taken.append((x, y))
        s["name"] = f"large_{int(x)}_{int(y)}"
        out.append(s)
    return out


def infill_sites(site, G, claimed, taken):
    """Small sites in dense residential blocks, each over two to five
    generated lots along a street."""
    lots = site.full_layout["lots"]
    lot_tree = STRtree(lots)
    big = site.full_layout["big"]
    big_tree = STRtree(big)
    blocks = site.full_layout["blocks"]
    blk_tree = STRtree(blocks)
    cands = []
    for _, _, w, _, kind, line in site.full_layout["roads"]:
        if kind not in INFILL_STREETS or line is None or line.length < 60:
            continue
        for dist in np.arange(25.0, line.length - 25.0, 45.0):
            p = line.interpolate(dist)
            if G.lots_near(p.x, p.y) < DENSE_LOTS:
                continue
            rng = block_rng(521, p)
            length, depth = rng.uniform(*INFILL_SIZE_M[0]), rng.uniform(*INFILL_SIZE_M[1])
            side = 1 if rng.random() < 0.5 else -1
            poly, c, ang, at = plot_on_street(line, w, dist, side, length, depth, INFILL_GAP_M)
            if not inside_play(poly, SITE_MARGIN_M) or site.districts.share(poly, 0) < 0.9:
                continue
            home = [blocks[i] for i in blk_tree.query(poly) if blocks[i].contains(poly)]
            if not home or rebuilt_block(site, home[0]):
                continue
            if len(big_tree.query(poly.buffer(2.0))) or G.road_gap(poly) < ROAD_SETBACK_M:
                continue
            grown = poly.buffer(1.0)
            hit = [lots[i] for i in lot_tree.query(grown) if lots[i].intersects(grown)]
            if len(hit) < 2 or len(hit) > 5:
                continue
            if any(h.intersection(poly).area < INFILL_COVER * h.area for h in hit):
                continue
            if claimed is not None and claimed.intersects(poly.buffer(2.0)):
                continue
            cands.append((float(rng.random()), round(c[0], 1), round(c[1], 1),
                          {"kind": "infill", "poly": poly, "c": c, "ang": ang, "gate": at, "w": length, "d": depth,
                           "lots": unary_union(hit), "block": home[0]}))
    cands.sort(key=lambda t: t[:3])
    out = []
    for _, x, y, s in cands:
        if len(out) >= INFILL_SITES:
            break
        if any(np.hypot(x - px, y - py) < INFILL_SPACING_M for px, py in taken):
            continue
        taken.append((x, y))
        s["name"] = f"infill_{int(x)}_{int(y)}"
        near = s["poly"].buffer(INFILL_HEAP_REACH_M + 1.0)
        grown = s["poly"].buffer(1.0)
        s["houses"] = unary_union([lots[i] for i in lot_tree.query(near) if not lots[i].intersects(grown)] +
                                  [big[i] for i in big_tree.query(near)])
        out.append(s)
    return out


def reserved_area(site):
    """Land the fabric module keeps off besides the claims: OSM areas
    with a use of their own (OSM_RESERVED, grown by RESERVED_GROW_M) and the
    real places other site modules build (RESERVED_PLACES), so estates and
    building sites stay off them whether or not those modules have run."""
    parts = []
    for kind, rings, p in site.feats or []:
        if kind == "poly" and "building" not in p and any(p.get(k) in v for k, v in OSM_RESERVED.items()):
            g = Polygon(to_frame_m(rings[0])).buffer(0)
            if not g.is_empty and g.intersects(box(-HALF_M, -HALF_M, HALF_M, HALF_M)):
                parts.append(g.buffer(RESERVED_GROW_M))
    for x0, y0, x1, y1 in RESERVED_PLACES:
        parts.append(box(x0, y0, x1, y1))
    return unary_union(parts) if parts else None


def choose(site):
    """Every building site over the whole map (dicts: kind, poly, c, ang,
    gate, w, d, name, and for infill sites the lots they replace)."""
    claimed = site.claimed()
    reserved = reserved_area(site)
    if reserved is not None:
        claimed = reserved if claimed is None else unary_union([claimed, reserved])
    G = Ground(site)
    out, taken = [], []
    rs = road_site(site, G, claimed)
    if rs is not None:
        out.append(rs)
        taken.append(rs["c"])
    out += large_sites(site, G, claimed, taken)
    out += infill_sites(site, G, claimed, list(taken))
    return out


def build(site, made):
    """Claims every building site of the map that is still free and builds
    the ones that touch the window. The claims and the biggest site's
    landmark are made in every run, so a window run leaves the same land to
    the modules after it and names the same places as the full run. made:
    the module's stats dict ("names": every site claimed; the counts: the
    sites built)."""
    st = made.setdefault("sites", {"large": 0, "infill": 0, "frames": 0, "floors": 0, "tower_cranes": 0,
                                   "mobile_cranes": 0, "lots_removed": 0, "names": []})
    bl.KINDS["frame"] = (None, False, 0.0, style.counted("sites_all", draw_frame))
    sites = choose(site)
    biggest = max((s for s in sites if s["kind"] == "large"), key=lambda s: s["poly"].area, default=None)
    for s in sites:
        if not site.is_free(s["poly"], 1.0):
            continue
        land = [s["poly"].buffer(1.0)]
        if s["kind"] == "infill":
            infill_yard(site, s)
            land.append(s["yard"])
            if s["heap"] is not None:
                x, y, rad = s["heap"]
                land.append(Point(x, y).buffer(rad * HEAP_REACH + HEAP_SHADOW_M))
        site.claim(unary_union(land), f"fabric:site:{s['name']}")
        st["names"].append(s["name"])
        rng = block_rng(541, s["poly"])
        plan = large_plan(s, rng) if s["kind"] == "large" else None
        if s is biggest:
            site.add_landmark("the Big Crane" if plan[3]["h"] >= BIG_CRANE_M else "the Crane", "building_site",
                              s["poly"])
        if not site.in_window(s["poly"].buffer(70.0)):
            continue
        g = s["poly"].buffer(1.0)
        keep = [b for b in site.buildings if not (b.opts.get("stage") == "lots" and b.poly.intersects(g))]
        st["lots_removed"] += len(site.buildings) - len(keep)
        site.buildings = keep
        site.clear_area(s["poly"].buffer(2.0))
        site.solid_extra.append(s["poly"])
        if s.get("road") is not None:
            site.drawers.append(style.counted("sites_all", road_works(site, *s["road"], block_rng(547, s["poly"]))))
        st[s["kind"]] += 1
        if s["kind"] == "large":
            large_site(site, s, plan, rng, st)
        else:
            infill_site(site, s, rng, st)


def frame_spec(F, x0, y0, x1, y1, floors, rng):
    """A frame on the local rectangle x0..x1, y0..y1 of a site frame F."""
    w, d = x1 - x0, y1 - y0
    nx = max(2, int(round(w / rng.uniform(*BAY_M))))
    ny = max(2, int(round(d / rng.uniform(*BAY_M))))
    c = F.pt((x0 + x1) / 2, (y0 + y1) / 2)
    return {"c": (c[0], c[1], F.ang), "w": w, "d": d, "nx": nx, "ny": ny, "floors": int(floors),
            "core": (int(rng.integers(0, 2)), int(rng.integers(0, 2))), "top": float(rng.uniform(0.25, 0.75)),
            "infill": int(rng.integers(0, 3)), "seed": int(rng.integers(1 << 30))}


def frame_core(spec):
    """The core's rectangle in the frame's own frame (centred, x along w):
    one corner bay, at most 4.4 x 5.2 m."""
    w, d, nx, ny = spec["w"], spec["d"], spec["nx"], spec["ny"]
    bx, by = min(w / nx, 4.4), min(d / ny, 5.2)
    ci, cj = spec["core"]
    x0 = -w / 2 + 0.3 if ci == 0 else w / 2 - 0.3 - bx
    y0 = -d / 2 + 0.3 if cj == 0 else d / 2 - 0.3 - by
    return x0, y0, x0 + bx, y0 + by


def add_frame(site, spec, st, crane=None):
    """Adds a frame building (pinned collapsed) and its core obstacle."""
    cx, cy, ang = spec["c"]
    B = style.Batch((cx, cy), ang)
    w, d = spec["w"], spec["d"]
    poly = Polygon(B.world([(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]))
    b = bl.Building(poly, 0.2, "frame", frame=spec, crane=crane, mobile=None, stage="fabric")
    b.opts["state"] = ruins.COLLAPSED
    site.buildings.append(b)
    x0, y0, x1, y1 = frame_core(spec)
    site.obstacles.add(obstacles.PIPE, Polygon(B.world([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])))
    st["frames"] += 1
    st["floors"] += spec["floors"]
    return b


def large_plan(s, rng):
    """A large site's frame and tower crane, from the first draws of the
    site's rng (build makes them for every site, built or not, to name the
    biggest after its crane). Returns (F, left, spec, crane): the plot's
    frame, whether the frame stands at the plot's left end, the frame_spec
    and the crane (draw_crane)."""
    F = kit.Frame(s["poly"], s["ang"])
    hl, hd = s["w"] / 2, s["d"] / 2
    left = rng.random() < 0.5
    fw = s["w"] * rng.uniform(0.42, 0.56)
    fd = s["d"] * rng.uniform(0.48, 0.62)
    fx0 = -hl + 3.0 if left else hl - 3.0 - fw
    fy1 = hd - 3.0
    spec = frame_spec(F, fx0, fy1 - fd, fx0 + fw, fy1, rng.integers(*FLOORS["large"]), rng)
    # The crane stands beside the frame on the yard side; its jib points
    # over the frame, give or take.
    kx = (fx0 + fw + 7.0) if left else (fx0 - 7.0)
    kc = F.pt(kx, fy1 - fd / 2)
    fc = F.pt(fx0 + fw / 2, fy1 - fd / 2)
    H = float(rng.uniform(*CRANE_H_M))
    crane = {"x": kc[0], "y": kc[1], "h": H, "jib": float(rng.uniform(*JIB_M)),
             "counter": float(rng.uniform(*COUNTER_JIB_M)),
             "ang": float(np.arctan2(fc[1] - kc[1], fc[0] - kc[0]) + rng.uniform(-0.7, 0.7)),
             "hook": float(rng.uniform(0.35, 0.8)), "hook_h": float(rng.uniform(6.0, H * 0.6)),
             "seed": int(rng.integers(1 << 30))}
    return F, left, spec, crane


def large_site(site, s, plan, rng, st):
    """Builds a large site from its plan (large_plan), drawing on from the
    same rng."""
    F, left, spec, crane = plan
    L0, D0 = s["w"], s["d"]
    hl, hd = L0 / 2, D0 / 2
    kc = (crane["x"], crane["y"])
    C = style.Batch(kc, np.degrees(crane["ang"]))
    pad = Polygon(C.world([(-3.0, -3.0), (3.0, -3.0), (3.0, 3.0), (-3.0, 3.0)]))
    site.obstacles.add(obstacles.PIPE, pad)
    cw, ch = equipment.SIZES["control_cabinet"]
    cx, cy = CABINET_AT
    cabinet = Polygon(C.world([(cx - ch / 2 - 0.8, cy - cw / 2 - 0.8), (cx + ch / 2 + 0.8, cy - cw / 2 - 0.8),
                               (cx + ch / 2 + 0.8, cy + cw / 2 + 0.8), (cx - ch / 2 - 0.8, cy + cw / 2 + 0.8)]))
    st["tower_cranes"] += 1
    b = add_frame(site, spec, st, crane=crane)
    space = kit.Space(s["poly"].buffer(-1.5, join_style="mitre"),
                      unary_union([b.poly.buffer(2.0), pad.buffer(1.5), cabinet]))
    # The gate lane from the street into the yard stays clear.
    gx = -hl + L0 * (0.75 if left else 0.25)
    space.take(F.rect(gx - 5.0, -hd - 1.0, gx + 5.0, hd * 0.2))
    gate = Point(F.pt(gx, -hd))
    if rng.random() < MOBILE_CRANE_CHANCE:
        spot = space.place(F, 13.0, 6.0, rng, margin=2.0, region=(F.x0, F.y0 + 6.0, F.x1, F.y1))
        if spot is not None:
            x, y, _ = spot
            mc = F.pt(x + 6.5, y + 3.0)
            b.opts["mobile"] = {"x": mc[0], "y": mc[1], "ang": F.ang + (180.0 if rng.random() < 0.5 else 0.0),
                                "boom": float(rng.uniform(16.0, 26.0)), "reach": float(rng.uniform(10.0, 16.0)),
                                "turn": float(rng.uniform(-1.2, 1.2))}
            site.obstacles.add(obstacles.PIPE, F.rect(x + 1.0, y + 1.6, x + 12.0, y + 4.4))
            st["mobile_cranes"] += 1
    yard = yard_things(site, s, F, space, rng)
    seed = int(rng.integers(1 << 30))
    poly = s["poly"]

    def draw(L):
        r = np.random.default_rng(seed)
        site_ground(L, poly, F, gx, -hd, r)
        kit.fence(L, poly.exterior, r, gate=gate, v=0.3, sub="interiors", post_every=2.5)
        hoarding(L, F, -hl, hl, -hd, gx)
        draw_yard(L, site, yard, F, r)
    site.drawers.append(style.counted("sites_all", draw))


def infill_frame(s):
    """An infill frame's rectangle in its plot's frame (kit.Frame(poly, ang)):
    the whole plot less a narrow margin."""
    hl, hd = s["w"] / 2, s["d"] / 2
    return -hl + 0.8, -hd + 1.0, hl - 0.8, hd - 0.6


def infill_yard(site, s):
    """Works out an infill site's yard and heap from the whole map's layout
    and the land claimed before it, so every run gets the same. s["yard"]:
    the land of the lots it takes out, less those claims and the road
    concrete (the frame fills the plot, so the pallets stand in what the lots
    leave beside or behind it). s["heap_size"]: (radius, gravel), and
    s["heap"]: (x, y, radius) at the most open spot of the free ground within
    INFILL_HEAP_REACH_M of the plot in its street block (off the frame, the
    houses left round it, the claims and the roads), shrunk to fit, or None
    when it does not fit there (infill_site then puts it on the frame)."""
    taken = site.claimed()
    roads = site.full_roads_near(s["poly"], INFILL_HEAP_REACH_M + 2.0)
    F = kit.Frame(s["poly"], s["ang"])
    yard = s["lots"]
    room = s["poly"].buffer(INFILL_HEAP_REACH_M).intersection(s["block"])
    room = room.difference(F.rect(*infill_frame(s)).buffer(INFILL_HEAP_FRAME_M)).difference(s["houses"])
    for g in (taken, roads):
        if g is not None:
            yard = yard.difference(g)
            room = room.difference(g)
    rng = block_rng(557, s["poly"])
    s["yard"] = yard
    s["heap_size"] = (float(rng.uniform(*INFILL_HEAP_M)), bool(rng.random() < 0.3))
    s["heap"] = fit_heap(room, s["heap_size"][0])


def fit_heap(area, rad):
    """The spot in area farthest from its edges, with rad cut down so that a
    heap there stays inside area, outline and shadow: (x, y, rad), or None
    when less than INFILL_HEAP_MIN_M fits."""
    room, spot = 0.0, None
    for part in style.polys(area):
        if part.area < 4.0:
            continue
        p = polylabel(part, 0.05)
        r = float(part.boundary.distance(p))
        if r > room:
            room, spot = r, p
    rad = min(rad, (room - HEAP_SHADOW_M) / HEAP_REACH)
    if spot is None or rad < INFILL_HEAP_MIN_M:
        return None
    return float(spot.x), float(spot.y), float(rad)


def infill_site(site, s, rng, st):
    """An infill site: the frame over its plot, the heap beside it where
    infill_yard found room (else on the frame's ground floor, away from the
    core), pallets in the yard and the fence along the street."""
    F = kit.Frame(s["poly"], s["ang"])
    hl, hd = s["w"] / 2, s["d"] / 2
    spec = frame_spec(F, *infill_frame(s), rng.integers(*FLOORS["infill"]), rng)
    b = add_frame(site, spec, st)
    yard_area = s["yard"].difference(b.poly.buffer(1.2))
    heaps = []
    rad, gravel = s["heap_size"]
    foot = None
    if s["heap"] is not None:
        heaps.append((*s["heap"], gravel))
        foot = Point(s["heap"][:2]).buffer(s["heap"][2] * HEAP_REACH)
        site.clear_area(foot)
        site.solid_extra.append(foot)
    else:
        cx, cy, ang = spec["c"]
        x0, y0, x1, y1 = frame_core(spec)
        core = Polygon(style.Batch((cx, cy), ang).world([(x0, y0), (x1, y0), (x1, y1), (x0, y1)]))
        fit = fit_heap(b.poly.difference(core.buffer(INFILL_HEAP_FRAME_M)), rad)
        if fit is not None:
            b.opts["heap"] = (*fit, gravel)
    P = site.props
    for _ in range(int(rng.integers(1, 4))):
        name = str(rng.choice(["pallets", "sacks", "pallets", "drums"]))
        v, size = district_life.variant_of("clutter", name)
        for part in style.polys(yard_area):
            if part.area < 6:
                continue
            p = part.representative_point()
            px, py = p.x + rng.normal(0, 1.0), p.y + rng.normal(0, 1.0)
            if foot is not None and foot.distance(Point(px, py)) < max(size) / 2:
                continue
            if v >= 0 and part.contains(Point(px, py)) and P.clear_of(px, py, max(size) / 2 + 0.2):
                P.add("clutter", px, py, F.rad + rng.normal(0, 0.2), size, v)
                break
    front = LineString([F.pt(-hl, -hd - INFILL_GAP_M * 0.5), F.pt(hl, -hd - INFILL_GAP_M * 0.5)])
    gate = Point(F.pt(rng.uniform(-hl * 0.5, hl * 0.5), -hd - INFILL_GAP_M * 0.5))
    seed = int(rng.integers(1 << 30))

    def draw(L):
        r = np.random.default_rng(seed)
        for x, y, rad, gravel in heaps:
            heap(L, x, y, rad, r, gravel)
        kit.fence(L, front, r, gate=gate, v=0.3, sub="interiors", post_every=2.2)
    site.drawers.append(style.counted("sites_all", draw))


def yard_things(site, s, F, space, rng):
    """Places the yard's props now (portacabins and a guard hut, a genset,
    pallets, sacks, drums) and the source of the rebar stacks; returns what
    the drawer draws: rebar stacks, heaps, formwork and often a cable drum
    (a salvage source)."""
    P = site.props
    out = []
    lim = PLAY_HALF_M - 2.0
    for _ in range(int(rng.integers(1, 4))):
        spot = space.place(F, 6.6, 3.2, rng, margin=1.0, region=(F.x0 + 1, F.y0 + 1, F.x1 - 1, F.y0 + 12.0))
        if spot is None:
            break
        px, py = F.pt(spot[0] + 3.3, spot[1] + 1.6)
        ruin = ruins.state_at(px, py, 0) >= ruins.GUTTED
        v, size = district_life.variant_of("hut", "cabin", ruin)
        if v >= 0 and abs(px) < lim and abs(py) < lim:
            P.add("hut", px, py, F.rad, size, v)
    spot = space.place(F, 3.0, 3.0, rng, margin=0.5, region=(F.x0 + 1, F.y0 + 1, F.x1 - 1, F.y0 + 5.0))
    if spot is not None:
        px, py = F.pt(spot[0] + 1.5, spot[1] + 1.5)
        ruin = ruins.state_at(px, py, 0) >= ruins.GUTTED
        v, size = district_life.variant_of("hut", "guard", ruin)
        if v >= 0:
            P.add("hut", px, py, F.rad, size, v)
    stacks = []
    top = int(rng.integers(2, 5))
    ln = float(rng.uniform(6.0, 9.0))
    spot, n = None, 0
    for n in range(top, 0, -1):
        spot = space.place(F, ln + 1.2, n * 2.5, rng, margin=1.0)
        if spot is not None:
            break
    if spot is not None:
        stacks = [(spot[0] + 0.6 + rng.uniform(-0.3, 0.3), spot[1] + 0.25 + k * 2.5, ln * rng.uniform(0.85, 1.0),
                   int(rng.integers(1 << 30))) for k in range(n)]
    if stacks:
        out.append(("rebar", stacks))
        pts = np.concatenate([np.asarray(F.rect(x, y, x + ln, y + 2.0).exterior.coords) for x, y, ln, _ in stacks])
        bl.add_poly_source(site.salvage, "building_materials", Polygon(pts).convex_hull, -1, pad=0.4)
    for _ in range(int(rng.integers(2, 5))):
        rad = float(rng.uniform(1.8, 3.4))
        spot = space.place(F, 2 * rad + 1.0, 2 * rad + 1.0, rng, margin=0.5)
        if spot is None:
            continue
        c = F.pt(spot[0] + rad + 0.5, spot[1] + rad + 0.5)
        out.append(("heap", c[0], c[1], rad, bool(rng.random() < 0.35)))
    for _ in range(int(rng.integers(1, 3))):
        spot = space.place(F, 2.8, 1.6, rng, margin=0.6)
        if spot is not None:
            out.append(("formwork", spot[0], spot[1]))
    if rng.random() >= 0.3:
        w, h = equipment.SIZES["cable_drum"]
        spot = space.place(F, w + 0.8, h + 0.8, rng, margin=0.8)
        if spot is not None:
            c = F.pt(spot[0] + w / 2 + 0.4, spot[1] + h / 2 + 0.4)
            out.append(("equipment", "cable_drum", c[0], c[1], F.rad))
    # The site's generator is a genset clutter prop, which has no salvage
    # source: a diesel_generator source would give fuel.
    v, size = district_life.variant_of("clutter", "genset")
    spot = space.place(F, max(size) + 0.8, max(size) + 0.8, rng, margin=0.8)
    if spot is not None and v >= 0:
        px, py = F.pt(spot[0] + max(size) / 2 + 0.4, spot[1] + max(size) / 2 + 0.4)
        if abs(px) < lim and abs(py) < lim and P.clear_of(px, py, max(size) / 2):
            P.add("clutter", px, py, F.rad, size, v)
    for _ in range(int(rng.integers(5, 11))):
        name = str(rng.choice(["pallets", "pallets", "sacks", "sacks", "drums", "cylinders", "reel", "tarp"]))
        v, size = district_life.variant_of("clutter", name)
        spot = space.place(F, max(size) + 0.4, max(size) + 0.4, rng, margin=0.3)
        if spot is None or v < 0:
            continue
        px, py = F.pt(spot[0] + max(size) / 2 + 0.2, spot[1] + max(size) / 2 + 0.2)
        if abs(px) < lim and abs(py) < lim and P.clear_of(px, py, max(size) / 2):
            P.add("clutter", px, py, F.rad + rng.choice([0.0, np.pi / 2]) + rng.normal(0, 0.1), size, v)
    return out


def hoarding(L, F, x0, x1, y, gx):
    """Solid hoarding panels along the street side of a site (local x0 to
    x1 at y), with a soft shadow on the street side and a gap at the gate
    (gx)."""
    B = style.Batch(F.c, F.ang)
    for a, b in ((x0, gx - 4.5), (gx + 4.5, x1)):
        if b - a < 1.0:
            continue
        B.rect(a, y - 0.9, b, y - 0.1, 0.0, 0.35)
        B.line(a, y, b, y, 0.18, 0.31)
        for xx in np.arange(a + 2.4, b - 0.5, 2.4):
            B.line(xx, y - 0.09, xx, y + 0.09, 0.05, 0.18)
    count("site_yard", B.flush(L, "interiors", style.chunk_key(F.c)))


def site_ground(L, poly, F, gx, gy, rng):
    """Compacted ground over the plot, and tyre tracks from the gate."""
    L.fill("groundlines", poly, 0.21, 0.3)
    B = style.Batch(F.c, F.ang)
    for _ in range(int(rng.integers(3, 6))):
        x1 = rng.uniform(F.x0 + 4, F.x1 - 4)
        y1 = rng.uniform(gy + 8.0, F.y1 - 4)
        for off in (-0.9, 0.9):
            pts = [(gx + off, gy), (gx + off + (x1 - gx) * 0.4, gy + (y1 - gy) * 0.5), (x1 + off, y1)]
            for (xa, ya), (xb, yb) in zip(pts[:-1], pts[1:]):
                B.line(xa, ya, xb, yb, 0.35, 0.05, 0.35)
    count("site_ground", B.flush(L, "groundlines", None))


def heap(L, x, y, rad, rng, gravel=False):
    """A sand (or darker gravel) heap: a rough mound with a lit top and a
    soft shadow round it."""
    key = style.chunk_key(Point(x, y))
    shape = ruins.noisy_disc(x, y, rad, rng, n=12, rough=HEAP_ROUGH)
    v = 0.17 if gravel else 0.26
    ring = shape.exterior if shape.exterior.is_ccw else LineString(shape.exterior.coords[::-1])
    L.strip("interiors", ring, HEAP_SHADOW_M, -1, 0.45, 0.0, chunk=key)
    L.fill("interiors", shape, v, chunk=key)
    sx, sy = style.ROOF_LIGHT
    top = ruins.noisy_disc(x + sx * rad * 0.15, y + sy * rad * 0.15, rad * 0.5, rng, n=9, rough=0.2)
    L.fill("interiors", top, v * 1.25, 0.8, chunk=key)


def draw_yard(L, site, yard, F, rng):
    key = style.chunk_key(F.c)
    B = style.Batch(F.c, F.ang)
    for t in yard:
        if t[0] == "heap":
            heap(L, t[1], t[2], t[3], rng, t[4])
        elif t[0] == "equipment":
            equipment.add_source(site.salvage, L, t[1], t[2], t[3], t[4], rng)
        elif t[0] == "rebar":
            for x, y, ln, seed in t[1]:
                r = np.random.default_rng(seed)
                B.rect(x, y + 0.1, x + ln, y + 1.9, 0.0, 0.4)
                B.rect(x + 0.6, y - 0.1, x + 0.9, y + 2.1, 0.08)
                B.rect(x + ln - 0.9, y - 0.1, x + ln - 0.6, y + 2.1, 0.08)
                for k in range(int(r.integers(10, 17))):
                    yy = y + 0.2 + k * 0.105
                    if yy > y + 1.85:
                        break
                    dx = r.uniform(-0.3, 0.3)
                    B.line(x + dx, yy, x + ln + dx, yy, 0.06, REBAR_V * r.uniform(0.75, 1.0))
        elif t[0] == "formwork":
            x, y = t[1], t[2]
            for k in range(3):
                B.rect(x + k * 0.08, y + k * 0.06, x + 2.44 + k * 0.08, y + 1.22 + k * 0.06, 0.24 + 0.02 * k)
            B.line(x, y + 0.61, x + 2.5, y + 0.61, 0.05, 0.15)
    count("site_yard", B.flush(L, "interiors", key))


def runs(flags):
    """(start, end) index runs of True in a list."""
    out, start = [], None
    for i, f in enumerate(list(flags) + [False]):
        if f and start is None:
            start = i
        elif not f and start is not None:
            out.append((start, i))
            start = None
    return out


def draw_frame(L, b, rng, salvage):
    """A concrete frame under construction: the ground slab (and the heap
    an infill site puts on it, b.opts["heap"]), then floor by floor in the
    talls sublayer the columns up to the floor and the floor (poured bays,
    then beams), rebar on top, the core, then the site's cranes."""
    f = b.opts["frame"]
    cx, cy, ang = f["c"]
    w, d, nx, ny, n = f["w"], f["d"], f["nx"], f["ny"], f["floors"]
    key = style.chunk_key(b.poly)
    r = np.random.default_rng(f["seed"])
    xs = np.linspace(-w / 2 + 0.25, w / 2 - 0.25, nx + 1)
    ys = np.linspace(-d / 2 + 0.25, d / 2 - 0.25, ny + 1)
    c0, c1, c2, c3 = frame_core(f)
    core_bays = np.zeros((nx, ny), bool)
    for i in range(nx):
        for j in range(ny):
            core_bays[i, j] = xs[i] < c2 - 0.5 and xs[i + 1] > c0 + 0.5 and ys[j] < c3 - 0.5 and ys[j + 1] > c1 + 0.5
    G = style.Batch((cx, cy), ang)
    G.rect(-w / 2 - 0.5, -d / 2 - 0.5, w / 2 + 0.5, d / 2 + 0.5, 0.0, 0.4)
    G.rect(-w / 2, -d / 2, w / 2, d / 2, 0.19)
    for x0, y0, x1, y1 in ((-w / 2, -d / 2, w / 2, -d / 2), (w / 2, -d / 2, w / 2, d / 2),
                           (w / 2, d / 2, -w / 2, d / 2), (-w / 2, d / 2, -w / 2, -d / 2)):
        G.line(x0, y0, x1, y1, 0.14, 0.3)
    for x in xs:
        for y in ys:
            G.rect(x - 0.3, y - 0.3, x + 0.3, y + 0.3, 0.28)
    sides = [((xs[i], ys[0]), (xs[i + 1], ys[0])) for i in range(nx)] + \
            [((xs[i], ys[-1]), (xs[i + 1], ys[-1])) for i in range(nx)] + \
            [((xs[0], ys[j]), (xs[0], ys[j + 1])) for j in range(ny)] + \
            [((xs[-1], ys[j]), (xs[-1], ys[j + 1])) for j in range(ny)]
    for k in r.permutation(len(sides))[:f["infill"] * 2]:
        (xa, ya), (xb, yb) = sides[k]
        G.line(xa, ya, xb, yb, 0.26, 0.2)
        G.line(xa, ya, xb, yb, 0.06, 0.3)
    G.rect(c0, c1, c2, c3, 0.07)
    for _ in range(int(r.integers(3, 8))):
        px, py = r.uniform(-w / 2, w / 2), r.uniform(-d / 2, d / 2)
        s = r.uniform(0.3, 0.9)
        G.rect(px - s, py - s * 0.6, px + s, py + s * 0.6, r.uniform(0.08, 0.22))
    count("frames", G.flush(L, "interiors", key))
    if b.opts.get("heap"):
        x, y, rad, gravel = b.opts["heap"]
        heap(L, x, y, rad, np.random.default_rng([f["seed"], 1]), gravel)
    T = style.Batch((cx, cy), ang)
    top_i = max(1, int(round(nx * f["top"])))
    slab_a = min(SLAB_A, 1.0 - (1.0 - SLAB_COVER) ** (1.0 / n))
    for k in range(1, n + 1):
        h = FLOOR_M * k
        for x in xs:
            for y in ys:
                T.post(x, y, 0.45, h - FLOOR_M, h, COLUMN_V)
        poured = ~core_bays & (r.random((nx, ny)) < (0.93 if k < n else 1.0))
        if k == n:
            poured[top_i:, :] = False
        for j in range(ny):
            for i0, i1 in runs(poured[:, j]):
                T.rect(xs[i0] + 0.2, ys[j] + 0.2, xs[i1] - 0.2, ys[j + 1] - 0.2, SLAB_V, slab_a, h)
        for i in range(nx + 1):
            beam = [(i > 0 and poured[i - 1, j]) or (i < nx and poured[i, j]) for j in range(ny)]
            for j0, j1 in runs(beam):
                T.line(xs[i], ys[j0], xs[i], ys[j1], 0.4, BEAM_V, 1.0, h)
        for j in range(ny + 1):
            beam = [(j > 0 and poured[i, j - 1]) or (j < ny and poured[i, j]) for i in range(nx)]
            for i0, i1 in runs(beam):
                T.line(xs[i0], ys[j], xs[i1], ys[j], 0.4, BEAM_V, 1.0, h)
    h = FLOOR_M * n
    for i, x in enumerate(xs):
        for y in ys:
            if i <= top_i and r.random() < 0.18:
                T.post(x, y, 0.45, h, h + r.uniform(1.2, FLOOR_M), COLUMN_V)
            T.post(x + 0.12, y + 0.12, 0.07, h, h + 1.1, REBAR_V)
    T.prism([(c0, c1), (c2, c1), (c2, c3), (c0, c3)], 0.0, h + 3.0, CORE_SIDE_V, CORE_TOP_V)
    T.line(c0, (c1 + c3) / 2, c2, (c1 + c3) / 2, 0.08, 0.26, 1.0, h + 3.0)
    count("frames_talls", T.flush(L, "talls", key))
    if b.opts.get("crane"):
        draw_crane(L, b.opts["crane"], salvage)
    if b.opts.get("mobile"):
        draw_mobile_crane(L, b.opts["mobile"])


def draw_crane(L, c, salvage):
    """A tower crane: the base pad on the ground with the control cabinet
    (a salvage source) beside it, the lattice mast, the hook and its load,
    the counterweight, the slewing head and cab, the counter-jib deck, the
    jib (chords and diagonals), the tower head and its tie bars; lower
    parts first."""
    x, y, H = c["x"], c["y"], c["h"]
    r = np.random.default_rng(c["seed"])
    key = style.chunk_key(Point(x, y))
    ang = np.degrees(c["ang"])
    G = style.Batch((x, y), ang)
    G.rect(-3.3, -3.3, 3.3, 3.3, 0.0, 0.4)
    G.rect(-3.0, -3.0, 3.0, 3.0, 0.21)
    for sx in (-1, 1):
        for sy in (-1, 1):
            G.rect(sx * 1.0 - 0.25, sy * 1.0 - 0.25, sx * 1.0 + 0.25, sy * 1.0 + 0.25, 0.06)
    G.line(-3.0, -3.0, 3.0, -3.0, 0.1, 0.32)
    G.line(-3.0, 3.0, 3.0, 3.0, 0.1, 0.32)
    count("cranes", G.flush(L, "interiors", key))
    cab = G.world([CABINET_AT])[0]
    equipment.add_source(salvage, L, "control_cabinet", cab[0], cab[1], np.radians(ang + 90.0), r)
    T = style.Batch((x, y), ang)
    m = 0.9
    corners = [(-m, -m), (m, -m), (m, m), (-m, m)]
    for px, py in corners:
        T.post(px, py, 0.22, 0.0, H, MAST_V)
    for f in range(4):
        (ax, ay), (bx, by) = corners[f], corners[(f + 1) % 4]
        for k, h in enumerate(np.arange(0.0, H - 1.0, 2.0)):
            if k % 2:
                T.line(ax, ay, bx, by, 0.09, MAST_V * 0.85, 1.0, h, h + 2.0)
            else:
                T.line(bx, by, ax, ay, 0.09, MAST_V * 0.85, 1.0, h, h + 2.0)
    lj, lc = c["jib"], c["counter"]
    t = 4.0 + (lj - 6.0) * c["hook"]
    hh = c["hook_h"]
    T.post(t, -0.2, 0.05, hh, H + 0.9, 0.34)
    T.post(t, 0.2, 0.05, hh, H + 0.9, 0.34)
    T.prism([(t - 0.4, -0.35), (t + 0.4, -0.35), (t + 0.4, 0.35), (t - 0.4, 0.35)], hh - 0.9, hh, 0.3, 0.26)
    if r.random() < 0.7:
        for sx in (-1.8, 1.8):
            T.line(t, 0.0, t + sx, 0.0, 0.04, 0.3, 1.0, hh - 0.9, hh - 2.6)
        T.rect(t - 2.4, -0.5, t + 2.4, 0.5, 0.0, 0.35, hh - 2.8)
        for k in range(6):
            T.line(t - 2.3, -0.4 + k * 0.16, t + 2.3, -0.4 + k * 0.16, 0.07, REBAR_V, 1.0, hh - 2.7)
    T.prism([(-lc, -1.5), (-lc + 2.8, -1.5), (-lc + 2.8, 1.5), (-lc, 1.5)], H - 2.0, H + 1.6, CW_V, CW_V * 0.8)
    T.prism([(-1.4, -1.4), (1.4, -1.4), (1.4, 1.4), (-1.4, 1.4)], H, H + 1.3, 0.26, 0.2)
    T.prism([(0.2, 1.4), (2.2, 1.4), (2.2, 3.0), (0.2, 3.0)], H - 0.3, H + 1.7, 0.3, 0.24)
    T.rect(-lc, -1.2, -1.4, 1.2, 0.23, 0.9, H + 1.3)
    T.line(-lc, -1.2, -1.4, -1.2, 0.08, JIB_V, 1.0, H + 1.6)
    T.line(-lc, 1.2, -1.4, 1.2, 0.08, JIB_V, 1.0, H + 1.6)
    hj = H + 1.3
    T.line(1.4, -0.85, lj, -0.35, 0.14, JIB_V, 1.0, hj)
    T.line(1.4, 0.85, lj, 0.35, 0.14, JIB_V, 1.0, hj)
    T.line(1.4, 0.0, lj, 0.0, 0.12, JIB_V, 1.0, hj + 1.6, hj + 0.8)
    xx, sgn = 1.4, 1.0
    while xx < lj - 1.0:
        w0 = 0.85 - 0.5 * (xx - 1.4) / max(lj - 1.4, 1.0)
        w1 = 0.85 - 0.5 * (xx + 2.0 - 1.4) / max(lj - 1.4, 1.0)
        T.line(xx, -sgn * w0, min(xx + 2.0, lj), sgn * w1, 0.07, JIB_V * 0.85, 1.0, hj)
        xx += 2.0
        sgn = -sgn
    T.rect(t - 0.7, -0.75, t + 0.7, 0.75, 0.3, 1.0, hj - 0.2)
    T.line(-1.0, -0.9, 0.0, 0.0, 0.18, MAST_V, 1.0, H + 1.3, H + 9.0)
    T.line(-1.0, 0.9, 0.0, 0.0, 0.18, MAST_V, 1.0, H + 1.3, H + 9.0)
    T.line(0.0, 0.0, lj * 0.62, 0.0, 0.05, 0.32, 1.0, H + 9.0, hj + 1.4)
    T.line(0.0, 0.0, -lc + 1.4, 0.0, 0.05, 0.32, 1.0, H + 9.0, H + 1.8)
    count("cranes_talls", T.flush(L, "talls", key))


def draw_mobile_crane(L, m):
    """A mobile crane parked with its outriggers down and its boom up: the
    chassis on the ground, the turret and the boom in the talls sublayer."""
    x, y = m["x"], m["y"]
    key = style.chunk_key(Point(x, y))
    G = style.Batch((x, y), m["ang"])
    for sx in (-3.6, 3.0):
        for sy in (-1, 1):
            G.line(sx, 0.0, sx, sy * 2.6, 0.22, 0.3)
            G.rect(sx - 0.4, sy * 2.6 - 0.4, sx + 0.4, sy * 2.6 + 0.4, 0.24)
    G.rect(-5.6, -1.6, 5.6, 1.6, 0.0, 0.45)
    G.rect(-5.5, -1.35, 5.5, 1.35, 0.2)
    G.rect(3.6, -1.3, 5.5, 1.3, 0.27)
    G.rect(4.6, -1.2, 5.4, 1.2, 0.08)
    for k in range(4):
        G.rect(-4.8 + k * 2.2, -1.45, -3.9 + k * 2.2, -1.25, 0.03)
        G.rect(-4.8 + k * 2.2, 1.25, -3.9 + k * 2.2, 1.45, 0.03)
    count("cranes", G.flush(L, "interiors", key))
    T = style.Batch((x, y), m["ang"])
    T.prism([(-3.4, -1.2), (-0.6, -1.2), (-0.6, 1.2), (-3.4, 1.2)], 0.0, 3.2, 0.24, 0.2)
    a = m["turn"]
    ux, uy = np.cos(a), np.sin(a)
    bx, by = -2.0 + ux * m["reach"], uy * m["reach"]
    T.line(-2.0, 0.0, bx, by, 0.7, 0.3, 1.0, 3.2, m["boom"])
    T.line(-2.0 - uy * 0.2, ux * 0.2, bx - uy * 0.2, by + ux * 0.2, 0.08, 0.4, 1.0, 3.3, m["boom"] + 0.1)
    T.post(bx, by, 0.05, 2.0, m["boom"], 0.34)
    T.prism([(bx - 0.3, by - 0.3), (bx + 0.3, by - 0.3), (bx + 0.3, by + 0.3), (bx - 0.3, by + 0.3)], 1.4, 2.0,
            0.3, 0.26)
    count("cranes_talls", T.flush(L, "talls", key))
