"""Industrial district content (section 3 of the districts brief): factory
and process plant compounds in the street blocks of the industrial district.

Each industrial street block that is large enough becomes one fenced
compound, with a gate on the side nearest a road. A block larger than
COMPOUND_MAX_M2 (an estate, a works site) is tiled with compound plots and
service roads. Houses inside a compound are removed; large roofs already
there stay (they are the compound's halls).

Process plant (blocks with room: free ground over PLANT_MIN_FREE_M2 and over
PLANT_FREE_SHARE of the block, PLANT_SHARE of them): see plant.py. A plant
is built network-first: a trunk rack round the plant, rungs along the
internal roads, branches to every node (tank bund, pool with pump house,
process units, control building, yards), long single pipes between distant
nodes, dense manifolds in the units; pipe bridges wherever a run crosses a
road, and a passability check. Plants that face each other across a road
are joined by a rack on a pipe bridge.

Factory (the other blocks): a sawtooth shed with loading docks (the largest
hall, or a new one), a container yard or bus depot, an L workshop, a
chimney, a silo cluster with a conveyor gantry, tanks in a bund, equipment
yards.

Tanks, silos, chimneys, pump houses, control buildings, sheds and workshops
are buildings (walls, roofs, ruin states) of their own kinds.

Salvage sources come with what shows them: transformers, motors, pumps,
cabinets, valves, oil drums, cable drums and generators in yards, by the
units and by the racks; shipping containers in yards (CONTAINER_SOURCE_SHARE
of them) and container trucks at the docks.

A start, spawn, exit or cyst marker of the master scene that lies in a
compound keeps a clear circle of plant.KEEP_CLEAR_M round it.

How pipes are shaped and drawn is in pipes.py.
"""
import numpy as np
from shapely.geometry import LineString, Point
from shapely.ops import unary_union

import buildings as bl
import density
import equipment
import kit
import plant
import props
import style
from districts import INDUSTRIAL
from gen_city import block_rng
from pipes import conveyor, truss_variant

## The density pass (density.py). False builds the lots without it, to count
## what they have before it.
DENSITY = True
## Street blocks with at least this share in the industrial district, and
## at least this large (m2), become compounds.
MIN_SHARE = 0.5
MIN_BLOCK_M2 = 2500.0
FENCE_INSET_M = 2.0
## A block larger than this (m2) is tiled with rows of compound plots
## PLOT_DEPTH_M deep; a plant's plot is PLANT_PLOT_M wide and a factory's
## FACTORY_PLOT_M (ranges, m). Service roads ESTATE_ROAD_M wide run between
## the plots.
COMPOUND_MAX_M2 = 45000.0
PLOT_DEPTH_M = (108.0, 150.0)
PLANT_PLOT_M = (170.0, 240.0)
FACTORY_PLOT_M = (110.0, 160.0)
ESTATE_ROAD_M = 14.0
## Process plants need this much free ground (m2) and this share of the
## block free; PLANT_SHARE of the blocks that qualify become plants.
PLANT_MIN_FREE_M2 = 9000.0
PLANT_FREE_SHARE = 0.55
PLANT_SHARE = 0.75
## Share of yard containers that are salvage sources (the rest are sealed).
CONTAINER_SOURCE_SHARE = 0.5
## Share of factories whose yard is a bus depot instead of a container yard.
BUS_DEPOT_SHARE = 0.1


# -------------------------------------------------------------- buildings

def roof_saw(L, b, rng):
    """A sawtooth roof: north-light bays across the long axis, each a shaded
    slope and a light glazed strip."""
    g = b.poly
    R = style.Roof(L, g, style.roof_value(b.mv) * rng.uniform(1.0, 1.25), rng)
    R.fill(g, R.v)
    bay = rng.uniform(6.0, 9.0)
    for x in np.arange(R.x0 + 0.4, R.x1 - 0.4, bay):
        xb = min(x + bay, R.x1)
        R.fill(R.rect(x, R.y0, xb - 1.3, R.y1).intersection(g), min(R.v * 1.35, 0.16))
        R.fill(R.rect(xb - 1.3, R.y0, xb, R.y1).intersection(g), 0.2)
        R.stroke(R.line([(xb, R.y0), (xb, R.y1)]).intersection(g), 0.14, style.DETAIL_LINE_V)
        R.stroke(R.line([(xb - 1.3, R.y0), (xb - 1.3, R.y1)]).intersection(g), 0.06, 0.03)
        for y in np.arange(R.y0 + 1.5, R.y1 - 0.5, 1.5):
            R.stroke(R.line([(xb - 1.25, y), (xb - 0.05, y)]).intersection(g), 0.04, 0.1)
    R.ring(g, style.OUTLINE_W * 1.3, style.OUTLINE_V)
    return None


