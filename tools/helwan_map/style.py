"""Draws the city layout in the old map's style and writes it per chunk.

The look: dark roofs with a light outline, an inset parapet line and roof
detail; a soft dark halo round every building; light concrete roads that
darken towards their edges, with a thin edge line; rail as a dark bed with
sleepers and two rails.

Geometry goes into seven sublayers. Each sublayer is one mesh per chunk, and
the scene draws all chunks of one sublayer before the next, so nothing in a
later sublayer is ever hidden by an earlier one from a neighbouring chunk:

  ground       water and concrete fills (clipped to the chunk)
  groundlines  concrete edge shadow, edge lines, road markings, rail, field
               furrows, rubble and scorch outside buildings
  halos        soft dark rings round buildings
  interiors    floors and walls, seen when a roof fades out; also ground
               objects that must draw over the halos (pipes, tank bunds,
               process skids, pool rims)
  roofs        buildings and their roof detail (whole building per chunk)
  overheads    pipe bridges over roads and strut frames, drawn above mechas
  talls        things that stand well above the roofs (crane masts and jibs,
               pylons and their wires, minarets, upper floors of building
               frames); every vertex has a height in metres, and the game
               shifts it away from the camera centre by its height, so tall
               things lean as they would in a real top-down view

The viaduct is not drawn here: the scene places it as an OverheadPath node.

A building's ruin state (see ruins.py) changes only its roofs, interiors,
ground and groundlines geometry. While a ruined roof is drawn, roof_cut
(holes) or roof_keep (the fragments left) clips every roof fill of that
building.

Layers.within(sub, poly) cuts every triangle added to a sublayer at an
outline while it is open (clip_tris). The generic roofs (draw_house,
draw_big, draw_pitched) draw within their footprint grown by ROOF_BOUND_M,
so no roof face, item, shadow or shading strip reaches past the outline
onto a road or a neighbour, and draw_interior within its footprint.

Output per chunk and sublayer is a small binary file:
  int32 vertex count, int32 index count, int32 channel flag (0 none, 1 roof
  channels follow, 2 a height channel follows), float32 x,y per vertex
  (world px), uint8 grey,alpha per vertex, then, for roofs, float32 building
  id per vertex (-1 for none) and float32 stripe coordinate per vertex (0 for
  none), or, for talls, float32 height per vertex (metres above the ground),
  then uint32 vertex indices.
Every three indices make one triangle, in drawing order. manifest.json maps
each mesh name to its bounds in world px ([x, y, width, height]). Roof geometry carries the id of its
building, so the roof shader can fade single buildings out. Pitched roof
faces carry a stripe coordinate, STRIPE_BASE plus the distance across the
tile courses in courses; the shader draws one line per course.

footprints.bin (version 2) lists every building's outline in id order:
  int32 building count n, then per building int32 point count and float32
  x,y per point (world px); then n uint8 ruin states (0 intact, 1 damaged,
  2 gutted, 3 collapsed) and n uint8 district codes (districts.py).
Every drawn building has a footprint, collapsed ones included.
"""
import json
import os
import struct
from contextlib import contextmanager

import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import LineString, LinearRing, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import substring, unary_union

from gen_city import CHUNK_M, CHUNKS, FRAME, HALF_M, min_width, rect_fill

PX = 20.0
SUBLAYERS = ("ground", "groundlines", "halos", "interiors", "roofs", "overheads", "talls")

WATER_V = 0.012
CONCRETE_V = 0.27
CONCRETE_EDGE_SHADOW_M = 0.9
CONCRETE_EDGE_SHADOW_A = 0.55
EDGE_LINE_V, EDGE_LINE_W = 0.34, 0.18
MARKING_V, MARKING_W = 0.32, 0.15

ROOF_V_MIN, ROOF_V_MAX = 0.045, 0.1
OUTLINE_V, OUTLINE_W = 0.38, 0.34
PARAPET_V, PARAPET_W = 0.2, 0.18
DETAIL_LINE_V = 0.28
HALO_A = 0.65
HALO_HOUSE_M, HALO_BIG_M = 2.4, 5.0
## How far the generic roofs reach past their footprint: the outer half of
## the outline drawn on it (OUTLINE_W, 1.3 times as wide on large roofs).
ROOF_BOUND_M = 0.25

RAIL_BED_V, SLEEPER_V, RAIL_V = 0.025, 0.17, 0.3
TRACK_SPACING_M = 4.5

STRIPE_BASE = 10000.0
TILE_COURSE_M = 0.42
SHEET_COURSE_M = 0.7
# Light on pitched roofs comes from the east-north-east (map y points down).
ROOF_LIGHT = np.array([1.0, -0.4]) / np.hypot(1.0, 0.4)


