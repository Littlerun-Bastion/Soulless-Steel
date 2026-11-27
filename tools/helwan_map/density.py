"""The industrial density pass (the industrial density brief).

Every industrial lot should read at three scales: big things (over BIG_M2:
sheds, bunds, pools, unit pads), medium ones (MEDIUM_M2 to BIG_M2) and small
ones, about 1 to MEDIUM_PER_BIG to SMALL_PER_BIG by count, and should have
little bare ground. The lots come out of industrial.py and plant.py with
mostly big things. This pass adds the rest until the lot has that many for
each big thing, or one medium thing for every MEDIUM_GROUND_M2 and one small
one for every SMALL_GROUND_M2 of open ground, whichever is more. They are
grouped, not spread evenly: medium things within GROUP_M of a big one or
along the fence, small things round the medium and big ones:

- Medium: sub-buildings of SUB_BUILDING_M2 or more (substations, shelters,
  workshops, cooling tower cells, tanks of TANK_BUILDING_M across or more:
  real buildings with a roof and a ruin state), and things that are drawn
  only: smaller tanks, vessel batteries, air-cooler banks, laydown squares,
  fenced pens, rows of portable cabins.
- Small: columns (drawn only), huts (props of kind "hut": they break like market stalls,
  and some are ruins from the start, by the ruin state a building there
  would have), and clutter (props of kind "clutter": drums, pallets, cable
  reels, cabinets, skids ...; sprites with no body).
- Thin pipes (0.1 to 0.3 m, drawn on the ground, no obstacle): a firewater
  ring round every lot with hydrants on it, tracing lines beside the
  overhead racks, and a line from every new tank, vessel battery, cooler
  and shelter to the nearest rack or hall. Each joins something at both
  ends.
- Overhead racks outside the plants (pipes.Run, raised from end to end, no
  obstacle): one along the service roads of an estate (road_racks), a stub
  from it to each lot's trunk or hall, and a rack between the hall and a
  tank of a factory. No rack, with its supports, comes within ROOF_CLEAR_M
  of a building footprint; a stub or a lot rack only touches the wall of
  the building it ends at. A road that is built over has no rack.
- Vehicles: tankers at loading racks and beside bunds, dump trucks at the
  cement works' heaps and silos and at laydown squares, a few of each on
  the paved service roads of the estates. Each stands inside a lot or on a
  service road, in the industrial district and in the play area
  (may_park).

Nothing here is an obstacle, and nothing under SUB_BUILDING_M2 is a
building (a mecha close to a footprint counts as indoors). In a process
plant the player's check runs again with the new buildings, and the ones
that would cut ground off are taken out again.

Every lot keeps a list of what stands on it (Compound.things); stats()
counts it by size and gives the built cover. industrial.DENSITY switches the
pass off, to count what the lots have without it.
"""
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import nearest_points, substring, unary_union
from shapely.strtree import STRtree

import kit
import plant
import props
import ruins
from districts import INDUSTRIAL
from pipes import Run, draw_run, group_width, perp_segment, rack_pipes, strut_frame

## Size classes by footprint (m2), and how many medium and small things a
## lot gets for each big one.
BIG_M2 = 400.0
MEDIUM_M2 = 30.0
MEDIUM_PER_BIG = 4
SMALL_PER_BIG = 15
## A building of this footprint or more is a real building; a smaller one is
## a hut (a prop) or is drawn only.
SUB_BUILDING_M2 = 60.0
## Tanks: the diameter from which a tank is a building (over SUB_BUILDING_M2),
## the share of the tanks that are that large, the largest diameter.
TANK_BUILDING_M = 9.0
TANK_BUILDING_SHARE = 0.3
TANK_MAX_M = 10.5
## New things are placed within this distance of a big thing.
GROUP_M = 16.0
## Open ground (m2) for each medium and each small thing, and the most of
## each a lot gets.
MEDIUM_GROUND_M2 = 450.0
SMALL_GROUND_M2 = 110.0
MAX_MEDIUM, MAX_SMALL = 40, 160
## Share of the medium things that are placed along the fence.
EDGE_SHARE = 0.25
## Thin pipes: width range (m), grey, the firewater ring's inset from the
## fence, the spacing of its hydrants.
THIN_W = (0.12, 0.28)
THIN_V = 0.36
RING_INSET_M = 1.6
HYDRANT_M = 34.0
## In a plant, a new building may not bring a salvage source closer than
## this to the limit of the player's reach (plant.REACH_M).
REACH_SPARE_M = 1.0
## No overhead rack, with its supports, comes this close to a building
## footprint (a stub or a lot rack may end at the wall of the building it
## serves).
ROOF_CLEAR_M = 1.5
## Ground detail drawn round the finished map (Built) stops this short of a
## building, road concrete or a ground obstacle it would run onto (under the
## building's halo, clear of the road's edge line).
BUILT_GAP_M = 0.3
## Lots in this box (map-frame metres) are the cement works.
CEMENT_BOX_M = (-1500.0, 1850.0, -600.0, 2750.0)
## Chances that set how many tankers and dump trucks are parked (about 60 of
## each on the Helwan map).
TANKER_AT_RACK = 0.9
TANKER_AT_BUND = 0.8
DUMP_AT_HEAP = 0.9
DUMP_AT_SILOS = 0.8
DUMP_IN_YARD = 0.2
ROAD_VEHICLE = 0.1
## Share of the plants' bunds that have a second loading rack.
SECOND_RACK = 0.7
## Share of the factories with silos that also have a material heap.
HEAP_AT_SILOS = 0.8
## Road racks: pipes, distance of the rack's centre line from the middle of
## its service road.
ROAD_RACK_PIPES = (3, 4)
ROAD_RACK_SIDE_M = 3.5
## A road rack is at least this long, and its centre line stays this far
## from the concrete of the streets round the estate (its end stations and
## supports keep off them).
ROAD_RACK_MIN_M = 30.0
ROAD_RACK_STREET_M = 4.5
## A vehicle on a service road stands at least this far from every building.
ROAD_PARK_M = 1.0

