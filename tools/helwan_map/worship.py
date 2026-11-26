"""Mosques and Coptic church compounds.

Mosques: minarets are what players steer by, so every mosque has one (the
large ones two), in the talls sublayer (25 to 40 m, styles in
civickit.minaret: octagonal tiered Mamluk-like, slim Ottoman pencil with a
cone cap, modern square shaft; balcony rings), and a dome on its roof (at
the roof's middle where it fits clear of the minaret, else at the nearest
point where it does, else as large as fits at the point deepest inside the
roof: dome_spot).

  OSM mosques     every OSM mosque in the play area (amenity
                  place_of_worship with religion muslim, or building mosque)
                  except the Japanese Garden Mosque, which the landmarks
                  module builds: its building becomes kind "mosque", with a
                  minaret at its street corner and, where the ground beside
                  it is free (also of district module content), a walled
                  courtyard with an ablution fountain
  large mosques   LARGE_MOSQUES rebuilt block corners on main roads,
                  LARGE_MOSQUE_SPACING_M from the OSM mosques and each
                  other: a prayer hall on the side towards the qibla
                  (south-east from Cairo) under a large dome, an open
                  courtyard (sahn) with a domed fountain, arcades (riwaq)
                  round its other sides, two minarets on the entrance front
  neighbourhood   street-corner and street-facing buildings of 200 to
  mosques         1,500 m2 in residential and market areas, converted in
                  place: one per cell of a MOSQUE_GRID grid over the play
                  area (the best building, nearest the cell's middle), at
                  least MOSQUE_SPACING_M from any other mosque, large ones
                  included

Coptic church compounds (CHURCHES): a walled yard with a gate on the
street, a church along the yard's long axis with a row of small domes over
the sanctuary at its east end, a central dome and twin bell towers at its
west front (talls, 20 to 25 m), a service building and trees.

A converted or OSM mosque keeps its ruin state from the damage map, but no
worse than damaged, so its dome and minaret stand; where the map says
gutted or worse, a share of them (BROKEN_MINARET) is gutted with only a
stump of its minaret left. Compound walls are drawing only, as the farm
yards' and military compounds' walls are; the buildings in them are
ordinary buildings.
"""
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import nearest_points, polylabel, unary_union

import buildings as bl
import civickit as ck
import kit
import ruins
import style
from districts import MARKET, RESIDENTIAL
from gen_city import min_width, rect_fill, to_frame_m

JAPANESE_GARDEN_MOSQUE = (1939.0, -962.0)
## Neighbourhood mosques: one per cell of a MOSQUE_GRID x MOSQUE_GRID grid
## over the play area where a cell has a good building.
MOSQUE_GRID = 6
## When a district module has taken a neighbourhood mosque's building, the
## best other building within this distance (m) that keeps the spacing.
FALLBACK_M = 150.0
MOSQUE_SPACING_M = 250.0
MOSQUE_M2 = (200.0, 1500.0)
## Narrowest building that becomes a mosque (m).
MOSQUE_MIN_W_M = 10.0
LARGE_MOSQUES = 3
## Least distance from a large mosque to any other mosque (m).
LARGE_MOSQUE_SPACING_M = 700.0
LARGE_MOSQUE_SIZES = ((56.0, 46.0), (60.0, 50.0), (52.0, 44.0))
CHURCHES = 3
CHURCH_SIZES = ((50.0, 40.0), (54.0, 42.0), (46.0, 38.0))
MINARET_M = (25.0, 34.0)
LARGE_MINARET_M = (34.0, 40.0)
BELL_TOWER_M = (20.0, 25.0)
BROKEN_MINARET = 0.5
## Qibla from Helwan: about 136 degrees from north, so south-east on the
## map (x east, y south).
QIBLA = np.array([np.sin(np.radians(136.0)), -np.cos(np.radians(136.0))])
DOME_KINDS = ("plain", "ribbed", "multi")


# ------------------------------------------------------------------- roofs

