"""Drawing helpers for the infrastructure modules (infra.py and the modules
it runs): single tracks, platforms, canopies, overhead line portals, buffer
stops, signals, rail vehicles standing on a track, container stacks, and
tall strips with heights that change along them.

Everything is in map-frame metres. Tracks and platforms go into the ground
sublayers; canopies into "overheads"; anything that stands well above a
mecha (portals, wires, stacked containers, pylons, flyover decks) into
"talls", where every vertex carries its height and the game leans it away
from the screen centre.
"""
import numpy as np
from shapely.geometry import LineString, Point, Polygon, box
from shapely import affinity
from shapely.ops import unary_union

import buildings as bl
import props
import ruins
import style
from frame import PLAY_HALF_M
from obstacles import PIPE

GAUGE_HALF_M = 0.72
SLEEPER_HALF_M = (0.12, 1.3)
SLEEPER_STEP_M = 1.3
BED_HALF_M = 2.4
CONTAINER_LEVEL_M = 2.6
CONTAINER_W_M = 2.44
CONTAINER_LENGTHS_M = (6.06, 12.19)
## Containers stand stacked only in blocks whose outline is at least this
## large (m2): a block is a building, and nothing smaller than 60 m2 is.
STACK_RUN_MIN_M2 = 60.0
## Gaps between the containers of a run up to this wide are closed in its
## outline.
RUN_CLOSE_M = 1.8


def full_roads_near(site, geom, dist):
    """The concrete of the whole map's roads (site.full_layout, so a window
    run sees the same roads as a full run) within dist of geom, or None."""
    return site.full_roads_near(geom, dist)


def full_big_near(site, geom):
    """The whole map's large roofs (site.full_layout) that touch geom."""
    return site.full_big_in(geom)


def sample(line, step):
    """Points every `step` metres along a line and the unit direction at each
    (two arrays (n, 2))."""
    n = max(2, int(np.ceil(line.length / step)) + 1)
    d = np.linspace(0.0, line.length, n)
    pts = np.array([line.interpolate(t).coords[0] for t in d])
    tang = np.gradient(pts, axis=0)
    tang /= np.maximum(np.hypot(tang[:, 0], tang[:, 1]), 1e-9)[:, None]
    return pts, tang


def offset_path(pts, tang, off):
    """The polyline beside pts at off metres (positive to the left of the
    direction of travel in a y-down frame, i.e. +normal = (-ty, tx)); off is
    a number or an array per point."""
    off = np.broadcast_to(np.asarray(off, float), (len(pts),))
    nrm = np.stack([-tang[:, 1], tang[:, 0]], 1)
    return pts + nrm * off[:, None]


def track(L, line, sleeper_v=style.SLEEPER_V, bed=True, step=SLEEPER_STEP_M, bed_half=BED_HALF_M):
    """One track along a line: a dark ballast bed, sleepers and two rails,
    in the style of the OSM rail (style.draw_rails)."""
    if line.is_empty or line.length < 1.0:
        return
    if bed:
        L.fill("groundlines", line.buffer(bed_half, cap_style="flat"), style.RAIL_BED_V)
    pts, tang = sample(line, step)
    nrm = np.stack([-tang[:, 1], tang[:, 0]], 1)
    hw, hl = SLEEPER_HALF_M
    c = pts[:, None, :] + tang[:, None, :] * np.array([-hw, hw, hw, -hw])[None, :, None] \
        + nrm[:, None, :] * np.array([-hl, -hl, hl, hl])[None, :, None]
    tris = np.concatenate([c[:, [0, 1, 2]], c[:, [0, 2, 3]]])
    L.add_tris("groundlines", tris, sleeper_v)
    for r in (-GAUGE_HALF_M, GAUGE_HALF_M):
        rail = LineString(offset_path(pts, tang, r))
        L.line("groundlines", rail, 0.1, style.RAIL_V)


def buffer_stop_parts(x, y, ang):
    """The beam (polygon) and the two struts (lines, 0.22 m wide) of a
    buffer stop at (x, y) facing along ang (radians)."""
    c, s = np.cos(ang), np.sin(ang)
    beam = affinity.rotate(box(x - 0.35, y - 1.5, x + 0.35, y + 1.5), np.degrees(ang), origin=(x, y))
    struts = []
    for side in (-1.0, 1.0):
        p0 = (x - s * side * 0.72, y + c * side * 0.72)
        struts.append(LineString([p0, (p0[0] + c * 2.2, p0[1] + s * 2.2)]))
    return beam, struts