## The clutter sprites of the industrial lots.
CLUTTER = ["drums", "pallets", "reel", "cylinders", "cabinet", "hydrant", "sleepers", "skid"]


def size_class(area):
    return "big" if area > BIG_M2 else "medium" if area >= MEDIUM_M2 else "small"


def may_park(site, x, y, size):
    """Whether a vehicle may stand at (x, y): in the play area, outside the
    KeepOut areas, and on ground of the industrial district."""
    return site.salvage.allowed(x, y, *size) and site.districts.at(x, y) == INDUSTRIAL


def draw_tank(L, c, r, v):
    """A small tank or column seen from above, drawn on the ground: its
    shadow, its roof with a rim and a hatch."""
    L.fill("interiors", kit.disc(c[0] - 0.9 - 0.12 * r, c[1] - 0.7 - 0.1 * r, r, 18), 0.0, 0.4)
    body = kit.disc(c[0], c[1], r, 20)
    L.fill("interiors", body, v)
    L.fill("interiors", kit.disc(c[0], c[1], r * 0.6, 16), min(v * 1.25, 0.5))
    L.line("interiors", body.exterior, 0.12, v * 0.5)
    L.fill("interiors", kit.disc(c[0] + r * 0.35, c[1] - r * 0.3, max(0.25, r * 0.12), 8), 0.08)


class Built:
    """The finished map round the ground detail a drawer draws: the
    building footprints, the road concrete (not rail) and the ground
    obstacles. The drawers run once every module has built and the
    footprint overlaps are resolved, so these are the ones the game gets."""

    def __init__(self, site):
        self.site = site
        self.polys = [b.poly for b in site.buildings]
        self.tree = STRtree(self.polys)
        obs = [Polygon(p) for _, p in site.obstacles.items] if site.obstacles is not None else []
        self.obs = [g if g.is_valid else g.buffer(0) for g in obs]
        self.obs_tree = STRtree(self.obs)

    def cover(self, zone, buildings=True, roads=True, obstacles=True, gap=BUILT_GAP_M):
        """What of those lies in zone, grown by gap, as one geometry (None
        for nothing)."""
        near = zone.buffer(gap) if gap else zone
        parts = []
        if buildings:
            parts += [self.polys[i] for i in self.tree.query(near)]
        if obstacles:
            parts += [self.obs[i] for i in self.obs_tree.query(near)]
        if roads:
            r = self.site.road_union_near(near, 0.0)
            if r is not None:
                parts.append(r.intersection(near.buffer(1.0)))
        if not parts:
            return None
        u = unary_union(parts)
        return (u.buffer(gap) if gap else u).intersection(zone)

    def off(self, geom, **kw):
        """A polygon geom less what cover() finds round it, without the
        slivers under 0.5 m across that this leaves (between two buildings
        standing close together)."""
        if geom.is_empty:
            return geom
        c = self.cover(geom.envelope.buffer(0.5), **kw)
        if c is None or c.is_empty:
            return geom
        rest = geom.difference(c)
        parts = [g for g in getattr(rest, "geoms", [rest]) if g.geom_type == "Polygon" and not g.buffer(-0.25).is_empty]
        return unary_union(parts) if parts else Polygon()


def built(site):
    """The Built of the finished map, made once per drawing pass."""
    key = (id(site.buildings), len(site.buildings), len(site.obstacles.items) if site.obstacles is not None else 0)
    got = getattr(site, "_built", None)
    if got is None or got[0] != key:
        got = (key, Built(site))
        site._built = got
    return got[1]


def lines_off(lines, cover, min_m=0.5):
    """Thin lines cut where they would run over cover, less the bits under
    min_m long."""
    out = []
    for g, w in lines:
        if cover is not None:
            g = g.difference(cover)
        parts = [p for p in getattr(g, "geoms", [g]) if p.geom_type == "LineString" and p.length >= min_m]
        out += [(p, w) for p in parts]
    return out


def truck_variant(name):
    """Index of a truck sprite by name, and its (length, width)."""
    for i, e in enumerate(props.CATALOGUE.get("truck", [])):
        if e["file"] == f"vehicle_{name}.png":
            return i, (e["length_m"], e["width_m"])
    return -1, props.SIZE_M["truck"]


# ---------------------------------------------------------------- placing

