"""What the district modules (industrial.py, market.py, farmland.py) share
while they build: the city layout, the districts, and the collectors they
add to.

  buildings    the Building list (buildings.py); a module may remove houses
               from a block it rebuilds and add its own buildings
  drawers      functions f(L) that draw a module's ground objects into the
               mesh layers (style.Layers), called before the buildings
  solid_extra  polygons (metres) that the generic prop rules keep clear of
  salvage, obstacles, props
               the salvage source, obstacle and prop spawn collectors
  claims       land taken by the site modules that run after the district
               modules (landmarks, infra, civic, fabric, sites): each takes
               its land with claim() and checks is_free() first, so no two
               of them build on the same ground
  landmarks    named places (landmark registry); written to landmarks.json
               for the game

The district modules (industrial, market, farmland, military) run first and
do not claim land. is_free() also keeps clear of what they built: their
buildings, solid_extra and the ground obstacles.
"""
import numpy as np
from shapely import STRtree, contains_xy, prepare
from shapely.geometry import Point
from shapely.ops import unary_union

from frame import PLAY_HALF_M
from gen_city import Sampler

# Buildings made by these stages count as taken land for is_free().
DISTRICT_STAGES = ("industrial", "market", "farmland", "military")
# How far is_free() keeps from district module buildings and from markers
# (start positions, exits, spawn zones), metres.
DISTRICT_CLEAR_M = 6.0
MARKER_CLEAR_M = 20.0


