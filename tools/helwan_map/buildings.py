"""Every generated building, and how it is drawn.

A Building is one footprint (map-frame metres) with a kind, a district and a
ruin state. Its id is its place in the list given to build_layers, which is
also its id in footprints.bin and on its roof vertices.

Kinds and how each is drawn live in KINDS: name -> (roof function, large
interior, halo width in metres). The district modules (industrial.py,
farmland.py, market.py) add their own kinds there. A roof function draws the
roof with the kit in style.py and returns the style.Roof it used (or None),
so its AC boxes can become a salvage source.

The ruin state decides what is drawn (see ruins.py):
  intact     halo, interior, roof
  damaged    halo, interior, roof with holes (roof items stay clear of them),
             rubble spilled out of the holes, cracks
  gutted     halo, interior with rubble and scorch, two roof fragments, the
             outer wall as broken segments; no roof items, no rooftop sources
  collapsed  a rubble heap on the ground, roof slabs, wall stubs; no halo,
             interior or roof
"""
import numpy as np

import ruins
import solar
import style
from gen_city import block_rng

INTACT, DAMAGED, GUTTED, COLLAPSED = 0, 1, 2, 3
STATE_NAMES = ["intact", "damaged", "gutted", "collapsed"]
## Share of the roofs with AC boxes whose boxes are a roof_ac salvage source,
## per district (residential, industrial, market, farmland). The others
## look the same but give nothing.
AC_SOURCE_SHARE = (0.22, 0.3, 0.35, 0.3)
## Chance of a solar installation, per district as above: a small set on a
## flat house roof, modules flush on a tile roof, and rack rows, a canopy or
## low ballasted rows on a large flat roof.
SOLAR_HOUSE = (0.04, 0.02, 0.05, 0.06)
SOLAR_TILES = (0.10, 0.03, 0.08, 0.10)
SOLAR_BIG = (0.22, 0.25, 0.2, 0.25)
## Chance of a diesel generator (a salvage source) on a flat roof, per
## district as above.
ROOF_GENERATOR = (0.012, 0.03, 0.03, 0.02)


## Two footprints overlap when they share more than OVERLAP_M2 or more than
## OVERLAP_SHARE of the smaller one (a shared wall is not an overlap).
## resolve_overlaps trims the smaller one, or drops it when less than
## KEEP_SHARE of it would be left.
OVERLAP_M2 = 1.0
OVERLAP_SHARE = 0.02
KEEP_SHARE = 0.7


def overlapping_pairs(buildings):
    """The pairs (i, j, shared area) of buildings whose footprints overlap."""
    from shapely.strtree import STRtree
    polys = [b.poly for b in buildings]
    tree = STRtree(polys)
    out = []
    for i, p in enumerate(polys):
        for j in tree.query(p):
            j = int(j)
            if j <= i or not p.intersects(polys[j]):
                continue
            a = p.intersection(polys[j]).area
            if a > OVERLAP_M2 or a > OVERLAP_SHARE * min(p.area, polys[j].area):
                out.append((i, j, a))
    return out


def resolve_overlaps(buildings):
    """Trims or drops buildings until no two footprints overlap. The
    smaller of a pair gives way. Returns (kept buildings, trimmed, dropped)."""
    trimmed = dropped = 0
    gone = set()
    for i, j, _ in sorted(overlapping_pairs(buildings), key=lambda t: -t[2]):
        if i in gone or j in gone:
            continue
        a, b = buildings[i], buildings[j]
        small, big, k = (a, b, i) if a.poly.area <= b.poly.area else (b, a, j)
        rest = small.poly.difference(big.poly.buffer(0.05, join_style="mitre"))
        parts = style.polys(rest)
        part = max(parts, key=lambda g: g.area) if parts else None
        if part is not None and part.area >= KEEP_SHARE * small.poly.area:
            small.poly = part.simplify(0.05)
            trimmed += 1
        else:
            gone.add(k)
            dropped += 1
    return [b for n, b in enumerate(buildings) if n not in gone], trimmed, dropped


