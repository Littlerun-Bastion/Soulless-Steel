"""Pipes and pipe racks: their shape and how they are drawn (section 3.3 of
the districts brief).

A pipe is a polyline with filleted corners; the elbow radius is ELBOW_K x the
diameter. In a rack every pipe is the same centre line offset sideways, so
the bends are concentric. Draw order per rack: shadows, then each pipe's dark
outline, body and light highlight, then flanges every 6 to 9 m. Racks have
3 to 5 pipes at about 0.9 m spacing on two runners with a cross-member every
6 m. An expansion loop is a U detour of LOOP_DEPTH_M on a long straight run.
Diameters are 0.4 to 1.3 m; pipes are brighter than roofs.

A Run is one pipe or rack from end to end. Parts of it can be raised as a
pipe bridge (add_bridge): those parts are drawn in the overheads sublayer on
a truss with a support at each end, and they are no obstacle (mechs pass
under). The parts on the ground are drawn in the interiors sublayer and each
one is one "pipe" obstacle outline (one outline per rack run, not per pipe).
Each end of a run is at equipment ("equip"), joins another pipe or rack
("tee"), or stops in open ground ("open").
"""
import numpy as np
from shapely import affinity
from shapely.geometry import LineString, Point
from shapely.ops import substring

from solar import Quads

RACK_PIPES = (3, 5)
PIPE_DIA_M = (0.4, 1.3)
RACK_GAP_M = 0.9
ELBOW_K = 2.5
LOOP_DEPTH_M = 7.0
LOOP_WIDTH_M = 9.0
CROSS_MEMBER_M = 6.0
FLANGE_M = (6.0, 9.0)
PIPE_V = (0.3, 0.44)
RUNNER_V = 0.15
TRUSS_V = 0.34
## Grey of a truss drawn over the pipes.
TRUSS_V_OVER = 0.42
## Ground kept clear on each side of a pipe or rack by its obstacle outline.
PIPE_CLEAR_M = 0.35
## The longest span of a pipe bridge between two supports.
SUPPORT_M = 26.0
## Where a rack's truss is: under the pipes, over them, or both (the pipes
## between two trusses). A rack takes one for its whole length
## (truss_variant).
TRUSS_VARIANTS = ("under", "over", "both")
## Two raised parts of a run closer together than this become one.
MIN_GROUND_M = 5.0
LIGHT = np.array([1.0, -0.4]) / np.hypot(1.0, 0.4)


def fillet(pts, radius, step_deg=12.0):
    """A polyline with each corner replaced by a circular arc of the given
    radius (less where the segments are too short for it)."""
    pts = np.asarray(pts, float)
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    seg = np.hypot(*(pts[1:] - pts[:-1]).T)
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        u, v = (b - a) / max(seg[i - 1], 1e-9), (c - b) / max(seg[i], 1e-9)
        theta = float(np.arccos(np.clip(u @ v, -1.0, 1.0)))
        if theta < 1e-3 or theta > np.pi - 1e-3:
            out.append(b)
            continue
        t = min(radius * np.tan(theta / 2), seg[i - 1] / 2, seg[i] / 2)
        r = t / np.tan(theta / 2)
        turn = np.sign(u[0] * v[1] - u[1] * v[0])
        n = np.array([-u[1], u[0]]) * turn
        p1 = b - u * t
        centre = p1 + n * r
        a0 = np.arctan2(p1[1] - centre[1], p1[0] - centre[0])
        k = max(2, int(np.degrees(theta) / step_deg))
        for j in range(k + 1):
            ang = a0 + theta * turn * j / k
            out.append(centre + r * np.array([np.cos(ang), np.sin(ang)]))
    out.append(pts[-1])
    return np.asarray(out)