def roof_mosque(L, b, rng):
    """A flat roof with a crenellated parapet, kept clear round the minaret's
    base, and the mosque's dome: a large plain or ribbed dome over the
    prayer hall, or a main dome with two smaller ones beside it; then a
    water tank or vents."""
    g = b.poly
    o = b.opts
    v = style.roof_value(b.mv) * rng.uniform(1.0, 1.3)
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    inner = style.set_inner(R, g, 0.5)
    R.shade_in(inner, 1.0, 0.35)
    R.ring(inner, style.PARAPET_W, style.PARAPET_V)
    ck.crenellations(L, "roofs", inner, 0.32, R.key)
    m = o.get("minaret")
    msq = ck.square(m[0], m[1], m[2] + 1.2, m[3]) if m is not None else None
    if msq is not None:
        R.taken.append(msq)
    kind = o.get("dome", "plain")
    side = min(R.x1 - R.x0, R.y1 - R.y0)
    length = R.x1 - R.x0
    r = float(np.clip(side * 0.3, 2.0, 9.5))
    dv = min(v * 2.6, 0.3)
    room = kit.largest(g.buffer(-0.3))
    if room is not None and msq is not None:
        room = kit.largest(room.difference(msq.buffer(0.3, join_style="mitre")))
    mid = R.rect((R.x0 + R.x1) / 2 - 0.01, (R.y0 + R.y1) / 2 - 0.01, (R.x0 + R.x1) / 2,
                 (R.y0 + R.y1) / 2).centroid
    main = dome_spot(room, mid.x, mid.y, r)
    if main is not None:
        wx, wy, rr = main
        domes = [(wx, wy, rr)]
        if kind == "multi" and length > 4.2 * rr:
            lx, ly = to_local(R, wx, wy)
            for s in (-1, 1):
                sx, sy = R.rect(lx + s * rr * 1.75 - 0.01, ly - 0.01, lx + s * rr * 1.75, ly).centroid.coords[0]
                domes.append((sx, sy, rr * 0.55))
        placed = []
        for k, (x, y, rd) in enumerate(domes):
            disc = ck.ngon(x, y, rd * 1.15, 16)
            if k > 0 and (not room.contains(disc) or any(disc.intersects(d) for d in placed)):
                continue
            ck.dome(L, "roofs", x, y, rd, dv * (1.0 if k == 0 else 0.9), R.key,
                    ribs=24 if kind == "ribbed" and k == 0 else 0)
            R.taken.append(disc)
            placed.append(disc)
    for _ in range(int(rng.integers(1, 3))):
        style.pick([(style.item_tanks, 0.6), (style.item_vents, 0.4)], rng)(R, 1.0 if g.area < 500 else 1.6)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return R


def dome_spot(room, x, y, r, min_r=1.8):
    """Centre and radius (x, y, r) of the main dome: radius r at the point
    nearest (x, y) where its disc (1.15 r, with the drum) fits inside room;
    where it fits nowhere, as large as fits at the point deepest inside
    room; None when that is under min_r."""
    if room is None or room.is_empty:
        return None
    core = room.buffer(-r * 1.15 - 0.05)
    if not core.is_empty:
        p = nearest_points(core, Point(x, y))[0]
        if room.contains(ck.ngon(p.x, p.y, r * 1.15, 16)):
            return p.x, p.y, r
    p = polylabel(room, 0.2)
    rr = min(r, room.boundary.distance(p) / 1.15 - 0.1)
    if rr < min_r or not room.contains(ck.ngon(p.x, p.y, rr * 1.15, 16)):
        return None
    return p.x, p.y, rr


def to_local(R, x, y):
    a = np.radians(R.ang)
    dx, dy = x - R.c.x, y - R.c.y
    return dx * np.cos(a) + dy * np.sin(a), -dx * np.sin(a) + dy * np.cos(a)


def roof_riwaq(L, b, rng):
    """An arcade round a courtyard: a flat roof with a parapet and a row of
    small domes, one per bay (Ottoman), or crenellations only."""
    g = b.poly
    v = style.roof_value(b.mv) * rng.uniform(1.0, 1.25)
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    inner = style.set_inner(R, g, 0.4)
    R.ring(inner, style.PARAPET_W, style.PARAPET_V)
    bays = b.opts.get("bays", [])
    if bays:
        for x, y, rr in bays:
            if g.buffer(-0.2).contains(Point(x, y).buffer(rr)):
                ck.dome(L, "roofs", x, y, rr, min(v * 2.3, 0.26), R.key, steps=2, n=10, drum=False)
    else:
        ck.crenellations(L, "roofs", inner, 0.32, R.key)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return None