class Filler:
    """Places things on one lot. anchors: the big things to group round."""

    def __init__(self, site, cp, anchors, plant=None):
        self.site, self.cp, self.rng, self.F = site, cp, cp.rng, cp.F
        self.anchors = [a for a in anchors if not a.is_empty]
        self.plant = plant
        self.thin = []
        self.tanks = []
        self.buildings = []
        self.removed = 0
        self.heaps = []
        # Vehicles parked: (name, where, x, y).
        self.parked = []
        self.keep = unary_union([a.buffer(0.3) for a in self.anchors]) if self.anchors else Polygon()
        self.mediums = []

    def spot(self, w, h, margin=1.2, tries=24, reach=GROUP_M, small=False):
        """A free w x h rectangle (in the lot's frame): for a medium thing
        within reach of a big thing or (EDGE_SHARE) of the fence, for a small
        one within reach of a medium or a big thing. Returns (local x, local
        y, polygon), or None."""
        cp, rng, F = self.cp, self.rng, self.F
        for _ in range(tries):
            pool = self.anchors
            if small and self.mediums and rng.random() < 0.7:
                pool = self.mediums
            elif not small and (not pool or rng.random() < EDGE_SHARE):
                pool = [cp.area]
            if not pool:
                pool = [cp.area]
            a = pool[int(rng.integers(len(pool)))]
            p = a.exterior.interpolate(rng.uniform(0, a.exterior.length))
            ang = rng.uniform(0, 2 * np.pi)
            d = rng.uniform(1.5, reach) + max(w, h) / 2
            lx, ly = F.to_local(p.x + np.cos(ang) * d, p.y + np.sin(ang) * d)
            r = F.rect(lx - w / 2, ly - h / 2, lx + w / 2, ly + h / 2)
            if cp.space.free(r, margin):
                cp.space.take(r)
                if not small:
                    self.mediums.append(r)
                return lx - w / 2, ly - h / 2, r
        return None

    def prop(self, kind, name, x, y, rot, ruin=False):
        """Adds a hut or clutter prop by sprite name. Returns whether it was
        added."""
        cat = props.CATALOGUE.get(kind, [])
        file = f"{kind}_{name}{'_broken' if ruin else ''}.png"
        for v, e in enumerate(cat):
            if e["file"] == file:
                size = (e["length_m"], e["width_m"])
                if self.site.props.add(kind, x, y, rot, size, v):
                    self.cp.thing(props.car_rect(x, y, rot, size))
                    return True
        return False

    def hut(self, name, x, y, rot):
        d = self.site.districts.at(x, y)
        return self.prop("hut", name, x, y, rot, ruins.state_at(x, y, d) >= ruins.GUTTED)

    def clutter(self, x, y, names=None, n=None):
        """A small group of clutter round (x, y). Returns how many props."""
        rng = self.rng
        names = names or CLUTTER
        made = 0
        for _ in range(n or int(rng.integers(2, 5))):
            px, py = x + rng.normal(0, 1.6), y + rng.normal(0, 1.6)
            g = Point(px, py).buffer(0.9)
            if not self.cp.space.free(g, 0.2):
                continue
            self.cp.space.take(g)
            made += self.prop("clutter", str(rng.choice(names)), px, py, self.F.rad + rng.choice([0, np.pi / 2]) + rng.normal(0, 0.12))
        return made

    def line_to_rack(self, x, y):
        """A thin pipe from (x, y) to the nearest rack or big thing."""
        p = Point(x, y)
        targets = list(self.anchors)
        if self.plant is not None:
            targets += [r.centre() for r in self.plant.runs if r.role in ("trunk", "rung")]
        if not targets:
            return
        t = min(targets, key=lambda g: g.distance(p))
        q = nearest_points(t if t.geom_type == "LineString" else t.exterior, p)[0]
        lx, ly = self.F.to_local(x, y)
        qx, qy = self.F.to_local(q.x, q.y)
        self.thin.append((LineString([self.F.pt(lx, ly), self.F.pt(qx, ly), self.F.pt(qx, qy)]), self.rng.uniform(*THIN_W)))

    # -- medium things ------------------------------------------------------

    def building(self, kind, w, h, pipe=True):
        got = self.spot(w, h, margin=2.0)
        if got is None:
            return False
        x, y, r = got
        self.buildings.append(self.cp.building(r, kind))
        if pipe:
            self.line_to_rack(*self.F.pt(x + w / 2, y + h / 2))
        return True

    def substation(self):
        return self.building("control", self.rng.uniform(8.2, 12.0), self.rng.uniform(7.6, 9.0), pipe=False)

    def shelter(self):
        return self.building("shelter", self.rng.uniform(10.0, 14.0), self.rng.uniform(6.2, 8.0))

    def workshop(self):
        return self.building("workshop", self.rng.uniform(12.0, 18.0), self.rng.uniform(8.0, 10.0), pipe=False)

    def cooling(self):
        n = int(self.rng.integers(2, 5))
        return self.building("cooling", 6.5 * n, 6.5)

    def tank(self, lo=6.4, hi=TANK_BUILDING_M):
        """A tank: a building from TANK_BUILDING_M across (TANK_BUILDING_SHARE
        of the tanks), drawn only below that."""
        rng = self.rng
        real = lo > 6.0 and rng.random() < TANK_BUILDING_SHARE
        d = rng.uniform(TANK_BUILDING_M, TANK_MAX_M) if real else rng.uniform(lo, hi)
        got = self.spot(d + 0.6, d + 0.6, margin=1.0, small=lo < 6.0)
        if got is None:
            return False
        x, y, r = got
        c = self.F.pt(x + d / 2 + 0.3, y + d / 2 + 0.3)
        if real:
            self.buildings.append(self.cp.building(kit.disc(c[0], c[1], d / 2, 20), "tank"))
        else:
            v = rng.uniform(0.26, 0.4)
            self.cp.thing(kit.disc(c[0], c[1], d / 2, 20))
            self.cp.draw(lambda L: draw_tank(L, c, d / 2, v))
        self.tanks.append((c, d / 2))
        self.line_to_rack(*c)
        return True

    def column(self):
        return self.tank(2.6, 4.0)

    def vessels(self):
        rng, F = self.rng, self.F
        n, ln, dia = int(rng.integers(2, 4)), rng.uniform(6.0, 9.0), rng.uniform(1.8, 2.6)
        w, h = ln + 1.6, n * (dia + 1.0) + 0.8
        got = self.spot(w, h)
        if got is None:
            return False
        x, y, r = got
        self.cp.thing(r)
        axes = [F.line([(x + 0.8, y + 0.9 + dia / 2 + i * (dia + 1.0)), (x + 0.8 + ln, y + 0.9 + dia / 2 + i * (dia + 1.0))])
                for i in range(n)]

        def draw(L):
            L.fill("interiors", r, 0.17)
            L.line("interiors", r.exterior, 0.1, 0.3)
            for axis in axes:
                body = axis.buffer(dia / 2, cap_style="round")
                L.fill("interiors", LineString([(px - 0.6, py - 0.5) for px, py in axis.coords]).buffer(dia / 2, cap_style="round"), 0.0, 0.35)
                L.fill("interiors", body, 0.36)
                L.line("interiors", body.exterior, 0.06, 0.2)
                L.line("interiors", axis, dia * 0.18, 0.5, 0.7)
                for t in (0.22, 0.78):
                    L.line("interiors", perp_segment(axis, axis.length * t, dia / 2 + 0.25), 0.3, 0.24)
        self.cp.draw(draw)
        self.line_to_rack(*F.pt(x + w / 2, y + h / 2))
        return True

    def cooler(self):
        rng, F = self.rng, self.F
        w, h = rng.uniform(9.0, 13.0), rng.uniform(5.0, 6.5)
        got = self.spot(w, h)
        if got is None:
            return False
        x, y, r = got
        self.cp.thing(r)
        fans = [F.pt(x + w * t, y + h / 2) for t in (1 / 6, 3 / 6, 5 / 6)]
        tubes = [F.line([(x + 0.5, yy), (x + w - 0.5, yy)]) for yy in np.arange(y + 0.5, y + h - 0.3, 0.7)]

        def draw(L):
            kit.soft_shadow(L, r, 0.8, 0.4)
            L.fill("interiors", r, 0.09)
            for c in fans:
                L.fill("interiors", kit.disc(c[0], c[1], min(h / 2 - 0.5, w / 6 - 0.3), 16), 0.05)
            for t in tubes:
                L.line("interiors", t, 0.26, 0.48, 0.9)
            L.line("interiors", r.exterior, 0.2, 0.26)
        self.cp.draw(draw)
        self.line_to_rack(*F.pt(x + w / 2, y + h / 2))
        return True

    def laydown(self):
        rng, F = self.rng, self.F
        w, h = rng.uniform(8.0, 13.0), rng.uniform(7.0, 11.0)
        got = self.spot(w, h, reach=GROUP_M * 1.6)
        if got is None:
            return False
        x, y, r = got
        self.cp.thing(r)
        stacks = []
        for yy in np.arange(y + 1.2, y + h - 1.5, rng.uniform(1.6, 2.4)):
            x0 = x + rng.uniform(0.8, 2.0)
            stacks.append((F.rect(x0, yy, x + w - rng.uniform(0.8, 3.0), yy + rng.uniform(0.7, 1.3)), rng.uniform(0.2, 0.42)))
        seed = int(rng.integers(1 << 30))

        def draw(L):
            kit.pave(L, r, 0.13, 0.9, sub="groundlines")
            kit.fence(L, r.exterior, np.random.default_rng(seed), v=0.24)
            for g, v in stacks:
                L.fill("interiors", g, v)
                L.line("interiors", g.exterior, 0.06, v * 0.6)
                L.line("interiors", LineString([g.exterior.coords[0], g.exterior.coords[2]]), 0.05, v * 1.3)
        self.cp.draw(draw)
        if rng.random() < DUMP_IN_YARD:
            self.beside(r, "dump_truck", "laydown square")
        return True

    def pen(self):
        rng, F = self.rng, self.F
        w, h = rng.uniform(6.0, 8.0), rng.uniform(5.5, 7.0)
        got = self.spot(w, h)
        if got is None:
            return False
        x, y, r = got
        self.cp.thing(r)
        seed = int(rng.integers(1 << 30))
        self.cp.draw(lambda L: (kit.pave(L, r, 0.1, 0.9, sub="interiors"),
                                kit.fence(L, r.exterior, np.random.default_rng(seed), v=0.28)))
        for dx in (w * 0.3, w * 0.7):
            px, py = F.pt(x + dx, y + h / 2)
            self.prop("clutter", str(rng.choice(["cabinet", "skid"])), px, py, F.rad + np.pi / 2)
        return True

    def cabins(self):
        rng, F = self.rng, self.F
        n = int(rng.integers(2, 5))
        w, h = 6.2, n * 3.0
        got = self.spot(w, h, reach=GROUP_M * 1.6)
        if got is None:
            return False
        x, y, r = got
        for i in range(n):
            self.hut("cabin", *F.pt(x + w / 2, y + 1.5 + i * 3.0), F.rad)
        return True

    def loading_rack(self, near):
        """A tanker loading rack: a canopy on a lattice frame over one or two
        bays, beside a bund, with a thin pipe to it."""
        rng, F = self.rng, self.F
        n = int(rng.integers(1, 3))
        for _ in range(150):
            # Bays side by side across the rack; the rack along x or along y.
            w, h = (13.0, 4.5 * n) if rng.random() < 0.5 else (4.5 * n, 13.0)
            p = near.exterior.interpolate(rng.uniform(0, near.exterior.length))
            ang = rng.uniform(0, 2 * np.pi)
            d = rng.uniform(6.0, 22.0)
            lx, ly = F.to_local(p.x + np.cos(ang) * d, p.y + np.sin(ang) * d)
            r = F.rect(lx - w / 2, ly - h / 2, lx + w / 2, ly + h / 2)
            if self.cp.space.free(r, 1.0):
                break
        else:
            return False
        x, y = lx - w / 2, ly - h / 2
        # The tankers are parked first: the bays are theirs.
        for i in range(n):
            if rng.random() < TANKER_AT_RACK:
                off = -4.5 * (n - 1) / 2 + 4.5 * i
                at = (lx + rng.uniform(-0.6, 0.6), ly + off) if w > h else (lx + off, ly + rng.uniform(-0.6, 0.6))
                self.vehicle("tanker", *F.pt(*at), F.rad + (0.0 if w > h else np.pi / 2) + rng.choice([0, np.pi]), "loading rack")
        self.cp.space.take(r)
        self.cp.thing(r)
        self.cp.draw(lambda L: (kit.pave(L, r, 0.2, 0.9, sub="groundlines"), strut_frame(L, F, x + 0.8, y + 0.4, x + w - 0.8, y + h - 0.4, v=0.3)))
        q = nearest_points(near.exterior, Point(F.pt(lx, ly)))[0]
        self.thin.append((LineString([F.pt(lx, ly), (q.x, q.y)]), 0.25))
        return True

    def heap(self):
        """A material heap of the cement works: a drawn mound."""
        rng, F = self.rng, self.F
        rad = rng.uniform(8.0, 14.0)
        got = self.spot(2 * rad + 2, 2 * rad + 2, margin=1.0, reach=GROUP_M * 2)
        if got is None:
            return False
        x, y, r = got
        c = F.pt(x + rad + 1, y + rad + 1)
        seed = int(rng.integers(1 << 30))
        v = rng.uniform(0.2, 0.34)
        rings = [ruins.noisy_disc(c[0] + rad * 0.12 * k, c[1] - rad * 0.1 * k, rad * (1 - 0.24 * k), np.random.default_rng(seed + k), 18, 0.16)
                 for k in range(4)]
        self.cp.thing(rings[0])

        def draw(L):
            L.fill("groundlines", rings[0].buffer(0.8), 0.0, 0.3)
            for k, g in enumerate(rings):
                L.fill("interiors", g, v * (0.8 + 0.16 * k))
            L.line("interiors", rings[0].exterior, 0.15, v * 0.55)
        self.cp.draw(draw)
        self.heaps.append((c, rad))
        if rng.random() < DUMP_AT_HEAP:
            self.beside(r, "dump_truck", "heap", facing=True)
        return True

    def beside(self, rect, name, where, facing=False):
        """Parks a vehicle beside a rectangle of the lot's frame: along one of
        its sides, or (facing) nose on to it. Returns whether one was parked."""
        F, rng = self.F, self.rng
        _, size = truck_variant(name)
        loc = [F.to_local(px, py) for px, py in rect.exterior.coords[:-1]]
        x0, x1 = min(p[0] for p in loc), max(p[0] for p in loc)
        y0, y1 = min(p[1] for p in loc), max(p[1] for p in loc)
        off = (size[0] if facing else size[1]) / 2 + 1.4
        turn = 0.0 if facing else np.pi / 2
        spots = [((x0 + x1) / 2, y0 - off, -np.pi / 2), ((x0 + x1) / 2, y1 + off, np.pi / 2),
                 (x0 - off, (y0 + y1) / 2, np.pi), (x1 + off, (y0 + y1) / 2, 0.0)]
        for k in rng.permutation(4):
            lx, ly, out = spots[k]
            if self.vehicle(name, *F.pt(lx, ly), F.rad + out + np.pi + turn, where):
                return True
        return False

    def vehicle(self, name, x, y, ang, where):
        """Parks a tanker or a dump truck on the lot, if it fits there and
        may stand there (may_park)."""
        v, size = truck_variant(name)
        g = props.car_rect(x, y, ang, size)
        if v < 0 or not self.cp.area.contains(g) or not self.cp.space.free(g, 0.6) or not may_park(self.site, x, y, size):
            return False
        if props.add_vehicle(self.site.props, self.site.salvage, "truck", x, y, ang, size, v):
            self.cp.space.take(g)
            self.cp.thing(g)
            self.parked.append((name, where, x, y))
            return True
        return False

    # -- the fill -------------------------------------------------------------

    def fill(self, medium, small_buildings=True):
        """Adds medium things from the weighted table `medium` ({method name:
        weight}) and then small ones, up to the lot's targets (see the module
        text), or until no more fit."""
        cp, rng = self.cp, self.rng
        n = cp.counts()
        big = max(1, n["big"])
        ground = cp.area.area - (unary_union(cp.things).area if cp.things else 0.0)
        names = list(medium)
        w = np.array([medium[k] for k in names], float)
        want = min(MAX_MEDIUM, max(MEDIUM_PER_BIG * big, int(ground / MEDIUM_GROUND_M2))) - n["medium"]
        fails = 0
        while want > 0 and fails < 30:
            before = cp.counts()["medium"]
            if getattr(self, str(rng.choice(names, p=w / w.sum())))():
                want -= max(1, cp.counts()["medium"] - before)
                fails = 0
            else:
                fails += 1
        want = min(MAX_SMALL, max(SMALL_PER_BIG * big, int(ground / SMALL_GROUND_M2))) - cp.counts()["small"]
        fails = 0
        while want > 0 and fails < 20:
            before = cp.counts()["small"]
            roll = rng.random()
            if roll < 0.06 and small_buildings:
                self.column()
            elif roll < 0.16:
                got = self.spot(4.4, 3.4, margin=0.8, reach=8.0, small=True)
                if got is not None:
                    self.hut(str(rng.choice(["shed", "shelter", "guard"])), *self.F.pt(got[0] + 2.2, got[1] + 1.7),
                             self.F.rad + rng.choice([0, np.pi / 2]))
            else:
                got = self.spot(3.0, 3.0, margin=0.3, reach=7.0, small=True)
                if got is not None:
                    self.cp.space.taken.pop()
                    self.clutter(*self.F.pt(got[0] + 1.5, got[1] + 1.5))
            made = cp.counts()["small"] - before
            want -= made
            fails = 0 if made else fails + 1

    def firewater(self):
        """The firewater ring inside the fence, with hydrants on it."""
        ring = kit.largest(self.cp.area.buffer(-RING_INSET_M))
        if ring is None:
            return
        self.thin.append((LineString(ring.exterior.coords), 0.2))
        inner = kit.largest(ring.buffer(-1.3))
        if inner is None:
            return
        q = inner.exterior
        for d in np.arange(HYDRANT_M / 2, ring.exterior.length, HYDRANT_M):
            p = ring.exterior.interpolate(d)
            h = q.interpolate(q.project(p))
            if self.cp.space.free(h.buffer(0.6)):
                self.thin.append((LineString([(p.x, p.y), (h.x, h.y)]), 0.14))
                self.prop("clutter", "hydrant", h.x, h.y, self.rng.uniform(0, 6.28))

    def tracing(self, runs):
        """A thin tracing line beside each overhead rack, tied to it at both
        ends."""
        for run in runs:
            c = run.centre()
            side = c.offset_curve(run.width / 2 + 1.0, join_style="round")
            for g in getattr(side, "geoms", [side]):
                if g.geom_type == "LineString" and g.length > 6.0:
                    self.thin.append((g, 0.14))
                    for end, d in ((g.coords[0], 0.0), (g.coords[-1], c.length)):
                        q = c.interpolate(c.project(Point(end)))
                        self.thin.append((LineString([end, (q.x, q.y)]), 0.14))

    def flush(self):
        """Queues the thin pipes for drawing, kept inside the lot's fence,
        cut where they would run over a big thing, and (when drawn) over a
        building, road concrete or a ground obstacle: a pipe that meets one
        ends at it. Returns their length."""
        if not self.thin:
            return 0.0
        lines = [(g.intersection(self.cp.area).difference(self.keep), w) for g, w in self.thin]
        lines = [(g, w) for g, w in lines if not g.is_empty]
        site, zone = self.site, self.cp.area.buffer(3.0)

        def draw(L):
            for g, w in lines_off(lines, built(site).cover(zone)):
                L.line("groundlines", g, w, THIN_V)
        self.cp.draw(draw)
        return float(sum(g.length for g, _ in lines))


