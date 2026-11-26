"""Drawing and placing helpers shared by the civic places (civic.py and its
parts: cemetery.py, worship.py, grounds.py).

Drawing:
  domes        shaded domes on roofs and on small tomb rooms: discs that
               shrink and brighten towards the light (style.ROOF_LIGHT), a
               drum ring, ribs and a finial
  talls        minarets, bell towers, floodlight masts and flagpoles in the
               talls sublayer (style.Layers): prisms and cones with one grey
               per face from the face's direction to the light, lower parts
               first so the game's height shift stacks them right
  walls        compound walls drawn on the ground (interiors), with gate
               gaps and piers; they are drawing only, as the farm yards' and
               military compounds' walls are
  courts       football pitches, basketball, tennis and volleyball courts
               and a running track, marked in the groundlines sublayer

Placing:
  free_land    the part of an area still free for a civic place (no roads,
               water, claims, district module content, KeepOut or markers)
  Layout       the whole map's roads, blocks, lots and large roofs
               (site.full_layout) with lookups, so the places are chosen
               over the whole map the same way in a window run as in a full
               run
"""
import numpy as np
from shapely import STRtree, affinity, prepare
from shapely.geometry import LineString, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import substring, unary_union

import style
from frame import PLAY_HALF_M
from gen_city import ROAD_SETBACK_M, rng_at
from solar import Quads

LIGHT = style.ROOF_LIGHT
## How much a face's direction to the light changes its grey (talls).
FACE_SHADE = 0.4
## Paint of the court and pitch markings: grey, alpha, line width (m).
PAINT_V, PAINT_A, PAINT_W = 0.36, 0.7, 0.12


# ------------------------------------------------------------------ shapes

def ngon(x, y, r, n, rot=0.0):
    a = np.linspace(0, 2 * np.pi, n, endpoint=False) + rot
    return Polygon(np.stack([x + np.cos(a) * r, y + np.sin(a) * r], 1))


def square(x, y, side, ang=0.0):
    h = side / 2
    return affinity.rotate(box(x - h, y - h, x + h, y + h), ang, origin=(x, y), use_radians=True)


class Local:
    """A local frame at (cx, cy) turned by ang (radians): x along, y
    across."""

    def __init__(self, cx, cy, ang):
        self.cx, self.cy, self.ang = cx, cy, ang
        self.cs, self.sn = np.cos(ang), np.sin(ang)

    def pt(self, x, y):
        return (self.cx + x * self.cs - y * self.sn, self.cy + x * self.sn + y * self.cs)

    def rect(self, x0, y0, x1, y1):
        return Polygon([self.pt(x0, y0), self.pt(x1, y0), self.pt(x1, y1), self.pt(x0, y1)])

    def line(self, pts):
        return LineString([self.pt(x, y) for x, y in pts])

    def poly(self, pts):
        return Polygon([self.pt(x, y) for x, y in pts])

    def to_local(self, x, y):
        dx, dy = x - self.cx, y - self.cy
        return dx * self.cs + dy * self.sn, -dx * self.sn + dy * self.cs

    def quads(self):
        return Quads(Point(self.cx, self.cy), np.degrees(self.ang))


# ------------------------------------------------------------------- domes

def dome(L, sub, x, y, r, v, chunk, ribs=0, steps=4, n=None, drum=True, finial=True):
    """A shaded dome of radius r: a dark drum ring, then discs that shrink
    and move towards the light, each a little brighter, then ribs and a
    finial at the top."""
    n = n or (12 if r < 2.5 else 18 if r < 5 else 24)
    if drum:
        L.fill(sub, ngon(x, y, r * 1.12, n), 0.0, 0.5, chunk=chunk)
        L.fill(sub, ngon(x, y, r * 1.06, n), v * 0.8, chunk=chunk)
    L.fill(sub, ngon(x, y, r, n), v, chunk=chunk)
    for i in range(1, steps + 1):
        t = i / (steps + 1)
        cx, cy = x + LIGHT[0] * r * 0.32 * t, y + LIGHT[1] * r * 0.32 * t
        L.fill(sub, ngon(cx, cy, r * (1 - 0.82 * t), n), min(v * (1 + 0.55 * t), 0.5), chunk=chunk)
    if ribs:
        for k in range(ribs):
            a = 2 * np.pi * k / ribs
            L.line(sub, LineString([(x + np.cos(a) * r * 0.2, y + np.sin(a) * r * 0.2),
                                    (x + np.cos(a) * r * 0.97, y + np.sin(a) * r * 0.97)]),
                   max(0.05, r * 0.025), v * 0.6, 0.8, chunk=chunk)
    L.line(sub, ngon(x, y, r, n).exterior, max(0.08, r * 0.03), style.OUTLINE_V * 0.8, chunk=chunk)
    if finial:
        L.fill(sub, ngon(x + LIGHT[0] * r * 0.1, y + LIGHT[1] * r * 0.1, max(0.15, r * 0.07), 6), 0.45, chunk=chunk)