def roof_church(L, b, rng):
    """A church roof: flat with a parapet, a row of small domes across the
    sanctuary at its east end, a larger dome over the nave, crosses on the
    domes."""
    g = b.poly
    o = b.opts
    v = style.roof_value(b.mv) * rng.uniform(1.1, 1.35)
    R = style.Roof(L, g, v, rng)
    R.fill(g, v)
    inner = style.set_inner(R, g, 0.5)
    R.shade_in(inner, 1.0, 0.35)
    R.ring(inner, style.PARAPET_W, style.PARAPET_V)
    F = ck.Local(*o["axis"])
    hl, hw = o["half"]
    dv = min(v * 2.5, 0.3)
    small = min(hw * 0.27, 2.6)
    east = hl - small - 1.4
    marks = []
    for k in (-1, 0, 1):
        marks.append((east, k * hw * 0.6, small))
    marks.append((hl * 0.05, 0.0, min(hw * 0.62, 6.5)))
    if hl > 14:
        marks.append((-hl * 0.45, 0.0, min(hw * 0.4, 4.0)))
    for x, y, rr in marks:
        wx, wy = F.pt(x, y)
        if not g.buffer(-0.3).contains(Point(wx, wy).buffer(rr * 1.1)):
            continue
        ck.dome(L, "roofs", wx, wy, rr, dv, R.key, steps=3 if rr < 3 else 4)
        s = max(0.35, rr * 0.22)
        for a in (F.ang, F.ang + np.pi / 2):
            L.line("roofs", LineString([(wx - np.cos(a) * s, wy - np.sin(a) * s),
                                        (wx + np.cos(a) * s, wy + np.sin(a) * s)]), 0.12, 0.5, chunk=R.key)
    R.ring(g, style.OUTLINE_W, style.OUTLINE_V)
    return None


bl.KINDS["mosque"] = (roof_mosque, True, 3.0)
bl.KINDS["riwaq"] = (roof_riwaq, False, style.HALO_HOUSE_M)
bl.KINDS["church"] = (roof_church, True, 3.0)


# --------------------------------------------------------------- pieces

def minaret_spot(poly, side, roads_u):
    """The minaret's base: a square of side `side` (smaller if it does not
    fit) in the footprint's corner nearest the road, turned with the
    footprint, as (x, y, side, angle)."""
    ang, _ = style.frame_of(poly)
    a = np.radians(ang)
    for s in (side, side * 0.85, 2.6):
        inner = kit.largest(poly.buffer(-(s * 0.72 + 0.3), join_style="mitre"))
        if inner is None:
            continue
        pts = [Point(p) for p in inner.exterior.coords[:-1]]
        if roads_u is not None:
            pts.sort(key=lambda p: roads_u.distance(p))
        for p in pts:
            if poly.buffer(-0.2).contains(ck.square(p.x, p.y, s, a)):
                return (p.x, p.y, s, a)
    return None


def courtyard(L, area, F, wall_gate=None):
    """A paved courtyard with a low wall and an ablution fountain (an
    octagonal basin under a small domed canopy)."""
    key = style.chunk_key(area)
    L.fill("groundlines", area, 0.22, 0.9, chunk=key)
    L.line("groundlines", area.exterior, 0.12, 0.33, 0.7, chunk=key)
    Q = F.quads()
    lx = [F.to_local(x, y) for x, y in area.exterior.coords]
    x0, x1 = min(p[0] for p in lx), max(p[0] for p in lx)
    y0, y1 = min(p[1] for p in lx), max(p[1] for p in lx)
    for xx in np.arange(x0 + 2.0, x1, 2.0):
        Q.line(xx, y0, xx, y1, 0.05, 0.16, 0.7)
    for yy in np.arange(y0 + 2.0, y1, 2.0):
        Q.line(x0, yy, x1, yy, 0.05, 0.16, 0.7)
    Q.flush(L, "groundlines", key)
    if wall_gate is not None:
        ck.compound_wall(L, area.exterior, v=0.3, width=0.4, gates=[wall_gate], gap=3.0, chunk=key)
    c = area.centroid
    rad = min(x1 - x0, y1 - y0) * 0.16
    if rad >= 1.0:
        L.fill("interiors", ck.ngon(c.x, c.y, rad * 1.3, 8, F.ang + np.pi / 8), 0.0, 0.4, chunk=key)
        L.fill("interiors", ck.ngon(c.x, c.y, rad * 1.15, 8, F.ang + np.pi / 8), 0.3, chunk=key)
        L.fill("interiors", ck.ngon(c.x, c.y, rad * 0.85, 8, F.ang + np.pi / 8), 0.05, chunk=key)
        ck.dome(L, "interiors", c.x, c.y, rad * 0.55, 0.3, key, steps=2, n=8, drum=False)


