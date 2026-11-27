"""Flyovers (the Cairo "kobri"): an elevated road on pillars lifted over a
busy junction, with the road below running on under it.

FLYOVERS names each one by the road kind it carries and a point on the
junction it crosses. The deck follows the road's centre line (the middle of
a dual carriageway when two lines of the kind run side by side) for
LENGTH_M, at DECK_H_M over the middle and down to the ground over RAMP_M at
both ends. It is drawn in the talls sublayer: the deck (darker than the
road under it), its side faces, parapets, joints over the pillars and lane
markings, pier caps and pillars, so it leans like a real elevated road and
(in the game) fades near the player.

On the ground: a pillar every PILLAR_STEP_M where the deck is high enough
(a small ground obstacle, kept off cross roads and rail) and the deck's
shadow on the road under it and beside it. Like the OSM viaduct's deck, the flyover itself does
not collide: the road runs on under the ramps too, so mechas keep the whole
width of the road all along it (no ramp end closes it), and the ramp's low
end fades over a mecha near the player like the rest of the deck. Parked
cars and abandoned traffic keep off the pillars and the low ramp ends
(props.ROAD_KEEP_OFF). Under the span of the first flyover a market fills
the road between the pillars.
"""
import numpy as np
import shapely
from shapely import STRtree
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

import district_life
import props
import railkit as rk
import style
from frame import PLAY_HALF_M
from gen_city import block_rng
from obstacles import PIPE

## name: (road kinds, junction point (x, y) map metres, total length m,
## deck width m, market under it).
FLYOVERS = {
    "arterial": (("secondary",), (-460.0, 195.0), 640.0, 16.0, True),
    "corniche": (("trunk",), (-2410.0, -640.0), 560.0, 18.0, False),
}
DECK_H_M = 7.0
RAMP_M = 115.0
DECK_T_M = 1.4
PARAPET_H_M = 1.1
## Greys of the deck top and its side faces: darker than the road concrete
## under it, so the deck does not read as the road.
DECK_V, FASCIA_V = 0.18, 0.12
## The parapet's top, a light band along each deck edge.
PARAPET_W_M, PARAPET_V = 0.5, 0.5
## A dark expansion joint across the deck over each pillar.
JOINT_W_M, JOINT_V = 0.35, 0.07
## The deck's shade on the ground beside it: SHADE_M wide where the deck is
## DECK_H_M high (narrower down the ramps), alpha SHADE_A at the deck edge
## fading out.
SHADE_M, SHADE_A = 3.0, 0.55
PILLAR_STEP_M = 27.0
PILLAR_M = (2.4, 1.8)
## Where a ramp is lower than LOW_UNDER_M no vehicle stands under it (the
## district modules' ones there go, and no car is parked or abandoned
## there later); pillars stand where the deck is at least PILLAR_MIN_H_M,
## and what the district modules put on a pillar's foot goes.
LOW_UNDER_M = 3.2
VEHICLE_KINDS = ("vehicle", "truck", "vehicle_wreck", "bus", "military", "container", "railcar")
PILLAR_MIN_H_M = 3.6
## Pillars keep this far from the centre line of a crossing road or rail.
CROSS_CLEAR_M = 13.0
STEP_M = 4.0
## How far the centre line may move from one 8 m bin to the next while it
## follows the road.
TRACK_M = 22.0
MARKET_M = (90.0, 130.0)