# ------------------------------------------------------------------- lots

def anchors_of(cp):
    """The things of a lot to group round: its big ones, or failing that its
    largest."""
    geoms = [g for g in cp.things if g.geom_type == "Polygon"]
    big = [g for g in geoms if g.area > BIG_M2]
    return big or sorted(geoms, key=lambda g: -g.area)[:2]


def clear_houses(site, cp):
    """A house whose centre is outside a lot can still reach into it (the
    fence cuts it). Removes the ones that are under an overhead rack of the
    lot's plant or within ROOF_CLEAR_M of its supports, and keeps the lot's
    new things off the others. Returns how many it removed."""
    P = getattr(cp, "plant", None)
    racks = [(r.centre(), rack_half(r.pipes) + ROOF_CLEAR_M) for r in P.runs if r.role in plant.OVERHEAD_ROLES] if P else []
    keep, gone = [], 0
    for b in site.buildings:
        if b.kind == "house" and b.poly.intersects(cp.area):
            if any(line.distance(b.poly) < reach for line, reach in racks):
                gone += 1
                continue
            cp.space.take(b.poly.buffer(ROOF_CLEAR_M))
        keep.append(b)
    site.buildings = keep
    return gone


def fill_plant(site, cp, P):
    """Fills a process plant. The plant's rectangle was taken whole when it
    was built; here it is opened again, less what stands in it, the fences
    of its yards, its roads and the ground under its racks."""
    if P.box in cp.space.taken:
        cp.space.taken.remove(P.box)
    for g in P.occupied + P.corridors + P.blockers + [y.exterior.buffer(1.0) for y in P.yards]:
        cp.space.take(g)
    for run in P.runs:
        # Under an overhead rack: its supports and ROOF_CLEAR_M more (a new
        # building also keeps its own margin from this strip).
        cp.space.take(run.centre().buffer(run.width / 2 + (1.3 if run.role in plant.OVERHEAD_ROLES else 1.6)))
    for s in P.sources:
        cp.space.take(Point(s[1], s[2]).buffer(2.6))
    W = Filler(site, cp, [n.S.box() for n in P.nodes.values()], plant=P)
    W.keep = unary_union([n.S.box().buffer(0.3) for n in P.nodes.values() if n.kind in ("unit", "bund", "pool")])
    R = P.reach()
    base = [R.gap(s[1], s[2]) for s in P.sources]
    for n in P.nodes.values():
        if n.kind == "bund":
            W.loading_rack(n.S.box())
            if W.rng.random() < SECOND_RACK:
                W.loading_rack(n.S.box())
            if W.rng.random() < TANKER_AT_BUND:
                W.beside(n.S.box(), "tanker", "bund")
    W.fill({"substation": 1.0, "shelter": 1.5, "cooling": 0.7, "tank": 2.0, "vessels": 2.5, "cooler": 1.5, "laydown": 0.8,
            "pen": 1.0, "cabins": 0.6})
    P.blockers += [b.poly for b in W.buildings]
    R = P.reach()
    cut = lambda: R.pockets or any(R.gap(s[1], s[2]) > max(g + 0.3, plant.REACH_M - REACH_SPARE_M) for s, g in zip(P.sources, base))
    while W.buildings and cut():
        b = W.buildings.pop()
        site.buildings.remove(b)
        P.blockers.remove(b.poly)
        cp.things = [g for g in cp.things if g is not b.poly]
        c = b.poly.centroid
        W.thin = [(g, w) for g, w in W.thin if Point(g.coords[0]).distance(c) > 1.0]
        W.removed += 1
        R = P.reach()
    W.firewater()
    W.tracing([r for r in P.runs if r.role in ("trunk", "rung")])
    for n in P.nodes.values():
        if n.kind == "unit":
            c = n.S.box().centroid
            W.line_to_rack(c.x + W.rng.uniform(-3, 3), c.y + W.rng.uniform(-3, 3))
    return W


