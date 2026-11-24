"""Process plants, built network-first (section 3 of the districts brief and
Yosqi's process plant reference aerial): the pipe network is laid out first
and every node hangs on it, so pipes are long, connected and end at
equipment.

A plant is built in the largest free rectangle of its compound, in this
order:

1. Internal roads: cross roads every COL_M or so, and in a deep plant
   (TWO_ROWS_M) a spine road along the middle. They cut the plant into
   cells and are CLEAR_M wide corridors that stay free.
2. Nodes, one per cell: a control building with a substation and a yard, a
   tank bund (round tanks and an empty pad), a pool with its pump house,
   1 to 3 process units, equipment yards.
3. The trunk rack: a ring round the plant's perimeter, or a U that starts
   at the control building and ends in a process unit. Its pipes turn
   every corner together. It is overhead from end to end.
4. Rungs: racks along the cross roads from one long side of the trunk to
   the other, so the racks make loops round the blocks. Overhead too, over
   the edge of their road.
5. Branches from the racks to every node, peeling off on concentric
   elbows: a branch rack into each process unit, a small pipe from every
   tank and from the pool, a branch from the control building, a utility
   pipe into each yard.
6. Long single pipes between distant nodes along the road edges, with two
   45 degree kinks (a jog) where the lane has room: the large bright pipe
   from the pool's pump house to the farthest process unit, the bund's
   manifold to a unit, and 2 or 3 parallel pipes between units.
7. The manifolds in each unit: an air-cooler bank (a frame of about 12
   tubes over fans), the branch pipes wrapped round it as nested
   rectangular loops with round corners, a row of pumps on a header,
   exchangers with U-loops, a vessel where the large pipe ends.
8. Expansion loops on the long straight runs of the racks, where a bay
   beside a node leaves room.

Passability. Pipes and racks on the ground block mechas, so a connected
network could wall a plant off. The long-haul racks (OVERHEAD_ROLES: the
trunk and the rungs, and the links between plants) are trussed racks on
supports, drawn in the overheads sublayer with no obstacle: mechas pass
under them anywhere. The other runs (branches, the long single pipes, tank
and pool pipes) are on the ground and are obstacles. Each of them is raised
as a pipe bridge (overheads sublayer, no obstacle, at least GAP_M long, a
support at each end) wherever it crosses an internal road, and so that no
stretch on the ground is longer than MAX_GROUND_M. Then the plant is checked
twice.

The player's check: buildings, bund walls, pools and the pipe obstacles are
rasterised, the free ground is shrunk by SHRINK_M (a mecha's half width and
a margin) and flood-filled from the ground outside the plant. Every open
area of MIN_OPEN_M2 or more must be reached, and every salvage source must
be within REACH_M of reached ground. Where that fails, the run in the way
is raised there, and the check runs again.

The NPCs' check (npc_access, over all plants together): NPCs plan their way
on the game's route grid, squares of ROUTE_CELL_M that are closed when an
obstacle outline grown by ROUTE_GROW_M overlaps them. The check builds the
same grid and floods it from the ground far from the plants. Every open
square in or beside a plant must be reached, every node must have a reached
square within NPC_NODE_M and every salvage source one within NPC_SOURCE_M.
Where that fails, the cheapest way in is found (by the length of run that
must be raised to open its squares) and those runs are raised. Last, for
each salvage source the check finds the square the game would send an NPC
to (the source's own square, or the first open one in the rings round it).
If that square is not reached or is more than NPC_GOAL_M from the source,
the source is moved into an open, reached square nearby (place_sources).

Across a road, the trunks of two plants that face each other are joined by
an overhead rack (link_plants), so an estate reads as one network.
"""
import heapq

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from shapely.geometry import LineString, Point, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from shapely.prepared import prep

import kit
import style
from frame import PLAY_HALF_M
from obstacles import PIPE, POOL
from pipes import (LIGHT, LOOP_DEPTH_M, LOOP_WIDTH_M, PIPE_CLEAR_M, RUNNER_V, Run, draw_run, group_radius,
                   group_width, loop_points, perp_segment, rack_pipes, single_pipe)

## Every pass-under gap (a raised part of a run that is otherwise on the
## ground) is at least this long. An NPC needs about 24 m between obstacle
## outlines.
GAP_M = 26.0
## Internal roads: the corridor kept clear along each one, the paved width.
CLEAR_M = 14.0
ROAD_W_M = 8.0
## A run is raised from 1 m before a road corridor to 1 m after it.
BRIDGE_PAD_M = 1.0
## No part of a run on the ground is longer than this.
MAX_GROUND_M = 70.0
## Cells: about this wide; a plant deeper than TWO_ROWS_M has two rows.
COL_M = 62.0
TWO_ROWS_M = 98.0
MIN_W_M, MIN_H_M = 100.0, 58.0
MIN_CELL_M = (24.0, 21.0)
## Rack edge to the plant rectangle's edge; rack edge to a node.
EDGE_M = 3.0
ALLEY_M = 6.0
## Band for the long single pipes between a road corridor and the nodes (two
## rows), or between the far rack and the nodes (one row); its two tracks.
LANE_BAND_M = 6.0
LANE_ALLEY_M = 8.0
LANE_SLOT0_M = 1.9
LANE_PITCH_M = 2.7
## A rung runs overhead along its cross road, this far inside the corridor's
## edge.
RUNG_SIDE_M = 1.0
## Roles of the long-haul racks: they are overhead from end to end (a
## trussed rack on supports, no obstacle).
OVERHEAD_ROLES = ("trunk", "rung")
## Free strip left beside a node where the cell has room (an expansion loop
## and the node's salvage sources go there).
BAY_M = 17.0
LOOP_MIN_RUN_M = 36.0
## The passability check.
SHRINK_M = 6.0
MIN_OPEN_M2 = 400.0
REACH_M = 8.0
CHECK_CELL_M = 0.5
CHECK_MARGIN_M = 24.0
REPAIR_TRIES = 10
## Ground kept free round a start, spawn, exit or cyst marker of the master
## scene that lies in a compound.
KEEP_CLEAR_M = 14.0
## Trunks of two plants this close (m) are joined across the road.
LINK_MAX_M = 75.0
## The game's route grid: squares this large from the play area's corner; a
## square is closed when an obstacle outline grown by ROUTE_GROW_M overlaps
## it. ROUTE_SLACK_M covers the simplifying of the outlines.
ROUTE_CELL_M = 12.5
ROUTE_GROW_M = 2.0
ROUTE_SLACK_M = 0.4
## For a goal in a closed square the game picks an open square at most this
## many squares away (BuildingField.ROUTE_OPEN_SEARCH).
ROUTE_OPEN_SEARCH = 4
## The NPCs' check: squares with their centre this close to a compound are
## checked; ground this far from every compound is taken as reached; a node
## needs a reached square (its centre) within NPC_NODE_M and a salvage source
## one within NPC_SOURCE_M.
NPC_ZONE_M = 20.0
NPC_FAR_M = 60.0
NPC_NODE_M = 20.0
NPC_SOURCE_M = 17.0
NPC_TRIES = 8
## A salvage source must be this close to the centre of the square the game
## sends an NPC to for it (an NPC counts as there within 20 m). One that is
## not is moved, at most NPC_MOVE_M, into an open square; candidates are
## tried on a grid of NPC_MOVE_STEP_M.
NPC_GOAL_M = 15.0
NPC_MOVE_M = 14.0
NPC_MOVE_STEP_M = 1.5
HALF = CLEAR_M / 2


# ------------------------------------------------------------------ frames

class Canon:
    """The plant rectangle's own frame: u along its long side (0..W), v
    across (0..H), mirrored either way for variety."""

    def __init__(self, F, rect, flip_u, flip_v):
        self.F = F
        self.x0, self.y0, self.x1, self.y1 = rect
        self.swap = (self.y1 - self.y0) > (self.x1 - self.x0)
        self.W = max(self.x1 - self.x0, self.y1 - self.y0)
        self.H = min(self.x1 - self.x0, self.y1 - self.y0)
        self.flip_u, self.flip_v = flip_u, flip_v

    def pt(self, u, v):
        if self.flip_u:
            u = self.W - u
        if self.flip_v:
            v = self.H - v
        x, y = (self.x0 + v, self.y0 + u) if self.swap else (self.x0 + u, self.y0 + v)
        return self.F.pt(x, y)

    def pts(self, uv):
        return [self.pt(u, v) for u, v in uv]

    def rect(self, u0, v0, u1, v1):
        return Polygon(self.pts([(u0, v0), (u1, v0), (u1, v1), (u0, v1)]))

    def line(self, uv):
        return LineString(self.pts(uv))

    def ang(self, du, dv):
        a, b = self.pt(0.0, 0.0), self.pt(du, dv)
        return float(np.arctan2(b[1] - a[1], b[0] - a[0]))


class Sub:
    """A node's frame: p along u from the node's west edge, q from its edge
    beside the rack towards its far (lane) side. The node is pw x ph."""

    def __init__(self, C, u0, v_rack, sign, pw, ph):
        self.C, self.u0, self.v_rack, self.sign, self.pw, self.ph = C, u0, v_rack, sign, pw, ph

    def uv(self, p, q):
        return (self.u0 + p, self.v_rack + self.sign * q)

    def pt(self, p, q):
        return self.C.pt(*self.uv(p, q))

    def pts(self, pq):
        return [self.pt(p, q) for p, q in pq]

    def rect(self, p0, q0, p1, q1):
        return Polygon(self.pts([(p0, q0), (p1, q0), (p1, q1), (p0, q1)]))

    def line(self, pq):
        return LineString(self.pts(pq))

    def box(self):
        return self.rect(0.0, 0.0, self.pw, self.ph)

    def ang(self, dp, dq):
        a, b = self.pt(0.0, 0.0), self.pt(dp, dq)
        return float(np.arctan2(b[1] - a[1], b[0] - a[0]))