def centre_line(site, kinds, at, length):
    """The middle of the roads of `kinds` through `at` over `length`:
    points sampled along every line of those kinds near `at`, kept where
    the line runs along the main direction (so crossing roads and a
    roundabout's ring drop out), then followed outward from `at` in 8 m
    bins, each bin the mean of its points within TRACK_M of the last one
    (so a dual carriageway gives its median and roads further off are
    left out), then fitted with a cubic in the distance along the main direction, so the
    deck runs smoothly. Returns (line, road width) or (None, 0)."""
    lay = site.full_layout or {"roads": site.roads}
    cx, cy = at
    reach = length / 2 + 40.0
    P, D, W = [], [], []
    for g, _, w, _, kind, line in lay["roads"]:
        if kind not in kinds or line is None or line.distance(Point(at)) > reach:
            continue
        pts, tang = rk.sample(line, 4.0)
        near = np.hypot(pts[:, 0] - cx, pts[:, 1] - cy) <= reach
        P.append(pts[near])
        D.append(tang[near])
        W.append(np.full(near.sum(), w))
    if not P:
        return None, 0.0
    P, D, W = np.concatenate(P), np.concatenate(D), np.concatenate(W)
    r = np.hypot(P[:, 0] - cx, P[:, 1] - cy)
    core = (r > 40.0) & (r < 160.0)
    if core.sum() < 6:
        return None, 0.0
    c = P[core] - P[core].mean(0)
    axis = np.linalg.eigh(c.T @ c)[1][:, -1]
    keep = (np.abs(D @ axis) > 0.87) & (r > 40.0)
    P, W = P[keep], W[keep]
    t = (P - np.array(at)) @ axis
    out = {}
    for sign in (1.0, -1.0):
        last = np.array(at, float)
        for b0 in np.arange(0.0, length / 2 + 8.0, 8.0) * sign:
            sel = (t >= b0 - 4.0) & (t < b0 + 4.0)
            sel &= np.hypot(P[:, 0] - last[0], P[:, 1] - last[1]) < TRACK_M + 8.0
            if sel.sum():
                last = P[sel].mean(0)
                out[round(float(b0), 1)] = last
            else:
                last = last + axis * 8.0 * sign
    keys = sorted(out)
    if len(keys) < 4 or keys[-1] - keys[0] < length * 0.6:
        return None, 0.0
    ts = np.array(keys)
    xy = np.array([out[k] for k in keys])
    full = np.arange(ts[0], ts[-1] + 0.1, 4.0)
    xs = np.polyval(np.polyfit(ts, xy[:, 0], 3), full)
    ys = np.polyval(np.polyfit(ts, xy[:, 1], 3), full)
    return LineString(np.stack([xs, ys], 1)), float(np.median(W))


def heights(s, total):
    """Deck height along the line: linear up the ramps, level between."""
    return DECK_H_M * np.clip(np.minimum(s, total - s) / RAMP_M, 0.0, 1.0)


def shade_beside(L, pts, nrm, h, half, stop=None):
    """The deck's shade on the ground along both its edges (groundlines):
    a band from the edge outward, SHADE_M wide where the deck stands
    DECK_H_M high and narrower where it is lower, dark at the edge and
    fading out. Seen from straight above, where the deck does not lean, it
    marks the deck as standing above the road. The band ends where it meets
    one of the polygons `stop` (the buildings beside the road, grown a
    little): rays across it every quarter of a step find the nearest, and
    both ends of a step keep inside the nearest hit along it."""
    w0 = SHADE_M * np.clip(h / DECK_H_M, 0.0, 1.0)
    fr = np.linspace(0.0, 1.0, 5)
    for side in (1, -1):
        inner = pts + nrm * half * side
        w = w0.copy()
        if stop:
            a = (inner[:-1, None] * (1 - fr)[None, :, None] + inner[1:, None] * fr[None, :, None]).reshape(-1, 2)
            n = (nrm[:-1, None] * (1 - fr)[None, :, None] + nrm[1:, None] * fr[None, :, None]).reshape(-1, 2)
            ww = (w0[:-1, None] * (1 - fr)[None, :] + w0[1:, None] * fr[None, :]).reshape(-1)
            rays = shapely.linestrings(np.stack([a, a + n * (np.maximum(ww, 0.01) * side)[:, None]], 1))
            ri, pi = STRtree(stop).query(rays, predicate="intersects")
            if len(ri):
                hit = np.full(len(rays), np.inf)
                d = shapely.distance(shapely.points(a[ri]), shapely.intersection(rays[ri], np.asarray(stop)[pi]))
                np.minimum.at(hit, ri, np.nan_to_num(d, nan=np.inf))
                seg = hit.reshape(-1, len(fr)).min(1)
                w[:-1] = np.minimum(w[:-1], seg)
                w[1:] = np.minimum(w[1:], seg)
        keep = (w[:-1] > 0.05) | (w[1:] > 0.05)
        outer = inner + nrm * (w * side)[:, None]
        p, q, po, qo = inner[:-1][keep], inner[1:][keep], outer[:-1][keep], outer[1:][keep]
        tris = np.concatenate([np.stack([p, q, qo], 1), np.stack([p, qo, po], 1)])
        va = np.concatenate([np.tile([SHADE_A, SHADE_A, 0.0], (len(p), 1)), np.tile([SHADE_A, 0.0, 0.0], (len(p), 1))])
        L.add_tris("groundlines", tris, 0.0, va=va)


def build(site, stats):
    S = stats.setdefault("flyovers", {})
    for name, (kinds, at, length, width, market) in FLYOVERS.items():
        if abs(at[0]) > PLAY_HALF_M or abs(at[1]) > PLAY_HALF_M:
            continue
        line, road_w = centre_line(site, kinds, at, length)
        if line is None:
            continue
        got = flyover(site, name, line, width, market)
        if got:
            S[name] = got


