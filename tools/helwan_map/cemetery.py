"""The two cemeteries, at the two OSM landuse=cemetery areas in the play area
(CEMETERIES). A Cairo cemetery is a dense town of walled family plots
(hosh): rows of walled tomb enclosures with small domed tomb rooms inside,
cenotaphs, a few large domed mausoleums, narrow lanes and a perimeter wall
with gates.

Land: the OSM area less the roads (grown by ROAD_SETBACK_M), water, claims,
KeepOut areas and the markers' circles, from the whole map's layout, so a
window run lays it out as the full run does. An area larger than its
max_m2 keeps its largest pieces up to that size. The OSM roads inside (the
cemetery's own service lanes) stay, with no parked cars, traffic or
junction wrecks (their concrete inside the landmark's outline is in
props.ROAD_KEEP_OFF); each piece between them is laid out on its own,
PLOT_SETBACK_M in from the roads, so a service lane is a mecha-wide
street. Lanes inside are 10 to 16 m wide, avenues 16 to 20 m:

  streets   straight lanes across a long piece (STREET_EVERY_M apart); in
            each cemetery's largest piece the middle one is an avenue
  bands     along the piece's long axis, the arrangement of bands that
            puts the most ground under plots: two rows back to back (ROW_M
            deep each), or one row at an edge where that fits better, with
            lanes (LANE_M) between them; in the largest piece, when three or
            more bands wide, the middle lane is a second avenue, crossing
            the first
  blocks    cross lanes (CROSS_M) cut each band into blocks (BLOCK_M long),
            placed afresh in every band, so they meet the lanes at
            T-junctions and offsets; some open one row only (dead-end
            niches); a block may sit up to JOG_M off its band's line (crooks
            in the lanes either side)
  plots     each row split into plots PLOT_W_M wide (some wider, some
            through both rows), clipped to the piece
  plugs     now and then a plot across a lane between two of its openings:
            a dead end on each side, each with a way out
  fill      ground still a lane's width from every plot (wedges, the ends
            of bands the outline cut short) gets bands of its own
  mausoleums MAUSOLEUMS_PER_HA large domed tombs (ordinary roofed
            buildings, with ruin states) at block ends, the avenues' first
  graves    land GRAVE_FIELD_CLEAR_M or more from every plot (between
            service lanes too close together for walled plots and
            mecha-wide lanes) is open burial ground: rows of simple graves,
            drawn only

Each plot is a building of kind "hosh" pinned to the gutted state: its
whole outline is a wall that blocks sight and shots, a mecha in it is not
"inside" (no camera zoom), and it draws itself as an open-topped walled
enclosure (draw_plot): ground, cenotaphs, a small domed tomb room, the walls
with a gate on the side that faces a lane. Some plots where the damage map
says collapsed (COLLAPSED_AT_MAP), and a few by chance, are collapsed
instead: wall stubs and rubble, no wall in the game, and sometimes a rubble
salvage source. Half the plots where it says gutted are damaged: they keep
their wall in the game, and their breaches are drawn as wall fallen into a
heap along its line, so the outline still reads closed.

The perimeter wall (drawn only, as the farm yards' and military compounds'
walls) runs where a piece faces the outside of the cemetery, with a gate
at each lane mouth. Bare trees stand along the lanes and in some plots.
The landmark's outline is the kept land with the lanes between its pieces
closed (landmark_outline).
"""
import numpy as np
from shapely import contains_xy, prepare
from shapely.geometry import LineString, Point, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import substring, unary_union
from shapely.strtree import STRtree

import buildings as bl
import civickit as ck
import kit
import props
import ruins
import style
from gen_city import min_width, rect_fill, to_frame_m

## (OSM centre near which the landuse=cemetery area is, landmark name,
## largest area kept m2).
CEMETERIES = (
    ((1877.0, 877.0), "the East Cemetery", "east_cemetery", 100000.0),
    ((-940.0, 341.0), "the West Cemetery", "west_cemetery", 105000.0),
)
PLOT_SETBACK_M = 2.5
LANE_M = (10.5, 14.5)
AVENUE_M = (16.0, 20.0)
CROSS_M = (10.0, 13.0)
## Straight lanes across a long piece.
STREET_EVERY_M = (75.0, 120.0)
ROW_M = (9.0, 13.5)
## Blocks along a band, between its cross lanes; share of the cross lanes of
## a two-row band that open one row only.
BLOCK_M = (35.0, 80.0)
HALF_CUT = 0.3
## Blocks moved off their band's line, by up to JOG_M, keeping every lane
## 10 to 16 m wide.
JOG_CHANCE = 0.5
JOG_M = 2.5
PLOT_W_M = (7.5, 15.5)
WIDE_PLOT_M = (16.0, 26.0)
WIDE_PLOT_CHANCE = 0.1
## Top-row plots of a two-row band that run through both rows.
DEEP_PLOT_CHANCE = 0.12
## Plots across a lane: their width, the least distance from an opening,
## and the chance for each stretch of lane between two openings.
PLUG_W_M = (8.0, 12.0)
PLUG_CLEAR_M = 4.0
PLUG_CHANCE = 0.3
PLOT_GAP_CHANCE = 0.25
MIN_PLOT_M2 = 60.0
MAX_PLOT_M2 = 400.0
## Large domed tombs per hectare of cemetery land, and their side (m).
MAUSOLEUMS_PER_HA = 0.5
MAUSOLEUM_M = (11.0, 15.5)
## Look of the plots: collapsed and damaged by chance on top of the damage
## map.
COLLAPSED_CHANCE = 0.04
DAMAGED_CHANCE = 0.1
## Share of the plots where the damage map says collapsed that are
## collapsed (the rest are damaged): the walls are what makes the
## cemetery, so most stand.
COLLAPSED_AT_MAP = 0.45
## Share of the plots where it says gutted (or worse, when not collapsed)
## that show breaches.
DAMAGED_AT_MAP = 0.5
RUBBLE_SOURCE_CHANCE = 0.35
TOMB_ROOM_CHANCE = 0.55
PLOT_TREE_CHANCE = 0.12
## Open burial ground where the land is this far (m) from every plot; share
## of its grave spots left empty and of its graves broken.
GRAVE_FIELD_CLEAR_M = 7.0
GRAVE_GAP = 0.2
GRAVE_BROKEN = 0.15
## How wide a gap between the kept pieces the landmark's outline closes (m,
## half).
LANDMARK_CLOSE_M = 15.0
## Lane ground (m2) per bare tree.
LANE_TREE_M2 = 700.0
## How far (m) rubble spills out of a plot: the plots and tombs this near are
## kept clear of it.
SPILL_M = 4.0


