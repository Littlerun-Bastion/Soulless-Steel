"""Solar panel installations: six looks, one salvage source each
("solar_panels", its box round the whole installation, amount = intact
modules). All give the same item; bigger installations give more.

  tilted rack rows    large flat roofs: rows two modules deep on steel frames,
                      concrete ballast feet, a long shadow behind each row
  raised canopy       large flat roofs: one continuous field on a raised frame
                      over the roof, posts along the long edges, a long dark
                      shadow; roof items stay under it (drawn after them)
  low ballasted rows  long flat roofs (schools, warehouses, sheds): landscape
                      modules in tight rows over most of the roof, a guard
                      rail round the roof edge
  small house set     flat house roofs: 2 to 6 modules on a small frame
  flush on tile roof  pitched roofs (rectangle and L): modules laid flat on
                      one slope, in rows along the eaves
  ground array        farmland and industrial edges: fenced rows on posts,
                      bare ground under them

Module styles vary per installation, never inside one (MODULE_STYLES): mono
60-cell (1.0 x 1.65 m), mono 72-cell (1.0 x 2.0 m), half-cut (split across the
middle), poly (lighter, a visible cell grid), black frame.
Wear (per module): MISSING (only the rails show), CRACKED, a few with glare.

The roof kit (style.Roof) treats a rack or small set as taken, so tanks,
dishes and AC boxes never sit under one. Everything is drawn as plain quads
(numpy), so thousands of modules stay cheap.
"""
import numpy as np
from shapely import affinity, prepare
from shapely.geometry import Polygon
from shapely.ops import unary_union

MODULE_STYLES = {
    # name: (short side, long side, cell grid (across, along), body grey,
    #        frame grey, half-cut)
    "mono60": (1.0, 1.65, (6, 10), 0.045, 0.30, False),
    "mono72": (1.0, 2.0, (6, 12), 0.045, 0.30, False),
    "halfcut": (1.0, 1.75, (6, 12), 0.05, 0.28, True),
    "poly": (1.0, 1.65, (6, 10), 0.11, 0.32, False),
    "black": (1.0, 1.7, (6, 10), 0.035, 0.03, False),
}
STYLE_WEIGHTS = {"mono60": 0.3, "mono72": 0.2, "halfcut": 0.2, "poly": 0.2, "black": 0.1}
MISSING = 0.04
CRACKED = 0.04
GLARE = 0.03
FRAME_V = 0.24
SHADOW_A = 0.55


def pick_style(rng):
    names = list(STYLE_WEIGHTS)
    w = np.array([STYLE_WEIGHTS[n] for n in names])
    return names[int(rng.choice(len(names), p=w / w.sum()))]


class Quads:
    """Collects rotated rectangles (and thin lines) in a local frame, then
    adds them to a sublayer as triangles in one call."""

    def __init__(self, origin, ang_deg):
        self.o = np.array([origin.x, origin.y])
        a = np.radians(ang_deg)
        self.R = np.array([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
        self.tris, self.grey, self.alpha = [], [], []

    def rect(self, x0, y0, x1, y1, v, a=1.0):
        q = np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]) @ self.R.T + self.o
        self.tris += [q[[0, 1, 2]], q[[0, 2, 3]]]
        self.grey += [[v] * 3] * 2
        self.alpha += [[a] * 3] * 2

    def grad(self, x0, y0, x1, y1, v, a0, a1):
        """A rectangle whose alpha fades from a0 at y0 to a1 at y1."""
        q = np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]) @ self.R.T + self.o
        self.tris += [q[[0, 1, 2]], q[[0, 2, 3]]]
        self.grey += [[v] * 3] * 2
        self.alpha += [[a0, a0, a1], [a0, a1, a1]]

    def line(self, x0, y0, x1, y1, w, v, a=1.0):
        d = np.array([x1 - x0, y1 - y0])
        n = np.hypot(*d)
        if n < 1e-6:
            return
        nx, ny = -d[1] / n * w / 2, d[0] / n * w / 2
        q = np.array([[x0 + nx, y0 + ny], [x1 + nx, y1 + ny], [x1 - nx, y1 - ny], [x0 - nx, y0 - ny]]) @ self.R.T + self.o
        self.tris += [q[[0, 1, 2]], q[[0, 2, 3]]]
        self.grey += [[v] * 3] * 2
        self.alpha += [[a] * 3] * 2

    def to_world(self, x, y):
        return np.array([x, y]) @ self.R.T + self.o

    def flush(self, L, sub, chunk):
        if not self.tris:
            return
        L.add_tris(sub, np.array(self.tris), 0.0, chunk=chunk, va=np.array(self.alpha), vg=np.array(self.grey))
        self.tris, self.grey, self.alpha = [], [], []


