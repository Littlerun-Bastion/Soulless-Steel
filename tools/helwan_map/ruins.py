"""Building ruin states: which buildings are ruined, and how a ruin is drawn.
All states are operations on any footprint, so no building needs a
hand-made ruined variant.

Which buildings (assign_states):
  A damage map over the map: BLAST_CENTRES seeded blast centres (gaussian
  blobs BLAST_RADIUS_M across, of random strength) plus smooth noise. Each
  building reads the map at its centre, scaled by its district
  (DISTRICT_SCALE: industrial more, farmland less), plus a little jitter of
  its own, so ruins cluster but no two neighbours are forced alike. The value
  against STATE_LIMITS gives the state.

How (the game reads the state from footprints.bin; see buildings.py for the
drawing order):
  damaged    noisy circular holes cut from the roof, centred on the outline
             (HOLE_EDGE_R_M), plus one near the centre (HOLE_CENTRE_R_M) on
             larger roofs. The interior shows through them; roof items stay
             clear of them. Rubble spills out of the edge holes; cracks run
             from the holes; the holes' rims are jagged.
  gutted     two roof fragments kept near the outline; the outer wall drawn as
             segments of WALL_SEG_M with WALL_MISSING of them missing; rubble
             inside and round the outline; scorch. The game keeps the whole
             outline as a wall; the gaps are visual only.
  collapsed  a heap (the footprint grown by HEAP_GROW_M, with noisy bites out
             of its edge), 2 to 5 large roof slabs with cracks (collapsed_slabs:
             they stay inside the footprint and off each other, so they never
             read as buildings on top of buildings), dense rubble,
             and wall stubs at about STUB_CORNERS of the corners. All of it
             is ground: the game gives the building no wall, no slow and no
             roof. Some collapsed buildings (RUBBLE_SOURCE_CHANCE) get one
             "rubble" salvage search point.
"""
import numpy as np
import shapely
from scipy import ndimage as ndi
from shapely import affinity
from shapely.geometry import LineString, LinearRing, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import substring, unary_union

import style
from frame import MAP_M

INTACT, DAMAGED, GUTTED, COLLAPSED = 0, 1, 2, 3

## Number of blast centres over the whole map, their gaussian radius (m) and
## the range of their strength.
BLAST_CENTRES = 16
BLAST_RADIUS_M = (140.0, 380.0)
BLAST_STRENGTH = (0.55, 1.0)
## Smooth noise added to the blasts: its scale (m) and strength.
NOISE_SCALE_M = 220.0
NOISE_STRENGTH = 0.3
## Each building's own jitter (standard deviation).
JITTER = 0.12
## Damage scale per district (residential, industrial, market, farmland).
DISTRICT_SCALE = (1.0, 1.3, 1.1, 0.6)
## Damage at or above each limit gives damaged, gutted, collapsed.
STATE_LIMITS = (0.42, 0.66, 0.86)
## Buildings larger than this (m2: industrial halls, sheds) are at most
## gutted: their steel frames stay up.
BIG_MAX_COLLAPSED_M2 = 1500.0
DAMAGE_CELL_M = 25.0

HOLE_EDGE_R_M = (1.8, 3.2)
HOLE_CENTRE_R_M = 3.6
WALL_SEG_M = (1.0, 3.0)
WALL_MISSING = 0.4
HEAP_GROW_M = 1.8
## Collapsed roof slabs: the narrowest slab (m, and share of the footprint's
## length), the most a slab's end moves when it is turned (m), the most it
## is pushed (m), and the gap kept between slabs (m).
SLAB_MIN_M = 3.5
SLAB_MIN_SHARE = 0.16
SLAB_TURN_M = 0.5
SLAB_PUSH_M = 0.5
SLAB_GAP_M = 0.3
STUB_CORNERS = 0.65
RUBBLE_SOURCE_CHANCE = 0.3

RUBBLE_V = (0.07, 0.22)
HEAP_V = 0.13
## Rubble pieces per m2 (and their sizes, m): inside damaged holes, spilled
## out of them, inside and round gutted buildings, on collapsed heaps.
RUBBLE_HOLE = 0.3
RUBBLE_SPILL = 0.2
RUBBLE_GUTTED = (0.1, 0.08)
RUBBLE_HEAP = (0.12, 0.16)
RUBBLE_MAX = 110
SCORCH_A = 0.55


