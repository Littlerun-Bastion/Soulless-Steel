"""Schools and walled sports grounds.

  Helwan General Club   at the OSM sports centre (its outline less the
                        roads): the large OSM roof there is replaced by a
                        400 m running track round a football pitch, a main
                        stand and a small one, four floodlight masts (talls,
                        FLOODLIGHT_M), tennis courts, a drained pool (a pool
                        obstacle), a volleyball court and the clubhouse;
                        registered as a landmark
  schools               SCHOOLS compounds in residential blocks, on a
                        street: an L- or U-shaped building round a yard with
                        a football pitch and a basketball court where they
                        fit, a flagpole (talls) by the gate, trees
  municipal pitches     PITCHES walled football grounds: a pitch, a small
                        stand, a changing room, four floodlight masts

Compound walls are drawing only, as the farm yards' and military
compounds' walls are (shots, sight and mechas pass them); the buildings in
the compounds (school wings, stands, clubhouse, changing rooms) are
ordinary buildings with walls and ruin states. Each compound is added to
solid_extra, so the generic props keep out of it. Pitches and courts are
marked in the groundlines sublayer.
"""
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

import buildings as bl
import civickit as ck
import equipment
import kit
import obstacles
import ruins
import style
from districts import RESIDENTIAL
from gen_city import to_frame_m

CLUB_NAME = "Helwan General Club"
FLOODLIGHT_M = (21.0, 25.0)
SCHOOLS = 10
SCHOOL_SIZES = ((80.0, 58.0), (84.0, 62.0), (76.0, 56.0), (88.0, 60.0))
SCHOOL_SPACING_M = 600.0
PITCHES = 5
PITCH_SIZES = ((78.0, 52.0), (74.0, 50.0), (82.0, 54.0))
PITCH_SPACING_M = 800.0
PITCH_FLOODLIGHT_M = (17.0, 20.0)
SURFACE_V = 0.14
## Least distance from a tree to a building, court or pool (m).
TREE_CLEAR_M = 1.5
YARD_V = 0.22


# ------------------------------------------------------------------- roofs

def roof_stand(L, b, rng):
    """A stand seen from above: rows of steps along its length, lighter
    towards the front, and a sheet canopy over the back rows when
    b.opts["canopy"]."""
    g = b.poly
    o = b.opts
    F = ck.Local(*o["frame"])
    hl, hd = o["half"]
    key = style.chunk_key(g)
    v = style.roof_value(b.mv) * 1.4
    L.fill("roofs", g, v, chunk=key)
    rows = max(3, int(2 * hd / 0.8))
    Q = F.quads()
    for i in range(rows):
        y0 = -hd + 2 * hd * i / rows
        Q.rect(-hl, y0, hl, y0 + 2 * hd / rows * 0.45, min(v * (1.4 + 0.8 * i / rows), 0.3), 0.9)
    for x in np.arange(-hl + 6.0, hl - 1.0, 6.0):
        Q.rect(x - 0.4, -hd, x + 0.4, hd, 0.06, 0.9)
    Q.flush(L, "roofs", key)
    if o.get("canopy"):
        cv = min(v * 2.2, 0.24)
        cy0 = -hd + 2 * hd * 0.45
        Q = F.quads()
        Q.grad(-hl, cy0 - 1.2, hl, cy0, 0.0, 0.0, 0.4)
        Q.rect(-hl, cy0, hl, hd, cv)
        for x in np.arange(-hl + 3.0, hl, 3.0):
            Q.line(x, cy0, x, hd, 0.08, cv * 0.7)
        Q.flush(L, "roofs", key)
    L.line("roofs", g.exterior, style.OUTLINE_W, style.OUTLINE_V, chunk=key)
    return None


bl.KINDS["stand"] = (roof_stand, False, style.HALO_HOUSE_M)
bl.KINDS["school"] = (bl.roof_big, True, style.HALO_BIG_M)


# ---------------------------------------------------------------- helpers

def building(site, poly, kind, **opts):
    c = poly.centroid
    b = bl.Building(poly, float(site.sampler.value(c.x, c.y)), kind, **opts)
    site.buildings.append(b)
    return b


def stand(site, F, x0, y0, x1, y1, canopy, front):
    """A stand in compound frame F from (x0, y0) to (x1, y1); front -1 or
    +1: the side (in y) that faces the pitch. Returns its footprint."""
    poly = F.rect(x0, y0, x1, y1)
    c = poly.centroid
    ang = F.ang if front < 0 else F.ang + np.pi
    building(site, poly, "stand", frame=(c.x, c.y, ang), half=((x1 - x0) / 2, (y1 - y0) / 2), canopy=canopy)
    return poly