def crenellations(L, sub, geom, v, chunk, step=1.2, size=0.5):
    """Small square merlons along the outline of each polygon in geom (a
    parapet: the stepped crenellation of old Cairo mosques, seen from
    above)."""
    for g in style.polys(geom):
        line = LineString(g.exterior.coords)
        for d in np.arange(step / 2, line.length, step):
            p = line.interpolate(d)
            q = line.interpolate(min(d + 0.1, line.length))
            a = np.arctan2(q.y - p.y, q.x - p.x)
            L.fill(sub, square(p.x, p.y, size, a), v, chunk=chunk)


# ------------------------------------------------------------------- talls

def tall_solid(L, poly, h0, h1, v, chunk, v_top=None, a=1.0):
    """A prism standing from h0 to h1 on poly, one grey per side face by its
    direction to the light, and its top at h1."""
    ring = np.asarray(orient(poly, 1.0).exterior.coords)[:-1]
    p = ring
    q = np.roll(p, -1, 0)
    d = q - p
    ln = np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)
    nrm = np.stack([d[:, 1], -d[:, 0]], 1) / ln[:, None]
    lit = 1.0 + FACE_SHADE * (nrm @ LIGHT)
    tris = np.concatenate([np.stack([p, q, q], 1), np.stack([p, q, p], 1)])
    vh = np.concatenate([np.tile([h0, h0, h1], (len(p), 1)), np.tile([h0, h1, h1], (len(p), 1))]).astype(np.float32)
    grey = np.clip(np.concatenate([lit, lit]) * v, 0, 1)
    L.add_tris("talls", tris, 0.0, a, chunk=chunk, vg=np.repeat(grey[:, None], 3, 1), vh=vh)
    L.fill("talls", poly, v_top if v_top is not None else min(v * 1.25, 0.6), a, chunk=chunk, h=h1)


def tall_cone(L, x, y, r, h0, h1, v, chunk, n=12, a=1.0):
    """A cone (or pyramid with n=4) from a ring of radius r at h0 to its
    apex at h1."""
    ring = np.asarray(orient(ngon(x, y, r, n, np.pi / n if n == 4 else 0.0), 1.0).exterior.coords)[:-1]
    q = np.roll(ring, -1, 0)
    apex = np.tile([x, y], (len(ring), 1))
    mid = (ring + q) / 2 - (x, y)
    ln = np.maximum(np.hypot(mid[:, 0], mid[:, 1]), 1e-9)
    lit = 1.0 + FACE_SHADE * 1.2 * ((mid / ln[:, None]) @ LIGHT)
    tris = np.stack([ring, q, apex], 1)
    vh = np.tile([h0, h0, h1], (len(ring), 1)).astype(np.float32)
    grey = np.clip(lit * v, 0, 1)
    L.add_tris("talls", tris, 0.0, a, chunk=chunk, vg=np.repeat(grey[:, None], 3, 1), vh=vh)


def tall_bulb(L, x, y, r, h0, h1, v, chunk, n=12):
    """An onion or round dome cap: a short drum then a cone with a bulge."""
    hm = h0 + (h1 - h0) * 0.35
    tall_solid(L, ngon(x, y, r, n), h0, hm, v, chunk, v_top=v * 1.15)
    tall_cone(L, x, y, r * 1.05, hm, h1, v * 1.1, chunk, n)


MINARET_STYLES = ("mamluk", "ottoman", "modern", "mamluk", "modern")


