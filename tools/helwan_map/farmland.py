"""Farmland district content (section 5 of the districts brief). Nothing
grows: flat land with old furrows, partly covered by drift.

1. The farmland areas (the district's cells, less roads, water and
   buildings) are first cut by natural boundaries: OSM canals, streams and
   ditches, plus a frozen canal along each large area (CANAL_MIN_AREA_M2)
   and a burn (a small frozen stream) or two across it.
2. Field splitting (from Yosqi's Kirkliston reference aerial), per piece:
   - its minimum turned rectangle's long side gives the long axis;
   - stop when the piece is smaller than its size goal (a random 0.55 to 1.7
     x FIELD_TARGET_M2, drawn again for each piece) and its aspect is below
     ASPECT_MAX; also stop below MIN_FIELD_M2 x 1.9, or at depth MAX_DEPTH;
   - else cut across the long axis at the middle +/- 12% of the length, the
     cut square to the long axis +/- 8 degrees;
   - reject a cut that makes a piece under MIN_FIELD_M2 (try again a few
     times, then keep the piece whole).
   After splitting, 2 neighbour pairs along a long shared edge merge into L
   shapes (a merged field stays under MERGE_MAX_M2).
3. Field detail: furrows along each field's long axis (TURNED_SHARE of the
   fields turned 90 degrees), broken where drift covers them; tramlines
   (pairs of wheel tracks) every 18 to 22 m; earth bunds or ditches between
   fields; hedgerow husks (bare tree props) on long edges (over 35 m) of
   HEDGE_SHARE of the fields, away from tracks and compounds.
4. Tree husks round the edge of the farmland and along canals and tracks.
5. Frozen canals with pump houses on the bank (an industrial_pump source
   beside each).
6. Farmhouse compounds (one per FARMHOUSE_EVERY_M2 of farmland): a walled
   yard with a gate, a house, a pitched-roof barn, a round dovecote tower,
   animal pens (low walls only), a well and a derelict tractor (a tractor
   source); sometimes a diesel generator and oil drums.
7. A fenced solar ground array now and then (SOLAR_ARRAY_EVERY_M2), and a few
   derelict tractors out in the fields.
"""
import cv2
import numpy as np
from scipy import ndimage as ndi
from shapely import affinity, contains_xy
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import split as shp_split, substring, unary_union

import buildings as bl
import equipment
import kit
import solar
import style
from districts import CELL_M, FARMLAND
from gen_city import block_rng, to_frame_m
from pipes import fillet

FIELD_TARGET_M2 = 5000.0
GOAL_RANGE = (0.55, 1.7)
ASPECT_MAX = 2.1
MIN_FIELD_M2 = 1800.0
MAX_DEPTH = 12
CUT_JITTER = 0.12
CUT_ANGLE_DEG = 8.0
MERGE_PAIRS = 2
MERGE_MAX_M2 = 11000.0
TURNED_SHARE = 0.25
HEDGE_SHARE = 0.3
## Share of the plain field edges (not ditches) that get a low mud wall.
WALL_SHARE = 0.3
HEDGE_MIN_EDGE_M = 35.0
TRAMLINES_M = (18.0, 22.0)
FURROW_M = 1.4
CANAL_MIN_AREA_M2 = 60000.0
CANAL_W_M = (6.0, 8.0)
BURN_W_M = (2.0, 3.0)
PUMP_EVERY_M = 320.0
FARMHOUSE_EVERY_M2 = 50000.0
## Spots tried for each farmyard on its region's edge.
FARMHOUSE_TRIES = 30
SOLAR_ARRAY_EVERY_M2 = 400000.0
## Fields looked at per solar array (the largest ones).
ARRAY_CHOICE = 6
FIELD_TRACTORS_PER_KM2 = 6.0
WATERWAYS = {"canal", "stream", "ditch", "drain", "river"}


# --------------------------------------------------------------- splitting