# ------------------------------------------------------------------ drawing

def roof_mausoleum(L, b, rng):
    """A square tomb chamber: flat roof with a crenellated parapet and one
    large dome (ribbed or plain), sometimes with small corner domes."""
    g = b.poly
    v = style.roof_value(b.mv) * rng.uniform(1.1, 1.4)
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    inner = style.set_inner(R, g, 0.5)
    R.shade_in(inner, 0.9, 0.35)
    R.ring(inner, style.PARAPET_W, style.PARAPET_V)
    ck.crenellations(L, "roofs", inner, min(v * 2.6, 0.32), R.key, step=1.0, size=0.38)
    c = g.centroid
    side = min(R.x1 - R.x0, R.y1 - R.y0)
    ribs = int(rng.choice([0, 0, 16, 24]))
    if rng.random() < 0.35 and side > 12.5:
        r_small = side * 0.11
        for sx in (-1, 1):
            for sy in (-1, 1):
                x, y = R.rect(sx * side * 0.33 - 0.01, sy * side * 0.33 - 0.01, sx * side * 0.33,
                              sy * side * 0.33).centroid.coords[0]
                ck.dome(L, "roofs", x, y, r_small, min(v * 2.2, 0.3), R.key, steps=2, n=10)
        ck.dome(L, "roofs", c.x, c.y, side * 0.27, min(v * 2.6, 0.34), R.key, ribs=ribs)
    else:
        ck.dome(L, "roofs", c.x, c.y, side * 0.36, min(v * 2.6, 0.34), R.key, ribs=ribs)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return None


bl.KINDS["mausoleum"] = (roof_mausoleum, False, style.HALO_HOUSE_M)


def tomb_room(L, x, y, size, ang, v, rng, key, broken=False):
    """A small domed tomb room (drawn only): a square with its shadow, a
    dome, or a broken dome with rubble."""
    sq = ck.square(x, y, size, ang)
    L.fill("interiors", sq.buffer(0.5, join_style="mitre"), 0.0, 0.35, chunk=key)
    L.fill("interiors", sq, v, chunk=key)
    L.line("interiors", sq.exterior, 0.18, min(v * 2.0, 0.42), 0.9, chunk=key)
    if broken:
        L.fill("interiors", ck.ngon(x, y, size * 0.32, 9, rng.uniform(0, 1)), 0.02, chunk=key)
        ruins.add_rubble(L, "interiors", sq, 0.5, (0.25, 0.7), rng, key)
    else:
        ck.dome(L, "interiors", x, y, size * 0.38, min(v * 1.5, 0.36), key, steps=3, n=12, drum=False)


def cenotaphs(L, poly, avoid, ang, rng, key, broken=False):
    """Rows of cenotaphs (light stone blocks with a headstone at one end)
    inside a plot, clear of avoid."""
    F = ck.Local(poly.centroid.x, poly.centroid.y, ang)
    lx = [F.to_local(x, y) for x, y in poly.exterior.coords]
    x0, x1 = min(p[0] for p in lx) + 1.2, max(p[0] for p in lx) - 1.2
    y0, y1 = min(p[1] for p in lx) + 1.2, max(p[1] for p in lx) - 1.2
    n = int(np.clip(poly.area / 22.0, 1, 9))
    room = poly.buffer(-0.8)
    Q = F.quads()
    made = 0
    for _ in range(n * 3):
        if made >= n or x1 - x0 < 1.0 or y1 - y0 < 2.4:
            break
        w, h = rng.uniform(0.7, 1.0), rng.uniform(1.9, 2.4)
        x = rng.uniform(x0, x1 - w)
        y = rng.uniform(y0, y1 - h)
        r = F.rect(x - 0.3, y - 0.3, x + w + 0.3, y + h + 0.3)
        if not room.contains(r) or any(r.intersects(a) for a in avoid):
            continue
        avoid.append(r)
        made += 1
        if broken and rng.random() < 0.5:
            Q.rect(x, y, x + w, y + h * rng.uniform(0.4, 0.7), rng.uniform(0.2, 0.28))
            continue
        Q.rect(x + 0.15, y + 0.15, x + w + 0.25, y + h + 0.25, 0.0, 0.4)
        Q.rect(x, y, x + w, y + h, rng.uniform(0.28, 0.36))
        Q.rect(x + 0.1, y + 0.12, x + w - 0.1, y + h - 0.12, rng.uniform(0.22, 0.3))
        hy = y if rng.random() < 0.5 else y + h - 0.22
        Q.rect(x - 0.05, hy, x + w + 0.05, hy + 0.22, 0.42)
    Q.flush(L, "interiors", key)


def plot_wall(L, poly, gate, v, key, rng, breaches=(), width=0.55, clip=None):
    """The plot's wall on its outline: a soft shadow on both sides, the
    wall top and a coping line, with a gate gap (and piers). At a breach
    the wall has fallen into a heap of rubble along its line, so the
    outline still reads closed, as the plot's wall in the game is (gutted,
    not collapsed); the heap stays off clip (the neighbouring plots)."""
    ring = orient(poly, 1.0).exterior
    L.strip("interiors", ring, 0.9, +1, 0.45, 0.0, chunk=key)
    line = LineString(ring.coords)
    holes = []
    for x, y, w in breaches:
        d = line.project(Point(x, y))
        holes.append((d - w / 2, d + w / 2))
    cuts = list(holes)
    if gate is not None:
        d = line.project(Point(gate[0], gate[1]))
        cuts.append((d - 0.9, d + 0.9))
    parts = ck.cut_ring(line, cuts)[0] if cuts else [line]
    for part in parts:
        L.line("interiors", part, width + 0.5, 0.0, 0.4, chunk=key)
        L.line("interiors", part, width, v, chunk=key)
        L.line("interiors", part, 0.07, min(v * 1.45, 0.5), 0.8, chunk=key)
    for seg in ck.cut_ring(line, holes)[1] if holes else []:
        heap = seg.buffer(width * 1.4)
        if clip is not None:
            heap = heap.difference(clip)
        L.fill("interiors", heap, ruins.HEAP_V, 0.9, chunk=key)
        ruins.add_rubble(L, "interiors", heap, 0.45, (0.25, 0.7), rng, key)
    if gate is not None:
        d = line.project(Point(gate[0], gate[1]))
        for dd in (d - 0.9, d + 0.9):
            p, _ = ck.point_along(line, dd)
            L.fill("interiors", ck.square(p.x, p.y, width * 1.9, gate[2]), min(v * 1.3, 0.5), chunk=key)


