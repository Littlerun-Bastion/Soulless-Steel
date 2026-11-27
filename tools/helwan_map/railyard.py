"""The rail yard among the OSM sidings north of the town, and container
stacks in the industrial yards.

The yard (YARD_BOX) is built round the OSM rail lines there:

  depot shed      a long-span shed over the dead ends of a fan of sidings
                  (a building of kind "rail_shed" that draws itself: the
                  tracks run on inside it, with inspection pits; skylights
                  over each track; doors open at the end the tracks enter;
                  a car stands inside under repair)
  works hall      a sawtooth hall along the OSM traverser (a transfer table
                  in its pit) with track stubs into its doors
  goods trains    rakes of boxcars, hoppers and flat wagons (some carrying
                  containers) standing on the sidings, with gaps
  crossings       bands across the tracks every CROSSING_EVERY_M where no
                  goods train stands, so mechas can cross the yard (plates
                  drawn over the tracks there)
  buffer stops and signals at the dead ends and along the lines
  container terminal
                  the largest free rectangle of the yard: rows of containers
                  in pairs, stacked 1 to 3 high (stacks of 2 and 3 are drawn
                  in the talls sublayer, each run of them over one ground
                  obstacle and a gutted building, so it gives cover; single
                  ones are container vehicles), 15 m lanes and cross lanes
                  for mechas, a gantry crane over one row pair, floodlight
                  masts

industrial_stacks() turns blocks of containers along the outside of the
industrial module's container yards into stacks of 2 or 3 in place, and
lot_yards() adds rows of containers in free corners of the industrial
lots.
"""
import numpy as np
from shapely import affinity, prepare
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

import buildings as bl
import kit
import props
import railkit as rk
import ruins
import style
from frame import PLAY_HALF_M
from gen_city import block_rng, to_frame_m

YARD_BOX = (540.0, -2500.0, 990.0, -1650.0)
TRACK_OFF_M = style.TRACK_SPACING_M / 2
SHED_LEN_M = (80.0, 64.0, 48.0)
HALL_DEPTH_M = (90.0, 70.0, 50.0)
## Share of the free siding stretches that hold a goods train, and the
## share of a stretch a train fills.
RAKE_SHARE = 0.75
RAKE_FILL = (0.45, 0.85)
## Chance that a goods wagon (boxcar, hopper, container flat) is a salvage
## source.
WAGON_SOURCE_SHARE = 0.35
## Mechas cross the tracks on crossings: bands CROSSING_M wide across the
## yard's main direction every CROSSING_EVERY_M, where no goods train
## stands (a crossing of plates is drawn on each track there).
CROSSING_M = 18.0
CROSSING_EVERY_M = 110.0
## Container terminal: lane between row pairs, cross lane every
## CROSS_EVERY_M, perimeter lane, size limits of the rectangle.
LANE_M = 15.0
CROSS_LANE_M = 14.0
CROSS_EVERY_M = 62.0
EDGE_LANE_M = 8.0
TERMINAL_MIN_M = (50.0, 36.0)
TERMINAL_MAX_M = (170.0, 110.0)
## Up to TERMINALS container terminals; a second one needs this much room.
TERMINALS = 2
SECOND_TERMINAL_M2 = 6000.0
## The traction substation's yard (power.py builds it), long and short
## side.
SUBSTATION_M = (58.0, 40.0)
## Chance of each stack height in the terminal (1, 2, 3 high).
STACK_HEIGHTS = (0.25, 0.4, 0.35)
STACK_SOURCE_SHARE = 0.12
## In the industrial container yards: the chance that a block of
## containers along the outside of a yard is stacked, and the chance a stack
## is 3 high (else 2).
YARD_STACK_SHARE = 0.6
YARD_THREE_HIGH = 0.35
## Containers closer than this belong to one yard.
YARD_LINK_M = 8.0
## Container rows added in the industrial lots (lot_yards): the chance per
## lot (the industrial module fills its lots, so few have room), the
## rectangle's least and largest size (along the lot, across it), its
## clearance from the lot's content, from the lot's fence and from markers.
LOT_YARD_SHARE = 1.0
LOT_YARD_MIN_M = (18.0, 9.0)
LOT_YARD_MAX_M = (62.0, 34.0)
LOT_CLEAR_M = 5.0
LOT_EDGE_M = 3.0
LOT_MARKER_M = 22.0
## A buffer stop stands STOP_BACK_M[0] in from its track's end, or further
## back (up to STOP_BACK_M[1], in 1 m steps) where that is on road concrete,
## a building or an obstacle; else it is left out. A signal stands clear of
## those too and SIGNAL_TRACK_M or more from the centre line of every yard
## track; where its place is not clear it tries the other side of its line,
## then the places SIGNAL_SHIFTS_M along the line.
STOP_BACK_M = (1.5, 20.0)
SIGNAL_SHIFTS_M = (0.0, 10.0, -10.0, 20.0, -20.0, 30.0, -30.0, 40.0, -40.0)
SIGNAL_TRACK_M = 2.9


def yard_rails(site):
    area = box(*YARD_BOX)
    out = []
    for g, v, w, f, kind, line in (site.full_layout or {}).get("roads", site.roads):
        if kind == "rail:rail" and line is not None and line.intersects(area):
            out.append(line)
    out.sort(key=lambda l: (round(l.coords[0][0], 1), round(l.coords[0][1], 1)))
    return out


def tracks_of(line):
    """The two drawn tracks of an OSM rail line (style.draw_rails draws two
    tracks TRACK_OFF_M either side of it)."""
    out = []
    for o in (-TRACK_OFF_M, TRACK_OFF_M):
        t = line.offset_curve(o)
        out += [p for p in getattr(t, "geoms", [t]) if p.geom_type == "LineString" and p.length > 5]
    return out


def dead_ends(rails, area):
    ends = []
    for i, line in enumerate(rails):
        for at_start in (True, False):
            p = Point(line.coords[0] if at_start else line.coords[-1])
            if not area.contains(p):
                continue
            if any(j != i and rails[j].distance(p) < 3.0 for j in range(len(rails))):
                continue
            back = min(25.0, line.length)
            q = line.interpolate(back if at_start else line.length - back)
            d = np.array([p.x - q.x, p.y - q.y])
            d /= max(np.hypot(*d), 1e-9)
            ends.append((p.x, p.y, d, i))
    return ends