def minaret(L, x, y, height, style_name, ang, rng, broken=False, v=0.3):
    """A minaret standing at (x, y): "mamluk" (square base, octagonal and
    round tiers, two balconies, a pavilion and a bulb), "ottoman" (a slim
    shaft, one or two balconies, a tall pencil cone) or "modern" (a square
    shaft, a balcony box, an upper shaft, a small cap). broken: only a stump
    with a jagged top."""
    key = style.chunk_key(Point(x, y))
    H = float(height)
    if broken:
        H = H * rng.uniform(0.3, 0.5)
    if style_name == "mamluk":
        s = rng.uniform(3.4, 4.0)
        tiers = [("sq", s, 0.0, 0.36), ("bal8", s * 0.78, 0.36, 0.36), ("oct", s * 0.48, 0.36, 0.64),
                 ("bal8", s * 0.66, 0.64, 0.64), ("round", s * 0.35, 0.64, 0.84), ("pav", s * 0.3, 0.84, 0.93),
                 ("bulb", s * 0.28, 0.93, 1.0)]
    elif style_name == "ottoman":
        r = rng.uniform(1.05, 1.3)
        tiers = [("sq", r * 2.6, 0.0, 0.1), ("shaft", r, 0.1, 0.48), ("bal", r * 1.6, 0.48, 0.48)]
        if rng.random() < 0.6:
            tiers += [("shaft", r, 0.48, 0.7), ("bal", r * 1.55, 0.7, 0.7), ("shaft", r * 0.95, 0.7, 0.78)]
        else:
            tiers += [("shaft", r, 0.48, 0.78)]
        tiers += [("cone", r * 1.08, 0.78, 1.0)]
    else:
        s = rng.uniform(2.6, 3.2)
        tiers = [("sq", s, 0.0, 0.74), ("balsq", s * 1.5, 0.74, 0.74), ("sq", s * 0.75, 0.74, 0.9),
                 ("cap", s * 0.42, 0.9, 1.0)]
    top_h = 0.0
    for kind, size, f0, f1 in tiers:
        h0, h1 = f0 * height, f1 * height
        if h0 >= H:
            break
        h1 = min(h1, H)
        if kind == "sq":
            tall_solid(L, square(x, y, size, ang), h0, h1, v, key)
        elif kind == "oct":
            tall_solid(L, ngon(x, y, size, 8, ang + np.pi / 8), h0, h1, v * 1.05, key)
        elif kind in ("round", "shaft"):
            tall_solid(L, ngon(x, y, size, 12, ang), h0, h1, v * 1.08, key)
        elif kind == "pav":
            tall_solid(L, ngon(x, y, size, 8, ang + np.pi / 8), h0, h1, v * 0.8, key, v_top=v * 1.3)
        elif kind in ("bal8", "bal", "balsq"):
            if kind == "balsq":
                g = square(x, y, size, ang)
            else:
                g = ngon(x, y, size, 8 if kind == "bal8" else 12, ang + np.pi / 8)
            tall_solid(L, g, h0 - 0.7, h0, v * 0.85, key, v_top=min(v * 1.45, 0.6))
            L.line("talls", g.exterior, 0.12, 0.08, 0.8, chunk=key, h=h0)
        elif kind == "bulb":
            tall_bulb(L, x, y, size, h0, h1, v * 1.15, key)
        elif kind == "cone":
            tall_cone(L, x, y, size, h0, h1, v * 1.05, key, n=12)
        elif kind == "cap":
            tall_bulb(L, x, y, size, h0, h1, v * 1.1, key, n=10)
        top_h = h1
    if broken:
        for _ in range(4):
            a = rng.uniform(0, 2 * np.pi)
            d = rng.uniform(0.3, 1.0)
            L.fill("talls", ngon(x + np.cos(a) * d, y + np.sin(a) * d, rng.uniform(0.3, 0.6), 5,
                                 rng.uniform(0, 1)), rng.uniform(0.12, 0.25), chunk=key, h=top_h + 0.1)
    elif style_name != "ottoman":
        L.fill("talls", ngon(x, y, 0.16, 6), 0.5, chunk=key, h=height + 0.3)
    return top_h


def bell_tower(L, x, y, side, height, ang, v=0.3, cap="dome"):
    """A square bell tower: a shaft, a darker belfry storey with openings, a
    cornice, a small dome or a pyramid cap and a cross."""
    key = style.chunk_key(Point(x, y))
    hb = height * 0.68
    tall_solid(L, square(x, y, side, ang), 0.0, hb, v, key)
    tall_solid(L, square(x, y, side * 1.12, ang), hb - 0.4, hb, v * 0.85, key, v_top=v * 1.35)
    tall_solid(L, square(x, y, side * 0.92, ang), hb, height * 0.84, v * 0.7, key, v_top=v * 0.5)
    tall_solid(L, square(x, y, side * 1.05, ang), height * 0.84 - 0.3, height * 0.84, v * 0.9, key,
               v_top=v * 1.4)
    if cap == "dome":
        tall_bulb(L, x, y, side * 0.42, height * 0.84, height * 0.97, v * 1.15, key)
    else:
        tall_cone(L, x, y, side * 0.62, height * 0.84, height * 0.97, v * 1.1, key, n=4)
    cs, sn = np.cos(ang), np.sin(ang)
    for (ax, ay), w in (((0.9, 0.0), 0.14), ((0.0, 0.55), 0.14)):
        L.tall_span((x - ax * cs + ay * sn, y - ax * sn - ay * cs), (x + ax * cs - ay * sn, y + ax * sn + ay * cs),
                    w, height, height, 0.5, chunk=key)