def draw_minaret(L, x, y, h, style_name, ang, seed, broken):
    ck.minaret(L, x, y, h, style_name, ang, np.random.default_rng(seed), broken)


def mosque_state(x, y, district, r):
    """(pinned state, broken minaret) for a mosque at (x, y)."""
    s = ruins.state_at(x, y, district)
    if s >= ruins.GUTTED and r.random() < BROKEN_MINARET:
        return ruins.GUTTED, True
    return min(s, ruins.DAMAGED), False


def make_mosque(site, b, roads_u, r, height, style_name=None, dome=None):
    """Turns building b into a mosque with a minaret at its street corner.
    Returns the minaret's spot or None."""
    side = r.uniform(3.2, 4.0) if b.poly.area > 260 else 3.0
    spot = minaret_spot(b.poly, side, roads_u)
    if spot is None:
        return None
    style_name = style_name or ck.MINARET_STYLES[int(r.integers(len(ck.MINARET_STYLES)))]
    c = b.poly.centroid
    state, broken = mosque_state(c.x, c.y, int(site.districts.of_geom(b.poly)), r)
    b.kind = "mosque"
    b.opts.update(state=state, minaret=spot, dome=dome or DOME_KINDS[int(r.integers(len(DOME_KINDS)))])
    seed = int(r.integers(1 << 30))
    site.drawers.append(lambda L, s=spot, h=height, st=style_name, sd=seed, br=broken:
                        draw_minaret(L, s[0], s[1], h, st, s[3], sd, br))
    return spot


# ------------------------------------------------------------- OSM mosques

def osm_mosques(site):
    """OSM mosque outlines in the play area, less the Japanese Garden
    Mosque."""
    out = []
    for kind, rings, p in site.feats or []:
        if kind != "poly":
            continue
        if not (p.get("building") == "mosque" or (p.get("amenity") == "place_of_worship"
                                                  and p.get("religion") == "muslim")):
            continue
        g = Polygon(to_frame_m(rings[0])).buffer(0)
        c = g.centroid
        if max(abs(c.x), abs(c.y)) > ck.PLAY_HALF_M - 10:
            continue
        if "Japanese" in str(p.get("name:en", "")) or c.distance(Point(*JAPANESE_GARDEN_MOSQUE)) < 40:
            continue
        out.append(g)
    return out


def best_roof(cands, g):
    best, area = None, 0.0
    for b in cands:
        a = b.intersection(g).area
        if a > area:
            best, area = b, a
    return best if area > 0.4 * g.area else None


def build_osm_mosques(site, lay, made):
    spots = []
    for g in osm_mosques(site):
        roof = best_roof(lay.big_in(g), g)
        if roof is None:
            made["osm_missing"] += 1
            continue
        c = roof.centroid
        if not site.is_free(roof.buffer(-0.5), districts=False):
            made["osm_claimed"] += 1
            continue
        spots.append((c.x, c.y))
        made["osm_at"].append([round(c.x), round(c.y)])
        r = ck.rng_at(301, c.x, c.y)
        height = r.uniform(*MINARET_M) + 3.0
        yard = osm_courtyard(site, lay, roof, r)
        site.claim(roof, "civic:mosque")
        if yard is not None:
            site.claim(yard[0], "civic:mosque_yard")
        if not site.in_window(roof):
            continue
        b = ck.find_building(site, roof)
        if b is None:
            made["osm_missing"] += 1
            continue
        roads_u = lay.roads_near(roof, 25.0)
        if make_mosque(site, b, roads_u, r, height) is not None:
            made["osm"] += 1
        d = site.district_taken()
        if yard is not None and d is not None and d.intersects(yard[0]):
            made["courtyards_district"] += 1
            yard = None
        if yard is not None:
            area, F, gate = yard
            ck.clear_for(site, area)
            site.solid_extra.append(area)
            site.drawers.append(lambda L, a=area, F=F, gt=gate: courtyard(L, a, F, gt))
            made["courtyards"] += 1
    return spots


