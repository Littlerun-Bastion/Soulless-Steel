"""The Cairo Metro line 1 (the OSM "Helwan-ElMarg Railway") across the map:
its walled double-track corridor from the north edge to the Helwan
terminus, the terminus with its island and side platforms, canopies,
buffer stops and station hall, the Ain Helwan station's side platforms,
overhead line portals and wires, level crossings, and stopped trains.

The OSM export maps the line as two tracks a little apart (one per
direction) and a few station tracks. The corridor runs along the middle
of the two, with the tracks TRACK_HALF_M either side, and opens out to
STATION_HALF_M through the terminus throat. Houses in the corridor are
removed or trimmed back to its walls; the corridor is claimed so no later
module builds on it.
"""
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import nearest_points, unary_union

import buildings as bl
import kit
import props
import railkit as rk
from frame import PLAY_HALF_M
from gen_city import FRAME, is_buildable, min_width, to_frame_m

TRACK_HALF_M = 2.1
STATION_HALF_M = 6.6
## The corridor's edge is this far outside the outer track. Its walls are
## WALL_W_M thick and stand inside it, their shadow strip (kit.wall: 0.3 m
## wider than the wall) along the edge.
WALL_OUT_M = 7.9
WALL_W_M = 0.4
WALL_IN_M = (WALL_W_M + 0.3) / 2
## The throat where the two tracks spread to the station's spacing.
THROAT_M = 80.0
## Overhead line: portal spacing on the open line and in the station, the
## contact wire height and the portal beam height.
PORTAL_STEP_M = 50.0
STATION_PORTAL_STEP_M = 36.0
WIRE_H_M = 5.6
PORTAL_H_M = 6.8
## A house cut by the corridor is kept (trimmed) when this share of it is
## left; a large roof when LARGE_KEEP_SHARE is; either only when what is
## left is a building (MIN_BUILDING_M2 or more).
HOUSE_KEEP_SHARE = 0.6
LARGE_KEEP_SHARE = 0.5
MIN_BUILDING_M2 = 60.0
## Chance that a car of a stopped train is a salvage source.
CAR_SOURCE_SHARE = 0.5
SAMPLE_M = 2.0


def subway_lines(site):
    out = []
    for kind, rings, p in site.feats or []:
        if kind == "line" and p.get("railway") == "subway":
            line = LineString(to_frame_m(rings[0]))
            if line.length > 20:
                out.append(line)
    return out


def terminus_platform(site):
    """The OSM platform of the Helwan terminus (the largest metro platform
    polygon), or None."""
    best = None
    for kind, rings, p in site.feats or []:
        if kind == "poly" and p.get("railway") == "platform":
            g = Polygon(to_frame_m(rings[0])).buffer(0)
            if best is None or g.area > best.area:
                best = g
    return best


def midline(a, b, step=5.0):
    """The line half way between two roughly parallel lines."""
    pts = []
    for d in np.arange(0.0, a.length, step):
        p = a.interpolate(d)
        q = nearest_points(b, p)[0]
        pts.append(((p.x + q.x) / 2, (p.y + q.y) / 2))
    return LineString(pts)


def chaikin(pts, n=3):
    pts = np.asarray(pts, float)
    for _ in range(n):
        q = 0.75 * pts[:-1] + 0.25 * pts[1:]
        r = 0.25 * pts[:-1] + 0.75 * pts[1:]
        mid = np.empty((2 * len(q), 2))
        mid[0::2], mid[1::2] = q, r
        pts = np.concatenate([pts[:1], mid, pts[-1:]])
    return pts


