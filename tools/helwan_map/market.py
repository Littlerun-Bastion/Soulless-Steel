"""Market district content (section 4 of the districts brief).

In each street block of the market district:
  - shop terraces: the houses along the block's streets stay, as narrow
    shops, each with a street awning (striped or plain canvas) over the
    pavement in front of it;
  - the block's inside (deeper than TERRACE_DEPTH_M from its edge) is
    cleared and becomes the market: lanes cut through the terrace from the
    streets into a plaza, with stalls on both sides of each lane;
  - the plaza: a ring of stalls round its inside edge, RING_INSET_M in from
    the edge, facing in, at about RING_SPACING_M; no stall within
    MOUTH_CLEAR_M of a lane mouth; inside the ring, two double rows of
    stalls back to back, with a walkway through the middle;
  - a market hall (barrel roof with arcade columns) in the larger blocks;
  - cart parks: hand carts parked in a corner;
  - a diesel generator or two (salvage sources) by the stalls.

Stalls are props (kind "stall"; variants 0 lean-to, 1 canopy, 2 table with
crates, 3 hand cart), not buildings: no wall, no AP cost. A stall's sprite
has its counter along x and its front towards +y, so a stall facing the unit
direction (dx, dy) is turned by atan2(-dx, dy).
"""
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

import buildings as bl
import equipment
import kit
import props
import style
from districts import MARKET
from gen_city import block_rng

MIN_SHARE = 0.5
MIN_BLOCK_M2 = 1500.0
TERRACE_DEPTH_M = 13.0
LANE_W_M = (5.0, 6.5)
RING_INSET_M = 2.2
RING_SPACING_M = 3.1
MOUTH_CLEAR_M = 6.0
ROW_SPACING_M = 3.2
WALKWAY_M = 5.0
HALL_MIN_INNER_M2 = 1800.0
## A block larger than this (m2: open commercial land, not a street block of
## shops) gets one market square of SQUARE_M (ranges, m) in its middle
## instead of a cleared middle with lanes.
BIG_BLOCK_M2 = 20000.0
SQUARE_M = ((45.0, 70.0), (30.0, 50.0))
## Stall variant weights in lanes and plazas: lean-to, canopy, table with
## crates, hand cart.
STALL_WEIGHTS = (0.3, 0.35, 0.27, 0.08)
AWNING_DEPTH_M = (1.6, 2.2)
## How far (m) an awning may reach past the edge of the road concrete in
## front of its shop (over the kerb), and the shallowest awning drawn.
AWNING_KERB_M = 0.3
AWNING_MIN_M = 0.9
PAVING_V = 0.24


def stall_rot(dx, dy):
    return float(np.arctan2(-dx, dy))


def stall(site, x, y, facing, rng, variant=None):
    cat = props.CATALOGUE.get("stall", [])
    if not cat:
        return False
    v = variant if variant is not None else int(rng.choice(len(cat), p=np.asarray(STALL_WEIGHTS[:len(cat)]) /
                                                            sum(STALL_WEIGHTS[:len(cat)])))
    e = cat[v]
    rot = stall_rot(*facing) + rng.normal(0, 0.04)
    return site.props.add("stall", x, y, rot, (e["length_m"], e["width_m"]), v)


def roof_hall(L, b, rng):
    """A barrel roof: corrugated stripes along the long axis, lit on one side
    and shaded on the other, a ridge, and arcade columns along both long
    sides."""
    g = b.poly
    R = style.Roof(L, g, style.roof_value(b.mv) * 1.2, rng)
    R.fill(g, R.v)
    h = R.y1 - R.y0
    bands = 10
    for i in range(bands):
        ya = R.y0 + h * i / bands
        t = (i + 0.5) / bands
        shade = 0.75 + 0.6 * (1 - abs(t - 0.35) * 1.8)
        R.fill(R.rect(R.x0, ya, R.x1, ya + h / bands).intersection(g), min(R.v * shade, 0.2))
    for y in np.arange(R.y0 + 0.5, R.y1, 0.6):
        R.stroke(R.line([(R.x0, y), (R.x1, y)]).intersection(g), 0.04, 0.04)
    R.stroke(R.line([(R.x0, R.y0 + h * 0.5), (R.x1, R.y0 + h * 0.5)]).intersection(g), 0.18, style.DETAIL_LINE_V)
    for x in np.arange(R.x0 + 2.0, R.x1 - 1.0, 4.0):
        for y in (R.y0 + 0.5, R.y1 - 1.1):
            R.fill(R.rect(x - 0.3, y, x + 0.3, y + 0.6), 0.3)
    R.ring(g, style.OUTLINE_W * 1.2, style.OUTLINE_V)
    return None