def groups(ends, dist=45.0):
    out = []
    for e in ends:
        hit = [g for g in out if any(np.hypot(e[0] - f[0], e[1] - f[1]) < dist for f in g)]
        merged = [e]
        for g in hit:
            merged += g
            out.remove(g)
        out.append(merged)
    return out


def land_ok(site, poly, setback=1.5):
    """Free for the yard: no claim, nothing the district modules built, no
    industrial district cell, no road concrete and no large roof or
    non-house building. A window run knows the district modules' content
    only inside the window, and builds an industrial block that crosses the
    window's edge from the part it sees, so a window preview matches the
    full run only when it takes in YARD_BOX and the industrial blocks east
    of it (--window 400,-2700,1500,-1400 does)."""
    if not site.is_free(poly) or site.districts.share(poly, 1) > 0.0:
        return False
    roads = rk.full_roads_near(site, poly, setback + 1.0)
    if roads is not None and roads.buffer(setback).intersects(poly):
        return False
    if rk.full_big_near(site, poly.buffer(2.0)):
        return False
    return not any(b.opts.get("stage") not in ("lots", "osm roofs") and b.poly.intersects(poly) for b in site.buildings)


# ------------------------------------------------------------ depot shed

def roof_shed(L, b, rng):
    """A long-span shed roof: a skylight band along each track inside, a
    ridge vent between, and a heavy outline."""
    g = b.poly
    R = style.Roof(L, g, style.roof_value(b.mv) * rng.uniform(0.95, 1.1), rng)
    R.fill(g, R.v)
    for t in b.opts.get("tracks", []):
        band = t.buffer(1.3, cap_style="flat").intersection(g.buffer(-1.5))
        if band.is_empty:
            continue
        R.fill(band, 0.07)
        for p in style.polys(band):
            R.stroke(LineString(p.exterior.coords), 0.08, style.DETAIL_LINE_V * 0.8)
        pts, tang = rk.sample(t, 2.6)
        for p, d in zip(pts, tang):
            n = np.array([-d[1], d[0]]) * 1.3
            seg = LineString([p - n, p + n]).intersection(band)
            R.stroke(seg, 0.05, 0.15)
    R.shade_in(g.buffer(-1.2, join_style="mitre"), 1.6, 0.4)
    R.ring(g, style.OUTLINE_W * 1.4, style.OUTLINE_V)
    return R


def shed_interior(L, b, rng):
    g = b.poly
    key = style.chunk_key(g)
    sub = "interiors"
    room = g.buffer(-0.6, join_style="mitre")
    L.fill(sub, g, 0.03, chunk=key)
    L.fill(sub, room, 0.15, chunk=key)
    for k, t in enumerate(b.opts.get("tracks", [])):
        inside = t.intersection(room)
        for seg in getattr(inside, "geoms", [inside]):
            if seg.geom_type != "LineString" or seg.length < 3:
                continue
            if k % 3 != 2:
                L.fill(sub, seg.buffer(0.55, cap_style="flat"), 0.02, chunk=key)
            pts, tang = rk.sample(seg, 2.0)
            for r in (-rk.GAUGE_HALF_M, rk.GAUGE_HALF_M):
                L.line(sub, LineString(rk.offset_path(pts, tang, r)), 0.1, 0.34, chunk=key)
    F = kit.Frame(g, ang=b.opts.get("ang"))
    for u in np.arange(F.x0 + 8.0, F.x1 - 4.0, 8.0):
        for w in (F.y0 + 1.2, F.y1 - 1.2):
            L.fill(sub, Point(*F.pt(u, w)).buffer(0.45, quad_segs=1), 0.03, chunk=key)
    for p in style.polys(room):
        L.strip(sub, orient_ring(p), 3.0, +1, 0.6, 0.0, chunk=key)
    doors = b.opts.get("doors", [])
    wall = LineString(g.exterior.coords)
    gaps = unary_union([Point(d).buffer(2.2, cap_style="square") for d in doors]) if doors else Polygon()
    L.line(sub, wall.difference(gaps), 0.6, 0.03, chunk=key)
    for d in doors:
        L.fill(sub, Point(d).buffer(2.2, cap_style="square").intersection(g.buffer(0.8)).difference(room), 0.2, 0.7,
               chunk=key)


def orient_ring(p):
    from shapely.geometry.polygon import orient
    return orient(p, 1.0).exterior


def draw_shed(L, b, rng, salvage):
    if b.state == ruins.COLLAPSED:
        ruins.draw_collapsed(L, b, rng, salvage)
        return
    style.draw_halo(L, b.poly, style.HALO_BIG_M)
    shed_interior(L, b, rng)
    if b.state == ruins.INTACT:
        roof_shed(L, b, rng)
    else:
        ruins.draw_ruined_roof(L, b, rng, roof_shed, True)


bl.KINDS["rail_shed"] = (roof_shed, True, style.HALO_BIG_M, draw_shed)


def depot_shed(site, rails, group, rng):
    """A shed over a group of dead ends. Returns (polygon, frame, tracks
    inside) or None."""
    d = np.mean([e[2] for e in group], axis=0)
    d /= max(np.hypot(*d), 1e-9)
    ang = float(np.degrees(np.arctan2(d[1], d[0])))
    cx, cy = np.mean([[e[0], e[1]] for e in group], axis=0)
    F = kit.Frame(Point(cx, cy).buffer(1.0), ang=ang)
    loc = [F.to_local(e[0], e[1]) for e in group]
    u1 = max(u for u, _ in loc) + 6.0
    w0 = min(w for _, w in loc) - TRACK_OFF_M - 5.0
    w1 = max(w for _, w in loc) + TRACK_OFF_M + 5.0
    for length in SHED_LEN_M:
        rect = F.rect(u1 - length, w0, u1, w1)
        if land_ok(site, rect):
            break
    else:
        return None
    lines = [rails[e[3]] for e in group]
    tracks = []
    for line in lines:
        for t in tracks_of(line):
            inside = t.intersection(rect)
            tracks += [p for p in getattr(inside, "geoms", [inside]) if p.geom_type == "LineString" and p.length > 5]
    return rect, F, tracks, u1 - length