def roof_round(L, b, rng):
    """A round tank or silo roof: rings, radial seams, a central vent; silos
    have a lighter cone, tanks a stair round the rim."""
    g = b.poly
    key = style.chunk_key(g)
    c = g.centroid
    r = np.sqrt(g.area / np.pi)
    silo = b.kind == "silo"
    v = style.roof_value(b.mv) * (1.6 if silo else 1.3)
    L.fill("roofs", g, v, chunk=key)
    inner = kit.disc(c.x, c.y, r * 0.62)
    L.fill("roofs", inner, min(v * (1.35 if silo else 1.1), 0.2), chunk=key)
    n = int(10 + r)
    for k in range(n):
        a = 2 * np.pi * k / n
        L.line("roofs", LineString([(c.x + np.cos(a) * r * 0.15, c.y + np.sin(a) * r * 0.15),
                                    (c.x + np.cos(a) * r * 0.97, c.y + np.sin(a) * r * 0.97)]), 0.05, 0.05, chunk=key)
    L.line("roofs", inner.exterior, 0.08, style.DETAIL_LINE_V * 0.8, chunk=key)
    L.fill("roofs", kit.disc(c.x, c.y, max(0.4, r * 0.12), 10), 0.03, chunk=key)
    if not silo:
        a0 = rng.uniform(0, 2 * np.pi)
        arc = [(c.x + np.cos(a0 + t) * r * 0.9, c.y + np.sin(a0 + t) * r * 0.9) for t in np.linspace(0, 1.2, 10)]
        L.line("roofs", LineString(arc), 0.5, 0.2, chunk=key)
    L.line("roofs", g.exterior, style.OUTLINE_W, style.OUTLINE_V, chunk=key)
    return None


def roof_chimney(L, b, rng):
    g = b.poly
    key = style.chunk_key(g)
    c = g.centroid
    r = np.sqrt(g.area / np.pi)
    L.fill("roofs", g, 0.22, chunk=key)
    L.fill("roofs", kit.disc(c.x, c.y, r * 0.72, 16), 0.005, chunk=key)
    L.line("roofs", g.exterior, 0.2, style.OUTLINE_V, chunk=key)
    L.line("roofs", kit.disc(c.x, c.y, r * 0.86, 16).exterior, 0.06, 0.1, chunk=key)
    return None


def roof_flat_small(L, b, rng):
    return style.draw_house(L, b.poly, b.mv, rng, items=b.state != bl.GUTTED)


def roof_shelter(L, b, rng):
    """A pump or compressor shelter: a corrugated roof with a ridge."""
    g = b.poly
    R = style.Roof(L, g, style.roof_value(b.mv) * rng.uniform(1.1, 1.4), rng)
    R.fill(g, R.v)
    for x in np.arange(R.x0 + 0.5, R.x1, 0.9):
        R.stroke(R.line([(x, R.y0), (x, R.y1)]).intersection(g), 0.05, R.v * 0.7)
    R.stroke(R.line([(R.x0, (R.y0 + R.y1) / 2), (R.x1, (R.y0 + R.y1) / 2)]).intersection(g), 0.12, style.DETAIL_LINE_V)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return None


def roof_cooling(L, b, rng):
    """A row of cooling tower cells: a fan stack in each cell."""
    g = b.poly
    R = style.Roof(L, g, style.roof_value(b.mv) * 1.2, rng)
    R.fill(g, R.v)
    n = max(1, int(round((R.x1 - R.x0) / 6.5)))
    step = (R.x1 - R.x0) / n
    rad = min(step, R.y1 - R.y0) / 2 - 0.9
    for i in range(n):
        c = R.rect(R.x0 + i * step, R.y0, R.x0 + (i + 1) * step, R.y1).centroid
        L.fill("roofs", kit.disc(c.x, c.y, rad + 0.5, 18), min(R.v * 1.5, 0.2), chunk=R.key)
        L.fill("roofs", kit.disc(c.x, c.y, rad, 18), 0.02, chunk=R.key)
        for a in np.arange(0, np.pi, np.pi / 3):
            L.line("roofs", LineString([(c.x - np.cos(a) * rad, c.y - np.sin(a) * rad), (c.x + np.cos(a) * rad, c.y + np.sin(a) * rad)]),
                   0.3, 0.09, chunk=R.key)
        if i:
            R.stroke(R.line([(R.x0 + i * step, R.y0), (R.x0 + i * step, R.y1)]), 0.12, style.DETAIL_LINE_V)
    R.ring(g, style.OUTLINE_W * 1.2, style.OUTLINE_V)
    return None