def long_axis(poly):
    rr = np.asarray(poly.minimum_rotated_rectangle.exterior.coords)
    e1, e2 = rr[1] - rr[0], rr[2] - rr[1]
    l1, l2 = np.hypot(*e1), np.hypot(*e2)
    if l1 >= l2:
        return e1 / max(l1, 1e-9), l1, l2
    return e2 / max(l2, 1e-9), l2, l1


def split_field(piece, rng, depth=0):
    """The brief's field splitting, recursively."""
    u, length, width = long_axis(piece)
    aspect = length / max(width, 1e-6)
    goal = rng.uniform(*GOAL_RANGE) * FIELD_TARGET_M2
    if (piece.area < goal and aspect < ASPECT_MAX) or piece.area < MIN_FIELD_M2 * 1.9 or depth >= MAX_DEPTH:
        return [piece]
    rr = piece.minimum_rotated_rectangle.centroid
    for _ in range(6):
        t = rng.uniform(-CUT_JITTER, CUT_JITTER) * length
        ang = np.radians(rng.uniform(-CUT_ANGLE_DEG, CUT_ANGLE_DEG))
        n = np.array([-u[1], u[0]])
        n = np.array([n[0] * np.cos(ang) - n[1] * np.sin(ang), n[0] * np.sin(ang) + n[1] * np.cos(ang)])
        cx, cy = rr.x + u[0] * t, rr.y + u[1] * t
        far = length + width
        cut = LineString([(cx - n[0] * far, cy - n[1] * far), (cx + n[0] * far, cy + n[1] * far)])
        parts = [g for g in shp_split(piece, cut).geoms if g.geom_type == "Polygon"]
        if len(parts) < 2 or any(p.area < MIN_FIELD_M2 for p in parts):
            continue
        out = []
        for p in parts:
            out += split_field(p, rng, depth + 1)
        return out
    return [piece]


def merge_pairs(fields, rng, pairs=MERGE_PAIRS):
    """Merges up to `pairs` neighbour pairs along a long shared edge into L
    shapes."""
    fields = list(fields)
    cands = []
    for i in range(len(fields)):
        for j in range(i + 1, len(fields)):
            a, b = fields[i], fields[j]
            if not a.buffer(0.3).intersects(b):
                continue
            shared = a.buffer(0.3).intersection(b.boundary).length
            if shared < 20 or a.area + b.area > MERGE_MAX_M2:
                continue
            cands.append((shared, i, j))
    cands.sort(reverse=True)
    used, merged = set(), []
    for shared, i, j in cands:
        if len(merged) >= pairs or i in used or j in used:
            continue
        u = unary_union([fields[i].buffer(0.2), fields[j].buffer(0.2)]).buffer(-0.2)
        if u.geom_type != "Polygon":
            continue
        used |= {i, j}
        merged.append(u)
    return [f for k, f in enumerate(fields) if k not in used] + merged


# ---------------------------------------------------------------- drawing

def furrows(L, field, ang_deg, rng, drift):
    """Furrow lines along ang_deg over a field, broken where drift covers
    them, plus tramlines (pairs of wheel tracks)."""
    F = kit.Frame(field, ang_deg)
    tram = rng.uniform(*TRAMLINES_M)
    y = F.y0 + rng.uniform(0.3, FURROW_M)
    tram_next = F.y0 + rng.uniform(4, tram)
    Q = solar.Quads(F.c, F.ang)
    while y < F.y1:
        is_tram = y >= tram_next
        if is_tram:
            tram_next += tram
        seg = F.line([(F.x0 - 1, y), (F.x1 + 1, y)]).intersection(field)
        for part in getattr(seg, "geoms", [seg]):
            if part.geom_type != "LineString" or part.length < 2:
                continue
            ax, ay = F.to_local(*part.coords[0])
            bx, by = F.to_local(*part.coords[-1])
            xa, xb = min(ax, bx), max(ax, bx)
            x = xa
            while x < xb:
                run = rng.uniform(6, 30)
                xe = min(x + run, xb)
                cover = drift(*F.pt((x + xe) / 2, y))
                if cover < 0.7:
                    a = 0.45 * (1 - cover)
                    if is_tram:
                        Q.line(x, y - 0.9, xe, y - 0.9, 0.45, 0.06, a)
                        Q.line(x, y + 0.9, xe, y + 0.9, 0.45, 0.06, a)
                    else:
                        Q.line(x, y, xe, y, 0.28, 0.05, a)
                        Q.line(x, y + 0.3, xe, y + 0.3, 0.12, 0.3, a * 0.6)
                x = xe + rng.uniform(0.0, 6.0)
        y += FURROW_M
    Q.flush(L, "groundlines", None)