def floodlights(site, F, hl, hw, height, r, extra=0.0):
    """Masts at the four corners of a hl x hw half-size field in F, each
    turned to the field's middle."""
    cx, cy = F.pt(0, 0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = F.pt(sx * (hl + extra), sy * (hw + extra))
            face = float(np.arctan2(cy - y, cx - x))
            h = height * r.uniform(0.97, 1.03)
            site.drawers.append(lambda L, x=x, y=y, h=h, f=face: ck.floodlight(L, x, y, h, f))


def fenced_court(L, F, hl, hw, chunk, v=0.17):
    """A court's surface with a light fence round it."""
    poly = F.rect(-hl, -hw, hl, hw)
    ck.surface(L, poly, v, 0.95, chunk)
    kit.fence(L, poly.exterior, np.random.default_rng(0), v=0.3, sub="interiors", post_every=3.0)


def trees_along(site, line, every, inset_poly, r, size=(7.0, 10.0), avoid=None):
    """Trees about every `every` m along a line, each moved onto
    inset_poly's outline; none stands in avoid (buildings, courts and the
    ground in front of the gates, grown by a margin)."""
    d = r.uniform(2.0, every)
    while d < line.length:
        p = line.interpolate(d)
        d += r.uniform(every * 0.8, every * 1.3)
        q = inset_poly.exterior.interpolate(inset_poly.exterior.project(p))
        rot, s = r.uniform(0, 2 * np.pi), r.uniform(*size)
        if avoid is None or not avoid.contains(q):
            site.props.add("tree", q.x, q.y, rot, (s, s))


# ------------------------------------------------------------------ club

def club_area(site):
    for kind, rings, p in site.feats or []:
        if kind == "poly" and p.get("leisure") == "sports_centre" and p.get("name") == CLUB_NAME:
            g = Polygon(to_frame_m(rings[0])).buffer(0)
            if not g.is_empty:
                return g
    return None


def build_club(site, lay, made):
    """The Helwan General Club."""
    g = club_area(site)
    if g is None:
        return
    roads_u = lay.roads_near(g, 20.0)
    area = g.difference(roads_u.buffer(1.0)) if roads_u is not None else g
    area = kit.largest(ck.free_land(site, area, districts=False))
    if area is None or area.area < 15000.0:
        return
    site.claim(area, "civic:club")
    site.add_landmark(CLUB_NAME, "sports", area)
    made["club"] = 1
    if not site.in_window(area):
        return
    d = site.district_taken()
    if d is not None and d.intersects(area):
        made["club_district"] = 1
        return
    site.remove_buildings_in(area, kinds=("big", "house"))
    ck.clear_for(site, area)
    site.solid_extra.append(area)
    Fk = kit.Frame(area)
    r = ck.rng_at(401, Fk.c.x, Fk.c.y)
    # Club frame: x along the long axis, y across; the track at one end,
    # the courts, pool and clubhouse at the other.
    F = ck.Local(Fk.c.x, Fk.c.y, Fk.rad)
    x0, x1, y0, y1 = Fk.x0 + 2.0, Fk.x1 - 2.0, Fk.y0 + 2.0, Fk.y1 - 2.0
    straight, r_in, lanes = 84.39, 36.5, 6
    r_out = r_in + lanes * 1.22
    tl = straight / 2 + r_out
    tx = x0 + 4.0 + tl
    stand_d = 9.0
    ty = (y0 + y1) / 2 + (stand_d - 5.0) / 2
    T = ck.Local(*F.pt(tx, ty), F.ang)
    east0 = tx + tl + 6.0
    gates = ck.gate_points(area, roads_u, n=2, min_gap=60.0)
    seed = int(r.integers(1 << 30))

    def draw(L, seed=seed):
        rr = np.random.default_rng(seed)
        key = style.chunk_key(area)
        L.fill("groundlines", area, 0.12, 0.7, chunk=key)
        ck.running_track(L, T, straight, r_in, lanes, key)
        ck.surface(L, T.rect(-52.0, -34.0, 52.0, 34.0), SURFACE_V, 0.9, key)
        ck.football(L, T, 100.0, 64.0, key)
        ck.compound_wall(L, area.exterior, v=0.3, width=0.6, gates=gates, gap=7.0)
        for cx, cy in courts:
            C = ck.Local(*F.pt(cx, cy), F.ang + np.pi / 2)
            fenced_court(L, C, 18.3, 9.15, key)
            ck.tennis(L, C, key)
        if pool is not None:
            px, py = pool
            P = ck.Local(*F.pt(px, py), F.ang)
            deck = P.rect(-16.5, -9.0, 16.5, 9.0)
            L.fill("groundlines", deck, 0.24, 0.9, chunk=key)
            L.line("groundlines", deck.exterior, 0.12, 0.36, 0.7, chunk=key)
            basin = P.rect(-12.5, -6.25, 12.5, 6.25)
            L.fill("interiors", basin.buffer(0.4, join_style="mitre"), 0.32, chunk=key)
            L.fill("interiors", basin, 0.05, chunk=key)
            for k in range(1, 6):
                yy = -6.25 + k * 12.5 / 6
                L.line("interiors", P.line([(-11.5, yy), (11.5, yy)]), 0.12, 0.12, 0.8, chunk=key)
            ruins.add_rubble(L, "interiors", basin.buffer(-0.5), 0.02, (0.3, 0.9), rr, None)
        if volley is not None:
            V = ck.Local(*F.pt(*volley), F.ang)
            ck.surface(L, V.rect(-11.0, -6.5, 11.0, 6.5), SURFACE_V, 0.9, key)
            ck.volleyball(L, V, key)

    ex = x1 - east0
    courts, pool, volley = [], None, None
    n_courts = int(np.clip(ex // 18.6, 0, 3))
    cy_top = y0 + 2.0 + 18.3
    for k in range(n_courts):
        courts.append((east0 + 9.3 + k * 18.6, cy_top))
    club_w = min(ex - 2.0, r.uniform(28.0, 34.0))
    house_y1 = y1 - 1.0
    house = F.rect(east0 + 1.0, house_y1 - 16.0, east0 + 1.0 + club_w, house_y1)
    keep = [g.buffer(6.0) for g in gates]
    if ex > 30.0:
        building(site, house, "big")
        keep.append(house.buffer(TREE_CLEAR_M))
        made["club_buildings"] += 1
    mid_y0, mid_y1 = cy_top + 18.3 + 3.0, house_y1 - 16.0 - 3.0
    if ex >= 34.0 and mid_y1 - mid_y0 >= 18.0:
        pool = (east0 + 17.5, mid_y0 + 9.0)
        P = ck.Local(*F.pt(*pool), F.ang)
        site.obstacles.add(obstacles.POOL, P.rect(-12.5, -6.25, 12.5, 6.25))
        if mid_y1 - mid_y0 >= 18.0 + 14.0 and ex >= 24.0:
            volley = (east0 + 12.0, mid_y0 + 18.0 + 8.0)
    keep.append(stand(site, T, -36.0, -r_out - 1.5 - stand_d, 36.0, -r_out - 1.5, True, 1).buffer(TREE_CLEAR_M))
    made["club_buildings"] += 1
    sy1 = r_out + 1.5 + 5.0
    if y1 - ty > sy1 + 0.5:
        keep.append(stand(site, T, -22.0, r_out + 1.5, 22.0, sy1, False, -1).buffer(TREE_CLEAR_M))
        made["club_buildings"] += 1
    for cx, cy in courts:
        keep.append(ck.Local(*F.pt(cx, cy), F.ang + np.pi / 2).rect(-18.3, -9.15, 18.3, 9.15).buffer(TREE_CLEAR_M))
    if pool is not None:
        keep.append(ck.Local(*F.pt(*pool), F.ang).rect(-16.5, -9.0, 16.5, 9.0).buffer(TREE_CLEAR_M))
    if volley is not None:
        keep.append(ck.Local(*F.pt(*volley), F.ang).rect(-11.0, -6.5, 11.0, 6.5).buffer(TREE_CLEAR_M))
    floodlights(site, T, tl - 2.0, r_out - 4.0, r.uniform(*FLOODLIGHT_M), r, extra=2.0)
    for cx, cy in courts[:1]:
        C = ck.Local(*F.pt(cx, cy), F.ang)
        site.drawers.append(lambda L, x=C.pt(-8.0, -19.0), f=F.ang + np.pi / 2:
                            ck.floodlight(L, x[0], x[1], 12.0, f))
    site.drawers.append(draw)
    gx, gy = F.pt(east0 + 1.0 + club_w - 3.0, house_y1 - 16.0 - 1.0)
    keep.append(Point(gx, gy).buffer(3.0))
    site.drawers.append(lambda L, x=gx, y=gy, s=int(r.integers(1 << 30)):
                        equipment.add_source(site.salvage, L, "control_cabinet", x, y, F.ang,
                                             np.random.default_rng(s)))
    trees_along(site, area.exterior, 14.0, area.buffer(-3.0), r, avoid=unary_union(keep))


# --------------------------------------------------------------- schools

def school(site, cp, made):
    """A school compound: L or U building round a yard, a pitch and a
    basketball court where they fit, flagpole, wall and gate, trees."""
    F, w, h = cp.F, cp.w, cp.h
    r = ck.rng_at(411, cp.x, cp.y)
    d = r.uniform(10.0, 12.0)
    m = 1.5
    u_shape = r.random() < 0.45
    left = r.random() < 0.5
    sx = -1 if left else 1
    back = F.rect(-w / 2 + m, h / 2 - m - d, w / 2 - m, h / 2 - m)
    wing_y0 = -h / 2 + r.uniform(7.0, 12.0)
    wings = [back]
    side_a = F.rect(sx * (w / 2 - m) - (d if sx > 0 else 0.0), wing_y0, sx * (w / 2 - m) + (0.0 if sx > 0 else d),
                    h / 2 - m)
    wings.append(side_a)
    if u_shape:
        wings.append(F.rect(-sx * (w / 2 - m) - (d if -sx > 0 else 0.0), wing_y0,
                            -sx * (w / 2 - m) + (0.0 if -sx > 0 else d), h / 2 - m))
    poly = unary_union([g.buffer(0.01, join_style="mitre") for g in wings]).buffer(-0.01, join_style="mitre")
    poly = kit.largest(poly).simplify(0.05)
    building(site, poly, "school")
    keep = [poly.buffer(TREE_CLEAR_M)]
    yx0 = -w / 2 + m + (d + 3.0 if (u_shape or sx < 0) else 3.0)
    yx1 = w / 2 - m - (d + 3.0 if (u_shape or sx > 0) else 3.0)
    yy0, yy1 = -h / 2 + 4.0, h / 2 - m - d - 3.0
    yard = F.rect(yx0, yy0, yx1, yy1)
    yw, yh = yx1 - yx0, yy1 - yy0
    features = []
    for pl, pw in ((40.0, 22.0), (34.0, 20.0), (30.0, 18.0)):
        if yw - pl >= 30.0 and yh >= pw + 2.0:
            features = [("pitch", yx0 + 1.0 + pl / 2, (yy0 + yy1) / 2, pl, pw),
                        ("basket", yx1 - 1.0 - 14.0, (yy0 + yy1) / 2, 28.0, 15.0)]
        elif yh - pw >= 18.0 and yw >= max(pl, 28.0) + 2.0:
            features = [("pitch", (yx0 + yx1) / 2, yy1 - 1.0 - pw / 2, pl, pw),
                        ("basket", (yx0 + yx1) / 2, yy0 + 1.0 + 7.5, 28.0, 15.0)]
        if features:
            break
    if not features:
        if yw >= 32.0 and yh >= 20.0:
            pl = min(yw - 2.0, 40.0)
            features = [("pitch", (yx0 + yx1) / 2, (yy0 + yy1) / 2, pl, min(yh - 2.0, 22.0, pl * 0.62))]
        elif yw >= 30.0 and yh >= 17.0:
            features = [("basket", (yx0 + yx1) / 2, (yy0 + yy1) / 2, 28.0, 15.0)]
    gate = Point(F.pt(r.uniform(-w * 0.25, w * 0.25), -h / 2))
    gx, _ = F.to_local(gate.x, gate.y)
    flag = F.pt(gx + (5.0 if gx < 0 else -5.0), -h / 2 + 3.0)
    seed = int(r.integers(1 << 30))
    area = cp.poly

    def draw(L):
        key = style.chunk_key(area)
        L.fill("groundlines", area.buffer(-0.5), YARD_V, 0.85, chunk=key)
        ck.compound_wall(L, area.exterior, v=0.3, width=0.5, gates=[gate], gap=5.0)
        for kind, cx, cy, ln, wd in features:
            C = ck.Local(*F.pt(cx, cy), F.ang)
            ck.surface(L, C.rect(-ln / 2 - 1.0, -wd / 2 - 1.0, ln / 2 + 1.0, wd / 2 + 1.0), SURFACE_V, 0.9, key,
                       edge_v=0.3)
            if kind == "pitch":
                ck.football(L, C, ln, wd, key)
            else:
                ck.basketball(L, C, key, ln, wd)
    site.drawers.append(draw)
    fh = r.uniform(9.0, 11.0)
    site.drawers.append(lambda L, x=flag[0], y=flag[1], s=seed: ck.flagpole(L, x, y, fh, F.ang,
                                                                           np.random.default_rng(s)))
    keep += [gate.buffer(6.0), Point(flag).buffer(2.5)]
    for kind, cx, cy, ln, wd in features:
        keep.append(ck.Local(*F.pt(cx, cy), F.ang).rect(-ln / 2 - 1.0, -wd / 2 - 1.0, ln / 2 + 1.0, wd / 2 + 1.0))
    front = LineString([F.pt(-w / 2 + 3.0, -h / 2 + 2.5), F.pt(w / 2 - 3.0, -h / 2 + 2.5)])
    trees_along(site, front, 9.0, area.buffer(-2.5), r, (6.0, 9.0), avoid=unary_union(keep))
    made["schools"] += 1


# ---------------------------------------------------------------- pitches

def municipal_pitch(site, cp, made):
    """A walled football ground: pitch, small stand on one long side,
    changing room, four floodlight masts, gate."""
    F, w, h = cp.F, cp.w, cp.h
    r = ck.rng_at(421, cp.x, cp.y)
    sd = 5.0
    pl = min(w - 10.0, 64.0)
    pw = min(h - 10.0 - sd, 40.0)
    py = -h / 2 + 4.0 + pw / 2
    P = ck.Local(*F.pt(0.0, py), F.ang)
    sl = min(pl * 0.5, 34.0)
    stand(site, F, -sl / 2, py + pw / 2 + 2.0, sl / 2, py + pw / 2 + 2.0 + sd, False, -1)
    cw, cd = min(11.0, pl / 2 - sl / 2 - 3.0), min(7.0, h / 2 - 1.5 - (py + pw / 2 + 2.0))
    if cw * cd >= 62.0:
        side = 1 if r.random() < 0.5 else -1
        xa = side * (sl / 2 + 2.0)
        room = F.rect(min(xa, xa + side * cw), py + pw / 2 + 2.0, max(xa, xa + side * cw), py + pw / 2 + 2.0 + cd)
        building(site, room, "house")
    floodlights(site, P, pl / 2 + 1.5, pw / 2 + 1.5, r.uniform(*PITCH_FLOODLIGHT_M), r)
    gate = Point(F.pt(r.uniform(-w * 0.3, w * 0.3), -h / 2))
    area = cp.poly

    def draw(L):
        key = style.chunk_key(area)
        L.fill("groundlines", area.buffer(-0.5), 0.17, 0.8, chunk=key)
        ck.surface(L, P.rect(-pl / 2 - 2.0, -pw / 2 - 2.0, pl / 2 + 2.0, pw / 2 + 2.0), SURFACE_V, 0.95, key)
        ck.football(L, P, pl, pw, key)
        ck.compound_wall(L, area.exterior, v=0.3, width=0.55, gates=[gate], gap=6.0)
    site.drawers.append(draw)
    made["pitches"] += 1


# ------------------------------------------------------------------ build

def build(site, lay, spots):
    """The club, schools and pitches; spots collects the compounds' centres
    (for the spacing of the compounds built after them)."""
    made = {"club": 0, "club_district": 0, "club_buildings": 0, "schools": 0, "pitches": 0, "school_at": [],
            "pitch_at": []}
    build_club(site, lay, made)
    cands = ck.compound_sites(site, lay, SCHOOL_SIZES, (RESIDENTIAL,), 431)
    for p in ck.grid_pick(ck.away_from(cands, spots, ck.COMPOUND_GAP_M), 4, SCHOOL_SPACING_M, (), SCHOOLS):
        cp = p["site"]
        spots.append((cp.x, cp.y))
        made["school_at"].append([round(cp.x), round(cp.y)])
        if ck.take_compound(site, cp, "civic:school"):
            school(site, cp, made)
    cands = ck.compound_sites(site, lay, PITCH_SIZES, (RESIDENTIAL,), 441)
    for p in ck.grid_pick(ck.away_from(cands, spots, ck.COMPOUND_GAP_M), 3, PITCH_SPACING_M, (), PITCHES):
        cp = p["site"]
        spots.append((cp.x, cp.y))
        made["pitch_at"].append([round(cp.x), round(cp.y)])
        if ck.take_compound(site, cp, "civic:pitch"):
            municipal_pitch(site, cp, made)
    return made
