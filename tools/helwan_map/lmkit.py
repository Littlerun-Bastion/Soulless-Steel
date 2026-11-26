"""Drawing and placement helpers for the landmarks (landmarks.py and the
lm_*.py builders): OSM look-ups, the ground of a set piece (lawns, gravel
paths, frozen ponds, bridges, hills), garden furniture (seated statues on
plinths, stone lanterns, benches, rocks), perimeter walls with gates, roof
functions for building kinds of their own (East-Asian hipped and pyramid
roofs, domes, a mosque roof) and talls (minaret, lattice mast, flagpoles,
an upper roof tier).

Everything is greys, like the rest of the map: dark roofs with light
outlines, light stone and gravel, dark ice and rough dark lawns (there is no
green). Ground objects go in "groundlines" (under the halos) or "interiors"
(over them); roofs in "roofs"; gate roofs that a mecha walks under in
"overheads" (they fade near the player); things that stand well above the
roofs in "talls" (they lean with height, see style.Layers).
"""
import numpy as np
from shapely import affinity, contains_xy, prepare
from shapely.geometry import LinearRing, LineString, MultiPolygon, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import substring, unary_union

import style
from gen_city import ROAD_SETBACK_M, rng_at, to_frame_m

# Light comes from the east-north-east (map y points down), as on the roofs.
LIGHT = style.ROOF_LIGHT
SHADOW_DIR = -LIGHT

STONE_V = 0.33
STONE_EDGE_V = 0.42
GRAVEL_V = 0.21
LAWN_V = 0.1
ICE_V = 0.085
RIM_V = 0.27


# ------------------------------------------------------------------ OSM

def osm_polys(site, test, near=None):
    """OSM polygons (map metres) whose tags pass test(props), optionally only
    those that touch `near`. Returns [(polygon, props)]."""
    out = []
    nb = near.bounds if near is not None else None
    for kind, rings, p in site.feats or []:
        if kind != "poly" or not test(p):
            continue
        shell = to_frame_m(rings[0])
        if len(shell) < 4:
            continue
        if nb is not None and (shell[:, 0].max() < nb[0] or shell[:, 0].min() > nb[2] or
                               shell[:, 1].max() < nb[1] or shell[:, 1].min() > nb[3]):
            continue
        holes = [to_frame_m(r) for r in rings[1:] if len(r) >= 4]
        g = Polygon(shell, holes).buffer(0)
        if g.is_empty or (near is not None and not g.intersects(near)):
            continue
        for part in style.polys(g):
            out.append((part, p))
    return out


def osm_lines(site, test, near=None):
    """OSM lines (map metres) whose tags pass test(props), clipped to
    `near` when given. Returns [(line, props)]."""
    out = []
    nb = near.bounds if near is not None else None
    for kind, rings, p in site.feats or []:
        if kind != "line" or not test(p):
            continue
        pts = to_frame_m(rings[0])
        if len(pts) < 2:
            continue
        if nb is not None and (pts[:, 0].max() < nb[0] or pts[:, 0].min() > nb[2] or
                               pts[:, 1].max() < nb[1] or pts[:, 1].min() > nb[3]):
            continue
        line = LineString(pts)
        if near is not None:
            if not line.intersects(near):
                continue
            line = line.intersection(near)
        for part in getattr(line, "geoms", [line]):
            if part.geom_type == "LineString" and part.length > 0.5:
                out.append((part, p))
    return out


def is_osm_poly(poly, osm_buildings, share=0.5):
    """True when a footprint matches an OSM building outline (rather than a
    roof read from the reference image)."""
    for g in osm_buildings:
        if poly.intersects(g) and poly.intersection(g).area > share * min(poly.area, g.area):
            return True
    return False


def is_osm_roof(b, osm_buildings, share=0.5):
    return is_osm_poly(b.poly, osm_buildings, share)


# ------------------------------------------------------------ whole map
#
# A window run (run_all.py --window) cuts site.roads, site.blocks and
# site.buildings down to the window. The landmarks decide their layout from
# the whole map's layout (site.full_layout) instead, so a window run lays a
# landmark out as the full run does, wherever the window cuts it.

def roads_near(site, geom, dist=40.0):
    """The road concrete (rail left out) within dist metres of geom, from the
    whole map's roads, or None."""
    return site.full_roads_near(geom, dist)


def big_roofs_in(site, area):
    """The whole map's large roofs (site.full_layout["big"], in their order)
    that touch area."""
    return site.full_big_in(area)


def kept_roofs(site, area, osm_buildings):
    """The footprints a landmark keeps on its land after drop_buildings(site,
    area, keep=real OSM roof): the whole map's large roofs that touch area and
    match an OSM building outline or have their centre outside area."""
    return [g for g in big_roofs_in(site, area)
            if is_osm_poly(g, osm_buildings) or not area.contains(g.centroid)]


def standing(site, polys):
    """The site's buildings on the given whole-map footprints, as a list
    parallel to polys (None where there is none: outside a window run's
    window, or replaced by a district module)."""
    at = {id(b.poly): b for b in site.buildings}
    return [at.get(id(g)) for g in polys]


def land_free(site, geom):
    """True when a landmark may take geom: inside the play area, outside every
    KeepOut area, clear of the markers and of earlier claims (Site.is_free;
    what the district modules built there is cleared by the landmark)."""
    return site.is_free(geom, districts=False)


def block_at(site, x, y):
    """The whole map's street block holding (x, y), or None."""
    p = Point(x, y)
    for blk in site.full_layout["blocks"]:
        if blk.contains(p):
            return blk
    return None


def drop_buildings(site, area, keep=lambda b: False):
    """Drops the buildings whose centre is in area, except those keep(b)
    accepts. Returns how many went."""
    prepare(area)
    before = len(site.buildings)
    site.buildings = [b for b in site.buildings if keep(b) or not area.contains(b.poly.centroid)]
    return before - len(site.buildings)


def road_clear(site, geom, margin=ROAD_SETBACK_M):
    """True when geom keeps margin metres off road concrete."""
    roads = roads_near(site, geom, margin + 5.0)
    return roads is None or not roads.intersects(geom.buffer(margin))


def seeded(seed, x, y):
    return rng_at(seed, x, y)


# ----------------------------------------------------------------- shapes

def ngon(x, y, r, n, rot=0.0):
    a = rot + np.linspace(0, 2 * np.pi, n, endpoint=False)
    return Polygon(np.stack([x + np.cos(a) * r, y + np.sin(a) * r], 1))


