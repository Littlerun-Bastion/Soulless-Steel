"""Builds the Helwan map's city layout: water, roads, rail, large roofs,
housing lots and viaduct centrelines, all in metres in the map frame
(world px / 20). style.py turns the layout into drawable meshes."""
import numpy as np
from shapely import affinity
from shapely.geometry import LineString, MultiPolygon, Polygon, box
from shapely.ops import linemerge, unary_union
from scipy import ndimage as ndi
import cv2

from frame import MAP_PX, MOCK_N, PX_PER_M, m_to_world
from zones import HOUSING, ROOF, WATER

HALF_M = MAP_PX / PX_PER_M / 2
FRAME = box(-HALF_M, -HALF_M, HALF_M, HALF_M)
# Mesh chunks about 500 m across.
CHUNKS = max(1, round(MAP_PX / PX_PER_M / 500.0))
CHUNK_M = 2 * HALF_M / CHUNKS

ROAD_WIDTH_M = {
    "trunk": 20, "trunk_link": 8, "secondary": 12, "secondary_link": 7,
    "tertiary": 9, "tertiary_link": 6, "unclassified": 6, "residential": 4.5,
    "service": 3.5, "track": 3, "path": 1.5, "construction": 6,
}
RAIL_WIDTH_M = {"rail": 8, "abandoned": 5}
VIADUCT_WIDTH_M = 10
VIADUCT_CLEARANCE_M = 3.0
ROAD_SETBACK_M = 1.0



class Sampler:
    """Reads mockup grids at positions given in map-frame metres."""

    def __init__(self, f, zone):
        self.mk = ndi.gaussian_filter(f["mk"], 0.8)
        self.zone = zone

    def _ij(self, x, y):
        k = MOCK_N / (2 * HALF_M)
        i = np.clip(((np.asarray(y) + HALF_M) * k).astype(int), 0, MOCK_N - 1)
        j = np.clip(((np.asarray(x) + HALF_M) * k).astype(int), 0, MOCK_N - 1)
        return i, j

    def value(self, x, y):
        i, j = self._ij(x, y)
        return self.mk[i, j]

    def zone_at(self, x, y):
        i, j = self._ij(x, y)
        return self.zone[i, j]


def to_frame_m(rings):
    return m_to_world(rings) / PX_PER_M