def draw_plot(L, b, rng, salvage):
    """A hosh: an open-topped walled enclosure drawn whole (halo, ground,
    tomb room, cenotaphs, walls), or its collapsed remains. Rubble spilling
    out of it keeps off the plots and tombs beside it (opts "clip")."""
    poly = b.poly
    key = style.chunk_key(poly)
    o = b.opts
    ang = o.get("ang", 0.0)
    look = o.get("look", "ok")
    gate = o.get("gate")
    clip = o.get("clip")
    wall_v = rng.uniform(0.25, 0.33)
    room = o.get("room")
    if look == "collapsed":
        ground = rng.uniform(0.1, 0.13)
        L.fill("interiors", poly, ground, chunk=key)
        heap = poly.buffer(0.8).difference(poly.buffer(-1.6))
        spread = poly.buffer(1.2)
        if clip is not None:
            heap, spread = heap.difference(clip), spread.difference(clip)
        L.fill("groundlines", spread, ruins.HEAP_V, 0.6, chunk=key)
        ruins.add_rubble(L, "groundlines", heap, 0.25, (0.3, 1.0), rng, key)
        ruins.add_rubble(L, "interiors", poly.buffer(-0.5), 0.06, (0.3, 1.1), rng, key)
        for seg in ruins.wall_segments(orient(poly, 1.0).exterior, rng):
            if rng.random() < 0.55:
                continue
            L.line("interiors", seg, 0.85, 0.0, 0.35, chunk=key)
            L.line("interiors", seg, 0.5, wall_v * 0.9, chunk=key)
        if room is not None:
            x, y, s = room
            L.fill("interiors", ruins.noisy_disc(x, y, s * 0.7, rng), ruins.HEAP_V * 1.2, chunk=key)
            ruins.add_rubble(L, "interiors", ck.square(x, y, s * 1.2, ang), 0.6, (0.3, 0.9), rng, key)
        cenotaphs(L, poly, [], ang, rng, key, broken=True)
        if salvage is not None and rng.random() < RUBBLE_SOURCE_CHANCE:
            p = poly.representative_point()
            salvage.add("rubble", p.x, p.y, ang, 3.0, 3.0, building=-1)
        return
    style.draw_halo(L, poly, 1.3)
    paved = rng.random() < 0.3
    L.fill("interiors", poly, rng.uniform(0.15, 0.19) if paved else rng.uniform(0.09, 0.13), chunk=key)
    if paved:
        F = ck.Local(poly.centroid.x, poly.centroid.y, ang)
        Q = F.quads()
        lx = [F.to_local(x, y) for x, y in poly.exterior.coords]
        xa, xb = min(p[0] for p in lx), max(p[0] for p in lx)
        ya, yb = min(p[1] for p in lx), max(p[1] for p in lx)
        for xx in np.arange(xa + 1.5, xb, 1.5):
            Q.line(xx, ya, xx, yb, 0.05, 0.08, 0.5)
        Q.flush(L, "interiors", key)
    avoid = []
    if gate is not None:
        avoid.append(Point(gate[0], gate[1]).buffer(2.5))
    if room is not None:
        x, y, s = room
        avoid.append(ck.square(x, y, s + 0.8, ang))
        tomb_room(L, x, y, s, ang, rng.uniform(0.17, 0.24), rng, key, broken=look == "damaged" and rng.random() < 0.5)
    cenotaphs(L, poly, avoid, ang, rng, key)
    breaches = []
    if look == "damaged":
        ring = poly.exterior
        for _ in range(int(rng.integers(1, 3))):
            p = ring.interpolate(rng.uniform(0, ring.length))
            w = rng.uniform(2.0, 4.5)
            breaches.append((p.x, p.y, w))
            spill = p.buffer(w * 0.8)
            out = spill.difference(poly) if clip is None else spill.difference(poly).difference(clip)
            ruins.add_rubble(L, "groundlines", out, 0.35, (0.25, 0.9), rng, key)
            ruins.add_rubble(L, "interiors", spill.intersection(poly.buffer(-0.3)), 0.35, (0.25, 0.9), rng, key)
        if rng.random() < 0.4:
            # A scorch mark reaches about 1.1 times its size from its point,
            # so its size is capped to stay inside the plot's wall.
            p = poly.representative_point()
            size = min(rng.uniform(2.0, 3.5), poly.exterior.distance(p) / 1.15)
            if size >= 1.0:
                ruins.scorch(L, "interiors", p.x, p.y, size, rng, key)
    plot_wall(L, poly, gate, wall_v, key, rng, breaches, clip=clip)


bl.KINDS["hosh"] = (None, False, 1.3, draw_plot)


# ------------------------------------------------------------------- layout

def cemetery_polys(site):
    """The OSM cemetery areas in map metres, matched to CEMETERIES."""
    found = []
    for kind, rings, p in site.feats or []:
        if kind == "poly" and p.get("landuse") == "cemetery":
            g = Polygon(to_frame_m(rings[0])).buffer(0)
            if not g.is_empty:
                found.append(g)
    out = []
    for (cx, cy), name, tag, max_m2 in CEMETERIES:
        best = min(found, key=lambda g: g.centroid.distance(Point(cx, cy)), default=None)
        if best is not None and best.centroid.distance(Point(cx, cy)) < 200:
            out.append((best, name, tag, max_m2))
    return out


def split_row(xa, xb, rng):
    """Column edges along a row: widths PLOT_W_M (now and then a wide plot,
    WIDE_PLOT_M), the last short piece joined to the one before, and now and
    then a narrow gap."""
    cols = []
    x = xa
    while xb - x >= PLOT_W_M[0]:
        w = rng.uniform(*WIDE_PLOT_M) if rng.random() < WIDE_PLOT_CHANCE else rng.uniform(*PLOT_W_M)
        if xb - (x + w) < PLOT_W_M[0]:
            w = xb - x
        cols.append((x, x + w))
        x += w
        if rng.random() < PLOT_GAP_CHANCE:
            x += rng.uniform(1.0, 2.0)
    return cols


def clean_plot(g):
    """A plot outline without the thin spikes and back-tracking edges that
    clipping leaves (they turn into self-crossings once the outline is
    written in float32 pixels), or None."""
    if g is None or g.is_empty:
        return None
    h = kit.largest(g.buffer(-0.1, join_style="mitre").buffer(0.1, join_style="mitre"))
    if h is None:
        return None
    h = h.simplify(0.1)
    px = np.round(np.asarray(h.exterior.coords) * 20.0).astype(np.float32) / 20.0
    h = Polygon(px)
    if not h.is_valid:
        h = kit.largest(h.buffer(0))
    return h