def floodlight(L, x, y, height, facing, v=0.32):
    """A floodlight mast: a slim post and a lamp frame at the top, turned to
    face the pitch (facing, radians)."""
    key = style.chunk_key(Point(x, y))
    tall_solid(L, square(x, y, 0.55, facing), 0.0, height - 0.8, v, key)
    cx, cy = x + np.cos(facing) * 0.5, y + np.sin(facing) * 0.5
    panel = affinity.rotate(box(cx - 0.45, cy - 1.7, cx + 0.45, cy + 1.7), facing, origin=(cx, cy), use_radians=True)
    tall_solid(L, panel, height - 1.6, height, v * 0.8, key, v_top=0.2)
    for k in range(4):
        t = -1.25 + k * 0.83
        px, py = cx - np.sin(facing) * t, cy + np.cos(facing) * t
        L.fill("talls", square(px, py, 0.55, facing), 0.55, chunk=key, h=height + 0.05)


def flagpole(L, x, y, height, ang, rng):
    key = style.chunk_key(Point(x, y))
    tall_solid(L, square(x, y, 0.22, 0.0), 0.0, height, 0.4, key)
    fx, fy = x + np.cos(ang) * 1.6, y + np.sin(ang) * 1.6
    L.tall_span((x, y), (fx, fy), 1.0, height - 0.6, height - 0.8, 0.3, chunk=key)


# ------------------------------------------------------------------- walls

def circle_spans(spans, n):
    """Spans (d0, d1) of distance along a closed ring of length n, each
    brought into 0..n (one that runs past either end is split in two),
    sorted and merged where they overlap."""
    out = []
    for a, b in spans:
        ln = min(b - a, n)
        a = a % n
        if a + ln > n:
            out += [(a, n), (0.0, a + ln - n)]
        else:
            out.append((a, a + ln))
    merged = []
    for a, b in sorted(out):
        if merged and a <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], b))
        else:
            merged.append((a, b))
    return merged


def ring_pieces(line, spans):
    """The pieces of a closed ring (a LineString round from its start back
    to it) over sorted spans in 0..n; a span ending at n and one starting at
    0 are one piece across the start."""
    n = line.length
    if len(spans) >= 2 and spans[0][0] <= 1e-9 and spans[-1][1] >= n - 1e-9:
        head, tail = substring(line, spans[-1][0], n), substring(line, 0.0, spans[0][1])
        out = [LineString(list(head.coords) + list(tail.coords)[1:])]
        out += [substring(line, a, b) for a, b in spans[1:-1]]
    else:
        out = [substring(line, a, b) for a, b in spans]
    return [p for p in out if not p.is_empty and p.length > 0.3]


def cut_ring(line, spans):
    """A closed ring with the spans (d0, d1) of distance along it cut out;
    a span may run past either end and wraps round. Returns (the pieces
    left, the pieces cut out)."""
    n = line.length
    cut = circle_spans(spans, n)
    keep, d = [], 0.0
    for a, b in cut:
        if a > d:
            keep.append((d, a))
        d = max(d, b)
    if d < n:
        keep.append((d, n))
    return ring_pieces(line, keep), ring_pieces(line, cut)


def wall_parts(ring, gates, gap):
    """The pieces of a ring (or line) left after cutting a gap at each gate
    point (on a closed ring a gap wraps round its start)."""
    line = LineString(ring.coords)
    if line.is_closed and len(line.coords) > 3:
        return cut_ring(line, [(line.project(g) - gap / 2, line.project(g) + gap / 2) for g in gates])[0]
    cuts = sorted(line.project(g) for g in gates)
    parts, d0 = [], 0.0
    for d in cuts:
        if d - gap / 2 > d0 + 0.3:
            parts.append(substring(line, d0, d - gap / 2))
        d0 = max(d0, d + gap / 2)
    if line.length > d0 + 0.3:
        parts.append(substring(line, d0, line.length))
    return [p for p in parts if not p.is_empty and p.length > 0.3]


def point_along(line, d):
    """The point at distance d along a line and the line's direction there
    (radians); on a closed ring d wraps round, on an open line it stops at
    the ends."""
    n = line.length
    d = d % n if line.is_closed else min(max(d, 0.0), n)
    p = line.interpolate(d)
    q = line.interpolate(min(d + 0.2, n)) if d + 0.2 <= n else line.interpolate(max(d - 0.2, 0.0))
    a = np.arctan2(q.y - p.y, q.x - p.x) if d + 0.2 <= n else np.arctan2(p.y - q.y, p.x - q.x)
    return p, a