def osm_courtyard(site, lay, roof, r):
    """A courtyard on the side of the mosque away from the road, where the
    ground is free of roads, large roofs and claims: (area, frame, gate)."""
    ang, c = style.frame_of(roof)
    a = np.radians(ang)
    F = ck.Local(c.x, c.y, a)
    lx = [F.to_local(x, y) for x, y in roof.exterior.coords]
    x0, x1 = min(p[0] for p in lx), max(p[0] for p in lx)
    y0, y1 = min(p[1] for p in lx), max(p[1] for p in lx)
    roads_u = lay.roads_near(roof, 30.0)
    opts = []
    for depth in (14.0, 11.0, 8.5):
        opts += [F.rect(x0, y1 + 0.3, x1, y1 + 0.3 + depth), F.rect(x0, y0 - 0.3 - depth, x1, y0 - 0.3),
                 F.rect(x1 + 0.3, y0, x1 + 0.3 + depth, y1), F.rect(x0 - 0.3 - depth, y0, x0 - 0.3, y1)]
    best = None
    for rect in opts:
        if rect.area < 60.0:
            continue
        if roads_u is not None and roads_u.buffer(1.5).intersects(rect):
            continue
        if any(not b.equals(roof) and b.intersects(rect) for b in lay.big_in(rect)):
            continue
        if not site.is_free(rect, margin=1.0, districts=False):
            continue
        d = (roads_u.distance(rect) if roads_u is not None else 30.0) + 0.5 * min(rect.area, 300.0) ** 0.5
        if best is None or d > best[0]:
            best = (d, rect)
    if best is None:
        return None
    rect = best[1]
    gate = rect.exterior.interpolate(rect.exterior.project(roads_u.centroid)) if roads_u is not None else None
    return rect, ck.Local(rect.centroid.x, rect.centroid.y, a), gate


# ---------------------------------------------------- neighbourhood mosques

def mosque_candidates(site, lay):
    """Street-facing lots and large roofs of MOSQUE_M2 in residential and
    market areas, scored: street corners, main roads and middling sizes
    first, generated lots before real roofs."""
    out = []
    for polys, is_lot in ((lay.lots, True), (lay.big, False)):
        for g in polys:
            a = g.area
            if a < MOSQUE_M2[0] or a > MOSQUE_M2[1]:
                continue
            c = g.centroid
            if max(abs(c.x), abs(c.y)) > ck.PLAY_HALF_M - 40:
                continue
            if min_width(g) < MOSQUE_MIN_W_M or rect_fill(g) < 0.7 or g.length ** 2 / a > 22.0:
                continue
            code = int(site.districts.at(c.x, c.y))
            if code not in (RESIDENTIAL, MARKET):
                continue
            lines = lay.roads_at(g, 2.5)
            if not lines:
                continue
            dirs = []
            for line, kind, _ in lines:
                p = line.interpolate(line.project(c))
                q = line.interpolate(min(line.project(c) + 1.0, line.length))
                dirs.append(np.arctan2(q.y - p.y, q.x - p.x) % np.pi)
            corner = any(abs(((d1 - d2) + np.pi / 2) % np.pi - np.pi / 2) > 0.5 for d1 in dirs for d2 in dirs)
            main = any(k in ck.MAIN_ROADS for _, k, _ in lines)
            score = 2.0 * corner + 1.0 * main + (1.0 if 250 <= a <= 900 else 0.0) + (0.5 if is_lot else 0.0)
            out.append({"x": c.x, "y": c.y, "score": score, "poly": g, "lot": is_lot})
    return out