def good_plot(g):
    return g is not None and g.area >= MIN_PLOT_M2 and min_width(g) >= 5.0 and rect_fill(g) >= 0.55


class Taken:
    """Plots placed so far, with a bounding-box test before the exact one."""

    def __init__(self):
        self.items = []

    def add(self, g):
        self.items.append((g.bounds, g))

    def cut(self, g, margin=0.0):
        x0, y0, x1, y1 = g.bounds
        for (a0, b0, a1, b1), t in self.items:
            if a0 > x1 + margin or a1 < x0 - margin or b0 > y1 + margin or b1 < y0 - margin:
                continue
            if t.intersects(g):
                g = g.difference(t.buffer(margin, join_style="mitre") if margin else t)
                if g.is_empty:
                    return g
        return g


def band_plan(h, rng, avenue=False):
    """Splits the width h (m) of a piece across its long axis into bands of
    plots and the lanes between them, from y = 0: ([(y0, [row depths])],
    [(y0, y1, wide)]). Of the arrangements that fit (bands two rows deep,
    or one row deep at an edge), the one that puts the most of h under
    plots, then the one with more bands; lanes near the narrow end of
    LANE_M, rows as deep as fit (ROW_M); in an avenue piece three or more
    bands wide the middle lane is AVENUE_M wide."""
    flip = rng.random() < 0.5
    best = None
    for n in range(1, int(h / (ROW_M[0] + LANE_M[0])) + 3):
        for k in (0, 1, 2):
            if k > n or (k == 2 and n < 2):
                continue
            single = [False] * n
            if k == 1:
                single[-1 if flip else 0] = True
            elif k == 2:
                single[0] = single[-1] = True
            wide = (n - 1) // 2 if avenue and n >= 3 else -1
            n_rows = sum(1 if s else 2 for s in single)
            lanes = [AVENUE_M if i == wide else LANE_M for i in range(n - 1)]
            lo = n_rows * ROW_M[0] + sum(a for a, _ in lanes)
            hi = n_rows * ROW_M[1] + sum(b for _, b in lanes)
            if not lo <= h <= hi:
                continue
            share = min(n_rows * ROW_M[1], h - sum(a for a, _ in lanes)) / h
            key = (round(share, 3), n)
            if best is None or key > best[0]:
                best = (key, single, wide, lanes)
    if best is None:
        if h < 7.0:
            return [], []
        return [(0.0, [h / 2, h / 2] if h >= 14.0 else [h])], []
    _, single, wide, lanes = best
    lw = [a + (b - a) * rng.uniform(0.0, 0.35) for a, b in lanes]
    weights = rng.uniform(0.85, 1.15, sum(1 if s else 2 for s in single))
    rows = np.clip((h - sum(lw)) * weights / weights.sum(), *ROW_M)
    # What the rows cannot take (or must give back) goes to the lanes, in
    # proportion to their room; with no lanes the rows split h evenly.
    left = h - sum(lw) - float(rows.sum())
    room = [(b - w) if left > 0 else (w - a) for w, (a, b) in zip(lw, lanes)]
    if abs(left) > 1e-6:
        if sum(room) > 1e-9:
            lw = [w + left * r / sum(room) for w, r in zip(lw, room)]
        else:
            rows = np.full(len(rows), (h - sum(lw)) / len(rows))
    bands, out_lanes, y, i = [], [], 0.0, 0
    for k, one in enumerate(single):
        rr = [float(d) for d in rows[i:i + (1 if one else 2)]]
        i += len(rr)
        bands.append((y, rr))
        y += sum(rr)
        if k < len(single) - 1:
            out_lanes.append((y, y + lw[k], k == wide))
            y += lw[k]
    return bands, out_lanes


def band_cuts(xa, xb, n_rows, rng, fixed=()):
    """Cross lanes through a band running from x = xa to xb: [(x0, x1, rows
    cut)]. fixed: the x ranges of the streets across the piece, which cut
    every row; between them cross lanes BLOCK_M apart, most opening every
    row, HALF_CUT of a two-row band's opening one row only (a dead-end niche
    off the lane on that side)."""
    every = set(range(n_rows))
    cuts = [(a, b, every) for a, b in sorted(fixed) if b > xa and a < xb]
    ends = [xa] + [v for a, b, _ in cuts for v in (a, b)] + [xb]
    for s0, s1 in zip(ends[0::2], ends[1::2]):
        x = s0 + rng.uniform(BLOCK_M[0] * 0.6, BLOCK_M[1])
        while x < s1 - BLOCK_M[0] * 0.6:
            w = rng.uniform(*CROSS_M)
            rows = every
            if n_rows == 2 and rng.random() < HALF_CUT:
                rows = {int(rng.integers(2))}
            cuts.append((x, x + w, rows))
            x += w + rng.uniform(*BLOCK_M)
    return sorted(cuts, key=lambda c: c[0])


def jog_room(lane, wider):
    """How far (m) a block may move into a lane (narrowing it) or away from
    it (widening it), sharing the change with the block across the lane."""
    if lane is None:
        return 0.0 if not wider else np.inf
    lo, hi = AVENUE_M if lane[2] else (10.0, 16.0)
    w = lane[1] - lane[0]
    return max(0.0, (hi - w) / 2 if wider else (w - lo) / 2)


def streets(piece, inner, F, rng, avenue):
    """Straight lanes across a long piece (STREET_EVERY_M apart, CROSS_M
    wide; the middle one AVENUE_M wide in the cemetery's largest piece)."""
    out = []
    span = F.x1 - F.x0
    if span < 2 * STREET_EVERY_M[0]:
        if avenue and span > 60.0:
            w = rng.uniform(*AVENUE_M)
            out.append((F.rect(-w / 2, F.y0 - 5, w / 2, F.y1 + 5), True))
        return out
    n = max(1, int(round(span / rng.uniform(*STREET_EVERY_M))) - 1)
    mid = n // 2
    for i in range(n):
        x = F.x0 + span * (i + 1) / (n + 1) + rng.uniform(-8, 8)
        wide = avenue and i == mid
        w = rng.uniform(*AVENUE_M) if wide else rng.uniform(*CROSS_M)
        out.append((F.rect(x - w / 2, F.y0 - 5, x + w / 2, F.y1 + 5), wide))
    return out


