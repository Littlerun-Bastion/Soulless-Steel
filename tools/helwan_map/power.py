"""High-voltage pylon lines and electrical substations.

The OSM export has no power lines; the region's power station is north of
the map. LINES lists the lines: each comes in from a map edge (an x range
on the north or south edge) to a substation, or runs from one substation to
another. SUBSTATIONS gives each substation an anchor; it goes on the
nearest free ground (SUB_SIZE_M, off roads, rails and buildings, a road
near for its gate).

Routing: a cost grid (GRID_M cells) over the whole map from the full
layout: buildings (with a margin), landmark claims and the reserved real
places are closed; roads, rail, water, the industrial and market districts
and the ground near buildings cost more than open ground. A Dijkstra path
from the substation to the edge (or the other substation) is then walked
by spans: each next tower is the farthest point of the path within
SPAN_M whose straight span crosses no building and whose foot is on free
ground, so the wires never pass over a roof.

Towers are lattice pylons (railkit.lattice_tower) TOWER_H_M tall with three
cross-arms, drawn in the talls sublayer; their base is a small ground
obstacle. Six conductors and an earth wire run between towers as straight
talls spans. Substations: a fenced gravel yard, line entry gantries,
busbars on posts, transformers (salvage sources, ground obstacles),
switchgear bays (switchgear sources), a control building, cable trenches.
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy import sparse
from scipy.sparse.csgraph import dijkstra
from shapely.geometry import LineString, Point, box
from shapely.ops import nearest_points, unary_union
from shapely.strtree import STRtree

import buildings as bl
import equipment
import kit
import railkit as rk
from frame import PLAY_HALF_M
from gen_city import HALF_M, block_rng
from obstacles import PIPE

GRID_M = 7.5
## Wires and towers keep at least this far from a building cell (metres
## between cell centres), so a line only follows open ground wider than
## about three cells.
CLEAR_M = 8.0
SPAN_M = (250.0, 350.0)
MIN_SPAN_M = 60.0
TOWER_H_M = 36.0
ARM_H_M = (23.0, 28.5, 33.5)
ARM_HALF_M = (6.0, 7.6, 6.0)
TOWER_BASE_M = 3.6
## The land under the wires is claimed this far either side of the line
## (the widest cross-arm and a margin), so no later module builds under it.
SPAN_CLAIM_M = 14.0
SUB_SIZE_M = (62.0, 44.0)
## Cross positions (local, metres) of the two entry gantries on a short
## side of a substation.
GANTRY_W = (-9.0, 9.0)
GANTRY_H_M = 12.0
BUS_H_M = 8.5
## The busbar portals' posts stand PORTAL_W_M either side of the yard's
## long axis. The transformers stand 9 m in from the fence, or nearer it
## where the yard is narrow, so that their foot keeps 1 m clear of the
## posts' bases.
PORTAL_W_M = 6.5
## Real places other modules build at (the observatory, the Japanese
## Garden, the hospital, the two cemeteries, the club, the road under
## construction): the lines keep off them and no substation goes there.
## (x, y, radius) in map metres.
RESERVED = (
    (2078.0, -1957.0, 260.0), (1800.0, -1000.0, 330.0), (1760.0, -1430.0, 220.0),
    (1877.0, 877.0, 230.0), (-940.0, 341.0, 260.0), (1678.0, -63.0, 160.0),
    (2017.0, 1099.0, 120.0),
)
## name: anchor (x, y) in map metres.
SUBSTATIONS = {
    "rail_yard": (610.0, -2150.0),
    "north_east": (1700.0, -1850.0),
    "south": (650.0, 1200.0),
    "south_east": (1250.0, 1550.0),
    "south_west": (-350.0, 1700.0),
}
## (from, to): from is (edge, a0, a1) for a stretch of a map edge (edge
## "north" or "south" with an x range, "east" or "west" with a y range),
## a substation name, or a tuple of these to try in turn. A substation no
## line reaches is fed by underground cable (it is built all the same):
## the rail yard's, which the town closes in on every side (no route keeps
## a line off the roofs there).
LINES = (
    (("north", 1450.0, 2050.0), "north_east"),
    (("east", -2450.0, -1500.0), "north_east"),
    (("south", 200.0, 1100.0), "south"),
    ("south", "south_east"),
    ("south", "south_west"),
)


class Grid:
    """The routing rasters over the whole map (cell GRID_M, row = y)."""

    def __init__(self, site):
        self.n = int(round(2 * HALF_M / GRID_M))
        lay = site.full_layout or {"roads": site.roads, "lots": [], "big": []}
        lots = list(lay.get("lots", []))
        cleared = [g for g, owner in site.claims if owner.startswith("infra:")]
        if cleared and lots:
            from shapely import contains_xy
            cu = unary_union(cleared)
            cen = np.array([[g.centroid.x, g.centroid.y] for g in lots])
            inside = contains_xy(cu, cen[:, 0], cen[:, 1])
            lots = [g for g, k in zip(lots, inside) if not k]
        bld = lots + list(lay.get("big", []))
        bld += [b.poly for b in site.buildings
                if b.opts.get("stage") not in ("lots", "osm roofs") and b.kind != "container_stack"]
        self.bld = self.raster(bld)
        roads = [g for g, *_, kind, _ in lay["roads"] if g is not None and not kind.startswith("rail:")]
        rails = [g for g, *_, kind, _ in lay["roads"] if g is not None and kind.startswith("rail:")]
        self.road = self.raster([g.buffer(3.0) for g in roads])
        self.rail = self.raster([g.buffer(3.0) for g in rails])
        self.water = self.raster([site.water])
        c = site.claimed()
        self.taken = self.raster([c] if c is not None else [])
        lm = [g for g, owner in site.claims if owner.startswith("landmarks")]
        self.reserved = self.raster(lm + [Point(x, y).buffer(r) for x, y, r in RESERVED])
        codes = np.zeros((self.n, self.n), np.uint8)
        xs = (np.arange(self.n) + 0.5) * GRID_M - HALF_M
        gx, gy = np.meshgrid(xs, xs)
        codes[:] = site.districts.codes[site.districts.ij(gx, gy)]
        self.codes = codes
        from scipy import ndimage as ndi
        self.bld_dist = ndi.distance_transform_edt(~self.bld) * GRID_M
        cost = np.ones((self.n, self.n), np.float32)
        cost += 2.0 * self.road + 0.5 * self.rail + 6.0 * self.water
        cost += 4.0 * (codes == 1) + 3.0 * (codes == 2)
        cost += 3.0 * np.clip(1.0 - self.bld_dist / 40.0, 0.0, 1.0)
        cost += 2.0 * self.taken
        self.cost = cost
        self.closed = (self.bld_dist < CLEAR_M) | self.reserved
        self.spot = ~((self.bld_dist < CLEAR_M) | self.road | self.rail | self.water | self.taken | self.reserved
                      | (codes == 1) | (codes == 2))
        self.sub_ok = self.spot & (codes == 0)

    def raster(self, geoms):
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

    def xy(self, i, j):
        return (j + 0.5) * GRID_M - HALF_M, (i + 0.5) * GRID_M - HALF_M

    def graph(self):
        n = self.n
        idx = np.arange(n * n).reshape(n, n)
        open_ = ~self.closed
        rows, cols, w = [], [], []
        for di, dj in ((0, 1), (1, 0), (1, 1), (1, -1)):
            a = idx[0:n - di, max(0, -dj):n - max(0, dj)]
            b = idx[di:n, max(0, dj):n + min(0, dj)]
            oa = open_.ravel()[a.ravel()]
            ob = open_.ravel()[b.ravel()]
            ok = oa & ob
            ca = self.cost.ravel()[a.ravel()][ok]
            cb = self.cost.ravel()[b.ravel()][ok]
            step = np.hypot(di, dj) * GRID_M
            rows.append(a.ravel()[ok])
            cols.append(b.ravel()[ok])
            w.append((ca + cb) * 0.5 * step)
        rows, cols, w = np.concatenate(rows), np.concatenate(cols), np.concatenate(w)
        return sparse.csr_matrix((np.concatenate([w, w]), (np.concatenate([rows, cols]), np.concatenate([cols, rows]))),
                                 shape=(n * n, n * n))

    def clear_span(self, a, b):
        """No building under the straight span a-b (sampled every 3 m)."""
        n = max(2, int(np.hypot(b[0] - a[0], b[1] - a[1]) / 3.0))
        xs = np.linspace(a[0], b[0], n)
        ys = np.linspace(a[1], b[1], n)
        i, j = self.ij(xs, ys)
        return not self.bld[i, j].any()

    def spot_ok(self, x, y):
        i, j = self.ij([x - 4, x + 4, x - 4, x + 4, x], [y - 4, y - 4, y + 4, y + 4, y])
        return bool(self.spot[i, j].all())


def substation_site(site, G, anchor, taken):
    """The nearest free SUB_SIZE_M rectangle to the anchor (searched on a
    20 m ring grid out to 600 m), turned to the nearest road, with a road
    within 60 m for its gate. Returns (polygon, frame) or None."""
    ax, ay = anchor
    w, h = SUB_SIZE_M
    lay = site.full_layout or {"roads": site.roads}
    road_geoms = [g for g, *_, kind, _ in lay["roads"] if g is not None and not kind.startswith("rail:")]
    road_tree = STRtree(road_geoms)
    cands = []
    for r in np.arange(0.0, 600.0, 20.0):
        for a in np.linspace(0, 2 * np.pi, max(1, int(2 * np.pi * r / 20.0)), endpoint=False):
            cands.append((ax + np.cos(a) * r, ay + np.sin(a) * r))
    lim = PLAY_HALF_M - 150.0
    for x, y in cands:
        if abs(x) > lim or abs(y) > lim:
            continue
        probe = box(x - w / 2 - 4, y - w / 2 - 4, x + w / 2 + 4, y + w / 2 + 4)
        i, j = G.ij(np.array([probe.bounds[0], probe.bounds[2]]), np.array([probe.bounds[1], probe.bounds[3]]))
        win = ~G.sub_ok[i[0]:i[1] + 1, j[0]:j[1] + 1]
        if win.any():
            continue
        near = road_tree.query(probe.buffer(60.0))
        if not len(near):
            continue
        roads = unary_union([road_geoms[k] for k in near])
        q = nearest_points(roads, Point(x, y))[0]
        ang = float(np.degrees(np.arctan2(q.y - y, q.x - x))) + 90.0
        rect = kit.Frame(Point(x, y).buffer(1.0), ang=ang).rect(-w / 2, -h / 2, w / 2, h / 2)
        if any(rect.buffer(30.0).intersects(t) for t in taken):
            continue
        if not site.is_free(rect, 3.0, districts=False):
            continue
        return rect, kit.Frame(rect, ang=ang)
    return None


def route(G, graph, start_cells, goal_cell):
    """The cheapest path from goal_cell to any of start_cells (cells as flat
    indices): a list of points (metres) from the chosen start to the goal."""
    dist, pred = dijkstra(graph, directed=False, indices=goal_cell, return_predecessors=True)
    starts = [c for c in start_cells if np.isfinite(dist[c])]
    if not starts:
        return None
    s = min(starts, key=lambda c: dist[c])
    path = []
    c = s
    while c >= 0 and c != goal_cell:
        path.append(c)
        c = pred[c]
    path.append(goal_cell)
    return [G.xy(c // G.n, c % G.n) for c in path]


def towers_along(G, path, start, end):
    """Tower spots along a path from start to end (both points kept): each
    next one the farthest path point within SPAN_M[1] (preferring at least
    SPAN_M[0]) with a clear span and a free foot, else the farthest such
    point past 30 m. None when the path cannot be spanned."""
    pts = [start] + list(path) + [end]
    out = [start]
    k = 0
    while True:
        cur = out[-1]
        if np.hypot(end[0] - cur[0], end[1] - cur[1]) <= SPAN_M[1] and G.clear_span(cur, end):
            out.append(end)
            break
        best = None
        for m in range(len(pts) - 2, k, -1):
            p = pts[m]
            span = np.hypot(p[0] - cur[0], p[1] - cur[1])
            if span > SPAN_M[1] or span < MIN_SPAN_M:
                continue
            if G.spot_ok(*p) and G.clear_span(cur, p):
                best = (m, span)
                break
        if best is None:
            for m in range(k + 1, len(pts) - 1):
                p = pts[m]
                if G.spot_ok(*p) and np.hypot(p[0] - cur[0], p[1] - cur[1]) > 30 and G.clear_span(cur, p):
                    best = (m, 0)
            if best is None:
                return None
        k = best[0]
        out.append(pts[k])
        if len(out) > 200:
            break
    return out


class Sub:
    def __init__(self, name, rect, F):
        self.name, self.rect, self.F = name, rect, F
        self.ends = []

    def gantry_point(self, toward):
        """The entry gantry for a new line on the yard's short side facing
        toward: (beam middle, (side, slot)); two slots per side."""
        F = self.F
        u, _ = F.to_local(*toward)
        side = 1 if u > 0 else -1
        used = [sl for (sd, sl), _ in self.ends if sd == side]
        slot = 0 if 0 not in used else 1
        return F.pt(side * (F.w / 2 - 4.0), GANTRY_W[slot]), (side, slot)


def build(site, stats):
    S = stats.setdefault("power", {})
    G = Grid(site)
    taken = []
    subs = {}
    given = getattr(site, "infra_subs", {})
    for name in sorted(SUBSTATIONS):
        if name in given:
            rect = given[name]
            F = kit.Frame(rect)
        else:
            got = substation_site(site, G, SUBSTATIONS[name], taken)
            if got is None:
                continue
            rect, F = got
        taken.append(rect)
        subs[name] = Sub(name, rect, F)
        site.claim(rect.buffer(2.0), "infra:substation")
        i0, j0 = G.ij(rect.bounds[0] - 5, rect.bounds[1] - 5)
        i1, j1 = G.ij(rect.bounds[2] + 5, rect.bounds[3] + 5)
        G.spot[i0:i1 + 1, j0:j1 + 1] = False
        G.sub_ok[i0:i1 + 1, j0:j1 + 1] = False
    graph = G.graph()
    lines = []
    failed = []
    for srcs, dst in LINES:
        if dst not in subs:
            failed.append([str(srcs), dst, "no substation"])
            continue
        alts = srcs if isinstance(srcs, tuple) and isinstance(srcs[0], tuple) else (srcs,)
        for src in alts:
            got = connect(site, G, graph, subs, src, dst, failed)
            if got is not None:
                lines.append(got)
                break
    n_towers = 0
    lengths = []
    for kind, T, D, A in lines:
        n_towers += build_line(site, T, A, D)
        lengths.append(round(sum(np.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(T[:-1], T[1:]))))
    for sub in subs.values():
        build_substation(site, sub, S)
    S.update({"failed": failed, "substations": len(subs), "lines": len(lines), "towers": n_towers, "line_m": lengths,
              "substation_at": {k: [round(v.rect.centroid.x), round(v.rect.centroid.y)] for k, v in sorted(subs.items())},
              "line_points": [[[round(x), round(y)] for x, y in T] for _, T, _, _ in lines]})


def connect(site, G, graph, subs, src, dst, failed):
    """Routes one line to substation dst from src (a map edge range or a
    substation name) and places its towers along it. Returns (kind, tower
    points, dst substation, src substation or None), or None."""
    D = subs[dst]
    if isinstance(src, tuple):
        edge, a0, a1 = src
        if edge in ("north", "south"):
            i = 0 if edge == "north" else G.n - 1
            j0, j1 = G.ij(np.array([a0, a1]), np.array([0.0, 0.0]))[1]
            starts = [i * G.n + j for j in range(j0, j1 + 1)]
        else:
            j = 0 if edge == "west" else G.n - 1
            i0, i1 = G.ij(np.array([0.0, 0.0]), np.array([a0, a1]))[0]
            starts = [i * G.n + j for i in range(i0, i1 + 1)]
        gx, gy = D.rect.centroid.x, D.rect.centroid.y
        path = route(G, graph, starts, int(G.ij(gx, gy)[0] * G.n + G.ij(gx, gy)[1]))
        if path is None:
            failed.append([str(src), dst, "no path"])
            return None
        first = path[0]
        start = {"north": (first[0], -HALF_M + 2.0), "south": (first[0], HALF_M - 2.0),
                 "west": (-HALF_M + 2.0, first[1]), "east": (HALF_M - 2.0, first[1])}[edge]
        end, side = D.gantry_point(path[-min(len(path), 8)])
        path = [p for p in path if not D.rect.buffer(25.0).contains(Point(p))]
        T = towers_along(G, path, start, end)
        if T is None:
            failed.append([str(src), dst, "no spans"])
            return None
        D.ends.append((side, T[-2] if len(T) > 1 else start))
        return ("edge", T, D, None)
    else:
        if src not in subs:
            return None
        A = subs[src]
        gx, gy = A.rect.centroid.x, A.rect.centroid.y
        hx, hy = D.rect.centroid.x, D.rect.centroid.y
        path = route(G, graph, [int(G.ij(hx, hy)[0] * G.n + G.ij(hx, hy)[1])],
                     int(G.ij(gx, gy)[0] * G.n + G.ij(gx, gy)[1]))
        if path is None:
            failed.append([str(src), dst, "no path"])
            return None
        path = path[::-1]
        start, sa = A.gantry_point(path[min(len(path) - 1, 8)])
        end, sd = D.gantry_point(path[-min(len(path), 8)])
        path = [p for p in path if not A.rect.buffer(25.0).contains(Point(p))
                and not D.rect.buffer(25.0).contains(Point(p))]
        T = towers_along(G, path, start, end)
        if T is None:
            failed.append([str(src), dst, "no spans"])
            return None
        A.ends.append((sa, T[1] if len(T) > 2 else end))
        D.ends.append((sd, T[-2] if len(T) > 2 else start))
        return ("link", T, D, A)


def build_line(site, T, A, D):
    """Towers at T[1:-1] (T[0] is substation A's gantry or the map edge,
    where a tower stands too, and T[-1] substation D's gantry), and the
    wires along the whole line. Returns the number of towers in the play
    area's frame (the edge tower not counted)."""
    towers = []
    edge_start = max(abs(T[0][0]), abs(T[0][1])) > HALF_M - 5.0
    if edge_start and len(T) > 1:
        d = np.asarray(T[1]) - np.asarray(T[0])
        towers.append((float(T[0][0]), float(T[0][1]), float(np.arctan2(d[1], d[0]))))
    for k in range(1, len(T) - 1):
        a, p, b = np.asarray(T[k - 1]), np.asarray(T[k]), np.asarray(T[k + 1])
        d0 = (p - a) / max(np.hypot(*(p - a)), 1e-9)
        d1 = (b - p) / max(np.hypot(*(b - p)), 1e-9)
        bis = d0 + d1
        if np.hypot(*bis) < 1e-6:
            bis = d0
        ang = float(np.arctan2(bis[1], bis[0]))
        towers.append((float(p[0]), float(p[1]), ang))
    feet = []
    for x, y, ang in towers:
        if abs(x) < PLAY_HALF_M - 5 and abs(y) < PLAY_HALF_M - 5:
            foot = rk.rect_at(x, y, ang, 2 * TOWER_BASE_M + 0.6, 2 * TOWER_BASE_M + 0.6)
            if site.in_window(foot.buffer(30)):
                site.obstacles.add(PIPE, foot)
                feet.append(foot)
    rk.clear_touching(site, feet)
    site.solid_extra += feet
    if len(T) > 1:
        site.claim(unary_union([LineString(T).buffer(SPAN_CLAIM_M)] + [Point(x, y).buffer(12.0) for x, y, _ in towers]),
                   "infra:pylons")

    def draw(L):
        ends = []
        for x, y, ang in towers:
            if not site.in_window(Point(x, y).buffer(400)):
                ends.append(None)
                continue
            ins = rk.lattice_tower(L, x, y, ang, TOWER_H_M, ARM_H_M, list(ARM_HALF_M), TOWER_BASE_M,
                                   foot=abs(x) < HALF_M - 4 and abs(y) < HALF_M - 4)
            ends.append((ins, (x, y, TOWER_H_M + 1.2)))
        for k in range(len(ends) - 1):
            if ends[k] is None or ends[k + 1] is None:
                continue
            (ia, pa), (ib, pb) = ends[k], ends[k + 1]
            for arm_a, arm_b in zip(ia, ib):
                for (xa, ya, ha), (xb, yb, hb) in zip(arm_a, arm_b):
                    rk.wire(L, (xa, ya), (xb, yb), ha, hb, 0.12, 0.38)
            rk.wire(L, pa[:2], pb[:2], pa[2], pb[2], 0.08, 0.34)
        if ends and ends[0] is not None:
            ia, pa = ends[0]
            if edge_start:
                _, _, a0 = towers[0]
                o = np.array([-np.cos(a0), -np.sin(a0)])
                for arm in ia:
                    for xa, ya, ha in arm:
                        t = min([(np.sign(oi) * HALF_M - pi) / oi for pi, oi in ((xa, o[0]), (ya, o[1]))
                                 if abs(oi) > 1e-6] + [300.0])
                        if t > 0.5:
                            rk.wire(L, (xa, ya), (xa + o[0] * t, ya + o[1] * t), ha, ha, 0.12, 0.38)
            else:
                gantry_wires(L, T[0], ia, (-np.sin(A.F.rad), np.cos(A.F.rad)))
        if ends and ends[-1] is not None:
            gantry_wires(L, T[-1], ends[-1][0], (-np.sin(D.F.rad), np.cos(D.F.rad)))
    site.drawers.append(draw)
    return len(towers) - (1 if edge_start else 0)


def gantry_wires(L, g, insulators, across):
    """The wires from a tower's arms down to a substation's entry gantry
    beam at GANTRY_H_M (beam middle g, unit vector `across` along it)."""
    pts = [p for arm in insulators for p in arm]
    gx, gy = g
    ax, ay = across
    for (xa, ya, ha) in pts:
        off = float(np.clip((xa - gx) * ax + (ya - gy) * ay, -6.0, 6.0))
        rk.wire(L, (xa, ya), (gx + ax * off, gy + ay * off), ha, GANTRY_H_M - 0.5, 0.12, 0.42)


def build_substation(site, sub, S):
    """The yard (local frame: u along the long side, w across): gravel, a
    double fence with a gate, an entry gantry per incoming line on the short
    sides, four busbar portals carrying three busbars down the middle, a
    row of breaker bays under them, transformers on one side, a control
    building and its cable trenches on the other."""
    F, rect = sub.F, sub.rect
    if not site.in_window(rect):
        return
    rng = block_rng(709, rect)
    site.remove_buildings_touching(rect, ("house",), 2.0)
    site.clear_area(rect.buffer(2.0))
    hw, hh = F.w / 2, F.h / 2
    house = F.rect(-7.0, hh - 11.0, 7.0, hh - 3.0)
    b = bl.Building(house, 0.2, "control")
    b.opts["stage"] = "infra"
    site.buildings.append(b)
    n_tr = 3 if rng.random() < 0.65 else 2
    trafo_w = min(-hh + 9.0, -(PORTAL_W_M + 0.6 + 1.0 + 3.2))
    trafos = [(u, trafo_w) for u in np.linspace(-hw + 18.0, hw - 15.0, n_tr)]
    feet = []
    for u, w in trafos:
        foot = F.rect(u - 4.4, w - 3.2, u + 4.4, w + 3.2)
        site.obstacles.add(PIPE, foot)
        feet.append(foot)
        x, y = F.pt(u, w)
        site.salvage.add("transformer", x, y, F.rad, 9.4, 7.0)
    bays = list(np.linspace(-hw + 14.0, hw - 12.0, 5))
    n_sw = 0
    for k, u in enumerate(bays):
        if k % 2 == 0:
            x, y = F.pt(u, 1.0)
            n_sw += site.salvage.add("switchgear", x, y, F.rad, 5.0, 6.0)
    cab = F.pt(-10.0, hh - 6.0)
    site.salvage.add("control_cabinet", cab[0], cab[1], F.rad, 3.2, 1.6)
    drum = F.pt(hw - 7.0, hh - 6.0)
    site.salvage.add("cable_drum", drum[0], drum[1], F.rad, 3.1, 2.3)
    gate = kit.nearest_edge_point(rect, rk.full_roads_near(site, rect, 80.0), rect.exterior.interpolate(0))
    ends = list(sub.ends)
    seed = int(rng.integers(1 << 30))
    site.solid_extra.append(rect)
    S["transformers"] = S.get("transformers", 0) + len(trafos)
    S["switchgear"] = S.get("switchgear", 0) + n_sw
    portals = list(np.linspace(-hw + 10.0, hw - 10.0, 4))
    bus_w = (-2.2, 0.0, 2.2)

    yard = rect.difference(unary_union([house] + feet))

    def draw(L):
        r = np.random.default_rng(seed)
        kit.pave(L, yard, 0.21, 0.9, sub="groundlines")
        for ug in np.arange(F.x0 + 1.0, F.x1, 1.4):
            L.line("groundlines", F.line([(ug, F.y0), (ug, F.y1)]).intersection(yard), 0.04, 0.14, 0.45)
        kit.fence(L, rect.exterior, r, gate=gate, v=0.38, post_every=2.0)
        kit.fence(L, rect.buffer(1.4, join_style="mitre").exterior, r, gate=gate, v=0.3, post_every=3.0)
        for u, w in trafos:
            big_transformer(L, F, u, w, r)
            L.line("groundlines", F.line([(u, w + 3.4), (u, hh - 14.0), (0.0, hh - 14.0), (0.0, hh - 11.0)]), 0.7, 0.1,
                   0.8)
        for u in bays:
            breaker_bay(L, F, u, 0.0)
        for u in portals:
            for w in (-PORTAL_W_M, PORTAL_W_M):
                x, y = F.pt(u, w)
                L.fill("interiors", Point(x, y).buffer(0.6, quad_segs=2), 0.3)
                L.tall_post(x, y, 0.45, 0.0, BUS_H_M + 1.0, 0.3, 0.4, ang=F.ang)
            L.tall_span(F.pt(u, -7.0), F.pt(u, 7.0), 0.6, BUS_H_M + 1.0, BUS_H_M + 1.0, 0.4)
        for w in bus_w:
            L.tall_span(F.pt(portals[0] - 3.0, w), F.pt(portals[-1] + 3.0, w), 0.25, BUS_H_M, BUS_H_M, 0.46)
        for u, w in trafos:
            for k, bw in enumerate(bus_w):
                rk.wire(L, F.pt(u - 1.5 + 1.5 * k, w + 0.6), F.pt(u - 1.5 + 1.5 * k, bw), 3.6, BUS_H_M, 0.1, 0.42)
        for (side, slot), _ in ends:
            u = side * (hw - 4.0)
            gw = GANTRY_W[slot]
            for dw in (-6.0, 6.0):
                x, y = F.pt(u, gw + dw)
                L.fill("interiors", Point(x, y).buffer(0.7, quad_segs=2), 0.3)
                L.tall_post(x, y, 0.55, 0.0, GANTRY_H_M, 0.3, 0.42, ang=F.ang)
            L.tall_span(F.pt(u, gw - 6.6), F.pt(u, gw + 6.6), 0.7, GANTRY_H_M, GANTRY_H_M, 0.42)
            end_u = portals[-1] + 3.0 if side > 0 else portals[0] - 3.0
            for k, bw in enumerate(bus_w):
                rk.wire(L, F.pt(u, gw + (k - 1) * 4.0), F.pt(end_u, bw), GANTRY_H_M - 0.5, BUS_H_M, 0.1, 0.42)
        equipment.place(L, "control_cabinet", cab[0], cab[1], F.rad, r)
        equipment.place(L, "cable_drum", drum[0], drum[1], F.rad, r)
    site.drawers.append(draw)


def big_transformer(L, F, u, w, rng):
    """A power transformer seen from above: tank, radiator banks each side,
    a conservator drum and three high-voltage bushings, on a concrete pad
    the size of its foot (the yard's gravel stops at the pad)."""
    sub = "interiors"
    pad = F.rect(u - 4.4, w - 3.2, u + 4.4, w + 3.2)
    L.fill(sub, pad, 0.2)
    L.line(sub, pad.exterior, 0.1, 0.3, 0.7)
    L.fill(sub, F.rect(u - 4.0, w - 2.6, u + 4.4, w + 3.4), 0.0, 0.4)
    for side in (-1, 1):
        for k in np.arange(-3.4, 3.5, 0.5):
            L.fill(sub, F.rect(u + k - 0.15, w + side * 1.9, u + k + 0.15, w + side * 2.9), 0.26)
    L.fill(sub, F.rect(u - 3.6, w - 1.8, u + 3.6, w + 1.8), 0.22)
    L.line(sub, F.rect(u - 3.6, w - 1.8, u + 3.6, w + 1.8).exterior, 0.08, 0.42)
    L.fill(sub, F.rect(u - 3.0, w - 1.6, u + 3.0, w - 0.9), 0.3)
    for k in (-1.5, 0.0, 1.5):
        x, y = F.pt(u + k, w + 0.6)
        L.fill(sub, Point(x, y).buffer(0.45, quad_segs=3), 0.4)
        L.fill(sub, Point(x, y).buffer(0.18, quad_segs=2), 0.12)


def breaker_bay(L, F, u, w):
    sub = "interiors"
    for k in (-1.5, 0.0, 1.5):
        L.fill(sub, F.rect(u - 1.0 + k * 0.0 - 0.4, w + k - 0.4, u - 1.0 + 0.4, w + k + 0.4), 0.3)
        L.fill(sub, F.rect(u + 0.6, w + k - 0.3, u + 1.6, w + k + 0.3), 0.24)
        L.line(sub, F.line([(u - 1.0, w + k), (u + 1.6, w + k)]), 0.06, 0.4)
    L.line(sub, F.rect(u - 2.0, w - 2.2, u + 2.4, w + 2.2).exterior, 0.06, 0.3, 0.7)