def roof_kiln(L, b, rng):
    """A rotary kiln from above: a long shell with a highlight along it and
    its tyres across."""
    g = b.poly
    R = style.Roof(L, g, 0.12, rng)
    R.fill(g, R.v)
    ym = (R.y0 + R.y1) / 2
    R.stroke(R.line([(R.x0 + 0.5, ym - 0.6), (R.x1 - 0.5, ym - 0.6)]), 1.1, 0.2)
    R.stroke(R.line([(R.x0 + 0.5, ym + 1.3), (R.x1 - 0.5, ym + 1.3)]), 0.9, 0.05)
    for t in (0.12, 0.5, 0.88):
        x = R.x0 + (R.x1 - R.x0) * t
        R.fill(R.rect(x - 0.6, R.y0 - 0.0, x + 0.6, R.y1), 0.2)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return None


def roof_tower(L, b, rng):
    """A preheater tower: a square deck with cyclones on it."""
    g = b.poly
    R = style.Roof(L, g, style.roof_value(b.mv) * 1.5, rng)
    R.fill(g, R.v)
    w, h = R.x1 - R.x0, R.y1 - R.y0
    R.stroke(R.rect(R.x0 + 1.2, R.y0 + 1.2, R.x1 - 1.2, R.y1 - 1.2).exterior, 0.15, style.DETAIL_LINE_V)
    for tx, ty in ((0.3, 0.3), (0.7, 0.3), (0.5, 0.7)):
        c = R.rect(R.x0 + w * tx - 0.1, R.y0 + h * ty - 0.1, R.x0 + w * tx + 0.1, R.y0 + h * ty + 0.1).centroid
        L.fill("roofs", kit.disc(c.x, c.y, min(w, h) * 0.16, 14), 0.2, chunk=R.key)
        L.fill("roofs", kit.disc(c.x, c.y, min(w, h) * 0.07, 10), 0.03, chunk=R.key)
    R.ring(g, style.OUTLINE_W * 1.3, style.OUTLINE_V)
    return None


bl.KINDS.update({
    "shelter": (roof_shelter, False, style.HALO_HOUSE_M),
    "cooling": (roof_cooling, False, style.HALO_HOUSE_M),
    "kiln": (roof_kiln, False, 3.0),
    "tower": (roof_tower, True, style.HALO_BIG_M),
    "saw": (roof_saw, True, style.HALO_BIG_M),
    "tank": (roof_round, True, 3.0),
    "silo": (roof_round, True, 3.5),
    "chimney": (roof_chimney, False, 2.0),
    "control": (roof_flat_small, False, style.HALO_HOUSE_M),
    "pumphouse": (roof_flat_small, False, style.HALO_HOUSE_M),
    "workshop": (bl.roof_big, True, style.HALO_BIG_M),
})


# -------------------------------------------------------------- compounds