class Band:
    """One band of plots in a piece (local frame F, x along the piece): its
    top edge y0 and row depths, the lanes above and below it (or None), its
    cross lanes and its blocks [(x0, x1, jog)] between the full cuts."""

    def __init__(self, y0, rows, above, below):
        self.y0, self.rows, self.above, self.below = y0, rows, above, below
        self.y1 = y0 + sum(rows)
        self.cuts, self.blocks = [], []

    def jog_at(self, x):
        for x0, x1, s in self.blocks:
            if x0 <= x <= x1:
                return s
        return 0.0

    def openings(self, row):
        """The x ranges where this band's row is open to its lane."""
        return [(a, b) for a, b, rows in self.cuts if row in rows]


def plan_piece(avail, F, prng, avenue, street_x):
    """The bands of one piece: rows along its long axis (F's x), cut into
    blocks (by cross lanes and by the streets across the piece, street_x)
    that jog a little off the band's line."""
    lx0, ly0, lx1, ly1 = F.local(avail).bounds
    plan, lanes = band_plan(ly1 - ly0, prng, avenue)
    lanes = [(ly0 + a, ly0 + b, w) for a, b, w in lanes]
    out = []
    for i, (y, rows) in enumerate(plan):
        above = lanes[i - 1] if i > 0 else None
        below = lanes[i] if i < len(lanes) else None
        band = Band(ly0 + y, rows, above, below)
        part = F.rect(lx0 - 5.0, band.y0, lx1 + 5.0, band.y1).intersection(avail)
        if part.is_empty:
            out.append(band)
            continue
        bx0, _, bx1, _ = F.local(part).bounds
        band.cuts = band_cuts(bx0, bx1, len(rows), prng, street_x)
        edges = [bx0 - 1.0] + [v for a, b, r in band.cuts if len(r) == len(rows) for v in (a, b)] + [bx1 + 1.0]
        for a, b in zip(edges[0::2], edges[1::2]):
            s = 0.0
            if prng.random() < JOG_CHANCE:
                down = min(jog_room(below, False), jog_room(above, True))
                up = min(jog_room(above, False), jog_room(below, True))
                s = prng.uniform(-min(up, JOG_M), min(down, JOG_M))
            band.blocks.append((a, b, s))
        out.append(band)
    return out, lanes


def add_plot(rect, avail, taken, out, ang, face):
    g = kit.largest(taken.cut(rect.intersection(avail)))
    if not good_plot(g):
        return None
    g = clean_plot(g)
    if not good_plot(g):
        return None
    taken.add(g)
    c = g.centroid
    out.append((g, ck.Local(c.x, c.y, ang), face))
    return g


def band_plots(band, n_bands, k, avail, F, prng, taken, out):
    """The plots of one band, block by block and row by row: each row split
    into plots PLOT_W_M wide; in a two-row band some top-row plots run
    through both rows (DEEP_PLOT_CHANCE). Rows face their lanes: the top row
    of a two-row band up, the bottom row down; a one-row band faces the
    lane beside it."""
    two = len(band.rows) == 2
    for bx0, bx1, s in band.blocks:
        ys = [band.y0 + s]
        for d in band.rows:
            ys.append(ys[-1] + d)
        for r in range(len(band.rows)):
            if two:
                face = -1 if r == 0 else 1
            else:
                face = 1 if (k == 0 and n_bands > 1) else -1
            cut = sorted((a, b) for a, b, rows in band.cuts if r in rows and a < bx1 and b > bx0)
            segs, x = [], bx0
            for a, b in cut:
                if a > x:
                    segs.append((x, a))
                x = max(x, b)
            if bx1 > x:
                segs.append((x, bx1))
            for sa, sb in segs:
                for c0, c1 in split_row(sa, sb, prng):
                    y1 = ys[r + 1]
                    deep = (two and r == 0 and prng.random() < DEEP_PLOT_CHANCE
                            and not any(a < c1 and b > c0 for a, b, rows in band.cuts if 1 in rows))
                    if deep:
                        y1 = ys[2]
                    add_plot(F.rect(c0, ys[r], c1, y1), avail, taken, out, F.rad,
                             face if not deep else (-1 if prng.random() < 0.5 else 1))


def lane_plugs(a, b, lane, avail, F, prng, taken, out):
    """Plots across the lane between bands a and b (a dead end on each
    side): at most one between two openings into the lane (a cross lane or
    a street meeting it), so each side keeps a way out, and only by chance
    (PLUG_CHANCE)."""
    opens = a.openings(len(a.rows) - 1) + b.openings(0)
    mid = F.rect(-1e4, lane[0] + 1.0, 1e4, lane[1] - 1.0).intersection(avail)
    if mid.is_empty:
        return
    mx0, _, mx1, _ = F.local(mid).bounds
    opens = sorted((max(x0, mx0), min(x1, mx1)) for x0, x1 in opens if x1 > mx0 and x0 < mx1)
    for (_, e0), (s1, _) in zip(opens[:-1], opens[1:]):
        pw = prng.uniform(*PLUG_W_M)
        if s1 - e0 < pw + 2 * PLUG_CLEAR_M or prng.random() >= PLUG_CHANCE:
            continue
        px = prng.uniform(e0 + PLUG_CLEAR_M, s1 - PLUG_CLEAR_M - pw)
        xm = px + pw / 2
        rect = F.rect(px, a.y1 + a.jog_at(xm), px + pw, b.y0 + b.jog_at(xm))
        add_plot(rect, avail, taken, out, F.rad, -1 if prng.random() < 0.5 else 1)


def mausoleum_spots(pieces_bands, avenues, rng_of):
    """Squares for large tombs at the ends of the two-row blocks, on the
    band's top or bottom edge: [(not on an avenue, random, square)]."""
    spots = []
    for (F, avail, bands), prng in zip(pieces_bands, rng_of):
        for band in bands:
            if len(band.rows) != 2:
                continue
            side = prng.uniform(*MAUSOLEUM_M)
            if band.y1 - band.y0 < side + 2.0:
                continue
            for bx0, bx1, s in band.blocks:
                if bx1 - bx0 < side + 10.0:
                    continue
                for xs in (bx0 + 0.5, bx1 - 0.5 - side):
                    for ys in (band.y0 + s, band.y1 + s - side):
                        sq = F.rect(xs, ys, xs + side, ys + side)
                        if not avail.contains(sq):
                            continue
                        if any(a < xs + side and b > xs for a, b, _ in band.cuts):
                            continue
                        on_avenue = any(sq.distance(a) < 3.0 for a in avenues)
                        spots.append((not on_avenue, prng.random(), sq))
    return spots