def build_neighbourhood(site, lay, seeds, made):
    cands = mosque_candidates(site, lay)
    claimed = site.claimed()
    if claimed is not None:
        cands = [c for c in cands if not claimed.intersects(c["poly"])]
    # Picks that fail Site.is_free (KeepOut, markers) leave the candidates
    # and the grid is picked again.
    while True:
        picks = ck.grid_pick(cands, MOSQUE_GRID, MOSQUE_SPACING_M, seeds)
        bad = {id(p) for p in picks if not site.is_free(p["poly"].buffer(-0.5), districts=False)}
        if not bad:
            break
        cands = [c for c in cands if id(c) not in bad]
    xy = np.array([(c["x"], c["y"]) for c in cands]) if cands else np.zeros((0, 2))
    others = list(seeds) + [(p["x"], p["y"]) for p in picks]
    for p in picks:
        site.claim(p["poly"], "civic:mosque")
        made["neighbourhood_at"].append([round(p["x"]), round(p["y"])])
    for p in picks:
        if not site.in_window(p["poly"]):
            continue
        # The pick first, then, when a district module took its building,
        # the best candidates within FALLBACK_M that keep the spacing.
        near = np.flatnonzero(np.hypot(xy[:, 0] - p["x"], xy[:, 1] - p["y"]) <= FALLBACK_M)
        alts = sorted((cands[i] for i in near if cands[i] is not p),
                      key=lambda c: (-c["score"], np.hypot(c["x"] - p["x"], c["y"] - p["y"])))
        done = False
        for c in [p] + alts:
            if c is not p and any(np.hypot(c["x"] - x, c["y"] - y) < MOSQUE_SPACING_M
                                  for x, y in others if (x, y) != (p["x"], p["y"])):
                continue
            if c is not p and not site.is_free(c["poly"].buffer(-0.5), districts=False):
                continue
            b = ck.find_building(site, c["poly"])
            if b is None or b.kind not in ("house", "big"):
                continue
            r = ck.rng_at(311, c["x"], c["y"])
            if make_mosque(site, b, lay.roads_near(c["poly"], 25.0), r, r.uniform(*MINARET_M)) is not None:
                site.claim(c["poly"], "civic:mosque")
                made["neighbourhood"] += 1
                if c is not p:
                    made["neighbourhood_moved"] += 1
                    made["neighbourhood_moved_to"].append([round(p["x"]), round(p["y"]), round(c["x"]),
                                                           round(c["y"])])
                done = True
                break
        if not done:
            made["neighbourhood_missing"] += 1
    return [(p["x"], p["y"]) for p in picks]


# ------------------------------------------------------------ large mosques

def large_mosque(site, cp, made):
    """A rebuilt block corner: prayer hall on the side nearest the qibla,
    courtyard with arcades and a fountain, two minarets on the front."""
    F, w, h = cp.F, cp.w, cp.h
    r = ck.rng_at(321, cp.x, cp.y)
    # The compound frame's y points in from the street; the prayer hall
    # goes on whichever side faces the qibla best.
    sides = {"back": np.array(F.pt(0, 1)) - np.array(F.pt(0, 0)),
             "left": np.array(F.pt(-1, 0)) - np.array(F.pt(0, 0)),
             "right": np.array(F.pt(1, 0)) - np.array(F.pt(0, 0))}
    side = max(sides, key=lambda k: float(sides[k] @ QIBLA))
    hall_d = r.uniform(17.0, 21.0)
    riwaq = r.uniform(4.5, 5.5)
    hx, hy = w / 2 - 1.0, h / 2 - 1.0
    if side == "back":
        hall = F.rect(-hx, hy - hall_d, hx, hy)
        yard = (-hx + riwaq, -hy + riwaq, hx - riwaq, hy - hall_d - 1.0)
    elif side == "left":
        hall = F.rect(-hx, -hy, -hx + hall_d, hy)
        yard = (-hx + hall_d + 1.0, -hy + riwaq, hx - riwaq, hy - riwaq)
    else:
        hall = F.rect(hx - hall_d, -hy, hx, hy)
        yard = (-hx + riwaq, -hy + riwaq, hx - hall_d - 1.0, hy - riwaq)
    yx0, yy0, yx1, yy1 = yard
    outer = F.rect(-hx, -hy, hx, hy)
    gate_w = r.uniform(5.0, 7.0)
    arc = outer.difference(hall.buffer(0.5, join_style="mitre")).difference(F.rect(yx0, yy0, yx1, yy1))
    arc = arc.difference(F.rect(-gate_w / 2, -hy - 1.0, gate_w / 2, yy0 + 0.5))
    mv = float(site.sampler.value(cp.x, cp.y))
    c = hall.centroid
    state, broken = mosque_state(c.x, c.y, 0, r)
    hb = bl.Building(hall, mv, "mosque")
    hb.opts.update(state=state, dome=str(r.choice(["multi", "ribbed", "plain"])))
    site.buildings.append(hb)
    otto = r.random() < 0.5
    for part in style.polys(arc):
        if part.area < 60.0:
            continue
        bays = []
        if otto:
            mid = LineString(outer.buffer(-riwaq / 2, join_style="mitre").exterior.coords)
            room = part.buffer(-0.3)
            for d in np.arange(riwaq / 2, mid.length, riwaq):
                p = mid.interpolate(d)
                if room.contains(p.buffer(riwaq * 0.38)):
                    bays.append((p.x, p.y, riwaq * 0.36))
        rb = bl.Building(part, mv, "riwaq", bays=bays)
        rb.opts["state"] = min(ruins.state_at(part.centroid.x, part.centroid.y, 0), ruins.DAMAGED)
        site.buildings.append(rb)
    yard_poly = F.rect(yx0, yy0, yx1, yy1)
    site.drawers.append(lambda L, a=yard_poly: courtyard(L, a, ck.Local(a.centroid.x, a.centroid.y, F.ang)))
    st = ck.MINARET_STYLES[int(r.integers(len(ck.MINARET_STYLES)))]
    height = r.uniform(*LARGE_MINARET_M)
    for k, sx in enumerate((-1, 1)):
        mx, my = F.pt(sx * (gate_w / 2 + 3.0), -hy + riwaq / 2)
        sd = int(r.integers(1 << 30))
        site.drawers.append(lambda L, x=mx, y=my, sd=sd, br=broken and k == 0:
                            draw_minaret(L, x, y, height, st, F.ang, sd, br))
    made["large"] += 1