def module(Q, x, y, w, h, style_name, state, rng):
    """One module, its corner at (x, y), w across and h along its long side
    (either way round). state: 0 intact, 1 missing, 2 cracked."""
    _, _, (ca, cl), body, frame, half = MODULE_STYLES[style_name]
    if state == 1:
        Q.line(x + w * 0.2, y, x + w * 0.2, y + h, 0.07, FRAME_V)
        Q.line(x + w * 0.8, y, x + w * 0.8, y + h, 0.07, FRAME_V)
        return
    Q.rect(x, y, x + w, y + h, frame)
    Q.rect(x + 0.07, y + 0.07, x + w - 0.07, y + h - 0.07, body)
    Q.grad(x + 0.07, y + 0.07, x + w - 0.07, y + h * 0.5, body * 1.9, 0.35, 0.0)
    across, along = (ca, cl) if w <= h else (cl, ca)
    if style_name == "poly":
        for i in range(1, across):
            xx = x + w * i / across
            Q.line(xx, y + 0.05, xx, y + h - 0.05, 0.02, body * 0.55)
        for j in range(1, along):
            yy = y + h * j / along
            Q.line(x + 0.05, yy, x + w - 0.05, yy, 0.02, body * 0.55)
    else:
        for i in range(1, across, 2):
            xx = x + w * i / across
            Q.line(xx, y + 0.05, xx, y + h - 0.05, 0.015, body * 1.8, 0.6)
    if half:
        if w <= h:
            Q.line(x + 0.04, y + h / 2, x + w - 0.04, y + h / 2, 0.05, frame)
        else:
            Q.line(x + w / 2, y + 0.04, x + w / 2, y + h - 0.04, 0.05, frame)
    if state == 2:
        cx, cy = x + w * rng.uniform(0.3, 0.7), y + h * rng.uniform(0.3, 0.7)
        for _ in range(3):
            a = rng.uniform(0, 2 * np.pi)
            r = rng.uniform(0.25, 0.6) * min(w, h)
            Q.line(cx, cy, cx + np.cos(a) * r, cy + np.sin(a) * r, 0.025, 0.32)
    elif rng.random() < GLARE:
        Q.line(x + w * 0.15, y + h * 0.8, x + w * 0.85, y + h * 0.2, min(w, h) * 0.18, 0.4, 0.5)


def wear(rng):
    r = rng.random()
    return 1 if r < MISSING else 2 if r < MISSING + CRACKED else 0


def module_grid(Q, x0, y0, cols, rows, mw, mh, gap, style_name, rng):
    """cols x rows modules from corner (x0, y0); returns how many are
    intact."""
    intact = 0
    for i in range(cols):
        for j in range(rows):
            st = wear(rng)
            module(Q, x0 + i * (mw + gap), y0 + j * (mh + gap), mw, mh, style_name, st, rng)
            intact += st == 0
    return intact


def free_rect(R, w, h, tries=20, margin=0.4):
    """A free w x h spot in the roof's local frame (like Roof.place, without
    taking it)."""
    for _ in range(tries):
        if R.x1 - R.x0 < w + 2 * margin or R.y1 - R.y0 < h + 2 * margin:
            return None
        x = R.rng.uniform(R.x0 + margin, R.x1 - w - margin)
        y = R.rng.uniform(R.y0 + margin, R.y1 - h - margin)
        r = R.rect(x, y, x + w, y + h)
        if R.inner.contains(r) and not any(r.buffer(margin).intersects(t) for t in R.taken):
            return x, y, r
    return None