# --------------------------------------------------- works hall, traverser

def traverser(site):
    for kind, rings, p in site.feats or []:
        if kind == "line" and p.get("railway") == "traverser":
            pts = to_frame_m(rings[0])
            g = Polygon(pts).buffer(0)
            if g.area > 500 and g.intersects(box(*YARD_BOX)):
                return g
    return None


def works_hall(site, trav):
    """The largest hall along one long side of the traverser, on free land
    (houses may go), off the rails: (polygon, traverser frame, side) or
    (None, frame, 0)."""
    F = kit.Frame(trav)
    rails = unary_union([l.buffer(3.0) for l in yard_rails(site)])
    spans = ((0.0, 1.0), (0.0, 0.66), (0.34, 1.0), (0.0, 0.5), (0.5, 1.0), (0.25, 0.75))
    best = None

    def rect(xa, xb, side, d):
        if side > 0:
            return F.rect(xa, F.y1 + 1.0, xb, F.y1 + 1.0 + d)
        return F.rect(xa, F.y0 - 1.0 - d, xb, F.y0 - 1.0)

    for side in (-1, 1):
        for a, b in spans:
            xa = F.x0 + 2.0 + (F.w - 4.0) * a
            xb = F.x0 + 2.0 + (F.w - 4.0) * b
            depth = 0
            for d in range(25, 95, 5):
                r = rect(xa, xb, side, d)
                if not land_ok(site, r) or rails.intersects(r):
                    break
                depth = d
            if depth >= 25:
                r = rect(xa, xb, side, depth)
                if best is None or r.area > best[0].area:
                    best = (r, side)
    if best is None:
        return None, F, 0
    return best[0], F, best[1]


# ------------------------------------------------------------ goods trains

RAKES = {
    "container": (("flatcar_container", 0.8), ("flatcar", 0.2)),
    "hopper": (("hopper", 1.0),),
    "box": (("boxcar", 0.75), ("hopper", 0.25)),
    "mixed": (("boxcar", 0.35), ("hopper", 0.25), ("flatcar_container", 0.25), ("flatcar", 0.15)),
}


def free_stretches(site, rails, keep_out):
    """Parts of the drawn tracks in the yard, inside the play area, off the
    roads and keep_out, at least 50 m long."""
    area = box(*YARD_BOX).intersection(box(-PLAY_HALF_M + 20, -PLAY_HALF_M + 20, PLAY_HALF_M - 20, PLAY_HALF_M - 20))
    roads = rk.full_roads_near(site, area, 0.0)
    cut = unary_union([keep_out] + ([roads.buffer(6.0)] if roads is not None else []))
    out = []
    for line in rails:
        for t in tracks_of(line):
            g = t.intersection(area).difference(cut)
            out += [p for p in getattr(g, "geoms", [g]) if p.geom_type == "LineString" and p.length >= 50]
    return out