# --------------------------------------------------------------- churches

def church(site, cp, made):
    """A Coptic church compound: wall and gate, the church along the
    compound's axis nearest east-west with its sanctuary at the east end,
    twin bell towers at its west front, a paved forecourt before the west
    door with a path from the gate, a service building, and trees round the
    inside of the wall."""
    F, w, h = cp.F, cp.w, cp.h
    r = ck.rng_at(331, cp.x, cp.y)
    ex = np.array(F.pt(1, 0)) - np.array(F.pt(0, 0))
    along_x = abs(ex[0]) >= 0.5
    cl, cw = (r.uniform(26.0, 32.0), r.uniform(13.0, 16.0))
    if along_x:
        cl, cw = min(cl, w - 12.0), min(cw, h - 16.0)
        east = 1 if ex[0] > 0 else -1
        cx, cy = 0.0, (h / 2 - 3.0) - cw / 2
        poly = F.rect(cx - cl / 2, cy - cw / 2, cx + cl / 2, cy + cw / 2)
        axis = (F.pt(cx, cy)[0], F.pt(cx, cy)[1], F.ang if east > 0 else F.ang + np.pi)
    else:
        cl, cw = min(cl, h - 10.0), min(cw, w - 18.0)
        ey = np.array(F.pt(0, 1)) - np.array(F.pt(0, 0))
        east = 1 if ey[0] > 0 else -1
        cx, cy = (w / 2 - 3.0) - cw / 2, (h / 2 - 3.0) - cl / 2 + 1.0
        poly = F.rect(cx - cw / 2, cy - cl / 2, cx + cw / 2, cy + cl / 2)
        axis = (F.pt(cx, cy)[0], F.pt(cx, cy)[1], F.ang + np.pi / 2 if east > 0 else F.ang - np.pi / 2)
    if cl < 18.0 or cw < 10.0:
        return
    mv = float(site.sampler.value(cp.x, cp.y))
    c = poly.centroid
    b = bl.Building(poly, mv, "church", axis=axis, half=(cl / 2, cw / 2))
    b.opts["state"] = min(ruins.state_at(c.x, c.y, 0), ruins.DAMAGED)
    site.buildings.append(b)
    A = ck.Local(*axis)
    tower = r.uniform(3.4, 4.2)
    th = r.uniform(*BELL_TOWER_M)
    cap = "dome" if r.random() < 0.6 else "pyramid"
    for s in (-1, 1):
        tx, ty = A.pt(-cl / 2 + tower / 2 + 0.6, s * (cw / 2 - tower / 2 - 0.6))
        site.drawers.append(lambda L, x=tx, y=ty: ck.bell_tower(L, x, y, tower, th, A.ang, cap=cap))
    sw, sd = r.uniform(9.0, 13.0), r.uniform(7.0, 8.5)
    service = F.rect(-w / 2 + 2.0, -h / 2 + 4.0, -w / 2 + 2.0 + sd, -h / 2 + 4.0 + sw) if not along_x else \
        F.rect(-w / 2 + 2.0, -h / 2 + 3.0, -w / 2 + 2.0 + sw, -h / 2 + 3.0 + sd)
    if not service.intersects(poly.buffer(3.0)) and service.area >= 60.0:
        sb = bl.Building(service, mv, "house")
        site.buildings.append(sb)
    gate = Point(F.pt(r.uniform(-w * 0.2, w * 0.2), -h / 2))
    yard = cp.poly
    # A paved forecourt before the west door and a path to it from the gate:
    # in from the gate, then across to the door, less any part that would
    # run under the church.
    inner = yard.buffer(-1.0, join_style="mitre")
    fore = A.rect(-cl / 2 - 7.0, -cw / 2 + 1.0, -cl / 2 - 0.2, cw / 2 - 1.0).intersection(inner)
    door = A.pt(-cl / 2 - 3.5, 0.0)
    gx, _ = F.to_local(gate.x, gate.y)
    _, dy = F.to_local(*door)
    path = F.line([(gx, -h / 2 + 0.5), (gx, dy)]).union(LineString([F.pt(gx, dy), door]))
    path = path.buffer(1.6, cap_style="flat", join_style="mitre").difference(poly.buffer(0.6)).intersection(inner)

    def draw(L, yard=yard, gate=gate, fore=fore, path=path):
        key = style.chunk_key(yard)
        L.fill("groundlines", yard.buffer(-0.4), 0.2, 0.8, chunk=key)
        for g, v in ((path, 0.25), (fore, 0.26)):
            if not g.is_empty:
                L.fill("groundlines", g, v, 0.85, chunk=key)
        if not fore.is_empty:
            for g in style.polys(fore):
                L.line("groundlines", g.exterior, 0.12, 0.33, 0.7, chunk=key)
        ck.compound_wall(L, yard.exterior, v=0.3, width=0.55, gates=[gate], gap=4.5)
    site.drawers.append(draw)
    # Trees round the inside of the wall, clear of the buildings, the path
    # and the forecourt.
    keep = unary_union([poly.buffer(4.0), service.buffer(3.0), path.buffer(2.5), fore.buffer(2.5),
                        gate.buffer(6.0)])
    ring = yard.buffer(-2.8, join_style="mitre").exterior
    d = r.uniform(2.0, 9.0)
    while d < ring.length:
        p = ring.interpolate(d)
        d += r.uniform(7.5, 11.0)
        if not keep.contains(p):
            site.props.add("tree", p.x, p.y, r.uniform(0, 2 * np.pi), (r.uniform(7, 10),) * 2)
    made["churches"] += 1