def lot_rack(site, cp, W, hall):
    """An overhead rack from the wall of a lot's hall to the rim of one of
    its new tanks, the farthest it can reach clear of every other building
    and of road concrete (both ends at equipment). Returns its Run, or
    None."""
    if hall is None or not W.tanks:
        return None
    F = cp.F
    roofs = Roofs(site)
    streets = site.full_roads_near(cp.area, 0.0)
    pipes = rack_pipes(cp.rng, 3, dia=(0.3, 0.6))
    seed = int(cp.rng.integers(1 << 30))
    half = rack_half(pipes)
    c = hall.centroid
    for t, rad in sorted(W.tanks, key=lambda k: -((k[0][0] - c.x) ** 2 + (k[0][1] - c.y) ** 2))[:6]:
        a = nearest_points(hall.exterior, Point(t))[0]
        ax, ay = F.to_local(a.x, a.y)
        tx, ty = F.to_local(*t)
        for corner in ((tx, ay), (ax, ty)):
            last = np.hypot(tx - corner[0], ty - corner[1])
            if last < rad + 3.0 or np.hypot(corner[0] - ax, corner[1] - ay) < 3.0:
                continue
            k = (last - rad) / last
            end = (corner[0] + (tx - corner[0]) * k, corner[1] + (ty - corner[1]) * k)
            path = LineString([F.pt(ax, ay), F.pt(*corner), F.pt(*end)])
            if path.length < 12.0:
                continue
            # Clear of every roof, but for where it leaves the hall's wall
            # and meets the tank's rim.
            body = substring(path, 2.0, path.length - 2.0)
            if not roofs.clear(body, half) or any(g is not hall and g.distance(Point(t)) > 0.5
                                                  for g in roofs.near(path, half + ROOF_CLEAR_M)):
                continue
            if streets is not None and path.buffer(half).intersects(streets):
                continue
            run = Run(list(path.coords), pipes, True, ("equip", "equip"), "lot")
            run.add_bridge(0.0, run.length, "overhead")
            cp.draw(lambda L: draw_run(L, run, np.random.default_rng(seed)))
            return run
    return None