def damage_map(seed):
    """Damage over the map on a DAMAGE_CELL_M grid, about 0..1.5."""
    rng = np.random.default_rng(seed)
    n = int(round(MAP_M / DAMAGE_CELL_M))
    half = MAP_M / 2
    c = (np.arange(n) + 0.5) * DAMAGE_CELL_M - half
    yy, xx = np.meshgrid(c, c, indexing="ij")
    d = np.zeros((n, n))
    for _ in range(BLAST_CENTRES):
        bx, by = rng.uniform(-half * 0.95, half * 0.95, 2)
        r = rng.uniform(*BLAST_RADIUS_M)
        d += rng.uniform(*BLAST_STRENGTH) * np.exp(-((xx - bx) ** 2 + (yy - by) ** 2) / (2 * r * r))
    noise = ndi.gaussian_filter(rng.standard_normal((n, n)), NOISE_SCALE_M / DAMAGE_CELL_M, mode="wrap")
    noise = (noise - noise.mean()) / max(noise.std(), 1e-9)
    noise2 = ndi.gaussian_filter(rng.standard_normal((n, n)), NOISE_SCALE_M / DAMAGE_CELL_M / 3, mode="wrap")
    noise2 = (noise2 - noise2.mean()) / max(noise2.std(), 1e-9)
    d += NOISE_STRENGTH * (0.7 * noise + 0.3 * noise2) * 0.5 + NOISE_STRENGTH * 0.5
    return d


_DAMAGE = {}


def state_at(x, y, district, seed=23):
    """The ruin state of something centred on (x, y) in a district, from the
    damage map."""
    if seed not in _DAMAGE:
        _DAMAGE[seed] = damage_map(seed)
    dmg = _DAMAGE[seed]
    n = dmg.shape[0]
    half = MAP_M / 2
    i = int(np.clip((y + half) / DAMAGE_CELL_M, 0, n - 1))
    j = int(np.clip((x + half) / DAMAGE_CELL_M, 0, n - 1))
    jit = np.random.default_rng([seed, int((x + 100000) * 10), int((y + 100000) * 10)]).normal(0, JITTER)
    return int(np.searchsorted(STATE_LIMITS, dmg[i, j] * DISTRICT_SCALE[district] + jit, side="right"))


def assign_states(buildings, seed=23):
    """Sets every building's state from the damage map and its district."""
    for b in buildings:
        if b.opts.get("state") is not None:
            b.state = b.opts["state"]
            continue
        p = b.poly.centroid
        b.state = state_at(p.x, p.y, b.district, seed)
        if b.state == COLLAPSED and b.poly.area > BIG_MAX_COLLAPSED_M2:
            b.state = GUTTED
    return buildings


def noisy_disc(x, y, r, rng, n=14, rough=0.22):
    a = np.linspace(0, 2 * np.pi, n, endpoint=False)
    ph = rng.uniform(0, 2 * np.pi, 2)
    k = 1 + 0.14 * np.sin(2 * a + ph[0]) + 0.1 * np.sin(3 * a + ph[1]) + rng.uniform(-rough, rough, n) * 0.5
    return Polygon(np.stack([x + np.cos(a) * r * k, y + np.sin(a) * r * k], 1))


def points_on_ring(ring, n, rng):
    """n points spread along a ring, at random offsets."""
    length = ring.length
    if n <= 0 or length <= 0:
        return []
    start = rng.uniform(0, length)
    out = []
    for i in range(n):
        d = (start + length * (i + rng.uniform(0.2, 0.8)) / n) % length
        p = ring.interpolate(d)
        out.append((p.x, p.y))
    return out


def rubble_tris(xs, ys, sizes, rng):
    """Small rough quads (rubble pieces) as triangles, with a grey per piece."""
    m = len(xs)
    if m == 0:
        return np.zeros((0, 3, 2)), np.zeros((0, 3))
    ang = rng.uniform(0, np.pi, m)
    asp = rng.uniform(0.5, 1.0, m)
    hw, hh = sizes / 2, sizes * asp / 2
    corners = np.array([[-1, -1], [1, -1], [1, 1], [-1, 1]], float)
    jitter = rng.uniform(0.7, 1.15, (m, 4, 1))
    loc = corners[None] * np.stack([hw, hh], 1)[:, None, :] * jitter
    cs, sn = np.cos(ang)[:, None], np.sin(ang)[:, None]
    px = loc[..., 0] * cs - loc[..., 1] * sn + np.asarray(xs)[:, None]
    py = loc[..., 0] * sn + loc[..., 1] * cs + np.asarray(ys)[:, None]
    q = np.stack([px, py], -1)
    tris = np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]])
    grey = rng.uniform(*RUBBLE_V, m)
    vg = np.repeat(np.concatenate([grey, grey])[:, None], 3, 1)
    return tris, vg