def house_set(R, rng):
    """2 to 6 modules on a small frame on a flat house roof. Returns (outline
    polygon, intact modules) or None. The set is taken on the roof."""
    st = pick_style(rng)
    sw, sl = MODULE_STYLES[st][:2]
    n = int(rng.integers(2, 7))
    rows = 1 if n <= 3 else 2
    cols = int(np.ceil(n / rows))
    gap = 0.05
    w, h = cols * (sw + gap) + 0.3, rows * (sl + gap) + 0.3
    spot = free_rect(R, w, h)
    if spot is None:
        spot = free_rect(R, h, w)
        if spot is None:
            return None
        w, h = h, w
        landscape = True
    else:
        landscape = False
    x, y, r = spot
    R.taken.append(r)
    Q = Quads(R.c, R.ang)
    Q.grad(x, y + h, x + w, y + h + 0.9, 0.0, SHADOW_A, 0.0)
    Q.rect(x, y, x + w, y + h, FRAME_V * 0.6)
    intact = 0
    for k in range(n):
        if landscape:
            i, j = k // cols, k % cols
            mx, my = x + 0.15 + i * (sl + gap), y + 0.15 + j * (sw + gap)
            st_k = wear(rng)
            module(Q, mx, my, sl, sw, st, st_k, rng)
        else:
            i, j = k % cols, k // cols
            mx, my = x + 0.15 + i * (sw + gap), y + 0.15 + j * (sl + gap)
            st_k = wear(rng)
            module(Q, mx, my, sw, sl, st, st_k, rng)
        intact += st_k == 0
    Q.flush(R.L, "roofs", R.key)
    return r, intact