def ellipse(x, y, rx, ry, ang, n=10):
    a = np.linspace(0, 2 * np.pi, n, endpoint=False)
    c, s = np.cos(ang), np.sin(ang)
    px, py = np.cos(a) * rx, np.sin(a) * ry
    return Polygon(np.stack([x + px * c - py * s, y + px * s + py * c], 1))


def local(x, y, ang):
    """A function turning local (u along ang, w across) offsets into map
    points round (x, y)."""
    c, s = np.cos(ang), np.sin(ang)
    return lambda u, w: (x + u * c - w * s, y + u * s + w * c)


def rect_at(x, y, ang, l, w):
    P = local(x, y, ang)
    return Polygon([P(-l / 2, -w / 2), P(l / 2, -w / 2), P(l / 2, w / 2), P(-l / 2, w / 2)])


def rect_frame(poly):
    """(x, y, ang, length, depth) of poly's smallest turned rectangle, its
    length along ang (the frame a pavilion roof is drawn over)."""
    r = np.asarray(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    e1, e2 = r[1] - r[0], r[2] - r[1]
    l1, l2 = float(np.hypot(*e1)), float(np.hypot(*e2))
    e, ln, d = (e1, l1, l2) if l1 >= l2 else (e2, l2, l1)
    c = r.mean(0)
    return float(c[0]), float(c[1]), float(np.arctan2(e[1], e[0])), ln, d


def cast(geom, dist):
    """geom moved away from the light by dist metres (a cast shadow)."""
    return affinity.translate(geom, SHADOW_DIR[0] * dist, SHADOW_DIR[1] * dist)


# ----------------------------------------------------------------- ground

def lawn(L, geom, rng, v=LAWN_V, a=0.55):
    """Rough dark ground (dead grass): a fill and a scatter of darker tufts."""
    if geom.is_empty:
        return
    L.fill("groundlines", geom, v, a)
    x0, y0, x1, y1 = geom.bounds
    n = int(min(geom.area / 40, 1500))
    if n <= 0:
        return
    prep = geom.buffer(-0.6)
    if prep.is_empty:
        return
    prepare(prep)
    tris, grey = [], []
    for _ in range(n):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if not prep.contains(Point(x, y)):
            continue
        r = rng.uniform(0.3, 0.9)
        a0 = rng.uniform(0, 2 * np.pi)
        pts = [(x + np.cos(a0 + k * 2.1) * r, y + np.sin(a0 + k * 2.1) * r) for k in range(3)]
        tris.append(pts)
        grey.append(rng.choice([0.05, 0.16]))
    if tris:
        t = np.asarray(tris, float)
        L.add_tris("groundlines", t, 0.0, vg=np.repeat(np.asarray(grey)[:, None], 3, 1),
                   va=np.full((len(t), 3), 0.5))


def gravel(L, geom, v=GRAVEL_V, a=0.92, edge_v=0.12):
    """A gravel or paved surface with a dark edge line, laid just inside the
    surface's outline so it stays off what borders it (a road, a lawn)."""
    if geom.is_empty:
        return
    L.fill("groundlines", geom, v, a)
    for g in style.polys(geom.buffer(-0.07, join_style="mitre")):
        for ring in [g.exterior] + list(g.interiors):
            L.line("groundlines", LineString(ring.coords), 0.14, edge_v, 0.8)


def paths_geom(lines, widths):
    """The union of path lines buffered by their widths."""
    parts = [ln.buffer(w / 2, cap_style="round", quad_segs=3) for ln, w in zip(lines, widths)]
    return unary_union(parts) if parts else Polygon()


def steps(L, line, width, v=0.3, avoid=None):
    """Steps: light treads across a path line, cut off `avoid` (buildings,
    road concrete) where they would cross it."""
    if avoid is not None and avoid.is_empty:
        avoid = None
    if avoid is not None:
        prepare(avoid)
    n = int(line.length // 0.45)
    for k in range(1, n):
        p = line.interpolate(k * 0.45)
        q = line.interpolate(min(k * 0.45 + 0.1, line.length))
        d = np.array([q.x - p.x, q.y - p.y])
        d /= np.hypot(*d) or 1.0
        nx, ny = -d[1] * width / 2, d[0] * width / 2
        tread = LineString([(p.x - nx, p.y - ny), (p.x + nx, p.y + ny)])
        if avoid is not None and avoid.intersects(tread):
            tread = tread.difference(avoid)
        L.line("groundlines", tread, 0.08, v, 0.9)


def frozen_pond(L, poly, rng, rim=1.2):
    """A frozen ornamental pond: a stone rim, dark ice with a shadow band
    under the rim, pale frost patches and cracks."""
    rim_geom = poly.buffer(rim, join_style="round").difference(poly)
    L.fill("groundlines", rim_geom, RIM_V)
    L.fill("groundlines", poly, ICE_V)
    for g in style.polys(poly):
        L.strip("groundlines", orient(g, 1.0).exterior, 2.2, +1, 0.55, 0.0)
        for hole in g.interiors:
            L.strip("groundlines", orient(Polygon(hole), 1.0).exterior, 1.6, -1, 0.5, 0.0)
    for g in style.polys(poly.buffer(rim)):
        L.line("groundlines", LineString(g.exterior.coords), 0.12, STONE_EDGE_V, 0.8)
    inner = poly.buffer(-2.0)
    if inner.is_empty:
        return
    prepare(inner)
    x0, y0, x1, y1 = inner.bounds
    for _ in range(int(np.clip(poly.area / 150, 3, 40))):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if not inner.contains(Point(x, y)):
            continue
        patch = ellipse(x, y, rng.uniform(1.5, 5.0), rng.uniform(0.8, 2.5), rng.uniform(0, np.pi), 9)
        L.fill("groundlines", patch.intersection(inner), 0.2, 0.25)
    for _ in range(int(np.clip(poly.area / 120, 3, 50))):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if not inner.contains(Point(x, y)):
            continue
        a = rng.uniform(0, np.pi)
        pts = [(x, y)]
        for _ in range(int(rng.integers(2, 5))):
            a += rng.normal(0, 0.5)
            step = rng.uniform(1.5, 4.0)
            pts.append((pts[-1][0] + np.cos(a) * step, pts[-1][1] + np.sin(a) * step))
        L.line("groundlines", LineString(pts).intersection(inner), 0.06, 0.24, 0.8)


def bridge(L, line, width, rng, arched=True, v=0.3):
    """A garden footbridge along line: its shadow on the ice, a plank deck,
    rails with posts and splayed ends. Drawn in interiors (over the ponds)."""
    if line.length < 1.0:
        return
    line = line.simplify(0.2)
    deck = line.buffer(width / 2, cap_style="flat", join_style="round")
    L.fill("groundlines", cast(deck, 1.6).difference(deck), 0.0, 0.45)
    L.fill("interiors", deck.buffer(0.25, cap_style="flat"), 0.05)
    L.fill("interiors", deck, v)
    n = int(line.length // 0.45)
    for k in range(1, n):
        p = line.interpolate(k * 0.45)
        q = line.interpolate(min(k * 0.45 + 0.1, line.length))
        d = np.array([q.x - p.x, q.y - p.y])
        d /= np.hypot(*d) or 1.0
        nx, ny = -d[1] * width / 2, d[0] * width / 2
        L.line("interiors", LineString([(p.x - nx, p.y - ny), (p.x + nx, p.y + ny)]), 0.05, 0.12, 0.85)
    if arched:
        L.line("interiors", substring(line, line.length * 0.3, line.length * 0.7), width * 0.5, v * 1.35, 0.5)
    for side in (-1, 1):
        rail = line.offset_curve(side * (width / 2 - 0.1))
        if rail.is_empty:
            continue
        L.line("interiors", rail, 0.16, STONE_EDGE_V)
        for t in np.linspace(0, rail.length, max(2, int(rail.length // 1.8) + 1)):
            p = rail.interpolate(t)
            L.fill("interiors", box(p.x - 0.14, p.y - 0.14, p.x + 0.14, p.y + 0.14), 0.48)


def hill(L, x, y, r, rng, rings=5):
    """An artificial garden hill: rough contour bands, lighter towards the
    top and towards the light, with a shadow on the far side."""
    L.fill("groundlines", cast(ngon(x, y, r, 24), r * 0.12), 0.0, 0.35)
    for k in range(rings):
        rr = r * (1.0 - k / rings)
        off = LIGHT * rr * 0.08 * k / rings
        g = Point(x + off[0], y + off[1]).buffer(rr, quad_segs=6)
        g = affinity.scale(g, rng.uniform(0.92, 1.08), rng.uniform(0.92, 1.08))
        L.fill("groundlines", g, 0.11 + 0.025 * k, 0.9)
        L.line("groundlines", LineString(g.exterior.coords), 0.07, 0.2 + 0.02 * k, 0.6)


def rocks(L, x, y, n, rng, spread=2.5):
    """A cluster of garden rocks with cast shadows (interiors)."""
    for _ in range(n):
        px, py = x + rng.normal(0, spread), y + rng.normal(0, spread)
        r = rng.uniform(0.4, 1.3)
        pts = [(px + np.cos(a) * r * rng.uniform(0.7, 1.15), py + np.sin(a) * r * rng.uniform(0.7, 1.15))
               for a in np.linspace(0, 2 * np.pi, 7, endpoint=False)]
        g = Polygon(pts).buffer(0)
        L.fill("interiors", cast(g, r * 0.6), 0.0, 0.45)
        L.fill("interiors", g, rng.uniform(0.22, 0.3))
        hi = affinity.translate(affinity.scale(g, 0.55, 0.55), LIGHT[0] * r * 0.25, LIGHT[1] * r * 0.25)
        L.fill("interiors", hi, 0.36, 0.8)


# -------------------------------------------------------------- furniture

def buddha(L, x, y, ang, scale=1.0, plinth=True):
    """A seated Buddha seen from above, facing ang (radians): a stone plinth,
    then the crossed legs and lap, the robed body, shoulders, the head with
    its top knot. Drawn in interiors."""
    s = scale
    P = local(x, y, ang)
    if plinth:
        base = rect_at(x, y, ang, 1.8 * s, 1.8 * s)
        L.fill("interiors", cast(base, 0.7 * s), 0.0, 0.5)
        L.fill("interiors", base, 0.17)
        L.fill("interiors", rect_at(x, y, ang, 1.5 * s, 1.5 * s), 0.21)
        L.line("interiors", LinearRing(base.exterior.coords), 0.08 * s, 0.36)
    legs = ellipse(*P(0.22 * s, 0), 0.34 * s, 0.66 * s, ang, 12)
    body = ellipse(*P(-0.2 * s, 0), 0.3 * s, 0.5 * s, ang, 12)
    figure = legs.union(body)
    L.fill("interiors", cast(figure, 0.4 * s), 0.0, 0.55)
    L.fill("interiors", figure.buffer(0.07 * s), 0.06)
    L.fill("interiors", legs, 0.42)
    L.fill("interiors", affinity.translate(affinity.scale(legs, 0.7, 0.7), LIGHT[0] * 0.08 * s,
                                           LIGHT[1] * 0.08 * s), 0.48, 0.8)
    L.fill("interiors", ellipse(*P(0.2 * s, 0), 0.13 * s, 0.22 * s, ang, 8), 0.3)
    L.fill("interiors", body, 0.46)
    L.fill("interiors", Point(*P(-0.2 * s, 0)).buffer(0.24 * s, quad_segs=3).buffer(0.05 * s), 0.12)
    hx, hy = P(-0.2 * s, 0)
    L.fill("interiors", Point(hx, hy).buffer(0.23 * s, quad_segs=3), 0.55)
    L.fill("interiors", Point(hx + LIGHT[0] * 0.06 * s, hy + LIGHT[1] * 0.06 * s).buffer(0.12 * s, quad_segs=2),
           0.64)
    L.fill("interiors", Point(*P(-0.24 * s, 0)).buffer(0.08 * s, quad_segs=2), 0.38)


def lantern(L, x, y, ang, s=1.0):
    """A stone lantern from above: base shadow, a hexagonal cap with upturned
    corners, a lit facet and the finial."""
    L.fill("interiors", cast(ngon(x, y, 0.6 * s, 6, ang), 1.1 * s), 0.0, 0.5)
    L.fill("interiors", ngon(x, y, 0.62 * s, 6, ang), 0.27)
    for k in range(6):
        a = ang + k * np.pi / 3
        L.line("interiors", LineString([(x + np.cos(a) * 0.55 * s, y + np.sin(a) * 0.55 * s),
                                        (x + np.cos(a) * 0.78 * s, y + np.sin(a) * 0.78 * s)]), 0.07 * s, 0.4)
    lx, ly = x + LIGHT[0] * 0.12 * s, y + LIGHT[1] * 0.12 * s
    L.fill("interiors", ngon(lx, ly, 0.34 * s, 6, ang), 0.37)
    L.fill("interiors", Point(x, y).buffer(0.13 * s, quad_segs=2), 0.47)


def bench(L, x, y, ang):
    b = rect_at(x, y, ang, 1.9, 0.55)
    L.fill("interiors", cast(b, 0.35), 0.0, 0.4)
    L.fill("interiors", b, 0.26)
    P = local(x, y, ang)
    for w in (-0.15, 0.0, 0.15):
        L.line("interiors", LineString([P(-0.9, w), P(0.9, w)]), 0.04, 0.14)


def cases(L, x, y, ang, rng, mark=None):
    """A stack of equipment cases on a pallet (a salvage source's look).
    mark "cross" puts a light cross on the lids (medical stores)."""
    P = local(x, y, ang)
    pallet = rect_at(x, y, ang, 2.6, 1.8)
    L.fill("interiors", cast(pallet, 0.5), 0.0, 0.45)
    L.fill("interiors", pallet, 0.17)
    for k in range(5):
        L.line("interiors", LineString([P(-1.3, -0.9 + k * 0.45), P(1.3, -0.9 + k * 0.45)]), 0.05, 0.1)
    for (u, w, l, d) in ((-0.62, -0.42, 1.1, 0.8), (0.62, -0.42, 1.1, 0.8), (-0.3, 0.45, 1.6, 0.75)):
        if rng.random() < 0.15:
            continue
        cx, cy = P(u, w)
        c = rect_at(cx, cy, ang + rng.normal(0, 0.05), l, d)
        L.fill("interiors", c, rng.uniform(0.25, 0.32))
        L.line("interiors", LinearRing(c.exterior.coords), 0.05, STONE_EDGE_V)
        if mark == "cross":
            Q = local(cx, cy, ang)
            L.line("interiors", LineString([Q(-0.22, 0), Q(0.22, 0)]), 0.1, 0.55)
            L.line("interiors", LineString([Q(0, -0.22), Q(0, 0.22)]), 0.1, 0.55)
        else:
            Q = local(cx, cy, ang)
            L.line("interiors", LineString([Q(-l / 2 + 0.1, 0), Q(l / 2 - 0.1, 0)]), 0.04, 0.15)


def lamp_post(L, x, y):
    L.fill("interiors", cast(Point(x, y).buffer(0.25, quad_segs=2), 1.2), 0.0, 0.4)
    L.fill("interiors", Point(x, y).buffer(0.22, quad_segs=2), 0.35)
    L.fill("interiors", Point(x, y).buffer(0.1, quad_segs=2), 0.5)


# ------------------------------------------------------------------ walls

def wall_parts(ring_line, gates, gap, cut=None):
    """The pieces of a perimeter line left after the gate gaps (a gap metres
    wide at each gate point) and the areas in `cut` (buildings that form part
    of the wall) are taken out."""
    line = LineString(ring_line.coords)
    cuts = sorted(line.project(Point(g)) for g in gates)
    parts, d0 = [], 0.0
    for d in cuts:
        if d - gap / 2 > d0 + 0.5:
            parts.append(substring(line, d0, d - gap / 2))
        d0 = max(d0, d + gap / 2)
    if line.length > d0 + 0.5:
        parts.append(substring(line, d0, line.length))
    out = []
    for p in parts:
        if cut is not None and not cut.is_empty:
            p = p.difference(cut)
        for q in getattr(p, "geoms", [p]):
            if q.geom_type == "LineString" and q.length > 0.6:
                out.append(q)
    return out


def perimeter_wall(L, parts, width=0.55, v=0.3, pier_every=7.0, pier=0.95, coping=True, avoid=None):
    """A garden or compound wall along the given lines: a soft shadow, the
    wall, a lighter coping line and square piers at intervals and at the
    ends (interiors). Where a line comes within reach of `avoid` (the
    buildings the wall meets) it stops, so the wall, its shadow and its end
    piers stay off them."""
    if avoid is not None and not avoid.is_empty:
        reach = max(width + 0.9, pier * 1.42) / 2 + 0.1
        cut = avoid.buffer(reach, quad_segs=3)
        parts = [q for p in parts for q in wall_parts(p, [], 0.0, cut)]
    for part in parts:
        L.line("interiors", part, width + 0.9, 0.0, 0.35)
        L.line("interiors", part, width, v)
        if coping:
            L.line("interiors", part, width * 0.35, min(v * 1.45, 0.48), 0.8)
        n = max(1, int(part.length // pier_every))
        for t in np.linspace(0, part.length, n + 1):
            p = part.interpolate(t)
            q = part.interpolate(min(t + 0.3, part.length)) if t < part.length else part.interpolate(t - 0.3)
            a = np.arctan2(q.y - p.y, q.x - p.x)
            sq = rect_at(p.x, p.y, a, pier, pier)
            L.fill("interiors", sq, v * 1.15)
            L.line("interiors", LinearRing(sq.exterior.coords), 0.06, STONE_EDGE_V, 0.9)


def gate_points(ring_line, lines, cluster=12.0):
    """Points where lines cross a perimeter ring, merged when closer than
    cluster metres."""
    ring = LineString(ring_line.coords)
    pts = []
    for ln in lines:
        x = ring.intersection(ln)
        for g in getattr(x, "geoms", [x]):
            if g.geom_type == "Point":
                pts.append((g.x, g.y))
    out = []
    for p in pts:
        if all(np.hypot(p[0] - q[0], p[1] - q[1]) > cluster for q in out):
            out.append(p)
    return out


def gate_piers(L, ring_line, gate, gap, v=0.33, size=1.6, avoid=None, slide=0.0):
    """Two tall square piers either side of a gate gap. A pier that would
    stand on `avoid` (buildings, road concrete) moves out along the ring,
    up to `slide` metres in 0.5 m steps, until it stands clear (a gate
    wider than its gap flanked by its piers) or is left out; the shadows
    stay off `avoid`."""
    line = LineString(ring_line.coords)
    d = line.project(Point(gate))
    if avoid is not None and avoid.is_empty:
        avoid = None
    for s in (-1, 1):
        for extra in np.arange(0.0, slide + 0.01, 0.5):
            t = d + s * (gap / 2 + size / 2 + extra)
            p = line.interpolate(np.clip(t, 0, line.length))
            q = line.interpolate(np.clip(t + 0.3, 0, line.length))
            a = np.arctan2(q.y - p.y, q.x - p.x)
            sq = rect_at(p.x, p.y, a, size, size)
            if avoid is None or not sq.buffer(0.1).intersects(avoid):
                break
        else:
            continue
        shadow = cast(sq, 1.0)
        L.fill("interiors", shadow if avoid is None else shadow.difference(avoid), 0.0, 0.5)
        L.fill("interiors", sq, v)
        L.fill("interiors", rect_at(p.x, p.y, a, size * 0.6, size * 0.6), v * 1.25)
        L.line("interiors", LinearRing(sq.exterior.coords), 0.08, STONE_EDGE_V)


def ring_angle(ring_line, pt):
    line = LineString(ring_line.coords)
    d = line.project(Point(pt))
    p = line.interpolate(max(d - 1.0, 0))
    q = line.interpolate(min(d + 1.0, line.length))
    return float(np.arctan2(q.y - p.y, q.x - p.x))


def gate_roof(L, x, y, ang, length, depth, v=0.1):
    """A small hipped roof over a gate (overheads: it fades near the player)
    with upturned corners: a roofed Japanese garden gate."""
    hip_roof(L, "overheads", x, y, ang, length, depth, v, flicks=True, chunk=style.chunk_key(Point(x, y)))


# ------------------------------------------------------------------ roofs

def _faces(sub, L, faces, v, key, course, a=1.0):
    for pts, axis, down in faces:
        face = Polygon(pts)
        if face.area < 0.02:
            continue
        lit = 1.0 + 0.32 * float(np.dot(down, LIGHT))
        if sub == "roofs":
            L.stripe = (np.asarray(pts[0]), np.asarray(axis) / course)
        L.fill(sub, face, min(v * lit, 0.24), a, chunk=key)
        L.stripe = None


def hip_roof(L, sub, x, y, ang, length, depth, v, flicks=True, chunk=None, course=0.33, ridge_v=None,
             outline=None):
    """A hipped roof over a length x depth rectangle centred on (x, y) along
    ang (radians), in the East-Asian manner: lit and shaded faces with tile
    channels running down the slope, a heavy ridge with raised ends, hip
    lines, a dark gutter band and upturned corner tips. `outline` (a
    polygon) carries the gutter band and the outline line instead of the
    rectangle, for a roof cut to a building's own outline."""
    key = chunk or style.chunk_key(Point(x, y))
    P = local(x, y, ang)
    hl, hw = length / 2, depth / 2
    r = max(hl - hw, 0.0)
    u = np.array([np.cos(ang), np.sin(ang)])
    w = np.array([-np.sin(ang), np.cos(ang)])
    faces = []
    for s in (1, -1):
        faces.append(([P(-hl, s * hw), P(hl, s * hw), P(r, 0), P(-r, 0)], u, s * w))
        faces.append(([P(s * hl, -hw), P(s * hl, hw), P(s * r, 0)], w, s * u))
    _faces(sub, L, faces, v, key, course)
    if outline is None:
        outline = Polygon([P(-hl, -hw), P(hl, -hw), P(hl, hw), P(-hl, hw)])
    L.strip(sub, orient(outline, 1.0).exterior, min(0.6, depth * 0.12), +1, 0.5, 0.0, chunk=key)
    rv = ridge_v if ridge_v is not None else style.DETAIL_LINE_V * 1.2
    L.line(sub, LineString([P(-r, 0), P(r, 0)]), 0.32, rv, chunk=key)
    for s1 in (1, -1):
        for s2 in (1, -1):
            L.line(sub, LineString([P(s1 * hl, s2 * hw), P(s1 * r, 0)]), 0.14, rv * 0.9, chunk=key)
    if r > 0.5:
        for s1 in (1, -1):
            L.fill(sub, Point(*P(s1 * (r + 0.1), 0)).buffer(0.32, quad_segs=2), rv * 1.15, chunk=key)
    L.line(sub, LinearRing(outline.exterior.coords), 0.16, style.OUTLINE_V, chunk=key)
    if flicks:
        k = min(1.0, depth * 0.14)
        for s1 in (1, -1):
            for s2 in (1, -1):
                L.line(sub, LineString([P(s1 * hl, s2 * hw), P(s1 * (hl + k), s2 * (hw + k))]), 0.18,
                       style.OUTLINE_V, chunk=key)


def pyramid_roof(L, sub, x, y, r, n, v, rot=0.0, chunk=None, flicks=True, apex=True, a=1.0):
    """A pyramid roof over a regular n-gon of radius r (a round pavilion or a
    pagoda tier): one lit or shaded face per side, an eave line, ridge lines
    to the apex, upturned tips and a finial."""
    key = chunk or style.chunk_key(Point(x, y))
    ang = rot + np.linspace(0, 2 * np.pi, n, endpoint=False)
    pts = np.stack([x + np.cos(ang) * r, y + np.sin(ang) * r], 1)
    faces = []
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        mid = (p + q) / 2
        down = (mid - (x, y)) / max(np.hypot(*(mid - (x, y))), 1e-6)
        axis = (q - p) / max(np.hypot(*(q - p)), 1e-6)
        faces.append(([tuple(p), tuple(q), (x, y)], axis, down))
    _faces(sub, L, faces, v, key, 0.33, a)
    ring = Polygon(pts)
    L.strip(sub, orient(ring, 1.0).exterior, min(0.6, r * 0.15), +1, 0.5 * a, 0.0, chunk=key)
    for p in pts:
        L.line(sub, LineString([tuple(p), (x, y)]), 0.12, style.DETAIL_LINE_V, a, chunk=key)
    L.line(sub, LinearRing(pts), 0.15, style.OUTLINE_V, a, chunk=key)
    if flicks:
        for p in pts:
            d = (p - (x, y)) / max(np.hypot(*(p - (x, y))), 1e-6)
            L.line(sub, LineString([tuple(p), tuple(p + d * min(0.9, r * 0.18))]), 0.16, style.OUTLINE_V, a,
                   chunk=key)
    if apex:
        L.fill(sub, Point(x, y).buffer(max(0.18, r * 0.06), quad_segs=2), 0.5, a, chunk=key)


def dome(L, sub, x, y, r, v, chunk=None, ribs=0, slit=None, rng=None):
    """A dome seen from above, lit from the east-north-east: stacked discs
    brightening towards the lit side, an outline, optional ribs (panel
    seams) and an optional observing slit at angle `slit` (radians): a dark
    band from the crown to the rim with its shutter rails."""
    key = chunk or style.chunk_key(Point(x, y))
    L.fill(sub, Point(x, y).buffer(r, quad_segs=8), v * 0.8, chunk=key)
    steps_n = 5
    for k in range(1, steps_n + 1):
        t = k / (steps_n + 1)
        rr = r * (1.0 - t * 0.85)
        off = LIGHT * r * 0.32 * t
        L.fill(sub, Point(x + off[0], y + off[1]).buffer(rr, quad_segs=8), min(v * (1.0 + 0.45 * t), 0.3), 0.85,
               chunk=key)
    for k in range(ribs):
        a = 2 * np.pi * k / ribs
        L.line(sub, LineString([(x + np.cos(a) * r * 0.12, y + np.sin(a) * r * 0.12),
                                (x + np.cos(a) * r * 0.98, y + np.sin(a) * r * 0.98)]), 0.06, 0.06, 0.7, chunk=key)
    if slit is not None:
        wdt = r * 0.2
        P = local(x, y, slit)
        band = Polygon([P(-r * 0.25, -wdt / 2), P(r * 0.97, -wdt / 2), P(r * 0.97, wdt / 2), P(-r * 0.25, wdt / 2)])
        L.fill(sub, band, 0.015, chunk=key)
        L.fill(sub, Polygon([P(r * 0.1, -wdt * 0.18), P(r * 0.62, -wdt * 0.18), P(r * 0.62, wdt * 0.18),
                             P(r * 0.1, wdt * 0.18)]), 0.2, chunk=key)
        for side in (-1, 1):
            L.line(sub, LineString([P(-r * 0.3, side * (wdt / 2 + 0.12)), P(r * 0.98, side * (wdt / 2 + 0.12))]),
                   0.14, 0.34, chunk=key)
    L.fill(sub, Point(x, y).buffer(r, quad_segs=8).difference(Point(x, y).buffer(r - 0.25, quad_segs=8)),
           style.OUTLINE_V * 0.9, chunk=key)


# --------------------------------------------------------- roof functions

# How far a cut pavilion roof may reach past its outline.
EAVE_M = 0.3


def _shade_room(poly, x, y, r, width):
    """The width of the shadow round a dome of radius r at (x, y), cut down
    so it ends at the roof's edge."""
    return float(np.clip(poly.exterior.distance(Point(x, y)) - r, 0.15, width))


def roof_pavilion(L, b, rng):
    """A rectangular garden pavilion: an East-Asian hipped roof over the
    whole footprint. Over an outline that is not a rectangle (a real
    building given this roof) the roof is drawn over the outline's turned
    rectangle and cut to the outline grown by EAVE_M, through the roof clip
    (on top of a ruined roof's own clip), its gutter band and outline line
    following the outline."""
    F = b.opts["frame"]
    x, y, ang, l, d = F
    key = style.chunk_key(b.poly)
    clip = None
    if b.poly.area < 0.97 * l * d:
        clip = b.poly.buffer(EAVE_M, join_style="mitre")
        cut, keep = L.roof_cut, L.roof_keep
        L.set_roof_clip(cut=cut, keep=clip if keep is None else keep.intersection(clip))
    hip_roof(L, "roofs", x, y, ang, l, d, style.roof_value(b.mv) * 1.45 + 0.03, chunk=key,
             outline=b.poly if clip is not None else None)
    if clip is not None:
        L.set_roof_clip(cut=cut, keep=keep)
    return None


def roof_kiosk(L, b, rng):
    """A round (polygonal) pavilion: a pyramid roof with upturned tips."""
    x, y, r, n, rot = b.opts["kiosk"]
    pyramid_roof(L, "roofs", x, y, r, n, style.roof_value(b.mv) * 1.45 + 0.03, rot, chunk=style.chunk_key(b.poly))
    return None


def roof_dome(L, b, rng):
    """An observatory dome on a round drum: a lit dome with panel seams and
    the observing slit, on a narrow drum ring."""
    x, y, r = b.opts["dome"]
    key = style.chunk_key(b.poly)
    L.fill("roofs", b.poly, 0.07, chunk=key)
    L.line("roofs", LinearRing(b.poly.exterior.coords), style.OUTLINE_W, style.OUTLINE_V, chunk=key)
    dome(L, "roofs", x, y, r - 0.7, 0.17, chunk=key, ribs=12, slit=b.opts.get("slit", 0.0))
    return None


def roof_flat_domes(L, b, rng):
    """A flat roof (the standard large-roof kit, no clutter in the dome
    spots) with one to three small observation domes on it."""
    spots = b.opts.get("domes", [])
    L.roof_taken = list(L.roof_taken) + [Point(x, y).buffer(r + 0.8) for x, y, r in spots]

    def post(R):
        for (x, y, r), s in zip(spots, b.opts.get("slits", [0.0] * len(spots))):
            R.shade_out(Point(x, y).buffer(r, quad_segs=6), 0.5 * r, 0.5)
            dome(L, "roofs", x, y, r, 0.16, chunk=R.key, ribs=8, slit=s)
    R = style.draw_big(L, b.poly, b.mv, rng, items=True, post=post)
    L.roof_taken = []
    return R


def roof_mosque(L, b, rng):
    """A mosque roof: a flat roof with a parapet, the main dome over the
    widest part of the prayer hall and a small dome over the widest part of
    the rest (b.opts "dome" and "small_domes")."""
    g = b.poly
    v = style.roof_value(b.mv) * 1.1
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    inner = style.set_inner(R, g, 0.6)
    R.shade_in(inner, 1.3, 0.4)
    R.ring(inner, style.PARAPET_W * 1.2, style.PARAPET_V)
    x, y, r = b.opts["dome"]
    R.shade_out(Point(x, y).buffer(r, quad_segs=8), _shade_room(g, x, y, r, r * 0.35), 0.55)
    dome(L, "roofs", x, y, r, 0.15, chunk=R.key, ribs=16)
    L.fill("roofs", Point(x, y).buffer(0.3, quad_segs=2), 0.55, chunk=R.key)
    for sx, sy, sr in b.opts.get("small_domes", []):
        R.shade_out(Point(sx, sy).buffer(sr, quad_segs=6), _shade_room(g, sx, sy, sr, sr * 0.4), 0.5)
        dome(L, "roofs", sx, sy, sr, 0.14, chunk=R.key)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return None


# ------------------------------------------------------------------ talls

def tall_cone(L, x, y, r, h0, h1, n, v_side, v_tip=None):
    """A cone (minaret cap, finial) from a ring of radius r at h0 to a point
    at h1."""
    a = np.linspace(0, 2 * np.pi, n, endpoint=False)
    ring = np.stack([x + np.cos(a) * r, y + np.sin(a) * r], 1)
    q = np.roll(ring, -1, 0)
    tip = np.tile([x, y], (n, 1))
    tris = np.stack([ring, q, tip], 1)
    vh = np.tile([h0, h0, h1], (n, 1)).astype(np.float32)
    mid = (ring + q) / 2 - (x, y)
    lit = 1.0 + 0.35 * (mid @ LIGHT) / max(r, 1e-6)
    vg = np.repeat((v_side * lit)[:, None], 3, 1)
    if v_tip is not None:
        vg[:, 2] = v_tip
    L.add_tris("talls", tris, 0.0, chunk=style.chunk_key(Point(x, y)), vg=vg, vh=vh)


def tall_pyramid(L, x, y, r, n, h0, h1, v, rot=0.0, flick=0.0):
    """A pyramid roof tier standing at h0 (eaves) to h1 (apex): one face per
    side lit by its direction, with an eave edge line at h0."""
    a = rot + np.linspace(0, 2 * np.pi, n, endpoint=False)
    ring = np.stack([x + np.cos(a) * r, y + np.sin(a) * r], 1)
    q = np.roll(ring, -1, 0)
    tip = np.tile([x, y], (n, 1))
    tris = np.stack([ring, q, tip], 1)
    vh = np.tile([h0, h0, h1], (n, 1)).astype(np.float32)
    mid = (ring + q) / 2 - (x, y)
    lit = 1.0 + 0.32 * (mid @ LIGHT) / max(r, 1e-6)
    key = style.chunk_key(Point(x, y))
    L.add_tris("talls", tris, 0.0, chunk=key, vg=np.repeat((v * lit)[:, None], 3, 1), vh=vh)
    for p, qq in zip(ring, q):
        L.tall_span(tuple(p), tuple(qq), 0.24, h0, h0, style.OUTLINE_V, chunk=key)
        L.tall_span(tuple(p), (x, y), 0.14, h0, h1, style.DETAIL_LINE_V, chunk=key)
    if flick > 0:
        for p in ring:
            d = (p - (x, y)) / max(np.hypot(*(p - (x, y))), 1e-6)
            L.tall_span(tuple(p), tuple(p + d * flick), 0.16, h0, h0 + flick * 0.6, style.OUTLINE_V, chunk=key)


def octagon(x, y, r):
    return ngon(x, y, r, 8, np.pi / 8)


def minaret(L, x, y, height=30.0, base=3.4):
    """A minaret in the talls: a square base, an octagonal shaft, a balcony
    ring with a parapet, a slimmer upper shaft, a second small balcony, a
    pointed cap and a finial. Lower parts first (painter's order)."""
    h = height
    side, top = 0.2, 0.33
    L.tall_post(x, y, base, 0.0, h * 0.2, side * 0.9, top)
    L.tall_prism(octagon(x, y, base * 0.45), h * 0.2, h * 0.72, side, top)
    L.tall_prism(octagon(x, y, base * 0.72), h * 0.72, h * 0.75, 0.26, 0.4)
    L.fill("talls", LineString(octagon(x, y, base * 0.66).exterior.coords).buffer(0.12), 0.48, h=h * 0.75 + 0.6)
    L.tall_prism(octagon(x, y, base * 0.34), h * 0.75, h * 0.88, side, top)
    L.tall_prism(octagon(x, y, base * 0.5), h * 0.88, h * 0.9, 0.26, 0.4)
    tall_cone(L, x, y, base * 0.36, h * 0.9, h * 0.99, 8, 0.24, 0.4)
    L.tall_post(x, y, 0.16, h * 0.99, h * 1.05, 0.45, 0.55)


def lattice_mast(L, x, y, height, ang=0.0, guys=3, guy_r=None, rng=None):
    """A guyed lattice mast in the talls: a slim braced shaft (two crossed
    strips per section and a light edge), equipment platforms and antennas
    near the top, and guy wires down to anchors on the ground. Returns the
    anchor points."""
    w = 1.1
    sec = 6.0
    n = max(2, int(height // sec))
    for k in range(n):
        h0, h1 = k * sec, min((k + 1) * sec, height)
        P = local(x, y, ang)
        L.tall_span(P(-w / 2, -w / 2), P(w / 2, w / 2), 0.09, h0, h1, 0.32)
        L.tall_span(P(w / 2, -w / 2), P(-w / 2, w / 2), 0.09, h0, h1, 0.32)
    for s1, s2 in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        P = local(x, y, ang)
        L.tall_span(P(s1 * w / 2, s2 * w / 2), P(s1 * w / 2, s2 * w / 2), 0.12, 0.0, height, 0.4)
    for hp in (height * 0.55, height * 0.86):
        L.tall_prism(rect_at(x, y, ang, w * 2.4, w * 2.4), hp, hp + 0.3, 0.22, 0.38)
    for k, a in enumerate((ang, ang + 2.1, ang + 4.2)):
        P = local(x, y, a)
        L.tall_prism(rect_at(*P(w * 1.4, 0), a, 0.5, 1.6), height * 0.86 + 0.3, height * 0.86 + 2.4, 0.3, 0.44)
    L.tall_post(x, y, 0.2, height, height + 4.0, 0.42, 0.5)
    guy_r = guy_r or height * 0.4
    anchors = []
    for k in range(guys):
        a = ang + np.pi / 4 + 2 * np.pi * k / guys
        ax, ay = x + np.cos(a) * guy_r, y + np.sin(a) * guy_r
        anchors.append((ax, ay))
        for hp in (height * 0.5, height * 0.85):
            L.tall_span((x, y), (ax, ay), 0.06, hp, 0.0, 0.36)
    return anchors


def flagpole(L, x, y, height, ang):
    """A flagpole with a tattered flag hanging off its top (talls)."""
    L.tall_post(x, y, 0.22, 0.0, height, 0.4, 0.5)
    P = local(x, y, ang)
    L.tall_span((x, y), P(1.6, 0.0), 0.75, height - 0.6, height - 1.0, 0.2)
    L.tall_span(P(1.6, 0.0), P(2.3, 0.25), 0.45, height - 1.0, height - 1.5, 0.17)


def pagoda_tier(L, x, y, r_body, r_roof, h0, h1, h2, v_roof, n=8, rot=np.pi / 8):
    """An upper storey of a pavilion in the talls: walls (an n-gon) from h0
    to h1 and a pyramid roof from its eaves at h1 to the apex at h2, with a
    finial."""
    L.tall_prism(ngon(x, y, r_body, n, rot), h0, h1, 0.26, 0.2)
    tall_pyramid(L, x, y, r_roof, n, h1, h2, v_roof, rot, flick=r_roof * 0.15)
    L.tall_post(x, y, 0.22, h2, h2 + 1.4, 0.4, 0.52)
    tall_cone(L, x, y, 0.35, h2 + 0.6, h2 + 0.9, 6, 0.45)


# --------------------------------------------------------------- placing

def free_spots(area, blocked, step, rng, clear=0.0):
    """Candidate points on a jittered grid inside area, clear of blocked by
    `clear` metres."""
    x0, y0, x1, y1 = area.bounds
    inside = area.buffer(-clear) if clear else area
    if inside.is_empty:
        return []
    prepare(inside)
    bl = blocked.buffer(clear) if (blocked is not None and not blocked.is_empty and clear) else blocked
    if bl is not None and not bl.is_empty:
        prepare(bl)
    out = []
    for gx in np.arange(x0 + step / 2, x1, step):
        for gy in np.arange(y0 + step / 2, y1, step):
            px, py = gx + rng.uniform(-0.4, 0.4) * step, gy + rng.uniform(-0.4, 0.4) * step
            p = Point(px, py)
            if not inside.contains(p):
                continue
            if bl is not None and not bl.is_empty and bl.contains(p):
                continue
            out.append((px, py))
    return out


def as_multi(geoms):
    geoms = [g for g in geoms if g is not None and not g.is_empty]
    return unary_union(geoms) if geoms else MultiPolygon()


def find_rect(cands, l, w, ang, inside, blocked):
    """The first candidate centre where an l x w rectangle turned by ang
    lies inside `inside` and clear of `blocked`. Returns (x, y, ang) or
    None."""
    prepare(inside)
    if blocked is not None and not blocked.is_empty:
        prepare(blocked)
    for x, y in cands:
        g = rect_at(x, y, ang, l, w)
        if inside.contains(g) and (blocked is None or blocked.is_empty or not blocked.intersects(g)):
            return (float(x), float(y), float(ang))
    return None


def raked_bed(L, x, y, ang, l, w, rng):
    """A dry garden: a bed of pale raked gravel in a stone kerb, the rake
    lines running its length and ringing three or four set stones."""
    P = local(x, y, ang)
    bed = rect_at(x, y, ang, l, w)
    L.fill("groundlines", bed.buffer(0.45, join_style="mitre"), 0.3)
    L.fill("groundlines", bed, 0.27)
    stones = []
    for _ in range(int(rng.integers(3, 5))):
        for _ in range(20):
            u, v = rng.uniform(-l / 2 + 2.0, l / 2 - 2.0), rng.uniform(-w / 2 + 1.6, w / 2 - 1.6)
            if all(np.hypot(u - a, v - b) > 3.2 for a, b, _ in stones):
                stones.append((u, v, rng.uniform(0.5, 1.0)))
                break
    rings = unary_union([Point(*P(u, v)).buffer(r + 0.5 + 0.35 * k, quad_segs=6)
                         for u, v, r in stones for k in range(4)]) if stones else Polygon()
    for k in np.arange(-w / 2 + 0.35, w / 2, 0.35):
        ln = LineString([P(-l / 2 + 0.2, k), P(l / 2 - 0.2, k)])
        if not rings.is_empty:
            ln = ln.difference(rings)
        L.line("groundlines", ln, 0.06, 0.2, 0.85)
    for u, v, r in stones:
        cx, cy = P(u, v)
        for k in range(4):
            L.line("groundlines", Point(cx, cy).buffer(r + 0.5 + 0.35 * k, quad_segs=6).exterior, 0.06, 0.2, 0.85)
    for u, v, r in stones:
        rocks(L, *P(u, v), 1, rng, 0.0)
    L.line("groundlines", LinearRing(bed.exterior.coords), 0.12, STONE_EDGE_V, 0.9)


def mask_drawers(site, drawers, area):
    """Wraps drawers (functions f(L) of the district modules) so that what
    they draw with a triangle centre inside `area`, and the salvage sources
    they register there while drawing, are left out: the landmarks take the
    land after the district modules have built on it, and their ground
    objects (yards, gantries, skids) are drawn closures that cannot be
    taken back otherwise."""
    if area is None or area.is_empty:
        return list(drawers)
    prepare(area)

    def wrap(draw):
        def run(L):
            orig = L.add_tris
            source = site.salvage.add if site.salvage is not None else None

            def add_tris(sub, tris, v, a=1.0, chunk=None, va=None, vg=None, vh=None):
                tris = np.asarray(tris, float)
                if len(tris):
                    cen = tris.mean(1)
                    keep = ~contains_xy(area, cen[:, 0], cen[:, 1])
                    if not keep.all():
                        tris = tris[keep]
                        va = None if va is None else np.asarray(va)[keep]
                        vg = None if vg is None else np.asarray(vg)[keep]
                        vh = None if vh is None else np.asarray(vh)[keep]
                orig(sub, tris, v, a, chunk, va, vg, vh)

            def add_source(kind, x, y, *args, **kw):
                if area.contains(Point(x, y)):
                    return False
                return source(kind, x, y, *args, **kw)
            L.add_tris = add_tris
            if source is not None:
                site.salvage.add = add_source
            try:
                draw(L)
            finally:
                del L.add_tris
                if source is not None:
                    del site.salvage.add
        return run
    return [wrap(d) for d in drawers]


def drop_obstacles(site, area):
    """Drops the ground obstacles whose centre is inside area. Returns how
    many went."""
    if site.obstacles is None or not site.obstacles.items:
        return 0
    prepare(area)
    before = len(site.obstacles.items)
    site.obstacles.items = [(k, p) for k, p in site.obstacles.items
                            if not area.contains(Point(*np.asarray(p).mean(0)))]
    return before - len(site.obstacles.items)