def scatter(geom, count, rng):
    """Random points inside a polygon."""
    if geom.is_empty or count <= 0:
        return np.zeros((0, 2))
    x0, y0, x1, y1 = geom.bounds
    pts = rng.uniform((x0, y0), (x1, y1), (count * 3, 2))
    inside = shapely.contains_xy(geom, pts[:, 0], pts[:, 1])
    return pts[inside][:count]


def add_rubble(L, sub, geom, density, size, rng, chunk):
    """Rubble pieces over a polygon: density pieces per m2, sizes in m."""
    count = int(min(geom.area * density, RUBBLE_MAX))
    pts = scatter(geom, count, rng)
    if len(pts) == 0:
        return
    sizes = rng.uniform(size[0], size[1], len(pts))
    tris, vg = rubble_tris(pts[:, 0], pts[:, 1], sizes, rng)
    L.add_tris(sub, tris, 0.0, chunk=chunk, vg=vg)


def scorch(L, sub, x, y, r, rng, chunk, a=SCORCH_A):
    disc = noisy_disc(x, y, r * 0.55, rng, n=14)
    L.fill(sub, disc, 0.0, a, chunk=chunk)
    L.strip(sub, orient(disc, 1.0).exterior, r * 0.5, -1, a, 0.0, chunk=chunk)


def edge_holes(poly, rng):
    small = poly.area < 70
    n = int(np.clip(poly.exterior.length / 20.0, 1, 7))
    if small:
        n = 1
    holes = []
    for x, y in points_on_ring(poly.exterior, n, rng):
        r = rng.uniform(*HOLE_EDGE_R_M) * (0.7 if small else 1.0)
        holes.append((noisy_disc(x, y, r, rng), True))
    if poly.area > 90:
        c = poly.representative_point()
        r = HOLE_CENTRE_R_M * rng.uniform(0.8, 1.15)
        holes.append((noisy_disc(c.x + rng.uniform(-2, 2), c.y + rng.uniform(-2, 2), r, rng), False))
    return holes


def draw_ruined_roof(L, b, rng, roof_fn, big):
    poly = b.poly
    key = style.chunk_key(poly)
    if b.state == DAMAGED:
        holes = edge_holes(poly, rng)
        merged = unary_union([h for h, _ in holes])
        cut = merged.intersection(poly)
        L.roof_taken = [cut.buffer(0.4)]
        L.set_roof_clip(cut=cut)
        R = roof_fn(L, b, rng)
        L.set_roof_clip()
        L.roof_taken = []
        # One rim round the merged holes, so overlapping holes never draw
        # their edges across each other.
        L.line("roofs", merged.boundary.intersection(poly), 0.12, style.OUTLINE_V * 0.75, chunk=key)
        for h, on_edge in holes:
            hc = h.centroid
            for _ in range(int(rng.integers(1, 3))):
                a = rng.uniform(0, 2 * np.pi)
                r0 = h.exterior.distance(hc) if not h.is_empty else 1.0
                crack = LineString([(hc.x + np.cos(a) * r0, hc.y + np.sin(a) * r0),
                                    (hc.x + np.cos(a + rng.uniform(-0.3, 0.3)) * (r0 + rng.uniform(1.5, 3.5)),
                                     hc.y + np.sin(a + rng.uniform(-0.3, 0.3)) * (r0 + rng.uniform(1.5, 3.5)))])
                crack = crack.intersection(poly).difference(cut)
                L.line("roofs", crack, 0.08, 0.02, chunk=key)
            inside = h.intersection(poly)
            add_rubble(L, "interiors", inside, RUBBLE_HOLE, (0.35, 1.1), rng, key)
            if on_edge:
                spill = h.buffer(1.2).difference(poly.buffer(0.2))
                add_rubble(L, "groundlines", spill, RUBBLE_SPILL, (0.3, 0.9), rng, key)
        return R
    # Gutted.
    frags = []
    for x, y in points_on_ring(poly.exterior, 2, rng):
        r = rng.uniform(2.5, 5.0) * (1.5 if big else 1.0)
        frags.append(noisy_disc(x, y, r, rng, rough=0.4))
    keep = unary_union(frags).intersection(poly)
    L.set_roof_clip(keep=keep)
    roof_fn(L, b, rng)
    L.set_roof_clip()
    for f in style.polys(keep):
        L.line("roofs", f.exterior.difference(poly.exterior.buffer(0.05)), 0.1, style.OUTLINE_V * 0.7, chunk=key)
    wall_w = 0.55 if big else 0.4
    for seg in wall_segments(poly.exterior, rng):
        L.line("roofs", seg, wall_w, style.OUTLINE_V * 0.85, chunk=key)
    room = poly.buffer(-0.5)
    add_rubble(L, "interiors", room, RUBBLE_GUTTED[0], (0.4, 1.4), rng, key)
    for x, y in scatter(room, int(np.clip(poly.area / 60, 1, 6)), rng):
        scorch(L, "interiors", x, y, rng.uniform(2.0, 4.5), rng, key)
    ring = poly.buffer(1.6).difference(poly)
    add_rubble(L, "groundlines", ring, RUBBLE_GUTTED[1], (0.3, 1.0), rng, key)
    for x, y in points_on_ring(poly.exterior, int(np.clip(poly.exterior.length / 25, 1, 5)), rng):
        if rng.random() < 0.6:
            scorch(L, "groundlines", x, y, rng.uniform(2.0, 4.0), rng, key, a=SCORCH_A * 0.7)
    return None