class Building:
    __slots__ = ("poly", "mv", "kind", "district", "state", "opts", "id")

    def __init__(self, poly, mv, kind, district=0, state=INTACT, **opts):
        self.poly = poly
        self.mv = mv
        self.kind = kind
        self.district = district
        self.state = state
        self.opts = opts
        self.id = -1


def solar_hook(L, fn, rng):
    """A pre or post hook for the roof kit that adds one solar installation
    and queues its salvage source."""
    def hook(R):
        got = fn(R, rng)
        if got is not None:
            L.pending_sources.append(("solar_panels", got[0], got[1]))
    return hook


def roof_generator(L, rng):
    """A pre hook that puts a diesel generator on a flat roof and queues it
    as a source."""
    def hook(R):
        spot = solar.free_rect(R, 3.4, 1.6)
        if spot is None:
            return
        x, y, r = spot
        R.taken.append(r)
        Q = solar.Quads(R.c, R.ang)
        Q.grad(x + 0.3, y + 1.6, x + 3.7, y + 2.2, 0.0, 0.45, 0.0)
        Q.rect(x, y, x + 3.4, y + 1.6, 0.22)
        Q.rect(x + 0.2, y + 0.2, x + 2.2, y + 1.4, 0.27)
        for yy in np.arange(y + 0.15, y + 1.5, 0.12):
            Q.line(x + 2.5, yy, x + 3.25, yy, 0.04, 0.12)
        Q.line(x, y, x + 3.4, y, 0.06, 0.42)
        Q.line(x + 3.4, y, x + 3.4, y + 1.6, 0.06, 0.42)
        Q.line(x + 3.4, y + 1.6, x, y + 1.6, 0.06, 0.42)
        Q.line(x, y + 1.6, x, y, 0.06, 0.42)
        Q.rect(x + 0.45, y + 0.4, x + 0.75, y + 0.7, 0.04)
        Q.flush(L, "roofs", R.key)
        L.pending_sources.append(("diesel_generator", r, 0))
    return hook


def chain(*hooks):
    hooks = [h for h in hooks if h is not None]
    if not hooks:
        return None
    return lambda R: [h(R) for h in hooks]


def roof_big(L, b, rng):
    g = b.poly
    shape, rects, ang, c = style.roof_shape(g)
    if b.state == INTACT and shape == "rect" and g.area < 2500 and rng.random() < 0.35:
        style.draw_sheet_shed(L, g, b.mv, rng, rects, ang, c)
        return None
    pre = post = None
    if b.state != GUTTED and rng.random() < SOLAR_BIG[b.district]:
        width = style.min_width(g)
        long_roof = g.minimum_rotated_rectangle.area / max(width * width, 1e-6) > 2.2
        if long_roof or (b.district == 1 and rng.random() < 0.5):
            pre = solar_hook(L, solar.low_rows, rng)
        elif rng.random() < 0.6:
            pre = solar_hook(L, solar.tilted_rows, rng)
        else:
            post = solar_hook(L, solar.canopy, rng)
    gen = roof_generator(L, rng) if b.state != GUTTED and rng.random() < ROOF_GENERATOR[b.district] else None
    return style.draw_big(L, g, b.mv, rng, items=b.state != GUTTED, pre=chain(pre, gen), post=post)


def roof_house(L, b, rng):
    lot = b.poly
    shape, rects, ang, c = style.roof_shape(lot)
    chance = {"rect": 0.3, "L": 0.6}.get(shape, 0.0)
    if b.state != GUTTED and 40 < lot.area < 320 and rng.random() < chance:
        style.draw_tiled_house(L, lot, b.mv, rng, rects, ang, c)
        if rng.random() < SOLAR_TILES[b.district]:
            got = solar.flush_on_tiles(L, rects, ang, c, rng, style.chunk_key(lot))
            if got is not None:
                L.pending_sources.append(("solar_panels", got[0], got[1]))
        return None
    pre = None
    if b.state != GUTTED and rng.random() < SOLAR_HOUSE[b.district]:
        pre = solar_hook(L, solar.house_set, rng)
    gen = roof_generator(L, rng) if b.state != GUTTED and rng.random() < ROOF_GENERATOR[b.district] else None
    return style.draw_house(L, lot, b.mv, rng, items=b.state != GUTTED, pre=chain(pre, gen))