class Layers:
    def __init__(self):
        self.parts = {}
        # Id of the building being drawn; roof geometry is tagged with it.
        self.bid = -1
        self.footprints = []
        self.states = []
        self.districts = []
        # (origin, axis / course length) while drawing a pitched roof face.
        self.stripe = None
        # Clips for the roof of a ruined building (see the module notes).
        self.roof_cut = None
        self.roof_keep = None
        # Areas the roof kit keeps its items out of (roof holes, solar
        # installations), set per building by the caller.
        self.roof_taken = []
        # Rooftop salvage sources found while drawing the current building:
        # (kind, outline polygon, amount); the caller registers them.
        self.pending_sources = []
        # Height in metres given to talls geometry drawn without its own
        # per-vertex heights.
        self.height = 0.0
        # Sublayer -> prepared outline its triangles are cut at (within).
        self.bounds = {}

    def _put(self, sub, key, tris, grey, alpha, heights=None):
        bucket = self.parts.setdefault((sub, key), [[], [], [], [], []])
        pts = tris.reshape(-1, 2)
        bucket[0].append(pts)
        bucket[1].append(grey.reshape(-1))
        bucket[2].append(alpha.reshape(-1))
        bid = self.bid if sub == "roofs" else -1
        bucket[3].append(np.full(grey.size, bid, np.float32))
        if sub == "talls":
            h = np.full(grey.size, self.height, np.float32) if heights is None else heights
            bucket[4].append(np.asarray(h, np.float32).reshape(-1))
        elif sub == "roofs" and self.stripe is not None:
            origin, axis = self.stripe
            bucket[4].append((STRIPE_BASE + (pts - origin) @ axis).astype(np.float32))
        else:
            bucket[4].append(np.zeros(grey.size, np.float32))

    def add_building(self, poly, state=0, district=0):
        """Registers a footprint and makes it the current building."""
        self.bid = len(self.footprints)
        self.footprints.append(np.asarray(poly.exterior.coords)[:-1] * PX)
        self.states.append(int(state))
        self.districts.append(int(district))
        return self.bid

    def set_roof_clip(self, cut=None, keep=None):
        self.roof_cut = cut if cut is not None and not cut.is_empty else None
        self.roof_keep = keep
        for g in (self.roof_cut, self.roof_keep):
            if g is not None:
                shapely.prepare(g)

    @contextmanager
    def within(self, sub, poly, grow=0.02):
        """While open, every triangle added to sublayer sub is cut at poly
        grown by grow metres (mitred; the default hair keeps geometry drawn
        on the outline itself whole). An outer within on the same sublayer
        stays in force."""
        if sub in self.bounds:
            yield
            return
        g = poly.buffer(grow, join_style="mitre", mitre_limit=2.0)
        shapely.prepare(g)
        self.bounds[sub] = (g, notches(g))
        try:
            yield
        finally:
            del self.bounds[sub]

    def add_tris(self, sub, tris, v, a=1.0, chunk=None, va=None, vg=None, vh=None):
        """tris (n, 3, 2) in metres. chunk None puts each triangle in the chunk
        holding its centre; a chunk key keeps them all together. va and vg
        give alpha and grey per vertex ((n, 3)) instead of a and v. vh gives
        talls heights per vertex ((n, 3), metres) instead of self.height."""
        if len(tris) == 0:
            return
        if sub == "roofs" and (self.roof_cut is not None or self.roof_keep is not None):
            cen = tris.mean(1)
            sel = np.ones(len(tris), bool)
            if self.roof_cut is not None:
                sel &= ~shapely.contains_xy(self.roof_cut, cen[:, 0], cen[:, 1])
            if self.roof_keep is not None:
                sel &= shapely.contains_xy(self.roof_keep, cen[:, 0], cen[:, 1])
            tris = tris[sel]
            if va is not None:
                va = va[sel]
            if vg is not None:
                vg = vg[sel]
            if len(tris) == 0:
                return
        grey = np.full(tris.shape[:2], v, float) if vg is None else vg
        alpha = np.full(tris.shape[:2], a, float) if va is None else va
        if sub == "talls" and vh is None:
            vh = np.full(tris.shape[:2], self.height, np.float32)
        bound = self.bounds.get(sub)
        if bound is not None:
            tris, grey, alpha, vh = clip_tris(tris, *bound, grey, alpha, vh)
            if len(tris) == 0:
                return
        if chunk is not None:
            self._put(sub, chunk, tris, grey, alpha, vh)
            return
        cen = tris.mean(1)
        keys = chunk_of(cen)
        for k in np.unique(keys, axis=0):
            sel = np.all(keys == k, axis=1)
            self._put(sub, tuple(k), tris[sel], grey[sel], alpha[sel], None if vh is None else vh[sel])

    def fill(self, sub, geom, v, a=1.0, chunk=None, clip=False, h=None):
        """h: the height in metres of a talls fill (self.height when None)."""
        if geom.is_empty:
            return
        if h is not None:
            keep, self.height = self.height, float(h)
            try:
                self.fill(sub, geom, v, a, chunk, clip)
            finally:
                self.height = keep
            return
        if sub == "roofs":
            if self.roof_cut is not None:
                geom = geom.difference(self.roof_cut)
            if self.roof_keep is not None:
                geom = geom.intersection(self.roof_keep)
            if geom.is_empty:
                return
        if clip:
            for key, cb in chunk_boxes():
                if geom.intersects(cb):
                    self.add_tris(sub, triangulate(geom.intersection(cb)), v, a, chunk=key)
        else:
            self.add_tris(sub, triangulate(geom), v, a, chunk=chunk)

    def line(self, sub, line, width, v, a=1.0, chunk=None, h=None):
        if line.is_empty or line.length == 0:
            return
        self.fill(sub, line.buffer(width / 2, cap_style="flat", join_style="mitre", mitre_limit=3), v, a, chunk,
                  h=h)

    def tall_prism(self, poly, h0, h1, v_side, v_top, a=1.0, chunk=None):
        """A solid that stands from h0 to h1 metres on poly's outline: one
        quad per outline edge from the edge at h0 to the edge at h1, then the
        top at h1 over them. With the game's height shift the quads facing
        away from the camera end up under the top, so only the near sides
        show, as on a real tall object seen from above."""
        for part in polys(poly):
            ring = np.asarray(orient(part).exterior.coords)
            p, q = ring[:-1], ring[1:]
            if len(p) < 3:
                continue
            tris = np.concatenate([np.stack([p, q, q], 1), np.stack([p, q, p], 1)])
            vh = np.concatenate([np.tile([h0, h0, h1], (len(p), 1)), np.tile([h0, h1, h1], (len(p), 1))])
            self.add_tris("talls", tris, v_side, a, chunk=chunk or chunk_key(part), vh=vh.astype(np.float32))
            self.fill("talls", part, v_top, a, chunk=chunk or chunk_key(part), h=h1)

    def tall_post(self, x, y, width, h0, h1, v_side, v_top, a=1.0, ang=0.0, chunk=None):
        """A square post (mast, minaret shaft, pylon leg) width metres across
        standing from h0 to h1."""
        r = width / 2
        self.tall_prism(affinity.rotate(box(x - r, y - r, x + r, y + r), ang, origin=(x, y)), h0, h1,
                        v_side, v_top, a, chunk)

    def tall_span(self, p0, p1, width, h0, h1, v, a=1.0, chunk=None):
        """A flat strip from p0 (at h0 metres) to p1 (at h1 metres): a jib, a
        wire, a beam. Heights run linearly along it."""
        (x0, y0), (x1, y1) = p0, p1
        d = np.array([x1 - x0, y1 - y0], float)
        n = float(np.hypot(*d))
        if n < 1e-6:
            return
        side = np.array([-d[1], d[0]]) / n * (width / 2)
        a0, a1 = np.array([x0, y0]) + side, np.array([x0, y0]) - side
        b0, b1 = np.array([x1, y1]) + side, np.array([x1, y1]) - side
        tris = np.array([[a0, b0, b1], [a0, b1, a1]])
        vh = np.array([[h0, h1, h1], [h0, h1, h0]], np.float32)
        key = chunk or tuple(chunk_of([[(x0 + x1) / 2, (y0 + y1) / 2]])[0])
        self.add_tris("talls", tris, v, a, chunk=key, vh=vh)

    def strip(self, sub, ring, width, side, a0, a1, v=0.0, chunk=None):
        """Gradient band along a ring: alpha a0 on the ring, a1 at the offset
        edge. side +1 offsets to the ring's left (into an oriented polygon),
        -1 to its right (out of it)."""
        p = np.asarray(ring.coords)[:-1]
        if len(p) < 3:
            return
        d = np.roll(p, -1, 0) - p
        ln = np.hypot(d[:, 0], d[:, 1])
        keep = ln > 1e-3
        p, d, ln = p[keep], d[keep], ln[keep]
        if len(p) < 3:
            return
        nl = np.stack([-d[:, 1], d[:, 0]], 1) / ln[:, None]
        prev = np.roll(nl, 1, 0)
        vn = prev + nl
        vl = np.hypot(vn[:, 0], vn[:, 1])
        vn = vn / np.maximum(vl, 1e-6)[:, None]
        scale = 1.0 / np.clip((vn * nl).sum(1), 0.4, 1.0)
        outer = p + vn * (side * width * scale)[:, None]
        q = np.roll(p, -1, 0)
        qo = np.roll(outer, -1, 0)
        t1 = np.stack([p, q, qo], 1)
        t2 = np.stack([p, qo, outer], 1)
        tris = np.concatenate([t1, t2])
        va = np.concatenate([np.tile([a0, a0, a1], (len(p), 1)), np.tile([a0, a1, a1], (len(p), 1))])
        self.add_tris(sub, tris, v, chunk=chunk, va=va)

    def write(self, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        manifest, total = {}, 0
        for (sub, key), (t, g, a, ids, stripes) in sorted(self.parts.items()):
            xy = (np.concatenate(t) * PX).astype(np.float32)
            ga = np.stack([np.concatenate(g), np.concatenate(a)], 1)
            ga = (np.clip(ga, 0, 1) * 255 + 0.5).astype(np.uint8)
            flag = 1 if sub == "roofs" else 2 if sub == "talls" else 0
            name = f"{sub}_{key[0]}_{key[1]}"
            # Triangle corners that are the same vertex become one vertex
            # plus an index list.
            cols = [xy.view(np.uint8).reshape(len(xy), 8), ga]
            if flag == 1:
                rid = np.concatenate(ids).astype(np.float32)
                rst = np.concatenate(stripes).astype(np.float32)
                cols += [rid.view(np.uint8).reshape(-1, 4), rst.view(np.uint8).reshape(-1, 4)]
            elif flag == 2:
                hgt = np.concatenate(stripes).astype(np.float32)
                cols.append(hgt.view(np.uint8).reshape(-1, 4))
            rows = np.ascontiguousarray(np.concatenate(cols, 1))
            keyv = rows.view(np.dtype((np.void, rows.shape[1]))).ravel()
            _, first, index = np.unique(keyv, return_index=True, return_inverse=True)
            index = index.astype(np.uint32).ravel()
            with open(os.path.join(out_dir, name + ".bin"), "wb") as fh:
                fh.write(struct.pack("<iii", len(first), len(index), flag))
                fh.write(xy[first].tobytes())
                fh.write(ga[first].tobytes())
                if flag == 1:
                    fh.write(rid[first].tobytes())
                    fh.write(rst[first].tobytes())
                elif flag == 2:
                    fh.write(hgt[first].tobytes())
                fh.write(index.tobytes())
            lo, hi = xy.min(0), xy.max(0)
            manifest[name] = [float(lo[0]), float(lo[1]), float(hi[0] - lo[0]), float(hi[1] - lo[1])]
            total += len(index) // 3
        with open(os.path.join(out_dir, "footprints.bin"), "wb") as fh:
            fh.write(struct.pack("<i", len(self.footprints)))
            for pts in self.footprints:
                fh.write(struct.pack("<i", len(pts)))
                fh.write(pts.astype(np.float32).tobytes())
            fh.write(np.asarray(self.states, np.uint8).tobytes())
            fh.write(np.asarray(self.districts, np.uint8).tobytes())
        with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh)
        return manifest, total


def chunk_of(pts):
    ij = np.floor((np.asarray(pts) + HALF_M) / CHUNK_M).astype(int)
    ij = np.clip(ij, 0, CHUNKS - 1)
    return np.stack([ij[:, 1], ij[:, 0]], 1)


def chunk_key(geom):
    c = geom.centroid
    return tuple(chunk_of([[c.x, c.y]])[0])


def chunk_boxes():
    for r in range(CHUNKS):
        for c in range(CHUNKS):
            x0, y0 = -HALF_M + c * CHUNK_M, -HALF_M + r * CHUNK_M
            yield (r, c), box(x0, y0, x0 + CHUNK_M, y0 + CHUNK_M)


def polys(geom):
    if geom.is_empty:
        return []
    if geom.geom_type == "Polygon":
        return [geom]
    return [g for g in getattr(geom, "geoms", []) if g.geom_type == "Polygon" and not g.is_empty]


def triangulate(geom):
    out = []
    for g in polys(geom):
        if len(g.interiors) == 0 and len(g.exterior.coords) == 5:
            c = np.asarray(g.exterior.coords)[:4]
            out.append(np.stack([c[[0, 1, 2]], c[[0, 2, 3]]]))
            continue
        t = shapely.constrained_delaunay_triangles(g)
        cs = shapely.get_coordinates(t.geoms if hasattr(t, "geoms") else [t])
        if len(cs):
            out.append(cs.reshape(-1, 4, 2)[:, :3])
    return np.concatenate(out) if out else np.zeros((0, 3, 2))


def outline_segments(geom):
    """Every edge of a polygon's rings as (k, 2, 2) start and end points."""
    segs = []
    for p in polys(geom):
        for ring in [p.exterior, *p.interiors]:
            c = np.asarray(ring.coords)
            segs.append(np.stack([c[:-1], c[1:]], 1))
    return np.concatenate(segs) if segs else np.zeros((0, 2, 2))


def _boxes_meet(lo, hi, boxes):
    """(n, b): whether each box lo..hi ((n, 2) corners) meets each of boxes
    ((b, 4): x0, y0, x1, y1)."""
    return ((lo[:, None, 0] <= boxes[None, :, 2]) & (hi[:, None, 0] >= boxes[None, :, 0]) &
            (lo[:, None, 1] <= boxes[None, :, 3]) & (hi[:, None, 1] >= boxes[None, :, 1]))