def compound_wall(L, ring, v=0.3, width=0.5, gates=(), gap=5.0, chunk=None, piers=True, sub="interiors"):
    """A masonry compound wall drawn on the ground: a soft shadow, the wall
    top and a coping line, with a gap and two piers at each gate."""
    parts = wall_parts(ring, gates, gap)
    for part in parts:
        L.line(sub, part, width + 0.9, 0.0, 0.35, chunk=chunk)
        L.line(sub, part, width, v, chunk=chunk)
        L.line(sub, part, 0.08, min(v * 1.4, 0.5), 0.8, chunk=chunk)
    if piers:
        line = LineString(ring.coords)
        for g in gates:
            d = line.project(g)
            for dd in (d - gap / 2, d + gap / 2):
                p, a = point_along(line, dd)
                L.fill(sub, square(p.x, p.y, width * 2.2, a), 0.0, 0.4, chunk=chunk)
                L.fill(sub, square(p.x, p.y, width * 1.8, a), min(v * 1.25, 0.5), chunk=chunk)
    return parts


def gate_points(poly, roads_union, n=1, min_gap=25.0):
    """Up to n points on a polygon's outline nearest the roads, at least
    min_gap apart along it."""
    ring = poly.exterior
    if roads_union is None or roads_union.is_empty:
        return [ring.interpolate(0.25, normalized=True)]
    ds = np.arange(0, ring.length, 2.0)
    pts = [ring.interpolate(d) for d in ds]
    dist = np.array([roads_union.distance(p) for p in pts])
    out, at = [], []
    for i in np.argsort(dist, kind="stable"):
        if dist[i] > 12.0 and out:
            break
        sep = [min(abs(ds[i] - d), ring.length - abs(ds[i] - d)) for d in at]
        if all(s > min_gap for s in sep):
            out.append(pts[i])
            at.append(ds[i])
        if len(out) >= n:
            break
    return out


# ------------------------------------------------------------------ courts

def paint_line(Q, pts, w=PAINT_W, v=PAINT_V, a=PAINT_A):
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        Q.line(x0, y0, x1, y1, w, v, a)


def arc(cx, cy, r, a0, a1, n=None):
    n = n or max(4, int(abs(a1 - a0) * r / 1.2))
    a = np.linspace(a0, a1, n + 1)
    return list(zip(cx + np.cos(a) * r, cy + np.sin(a) * r))


def rect_pts(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)]


def surface(L, poly, v, a=0.9, chunk=None, edge_v=None):
    L.fill("groundlines", poly, v, a, chunk=chunk)
    if edge_v is not None:
        L.line("groundlines", poly.exterior, 0.15, edge_v, 0.7, chunk=chunk)


def football(L, F, length, width, chunk, goals=True):
    """Pitch markings centred on F's origin, the long axis along F's x:
    touchlines, halfway line, centre circle, penalty and goal areas, penalty
    spots and arcs, corner arcs and goals. Sizes scale with the pitch."""
    Q = F.quads()
    hl, hw = length / 2, width / 2
    k = min(1.0, length / 100.0)
    paint_line(Q, rect_pts(-hl, -hw, hl, hw))
    paint_line(Q, [(0, -hw), (0, hw)])
    paint_line(Q, arc(0, 0, 9.15 * k, 0, 2 * np.pi, 28))
    for s in (-1, 1):
        pd, pw = 16.5 * k, min(40.3 * k, width * 0.62) / 2
        gd, gw = 5.5 * k, min(18.3 * k, width * 0.3) / 2
        x0 = s * hl
        paint_line(Q, [(x0, -pw), (x0 - s * pd, -pw), (x0 - s * pd, pw), (x0, pw)])
        paint_line(Q, [(x0, -gw), (x0 - s * gd, -gw), (x0 - s * gd, gw), (x0, gw)])
        spot = x0 - s * 11.0 * k
        Q.rect(spot - 0.2, -0.2, spot + 0.2, 0.2, PAINT_V, PAINT_A)
        r = 9.15 * k
        if r > pd - 11.0 * k:
            c = np.arccos(min(1.0, (pd - 11.0 * k) / r))
            a0, a1 = (np.pi - c, np.pi + c) if s > 0 else (-c, c)
            paint_line(Q, arc(spot, 0, r, a0, a1, 8))
        for t in (-1, 1):
            a0 = np.arctan2(0.0, -s)
            a1 = a0 + np.pi / 2 * (1 if s * t > 0 else -1)
            paint_line(Q, arc(x0, t * hw, 1.0, a0, a1, 3))
        if goals:
            gx = x0 + s * 1.2
            Q.rect(min(x0, gx), -3.66 * k, max(x0, gx), 3.66 * k, 0.05, 0.5)
            paint_line(Q, [(x0, -3.66 * k), (gx, -3.66 * k), (gx, 3.66 * k), (x0, 3.66 * k)], 0.14, 0.42, 0.9)
    Q.flush(L, "groundlines", chunk)