bl.KINDS["hall"] = (roof_hall, True, style.HALO_BIG_M)


def built(site):
    """The buildings as build_layers draws them (site.buildings once every
    module and resolve_overlaps have run): (STR tree of their footprints,
    the buildings, their ids). Made once per buildings list, for drawers
    that keep their detail off the final buildings."""
    got = getattr(site, "_built", None)
    if got is None or got[1] is not site.buildings:
        bs = site.buildings
        got = (STRtree([b.poly for b in bs]), bs, {id(b) for b in bs})
        site._built = got
    return got


def others_near(site, geom, own=None, grow=0.0):
    """The final footprints (built) that come within grow of geom, other
    than own's, as one geometry grown by grow, or None."""
    tree, bs, _ = built(site)
    near = [bs[i].poly for i in tree.query(geom.buffer(grow + 0.05)) if bs[i] is not own]
    if not near:
        return None
    return unary_union([p.buffer(grow, join_style="mitre") if grow else p for p in near])


def awning(L, g, edge_line, depth, rng, striped, roads=None, others=None):
    """A canvas awning along a shop's street side, over the ground in front
    of it: no deeper than the gap from the shop to the road's concrete plus
    AWNING_KERB_M, and clear of the other buildings (others)."""
    seg = edge_line
    if seg.length < 2.0:
        return
    if roads is not None:
        depth = min(depth, seg.distance(roads) + AWNING_KERB_M)
    if depth < AWNING_MIN_M:
        return
    side = 1.0
    out = seg.buffer(depth, single_sided=True)
    if out.intersects(g.buffer(-0.05)):
        side = -1.0
        out = seg.buffer(-depth, single_sided=True)
    out = out.difference(g)
    # The shadow spreads 0.35 m past the awning's ends, not further out
    # than the awning itself.
    (ax, ay), (bx, by) = seg.coords[0], seg.coords[-1]
    t = np.array([bx - ax, by - ay]) / seg.length * 0.35
    ext = LineString([(ax - t[0], ay - t[1]), (bx + t[0], by + t[1])])
    shadow = out.buffer(0.35, join_style="mitre").intersection(ext.buffer(side * depth, single_sided=True))
    shadow = shadow.difference(g)
    if others is not None:
        out = out.difference(others)
        shadow = shadow.difference(others)
    parts = [p for p in style.polys(out) if p.area >= 0.8 and not p.buffer(-0.25).is_empty]
    if not parts:
        return
    out = unary_union(parts)
    L.fill("interiors", shadow, 0.0, 0.35)
    L.fill("interiors", out, 0.3 if striped else rng.uniform(0.18, 0.32))
    if striped:
        n = int(seg.length // 0.6)
        for i in range(0, n, 2):
            a = seg.interpolate(i * 0.6)
            b2 = seg.interpolate(min((i + 1) * 0.6, seg.length))
            stripe = LineString([a, b2]).buffer(depth + 0.1, single_sided=True, cap_style="flat")
            stripe2 = LineString([a, b2]).buffer(-depth - 0.1, single_sided=True, cap_style="flat")
            L.fill("interiors", unary_union([stripe, stripe2]).intersection(out), 0.1)
    for p in parts:
        L.line("interiors", p.exterior, 0.06, 0.42)


def street_edges(poly, street, min_len=2.5):
    """The straight sides of a polygon that face the street (their middle is
    within 3 m of it)."""
    pts = list(poly.exterior.coords)
    out = []
    for a, b in zip(pts[:-1], pts[1:]):
        seg = LineString([a, b])
        if seg.length >= min_len and street.distance(seg.interpolate(0.5, normalized=True)) < 3.0:
            out.append(seg)
    return out


def lane_stalls(site, lane_axis, width, rng, clear):
    """Stalls along both sides of a lane, facing into it."""
    n = int(lane_axis.length // ROW_SPACING_M)
    for i in range(1, n):
        d = i * ROW_SPACING_M + rng.uniform(-0.3, 0.3)
        p = lane_axis.interpolate(d)
        q = lane_axis.interpolate(min(d + 0.5, lane_axis.length))
        t = np.array([q.x - p.x, q.y - p.y])
        t /= max(np.hypot(*t), 1e-9)
        nrm = np.array([-t[1], t[0]])
        for side in (-1, 1):
            if rng.random() < 0.18:
                continue
            off = side * (width / 2 - 1.1)
            x, y = p.x + nrm[0] * off, p.y + nrm[1] * off
            if clear is not None and not clear.contains(Point(x, y)):
                continue
            stall(site, x, y, (-nrm[0] * side, -nrm[1] * side), rng)


def plaza_stalls(site, F, plaza, mouths, rng):
    """The ring round the plaza's inside edge and two double rows inside."""
    ring_line = plaza.buffer(-RING_INSET_M, join_style="mitre")
    ring_poly = kit.largest(ring_line)
    if ring_poly is None:
        return
    ring = LineString(ring_poly.exterior.coords)
    n = int(ring.length // RING_SPACING_M)
    for i in range(n):
        d = i * RING_SPACING_M
        p = ring.interpolate(d)
        if any(m.distance(p) < MOUTH_CLEAR_M for m in mouths):
            continue
        q = ring.interpolate(min(d + 0.5, ring.length))
        t = np.array([q.x - p.x, q.y - p.y])
        t /= max(np.hypot(*t), 1e-9)
        inward = np.array([-t[1], t[0]])
        if not ring_poly.contains(Point(p.x + inward[0] * 1.5, p.y + inward[1] * 1.5)):
            inward = -inward
        stall(site, p.x, p.y, inward, rng)
    inner = plaza.buffer(-(RING_INSET_M + 2.5 + WALKWAY_M), join_style="mitre")
    inner = kit.largest(inner)
    if inner is None:
        return
    fi = kit.Frame(inner, F.ang)
    depth = 2.4
    for sign in (-1, 1):
        yc = sign * (WALKWAY_M / 2 + depth)
        if abs(yc) + depth > fi.h / 2:
            continue
        xa, xb = fi.x0 + 1.5, fi.x1 - 1.5
        gap = (xa + xb) / 2
        for x in np.arange(xa, xb, ROW_SPACING_M):
            if abs(x - gap) < 2.5:
                continue
            for back in (-1, 1):
                y = yc + back * depth / 2
                px, py = fi.pt(x, y)
                if not inner.buffer(0.5).contains(Point(px, py)):
                    continue
                face = np.array([-fi.sin, fi.cos]) * back
                stall(site, px, py, face, rng)


def cart_park(site, F, area, rng):
    cat = props.CATALOGUE.get("stall", [])
    if len(cat) < 4:
        return
    e = cat[3]
    c = area.representative_point()
    n = int(rng.integers(3, 7))
    for i in range(n):
        lx, ly = F.to_local(c.x, c.y)
        px, py = F.pt(lx + (i - n / 2) * (e["width_m"] + 0.5), ly)
        if area.contains(Point(px, py)):
            site.props.add("stall", px, py, F.rad + np.pi / 2 + rng.normal(0, 0.08),
                           (e["length_m"], e["width_m"]), 3)


def build(site):
    """Lanes, plazas, halls, stalls and shop awnings in the market blocks."""
    n_blocks = n_plazas = n_halls = 0
    for blk in site.blocks_of(MARKET, MIN_SHARE, MIN_BLOCK_M2):
        rng = block_rng(43, blk)
        F = kit.Frame(blk)
        street = blk.exterior
        inner = kit.largest(blk.buffer(-TERRACE_DEPTH_M, join_style="mitre"))
        big = blk.area > BIG_BLOCK_M2
        if big and inner is not None:
            pw, ph = rng.uniform(*SQUARE_M[0]), rng.uniform(*SQUARE_M[1])
            fx = kit.Frame(inner, F.ang)
            if fx.w > pw + 10 and fx.h > ph + 10:
                cx = rng.uniform(fx.x0 + pw / 2 + 5, fx.x1 - pw / 2 - 5)
                cy = rng.uniform(fx.y0 + ph / 2 + 5, fx.y1 - ph / 2 - 5)
                inner = kit.largest(fx.rect(cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2).intersection(inner))
            else:
                inner = None
        mouths, lanes, paving = [], [], []
        plaza = None
        if inner is not None and inner.area >= 350:
            site.remove_buildings_in(inner)
            site.remove_buildings_touching(inner, margin=0.0)
            fi = kit.Frame(inner, F.ang)
            if inner.area >= HALL_MIN_INNER_M2 and fi.w > 45:
                hw = min(fi.w * 0.4, rng.uniform(30, 48))
                hh = min(fi.h - 6, rng.uniform(14, 22))
                at_left = rng.random() < 0.5
                hx0 = fi.x0 + 2 if at_left else fi.x1 - 2 - hw
                hall = fi.rect(hx0, -hh / 2, hx0 + hw, hh / 2)
                if inner.contains(hall):
                    site.buildings.append(bl.Building(hall, float(site.sampler.value(hall.centroid.x,
                                                                                     hall.centroid.y)), "hall"))
                    inner = kit.largest(inner.difference(hall.buffer(4.0)))
                    n_halls += 1
            plaza = inner
            n_plazas += plaza is not None
            n_lanes = int(np.clip(blk.exterior.length / 140, 1, 4)) if not big else 0
            for k in range(n_lanes):
                x = F.x0 + F.w * (k + 1) / (n_lanes + 1) + rng.uniform(-0.08, 0.08) * F.w
                side = 1 if (k + rng.integers(2)) % 2 else -1
                w = rng.uniform(*LANE_W_M)
                lane = F.rect(x - w / 2, 0 if side > 0 else F.y0 - 2, x + w / 2, F.y1 + 2 if side > 0 else 0)
                lane = lane.intersection(blk).difference(plaza.buffer(-0.5) if plaza is not None else Polygon())
                lane = kit.largest(lane)
                if lane is None or lane.area < 30:
                    continue
                site.remove_buildings_touching(lane, margin=0.3)
                lanes.append(lane)
                axis = F.line([(x, 0), (x, F.y1 if side > 0 else F.y0)]).intersection(lane)
                if axis.geom_type == "LineString" and axis.length > 6:
                    lane_stalls(site, axis, w, rng, lane.buffer(-0.4))
            if plaza is not None:
                # The open ground left inside the block (the cleared middle,
                # up to the backs of the terraces) is paved; without the
                # lanes it is the plaza.
                kept = [b.poly.buffer(1.0) for b in site.buildings if blk.contains(b.poly.centroid)]
                void = kit.largest(blk.buffer(-1.0).difference(unary_union(kept))) if kept else blk.buffer(-1.0)
                if void is not None and void.area > plaza.area and not big:
                    rest = kit.largest(void.difference(unary_union(lanes).buffer(0.3))) if lanes else void
                    plaza = rest if rest is not None else plaza
                    paving.append(void)
                for lane in lanes:
                    m = lane.intersection(plaza.buffer(1.0))
                    if not m.is_empty:
                        mouths.append(m.centroid)
            if plaza is not None:
                paving.append(plaza)
                plaza_stalls(site, F, plaza, mouths, rng)
                corner = plaza.exterior.interpolate(rng.uniform(0, 1), normalized=True).buffer(7.0).intersection(
                    plaza.buffer(-1.5))
                if not corner.is_empty:
                    cart_park(site, F, corner, rng)
                for _ in range(int(rng.integers(1, 3))):
                    p = plaza.exterior.interpolate(rng.uniform(0, 1), normalized=True)
                    lx, ly = F.to_local(p.x, p.y)
                    c = plaza.centroid
                    q = (p.x + (c.x - p.x) * 0.1, p.y + (c.y - p.y) * 0.1)
                    if plaza.contains(Point(q)):
                        site.drawers.append(lambda L, q=q, a=F.rad, s=int(rng.integers(1 << 30)):
                                            equipment.add_source(site.salvage, L, "diesel_generator", q[0], q[1], a,
                                                                 np.random.default_rng(s)))
        shops = [b for b in site.buildings if b.kind == "house" and blk.contains(b.poly.centroid)]
        awn = []
        for b in shops:
            for seg in street_edges(b.poly, street):
                if rng.random() < 0.7:
                    awn.append((b, seg, rng.uniform(*AWNING_DEPTH_M), rng.random() < 0.5))
        paving += lanes
        seed = int(rng.integers(1 << 30))
        roads = site.road_union_near(blk, 3.0) if awn else None

        def draw(L, paving=paving, awn=awn, seed=seed, roads=roads):
            r = np.random.default_rng(seed)
            for g in paving:
                under = others_near(site, g)
                if under is not None:
                    g = g.difference(under)
                kit.pave(L, g, PAVING_V, 0.85, sub="groundlines")
                for pg in style.polys(g):
                    x0, y0, x1, y1 = pg.bounds
                    for x in np.arange(x0, x1, 2.5):
                        L.line("groundlines", LineString([(x, y0), (x, y1)]).intersection(pg), 0.04, 0.17, 0.6)
            # A shop that a later module took or turned into something else
            # loses its awning; the rest keep off the buildings as drawn.
            live = built(site)[2]
            for b, seg, depth, striped in awn:
                if id(b) not in live or b.kind != "house":
                    continue
                others = others_near(site, seg.buffer(depth + 0.5), own=b)
                awning(L, b.poly, seg, depth, r, striped, roads, others)
        site.drawers.append(draw)
        site.solid_extra += paving
        n_blocks += 1
    site.stats["market"] = {"blocks": n_blocks, "plazas": n_plazas, "halls": n_halls}
    return site