def wall_segments(ring, rng):
    out = []
    d, length = 0.0, ring.length
    while d < length:
        seg = rng.uniform(*WALL_SEG_M)
        if rng.random() >= WALL_MISSING:
            out.append(substring(LineString(ring.coords), d, min(d + seg, length)))
        d += seg
    return out


def corners(poly, min_turn=0.5):
    pts = np.asarray(poly.exterior.coords)[:-1]
    out = []
    n = len(pts)
    for i in range(n):
        a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
        u, v = b - a, c - b
        lu, lv = np.hypot(*u), np.hypot(*v)
        if lu < 0.8 or lv < 0.8:
            continue
        cos = float(u @ v / (lu * lv))
        if cos < 1 - min_turn:
            out.append((b, -u / lu, v / lv))
    return out


def draw_collapsed(L, b, rng, salvage=None):
    poly = b.poly
    key = style.chunk_key(poly)
    big = b.poly.area > 600
    heap = poly.buffer(HEAP_GROW_M * rng.uniform(0.8, 1.2), join_style="round")
    bites = [noisy_disc(x, y, rng.uniform(0.8, 2.2), rng) for x, y in
             points_on_ring(heap.exterior, int(np.clip(heap.exterior.length / 6, 3, 30)), rng)]
    heap = heap.difference(unary_union(bites))
    if heap.geom_type != "Polygon":
        parts = style.polys(heap)
        heap = max(parts, key=lambda g: g.area) if parts else poly
    sub = "groundlines"
    L.strip(sub, orient(heap, 1.0).exterior, 1.4, -1, 0.35, 0.0, chunk=key)
    L.fill(sub, heap, HEAP_V, chunk=key)
    L.strip(sub, orient(heap, 1.0).exterior, 1.2, +1, 0.3, 0.0, chunk=key)
    add_rubble(L, sub, heap, RUBBLE_HEAP[0], (0.4, 1.3), rng, key)
    # Roof slabs: the footprint cut into pieces, each shifted and turned a
    # little, with cracks.
    v = style.roof_value(b.mv)
    ang, c = style.frame_of(poly)
    shrunk = poly.buffer(-0.6, join_style="mitre")
    if not shrunk.is_empty:
        for s in collapsed_slabs(shrunk, ang, c, rng):
            L.strip(sub, orient(style.polys(s)[0], 1.0).exterior, 0.7, -1, 0.5, 0.0, chunk=key)
            L.fill(sub, s, v * rng.uniform(1.0, 1.5), chunk=key)
            for g in style.polys(s):
                L.line(sub, LinearRing(g.exterior.coords), 0.14, style.OUTLINE_V * 0.55, chunk=key)
                cs = g.centroid
                for _ in range(int(rng.integers(1, 3))):
                    a = rng.uniform(0, np.pi)
                    r = np.sqrt(g.area)
                    crack = LineString([(cs.x - np.cos(a) * r, cs.y - np.sin(a) * r),
                                        (cs.x + rng.uniform(-0.5, 0.5), cs.y + rng.uniform(-0.5, 0.5)),
                                        (cs.x + np.cos(a + 0.4) * r, cs.y + np.sin(a + 0.4) * r)])
                    L.line(sub, crack.intersection(g), 0.09, 0.02, chunk=key)
    add_rubble(L, sub, heap.buffer(-0.4), RUBBLE_HEAP[1], (0.25, 0.8), rng, key)
    for corner, back, fwd in corners(poly):
        if rng.random() > STUB_CORNERS:
            continue
        la, lb = rng.uniform(0.8, 2.4), rng.uniform(0.8, 2.4)
        stub = LineString([corner + back * la, corner, corner + fwd * lb])
        L.line(sub, stub, 0.5 if big else 0.38, style.OUTLINE_V * 0.8, chunk=key)
    if salvage is not None and rng.random() < RUBBLE_SOURCE_CHANCE:
        p = poly.representative_point()
        salvage.add("rubble", p.x, p.y, np.radians(ang), 3.0, 3.0, building=-1)