def loop_points(a, b, m, side):
    """The four corner points of an expansion loop on the straight run from a
    to b: a U detour LOOP_WIDTH_M wide and LOOP_DEPTH_M deep, centred m
    along the run, on the given side (+1 left of the direction, -1 right)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    u = (b - a) / max(np.hypot(*(b - a)), 1e-9)
    n = np.array([-u[1], u[0]]) * side
    pa, pb = a + u * (m - LOOP_WIDTH_M / 2), a + u * (m + LOOP_WIDTH_M / 2)
    return [tuple(pa), tuple(pa + n * LOOP_DEPTH_M), tuple(pb + n * LOOP_DEPTH_M), tuple(pb)]


def group_width(pipes):
    return max(o + d / 2 for o, d, _ in pipes) - min(o - d / 2 for o, d, _ in pipes)


def group_radius(pipes):
    """Centre-line elbow radius of a pipe group: the innermost pipe keeps
    ELBOW_K x the largest diameter."""
    return ELBOW_K * max(d for _, d, _ in pipes) + max(abs(o) for o, _, _ in pipes)


def rack_pipes(rng, n=None, dia=PIPE_DIA_M, max_width=None):
    """Pipes of a rack as (offset across, diameter, grey), centred on the
    rack's centre line."""
    n = n or int(rng.integers(RACK_PIPES[0], RACK_PIPES[1] + 1))
    for _ in range(8):
        dias = rng.uniform(*dia, n)
        offs, x = [0.0], 0.0
        for i in range(1, n):
            x += max(RACK_GAP_M, (dias[i - 1] + dias[i]) / 2 + 0.25)
            offs.append(x)
        if max_width is None or x + dias[0] / 2 + dias[-1] / 2 <= max_width:
            break
    offs = np.asarray(offs) - x / 2
    return [(float(o), float(d), float(rng.uniform(*PIPE_V))) for o, d in zip(offs, dias)]


def single_pipe(dia, grey):
    return [(0.0, float(dia), float(grey))]


def perp_segment(line, d, half):
    p = line.interpolate(d)
    q = line.interpolate(min(d + 0.3, line.length))
    t = np.array([q.x - p.x, q.y - p.y])
    if np.hypot(*t) < 1e-9:
        q = line.interpolate(max(d - 0.3, 0.0))
        t = np.array([p.x - q.x, p.y - q.y])
    t /= max(np.hypot(*t), 1e-9)
    n = np.array([-t[1], t[0]]) * half
    return LineString([(p.x - n[0], p.y - n[1]), (p.x + n[0], p.y + n[1])])


def draw_pipe_set(L, sub, centre, pipes, rng, runners=None):
    """Draws pipes along a centre line: shadows first, then each pipe's
    outline, body and highlight, then flanges. runners: the rack's half
    width, for its two runners and cross-members (None for a bare run)."""
    if centre.is_empty or centre.length < 0.5:
        return
    if runners is not None:
        for s in (-runners, runners):
            rl = centre.offset_curve(s, join_style="round")
            if not rl.is_empty:
                L.line(sub, rl, 0.22, RUNNER_V)
        for d in np.arange(0.5, centre.length, CROSS_MEMBER_M):
            L.line(sub, perp_segment(centre, d, runners + 0.15), 0.25, RUNNER_V)
    paths = []
    for o, d, v in pipes:
        path = centre.offset_curve(o, join_style="round") if abs(o) > 1e-3 else centre
        for part in getattr(path, "geoms", [path]):
            if part.is_empty or part.geom_type != "LineString" or part.length < 0.2:
                continue
            paths.append((part, d, v))
            sh = affinity.translate(part, -LIGHT[0] * 0.45, -LIGHT[1] * 0.45)
            L.fill(sub, sh.buffer(d / 2 + 0.1, cap_style="flat"), 0.0, 0.32)
    for path, d, v in paths:
        L.fill(sub, path.buffer(d / 2 + 0.07, cap_style="flat"), 0.03)
        L.fill(sub, path.buffer(d / 2, cap_style="flat"), v)
        hl = path.offset_curve(d * 0.22, join_style="round")
        if not hl.is_empty and hl.length > 0.2:
            L.line(sub, hl, d * 0.16, min(v * 1.55, 0.72), 0.8)
    for path, d, v in paths:
        dist = rng.uniform(1.0, FLANGE_M[0])
        while dist < path.length - 0.5:
            L.line(sub, perp_segment(path, dist, d / 2 + 0.12), 0.16, min(v * 1.3, 0.6))
            dist += rng.uniform(*FLANGE_M)