def crossing_lines(rails):
    """The centre lines of the crossings: lines across the yard's main
    direction (the mean direction of its long rail lines) every
    CROSSING_EVERY_M through the middle of YARD_BOX, clipped to it."""
    long_ = [l for l in rails if l.length > 100]
    if not long_:
        return []
    ref = np.array(long_[0].coords[-1]) - np.array(long_[0].coords[0])
    d = np.zeros(2)
    for l in long_:
        v = np.array(l.coords[-1]) - np.array(l.coords[0])
        d += v if v @ ref >= 0 else -v
    d /= max(np.hypot(*d), 1e-9)
    n = np.array([-d[1], d[0]])
    x0, y0, x1, y1 = YARD_BOX
    c = np.array([(x0 + x1) / 2, (y0 + y1) / 2])
    reach = float(np.hypot(x1 - x0, y1 - y0))
    k_max = int(reach / 2 // CROSSING_EVERY_M) + 1
    out = []
    for k in range(-k_max, k_max + 1):
        p = c + d * (k + 0.5) * CROSSING_EVERY_M
        line = LineString([p - n * reach, p + n * reach]).intersection(box(*YARD_BOX))
        if not line.is_empty and line.geom_type == "LineString":
            out.append(line)
    return out


def draw_crossings(L, rails, lines, skip, roads=None):
    """A crossing of concrete plates on every track where a crossing line
    meets it (outside `skip`), with the rails over the plates. Where a track
    runs onto road concrete (`roads`) the road is the crossing: the plate
    stops at the road's edge."""
    for line in lines:
        for rl in rails:
            for t in tracks_of(rl):
                x = t.intersection(line)
                for p in getattr(x, "geoms", [x]):
                    if p.geom_type != "Point" or skip.contains(p) or max(abs(p.x), abs(p.y)) > PLAY_HALF_M - 10:
                        continue
                    d = t.project(p)
                    q0, q1 = t.interpolate(max(d - 1.0, 0.0)), t.interpolate(min(d + 1.0, t.length))
                    ang = float(np.arctan2(q1.y - q0.y, q1.x - q0.x))
                    plate = rk.rect_at(p.x, p.y, ang, 3.2, 2 * rk.BED_HALF_M + 0.4)
                    if roads is not None and roads.intersects(plate):
                        plate = plate.difference(roads.buffer(0.3))
                        if plate.area < 1.5:
                            continue
                    L.fill("groundlines", plate, 0.26)
                    for g in style.polys(plate):
                        L.line("groundlines", g.exterior, 0.08, 0.34, 0.8)
                    c, s = np.cos(ang), np.sin(ang)
                    for r in (-rk.GAUGE_HALF_M, rk.GAUGE_HALF_M):
                        a = (p.x - c * 1.6 - s * r, p.y - s * 1.6 + c * r)
                        b = (p.x + c * 1.6 - s * r, p.y + s * 1.6 + c * r)
                        L.line("groundlines", LineString([a, b]).intersection(plate), 0.1, style.RAIL_V)


def blocked_test(site):
    """A test for the small things the yard draws (signals, buffer stops):
    blocked(geom) is True when geom touches a building, road concrete or a
    ground obstacle. Made when the drawers run, so it sees the final
    buildings and obstacles, whichever module put them there."""
    from shapely import STRtree
    geoms = [b.poly for b in site.buildings] + [Polygon(p) for _, p in site.obstacles.items]
    tree = STRtree(geoms)

    def blocked(g):
        if any(geoms[i].intersects(g) for i in tree.query(g)):
            return True
        roads = rk.full_roads_near(site, g, 0.5)
        return roads is not None and roads.intersects(g)
    return blocked


def track_end(line, x, y):
    """The drawn track of an OSM rail line that ends nearest (x, y), as
    (track, True when it ends at its start), or (None, False)."""
    best = None
    for t in tracks_of(line):
        for at_start, q in ((True, t.coords[0]), (False, t.coords[-1])):
            d = np.hypot(q[0] - x, q[1] - y)
            if d < TRACK_OFF_M + 1.0 and (best is None or d < best[0]):
                best = (d, t, at_start)
    return (best[1], best[2]) if best else (None, False)


def stop_spot(t, at_start, back):
    """The point `back` metres in from a track's end and the direction
    (radians) towards the end."""
    s = back if at_start else t.length - back
    p = t.interpolate(s)
    q = t.interpolate(s - 1.0 if at_start else s + 1.0)
    return p.x, p.y, float(np.arctan2(q.y - p.y, q.x - p.x))


def goods_trains(site, stretches, taken, yard_area):
    """Rakes of wagons on the free stretches. What stood on a wagon's place
    before (a lorry the industrial module parked across the sidings, yard
    clutter, its sources) is removed. Returns the number of wagons."""
    n_before = len(site.props.items), len(site.salvage.items)
    cars, bodies = 0, []
    for t in stretches:
        mid = t.interpolate(0.5, normalized=True)
        rng = block_rng(331, mid.buffer(1.0))
        if rng.random() > RAKE_SHARE or not site.in_window(t.buffer(10)):
            continue
        kind = str(rng.choice(list(RAKES)))
        names, w = zip(*RAKES[kind])
        fill = rng.uniform(*RAKE_FILL) * t.length
        start = rng.uniform(0, max(t.length - fill, 0.0))
        seq, length = [], 0.0
        while length < fill:
            nm = str(rng.choice(names, p=np.asarray(w) / sum(w)))
            seq.append(nm)
            length += rk.variant("railcar", nm)[1][0] + 1.2 if rk.variant("railcar", nm)[0] >= 0 else 15.0
        placed = rk.rake(site, t, start, seq, rng, taken=taken, clear=yard_area, src_share=WAGON_SOURCE_SHARE)
        cars += len(placed)
        bodies += [rk.rect_at(x, y, a, *rk.variant("railcar", nm)[1]) for x, y, a, nm in placed]
    rk.clear_touching(site, bodies, upto=n_before)
    return cars


# ------------------------------------------------------ container terminal

def max_rect(mask):
    """The largest rectangle of True cells: (area, row0, col0, row1, col1)
    with row1/col1 exclusive."""
    h = np.zeros(mask.shape[1], int)
    best = (0, 0, 0, 0, 0)
    for r in range(mask.shape[0]):
        h = np.where(mask[r], h + 1, 0)
        stack = []
        for c in range(len(h) + 1):
            cur = h[c] if c < len(h) else 0
            start = c
            while stack and stack[-1][1] >= cur:
                s, hh = stack.pop()
                area = hh * (c - s)
                if area > best[0]:
                    best = (area, r - hh + 1, s, r + 1, c)
                start = s
            stack.append((start, cur))
    return best


def terminal_spot(site, angs, avoid, min_wh=TERMINAL_MIN_M, max_wh=TERMINAL_MAX_M):
    """The largest free rectangle of the yard, turned by one of angs
    (degrees), at least min_wh and at most max_wh (long side, short side)
    in metres."""
    area = box(*YARD_BOX).intersection(box(-PLAY_HALF_M + 30, -PLAY_HALF_M + 30, PLAY_HALF_M - 30, PLAY_HALF_M - 30))
    blocked = [avoid]
    for g, *_, kind, _ in (site.full_layout or {}).get("roads", site.roads):
        if g is not None and g.intersects(area):
            blocked.append(g.buffer(6.0 if kind.startswith("rail:") else 3.0))
    blocked += [b.poly.buffer(2.0) for b in site.buildings
                if b.opts.get("stage") not in ("lots", "osm roofs") and b.poly.intersects(area)]
    for g in (site.full_layout or {}).get("lots", []):
        if g.intersects(area):
            blocked.append(g.buffer(2.0))
    for g in (site.full_layout or {}).get("big", []):
        if g.intersects(area):
            blocked.append(g.buffer(4.0))
    c = site.claimed()
    if c is not None:
        blocked.append(c.intersection(area.buffer(5)))
    blocked += [Point(mx, my).buffer(22.0) for _, mx, my in site.markers]
    free = area.difference(unary_union(blocked))
    if free.is_empty:
        return None
    from shapely import contains_xy
    best = None
    for ang in angs:
        F = kit.Frame(area, ang=ang)
        loc = F.local(free)
        x0, y0, x1, y1 = loc.bounds
        cell = 2.0
        nx, ny = int((x1 - x0) / cell) + 1, int((y1 - y0) / cell) + 1
        xs = x0 + (np.arange(nx) + 0.5) * cell
        ys = y0 + (np.arange(ny) + 0.5) * cell
        gx, gy = np.meshgrid(xs, ys)
        prepare(loc)
        mask = contains_xy(loc, gx, gy)
        wx = F.c.x + gx * F.cos - gy * F.sin
        wy = F.c.y + gx * F.sin + gy * F.cos
        mask &= site.districts.at(wx, wy) != 1
        a, r0, c0, r1, c1 = max_rect(mask)
        w, h = (c1 - c0) * cell, (r1 - r0) * cell
        if w >= h:
            w, h = min(w, max_wh[0]), min(h, max_wh[1])
        else:
            w, h = min(w, max_wh[1]), min(h, max_wh[0])
        if max(w, h) < min_wh[0] or min(w, h) < min_wh[1]:
            continue
        if w * h > (best[0] if best else 0):
            u0, v0 = xs[c0] - cell / 2, ys[r0] - cell / 2
            best = (w * h, F.rect(u0 + 1.0, v0 + 1.0, u0 + w - 1.0, v0 + h - 1.0))
    if best is None:
        return None
    for shrink in (0.0, 3.0, 6.0):
        r = best[1].buffer(-shrink, join_style="mitre") if shrink else best[1]
        if land_ok(site, r):
            return r
    return None


def container_terminal(site, rect, rng, stats, crane=True, edge=EDGE_LANE_M):
    """Rows of containers in pairs with lanes between, stacked 1-3 high, a
    gantry crane (with crane) and floodlight masts, `edge` metres of lane
    round the rows. The stacks of a row pair stand in blocks (the stacks
    that touch, rk.split_blocks; a block ends at single containers, gaps and
    cross lanes), each one obstacle and building (rk.stack_runs); a block
    too small to be a building is left as single containers, so every stack
    gives cover and no single container stands inside a block. Returns the
    stack footprints."""
    F = kit.Frame(rect)
    cat = props.CATALOGUE.get("container", [])
    by_len = {}
    for i, e in enumerate(cat):
        by_len.setdefault(round(e["length_m"]), []).append(i)
    x0, x1 = F.x0 + edge, F.x1 - edge
    y = F.y0 + edge
    pairs = []
    while y + 5.3 <= F.y1 - edge:
        pairs.append(y)
        y += 5.3 + LANE_M
    rows = []
    for py in pairs:
        for row in (0, 1):
            cy = py + 1.22 + row * 2.84
            x = x0
            slots = []
            while x < x1 - 6.0:
                if (x - x0) > 0 and ((x - x0) % (CROSS_EVERY_M + CROSS_LANE_M)) > CROSS_EVERY_M:
                    slots.append(None)
                    x += 2.0
                    continue
                ln = 12.19 if rng.random() < 0.65 and x + 12.19 <= x1 else 6.06
                if x + ln > x1:
                    break
                levels = int(rng.choice([1, 2, 3], p=STACK_HEIGHTS))
                if rng.random() < 0.08:
                    slots.append(None)
                else:
                    slots.append((x, ln, levels, int(rng.integers(1 << 30))))
                x += ln + 0.4
            rows.append((cy, slots))
    stacks, singles, sources, draw_stacks, runs = [], 0, 0, [], []
    for p in range(0, len(rows), 2):
        pair = [(cy, s) for cy, slots in rows[p:p + 2] for s in slots if s is not None]
        feet = [rk.rect_at(*F.pt(s[0] + s[1] / 2, cy), F.rad, s[1], rk.CONTAINER_W_M) if s[2] > 1 else None
                for cy, s in pair]
        got, short = rk.split_blocks(feet)
        for k in short:
            cy, s = pair[k]
            pair[k] = (cy, s[:2] + (1,) + s[3:])
        runs += [[feet[k] for k in run] for run in got]
        for cy, s in pair:
            x, ln, levels, seed_s = s
            r = np.random.default_rng(seed_s)
            cx, cyw = F.pt(x + ln / 2, cy)
            if levels == 1:
                vs = by_len.get(round(ln), [])
                if vs:
                    v = int(r.choice(vs))
                    size = (cat[v]["length_m"], cat[v]["width_m"])
                    src = site.salvage if r.random() < 0.5 else None
                    if props.add_vehicle(site.props, src, "container", cx, cyw,
                                         F.rad + (np.pi if r.random() < 0.5 else 0), size, v):
                        singles += 1
                        sources += src is not None
            else:
                stacks.append(rk.rect_at(cx, cyw, F.rad, ln, rk.CONTAINER_W_M))
                draw_stacks.append((cx, cyw, F.rad, ln, levels, int(r.integers(1 << 30))))
                if r.random() < STACK_SOURCE_SHARE:
                    sources += site.salvage.add("shipping_container", cx, cyw, F.rad, ln + 0.6, 3.0)
    crane_at = None
    if pairs and crane:
        py = pairs[int(rng.integers(len(pairs)))]
        cu = rng.uniform(x0 + 10, max(x0 + 11, x1 - 10))
        crane_at = (cu, py + 2.65)
    masts = [F.pt(F.x0 + 3.0, F.y0 + 3.0), F.pt(F.x1 - 3.0, F.y1 - 3.0)] if crane else []
    seed = int(rng.integers(1 << 30))

    def draw(L):
        r = np.random.default_rng(seed)
        kit.pave(L, rect, 0.2, 0.85, sub="groundlines")
        for py in pairs:
            if py + 5.3 + LANE_M / 2 < F.y1 - 1.0:
                L.line("groundlines", F.line([(x0, py + 5.3 + LANE_M / 2), (x1, py + 5.3 + LANE_M / 2)]), 0.15, 0.3,
                       0.7)
        for cx, cyw, a, ln, levels, s in draw_stacks:
            rk.container_stack(L, cx, cyw, a, ln, levels, np.random.default_rng(s))
        if crane_at is not None:
            gantry_crane(L, F, crane_at[0], crane_at[1], r)
        for mx, my in masts:
            floodlight(L, mx, my, F.rad)
    site.drawers.append(draw)
    rk.stack_runs(site, runs)
    site.solid_extra.append(rect)
    stats["terminal"] = {"stacks": len(stacks), "single_containers": singles, "sources": int(sources),
                         "row_pairs": len(pairs), "stack_runs": len(runs), "crane": crane_at is not None}
    return stacks


def gantry_crane(L, F, u, w, rng, span=13.0, gauge=8.0, h=17.0, v=0.36):
    """A rubber-tyred gantry crane straddling a row pair: four legs, sill
    beams, two portal beams, the trolley girders and a trolley."""
    feet = [(u + du, w + dw) for du in (-gauge / 2, gauge / 2) for dw in (-span / 2, span / 2)]
    for fu, fw in feet:
        x, y = F.pt(fu, fw)
        L.fill("interiors", Point(x, y).buffer(0.9, quad_segs=2), 0.06)
    for dw in (-span / 2, span / 2):
        L.tall_span(F.pt(u - gauge / 2 - 1.0, w + dw), F.pt(u + gauge / 2 + 1.0, w + dw), 0.8, 0.8, 0.8, v * 0.8)
    for fu, fw in feet:
        x, y = F.pt(fu, fw)
        L.tall_post(x, y, 0.8, 0.0, h, v * 0.8, v, ang=F.ang)
    for du in (-gauge / 2, gauge / 2):
        L.tall_span(F.pt(u + du, w - span / 2 - 0.6), F.pt(u + du, w + span / 2 + 0.6), 1.0, h, h, v)
    for dw in (-1.2, 1.2):
        L.tall_span(F.pt(u - gauge / 2, w + dw), F.pt(u + gauge / 2, w + dw), 0.5, h + 0.4, h + 0.4, v * 0.9)
    tw = rng.uniform(-span / 3, span / 3)
    L.tall_prism(F.rect(u - 2.2, w + tw - 1.6, u + 2.2, w + tw + 1.6), h + 0.4, h + 2.2, v * 0.7, v * 1.15)


def floodlight(L, x, y, a, h=24.0, v=0.34):
    L.fill("interiors", Point(x, y).buffer(0.8, quad_segs=2), 0.24)
    L.tall_post(x, y, 0.5, 0.0, h, v * 0.8, v)
    c, s = np.cos(a), np.sin(a)
    head = Polygon([(x - c * 1.6 - s * 0.5, y - s * 1.6 + c * 0.5), (x + c * 1.6 - s * 0.5, y + s * 1.6 + c * 0.5),
                    (x + c * 1.6 + s * 0.5, y + s * 1.6 - c * 0.5), (x - c * 1.6 + s * 0.5, y - s * 1.6 - c * 0.5)])
    L.tall_prism(head, h, h + 0.8, v * 0.7, 0.45)


# ----------------------------------------------------------------- build

def build(site, stats, M=None):
    S = stats.setdefault("rail_yard", {})
    rails = yard_rails(site)
    if not rails:
        S["built"] = False
        return
    area = box(*YARD_BOX)
    rng = np.random.default_rng(613)
    parts = []
    taken = []

    shed_poly = None
    for grp in sorted(groups(dead_ends(rails, area)), key=lambda g: -len(g)):
        if len(grp) < 3:
            continue
        got = depot_shed(site, rails, grp, rng)
        if got is None:
            continue
        rect, F, tracks, u_open = got
        site.remove_buildings_touching(rect, ("house",), 1.0)
        doors = []
        for t in tracks:
            for p in (t.coords[0], t.coords[-1]):
                if abs(F.to_local(*p)[0] - u_open) < 3.0:
                    doors.append(p)
        b = bl.Building(rect, 0.22, "rail_shed", tracks=tracks, ang=F.ang, doors=doors)
        b.opts["stage"] = "infra"
        b.opts["state"] = ruins.DAMAGED
        site.buildings.append(b)
        site.claim(rect.buffer(4.0), "infra:depot_shed")
        shed_poly = rect
        parts.append(rect)
        r = block_rng(617, rect)
        inside = sorted(tracks, key=lambda t: -t.length)
        for t in inside[:6:2]:
            name = "metro_car" if r.random() < 0.5 else str(r.choice(["boxcar", "hopper"]))
            rk.rake(site, t, max(2.0, t.length * 0.2), [name], r, taken=taken, clear=rect,
                              src_share=0.5)
        S["depot_shed_m2"] = round(rect.area)
        break

    trav = traverser(site)
    hall = None
    if trav is not None:
        hall, TF, side = works_hall(site, trav)
        site.remove_buildings_touching(trav, ("house",), 1.0)
        site.claim(trav.buffer(3.0), "infra:traverser")
        parts.append(trav)
        if hall is not None:
            site.remove_buildings_touching(hall, ("house",), 1.0)
            b = bl.Building(hall, 0.2, "saw")
            b.opts["stage"] = "infra"
            site.buildings.append(b)
            site.claim(hall.buffer(4.0), "infra:works_hall")
            parts.append(hall)
        S["works_hall_m2"] = round(hall.area) if hall is not None else 0
        seed = int(rng.integers(1 << 30))
        site.drawers.append(lambda L, g=trav, h=hall, s=seed: draw_traverser(L, g, h, np.random.default_rng(s)))

    crossings = crossing_lines(rails)
    bands = [l.buffer(CROSSING_M / 2, cap_style="flat") for l in crossings]
    keep_out = unary_union([p.buffer(3.0) for p in parts] + bands
                           + ([site.claimed()] if site.claimed() is not None else []))
    stretches = free_stretches(site, rails, keep_out)
    ends = dead_ends(rails, area)
    yard_area = area.difference(unary_union([p.buffer(2.0) for p in parts])) if parts else area
    S["goods_wagons"] = goods_trains(site, stretches, taken, yard_area)
    skip = unary_union([p.buffer(2.0) for p in parts] + ([site.claimed()] if site.claimed() is not None else []))
    yard_roads = rk.full_roads_near(site, area, 5.0)
    site.drawers.append(lambda L, sk=skip: draw_crossings(L, rails, crossings, sk, yard_roads))
    S["crossings"] = len(crossings)

    def draw_ends(L):
        blocked = blocked_test(site)
        for x, y, d, i in ends:
            if shed_poly is not None and shed_poly.buffer(2).contains(Point(x, y)):
                continue
            nx, ny = -d[1], d[0]
            for o in (-TRACK_OFF_M, TRACK_OFF_M):
                t, at_start = track_end(rails[i], x + nx * o, y + ny * o)
                if t is None:
                    continue
                for back in np.arange(STOP_BACK_M[0], min(STOP_BACK_M[1], t.length - 2.0) + 0.01, 1.0):
                    sx, sy, a = stop_spot(t, at_start, back)
                    if not blocked(rk.buffer_stop_outline(sx, sy, a).buffer(0.2)):
                        rk.buffer_stop(L, sx, sy, a)
                        break
        tracks = unary_union([t for line in rails for t in tracks_of(line)])
        r = np.random.default_rng(619)
        def signal_spot(line, dist, side):
            p = line.interpolate(dist)
            q = line.interpolate(dist + 1.0)
            a = float(np.arctan2(q.y - p.y, q.x - p.x))
            off = side * (TRACK_OFF_M + 3.2)
            return p.x - np.sin(a) * off, p.y + np.cos(a) * off, a

        for line in rails:
            for dist in np.arange(120.0, line.length - 60.0, 260.0):
                if not area.contains(Point(*signal_spot(line, dist, 1)[:2])):
                    continue
                for shift in SIGNAL_SHIFTS_M:
                    if not 0.0 <= dist + shift <= line.length - 1.0:
                        continue
                    spots = [signal_spot(line, dist + shift, side) for side in (1, -1)]
                    spots = [(x, y, a) for x, y, a in spots if area.contains(Point(x, y))
                             and tracks.distance(Point(x, y)) >= SIGNAL_TRACK_M
                             and not blocked(Point(x + 0.15, y + 0.15).buffer(0.95))]
                    if spots:
                        rk.signal(L, *spots[0], r)
                        break
    site.drawers.append(draw_ends)

    angs = sorted({round(float(np.degrees(np.arctan2(l.coords[-1][1] - l.coords[0][1], l.coords[-1][0] - l.coords[0][0])))
                         % 180.0 / 5.0) * 5.0 for l in rails if l.length > 100})
    sub = terminal_spot(site, angs, unary_union([p.buffer(10.0) for p in parts]) if parts else Polygon(),
                        SUBSTATION_M, SUBSTATION_M)
    if sub is not None:
        parts.append(sub)
        site.claim(sub.buffer(2.0), "infra:substation")
        site.infra_subs = getattr(site, "infra_subs", {})
        site.infra_subs["rail_yard"] = sub
    S["terminals"] = []
    for k in range(TERMINALS):
        spot = terminal_spot(site, angs, unary_union([p.buffer(8.0) for p in parts]) if parts else Polygon())
        if spot is None or (k and spot.area < SECOND_TERMINAL_M2):
            break
        site.claim(spot.buffer(2.0), "infra:container_terminal")
        site.remove_buildings_touching(spot, ("house",), 1.0)
        site.clear_area(spot)
        if site.in_window(spot):
            T = {}
            container_terminal(site, spot, block_rng(623, spot), T)
            S["terminals"].append(T.get("terminal", {}))
        parts.append(spot)
    if parts:
        hull = unary_union(parts + [s.buffer(5.0) for s in stretches]).convex_hull
        site.add_landmark("Helwan Rail Yard", "rail_yard", hull)
    S["built"] = True
    S["stretches"] = len(stretches)


def draw_traverser(L, g, hall, rng):
    """The traverser pit: a sunken strip with rails along it and the
    traverser table standing in it, and track stubs from the pit into the
    hall's doors."""
    F = kit.Frame(g)
    L.fill("groundlines", g, 0.07)
    L.line("groundlines", LineString(g.exterior.coords), 0.3, 0.33)
    for w in (F.y0 + 2.5, F.y1 - 2.5):
        L.line("groundlines", F.line([(F.x0 + 1, w), (F.x1 - 1, w)]), 0.12, 0.34)
    u = rng.uniform(F.x0 + 10, F.x1 - 10)
    table = F.rect(u - 3.5, F.y0 + 0.5, u + 3.5, F.y1 - 0.5)
    L.fill("interiors", affinity.translate(table, 0.5, 0.5), 0.0, 0.45)
    L.fill("interiors", table, 0.24)
    L.line("interiors", table.exterior, 0.1, 0.42)
    for r in (-rk.GAUGE_HALF_M, rk.GAUGE_HALF_M):
        L.line("interiors", F.line([(u + r, F.y0 + 0.5), (u + r, F.y1 - 0.5)]), 0.1, 0.36)
    for uu in np.arange(F.x0 + 8.0, F.x1 - 6.0, 13.0):
        for r in (-rk.GAUGE_HALF_M, rk.GAUGE_HALF_M):
            L.line("groundlines", F.line([(uu + r, F.y0), (uu + r, F.y1)]), 0.08, 0.3, 0.8)


# ---------------------------------------- container rows in industrial lots

def lot_yards(site, stats):
    """Rows of containers (a small container_terminal, no crane) in the
    largest free rectangle of some of the industrial factory and depot lots,
    with chance LOT_YARD_SHARE per lot that has room. The rectangle keeps
    LOT_CLEAR_M from everything on the lot: what the industrial modules put
    there (Compound.things: halls, equipment that is drawn and made a source
    later, vehicles, yards), and every building, obstacle, prop and source,
    so the sources stay reachable; and LOT_EDGE_M inside the lot's
    fence."""
    lots = [cp for cp in getattr(site, "industrial_lots", [])
            if cp.lot in ("factory", "depot") and site.in_window(cp.area)]
    out = {"yards": 0, "stacks": 0, "single_containers": 0, "stack_runs": 0, "sources": 0}
    if not lots:
        stats["lot_yards"] = out
        return
    from shapely import STRtree, contains_xy
    things = [b.poly for b in site.buildings]
    things += [Polygon(p) for _, p in site.obstacles.items]
    things += [rk.rect_at(x, y, r, sx, sy) for _, x, y, r, sx, sy, _ in site.props.items]
    things += [Point(s[1], s[2]).buffer(max(s[4], s[5]) / 2, quad_segs=4) for s in site.salvage.items]
    things += [Point(mx, my).buffer(LOT_MARKER_M - LOT_CLEAR_M) for _, mx, my in site.markers]
    tree = STRtree(things)
    cell = 2.0
    for cp in lots:
        lot = cp.area
        rng = block_rng(661, lot)
        if rng.random() > LOT_YARD_SHARE:
            continue
        inner = lot.buffer(-LOT_EDGE_M, join_style="mitre")
        near = [things[i].buffer(LOT_CLEAR_M, quad_segs=4) for i in tree.query(inner.buffer(LOT_CLEAR_M))]
        near += [g.buffer(LOT_CLEAR_M, quad_segs=4) for g in cp.things if g is not None and not g.is_empty]
        c = site.claimed()
        if c is not None and c.intersects(inner):
            near.append(c.intersection(lot.buffer(5.0)))
        free = inner.difference(unary_union(near)) if near else inner
        if free.is_empty or free.area < LOT_YARD_MIN_M[0] * LOT_YARD_MIN_M[1]:
            continue
        F = kit.Frame(lot)
        loc = F.local(free)
        x0, y0, x1, y1 = loc.bounds
        nx, ny = int((x1 - x0) / cell) + 1, int((y1 - y0) / cell) + 1
        xs, ys = x0 + (np.arange(nx) + 0.5) * cell, y0 + (np.arange(ny) + 0.5) * cell
        gx, gy = np.meshgrid(xs, ys)
        prepare(loc)
        _, r0, c0, r1, c1 = max_rect(contains_xy(loc, gx, gy))
        W, H = (c1 - c0) * cell, (r1 - r0) * cell
        cap = LOT_YARD_MAX_M if W >= H else LOT_YARD_MAX_M[::-1]
        w, h = min(W, cap[0]), min(H, cap[1])
        if max(w, h) < LOT_YARD_MIN_M[0] or min(w, h) < LOT_YARD_MIN_M[1]:
            continue
        u0, v0 = xs[c0] - cell / 2, ys[r0] - cell / 2
        rect = F.rect(u0, v0, u0 + w, v0 + h)
        if not site.is_free(rect, districts=False):
            continue
        site.claim(rect.buffer(1.0), "infra:lot_yard")
        site.clear_area(rect)
        T = {}
        container_terminal(site, rect, block_rng(667, rect), T, crane=False, edge=1.5)
        t = T.get("terminal", {})
        out["yards"] += 1
        for k in ("stacks", "single_containers", "stack_runs", "sources"):
            out[k] += int(t.get(k, 0))
    stats["lot_yards"] = out


# --------------------------------------------- stacks in industrial yards

def outer_sides(items):
    """The containers (prop items) along the outside of each yard: lists of
    item indices, one per side, each the two outermost rows on that side (a
    yard of up to three rows gives one or two such sides). Yards are found
    as chains of containers less than YARD_LINK_M apart, rows by the
    coordinate across the containers' long axis."""
    pts = np.array([[it[1], it[2]] for it in items])
    n = len(items)
    group = list(range(n))

    def find(a):
        while group[a] != a:
            group[a] = group[group[a]]
            a = group[a]
        return a

    for i in range(n):
        d = np.hypot(pts[i + 1:, 0] - pts[i, 0], pts[i + 1:, 1] - pts[i, 1])
        for j in np.flatnonzero(d < YARD_LINK_M) + i + 1:
            group[find(int(j))] = find(i)
    yards = {}
    for i in range(n):
        yards.setdefault(find(i), []).append(i)
    out = []
    for members in yards.values():
        a = items[members[0]][3]
        across = np.array([-np.sin(a), np.cos(a)])
        v = dict(zip(members, pts[members] @ across))
        rows = []
        for m in sorted(members, key=lambda m: v[m]):
            if rows and v[m] - v[rows[-1][-1]] < 1.5:
                rows[-1].append(m)
            else:
                rows.append([m])
        if len(rows) <= 2:
            sides = [rows]
        elif len(rows) == 3:
            sides = [rows[:2], rows[2:]]
        else:
            sides = [rows[:2], rows[-2:]]
        out += [[m for r in side for m in r] for side in sides]
    return out


def industrial_stacks(site, stats):
    """Stacks containers 2 or 3 high along the outside of the industrial
    container yards: each block of containers in the two outermost rows of
    a side (outer_sides, rk.split_blocks; large enough to be a building) is
    stacked whole with chance YARD_STACK_SHARE, in place (talls stacks over
    one ground obstacle and a gutted building, rk.stack_runs, so the block
    gives cover). The rows further in stay containers a mecha can push. A
    stacked container that was a salvage source stays one, searched from
    the open ground beside its block (at most two rows in, under 8 m).
    Nothing in the border band is stacked."""
    ci = props.KINDS.index("container")
    infra_claims = site.claimed()
    keep, convert, cands = [], [], []
    for it in site.props.items:
        if it[0] != ci:
            keep.append(it)
            continue
        p = Point(it[1], it[2])
        if (infra_claims is not None and infra_claims.contains(p)) or site.districts.of_geom(p.buffer(5.0)) != 1:
            keep.append(it)
            continue
        cands.append(it)
    chosen, runs = set(), []
    for side in (outer_sides(cands) if cands else []):
        feet = [rk.rect_at(cands[i][1], cands[i][2], cands[i][3], cands[i][4], rk.CONTAINER_W_M) for i in side]
        for block in rk.split_blocks(feet)[0]:
            hull = rk.run_outline([feet[k] for k in block])
            if hull is None or not site.in_window(hull.buffer(10)) or max(map(abs, hull.bounds)) > PLAY_HALF_M:
                continue
            if block_rng(641, hull).random() < YARD_STACK_SHARE:
                chosen.update(side[k] for k in block)
                runs.append([feet[k] for k in block])
    for i, it in enumerate(cands):
        if i in chosen:
            r = block_rng(643, Point(it[1], it[2]).buffer(1.0))
            convert.append((it, 3 if r.random() < YARD_THREE_HIGH else 2, int(r.integers(1 << 30))))
        else:
            keep.append(it)
    if not convert:
        stats["yard_stacks"] = 0
        return
    site.props.replace_items(keep)
    at = {(round(it[1], 3), round(it[2], 3)) for it, _, _ in convert}
    sal = []
    for s in site.salvage.items:
        if s[8] and (round(s[1], 3), round(s[2], 3)) in at:
            s = s[:8] + (0,)
        sal.append(s)
    site.salvage.items = sal

    def draw(L):
        for it, levels, s in convert:
            rk.container_stack(L, it[1], it[2], it[3], it[4], levels, np.random.default_rng(s))
    site.drawers.append(draw)
    rk.stack_runs(site, runs)
    stats["yard_stacks"] = len(convert)
    stats["yard_stack_runs"] = len(runs)