class Compound:
    """One industrial block being built: its fenced area and frame, its free
    space, the drawing calls it queues, and its halls."""

    def __init__(self, site, area, rng):
        self.site, self.rng = site, rng
        self.area = area
        self.F = kit.Frame(area)
        self.halls = [b.poly for b in site.buildings if b.kind != "house" and b.poly.intersects(area)]
        blocked = unary_union([h.buffer(3.0) for h in self.halls]) if self.halls else None
        self.space = kit.Space(area, blocked)
        for _, x, y in getattr(site, "markers", []):
            if area.contains(Point(x, y)):
                self.space.take(Point(x, y).buffer(plant.KEEP_CLEAR_M))
        self.ops = []
        c = area.centroid
        self.mv = float(site.sampler.value(c.x, c.y))
        # What stands on the lot (footprints), for the density pass and its
        # counts; the lot's type ("plant", "factory", "depot", "cement").
        self.things = list(self.halls)
        self.lot = "factory"
        self.bunds = []

    def draw(self, fn):
        self.ops.append(fn)

    def thing(self, geom):
        self.things.append(geom)

    def counts(self):
        """How many big, medium and small things stand on the lot."""
        out = {"big": 0, "medium": 0, "small": 0}
        for g in self.things:
            out[density.size_class(g.area)] += 1
        return out

    def building(self, poly, kind):
        b = bl.Building(poly, self.mv, kind)
        self.site.buildings.append(b)
        self.space.take(poly.buffer(1.5))
        self.thing(poly)
        return b

    def source(self, kind, x, y, ang):
        S = self.site.salvage
        seed = int(self.rng.integers(1 << 30))
        self.thing(equipment.footprint(kind, x, y, ang))
        self.draw(lambda L: equipment.add_source(S, L, kind, x, y, ang, np.random.default_rng(seed)))

    def vehicle(self, salvage, kind, x, y, ang, size, variant):
        """Parks a vehicle prop on the lot (see props.add_vehicle)."""
        if props.add_vehicle(self.site.props, salvage, kind, x, y, ang, size, variant):
            self.thing(props.car_rect(x, y, ang, size))

    def place(self, w, h, margin=1.5, region=None):
        return self.space.place(self.F, w, h, self.rng, margin=margin, region=region)

    def corner(self, r):
        """The local (x1, y1) corner of a rectangle made by place()."""
        return self.F.to_local(*r.exterior.coords[2])

    def free_area(self):
        free = self.area
        for t in self.space.taken:
            free = free.difference(t)
        return free