class Line:
    """The metro's centre line, sampled every SAMPLE_M: points, directions,
    arc lengths, and the station frame (north end, axis, length)."""

    def __init__(self, site):
        lines = sorted(subway_lines(site), key=lambda g: -g.length)
        plat = terminus_platform(site)
        self.ok = len(lines) >= 2 and plat is not None
        if not self.ok:
            return
        a, b = lines[0], lines[1]
        if a.coords[0][1] > a.coords[-1][1]:
            a = LineString(a.coords[::-1])
        if b.coords[0][1] > b.coords[-1][1]:
            b = LineString(b.coords[::-1])
        mid = midline(a, b)
        rr = np.asarray(plat.minimum_rotated_rectangle.exterior.coords)[:4]
        e = [rr[(i + 1) % 4] - rr[i] for i in range(4)]
        i = int(np.argmax([np.hypot(*v) for v in e[:2]]))
        ends = [(rr[(i + 1) % 4] + rr[(i + 2) % 4]) / 2, (rr[(i + 3) % 4] + rr[i]) / 2]
        pn, ps = sorted(ends, key=lambda p: p[1])
        self.pn, self.ps = np.asarray(pn), np.asarray(ps)
        self.length = float(np.hypot(*(self.ps - self.pn)))
        self.u = (self.ps - self.pn) / self.length
        self.n = np.array([-self.u[1], self.u[0]])
        q = self.pn - self.u * THROAT_M
        head = [p for p in mid.coords if np.hypot(p[0] - pn[0], p[1] - pn[1]) > THROAT_M + 90.0]
        # The open line must reach the throat from behind it (along the axis).
        head = [p for p in head if np.dot(np.asarray(p) - q, self.u) < -30.0]
        curve = chaikin(head + [tuple(q - self.u * 30.0), tuple(q)], 4)
        tail = np.array([q + self.u * t for t in np.arange(SAMPLE_M, THROAT_M + self.length + 2.0, SAMPLE_M)])
        line = LineString(np.concatenate([curve, tail]))
        pts, tang = rk.sample(line, SAMPLE_M)
        self.line = line
        self.pts, self.tang = pts, tang
        self.s = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])
        self.s_throat = float(self.s[-1] - self.length - THROAT_M)
        self.s_north = self.s_throat + THROAT_M
        t = np.clip((self.s - self.s_throat) / THROAT_M, 0.0, 1.0)
        t = t * t * (3 - 2 * t)
        self.off = TRACK_HALF_M + (STATION_HALF_M - TRACK_HALF_M) * t

    def local(self, x, y):
        """A station-frame point: x metres along the axis from the north end
        of the platform, y across (+ to the axis's left normal)."""
        p = self.pn + self.u * x + self.n * y
        return float(p[0]), float(p[1])

    def rect(self, x0, y0, x1, y1):
        return Polygon([self.local(x0, y0), self.local(x1, y0), self.local(x1, y1), self.local(x0, y1)])

    def track(self, side, s0=None, s1=None):
        """Track `side` (-1 or +1) between arc lengths s0 and s1."""
        sel = np.ones(len(self.s), bool)
        if s0 is not None:
            sel &= self.s >= s0
        if s1 is not None:
            sel &= self.s <= s1
        return LineString(rk.offset_path(self.pts[sel], self.tang[sel], side * self.off[sel]))

    def at(self, s):
        i = int(np.clip(np.searchsorted(self.s, s), 0, len(self.s) - 1))
        return self.pts[i], self.tang[i], self.off[i]


def clear_buildings(site, area):
    """Trims the houses and large roofs that come within 0.5 m of area back
    to 0.5 m from it. Where what is left would not make a building, one in
    area is removed and one only near it stays as it is. Returns (removed,
    trimmed)."""
    keep, removed, trimmed = [], 0, 0
    grown = area.buffer(0.5)
    for b in site.buildings:
        if b.kind not in ("house", "big") or not b.poly.intersects(grown):
            keep.append(b)
            continue
        rest = kit.largest(b.poly.difference(grown))
        share = HOUSE_KEEP_SHARE if b.kind == "house" else LARGE_KEEP_SHARE
        ok = rest is not None and rest.area >= max(share * b.poly.area, MIN_BUILDING_M2)
        if ok and b.kind == "house":
            ok = is_buildable(rest)
        elif ok:
            ok = min_width(rest) >= 5.0
        if ok:
            b.poly = rest.simplify(0.1)
            trimmed += 1
            keep.append(b)
        elif not b.poly.intersects(area):
            keep.append(b)
        else:
            removed += 1
    site.buildings = keep
    return removed, trimmed


def trim_side_streets(site, corridor, M):
    """Streets that run into the corridor without crossing the line end at
    its edge, so no street lies under the tracks. A street whose centre line
    crosses the line is a level crossing and stays whole. Both road lists
    (the window's and the whole map's, which hold the same entries) are cut
    the same way. Returns how many streets were cut."""
    crossing = {}

    def cut(r):
        g, v, w, flag, kind, line = r
        if g is None or kind.startswith("rail:") or not g.intersects(corridor):
            return r
        key = id(r)
        if key not in crossing:
            crossing[key] = line is not None and not line.intersection(M.line).is_empty
        if crossing[key]:
            return r
        g2 = g.difference(corridor)
        if g2.area >= g.area - 0.5:
            return r
        if g2.is_empty:
            return None
        if line is None:
            return (g2, v, w, flag, kind, None)
        line2 = line.difference(corridor)
        if line2.geom_type != "LineString":
            parts = [p for p in getattr(line2, "geoms", []) if p.geom_type == "LineString"]
            line2 = max(parts, key=lambda p: p.length) if parts else None
        return None if line2 is None or line2.is_empty else (g2, v, w, flag, kind, line2)

    lists = [site.roads]
    full = (site.full_layout or {}).get("roads")
    if full is not None and full is not site.roads:
        lists.append(full)
    done = {}
    for roads in lists:
        for r in roads:
            if id(r) not in done:
                done[id(r)] = cut(r)
        roads[:] = [done[id(r)] for r in roads if done[id(r)] is not None]
    n = sum(1 for k, new in done.items() if new is None or id(new) != k)
    site._road_tree = site._road_geoms = None
    site._full_road_tree = site._full_road_geoms = None
    return n