def notches(geom):
    """None for a convex polygon. Otherwise the bounding boxes ((p, 4)) of
    its notches (the parts of its convex hull outside it, holes included)
    and the outline segments near them: only there can the outline cut into
    a triangle whose corners are all inside (see clip_tris)."""
    hull = geom.convex_hull
    if hull.area - geom.area < 1e-6:
        return None
    pockets = [p for p in polys(hull.difference(geom)) if p.area > 1e-8]
    if not pockets:
        return None
    boxes = np.array([p.bounds for p in pockets])
    segs = outline_segments(geom)
    near = _boxes_meet(segs.min(1), segs.max(1), boxes).any(1)
    return segs[near], boxes


def _turn(o, a, b):
    return (a[..., 0] - o[..., 0]) * (b[..., 1] - o[..., 1]) - (a[..., 1] - o[..., 1]) * (b[..., 0] - o[..., 0])


def _crossed(tris, segs):
    """Which triangles an outline (segs, (k, 2, 2)) cuts into although all
    their corners are inside it: one of the triangle's edges crosses one of
    the outline's, or a vertex of the outline lies inside the triangle."""
    out = np.zeros(len(tris), bool)
    r, s = segs[None, None, :, 0], segs[None, None, :, 1]
    step = max(1, 60000 // max(len(segs), 1))
    for i0 in range(0, len(tris), step):
        t = tris[i0:i0 + step]
        p, q = t[:, :, None, :], np.roll(t, -1, 1)[:, :, None, :]
        d1, d2 = _turn(p, q, r), _turn(p, q, s)
        cross = ((d1 * d2 < 0) & (_turn(r, s, p) * _turn(r, s, q) < 0)).any((1, 2))
        poke = ((d1 > 1e-9).all(1) | (d1 < -1e-9).all(1)).any(1)
        out[i0:i0 + step] = cross | poke
    return out


def clip_tris(tris, bound, notched, *attrs):
    """The parts of triangles (n, 3, 2) that lie in a prepared polygon, as
    triangles, with their per-vertex attributes ((n, 3) arrays, or None)
    interpolated to the new corners. notched: the polygon's notches(). A
    triangle with its three corners in the polygon is kept whole unless it
    reaches into a notch and the outline cuts into it there (_crossed); any
    other is intersected with the polygon and the piece triangulated."""
    pts = tris.reshape(-1, 2)
    inside = shapely.intersects_xy(bound, pts[:, 0], pts[:, 1]).reshape(-1, 3).all(1)
    if notched is not None and inside.any():
        segs, boxes = notched
        sel = np.flatnonzero(inside)
        sel = sel[_boxes_meet(tris[sel].min(1), tris[sel].max(1), boxes).any(1)]
        if len(sel):
            inside[sel[_crossed(tris[sel], segs)]] = False
    if inside.all():
        return (tris,) + attrs
    out = [[tris[inside]]] + [None if a is None else [a[inside]] for a in attrs]
    cut = np.flatnonzero(~inside)
    e1, e2 = tris[cut, 1] - tris[cut, 0], tris[cut, 2] - tris[cut, 0]
    cut = cut[np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]) > 1e-9]
    rings = np.concatenate([tris[cut], tris[cut, :1]], 1)
    pieces = shapely.intersection(shapely.polygons(rings), bound) if len(cut) else []
    for i, piece in zip(cut, pieces):
        found = []
        for g in polys(piece):
            t = shapely.constrained_delaunay_triangles(g)
            cs = shapely.get_coordinates(t)
            if len(cs):
                found.append(cs.reshape(-1, 4, 2)[:, :3])
        if not found:
            continue
        t = np.concatenate(found)
        # Barycentric weights of the new corners in the original triangle.
        a, b, c = tris[i]
        v0, v1, v2 = b - a, c - a, t.reshape(-1, 2) - a
        den = v0[0] * v1[1] - v1[0] * v0[1]
        wb = (v2[:, 0] * v1[1] - v1[0] * v2[:, 1]) / den
        wc = (v0[0] * v2[:, 1] - v2[:, 0] * v0[1]) / den
        w = np.stack([1.0 - wb - wc, wb, wc], 1)
        out[0].append(t)
        for got, at in zip(out[1:], attrs):
            if got is not None:
                got.append((w @ np.asarray(at[i], float)).reshape(-1, 3))
    return tuple(None if got is None else np.concatenate(got) for got in out)


def frame_of(poly):
    """Angle (degrees) and centre of a footprint's long axis."""
    rr = poly.minimum_rotated_rectangle
    xy = np.asarray(rr.exterior.coords)
    e1, e2 = xy[1] - xy[0], xy[2] - xy[1]
    long_e = e1 if np.hypot(*e1) >= np.hypot(*e2) else e2
    return np.degrees(np.arctan2(long_e[1], long_e[0])), rr.centroid


def local_rect(c, ang, x0, y0, x1, y1):
    return affinity.rotate(box(c.x + x0, c.y + y0, c.x + x1, c.y + y1), ang, origin=c)


def local_line(c, ang, pts):
    return affinity.rotate(LineString([(c.x + x, c.y + y) for x, y in pts]), ang, origin=c)


def roof_value(mockup_v):
    t = np.clip((mockup_v - 0.05) / 0.3, 0, 1)
    return ROOF_V_MIN + t * (ROOF_V_MAX - ROOF_V_MIN)


def outlined(L, sub, poly, v, chunk, outline_v=OUTLINE_V, w=OUTLINE_W, a=1.0):
    L.fill(sub, poly, v, a, chunk)
    for g in polys(poly):
        L.line(sub, LinearRing(g.exterior.coords), w, outline_v, a, chunk)


## Triangles drawn by the Batch-built parts of the roof kit and by the
## fabric module's estates and building sites, by item name, and how many
## times each was drawn (KIT_COUNT; "cairo_roofs" counts the Cairo roofs
## that could take an unfinished top floor); fabric.py reports them in
## stats.json.
KIT_TRIS = {}
KIT_COUNT = {}


def counted(name, fn):
    """fn (a drawer f(L) or a building's draw f(L, b, rng, salvage)) with
    every triangle it adds to any sublayer counted in KIT_TRIS[name]: the
    Layers' _put is wrapped while fn runs."""
    def run(L, *args):
        put = L._put

        def tally(sub, key, tris, grey, alpha, heights=None):
            KIT_TRIS[name] = KIT_TRIS.get(name, 0) + grey.size // 3
            return put(sub, key, tris, grey, alpha, heights)
        L._put = tally
        try:
            return fn(L, *args)
        finally:
            del L._put
    return run


class Batch:
    """Triangles collected in a local frame (origin c, angle ang in degrees:
    the frame of a Roof or a kit.Frame) and added to a sublayer in one call,
    with no shapely work: quads, thin lines, discs (fans of n sides) and, for
    the talls sublayer, upright posts and prisms. Every vertex has a grey,
    an alpha and a height in metres (used only by talls)."""

    def __init__(self, c, ang):
        self.o = np.array([c.x, c.y], float) if hasattr(c, "x") else np.asarray(c, float)
        a = np.radians(ang)
        self.cs, self.sn = float(np.cos(a)), float(np.sin(a))
        self.t, self.g, self.a, self.h = [], [], [], []

    def world(self, pts):
        p = np.asarray(pts, float).reshape(-1, 2)
        return np.stack([self.o[0] + p[:, 0] * self.cs - p[:, 1] * self.sn,
                         self.o[1] + p[:, 0] * self.sn + p[:, 1] * self.cs], 1)

    def local(self, x, y):
        dx, dy = x - self.o[0], y - self.o[1]
        return dx * self.cs + dy * self.sn, -dx * self.sn + dy * self.cs

    def tri(self, pts, v, a=1.0, h=0.0):
        """pts: three local points; a and h a value or one per point."""
        self.t.append(self.world(pts))
        self.g.append((v, v, v))
        self.a.append(np.broadcast_to(np.asarray(a, float), (3,)))
        self.h.append(np.broadcast_to(np.asarray(h, float), (3,)))

    def quad(self, pts, v, a=1.0, h=0.0):
        """pts: four local points in order round the quad; a and h a value or
        one per point."""
        q = self.world(pts)
        aa = np.broadcast_to(np.asarray(a, float), (4,))
        hh = np.broadcast_to(np.asarray(h, float), (4,))
        self.t += [q[[0, 1, 2]], q[[0, 2, 3]]]
        self.g += [(v, v, v)] * 2
        self.a += [aa[[0, 1, 2]], aa[[0, 2, 3]]]
        self.h += [hh[[0, 1, 2]], hh[[0, 2, 3]]]

    def rect(self, x0, y0, x1, y1, v, a=1.0, h=0.0):
        self.quad([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], v, a, h)

    def line(self, x0, y0, x1, y1, w, v, a=1.0, h0=0.0, h1=None):
        """A strip w wide from (x0, y0) at h0 to (x1, y1) at h1 (h0 when
        None)."""
        d = np.array([x1 - x0, y1 - y0], float)
        n = float(np.hypot(*d))
        if n < 1e-6:
            return
        nx, ny = -d[1] / n * w / 2, d[0] / n * w / 2
        h1 = h0 if h1 is None else h1
        self.quad([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)], v, a,
                  (h0, h1, h1, h0))

    def poly(self, pts, v, a=1.0, h=0.0):
        """A convex polygon (local points in order) as a fan."""
        for i in range(1, len(pts) - 1):
            self.tri([pts[0], pts[i], pts[i + 1]], v, a, h)

    def disc(self, x, y, r, v, n=8, a=1.0, h=0.0):
        ang = np.linspace(0, 2 * np.pi, n, endpoint=False) + np.pi / n
        self.poly(list(zip(x + np.cos(ang) * r, y + np.sin(ang) * r)), v, a, h)

    def post(self, x, y, w, h0, h1, v, a=1.0):
        """A thin upright in the talls sublayer: two crossed quads standing
        from h0 to h1, so it shows as a strip whichever way the game's height
        shift leans it."""
        r = w / 2
        hh = (h0, h0, h1, h1)
        self.quad([(x - r, y), (x + r, y), (x + r, y), (x - r, y)], v, a, hh)
        self.quad([(x, y - r), (x, y + r), (x, y + r), (x, y - r)], v, a, hh)

    def prism(self, pts, h0, h1, v_side, v_top, a=1.0, top=True):
        """A solid on a convex outline (local points) from h0 to h1 in the
        talls sublayer: a quad per side, then the top. The game's height
        shift tucks the far sides under the top."""
        n = len(pts)
        for i in range(n):
            p, q = pts[i], pts[(i + 1) % n]
            self.quad([p, q, q, p], v_side, a, (h0, h0, h1, h1))
        if top:
            self.poly(pts, v_top, a, h1)

    def count(self):
        return len(self.t)

    def flush(self, L, sub, chunk, name=None):
        """Adds the triangles to a sublayer (all in one chunk) and returns
        how many there were; name counts them in KIT_TRIS."""
        n = len(self.t)
        if n:
            L.add_tris(sub, np.array(self.t), 0.0, chunk=chunk, va=np.array(self.a), vg=np.array(self.g),
                       vh=np.array(self.h, np.float32) if sub == "talls" else None)
            if name:
                KIT_TRIS[name] = KIT_TRIS.get(name, 0) + n
                KIT_COUNT[name] = KIT_COUNT.get(name, 0) + 1
        self.t, self.g, self.a, self.h = [], [], [], []
        return n