def mask_to_polys(mask, simplify_m=1.0):
    """Vectorises a mockup-grid mask into polygons in map-frame metres."""
    k = 2 * HALF_M / MOCK_N
    cs, hier = cv2.findContours(mask.astype(np.uint8), cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    polys = []
    if hier is None:
        return polys
    hier = hier[0]
    for i, c in enumerate(cs):
        if hier[i][3] != -1 or len(c) < 3:
            continue
        shell = c[:, 0, :] * k - HALF_M
        holes = []
        ch = hier[i][2]
        while ch != -1:
            if len(cs[ch]) >= 3:
                holes.append(cs[ch][:, 0, :] * k - HALF_M)
            ch = hier[ch][0]
        p = Polygon(shell, holes).buffer(0)
        if not p.is_empty:
            polys.append(p.simplify(simplify_m))
    return polys


def rng_at(seed, x, y):
    """A random generator for one place, seeded by its position (map metres,
    to 0.1 m), so a part of the map comes out the same in a window run
    (run_all.py --window) as in a full run."""
    return np.random.default_rng([seed, int((x + 100000) * 10), int((y + 100000) * 10)])


def block_rng(seed, geom):
    """rng_at for one street block or building, at its centroid."""
    c = geom.centroid
    return rng_at(seed, c.x, c.y)


def build(feats, f, zone, rects, keep_out=None, seed=7, window=None):
    """keep_out: hand-made areas (map-frame metres) where nothing is built.
    window: a box (map-frame metres); only the street blocks and large roofs
    that touch it are built (for quick previews).
    Returns water, roads, large roofs, house lots, viaduct centre lines and
    the street blocks (the land between roads and water)."""
    keep_out = keep_out if keep_out is not None else Polygon()
    smp = Sampler(f, zone)
    near = window.buffer(150) if window is not None else None

    # Water from the mockup itself, so it lines up with the macro tone.
    water_mask = ndi.binary_opening(zone == WATER, iterations=1)
    water = unary_union(mask_to_polys(water_mask, 2.0)).buffer(1.5).buffer(-1.5)
    water = water.intersection(FRAME)

    raw, viaducts = {}, []
    for kind, rings, p in feats:
        if kind != "line":
            continue
        pts = to_frame_m(rings[0])
        if len(pts) < 2:
            continue
        line = LineString(pts)
        if not line.intersects(FRAME.buffer(30)):
            continue
        if near is not None and not line.intersects(near):
            continue
        if p.get("railway") == "construction":
            viaducts.append(line)
            continue
        if p.get("highway") in ROAD_WIDTH_M:
            kind = p["highway"]
        elif p.get("railway") in RAIL_WIDTH_M:
            kind = "rail:" + p["railway"]
        else:
            continue
        raw.setdefault(kind, []).append(line)

    # Streets of one type are merged into continuous lines first, so bends are
    # mitred inside one buffer. Ends are flat: dead ends stop square.
    roads = []
    for kind, lines in raw.items():
        w = RAIL_WIDTH_M[kind[5:]] if kind.startswith("rail:") else ROAD_WIDTH_M[kind]
        merged = linemerge(lines)
        for line in getattr(merged, "geoms", [merged]):
            geom = line.buffer(w / 2, cap_style="flat", join_style="mitre", mitre_limit=2.0)
            samples = [line.interpolate(t, normalized=True) for t in np.linspace(0, 1, 24)]
            v = float(np.median(smp.value([s.x for s in samples], [s.y for s in samples])))
            v = float(np.clip(v * 0.85, 0.05, 0.17))
            roads.append((geom, v, w, False, kind, line))
    roads += [(g, 0.1, 0.0, False, "joint", None) for g in joint_patches(roads)]
    roads.sort(key=lambda r: r[2])
    road_union = unary_union([r[0] for r in roads])

    # Large roofs: bright hard-edged rectangles from the mockup, plus OSM buildings.
    k = 2 * HALF_M / MOCK_N
    big = []
    dens = f["dens"]
    for (cx, cy), (w, h), ang, val in rects:
        # Bright shapes far from any street are sandbanks and fields, not roofs.
        if dens[int(cy), int(cx)] < 0.006 and w * h < 200:
            continue
        r = Polygon(cv2.boxPoints(((cx, cy), (w, h), ang)) * k - HALF_M)
        if window is not None and not r.intersects(window):
            continue
        big.append((r, float(val), 9.0))
    for kind, rings, p in feats:
        if kind == "poly" and "building" in p:
            r = Polygon(to_frame_m(rings[0])).buffer(0)
            if r.intersects(FRAME) and (window is None or r.intersects(window)):
                c = r.centroid
                big.append((r, float(smp.value(c.x, c.y)), 10.0))
    # Nothing is built under an elevated structure, and large roofs are cut
    # back from roads, rail and water by ROAD_SETBACK_M. A roof that a road
    # crosses becomes two buildings; style.tidy_big_roofs drops leftover
    # strips. House lots are cut from the land between roads, so they need
    # no cut.
    under = viaduct_clearance(viaducts)
    no_roof = unary_union([under, keep_out, road_union.buffer(ROAD_SETBACK_M), water.buffer(ROAD_SETBACK_M)])
    big = [(square_off(r).intersection(FRAME).difference(no_roof), v, h) for r, v, h in big if r.area > 60]
    big = [(r, v, h) for r, v, h in big if not r.is_empty]
    big_union = unary_union([b[0] for b in big] + [under, keep_out]).buffer(1.5)

    # Housing: street blocks cut into lots, kept where the mockup reads as housing.
    land = FRAME.difference(water.buffer(2)).difference(road_union)
    if window is not None:
        land = land.intersection(window.buffer(60))
    blocks = list(land.geoms) if isinstance(land, MultiPolygon) else [land]
    housing_m = mask_to_polys(zone == HOUSING, 2.0)
    housing_area = unary_union(housing_m).buffer(4)
    if window is not None:
        blocks = [b for b in blocks if b.intersects(window)]
    lots = []
    for blk in blocks:
        if blk.area < 25 or not blk.intersects(housing_area):
            continue
        rng = block_rng(seed, blk)
        inner = blk.buffer(-0.6, join_style="mitre")
        if inner.is_empty:
            continue
        rr = blk.minimum_rotated_rectangle
        xy = np.asarray(rr.exterior.coords)[:2]
        ang = np.degrees(np.arctan2(xy[1][1] - xy[0][1], xy[1][0] - xy[0][0]))
        c = blk.centroid
        loc = affinity.rotate(inner, -ang, origin=c)
        x0, y0, x1, y1 = loc.bounds
        ys = [y0]
        while ys[-1] < y1:
            ys.append(ys[-1] + rng.uniform(9, 16))
        cells = []
        for ya, yb in zip(ys[:-1], ys[1:]):
            x = x0 - rng.uniform(0, 6)
            while x < x1:
                wl = rng.uniform(6, 12) if rng.random() > 0.12 else rng.uniform(14, 22)
                piece = loc.intersection(box(x, ya, x + wl, yb))
                x += wl
                for part in getattr(piece, "geoms", [piece]):
                    if part.geom_type != "Polygon" or part.area < 2:
                        continue
                    cc = affinity.rotate(part.centroid, ang, origin=c)
                    if smp.zone_at(cc.x, cc.y) == HOUSING:
                        cells.append(Polygon(part.exterior))
        cells = merge_slivers(cells)
        cells = shape_variety(cells, rng)
        for part in cells:
            if rng.random() < 0.07:
                continue
            lot = affinity.rotate(part, ang, origin=c)
            lot = lot.buffer(-rng.uniform(0.25, 0.7), join_style="mitre")
            if lot.is_empty or lot.intersects(big_union):
                continue
            if lot.geom_type != "Polygon":
                lot = max(lot.geoms, key=lambda g: g.area)
            if not is_buildable(lot):
                continue
            cc = lot.centroid
            v = float(smp.value(cc.x, cc.y)) * rng.uniform(0.8, 1.2)
            v = float(np.clip(v, 0.05, 0.4))
            lots.append((lot.simplify(0.15), v, rng.uniform(6, 15)))

    return water, roads, big, lots, viaducts, blocks


def joint_patches(roads):
    """Where street lines of different types end at the same node (a bend
    from one type into another, or a junction whose arms all end there), the
    flat ends leave wedge-shaped gaps. Each pair of ends gets a short mitred
    patch through the node, as wide as the narrower street."""
    ends = {}
    for _, _, w, _, kind, line in roads:
        if kind.startswith("rail:") or line is None or line.length < 0.5:
            continue
        for at_start in (True, False):
            node = line.coords[0] if at_start else line.coords[-1]
            d = min(w, line.length)
            p = line.interpolate(d if at_start else line.length - d)
            key = (round(node[0], 2), round(node[1], 2))
            ends.setdefault(key, []).append(((p.x, p.y), w))
    patches = []
    for node, arms in ends.items():
        for i in range(len(arms)):
            for j in range(i + 1, len(arms)):
                (pa, wa), (pb, wb) = arms[i], arms[j]
                patch = LineString([pa, node, pb]).buffer(
                    min(wa, wb) / 2, cap_style="flat", join_style="mitre", mitre_limit=2.0)
                patches.append(patch)
    return patches


def min_width(p):
    xy = np.asarray(p.minimum_rotated_rectangle.exterior.coords)
    return min(np.hypot(*(xy[1] - xy[0])), np.hypot(*(xy[2] - xy[1])))


MIN_HOUSE_AREA_M2 = 30.0
MIN_HOUSE_WIDTH_M = 4.5
MIN_HOUSE_FILL = 0.62


def rect_fill(p):
    """Area over the area of the smallest rotated rectangle round it: 1 for a
    rectangle, 0.5 for a right triangle."""
    return p.area / max(p.minimum_rotated_rectangle.area, 1e-6)


def is_sliver(p):
    return (p.area < MIN_HOUSE_AREA_M2 or min_width(p) < MIN_HOUSE_WIDTH_M
            or (rect_fill(p) < MIN_HOUSE_FILL and p.area < 250))


def is_buildable(p):
    """Final check on a house footprint after it is shrunk off the lot edge."""
    return (p.area >= MIN_HOUSE_AREA_M2 and min_width(p) >= MIN_HOUSE_WIDTH_M - 0.8
            and rect_fill(p) >= MIN_HOUSE_FILL - 0.05)


def merge_slivers(cells):
    """Slivers and thin triangles join the neighbour they share the longest
    wall with; a sliver with no neighbour is dropped."""
    cells = list(cells)
    changed = True
    while changed:
        changed = False
        for i, p in enumerate(cells):
            if not is_sliver(p):
                continue
            best = None
            for j, q in enumerate(cells):
                if j == i or not p.intersects(q):
                    continue
                shared = p.intersection(q).length
                if shared > 0.5 and (best is None or shared > best[0]):
                    best = (shared, j)
            if best is not None:
                merged = unary_union([p, cells[best[1]]]).simplify(0.05)
                if merged.geom_type == "Polygon":
                    cells[best[1]] = Polygon(merged.exterior)
            del cells[i]
            changed = True
            break
    return cells


def shape_variety(cells, rng):
    """Some neighbouring lots in different rows join into L or stepped
    shapes; some large lots lose a corner (a yard or light well)."""
    order = rng.permutation(len(cells))
    used = set()
    out = []
    for i in order:
        if i in used:
            continue
        p = cells[i]
        if rng.random() < 0.16:
            for j in rng.permutation(len(cells)):
                if j == i or j in used or not p.intersects(cells[j]):
                    continue
                if p.intersection(cells[j]).length < 3.0:
                    continue
                u = unary_union([p, cells[j]]).simplify(0.05)
                if u.geom_type != "Polygon" or u.area > 380:
                    continue
                if u.area / u.minimum_rotated_rectangle.area < 0.92:
                    p = Polygon(u.exterior)
                    used.add(j)
                    break
        elif rng.random() < 0.1 and p.area > 70:
            x0, y0, x1, y1 = p.bounds
            fw, fh = rng.uniform(0.3, 0.45) * (x1 - x0), rng.uniform(0.3, 0.45) * (y1 - y0)
            cx = x0 if rng.random() < 0.5 else x1 - fw
            cy = y0 if rng.random() < 0.5 else y1 - fh
            cut = p.difference(box(cx, cy, cx + fw, cy + fh))
            if cut.geom_type == "Polygon" and cut.area > 0.6 * p.area:
                p = cut
        used.add(i)
        out.append(p)
    return out


def viaduct_clearance(viaducts):
    return unary_union([
        v.buffer(VIADUCT_WIDTH_M / 2 + VIADUCT_CLEARANCE_M, cap_style="flat") for v in viaducts
    ])


def square_off(poly):
    """A near-rectangular footprint (over 80% of its smallest rotated
    rectangle) becomes that rectangle."""
    rr = poly.minimum_rotated_rectangle
    return rr if poly.area / max(rr.area, 1e-6) > 0.8 else poly