def build(site, stats):
    M = Line(site)
    if not M.ok:
        stats["metro"] = {"built": False}
        return None
    rng = np.random.default_rng(907)
    s_end = float(M.s[-1])
    s_buf = s_end - 2.0
    in_frame = (np.abs(M.pts[:, 0]) < FRAME.bounds[2] + 5) & (np.abs(M.pts[:, 1]) < FRAME.bounds[3] + 5)
    first = int(np.argmax(in_frame))
    s0 = float(M.s[first])

    # The corridor: wall to wall on the open line, the station block at the
    # terminus (platforms, the concourse and the hall).
    sel = M.s >= s0
    sel &= M.s <= M.s_north + 1.0
    half = M.off[sel] + WALL_OUT_M
    left = rk.offset_path(M.pts[sel], M.tang[sel], half)
    right = rk.offset_path(M.pts[sel], M.tang[sel], -half)
    open_line = Polygon(np.concatenate([left, right[::-1]])).buffer(0)
    station_half = STATION_HALF_M + 7.6
    block = M.rect(-2.0, -station_half, M.length + 30.0, station_half)
    corridor = unary_union([open_line, block]).intersection(FRAME)
    removed, trimmed = clear_buildings(site, corridor)
    site.clear_area(corridor)
    site.claim(corridor, "infra:metro")
    streets_cut = trim_side_streets(site, corridor, M)
    tracks = [M.track(-1, s0, s_buf), M.track(1, s0, s_buf)]
    beds = unary_union([t.buffer(rk.BED_HALF_M, cap_style="flat") for t in tracks])
    site.solid_extra.append(beds)
    props.ROAD_KEEP_OFF.append(corridor)

    road_near = rk.full_roads_near(site, corridor, 5.0)
    road_cut = road_near.buffer(1.5) if road_near is not None else Polygon()
    walls = []
    for side in (-1, 1):
        edge = LineString(rk.offset_path(M.pts[sel], M.tang[sel], side * (half - WALL_IN_M)))
        walls.append(edge)
    sx0, sx1, sy = -2.0, M.length + 30.0 - WALL_IN_M, station_half - WALL_IN_M
    walls += [LineString([M.local(sx0, side * sy), M.local(sx1, side * sy)]) for side in (-1, 1)]
    walls.append(LineString([M.local(sx1, -sy), M.local(sx1, sy)]))
    wall_parts = []
    for w in walls:
        g = w.difference(road_cut)
        wall_parts += [p for p in getattr(g, "geoms", [g]) if p.geom_type == "LineString" and p.length > 2.0]

    crossings = []
    if site.roads:
        for g, _, w, _, kind, line in (site.full_layout or {}).get("roads", site.roads):
            if kind.startswith("rail:") or line is None or w < 4.0:
                continue
            x = line.intersection(M.line)
            for p in getattr(x, "geoms", [x]):
                if p.geom_type == "Point" and abs(p.x) < FRAME.bounds[2] and abs(p.y) < FRAME.bounds[3]:
                    crossings.append((p.x, p.y, w, line))

    station = Station(site, M)
    portals = portal_points(M, s0, s_buf, road_near)
    trains = place_trains(site, M, rng)
    ain = ain_helwan(site, M)

    def draw(L):
        r = np.random.default_rng(911)
        kit.pave(L, corridor.difference(road_cut), 0.12, 0.55, sub="groundlines", edge=False)
        for t in tracks:
            rk.track(L, t)
        for part in wall_parts:
            kit.wall(L, part, WALL_W_M, 0.27)
        for x, y, w, line in crossings:
            d = line.project(Point(x, y))
            for sgn in (-1, 1):
                q = line.interpolate(min(max(d + sgn * (TRACK_HALF_M + 4.5), 0), line.length))
                q2 = line.interpolate(min(max(d + sgn * (TRACK_HALF_M + 4.6), 0), line.length))
                dx, dy = q2.x - q.x, q2.y - q.y
                n = np.hypot(dx, dy) or 1.0
                nx, ny = -dy / n * w / 2, dx / n * w / 2
                L.line("groundlines", LineString([(q.x - nx, q.y - ny), (q.x + nx, q.y + ny)]), 0.35, 0.36, 0.85)
        station.draw(L, r)
        for s_p, half_span, masts in portals:
            p, t, off = M.at(s_p)
            rk.portal(L, p[0], p[1], float(np.arctan2(t[1], t[0])), half_span, PORTAL_H_M, masts=masts)
        for a, b in zip(portals[:-1], portals[1:]):
            for side in (-1, 1):
                pa, ta, oa = M.at(a[0])
                pb, tb, ob = M.at(b[0])
                na, nb = np.array([-ta[1], ta[0]]), np.array([-tb[1], tb[0]])
                rk.wire(L, tuple(pa + na * side * oa), tuple(pb + nb * side * ob), WIRE_H_M)
        ain.draw(L, r)

    site.drawers.append(draw)
    site.add_landmark("Helwan Metro Station", "metro_station", block)
    if ain.area is not None:
        site.add_landmark("Ain Helwan Metro Station", "metro_station", ain.area)
    stats["metro"] = {
        "built": True, "corridor_m": round(M.s_north - s0), "houses_removed": removed, "trimmed": trimmed,
        "level_crossings": len(crossings), "streets_cut": streets_cut, "portals": len(portals), "train_cars": trains,
        "ain_helwan_platforms": ain.count,
    }
    return M