class Roof:
    """A roof being decorated: its chunk, base value, local frame (angle and
    centre of the long axis), the usable area inside the parapet, and what
    has been placed on it so far."""

    def __init__(self, L, poly, v, rng):
        self.L, self.v, self.rng = L, v, rng
        self.key = chunk_key(poly)
        self.ang, self.c = frame_of(poly)
        loc = affinity.rotate(poly, -self.ang, origin=self.c)
        self.x0, self.y0, self.x1, self.y1 = (b - o for b, o in zip(loc.bounds, (self.c.x, self.c.y) * 2))
        self.inner = poly
        # Spots already used: anything the caller blocked (roof holes,
        # solar installations), then each item placed.
        self.taken = list(L.roof_taken)
        # AC boxes (rectangles) placed by item_vents; a roof with any is a
        # roof_ac salvage source.
        self.ac = []
        # The way shadows fall in the roof's local frame (away from
        # ROOF_LIGHT), one metre long.
        a = np.radians(self.ang)
        self.shade = (float(-ROOF_LIGHT[0] * np.cos(a) - ROOF_LIGHT[1] * np.sin(a)),
                      float(ROOF_LIGHT[0] * np.sin(a) - ROOF_LIGHT[1] * np.cos(a)))

    def batch(self):
        return Batch(self.c, self.ang)

    def rect(self, x0, y0, x1, y1):
        return local_rect(self.c, self.ang, x0, y0, x1, y1)

    def line(self, pts):
        return local_line(self.c, self.ang, pts)

    def place(self, w, h, margin=0.3, tries=12, near=None):
        """A free w x h spot inside the parapet, in local coordinates. near
        (x, y, radius) keeps the spot within radius of a point."""
        x0, y0, x1, y1 = self.x0, self.y0, self.x1, self.y1
        if near:
            nx, ny, rad = near
            x0, y0, x1, y1 = max(x0, nx - rad), max(y0, ny - rad), min(x1, nx + rad), min(y1, ny + rad)
        for _ in range(tries):
            if x1 - x0 < w or y1 - y0 < h:
                return None
            x = self.rng.uniform(x0, x1 - w)
            y = self.rng.uniform(y0, y1 - h)
            r = self.rect(x, y, x + w, y + h)
            if not self.inner.contains(r):
                continue
            grown = r.buffer(margin)
            if any(grown.intersects(t) for t in self.taken):
                continue
            self.taken.append(r)
            return x, y, r
        return None

    def fill(self, geom, v, a=1.0):
        self.L.fill("roofs", geom, v, a, chunk=self.key)

    def stroke(self, geom, w, v, a=1.0):
        self.L.line("roofs", geom, w, v, a, chunk=self.key)

    def ring(self, poly, w, v):
        for g in polys(poly):
            self.stroke(LinearRing(g.exterior.coords), w, v)

    def shade_out(self, poly, width, a=0.5):
        for g in polys(poly):
            self.L.strip("roofs", orient(g, 1.0).exterior, width, -1, a, 0.0, chunk=self.key)

    def shade_in(self, poly, width, a=0.4):
        for g in polys(poly):
            self.L.strip("roofs", orient(g, 1.0).exterior, width, +1, a, 0.0, chunk=self.key)


def set_inner(roof, poly, inset):
    inner = poly.buffer(-inset, join_style="mitre")
    roof.inner = inner if not inner.is_empty else poly
    return inner


def item_annex(R, scale):
    """A raised block on the roof (plant room, upper storey): its own outline,
    parapet line and a soft shadow onto the roof round it."""
    sx, sy = R.x1 - R.x0, R.y1 - R.y0
    w = sx * R.rng.uniform(0.3, 0.55)
    h = sy * R.rng.uniform(0.35, 0.65)
    spot = R.place(max(w, 2.0), max(h, 2.0))
    if not spot:
        return
    x, y, r = spot
    R.shade_out(r, 0.9 * scale, 0.55)
    R.fill(r, min(R.v * 1.3, 0.13))
    inner = r.buffer(-0.35 * scale, join_style="mitre")
    R.shade_in(inner, 0.6 * scale, 0.35)
    R.ring(inner, PARAPET_W * 0.8, PARAPET_V)
    R.ring(r, OUTLINE_W * 0.7, OUTLINE_V * 0.85)


def item_stair(R, scale):
    spot = R.place(R.rng.uniform(2.0, 3.2) * scale, R.rng.uniform(1.8, 2.8) * scale)
    if not spot:
        return
    _, _, r = spot
    R.shade_out(r, 0.6, 0.45)
    R.fill(r, min(R.v * 1.5, 0.12))
    R.ring(r, 0.12, OUTLINE_V * 0.8)


def item_tanks(R, scale):
    """Two round tanks joined by a pipe, with crosshair lid lines."""
    r1 = R.rng.uniform(0.6, 1.0) * scale
    r2 = r1 * R.rng.uniform(0.55, 0.8)
    a = R.place(2 * r1, 2 * r1)
    if not a:
        return
    b = R.place(2 * r2, 2 * r2, margin=0.6 * scale, near=(a[0] + r1, a[1] + r1, 4.0 * r1))
    centres = []
    for spot, r in ((a, r1), (b, r2)):
        if not spot:
            continue
        x, y, _ = spot
        centres.append((x + r, y + r, r))
    B = R.batch()
    if len(centres) == 2:
        (xa, ya, _), (xb, yb, _) = centres
        B.line(xa, ya, xb, yb, 0.16 * scale, 0.01)
    sx, sy = R.shade
    for x, y, r in centres:
        n = 12 if r * scale < 2 else 18
        if scale > 1:
            B.disc(x + sx * 0.3 * scale, y + sy * 0.3 * scale, r * 1.08, 0.0, n, 0.45)
        # A light rim: the tank's disc drawn over a slightly larger light one.
        B.disc(x, y, r, DETAIL_LINE_V * 0.85, n)
        B.disc(x, y, r - 0.07 * scale, min(R.v * 1.25, 0.11), n)
        if scale > 1:
            B.disc(x, y, r * 0.6, min(R.v * 1.45, 0.13), n)
        w = 0.04 * scale
        B.line(x - r * 0.9, y, x + r * 0.9, y, w, 0.12)
        B.line(x, y - r * 0.9, x, y + r * 0.9, w, 0.12)
        q = r * 0.14
        B.rect(x - q, y - q, x + q, y + q, 0.008)
    B.flush(R.L, "roofs", R.key, "tanks")


def item_dishes(R, scale):
    """One to three satellite dishes on short masts, each a pale disc with a
    feed arm and a shadow."""
    B = R.batch()
    sx, sy = R.shade
    for _ in range(int(R.rng.integers(1, 4))):
        r = R.rng.uniform(0.35, 0.55) * scale
        spot = R.place(2 * r + 0.3, 2 * r + 0.3)
        if not spot:
            break
        x, y, _ = spot
        x, y = x + 0.15 + r, y + 0.15 + r
        B.disc(x + sx * 0.18 * scale, y + sy * 0.18 * scale, r * 1.1, 0.0, 8, 0.4)
        B.disc(x, y, r, DETAIL_LINE_V, 10)
        B.disc(x, y, r - 0.05 * scale, min(R.v * 2.2, 0.3), 10)
        a = R.rng.uniform(0, 2 * np.pi)
        B.line(x, y, x + np.cos(a) * r * 0.9, y + np.sin(a) * r * 0.9, 0.05 * scale, 0.06)
    B.flush(R.L, "roofs", R.key, "dishes")