def basketball(L, F, chunk, length=28.0, width=15.0):
    Q = F.quads()
    hl, hw = length / 2, width / 2
    paint_line(Q, rect_pts(-hl, -hw, hl, hw))
    paint_line(Q, [(0, -hw), (0, hw)])
    paint_line(Q, arc(0, 0, 1.8, 0, 2 * np.pi, 14))
    for s in (-1, 1):
        x0 = s * hl
        paint_line(Q, [(x0, -2.45), (x0 - s * 5.8, -2.45), (x0 - s * 5.8, 2.45), (x0, 2.45)])
        paint_line(Q, arc(x0 - s * 5.8, 0, 1.8, -np.pi / 2, np.pi / 2, 8) if s < 0 else
                   arc(x0 - s * 5.8, 0, 1.8, np.pi / 2, 3 * np.pi / 2, 8))
        hx = x0 - s * 1.575
        c = np.arcsin(min(1.0, 6.6 / 6.75))
        a0, a1 = (np.pi - c, np.pi + c) if s > 0 else (-c, c)
        three = arc(hx, 0, 6.75, a0, a1, 16)
        paint_line(Q, [(x0, three[0][1])] + three + [(x0, three[-1][1])])
        Q.rect(x0 - s * 1.2 - 0.05, -0.9, x0 - s * 1.2 + 0.05, 0.9, 0.45, 0.9)
        Q.rect(hx - 0.25, -0.25, hx + 0.25, 0.25, 0.4, 0.8)
    Q.flush(L, "groundlines", chunk)


def tennis(L, F, chunk):
    Q = F.quads()
    hl, hd, hs = 23.77 / 2, 10.97 / 2, 8.23 / 2
    paint_line(Q, rect_pts(-hl, -hd, hl, hd))
    paint_line(Q, [(-hl, -hs), (hl, -hs)])
    paint_line(Q, [(-hl, hs), (hl, hs)])
    paint_line(Q, [(-6.4, -hs), (-6.4, hs)])
    paint_line(Q, [(6.4, -hs), (6.4, hs)])
    paint_line(Q, [(-6.4, 0), (6.4, 0)])
    Q.line(0, -hd - 0.9, 0, hd + 0.9, 0.1, 0.45, 0.9)
    Q.flush(L, "groundlines", chunk)


def volleyball(L, F, chunk):
    Q = F.quads()
    paint_line(Q, rect_pts(-9, -4.5, 9, 4.5))
    paint_line(Q, [(-3, -4.5), (-3, 4.5)])
    paint_line(Q, [(3, -4.5), (3, 4.5)])
    Q.line(0, -5.2, 0, 5.2, 0.1, 0.45, 0.9)
    Q.flush(L, "groundlines", chunk)


def running_track(L, F, straight, r_in, lanes, chunk, v=0.2):
    """A running track round F's origin: straights along x, bends of inner
    radius r_in, lanes of 1.22 m."""
    lane = 1.22
    r_out = r_in + lanes * lane

    def oval(r, n=24):
        h = straight / 2
        pts = arc(h, 0, r, -np.pi / 2, np.pi / 2, n) + arc(-h, 0, r, np.pi / 2, 3 * np.pi / 2, n)
        return F.poly(pts)

    outer, inner = oval(r_out), oval(r_in)
    L.fill("groundlines", outer.difference(inner), v, 0.95, chunk=chunk)
    Q = F.quads()
    for i in range(lanes + 1):
        r = r_in + i * lane
        h = straight / 2
        pts = arc(h, 0, r, -np.pi / 2, np.pi / 2, 20) + arc(-h, 0, r, np.pi / 2, 3 * np.pi / 2, 20)
        paint_line(Q, pts + [pts[0]], 0.08, 0.34, 0.6 if 0 < i < lanes else 0.75)
    for x in (straight / 2, -straight / 2 + 10.0):
        Q.line(x, -r_out, x, -r_in, 0.12, 0.4, 0.75)
    Q.flush(L, "groundlines", chunk)
    return outer, inner


# --------------------------------------------------------------- placing