def tilted_rows(R, rng):
    """Rows two modules deep across a large flat roof, each on a steel frame
    with ballast feet and a long shadow behind it. Taken on the roof."""
    st = pick_style(rng)
    sw, sl = MODULE_STYLES[st][:2]
    depth = 2 * sw + 0.1
    pitch = depth * rng.uniform(1.9, 2.4)
    spot = None
    for k in np.linspace(1.0, 0.45, 6):
        span_x = (R.x1 - R.x0) * 0.85 * k
        span_y = (R.y1 - R.y0) * 0.8 * k
        cols = int(span_x // (sl + 0.04))
        rows = int(span_y // pitch)
        if cols < 3 or rows < 1:
            return None
        w = cols * (sl + 0.04)
        h = (rows - 1) * pitch + depth
        spot = free_rect(R, w + 0.6, h + 1.4)
        if spot is not None:
            break
    if spot is None:
        return None
    x, y, r = spot
    R.taken.append(r)
    Q = Quads(R.c, R.ang)
    intact = 0
    for k in range(rows):
        ry = y + 0.3 + k * pitch
        Q.grad(x + 0.3, ry + depth, x + 0.3 + w, ry + depth + depth * 0.8, 0.0, SHADOW_A, 0.0)
        Q.rect(x + 0.2, ry - 0.08, x + 0.4 + w, ry + depth + 0.08, FRAME_V * 0.7)
        intact += module_grid(Q, x + 0.3, ry, cols, 2, sl, sw, 0.04, st, rng)
        for fx in np.arange(x + 0.3, x + 0.3 + w + 0.1, max(sl * 2, 3.0)):
            for fy in (ry - 0.25, ry + depth + 0.05):
                Q.rect(fx - 0.18, fy, fx + 0.18, fy + 0.22, 0.2)
    Q.flush(R.L, "roofs", R.key)
    return r, intact


def low_rows(R, rng):
    """Landscape modules in tight rows over most of a long roof, with a guard
    rail round the roof's edge. Taken on the roof."""
    st = pick_style(rng)
    sw, sl = MODULE_STYLES[st][:2]
    inset = 1.4
    x0, y0, x1, y1 = R.x0 + inset, R.y0 + inset, R.x1 - inset, R.y1 - inset
    cols = int((x1 - x0) // (sl + 0.05))
    pitch = sw + rng.uniform(0.35, 0.6)
    rows = int((y1 - y0) // pitch)
    if cols < 3 or rows < 2:
        return None
    r = R.rect(x0, y0, x0 + cols * (sl + 0.05), y0 + rows * pitch)
    if not R.inner.contains(r):
        return None
    blocked = unary_union([t.buffer(0.4) for t in R.taken]) if R.taken else None
    if blocked is not None:
        prepare(blocked)
    Q = Quads(R.c, R.ang)
    intact = placed = 0
    for k in range(rows):
        ry = y0 + k * pitch
        for i in range(cols):
            mx = x0 + i * (sl + 0.05)
            if blocked is not None and blocked.intersects(R.rect(mx, ry, mx + sl, ry + sw)):
                continue
            Q.grad(mx, ry + sw, mx + sl, ry + sw + 0.3, 0.0, SHADOW_A * 0.8, 0.0)
            st_k = wear(rng)
            module(Q, mx, ry, sl, sw, st, st_k, rng)
            intact += st_k == 0
            placed += 1
    if placed < 6:
        return None
    R.taken.append(r)
    g = 0.5
    for a, b in (((R.x0 + g, R.y0 + g), (R.x1 - g, R.y0 + g)), ((R.x1 - g, R.y0 + g), (R.x1 - g, R.y1 - g)),
                 ((R.x1 - g, R.y1 - g), (R.x0 + g, R.y1 - g)), ((R.x0 + g, R.y1 - g), (R.x0 + g, R.y0 + g))):
        Q.line(a[0], a[1], b[0], b[1], 0.08, 0.36)
    Q.flush(R.L, "roofs", R.key)
    return r, intact


def canopy(R, rng):
    """One continuous field on a raised frame over most of the roof, drawn
    after the roof items (they show only at its edges)."""
    st = pick_style(rng)
    sw, sl = MODULE_STYLES[st][:2]
    inset = 1.6
    span_x = (R.x1 - R.x0 - 2 * inset) * rng.uniform(0.6, 0.95)
    span_y = (R.y1 - R.y0 - 2 * inset) * rng.uniform(0.6, 0.9)
    cols, rows = int(span_x // (sw + 0.03)), int(span_y // (sl + 0.03))
    if cols < 4 or rows < 2:
        return None
    w, h = cols * (sw + 0.03), rows * (sl + 0.03)
    x = R.x0 + inset + rng.uniform(0, max(0.0, R.x1 - R.x0 - 2 * inset - w))
    y = R.y0 + inset + rng.uniform(0, max(0.0, R.y1 - R.y0 - 2 * inset - h))
    r = R.rect(x, y, x + w, y + h)
    if not R.inner.contains(r):
        return None
    Q = Quads(R.c, R.ang)
    Q.grad(x + 1.0, y + h, x + w + 1.0, y + h + 2.4, 0.0, SHADOW_A, 0.0)
    Q.grad(x + w, y + 1.0, x + w + 1.6, y + h + 1.0, 0.0, SHADOW_A * 0.8, 0.0)
    Q.rect(x - 0.15, y - 0.15, x + w + 0.15, y + h + 0.15, FRAME_V * 0.8)
    intact = module_grid(Q, x, y, cols, rows, sw, sl, 0.03, st, rng)
    for px in np.arange(x, x + w + 0.1, 5.0):
        for py in (y - 0.1, y + h - 0.2):
            Q.rect(px - 0.15, py, px + 0.15, py + 0.3, 0.3)
    Q.flush(R.L, "roofs", R.key)
    return r, intact


def flush_on_tiles(L, rects, ang, c, rng, key):
    """Modules laid flat on one slope of a pitched roof (its largest section),
    in rows along the eaves. rects are the roof sections in the local frame
    (style.roof_shape). Returns (outline polygon, intact) or None."""
    x0, y0, x1, y1 = rects[0]
    x0, x1, y0, y1 = x0 - c.x, x1 - c.x, y0 - c.y, y1 - c.y
    st = pick_style(rng)
    sw, sl = MODULE_STYLES[st][:2]
    along_x = (x1 - x0) >= (y1 - y0)
    length = (x1 - x0) if along_x else (y1 - y0)
    half = ((y1 - y0) if along_x else (x1 - x0)) / 2
    cols = int((length - 1.6) // (sw + 0.03))
    rows = int((half - 0.9) // (sl + 0.03))
    if cols < 2 or rows < 1:
        return None
    cols = min(cols, int(rng.integers(2, cols + 1)))
    w, h = cols * (sw + 0.03), rows * (sl + 0.03)
    Q = Quads(c, ang)
    lo = rng.random() < 0.5
    if along_x:
        sx = x0 + 0.8 + rng.uniform(0, max(0.0, length - 1.6 - w))
        sy = (y0 + 0.5) if lo else (y1 - 0.5 - h)
        intact = module_grid(Q, sx, sy, cols, rows, sw, sl, 0.03, st, rng)
        box = (sx, sy, sx + w, sy + h)
    else:
        sy = y0 + 0.8 + rng.uniform(0, max(0.0, length - 1.6 - w))
        sx = (x0 + 0.5) if lo else (x1 - 0.5 - h)
        intact = module_grid(Q, sx, sy, rows, cols, sl, sw, 0.03, st, rng)
        box = (sx, sy, sx + h, sy + w)
    Q.flush(L, "roofs", key)
    pts = [Q.to_world(px, py) for px, py in
           ((box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3]))]
    return Polygon(pts), intact


def ground_array(L, poly_area, ang, rng, chunk):
    """Fenced rows of modules on posts over a patch of ground (a shapely
    polygon), in rows along ang (degrees). Draws into "interiors" (over the
    halos). Returns (outline polygon, intact modules) or None."""
    c = poly_area.centroid
    loc = affinity.rotate(poly_area, -ang, origin=c)
    x0, y0, x1, y1 = (b - o for b, o in zip(loc.bounds, (c.x, c.y) * 2))
    st = pick_style(rng)
    sw, sl = MODULE_STYLES[st][:2]
    depth = 2 * sw + 0.1
    pitch = depth + rng.uniform(2.5, 3.5)
    cols = int((x1 - x0 - 4) // (sl + 0.04))
    rows = int((y1 - y0 - 4) // pitch)
    if cols < 4 or rows < 2:
        return None
    w, h = cols * (sl + 0.04), (rows - 1) * pitch + depth
    ox, oy = x0 + (x1 - x0 - w) / 2, y0 + (y1 - y0 - h) / 2
    Q = Quads(c, ang)
    Q.rect(ox - 2.0, oy - 2.0, ox + w + 2.0, oy + h + 2.0, 0.07, 0.5)
    intact = 0
    for k in range(rows):
        ry = oy + k * pitch
        Q.grad(ox, ry + depth, ox + w, ry + depth + 1.6, 0.0, SHADOW_A, 0.0)
        intact += module_grid(Q, ox, ry, cols, 2, sl, sw, 0.04, st, rng)
        for px in np.arange(ox + 0.5, ox + w, 3.2):
            Q.rect(px - 0.1, ry + depth, px + 0.1, ry + depth + 0.25, 0.25)
    fx0, fy0, fx1, fy1 = ox - 2.6, oy - 2.6, ox + w + 2.6, oy + h + 2.6
    for a, b in (((fx0, fy0), (fx1, fy0)), ((fx1, fy0), (fx1, fy1)), ((fx1, fy1), (fx0, fy1)), ((fx0, fy1), (fx0, fy0))):
        Q.line(a[0], a[1], b[0], b[1], 0.08, 0.3)
        n = int(np.hypot(b[0] - a[0], b[1] - a[1]) // 3)
        for t in np.linspace(0, 1, max(n, 2)):
            px, py = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            Q.rect(px - 0.1, py - 0.1, px + 0.1, py + 0.1, 0.34)
    Q.flush(L, "interiors", chunk)
    pts = [Q.to_world(px, py) for px, py in ((fx0, fy0), (fx1, fy0), (fx1, fy1), (fx0, fy1))]
    return Polygon(pts), intact