def layout(cem, kept, blocked, rng):
    """Plots, mausoleums and lanes of one cemetery (its kept pieces).
    Returns (plots as (polygon, frame, face), mausoleums, lane polygons,
    pieces as (piece, inner), ways: the streets and avenues, which stay
    open)."""
    taken = Taken()
    pieces, planned, rngs, avenues, lane_polys, piece_lanes, ways = [], [], [], [], [], [], []
    for k, piece in enumerate(kept):
        prng = ck.rng_at(203, piece.centroid.x, piece.centroid.y)
        F = kit.Frame(piece)
        inner = piece.buffer(-PLOT_SETBACK_M, join_style="mitre")
        if blocked is not None:
            inner = inner.difference(blocked)
        if inner.is_empty:
            continue
        pieces.append((piece, inner))
        st = streets(piece, inner, F, prng, k == 0)
        street_u = unary_union([s for s, _ in st]) if st else None
        avenues += [s for s, wide in st if wide]
        ways += [s.intersection(inner) for s, _ in st]
        avail = inner.difference(street_u) if street_u is not None else inner
        if avail.is_empty:
            continue
        prepare(avail)
        street_x = [F.local(s).bounds[0::2] for s, _ in st]
        bands, lanes = plan_piece(avail, F, prng, k == 0, street_x)
        for a, b, wide in lanes:
            lane = F.rect(-1e4, a, 1e4, b).intersection(inner)
            lane_polys.append(lane)
            if wide:
                avenues.append(lane)
                ways.append(lane)
        planned.append((F, avail, bands))
        rngs.append(prng)
        piece_lanes.append(lanes)
    total = sum(p.area for p, _ in pieces)
    n_maus = int(round(total / 10000.0 * MAUSOLEUMS_PER_HA))
    spots = sorted(mausoleum_spots(planned, avenues, rngs), key=lambda s: (s[0], s[1]))
    maus = []
    for _, _, sq in spots:
        if len(maus) >= n_maus:
            break
        if any(sq.centroid.distance(m.centroid) < 55.0 for m in maus):
            continue
        maus.append(sq)
        taken.add(sq.buffer(1.5, join_style="mitre"))
    plots = []
    for (F, avail, bands), prng in zip(planned, rngs):
        for k, band in enumerate(bands):
            band_plots(band, len(bands), k, avail, F, prng, taken, plots)
    for (F, avail, bands), prng, lanes in zip(planned, rngs, piece_lanes):
        for j, lane in enumerate(lanes):
            if not lane[2] and j + 1 < len(bands):
                lane_plugs(bands[j], bands[j + 1], lane, avail, F, prng, taken, plots)
    # Ground still a lane's width from every plot (wedges, the ends of
    # bands the piece's outline cut short) gets bands of its own, laid
    # along its own long axis.
    near = unary_union([g for g, *_ in plots] + maus).buffer(LANE_M[0])
    if ways:
        near = near.union(unary_union(ways))
    for F, avail, bands in planned:
        for part in style.polys(avail.difference(near)):
            if part.area < 2 * MIN_PLOT_M2:
                continue
            c = part.representative_point()
            prng = ck.rng_at(207, c.x, c.y)
            Fp = kit.Frame(part)
            more, _ = plan_piece(part, Fp, prng, False, [])
            for k, band in enumerate(more):
                band_plots(band, len(more), k, part, Fp, prng, taken, plots)
    out = []
    for g, F, face in plots:
        for part in split_large(g, F):
            part = clean_plot(part)
            if good_plot(part):
                out.append((part, F, face))
    for piece, inner in pieces:
        lane_polys.append(inner)
    return out, maus, lane_polys, pieces, ways


def landmark_outline(cem, land):
    """The cemetery as the game names it: its kept land with the lanes
    between the pieces closed, inside the OSM area."""
    g = land.buffer(LANDMARK_CLOSE_M, join_style="mitre").buffer(-LANDMARK_CLOSE_M, join_style="mitre")
    g = g.intersection(cem).buffer(0)
    return kit.largest(g) if len(style.polys(g)) == 1 else g


def grave_fields(land, plot_u, ways):
    """Open burial ground: cemetery land at least GRAVE_FIELD_CLEAR_M from
    every plot (the spurs between narrow service lanes, too tight for walled
    plots and mecha-wide lanes, and leftover corners), less the streets and
    avenues."""
    g = land.difference(plot_u.buffer(GRAVE_FIELD_CLEAR_M))
    if ways is not None:
        g = g.difference(ways.buffer(1.0))
    g = g.buffer(-1.5, join_style="mitre").buffer(1.5, join_style="mitre").intersection(land)
    return [p for p in style.polys(g) if p.area >= 40.0]


def grave_field(L, area, rng):
    """Rows of simple graves on rough ground (drawing only), along the
    area's long axis: a stone kerb round a low mound and a headstone at the
    head; some broken down to their kerb, gaps here and there."""
    key = style.chunk_key(area)
    L.fill("groundlines", area, 0.13, 0.55, chunk=key)
    room = area.buffer(-1.1)
    if room.is_empty:
        return
    prepare(room)
    ang, c = style.frame_of(area)
    F = ck.Local(c.x, c.y, np.radians(ang))
    lx = [F.to_local(x, y) for x, y in area.exterior.coords]
    x0, x1 = min(p[0] for p in lx), max(p[0] for p in lx)
    y0, y1 = min(p[1] for p in lx), max(p[1] for p in lx)
    Q = F.quads()
    for y in np.arange(y0 + 1.3, y1 - 1.0, rng.uniform(2.7, 3.1)):
        x = x0 + rng.uniform(0.4, 1.4)
        while x < x1 - 0.6:
            w, h = rng.uniform(0.8, 1.0), rng.uniform(1.8, 2.2)
            px, py = F.pt(x + w / 2, y)
            if rng.random() > GRAVE_GAP and contains_xy(room, px, py):
                ya, yb = y - h / 2, y + h / 2
                if rng.random() < GRAVE_BROKEN:
                    Q.rect(x, ya, x + w, yb, rng.uniform(0.17, 0.22), 0.8)
                    Q.rect(x + 0.15, ya + 0.15, x + w - 0.15, yb - 0.15, 0.1)
                else:
                    Q.rect(x, ya, x + w, yb, rng.uniform(0.26, 0.32))
                    Q.rect(x + 0.12, ya + 0.12, x + w - 0.12, yb - 0.12, rng.uniform(0.14, 0.19))
                    Q.rect(x - 0.05, ya, x + w + 0.05, ya + 0.22, 0.4)
            x += w + rng.uniform(0.5, 1.0)
    Q.flush(L, "groundlines", key)