class Run:
    """One pipe or rack from end to end: corner points (map-frame metres),
    pipes, whether it is a rack (runners and cross-members), what each end
    is, and the parts raised as pipe bridges ([from, to, why] along its
    filleted centre line)."""

    def __init__(self, pts, pipes, rack=False, ends=("open", "open"), role=""):
        self.pts = [(float(x), float(y)) for x, y in pts]
        self.pipes = list(pipes)
        self.rack = rack
        self.ends = list(ends)
        self.role = role
        self.bridges = []
        self.width = group_width(pipes)
        self.radius = group_radius(pipes)
        self._centre = None

    def set_pts(self, pts):
        self.pts = [(float(x), float(y)) for x, y in pts]
        self._centre = None

    def centre(self):
        if self._centre is None:
            self._centre = LineString(fillet(self.pts, self.radius))
        return self._centre

    @property
    def length(self):
        return self.centre().length

    def pipe_length(self):
        return self.length * len(self.pipes)

    def add_bridge(self, d0, d1, why):
        """Raises the run from d0 to d1 (metres along its centre line). Joins
        with raised parts it touches or nearly touches."""
        total = self.length
        d0, d1 = max(0.0, d0), min(total, d1)
        if d0 < MIN_GROUND_M * 0.6:
            d0 = 0.0
        if total - d1 < MIN_GROUND_M * 0.6:
            d1 = total
        if d1 - d0 < 2.0:
            return False
        merged, keep = [d0, d1, why], []
        for b in self.bridges:
            if b[1] < merged[0] - MIN_GROUND_M or b[0] > merged[1] + MIN_GROUND_M:
                keep.append(b)
            else:
                merged[0], merged[1] = min(merged[0], b[0]), max(merged[1], b[1])
        keep.append(merged)
        keep.sort(key=lambda b: b[0])
        self.bridges = keep
        return True

    def raised_at(self, d, margin=0.0):
        return any(b[0] - margin <= d <= b[1] + margin for b in self.bridges)

    def parts(self):
        """The run cut at its raised parts: [(centre line part, raised)]."""
        c = self.centre()
        out, d = [], 0.0
        for d0, d1, _ in self.bridges:
            if d0 - d > 0.3:
                out.append((substring(c, d, d0), False))
            out.append((substring(c, d0, d1), True))
            d = d1
        if c.length - d > 0.3:
            out.append((substring(c, d, c.length), False))
        return out

    def ground_parts(self):
        return [p for p, up in self.parts() if not up and p.length > 0.8]

    def ground_outlines(self):
        """One obstacle outline per part of the run on the ground."""
        return [p.buffer(self.width / 2 + PIPE_CLEAR_M, cap_style="flat", join_style="round")
                for p in self.ground_parts()]

    def ground_stretches(self):
        """(from, to) along the centre line of each part on the ground."""
        out, d = [], 0.0
        for d0, d1, _ in self.bridges:
            if d0 - d > 0.3:
                out.append((d, d0))
            d = d1
        if self.length - d > 0.3:
            out.append((d, self.length))
        return out


def truss_variant(run):
    """The truss variant of a run: one of TRUSS_VARIANTS for a rack, chosen
    from where it starts (so the same rack always gets the same one), and
    "under" for a single pipe."""
    if not run.rack:
        return "under"
    x, y = run.pts[0]
    k = int(abs(round(x * 10.0)) * 31 + abs(round(y * 10.0)) * 17 + len(run.pipes))
    return TRUSS_VARIANTS[k % len(TRUSS_VARIANTS)]