def cut_slabs(poly, n, ang, c, rng):
    """Cuts a polygon into about n pieces with lines across its long axis
    (no piece narrower than SLAB_MIN_M or SLAB_MIN_SHARE of the length) and,
    when it is wide enough, one along it."""
    loc = affinity.rotate(poly, -ang, origin=c)
    x0, y0, x1, y1 = loc.bounds
    least = max(SLAB_MIN_M, SLAB_MIN_SHARE * (x1 - x0))
    k = int(min(max(1, n - 2), (x1 - x0) // least - 1))
    xs = [x0 - 1]
    if k > 0:
        # k cuts, each at least `least` from the ends and from each other.
        free = (x1 - x0) - (k + 1) * least
        gaps = np.sort(rng.uniform(0, free, k))
        xs += [x0 + least * (i + 1) + g for i, g in enumerate(gaps)]
    xs.append(x1 + 1)
    split = (y1 - y0) >= 2 * SLAB_MIN_M + 1.0
    ym = rng.uniform(y0 + (y1 - y0) * 0.35, y0 + (y1 - y0) * 0.65)
    out = []
    for xa, xb in zip(xs[:-1], xs[1:]):
        rows = ((y0 - 1, ym), (ym, y1 + 1)) if split else ((y0 - 1, y1 + 1),)
        for ya, yb in rows:
            if split and rng.random() < 0.35 and (ya, yb) == (ym, y1 + 1):
                continue
            piece = loc.intersection(box(xa, ya, xb, yb))
            for g in style.polys(piece):
                if g.area > 2.0:
                    out.append(affinity.rotate(g, ang, origin=c))
    return out


def collapsed_slabs(poly, ang, c, rng):
    """The roof slabs of a collapsed building over poly (its footprint, a
    little shrunk): cut_slabs, each turned and pushed a little (its ends
    move at most SLAB_TURN_M), then kept inside poly and SLAB_GAP_M off the
    slabs before it."""
    out = []
    taken = None
    for s in cut_slabs(poly, int(rng.integers(3, 6)), ang, c, rng):
        half = max(s.minimum_rotated_rectangle.length / 4.0, 1.0)
        turn = np.degrees(np.arcsin(min(1.0, SLAB_TURN_M / half)))
        s = affinity.rotate(s, rng.uniform(-turn, turn), origin=s.centroid)
        s = affinity.translate(s, rng.uniform(-SLAB_PUSH_M, SLAB_PUSH_M), rng.uniform(-SLAB_PUSH_M, SLAB_PUSH_M))
        s = s.intersection(poly)
        if taken is not None:
            s = s.difference(taken.buffer(SLAB_GAP_M))
        s = s.buffer(-0.25, join_style="mitre")
        parts = [g for g in style.polys(s) if g.area > 2.0]
        if not parts:
            continue
        s = unary_union(parts)
        out.append(s)
        taken = s if taken is None else taken.union(s)
    return out