def build_large_and_churches(site, lay, made, mosque_seeds, spots):
    cands = ck.compound_sites(site, lay, LARGE_MOSQUE_SIZES, (RESIDENTIAL, MARKET), 341)
    cands = [c for c in ck.away_from(cands, spots, ck.COMPOUND_GAP_M) if c["site"].main_road]
    picks = ck.grid_pick(cands, 2, LARGE_MOSQUE_SPACING_M, mosque_seeds, LARGE_MOSQUES)
    mosque_spots = []
    for p in picks:
        cp = p["site"]
        mosque_spots.append((cp.x, cp.y))
        spots.append((cp.x, cp.y))
        made["large_at"].append([round(cp.x), round(cp.y)])
        if ck.take_compound(site, cp, "civic:large_mosque"):
            large_mosque(site, cp, made)
    cands = ck.compound_sites(site, lay, CHURCH_SIZES, (RESIDENTIAL,), 351)
    picks = ck.grid_pick(ck.away_from(cands, spots, ck.COMPOUND_GAP_M), 2, 1200.0, (), CHURCHES)
    for p in picks:
        cp = p["site"]
        spots.append((cp.x, cp.y))
        made["church_at"].append([round(cp.x), round(cp.y)])
        if ck.take_compound(site, cp, "civic:church"):
            church(site, cp, made)
    return mosque_spots


def build_osm(site, lay):
    """The OSM mosques. Returns (stats, mosque positions)."""
    made = {"osm": 0, "osm_missing": 0, "osm_claimed": 0, "courtyards": 0, "courtyards_district": 0, "osm_at": []}
    spots = build_osm_mosques(site, lay, made)
    return made, spots


def build_rest(site, lay, osm_spots, spots):
    """Large mosques, churches and neighbourhood mosques. spots: the centres
    of the compounds built so far (kept COMPOUND_GAP_M away)."""
    made = {"large": 0, "churches": 0, "neighbourhood": 0, "neighbourhood_missing": 0,
            "neighbourhood_moved": 0, "large_at": [], "church_at": [], "neighbourhood_at": [],
            "neighbourhood_moved_to": []}
    seeds = list(osm_spots) + [JAPANESE_GARDEN_MOSQUE]
    seeds += build_large_and_churches(site, lay, made, seeds, spots)
    build_neighbourhood(site, lay, seeds, made)
    return made