def draw_truss(L, part, hw, v, phase=0):
    """A truss along a part: two chords hw from the centre line, posts across
    and diagonals between the chords (starting on the other chord when
    phase is 1)."""
    chords = []
    for s in (-hw, hw):
        ch = part.offset_curve(s, join_style="round")
        if not ch.is_empty and ch.geom_type == "LineString":
            L.line("overheads", ch, 0.2, v)
            chords.append(ch)
    step = max(2.4, 2 * hw)
    n = max(2, int(round(part.length / step)))
    for i in range(n + 1):
        L.line("overheads", perp_segment(part, part.length * i / n, hw), 0.14, v)
    if len(chords) == 2:
        for i in range(n):
            a = chords[(i + phase) % 2].interpolate(i / n, normalized=True)
            b = chords[(i + 1 + phase) % 2].interpolate((i + 1) / n, normalized=True)
            L.line("overheads", LineString([a, b]), 0.1, v * 0.85)


def draw_bridge(L, part, run, rng):
    """A raised part of a run: a soft shadow on the ground, a truss (two
    chords with posts and diagonals) and the pipes, and a support with
    footings at each end. The truss is under the pipes, over them, or both
    (truss_variant); a truss over the pipes is drawn a little lighter so it
    reads against them. A long part is drawn as spans of SUPPORT_M or less,
    so it has a support at that pitch. All but the shadow is in the
    overheads sublayer."""
    spans = int(np.ceil(part.length / SUPPORT_M))
    if spans > 1:
        for i in range(spans):
            draw_bridge(L, substring(part, part.length * i / spans, part.length * (i + 1) / spans), run, rng)
        return
    hw = run.width / 2 + (0.7 if run.rack else 0.45)
    sh = affinity.translate(part, -LIGHT[0] * 2.2, -LIGHT[1] * 2.2)
    L.fill("groundlines", sh.buffer(hw + 0.3, cap_style="flat"), 0.0, 0.26)
    variant = truss_variant(run)
    if variant in ("under", "both"):
        draw_truss(L, part, hw, TRUSS_V * (0.8 if variant == "both" else 1.0))
    draw_pipe_set(L, "overheads", part, run.pipes, rng)
    if variant in ("over", "both"):
        draw_truss(L, part, hw - (0.15 if variant == "both" else 0.0), TRUSS_V_OVER, phase=1 if variant == "both" else 0)
    for d in (0.4, part.length - 0.4):
        post = perp_segment(part, d, hw + 0.9)
        L.line("overheads", post, 0.9, TRUSS_V * 0.8)
        L.line("overheads", post, 0.3, 0.46)
        for p in post.coords:
            L.fill("overheads", Point(p).buffer(0.7, cap_style="square"), 0.44)


def draw_run(L, run, rng):
    """Draws a run: its parts on the ground in the interiors sublayer, its
    raised parts as pipe bridges."""
    for part, up in run.parts():
        if up:
            draw_bridge(L, part, run, rng)
        else:
            draw_pipe_set(L, "interiors", part, run.pipes, rng, runners=run.width / 2 + 0.2 if run.rack else None)


def strut_frame(L, F, x0, y0, x1, y1, v=0.36, sub="overheads"):
    """A steel lattice: a frame with cross braces, drawn as an overhead."""
    Q = Quads(F.c, F.ang)
    for (xa, ya), (xb, yb) in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        Q.line(xa, ya, xb, yb, 0.22, v)
    n = max(1, int(round((x1 - x0) / max(y1 - y0, 1.0))))
    for i in range(n):
        xa, xb = x0 + (x1 - x0) * i / n, x0 + (x1 - x0) * (i + 1) / n
        Q.line(xa, y0, xb, y1, 0.1, v * 0.85)
        Q.line(xa, y1, xb, y0, 0.1, v * 0.85)
        if i:
            Q.line(xa, y0, xa, y1, 0.14, v)
    Q.flush(L, sub, None)


def conveyor(L, line):
    """A covered conveyor gantry, drawn as an overhead."""
    L.line("overheads", line, 2.8, 0.0, 0.45)
    L.line("overheads", line, 2.2, 0.26)
    L.line("overheads", line, 0.08, 0.4)
    for d in np.arange(0.0, line.length, 2.0):
        L.line("overheads", perp_segment(line, d, 1.1), 0.08, 0.38)