KINDS = {
    "big": (roof_big, True, style.HALO_BIG_M),
    "house": (roof_house, False, style.HALO_HOUSE_M),
}


def register_roof_sources(L, R, b, salvage, rng):
    """Some roofs with AC boxes (AC_SOURCE_SHARE) are a roof_ac source, its
    box round all the boxes (in the roof's frame). Gutted and collapsed
    buildings have no rooftop sources."""
    if salvage is None or R is None or not R.ac or b.state not in (INTACT, DAMAGED):
        return
    if rng.random() < AC_SOURCE_SHARE[b.district]:
        add_roof_source(salvage, "roof_ac", R, R.ac, b.id, amount=len(R.ac))


def add_poly_source(salvage, kind, poly, bid, amount=0, pad=0.3):
    """A source whose box is the smallest turned rectangle round a polygon."""
    rr = np.asarray(poly.minimum_rotated_rectangle.exterior.coords)
    e1, e2 = rr[1] - rr[0], rr[2] - rr[1]
    w, h = np.hypot(*e1), np.hypot(*e2)
    c = poly.minimum_rotated_rectangle.centroid
    return salvage.add(kind, c.x, c.y, float(np.arctan2(e1[1], e1[0])), w + 2 * pad, h + 2 * pad,
                       building=bid, amount=amount)


def add_roof_source(salvage, kind, R, rects, bid, amount=0, pad=0.3):
    """A source whose box covers the given roof rectangles, turned with the
    roof's long axis."""
    ang = np.radians(R.ang)
    cs, sn = np.cos(ang), np.sin(ang)
    pts = np.concatenate([np.asarray(r.exterior.coords) for r in rects])
    rel = pts - (R.c.x, R.c.y)
    lx = rel[:, 0] * cs + rel[:, 1] * sn
    ly = -rel[:, 0] * sn + rel[:, 1] * cs
    x0, x1, y0, y1 = lx.min() - pad, lx.max() + pad, ly.min() - pad, ly.max() + pad
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    cx, cy = R.c.x + mx * cs - my * sn, R.c.y + mx * sn + my * cs
    return salvage.add(kind, cx, cy, ang, x1 - x0, y1 - y0, building=bid, amount=amount)


def build_layers(water, roads, buildings, drawers=(), salvage=None, seed=11):
    """Draws roads, rail, every building (in id order) and the district
    modules' ground objects. drawers: functions f(L) that draw the rest
    (industrial yards, fields, market stalls' ground)."""
    L = style.Layers()
    style.draw_roads(L, roads, water)
    style.draw_rails(L, roads)
    for draw in drawers:
        draw(L)
    for b in buildings:
        b.id = L.add_building(b.poly, b.state, b.district)
        rng = block_rng(seed, b.poly)
        roof_fn, big, halo = KINDS[b.kind]
        if b.state == COLLAPSED:
            ruins.draw_collapsed(L, b, rng, salvage)
            continue
        style.draw_halo(L, b.poly, halo)
        style.draw_interior(L, b.poly, big, rng)
        if b.state == INTACT:
            R = roof_fn(L, b, rng)
        else:
            R = ruins.draw_ruined_roof(L, b, rng, roof_fn, big)
        register_roof_sources(L, R, b, salvage, rng)
        for kind, poly, amount in L.pending_sources:
            if salvage is not None and b.state in (INTACT, DAMAGED):
                add_poly_source(salvage, kind, poly, b.id, amount)
        L.pending_sources = []
    L.bid = -1
    return L