def free_land(site, area, setback=ROAD_SETBACK_M, districts=True):
    """What is left of area for a civic place: inside the play area, less
    the roads (grown by setback), water, claims, KeepOut areas, the markers'
    clear circles and, with districts, what the district modules built."""
    if area is None or area.is_empty:
        return Polygon()
    lim = PLAY_HALF_M - 1.0
    area = area.intersection(box(-lim, -lim, lim, lim))
    cut = []
    roads = site.road_union_near(area, 2.0)
    if roads is not None and not roads.is_empty:
        cut.append(roads.buffer(setback))
    if site.water is not None and not site.water.is_empty:
        cut.append(site.water.buffer(2.0).intersection(area.buffer(5)))
    c = site.claimed()
    if c is not None:
        cut.append(c.intersection(area.buffer(5)))
    if site.keep_out is not None and not site.keep_out.is_empty:
        cut.append(site.keep_out.buffer(2.0))
    for _, mx, my in site.markers:
        cut.append(Point(mx, my).buffer(21.0))
    if districts:
        d = site.district_taken()
        if d is not None:
            cut.append(d.intersection(area.buffer(5)))
    cut = [g for g in cut if g is not None and not g.is_empty]
    return area.difference(unary_union(cut)) if cut else area


class Layout:
    """The whole map's layout (site.full_layout) with lookups: the roads'
    concrete and kinds, the blocks, and the lots and large roofs in STR
    trees."""

    def __init__(self, site):
        fl = site.full_layout or {"roads": site.roads, "blocks": site.blocks,
                                  "big": [b.poly for b in site.buildings if b.kind == "big"],
                                  "lots": [b.poly for b in site.buildings if b.kind == "house"]}
        self.roads = [r for r in fl["roads"] if not r[4].startswith("rail:")]
        self.road_geoms = [r[0] for r in self.roads]
        self.road_tree = STRtree(self.road_geoms)
        self.blocks = fl["blocks"]
        self.lots = fl["lots"]
        self.big = fl["big"]
        self.lot_tree = STRtree(self.lots) if self.lots else None
        self.big_tree = STRtree(self.big) if self.big else None

    def roads_near(self, geom, dist):
        idx = self.road_tree.query(geom.buffer(dist))
        return unary_union([self.road_geoms[i] for i in idx]) if len(idx) else None

    def roads_at(self, geom, dist):
        """(centre line, kind, width) of the roads whose concrete comes within
        dist of geom."""
        idx = self.road_tree.query(geom.buffer(dist))
        return [(self.roads[i][5], self.roads[i][4], self.roads[i][2]) for i in idx
                if self.roads[i][5] is not None and self.road_geoms[i].distance(geom) <= dist]

    def lots_in(self, geom):
        if self.lot_tree is None:
            return []
        return [self.lots[i] for i in self.lot_tree.query(geom) if self.lots[i].intersects(geom)]

    def big_in(self, geom):
        if self.big_tree is None:
            return []
        return [self.big[i] for i in self.big_tree.query(geom) if self.big[i].intersects(geom)]


def find_building(site, poly, tol=0.6):
    """The Building in site.buildings with this footprint (its centre within
    tol and its area within 3%), or None."""
    c = poly.centroid
    for b in site.buildings:
        bc = b.poly.centroid
        if abs(bc.x - c.x) < tol and abs(bc.y - c.y) < tol and abs(b.poly.area - poly.area) < 0.03 * poly.area:
            return b
    return None