def item_vents(R, scale):
    """Two to four fan units joined by ducts that run along the roof's axes."""
    n = int(R.rng.integers(2, 5))
    s = R.rng.uniform(0.7, 1.2) * scale
    units = []
    for _ in range(n):
        near = (units[0][0], units[0][1], 5.0 * scale) if units else None
        spot = R.place(s, s, margin=0.8 * scale, near=near)
        if spot:
            x, y, r = spot
            units.append((x + s / 2, y + s / 2, r))
    if len(units) < 2:
        for *_, r in units:
            R.taken.remove(r)
        return
    for (xa, ya, _), (xb, yb, _) in zip(units[:-1], units[1:]):
        duct = R.line([(xa, ya), (xb, ya), (xb, yb)]).intersection(R.inner)
        R.stroke(duct, 0.34 * scale, 0.012)
        R.stroke(duct, 0.06 * scale, 0.09)
    for xc, yc, r in units:
        R.ac.append(r)
        if scale > 1:
            R.shade_out(r, 0.35 * scale, 0.45)
        R.fill(r, 0.1)
        R.ring(r, 0.07 * scale, DETAIL_LINE_V * 0.85)
        R.fill(R.rect(xc - s * 0.22, yc - s * 0.22, xc + s * 0.22, yc + s * 0.22), 0.015)


def item_xpanels(R, scale):
    """A row of light X-braced panels (skylights or grilles)."""
    k = int(R.rng.integers(2, 6))
    s = R.rng.uniform(1.0, 1.6) * scale
    spot = R.place(k * s, s)
    if not spot:
        return
    x, y, r = spot
    R.shade_out(r, 0.4 * scale, 0.45)
    R.fill(r, 0.12)
    for i in range(k):
        cx = x + i * s
        R.stroke(R.line([(cx, y), (cx + s, y + s)]), 0.06 * scale, 0.02)
        R.stroke(R.line([(cx, y + s), (cx + s, y)]), 0.06 * scale, 0.02)
        if i:
            R.stroke(R.line([(cx, y), (cx, y + s)]), 0.07 * scale, 0.02)
    R.ring(r, 0.08 * scale, 0.02)


def item_hatch(R, scale):
    """A dark recessed opening with heavy corner brackets."""
    w, h = R.rng.uniform(1.6, 3.0) * scale, R.rng.uniform(1.2, 2.2) * scale
    spot = R.place(w, h)
    if not spot:
        return
    x, y, r = spot
    R.fill(r, 0.015)
    R.ring(r, 0.07 * scale, 0.14)
    b = min(w, h) * 0.3
    for (px, py), (dx, dy) in (((x, y), (1, 1)), ((x + w, y + h), (-1, -1))):
        R.stroke(R.line([(px + dx * b, py + dy * 0.1), (px + dx * 0.1, py + dy * 0.1), (px + dx * 0.1, py + dy * b)]), 0.1 * scale, 0.0)


def item_struts(R, scale):
    """A braced strut band along one long side, just inside the parapet."""
    if R.x1 - R.x0 < 6 * scale:
        return
    band = 0.9 * scale
    t0 = R.y0 + 0.2 if R.rng.random() < 0.5 else R.y1 - 0.2 - band
    xa = R.x0 + 0.3
    xb = R.x0 + (R.x1 - R.x0) * R.rng.uniform(0.45, 0.95)
    strip = R.rect(xa, t0, xb, t0 + band)
    if any(strip.intersects(t) for t in R.taken):
        return
    R.taken.append(strip)
    for yy in (t0, t0 + band):
        R.stroke(R.line([(xa, yy), (xb, yy)]), 0.08 * scale, DETAIL_LINE_V * 0.8)
    step = band * 1.1
    zz = [(xx, t0 + (band if i % 2 else 0)) for i, xx in enumerate(np.arange(xa, xb, step))]
    if len(zz) > 1:
        R.stroke(R.line(zz).intersection(R.inner.buffer(0.3)), 0.06 * scale, DETAIL_LINE_V * 0.8)


def item_pigeon_tower(R, scale):
    """A pigeon tower (the Cairo rooftop dovecote): a lattice of four posts
    on a braced base, with the cage box and a flag pole on top. The base is
    roof detail; the posts, cage and pole stand in the talls sublayer, 4.5
    to 8 m up, so the tower leans with the view."""
    rng = R.rng
    s = rng.uniform(2.2, 3.0) * scale
    spot = R.place(s + 0.8, s + 0.8, margin=0.3)
    if not spot:
        return
    x0, y0 = spot[0] + 0.4, spot[1] + 0.4
    x1, y1 = x0 + s, y0 + s
    h = rng.uniform(4.5, 8.0)
    sx, sy = R.shade
    B = R.batch()
    B.quad([(x0, y0), (x1, y0), (x1 + sx * 1.6, y1 + sy * 1.6), (x0 + sx * 1.6, y1 + sy * 1.6)], 0.0, 0.25)
    B.line(x0, y0, x1, y1, 0.07, 0.3)
    B.line(x0, y1, x1, y0, 0.07, 0.3)
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    for px, py in corners:
        B.rect(px - 0.13, py - 0.13, px + 0.13, py + 0.13, 0.02)
    B.flush(R.L, "roofs", R.key, "pigeon_tower")
    T = R.batch()
    hc = h - rng.uniform(1.3, 1.9)
    for px, py in corners:
        T.post(px, py, 0.14, 0.0, hc, 0.24)
    T.line(x0, y0, x1, y0, 0.08, 0.26, h0=hc * 0.5)
    T.line(x0, y1, x1, y1, 0.08, 0.26, h0=hc * 0.5)
    o = 0.35
    T.prism([(x0 - o, y0 - o), (x1 + o, y0 - o), (x1 + o, y1 + o), (x0 - o, y1 + o)], hc, h, 0.2, 0.09)
    T.line(x0 - o, (y0 + y1) / 2, x1 + o, (y0 + y1) / 2, 0.06, 0.28, h0=h)
    T.post(x1 + o - 0.1, y0 - o + 0.1, 0.07, h, h + 2.2, 0.3)
    T.line(x1 + o - 0.1, y0 - o + 0.1, x1 + o + 0.6, y0 - o + 0.1, 0.35, 0.34, h0=h + 2.0)
    T.flush(R.L, "talls", R.key, "pigeon_tower_talls")


def tank_discs(B, x, y, r, v_body=0.035, n=8):
    """One black plastic water tank seen from above: a light rim, the dark
    body and a lid."""
    B.disc(x, y, r, 0.22, n)
    B.disc(x, y, r - 0.06, v_body, n)
    q = r * 0.28
    B.rect(x - q, y - q, x + q, y + q, 0.15)


def item_tank_stand(R, scale):
    """Two to four water tanks up on a steel stand, which throws a long
    shadow on the roof."""
    rng = R.rng
    n = int(rng.integers(2, 5))
    cols, rows = (n, 1) if n < 4 else (2, 2)
    r = rng.uniform(0.5, 0.65) * scale
    w, d = cols * (2 * r + 0.12) + 0.3, rows * (2 * r + 0.12) + 0.3
    spot = R.place(w + 1.0, d + 1.0, margin=0.3)
    if not spot:
        return
    x0, y0 = spot[0] + 0.2, spot[1] + 0.2
    x1, y1 = x0 + w, y0 + d
    sx, sy = R.shade
    B = R.batch()
    k = 1.8 * scale
    B.rect(x0 + sx * k, y0 + sy * k, x1 + sx * k, y1 + sy * k, 0.0, 0.4)
    B.rect(x0, y0, x1, y1, 0.13)
    B.rect(x0 + 0.08, y0 + 0.08, x1 - 0.08, y1 - 0.08, 0.06)
    for i in range(cols):
        for j in range(rows):
            tank_discs(B, x0 + 0.15 + r + i * (2 * r + 0.12) + 0.06, y0 + 0.15 + r + j * (2 * r + 0.12) + 0.06, r)
    B.flush(R.L, "roofs", R.key, "tank_stand")


def item_tank_cluster(R, scale):
    """Three to six water tanks side by side on the roof, joined by a pipe."""
    rng = R.rng
    n = int(rng.integers(3, 7))
    r = rng.uniform(0.42, 0.6) * scale
    rows = 1 if n <= 4 else 2
    cols = int(np.ceil(n / rows))
    w, d = cols * (2 * r + 0.1), rows * (2 * r + 0.1)
    spot = R.place(w + 0.4, d + 0.4, margin=0.3)
    if not spot:
        return
    x0, y0 = spot[0] + 0.2, spot[1] + 0.2
    sx, sy = R.shade
    B = R.batch()
    B.rect(x0 + sx * 0.4, y0 + sy * 0.4, x0 + w + sx * 0.4, y0 + d + sy * 0.4, 0.0, 0.35)
    B.line(x0 + r, y0 + r, x0 + w - r, y0 + r, 0.12, 0.012)
    k = 0
    for j in range(rows):
        for i in range(cols):
            if k < n:
                tank_discs(B, x0 + r + 0.05 + i * (2 * r + 0.1), y0 + r + 0.05 + j * (2 * r + 0.1), r)
            k += 1
    B.flush(R.L, "roofs", R.key, "tank_cluster")


