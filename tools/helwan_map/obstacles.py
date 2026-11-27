"""Ground obstacles: pipe runs, pipe racks and open pools. Mechas can't walk
through them; shots and sight pass over them (the game's ObstacleField puts
them on the barrier layer, one merged body per cell).

  pipe  a pipe rack is one outline round the whole rack; a single pipe run
        is its centre line buffered by its radius
  pool  the basin outline

Pipe bridges over roads and strut frames are not obstacles (overhead
visuals only).

Outlines are simplified (SIMPLIFY_M) and kept small: a run longer than
MAX_PIECE_M is cut into pieces, and an outline with more than MAX_POINTS
points is simplified harder.

obstacles.bin: int32 count n; per obstacle int32 kind (0 pipe, 1 pool),
int32 point count k, k x float32 x, y (world px). Closed outlines; the first
point is not repeated.
"""
import struct

import numpy as np
from shapely.geometry import Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

from frame import PX_PER_M

PIPE, POOL = 0, 1
SIMPLIFY_M = 0.3
MAX_POINTS = 64
MAX_PIECE_M = 60.0


def _parts(geom):
    if geom.is_empty:
        return []
    if geom.geom_type == "Polygon":
        return [geom]
    return [g for g in getattr(geom, "geoms", []) if g.geom_type == "Polygon" and not g.is_empty]


class Obstacles:
    def __init__(self):
        self.items = []

    def add(self, kind, geom):
        """Adds every polygon part of geom (map-frame metres). Holes are
        dropped: only the outline blocks."""
        for g in _parts(geom):
            for piece in self._split(g):
                self._add_one(kind, piece)

    def _split(self, g):
        x0, y0, x1, y1 = g.bounds
        if max(x1 - x0, y1 - y0) <= MAX_PIECE_M:
            return [g]
        nx = int(np.ceil((x1 - x0) / MAX_PIECE_M))
        ny = int(np.ceil((y1 - y0) / MAX_PIECE_M))
        out = []
        for i in range(nx):
            for j in range(ny):
                cell = box(x0 + i * (x1 - x0) / nx, y0 + j * (y1 - y0) / ny,
                           x0 + (i + 1) * (x1 - x0) / nx, y0 + (j + 1) * (y1 - y0) / ny)
                out += _parts(g.intersection(cell))
        return out

    def _add_one(self, kind, g):
        tol = SIMPLIFY_M
        s = g
        while True:
            s = g.simplify(tol, preserve_topology=True)
            s = _parts(s)
            s = max(s, key=lambda p: p.area) if s else None
            if s is None or len(s.exterior.coords) - 1 <= MAX_POINTS:
                break
            tol *= 1.6
        if s is None or s.area < 0.05:
            return
        pts = np.asarray(orient(s, 1.0).exterior.coords)[:-1]
        if len(pts) >= 3:
            self.items.append((kind, pts))

    def union(self):
        """All outlines as one geometry (metres)."""
        return unary_union([Polygon(p) for _, p in self.items])

    def counts(self):
        out = {"pipe": 0, "pool": 0}
        for k, _ in self.items:
            out["pipe" if k == PIPE else "pool"] += 1
        return out

    def write(self, path):
        with open(path, "wb") as fh:
            fh.write(struct.pack("<i", len(self.items)))
            for kind, pts in self.items:
                fh.write(struct.pack("<ii", kind, len(pts)))
                fh.write((pts * PX_PER_M).astype(np.float32).tobytes())