class Cell:
    def __init__(self, c, r, ua, ub, va, vb, rack_sign, anchor_east, lane, v_line):
        self.c, self.r, self.ua, self.ub, self.va, self.vb = c, r, ua, ub, va, vb
        self.rack_sign, self.anchor_east, self.lane, self.v_line = rack_sign, anchor_east, lane, v_line
        self.w, self.h = ub - ua, vb - va

    def sub(self, C, pw, ph):
        pw, ph = min(pw, self.w), min(ph, self.h)
        u0 = self.ub - pw if self.anchor_east else self.ua
        v_rack = self.va if self.rack_sign < 0 else self.vb
        return Sub(C, u0, v_rack, -self.rack_sign, pw, ph)


class Lane:
    """A band for long pipes along a road or rack, with two tracks."""

    def __init__(self, v_edge, sign):
        self.v_edge, self.sign = v_edge, sign
        self.used = {0: [], 1: []}

    def v(self, s):
        return self.v_edge + self.sign * (LANE_SLOT0_M + LANE_PITCH_M * s)

    def free(self, s, lo, hi):
        return all(hi < a or lo > b for a, b in self.used[s])

    def take(self, s, lo, hi):
        self.used[s].append((min(lo, hi) - 1.5, max(lo, hi) + 1.5))


class Node:
    def __init__(self, kind, cell, S):
        self.kind, self.cell, self.S = kind, cell, S
        self.ports = {}
        self.bay = cell.w - S.pw
        # What an NPC must be able to get near (None: nothing).
        self.target = None

    def bay_spot(self, i):
        """Node frame position of the i-th salvage source beside the node: in
        its bay if it has one, else on the verge of the cross road."""
        S = self.S
        off = 3.2 if self.bay >= 5.0 else self.bay + 2.0
        p = -off if self.cell.anchor_east else S.pw + off
        return p, max(3.0, S.ph - 2.5 - 4.6 * i)


# ------------------------------------------------------------- work rectangle

def largest_rect(mask):
    """The largest all-true rectangle of a boolean grid: (i0, j0, i1, j1)."""
    h, w = mask.shape
    heights = np.zeros(w, int)
    best = (0, 0, 0, 0, 0)
    for i in range(h):
        heights = np.where(mask[i], heights + 1, 0)
        stack = []
        for j in range(w + 1):
            cur = int(heights[j]) if j < w else 0
            start = j
            while stack and stack[-1][1] > cur:
                s, hh = stack.pop()
                if hh * (j - s) > best[0]:
                    best = (hh * (j - s), i - hh + 1, s, i + 1, j)
                start = s
            stack.append((start, cur))
    return best[1:]