def canal(L, axis, width, rng):
    """A frozen canal: earth banks, grey ice, cracks."""
    bank = axis.buffer(width / 2 + 1.6, cap_style="flat")
    ice = axis.buffer(width / 2, cap_style="flat")
    L.fill("groundlines", bank, 0.2, 0.9)
    L.fill("groundlines", ice, 0.12)
    for g in style.polys(ice):
        L.strip("groundlines", style.orient(g, 1.0).exterior, 1.0, +1, 0.5, 0.0)
    for d in np.arange(rng.uniform(0, 8), axis.length, rng.uniform(6, 12)):
        p = axis.interpolate(d)
        a = rng.uniform(0, np.pi)
        crack = LineString([(p.x - np.cos(a) * width, p.y - np.sin(a) * width),
                            (p.x + np.cos(a) * width, p.y + np.sin(a) * width)]).intersection(ice)
        L.line("groundlines", crack, 0.05, 0.22, 0.8)


def array_ground(field, cell=1.0):
    """The ground for a solar array in a field, and the angle of its rows:
    the largest rectangle along the field's long axis that lies 1 m inside
    the field (the array's fence reaches 0.6 m past the box it is given),
    or None. The field is sampled on a grid of cells in its own frame; a
    cell counts when its middle is 1 m plus half its diagonal inside, and
    the rectangle is the largest block of such cells."""
    ang, _ = style.frame_of(field)
    F = kit.Frame(field, ang)
    room = field.buffer(-(1.0 + cell * 0.71))
    if room.is_empty:
        return None
    loc = F.local(room)
    x0, y0, x1, y1 = loc.bounds
    xs = x0 + cell * (np.arange(int(np.ceil((x1 - x0) / cell))) + 0.5)
    ys = y0 + cell * (np.arange(int(np.ceil((y1 - y0) / cell))) + 0.5)
    if len(xs) == 0 or len(ys) == 0:
        return None
    gx, gy = np.meshgrid(xs, ys)
    inside = contains_xy(loc, gx, gy)
    # Largest rectangle of inside cells: per row, the run of inside cells
    # above each column is a histogram, and its largest rectangle is found
    # with a stack of rising bars.
    best, run = None, np.zeros(len(xs), int)
    for j in range(len(ys)):
        run = np.where(inside[j], run + 1, 0)
        stack = []
        for i in range(len(xs) + 1):
            h = run[i] if i < len(xs) else 0
            start = i
            while stack and stack[-1][1] >= h:
                start, sh = stack.pop()
                if best is None or sh * (i - start) > best[0]:
                    best = (sh * (i - start), start, i, j - sh + 1, j + 1)
            stack.append((start, h))
    if best is None or best[0] == 0:
        return None
    _, i0, i1, j0, j1 = best
    rect = F.rect(xs[i0] - cell / 2, ys[j0] - cell / 2, xs[i1 - 1] + cell / 2, ys[j1 - 1] + cell / 2)
    return rect, ang


def burn(L, axis, width):
    L.line("groundlines", axis, width + 1.2, 0.04, 0.6)
    L.line("groundlines", axis, width, 0.14)
    L.line("groundlines", axis, 0.12, 0.26, 0.7)


