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
"""
import numpy as np
from shapely import STRtree, contains_xy
from shapely.ops import unary_union

from gen_city import Sampler


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
        self._road_tree = None
        self._road_geoms = None

    def road_union_near(self, geom, dist=40.0):
        """The concrete of the roads within dist of geom (metres)."""
        if self._road_tree is None:
            self._road_geoms = [g for g, *_, kind, _ in self.roads if not kind.startswith("rail:")]
            self._road_tree = STRtree(self._road_geoms)
        idx = self._road_tree.query(geom.buffer(dist))
        return unary_union([self._road_geoms[i] for i in idx]) if len(idx) else None

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