class Site:
    def __init__(self, water, roads, blocks, viaducts, districts, keep_out, f, zone):
        self.water = water
        self.roads = roads
        self.blocks = blocks
        self.viaducts = viaducts
        self.districts = districts
        self.keep_out = keep_out
        self.f = f
        self.zone = zone
        self.sampler = Sampler(f, zone)
        self.buildings = []
        self.drawers = []
        self.solid_extra = []
        self.salvage = None
        self.obstacles = None
        self.props = None
        self.stats = {}
        # Pipe rack ends of the process plants: (point, plant id, rack).
        self.rack_ends = []
        # (polygon, owner) per claim; see claim().
        self.claims = []
        self._claimed = None
        self._district_taken = None
        # Named places: dicts with name, kind, x, y (metres), radius (metres)
        # and outline (list of (x, y) metres); see add_landmark().
        self.landmarks = []
        self.markers = []
        # Set by run_all: the whole map's roads, blocks, big roofs and lots
        # (also in a window run), and the window box (None in a full run).
        self.full_layout = None
        self.window = None
        self._road_tree = None
        self._road_geoms = None
        self._full_road_tree = None
        self._full_road_geoms = None
        self._full_big_tree = None

    def road_union_near(self, geom, dist=40.0):
        """The concrete of the roads within dist of geom (metres)."""
        if self._road_tree is None:
            self._road_geoms = [g for g, *_, kind, _ in self.roads if not kind.startswith("rail:")]
            self._road_tree = STRtree(self._road_geoms)
        idx = self._road_tree.query(geom.buffer(dist))
        return unary_union([self._road_geoms[i] for i in idx]) if len(idx) else None

    def full_roads_near(self, geom, dist=40.0):
        """The concrete of the whole map's roads (full_layout, rail left out)
        within dist of geom, or None: a window run sees the same roads as a
        full run."""
        if self._full_road_tree is None:
            self._full_road_geoms = [g for g, *_, kind, _ in self.full_layout["roads"]
                                     if g is not None and not kind.startswith("rail:")]
            self._full_road_tree = STRtree(self._full_road_geoms)
        idx = self._full_road_tree.query(geom.buffer(dist))
        return unary_union([self._full_road_geoms[i] for i in idx]) if len(idx) else None

    def full_big_in(self, area):
        """The whole map's large roofs (full_layout["big"], in their order)
        that touch area."""
        big = self.full_layout["big"]
        if self._full_big_tree is None:
            self._full_big_tree = STRtree(big)
        return [big[i] for i in sorted(int(i) for i in self._full_big_tree.query(area)) if big[i].intersects(area)]

    def blocks_of(self, code, min_share=0.5, min_area=0.0):
        """Street blocks whose district is mostly `code`."""
        out = []
        for blk in self.blocks:
            if blk.area < min_area:
                continue
            if self.districts.share(blk, code) >= min_share:
                out.append(blk)
        return out

    def remove_buildings_in(self, area, kinds=("house",)):
        """Drops buildings of the given kinds whose centre is inside area."""
        if area.is_empty:
            return 0
        keep, dropped = [], 0
        cen = np.array([[b.poly.centroid.x, b.poly.centroid.y] for b in self.buildings]) if self.buildings else np.zeros((0, 2))
        inside = contains_xy(area, cen[:, 0], cen[:, 1]) if len(cen) else np.zeros(0, bool)
        for b, ins in zip(self.buildings, inside):
            if ins and b.kind in kinds:
                dropped += 1
                continue
            keep.append(b)
        self.buildings = keep
        return dropped

    def remove_buildings_touching(self, area, kinds=("house",), margin=0.5):
        """Drops buildings of the given kinds that touch area (grown by
        margin)."""
        if area.is_empty:
            return 0
        g = area.buffer(margin)
        keep = [b for b in self.buildings if not (b.kind in kinds and b.poly.intersects(g))]
        dropped = len(self.buildings) - len(keep)
        self.buildings = keep
        return dropped

    def building_tree(self):
        return STRtree([b.poly for b in self.buildings])

    def in_window(self, geom):
        """True in a full run, or when geom touches the window of a window
        run."""
        return self.window is None or self.window.intersects(geom)

    def claim(self, geom, owner):
        """Takes land (a polygon in metres) for a site module; owner names it
        in the claims list (e.g. "landmarks:japanese_garden")."""
        if geom is None or geom.is_empty:
            return
        self.claims.append((geom, owner))
        self._claimed = None

    def claimed(self):
        """All claimed land as one geometry (prepared)."""
        if self._claimed is None:
            self._claimed = unary_union([g for g, _ in self.claims]) if self.claims else None
            if self._claimed is not None:
                prepare(self._claimed)
        return self._claimed

    def district_taken(self):
        """What the district modules built, as one geometry: their buildings
        grown by DISTRICT_CLEAR_M, solid_extra and the ground obstacles.
        Worked out on first use, so call it only after they have run."""
        if self._district_taken is None:
            parts = [b.poly.buffer(DISTRICT_CLEAR_M) for b in self.buildings
                     if b.opts.get("stage") in DISTRICT_STAGES]
            parts += [g for g in self.solid_extra if g is not None and not g.is_empty]
            if self.obstacles is not None:
                u = self.obstacles.union()
                if u is not None and not u.is_empty:
                    parts.append(u)
            self._district_taken = unary_union(parts) if parts else None
            if self._district_taken is not None:
                prepare(self._district_taken)
        return self._district_taken

    def is_free(self, geom, margin=0.0, districts=True):
        """True when geom (grown by margin) is inside the play area, outside
        every KeepOut area, clear of the markers by MARKER_CLEAR_M, clear of
        every claim and, with districts, clear of what the district modules
        built."""
        g = geom.buffer(margin) if margin else geom
        x0, y0, x1, y1 = g.bounds
        if min(x0, y0) < -PLAY_HALF_M or max(x1, y1) > PLAY_HALF_M:
            return False
        if self.keep_out is not None and not self.keep_out.is_empty and g.intersects(self.keep_out):
            return False
        for _, mx, my in self.markers:
            if g.distance(Point(mx, my)) < MARKER_CLEAR_M:
                return False
        c = self.claimed()
        if c is not None and c.intersects(g):
            return False
        if districts:
            d = self.district_taken()
            if d is not None and d.intersects(g):
                return False
        return True

    def clear_area(self, area, prop_kinds=None):
        """Removes the prop spawns (of the given kinds, all when None) and the
        salvage sources whose centre is inside area. Returns (props removed,
        sources removed). The generic props placed later (props.build) keep
        clear of buildings and solid_extra on their own."""
        if area is None or area.is_empty:
            return 0, 0
        prepare(area)
        removed_p = removed_s = 0
        if self.props is not None and self.props.items:
            import props as props_mod
            keep = []
            for it in self.props.items:
                kind = props_mod.KINDS[it[0]]
                if (prop_kinds is None or kind in prop_kinds) and area.contains(Point(it[1], it[2])):
                    removed_p += 1
                    continue
                keep.append(it)
            if removed_p:
                self.props.replace_items(keep)
        if self.salvage is not None and self.salvage.items:
            keep = [it for it in self.salvage.items if not area.contains(Point(it[1], it[2]))]
            removed_s = len(self.salvage.items) - len(keep)
            self.salvage.items = keep
        return removed_p, removed_s

    def add_landmark(self, name, kind, geom, radius=None):
        """Registers a named place: name as the player sees it, kind a short
        tag (garden, observatory, cemetery, rail_yard, ...), geom its area in
        metres. radius defaults to the circle round geom's bounds."""
        c = geom.centroid
        if radius is None:
            x0, y0, x1, y1 = geom.bounds
            radius = 0.5 * float(np.hypot(x1 - x0, y1 - y0))
        hull = geom.convex_hull if geom.geom_type != "Polygon" else geom
        outline = [(float(x), float(y)) for x, y in hull.simplify(2.0).exterior.coords[:-1]] \
            if hull.geom_type == "Polygon" else []
        self.landmarks.append({"name": name, "kind": kind, "x": float(c.x), "y": float(c.y),
                               "radius": float(radius), "outline": outline})