def buffer_stop_outline(x, y, ang):
    """Everything buffer_stop draws at (x, y, ang), as one polygon."""
    beam, struts = buffer_stop_parts(x, y, ang)
    return unary_union([beam, affinity.translate(beam, 0.4, 0.4)] + [p.buffer(0.11) for p in struts])


def buffer_stop(L, x, y, ang):
    """A buffer stop at a track end, facing along ang (radians): a beam
    across the rails on two struts, with its shadow."""
    beam, struts = buffer_stop_parts(x, y, ang)
    L.fill("interiors", affinity.translate(beam, 0.4, 0.4), 0.0, 0.45)
    for p in struts:
        L.line("interiors", p, 0.22, 0.3)
    L.fill("interiors", beam, 0.36)
    L.line("interiors", beam.exterior, 0.06, 0.48)


def signal(L, x, y, ang, rng):
    """A colour light signal beside the track: a base, a mast and a dark head
    with its hood, drawn flat with a shadow."""
    c, s = np.cos(ang), np.sin(ang)
    L.fill("interiors", Point(x + 0.3, y + 0.3).buffer(0.55, quad_segs=3), 0.0, 0.4)
    L.fill("interiors", Point(x, y).buffer(0.45, quad_segs=3), 0.3)
    head = affinity.rotate(box(x - 0.35, y - 0.55, x + 0.35, y + 0.55), np.degrees(ang), origin=(x, y))
    L.fill("interiors", head, 0.05)
    L.line("interiors", head.exterior, 0.05, 0.42)
    for k in (-0.25, 0.25):
        L.fill("interiors", Point(x - s * k, y + c * k).buffer(0.12, quad_segs=2), rng.choice([0.2, 0.32]))


def platform(L, poly, edges=(), v=0.21):
    """A platform: paving over the ground with light edges; `edges` are the
    lines along the track side, which get a light safety line and a darker
    tactile strip just inside it."""
    L.fill("interiors", poly, v)
    for g in style.polys(poly):
        L.line("interiors", LineString(g.exterior.coords), 0.12, 0.32, 0.8)
    for e in edges:
        L.line("interiors", e, 0.18, 0.4)


def canopy(L, axis, half_w, pts_step=6.0, v=0.19, columns=True):
    """A platform canopy along `axis` (a line), half_w each side: a roof
    sheet with ribs and a ridge in the overheads sublayer, and its columns
    on the platform (drawn under it)."""
    if axis.length < 4:
        return
    roof = axis.buffer(half_w, cap_style="flat")
    pts, tang = sample(axis, pts_step)
    if columns:
        for p in pts[1:-1]:
            L.fill("interiors", Point(*p).buffer(0.3, quad_segs=2), 0.06)
    L.fill("overheads", roof, v, 0.92)
    L.line("overheads", axis, 0.25, v * 1.9, 0.92)
    for p, t in zip(pts, tang):
        n = np.array([-t[1], t[0]])
        rib = LineString([p - n * half_w, p + n * half_w])
        L.line("overheads", rib, 0.1, v * 0.6, 0.92)
    for side in (-1, 1):
        edge = LineString(offset_path(pts, tang, side * half_w))
        L.line("overheads", edge, 0.16, 0.34, 0.92)


def portal(L, x, y, ang, half_span, h=6.8, v=0.34, masts=(True, True)):
    """An overhead line portal across a double track: two masts and a beam
    in the talls sublayer, mast feet drawn on the ground. masts says which
    of the two (left and right of ang) stand; with one, the beam is a
    cantilever from it across both tracks."""
    nx, ny = -np.sin(ang), np.cos(ang)
    a = (x + nx * half_span, y + ny * half_span)
    b = (x - nx * half_span, y - ny * half_span)
    for (px, py), up in zip((a, b), masts):
        if not up:
            continue
        L.fill("interiors", Point(px, py).buffer(0.4, quad_segs=2), 0.3)
        L.tall_post(px, py, 0.32, 0.0, h, v * 0.8, v, ang=np.degrees(ang))
    L.tall_span(a, b, 0.22, h, h, v)