def item_shack(R, scale):
    """A rooftop shack: a small room roofed with corrugated tin, held down
    with a few stones, sometimes with a lean-to on one side."""
    rng = R.rng
    w, d = rng.uniform(2.6, 4.2) * scale, rng.uniform(2.2, 3.2) * scale
    spot = R.place(w + 0.4, d + 0.4, margin=0.35)
    if not spot:
        return
    x0, y0 = spot[0] + 0.2, spot[1] + 0.2
    x1, y1 = x0 + w, y0 + d
    sx, sy = R.shade
    B = R.batch()
    B.quad([(x0, y1), (x1, y1), (x1 + sx * 1.1, y1 + sy * 1.1), (x0 + sx * 1.1, y1 + sy * 1.1)], 0.0, 0.4)
    B.quad([(x1, y0), (x1, y1), (x1 + sx * 1.1, y1 + sy * 1.1), (x1 + sx * 1.1, y0 + sy * 1.1)], 0.0, 0.4)
    B.rect(x0, y0, x1, y1, 0.025)
    tin = rng.uniform(0.11, 0.17)
    B.rect(x0 + 0.1, y0 + 0.1, x1 - 0.1, y1 - 0.1, tin)
    for xx in np.arange(x0 + 0.4, x1 - 0.2, 0.42):
        B.line(xx, y0 + 0.12, xx, y1 - 0.12, 0.05, tin * 0.6)
    for _ in range(int(rng.integers(1, 4))):
        px, py = rng.uniform(x0 + 0.4, x1 - 0.4), rng.uniform(y0 + 0.4, y1 - 0.4)
        B.rect(px - 0.14, py - 0.12, px + 0.14, py + 0.12, 0.2)
    if rng.random() < 0.4 and R.inner.contains(R.rect(x1, y0, x1 + 1.4, y1)):
        B.rect(x1, y0 + 0.2, x1 + 1.3, y1 - 0.2, tin * 0.8, 0.9)
        B.line(x1 + 1.3, y0 + 0.2, x1 + 1.3, y1 - 0.2, 0.05, 0.3)
    B.flush(R.L, "roofs", R.key, "shack")


