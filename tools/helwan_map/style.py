"""Draws the city layout in the old map's style and writes it per chunk.

The look: dark roofs with a light outline, an inset parapet line and roof
detail; a soft dark halo round every building; light concrete roads that
darken towards their edges, with a thin edge line; rail as a dark bed with
sleepers and two rails.

Geometry goes into six sublayers. Each sublayer is one mesh per chunk, and
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

The viaduct is not drawn here: the scene places it as an OverheadPath node.

A building's ruin state (see ruins.py) changes only its roofs, interiors,
ground and groundlines geometry. While a ruined roof is drawn, roof_cut
(holes) or roof_keep (the fragments left) clips every roof fill of that
building.

Output per chunk and sublayer is a small binary file:
  int32 vertex count, int32 index count, int32 1 if roof channels follow
  (else 0), float32 x,y per vertex (world px), uint8 grey,alpha per vertex,
  then, for roofs, float32 building id per vertex (-1 for none) and float32
  stripe coordinate per vertex (0 for none), then uint32 vertex indices.
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

import numpy as np
import shapely
from shapely import affinity
from shapely.geometry import LineString, LinearRing, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import substring, unary_union

from gen_city import CHUNK_M, CHUNKS, FRAME, HALF_M, min_width, rect_fill

PX = 20.0
SUBLAYERS = ("ground", "groundlines", "halos", "interiors", "roofs", "overheads")

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

    def _put(self, sub, key, tris, grey, alpha):
        bucket = self.parts.setdefault((sub, key), [[], [], [], [], []])
        pts = tris.reshape(-1, 2)
        bucket[0].append(pts)
        bucket[1].append(grey.reshape(-1))
        bucket[2].append(alpha.reshape(-1))
        bid = self.bid if sub == "roofs" else -1
        bucket[3].append(np.full(grey.size, bid, np.float32))
        if sub == "roofs" and self.stripe is not None:
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

    def add_tris(self, sub, tris, v, a=1.0, chunk=None, va=None, vg=None):
        """tris (n, 3, 2) in metres. chunk None puts each triangle in the chunk
        holding its centre; a chunk key keeps them all together. va and vg
        give alpha and grey per vertex ((n, 3)) instead of a and v."""
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
        if chunk is not None:
            self._put(sub, chunk, tris, grey, alpha)
            return
        cen = tris.mean(1)
        keys = chunk_of(cen)
        for k in np.unique(keys, axis=0):
            sel = np.all(keys == k, axis=1)
            self._put(sub, tuple(k), tris[sel], grey[sel], alpha[sel])

    def fill(self, sub, geom, v, a=1.0, chunk=None, clip=False):
        if geom.is_empty:
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

    def line(self, sub, line, width, v, a=1.0, chunk=None):
        if line.is_empty or line.length == 0:
            return
        self.fill(sub, line.buffer(width / 2, cap_style="flat", join_style="mitre", mitre_limit=3), v, a, chunk)

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
            has_roof = int(sub == "roofs")
            name = f"{sub}_{key[0]}_{key[1]}"
            # Triangle corners that are the same vertex become one vertex
            # plus an index list.
            cols = [xy.view(np.uint8).reshape(len(xy), 8), ga]
            if has_roof:
                rid = np.concatenate(ids).astype(np.float32)
                rst = np.concatenate(stripes).astype(np.float32)
                cols += [rid.view(np.uint8).reshape(-1, 4), rst.view(np.uint8).reshape(-1, 4)]
            rows = np.ascontiguousarray(np.concatenate(cols, 1))
            keyv = rows.view(np.dtype((np.void, rows.shape[1]))).ravel()
            _, first, index = np.unique(keyv, return_index=True, return_inverse=True)
            index = index.astype(np.uint32).ravel()
            with open(os.path.join(out_dir, name + ".bin"), "wb") as fh:
                fh.write(struct.pack("<iii", len(first), len(index), has_roof))
                fh.write(xy[first].tobytes())
                fh.write(ga[first].tobytes())
                if has_roof:
                    fh.write(rid[first].tobytes())
                    fh.write(rst[first].tobytes())
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
        c = R.rect(x, y, x + 2 * r, y + 2 * r).centroid
        centres.append((c, r))
    if len(centres) == 2:
        R.stroke(LineString([centres[0][0], centres[1][0]]), 0.16 * scale, 0.01)
    for c, r in centres:
        disc = c.buffer(r, quad_segs=3 if r < 2 else 5)
        if scale > 1:
            R.shade_out(disc, 0.35 * scale, 0.45)
            R.fill(c.buffer(r * 0.6, quad_segs=5), min(R.v * 1.45, 0.13))
        R.fill(disc, min(R.v * 1.25, 0.11))
        R.stroke(disc.exterior, 0.08 * scale, DETAIL_LINE_V * 0.85)
        for dx, dy in ((1, 0), (0, 1)):
            d = np.array([dx, dy]) * r * 0.95
            cs, sn = np.cos(np.radians(R.ang)), np.sin(np.radians(R.ang))
            d = np.array([cs * d[0] - sn * d[1], sn * d[0] + cs * d[1]])
            R.stroke(LineString([(c.x - d[0], c.y - d[1]), (c.x + d[0], c.y + d[1])]), 0.04 * scale, 0.12)
        R.fill(c.buffer(r * 0.14, cap_style="square"), 0.008)


def item_dishes(R, scale):
    """One to three satellite dishes on short masts, each a pale disc with a
    feed arm and a shadow."""
    for _ in range(int(R.rng.integers(1, 4))):
        r = R.rng.uniform(0.35, 0.55) * scale
        spot = R.place(2 * r + 0.3, 2 * r + 0.3)
        if not spot:
            return
        x, y, _ = spot
        c = R.rect(x + 0.15, y + 0.15, x + 0.15 + 2 * r, y + 0.15 + 2 * r).centroid
        disc = c.buffer(r, quad_segs=4)
        R.shade_out(disc, 0.25 * scale, 0.4)
        R.fill(disc, min(R.v * 2.2, 0.3))
        R.stroke(disc.exterior, 0.05 * scale, DETAIL_LINE_V)
        a = np.radians(R.ang) + R.rng.uniform(0, 2 * np.pi)
        R.stroke(LineString([(c.x, c.y), (c.x + np.cos(a) * r * 0.9, c.y + np.sin(a) * r * 0.9)]), 0.05 * scale, 0.06)


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


HOUSE_ITEMS = [(item_annex, 0.24), (item_stair, 0.18), (item_tanks, 0.14), (item_vents, 0.14),
               (item_xpanels, 0.11), (item_struts, 0.1), (item_hatch, 0.09), (item_dishes, 0.14)]
BIG_ITEMS = [(item_annex, 0.24), (item_vents, 0.26), (item_tanks, 0.14), (item_xpanels, 0.18),
             (item_hatch, 0.18)]


def pick(table, rng):
    fns, w = zip(*table)
    return fns[rng.choice(len(fns), p=np.asarray(w) / sum(w))]


def draw_halo(L, poly, width):
    for g in polys(poly):
        L.strip("halos", orient(g, 1.0).exterior, width, -1, HALO_A, 0.0)


def draw_house(L, lot, mv, rng, items=True, pre=None, post=None):
    """A flat house roof with its parapet and 1-3 roof kit items. pre(R) runs
    before the items are placed (what it takes, they avoid), post(R) after.
    Returns the Roof (its items, for salvage)."""
    v = roof_value(mv) * rng.uniform(0.85, 1.15)
    R = Roof(L, lot, v, rng)
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
    for _ in range(n if items else 0):
        pick(HOUSE_ITEMS, rng)(R, 1.0)
    if post:
        post(R)
    R.ring(lot, OUTLINE_W, OUTLINE_V)
    return R


def draw_big(L, roof, mv, rng, items=True, pre=None, post=None):
    """A large flat roof: bays, columns or a skylight band, struts and 2-6
    roof kit items at a larger scale. pre and post as in draw_house.
    Returns the Roof."""
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
        sect = Polygon([to_world(p) for p in ((rect[0], rect[1]), (rect[2], rect[1]), (rect[2], rect[3]), (rect[0], rect[3]))])
        L.strip("roofs", orient(sect, 1.0).exterior, 0.35, +1, 0.45, 0.0, chunk=key)
        L.line("roofs", LinearRing(sect.exterior.coords), 0.14, PARAPET_V * 0.9, chunk=key)
    x0, y0, x1, y1 = rects[0]
    if hip and rng.random() < 0.3 and min(x1 - x0, y1 - y0) > 3.0:
        px, py = rng.uniform(x0 + 1.0, x1 - 1.6), rng.uniform(y0 + 1.0, y1 - 1.6)
        stack = Polygon([to_world(p) for p in ((px, py), (px + 0.6, py), (px + 0.6, py + 0.6), (px, py + 0.6))])
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