def fill_factory(site, cp, cement=False):
    """Fills a factory, a depot or a cement works lot."""
    W = Filler(site, cp, anchors_of(cp))
    hall = max(cp.halls, key=lambda g: g.area) if cp.halls else None
    silos = [b.poly.centroid for b in site.buildings if b.kind == "silo" and cp.area.contains(b.poly.centroid)]
    if cement:
        for _ in range(int(cp.rng.integers(2, 5))):
            W.heap()
    elif silos and cp.rng.random() < HEAP_AT_SILOS:
        W.heap()
    for c in silos[:2]:
        if cp.rng.random() < (DUMP_AT_HEAP if cement else DUMP_AT_SILOS):
            side = cp.rng.choice([-1.0, 1.0])
            lx, ly = cp.F.to_local(c.x, c.y)
            W.vehicle("dump_truck", *cp.F.pt(lx + cp.rng.uniform(-2, 2), ly + side * 10.0), cp.F.rad, "silos")
    for bund in cp.bunds:
        if cp.rng.random() < TANKER_AT_BUND:
            W.beside(bund, "tanker", "bund")
        table = {"substation": 1.0, "shelter": 1.5, "workshop": 1.0, "tank": 1.2, "cooler": 0.6, "laydown": 1.6, "pen": 1.0,
                 "cabins": 1.0, "cooling": 0.4}
    else:
        table = {"substation": 1.0, "shelter": 1.2, "workshop": 1.2, "cooling": 0.6, "tank": 1.6, "vessels": 1.0, "cooler": 0.8,
                 "laydown": 1.6, "pen": 1.0, "cabins": 1.0}
    W.fill(table)
    rack = lot_rack(site, cp, W, hall)
    W.firewater()
    if rack is not None:
        W.tracing([rack])
    return W, rack