def item_dish_row(R, scale):
    """A row of four to eight satellite dishes on a rail along the parapet,
    one for each flat below."""
    rng = R.rng
    n = int(rng.integers(4, 9))
    r = rng.uniform(0.3, 0.42) * scale
    step = 2 * r + 0.22
    length = n * step
    if R.x1 - R.x0 < length + 1.0:
        n = int((R.x1 - R.x0 - 1.0) // step)
        length = n * step
        if n < 3:
            return
    spot = None
    for _ in range(8):
        x = rng.uniform(R.x0 + 0.5, R.x1 - 0.5 - length)
        y = R.y0 + 0.6 if rng.random() < 0.5 else R.y1 - 0.6 - 2 * r
        rect = R.rect(x, y, x + length, y + 2 * r)
        if R.inner.contains(rect) and not any(rect.buffer(0.3).intersects(t) for t in R.taken):
            spot = (x, y, rect)
            break
    if spot is None:
        return
    x, y, rect = spot
    R.taken.append(rect)
    sx, sy = R.shade
    B = R.batch()
    B.line(x + sx * 0.2, y + r + sy * 0.2, x + length + sx * 0.2, y + r + sy * 0.2, 2 * r, 0.0, 0.3)
    B.line(x, y + r, x + length, y + r, 0.08, 0.2)
    a = rng.uniform(0, 2 * np.pi)
    for i in range(n):
        cx = x + step * (i + 0.5)
        B.disc(cx, y + r, r, DETAIL_LINE_V, 6)
        B.disc(cx, y + r, r - 0.05, min(R.v * 2.4, 0.3), 6)
        aa = a + rng.normal(0, 0.15)
        B.line(cx, y + r, cx + np.cos(aa) * r * 0.85, y + r + np.sin(aa) * r * 0.85, 0.05, 0.06)
    B.flush(R.L, "roofs", R.key, "dish_row")


def unfinished_floor(R):
    """An unfinished top floor (the Cairo look): concrete columns with rebar
    sticking out, on a grid along the roof's edge and across it, a few
    half-built brick walls between them, bricks and sand, and a stair head.
    The edge band and the stair head are taken, so items placed afterwards
    keep clear. Returns False when the roof is too small for it."""
    rng = R.rng
    x0, y0, x1, y1 = R.x0 + 0.62, R.y0 + 0.62, R.x1 - 0.62, R.y1 - 0.62
    if x1 - x0 < 4.0 or y1 - y0 < 3.5:
        return False
    nx = max(1, int(round((x1 - x0) / rng.uniform(3.4, 4.6))))
    ny = max(1, int(round((y1 - y0) / rng.uniform(3.4, 4.6))))
    xs, ys = np.linspace(x0, x1, nx + 1), np.linspace(y0, y1, ny + 1)
    blocked = list(R.taken)
    B = R.batch()
    sx, sy = R.shade
    edge = []
    for i, xx in enumerate(xs):
        for j, yy in enumerate(ys):
            rim = i in (0, nx) or j in (0, ny)
            if not rim and rng.random() < 0.4:
                continue
            col = R.rect(xx - 0.25, yy - 0.25, xx + 0.25, yy + 0.25)
            if not R.inner.contains(col) or any(col.intersects(t) for t in blocked):
                continue
            if rim:
                edge.append((i, j, xx, yy))
            B.rect(xx - 0.25 + sx * 0.5, yy - 0.25 + sy * 0.5, xx + 0.25 + sx * 0.5, yy + 0.25 + sy * 0.5, 0.0, 0.5)
            B.rect(xx - 0.25, yy - 0.25, xx + 0.25, yy + 0.25, 0.27)
            if rng.random() < 0.75:
                B.line(xx - 0.36, yy - 0.36, xx + 0.36, yy + 0.36, 0.05, 0.42)
                B.line(xx - 0.36, yy + 0.36, xx + 0.36, yy - 0.36, 0.05, 0.42)
    pairs = [(a, b) for a in edge for b in edge
             if (a[0] == b[0] and a[0] in (0, nx) and b[1] == a[1] + 1) or
             (a[1] == b[1] and a[1] in (0, ny) and b[0] == a[0] + 1)]
    for k in rng.permutation(len(pairs))[:int(rng.integers(2, 5))]:
        (_, _, xa, ya), (_, _, xb, yb) = pairs[k]
        t = rng.uniform(0.45, 1.0)
        xm, ym = xa + (xb - xa) * t, ya + (yb - ya) * t
        if any(R.line([(xa, ya), (xm, ym)]).buffer(0.2).intersects(g) for g in blocked):
            continue
        B.line(xa + sx * 0.4, ya + sy * 0.4, xm + sx * 0.4, ym + sy * 0.4, 0.34, 0.0, 0.45)
        B.line(xa, ya, xm, ym, 0.3, 0.19)
        B.line(xa, ya, xm, ym, 0.07, 0.3)
    for _ in range(int(rng.integers(1, 3))):
        px, py = rng.uniform(x0 + 1.0, x1 - 1.0), rng.uniform(y0 + 1.0, y1 - 1.0)
        pile = R.rect(px - 0.5, py - 0.4, px + 0.5, py + 0.4)
        if not R.inner.contains(pile) or any(pile.intersects(t) for t in blocked):
            continue
        if rng.random() < 0.5:
            B.rect(px - 0.5, py - 0.35, px + 0.5, py + 0.35, 0.16)
            B.line(px - 0.5, py, px + 0.5, py, 0.04, 0.09)
        else:
            B.disc(px, py, rng.uniform(0.45, 0.7), 0.18, 7, 0.85)
    B.flush(R.L, "roofs", R.key, "unfinished_floor")
    R.taken.append(R.inner.difference(R.rect(x0 + 0.5, y0 + 0.5, x1 - 0.5, y1 - 0.5)))
    item_stair(R, 1.15)
    return True


HOUSE_ITEMS = [(item_annex, 0.24), (item_stair, 0.18), (item_tanks, 0.14), (item_vents, 0.14),
               (item_xpanels, 0.11), (item_struts, 0.1), (item_hatch, 0.09), (item_dishes, 0.14)]
BIG_ITEMS = [(item_annex, 0.24), (item_vents, 0.26), (item_tanks, 0.14), (item_xpanels, 0.18),
             (item_hatch, 0.18)]
## The Cairo roof kit, for flat house roofs in the residential and market
## districts (draw_house with cairo): the house items plus pigeon towers,
## tank stands and clusters, rooftop shacks and dish rows.
CAIRO_ITEMS = [(item_annex, 0.15), (item_stair, 0.15), (item_tanks, 0.07), (item_vents, 0.155),
               (item_xpanels, 0.05), (item_struts, 0.05), (item_hatch, 0.05), (item_dishes, 0.1),
               (item_pigeon_tower, 0.022), (item_tank_stand, 0.09), (item_tank_cluster, 0.06),
               (item_shack, 0.08), (item_dish_row, 0.07)]
## Share of the Cairo roofs (draw_house with cairo, roofs of at least
## UNFINISHED_MIN_M2) with an unfinished top floor.
UNFINISHED_SHARE = 0.15
UNFINISHED_MIN_M2 = 45.0


def pick(table, rng):
    fns, w = zip(*table)
    return fns[rng.choice(len(fns), p=np.asarray(w) / sum(w))]


def draw_halo(L, poly, width):
    for g in polys(poly):
        L.strip("halos", orient(g, 1.0).exterior, width, -1, HALO_A, 0.0)


def draw_house(L, lot, mv, rng, items=True, pre=None, post=None, cairo=False):
    """A flat house roof with its parapet and 1-3 roof kit items. pre(R) runs
    before the items are placed (what it takes, they avoid), post(R) after.
    cairo picks the items from CAIRO_ITEMS and gives UNFINISHED_SHARE of the
    roofs an unfinished top floor (in place of one item).
    Returns the Roof (its items, for salvage)."""
    with L.within("roofs", lot, ROOF_BOUND_M):
        v = roof_value(mv) * rng.uniform(0.85, 1.15)
        R = Roof(L, lot, v, rng)
        unfinished = False
        if items and cairo and lot.area >= UNFINISHED_MIN_M2 and min(R.x1 - R.x0, R.y1 - R.y0) >= 5.2:
            KIT_COUNT["cairo_roofs"] = KIT_COUNT.get("cairo_roofs", 0) + 1
            unfinished = rng.random() < UNFINISHED_SHARE
        if unfinished:
            # A bare slab: lighter raw concrete, no parapet.
            R.fill(lot, min(v * 1.45, 0.14))
            set_inner(R, lot, 0.3)
            R.shade_in(lot, 0.5, 0.3)
        else:
            R.fill(lot, v)
            if rng.random() < 0.35 and R.x1 - R.x0 > 7:
                # Roof level change: one end a different tone, split by a line.
                sx = R.x0 + (R.x1 - R.x0) * rng.uniform(0.35, 0.65)
                R.fill(R.rect(sx, R.y0, R.x1, R.y1).intersection(lot), v * rng.choice([0.75, 1.3]))
                R.stroke(R.line([(sx, R.y0), (sx, R.y1)]).intersection(lot), PARAPET_W, PARAPET_V)
            inner = set_inner(R, lot, 0.45)
            R.shade_in(inner, 1.1, 0.4)
            R.ring(inner, PARAPET_W, PARAPET_V)
        n = 1 if lot.area < 50 else 2 if lot.area < 110 else 3
        if pre:
            pre(R)
        if unfinished and unfinished_floor(R):
            n = max(1, n - 1)
        for _ in range(n if items else 0):
            pick(CAIRO_ITEMS if cairo else HOUSE_ITEMS, rng)(R, 1.0)
        if post:
            post(R)
        R.ring(lot, OUTLINE_W, OUTLINE_V)
        return R


def draw_big(L, roof, mv, rng, items=True, pre=None, post=None):
    """A large flat roof: bays, columns or a skylight band, struts and 2-6
    roof kit items at a larger scale. pre and post as in draw_house.
    Returns the Roof."""
    with L.within("roofs", roof, ROOF_BOUND_M):
        v = roof_value(mv) * rng.uniform(0.9, 1.1)
        R = Roof(L, roof, v, rng)
        R.fill(roof, v)
        inset = 1.2
        inner = set_inner(R, roof, inset)
        ix0, iy0, ix1, iy1 = R.x0 + inset, R.y0 + inset, R.x1 - inset, R.y1 - inset
        # Bays run the length of the roof; alternate tones read as roof sections.
        bay_w = rng.uniform(5.0, 8.0)
        ys = np.arange(iy0, iy1, bay_w)
        for i, ya in enumerate(ys):
            yb = min(ya + bay_w, iy1)
            bay = R.rect(ix0, ya, ix1, yb).intersection(inner)
            if i % 2:
                R.fill(bay, v * 1.18)
            if bay.area > 4:
                R.stroke(R.line([(ix0, yb - 0.3), (ix1, yb - 0.3)]).intersection(inner), 0.6, 0.0, 0.35)
            if i:
                R.stroke(R.line([(ix0, ya), (ix1, ya)]).intersection(inner), 0.1, PARAPET_V)
        pattern = rng.choice(["columns", "skylights", "plain"], p=[0.45, 0.4, 0.15])
        if pattern == "columns":
            step = rng.uniform(6.0, 9.0)
            for ya in ys[1::2]:
                yc = ya + bay_w / 2
                for xc in np.arange(ix0 + step / 2, ix1 - 1, step):
                    sq = R.rect(xc - 0.7, yc - 0.7, xc + 0.7, yc + 0.7)
                    if inner.contains(sq):
                        R.fill(sq, 0.022)
        elif pattern == "skylights":
            band_h = min((iy1 - iy0) * 0.5, rng.uniform(4.0, 9.0))
            by0 = iy0 + (iy1 - iy0 - band_h) * rng.uniform(0.2, 0.8)
            bx0, bx1 = ix0 + 2.0, ix1 - 2.0
            if bx1 - bx0 > 6:
                band = R.rect(bx0, by0, bx1, by0 + band_h).intersection(inner)
                R.taken.append(band)
                R.fill(band, 0.075)
                R.ring(band, 0.14, DETAIL_LINE_V)
                pane = rng.uniform(2.0, 3.0)
                for xg in np.arange(bx0 + pane, bx1, pane):
                    R.stroke(R.line([(xg, by0), (xg, by0 + band_h)]).intersection(band), 0.08, 0.15)
                R.stroke(R.line([(bx0, by0 + band_h / 2), (bx1, by0 + band_h / 2)]).intersection(band), 0.08, 0.15)
        R.shade_in(inner, 1.6, 0.4)
        R.ring(inner, PARAPET_W * 1.3, PARAPET_V)
        if rng.random() < 0.4 and items:
            item_struts(R, 1.5)
        n = int(np.clip(roof.area / 400, 2, 6))
        if pre:
            pre(R)
        for _ in range(n if items else 0):
            pick(BIG_ITEMS, rng)(R, rng.uniform(1.6, 2.6))
        if post:
            post(R)
        R.ring(roof, OUTLINE_W * 1.3, OUTLINE_V)
        return R


def draw_roads(L, roads, water):
    concrete = unary_union([g for g, _, _, _, kind, _ in roads if not kind.startswith("rail:")])
    concrete = concrete.intersection(FRAME)
    L.fill("ground", water, WATER_V, clip=True)
    L.fill("ground", concrete, CONCRETE_V, clip=True)
    for g in polys(concrete):
        g = orient(g.simplify(0.05), 1.0)
        for ring in [g.exterior] + list(g.interiors):
            L.strip("groundlines", ring, CONCRETE_EDGE_SHADOW_M, +1, CONCRETE_EDGE_SHADOW_A, 0.0)
            L.line("groundlines", LineString(ring.coords), EDGE_LINE_W, EDGE_LINE_V, 0.8)
    for g, _, w, _, kind, line in roads:
        if kind.startswith("rail:") or w < 9:
            continue
        line = line.intersection(FRAME)
        for seg in getattr(line, "geoms", [line]):
            n = int(seg.length // 6.0)
            for i in range(n):
                dash = substring(seg, i * 6.0, i * 6.0 + 3.0)
                L.line("groundlines", dash, MARKING_W, MARKING_V, 0.9)


def draw_rails(L, roads):
    for _, _, _, _, kind, line in roads:
        if not kind.startswith("rail:"):
            continue
        line = line.intersection(FRAME.buffer(10))
        if line.is_empty:
            continue
        tracks = 2 if kind == "rail:rail" else 1
        offs = [-TRACK_SPACING_M / 2, TRACK_SPACING_M / 2] if tracks == 2 else [0.0]
        for seg in getattr(line, "geoms", [line]):
            if seg.length < 2:
                continue
            seg = seg.simplify(0.3)
            bed = seg.buffer(TRACK_SPACING_M / 2 * tracks + 1.0, cap_style="flat")
            L.fill("groundlines", bed, RAIL_BED_V)
            for o in offs:
                t = seg if o == 0 else seg.offset_curve(o)
                if t.is_empty:
                    continue
                spacing = 1.3 if kind == "rail:rail" else 2.4
                for dist in np.arange(0.5, t.length, spacing):
                    p0 = t.interpolate(dist)
                    p1 = t.interpolate(min(dist + 0.2, t.length))
                    dx, dy = p1.x - p0.x, p1.y - p0.y
                    ln = np.hypot(dx, dy) or 1.0
                    ux, uy = dx / ln, dy / ln
                    nx, ny = -uy, ux
                    hw, hl = 0.24, 1.35
                    q = np.array([[p0.x + ux * s + nx * r, p0.y + uy * s + ny * r] for s, r in
                                  ((-hw, -hl), (hw, -hl), (hw, hl), (-hw, hl))])
                    L.add_tris("groundlines", np.stack([q[[0, 1, 2]], q[[0, 2, 3]]]), SLEEPER_V)
                for r in (-0.72, 0.72):
                    rl = t.offset_curve(r)
                    if not rl.is_empty:
                        L.line("groundlines", rl, 0.1, RAIL_V)


def tidy_big_roofs(big):
    """Large roofs come from two sources and can overlap. Largest first, a
    roof mostly covered by ones already kept is dropped, and a partly covered
    one is trimmed. (Squaring off happens in gen_city, before roofs are cut
    back from roads.)"""
    items = []
    for roof, mv, _ in big:
        for g in polys(roof):
            if g.area >= 30:
                items.append((g, mv))
    items.sort(key=lambda t: -t[0].area)
    kept, taken = [], Polygon()
    for g, mv in items:
        over = g.intersection(taken).area
        if over > 0.25 * g.area:
            continue
        if over > 0:
            g = g.difference(taken.buffer(1.0))
        for part in polys(g):
            # Trimming can leave thin strips and wedges; keep only solid parts.
            if part.area > 60 and min_width(part) >= 5.0 and rect_fill(part) >= 0.6:
                kept.append((part, mv))
        taken = taken.union(g)
    return kept


def draw_interior(L, poly, big, rng):
    """What shows when the roof fades: a tiled floor, brighter in the middle,
    darkening towards thick dark walls, with partition walls (door gaps
    left in them), columns in large halls and a little debris."""
    with L.within("interiors", poly):
        key = chunk_key(poly)
        sub = "interiors"
        ang, c = frame_of(poly)
        loc = affinity.rotate(poly, -ang, origin=c)
        x0, y0, x1, y1 = (b - o for b, o in zip(loc.bounds, (c.x, c.y) * 2))
        wall = 0.5 if big else 0.35
        room = poly.buffer(-wall, join_style="mitre")
        if room.is_empty:
            L.fill(sub, poly, 0.03, chunk=key)
            return
        L.fill(sub, poly, 0.03, chunk=key)
        L.fill(sub, room, 0.19 if not big else 0.16, chunk=key)
        tile = 6.0 if big else 3.0
        for xg in np.arange(x0 + tile, x1, tile):
            L.line(sub, local_line(c, ang, [(xg, y0), (xg, y1)]).intersection(room), 0.06, 0.07, chunk=key)
        for yg in np.arange(y0 + tile, y1, tile):
            L.line(sub, local_line(c, ang, [(x0, yg), (x1, yg)]).intersection(room), 0.06, 0.07, chunk=key)
        if big:
            for xg in np.arange(x0 + 8.0, x1 - 2, 8.0):
                for yg in np.arange(y0 + 8.0, y1 - 2, 8.0):
                    col = local_rect(c, ang, xg - 0.4, yg - 0.4, xg + 0.4, yg + 0.4)
                    if room.contains(col):
                        L.fill(sub, col, 0.03, chunk=key)
        # Partition walls across the short way, each with a door gap.
        n = 0 if poly.area < 40 else int(rng.integers(1, 3 if not big else 4))
        span = x1 - x0
        for i in range(n):
            xw = x0 + span * (i + 1) / (n + 1) + rng.uniform(-0.1, 0.1) * span
            gap = rng.uniform(y0 + 1.0, max(y0 + 1.1, y1 - 2.4))
            for ya, yb in ((y0, gap), (gap + (2.2 if big else 1.3), y1)):
                if yb - ya > 0.3:
                    seg = local_line(c, ang, [(xw, ya), (xw, yb)]).intersection(room)
                    L.line(sub, seg, 0.3 if big else 0.22, 0.03, chunk=key)
        for g in polys(room):
            L.strip(sub, orient(g, 1.0).exterior, 3.0 if big else 1.4, +1, 0.7, 0.0, chunk=key)
            L.line(sub, LinearRing(g.exterior.coords), 0.06, 0.2, chunk=key)
        for _ in range(int(rng.integers(1, 4))):
            p = room.representative_point()
            s = rng.uniform(0.4, 1.0) * (2 if big else 1)
            bit = Point(p.x + rng.uniform(-3, 3), p.y + rng.uniform(-3, 3)).buffer(s / 2, cap_style="square")
            bit = affinity.rotate(bit, rng.uniform(0, 90), origin=bit.centroid).intersection(room)
            if not bit.is_empty:
                L.fill(sub, bit, rng.choice([0.04, 0.2]), chunk=key)


def roof_shape(poly):
    """Classifies a footprint as "rect", "L" or None (anything else), and
    returns the rectangles to roof, largest first, in the footprint's local
    frame, with that frame's angle and centre."""
    ang, c = frame_of(poly)
    loc = affinity.rotate(poly, -ang, origin=c).simplify(0.3)
    if loc.geom_type != "Polygon" or loc.interiors:
        return None, [], ang, c
    pts = np.asarray(loc.exterior.coords)[:-1]
    n = len(pts)
    if n not in (4, 6):
        return None, [], ang, c
    d_in = pts - np.roll(pts, 1, 0)
    d_out = np.roll(pts, -1, 0) - pts
    cosines = (d_in * d_out).sum(1) / (np.hypot(*d_in.T) * np.hypot(*d_out.T) + 1e-9)
    if np.any(np.abs(cosines) > 0.17):
        return None, [], ang, c
    x0, y0, x1, y1 = loc.bounds
    if n == 4:
        return "rect", [(x0, y0, x1, y1)], ang, c
    cross = d_in[:, 0] * d_out[:, 1] - d_in[:, 1] * d_out[:, 0]
    orient_sign = 1.0 if loc.exterior.is_ccw else -1.0
    reflex = np.flatnonzero(np.sign(cross) != orient_sign)
    if len(reflex) != 1:
        return None, [], ang, c
    rx, ry = pts[reflex[0]]
    best = None
    for cut_a, cut_b in ((box(x0, y0, rx, y1), box(rx, y0, x1, y1)),
                         (box(x0, y0, x1, ry), box(x0, ry, x1, y1))):
        # A cut along one of the L's own edges also returns that edge as a
        # line; only the polygon part counts.
        parts = [polys(loc.intersection(cut)) for cut in (cut_a, cut_b)]
        if any(not p for p in parts):
            continue
        parts = [max(p, key=lambda g: g.area) for p in parts]
        if any(p.area < 9 for p in parts):
            continue
        parts.sort(key=lambda p: -p.area)
        if best is None or parts[0].area > best[0].area:
            best = parts
    if best is None:
        return None, [], ang, c
    return "L", [p.bounds for p in best], ang, c


def pitched_faces(rect, hip):
    """Faces of a pitched roof over a local-frame rectangle. Each face is
    (points, stripe axis, downhill direction), all in the local frame. The
    ridge runs along the long side; stripes run down the slope."""
    x0, y0, x1, y1 = rect
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if x1 - x0 >= y1 - y0:
        u, v, hl, hw = np.array([1.0, 0.0]), np.array([0.0, 1.0]), (x1 - x0) / 2, (y1 - y0) / 2
    else:
        u, v, hl, hw = np.array([0.0, 1.0]), np.array([1.0, 0.0]), (y1 - y0) / 2, (x1 - x0) / 2
    c = np.array([cx, cy])
    P = lambda a, b: c + a * u + b * v
    r = max(hl - hw, 0.0) if hip else hl
    faces, ridge = [], (P(-r, 0), P(r, 0))
    for s in (1, -1):
        faces.append(([P(-hl, s * hw), P(hl, s * hw), P(r, 0), P(-r, 0)], u, s * v))
        if hip:
            faces.append(([P(s * hl, -hw), P(s * hl, hw), P(s * r, 0)], v, s * u))
    hips = [(P(s1 * hl, s2 * hw), P(s1 * r, 0)) for s1 in (1, -1) for s2 in (1, -1)] if hip else []
    return faces, ridge, hips


def draw_pitched(L, poly, rects, ang, c, v, rng, hip, course_m):
    """Draws pitched roof sections (largest first in rects; drawn last so it
    sits over the joins) with lit and shaded faces, tile courses, ridge and
    hip lines."""
    with L.within("roofs", poly, ROOF_BOUND_M):
        key = chunk_key(poly)
        rot = np.radians(ang)
        R2 = np.array([[np.cos(rot), -np.sin(rot)], [np.sin(rot), np.cos(rot)]])
        origin = np.array([c.x, c.y])
        # Local points are the footprint rotated by -ang about c; this undoes it.
        to_world = lambda p: origin + R2 @ (np.asarray(p) - origin)
        for i, rect in reversed(list(enumerate(rects))):
            faces, ridge, hips = pitched_faces(rect, hip and i == 0)
            for pts, axis, down in faces:
                wpts = [to_world(p) for p in pts]
                face = Polygon(wpts)
                if face.area < 0.05:
                    continue
                down_w = R2 @ down
                lit = 1.0 + 0.3 * float(down_w @ ROOF_LIGHT)
                L.stripe = (origin, (R2 @ axis) / course_m)
                L.fill("roofs", face, min(v * lit, 0.2), chunk=key)
                L.stripe = None
            L.line("roofs", LineString([to_world(p) for p in ridge]), 0.16, DETAIL_LINE_V, chunk=key)
            for a, b in hips:
                L.line("roofs", LineString([to_world(a), to_world(b)]), 0.1, DETAIL_LINE_V * 0.8, chunk=key)
            sect = Polygon([to_world(p) for p in
                            ((rect[0], rect[1]), (rect[2], rect[1]), (rect[2], rect[3]), (rect[0], rect[3]))])
            L.strip("roofs", orient(sect, 1.0).exterior, 0.35, +1, 0.45, 0.0, chunk=key)
            L.line("roofs", LinearRing(sect.exterior.coords), 0.14, PARAPET_V * 0.9, chunk=key)
        x0, y0, x1, y1 = rects[0]
        if hip and rng.random() < 0.3 and min(x1 - x0, y1 - y0) > 3.0:
            px, py = rng.uniform(x0 + 1.0, x1 - 1.6), rng.uniform(y0 + 1.0, y1 - 1.6)
            stack = Polygon([to_world(p) for p in ((px, py), (px + 0.6, py), (px + 0.6, py + 0.6), (px, py + 0.6))])
            if poly.buffer(-0.4).contains(stack):
                L.strip("roofs", orient(stack, 1.0).exterior, 0.4, -1, 0.5, 0.0, chunk=key)
                L.fill("roofs", stack, 0.1, chunk=key)
                L.line("roofs", LinearRing(stack.exterior.coords), 0.06, OUTLINE_V * 0.8, chunk=key)
        L.line("roofs", LinearRing(poly.exterior.coords), OUTLINE_W, OUTLINE_V, chunk=key)


def draw_tiled_house(L, lot, mv, rng, rects, ang, c):
    v = roof_value(mv) * rng.uniform(1.05, 1.35)
    draw_pitched(L, lot, rects, ang, c, v, rng, hip=rng.random() < 0.7, course_m=TILE_COURSE_M)


def draw_sheet_shed(L, roof, mv, rng, rects, ang, c):
    v = roof_value(mv) * rng.uniform(1.0, 1.25)
    draw_pitched(L, roof, rects, ang, c, v, rng, hip=False, course_m=SHEET_COURSE_M)