def flyover(site, name, line, width, market):
    pts, tang = rk.sample(line, STEP_M)
    s = np.concatenate([[0.0], np.cumsum(np.hypot(*np.diff(pts, axis=0).T))])
    total = float(s[-1])
    h = heights(s, total)
    half = width / 2
    nrm = np.stack([-tang[:, 1], tang[:, 0]], 1)
    deck = Polygon(np.concatenate([pts + nrm * half, (pts - nrm * half)[::-1]])).buffer(0)
    lay = site.full_layout or {"roads": site.roads}
    crossing = []
    for g, _, w, _, kind, l2 in lay["roads"]:
        if l2 is None or kind == "joint":
            continue
        x = l2.intersection(line)
        if x.is_empty:
            continue
        for p in getattr(x, "geoms", [x]):
            if p.geom_type != "Point":
                continue
            dd = line.project(p)
            q = line.interpolate(min(dd + 1.0, line.length))
            r0 = l2.interpolate(max(l2.project(p) - 1.0, 0.0))
            r1 = l2.interpolate(min(l2.project(p) + 1.0, l2.length))
            a = np.array([q.x - p.x, q.y - p.y])
            b = np.array([r1.x - r0.x, r1.y - r0.y])
            cosang = abs(a @ b) / max(np.hypot(*a) * np.hypot(*b), 1e-9)
            if cosang < 0.85:
                crossing.append((dd, max(CROSS_CLEAR_M, w / 2 + 6.0)))
    pillars = []
    sp = RAMP_M * 0.45
    while sp < total - RAMP_M * 0.45:
        k = int(np.clip(np.searchsorted(s, sp), 0, len(s) - 1))
        if h[k] >= PILLAR_MIN_H_M and all(abs(sp - c) > r for c, r in crossing):
            x, y = pts[k]
            ang = float(np.arctan2(tang[k][1], tang[k][0]))
            pillars.append((float(x), float(y), ang, float(h[k])))
            sp += PILLAR_STEP_M
        else:
            sp += 3.0
    low = []
    for end in (0, 1):
        sel = (h < LOW_UNDER_M) & ((s < total / 2) if end == 0 else (s > total / 2))
        if sel.sum() >= 2:
            seg = pts[sel]
            tg = tang[sel]
            n = np.stack([-tg[:, 1], tg[:, 0]], 1) * half
            low.append(Polygon(np.concatenate([seg + n, (seg - n)[::-1]])).buffer(0))
    feet = [rk.rect_at(x, y, a, PILLAR_M[1], PILLAR_M[0]) for x, y, a, _ in pillars]
    placed = [g for g in feet
              if abs(g.centroid.x) < PLAY_HALF_M and abs(g.centroid.y) < PLAY_HALF_M and site.in_window(g.buffer(20))]
    for g in placed:
        site.obstacles.add(PIPE, g)
    rk.clear_touching(site, placed)
    for g in low:
        if site.in_window(g):
            site.clear_area(g, VEHICLE_KINDS)
    site.solid_extra += feet
    props.ROAD_KEEP_OFF.extend([g.buffer(1.5) for g in feet] + low)
    site.claim(unary_union(feet + low).buffer(1.0), f"infra:flyover_{name}")
    out = {"length_m": round(total), "pillars": len(pillars), "crossings": len(crossing)}
    stalls = 0
    if market:
        stalls = under_market(site, pts, tang, s, h, pillars, crossing, half, name)
        out["market_stalls"] = stalls

    key = style.chunk_key(deck)

    def draw(L):
        L.fill("groundlines", deck, 0.0, 0.28)
        band = deck.buffer(SHADE_M + 1.0)
        stop = [b.poly.buffer(0.4) for b in site.buildings if b.poly.intersects(band)]
        shade_beside(L, pts, nrm, h, half, stop)
        for x, y, a, ph in pillars:
            foot = rk.rect_at(x, y, a, PILLAR_M[1], PILLAR_M[0])
            L.fill("interiors", foot, 0.28)
            L.line("interiors", foot.exterior, 0.08, 0.4)
            L.tall_prism(foot, 0.0, ph - DECK_T_M - 0.9, 0.22, 0.3, chunk=key)
            cap = rk.rect_at(x, y, a, 2.2, width - 2.0)
            L.tall_prism(cap, ph - DECK_T_M - 0.9, ph - DECK_T_M, 0.24, 0.3, chunk=key)
        for g in low:
            L.fill("groundlines", g, 0.0, 0.18)
        for side in (1, -1):
            edge = pts + nrm * half * side
            rk.tall_wall(L, edge, np.maximum(h - DECK_T_M, 0.0), h, FASCIA_V, chunk=key)
        rk.tall_ribbon(L, pts, h, half, DECK_V, chunk=key)
        for x, y, a, ph in pillars:
            c, s_ = np.cos(a), np.sin(a)
            n = np.array([-s_, c]) * (half - PARAPET_W_M)
            L.tall_span((x + n[0], y + n[1]), (x - n[0], y - n[1]), JOINT_W_M, ph + 0.01, ph + 0.01, JOINT_V,
                        chunk=key)
        for side in (1, -1):
            edge = pts + nrm * (half - PARAPET_W_M / 2) * side
            rk.tall_wall(L, edge, h, h + PARAPET_H_M, 0.3, chunk=key)
            rk.tall_ribbon(L, edge, h + PARAPET_H_M, PARAPET_W_M / 2, PARAPET_V, chunk=key)
        for off in (-0.25, 0.25):
            rk.tall_ribbon(L, pts + nrm * off, h + 0.01, 0.06, 0.38, chunk=key)
        for off in (-half / 2, half / 2):
            lane = pts + nrm * off
            for k in range(0, len(lane) - 1, 3):
                rk.tall_ribbon(L, lane[k:k + 2], h[k:k + 2] + 0.01, 0.07, 0.36, 0.9, chunk=key)
        for k in range(8, len(pts) - 8, 10):
            x, y = pts[k]
            L.tall_post(float(x), float(y), 0.25, float(h[k]), float(h[k]) + 6.5, 0.3, 0.36, chunk=key)
    site.drawers.append(draw)
    return out