def split_large(g, F):
    """A plot over MAX_PLOT_M2 cut across its long side into equal parts."""
    if g.area <= MAX_PLOT_M2:
        return [g]
    n = int(np.ceil(g.area / MAX_PLOT_M2))
    lx = [F.to_local(x, y) for x, y in g.exterior.coords]
    x0, x1 = min(p[0] for p in lx), max(p[0] for p in lx)
    y0, y1 = min(p[1] for p in lx), max(p[1] for p in lx)
    out = []
    for i in range(n):
        if x1 - x0 >= y1 - y0:
            cut = F.rect(x0 + (x1 - x0) * i / n, y0 - 1, x0 + (x1 - x0) * (i + 1) / n, y1 + 1)
        else:
            cut = F.rect(x0 - 1, y0 + (y1 - y0) * i / n, x1 + 1, y0 + (y1 - y0) * (i + 1) / n)
        part = kit.largest(g.intersection(cut))
        if part is not None and part.area >= MIN_PLOT_M2:
            out.append(part)
    return out


def gate_of(g, F, face, free, rng):
    """The gate (x, y, angle of the wall) on the side of the plot that
    faces a lane: the layout's side when its probe is free ground, else
    any side whose probe 4 m out is free (not in a plot)."""
    lx = [F.to_local(x, y) for x, y in g.exterior.coords]
    x0, x1 = min(p[0] for p in lx), max(p[0] for p in lx)
    y0, y1 = min(p[1] for p in lx), max(p[1] for p in lx)
    xm = (x0 + x1) / 2 + rng.uniform(-0.2, 0.2) * (x1 - x0)
    ym = (y0 + y1) / 2 + rng.uniform(-0.2, 0.2) * (y1 - y0)
    sides = {-1: (xm, y0, 0.0, (0, -4)), 1: (xm, y1, 0.0, (0, 4)), -2: (x0, ym, np.pi / 2, (-4, 0)),
             2: (x1, ym, np.pi / 2, (4, 0))}
    order = ([face] if face else []) + [s for s in (-1, 1, -2, 2) if s != face]
    pick = None
    for s in order:
        x, y, _, (dx, dy) = sides[s]
        if free.contains(Point(*F.pt(x + dx, y + dy))):
            pick = s
            break
    if pick is None:
        pick = face or -1
    x, y, a, _ = sides[pick]
    wx, wy = F.pt(x, y)
    p = g.exterior.interpolate(g.exterior.project(Point(wx, wy)))
    return (p.x, p.y, F.ang + a)


def outer_walls(piece, land, roads_u):
    """Runs of the piece's outline that face the outside of the cemetery:
    away from the roads, or along a road whose far side (16 m out) is not
    cemetery land."""
    ring = orient(piece, 1.0).exterior
    n = max(8, int(ring.length / 2.0))
    ds = np.linspace(0, ring.length, n, endpoint=False)
    flags = []
    for d in ds:
        p = ring.interpolate(d)
        q = ring.interpolate(min(d + 0.5, ring.length))
        t = np.array([q.x - p.x, q.y - p.y])
        t /= max(np.hypot(*t), 1e-9)
        nx, ny = t[1], -t[0]
        near_road = roads_u is not None and roads_u.distance(p) < 2.5
        if not near_road:
            flags.append(True)
        else:
            flags.append(not land.contains(Point(p.x + nx * 16.0, p.y + ny * 16.0)))
    runs, cur = [], []
    for d, f in zip(ds, flags):
        if f:
            cur.append(d)
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        if runs and flags[0] and runs[0][0] == ds[0]:
            runs[0] = [d - ring.length for d in cur] + runs[0]
        else:
            runs.append(cur)
    out = []
    for r in runs:
        if r[-1] - r[0] < 4.0:
            continue
        a, b = r[0], r[-1] + ring.length / n
        if a < 0:
            line = LineString(list(substring(ring, ring.length + a, ring.length).coords) +
                              list(substring(ring, 0, b).coords)[1:])
        else:
            line = substring(ring, a, min(b, ring.length))
        if line.length > 4.0:
            out.append(line)
    return out


def wall_mouths(line, plot_u, min_open=9.0, step=2.0):
    """Gates in a perimeter wall: the middle of each stretch of at least
    min_open metres where no plot stands within PLOT_SETBACK_M + 2 m inside
    it (a lane or a cut meets the wall there); one in the middle of a long
    wall with none."""
    ds = np.arange(0.0, line.length + 0.01, step)
    open_ = [not plot_u.intersects(line.interpolate(d).buffer(PLOT_SETBACK_M + 2.0)) for d in ds]
    out, start = [], None
    for d, o in zip(list(ds) + [None], open_ + [False]):
        if o and start is None:
            start = d
        elif not o and start is not None:
            end = d if d is not None else line.length
            if end - start >= min_open:
                out.append(line.interpolate((start + end) / 2))
            start = None
    if not out and line.length > 80.0:
        out.append(line.interpolate(0.5, normalized=True))
    return out