def work_rect(F, free, grid=2.0):
    """The largest rectangle in the frame F that lies inside the free ground
    (local x0, y0, x1, y1), or None."""
    loc = F.local(free)
    n, m = int(F.w // grid), int(F.h // grid)
    if n < 4 or m < 4:
        return None
    im = Image.new("1", (n, m))
    d = ImageDraw.Draw(im)
    for g in style.polys(loc):
        d.polygon([((x - F.x0) / grid, (y - F.y0) / grid) for x, y in g.exterior.coords], fill=1)
        for hole in g.interiors:
            d.polygon([((x - F.x0) / grid, (y - F.y0) / grid) for x, y in hole.coords], fill=0)
    i0, j0, i1, j1 = largest_rect(np.asarray(im, bool))
    if i1 - i0 < 4 or j1 - j0 < 4:
        return None
    rect = [F.x0 + j0 * grid, F.y0 + i0 * grid, F.x0 + j1 * grid, F.y0 + i1 * grid]
    for _ in range(14):
        if free.contains(F.rect(*rect)):
            return tuple(rect)
        rect = [rect[0] + 0.5, rect[1] + 0.5, rect[2] - 0.5, rect[3] - 0.5]
    return None


# ------------------------------------------------------------ the check

class Reach:
    """Where a mecha can get to in and round a plant: the free ground shrunk
    by SHRINK_M, flood-filled from outside the plant."""

    def __init__(self, area, blockers, walls):
        c = CHECK_CELL_M
        x0, y0, x1, y1 = area.buffer(CHECK_MARGIN_M).bounds
        self.x0, self.y0 = x0, y0
        nx, ny = int((x1 - x0) / c) + 1, int((y1 - y0) / c) + 1
        im = Image.new("1", (nx, ny))
        d = ImageDraw.Draw(im)
        px = lambda coords: [((x - x0) / c, (y - y0) / c) for x, y in coords]
        for g in blockers:
            for p in style.polys(g):
                d.polygon(px(p.exterior.coords), fill=1)
        for ring in walls:
            d.line(px(ring.coords), fill=1, width=max(1, int(round(0.9 / c))))
        self.blocked = np.asarray(im, bool)
        im = Image.new("1", (nx, ny))
        ImageDraw.Draw(im).polygon(px(area.exterior.coords), fill=1)
        self.inside = np.asarray(im, bool)
        free = ~self.blocked
        er = ndi.distance_transform_edt(free) * c >= SHRINK_M
        lab, n = ndi.label(er, structure=np.ones((3, 3)))
        seeds = set(int(v) for v in np.unique(lab[er & ~self.inside]) if v > 0)
        self.reached = np.isin(lab, list(seeds))
        self.any = bool(self.reached.any())
        if self.any:
            self.dist, idx = ndi.distance_transform_edt(~self.reached, return_indices=True)
            self.near_i, self.near_j = idx
        else:
            self.dist = np.full(lab.shape, 1e9)
            self.near_i, self.near_j = np.indices(lab.shape)
        self.pockets = []
        sizes = np.bincount(lab.ravel(), minlength=n + 1)
        for i in range(1, n + 1):
            if i in seeds or sizes[i] < 4:
                continue
            comp = lab == i
            grown = ndi.distance_transform_edt(~comp) * c <= SHRINK_M
            open_m2 = float((grown & free & self.inside).sum()) * c * c
            if open_m2 >= MIN_OPEN_M2:
                ii, jj = np.nonzero(comp)
                k = int(np.argmin(self.dist[ii, jj]))
                self.pockets.append((self.xy(ii[k], jj[k]), open_m2))

    def xy(self, i, j):
        return (self.x0 + (j + 0.5) * CHECK_CELL_M, self.y0 + (i + 0.5) * CHECK_CELL_M)

    def ij(self, x, y):
        i = int(np.clip((y - self.y0) / CHECK_CELL_M, 0, self.blocked.shape[0] - 1))
        j = int(np.clip((x - self.x0) / CHECK_CELL_M, 0, self.blocked.shape[1] - 1))
        return i, j

    def gap(self, x, y):
        """Distance (m) from a point to reached ground."""
        return float(self.dist[self.ij(x, y)]) * CHECK_CELL_M if self.any else 1e9

    def nearest(self, x, y):
        i, j = self.ij(x, y)
        return self.xy(self.near_i[i, j], self.near_j[i, j])

    def is_blocked(self, x, y):
        return bool(self.blocked[self.ij(x, y)])


def raise_span(run, d0, d1, why):
    """Raises a run from d0 to d1 (metres along its centre line), made at
    least GAP_M long and moved to stay on the run. Returns whether anything
    was raised."""
    total = run.length
    if d1 - d0 < GAP_M:
        mid = (d0 + d1) / 2
        d0, d1 = mid - GAP_M / 2, mid + GAP_M / 2
    if d0 < 0.0:
        d0, d1 = 0.0, d1 - d0
    if d1 > total:
        d0, d1 = max(0.0, d0 - (d1 - total)), total
    return run.add_bridge(d0, d1, why)


# ---------------------------------------------------------------- the plant

def unit_dims(cw, ch, wr, tubes=12):
    """Sizes of a process unit that fits cw x ch, for branch pipes wr wide;
    None if it cannot fit."""
    gap = wr / 2 + 1.2
    bw, bh, ex, pumps = 13.0, 0.7 * tubes + 0.6, 9.5, True
    width = lambda: 2.0 + ex + 2 * wr + 2.4 + bw
    if width() > cw:
        ex = 0.0
    if width() > cw:
        bw = cw - (2.0 + 2 * wr + 2.4)
    if bw < 7.0:
        return None
    height = lambda: 2 * wr + 4.0 + bh + (4.5 if pumps else 0.0)
    if height() > ch:
        bh = max(4.8, ch - (2 * wr + 4.0 + 4.5))
    if height() > ch:
        pumps = False
        bh = min(0.7 * tubes + 0.6, max(4.8, ch - (2 * wr + 4.0)))
    if height() > ch + 1e-6:
        return None
    d = {"gap": gap, "ex": ex, "pumps": pumps}
    d["q_t"] = wr / 2 + 0.8
    d["bq0"] = d["q_t"] + gap
    d["bq1"] = d["bq0"] + bh
    d["q_b"] = d["bq1"] + gap
    q_end = d["q_b"] + wr / 2 + 0.8
    d["q_h"], d["q_p"] = q_end + 0.9, q_end + 2.9
    d["ph"] = q_end + (4.5 if pumps else 0.0)
    d["p_in"] = 1.0 + ex + wr / 2
    d["bp0"] = d["p_in"] + gap
    d["bp1"] = d["bp0"] + bw
    d["p_r"] = d["bp1"] + gap
    d["pw"] = d["p_r"] + wr / 2 + 1.0
    d["vessel"] = pumps and d["pw"] >= 26.0
    d["p_big"] = d["pw"] - 10.2
    d["p_link"] = d["p_big"] - 2.6 if d["vessel"] else d["pw"] - 3.0
    d["p_h0"] = d["p_in"] + wr / 2 + 1.5
    return d


def capsule(L, a, b, dia, v):
    """A horizontal vessel or exchanger seen from above."""
    axis = LineString([a, b])
    body = axis.buffer(dia / 2, cap_style="round")
    sh = LineString([(a[0] - LIGHT[0] * 0.35, a[1] - LIGHT[1] * 0.35), (b[0] - LIGHT[0] * 0.35, b[1] - LIGHT[1] * 0.35)])
    L.fill("interiors", sh.buffer(dia / 2, cap_style="round"), 0.0, 0.35)
    L.fill("interiors", body, v)
    L.line("interiors", body.exterior, 0.06, 0.2)
    for t in (0.2, 0.5, 0.8):
        L.line("interiors", perp_segment(axis, axis.length * t, dia / 2 + 0.05), 0.1, min(v * 1.4, 0.6))


class Plant:
    def __init__(self, site, cp, rect):
        self.site, self.cp, self.rng = site, cp, cp.rng
        self.C = Canon(cp.F, rect, self.rng.random() < 0.5, self.rng.random() < 0.5)
        self.runs, self.nodes, self.cells = [], {}, {}
        self.blockers, self.walls, self.pools, self.pads, self.houses, self.yards = [], [], [], [], [], []
        self.sources, self.tees, self.occupied, self.ops = [], [], [], []
        self.manifold_m = 0.0
        self.near = None
        self.npc_stats = {}
        self.markers = [(x, y) for _, x, y in getattr(site, "markers", []) if cp.area.contains(Point(x, y))]
        self.stats = {}

    # -- layout ------------------------------------------------------------

    def layout(self):
        C, rng = self.C, self.rng
        W, H = C.W, C.H
        if W < MIN_W_M or H < MIN_H_M:
            return False
        self.two = H >= TWO_ROWS_M
        self.cols = max(2, int(round(W / COL_M)))
        if not self.two and self.cols < 3:
            return False
        self.trunk_pipes = rack_pipes(rng, int(rng.integers(4, 6)), max_width=5.5)
        w = self.w = group_width(self.trunk_pipes)
        self.vT, self.vB = EDGE_M + w / 2, H - EDGE_M - w / 2
        self.uL, self.uR = EDGE_M + w / 2, W - EDGE_M - w / 2
        self.cross = [W * k / self.cols + rng.uniform(-3, 3) for k in range(1, self.cols)]
        self.vS = H / 2 + rng.uniform(-0.03, 0.03) * H if self.two else None
        allowed = list(range(1, self.cols if self.two else self.cols - 1))
        self.rungs = {k: rack_pipes(rng, 3, dia=(0.4, 0.8)) for k in allowed if rng.random() < 0.7}
        if allowed and not self.rungs:
            self.rungs[int(rng.choice(allowed))] = rack_pipes(rng, 3, dia=(0.4, 0.8))
        if self.two:
            lanes = (Lane(self.vS - HALF, -1), Lane(self.vS + HALF, +1))
        else:
            lanes = (Lane(self.vB - w / 2, -1),)
        for c in range(self.cols):
            for r in range(2 if self.two else 1):
                if c == 0:
                    ua = self.uL + w / 2 + ALLEY_M
                else:
                    ua = self.cross[c - 1] + HALF + 1.5
                ub = self.uR - w / 2 - ALLEY_M if c == self.cols - 1 else self.cross[c] - HALF - 1.5
                if not self.two:
                    va, vb = self.vT + w / 2 + ALLEY_M, self.vB - w / 2 - LANE_ALLEY_M
                elif r == 0:
                    va, vb = self.vT + w / 2 + ALLEY_M, self.vS - HALF - LANE_BAND_M
                else:
                    va, vb = self.vS + HALF + LANE_BAND_M, self.vB - w / 2 - ALLEY_M
                if ub - ua < MIN_CELL_M[0] or vb - va < MIN_CELL_M[1]:
                    return False
                self.cells[(c, r)] = Cell(c, r, ua, ub, va, vb, -1 if r == 0 else 1, c == self.cols - 1,
                                          lanes[r], self.vT if r == 0 else self.vB)
        self.kinds = self.assign()
        cell = self.cells.get((0, 1))
        self.u_shape = bool(self.two and self.kinds.get((0, 0)) == "control" and self.kinds.get((0, 1)) == "unit"
                            and rng.random() < 0.5 and unit_dims(cell.w, cell.h, w) is not None)
        self.corridors = [C.rect(u - HALF, -40.0, u + HALF, H + 40.0) for u in self.cross]
        self.axes = [C.line([(u, -60.0), (u, H + 60.0)]) for u in self.cross]
        if self.two:
            self.corridors.append(C.rect(-40.0, self.vS - HALF, W + 40.0, self.vS + HALF))
            self.axes.append(C.line([(-60.0, self.vS), (W + 60.0, self.vS)]))
        return True

    def assign(self):
        """Which node goes in which cell: the control building at the trunk's
        start, the bund beside the far corner, the pool far from a unit."""
        cols = self.cols
        if self.two:
            kinds = {(0, 0): "control", (cols - 1, 0): "bund", (0, 1): "unit", (cols - 1, 1): "pool"}
            rest = ["unit", "yard", "bund", "unit", "yard", "yard"]
            i = 0
            for c in range(1, cols - 1):
                for r in (0, 1):
                    kinds[(c, r)] = rest[i % len(rest)]
                    i += 1
            return kinds
        row = {3: ["pool", "bund", "unit"], 4: ["control", "pool", "bund", "unit"]}.get(cols)
        if row is None:
            row = ["control", "pool", "unit", "bund"] + ["yard"] * (cols - 5) + ["unit"]
        return {(c, 0): k for c, k in enumerate(row)}

    # -- helpers -----------------------------------------------------------

    def add_run(self, uv, pipes, rack, ends, role):
        run = Run(self.C.pts(uv), pipes, rack, ends, role)
        run.uv = [(float(u), float(v)) for u, v in uv]
        self.runs.append(run)
        return run

    def q_line(self):
        return -(ALLEY_M + self.w / 2)

    def q_near(self):
        return -(ALLEY_M + 0.35)

    def source(self, kind, S, p, q, ang=None):
        x, y = S.pt(p, q)
        self.sources.append([kind, x, y, S.ang(1, 0) if ang is None else ang])
        self.occupied.append(Point(x, y).buffer(2.6))

    def node(self, kind, cell, S):
        n = Node(kind, cell, S)
        self.nodes[(cell.c, cell.r)] = n
        return n

    def inner(self, S, pq, pipes):
        """A pipe group inside a node (drawn with the node, no obstacle of its
        own)."""
        run = Run(S.pts(pq), pipes)
        self.manifold_m += run.pipe_length()
        return run

    # -- nodes -------------------------------------------------------------

    def make_nodes(self):
        for key in sorted(self.cells):
            cell, kind = self.cells[key], self.kinds[key]
            if kind == "unit":
                fed = self.u_shape and key == (0, 1)
                pipes = self.trunk_pipes if fed else rack_pipes(self.rng, 3, dia=(0.4, 0.8))
                if not self.unit(cell, pipes, fed):
                    self.yard(cell)
            elif kind == "bund":
                self.bund(cell)
            elif kind == "pool":
                self.pool(cell)
            elif kind == "control":
                self.control(cell)
            else:
                self.yard(cell)

    def unit(self, cell, pipes, fed):
        rng, C = self.rng, self.C
        wr = group_width(pipes)
        d = unit_dims(cell.w - BAY_M, cell.h, wr) if cell.w - BAY_M >= 30.0 else None
        d = d or unit_dims(cell.w, cell.h, wr)
        if d is None:
            return False
        S = cell.sub(C, d["pw"], d["ph"])
        n = self.node("unit", cell, S)
        pad = S.box()
        n.target = pad
        self.blockers.append(pad)
        self.pads.append(pad)
        self.occupied.append(pad.buffer(1.0))
        n.ports["rack"] = {"uv": S.uv(d["p_in"], 0.0)}
        if d["pumps"]:
            n.ports["link"] = {"uv": S.uv(d["p_link"], d["ph"]), "lane": cell.lane, "used": False, "pipes": None}
        if d["vessel"]:
            n.ports["big"] = {"uv": S.uv(d["p_big"], d["ph"]), "lane": cell.lane, "used": False, "pipes": None}
        if not fed:
            lead = group_radius(pipes) + 1.5
            ql = self.q_line()
            self.add_run([S.uv(d["p_in"] + lead, ql), S.uv(d["p_in"], ql), S.uv(d["p_in"], 0.0)], pipes, True,
                         ("tee", "equip"), "branch")
            self.tees.append(S.uv(d["p_in"], ql))
        loops = self.inner(S, [(d["p_in"], 0.0), (d["p_in"], d["q_b"]), (d["p_r"], d["q_b"]), (d["p_r"], d["q_t"]),
                               (d["bp0"] + wr / 2 + 1.0, d["q_t"]), (d["bp0"] + wr / 2 + 1.0, d["bq0"] + 0.5)], pipes)
        kinds = list(rng.choice(["electric_motor", "industrial_pump", "valve_assembly"], size=int(rng.integers(2, 4))))
        for i, k in enumerate(kinds):
            self.source(str(k), S, *n.bay_spot(i), ang=S.ang(0, 1))
        seed = int(rng.integers(1 << 30))
        n_ex = int(rng.integers(2, 4)) if d["ex"] else 0
        ex_q = [d["q_t"] + 1.5 + (d["q_b"] - d["q_t"] - 3.0) * (i + 0.5) / n_ex for i in range(n_ex)]
        pumps_p = list(np.arange(d["p_h0"] + 1.2, d["p_link"] - 2.6, 3.0)) if d["pumps"] else []

        def draw(L):
            r = np.random.default_rng(seed)
            kit.soft_shadow(L, pad, 0.8, 0.4)
            L.fill("interiors", pad, 0.2)
            L.line("interiors", pad.exterior, 0.18, 0.33)
            for q in ex_q:
                capsule(L, S.pt(1.8, q), S.pt(7.0, q), 1.2, 0.4)
                for dq in (-0.3, 0.3):
                    L.line("interiors", S.line([(7.4, q + dq), (d["p_in"] - wr / 2, q + dq)]), 0.22, 0.42)
                L.line("interiors", S.line([(7.4, q - 0.42), (7.4, q + 0.42)]), 0.3, 0.55)
            bank = S.rect(d["bp0"], d["bq0"], d["bp1"], d["bq1"])
            L.fill("interiors", bank, 0.09)
            bw, bh = d["bp1"] - d["bp0"], d["bq1"] - d["bq0"]
            fan_r = min(bh / 2 - 0.5, bw / 6 - 0.3)
            for t in (1 / 6, 3 / 6, 5 / 6):
                c = S.pt(d["bp0"] + bw * t, (d["bq0"] + d["bq1"]) / 2)
                L.fill("interiors", kit.disc(c[0], c[1], fan_r, 18), 0.05)
                L.line("interiors", kit.disc(c[0], c[1], fan_r, 18).exterior, 0.12, 0.26)
                L.fill("interiors", kit.disc(c[0], c[1], 0.35, 8), 0.3)
            n_t = max(6, int(round((bh - 0.6) / 0.7)))
            for i in range(n_t):
                q = d["bq0"] + 0.3 + (bh - 0.6) * (i + 0.5) / n_t
                L.line("interiors", S.line([(d["bp0"] + 0.7, q), (d["bp1"] - 0.7, q)]), 0.26, 0.5, 0.92)
            for p in (d["bp0"] + 0.55, d["bp1"] - 0.55):
                L.line("interiors", S.line([(p, d["bq0"] + 0.2), (p, d["bq1"] - 0.2)]), 0.6, 0.44)
                L.line("interiors", S.line([(p + 0.12, d["bq0"] + 0.3), (p + 0.12, d["bq1"] - 0.3)]), 0.12, 0.62, 0.8)
            L.line("interiors", bank.exterior, 0.2, RUNNER_V * 1.6)
            draw_run(L, loops, r)
            if d["pumps"]:
                link = n.ports["link"]
                hp = link["pipes"] or single_pipe(0.5, 0.4)
                hw = group_width(hp) / 2
                path = [(d["p_link"], d["q_h"]), (d["p_h0"], d["q_h"]), (d["p_h0"], d["q_b"] + wr / 2 - 0.1)]
                if link["used"]:
                    path = [(d["p_link"], d["ph"])] + path
                for p in pumps_p:
                    L.line("interiors", S.line([(p + 0.95, d["q_p"] - 0.4), (p + 0.95, d["q_h"] + hw)]), 0.2, 0.42)
                    L.fill("interiors", S.rect(p - 0.7, d["q_p"] - 0.4, p + 0.5, d["q_p"] + 0.4), 0.3)
                    L.line("interiors", S.line([(p - 0.3, d["q_p"] - 0.4), (p - 0.3, d["q_p"] + 0.4)]), 0.06, 0.16)
                    c = S.pt(p + 0.95, d["q_p"])
                    L.fill("interiors", kit.disc(c[0], c[1], 0.45, 10), 0.36)
                    L.line("interiors", kit.disc(c[0], c[1], 0.45, 10).exterior, 0.06, 0.5)
                draw_run(L, Run(S.pts(path), hp), r)
            if d["vessel"]:
                qv = d["q_h"] + 0.4
                capsule(L, S.pt(d["pw"] - 7.5, qv), S.pt(d["pw"] - 3.5, qv), 2.0, 0.38)
                L.line("interiors", S.line([(d["pw"] - 5.5, qv - 1.0), (d["pw"] - 5.5, d["q_b"] + wr / 2 - 0.1)]), 0.4, 0.4)
                big = n.ports["big"]
                if big["used"]:
                    draw_run(L, Run(S.pts([(d["p_big"], d["ph"]), (d["p_big"], qv), (d["pw"] - 8.4, qv)]), big["pipes"]), r)
        self.ops.append(draw)
        return True

    def bund(self, cell):
        rng, C = self.rng, self.C
        pw = cell.w - BAY_M if cell.w - BAY_M >= 28.0 else cell.w
        S = cell.sub(C, pw, min(cell.h, rng.uniform(28.0, 38.0)))
        pw, ph = S.pw, S.ph
        n = self.node("bund", cell, S)
        box = S.box()
        n.target = box
        self.walls.append(box.exterior)
        self.occupied.append(box.buffer(1.0))
        q_m = ph - 2.0
        dia = float(min(rng.uniform(11.0, 18.0), ph - 7.0, (pw - 3.0) / 2 - 3.5))
        slot = dia + 3.5
        count = max(2, int((pw - 3.0) // slot))
        m0 = (pw - count * slot) / 2
        q_c = q_m / 2 + 0.2
        empty = int(rng.integers(1, count)) if count >= 3 else None
        tanks, pads = [], []
        for i in range(count):
            p = m0 + slot * (i + 0.5)
            x, y = S.pt(p, q_c)
            if i == empty:
                pads.append(kit.disc(x, y, dia / 2 + 0.3))
                continue
            tank = kit.disc(x, y, dia / 2)
            self.cp.building(tank, "tank")
            self.blockers.append(tank)
            self.houses.append(tank)
            tanks.append(p)
            s = 1.0 if i % 2 else -1.0
            self.add_run([S.uv(p, q_c - dia / 2 + 0.2), S.uv(p, self.q_near()), S.uv(p + s * 1.8, self.q_near())],
                         single_pipe(0.4, 0.42), False, ("equip", "tee"), "tank")
            self.tees.append(S.uv(p, self.q_line()))

        def manifold(to_east):
            p_x = pw - 2.2 if to_east else 2.2
            first = tanks[0] if to_east else tanks[-1]
            prefix = [S.uv(first, q_c + dia / 2 - 0.2), S.uv(first, q_m), S.uv(p_x, q_m)]
            others = [[S.uv(p, q_c + dia / 2 - 0.2), S.uv(p, q_m)] for p in tanks if p != first]
            return prefix, S.uv(p_x, ph), others
        n.manifold = manifold
        n.ports["manifold"] = {"uv": S.uv(pw / 2, ph), "lane": cell.lane, "used": False, "pipes": None}
        self.ops.append(lambda L: (kit.pave(L, box, 0.11, 0.9, sub="groundlines", edge=False),
                                   L.line("interiors", box.exterior, 0.7, 0.24),
                                   [(L.fill("interiors", g, 0.2), L.line("interiors", g.exterior, 0.12, 0.32)) for g in pads]))

    def pool(self, cell):
        rng, C = self.rng, self.C
        pw = min(cell.w - BAY_M if cell.w - BAY_M >= 24.0 else cell.w, rng.uniform(26.0, 40.0))
        S = cell.sub(C, pw, min(cell.h, rng.uniform(22.0, 30.0)))
        pw, ph = S.pw, S.ph
        n = self.node("pool", cell, S)
        p_h = 4.5 if cell.anchor_east else pw - 4.5
        rim = S.rect(0.0, 0.0, pw, ph - 2.5)
        basin = S.rect(1.2, 1.2, pw - 1.2, ph - 3.7)
        house = S.rect(p_h - 3.0, ph - 5.0, p_h + 3.0, ph)
        self.cp.building(house, "pumphouse")
        self.houses.append(house)
        n.target = house
        water = basin.difference(house.buffer(0.5))
        self.pools.append(water)
        self.blockers += [basin, house]
        self.occupied.append(S.box().buffer(1.0))
        n.ports["pump"] = {"uv": S.uv(p_h, ph), "lane": cell.lane, "used": False, "pipes": None}
        self.add_run([S.uv(pw / 2, 0.0), S.uv(pw / 2, self.q_near()), S.uv(pw / 2 + 2.0, self.q_near())],
                     single_pipe(0.5, 0.4), False, ("equip", "tee"), "overflow")
        self.tees.append(S.uv(pw / 2, self.q_line()))
        self.source("industrial_pump", S, *n.bay_spot(0))
        seed = int(rng.integers(1 << 30))

        def draw(L):
            r = np.random.default_rng(seed)
            L.fill("interiors", rim, 0.27)
            L.fill("interiors", basin, 0.045)
            L.strip("interiors", orient(basin, 1.0).exterior, 1.4, +1, 0.6, 0.0)
            bx0, by0, bx1, by1 = basin.bounds
            for _ in range(int(basin.area / 60) + 2):
                p = (r.uniform(bx0, bx1), r.uniform(by0, by1))
                crack = LineString([p, (p[0] + r.uniform(-6, 6), p[1] + r.uniform(-6, 6))]).intersection(basin)
                L.line("interiors", crack, 0.06, 0.12, 0.8)
            L.line("interiors", rim.exterior, 0.15, 0.38)
        self.ops.append(draw)

    def control(self, cell):
        rng, C = self.rng, self.C
        S = cell.sub(C, cell.w, cell.h)
        pw, ph = S.pw, S.ph
        n = self.node("control", cell, S)
        bwid, bdep = min(pw - 2.0, rng.uniform(13.0, 19.0)), min(ph * 0.4, rng.uniform(8.0, 11.0))
        house = S.rect(1.0, 1.0, 1.0 + bwid, 1.0 + bdep)
        self.cp.building(house, "control")
        self.houses.append(house)
        n.target = house
        self.blockers.append(house)
        self.occupied.append(house.buffer(1.5))
        pc = 1.0 + bwid / 2
        n.ports["rack"] = {"uv": S.uv(pc, 1.0)}
        if not self.u_shape:
            pipes = rack_pipes(rng, 3, dia=(0.4, 0.6))
            lead = group_radius(pipes) + 1.5
            self.add_run([S.uv(pc, 1.0), S.uv(pc, self.q_line()), S.uv(pc + lead, self.q_line())], pipes, True,
                         ("equip", "tee"), "branch")
            self.tees.append(S.uv(pc, self.q_line()))
        self.source("control_cabinet", S, pc, 1.0 + bdep + 1.5)
        yards = []
        if pw - (1.0 + bwid + 3.5) - 1.0 >= 8.0:
            yards.append(S.rect(1.0 + bwid + 3.5, 1.0, pw - 1.0, 1.0 + bdep))
            self.source("transformer", S, (1.0 + bwid + 3.5 + pw - 1.0) / 2, 1.0 + bdep / 2)
        q0 = 1.0 + bdep + 6.5
        if ph - 1.0 - q0 >= 7.0:
            p1 = min(pw - 1.0, 30.0)
            yards.append(S.rect(1.0, q0, p1, min(ph - 1.0, q0 + 12.0)))
            kinds = list(rng.choice(["cable_drum", "oil_drums", "diesel_generator", "electric_motor"],
                                    size=int(min(3, (p1 - 3.0) // 7.0)), replace=False))
            for i, k in enumerate(kinds):
                self.source(str(k), S, 5.0 + 7.5 * i, q0 + 3.5)
        self.yards += yards
        self.ops.append(lambda L: [(kit.pave(L, g, 0.12, 0.9, sub="interiors"),
                                    kit.fence(L, g.exterior, rng, v=0.26)) for g in yards])

    def yard(self, cell):
        rng, C = self.rng, self.C
        S = cell.sub(C, cell.w, cell.h)
        pw, ph = S.pw, S.ph
        self.node("yard", cell, S)
        g = S.rect(1.0, 1.0, pw - 1.0, ph - 1.0)
        self.yards.append(g)
        p_v = pw * rng.uniform(0.25, 0.4)
        self.add_run([S.uv(p_v + 1.8, self.q_near()), S.uv(p_v, self.q_near()), S.uv(p_v, 3.4)], single_pipe(0.4, 0.42),
                     False, ("tee", "equip"), "utility")
        self.tees.append(S.uv(p_v, self.q_line()))
        self.source("valve_assembly", S, p_v, 4.8, ang=S.ang(0, 1))
        kinds = ["transformer", "control_cabinet", "cable_drum", "oil_drums", "diesel_generator", "electric_motor"]
        picks = list(rng.choice(kinds, size=int(rng.integers(3, 6)), replace=False))
        i = 0
        for q in np.arange(11.0, ph - 4.0, 8.0):
            for p in np.arange(6.0, pw - 5.0, 8.5):
                if i < len(picks):
                    self.source(str(picks[i]), S, p, q)
                    i += 1
        self.ops.append(lambda L: (kit.pave(L, g, 0.12, 0.9, sub="interiors"), kit.fence(L, g.exterior, rng, v=0.26)))

    # -- network -----------------------------------------------------------

    def network(self):
        rng = self.rng
        vT, vB, uL, uR = self.vT, self.vB, self.uL, self.uR
        if self.u_shape:
            uc, vc = self.nodes[(0, 0)].ports["rack"]["uv"]
            ui, vi = self.nodes[(0, 1)].ports["rack"]["uv"]
            self.trunk = self.add_run([(uc, vc), (uc, vT), (uR, vT), (uR, vB), (ui, vB), (ui, vi)], self.trunk_pipes,
                                      True, ("equip", "equip"), "trunk")
        else:
            um = uL + group_radius(self.trunk_pipes) + 3.0
            self.trunk = self.add_run([(um, vT), (uR, vT), (uR, vB), (uL, vB), (uL, vT), (um - 0.2, vT)],
                                      self.trunk_pipes, True, (), "trunk")
        for k, pipes in self.rungs.items():
            u = self.cross[k - 1] + HALF - RUNG_SIDE_M - group_width(pipes) / 2
            lead = group_radius(pipes) + 1.5
            self.add_run([(u + lead, vT), (u, vT), (u, vB), (u + lead, vB)], pipes, True, ("tee", "tee"), "rung")
            self.tees += [(u, vT), (u, vB)]
        units = [n for _, n in sorted(self.nodes.items()) if n.kind == "unit"]
        pools = [n for n in self.nodes.values() if n.kind == "pool"]
        bunds = [n for n in self.nodes.values() if n.kind == "bund"]

        def far(a, cands, port):
            cands = [n for n in cands if port in n.ports and not n.ports[port]["used"]]
            key = lambda n: abs(n.ports[port]["uv"][0] - a[0]) + (25.0 if n.cell.r != a[2] else 0.0)
            return max(cands, key=key) if cands else None

        for pool in pools:
            a = pool.ports["pump"]
            tgt = far((a["uv"][0], 0, pool.cell.r), units, "big")
            if tgt is not None:
                self.route(a, tgt.ports["big"], single_pipe(rng.uniform(1.0, 1.3), rng.uniform(0.46, 0.52)), "main")
        for bund in bunds:
            centre = bund.ports["manifold"]["uv"][0]
            tgt, port = far((centre, 0, bund.cell.r), units, "big"), "big"
            if tgt is None:
                tgt, port = far((centre, 0, bund.cell.r), units, "link"), "link"
            if tgt is None:
                continue
            prefix, uv, others = bund.manifold(tgt.ports[port]["uv"][0] > centre)
            a = bund.ports["manifold"]
            a["uv"] = uv
            if self.route(a, tgt.ports[port], single_pipe(rng.uniform(0.7, 0.9), rng.uniform(0.4, 0.46)), "manifold",
                          prefix):
                for pts in others:
                    self.add_run(pts, single_pipe(0.4, 0.42), False, ("equip", "tee"), "tank")
        for a, b in zip(units[:-1], units[1:]):
            if "link" in a.ports and "link" in b.ports and not a.ports["link"]["used"] and not b.ports["link"]["used"]:
                self.route(a.ports["link"], b.ports["link"], rack_pipes(rng, int(rng.integers(2, 4)), dia=(0.4, 0.5)),
                           "link")
        for k in range(len(self.cross)):
            if rng.random() < 0.6:
                side = -1.0 if rng.random() < 0.5 else 1.0
                x, y = self.C.pt(self.cross[k] + side * 5.6, vT + self.w / 2 + 1.9)
                self.sources.append(["valve_assembly", x, y, self.C.ang(1, 0)])

    def route(self, A, B, pipes, role, prefix=()):
        """A long pipe (or 2 to 3 parallel pipes) from port A to port B: out
        to a lane, along it (with a jog of two 45 degree kinks if the other
        track is free), and in. Returns whether it was made."""
        rng = self.rng
        (ua, va), (ub, vb) = A["uv"], B["uv"]
        if abs(ua - ub) < 2 * group_radius(pipes) + 2.5:
            return False
        lo, hi = min(ua, ub), max(ua, ub)
        prefer = (0, 1) if len(pipes) == 1 else (1, 0)
        pick = None
        for lane in ([A["lane"]] if A["lane"] is B["lane"] else [A["lane"], B["lane"]]):
            for s in prefer:
                if lane.free(s, lo, hi):
                    pick = (lane, s)
                    break
            if pick:
                break
        if pick is None:
            return False
        lane, s = pick
        uv = list(prefix) + [(ua, va), (ua, lane.v(s))]
        step = 1.0 if ub > ua else -1.0
        um = ua + (ub - ua) * rng.uniform(0.35, 0.55)
        jog = hi - lo > 44.0 and lane.free(1 - s, min(um, ub), max(um, ub))
        if jog:
            uv += [(um, lane.v(s)), (um + step * LANE_PITCH_M, lane.v(1 - s))]
            lane.take(s, ua, um + step * LANE_PITCH_M)
            lane.take(1 - s, um, ub)
            s = 1 - s
        else:
            lane.take(s, lo, hi)
        uv += [(ub, lane.v(s)), (ub, vb)]
        self.add_run(uv, pipes, False, ("equip", "equip"), role)
        A["used"] = B["used"] = True
        A["pipes"] = [(-o, d, v) for o, d, v in pipes]
        B["pipes"] = list(pipes)
        return True

    # -- expansion loops -----------------------------------------------------

    def loops(self):
        C = self.C
        centre = (C.W / 2, C.H / 2)
        made = 0
        for run in [r for r in self.runs if r.role in ("trunk", "rung")]:
            hw = run.width / 2
            others = [o.centre().buffer(o.width / 2 + 1.0) for o in self.runs if o is not run]
            taken = self.occupied + self.corridors + others
            new = [run.uv[0]]
            for a, b in zip(run.uv[:-1], run.uv[1:]):
                new += self.loops_on(a, b, hw, run.radius, taken, centre)
                new.append(b)
            if len(new) > len(run.uv):
                made += (len(new) - len(run.uv)) // 4
                run.uv = new
                run.set_pts(C.pts(new))
        return made

    def loops_on(self, a, b, hw, radius, taken, centre):
        """Expansion loops on the straight run a-b: one in each stretch
        between road corridors that is long enough and has a free bay."""
        C = self.C
        a, b = np.asarray(a, float), np.asarray(b, float)
        length = float(np.hypot(*(b - a)))
        if length < LOOP_MIN_RUN_M:
            return []
        u = (b - a) / length
        horiz = abs(u[0]) > 0.5
        cuts = []
        for c in (self.cross if horiz else ([self.vS] if self.two else [])):
            s = (c - (a[0] if horiz else a[1])) * (u[0] if horiz else u[1])
            if 0 < s < length:
                cuts.append((s - HALF - 2.0, s + HALF + 2.0))
        edges = [radius + 3.0] + [v for c in sorted(cuts) for v in c] + [length - radius - 3.0]
        tee_s = [float((np.asarray(t) - a) @ u) for t in self.tees
                 if abs(float((np.asarray(t) - a) @ np.array([-u[1], u[0]]))) < 1.0]
        mid = (a + b) / 2
        inward = 1.0 if (np.asarray(centre) - mid) @ np.array([-u[1], u[0]]) > 0 else -1.0
        half = LOOP_WIDTH_M / 2 + hw + 0.8
        out = []
        for s0, s1 in zip(edges[::2], edges[1::2]):
            if s1 - s0 < LOOP_MIN_RUN_M:
                continue
            done = False
            for t in (0.5, 0.3, 0.7, 0.18, 0.82):
                m = s0 + (s1 - s0) * t
                if m - half < s0 or m + half > s1 or any(abs(ts - m) < half + radius + 1.5 for ts in tee_s):
                    continue
                for side in (inward, -inward):
                    n = np.array([-u[1], u[0]]) * side
                    p0, p1 = a + u * (m - half), a + u * (m + half)
                    foot = Polygon(C.pts([tuple(p0 + n * (hw + 0.3)), tuple(p1 + n * (hw + 0.3)),
                                          tuple(p1 + n * (LOOP_DEPTH_M + hw + 0.8)),
                                          tuple(p0 + n * (LOOP_DEPTH_M + hw + 0.8))]))
                    if not self.cp.area.contains(foot) or any(foot.intersects(g) for g in taken):
                        continue
                    out += loop_points(a, b, m, side)
                    self.occupied.append(foot)
                    taken.append(foot)
                    done = True
                    break
                if done:
                    break
        return out

    # -- pipe bridges ----------------------------------------------------------

    def bridge(self):
        for run in self.runs:
            c = run.centre()
            if run.role in OVERHEAD_ROLES:
                run.add_bridge(0.0, run.length, "overhead")
                continue
            for cor in self.corridors:
                if not c.intersects(cor):
                    continue
                inter = c.intersection(cor)
                for g in getattr(inter, "geoms", [inter]):
                    if g.geom_type != "LineString" or g.length < 1.0:
                        continue
                    d0, d1 = sorted((c.project(Point(g.coords[0])), c.project(Point(g.coords[-1]))))
                    raise_span(run, d0 - BRIDGE_PAD_M, d1 + BRIDGE_PAD_M, "road")
            for x, y in self.markers:
                if c.distance(Point(x, y)) < KEEP_CLEAR_M:
                    d = c.project(Point(x, y))
                    raise_span(run, d - KEEP_CLEAR_M, d + KEEP_CLEAR_M, "marker")
            for s0, s1 in run.ground_stretches():
                if s1 - s0 > MAX_GROUND_M:
                    k = int(np.ceil((s1 - s0 - MAX_GROUND_M) / (MAX_GROUND_M + GAP_M)))
                    for i in range(1, k + 1):
                        d = s0 + (s1 - s0) * i / (k + 1)
                        raise_span(run, d, d, "spacing")

    # -- the passability check ---------------------------------------------------

    def reach(self):
        """The check's picture of the plant: its own blockers, the buildings
        round it (the neighbours' too), and the runs on the ground."""
        if self.near is None:
            zone = self.cp.area.buffer(CHECK_MARGIN_M)
            built = self.site.buildings
            self.near = [built[i].poly for i in self.site.building_tree().query(zone)]
        outlines = [g for run in self.runs for g in run.ground_outlines()]
        return Reach(self.cp.area, self.blockers + self.near + outlines, self.walls)

    def open_between(self, t, q, tried):
        """Raises the runs that lie between an unreached point t and reached
        ground q. Returns how many pipe bridges it added."""
        seg = LineString([t, q])
        added = 0
        for run in self.runs:
            c = run.centre()
            for part in run.ground_parts():
                outline = part.buffer(run.width / 2 + PIPE_CLEAR_M, cap_style="flat")
                if not outline.intersects(seg):
                    continue
                d = c.project(outline.intersection(seg).centroid)
                key = (id(run), round(d / 4.0))
                if key not in tried and raise_span(run, d, d, "repair"):
                    tried.add(key)
                    added += 1
                break
        if added:
            return added
        best = None
        for run in self.runs:
            for part in run.ground_parts():
                dist = part.distance(Point(t))
                if dist < 25.0 and (best is None or dist < best[0]):
                    best = (dist, run, part)
        if best is not None:
            _, run, part = best
            d = run.centre().project(part.interpolate(part.project(Point(t))))
            key = (id(run), round(d / 4.0))
            if key not in tried and raise_span(run, d, d, "repair"):
                tried.add(key)
                return 1
        return 0

    def check(self):
        """Runs the passability check, raising runs until every open area and
        every source is reached (or nothing more helps)."""
        st = {"open_areas_cut_off_first": 0, "sources_cut_off_first": 0, "repair_bridges": 0,
              "open_areas_cut_off": 0, "sources_moved": 0, "sources_dropped": 0, "markers_cut_off": 0}
        tried = set()
        R = None
        for it in range(REPAIR_TRIES):
            R = self.reach()
            bad = [s for s in self.sources if R.gap(s[1], s[2]) > REACH_M]
            bad_m = [m for m in self.markers if R.gap(*m) > REACH_M]
            if it == 0:
                st["open_areas_cut_off_first"] = len(R.pockets)
                st["sources_cut_off_first"] = len(bad)
            if not R.any or not (R.pockets or bad or bad_m):
                break
            added = 0
            for t, _ in R.pockets:
                added += self.open_between(t, R.nearest(*t), tried)
            for t in [(s[1], s[2]) for s in bad] + bad_m:
                added += self.open_between(t, R.nearest(*t), tried)
            st["repair_bridges"] += added
            if not added:
                break
        st["open_areas_cut_off"] = len(R.pockets)
        st["markers_cut_off"] = sum(1 for m in self.markers if R.gap(*m) > REACH_M or R.is_blocked(*m))
        st["markers"] = len(self.markers)
        kept = []
        for s in self.sources:
            if not R.any or R.gap(s[1], s[2]) <= REACH_M:
                kept.append(s)
                continue
            q = np.asarray(R.nearest(s[1], s[2]))
            v = np.asarray(s[1:3]) - q
            p = q + v / max(np.hypot(*v), 1e-9) * (REACH_M - 1.5)
            if not R.is_blocked(*p) and R.gap(*p) <= REACH_M:
                s[1], s[2] = float(p[0]), float(p[1])
                kept.append(s)
                st["sources_moved"] += 1
            else:
                st["sources_dropped"] += 1
        self.sources = kept
        self.check_stats = st

    # -- output ------------------------------------------------------------------

    def emit(self):
        C, cp, site, rng = self.C, self.cp, self.site, self.rng
        ground = cp.free_area().union(C.rect(0.0, 0.0, C.W, C.H))
        roads, self.gates = [], []
        box = C.rect(0.0, 0.0, C.W, C.H)
        for axis in self.axes:
            for g in style.polys(axis.buffer(ROAD_W_M / 2, cap_style="flat").intersection(ground)):
                if g.intersects(box):
                    roads.append(g)
                    ends = axis.intersection(cp.area.exterior)
                    self.gates += [p for p in getattr(ends, "geoms", [ends]) if p.geom_type == "Point"
                                   and g.distance(p) < 1.5]
        cp.draw(lambda L: [kit.pave(L, g, 0.24, 0.9, sub="groundlines") for g in roads])
        for op in self.ops:
            cp.draw(op)
        for g in self.pools:
            site.obstacles.add(POOL, g)
        for g in self.pads:
            site.obstacles.add(PIPE, g)
        for run in self.runs:
            seed = int(rng.integers(1 << 30))
            cp.draw(lambda L, run=run, s=seed: draw_run(L, run, np.random.default_rng(s)))
            cp.draw(lambda L, run=run: end_marks(L, run))
        self.box = box
        cp.space.take(box)
        for g in self.pads + self.yards + [Polygon(ring) for ring in self.walls] +                 [n.S.box() for n in self.nodes.values() if n.kind == "pool"]:
            cp.thing(g)

    def finish(self):
        """Writes what depends on the raised parts, once both checks are
        done: the runs' obstacle outlines, the salvage sources and the
        plant's numbers. (The runs are drawn later, from the same parts.)"""
        C, cp, site = self.C, self.cp, self.site
        n_parts = 0
        for run in self.runs:
            for g in run.ground_outlines():
                site.obstacles.add(PIPE, g)
                n_parts += 1
        for kind, x, y, ang in self.sources:
            cp.source(kind, x, y, ang)
        ends = {"equip": 0, "tee": 0, "open": 0}
        raised = {"overhead": 0, "road": 0, "spacing": 0, "repair": 0, "marker": 0, "npc": 0}
        for run in self.runs:
            for e in run.ends:
                ends[e] += 1
            for _, _, why in run.bridges:
                raised[why] += 1
        up = lambda runs: round(sum(b[1] - b[0] for r in runs for b in r.bridges), 1)
        racks = [r for r in self.runs if r.rack]
        self.stats = {
            "centre": [round(v) for v in cp.area.centroid.coords[0]],
            "area": [[round(x, 1), round(y, 1)] for x, y in cp.area.exterior.coords[:-1]],
            "bund_walls": [[[round(x, 1), round(y, 1)] for x, y in ring.coords[:-1]] for ring in self.walls],
            "size_m": [round(C.W), round(C.H)], "cols": self.cols, "rows": 2 if self.two else 1,
            "trunk": "U" if self.u_shape else "ring",
            "nodes": {k: sum(1 for n in self.nodes.values() if n.kind == k) for k in
                      ("control", "bund", "pool", "unit", "yard")},
            "runs": len(self.runs),
            "pipe_m": round(sum(r.pipe_length() for r in self.runs), 1),
            "run_m": round(sum(r.length for r in self.runs), 1),
            "longest_run_m": round(max(r.length for r in self.runs), 1),
            "unit_manifold_pipe_m": round(self.manifold_m, 1),
            "ends": ends, "bridges": raised,
            "raised_m": up(self.runs),
            "rack_m": round(sum(r.length for r in racks), 1), "rack_raised_m": up(racks),
            "obstacles": n_parts + len(self.pads) + len(self.pools),
            "sources": len(self.sources), "check": self.check_stats, "npc": self.npc_stats,
            "expansion_loops": self.n_loops,
        }


def end_marks(L, run):
    """A flange across each end of a run: the nozzle at equipment, the joint
    at a tee."""
    c = run.centre()
    for kind, d in zip(run.ends, (0.15, c.length - 0.15)):
        if kind in ("equip", "tee") and not run.raised_at(d):
            L.line("interiors", perp_segment(c, d, run.width / 2 + 0.15), 0.3, 0.58)


def build_plant(site, cp):
    """Builds a process plant in the compound cp, up to the player's check.
    npc_access and Plant.finish complete it. Returns the Plant, or None when
    the compound has no rectangle large enough (nothing is changed then)."""
    free = cp.free_area()
    marks = [Point(x, y).buffer(KEEP_CLEAR_M) for _, x, y in getattr(site, "markers", [])
             if cp.area.contains(Point(x, y))]
    if marks:
        free = free.difference(unary_union(marks))
    rect = work_rect(cp.F, free)
    if rect is None:
        return None
    P = Plant(site, cp, rect)
    if not P.layout():
        return None
    P.make_nodes()
    P.network()
    P.n_loops = P.loops()
    P.bridge()
    P.check()
    P.emit()
    return P


# ------------------------------------------------------- the NPCs' check

def route_square(i, j):
    """Square (row i, column j) of the game's route grid, in metres."""
    c = ROUTE_CELL_M
    x, y = j * c - PLAY_HALF_M, i * c - PLAY_HALF_M
    return Polygon([(x, y), (x + c, y), (x + c, y + c), (x, y + c)])


def square_range(geom, n, margin=0.0):
    x0, y0, x1, y1 = geom.bounds
    lo = lambda v: max(0, int((v - margin + PLAY_HALF_M) // ROUTE_CELL_M))
    hi = lambda v: min(n - 1, int((v + margin + PLAY_HALF_M) // ROUTE_CELL_M))
    return [(i, j) for i in range(lo(y0), hi(y1) + 1) for j in range(lo(x0), hi(x1) + 1)]


def squares_over(geom, n):
    """The route squares that a geometry overlaps."""
    pg = prep(geom)
    return [ij for ij in square_range(geom, n) if pg.intersects(route_square(*ij))]


def squares_near(geom, dist, n):
    """The route squares with their centre within dist of a geometry."""
    pg = prep(geom.buffer(dist))
    c = ROUTE_CELL_M
    return [(i, j) for i, j in square_range(geom, n, dist)
            if pg.contains(Point((j + 0.5) * c - PLAY_HALF_M, (i + 0.5) * c - PLAY_HALF_M))]


def route_costs(reached, fixed, house, pipes, near):
    """The cheapest way from reached squares to every square near a plant.
    A square costs the length of run that must be raised to open it (GAP_M
    for each run on it); a square on a fixed obstacle cannot be opened.
    Returns (cost of each square, the square before it on its way)."""
    n = reached.shape[0]
    cost = np.full((n, n), 1e9)
    prev, heap = {}, []
    for i, j in zip(*np.nonzero(reached & near)):
        cost[i, j] = 0.0
        heap.append((0.0, int(i), int(j)))
    heapq.heapify(heap)
    while heap:
        d, i, j = heapq.heappop(heap)
        if d > cost[i, j]:
            continue
        for a in range(max(i - 1, 0), min(i + 2, n)):
            for b in range(max(j - 1, 0), min(j + 2, n)):
                if (a == i and b == j) or fixed[a, b] or not near[a, b]:
                    continue
                step = 1.0 + (40.0 if house[a, b] else 0.0) + GAP_M * len(pipes.get((a, b), ()))
                if d + step < cost[a, b]:
                    cost[a, b] = d + step
                    prev[(a, b)] = (i, j)
                    heapq.heappush(heap, (d + step, a, b))
    return cost, prev


def open_square(run, ij, grow):
    """Raises a run where its grown outline overlaps a route square.
    Returns whether more of the run is raised now."""
    zone = route_square(*ij).buffer(grow + run.width / 2 + PIPE_CLEAR_M + 0.5, join_style="mitre")
    c = run.centre()
    inter = c.intersection(zone)
    spans = []
    for g in getattr(inter, "geoms", [inter]):
        if g.geom_type == "LineString" and not g.is_empty:
            ds = [c.project(Point(q)) for q in g.coords]
            spans.append((min(ds), max(ds)))
    if not spans:
        d = c.project(zone.centroid)
        spans = [(d, d)]
    before = sum(b[1] - b[0] for b in run.bridges)
    for d0, d1 in spans:
        raise_span(run, d0, d1, "npc")
    return sum(b[1] - b[0] for b in run.bridges) > before + 0.5


def square_of(x, y, n):
    """(row, column) of the route square that holds a point, or None outside
    the grid."""
    i, j = int((y + PLAY_HALF_M) // ROUTE_CELL_M), int((x + PLAY_HALF_M) // ROUTE_CELL_M)
    return (i, j) if 0 <= i < n and 0 <= j < n else None


def goal_square(solid, ij):
    """The square the game sends an NPC to for a goal in square ij: that
    square, or the first open one in the rings round it, in the game's order
    (BuildingField._open_cell_near). None when there is none."""
    n = solid.shape[0]
    i, j = ij
    is_open = lambda a, b: 0 <= a < n and 0 <= b < n and not solid[a, b]
    if is_open(i, j):
        return ij
    for r in range(1, ROUTE_OPEN_SEARCH + 1):
        for dx in range(-r, r + 1):
            for dy in (-r, r):
                if is_open(i + dy, j + dx):
                    return (i + dy, j + dx)
        for dy in range(-r + 1, r):
            for dx in (-r, r):
                if is_open(i + dy, j + dx):
                    return (i + dy, j + dx)
    return None


def source_reached(x, y, solid, reached):
    """Whether an NPC sent to a salvage source at (x, y) ends near it: the
    square the game picks for it is reached, and its centre is within
    NPC_GOAL_M. None for a point outside the grid."""
    ij = square_of(x, y, solid.shape[0])
    if ij is None:
        return None
    b = goal_square(solid, ij)
    if b is None or not reached[b]:
        return False
    cx, cy = (b[1] + 0.5) * ROUTE_CELL_M - PLAY_HALF_M, (b[0] + 0.5) * ROUTE_CELL_M - PLAY_HALF_M
    return float(np.hypot(cx - x, cy - y)) <= NPC_GOAL_M


def place_sources(P, solid, stand):
    """Moves each salvage source that an NPC would not reach (see
    source_reached) to the nearest free spot in an open, reached square: off
    the roads, clear of the nodes and of the other sources, and still within
    the player's reach. Counts what it did in P.npc_stats."""
    st = P.npc_stats
    st["sources_moved"] = st["sources_cut_off"] = 0
    st["sources_moved_m"] = 0.0
    n = solid.shape[0]
    bad = [s for s in P.sources if source_reached(s[1], s[2], solid, stand) is False]
    if not bad:
        return
    keep_out = unary_union(P.blockers + [Polygon(ring) for ring in P.walls]).buffer(1.5)
    roads = unary_union(P.axes).buffer(ROAD_W_M / 2 + 1.0)
    steps = np.arange(-NPC_MOVE_M, NPC_MOVE_M + 0.01, NPC_MOVE_STEP_M)
    moved = []
    for s in bad:
        best = None
        for dx in steps:
            for dy in steps:
                d = float(np.hypot(dx, dy))
                if d > NPC_MOVE_M or (best is not None and d >= best[0]):
                    continue
                x, y = s[1] + dx, s[2] + dy
                ij = square_of(x, y, n)
                if ij is None or solid[ij] or not stand[ij]:
                    continue
                p = Point(x, y)
                if not P.cp.area.contains(p) or keep_out.contains(p) or roads.contains(p):
                    continue
                if any(o is not s and np.hypot(o[1] - x, o[2] - y) < 3.0 for o in P.sources):
                    continue
                best = (d, x, y)
        if best is None:
            st["sources_cut_off"] += 1
            continue
        moved.append((s, s[1], s[2]))
        s[1], s[2] = best[1], best[2]
    if moved:
        R = P.reach()
        for s, x, y in moved:
            if R.any and R.gap(s[1], s[2]) > REACH_M:
                s[1], s[2] = x, y
                st["sources_cut_off"] += 1
            else:
                st["sources_moved"] += 1
                st["sources_moved_m"] = round(st["sources_moved_m"] + float(np.hypot(s[1] - x, s[2] - y)), 1)


def npc_access(site, plants):
    """The NPCs' check over all plants together (see the module text).
    Raises runs until the route grid reaches every open square, node and
    salvage source of every plant, or nothing more helps; then moves the
    sources an NPC would still not reach (place_sources). Stores each
    plant's numbers in its npc_stats."""
    n = int(round(2 * PLAY_HALF_M / ROUTE_CELL_M))
    grow = ROUTE_GROW_M + ROUTE_SLACK_M
    fixed, house, near = (np.zeros((n, n), bool) for _ in range(3))
    for _, pts in site.obstacles.items:
        for ij in squares_over(Polygon(pts).buffer(grow, join_style="mitre"), n):
            fixed[ij] = True
    for P in plants:
        for g in P.houses:
            for ij in squares_over(g, n):
                house[ij] = True
        P.zone = squares_near(P.cp.area, NPC_ZONE_M, n)
        for ij in squares_near(P.cp.area, NPC_FAR_M, n):
            near[ij] = True
        P.goals = [squares_near(nd.target, NPC_NODE_M, n) for nd in P.nodes.values() if nd.target is not None]
        P.goals += [squares_near(Point(src[1], src[2]), NPC_SOURCE_M, n) for src in P.sources]
        P.goals = [sq for sq in P.goals if sq]
        P.npc_stats = {"goals": len(P.goals)}
    for it in range(NPC_TRIES + 1):
        pipes = {}
        for P in plants:
            for run in P.runs:
                for g in run.ground_outlines():
                    for ij in squares_over(g.buffer(grow, join_style="mitre"), n):
                        if run not in pipes.setdefault(ij, []):
                            pipes[ij].append(run)
        solid = fixed.copy()
        for ij in pipes:
            solid[ij] = True
        lab, _ = ndi.label(~solid, structure=np.ones((3, 3)))
        seeds = np.unique(lab[~near & ~solid])
        reached = np.isin(lab, seeds[seeds > 0])
        stand = reached & ~house
        todo = []
        for P in plants:
            pockets = {}
            for ij in P.zone:
                if not solid[ij] and not reached[ij]:
                    pockets.setdefault(int(lab[ij]), []).append(ij)
            bad = [sq for sq in P.goals if not any(stand[ij] for ij in sq)]
            st = P.npc_stats
            st["squares_cut_off"] = sum(len(v) for v in pockets.values())
            st["goals_cut_off"] = len(bad)
            if it == 0:
                st["squares_cut_off_first"], st["goals_cut_off_first"] = st["squares_cut_off"], st["goals_cut_off"]
            todo += list(pockets.values()) + [[ij for ij in sq if not house[ij]] for sq in bad]
        if not todo or it == NPC_TRIES:
            break
        cost, prev = route_costs(reached, fixed, house, pipes, near)
        more = False
        for sq in todo:
            sq = [ij for ij in sq if cost[ij] < 1e8]
            ij = min(sq, key=lambda q: cost[q]) if sq else None
            while ij is not None and not reached[ij]:
                for run in pipes.get(ij, ()):
                    more = open_square(run, ij, grow) or more
                ij = prev.get(ij)
        if not more:
            break
    for P in plants:
        P.npc_stats["bridges"] = sum(1 for r in P.runs for b in r.bridges if b[2] == "npc")
        place_sources(P, solid, stand)


# ------------------------------------------------------------- links

def straight_spots(P, step=3.0):
    """Points on a plant's trunk where another rack can join: on a straight
    part, away from the corners."""
    run = P.trunk
    c = run.centre()
    corners = [Point(p) for p in run.pts[1:-1]]
    out = []
    for d in np.arange(step, c.length - step, step):
        p = c.interpolate(d)
        if any(p.distance(k) < run.radius + 4.0 for k in corners):
            continue
        q = c.interpolate(d + 0.5)
        out.append((d, np.array([p.x, p.y]), np.array([q.x - p.x, q.y - p.y]) / 0.5))
    return out


def link_plants(site, plants, areas, rng):
    """Joins the trunks of plants that face each other across a road with a
    rack that is overhead from end to end. Returns the links' statistics."""
    tree = site.building_tree()
    built = site.buildings
    links = []
    spots = {id(P): straight_spots(P) for P in plants}
    for i, A in enumerate(plants):
        for B in plants[i + 1:]:
            if A.cp.area.distance(B.cp.area) > LINK_MAX_M:
                continue
            cb = B.trunk.centre()
            best = []
            for d, p, t in spots[id(A)]:
                db = cb.project(Point(p))
                q = cb.interpolate(db)
                v = np.array([q.x - p[0], q.y - p[1]])
                dist = float(np.hypot(*v))
                if dist > LINK_MAX_M or dist < 10.0 or abs(float(v @ t)) / dist > 0.08:
                    continue
                near = min(spots[id(B)], key=lambda s: abs(s[0] - db), default=None)
                if near is None or abs(near[0] - db) > 2.0 or abs(float(v @ near[2])) / dist > 0.08:
                    continue
                best.append((dist, d, p, t, np.array([q.x, q.y]), near[2]))
            if not best:
                continue
            dmin = min(b[0] for b in best)
            ties = [b for b in best if b[0] < dmin + 0.6]
            ok = None
            for dist, d, p, t, q, tb in sorted(ties, key=lambda b: abs(b[1] - np.median([x[1] for x in ties]))):
                seg = LineString([p, q])
                corridor = seg.buffer(3.0)
                if any(built[k].poly.intersects(corridor) for k in tree.query(corridor)):
                    continue
                if any(g.intersects(seg) for g in areas if g is not A.cp.area and g is not B.cp.area):
                    continue
                if any(g.intersects(corridor) for P in (A, B) for g in P.blockers):
                    continue
                ok = (p, t, q, tb)
                break
            if ok is None:
                continue
            p, t, q, tb = ok
            pipes = rack_pipes(rng, 3, dia=(0.4, 0.8))
            lead = group_radius(pipes) + 1.5
            run = Run([tuple(p + t * lead), tuple(p), tuple(q), tuple(q + tb * lead)], pipes, True, ("tee", "tee"), "link")
            run.add_bridge(0.0, run.length, "link")
            for g in run.ground_outlines():
                site.obstacles.add(PIPE, g)
            seed = int(rng.integers(1 << 30))
            site.drawers.append(lambda L, run=run, s=seed: (draw_run(L, run, np.random.default_rng(s)), end_marks(L, run)))
            links.append({"pipe_m": round(run.pipe_length(), 1), "span_m": round(run.length, 1), "run": run})
    return links


def summary(plants, links):
    """Totals over all plants for stats.json (and each plant's own numbers)."""
    if not plants:
        return {}
    st = [P.stats for P in plants]
    ends = {k: sum(s["ends"][k] for s in st) for k in ("equip", "tee", "open")}
    ends["tee"] += 2 * len(links)
    raised = {k: sum(s["bridges"][k] for s in st) for k in ("overhead", "road", "spacing", "repair", "marker", "npc")}
    raised["link"] = len(links)
    check = {k: sum(s["check"][k] for s in st) for k in st[0]["check"]}
    npc = {k: sum(s["npc"][k] for s in st) for k in st[0]["npc"]}
    total = lambda key: sum(s[key] for s in st)
    mean = lambda key: round(float(np.mean([s[key] for s in st])), 1)
    return {
        "plants": len(st),
        "trunks": {k: sum(1 for s in st if s["trunk"] == k) for k in ("ring", "U")},
        "pipe_m_mean": mean("pipe_m"),
        "pipe_m_median": round(float(np.median([s["pipe_m"] for s in st])), 1),
        "run_m_mean": mean("run_m"),
        "longest_run_m_mean": mean("longest_run_m"),
        "unit_manifold_pipe_m_mean": mean("unit_manifold_pipe_m"),
        "ends": ends,
        "ends_at_equipment_or_tee_share": round((ends["equip"] + ends["tee"]) / max(1, sum(ends.values())), 3),
        "bridges": raised,
        "raised_m": round(total("raised_m"), 1),
        "raised_share": round(total("raised_m") / max(1.0, total("run_m")), 3),
        "rack_m": round(total("rack_m"), 1),
        "rack_raised_m": round(total("rack_raised_m"), 1),
        "rack_raised_share": round(total("rack_raised_m") / max(1.0, total("rack_m")), 3),
        "expansion_loops": sum(s["expansion_loops"] for s in st),
        "obstacles": sum(s["obstacles"] for s in st),
        "sources": sum(s["sources"] for s in st),
        "check": check,
        "npc": npc,
        "links": {"count": len(links), "pipe_m": round(sum(k["pipe_m"] for k in links), 1)},
        "per_plant": st,
    }