def wire(L, p0, p1, h0, h1=None, width=0.07, v=0.36, a=0.9):
    L.tall_span(p0, p1, width, h0, h0 if h1 is None else h1, v, a)


def tall_ribbon(L, pts, hs, half_w, v, a=1.0, chunk=None):
    """A flat strip along a polyline pts ((n, 2) metres) whose height at each
    point is hs ((n,) metres): a deck, a parapet, a lane line. One quad per
    segment."""
    pts = np.asarray(pts, float)
    hs = np.asarray(hs, np.float32)
    if len(pts) < 2:
        return
    d = np.gradient(pts, axis=0)
    d /= np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)[:, None]
    n = np.stack([-d[:, 1], d[:, 0]], 1) * half_w
    left, right = pts + n, pts - n
    a0, a1, b0, b1 = left[:-1], left[1:], right[:-1], right[1:]
    tris = np.concatenate([np.stack([a0, a1, b1], 1), np.stack([a0, b1, b0], 1)])
    vh = np.concatenate([np.stack([hs[:-1], hs[1:], hs[1:]], 1), np.stack([hs[:-1], hs[1:], hs[:-1]], 1)])
    mid = pts[len(pts) // 2]
    L.add_tris("talls", tris, v, a, chunk=chunk or tuple(style.chunk_of([mid])[0]), vh=vh)


def tall_wall(L, pts, h0s, h1s, v, a=1.0, chunk=None):
    """A vertical face along a polyline: from heights h0s up to h1s at each
    point (a deck's fascia, a parapet). With the game's lean the face shows
    on the side away from the camera."""
    pts = np.asarray(pts, float)
    if len(pts) < 2:
        return
    h0s = np.asarray(h0s, np.float32)
    h1s = np.asarray(h1s, np.float32)
    p, q = pts[:-1], pts[1:]
    tris = np.concatenate([np.stack([p, q, q], 1), np.stack([p, q, p], 1)])
    vh = np.concatenate([np.stack([h0s[:-1], h0s[1:], h1s[1:]], 1), np.stack([h0s[:-1], h1s[1:], h1s[:-1]], 1)])
    mid = pts[len(pts) // 2]
    L.add_tris("talls", tris, v, a, chunk=chunk or tuple(style.chunk_of([mid])[0]), vh=vh)


def variant(kind, name):
    """(variant index, (length, width) m) of a sprite in the catalogue by its
    file name stem (e.g. "boxcar"), or (-1, None)."""
    for i, e in enumerate(props.CATALOGUE.get(kind, [])):
        if e["file"] == f"vehicle_{name}.png":
            return i, (e["length_m"], e["width_m"])
    return -1, None


def rect_at(x, y, ang, length, width):
    return affinity.rotate(box(x - length / 2, y - width / 2, x + length / 2, y + width / 2), ang, origin=(x, y),
                           use_radians=True)


def clear_touching(site, areas, margin=0.5, upto=None):
    """Removes the prop spawns whose body (its turned rectangle) touches one
    of `areas` grown by margin, with their vehicle-bound sources, and the
    salvage sources whose box touches one. For a small new obstacle (a
    pillar, a tower foot): what stood clear of it stays, however near.
    upto (props, sources) limits the candidates to the first that many
    prop spawns and salvage sources, so what was added after them (the
    things `areas` outline) stays. Returns (props removed, sources
    removed)."""
    from shapely import STRtree
    gs = [a.buffer(margin) for a in areas if a is not None and not a.is_empty]
    if not gs:
        return 0, 0
    tree = STRtree(gs)
    n_p, n_s = upto if upto is not None else (len(site.props.items), len(site.salvage.items))

    def hit(geom):
        return any(gs[i].intersects(geom) for i in tree.query(geom))

    keep, gone = [], set()
    for it in site.props.items[:n_p]:
        _, x, y, r, sx, sy, _ = it
        if len(tree.query(Point(x, y).buffer(max(sx, sy)))) and hit(rect_at(x, y, r, sx, sy)):
            gone.add((round(x, 3), round(y, 3)))
            continue
        keep.append(it)
    keep += site.props.items[n_p:]
    n_props = len(site.props.items) - len(keep)
    if n_props:
        site.props.replace_items(keep)
    sal = [s for s in site.salvage.items[:n_s]
           if not ((s[8] and (round(s[1], 3), round(s[2], 3)) in gone)
                   or (len(tree.query(Point(s[1], s[2]).buffer(max(s[4], s[5])))) and hit(rect_at(*s[1:6]))))]
    sal += site.salvage.items[n_s:]
    n_src = len(site.salvage.items) - len(sal)
    site.salvage.items = sal
    return n_props, n_src


def rake(site, line, start, names, rng, gap=(0.9, 1.6), taken=None, clear=None, flip=False, src_share=1.0):
    """Stands rail vehicles nose to tail along a track line from distance
    `start`: one per name in names (sprite stems, see variant). Each one is
    a railcar prop and, with chance src_share if its sprite is a source, a
    salvage source. A car that would leave the line, touch a rectangle in
    `taken` or leave the polygon `clear` stops the rake there. Cars outside
    the play area or the window are skipped. Returns the cars placed as
    (x, y, ang, name)."""
    out = []
    d = start
    taken = taken if taken is not None else []
    for name in names:
        v, size = variant("railcar", name)
        if v < 0:
            break
        ln, wd = size
        if d + ln > line.length or d < 0:
            break
        p0, p1 = line.interpolate(d), line.interpolate(d + ln)
        x, y = (p0.x + p1.x) / 2, (p0.y + p1.y) / 2
        ang = float(np.arctan2(p1.y - p0.y, p1.x - p0.x)) + (np.pi if flip else 0.0)
        r = rect_at(x, y, ang, ln, wd)
        if (clear is not None and not clear.contains(r)) or any(r.intersects(t) for t in taken):
            break
        src = site.salvage if rng.random() < src_share else None
        inside = abs(x) < PLAY_HALF_M - 15 and abs(y) < PLAY_HALF_M - 15 and site.in_window(r)
        if inside and props.add_vehicle(site.props, src, "railcar", x, y, ang, size, v):
            taken.append(r.buffer(0.3))
            out.append((x, y, ang, name))
        d += ln + rng.uniform(*gap)
    return out


def container_stack(L, x, y, ang, length, levels, rng, v=None):
    """A stack of `levels` containers (2 or 3) standing on (x, y), long side
    along ang (radians): each level a prism in the talls sublayer with ribs
    on the top one. Returns the footprint polygon (the caller makes it an
    obstacle)."""
    foot = rect_at(x, y, ang, length, CONTAINER_W_M)
    L.fill("interiors", affinity.translate(foot, 0.5, 0.5), 0.0, 0.45)
    L.fill("interiors", foot, 0.12)
    tones = [rng.choice([0.13, 0.17, 0.22, 0.27]) if v is None else v for _ in range(levels)]
    for k in range(levels):
        h0, h1 = k * CONTAINER_LEVEL_M, (k + 1) * CONTAINER_LEVEL_M
        L.tall_prism(foot, h0, h1, tones[k] * 0.7, tones[k])
    top = levels * CONTAINER_LEVEL_M
    c, s = np.cos(ang), np.sin(ang)
    nx, ny = -s, c
    for t in np.arange(-length / 2 + 0.6, length / 2 - 0.4, 0.9):
        a = (x + c * t + nx * 1.1, y + s * t + ny * 1.1)
        b = (x + c * t - nx * 1.1, y + s * t - ny * 1.1)
        L.tall_span(a, b, 0.07, top, top, tones[-1] * 0.7)
    ring = list(foot.exterior.coords)
    for p, q in zip(ring[:-1], ring[1:]):
        L.tall_span(p, q, 0.08, top, top, min(tones[-1] + 0.15, 0.45))
    return foot


def draw_stack_building(L, b, rng, salvage):
    """A stack run's building draws nothing of its own: the module that
    placed the stacks draws them (container_stack)."""


bl.KINDS["container_stack"] = (lambda L, b, rng: None, False, 0.0, draw_stack_building)


def closed_union(feet):
    """The union of container footprints with the gaps between them (up to
    RUN_CLOSE_M) closed, square-cornered."""
    return unary_union(feet).buffer(RUN_CLOSE_M / 2, join_style="mitre").buffer(-RUN_CLOSE_M / 2, join_style="mitre")


def run_outline(feet):
    """The outline of a block of container footprints (closed_union), or
    None when the block is not one piece."""
    g = closed_union(feet)
    return g if g.geom_type == "Polygon" and not g.is_empty else None


def split_blocks(feet):
    """Groups container stack footprints into blocks: the pieces of their
    closed_union. feet: a footprint per slot, or None for a slot that is no
    stack (a single container, a gap). Returns (blocks, short): the blocks of
    STACK_RUN_MIN_M2 or more as lists of slot indices, and the slot indices
    in smaller pieces."""
    idx = [i for i, f in enumerate(feet) if f is not None]
    if not idx:
        return [], []
    blocks, short = [], []
    for piece in style.polys(closed_union([feet[i] for i in idx])):
        members = [i for i in idx if feet[i].intersection(piece).area > 0.5 * feet[i].area]
        if piece.area >= STACK_RUN_MIN_M2:
            blocks.append(members)
        else:
            short += members
    return blocks, short


def stack_runs(site, runs):
    """Each block of container stacks (footprints side by side or end to
    end, its outline STACK_RUN_MIN_M2 or more) is one ground obstacle, so
    mechas cannot walk through it, and one gutted building of kind
    container_stack, so its walls stop shots and sight and cast light
    shadows like a building's. Both follow the block's outline; the generic
    props keep clear of it. Returns the outlines."""
    out = []
    for feet in runs:
        g = run_outline(feet)
        if g is None:
            continue
        site.obstacles.add(PIPE, g)
        site.solid_extra.append(g)
        b = bl.Building(g, 0.2, "container_stack")
        b.opts["stage"] = "infra"
        b.opts["state"] = ruins.GUTTED
        site.buildings.append(b)
        out.append(g)
    return out


def lattice_tower(L, x, y, ang, h, arm_hs, arm_half, base_half=3.6, v=0.4, foot=True):
    """A lattice pylon standing on (x, y), its cross-arms across ang
    (radians): four legs from the base corners taper to a waist, a mast to
    the top, X braces on the legs, and one cross-arm per height in arm_hs
    (half length arm_half, or a list of them). Kept to about 40 triangles.
    Returns the insulator points as a list per arm: [(x, y, h), ...]."""
    c, s = np.cos(ang), np.sin(ang)

    def at(u, w):
        return (x + c * u - s * w, y + s * u + c * w)

    waist_h = 0.78 * h
    waist = 0.9
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    if foot:
        for cu, cw in corners:
            px, py = at(cu * base_half, cw * base_half)
            L.fill("interiors", Point(px, py).buffer(0.7, quad_segs=2), 0.24)
        L.line("interiors", Polygon([at(cu * base_half, cw * base_half) for cu, cw in corners]).exterior, 0.08, 0.2,
               0.6)
    for cu, cw in corners:
        L.tall_span(at(cu * base_half, cw * base_half), at(cu * waist, cw * waist), 0.5, 0.0, waist_h, v * 0.85)
    for (au, aw), (bu, bw) in ((corners[0], corners[1]), (corners[3], corners[2]),
                               (corners[0], corners[3]), (corners[1], corners[2])):
        for f0, f1 in ((0.0, 0.42), (0.42, 0.75)):
            ha, hb = f0 * waist_h, f1 * waist_h
            ra = base_half + (waist - base_half) * f0
            rb = base_half + (waist - base_half) * f1
            L.tall_span(at(au * ra, aw * ra), at(bu * rb, bw * rb), 0.16, ha, hb, v * 0.75, 0.9)
    L.tall_post(x, y, 1.0, waist_h, h, v * 0.85, v, ang=np.degrees(ang))
    out = []
    halves = arm_half if isinstance(arm_half, (list, tuple)) else [arm_half] * len(arm_hs)
    for ah, half in zip(arm_hs, halves):
        a, b = at(0, -half), at(0, half)
        L.tall_span(a, b, 0.8, ah, ah, v)
        out.append([(a[0], a[1], ah - 1.6), (b[0], b[1], ah - 1.6)])
    L.tall_span(at(0, -0.5), at(0, 0.5), 0.5, h + 1.2, h + 1.2, v)
    return out