# ----------------------------------------------------------- road racks

class Roofs:
    """The building footprints, for keeping overhead racks off them."""

    def __init__(self, site):
        self.polys = [b.poly for b in site.buildings]
        self.tree = STRtree(self.polys)

    def near(self, geom, dist):
        """The footprints within dist of a geometry."""
        zone = geom.buffer(dist)
        return [self.polys[i] for i in self.tree.query(zone) if self.polys[i].intersects(zone)]

    def clear(self, line, half, but=None):
        """Whether a rack along a line, half wide with its supports, stays
        ROOF_CLEAR_M off every footprint to its sides (but one: the building
        it serves). The line's ends are not carried on."""
        zone = line.buffer(half + ROOF_CLEAR_M, cap_style="flat")
        return not any(self.polys[k] is not but and self.polys[k].intersects(zone) for k in self.tree.query(zone))


def rack_half(pipes):
    """Half the width of an overhead rack with its supports (pipes.draw_bridge)."""
    return group_width(pipes) / 2 + 1.6


def road_racks(site, blk, axes, rng):
    """An overhead rack along the service roads of an estate block, on one
    verge. axes: the centre lines of the roads. Along each road the rack
    takes the side with the most length clear of buildings, and only the
    stretches of ROAD_RACK_MIN_M or more that are clear: a road that is
    built over gets none. A rack that meets another ends in a tee; any
    other end is at a drawn valve station. Returns the Runs; each has .side
    (+1 left of its road's centre line, -1 right) for road_vehicles."""
    roofs = Roofs(site)
    inner = blk.buffer(-3.0)
    streets = site.full_roads_near(blk, ROAD_RACK_STREET_M)
    if streets is not None:
        inner = inner.difference(streets.buffer(ROAD_RACK_STREET_M))
    pieces = []
    for axis in axes:
        pipes = rack_pipes(rng, int(rng.integers(ROAD_RACK_PIPES[0], ROAD_RACK_PIPES[1] + 1)), dia=(0.4, 0.8))
        best = (0.0, [], 0)
        for side in (1, -1):
            line = axis.offset_curve(side * ROAD_RACK_SIDE_M).intersection(inner)
            built = roofs.near(line, rack_half(pipes) + ROOF_CLEAR_M) if not line.is_empty else []
            if built:
                line = line.difference(unary_union(built).buffer(rack_half(pipes) + ROOF_CLEAR_M))
            parts = [g for g in getattr(line, "geoms", [line]) if g.geom_type == "LineString" and g.length >= ROAD_RACK_MIN_M]
            total = sum(g.length for g in parts)
            if total > best[0]:
                best = (total, parts, side)
        pieces += [(g, pipes, best[2]) for g in best[1]]
    runs = []
    for line, pipes, side in pieces:
        pts, ends = [np.asarray(line.coords[0]), np.asarray(line.coords[-1])], []
        for k in (0, 1):
            # An end that reaches another rack when carried on a little, clear
            # of buildings, ends in a tee there.
            u = (pts[k] - pts[1 - k]) / line.length
            reach = LineString([pts[k] - u * 2.0, pts[k] + u * (2 * ROAD_RACK_SIDE_M + 2.0)])
            hits = [reach.intersection(o) for o, _, _ in pieces if o is not line and reach.intersects(o)]
            hits = [h for h in hits if h.geom_type == "Point"]
            if hits and roofs.clear(LineString([pts[k], hits[0].coords[0]]), rack_half(pipes)):
                pts[k] = np.asarray(hits[0].coords[0])
                ends.append("tee")
            else:
                ends.append("equip")
        run = Run([tuple(pts[0]), tuple(pts[1])], pipes, True, tuple(ends), "road")
        run.add_bridge(0.0, run.length, "overhead")
        run.side = side
        runs.append(run)
        seed = int(rng.integers(1 << 30))

        def draw(L, run=run, seed=seed):
            draw_run(L, run, np.random.default_rng(seed))
            for kind, p in zip(run.ends, (run.pts[0], run.pts[-1])):
                if kind == "equip":
                    L.fill("interiors", Point(p).buffer(run.width / 2 + 1.2, cap_style="square"), 0.2)
                    L.line("interiors", Point(p).buffer(run.width / 2 + 1.2, cap_style="square").exterior, 0.2, 0.42)
                    L.fill("interiors", Point(p).buffer(0.8), 0.46)
        site.drawers.append(draw)
        trace = run.centre().offset_curve(run.width / 2 + 0.9)
        if trace.geom_type == "LineString":
            tie = [LineString([trace.coords[0], run.pts[0]]), LineString([trace.coords[-1], run.pts[-1]])]
            site.drawers.append(lambda L, trace=trace, tie=tie: [L.line("groundlines", g, 0.14, THIN_V) for g in [trace] + tie])
            run.thin_m = trace.length + sum(t.length for t in tie)
    return runs