def grid_pick(cands, n_cells, min_d, seeds=(), n_max=None):
    """One candidate per cell of an n_cells x n_cells grid over the play
    area: the best score, then the nearest the cell's middle, at least min_d
    from the seeds and from the picks before it (cells in row order). With
    n_max, only the n_max best-scored picks are kept."""
    cell = 2 * PLAY_HALF_M / n_cells
    by_cell = {}
    for c in cands:
        i = int(np.clip((c["y"] + PLAY_HALF_M) // cell, 0, n_cells - 1))
        j = int(np.clip((c["x"] + PLAY_HALF_M) // cell, 0, n_cells - 1))
        by_cell.setdefault((i, j), []).append(c)
    taken = list(seeds)
    out = []
    for (i, j) in sorted(by_cell):
        mx = -PLAY_HALF_M + (j + 0.5) * cell
        my = -PLAY_HALF_M + (i + 0.5) * cell
        for c in sorted(by_cell[(i, j)], key=lambda c: (-round(c["score"], 3), np.hypot(c["x"] - mx, c["y"] - my))):
            if all(np.hypot(c["x"] - x, c["y"] - y) >= min_d for x, y in taken):
                out.append(c)
                taken.append((c["x"], c["y"]))
                break
    if n_max is not None and len(out) > n_max:
        keep = sorted(range(len(out)), key=lambda k: -out[k]["score"])[:n_max]
        out = [out[k] for k in sorted(keep)]
    return out


def away_from(cands, pts, d):
    """The candidates at least d from every point of pts."""
    if not pts:
        return cands
    xy = np.asarray(pts, float)
    return [c for c in cands if np.min(np.hypot(xy[:, 0] - c["x"], xy[:, 1] - c["y"])) >= d]


MAIN_ROADS = {"trunk", "secondary", "tertiary", "secondary_link", "tertiary_link"}
## Least distance between two compounds of different kinds (schools,
## pitches, churches, large mosques), m.
COMPOUND_GAP_M = 250.0


class Compound:
    """A rectangular site for a walled compound: its polygon and a frame at
    its centre with x along the street side and y pointing in from it (the
    street side is at y = -h / 2)."""

    def __init__(self, poly, F, w, h, main_road):
        self.poly, self.F, self.w, self.h, self.main_road = poly, F, w, h, main_road
        c = poly.centroid
        self.x, self.y = c.x, c.y

    def rect(self, x0, y0, x1, y1):
        return self.F.rect(x0, y0, x1, y1)


def compound_sites(site, lay, sizes, codes, rng_seed, min_share=0.7, avoid=None):
    """Candidate compound sites over the whole map, at most one per street
    block mostly of the district codes: a rectangle of one of sizes ((w, h)
    in m, w along the street), turned with the block, slid along it in 5 m
    steps and pushed as far towards either long side as it fits 1.5 m inside
    the block; clear of large roofs, water, KeepOut areas, markers, claims
    and avoid, with a road's concrete within 3 m of its street side. The block's best
    spot wins: open ground first (few house lots to clear), then a main road
    in front, then a block corner (either end of the slide)."""
    out = []
    for blk in lay.blocks:
        w_min = min(w for w, _ in sizes)
        h_min = min(h for _, h in sizes)
        if blk.area < w_min * h_min * 1.15:
            continue
        x0, y0, x1, y1 = blk.bounds
        if max(abs(x0), abs(x1), abs(y0), abs(y1)) > PLAY_HALF_M - 40.0:
            continue
        if sum(site.districts.share(blk, c) for c in codes) < min_share:
            continue
        r = rng_at(rng_seed, *blk.centroid.coords[0])
        w, h = sizes[int(r.integers(len(sizes)))]
        Fb = _block_frame(blk)
        if Fb.w < w + 3.0 or Fb.h < h + 3.0:
            continue
        inside = blk.buffer(-1.5, join_style="mitre")
        prepare(inside)
        spots = []
        xs = np.arange(Fb.x0 + 1.5, Fb.x1 - 1.5 - w + 0.01, 5.0)
        for k, fx in enumerate(xs):
            ys = np.arange(Fb.y0 + 1.5, Fb.y1 - 1.5 - h + 0.01, 2.5)
            end = k == 0 or k == len(xs) - 1
            for fy in ys:
                if inside.contains(Fb.rect(fx, fy, fx + w, fy + h)):
                    spots.append((fx, fy, -1, end))
                    break
            for fy in ys[::-1]:
                if inside.contains(Fb.rect(fx, fy, fx + w, fy + h)):
                    spots.append((fx, fy, 1, end))
                    break
        best = None
        for fx, fy, front, end in spots:
            rect = Fb.rect(fx, fy, fx + w, fy + h)
            if lay.big_in(rect):
                continue
            if avoid is not None and avoid.intersects(rect):
                continue
            if not site.is_free(rect, margin=2.0, districts=False):
                continue
            if site.water is not None and site.water.intersects(rect.buffer(3.0)):
                continue
            ang = Fb.rad if front < 0 else Fb.rad + np.pi
            F = Local(rect.centroid.x, rect.centroid.y, ang)
            lines = lay.roads_at(F.line([(-w / 4, -h / 2 - 0.5), (w / 4, -h / 2 - 0.5)]), 2.5)
            if not lines:
                continue
            main = any(k in MAIN_ROADS for _, k, _ in lines)
            lots = len(lay.lots_in(rect))
            score = -lots * 100.0 / rect.area + (1.5 if main else 0.0) + (0.5 if end else 0.0) + r.uniform(0, 0.3)
            if best is None or score > best[0]:
                best = (score, Compound(rect, F, w, h, main))
        if best is not None:
            c = best[1]
            out.append({"x": c.x, "y": c.y, "score": best[0], "site": c})
    return out


def _block_frame(blk):
    from kit import Frame
    return Frame(blk)


def clear_for(site, area, kinds=("house",)):
    """Takes a compound's ground: drops the house lots in or
    touching it and the props and sources inside."""
    site.remove_buildings_touching(area, kinds=kinds, margin=0.0)
    site.clear_area(area.buffer(0.5))


def take_compound(site, cp, tag):
    """Claims a compound site (always), and in the window clears its
    ground; returns whether to build it here."""
    site.claim(cp.poly, tag)
    if not site.in_window(cp.poly):
        return False
    d = site.district_taken()
    if d is not None and d.intersects(cp.poly):
        return False
    clear_for(site, cp.poly)
    site.solid_extra.append(cp.poly)
    return True