def wiggle(a, b, rng, amp, step=12.0):
    """A wiggly line from a to b (a burn's course)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = np.hypot(*(b - a))
    n = max(3, int(d // step))
    t = np.linspace(0, 1, n)
    u = (b - a) / max(d, 1e-9)
    nrm = np.array([-u[1], u[0]])
    off = np.cumsum(rng.normal(0, amp, n))
    off -= np.linspace(off[0], off[-1], n)
    pts = a[None] + t[:, None] * (b - a)[None] + off[:, None] * nrm[None]
    return LineString(fillet(pts, step * 0.6))


def roof_dovecote(L, b, rng):
    """A round dovecote tower: a domed top with rings of nesting holes."""
    g = b.poly
    key = style.chunk_key(g)
    c = g.centroid
    r = np.sqrt(g.area / np.pi)
    L.fill("roofs", g, 0.17, chunk=key)
    for k, rr in enumerate((0.8, 0.55, 0.3)):
        ring = kit.disc(c.x, c.y, r * rr, 20)
        L.fill("roofs", ring, 0.17 + 0.03 * k, chunk=key)
        n = int(18 * rr) + 4
        for i in range(n):
            a = 2 * np.pi * (i + 0.5 * k) / n
            L.fill("roofs", kit.disc(c.x + np.cos(a) * r * (rr + 0.08), c.y + np.sin(a) * r * (rr + 0.08), 0.13, 6),
                   0.02, chunk=key)
    L.line("roofs", g.exterior, style.OUTLINE_W, style.OUTLINE_V, chunk=key)
    return None


def roof_barn(L, b, rng):
    shape, rects, ang, c = style.roof_shape(b.poly)
    if shape is None:
        return style.draw_house(L, b.poly, b.mv, rng, items=False)
    style.draw_sheet_shed(L, b.poly, b.mv, rng, rects, ang, c)
    return None


def roof_farmhouse(L, b, rng):
    shape, rects, ang, c = style.roof_shape(b.poly)
    if shape is not None and b.state != bl.GUTTED and rng.random() < 0.6:
        style.draw_tiled_house(L, b.poly, b.mv, rng, rects, ang, c)
        return None
    return style.draw_house(L, b.poly, b.mv, rng, items=b.state != bl.GUTTED)


bl.KINDS.update({
    "dovecote": (roof_dovecote, False, 2.0),
    "barn": (roof_barn, True, style.HALO_BIG_M),
    "farmhouse": (roof_farmhouse, False, style.HALO_HOUSE_M),
})


# --------------------------------------------------------------- regions

def farmland_polys(site):
    """The farmland district as polygons (metres), less roads, water and
    buildings."""
    D = site.districts
    mask = (D.codes == FARMLAND).astype(np.uint8)
    cs, hier = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    polys = []
    if hier is not None:
        for i, c in enumerate(cs):
            if hier[0][i][3] != -1 or len(c) < 3:
                continue
            shell = c[:, 0, :] * CELL_M - D.half_m
            holes = []
            ch = hier[0][i][2]
            while ch != -1:
                if len(cs[ch]) >= 3:
                    holes.append(cs[ch][:, 0, :] * CELL_M - D.half_m)
                ch = hier[0][ch][0]
            p = Polygon(shell, holes).buffer(CELL_M / 2, join_style="mitre").buffer(-CELL_M / 2)
            if not p.is_empty:
                polys.append(p)
    if not polys:
        return Polygon()
    area = unary_union(polys).buffer(8).buffer(-8)
    roads = unary_union([g.buffer(2.0) for g, *_, kind, _ in site.roads if not kind.startswith("rail:")])
    blocked = unary_union([roads, site.water.buffer(4.0)] +
                          [b.poly.buffer(5.0) for b in site.buildings if b.poly.intersects(area)])
    return area.difference(blocked).buffer(-0.5).buffer(0.5)


def osm_waterways(site, area):
    out = []
    for kind, rings, p in getattr(site, "feats", None) or []:
        if kind == "line" and p.get("waterway") in WATERWAYS:
            line = LineString(to_frame_m(rings[0]))
            if line.intersects(area):
                out.append((line.intersection(area.buffer(5)), p["waterway"]))
    return out


def build(site):
    rng = np.random.default_rng(59)
    area = farmland_polys(site)
    regions = [g for g in style.polys(area) if g.area > 4000]
    total = sum(g.area for g in regions)
    drift_noise = rng.standard_normal((64, 64))
    drift_noise = ndi.gaussian_filter(drift_noise, 3, mode="wrap")
    drift_noise = (drift_noise - drift_noise.mean()) / drift_noise.std()

    def drift(x, y):
        i, j = int((y / 40.0) % 64), int((x / 40.0) % 64)
        return float(np.clip(drift_noise[i, j] * 0.6 + 0.1, 0, 1))

    canals, burns, fields, compounds = [], [], [], []
    for reg in regions:
        rrng = block_rng(61, reg)
        cuts = []
        for line, kind in osm_waterways(site, reg):
            w = rrng.uniform(*CANAL_W_M) if kind in ("canal", "river") else rrng.uniform(*BURN_W_M)
            (canals if kind in ("canal", "river") else burns).append((line, w))
            cuts.append(line.buffer(w / 2 + 2.0))
        if reg.area > CANAL_MIN_AREA_M2:
            F = kit.Frame(reg)
            yc = rrng.uniform(-0.2, 0.2) * F.h
            pts = [(F.x0 - 5, yc)]
            for x in np.linspace(F.x0, F.x1, 5)[1:-1]:
                pts.append((x, yc + rrng.uniform(-0.06, 0.06) * F.h))
            pts.append((F.x1 + 5, yc))
            axis = LineString(fillet(F.pts(pts), 30.0)).intersection(reg)
            for part in getattr(axis, "geoms", [axis]):
                if part.geom_type == "LineString" and part.length > 40:
                    w = rrng.uniform(*CANAL_W_M)
                    canals.append((part, w))
                    cuts.append(part.buffer(w / 2 + 2.0, cap_style="flat"))
            for _ in range(int(rrng.integers(1, 3))):
                a = reg.exterior.interpolate(rrng.uniform(0, 1), normalized=True)
                b = reg.exterior.interpolate(rrng.uniform(0, 1), normalized=True)
                if a.distance(b) < 80:
                    continue
                line = wiggle((a.x, a.y), (b.x, b.y), rrng, 3.0).intersection(reg)
                for part in getattr(line, "geoms", [line]):
                    if part.geom_type == "LineString" and part.length > 30:
                        w = rrng.uniform(*BURN_W_M)
                        burns.append((part, w))
                        cuts.append(part.buffer(w / 2 + 1.5))
        taken = unary_union(cuts) if cuts else None
        pieces = style.polys(reg.difference(taken)) if cuts else [reg]
        n_farms = int(reg.area // FARMHOUSE_EVERY_M2) + (1 if reg.area > FARMHOUSE_EVERY_M2 * 0.4 else 0)
        for _ in range(n_farms):
            cp = farmhouse(site, reg, pieces, rrng, taken)
            if cp is not None:
                compounds.append(cp)
                pieces = [g for p in pieces for g in style.polys(p.difference(cp.buffer(3.0)))]
                taken = cp.buffer(3.0) if taken is None else taken.union(cp.buffer(3.0))
        reg_fields = []
        for piece in pieces:
            if piece.area < MIN_FIELD_M2 * 0.6:
                continue
            reg_fields += split_field(piece, rrng)
        reg_fields = merge_pairs(reg_fields, rrng)
        fields += [(kit.largest(f.buffer(-0.8, join_style="mitre")), rrng.random() < TURNED_SHARE) for f in reg_fields]
        fields = [(f, t) for f, t in fields if f is not None]
    site.stats["farmland"] = {"regions": len(regions), "area_m2": round(total), "fields": len(fields),
                              "canals": len(canals), "burns": len(burns), "farmhouses": len(compounds)}

    # Pump houses keep off every canal's and burn's banks but their own and
    # off the farmyards: on the bank picked, or else on the other one.
    banks = unary_union([line.buffer(w / 2 + 1.6, cap_style="flat") for line, w in canals] +
                        [line.buffer(w / 2 + 0.6, cap_style="flat") for line, w in burns] + compounds)
    pumps, houses = [], []
    for line, w in canals:
        for d in np.arange(rng.uniform(60, 160), line.length - 20, PUMP_EVERY_M):
            p = line.interpolate(d)
            q = line.interpolate(min(d + 1, line.length))
            t = np.array([q.x - p.x, q.y - p.y])
            t /= max(np.hypot(*t), 1e-9)
            side = 1 if rng.random() < 0.5 else -1
            ang = np.degrees(np.arctan2(t[1], t[0]))
            for k, s in enumerate((side, -side)):
                nrm = np.array([-t[1], t[0]]) * s
                cx, cy = p.x + nrm[0] * (w / 2 + 4.5), p.y + nrm[1] * (w / 2 + 4.5)
                house = affinity.rotate(Polygon([(cx - 3, cy - 2.2), (cx + 3, cy - 2.2), (cx + 3, cy + 2.2),
                                                 (cx - 3, cy + 2.2)]), ang, origin=(cx, cy))
                if not area.buffer(2).contains(house):
                    if k == 0:
                        break
                    continue
                px, py = cx + t[0] * 5.2, cy + t[1] * 5.2
                if banks.intersects(house.buffer(0.3)) or banks.intersects(Point(px, py).buffer(1.5)):
                    continue
                site.buildings.append(bl.Building(house, float(site.sampler.value(cx, cy)), "pumphouse"))
                houses.append(house)
                pumps.append((px, py, float(np.arctan2(t[1], t[0]))))
                break
    pump_u = unary_union([h.buffer(0.5, join_style="mitre") for h in houses]) if houses else None

    field_geoms = [f for f, _ in fields]
    hedges = []
    tracks = site.road_union_near(area, 5.0) if not area.is_empty else None
    for f, turned in fields:
        if rng.random() > HEDGE_SHARE:
            continue
        pts = list(f.exterior.coords)
        for a, b in zip(pts[:-1], pts[1:]):
            seg = LineString([a, b])
            if seg.length < HEDGE_MIN_EDGE_M:
                continue
            if tracks is not None and seg.distance(tracks) < 8:
                continue
            if any(seg.distance(c) < 10 for c in compounds):
                continue
            hedges.append(seg)
    trees = []
    for seg in hedges:
        for d in np.arange(rng.uniform(1, 4), seg.length, rng.uniform(4, 7)):
            p = seg.interpolate(d)
            trees.append((p.x + rng.normal(0, 0.6), p.y + rng.normal(0, 0.6), rng.uniform(7, 12)))
    edge_lines = [LineString(g.exterior.coords) for g in style.polys(area)]
    edge_lines += [line for line, _ in canals]
    for line in edge_lines:
        for d in np.arange(rng.uniform(0, 10), line.length, rng.uniform(9, 16)):
            if rng.random() < 0.45:
                continue
            p = line.interpolate(d)
            trees.append((p.x + rng.normal(0, 2.0), p.y + rng.normal(0, 2.0), rng.uniform(8, 14)))
    for x, y, s in trees:
        if any(Point(x, y).within(c) for c in compounds):
            continue
        site.props.add("tree", x, y, rng.uniform(0, 2 * np.pi), (s, s))

    # Solar arrays: an array fills the box it is given, so it gets the
    # field's array_ground, not the field; of the ARRAY_CHOICE largest
    # fields per array, the ones whose array_ground is largest.
    n_arrays = int(total // SOLAR_ARRAY_EVERY_M2)
    order = sorted(range(len(field_geoms)), key=lambda i: -field_geoms[i].area)
    cands = []
    for i in order[:n_arrays * ARRAY_CHOICE]:
        got = array_ground(field_geoms[i])
        if got is not None:
            cands.append((-got[0].area, i, got))
    arrays = [(field_geoms[i], *got) for _, i, got in sorted(cands, key=lambda t: t[:2])[:n_arrays]]
    field_tractors = []
    for _ in range(int(total / 1e6 * FIELD_TRACTORS_PER_KM2)):
        if not field_geoms:
            break
        f = field_geoms[int(rng.integers(len(field_geoms)))]
        p = f.representative_point()
        field_tractors.append((p.x + rng.uniform(-5, 5), p.y + rng.uniform(-5, 5), rng.uniform(0, 2 * np.pi)))

    seed = int(rng.integers(1 << 30))

    array_at = {id(g): rect for g, rect, _ in arrays}

    def draw(L):
        r = np.random.default_rng(seed)
        for f, turned in fields:
            ang, _ = style.frame_of(f)
            if id(f) in array_at:
                f = f.difference(array_at[id(f)].buffer(3.0, join_style="mitre"))
                if f.area < 20.0:
                    continue
            if pump_u is not None and pump_u.intersects(f):
                f = f.difference(pump_u)
            L.fill("groundlines", f, r.choice([0.0, 0.3]), r.uniform(0.06, 0.16))
            furrows(L, f, ang + (90 if turned else 0), r, drift)
        seen = set()
        for i, f in enumerate(field_geoms):
            for j in range(i + 1, len(field_geoms)):
                g = field_geoms[j]
                if (i, j) in seen or f.distance(g) > 2.2:
                    continue
                seen.add((i, j))
                shared = f.buffer(1.2).intersection(g.buffer(1.2))
                if shared.is_empty or shared.area < 10:
                    continue
                strip = kit.largest(shared)
                if strip is None:
                    continue
                ditch = r.random() < 0.4
                bund = strip.buffer(0.4)
                if pump_u is not None and pump_u.intersects(bund):
                    strip, bund = strip.difference(pump_u), bund.difference(pump_u)
                L.fill("groundlines", bund, 0.0, 0.25 if not ditch else 0.4)
                L.fill("groundlines", strip, 0.03 if ditch else 0.25, 0.8)
                if not ditch and r.random() < WALL_SHARE:
                    # A low mud wall along the shared edge, with gaps.
                    edge = f.exterior.intersection(g.buffer(1.5))
                    if pump_u is not None and pump_u.intersects(edge):
                        edge = edge.difference(pump_u)
                    for part in getattr(edge, "geoms", [edge]):
                        if part.geom_type != "LineString" or part.length < 6.0:
                            continue
                        d = 0.0
                        while d < part.length:
                            run = r.uniform(6.0, 18.0)
                            seg = substring(part, d, min(d + run, part.length))
                            L.line("interiors", seg, 0.55, 0.0, 0.35)
                            L.line("interiors", seg, 0.4, 0.27)
                            d += run + r.uniform(1.5, 4.0)
        for line, w in canals:
            canal(L, line, w, r)
        for line, w in burns:
            burn(L, line, w)
        for _, rect, ang in arrays:
            got = solar.ground_array(L, rect, ang, r, None)
            if got is not None:
                bl.add_poly_source(site.salvage, "solar_panels", got[0], -1, got[1])
        for px, py, a in pumps:
            equipment.add_source(site.salvage, L, "industrial_pump", px, py, a, r)
        for x, y, a in field_tractors:
            equipment.add_source(site.salvage, L, "tractor", x, y, a, r)
    site.drawers.append(draw)
    for c in compounds:
        site.solid_extra.append(c)
    return site


def farmhouse(site, reg, pieces, rng, avoid=None):
    """A walled farmyard on the edge of a region, near a road if one is
    close, clear of avoid (the canals' and burns' banks, the other yards):
    house, barn, dovecote, pens, a well, a tractor."""
    near = site.road_union_near(reg, 10.0)
    for _ in range(FARMHOUSE_TRIES):
        p = reg.exterior.interpolate(rng.uniform(0, 1), normalized=True)
        if near is not None and p.distance(near) > 30 and rng.random() < 0.7:
            continue
        w, h = rng.uniform(32, 46), rng.uniform(26, 36)
        ang = rng.uniform(0, 180)
        c = reg.exterior.interpolate(reg.exterior.project(p))
        inward = reg.representative_point()
        dx, dy = inward.x - c.x, inward.y - c.y
        dn = max(np.hypot(dx, dy), 1e-6)
        cx, cy = c.x + dx / dn * (h / 2 + 4), c.y + dy / dn * (h / 2 + 4)
        ang = np.degrees(np.arctan2(dy, dx)) + 90
        yard = affinity.rotate(Polygon([(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2),
                                        (cx - w / 2, cy + h / 2)]), ang, origin=(cx, cy))
        if not reg.contains(yard) or (avoid is not None and avoid.intersects(yard)):
            continue
        break
    else:
        return None
    F = kit.Frame(yard, ang)
    mv = float(site.sampler.value(cx, cy))
    add = lambda poly, kind: site.buildings.append(bl.Building(poly, mv, kind))
    hx = F.x0 + 2.0
    hw = rng.uniform(9, 12)
    add(F.rect(hx, F.y0 + 2.0, hx + hw, F.y0 + 2.0 + rng.uniform(7, 9)), "farmhouse")
    bw = min(rng.uniform(15, 20), F.x1 - 2.0 - (hx + hw + 3.0))
    add(F.rect(F.x1 - 2.0 - bw, F.y0 + 2.0, F.x1 - 2.0, F.y0 + 2.0 + rng.uniform(9, 11)), "barn")
    dx_, dy_ = F.pt(F.x1 - 5.0, F.y1 - 5.0)
    add(kit.disc(dx_, dy_, rng.uniform(2.2, 2.8), 16), "dovecote")
    pens = F.rect(F.x0 + 2.0, F.y1 - 11.0, F.x0 + 2.0 + rng.uniform(12, 18), F.y1 - 2.0)
    well = F.pt((F.x0 + F.x1) / 2, (F.y0 + F.y1) / 2 + 3)
    tx, ty = F.pt((F.x0 + F.x1) / 2 + 6, F.y1 - 6)
    gate = yard.exterior.interpolate(yard.exterior.project(Point(F.pt((F.x0 + F.x1) / 2, F.y0))))
    extra = []
    if rng.random() < 0.5:
        extra.append(("diesel_generator", F.pt(F.x0 + 6, (F.y0 + F.y1) / 2 + 2)))
    if rng.random() < 0.5:
        extra.append(("oil_drums", F.pt(F.x1 - 6, (F.y0 + F.y1) / 2 + 3)))
    seed = int(rng.integers(1 << 30))

    def draw(L):
        r = np.random.default_rng(seed)
        kit.pave(L, yard, 0.17, 0.85, sub="groundlines", edge=False)
        kit.wall(L, yard.exterior, 0.45, 0.3, gate=gate)
        L.line("interiors", pens.exterior, 0.3, 0.28)
        px0, py0, px1, py1 = F.to_local(*pens.exterior.coords[0]) + F.to_local(*pens.exterior.coords[2])
        for x in np.linspace(min(px0, px1), max(px0, px1), 4)[1:-1]:
            L.line("interiors", F.line([(x, min(py0, py1)), (x, max(py0, py1))]), 0.25, 0.28)
        L.fill("interiors", kit.disc(well[0], well[1], 1.0, 14), 0.3)
        L.fill("interiors", kit.disc(well[0], well[1], 0.6, 12), 0.01)
        equipment.add_source(site.salvage, L, "tractor", tx, ty, F.rad, r)
        for kind, (x, y) in extra:
            equipment.add_source(site.salvage, L, kind, x, y, F.rad, r)
    site.drawers.append(draw)
    return yard