def tank_bund(cp, x0, y0, x1, y1):
    """A bund (a low wall) round round tanks and empty tank pads."""
    F, rng = cp.F, cp.rng
    w, h = x1 - x0, y1 - y0
    d = float(min(rng.uniform(8.0, 16.0), min(w, h) - 4.0))
    if d < 6.0:
        return
    cols, rows = max(1, int((w - 2) // (d * 1.5))), max(1, int((h - 2) // (d * 1.5)))
    bund = F.rect(x0, y0, x1, y1)
    cp.thing(bund)
    cp.bunds.append(bund)
    cp.draw(lambda L: (kit.pave(L, bund, 0.11, 0.9, sub="groundlines", edge=False),
                       L.line("interiors", bund.exterior, 0.7, 0.24)))
    for i in range(cols):
        for j in range(rows):
            px, py = F.pt(x0 + (i + 0.5) * w / cols, y0 + (j + 0.5) * h / rows)
            if rng.random() < 0.22:
                pad = kit.disc(px, py, d / 2 + 0.3)
                cp.draw(lambda L, g=pad: (L.fill("interiors", g, 0.2), L.line("interiors", g.exterior, 0.12, 0.32)))
            else:
                cp.building(kit.disc(px, py, d / 2), "tank")


def yard(cp, x0, y0, x1, y1, kinds=None):
    """An equipment yard: gravel, a light fence, and 2 to 4 pieces of
    equipment that are salvage sources."""
    F, rng = cp.F, cp.rng
    g = F.rect(x0, y0, x1, y1)
    cp.thing(g)
    gate = g.exterior.interpolate(0.1, normalized=True)
    cp.draw(lambda L: (kit.pave(L, g, 0.12, 0.9, sub="interiors"), kit.fence(L, g.exterior, rng, gate=gate, v=0.26)))
    kinds = kinds or ["transformer", "control_cabinet", "cable_drum", "oil_drums", "diesel_generator",
                      "electric_motor"]
    picks = list(rng.choice(kinds, size=min(len(kinds), int(rng.integers(2, 5))), replace=False))
    xs = np.linspace(x0 + 1.5, x1 - 1.5, len(picks) + 1)
    for k, xa, xb in zip(picks, xs[:-1], xs[1:]):
        w, h = equipment.SIZES[k]
        if xb - xa < w + 0.4 or y1 - y0 < h + 2:
            continue
        px, py = F.pt((xa + xb) / 2, rng.uniform(y0 + h / 2 + 1, y1 - h / 2 - 1))
        cp.source(str(k), px, py, F.rad)


def bus_depot(cp):
    """A bus depot: rows of parked buses on paving (each a bus source)."""
    F, rng = cp.F, cp.rng
    cat = props.CATALOGUE.get("bus", [])
    if not cat:
        return
    got = cp.place(rng.uniform(30, 50), rng.uniform(26, 34), margin=2.0)
    if got is None:
        return
    x, y, r = got
    xb, yb = cp.corner(r)
    cp.thing(r)
    cp.lot = "depot"
    cp.draw(lambda L: kit.pave(L, r, 0.19, 0.9, sub="groundlines"))
    for row_y in (y + 7.0, yb - 7.0):
        xx = x + 2.5
        while xx < xb - 2.5:
            v = int(rng.integers(len(cat)))
            ln, wd = cat[v]["length_m"], cat[v]["width_m"]
            if rng.random() < 0.75:
                px, py = F.pt(xx, row_y)
                cp.vehicle(cp.site.salvage, "bus", px, py, F.rad + np.pi / 2 + rng.normal(0, 0.03), (ln, wd), v)
            xx += wd + rng.uniform(1.2, 2.0)


def container_yard(cp, region=None, n_max=24):
    """A container yard: rows of shipping containers on paving."""
    F, rng = cp.F, cp.rng
    cat = props.CATALOGUE.get("container", [])
    if not cat:
        return
    got = cp.place(rng.uniform(20, 40), rng.uniform(14, 26), margin=2.0, region=region)
    if got is None:
        return
    x, y, r = got
    xb, yb = cp.corner(r)
    cp.thing(r)
    cp.draw(lambda L: kit.pave(L, r, 0.17, 0.9, sub="groundlines"))
    n = 0
    for row in np.arange(y + 1.6, yb - 1.4, 3.4):
        xx = x + 1.0
        while xx < xb - 2 and n < n_max:
            v = int(rng.integers(len(cat)))
            ln, wd = cat[v]["length_m"], cat[v]["width_m"]
            if xx + ln > xb - 1:
                break
            if rng.random() < 0.8:
                px, py = F.pt(xx + ln / 2, row)
                ang = F.rad + (np.pi if rng.random() < 0.5 else 0.0) + rng.normal(0, 0.01)
                S = cp.site.salvage if rng.random() < CONTAINER_SOURCE_SHARE else None
                cp.vehicle(S, "container", px, py, ang, (ln, wd), v)
                n += 1
            xx += ln + rng.uniform(0.4, 1.2)


def docks(cp, hall):
    """Loading docks along one long side of a hall: door marks, an apron,
    and trucks backed up to some of them (container trucks are sources)."""
    F = kit.Frame(hall)
    rng = cp.rng
    side = 1 if rng.random() < 0.5 else -1
    y = F.y1 if side > 0 else F.y0
    apron = F.rect(F.x0 + 2, min(y, y + 14 * side), F.x1 - 2, max(y, y + 14 * side)).intersection(cp.area)
    others = [h for h in cp.halls if h is not hall]
    if others:
        apron = apron.difference(unary_union(others).buffer(0.5))
    apron = kit.largest(apron)
    if apron is None or apron.area < 60:
        return
    cp.space.take(apron)
    doors = list(np.arange(F.x0 + 5, F.x1 - 4, rng.uniform(5.5, 8.0)))

    def draw(L):
        kit.pave(L, apron, 0.2, 0.9, sub="groundlines")
        for xd in doors:
            L.fill("interiors", F.rect(xd - 1.6, min(y, y + 1.4 * side), xd + 1.6, max(y, y + 1.4 * side)), 0.05)
            L.line("interiors", F.line([(xd - 1.8, y + 1.5 * side), (xd + 1.8, y + 1.5 * side)]), 0.12, 0.45)
    cp.draw(draw)
    # The trucks that call at a dock: the ones with a spawn weight (not the
    # tanker or the dump truck).
    cat = props.CATALOGUE.get("truck", [])
    trucks = [i for i, e in enumerate(cat) if e.get("weight", 1.0) > 0]
    for xd in doors:
        if not trucks or rng.random() > 0.35:
            continue
        v = trucks[int(rng.integers(len(trucks)))]
        ln, wd = cat[v]["length_m"], cat[v]["width_m"]
        px, py = F.pt(xd, y + side * (ln / 2 + 1.6))
        if apron.buffer(2.0).contains(Point(px, py)):
            cp.vehicle(cp.site.salvage, "truck", px, py, F.rad + side * np.pi / 2, (ln, wd), v)


def silos(cp, d_min=7.0):
    F, rng = cp.F, cp.rng
    n = int(rng.integers(3, 7))
    d = rng.uniform(d_min, 10.0)
    w, h = n * (d + 1.0) + 2, d + 4
    got = cp.place(w, h, margin=2.0)
    if got is None:
        return None
    x, y, _ = got
    for i in range(n):
        px, py = F.pt(x + 1.5 + d / 2 + i * (d + 1.0), y + 2 + d / 2)
        cp.building(kit.disc(px, py, d / 2), "silo")
    return F.pt(x + w / 2, y + h / 2)


def factory(site, cp):
    F, rng = cp.F, cp.rng
    main = None
    if cp.halls:
        biggest = max(cp.halls, key=lambda g: g.area)
        for b in site.buildings:
            if b.poly is biggest:
                if b.kind == "big" and style.roof_shape(b.poly)[0] == "rect":
                    b.kind = "saw"
                main = biggest
                break
    if main is None:
        got = cp.place(min(F.w * 0.6, rng.uniform(40, 80)), min(F.h * 0.55, rng.uniform(24, 42)), margin=4.0)
        if got is not None:
            main = got[2]
            cp.building(main, "saw")
            cp.halls.append(main)
    if main is not None:
        docks(cp, main)
    if rng.random() < BUS_DEPOT_SHARE:
        bus_depot(cp)
    else:
        container_yard(cp)
    if rng.random() < 0.6:
        w1, h1, leg = rng.uniform(18, 30), rng.uniform(9, 14), rng.uniform(8, 12)
        got = cp.place(w1, h1 + 9, margin=3.0)
        if got is not None:
            x, y, r = got
            cp.space.taken.pop()
            cp.building(F.poly([(x, y), (x + w1, y), (x + w1, y + h1), (x + leg, y + h1), (x + leg, y + h1 + 9),
                                (x, y + h1 + 9)]), "workshop")
    if rng.random() < 0.55:
        got = cp.place(5.0, 5.0, margin=3.0)
        if got is not None:
            c = got[2].centroid
            cp.building(kit.disc(c.x, c.y, rng.uniform(1.8, 2.4), 16), "chimney")
    if rng.random() < 0.5:
        s = silos(cp)
        if s is not None and main is not None:
            q = main.boundary.interpolate(main.boundary.project(Point(s)))
            gantry = LineString([s, (q.x, q.y)])
            if 5 < gantry.length < 60:
                cp.draw(lambda L: conveyor(L, gantry))
    if rng.random() < 0.5:
        got = cp.place(rng.uniform(22, 36), rng.uniform(16, 24), margin=3.0)
        if got is not None:
            x, y, r = got
            tank_bund(cp, x, y, *cp.corner(r))
    for _ in range(int(rng.integers(1, 3))):
        got = cp.place(rng.uniform(14, 22), rng.uniform(8, 12), margin=2.0)
        if got is not None:
            x, y, r = got
            yard(cp, x, y, *cp.corner(r))


def cement_works(site, cp):
    """A lot of the cement works: a mill hall, a rotary kiln between its
    preheater tower and its cooler house, silo clusters with conveyors, and
    equipment yards. The density pass adds the material heaps and the dump
    trucks."""
    F, rng = cp.F, cp.rng
    cp.lot = "cement"
    main = max(cp.halls, key=lambda g: g.area) if cp.halls else None
    if main is None:
        got = cp.place(min(F.w * 0.5, rng.uniform(36, 60)), min(F.h * 0.4, rng.uniform(22, 34)), margin=4.0)
        if got is not None:
            main = got[2]
            cp.building(main, "workshop")
            cp.halls.append(main)
    w = rng.uniform(44.0, 58.0) + 22.0
    got = cp.place(w, 11.0, margin=3.0) if F.w > w + 12 else None
    if got is not None:
        x, y, _ = got
        cp.building(F.rect(x, y, x + 11.0, y + 11.0), "tower")
        cp.building(F.rect(x + 11.0, y + 3.2, x + w - 11.0, y + 7.8), "kiln")
        cp.building(F.rect(x + w - 11.0, y + 0.5, x + w, y + 10.5), "workshop")
    for _ in range(int(rng.integers(1, 3))):
        s = silos(cp, d_min=9.0)
        if s is not None and main is not None:
            q = main.boundary.interpolate(main.boundary.project(Point(s)))
            gantry = LineString([s, (q.x, q.y)])
            if 5 < gantry.length < 70:
                cp.draw(lambda L, g=gantry: conveyor(L, g))
    for _ in range(int(rng.integers(1, 3))):
        got = cp.place(rng.uniform(14, 22), rng.uniform(8, 12), margin=2.0)
        if got is not None:
            x, y, r = got
            yard(cp, x, y, *cp.corner(r))


def truss_stats(overhead):
    """How many overhead racks have each truss variant, and the middle (px)
    of the two longest of each, for looking at them in the game."""
    out = {}
    for runs in overhead.values():
        for r in runs:
            if r.rack:
                out.setdefault(truss_variant(r), []).append(r)
    res = {}
    for k, runs in out.items():
        longest = sorted(runs, key=lambda r: -r.length)[:2]
        res[k] = {"racks": len(runs), "length_m": round(sum(r.length for r in runs)),
                  "examples_px": [[round(c.x * props.PX_PER_M), round(c.y * props.PX_PER_M)]
                                  for c in (r.centre().interpolate(0.5, normalized=True) for r in longest)]}
    return res


def in_cement_works(area):
    x0, y0, x1, y1 = density.CEMENT_BOX_M
    c = area.centroid
    return x0 <= c.x <= x1 and y0 <= c.y <= y1


def plots(blk, rng):
    """Compound plots in an industrial street block: (plot, kind) with kind
    "plant", "factory" or None (not decided). A block up to COMPOUND_MAX_M2
    is one compound. A larger one (an estate or a works site) is tiled with
    rows of plots PLOT_DEPTH_M deep; in a row, a process plant's plot is
    PLANT_PLOT_M wide and a factory's FACTORY_PLOT_M. The gaps between
    plots (ESTATE_ROAD_M) are service roads. Returns (plots, service road
    polygons, centre lines of the service roads)."""
    if blk.area <= COMPOUND_MAX_M2:
        return [(blk, None)], [], []
    F = kit.Frame(blk)
    out, roads, axes = [], [], []
    half = ESTATE_ROAD_M / 2
    y = F.y0 + ESTATE_ROAD_M / 2
    while y < F.y1 - 40:
        ph = rng.uniform(*PLOT_DEPTH_M)
        x = F.x0 + ESTATE_ROAD_M / 2
        while x < F.x1 - 40:
            kind = "plant" if rng.random() < PLANT_SHARE else "factory"
            pw = rng.uniform(*(PLANT_PLOT_M if kind == "plant" else FACTORY_PLOT_M))
            r = F.rect(x, y, x + pw, y + ph)
            g = kit.largest(r.intersection(blk))
            if g is not None and g.area > 0.7 * r.area:
                out.append((g, kind))
            roads.append(F.rect(x + pw, y, x + pw + ESTATE_ROAD_M, y + ph).intersection(blk))
            axes.append(F.line([(x + pw + half, y - half), (x + pw + half, y + ph + half)]))
            x += pw + ESTATE_ROAD_M
        roads.append(F.rect(F.x0, y + ph, F.x1, y + ph + ESTATE_ROAD_M).intersection(blk))
        axes.append(F.line([(F.x0, y + ph + half), (F.x1, y + ph + half)]))
        y += ph + ESTATE_ROAD_M
    return out, roads, axes


def build(site):
    """Turns the industrial street blocks into compounds."""
    n_factories = 0
    plants, areas, estates = [], [], []
    for blk in site.blocks_of(INDUSTRIAL, MIN_SHARE, MIN_BLOCK_M2):
        rng = block_rng(41, blk)
        parts, service, axes = plots(blk, rng)
        lots = []
        estates.append((blk, service, axes, lots, rng))
        if service:
            site.drawers.append(lambda L, g=service: [kit.pave(L, r, 0.24, 0.8, sub="groundlines") for r in g])
        for plot, kind in parts:
            area = kit.largest(plot.buffer(-FENCE_INSET_M, join_style="mitre"))
            if area is None or area.area < MIN_BLOCK_M2 * 0.7:
                continue
            site.remove_buildings_in(area)
            cp = Compound(site, area, rng)
            free = cp.free_area().area
            gates = [kit.nearest_edge_point(area, site.road_union_near(area, 80.0), area.exterior.interpolate(0))]
            P = None
            wanted = kind == "plant" or (kind is None and rng.random() < PLANT_SHARE)
            if wanted and free >= PLANT_MIN_FREE_M2 and free >= PLANT_FREE_SHARE * area.area:
                P = plant.build_plant(site, cp)
            if P is not None:
                plants.append(P)
                cp.lot, cp.plant = "plant", P
                gates = P.gates or gates
                got = cp.place(10, 8, margin=2.0)
                if got is not None:
                    yard(cp, got[0], got[1], *cp.corner(got[2]), kinds=["transformer"])
            else:
                if DENSITY and in_cement_works(area):
                    cement_works(site, cp)
                else:
                    factory(site, cp)
                    if in_cement_works(area):
                        cp.lot = "cement"
                n_factories += 1
            areas.append(area)
            lots.append(cp)
            ops = cp.ops

            def draw(L, area=area, ops=ops, gates=gates, rng=rng):
                kit.pave(L, area, 0.15, 0.5, sub="groundlines", edge=False)
                for fn in ops:
                    fn(L)
                kit.fence(L, area.exterior, rng, gates=gates, v=0.3)
            site.drawers.append(draw)
            site.solid_extra.append(area)
    plant.npc_access(site, plants)
    for P in plants:
        P.finish()
    pipes_m = {"overhead_racks": sum(r.length for P in plants for r in P.runs if r.role in plant.OVERHEAD_ROLES),
               "ground_pipes": sum(r.length - sum(b[1] - b[0] for b in r.bridges) for P in plants for r in P.runs
                                   if r.role not in plant.OVERHEAD_ROLES),
               "thin_pipes": 0.0}
    made = {"huts": 0, "huts_ruined": 0, "clutter": 0, "sub_buildings": 0, "sub_buildings_taken_out": 0, "road_racks": 0,
            "stubs": 0, "lot_racks": 0, "houses_removed": 0}
    parked = []
    overhead = {"road": [], "stub": [], "lot": []}
    n_props = len(site.props.items)
    for blk, service, axes, lots, _ in estates if DENSITY else ():
        # The racks and the vehicles of the roads draw their own random
        # numbers, so the lots do not change with them.
        rng = block_rng(59, blk)
        racks = density.road_racks(site, blk, axes, rng) if axes else []
        overhead["road"] += racks
        made["road_racks"] += len(racks)
        pipes_m["overhead_racks"] += sum(r.length for r in racks)
        pipes_m["thin_pipes"] += sum(getattr(r, "thin_m", 0.0) for r in racks)
        for cp in lots:
            made["houses_removed"] += density.clear_houses(site, cp)
            if cp.lot == "plant":
                W, extra = density.fill_plant(site, cp, cp.plant), []
                link = density.stub(site, racks, cp.plant.trunk.centre(), "tee", rng)
            else:
                W, rack = density.fill_factory(site, cp, cp.lot == "cement")
                extra = [rack] if rack is not None else []
                made["lot_racks"] += len(extra)
                link = density.stub(site, racks, max(cp.halls, key=lambda g: g.area) if cp.halls else None, "equip", rng)
            made["stubs"] += link is not None
            overhead["lot"] += extra
            overhead["stub"] += [link] if link is not None else []
            pipes_m["overhead_racks"] += sum(r.length for r in extra + ([link] if link is not None else []))
            pipes_m["thin_pipes"] += W.flush()
            made["sub_buildings"] += len(W.buildings)
            made["sub_buildings_taken_out"] += W.removed
            parked += W.parked
        parked += density.road_vehicles(site, service, racks, [cp.area for cp in lots], rng)
    hut, clutter = props.KINDS.index("hut"), props.KINDS.index("clutter")
    ruin = {i for i, e in enumerate(props.CATALOGUE.get("hut", [])) if e.get("ruin")}
    for it in site.props.items[n_props:]:
        made["huts"] += it[0] == hut
        made["huts_ruined"] += it[0] == hut and it[6] in ruin
        made["clutter"] += it[0] == clutter
    links = plant.link_plants(site, plants, areas, np.random.default_rng(47)) if plants else []
    pipes_m["overhead_racks"] += sum(k["span_m"] for k in links)
    site.stats["industrial"] = {"plants": len(plants), "factories": n_factories, "plant_links": len(links)}
    site.stats["plant_network"] = plant.summary(plants, links)
    every = [cp for *_, lots, _ in estates for cp in lots]
    overhead["plant"] = [r for P in plants for r in P.runs if r.role in plant.OVERHEAD_ROLES]
    overhead["link"] = [k["run"] for k in links]
    vehicles = {}
    for name, where, _, _ in parked:
        vehicles.setdefault(name, {}).setdefault(where, 0)
        vehicles[name][where] += 1
    site.stats["density"] = {"lots": density.stats(every), "per_lot": density.lot_list(every),
                             "pipe_m": {k: round(v) for k, v in pipes_m.items()},
                             "made": {k: int(v) for k, v in made.items()},
                             "vehicles": vehicles,
                             "truss": truss_stats(overhead),
                             "racks_near_roofs_m": {k: density.near_roofs(site, [r.centre() for r in v])
                                                    for k, v in overhead.items()},
                             "vehicle_list": [[name, where, round(x * props.PX_PER_M), round(y * props.PX_PER_M)]
                                              for name, where, x, y in parked]}
    return site
