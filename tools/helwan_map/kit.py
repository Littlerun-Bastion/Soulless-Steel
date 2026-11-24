"""Shared helpers for the district modules (industrial.py, market.py,
farmland.py): a local frame on a polygon, free-space placement, fences,
paving and a few ground shapes.

A Frame works in a polygon's local frame: x along its long axis, y across,
origin at the centre of its smallest turned rectangle. rect(), line() and
poly() turn local shapes into map-frame shapely geometry.
"""
import numpy as np
from shapely import affinity, prepare
from shapely.geometry import LineString, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import nearest_points, substring, unary_union

import style


def largest(geom):
    parts = style.polys(geom)
    return max(parts, key=lambda g: g.area) if parts else None


class Frame:
    def __init__(self, poly, ang=None):
        a, c = style.frame_of(poly)
        self.ang = a if ang is None else ang
        self.c = c
        loc = affinity.rotate(poly, -self.ang, origin=c)
        self.x0, self.y0, self.x1, self.y1 = (b - o for b, o in zip(loc.bounds, (c.x, c.y) * 2))
        self.cos, self.sin = np.cos(np.radians(self.ang)), np.sin(np.radians(self.ang))

    @property
    def w(self):
        return self.x1 - self.x0

    @property
    def h(self):
        return self.y1 - self.y0

    def pt(self, x, y):
        return (self.c.x + x * self.cos - y * self.sin, self.c.y + x * self.sin + y * self.cos)

    def pts(self, xy):
        return [self.pt(x, y) for x, y in xy]

    def rect(self, x0, y0, x1, y1):
        return Polygon(self.pts([(x0, y0), (x1, y0), (x1, y1), (x0, y1)]))

    def line(self, xy):
        return LineString(self.pts(xy))

    def poly(self, xy):
        return Polygon(self.pts(xy))

    def local(self, geom):
        return affinity.translate(affinity.rotate(geom, -self.ang, origin=self.c), -self.c.x, -self.c.y)

    def to_local(self, x, y):
        dx, dy = x - self.c.x, y - self.c.y
        return dx * self.cos + dy * self.sin, -dx * self.sin + dy * self.cos

    @property
    def rad(self):
        return np.radians(self.ang)


class Space:
    """Free space inside an area: place() finds a spot for a rectangle (in
    the area's frame, or turned by a given angle) that is inside the area and
    clear of everything taken so far."""

    def __init__(self, area, blocked=None):
        self.area = area
        prepare(self.area)
        self.taken = []
        if blocked is not None and not blocked.is_empty:
            self.taken.append(blocked)

    def free(self, geom, margin=0.0):
        if not self.area.contains(geom):
            return False
        g = geom.buffer(margin) if margin else geom
        return not any(g.intersects(t) for t in self.taken)

    def take(self, geom):
        self.taken.append(geom)

    def place(self, F, w, h, rng, margin=1.5, tries=40, region=None):
        """A w x h rectangle (local frame F) inside region (local x0, y0, x1,
        y1; default the whole frame), free and inside the area. Returns
        (x, y, polygon) of its corner, or None."""
        x0, y0, x1, y1 = region or (F.x0, F.y0, F.x1, F.y1)
        if x1 - x0 < w or y1 - y0 < h:
            return None
        for _ in range(tries):
            x = rng.uniform(x0, x1 - w)
            y = rng.uniform(y0, y1 - h)
            r = F.rect(x, y, x + w, y + h)
            if self.free(r, margin):
                self.take(r)
                return x, y, r
        return None


def fence(L, ring, rng, gate=None, v=0.3, sub="interiors", post_every=2.5, gates=()):
    """A light fence along a ring (shapely LinearRing or LineString), with
    posts, and a gap of about 9 m at each gate (a point)."""
    line = LineString(ring.coords)
    gap = 4.5
    cuts = sorted(line.project(g) for g in ([gate] if gate is not None else []) + list(gates))
    parts, d0 = [], 0.0
    for d in cuts:
        if d - gap > d0 + 0.5:
            parts.append(substring(line, d0, d - gap))
        d0 = max(d0, d + gap)
    if line.length > d0 + 0.5:
        parts.append(substring(line, d0, line.length))
    for part in parts:
        if part.is_empty or part.length < 0.5:
            continue
        L.line(sub, part, 0.07, v)
        n = int(part.length // post_every)
        for t in np.linspace(0, part.length, max(n, 2)):
            p = part.interpolate(t)
            L.fill(sub, box(p.x - 0.09, p.y - 0.09, p.x + 0.09, p.y + 0.09), v * 1.2)


def wall(L, ring, width, v, sub="interiors", gate=None):
    """A low wall along a ring, with a gate gap of about 4 m at gate."""
    line = LineString(ring.coords)
    if gate is not None:
        d = line.project(gate)
        parts = [substring(line, 0, max(0.0, d - 2.2)), substring(line, min(line.length, d + 2.2), line.length)]
    else:
        parts = [line]
    for part in parts:
        if part.is_empty or part.length < 0.3:
            continue
        L.line(sub, part, width + 0.3, 0.02, 0.55)
        L.line(sub, part, width, v)


def pave(L, geom, v=0.2, a=0.9, sub="groundlines", edge=True):
    """A paved or gravel surface over the ground."""
    if geom.is_empty:
        return
    L.fill(sub, geom, v, a)
    if edge:
        for g in style.polys(geom):
            L.line(sub, LineString(g.exterior.coords), 0.12, min(v * 1.5, 0.45), 0.7)


def soft_shadow(L, geom, width, a=0.45, sub="interiors"):
    for g in style.polys(geom):
        L.strip(sub, orient(g, 1.0).exterior, width, -1, a, 0.0)


def disc(x, y, r, n=24):
    a = np.linspace(0, 2 * np.pi, n, endpoint=False)
    return Polygon(np.stack([x + np.cos(a) * r, y + np.sin(a) * r], 1))


def nearest_edge_point(poly, roads_union, fallback=None):
    """The point of a polygon's outline nearest the roads (for a gate)."""
    if roads_union is None or roads_union.is_empty:
        return fallback
    return nearest_points(poly.exterior, roads_union)[0]


def union(geoms):
    geoms = [g for g in geoms if g is not None and not g.is_empty]
    return unary_union(geoms) if geoms else Polygon()


def point(x, y):
    return Point(x, y)