def build(site, lay):
    """Lays out and builds both cemeteries (lay: civickit.Layout). Returns
    their stats."""
    stats = {}
    for cem, name, tag, max_m2 in cemetery_polys(site):
        rng = ck.rng_at(201, cem.centroid.x, cem.centroid.y)
        roads_u = lay.roads_near(cem, 30.0)
        land = cem.difference(roads_u.buffer(1.0)) if roads_u is not None else cem
        land = ck.free_land(site, land, districts=False)
        pieces = sorted([g for g in style.polys(land) if g.area >= 150.0], key=lambda g: -g.area)
        kept, total = [], 0.0
        for g in pieces:
            if total + g.area <= max_m2 * 1.05:
                kept.append(g)
                total += g.area
        if not kept:
            continue
        land = unary_union(kept)
        site.claim(land, f"civic:{tag}")
        outline = landmark_outline(cem, land)
        site.add_landmark(name, "cemetery", outline)
        if roads_u is not None:
            props.ROAD_KEEP_OFF.append(outline.intersection(roads_u))
        others = [g for g in lay.big_in(land) if not land.contains(g.centroid)]
        blocked = unary_union([g.buffer(2.0) for g in others]) if others else None
        plots, maus, lanes, piece_info, ways = layout(cem, kept, blocked, rng)
        plot_u = unary_union([g.buffer(0.3) for g, *_ in plots] + [m.buffer(1.0) for m in maus])
        prepare(plot_u)
        fields = grave_fields(land, plot_u, unary_union(ways) if ways else None)
        if site.in_window(land):
            site.remove_buildings_touching(land, kinds=("house",), margin=0.0)
            site.remove_buildings_in(land, kinds=("big",))
            site.clear_area(land.buffer(0.5))
        free = land.buffer(6.0).difference(plot_u)
        prepare(free)
        walls = []
        land_near = land.buffer(3.0)
        prepare(land_near)
        for piece, inner in piece_info:
            for line in outer_walls(piece, land_near, roads_u):
                walls.append((line, wall_mouths(line, plot_u)))
        if walls:
            free = free.difference(unary_union([line for line, _ in walls]).buffer(2.6))
            prepare(free)

        made = {"plots": 0, "collapsed": 0, "damaged": 0, "mausoleums": 0, "tomb_rooms": 0, "trees": 0,
                "grave_fields_m2": 0}
        district_taken = site.district_taken()
        tombs = [g for g, *_ in plots] + maus
        tomb_tree = STRtree(tombs)
        for g, F, face in plots:
            if not site.in_window(g):
                continue
            if district_taken is not None and district_taken.intersects(g):
                continue
            near = [tombs[i] for i in tomb_tree.query(g.buffer(SPILL_M)) if tombs[i] is not g]
            clip = unary_union(near) if near else None
            c = g.centroid
            r = ck.rng_at(211, c.x, c.y)
            dmg = ruins.state_at(c.x, c.y, 0)
            u = r.random()
            if (dmg >= ruins.COLLAPSED and u < COLLAPSED_AT_MAP) or u < COLLAPSED_CHANCE:
                look = "collapsed"
            elif (dmg >= ruins.GUTTED and r.random() < DAMAGED_AT_MAP) or r.random() < DAMAGED_CHANCE:
                look = "damaged"
            else:
                look = "ok"
            gate = gate_of(g, F, face, free, r)
            room = None
            if g.area >= 80.0 and r.random() < TOMB_ROOM_CHANCE:
                s = r.uniform(3.4, 4.8)
                gx, gy = F.to_local(gate[0], gate[1])
                lx = [F.to_local(x, y) for x, y in g.exterior.coords]
                x0, x1 = min(q[0] for q in lx), max(q[0] for q in lx)
                y0, y1 = min(q[1] for q in lx), max(q[1] for q in lx)
                if abs(gy - y0) < 1.0 or abs(gy - y1) < 1.0:
                    ry_ = y1 - s / 2 - 1.0 if abs(gy - y0) < abs(gy - y1) else y0 + s / 2 + 1.0
                    rx_ = r.uniform(x0 + s / 2 + 1.0, max(x0 + s / 2 + 1.01, x1 - s / 2 - 1.0))
                else:
                    rx_ = x1 - s / 2 - 1.0 if abs(gx - x0) < abs(gx - x1) else x0 + s / 2 + 1.0
                    ry_ = r.uniform(y0 + s / 2 + 1.0, max(y0 + s / 2 + 1.01, y1 - s / 2 - 1.0))
                rx, ry = F.pt(rx_, ry_)
                if g.buffer(-0.8).contains(ck.square(rx, ry, s, F.ang)):
                    room = (rx, ry, s)
                    made["tomb_rooms"] += 1
            b = bl.Building(g, float(site.sampler.value(c.x, c.y)), "hosh", ang=F.ang, look=look, gate=gate,
                            room=room, clip=clip)
            b.opts["state"] = ruins.COLLAPSED if look == "collapsed" else ruins.GUTTED
            site.buildings.append(b)
            made["plots"] += 1
            made["collapsed"] += look == "collapsed"
            made["damaged"] += look == "damaged"
            if look != "collapsed" and g.area >= 120.0 and r.random() < PLOT_TREE_CHANCE:
                inner = g.buffer(-2.5)
                q = inner.representative_point() if not inner.is_empty else None
                if q is not None and (room is None or q.distance(Point(room[0], room[1])) > room[2]):
                    made["trees"] += site.props.add("tree", q.x, q.y, r.uniform(0, 2 * np.pi),
                                                    (r.uniform(6, 9),) * 2)
        for g in maus:
            if not site.in_window(g):
                continue
            if district_taken is not None and district_taken.intersects(g):
                continue
            c = g.centroid
            b = bl.Building(g, float(site.sampler.value(c.x, c.y)), "mausoleum")
            if ruins.state_at(c.x, c.y, 0) >= ruins.COLLAPSED:
                b.opts["state"] = ruins.GUTTED
            site.buildings.append(b)
            made["mausoleums"] += 1
        site.solid_extra.append(land)

        # Bare trees in the lanes, kept 2 m off the plots.
        lane_room = land.buffer(-1.0).difference(plot_u.buffer(2.0))
        for part in style.polys(lane_room):
            if part.area < 60.0:
                continue
            tr = ck.rng_at(213, *part.representative_point().coords[0])
            for x, y in ruins.scatter(part, int(part.area / LANE_TREE_M2) + (tr.random() < 0.3), tr):
                size, ang = tr.uniform(7, 11), tr.uniform(0, 2 * np.pi)
                if site.in_window(Point(x, y)):
                    made["trees"] += site.props.add("tree", float(x), float(y), ang, (size, size))
        seed = int(rng.integers(1 << 30))
        drawn = [(piece, inner) for piece, inner in piece_info if site.in_window(piece)]
        drawn_walls = [(line, mouths) for line, mouths in walls if site.in_window(line)]
        drawn_fields = [g for g in fields if site.in_window(g)]
        made["grave_fields_m2"] = round(sum(g.area for g in drawn_fields))

        def draw(L, drawn=drawn, drawn_walls=drawn_walls, drawn_fields=drawn_fields, seed=seed, plot_u=plot_u):
            for piece, inner in drawn:
                r = ck.rng_at(seed, *piece.representative_point().coords[0])
                L.fill("groundlines", piece, 0.21, 0.35, clip=True)
                ruins.add_rubble(L, "groundlines", inner.difference(plot_u), 0.004, (0.3, 0.8), r, None)
            for g in drawn_fields:
                grave_field(L, g, ck.rng_at(seed, *g.representative_point().coords[0]))
            for line, mouths in drawn_walls:
                ck.compound_wall(L, line, v=0.34, width=0.85, gates=mouths, gap=9.0)
        site.drawers.append(draw)
        stats[tag] = {"area_m2": round(total), "pieces": len(kept), "plots_laid": len(plots),
                      "mausoleums_laid": len(maus), **made}
    return stats