def under_market(site, pts, tang, s, h, pillars, crossing, half, name):
    """Stalls in two rows each side of the pillar line under the level part
    of the deck, away from crossing roads; the road there is kept clear of
    parked cars. Returns the number of stalls."""
    total = float(s[-1])
    lo, hi = RAMP_M + 10.0, total - RAMP_M - 10.0
    best = None
    for a in np.arange(lo, hi - MARKET_M[0], 5.0):
        b = min(a + MARKET_M[1], hi)
        if any(a - r < c < b + r for c, r in crossing):
            continue
        if best is None or b - a > best[1] - best[0]:
            best = (a, b)
    if best is None:
        return 0
    a, b = best
    sel = (s >= a) & (s <= b)
    if sel.sum() < 3:
        return 0
    seg, tg = pts[sel], tang[sel]
    nrm = np.stack([-tg[:, 1], tg[:, 0]], 1)
    area = Polygon(np.concatenate([seg + nrm * (half - 0.5), (seg - nrm * (half - 0.5))[::-1]])).buffer(0)
    props.ROAD_KEEP_OFF.append(area)
    site.claim(area, f"infra:flyover_market_{name}")
    site.solid_extra.append(area)
    site.add_landmark("the Flyover Market", "market", area)
    if not site.in_window(area):
        return 0
    rng = block_rng(823, area)
    cat = props.CATALOGUE.get("stall", [])
    if not cat:
        return 0
    feet = [Point(x, y).buffer(2.4) for x, y, _, _ in pillars]
    line = LineString(seg)
    n = 0
    for off, face in ((2.6, 0.0), (-2.6, np.pi), (half - 2.0, np.pi), (-(half - 2.0), 0.0)):
        side = LineString(rk.offset_path(seg, tg, off))
        d = rng.uniform(0.5, 2.0)
        while d < side.length - 2.0:
            p = side.interpolate(d)
            q = side.interpolate(min(d + 0.5, side.length))
            ang = float(np.arctan2(q.y - p.y, q.x - p.x)) + face
            v = int(rng.integers(len(cat)))
            size = (cat[v]["length_m"], cat[v]["width_m"])
            if rng.random() < 0.85 and not any(f.contains(p) for f in feet) and site.props.clear_of(p.x, p.y, 1.2):
                n += site.props.add("stall", p.x, p.y, ang, size, v)
            d += size[0] + rng.uniform(0.3, 1.2)
    for _ in range(int(rng.integers(10, 18))):
        t = rng.uniform(0, line.length)
        p = line.interpolate(t)
        k = int(np.clip(np.searchsorted(s[sel] - s[sel][0], t), 0, len(seg) - 1))
        o = rng.choice([-1.0, 1.0]) * rng.uniform(4.2, half - 3.6)
        x, y = p.x - tg[k][1] * o, p.y + tg[k][0] * o
        name_c = str(rng.choice(["crates", "sacks", "tarp", "crates", "cart"]))
        v, size = district_life.variant_of("clutter", name_c)
        if v >= 0 and site.props.clear_of(x, y, max(size) / 2 + 0.3):
            site.props.add("clutter", x, y, rng.uniform(0, 2 * np.pi), size, v)
    return n