def portal_points(M, s0, s1, roads=None):
    """Portals along the line every PORTAL_STEP_M (STATION_PORTAL_STEP_M
    past the throat): (arc length, half span, (left mast, right mast)). A
    mast whose foot would stand on road concrete (`roads`, where a street
    meets the line) is left out and the beam hangs from the other one, so
    the wire spans stay as they are; with both feet on a road both stay."""
    out = []
    s = s0 + 10.0
    while s < s1 - 4.0:
        p, t, off = M.at(s)
        n = np.array([-t[1], t[0]]) * (off + 2.3)
        masts = tuple(roads is None or not roads.intersects(Point(*q).buffer(0.8)) for q in (p + n, p - n))
        out.append((s, off + 2.3, masts if any(masts) else (True, True)))
        s += PORTAL_STEP_M if s < M.s_throat else STATION_PORTAL_STEP_M
    return out


def place_trains(site, M, rng):
    """A train at the terminus platform, a shorter one on its other track,
    and one stopped on the open line between the stations."""
    placed = 0
    s_buf = float(M.s[-1]) - 2.0

    def run(side, s_front, n_cars, seed):
        r = np.random.default_rng(seed)
        line = M.track(side, s_front - n_cars * 21.5 - 10.0, s_front)
        names = [("metro_cab", True)] + [("metro_car", False)] * (n_cars - 2) + [("metro_cab", False)]
        start = line.length - n_cars * 21.0
        out = 0
        d = max(start, 0.0)
        for name, flip in names:
            v, size = rk.variant("railcar", name)
            if v < 0:
                return out
            ln, wd = size
            if d + ln > line.length:
                break
            p0, p1 = line.interpolate(d), line.interpolate(d + ln)
            x, y = (p0.x + p1.x) / 2, (p0.y + p1.y) / 2
            if abs(x) > PLAY_HALF_M - 30 or abs(y) > PLAY_HALF_M - 30 or not site.in_window(Point(x, y).buffer(15)):
                d += ln + 1.0
                continue
            ang = float(np.arctan2(p1.y - p0.y, p1.x - p0.x)) + (np.pi if flip else 0.0)
            src = site.salvage if r.random() < CAR_SOURCE_SHARE else None
            if props.add_vehicle(site.props, src, "railcar", x, y, ang, size, v):
                out += 1
            d += ln + 1.0
        return out

    placed += run(-1, s_buf - 1.0, 8, 31)
    placed += run(1, s_buf - 45.0, 6, 32)
    mid = 0.5 * (M.s_throat + max(M.s[0], M.s_throat - 1700.0))
    placed += run(-1, mid, 6, 33)
    return placed