def stub(site, racks, target, kind, rng):
    """An overhead rack from a road rack straight across to a lot's trunk
    (a tee) or hall (equipment, at its wall), clear of every other
    building. Returns its Run, or None."""
    if not racks or target is None:
        return None
    roofs = Roofs(site)
    c = target.centroid
    rack = min(racks, key=lambda r: r.centre().distance(c))
    line = rack.centre()
    if line.distance(target) > 60.0 or line.length < 16.0:
        return None
    hall = target if target.geom_type == "Polygon" else None
    edge = target.exterior if hall is not None else target
    pipes = rack_pipes(rng, 3, dia=(0.3, 0.6))
    d0 = line.project(c)
    for d in sorted(np.arange(6.0, line.length - 6.0, 5.0), key=lambda d: abs(d - d0)):
        a, a2 = line.interpolate(d), line.interpolate(d + 1.0)
        n = np.array([-(a2.y - a.y), a2.x - a.x])
        if n @ np.array([c.x - a.x, c.y - a.y]) < 0:
            n = -n
        hit = LineString([(a.x, a.y), (a.x + n[0] * 70.0, a.y + n[1] * 70.0)]).intersection(edge)
        pts = [p for p in getattr(hit, "geoms", [hit]) if p.geom_type == "Point"]
        if not pts:
            continue
        b = min(pts, key=lambda p: p.distance(a))
        span = a.distance(b)
        if not 6.0 < span < 70.0:
            continue
        # The stub may touch the hall it serves at its end only.
        short = LineString([(a.x, a.y), (b.x - n[0] * 2.0, b.y - n[1] * 2.0)])
        if not roofs.clear(LineString([(a.x, a.y), (b.x, b.y)]), rack_half(pipes), but=hall) or not roofs.clear(short, rack_half(pipes)):
            continue
        run = Run([(a.x, a.y), (b.x, b.y)], pipes, True, ("tee", kind), "stub")
        run.add_bridge(0.0, run.length, "overhead")
        seed = int(rng.integers(1 << 30))
        site.drawers.append(lambda L: draw_run(L, run, np.random.default_rng(seed)))
        return run
    return None


def road_vehicles(site, paved, racks, areas, rng):
    """A few tankers and dump trucks left on the paved service roads of an
    estate (paved: the road polygons): along a stretch that has a rack, on
    the other side of the road, clear of the lots and at least ROAD_PARK_M
    from every building. Returns them as (name, where, x, y)."""
    out = []
    paved = [g for g in paved if not g.is_empty]
    if not paved or not racks:
        return out
    roofs = Roofs(site)
    road = unary_union(paved)
    lots = unary_union(areas) if areas else Polygon()
    for rack in racks:
        line = rack.centre().offset_curve(-rack.side * (ROAD_RACK_SIDE_M + 2.6))
        if line.geom_type != "LineString":
            continue
        for d in np.arange(15.0, line.length - 15.0, 45.0):
            if rng.random() > ROAD_VEHICLE:
                continue
            name = "tanker" if rng.random() < 0.5 else "dump_truck"
            v, size = truck_variant(name)
            p, q = line.interpolate(d), line.interpolate(d + 1.0)
            ang = float(np.arctan2(q.y - p.y, q.x - p.x))
            g = props.car_rect(p.x, p.y, ang, size)
            if v >= 0 and road.contains(g) and not g.intersects(lots) and may_park(site, p.x, p.y, size) and \
                    not roofs.near(g, ROAD_PARK_M) and site.props.clear_of(p.x, p.y, size[0] / 2) and \
                    props.add_vehicle(site.props, site.salvage, "truck", p.x, p.y, ang, size, v):
                out.append((name, "service road", p.x, p.y))
    return out


# ------------------------------------------------------------------ stats

def stats(lots):
    """What stands on the lots, by lot type (Compound.lot): how many lots,
    their area, the big, medium and small things, and the built cover (the
    share of the lots' area under a thing)."""
    out = {}
    for cp in lots:
        s = out.setdefault(cp.lot, {"lots": 0, "area_m2": 0.0, "big": 0, "medium": 0, "small": 0, "cover_m2": 0.0})
        s["lots"] += 1
        s["area_m2"] += cp.area.area
        for g in cp.things:
            s[size_class(g.area)] += 1
        s["cover_m2"] += unary_union(cp.things).intersection(cp.area).area if cp.things else 0.0
    for s in out.values():
        s["cover_share"] = round(s.pop("cover_m2") / max(s["area_m2"], 1.0), 3)
        s["area_m2"] = round(s["area_m2"])
    return out


def near_roofs(site, lines):
    """Metres of the given centre lines that are over a building footprint
    or within ROOF_CLEAR_M of one."""
    polys = [b.poly for b in site.buildings]
    tree = STRtree(polys)
    total = 0.0
    for line in lines:
        idx = tree.query(line.buffer(ROOF_CLEAR_M))
        if len(idx):
            total += line.intersection(unary_union([polys[i] for i in idx]).buffer(ROOF_CLEAR_M)).length
    return round(total, 1)


def lot_list(lots):
    """Each lot's type, centre (m) and counts, for finding a lot on the map."""
    return [dict(cp.counts(), lot=cp.lot, centre=[round(cp.area.centroid.x), round(cp.area.centroid.y)],
                 area_m2=round(cp.area.area)) for cp in lots]