class Station:
    """The Helwan terminus in the station frame: two tracks at
    +-STATION_HALF_M, an island platform between them and a side platform
    outside each, canopies, buffer stops, a concourse across the track ends
    and the station hall beyond it."""

    def __init__(self, site, M):
        self.M = M
        Ln = M.length
        h = STATION_HALF_M
        self.island = M.rect(14.0, -h + 1.75, Ln + 1.0, h - 1.75)
        self.sides = [M.rect(14.0, -h - 7.2, Ln + 1.0, -h - 1.75), M.rect(14.0, h + 1.75, Ln + 1.0, h + 7.2)]
        self.concourse = M.rect(Ln + 1.0, -h - 7.2, Ln + 9.0, h + 7.2)
        hall = M.rect(Ln + 9.0, -h - 6.0, Ln + 25.0, h + 6.0)
        b = bl.Building(hall, 0.2, "big")
        b.opts["stage"] = "infra"
        site.buildings.append(b)
        self.hall = hall
        self.edges = []
        for side in (-1, 1):
            for off in (h - 1.75, h + 1.75):
                self.edges.append(LineString([M.local(14.0, side * off), M.local(Ln - 1.0, side * off)]))
        self.signals = [(M.local(-THROAT_M - 20.0, side * (TRACK_HALF_M + 3.0)), side) for side in (-1, 1)]
        site.solid_extra.append(unary_union([self.island, self.concourse] + self.sides))

    def draw(self, L, rng):
        M = self.M
        Ln = M.length
        h = STATION_HALF_M
        for g in [self.island] + self.sides:
            rk.platform(L, g)
        rk.platform(L, self.concourse, v=0.24)
        for e in self.edges:
            L.line("interiors", e, 0.18, 0.4)
        ang = float(np.arctan2(M.u[1], M.u[0]))
        for side in (-1, 1):
            x, y = M.local(Ln - 1.0, side * h)
            rk.buffer_stop(L, x, y, ang)
        x0, x1 = 30.0, Ln - 12.0
        rk.canopy(L, LineString([M.local(x0, 0.0), M.local(x1, 0.0)]), h - 2.0)
        for side in (-1, 1):
            rk.canopy(L, LineString([M.local(x0 + 10, side * (h + 4.6)), M.local(x1 - 10, side * (h + 4.6))]), 2.2)
        for (x, y), side in self.signals:
            rk.signal(L, x, y, ang, rng)


class AinHelwan:
    def __init__(self):
        self.area = None
        self.count = 0
        self.parts = []

    def draw(self, L, rng):
        for poly, edge, axis in self.parts:
            rk.platform(L, poly, [edge])
            rk.canopy(L, axis, 2.4)


def ain_helwan(site, M):
    """Side platforms along the open line where OSM maps the platforms of
    Ain Helwan station (platform lines beside the line)."""
    A = AinHelwan()
    areas = []
    for kind, rings, p in site.feats or []:
        if kind != "line" or p.get("railway") != "platform":
            continue
        g = LineString(to_frame_m(rings[0]))
        if g.distance(M.line) > 25.0 or g.length < 40:
            continue
        sa, sb = sorted((M.line.project(Point(g.coords[0])), M.line.project(Point(g.coords[-1]))))
        if sb > M.s_throat - 50:
            continue
        mid = g.interpolate(0.5, normalized=True)
        pm, tm, _ = M.at(M.line.project(mid))
        side = 1 if np.dot(np.array([mid.x, mid.y]) - pm, np.array([-tm[1], tm[0]])) > 0 else -1
        sel = (M.s >= sa) & (M.s <= sb)
        if sel.sum() < 5:
            continue
        inner = rk.offset_path(M.pts[sel], M.tang[sel], side * (TRACK_HALF_M + 1.75))
        outer = rk.offset_path(M.pts[sel], M.tang[sel], side * (TRACK_HALF_M + 6.0))
        poly = Polygon(np.concatenate([inner, outer[::-1]])).buffer(0)
        axis = LineString(rk.offset_path(M.pts[sel], M.tang[sel], side * (TRACK_HALF_M + 4.0)))
        trim = max(axis.length * 0.15, 5.0)
        axis = LineString([axis.interpolate(trim).coords[0]] + [c for c in axis.coords
                                                                 if trim < axis.project(Point(c)) < axis.length - trim]
                          + [axis.interpolate(axis.length - trim).coords[0]])
        A.parts.append((poly, LineString(inner), axis))
        areas.append(poly)
    A.count = len(A.parts)
    if areas:
        A.area = unary_union(areas).buffer(12.0)
        site.solid_extra.append(unary_union(areas))
    return A
